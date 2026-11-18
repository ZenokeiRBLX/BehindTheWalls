local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20261119
local FLESH_TAG = "SignalMazeFlesh"
local TV_TAG = "MonsterTV"
local BACKUP_NAME = "SignalMaze_V11Backup"
local SHAFT_NAME = "EntryShaft"
local CEILING_MODEL = "Ceiling_RemoveForLayoutView"
local CEILING_NAME = "Ceiling"
local SLAB_PREFIX = "Ceiling_"
local ENTRANCE_NAME = "MazeEntrance"

local ENTRY_SHIFT = Vector3.new(0, 0, -2)
local HOLE_RADIUS = 6.5
local CUT_HALF = 10
local COLLAR_SEGMENTS = 24
local COLLAR_OUTER = 15
local COLLAR_DROP = 0.1
local COLUMN_MESHES = { "rbxassetid://94700111830946", "rbxassetid://84485778794624" }
local COLUMNS_PER_ROW = 9
local ROWS = 3
local RADIAL_JITTER = 0.4
local BACKING_SEGMENTS = 20
local BACKING_THICKNESS = 2
local BACKING_COLOR = Color3.fromRGB(34, 20, 22)
local TOP_MARGIN = 14
local CAP_THICKNESS = 2
local CAP_COLOR = Color3.fromRGB(40, 26, 28)
local TV_HEIGHTS = { 22, 52, 80 }
local TV_INSET = 0.8
local GLOW = {
	Color = Color3.fromRGB(255, 92, 78),
	Brightness = 0.7,
	Range = 24,
	Heights = { 12, 40, 70 },
	WallGap = 2,
}
local TWO_PI = math.pi * 2

local function findTemplates(root: Instance, meshIds: { string }, exclude: Instance?): { MeshPart }
	local found = {}
	for _, descendant in root:GetDescendants() do
		if exclude and descendant:IsDescendantOf(exclude) then
			continue
		end
		if descendant:IsA("MeshPart") and table.find(meshIds, descendant.MeshId) and CollectionService:HasTag(descendant, FLESH_TAG) then
			table.insert(found, descendant)
		end
	end
	table.sort(found, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return found
end

local function findTvTemplates(root: Instance, exclude: Instance?): ({ Model }, { Model })
	local red, static = {}, {}
	for _, model in CollectionService:GetTagged(TV_TAG) do
		if model:IsA("Model") and model:IsDescendantOf(root) and not (exclude and model:IsDescendantOf(exclude)) then
			local glass = model:FindFirstChild("BroadcastGlass")
			local gui = glass and glass:FindFirstChild("Signal")
			if gui and gui:FindFirstChild("RedSilhouette") then
				table.insert(red, model)
			elseif gui then
				table.insert(static, model)
			end
		end
	end
	local function byName(a: Model, b: Model)
		return a.Name < b.Name
	end
	table.sort(red, byName)
	table.sort(static, byName)
	return red, static
end

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function marker(name: string, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(4, 1, 4)
	part.Transparency = 1
	part.CastShadow = false
	part.CFrame = cframe
	quiet(part)
	part.Parent = parent
	return part
end

local function restoreCeiling(root: Instance, backup: Instance): BasePart
	local model = root:FindFirstChild(CEILING_MODEL)
	assert(model, "SignalMaze." .. CEILING_MODEL .. " not found")
	local original = backup:FindFirstChild(CEILING_NAME)
	local live = model:FindFirstChild(CEILING_NAME)
	if not original then
		assert(live and live:IsA("BasePart"), "no original ceiling to split")
		live:Clone().Parent = backup
		original = backup:FindFirstChild(CEILING_NAME)
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and (child.Name == CEILING_NAME or child.Name:sub(1, #SLAB_PREFIX) == SLAB_PREFIX) then
			child:Destroy()
		end
	end
	local ceiling = (original :: BasePart):Clone()
	ceiling.Parent = model
	return ceiling
end

local function ceilingSlab(name: string, minX: number, maxX: number, minZ: number, maxZ: number, template: BasePart, parent: Instance)
	if maxX - minX <= 0.01 or maxZ - minZ <= 0.01 then
		return
	end
	local slab = template:Clone()
	slab:ClearAllChildren()
	slab.Name = name
	slab.Size = Vector3.new(maxX - minX, template.Size.Y, maxZ - minZ)
	slab.CFrame = CFrame.new((minX + maxX) / 2, template.Position.Y, (minZ + maxZ) / 2)
	slab.Parent = parent
	for _, child in template:GetChildren() do
		if child:IsA("Attachment") then
			local position = child.WorldPosition
			if position.X >= minX and position.X < maxX and position.Z >= minZ and position.Z < maxZ then
				local world = child.WorldCFrame
				child.Parent = slab
				child.WorldCFrame = world
			end
		end
	end
end

local function splitCeiling(ceiling: BasePart, center: Vector3): BasePart
	local model = ceiling.Parent :: Instance
	local half = ceiling.Size / 2
	local minX, maxX = ceiling.Position.X - half.X, ceiling.Position.X + half.X
	local minZ, maxZ = ceiling.Position.Z - half.Z, ceiling.Position.Z + half.Z
	local holeMinX, holeMaxX = center.X - CUT_HALF, center.X + CUT_HALF
	local holeMinZ, holeMaxZ = center.Z - CUT_HALF, center.Z + CUT_HALF
	ceilingSlab(SLAB_PREFIX .. "West", minX, holeMinX, minZ, maxZ, ceiling, model)
	ceilingSlab(SLAB_PREFIX .. "East", holeMaxX, maxX, minZ, maxZ, ceiling, model)
	ceilingSlab(SLAB_PREFIX .. "North", holeMinX, holeMaxX, minZ, holeMinZ, ceiling, model)
	ceilingSlab(SLAB_PREFIX .. "South", holeMinX, holeMaxX, holeMaxZ, maxZ, ceiling, model)
	local template = ceiling:Clone()
	template:ClearAllChildren()
	ceiling:Destroy()
	return template
end

local function buildCollar(slab: BasePart, axis: Vector3, parent: Instance)
	local collar = Instance.new("Model")
	collar.Name = "Collar"
	local depth = COLLAR_OUTER - HOLE_RADIUS
	local width = 2 * COLLAR_OUTER * math.tan(math.pi / COLLAR_SEGMENTS) + 0.3
	local thickness = slab.Size.Y + COLLAR_DROP * 2
	local y = slab.Position.Y
	for index = 0, COLLAR_SEGMENTS - 1 do
		local angle = index / COLLAR_SEGMENTS * TWO_PI
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = Vector3.new(axis.X, y, axis.Z) + direction * (HOLE_RADIUS + depth / 2)
		local segment = slab:Clone()
		segment.Name = "Collar_" .. (index + 1)
		segment.Size = Vector3.new(width, thickness, depth)
		segment.CFrame = CFrame.lookAt(position, Vector3.new(axis.X, y, axis.Z))
		quiet(segment)
		segment.Parent = collar
	end
	collar.Parent = parent
end

local function placeMesh(template: MeshPart, cframe: CFrame, name: string, parent: Instance): MeshPart
	local part = template:Clone()
	part.Name = name
	part.CFrame = cframe
	part.CastShadow = true
	quiet(part)
	part.Parent = parent
	return part
end

local function buildLining(columns: { MeshPart }, axis: Vector3, bottom: number, rng: Random, parent: Instance): number
	local lining = Instance.new("Model")
	lining.Name = "Lining"
	local height = columns[1].Size.Y
	for row = 1, ROWS do
		local y = bottom + height * (row - 0.5)
		local stagger = (row % 2) * 0.5
		for index = 0, COLUMNS_PER_ROW - 1 do
			local template = columns[rng:NextInteger(1, #columns)]
			local depth = template.Size.Z
			local angle = (index + stagger) / COLUMNS_PER_ROW * TWO_PI + rng:NextNumber(-0.06, 0.06)
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local radius = HOLE_RADIUS + depth / 2 + rng:NextNumber(-RADIAL_JITTER, RADIAL_JITTER)
			local position = Vector3.new(axis.X, y, axis.Z) + direction * radius
			local cframe = CFrame.lookAt(position, Vector3.new(axis.X, y, axis.Z))
			if rng:NextNumber() < 0.5 then
				cframe *= CFrame.Angles(0, 0, math.pi)
			end
			cframe *= CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), 0)
			placeMesh(template, cframe, ("Column_%d_%d"):format(row, index + 1), lining)
		end
	end
	lining.Parent = parent
	return bottom + height * ROWS
end

local function buildBacking(slab: BasePart, axis: Vector3, bottom: number, top: number, radius: number, parent: Instance)
	local backing = Instance.new("Model")
	backing.Name = "Backing"
	local width = 2 * (radius + BACKING_THICKNESS) * math.tan(math.pi / BACKING_SEGMENTS) + 0.2
	local height = top - bottom
	local y = (bottom + top) / 2
	for index = 0, BACKING_SEGMENTS - 1 do
		local angle = index / BACKING_SEGMENTS * TWO_PI
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = Vector3.new(axis.X, y, axis.Z) + direction * (radius + BACKING_THICKNESS / 2)
		local wall = slab:Clone()
		wall.Name = "Backing_" .. (index + 1)
		wall.Size = Vector3.new(width, height, BACKING_THICKNESS)
		wall.CFrame = CFrame.lookAt(position, Vector3.new(axis.X, y, axis.Z))
		wall.Color = BACKING_COLOR
		wall.CastShadow = false
		quiet(wall)
		wall.Parent = backing
	end
	backing.Parent = parent
end

local function placeTv(template: Model, axis: Vector3, direction: Vector3, height: number, name: string, parent: Instance)
	local tv = template:Clone()
	tv.Name = name
	local glass = tv:FindFirstChild("BroadcastGlass") :: BasePart
	local relative = tv:GetPivot():ToObjectSpace(glass.CFrame).Position
	local glassPosition = Vector3.new(axis.X, height, axis.Z) - direction * (HOLE_RADIUS - TV_INSET)
	local rotation = CFrame.lookAt(Vector3.zero, direction)
	tv:PivotTo(CFrame.new(glassPosition - rotation:VectorToWorldSpace(relative)) * rotation)
	for _, descendant in tv:GetDescendants() do
		if descendant:IsA("BasePart") then
			quiet(descendant)
		end
	end
	tv.Parent = parent
end

return function()
	local root = workspace:FindFirstChild("SignalMaze")
	assert(root and root:IsA("Model"), "Workspace.SignalMaze not found")
	local entrance = root:FindFirstChild(ENTRANCE_NAME)
	assert(entrance and entrance:IsA("BasePart"), "SignalMaze." .. ENTRANCE_NAME .. " not found")
	local floor = root:FindFirstChild("Floor")
	local floorPart = floor and floor:FindFirstChildWhichIsA("BasePart")
	assert(floorPart, "SignalMaze.Floor has no part")

	ChangeHistoryService:SetWaypoint("Before Signal Maze v12 round entry shaft")
	local rng = Random.new(SEED)

	local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
	if not backup then
		backup = Instance.new("Folder")
		backup.Name = BACKUP_NAME
		backup:SetAttribute("BuildVersion", root:GetAttribute("BuildVersion"))
		backup.Parent = ServerStorage
	end

	local existing = root:FindFirstChild(SHAFT_NAME)
	local center = Vector3.new(entrance.Position.X, 0, entrance.Position.Z) + ENTRY_SHIFT
	local axis = Vector3.new(center.X, 0, center.Z)
	local floorTop = floorPart.Position.Y + floorPart.Size.Y / 2
	local columns = findTemplates(root, COLUMN_MESHES, existing)
	local red, static = findTvTemplates(root, existing)
	assert(#columns > 0, "flesh column templates not found")
	if existing then
		existing:Destroy()
	end

	local ceiling = restoreCeiling(root, backup :: Instance)
	local slab = splitCeiling(ceiling, center)
	local ceilingBottom = slab.Position.Y - slab.Size.Y / 2

	local shaft = Instance.new("Model")
	shaft.Name = SHAFT_NAME
	shaft.Parent = root

	buildCollar(slab, axis, shaft)
	local topY = buildLining(columns, axis, ceilingBottom, rng, shaft)
	buildBacking(slab, axis, ceilingBottom, topY, HOLE_RADIUS + columns[1].Size.Z + 0.5, shaft)

	local capSize = (HOLE_RADIUS + columns[1].Size.Z + BACKING_THICKNESS + 2) * 2
	local cap = slab:Clone()
	cap.Name = "Cap"
	cap.Size = Vector3.new(capSize, CAP_THICKNESS, capSize)
	cap.CFrame = CFrame.new(axis + Vector3.yAxis * (topY + CAP_THICKNESS / 2))
	cap.Color = CAP_COLOR
	quiet(cap)
	cap.Parent = shaft

	local screens = Instance.new("Model")
	screens.Name = "Screens"
	screens.Parent = shaft
	for index, height in TV_HEIGHTS do
		local pool = if index % 2 == 1 and #red > 0 then red else static
		if #pool > 0 then
			local angle = rng:NextNumber(0, TWO_PI)
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			placeTv(pool[rng:NextInteger(1, #pool)], axis, direction, ceilingBottom + height, "ShaftTV_" .. index, screens)
		end
	end

	local glow = Instance.new("Model")
	glow.Name = "Glow"
	glow.Parent = shaft
	for index, height in GLOW.Heights do
		local angle = index * 2.39996
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (HOLE_RADIUS - GLOW.WallGap)
		local holder = marker("Glow_" .. index, CFrame.new(axis + Vector3.yAxis * (ceilingBottom + height) + offset), glow)
		holder.Size = Vector3.one * 0.2
		local light = Instance.new("PointLight")
		light.Color = GLOW.Color
		light.Brightness = GLOW.Brightness
		light.Range = GLOW.Range
		light.Shadows = false
		light.Parent = holder
	end

	local entryPosition = Vector3.new(axis.X, floorTop + 0.5, axis.Z)
	local facing = entrance.CFrame.LookVector
	facing = Vector3.new(facing.X, 0, facing.Z)
	facing = if facing.Magnitude > 0.01 then facing.Unit else -Vector3.zAxis
	marker("LevelEntry", CFrame.lookAt(entryPosition, entryPosition + facing), shaft)
	local topPosition = Vector3.new(axis.X, topY - TOP_MARGIN, axis.Z)
	marker("ShaftTop", CFrame.lookAt(topPosition, topPosition + facing), shaft)

	root:SetAttribute("BuildVersion", 12)
	root:SetAttribute("EntryShaftSeed", SEED)
	ChangeHistoryService:SetWaypoint("After Signal Maze v12 round entry shaft")

	return {
		center = center,
		ceilingBottom = ceilingBottom,
		top = topY,
		columns = #columns,
		collar = COLLAR_SEGMENTS,
	}
end
