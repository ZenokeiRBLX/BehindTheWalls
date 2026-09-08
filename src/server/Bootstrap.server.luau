local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local Systems = Server:WaitForChild("Systems")
local SystemRegistry = require(Systems:WaitForChild("SystemRegistry"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

local hasGameSystems = Systems:FindFirstChild("MatchSystem") ~= nil
if game.PlaceId == Config.Places.Game and not hasGameSystems then
	warn("Bootstrap: this is the game place but the lobby tree is synced in; connect Rojo to game.project.json (port 34873)")
elseif game.PlaceId == Config.Places.Lobby and hasGameSystems then
	warn("Bootstrap: this is the lobby place but the game tree is synced in; connect Rojo to default.project.json (port 34872)")
end

SystemRegistry.start()

print("Server bootstrap loaded.")
