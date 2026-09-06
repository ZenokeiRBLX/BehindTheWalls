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
local TELEPORT_HEIGHT = 3
local MEMBER_RING_RADIUS = 1.4
local IN_QUEUE_ATTRIBUTE = "InQueue"

local DIFFICULTIES: { [string]: boolean } = { Easy = true, Normal = true, Hard = true }

type Difficulty = "Easy" | "Normal" | "Hard"

type Portal = {
	id: number,
	model: Model,
	teleportPart: BasePart,
	titleLabel: TextLabel?,
	countLabel: TextLabel?,
	host: Player?,
	members: { Player },
	maxSize: number,
	difficulty: Difficulty,
	friendsOnly: boolean,
	countdown: number,
	starting: boolean,
	connections: { RBXScriptConnection },
}

local isStarted = false
local portals: { [number]: Portal } = {}
local playerPortal: { [Player]: number } = {}
local touchDebounce: { [Player]: number } = {}
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
		if portal.starting and portal.countdown > 0 then
			portal.countLabel.Text = ("Starting in %d"):format(portal.countdown)
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

local function teleportOut(player: Player)
	local spawnLocation = Workspace:FindFirstChild(SPAWN_NAME)
	if spawnLocation and spawnLocation:IsA("BasePart") then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hipHeight = if humanoid then humanoid.HipHeight else 2
		placeCharacter(player, CFrame.new(spawnLocation.Position + Vector3.new(0, spawnLocation.Size.Y / 2 + hipHeight + 1.2, 0)))
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

local function leaveParty(player: Player, notify: boolean)
	local portalId = playerPortal[player]
	if not portalId then
		return
	end
	local portal = portals[portalId]
	playerPortal[player] = nil
	player:SetAttribute(IN_QUEUE_ATTRIBUTE, false)
	if not portal then
		return
	end

	local index = table.find(portal.members, player)
	if index then
		table.remove(portal.members, index)
	end
	cancelCountdown(portal)

	if portal.host == player then
		portal.host = portal.members[1]
	end
	if #portal.members == 0 then
		resetPortal(portal)
	else
		broadcast(portal)
	end

	if player.Parent == Players then
		teleportOut(player)
		if notify then
			sendInactive(player)
		end
	end
end

local function joinParty(portal: Portal, player: Player)
	if playerPortal[player] then
		return
	end

	if portal.host == nil then
		resetPortal(portal)
		portal.host = player
	else
		if portal.starting then
			Blink.PartyMessage.Fire(player, "That party is already starting")
			return
		end
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
end

local function onBorderTouched(portal: Portal, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local now = os.clock()
	if (touchDebounce[player] or 0) + TOUCH_DEBOUNCE > now then
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

local function launchParty(portal: Portal)
	local placeId = Config.Party.GamePlaceId
	local members = table.clone(portal.members)
	if placeId and placeId > 0 then
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({
			difficulty = portal.difficulty,
			friendsOnly = portal.friendsOnly,
			partySize = #members,
		})
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, members, options)
		end)
		if not ok then
			warn(("PartySystem teleport failed: %s"):format(tostring(err)))
			for _, member in members do
				Blink.PartyMessage.Fire(member, "Teleport failed, please try again")
			end
		end
	else
		for _, member in members do
			Blink.PartyMessage.Fire(member, "No game place is set up yet (Config.Party.GamePlaceId)")
		end
	end
	portal.starting = false
	portal.countdown = 0
	broadcast(portal)
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
	if not portal or portal.host ~= player or portal.starting then
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
	if not portal or portal.host ~= player or portal.starting then
		return
	end
	startCountdown(portal)
end

local function findLabels(teleportPart: BasePart): (TextLabel?, TextLabel?)
	local billboard = teleportPart:FindFirstChild(BILLBOARD_NAME) or teleportPart:FindFirstChildWhichIsA("BillboardGui")
	if not billboard then
		return nil, nil
	end
	local labels = {}
	for _, descendant in billboard:GetDescendants() do
		if descendant:IsA("TextLabel") then
			table.insert(labels, descendant)
		end
	end
	table.sort(labels, function(a, b)
		return a.Position.Y.Scale < b.Position.Y.Scale
	end)
	return labels[1], labels[2]
end

local function registerPortal(model: Model)
	local id = tonumber(string.match(model.Name, "%d+")) or (#portals + 1)
	local teleportPart = model:FindFirstChild(TELEPORT_NAME, true)
	if not teleportPart or not teleportPart:IsA("BasePart") then
		warn(("PartySystem: %s has no %s part"):format(model:GetFullName(), TELEPORT_NAME))
		return
	end
	local titleLabel, countLabel = findLabels(teleportPart)
	local portal: Portal = {
		id = id,
		model = model,
		teleportPart = teleportPart,
		titleLabel = titleLabel,
		countLabel = countLabel,
		host = nil,
		members = {},
		maxSize = Config.Party.DefaultSize,
		difficulty = Config.Party.DefaultDifficulty,
		friendsOnly = false,
		countdown = 0,
		starting = false,
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

	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		leaveParty(player, false)
		touchDebounce[player] = nil
	end))
	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			leaveParty(player, true)
		end)
	end))
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			leaveParty(player, true)
		end)
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
end

return PartySystem
