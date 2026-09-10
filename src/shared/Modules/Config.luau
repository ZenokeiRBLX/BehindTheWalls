local ReplicatedFirst = game:GetService("ReplicatedFirst")

local PlaceIds = require(ReplicatedFirst:WaitForChild("PlaceIds"))

local Config = {}

Config.GameName = "Behind Every Wall"
Config.MaxPlayers = 12
Config.Gravity = 196.2

Config.Places = PlaceIds

function Config.isGamePlace(): boolean
	return game.PlaceId == PlaceIds.Game
end

Config.Party = {
	MinSize = 1,
	MaxSize = 5,
	DefaultSize = 5,
	DefaultDifficulty = "Normal",
	CountdownSeconds = 10,
	ArrivalTimeoutSeconds = 60,
	GamePlaceId = Config.Places.Game,
	MinLoadingSeconds = 6,
	PreloadTimeoutSeconds = 12,
}

Config.Cutscene = {
	FieldOfView = 55,
	PanDownSeconds = 3,
	PanDownLift = 12,
	PanDownTiltDegrees = 30,
	WalkSpeed = 7.5,
	WalkAnimationReferenceSpeed = 6.5,
	WalkAnimationSpeedVariance = 0.15,
	WalkAnimationFadeRange = { 0.2, 0.5 },
	StopDistance = 14,
	LineSpacing = 3.5,
	LineMergeStart = 0.45,
	WalkAnimationId = "rbxassetid://127105345264603",
	PhoneWalkAnimationId = "rbxassetid://83856887116046",
	PhoneWalkSlots = { 1 },
	PanDownPushIn = 4,
	SwayAmount = 0.12,
	Shots = {
		{ name = "HeroLow", startAt = 0, fov = 62, anchor = "group", from = { 15, 2, 1.1 }, to = { 9, -1.5, 0.9 }, focus = { 0, 0, 2.2 }, smoothing = 3 },
		{ name = "Profile", startAt = 0.22, fov = 40, anchor = "group", from = { 4, 20, 1.6 }, to = { -3, 17, 1.3 }, focus = { 0, 0, 2 }, smoothing = 2.5 },
		{ name = "RearCrane", startAt = 0.44, fov = 58, anchor = "group", from = { -8, -3, 1.4 }, to = { -13, -5, 8 }, focus = { 18, 0, 1 }, smoothing = 3 },
		{ name = "HoleLow", startAt = 0.64, fov = 48, anchor = "hole", from = { -3, -15, 1.1 }, to = { -6, -11, 1.5 }, focus = { 0, 0, 2 }, smoothing = 4 },
		{ name = "HoleSide", startAt = 0.85, fov = 55, anchor = "hole", from = { 6, 26, 10 }, to = { 2, 22, 8 }, focus = { 7, 0, 0.5 }, smoothing = 2.5 },
	},
	HoldSeconds = 1.5,
	CharacterWaitSeconds = 10,
	HoleName = "Main_Hole",
	PinnedNames = { "Neighborhood", "Teleport_Players", "PORTAL" },
	PreloadSpacing = 40,
	DebugFillSlots = true,
	DebugFillUserIds = { 1, 156, 261, 3, 13645, 56449, 2032622 },
}

return Config
