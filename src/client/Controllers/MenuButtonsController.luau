local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MenuButtonsController = {}

local MENU_KEYWORDS = { "shop", "index", "badges", "settings" }
local CLOSE_KEYWORDS = { "exit", "close" }
local IGNORED_SCREEN_GUIS = { PRELOADING = true, LoadingScreen = true, Intro_Screen = true, Black_Transition = true, PartyGui = true }
local PANEL_SUFFIXES = { "Frame", "_Frame", "Panel", "_Panel", "Menu", "_Menu", "" }
local HOVER_SOUND = "UI_HIGHLIGHT"
local CLICK_SOUND = "UI_CLICK"

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 236, 150)
local HOVER_TINT = 0.45
local HOVER_BACKGROUND_TINT = 0.25
local HOVER_SCALE = 1.12
local HOVER_TILT = 6
local HOVER_ICON_TILT = 12
local PRESS_SCALE = 0.9
local PRESS_TILT = -10
local PRESS_ICON_TILT = -18
local HOVER_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LEAVE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN = TweenInfo.new(0.55, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local PANEL_OPEN_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PANEL_CLOSE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local IDLE_WOBBLE_DEGREES = 2.5
local IDLE_WOBBLE_SECONDS = 2.2
local POP_IN_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_IN_STAGGER = 0.09
local POP_IN_SPIN = 28
local POP_IN_BATCH_GAP = 1

type ButtonState = {
	button: GuiButton,
	scale: UIScale,
	icon: GuiObject?,
	baseRotation: number,
	baseIconRotation: number,
	tiltDirection: number,
	baseImageColor: Color3?,
	baseIconColor: Color3?,
	baseTextColor: Color3?,
	baseBackgroundColor: Color3,
	hovered: boolean,
	pressed: boolean,
	idleResumeAt: number,
	keyword: string?,
	isCloser: boolean,
	connections: { RBXScriptConnection },
}

local isStarted = false
local bound: { [GuiButton]: ButtonState } = {}
local openPanel: GuiObject?
local watchConnections: { RBXScriptConnection } = {}
local wobbleIndex = 0
local popIndex = 0
local lastPopAt = 0

local function findKeyword(name: string, keywords: { string }): string?
	local lowered = string.lower(name)
	for _, keyword in keywords do
		if string.find(lowered, keyword, 1, true) then
			return keyword
		end
	end
	return nil
end

local function getScreenGui(instance: Instance): ScreenGui?
	local current = instance.Parent
	while current do
		if current:IsA("ScreenGui") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isIgnored(button: GuiButton): boolean
	local screenGui = getScreenGui(button)
	return screenGui == nil or IGNORED_SCREEN_GUIS[screenGui.Name] == true
end

local function ensureScale(gui: GuiObject): UIScale
	local existing = gui:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "MenuButtonScale"
	scale.Parent = gui
	return scale
end

local function tint(color: Color3, amount: number): Color3
	return color:Lerp(HIGHLIGHT_COLOR, amount)
end

local function findIcon(button: GuiButton): GuiObject?
	for _, child in button:GetChildren() do
		if child:IsA("ImageLabel") and string.find(string.lower(child.Name), "image", 1, true) then
			return child
		end
	end
	return button:FindFirstChildWhichIsA("ImageLabel")
end

local function findPanel(button: GuiButton, keyword: string): GuiObject?
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	local explicit = button:GetAttribute("Panel")
	local baseNames = if typeof(explicit) == "string"
		then { explicit }
		else { string.upper(string.sub(keyword, 1, 1)) .. string.sub(keyword, 2), keyword, string.upper(keyword) }
	for _, baseName in baseNames do
		for _, suffix in PANEL_SUFFIXES do
			local candidate = playerGui:FindFirstChild(baseName .. suffix, true)
			if candidate and candidate:IsA("GuiObject") and candidate ~= button and not candidate:IsA("GuiButton") then
				return candidate
			end
		end
	end
	return nil
end

local function findContainingPanel(button: GuiButton): GuiObject?
	local current = button.Parent
	while current and not current:IsA("ScreenGui") do
		if current:IsA("GuiObject") and current.Parent and current.Parent:IsA("ScreenGui") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function playUiSound(name: string)
	local sound = SoundService:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

local function setPanelVisible(panel: GuiObject, visible: boolean)
	local scale = ensureScale(panel)
	if visible then
		panel.Visible = true
		scale.Scale = 0.85
		TweenService:Create(scale, PANEL_OPEN_TWEEN, { Scale = 1 }):Play()
	else
		local tween = TweenService:Create(scale, PANEL_CLOSE_TWEEN, { Scale = 0.85 })
		tween.Completed:Once(function()
			if scale.Scale <= 0.86 then
				panel.Visible = false
				scale.Scale = 1
			end
		end)
		tween:Play()
	end
end

local function closePanel(panel: GuiObject)
	setPanelVisible(panel, false)
	if openPanel == panel then
		openPanel = nil
	end
end

local function togglePanel(panel: GuiObject)
	if openPanel == panel then
		closePanel(panel)
		return
	end
	if openPanel then
		setPanelVisible(openPanel, false)
	end
	setPanelVisible(panel, true)
	openPanel = panel
end

local function applyHoverLook(state: ButtonState)
	local button = state.button
	TweenService:Create(state.scale, HOVER_TWEEN, { Scale = HOVER_SCALE }):Play()
	TweenService:Create(button, HOVER_TWEEN, { Rotation = state.baseRotation + HOVER_TILT * state.tiltDirection }):Play()
	if button:IsA("ImageButton") and state.baseImageColor then
		TweenService:Create(button, HOVER_TWEEN, { ImageColor3 = tint(state.baseImageColor, HOVER_TINT) }):Play()
	end
	if button:IsA("TextButton") and state.baseTextColor then
		TweenService:Create(button, HOVER_TWEEN, { TextColor3 = tint(state.baseTextColor, HOVER_TINT) }):Play()
	end
	if button.BackgroundTransparency < 1 then
		TweenService:Create(button, HOVER_TWEEN, { BackgroundColor3 = tint(state.baseBackgroundColor, HOVER_BACKGROUND_TINT) }):Play()
	end
	local icon = state.icon
	if icon then
		TweenService:Create(icon, HOVER_TWEEN, { Rotation = state.baseIconRotation + HOVER_ICON_TILT * state.tiltDirection }):Play()
		if icon:IsA("ImageLabel") and state.baseIconColor then
			TweenService:Create(icon, HOVER_TWEEN, { ImageColor3 = tint(state.baseIconColor, HOVER_TINT) }):Play()
		end
	end
end

local function applyRestLook(state: ButtonState)
	local button = state.button
	TweenService:Create(state.scale, LEAVE_TWEEN, { Scale = 1 }):Play()
	TweenService:Create(button, LEAVE_TWEEN, { Rotation = state.baseRotation }):Play()
	if button:IsA("ImageButton") and state.baseImageColor then
		TweenService:Create(button, LEAVE_TWEEN, { ImageColor3 = state.baseImageColor }):Play()
	end
	if button:IsA("TextButton") and state.baseTextColor then
		TweenService:Create(button, LEAVE_TWEEN, { TextColor3 = state.baseTextColor }):Play()
	end
	if button.BackgroundTransparency < 1 then
		TweenService:Create(button, LEAVE_TWEEN, { BackgroundColor3 = state.baseBackgroundColor }):Play()
	end
	local icon = state.icon
	if icon then
		TweenService:Create(icon, LEAVE_TWEEN, { Rotation = state.baseIconRotation }):Play()
		if icon:IsA("ImageLabel") and state.baseIconColor then
			TweenService:Create(icon, LEAVE_TWEEN, { ImageColor3 = state.baseIconColor }):Play()
		end
	end
end

local function applyPressLook(state: ButtonState)
	TweenService:Create(state.scale, PRESS_TWEEN, { Scale = PRESS_SCALE }):Play()
	TweenService:Create(state.button, PRESS_TWEEN, { Rotation = state.baseRotation + PRESS_TILT * state.tiltDirection }):Play()
	if state.icon then
		TweenService:Create(state.icon, PRESS_TWEEN, { Rotation = state.baseIconRotation + PRESS_ICON_TILT * state.tiltDirection }):Play()
	end
end

local function applyReleaseLook(state: ButtonState)
	local hovered = state.hovered
	TweenService:Create(state.scale, RELEASE_TWEEN, { Scale = if hovered then HOVER_SCALE else 1 }):Play()
	TweenService:Create(state.button, RELEASE_TWEEN, {
		Rotation = if hovered then state.baseRotation + HOVER_TILT * state.tiltDirection else state.baseRotation,
	}):Play()
	if state.icon then
		TweenService:Create(state.icon, RELEASE_TWEEN, {
			Rotation = if hovered then state.baseIconRotation + HOVER_ICON_TILT * state.tiltDirection else state.baseIconRotation,
		}):Play()
	end
end

local function popIn(state: ButtonState)
	local now = os.clock()
	if now - lastPopAt > POP_IN_BATCH_GAP then
		popIndex = 0
	end
	lastPopAt = now
	local delay = popIndex * POP_IN_STAGGER
	popIndex += 1

	state.scale.Scale = 0
	state.button.Rotation = state.baseRotation - POP_IN_SPIN * state.tiltDirection
	state.idleResumeAt = now + delay + POP_IN_TWEEN.Time
	task.delay(delay, function()
		if not bound[state.button] then
			return
		end
		TweenService:Create(state.scale, POP_IN_TWEEN, { Scale = 1 }):Play()
		TweenService:Create(state.button, POP_IN_TWEEN, { Rotation = state.baseRotation }):Play()
	end)
end

local function startIdleWobble(state: ButtonState)
	wobbleIndex += 1
	local phase = wobbleIndex * 0.7
	task.spawn(function()
		local startTime = os.clock()
		while bound[state.button] do
			if not state.hovered and not state.pressed and os.clock() >= state.idleResumeAt then
				local wobble = math.sin((os.clock() - startTime) / IDLE_WOBBLE_SECONDS * math.pi * 2 + phase) * IDLE_WOBBLE_DEGREES
				state.button.Rotation = state.baseRotation + wobble
			end
			task.wait(0.03)
		end
	end)
end

local function unbind(button: GuiButton)
	local state = bound[button]
	if not state then
		return
	end
	bound[button] = nil
	for _, connection in state.connections do
		connection:Disconnect()
	end
end

local function onActivated(state: ButtonState)
	playUiSound(CLICK_SOUND)
	if state.isCloser then
		local panel = findContainingPanel(state.button)
		if panel then
			closePanel(panel)
		end
		return
	end
	local keyword = state.keyword
	if keyword then
		local panel = findPanel(state.button, keyword)
		if panel then
			togglePanel(panel)
		end
	end
end

local function bind(button: GuiButton, keyword: string?, isCloser: boolean)
	if bound[button] or isIgnored(button) then
		return
	end

	local icon = findIcon(button)
	local state: ButtonState = {
		button = button,
		scale = ensureScale(button),
		icon = icon,
		baseRotation = button.Rotation,
		baseIconRotation = if icon then icon.Rotation else 0,
		tiltDirection = if wobbleIndex % 2 == 0 then 1 else -1,
		baseImageColor = if button:IsA("ImageButton") then button.ImageColor3 else nil,
		baseIconColor = if icon and icon:IsA("ImageLabel") then icon.ImageColor3 else nil,
		baseTextColor = if button:IsA("TextButton") then button.TextColor3 else nil,
		baseBackgroundColor = button.BackgroundColor3,
		hovered = false,
		pressed = false,
		idleResumeAt = 0,
		keyword = keyword,
		isCloser = isCloser,
		connections = {},
	}
	bound[button] = state

	table.insert(state.connections, button.MouseEnter:Connect(function()
		state.hovered = true
		playUiSound(HOVER_SOUND)
		applyHoverLook(state)
	end))
	table.insert(state.connections, button.MouseLeave:Connect(function()
		state.hovered = false
		state.pressed = false
		state.idleResumeAt = os.clock() + 0.25
		applyRestLook(state)
	end))
	table.insert(state.connections, button.MouseButton1Down:Connect(function()
		state.pressed = true
		applyPressLook(state)
	end))
	table.insert(state.connections, button.MouseButton1Up:Connect(function()
		state.pressed = false
		applyReleaseLook(state)
	end))
	table.insert(state.connections, button.Activated:Connect(function()
		onActivated(state)
	end))
	table.insert(state.connections, button.AncestryChanged:Connect(function()
		if not button:IsDescendantOf(game) then
			unbind(button)
		end
	end))

	if not isCloser then
		popIn(state)
		startIdleWobble(state)
	end
end

local function consider(instance: Instance)
	if not instance:IsA("GuiButton") then
		return
	end
	local closeKeyword = findKeyword(instance.Name, CLOSE_KEYWORDS)
	if closeKeyword then
		bind(instance, nil, true)
		return
	end
	local keyword = findKeyword(instance.Name, MENU_KEYWORDS)
	if keyword then
		bind(instance, keyword, false)
	end
end

function MenuButtonsController.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		for _, descendant in playerGui:GetDescendants() do
			consider(descendant)
		end
		table.insert(watchConnections, playerGui.DescendantAdded:Connect(function(descendant)
			task.defer(consider, descendant)
		end))
	end)
end

function MenuButtonsController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in watchConnections do
		connection:Disconnect()
	end
	table.clear(watchConnections)
	for button in bound do
		unbind(button)
	end
end

return MenuButtonsController
