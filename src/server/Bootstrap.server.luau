local Server = script.Parent
local Systems = Server:WaitForChild("Systems")
local SystemRegistry = require(Systems:WaitForChild("SystemRegistry"))

SystemRegistry.start()

print("Server bootstrap loaded.")
