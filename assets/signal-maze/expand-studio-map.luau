local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local root = workspace:FindFirstChild("SignalMaze")
assert(game.PlaceId == 126262358232325, "This expansion targets Map Creation")
assert(root and root:GetAttribute("BuildVersion") == 1, "Expected the compact version of SignalMaze")
assert(not ServerStorage:FindFirstChild("SignalMaze_ExpansionBackup"), "An expansion backup already exists")
local origin = root:GetAttribute("Origin")
assert(typeof(origin) == "Vector3", "SignalMaze requires its original build origin")
local walls = root:FindFirstChild("BoneWalls")
local architecture = root:FindFirstChild("Architecture")
local screens = root:FindFirstChild("EmbeddedTVs")
local landmarks = root:FindFirstChild("Landmarks")
assert(walls and architecture and screens and landmarks, "The compact map hierarchy is incomplete")
assert(architecture:FindFirstChild("WetFloor") and architecture:FindFirstChild("Ceiling_RemoveForLayoutView"), "Floor and ceiling are required")
local wallRecords = {}
for _, mesh in walls:GetChildren() do
	assert(mesh:IsA("MeshPart"), "Unexpected instance in BoneWalls")
	local collision = architecture:FindFirstChild(mesh.Name .. "_Collision")
	assert(collision and collision:IsA("BasePart"), "Each wall requires a collision box")
	wallRecords[mesh.Name] = {mesh = mesh, collision = collision, oldCFrame = mesh.CFrame, oldSize = mesh.Size}
end
local changes = {
	Wall_1_Entrance = {x = -20, z = 82, length = 52},
	Wall_2_Entrance = {x = 20, z = 82, length = 52},
	WestChamberSpine = {x = -56, z = 76, length = 64},
	EastChamberSpine = {x = 56, z = 76, length = 64},
	CourtNorthEast = {x = 44, z = -16, length = 32},
	ReceiverSpine = {x = -20, z = -90, length = 36},
	Dogleg = {x = 72, z = -60, length = 72},
}
for name in changes do
	assert(wallRecords[name], "Expected wall missing: " .. name)
end
local screenRecords = {}
for _, model in screens:GetChildren() do
	local housing = model:FindFirstChild("Housing")
	assert(model:IsA("Model") and housing and model:FindFirstChild("BroadcastGlass"), "Unexpected TV structure")
	local record = {model = model, pivot = model:GetPivot(), housing = housing.CFrame}
	if not string.find(model.Name, "CourtFreestanding") then
		local closest = math.huge
		for _, wallRecord in wallRecords do
			local p = wallRecord.oldCFrame:PointToObjectSpace(housing.Position)
			local excess = math.max(math.abs(p.X) - wallRecord.oldSize.X / 2, 0)
			local distance = excess * excess + p.Z * p.Z
			if distance < closest then
				closest = distance
				record.wall = wallRecord
				record.localPosition = p
			end
		end
	end
	table.insert(screenRecords, record)
end
local redTemplate
local staticTemplate
for _, model in screens:GetChildren() do
	local signal = model.BroadcastGlass:FindFirstChild("Signal")
	local content = signal and signal:FindFirstChildWhichIsA("ImageLabel")
	if content and content.Name == "RedSilhouette" and not redTemplate then redTemplate = model end
	if content and content.Name == "Static" and not staticTemplate then staticTemplate = model end
end
assert(redTemplate and staticTemplate, "Both broadcast styles are required")
ChangeHistoryService:SetWaypoint("Before Signal Maze expansion")
local backup = Instance.new("Folder")
backup.Name = "SignalMaze_ExpansionBackup"
backup.Parent = ServerStorage
root:Clone().Parent = backup
for _, property in {"Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "FogColor", "FogStart", "FogEnd", "GlobalShadows"} do
	backup:SetAttribute(property, Lighting[property])
end
backup:SetAttribute("CameraCFrame", workspace.CurrentCamera.CFrame)
local oldLighting = Instance.new("Folder")
oldLighting.Name = "Lighting"
oldLighting.Parent = backup
for _, child in Lighting:GetChildren() do
	child:Clone().Parent = oldLighting
end
local function expandPosition(position: Vector3): Vector3
	local relative = position - origin
	return origin + Vector3.new(relative.X * 2, relative.Y, relative.Z * 2)
end
for _, record in wallRecords do
	local mesh = record.mesh
	local change = changes[mesh.Name]
	local size = Vector3.new((record.oldSize.X - 0.5) * 2 + 0.5, record.oldSize.Y, record.oldSize.Z)
	local position = expandPosition(record.oldCFrame.Position)
	if change then
		size = Vector3.new(change.length + 0.5, size.Y, size.Z)
		position = origin + Vector3.new(change.x, record.oldCFrame.Position.Y - origin.Y, change.z)
	end
	local ratio = size / record.oldSize
	mesh.Size = size
	mesh.CFrame = CFrame.new(position) * record.oldCFrame.Rotation
	for _, bone in mesh:GetDescendants() do
		if bone:IsA("Bone") then
			bone.CFrame = CFrame.new(bone.Position * ratio) * bone.CFrame.Rotation
		end
	end
	record.collision.Size = size
	record.collision.CFrame = mesh.CFrame
	record.lengthRatio = ratio.X
end
for _, name in {"WetFloor", "Ceiling_RemoveForLayoutView"} do
	local p = architecture[name]
	p.Size = p.Size * Vector3.new(2, 1, 2)
	p.CFrame = CFrame.new(expandPosition(p.Position)) * p.CFrame.Rotation
end
for _, item in landmarks:GetChildren() do
	if item:IsA("BasePart") then
		item.CFrame = CFrame.new(expandPosition(item.Position)) * item.CFrame.Rotation
	elseif item:IsA("Model") then
		local pivot = item:GetPivot()
		item:PivotTo(CFrame.new(expandPosition(pivot.Position)) * pivot.Rotation)
	end
end
for _, record in screenRecords do
	local destination
	if record.wall then
		local p = record.localPosition
		destination = record.wall.mesh.CFrame:PointToWorldSpace(Vector3.new(p.X * record.wall.lengthRatio, p.Y, p.Z))
	else
		destination = expandPosition(record.housing.Position)
	end
	record.model:PivotTo(record.pivot + (destination - record.housing.Position))
end
local spawn = root:FindFirstChild("MazeEntrance")
if spawn and spawn:IsA("BasePart") then
	spawn.CFrame = CFrame.new(expandPosition(spawn.Position)) * spawn.CFrame.Rotation
end
for _, d in screens:GetDescendants() do
	if d:IsA("Light") then
		d.Range = math.min(d.Range * 1.35, 34)
		d.Shadows = false
	elseif d:IsA("SurfaceGui") then
		d.MaxDistance = 125
	end
end
local additional = {
	{name = "WestGallery", position = Vector3.new(-105.1, 7, 28), yaw = -90, red = false},
	{name = "WestGalleryHigh", position = Vector3.new(-105.1, 12, 76), yaw = -90, red = true},
	{name = "EastGallery", position = Vector3.new(105.1, 7, 22), yaw = 90, red = false},
	{name = "EastGalleryHigh", position = Vector3.new(105.1, 12, 80), yaw = 90, red = true},
	{name = "CourtGuide", position = Vector3.new(-26, 6, -13.1), yaw = 180, red = false},
	{name = "NorthGuide", position = Vector3.new(65, 7, -105.1), yaw = 180, red = false},
	{name = "ReceiverGuide", position = Vector3.new(-52, 12, -105.1), yaw = 180, red = true},
	{name = "EastLoopGuide", position = Vector3.new(105.1, 6, -39), yaw = 90, red = true},
}
for _, spec in additional do
	local model = (spec.red and redTemplate or staticTemplate):Clone()
	model.Name = "Expansion_" .. spec.name
	for _, d in model:GetDescendants() do
		if d:IsA("Light") then d:Destroy() end
	end
	local housing = model.Housing
	local destination = CFrame.new(origin + spec.position) * CFrame.Angles(0, math.rad(spec.yaw), 0)
	model:PivotTo(destination * housing.CFrame:Inverse() * model:GetPivot())
	model.Parent = screens
end
local ceiling = architecture.Ceiling_RemoveForLayoutView
for name, position in {
	Entrance = Vector3.new(0, 14, 78),
	Court = Vector3.new(0, 14, 18),
	WestGallery = Vector3.new(-79, 14, 65),
	EastGallery = Vector3.new(79, 14, 65),
	NorthGallery = Vector3.new(0, 14, -73),
} do
	local attachment = Instance.new("Attachment")
	attachment.Name = "RoomFill_" .. name
	attachment.Position = ceiling.CFrame:PointToObjectSpace(origin + position)
	attachment.Parent = ceiling
	local light = Instance.new("PointLight")
	light.Name = "SoftRoomFill"
	light.Color = Color3.fromRGB(170, 150, 158)
	light.Brightness = name == "Entrance" and 0.55 or 0.45
	light.Range = 48
	light.Shadows = false
	light.Parent = attachment
end
Lighting.Ambient = Color3.fromRGB(96, 83, 91)
Lighting.OutdoorAmbient = Color3.fromRGB(28, 25, 33)
Lighting.ExposureCompensation = 0.35
Lighting.FogStart = 22
Lighting.FogEnd = 190
Lighting.FogColor = Color3.fromRGB(34, 26, 32)
local grade = Lighting:FindFirstChild("SignalMaze_Grade")
if grade and grade:IsA("ColorCorrectionEffect") then grade.Contrast = 0.05 end
root:SetAttribute("BuildVersion", 2)
root:SetAttribute("Footprint", "Approximately 224 x 224 studs")
root:SetAttribute("FloorAreaMultiplier", 4)
root:SetAttribute("Design", "Expanded signal court, west and east galleries, north gallery, receiver chamber, connecting loops")
root:SetAttribute("WalkableSampleCount", nil)
root:SetAttribute("UnreachableSampleCount", nil)
local counts = {parts = 0, bones = 0, lights = 0, screens = #screens:GetChildren()}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then counts.parts += 1 end
	if d:IsA("Bone") then counts.bones += 1 end
	if d:IsA("Light") then counts.lights += 1 end
end
root:SetAttribute("PartCount", counts.parts)
root:SetAttribute("ScreenCount", counts.screens)
root:SetAttribute("LightCount", counts.lights)
workspace.CurrentCamera.CFrame = CFrame.lookAt(origin + Vector3.new(0, 6, 98), origin + Vector3.new(-1, 7, 32))
workspace.CurrentCamera.Focus = CFrame.new(origin + Vector3.new(0, 6, 60))
ChangeHistoryService:SetWaypoint("Expand Signal Maze")
return game:GetService("HttpService"):JSONEncode(counts)
