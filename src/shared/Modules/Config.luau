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
	GamePlaceId = Config.Places.Game,
}

return Config
