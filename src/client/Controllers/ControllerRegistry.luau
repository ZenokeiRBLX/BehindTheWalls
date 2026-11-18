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
		require(Game:WaitForChild("FirstPersonCameraController")),
		require(Game:WaitForChild("SprintController")),
		require(Game:WaitForChild("CutsceneController")),
		require(Game:WaitForChild("FlashlightController")),
		require(Game:WaitForChild("HudController")),
		require(Game:WaitForChild("ObjectiveController")),
		require(Game:WaitForChild("MapController")),
		require(Game:WaitForChild("LevelCardController")),
		require(Game:WaitForChild("IntroHoleController")),
		require(Game:WaitForChild("SignalMazeController")),
		require(Game:WaitForChild("MonsterController")),
	}
end

local function mapCreationControllers(): { Controller }
	local Game = Controllers:WaitForChild("Game")
	return {
		require(Game:WaitForChild("SignalMazeController")),
	}
end

function ControllerRegistry.start()
	local controllers = if Config.isGamePlace()
		then gameControllers()
		elseif Config.isMapCreationPlace() then mapCreationControllers()
		else lobbyControllers()
	for _, controller in controllers do
		if controller.start then
			controller.start()
		end
	end
end

return ControllerRegistry
