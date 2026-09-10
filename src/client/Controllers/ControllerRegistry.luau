local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ControllerRegistry = {}

local Controllers = script.Parent
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

type Controller = { start: (() -> ())?, stop: (() -> ())? }

local function lobbyControllers(): { Controller }
	return {
		require(Controllers:WaitForChild("PlayerDataController")),
		require(Controllers:WaitForChild("IntroController")),
		require(Controllers:WaitForChild("MusicController")),
		require(Controllers:WaitForChild("FootstepsController")),
		require(Controllers:WaitForChild("MenuButtonsController")),
		require(Controllers:WaitForChild("PartyController")),
		require(Controllers:WaitForChild("TeleportHudController")),
	}
end

local function gameControllers(): { Controller }
	local Game = Controllers:WaitForChild("Game")
	return {
		require(Controllers:WaitForChild("PlayerDataController")),
		require(Controllers:WaitForChild("FootstepsController")),
		require(Controllers:WaitForChild("TeleportHudController")),
		require(Game:WaitForChild("CutsceneController")),
	}
end

function ControllerRegistry.start()
	local controllers = if Config.isGamePlace() then gameControllers() else lobbyControllers()
	for _, controller in controllers do
		if controller.start then
			controller.start()
		end
	end
end

return ControllerRegistry
