local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))
local FirstPersonCameraController = require(script.Parent:WaitForChild("FirstPersonCameraController"))

local FlashlightController = {}

local ACTION_NAME = "ToggleFlashlight"
local RENDER_BIND = "FlashlightBeam"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local STATE_ON = "On"
local STATE_EQUIPPING = "Equipping"
local MAX_DELTA_TIME = 0.1

type Beam = {
	character: Model,
	node: BasePart,
	view: CFrame?,
	connections: { RBXScriptConnection },
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local characterConnections: { [Model]: { RBXScriptConnection } } = {}
local beams: { [Model]: Beam } = {}
local lastPress = 0
local renderBound = false

local function stateAttribute(): string
	return Config.Flashlight.StateAttribute
end

local function toVector(values: { number }): Vector3
	return Vector3.new(values[1] or 0, values[2] or 0, values[3] or 0)
end

local function isAssetFolder(instance: Instance): boolean
	if instance.Name ~= Config.Flashlight.AssetFolder then
		return false
	end
	return instance:FindFirstChild(Config.Flashlight.ServerFolder) ~= nil
		or instance:FindFirstChild(Config.Flashlight.ClientFolder) ~= nil
end

local function findAssetFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		if isAssetFolder(assets) then
			return assets
		end
		for _, descendant in assets:GetDescendants() do
			if isAssetFolder(descendant) then
				return descendant
			end
		end
	end
	for _, descendant in ReplicatedStorage:GetDescendants() do
		if isAssetFolder(descendant) then
			return descendant
		end
	end
	return nil
end

local function hasLight(part: Instance): boolean
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("Light") then
			return true
		end
	end
	return false
end

local function findNodeTemplate(): BasePart?
	local roots: { Instance } = {}
	local folder = findAssetFolder()
	local clientFolder = if folder then folder:FindFirstChild(Config.Flashlight.ClientFolder) else nil
	if clientFolder then
		table.insert(roots, clientFolder)
	end
	if folder then
		table.insert(roots, folder)
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		table.insert(roots, assets)
	end
	for _, root in roots do
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Name == Config.Flashlight.NodeName then
				return descendant
			end
		end
	end
	if clientFolder then
		for _, descendant in clientFolder:GetDescendants() do
			if descendant:IsA("BasePart") and hasLight(descendant) then
				return descendant
			end
		end
	end
	return nil
end

local function buildNode(): BasePart
	local template = findNodeTemplate()
	local node: BasePart
	if template then
		node = template:Clone()
	else
		node = Instance.new("Part")
		node.Name = Config.Flashlight.NodeName
		node.Size = Vector3.new(0.2, 0.2, 0.2)
		local attachment = Instance.new("Attachment")
		attachment.Name = "LightAttachment"
		attachment.Parent = node
		local settings = Config.Flashlight.Light
		local light = Instance.new("SpotLight")
		light.Name = "Light"
		light.Face = Enum.NormalId.Front
		light.Angle = settings.Angle
		light.Range = settings.Range
		light.Brightness = settings.Brightness
		light.Color = settings.Color
		light.Shadows = settings.Shadows
		light.Parent = attachment
	end
	node.Anchored = true
	node.CanCollide = false
	node.CanQuery = false
	node.CanTouch = false
	node.Massless = true
	node.CastShadow = false
	node.Transparency = 1
	for _, descendant in node:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
		elseif descendant:IsA("Light") or descendant:IsA("Beam") or descendant:IsA("ParticleEmitter") then
			(descendant :: any).Enabled = true
		end
	end
	return node
end

local function suppressHandleLights(beam: Beam)
	local itemName = Config.Flashlight.ItemName
	local function suppress(light: Instance)
		if not (light:IsA("Light") or light:IsA("Beam")) or not light:FindFirstAncestor(itemName) then
			return
		end
		(light :: any).Enabled = false
		table.insert(beam.connections, light:GetPropertyChangedSignal("Enabled"):Connect(function()
			if (light :: any).Enabled then
				(light :: any).Enabled = false
			end
		end))
	end
	for _, descendant in beam.character:GetDescendants() do
		suppress(descendant)
	end
	table.insert(beam.connections, beam.character.DescendantAdded:Connect(function(descendant)
		task.defer(suppress, descendant)
	end))
end

local function targetCFrame(): CFrame?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	return camera.CFrame * CFrame.new(toVector(Config.Flashlight.Local.Offset))
end

local function unbindRender()
	if not renderBound then
		return
	end
	renderBound = false
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_BIND)
	end)
end

local function updateBeams(dt: number)
	dt = math.clamp(dt, 0, MAX_DELTA_TIME)
	for _, beam in beams do
		local target = targetCFrame()
		if not target then
			continue
		end
		local smoothing = Config.Flashlight.Local.Smoothing
		local current = beam.view
		local view = if current then current:Lerp(target, 1 - math.exp(-smoothing * dt)) else target
		beam.view = view
		beam.node.CFrame = view
	end
end

local function bindRender()
	if renderBound then
		return
	end
	renderBound = true
	RunService:BindToRenderStep(RENDER_BIND, Enum.RenderPriority.Camera.Value + 2, updateBeams)
end

local function removeBeam(character: Model)
	local beam = beams[character]
	if not beam then
		return
	end
	beams[character] = nil
	for _, connection in beam.connections do
		connection:Disconnect()
	end
	beam.node:Destroy()
	if next(beams) == nil then
		unbindRender()
	end
end

local function addBeam(character: Model)
	if beams[character] then
		return
	end
	local beam: Beam = {
		character = character,
		node = buildNode(),
		view = nil,
		connections = {},
	}
	beams[character] = beam
	local target = targetCFrame()
	if target then
		beam.view = target
		beam.node.CFrame = target
	end
	beam.node.Parent = Workspace.CurrentCamera or Workspace
	suppressHandleLights(beam)
	bindRender()
end

local function refreshCharacter(character: Model)
	if character ~= Players.LocalPlayer.Character then
		return
	end
	if character:GetAttribute(stateAttribute()) == STATE_ON then
		addBeam(character)
	else
		removeBeam(character)
	end
end

local function untrackCharacter(character: Model)
	local list = characterConnections[character]
	if list then
		characterConnections[character] = nil
		for _, connection in list do
			connection:Disconnect()
		end
	end
	removeBeam(character)
end

local function trackCharacter(character: Model)
	if characterConnections[character] then
		return
	end
	local list = {}
	characterConnections[character] = list
	table.insert(list, character:GetAttributeChangedSignal(stateAttribute()):Connect(function()
		refreshCharacter(character)
	end))
	table.insert(list, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(Workspace) then
			untrackCharacter(character)
		end
	end))
	refreshCharacter(character)
end

local function onPlayerRemoving(player: Player)
	local list = playerConnections[player]
	if list then
		playerConnections[player] = nil
		for _, connection in list do
			connection:Disconnect()
		end
	end
	if player.Character then
		untrackCharacter(player.Character)
	end
end

local function onPlayerAdded(player: Player)
	local list = {}
	playerConnections[player] = list
	if player.Character then
		trackCharacter(player.Character)
	end
	table.insert(list, player.CharacterAdded:Connect(trackCharacter))
	table.insert(list, player.CharacterRemoving:Connect(untrackCharacter))
end

local function isHeld(character: Model): boolean
	local state = character:GetAttribute(stateAttribute())
	return state == STATE_ON or state == STATE_EQUIPPING
end

local function canToggle(): Model?
	if not FirstPersonCameraController.isEnabled() then
		return nil
	end
	local character = Players.LocalPlayer.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	if character:GetAttribute(RAGDOLL_ATTRIBUTE) then
		return nil
	end
	return character
end

function FlashlightController.isOn(): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil and character:GetAttribute(stateAttribute()) == STATE_ON
end

function FlashlightController.toggle()
	local now = os.clock()
	if now - lastPress < Config.Flashlight.ToggleCooldown then
		return
	end
	local character = canToggle()
	if not character then
		return
	end
	lastPress = now
	Blink.FlashlightToggle.Fire(not isHeld(character))
end

local function onAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	FlashlightController.toggle()
	return Enum.ContextActionResult.Sink
end

function FlashlightController.start()
	if isStarted then
		return
	end
	isStarted = true

	ContextActionService:BindAction(ACTION_NAME, onAction, true, table.unpack(Config.Flashlight.ToggleKeys))
	ContextActionService:SetTitle(ACTION_NAME, Config.Flashlight.TouchButtonTitle)

	onPlayerAdded(Players.LocalPlayer)
end

function FlashlightController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	ContextActionService:UnbindAction(ACTION_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for player in playerConnections do
		onPlayerRemoving(player)
	end
	for character in characterConnections do
		untrackCharacter(character)
	end
	unbindRender()
end

return FlashlightController
