local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))

local SpawnSystem = {}

local isStarted = false

function SpawnSystem.start()
	if isStarted then
		return
	end
	isStarted = true

	Blink.RequestSpawn.On(function(player)
		if player.Character and player.Character.Parent then
			return
		end
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn(("SpawnSystem failed to load character for %s: %s"):format(player.Name, tostring(err)))
		end
	end)
end

return SpawnSystem
