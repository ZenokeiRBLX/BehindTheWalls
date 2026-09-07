local SystemRegistry = {}

local Systems = script.Parent
local DataSystem = require(Systems:WaitForChild("DataSystem"))
local MatchSystem = require(Systems:WaitForChild("MatchSystem"))
local GameSpawnSystem = require(Systems:WaitForChild("GameSpawnSystem"))

local SYSTEMS = {
	DataSystem,
	MatchSystem,
	GameSpawnSystem,
}

function SystemRegistry.start()
	for _, system in SYSTEMS do
		if system.start then
			system.start()
		end
	end
end

return SystemRegistry
