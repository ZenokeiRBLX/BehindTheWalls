local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

local LevelCardController = {}

type Faded = {
	instance: Instance,
	property: string,
	shown: number,
}

type View = {
	gui: ScreenGui,
	icon: ImageLabel?,
	caption: TextLabel?,
	title: TextLabel?,
	rule: GuiObject?,
	subtitle: TextLabel?,
	captionBase: UDim2,
	ruleSize: UDim2,
	faded: { Faded },
}

local isStarted = false
local view: View? = nil
local token = 0
local warned = false

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(math.max(seconds, 0), style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
	local created = TweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function later(delay: number, current: number, callback: () -> ())
	task.delay(delay, function()
		if token == current then
			callback()
		end
	end)
end

local function child(parent: Instance, name: string, className: string): any
	local found = parent:FindFirstChild(name, true)
	return if found and found:IsA(className) then found else nil
end

local function track(faded: { Faded }, instance: Instance?, property: string)
	if not instance then
		return
	end
	table.insert(faded, { instance = instance, property = property, shown = (instance :: any)[property] })
	for _, descendant in instance:GetChildren() do
		if descendant:IsA("UIStroke") then
			table.insert(faded, { instance = descendant, property = "Transparency", shown = descendant.Transparency })
		end
	end
end

local function shownValue(current: View, instance: Instance): number
	for _, entry in current.faded do
		if entry.instance == instance then
			return entry.shown
		end
	end
	return 0
end

local function strokesOf(instance: Instance): { UIStroke }
	local strokes = {}
	for _, descendant in instance:GetChildren() do
		if descendant:IsA("UIStroke") then
			table.insert(strokes, descendant)
		end
	end
	return strokes
end

local function fadeIn(current: View, instance: Instance?, seconds: number)
	if not instance then
		return
	end
	local property = if instance:IsA("ImageLabel") then "ImageTransparency" elseif instance:IsA("TextLabel") then "TextTransparency" else "BackgroundTransparency"
	tween(instance, seconds, { [property] = shownValue(current, instance) }, Enum.EasingStyle.Quad)
	for _, stroke in strokesOf(instance) do
		tween(stroke, seconds, { Transparency = shownValue(current, stroke) }, Enum.EasingStyle.Quad)
	end
end

local function conceal(current: View)
	for _, entry in current.faded do
		(entry.instance :: any)[entry.property] = 1
	end
	if current.title then
		current.title.MaxVisibleGraphemes = 0
	end
	if current.caption then
		current.caption.Position = current.captionBase + UDim2.fromScale(0, Config.LevelCard.CaptionLift)
	end
	if current.rule then
		current.rule.Size = UDim2.new(0, 0, current.ruleSize.Y.Scale, current.ruleSize.Y.Offset)
	end
end

local function bind(): View?
	local current = view
	if current and current.gui.Parent then
		return current
	end
	view = nil
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local settings = Config.LevelCard
	local gui = if playerGui then playerGui:FindFirstChild(settings.GuiName) else nil
	if not gui or not gui:IsA("ScreenGui") then
		if not warned then
			warned = true
			warn("LevelCardController: PlayerGui." .. settings.GuiName .. " not found")
		end
		return nil
	end
	local root = gui:FindFirstChild(settings.CardName) or gui
	local caption = child(root, settings.CaptionName, "TextLabel")
	local rule = child(root, settings.RuleName, "GuiObject")
	local created: View = {
		gui = gui,
		icon = child(root, settings.IconName, "ImageLabel"),
		caption = caption,
		title = child(root, settings.TitleName, "TextLabel"),
		rule = rule,
		subtitle = child(root, settings.SubtitleName, "TextLabel"),
		captionBase = if caption then caption.Position else UDim2.new(),
		ruleSize = if rule then rule.Size else UDim2.new(),
		faded = {},
	}
	track(created.faded, created.icon, "ImageTransparency")
	track(created.faded, created.caption, "TextTransparency")
	track(created.faded, created.title, "TextTransparency")
	track(created.faded, created.subtitle, "TextTransparency")
	track(created.faded, created.rule, "BackgroundTransparency")
	conceal(created)
	gui.Enabled = false
	view = created
	return created
end

local function playHit()
	local settings = Config.LevelCard
	local template = SoundService:FindFirstChild(settings.HitName)
	if not template or not template:IsA("Sound") then
		return
	end
	local sound = template:Clone()
	sound.Volume = template.Volume * settings.HitVolumeScale
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local function flickerTitle(current: View, played: number)
	local title = current.title
	if not title then
		return
	end
	local shown = shownValue(current, title)
	task.spawn(function()
		for _, frame in Config.LevelCard.TitleFlicker do
			if token ~= played or not title.Parent then
				return
			end
			title.TextTransparency = math.max(shown, frame[1])
			task.wait(frame[2])
		end
		if token == played then
			title.TextTransparency = shown
		end
	end)
end

local function typeTitle(current: View, played: number)
	local title = current.title
	if not title then
		return
	end
	local settings = Config.LevelCard
	local count = utf8.len(title.ContentText) or #title.ContentText
	local seconds = count / math.max(settings.TitleCharactersPerSecond, 1)
	title.TextTransparency = shownValue(current, title)
	for _, stroke in strokesOf(title) do
		stroke.Transparency = shownValue(current, stroke)
	end
	local driver = Instance.new("NumberValue")
	local connection = driver.Changed:Connect(function(alpha)
		if token == played then
			title.MaxVisibleGraphemes = if alpha >= 1 then -1 else math.floor(alpha * count + 0.5)
		end
	end)
	local created = tween(driver, math.max(seconds, 0.05), { Value = 1 }, Enum.EasingStyle.Linear)
	created.Completed:Once(function()
		connection:Disconnect()
		driver:Destroy()
	end)
	playHit()
	flickerTitle(current, played)
end

local function fadeOut(current: View, seconds: number, played: number)
	for _, entry in current.faded do
		tween(entry.instance, seconds, { [entry.property] = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	if current.caption then
		tween(current.caption, seconds, { Position = current.captionBase - UDim2.fromScale(0, Config.LevelCard.CaptionLift) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	later(seconds, played, function()
		current.gui.Enabled = false
		conceal(current)
	end)
end

function LevelCardController.play(mapKey: string): number
	local level = (Config.Maps.Levels :: any)[mapKey]
	local current = bind()
	if not level or not current then
		return 0
	end
	local settings = Config.LevelCard
	token += 1
	local played = token
	if current.title then
		current.title.Text = level.DisplayName
	end
	if current.caption then
		current.caption.Text = string.upper(level.Caption or "")
		current.caption.Visible = (level.Caption or "") ~= ""
	end
	if current.subtitle then
		current.subtitle.Text = level.Subtitle or ""
		current.subtitle.Visible = (level.Subtitle or "") ~= ""
	end
	conceal(current)
	current.gui.Enabled = true

	fadeIn(current, current.icon, settings.IconSeconds)
	later(settings.CaptionDelay, played, function()
		local caption = current.caption
		if caption then
			fadeIn(current, caption, settings.CaptionSeconds)
			tween(caption, settings.CaptionSeconds, { Position = current.captionBase })
		end
	end)
	later(settings.RuleDelay, played, function()
		local rule = current.rule
		if rule then
			fadeIn(current, rule, settings.RuleSeconds * 0.5)
			tween(rule, settings.RuleSeconds, { Size = current.ruleSize })
		end
	end)
	later(settings.TitleDelay, played, function()
		typeTitle(current, played)
	end)
	later(settings.SubtitleDelay, played, function()
		fadeIn(current, current.subtitle, settings.SubtitleSeconds)
	end)
	later(settings.HoldSeconds, played, function()
		fadeOut(current, settings.FadeSeconds, played)
	end)
	return settings.HoldSeconds + settings.FadeSeconds
end

function LevelCardController.hide(seconds: number?)
	local current = view
	if not current then
		return
	end
	token += 1
	fadeOut(current, seconds or 0, token)
	if not seconds or seconds <= 0 then
		current.gui.Enabled = false
		conceal(current)
	end
end

function LevelCardController.start()
	if isStarted then
		return
	end
	isStarted = true
end

function LevelCardController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	LevelCardController.hide(0)
	view = nil
end

return LevelCardController
