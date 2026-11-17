local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20261117
local TV_TAG = "MonsterTV"
local FLESH_TAG = "SignalMazeFlesh"
local BACKUP_NAME = "SignalMaze_V9Backup"
local OLD_VARIANT = "Flesh_WetFolds_V2"
local VARIANT_NAME = "Flesh_Lumps_V9"
local SKIN_NAME = "FleshSkin"
local COLLAR_NAME = "FleshCollar"
local GLASS_NAME = "CrtGlass"
local ROLL_NAME = "RollBar"

local MESHES = {
	Wall27 = { "rbxassetid://91902436901962", "rbxassetid://122935893228430" },
	Wall51 = { "rbxassetid://87180627489987", "rbxassetid://119994533743548" },
	Column = { "rbxassetid://96400586491073", "rbxassetid://72975452786060" },
	Collar = { "rbxassetid://120258748207168", "rbxassetid://130241850805179" },
}
local TEXTURES = {
	Color = "rbxassetid://133842902769997",
	Normal = "rbxassetid://79057930927120",
	Roughness = "rbxassetid://76510653129905",
	Static = "rbxassetid://79102717337929",
	Red = "rbxassetid://132076644354660",
	Overlay = "rbxassetid://127074494669484",
}

local LIGHTING = {
	ClockTime = 14,
	Brightness = 1,
	Ambient = Color3.fromRGB(104, 82, 86),
	OutdoorAmbient = Color3.fromRGB(30, 18, 20),
	ExposureCompensation = 0.55,
	EnvironmentDiffuseScale = 0.2,
	EnvironmentSpecularScale = 0.8,
}
local HAZE = {
	Density = 0.46,
	Offset = 0,
	Color = Color3.fromRGB(150, 112, 114),
	Decay = Color3.fromRGB(78, 48, 52),
	Glare = 0,
	Haze = 2.2,
}
local BLOOM = { Intensity = 1, Size = 38, Threshold = 0.85 }
local GRADE = { Brightness = 0, Contrast = 0.14, Saturation = -0.26, TintColor = Color3.fromRGB(255, 236, 230) }
local WATER = {
	WaterColor = Color3.fromRGB(40, 12, 14),
	WaterReflectance = 0.6,
	WaterTransparency = 0.15,
	WaterWaveSize = 0.045,
	WaterWaveSpeed = 2,
}

local FLESH_TINT = Color3.fromRGB(245, 225, 225)
local FLESH_JITTER = 0.08
local SLAB_TILE = 12
local CEILING_COLOR = Color3.fromRGB(70, 46, 48)
local FLOOR_COLOR = Color3.fromRGB(96, 60, 62)

local COLLAR_NATIVE = Vector3.new(12, 9.2, 4)
local COLLAR_INNER = Vector2.new(3.6, 2.7)
local COLLAR_HOLE = 0.9
local COLLAR_BASE = 3.3
local COLLAR_LEAD = 0.3

local STATIC_FRAME = 256
local STATIC_GRID = 4
local RED_FRAME = 512
local RED_GRID = 2
local STATIC_COLOR = Color3.fromRGB(205, 208, 218)
local STATIC_GUI_BRIGHTNESS = 1.2
local RED_GUI_BRIGHTNESS = 2.2
local ROLL_HEIGHT = 0.22
local ROLL_TRANSPARENCY = 0.7

local RED_LIGHT = { Color = Color3.fromRGB(255, 128, 104), Brightness = { 0.6, 0.9 } }
local STATIC_LIGHT = { Color = Color3.fromRGB(186, 192, 208), Brightness = { 0.35, 0.5 } }
local FILL = { Color = Color3.fromRGB(236, 204, 204), Brightness = 0.7, EntranceBrightness = 0.5 }

return function()
	assert(game.PlaceId == 126262358232325, "This pass targets Map Creation")
	local root = workspace:FindFirstChild("SignalMaze")
	local version = root and root:GetAttribute("BuildVersion")
	assert(version == 8 or version == 9, "Expected the version 8 or 9 SignalMaze")
	local ceiling = root.Ceiling_RemoveForLayoutView:FindFirstChild("Ceiling")
	local floor = root.Floor:FindFirstChildWhichIsA("BasePart")
	local oldVariant = MaterialService:FindFirstChild(OLD_VARIANT, true)
	assert(ceiling and floor and oldVariant, "Missing the ceiling, the floor or the old flesh variant")

	ChangeHistoryService:SetWaypoint("Before Signal Maze v9 remesh")

	local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
	if not backup then
		assert(version == 8, "Version 9 is applied but its backup is missing")
		backup = Instance.new("Folder")
		backup.Name = BACKUP_NAME
		local copy = root:Clone()
		for _, descendant in copy:GetDescendants() do
			if descendant:HasTag(TV_TAG) then
				descendant:RemoveTag(TV_TAG)
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
			backup:SetAttribute(name, (Lighting :: any)[name])
		end
		for name in WATER do
			backup:SetAttribute(name, (workspace.Terrain :: any)[name])
		end
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
	local function skinOn(part: MeshPart, tint: Color3)
		local skin = part:FindFirstChild(SKIN_NAME) or Instance.new("SurfaceAppearance")
		skin.Name = SKIN_NAME
		skin.ColorMap = TEXTURES.Color
		skin.NormalMap = TEXTURES.Normal
		skin.RoughnessMap = TEXTURES.Roughness
		skin.Color = tint
		skin.Parent = part
	end

	local templates: { [string]: { MeshPart } } = {}
	for kind, ids in MESHES do
		templates[kind] = {}
		for index, id in ids do
			templates[kind][index] = AssetService:CreateMeshPartAsync(Content.fromUri(id), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end
	end

	apply(Lighting, LIGHTING)
	apply(Lighting:FindFirstChildOfClass("Atmosphere"), HAZE)
	apply(Lighting:FindFirstChildOfClass("BloomEffect"), BLOOM)
	apply(Lighting:FindFirstChildOfClass("ColorCorrectionEffect"), GRADE)
	apply(workspace.Terrain, WATER)

	local variant = MaterialService:FindFirstChild(VARIANT_NAME, true) or Instance.new("MaterialVariant")
	variant.Name = VARIANT_NAME
	variant.BaseMaterial = ceiling.Material
	variant.ColorMap = TEXTURES.Color
	variant.NormalMap = TEXTURES.Normal
	variant.RoughnessMap = TEXTURES.Roughness
	variant.StudsPerTile = SLAB_TILE
	variant.Parent = oldVariant.Parent
	ceiling.MaterialVariant = VARIANT_NAME
	ceiling.Color = CEILING_COLOR
	ceiling.Transparency = 0
	floor.MaterialVariant = VARIANT_NAME
	floor.Color = FLOOR_COLOR

	local fleshParts = {}
	for _, group in { root.FleshWalls, root.FleshColumns, root.Landmarks } do
		for _, descendant in group:GetDescendants() do
			if descendant:IsA("MeshPart") and descendant.Name == "Wall" then
				table.insert(fleshParts, descendant)
			end
		end
	end
	local meshCounts = { Wall27 = 0, Wall51 = 0, Column = 0 }
	for _, part in sortedByName(fleshParts) do
		local size = part.Size
		local kind = if size.X < 15 then "Column" elseif size.X < 40 then "Wall27" else "Wall51"
		part:ApplyMesh(templates[kind][rng:NextInteger(1, 2)])
		part.Size = size
		part.Material = Enum.Material.SmoothPlastic
		part.MaterialVariant = ""
		part.Color = Color3.new(1, 1, 1)
		skinOn(part, shade(FLESH_TINT, FLESH_JITTER))
		part:AddTag(FLESH_TAG)
		meshCounts[kind] += 1
	end

	local fills = 0
	for _, descendant in root.Ceiling_RemoveForLayoutView:GetDescendants() do
		if descendant:IsA("PointLight") then
			descendant.Color = FILL.Color
			descendant.Brightness = if descendant.Parent.Name == "RoomFill_EntranceHall"
				then FILL.EntranceBrightness
				else FILL.Brightness
			fills += 1
		end
	end

	local collars, redScreens, staticScreens, lights = 0, 0, 0, 0
	for index, tv in sortedByName(root.EmbeddedTVs:GetChildren()) do
		local glass = tv:FindFirstChild("BroadcastGlass")
		local housing = tv:FindFirstChild("Housing")
		if not (glass and housing and glass:IsA("BasePart") and housing:IsA("BasePart")) then
			continue
		end
		local old = tv:FindFirstChild(COLLAR_NAME)
		if old then
			old:Destroy()
		end
		local frame = glass.CFrame
		local half = housing.Size / 2
		local low = Vector3.new(math.huge, math.huge, math.huge)
		local high = -low
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = housing.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
					local p = frame:PointToObjectSpace(corner)
					low = low:Min(p)
					high = high:Max(p)
				end
			end
		end
		local extent = high - low
		local top = low.Z - COLLAR_LEAD
		local depth = COLLAR_BASE - top
		local collar = templates.Collar[index % 2 + 1]:Clone()
		collar.Name = COLLAR_NAME
		collar.Size = Vector3.new(
			extent.X * COLLAR_HOLE * COLLAR_NATIVE.X / (2 * COLLAR_INNER.X),
			extent.Y * COLLAR_HOLE * COLLAR_NATIVE.Y / (2 * COLLAR_INNER.Y),
			depth
		)
		collar.CFrame = frame
			* CFrame.new((low.X + high.X) / 2, (low.Y + high.Y) / 2, top + depth / 2)
			* CFrame.Angles(0, math.pi, 0)
		collar.Anchored = true
		collar.CanCollide = false
		collar.CanTouch = false
		collar.CanQuery = false
		collar.CastShadow = false
		collar.Material = Enum.Material.SmoothPlastic
		skinOn(collar, shade(FLESH_TINT, FLESH_JITTER))
		collar.Parent = tv
		collars += 1

		local gui = glass:FindFirstChild("Signal")
		local red = gui and gui:FindFirstChild("RedSilhouette")
		local static = gui and gui:FindFirstChild("Static")
		local label = red or static
		if gui and label then
			gui.ClipsDescendants = true
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			label.ZIndex = 1
			if red then
				red.Image = TEXTURES.Red
				red.ImageRectSize = Vector2.new(RED_FRAME, RED_FRAME)
				red.ImageRectOffset = Vector2.new(rng:NextInteger(0, RED_GRID - 1), rng:NextInteger(0, RED_GRID - 1)) * RED_FRAME
				red.ImageColor3 = Color3.new(1, 1, 1)
				gui.Brightness = RED_GUI_BRIGHTNESS
				redScreens += 1
			else
				static.Image = TEXTURES.Static
				static.ImageRectSize = Vector2.new(STATIC_FRAME, STATIC_FRAME)
				static.ImageRectOffset = Vector2.new(rng:NextInteger(0, STATIC_GRID - 1), rng:NextInteger(0, STATIC_GRID - 1)) * STATIC_FRAME
				static.ImageColor3 = STATIC_COLOR
				gui.Brightness = STATIC_GUI_BRIGHTNESS
				staticScreens += 1
			end
			local roll = gui:FindFirstChild(ROLL_NAME) or Instance.new("Frame")
			roll.Name = ROLL_NAME
			roll.BackgroundColor3 = Color3.new(0, 0, 0)
			roll.BackgroundTransparency = ROLL_TRANSPARENCY
			roll.BorderSizePixel = 0
			roll.Size = UDim2.fromScale(1, ROLL_HEIGHT)
			roll.Position = UDim2.fromScale(0, r(0, 1 - ROLL_HEIGHT))
			roll.ZIndex = 2
			local gradient = roll:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			gradient.Parent = roll
			roll.Parent = gui
			local overlay = gui:FindFirstChild(GLASS_NAME) or Instance.new("ImageLabel")
			overlay.Name = GLASS_NAME
			overlay.BackgroundTransparency = 1
			overlay.BorderSizePixel = 0
			overlay.Size = UDim2.fromScale(1, 1)
			overlay.Image = TEXTURES.Overlay
			overlay.ZIndex = 3
			overlay.Parent = gui
		end
		local light = glass:FindFirstChildOfClass("SurfaceLight")
		if light then
			local spec = if red then RED_LIGHT else STATIC_LIGHT
			light.Color = spec.Color
			light.Brightness = r(spec.Brightness[1], spec.Brightness[2])
			lights += 1
		end
	end

	for _, list in templates do
		for _, template in list do
			template:Destroy()
		end
	end

	local parts = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	root:SetAttribute("BuildVersion", 9)
	root:SetAttribute("RemeshSeed", SEED)
	root:SetAttribute("FleshTag", FLESH_TAG)
	root:SetAttribute("FleshVariant", VARIANT_NAME)
	root:SetAttribute("PartCount", parts)

	ChangeHistoryService:SetWaypoint("After Signal Maze v9 remesh")

	return {
		meshes = meshCounts,
		collars = collars,
		redScreens = redScreens,
		staticScreens = staticScreens,
		screenLights = lights,
		fills = fills,
		parts = parts,
		fleshTagged = #CollectionService:GetTagged(FLESH_TAG),
		tvTagged = #CollectionService:GetTagged(TV_TAG),
	}
end
