local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

local SignalMazeController = {}

local SETTINGS = Config.SignalMaze
local FLESH = SETTINGS.Flesh
local SCREENS = SETTINGS.Screens
local SHADOWS = SETTINGS.Shadows
local AUDIO = SETTINGS.Audio
local TAU = 2 * math.pi
local BASE_BRIGHTNESS_ATTRIBUTE = "SignalBaseBrightness"
local BASE_RANGE_ATTRIBUTE = "SignalBaseRange"
local SOUND_LIFETIME = 10

type BoneState = {
	bone: Bone,
	breathPhase: number,
	pulseDelay: number,
	seed: number,
}

type FleshState = {
	part: BasePart,
	bones: { BoneState },
	active: boolean,
	nextCollectAt: number,
}

type ScreenState = {
	model: Instance,
	glass: BasePart?,
	gui: SurfaceGui?,
	label: ImageLabel?,
	roll: GuiObject?,
	light: Light?,
	frameSize: number,
	grid: number,
	interval: number,
	frame: number,
	nextFrameAt: number,
	nextResolveAt: number,
	baseBrightness: number,
	baseLight: number,
	authoredLight: number,
	authoredRange: number,
	rollStart: number,
	rollSeconds: number,
	rollHeight: number,
	dropUntil: number,
	seed: number,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local fleshStates: { [Instance]: FleshState } = {}
local screenStates: { [Instance]: ScreenState } = {}
local rng = Random.new()
local accumulated = 0
local shadowed: { [Light]: boolean } = {}
local nextShadowAt = 0
local staticSounds: { [ScreenState]: Sound } = {}
local squirmSounds: { [FleshState]: Sound } = {}
local nextAudioAt = 0
local nextSquelchAt = 0
local warnedSounds: { [string]: boolean } = {}

local function findSound(name: string): Sound?
	local sound = SoundService:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		return sound
	end
	if not warnedSounds[name] then
		warnedSounds[name] = true
		warn("SignalMazeController: SoundService." .. name .. " not found")
	end
	return nil
end

local function startLoop(name: string, parent: BasePart, speedRange: { number }, volumeScale: number): Sound?
	local template = findSound(name)
	if not template then
		return nil
	end
	local sound = template:Clone()
	local volume = template.Volume * volumeScale
	sound.Looped = true
	sound.PlaybackSpeed = template.PlaybackSpeed * rng:NextNumber(speedRange[1], speedRange[2])
	sound.Volume = 0
	sound.Parent = parent
	if template.TimeLength > 0 then
		sound.TimePosition = rng:NextNumber(0, template.TimeLength)
	end
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(AUDIO.FadeSeconds), { Volume = volume }):Play()
	return sound
end

local function stopLoop(sound: Sound, instant: boolean?)
	if instant or not sound.Parent then
		sound:Destroy()
		return
	end
	local tween = TweenService:Create(sound, TweenInfo.new(AUDIO.FadeSeconds), { Volume = 0 })
	tween.Completed:Once(function()
		sound:Destroy()
	end)
	tween:Play()
end

local function playOnce(name: string, parent: BasePart, speedRange: { number })
	local template = findSound(name)
	if not template then
		return
	end
	local sound = template:Clone()
	sound.Looped = false
	sound.PlaybackSpeed = template.PlaybackSpeed * rng:NextNumber(speedRange[1], speedRange[2])
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, SOUND_LIFETIME)
end

local function heartbeat(u: number): number
	local first = (u - 0.08) / 0.045
	local second = (u - 0.26) / 0.06
	return math.exp(-first * first) + 0.65 * math.exp(-second * second)
end

local function collectBones(state: FleshState)
	local part = state.part
	table.clear(state.bones)
	for _, child in part:GetChildren() do
		if child:IsA("Bone") then
			local position = part.CFrame:PointToWorldSpace(child.Position)
			table.insert(state.bones, {
				bone = child,
				breathPhase = (position.X + position.Z) / FLESH.WaveLength * TAU + position.Y * 0.04,
				pulseDelay = (position.X + position.Z * 0.7) / FLESH.PulseTravelSpeed,
				seed = rng:NextNumber(0, TAU),
			})
		end
	end
end

local function relaxFlesh(state: FleshState)
	for _, entry in state.bones do
		entry.bone.Transform = CFrame.identity
	end
	state.active = false
end

local function addFlesh(instance: Instance)
	if fleshStates[instance] or not instance:IsA("BasePart") then
		return
	end
	local state: FleshState = { part = instance, bones = {}, active = false, nextCollectAt = 0 }
	collectBones(state)
	fleshStates[instance] = state
end

local function removeFlesh(instance: Instance)
	local state = fleshStates[instance]
	if state then
		relaxFlesh(state)
		local sound = squirmSounds[state]
		if sound then
			squirmSounds[state] = nil
			stopLoop(sound, true)
		end
		fleshStates[instance] = nil
	end
end

local function updateFlesh(state: FleshState, eye: Vector3, now: number)
	local part = state.part
	if (part.Position - eye).Magnitude > FLESH.Radius then
		if state.active then
			relaxFlesh(state)
		end
		return
	end
	if #state.bones == 0 then
		if now >= state.nextCollectAt then
			state.nextCollectAt = now + SCREENS.ResolveSeconds
			collectBones(state)
		end
		return
	end
	state.active = true
	local twist = math.rad(FLESH.TwistDegrees)
	local squirmTime = now / FLESH.SquirmSeconds * TAU
	for _, entry in state.bones do
		local breath = math.sin(now / FLESH.BreathSeconds * TAU - entry.breathPhase)
		local pulse = heartbeat(((now - entry.pulseDelay) / FLESH.PulseSeconds) % 1)
		local squirm = squirmTime + entry.seed
		entry.bone.Transform = CFrame.new(
			FLESH.SquirmAmplitude * math.sin(squirm),
			FLESH.SquirmAmplitude * math.cos(squirm * 0.8),
			FLESH.BreathAmplitude * breath + FLESH.PulseAmplitude * pulse
		) * CFrame.Angles(twist * math.sin(squirm * 1.3), twist * math.cos(squirm * 0.7), 0)
	end
end

local function resolveScreen(state: ScreenState, now: number): boolean
	local glass = state.model:FindFirstChild(SCREENS.GlassName)
	local gui = glass and glass:FindFirstChild(SCREENS.GuiName)
	local red = gui and gui:FindFirstChild(SCREENS.RedName)
	local label = red or (gui and gui:FindFirstChild(SCREENS.StaticName))
	if not (glass and glass:IsA("BasePart") and gui and gui:IsA("SurfaceGui") and label and label:IsA("ImageLabel")) then
		state.nextResolveAt = now + SCREENS.ResolveSeconds
		return false
	end
	local roll = gui:FindFirstChild(SCREENS.RollName)
	local light = glass:FindFirstChildWhichIsA("Light")
	state.glass = glass
	state.gui = gui
	state.label = label
	state.roll = if roll and roll:IsA("GuiObject") then roll else nil
	state.light = light
	state.frameSize = if red then SCREENS.RedFrame else SCREENS.StaticFrame
	state.grid = if red then SCREENS.RedGrid else SCREENS.StaticGrid
	state.interval = 1 / (if red then SCREENS.RedFps else SCREENS.StaticFps)
	state.baseBrightness = gui.Brightness
	state.rollHeight = if state.roll then state.roll.Size.Y.Scale else 0
	if light then
		local brightness = light:GetAttribute(BASE_BRIGHTNESS_ATTRIBUTE)
		local range = light:GetAttribute(BASE_RANGE_ATTRIBUTE)
		if type(brightness) ~= "number" or type(range) ~= "number" then
			brightness = light.Brightness
			range = light.Range
			light:SetAttribute(BASE_BRIGHTNESS_ATTRIBUTE, brightness)
			light:SetAttribute(BASE_RANGE_ATTRIBUTE, range)
		end
		state.authoredLight = brightness
		state.authoredRange = range
		state.baseLight = brightness * SCREENS.LightScale
		light.Brightness = state.baseLight
		light.Range = range * SCREENS.RangeScale
	else
		state.baseLight = 0
	end
	return true
end

local function restoreScreen(state: ScreenState)
	if state.gui then
		state.gui.Brightness = state.baseBrightness
	end
	local light = state.light
	if light then
		light.Brightness = state.authoredLight
		light.Range = state.authoredRange
		if shadowed[light] then
			light.Shadows = false
			shadowed[light] = nil
		end
	end
	local sound = staticSounds[state]
	if sound then
		staticSounds[state] = nil
		stopLoop(sound, true)
	end
end

local function updateShadows(eye: Vector3)
	local candidates = {}
	for _, state in screenStates do
		local glass = state.glass
		local light = state.light
		if glass and light and light.Parent == glass then
			local distance = (glass.Position - eye).Magnitude
			if distance <= SHADOWS.Radius then
				table.insert(candidates, { light = light, distance = distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local wanted: { [Light]: boolean } = {}
	for index = 1, math.min(SHADOWS.Count, #candidates) do
		wanted[candidates[index].light] = true
	end
	for light in shadowed do
		if not wanted[light] then
			light.Shadows = false
			shadowed[light] = nil
		end
	end
	for light in wanted do
		if not shadowed[light] then
			light.Shadows = true
			shadowed[light] = true
		end
	end
end

local function addScreen(instance: Instance)
	if screenStates[instance] then
		return
	end
	screenStates[instance] = {
		model = instance,
		frameSize = SCREENS.StaticFrame,
		grid = SCREENS.StaticGrid,
		interval = 1 / SCREENS.StaticFps,
		frame = 0,
		nextFrameAt = 0,
		nextResolveAt = 0,
		baseBrightness = 1,
		baseLight = 0,
		authoredLight = 0,
		authoredRange = 0,
		rollStart = rng:NextNumber(0, SCREENS.RollSeconds[2]),
		rollSeconds = rng:NextNumber(SCREENS.RollSeconds[1], SCREENS.RollSeconds[2]),
		rollHeight = 0,
		dropUntil = 0,
		seed = rng:NextNumber(0, 1000),
	}
end

local function removeScreen(instance: Instance)
	local state = screenStates[instance]
	if state then
		restoreScreen(state)
		screenStates[instance] = nil
	end
end

local function updateScreen(state: ScreenState, eye: Vector3, now: number, step: number)
	local glass = state.glass
	if glass and not glass:IsDescendantOf(Workspace) then
		state.glass = nil
		glass = nil
	end
	if not glass then
		if now < state.nextResolveAt or not resolveScreen(state, now) then
			return
		end
		glass = state.glass :: BasePart
	end
	if (glass.Position - eye).Magnitude > SCREENS.Radius then
		return
	end
	local gui = state.gui :: SurfaceGui
	local label = state.label :: ImageLabel
	if now >= state.nextFrameAt then
		local count = state.grid * state.grid
		local frame = (state.frame + rng:NextInteger(1, count - 1)) % count
		state.frame = frame
		state.nextFrameAt = now + state.interval
		label.ImageRectOffset = Vector2.new(frame % state.grid, frame // state.grid) * state.frameSize
	end
	local roll = state.roll
	if roll then
		local travel = ((now + state.rollStart) / state.rollSeconds) % 1
		roll.Position = UDim2.fromScale(0, -state.rollHeight + (1 + state.rollHeight) * travel)
	end
	if now >= state.dropUntil and rng:NextNumber() < SCREENS.DropChancePerSecond * step then
		state.dropUntil = now + rng:NextNumber(SCREENS.DropSeconds[1], SCREENS.DropSeconds[2])
		if staticSounds[state] and rng:NextNumber() < AUDIO.BurstChance then
			playOnce(AUDIO.BurstName, glass, AUDIO.StaticSpeedRange)
		end
	end
	local level = 1 - SCREENS.FlickerDepth * (0.5 + math.noise(now * SCREENS.FlickerSpeed, state.seed))
	if now < state.dropUntil then
		level = SCREENS.DropBrightness
	end
	gui.Brightness = state.baseBrightness * level
	if state.light then
		state.light.Brightness = state.baseLight * level
	end
end

type Candidate<T> = {
	state: T,
	distance: number,
}

local function nearestScreens(eye: Vector3): { [ScreenState]: boolean }
	local candidates: { Candidate<ScreenState> } = {}
	for _, state in screenStates do
		local glass = state.glass
		if glass and glass:IsDescendantOf(Workspace) then
			local distance = (glass.Position - eye).Magnitude
			if distance <= AUDIO.StaticRadius then
				table.insert(candidates, { state = state, distance = distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local wanted: { [ScreenState]: boolean } = {}
	for index = 1, math.min(AUDIO.StaticCount, #candidates) do
		wanted[candidates[index].state] = true
	end
	return wanted
end

local function nearestFlesh(eye: Vector3): { [FleshState]: boolean }
	local candidates: { Candidate<FleshState> } = {}
	for _, state in fleshStates do
		if state.part:IsDescendantOf(Workspace) then
			local distance = (state.part.Position - eye).Magnitude
			if distance <= AUDIO.SquirmRadius then
				table.insert(candidates, { state = state, distance = distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local wanted: { [FleshState]: boolean } = {}
	for index = 1, math.min(AUDIO.SquirmCount, #candidates) do
		wanted[candidates[index].state] = true
	end
	return wanted
end

local function refreshLoops(eye: Vector3)
	local screens = nearestScreens(eye)
	for state, sound in staticSounds do
		if not screens[state] or not sound.Parent then
			staticSounds[state] = nil
			stopLoop(sound)
		end
	end
	for state in screens do
		local glass = state.glass
		if not staticSounds[state] and glass then
			local sound = startLoop(AUDIO.StaticName, glass, AUDIO.StaticSpeedRange, AUDIO.StaticVolumeScale)
			if sound then
				staticSounds[state] = sound
			end
		end
	end
	local flesh = nearestFlesh(eye)
	for state, sound in squirmSounds do
		if not flesh[state] or not sound.Parent then
			squirmSounds[state] = nil
			stopLoop(sound)
		end
	end
	for state in flesh do
		if not squirmSounds[state] then
			local sound = startLoop(AUDIO.SquirmName, state.part, AUDIO.SquirmSpeedRange, 1)
			if sound then
				squirmSounds[state] = sound
			end
		end
	end
end

local function squelch(eye: Vector3, now: number)
	if now < nextSquelchAt then
		return
	end
	nextSquelchAt = now + rng:NextNumber(AUDIO.SquelchInterval[1], AUDIO.SquelchInterval[2])
	local names = AUDIO.SquelchNames
	if #names == 0 then
		return
	end
	local options: { BasePart } = {}
	for _, state in fleshStates do
		if state.part:IsDescendantOf(Workspace) and (state.part.Position - eye).Magnitude <= AUDIO.SquelchRadius then
			table.insert(options, state.part)
		end
	end
	if #options > 0 then
		playOnce(names[rng:NextInteger(1, #names)], options[rng:NextInteger(1, #options)], AUDIO.SquelchSpeedRange)
	end
end

local function update(step: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	for _, state in fleshStates do
		updateFlesh(state, eye, now)
	end
	for _, state in screenStates do
		updateScreen(state, eye, now, step)
	end
	if now >= nextShadowAt then
		nextShadowAt = now + SHADOWS.RefreshSeconds
		updateShadows(eye)
	end
	if now >= nextAudioAt then
		nextAudioAt = now + AUDIO.RefreshSeconds
		refreshLoops(eye)
	end
	squelch(eye, now)
end

local function watch(tag: string, add: (Instance) -> (), remove: (Instance) -> ())
	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(add))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(remove))
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
end

function SignalMazeController.start()
	if isStarted then
		return
	end
	isStarted = true
	accumulated = 0
	nextShadowAt = 0
	nextAudioAt = 0
	nextSquelchAt = os.clock() + AUDIO.SquelchInterval[1]
	watch(SETTINGS.FleshTag, addFlesh, removeFlesh)
	watch(SETTINGS.ScreenTag, addScreen, removeScreen)
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		accumulated += dt
		if accumulated < 1 / SETTINGS.UpdateRate then
			return
		end
		local step = accumulated
		accumulated = 0
		update(step)
	end))
end

function SignalMazeController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, state in fleshStates do
		relaxFlesh(state)
	end
	for _, state in screenStates do
		restoreScreen(state)
	end
	for _, sound in squirmSounds do
		stopLoop(sound, true)
	end
	table.clear(squirmSounds)
	table.clear(fleshStates)
	table.clear(screenStates)
	table.clear(shadowed)
end

return SignalMazeController
