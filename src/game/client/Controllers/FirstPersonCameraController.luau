local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

local FirstPersonCameraController = {}

local CAMERA_BIND = "FirstPersonCamera"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local MAX_DELTA_TIME = 0.1
local SPRING_STEP = 1 / 120
local THUMBSTICK_DEADZONE = 0.15
local EPSILON = 0.001
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
local characterConnections: { RBXScriptConnection } = {}
local hiddenParts: { BasePart } = {}
local visibleParts: { BasePart } = {}
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true

local yaw = 0
local pitch = 0
local lookDelta = Vector2.zero
local stick = Vector2.zero
local touchInput: InputObject? = nil
local eyeHeight: number? = nil
local eyeY: number? = nil
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

local function isHeadPart(part: BasePart): boolean
	if part.Name == "Head" then
		return true
	end
	return part:FindFirstAncestorOfClass("Accessory") ~= nil
end

local function trackPart(descendant: Instance)
	if not descendant:IsA("BasePart") or descendant.Name == "HumanoidRootPart" then
		return
	end
	if isHeadPart(descendant) or not Config.Camera.ShowBody then
		table.insert(hiddenParts, descendant)
	else
		table.insert(visibleParts, descendant)
	end
end

local function watchCharacter(character: Model?)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	table.clear(hiddenParts)
	table.clear(visibleParts)
	castParams.FilterDescendantsInstances = if character then { character } else {}
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		trackPart(descendant)
	end
	table.insert(characterConnections, character.DescendantAdded:Connect(function(descendant)
		task.defer(trackPart, descendant)
	end))
	table.insert(characterConnections, character.DescendantRemoving:Connect(function(descendant)
		if not descendant:IsA("BasePart") then
			return
		end
		local hiddenIndex = table.find(hiddenParts, descendant)
		if hiddenIndex then
			table.remove(hiddenParts, hiddenIndex)
		end
		local visibleIndex = table.find(visibleParts, descendant)
		if visibleIndex then
			table.remove(visibleParts, visibleIndex)
		end
	end))
end

local function setBodyVisibility(hidden: boolean)
	for _, part in hiddenParts do
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end
	for _, part in visibleParts do
		part.LocalTransparencyModifier = 0
	end
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
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		lookDelta += UserInputService:GetMouseDelta() * settings.MouseSensitivity * UserGameSettings.MouseSensitivity
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
	local turnRate = deltaYaw / math.max(dt, EPSILON)
	local turnLimit = math.rad(settings.TurnRoll.MaxDegrees)
	local turnTarget = math.clamp(turnRate * math.rad(settings.TurnRoll.DegreesPerRadian), -turnLimit, turnLimit)
	turnRoll = damp(turnRoll, turnTarget, settings.TurnRoll.Smoothing, dt)
end

local function eyePosition(character: Model, root: BasePart, ragdolled: boolean, dt: number): Vector3
	local settings = Config.Camera
	local head = character:FindFirstChild("Head")
	if ragdolled or not head or not head:IsA("BasePart") then
		local fallback = if head and head:IsA("BasePart") then head.Position else root.Position
		eyeY = fallback.Y
		return fallback
	end
	local measured = root.CFrame:PointToObjectSpace(head.Position).Y + settings.EyeLift
	eyeHeight = if eyeHeight then damp(eyeHeight, measured, settings.EyeHeightSmoothing, dt) else measured
	local flatForward = CFrame.Angles(0, yaw, 0).LookVector
	local target = root.Position + Vector3.yAxis * (eyeHeight :: number)
	eyeY = if eyeY then damp(eyeY, target.Y, settings.VerticalSmoothing, dt) else target.Y
	local anchor = Vector3.new(target.X, eyeY :: number, target.Z)
	local offset = flatForward * settings.EyeForward
	local hit = Workspace:Raycast(anchor, offset + flatForward * settings.WallPadding, castParams)
	if hit then
		offset = flatForward * math.max(hit.Distance - settings.WallPadding, 0)
	end
	return anchor + offset
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
		setBodyVisibility(false)
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

	local velocity = root.AssemblyLinearVelocity
	local planarSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local walkSpeed = if humanoid then math.max(humanoid.WalkSpeed, 1) else 16
	local grounded = humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
	local ragdolled = character:GetAttribute(RAGDOLL_ATTRIBUTE) == true
	local alive = humanoid ~= nil and humanoid.Health > 0

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

	local moveRatio = if grounded and not ragdolled then math.clamp(planarSpeed / walkSpeed, 0, 1.5) else 0
	bobWeight = damp(bobWeight, moveRatio, settings.Bob.Smoothing, dt)
	bobPhase = (bobPhase + planarSpeed * dt * math.pi / math.max(settings.Bob.StrideStuds, 0.1)) % (TWO_PI * 2)
	local bobOffset = Vector3.new(
		math.cos(bobPhase) * settings.Bob.Sway * bobWeight,
		(math.sin(bobPhase * 2) * settings.Bob.Height * bobWeight) + impact.position,
		0
	)
	local bobPitch = math.sin(bobPhase * 2) * math.rad(settings.Bob.PitchDegrees) * bobWeight
	local bobRoll = math.cos(bobPhase) * math.rad(settings.Bob.RollDegrees) * bobWeight

	local yawRotation = CFrame.Angles(0, yaw, 0)
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

	local eye = eyePosition(character, root, ragdolled, dt)
	local rotation = yawRotation * CFrame.Angles(pitch, 0, 0)
	camera.CFrame = CFrame.new(eye)
		* rotation
		* CFrame.new(bobOffset)
		* CFrame.Angles(breathPitch + impactPitch + bobPitch, breathYaw, bobRoll + strafeRoll + turnRoll + breathRoll)
	camera.Focus = CFrame.new(eye)

	local speedBoost = math.clamp((planarSpeed - walkSpeed) / walkSpeed, 0, 1) * settings.SpeedFovBoost
	fieldOfView = damp(fieldOfView, settings.FieldOfView + speedBoost, settings.FovSmoothing, dt)
	camera.FieldOfView = fieldOfView

	setBodyVisibility(not ragdolled)

	local faceCamera = alive and not ragdolled and not (humanoid :: Humanoid).Sit
	setAutoRotate(humanoid, faceCamera)
	if faceCamera then
		root.CFrame = CFrame.new(root.Position) * yawRotation
	end
end

local function onInputBegan(input: InputObject, processed: boolean)
	if not enabled or processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch and touchInput == nil then
		touchInput = input
	end
end

local function onInputEnded(input: InputObject)
	if input == touchInput then
		touchInput = nil
	end
end

local function onInputChanged(input: InputObject)
	if not enabled then
		return
	end
	if input == touchInput then
		lookDelta += Vector2.new(input.Delta.X, input.Delta.Y) * Config.Camera.TouchSensitivity
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stick = Vector2.new(input.Position.X, input.Position.Y)
	end
end

function FirstPersonCameraController.snap()
	local _, _, root = getCharacterParts()
	if root then
		local look = root.CFrame.LookVector
		if Vector3.new(look.X, 0, look.Z).Magnitude > EPSILON then
			yaw = yawOf(look)
		end
	end
	pitch = math.rad(Config.Camera.DefaultPitch)
	eyeHeight = nil
	eyeY = nil
	lookDelta = Vector2.zero
	turnRoll = 0
	strafeRoll = 0
	bobWeight = 0
	airSpeed = 0
	impact.position = 0
	impact.velocity = 0
end

function FirstPersonCameraController.isEnabled(): boolean
	return enabled
end

function FirstPersonCameraController.enable()
	if enabled then
		return
	end
	enabled = true
	watchCharacter(Players.LocalPlayer.Character)
	FirstPersonCameraController.snap()
	local camera = Workspace.CurrentCamera
	fieldOfView = if camera then camera.FieldOfView else Config.Camera.FieldOfView
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, update)
end

function FirstPersonCameraController.disable()
	if not enabled then
		return
	end
	enabled = false
	touchInput = nil
	stick = Vector2.zero
	pcall(function()
		RunService:UnbindFromRenderStep(CAMERA_BIND)
	end)
	restoreAutoRotate()
	setBodyVisibility(false)
	watchCharacter(nil)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function FirstPersonCameraController.start()
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
			watchCharacter(character)
			FirstPersonCameraController.snap()
		end
	end))
end

function FirstPersonCameraController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	FirstPersonCameraController.disable()
end

return FirstPersonCameraController
