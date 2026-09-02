local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))

local SpawnSystem = {}

local SPAWN_NAME = "Spawn"

local isStarted = false

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

function SpawnSystem.start()
	if isStarted then
		return
	end
	isStarted = true

	Blink.RequestSpawn.On(function(player)
		if player.Character and player.Character.Parent then
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
	end)
end

return SpawnSystem
