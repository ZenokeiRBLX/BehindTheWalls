local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))

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
local SKIP_BUTTON_NAME = "Cutscene_Skip"
local ARRIVAL_COMPLETE_ATTRIBUTE = "ArrivalComplete"
local ARRIVAL_WAIT_MARGIN = 15
local ATTRIBUTE_TIMEOUT = 5
local MAX_PRELOAD_SAMPLES = 24
local FOV_SMOOTHING = 6
local RIG_PRELOAD_WAIT = 1.5
local SWAY_SPEED = 0.9

type CameraTarget = {
	cframe: CFrame,
	fov: number?,
}

type Walker = {
	rig: Model,
	startCFrame: CFrame,
	endCFrame: CFrame,
	formationEnd: Vector3,
	track: AnimationTrack?,
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
local currentCFrame: CFrame? = nil
local currentFov: number? = nil
local sequenceToken = 0
local walkers: { Walker } = {}

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

	local walkAnimation = Instance.new("Animation")
	walkAnimation.AnimationId = Config.Cutscene.WalkAnimationId
	local assets: { Instance } = { walkAnimation }
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
	walkAnimation:Destroy()
	player:SetAttribute(PRELOADED_ATTRIBUTE, true)
end

local function loadWalkTrack(rig: Model): AnimationTrack?
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
	animation.AnimationId = Config.Cutscene.WalkAnimationId
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

local function collectWalkers(): { Walker }
	local list: { Walker } = {}
	local folder = Workspace:FindFirstChild(PLAYERS_FOLDER_NAME, true)
	if not folder then
		return list
	end
	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local index = slotIndex(child)
		local finish = if index then readCFrameAttribute(WALK_END_ATTRIBUTE_PREFIX .. index) else nil
		if not finish then
			continue
		end
		local startPosition = child:GetPivot().Position
		local forward = flatForward(finish)
		local endPosition = Vector3.new(finish.Position.X, startPosition.Y, finish.Position.Z)
		local travel = (endPosition - startPosition):Dot(forward)
		table.insert(list, {
			rig = child,
			startCFrame = CFrame.lookAt(startPosition, startPosition + forward),
			endCFrame = CFrame.lookAt(endPosition, endPosition + forward),
			formationEnd = startPosition + forward * travel,
			track = nil,
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

local function moveWalkers(alpha: number)
	for _, walker in walkers do
		if walker.rig.Parent then
			local position = walkerPosition(walker, alpha)
			walker.rig:PivotTo(CFrame.lookAt(position, position + walker.endCFrame.LookVector))
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

local function walkToHole(token: number, scene: Scene)
	local settings = Config.Cutscene
	if #walkers == 0 or not scene.hole then
		return
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

	for _, walker in walkers do
		walker.track = loadWalkTrack(walker.rig)
		if walker.track then
			walker.track:Play(0.3)
			walker.track:AdjustSpeed(settings.WalkSpeed / math.max(settings.WalkAnimationReferenceSpeed, 1))
		end
	end

	local shots = settings.Shots :: { Shot }
	local activeShot: Shot? = nil
	local cameraPosition = if currentCFrame then currentCFrame.Position else scene.start.Position
	local focusPosition = startCenter
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
		local cut = shot ~= activeShot
		activeShot = shot

		local anchor = if shot.anchor == "hole" then Vector3.new(hole.Position.X, center.Y, hole.Position.Z) else center
		local offset = localOffset(shot.from, forward, right):Lerp(localOffset(shot.to, forward, right), smoothstep(shotAlpha))
		local desired = anchor + offset + sway(now - startTime, forward, right)
		local desiredFocus = center + localOffset(shot.focus, forward, right)
		if cut then
			cameraPosition = desired
			focusPosition = desiredFocus
			currentFov = shot.fov
		else
			local blend = 1 - math.exp(-shot.smoothing * dt)
			cameraPosition = cameraPosition:Lerp(desired, blend)
			focusPosition = focusPosition:Lerp(desiredFocus, blend)
			local fovBlend = 1 - math.exp(-FOV_SMOOTHING * dt)
			currentFov = (currentFov or shot.fov) + (shot.fov - (currentFov or shot.fov)) * fovBlend
		end
		currentCFrame = CFrame.lookAt(cameraPosition, focusPosition)
		if progress >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	stopWalkers(walkers)
end

local function runSequence(scene: Scene)
	sequenceToken += 1
	local token = sequenceToken
	walkToHole(token, scene)
	if finished or sequenceToken ~= token then
		return
	end
	task.wait(Config.Cutscene.HoldSeconds)
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
	if gui then
		gui.Enabled = false
	end
	unbindCamera()
	setCoreGuiEnabled(true)
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
		while not released and os.clock() < deadline do
			local character = player.Character
			if character and character:FindFirstChild("HumanoidRootPart") and character.Parent then
				break
			end
			task.wait(0.1)
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
