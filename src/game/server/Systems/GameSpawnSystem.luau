local Players = game:GetService("Players")

local GameSpawnSystem = {}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local respawning: { [Player]: boolean } = {}

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

local function watchCharacter(player: Player, character: Model)
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

local function watchPlayer(player: Player)
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end))
	if player.Character then
		watchCharacter(player, player.Character)
	elseif not Players.CharacterAutoLoads then
		task.defer(loadCharacter, player)
	end
end

function GameSpawnSystem.start()
	if isStarted then
		return
	end
	isStarted = true

	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		respawning[player] = nil
	end))
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
	table.clear(respawning)
end

return GameSpawnSystem
