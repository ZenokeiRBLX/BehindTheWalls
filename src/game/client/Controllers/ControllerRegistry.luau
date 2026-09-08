local ControllerRegistry = {}

local Controllers = script.Parent
local PlayerDataController = require(Controllers:WaitForChild("PlayerDataController"))
local FootstepsController = require(Controllers:WaitForChild("FootstepsController"))
local TeleportHudController = require(Controllers:WaitForChild("TeleportHudController"))
local CutsceneController = require(Controllers:WaitForChild("CutsceneController"))

local CONTROLLERS = {
	PlayerDataController,
	FootstepsController,
	TeleportHudController,
	CutsceneController,
}

function ControllerRegistry.start()
	for _, controller in CONTROLLERS do
		if controller.start then
			controller.start()
		end
	end
end

return ControllerRegistry
