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

-- The light shining down into the hole is steady: it only breathes very slowly between 0.55 and 0.65
-- transparency, like a distant lamp whose glow drifts a touch (it may still be replicating in)
local LIGHT_STEADY_MIN = 0.55
local LIGHT_STEADY_MAX = 0.65
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

-- The hourglass flips when the character drops into it: one smooth full turn from wherever its
-- lean left it. The fall loop below leans it gradually as he approaches, then calls spinHourGlass
-- the moment he is in. (The hourglass may still be replicating in when we get here.)
local spinHourGlass = nil
task.spawn(function()
	local hourGlass = preloadGui:WaitForChild("Hour_Glass", 10)
	if not hourGlass or not hourGlass:IsA("GuiObject") then
		return
	end
	local baseRotation = hourGlass.Rotation
	local spinning = false
	local function spinTo(rotation, duration, style, direction)
		local tween = ts:Create(hourGlass, TweenInfo.new(duration, style, direction), {Rotation = rotation})
		tween:Play()
		tween.Completed:Wait()
	end
	spinHourGlass = function()
		if spinning then
			return
		end
		spinning = true
		task.spawn(function()
			spinTo(baseRotation + 360, 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) -- the flip
			hourGlass.Rotation = baseRotation
			spinning = false
		end)
	end
end)
ReplicatedFirst:RemoveDefaultLoadingScreen() -- swap Roblox's default loading spinner for ours right away
local preloadStart = os.clock()
local PRELOAD_MIN_TIME = 5 -- keep the preloading screen up at least this long so the animation is seen
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
local fallRunning = false -- true once the fall loop is driving the viewport
local fallCyclesDone = 0 -- counts every time he has fully dropped into the hourglass
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
	local tumbleSpeed = math.rad(viewport:GetAttribute("TumbleSpeed") or 70)
	local tumbleWobble = math.rad(viewport:GetAttribute("TumbleWobble") or 12)
	local basePivot = rig:GetPivot()
	local baseRotation = basePivot.Rotation
	local centerOffset = basePivot:PointToObjectSpace(center)
	-- The fall itself, in phases that repeat:
	--   1. FALL:  he starts small up by the light and drops toward the TOP of the hourglass, growing
	--             as he gets closer (FallDuration seconds, FallStartScale -> FallEndScale)
	--   2. ENTER: the moment he reaches the top of the glass he shrinks quickly down into it
	--             (FALL_ENTER_SECONDS, down to FallEnterScale) and disappears
	--   3. SPIN:  the hourglass flips in response while he is inside
	--   4. REST:  a short beat, then he starts over from the light
	-- FallDuration / FallStartScale / FallEndScale / FallEnterScale are attributes on the ViewportFrame;
	-- FallDrop is only used if there is no Hour_Glass to aim for.
	local FALL_ENTER_SECONDS = 0.3
	local FALL_SPIN_SECONDS = 1.0
	local FALL_REST_SECONDS = 0.3
	local fallDuration = viewport:GetAttribute("FallDuration") or 3.5
	local fallStartScale = viewport:GetAttribute("FallStartScale") or 0.45
	local fallEndScale = viewport:GetAttribute("FallEndScale") or 1.2
	local fallEnterScale = viewport:GetAttribute("FallEnterScale") or 0.1
	local fallDrop = viewport:GetAttribute("FallDrop") or 0.45
	local designedSize = viewport.Size
	local designedPosition = viewport.Position

	-- Where the drop ends: the top edge of the hourglass (minus a bit so his feet touch it first),
	-- and where he enters to: its center. The hourglass draws on top so he slips in behind the glass.
	local fallTopPosition = designedPosition + UDim2.fromScale(0, fallDrop)
	local fallEnterPosition = fallTopPosition
	local HOURGLASS_LEAN_DEGREES = 14 -- how far the hourglass tips back as he closes in on it
	local hourGlass = preloadGui:FindFirstChild("Hour_Glass")
	local hourGlassBaseRotation = 0
	if hourGlass and hourGlass:IsA("GuiObject") then
		local viewportEndHeight = designedSize.Y.Scale * fallEndScale
		fallTopPosition = hourGlass.Position - UDim2.fromScale(0, hourGlass.Size.Y.Scale / 2 + viewportEndHeight * 0.25)
		fallEnterPosition = hourGlass.Position
		hourGlass.ZIndex = viewport.ZIndex + 1
		hourGlassBaseRotation = hourGlass.Rotation
	end

	local function applyViewport(position, scale, transparency)
		viewport.Position = position
		viewport.Size = UDim2.new(
			designedSize.X.Scale * scale, designedSize.X.Offset * scale,
			designedSize.Y.Scale * scale, designedSize.Y.Offset * scale
		)
		viewport.ImageTransparency = transparency
	end

	local cycleLength = fallDuration + FALL_ENTER_SECONDS + FALL_SPIN_SECONDS + FALL_REST_SECONDS
	local tumbleTime = 0
	local lastCycleTime = 0
	local spinTriggered = false
	local tumbleConnection
	fallRunning = true
	tumbleConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if preloadExiting or not preloadGui.Parent then
			tumbleConnection:Disconnect()
			return
		end
		tumbleTime += deltaTime
		local spin = CFrame.Angles(tumbleTime * tumbleSpeed, 0, math.sin(tumbleTime * 0.7) * tumbleWobble)
		local rotation = spin * baseRotation
		rig:PivotTo(CFrame.new(center - rotation * centerOffset) * rotation)

		local cycleTime = tumbleTime % cycleLength
		if cycleTime < lastCycleTime then
			fallCyclesDone += 1 -- a full fall, entry, and flip just finished; he restarts from the light
			spinTriggered = false
		end
		lastCycleTime = cycleTime

		if cycleTime < fallDuration then
			local progress = cycleTime / fallDuration
			local growth = progress * progress -- grows faster the closer he gets, like real perspective
			local scale = fallStartScale + (fallEndScale - fallStartScale) * growth
			local fadeIn = math.min(progress / 0.12, 1)
			applyViewport(designedPosition:Lerp(fallTopPosition, progress), scale, 1 - fadeIn)
			if hourGlass then
				-- tips back more and more the closer he gets, ready for the flip
				hourGlass.Rotation = hourGlassBaseRotation - HOURGLASS_LEAN_DEGREES * (progress * progress)
			end
		elseif cycleTime < fallDuration + FALL_ENTER_SECONDS then
			local progress = (cycleTime - fallDuration) / FALL_ENTER_SECONDS
			local dive = progress * progress -- drops into the glass faster and faster
			local scale = fallEndScale + (fallEnterScale - fallEndScale) * dive
			local fadeOut = math.clamp((progress - 0.7) / 0.3, 0, 1) -- only vanish at the very end
			applyViewport(fallTopPosition:Lerp(fallEnterPosition, dive), scale, fadeOut)
		else
			applyViewport(fallEnterPosition, fallEnterScale, 1)
			if not spinTriggered then
				spinTriggered = true
				if spinHourGlass then
					spinHourGlass()
				end
			end
		end
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

-- Let him finish his current fall into the hourglass before we move on, so he is never cut off mid-air
if fallRunning then
	local cyclesAtReady = fallCyclesDone
	local waitStart = os.clock()
	repeat
		task.wait()
	until fallCyclesDone > cyclesAtReady or os.clock() - waitStart > 10
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
ts:Create(blur, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = 15}):Play()
ts:Create(colorCorrection, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Saturation = -1}):Play()

-- This is our own mini-tool: it swaps the words in instantly (no fading), hard cut like a title card
local function showLine(newText)
	text.Text = newText -- change the words
	text.TextTransparency = 0 -- show them straight away
end

-- The credit lines, and how each one is timed to the music:
--  * LINE_CUE_TIMES: exact seconds into the track for each line. Fill one in once you know where a
--    high note lands and that line will appear right on it. A nil entry uses the hit detector.
--  * Hit detector: the next line appears when the music's loudness suddenly jumps above HIT_THRESHOLD
--    (the accented, higher-toned hits), but never sooner than HIT_MIN_GAP seconds after the previous
--    line so the words stay readable, and never later than HIT_MAX_WAIT so it can't stall.
local CREDIT_LINES = {
	"Compact alliance presents to you",
	"Behind Every Wall",
	"Produced by Jxsonxn and Zenokei",
	"2 Extremely hard working developers",
	"Enjoy.",
}
local LINE_CUE_TIMES = {36.30, 40.30, 44.30, 48.10, 52.30}
local HIT_THRESHOLD = 350 -- PlaybackLoudness runs 0-1000; lower this if lines never trigger, raise it if they trigger on every beat
local HIT_JUMP = 1.3 -- how much louder than a moment ago counts as a hit (1.3 = 30% louder)
local HIT_MIN_GAP = 1.6
local HIT_MAX_WAIT = 3

local function waitForCue(index)
	local cueTime = LINE_CUE_TIMES[index]
	if cueTime then
		repeat
			task.wait()
		until sound.TimePosition >= cueTime or not sound.IsPlaying
		return
	end
	local startedAt = os.clock()
	local lastLoudness = sound.PlaybackLoudness
	while os.clock() - startedAt < HIT_MAX_WAIT do
		local loudness = sound.PlaybackLoudness
		local gapPassed = os.clock() - startedAt >= HIT_MIN_GAP
		if gapPassed and loudness >= HIT_THRESHOLD and loudness >= lastLoudness * HIT_JUMP then
			return
		end
		lastLoudness = loudness
		task.wait(0.03)
	end
end

-- Start with no words showing
text.TextTransparency = 1

-- Slowly turn the background dark gray
ts:Create(bgFrame, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundColor3 = Color3.fromRGB(17,17,17)}):Play()

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- The track has a quiet 36 second intro before the big "dun dun" hits start, so we skip straight to
-- just before the first hit; the credit lines are pinned to the accent hits measured from the track
local MUSIC_START_TIME = 35.6
if not sound.IsLoaded then
	sound.Loaded:Wait()
end
sound.TimePosition = MUSIC_START_TIME
sound:Play() -- start the loading screen music

-- Show each line when the music cues it
for index, line in CREDIT_LINES do
	waitForCue(index)
	showLine(line)
end
task.wait(2) -- let the last line sit for a bit

-- Turn the background all the way black
ts:Create(bgFrame, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundColor3 = Color3.fromRGB(0,0,0)}):Play()

-- Cut the last words off instantly
text.TextTransparency = 1

-- Fade the sound out smoothly instead of cutting off abruptly
ts:Create(sound, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Volume = 0}):Play()

task.wait(1.5) -- wait for those to finish

-- Tell the intro screen we're done, so it can appear underneath before we fade away
player:SetAttribute("LoadingScreenDone", true)

ts:Create(bgFrame.vignette, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {ImageTransparency = 1}):Play()
-- Make the whole box disappear
ts:Create(bgFrame, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 1}):Play()

-- Slowly undo the special camera effects so the game looks normal again, with a smoother ease
ts:Create(colorCorrection, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Saturation = 0}):Play()
ts:Create(blur, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = 1}):Play()

task.wait(2) -- wait a bit more

introGui:Destroy() -- get rid of the intro screen, we don't need it anymore
sound:Stop() -- make sure it's fully stopped (Volume 0 doesn't free it up)
colorCorrection:Destroy() -- also remove the effects completely so nothing lingers
blur:Destroy()
