-- ObbyLevels: which Sky Obby levels a player may pick at the ONE obby portal (ARCHITECTURE_V3.md "Phase 5 build
-- contract" 6.3). Pure data rules, shared by the server (PortalService.PickLevel validates with the server copy of the
-- profile) and the client (ObbyController draws the level cards; HudController's party row).
--
--   ObbyLevels.List()                        -> { "Easy", "Medium", "Hard", "Extreme", "Saint" } (Config.Difficulties order)
--   ObbyLevels.IndexOf(levelId)              -> 1..5 | nil
--   ObbyLevels.HighestUnlocked(bestTimes)    -> 1..5  = min(5, 1 + the highest index i whose level has a win in bestTimes:
--                                               bestTimes[Difficulties[i].Id] is a positive number); 1 when none / junk.
--                                               The HIGHEST beaten level decides (a player who beat Medium has Hard even
--                                               without an Easy time); no win = Easy only (the approved rule; no migration:
--                                               Stats.BestTimes has every win since v2).
--   ObbyLevels.IsUnlocked(bestTimes, levelId) -> bool (false for an unknown id)
--   ObbyLevels.NextAfter(levelId)            -> the next level id, or nil for Saint / an unknown id
-- Plain Lua 5.1-compatible syntax only.

local Config = require(script.Parent.Config)

local ObbyLevels = {}

local MAX_LEVELS = 5

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function difficulties()
	local list = Config.Difficulties
	if type(list) ~= "table" then
		return {}
	end
	return list
end

-- the level ids in Config.Difficulties order (a fresh table every call: callers may sort or edit it)
function ObbyLevels.List()
	local out = {}
	for i, d in ipairs(difficulties()) do
		if i > MAX_LEVELS then
			break
		end
		out[#out + 1] = d.Id
	end
	return out
end

function ObbyLevels.IndexOf(levelId)
	if type(levelId) ~= "string" then
		return nil
	end
	for i, d in ipairs(difficulties()) do
		if d.Id == levelId then
			return i
		end
	end
	return nil
end

function ObbyLevels.HighestUnlocked(bestTimes)
	local best = 0
	if type(bestTimes) == "table" then
		for i, d in ipairs(difficulties()) do
			local t = bestTimes[d.Id]
			if finite(t) and t > 0 and i > best then
				best = i
			end
		end
	end
	local top = math.min(MAX_LEVELS, #difficulties())
	if top < 1 then
		top = 1
	end
	return math.min(top, best + 1)
end

function ObbyLevels.IsUnlocked(bestTimes, levelId)
	local index = ObbyLevels.IndexOf(levelId)
	if not index then
		return false
	end
	return index <= ObbyLevels.HighestUnlocked(bestTimes)
end

function ObbyLevels.NextAfter(levelId)
	local index = ObbyLevels.IndexOf(levelId)
	if not index then
		return nil
	end
	local nextDef = difficulties()[index + 1]
	if nextDef and index + 1 <= MAX_LEVELS then
		return nextDef.Id
	end
	return nil
end

return ObbyLevels
