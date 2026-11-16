local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20260927
local ROWS = {"Lower", "Middle", "Upper"}
local COLUMNS = {"Left", "Center", "Right"}
local WALL_STRENGTH = {z = 2.2, xy = 2, rot = 0.09}
local SCREEN_SINK = 0.7
local FOLD_STRENGTH = {z = 0.6, xy = 1, rot = 0.05}
local COLUMN_STRENGTH = {z = 0.9, xy = 1, rot = 0.05}
local PILLAR_STRENGTH = {z = 1.1, xy = 1.2, rot = 0.07}
local TOTEM_STRENGTH = {z = 0.35, xy = 0.3, rot = 0.03}
local FOLD_CHANCE = 0.3
local PILLARS = {
	{6, 1}, {7, 1}, {1, 5}, {1, 6}, {12, 7}, {12, 8}, {2, 1}, {11, 2}, {2, 11}, {10, 11},
}

assert(game.PlaceId == 126262358232325, "This refinement targets Map Creation")
local root = workspace:FindFirstChild("SignalMaze")
assert(root and root:GetAttribute("BuildVersion") == 3, "Expected the version 3 SignalMaze")
assert(not ServerStorage:FindFirstChild("SignalMaze_V4Backup"), "A version 4 backup already exists")
local v3Backup = ServerStorage:FindFirstChild("SignalMaze_V3Backup")
local v2 = v3Backup and v3Backup:FindFirstChild("SignalMaze")
local source = v2 and v2:FindFirstChild("BoneWalls") and v2.BoneWalls:FindFirstChildWhichIsA("MeshPart")
assert(source, "The rigged flesh wall in SignalMaze_V3Backup is required")
local variant = MaterialService:FindFirstChild("Flesh_WetFolds_V2")
assert(variant and variant:IsA("MaterialVariant"), "Flesh_WetFolds_V2 is required")

local ORIGIN = root:GetAttribute("Origin")
local CELL = root:GetAttribute("CellSize")
local N = root:GetAttribute("GridSize")
local H = root:GetAttribute("WallHeight")
local HALF = N * CELL / 2

local meshTemplate = source:Clone()
for _, child in meshTemplate:GetChildren() do
	if not child:IsA("Bone") then
		child:Destroy()
	end
end
for row = 1, 3 do
	for column = 1, 3 do
		assert(meshTemplate:FindFirstChild("Wall_" .. ROWS[row] .. "_" .. COLUMNS[column]), "Missing wall bone")
	end
end

ChangeHistoryService:SetWaypoint("Before Signal Maze v4")
local backup = Instance.new("Folder")
backup.Name = "SignalMaze_V4Backup"
for _, property in {"Ambient", "OutdoorAmbient", "ExposureCompensation"} do
	backup:SetAttribute(property, Lighting[property])
end
local terrain = workspace.Terrain
backup:SetAttribute("TerrainWaterColor", terrain.WaterColor)
local oldLighting = Instance.new("Folder")
oldLighting.Name = "Lighting"
oldLighting.Parent = backup
for _, child in Lighting:GetChildren() do
	child:Clone().Parent = oldLighting
end
root:Clone().Parent = backup
backup.Parent = ServerStorage

local rng = Random.new(SEED)
local function r(a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end
local function chance(p: number): boolean
	return rng:NextNumber() < p
end

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
end

local function collisionBox(name: string, size: Vector3, cframe: CFrame, parent: Instance)
	local box = Instance.new("Part")
	box.Name = name
	box.Size = size
	box.CFrame = cframe
	box.Anchored = true
	box.CanCollide = true
	box.CanTouch = false
	box.CanQuery = true
	box.CastShadow = false
	box.Transparency = 1
	box.Parent = parent
end

type Rig = {
	mesh: MeshPart,
	size: Vector3,
	binds: { CFrame },
	poses: { CFrame },
}

local baseRigs: { Rig } = {}
local rigCount = 0

local function buildRig(name: string, size: Vector3, cframe: CFrame, strength, parent: Instance, shade: number?): Rig
	rigCount += 1
	local model = Instance.new("Model")
	model.Name = string.format("%s_%03d", name, rigCount)
	local mesh = meshTemplate:Clone()
	mesh.Name = "Wall"
	mesh.Size = size
	mesh.CFrame = cframe
	style(mesh, fleshColor(shade))
	local rig: Rig = {mesh = mesh, size = size, binds = {}, poses = {}}
	for row = 0, 2 do
		for column = 0, 2 do
			local index = row * 3 + column + 1
			local bind = CFrame.new((column - 1) * size.X * 0.4, (row - 1) * size.Y * 0.4, 0)
			local endColumn = column ~= 1
			local endRow = row ~= 1
			local dz = r(-1, 1) * strength.z * (if endColumn then 0.45 else 1) * (if endRow then 0.75 else 1)
			local dx = if endColumn then 0 else r(-1, 1) * strength.xy
			local dy = if endRow then 0 else r(-1, 1) * strength.xy
			local pose = CFrame.new(bind.Position + Vector3.new(dx, dy, dz)) * CFrame.Angles(r(-1, 1) * strength.rot, r(-1, 1) * strength.rot, r(-1, 1) * strength.rot)
			local bone = mesh:FindFirstChild("Wall_" .. ROWS[row + 1] .. "_" .. COLUMNS[column + 1]) :: Bone
			bone.CFrame = pose
			rig.binds[index] = bind
			rig.poses[index] = pose
		end
	end
	mesh.Parent = model
	model.PrimaryPart = mesh
	local controller = Instance.new("AnimationController")
	controller.Name = "AnimationController"
	Instance.new("Animator").Parent = controller
	controller.Parent = model
	model:SetAttribute("BoneCount", 9)
	model.Parent = parent
	return rig
end

local function deform(rig: Rig, v: Vector3): Vector3
	local gx = math.clamp(v.X / (rig.size.X * 0.4) + 1, 0, 2)
	local gy = math.clamp(v.Y / (rig.size.Y * 0.4) + 1, 0, 2)
	local x0 = math.min(math.floor(gx), 1)
	local y0 = math.min(math.floor(gy), 1)
	local tx = gx - x0
	local ty = gy - y0
	local ids = {y0 * 3 + x0 + 1, y0 * 3 + x0 + 2, (y0 + 1) * 3 + x0 + 1, (y0 + 1) * 3 + x0 + 2}
	local weights = {(1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty}
	local sum = Vector3.zero
	for k = 1, 4 do
		sum += (rig.poses[ids[k]] * rig.binds[ids[k]]:Inverse() * v) * weights[k]
	end
	return sum
end

local function surfaceShift(point: Vector3, normal: Vector3): Vector3
	local best: Rig? = nil
	local bestLocal = Vector3.zero
	local bestDepth = math.huge
	for _, rig in baseRigs do
		local p = rig.mesh.CFrame:PointToObjectSpace(point)
		local depth = math.abs(p.Z)
		if math.abs(p.X) <= rig.size.X / 2 and math.abs(p.Y) <= rig.size.Y / 2 and depth <= rig.size.Z / 2 + 4 and depth < bestDepth then
			best = rig
			bestLocal = p
			bestDepth = depth
		end
	end
	if not best then
		return Vector3.zero
	end
	local side = if best.mesh.CFrame:VectorToObjectSpace(normal).Z >= 0 then 1 else -1
	local surface = Vector3.new(bestLocal.X, bestLocal.Y, side * best.size.Z / 2)
	return best.mesh.CFrame:VectorToWorldSpace(deform(best, surface) - surface)
end

for _, part in root:GetDescendants() do
	if part.Name == "Growth" then
		part:Destroy()
	end
end
local growths = root:FindFirstChild("FleshGrowths")
if growths then
	growths:Destroy()
end

local wallsModel = root:FindFirstChild("FleshWalls")
local oldWalls = {}
for _, mesh in wallsModel:GetChildren() do
	if mesh:IsA("MeshPart") then
		table.insert(oldWalls, {cframe = mesh.CFrame, size = mesh.Size})
		mesh:Destroy()
	end
end
table.sort(oldWalls, function(a, b)
	local pa = a.cframe.Position
	local pb = b.cframe.Position
	if pa.X ~= pb.X then
		return pa.X < pb.X
	end
	return pa.Z < pb.Z
end)
for _, record in oldWalls do
	table.insert(baseRigs, buildRig("FleshWall", record.size, record.cframe, WALL_STRENGTH, wallsModel))
end

local collisionModel = root:FindFirstChild("Collision")
local runBoxes = {}
for _, box in collisionModel:GetChildren() do
	if box:IsA("BasePart") then
		table.insert(runBoxes, box)
	end
end

local columnModel = root:FindFirstChild("FleshColumns")
local columnSpots = {}
for _, part in columnModel:GetChildren() do
	if part:IsA("BasePart") and part.Name == "FleshColumn" then
		table.insert(columnSpots, {position = Vector3.new(part.Position.X, 0, part.Position.Z), diameter = part.Size.Y})
	end
end
columnModel:ClearAllChildren()
table.sort(columnSpots, function(a, b)
	if a.position.X ~= b.position.X then
		return a.position.X < b.position.X
	end
	return a.position.Z < b.position.Z
end)

local pillarSet = {}
for _, pillar in PILLARS do
	local p = ORIGIN + Vector3.new(pillar[1] * CELL - HALF, 0, pillar[2] * CELL - HALF)
	pillarSet[math.floor(p.X + 0.5) .. ":" .. math.floor(p.Z + 0.5)] = true
end

local function vertexRole(position: Vector3): string
	if pillarSet[math.floor(position.X + 0.5) .. ":" .. math.floor(position.Z + 0.5)] then
		return "pillar"
	end
	local through = false
	for _, box in runBoxes do
		local p = box.CFrame:PointToObjectSpace(position + Vector3.new(0, H / 2, 0))
		local alongX = box.Size.X > box.Size.Z
		local along = if alongX then p.X else p.Z
		local across = if alongX then p.Z else p.X
		local halfLength = (if alongX then box.Size.X else box.Size.Z) / 2
		if math.abs(across) < 1 and math.abs(along) <= halfLength then
			if halfLength - math.abs(along) < 6 then
				return "joint"
			end
			through = true
		end
	end
	return if through then "straight" else "joint"
end

local droppedColumns = 0
for _, spot in columnSpots do
	local role = vertexRole(spot.position)
	if role == "straight" then
		droppedColumns += 1
	elseif role == "pillar" then
		local yaw = r(0, math.pi)
		for k = 0, 1 do
			local size = Vector3.new(spot.diameter * r(1.2, 1.35), H + 2, spot.diameter * r(0.75, 0.9))
			buildRig("FleshPillar", size, CFrame.new(spot.position + Vector3.new(0, H / 2, 0)) * CFrame.Angles(0, yaw + k * math.pi / 2 + r(-0.2, 0.2), 0), PILLAR_STRENGTH, columnModel)
		end
		collisionBox("Pillar_Collision", Vector3.new(spot.diameter * 0.9, H, spot.diameter * 0.9), CFrame.new(spot.position + Vector3.new(0, H / 2, 0)), collisionModel)
	else
		local size = Vector3.new(spot.diameter * r(1.05, 1.2), H + 2, spot.diameter * r(0.9, 1))
		buildRig("FleshColumn", size, CFrame.new(spot.position + Vector3.new(0, H / 2, 0)) * CFrame.Angles(0, math.rad(45 + r(-15, 15)), 0), COLUMN_STRENGTH, columnModel)
		collisionBox("Column_Collision", Vector3.new(8.5, H, 8.5), CFrame.new(spot.position + Vector3.new(0, H / 2, 0)), collisionModel)
	end
end

local landmarks = root:FindFirstChild("Landmarks")
local totem = landmarks:FindFirstChild("SignalTotem")
local totemCenter = totem.Position
totem:Destroy()
for k = 0, 1 do
	buildRig("SignalTotem", Vector3.new(6.6, 21, 6.6), CFrame.new(Vector3.new(totemCenter.X, 10, totemCenter.Z)) * CFrame.Angles(0, k * math.pi / 4, 0), TOTEM_STRENGTH, landmarks, 0.95)
end
collisionBox("SignalTotem_Collision", Vector3.new(7.5, 20, 7.5), CFrame.new(Vector3.new(totemCenter.X, 10, totemCenter.Z)), landmarks)

local screenModel = root:FindFirstChild("EmbeddedTVs")
local screens = {}
for _, model in screenModel:GetChildren() do
	local anchor = model:FindFirstChild("Housing") or model:FindFirstChild("Bezel")
	if model:IsA("Model") and anchor and anchor:IsA("BasePart") then
		local look = anchor.CFrame.LookVector
		local normal = Vector3.new(look.X, 0, look.Z).Unit
		table.insert(screens, {model = model, anchor = anchor, normal = normal})
	end
end
table.sort(screens, function(a, b)
	return a.model.Name < b.model.Name
end)
local reseated = 0
for _, screen in screens do
	if string.find(screen.model.Name, "Totem") then
		screen.model:PivotTo(screen.model:GetPivot() + screen.normal * 1.1)
	else
		local shift = surfaceShift(screen.anchor.Position, screen.normal)
		screen.model:PivotTo(screen.model:GetPivot() + shift - screen.normal * SCREEN_SINK)
		reseated += 1
	end
end

local folds = 0
for _, rig in table.clone(baseRigs) do
	for _, side in {1, -1} do
		local mesh = rig.mesh
		local outward = mesh.CFrame:VectorToWorldSpace(Vector3.new(0, 0, side))
		local probe = mesh.Position + outward * (rig.size.Z / 2 + 3)
		local inside = math.abs(probe.X - ORIGIN.X) < HALF - 1 and math.abs(probe.Z - ORIGIN.Z) < HALF - 1
		local length = r(10, 16)
		if inside and rig.size.X > length + 2 and chance(FOLD_CHANCE) then
			local x = r(-(rig.size.X - length) / 2, (rig.size.X - length) / 2)
			local clear = true
			for _, screen in screens do
				local p = mesh.CFrame:PointToObjectSpace(screen.anchor.Position)
				if p.Z * side > 0 and math.abs(p.X - x) < length / 2 + 3 then
					clear = false
					break
				end
			end
			if clear then
				local height = r(12, 24)
				local thickness = r(3, 4)
				local y = r(-rig.size.Y / 2 + height / 2 - 1, rig.size.Y / 2 - height / 2 + 1)
				local surface = Vector3.new(x, y, side * rig.size.Z / 2)
				local bulge = (deform(rig, surface) - surface).Z
				local z = side * (rig.size.Z / 2 + r(0, 0.5) - thickness / 2) + bulge
				local cframe = mesh.CFrame * CFrame.new(x, y, z) * CFrame.Angles(0, r(-0.14, 0.14), r(-0.2, 0.2))
				buildRig("FleshFold", Vector3.new(length, height, thickness), cframe, FOLD_STRENGTH, wallsModel, 0.95)
				folds += 1
			end
		end
	end
end

local red = Color3.fromRGB(255, 66, 57)
local softRed = Color3.fromRGB(240, 104, 96)
for _, d in root:GetDescendants() do
	if d:IsA("SurfaceLight") and d.Color == red then
		d.Color = softRed
	elseif d:IsA("PointLight") and d.Name == "SoftRoomFill" then
		d.Color = Color3.fromRGB(205, 170, 172)
	end
end
Lighting.Ambient = Color3.fromRGB(88, 72, 78)
Lighting.OutdoorAmbient = Color3.fromRGB(20, 15, 17)
local atmosphere = Lighting:FindFirstChild("SignalMaze_Haze")
if atmosphere and atmosphere:IsA("Atmosphere") then
	atmosphere.Color = Color3.fromRGB(62, 42, 46)
	atmosphere.Decay = Color3.fromRGB(34, 20, 23)
end
local grade = Lighting:FindFirstChild("SignalMaze_Grade")
if grade and grade:IsA("ColorCorrectionEffect") then
	grade.Saturation = -0.18
	grade.Contrast = 0.1
	grade.TintColor = Color3.fromRGB(255, 246, 246)
end
terrain.WaterColor = Color3.fromRGB(36, 22, 24)

local counts = {parts = 0, fleshMeshes = 0, bones = 0, folds = folds, reseatedScreens = reseated, droppedStraightColumns = droppedColumns, growthsLeft = 0}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then counts.parts += 1 end
	if d:IsA("MeshPart") and d.Name == "Wall" then counts.fleshMeshes += 1 end
	if d:IsA("Bone") then counts.bones += 1 end
	if d.Name == "Growth" then counts.growthsLeft += 1 end
end
root:SetAttribute("BuildVersion", 4)
root:SetAttribute("PartCount", counts.parts)
root:SetAttribute("BoneCount", counts.bones)
root:SetAttribute("Design", "Seeded braided maze of bone-rigged flesh walls, folds, and columns with embedded TVs; no sphere growths")
ChangeHistoryService:SetWaypoint("Refine Signal Maze v4")
return HttpService:JSONEncode(counts)
