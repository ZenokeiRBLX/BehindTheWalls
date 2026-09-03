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

-- Find the player and their screen
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")  -- this is like their screen

-- Show the preloading screen (the little falling character) straight away, on top of everything
local preloadGui = ReplicatedFirst:WaitForChild("PRELOADING")
preloadGui.Parent = playerGui
local preloadStart = os.clock()
local PRELOAD_MIN_TIME = 2.5 -- keep the preloading screen up at least this long so the animation is seen

-- Start the falling animation on the viewport character as soon as the animation asset replicates
local fallingTrack
task.spawn(function()
	local viewport = preloadGui:FindFirstChild("ViewportFrame")
	local worldModel = viewport and viewport:FindFirstChild("WorldModel")
	local rig = worldModel and worldModel:FindFirstChild("Falling_Rig")
	local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
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

-- Wait here until the whole game is ready (and the preloading screen has had its minimum time)
repeat task.wait() until game:IsLoaded() and os.clock() - preloadStart >= PRELOAD_MIN_TIME

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
