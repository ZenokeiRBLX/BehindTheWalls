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

-- Show the preloading screen (the little falling character) straight away, on top of everything.
-- It lives in StarterGui so it can be edited visually, but StarterGui only copies itself into PlayerGui
-- when the character spawns (which is after the intro), so we MOVE the original over ourselves.
-- Moving instead of cloning matters: the GUI's contents (the rig, its parts, constraints) are still
-- streaming in from the server at this point, and a clone would only copy what has arrived so far,
-- while the moved instance keeps receiving the rest. ReplicatedFirst is checked first in case it
-- ever gets moved back there.
local preloadGui = ReplicatedFirst:FindFirstChild("PRELOADING") or StarterGui:WaitForChild("PRELOADING")
preloadGui.Enabled = true
preloadGui.ResetOnSpawn = false
preloadGui.Parent = playerGui
local preloadExiting = false -- flips true when the preloading screen starts fading away

-- The light shining down into the hole is steady: it only breathes very slowly between 0.8 and 0.9
-- transparency, like a distant lamp whose glow drifts a touch (it may still be replicating in)
local LIGHT_STEADY_MIN = 0.8
local LIGHT_STEADY_MAX = 0.9
local LIGHT_BREATHE_SECONDS = 6
task.spawn(function()
	local lightImage = preloadGui:WaitForChild("Light_Falling", 10)
	if not lightImage or not lightImage:IsA("ImageLabel") then
		return
	end
	local startTime = os.clock()
	while not preloadExiting and preloadGui.Parent do
		local breathe = (math.sin((os.clock() - startTime) / LIGHT_BREATHE_SECONDS * math.pi * 2) + 1) / 2
		lightImage.ImageTransparency = LIGHT_STEADY_MIN + (LIGHT_STEADY_MAX - LIGHT_STEADY_MIN) * breathe
		task.wait(0.1)
	end
end)

-- The hourglass wobbles like it is being nudged, winds up into a full spin that accelerates and
-- settles, bounces to a stop, rests, and does it all again (it may still be replicating in too)
task.spawn(function()
	local hourGlass = preloadGui:WaitForChild("Hour_Glass", 10)
	if not hourGlass or not hourGlass:IsA("GuiObject") then
		return
	end
	local baseRotation = hourGlass.Rotation
	local function spinTo(rotation, duration, style, direction)
		local tween = ts:Create(hourGlass, TweenInfo.new(duration, style, direction), {Rotation = rotation})
		tween:Play()
		tween.Completed:Wait()
	end
	while not preloadExiting and preloadGui.Parent do
		hourGlass.Rotation = baseRotation
		spinTo(baseRotation - 8, 0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) -- gentle lean
		spinTo(baseRotation + 10, 1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) -- easy sway back
		spinTo(baseRotation - 12, 1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) -- slow wind up
		spinTo(baseRotation + 360, 2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) -- one smooth full turn
		task.wait(1.5)
	end
end)
ReplicatedFirst:RemoveDefaultLoadingScreen() -- swap Roblox's default loading spinner for ours right away
local preloadStart = os.clock()
local PRELOAD_MIN_TIME = 2.5 -- keep the preloading screen up at least this long so the animation is seen
local PRELOAD_MAX_TIME = 20 -- don't hold the player forever if an asset refuses to load
local PRELOAD_TESTING_MODE = false -- true = hold the preloading screen forever so it can be edited live; false = the real flow

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
	-- MainText reports real progress: each asset the preloader finishes bumps the counter
	local mainText = preloadGui:WaitForChild("MainText", 10)
	local loadedCount = 0
	local function showProgress()
		if mainText and mainText:IsA("TextLabel") then
			mainText.Text = ("Loading... [Asset %d]"):format(loadedCount)
		end
	end
	showProgress()
	ContentProvider:PreloadAsync(toPreload, function()
		loadedCount += 1
		showProgress()
	end)
	preloadFinished = true
end)

-- Start the falling animation on the viewport character as soon as the animation asset replicates
local fallingTrack
task.spawn(function()
	local viewport = preloadGui:WaitForChild("ViewportFrame", 15)
	local worldModel = viewport and viewport:WaitForChild("WorldModel", 15)
	local rig = worldModel and worldModel:WaitForChild("Falling_Rig", 15)
	if not rig then
		return
	end

	-- The rig's parts stream in piece by piece; wait for the initial replication to finish so we
	-- pose, frame, and animate the complete character instead of half of one
	if not game:IsLoaded() then
		game.Loaded:Wait()
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
	-- The fall itself: the viewport starts small up by the light, then slowly drops and grows as he
	-- falls toward the screen, fading in at the top and out at the bottom before starting over.
	-- FallDuration (seconds), FallStartScale / FallEndScale (relative to the viewport's designed size),
	-- and FallDrop (how far down the screen he travels, in scale) are attributes on the ViewportFrame.
	local fallDuration = viewport:GetAttribute("FallDuration") or 6
	local fallStartScale = viewport:GetAttribute("FallStartScale") or 0.45
	local fallEndScale = viewport:GetAttribute("FallEndScale") or 1.2
	local fallDrop = viewport:GetAttribute("FallDrop") or 0.45
	-- Once he is FallShrinkStart of the way down he shrinks toward FallEnterScale, as if going into
	-- the hourglass, and fades away right as he reaches it
	local fallShrinkStart = viewport:GetAttribute("FallShrinkStart") or 0.7
	local fallEnterScale = viewport:GetAttribute("FallEnterScale") or 0.1
	local designedSize = viewport.Size
	local designedPosition = viewport.Position

	-- He falls from the light down INTO the hourglass: its center is where the drop ends and it draws
	-- on top of the viewport so he slips in behind the glass. FallDrop only applies if there is no
	-- Hour_Glass to aim for.
	local fallEndPosition = designedPosition + UDim2.fromScale(0, fallDrop)
	local hourGlass = preloadGui:FindFirstChild("Hour_Glass")
	if hourGlass and hourGlass:IsA("GuiObject") then
		fallEndPosition = hourGlass.Position
		hourGlass.ZIndex = viewport.ZIndex + 1
	end

	local tumbleTime = 0
	local tumbleConnection
	tumbleConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if preloadExiting or not preloadGui.Parent then
			tumbleConnection:Disconnect()
			return
		end
		tumbleTime += deltaTime
		local spin = CFrame.Angles(tumbleTime * tumbleSpeed, 0, math.sin(tumbleTime * 0.7) * tumbleWobble)
		local rotation = spin * baseRotation
		rig:PivotTo(CFrame.new(center - rotation * centerOffset) * rotation)

		local progress = (tumbleTime % fallDuration) / fallDuration
		local scale
		if progress < fallShrinkStart then
			local growProgress = progress / fallShrinkStart
			local growth = growProgress * growProgress -- grows faster the closer he gets, like real perspective
			scale = fallStartScale + (fallEndScale - fallStartScale) * growth
		else
			local shrinkProgress = (progress - fallShrinkStart) / (1 - fallShrinkStart)
			local shrink = shrinkProgress * shrinkProgress -- slips into the glass faster and faster
			scale = fallEndScale + (fallEnterScale - fallEndScale) * shrink
		end
		viewport.Size = UDim2.new(
			designedSize.X.Scale * scale, designedSize.X.Offset * scale,
			designedSize.Y.Scale * scale, designedSize.Y.Offset * scale
		)
		viewport.Position = designedPosition:Lerp(fallEndPosition, progress)
		local fadeIn = math.min(progress / 0.12, 1)
		local fadeOut = math.min((1 - progress) / 0.08, 1) -- only vanish at the very end, after the shrink
		viewport.ImageTransparency = 1 - math.min(fadeIn, fadeOut)
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
preloadExiting = true
local preloadFade = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
for _, element in preloadGui:GetDescendants() do
	if element:IsA("ViewportFrame") then
		ts:Create(element, preloadFade, {ImageTransparency = 1}):Play()
	elseif element:IsA("ImageLabel") then
		ts:Create(element, preloadFade, {ImageTransparency = 1, BackgroundTransparency = 1}):Play()
	elseif element:IsA("Frame") then
		ts:Create(element, preloadFade, {BackgroundTransparency = 1}):Play()
	elseif element:IsA("TextLabel") then
		ts:Create(element, preloadFade, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
	end
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
