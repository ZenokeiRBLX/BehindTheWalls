local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local FirstPersonCameraController = require(script.Parent:WaitForChild("FirstPersonCameraController"))

local IntroHoleController = {}

local CENTER_ATTRIBUTE = "IntroHoleCenter"
local RADIUS_ATTRIBUTE = "IntroHoleRadius"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local DEFAULT_GROUP = "Default"
local CAMERA_BIND = "IntroHoleCamera"
local FADE_GUI_NAME = "IntroHoleFade"
local FADE_DISPLAY_ORDER = 1000
local SHAFT_NAME = "IntroHoleShaft"
local BLUR_NAME = "IntroHoleWakeBlur"
local LIFT_NAME = "IntroHoleLift"
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local GLOW_LOOKUP_SECONDS = 1
local MAX_LIGHT_RANGE = 60
local SOUND_ROLLOFF_MIN = 10
local SOUND_ROLLOFF_MAX = 250
local SOUND_LIFETIME = 8
local WIND_STOP_SECONDS = 0.3
local FLOOR_SLAB = 3
local ABORT_MARGIN = 3
local DEFAULT_EYE_OFFSET = 1.5
local GOLDEN_ANGLE = 2.39996
local EPSILON = 0.001
local TWO_PI = math.pi * 2
local NOISE_PITCH = 11.3
local NOISE_YAW = 23.7
local NOISE_ROLL = 37.9
local NOISE_GLOW = 51.1
local RNG = Random.new()
local LOCKED_STATES = {
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.Landed,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.GettingUp,
}

type GlowBase = {
	brightness: number,
	range: number,
}

type Fall = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	center: Vector3,
	startTime: number,
	startPosition: Vector3,
	startPitch: number,
	startFov: number,
	yaw: number,
	eyeOffset: number,
	confirmed: boolean,
	arrived: boolean,
	cleaned: boolean,
	floorHidden: boolean,
	groups: { [BasePart]: string },
	bodyParts: { BasePart },
	hiddenParts: { [BasePart]: number },
	hiddenDecals: { [Decal]: number },
	connections: { RBXScriptConnection },
	bodyConnection: RBXScriptConnection?,
	shaft: Folder?,
	dust: BasePart?,
	lift: VectorForce?,
	liftAttachment: Attachment?,
	fadeGui: ScreenGui?,
	fadeFrame: Frame?,
	wind: Sound?,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local watched: { [Model]: RBXScriptConnection } = {}
local active: Fall? = nil
local retriggerAt = 0
local controls: any = nil
local glowLights: { PointLight } = {}
local glowBase: { [PointLight]: GlowBase } = setmetatable({}, { __mode = "k" }) :: any
local glowLookupAt = 0
local flareAt = -math.huge
local warnedSounds: { [string]: boolean } = {}

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

local function smoothstep(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

local function easeOut(x: number): number
	local t = math.clamp(x, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

local function findHoleModel(): Instance?
	local name = Config.IntroHole.ModelName
	return Workspace:FindFirstChild(name) or Workspace:FindFirstChild(name, true)
end

local function findSound(name: string): Sound?
	if name == "" then
		return nil
	end
	local sound = SoundService:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		return sound
	end
	if not warnedSounds[name] then
		warnedSounds[name] = true
		warn("IntroHoleController: SoundService." .. name .. " not found")
	end
	return nil
end

local function playClone(template: Sound, parent: Instance, volumeScale: number, speedRange: { number }?)
	local sound = template:Clone()
	sound.Looped = false
	sound.Volume = template.Volume * volumeScale
	if speedRange then
		sound.PlaybackSpeed = RNG:NextNumber(speedRange[1], speedRange[2])
	end
	if parent:IsA("BasePart") and sound.RollOffMaxDistance >= 10000 then
		sound.RollOffMinDistance = SOUND_ROLLOFF_MIN
		sound.RollOffMaxDistance = SOUND_ROLLOFF_MAX
	end
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, SOUND_LIFETIME)
end

local function scream(root: BasePart)
	local audio = Config.IntroHole.Audio
	local names = audio.ScreamNames
	if #names == 0 then
		return
	end
	local template = findSound(names[RNG:NextInteger(1, #names)])
	if template then
		playClone(template, root, audio.ScreamVolumeScale, audio.ScreamSpeedRange)
	end
end

local function fadeOutAmbience()
	local audio = Config.IntroHole.Audio
	for _, name in audio.FadeOutNames do
		local sound = SoundService:FindFirstChild(name)
		if not sound or not sound:IsA("Sound") or not sound.IsPlaying then
			continue
		end
		local volume = sound.Volume
		local tween = TweenService:Create(sound, TweenInfo.new(math.max(audio.FadeOutSeconds, 0.05)), { Volume = 0 })
		tween.Completed:Once(function()
			sound:Stop()
			sound.Volume = volume
		end)
		tween:Play()
	end
end

local function startWind(fall: Fall)
	local audio = Config.IntroHole.Audio
	local template = if audio.WindName ~= "" then SoundService:FindFirstChild(audio.WindName) else nil
	if not template or not template:IsA("Sound") then
		return
	end
	local sound = template:Clone()
	local volume = template.Volume * audio.WindVolumeScale
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(math.max(audio.WindFadeSeconds, 0.05)), { Volume = volume }):Play()
	fall.wind = sound
end

local function stopWind(fall: Fall)
	local sound = fall.wind
	fall.wind = nil
	if not sound then
		return
	end
	local tween = TweenService:Create(sound, TweenInfo.new(WIND_STOP_SECONDS), { Volume = 0 })
	tween.Completed:Once(function()
		sound:Destroy()
	end)
	tween:Play()
end

local function playFallAudio(fall: Fall)
	local audio = Config.IntroHole.Audio
	scream(fall.root)
	local boom = findSound(audio.BoomName)
	if boom then
		playClone(boom, SoundService, audio.BoomVolumeScale, nil)
	end
	startWind(fall)
	fadeOutAmbience()
end

local function flareAmount(now: number): number
	local settings = Config.IntroHole.Glow
	local since = now - flareAt
	if since < 0 or since >= settings.FlareSeconds then
		return 0
	end
	local rise = math.max(settings.FlareRiseSeconds, EPSILON)
	if since < rise then
		return smoothstep(since / rise)
	end
	local remaining = 1 - (since - rise) / math.max(settings.FlareSeconds - rise, EPSILON)
	return remaining * remaining
end

local function collectGlow(now: number)
	if now < glowLookupAt then
		return
	end
	glowLookupAt = now + GLOW_LOOKUP_SECONDS
	table.clear(glowLights)
	local model = findHoleModel()
	if not model then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("PointLight") then
			table.insert(glowLights, descendant)
			if not glowBase[descendant] then
				glowBase[descendant] = { brightness = descendant.Brightness, range = descendant.Range }
			end
		end
	end
end

local function shaftLightScale(): number
	local fall = active
	local camera = Workspace.CurrentCamera
	if not fall or not fall.floorHidden or fall.arrived or not camera then
		return 1
	end
	local settings = Config.IntroHole.Fall
	local depth = fall.center.Y - camera.CFrame.Position.Y
	return lerp(settings.HoleLightScale, 1, smoothstep(depth / math.max(settings.HoleLightRestoreDepth, EPSILON)))
end

local function updateGlow(now: number)
	local valid = #glowLights > 0
	for _, light in glowLights do
		if not light.Parent then
			valid = false
			break
		end
	end
	if not valid then
		collectGlow(now)
	end
	if #glowLights == 0 then
		return
	end
	local settings = Config.IntroHole.Glow
	local wave = math.sin(now * settings.PulseSpeed * TWO_PI) * 0.6 + math.noise(now * settings.FlickerSpeed, NOISE_GLOW) * 0.8
	local flare = flareAmount(now)
	local brightnessScale = (1 + settings.PulseAmount * wave)
		* (1 + (settings.FlareBrightnessScale - 1) * flare)
		* shaftLightScale()
	local rangeScale = 1 + (settings.FlareRangeScale - 1) * flare
	for _, light in glowLights do
		local base = glowBase[light]
		if base then
			light.Brightness = base.brightness * brightnessScale
			light.Range = math.min(base.range * rangeScale, MAX_LIGHT_RANGE)
		end
	end
end

local function restoreGlow()
	for _, light in glowLights do
		local base = glowBase[light]
		if base and light.Parent then
			light.Brightness = base.brightness
			light.Range = base.range
		end
	end
	table.clear(glowLights)
end

local function flare()
	flareAt = os.clock()
end

local function getControls(): any
	if controls ~= nil then
		return controls
	end
	local playerScripts = Players.LocalPlayer:FindFirstChildOfClass("PlayerScripts")
	local module = if playerScripts then playerScripts:FindFirstChild("PlayerModule") else nil
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(function()
		return (require(module :: any) :: any):GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

local function setControls(enabled: boolean)
	local current = getControls()
	if not current then
		return
	end
	pcall(function()
		if enabled then
			current:Enable()
		else
			current:Disable()
		end
	end)
end

local function newLocalPart(name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	return part
end

local function buildShaft(center: Vector3): Folder
	local settings = Config.IntroHole.Shaft
	local folder = Instance.new("Folder")
	folder.Name = SHAFT_NAME
	local segments = math.max(math.floor(settings.Segments), 6)
	local thickness = settings.WallThickness
	local width = 2 * (settings.Radius + thickness) * math.tan(math.pi / segments) + 0.05
	local axis = Vector3.new(center.X, center.Y - settings.Depth / 2, center.Z)
	for index = 0, segments - 1 do
		local angle = index / segments * TWO_PI
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = axis + direction * (settings.Radius + thickness / 2)
		local wall = newLocalPart("Wall", Vector3.new(width, settings.Depth, thickness), CFrame.lookAt(position, axis))
		wall.Material = settings.Material
		wall.Color = settings.Color
		wall.Parent = folder
	end
	local spacing = math.max(settings.LightSpacing, 4)
	for index = 1, math.floor(settings.Depth / spacing) do
		local angle = index * GOLDEN_ANGLE
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = Vector3.new(center.X, center.Y - index * spacing, center.Z) + direction * (settings.Radius - 0.6)
		local holder = newLocalPart("Glow", Vector3.one * 0.2, CFrame.new(position))
		holder.Transparency = 1
		local light = Instance.new("PointLight")
		light.Color = settings.LightColor
		light.Brightness = settings.LightBrightness
		light.Range = settings.LightRange
		light.Shadows = false
		light.Parent = holder
		holder.Parent = folder
	end
	folder.Parent = Workspace.CurrentCamera
	return folder
end

local function buildDust(folder: Folder): BasePart
	local settings = Config.IntroHole.Shaft
	local dust = settings.Dust
	local span = settings.Radius * 1.6
	local part = newLocalPart("Dust", Vector3.new(span, 1, span), CFrame.new())
	part.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = DUST_TEXTURE
	emitter.Rate = dust.Rate
	emitter.Lifetime = NumberRange.new(dust.Lifetime)
	emitter.Speed = NumberRange.new(0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new(dust.Size)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, dust.Transparency),
		NumberSequenceKeypoint.new(0.8, dust.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(dust.Color)
	emitter.LightInfluence = dust.LightInfluence
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.LockedToPart = false
	emitter.Parent = part
	part.Parent = folder
	return part
end

local function createFade(fall: Fall)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = FADE_GUI_NAME
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = FADE_DISPLAY_ORDER
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = screen
	screen.Parent = playerGui
	fall.fadeGui = screen
	fall.fadeFrame = frame
end

local function setFade(fall: Fall, alpha: number)
	local frame = fall.fadeFrame
	if frame then
		frame.BackgroundTransparency = 1 - math.clamp(alpha, 0, 1)
	end
end

local function wakeBlur()
	local camera = Workspace.CurrentCamera
	local settings = Config.IntroHole.Wake
	if not camera or settings.Blur <= 0 then
		return
	end
	local blur = Instance.new("BlurEffect")
	blur.Name = BLUR_NAME
	blur.Size = settings.Blur
	blur.Parent = camera
	local info = TweenInfo.new(math.max(settings.BlurSeconds, 0.05), Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local tween = TweenService:Create(blur, info, { Size = 0 })
	tween.Completed:Once(function()
		blur:Destroy()
	end)
	tween:Play()
	Debris:AddItem(blur, settings.BlurSeconds + 1)
end

local function trackBodyPart(fall: Fall, instance: Instance, groupReady: boolean)
	if not instance:IsA("BasePart") then
		return
	end
	if not table.find(fall.bodyParts, instance) then
		table.insert(fall.bodyParts, instance)
	end
	if not groupReady or fall.groups[instance] ~= nil then
		return
	end
	local group = Config.IntroHole.CollisionGroup
	fall.groups[instance] = if instance.CollisionGroup == group then DEFAULT_GROUP else instance.CollisionGroup
	instance.CollisionGroup = group
end

local function lockBody(fall: Fall)
	local groupReady = PhysicsService:IsCollisionGroupRegistered(Config.IntroHole.CollisionGroup)
	for _, descendant in fall.character:GetDescendants() do
		trackBodyPart(fall, descendant, groupReady)
	end
	fall.bodyConnection = fall.character.DescendantAdded:Connect(function(descendant)
		trackBodyPart(fall, descendant, groupReady)
	end)
	for _, state in LOCKED_STATES do
		fall.humanoid:SetStateEnabled(state, false)
	end
	fall.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local attachment = Instance.new("Attachment")
	attachment.Name = LIFT_NAME
	attachment.Parent = fall.root
	local lift = Instance.new("VectorForce")
	lift.Name = LIFT_NAME
	lift.Attachment0 = attachment
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.new(0, fall.root.AssemblyMass * Workspace.Gravity, 0)
	lift.Parent = fall.root
	fall.lift = lift
	fall.liftAttachment = attachment
end

local function releaseBody(fall: Fall)
	if fall.bodyConnection then
		fall.bodyConnection:Disconnect()
		fall.bodyConnection = nil
	end
	if fall.lift then
		fall.lift:Destroy()
		fall.lift = nil
	end
	if fall.liftAttachment then
		fall.liftAttachment:Destroy()
		fall.liftAttachment = nil
	end
	for part, group in fall.groups do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	table.clear(fall.groups)
	if fall.humanoid.Parent then
		for _, state in LOCKED_STATES do
			fall.humanoid:SetStateEnabled(state, true)
		end
	end
end

local function hideOpening(fall: Fall)
	fall.floorHidden = true
	local settings = Config.IntroHole.Shaft
	local exclude: { Instance } = { fall.character, Workspace.Terrain }
	if fall.shaft then
		table.insert(exclude, fall.shaft)
	end
	local model = findHoleModel()
	if model then
		table.insert(exclude, model)
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Decal") and fall.hiddenDecals[descendant] == nil then
				fall.hiddenDecals[descendant] = descendant.LocalTransparencyModifier
				descendant.LocalTransparencyModifier = 1
			end
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local box = CFrame.new(fall.center + Vector3.yAxis * (settings.RevealHeight - FLOOR_SLAB / 2))
	local size = Vector3.new(settings.Radius * 2, FLOOR_SLAB, settings.Radius * 2)
	for _, part in Workspace:GetPartBoundsInBox(box, size, params) do
		if part.Transparency < 1 and fall.hiddenParts[part] == nil then
			fall.hiddenParts[part] = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 1
		end
	end
end

local function clearScene(fall: Fall)
	if fall.shaft then
		fall.shaft:Destroy()
		fall.shaft = nil
	end
	fall.dust = nil
	for part, value in fall.hiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
	table.clear(fall.hiddenParts)
	for decal, value in fall.hiddenDecals do
		if decal.Parent then
			decal.LocalTransparencyModifier = value
		end
	end
	table.clear(fall.hiddenDecals)
end

local function unbindCamera()
	pcall(function()
		RunService:UnbindFromRenderStep(CAMERA_BIND)
	end)
end

local function cleanup(fall: Fall)
	if fall.cleaned then
		return
	end
	fall.cleaned = true
	fall.arrived = true
	for _, connection in fall.connections do
		connection:Disconnect()
	end
	table.clear(fall.connections)
	unbindCamera()
	releaseBody(fall)
	clearScene(fall)
	stopWind(fall)
	if fall.fadeGui then
		fall.fadeGui:Destroy()
		fall.fadeGui = nil
		fall.fadeFrame = nil
	end
	setControls(true)
	if active == fall then
		active = nil
	end
	FirstPersonCameraController.enable()
	FirstPersonCameraController.setHudHidden(false)
end

local function wake(fall: Fall)
	local settings = Config.IntroHole.Wake
	task.wait(settings.HoldSeconds)
	if fall.cleaned then
		return
	end
	setControls(true)
	wakeBlur()
	local frame = fall.fadeFrame
	if frame then
		local info = TweenInfo.new(math.max(settings.FadeSeconds, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		task.wait(settings.FadeSeconds)
	end
	cleanup(fall)
end

local function rimCFrame(fall: Fall): CFrame
	local away = Vector3.new(fall.startPosition.X - fall.center.X, 0, fall.startPosition.Z - fall.center.Z)
	if away.Magnitude < EPSILON then
		local look = fall.root.CFrame.LookVector
		away = Vector3.new(-look.X, 0, -look.Z)
	end
	away = if away.Magnitude < EPSILON then Vector3.zAxis else away.Unit
	local radius = Workspace:GetAttribute(RADIUS_ATTRIBUTE)
	local edge = (if type(radius) == "number" then radius else Config.IntroHole.TriggerRadius) + ABORT_MARGIN
	local height = fall.humanoid.HipHeight + fall.root.Size.Y / 2
	local position = fall.center + away * edge + Vector3.yAxis * height
	return CFrame.lookAt(position, position + away)
end

local function arrive(fall: Fall, target: CFrame)
	if fall.arrived or fall.cleaned then
		return
	end
	fall.arrived = true
	setFade(fall, 1)
	unbindCamera()
	releaseBody(fall)
	fall.root.AssemblyLinearVelocity = Vector3.zero
	fall.root.AssemblyAngularVelocity = Vector3.zero
	fall.character:PivotTo(target)
	if fall.humanoid.Health > 0 then
		fall.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	clearScene(fall)
	stopWind(fall)
	retriggerAt = os.clock() + Config.IntroHole.RetriggerCooldown
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = Config.Camera.FieldOfView
	end
	FirstPersonCameraController.enable()
	FirstPersonCameraController.snap()
	task.spawn(wake, fall)
end

local function cameraAngles(fall: Fall, t: number): (number, number)
	local settings = Config.IntroHole.Fall
	local tipPitch = math.rad(settings.TipPitchDegrees)
	local roll = math.rad(settings.RollDegrees)
	if t < settings.TipSeconds then
		local alpha = easeOut(t / math.max(settings.TipSeconds, EPSILON))
		return lerp(fall.startPitch, tipPitch, alpha), roll * 0.35 * alpha
	end
	local progress = math.clamp((t - settings.TipSeconds) / math.max(settings.TurnSeconds, EPSILON), 0, 1)
	local alpha = smoothstep(progress)
	local pitch = lerp(tipPitch, math.rad(settings.LookUpPitchDegrees), alpha)
	return pitch, roll * (0.35 * (1 - alpha) + math.sin(progress * math.pi))
end

local function stepCamera(dt: number)
	local fall = active
	local camera = Workspace.CurrentCamera
	if not fall or fall.arrived or not camera then
		return
	end
	local settings = Config.IntroHole.Fall
	local t = os.clock() - fall.startTime
	camera.CameraType = Enum.CameraType.Scriptable
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	UserInputService.MouseIconEnabled = false
	for _, part in fall.bodyParts do
		part.LocalTransparencyModifier = 1
	end

	local pitch, roll = cameraAngles(fall, t)
	local turn = smoothstep((t - settings.TipSeconds) / math.max(settings.TurnSeconds, EPSILON))
	fall.yaw += math.rad(settings.DriftDegreesPerSecond) * turn * dt
	local speed = math.max(-fall.root.AssemblyLinearVelocity.Y, 0)
	local amplitude = math.rad(settings.ShakeDegrees) * math.clamp(speed / math.max(settings.MaxSpeed, EPSILON), 0, 1)
	local noiseTime = t * settings.ShakeSpeed
	local shake = CFrame.Angles(
		math.noise(noiseTime, NOISE_PITCH) * amplitude,
		math.noise(noiseTime, NOISE_YAW) * amplitude,
		math.noise(noiseTime, NOISE_ROLL) * amplitude
	)
	local eye = fall.root.Position + Vector3.yAxis * fall.eyeOffset
	camera.CFrame = CFrame.new(eye) * CFrame.Angles(0, fall.yaw, 0) * CFrame.Angles(pitch, 0, roll) * shake
	camera.Focus = CFrame.new(eye)
	camera.FieldOfView = lerp(fall.startFov, settings.FieldOfView, smoothstep(t / math.max(settings.FovSeconds, EPSILON)))

	if not fall.floorHidden and eye.Y < fall.center.Y + Config.IntroHole.Shaft.RevealHeight then
		hideOpening(fall)
	end
	local dust = fall.dust
	if dust then
		dust.CFrame = CFrame.new(eye - Vector3.yAxis * Config.IntroHole.Shaft.Dust.Lead)
	end
	setFade(fall, (t - settings.FadeStart) / math.max(settings.FadeSeconds, EPSILON))
end

local function stepBody()
	local fall = active
	if not fall or fall.arrived then
		return
	end
	local settings = Config.IntroHole.Fall
	local t = os.clock() - fall.startTime
	local speed
	if t >= settings.FadeStart + settings.FadeSeconds then
		speed = 0
	elseif t < settings.TipSeconds then
		speed = settings.TipSpeed
	else
		speed = math.min(settings.TipSpeed + settings.Acceleration * (t - settings.TipSeconds), settings.MaxSpeed)
	end
	local offset = fall.center - fall.root.Position
	fall.root.AssemblyLinearVelocity = Vector3.new(offset.X * settings.CenterPull, -speed, offset.Z * settings.CenterPull)
	fall.root.AssemblyAngularVelocity = Vector3.zero
end

local function stepFall()
	local fall = active
	if not fall or fall.arrived then
		return
	end
	local settings = Config.IntroHole
	local t = os.clock() - fall.startTime
	if fall.character:GetAttribute(settings.FallingAttribute) == true then
		fall.confirmed = true
	elseif fall.confirmed then
		local target = fall.character:GetAttribute(settings.ArrivalAttribute)
		arrive(fall, if typeof(target) == "CFrame" then target else rimCFrame(fall))
		return
	end
	local unconfirmed = not fall.confirmed and t > settings.Fall.ConfirmSeconds
	if unconfirmed or t > settings.FallSeconds + settings.Fall.ArrivalTimeout then
		arrive(fall, rimCFrame(fall))
	end
end

local function beginFall(character: Model, humanoid: Humanoid, root: BasePart, center: Vector3, confirmed: boolean)
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local head = character:FindFirstChild("Head")
	local eyeOffset = if head and head:IsA("BasePart")
		then head.Position.Y - root.Position.Y + Config.Camera.EyeLift
		else DEFAULT_EYE_OFFSET
	local fall: Fall = {
		character = character,
		humanoid = humanoid,
		root = root,
		center = center,
		startTime = os.clock(),
		startPosition = root.Position,
		startPitch = math.asin(math.clamp(look.Y, -1, 1)),
		startFov = if camera then camera.FieldOfView else Config.Camera.FieldOfView,
		yaw = math.atan2(-look.X, -look.Z),
		eyeOffset = eyeOffset,
		confirmed = confirmed,
		arrived = false,
		cleaned = false,
		floorHidden = false,
		groups = {},
		bodyParts = {},
		hiddenParts = {},
		hiddenDecals = {},
		connections = {},
		bodyConnection = nil,
		shaft = nil,
		dust = nil,
		lift = nil,
		liftAttachment = nil,
		fadeGui = nil,
		fadeFrame = nil,
		wind = nil,
	}
	active = fall
	FirstPersonCameraController.setHudHidden(true)
	FirstPersonCameraController.disable()
	setControls(false)
	lockBody(fall)
	local shaft = buildShaft(center)
	fall.shaft = shaft
	fall.dust = buildDust(shaft)
	createFade(fall)
	flare()
	playFallAudio(fall)
	table.insert(fall.connections, RunService.PreSimulation:Connect(stepBody))
	table.insert(fall.connections, RunService.Heartbeat:Connect(stepFall))
	table.insert(fall.connections, humanoid.Died:Connect(function()
		cleanup(fall)
	end))
	table.insert(fall.connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(Workspace) then
			cleanup(fall)
		end
	end))
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 2, stepCamera)
end

local function readBody(character: Model): (Humanoid?, BasePart?)
	if character:GetAttribute(RAGDOLL_ATTRIBUTE) then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

local function checkTrigger(now: number)
	if active or now < retriggerAt then
		return
	end
	if not FirstPersonCameraController.isEnabled() or FirstPersonCameraController.isHudHidden() then
		return
	end
	local center = Workspace:GetAttribute(CENTER_ATTRIBUTE)
	local radius = Workspace:GetAttribute(RADIUS_ATTRIBUTE)
	local character = Players.LocalPlayer.Character
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" or not character then
		return
	end
	local humanoid, root = readBody(character)
	if not humanoid or not root then
		return
	end
	local settings = Config.IntroHole
	local offset = root.Position - center
	if offset.Y > settings.TriggerHeight or offset.Y < -settings.TriggerDepth then
		return
	end
	if Vector2.new(offset.X, offset.Z).Magnitude > radius then
		return
	end
	beginFall(character, humanoid, root, center, character:GetAttribute(settings.FallingAttribute) == true)
end

local function onFallingChanged(character: Model)
	if character:GetAttribute(Config.IntroHole.FallingAttribute) ~= true then
		return
	end
	if character == Players.LocalPlayer.Character then
		if active then
			return
		end
		local center = Workspace:GetAttribute(CENTER_ATTRIBUTE)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = if humanoid then humanoid.RootPart else nil
		if typeof(center) == "Vector3" and humanoid and root and humanoid.Health > 0 then
			beginFall(character, humanoid, root, center, true)
		end
		return
	end
	flare()
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		scream(root)
	end
end

local function unwatchCharacter(character: Model)
	local connection = watched[character]
	if connection then
		connection:Disconnect()
		watched[character] = nil
	end
end

local function watchCharacter(character: Model)
	if watched[character] then
		return
	end
	watched[character] = character:GetAttributeChangedSignal(Config.IntroHole.FallingAttribute):Connect(function()
		onFallingChanged(character)
	end)
end

local function watchPlayer(player: Player)
	if playerConnections[player] then
		return
	end
	playerConnections[player] = {
		player.CharacterAdded:Connect(watchCharacter),
		player.CharacterRemoving:Connect(unwatchCharacter),
	}
	if player.Character then
		watchCharacter(player.Character)
	end
end

local function unwatchPlayer(player: Player)
	local list = playerConnections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		playerConnections[player] = nil
	end
	if player.Character then
		unwatchCharacter(player.Character)
	end
end

local function onHeartbeat()
	local now = os.clock()
	updateGlow(now)
	checkTrigger(now)
end

function IntroHoleController.start()
	if isStarted then
		return
	end
	isStarted = true
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(unwatchPlayer))
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	table.insert(connections, RunService.Heartbeat:Connect(onHeartbeat))
end

function IntroHoleController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local players = {}
	for player in playerConnections do
		table.insert(players, player)
	end
	for _, player in players do
		unwatchPlayer(player)
	end
	for _, connection in watched do
		connection:Disconnect()
	end
	table.clear(watched)
	local fall = active
	if fall then
		cleanup(fall)
	end
	restoreGlow()
end

return IntroHoleController
