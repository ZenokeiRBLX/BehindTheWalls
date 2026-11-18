local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local MapSystem = require(script.Parent:WaitForChild("MapSystem"))

local IntroHoleSystem = {}

local CENTER_ATTRIBUTE = "IntroHoleCenter"
local RADIUS_ATTRIBUTE = "IntroHoleRadius"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local DEFAULT_GROUP = "Default"
local FLOOR_SEARCH_HEIGHT = 6
local FLOOR_SEARCH_DEPTH = 20
local RIM_MARGIN = 3
local SETTLE_HEIGHT = 12
local SETTLE_RADIUS = 30
local EPSILON = 0.001

type Fall = {
	character: Model,
	target: CFrame,
	transit: CFrame?,
	level: string?,
	groups: { [BasePart]: string },
	connection: RBXScriptConnection?,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local falls: { [Player]: Fall } = {}
local cooldowns: { [Player]: number } = {}
local respawnDrops: { [Player]: string } = {}
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

local function standHeight(humanoid: Humanoid, root: BasePart): number
	return humanoid.HipHeight + root.Size.Y / 2
end

local function levelCFrame(entry: CFrame, humanoid: Humanoid, root: BasePart): CFrame
	local position = entry.Position + Vector3.yAxis * standHeight(humanoid, root)
	return CFrame.lookAt(position, position + flatten(entry.LookVector, -Vector3.zAxis))
end

local function descentSeconds(transit: CFrame, landing: CFrame): number
	local settings = Config.IntroHole.Level
	local distance = math.max(transit.Position.Y - (landing.Position.Y + settings.ReleaseHeight), 0)
	return 2 * distance / math.max(settings.StartSpeed + settings.EndSpeed, EPSILON)
end

local function arrivalCFrame(humanoid: Humanoid, root: BasePart, hole: Vector3): CFrame
	local height = standHeight(humanoid, root) + Config.IntroHole.ArrivalDropHeight
	local destination = findDestination()
	local surface = if destination then surfaceOf(destination) else nil
	if surface then
		local position = surface.Position + Vector3.yAxis * height
		return CFrame.lookAt(position, position + flatten(surface.LookVector, -Vector3.zAxis))
	end
	local away = flatten(root.Position - hole, -root.CFrame.LookVector)
	local position = hole + away * (Config.IntroHole.TriggerRadius + RIM_MARGIN) + Vector3.yAxis * height
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
		fall.character:SetAttribute(Config.IntroHole.Level.TransitAttribute, nil)
	end
	cooldowns[player] = os.clock() + Config.IntroHole.RetriggerCooldown
end

local function livingBody(fall: Fall): (Humanoid?, BasePart?)
	local character = fall.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if not character.Parent or not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

local function moveBody(fall: Fall, root: BasePart, target: CFrame)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	fall.character:PivotTo(target)
end

local function land(player: Player, fall: Fall)
	if falls[player] ~= fall then
		return
	end
	local _, root = livingBody(fall)
	if not root then
		endFall(player)
		return
	end
	fall.character:SetAttribute(Config.IntroHole.ArrivalAttribute, fall.target)
	moveBody(fall, root, fall.target)
	if fall.level then
		MapSystem.setPlayerMap(player, fall.level)
	end
	endFall(player)
end

local function settle(player: Player, fall: Fall)
	if falls[player] ~= fall then
		return
	end
	local _, root = livingBody(fall)
	if not root then
		endFall(player)
		return
	end
	fall.character:SetAttribute(Config.IntroHole.ArrivalAttribute, fall.target)
	local offset = root.Position - fall.target.Position
	if math.abs(offset.Y) > SETTLE_HEIGHT or Vector2.new(offset.X, offset.Z).Magnitude > SETTLE_RADIUS then
		moveBody(fall, root, fall.target)
	end
	endFall(player)
end

local function enterLevel(player: Player, fall: Fall)
	if falls[player] ~= fall then
		return
	end
	local transit = fall.transit
	local _, root = livingBody(fall)
	if not root or not transit then
		land(player, fall)
		return
	end
	local settings = Config.IntroHole.Level
	fall.character:SetAttribute(settings.TransitAttribute, transit)
	moveBody(fall, root, transit)
	if fall.level then
		MapSystem.setPlayerMap(player, fall.level)
	end
	task.delay(settings.CardSeconds + descentSeconds(transit, fall.target) + settings.FinalizeMargin, settle, player, fall)
end

local function claimBody(fall: Fall)
	local character = fall.character
	for _, descendant in character:GetDescendants() do
		moveToFallGroup(fall, descendant)
	end
	fall.connection = character.DescendantAdded:Connect(function(descendant)
		moveToFallGroup(fall, descendant)
	end)
end

local function streamAround(player: Player, positions: { Vector3 })
	task.spawn(function()
		for _, position in positions do
			local ok, err = pcall(function()
				player:RequestStreamAroundAsync(position, Config.IntroHole.StreamTimeout)
			end)
			if not ok then
				warn(("IntroHoleSystem: could not stream the landing for %s: %s"):format(player.Name, tostring(err)))
			end
		end
	end)
end

local function beginFall(player: Player, character: Model, humanoid: Humanoid, root: BasePart, hole: Vector3)
	local settings = Config.IntroHole
	local level = MapSystem.getActive()
	local fall: Fall = {
		character = character,
		target = if level then levelCFrame(level.entry, humanoid, root) else arrivalCFrame(humanoid, root, hole),
		transit = if level then level.shaftTop else nil,
		level = if level then level.key else nil,
		groups = {},
		connection = nil,
	}
	falls[player] = fall
	claimBody(fall)
	character:SetAttribute(settings.ArrivalAttribute, nil)
	character:SetAttribute(settings.Level.TransitAttribute, nil)
	character:SetAttribute(settings.FallingAttribute, true)
	local transit = fall.transit
	streamAround(player, if transit then { fall.target.Position, transit.Position } else { fall.target.Position })
	task.delay(settings.FallSeconds, if transit then enterLevel else land, player, fall)
end

local function dropIntoLevel(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	local level = MapSystem.getActive()
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") or not level or not level.shaftTop then
		return
	end
	task.wait()
	if falls[player] or player.Character ~= character then
		return
	end
	local settings = Config.IntroHole
	local transit = level.shaftTop :: CFrame
	local fall: Fall = {
		character = character,
		target = levelCFrame(level.entry, humanoid, root),
		transit = transit,
		level = level.key,
		groups = {},
		connection = nil,
	}
	falls[player] = fall
	claimBody(fall)
	MapSystem.setPlayerMap(player, level.key)
	character:SetAttribute(settings.ArrivalAttribute, nil)
	character:SetAttribute(settings.Level.TransitAttribute, transit)
	character:SetAttribute(settings.FallingAttribute, true)
	moveBody(fall, root, transit)
	streamAround(player, { fall.target.Position, transit.Position })
	local levelSettings = settings.Level
	task.delay(levelSettings.RespawnHoldSeconds + descentSeconds(transit, fall.target) + levelSettings.FinalizeMargin, settle, player, fall)
end

local function watchRespawns(player: Player)
	local function onCharacter(character: Model)
		local key = respawnDrops[player]
		respawnDrops[player] = nil
		if key then
			task.spawn(dropIntoLevel, player, character)
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		humanoid.Died:Once(function()
			local level = MapSystem.getActive()
			if level and level.shaftTop and MapSystem.getPlayerMap(player) == level.key then
				respawnDrops[player] = level.key
				MapSystem.setRespawnMap(player, level.key)
			end
		end)
	end
	table.insert(connections, player.CharacterAdded:Connect(onCharacter))
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
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
	respawnDrops[player] = nil
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
	if not MapSystem.getActive() then
		findDestination()
	end
	table.insert(connections, RunService.Heartbeat:Connect(poll))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	table.insert(connections, Players.PlayerAdded:Connect(watchRespawns))
	for _, player in Players:GetPlayers() do
		watchRespawns(player)
	end
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
