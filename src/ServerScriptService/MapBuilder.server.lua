local Workspace = game:GetService("Workspace")

local arena = Workspace:FindFirstChild("Arena")
if arena then
	arena:Destroy()
end

arena = Instance.new("Model")
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

local wallMaterial = Enum.Material.SmoothPlastic
local wallColor = Color3.fromRGB(80, 80, 90)

local walls = {
	{ "NorthWall", Vector3.new(0, 10, -60), Vector3.new(120, 20, 1) },
	{ "SouthWall", Vector3.new(0, 10, 60), Vector3.new(120, 20, 1) },
	{ "WestWall", Vector3.new(-60, 10, 0), Vector3.new(1, 20, 120) },
	{ "EastWall", Vector3.new(60, 10, 0), Vector3.new(1, 20, 120) },
}

for _, wallData in ipairs(walls) do
	local name, position, size = wallData[1], wallData[2], wallData[3]
	local wall = Instance.new("Part")
	wall.Name = name
	wall.Size = size
	wall.Position = position
	wall.Anchored = true
	wall.Material = wallMaterial
	wall.Color = wallColor
	wall.Parent = arena
end

local spawnFolder = Instance.new("Folder")
spawnFolder.Name = "SpawnLocations"
spawnFolder.Parent = arena

local hunterFolder = Instance.new("Folder")
hunterFolder.Name = "Hunter"
hunterFolder.Parent = spawnFolder

local runnerFolder = Instance.new("Folder")
runnerFolder.Name = "Runner"
runnerFolder.Parent = spawnFolder

local spawnPositions = {
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

for roleName, positions in pairs(spawnPositions) do
	local folder = roleName == "Hunter" and hunterFolder or runnerFolder
	for index, pos in ipairs(positions) do
		local spawn = Instance.new("Part")
		spawn.Name = roleName .. "Spawn" .. index
		spawn.Size = Vector3.new(2, 1, 2)
		spawn.Position = pos
		spawn.Anchored = true
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = folder
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

print("[MapBuilder] Arena generated.")
