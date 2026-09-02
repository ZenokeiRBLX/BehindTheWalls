-- StarterPlayer/StarterPlayerScripts/Client/Controllers/PlayerDataController.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Replica = require(ReplicatedStorage:WaitForChild("ReplicaClient"))

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_DATA_TOKEN = "PlayerData"

local PlayerDataController = {}

local playerReplica: any?
local replicaConnection: any?
local isStarted = false
local readyCallbacks: { (replica: any) -> () } = {}

local function bindPlayerDataReplica(replica)
	if replica.Tags.UserId ~= LOCAL_PLAYER.UserId then
		return
	end

	playerReplica = replica
	for _, callback in readyCallbacks do
		task.spawn(callback, replica)
	end
end

function PlayerDataController.getReplica(): any?
	return playerReplica
end

function PlayerDataController.getData(): any?
	return if playerReplica then playerReplica.Data else nil
end

function PlayerDataController.onReplicaReady(callback: (replica: any) -> ())
	table.insert(readyCallbacks, callback)
	if playerReplica then
		task.spawn(callback, playerReplica)
	end
end

function PlayerDataController.start()
	if isStarted then
		return
	end

	isStarted = true

	replicaConnection = Replica.OnNew(PLAYER_DATA_TOKEN, bindPlayerDataReplica)
	Replica.RequestData()
end

function PlayerDataController.stop()
	if not isStarted then
		return
	end

	isStarted = false

	if replicaConnection then
		replicaConnection:Disconnect()
		replicaConnection = nil
	end

	playerReplica = nil
end

return PlayerDataController
