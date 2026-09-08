local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))

local PartySystem = {}

local PORTAL_FOLDER_NAME = "Portal"
local BORDER_NAME = "BORDER"
local TELEPORT_NAME = "TELEPORT"
local BILLBOARD_NAME = "billboardGui"
local SPAWN_NAME = "Spawn"
local TOUCH_DEBOUNCE = 1.5
local LEAVE_TOUCH_GRACE = 2.5
local JOIN_MAX_DISTANCE = 30
local SWEEP_INTERVAL = 2
local TELEPORT_HEIGHT = 3
local MEMBER_RING_RADIUS = 1.4
local EXIT_DISTANCE = 4.5
local EXIT_SPACING = 2.5
local EXIT_RAY_HEIGHT = 10
local EXIT_RAY_DEPTH = 30
local IN_QUEUE_ATTRIBUTE = "InQueue"
local TELEPORT_PREP_TIMEOUT = 4
local TELEPORT_PREP_POLL = 0.1

local DIFFICULTIES: { [string]: boolean } = { Easy = true, Normal = true, Hard = true }

type Difficulty = "Easy" | "Normal" | "Hard"

type Portal = {
	id: number,
	model: Model,
	teleportPart: BasePart,
	billboard: BillboardGui?,
	titleLabel: TextLabel?,
	countLabel: TextLabel?,
	host: Player?,
	members: { Player },
	maxSize: number,
	difficulty: Difficulty,
	friendsOnly: boolean,
	countdown: number,
	starting: boolean,
	launching: boolean,
	connections: { RBXScriptConnection },
}

local isStarted = false
local portals: { [number]: Portal } = {}
local playerPortal: { [Player]: number } = {}
local touchDebounce: { [Player]: number } = {}
local lastPortal: { [Player]: number } = {}
local teleportReady: { [Player]: boolean } = {}
local connections: { RBXScriptConnection } = {}

local function memberNames(portal: Portal): { string }
	local names = {}
	for _, member in portal.members do
		table.insert(names, member.DisplayName)
	end
	return names
end

local function updateBillboard(portal: Portal)
	local host = portal.host
	if portal.billboard then
		portal.billboard.Enabled = true
	end
	if portal.titleLabel then
		if host then
			local title = host.DisplayName .. "'s Party  -  " .. portal.difficulty
			if portal.friendsOnly then
				title ..= "  [Friends Only]"
			end
			portal.titleLabel.Text = title
		else
			portal.titleLabel.Text = "Create Party"
		end
	end
	if portal.countLabel then
		if portal.launching then
			portal.countLabel.Text = ("%d/%d  -  Teleporting"):format(#portal.members, portal.maxSize)
		elseif portal.starting and portal.countdown > 0 then
			portal.countLabel.Text = ("%d/%d  -  Starting in %d"):format(#portal.members, portal.maxSize, portal.countdown)
		else
			portal.countLabel.Text = ("%d/%d"):format(#portal.members, portal.maxSize)
		end
	end
end

local function sendState(portal: Portal, player: Player)
	Blink.PartyState.Fire(player, {
		active = true,
		isHost = portal.host == player,
		portalId = portal.id,
		maxSize = portal.maxSize,
		difficulty = portal.difficulty,
		friendsOnly = portal.friendsOnly,
		countdown = if portal.starting then portal.countdown else 0,
		members = memberNames(portal),
	})
end

local function sendInactive(player: Player)
	Blink.PartyState.Fire(player, {
		active = false,
		isHost = false,
		portalId = 0,
		maxSize = 0,
		difficulty = "Normal",
		friendsOnly = false,
		countdown = 0,
		members = {},
	})
end

local function broadcast(portal: Portal)
	updateBillboard(portal)
	for _, member in portal.members do
		sendState(portal, member)
	end
end

local function resetPortal(portal: Portal)
	portal.host = nil
	portal.members = {}
	portal.maxSize = Config.Party.DefaultSize
	portal.difficulty = Config.Party.DefaultDifficulty
	portal.friendsOnly = false
	portal.countdown = 0
	portal.starting = false
	updateBillboard(portal)
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function detachMember(player: Player, portalId: number)
	playerPortal[player] = nil
	lastPortal[player] = portalId
	player:SetAttribute(IN_QUEUE_ATTRIBUTE, false)
	touchDebounce[player] = os.clock() + LEAVE_TOUCH_GRACE
end

local function placeCharacter(player: Player, cframe: CFrame)
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.AssemblyLinearVelocity = Vector3.zero
	end
	character:PivotTo(cframe)
end

local function teleportIn(portal: Portal, player: Player, index: number)
	local angle = (index - 1) / math.max(portal.maxSize, 1) * math.pi * 2
	local ringOffset = Vector3.new(math.cos(angle) * MEMBER_RING_RADIUS, 0, math.sin(angle) * MEMBER_RING_RADIUS)
	local base = portal.teleportPart.CFrame
	placeCharacter(player, CFrame.new(base.Position + Vector3.new(0, TELEPORT_HEIGHT, 0) + ringOffset) * base.Rotation)
end

local function findExitBorder(portal: Portal): BasePart?
	local center = portal.teleportPart.Position
	local spawnLocation = Workspace:FindFirstChild(SPAWN_NAME)
	local toward = if spawnLocation and spawnLocation:IsA("BasePart") then spawnLocation.Position - center else -center
	toward = Vector3.new(toward.X, 0, toward.Z)
	local best: BasePart? = nil
	local bestDot = -math.huge
	for _, child in portal.model:GetChildren() do
		if child.Name == BORDER_NAME and child:IsA("BasePart") then
			local outward = Vector3.new(child.Position.X - center.X, 0, child.Position.Z - center.Z)
			if outward.Magnitude > 0 then
				local dot = if toward.Magnitude > 0 then outward.Unit:Dot(toward.Unit) else 0
				if dot > bestDot then
					bestDot = dot
					best = child
				end
			end
		end
	end
	return best
end

local function findExitCFrame(portal: Portal, slot: number): CFrame?
	local border = findExitBorder(portal)
	if not border then
		return nil
	end
	local center = portal.teleportPart.Position
	local outward = Vector3.new(border.Position.X - center.X, 0, border.Position.Z - center.Z).Unit
	local sideways = Vector3.new(-outward.Z, 0, outward.X)
	local thickness = math.min(border.Size.X, border.Size.Z)
	local lateralSign = if (slot - 1) % 2 == 0 then 1 else -1
	local lateral = lateralSign * math.ceil((slot - 1) / 2) * EXIT_SPACING
	local spot = Vector3.new(border.Position.X, center.Y, border.Position.Z) + outward * (thickness / 2 + EXIT_DISTANCE) + sideways * lateral
	local characters = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(characters, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characters
	local result = Workspace:Raycast(spot + Vector3.new(0, EXIT_RAY_HEIGHT, 0), Vector3.new(0, -EXIT_RAY_DEPTH, 0), params)
	local floorY = if result then result.Position.Y else center.Y + portal.teleportPart.Size.Y / 2
	return CFrame.lookAt(Vector3.new(spot.X, floorY, spot.Z), Vector3.new(center.X, floorY, center.Z))
end

local function teleportOut(player: Player, portal: Portal?, slot: number?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local hipHeight = if humanoid then humanoid.HipHeight else 2
	local rootHalf = if rootPart and rootPart:IsA("BasePart") then rootPart.Size.Y / 2 else 1
	local exit = if portal then findExitCFrame(portal, slot or 1) else nil
	if exit then
		placeCharacter(player, exit + Vector3.new(0, hipHeight + rootHalf + 0.1, 0))
		return
	end
	local spawnLocation = Workspace:FindFirstChild(SPAWN_NAME)
	if spawnLocation and spawnLocation:IsA("BasePart") then
		placeCharacter(player, CFrame.new(spawnLocation.Position + Vector3.new(0, spawnLocation.Size.Y / 2 + hipHeight + rootHalf + 0.1, 0)))
	end
end

local function isFriendOfHost(portal: Portal, player: Player): boolean
	local host = portal.host
	if not host then
		return true
	end
	local ok, result = pcall(function()
		return player:IsFriendsWith(host.UserId)
	end)
	return ok and result == true
end

local function cancelCountdown(portal: Portal)
	if portal.starting then
		portal.starting = false
		portal.countdown = 0
	end
end

local launchParty

local function leaveParty(player: Player, notify: boolean)
	local portalId = playerPortal[player]
	if not portalId then
		return
	end
	local portal = portals[portalId]
	detachMember(player, portalId)
	if not portal then
		return
	end

	local index = table.find(portal.members, player)
	if index then
		table.remove(portal.members, index)
	end
	if portal.host == player then
		cancelCountdown(portal)
	end

	if portal.host == player then
		portal.host = portal.members[1]
	end
	if #portal.members == 0 then
		resetPortal(portal)
	else
		broadcast(portal)
	end

	if player.Parent == Players then
		if isAlive(player) then
			teleportOut(player, portal, index or 1)
		end
		if notify then
			sendInactive(player)
		end
	end
end

local function joinParty(portal: Portal, player: Player)
	if playerPortal[player] then
		return
	end
	if portal.launching then
		Blink.PartyMessage.Fire(player, "That party is teleporting")
		return
	end

	if portal.host == nil then
		resetPortal(portal)
		portal.host = player
	else
		if #portal.members >= portal.maxSize then
			Blink.PartyMessage.Fire(player, "That party is full")
			return
		end
		if portal.friendsOnly and not isFriendOfHost(portal, player) then
			Blink.PartyMessage.Fire(player, "That party is friends only")
			return
		end
	end

	table.insert(portal.members, player)
	playerPortal[player] = portal.id
	player:SetAttribute(IN_QUEUE_ATTRIBUTE, true)
	teleportIn(portal, player, #portal.members)
	broadcast(portal)
	if portal.starting and #portal.members >= portal.maxSize then
		launchParty(portal)
	end
end

local function onBorderTouched(portal: Portal, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or not isAlive(player) then
		return
	end
	local now = os.clock()
	if (touchDebounce[player] or 0) + TOUCH_DEBOUNCE > now then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end
	if (rootPart.Position - portal.teleportPart.Position).Magnitude > JOIN_MAX_DISTANCE then
		return
	end
	touchDebounce[player] = now
	if playerPortal[player] == portal.id then
		return
	end
	if playerPortal[player] then
		Blink.PartyMessage.Fire(player, "Leave your current party first")
		return
	end
	joinParty(portal, player)
end

local function memberIds(members: { Player }): { number }
	local ids = {}
	for _, member in members do
		table.insert(ids, member.UserId)
	end
	return ids
end

local function waitForTeleportReady(portal: Portal, members: { Player })
	local deadline = os.clock() + TELEPORT_PREP_TIMEOUT
	while os.clock() < deadline do
		local pending = false
		for _, member in members do
			if member.Parent == Players and playerPortal[member] == portal.id and not teleportReady[member] then
				pending = true
				break
			end
		end
		if not pending then
			return
		end
		task.wait(TELEPORT_PREP_POLL)
	end
end

function launchParty(portal: Portal)
	if portal.launching then
		return
	end
	portal.launching = true
	portal.starting = false
	portal.countdown = 0
	updateBillboard(portal)

	local placeId = Config.Party.GamePlaceId
	local members = table.clone(portal.members)
	local hasPlace = placeId ~= nil and placeId > 0
	local travelers: { Player } = {}
	local teleported = false
	if hasPlace then
		for _, member in members do
			teleportReady[member] = nil
			Blink.PartyTeleporting.Fire(member)
		end
		waitForTeleportReady(portal, members)
		for _, member in members do
			if member.Parent == Players and playerPortal[member] == portal.id then
				table.insert(travelers, member)
			end
		end
		if #travelers > 0 then
			local options = Instance.new("TeleportOptions")
			options.ShouldReserveServer = true
			options:SetTeleportData({
				difficulty = portal.difficulty,
				friendsOnly = portal.friendsOnly,
				partySize = #travelers,
				memberIds = memberIds(travelers),
			})
			local ok, err = pcall(function()
				TeleportService:TeleportAsync(placeId, travelers, options)
			end)
			teleported = ok
			if not ok then
				warn(("PartySystem teleport failed: %s"):format(tostring(err)))
			end
		end
	end

	portal.launching = false
	for _, member in members do
		teleportReady[member] = nil
		if playerPortal[member] == portal.id then
			detachMember(member, portal.id)
		end
	end
	resetPortal(portal)

	local failMessage = if hasPlace then "Teleport failed, sending you back to the lobby" else "No game place is set up yet, sending you back to the lobby"
	for slot, member in members do
		if member.Parent ~= Players then
			continue
		end
		local traveling = not hasPlace or table.find(travelers, member) ~= nil
		if not (teleported and traveling) then
			Blink.PartyTeleportCancelled.Fire(member)
		end
		if not teleported and traveling then
			Blink.PartyMessage.Fire(member, failMessage)
			if isAlive(member) then
				teleportOut(member, portal, slot)
			end
		end
		sendInactive(member)
	end
end

local function onTeleportFailed(player: Player, _result: Enum.TeleportResult, errorMessage: string)
	if player.Parent ~= Players or playerPortal[player] then
		return
	end
	warn(("PartySystem teleport failed for %s: %s"):format(player.Name, tostring(errorMessage)))
	Blink.PartyTeleportCancelled.Fire(player)
	Blink.PartyMessage.Fire(player, "Teleport failed, sending you back to the lobby")
	local portalId = lastPortal[player]
	local portal = if portalId then portals[portalId] else nil
	if isAlive(player) then
		teleportOut(player, portal, 1)
	end
end

local function startCountdown(portal: Portal)
	portal.starting = true
	task.spawn(function()
		for remaining = Config.Party.CountdownSeconds, 1, -1 do
			if not portal.starting then
				return
			end
			portal.countdown = remaining
			broadcast(portal)
			task.wait(1)
		end
		if not portal.starting then
			return
		end
		launchParty(portal)
	end)
end

local function onSetSettings(player: Player, data)
	local portalId = playerPortal[player]
	local portal = portalId and portals[portalId]
	if not portal or portal.host ~= player or portal.starting or portal.launching then
		return
	end

	local maxSize = math.floor(tonumber(data.maxSize) or portal.maxSize)
	maxSize = math.clamp(maxSize, Config.Party.MinSize, Config.Party.MaxSize)
	maxSize = math.max(maxSize, #portal.members)
	portal.maxSize = maxSize

	if DIFFICULTIES[data.difficulty] then
		portal.difficulty = data.difficulty
	end
	portal.friendsOnly = data.friendsOnly == true
	broadcast(portal)
end

local function onStart(player: Player)
	local portalId = playerPortal[player]
	local portal = portalId and portals[portalId]
	if not portal or portal.host ~= player or portal.starting or portal.launching then
		return
	end
	startCountdown(portal)
end

local function findLabels(teleportPart: BasePart): (BillboardGui?, TextLabel?, TextLabel?)
	local container = teleportPart:FindFirstChild(BILLBOARD_NAME) or teleportPart:FindFirstChildWhichIsA("BillboardGui")
	if not container then
		return nil, nil, nil
	end
	local billboard = if container:IsA("BillboardGui") then container else nil
	local labels = {}
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("TextLabel") then
			table.insert(labels, descendant)
		end
	end
	table.sort(labels, function(a, b)
		return a.Position.Y.Scale < b.Position.Y.Scale
	end)
	return billboard, labels[1], labels[2]
end

local function registerPortal(model: Model)
	local id = tonumber(string.match(model.Name, "%d+")) or (#portals + 1)
	local teleportPart = model:FindFirstChild(TELEPORT_NAME, true)
	if not teleportPart or not teleportPart:IsA("BasePart") then
		warn(("PartySystem: %s has no %s part"):format(model:GetFullName(), TELEPORT_NAME))
		return
	end
	local billboard, titleLabel, countLabel = findLabels(teleportPart)
	local portal: Portal = {
		id = id,
		model = model,
		teleportPart = teleportPart,
		billboard = billboard,
		titleLabel = titleLabel,
		countLabel = countLabel,
		host = nil,
		members = {},
		maxSize = Config.Party.DefaultSize,
		difficulty = Config.Party.DefaultDifficulty,
		friendsOnly = false,
		countdown = 0,
		starting = false,
		launching = false,
		connections = {},
	}
	portals[id] = portal

	for _, child in model:GetChildren() do
		if child.Name == BORDER_NAME and child:IsA("BasePart") then
			table.insert(portal.connections, child.Touched:Connect(function(hit)
				onBorderTouched(portal, hit)
			end))
		end
	end
	updateBillboard(portal)
end

local function sweepPortals()
	for _, portal in portals do
		local changed = false
		for index = #portal.members, 1, -1 do
			local member = portal.members[index]
			if member.Parent ~= Players or not isAlive(member) then
				table.remove(portal.members, index)
				playerPortal[member] = nil
				changed = true
			end
		end
		if changed then
			cancelCountdown(portal)
			if portal.host and not table.find(portal.members, portal.host) then
				portal.host = portal.members[1]
			end
			if #portal.members == 0 then
				resetPortal(portal)
			else
				broadcast(portal)
			end
		else
			updateBillboard(portal)
		end
	end
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Once(function()
			leaveParty(player, true)
		end)
	end
end

local function watchPlayer(player: Player)
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		leaveParty(player, true)
	end))
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

function PartySystem.start()
	if isStarted then
		return
	end
	isStarted = true

	local folder = Workspace:WaitForChild(PORTAL_FOLDER_NAME, 30)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				registerPortal(child)
			end
		end
	else
		warn("PartySystem: Workspace." .. PORTAL_FOLDER_NAME .. " folder not found")
	end

	Blink.PartySetSettings.On(onSetSettings)
	Blink.PartyLeave.On(function(player)
		leaveParty(player, true)
	end)
	Blink.PartyStart.On(onStart)
	Blink.PartyTeleportReady.On(function(player)
		teleportReady[player] = true
	end)

	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		leaveParty(player, false)
		touchDebounce[player] = nil
		lastPortal[player] = nil
		teleportReady[player] = nil
	end))
	table.insert(connections, TeleportService.TeleportInitFailed:Connect(onTeleportFailed))
	task.spawn(function()
		while isStarted do
			task.wait(SWEEP_INTERVAL)
			sweepPortals()
		end
	end)
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

function PartySystem.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, portal in portals do
		for _, connection in portal.connections do
			connection:Disconnect()
		end
	end
	table.clear(portals)
	table.clear(playerPortal)
	table.clear(lastPortal)
	table.clear(teleportReady)
end

return PartySystem
