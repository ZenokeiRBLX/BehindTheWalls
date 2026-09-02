local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))

local RoundSystem = {}

local isStarted = false

local roundState = {
	phase = "Lobby",
	remaining = Config.LobbyTimeSeconds,
}

local playerRoles: { [Player]: string } = {}

local function broadcastMatchState()
	Blink.MatchState.FireAll({
		phase = roundState.phase,
		remaining = math.max(roundState.remaining, 0),
	})
end

local function setPhase(newPhase: string, newRemaining: number)
	roundState.phase = newPhase
	roundState.remaining = newRemaining
	broadcastMatchState()
end

local function getSpawnLocation(role: string): Vector3
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then
		return Config.DefaultSpawnPosition
	end

	local spawns = arena:FindFirstChild("SpawnLocations")
	if not spawns then
		return Config.DefaultSpawnPosition
	end

	local roleFolder = spawns:FindFirstChild(role)
	if not roleFolder then
		return Config.DefaultSpawnPosition
	end

	local spawnParts = roleFolder:GetChildren()
	if #spawnParts == 0 then
		return Config.DefaultSpawnPosition
	end

	local chosenSpawn = spawnParts[math.random(1, #spawnParts)]
	return chosenSpawn.Position
end

local function assignRoles()
	local players = Players:GetPlayers()
	local hunterCount = 1
	for _, player in players do
		local role = (hunterCount <= 1 and Config.TeamNames.Hunter) or Config.TeamNames.Runner
		playerRoles[player] = role
		player:SetAttribute("Role", role)
		hunterCount += 1
	end
end

local function respawnPlayer(player: Player)
	local role = playerRoles[player] or Config.TeamNames.Runner
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart.CFrame = CFrame.new(getSpawnLocation(role))
		return
	end

	player.CharacterAdded:Once(function(character)
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
		humanoidRootPart.CFrame = CFrame.new(getSpawnLocation(role))
	end)
end

local function startRoundLoop()
	assignRoles()
	for _, player in Players:GetPlayers() do
		respawnPlayer(player)
	end

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

function RoundSystem.start()
	if isStarted then
		return
	end
	isStarted = true

	Players.PlayerAdded:Connect(function(player)
		assignRoles()
		Blink.MatchState.Fire(player, {
			phase = roundState.phase,
			remaining = math.max(roundState.remaining, 0),
		})
		respawnPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerRoles[player] = nil
	end)

	task.spawn(startRoundLoop)
	print(string.format("[%s] server initialized.", Config.GameName))
end

return RoundSystem
