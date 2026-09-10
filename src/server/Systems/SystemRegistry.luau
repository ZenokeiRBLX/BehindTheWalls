local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SystemRegistry = {}

local Systems = script.Parent
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local DataSystem = require(Systems:WaitForChild("DataSystem"))

type System = { start: (() -> ())?, stop: (() -> ())? }

local function lobbySystems(): { System }
	return {
		DataSystem,
		require(Systems:WaitForChild("SpawnSystem")),
		require(Systems:WaitForChild("PartySystem")),
	}
end

local function gameSystems(): { System }
	local Game = Systems:WaitForChild("Game")
	return {
		DataSystem,
		require(Game:WaitForChild("MatchSystem")),
		require(Game:WaitForChild("GameSpawnSystem")),
	}
end

function SystemRegistry.start()
	local systems = if Config.isGamePlace() then gameSystems() else lobbySystems()
	for _, system in systems do
		if system.start then
			system.start()
		end
	end
end

return SystemRegistry
