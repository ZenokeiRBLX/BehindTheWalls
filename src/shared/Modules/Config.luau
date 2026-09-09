local Config = {}

Config.GameName = "Behind Every Wall"
Config.MaxPlayers = 12
Config.Gravity = 196.2

Config.Places = {
	Lobby = 118916171408858,
	Game = 115970043416367,
}

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
	FlightSeconds = 12,
	SkimDistance = 110,
	SkimHeight = 3.5,
	ReturnHeight = 6,
	FieldOfView = 55,
	HoldSeconds = 1,
	CharacterWaitSeconds = 10,
}

return Config
