local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")

local HUD_NAME = "Teleporting_HUD"
local FRAME_NAME = "Outer_Frame"
local LABEL_NAME = "TextLabel"
local DISPLAY_ORDER = 1000
local PHASE_ATTRIBUTE = "ArrivalPhase"
local WAITING_TEXT = "Waiting for Players to Load.."
local TEMPLATE_WAIT = 3
local CHILD_WAIT = 5

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function findTemplate(): ScreenGui?
	for _, container in { ReplicatedFirst, StarterGui } do
		local template = container:FindFirstChild(HUD_NAME) or container:WaitForChild(HUD_NAME, TEMPLATE_WAIT)
		if template and template:IsA("ScreenGui") then
			template:WaitForChild(FRAME_NAME, CHILD_WAIT)
			template:WaitForChild(LABEL_NAME, CHILD_WAIT)
			return template
		end
	end
	return nil
end

local ok, arriving = pcall(function()
	return TeleportService:GetArrivingTeleportGui()
end)

local hud: ScreenGui? = nil
local phase = "Teleporting"
if ok and arriving and arriving:IsA("ScreenGui") then
	hud = arriving
else
	local template = findTemplate()
	if template then
		local clone = template:Clone()
		local label = clone:FindFirstChild(LABEL_NAME)
		if label and label:IsA("TextLabel") then
			label.Text = WAITING_TEXT
		end
		hud = clone
		phase = "Waiting"
	end
end

if not hud then
	return
end

hud.Name = HUD_NAME
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = DISPLAY_ORDER
hud:SetAttribute(PHASE_ATTRIBUTE, phase)
hud.Enabled = true
hud.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()
