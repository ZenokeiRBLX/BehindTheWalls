local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))

local CutsceneController = {}

local CAMERA_PART_NAME = "Cutscene_Camera"
local CAMERA_PART_TIMEOUT = 30
local CAMERA_PART_POLL = 0.25
local CAMERA_BIND = "CutsceneCamera"
local FOV_ATTRIBUTE = "FieldOfView"
local GUI_NAME = "Cutscene"
local SKIP_BUTTON_NAME = "Cutscene_Skip"
local ARRIVAL_COMPLETE_ATTRIBUTE = "ArrivalComplete"
local ARRIVAL_WAIT_MARGIN = 15

local isStarted = false
local connections: { RBXScriptConnection } = {}
local cameraBound = false
local released = false
local savedFov: number?
local gui: ScreenGui?

local function findCameraPart(): BasePart?
	local deadline = os.clock() + CAMERA_PART_TIMEOUT
	while os.clock() < deadline do
		local part = Workspace:FindFirstChild(CAMERA_PART_NAME, true)
		if part and part:IsA("BasePart") then
			return part
		end
		task.wait(CAMERA_PART_POLL)
	end
	warn("CutsceneController: Workspace." .. CAMERA_PART_NAME .. " not found")
	return nil
end

local function bindCamera(part: BasePart)
	if cameraBound or released then
		return
	end
	cameraBound = true
	local camera = Workspace.CurrentCamera
	savedFov = if camera then camera.FieldOfView else nil
	local fov = part:GetAttribute(FOV_ATTRIBUTE)
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		local current = Workspace.CurrentCamera
		if not current then
			return
		end
		current.CameraType = Enum.CameraType.Scriptable
		current.CFrame = part.CFrame
		if type(fov) == "number" then
			current.FieldOfView = fov
		end
	end)
end

local function unbindCamera()
	if not cameraBound then
		return
	end
	cameraBound = false
	pcall(function()
		RunService:UnbindFromRenderStep(CAMERA_BIND)
	end)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	if savedFov then
		camera.FieldOfView = savedFov
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function resolveGui(playerGui: PlayerGui): ScreenGui?
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	local template = StarterGui:FindFirstChild(GUI_NAME)
	if template and template:IsA("ScreenGui") then
		local clone = template:Clone()
		clone.Parent = playerGui
		return clone
	end
	return nil
end

local function showGui(playerGui: PlayerGui)
	local screen = resolveGui(playerGui)
	gui = screen
	if not screen then
		return
	end
	screen.ResetOnSpawn = false
	screen.Enabled = true
	local skip = screen:FindFirstChild(SKIP_BUTTON_NAME, true)
	if skip and skip:IsA("GuiButton") then
		table.insert(connections, skip.Activated:Connect(function()
			CutsceneController.release()
		end))
	end
end

local function waitForArrival(player: Player)
	if player:GetAttribute(ARRIVAL_COMPLETE_ATTRIBUTE) then
		return
	end
	local deadline = os.clock() + Config.Party.ArrivalTimeoutSeconds + ARRIVAL_WAIT_MARGIN
	while not player:GetAttribute(ARRIVAL_COMPLETE_ATTRIBUTE) and os.clock() < deadline do
		task.wait(0.1)
	end
end

function CutsceneController.isActive(): boolean
	return isStarted and not released
end

function CutsceneController.release()
	if released then
		return
	end
	released = true
	if gui then
		gui.Enabled = false
	end
	unbindCamera()
end

function CutsceneController.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

		table.insert(connections, playerGui.ChildAdded:Connect(function(child)
			if child.Name ~= GUI_NAME or not child:IsA("ScreenGui") then
				return
			end
			if released or (gui ~= nil and child ~= gui) then
				task.defer(function()
					child.Enabled = false
				end)
			end
		end))
		local early = playerGui:FindFirstChild(GUI_NAME)
		if early and early:IsA("ScreenGui") then
			early.Enabled = false
		end

		local part = findCameraPart()
		if part then
			bindCamera(part)
		end
		waitForArrival(player)
		if released then
			return
		end
		showGui(playerGui)
	end)
end

function CutsceneController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	CutsceneController.release()
end

return CutsceneController
