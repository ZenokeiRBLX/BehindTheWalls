local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FootstepsController = {}

local STRIDE_LENGTH = 4.4
local MIN_MOVE_SPEED = 1
local STEP_PITCH_MIN = 0.965
local STEP_PITCH_JITTER = 0.1
local LAND_PITCH_MIN = 0.85
local LAND_PITCH_JITTER = 0.1
local LAND_MIN_SPEED = 30
local SOUND_LIFETIME = 5
local CULL_DISTANCE = 150
local CULL_DISTANCE_SQ = CULL_DISTANCE * CULL_DISTANCE
local DEFAULT_ROLLOFF_MIN = 5
local DEFAULT_ROLLOFF_MAX = 60
local DEFAULT_FOLDER_NAMES = { "Stone", "Concrete", "Default", "Ground" }

local MATERIAL_FOLDER_ALIASES: { [Enum.Material]: string } = {
	[Enum.Material.Grass] = "Grass",
	[Enum.Material.LeafyGrass] = "Grass",
	[Enum.Material.Mud] = "Grass",
	[Enum.Material.Ground] = "Grass",
	[Enum.Material.Snow] = "Snow",
	[Enum.Material.Glacier] = "Snow",
	[Enum.Material.Sand] = "Sand",
	[Enum.Material.Wood] = "Wood",
	[Enum.Material.WoodPlanks] = "Wood",
	[Enum.Material.Metal] = "Metal",
	[Enum.Material.DiamondPlate] = "Metal",
	[Enum.Material.CorrodedMetal] = "Metal",
	[Enum.Material.Concrete] = "Concrete",
	[Enum.Material.Cobblestone] = "Stone",
	[Enum.Material.Brick] = "Stone",
	[Enum.Material.Slate] = "Stone",
	[Enum.Material.Rock] = "Stone",
	[Enum.Material.Basalt] = "Stone",
	[Enum.Material.Water] = "Water",
}

type TrackedCharacter = {
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	lastPosition: Vector3,
	distanceSinceStep: number,
	connections: { RBXScriptConnection },
}

local isStarted = false
local footstepsFolder: Instance?
local missingWarned: { [string]: boolean } = {}
local tracked: { [Model]: TrackedCharacter } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local heartbeatConnection: RBXScriptConnection?
local playerAddedConnection: RBXScriptConnection?
local playerRemovingConnection: RBXScriptConnection?

local function resolveFootstepsFolder(): Instance?
	local assets = ReplicatedStorage:WaitForChild("Assets", 30)
	if not assets then
		return nil
	end
	local sounds = assets:WaitForChild("Sounds", 30)
	if not sounds then
		return nil
	end
	return sounds:WaitForChild("Footsteps", 30)
end

local function collectSounds(container: Instance): { Sound }
	local found = {}
	if container:IsA("Sound") then
		table.insert(found, container)
		return found
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("Sound") then
			table.insert(found, descendant)
		end
	end
	return found
end

local function findMaterialContainer(material: Enum.Material): Instance?
	local folder = footstepsFolder
	if not folder then
		return nil
	end

	local exact = folder:FindFirstChild(material.Name)
	if exact then
		return exact
	end

	local alias = MATERIAL_FOLDER_ALIASES[material]
	local aliased = alias and folder:FindFirstChild(alias)
	if aliased then
		return aliased
	end

	for _, name in DEFAULT_FOLDER_NAMES do
		local fallback = folder:FindFirstChild(name)
		if fallback then
			return fallback
		end
	end

	return folder
end

local function pickVariant(material: Enum.Material): Sound?
	local container = findMaterialContainer(material)
	if not container then
		return nil
	end

	local variants = collectSounds(container)
	if #variants == 0 and container ~= footstepsFolder and footstepsFolder then
		variants = collectSounds(footstepsFolder)
	end
	if #variants == 0 then
		if not missingWarned[material.Name] then
			missingWarned[material.Name] = true
			warn(("FootstepsController found no Sound for material %s under %s"):format(material.Name, container:GetFullName()))
		end
		return nil
	end
	return variants[math.random(1, #variants)]
end

local function playVariant(template: Sound, rootPart: BasePart, pitchMin: number, pitchJitter: number)
	local sound = template:Clone()
	sound.PlaybackSpeed = pitchMin + math.random() * pitchJitter
	if sound.RollOffMaxDistance >= 10000 then
		sound.RollOffMinDistance = DEFAULT_ROLLOFF_MIN
		sound.RollOffMaxDistance = DEFAULT_ROLLOFF_MAX
	end
	sound.Parent = rootPart
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, SOUND_LIFETIME)
end

local function isWithinRange(rootPart: BasePart): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return true
	end
	local offset = rootPart.Position - camera.CFrame.Position
	return offset:Dot(offset) <= CULL_DISTANCE_SQ
end

local function isWalking(humanoid: Humanoid, rootPart: BasePart): boolean
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	if humanoid.MoveDirection.Magnitude <= 0 then
		return false
	end
	local velocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= MIN_MOVE_SPEED
end

local function playStep(entry: TrackedCharacter)
	if not isWithinRange(entry.rootPart) then
		return
	end
	local template = pickVariant(entry.humanoid.FloorMaterial)
	if template then
		playVariant(template, entry.rootPart, STEP_PITCH_MIN, STEP_PITCH_JITTER)
	end
end

local function playLanding(entry: TrackedCharacter)
	if not isWithinRange(entry.rootPart) then
		return
	end
	local template = pickVariant(entry.humanoid.FloorMaterial)
	if template then
		playVariant(template, entry.rootPart, LAND_PITCH_MIN, LAND_PITCH_JITTER)
	end
end

local function muteDefaultRunningSound(rootPart: BasePart)
	task.spawn(function()
		local running = rootPart:WaitForChild("Running", 10)
		if running and running:IsA("Sound") then
			running.Volume = 0
		end
	end)
end

local function untrackCharacter(character: Model)
	local entry = tracked[character]
	if not entry then
		return
	end
	tracked[character] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
end

local function trackCharacter(character: Model)
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local rootPart = character:WaitForChild("HumanoidRootPart", 10)
		if not humanoid or not rootPart or not humanoid:IsA("Humanoid") or not rootPart:IsA("BasePart") then
			return
		end
		if tracked[character] then
			return
		end

		local entry: TrackedCharacter = {
			character = character,
			humanoid = humanoid,
			rootPart = rootPart,
			lastPosition = rootPart.Position,
			distanceSinceStep = 0,
			connections = {},
		}
		tracked[character] = entry

		table.insert(
			entry.connections,
			humanoid.StateChanged:Connect(function(_, newState)
				if newState == Enum.HumanoidStateType.Landed then
					local verticalSpeed = math.abs(rootPart.AssemblyLinearVelocity.Y)
					if verticalSpeed >= LAND_MIN_SPEED then
						playLanding(entry)
					end
					entry.distanceSinceStep = 0
				end
			end)
		)

		table.insert(
			entry.connections,
			character.AncestryChanged:Connect(function()
				if not character:IsDescendantOf(Workspace) then
					untrackCharacter(character)
				end
			end)
		)

		muteDefaultRunningSound(rootPart)
	end)
end

local function onHeartbeat()
	for _, entry in tracked do
		local rootPart = entry.rootPart
		local position = rootPart.Position
		local delta = position - entry.lastPosition
		entry.lastPosition = position

		if not isWalking(entry.humanoid, rootPart) then
			entry.distanceSinceStep = 0
			continue
		end

		entry.distanceSinceStep += Vector3.new(delta.X, 0, delta.Z).Magnitude
		if entry.distanceSinceStep >= STRIDE_LENGTH then
			entry.distanceSinceStep -= STRIDE_LENGTH
			playStep(entry)
		end
	end
end

local function onPlayerRemoving(player: Player)
	local connections = playerConnections[player]
	if connections then
		playerConnections[player] = nil
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	if player.Character then
		untrackCharacter(player.Character)
	end
end

local function onPlayerAdded(player: Player)
	local connections = {}
	playerConnections[player] = connections

	if player.Character then
		trackCharacter(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(trackCharacter))
	table.insert(connections, player.CharacterRemoving:Connect(untrackCharacter))
end

function FootstepsController.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		footstepsFolder = resolveFootstepsFolder()
		if not footstepsFolder then
			warn("FootstepsController could not find ReplicatedStorage.Assets.Sounds.Footsteps")
			return
		end
		local containerNames = {}
		for _, child in footstepsFolder:GetChildren() do
			table.insert(containerNames, ("%s(%s)"):format(child.Name, child.ClassName))
		end
		print(("FootstepsController ready: %d sounds across [%s]"):format(#collectSounds(footstepsFolder), table.concat(containerNames, ", ")))

		for _, player in Players:GetPlayers() do
			onPlayerAdded(player)
		end
		playerAddedConnection = Players.PlayerAdded:Connect(onPlayerAdded)
		playerRemovingConnection = Players.PlayerRemoving:Connect(onPlayerRemoving)
		heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	end)
end

function FootstepsController.stop()
	if not isStarted then
		return
	end
	isStarted = false

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	for player in playerConnections do
		onPlayerRemoving(player)
	end
	for character in tracked do
		untrackCharacter(character)
	end
end

return FootstepsController
