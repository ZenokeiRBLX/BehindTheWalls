local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local IntroScene = {}

local MOSS_SWAY_SPEED = 0.7
local MOSS_SWAY_ANGLE = math.rad(1.6)
local BEAM_FLICKER_MIN_WAIT = 0.08
local BEAM_FLICKER_MAX_WAIT = 0.35
local BEAM_DROPOUT_CHANCE = 0.18
local FLASH_INTERVAL_MIN = 4
local FLASH_INTERVAL_MAX = 8
local FLASH_PULSES_MIN = 2
local FLASH_PULSES_MAX = 4
local FLASH_BRIGHTNESS = 6
local TWITCH_INTERVAL_MIN = 1.5
local TWITCH_INTERVAL_MAX = 4
local TWITCH_DECAY = 6

local EERIE_AMBIENT = Color3.fromRGB(35, 46, 38)
local EERIE_FOG_COLOR = Color3.fromRGB(8, 12, 9)
local EERIE_FOG_END = 150
local EERIE_TINT = Color3.fromRGB(190, 215, 190)

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
	twitch: CFrame,
}

local isActive = false
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
	colorCorrection.Saturation = -0.35
	colorCorrection.Contrast = 0.12
	colorCorrection.Brightness = -0.03
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
				twitch = CFrame.identity,
			})
			table.insert(restoreFunctions, function()
				bone.Transform = originalTransform
			end)
		end
	end
end

local function joltBones(count: number, strength: number)
	for _ = 1, count do
		local state = boneStates[math.random(1, #boneStates)]
		if state then
			state.twitch = CFrame.Angles(
				(math.random() - 0.5) * 2 * strength,
				(math.random() - 0.5) * 2 * strength,
				(math.random() - 0.5) * 2 * strength
			)
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

		local decay = math.min(deltaTime * TWITCH_DECAY, 1)
		for _, state in boneStates do
			state.twitch = state.twitch:Lerp(CFrame.identity, decay)
			local t = elapsed * state.speed + state.phase
			local drift = CFrame.Angles(
				math.sin(t) * state.amplitude * state.weights.X,
				math.sin(t * 0.83 + 1.3) * state.amplitude * state.weights.Y,
				math.sin(t * 0.67 + 2.6) * state.amplitude * state.weights.Z
			)
			state.bone.Transform = drift * state.twitch
		end
	end)
end

local function startTwitchLoop()
	task.spawn(function()
		while isActive do
			task.wait(TWITCH_INTERVAL_MIN + math.random() * (TWITCH_INTERVAL_MAX - TWITCH_INTERVAL_MIN))
			if not isActive then
				break
			end
			joltBones(math.random(1, 3), math.rad(12))
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

local function startFlashLoop(flashLights: { PointLight })
	for _, light in flashLights do
		local originalBrightness = light.Brightness
		table.insert(restoreFunctions, function()
			light.Brightness = originalBrightness
		end)
	end

	local function setFlash(brightness: number)
		for _, light in flashLights do
			light.Brightness = brightness
		end
	end

	task.spawn(function()
		while isActive do
			task.wait(FLASH_INTERVAL_MIN + math.random() * (FLASH_INTERVAL_MAX - FLASH_INTERVAL_MIN))
			if not isActive then
				break
			end
			local pulses = math.random(FLASH_PULSES_MIN, FLASH_PULSES_MAX)
			for _ = 1, pulses do
				if not isActive then
					break
				end
				joltBones(math.random(5, 10), math.rad(25))
				setFlash(FLASH_BRIGHTNESS)
				if boiledOne then
					boiledOne.Transparency = 0
				end
				task.wait(0.05 + math.random() * 0.08)
				setFlash(0)
				if boiledOne then
					boiledOne.Transparency = 1
				end
				task.wait(0.04 + math.random() * 0.12)
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
		startTwitchLoop()
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
		if #flashLights > 0 then
			startFlashLoop(flashLights)
		end
	end

	startHeartbeat()
end

function IntroScene.finish()
	if not isActive then
		return
	end
	isActive = false

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
