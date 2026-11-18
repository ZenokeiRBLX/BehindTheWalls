local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local MapSystem = require(script.Parent:WaitForChild("MapSystem"))

local MonsterSystem = {}

local SETTINGS = Config.Monsters
local HIDDEN = "Hidden"
local EMERGING = "Emerging"
local ROAMING = "Roaming"
local NOTICING = "Noticing"
local CHASING = "Chasing"
local SEARCHING = "Searching"
local ATTACKING = "Attacking"
local CAUGHT = "Caught"
local RETREATING = "Retreating"
local ENTERING = "Entering"
local ROOT_NAME = "HumanoidRootPart"
local COLLISION_NAME = "Collision"
local FLOOR_NAME = "Floor"
local FLOOR_PROBE = 40
local FACE_RATE = 8
local DIRECT_RETREAT_DISTANCE = 30
local SEARCH_WANDER = 15
local EPSILON = 0.001
local DISABLED_STATES = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Flying,
}

type Spot = {
	tv: Model,
	glass: Vector3,
	normal: Vector3,
	stand: CFrame,
}

type Victim = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	head: Vector3,
}

type Monster = {
	key: string,
	settings: any,
	level: string,
	levelModel: Model,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	rootHeight: number,
	spots: { Spot },
	collision: Instance?,
	floorMin: Vector2,
	floorMax: Vector2,
	floorY: number,
	state: string,
	stateStart: number,
	target: Player?,
	lastSeen: Vector3?,
	lastSeenAt: number,
	noticed: { [Player]: number },
	waypoints: { PathWaypoint },
	waypointIndex: number,
	pathBusy: boolean,
	pathToken: number,
	pathFailures: number,
	nextRepath: number,
	emergeAt: number,
	nextHopAt: number,
	hopTarget: Player?,
	chaseAfterEmerge: boolean,
	retreatSpot: Spot?,
	activeSince: number?,
	progressAt: number,
	progressPosition: Vector3,
	searchUntil: number,
	searchGoal: Vector3?,
	thinkElapsed: number,
	rng: Random,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local monsters: { Monster } = {}
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Include
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local function flat(vector: Vector3): Vector3
	local value = Vector3.new(vector.X, 0, vector.Z)
	return if value.Magnitude > EPSILON then value.Unit else Vector3.zAxis
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function range(rng: Random, values: { number }): number
	return rng:NextNumber(values[1], values[2])
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function monstersFolder(): Instance
	local folder = Workspace:FindFirstChild(SETTINGS.FolderName)
	if folder then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = SETTINGS.FolderName
	created.Parent = Workspace
	return created
end

local function findTemplate(name: string): Model?
	local storage = ServerStorage:FindFirstChild(SETTINGS.StorageName)
	local stored = if storage then storage:FindFirstChild(name) else nil
	if stored and stored:IsA("Model") then
		return stored
	end
	local placed = Workspace:FindFirstChild(name)
	if placed and placed:IsA("Model") then
		warn(("MonsterSystem: Workspace.%s should live in ServerStorage.%s; moving it there for this server"):format(name, SETTINGS.StorageName))
		if not storage then
			storage = Instance.new("Folder")
			storage.Name = SETTINGS.StorageName
			storage.Parent = ServerStorage
		end
		placed.Parent = storage
		return placed
	end
	warn(("MonsterSystem: ServerStorage.%s.%s not found"):format(SETTINGS.StorageName, name))
	return nil
end

local function setState(monster: Monster, state: string, target: Player?)
	monster.state = state
	monster.stateStart = os.clock()
	monster.target = target
	local model = monster.model
	model:SetAttribute(SETTINGS.StateAttribute, state)
	model:SetAttribute(SETTINGS.StateTimeAttribute, serverNow())
	model:SetAttribute(SETTINGS.TargetAttribute, if target then target.UserId else 0)
end

local function setAnchored(monster: Monster, anchored: boolean)
	monster.root.Anchored = anchored
	if not anchored then
		pcall(function()
			monster.root:SetNetworkOwner(nil)
		end)
	end
end

local function clearPath(monster: Monster)
	monster.pathToken += 1
	table.clear(monster.waypoints)
	monster.waypointIndex = 1
end

local function stop(monster: Monster)
	clearPath(monster)
	if not monster.root.Anchored then
		monster.humanoid:MoveTo(monster.root.Position)
	end
end

local function requestPath(monster: Monster, goal: Vector3)
	if monster.pathBusy then
		return
	end
	local settings = monster.settings.Path
	monster.pathBusy = true
	monster.pathToken += 1
	local token = monster.pathToken
	local start = monster.root.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = settings.AgentRadius,
			AgentHeight = settings.AgentHeight,
			AgentCanJump = false,
			WaypointSpacing = settings.WaypointSpacing,
		})
		local ok = pcall(function()
			path:ComputeAsync(start, goal)
		end)
		monster.pathBusy = false
		if monster.pathToken ~= token or not monster.model.Parent then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			monster.waypoints = path:GetWaypoints()
			monster.waypointIndex = 2
			monster.pathFailures = 0
		else
			table.clear(monster.waypoints)
			monster.pathFailures += 1
		end
	end)
end

local function followPath(monster: Monster): string
	local waypoints = monster.waypoints
	local waypoint = waypoints[monster.waypointIndex]
	if not waypoint then
		return if monster.pathBusy then "waiting" else "idle"
	end
	if flatDistance(waypoint.Position, monster.root.Position) <= monster.settings.Path.ReachDistance then
		monster.waypointIndex += 1
		waypoint = waypoints[monster.waypointIndex]
		if not waypoint then
			table.clear(waypoints)
			return "arrived"
		end
	end
	monster.humanoid:MoveTo(waypoint.Position)
	return "moving"
end

local function checkStuck(monster: Monster, now: number)
	local position = monster.root.Position
	if (position - monster.progressPosition).Magnitude > 1 then
		monster.progressPosition = position
		monster.progressAt = now
		return
	end
	if #monster.waypoints > 0 and now - monster.progressAt > monster.settings.Path.StuckSeconds then
		monster.progressAt = now
		clearPath(monster)
		monster.pathFailures += 1
	end
end

local function victims(monster: Monster): { Victim }
	local list: { Victim } = {}
	for _, player in Players:GetPlayers() do
		if MapSystem.getPlayerMap(player) ~= monster.level or player:GetAttribute(SETTINGS.CaughtAttribute) then
			continue
		end
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if humanoid then humanoid.RootPart else nil
		if not character or not humanoid or not root or humanoid.Health <= 0 or character:GetAttribute(Config.IntroHole.FallingAttribute) then
			continue
		end
		local head = character:FindFirstChild("Head")
		table.insert(list, {
			player = player,
			character = character,
			humanoid = humanoid,
			root = root,
			head = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.yAxis * 1.5,
		})
	end
	return list
end

local function victimOf(monster: Monster, player: Player?): Victim?
	if not player then
		return nil
	end
	for _, victim in victims(monster) do
		if victim.player == player then
			return victim
		end
	end
	return nil
end

local function eyePosition(monster: Monster): Vector3
	return monster.root.Position + Vector3.yAxis * (monster.settings.EyeHeight - monster.rootHeight)
end

local function canSee(monster: Monster, victim: Victim): boolean
	local senses = monster.settings.Senses
	local eye = eyePosition(monster)
	local toTarget = victim.head - eye
	local distance = toTarget.Magnitude
	if distance > senses.SightRange then
		return false
	end
	if distance > senses.CloseRange then
		local forward = flat(monster.root.CFrame.LookVector)
		local angle = math.deg(math.acos(math.clamp(forward:Dot(flat(toTarget)), -1, 1)))
		if angle > senses.SightAngle / 2 then
			return false
		end
	end
	if monster.collision then
		sightParams.FilterDescendantsInstances = { monster.collision }
		if Workspace:Raycast(eye, toTarget, sightParams) then
			return false
		end
	end
	return true
end

local function nearestVisible(monster: Monster): Victim?
	local best: Victim? = nil
	local bestDistance = math.huge
	for _, victim in victims(monster) do
		local distance = (victim.root.Position - monster.root.Position).Magnitude
		if distance < bestDistance and canSee(monster, victim) then
			best = victim
			bestDistance = distance
		end
	end
	return best
end

local function heardVictim(monster: Monster): Victim?
	local senses = monster.settings.Senses
	for _, victim in victims(monster) do
		local velocity = victim.root.AssemblyLinearVelocity
		local loud = Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= senses.HearSpeed
		if loud and (victim.root.Position - monster.root.Position).Magnitude <= senses.HearRange then
			return victim
		end
	end
	return nil
end

local function floorAt(monster: Monster, position: Vector3, height: number): number?
	local floorModel = monster.levelModel:FindFirstChild(FLOOR_NAME)
	floorParams.FilterDescendantsInstances = { floorModel or monster.levelModel }
	local hit = Workspace:Raycast(Vector3.new(position.X, height, position.Z), Vector3.new(0, -FLOOR_PROBE, 0), floorParams)
	return if hit then hit.Position.Y else nil
end

local function clear(monster: Monster, center: Vector3, size: Vector3): boolean
	if not monster.collision then
		return true
	end
	overlapParams.FilterDescendantsInstances = { monster.collision }
	return #Workspace:GetPartBoundsInBox(CFrame.new(center), size, overlapParams) == 0
end

local function collectSpots(monster: Monster)
	local tv = monster.settings.Tv
	local clearance = Vector3.new(tv.Clearance[1], tv.Clearance[2], tv.Clearance[3])
	local shaft = monster.levelModel:FindFirstChild("EntryShaft")
	for _, model in CollectionService:GetTagged(SETTINGS.TvTag) do
		if not model:IsA("Model") or not model:IsDescendantOf(monster.levelModel) or (shaft and model:IsDescendantOf(shaft)) then
			continue
		end
		local glass = model:FindFirstChild(SETTINGS.TvGlassName)
		if not glass or not glass:IsA("BasePart") then
			continue
		end
		local normal = flat(model:GetPivot().LookVector)
		local standXZ = glass.Position + normal * (tv.StandOff + monster.root.Size.Z)
		local floorY = floorAt(monster, standXZ, glass.Position.Y)
		if not floorY or glass.Position.Y - floorY > tv.MaxGlassHeight then
			continue
		end
		local standPosition = Vector3.new(standXZ.X, floorY + monster.rootHeight, standXZ.Z)
		if not clear(monster, Vector3.new(standXZ.X, floorY + clearance.Y / 2 + 1, standXZ.Z), clearance) then
			continue
		end
		table.insert(monster.spots, {
			tv = model,
			glass = glass.Position,
			normal = normal,
			stand = CFrame.lookAt(standPosition, standPosition + normal),
		})
	end
end

local function pickSpot(monster: Monster, target: Victim?, near: boolean): Spot?
	local tv = monster.settings.Tv
	local spots = monster.spots
	if #spots == 0 then
		return nil
	end
	if target then
		local minimum = if near then tv.ChaseMinDistance else tv.MinDistance
		local maximum = if near then tv.ChaseMaxDistance else tv.MaxDistance
		local ideal = if near then (minimum + maximum) / 2 else tv.IdealDistance
		local best: Spot? = nil
		local bestScore = math.huge
		for _, spot in spots do
			local distance = (spot.stand.Position - target.root.Position).Magnitude
			if distance >= minimum and distance <= maximum then
				local score = math.abs(distance - ideal) + monster.rng:NextNumber(0, 12)
				if score < bestScore then
					best = spot
					bestScore = score
				end
			end
		end
		if best then
			return best
		end
	end
	return spots[monster.rng:NextInteger(1, #spots)]
end

local function nearestSpot(monster: Monster): (Spot?, number)
	local best: Spot? = nil
	local bestDistance = math.huge
	for _, spot in monster.spots do
		local distance = (spot.stand.Position - monster.root.Position).Magnitude
		if distance < bestDistance then
			best = spot
			bestDistance = distance
		end
	end
	return best, bestDistance
end

local function setTv(monster: Monster, spot: Spot)
	monster.model:SetAttribute(SETTINGS.TvGlassAttribute, spot.glass)
	monster.model:SetAttribute(SETTINGS.TvNormalAttribute, spot.normal)
end

local function emerge(monster: Monster, target: Victim?, near: boolean): boolean
	local spot = pickSpot(monster, target, near)
	if not spot then
		return false
	end
	clearPath(monster)
	setAnchored(monster, true)
	monster.model:PivotTo(spot.stand)
	setTv(monster, spot)
	monster.chaseAfterEmerge = near and target ~= nil
	if target then
		monster.lastSeen = target.root.Position
		monster.lastSeenAt = os.clock()
	end
	setState(monster, EMERGING, if target then target.player else nil)
	return true
end

local function enter(monster: Monster, spot: Spot)
	clearPath(monster)
	setAnchored(monster, true)
	local position = monster.root.Position
	monster.model:PivotTo(CFrame.lookAt(position, position - spot.normal))
	setTv(monster, spot)
	setState(monster, ENTERING, monster.target)
end

local function hide(monster: Monster)
	local timing = monster.settings.Timing
	setAnchored(monster, true)
	local duration = if monster.hopTarget then range(monster.rng, timing.ChaseHop) else range(monster.rng, timing.InTv)
	monster.emergeAt = os.clock() + duration
	setState(monster, HIDDEN, monster.hopTarget)
end

local function retreat(monster: Monster, hopTarget: Player?)
	monster.hopTarget = hopTarget
	local spot, distance = nearestSpot(monster)
	if not spot then
		hide(monster)
		return
	end
	monster.retreatSpot = spot
	if distance > DIRECT_RETREAT_DISTANCE or monster.root.Anchored then
		enter(monster, spot)
		return
	end
	monster.humanoid.WalkSpeed = monster.settings.Speeds.Retreat
	monster.humanoid.AutoRotate = true
	setState(monster, RETREATING, monster.target)
	clearPath(monster)
	requestPath(monster, spot.stand.Position)
end

local function randomRoamGoal(monster: Monster): Vector3?
	local path = monster.settings.Path
	local list = victims(monster)
	for _ = 1, 8 do
		local candidate: Vector3
		if #list > 0 and monster.rng:NextNumber() < 0.65 then
			local victim = list[monster.rng:NextInteger(1, #list)]
			local angle = monster.rng:NextNumber(0, math.pi * 2)
			local distance = range(monster.rng, path.RoamRadius)
			candidate = victim.root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
		else
			candidate = Vector3.new(
				monster.rng:NextNumber(monster.floorMin.X, monster.floorMax.X),
				monster.floorY,
				monster.rng:NextNumber(monster.floorMin.Y, monster.floorMax.Y)
			)
		end
		local floorY = floorAt(monster, candidate, monster.floorY + 30)
		if floorY then
			local goal = Vector3.new(candidate.X, floorY + 3, candidate.Z)
			if clear(monster, goal + Vector3.yAxis * 2, Vector3.new(4, 6, 4)) then
				return goal
			end
		end
	end
	return nil
end

local function startChase(monster: Monster, victim: Victim)
	monster.lastSeen = victim.root.Position
	monster.lastSeenAt = os.clock()
	monster.noticed[victim.player] = os.clock()
	monster.humanoid.WalkSpeed = monster.settings.Speeds.Chase
	monster.humanoid.AutoRotate = true
	monster.nextRepath = 0
	monster.pathFailures = 0
	setState(monster, CHASING, victim.player)
end

local function notice(monster: Monster, victim: Victim)
	local last = monster.noticed[victim.player]
	if last and os.clock() - last < monster.settings.Senses.NoticeCooldown then
		startChase(monster, victim)
		return
	end
	stop(monster)
	monster.humanoid.AutoRotate = false
	monster.lastSeen = victim.root.Position
	monster.lastSeenAt = os.clock()
	monster.noticed[victim.player] = os.clock()
	setState(monster, NOTICING, victim.player)
end

local function search(monster: Monster, position: Vector3?)
	monster.searchGoal = position
	monster.searchUntil = os.clock() + monster.settings.Timing.Search
	monster.humanoid.WalkSpeed = monster.settings.Speeds.Search
	monster.humanoid.AutoRotate = true
	clearPath(monster)
	if position then
		requestPath(monster, position)
	end
	setState(monster, SEARCHING, nil)
end

local function roam(monster: Monster)
	monster.humanoid.WalkSpeed = monster.settings.Speeds.Roam
	monster.humanoid.AutoRotate = true
	clearPath(monster)
	setState(monster, ROAMING, nil)
end

local function catch(monster: Monster, victim: Victim)
	stop(monster)
	monster.humanoid.AutoRotate = false
	victim.root.Anchored = true
	victim.player:SetAttribute(SETTINGS.CaughtAttribute, true)
	setState(monster, CAUGHT, victim.player)
	local player = victim.player
	local humanoid = victim.humanoid
	task.delay(monster.settings.Timing.Caught, function()
		if humanoid.Parent then
			humanoid.Health = 0
		end
		if player.Parent then
			player:SetAttribute(SETTINGS.CaughtAttribute, nil)
		end
	end)
end

local function faceToward(monster: Monster, position: Vector3, dt: number)
	local root = monster.root
	if root.Anchored then
		return
	end
	local direction = flat(position - root.Position)
	local goal = CFrame.lookAt(root.Position, root.Position + direction)
	root.CFrame = root.CFrame:Lerp(goal, 1 - math.exp(-FACE_RATE * dt))
end

local function thinkHidden(monster: Monster, now: number)
	local list = victims(monster)
	if #list == 0 or now < monster.emergeAt then
		return
	end
	local hop = victimOf(monster, monster.hopTarget)
	local target = hop or list[monster.rng:NextInteger(1, #list)]
	monster.hopTarget = nil
	if not emerge(monster, target, hop ~= nil) then
		monster.emergeAt = now + 2
	end
end

local function thinkWander(monster: Monster, now: number)
	local seen = nearestVisible(monster)
	if seen then
		notice(monster, seen)
		return
	end
	if monster.state == ROAMING then
		local heard = heardVictim(monster)
		if heard then
			search(monster, heard.root.Position)
			return
		end
		if now >= monster.nextHopAt then
			monster.nextHopAt = now + range(monster.rng, monster.settings.Timing.RoamHop)
			retreat(monster, nil)
			return
		end
	elseif now >= monster.searchUntil then
		roam(monster)
		return
	end
	local status = followPath(monster)
	if status == "idle" or status == "arrived" then
		local goal: Vector3?
		if monster.state == SEARCHING then
			local center = monster.searchGoal or monster.root.Position
			local angle = monster.rng:NextNumber(0, math.pi * 2)
			goal = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * monster.rng:NextNumber(4, SEARCH_WANDER)
		else
			goal = randomRoamGoal(monster)
		end
		if goal then
			requestPath(monster, goal)
		end
	end
	checkStuck(monster, now)
end

local function thinkChase(monster: Monster, now: number)
	local settings = monster.settings
	local victim = victimOf(monster, monster.target)
	if not victim then
		if monster.lastSeen then
			search(monster, monster.lastSeen)
		else
			roam(monster)
		end
		return
	end
	local visible = canSee(monster, victim)
	if visible then
		monster.lastSeen = victim.root.Position
		monster.lastSeenAt = now
	end
	local distance = (victim.root.Position - monster.root.Position).Magnitude
	if visible and distance <= settings.Attack.Range then
		monster.humanoid.WalkSpeed = settings.Speeds.Lunge
		monster.humanoid.AutoRotate = false
		clearPath(monster)
		setState(monster, ATTACKING, victim.player)
		return
	end
	if now - monster.lastSeenAt > settings.Senses.LoseSeconds then
		search(monster, monster.lastSeen)
		return
	end
	if visible and distance <= settings.Path.DirectChaseDistance then
		clearPath(monster)
		monster.humanoid:MoveTo(victim.root.Position)
	else
		if now >= monster.nextRepath then
			monster.nextRepath = now + settings.Path.RepathSeconds
			requestPath(monster, victim.root.Position)
		end
		followPath(monster)
		checkStuck(monster, now)
		if monster.pathFailures >= settings.Path.FailuresBeforeHop then
			monster.pathFailures = 0
			retreat(monster, victim.player)
		end
	end
end

local function thinkAttack(monster: Monster, now: number)
	local victim = victimOf(monster, monster.target)
	if not victim then
		roam(monster)
		return
	end
	monster.humanoid:MoveTo(victim.root.Position)
	if now - monster.stateStart < monster.settings.Timing.AttackWindup then
		return
	end
	if (victim.root.Position - monster.root.Position).Magnitude <= monster.settings.Attack.Reach then
		catch(monster, victim)
	else
		startChase(monster, victim)
	end
end

local function think(monster: Monster, now: number)
	local list = victims(monster)
	local state = monster.state
	if #list == 0 then
		monster.activeSince = nil
		if state ~= HIDDEN and state ~= ENTERING and state ~= CAUGHT then
			local spot = nearestSpot(monster)
			if spot then
				enter(monster, spot)
			else
				hide(monster)
			end
		end
		return
	end
	if not monster.activeSince then
		monster.activeSince = now
		if state == HIDDEN then
			monster.emergeAt = now + monster.settings.Timing.FirstDelay
		end
	end
	local timing = monster.settings.Timing
	local elapsed = now - monster.stateStart
	if state == HIDDEN then
		thinkHidden(monster, now)
	elseif state == EMERGING then
		if elapsed >= timing.Emerge then
			setAnchored(monster, false)
			monster.nextHopAt = now + range(monster.rng, timing.RoamHop)
			local victim = victimOf(monster, monster.target)
			if monster.chaseAfterEmerge and victim then
				startChase(monster, victim)
			else
				roam(monster)
			end
		end
	elseif state == ENTERING then
		if elapsed >= timing.Enter then
			hide(monster)
		end
	elseif state == CAUGHT then
		if elapsed >= timing.Caught + timing.AfterCatch then
			retreat(monster, nil)
		end
	elseif state == NOTICING then
		if elapsed >= timing.Notice then
			local victim = victimOf(monster, monster.target)
			if victim then
				startChase(monster, victim)
			else
				search(monster, monster.lastSeen)
			end
		end
	elseif state == RETREATING then
		local spot = monster.retreatSpot
		if not spot then
			hide(monster)
			return
		end
		local status = followPath(monster)
		if flatDistance(spot.stand.Position, monster.root.Position) <= monster.settings.Tv.EnterDistance or status == "arrived" or status == "idle" or monster.pathFailures > 0 then
			enter(monster, spot)
		end
		checkStuck(monster, now)
	elseif state == ROAMING or state == SEARCHING then
		thinkWander(monster, now)
	elseif state == CHASING then
		thinkChase(monster, now)
	elseif state == ATTACKING then
		thinkAttack(monster, now)
	end
end

local function targetPosition(monster: Monster): Vector3?
	local player = monster.target
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild(ROOT_NAME) else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function onHeartbeat(dt: number)
	local now = os.clock()
	for _, monster in monsters do
		if not monster.model.Parent then
			continue
		end
		local state = monster.state
		if state == NOTICING or state == ATTACKING or state == CAUGHT then
			local position = targetPosition(monster)
			if position then
				faceToward(monster, position, dt)
			end
		end
		monster.thinkElapsed += dt
		if monster.thinkElapsed >= monster.settings.Timing.Think then
			monster.thinkElapsed = 0
			think(monster, now)
		end
	end
end

local function build(key: string, levelKey: string, levelModel: Model): Monster?
	local settings = (SETTINGS.Types :: any)[key]
	if not settings then
		warn("MonsterSystem: Config.Monsters.Types." .. key .. " not found")
		return nil
	end
	local template = findTemplate(settings.ModelName)
	if not template then
		return nil
	end
	local model = template:Clone()
	model:ScaleTo(settings.Scale)
	local mesh = model:FindFirstChildWhichIsA("MeshPart")
	if not mesh then
		warn("MonsterSystem: " .. settings.ModelName .. " has no MeshPart")
		return nil
	end
	local rootSize = Vector3.new(settings.RootSize[1], settings.RootSize[2], settings.RootSize[3])
	local root = Instance.new("Part")
	root.Name = ROOT_NAME
	root.Size = rootSize
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Anchored = true
	local look = flat(mesh.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(mesh.Position, mesh.Position + look)
	root.Parent = model
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = root
		end
	end
	model.PrimaryPart = root
	local halfMesh = mesh.Size.Y / 2
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = halfMesh - rootSize.Y / 2 + settings.Hover
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoJumpEnabled = false
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.WalkSpeed = settings.Speeds.Roam
	humanoid.Parent = model
	for _, state in DISABLED_STATES do
		humanoid:SetStateEnabled(state, false)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute(SETTINGS.TypeAttribute, key)
	CollectionService:AddTag(model, SETTINGS.Tag)

	local floorModel = levelModel:FindFirstChild(FLOOR_NAME)
	local floorPart = if floorModel then floorModel:FindFirstChildWhichIsA("BasePart", true) else nil
	local floorCFrame, floorSize = levelModel:GetBoundingBox()
	if floorPart then
		floorCFrame, floorSize = floorPart.CFrame, floorPart.Size
	end
	local floorTop = floorCFrame.Position.Y + floorSize.Y / 2

	local monster: Monster = {
		key = key,
		settings = settings,
		level = levelKey,
		levelModel = levelModel,
		model = model,
		root = root,
		humanoid = humanoid,
		rootHeight = humanoid.HipHeight + rootSize.Y / 2,
		spots = {},
		collision = levelModel:FindFirstChild(COLLISION_NAME),
		floorMin = Vector2.new(floorCFrame.Position.X - floorSize.X / 2, floorCFrame.Position.Z - floorSize.Z / 2),
		floorMax = Vector2.new(floorCFrame.Position.X + floorSize.X / 2, floorCFrame.Position.Z + floorSize.Z / 2),
		floorY = floorTop,
		state = HIDDEN,
		stateStart = os.clock(),
		target = nil,
		lastSeen = nil,
		lastSeenAt = 0,
		noticed = {},
		waypoints = {},
		waypointIndex = 1,
		pathBusy = false,
		pathToken = 0,
		pathFailures = 0,
		nextRepath = 0,
		emergeAt = math.huge,
		nextHopAt = math.huge,
		hopTarget = nil,
		chaseAfterEmerge = false,
		retreatSpot = nil,
		activeSince = nil,
		progressAt = os.clock(),
		progressPosition = Vector3.zero,
		searchUntil = 0,
		searchGoal = nil,
		thinkElapsed = 0,
		rng = Random.new(),
	}
	collectSpots(monster)
	if #monster.spots == 0 then
		warn("MonsterSystem: no usable TVs for " .. key .. " in " .. levelKey)
		model:Destroy()
		return nil
	end
	local first = monster.spots[1]
	model:PivotTo(first.stand)
	model.Parent = monstersFolder()
	setState(monster, HIDDEN, nil)
	return monster
end

local function onCharacterAdded(player: Player)
	player:SetAttribute(SETTINGS.CaughtAttribute, nil)
end

function MonsterSystem.getMonsters(): { Model }
	local list = {}
	for _, monster in monsters do
		table.insert(list, monster.model)
	end
	return list
end

function MonsterSystem.start()
	if isStarted then
		return
	end
	isStarted = true
	local level = MapSystem.getActive()
	if level then
		local settings = (Config.Maps.Levels :: any)[level.key]
		for _, key in (if settings then settings.Monsters else nil) or {} do
			local monster = build(key, level.key, level.model)
			if monster then
				table.insert(monsters, monster)
			end
		end
	end
	table.insert(connections, RunService.Heartbeat:Connect(onHeartbeat))
	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		table.insert(connections, player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end))
	end))
	for _, player in Players:GetPlayers() do
		table.insert(connections, player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end))
	end
end

function MonsterSystem.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, monster in monsters do
		monster.model:Destroy()
	end
	table.clear(monsters)
end

return MonsterSystem
