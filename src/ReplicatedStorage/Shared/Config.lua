local Config = {}

Config.GameName = "BehindTheWalls"
Config.MaxPlayers = 12
Config.LobbyTimeSeconds = 15
Config.RoundLengthSeconds = 180
Config.Gravity = 196.2
Config.DefaultSpawnPosition = Vector3.new(0, 10, 0)

Config.TeamNames = {
	Hunter = "Hunter",
	Runner = "Runner",
}

return Config
