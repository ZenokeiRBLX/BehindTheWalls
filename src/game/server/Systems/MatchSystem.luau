local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))

local MatchSystem = {}

export type MatchSettings = {
	difficulty: string,
	friendsOnly: boolean,
	partySize: number,
}

local DIFFICULTIES: { [string]: boolean } = { Easy = true, Normal = true, Hard = true }
local DIFFICULTY_ATTRIBUTE = "Difficulty"
local PARTY_SIZE_ATTRIBUTE = "PartySize"

local isStarted = false
local connections: { RBXScriptConnection } = {}
local settings: MatchSettings? = nil

local function readTeleportData(player: Player): MatchSettings?
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return nil
	end
	local data = joinData.TeleportData
	if type(data) ~= "table" then
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

local function applyToPlayer(player: Player)
	local current = MatchSystem.getSettings()
	player:SetAttribute(DIFFICULTY_ATTRIBUTE, current.difficulty)
	player:SetAttribute(PARTY_SIZE_ATTRIBUTE, current.partySize)
end

local function onPlayerAdded(player: Player)
	if not settings then
		settings = readTeleportData(player)
	end
	applyToPlayer(player)
end

function MatchSystem.getSettings(): MatchSettings
	return settings or {
		difficulty = Config.Party.DefaultDifficulty,
		friendsOnly = false,
		partySize = 1,
	}
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

	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
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
	settings = nil
end

return MatchSystem
