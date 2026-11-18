local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Config"))
local HudController = require(script.Parent:WaitForChild("HudController"))

local ObjectiveController = {}

local DEFAULT_SET = "Default"

type ObjectiveSettings = {
	text: string,
	progress: number?,
	goal: number?,
	target: string?,
}

local isStarted = false
local connections: { RBXScriptConnection } = {}
local targetConnection: RBXScriptConnection? = nil
local currentSet: string? = nil
local targetAttribute: string? = nil

local function objectivesFor(setName: string): { ObjectiveSettings }
	if setName ~= DEFAULT_SET then
		local level = (Config.Maps.Levels :: any)[setName]
		if level and level.Objectives then
			return level.Objectives
		end
	end
	return Config.Objectives.Default :: any
end

local function readTarget(): Vector3?
	local name = targetAttribute
	if not name then
		return nil
	end
	local value = Workspace:GetAttribute(name)
	if typeof(value) == "Vector3" then
		return value
	elseif typeof(value) == "CFrame" then
		return value.Position
	end
	return nil
end

local function refreshTarget()
	HudController.setGuideTarget(readTarget())
end

local function watchTarget(name: string?)
	if targetConnection then
		targetConnection:Disconnect()
		targetConnection = nil
	end
	targetAttribute = name
	if name then
		targetConnection = Workspace:GetAttributeChangedSignal(name):Connect(refreshTarget)
	end
	refreshTarget()
end

local function currentSetName(): string
	local value = Players.LocalPlayer:GetAttribute(Config.Maps.PlayerAttribute)
	return if type(value) == "string" and value ~= "" then value else DEFAULT_SET
end

local function refresh()
	local setName = currentSetName()
	if setName == currentSet then
		return
	end
	currentSet = setName
	local entries: { HudController.ObjectiveEntry } = {}
	local target: string? = nil
	for index, objective in objectivesFor(setName) do
		local guided = objective.target ~= nil and target == nil
		if guided then
			target = objective.target
		end
		entries[index] = {
			text = objective.text,
			progress = objective.progress,
			goal = objective.goal,
			guide = guided,
		}
	end
	HudController.setObjectives(entries)
	watchTarget(target)
end

function ObjectiveController.getCurrentSet(): string?
	return currentSet
end

function ObjectiveController.start()
	if isStarted then
		return
	end
	isStarted = true
	table.insert(connections, Players.LocalPlayer:GetAttributeChangedSignal(Config.Maps.PlayerAttribute):Connect(refresh))
	refresh()
end

function ObjectiveController.stop()
	if not isStarted then
		return
	end
	isStarted = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	watchTarget(nil)
	currentSet = nil
end

return ObjectiveController
