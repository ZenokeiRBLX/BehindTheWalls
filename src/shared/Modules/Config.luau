local Config = {}

Config.GameName = "Behind Every Wall"
Config.MaxPlayers = 12
Config.Gravity = 196.2

Config.Party = {
	MinSize = 1,
	MaxSize = 5,
	DefaultSize = 4,
	DefaultDifficulty = "Normal",
	CountdownSeconds = 5,
	GamePlaceId = 0,
}

return Config
