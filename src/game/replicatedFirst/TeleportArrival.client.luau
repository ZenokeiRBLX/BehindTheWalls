local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")

local HUD_NAME = "Teleporting_HUD"
local LABEL_NAME = "TextLabel"
local DISPLAY_ORDER = 1000
local PHASE_ATTRIBUTE = "ArrivalPhase"
local WAITING_TEXT = "Waiting for Players to Load.."
local TEMPLATE_WAIT = 5

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ok, arriving = pcall(function()
	return TeleportService:GetArrivingTeleportGui()
end)

local hud: ScreenGui? = nil
local phase = "Teleporting"
if ok and arriving and arriving:IsA("ScreenGui") then
	hud = arriving
else
	local template = ReplicatedFirst:FindFirstChild(HUD_NAME) or ReplicatedFirst:WaitForChild(HUD_NAME, TEMPLATE_WAIT)
	if template and template:IsA("ScreenGui") then
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
