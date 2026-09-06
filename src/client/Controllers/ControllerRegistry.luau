local ControllerRegistry = {}

local Controllers = script.Parent
local PlayerDataController = require(Controllers:WaitForChild("PlayerDataController"))
local IntroController = require(Controllers:WaitForChild("IntroController"))
local MusicController = require(Controllers:WaitForChild("MusicController"))
local FootstepsController = require(Controllers:WaitForChild("FootstepsController"))
local MenuButtonsController = require(Controllers:WaitForChild("MenuButtonsController"))
local PartyController = require(Controllers:WaitForChild("PartyController"))

local CONTROLLERS = {
	PlayerDataController,
	IntroController,
	MusicController,
	FootstepsController,
	MenuButtonsController,
	PartyController,
}

function ControllerRegistry.start()
	for _, controller in CONTROLLERS do
		if controller.start then
			controller.start()
		end
	end
end

return ControllerRegistry
