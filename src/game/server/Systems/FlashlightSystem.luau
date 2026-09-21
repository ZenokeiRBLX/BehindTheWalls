local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Server"))

local FlashlightSystem = {}

local ASSETS_WAIT = 30
local RAGDOLL_ATTRIBUTE = "Ragdolled"
local VISIBLE_ATTRIBUTE = "FirstPersonVisible"
local GRIP_ATTACHMENT_SUFFIX = "GripAttachment$"
local STATE_EQUIPPING = "Equipping"
local STATE_ON = "On"
local STATE_UNEQUIPPING = "Unequipping"

type Session = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	handle: Instance,
	handlePart: BasePart,
	equipTrack: AnimationTrack?,
	held: boolean,
	closing: boolean,
	connections: { RBXScriptConnection },
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local sessions: { [Player]: Session } = {}
local lastToggle: { [Player]: number } = {}
local disconnectToggle: (() -> ())? = nil
local assetsFolder: Instance? = nil
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function findAssets(): Instance?
	if assetsFolder then
		return assetsFolder
	end
	assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	return assetsFolder
end

local function isAssetFolder(instance: Instance): boolean
	if instance.Name ~= Config.Flashlight.AssetFolder then
		return false
	end
	return instance:FindFirstChild(Config.Flashlight.ServerFolder) ~= nil
		or instance:FindFirstChild(Config.Flashlight.ClientFolder) ~= nil
end

local function findAssetFolder(): Instance?
	local assets = findAssets()
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

local function searchRoots(): { Instance }
	local roots = {}
	local folder = findAssetFolder()
	if folder then
		local serverFolder = folder:FindFirstChild(Config.Flashlight.ServerFolder)
		if serverFolder then
			table.insert(roots, serverFolder)
		end
		table.insert(roots, folder)
	end
	local assets = findAssets()
	if assets then
		table.insert(roots, assets)
	end
	return roots
end

local function findIn(root: Instance, className: string, name: string?): Instance?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA(className) and (name == nil or descendant.Name == name) then
			return descendant
		end
	end
	return nil
end

local function findAsset(name: string, className: string): Instance?
	for _, root in searchRoots() do
		local found = findIn(root, className, name)
		if found then
			return found
		end
	end
	return nil
end

local function findHandleTemplate(): Instance?
	local folder = findAssetFolder()
	local serverFolder = if folder then folder:FindFirstChild(Config.Flashlight.ServerFolder) else nil
	if serverFolder then
		return findIn(serverFolder, "Model", Config.Flashlight.ItemName)
			or findIn(serverFolder, "BasePart", Config.Flashlight.ItemName)
			or findIn(serverFolder, "BasePart", Config.Flashlight.HandleName)
			or findIn(serverFolder, "Model")
			or findIn(serverFolder, "BasePart")
	end
	return findAsset(Config.Flashlight.ItemName, "Model") or findAsset(Config.Flashlight.ItemName, "BasePart")
end

local function resolveAnimation(name: string, assetId: string): Animation?
	local found = findAsset(name, "Animation")
	if found then
		return found :: Animation
	end
	if assetId ~= "" then
		local animation = Instance.new("Animation")
		animation.Name = name
		animation.AnimationId = assetId
		return animation
	end
	warnOnce("anim:" .. name, ("FlashlightSystem: no Animation named %s under ReplicatedStorage.Assets and no id in Config.Flashlight.Animations"):format(name))
	return nil
end

local function toVector(values: { number }): Vector3
	return Vector3.new(values[1] or 0, values[2] or 0, values[3] or 0)
end

local function gripOffset(): CFrame
	local grip = Config.Flashlight.Grip
	local rotation = grip.RotationDegrees
	return CFrame.new(toVector(grip.Position))
		* CFrame.Angles(math.rad(rotation[1] or 0), math.rad(rotation[2] or 0), math.rad(rotation[3] or 0))
end

local function buildHandle(): BasePart
	local settings = Config.Flashlight.Handle
	local part = Instance.new("Part")
	part.Name = Config.Flashlight.ItemName
	part.Size = toVector(settings.Size)
	part.Color = settings.Color
	part.Material = settings.Material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "LightAttachment"
	attachment.CFrame = CFrame.new(0, 0, -part.Size.Z / 2)
	attachment.Parent = part

	local lightSettings = Config.Flashlight.Light
	local light = Instance.new("SpotLight")
	light.Name = "Light"
	light.Face = Enum.NormalId.Front
	light.Angle = lightSettings.Angle
	light.Range = lightSettings.Range
	light.Brightness = lightSettings.Brightness
	light.Color = lightSettings.Color
	light.Shadows = lightSettings.Shadows
	light.Enabled = false
	light.Parent = attachment

	return part
end

local function cloneHandle(): (Instance?, BasePart?)
	local template = findHandleTemplate()
	if template then
		local handle = template:Clone()
		local handlePart: BasePart? = nil
		if handle:IsA("BasePart") then
			handlePart = handle
		elseif handle:IsA("Model") then
			local named = handle:FindFirstChild(Config.Flashlight.HandleName, true)
			handlePart = handle.PrimaryPart
				or (if named and named:IsA("BasePart") then named else nil)
				or handle:FindFirstChildWhichIsA("BasePart", true)
		end
		if handlePart then
			return handle, handlePart
		end
		handle:Destroy()
		warnOnce("handle", "FlashlightSystem: the Flashlight asset has no BasePart to grip, using a generated handle")
	end
	local built = buildHandle()
	return built, built
end

local function markVisible(handle: Instance)
	if handle:IsA("BasePart") then
		handle:SetAttribute(VISIBLE_ATTRIBUTE, true)
	end
	for _, descendant in handle:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute(VISIBLE_ATTRIBUTE, true)
		end
	end
end

local function preparePart(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function setHandlePhysics(handle: Instance)
	preparePart(handle)
	for _, descendant in handle:GetDescendants() do
		preparePart(descendant)
	end
end

local function isToggleable(instance: Instance): boolean
	return instance:IsA("Light") or instance:IsA("Beam") or instance:IsA("ParticleEmitter") or instance:IsA("LayerCollector")
end

local function setHandleLights(handle: Instance, enabled: boolean)
	for _, descendant in handle:GetDescendants() do
		if isToggleable(descendant) then
			(descendant :: any).Enabled = enabled
		end
	end
end

local function findGripAttachment(hand: BasePart): Attachment?
	for _, child in hand:GetChildren() do
		if child:IsA("Attachment") and child.Name:match(GRIP_ATTACHMENT_SUFFIX) then
			return child
		end
	end
	return nil
end

local function attachHandle(hand: BasePart, handle: Instance, handlePart: BasePart)
	local authored = handle:FindFirstChildWhichIsA("Motor6D", true)
	local motor: Motor6D
	if authored and (authored.Part1 == nil or authored.Part1 == handlePart) then
		motor = authored
		motor.Name = Config.Flashlight.GripName
		motor.Part0 = hand
		motor.Part1 = handlePart
	else
		motor = Instance.new("Motor6D")
		motor.Name = Config.Flashlight.GripName
		motor.Part0 = hand
		motor.Part1 = handlePart
		local grip = findGripAttachment(hand)
		motor.C0 = if grip then grip.CFrame else CFrame.identity
		local handleGrip = findGripAttachment(handlePart)
		motor.C1 = if handleGrip then handleGrip.CFrame else gripOffset()
	end
	local target = hand.CFrame * motor.C0 * motor.C1:Inverse()
	if handle:IsA("Model") then
		handle:PivotTo(target * handlePart.CFrame:Inverse() * handle:GetPivot())
	else
		handlePart.CFrame = target
	end
	handle.Parent = hand.Parent
	motor.Parent = hand
end

local function playClick(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local audio = Config.Flashlight.Audio
	local template = SoundService:FindFirstChild(audio.ClickName, true)
	if not template or not template:IsA("Sound") then
		local folder = findAssetFolder()
		template = if folder then findIn(folder, "Sound", audio.AssetClickName) or findIn(folder, "Sound") else nil
	end
	if not template or not template:IsA("Sound") then
		warnOnce("click", ("FlashlightSystem: no Sound named %s in SoundService or %s in the flashlight assets"):format(audio.ClickName, audio.AssetClickName))
		return
	end
	local sound = template:Clone()
	sound.Volume *= audio.ClickVolumeScale
	sound.Parent = root
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, audio.ClickLifetime)
end

local function getAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator :: Animator
end

local function setState(session: Session, state: string?)
	if session.character.Parent then
		session.character:SetAttribute(Config.Flashlight.StateAttribute, state)
	end
end

local function hold(session: Session)
	if session.held or session.closing then
		return
	end
	session.held = true
	local track = session.equipTrack
	if track then
		track:AdjustSpeed(0)
	end
	setHandleLights(session.handle, true)
	setState(session, STATE_ON)
	playClick(session.character)
end

local function playEquip(session: Session)
	local settings = Config.Flashlight.Animations
	local animation = resolveAnimation(settings.EquipName, settings.EquipId)
	if not animation then
		hold(session)
		return
	end
	local track = getAnimator(session.humanoid):LoadAnimation(animation)
	track.Priority = settings.Priority
	track.Looped = false
	session.equipTrack = track

	table.insert(session.connections, track:GetMarkerReachedSignal(settings.HoldMarker):Connect(function()
		hold(session)
	end))
	table.insert(session.connections, track.Stopped:Connect(function()
		if session.closing or session.held then
			return
		end
		track:Play(0)
		track:AdjustSpeed(0)
		track.TimePosition = math.max(track.Length - settings.HoldMargin, 0)
		hold(session)
	end))
	track:Play(settings.FadeSeconds)

	task.spawn(function()
		local deadline = os.clock() + settings.LoadTimeout
		while track.Length <= 0 and os.clock() < deadline and not session.closing do
			task.wait(0.05)
		end
		if session.closing or session.held or not track.IsPlaying then
			return
		end
		local remaining = math.max(track.Length - track.TimePosition - settings.HoldMargin, 0)
		task.wait(remaining)
		if not session.closing and not session.held and track.IsPlaying then
			hold(session)
		end
	end)
end

local function playUnequip(session: Session)
	local settings = Config.Flashlight.Animations
	local animation = resolveAnimation(settings.UnequipName, settings.UnequipId)
	if not animation or session.humanoid.Health <= 0 then
		return
	end
	local track = getAnimator(session.humanoid):LoadAnimation(animation)
	track.Priority = settings.Priority
	track.Looped = false
	track:Play(settings.FadeSeconds)
	track:AdjustSpeed(settings.UnequipSpeed)
	track.Stopped:Once(function()
		track:Destroy()
	end)
end

local function endSession(player: Player, animate: boolean)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	session.closing = true
	for _, connection in session.connections do
		connection:Disconnect()
	end
	table.clear(session.connections)
	local wasOn = session.held
	if session.equipTrack then
		session.equipTrack:Stop(Config.Flashlight.Animations.FadeSeconds)
		session.equipTrack:Destroy()
		session.equipTrack = nil
	end
	local hand = session.character:FindFirstChild(Config.Flashlight.HandName)
	if hand then
		local grip = hand:FindFirstChild(Config.Flashlight.GripName)
		if grip then
			grip:Destroy()
		end
	end
	session.handle:Destroy()
	if animate and session.character.Parent then
		setState(session, STATE_UNEQUIPPING)
		if wasOn then
			playClick(session.character)
		end
		playUnequip(session)
	end
	setState(session, nil)
end

local function beginSession(player: Player, character: Model, humanoid: Humanoid): boolean
	local hand = character:FindFirstChild(Config.Flashlight.HandName)
	if not hand or not hand:IsA("BasePart") then
		warnOnce("hand", "FlashlightSystem: character has no " .. Config.Flashlight.HandName .. " part, flashlight needs an R15 rig")
		return false
	end
	local handle, handlePart = cloneHandle()
	if not handle or not handlePart then
		return false
	end
	setHandlePhysics(handle)
	setHandleLights(handle, false)
	markVisible(handle)
	attachHandle(hand, handle, handlePart)

	local session: Session = {
		player = player,
		character = character,
		humanoid = humanoid,
		handle = handle,
		handlePart = handlePart,
		equipTrack = nil,
		held = false,
		closing = false,
		connections = {},
	}
	sessions[player] = session
	setState(session, STATE_EQUIPPING)

	table.insert(session.connections, humanoid.Died:Connect(function()
		endSession(player, false)
	end))
	table.insert(session.connections, character:GetAttributeChangedSignal(RAGDOLL_ATTRIBUTE):Connect(function()
		if character:GetAttribute(RAGDOLL_ATTRIBUTE) then
			endSession(player, false)
		end
	end))
	table.insert(session.connections, handle.AncestryChanged:Connect(function()
		if not handle:IsDescendantOf(character) then
			endSession(player, false)
		end
	end))

	playEquip(session)
	return true
end

local function canToggle(player: Player): (Model?, Humanoid?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	if character:GetAttribute(RAGDOLL_ATTRIBUTE) then
		return nil, nil
	end
	return character, humanoid
end

local function onToggle(player: Player, wanted: boolean)
	local now = os.clock()
	local last = lastToggle[player]
	if last and now - last < Config.Flashlight.ToggleCooldown then
		return
	end
	lastToggle[player] = now

	local session = sessions[player]
	if wanted then
		if session then
			return
		end
		local character, humanoid = canToggle(player)
		if not character or not humanoid then
			return
		end
		beginSession(player, character, humanoid)
	else
		if not session then
			return
		end
		endSession(player, true)
	end
end

function FlashlightSystem.isOn(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.held
end

function FlashlightSystem.turnOff(player: Player)
	endSession(player, true)
end

local function onPlayerRemoving(player: Player)
	endSession(player, false)
	lastToggle[player] = nil
	local list = playerConnections[player]
	if list then
		playerConnections[player] = nil
		for _, connection in list do
			connection:Disconnect()
		end
	end
end

local function onPlayerAdded(player: Player)
	local list = {}
	playerConnections[player] = list
	table.insert(list, player.CharacterRemoving:Connect(function()
		endSession(player, false)
	end))
end

function FlashlightSystem.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		assetsFolder = ReplicatedStorage:WaitForChild("Assets", ASSETS_WAIT)
		if not assetsFolder then
			warnOnce("assets", "FlashlightSystem: ReplicatedStorage.Assets not found, using generated flashlight assets")
		end
	end)

	disconnectToggle = Blink.FlashlightToggle.On(onToggle)
	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

function FlashlightSystem.stop()
	if not isStarted then
		return
	end
	isStarted = false
	if disconnectToggle then
		disconnectToggle()
		disconnectToggle = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for player in playerConnections do
		onPlayerRemoving(player)
	end
	for player in sessions do
		endSession(player, false)
	end
end

return FlashlightSystem
