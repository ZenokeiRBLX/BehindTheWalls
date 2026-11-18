local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20261119
local TV_TAG = "MonsterTV"
local FLESH_TAG = "SignalMazeFlesh"
local BACKUP_NAME = "SignalMaze_V10Backup"
local FX_NAME = "MoodFX"

local LIGHTING = {
	ClockTime = 17.9,
	Brightness = 1,
	Ambient = Color3.fromRGB(38, 24, 26),
	OutdoorAmbient = Color3.fromRGB(12, 7, 8),
	ExposureCompensation = 0.1,
	EnvironmentDiffuseScale = 0.05,
	EnvironmentSpecularScale = 0.35,
	ShadowSoftness = 0.35,
}
local HAZE = {
	Density = 0.42,
	Offset = 0,
	Color = Color3.fromRGB(96, 58, 56),
	Decay = Color3.fromRGB(44, 20, 20),
	Glare = 0,
	Haze = 1.4,
}
local BLOOM = { Intensity = 0.9, Size = 32, Threshold = 0.92 }
local GRADE = { Brightness = -0.02, Contrast = 0.2, Saturation = -0.24, TintColor = Color3.fromRGB(255, 236, 232) }
local DEPTH = { FarIntensity = 0.18, FocusDistance = 30, InFocusRadius = 40, NearIntensity = 0 }
local WATER = {
	WaterColor = Color3.fromRGB(24, 8, 10),
	WaterReflectance = 0.45,
	WaterTransparency = 0.1,
	WaterWaveSize = 0.03,
	WaterWaveSpeed = 1.4,
}

local CEILING_COLOR = Color3.fromRGB(40, 26, 28)
local FILL = { Enabled = false }

local RED_LIGHT = {
	Color = Color3.fromRGB(255, 108, 86),
	Brightness = { 0.55, 0.8 },
	Range = { 14, 30 },
	Angle = 120,
}
local STATIC_LIGHT = {
	Color = Color3.fromRGB(170, 182, 210),
	Brightness = { 0.55, 0.8 },
	Range = { 12, 24 },
	Angle = 120,
}
local RANGE_PER_STUD = 2.2
local RANGE_BASE = 9
local REFERENCE_WIDTH = 6

local MIST = { LightInfluence = 1, LightEmission = 0, Color = Color3.fromRGB(176, 156, 156), Rate = 0.9 }
local MOTES = { LightInfluence = 1, LightEmission = 0 }

return function()
	assert(game.PlaceId == 126262358232325, "This pass targets Map Creation")
	local root = workspace:FindFirstChild("SignalMaze")
	local version = root and root:GetAttribute("BuildVersion")
	assert(version == 9 or version == 10, "Expected the version 9 or 10 SignalMaze")
	local ceiling = root.Ceiling_RemoveForLayoutView:FindFirstChild("Ceiling")
	assert(ceiling, "Missing the ceiling")

	ChangeHistoryService:SetWaypoint("Before Signal Maze v10 lighting")

	local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
	if not backup then
		assert(version == 9, "Version 10 is applied but its backup is missing")
		backup = Instance.new("Folder")
		backup.Name = BACKUP_NAME
		local lightingCopy = Instance.new("Folder")
		lightingCopy.Name = "Lighting"
		for _, child in Lighting:GetChildren() do
			child:Clone().Parent = lightingCopy
		end
		lightingCopy.Parent = backup
		for name in LIGHTING do
			backup:SetAttribute(name, (Lighting :: any)[name])
		end
		for name in WATER do
			backup:SetAttribute(name, (workspace.Terrain :: any)[name])
		end
		backup:SetAttribute("CeilingColor", ceiling.Color)
		local lights = {}
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Light") then
				local entry = {
					parent = descendant.Parent:GetFullName(),
					class = descendant.ClassName,
					enabled = descendant.Enabled,
					brightness = descendant.Brightness,
					color = { descendant.Color.R, descendant.Color.G, descendant.Color.B },
					range = (descendant :: any).Range,
				}
				if descendant:IsA("SurfaceLight") then
					entry.angle = descendant.Angle
				end
				table.insert(lights, entry)
			end
		end
		backup:SetAttribute("Lights", HttpService:JSONEncode(lights))
		backup.Parent = ServerStorage
	end

	local rng = Random.new(SEED)
	local function r(range: { number }): number
		return range[1] + (range[2] - range[1]) * rng:NextNumber()
	end
	local function apply(target: Instance?, props: { [string]: any })
		if not target then
			return
		end
		for name, value in props do
			(target :: any)[name] = value
		end
	end
	local function sortedByName(list: { Instance }): { Instance }
		table.sort(list, function(a, b)
			return a:GetFullName() < b:GetFullName()
		end)
		return list
	end

	apply(Lighting, LIGHTING)
	apply(Lighting:FindFirstChildOfClass("Atmosphere"), HAZE)
	apply(Lighting:FindFirstChildOfClass("BloomEffect"), BLOOM)
	apply(Lighting:FindFirstChildOfClass("ColorCorrectionEffect"), GRADE)
	apply(Lighting:FindFirstChildOfClass("DepthOfFieldEffect"), DEPTH)
	apply(workspace.Terrain, WATER)
	ceiling.Color = CEILING_COLOR

	local fills = 0
	for _, descendant in root.Ceiling_RemoveForLayoutView:GetDescendants() do
		if descendant:IsA("PointLight") then
			apply(descendant, FILL)
			fills += 1
		end
	end

	local shadowCasters = 0
	for _, part in CollectionService:GetTagged(FLESH_TAG) do
		if part:IsA("BasePart") and part:IsDescendantOf(root) then
			part.CastShadow = true
			shadowCasters += 1
		end
	end

	local red, static = 0, 0
	for _, tv in sortedByName(root.EmbeddedTVs:GetChildren()) do
		local glass = tv:FindFirstChild("BroadcastGlass")
		local gui = glass and glass:FindFirstChild("Signal")
		if not (glass and glass:IsA("BasePart") and gui) then
			continue
		end
		local isRed = gui:FindFirstChild("RedSilhouette") ~= nil
		local spec = if isRed then RED_LIGHT else STATIC_LIGHT
		for _, child in glass:GetChildren() do
			if child:IsA("Light") then
				child:Destroy()
			end
		end
		local width = math.max(glass.Size.X, glass.Size.Y)
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Front
		light.Shadows = false
		light.Color = spec.Color
		light.Angle = spec.Angle
		light.Brightness = r(spec.Brightness) * math.sqrt(width / REFERENCE_WIDTH)
		light.Range = math.clamp(RANGE_BASE + width * RANGE_PER_STUD + rng:NextNumber(-2, 2), spec.Range[1], spec.Range[2])
		light.Parent = glass
		if isRed then
			red += 1
		else
			static += 1
		end
	end

	local fx = root:FindFirstChild(FX_NAME)
	local emitters = 0
	if fx then
		for _, descendant in fx:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				if descendant.Name == "GroundMist" then
					descendant.LightInfluence = MIST.LightInfluence
					descendant.LightEmission = MIST.LightEmission
					descendant.Color = ColorSequence.new(MIST.Color)
					descendant.Rate = MIST.Rate
				elseif descendant.Name == "Motes" then
					descendant.LightInfluence = MOTES.LightInfluence
					descendant.LightEmission = MOTES.LightEmission
				end
				emitters += 1
			end
		end
	end

	local lightCount = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Light") and descendant.Enabled then
			lightCount += 1
		end
	end
	root:SetAttribute("BuildVersion", 10)
	root:SetAttribute("LightSeed", SEED)
	root:SetAttribute("LightCount", lightCount)

	ChangeHistoryService:SetWaypoint("After Signal Maze v10 lighting")

	return {
		redLights = red,
		staticLights = static,
		enabledLights = lightCount,
		fillsDisabled = fills,
		shadowCasters = shadowCasters,
		emitters = emitters,
	}
end
