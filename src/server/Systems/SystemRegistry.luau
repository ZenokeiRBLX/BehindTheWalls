local SystemRegistry = {}

local Systems = script.Parent
local DataSystem = require(Systems:WaitForChild("DataSystem"))
local MapSystem = require(Systems:WaitForChild("MapSystem"))
local RoundSystem = require(Systems:WaitForChild("RoundSystem"))

local SYSTEMS = {
	DataSystem,
	MapSystem,
	RoundSystem,
}

function SystemRegistry.start()
	for _, system in SYSTEMS do
		if system.start then
			system.start()
		end
	end
end

return SystemRegistry
