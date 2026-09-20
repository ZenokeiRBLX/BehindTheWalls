local MaterialService = game:GetService("MaterialService")
local variant = MaterialService:FindFirstChild("Flesh_WetFolds_V2")
if not variant then
	variant = Instance.new("MaterialVariant")
	variant.Name = "Flesh_WetFolds_V2"
end
variant.BaseMaterial = Enum.Material.SmoothPlastic
variant.ColorMap = "rbxassetid://114798040361975"
variant.NormalMap = "rbxassetid://136727296834708"
variant.RoughnessMap = "rbxassetid://114387089191722"
variant.MetalnessMap = ""
variant.StudsPerTile = 12
variant.MaterialPattern = Enum.MaterialPattern.Regular
variant.Parent = MaterialService

local model = workspace:FindFirstChild("FleshWall_Rigged9")
assert(model, "Build the rigged wall first")
local wall = model:FindFirstChild("Wall")
local surface = wall:FindFirstChildOfClass("SurfaceAppearance")
if not surface then
	surface = Instance.new("SurfaceAppearance")
	surface.Name = "WetFlesh"
end
surface.ColorMap = variant.ColorMap
surface.NormalMap = variant.NormalMap
surface.RoughnessMap = variant.RoughnessMap
surface.MetalnessMap = ""
surface.Parent = wall
wall.Material = Enum.Material.SmoothPlastic
wall.MaterialVariant = ""
wall.Color = Color3.new(1, 1, 1)
model:SetAttribute("MaterialVariantName", variant.Name)
model:SetAttribute("ColorMap", variant.ColorMap)
model:SetAttribute("NormalMap", variant.NormalMap)
model:SetAttribute("RoughnessMap", variant.RoughnessMap)

local statuses = {}
game:GetService("ContentProvider"):PreloadAsync({surface, variant}, function(id, status)
	statuses[id] = status.Name
end)
return game:GetService("HttpService"):JSONEncode({variant = variant:GetFullName(), surface = surface:GetFullName(), fetchStatuses = statuses})
