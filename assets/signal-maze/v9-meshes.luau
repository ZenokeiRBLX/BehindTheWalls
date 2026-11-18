local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local SEED = 20261118
local HEIGHT = 34
local CORE = 1.25
local COLUMN_CORE = 0.62
local SPACING = 0.66
local BONE_SPREAD = 0.4
local BLEND = 1.6
local BASE_LIFT = 1.1
local TILE = 14
local UV_WARP = 1.3
local PREVIEW_NAME = "SignalMazeV9_MeshPreview"
local ROWS = { "Lower", "Middle", "Upper" }
local COLUMNS = { "Left", "Center", "Right" }

type Spec = {
	name: string,
	kind: "wall" | "column",
	size: Vector3,
	seed: number,
}

local SPECS: { Spec } = {
	{ name = "FleshWall27_A", kind = "wall", size = Vector3.new(27, HEIGHT, 6), seed = SEED + 1 },
	{ name = "FleshWall27_B", kind = "wall", size = Vector3.new(27, HEIGHT, 6), seed = SEED + 2 },
	{ name = "FleshWall51_A", kind = "wall", size = Vector3.new(51, HEIGHT, 6), seed = SEED + 3 },
	{ name = "FleshWall51_B", kind = "wall", size = Vector3.new(51, HEIGHT, 6), seed = SEED + 4 },
	{ name = "FleshColumn_A", kind = "column", size = Vector3.new(10.5, HEIGHT, 8.5), seed = SEED + 5 },
	{ name = "FleshColumn_B", kind = "column", size = Vector3.new(10.5, HEIGHT, 8.5), seed = SEED + 6 },
}

type Blob = { x: number, y: number, rx: number, ry: number, c: number, s: number, h: number }
type Field = (number, number) -> number

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function smax(a: number, b: number, k: number): number
	local h = math.max(k - math.abs(a - b), 0) / k
	return math.max(a, b) + h * h * k * 0.25
end

local function bucketed(list: { Blob }, width: number, wrapX: boolean): (number, number) -> { Blob }?
	local cell = 6
	local buckets: { [number]: { Blob } } = {}
	local function key(ix: number, iy: number): number
		return ix * 4096 + iy
	end
	local function insert(blob: Blob, ox: number)
		local reach = math.max(blob.rx, blob.ry)
		for ix = math.floor((blob.x + ox - reach) / cell), math.floor((blob.x + ox + reach) / cell) do
			for iy = math.floor((blob.y - reach) / cell), math.floor((blob.y + reach) / cell) do
				local k = key(ix, iy)
				buckets[k] = buckets[k] or {}
				table.insert(buckets[k], { x = blob.x + ox, y = blob.y, rx = blob.rx, ry = blob.ry, c = blob.c, s = blob.s, h = blob.h })
			end
		end
	end
	for _, blob in list do
		insert(blob, 0)
		if wrapX then
			insert(blob, width)
			insert(blob, -width)
		end
	end
	return function(x: number, y: number): { Blob }?
		return buckets[key(math.floor(x / cell), math.floor(y / cell))]
	end
end

local function bell(b: Blob, x: number, y: number): number
	local dx = x - b.x
	local dy = y - b.y
	local u = (dx * b.c + dy * b.s) / b.rx
	local v = (-dx * b.s + dy * b.c) / b.ry
	local d2 = u * u + v * v
	if d2 >= 1 then
		return 0
	end
	local f = 1 - d2
	return b.h * f * f
end

local function makeField(rng: Random, width: number, height: number, wrapX: boolean): Field
	local area = width * height
	local turns = 2 * math.pi / width
	local waves = {}
	for i = 1, 4 do
		waves[i] = {
			fx = if wrapX then rng:NextInteger(1, 2) * turns else rng:NextNumber(0.07, 0.17),
			fy = rng:NextNumber(0.05, 0.15),
			p = rng:NextNumber(0, 2 * math.pi),
		}
	end
	local function mass(x: number, y: number): number
		local m = 0
		for _, w in waves do
			m += math.sin(x * w.fx + y * w.fy + w.p)
		end
		return 0.5 + m / 8
	end
	local lumps: { Blob } = {}
	local pits: { Blob } = {}
	local function add(list: { Blob }, count: number, rMin: number, rMax: number, lift: number, stretchMin: number, stretchMax: number, lean: number)
		for _ = 1, count do
			local r = rng:NextNumber(rMin, rMax)
			local stretch = rng:NextNumber(stretchMin, stretchMax)
			local angle = rng:NextNumber(-lean, lean)
			local x = rng:NextNumber(-width / 2, width / 2)
			local y = rng:NextNumber(-height / 2, height / 2)
			table.insert(list, {
				x = x,
				y = y,
				rx = r / math.sqrt(stretch),
				ry = r * math.sqrt(stretch),
				c = math.cos(angle),
				s = math.sin(angle),
				h = r * lift * (0.4 + 0.9 * mass(x, y)),
			})
		end
	end
	add(lumps, math.floor(area / 42), 3.6, 6.4, 0.42, 1.2, 2.4, 0.35)
	add(lumps, math.floor(area / 24), 1.9, 3.2, 0.55, 1.1, 2.2, 0.5)
	add(lumps, math.floor(area / 48), 1, 1.6, 0.6, 0.9, 1.4, 1.5)
	add(pits, math.floor(area / 60), 0.8, 1.4, 0.32, 0.9, 1.6, 1.5)
	local lumpsAt = bucketed(lumps, width, wrapX)
	local pitsAt = bucketed(pits, width, wrapX)
	local phases = { rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28) }
	local sway = if wrapX then 2 * turns else 0.19
	return function(x: number, y: number): number
		local wx = x + 1.5 * math.sin(y * 0.21 + phases[1]) + 0.7 * math.sin(y * 0.47 + phases[2])
		local wy = y + 1.1 * math.sin(x * sway + phases[3])
		if wrapX then
			wx = (wx + width / 2) % width - width / 2
		end
		local value = BASE_LIFT * mass(wx, wy)
		local bucket = lumpsAt(wx, wy)
		if bucket then
			for _, b in bucket do
				local h = bell(b, wx, wy)
				if h > 0 then
					value = smax(value, h, BLEND)
				end
			end
		end
		bucket = pitsAt(wx, wy)
		if bucket then
			for _, b in bucket do
				value -= bell(b, wx, wy)
			end
		end
		return math.max(value, 0)
	end
end

local function boneLayout(size: Vector3): ({ string }, { Vector3 })
	local names, positions = {}, {}
	for row = 0, 2 do
		for column = 0, 2 do
			local index = row * 3 + column + 1
			names[index] = "Wall_" .. ROWS[row + 1] .. "_" .. COLUMNS[column + 1]
			positions[index] = Vector3.new((column - 1) * size.X * BONE_SPREAD, (row - 1) * size.Y * BONE_SPREAD, 0)
		end
	end
	return names, positions
end

local function skin(size: Vector3, p: Vector3): ({ number }, { number })
	local gx = math.clamp(p.X / (size.X * BONE_SPREAD) + 1, 0, 2)
	local gy = math.clamp(p.Y / (size.Y * BONE_SPREAD) + 1, 0, 2)
	local x0, y0 = math.min(math.floor(gx), 1), math.min(math.floor(gy), 1)
	local tx, ty = smoothstep(0, 1, gx - x0), smoothstep(0, 1, gy - y0)
	return { y0 * 3 + x0 + 1, y0 * 3 + x0 + 2, (y0 + 1) * 3 + x0 + 1, (y0 + 1) * 3 + x0 + 2 },
		{ (1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty }
end

type Geometry = { positions: { Vector3 }, uvs: { Vector2 }, tris: { { number } }, triUvs: { { number } }? }

local function buildWall(spec: Spec): Geometry
	local size = spec.size
	local rng = Random.new(spec.seed)
	local nx = math.max(8, math.round(size.X / SPACING))
	local ny = math.max(8, math.round(size.Y / SPACING))
	local positions: { Vector3 } = {}
	local uvs: { Vector2 } = {}
	local tris: { { number } } = {}
	local relief = size.Z / 2 - CORE
	local grids = {}
	for side = 1, 2 do
		local field = makeField(rng, size.X + 4, size.Y, false)
		local sign = if side == 1 then 1 else -1
		local a, b = rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)
		local grid = {}
		local maxZ = CORE
		for j = 0, ny do
			grid[j] = {}
			for i = 0, nx do
				local x = (i / nx - 0.5) * size.X
				local y = (j / ny - 0.5) * size.Y
				local inset = math.min(size.X / 2 - math.abs(x), size.Y / 2 - math.abs(y))
				local fade = if inset <= 1e-6 then 0 else smoothstep(0, 1.6, inset + 0.3)
				local z = CORE + relief * math.tanh(field(x, y) / relief) * fade
				maxZ = math.max(maxZ, z)
				grid[j][i] = { x, y, z }
			end
		end
		local scale = relief / (maxZ - CORE)
		for j = 0, ny do
			for i = 0, nx do
				local g = grid[j][i]
				table.insert(positions, Vector3.new(g[1], g[2], (CORE + (g[3] - CORE) * scale) * sign))
				table.insert(uvs, Vector2.new(
					(sign * g[1] + UV_WARP * math.sin(g[2] * 0.23 + a)) / TILE,
					1 - (g[2] + UV_WARP * math.sin(g[1] * 0.19 + b)) / TILE
				))
				grid[j][i] = #positions
			end
		end
		grids[side] = grid
	end
	local function tri(a: number, b: number, c: number, outward: Vector3)
		local n = (positions[b] - positions[a]):Cross(positions[c] - positions[a])
		if n:Dot(outward) < 0 then
			b, c = c, b
		end
		table.insert(tris, { a, b, c })
	end
	for side = 1, 2 do
		local grid = grids[side]
		local out = Vector3.new(0, 0, if side == 1 then 1 else -1)
		for j = 0, ny - 1 do
			for i = 0, nx - 1 do
				tri(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], out)
				tri(grid[j][i], grid[j + 1][i + 1], grid[j + 1][i], out)
			end
		end
	end
	local ring = {}
	for i = 0, nx do
		table.insert(ring, { i, 0 })
	end
	for j = 1, ny do
		table.insert(ring, { nx, j })
	end
	for i = nx - 1, 0, -1 do
		table.insert(ring, { i, ny })
	end
	for j = ny - 1, 1, -1 do
		table.insert(ring, { 0, j })
	end
	for k = 1, #ring do
		local a = ring[k]
		local b = ring[k % #ring + 1]
		local fa, fb = grids[1][a[2]][a[1]], grids[1][b[2]][b[1]]
		local ba, bb = grids[2][a[2]][a[1]], grids[2][b[2]][b[1]]
		local mid = (positions[fa] + positions[fb]) / 2
		local out = Vector3.new(mid.X, mid.Y, 0)
		tri(fa, fb, bb, out)
		tri(fa, bb, ba, out)
	end
	return { positions = positions, uvs = uvs, tris = tris }
end

local function buildColumn(spec: Spec): Geometry
	local size = spec.size
	local rng = Random.new(spec.seed)
	local a, b = size.X / 2, size.Z / 2
	local radius = (a + b) / 2
	local circumference = 2 * math.pi * radius
	local repeats = math.max(1, math.round(circumference / TILE))
	local nt = 48
	local ny = math.max(8, math.round(size.Y / SPACING))
	local field = makeField(rng, circumference, size.Y, true)
	local relief = radius * (1 - COLUMN_CORE)
	local phase = rng:NextNumber(0, 6.28)
	local positions: { Vector3 } = {}
	local uvs: { Vector2 } = {}
	local raw = {}
	local maxX, maxZ = 0, 0
	for j = 0, ny do
		raw[j] = {}
		for i = 0, nt - 1 do
			local theta = i / nt * 2 * math.pi
			local y = (j / ny - 0.5) * size.Y
			local h = field(theta * radius - circumference / 2, y)
			local r = radius * COLUMN_CORE + relief * math.tanh(h / relief)
			local x = math.cos(theta) * r * (a / radius)
			local z = math.sin(theta) * r * (b / radius)
			maxX = math.max(maxX, math.abs(x))
			maxZ = math.max(maxZ, math.abs(z))
			raw[j][i] = { x, y, z, theta }
		end
	end
	local function uvAt(theta: number, y: number): Vector2
		return Vector2.new(
			theta / (2 * math.pi) * repeats + UV_WARP * math.sin(y * 0.23 + phase) / TILE,
			1 - (y + UV_WARP * math.sin(2 * theta + phase)) / TILE
		)
	end
	local grid = {}
	for j = 0, ny do
		grid[j] = {}
		for i = 0, nt - 1 do
			local g = raw[j][i]
			table.insert(positions, Vector3.new(g[1] * a / maxX, g[2], g[3] * b / maxZ))
			table.insert(uvs, uvAt(g[4], g[2]))
			grid[j][i] = #positions
		end
	end
	local seamUvs = {}
	for j = 0, ny do
		table.insert(uvs, uvAt(2 * math.pi, raw[j][0][2]))
		seamUvs[j] = #uvs
	end
	local tris: { { number } } = {}
	local triUvs: { { number } } = {}
	local function tri(p: { number }, u: { number }, outward: Vector3)
		local n = (positions[p[2]] - positions[p[1]]):Cross(positions[p[3]] - positions[p[1]])
		if n:Dot(outward) < 0 then
			p = { p[1], p[3], p[2] }
			u = { u[1], u[3], u[2] }
		end
		table.insert(tris, p)
		table.insert(triUvs, u)
	end
	for j = 0, ny - 1 do
		for i = 0, nt - 1 do
			local i2 = (i + 1) % nt
			local p00, p10, p11, p01 = grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]
			local u10 = if i2 == 0 then seamUvs[j] else p10
			local u11 = if i2 == 0 then seamUvs[j + 1] else p11
			local mid = positions[p00]
			local out = Vector3.new(mid.X, 0, mid.Z)
			tri({ p00, p10, p11 }, { p00, u10, u11 }, out)
			tri({ p00, p11, p01 }, { p00, u11, p01 }, out)
		end
	end
	for _, cap in { { 0, -1 }, { ny, 1 } } do
		local j, dir = cap[1], cap[2]
		local y = (j / ny - 0.5) * size.Y
		table.insert(positions, Vector3.new(0, y, 0))
		table.insert(uvs, Vector2.new(0.5, 1 - y / TILE))
		local center = #positions
		for i = 0, nt - 1 do
			local i2 = (i + 1) % nt
			tri({ center, grid[j][i], grid[j][i2] }, { center, grid[j][i], grid[j][i2] }, Vector3.new(0, dir, 0))
		end
	end
	return { positions = positions, uvs = uvs, tris = tris, triUvs = triUvs }
end

local function toEditable(spec: Spec, geometry: Geometry): EditableMesh
	local mesh = AssetService:CreateEditableMesh({ FixedSize = false })
	assert(mesh, "EditableMesh creation failed")
	local names, bonePositions = boneLayout(spec.size)
	local boneIds = {}
	for index, name in names do
		boneIds[index] = mesh:AddBone({ Name = name, CFrame = CFrame.new(bonePositions[index]), Virtual = false })
	end
	local vertexIds = {}
	for index, p in geometry.positions do
		local id = mesh:AddVertex(p)
		vertexIds[index] = id
		local slots, weights = skin(spec.size, p)
		mesh:SetVertexBones(id, { boneIds[slots[1]], boneIds[slots[2]], boneIds[slots[3]], boneIds[slots[4]] })
		mesh:SetVertexBoneWeights(id, weights)
	end
	local uvIds = {}
	for index, uv in geometry.uvs do
		uvIds[index] = mesh:AddUV(uv)
	end
	for index, t in geometry.tris do
		local face = mesh:AddTriangle(vertexIds[t[1]], vertexIds[t[2]], vertexIds[t[3]])
		local u = if geometry.triUvs then geometry.triUvs[index] else t
		mesh:SetFaceUVs(face, { uvIds[u[1]], uvIds[u[2]], uvIds[u[3]] })
	end
	mesh:RemoveUnused()
	return mesh
end

return function(mode: "preview" | "upload", only: { string }?): string
	local results = {}
	local built = {}
	for _, spec in SPECS do
		if only and not table.find(only, spec.name) then
			continue
		end
		local geometry = if spec.kind == "wall" then buildWall(spec) else buildColumn(spec)
		local mesh = toEditable(spec, geometry)
		local entry = { name = spec.name, vertices = #geometry.positions, triangles = #geometry.tris }
		if mode == "upload" then
			local ok, result, assetId = pcall(function()
				return AssetService:CreateAssetAsync(mesh, Enum.AssetType.Mesh, {
					CreatorId = game.CreatorId,
					CreatorType = if game.CreatorType == Enum.CreatorType.Group
						then Enum.AssetCreatorType.Group
						else Enum.AssetCreatorType.User,
					Name = "SignalMazeV9_" .. spec.name,
					Description = "Signal Maze v9 flesh mesh with nine Wall_* bones.",
				})
			end)
			entry.ok = ok
			entry.result = tostring(result)
			entry.assetId = if ok and result == Enum.CreateAssetResult.Success then tostring(assetId) else nil
			mesh:Destroy()
		else
			built[spec.name] = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
		end
		table.insert(results, entry)
	end

	if mode == "preview" then
		local folder = ServerStorage:FindFirstChild(PREVIEW_NAME) or Instance.new("Folder")
		folder.Name = PREVIEW_NAME
		folder.Parent = ServerStorage
		for name, part in built do
			local old = folder:FindFirstChild(name)
			if old then
				old:Destroy()
			end
			part.Name = name
			part.Anchored = true
			part.Parent = folder
		end
	end

	return HttpService:JSONEncode(results)
end
