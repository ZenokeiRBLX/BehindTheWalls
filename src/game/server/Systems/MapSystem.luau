local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

local MapSystem = {}

export type Level = {
	key: string,
	displayName: string,
	model: Model,
	entry: CFrame,
	shaftTop: CFrame?,
}

type LevelSettings = {
	DisplayName: string,
	ModelName: string,
	Origin: Vector3?,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local levels: { [string]: Level } = {}
local activeKey: string? = nil

local function settingsFor(key: string): LevelSettings?
	return (Config.Maps.Levels :: any)[key]
end

local function mapsFolder(): Instance
	local name = Config.Maps.WorkspaceName
	local folder = Workspace:FindFirstChild(name)
	if folder then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = Workspace
	return created
end

local function findStored(modelName: string): Model?
	local storage = ServerStorage:FindFirstChild(Config.Maps.StorageName)
	local stored = if storage then storage:FindFirstChild(modelName) else nil
	return if stored and stored:IsA("Model") then stored else nil
end

local function findPlaced(modelName: string): Model?
	local folder = Workspace:FindFirstChild(Config.Maps.WorkspaceName)
	local placed = if folder then folder:FindFirstChild(modelName) else nil
	placed = placed or Workspace:FindFirstChild(modelName)
	return if placed and placed:IsA("Model") then placed else nil
end

local function snapToVoxels(offset: Vector3): Vector3
	local voxel = Config.Maps.VoxelSize
	return Vector3.new(
		math.round(offset.X / voxel) * voxel,
		math.round(offset.Y / voxel) * voxel,
		math.round(offset.Z / voxel) * voxel
	)
end

local function pasteTerrain(model: Model, region: TerrainRegion, offset: Vector3)
	local corner = region:GetAttribute(Config.Maps.TerrainCornerAttribute)
	if typeof(corner) ~= "Vector3" then
		warn(("MapSystem: %s has no %s attribute, its terrain was skipped"):format(region:GetFullName(), Config.Maps.TerrainCornerAttribute))
		return
	end
	local cell = (corner + offset) / Config.Maps.VoxelSize
	local ok, err = pcall(function()
		Workspace.Terrain:PasteRegion(region, Vector3int16.new(math.round(cell.X), math.round(cell.Y), math.round(cell.Z)), false)
	end)
	if not ok then
		warn(("MapSystem: could not paste the terrain of %s: %s"):format(model.Name, tostring(err)))
	end
end

local function disableSpawns(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			descendant.Enabled = false
		end
	end
end

local function place(settings: LevelSettings): Model?
	local placed = findPlaced(settings.ModelName)
	if placed then
		disableSpawns(placed)
		return placed
	end
	local stored = findStored(settings.ModelName)
	if not stored then
		warn(("MapSystem: ServerStorage.%s.%s not found"):format(Config.Maps.StorageName, settings.ModelName))
		return nil
	end
	local model = stored:Clone()
	local origin = model:GetAttribute(Config.Maps.OriginAttribute)
	local offset = Vector3.zero
	if settings.Origin and typeof(origin) == "Vector3" then
		offset = snapToVoxels(settings.Origin - origin)
		model:PivotTo(model:GetPivot() + offset)
		model:SetAttribute(Config.Maps.OriginAttribute, origin + offset)
	end
	local terrain = model:FindFirstChild(Config.Maps.TerrainName)
	if terrain and terrain:IsA("TerrainRegion") then
		pasteTerrain(model, terrain, offset)
		terrain:Destroy()
	end
	disableSpawns(model)
	model.Parent = mapsFolder()
	return model
end

local function findMarker(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function feetOf(part: BasePart): CFrame
	return part.CFrame - Vector3.yAxis * (part.Size.Y / 2)
end

local function entryOf(model: Model): CFrame?
	local marker = findMarker(model, Config.Maps.EntryName)
	if marker then
		return feetOf(marker)
	end
	local spawn = model:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.CFrame + Vector3.yAxis * (spawn.Size.Y / 2)
	end
	return nil
end

local function load(key: string): Level?
	local existing = levels[key]
	if existing and existing.model.Parent then
		return existing
	end
	local settings = settingsFor(key)
	if not settings then
		warn("MapSystem: Config.Maps.Levels." .. key .. " not found")
		return nil
	end
	local model = place(settings)
	if not model then
		return nil
	end
	local entry = entryOf(model)
	if not entry then
		warn(("MapSystem: %s has no %s marker or SpawnLocation"):format(model:GetFullName(), Config.Maps.EntryName))
		return nil
	end
	local top = findMarker(model, Config.Maps.ShaftTopName)
	local level: Level = {
		key = key,
		displayName = settings.DisplayName,
		model = model,
		entry = entry,
		shaftTop = if top then top.CFrame else nil,
	}
	levels[key] = level
	return level
end

local function publish(level: Level?)
	Workspace:SetAttribute(Config.Maps.LevelAttribute, if level then level.key else nil)
	Workspace:SetAttribute(Config.Maps.EntryAttribute, if level then level.entry else nil)
	Workspace:SetAttribute(Config.Maps.ShaftTopAttribute, if level then level.shaftTop else nil)
end

function MapSystem.getActive(): Level?
	local key = activeKey
	return if key then levels[key] else nil
end

function MapSystem.getLevel(key: string): Level?
	return levels[key]
end

function MapSystem.activate(key: string): Level?
	local level = load(key)
	if level then
		activeKey = key
	end
	publish(level)
	return level
end

function MapSystem.setPlayerMap(player: Player, key: string?)
	player:SetAttribute(Config.Maps.PlayerAttribute, key)
end

function MapSystem.getPlayerMap(player: Player): string?
	local value = player:GetAttribute(Config.Maps.PlayerAttribute)
	return if type(value) == "string" then value else nil
end

local function watchPlayer(player: Player)
	table.insert(connections, player.CharacterAdded:Connect(function()
		MapSystem.setPlayerMap(player, nil)
	end))
end

function MapSystem.start()
	if isStarted then
		return
	end
	isStarted = true
	local key = Config.Maps.Default
	if key and key ~= "" then
		MapSystem.activate(key)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

function MapSystem.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	activeKey = nil
	publish(nil)
end

return MapSystem
