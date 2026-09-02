local SystemRegistry = {}

local Systems = script.Parent
local DataSystem = require(Systems:WaitForChild("DataSystem"))

local SYSTEMS = {
	DataSystem,
}

function SystemRegistry.start()
	for _, system in SYSTEMS do
		if system.start then
			system.start()
		end
	end
end

return SystemRegistry
