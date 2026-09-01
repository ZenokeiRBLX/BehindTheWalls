local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

print(string.format("%s server initialized.", Config.GameName))

Players.PlayerAdded:Connect(function(player)
	print(string.format("Player joined: %s", player.Name))
end)

Players.PlayerRemoving:Connect(function(player)
	print(string.format("Player left: %s", player.Name))
end)
