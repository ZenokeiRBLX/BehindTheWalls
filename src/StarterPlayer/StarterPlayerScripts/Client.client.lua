local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local matchStateRemote = remotes:WaitForChild("MatchState")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BehindTheWallsHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Size = UDim2.fromOffset(300, 90)
root.Position = UDim2.new(0.5, -150, 0, 18)
root.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
root.BackgroundTransparency = 0.2
root.BorderSizePixel = 0
root.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = root

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -16, 0, 24)
titleLabel.Position = UDim2.new(0, 8, 0, 8)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "BehindTheWalls"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 18
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = root

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -16, 0, 22)
statusLabel.Position = UDim2.new(0, 8, 0, 34)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Lobby"
statusLabel.TextColor3 = Color3.fromRGB(160, 210, 255)
statusLabel.Font = Enum.Font.GothamSemibold
statusLabel.TextSize = 16
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = root

local timerLabel = Instance.new("TextLabel")
timerLabel.Size = UDim2.new(1, -16, 0, 20)
timerLabel.Position = UDim2.new(0, 8, 0, 58)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = "15s"
timerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
timerLabel.Font = Enum.Font.Gotham

timerLabel.TextSize = 14
timerLabel.TextXAlignment = Enum.TextXAlignment.Left
timerLabel.Parent = root

local function updateHud(phase, remaining)
	statusLabel.Text = phase
	timerLabel.Text = tostring(remaining) .. "s"
end

matchStateRemote.OnClientEvent:Connect(function(phase, remaining)
	updateHud(phase, remaining)
end)

updateHud("Connecting", 0)
print(string.format("[%s] client initialized.", player.Name))
