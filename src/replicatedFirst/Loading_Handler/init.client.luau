-- These lines grab tools we need from Roblox
local Players = game:GetService("Players")       -- tool to find the player
local ts = game:GetService("TweenService")       -- tool that makes things fade/move smoothly
local Lighting = game:GetService("Lighting")     -- tool to control lighting effects
local StarterGui = game:GetService("StarterGui") -- tool to control the built-in Roblox UI

-- Hide the Roblox UI (player list, chat, backpack...) until the intro is fully over;
-- the intro screen turns it back on after the player taps to continue
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Find the player and their screen
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")  -- this is like their screen

-- Show the preloading screen (the little falling character) straight away, on top of everything
local preloadGui = ReplicatedFirst:WaitForChild("PRELOADING")
preloadGui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen() -- swap Roblox's default loading spinner for ours right away
local preloadStart = os.clock()
local PRELOAD_MIN_TIME = 2.5 -- keep the preloading screen up at least this long so the animation is seen
local PRELOAD_MAX_TIME = 20 -- don't hold the player forever if an asset refuses to load
local PRELOAD_TESTING_MODE = true -- true = hold the preloading screen forever so it can be edited live; set false for the real flow

-- Actually preload the credits, intro screen, and intro sounds while the preloading screen is up,
-- so nothing pops in late once the real loading screen and the intro start
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local preloadFinished = false
task.spawn(function()
	local toPreload = {}
	local function addWithDescendants(root)
		if not root then
			return
		end
		table.insert(toPreload, root)
		for _, descendant in root:GetDescendants() do
			table.insert(toPreload, descendant)
		end
	end
	addWithDescendants(script:WaitForChild("LoadingScreen"))
	addWithDescendants(StarterGui:WaitForChild("Intro_Screen", 10))
	addWithDescendants(SoundService)
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	addWithDescendants(assets and assets:FindFirstChild("Animations"))
	addWithDescendants(assets and assets:FindFirstChild("Sounds"))
	ContentProvider:PreloadAsync(toPreload)
	preloadFinished = true
end)

-- Start the falling animation on the viewport character as soon as the animation asset replicates
local fallingTrack
task.spawn(function()
	local viewport = preloadGui:FindFirstChild("ViewportFrame")
	local worldModel = viewport and viewport:FindFirstChild("WorldModel")
	local rig = worldModel and worldModel:FindFirstChild("Falling_Rig")
	if not rig then
		return
	end

	-- Lay the rig out for the fall (flat on his back by default).
	-- Tweak the pose with the RigPitch / RigYaw / RigRoll attributes (degrees) on the ViewportFrame.
	local rigPitch = math.rad(viewport:GetAttribute("RigPitch") or 90)
	local rigYaw = math.rad(viewport:GetAttribute("RigYaw") or 0)
	local rigRoll = math.rad(viewport:GetAttribute("RigRoll") or 0)
	rig:PivotTo(CFrame.new(rig:GetPivot().Position) * CFrame.fromOrientation(rigPitch, rigYaw, rigRoll))

	-- Aim the viewport camera at wherever the rig currently is, so moving the rig in Studio never loses it.
	-- Tweak the angle with the CameraDistance / CameraHeight / CameraYaw attributes on the ViewportFrame
	-- (CameraYaw 90 = side profile view).
	local camera = viewport.CurrentCamera or Instance.new("Camera")
	camera.Name = "ViewportCamera"
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local center = rig:GetBoundingBox().Position
	local distance = viewport:GetAttribute("CameraDistance") or 6
	local height = viewport:GetAttribute("CameraHeight") or 0.2
	local yaw = math.rad(viewport:GetAttribute("CameraYaw") or 90)
	local offset = CFrame.fromAxisAngle(Vector3.yAxis, yaw) * Vector3.new(0, height, -distance)
	camera.CFrame = CFrame.lookAt(center + offset, center)

	-- Make him actually tumble while he falls: a steady head-over-heels spin around the body's own
	-- center (so he stays in frame) plus a gentle side-to-side wobble. TumbleSpeed is degrees per
	-- second and TumbleWobble is the wobble angle in degrees, both attributes on the ViewportFrame.
	local tumbleSpeed = math.rad(viewport:GetAttribute("TumbleSpeed") or 45)
	local tumbleWobble = math.rad(viewport:GetAttribute("TumbleWobble") or 12)
	local basePivot = rig:GetPivot()
	local baseRotation = basePivot.Rotation
	local centerOffset = basePivot:PointToObjectSpace(center)
	local tumbleTime = 0
	local tumbleConnection
	tumbleConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not preloadGui.Parent then
			tumbleConnection:Disconnect()
			return
		end
		tumbleTime += deltaTime
		local spin = CFrame.Angles(tumbleTime * tumbleSpeed, 0, math.sin(tumbleTime * 0.7) * tumbleWobble)
		local rotation = spin * baseRotation
		rig:PivotTo(CFrame.new(center - rotation * centerOffset) * rotation)
	end)

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animation = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("Rig"):WaitForChild("LoadFallingAnim")
	fallingTrack = animator:LoadAnimation(animation)
	fallingTrack.Looped = true
	fallingTrack:Play()
end)

-- Grab our intro screen and put it on the player's screen so they can see it
local introGui = script:WaitForChild("LoadingScreen")
introGui.Parent = playerGui

-- Grab the background box and the text inside it
local bgFrame = introGui:WaitForChild("BGFrame")
local text = bgFrame:WaitForChild("mainText")
local sound = bgFrame.textSound

-- Wait here until the whole game is ready, the assets are preloaded (or we hit the cap),
-- and the preloading screen has had its minimum time on screen
repeat
	task.wait()
until game:IsLoaded()
	and os.clock() - preloadStart >= PRELOAD_MIN_TIME
	and (preloadFinished or os.clock() - preloadStart >= PRELOAD_MAX_TIME)

-- TESTING MODE: park here forever so the preloading screen stays up for live editing
if PRELOAD_TESTING_MODE then
	while true do
		task.wait(1)
	end
end

-- Fade the preloading screen away to reveal the credits waiting underneath
local preloadFade = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local preloadFrame = preloadGui:FindFirstChild("Frame")
local preloadViewport = preloadGui:FindFirstChild("ViewportFrame")
if preloadFrame then
	ts:Create(preloadFrame, preloadFade, {BackgroundTransparency = 1}):Play()
end
if preloadViewport then
	ts:Create(preloadViewport, preloadFade, {ImageTransparency = 1}):Play()
end
task.delay(1.1, function()
	if fallingTrack then
		fallingTrack:Stop()
	end
	preloadGui:Destroy()
end)

-- Make the special camera effects ourselves, so the game stays normal until the intro starts
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Saturation = 0  -- start normal so the fade to gray can grow in smoothly
colorCorrection.Parent = Lighting

local blur = Instance.new("BlurEffect")
blur.Size = 0  -- start at 0 so it can smoothly grow in, instead of popping in at full strength
blur.Parent = Lighting

-- Smoothly grow the vignette in (blur + saturation) instead of snapping to full strength instantly
ts:Create(blur, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = 15}):Play()
ts:Create(colorCorrection, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Saturation = -1}):Play()

-- These control how smooth the fading looks
local fadeIn = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)  -- fading IN (appearing)
local fadeOut = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.In)  -- fading OUT (disappearing)

-- This is our own mini-tool: it fades out old text, puts in new text, then fades it back in
local function showLine(newText, holdTime)
	if text.TextTransparency < 1 then
		-- fade the old words away first
		ts:Create(text, fadeOut, {TextTransparency = 1}):Play()
		task.wait(0.9)
	end
	text.Text = newText -- change the words
	ts:Create(text, fadeIn, {TextTransparency = 0}):Play() -- fade the new words in
	task.wait(holdTime) -- leave them on screen for a bit
end

-- Start with no words showing
text.TextTransparency = 1

-- Slowly turn the background dark gray
ts:Create(bgFrame, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundColor3 = Color3.fromRGB(17,17,17)}):Play()

if not game:IsLoaded() then
	game.Loaded:Wait()
end

sound:Play() -- start the loading screen music
task.wait(2.5) -- wait a bit before words show up

-- Show each line, one after another
showLine("Compact alliance presents to you", 3)
showLine("Behind Every Wall", 3.2)
showLine("Produced by Jxsonxn and Zenokei", 3.2)
showLine("2 Extremely hard working developers", 3.2)
showLine("Enjoy.", 3.2)

-- Turn the background all the way black
ts:Create(bgFrame, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundColor3 = Color3.fromRGB(0,0,0)}):Play()

-- Make the last words fade away
ts:Create(text, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {TextTransparency = 1}):Play()

-- Fade the sound out smoothly instead of cutting off abruptly
ts:Create(sound, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Volume = 0}):Play()

task.wait(2.5) -- wait for those to finish

-- Tell the intro screen we're done, so it can appear underneath before we fade away
player:SetAttribute("LoadingScreenDone", true)

ts:Create(bgFrame.vignette, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {ImageTransparency = 1}):Play()
-- Make the whole box disappear
ts:Create(bgFrame, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 1}):Play()

-- Slowly undo the special camera effects so the game looks normal again, with a smoother ease
ts:Create(colorCorrection, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Saturation = 0}):Play()
ts:Create(blur, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = 1}):Play()

task.wait(5) -- wait a bit more

introGui:Destroy() -- get rid of the intro screen, we don't need it anymore
sound:Stop() -- make sure it's fully stopped (Volume 0 doesn't free it up)
colorCorrection:Destroy() -- also remove the effects completely so nothing lingers
blur:Destroy()
