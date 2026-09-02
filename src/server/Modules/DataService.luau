-- ServerScriptService/Server/Modules/DataService.luau

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = script.Parent
local DataConfig = require(Modules:WaitForChild("DataConfig"))
local ProfileStore = require(Modules:WaitForChild("ProfileStore"))
local ProfileTemplate = require(Modules:WaitForChild("ProfileTemplate"))
local Replica = require(ServerScriptService:WaitForChild("ReplicaServer"))

export type PlayerData = ProfileTemplate.PlayerData

type PlayerProfile = ProfileStore.Profile<PlayerData>

local PROFILE_TEMPLATE: PlayerData = ProfileTemplate

local PLAYER_DATA_TOKEN = Replica.Token("PlayerData")
local PROFILE_STORE_NAME = "PlayerData_v1"
local PROFILE_LOAD_FAILURE_MESSAGE = "Unable to load your data. Please rejoin."

local livePlayerStore = ProfileStore.New(PROFILE_STORE_NAME, PROFILE_TEMPLATE)
local playerStore = livePlayerStore
if RunService:IsStudio() and DataConfig.UseMockProfileStoreInStudio == true then
	playerStore = livePlayerStore.Mock
end

local profiles: { [Player]: PlayerProfile } = {}
local playerReplicas: { [Player]: any } = {}
local playerAddedConnection: RBXScriptConnection?
local playerRemovingConnection: RBXScriptConnection?
local readyPlayerConnection: any?
local isStarted = false
local playerDataActionHandlers: { [string]: (Player, ...any) -> () } = {}

local DataService = {}

local function sanitizeCoins(amount: any): number
	return math.max(0, math.floor(tonumber(amount) or 0))
end

local function sanitizePlayTime(amount: any): number
	return math.max(0, math.floor(tonumber(amount) or 0))
end

local function sanitizeTimestamp(amount: any): number
	return math.max(0, math.floor(tonumber(amount) or 0))
end

local function sanitizeBooleanMap(value: any): { [string]: boolean }
	if type(value) ~= "table" then
		return {}
	end

	local result = {}
	for key, mapValue in value do
		if type(key) == "string" and mapValue == true then
			result[key] = true
		end
	end

	return result
end

local function subscribePlayerReplica(player: Player)
	local replica = playerReplicas[player]
	if replica and replica:IsActive() and Replica.ReadyPlayers[player] == true then
		replica:Subscribe(player)
	end
end

local function setReplicaCoins(player: Player, coins: number)
	local replica = playerReplicas[player]
	if replica and replica:IsActive() and replica.Data.Coins ~= coins then
		replica:Set({ "Coins" }, coins)
	end
end

local function setReplicaPlayTime(player: Player, playTime: number)
	local replica = playerReplicas[player]
	if replica and replica:IsActive() and replica.Data.PlayTime ~= playTime then
		replica:Set({ "PlayTime" }, playTime)
	end
end

local function setReplicaSetting(player: Player, settingName: string, enabled: boolean)
	local replica = playerReplicas[player]
	if replica and replica:IsActive() and replica.Data.Settings[settingName] ~= enabled then
		replica:Set({ "Settings", settingName }, enabled)
	end
end

local function dispatchPlayerDataAction(player: Player, actionName: any, ...: any)
	if typeof(actionName) ~= "string" then
		return
	end

	local handler = playerDataActionHandlers[actionName]
	if not handler then
		return
	end

	handler(player, ...)
end

local function createPlayerReplica(player: Player, profile: PlayerProfile)
	local replica = Replica.New({
		Token = PLAYER_DATA_TOKEN,
		Tags = {
			UserId = player.UserId,
		},
		Data = {
			Coins = profile.Data.Coins,
			PlayTime = profile.Data.PlayTime,
			Settings = profile.Data.Settings,
		},
	})

	replica.OnServerEvent:Connect(function(playerWhoFired: Player, actionName: any, ...: any)
		if playerWhoFired == player then
			dispatchPlayerDataAction(player, actionName, ...)
		end
	end)

	playerReplicas[player] = replica
	subscribePlayerReplica(player)
end

local function destroyPlayerReplica(player: Player)
	local replica = playerReplicas[player]
	if replica then
		playerReplicas[player] = nil
		replica:Destroy()
	end
end

local function cleanupPlayer(player: Player)
	destroyPlayerReplica(player)
	profiles[player] = nil
end

local function onPlayerAdded(player: Player)
	local profile = (playerStore :: any):StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	}) :: PlayerProfile?

	if profile == nil then
		player:Kick(PROFILE_LOAD_FAILURE_MESSAGE)
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.Data.Coins = sanitizeCoins(profile.Data.Coins)
	profile.Data.PlayTime = sanitizePlayTime(profile.Data.PlayTime)
	profile.Data.LastLogoutTime = sanitizeTimestamp(profile.Data.LastLogoutTime)
	profile.Data.Settings = sanitizeBooleanMap(profile.Data.Settings)

	profile.OnSessionEnd:Connect(function()
		cleanupPlayer(player)

		if player.Parent == Players then
			player:Kick("Your data was loaded on another server.")
		end
	end)

	if player.Parent == Players then
		profiles[player] = profile
		createPlayerReplica(player, profile)
	else
		profile:EndSession()
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Data.LastLogoutTime = os.time()
		profile:EndSession()
	end
end

function DataService.start()
	if isStarted then
		return
	end

	isStarted = true

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	playerAddedConnection = Players.PlayerAdded:Connect(onPlayerAdded)
	playerRemovingConnection = Players.PlayerRemoving:Connect(onPlayerRemoving)
	readyPlayerConnection = Replica.NewReadyPlayer:Connect(subscribePlayerReplica)
end

function DataService.stop()
	if not isStarted then
		return
	end

	isStarted = false

	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end

	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	if readyPlayerConnection then
		readyPlayerConnection:Disconnect()
		readyPlayerConnection = nil
	end

	local activeProfiles = {}
	for player, profile in profiles do
		table.insert(activeProfiles, {
			player = player,
			profile = profile,
		})
	end

	for _, entry in activeProfiles do
		entry.profile.Data.LastLogoutTime = os.time()
		cleanupPlayer(entry.player)
		entry.profile:EndSession()
	end
end

function DataService.registerActionHandler(actionName: string, handler: (Player, ...any) -> ())
	playerDataActionHandlers[actionName] = handler
end

function DataService.resetData(player: Player): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	for key in profile.Data do
		profile.Data[key] = nil
	end
	profile:Reconcile()

	return true
end

function DataService.getProfile(player: Player): PlayerProfile?
	return profiles[player]
end

function DataService.getData(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.getCoins(player: Player): number?
	local data = DataService.getData(player)
	return if data then data.Coins else nil
end

function DataService.setCoins(player: Player, amount: number): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	local coins = sanitizeCoins(amount)
	profile.Data.Coins = coins
	setReplicaCoins(player, coins)

	return true
end

function DataService.addCoins(player: Player, amount: number): boolean
	local coins = DataService.getCoins(player)
	if coins == nil then
		return false
	end

	return DataService.setCoins(player, coins + amount)
end

function DataService.getPlayTime(player: Player): number?
	local data = DataService.getData(player)
	return if data then data.PlayTime else nil
end

function DataService.setPlayTime(player: Player, amount: number): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	local playTime = sanitizePlayTime(amount)
	profile.Data.PlayTime = playTime
	setReplicaPlayTime(player, playTime)

	return true
end

function DataService.addPlayTime(player: Player, amount: number): boolean
	local playTime = DataService.getPlayTime(player)
	if playTime == nil then
		return false
	end

	return DataService.setPlayTime(player, playTime + math.max(0, amount))
end

function DataService.getSetting(player: Player, settingName: string): boolean
	local data = DataService.getData(player)
	return data ~= nil and data.Settings[settingName] == true
end

function DataService.setSetting(player: Player, settingName: string, enabled: boolean): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end

	if enabled then
		profile.Data.Settings[settingName] = true
	else
		profile.Data.Settings[settingName] = nil
	end
	setReplicaSetting(player, settingName, enabled)

	return true
end

return DataService
