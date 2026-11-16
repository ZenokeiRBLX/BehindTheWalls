local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20260929
local ROWS = {"Lower", "Middle", "Upper"}
local COLUMNS = {"Left", "Center", "Right"}
local TAG = "MonsterTV"
local SPAWN_NAME = "MonsterSpawn"
local SPAWN_DISTANCE = 2.5
local SCREEN_SINK = 0.7
local CANVAS = Vector2.new(256, 200)
local MAX_DISTANCE = 110
local RED_CHANCE = 0.55
local EXTRA_CHANCE = 0.33
local MIN_SCALE = 0.55
local FLOOR_CLEARANCE = 1.5
local CEILING_CLEARANCE = 1.5
local EDGE_LIMIT = 10.5
local GAP = 0.3

assert(game.PlaceId == 126262358232325, "This pass targets Map Creation")
local root = workspace:FindFirstChild("SignalMaze")
assert(root and root:GetAttribute("BuildVersion") == 5, "Expected the version 5 SignalMaze")
assert(not ServerStorage:FindFirstChild("SignalMaze_V6Backup"), "A version 6 backup already exists")

local ORIGIN = root:GetAttribute("Origin")
local CELL = root:GetAttribute("CellSize")
local N = root:GetAttribute("GridSize")
local H = root:GetAttribute("WallHeight")
local HALF = N * CELL / 2
local screenModel = root:FindFirstChild("EmbeddedTVs")

ChangeHistoryService:SetWaypoint("Before Signal Maze v6")
local backup = Instance.new("Folder")
backup.Name = "SignalMaze_V6Backup"
root:Clone().Parent = backup
backup.Parent = ServerStorage

local rng = Random.new(SEED)
local function r(a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end

local function pickScale(): number
	local roll = rng:NextNumber()
	if roll < 0.28 then
		return r(MIN_SCALE, 0.8)
	elseif roll < 0.72 then
		return r(0.85, 1.15)
	end
	return r(1.3, 2)
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
	if content and not string.find(name, "Totem") and string.sub(name, 1, 1) == "S" then
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
end

type Rig = {
	cframe: CFrame,
	size: Vector3,
	binds: { CFrame },
	poses: { CFrame },
}

local rigs: { Rig } = {}
local folds = {}
for _, model in root.FleshWalls:GetChildren() do
	local mesh = model:FindFirstChild("Wall")
	if model:IsA("Model") and mesh and mesh:IsA("MeshPart") then
		if string.find(model.Name, "^FleshWall_") then
			local rig: Rig = {cframe = mesh.CFrame, size = mesh.Size, binds = {}, poses = {}}
			for row = 0, 2 do
				for column = 0, 2 do
					local index = row * 3 + column + 1
					rig.binds[index] = CFrame.new((column - 1) * mesh.Size.X * 0.4, (row - 1) * mesh.Size.Y * 0.4, 0)
					rig.poses[index] = (mesh:FindFirstChild("Wall_" .. ROWS[row + 1] .. "_" .. COLUMNS[column + 1]) :: Bone).CFrame
				end
			end
			table.insert(rigs, rig)
		elseif string.find(model.Name, "^FleshFold_") then
			table.insert(folds, {cframe = mesh.CFrame, size = mesh.Size})
		end
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

local function surfaceShift(point: Vector3, normal: Vector3): Vector3
	local best: Rig? = nil
	local bestLocal = Vector3.zero
	local bestDepth = math.huge
	for _, rig in rigs do
		local p = rig.cframe:PointToObjectSpace(point)
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
	local side = if best.cframe:VectorToObjectSpace(normal).Z >= 0 then 1 else -1
	local surface = Vector3.new(bestLocal.X, bestLocal.Y, side * best.size.Z / 2)
	return best.cframe:VectorToWorldSpace(deform(best, surface) - surface)
end

local function behindFold(point: Vector3, normal: Vector3, radius: number): boolean
	for _, fold in folds do
		local p = fold.cframe:PointToObjectSpace(point)
		local facing = fold.cframe:VectorToObjectSpace(normal)
		if math.abs(p.X) < fold.size.X / 2 + radius + 1 and math.abs(p.Y) < fold.size.Y / 2 + radius + 1 and math.abs(p.Z) < 8 and math.abs(facing.Z) > 0.5 then
			return true
		end
	end
	return false
end

local function faceOffset(point: Vector3, normal: Vector3): number
	local u = if math.abs(normal.X) > math.abs(normal.Z) then point.Z - (ORIGIN.Z - HALF) else point.X - (ORIGIN.X - HALF)
	return u - math.floor(u / CELL) * CELL - CELL / 2
end

type Record = {
	model: Model?,
	front: Vector3,
	normal: Vector3,
	radius: number,
}

local records: { Record } = {}

local function overlaps(front: Vector3, normal: Vector3, radius: number, ignore: Record?): boolean
	for _, other in records do
		if other ~= ignore and other.normal:Dot(normal) > 0.5 then
			local offset = other.front - front
			local depth = offset:Dot(normal)
			local planar = (offset - normal * depth).Magnitude
			if math.abs(depth) < 3 and planar < radius + other.radius + GAP then
				return true
			end
		end
	end
	return false
end

local function tvRadius(housing: BasePart): number
	return 0.5 * math.sqrt(housing.Size.X ^ 2 + housing.Size.Y ^ 2) * 0.9
end

local tvs = {}
for _, name in names do
	local model = screenModel:FindFirstChild(name)
	local housing = model and model:FindFirstChild("Housing")
	local bezel = model and model:FindFirstChild("Bezel")
	if model and model:IsA("Model") and housing and housing:IsA("BasePart") then
		local look = housing.CFrame.LookVector
		local normal = Vector3.new(look.X, 0, look.Z).Unit
		local record: Record = {model = model, front = housing.Position + look * housing.Size.Z / 2, normal = normal, radius = tvRadius(housing)}
		table.insert(records, record)
		if not string.find(name, "Totem") then
			table.insert(tvs, record)
		end
	elseif model and bezel and bezel:IsA("BasePart") then
		local look = bezel.CFrame.LookVector
		table.insert(records, {model = model, front = bezel.Position + look * bezel.Size.Z / 2, normal = Vector3.new(look.X, 0, look.Z).Unit, radius = 0.5 * math.sqrt(bezel.Size.X ^ 2 + bezel.Size.Y ^ 2)})
	end
end

local function fits(front: Vector3, normal: Vector3, width: number, height: number, radius: number, ignore: Record?): boolean
	if front.Y - height / 2 < FLOOR_CLEARANCE or front.Y + height / 2 > H - CEILING_CLEARANCE then
		return false
	end
	if math.abs(faceOffset(front, normal)) + width / 2 > EDGE_LIMIT then
		return false
	end
	return not overlaps(front, normal, radius, ignore)
end

local function placeFront(model: Model, front: Vector3)
	local housing = model:FindFirstChild("Housing") :: BasePart
	local current = housing.Position + housing.CFrame.LookVector * housing.Size.Z / 2
	model:PivotTo(model:GetPivot() + (front - current))
end

local resized = {grown = 0, shrunk = 0, kept = 0}
for _, record in tvs do
	local model = record.model :: Model
	local housing = model:FindFirstChild("Housing") :: BasePart
	local baseScale = model:GetScale()
	local unitWidth = housing.Size.X / baseScale
	local unitHeight = housing.Size.Y / baseScale
	local target = pickScale()
	local chosen = baseScale
	local candidate = target
	for _ = 1, 12 do
		local width = unitWidth * candidate
		local height = unitHeight * candidate
		local front = record.front
		if front.Y - height / 2 < FLOOR_CLEARANCE then
			front += Vector3.yAxis * (FLOOR_CLEARANCE - (front.Y - height / 2))
		end
		local radius = 0.5 * math.sqrt(width ^ 2 + height ^ 2) * 0.9
		if fits(front, record.normal, width, height, radius, record) then
			chosen = candidate
			record.front = front
			break
		end
		if candidate > 1 then
			candidate = math.max(1, candidate - 0.1)
		elseif candidate < baseScale then
			break
		else
			candidate = math.max(MIN_SCALE, candidate - 0.1)
		end
	end
	if math.abs(chosen - baseScale) > 0.01 then
		model:ScaleTo(chosen)
		placeFront(model, record.front)
		if chosen > baseScale then
			resized.grown += 1
		else
			resized.shrunk += 1
		end
	else
		resized.kept += 1
	end
	record.radius = tvRadius(model:FindFirstChild("Housing") :: BasePart)
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

local added = 0
local function pickHeight(): number
	local roll = rng:NextNumber()
	if roll < 0.6 then
		return r(3, 9)
	elseif roll < 0.85 then
		return r(9, 16)
	end
	return r(16, H - 6)
end

local function addExtra(center: Vector3, along: Vector3, normal: Vector3, name: string): boolean
	for _ = 1, 10 do
		local scale = pickScale()
		local red = rng:NextNumber() < RED_CHANCE
		local offset = r(-8, 8)
		local height = pickHeight()
		local frontAt = r(3.9, 4.5)
		local tilt = CFrame.Angles(math.rad(r(-3, 6)), math.rad(r(-8, 8)), math.rad(r(-7, 7)))
		local template = if red then redTemplate else staticTemplate
		local width = template.Housing.Size.X * scale
		local tall = template.Housing.Size.Y * scale
		local radius = 0.5 * math.sqrt(width ^ 2 + tall ^ 2) * 0.9
		local surfacePoint = center + along * offset + Vector3.yAxis * height
		local front = surfacePoint + normal * frontAt
		front += surfaceShift(surfacePoint + normal * 2.5, normal) - normal * SCREEN_SINK
		if fits(front, normal, width, tall, radius, nil) and not behindFold(surfacePoint, normal, radius) then
			local model = template:Clone()
			if math.abs(scale - 1) > 0.01 then
				model:ScaleTo(scale)
			end
			local housing = model.Housing
			local position = front - normal * housing.Size.Z / 2
			model:PivotTo(CFrame.lookAt(position, position + normal) * tilt * housing.CFrame:Inverse() * model:GetPivot())
			placeFront(model, front)
			added += 1
			model.Name = string.format("X%03d_%s", added, name)
			model.Parent = screenModel
			table.insert(records, {model = model, front = front, normal = normal, radius = tvRadius(housing)})
			return true
		end
	end
	return false
end

local extraAttempts = 0
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
		if math.abs(probe.X - ORIGIN.X) < HALF and math.abs(probe.Z - ORIGIN.Z) < HALF and rng:NextNumber() < EXTRA_CHANCE then
			extraAttempts += 1
			addExtra(center, along, normal, edge.kind .. edge.line .. "_" .. edge.k)
		end
	end
end

local tagged = 0
for index, name in (function()
	local list = {}
	for _, model in screenModel:GetChildren() do
		table.insert(list, model.Name)
	end
	table.sort(list)
	return list
end)() do
	local model = screenModel:FindFirstChild(name)
	local screen = model and (model:FindFirstChild("BroadcastGlass") or model:FindFirstChild("StaticScreen"))
	if model and model:IsA("Model") and screen and screen:IsA("BasePart") then
		local spawn = screen:FindFirstChild(SPAWN_NAME)
		if not spawn then
			spawn = Instance.new("Attachment")
			spawn.Name = SPAWN_NAME
			spawn.Parent = screen
		end
		local look = screen.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z).Unit
		local worldPosition = screen.Position + flat * SPAWN_DISTANCE
		spawn.WorldCFrame = CFrame.lookAt(worldPosition, worldPosition + flat)
		CollectionService:AddTag(model, TAG)
		model:SetAttribute("SpawnIndex", index)
		model:SetAttribute("TvScale", math.floor(model:GetScale() * 100 + 0.5) / 100)
		tagged += 1
		for _, d in model:GetDescendants() do
			if d:IsA("SurfaceGui") then
				d.MaxDistance = MAX_DISTANCE
				if d.SizingMode == Enum.SurfaceGuiSizingMode.FixedSize then
					d.CanvasSize = CANVAS
				end
			elseif d:IsA("BasePart") then
				d.CanTouch = false
				d.CanQuery = false
				d.CanCollide = false
				d.CastShadow = false
			end
		end
	end
end

local counts = {screens = #screenModel:GetChildren(), grown = resized.grown, shrunk = resized.shrunk, kept = resized.kept, added = added, extraAttempts = extraAttempts, tagged = tagged, lights = 0, parts = 0}
for _, d in root:GetDescendants() do
	if d:IsA("Light") then counts.lights += 1 end
	if d:IsA("BasePart") then counts.parts += 1 end
end
root:SetAttribute("BuildVersion", 6)
root:SetAttribute("ScreenCount", counts.screens)
root:SetAttribute("PartCount", counts.parts)
root:SetAttribute("LightCount", counts.lights)
ChangeHistoryService:SetWaypoint("Vary Signal Maze TVs v6")
return HttpService:JSONEncode(counts)
