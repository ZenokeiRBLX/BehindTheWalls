local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))
local IntroScene = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("IntroScene"))

local IntroController = {}

local CAMERA_BIND = "IntroCamera"
local CAM_MOUSE_TILT = math.rad(2.5)
local CAM_MOUSE_SMOOTHING = 3.5
local LOADING_DONE_ATTRIBUTE = "LoadingScreenDone"
local LOADING_DONE_TIMEOUT = 90
local GLITCH_MIN_DELAY = 3
local GLITCH_MAX_DELAY = 6
local VHS_BOB_TIME = 1.2
local STATIC_FLICKER_MIN = 0.5
local STATIC_FLICKER_MAX = 0.7
local TAP_PULSE_TIME = 1.1
local FOV_MIN = 56
local FOV_MAX = 67
local FOV_DRIFT_MIN = 6
local FOV_DRIFT_MAX = 11
local LOGO_SHAKE_PIXELS = 1
local LOGO_SHAKE_ROTATION = 0.2
local FADE_OUT_TIME = 0.6
local TRANSITION_IN_TIME = 0.35
local TRANSITION_OUT_TIME = 0.8
local TRANSITION_HOLD_TIME = 0.3

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

local savedFov: number?

local function startCamera(camPart: BasePart)
	local smoothMouse = Vector2.zero
	local startCam = Workspace.CurrentCamera
	savedFov = startCam and startCam.FieldOfView or 70
	local currentFov = savedFov :: number
	local fovStart = currentFov
	local fovTarget = currentFov
	local clock = 0
	local fovStartTime = 0
	local fovEndTime = 0
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable

		clock += deltaTime
		if clock >= fovEndTime then
			fovStart = currentFov
			fovTarget = FOV_MIN + math.random() * (FOV_MAX - FOV_MIN)
			fovStartTime = clock
			fovEndTime = clock + FOV_DRIFT_MIN + math.random() * (FOV_DRIFT_MAX - FOV_DRIFT_MIN)
		end
		local span = fovEndTime - fovStartTime
		local progress = if span > 0 then math.clamp((clock - fovStartTime) / span, 0, 1) else 1
		local eased = progress * progress * (3 - 2 * progress)
		currentFov = fovStart + (fovTarget - fovStart) * eased
		camera.FieldOfView = currentFov
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
	if savedFov then
		camera.FieldOfView = savedFov
	end
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
			task.wait(0.04 + math.random() * 0.04)
		end
	end)
end

local function runScanlineBob(vhs1: ImageLabel)
	local basePosition = vhs1.Position
	local bobInfo = TweenInfo.new(VHS_BOB_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(vhs1, bobInfo, {
		Position = basePosition + UDim2.fromScale(0, 0.03),
	})
	tween:Play()
	return tween
end

local function runTapPulse(tapText: TextLabel)
	local pulseInfo = TweenInfo.new(TAP_PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(tapText, pulseInfo, { TextTransparency = 0.85 })
	tween:Play()
	return tween
end

local function runLogoShake(logo: ImageLabel)
	local basePosition = logo.Position
	local baseRotation = logo.Rotation
	task.spawn(function()
		while introActive do
			logo.Position = basePosition
				+ UDim2.fromOffset(math.random(-LOGO_SHAKE_PIXELS, LOGO_SHAKE_PIXELS), math.random(-LOGO_SHAKE_PIXELS, LOGO_SHAKE_PIXELS))
			logo.Rotation = baseRotation + (math.random() - 0.5) * 2 * LOGO_SHAKE_ROTATION
			task.wait(0.15 + math.random() * 0.2)
		end
		logo.Position = basePosition
		logo.Rotation = baseRotation
	end)
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

local function playBlackTransition(playerGui: PlayerGui): () -> ()
	local transitionGui = Instance.new("ScreenGui")
	transitionGui.Name = "Black_Transition"
	transitionGui.IgnoreGuiInset = true
	transitionGui.ResetOnSpawn = false
	transitionGui.DisplayOrder = 200
	transitionGui.Parent = playerGui

	local cover = Instance.new("Frame")
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.Parent = transitionGui

	local fadeIn = TweenService:Create(
		cover,
		TweenInfo.new(TRANSITION_IN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0 }
	)
	fadeIn:Play()
	fadeIn.Completed:Wait()

	return function()
		local fadeOut = TweenService:Create(
			cover,
			TweenInfo.new(TRANSITION_OUT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Wait()
		transitionGui:Destroy()
	end
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
	introGui:Destroy()
end

local function runIntro()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local camPart = resolveCameraPart()
	if camPart then
		startCamera(camPart)
	end
	IntroScene.begin()

	waitForLoadingDone()

	local introGui = playerGui:FindFirstChild("Intro_Screen")
	if not introGui then
		local template = StarterGui:FindFirstChild("Intro_Screen")
		if template then
			introGui = template:Clone()
			introGui.Parent = playerGui
		end
	end
	if not introGui then
		stopCamera()
		IntroScene.finish()
		return
	end

	introGui.ResetOnSpawn = false
	local frame = introGui:FindFirstChild("Frame")
	local vhs1 = frame and frame:FindFirstChild("VHS1")
	local vhs2 = frame and frame:FindFirstChild("VHS2")
	local tapText = introGui:FindFirstChild("Tap_Text")
	local logo = introGui:FindFirstChild("Game_Logo") or introGui:FindFirstChild("ImageLabel")

	introActive = true
	introGui.Enabled = true
	IntroScene.setRevealed()

	local activeTweens = {}
	if vhs1 and vhs1:IsA("ImageLabel") then
		table.insert(activeTweens, runScanlineBob(vhs1))
	end
	if vhs2 and vhs2:IsA("ImageLabel") then
		runStaticFlicker(vhs2)
	end
	if tapText and tapText:IsA("TextLabel") then
		table.insert(activeTweens, runTapPulse(tapText))
		runGlitchLoop(tapText, "TextTransparency")
	end
	if logo and logo:IsA("ImageLabel") then
		runLogoShake(logo)
		runGlitchLoop(logo, "ImageTransparency")
	end

	waitForContinue()

	introActive = false
	local removeTransition = playBlackTransition(playerGui)
	Blink.RequestSpawn.Fire()
	fadeOutIntro(introGui, activeTweens)
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	stopCamera()
	IntroScene.finish()
	task.wait(TRANSITION_HOLD_TIME)
	removeTransition()
end

function IntroController.start()
	if isStarted then
		return
	end
	isStarted = true
	task.spawn(runIntro)
end

return IntroController
