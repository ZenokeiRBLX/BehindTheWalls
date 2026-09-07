local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))

local SpawnSystem = {}

local SPAWN_NAME = "Spawn"

local isStarted = false
local connections: { RBXScriptConnection } = {}
local respawning: { [Player]: boolean } = {}

local function placeCharacterOnSpawn(character: Model)
	local spawnLocation = Workspace:FindFirstChild(SPAWN_NAME)
	if not spawnLocation or not spawnLocation:IsA("BasePart") then
		return
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight else 2
	local offsetY = (spawnLocation.Size.Y / 2) + hipHeight + (rootPart.Size.Y / 2) + 0.1
	character:PivotTo(CFrame.new(spawnLocation.Position + Vector3.new(0, offsetY, 0)))
end

local function loadCharacter(player: Player)
	if player.Parent ~= Players then
		return
	end
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn(("SpawnSystem failed to load character for %s: %s"):format(player.Name, tostring(err)))
		return
	end
	local character = player.Character
	if character then
		placeCharacterOnSpawn(character)
	end
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Once(function()
		if respawning[player] then
			return
		end
		respawning[player] = true
		task.delay(Players.RespawnTime, function()
			respawning[player] = nil
			if player.Parent ~= Players or player.Character ~= character then
				return
			end
			loadCharacter(player)
		end)
	end)
end

local function watchPlayer(player: Player)
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end))
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

function SpawnSystem.start()
	if isStarted then
		return
	end
	isStarted = true

	Blink.RequestSpawn.On(function(player)
		if player.Character and player.Character.Parent then
			return
		end
		loadCharacter(player)
	end)

	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		respawning[player] = nil
	end))
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

function SpawnSystem.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(respawning)
end

return SpawnSystem
