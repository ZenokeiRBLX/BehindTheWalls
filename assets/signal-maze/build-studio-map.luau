local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local MaterialService = game:GetService("MaterialService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local origin = Vector3.new(147, 0, 54)
assert(game.PlaceId == 126262358232325, "This build targets Map Creation")
assert(not workspace:FindFirstChild("SignalMaze"), "SignalMaze already exists")
assert(not ServerStorage:FindFirstChild("SignalMaze_Backup"), "A maze backup already exists")
local sourceA = workspace:FindFirstChild("Wall_1")
local sourceB = workspace:FindFirstChild("Wall_2")
assert(sourceA and sourceB, "Both original walls are required")
local tvTemplate = sourceA:FindFirstChild("Old Tv", true):Clone()
for _, child in tvTemplate:GetChildren() do
	child:Destroy()
end
ChangeHistoryService:SetWaypoint("Before Signal Maze")
local backup = Instance.new("Folder")
backup.Name = "SignalMaze_Backup"
backup.Parent = ServerStorage
for _, property in {"Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "FogColor", "FogStart", "FogEnd", "GlobalShadows"} do
	backup:SetAttribute(property, Lighting[property])
end
backup:SetAttribute("CameraCFrame", workspace.CurrentCamera.CFrame)
local savedLighting = Instance.new("Folder")
savedLighting.Name = "OriginalLighting"
savedLighting.Parent = backup
for _, child in Lighting:GetChildren() do
	child.Parent = savedLighting
end
for _, child in workspace:GetChildren() do
	if child == sourceA or child == sourceB or child.Name == "Baseplate" or child:IsA("SpawnLocation") then
		child.Parent = backup
	end
end
local root = Instance.new("Model")
root.Name = "SignalMaze"
root:SetAttribute("BuildVersion", 1)
root:SetAttribute("Footprint", "112 x 112 studs")
root:SetAttribute("Design", "Entrance throat, signal court, two side chambers, looping passages, receiver chamber")
root:SetAttribute("Origin", origin)
root.Parent = workspace
local function group(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = root
	return model
end
local architecture = group("Architecture")
local walls = group("BoneWalls")
local screens = group("EmbeddedTVs")
local detail = group("Landmarks")
local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local floorMaterial = Instance.new("MaterialVariant")
floorMaterial.Name = "SignalMaze_WetFloor"
floorMaterial.BaseMaterial = Enum.Material.SmoothPlastic
floorMaterial.NormalMap = "rbxassetid://136727296834708"
floorMaterial.RoughnessMap = "rbxassetid://114387089191722"
floorMaterial.StudsPerTile = 12
floorMaterial.Parent = MaterialService
local floor = part("WetFloor", Vector3.new(116, 1, 116), CFrame.new(origin + Vector3.new(0, -0.5, 0)), Color3.fromRGB(30, 23, 26), architecture, true)
floor.MaterialVariant = floorMaterial.Name
local ceiling = part("Ceiling_RemoveForLayoutView", Vector3.new(116, 1, 116), CFrame.new(origin + Vector3.new(0, 18.6, 0)), Color3.fromRGB(12, 10, 13), architecture, true)
ceiling.Material = Enum.Material.Concrete
local wallIndex = 0
local function wall(name: string, x: number, z: number, length: number, yaw: number): MeshPart
	wallIndex += 1
	local source = wallIndex % 2 == 0 and sourceB.Wall or sourceA.Wall
	local mesh = source:Clone()
	mesh.Name = name
	local size = Vector3.new(length + 0.5, 18.5, 5.2)
	local ratio = size / mesh.Size
	mesh.Size = size
	mesh.CFrame = CFrame.new(origin + Vector3.new(x, 9.1, z)) * CFrame.Angles(0, math.rad(yaw), 0)
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanTouch = false
	mesh.CanQuery = false
	mesh.CastShadow = true
	mesh.RenderFidelity = Enum.RenderFidelity.Automatic
	mesh.Color = Color3.fromRGB(204, 174, 179)
	for _, bone in mesh:GetDescendants() do
		if bone:IsA("Bone") then
			bone.CFrame = CFrame.new(bone.Position * ratio) * bone.CFrame.Rotation
			bone.Transform = CFrame.identity
		end
	end
	mesh.Parent = walls
	local collision = part(name .. "_Collision", Vector3.new(length + 0.5, 18.5, 5.2), mesh.CFrame, Color3.new(), architecture, true)
	collision.Transparency = 1
	return mesh
end
wall("SouthWest", -27, 54, 54, 0)
wall("SouthEast", 27, 54, 54, 0)
wall("NorthWest", -27, -54, 54, 180)
wall("NorthEast", 27, -54, 54, 180)
wall("WestSouth", -54, 27, 54, 90)
wall("WestNorth", -54, -27, 54, 90)
wall("EastSouth", 54, 27, 54, -90)
wall("EastNorth", 54, -27, 54, -90)
wall("Wall_1_Entrance", -10, 36, 36, 90)
wall("Wall_2_Entrance", 10, 36, 36, -90)
wall("WestChamberSpine", -28, 32, 44, 90)
wall("EastChamberSpine", 28, 31, 46, -90)
wall("CourtNorthWest", -31, -8, 46, 0)
wall("CourtNorthEast", 19, -8, 22, 0)
wall("ReceiverSpine", -10, -40, 28, 90)
wall("Dogleg", 31, -30, 46, 180)
wall("BlindAlcove", -43, -1, 14, 90)
local tvIndex = 0
local lightCount = 0
local function tv(name: string, position: Vector3, yaw: number, scale: number, red: boolean, lit: boolean, roll: number?): Model
	tvIndex += 1
	local model = Instance.new("Model")
	model.Name = string.format("%02d_%s", tvIndex, name)
	model.Parent = screens
	local cf = CFrame.new(origin + position) * CFrame.Angles(0, math.rad(yaw), math.rad(roll or 0))
	local housing = tvTemplate:Clone()
	housing.Name = "Housing"
	housing.Size = tvTemplate.Size * scale
	housing.CFrame = cf
	housing.Color = Color3.fromRGB(140, 129, 128)
	housing.Anchored = true
	housing.CanCollide = false
	housing.CanTouch = false
	housing.CanQuery = false
	housing.CastShadow = false
	housing.RenderFidelity = Enum.RenderFidelity.Automatic
	housing.Parent = model
	local screen = part("BroadcastGlass", Vector3.new(2, 1.38, 0.035) * scale, cf * CFrame.new(0.255 * scale, -0.265 * scale, -0.928 * scale), Color3.fromRGB(8, 5, 7), model, false)
	screen.CastShadow = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Signal"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(512, 400)
	gui.LightInfluence = 0
	gui.Brightness = red and 1.5 or 0.55
	gui.MaxDistance = 85
	gui.Parent = screen
	local signal = Instance.new("ImageLabel")
	signal.Name = red and "RedSilhouette" or "Static"
	signal.Size = UDim2.fromScale(1, 1)
	signal.BackgroundColor3 = Color3.fromRGB(12, 2, 3)
	signal.BorderSizePixel = 0
	signal.Image = "rbxassetid://125278888728934"
	signal.ImageRectOffset = Vector2.new(red and 512 or 0, 0)
	signal.ImageRectSize = Vector2.new(512, 512)
	signal.ImageColor3 = red and Color3.fromRGB(255, 148, 143) or Color3.fromRGB(164, 189, 193)
	signal.Parent = gui
	if lit then
		lightCount += 1
		local light = Instance.new("SurfaceLight")
		light.Name = "ScreenSpill"
		light.Face = Enum.NormalId.Front
		light.Angle = 125
		light.Range = scale > 2 and 27 or 21
		light.Brightness = red and 1.65 or 0.6
		light.Color = red and Color3.fromRGB(255, 66, 57) or Color3.fromRGB(138, 169, 182)
		light.Shadows = false
		light.Parent = screen
	end
	return model
end
for sideIndex, side in {-1, 1} do
	for i, z in {23, 32, 43, 49} do
		local y = i % 2 == 0 and 11.5 or 5.6
		tv("Entrance", Vector3.new(side * 7.25, y, z), side < 0 and -90 or 90, i == 2 and 1.65 or 1.25, i ~= 3, i == 1 or i == 3, side * (i % 2 == 0 and 7 or -5))
	end
end
tv("CourtWitness", Vector3.new(-17, 8.6, -5.1), 180, 2.5, true, true)
tv("CourtStatic", Vector3.new(-36, 12, -5.1), 180, 1.65, false, false, -8)
tv("CourtLow", Vector3.new(19, 5.3, -5.1), 180, 1.65, true, true, 9)
tv("CourtHigh", Vector3.new(25, 13, -5.1), 180, 1.2, false, false, -6)
tv("WestChamber", Vector3.new(-51.15, 8.3, 34), -90, 2.5, true, true, -6)
tv("WestChamberStatic", Vector3.new(-51.15, 13, 19), -90, 1.6, false, false, 8)
tv("WestChamberLow", Vector3.new(-31, 4, 43), 90, 1.4, true, false, -9)
tv("EastChamber", Vector3.new(51.15, 10, 36), 90, 2.75, false, true, 4)
tv("EastChamberLow", Vector3.new(51.15, 4.5, 23), 90, 1.5, true, false, -10)
tv("EastChamberWitness", Vector3.new(31, 8, 43), -90, 1.6, true, true)
tv("DoglegSignal", Vector3.new(35, 7, -27), 180, 2.2, true, true, -6)
tv("DoglegStatic", Vector3.new(18, 12, -27), 180, 1.3, false, false)
tv("NorthSignal", Vector3.new(26, 9, -51), 180, 2, true, true)
tv("NorthStatic", Vector3.new(7, 5, -51), 180, 1.7, false, false, 8)
tv("SpineSignal", Vector3.new(-7, 8, -39), -90, 1.6, true, false, -5)
tv("Receiver", Vector3.new(-39, 9, -51), 180, 3.6, true, true)
tv("ReceiverLeft", Vector3.new(-50.8, 5, -42), -90, 1.65, false, true, 8)
tv("ReceiverRight", Vector3.new(-13, 12, -43), 90, 1.5, true, false, -8)
tv("Alcove", Vector3.new(-48, 7, -5), 180, 1.3, true, false, 12)
local altar = part("ReceiverPlinth", Vector3.new(10, 2, 5), CFrame.new(origin + Vector3.new(-39, 1, -46)), Color3.fromRGB(35, 25, 28), detail, true)
altar.Material = Enum.Material.Slate
local pedestal = part("CourtPlinth", Vector3.new(6, 3.6, 4), CFrame.new(origin + Vector3.new(0, 1.8, 4)), Color3.fromRGB(28, 21, 24), detail, true)
pedestal.Material = Enum.Material.Slate
tv("CourtFreestanding", Vector3.new(0, 5.25, 4), 180, 1.35, false, false, -4)
for i, position in {Vector3.new(-42, 0.08, 32), Vector3.new(41, 0.08, 29), Vector3.new(-37, 0.08, -39)} do
	local pool = part("DarkPool_" .. i, Vector3.new(13, 0.08, 9), CFrame.new(origin + position) * CFrame.Angles(0, math.rad(i * 21), 0), Color3.fromRGB(13, 5, 8), detail, false)
	pool.Material = Enum.Material.Glass
	pool.Reflectance = 0
	pool.Transparency = 0.72
	pool.Shape = Enum.PartType.Cylinder
	pool.Size = Vector3.new(0.06, 11, 15)
	pool.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
	pool.CastShadow = false
end
local spawn = Instance.new("SpawnLocation")
spawn.Name = "MazeEntrance"
spawn.Size = Vector3.new(10, 0.2, 8)
spawn.CFrame = CFrame.new(origin + Vector3.new(0, 0.1, 46))
spawn.Transparency = 1
spawn.Anchored = true
spawn.CanCollide = false
spawn.Neutral = true
spawn.Duration = 0
spawn.Parent = root
Lighting.ClockTime = 0
Lighting.Brightness = 0.6
Lighting.Ambient = Color3.fromRGB(65, 52, 59)
Lighting.OutdoorAmbient = Color3.fromRGB(21, 19, 27)
Lighting.ExposureCompensation = 0.15
Lighting.EnvironmentDiffuseScale = 0.2
Lighting.EnvironmentSpecularScale = 0.65
Lighting.GlobalShadows = true
Lighting.FogColor = Color3.fromRGB(30, 21, 26)
Lighting.FogStart = 14
Lighting.FogEnd = 108
local sky = savedLighting:FindFirstChildWhichIsA("Sky")
if sky then sky:Clone().Parent = Lighting end
local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "SignalMaze_Grade"
grade.Contrast = 0.08
grade.Saturation = -0.22
grade.TintColor = Color3.fromRGB(255, 234, 237)
grade.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Name = "SignalMaze_ScreenBloom"
bloom.Intensity = 0.18
bloom.Size = 20
bloom.Threshold = 1.25
bloom.Parent = Lighting
workspace.CurrentCamera.CFrame = CFrame.lookAt(origin + Vector3.new(0, 6, 49), origin + Vector3.new(-1, 7, 5))
workspace.CurrentCamera.FieldOfView = 75
local counts = {parts = 0, bones = 0, lights = 0, screens = tvIndex}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then counts.parts += 1 end
	if d:IsA("Bone") then counts.bones += 1 end
	if d:IsA("Light") then counts.lights += 1 end
end
root:SetAttribute("PartCount", counts.parts)
root:SetAttribute("ScreenCount", counts.screens)
root:SetAttribute("LightCount", counts.lights)
tvTemplate:Destroy()
ChangeHistoryService:SetWaypoint("Build Signal Maze")
return game:GetService("HttpService"):JSONEncode(counts)
