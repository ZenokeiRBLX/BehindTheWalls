local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local IntroScene = {}

local MOSS_SWAY_SPEED = 0.9
local MOSS_SWAY_ANGLE = math.rad(4.5)
local BEAM_FLICKER_MIN_WAIT = 0.08
local BEAM_FLICKER_MAX_WAIT = 0.35
local BEAM_DROPOUT_CHANCE = 0.18
local FLASH_INTERVAL_MIN = 2
local FLASH_INTERVAL_MAX = 4.5
local FLICKER_VOLUME_SCALE = 0.4
local FLASH_PULSES_MIN = 2
local FLASH_PULSES_MAX = 4
local FLASH_BRIGHTNESS = 6
local FLASH_ON_MIN = 0.2
local FLASH_ON_MAX = 0.45
local POSES = {
	{
		{ pattern = "Head", angles = Vector3.new(0, 0, math.rad(35)) },
		{ pattern = "Neck", angles = Vector3.new(0, 0, math.rad(15)) },
		{ pattern = "Jaw", angles = Vector3.new(math.rad(20), 0, 0) },
	},
	{
		{ pattern = "Head", angles = Vector3.new(math.rad(-30), 0, 0) },
		{ pattern = "Neck", angles = Vector3.new(math.rad(-10), 0, 0) },
		{ pattern = "Spine", angles = Vector3.new(math.rad(6), 0, 0) },
	},
	{
		{ pattern = "Spine", angles = Vector3.new(math.rad(-10), 0, 0) },
		{ pattern = "Head", angles = Vector3.new(math.rad(20), math.rad(25), 0) },
		{ pattern = "Arm1", angles = Vector3.new(0, 0, math.rad(18)) },
	},
	{
		{ pattern = "Head", angles = Vector3.new(0, math.rad(-40), 0) },
		{ pattern = "Jaw", angles = Vector3.new(math.rad(40), 0, 0) },
	},
	{
		{ pattern = "Neck", angles = Vector3.new(0, math.rad(30), math.rad(10)) },
		{ pattern = "Hand", angles = Vector3.new(math.rad(-15), 0, 0) },
		{ pattern = "Finger", angles = Vector3.new(math.rad(25), 0, 0) },
	},
}

local EERIE_AMBIENT = Color3.fromRGB(130, 140, 130)
local EERIE_FOG_COLOR = Color3.fromRGB(28, 34, 29)
local EERIE_FOG_END = 600
local EERIE_TINT = Color3.fromRGB(208, 224, 208)

local BONE_AMPLITUDES = {
	{ pattern = "Finger", amplitude = math.rad(7) },
	{ pattern = "Jaw", amplitude = math.rad(9) },
	{ pattern = "Head", amplitude = math.rad(5) },
	{ pattern = "Neck", amplitude = math.rad(4) },
	{ pattern = "Eye", amplitude = math.rad(3) },
	{ pattern = "Arm", amplitude = math.rad(3) },
	{ pattern = "Hand", amplitude = math.rad(4) },
	{ pattern = "Spine", amplitude = math.rad(2) },
}
local DEFAULT_BONE_AMPLITUDE = math.rad(2.5)

type BoneState = {
	bone: Bone,
	amplitude: number,
	phase: number,
	speed: number,
	weights: Vector3,
	pose: CFrame,
}

local isActive = false
local isRevealed = false
local heartbeatConnection: RBXScriptConnection?
local restoreFunctions: { () -> () } = {}

local mossStates: { { part: BasePart, baseCFrame: CFrame, phase: number } } = {}
local boneStates: { BoneState } = {}
local boiledOne: BasePart?

local function getAmplitudeFor(boneName: string): number
	for _, entry in BONE_AMPLITUDES do
		if string.find(boneName, entry.pattern) then
			return entry.amplitude
		end
	end
	return DEFAULT_BONE_AMPLITUDE
end

local function applyEerieLighting()
	local originalAmbient = Lighting.Ambient
	local originalFogColor = Lighting.FogColor
	local originalFogEnd = Lighting.FogEnd
	Lighting.Ambient = EERIE_AMBIENT
	Lighting.FogColor = EERIE_FOG_COLOR
	Lighting.FogEnd = EERIE_FOG_END

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "IntroSceneColorCorrection"
	colorCorrection.Saturation = -0.2
	colorCorrection.Contrast = 0.06
	colorCorrection.Brightness = 0.05
	colorCorrection.TintColor = EERIE_TINT
	colorCorrection.Parent = Lighting

	table.insert(restoreFunctions, function()
		Lighting.Ambient = originalAmbient
		Lighting.FogColor = originalFogColor
		Lighting.FogEnd = originalFogEnd
		colorCorrection:Destroy()
	end)
end

local function collectMoss(sewer: Model)
	for _, child in sewer:GetChildren() do
		if child.Name == "MOSS" and child:IsA("BasePart") then
			local baseCFrame = child.CFrame
			table.insert(mossStates, {
				part = child,
				baseCFrame = baseCFrame,
				phase = math.random() * math.pi * 2,
			})
			table.insert(restoreFunctions, function()
				child.CFrame = baseCFrame
			end)
		end
	end
end

local function collectBones(rig: BasePart)
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("Bone") then
			local bone = descendant
			local originalTransform = bone.Transform
			table.insert(boneStates, {
				bone = bone,
				amplitude = getAmplitudeFor(bone.Name),
				phase = math.random() * math.pi * 2,
				speed = 0.4 + math.random() * 0.5,
				weights = Vector3.new(math.random(), math.random(), math.random()).Unit,
				pose = CFrame.identity,
			})
			table.insert(restoreFunctions, function()
				bone.Transform = originalTransform
			end)
		end
	end
end

local lastPoseIndex = 0

local function applyNextPose()
	if #POSES == 0 or #boneStates == 0 then
		return
	end
	local poseIndex = math.random(1, #POSES)
	if #POSES > 1 then
		while poseIndex == lastPoseIndex do
			poseIndex = math.random(1, #POSES)
		end
	end
	lastPoseIndex = poseIndex

	local pose = POSES[poseIndex]
	for _, state in boneStates do
		state.pose = CFrame.identity
		for _, entry in pose do
			if string.find(state.bone.Name, entry.pattern) then
				state.pose = CFrame.Angles(entry.angles.X, entry.angles.Y, entry.angles.Z)
				break
			end
		end
	end
end

local function startHeartbeat()
	local elapsed = 0
	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		for _, moss in mossStates do
			local sway = math.sin(elapsed * MOSS_SWAY_SPEED + moss.phase) * MOSS_SWAY_ANGLE
			local lean = math.sin(elapsed * MOSS_SWAY_SPEED * 0.63 + moss.phase * 1.7) * MOSS_SWAY_ANGLE * 0.5
			moss.part.CFrame = moss.baseCFrame * CFrame.Angles(sway, 0, lean)
		end

		for _, state in boneStates do
			local t = elapsed * state.speed + state.phase
			local drift = CFrame.Angles(
				math.sin(t) * state.amplitude * state.weights.X,
				math.sin(t * 0.83 + 1.3) * state.amplitude * state.weights.Y,
				math.sin(t * 0.67 + 2.6) * state.amplitude * state.weights.Z
			)
			state.bone.Transform = drift * state.pose
		end
	end)
end

local function startBeamFlicker(beam: Beam)
	local originalBrightness = beam.Brightness
	local originalEnabled = beam.Enabled
	table.insert(restoreFunctions, function()
		beam.Brightness = originalBrightness
		beam.Enabled = originalEnabled
	end)

	task.spawn(function()
		while isActive do
			if math.random() < BEAM_DROPOUT_CHANCE then
				beam.Enabled = false
				task.wait(0.05 + math.random() * 0.12)
				beam.Enabled = true
			else
				beam.Brightness = originalBrightness * (0.25 + math.random() * 0.75)
			end
			task.wait(BEAM_FLICKER_MIN_WAIT + math.random() * (BEAM_FLICKER_MAX_WAIT - BEAM_FLICKER_MIN_WAIT))
		end
		beam.Brightness = originalBrightness
		beam.Enabled = originalEnabled
	end)
end

local function startFlashLoop(flashLights: { PointLight }, flashPart: BasePart?)
	for _, light in flashLights do
		local originalBrightness = light.Brightness
		table.insert(restoreFunctions, function()
			light.Brightness = originalBrightness
		end)
	end

	local originalPartColor: Color3?
	if flashPart then
		originalPartColor = flashPart.Color
		flashPart.Color = Color3.new(0, 0, 0)
		table.insert(restoreFunctions, function()
			flashPart.Color = originalPartColor :: Color3
		end)
	end

	local function setFlash(brightness: number)
		for _, light in flashLights do
			light.Brightness = brightness
		end
		if flashPart and originalPartColor then
			flashPart.Color = if brightness > 0 then originalPartColor :: Color3 else Color3.new(0, 0, 0)
		end
	end

	task.spawn(function()
		while isActive do
			task.wait(FLASH_INTERVAL_MIN + math.random() * (FLASH_INTERVAL_MAX - FLASH_INTERVAL_MIN))
			if not isActive then
				break
			end
			local pulses = math.random(FLASH_PULSES_MIN, FLASH_PULSES_MAX)
			local flickerSound = SoundService:FindFirstChild("Light_Flicker")
			if isRevealed and flickerSound and flickerSound:IsA("Sound") then
				flickerSound:Play()
			end
			applyNextPose()
			for _ = 1, pulses do
				if not isActive then
					break
				end
				setFlash(FLASH_BRIGHTNESS)
				if boiledOne then
					boiledOne.Transparency = 0
				end
				task.wait(FLASH_ON_MIN + math.random() * (FLASH_ON_MAX - FLASH_ON_MIN))
				setFlash(0)
				if boiledOne then
					boiledOne.Transparency = 1
				end
				task.wait(0.06 + math.random() * 0.14)
			end
		end
		setFlash(0)
	end)
end

function IntroScene.begin()
	if isActive then
		return
	end
	isActive = true

	local map = Workspace:WaitForChild("Map", 30)
	local sewer = map and map:WaitForChild("Sewer", 30)
	if not sewer then
		return
	end

	applyEerieLighting()

	local originalReverb = SoundService.AmbientReverb
	SoundService.AmbientReverb = Enum.ReverbType.SewerPipe
	table.insert(restoreFunctions, function()
		SoundService.AmbientReverb = originalReverb
	end)

	local flickerSound = SoundService:FindFirstChild("Light_Flicker")
	if flickerSound and flickerSound:IsA("Sound") then
		local originalVolume = flickerSound.Volume
		flickerSound.Volume = originalVolume * FLICKER_VOLUME_SCALE
		table.insert(restoreFunctions, function()
			flickerSound.Volume = originalVolume
		end)
	end

	collectMoss(sewer)

	local boiled = sewer:FindFirstChild("The Boiled One")
	if boiled and boiled:IsA("BasePart") then
		boiledOne = boiled
		local originalTransparency = boiled.Transparency
		boiled.Transparency = 1
		table.insert(restoreFunctions, function()
			boiled.Transparency = originalTransparency
		end)
		collectBones(boiled)
	end

	local sewerLight = sewer:FindFirstChild("SEWERLIGHT")
	local lightPart = sewerLight and sewerLight:FindFirstChild("light1")
	local beam = lightPart and lightPart:FindFirstChild("light")
	if beam and beam:IsA("Beam") then
		startBeamFlicker(beam)
	end

	local flashModel = sewer:FindFirstChild("Flashing_LIGHT")
	if flashModel then
		local flashLights = {}
		for _, descendant in flashModel:GetDescendants() do
			if descendant:IsA("PointLight") then
				table.insert(flashLights, descendant)
			end
		end
		local flashPart = flashModel:FindFirstChild("Light")
		if #flashLights > 0 then
			startFlashLoop(flashLights, if flashPart and flashPart:IsA("BasePart") then flashPart else nil)
		end
	end

	startHeartbeat()
end

function IntroScene.setRevealed()
	if not isActive or isRevealed then
		return
	end
	isRevealed = true

	local ambience = SoundService:FindFirstChild("Sewer_Sound_Effect")
	if ambience and ambience:IsA("Sound") then
		local originalLooped = ambience.Looped
		ambience.Looped = true
		ambience:Play()
		table.insert(restoreFunctions, function()
			ambience:Stop()
			ambience.Looped = originalLooped
		end)
	end
end

function IntroScene.finish()
	if not isActive then
		return
	end
	isActive = false
	isRevealed = false

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	for _, restore in restoreFunctions do
		pcall(restore)
	end
	table.clear(restoreFunctions)
	table.clear(mossStates)
	table.clear(boneStates)
	boiledOne = nil
end

return IntroScene
