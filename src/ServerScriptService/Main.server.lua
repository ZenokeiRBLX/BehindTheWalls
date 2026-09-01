local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

local matchStateRemote = remotesFolder:FindFirstChild("MatchState") or Instance.new("RemoteEvent")
matchStateRemote.Name = "MatchState"
matchStateRemote.Parent = remotesFolder

local roundState = {
	phase = "Lobby",
	remaining = Config.LobbyTimeSeconds,
}

local function broadcastMatchState()
	matchStateRemote:FireAllClients(roundState.phase, roundState.remaining)
end

local function setPhase(newPhase, newRemaining)
	roundState.phase = newPhase
	roundState.remaining = newRemaining
	broadcastMatchState()
end

local function startRoundLoop()
	setPhase("Lobby", Config.LobbyTimeSeconds)
	for _ = 1, Config.LobbyTimeSeconds do
		task.wait(1)
		if roundState.phase ~= "Lobby" then
			return
		end
		roundState.remaining -= 1
		broadcastMatchState()
		if roundState.remaining <= 0 then
			setPhase("Round", Config.RoundLengthSeconds)
			break
		end
	end

	while roundState.phase == "Round" do
		task.wait(1)
		roundState.remaining -= 1
		broadcastMatchState()
		if roundState.remaining <= 0 then
			setPhase("Intermission", Config.LobbyTimeSeconds)
		end
	end

	while roundState.phase == "Intermission" do
		task.wait(1)
		roundState.remaining -= 1
		broadcastMatchState()
		if roundState.remaining <= 0 then
			startRoundLoop()
			return
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	print(string.format("[%s] joined the server.", player.Name))
	matchStateRemote:FireClient(player, roundState.phase, roundState.remaining)
end)

Players.PlayerRemoving:Connect(function(player)
	print(string.format("[%s] left the server.", player.Name))
end)

print(string.format("[%s] server initialized.", Config.GameName))
startRoundLoop()
