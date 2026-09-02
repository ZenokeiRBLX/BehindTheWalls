local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))

local IntroController = {}

local CAMERA_BIND = "IntroCamera"
local CAM_MOUSE_TILT = math.rad(2.5)
local CAM_MOUSE_SMOOTHING = 3.5
local LOADING_DONE_ATTRIBUTE = "LoadingScreenDone"
local LOADING_DONE_TIMEOUT = 90
local GLITCH_MIN_DELAY = 5
local GLITCH_MAX_DELAY = 10
local STATIC_FLICKER_MIN = 0.5
local STATIC_FLICKER_MAX = 0.7
local TAP_PULSE_TIME = 1.2
local FADE_OUT_TIME = 0.6

local isStarted = false
local introActive = false

local function resolveCameraPart(): BasePart?
	local map = Workspace:WaitForChild("Map", 30)
	if not map then
		return nil
	end
	local sewer = map:WaitForChild("Sewer", 30)
	if not sewer then
		return nil
	end
	local camPart = sewer:WaitForChild("Intro_Camera", 30)
	if camPart and camPart:IsA("BasePart") then
		return camPart
	end
	return nil
end

local function startCamera(camPart: BasePart)
	local smoothMouse = Vector2.zero
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		local viewport = camera.ViewportSize
		local target = Vector2.zero
		if viewport.X > 0 and viewport.Y > 0 then
			local mouse = UserInputService:GetMouseLocation()
			target = Vector2.new(
				math.clamp((mouse.X / viewport.X) * 2 - 1, -1, 1),
				math.clamp((mouse.Y / viewport.Y) * 2 - 1, -1, 1)
			)
		end
		local alpha = math.min(deltaTime * CAM_MOUSE_SMOOTHING, 1)
		smoothMouse = smoothMouse:Lerp(target, alpha)
		camera.CFrame = camPart.CFrame
			* CFrame.Angles(-smoothMouse.Y * CAM_MOUSE_TILT, -smoothMouse.X * CAM_MOUSE_TILT, 0)
	end)
end

local function stopCamera()
	pcall(function()
		RunService:UnbindFromRenderStep(CAMERA_BIND)
	end)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function runGlitchLoop(label: GuiObject, transparencyProperty: string)
	local target = label :: any
	task.spawn(function()
		while introActive do
			task.wait(math.random(GLITCH_MIN_DELAY, GLITCH_MAX_DELAY))
			if not introActive then
				break
			end
			local basePosition = label.Position
			local offsetY = math.random(-5, 5)
			label.Position = basePosition + UDim2.fromOffset(0, offsetY)
			target[transparencyProperty] = math.random() * 0.3
			task.wait(0.1)
			label.Position = basePosition
			target[transparencyProperty] = 0
		end
	end)
end

local function runStaticFlicker(vhs2: ImageLabel)
	task.spawn(function()
		while introActive do
			vhs2.ImageTransparency = STATIC_FLICKER_MIN
				+ math.random() * (STATIC_FLICKER_MAX - STATIC_FLICKER_MIN)
			task.wait(0.08 + math.random() * 0.07)
		end
	end)
end

local function runScanlineBob(vhs1: ImageLabel)
	local basePosition = vhs1.Position
	local bobInfo = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(vhs1, bobInfo, {
		Position = basePosition + UDim2.fromScale(0, 0.03),
	})
	tween:Play()
	return tween
end

local function runTapPulse(tapText: TextLabel)
	local pulseInfo = TweenInfo.new(TAP_PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(tapText, pulseInfo, { TextTransparency = 0.5 })
	tween:Play()
	return tween
end

local function waitForLoadingDone()
	local player = Players.LocalPlayer
	if player:GetAttribute(LOADING_DONE_ATTRIBUTE) then
		return
	end
	local elapsed = 0
	while not player:GetAttribute(LOADING_DONE_ATTRIBUTE) and elapsed < LOADING_DONE_TIMEOUT do
		elapsed += task.wait(0.1)
	end
end

local function waitForContinue()
	local continued = false
	local connection
	connection = UserInputService.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			continued = true
		end
	end)
	while not continued do
		task.wait()
	end
	connection:Disconnect()
end

local function fadeOutIntro(introGui: ScreenGui, activeTweens: { Tween })
	for _, tween in activeTweens do
		tween:Cancel()
	end

	local fadeInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	local tweens = {}
	for _, descendant in introGui:GetDescendants() do
		if descendant:IsA("TextLabel") then
			table.insert(tweens, TweenService:Create(descendant, fadeInfo, { TextTransparency = 1 }))
		elseif descendant:IsA("ImageLabel") then
			table.insert(
				tweens,
				TweenService:Create(descendant, fadeInfo, { ImageTransparency = 1, BackgroundTransparency = 1 })
			)
		end
	end
	for _, tween in tweens do
		tween:Play()
	end
	task.wait(FADE_OUT_TIME)
	introGui.Enabled = false
end

local function runIntro()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local camPart = resolveCameraPart()
	if camPart then
		startCamera(camPart)
	end

	waitForLoadingDone()

	local introGui = playerGui:WaitForChild("Intro_Screen", 10)
	if not introGui then
		stopCamera()
		return
	end

	introGui.ResetOnSpawn = false
	local frame = introGui:WaitForChild("Frame")
	local vhs1 = frame:WaitForChild("VHS1")
	local vhs2 = frame:WaitForChild("VHS2")
	local tapText = introGui:WaitForChild("Tap_Text")
	local logo = introGui:WaitForChild("ImageLabel")

	introActive = true
	introGui.Enabled = true

	local activeTweens = {
		runScanlineBob(vhs1),
		runTapPulse(tapText),
	}
	runStaticFlicker(vhs2)
	runGlitchLoop(tapText, "TextTransparency")
	runGlitchLoop(logo, "ImageTransparency")

	waitForContinue()

	introActive = false
	Blink.RequestSpawn.Fire()
	fadeOutIntro(introGui, activeTweens)
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	stopCamera()
end

function IntroController.start()
	if isStarted then
		return
	end
	isStarted = true
	task.spawn(runIntro)
end

return IntroController
