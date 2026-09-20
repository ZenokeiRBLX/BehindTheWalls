local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local MaterialService = game:GetService("MaterialService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local rng = Random.new(8319)
assert(not workspace:FindFirstChild("SignalHallway_Mockup"), "The hallway already exists")
local sourceWall = workspace:FindFirstChild("Flesh_Wall")
local sourceTv = workspace:FindFirstChild("Tv")
assert(sourceWall and sourceTv, "Expected the existing Flesh_Wall and Tv models")
local wallTemplate = sourceWall:FindFirstChild("Wall"):Clone()
local tvTemplate = sourceTv:FindFirstChild("Old Tv"):Clone()
ChangeHistoryService:SetWaypoint("Before signal hallway mockup")
local backup = Instance.new("Folder")
backup.Name = "SignalHallway_Backup"
backup.Parent = ServerStorage
for _, property in {"Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "FogColor", "FogStart", "FogEnd", "GlobalShadows"} do
	backup:SetAttribute(property, Lighting[property])
end
local lightingBackup = Instance.new("Folder")
lightingBackup.Name = "OriginalLighting"
lightingBackup.Parent = backup
for _, child in Lighting:GetChildren() do
	child.Parent = lightingBackup
end
for _, child in workspace:GetChildren() do
	if child.Name == "Flesh_Wall" or child.Name == "Tv" or child.Name == "Rig" or child:IsA("SpawnLocation") then
		child.Parent = backup
	end
end
local root = Instance.new("Model")
root.Name = "SignalHallway_Mockup"
root:SetAttribute("WalkDirection", "From X=179 toward X=117; center Z=55")
root.Parent = workspace
local function group(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end
local architecture = group("Architecture", root)
local walls = group("PosedFleshWalls", root)
local growth = group("OrganicRidges", root)
local televisions = group("EmbeddedTelevisions", root)
local atmosphere = group("HazeAndLight", root)
local floorDetail = group("WetFloor", root)
local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CanQuery = collide == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end
local floorMaterial = Instance.new("MaterialVariant")
floorMaterial.Name = "SignalHallway_WetFloor"
floorMaterial.BaseMaterial = Enum.Material.SmoothPlastic
floorMaterial.NormalMap = "rbxassetid://136727296834708"
floorMaterial.RoughnessMap = "rbxassetid://114387089191722"
floorMaterial.StudsPerTile = 9
floorMaterial.Parent = MaterialService
local floor = part("WalkableWetFloor", Vector3.new(68, 1, 22), CFrame.new(147, -0.5, 55), Color3.fromRGB(29, 17, 20), architecture, true)
floor.MaterialVariant = floorMaterial.Name
part("RemovableCeiling", Vector3.new(66, 1, 24), CFrame.new(147, 20.5, 55), Color3.fromRGB(12, 8, 11), architecture, true)
part("TerminalBacking", Vector3.new(1, 21, 24), CFrame.new(115, 10, 55), Color3.fromRGB(18, 8, 12), architecture, true)
local function flesh(name: string, size: Vector3, cf: CFrame): Part
	local p = part(name, size, cf, Color3.fromRGB(211, 184, 185), growth)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Salt
	p.MaterialVariant = "Flesh_WetFolds_V2"
	return p
end
for sideIndex, side in {-1, 1} do
	local wallZ = 55 + side * 9.3
	for bay = 1, 3 do
		local x = 187 - bay * 20
		local model = group((side < 0 and "Left" or "Right") .. "Wall_" .. bay, walls)
		local wall = wallTemplate:Clone()
		local size = Vector3.new(21.5, 20, 5.4)
		local ratio = size / wall.Size
		wall.Size = size
		wall.CFrame = CFrame.new(x, 9.8, wallZ)
		wall.Anchored = true
		wall.CanCollide = false
		wall.CanTouch = false
		wall.CanQuery = false
		wall.Color = Color3.fromRGB(219, 195, 194)
		wall.Material = Enum.Material.Salt
		wall.MaterialVariant = "Flesh_WetFolds_V2"
		for _, bone in wall:GetChildren() do
			if bone:IsA("Bone") then
				local rest = bone.CFrame.Position * ratio
				local swell = rng:NextNumber(-0.45, 1.55)
				bone.CFrame = CFrame.new(rest + Vector3.new(rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.25, 0.25), -side * swell)) * CFrame.Angles(0, rng:NextNumber(-0.065, 0.065), rng:NextNumber(-0.04, 0.04))
				bone.Transform = CFrame.identity
			end
		end
		wall.Parent = model
		part("InvisibleWallCollision", Vector3.new(21.5, 20, 1), CFrame.new(x, 10, 55 + side * 7.1), Color3.new(), model, true).Transparency = 1
	end
	for ridge = 0, 8 do
		local x = 176 - ridge * 7.1 + rng:NextNumber(-0.65, 0.65)
		local phase = rng:NextNumber(0, 6.28)
		for level = 0, 5 do
			local y = 0.7 + level * 3.55
			local bend = math.sin(level * 1.35 + phase)
			flesh("Fold_" .. sideIndex .. "_" .. ridge .. "_" .. level, Vector3.new(rng:NextNumber(1.55, 2.75), rng:NextNumber(4.8, 5.8), rng:NextNumber(1.8, 2.65)), CFrame.new(x + bend * 0.7, y, 55 + side * (6.9 + bend * 0.35)) * CFrame.Angles(side * 0.14, 0, bend * 0.18))
		end
		flesh("FloorRoot_" .. sideIndex .. "_" .. ridge, Vector3.new(3.7, 1.25, 3.4), CFrame.new(x, 0.35, 55 + side * 6.4) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0))
	end
end
local function addBroadcast(name: string, cf: CFrame, scale: number, red: boolean)
	local model = group(name, televisions)
	local housing = tvTemplate:Clone()
	housing.Name = "VintageHousing"
	housing.Size = tvTemplate.Size * scale
	housing.CFrame = cf
	housing.Color = Color3.fromRGB(111, 99, 98)
	housing.Anchored = true
	housing.CanCollide = false
	housing.CanTouch = false
	housing.CanQuery = false
	for _, child in housing:GetChildren() do
		if child:IsA("LuaSourceContainer") then child:Destroy() end
	end
	housing.Parent = model
	local screen = part("BroadcastGlass", Vector3.new(2.12, 1.63, 0.035) * scale, cf * CFrame.new(-0.245 * scale, -0.065 * scale, -0.928 * scale), Color3.fromRGB(8, 5, 7), model)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Broadcast"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(512, 400)
	gui.LightInfluence = 0
	gui.Brightness = red and 2.1 or 0.8
	gui.MaxDistance = 110
	gui.Parent = screen
	local signal = Instance.new("ImageLabel")
	signal.Name = red and "RedSilhouette" or "Static"
	signal.Size = UDim2.fromScale(1, 1)
	signal.BackgroundColor3 = Color3.fromRGB(12, 2, 3)
	signal.BorderSizePixel = 0
	signal.Image = "rbxassetid://125278888728934"
	signal.ImageRectOffset = Vector2.new(red and 512 or 0, 0)
	signal.ImageRectSize = Vector2.new(512, 512)
	signal.ImageColor3 = red and Color3.fromRGB(255, 137, 129) or Color3.fromRGB(174, 187, 179)
	signal.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.085, 0)
	corner.Parent = signal
	for i = 1, 30 do
		local line = Instance.new("Frame")
		line.Name = "Scanline"
		line.Size = UDim2.fromScale(1, 0.006)
		line.Position = UDim2.fromScale(0, i / 31)
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new()
		line.BackgroundTransparency = 0.65
		line.Parent = signal
	end
	local light = Instance.new("SurfaceLight")
	light.Name = "ScreenSpill"
	light.Face = Enum.NormalId.Front
	light.Color = red and Color3.fromRGB(255, 51, 47) or Color3.fromRGB(163, 185, 180)
	light.Brightness = red and 1.7 or 0.65
	light.Range = red and 15 or 11
	light.Angle = 125
	light.Shadows = true
	light.Parent = screen
end
for sideIndex, side in {-1, 1} do
	for column = 0, 8 do
		for row = 0, 2 do
			local red = (column + row + sideIndex) % 3 ~= 0
			local scale = red and rng:NextNumber(1.2, 1.6) or rng:NextNumber(1.85, 2.08)
			local x = 174 - column * 6.5 + ((row % 2 == 0) and 0.5 or -0.75) + rng:NextNumber(-0.35, 0.35)
			local y = 3.0 + row * 6.15 + rng:NextNumber(-0.65, 0.65)
			local cf = CFrame.new(x, y, 55 + side * 6.35) * CFrame.Angles(0, side < 0 and math.pi or 0, 0) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.17, 0.17))
			addBroadcast("CRT_" .. sideIndex .. "_" .. column .. "_" .. row, cf, scale, red)
		end
	end
end
addBroadcast("EndBroadcast_High", CFrame.new(116.8, 11.8, 55.2) * CFrame.Angles(0, -math.pi / 2, 0), 1.55, true)
addBroadcast("EndBroadcast_Low", CFrame.new(117, 4.5, 57.8) * CFrame.Angles(0, -math.pi / 2, 0.06), 1.25, true)
for i = 1, 24 do
	local p = part("Puddle_" .. i, Vector3.new(rng:NextNumber(1.2, 5), 0.028, rng:NextNumber(0.55, 2.9)), CFrame.new(rng:NextNumber(118, 177), 0.02, rng:NextNumber(49.5, 60.5)) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0), Color3.fromRGB(14, 10, 13), floorDetail)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Glass
	p.Transparency = 0.32
	p.Reflectance = 0.12
end
for i = 0, 4 do
	local p = part("HazeEmitter_" .. i, Vector3.new(1, 1, 10), CFrame.new(174 - i * 13, 0.3, 55), Color3.new(), atmosphere)
	p.Transparency = 1
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "LowMist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(121, 110, 112))
	mist.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.94), NumberSequenceKeypoint.new(0.75, 0.96), NumberSequenceKeypoint.new(1, 1)})
	mist.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 10)})
	mist.Lifetime = NumberRange.new(9, 14)
	mist.Rate = 2
	mist.Speed = NumberRange.new(0.08, 0.18)
	mist.SpreadAngle = Vector2.new(80, 80)
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-4, 4)
	mist.LightInfluence = 0.2
	mist.LightEmission = 0.12
	mist.Parent = p
	local bounce = part("SoftFill_" .. i, Vector3.one, CFrame.new(174 - i * 13, 13, 55), Color3.new(), atmosphere)
	bounce.Transparency = 1
	local fill = Instance.new("PointLight")
	fill.Color = Color3.fromRGB(192, 155, 158)
	fill.Brightness = 0.55
	fill.Range = 19
	fill.Shadows = true
	fill.Parent = bounce
end
Lighting.Ambient = Color3.fromRGB(25, 18, 23)
Lighting.OutdoorAmbient = Color3.fromRGB(20, 15, 19)
Lighting.Brightness = 0
Lighting.ClockTime = 0
Lighting.GlobalShadows = true
Lighting.EnvironmentDiffuseScale = 0.25
Lighting.EnvironmentSpecularScale = 1
Lighting.ExposureCompensation = -0.12
Lighting.FogColor = Color3.fromRGB(33, 26, 30)
Lighting.FogStart = 17
Lighting.FogEnd = 87
local sky = lightingBackup:FindFirstChildOfClass("Sky")
if sky then sky:Clone().Parent = Lighting end
local bloom = Instance.new("BloomEffect")
bloom.Name = "SignalScreenBloom"
bloom.Intensity = 0.24
bloom.Size = 27
bloom.Threshold = 1.25
bloom.Parent = Lighting
local grading = Instance.new("ColorCorrectionEffect")
grading.Name = "SignalFilmGrade"
grading.Brightness = -0.015
grading.Contrast = 0.12
grading.Saturation = -0.15
grading.TintColor = Color3.fromRGB(255, 238, 240)
grading.Parent = Lighting
local spawn = Instance.new("SpawnLocation")
spawn.Name = "HallwayTestSpawn"
spawn.Size = Vector3.new(4, 1, 4)
spawn.CFrame = CFrame.new(177, 0.5, 55) * CFrame.Angles(0, math.pi / 2, 0)
spawn.Anchored = true
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Neutral = true
spawn.Duration = 0
spawn.Parent = root
local starter = game:GetService("StarterPlayer")
backup:SetAttribute("CameraMode", starter.CameraMode.Name)
backup:SetAttribute("CharacterWalkSpeed", starter.CharacterWalkSpeed)
starter.CameraMode = Enum.CameraMode.LockFirstPerson
starter.CharacterWalkSpeed = 10
workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(178, 6.6, 55), Vector3.new(118, 7.7, 55))
workspace.CurrentCamera.FieldOfView = 76
game:GetService("Selection"):Set({})
wallTemplate:Destroy()
tvTemplate:Destroy()
ChangeHistoryService:SetWaypoint("Build signal hallway mockup")
return "Built SignalHallway_Mockup with 6 posed wall meshes, 56 televisions, wet floor, haze, and backed-up source assets"
