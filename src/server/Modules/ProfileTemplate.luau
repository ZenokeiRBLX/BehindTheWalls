-- ServerScriptService/Server/Modules/ProfileTemplate.luau

export type PlayerData = {
	Coins: number,
	Wins: number,
	Donated: number,
	PlayTime: number,
	LastLogoutTime: number,
	Settings: { [string]: boolean },
}

local ProfileTemplate: PlayerData = {
	Coins = 0,
	Wins = 0,
	Donated = 0,
	PlayTime = 0,
	LastLogoutTime = 0,
	Settings = {},
}

return ProfileTemplate
