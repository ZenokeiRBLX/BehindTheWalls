local Config = {}

Config.GameName = "Behind Every Wall"
Config.MaxPlayers = 12
Config.Gravity = 196.2

Config.Party = {
	MinSize = 1,
	MaxSize = 5,
	DefaultSize = 5,
	DefaultDifficulty = "Normal",
	CountdownSeconds = 10,
	GamePlaceId = 0,
}

return Config
