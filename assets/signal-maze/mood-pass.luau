local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20261116
local TAG = "MonsterTV"
local BACKUP_NAME = "SignalMaze_V8Backup"
local FX_NAME = "MoodFX"
local GRIME_NAME = "Grime"
local FLESH_VARIANT = "Flesh_WetFolds_V2"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local WATER_TOP = 1.3

local LIGHTING = {
	ClockTime = 14,
	Brightness = 1,
	Ambient = Color3.fromRGB(70, 52, 56),
	OutdoorAmbient = Color3.fromRGB(40, 24, 26),
	ExposureCompensation = 0.4,
	EnvironmentDiffuseScale = 0.25,
	EnvironmentSpecularScale = 1,
}
local HAZE = {
	Density = 0.5,
	Offset = 0,
	Color = Color3.fromRGB(160, 112, 112),
	Decay = Color3.fromRGB(96, 58, 60),
	Glare = 0,
	Haze = 2,
}
local BLOOM = { Intensity = 1.1, Size = 40, Threshold = 0.8 }
local GRADE = { Brightness = 0.02, Contrast = 0.08, Saturation = -0.15, TintColor = Color3.fromRGB(255, 228, 218) }
local DEPTH = { FarIntensity = 0.22, FocusDistance = 40, InFocusRadius = 50, NearIntensity = 0 }
local WATER = {
	WaterColor = Color3.fromRGB(64, 20, 22),
	WaterReflectance = 0.7,
	WaterTransparency = 0.2,
	WaterWaveSize = 0.07,
	WaterWaveSpeed = 2.5,
}

local FLESH_COLOR = Color3.fromRGB(215, 160, 162)
local FLESH_JITTER = 0.08
local FLESH_TILE = 14
local CEILING_COLOR = Color3.fromRGB(52, 34, 36)
local HOUSING_COLOR = Color3.fromRGB(80, 64, 62)
local HOUSING_JITTER = 0.3

local RED_GUI_BRIGHTNESS = 2.4
local STATIC_GUI_BRIGHTNESS = 0.9
local STATIC_COLOR = Color3.fromRGB(214, 210, 208)

local RED_LIGHT = {
	Budget = 96,
	Spacing = 15,
	Color = Color3.fromRGB(255, 96, 80),
	Brightness = { 0.9, 1.3 },
	Range = { 22, 28 },
	Angle = 110,
}
local STATIC_LIGHT = {
	Budget = 18,
	Spacing = 32,
	Color = Color3.fromRGB(180, 186, 200),
	Brightness = { 0.35, 0.5 },
	Range = { 14, 18 },
	Angle = 100,
}
local FILL = { Color = Color3.fromRGB(240, 196, 190), Brightness = 0.8, EntranceBrightness = 0.4, Range = 64 }

local MIST = {
	Color = Color3.fromRGB(150, 118, 118),
	LightInfluence = 0.5,
	Size = { 10, 18 },
	Transparency = { 0.8, 0.83 },
	Lifetime = { 10, 16 },
	Rate = 0.7,
	Speed = { 0.3, 0.8 },
	Height = 2,
	Lift = 1,
}
local MOTES = {
	Color = Color3.fromRGB(255, 214, 205),
	Size = { 0.12, 0.2 },
	Transparency = 0.2,
	Lifetime = { 8, 12 },
	Rate = 2,
	Speed = { 0.15, 0.4 },
	Height = 20,
	Bottom = 2,
}

assert(game.PlaceId == 126262358232325, "This pass targets Map Creation")
local root = workspace:FindFirstChild("SignalMaze")
local version = root and root:GetAttribute("BuildVersion")
assert(version == 7 or version == 8, "Expected the version 7 or 8 SignalMaze")

local ORIGIN = root:GetAttribute("Origin")
local CELL = root:GetAttribute("CellSize")
local N = root:GetAttribute("GridSize")
local HALF = N * CELL / 2
local ceiling = root.Ceiling_RemoveForLayoutView:FindFirstChild("Ceiling")
local fleshVariant = MaterialService:FindFirstChild(FLESH_VARIANT, true)
assert(ceiling and fleshVariant, "Missing the ceiling or the flesh material variant")

ChangeHistoryService:SetWaypoint("Before Signal Maze v8 mood")

local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
if not backup then
	assert(version == 7, "Version 8 is applied but its backup is missing")
	backup = Instance.new("Folder")
	backup.Name = BACKUP_NAME
	local copy = root:Clone()
	for _, descendant in copy:GetDescendants() do
		if descendant:HasTag(TAG) then
			descendant:RemoveTag(TAG)
		end
	end
	copy.Parent = backup
	local lightingCopy = Instance.new("Folder")
	lightingCopy.Name = "Lighting"
	for _, child in Lighting:GetChildren() do
		child:Clone().Parent = lightingCopy
	end
	lightingCopy.Parent = backup
	for name in LIGHTING do
		backup:SetAttribute(name, Lighting[name])
	end
	for name in WATER do
		backup:SetAttribute(name, workspace.Terrain[name])
	end
	backup:SetAttribute("FleshStudsPerTile", fleshVariant.StudsPerTile)
	backup:SetAttribute("CeilingTransparency", ceiling.Transparency)
	backup:SetAttribute("CeilingCastShadow", ceiling.CastShadow)
	backup.Parent = ServerStorage
end

local rng = Random.new(SEED)
local function r(a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end

local function apply(target: Instance, props: { [string]: any })
	for name, value in props do
		(target :: any)[name] = value
	end
end

local function shade(color: Color3, amount: number): Color3
	local f = 1 - amount * rng:NextNumber()
	return Color3.new(color.R * f, color.G * f, color.B * f)
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
fleshVariant.StudsPerTile = FLESH_TILE
ceiling.Transparency = 0
ceiling.CastShadow = true
ceiling.Color = CEILING_COLOR

local fleshParts = {}
for _, group in { root.FleshWalls, root.FleshColumns, root.Landmarks } do
	for _, descendant in group:GetDescendants() do
		if descendant:IsA("MeshPart") and descendant.Name == "Wall" then
			table.insert(fleshParts, descendant)
		end
	end
end
for _, part in sortedByName(fleshParts) do
	part.Color = shade(FLESH_COLOR, FLESH_JITTER)
end

local fills = 0
for _, descendant in root.Ceiling_RemoveForLayoutView:GetDescendants() do
	if descendant:IsA("PointLight") then
		descendant.Color = FILL.Color
		descendant.Range = FILL.Range
		descendant.Brightness = if descendant.Parent.Name == "RoomFill_EntranceHall"
			then FILL.EntranceBrightness
			else FILL.Brightness
		fills += 1
	end
end

local tvs = sortedByName(root.EmbeddedTVs:GetChildren())
local redScreens = {}
local staticScreens = {}
local grimed = 0
for _, tv in tvs do
	for _, descendant in tv:GetDescendants() do
		if descendant:IsA("Light") then
			descendant:Destroy()
		end
	end
	local housing = tv:FindFirstChild("Housing", true)
	if housing and housing:IsA("MeshPart") then
		local grime = housing:FindFirstChild(GRIME_NAME) or Instance.new("SurfaceAppearance")
		grime.Name = GRIME_NAME
		grime.ColorMap = housing.TextureID
		grime.Color = shade(HOUSING_COLOR, HOUSING_JITTER)
		grime.Parent = housing
		grimed += 1
	end
	local red = tv:FindFirstChild("RedSilhouette", true)
	local static = tv:FindFirstChild("Static", true)
	if red then
		red.Parent.Brightness = RED_GUI_BRIGHTNESS
		table.insert(redScreens, red.Parent.Parent)
	elseif static then
		static.ImageColor3 = STATIC_COLOR
		static.Parent.Brightness = STATIC_GUI_BRIGHTNESS
		table.insert(staticScreens, static.Parent.Parent)
	end
end

local function light(screens: { BasePart }, spec): number
	local order = table.clone(screens)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local chosen = {}
	for _, screen in order do
		if #chosen >= spec.Budget then
			break
		end
		local ok = true
		for _, other in chosen do
			if (other.Position - screen.Position).Magnitude < spec.Spacing then
				ok = false
				break
			end
		end
		if ok then
			table.insert(chosen, screen)
			local surface = Instance.new("SurfaceLight")
			surface.Face = Enum.NormalId.Front
			surface.Shadows = false
			surface.Color = spec.Color
			surface.Angle = spec.Angle
			surface.Brightness = r(spec.Brightness[1], spec.Brightness[2])
			surface.Range = r(spec.Range[1], spec.Range[2])
			surface.Parent = screen
		end
	end
	return #chosen
end
local redLights = light(redScreens, RED_LIGHT)
local staticLights = light(staticScreens, STATIC_LIGHT)

local existing = root:FindFirstChild(FX_NAME)
if existing then
	existing:Destroy()
end
local fx = Instance.new("Model")
fx.Name = FX_NAME

local function volume(name: string, center: Vector3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = CFrame.new(center)
	part.Parent = fx
	return part
end

local function fade(peak: number, hold: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, peak),
		NumberSequenceKeypoint.new(0.75, hold),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function emitter(name: string, spec, parent: BasePart): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Name = name
	particles.Texture = SMOKE_TEXTURE
	particles.Color = ColorSequence.new(spec.Color)
	particles.Size = NumberSequence.new(spec.Size[1], spec.Size[2])
	particles.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
	particles.Rate = spec.Rate
	particles.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Acceleration = Vector3.new(0, -0.02, 0)
	particles.Shape = Enum.ParticleEmitterShape.Box
	particles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	particles.Parent = parent
	return particles
end

local emitters = 0
for row = 1, N do
	for column = 1, N do
		local x = ORIGIN.X - HALF + (column - 0.5) * CELL
		local z = ORIGIN.Z - HALF + (row - 0.5) * CELL
		local mistVolume = volume(
			string.format("Mist_%02d_%02d", row, column),
			Vector3.new(x, WATER_TOP + MIST.Lift + MIST.Height / 2, z),
			Vector3.new(CELL - 2, MIST.Height, CELL - 2)
		)
		local mist = emitter("GroundMist", MIST, mistVolume)
		mist.LightEmission = 0
		mist.LightInfluence = MIST.LightInfluence
		mist.Transparency = fade(MIST.Transparency[1], MIST.Transparency[2])
		mist.Drag = 0.15
		mist.Rotation = NumberRange.new(0, 360)
		mist.RotSpeed = NumberRange.new(-6, 6)
		emitters += 1
		if (row + column) % 2 == 0 then
			local moteVolume = volume(
				string.format("Motes_%02d_%02d", row, column),
				Vector3.new(x, WATER_TOP + MOTES.Bottom + MOTES.Height / 2, z),
				Vector3.new(CELL - 2, MOTES.Height, CELL - 2)
			)
			local motes = emitter("Motes", MOTES, moteVolume)
			motes.LightEmission = 1
			motes.LightInfluence = 0.3
			motes.Transparency = fade(MOTES.Transparency, MOTES.Transparency)
			motes.Drag = 0.3
			emitters += 1
		end
	end
end
fx.Parent = root

local lights = 0
local parts = 0
for _, descendant in root:GetDescendants() do
	if descendant:IsA("Light") then
		lights += 1
	elseif descendant:IsA("BasePart") then
		parts += 1
	end
end
root:SetAttribute("BuildVersion", 8)
root:SetAttribute("MoodSeed", SEED)
root:SetAttribute("LightCount", lights)
root:SetAttribute("PartCount", parts)

ChangeHistoryService:SetWaypoint("After Signal Maze v8 mood")

return {
	redLights = redLights,
	staticLights = staticLights,
	fills = fills,
	lights = lights,
	parts = parts,
	emitters = emitters,
	grimed = grimed,
	fleshParts = #fleshParts,
	redScreens = #redScreens,
	staticScreens = #staticScreens,
	tagged = #CollectionService:GetTagged(TAG),
}
