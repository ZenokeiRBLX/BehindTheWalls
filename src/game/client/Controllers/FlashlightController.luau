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
local HOLD_TIME_ATTRIBUTE = "FlashlightHoldTime"
local EQUIP_ID_ATTRIBUTE = "FlashlightEquipId"
local STATE_ON = "On"
local STATE_EQUIPPING = "Equipping"

type View = {
	item: BasePart?,
	node: BasePart?,
	hitLight: PointLight?,
	hitPart: BasePart?,
	aim: CFrame?,
}

type ArmJoint = {
	target: Instance,
	original: CFrame,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local hiddenHandleParts: { BasePart } = {}
local view: View? = nil
local armJoints: { ArmJoint } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local heldCharacters: { [Model]: { RBXScriptConnection } } = {}
local snapTokens: { [Model]: number } = {}
local lastPress = 0
local renderBound = false
local warned: { [string]: boolean } = {}
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true

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

local function toAngles(values: { number }): CFrame
	return CFrame.Angles(math.rad(values[1] or 0), math.rad(values[2] or 0), math.rad(values[3] or 0))
end

local function damp(current: CFrame, target: CFrame, speed: number, dt: number): CFrame
	return current:Lerp(target, 1 - math.exp(-speed * dt))
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

local function prepareLocalPart(part: BasePart, anchored: boolean, invisible: boolean)
	part.Anchored = anchored
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	if invisible then
		part.Transparency = 1
	end
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = false
			if invisible then
				descendant.Transparency = 1
			end
		elseif invisible and (descendant:IsA("Decal") or descendant:IsA("Texture")) then
			descendant.Transparency = 1
		end
	end
end

local function scaleItem(item: BasePart, scale: number)
	if scale <= 0 or math.abs(scale - 1) < 0.001 then
		return
	end
	local origin = item.CFrame
	item.Size *= scale
	for _, descendant in item:GetDescendants() do
		if descendant:IsA("BasePart") then
			local offset = origin:ToObjectSpace(descendant.CFrame)
			descendant.Size *= scale
			descendant.CFrame = origin * CFrame.new(offset.Position * scale) * (offset - offset.Position)
		elseif descendant:IsA("Attachment") then
			descendant.CFrame = CFrame.new(descendant.CFrame.Position * scale) * (descendant.CFrame - descendant.CFrame.Position)
		elseif descendant:IsA("Weld") or descendant:IsA("Motor6D") then
			descendant.C0 = CFrame.new(descendant.C0.Position * scale) * (descendant.C0 - descendant.C0.Position)
			descendant.C1 = CFrame.new(descendant.C1.Position * scale) * (descendant.C1 - descendant.C1.Position)
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

local function handAnchor(): BasePart?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	local hand = character:FindFirstChild(Config.Flashlight.HandName)
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local grip = hand:FindFirstChild(Config.Flashlight.GripName)
	if grip and grip:IsA("Motor6D") and grip.Part1 then
		return grip.Part1
	end
	return hand
end

local function buildHitLight(): (BasePart, PointLight)
	local settings = Config.Flashlight.Local.HitLight
	local part = Instance.new("Part")
	part.Name = "FlashlightHit"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Range = settings.Range
	light.Brightness = settings.Brightness
	light.Color = settings.Color
	light.Shadows = false
	light.Enabled = false
	light.Parent = part
	return part, light
end

local function applyShadowSetting(root: Instance)
	local shadows = Config.Flashlight.Local.LightShadows
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Light") then
			descendant.Shadows = shadows
		end
	end
end

local function clampPitch(direction: Vector3, fallback: Vector3): Vector3
	local settings = Config.Flashlight.Local
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.001 then
		flat = Vector3.new(fallback.X, 0, fallback.Z)
		if flat.Magnitude < 0.001 then
			flat = -Vector3.zAxis
		end
	end
	flat = flat.Unit
	local pitch = math.asin(math.clamp(direction.Y, -1, 1))
	pitch = math.clamp(pitch, math.rad(settings.PitchMinDegrees), math.rad(settings.PitchMaxDegrees))
	return flat * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
end

local function aimPoint(camera: Camera): (Vector3, RaycastResult?)
	local distance = Config.Flashlight.Local.AimDistance
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * distance
	local hit = Workspace:Raycast(origin, direction, castParams)
	return (if hit then hit.Position else origin + direction), hit
end

local function aimedFrames(camera: Camera, anchor: BasePart?): (CFrame, CFrame, RaycastResult?)
	local origin = if anchor then anchor.Position else camera.CFrame.Position
	local target, hit = aimPoint(camera)
	local direction = target - origin
	if direction.Magnitude < 0.01 then
		direction = camera.CFrame.LookVector
	end
	direction = direction.Unit
	local lightFrame = CFrame.lookAt(origin, origin + direction)
	local clamped = clampPitch(direction, camera.CFrame.LookVector)
	local itemAim = CFrame.lookAt(origin, origin + clamped)
	return itemAim, lightFrame, hit
end

local function itemFrame(aim: CFrame): CFrame
	local settings = Config.Flashlight.Local
	return aim * CFrame.new(toVector(settings.ItemOffset)) * toAngles(settings.ItemRotationDegrees)
end

local function updateHitLight(current: View, hit: RaycastResult?)
	local light = current.hitLight
	local part = current.hitPart
	if not light or not part then
		return
	end
	local settings = Config.Flashlight.Local.HitLight
	if not hit or not settings.Enabled then
		light.Enabled = false
		return
	end
	local camera = Workspace.CurrentCamera
	local distance = if camera then (hit.Position - camera.CFrame.Position).Magnitude else 0
	local fade = 1 - math.clamp((distance - settings.FadeStart) / math.max(settings.FadeEnd - settings.FadeStart, 0.001), 0, 1)
	if fade <= 0.001 then
		light.Enabled = false
		return
	end
	part.CFrame = CFrame.new(hit.Position + hit.Normal * settings.SurfaceOffset)
	light.Brightness = settings.Brightness * fade
	light.Enabled = true
end

local function updateView(dt: number)
	for _, part in hiddenHandleParts do
		part.LocalTransparencyModifier = 1
	end
	local current = view
	local camera = Workspace.CurrentCamera
	if not current or not camera then
		return
	end
	local settings = Config.Flashlight.Local
	local anchor = handAnchor()
	local itemTarget, lightFrame, hit = aimedFrames(camera, anchor)
	local aim = if current.aim and settings.AimSmoothing > 0
		then damp(current.aim, itemTarget, settings.AimSmoothing, math.min(dt, 0.1))
		else itemTarget
	current.aim = aim

	local item = current.item
	if item and item.Parent then
		item.CFrame = itemFrame(aim)
	end
	local node = current.node
	if node and node.Parent then
		local lensOffset = toVector(settings.NodeOffset)
		node.CFrame = lightFrame * CFrame.new(lensOffset)
	end
	updateHitLight(current, hit)
end

local function bindRender()
	if renderBound then
		return
	end
	renderBound = true
	RunService:BindToRenderStep(RENDER_BIND, Enum.RenderPriority.Last.Value, updateView)
end

local function releaseRenderIfIdle()
	if view == nil and #hiddenHandleParts == 0 then
		unbindRender()
	end
end

local function restoreArms()
	for _, joint in armJoints do
		local target = joint.target
		if target:IsA("Motor6D") then
			target.C0 = joint.original
		elseif target:IsA("Attachment") then
			target.CFrame = joint.original
		end
	end
	table.clear(armJoints)
end

local function offsetArms(character: Model)
	restoreArms()
	local settings = Config.Flashlight.Local
	local offset = CFrame.new(toVector(settings.ArmOffset))
	for _, name in settings.ArmJointNames do
		local joint = character:FindFirstChild(name, true)
		if joint and joint:IsA("Motor6D") then
			table.insert(armJoints, { target = joint, original = joint.C0 })
			joint.C0 = joint.C0 * offset
		elseif joint and joint:IsA("AnimationConstraint") then
			local attachment = joint.Attachment0
			if attachment then
				table.insert(armJoints, { target = attachment, original = attachment.CFrame })
				attachment.CFrame = attachment.CFrame * offset
			end
		end
	end
end

local function findEquipTrack(character: Model): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then
		return nil
	end
	local wantedId = character:GetAttribute(EQUIP_ID_ATTRIBUTE)
	for _, track in animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and (wantedId == nil or animation.AnimationId == wantedId) then
			if wantedId ~= nil or track.Priority == Config.Flashlight.Animations.Priority then
				return track
			end
		end
	end
	return nil
end

local function snapHold(character: Model)
	local token = (snapTokens[character] or 0) + 1
	snapTokens[character] = token
	task.spawn(function()
		local deadline = os.clock() + Config.Flashlight.Animations.HoldSnapTimeout
		while snapTokens[character] == token and os.clock() < deadline do
			if character:GetAttribute(stateAttribute()) ~= STATE_ON then
				return
			end
			local holdTime = character:GetAttribute(HOLD_TIME_ATTRIBUTE)
			local track = findEquipTrack(character)
			if track and typeof(holdTime) == "number" then
				track:AdjustSpeed(0)
				track.TimePosition = holdTime
				return
			end
			task.wait(0.05)
		end
	end)
end

local function unholdCharacter(character: Model)
	local list = heldCharacters[character]
	if list then
		heldCharacters[character] = nil
		for _, connection in list do
			connection:Disconnect()
		end
	end
	snapTokens[character] = nil
end

local function holdCharacter(character: Model)
	if heldCharacters[character] then
		return
	end
	local list = {}
	heldCharacters[character] = list
	local function refresh()
		if character:GetAttribute(stateAttribute()) == STATE_ON then
			snapHold(character)
		else
			snapTokens[character] = (snapTokens[character] or 0) + 1
		end
	end
	table.insert(list, character:GetAttributeChangedSignal(stateAttribute()):Connect(refresh))
	table.insert(list, character:GetAttributeChangedSignal(HOLD_TIME_ATTRIBUTE):Connect(refresh))
	table.insert(list, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(Workspace) then
			unholdCharacter(character)
		end
	end))
	refresh()
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
		unholdCharacter(player.Character)
	end
end

local function onPlayerAdded(player: Player)
	local list = {}
	playerConnections[player] = list
	table.insert(list, player.CharacterAdded:Connect(holdCharacter))
	table.insert(list, player.CharacterRemoving:Connect(unholdCharacter))
	if player.Character then
		holdCharacter(player.Character)
	end
end

local function showView()
	if view then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local settings = Config.Flashlight.Local
	local character = Players.LocalPlayer.Character
	castParams.FilterDescendantsInstances = if character then { character, camera } else { camera }

	local itemTemplate = findClientPart(settings.ItemName)
	local nodeTemplate = findClientPart(settings.NodeName)
	local item = if itemTemplate then itemTemplate:Clone() else nil
	local node = if nodeTemplate then nodeTemplate:Clone() else buildFallbackNode()

	local anchor = handAnchor()
	local aim, lightFrame, hit = aimedFrames(camera, anchor)
	if item then
		prepareLocalPart(item, true, false)
		scaleItem(item, settings.ItemScale)
		item.CFrame = itemFrame(aim)
		item.Parent = camera
	end

	prepareLocalPart(node, true, true)
	applyShadowSetting(node)
	node.CFrame = lightFrame * CFrame.new(toVector(settings.NodeOffset))
	node.Parent = camera

	local hitPart, hitLight = buildHitLight()
	hitPart.Parent = camera

	local current: View = {
		item = item,
		node = node,
		hitLight = hitLight,
		hitPart = hitPart,
		aim = aim,
	}
	view = current
	updateHitLight(current, hit)
	bindRender()
	if character then
		offsetArms(character)
	end

	if item then
		setOnUi(item, true)
		playItemSound(item)
	end
	setEnabled(node, true)
	tweenHud(true)
end

local function hideView()
	local current = view
	if not current then
		return
	end
	view = nil
	tweenHud(false)
	restoreArms()
	if current.node then
		current.node:Destroy()
	end
	if current.hitPart then
		current.hitPart:Destroy()
	end
	local item = current.item
	if item then
		setOnUi(item, false)
		playItemSound(item)
		local sound = item:FindFirstChild(Config.Flashlight.Local.SoundName, true)
		if sound and sound:IsA("Sound") and sound.IsPlaying then
			item.Transparency = 1
			setEnabled(item, false)
			for _, descendant in item:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Transparency = 1
				end
			end
			sound.Ended:Once(function()
				item:Destroy()
			end)
			task.delay(Config.Flashlight.Audio.ClickLifetime, function()
				if item.Parent then
					item:Destroy()
				end
			end)
		else
			item:Destroy()
		end
	end
	releaseRenderIfIdle()
end

local function hideHandlePart(part: Instance)
	if part:IsA("BasePart") then
		part.LocalTransparencyModifier = 1
		part.CastShadow = false
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
	table.clear(armJoints)
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
	for _, other in Players:GetPlayers() do
		onPlayerAdded(other)
	end
	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
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
	for player in playerConnections do
		onPlayerRemoving(player)
	end
	for character in heldCharacters do
		unholdCharacter(character)
	end
	unbindRender()
end

return FlashlightController
