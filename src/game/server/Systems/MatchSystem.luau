local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

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

local isStarted = false
local connections: { RBXScriptConnection } = {}
local settings: MatchSettings? = nil
local roster: { RosterEntry } = {}
local rosterLoaded = false
local arrivalDeadline: number? = nil
local gateOpen = false
local readyCallbacks: { () -> () } = {}
local lastBroadcast: ArrivalState? = nil

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

local function onPlayerAdded(player: Player)
	if not settings then
		settings = readTeleportData(player)
	end
	applyToPlayer(player)

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

function MatchSystem.start()
	if isStarted then
		return
	end
	isStarted = true

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
	settings = nil
	rosterLoaded = false
	arrivalDeadline = nil
	gateOpen = false
	lastBroadcast = nil
end

return MatchSystem
