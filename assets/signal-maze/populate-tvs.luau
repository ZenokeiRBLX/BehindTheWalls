local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20260928
local ROWS = {"Lower", "Middle", "Upper"}
local COLUMNS = {"Left", "Center", "Right"}
local TAG = "MonsterTV"
local SPAWN_NAME = "MonsterSpawn"
local SPAWN_DISTANCE = 2.5
local SCREEN_SINK = 0.7
local CANVAS = Vector2.new(256, 200)
local MAX_DISTANCE = 110
local RED_CHANCE = 0.55

assert(game.PlaceId == 126262358232325, "This pass targets Map Creation")
local root = workspace:FindFirstChild("SignalMaze")
assert(root and root:GetAttribute("BuildVersion") == 4, "Expected the version 4 SignalMaze")
assert(not ServerStorage:FindFirstChild("SignalMaze_V5Backup"), "A version 5 backup already exists")

local ORIGIN = root:GetAttribute("Origin")
local CELL = root:GetAttribute("CellSize")
local N = root:GetAttribute("GridSize")
local HALF = N * CELL / 2
local screenModel = root:FindFirstChild("EmbeddedTVs")

ChangeHistoryService:SetWaypoint("Before Signal Maze v5")
local backup = Instance.new("Folder")
backup.Name = "SignalMaze_V5Backup"
root:Clone().Parent = backup
backup.Parent = ServerStorage

local rng = Random.new(SEED)
local function r(a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end

local redTemplate
local staticTemplate
local templateNames = {}
for _, model in screenModel:GetChildren() do
	table.insert(templateNames, model.Name)
end
table.sort(templateNames)
for _, name in templateNames do
	local model = screenModel:FindFirstChild(name)
	local glass = model and model:FindFirstChild("BroadcastGlass")
	local signal = glass and glass:FindFirstChild("Signal")
	local content = signal and signal:FindFirstChildWhichIsA("ImageLabel")
	if content and not string.find(name, "Totem") then
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

local function behindFold(point: Vector3, normal: Vector3): boolean
	for _, fold in folds do
		local p = fold.cframe:PointToObjectSpace(point)
		local facing = fold.cframe:VectorToObjectSpace(normal)
		if math.abs(p.X) < fold.size.X / 2 + 3 and math.abs(p.Y) < fold.size.Y / 2 + 3 and math.abs(p.Z) < 8 and math.abs(facing.Z) > 0.5 then
			return true
		end
	end
	return false
end

local function foldOuter(center: Vector3, normal: Vector3): number
	local outer = 0
	for _, fold in folds do
		local p = fold.cframe:PointToObjectSpace(center + Vector3.new(0, 10, 0))
		if math.abs(p.X) < fold.size.X / 2 + 3 and math.abs(p.Z) < 8 then
			outer = math.max(outer, (fold.cframe.Position - center):Dot(normal) + fold.size.Z / 2)
		end
	end
	return outer
end

local screens = {}
for _, model in screenModel:GetChildren() do
	local anchor = model:FindFirstChild("Housing") or model:FindFirstChild("Bezel")
	if model:IsA("Model") and anchor and anchor:IsA("BasePart") then
		local look = anchor.CFrame.LookVector
		table.insert(screens, {position = anchor.Position, normal = Vector3.new(look.X, 0, look.Z).Unit})
	end
end

local function covered(center: Vector3, along: Vector3, normal: Vector3): boolean
	for _, screen in screens do
		local offset = screen.position - center
		if screen.normal:Dot(normal) > 0.7 and math.abs(offset:Dot(along)) <= CELL / 2 + 0.5 and offset:Dot(normal) > -1 and offset:Dot(normal) < 9 then
			return true
		end
	end
	return false
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
local sidesChecked = 0
local skipped = 0
local fallbacks = {}
local function addTv(center: Vector3, along: Vector3, normal: Vector3, name: string)
	for _ = 1, 8 do
		local offset = r(-5, 5)
		local height = r(4.2, 8.5)
		local red = rng:NextNumber() < RED_CHANCE
		local frontAt = r(3.9, 4.5)
		local tilt = CFrame.Angles(math.rad(r(-3, 6)), math.rad(r(-8, 8)), math.rad(r(-7, 7)))
		local wallPoint = center + along * offset + Vector3.yAxis * height
		if not behindFold(wallPoint, normal) then
			local model = (if red then redTemplate else staticTemplate):Clone()
			local housing = model.Housing
			local position = wallPoint + normal * (frontAt - housing.Size.Z / 2)
			position += surfaceShift(position, normal) - normal * SCREEN_SINK
			model:PivotTo(CFrame.lookAt(position, position + normal) * tilt * housing.CFrame:Inverse() * model:GetPivot())
			added += 1
			model.Name = string.format("S%03d_%s", added, name)
			model.Parent = screenModel
			return
		end
	end
	skipped += 1
	table.insert(fallbacks, {center = center, along = along, normal = normal, name = name})
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
			sidesChecked += 1
			if not covered(center, along, normal) then
				addTv(center, along, normal, edge.kind .. edge.line .. "_" .. edge.k)
			end
		end
	end
end

for _, fallback in fallbacks do
	local model = redTemplate:Clone()
	local housing = model.Housing
	local frontAt = math.max(4.3, foldOuter(fallback.center, fallback.normal) + 1.1)
	local position = fallback.center + Vector3.yAxis * 6 + fallback.normal * (frontAt - housing.Size.Z / 2)
	model:PivotTo(CFrame.lookAt(position, position + fallback.normal) * CFrame.Angles(math.rad(3), math.rad(-4), math.rad(5)) * housing.CFrame:Inverse() * model:GetPivot())
	added += 1
	model.Name = string.format("S%03d_%s", added, fallback.name)
	model.Parent = screenModel
end

local tagged = 0
local fidelityChanged = 0
for index, model in screenModel:GetChildren() do
	local screen = model:FindFirstChild("BroadcastGlass") or model:FindFirstChild("StaticScreen")
	if model:IsA("Model") and screen and screen:IsA("BasePart") then
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
		tagged += 1
	end
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceGui") then
			d.MaxDistance = MAX_DISTANCE
			if d.SizingMode == Enum.SurfaceGuiSizingMode.FixedSize then
				d.CanvasSize = CANVAS
			else
				d.PixelsPerStud = math.min(d.PixelsPerStud, 20)
			end
		elseif d:IsA("BasePart") then
			d.CanTouch = false
			d.CanQuery = false
			d.CanCollide = false
			d.CastShadow = false
			if d:IsA("MeshPart") and pcall(function()
				d.CollisionFidelity = Enum.CollisionFidelity.Box
			end) then
				fidelityChanged += 1
			end
		end
	end
end

local counts = {screens = #screenModel:GetChildren(), added = added, placedInFrontOfFolds = skipped, sidesChecked = sidesChecked, tagged = tagged, boxFidelity = fidelityChanged, lights = 0, parts = 0}
for _, d in root:GetDescendants() do
	if d:IsA("Light") then counts.lights += 1 end
	if d:IsA("BasePart") then counts.parts += 1 end
end
root:SetAttribute("BuildVersion", 5)
root:SetAttribute("ScreenCount", counts.screens)
root:SetAttribute("PartCount", counts.parts)
root:SetAttribute("LightCount", counts.lights)
root:SetAttribute("MonsterTag", TAG)
ChangeHistoryService:SetWaypoint("Populate Signal Maze TVs v5")
return HttpService:JSONEncode(counts)
