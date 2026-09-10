local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))

local MatchSystem = {}

export type MatchSettings = {
	difficulty: string,
	friendsOnly: boolean,
	partySize: number,
}

export type ArrivalState = {
	arrived: number,
	expected: number,
	complete: boolean,
}

type RosterEntry = {
	userId: number,
	arrived: boolean,
}

local DIFFICULTIES: { [string]: boolean } = { Easy = true, Normal = true, Hard = true }
local DIFFICULTY_ATTRIBUTE = "Difficulty"
local PARTY_SIZE_ATTRIBUTE = "PartySize"
local ARRIVAL_POLL = 1
local CAMERA_PART_NAME = "Cutscene_Camera"
local CAMERA_CFRAME_ATTRIBUTE = "CutsceneCameraCFrame"
local CAMERA_FOV_ATTRIBUTE = "CutsceneCameraFov"
local PLAYERS_FOLDER_NAME = "Teleport_Players"
local PLAYERS_CFRAME_ATTRIBUTE = "CutscenePlayersCFrame"
local CAMERA_PART_WAIT = 10
local CUTSCENE_MAP_FOLDER_NAME = "Cutscene_Map"
local HOLE_PART_NAME = "Cutscene_Hole"
local HOLE_ATTRIBUTE = "CutsceneHoleCFrame"
local SLOT_ATTRIBUTE_PREFIX = "CutsceneSlot"
local WALK_END_ATTRIBUTE_PREFIX = "CutsceneWalkEnd"

local isStarted = false
local connections: { RBXScriptConnection } = {}
local settings: MatchSettings? = nil
local roster: { RosterEntry } = {}
local rosterLoaded = false
local arrivalDeadline: number? = nil
local gateOpen = false
local readyCallbacks: { () -> () } = {}
local lastBroadcast: ArrivalState? = nil
local cutsceneModels: { Model } = {}
local pinnedPlayers: { [Player]: boolean } = {}

local function getJoinData(player: Player): (any, any)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return nil, nil
	end
	local data = joinData.TeleportData
	return if type(data) == "table" then data else nil, joinData
end

local function readTeleportData(player: Player): MatchSettings?
	local data = getJoinData(player)
	if not data then
		return nil
	end
	local difficulty = if DIFFICULTIES[data.difficulty] then data.difficulty else Config.Party.DefaultDifficulty
	local partySize = math.clamp(math.floor(tonumber(data.partySize) or 1), Config.Party.MinSize, Config.Party.MaxSize)
	return {
		difficulty = difficulty,
		friendsOnly = data.friendsOnly == true,
		partySize = partySize,
	}
end

local function findEntry(list: { RosterEntry }, userId: number): RosterEntry?
	for _, entry in list do
		if entry.userId == userId then
			return entry
		end
	end
	return nil
end

local function readRoster(player: Player): { RosterEntry }
	local data, joinData = getJoinData(player)
	local ids = if data then data.memberIds else nil
	if type(ids) ~= "table" and joinData then
		ids = joinData.Members
	end
	local entries: { RosterEntry } = {}
	if type(ids) == "table" then
		for _, id in ids do
			local userId = tonumber(id)
			if userId and not findEntry(entries, userId) then
				table.insert(entries, { userId = userId, arrived = false })
			end
		end
	end
	return entries
end

local function applyToPlayer(player: Player)
	local current = MatchSystem.getSettings()
	player:SetAttribute(DIFFICULTY_ATTRIBUTE, current.difficulty)
	player:SetAttribute(PARTY_SIZE_ATTRIBUTE, current.partySize)
end

local function countArrivals(): (number, number)
	local arrived = 0
	for _, entry in roster do
		if entry.arrived then
			arrived += 1
		end
	end
	return arrived, #roster
end

function MatchSystem.getArrivalState(): ArrivalState
	local arrived, expected = countArrivals()
	return {
		arrived = arrived,
		expected = expected,
		complete = gateOpen,
	}
end

local function sendArrival(player: Player)
	Blink.ArrivalState.Fire(player, MatchSystem.getArrivalState())
end

local function broadcastArrival()
	local state = MatchSystem.getArrivalState()
	local last = lastBroadcast
	if last and last.arrived == state.arrived and last.expected == state.expected and last.complete == state.complete then
		return
	end
	lastBroadcast = state
	Blink.ArrivalState.FireAll(state)
end

local function openGate()
	if gateOpen then
		return
	end
	gateOpen = true
	arrivalDeadline = nil
	broadcastArrival()
	local callbacks = readyCallbacks
	readyCallbacks = {}
	for _, callback in callbacks do
		task.spawn(callback)
	end
end

local function evaluateArrivals()
	if gateOpen then
		return
	end
	local arrived, expected = countArrivals()
	if expected > 0 and arrived >= expected then
		openGate()
		return
	end
	if arrivalDeadline and os.clock() >= arrivalDeadline then
		for index = #roster, 1, -1 do
			local entry = roster[index]
			if not entry.arrived then
				warn(("MatchSystem: user %d never arrived, starting without them"):format(entry.userId))
				table.remove(roster, index)
			end
		end
		openGate()
		return
	end
	broadcastArrival()
end

local function collectCutsceneModels()
	local roots: { Instance } = {}
	local custom = Workspace:FindFirstChild(CUTSCENE_MAP_FOLDER_NAME, true)
	if custom then
		table.insert(roots, custom)
	else
		for _, name in Config.Cutscene.PinnedNames do
			local found = Workspace:FindFirstChild(name, true) or Workspace:WaitForChild(name, CAMERA_PART_WAIT)
			if found then
				table.insert(roots, found)
			end
		end
	end
	local looseParts = 0
	local function pin(model: Model)
		model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
		table.insert(cutsceneModels, model)
	end
	local function scan(instance: Instance)
		for _, child in instance:GetChildren() do
			if child:IsA("Model") then
				pin(child)
			elseif child:IsA("BasePart") then
				looseParts += 1
			elseif child:IsA("Folder") then
				scan(child)
			end
		end
	end
	for _, root in roots do
		if root:IsA("Model") then
			pin(root)
		else
			scan(root)
		end
	end
	if looseParts > 0 then
		warn(("MatchSystem: %d loose parts in the cutscene map are not inside a Model and cannot be pinned"):format(looseParts))
	end
end

local function pinCutsceneMap(player: Player)
	if pinnedPlayers[player] or #cutsceneModels == 0 then
		return
	end
	pinnedPlayers[player] = true
	for _, model in cutsceneModels do
		if model.Parent then
			model:AddPersistentPlayer(player)
		end
	end
end

function MatchSystem.releaseCutsceneMap(player: Player)
	if not pinnedPlayers[player] then
		return
	end
	pinnedPlayers[player] = nil
	for _, model in cutsceneModels do
		if model.Parent then
			model:RemovePersistentPlayer(player)
		end
	end
end

local function onPlayerAdded(player: Player)
	if not settings then
		settings = readTeleportData(player)
	end
	applyToPlayer(player)
	pinCutsceneMap(player)

	if not rosterLoaded then
		rosterLoaded = true
		roster = readRoster(player)
		arrivalDeadline = os.clock() + Config.Party.ArrivalTimeoutSeconds
	end
	local entry = findEntry(roster, player.UserId)
	if not entry then
		entry = { userId = player.UserId, arrived = false }
		table.insert(roster, entry)
	end
	entry.arrived = true
	evaluateArrivals()
	sendArrival(player)
end

local function onPlayerRemoving(player: Player)
	pinnedPlayers[player] = nil
	if gateOpen then
		return
	end
	for index, entry in roster do
		if entry.userId == player.UserId then
			table.remove(roster, index)
			break
		end
	end
	evaluateArrivals()
end

function MatchSystem.getSettings(): MatchSettings
	return settings or {
		difficulty = Config.Party.DefaultDifficulty,
		friendsOnly = false,
		partySize = 1,
	}
end

function MatchSystem.isReady(): boolean
	return gateOpen
end

function MatchSystem.onReady(callback: () -> ())
	if gateOpen then
		task.spawn(callback)
		return
	end
	table.insert(readyCallbacks, callback)
end

function MatchSystem.returnToLobby(players: { Player })
	if #players == 0 then
		return
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.Places.Lobby, players)
	end)
	if not ok then
		warn(("MatchSystem failed to return players to the lobby: %s"):format(tostring(err)))
	end
end

local function findInWorkspace(name: string): Instance?
	return Workspace:FindFirstChild(name, true) or Workspace:WaitForChild(name, CAMERA_PART_WAIT)
end

local function findHole(): CFrame?
	local part = Workspace:FindFirstChild(HOLE_PART_NAME, true) or Workspace:FindFirstChild(Config.Cutscene.HoleName, true)
	if not part then
		part = Workspace:WaitForChild(Config.Cutscene.HoleName, CAMERA_PART_WAIT)
	end
	if part and part:IsA("BasePart") then
		return part.CFrame
	end
	if part and part:IsA("Model") then
		return part:GetPivot()
	end
	warn("MatchSystem: cutscene hole part not found")
	return nil
end

local function slotIndex(instance: Instance): number?
	return tonumber(instance.Name:match("%d+$"))
end

local function publishPlayersCFrame()
	local folder = findInWorkspace(PLAYERS_FOLDER_NAME)
	if not folder then
		return
	end
	local slots: { [number]: CFrame } = {}
	local sum = Vector3.zero
	local look = Vector3.zero
	local count = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			local pivot = child:GetPivot()
			sum += pivot.Position
			look += pivot.LookVector
			count += 1
			local index = slotIndex(child)
			if index then
				slots[index] = pivot
				Workspace:SetAttribute(SLOT_ATTRIBUTE_PREFIX .. index, pivot)
			end
		end
	end
	if count == 0 then
		return
	end
	local center = sum / count
	local forward = if look.Magnitude > 0.001 then look.Unit else -Vector3.zAxis
	Workspace:SetAttribute(PLAYERS_CFRAME_ATTRIBUTE, CFrame.lookAt(center, center + forward))

	local hole = findHole()
	if not hole then
		return
	end
	Workspace:SetAttribute(HOLE_ATTRIBUTE, hole)
	local toHole = Vector3.new(hole.Position.X - center.X, 0, hole.Position.Z - center.Z)
	local walkForward = if toHole.Magnitude > 0.001 then toHole.Unit else forward
	local lineHead = Vector3.new(hole.Position.X, center.Y, hole.Position.Z) - walkForward * Config.Cutscene.StopDistance
	local order: { number } = {}
	for index in slots do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		local da = slots[a].Position:Dot(walkForward)
		local db = slots[b].Position:Dot(walkForward)
		if da ~= db then
			return da > db
		end
		return a < b
	end)
	for rank, index in order do
		local position = lineHead - walkForward * ((rank - 1) * Config.Cutscene.LineSpacing)
		Workspace:SetAttribute(WALK_END_ATTRIBUTE_PREFIX .. index, CFrame.lookAt(position, position + walkForward))
	end
end

local function publishCutsceneCamera()
	local part = findInWorkspace(CAMERA_PART_NAME)
	if not part or not part:IsA("BasePart") then
		warn("MatchSystem: Workspace." .. CAMERA_PART_NAME .. " not found")
		return
	end
	local fov = part:GetAttribute("FieldOfView")
	if type(fov) == "number" then
		Workspace:SetAttribute(CAMERA_FOV_ATTRIBUTE, fov)
	end
	Workspace:SetAttribute(CAMERA_CFRAME_ATTRIBUTE, part.CFrame)
end

local function publishCutscene()
	task.spawn(publishPlayersCFrame)
	publishCutsceneCamera()
end

function MatchSystem.start()
	if isStarted then
		return
	end
	isStarted = true

	collectCutsceneModels()
	task.spawn(publishCutscene)

	Blink.ArrivalRequest.On(sendArrival)
	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	task.spawn(function()
		while isStarted and not gateOpen do
			task.wait(ARRIVAL_POLL)
			evaluateArrivals()
		end
	end)
end

function MatchSystem.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(roster)
	table.clear(readyCallbacks)
	for player in pinnedPlayers do
		MatchSystem.releaseCutsceneMap(player)
	end
	table.clear(cutsceneModels)
	settings = nil
	rosterLoaded = false
	arrivalDeadline = nil
	gateOpen = false
	lastBroadcast = nil
end

return MatchSystem
