local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local FirstPersonCameraController = require(script.Parent:WaitForChild("FirstPersonCameraController"))

local MonsterController = {}

local SETTINGS = Config.Monsters
local GLITCH = SETTINGS.Glitch
local ANIMATION_BIND = "MonsterAnimation"
local JUMPSCARE_BIND = "MonsterJumpscare"
local GHOST_FOLDER = "MonsterWarpGhosts"
local GRADE_NAME = "MonsterGlitchGrade"
local HIDDEN = "Hidden"
local EMERGING = "Emerging"
local ENTERING = "Entering"
local NOTICING = "Noticing"
local CHASING = "Chasing"
local SEARCHING = "Searching"
local ROAMING = "Roaming"
local RETREATING = "Retreating"
local SOUND_LIFETIME = 10
local TEAR_HEIGHT = { 0.006, 0.05 }
local TEAR_SHIFT = 0.05
local TEAR_COLORS = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(110, 230, 255), Color3.fromRGB(255, 255, 255) }
local EPSILON = 0.001

local ARMS = {
	{ prefix = "UpR", side = 1, phase = 0, lift = 0 },
	{ prefix = "UpL", side = -1, phase = 1.7, lift = 0 },
	{ prefix = "BottomR", side = 1, phase = 3.1, lift = 0.15 },
	{ prefix = "BottomL", side = -1, phase = 4.4, lift = 0.15 },
}

type Pose = {
	lean: number,
	reach: number,
	flare: number,
	curl: number,
	jaw: number,
	look: number,
	scan: number,
}

local POSES: { [string]: Pose } = {
	Hidden = { lean = 0.1, reach = 0.2, flare = 0, curl = 0.3, jaw = 0.05, look = 0, scan = 0.3 },
	Emerging = { lean = 0.3, reach = 0.75, flare = 0.7, curl = 0.15, jaw = 0.75, look = 0, scan = 0 },
	Roaming = { lean = 0.12, reach = 0.2, flare = 0.05, curl = 0.3, jaw = 0.08, look = 0, scan = 0.6 },
	Searching = { lean = 0.06, reach = 0.35, flare = 0.2, curl = 0.4, jaw = 0.2, look = 0, scan = 1 },
	Noticing = { lean = -0.2, reach = 0.1, flare = 1, curl = 0.05, jaw = 1, look = 1, scan = 0 },
	Chasing = { lean = 0.34, reach = 0.85, flare = 0.25, curl = 0.65, jaw = 0.55, look = 1, scan = 0 },
	Attacking = { lean = 0.55, reach = 1, flare = 0, curl = 0.95, jaw = 1, look = 1, scan = 0 },
	Caught = { lean = 0.4, reach = 1, flare = 0.1, curl = 1, jaw = 1, look = 1, scan = 0 },
	Retreating = { lean = 0.18, reach = 0.3, flare = 0.1, curl = 0.3, jaw = 0.1, look = 0, scan = 0.2 },
	Entering = { lean = 0.4, reach = 1, flare = 0.4, curl = 0.1, jaw = 0.6, look = 0, scan = 0 },
}

type BoneEntry = {
	bone: Bone,
	bind: CFrame,
	inverse: CFrame,
}

type Ghost = {
	model: Model,
	mesh: MeshPart,
	bones: { [string]: Bone },
	glow: PointLight?,
	lag: number,
	base: number,
}

type View = {
	model: Model,
	mesh: MeshPart,
	settings: any,
	scale: number,
	bones: { [string]: BoneEntry },
	lights: { Light },
	seed: number,
	state: string,
	stateTime: number,
	pose: Pose,
	moving: number,
	headYaw: number,
	headPitch: number,
	twitch: CFrame,
	twitchUntil: number,
	nextTwitch: number,
	ghosts: { Ghost },
	surgeTv: Model?,
	breath: Sound?,
	nextVoiceAt: number,
	hidden: boolean,
	connections: { RBXScriptConnection },
}

type Glitch = {
	gui: ScreenGui,
	static: ImageLabel,
	red: ImageLabel,
	vignette: Frame,
	tears: { ImageLabel },
	grade: ColorCorrectionEffect?,
	glitchSound: Sound?,
	heartbeat: Sound?,
	intensity: number,
	nextFrameAt: number,
	redUntil: number,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local views: { [Model]: View } = {}
local glitch: Glitch? = nil
local jumpscareView: View? = nil
local jumpscareStart = 0
local rng = Random.new()
local warnedSounds: { [string]: boolean } = {}

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

local function smoothstep(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

local function between(values: { number }): number
	return rng:NextNumber(values[1], values[2])
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function findSound(name: string): Sound?
	local sound = SoundService:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		return sound
	end
	if not warnedSounds[name] then
		warnedSounds[name] = true
		warn("MonsterController: SoundService." .. name .. " not found")
	end
	return nil
end

local function playAt(name: string, parent: Instance, volumeScale: number?, speedRange: { number }?)
	local template = findSound(name)
	if not template then
		return
	end
	local sound = template:Clone()
	sound.Looped = false
	sound.Volume = template.Volume * (volumeScale or 1)
	if speedRange then
		sound.PlaybackSpeed = template.PlaybackSpeed * between(speedRange)
	end
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, SOUND_LIFETIME)
end

local function playAtPoint(name: string, position: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	playAt(name, attachment)
	Debris:AddItem(attachment, SOUND_LIFETIME)
end

local function setPose(view: View, name: string, rotation: CFrame, offset: Vector3?)
	local entry = view.bones[name]
	if not entry then
		return
	end
	local transform = entry.inverse * rotation * entry.bind
	if offset then
		transform = CFrame.new(entry.bind:VectorToObjectSpace(offset)) * transform
	end
	entry.bone.Transform = transform
end

local function targetHead(view: View): Vector3?
	local id = view.model:GetAttribute(SETTINGS.TargetAttribute)
	local player = if type(id) == "number" and id > 0 then Players:GetPlayerByUserId(id) else nil
	local character = if player then player.Character else nil
	local head = if character then character:FindFirstChild("Head") else nil
	return if head and head:IsA("BasePart") then head.Position else nil
end

local function stateDuration(view: View): number
	local timing = view.settings.Timing
	return if view.state == EMERGING then timing.Emerge else timing.Enter
end

local function warping(view: View): boolean
	return view.state == EMERGING or view.state == ENTERING
end

local function animate(view: View, dt: number, now: number)
	local settings = view.settings
	local animation = settings.Animation
	local target = POSES[view.state] or POSES.Roaming
	local alpha = 1 - math.exp(-animation.Smoothing * dt)
	local jawAlpha = 1 - math.exp(-animation.JawSmoothing * dt)
	local pose = view.pose
	pose.lean += (target.lean - pose.lean) * alpha
	pose.reach += (target.reach - pose.reach) * alpha
	pose.flare += (target.flare - pose.flare) * alpha
	pose.curl += (target.curl - pose.curl) * alpha
	pose.look += (target.look - pose.look) * alpha
	pose.scan += (target.scan - pose.scan) * alpha
	pose.jaw += (target.jaw - pose.jaw) * jawAlpha

	local mesh = view.mesh
	local velocity = mesh.AssemblyLinearVelocity
	local localVelocity = mesh.CFrame:VectorToObjectSpace(velocity)
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	view.moving += (math.clamp(speed / settings.Speeds.Chase, 0, 1) - view.moving) * alpha
	local moving = view.moving
	local t = now + view.seed
	local shudder = if view.state == NOTICING then math.exp(-(serverNow() - view.stateTime) * 2.2) else 0

	local bob = math.sin(t * (1.5 + moving * 5)) * (0.22 + moving * 0.18) * view.scale
	local lean = pose.lean + moving * 0.12
	local bank = math.clamp(localVelocity.X / settings.Speeds.Chase, -1, 1) * 0.16 + math.sin(t * 0.8) * 0.035
	local twist = math.sin(t * 0.6) * 0.07 + math.sin(t * (2 + moving * 6)) * 0.06 * moving
	local jolt = shudder * 0.14
	setPose(view, "Pelvis", CFrame.Angles(0, twist * 0.4, bank * 0.3), Vector3.new(0, bob, 0))
	for index, name in { "Spine1", "Spine2", "Spine3" } do
		local weight = if index == 1 then 0.3 else 0.35
		local shake = CFrame.Angles(
			math.noise(t * 18, index * 1.7) * jolt,
			math.noise(t * 18, index * 2.9) * jolt,
			math.noise(t * 18, index * 4.3) * jolt
		)
		setPose(view, name, CFrame.Angles(-lean * weight, twist * weight, bank * weight) * shake)
	end

	local lookYaw, lookPitch = 0, 0
	local head = view.bones.Head
	local aim = if pose.look > 0.01 then targetHead(view) else nil
	if aim and head then
		local direction = mesh.CFrame:VectorToObjectSpace(aim - head.bone.WorldPosition)
		local yawLimit = math.rad(animation.LookYawLimit)
		local pitchLimit = math.rad(animation.LookPitchLimit)
		lookYaw = math.clamp(math.atan2(-direction.X, -direction.Z), -yawLimit, yawLimit) * pose.look
		lookPitch = math.clamp(math.atan2(direction.Y, Vector2.new(direction.X, direction.Z).Magnitude) + lean * 0.8, -pitchLimit, pitchLimit) * pose.look
	end
	local scanYaw = (math.sin(t * 0.42) * 0.55 + math.noise(t * 0.3, 5.5) * 0.4) * pose.scan
	local scanPitch = (math.noise(t * 0.25, 6.6) * 0.15 - 0.08) * pose.scan
	local headAlpha = 1 - math.exp(-animation.HeadSmoothing * dt)
	view.headYaw += (lookYaw + scanYaw - view.headYaw) * headAlpha
	view.headPitch += (lookPitch + scanPitch - view.headPitch) * headAlpha

	if now >= view.nextTwitch then
		local angles = animation.TwitchAngles
		view.twitch = CFrame.Angles(
			rng:NextNumber(-angles[2], angles[2]),
			rng:NextNumber(-angles[1], angles[1]),
			rng:NextNumber(-angles[3], angles[3])
		)
		view.twitchUntil = now + between(animation.TwitchSeconds)
		view.nextTwitch = now + between(if view.state == CHASING then animation.ChaseTwitchInterval else animation.TwitchInterval)
		if not view.hidden and not warping(view) and rng:NextNumber() < animation.TwitchCrackChance then
			local audio = settings.Audio
			playAt(audio.Twitch, mesh, audio.TwitchVolumeScale, audio.TwitchSpeedRange)
		end
	end
	local twitch = if now < view.twitchUntil then view.twitch else CFrame.identity
	local tilt = math.sin(t * 0.33) * 0.12 * (pose.scan + 0.3)
	setPose(view, "Neck", CFrame.Angles(0, view.headYaw * 0.4, 0) * CFrame.Angles(view.headPitch * 0.4, 0, 0))
	setPose(view, "Head", CFrame.Angles(0, view.headYaw * 0.6, 0) * CFrame.Angles(view.headPitch * 0.6, 0, tilt) * twitch)
	local jaw = math.clamp(pose.jaw + math.noise(t * 9, 7.7) * 0.08 * pose.jaw + shudder * 0.2, 0, 1.2)
	setPose(view, "Jaw", CFrame.Angles(-jaw * 0.55, 0, 0))
	setPose(view, "RightEye", CFrame.Angles(math.noise(t * 7, 8.1) * 0.12, math.noise(t * 7, 8.9) * 0.12, 0))
	setPose(view, "LeftEye", CFrame.Angles(math.noise(t * 7, 9.4) * 0.12, math.noise(t * 7, 9.9) * 0.12, 0))

	for index, arm in ARMS do
		local side = arm.side
		local phase = t * (1.1 + moving * 4.2) + arm.phase
		local swing = math.sin(phase) * (0.12 + 0.4 * moving)
		local reach = pose.reach * 0.95 + arm.lift * pose.reach
		local lower = (0.45 - pose.flare * 0.95) + math.sin(phase * 0.7 + index) * 0.08
		local wave = math.sin(phase * 1.4 + index * 0.9)
		local grab = pose.curl
		local spasm = math.noise(t * 14, index * 3.3) * shudder * 0.3
		setPose(view, arm.prefix .. "Arm1", CFrame.Angles(0, side * (reach + swing), -side * lower + spasm))
		setPose(view, arm.prefix .. "Arm2", CFrame.Angles(math.sin(phase + 0.7) * 0.12, side * wave * 0.12, side * (0.15 * wave - grab * 0.25)))
		setPose(view, arm.prefix .. "Arm3", CFrame.Angles(math.sin(phase + 1.4) * 0.14, side * (grab * 0.35 + wave * 0.1), side * 0.12 * math.sin(phase + 1.4)))
		setPose(view, arm.prefix .. "Hand", CFrame.Angles(grab * 0.35, side * math.sin(phase + 2.1) * 0.18, 0))
		for finger = 1, 6 do
			local curl = grab * (if finger % 2 == 1 then 0.5 else 0.8) + math.noise(t * 3, index * 10 + finger) * 0.15
			setPose(view, arm.prefix .. "Finger" .. finger, CFrame.Angles(0, side * curl, 0))
		end
	end
end

local function destroyGhosts(view: View)
	for _, ghost in view.ghosts do
		ghost.model:Destroy()
	end
	table.clear(view.ghosts)
	local tv = view.surgeTv
	if tv then
		tv:SetAttribute(Config.SignalMaze.Screens.SurgeAttribute, nil)
		view.surgeTv = nil
	end
end

local function ghostFolder(): Instance?
	local folder = Workspace:FindFirstChild(GHOST_FOLDER)
	if folder then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = GHOST_FOLDER
	created.Parent = Workspace
	return created
end

local function ensureGhosts(view: View)
	if #view.ghosts > 0 then
		return
	end
	local folder = ghostFolder()
	if not folder then
		return
	end
	local warp = view.settings.Warp
	for index = 0, warp.Afterimages do
		local model = Instance.new("Model")
		model.Name = "Ghost"
		local mesh = view.mesh:Clone()
		for _, descendant in mesh:GetDescendants() do
			if descendant:IsA("Light") or descendant:IsA("Sound") then
				descendant:Destroy()
			end
		end
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = false
		mesh.LocalTransparencyModifier = 0
		mesh.Parent = model
		local bones: { [string]: Bone } = {}
		for _, descendant in mesh:GetDescendants() do
			if descendant:IsA("Bone") then
				bones[descendant.Name] = descendant
			end
		end
		local glow: PointLight? = nil
		if index == 0 then
			local light = Instance.new("PointLight")
			light.Color = warp.Color
			light.Range = warp.GlowRange
			light.Brightness = 0
			light.Shadows = false
			light.Parent = mesh
			glow = light
		else
			mesh.TextureID = ""
			mesh.Material = Enum.Material.Neon
			mesh.Color = if index == 1 then warp.Color else warp.Outline
		end
		model.Parent = folder
		table.insert(view.ghosts, {
			model = model,
			mesh = mesh,
			bones = bones,
			glow = glow,
			lag = index * warp.AfterimageLag,
			base = if index == 0 then 0 else 0.35 + index * 0.15,
		})
	end
end

local function findTv(position: Vector3, radius: number): Model?
	local best: Model? = nil
	local bestDistance = radius
	for _, model in CollectionService:GetTagged(SETTINGS.TvTag) do
		if model:IsA("Model") then
			local glass = model:FindFirstChild(SETTINGS.TvGlassName)
			if glass and glass:IsA("BasePart") then
				local distance = (glass.Position - position).Magnitude
				if distance < bestDistance then
					best = model
					bestDistance = distance
				end
			end
		end
	end
	return best
end

local function updateWarp(view: View)
	if not warping(view) then
		if #view.ghosts > 0 or view.surgeTv then
			destroyGhosts(view)
		end
		return
	end
	local glass = view.model:GetAttribute(SETTINGS.TvGlassAttribute)
	local normal = view.model:GetAttribute(SETTINGS.TvNormalAttribute)
	if typeof(glass) ~= "Vector3" or typeof(normal) ~= "Vector3" then
		return
	end
	ensureGhosts(view)
	local warp = view.settings.Warp
	local progress = math.clamp((serverNow() - view.stateTime) / math.max(stateDuration(view), EPSILON), 0, 1)
	local emerging = view.state == EMERGING
	local real = view.mesh.CFrame
	local baseSize = view.mesh.Size
	local start = glass - normal * 0.4
	for _, ghost in view.ghosts do
		local out = if emerging then math.clamp(progress - ghost.lag, 0, 1) else 1 - math.clamp(progress + ghost.lag, 0, 1)
		local eased = 1 - (1 - out) ^ 3
		local bump = math.sin(out * math.pi)
		local size = lerp(warp.StartScale, 1, eased)
		local jitter = (1 - out) * warp.Jitter * view.scale * 2
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 1)) * jitter
		ghost.mesh.Size = baseSize * Vector3.new(size * (1 - 0.18 * bump), size * (1 + warp.Stretch * bump), lerp(warp.Depth, 1, eased * eased))
		ghost.mesh.CFrame = CFrame.new(start:Lerp(real.Position, eased) + offset)
			* real.Rotation
			* CFrame.Angles(rng:NextNumber(-0.1, 0.1) * (1 - out), 0, rng:NextNumber(-0.15, 0.15) * (1 - out))
		local flicker = if rng:NextNumber() < 0.18 * (1 - out) then 0.6 else 0
		local trail = if ghost.lag > 0 then out * out * 0.6 else 0
		ghost.mesh.Transparency = math.clamp(ghost.base + (1 - out) * 0.35 + flicker + trail, 0, 1)
		local glow = ghost.glow
		if glow then
			glow.Brightness = warp.GlowBrightness * (1 - out * out) * (0.55 + 0.45 * rng:NextNumber())
		end
		for name, entry in view.bones do
			local bone = ghost.bones[name]
			if bone then
				bone.Transform = entry.bone.Transform
			end
		end
	end
	local tv = view.surgeTv or findTv(glass, warp.SurgeDistance)
	view.surgeTv = tv
	if tv then
		tv:SetAttribute(Config.SignalMaze.Screens.SurgeAttribute, math.sin(progress * math.pi) * 0.8 + 0.2)
	end
end

local function setBreath(view: View, on: boolean)
	local current = view.breath
	if on and not current then
		local template = findSound(view.settings.Audio.Breath)
		if template then
			local sound = template:Clone()
			sound.Looped = true
			sound.Parent = view.mesh
			sound:Play()
			view.breath = sound
		end
	elseif not on and current then
		view.breath = nil
		current:Destroy()
	end
end

local function updateVisibility(view: View)
	local hidden = view.state == HIDDEN
	local invisible = hidden or warping(view)
	view.hidden = hidden
	view.mesh.LocalTransparencyModifier = if invisible then 1 else 0
	for _, light in view.lights do
		light.Enabled = not invisible
	end
	setBreath(view, not invisible)
end

local function updateVoices(view: View, now: number)
	if view.hidden or warping(view) or now < view.nextVoiceAt then
		return
	end
	local audio = view.settings.Audio
	if view.state == CHASING then
		playAt(audio.Growl, view.mesh, 1, { 0.9, 1.1 })
		view.nextVoiceAt = now + between(audio.ChaseGrowl)
	elseif view.state == SEARCHING then
		playAt(audio.Murmur, view.mesh, 1, { 0.85, 1.05 })
		view.nextVoiceAt = now + between(audio.SearchMurmur)
	elseif view.state == ROAMING or view.state == RETREATING then
		playAt(if rng:NextNumber() < 0.5 then audio.Murmur else audio.Possessed, view.mesh, 0.8, { 0.85, 1.05 })
		view.nextVoiceAt = now + between(audio.RoamMurmur)
	end
end

local function onStateChanged(view: View)
	local state = view.model:GetAttribute(SETTINGS.StateAttribute)
	local stateTime = view.model:GetAttribute(SETTINGS.StateTimeAttribute)
	view.state = if type(state) == "string" then state else HIDDEN
	view.stateTime = if type(stateTime) == "number" then stateTime else serverNow()
	local audio = view.settings.Audio
	if view.state == NOTICING then
		playAt(audio.Notice, view.mesh, 1, { 0.95, 1.05 })
		view.nextVoiceAt = os.clock() + 2.5
	elseif warping(view) then
		local glass = view.model:GetAttribute(SETTINGS.TvGlassAttribute)
		if typeof(glass) == "Vector3" then
			playAtPoint(audio.Warp, glass)
			playAtPoint(audio.WarpWhoosh, glass)
		end
		destroyGhosts(view)
	end
	updateVisibility(view)
end

local function addMonster(model: Instance)
	if not model:IsA("Model") or views[model] then
		return
	end
	local key = model:GetAttribute(SETTINGS.TypeAttribute)
	local settings = if type(key) == "string" then (SETTINGS.Types :: any)[key] else nil
	local mesh = model:FindFirstChildWhichIsA("MeshPart") or model:WaitForChild("The Boiled One", 10)
	if not settings or not mesh or not mesh:IsA("MeshPart") then
		return
	end
	local bones: { [string]: BoneEntry } = {}
	for _, descendant in mesh:GetDescendants() do
		if descendant:IsA("Bone") then
			descendant.Transform = CFrame.identity
		end
	end
	for _, descendant in mesh:GetDescendants() do
		if descendant:IsA("Bone") then
			local bind = mesh.CFrame:ToObjectSpace(descendant.WorldCFrame).Rotation
			bones[descendant.Name] = { bone = descendant, bind = bind, inverse = bind:Inverse() }
		end
	end
	local lights: { Light } = {}
	for _, descendant in mesh:GetDescendants() do
		if descendant:IsA("Light") then
			table.insert(lights, descendant)
		end
	end
	local view: View = {
		model = model,
		mesh = mesh,
		settings = settings,
		scale = settings.Scale,
		bones = bones,
		lights = lights,
		seed = rng:NextNumber(0, 100),
		state = HIDDEN,
		stateTime = serverNow(),
		pose = table.clone(POSES.Hidden),
		moving = 0,
		headYaw = 0,
		headPitch = 0,
		twitch = CFrame.identity,
		twitchUntil = 0,
		nextTwitch = os.clock() + 1,
		ghosts = {},
		surgeTv = nil,
		breath = nil,
		nextVoiceAt = os.clock() + 3,
		hidden = true,
		connections = {},
	}
	views[model] = view
	table.insert(view.connections, model:GetAttributeChangedSignal(SETTINGS.StateAttribute):Connect(function()
		onStateChanged(view)
	end))
	onStateChanged(view)
end

local function removeMonster(model: Instance)
	local view = views[model :: Model]
	if not view then
		return
	end
	views[model :: Model] = nil
	for _, connection in view.connections do
		connection:Disconnect()
	end
	destroyGhosts(view)
	setBreath(view, false)
	if jumpscareView == view then
		jumpscareView = nil
	end
end

local function buildGlitch(): Glitch?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = GLITCH.GuiName
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = GLITCH.DisplayOrder
	gui.Enabled = false
	local function image(name: string, source: string, rect: number, zIndex: number): ImageLabel
		local label = Instance.new("ImageLabel")
		label.Name = name
		label.Image = source
		label.ImageRectSize = Vector2.new(rect, rect)
		label.ScaleType = Enum.ScaleType.Stretch
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = zIndex
		label.ImageTransparency = 1
		label.Parent = gui
		return label
	end
	local vignette = Instance.new("Frame")
	vignette.Name = "Shade"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.new(0, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.ZIndex = 1
	vignette.Parent = gui
	local static = image("Static", GLITCH.StaticImage, GLITCH.StaticFrame, 2)
	local red = image("Signal", GLITCH.RedImage, GLITCH.RedFrame, 3)
	red.Visible = false
	red.ImageTransparency = GLITCH.RedFlashTransparency
	local tears: { ImageLabel } = {}
	for index = 1, GLITCH.Tears do
		local tear = image("Tear" .. index, GLITCH.StaticImage, GLITCH.StaticFrame, 4)
		tear.AnchorPoint = Vector2.new(0.5, 0)
		tear.Size = UDim2.fromScale(1.12, 0.02)
		tear.ImageColor3 = TEAR_COLORS[(index - 1) % #TEAR_COLORS + 1]
		tear.Visible = false
		table.insert(tears, tear)
	end
	gui.Parent = playerGui
	return {
		gui = gui,
		static = static,
		red = red,
		vignette = vignette,
		tears = tears,
		grade = nil,
		glitchSound = nil,
		heartbeat = nil,
		intensity = 0,
		nextFrameAt = 0,
		redUntil = 0,
	}
end

local function loopSound(name: string): Sound?
	local template = findSound(name)
	if not template then
		return nil
	end
	local sound = template:Clone()
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	return sound
end

local function ensureGrade(current: Glitch): ColorCorrectionEffect?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local grade = current.grade
	if grade and grade.Parent == camera then
		return grade
	end
	if grade then
		grade:Destroy()
	end
	local created = Instance.new("ColorCorrectionEffect")
	created.Name = GRADE_NAME
	created.Parent = camera
	current.grade = created
	return created
end

local function targetIntensity(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end
	if jumpscareView then
		return 1
	end
	local eye = camera.CFrame.Position
	local best = 0
	for _, view in views do
		if view.hidden then
			continue
		end
		local position = view.mesh.Position
		local distance = (position - eye).Magnitude
		local amount = smoothstep((GLITCH.Range - distance) / math.max(GLITCH.Range - GLITCH.FullRange, EPSILON))
		if amount > 0 and (position - eye).Unit:Dot(camera.CFrame.LookVector) > 0.5 then
			amount = math.min(1, amount * (1 + GLITCH.VisibleBonus))
		end
		if warping(view) then
			local glass = view.model:GetAttribute(SETTINGS.TvGlassAttribute)
			if typeof(glass) == "Vector3" then
				local near = 1 - (glass - eye).Magnitude / GLITCH.WarpRange
				amount = math.max(amount, near * 0.85)
			end
		end
		best = math.max(best, amount)
	end
	return math.clamp(best, 0, 1)
end

local function updateGlitch(dt: number, now: number)
	local current = glitch
	if not current or not current.gui.Parent then
		current = buildGlitch()
		glitch = current
		if not current then
			return
		end
	end
	local goal = targetIntensity()
	local rate = if goal > current.intensity then GLITCH.Rise else GLITCH.Fall
	current.intensity += (goal - current.intensity) * (1 - math.exp(-rate * dt))
	local intensity = current.intensity
	local active = intensity > 0.01
	current.gui.Enabled = active
	local grade = ensureGrade(current)
	if grade then
		local settings = GLITCH.Grade
		grade.Enabled = active
		grade.Saturation = settings.Saturation * intensity
		grade.Contrast = settings.Contrast * intensity + rng:NextNumber(-1, 1) * settings.Flicker * intensity
		grade.Brightness = settings.Brightness * intensity + rng:NextNumber(-0.5, 0.5) * settings.Flicker * intensity
		grade.TintColor = Color3.new(1, 1, 1):Lerp(settings.Tint, intensity)
	end
	if not current.glitchSound then
		current.glitchSound = loopSound(GLITCH.GlitchSound)
	end
	if not current.heartbeat then
		current.heartbeat = loopSound(GLITCH.HeartbeatSound)
	end
	local glitchTemplate = SoundService:FindFirstChild(GLITCH.GlitchSound)
	local heartbeatTemplate = SoundService:FindFirstChild(GLITCH.HeartbeatSound)
	if current.glitchSound and glitchTemplate and glitchTemplate:IsA("Sound") then
		current.glitchSound.Volume = glitchTemplate.Volume * intensity ^ 1.3
	end
	if current.heartbeat and heartbeatTemplate and heartbeatTemplate:IsA("Sound") then
		current.heartbeat.Volume = heartbeatTemplate.Volume * intensity
		current.heartbeat.PlaybackSpeed = lerp(GLITCH.HeartbeatSpeed[1], GLITCH.HeartbeatSpeed[2], intensity)
	end
	if not active then
		return
	end
	current.vignette.BackgroundTransparency = 1 - intensity * GLITCH.VignetteOpacity
	current.static.ImageTransparency = 1 - intensity * GLITCH.StaticOpacity
	if now >= current.nextFrameAt then
		current.nextFrameAt = now + 1 / GLITCH.StaticFps
		local frame = rng:NextInteger(0, GLITCH.StaticGrid * GLITCH.StaticGrid - 1)
		current.static.ImageRectOffset = Vector2.new(frame % GLITCH.StaticGrid, frame // GLITCH.StaticGrid) * GLITCH.StaticFrame
		for _, tear in current.tears do
			local show = rng:NextNumber() < GLITCH.TearChance * intensity
			tear.Visible = show
			if show then
				local tearFrame = rng:NextInteger(0, GLITCH.StaticGrid * GLITCH.StaticGrid - 1)
				tear.ImageRectOffset = Vector2.new(tearFrame % GLITCH.StaticGrid, tearFrame // GLITCH.StaticGrid) * GLITCH.StaticFrame
				tear.Position = UDim2.fromScale(0.5 + rng:NextNumber(-TEAR_SHIFT, TEAR_SHIFT) * intensity, rng:NextNumber(0, 1))
				tear.Size = UDim2.fromScale(1.12, between(TEAR_HEIGHT) * (0.5 + intensity))
				tear.ImageTransparency = GLITCH.TearTransparency + (1 - intensity) * (1 - GLITCH.TearTransparency)
			end
		end
	end
	if now >= current.redUntil and rng:NextNumber() < GLITCH.RedFlashChance * intensity * intensity * dt then
		current.redUntil = now + GLITCH.RedFlashSeconds
		local frame = rng:NextInteger(0, GLITCH.RedGrid * GLITCH.RedGrid - 1)
		current.red.ImageRectOffset = Vector2.new(frame % GLITCH.RedGrid, frame // GLITCH.RedGrid) * GLITCH.RedFrame
	end
	current.red.Visible = now < current.redUntil
end

local function nearestView(): View?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local best: View? = nil
	local bestDistance = math.huge
	for _, view in views do
		local distance = (view.mesh.Position - root.Position).Magnitude
		if distance < bestDistance then
			best = view
			bestDistance = distance
		end
	end
	return best
end

local function stepJumpscare(_: number)
	local view = jumpscareView
	local camera = Workspace.CurrentCamera
	if not view or not camera then
		return
	end
	local settings = SETTINGS.Jumpscare
	local head = view.bones.Head
	local face = if head then head.bone.WorldPosition else view.mesh.Position + Vector3.yAxis * view.mesh.Size.Y * 0.35
	local forward = view.mesh.CFrame.LookVector
	local elapsed = os.clock() - jumpscareStart
	local amplitude = math.rad(settings.ShakeDegrees)
	local shake = CFrame.Angles(
		math.noise(elapsed * settings.ShakeSpeed, 1.3) * amplitude,
		math.noise(elapsed * settings.ShakeSpeed, 2.6) * amplitude,
		math.noise(elapsed * settings.ShakeSpeed, 3.9) * amplitude
	)
	local eye = face + forward * settings.Distance - Vector3.yAxis * 0.4
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye, face) * shake
	camera.FieldOfView = lerp(settings.FieldOfView[1], settings.FieldOfView[2], math.clamp(elapsed / 0.6, 0, 1))
end

local function stopJumpscare()
	if not jumpscareView then
		return
	end
	jumpscareView = nil
	pcall(function()
		RunService:UnbindFromRenderStep(JUMPSCARE_BIND)
	end)
	FirstPersonCameraController.setHudHidden(false)
end

local function startJumpscare()
	local view = nearestView()
	if not view or jumpscareView then
		return
	end
	jumpscareView = view
	jumpscareStart = os.clock()
	FirstPersonCameraController.setHudHidden(true)
	local audio = view.settings.Audio
	playAt(audio.Jumpscare, SoundService)
	playAt(audio.JumpscareBoom, SoundService, 0.8)
	RunService:BindToRenderStep(JUMPSCARE_BIND, Enum.RenderPriority.Camera.Value + 20, stepJumpscare)
end

local function onCaughtChanged()
	if Players.LocalPlayer:GetAttribute(SETTINGS.CaughtAttribute) == true then
		startJumpscare()
	else
		stopJumpscare()
	end
end

local function onRender(dt: number)
	local now = os.clock()
	for _, view in views do
		if not view.mesh.Parent then
			continue
		end
		animate(view, dt, now)
		updateWarp(view)
		updateVoices(view, now)
	end
	updateGlitch(dt, now)
end

function MonsterController.isCaught(): boolean
	return jumpscareView ~= nil
end

function MonsterController.start()
	if isStarted then
		return
	end
	isStarted = true
	table.insert(connections, CollectionService:GetInstanceAddedSignal(SETTINGS.Tag):Connect(function(model)
		task.spawn(addMonster, model)
	end))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(SETTINGS.Tag):Connect(removeMonster))
	for _, model in CollectionService:GetTagged(SETTINGS.Tag) do
		task.spawn(addMonster, model)
	end
	local player = Players.LocalPlayer
	table.insert(connections, player:GetAttributeChangedSignal(SETTINGS.CaughtAttribute):Connect(onCaughtChanged))
	table.insert(connections, player.CharacterRemoving:Connect(stopJumpscare))
	RunService:BindToRenderStep(ANIMATION_BIND, Enum.RenderPriority.Camera.Value + 15, onRender)
end

function MonsterController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	pcall(function()
		RunService:UnbindFromRenderStep(ANIMATION_BIND)
	end)
	stopJumpscare()
	for model in views do
		removeMonster(model)
	end
	local current = glitch
	if current then
		current.gui:Destroy()
		if current.grade then
			current.grade:Destroy()
		end
		if current.glitchSound then
			current.glitchSound:Destroy()
		end
		if current.heartbeat then
			current.heartbeat:Destroy()
		end
		glitch = nil
	end
end

return MonsterController
