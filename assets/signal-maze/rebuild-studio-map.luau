local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20260926
local CELL = 24
local N = 13
local H = 32
local HALF = N * CELL / 2
local WALL_HALF = 4
local ORIGIN = Vector3.new(147, 0, 54)
local RED = Color3.fromRGB(255, 66, 57)
local STATIC_LIGHT = Color3.fromRGB(190, 205, 215)
local LIGHT_BUDGET = 72
local STATIC_LIGHT_BUDGET = 14

assert(game.PlaceId == 126262358232325, "This rebuild targets Map Creation")
local old = workspace:FindFirstChild("SignalMaze")
assert(old and old:GetAttribute("BuildVersion") == 2, "Expected the expanded (version 2) SignalMaze")
assert(not ServerStorage:FindFirstChild("SignalMaze_V3Backup"), "A version 3 backup already exists")

local variant = MaterialService:FindFirstChild("Flesh_WetFolds_V2")
assert(variant and variant:IsA("MaterialVariant"), "A flesh MaterialVariant is required")

local wallSource = old:FindFirstChild("BoneWalls") and old.BoneWalls:FindFirstChildWhichIsA("MeshPart")
assert(wallSource, "The flesh wall mesh is required")
local wallTemplate = wallSource:Clone()
for _, child in wallTemplate:GetChildren() do
	child:Destroy()
end

local redTemplate
local staticTemplate
for _, model in old.EmbeddedTVs:GetChildren() do
	local glass = model:FindFirstChild("BroadcastGlass")
	local signal = glass and glass:FindFirstChild("Signal")
	local content = signal and signal:FindFirstChildWhichIsA("ImageLabel")
	if content and content.Name == "RedSilhouette" and not redTemplate then
		redTemplate = model:Clone()
	elseif content and content.Name == "Static" and not staticTemplate then
		staticTemplate = model:Clone()
	end
end
assert(redTemplate and staticTemplate, "Both broadcast styles are required")
for _, template in {redTemplate, staticTemplate} do
	for _, d in template:GetDescendants() do
		if d:IsA("Light") then
			d:Destroy()
		end
	end
end
local staticImage = staticTemplate.BroadcastGlass.Signal.Static
local spawnTemplate = old.MazeEntrance:Clone()

ChangeHistoryService:SetWaypoint("Before Signal Maze v3")
local backup = Instance.new("Folder")
backup.Name = "SignalMaze_V3Backup"
for _, property in {"Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "FogColor", "FogStart", "FogEnd", "GlobalShadows"} do
	backup:SetAttribute(property, Lighting[property])
end
local terrain = workspace.Terrain
for _, property in {"WaterColor", "WaterReflectance", "WaterTransparency", "WaterWaveSize", "WaterWaveSpeed"} do
	backup:SetAttribute("Terrain" .. property, terrain[property])
end
backup:SetAttribute("CameraCFrame", workspace.CurrentCamera.CFrame)
backup:SetAttribute("TerrainWaterRegion", "Water filled from y 0 to 1.3 across the maze footprint; clear it with Terrain:FillBlock(Air) to revert")
local oldLighting = Instance.new("Folder")
oldLighting.Name = "Lighting"
oldLighting.Parent = backup
for _, child in Lighting:GetChildren() do
	child:Clone().Parent = oldLighting
end
backup.Parent = ServerStorage
old.Parent = backup

local rng = Random.new(SEED)
local function r(a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end
local function chance(p: number): boolean
	return rng:NextNumber() < p
end
local function shuffle(list)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local root = Instance.new("Model")
root.Name = "SignalMaze"
local function group(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = root
	return model
end
local wallsModel = group("FleshWalls")
local growthModel = group("FleshGrowths")
local columnModel = group("FleshColumns")
local collisionModel = group("Collision")
local screenModel = group("EmbeddedTVs")
local landmarkModel = group("Landmarks")
local ceilingModel = group("Ceiling_RemoveForLayoutView")
local floorModel = group("Floor")

local function fleshColor(shade: number?): Color3
	local v = r(0.84, 1.06) * (shade or 1)
	return Color3.new(math.clamp(0.8 * v, 0, 1), math.clamp(0.64 * v * r(0.94, 1.06), 0, 1), math.clamp(0.67 * v, 0, 1))
end

local function style(part: BasePart, color: Color3?)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = variant.BaseMaterial
	part.MaterialVariant = variant.Name
	part.Color = color or fleshColor()
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function ball(position: Vector3, diameter: number, parent: Instance, shade: number?): Part
	local part = Instance.new("Part")
	part.Name = "Growth"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * diameter
	part.CFrame = CFrame.new(position) * CFrame.Angles(r(0, 6.28), r(0, 6.28), r(0, 6.28))
	style(part, fleshColor(shade))
	part.Parent = parent
	return part
end

local function vertexPosition(i: number, j: number): Vector3
	return ORIGIN + Vector3.new(i * CELL - HALF, 0, j * CELL - HALF)
end

local function cellCenter(i: number, j: number): Vector3
	return ORIGIN + Vector3.new((i + 0.5) * CELL - HALF, 0, (j + 0.5) * CELL - HALF)
end

local vWall = {}
local hWall = {}
for i = 0, N do
	vWall[i] = {}
	for j = 0, N - 1 do
		vWall[i][j] = true
	end
end
for i = 0, N - 1 do
	hWall[i] = {}
	for j = 0, N do
		hWall[i][j] = true
	end
end
local locked = {}
local function edgeKey(kind: string, a: number, b: number): string
	return kind .. ":" .. a .. ":" .. b
end
local function setEdge(kind: string, a: number, b: number, value: boolean)
	if kind == "v" then
		vWall[a][b] = value
	else
		hWall[a][b] = value
	end
end
local function getEdge(kind: string, a: number, b: number): boolean
	if kind == "v" then
		return vWall[a][b]
	end
	return hWall[a][b]
end
local function neighbors(i: number, j: number)
	local list = {}
	if i > 0 then table.insert(list, {i - 1, j, "v", i, j}) end
	if i < N - 1 then table.insert(list, {i + 1, j, "v", i + 1, j}) end
	if j > 0 then table.insert(list, {i, j - 1, "h", i, j}) end
	if j < N - 1 then table.insert(list, {i, j + 1, "h", i, j + 1}) end
	return list
end

local ROOMS = {
	{name = "EntranceHall", i0 = 6, j0 = 8, i1 = 6, j1 = 12, sealed = true},
	{name = "SignalCourt", i0 = 5, j0 = 5, i1 = 7, j1 = 7},
	{name = "ReceiverChamber", i0 = 5, j0 = 0, i1 = 7, j1 = 1},
	{name = "WestGallery", i0 = 0, j0 = 4, i1 = 1, j1 = 6},
	{name = "EastGallery", i0 = 11, j0 = 6, i1 = 12, j1 = 8},
	{name = "NorthWestHollow", i0 = 1, j0 = 0, i1 = 2, j1 = 1},
	{name = "NorthEastHollow", i0 = 10, j0 = 1, i1 = 11, j1 = 2},
	{name = "SouthWestHollow", i0 = 1, j0 = 10, i1 = 2, j1 = 11},
	{name = "SouthEastHollow", i0 = 9, j0 = 10, i1 = 10, j1 = 11},
}
local DOORS = {
	{"h", 6, 8},
	{"v", 5, 6},
	{"v", 8, 6},
	{"h", 6, 5},
}
local PILLARS = {
	{6, 1}, {7, 1}, {1, 5}, {1, 6}, {12, 7}, {12, 8}, {2, 1}, {11, 2}, {2, 11}, {10, 11},
}

local roomOf = {}
local function cellKey(i: number, j: number): number
	return i * 100 + j
end
for _, room in ROOMS do
	for i = room.i0, room.i1 do
		for j = room.j0, room.j1 do
			roomOf[cellKey(i, j)] = room
			if i < room.i1 then
				setEdge("v", i + 1, j, false)
				locked[edgeKey("v", i + 1, j)] = true
			end
			if j < room.j1 then
				setEdge("h", i, j + 1, false)
				locked[edgeKey("h", i, j + 1)] = true
			end
		end
	end
	if room.sealed then
		for i = room.i0, room.i1 do
			for j = room.j0, room.j1 do
				for _, nb in neighbors(i, j) do
					if roomOf[cellKey(nb[1], nb[2])] ~= room then
						locked[edgeKey(nb[3], nb[4], nb[5])] = true
					end
				end
			end
		end
	end
end
for _, door in DOORS do
	setEdge(door[1], door[2], door[3], false)
	locked[edgeKey(door[1], door[2], door[3])] = true
end

local visited = {}
local stack = {}
local function markVisited(i: number, j: number)
	local room = roomOf[cellKey(i, j)]
	if room then
		local cells = {}
		for ci = room.i0, room.i1 do
			for cj = room.j0, room.j1 do
				if not visited[cellKey(ci, cj)] then
					visited[cellKey(ci, cj)] = true
					table.insert(cells, {ci, cj})
				end
			end
		end
		shuffle(cells)
		for _, cell in cells do
			table.insert(stack, cell)
		end
	else
		visited[cellKey(i, j)] = true
		table.insert(stack, {i, j})
	end
end
markVisited(6, 12)
while #stack > 0 do
	local top = stack[#stack]
	local options = {}
	for _, nb in neighbors(top[1], top[2]) do
		local open = not getEdge(nb[3], nb[4], nb[5])
		if not visited[cellKey(nb[1], nb[2])] and (open or not locked[edgeKey(nb[3], nb[4], nb[5])]) then
			table.insert(options, nb)
		end
	end
	if #options == 0 then
		table.remove(stack)
	else
		local pick = options[rng:NextInteger(1, #options)]
		setEdge(pick[3], pick[4], pick[5], false)
		markVisited(pick[1], pick[2])
	end
end
local visitedCount = 0
for _ in visited do
	visitedCount += 1
end
assert(visitedCount == N * N, "The maze did not reach every cell")

for i = 0, N - 1 do
	for j = 0, N - 1 do
		if not roomOf[cellKey(i, j)] then
			local closed = {}
			local walls = 0
			for _, nb in neighbors(i, j) do
				if getEdge(nb[3], nb[4], nb[5]) then
					walls += 1
					if not locked[edgeKey(nb[3], nb[4], nb[5])] then
						table.insert(closed, nb)
					end
				end
			end
			local perimeterWalls = (i == 0 and 1 or 0) + (i == N - 1 and 1 or 0) + (j == 0 and 1 or 0) + (j == N - 1 and 1 or 0)
			if walls + perimeterWalls >= 3 and #closed > 0 and chance(0.55) then
				local pick = closed[rng:NextInteger(1, #closed)]
				setEdge(pick[3], pick[4], pick[5], false)
			end
		end
	end
end
for i = 1, N - 1 do
	for j = 0, N - 1 do
		if vWall[i][j] and not locked[edgeKey("v", i, j)] and chance(0.07) then
			vWall[i][j] = false
		end
	end
end
for i = 0, N - 1 do
	for j = 1, N - 1 do
		if hWall[i][j] and not locked[edgeKey("h", i, j)] and chance(0.07) then
			hWall[i][j] = false
		end
	end
end

local function placeMesh(center: Vector3, alongX: boolean, length: number)
	local mesh = wallTemplate:Clone()
	mesh.Name = "FleshWall"
	mesh.Size = Vector3.new(length + 3, H + 2, r(6, 6.6))
	local yaw = (alongX and 0 or 90) + (chance(0.5) and 180 or 0) + r(-1.2, 1.2)
	local jitter = r(-0.35, 0.35)
	local offset = if alongX then Vector3.new(0, 0, jitter) else Vector3.new(jitter, 0, 0)
	mesh.CFrame = CFrame.new(center + offset + Vector3.new(0, H / 2, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
	style(mesh)
	mesh.Parent = wallsModel
end

local function placeCollision(center: Vector3, alongX: boolean, length: number, name: string)
	local box = Instance.new("Part")
	box.Name = name
	box.Size = if alongX then Vector3.new(length + WALL_HALF * 2, H, WALL_HALF * 2) else Vector3.new(WALL_HALF * 2, H, length + WALL_HALF * 2)
	box.CFrame = CFrame.new(center + Vector3.new(0, H / 2, 0))
	box.Anchored = true
	box.CanCollide = true
	box.CanTouch = false
	box.CanQuery = true
	box.CastShadow = false
	box.Transparency = 1
	box.Material = Enum.Material.SmoothPlastic
	box.Parent = collisionModel
end

local function emitRun(line: number, first: number, last: number, vertical: boolean)
	local startPos = if vertical then vertexPosition(line, first) else vertexPosition(first, line)
	local endPos = if vertical then vertexPosition(line, last + 1) else vertexPosition(last + 1, line)
	placeCollision((startPos + endPos) / 2, not vertical, (endPos - startPos).Magnitude, (vertical and "V" or "H") .. line .. "_" .. first .. "_" .. last)
	local k = first
	while k <= last do
		local span = if k < last and chance(0.55) then 2 else 1
		local a = if vertical then vertexPosition(line, k) else vertexPosition(k, line)
		local b = if vertical then vertexPosition(line, k + span) else vertexPosition(k + span, line)
		placeMesh((a + b) / 2, not vertical, span * CELL)
		k += span
	end
end

for i = 0, N do
	local j = 0
	while j < N do
		if vWall[i][j] then
			local first = j
			while j + 1 < N and vWall[i][j + 1] do
				j += 1
			end
			emitRun(i, first, j, true)
		end
		j += 1
	end
end
for j = 0, N do
	local i = 0
	while i < N do
		if hWall[i][j] then
			local first = i
			while i + 1 < N and hWall[i + 1][j] do
				i += 1
			end
			emitRun(j, first, i, false)
		end
		i += 1
	end
end

local function placeColumn(position: Vector3, freestanding: boolean)
	local diameter = if freestanding then r(7, 9) else r(8.6, 10.2)
	local core = Instance.new("Part")
	core.Name = "FleshColumn"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(H + 2, diameter, diameter)
	core.CFrame = CFrame.new(position + Vector3.new(0, H / 2, 0)) * CFrame.Angles(0, math.rad(r(0, 360)), math.rad(90))
	style(core)
	core.CanCollide = true
	core.CanQuery = true
	core.Parent = columnModel
	for _ = 1, rng:NextInteger(3, 6) do
		local size = r(4.5, 9)
		local angle = r(0, math.pi * 2)
		local radial = diameter / 2 - size * 0.22
		ball(position + Vector3.new(math.cos(angle) * radial, r(1, H - 1), math.sin(angle) * radial), size, columnModel)
	end
	ball(position + Vector3.new(0, r(-1.5, 0), 0), diameter * r(1.15, 1.35), columnModel, 0.9)
	if freestanding then
		ball(position + Vector3.new(0, H - r(0, 1.5), 0), diameter * r(1.2, 1.5), columnModel, 0.85)
	end
end

for i = 0, N do
	for j = 0, N do
		local west = i > 0 and hWall[i - 1][j]
		local east = i < N and hWall[i][j]
		local north = j > 0 and vWall[i][j - 1]
		local south = j < N and vWall[i][j]
		local count = (west and 1 or 0) + (east and 1 or 0) + (north and 1 or 0) + (south and 1 or 0)
		local straight = count == 2 and ((west and east) or (north and south))
		if count > 0 and (not straight or chance(0.45)) then
			placeColumn(vertexPosition(i, j), false)
		end
	end
end
for _, pillar in PILLARS do
	placeColumn(vertexPosition(pillar[1], pillar[2]), true)
end

local lightBudget = LIGHT_BUDGET
local staticLightBudget = STATIC_LIGHT_BUDGET
local screenCount = 0

local function engulf(center: Vector3, right: Vector3, normal: Vector3, width: number, height: number, frontAt: number, count: number, small: number, large: number)
	for _ = 1, count do
		local side = rng:NextInteger(1, 4)
		local x
		local y
		if side == 1 then
			x = -width / 2 - r(0, 0.8)
			y = r(-height / 2, height / 2)
		elseif side == 2 then
			x = width / 2 + r(0, 0.8)
			y = r(-height / 2, height / 2)
		elseif side == 3 then
			x = r(-width / 2, width / 2)
			y = height / 2 + r(0, 0.8)
		else
			x = r(-width / 2, width / 2)
			y = -height / 2 - r(0, 0.8)
		end
		local d = r(small, large)
		ball(center + right * x + Vector3.yAxis * y + normal * (frontAt - d / 2 - r(0.1, 0.7)), d, growthModel)
	end
end

local function placeTv(wallPoint: Vector3, normal: Vector3, red: boolean, scale: number, name: string, withLight: boolean?)
	local model = (red and redTemplate or staticTemplate):Clone()
	if math.abs(scale - 1) > 0.01 then
		model:ScaleTo(scale)
	end
	local housing = model.Housing
	local depth = housing.Size.Z
	local frontAt = r(3.9, 4.5)
	local position = wallPoint + normal * (frontAt - depth / 2)
	local target = CFrame.lookAt(position, position + normal) * CFrame.Angles(math.rad(r(-3, 6)), math.rad(r(-8, 8)), math.rad(r(-7, 7)))
	model:PivotTo(target * housing.CFrame:Inverse() * model:GetPivot())
	screenCount += 1
	model.Name = string.format("%03d_%s", screenCount, name)
	model.Parent = screenModel
	local glass = model.BroadcastGlass
	if red and lightBudget > 0 and withLight ~= false then
		lightBudget -= 1
		local light = Instance.new("SurfaceLight")
		light.Name = "ScreenSpill"
		light.Face = Enum.NormalId.Front
		light.Angle = 120
		light.Range = r(15, 22) * math.sqrt(scale)
		light.Brightness = r(1, 1.35)
		light.Color = RED
		light.Shadows = false
		light.Parent = glass
	elseif not red and staticLightBudget > 0 and chance(0.25) then
		staticLightBudget -= 1
		local light = Instance.new("SurfaceLight")
		light.Name = "ScreenSpill"
		light.Face = Enum.NormalId.Front
		light.Angle = 110
		light.Range = 12
		light.Brightness = 0.5
		light.Color = STATIC_LIGHT
		light.Shadows = false
		light.Parent = glass
	end
	local signal = glass:FindFirstChild("Signal")
	if signal and signal:IsA("SurfaceGui") then
		signal.MaxDistance = 170
	end
	local right = normal:Cross(Vector3.yAxis).Unit
	engulf(wallPoint + normal * 0, right, normal, housing.Size.X, housing.Size.Y, frontAt, rng:NextInteger(2, 3), 2.6, 4.8)
	return model
end

local function staticPanel(wallPoint: Vector3, normal: Vector3, width: number, name: string)
	local height = width * 0.62
	local frontAt = r(4.2, 4.6)
	local right = normal:Cross(Vector3.yAxis).Unit
	local facing = CFrame.lookAt(wallPoint, wallPoint + normal) * CFrame.Angles(0, 0, math.rad(r(-3, 3)))
	local bezel = Instance.new("Part")
	bezel.Name = "Bezel"
	bezel.Size = Vector3.new(width + 1, height + 1, 1.4)
	bezel.CFrame = facing + normal * (frontAt - 0.75)
	bezel.Anchored = true
	bezel.CanCollide = false
	bezel.CanTouch = false
	bezel.CanQuery = false
	bezel.CastShadow = false
	bezel.Material = Enum.Material.Plastic
	bezel.Color = Color3.fromRGB(38, 31, 30)
	local screen = Instance.new("Part")
	screen.Name = "StaticScreen"
	screen.Size = Vector3.new(width, height, 0.1)
	screen.CFrame = facing + normal * (frontAt - 0.02)
	screen.Anchored = true
	screen.CanCollide = false
	screen.CanTouch = false
	screen.CanQuery = false
	screen.CastShadow = false
	screen.Material = Enum.Material.SmoothPlastic
	screen.Color = Color3.fromRGB(8, 6, 7)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Signal"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.25
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.MaxDistance = 170
	local image = staticImage:Clone()
	image.AnchorPoint = Vector2.zero
	image.Position = UDim2.new()
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = gui
	gui.Parent = screen
	if staticLightBudget > 0 then
		staticLightBudget -= 1
		local light = Instance.new("SurfaceLight")
		light.Name = "ScreenSpill"
		light.Face = Enum.NormalId.Front
		light.Angle = 120
		light.Range = 18
		light.Brightness = 0.6
		light.Color = STATIC_LIGHT
		light.Shadows = false
		light.Parent = screen
	end
	screenCount += 1
	local model = Instance.new("Model")
	model.Name = string.format("%03d_%s", screenCount, name)
	bezel.Parent = model
	screen.Parent = model
	model.Parent = screenModel
	engulf(wallPoint, right, normal, width + 1, height + 1, frontAt, rng:NextInteger(7, 10), 3, 6.5)
end

local function cluster(center: Vector3, along: Vector3, normal: Vector3, offset: number, name: string, allowStatic: boolean)
	local roll = rng:NextNumber()
	if allowStatic and roll < 0.16 then
		local width = r(7, 10)
		local limit = CELL / 2 - width / 2 - 1.5
		staticPanel(center + along * math.clamp(offset, -limit, limit) + Vector3.yAxis * r(12, H - 11), normal, width, name .. "_Static")
	elseif roll < 0.5 then
		placeTv(center + along * offset + Vector3.yAxis * r(4.5, 10), normal, chance(0.55), 1, name)
	elseif roll < 0.84 then
		local y = r(3, 6)
		for k = 1, rng:NextInteger(2, 3) do
			placeTv(center + along * (offset + r(-1, 1)) + Vector3.yAxis * (y + (k - 1) * 4.3), normal, chance(0.5), 1, name .. "_Stack" .. k)
		end
	else
		placeTv(center + along * offset + Vector3.yAxis * r(15, H - 7), normal, chance(0.7), r(1.25, 1.6), name .. "_High")
	end
end

local function growSide(center: Vector3, along: Vector3, normal: Vector3, backLimit: number)
	for _ = 1, rng:NextInteger(2, 4) do
		local outer = r(4.3, 5.6)
		local d = math.min(r(4.5, 9), outer + backLimit)
		ball(center + along * r(-10.5, 10.5) + normal * (outer - d / 2) + Vector3.yAxis * r(-1.2, 2.2), d, growthModel)
	end
	for _ = 1, rng:NextInteger(2, 4) do
		local outer = r(4, 5.4)
		local d = math.min(r(3.5, 9.5), outer + backLimit)
		ball(center + along * r(-11, 11) + normal * (outer - d / 2) + Vector3.yAxis * r(4, H - 3), d, growthModel)
	end
	if chance(0.35) then
		local outer = r(5, 5.8)
		local d = math.min(r(11, 16), outer + backLimit)
		ball(center + along * r(-8, 8) + normal * (outer - d / 2) + Vector3.yAxis * r(7, H - 9), d, growthModel)
	end
end

local function decorateSide(center: Vector3, along: Vector3, normal: Vector3, faceI: number, faceJ: number, backLimit: number, name: string)
	growSide(center, along, normal, backLimit)
	local room = roomOf[cellKey(faceI, faceJ)]
	if room and room.name == "ReceiverChamber" and faceJ == 0 and normal.Z > 0.5 then
		staticPanel(center + Vector3.yAxis * r(13, 16), normal, 10, name .. "_ReceiverWall")
		placeTv(center + along * -7.5 + Vector3.yAxis * r(4.5, 6.5), normal, true, 1, name .. "_ReceiverLeft")
		placeTv(center + along * 7.5 + Vector3.yAxis * r(4.5, 6.5), normal, true, 1, name .. "_ReceiverRight")
		placeTv(center + along * r(-6, 6) + Vector3.yAxis * r(23, 26), normal, chance(0.5), 1.4, name .. "_ReceiverHigh")
	elseif room and room.name == "EntranceHall" then
		if chance(0.22) then
			cluster(center, along, normal, 0, name, true)
			placeTv(center + along * r(-7, 7) + Vector3.yAxis * r(4, 7), normal, true, 1, name .. "_Low")
		else
			cluster(center, along, normal, r(-8, -3.5), name .. "_A", false)
			cluster(center, along, normal, r(3.5, 8), name .. "_B", false)
		end
	elseif chance(if room then 0.5 else 0.33) then
		cluster(center, along, normal, r(-6, 6), name, true)
	end
end

for i = 0, N do
	for j = 0, N - 1 do
		if vWall[i][j] then
			local center = (vertexPosition(i, j) + vertexPosition(i, j + 1)) / 2
			local interior = i > 0 and i < N
			if i > 0 then
				decorateSide(center, Vector3.zAxis, -Vector3.xAxis, i - 1, j, if interior then 5.4 else 40, "V" .. i .. "_" .. j .. "W")
			end
			if i < N then
				decorateSide(center, Vector3.zAxis, Vector3.xAxis, i, j, if interior then 5.4 else 40, "V" .. i .. "_" .. j .. "E")
			end
		end
	end
end
for i = 0, N - 1 do
	for j = 0, N do
		if hWall[i][j] then
			local center = (vertexPosition(i, j) + vertexPosition(i + 1, j)) / 2
			local interior = j > 0 and j < N
			if j > 0 then
				decorateSide(center, Vector3.xAxis, -Vector3.zAxis, i, j - 1, if interior then 5.4 else 40, "H" .. i .. "_" .. j .. "N")
			end
			if j < N then
				decorateSide(center, Vector3.xAxis, Vector3.zAxis, i, j, if interior then 5.4 else 40, "H" .. i .. "_" .. j .. "S")
			end
		end
	end
end

local court = cellCenter(6, 6)
local totemCore = Instance.new("Part")
totemCore.Name = "SignalTotem"
totemCore.Shape = Enum.PartType.Cylinder
totemCore.Size = Vector3.new(19, 7, 7)
totemCore.CFrame = CFrame.new(court + Vector3.new(0, 9.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
style(totemCore)
totemCore.CanCollide = true
totemCore.CanQuery = true
totemCore.Parent = landmarkModel
ball(court + Vector3.new(0, -2.5, 0), 14, landmarkModel, 0.9)
ball(court + Vector3.new(0, 19.5, 0), 8, landmarkModel)
for level = 0, 2 do
	for k = 0, 3 do
		local yaw = math.rad(k * 90 + level * 45)
		local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		placeTv(court + dir * -0.3 + Vector3.new(0, 4 + level * 4.8, 0), dir, level == 2 or chance(0.5), 1, "Totem_L" .. level .. "_" .. k, level ~= 1)
	end
end
for _ = 1, 8 do
	local angle = r(0, math.pi * 2)
	ball(court + Vector3.new(math.cos(angle) * 3.4, r(1, 18), math.sin(angle) * 3.4), r(3, 6), landmarkModel)
end

local ceiling = Instance.new("Part")
ceiling.Name = "Ceiling"
ceiling.Size = Vector3.new(N * CELL + 24, 2, N * CELL + 24)
ceiling.CFrame = CFrame.new(ORIGIN + Vector3.new(0, H + 1, 0))
style(ceiling, fleshColor(0.45))
ceiling.CanCollide = true
ceiling.Parent = ceilingModel
for i = 0, N - 1 do
	for j = 0, N - 1 do
		for _ = 1, rng:NextInteger(0, 2) do
			local d = r(4, 10)
			ball(cellCenter(i, j) + Vector3.new(r(-8, 8), H + d / 2 - r(1, 2.8), r(-8, 8)), d, ceilingModel, 0.5)
		end
	end
end

local floor = Instance.new("Part")
floor.Name = "FleshFloor"
floor.Size = Vector3.new(N * CELL + 24, 2, N * CELL + 24)
floor.CFrame = CFrame.new(ORIGIN + Vector3.new(0, -1, 0))
style(floor, fleshColor(0.35))
floor.CanCollide = true
floor.CanQuery = true
floor.Parent = floorModel

for _, room in ROOMS do
	local a = cellCenter(room.i0, room.j0)
	local b = cellCenter(room.i1, room.j1)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RoomFill_" .. room.name
	attachment.Position = ceiling.CFrame:PointToObjectSpace((a + b) / 2 + Vector3.new(0, H - 4, 0))
	attachment.Parent = ceiling
	local light = Instance.new("PointLight")
	light.Name = "SoftRoomFill"
	light.Color = Color3.fromRGB(220, 140, 146)
	light.Brightness = if room.name == "EntranceHall" then 0.35 else 0.9
	light.Range = 60
	light.Shadows = false
	light.Parent = attachment
end

local spawn = spawnTemplate
spawn.Name = "MazeEntrance"
local start = cellCenter(6, 12) + Vector3.new(0, 0.5, 4)
spawn.CFrame = CFrame.lookAt(start, start - Vector3.zAxis)
spawn.Parent = root

root:SetAttribute("BuildVersion", 3)
root:SetAttribute("Seed", SEED)
root:SetAttribute("Origin", ORIGIN)
root:SetAttribute("CellSize", CELL)
root:SetAttribute("GridSize", N)
root:SetAttribute("WallHeight", H)
root:SetAttribute("Footprint", string.format("%d x %d studs", N * CELL, N * CELL))
root:SetAttribute("FleshVariant", variant.Name)
root:SetAttribute("Design", "Seeded braided maze with a sealed TV entrance hall, signal court totem, receiver static wall, two galleries, four hollows")
root.Parent = workspace

terrain:FillBlock(CFrame.new(ORIGIN + Vector3.new(0, 0.65, 0)), Vector3.new(N * CELL + 8, 1.3, N * CELL + 8), Enum.Material.Water)
terrain.WaterColor = Color3.fromRGB(46, 12, 14)
terrain.WaterReflectance = 1
terrain.WaterTransparency = 0.35
terrain.WaterWaveSize = 0.05
terrain.WaterWaveSpeed = 3

Lighting.Ambient = Color3.fromRGB(92, 62, 70)
Lighting.OutdoorAmbient = Color3.fromRGB(20, 11, 14)
Lighting.Brightness = 0
Lighting.ClockTime = 0
Lighting.ExposureCompensation = 0.55
Lighting.EnvironmentDiffuseScale = 0.2
Lighting.EnvironmentSpecularScale = 1
Lighting.GlobalShadows = true
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Name = "SignalMaze_Haze"
atmosphere.Density = 0.36
atmosphere.Offset = 0
atmosphere.Color = Color3.fromRGB(74, 30, 36)
atmosphere.Decay = Color3.fromRGB(38, 12, 16)
atmosphere.Glare = 0
atmosphere.Haze = 1.6
atmosphere.Parent = Lighting
local bloom = Lighting:FindFirstChild("SignalMaze_ScreenBloom") or Instance.new("BloomEffect")
bloom.Name = "SignalMaze_ScreenBloom"
bloom.Intensity = 0.75
bloom.Size = 32
bloom.Threshold = 0.95
bloom.Parent = Lighting
local grade = Lighting:FindFirstChild("SignalMaze_Grade") or Instance.new("ColorCorrectionEffect")
grade.Name = "SignalMaze_Grade"
grade.Contrast = 0.12
grade.Saturation = 0.08
grade.TintColor = Color3.fromRGB(255, 236, 236)
grade.Parent = Lighting
local depth = Lighting:FindFirstChild("SignalMaze_Depth") or Instance.new("DepthOfFieldEffect")
depth.Name = "SignalMaze_Depth"
depth.FarIntensity = 0.18
depth.FocusDistance = 45
depth.InFocusRadius = 60
depth.NearIntensity = 0
depth.Parent = Lighting

local counts = {parts = 0, meshes = 0, growths = 0, screens = screenCount, lights = 0, collision = #collisionModel:GetChildren()}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then counts.parts += 1 end
	if d:IsA("MeshPart") then counts.meshes += 1 end
	if d.Name == "Growth" then counts.growths += 1 end
	if d:IsA("Light") then counts.lights += 1 end
end
root:SetAttribute("PartCount", counts.parts)
root:SetAttribute("ScreenCount", counts.screens)
root:SetAttribute("LightCount", counts.lights)

workspace.CurrentCamera.CFrame = CFrame.lookAt(start + Vector3.new(0, 5, 2), start + Vector3.new(0, 7, -60))
workspace.CurrentCamera.Focus = CFrame.new(start + Vector3.new(0, 6, -30))
ChangeHistoryService:SetWaypoint("Rebuild Signal Maze v3")
return HttpService:JSONEncode(counts)
