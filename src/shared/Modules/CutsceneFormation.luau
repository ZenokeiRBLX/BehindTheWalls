local Config = require(script.Parent:WaitForChild("Config"))

export type Spot = {
	slot: number,
	rank: number,
	offset: number,
	gather: CFrame,
	brink: CFrame,
}

local CutsceneFormation = {}

local EPSILON = 0.001

local function flatUnit(vector: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > EPSILON then flat.Unit else fallback
end

function CutsceneFormation.compute(hole: Vector3, starts: { [number]: Vector3 }): ({ [number]: Spot }, Vector3)
	local settings = Config.Cutscene.Gather
	local slots: { number } = {}
	local sum = Vector3.zero
	for slot, position in starts do
		table.insert(slots, slot)
		sum += position
	end
	local spots: { [number]: Spot } = {}
	local count = #slots
	if count == 0 then
		return spots, -Vector3.zAxis
	end
	local forward = flatUnit(hole - sum / count, -Vector3.zAxis)
	local right = forward:Cross(Vector3.yAxis).Unit

	table.sort(slots, function(a, b)
		local da = starts[a]:Dot(forward)
		local db = starts[b]:Dot(forward)
		if math.abs(da - db) > EPSILON then
			return da > db
		end
		return a < b
	end)
	local frontCount = math.min(count, math.max(settings.FrontCount, 1))
	local ranks: { { number } } = { {}, {} }
	for index, slot in slots do
		table.insert(if index <= frontCount then ranks[1] else ranks[2], slot)
	end

	local radius = math.max(settings.BrinkRadius, EPSILON)
	local step = 2 * math.asin(math.clamp(settings.Spacing / (2 * radius), 0, 1))
	local converge = math.clamp(settings.Converge, 0, 1)
	local backShift = if (frontCount + #ranks[2]) % 2 == 0 then 0.5 else 0
	for rankIndex, rank in ranks do
		table.sort(rank, function(a, b)
			local la = starts[a]:Dot(right)
			local lb = starts[b]:Dot(right)
			if math.abs(la - lb) > EPSILON then
				return la < lb
			end
			return a < b
		end)
		local rankCount = #rank
		local rankRadius = radius + (rankIndex - 1) * settings.RankDepth
		local shift = if rankIndex > 1 then backShift else 0
		for position, slot in rank do
			local offset = position - (rankCount + 1) / 2 + shift
			local angle = offset * step
			local outward = -forward * math.cos(angle) + right * math.sin(angle)
			local ground = Vector3.new(hole.X, starts[slot].Y, hole.Z)
			local brink = ground + outward * rankRadius
			local heading = flatUnit(forward * (1 - converge) - outward * converge, forward)
			local gather = brink - heading * settings.ApproachDistance
			spots[slot] = {
				slot = slot,
				rank = rankIndex,
				offset = offset,
				gather = CFrame.lookAt(gather, gather + heading),
				brink = CFrame.lookAt(brink, brink - outward),
			}
		end
	end
	return spots, forward
end

return CutsceneFormation
