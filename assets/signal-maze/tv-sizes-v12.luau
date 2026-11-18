local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")

local SEED = 20261120
local TV_TAG = "MonsterTV"
local SHAFT_NAME = "EntryShaft"
local COLLISION_NAME = "Collision"
local CEILING_MODEL = "Ceiling_RemoveForLayoutView"
local SPAWN_NAME = "MonsterSpawn"
local SPAWN_DISTANCE = 2.5
local BASE_PIVOT = "BasePivot"
local BASE_SCALE = "BaseScale"
local BASE_TV_SCALE = "BaseTvScale"
local BASE_BRIGHTNESS = "BaseLightBrightness"
local BASE_RANGE = "BaseLightRange"

local CATEGORIES = {
	{ name = "Small", weight = 0.32, range = { 0.5, 0.75 } },
	{ name = "Medium", weight = 0.33, range = { 0.85, 1.05 } },
	{ name = "Large", weight = 0.25, range = { 1.25, 1.6 } },
	{ name = "Giant", weight = 0.1, range = { 1.9, 2.5 } },
}
local MAX_WIDTH = 28
local CEILING_CLEARANCE = 1.5
local PUSH_PER_SCALE = 0.6
local MAX_PUSH = 1.4
local OVERLAP_PADDING = 0.3
local EDGE_INSET = 0.6
local PROBE_FRONT = 3
local PROBE_DEPTH = 12
local SIDE_PROBE_FRONT = 0.3
local SHRINK_STEP = 0.88
local MIN_FACTOR = 0.45
local RED_RANGE = { 14, 36 }
local STATIC_RANGE = { 12, 28 }
local RANGE_BASE = 9
local RANGE_PER_STUD = 2.2
local BRIGHTNESS_LIMITS = { 0.45, 1.05 }

type Tv = {
	model: Model,
	housing: BasePart,
	glass: BasePart,
	light: SurfaceLight?,
	spawn: Attachment?,
	red: boolean,
	basePivot: CFrame,
	baseScale: number,
	anchor: Vector3,
	front: Vector3,
	target: number,
	category: string,
	factor: number,
	minimum: Vector3,
	maximum: Vector3,
}

local function flat(vector: Vector3): Vector3
	local value = Vector3.new(vector.X, 0, vector.Z)
	return if value.Magnitude > 0.001 then value.Unit else Vector3.zAxis
end

local function anchorOf(tv: Tv): Vector3
	local glass = tv.glass
	local frontCenter = glass.CFrame:PointToWorldSpace(Vector3.new(0, 0, -glass.Size.Z / 2))
	local bottom = tv.housing.Position.Y - tv.housing.ExtentsSize.Y / 2
	return Vector3.new(frontCenter.X, bottom, frontCenter.Z)
end

local function bounds(model: Model): (Vector3, Vector3)
	local cframe, size = model:GetBoundingBox()
	local half = size / 2
	local minimum = Vector3.one * math.huge
	local maximum = -Vector3.one * math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local corner = cframe:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
				minimum = minimum:Min(corner)
				maximum = maximum:Max(corner)
			end
		end
	end
	return minimum, maximum
end

local function apply(tv: Tv, factor: number)
	local model = tv.model
	model:PivotTo(tv.basePivot)
	model:ScaleTo(tv.baseScale * factor)
	local push = math.clamp((factor - 1) * PUSH_PER_SCALE, 0, MAX_PUSH)
	model:PivotTo(model:GetPivot() + (tv.anchor - anchorOf(tv)) + tv.front * push)
	tv.factor = factor
	tv.minimum, tv.maximum = bounds(model)
end

local function overlaps(a: Tv, b: Tv): boolean
	local pad = OVERLAP_PADDING
	return a.minimum.X < b.maximum.X - pad
		and a.maximum.X > b.minimum.X + pad
		and a.minimum.Y < b.maximum.Y - pad
		and a.maximum.Y > b.minimum.Y + pad
		and a.minimum.Z < b.maximum.Z - pad
		and a.maximum.Z > b.minimum.Z + pad
end

local function backed(tv: Tv, params: RaycastParams): boolean
	local housing = tv.housing
	local right = flat(tv.front):Cross(Vector3.yAxis)
	local frontCenter = tv.glass.CFrame:PointToWorldSpace(Vector3.new(0, 0, -tv.glass.Size.Z / 2))
	local halfWidth = housing.Size.X / 2 - EDGE_INSET
	local bottom = housing.Position.Y - housing.Size.Y / 2
	for _, side in { -1, 1 } do
		for _, level in { 0.25, 0.85 } do
			local point = Vector3.new(frontCenter.X, bottom + housing.Size.Y * level, frontCenter.Z) + right * side * halfWidth
			if not workspace:Raycast(point + tv.front * PROBE_FRONT, -tv.front * PROBE_DEPTH, params) then
				return false
			end
		end
		local start = frontCenter + tv.front * SIDE_PROBE_FRONT
		if workspace:Raycast(start, right * side * (housing.Size.X / 2 + 0.3), params) then
			return false
		end
	end
	return true
end

local function fits(tv: Tv, others: { Tv }, params: RaycastParams, ceiling: number): boolean
	if tv.housing.Size.X > MAX_WIDTH or tv.maximum.Y > ceiling - CEILING_CLEARANCE then
		return false
	end
	if not backed(tv, params) then
		return false
	end
	for _, other in others do
		if other ~= tv and overlaps(tv, other) then
			return false
		end
	end
	return true
end

local function pickCategory(rng: Random): (string, number)
	local roll = rng:NextNumber()
	local total = 0
	for _, category in CATEGORIES do
		total += category.weight
		if roll <= total then
			return category.name, rng:NextNumber(category.range[1], category.range[2])
		end
	end
	local last = CATEGORIES[#CATEGORIES]
	return last.name, rng:NextNumber(last.range[1], last.range[2])
end

local function relight(tv: Tv)
	local light = tv.light
	if not light then
		return
	end
	local baseBrightness = light:GetAttribute(BASE_BRIGHTNESS)
	if type(baseBrightness) ~= "number" then
		baseBrightness = light.Brightness
		light:SetAttribute(BASE_BRIGHTNESS, baseBrightness)
		light:SetAttribute(BASE_RANGE, light.Range)
	end
	local limits = if tv.red then RED_RANGE else STATIC_RANGE
	light.Brightness = math.clamp(baseBrightness * math.sqrt(tv.factor), BRIGHTNESS_LIMITS[1], BRIGHTNESS_LIMITS[2])
	light.Range = math.clamp(RANGE_BASE + RANGE_PER_STUD * tv.glass.Size.X, limits[1], limits[2])
	light.Shadows = false
end

local function collect(root: Instance): { Tv }
	local shaft = root:FindFirstChild(SHAFT_NAME)
	local list: { Tv } = {}
	for _, model in CollectionService:GetTagged(TV_TAG) do
		if not model:IsA("Model") or not model:IsDescendantOf(root) or (shaft and model:IsDescendantOf(shaft)) then
			continue
		end
		local housing = model:FindFirstChild("Housing")
		local glass = model:FindFirstChild("BroadcastGlass")
		if not housing or not housing:IsA("BasePart") or not glass or not glass:IsA("BasePart") then
			continue
		end
		local basePivot = model:GetAttribute(BASE_PIVOT)
		local baseScale = model:GetAttribute(BASE_SCALE)
		if typeof(basePivot) == "CFrame" and type(baseScale) == "number" then
			model:ScaleTo(baseScale)
			model:PivotTo(basePivot)
		else
			basePivot = model:GetPivot()
			baseScale = model:GetScale()
			model:SetAttribute(BASE_PIVOT, basePivot)
			model:SetAttribute(BASE_SCALE, baseScale)
			model:SetAttribute(BASE_TV_SCALE, model:GetAttribute("TvScale"))
		end
		local gui = glass:FindFirstChild("Signal")
		local spawn = glass:FindFirstChild(SPAWN_NAME)
		local tv: Tv = {
			model = model,
			housing = housing,
			glass = glass,
			light = glass:FindFirstChildOfClass("SurfaceLight"),
			spawn = if spawn and spawn:IsA("Attachment") then spawn else nil,
			red = gui ~= nil and gui:FindFirstChild("RedSilhouette") ~= nil,
			basePivot = basePivot :: CFrame,
			baseScale = baseScale :: number,
			anchor = Vector3.zero,
			front = flat((basePivot :: CFrame).LookVector),
			target = 1,
			category = "Medium",
			factor = 1,
			minimum = Vector3.zero,
			maximum = Vector3.zero,
		}
		tv.anchor = anchorOf(tv)
		tv.minimum, tv.maximum = bounds(model)
		table.insert(list, tv)
	end
	table.sort(list, function(a, b)
		return a.model.Name < b.model.Name
	end)
	return list
end

return function()
	local root = workspace:FindFirstChild("SignalMaze")
	assert(root and root:IsA("Model"), "Workspace.SignalMaze not found")
	local collision = root:FindFirstChild(COLLISION_NAME)
	assert(collision, "SignalMaze." .. COLLISION_NAME .. " not found")
	local ceilingModel = root:FindFirstChild(CEILING_MODEL)
	local ceilingPart = ceilingModel and ceilingModel:FindFirstChildWhichIsA("BasePart")
	assert(ceilingPart, "ceiling not found")
	local ceiling = ceilingPart.Position.Y - ceilingPart.Size.Y / 2

	ChangeHistoryService:SetWaypoint("Before Signal Maze v12 TV sizes")
	local rng = Random.new(SEED)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { collision }

	local list = collect(root)
	for _, tv in list do
		tv.category, tv.target = pickCategory(rng)
	end
	local order = table.clone(list)
	table.sort(order, function(a, b)
		return a.target > b.target
	end)

	local counts: { [string]: number } = {}
	local kept = 0
	for _, tv in order do
		local factor = tv.target
		local placed = false
		while factor >= MIN_FACTOR do
			apply(tv, factor)
			if fits(tv, list, params, ceiling) then
				placed = true
				break
			end
			factor *= SHRINK_STEP
		end
		if not placed then
			apply(tv, 1)
			kept += 1
		end
		relight(tv)
		local glass = tv.glass
		local spawn = tv.spawn
		if spawn then
			spawn.WorldPosition = glass.Position + flat(tv.front) * SPAWN_DISTANCE
		end
		local baseTvScale = tv.model:GetAttribute(BASE_TV_SCALE)
		if type(baseTvScale) == "number" then
			tv.model:SetAttribute("TvScale", math.round(baseTvScale * tv.factor * 100) / 100)
		end
		tv.model:SetAttribute("ScreenSize", Vector2.new(glass.Size.X, glass.Size.Y))
		local size = if tv.factor >= 1.8 then "Giant" elseif tv.factor >= 1.2 then "Large" elseif tv.factor >= 0.8 then "Medium" else "Small"
		tv.model:SetAttribute("SizeClass", size)
		counts[size] = (counts[size] or 0) + 1
	end

	local widths = {}
	for _, tv in list do
		table.insert(widths, tv.housing.Size.X)
	end
	table.sort(widths)
	root:SetAttribute("TvSizeSeed", SEED)
	ChangeHistoryService:SetWaypoint("After Signal Maze v12 TV sizes")
	return {
		screens = #list,
		counts = counts,
		keptOriginal = kept,
		smallest = widths[1],
		median = widths[#widths // 2],
		largest = widths[#widths],
	}
end
