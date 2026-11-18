local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local FirstPersonCameraController = require(script.Parent:WaitForChild("FirstPersonCameraController"))

local SprintController = {}

local HOLD_ACTION = "SprintHold"
local TOGGLE_ACTION = "SprintToggle"
local MOVE_EPSILON = 0.1
local BREATH_LIFETIME = 5

local isStarted = false
local connections: { RBXScriptConnection } = {}
local holding = false
local latched = false
local sprinting = false
local controlled: Humanoid? = nil
local stamina = Config.Movement.Stamina.Max
local exhausted = false
local regenAt = 0
local exertion = 0
local nextBreathAt = 0
local breathRng = Random.new()

local function playBreath(level: number)
	local settings = Config.Movement.Stamina
	local folder = SoundService:FindFirstChild(settings.BreathFolder)
	if not folder then
		return
	end
	local variants = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Sound") then
			table.insert(variants, child)
		end
	end
	if #variants == 0 then
		return
	end
	local template = variants[breathRng:NextInteger(1, #variants)]
	local sound = template:Clone()
	sound.Volume = template.Volume * settings.BreathVolumeScale * (0.45 + 0.55 * level)
	sound.PlaybackSpeed = template.PlaybackSpeed * breathRng:NextNumber(settings.BreathSpeedRange[1], settings.BreathSpeedRange[2])
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, BREATH_LIFETIME)
end

local function updateBreathing(now: number)
	local settings = Config.Movement.Stamina
	local level = math.clamp((exertion - settings.BreathThreshold) / math.max(1 - settings.BreathThreshold, 0.01), 0, 1)
	if level <= 0 then
		nextBreathAt = 0
		return
	end
	if nextBreathAt == 0 then
		nextBreathAt = now
	end
	if now < nextBreathAt then
		return
	end
	playBreath(level)
	local interval = settings.BreathInterval
	nextBreathAt = now + (interval[1] + (interval[2] - interval[1]) * level) * breathRng:NextNumber(0.85, 1.15)
end

local function updateStamina(dt: number, moving: boolean)
	local settings = Config.Movement.Stamina
	local now = os.clock()
	if sprinting and moving then
		stamina = math.max(stamina - settings.Drain * dt, 0)
		regenAt = now + settings.RegenDelay
		if stamina <= 0 then
			exhausted = true
			latched = false
		end
	elseif now >= regenAt then
		stamina = math.min(stamina + settings.Regen * dt, settings.Max)
	end
	if exhausted and stamina >= settings.RecoverAt then
		exhausted = false
	end
	local fraction = stamina / settings.Max
	local target = if exhausted then 1 else math.clamp((settings.ExertionStart - fraction) / math.max(settings.ExertionStart, 0.01), 0, 1)
	local rate = if target > exertion then settings.ExertionRise else settings.ExertionFall
	exertion += (target - exertion) * (1 - math.exp(-rate * dt))
	FirstPersonCameraController.setExertion(exertion)
	updateBreathing(now)
end

local function resetStamina()
	stamina = Config.Movement.Stamina.Max
	exhausted = false
	regenAt = 0
	exertion = 0
	nextBreathAt = 0
	FirstPersonCameraController.setExertion(0)
end

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
		resetStamina()
		humanoid.WalkSpeed = Config.Movement.WalkSpeed
	end
	local moving = humanoid.MoveDirection.Magnitude >= MOVE_EPSILON
	if latched and not moving then
		latched = false
	end
	local settings = Config.Movement
	sprinting = (holding or latched) and not exhausted and stamina > 0 and canSprint(character, humanoid)
	updateStamina(dt, moving)
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

function SprintController.getStamina(): (number, number, boolean)
	return stamina, Config.Movement.Stamina.Max, exhausted
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
	resetStamina()
	local humanoid = controlled
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = Config.Movement.WalkSpeed
	end
	controlled = nil
end

return SprintController
