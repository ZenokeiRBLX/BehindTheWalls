local SystemRegistry = {}

local Systems = script.Parent
local DataSystem = require(Systems:WaitForChild("DataSystem"))
local SpawnSystem = require(Systems:WaitForChild("SpawnSystem"))

local SYSTEMS = {
	DataSystem,
	SpawnSystem,
}

function SystemRegistry.start()
	for _, system in SYSTEMS do
		if system.start then
			system.start()
		end
	end
end

return SystemRegistry
