local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Modules"):WaitForChild("Config"))
local Blink = require(ReplicatedStorage:WaitForChild("Blink"):WaitForChild("Client"))

local CutsceneController = {}

local CAMERA_PART_NAME = "Cutscene_Camera"
local CAMERA_PART_TIMEOUT = 30
local CAMERA_PART_POLL = 0.25
local CAMERA_BIND = "CutsceneCamera"
local FOV_ATTRIBUTE = "FieldOfView"
local CAMERA_CFRAME_ATTRIBUTE = "CutsceneCameraCFrame"
local CAMERA_FOV_ATTRIBUTE = "CutsceneCameraFov"
local PLAYERS_CFRAME_ATTRIBUTE = "CutscenePlayersCFrame"
local PATH_ATTRIBUTE_PREFIX = "CutscenePath"
local PRELOADED_ATTRIBUTE = "CutscenePreloaded"
local STREAM_TIMEOUT = 8
local GUI_NAME = "Cutscene"
local SKIP_BUTTON_NAME = "Cutscene_Skip"
local ARRIVAL_COMPLETE_ATTRIBUTE = "ArrivalComplete"
local ARRIVAL_WAIT_MARGIN = 15
local MAX_PATH_POINTS = 32
local ATTRIBUTE_TIMEOUT = 5

type Waypoint = {
	cframe: CFrame,
	weight: number,
}

type CameraTarget = {
	cframe: CFrame,
	fov: number?,
	part: BasePart?,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local cameraBound = false
local released = false
local savedFov: number?
local gui: ScreenGui?
local currentCFrame: CFrame? = nil
local currentFov: number? = nil
local flightToken = 0
local finished = false

local function findCameraPart(): BasePart?
	local part = Workspace:FindFirstChild(CAMERA_PART_NAME, true)
	return if part and part:IsA("BasePart") then part else nil
end

local function readTarget(): CameraTarget?
	local part = findCameraPart()
	if part then
		local fov = part:GetAttribute(FOV_ATTRIBUTE)
		return {
			cframe = part.CFrame,
			fov = if type(fov) == "number" then fov else nil,
			part = part,
		}
	end
	local published = Workspace:GetAttribute(CAMERA_CFRAME_ATTRIBUTE)
	if typeof(published) == "CFrame" then
		local fov = Workspace:GetAttribute(CAMERA_FOV_ATTRIBUTE)
		return {
			cframe = published,
			fov = if type(fov) == "number" then fov else nil,
			part = nil,
		}
	end
	return nil
end

local function waitForTarget(): CameraTarget?
	local deadline = os.clock() + CAMERA_PART_TIMEOUT
	while os.clock() < deadline do
		local target = readTarget()
		if target then
			return target
		end
		task.wait(CAMERA_PART_POLL)
	end
	warn("CutsceneController: Workspace." .. CAMERA_PART_NAME .. " not found")
	return nil
end

local function streamAround(position: Vector3)
	if not Workspace.StreamingEnabled then
		return
	end
	local ok, err = pcall(function()
		Players.LocalPlayer:RequestStreamAroundAsync(position, STREAM_TIMEOUT)
	end)
	if not ok then
		warn(("CutsceneController: RequestStreamAroundAsync failed: %s"):format(tostring(err)))
	end
end

local function bindCamera(target: CameraTarget)
	if cameraBound or released then
		return
	end
	cameraBound = true
	local camera = Workspace.CurrentCamera
	savedFov = if camera then camera.FieldOfView else nil
	currentCFrame = target.cframe
	currentFov = target.fov or Config.Cutscene.FieldOfView
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		local current = Workspace.CurrentCamera
		if not current then
			return
		end
		current.CameraType = Enum.CameraType.Scriptable
		current.CFrame = currentCFrame or target.cframe
		if type(currentFov) == "number" then
			current.FieldOfView = currentFov
		end
	end)
end

local function unbindCamera()
	if not cameraBound then
		return
	end
	cameraBound = false
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

local function readPlayersCFrame(): CFrame?
	local value = Workspace:GetAttribute(PLAYERS_CFRAME_ATTRIBUTE)
	return if typeof(value) == "CFrame" then value else nil
end

local function readPublishedPath(): { CFrame }
	local points = {}
	for index = 1, MAX_PATH_POINTS do
		local value = Workspace:GetAttribute(PATH_ATTRIBUTE_PREFIX .. index)
		if typeof(value) ~= "CFrame" then
			break
		end
		table.insert(points, value)
	end
	return points
end

local function flatForward(cframe: CFrame): Vector3
	local flat = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	return if flat.Magnitude > 0.001 then flat.Unit else -Vector3.zAxis
end

local function buildFlightPath(start: CFrame, players: CFrame?): { Waypoint }
	local settings = Config.Cutscene
	local waypoints: { Waypoint } = { { cframe = start, weight = 1 } }
	local published = readPublishedPath()
	if #published > 0 then
		for _, cframe in published do
			table.insert(waypoints, { cframe = cframe, weight = 1 })
		end
	else
		local forward = flatForward(if players then players else start)
		local groundY = if players then players.Position.Y else start.Position.Y - 6
		local origin = Vector3.new(start.Position.X, groundY, start.Position.Z)
		local distance = settings.SkimDistance
		local skimY = groundY + settings.SkimHeight
		local returnY = groundY + settings.ReturnHeight
		local points = {
			{ origin + forward * (distance * 0.3) + Vector3.new(0, skimY - groundY + 1, 0), origin + forward * (distance * 0.3 + 30) + Vector3.new(0, 2, 0) },
			{ origin + forward * (distance * 0.65) + Vector3.new(0, skimY - groundY, 0), origin + forward * (distance * 0.65 + 30) + Vector3.new(0, 2.5, 0) },
			{ origin + forward * distance + Vector3.new(0, skimY - groundY + 1.5, 0), origin + forward * (distance + 30) + Vector3.new(0, 3, 0) },
			{ origin + forward * (distance * 0.5) + Vector3.new(0, returnY - groundY, 0), origin + forward * (distance * 0.5 + 30) + Vector3.new(0, 2, 0) },
		}
		for _, pair in points do
			table.insert(waypoints, { cframe = CFrame.lookAt(pair[1], pair[2]), weight = 1 })
		end
	end
	table.insert(waypoints, { cframe = start, weight = 1.3 })
	return waypoints
end

local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

local function samplePath(waypoints: { Waypoint }, alpha: number): CFrame
	local count = #waypoints
	if count == 1 then
		return waypoints[1].cframe
	end
	local total = 0
	for index = 1, count - 1 do
		total += waypoints[index].weight
	end
	local distance = math.clamp(alpha, 0, 1) * total
	local segment = 1
	while segment < count - 1 and distance > waypoints[segment].weight do
		distance -= waypoints[segment].weight
		segment += 1
	end
	local t = math.clamp(distance / waypoints[segment].weight, 0, 1)
	local p0 = waypoints[math.max(segment - 1, 1)].cframe.Position
	local p1 = waypoints[segment].cframe.Position
	local p2 = waypoints[segment + 1].cframe.Position
	local p3 = waypoints[math.min(segment + 2, count)].cframe.Position
	local position = catmullRom(p0, p1, p2, p3, t)
	local rotation = waypoints[segment].cframe.Rotation:Lerp(waypoints[segment + 1].cframe.Rotation, t)
	return rotation + position
end

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function runFlight(waypoints: { Waypoint })
	flightToken += 1
	local myToken = flightToken
	local duration = Config.Cutscene.FlightSeconds
	local startTime = os.clock()
	while not released and flightToken == myToken do
		local elapsed = os.clock() - startTime
		local alpha = smoothstep(elapsed / duration)
		currentCFrame = samplePath(waypoints, alpha)
		if elapsed >= duration then
			break
		end
		RunService.RenderStepped:Wait()
	end
	if released or flightToken ~= myToken then
		return
	end
	task.wait(Config.Cutscene.HoldSeconds)
	if flightToken == myToken then
		CutsceneController.finish()
	end
end

local function resolveGui(playerGui: PlayerGui): ScreenGui?
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	for _, container in { ReplicatedFirst, StarterGui } do
		local template = container:FindFirstChild(GUI_NAME)
		if template and template:IsA("ScreenGui") then
			local clone = template:Clone()
			clone.Parent = playerGui
			return clone
		end
	end
	return nil
end

local function showGui(playerGui: PlayerGui)
	local screen = resolveGui(playerGui)
	gui = screen
	if not screen then
		return
	end
	screen.ResetOnSpawn = false
	screen.Enabled = true
	local skip = screen:FindFirstChild(SKIP_BUTTON_NAME, true)
	if skip and skip:IsA("GuiButton") then
		table.insert(connections, skip.Activated:Connect(function()
			CutsceneController.finish()
		end))
	end
end

local function waitForArrival(player: Player)
	if player:GetAttribute(ARRIVAL_COMPLETE_ATTRIBUTE) then
		return
	end
	local deadline = os.clock() + Config.Party.ArrivalTimeoutSeconds + Config.Party.MinLoadingSeconds + ARRIVAL_WAIT_MARGIN
	while not player:GetAttribute(ARRIVAL_COMPLETE_ATTRIBUTE) and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function preload(player: Player, waypoints: { Waypoint })
	local step = math.max(1, math.floor(#waypoints / 4))
	for index = 1, #waypoints, step do
		streamAround(waypoints[index].cframe.Position)
	end
	streamAround(waypoints[#waypoints].cframe.Position)
	player:SetAttribute(PRELOADED_ATTRIBUTE, true)
end

function CutsceneController.isActive(): boolean
	return isStarted and not released
end

function CutsceneController.release()
	if released then
		return
	end
	released = true
	finished = true
	flightToken += 1
	if gui then
		gui.Enabled = false
	end
	unbindCamera()
end

function CutsceneController.finish()
	if finished or released then
		return
	end
	finished = true
	flightToken += 1
	if gui then
		gui.Enabled = false
	end
	Blink.CutsceneFinished.Fire()
	task.spawn(function()
		local player = Players.LocalPlayer
		local deadline = os.clock() + Config.Cutscene.CharacterWaitSeconds
		while not released and os.clock() < deadline do
			local character = player.Character
			if character and character:FindFirstChild("HumanoidRootPart") and character.Parent then
				break
			end
			task.wait(0.1)
		end
		CutsceneController.release()
	end)
end

function CutsceneController.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

		table.insert(connections, playerGui.ChildAdded:Connect(function(child)
			if child.Name ~= GUI_NAME or not child:IsA("ScreenGui") then
				return
			end
			if released or (gui ~= nil and child ~= gui) then
				task.defer(function()
					child.Enabled = false
				end)
			end
		end))
		local early = playerGui:FindFirstChild(GUI_NAME)
		if early and early:IsA("ScreenGui") then
			early.Enabled = false
		end

		local target = waitForTarget()
		if not target then
			player:SetAttribute(PRELOADED_ATTRIBUTE, true)
			return
		end
		bindCamera(target)
		local attributeDeadline = os.clock() + ATTRIBUTE_TIMEOUT
		while os.clock() < attributeDeadline and not readPlayersCFrame() do
			task.wait(CAMERA_PART_POLL)
		end
		local waypoints = buildFlightPath(target.cframe, readPlayersCFrame())
		preload(player, waypoints)
		waitForArrival(player)
		if released then
			return
		end
		showGui(playerGui)
		runFlight(waypoints)
	end)
end

function CutsceneController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	CutsceneController.release()
end

return CutsceneController
