local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MusicController = {}

local LOBBY_TRACK_NAME = "lobbyforestmusic"

local isStarted = false

local function resolveLobbyTrack(): Sound?
	local assets = ReplicatedStorage:WaitForChild("Assets", 30)
	if not assets then
		return nil
	end
	local sounds = assets:WaitForChild("Sounds", 30)
	if not sounds then
		return nil
	end
	local track = sounds:WaitForChild(LOBBY_TRACK_NAME, 30)
	if track and track:IsA("Sound") then
		return track
	end
	return nil
end

function MusicController.start()
	if isStarted then
		return
	end
	isStarted = true

	task.spawn(function()
		local player = Players.LocalPlayer
		if not player.Character then
			player.CharacterAdded:Wait()
		end

		local track = resolveLobbyTrack()
		if not track then
			warn("MusicController could not find the lobby music track")
			return
		end

		local music = track:Clone()
		music.Name = "LobbyMusic"
		music.Looped = true
		music.Parent = SoundService
		music:Play()
	end)
end

return MusicController
