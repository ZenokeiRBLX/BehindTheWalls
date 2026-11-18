local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20261118
local FLESH_TAG = "SignalMazeFlesh"
local TV_TAG = "MonsterTV"
local BACKUP_NAME = "SignalMaze_V11Backup"
local SHAFT_NAME = "EntryShaft"
local CEILING_MODEL = "Ceiling_RemoveForLayoutView"
local CEILING_NAME = "Ceiling"
local ENTRANCE_NAME = "MazeEntrance"

local HOLE_SIZE = 12
local ENTRY_SHIFT = Vector3.new(0, 0, -2)
local INNER_HALF_WIDTH = 7.5
local PANEL_MESHES = { "rbxassetid://105590144937639", "rbxassetid://98683797457305" }
local RIM_MESHES = { "rbxassetid://94700111830946", "rbxassetid://84485778794624" }
local ROWS = 3
local RIM_DROP = 1.5
local RIM_INSET = 0.5
local TOP_MARGIN = 14
local CAP_THICKNESS = 2
local CAP_COLOR = Color3.fromRGB(40, 26, 28)
local TV_HEIGHTS = { 22, 52, 80 }
local TV_INSET = 1.2
local GLOW = {
	Color = Color3.fromRGB(255, 92, 78),
	Brightness = 0.7,
	Range = 24,
	Heights = { 12, 40, 70 },
	WallGap = 2,
}

local function findTemplates(root: Instance, meshIds: { string }): { MeshPart }
	local found = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("MeshPart") and table.find(meshIds, descendant.MeshId) and CollectionService:HasTag(descendant, FLESH_TAG) then
			table.insert(found, descendant)
		end
	end
	table.sort(found, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return found
end

local function findTvTemplates(root: Instance): ({ Model }, { Model })
	local red, static = {}, {}
	for _, model in CollectionService:GetTagged(TV_TAG) do
		if model:IsA("Model") and model:IsDescendantOf(root) then
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

local function splitCeiling(root: Instance, center: Vector3, backup: Folder): BasePart?
	local model = root:FindFirstChild(CEILING_MODEL)
	local ceiling = model and model:FindFirstChild(CEILING_NAME)
	if not model or not ceiling or not ceiling:IsA("BasePart") then
		return if model then model:FindFirstChildWhichIsA("BasePart") else nil
	end
	if not backup:FindFirstChild(CEILING_NAME) then
		ceiling:Clone().Parent = backup
	end
	local half = ceiling.Size / 2
	local minX, maxX = ceiling.Position.X - half.X, ceiling.Position.X + half.X
	local minZ, maxZ = ceiling.Position.Z - half.Z, ceiling.Position.Z + half.Z
	local holeHalf = HOLE_SIZE / 2
	local holeMinX, holeMaxX = center.X - holeHalf, center.X + holeHalf
	local holeMinZ, holeMaxZ = center.Z - holeHalf, center.Z + holeHalf
	ceilingSlab("Ceiling_West", minX, holeMinX, minZ, maxZ, ceiling, model)
	ceilingSlab("Ceiling_East", holeMaxX, maxX, minZ, maxZ, ceiling, model)
	ceilingSlab("Ceiling_North", holeMinX, holeMaxX, minZ, holeMinZ, ceiling, model)
	ceilingSlab("Ceiling_South", holeMinX, holeMaxX, holeMaxZ, maxZ, ceiling, model)
	local template = ceiling:Clone()
	ceiling:Destroy()
	return template
end

local function placePanel(template: MeshPart, cframe: CFrame, name: string, parent: Instance)
	local panel = template:Clone()
	panel.Name = name
	panel.CFrame = cframe
	panel.CastShadow = true
	quiet(panel)
	panel.Parent = parent
	return panel
end

local function placeTv(template: Model, axis: Vector3, direction: Vector3, height: number, name: string, parent: Instance)
	local tv = template:Clone()
	tv.Name = name
	local glass = tv:FindFirstChild("BroadcastGlass") :: BasePart
	local relative = tv:GetPivot():ToObjectSpace(glass.CFrame).Position
	local glassPosition = axis + Vector3.yAxis * height - direction * (INNER_HALF_WIDTH - TV_INSET)
	local rotation = CFrame.lookAt(Vector3.zero, direction)
	tv:PivotTo(CFrame.new(glassPosition - rotation:VectorToWorldSpace(relative)) * rotation)
	for _, descendant in tv:GetDescendants() do
		if descendant:IsA("BasePart") then
			quiet(descendant)
		end
	end
	tv.Parent = parent
	return tv
end

return function()
	local root = workspace:FindFirstChild("SignalMaze")
	assert(root and root:IsA("Model"), "Workspace.SignalMaze not found")
	local entrance = root:FindFirstChild(ENTRANCE_NAME)
	assert(entrance and entrance:IsA("BasePart"), "SignalMaze." .. ENTRANCE_NAME .. " not found")
	local floor = root:FindFirstChild("Floor")
	local floorPart = floor and floor:FindFirstChildWhichIsA("BasePart")
	assert(floorPart, "SignalMaze.Floor has no part")

	ChangeHistoryService:SetWaypoint("Before Signal Maze v11 entry shaft")
	local rng = Random.new(SEED)

	local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
	if not backup then
		backup = Instance.new("Folder")
		backup.Name = BACKUP_NAME
		backup:SetAttribute("BuildVersion", root:GetAttribute("BuildVersion"))
		backup.Parent = ServerStorage
	end

	local center = Vector3.new(entrance.Position.X, 0, entrance.Position.Z) + ENTRY_SHIFT
	local floorTop = floorPart.Position.Y + floorPart.Size.Y / 2
	local slabTemplate = splitCeiling(root, center, backup :: Folder)
	assert(slabTemplate, "SignalMaze ceiling not found")
	local ceilingBottom = slabTemplate.Position.Y - slabTemplate.Size.Y / 2

	local existing = root:FindFirstChild(SHAFT_NAME)
	if existing then
		existing:Destroy()
	end
	local shaft = Instance.new("Model")
	shaft.Name = SHAFT_NAME
	shaft.Parent = root

	local panels = findTemplates(root, PANEL_MESHES)
	local rims = findTemplates(root, RIM_MESHES)
	assert(#panels > 0 and #rims > 0, "flesh templates not found")
	local panelHeight = panels[1].Size.Y
	local panelDepth = panels[1].Size.Z
	local axis = Vector3.new(center.X, 0, center.Z)
	local directions = { Vector3.xAxis, Vector3.zAxis, -Vector3.xAxis, -Vector3.zAxis }

	local lining = Instance.new("Model")
	lining.Name = "Lining"
	lining.Parent = shaft
	for row = 1, ROWS do
		local y = ceilingBottom + panelHeight * (row - 0.5)
		local turn = rng:NextInteger(0, 3)
		for side = 1, 4 do
			local direction = directions[(side + turn - 1) % 4 + 1]
			local position = axis + Vector3.yAxis * y - direction * (INNER_HALF_WIDTH + panelDepth / 2)
			local cframe = CFrame.lookAt(position, Vector3.new(axis.X, y, axis.Z))
			if rng:NextNumber() < 0.5 then
				cframe *= CFrame.Angles(0, math.pi, 0)
			end
			if rng:NextNumber() < 0.5 then
				cframe *= CFrame.Angles(0, 0, math.pi)
			end
			local template = panels[rng:NextInteger(1, #panels)]
			placePanel(template, cframe, ("Panel_%d_%d"):format(row, side), lining)
		end
	end

	local rim = Instance.new("Model")
	rim.Name = "Rim"
	rim.Parent = shaft
	local holeHalf = HOLE_SIZE / 2
	for side = 1, 4 do
		local direction = directions[side]
		local template = rims[rng:NextInteger(1, #rims)]
		local depth = template.Size.X
		local position = axis + Vector3.yAxis * (ceilingBottom - RIM_DROP) - direction * (holeHalf + depth / 2 - RIM_INSET)
		local along = direction:Cross(Vector3.yAxis)
		local cframe = CFrame.fromMatrix(position, direction, along) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0)
		placePanel(template, cframe, "Rim_" .. side, rim)
	end

	local topY = ceilingBottom + panelHeight * ROWS
	local cap = slabTemplate:Clone()
	cap:ClearAllChildren()
	cap.Name = "Cap"
	cap.Size = Vector3.new(INNER_HALF_WIDTH * 2 + panelDepth * 2 + 6, CAP_THICKNESS, INNER_HALF_WIDTH * 2 + panelDepth * 2 + 6)
	cap.CFrame = CFrame.new(axis + Vector3.yAxis * (topY + CAP_THICKNESS / 2))
	cap.Color = CAP_COLOR
	quiet(cap)
	cap.Parent = shaft

	local red, static = findTvTemplates(root)
	local screens = Instance.new("Model")
	screens.Name = "Screens"
	screens.Parent = shaft
	for index, height in TV_HEIGHTS do
		local pool = if index % 2 == 1 and #red > 0 then red else static
		if #pool > 0 then
			local template = pool[rng:NextInteger(1, #pool)]
			local direction = directions[rng:NextInteger(1, 4)]
			placeTv(template, axis, direction, ceilingBottom + height, "ShaftTV_" .. index, screens)
		end
	end

	local glow = Instance.new("Model")
	glow.Name = "Glow"
	glow.Parent = shaft
	for index, height in GLOW.Heights do
		local angle = index * 2.39996
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (INNER_HALF_WIDTH - GLOW.WallGap)
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

	root:SetAttribute("BuildVersion", 11)
	root:SetAttribute("EntryShaftSeed", SEED)
	ChangeHistoryService:SetWaypoint("After Signal Maze v11 entry shaft")

	return {
		center = center,
		ceilingBottom = ceilingBottom,
		top = topY,
		panels = #lining:GetChildren(),
		rim = #rim:GetChildren(),
		screens = #screens:GetChildren(),
	}
end
