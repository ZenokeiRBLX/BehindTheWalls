local ControllerRegistry = {}

local Controllers = script.Parent
local PlayerDataController = require(Controllers:WaitForChild("PlayerDataController"))

local CONTROLLERS = {
	PlayerDataController,
}

function ControllerRegistry.start()
	for _, controller in CONTROLLERS do
		if controller.start then
			controller.start()
		end
	end
end

return ControllerRegistry
