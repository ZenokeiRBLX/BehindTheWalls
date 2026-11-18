local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local CutsceneFormation = require(Shared:WaitForChild("Modules"):WaitForChild("CutsceneFormation"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))
local WRagdoll = require(ReplicatedStorage:WaitForChild("WRagdoll"))
local FootstepsController = require(script.Parent.Parent:WaitForChild("FootstepsController"))
local FirstPersonCameraController = require(script.Parent:WaitForChild("FirstPersonCameraController"))

local CutsceneController = {}

local CAMERA_PART_NAME = "Cutscene_Camera"
local CAMERA_PART_TIMEOUT = 30
local CAMERA_PART_POLL = 0.25
local CAMERA_BIND = "CutsceneCamera"
local LANDING_POLL = 0.05
local WAKE_BLUR_NAME = "CutsceneWakeBlur"
local FOV_ATTRIBUTE = "FieldOfView"
local CAMERA_CFRAME_ATTRIBUTE = "CutsceneCameraCFrame"
local CAMERA_FOV_ATTRIBUTE = "CutsceneCameraFov"
local PLAYERS_CFRAME_ATTRIBUTE = "CutscenePlayersCFrame"
local HOLE_ATTRIBUTE = "CutsceneHoleCFrame"
local HOLE_PART_NAME = "Cutscene_Hole"
local HOLE_MATCH_DISTANCE = 2
local PRELOADED_ATTRIBUTE = "CutscenePreloaded"
local PLAYERS_FOLDER_NAME = "Teleport_Players"
local STREAM_TIMEOUT = 8
local GUI_NAME = "Cutscene"
local FADE_GUI_NAME = "CutsceneFade"
local FADE_DISPLAY_ORDER = 1000
local SKIP_BUTTON_NAME = "Cutscene_Skip"
local SKIP_VOTES_TEXT = "%d/%d Votes"
local SKIP_VOTES_PATTERN = "%d+%s*/%s*%d+"
local ARRIVAL_COMPLETE_ATTRIBUTE = "ArrivalComplete"
local ARRIVAL_WAIT_MARGIN = 15
local ATTRIBUTE_TIMEOUT = 5
local MAX_PRELOAD_SAMPLES = 24
local FOV_SMOOTHING = 6
local RIG_PRELOAD_WAIT = 1.5
local PIVOT_EPSILON = 0.001
local SWAY_SPEED = 0.9
local WALK_RNG = Random.new()
local STEP_RAY_LIFT = 2
local STEP_RAY_LENGTH = 12
local FALL_ROLLOFF_MIN = 10
local FALL_ROLLOFF_MAX = 250
local FALL_SOUND_LIFETIME = 8
local IMPACT_PART_NAMES = { "LowerTorso", "UpperTorso", "Torso", "LeftFoot", "RightFoot" }
local ROOT_JOINT_NAME = "Root"
local TORSO_PARTS = { HumanoidRootPart = true, LowerTorso = true, UpperTorso = true }
local LIFT_ATTACHMENT_NAME = "CutsceneLift"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local WALK_EASE_LINEAR = 0.6
local SPEED_SMOOTHING = 8
local EFFECTS_FOLDER_NAME = "CutsceneEffects"
local DUST_ANCHOR_SIZE = 0.2
local DUST_LIFETIME_MARGIN = 0.5
local SHAKE_SEEDS = { 0.37, 7.13, 13.71 }

type CameraTarget = {
	cframe: CFrame,
	fov: number?,
}

type Walker = {
	rig: Model,
	slot: number,
	rank: number,
	offset: number,
	rootPart: BasePart?,
	startCFrame: CFrame,
	endCFrame: CFrame,
	brinkCFrame: CFrame,
	formationEnd: Vector3,
	track: AnimationTrack?,
	animationSpeed: number,
	speed: number,
	lastPosition: Vector3,
	distanceSinceStep: number,
	stepStride: number,
	dropAt: number,
	isLocal: boolean,
	dropped: boolean,
}

type MusicTrack = {
	sound: Sound,
	volume: number,
	tween: Tween?,
}

type CameraRig = {
	position: Vector3,
	focus: Vector3,
	shot: Shot?,
}

type Scene = {
	start: CFrame,
	players: CFrame,
	hole: CFrame?,
}

type Shot = {
	name: string,
	startAt: number,
	fov: number,
	anchor: string,
	from: { number },
	to: { number },
	focus: { number },
	smoothing: number,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local cameraBound = false
local released = false
local finished = false
local savedFov: number?
local gui: ScreenGui?
local fadeGui: ScreenGui?
local fadeFrame: Frame?
local musicTracks: { [string]: MusicTrack } = {}
local currentCFrame: CFrame? = nil
local currentFov: number? = nil
local sequenceToken = 0
local walkers: { Walker } = {}
local groupForward = -Vector3.zAxis
local cameraShake = 0
local effectsFolder: Folder? = nil
local holePart: BasePart? = nil
local holeSize: Vector3? = nil
local cameraRig: CameraRig? = nil
local skipLabel: TextLabel? = nil
local skipState: Blink.CutsceneSkipData? = nil
local skipDisconnect: (() -> ())? = nil

local function setCoreGuiEnabled(enabled: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, enabled)
	end)
end

local function findCameraPart(): BasePart?
	local part = Workspace:FindFirstChild(CAMERA_PART_NAME, true)
	return if part and part:IsA("BasePart") then part else nil
end

local function readTarget(): CameraTarget?
	local part = findCameraPart()
	if part then
		local fov = part:GetAttribute(FOV_ATTRIBUTE)
		return {
			cframe = part.CFrame,
			fov = if type(fov) == "number" then fov else nil,
		}
	end
	local published = Workspace:GetAttribute(CAMERA_CFRAME_ATTRIBUTE)
	if typeof(published) == "CFrame" then
		local fov = Workspace:GetAttribute(CAMERA_FOV_ATTRIBUTE)
		return {
			cframe = published,
			fov = if type(fov) == "number" then fov else nil,
		}
	end
	return nil
end

local function waitForTarget(): CameraTarget?
	local deadline = os.clock() + CAMERA_PART_TIMEOUT
	while os.clock() < deadline do
		local target = readTarget()
		if target then
			return target
		end
		task.wait(CAMERA_PART_POLL)
	end
	warn("CutsceneController: Workspace." .. CAMERA_PART_NAME .. " not found")
	return nil
end

local function readCFrameAttribute(name: string): CFrame?
	local value = Workspace:GetAttribute(name)
	return if typeof(value) == "CFrame" then value else nil
end

local function streamAround(position: Vector3)
	if not Workspace.StreamingEnabled then
		return
	end
	local ok, err = pcall(function()
		Players.LocalPlayer:RequestStreamAroundAsync(position, STREAM_TIMEOUT)
	end)
	if not ok then
		warn(("CutsceneController: RequestStreamAroundAsync failed: %s"):format(tostring(err)))
	end
end

local function bindCamera(target: CameraTarget)
	if cameraBound or released then
		return
	end
	cameraBound = true
	local camera = Workspace.CurrentCamera
	savedFov = if camera then camera.FieldOfView else nil
	currentCFrame = target.cframe
	currentFov = target.fov or Config.Cutscene.FieldOfView
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		local current = Workspace.CurrentCamera
		if not current then
			return
		end
		current.CameraType = Enum.CameraType.Scriptable
		current.CFrame = currentCFrame or target.cframe
		if type(currentFov) == "number" then
			current.FieldOfView = currentFov
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

local function flatForward(cframe: CFrame): Vector3
	local flat = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	return if flat.Magnitude > 0.001 then flat.Unit else -Vector3.zAxis
end

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function walkEase(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return alpha * WALK_EASE_LINEAR + smoothstep(alpha) * (1 - WALK_EASE_LINEAR)
end

local function blendDirection(from: Vector3, to: Vector3, alpha: number): Vector3
	local blended = from:Lerp(to, alpha)
	return if blended.Magnitude > PIVOT_EPSILON then blended.Unit else to
end

local function readScene(start: CFrame): Scene
	return {
		start = start,
		players = readCFrameAttribute(PLAYERS_CFRAME_ATTRIBUTE) or start,
		hole = readCFrameAttribute(HOLE_ATTRIBUTE),
	}
end

local function slotIndex(instance: Instance): number?
	return tonumber(instance.Name:match("%d+$"))
end

local function walkAnimationIdForSlot(slot: number): string
	for _, phoneSlot in Config.Cutscene.PhoneWalkSlots do
		if phoneSlot == slot then
			return Config.Cutscene.PhoneWalkAnimationId
		end
	end
	return Config.Cutscene.WalkAnimationId
end

local function preloadAssets(instances: { Instance })
	if #instances == 0 then
		return
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(instances)
	end)
	if not ok then
		warn(("CutsceneController: PreloadAsync failed: %s"):format(tostring(err)))
	end
end

local function preload(player: Player, scene: Scene)
	local spacing = math.max(Config.Cutscene.PreloadSpacing, 1)
	local from = scene.players.Position
	local to = if scene.hole then scene.hole.Position else from
	local length = (to - from).Magnitude
	local samples = math.clamp(math.ceil(length / spacing), 1, MAX_PRELOAD_SAMPLES)
	streamAround(scene.start.Position)
	for step = 0, samples do
		streamAround(from:Lerp(to, step / samples))
	end

	local assets: { Instance } = {}
	for _, animationId in { Config.Cutscene.WalkAnimationId, Config.Cutscene.PhoneWalkAnimationId } do
		local walkAnimation = Instance.new("Animation")
		walkAnimation.AnimationId = animationId
		table.insert(assets, walkAnimation)
	end
	task.wait(RIG_PRELOAD_WAIT)
	local folder = Workspace:FindFirstChild(PLAYERS_FOLDER_NAME, true)
	if folder then
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("MeshPart") or descendant:IsA("Decal") or descendant:IsA("Shirt") or descendant:IsA("Pants") or descendant:IsA("Accessory") or descendant:IsA("SpecialMesh") then
				table.insert(assets, descendant)
			end
		end
	end
	preloadAssets(assets)
	for _, asset in assets do
		if asset:IsA("Animation") then
			asset:Destroy()
		end
	end
	player:SetAttribute(PRELOADED_ATTRIBUTE, true)
end

local function loadWalkTrack(rig: Model, slot: number): AnimationTrack?
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = walkAnimationIdForSlot(slot)
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok then
		warn(("CutsceneController: could not load walk animation: %s"):format(tostring(track)))
		return nil
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Movement
	return track
end

local stepRaycastParams: RaycastParams?

local function floorMaterialAt(position: Vector3): Enum.Material
	local result = Workspace:Raycast(position + Vector3.yAxis * STEP_RAY_LIFT, Vector3.new(0, -STEP_RAY_LENGTH, 0), stepRaycastParams)
	return if result then result.Material else Enum.Material.Concrete
end

local function collectWalkers(scene: Scene): { Walker }
	local list: { Walker } = {}
	local folder = Workspace:FindFirstChild(PLAYERS_FOLDER_NAME, true)
	local hole = scene.hole
	if not folder or not hole then
		return list
	end
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { folder }
	stepRaycastParams = raycastParams
	local rigs: { [number]: Model } = {}
	local starts: { [number]: Vector3 } = {}
	for _, child in folder:GetChildren() do
		local index = if child:IsA("Model") then slotIndex(child) else nil
		if index and not rigs[index] then
			rigs[index] = child :: Model
			starts[index] = child:GetPivot().Position
		end
	end
	local spots, forward = CutsceneFormation.compute(hole.Position, starts)
	groupForward = forward
	for index, spot in spots do
		local rig = rigs[index]
		local startPosition = starts[index]
		local travel = (spot.gather.Position - startPosition):Dot(forward)
		local rootPart = rig.PrimaryPart or rig:FindFirstChild("HumanoidRootPart")
		table.insert(list, {
			rig = rig,
			slot = index,
			rank = spot.rank,
			offset = spot.offset,
			rootPart = if rootPart and rootPart:IsA("BasePart") then rootPart else nil,
			startCFrame = CFrame.lookAt(startPosition, startPosition + forward),
			endCFrame = spot.gather,
			brinkCFrame = spot.brink,
			formationEnd = startPosition + forward * travel,
			track = nil,
			animationSpeed = 1,
			speed = 0,
			lastPosition = startPosition,
			distanceSinceStep = 0,
			stepStride = math.max(Config.Cutscene.StepStride, 0.5),
			dropAt = 0,
			isLocal = false,
			dropped = false,
		})
	end
	table.sort(list, function(a, b)
		return a.slot < b.slot
	end)
	return list
end

local function groupCenter(list: { Walker }, fallback: Vector3): Vector3
	local sum = Vector3.zero
	local count = 0
	for _, walker in list do
		if walker.rig.Parent then
			sum += walker.rig:GetPivot().Position
			count += 1
		end
	end
	return if count > 0 then sum / count else fallback
end

local function walkerPosition(walker: Walker, alpha: number): (Vector3, number)
	local formation = walker.startCFrame.Position:Lerp(walker.formationEnd, alpha)
	local gathered = walker.startCFrame.Position:Lerp(walker.endCFrame.Position, alpha)
	local mergeStart = math.clamp(Config.Cutscene.Gather.MergeStart, 0, 0.99)
	local merge = smoothstep((alpha - mergeStart) / (1 - mergeStart))
	return formation:Lerp(gathered, merge), merge
end

local function stepWalker(walker: Walker, position: Vector3, dt: number)
	local delta = position - walker.lastPosition
	walker.lastPosition = position
	local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
	if dt > 0 then
		walker.speed += (distance / dt - walker.speed) * (1 - math.exp(-SPEED_SMOOTHING * dt))
		local track = walker.track
		if track then
			local settings = Config.Cutscene
			local scale = math.clamp(walker.speed / math.max(settings.WalkSpeed, 0.1), settings.WalkAnimationMinScale, settings.WalkAnimationMaxScale)
			track:AdjustSpeed(walker.animationSpeed * scale)
		end
	end
	walker.distanceSinceStep += distance
	if walker.distanceSinceStep < walker.stepStride then
		return
	end
	walker.distanceSinceStep -= walker.stepStride
	if walker.rootPart then
		FootstepsController.playStepAt(walker.rootPart, floorMaterialAt(position), Config.Cutscene.Audio.FootstepVolumeScale)
	end
end

local function moveWalkers(alpha: number, dt: number)
	for _, walker in walkers do
		if walker.rig.Parent and not walker.dropped then
			local position, merge = walkerPosition(walker, alpha)
			local look = blendDirection(walker.startCFrame.LookVector, walker.endCFrame.LookVector, merge)
			walker.rig:PivotTo(CFrame.lookAt(position, position + look))
			stepWalker(walker, position, dt)
		end
	end
end

local function stopWalkers(list: { Walker })
	for _, walker in list do
		if walker.track then
			walker.track:Stop(0.2)
			walker.track = nil
		end
	end
end

local function droppedCenter(list: { Walker }, fallback: Vector3): Vector3
	local sum = Vector3.zero
	local count = 0
	for _, walker in list do
		local root = if walker.dropped then walker.rig:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			sum += root.Position
			count += 1
		end
	end
	return if count > 0 then sum / count else fallback
end

local function setFade(alpha: number)
	if fadeFrame then
		fadeFrame.BackgroundTransparency = 1 - math.clamp(alpha, 0, 1)
	end
end

local function createFade(playerGui: PlayerGui)
	if fadeGui then
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
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	frame.Parent = screen
	screen.Parent = playerGui
	fadeGui = screen
	fadeFrame = frame
end

local function fadeOut()
	local screen = fadeGui
	local frame = fadeFrame
	fadeGui = nil
	fadeFrame = nil
	if not screen or not frame then
		return
	end
	if frame.BackgroundTransparency >= 1 then
		screen:Destroy()
		return
	end
	local info = TweenInfo.new(Config.Cutscene.Fall.FadeOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(frame, info, { BackgroundTransparency = 1 })
	tween.Completed:Once(function()
		screen:Destroy()
	end)
	tween:Play()
end

local function findSound(name: string): Sound?
	local sound = SoundService:FindFirstChild(name)
	return if sound and sound:IsA("Sound") then sound else nil
end

local function playMusic(name: string, fadeInSeconds: number)
	local sound = findSound(name)
	if not sound then
		warn("CutsceneController: SoundService." .. name .. " not found")
		return
	end
	local existing = musicTracks[name]
	local volume = if existing then existing.volume else sound.Volume
	if existing and existing.tween then
		existing.tween:Cancel()
	end
	sound.TimePosition = 0
	sound.Volume = 0
	sound:Play()
	local tween = TweenService:Create(sound, TweenInfo.new(math.max(fadeInSeconds, 0.05)), { Volume = volume })
	musicTracks[name] = { sound = sound, volume = volume, tween = tween }
	tween:Play()
end

local function stopMusic(name: string, seconds: number)
	local track = musicTracks[name]
	if not track then
		return
	end
	musicTracks[name] = nil
	if track.tween then
		track.tween:Cancel()
	end
	local sound = track.sound
	local restoreVolume = track.volume
	local tween = TweenService:Create(sound, TweenInfo.new(math.max(seconds, 0.05)), { Volume = 0 })
	tween.Completed:Once(function()
		sound:Stop()
		sound.Volume = restoreVolume
	end)
	tween:Play()
end

local function stopAllMusic(seconds: number)
	local names = {}
	for name in musicTracks do
		table.insert(names, name)
	end
	for _, name in names do
		stopMusic(name, seconds)
	end
end

local function playSound(name: string)
	local sound = findSound(name)
	if not sound then
		warn("CutsceneController: SoundService." .. name .. " not found")
		return
	end
	sound.TimePosition = 0
	sound:Play()
end

local function playSoundAt(name: string, part: BasePart, volumeScale: number, speedRange: { number }?)
	local template = findSound(name)
	if not template then
		warn("CutsceneController: SoundService." .. name .. " not found")
		return
	end
	local sound = template:Clone()
	sound.Volume = template.Volume * volumeScale
	if speedRange then
		sound.PlaybackSpeed = WALK_RNG:NextNumber(speedRange[1], speedRange[2])
	end
	if sound.RollOffMaxDistance >= 10000 then
		sound.RollOffMinDistance = FALL_ROLLOFF_MIN
		sound.RollOffMaxDistance = FALL_ROLLOFF_MAX
	end
	sound.Parent = part
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, FALL_SOUND_LIFETIME)
end

local function playFallSounds(rootPart: BasePart)
	local audio = Config.Cutscene.Audio
	playSoundAt(audio.BoneCrackName, rootPart, audio.BoneCrackVolumeScale, audio.BoneCrackSpeedRange)
	local screams = audio.ScreamNames
	if #screams > 0 then
		local pick = screams[WALK_RNG:NextInteger(1, #screams)]
		playSoundAt(pick, rootPart, audio.ScreamVolumeScale, audio.ScreamSpeedRange)
	end
end

local function playOptionalSound(name: string?)
	local sound = if name then findSound(name) else nil
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

local function clearLocalWalkers(list: { Walker })
	for _, walker in list do
		if walker.isLocal then
			walker.rig:Destroy()
		end
	end
end

local function ensureEffectsFolder(): Folder
	local existing = effectsFolder
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = EFFECTS_FOLDER_NAME
	folder.Parent = Workspace
	effectsFolder = folder
	return folder
end

local function clearEffects()
	if effectsFolder then
		effectsFolder:Destroy()
		effectsFolder = nil
	end
end

local function findHolePart(position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = HOLE_MATCH_DISTANCE
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and (descendant.Name == HOLE_PART_NAME or descendant.Name == Config.Cutscene.HoleName) then
			local distance = (descendant.Position - position).Magnitude
			if distance < bestDistance then
				best = descendant
				bestDistance = distance
			end
		end
	end
	return best
end

local function setHoleScale(scale: number)
	local part = holePart
	local size = holeSize
	if not part or not size or not part.Parent then
		return
	end
	local cframe = part.CFrame
	local function axisScale(direction: Vector3): number
		return if math.abs(direction.Y) > 0.7 then 1 else scale
	end
	part.Size = size * Vector3.new(axisScale(cframe.RightVector), axisScale(cframe.UpVector), axisScale(cframe.LookVector))
end

local function randomIn(range: { number }): number
	return WALK_RNG:NextNumber(range[1], range[2])
end

local function ringPoint(center: Vector3, forward: Vector3, right: Vector3, angle: number, radius: number): (Vector3, Vector3)
	local outward = -forward * math.cos(angle) + right * math.sin(angle)
	return center + outward * radius, outward
end

local function spawnChunk(position: Vector3, sizeRange: { number }, velocity: Vector3)
	local rubble = Config.Cutscene.Collapse.Rubble
	local width = randomIn(sizeRange)
	local part = Instance.new("Part")
	part.Name = "Rubble"
	part.Size = Vector3.new(width, width * WALK_RNG:NextNumber(0.35, 0.6), randomIn(sizeRange))
	part.Color = rubble.Color
	part.Material = rubble.Material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position - Vector3.yAxis * (part.Size.Y * 0.3))
		* CFrame.Angles(WALK_RNG:NextNumber(-0.4, 0.4), WALK_RNG:NextNumber(0, math.pi * 2), WALK_RNG:NextNumber(-0.4, 0.4))
	part.Parent = ensureEffectsFolder()
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = WALK_RNG:NextUnitVector() * rubble.Spin
	Debris:AddItem(part, rubble.Lifetime)
end

local function spawnDust(position: Vector3)
	local dust = Config.Cutscene.Collapse.Dust
	if dust.Count <= 0 then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "Dust"
	anchor.Size = Vector3.one * DUST_ANCHOR_SIZE
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = dust.Texture
	emitter.Color = ColorSequence.new(dust.Color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, dust.Size[1]),
		NumberSequenceKeypoint.new(1, dust.Size[2]),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, dust.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(dust.Lifetime[1], dust.Lifetime[2])
	emitter.Speed = NumberRange.new(dust.Speed[1], dust.Speed[2])
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	emitter.Drag = 1.5
	emitter.Acceleration = Vector3.new(0, -1, 0)
	emitter.LightInfluence = 1
	emitter.LightEmission = 0
	emitter.Enabled = false
	emitter.Parent = anchor
	anchor.Parent = ensureEffectsFolder()
	emitter:Emit(dust.Count)
	Debris:AddItem(anchor, dust.Lifetime[2] + DUST_LIFETIME_MARGIN)
end

local function spawnPebble(center: Vector3, forward: Vector3, right: Vector3, span: { number }, edgeRadius: number, crackScale: number)
	local pebbles = Config.Cutscene.Collapse.Pebbles
	local position, outward = ringPoint(center, forward, right, randomIn(span), WALK_RNG:NextNumber(edgeRadius * 0.97, edgeRadius * crackScale))
	local velocity = -outward * (WALK_RNG:NextNumber(0.2, 1) * pebbles.Speed) - Vector3.yAxis * WALK_RNG:NextNumber(0, pebbles.Speed)
	spawnChunk(position, pebbles.SizeRange, velocity)
end

local function spawnCollapse(center: Vector3, forward: Vector3, right: Vector3, span: { number }, innerRadius: number, outerRadius: number)
	local collapse = Config.Cutscene.Collapse
	local rubble = collapse.Rubble
	for _ = 1, math.max(rubble.Count, 0) do
		local position, outward = ringPoint(center, forward, right, randomIn(span), WALK_RNG:NextNumber(innerRadius, outerRadius))
		local velocity = -outward * (WALK_RNG:NextNumber(0.3, 1) * rubble.Speed) + Vector3.yAxis * WALK_RNG:NextNumber(-rubble.Speed, rubble.Speed * 0.4)
		spawnChunk(position, rubble.SizeRange, velocity)
	end
	local points = math.max(collapse.Dust.Points, 0)
	for index = 1, points do
		local alpha = if points > 1 then (index - 1) / (points - 1) else 0.5
		local position = ringPoint(center, forward, right, span[1] + (span[2] - span[1]) * alpha, (innerRadius + outerRadius) * 0.5)
		spawnDust(position)
	end
end

local function holeScaleAt(elapsed: number, rumbleAt: number, collapseAt: number, crackScale: number, holeScale: number): number
	if elapsed < rumbleAt then
		return 1
	end
	if elapsed < collapseAt then
		return 1 + (crackScale - 1) * smoothstep((elapsed - rumbleAt) / math.max(collapseAt - rumbleAt, PIVOT_EPSILON))
	end
	local grow = math.clamp((elapsed - collapseAt) / math.max(Config.Cutscene.Collapse.GrowSeconds, PIVOT_EPSILON), 0, 1)
	return crackScale + (holeScale - crackScale) * (1 - (1 - grow) ^ 3)
end

local function shakeAt(elapsed: number, rumbleAt: number, collapseAt: number): number
	local collapse = Config.Cutscene.Collapse
	if elapsed < rumbleAt then
		return 0
	end
	if elapsed < collapseAt then
		return collapse.RumbleShakeDegrees * smoothstep((elapsed - rumbleAt) / math.max(collapseAt - rumbleAt, PIVOT_EPSILON))
	end
	return collapse.ShakeDegrees * (1 - smoothstep((elapsed - collapseAt) / math.max(collapse.ShakeDecaySeconds, PIVOT_EPSILON)))
end

local function shakeRotation(time: number): CFrame
	if cameraShake <= 0 then
		return CFrame.identity
	end
	local phase = time * Config.Cutscene.Collapse.ShakeSpeed
	local amount = math.rad(cameraShake) * 2
	return CFrame.Angles(
		math.noise(phase, SHAKE_SEEDS[1]) * amount,
		math.noise(phase, SHAKE_SEEDS[2]) * amount,
		math.noise(phase, SHAKE_SEEDS[3]) * amount * 0.5
	)
end

local function localOffset(values: { number }, forward: Vector3, right: Vector3): Vector3
	return forward * values[1] + right * values[2] + Vector3.yAxis * values[3]
end

local function shotAt(shots: { Shot }, progress: number): (Shot, number)
	local index = 1
	for i, shot in shots do
		if progress >= shot.startAt then
			index = i
		end
	end
	local shot = shots[index]
	local nextStart = if shots[index + 1] then shots[index + 1].startAt else 1
	local span = math.max(nextStart - shot.startAt, 0.001)
	return shot, math.clamp((progress - shot.startAt) / span, 0, 1)
end

local function sway(time: number, forward: Vector3, right: Vector3): Vector3
	local amount = Config.Cutscene.SwayAmount
	return right * (math.sin(time * SWAY_SPEED) * amount)
		+ Vector3.yAxis * (math.sin(time * SWAY_SPEED * 1.37 + 1.3) * amount * 0.7)
		+ forward * (math.sin(time * SWAY_SPEED * 0.71 + 2.1) * amount * 0.4)
end

local function frameShot(shot: Shot, shotAlpha: number, anchor: Vector3, focusOrigin: Vector3, forward: Vector3, right: Vector3, dt: number, time: number)
	local rig = cameraRig
	if not rig then
		rig = { position = anchor, focus = focusOrigin, shot = nil }
		cameraRig = rig
	end
	local cut = shot ~= rig.shot
	rig.shot = shot
	local offset = localOffset(shot.from, forward, right):Lerp(localOffset(shot.to, forward, right), smoothstep(shotAlpha))
	local desired = anchor + offset + sway(time, forward, right)
	local desiredFocus = focusOrigin + localOffset(shot.focus, forward, right)
	if cut then
		rig.position = desired
		rig.focus = desiredFocus
		currentFov = shot.fov
	else
		local blend = 1 - math.exp(-shot.smoothing * dt)
		rig.position = rig.position:Lerp(desired, blend)
		rig.focus = rig.focus:Lerp(desiredFocus, blend)
		local fovBlend = 1 - math.exp(-FOV_SMOOTHING * dt)
		local fov = currentFov or shot.fov
		currentFov = fov + (shot.fov - fov) * fovBlend
	end
	currentCFrame = CFrame.lookAt(rig.position, rig.focus) * shakeRotation(time)
end

local function localizeWalker(walker: Walker)
	local source = walker.rig
	if walker.isLocal or walker.dropped or not source.Parent then
		return
	end
	local rig = source:Clone()
	if not rig then
		return
	end
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	rig.Parent = source.Parent
	source.Parent = nil
	walker.rig = rig
	walker.isLocal = true
	local rootPart = rig.PrimaryPart or rig:FindFirstChild("HumanoidRootPart")
	walker.rootPart = if rootPart and rootPart:IsA("BasePart") then rootPart else nil
	local previous = walker.track
	walker.track = nil
	if not previous then
		return
	end
	local timePosition = previous.TimePosition
	local speed = previous.Speed
	previous:Stop(0)
	local track = loadWalkTrack(rig, walker.slot)
	if track then
		track:Play(0)
		track.TimePosition = timePosition
		track:AdjustSpeed(speed)
		walker.track = track
	end
end

local function ragdollWalker(walker: Walker, forward: Vector3, right: Vector3)
	if walker.dropped then
		return
	end
	localizeWalker(walker)
	walker.dropped = true
	if walker.track then
		walker.track:Stop(0)
		walker.track = nil
	end
	local rig = walker.rig
	if not walker.isLocal or not rig.PrimaryPart or not rig:FindFirstChild("UpperTorso") then
		return
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.EvaluateStateMachine = false
	end
	for _, constraint in rig:GetDescendants() do
		local isJoint = constraint:IsA("AnimationConstraint") and constraint.Name ~= ROOT_JOINT_NAME
		if isJoint or constraint:IsA("BallSocketConstraint") then
			constraint.Enabled = false
		end
	end
	if humanoid then
		local ok, err = pcall(WRagdoll.TurnRagdoll, WRagdoll, humanoid)
		if not ok then
			warn(("CutsceneController: ragdoll failed for %s: %s"):format(rig.Name, tostring(err)))
			return
		end
	end
	local fall = Config.Cutscene.Fall
	local torsoGravityScale = math.clamp(fall.TorsoGravityScale, 0, 1)
	local limbGravityScale = math.clamp(fall.LimbGravityScale, 0, 1)
	local velocity = forward * fall.TossSpeed
		+ Vector3.yAxis * fall.TossUp
		+ right * WALK_RNG:NextNumber(-fall.Spread, fall.Spread)
	local spin = -right * fall.TumbleSpeed + forward * (WALK_RNG:NextNumber(-0.3, 0.3) * fall.TumbleSpeed)
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
			local isTorso = TORSO_PARTS[part.Name] == true
			if isTorso then
				part.AssemblyLinearVelocity = velocity
				part.AssemblyAngularVelocity = spin
			else
				part.AssemblyLinearVelocity = velocity * 0.5 + WALK_RNG:NextUnitVector() * fall.LimbScatter
				part.AssemblyAngularVelocity = spin + WALK_RNG:NextUnitVector() * fall.LimbSpin
			end
			local scale = if isTorso then torsoGravityScale else limbGravityScale
			if scale < 1 and part.Parent == rig then
				local attachment = Instance.new("Attachment")
				attachment.Name = LIFT_ATTACHMENT_NAME
				attachment.Parent = part
				local lift = Instance.new("VectorForce")
				lift.Attachment0 = attachment
				lift.RelativeTo = Enum.ActuatorRelativeTo.World
				lift.ApplyAtCenterOfMass = true
				lift.Force = Vector3.yAxis * (part:GetMass() * Workspace.Gravity * (1 - scale))
				lift.Parent = part
			end
		end
	end
	local rootPart = rig.PrimaryPart
	if rootPart then
		playFallSounds(rootPart)
	end
end

local function walkToHole(token: number, scene: Scene): (Vector3?, Vector3?)
	local settings = Config.Cutscene
	if #walkers == 0 or not scene.hole then
		return nil, nil
	end
	local hole = scene.hole :: CFrame
	local startCenter = groupCenter(walkers, scene.players.Position)
	local endCenter = Vector3.zero
	for _, walker in walkers do
		endCenter += walker.endCFrame.Position
	end
	endCenter /= #walkers
	local distance = (endCenter - startCenter).Magnitude
	local duration = math.max(distance / math.max(settings.WalkSpeed, 1), 0.5)
	local forward = groupForward
	local right = forward:Cross(Vector3.yAxis).Unit

	local baseAnimationSpeed = settings.WalkSpeed / math.max(settings.WalkAnimationReferenceSpeed, 1)
	local variance = math.clamp(settings.WalkAnimationSpeedVariance, 0, 0.9)
	local fadeRange = settings.WalkAnimationFadeRange
	for _, walker in walkers do
		walker.track = loadWalkTrack(walker.rig, walker.slot)
		if walker.track then
			local track = walker.track
			track:Play(WALK_RNG:NextNumber(fadeRange[1], fadeRange[2]))
			if track.Length > 0 then
				track.TimePosition = WALK_RNG:NextNumber(0, track.Length)
			end
			local rate = 1 + WALK_RNG:NextNumber(-variance, variance)
			walker.animationSpeed = baseAnimationSpeed * rate
			track:AdjustSpeed(walker.animationSpeed * WALK_EASE_LINEAR)
			walker.stepStride = math.max(Config.Cutscene.StepStride / rate, 0.5)
		end
	end

	local shots = settings.Shots :: { Shot }
	cameraRig = {
		position = if currentCFrame then currentCFrame.Position else scene.start.Position,
		focus = startCenter,
		shot = nil,
	}
	local tilt = math.rad(settings.PanDownTiltDegrees)
	local craneFrom = (scene.start * CFrame.Angles(tilt, 0, 0)) + Vector3.new(0, settings.PanDownLift, 0)
	local craneTo = scene.start * CFrame.new(0, 0, -settings.PanDownPushIn)
	local craneSeconds = math.max(settings.PanDownSeconds, 0)
	local lastFrame = os.clock()
	local startTime = os.clock()
	while not finished and sequenceToken == token do
		local now = os.clock()
		local dt = now - lastFrame
		lastFrame = now
		local elapsed = now - startTime
		local progress = math.clamp(elapsed / duration, 0, 1)
		local alpha = walkEase(progress)
		moveWalkers(alpha, dt)
		local center = groupCenter(walkers, startCenter:Lerp(endCenter, alpha))

		if elapsed < craneSeconds then
			currentCFrame = craneFrom:Lerp(craneTo, smoothstep(elapsed / craneSeconds))
			currentFov = settings.FieldOfView
			RunService.RenderStepped:Wait()
			continue
		end

		local shot, shotAlpha = shotAt(shots, progress)
		local anchor = if shot.anchor == "hole" then Vector3.new(hole.Position.X, center.Y, hole.Position.Z) else center
		frameShot(shot, shotAlpha, anchor, center, forward, right, dt, now - startTime)
		if progress >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	return forward, right
end

local function diveIntoHole(token: number, holeGround: Vector3)
	local fall = Config.Cutscene.Fall
	stopAllMusic(Config.Cutscene.Audio.MusicFadeOutSeconds)
	local riseSeconds = math.max(fall.RiseSeconds, 0.1)
	local plungeSeconds = math.max(fall.PlungeSeconds, 0.1)
	local fadeDepth = math.max(fall.FadeDepth, 0.1)
	local from = if currentCFrame then currentCFrame.Position else holeGround + Vector3.yAxis * 10
	local apex = holeGround + Vector3.yAxis * fall.RiseHeight
	local bottom = holeGround - Vector3.yAxis * fall.DiveDepth
	local fallbackFocus = holeGround - Vector3.yAxis * 60
	local startFocus = if cameraRig then cameraRig.focus else holeGround
	local crossSpan = math.max(fall.RiseHeight + fall.DiveDepth, PIVOT_EPSILON)
	local crossTime = riseSeconds + math.sqrt(math.clamp(fall.RiseHeight / crossSpan, 0, 1)) * plungeSeconds
	local boomTime = math.max(crossTime - Config.Cutscene.Audio.BoomLeadSeconds, 0)
	local boomPlayed = false
	local startTime = os.clock()
	while not finished and sequenceToken == token do
		local elapsed = os.clock() - startTime
		local position: Vector3
		local focus: Vector3
		if elapsed < riseSeconds then
			local alpha = smoothstep(elapsed / riseSeconds)
			position = from:Lerp(apex, alpha)
			focus = startFocus:Lerp(holeGround, alpha)
		else
			local alpha = math.clamp((elapsed - riseSeconds) / plungeSeconds, 0, 1)
			position = apex:Lerp(bottom, alpha * alpha)
			focus = holeGround:Lerp(droppedCenter(walkers, fallbackFocus), smoothstep(alpha))
		end
		if (focus - position).Magnitude < 1 then
			focus = position - Vector3.yAxis
		end
		currentCFrame = CFrame.lookAt(position, focus)
		if not boomPlayed and elapsed >= boomTime then
			boomPlayed = true
			playSound(Config.Cutscene.Audio.BoomName)
		end
		setFade((holeGround.Y - position.Y) / fadeDepth)
		if elapsed >= riseSeconds + plungeSeconds then
			break
		end
		RunService.RenderStepped:Wait()
	end
	setFade(1)
end

local function fallIntoHole(token: number, scene: Scene, forward: Vector3, right: Vector3)
	local settings = Config.Cutscene
	local gather = settings.Gather
	local collapse = settings.Collapse
	local fall = settings.Fall
	stopMusic(settings.Audio.CutsceneMusicName, settings.Audio.CutsceneMusicFadeOutSeconds)
	for _, walker in walkers do
		localizeWalker(walker)
	end
	local hole = scene.hole :: CFrame
	local groundY = walkers[1].endCFrame.Position.Y
	local holeGround = Vector3.new(hole.Position.X, groundY, hole.Position.Z)

	local entrySpeed = math.max(settings.WalkSpeed * WALK_EASE_LINEAR, 0.1)
	local creepSpeed = math.max(gather.CreepSpeed, 0)
	local distance = math.max(gather.ApproachDistance, 0)
	local approachSeconds = 2 * distance / (entrySpeed + creepSpeed)
	local collapseAt = approachSeconds + math.max(collapse.Delay, 0)
	local rumbleAt = math.max(collapseAt - math.max(collapse.RumbleLeadSeconds, 0), 0)
	local lastDrop = collapseAt
	local swallowRadius = 0
	local spanLow, spanHigh = 0, 0
	for _, walker in walkers do
		walker.dropAt = collapseAt
			+ math.abs(walker.offset) * collapse.CascadeStep
			+ (walker.rank - 1) * collapse.RankDelay
			+ WALK_RNG:NextNumber(0, math.max(collapse.Jitter, 0))
		lastDrop = math.max(lastDrop, walker.dropAt)
		local offset = walker.brinkCFrame.Position - holeGround
		local flat = Vector3.new(offset.X, 0, offset.Z)
		swallowRadius = math.max(swallowRadius, flat.Magnitude)
		local angle = math.atan2(flat:Dot(right), flat:Dot(-forward))
		spanLow = math.min(spanLow, angle)
		spanHigh = math.max(spanHigh, angle)
	end
	local edgeRadius = math.max(collapse.EdgeRadius, 0.1)
	local holeScale = math.clamp((swallowRadius + collapse.Swallow) / edgeRadius, 1, math.max(collapse.MaxHoleScale, 1))
	local crackScale = math.clamp(collapse.CrackScale, 1, holeScale)
	local margin = math.rad(collapse.Rubble.SpanMarginDegrees)
	local span = { spanLow - margin, spanHigh + margin }
	local pebbleTimes: { number } = {}
	for _ = 1, math.max(collapse.Pebbles.Count, 0) do
		table.insert(pebbleTimes, WALK_RNG:NextNumber(rumbleAt, collapseAt))
	end
	table.sort(pebbleTimes)
	local nextPebble = 1
	local rumbled = false
	local collapsed = false

	local shots = fall.Shots :: { Shot }
	local total = lastDrop + fall.DiveDelay
	local lastFrame = os.clock()
	local startTime = lastFrame
	while not finished and sequenceToken == token do
		local now = os.clock()
		local dt = now - lastFrame
		lastFrame = now
		local elapsed = now - startTime
		local walked = if elapsed < approachSeconds
			then entrySpeed * elapsed + (creepSpeed - entrySpeed) * elapsed * elapsed / (2 * approachSeconds)
			else distance + creepSpeed * (elapsed - approachSeconds)
		for _, walker in walkers do
			if walker.dropped or not walker.rig.Parent then
				continue
			end
			local heading = walker.endCFrame.LookVector
			local inward = walker.brinkCFrame.LookVector
			local position = if walked <= distance
				then walker.endCFrame.Position + heading * walked
				else walker.brinkCFrame.Position + inward * (walked - distance)
			local turn = if distance > 0 then smoothstep(walked / distance) else 1
			local look = blendDirection(heading, inward, turn)
			walker.rig:PivotTo(CFrame.lookAt(position, position + look))
			stepWalker(walker, position, dt)
			if elapsed >= walker.dropAt then
				ragdollWalker(walker, inward, inward:Cross(Vector3.yAxis).Unit)
			end
		end
		if not rumbled and elapsed >= rumbleAt then
			rumbled = true
			playOptionalSound(settings.Audio.RumbleName)
		end
		while nextPebble <= #pebbleTimes and elapsed >= pebbleTimes[nextPebble] do
			nextPebble += 1
			spawnPebble(holeGround, forward, right, span, edgeRadius, crackScale)
		end
		if not collapsed and elapsed >= collapseAt then
			collapsed = true
			spawnCollapse(holeGround, forward, right, span, edgeRadius, edgeRadius * holeScale)
		end
		setHoleScale(holeScaleAt(elapsed, rumbleAt, collapseAt, crackScale, holeScale))
		cameraShake = shakeAt(elapsed, rumbleAt, collapseAt)
		local shot, shotAlpha = shotAt(shots, math.clamp(elapsed / math.max(total, PIVOT_EPSILON), 0, 1))
		frameShot(shot, shotAlpha, holeGround, holeGround, forward, right, dt, now - startTime)
		if elapsed >= total then
			break
		end
		RunService.RenderStepped:Wait()
	end
	cameraShake = 0
	stopWalkers(walkers)
	if finished or sequenceToken ~= token then
		return
	end
	diveIntoHole(token, holeGround)
end

local function runSequence(scene: Scene)
	sequenceToken += 1
	local token = sequenceToken
	local forward, right = walkToHole(token, scene)
	if finished or sequenceToken ~= token then
		return
	end
	if forward and right and scene.hole and #walkers > 0 then
		fallIntoHole(token, scene, forward, right)
	else
		task.wait(Config.Cutscene.HoldSeconds)
	end
	if sequenceToken == token then
		CutsceneController.finish()
	end
end

local function findVotesLabel(button: Instance): TextLabel?
	local fallback: TextLabel? = nil
	for _, descendant in button:GetDescendants() do
		if descendant:IsA("TextLabel") then
			local text = descendant.Text
			if text:lower():find("vote") then
				return descendant
			end
			if not fallback and text:match(SKIP_VOTES_PATTERN) then
				fallback = descendant
			end
		end
	end
	return fallback
end

local function applySkipState()
	local state = skipState
	local target = skipLabel
	if state and target then
		target.Text = SKIP_VOTES_TEXT:format(state.votes, state.total)
	end
end

local function onSkipState(state: Blink.CutsceneSkipData)
	skipState = state
	applySkipState()
	if state.complete and isStarted then
		CutsceneController.finish()
	end
end

local function resolveGui(playerGui: PlayerGui): ScreenGui?
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	for _, container in { ReplicatedFirst, StarterGui } do
		local template = container:FindFirstChild(GUI_NAME)
		if template and template:IsA("ScreenGui") then
			local clone = template:Clone()
			clone.Parent = playerGui
			return clone
		end
	end
	return nil
end

local function showGui(playerGui: PlayerGui)
	createFade(playerGui)
	local screen = resolveGui(playerGui)
	gui = screen
	if not screen then
		return
	end
	screen.ResetOnSpawn = false
	screen.Enabled = true
	local skip = screen:FindFirstChild(SKIP_BUTTON_NAME, true)
	if skip and skip:IsA("GuiButton") then
		skipLabel = findVotesLabel(skip)
		applySkipState()
		table.insert(connections, skip.Activated:Connect(function()
			Blink.CutsceneSkipVote.Fire()
		end))
	end
end

local function waitForArrival(player: Player)
	if player:GetAttribute(ARRIVAL_COMPLETE_ATTRIBUTE) then
		return
	end
	local deadline = os.clock() + Config.Party.ArrivalTimeoutSeconds + Config.Party.MinLoadingSeconds + ARRIVAL_WAIT_MARGIN
	while not player:GetAttribute(ARRIVAL_COMPLETE_ATTRIBUTE) and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function playSplashOnImpact(character: Model)
	local audio = Config.Cutscene.Audio
	local touches: { RBXScriptConnection } = {}
	local fired = false
	local function onTouched(hit: BasePart)
		if fired or hit:IsDescendantOf(character) then
			return
		end
		fired = true
		for _, touch in touches do
			touch:Disconnect()
		end
		table.clear(touches)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			playSoundAt(audio.SplashName, root, audio.SplashVolumeScale, nil)
		else
			playSound(audio.SplashName)
		end
	end
	for _, name in IMPACT_PART_NAMES do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local touch = part.Touched:Connect(onTouched)
			table.insert(touches, touch)
			table.insert(connections, touch)
		end
	end
end

local function tweenFade(transparency: number, seconds: number)
	local frame = fadeFrame
	if not frame then
		return
	end
	if seconds <= 0 then
		frame.BackgroundTransparency = transparency
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(frame, info, { BackgroundTransparency = transparency })
	tween:Play()
	tween.Completed:Wait()
end

local function wakeBlur()
	local camera = Workspace.CurrentCamera
	local settings = Config.Cutscene.Landing
	if not camera or settings.WakeBlur <= 0 then
		return
	end
	local blur = Instance.new("BlurEffect")
	blur.Name = WAKE_BLUR_NAME
	blur.Size = settings.WakeBlur
	blur.Parent = camera
	local info = TweenInfo.new(math.max(settings.WakeBlurSeconds, 0.05), Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local tween = TweenService:Create(blur, info, { Size = 0 })
	tween.Completed:Once(function()
		blur:Destroy()
	end)
	tween:Play()
end

local function waitForAttribute(character: Model, predicate: (any) -> boolean, seconds: number): boolean
	local deadline = os.clock() + seconds
	while not released and character.Parent do
		if predicate(character:GetAttribute(RAGDOLL_ATTRIBUTE)) then
			return true
		end
		if os.clock() >= deadline then
			return false
		end
		task.wait(LANDING_POLL)
	end
	return false
end

local function landingLook(root: BasePart): Vector3
	local name = Config.Cutscene.Landing.FaceTargetName
	local target = if name then Workspace:FindFirstChild(name, true) else nil
	local position: Vector3? = nil
	if target and target:IsA("Model") then
		position = target:GetPivot().Position
	elseif target and target:IsA("BasePart") then
		position = target.Position
	end
	if position then
		local flat = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
		if flat.Magnitude > PIVOT_EPSILON then
			return flat.Unit
		end
	end
	if name then
		warn("CutsceneController: Workspace." .. name .. " not found, facing the way the character landed")
	end
	return flatForward(root.CFrame)
end

local function landCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local settings = Config.Cutscene.Landing
	playSound(Config.Cutscene.Audio.SewerSoundName)
	playSplashOnImpact(character)
	local function apply()
		local root = character:FindFirstChild("HumanoidRootPart")
		if character:GetAttribute(RAGDOLL_ATTRIBUTE) then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			if root and root:IsA("BasePart") then
				root.AssemblyAngularVelocity = WALK_RNG:NextUnitVector() * settings.TumbleSpeed
			end
			return
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		if root and root:IsA("BasePart") then
			local position = root.Position + Vector3.yAxis * settings.StandLift
			local look = landingLook(root)
			root.CanCollide = true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			character:PivotTo(CFrame.lookAt(position, position + look))
		end
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		if FirstPersonCameraController.isEnabled() then
			FirstPersonCameraController.snap()
		end
	end
	local connection
	connection = character:GetAttributeChangedSignal(RAGDOLL_ATTRIBUTE):Connect(function()
		apply()
		if not character:GetAttribute(RAGDOLL_ATTRIBUTE) then
			connection:Disconnect()
		end
	end)
	table.insert(connections, connection)
	if character:GetAttribute(RAGDOLL_ATTRIBUTE) then
		apply()
	end

	local hasRagdoll = waitForAttribute(character, function(value)
		return value ~= nil
	end, settings.AttributeWaitSeconds)
	if released or not hasRagdoll or character:GetAttribute(RAGDOLL_ATTRIBUTE) ~= true then
		return
	end

	unbindCamera()
	FirstPersonCameraController.enable()
	tweenFade(1, settings.RevealSeconds)
	task.wait(settings.BlackoutDelay)
	if released then
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		createFade(playerGui)
	end
	tweenFade(0, settings.BlackoutSeconds)

	waitForAttribute(character, function(value)
		return value ~= true
	end, settings.RagdollSeconds + settings.RagdollWaitMargin)
	task.wait(settings.WakeDelay)
	if released then
		return
	end
	FirstPersonCameraController.snap()
	wakeBlur()
	tweenFade(1, settings.WakeFadeSeconds)
end

function CutsceneController.isActive(): boolean
	return isStarted and not released
end

function CutsceneController.release()
	if released then
		return
	end
	released = true
	finished = true
	sequenceToken += 1
	cameraShake = 0
	stopWalkers(walkers)
	clearLocalWalkers(walkers)
	clearEffects()
	setHoleScale(1)
	if gui then
		gui.Enabled = false
	end
	unbindCamera()
	FirstPersonCameraController.enable()
	FirstPersonCameraController.setHudHidden(false)
	setCoreGuiEnabled(true)
	fadeOut()
	stopAllMusic(Config.Cutscene.Audio.MusicFadeOutSeconds)
end

function CutsceneController.finish()
	if finished or released then
		return
	end
	finished = true
	sequenceToken += 1
	stopWalkers(walkers)
	if gui then
		gui.Enabled = false
	end
	Blink.CutsceneFinished.Fire()
	task.spawn(function()
		local player = Players.LocalPlayer
		local deadline = os.clock() + Config.Cutscene.CharacterWaitSeconds
		local landed: Model? = nil
		while not released and os.clock() < deadline do
			local character = player.Character
			if character and character:FindFirstChild("HumanoidRootPart") and character.Parent then
				landed = character
				break
			end
			task.wait(0.1)
		end
		if landed then
			landCharacter(landed)
		end
		CutsceneController.release()
	end)
end

function CutsceneController.start()
	if isStarted then
		return
	end
	isStarted = true
	setCoreGuiEnabled(false)
	FirstPersonCameraController.setHudHidden(true)
	skipDisconnect = Blink.CutsceneSkipState.On(onSkipState)

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

		local target = waitForTarget()
		if not target then
			FirstPersonCameraController.enable()
			player:SetAttribute(PRELOADED_ATTRIBUTE, true)
			return
		end
		bindCamera(target)
		local attributeDeadline = os.clock() + ATTRIBUTE_TIMEOUT
		while os.clock() < attributeDeadline and not (readCFrameAttribute(PLAYERS_CFRAME_ATTRIBUTE) and readCFrameAttribute(HOLE_ATTRIBUTE)) do
			task.wait(CAMERA_PART_POLL)
		end
		local scene = readScene(target.cframe)
		preload(player, scene)
		if scene.hole then
			holePart = findHolePart(scene.hole.Position)
			holeSize = if holePart then holePart.Size else nil
		end
		waitForArrival(player)
		if released then
			return
		end
		walkers = collectWalkers(scene)
		showGui(playerGui)
		playMusic(Config.Cutscene.Audio.MusicName, Config.Cutscene.Audio.MusicFadeInSeconds)
		playMusic(Config.Cutscene.Audio.CutsceneMusicName, Config.Cutscene.Audio.MusicFadeInSeconds)
		runSequence(scene)
	end)
end

function CutsceneController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	if skipDisconnect then
		skipDisconnect()
		skipDisconnect = nil
	end
	skipLabel = nil
	skipState = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	CutsceneController.release()
end

return CutsceneController
