local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local SEED = 20261117
local HEIGHT = 34
local CORE = 0.55
local COLUMN_CORE = 0.6
local SPACING = 0.66
local BONE_SPREAD = 0.4
local BLEND = 1.1
local BASE_LIFT = 1.4
local ROWS = { "Lower", "Middle", "Upper" }
local COLUMNS = { "Left", "Center", "Right" }
local COLLAR_SIZE = Vector3.new(12, 9.2, 4)
local COLLAR_INNER = Vector2.new(3.6, 2.7)
local COLLAR_CELLS = Vector2.new(44, 33)

type Spec = {
	name: string,
	kind: "wall" | "column" | "collar",
	size: Vector3,
	seed: number,
	tile: number,
}

local SPECS: { Spec } = {
	{ name = "FleshWall27_A", kind = "wall", size = Vector3.new(27, HEIGHT, 6), seed = SEED + 1, tile = 10 },
	{ name = "FleshWall27_B", kind = "wall", size = Vector3.new(27, HEIGHT, 6), seed = SEED + 2, tile = 10 },
	{ name = "FleshWall51_A", kind = "wall", size = Vector3.new(51, HEIGHT, 6), seed = SEED + 3, tile = 10 },
	{ name = "FleshWall51_B", kind = "wall", size = Vector3.new(51, HEIGHT, 6), seed = SEED + 4, tile = 10 },
	{ name = "FleshColumn_A", kind = "column", size = Vector3.new(10.5, HEIGHT, 8.5), seed = SEED + 5, tile = 10 },
	{ name = "FleshColumn_B", kind = "column", size = Vector3.new(10.5, HEIGHT, 8.5), seed = SEED + 6, tile = 10 },
	{ name = "FleshCollar_A", kind = "collar", size = COLLAR_SIZE, seed = SEED + 7, tile = 10 },
	{ name = "FleshCollar_B", kind = "collar", size = COLLAR_SIZE, seed = SEED + 8, tile = 10 },
}

type Blob = { x: number, y: number, rx: number, ry: number, c: number, s: number, h: number }

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function smax(a: number, b: number, k: number): number
	local h = math.max(k - math.abs(a - b), 0) / k
	return math.max(a, b) + h * h * k * 0.25
end

local function makeBlobs(rng: Random, width: number, height: number, wrapX: boolean): ({ Blob }, (number, number) -> number)
	local area = width * height
	local list: { Blob } = {}
	local waves = {}
	for i = 1, 4 do
		waves[i] = {
			fx = (if wrapX then math.round(rng:NextNumber(1, 2.5)) * 2 * math.pi / width else rng:NextNumber(0.08, 0.2)),
			fy = rng:NextNumber(0.06, 0.18),
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
	local function add(count: number, rMin: number, rMax: number, lift: number, sag: boolean)
		for _ = 1, count do
			local r = rng:NextNumber(rMin, rMax)
			local stretch = if sag then rng:NextNumber(1.8, 2.8) else rng:NextNumber(0.8, 1.25)
			local angle = if sag then rng:NextNumber(-0.25, 0.25) else rng:NextNumber(0, math.pi)
			local x = rng:NextNumber(-width / 2, width / 2)
			local y = rng:NextNumber(-height / 2, height / 2)
			local m = mass(x, y)
			table.insert(list, {
				x = x,
				y = y,
				rx = r / math.sqrt(stretch),
				ry = r * math.sqrt(stretch),
				c = math.cos(angle),
				s = math.sin(angle),
				h = r * lift * (0.35 + 0.9 * m),
			})
		end
	end
	add(math.floor(area / 34), 3, 6, 0.5, false)
	add(math.floor(area / 20), 1.4, 2.6, 0.7, false)
	add(math.floor(area / 60), 0.8, 1.3, 0.8, true)
	add(math.floor(area / 24), 0.8, 1.3, 0.75, false)
	return list, mass
end

local function sampler(list: { Blob }, width: number, wrapX: boolean, mass: (number, number) -> number): (number, number) -> number
	local cell = 5
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
	return function(x: number, y: number): number
		local bucket = buckets[key(math.floor(x / cell), math.floor(y / cell))]
		local value = BASE_LIFT * mass(x, y) ^ 1.4
		if bucket then
			for _, b in bucket do
				local dx = x - b.x
				local dy = y - b.y
				local u = (dx * b.c + dy * b.s) / b.rx
				local v = (-dx * b.s + dy * b.c) / b.ry
				local d2 = u * u + v * v
				if d2 < 1 then
					value = smax(value, b.h * math.sqrt(1 - d2), BLEND)
				end
			end
		end
		return value
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
		local list, mass = makeBlobs(rng, size.X + 4, size.Y, false)
		local field = sampler(list, size.X + 4, false, mass)
		local sign = if side == 1 then 1 else -1
		local grid = {}
		local maxZ = 0
		for j = 0, ny do
			grid[j] = {}
			for i = 0, nx do
				local x = (i / nx - 0.5) * size.X
				local y = (j / ny - 0.5) * size.Y
				local edge = math.min(i, nx - i, j, ny - j)
				local fade = if edge == 0 then 0 else smoothstep(0, 1.2, math.min(size.X / 2 - math.abs(x), size.Y / 2 - math.abs(y)) + 0.35)
				local h = field(x, y)
				local z = CORE + relief * math.tanh(h / relief) * fade
				maxZ = math.max(maxZ, z)
				grid[j][i] = { x, y, z }
			end
		end
		local scale = (size.Z / 2 - CORE) / (maxZ - CORE)
		for j = 0, ny do
			for i = 0, nx do
				local g = grid[j][i]
				local z = if i == 0 or i == nx or j == 0 or j == ny then CORE else CORE + (g[3] - CORE) * scale
				table.insert(positions, Vector3.new(g[1], g[2], z * sign))
				table.insert(uvs, Vector2.new(sign * g[1] / spec.tile, 1 - g[2] / spec.tile))
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
	local nt = 48
	local ny = math.max(8, math.round(size.Y / SPACING))
	local list, mass = makeBlobs(rng, circumference, size.Y, true)
	local field = sampler(list, circumference, true, mass)
	local relief = radius * (1 - COLUMN_CORE)
	local positions: { Vector3 } = {}
	local uvs: { Vector2 } = {}
	local raw = {}
	local maxX, maxZ = 0, 0
	for j = 0, ny do
		raw[j] = {}
		for i = 0, nt - 1 do
			local theta = i / nt * 2 * math.pi
			local y = (j / ny - 0.5) * size.Y
			local h = field(theta * radius, y)
			local r = radius * COLUMN_CORE + relief * math.tanh(h / relief)
			local x = math.cos(theta) * r * (a / radius)
			local z = math.sin(theta) * r * (b / radius)
			maxX = math.max(maxX, math.abs(x))
			maxZ = math.max(maxZ, math.abs(z))
			raw[j][i] = { x, y, z, theta }
		end
	end
	local grid = {}
	for j = 0, ny do
		grid[j] = {}
		for i = 0, nt - 1 do
			local g = raw[j][i]
			table.insert(positions, Vector3.new(g[1] * a / maxX, g[2], g[3] * b / maxZ))
			table.insert(uvs, Vector2.new(g[4] * radius / spec.tile, 1 - g[2] / spec.tile))
			grid[j][i] = #positions
		end
	end
	local seamUvs = {}
	for j = 0, ny do
		table.insert(uvs, Vector2.new(circumference / spec.tile, 1 - raw[j][0][2] / spec.tile))
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
		table.insert(uvs, Vector2.new(0, 1 - y / spec.tile))
		local center = #positions
		for i = 0, nt - 1 do
			local i2 = (i + 1) % nt
			tri({ center, grid[j][i], grid[j][i2] }, { center, grid[j][i], grid[j][i2] }, Vector3.new(0, dir, 0))
		end
	end
	return { positions = positions, uvs = uvs, tris = tris, triUvs = triUvs }
end

local function buildCollar(spec: Spec): Geometry
	local size = spec.size
	local rng = Random.new(spec.seed)
	local half = Vector2.new(size.X / 2, size.Y / 2)
	local list: { Blob } = {}
	for _ = 1, 70 do
		local r = rng:NextNumber(0.4, 1.0)
		local stretch = rng:NextNumber(0.8, 1.3)
		local angle = rng:NextNumber(0, math.pi)
		table.insert(list, {
			x = rng:NextNumber(-half.X, half.X),
			y = rng:NextNumber(-half.Y, half.Y),
			rx = r / math.sqrt(stretch),
			ry = r * math.sqrt(stretch),
			c = math.cos(angle),
			s = math.sin(angle),
			h = r * rng:NextNumber(0.6, 1.0),
		})
	end
	local field = sampler(list, size.X, false, function()
		return 0
	end)
	local function outside(x: number, y: number): number
		local dx = math.max(math.abs(x) - COLLAR_INNER.X, 0)
		local dy = math.max(math.abs(y) - COLLAR_INNER.Y, 0)
		return math.sqrt(dx * dx + dy * dy)
	end
	local band = math.min(half.X - COLLAR_INNER.X, half.Y - COLLAR_INNER.Y)
	local nx, ny = COLLAR_CELLS.X, COLLAR_CELLS.Y
	local positions: { Vector3 } = {}
	local uvs: { Vector2 } = {}
	local grid = {}
	for j = 0, ny do
		grid[j] = {}
		for i = 0, nx do
			local x = (i / nx - 0.5) * size.X
			local y = (j / ny - 0.5) * size.Y
			local d = outside(x, y)
			local edge = math.min(half.X - math.abs(x), half.Y - math.abs(y))
			local lumps = math.tanh(field(x, y) / 0.6)
			local reach = band * (0.62 + 0.38 * lumps)
			local t = math.clamp(d / reach, 0, 1)
			local dome = math.sqrt(math.max(0, 1 - t * t))
			local z = size.Z * math.clamp(0.78 * dome + 0.3 * lumps * dome, 0, 1)
			if edge <= 1e-6 then
				z = 0
			end
			table.insert(positions, Vector3.new(x, y, z - size.Z / 2))
			table.insert(uvs, Vector2.new(x / spec.tile, 1 - y / spec.tile))
			grid[j][i] = { #positions, d, z }
		end
	end
	local tris: { { number } } = {}
	local out = Vector3.new(0, 0, 1)
	local function tri(a: number, b: number, c: number)
		local n = (positions[b] - positions[a]):Cross(positions[c] - positions[a])
		if n:Dot(out) < 0 then
			b, c = c, b
		end
		table.insert(tris, { a, b, c })
	end
	for j = 0, ny - 1 do
		for i = 0, nx - 1 do
			local a, b, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
			local raised = a[3] > 0.01 or b[3] > 0.01 or c[3] > 0.01 or d[3] > 0.01
			if raised and (a[2] > 0 or b[2] > 0 or c[2] > 0 or d[2] > 0) then
				tri(a[1], b[1], c[1])
				tri(a[1], c[1], d[1])
			end
		end
	end
	local maxZ = -math.huge
	for _, p in positions do
		maxZ = math.max(maxZ, p.Z)
	end
	local stretch = size.Z / (maxZ + size.Z / 2)
	for index, p in positions do
		positions[index] = Vector3.new(p.X, p.Y, (p.Z + size.Z / 2) * stretch - size.Z / 2)
	end
	return { positions = positions, uvs = uvs, tris = tris }
end

local function toEditable(spec: Spec, geometry: Geometry): EditableMesh
	local mesh = AssetService:CreateEditableMesh({ FixedSize = false })
	assert(mesh, "EditableMesh creation failed")
	local rigged = spec.kind ~= "collar"
	local names, bonePositions = boneLayout(spec.size)
	local boneIds = {}
	if rigged then
		for index, name in names do
			boneIds[index] = mesh:AddBone({ Name = name, CFrame = CFrame.new(bonePositions[index]), Virtual = false })
		end
	end
	local vertexIds = {}
	for index, p in geometry.positions do
		local id = mesh:AddVertex(p)
		vertexIds[index] = id
		if rigged then
			local slots, weights = skin(spec.size, p)
			mesh:SetVertexBones(id, { boneIds[slots[1]], boneIds[slots[2]], boneIds[slots[3]], boneIds[slots[4]] })
			mesh:SetVertexBoneWeights(id, weights)
		end
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

return function(MODE: "preview" | "upload", ONLY: { string }?): string
	local results = {}
	local built = {}
	for _, spec in SPECS do
		if ONLY and not table.find(ONLY, spec.name) then
			continue
		end
		local geometry = if spec.kind == "wall"
			then buildWall(spec)
			elseif spec.kind == "column" then buildColumn(spec)
			else buildCollar(spec)
		local mesh = toEditable(spec, geometry)
		local entry = { name = spec.name, vertices = #geometry.positions, triangles = #geometry.tris }
		if MODE == "upload" then
			local ok, result, assetId = pcall(function()
				return AssetService:CreateAssetAsync(mesh, Enum.AssetType.Mesh, {
					CreatorId = game.CreatorId,
					CreatorType = if game.CreatorType == Enum.CreatorType.Group
						then Enum.AssetCreatorType.Group
						else Enum.AssetCreatorType.User,
					Name = "SignalMazeV9_" .. spec.name,
					Description = "Signal Maze v9 lumpy flesh mesh with nine Wall_* bones.",
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

	if MODE == "preview" then
		local folder = game:GetService("ServerStorage"):FindFirstChild("SignalMazeV9_MeshPreview") or Instance.new("Folder")
		folder.Name = "SignalMazeV9_MeshPreview"
		folder.Parent = game:GetService("ServerStorage")
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
