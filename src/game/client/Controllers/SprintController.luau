local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local FirstPersonCameraController = require(script.Parent:WaitForChild("FirstPersonCameraController"))

local SprintController = {}

local HOLD_ACTION = "SprintHold"
local TOGGLE_ACTION = "SprintToggle"
local MOVE_EPSILON = 0.1

local isStarted = false
local connections: { RBXScriptConnection } = {}
local holding = false
local latched = false
local sprinting = false
local controlled: Humanoid? = nil

local function blocked(character: Model): boolean
	for _, name in Config.Movement.BlockAttributes do
		if character:GetAttribute(name) then
			return true
		end
	end
	local player = Players.LocalPlayer
	for _, name in Config.Camera.SuspendAttributes do
		if player:GetAttribute(name) then
			return true
		end
	end
	return false
end

local function movingForward(humanoid: Humanoid): boolean
	local move = humanoid.MoveDirection
	if move.Magnitude < MOVE_EPSILON then
		return false
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return true
	end
	local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	local flatMove = Vector3.new(move.X, 0, move.Z)
	if look.Magnitude < MOVE_EPSILON or flatMove.Magnitude < MOVE_EPSILON then
		return true
	end
	return look.Unit:Dot(flatMove.Unit) >= Config.Movement.ForwardDot
end

local function canSprint(character: Model, humanoid: Humanoid): boolean
	if not FirstPersonCameraController.isEnabled() or FirstPersonCameraController.isHudHidden() then
		return false
	end
	if humanoid.Health <= 0 or humanoid.Sit or blocked(character) then
		return false
	end
	return movingForward(humanoid)
end

local function step(dt: number)
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not humanoid then
		sprinting = false
		controlled = nil
		return
	end
	if controlled ~= humanoid then
		controlled = humanoid
		latched = false
		humanoid.WalkSpeed = Config.Movement.WalkSpeed
	end
	if latched and humanoid.MoveDirection.Magnitude < MOVE_EPSILON then
		latched = false
	end
	local settings = Config.Movement
	sprinting = (holding or latched) and canSprint(character, humanoid)
	local target = if sprinting then settings.SprintSpeed else settings.WalkSpeed
	local current = humanoid.WalkSpeed
	if current == target then
		return
	end
	local rate = if target > current then settings.SpeedUp else settings.SlowDown
	local change = rate * dt
	humanoid.WalkSpeed = if math.abs(target - current) <= change then target else current + math.sign(target - current) * change
end

local function onHold(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		holding = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		holding = false
	end
	return Enum.ContextActionResult.Pass
end

local function onToggle(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		latched = not latched
	end
	return Enum.ContextActionResult.Pass
end

function SprintController.isSprinting(): boolean
	return sprinting
end

function SprintController.start()
	if isStarted then
		return
	end
	isStarted = true
	local settings = Config.Movement
	local priority = Enum.ContextActionPriority.High.Value + 1
	ContextActionService:BindActionAtPriority(HOLD_ACTION, onHold, true, priority, table.unpack(settings.SprintKeys))
	ContextActionService:BindActionAtPriority(TOGGLE_ACTION, onToggle, false, priority, table.unpack(settings.ToggleKeys))
	ContextActionService:SetTitle(HOLD_ACTION, settings.TouchButtonTitle)
	table.insert(connections, RunService.Heartbeat:Connect(step))
end

function SprintController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	ContextActionService:UnbindAction(HOLD_ACTION)
	ContextActionService:UnbindAction(TOGGLE_ACTION)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	holding = false
	latched = false
	sprinting = false
	local humanoid = controlled
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = Config.Movement.WalkSpeed
	end
	controlled = nil
end

return SprintController
