local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

local ThirdPersonCameraController = {}

local CAMERA_BIND = "ThirdPersonCamera"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local MAX_DELTA_TIME = 0.1
local SPRING_STEP = 1 / 120
local THUMBSTICK_DEADZONE = 0.15
local FILTER_REFRESH_SECONDS = 0.5
local MIN_CAST_LENGTH = 0.001
local NOISE_SEED_PITCH = 17.3
local NOISE_SEED_YAW = 41.9
local NOISE_SEED_ROLL = 73.1
local TWO_PI = math.pi * 2

type Spring = {
	position: number,
	velocity: number,
}

local UserGameSettings = UserSettings():GetService("UserGameSettings")

local isStarted = false
local enabled = false
local connections: { RBXScriptConnection } = {}
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true
local filterRefreshAt = 0

local yaw = 0
local pitch = 0
local lookDelta = Vector2.zero
local stick = Vector2.zero
local touchInput: InputObject? = nil
local aiming = false
local aimBlend = 0
local shoulderSide = 1
local shoulderBlend = 1
local zoomTarget = Config.Camera.Distance
local distance = Config.Camera.Distance
local focus: Vector3? = nil
local fieldOfView = Config.Camera.FieldOfView
local elapsed = 0
local bobPhase = 0
local bobWeight = 0
local strafeRoll = 0
local turnRoll = 0
local airSpeed = 0
local impact: Spring = { position = 0, velocity = 0 }
local autoRotateOverridden = false

local function damp(current: number, target: number, speed: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

local function yawOf(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

local function getCharacterParts(): (Model?, Humanoid?, BasePart?)
	local character = Players.LocalPlayer.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid and humanoid.RootPart then humanoid.RootPart else character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, if root and root:IsA("BasePart") then root else nil
end

local function isSuspended(): boolean
	local player = Players.LocalPlayer
	for _, name in Config.Camera.SuspendAttributes do
		if player:GetAttribute(name) then
			return true
		end
	end
	return false
end

local function refreshFilter()
	local now = os.clock()
	if now < filterRefreshAt then
		return
	end
	filterRefreshAt = now + FILTER_REFRESH_SECONDS
	local excluded = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	castParams.FilterDescendantsInstances = excluded
end

local function castLength(origin: Vector3, direction: Vector3): number
	local length = direction.Magnitude
	if length < MIN_CAST_LENGTH then
		return length
	end
	local settings = Config.Camera
	local result = Workspace:Spherecast(origin, settings.CollisionRadius, direction, castParams)
	if result then
		return math.max(result.Distance - settings.CollisionPadding, 0)
	end
	return length
end

local function setAutoRotate(humanoid: Humanoid?, faceCamera: boolean)
	if not humanoid then
		return
	end
	if faceCamera ~= autoRotateOverridden then
		autoRotateOverridden = faceCamera
		humanoid.AutoRotate = not faceCamera
	end
end

local function restoreAutoRotate()
	local _, humanoid = getCharacterParts()
	if humanoid and autoRotateOverridden then
		humanoid.AutoRotate = true
	end
	autoRotateOverridden = false
end

local function stepSpring(spring: Spring, stiffness: number, damping: number, dt: number)
	local remaining = dt
	while remaining > 0 do
		local step = math.min(remaining, SPRING_STEP)
		local acceleration = -stiffness * spring.position - damping * spring.velocity
		spring.velocity += acceleration * step
		spring.position += spring.velocity * step
		remaining -= step
	end
end

local function readLook(dt: number)
	local settings = Config.Camera
	local sensitivity = UserGameSettings.MouseSensitivity
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		lookDelta += UserInputService:GetMouseDelta() * settings.MouseSensitivity * sensitivity
	end
	local magnitude = stick.Magnitude
	if magnitude > THUMBSTICK_DEADZONE then
		local scaled = stick.Unit * ((magnitude - THUMBSTICK_DEADZONE) / (1 - THUMBSTICK_DEADZONE))
		lookDelta += Vector2.new(scaled.X, -scaled.Y) * settings.GamepadSpeed * dt
	end
	local deltaYaw = -math.rad(lookDelta.X)
	yaw = (yaw + deltaYaw) % TWO_PI
	pitch = math.clamp(pitch - math.rad(lookDelta.Y), math.rad(settings.PitchMin), math.rad(settings.PitchMax))
	lookDelta = Vector2.zero
	local turnRate = deltaYaw / math.max(dt, MIN_CAST_LENGTH)
	local turnLimit = math.rad(settings.TurnRoll.MaxDegrees)
	local turnTarget = math.clamp(turnRate * math.rad(settings.TurnRoll.DegreesPerRadian), -turnLimit, turnLimit)
	turnRoll = damp(turnRoll, turnTarget, settings.TurnRoll.Smoothing, dt)
end

local function faceCharacter(character: Model, humanoid: Humanoid?, root: BasePart, dt: number)
	local settings = Config.Camera
	local ragdolled = character:GetAttribute(RAGDOLL_ATTRIBUTE) == true
	local alive = humanoid ~= nil and humanoid.Health > 0 and not humanoid.Sit
	local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0
	local faceCamera = alive and not ragdolled and (aiming or (settings.FaceCameraWhenMoving and moving))
	setAutoRotate(humanoid, faceCamera)
	if not faceCamera then
		return
	end
	local currentYaw = yawOf(root.CFrame.LookVector)
	local difference = (yaw - currentYaw + math.pi) % TWO_PI - math.pi
	local nextYaw = currentYaw + difference * (1 - math.exp(-settings.CharacterTurnSpeed * dt))
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, nextYaw, 0)
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local settings = Config.Camera
	if isSuspended() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		lookDelta = Vector2.zero
		restoreAutoRotate()
		return
	end
	dt = math.clamp(dt, 0, MAX_DELTA_TIME)
	elapsed += dt
	camera.CameraType = Enum.CameraType.Scriptable
	readLook(dt)

	local character, humanoid, root = getCharacterParts()
	if not character or not root then
		return
	end
	refreshFilter()

	local velocity = root.AssemblyLinearVelocity
	local planarSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local walkSpeed = if humanoid then math.max(humanoid.WalkSpeed, 1) else 16
	local grounded = humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
	local ragdolled = character:GetAttribute(RAGDOLL_ATTRIBUTE) == true
	if grounded then
		if airSpeed < 0 and not ragdolled then
			local impactSettings = settings.Impact
			local strength = math.clamp((-airSpeed - impactSettings.MinSpeed) / impactSettings.MaxSpeed, 0, 1)
			impact.velocity -= strength * impactSettings.Kick
		end
		airSpeed = 0
	else
		airSpeed = math.min(airSpeed, velocity.Y)
	end
	stepSpring(impact, settings.Impact.Stiffness, settings.Impact.Damping, dt)

	aimBlend = damp(aimBlend, if aiming then 1 else 0, settings.AimSmoothing, dt)
	shoulderBlend = damp(shoulderBlend, shoulderSide, settings.ShoulderSmoothing, dt)

	local target = root.Position + Vector3.yAxis * settings.FocusHeight
	if not focus then
		focus = target
	end
	local current = focus :: Vector3
	local followAlpha = 1 - math.exp(-settings.FollowSmoothing * dt)
	focus = Vector3.new(
		current.X + (target.X - current.X) * followAlpha,
		damp(current.Y, target.Y, settings.VerticalSmoothing, dt),
		current.Z + (target.Z - current.Z) * followAlpha
	)
	local base = (focus :: Vector3) + Vector3.yAxis * impact.position

	local yawRotation = CFrame.Angles(0, yaw, 0)
	local rotation = yawRotation * CFrame.Angles(pitch, 0, 0)
	local shoulderX = shoulderBlend * (settings.ShoulderOffset + (settings.AimShoulderOffset - settings.ShoulderOffset) * aimBlend)
	local shoulderVector = rotation:VectorToWorldSpace(Vector3.new(shoulderX, settings.ShoulderHeight, 0))
	local shoulderLength = castLength(base, shoulderVector)
	local shoulderPoint = if shoulderVector.Magnitude > MIN_CAST_LENGTH
		then base + shoulderVector.Unit * shoulderLength
		else base

	local goalDistance = zoomTarget + (settings.AimDistance - zoomTarget) * aimBlend
	local backward = -rotation.LookVector
	local allowed = castLength(shoulderPoint, backward * goalDistance)
	if allowed < distance then
		distance = allowed
	else
		distance = damp(distance, allowed, settings.ZoomSmoothing, dt)
	end
	local position = shoulderPoint + backward * distance

	local moveRatio = if grounded and not ragdolled then math.clamp(planarSpeed / walkSpeed, 0, 1.5) else 0
	bobWeight = damp(bobWeight, moveRatio, settings.Bob.Smoothing, dt)
	bobPhase = (bobPhase + planarSpeed * dt * math.pi / math.max(settings.Bob.StrideStuds, 0.1)) % (TWO_PI * 2)
	local bobOffset = Vector3.new(
		math.cos(bobPhase) * settings.Bob.Sway * bobWeight,
		math.sin(bobPhase * 2) * settings.Bob.Height * bobWeight,
		0
	)
	local bobRoll = math.cos(bobPhase) * math.rad(settings.Bob.RollDegrees) * bobWeight

	local localVelocity = yawRotation:VectorToObjectSpace(velocity)
	local strafeTarget = math.clamp(-localVelocity.X / walkSpeed, -1, 1) * math.rad(settings.StrafeTiltDegrees)
	strafeRoll = damp(strafeRoll, if ragdolled then 0 else strafeTarget, settings.TiltSmoothing, dt)

	local breathing = settings.Breathing
	local breathAmount = math.rad(breathing.Degrees) * (1 - breathing.MovingReduction * math.min(bobWeight, 1))
	local noiseTime = elapsed * breathing.NoiseSpeed
	local breathPitch = (math.noise(noiseTime, NOISE_SEED_PITCH) + math.sin(elapsed * breathing.Rate) * 0.5) * breathAmount
	local breathYaw = math.noise(noiseTime, NOISE_SEED_YAW) * breathAmount
	local breathRoll = math.noise(noiseTime, NOISE_SEED_ROLL) * breathAmount * 0.5
	local impactPitch = math.rad(impact.position * settings.Impact.PitchDegreesPerStud)

	camera.CFrame = CFrame.new(position)
		* rotation
		* CFrame.new(bobOffset)
		* CFrame.Angles(breathPitch + impactPitch, breathYaw, bobRoll + strafeRoll + turnRoll + breathRoll)
	camera.Focus = CFrame.new(base)

	local speedBoost = math.clamp((planarSpeed - walkSpeed) / walkSpeed, 0, 1) * settings.SpeedFovBoost
	local goalFov = settings.FieldOfView + (settings.AimFieldOfView - settings.FieldOfView) * aimBlend + speedBoost
	fieldOfView = damp(fieldOfView, goalFov, settings.FovSmoothing, dt)
	camera.FieldOfView = fieldOfView

	faceCharacter(character, humanoid, root, dt)
end

local function isAimInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2
end

local function onInputBegan(input: InputObject, processed: boolean)
	if not enabled or processed then
		return
	end
	if isAimInput(input) then
		aiming = true
	elseif table.find(Config.Camera.ShoulderSwapKeys, input.KeyCode) then
		shoulderSide = -shoulderSide
	elseif input.UserInputType == Enum.UserInputType.Touch and touchInput == nil then
		touchInput = input
	end
end

local function onInputEnded(input: InputObject)
	if isAimInput(input) then
		aiming = false
	end
	if input == touchInput then
		touchInput = nil
	end
end

local function onInputChanged(input: InputObject, processed: boolean)
	if not enabled then
		return
	end
	if input == touchInput then
		lookDelta += Vector2.new(input.Delta.X, input.Delta.Y) * Config.Camera.TouchSensitivity
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stick = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		local settings = Config.Camera
		zoomTarget = math.clamp(zoomTarget - input.Position.Z * settings.ZoomStep, settings.MinDistance, settings.MaxDistance)
	end
end

function ThirdPersonCameraController.snap()
	local settings = Config.Camera
	local _, _, root = getCharacterParts()
	if root then
		local look = root.CFrame.LookVector
		if Vector3.new(look.X, 0, look.Z).Magnitude > MIN_CAST_LENGTH then
			yaw = yawOf(look)
		end
	end
	pitch = math.rad(settings.DefaultPitch)
	focus = nil
	distance = zoomTarget
	lookDelta = Vector2.zero
	turnRoll = 0
	strafeRoll = 0
	bobWeight = 0
	airSpeed = 0
	impact.position = 0
	impact.velocity = 0
	filterRefreshAt = 0
end

function ThirdPersonCameraController.isEnabled(): boolean
	return enabled
end

function ThirdPersonCameraController.enable()
	if enabled then
		return
	end
	enabled = true
	ThirdPersonCameraController.snap()
	local camera = Workspace.CurrentCamera
	fieldOfView = if camera then camera.FieldOfView else Config.Camera.FieldOfView
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, update)
end

function ThirdPersonCameraController.disable()
	if not enabled then
		return
	end
	enabled = false
	aiming = false
	touchInput = nil
	stick = Vector2.zero
	pcall(function()
		RunService:UnbindFromRenderStep(CAMERA_BIND)
	end)
	restoreAutoRotate()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function ThirdPersonCameraController.start()
	if isStarted then
		return
	end
	isStarted = true
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(connections, Players.LocalPlayer.CharacterAdded:Connect(function(character)
		autoRotateOverridden = false
		character:WaitForChild("HumanoidRootPart", 10)
		if enabled and Players.LocalPlayer.Character == character then
			ThirdPersonCameraController.snap()
		end
	end))
end

function ThirdPersonCameraController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	ThirdPersonCameraController.disable()
end

return ThirdPersonCameraController
