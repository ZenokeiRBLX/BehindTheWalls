local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))
local FirstPersonCameraController = require(script.Parent:WaitForChild("FirstPersonCameraController"))

local FlashlightController = {}

local ACTION_NAME = "ToggleFlashlight"
local RENDER_BIND = "FlashlightView"
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local HANDLE_ATTRIBUTE = "FlashlightHandle"
local STATE_ON = "On"
local STATE_EQUIPPING = "Equipping"

type View = {
	item: BasePart?,
	node: BasePart?,
	offset: Vector3Value?,
	hiding: boolean,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local hiddenHandleParts: { BasePart } = {}
local view: View? = nil
local lastPress = 0
local renderBound = false
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

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

local function findClientPart(name: string): BasePart?
	local folder = findAssetFolder()
	local clientFolder = if folder then folder:FindFirstChild(Config.Flashlight.ClientFolder) else nil
	if not clientFolder then
		warnOnce("clientFolder", ("FlashlightController: no %s.%s folder found under ReplicatedStorage"):format(Config.Flashlight.AssetFolder, Config.Flashlight.ClientFolder))
		return nil
	end
	local found = clientFolder:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found
	end
	warnOnce("part:" .. name, ("FlashlightController: no BasePart named %s in the %s folder"):format(name, Config.Flashlight.ClientFolder))
	return nil
end

local function prepareLocalPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

local function buildFallbackNode(): BasePart
	local node = Instance.new("Part")
	node.Name = Config.Flashlight.Local.NodeName
	node.Size = Vector3.new(0.2, 0.2, 0.2)
	node.Transparency = 1
	local attachment = Instance.new("Attachment")
	attachment.Name = "Attachment"
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
	light.Enabled = false
	light.Parent = attachment
	return node
end

local function setEnabled(root: Instance, enabled: boolean)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Light") or descendant:IsA("Beam") or descendant:IsA("ParticleEmitter") then
			(descendant :: any).Enabled = enabled
		end
	end
end

local function findOnUi(item: BasePart): Instance?
	local settings = Config.Flashlight.Local
	local onFx = item:FindFirstChild(settings.OnFxName, true)
	local onUi = if onFx then onFx:FindFirstChild(settings.OnUiName, true) else item:FindFirstChild(settings.OnUiName, true)
	return onUi
end

local function setOnUi(item: BasePart, enabled: boolean)
	local onUi = findOnUi(item)
	if onUi and (onUi:IsA("LayerCollector") or onUi:IsA("Light") or onUi:IsA("Beam") or onUi:IsA("ParticleEmitter")) then
		(onUi :: any).Enabled = enabled
	end
end

local function playItemSound(item: BasePart)
	local sound = item:FindFirstChild(Config.Flashlight.Local.SoundName, true)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

local function findHud(): GuiObject?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local current: Instance? = playerGui
	for _, name in Config.Flashlight.Local.HudPath do
		current = if current then current:FindFirstChild(name) else nil
	end
	return if current and current:IsA("GuiObject") then current else nil
end

local function tweenHud(shown: boolean)
	local hud = findHud()
	if not hud then
		return
	end
	local settings = Config.Flashlight.Local
	local seconds = if shown then settings.HudShowSeconds else settings.HudHideSeconds
	local goal: { [string]: any } = {}
	if hud:IsA("ImageLabel") or hud:IsA("ImageButton") then
		goal.ImageTransparency = if shown then 0 else 1
	else
		goal.BackgroundTransparency = if shown then 0 else 1
	end
	TweenService:Create(hud, TweenInfo.new(seconds, Enum.EasingStyle.Quad), goal):Play()
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

local function updateView()
	for _, part in hiddenHandleParts do
		part.LocalTransparencyModifier = 1
	end
	local current = view
	local camera = Workspace.CurrentCamera
	if not current or not camera then
		return
	end
	local settings = Config.Flashlight.Local
	local item = current.item
	if item and item.Parent then
		local offset = if current.offset then current.offset.Value else toVector(settings.ShownOffset)
		item.CFrame = camera.CFrame * CFrame.new(offset)
	end
	local node = current.node
	if node and node.Parent then
		local target = camera.CFrame * CFrame.new(toVector(settings.NodeOffset))
		TweenService:Create(node, TweenInfo.new(settings.NodeTweenSeconds, Enum.EasingStyle.Back), { CFrame = target }):Play()
	end
end

local function bindRender()
	if renderBound then
		return
	end
	renderBound = true
	RunService:BindToRenderStep(RENDER_BIND, Enum.RenderPriority.Camera.Value + 2, updateView)
end

local function releaseRenderIfIdle()
	if view == nil and #hiddenHandleParts == 0 then
		unbindRender()
	end
end

local function showView()
	if view then
		if view.hiding then
			local stale = view
			view = nil
			if stale.item then
				stale.item:Destroy()
			end
			if stale.node then
				stale.node:Destroy()
			end
		else
			return
		end
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local settings = Config.Flashlight.Local

	local itemTemplate = findClientPart(settings.ItemName)
	local nodeTemplate = findClientPart(settings.NodeName)
	local item = if itemTemplate then itemTemplate:Clone() else nil
	local node = if nodeTemplate then nodeTemplate:Clone() else buildFallbackNode()

	local offset: Vector3Value? = nil
	if item then
		prepareLocalPart(item)
		local found = item:FindFirstChild(settings.OffsetValueName)
		if found and found:IsA("Vector3Value") then
			offset = found
		else
			offset = Instance.new("Vector3Value")
			offset.Name = settings.OffsetValueName
			offset.Parent = item
		end
		offset.Value = toVector(settings.HiddenOffset)
		item.CFrame = camera.CFrame * CFrame.new(offset.Value)
		item.Parent = camera
	end

	prepareLocalPart(node)
	node.CFrame = camera.CFrame * CFrame.new(toVector(settings.NodeOffset))
	node.Parent = camera

	view = {
		item = item,
		node = node,
		offset = offset,
		hiding = false,
	}
	bindRender()

	if item and offset then
		TweenService:Create(offset, TweenInfo.new(settings.ShowSeconds, Enum.EasingStyle.Back), { Value = toVector(settings.ShownOffset) }):Play()
		setOnUi(item, true)
		playItemSound(item)
	end
	setEnabled(node, true)
	tweenHud(true)
end

local function hideView()
	local current = view
	if not current or current.hiding then
		return
	end
	current.hiding = true
	local settings = Config.Flashlight.Local
	tweenHud(false)

	if current.node then
		current.node:Destroy()
		current.node = nil
	end

	local item = current.item
	local function finish()
		if view == current then
			view = nil
		end
		if item then
			item:Destroy()
		end
		releaseRenderIfIdle()
	end

	if item and item.Parent then
		setOnUi(item, false)
		playItemSound(item)
		local offset = current.offset
		if offset then
			local tween = TweenService:Create(offset, TweenInfo.new(settings.HideSeconds), { Value = toVector(settings.HiddenOffset) })
			tween.Completed:Once(finish)
			tween:Play()
			return
		end
	end
	finish()
end

local function hideHandlePart(part: Instance)
	if part:IsA("BasePart") then
		part.LocalTransparencyModifier = 1
		if not table.find(hiddenHandleParts, part) then
			table.insert(hiddenHandleParts, part)
		end
	elseif part:IsA("Light") or part:IsA("Beam") or part:IsA("ParticleEmitter") or part:IsA("LayerCollector") then
		(part :: any).Enabled = false
		table.insert(characterConnections, part:GetPropertyChangedSignal("Enabled"):Connect(function()
			if (part :: any).Enabled then
				(part :: any).Enabled = false
			end
		end))
	end
end

local function hideServerHandle(handle: Instance)
	hideHandlePart(handle)
	for _, descendant in handle:GetDescendants() do
		hideHandlePart(descendant)
	end
	table.insert(characterConnections, handle.DescendantAdded:Connect(function(descendant)
		task.defer(hideHandlePart, descendant)
	end))
	table.insert(characterConnections, handle.AncestryChanged:Connect(function()
		if handle.Parent then
			return
		end
		for index = #hiddenHandleParts, 1, -1 do
			local part = hiddenHandleParts[index]
			if part == handle or part:IsDescendantOf(handle) then
				table.remove(hiddenHandleParts, index)
			end
		end
		releaseRenderIfIdle()
	end))
	bindRender()
end

local function refreshState(character: Model)
	local state = character:GetAttribute(stateAttribute())
	if state == STATE_EQUIPPING or state == STATE_ON then
		showView()
	else
		hideView()
	end
end

local function watchCharacter(character: Model?)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	table.clear(hiddenHandleParts)
	hideView()
	if not character then
		releaseRenderIfIdle()
		return
	end
	table.insert(characterConnections, character:GetAttributeChangedSignal(stateAttribute()):Connect(function()
		refreshState(character)
	end))
	table.insert(characterConnections, character.DescendantAdded:Connect(function(descendant)
		if descendant:GetAttribute(HANDLE_ATTRIBUTE) then
			task.defer(hideServerHandle, descendant)
		end
	end))
	for _, descendant in character:GetDescendants() do
		if descendant:GetAttribute(HANDLE_ATTRIBUTE) then
			hideServerHandle(descendant)
		end
	end
	refreshState(character)
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

	local player = Players.LocalPlayer
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		watchCharacter(character)
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		watchCharacter(nil)
	end))
	if player.Character then
		watchCharacter(player.Character)
	end
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
	watchCharacter(nil)
	unbindRender()
end

return FlashlightController
