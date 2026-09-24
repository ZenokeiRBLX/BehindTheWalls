local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local FirstPersonCameraController = require(script.Parent:WaitForChild("FirstPersonCameraController"))
local FlashlightController = require(script.Parent:WaitForChild("FlashlightController"))

local HudController = {}

local RAGDOLL_ATTRIBUTE = "Ragdolled"

export type ObjectiveEntry = {
	text: string,
	progress: number?,
	goal: number?,
	complete: boolean?,
}

type Step = {
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
}

type IconState = {
	image: ImageLabel,
	transparency: number,
}

type MainView = {
	gui: ScreenGui,
	connections: { RBXScriptConnection },
	objective: GuiObject?,
	objectiveBase: UDim2,
	title: TextLabel?,
	titleTransparency: number,
	rule: Frame?,
	icons: { IconState },
	list: GuiObject?,
	template: TextLabel?,
	labels: { TextLabel },
	texts: { string },
	completed: { boolean },
	idleTransparency: number,
	baseColor: Color3,
	statBar: GuiObject?,
	statBase: UDim2,
	revives: TextLabel?,
	revivesColor: Color3,
	revivesTransparency: number,
	revivesScale: UIScale?,
	heart: ImageLabel?,
	heartSize: UDim2,
	heartColor: Color3,
	heartTransparency: number,
}

type SlotSettings = {
	Attribute: string,
	Active: { string },
	Lit: { string },
}

type Slot = {
	button: GuiButton,
	settings: SlotSettings?,
	icon: ImageLabel?,
	stroke: UIStroke?,
	hotkey: TextLabel?,
	aura: UIStroke?,
	pip: Frame?,
	shine: Frame?,
	shineGradient: UIGradient?,
	corner: UDim,
	iconSize: UDim2,
	iconPosition: UDim2,
	iconColor: Color3,
	iconTransparency: number,
	strokeColor: Color3,
	strokeTransparency: number,
	strokeThickness: number,
	background: Color3,
	backgroundTransparency: number,
	hotkeyColor: Color3,
	hovered: boolean,
	pressed: boolean,
	active: boolean,
	lit: boolean,
	token: number,
}

type HotbarView = {
	gui: ScreenGui,
	connections: { RBXScriptConnection },
	bar: GuiObject?,
	barBase: UDim2,
	slots: { Slot },
}

local SLOT_ACTIONS: { [string]: () -> () } = {
	Flashlight = FlashlightController.toggle,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local mainView: MainView? = nil
local hotbarView: HotbarView? = nil
local shown = false
local visibilityToken = 0
local rollToken = 0
local reviveCount = 0
local objectives: { ObjectiveEntry }? = nil
local typeTokens: { [TextLabel]: number } = setmetatable({}, { __mode = "k" }) :: any

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local info = TweenInfo.new(math.max(seconds, 0), style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
	local created = TweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function apply(instance: Instance, goal: { [string]: any }, seconds: number, style: Enum.EasingStyle?)
	if seconds <= 0 then
		for property, value in goal do
			(instance :: any)[property] = value
		end
	end
	tween(instance, seconds, goal, style)
end

local function loop(instance: Instance, seconds: number, goal: { [string]: any }): Tween
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local created = TweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function step(seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Step
	return { seconds = seconds, goal = goal, style = style, direction = direction }
end

local function chain(instance: Instance, steps: { Step })
	local function play(index: number)
		local current = steps[index]
		if not current or not instance.Parent then
			return
		end
		local created = tween(instance, current.seconds, current.goal, current.style, current.direction)
		created.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				play(index + 1)
			end
		end)
	end
	play(1)
end

local function animate(seconds: number, style: Enum.EasingStyle, callback: (number) -> ())
	local driver = Instance.new("NumberValue")
	local connection = driver.Changed:Connect(callback)
	local created = TweenService:Create(driver, TweenInfo.new(math.max(seconds, 0.01), style, Enum.EasingDirection.Out), { Value = 1 })
	created.Completed:Once(function()
		connection:Disconnect()
		driver:Destroy()
	end)
	created:Play()
end

local function later(delay: number, callback: () -> ())
	local token = visibilityToken
	task.delay(delay, function()
		if visibilityToken == token then
			callback()
		end
	end)
end

local function scaleUDim2(value: UDim2, factor: number): UDim2
	return UDim2.new(value.X.Scale * factor, value.X.Offset * factor, value.Y.Scale * factor, value.Y.Offset * factor)
end

local function centerAnchor(gui: GuiObject)
	local anchor = gui.AnchorPoint
	local size = gui.Size
	local position = gui.Position
	local dx = 0.5 - anchor.X
	local dy = 0.5 - anchor.Y
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.new(
		position.X.Scale + size.X.Scale * dx,
		position.X.Offset + size.X.Offset * dx,
		position.Y.Scale + size.Y.Scale * dy,
		position.Y.Offset + size.Y.Offset * dy
	)
end

local function findPath(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in path do
		current = if current then current:FindFirstChild(name) else nil
	end
	return current
end

local function newCorner(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function graphemeCount(label: TextLabel): number
	return utf8.len(label.ContentText) or #label.ContentText
end

local function conceal(label: TextLabel)
	typeTokens[label] = (typeTokens[label] or 0) + 1
	label.MaxVisibleGraphemes = 0
	label.TextTransparency = 1
end

local function typeIn(label: TextLabel, delay: number, transparency: number)
	local token = (typeTokens[label] or 0) + 1
	typeTokens[label] = token
	label.MaxVisibleGraphemes = 0
	label.TextTransparency = 1
	task.delay(delay, function()
		if typeTokens[label] ~= token or not label.Parent then
			return
		end
		local intro = Config.Hud.Intro
		local count = graphemeCount(label)
		tween(label, intro.FadeSeconds, { TextTransparency = transparency }, Enum.EasingStyle.Quad)
		animate(count / intro.TypeCharactersPerSecond, Enum.EasingStyle.Linear, function(alpha)
			if typeTokens[label] == token then
				label.MaxVisibleGraphemes = if alpha >= 1 then -1 else math.floor(alpha * count)
			end
		end)
	end)
end

local function wantsHud(): boolean
	if not FirstPersonCameraController.isEnabled() or FirstPersonCameraController.isHudHidden() then
		return false
	end
	local character = Players.LocalPlayer.Character
	if not character or character:GetAttribute(RAGDOLL_ATTRIBUTE) then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function escapeRichText(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function isComplete(entry: ObjectiveEntry): boolean
	if entry.complete ~= nil then
		return entry.complete
	end
	return entry.goal ~= nil and (entry.progress or 0) >= entry.goal
end

local function objectiveText(index: number, entry: ObjectiveEntry): string
	local text = ("%d. %s"):format(index, entry.text)
	local goal = entry.goal
	if goal then
		text ..= (" (%d/%d)"):format(math.clamp(entry.progress or 0, 0, goal), goal)
	end
	return text
end

local function labelTransparency(view: MainView, complete: boolean): number
	return if complete then Config.Hud.Objectives.CompleteTransparency else view.idleTransparency
end

local function writeLabel(view: MainView, label: TextLabel, text: string, complete: boolean)
	label.RichText = complete
	label.Text = if complete then "<s>" .. escapeRichText(text) .. "</s>" else text
	label.TextColor3 = if complete then Config.Hud.Objectives.CompleteColor else view.baseColor
end

local function flashLabel(view: MainView, label: TextLabel, complete: boolean, finished: boolean)
	local settings = Config.Hud.Objectives
	typeTokens[label] = (typeTokens[label] or 0) + 1
	label.MaxVisibleGraphemes = -1
	label.TextTransparency = 0
	label.TextColor3 = if finished then Color3.new(1, 1, 1) else Config.Hud.AccentColor
	tween(label, settings.PulseSeconds, {
		TextTransparency = labelTransparency(view, complete),
		TextColor3 = if complete then settings.CompleteColor else view.baseColor,
	}, Enum.EasingStyle.Quad)
end

local function removeLabel(label: TextLabel)
	local seconds = Config.Hud.Objectives.RemoveSeconds
	typeTokens[label] = (typeTokens[label] or 0) + 1
	tween(label, seconds, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		tween(stroke, seconds, { Transparency = 1 }, Enum.EasingStyle.Quad)
	end
	Debris:AddItem(label, seconds)
end

local function renderObjectives(view: MainView)
	local entries = objectives
	local list = view.list
	local template = view.template
	if not entries or not list or not template then
		return
	end
	local live = shown and view.gui.Enabled
	local stagger = Config.Hud.Intro.Stagger
	local added = 0
	for index, entry in entries do
		local text = objectiveText(index, entry)
		local complete = isComplete(entry)
		local label = view.labels[index]
		if not label then
			local created = template:Clone()
			created.LayoutOrder = index
			view.labels[index] = created
			view.texts[index] = text
			view.completed[index] = complete
			writeLabel(view, created, text, complete)
			created.Parent = list
			if live then
				typeIn(created, added * stagger, labelTransparency(view, complete))
				added += 1
			else
				conceal(created)
			end
		elseif view.texts[index] ~= text or view.completed[index] ~= complete then
			local finished = complete and not view.completed[index]
			view.texts[index] = text
			view.completed[index] = complete
			label.LayoutOrder = index
			writeLabel(view, label, text, complete)
			if live then
				flashLabel(view, label, complete, finished)
			else
				conceal(label)
			end
		end
	end
	for index = #view.labels, #entries + 1, -1 do
		local label = table.remove(view.labels, index)
		table.remove(view.texts, index)
		table.remove(view.completed, index)
		if label then
			if live then
				removeLabel(label)
			else
				label:Destroy()
			end
		end
	end
end

local function applyHeart(view: MainView, seconds: number)
	local settings = Config.Hud.Revives
	local alive = reviveCount > 0
	local heart = view.heart
	if heart then
		apply(heart, {
			ImageColor3 = if alive then view.heartColor else settings.EmptyColor,
			ImageTransparency = if alive then view.heartTransparency else settings.EmptyTransparency,
		}, seconds, Enum.EasingStyle.Quad)
	end
	local label = view.revives
	if label then
		apply(label, { TextTransparency = if alive then view.revivesTransparency else settings.EmptyTransparency }, seconds, Enum.EasingStyle.Quad)
	end
end

local function rollRevives(view: MainView, from: number, to: number, delay: number)
	local label = view.revives
	if not label then
		return
	end
	rollToken += 1
	local token = rollToken
	task.delay(delay, function()
		if rollToken ~= token or mainView ~= view then
			return
		end
		animate(Config.Hud.Revives.CountSeconds, Enum.EasingStyle.Quart, function(alpha)
			if rollToken == token and label.Parent then
				label.Text = tostring(math.floor(from + (to - from) * alpha + 0.5))
			end
		end)
	end)
end

local function popHeart(view: MainView, factor: number)
	local heart = view.heart
	if not heart then
		return
	end
	chain(heart, {
		step(0.1, { Size = scaleUDim2(view.heartSize, factor) }, Enum.EasingStyle.Quad),
		step(0.45, { Size = view.heartSize }, Enum.EasingStyle.Back),
	})
end

local function flashRevives(view: MainView, gained: boolean)
	local settings = Config.Hud.Revives
	local label = view.revives
	if label then
		label.TextColor3 = if gained then settings.GainColor else settings.LossColor
		tween(label, settings.FlashSeconds, { TextColor3 = view.revivesColor }, Enum.EasingStyle.Quad)
	end
	local scale = view.revivesScale
	if scale then
		chain(scale, {
			step(0.1, { Scale = settings.PopScale }, Enum.EasingStyle.Quad),
			step(0.45, { Scale = 1 }, Enum.EasingStyle.Back),
		})
	end
	local heart = view.heart
	if heart then
		if gained then
			popHeart(view, settings.PopScale + 0.15)
		else
			heart.ImageColor3 = settings.LossColor
			local steps = {}
			for _, degrees in settings.ShakeDegrees do
				table.insert(steps, step(0.06, { Rotation = degrees }, Enum.EasingStyle.Sine))
			end
			chain(heart, steps)
		end
	end
	applyHeart(view, settings.FlashSeconds)
end

local function readRevives(): number?
	local value = Players.LocalPlayer:GetAttribute(Config.Hud.Revives.Attribute)
	return if typeof(value) == "number" then math.max(math.floor(value), 0) else nil
end

local function refreshRevives()
	local value = readRevives()
	if value == nil then
		return
	end
	local previous = reviveCount
	reviveCount = value
	local view = mainView
	if not view or not view.revives then
		return
	end
	if not shown or not view.gui.Enabled then
		rollToken += 1
		view.revives.Text = tostring(value)
		applyHeart(view, 0)
		return
	end
	if value == previous then
		return
	end
	rollRevives(view, previous, value, 0)
	flashRevives(view, value > previous)
end

local function heartbeat(view: MainView)
	task.spawn(function()
		local settings = Config.Hud.Revives
		while mainView == view do
			local heart = view.heart
			if heart and shown and view.gui.Enabled and reviveCount > 0 then
				local strong = settings.HeartbeatScale
				local soft = 1 + (strong - 1) * 0.6
				chain(heart, {
					step(0.08, { Size = scaleUDim2(view.heartSize, strong) }, Enum.EasingStyle.Quad),
					step(0.12, { Size = view.heartSize }, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					step(0.07, { Size = scaleUDim2(view.heartSize, soft) }, Enum.EasingStyle.Quad),
					step(0.22, { Size = view.heartSize }, Enum.EasingStyle.Sine),
				})
			end
			task.wait(settings.HeartbeatInterval)
		end
	end)
end

local function buildRule(objective: GuiObject, title: TextLabel): Frame
	local settings = Config.Hud.Objectives
	local rule = Instance.new("Frame")
	rule.Name = "HudRule"
	rule.AnchorPoint = Vector2.new(0, 0.5)
	rule.Position = UDim2.new(title.Position.X.Scale, title.Position.X.Offset, settings.RuleY, 0)
	rule.Size = UDim2.fromOffset(0, 1)
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = Config.Hud.AccentColor
	rule.BackgroundTransparency = settings.RuleTransparency
	rule.ZIndex = title.ZIndex
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new(0, 1)
	gradient.Parent = rule
	rule.Parent = objective
	return rule
end

local function objectiveHidden(view: MainView): UDim2
	return view.objectiveBase - UDim2.fromScale(Config.Hud.Objectives.SlideScale, 0)
end

local function statHidden(view: MainView): UDim2
	return view.statBase + UDim2.fromScale(Config.Hud.Revives.SlideScale, 0)
end

local function concealMain(view: MainView)
	view.gui.Enabled = false
	local objective = view.objective
	if objective then
		apply(objective, { Position = objectiveHidden(view) }, 0)
	end
	if view.title then
		conceal(view.title)
	end
	if view.rule then
		apply(view.rule, { Size = UDim2.fromOffset(0, 1) }, 0)
	end
	for _, icon in view.icons do
		apply(icon.image, { ImageTransparency = 1 }, 0)
	end
	for _, label in view.labels do
		conceal(label)
	end
	local statBar = view.statBar
	if statBar then
		apply(statBar, { Position = statHidden(view) }, 0)
	end
	rollToken += 1
	if view.revives then
		view.revives.Text = tostring(reviveCount)
	end
	applyHeart(view, 0)
end

local function introMain(view: MainView)
	local intro = Config.Hud.Intro
	local settings = Config.Hud.Objectives
	view.gui.Enabled = true
	local objective = view.objective
	if objective then
		objective.Position = objectiveHidden(view)
		tween(objective, intro.Seconds, { Position = view.objectiveBase })
	end
	for index, icon in view.icons do
		icon.image.ImageTransparency = 1
		later(intro.Delay, function()
			tween(icon.image, intro.FadeSeconds, { ImageTransparency = icon.transparency }, Enum.EasingStyle.Quad)
			if index == 1 and #view.icons > 1 then
				later(intro.FadeSeconds, function()
					loop(icon.image, settings.IconPulseSeconds, { ImageTransparency = settings.IconPulseTransparency })
				end)
			end
		end)
	end
	if view.title then
		typeIn(view.title, intro.Delay, view.titleTransparency)
	end
	local rule = view.rule
	if rule then
		rule.Size = UDim2.fromOffset(0, 1)
		later(intro.Delay + 0.2, function()
			tween(rule, intro.Seconds, { Size = UDim2.new(settings.RuleWidth, 0, 0, 1) })
		end)
	end
	for index, label in view.labels do
		typeIn(label, intro.Delay + 0.3 + (index - 1) * intro.Stagger, labelTransparency(view, view.completed[index] == true))
	end
	local statBar = view.statBar
	if statBar then
		statBar.Position = statHidden(view)
		later(intro.Delay, function()
			tween(statBar, intro.Seconds, { Position = view.statBase })
		end)
	end
	if view.revives then
		view.revives.Text = "0"
		rollRevives(view, 0, reviveCount, intro.Delay + intro.Seconds * 0.4)
		later(intro.Delay + intro.Seconds * 0.4, function()
			popHeart(view, Config.Hud.Revives.PopScale)
		end)
	end
	applyHeart(view, 0)
end

local function outroMain(view: MainView)
	local seconds = Config.Hud.Outro.Seconds
	local objective = view.objective
	if objective then
		tween(objective, seconds, { Position = objectiveHidden(view) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	local statBar = view.statBar
	if statBar then
		tween(statBar, seconds, { Position = statHidden(view) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	later(seconds, function()
		if mainView == view then
			concealMain(view)
		end
	end)
end

local function unbindMain()
	local view = mainView
	if not view then
		return
	end
	mainView = nil
	for _, connection in view.connections do
		connection:Disconnect()
	end
end

local function bindMain(gui: ScreenGui)
	unbindMain()
	local settings = Config.Hud
	local view: MainView = {
		gui = gui,
		connections = {},
		objectiveBase = UDim2.new(),
		titleTransparency = 0,
		icons = {},
		labels = {},
		texts = {},
		completed = {},
		idleTransparency = 0.5,
		baseColor = Color3.new(1, 1, 1),
		statBase = UDim2.new(),
		revivesColor = Color3.new(1, 1, 1),
		revivesTransparency = 0,
		heartSize = UDim2.new(),
		heartColor = Color3.new(1, 1, 1),
		heartTransparency = 0,
	}

	local objective = findPath(gui, settings.Objectives.FramePath)
	if objective and objective:IsA("GuiObject") then
		view.objective = objective
		view.objectiveBase = objective.Position
		local title = objective:FindFirstChild(settings.Objectives.TitleName)
		if title and title:IsA("TextLabel") then
			view.title = title
			view.titleTransparency = title.TextTransparency
			view.rule = buildRule(objective, title)
		end
		local folder = objective:FindFirstChild(settings.Objectives.IconFolderName)
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("ImageLabel") then
					table.insert(view.icons, { image = child, transparency = child.ImageTransparency })
				end
			end
			table.sort(view.icons, function(a, b)
				return a.image.ZIndex < b.image.ZIndex
			end)
		end
		local list = objective:FindFirstChild(settings.Objectives.ListName)
		if list and list:IsA("GuiObject") then
			view.list = list
			local existing: { TextLabel } = {}
			for _, child in list:GetChildren() do
				if child:IsA("TextLabel") then
					table.insert(existing, child)
				end
			end
			table.sort(existing, function(a, b)
				if a.LayoutOrder ~= b.LayoutOrder then
					return a.LayoutOrder < b.LayoutOrder
				end
				return a.Text < b.Text
			end)
			local first = existing[1]
			if first then
				local template = first:Clone()
				template.MaxVisibleGraphemes = -1
				view.template = template
				view.idleTransparency = first.TextTransparency
				view.baseColor = first.TextColor3
			end
			for index, label in existing do
				if objectives then
					label:Destroy()
				else
					label.LayoutOrder = index
					view.labels[index] = label
					view.texts[index] = label.Text
					view.completed[index] = false
				end
			end
		end
	end

	local statBar = gui:FindFirstChild(settings.Revives.StatBarName, true)
	if statBar and statBar:IsA("GuiObject") then
		view.statBar = statBar
		view.statBase = statBar.Position
		local revives = statBar:FindFirstChild(settings.Revives.LabelName)
		if revives and revives:IsA("TextLabel") then
			view.revives = revives
			view.revivesColor = revives.TextColor3
			view.revivesTransparency = revives.TextTransparency
			local scale = Instance.new("UIScale")
			scale.Name = "HudScale"
			scale.Parent = revives
			view.revivesScale = scale
			if readRevives() == nil then
				reviveCount = tonumber(revives.Text) or reviveCount
			end
			local heart = revives:FindFirstChild(settings.Revives.IconName)
			if heart and heart:IsA("ImageLabel") then
				centerAnchor(heart)
				view.heart = heart
				view.heartSize = heart.Size
				view.heartColor = heart.ImageColor3
				view.heartTransparency = heart.ImageTransparency
			end
		end
	end

	mainView = view
	renderObjectives(view)
	table.insert(view.connections, gui.AncestryChanged:Connect(function()
		if not gui:IsDescendantOf(Players.LocalPlayer) and mainView == view then
			unbindMain()
		end
	end))
	concealMain(view)
	if shown then
		introMain(view)
	end
	heartbeat(view)
end

local function slotIconSize(slot: Slot): UDim2
	local settings = Config.Hud.Hotbar
	local factor = 1
	if slot.active then
		factor *= settings.ActiveIconScale
	end
	if slot.hovered then
		factor *= settings.HoverScale
	end
	if slot.pressed then
		factor *= settings.PressScale
	end
	return scaleUDim2(slot.iconSize, factor)
end

local function slotIconPosition(slot: Slot): UDim2
	if slot.active then
		return slot.iconPosition - UDim2.fromScale(0, Config.Hud.Hotbar.ActiveIconLift)
	end
	return slot.iconPosition
end

local function slotIconColor(slot: Slot): Color3
	return if slot.lit then Config.Hud.Hotbar.LitIconColor else slot.iconColor
end

local function settleIcon(slot: Slot, seconds: number, style: Enum.EasingStyle?)
	local icon = slot.icon
	if icon then
		apply(icon, {
			Size = slotIconSize(slot),
			Position = slotIconPosition(slot),
			ImageColor3 = slotIconColor(slot),
		}, seconds, style)
	end
end

local function settleFrame(slot: Slot, seconds: number)
	local settings = Config.Hud.Hotbar
	local accent = Config.Hud.AccentColor
	apply(slot.button, {
		BackgroundColor3 = if slot.active then settings.ActiveBackground else slot.background,
		BackgroundTransparency = if slot.active then settings.ActiveBackgroundTransparency else slot.backgroundTransparency,
	}, seconds)
	local stroke = slot.stroke
	if stroke then
		apply(stroke, {
			Color = if slot.active then accent else slot.strokeColor,
			Transparency = if slot.active
				then settings.ActiveStrokeTransparency
				elseif slot.hovered then settings.HoverStrokeTransparency
				else slot.strokeTransparency,
			Thickness = if slot.active then settings.ActiveStrokeThickness else slot.strokeThickness,
		}, seconds)
	end
	local hotkey = slot.hotkey
	if hotkey then
		apply(hotkey, { TextColor3 = if slot.active then accent else slot.hotkeyColor }, seconds)
	end
	local pip = slot.pip
	if pip then
		local width = if slot.active then settings.PipWidth else 0
		apply(pip, { Size = UDim2.new(width, 0, 0, settings.PipHeight) }, seconds, if slot.active then Enum.EasingStyle.Back else Enum.EasingStyle.Quint)
	end
end

local function settleAura(slot: Slot, seconds: number)
	local aura = slot.aura
	if not aura then
		return
	end
	local settings = Config.Hud.Hotbar
	local target = if slot.lit then settings.AuraPulse[2] elseif slot.active then settings.AuraActiveTransparency else 1
	apply(aura, { Transparency = target }, seconds, Enum.EasingStyle.Quad)
	if slot.lit then
		local token = slot.token
		task.delay(seconds, function()
			if slot.token == token and slot.lit and aura.Parent then
				loop(aura, settings.AuraPulseSeconds, { Transparency = settings.AuraPulse[1] })
			end
		end)
	end
end

local function ripple(slot: Slot, from: number, to: number, seconds: number, transparency: number)
	local ring = Instance.new("Frame")
	ring.Name = "HudRipple"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(from, from)
	ring.BackgroundTransparency = 1
	ring.ZIndex = slot.button.ZIndex
	newCorner(ring, slot.corner)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Config.Hud.AccentColor
	stroke.Thickness = 2
	stroke.Transparency = transparency
	stroke.Parent = ring
	ring.Parent = slot.button
	tween(ring, seconds, { Size = UDim2.fromScale(to, to) })
	tween(stroke, seconds, { Transparency = 1, Thickness = 0.5 }, Enum.EasingStyle.Quad)
	Debris:AddItem(ring, seconds + 0.1)
end

local function sweep(slot: Slot)
	local shine = slot.shine
	local gradient = slot.shineGradient
	if not shine or not gradient then
		return
	end
	shine.Visible = true
	gradient.Offset = Vector2.new(-1.2, 0)
	local created = tween(gradient, Config.Hud.Hotbar.ShineSeconds, { Offset = Vector2.new(1.2, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	created.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			shine.Visible = false
		end
	end)
end

local function flicker(slot: Slot, pattern: { { number } }, token: number): number
	local total = 0
	for _, frame in pattern do
		total += frame[2]
	end
	task.spawn(function()
		for _, frame in pattern do
			local icon = slot.icon
			if slot.token ~= token or not icon or not icon.Parent then
				return
			end
			icon.ImageTransparency = frame[1]
			task.wait(frame[2])
		end
		if slot.token == token and slot.icon then
			slot.icon.ImageTransparency = slot.iconTransparency
		end
	end)
	return total
end

local function applySlotInstant(slot: Slot)
	slot.token += 1
	local icon = slot.icon
	if icon then
		icon.Rotation = 0
		icon.ImageTransparency = slot.iconTransparency
	end
	settleIcon(slot, 0)
	settleFrame(slot, 0)
	settleAura(slot, 0)
end

local function playEquip(slot: Slot)
	slot.token += 1
	local settings = Config.Hud.Hotbar
	local icon = slot.icon
	if icon then
		icon.Rotation = -16
		tween(icon, 0.7, { Rotation = 0 }, Enum.EasingStyle.Elastic)
		tween(icon, 0.35, { Position = slotIconPosition(slot), ImageColor3 = slotIconColor(slot) })
		chain(icon, {
			step(0.1, { Size = scaleUDim2(slot.iconSize, settings.PopScale) }, Enum.EasingStyle.Quad),
			step(0.45, { Size = slotIconSize(slot) }, Enum.EasingStyle.Back),
		})
	end
	settleFrame(slot, 0.35)
	settleAura(slot, 0.35)
	ripple(slot, 1, 1.45, 0.45, 0.45)
end

local function playLit(slot: Slot)
	slot.token += 1
	local token = slot.token
	local settings = Config.Hud.Hotbar
	local wait = flicker(slot, settings.LitFlicker, token)
	task.delay(wait, function()
		if slot.token ~= token or not slot.button.Parent then
			return
		end
		local button = slot.button
		button.BackgroundColor3 = Config.Hud.AccentColor
		button.BackgroundTransparency = 0.3
		tween(button, 0.6, {
			BackgroundColor3 = settings.ActiveBackground,
			BackgroundTransparency = settings.ActiveBackgroundTransparency,
		}, Enum.EasingStyle.Quad)
		ripple(slot, 1, settings.RippleScale, settings.RippleSeconds, 0.2)
		task.delay(0.12, function()
			if slot.token == token and slot.button.Parent then
				ripple(slot, 1, settings.RippleScale * 0.8, settings.RippleSeconds, 0.45)
			end
		end)
		sweep(slot)
		local icon = slot.icon
		if icon then
			tween(icon, 0.3, { ImageColor3 = slotIconColor(slot) }, Enum.EasingStyle.Quad)
			chain(icon, {
				step(0.08, { Size = scaleUDim2(slotIconSize(slot), 1.12) }, Enum.EasingStyle.Quad),
				step(0.4, { Size = slotIconSize(slot) }, Enum.EasingStyle.Back),
			})
		end
		settleAura(slot, 0.25)
	end)
end

local function playUnequip(slot: Slot)
	slot.token += 1
	local token = slot.token
	local settings = Config.Hud.Hotbar
	flicker(slot, settings.OffFlicker, token)
	local icon = slot.icon
	if icon then
		chain(icon, {
			step(0.08, { Rotation = 10 }, Enum.EasingStyle.Quad),
			step(0.4, { Rotation = 0 }, Enum.EasingStyle.Back),
		})
		chain(icon, {
			step(0.1, { Size = scaleUDim2(slot.iconSize, 0.86) }, Enum.EasingStyle.Quad),
			step(0.4, { Size = slotIconSize(slot) }, Enum.EasingStyle.Back),
		})
		tween(icon, 0.35, { Position = slotIconPosition(slot), ImageColor3 = slotIconColor(slot) })
	end
	settleFrame(slot, 0.4)
	settleAura(slot, 0.3)
	ripple(slot, settings.RippleScale * 0.75, 1, 0.35, 0.55)
end

local function updateSlot(slot: Slot, instant: boolean)
	local settings = slot.settings
	if not settings then
		return
	end
	local character = Players.LocalPlayer.Character
	local state = if character then character:GetAttribute(settings.Attribute) else nil
	local active = typeof(state) == "string" and table.find(settings.Active, state) ~= nil
	local lit = typeof(state) == "string" and table.find(settings.Lit, state) ~= nil
	local wasActive = slot.active
	local wasLit = slot.lit
	slot.active = active
	slot.lit = lit
	if instant or not shown then
		applySlotInstant(slot)
		return
	end
	if active and not wasActive then
		playEquip(slot)
	end
	if lit and not wasLit then
		playLit(slot)
	elseif not active and wasActive then
		playUnequip(slot)
	elseif wasLit and not lit then
		settleIcon(slot, 0.3)
		settleAura(slot, 0.3)
	end
end

local function refreshSlots(instant: boolean)
	local view = hotbarView
	if not view then
		return
	end
	for _, slot in view.slots do
		updateSlot(slot, instant)
	end
end

local function buildSlot(button: GuiButton): Slot
	local settings = Config.Hud.Hotbar
	local icon = button:FindFirstChild(settings.IconName)
	local hotkey = button:FindFirstChild(settings.HotkeyName)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	local corner = button:FindFirstChildOfClass("UICorner")
	local slotIcon = if icon and icon:IsA("ImageLabel") then icon else nil
	local slotHotkey = if hotkey and hotkey:IsA("TextLabel") then hotkey else nil
	local slot: Slot = {
		button = button,
		settings = (settings.Slots :: any)[button.Name],
		icon = slotIcon,
		stroke = stroke,
		hotkey = slotHotkey,
		corner = if corner then corner.CornerRadius else UDim.new(0, 0),
		iconSize = if slotIcon then slotIcon.Size else UDim2.new(),
		iconPosition = if slotIcon then slotIcon.Position else UDim2.new(),
		iconColor = if slotIcon then slotIcon.ImageColor3 else Color3.new(1, 1, 1),
		iconTransparency = if slotIcon then slotIcon.ImageTransparency else 0,
		strokeColor = if stroke then stroke.Color else Color3.new(1, 1, 1),
		strokeTransparency = if stroke then stroke.Transparency else 1,
		strokeThickness = if stroke then stroke.Thickness else 1,
		background = button.BackgroundColor3,
		backgroundTransparency = button.BackgroundTransparency,
		hotkeyColor = if slotHotkey then slotHotkey.TextColor3 else Color3.new(1, 1, 1),
		hovered = false,
		pressed = false,
		active = false,
		lit = false,
		token = 0,
	}

	local aura = Instance.new("Frame")
	aura.Name = "HudAura"
	aura.AnchorPoint = Vector2.new(0.5, 0.5)
	aura.Position = UDim2.fromScale(0.5, 0.5)
	aura.Size = UDim2.new(1, settings.AuraPadding, 1, settings.AuraPadding)
	aura.BackgroundTransparency = 1
	aura.ZIndex = button.ZIndex
	newCorner(aura, slot.corner)
	local auraStroke = Instance.new("UIStroke")
	auraStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	auraStroke.Color = Config.Hud.AccentColor
	auraStroke.Thickness = settings.AuraThickness
	auraStroke.Transparency = 1
	auraStroke.Parent = aura
	aura.Parent = button
	slot.aura = auraStroke

	local pip = Instance.new("Frame")
	pip.Name = "HudPip"
	pip.AnchorPoint = Vector2.new(0.5, 0)
	pip.Position = UDim2.new(0.5, 0, 1, settings.PipGap)
	pip.Size = UDim2.fromOffset(0, settings.PipHeight)
	pip.BorderSizePixel = 0
	pip.BackgroundColor3 = Config.Hud.AccentColor
	pip.ZIndex = button.ZIndex
	newCorner(pip, UDim.new(1, 0))
	pip.Parent = button
	slot.pip = pip

	local shine = Instance.new("Frame")
	shine.Name = "HudShine"
	shine.Size = UDim2.fromScale(1, 1)
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0
	shine.Visible = false
	shine.ZIndex = (if slotIcon then slotIcon.ZIndex else button.ZIndex) + 1
	newCorner(shine, slot.corner)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = Vector2.new(-1.2, 0)
	gradient.Parent = shine
	shine.Parent = button
	slot.shine = shine
	slot.shineGradient = gradient
	return slot
end

local function bindSlotInput(view: HotbarView, slot: Slot)
	local button = slot.button
	local function setHovered(hovered: boolean)
		slot.hovered = hovered
		if not hovered then
			slot.pressed = false
		end
		settleIcon(slot, 0.2)
		settleFrame(slot, 0.2)
	end
	table.insert(view.connections, button.MouseEnter:Connect(function()
		setHovered(true)
	end))
	table.insert(view.connections, button.MouseLeave:Connect(function()
		setHovered(false)
	end))
	table.insert(view.connections, button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			slot.pressed = true
			settleIcon(slot, 0.08, Enum.EasingStyle.Quad)
		end
	end))
	table.insert(view.connections, button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			slot.pressed = false
			settleIcon(slot, 0.35, Enum.EasingStyle.Back)
		end
	end))
	table.insert(view.connections, button.Activated:Connect(function()
		local action = SLOT_ACTIONS[button.Name]
		if action then
			action()
		end
	end))
end

local function barHidden(view: HotbarView): UDim2
	return view.barBase + UDim2.fromScale(0, Config.Hud.Hotbar.SlideScale)
end

local function concealHotbar(view: HotbarView)
	view.gui.Enabled = false
	local bar = view.bar
	if bar then
		apply(bar, { Position = barHidden(view) }, 0)
	end
end

local function introHotbar(view: HotbarView)
	local intro = Config.Hud.Intro
	view.gui.Enabled = true
	local bar = view.bar
	if bar then
		bar.Position = barHidden(view)
		later(intro.Delay * 2, function()
			tween(bar, intro.Seconds, { Position = view.barBase })
		end)
	end
	for index, slot in view.slots do
		local icon = slot.icon
		if icon then
			apply(icon, { Size = UDim2.new() }, 0)
			later(intro.Delay * 2 + intro.Seconds * 0.4 + (index - 1) * intro.Stagger, function()
				tween(icon, 0.5, { Size = slotIconSize(slot) }, Enum.EasingStyle.Back)
			end)
		end
	end
end

local function outroHotbar(view: HotbarView)
	local seconds = Config.Hud.Outro.Seconds
	local bar = view.bar
	if bar then
		tween(bar, seconds, { Position = barHidden(view) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	later(seconds, function()
		if hotbarView == view then
			concealHotbar(view)
		end
	end)
end

local function unbindHotbar()
	local view = hotbarView
	if not view then
		return
	end
	hotbarView = nil
	for _, connection in view.connections do
		connection:Disconnect()
	end
end

local function bindHotbar(gui: ScreenGui)
	unbindHotbar()
	local view: HotbarView = {
		gui = gui,
		connections = {},
		barBase = UDim2.new(),
		slots = {},
	}
	local bar = gui:FindFirstChild(Config.Hud.Hotbar.BarName)
	if bar and bar:IsA("GuiObject") then
		view.bar = bar
		view.barBase = bar.Position
		for _, child in bar:GetChildren() do
			if child:IsA("GuiButton") then
				local slot = buildSlot(child)
				table.insert(view.slots, slot)
				bindSlotInput(view, slot)
			end
		end
		table.sort(view.slots, function(a, b)
			return a.button.LayoutOrder < b.button.LayoutOrder
		end)
	end
	hotbarView = view
	table.insert(view.connections, gui.AncestryChanged:Connect(function()
		if not gui:IsDescendantOf(Players.LocalPlayer) and hotbarView == view then
			unbindHotbar()
		end
	end))
	concealHotbar(view)
	refreshSlots(true)
	if shown then
		introHotbar(view)
	end
end

local function onGuiAdded(child: Instance)
	if not child:IsA("ScreenGui") then
		return
	end
	if child.Name == Config.Hud.MainGuiName then
		bindMain(child)
	elseif child.Name == Config.Hud.HotbarGuiName then
		bindHotbar(child)
	end
end

local function setShown(visible: boolean)
	shown = visible
	visibilityToken += 1
	local main = mainView
	if main then
		if visible then
			introMain(main)
		else
			outroMain(main)
		end
	end
	local hotbar = hotbarView
	if hotbar then
		if visible then
			introHotbar(hotbar)
		else
			outroHotbar(hotbar)
		end
	end
end

local function watchCharacter(character: Model?)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	if character then
		local watched: { [string]: boolean } = {}
		for _, settings: SlotSettings in Config.Hud.Hotbar.Slots do
			if not watched[settings.Attribute] then
				watched[settings.Attribute] = true
				table.insert(characterConnections, character:GetAttributeChangedSignal(settings.Attribute):Connect(function()
					refreshSlots(false)
				end))
			end
		end
	end
	refreshSlots(true)
end

function HudController.isShown(): boolean
	return shown
end

function HudController.setObjectives(entries: { ObjectiveEntry })
	local copy: { ObjectiveEntry } = {}
	for index, entry in entries do
		copy[index] = table.clone(entry)
	end
	objectives = copy
	if mainView then
		renderObjectives(mainView)
	end
end

function HudController.updateObjective(index: number, progress: number?, complete: boolean?)
	local entries = objectives
	local current = if entries then entries[index] else nil
	if not entries or not current then
		return
	end
	local entry = table.clone(current)
	entry.progress = progress
	if complete ~= nil then
		entry.complete = complete
	end
	entries[index] = entry
	if mainView then
		renderObjectives(mainView)
	end
end

function HudController.start()
	if isStarted then
		return
	end
	isStarted = true
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	reviveCount = readRevives() or 0
	table.insert(connections, playerGui.ChildAdded:Connect(onGuiAdded))
	for _, child in playerGui:GetChildren() do
		onGuiAdded(child)
	end
	table.insert(connections, player:GetAttributeChangedSignal(Config.Hud.Revives.Attribute):Connect(refreshRevives))
	table.insert(connections, player.CharacterAdded:Connect(watchCharacter))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		watchCharacter(nil)
	end))
	watchCharacter(player.Character)
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local wanted = wantsHud()
		if wanted ~= shown then
			setShown(wanted)
		end
	end))
end

function HudController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	watchCharacter(nil)
	unbindMain()
	unbindHotbar()
	shown = false
	visibilityToken += 1
end

return HudController
