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
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))
local WRagdoll = require(ReplicatedStorage:WaitForChild("WRagdoll"))
local FootstepsController = require(script.Parent.Parent:WaitForChild("FootstepsController"))

local CutsceneController = {}

local CAMERA_PART_NAME = "Cutscene_Camera"
local CAMERA_PART_TIMEOUT = 30
local CAMERA_PART_POLL = 0.25
local CAMERA_BIND = "CutsceneCamera"
local FOV_ATTRIBUTE = "FieldOfView"
local CAMERA_CFRAME_ATTRIBUTE = "CutsceneCameraCFrame"
local CAMERA_FOV_ATTRIBUTE = "CutsceneCameraFov"
local PLAYERS_CFRAME_ATTRIBUTE = "CutscenePlayersCFrame"
local HOLE_ATTRIBUTE = "CutsceneHoleCFrame"
local WALK_END_ATTRIBUTE_PREFIX = "CutsceneWalkEnd"
local PRELOADED_ATTRIBUTE = "CutscenePreloaded"
local PLAYERS_FOLDER_NAME = "Teleport_Players"
local STREAM_TIMEOUT = 8
local GUI_NAME = "Cutscene"
local FADE_GUI_NAME = "CutsceneFade"
local FADE_DISPLAY_ORDER = 1000
local SKIP_BUTTON_NAME = "Cutscene_Skip"
local ARRIVAL_COMPLETE_ATTRIBUTE = "ArrivalComplete"
local ARRIVAL_WAIT_MARGIN = 15
local ATTRIBUTE_TIMEOUT = 5
local MAX_PRELOAD_SAMPLES = 24
local FOV_SMOOTHING = 6
local RIG_PRELOAD_WAIT = 1.5
local SWAY_SPEED = 0.9
local WALK_RNG = Random.new()
local STEP_RAY_LIFT = 2
local STEP_RAY_LENGTH = 12
local FALL_ROLLOFF_MIN = 10
local FALL_ROLLOFF_MAX = 250
local FALL_SOUND_LIFETIME = 8
local ROOT_JOINT_NAME = "Root"
local TORSO_PARTS = { HumanoidRootPart = true, LowerTorso = true, UpperTorso = true }
local LIFT_ATTACHMENT_NAME = "CutsceneLift"
local RAGDOLL_ATTRIBUTE = "Ragdolled"

type CameraTarget = {
	cframe: CFrame,
	fov: number?,
}

type Walker = {
	rig: Model,
	slot: number,
	rootPart: BasePart?,
	startCFrame: CFrame,
	endCFrame: CFrame,
	formationEnd: Vector3,
	track: AnimationTrack?,
	lastPosition: Vector3,
	distanceSinceStep: number,
	stepStride: number,
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
local cameraRig: CameraRig? = nil

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
	return alpha * 0.6 + smoothstep(alpha) * 0.4
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

local function collectWalkers(): { Walker }
	local list: { Walker } = {}
	local folder = Workspace:FindFirstChild(PLAYERS_FOLDER_NAME, true)
	if not folder then
		return list
	end
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { folder }
	stepRaycastParams = raycastParams
	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local index = slotIndex(child)
		if not index then
			continue
		end
		local finish = readCFrameAttribute(WALK_END_ATTRIBUTE_PREFIX .. index)
		if not finish then
			continue
		end
		local startPosition = child:GetPivot().Position
		local forward = flatForward(finish)
		local endPosition = Vector3.new(finish.Position.X, startPosition.Y, finish.Position.Z)
		local travel = (endPosition - startPosition):Dot(forward)
		local rootPart = child.PrimaryPart or child:FindFirstChild("HumanoidRootPart")
		table.insert(list, {
			rig = child,
			slot = index,
			rootPart = if rootPart and rootPart:IsA("BasePart") then rootPart else nil,
			startCFrame = CFrame.lookAt(startPosition, startPosition + forward),
			endCFrame = CFrame.lookAt(endPosition, endPosition + forward),
			formationEnd = startPosition + forward * travel,
			track = nil,
			lastPosition = startPosition,
			distanceSinceStep = 0,
			stepStride = math.max(Config.Cutscene.StepStride, 0.5),
			dropped = false,
		})
	end
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

local function walkerPosition(walker: Walker, alpha: number): Vector3
	local formation = walker.startCFrame.Position:Lerp(walker.formationEnd, alpha)
	local line = walker.startCFrame.Position:Lerp(walker.endCFrame.Position, alpha)
	local mergeStart = math.clamp(Config.Cutscene.LineMergeStart, 0, 0.99)
	local merge = smoothstep((alpha - mergeStart) / (1 - mergeStart))
	return formation:Lerp(line, merge)
end

local function stepWalker(walker: Walker, position: Vector3)
	local delta = position - walker.lastPosition
	walker.lastPosition = position
	walker.distanceSinceStep += Vector3.new(delta.X, 0, delta.Z).Magnitude
	if walker.distanceSinceStep < walker.stepStride then
		return
	end
	walker.distanceSinceStep -= walker.stepStride
	if walker.rootPart then
		FootstepsController.playStepAt(walker.rootPart, floorMaterialAt(position), Config.Cutscene.Audio.FootstepVolumeScale)
	end
end

local function moveWalkers(alpha: number)
	for _, walker in walkers do
		if walker.rig.Parent and not walker.dropped then
			local position = walkerPosition(walker, alpha)
			walker.rig:PivotTo(CFrame.lookAt(position, position + walker.endCFrame.LookVector))
			stepWalker(walker, position)
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

local function clearDroppedWalkers(list: { Walker })
	for _, walker in list do
		if walker.dropped then
			walker.rig:Destroy()
		end
	end
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
	currentCFrame = CFrame.lookAt(rig.position, rig.focus)
end

local function ragdollWalker(walker: Walker, forward: Vector3, right: Vector3)
	walker.dropped = true
	if walker.track then
		walker.track:Stop(0)
		walker.track = nil
	end
	local source = walker.rig
	if not source.PrimaryPart or not source:FindFirstChild("UpperTorso") then
		return
	end
	local rig = source:Clone()
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	rig.Parent = source.Parent
	source.Parent = nil
	walker.rig = rig
	walker.rootPart = rig.PrimaryPart
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
	local forward = flatForward(walkers[1].endCFrame)
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
			track:AdjustSpeed(baseAnimationSpeed * rate)
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
		moveWalkers(alpha)
		local center = groupCenter(walkers, startCenter:Lerp(endCenter, alpha))

		if elapsed < craneSeconds then
			moveWalkers(alpha)
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
		if not boomPlayed and elapsed >= riseSeconds and position.Y <= holeGround.Y + Config.Cutscene.Audio.BoomLeadStuds then
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
	stopMusic(settings.Audio.CutsceneMusicName, settings.Audio.CutsceneMusicFadeOutSeconds)
	local fall = settings.Fall
	local hole = scene.hole :: CFrame
	local groundY = walkers[1].endCFrame.Position.Y
	local holeGround = Vector3.new(hole.Position.X, groundY, hole.Position.Z)
	local speed = math.max(settings.WalkSpeed, 1)
	local travels: { [Walker]: number } = {}
	local duration = 0.1
	for _, walker in walkers do
		local travel = math.max((holeGround - walker.endCFrame.Position):Dot(forward) - fall.DropDistance, 0)
		travels[walker] = travel
		duration = math.max(duration, travel / speed)
	end
	local shots = fall.Shots :: { Shot }
	local total = duration + fall.DiveDelay
	local lastFrame = os.clock()
	local startTime = os.clock()
	while not finished and sequenceToken == token do
		local now = os.clock()
		local dt = now - lastFrame
		lastFrame = now
		local elapsed = now - startTime
		local walked = elapsed * speed
		for _, walker in walkers do
			if walker.dropped or not walker.rig.Parent then
				continue
			end
			local travel = travels[walker]
			local position = walker.endCFrame.Position + forward * math.min(walked, travel)
			walker.rig:PivotTo(CFrame.lookAt(position, position + forward))
			stepWalker(walker, position)
			if walked >= travel then
				ragdollWalker(walker, forward, right)
			end
		end
		local progress = math.clamp(elapsed / duration, 0, 1)
		local shot, shotAlpha = shotAt(shots, progress)
		frameShot(shot, shotAlpha, holeGround, holeGround, forward, right, dt, now - startTime)
		if elapsed >= total then
			break
		end
		RunService.RenderStepped:Wait()
	end
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
		table.insert(connections, skip.Activated:Connect(function()
			CutsceneController.finish()
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

local function landCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local settings = Config.Cutscene.Landing
	playSound(Config.Cutscene.Audio.SewerSoundName)
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
			local look = flatForward(root.CFrame)
			root.CanCollide = true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			character:PivotTo(CFrame.lookAt(position, position + look))
		end
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
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
	stopWalkers(walkers)
	clearDroppedWalkers(walkers)
	if gui then
		gui.Enabled = false
	end
	unbindCamera()
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
		waitForArrival(player)
		if released then
			return
		end
		walkers = collectWalkers()
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
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	CutsceneController.release()
end

return CutsceneController
