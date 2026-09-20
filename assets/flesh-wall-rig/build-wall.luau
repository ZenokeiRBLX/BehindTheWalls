local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local source = workspace:FindFirstChild("btool")
assert(source and source:IsA("MeshPart"), "Expected the original btool wall")
assert(not workspace:FindFirstChild("FleshWall_Rigged9"), "The rigged wall already exists")

local size = source.Size
local half = size / 2
local rounding = 0.78
local subdivisions = {64, 32, 10}
local positions = {}
local triangles = {}
local cornerUvs = {}
local lookup = {}
local tileSize = 12

local function roundedPoint(point: Vector3): Vector3
	local inner = half - Vector3.one * rounding
	local closest = Vector3.new(math.clamp(point.X, -inner.X, inner.X), math.clamp(point.Y, -inner.Y, inner.Y), math.clamp(point.Z, -inner.Z, inner.Z))
	local delta = point - closest
	local p = closest + delta.Unit * rounding
	local mask = math.clamp((math.abs(p.Z) - half.Z + rounding) / rounding, 0, 1)
	local edgeFade = math.clamp((half.X - math.abs(p.X)) / 2, 0, 1) * math.clamp((half.Y - math.abs(p.Y)) / 2, 0, 1)
	local wave = math.sin(p.X * 0.65 + math.sin(p.Y * 0.48) * 1.1) * 0.21
	wave += math.sin(p.Y * 0.87 + math.cos(p.X * 0.38)) * 0.15
	wave += math.sin(p.X * 1.31 - p.Y * 0.69) * 0.065
	return p + Vector3.new(0, 0, math.sign(p.Z) * mask * edgeFade * wave)
end

local function vertex(point: Vector3): number
	local key = string.format("%.5f,%.5f,%.5f", point.X, point.Y, point.Z)
	if lookup[key] then
		return lookup[key]
	end
	local id = #positions + 1
	lookup[key] = id
	positions[id] = roundedPoint(point)
	return id
end

local function face(center: Vector3, uAxis: Vector3, vAxis: Vector3, uSize: number, vSize: number, uCount: number, vCount: number)
	local grid = {}
	for y = 0, vCount do
		grid[y] = {}
		for x = 0, uCount do
			grid[y][x] = vertex(center + uAxis * ((x / uCount - 0.5) * uSize) + vAxis * ((y / vCount - 0.5) * vSize))
		end
	end
	local function add(a: number, b: number, c: number, ua: Vector2, ub: Vector2, uc: Vector2)
		table.insert(triangles, {a, b, c})
		table.insert(cornerUvs, {ua, ub, uc})
	end
	for y = 0, vCount - 1 do
		for x = 0, uCount - 1 do
			local a, b, c, d = grid[y][x], grid[y][x + 1], grid[y + 1][x + 1], grid[y + 1][x]
			local ua = Vector2.new(x / uCount * uSize / tileSize, 1 - y / vCount * vSize / tileSize)
			local ub = Vector2.new((x + 1) / uCount * uSize / tileSize, ua.Y)
			local uc = Vector2.new(ub.X, 1 - (y + 1) / vCount * vSize / tileSize)
			local ud = Vector2.new(ua.X, uc.Y)
			add(a, b, c, ua, ub, uc)
			add(a, c, d, ua, uc, ud)
		end
	end
end

face(Vector3.new(0, 0, half.Z), Vector3.xAxis, Vector3.yAxis, size.X, size.Y, subdivisions[1], subdivisions[2])
face(Vector3.new(0, 0, -half.Z), -Vector3.xAxis, Vector3.yAxis, size.X, size.Y, subdivisions[1], subdivisions[2])
face(Vector3.new(half.X, 0, 0), -Vector3.zAxis, Vector3.yAxis, size.Z, size.Y, subdivisions[3], subdivisions[2])
face(Vector3.new(-half.X, 0, 0), Vector3.zAxis, Vector3.yAxis, size.Z, size.Y, subdivisions[3], subdivisions[2])
face(Vector3.new(0, half.Y, 0), Vector3.xAxis, -Vector3.zAxis, size.X, size.Z, subdivisions[1], subdivisions[3])
face(Vector3.new(0, -half.Y, 0), Vector3.xAxis, Vector3.zAxis, size.X, size.Z, subdivisions[1], subdivisions[3])

local minimum = Vector3.new(math.huge, math.huge, math.huge)
local maximum = -minimum
for _, p in positions do
	minimum = minimum:Min(p)
	maximum = maximum:Max(p)
end
local center = (minimum + maximum) / 2
local scale = size / (maximum - minimum)
for i, p in positions do
	positions[i] = (p - center) * scale
end

local mesh = AssetService:CreateEditableMesh()
assert(mesh, "EditableMesh creation failed")
local boneIds = {}
local bonePositions = {}
local boneNames = {}
local rows = {"Lower", "Middle", "Upper"}
local columns = {"Left", "Center", "Right"}
for row = 0, 2 do
	for column = 0, 2 do
		local index = row * 3 + column + 1
		local p = Vector3.new((column - 1) * size.X * 0.4, (row - 1) * size.Y * 0.4, 0)
		local name = "Wall_" .. rows[row + 1] .. "_" .. columns[column + 1]
		boneIds[index] = mesh:AddBone({Name = name, CFrame = CFrame.new(p), Virtual = false})
		boneNames[index] = name
		bonePositions[index] = p
	end
end

local vertexIds = {}
local function smooth(value: number): number
	return value * value * (3 - 2 * value)
end

for index, p in positions do
	local id = mesh:AddVertex(p)
	vertexIds[index] = id
	local gx = math.clamp(p.X / (size.X * 0.4) + 1, 0, 2)
	local gy = math.clamp(p.Y / (size.Y * 0.4) + 1, 0, 2)
	local x0, y0 = math.min(math.floor(gx), 1), math.min(math.floor(gy), 1)
	local tx, ty = smooth(gx - x0), smooth(gy - y0)
	local ids = {boneIds[y0 * 3 + x0 + 1], boneIds[y0 * 3 + x0 + 2], boneIds[(y0 + 1) * 3 + x0 + 1], boneIds[(y0 + 1) * 3 + x0 + 2]}
	local weights = {(1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty}
	mesh:SetVertexBones(id, ids)
	mesh:SetVertexBoneWeights(id, weights)
end

for index, triangle in triangles do
	local id = mesh:AddTriangle(vertexIds[triangle[1]], vertexIds[triangle[2]], vertexIds[triangle[3]])
	local uvs = cornerUvs[index]
	mesh:SetFaceUVs(id, {mesh:AddUV(uvs[1]), mesh:AddUV(uvs[2]), mesh:AddUV(uvs[3])})
end
mesh:RemoveUnused()

local model = Instance.new("Model")
model.Name = "FleshWall_Rigged9"
local wall = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
wall.Name = "Wall"
wall.Anchored = true
wall.CanCollide = true
wall.Size = size
wall.CFrame = source.CFrame * CFrame.new(size.X + 8, 0, 0)
wall.Color = Color3.new(1, 1, 1)
wall.Material = Enum.Material.Salt
wall.MaterialVariant = "Flesh"
wall.Parent = model

for i, name in boneNames do
	local bone = wall:FindFirstChild(name)
	if not bone then
		bone = Instance.new("Bone")
		bone.Name = name
		bone.Parent = wall
	end
	bone.CFrame = CFrame.new(bonePositions[i])
end
local controller = Instance.new("AnimationController")
controller.Name = "AnimationController"
controller.Parent = model
local animator = Instance.new("Animator")
animator.Parent = controller
model.PrimaryPart = wall
model:SetAttribute("BoneCount", 9)
model:SetAttribute("SourceMeshRebuilt", true)
model:SetAttribute("OriginalMeshId", source.MeshId)
model:SetAttribute("VertexCount", #positions)
model:SetAttribute("TriangleCount", #triangles)
model:SetAttribute("TileSize", tileSize)
model.Parent = workspace

local request = {
	CreatorId = game.CreatorId,
	CreatorType = game.CreatorType == Enum.CreatorType.Group and Enum.AssetCreatorType.Group or Enum.AssetCreatorType.User,
	Name = "Organic Wall - Nine Bone Deformation",
	Description = "Rounded organic wall with nine weighted deformation bones and continuous skinning.",
}
local ok, result, assetId = pcall(function()
	return AssetService:CreateAssetAsync(mesh, Enum.AssetType.Mesh, request)
end)
if ok and result == Enum.CreateAssetResult.Success then
	local uploaded = AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. tostring(assetId)))
	wall:ApplyMesh(uploaded)
	wall.Size = size
	uploaded:Destroy()
	model:SetAttribute("PublishedMeshId", tostring(assetId))
	mesh:Destroy()
end
game:GetService("Selection"):Set({model})
return HttpService:JSONEncode({vertices = #positions, triangles = #triangles, bones = #boneIds, uploadCallOk = ok, uploadResult = tostring(result), assetId = tostring(assetId), path = model:GetFullName()})
