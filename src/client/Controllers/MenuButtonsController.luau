local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MenuButtonsController = {}

local BUTTON_KEYWORDS = { "shop", "index", "badges", "settings" }
local IGNORED_SCREEN_GUIS = { PRELOADING = true, LoadingScreen = true, Intro_Screen = true, Black_Transition = true }
local PANEL_SUFFIXES = { "Frame", "_Frame", "Panel", "_Panel", "Menu", "_Menu", "" }

local HOVER_SCALE = 1.12
local HOVER_TILT = 6
local PRESS_SCALE = 0.9
local PRESS_TILT = -10
local HOVER_BRIGHTEN = 0.18
local HOVER_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LEAVE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN = TweenInfo.new(0.55, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local PANEL_OPEN_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PANEL_CLOSE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local IDLE_WOBBLE_DEGREES = 2.5
local IDLE_WOBBLE_SECONDS = 2.2

type ButtonState = {
	button: GuiButton,
	scale: UIScale,
	baseRotation: number,
	tiltDirection: number,
	baseImageColor: Color3?,
	baseTextColor: Color3?,
	baseBackgroundColor: Color3,
	hovered: boolean,
	pressed: boolean,
	idleResumeAt: number,
	panel: GuiObject?,
	connections: { RBXScriptConnection },
}

local isStarted = false
local bound: { [GuiButton]: ButtonState } = {}
local openPanel: GuiObject?
local watchConnections: { RBXScriptConnection } = {}
local wobbleIndex = 0

local function matchesKeyword(name: string): boolean
	local lowered = string.lower(name)
	for _, keyword in BUTTON_KEYWORDS do
		if string.find(lowered, keyword, 1, true) then
			return true
		end
	end
	return false
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

local function brighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function findPanel(button: GuiButton): GuiObject?
	local explicit = button:GetAttribute("Panel")
	local screenGui = getScreenGui(button)
	if not screenGui then
		return nil
	end
	local baseName = if typeof(explicit) == "string" then explicit else button.Name
	for _, suffix in PANEL_SUFFIXES do
		local candidate = screenGui:FindFirstChild(baseName .. suffix, true)
		if candidate and candidate:IsA("GuiObject") and candidate ~= button and not candidate:IsA("GuiButton") then
			return candidate
		end
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

local function togglePanel(state: ButtonState)
	local panel = state.panel
	if not panel then
		return
	end
	if openPanel == panel then
		setPanelVisible(panel, false)
		openPanel = nil
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
		TweenService:Create(button, HOVER_TWEEN, { ImageColor3 = brighten(state.baseImageColor, HOVER_BRIGHTEN) }):Play()
	end
	if button:IsA("TextButton") and state.baseTextColor then
		TweenService:Create(button, HOVER_TWEEN, { TextColor3 = brighten(state.baseTextColor, HOVER_BRIGHTEN) }):Play()
	end
	if button.BackgroundTransparency < 1 then
		TweenService:Create(button, HOVER_TWEEN, { BackgroundColor3 = brighten(state.baseBackgroundColor, HOVER_BRIGHTEN * 0.6) }):Play()
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
end

local function applyPressLook(state: ButtonState)
	TweenService:Create(state.scale, PRESS_TWEEN, { Scale = PRESS_SCALE }):Play()
	TweenService:Create(state.button, PRESS_TWEEN, { Rotation = state.baseRotation + PRESS_TILT * state.tiltDirection }):Play()
end

local function applyReleaseLook(state: ButtonState)
	local targetScale = if state.hovered then HOVER_SCALE else 1
	local targetRotation = if state.hovered then state.baseRotation + HOVER_TILT * state.tiltDirection else state.baseRotation
	TweenService:Create(state.scale, RELEASE_TWEEN, { Scale = targetScale }):Play()
	TweenService:Create(state.button, RELEASE_TWEEN, { Rotation = targetRotation }):Play()
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

local function bind(button: GuiButton)
	if bound[button] or isIgnored(button) then
		return
	end

	local state: ButtonState = {
		button = button,
		scale = ensureScale(button),
		baseRotation = button.Rotation,
		tiltDirection = if (#BUTTON_KEYWORDS + wobbleIndex) % 2 == 0 then 1 else -1,
		baseImageColor = if button:IsA("ImageButton") then button.ImageColor3 else nil,
		baseTextColor = if button:IsA("TextButton") then button.TextColor3 else nil,
		baseBackgroundColor = button.BackgroundColor3,
		hovered = false,
		pressed = false,
		idleResumeAt = 0,
		panel = findPanel(button),
		connections = {},
	}
	bound[button] = state

	table.insert(
		state.connections,
		button.MouseEnter:Connect(function()
			state.hovered = true
			playUiSound("UI_Hover")
			applyHoverLook(state)
		end)
	)
	table.insert(
		state.connections,
		button.MouseLeave:Connect(function()
			state.hovered = false
			state.pressed = false
			state.idleResumeAt = os.clock() + 0.25
			applyRestLook(state)
		end)
	)
	table.insert(
		state.connections,
		button.MouseButton1Down:Connect(function()
			state.pressed = true
			applyPressLook(state)
		end)
	)
	table.insert(
		state.connections,
		button.MouseButton1Up:Connect(function()
			state.pressed = false
			applyReleaseLook(state)
		end)
	)
	table.insert(
		state.connections,
		button.Activated:Connect(function()
			playUiSound("UI_Click")
			togglePanel(state)
		end)
	)
	table.insert(
		state.connections,
		button.AncestryChanged:Connect(function()
			if not button:IsDescendantOf(game) then
				unbind(button)
			end
		end)
	)

	startIdleWobble(state)
end

local function scan(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") and matchesKeyword(descendant.Name) then
			bind(descendant)
		end
	end
end

function MenuButtonsController.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		scan(playerGui)
		table.insert(
			watchConnections,
			playerGui.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("GuiButton") and matchesKeyword(descendant.Name) then
					task.defer(bind, descendant)
				end
			end)
		)
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
