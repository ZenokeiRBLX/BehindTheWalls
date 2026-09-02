-- ServerScriptService/Server/Systems/DataSystem.luau

local Server = script.Parent.Parent
local Modules = Server:WaitForChild("Modules")
local DataService = require(Modules:WaitForChild("DataService"))

local DataSystem = {}

function DataSystem.start()
	DataService.start()
end

function DataSystem.stop()
	DataService.stop()
end

return DataSystem
