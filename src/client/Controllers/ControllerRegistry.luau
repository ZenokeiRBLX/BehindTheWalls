local ControllerRegistry = {}

local Controllers = script.Parent
local PlayerDataController = require(Controllers:WaitForChild("PlayerDataController"))
local IntroController = require(Controllers:WaitForChild("IntroController"))

local CONTROLLERS = {
	PlayerDataController,
	IntroController,
}

function ControllerRegistry.start()
	for _, controller in CONTROLLERS do
		if controller.start then
			controller.start()
		end
	end
end

return ControllerRegistry
