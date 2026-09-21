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
local EPSILON = 0.001
local NOISE_SEED_PITCH = 17.3
local NOISE_SEED_YAW = 41.9
local NOISE_SEED_ROLL = 73.1
local TWO_PI = math.pi * 2

type Spring = {
	position: number,
	velocity: number,
}

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
local mouseDelta = Vector2.zero
local touchDelta = Vector2.zero
local stick = Vector2.zero
local stickHoldTime = 0
local touchInput: InputObject? = nil
local eyeHeight: number? = nil
local eyeY: number? = nil
local ragdollView: CFrame? = nil
local fieldOfView = Config.Camera.FieldOfView
local elapsed = 0
local bobPhase = 0
local bobWeight = 0
local strafeRoll = 0
local turnRoll = 0
local airSpeed = 0
local impact: Spring = { position = 0, velocity = 0 }
local autoRotateOverridden = false
local crosshairGui: ScreenGui? = nil
local crosshairWanted = false
local hudHidden = false

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

local function isVisiblePart(part: BasePart): boolean
	if part:FindFirstAncestorOfClass("Accessory") then
		return false
	end
	return table.find(Config.Camera.VisibleParts, part.Name) ~= nil
end

local function trackPart(descendant: Instance)
	if not descendant:IsA("BasePart") or descendant.Name == "HumanoidRootPart" then
		return
	end
	if isVisiblePart(descendant) then
		table.insert(visibleParts, descendant)
	else
		table.insert(hiddenParts, descendant)
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

local function findCrosshair(): ScreenGui?
	local current = crosshairGui
	if current and current.Parent then
		return current
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local found = if playerGui then playerGui:FindFirstChild(Config.Camera.CrosshairGuiName) else nil
	crosshairGui = if found and found:IsA("ScreenGui") then found else nil
	return crosshairGui
end

local function applyCrosshair()
	local screen = findCrosshair()
	local shown = crosshairWanted and not hudHidden
	if screen and screen.Enabled ~= shown then
		screen.Enabled = shown
	end
end

local function setCrosshair(wanted: boolean)
	crosshairWanted = wanted
	applyCrosshair()
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

local function stickCurve(value: number, deadzone: number, curvature: number): number
	local magnitude = math.abs(value)
	if magnitude <= deadzone then
		return 0
	end
	local normalized = math.clamp((magnitude - deadzone) / (1 - deadzone), 0, 1)
	local shaped = if curvature > EPSILON
		then (math.exp(curvature * normalized) - 1) / (math.exp(curvature) - 1)
		else normalized
	return math.sign(value) * shaped
end

local function pixelLook(delta: Vector2, settings: { DegreesPerPixel: number, VerticalScale: number, Multiplier: number }): Vector2
	local degrees = settings.DegreesPerPixel * settings.Multiplier
	return Vector2.new(delta.X * degrees, delta.Y * degrees * settings.VerticalScale)
end

local function gamepadLook(dt: number): Vector2
	local settings = Config.Camera.Look.Gamepad
	local x = stickCurve(stick.X, settings.Deadzone, settings.Curve)
	local y = stickCurve(stick.Y, settings.Deadzone, settings.Curve)
	if x == 0 and y == 0 then
		stickHoldTime = 0
		return Vector2.zero
	end
	local acceleration = settings.Acceleration
	local pushed = math.max(math.abs(stick.X), math.abs(stick.Y)) >= acceleration.Threshold
	stickHoldTime = if pushed then stickHoldTime + dt else 0
	local ramp = math.clamp(stickHoldTime / math.max(acceleration.RampSeconds, EPSILON), 0, 1)
	local boost = 1 + acceleration.Bonus * ramp * ramp
	local degrees = settings.DegreesPerSecond * settings.Multiplier * boost * dt
	return Vector2.new(x * degrees, -y * degrees * settings.VerticalScale)
end

local function readLook(dt: number)
	local settings = Config.Camera
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		mouseDelta += UserInputService:GetMouseDelta()
	end
	local look = pixelLook(mouseDelta, settings.Look.Mouse) + pixelLook(touchDelta, settings.Look.Touch) + gamepadLook(dt)
	mouseDelta = Vector2.zero
	touchDelta = Vector2.zero
	local limit = settings.Look.MaxDegreesPerFrame
	look = Vector2.new(math.clamp(look.X, -limit, limit), math.clamp(look.Y, -limit, limit))

	local deltaYaw = -math.rad(look.X)
	yaw = (yaw + deltaYaw) % TWO_PI
	pitch = math.clamp(pitch - math.rad(look.Y), math.rad(settings.PitchMin), math.rad(settings.PitchMax))

	local turnRate = deltaYaw / math.max(dt, EPSILON)
	local turnLimit = math.rad(settings.TurnRoll.MaxDegrees)
	local turnTarget = math.clamp(turnRate * math.rad(settings.TurnRoll.DegreesPerRadian), -turnLimit, turnLimit)
	turnRoll = damp(turnRoll, turnTarget, settings.TurnRoll.Smoothing, dt)
end

local function eyePosition(character: Model, root: BasePart, dt: number): Vector3
	local settings = Config.Camera
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		eyeY = root.Position.Y
		return root.Position
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

local function ragdollCFrame(character: Model, root: BasePart, dt: number): CFrame
	local settings = Config.Camera
	local head = character:FindFirstChild("Head")
	local source = if head and head:IsA("BasePart") then head.CFrame else root.CFrame
	local target = source * CFrame.new(0, settings.EyeLift, -settings.EyeForward)
	local current = ragdollView
	if current then
		target = current:Lerp(target, 1 - math.exp(-settings.RagdollViewSmoothing * dt))
	end
	ragdollView = target
	return target
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
		mouseDelta = Vector2.zero
		touchDelta = Vector2.zero
		restoreAutoRotate()
		setBodyVisibility(false)
		setCrosshair(false)
		return
	end
	dt = math.clamp(dt, 0, MAX_DELTA_TIME)
	elapsed += dt
	camera.CameraType = Enum.CameraType.Scriptable
	readLook(dt)

	local character, humanoid, root = getCharacterParts()
	if not character or not root then
		setCrosshair(false)
		return
	end
	setBodyVisibility(true)

	local ragdolled = character:GetAttribute(RAGDOLL_ATTRIBUTE) == true
	setCrosshair(not ragdolled)
	if ragdolled then
		restoreAutoRotate()
		local view = ragdollCFrame(character, root, dt)
		camera.CFrame = view
		camera.Focus = view
		fieldOfView = damp(fieldOfView, settings.FieldOfView, settings.FovSmoothing, dt)
		camera.FieldOfView = fieldOfView
		airSpeed = 0
		bobWeight = 0
		return
	end
	ragdollView = nil

	local velocity = root.AssemblyLinearVelocity
	local planarSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local walkSpeed = if humanoid then math.max(humanoid.WalkSpeed, 1) else 16
	local grounded = humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
	local alive = humanoid ~= nil and humanoid.Health > 0

	if grounded then
		if airSpeed < 0 then
			local impactSettings = settings.Impact
			local strength = math.clamp((-airSpeed - impactSettings.MinSpeed) / impactSettings.MaxSpeed, 0, 1)
			impact.velocity -= strength * impactSettings.Kick
		end
		airSpeed = 0
	else
		airSpeed = math.min(airSpeed, velocity.Y)
	end
	stepSpring(impact, settings.Impact.Stiffness, settings.Impact.Damping, dt)

	local moveRatio = if grounded then math.clamp(planarSpeed / walkSpeed, 0, 1.5) else 0
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
	strafeRoll = damp(strafeRoll, strafeTarget, settings.TiltSmoothing, dt)

	local breathing = settings.Breathing
	local breathAmount = math.rad(breathing.Degrees) * (1 - breathing.MovingReduction * math.min(bobWeight, 1))
	local noiseTime = elapsed * breathing.NoiseSpeed
	local breathPitch = (math.noise(noiseTime, NOISE_SEED_PITCH) + math.sin(elapsed * breathing.Rate) * 0.5) * breathAmount
	local breathYaw = math.noise(noiseTime, NOISE_SEED_YAW) * breathAmount
	local breathRoll = math.noise(noiseTime, NOISE_SEED_ROLL) * breathAmount * 0.5
	local impactPitch = math.rad(impact.position * settings.Impact.PitchDegreesPerStud)

	local eye = eyePosition(character, root, dt)
	local rotation = yawRotation * CFrame.Angles(pitch, 0, 0)
	camera.CFrame = CFrame.new(eye)
		* rotation
		* CFrame.new(bobOffset)
		* CFrame.Angles(breathPitch + impactPitch + bobPitch, breathYaw, bobRoll + strafeRoll + turnRoll + breathRoll)
	camera.Focus = CFrame.new(eye)

	local speedBoost = math.clamp((planarSpeed - walkSpeed) / walkSpeed, 0, 1) * settings.SpeedFovBoost
	fieldOfView = damp(fieldOfView, settings.FieldOfView + speedBoost, settings.FovSmoothing, dt)
	camera.FieldOfView = fieldOfView

	local faceCamera = alive and not (humanoid :: Humanoid).Sit
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
		touchDelta += Vector2.new(input.Delta.X, input.Delta.Y)
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
	ragdollView = nil
	mouseDelta = Vector2.zero
	touchDelta = Vector2.zero
	stickHoldTime = 0
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

function FirstPersonCameraController.setHudHidden(hidden: boolean)
	hudHidden = hidden
	applyCrosshair()
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
	if UserInputService.MouseEnabled then
		UserInputService:GetMouseDelta()
	end
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, update)
end

function FirstPersonCameraController.disable()
	if not enabled then
		return
	end
	enabled = false
	touchInput = nil
	stick = Vector2.zero
	stickHoldTime = 0
	pcall(function()
		RunService:UnbindFromRenderStep(CAMERA_BIND)
	end)
	restoreAutoRotate()
	setBodyVisibility(false)
	setCrosshair(false)
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
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if child.Name == Config.Camera.CrosshairGuiName then
			task.defer(applyCrosshair)
		end
	end))
	applyCrosshair()
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
