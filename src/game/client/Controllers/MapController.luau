local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))

local MapController = {}

local CREATED_PREFIX = "MapLighting"

type Values = { [string]: any }

type AmbienceEntry = {
	name: string,
	volumeScale: number?,
}

type Profile = {
	Lighting: Values?,
	Effects: { [string]: Values }?,
	Water: Values?,
	Ambience: { AmbienceEntry }?,
}

type Defaults = {
	lighting: Values,
	effects: { [string]: Values },
	water: Values,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local defaults: Defaults = { lighting = {}, effects = {}, water = {} }
local created: { [string]: Instance } = {}
local tweens: { Tween } = {}
local ambience: { [string]: Sound } = {}
local warnedSounds: { [string]: boolean } = {}
local currentMap: string? = nil
local currentProfile: string? = nil

local function profiles(): { [string]: Profile }
	return Config.Maps.Lighting.Profiles :: any
end

local function profileFor(mapKey: string?): (string?, Profile?)
	if not mapKey then
		return nil, nil
	end
	local level = (Config.Maps.Levels :: any)[mapKey]
	local name = if level then level.Lighting else nil
	if type(name) ~= "string" then
		return nil, nil
	end
	return name, profiles()[name]
end

local function findEffect(className: string): Instance?
	for _, child in Lighting:GetChildren() do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

local function read(instance: Instance, property: string): (boolean, any)
	return pcall(function()
		return (instance :: any)[property]
	end)
end

local function write(instance: Instance, property: string, value: any)
	local ok, err = pcall(function()
		(instance :: any)[property] = value
	end)
	if not ok then
		warn(("MapController: could not set %s.%s: %s"):format(instance:GetFullName(), property, tostring(err)))
	end
end

local function captureDefaults()
	local terrain = Workspace.Terrain
	for _, profile in profiles() do
		for property in profile.Lighting or {} do
			if defaults.lighting[property] == nil then
				local ok, value = read(Lighting, property)
				if ok then
					defaults.lighting[property] = value
				end
			end
		end
		for className, values in profile.Effects or {} do
			local effect = findEffect(className)
			local stored = defaults.effects[className] or {}
			defaults.effects[className] = stored
			for property in values do
				if stored[property] == nil and effect then
					local ok, value = read(effect, property)
					if ok then
						stored[property] = value
					end
				end
			end
		end
		for property in profile.Water or {} do
			if defaults.water[property] == nil then
				local ok, value = read(terrain, property)
				if ok then
					defaults.water[property] = value
				end
			end
		end
	end
end

local function cancelTweens()
	for _, tween in tweens do
		tween:Cancel()
	end
	table.clear(tweens)
end

local function blend(instance: Instance, values: Values, seconds: number)
	local goal: Values = {}
	for property, value in values do
		local kind = typeof(value)
		if seconds > 0 and (kind == "number" or kind == "Color3") then
			goal[property] = value
		else
			write(instance, property, value)
		end
	end
	if next(goal) == nil then
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local ok, tween = pcall(TweenService.Create, TweenService, instance, info, goal)
	if ok then
		tween:Play()
		table.insert(tweens, tween)
	else
		for property, value in goal do
			write(instance, property, value)
		end
	end
end

local function effectFor(className: string): Instance?
	local effect = findEffect(className)
	if effect then
		return effect
	end
	local ok, instance = pcall(Instance.new, className)
	if not ok then
		warn("MapController: cannot create Lighting effect " .. className)
		return nil
	end
	instance.Name = CREATED_PREFIX .. className
	if instance:IsA("PostEffect") then
		instance.Enabled = false
	end
	instance.Parent = Lighting
	created[className] = instance
	return instance
end

local function clearCreated()
	for className, instance in created do
		instance:Destroy()
		created[className] = nil
	end
end

local function applyAmbience(list: { AmbienceEntry }?, seconds: number)
	local wanted: { [string]: number } = {}
	local entries: { AmbienceEntry } = list or {}
	for _, entry in entries do
		wanted[entry.name] = entry.volumeScale or 1
	end
	for name, sound in ambience do
		if wanted[name] == nil then
			ambience[name] = nil
			local fade = TweenService:Create(sound, TweenInfo.new(math.max(seconds, 0.05)), { Volume = 0 })
			fade.Completed:Once(function()
				sound:Destroy()
			end)
			fade:Play()
		end
	end
	for name, scale in wanted do
		if ambience[name] then
			continue
		end
		local template = SoundService:FindFirstChild(name)
		if not template or not template:IsA("Sound") then
			if not warnedSounds[name] then
				warnedSounds[name] = true
				warn("MapController: SoundService." .. name .. " not found")
			end
			continue
		end
		local sound = template:Clone()
		local volume = template.Volume * scale
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(math.max(seconds, 0.05)), { Volume = volume }):Play()
		ambience[name] = sound
	end
end

local function applyProfile(name: string?, profile: Profile?, seconds: number)
	cancelTweens()
	local lighting = if profile then profile.Lighting else nil
	blend(Lighting, lighting or defaults.lighting, seconds)
	local targets = if profile then profile.Effects or {} else {}
	for className, values in defaults.effects do
		if targets[className] == nil then
			local effect = findEffect(className)
			if effect then
				blend(effect, values, seconds)
			end
		end
	end
	for className, values in targets do
		local effect = effectFor(className)
		if effect then
			blend(effect, values, seconds)
		end
	end
	if not profile then
		clearCreated()
	end
	local water = if profile then profile.Water else nil
	blend(Workspace.Terrain, water or defaults.water, seconds)
	applyAmbience(if profile then profile.Ambience else nil, Config.Maps.Lighting.AmbienceFadeSeconds)
	currentProfile = name
end

local function readMap(): string?
	local value = Players.LocalPlayer:GetAttribute(Config.Maps.PlayerAttribute)
	return if type(value) == "string" then value else nil
end

local function refresh(seconds: number)
	local mapKey = readMap()
	currentMap = mapKey
	local name, profile = profileFor(mapKey)
	if name == currentProfile then
		return
	end
	applyProfile(name, profile, seconds)
end

function MapController.getCurrentMap(): string?
	return currentMap
end

function MapController.getLevelSettings(mapKey: string?): any
	if not mapKey then
		return nil
	end
	return (Config.Maps.Levels :: any)[mapKey]
end

function MapController.start()
	if isStarted then
		return
	end
	isStarted = true
	captureDefaults()
	local player = Players.LocalPlayer
	table.insert(connections, player:GetAttributeChangedSignal(Config.Maps.PlayerAttribute):Connect(function()
		refresh(Config.Maps.Lighting.TransitionSeconds)
	end))
	refresh(0)
end

function MapController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if currentProfile then
		applyProfile(nil, nil, 0)
	end
	applyAmbience(nil, 0)
	currentMap = nil
end

return MapController
