local Workspace = game:GetService("Workspace")

local MapSystem = {}

local isStarted = false

local WALL_MATERIAL = Enum.Material.SmoothPlastic
local WALL_COLOR = Color3.fromRGB(80, 80, 90)

local WALLS = {
	{ "NorthWall", Vector3.new(0, 10, -60), Vector3.new(120, 20, 1) },
	{ "SouthWall", Vector3.new(0, 10, 60), Vector3.new(120, 20, 1) },
	{ "WestWall", Vector3.new(-60, 10, 0), Vector3.new(1, 20, 120) },
	{ "EastWall", Vector3.new(60, 10, 0), Vector3.new(1, 20, 120) },
}

local SPAWN_POSITIONS = {
	Hunter = {
		Vector3.new(-30, 2, -30),
		Vector3.new(-30, 2, 30),
	},
	Runner = {
		Vector3.new(30, 2, -30),
		Vector3.new(30, 2, 30),
		Vector3.new(0, 2, 25),
		Vector3.new(0, 2, -25),
	},
}

function MapSystem.build()
	local existing = Workspace:FindFirstChild("Arena")
	if existing then
		existing:Destroy()
	end

	local arena = Instance.new("Model")
	arena.Name = "Arena"
	arena.Parent = Workspace

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(120, 1, 120)
	floor.Position = Vector3.new(0, 0, 0)
	floor.Anchored = true
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(45, 45, 52)
	floor.Parent = arena

	for _, wallData in WALLS do
		local name, position, size = wallData[1], wallData[2], wallData[3]
		local wall = Instance.new("Part")
		wall.Name = name
		wall.Size = size
		wall.Position = position
		wall.Anchored = true
		wall.Material = WALL_MATERIAL
		wall.Color = WALL_COLOR
		wall.Parent = arena
	end

	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "SpawnLocations"
	spawnFolder.Parent = arena

	for roleName, positions in SPAWN_POSITIONS do
		local roleFolder = Instance.new("Folder")
		roleFolder.Name = roleName
		roleFolder.Parent = spawnFolder

		for index, position in positions do
			local spawnPart = Instance.new("Part")
			spawnPart.Name = roleName .. "Spawn" .. index
			spawnPart.Size = Vector3.new(2, 1, 2)
			spawnPart.Position = position
			spawnPart.Anchored = true
			spawnPart.Transparency = 1
			spawnPart.CanCollide = false
			spawnPart.Parent = roleFolder
		end
	end

	local centerBlock = Instance.new("Part")
	centerBlock.Name = "CenterBlock"
	centerBlock.Size = Vector3.new(16, 10, 16)
	centerBlock.Position = Vector3.new(0, 5, 0)
	centerBlock.Anchored = true
	centerBlock.Material = Enum.Material.Slate
	centerBlock.Color = Color3.fromRGB(90, 90, 100)
	centerBlock.Parent = arena
end

function MapSystem.start()
	if isStarted then
		return
	end
	isStarted = true
	MapSystem.build()
end

return MapSystem
