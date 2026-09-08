local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")

local HUD_NAME = "Teleporting_HUD"
local DISPLAY_ORDER = 1000

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ok, hud = pcall(function()
	return TeleportService:GetArrivingTeleportGui()
end)
if not ok or not hud or not hud:IsA("ScreenGui") then
	return
end

hud.Name = HUD_NAME
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = DISPLAY_ORDER
hud.Enabled = true
hud.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()
