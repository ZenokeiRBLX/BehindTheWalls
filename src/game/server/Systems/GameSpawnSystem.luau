local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))
local MatchSystem = require(script.Parent:WaitForChild("MatchSystem"))

local GameSpawnSystem = {}

local SLOTS_FOLDER_NAME = "Teleport_Players"
local SLOT_WAIT = 10
local SLOT_HEIGHT_OFFSET = 3
local SLOT_ATTRIBUTE = "SpawnSlot"
local CUTSCENE_MARGIN = 10

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

local function dressRig(player: Player, slot: Slot)
	local rig = slot.rig
	if not rig or not rig.Parent then
		return
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not ok or not description then
		warn(("GameSpawnSystem: could not load appearance for %s: %s"):format(player.Name, tostring(description)))
		return
	end
	local applied, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not applied then
		warn(("GameSpawnSystem: could not apply appearance for %s: %s"):format(player.Name, tostring(err)))
	end
end

local function removeUnusedRigs()
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

local function placeCharacter(player: Player, character: Model)
	local slot = findSlot(player) or assignSlot(player)
	if not slot then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local flatLook = Vector3.new(slot.cframe.LookVector.X, 0, slot.cframe.LookVector.Z)
	local forward = if flatLook.Magnitude > 0.001 then flatLook.Unit else -Vector3.zAxis
	local position = slot.cframe.Position + Vector3.new(0, SLOT_HEIGHT_OFFSET, 0)
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
	return cutscene.FlightSeconds + cutscene.HoldSeconds + Config.Party.MinLoadingSeconds + CUTSCENE_MARGIN
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

	loadSlots()
	disconnectCutscene = Blink.CutsceneFinished.On(function(player)
		cutsceneDone[player] = true
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
	table.clear(slots)
end

return GameSpawnSystem
