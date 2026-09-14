local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))
local WRagdoll = require(ReplicatedStorage:WaitForChild("WRagdoll"))
local MatchSystem = require(script.Parent:WaitForChild("MatchSystem"))

local GameSpawnSystem = {}

local SLOTS_FOLDER_NAME = "Teleport_Players"
local SLOT_WAIT = 10
local SLOT_HEIGHT_OFFSET = 3
local SLOT_ATTRIBUTE = "SpawnSlot"
local CUTSCENE_MARGIN = 10
local WALK_END_ATTRIBUTE_PREFIX = "CutsceneWalkEnd"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local ROOT_JOINT_NAME = "Root"
local RAGDOLL_WELD_NAME = "RagdollWeld"
local ENGINE_SOCKET_SUFFIX = "BallSocket$"
local FOOT_PART_NAMES = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }
local PIVOT_EPSILON = 0.001
local GRIP_ATTACHMENT_SUFFIX = "GripAttachment$"

type PropWeld = {
	bodyPartName: string,
	propName: string,
	propPartName: string,
	gripName: string?,
	offset: CFrame,
	gripOffset: CFrame?,
}

type Slot = {
	index: number,
	cframe: CFrame,
	rig: Model?,
	owner: Player?,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local respawning: { [Player]: boolean } = {}
local slots: { Slot } = {}
local cutsceneDone: { [Player]: boolean } = {}
local spawned: { [Player]: boolean } = {}
local disconnectCutscene: (() -> ())? = nil
local debugRigs: { [Model]: boolean } = {}
local landing: { [Player]: boolean } = {}

local function loadSlots()
	local folder = Workspace:FindFirstChild(SLOTS_FOLDER_NAME, true) or Workspace:WaitForChild(SLOTS_FOLDER_NAME, SLOT_WAIT)
	if not folder then
		warn("GameSpawnSystem: Workspace." .. SLOTS_FOLDER_NAME .. " not found, players will use the default spawn")
		return
	end
	local children = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			table.insert(children, child)
		end
	end
	table.sort(children, function(a, b)
		local na = tonumber(a.Name:match("%d+$")) or math.huge
		local nb = tonumber(b.Name:match("%d+$")) or math.huge
		if na ~= nb then
			return na < nb
		end
		return a.Name < b.Name
	end)
	for index, child in children do
		if child:IsA("Model") then
			local root = child:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.Anchored = true
			end
			local humanoid = child:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end
		table.insert(slots, {
			index = index,
			cframe = child:GetPivot(),
			rig = if child:IsA("Model") then child else nil,
			owner = nil,
		})
	end
end

local function findSlot(player: Player): Slot?
	for _, slot in slots do
		if slot.owner == player then
			return slot
		end
	end
	return nil
end

local function assignSlot(player: Player): Slot?
	local existing = findSlot(player)
	if existing then
		return existing
	end
	for _, slot in slots do
		if not slot.owner or slot.owner.Parent ~= Players then
			slot.owner = player
			player:SetAttribute(SLOT_ATTRIBUTE, slot.index)
			return slot
		end
	end
	return nil
end

local function propRoot(part: BasePart, rig: Model): Instance
	local node: Instance = part
	while node.Parent and node.Parent ~= rig do
		node = node.Parent
	end
	return node
end

local function crossingParts(rig: Model, weld: WeldConstraint): (BasePart?, BasePart?)
	local part0, part1 = weld.Part0, weld.Part1
	if not part0 or not part1 then
		return nil, nil
	end
	if part0.Parent == rig and part1.Parent ~= rig then
		return part0, part1
	end
	if part1.Parent == rig and part0.Parent ~= rig then
		return part1, part0
	end
	return nil, nil
end

local function gripAttachment(bodyPart: BasePart): Attachment?
	for _, child in bodyPart:GetChildren() do
		if child:IsA("Attachment") and child.Name:match(GRIP_ATTACHMENT_SUFFIX) then
			return child
		end
	end
	return nil
end

local function capturePropWelds(rig: Model): ({ PropWeld }, { BasePart })
	local captured: { PropWeld } = {}
	local held: { BasePart } = {}
	for _, descendant in rig:GetDescendants() do
		if not descendant:IsA("WeldConstraint") then
			continue
		end
		local bodyPart, propPart = crossingParts(rig, descendant)
		if not bodyPart or not propPart then
			continue
		end
		local prop = propRoot(propPart, rig)
		if not prop:IsA("PVInstance") then
			continue
		end
		local propPivot = (prop :: PVInstance):GetPivot()
		local grip = gripAttachment(bodyPart)
		table.insert(captured, {
			bodyPartName = bodyPart.Name,
			propName = prop.Name,
			propPartName = propPart.Name,
			gripName = if grip then grip.Name else nil,
			offset = bodyPart.CFrame:ToObjectSpace(propPivot),
			gripOffset = if grip then grip.WorldCFrame:ToObjectSpace(propPivot) else nil,
		})
		if prop:IsA("BasePart") and not prop.Anchored then
			prop.Anchored = true
			table.insert(held, prop)
		end
		for _, part in prop:GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored then
				part.Anchored = true
				table.insert(held, part)
			end
		end
	end
	return captured, held
end

local function restorePropWelds(rig: Model, captured: { PropWeld }, held: { BasePart })
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("WeldConstraint") then
			local bodyPart, propPart = crossingParts(rig, descendant)
			if bodyPart and propPart then
				descendant:Destroy()
			end
		end
	end
	for _, entry in captured do
		local bodyPart = rig:FindFirstChild(entry.bodyPartName)
		local prop = rig:FindFirstChild(entry.propName)
		if not (bodyPart and bodyPart:IsA("BasePart") and prop and prop:IsA("PVInstance")) then
			warn(("GameSpawnSystem: could not reattach %s to %s"):format(entry.propName, entry.bodyPartName))
			continue
		end
		local propPart = if prop:IsA("BasePart") then prop else prop:FindFirstChild(entry.propPartName, true)
		if not (propPart and propPart:IsA("BasePart")) then
			warn(("GameSpawnSystem: could not find %s inside %s"):format(entry.propPartName, entry.propName))
			continue
		end
		local grip = if entry.gripName then bodyPart:FindFirstChild(entry.gripName) else nil
		if grip and grip:IsA("Attachment") and entry.gripOffset then
			prop:PivotTo(grip.WorldCFrame * entry.gripOffset)
		else
			prop:PivotTo(bodyPart.CFrame * entry.offset)
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bodyPart
		weld.Part1 = propPart
		weld.Parent = bodyPart
	end
	for _, part in held do
		if part.Parent then
			part.Anchored = false
		end
	end
end

local function lowestFootY(rig: Model): number?
	local lowest: number? = nil
	for _, name in FOOT_PART_NAMES do
		local part = rig:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local bottom = part.Position.Y - part.Size.Y / 2
			lowest = if lowest then math.min(lowest, bottom) else bottom
		end
	end
	if lowest then
		return lowest
	end
	local ok, cframe, size = pcall(function()
		return rig:GetBoundingBox()
	end)
	if not ok or typeof(cframe) ~= "CFrame" then
		return nil
	end
	return cframe.Position.Y - (size :: Vector3).Y / 2
end

local function alignPivotToFeet(rig: Model)
	local feetY = lowestFootY(rig)
	if not feetY then
		return
	end
	local pivot = rig:GetPivot()
	local delta = feetY - pivot.Position.Y
	if math.abs(delta) < PIVOT_EPSILON then
		return
	end
	local primary = rig.PrimaryPart
	if primary then
		primary.PivotOffset += primary.CFrame:VectorToObjectSpace(Vector3.new(0, delta, 0))
	else
		rig.WorldPivot = pivot + Vector3.new(0, delta, 0)
	end
end

local function dressRigAs(rig: Model?, userId: number, label: string)
	if not rig or not rig.Parent then
		return
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if not ok or not description then
		warn(("GameSpawnSystem: could not load appearance for %s: %s"):format(label, tostring(description)))
		return
	end
	local standing = rig:GetPivot()
	local props, held = capturePropWelds(rig)
	local applied, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not applied then
		warn(("GameSpawnSystem: could not apply appearance for %s: %s"):format(label, tostring(err)))
	end
	if not rig.Parent then
		return
	end
	restorePropWelds(rig, props, held)
	alignPivotToFeet(rig)
	rig:PivotTo(standing)
	local root = rig.PrimaryPart or rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

local function dressRig(player: Player, slot: Slot)
	dressRigAs(slot.rig, player.UserId, player.Name)
end

local function debugFillEnabled(): boolean
	return Config.Cutscene.DebugFillSlots == true and RunService:IsStudio()
end

local function fillDebugRigs()
	local ids = Config.Cutscene.DebugFillUserIds
	if #ids == 0 then
		return
	end
	for _, slot in slots do
		local owner = slot.owner
		if slot.rig and (not owner or owner.Parent ~= Players) then
			local userId = ids[(slot.index - 1) % #ids + 1]
			debugRigs[slot.rig] = true
			task.spawn(dressRigAs, slot.rig, userId, "debug slot " .. slot.index)
		end
	end
end

local function clearDebugRigs()
	for rig in debugRigs do
		if rig.Parent then
			rig:Destroy()
		end
	end
	table.clear(debugRigs)
end

local function removeUnusedRigs()
	if debugFillEnabled() then
		fillDebugRigs()
		return
	end
	for _, slot in slots do
		local owner = slot.owner
		if slot.rig and (not owner or owner.Parent ~= Players) then
			slot.rig:Destroy()
			slot.rig = nil
			slot.owner = nil
		end
	end
end

local function loadCharacter(player: Player)
	if player.Parent ~= Players then
		return
	end
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn(("GameSpawnSystem failed to load character for %s: %s"):format(player.Name, tostring(err)))
	end
end

local function findLandingModel(): Instance?
	return Workspace:FindFirstChild(Config.Cutscene.Landing.ModelName, true)
end

local function findLandingSpawn(): SpawnLocation?
	local model = findLandingModel()
	if not model then
		return nil
	end
	local spawn = model:FindFirstChildWhichIsA("SpawnLocation", true)
	return spawn
end

local function anchorLandingModel()
	local model = findLandingModel()
	if not model then
		warn("GameSpawnSystem: Workspace." .. Config.Cutscene.Landing.ModelName .. " not found, landing spawn unavailable")
		return
	end
	local anchored = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			descendant.Anchored = true
			anchored += 1
		end
	end
	if anchored > 0 then
		warn(("GameSpawnSystem: anchored %d loose parts under %s; anchor the model in Studio"):format(anchored, model:GetFullName()))
	end
end

local function setEngineJoints(character: Model, enabled: boolean)
	for _, descendant in character:GetDescendants() do
		local isJoint = descendant:IsA("AnimationConstraint") and descendant.Name ~= ROOT_JOINT_NAME
		local isSocket = descendant:IsA("BallSocketConstraint") and descendant.Name:match(ENGINE_SOCKET_SUFFIX) ~= nil
		if isJoint or isSocket then
			descendant.Enabled = enabled
		end
	end
end

local function ragdollCharacter(character: Model, humanoid: Humanoid)
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	setEngineJoints(character, false)
	local ok, err = pcall(WRagdoll.TurnRagdoll, WRagdoll, humanoid)
	if not ok then
		warn(("GameSpawnSystem: could not ragdoll %s: %s"):format(character.Name, tostring(err)))
	end
	character:SetAttribute(RAGDOLL_ATTRIBUTE, true)
end

local function restoreCharacter(character: Model, humanoid: Humanoid)
	for _, descendant in character:GetDescendants() do
		local isOwnSocket = descendant:IsA("BallSocketConstraint") and descendant.Name:match(ENGINE_SOCKET_SUFFIX) == nil
		local isWeld = descendant:IsA("WeldConstraint") and descendant.Name == RAGDOLL_WELD_NAME
		if isOwnSocket or isWeld then
			descendant:Destroy()
		elseif descendant:IsA("Motor6D") then
			descendant.Enabled = true
		end
	end
	setEngineJoints(character, true)
	local rootPart = character.PrimaryPart
	if rootPart then
		rootPart.CanCollide = true
	end
	humanoid.RequiresNeck = true
	humanoid.BreakJointsOnDeath = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	character:SetAttribute(RAGDOLL_ATTRIBUTE, false)
end

local function landCharacter(character: Model, spawn: SpawnLocation)
	local settings = Config.Cutscene.Landing
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local position = spawn.Position + Vector3.new(0, settings.DropHeight, 0)
	local tilt = math.rad(settings.TiltDegrees)
	character:PivotTo(CFrame.new(position) * CFrame.Angles(tilt, math.random() * math.pi * 2, 0))
	ragdollCharacter(character, humanoid)
	task.delay(settings.RagdollSeconds, function()
		if character.Parent and humanoid.Parent == character and humanoid.Health > 0 then
			restoreCharacter(character, humanoid)
		end
	end)
end

local function placeCharacter(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local isLanding = landing[player] == true
	landing[player] = nil
	local spawn = findLandingSpawn()
	if spawn then
		if isLanding then
			landCharacter(character, spawn)
		end
		return
	end
	local slot = findSlot(player) or assignSlot(player)
	if not slot then
		return
	end
	local target = slot.cframe
	local walkEnd = Workspace:GetAttribute(WALK_END_ATTRIBUTE_PREFIX .. slot.index)
	if typeof(walkEnd) == "CFrame" then
		target = walkEnd
	end
	local flatLook = Vector3.new(target.LookVector.X, 0, target.LookVector.Z)
	local forward = if flatLook.Magnitude > 0.001 then flatLook.Unit else -Vector3.zAxis
	local position = target.Position + Vector3.new(0, SLOT_HEIGHT_OFFSET, 0)
	character:PivotTo(CFrame.lookAt(position, position + forward))
end

local function watchCharacter(player: Player, character: Model)
	placeCharacter(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Once(function()
		if Players.CharacterAutoLoads or respawning[player] then
			return
		end
		respawning[player] = true
		task.delay(Players.RespawnTime, function()
			respawning[player] = nil
			if player.Parent ~= Players or player.Character ~= character then
				return
			end
			loadCharacter(player)
		end)
	end)
end

local function cutsceneTimeout(): number
	local cutscene = Config.Cutscene
	local walkSeconds = 0
	local hole = Workspace:GetAttribute("CutsceneHoleCFrame")
	local players = Workspace:GetAttribute("CutscenePlayersCFrame")
	if typeof(hole) == "CFrame" and typeof(players) == "CFrame" then
		walkSeconds = (hole.Position - players.Position).Magnitude / math.max(cutscene.WalkSpeed, 1)
	end
	local approachSeconds = (cutscene.StopDistance + (Config.Party.MaxSize - 1) * cutscene.LineSpacing) / math.max(cutscene.WalkSpeed, 1)
	local diveSeconds = cutscene.Fall.DiveDelay + cutscene.Fall.RiseSeconds + cutscene.Fall.PlungeSeconds
	return cutscene.PanDownSeconds + walkSeconds + approachSeconds + diveSeconds + cutscene.HoldSeconds + Config.Party.MinLoadingSeconds + CUTSCENE_MARGIN
end

local function spawnAfterCutscene(player: Player)
	if spawned[player] or player.Character then
		return
	end
	local deadline = os.clock() + cutsceneTimeout()
	while player.Parent == Players and not cutsceneDone[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	if player.Parent ~= Players or spawned[player] or player.Character then
		return
	end
	spawned[player] = true
	local slot = findSlot(player)
	if slot and slot.rig then
		slot.rig:Destroy()
		slot.rig = nil
	end
	clearDebugRigs()
	landing[player] = true
	loadCharacter(player)
end

local function watchPlayer(player: Player)
	local slot = assignSlot(player)
	if slot then
		task.spawn(dressRig, player, slot)
	end
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end))
	if player.Character then
		watchCharacter(player, player.Character)
	elseif not Players.CharacterAutoLoads then
		MatchSystem.onReady(function()
			spawnAfterCutscene(player)
		end)
	end
end

local function onPlayerRemoving(player: Player)
	respawning[player] = nil
	cutsceneDone[player] = nil
	spawned[player] = nil
	landing[player] = nil
	local slot = findSlot(player)
	if slot then
		slot.owner = nil
		if slot.rig then
			slot.rig:Destroy()
			slot.rig = nil
		end
	end
end

function GameSpawnSystem.start()
	if isStarted then
		return
	end
	isStarted = true

	anchorLandingModel()
	loadSlots()
	disconnectCutscene = Blink.CutsceneFinished.On(function(player)
		cutsceneDone[player] = true
		MatchSystem.registerSkipVote(player)
		MatchSystem.releaseCutsceneMap(player)
	end)
	MatchSystem.onReady(removeUnusedRigs)
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

function GameSpawnSystem.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if disconnectCutscene then
		disconnectCutscene()
		disconnectCutscene = nil
	end
	table.clear(respawning)
	table.clear(cutsceneDone)
	table.clear(spawned)
	table.clear(landing)
	table.clear(slots)
	table.clear(debugRigs)
end

return GameSpawnSystem
