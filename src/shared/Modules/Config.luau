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
	StepStride = 4.4,
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
	Fall = {
		DropDistance = 4,
		TossSpeed = 11,
		TossUp = 7,
		TumbleSpeed = 5,
		Spread = 2,
		TorsoGravityScale = 0.7,
		LimbGravityScale = 0.3,
		LimbScatter = 14,
		LimbSpin = 8,
		DiveDelay = 0.5,
		RiseHeight = 16,
		RiseSeconds = 1.3,
		PlungeSeconds = 0.9,
		DiveDepth = 10,
		FadeDepth = 2.5,
		FadeOutSeconds = 0.5,
		Shots = {
			{ name = "Brink", startAt = 0, fov = 50, anchor = "hole", from = { -6, 13, 3 }, to = { -3, 11, 2.4 }, focus = { -2, 0, 1 }, smoothing = 3 },
			{ name = "Plunge", startAt = 0.55, fov = 65, anchor = "hole", from = { 9, -5, 1.2 }, to = { 7, -4, 0.6 }, focus = { -1, 0, 0.5 }, smoothing = 2.5 },
		},
	},
	Audio = {
		MusicName = "Forest_Music",
		CutsceneMusicName = "Intro_Cutscene_Music",
		MusicFadeInSeconds = 2,
		MusicFadeOutSeconds = 1.5,
		CutsceneMusicFadeOutSeconds = 2.5,
		SewerSoundName = "Sewer_Sound_Effect",
		BoomName = "CinematicBoom2",
		BoomLeadSeconds = 0.75,
		BoneCrackName = "Bone_Crack",
		BoneCrackSpeedRange = { 0.75, 1.35 },
		BoneCrackVolumeScale = 1,
		ScreamNames = { "SCREAM_1", "SCREAM_2", "SCREAM_3" },
		ScreamSpeedRange = { 0.92, 1.08 },
		ScreamVolumeScale = 1,
		SplashName = "Water_Splash",
		SplashVolumeScale = 1,
		FootstepVolumeScale = 0.35,
	},
	Landing = {
		ModelName = "Intro_Sewer",
		DropHeight = 18,
		TiltDegrees = 70,
		TumbleSpeed = 4,
		RagdollSeconds = 3,
		StandLift = 2,
		RevealSeconds = 0.2,
		BlackoutDelay = 1.3,
		BlackoutSeconds = 0.35,
		WakeDelay = 0.25,
		WakeFadeSeconds = 1.1,
		WakeBlur = 18,
		WakeBlurSeconds = 1.8,
		AttributeWaitSeconds = 1,
		RagdollWaitMargin = 2,
	},
	HoldSeconds = 2.5,
	CharacterWaitSeconds = 10,
	HoleName = "Main_Hole",
	PinnedNames = { "Neighborhood", "Teleport_Players", "PORTAL" },
	PreloadSpacing = 40,
	DebugFillSlots = true,
	DebugFillUserIds = { 603692115, 156, 261, 3, 13645, 56449, 2032622 },
}

Config.Camera = {
	FieldOfView = 70,
	SpeedFovBoost = 5,
	FovSmoothing = 6,
	DefaultPitch = -5,
	PitchMin = -80,
	PitchMax = 80,
	Look = {
		Mouse = {
			DegreesPerPixel = 0.5,
			VerticalScale = 0.77,
			Multiplier = 1,
		},
		Touch = {
			DegreesPerPixel = 1,
			VerticalScale = 0.66,
			Multiplier = 1,
		},
		Gamepad = {
			DegreesPerSecond = 180,
			VerticalScale = 0.77,
			Multiplier = 1,
			Deadzone = 0.15,
			Curve = 2,
			Acceleration = {
				Threshold = 0.9,
				Bonus = 1.6,
				RampSeconds = 0.9,
			},
		},
		MaxDegreesPerFrame = 45,
	},
	LookSmoothing = 22,
	EyeLift = 0.2,
	EyeForward = 0.35,
	WallPadding = 0.3,
	EyeHeightSmoothing = 6,
	VerticalSmoothing = 14,
	RagdollViewSmoothing = 14,
	CrosshairGuiName = "MouseFrame",
	VisibleParts = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" },
	StrafeTiltDegrees = 2,
	TiltSmoothing = 6,
	TurnRoll = {
		DegreesPerRadian = 0.6,
		MaxDegrees = 2.5,
		Smoothing = 8,
	},
	Bob = {
		StrideStuds = 4.4,
		Height = 0.1,
		Sway = 0.07,
		PitchDegrees = 0.3,
		RollDegrees = 0.6,
		Smoothing = 8,
	},
	Breathing = {
		Degrees = 0.35,
		Rate = 1.4,
		NoiseSpeed = 0.35,
		MovingReduction = 0.6,
	},
	Impact = {
		MinSpeed = 20,
		MaxSpeed = 80,
		Kick = 12,
		Stiffness = 170,
		Damping = 18,
		PitchDegreesPerStud = 4,
	},
	SuspendAttributes = { "UnderBed", "InCloset" },
}

return Config
