local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

local IntroHoleSystem = {}

local CENTER_ATTRIBUTE = "IntroHoleCenter"
local RADIUS_ATTRIBUTE = "IntroHoleRadius"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local DEFAULT_GROUP = "Default"
local FLOOR_SEARCH_HEIGHT = 6
local FLOOR_SEARCH_DEPTH = 20
local RIM_MARGIN = 3
local EPSILON = 0.001

type Fall = {
	character: Model,
	target: CFrame,
	groups: { [BasePart]: string },
	connection: RBXScriptConnection?,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local falls: { [Player]: Fall } = {}
local cooldowns: { [Player]: number } = {}
local center: Vector3? = nil
local pollElapsed = 0
local warnedDestination = false

local function findHole(): (Instance?, BasePart?)
	local settings = Config.IntroHole
	local model = Workspace:FindFirstChild(settings.ModelName) or Workspace:FindFirstChild(settings.ModelName, true)
	if not model then
		return nil, nil
	end
	local part = model:FindFirstChild(settings.HolePartName, true)
	return model, if part and part:IsA("BasePart") then part else nil
end

local function holeBounds(model: Instance, part: BasePart?): (Vector3?, number?)
	if part then
		return part.Position, part.Position.Y + part.ExtentsSize.Y / 2
	end
	if model:IsA("Model") then
		local cframe, size = model:GetBoundingBox()
		return cframe.Position, cframe.Position.Y + size.Y / 2
	end
	if model:IsA("BasePart") then
		return model.Position, model.Position.Y + model.ExtentsSize.Y / 2
	end
	return nil, nil
end

local function resolveCenter(): Vector3?
	local model, part = findHole()
	if not model then
		warn("IntroHoleSystem: Workspace." .. Config.IntroHole.ModelName .. " not found, the sewer hole is disabled")
		return nil
	end
	local position, top = holeBounds(model, part)
	if not position or not top then
		warn("IntroHoleSystem: could not measure " .. model:GetFullName())
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local origin = Vector3.new(position.X, top + FLOOR_SEARCH_HEIGHT, position.Z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(FLOOR_SEARCH_HEIGHT + FLOOR_SEARCH_DEPTH), 0), params)
	local planeY = if hit then hit.Position.Y else top
	return Vector3.new(position.X, planeY, position.Z)
end

local function registerGroup()
	local name = Config.IntroHole.CollisionGroup
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
	PhysicsService:CollisionGroupSetCollidable(name, DEFAULT_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(name, name, false)
end

local function findDestination(): Instance?
	local name = Config.IntroHole.DestinationName
	local found = if name ~= "" then Workspace:FindFirstChild(name, true) else nil
	if found and (found:IsA("BasePart") or found:IsA("Model")) then
		return found
	end
	local landing = Workspace:FindFirstChild(Config.Cutscene.Landing.ModelName, true)
	local spawn = if landing then landing:FindFirstChildWhichIsA("SpawnLocation", true) else nil
	if not warnedDestination then
		warnedDestination = true
		local fallback = if spawn then spawn:GetFullName() else "the rim of the hole"
		warn(("IntroHoleSystem: Workspace.%s not found, the hole drops players at %s"):format(name, fallback))
	end
	return spawn
end

local function surfaceOf(destination: Instance): CFrame?
	if destination:IsA("BasePart") then
		return destination.CFrame + Vector3.yAxis * (destination.ExtentsSize.Y / 2)
	end
	if destination:IsA("Model") then
		return destination:GetPivot()
	end
	return nil
end

local function flatten(vector: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < EPSILON then
		return fallback
	end
	return flat.Unit
end

local function arrivalCFrame(humanoid: Humanoid, root: BasePart, hole: Vector3): CFrame
	local standHeight = humanoid.HipHeight + root.Size.Y / 2 + Config.IntroHole.ArrivalDropHeight
	local destination = findDestination()
	local surface = if destination then surfaceOf(destination) else nil
	if surface then
		local position = surface.Position + Vector3.yAxis * standHeight
		return CFrame.lookAt(position, position + flatten(surface.LookVector, -Vector3.zAxis))
	end
	local away = flatten(root.Position - hole, -root.CFrame.LookVector)
	local position = hole + away * (Config.IntroHole.TriggerRadius + RIM_MARGIN) + Vector3.yAxis * standHeight
	return CFrame.lookAt(position, position + away)
end

local function moveToFallGroup(fall: Fall, instance: Instance)
	if not instance:IsA("BasePart") or fall.groups[instance] ~= nil then
		return
	end
	local group = Config.IntroHole.CollisionGroup
	fall.groups[instance] = if instance.CollisionGroup == group then DEFAULT_GROUP else instance.CollisionGroup
	instance.CollisionGroup = group
end

local function restoreGroups(fall: Fall)
	if fall.connection then
		fall.connection:Disconnect()
		fall.connection = nil
	end
	for part, group in fall.groups do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	table.clear(fall.groups)
end

local function endFall(player: Player)
	local fall = falls[player]
	if not fall then
		return
	end
	falls[player] = nil
	restoreGroups(fall)
	if fall.character.Parent then
		fall.character:SetAttribute(Config.IntroHole.FallingAttribute, nil)
	end
	cooldowns[player] = os.clock() + Config.IntroHole.RetriggerCooldown
end

local function land(player: Player, fall: Fall)
	if falls[player] ~= fall then
		return
	end
	local character = fall.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if not character.Parent or not humanoid or not root or humanoid.Health <= 0 then
		endFall(player)
		return
	end
	character:SetAttribute(Config.IntroHole.ArrivalAttribute, fall.target)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(fall.target)
	endFall(player)
end

local function beginFall(player: Player, character: Model, humanoid: Humanoid, root: BasePart, hole: Vector3)
	local settings = Config.IntroHole
	local fall: Fall = {
		character = character,
		target = arrivalCFrame(humanoid, root, hole),
		groups = {},
		connection = nil,
	}
	falls[player] = fall
	for _, descendant in character:GetDescendants() do
		moveToFallGroup(fall, descendant)
	end
	fall.connection = character.DescendantAdded:Connect(function(descendant)
		moveToFallGroup(fall, descendant)
	end)
	character:SetAttribute(settings.ArrivalAttribute, nil)
	character:SetAttribute(settings.FallingAttribute, true)
	task.spawn(function()
		local ok, err = pcall(function()
			player:RequestStreamAroundAsync(fall.target.Position, settings.StreamTimeout)
		end)
		if not ok then
			warn(("IntroHoleSystem: could not stream the landing for %s: %s"):format(player.Name, tostring(err)))
		end
	end)
	task.delay(settings.FallSeconds, land, player, fall)
end

local function isInHole(root: BasePart, hole: Vector3): boolean
	local settings = Config.IntroHole
	local offset = root.Position - hole
	if offset.Y > settings.TriggerHeight or offset.Y < -settings.TriggerDepth then
		return false
	end
	return Vector2.new(offset.X, offset.Z).Magnitude <= settings.TriggerRadius
end

local function checkPlayer(player: Player, hole: Vector3, now: number)
	if falls[player] or now < (cooldowns[player] or 0) then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(RAGDOLL_ATTRIBUTE) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if isInHole(root, hole) then
		beginFall(player, character, humanoid, root, hole)
	end
end

local function poll(dt: number)
	pollElapsed += dt
	if pollElapsed < Config.IntroHole.ServerPollSeconds then
		return
	end
	pollElapsed = 0
	local hole = center
	if not hole then
		return
	end
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		checkPlayer(player, hole, now)
	end
end

local function onPlayerRemoving(player: Player)
	endFall(player)
	cooldowns[player] = nil
end

function IntroHoleSystem.start()
	if isStarted then
		return
	end
	isStarted = true
	center = resolveCenter()
	if not center then
		return
	end
	registerGroup()
	Workspace:SetAttribute(CENTER_ATTRIBUTE, center)
	Workspace:SetAttribute(RADIUS_ATTRIBUTE, Config.IntroHole.TriggerRadius)
	findDestination()
	table.insert(connections, RunService.Heartbeat:Connect(poll))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

function IntroHoleSystem.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local players = {}
	for player in falls do
		table.insert(players, player)
	end
	for _, player in players do
		endFall(player)
	end
	table.clear(cooldowns)
	center = nil
	Workspace:SetAttribute(CENTER_ATTRIBUTE, nil)
	Workspace:SetAttribute(RADIUS_ATTRIBUTE, nil)
end

return IntroHoleSystem
