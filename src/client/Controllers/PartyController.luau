local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))

local PartyController = {}

local GUI_NAME = "PartyGui"
local HUD_GUI_NAME = "ScreenGui"
local HUD_LEAVE_BUTTON_NAME = "LeaveQueue"
local SIZE_COUNT = 5
local DIFFICULTIES = { "Easy", "Normal", "Hard" }
local CLICK_SOUND = "UI_CLICK"
local HOVER_SOUND = "UI_HIGHLIGHT"
local TOAST_HOLD = 2.2
local SELECT_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local PRESS_TWEEN = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local PANEL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PANEL_HIDE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DISABLED_TEXT_TRANSPARENCY = 0.55

type PartyState = Blink.PartyStateData

local isStarted = false
local connections: { RBXScriptConnection } = {}
local currentState: PartyState?
local pendingSettings: { maxSize: number, difficulty: string, friendsOnly: boolean }?
local toastToken = 0

local panel: Frame?
local toast: TextLabel?
local sizeButtons: { [number]: TextButton } = {}
local difficultyButtons: { [string]: TextButton } = {}
local friendsToggle: TextButton?
local membersLabel: TextLabel?
local startButton: TextButton?
local leaveButton: TextButton?
local hudLeaveButton: GuiButton?

local function playUiSound(name: string)
	local sound = SoundService:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

local function ensureScale(gui: GuiObject): UIScale
	local existing = gui:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "PartyScale"
	scale.Parent = gui
	return scale
end

local function showToast(text: string)
	if not toast then
		return
	end
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextTransparency = 1
	toast.BackgroundTransparency = 1
	local toastStroke = toast:FindFirstChild("Stroke")
	TweenService:Create(toast, SELECT_TWEEN, { TextTransparency = 0, BackgroundTransparency = 0.2 }):Play()
	if toastStroke and toastStroke:IsA("UIStroke") then
		TweenService:Create(toastStroke, SELECT_TWEEN, { Transparency = 0.4 }):Play()
	end
	task.delay(TOAST_HOLD, function()
		if token ~= toastToken then
			return
		end
		TweenService:Create(toast, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
		if toastStroke and toastStroke:IsA("UIStroke") then
			TweenService:Create(toastStroke, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		end
	end)
end

local SELECTED_TEXT_COLOR = Color3.new(0.07, 0.07, 0.09)
local UNSELECTED_TEXT_COLOR = Color3.new(1, 1, 1)

local function setSelected(button: TextButton?, selected: boolean)
	if not button then
		return
	end
	local selectedStroke = button:FindFirstChild("Selected")
	if selectedStroke and selectedStroke:IsA("UIStroke") then
		TweenService:Create(selectedStroke, SELECT_TWEEN, { Transparency = if selected then 0 else 1 }):Play()
	end
	TweenService:Create(button, SELECT_TWEEN, {
		BackgroundTransparency = if selected then 0 else 1,
		TextColor3 = if selected then SELECTED_TEXT_COLOR else UNSELECTED_TEXT_COLOR,
	}):Play()
end

local function setEnabledLook(button: TextButton?, enabled: boolean)
	if not button then
		return
	end
	TweenService:Create(button, SELECT_TWEEN, { TextTransparency = if enabled then 0 else DISABLED_TEXT_TRANSPARENCY }):Play()
end

local function wirePress(button: GuiButton, onActivated: () -> ())
	local scale = ensureScale(button)
	table.insert(connections, button.MouseEnter:Connect(function()
		playUiSound(HOVER_SOUND)
		TweenService:Create(scale, SELECT_TWEEN, { Scale = 1.06 }):Play()
	end))
	table.insert(connections, button.MouseLeave:Connect(function()
		TweenService:Create(scale, SELECT_TWEEN, { Scale = 1 }):Play()
	end))
	table.insert(connections, button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, PRESS_TWEEN, { Scale = 0.92 }):Play()
	end))
	table.insert(connections, button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, RELEASE_TWEEN, { Scale = 1.06 }):Play()
	end))
	table.insert(connections, button.Activated:Connect(function()
		playUiSound(CLICK_SOUND)
		onActivated()
	end))
end

local function isHost(): boolean
	return currentState ~= nil and currentState.active and currentState.isHost
end

local function sendSettings()
	local state = currentState
	if not state or not pendingSettings then
		return
	end
	Blink.PartySetSettings.Fire({
		maxSize = pendingSettings.maxSize,
		difficulty = pendingSettings.difficulty :: any,
		friendsOnly = pendingSettings.friendsOnly,
	})
end

local function requireHost(): boolean
	if isHost() then
		return true
	end
	showToast("Only the party host can change settings")
	return false
end

local function applyState(state: PartyState)
	currentState = state
	pendingSettings = {
		maxSize = state.maxSize,
		difficulty = state.difficulty,
		friendsOnly = state.friendsOnly,
	}

	for index, button in sizeButtons do
		setSelected(button, state.active and index == state.maxSize)
		setEnabledLook(button, state.isHost)
	end
	for name, button in difficultyButtons do
		setSelected(button, state.active and name == state.difficulty)
		setEnabledLook(button, state.isHost)
	end
	if friendsToggle then
		friendsToggle.Text = if state.friendsOnly then "FRIENDS ONLY: ON" else "FRIENDS ONLY: OFF"
		setSelected(friendsToggle, state.active and state.friendsOnly)
		setEnabledLook(friendsToggle, state.isHost)
	end
	if membersLabel then
		if #state.members > 0 then
			membersLabel.Text = ("Party (%d/%d): %s"):format(#state.members, state.maxSize, table.concat(state.members, ", "))
		else
			membersLabel.Text = "Party: (nobody yet)"
		end
	end
	if startButton then
		startButton.Visible = state.isHost
		if state.countdown > 0 then
			startButton.Text = ("STARTING IN %d"):format(state.countdown)
		else
			startButton.Text = "START"
		end
	end
	if hudLeaveButton then
		hudLeaveButton.Visible = state.active
	end
end

local function setPanelVisible(visible: boolean)
	if not panel then
		return
	end
	local scale = ensureScale(panel)
	if visible then
		if not panel.Visible then
			panel.Visible = true
			scale.Scale = 0.85
			TweenService:Create(scale, PANEL_TWEEN, { Scale = 1 }):Play()
		end
	elseif panel.Visible then
		local tween = TweenService:Create(scale, PANEL_HIDE_TWEEN, { Scale = 0.85 })
		tween.Completed:Once(function()
			if currentState == nil or not currentState.active then
				panel.Visible = false
				scale.Scale = 1
			end
		end)
		tween:Play()
	end
end

local function onPartyState(state: PartyState)
	applyState(state)
	setPanelVisible(state.active)
end

local function bindGui(gui: ScreenGui)
	panel = gui:WaitForChild("Panel", 10) :: Frame?
	toast = gui:FindFirstChild("Toast") :: TextLabel?
	if not panel then
		warn("PartyController: PartyGui.Panel missing")
		return
	end

	local sizeRow = panel:FindFirstChild("SizeRow")
	for index = 1, SIZE_COUNT do
		local button = sizeRow and sizeRow:FindFirstChild("Size_" .. index)
		if button and button:IsA("TextButton") then
			sizeButtons[index] = button
			wirePress(button, function()
				if not requireHost() or not pendingSettings then
					return
				end
				pendingSettings.maxSize = index
				sendSettings()
			end)
		end
	end

	local difficultyRow = panel:FindFirstChild("DifficultyRow")
	for _, name in DIFFICULTIES do
		local button = difficultyRow and difficultyRow:FindFirstChild(name)
		if button and button:IsA("TextButton") then
			difficultyButtons[name] = button
			wirePress(button, function()
				if not requireHost() or not pendingSettings then
					return
				end
				pendingSettings.difficulty = name
				sendSettings()
			end)
		end
	end

	local friendsRow = panel:FindFirstChild("FriendsRow")
	local toggle = friendsRow and friendsRow:FindFirstChild("FriendsToggle")
	if toggle and toggle:IsA("TextButton") then
		friendsToggle = toggle
		wirePress(toggle, function()
			if not requireHost() or not pendingSettings then
				return
			end
			pendingSettings.friendsOnly = not pendingSettings.friendsOnly
			sendSettings()
		end)
	end

	membersLabel = panel:FindFirstChild("MembersLabel") :: TextLabel?

	local start = panel:FindFirstChild("StartButton")
	if start and start:IsA("TextButton") then
		startButton = start
		wirePress(start, function()
			if not requireHost() then
				return
			end
			Blink.PartyStart.Fire()
		end)
	end

	local leave = panel:FindFirstChild("LeaveButton")
	if leave and leave:IsA("TextButton") then
		leaveButton = leave
		wirePress(leave, function()
			Blink.PartyLeave.Fire()
		end)
	end

	local exit = panel:FindFirstChild("ExitButton")
	if exit and exit:IsA("GuiButton") then
		wirePress(exit, function()
			Blink.PartyLeave.Fire()
		end)
	end
end

local function bindHudLeaveButton(playerGui: PlayerGui)
	local hud = playerGui:FindFirstChild(HUD_GUI_NAME)
	local button = hud and hud:FindFirstChild(HUD_LEAVE_BUTTON_NAME)
	if button and button:IsA("GuiButton") then
		hudLeaveButton = button
		button.Visible = currentState ~= nil and currentState.active
		wirePress(button, function()
			Blink.PartyLeave.Fire()
		end)
	end
end

function PartyController.start()
	if isStarted then
		return
	end
	isStarted = true

	table.insert(connections, Blink.PartyState.On(onPartyState) :: any)
	table.insert(connections, Blink.PartyMessage.On(showToast) :: any)

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local gui = playerGui:FindFirstChild(GUI_NAME)
		while not gui do
			gui = playerGui:WaitForChild(GUI_NAME, 30)
		end
		bindGui(gui :: ScreenGui)
		bindHudLeaveButton(playerGui)
		table.insert(connections, playerGui.ChildAdded:Connect(function(child)
			if child.Name == HUD_GUI_NAME and not hudLeaveButton then
				task.defer(bindHudLeaveButton, playerGui)
			end
		end))
	end)
end

return PartyController
