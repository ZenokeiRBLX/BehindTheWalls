local Client = script.Parent
local Controllers = Client:WaitForChild("Controllers")
local ControllerRegistry = require(Controllers:WaitForChild("ControllerRegistry"))

ControllerRegistry.start()

print("Client bootstrap loaded.")
