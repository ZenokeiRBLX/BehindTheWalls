local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20261001
local ROWS = {"Lower", "Middle", "Upper"}
local COLUMNS = {"Left", "Center", "Right"}
local TAG = "MonsterTV"
local SPAWN_NAME = "MonsterSpawn"
local SPAWN_DISTANCE = 2.5
local SCALE_RANGE = {1.8, 2.6}
local SECOND_SCALE_RANGE = {1, 1.5}
local SECOND_CHANCE = 0.35
local HEIGHT_RATIO = 1.1
local DEPTH_SCALE = 1.3
local MAX_WIDTH = 12.5
local EDGE_LIMIT = 10.5
local CEILING_CLEARANCE = 2
local BOTTOM_RANGE = {1.3, 2.2}
local FRONT_CLEARANCE = 0.35
local RED_CHANCE = 0.55
local CANVAS = Vector2.new(320, 250)
local MAX_DISTANCE = 120
local LIGHT_BUDGET = 70
local LIGHT_COLOR = Color3.fromRGB(240, 104, 96)
local TOTEM_SCALE = 1.8
local TOTEM_COLLISION = 10

assert(game.PlaceId == 126262358232325, "This pass targets Map Creation")
local root = workspace:FindFirstChild("SignalMaze")
assert(root and root:GetAttribute("BuildVersion") == 6, "Expected the version 6 SignalMaze")
assert(not ServerStorage:FindFirstChild("SignalMaze_V7Backup"), "A version 7 backup already exists")

local ORIGIN = root:GetAttribute("Origin")
local CELL = root:GetAttribute("CellSize")
local N = root:GetAttribute("GridSize")
local H = root:GetAttribute("WallHeight")
local HALF = N * CELL / 2
local screenModel = root:FindFirstChild("EmbeddedTVs")

ChangeHistoryService:SetWaypoint("Before Signal Maze v7 sized TVs")
local backup = Instance.new("Folder")
backup.Name = "SignalMaze_V7Backup"
root:Clone().Parent = backup
backup.Parent = ServerStorage

local rng = Random.new(SEED)
local function r(a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end

local names = {}
for _, model in screenModel:GetChildren() do
	table.insert(names, model.Name)
end
table.sort(names)
local redTemplate
local staticTemplate
for _, name in names do
	local model = screenModel:FindFirstChild(name)
	local glass = model and model:FindFirstChild("BroadcastGlass")
	local signal = glass and glass:FindFirstChild("Signal")
	local content = signal and signal:FindFirstChildWhichIsA("ImageLabel")
	if content and model:FindFirstChild("Housing") then
		if content.Name == "RedSilhouette" and not redTemplate then
			redTemplate = model:Clone()
		elseif content.Name == "Static" and not staticTemplate then
			staticTemplate = model:Clone()
		end
	end
end
assert(redTemplate and staticTemplate, "Both broadcast styles are required")
for _, template in {redTemplate, staticTemplate} do
	template:ScaleTo(1)
	for _, d in template:GetDescendants() do
		if d:IsA("Light") or d.Name == SPAWN_NAME then
			d:Destroy()
		end
	end
	for name in template:GetAttributes() do
		template:SetAttribute(name, nil)
	end
	CollectionService:RemoveTag(template, TAG)
end
local baseHousing = redTemplate.Housing.Size
local glassOffset = redTemplate.Housing.CFrame:ToObjectSpace(redTemplate.BroadcastGlass.CFrame)
local baseGlass = redTemplate.BroadcastGlass.Size

screenModel:ClearAllChildren()
local foldCount = 0
for _, model in root.FleshWalls:GetChildren() do
	if string.find(model.Name, "^FleshFold_") then
		model:Destroy()
		foldCount += 1
	end
end

type Rig = {
	cframe: CFrame,
	size: Vector3,
	binds: { CFrame },
	poses: { CFrame },
}

local rigs: { Rig } = {}
for _, model in root.FleshWalls:GetChildren() do
	local mesh = model:FindFirstChild("Wall")
	if model:IsA("Model") and mesh and mesh:IsA("MeshPart") and string.find(model.Name, "^FleshWall_") then
		local rig: Rig = {cframe = mesh.CFrame, size = mesh.Size, binds = {}, poses = {}}
		for row = 0, 2 do
			for column = 0, 2 do
				local index = row * 3 + column + 1
				rig.binds[index] = CFrame.new((column - 1) * mesh.Size.X * 0.4, (row - 1) * mesh.Size.Y * 0.4, 0)
				rig.poses[index] = (mesh:FindFirstChild("Wall_" .. ROWS[row + 1] .. "_" .. COLUMNS[column + 1]) :: Bone).CFrame
			end
		end
		table.insert(rigs, rig)
	end
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

local function surfaceDistance(point: Vector3, center: Vector3, normal: Vector3): number?
	local best: Rig? = nil
	local bestLocal = Vector3.zero
	local bestDepth = math.huge
	for _, rig in rigs do
		local p = rig.cframe:PointToObjectSpace(point)
		local depth = math.abs(p.Z)
		if math.abs(p.X) <= rig.size.X / 2 and math.abs(p.Y) <= rig.size.Y / 2 and depth <= rig.size.Z / 2 and depth < bestDepth then
			best = rig
			bestLocal = p
			bestDepth = depth
		end
	end
	if not best then
		return nil
	end
	local side = if best.cframe:VectorToObjectSpace(normal).Z >= 0 then 1 else -1
	local surface = best.cframe * deform(best, Vector3.new(bestLocal.X, bestLocal.Y, side * best.size.Z / 2))
	return (surface - center):Dot(normal)
end

local lightBudget = LIGHT_BUDGET
local built = 0

local function buildTv(red: boolean, scale: number, name: string): Model
	local model = (if red then redTemplate else staticTemplate):Clone()
	local housing = model.Housing
	local glass = model.BroadcastGlass
	local housingSize = Vector3.new(baseHousing.X * scale, baseHousing.Y * scale * HEIGHT_RATIO, baseHousing.Z * DEPTH_SCALE)
	local origin = housing.CFrame
	housing.Size = housingSize
	glass.Size = Vector3.new(baseGlass.X * scale, baseGlass.Y * scale * HEIGHT_RATIO, baseGlass.Z)
	glass.CFrame = origin * CFrame.new(glassOffset.X * scale, glassOffset.Y * scale * HEIGHT_RATIO, -(housingSize.Z / 2 + 0.03)) * glassOffset.Rotation
	local signal = glass:FindFirstChild("Signal")
	if signal and signal:IsA("SurfaceGui") then
		signal.CanvasSize = CANVAS
		signal.MaxDistance = MAX_DISTANCE
	end
	for _, part in {housing, glass} do
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
	end
	if red and lightBudget > 0 then
		lightBudget -= 1
		local light = Instance.new("SurfaceLight")
		light.Name = "ScreenSpill"
		light.Face = Enum.NormalId.Front
		light.Angle = 120
		light.Range = r(20, 26)
		light.Brightness = r(1, 1.3)
		light.Color = LIGHT_COLOR
		light.Shadows = false
		light.Parent = glass
	end
	built += 1
	model.Name = string.format("G%03d_%s", built, name)
	model:SetAttribute("TvScale", math.floor(scale * 100 + 0.5) / 100)
	model:SetAttribute("ScreenSize", Vector2.new(glass.Size.X, glass.Size.Y))
	return model
end

local function place(model: Model, front: Vector3, normal: Vector3, tilt: CFrame)
	local housing = model.Housing
	local position = front - normal * housing.Size.Z / 2
	model:PivotTo(CFrame.lookAt(position, position + normal) * tilt * housing.CFrame:Inverse() * model:GetPivot())
	local current = housing.Position + housing.CFrame.LookVector * housing.Size.Z / 2
	model:PivotTo(model:GetPivot() + (front - current))
	model.Parent = screenModel
end

local edges = {}
for _, box in root.Collision:GetChildren() do
	local kind, line, first, last = string.match(box.Name, "^([VH])(%d+)_(%d+)_(%d+)$")
	if kind then
		for k = tonumber(first), tonumber(last) do
			table.insert(edges, {kind = kind, line = tonumber(line), k = k})
		end
	end
end
table.sort(edges, function(a, b)
	if a.kind ~= b.kind then
		return a.kind < b.kind
	end
	if a.line ~= b.line then
		return a.line < b.line
	end
	return a.k < b.k
end)

local faces = 0
local seconds = 0
local lift = {max = 0}

local function mountTv(center: Vector3, along: Vector3, normal: Vector3, offset: number, centerY: number, scale: number, red: boolean, name: string)
	local tilt = CFrame.Angles(math.rad(r(-2, 3)), math.rad(r(-3, 3)), math.rad(r(-2.5, 2.5)))
	local faceCenter = center + along * offset
	local frontDistance = 3.4
	local screenWidth = baseGlass.X * scale
	local screenHeight = baseGlass.Y * scale * HEIGHT_RATIO
	for u = -1, 1 do
		for v = -1, 1 do
			local point = faceCenter + along * (u * screenWidth / 2 + glassOffset.X * scale) + Vector3.yAxis * (centerY + v * screenHeight / 2 + glassOffset.Y * scale * HEIGHT_RATIO)
			local distance = surfaceDistance(point, center, normal)
			if distance then
				frontDistance = math.max(frontDistance, distance + FRONT_CLEARANCE)
			end
		end
	end
	lift.max = math.max(lift.max, frontDistance)
	local model = buildTv(red, scale, name)
	place(model, faceCenter + Vector3.yAxis * centerY + normal * frontDistance, normal, tilt)
end
for _, edge in edges do
	local a
	local b
	if edge.kind == "V" then
		a = ORIGIN + Vector3.new(edge.line * CELL - HALF, 0, edge.k * CELL - HALF)
		b = a + Vector3.new(0, 0, CELL)
	else
		a = ORIGIN + Vector3.new(edge.k * CELL - HALF, 0, edge.line * CELL - HALF)
		b = a + Vector3.new(CELL, 0, 0)
	end
	local center = (a + b) / 2
	local along = (b - a).Unit
	local across = Vector3.new(along.Z, 0, -along.X)
	for _, normal in {across, -across} do
		local probe = center + normal * 6
		if math.abs(probe.X - ORIGIN.X) < HALF and math.abs(probe.Z - ORIGIN.Z) < HALF then
			faces += 1
			local name = edge.kind .. edge.line .. "_" .. edge.k
			local scale = math.min(r(SCALE_RANGE[1], SCALE_RANGE[2]), MAX_WIDTH / baseHousing.X)
			local height = baseHousing.Y * scale * HEIGHT_RATIO
			local offset = r(-1.5, 1.5)
			local centerY = r(BOTTOM_RANGE[1], BOTTOM_RANGE[2]) + height / 2
			mountTv(center, along, normal, offset, centerY, scale, rng:NextNumber() < RED_CHANCE, name)
			if rng:NextNumber() < SECOND_CHANCE then
				local second = r(SECOND_SCALE_RANGE[1], SECOND_SCALE_RANGE[2])
				local secondHeight = baseHousing.Y * second * HEIGHT_RATIO
				local secondWidth = baseHousing.X * second
				local secondOffset = r(-6, 6)
				local secondY = centerY + height / 2 + 1 + secondHeight / 2 + r(0, 3)
				local red = rng:NextNumber() < RED_CHANCE
				if math.abs(secondOffset) + secondWidth / 2 <= EDGE_LIMIT and secondY + secondHeight / 2 <= H - CEILING_CLEARANCE then
					mountTv(center, along, normal, secondOffset, secondY, second, red, name .. "_Upper")
					seconds += 1
				end
			end
		end
	end
end

local landmarks = root:FindFirstChild("Landmarks")
local totemCollision = landmarks:FindFirstChild("SignalTotem_Collision")
local totemCenter = if totemCollision then totemCollision.Position else ORIGIN
if totemCollision and totemCollision:IsA("BasePart") then
	totemCollision.Size = Vector3.new(TOTEM_COLLISION, totemCollision.Size.Y, TOTEM_COLLISION)
end
local totemHeight = baseHousing.Y * TOTEM_SCALE * HEIGHT_RATIO
for k = 0, 3 do
	local yaw = math.rad(k * 90)
	local normal = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local model = buildTv(k % 2 == 0, TOTEM_SCALE, "Totem_" .. k)
	local front = Vector3.new(totemCenter.X, 1.4 + totemHeight / 2, totemCenter.Z) + normal * (baseHousing.X * TOTEM_SCALE / 2 + 0.5)
	place(model, front, normal, CFrame.identity)
end

local names2 = {}
for _, model in screenModel:GetChildren() do
	table.insert(names2, model.Name)
end
table.sort(names2)
for index, name in names2 do
	local model = screenModel:FindFirstChild(name) :: Model
	local glass = model:FindFirstChild("BroadcastGlass") :: BasePart
	local spawn = Instance.new("Attachment")
	spawn.Name = SPAWN_NAME
	spawn.Parent = glass
	local look = glass.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	local worldPosition = glass.Position + flat * SPAWN_DISTANCE
	spawn.WorldCFrame = CFrame.lookAt(worldPosition, worldPosition + flat)
	CollectionService:AddTag(model, TAG)
	model:SetAttribute("SpawnIndex", index)
end

local counts = {screens = #screenModel:GetChildren(), faces = faces, upperTvs = seconds, foldsRemoved = foldCount, maxFront = math.floor(lift.max * 100) / 100, lights = 0, parts = 0, tagged = #CollectionService:GetTagged(TAG)}
for _, d in root:GetDescendants() do
	if d:IsA("Light") then counts.lights += 1 end
	if d:IsA("BasePart") then counts.parts += 1 end
end
root:SetAttribute("BuildVersion", 7)
root:SetAttribute("ScreenCount", counts.screens)
root:SetAttribute("PartCount", counts.parts)
root:SetAttribute("LightCount", counts.lights)
ChangeHistoryService:SetWaypoint("Sized Signal Maze TVs v7")
return HttpService:JSONEncode(counts)
