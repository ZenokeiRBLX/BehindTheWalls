local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))

local TeleportHudController = {}

local HUD_NAME = "Teleporting_HUD"
local FRAME_NAME = "Outer_Frame"
local LABEL_NAME = "TextLabel"
local DISPLAY_ORDER = 1000
local SHOWN_FRAME_ATTRIBUTE = "ShownFrameTransparency"
local SHOWN_TEXT_ATTRIBUTE = "ShownTextTransparency"
local PHASE_ATTRIBUTE = "ArrivalPhase"
local ARRIVAL_COMPLETE_ATTRIBUTE = "ArrivalComplete"
local TELEPORT_TEXT = "Teleporting"
local WAITING_TEXT = "Waiting for Players to Load.. [%d/%d]"
local WAITING_PENDING_TEXT = "Waiting for Players to Load.."
local DOT_INTERVAL = 0.45
local MAX_DOTS = 3
local FALLBACK_MAX_TEXT_SIZE = 36
local FADE_IN = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

type Phase = "Hidden" | "Teleporting" | "Waiting"
type ArrivalState = Blink.ArrivalStateData

local isStarted = false
local disconnects: { () -> () } = {}
local phase: Phase = "Hidden"
local token = 0
local hud: ScreenGui?
local frame: GuiObject?
local label: TextLabel?
local shownFrameTransparency = 0
local shownTextTransparency = 0

local function buildFallbackHud(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = HUD_NAME
	gui.Enabled = false

	local outer = Instance.new("Frame")
	outer.Name = FRAME_NAME
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.fromScale(1, 1)
	outer.BackgroundColor3 = Color3.new(0, 0, 0)
	outer.BorderSizePixel = 0
	outer.Parent = gui

	local text = Instance.new("TextLabel")
	text.Name = LABEL_NAME
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextScaled = true
	text.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	text.ZIndex = 6
	text.Parent = gui

	local sizer = Instance.new("UITextSizeConstraint")
	sizer.Name = "TextSizer"
	sizer.MaxTextSize = FALLBACK_MAX_TEXT_SIZE
	sizer.Parent = text

	return gui
end

local function resolveHud(): ScreenGui?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local existing = playerGui:FindFirstChild(HUD_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	local template = ReplicatedFirst:FindFirstChild(HUD_NAME) or StarterGui:FindFirstChild(HUD_NAME)
	local gui = if template and template:IsA("ScreenGui") then template:Clone() else buildFallbackHud()
	gui.Parent = playerGui
	return gui
end

local function bindHud(): boolean
	if hud and hud.Parent then
		return true
	end
	local gui = resolveHud()
	if not gui then
		return false
	end
	hud = gui
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER

	local outer = gui:FindFirstChild(FRAME_NAME)
	frame = if outer and outer:IsA("GuiObject") then outer else nil
	local text = gui:FindFirstChild(LABEL_NAME)
	label = if text and text:IsA("TextLabel") then text else nil

	local frameValue = gui:GetAttribute(SHOWN_FRAME_ATTRIBUTE)
	shownFrameTransparency = if type(frameValue) == "number" then frameValue elseif frame then frame.BackgroundTransparency else 0
	local textValue = gui:GetAttribute(SHOWN_TEXT_ATTRIBUTE)
	shownTextTransparency = if type(textValue) == "number" then textValue elseif label then label.TextTransparency else 0
	gui:SetAttribute(SHOWN_FRAME_ATTRIBUTE, shownFrameTransparency)
	gui:SetAttribute(SHOWN_TEXT_ATTRIBUTE, shownTextTransparency)

	if gui.Enabled and phase == "Hidden" then
		phase = "Teleporting"
	end
	return true
end

local function setText(text: string)
	if label then
		label.Text = text
	end
end

local function tweenTo(frameTransparency: number, textTransparency: number, info: TweenInfo): Tween?
	local last: Tween? = nil
	if frame then
		last = TweenService:Create(frame, info, { BackgroundTransparency = frameTransparency })
		last:Play()
	end
	if label then
		last = TweenService:Create(label, info, { TextTransparency = textTransparency })
		last:Play()
	end
	return last
end

local function runDots()
	local myToken = token
	task.spawn(function()
		local count = MAX_DOTS - 1
		while token == myToken and phase == "Teleporting" do
			count = count % MAX_DOTS + 1
			setText(TELEPORT_TEXT .. string.rep(".", count))
			task.wait(DOT_INTERVAL)
		end
	end)
end

local function show(text: string, newPhase: Phase, onShown: (() -> ())?)
	if not bindHud() then
		return
	end
	local gui = hud :: ScreenGui
	token += 1
	local wasVisible = phase ~= "Hidden"
	phase = newPhase
	setText(text)
	if wasVisible then
		tweenTo(shownFrameTransparency, shownTextTransparency, FADE_IN)
		if onShown then
			onShown()
		end
		return
	end
	if frame then
		frame.BackgroundTransparency = 1
	end
	if label then
		label.TextTransparency = 1
	end
	gui.Enabled = true
	local tween = tweenTo(shownFrameTransparency, shownTextTransparency, FADE_IN)
	if not onShown then
		return
	end
	if tween then
		tween.Completed:Once(onShown)
	else
		onShown()
	end
end

local function hide()
	if not hud or phase == "Hidden" then
		return
	end
	token += 1
	local myToken = token
	phase = "Hidden"
	local function finish()
		if token ~= myToken or not hud then
			return
		end
		hud.Enabled = false
	end
	local tween = tweenTo(1, 1, FADE_OUT)
	if tween then
		tween.Completed:Once(finish)
	else
		finish()
	end
end

local function onPartyTeleporting()
	show(TELEPORT_TEXT .. string.rep(".", MAX_DOTS), "Teleporting", function()
		if hud then
			local ok, err = pcall(function()
				TeleportService:SetTeleportGui(hud)
			end)
			if not ok then
				warn(("TeleportHudController: SetTeleportGui failed: %s"):format(tostring(err)))
			end
		end
		Blink.PartyTeleportReady.Fire()
	end)
	runDots()
end

local function onPartyTeleportCancelled()
	hide()
end

local function onArrivalState(state: ArrivalState)
	if state.complete then
		Players.LocalPlayer:SetAttribute(ARRIVAL_COMPLETE_ATTRIBUTE, true)
		hide()
		return
	end
	show(WAITING_TEXT:format(state.arrived, state.expected), "Waiting")
end

local function hasArrivingHud(playerGui: PlayerGui): boolean
	local existing = playerGui:FindFirstChild(HUD_NAME)
	return existing ~= nil and existing:IsA("ScreenGui") and existing.Enabled
end

function TeleportHudController.start()
	if isStarted then
		return
	end
	isStarted = true

	table.insert(disconnects, Blink.PartyTeleporting.On(onPartyTeleporting))
	table.insert(disconnects, Blink.PartyTeleportCancelled.On(onPartyTeleportCancelled))
	table.insert(disconnects, Blink.ArrivalState.On(onArrivalState))

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local arriving = hasArrivingHud(playerGui :: PlayerGui)
		if arriving and bindHud() then
			if hud and hud:GetAttribute(PHASE_ATTRIBUTE) == "Waiting" then
				phase = "Waiting"
				setText(WAITING_PENDING_TEXT)
			else
				runDots()
			end
		end
		if arriving or game.PlaceId == Config.Places.Game then
			Blink.ArrivalRequest.Fire()
		end
	end)
end

function TeleportHudController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, disconnect in disconnects do
		disconnect()
	end
	table.clear(disconnects)
	token += 1
	phase = "Hidden"
	if hud then
		hud.Enabled = false
	end
end

return TeleportHudController
