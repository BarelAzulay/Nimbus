-- SkyService: the living sky's server half (docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md, plan
-- docs/superpowers/plans/2026-10-30-living-sky.md Task 4). The server never tweens the sky: it publishes one clock and the
-- raid event as Workspace attributes (Config.Sky.Attr), every client turns them into the same phase and look with
-- shared/SkyCycle and applies it as the base of its LightingStack. No remote traffic, no per-frame work.
--
--   SkyService.Init(deps)        deps = { EventService, BattleService } (both optional). The first call publishes
--                                SkyEpoch = Workspace:GetServerTimeNow(), SkySpeed = Config.Sky.Speed.Default, SkyOffset 0,
--                                SkyEvent "" and SkyEventAt = now, and starts the raid watchdog. Init again (tests) never
--                                rewrites them: it only wires signals it was not given before and points the watchdog
--                                at the newest BattleService.
--   SkyService.SetPhase(name) -> ok, message     "dawn" | "day" | "sunset" | "night" (any case): SkyOffset so that
--                                phase starts now (dev /sky <phase>)
--   SkyService.SetSpeed(x) -> ok, speed|message  a finite number clamped to Config.Sky.Speed (0.1..120); SkyOffset moves
--                                with it so the loop keeps its position (no jump); NaN / inf / non-numbers are refused
--   SkyService.SetEvent(bossId, source, battleId) -> ok, message   a Config.Sky.RaidThemes boss id; source "raid" (the
--                                default) or "dev" (/sky raid: a preview the watchdog leaves alone)
--   SkyService.ClearEvent() -> ok                 SkyEvent "" (the clients blend back to the cycle)
--   SkyService.Status() -> { Phase, Next, T, Blend, LoopT, Seconds, Length, Speed, Offset, Event, Source }
--   SkyService.Find(word) -> bossId | nil         an exact boss id or a unique prefix ("storm" -> storm_titan)
-- The raid sky (server-wide, raids are server-wide events):
--   * on   EventService.EventStarted("BossRaid", { BossId, BattleId }) for a boss with a RaidThemes sky
--   * off  BattleService.BattleEnded(battleId, result) with result.Mode "Raid" (every Reason: BossDown, Wipe, Error,
--          Timeout, NoPlayers) and EventService.EventEnded("BossRaid", info); an end that names ANOTHER raid's battle id
--          (a late end of the raid before) leaves the current raid's sky up. Non-Raid ends never clear.
--   * the watchdog, every Config.Sky.EventWatch s: BattleService.GetRaidStatus() is the truth for raid skies (a raid gone
--          without an end we heard clears, a raid that started without EventStarted gets its sky); dev previews are
--          left alone. A server shutdown takes the attributes with it (a new server starts on SkyEvent "").
-- SkyEventAt changes only when SkyEvent does (the same boss again does not restart the clients' blend).
-- Plain Lua 5.1-compatible syntax only.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SkyCycle = require(Shared.SkyCycle)

local SkyService = {}

local St = {
	initialized = false,
	wired = {}, -- [signal table] = true once connected
	battle = nil, -- the BattleService the watchdog asks (the newest Init's)
	source = nil, -- "raid" | "dev" while SkyEvent is set
	battleId = nil, -- the raid battle id behind a "raid" sky (nil = unknown)
}

local function cfg()
	return Config.Sky
end

local function attr(key)
	return cfg().Attr[key]
end

local function now()
	return Workspace:GetServerTimeNow()
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function hasFn(m, name)
	return type(m) == "table" and type(m[name]) == "function"
end

local function get(key, default)
	local v = Workspace:GetAttribute(attr(key))
	if v == nil then
		return default
	end
	return v
end

local function set(key, value)
	Workspace:SetAttribute(attr(key), value)
end

local function loopLength()
	local total = 0
	for _, phase in ipairs(cfg().Cycle.Order) do
		total = total + cfg().Cycle.Seconds[phase]
	end
	return total
end

-- a loop position in [0, loop)
local function wrap(pos)
	local loop = loopLength()
	local w = pos - math.floor(pos / loop) * loop
	if not finite(w) or w < 0 or w >= loop then
		return 0
	end
	return w
end

-- the published clock: epoch, speed, offset (finite numbers, whatever someone wrote into the attributes)
local function clock()
	local epoch = get("Epoch", 0)
	local speed = get("Speed", cfg().Speed.Default)
	local offset = get("Offset", 0)
	if not finite(epoch) then
		epoch = 0
	end
	if not finite(speed) then
		speed = cfg().Speed.Default
	end
	if not finite(offset) then
		offset = 0
	end
	return epoch, math.max(cfg().Speed.Min, math.min(cfg().Speed.Max, speed)), offset
end

-- the loop position right now (the same sum SkyCycle.At takes)
local function position()
	local epoch, speed, offset = clock()
	return wrap((now() - epoch) * speed + offset)
end

----------------------------------------------------------------------
-- The clock
----------------------------------------------------------------------

function SkyService.Status()
	local epoch, speed, offset = clock()
	local at = SkyCycle.At(now(), epoch, speed, offset)
	local length = cfg().Cycle.Seconds[at.Phase] or 0
	return {
		Phase = at.Phase, Next = at.Next, T = at.T, Blend = at.Blend, LoopT = at.LoopT,
		Seconds = at.T * length, Length = length, Speed = speed, Offset = offset,
		Event = get("Event", ""), Source = St.source,
	}
end

function SkyService.SetPhase(name)
	if type(name) ~= "string" then
		return false, "name a phase"
	end
	local want = string.lower(name)
	local start = 0
	for _, phase in ipairs(cfg().Cycle.Order) do
		if string.lower(phase) == want then
			local epoch, speed = clock()
			-- a hair into the phase, so float rounding never lands on the end of the one before
			set("Offset", wrap(start + 0.001 - (now() - epoch) * speed))
			return true, phase
		end
		start = start + cfg().Cycle.Seconds[phase]
	end
	return false, "unknown phase " .. string.sub(name, 1, 16)
end

function SkyService.SetSpeed(x)
	if not finite(x) then
		return false, "the speed must be a number"
	end
	local s = cfg().Speed
	local speed = math.max(s.Min, math.min(s.Max, x))
	local pos = position()
	local epoch = clock()
	set("Speed", speed)
	set("Offset", wrap(pos - (now() - epoch) * speed)) -- the loop goes on from where it is
	return true, speed
end

----------------------------------------------------------------------
-- The raid sky
----------------------------------------------------------------------

-- an exact Config.Sky.RaidThemes boss id, or a unique prefix of one (any case)
function SkyService.Find(word)
	if type(word) ~= "string" or word == "" then
		return nil
	end
	local w = string.lower(word)
	local themes = cfg().RaidThemes
	if themes[w] then
		return w
	end
	local found = nil
	for id in pairs(themes) do
		if string.sub(id, 1, #w) == w then
			if found then
				return nil -- more than one boss starts like that
			end
			found = id
		end
	end
	return found
end

function SkyService.SetEvent(bossId, source, battleId)
	if type(bossId) ~= "string" or cfg().RaidThemes[bossId] == nil then
		return false, "no raid sky for " .. tostring(bossId)
	end
	St.source = source == "dev" and "dev" or "raid"
	St.battleId = battleId
	if get("Event", "") ~= bossId then
		set("Event", bossId)
		set("EventAt", now())
	end
	return true, bossId
end

function SkyService.ClearEvent()
	St.source = nil
	St.battleId = nil
	if get("Event", "") ~= "" then
		set("Event", "")
		set("EventAt", now())
	end
	return true
end

-- a raid ended: clear unless the end names another raid than the one whose sky is up
local function raidEnded(battleId)
	if get("Event", "") == "" then
		return
	end
	if battleId ~= nil and St.battleId ~= nil and battleId ~= St.battleId then
		return -- the late end of the raid before; the current raid's sky stays
	end
	SkyService.ClearEvent()
end

local function onEventStarted(kind, info)
	if kind ~= "BossRaid" or type(info) ~= "table" then
		return
	end
	SkyService.SetEvent(info.BossId, "raid", info.BattleId)
end

local function onEventEnded(kind, info)
	if kind ~= "BossRaid" then
		return
	end
	raidEnded(type(info) == "table" and info.BattleId or nil)
end

local function onBattleEnded(battleId, result)
	if type(result) ~= "table" or result.Mode ~= "Raid" then
		return
	end
	raidEnded(battleId)
end

-- the raid status is the truth for raid skies; dev previews are left alone
local function watch()
	local bs = St.battle
	if St.source == "dev" or not hasFn(bs, "GetRaidStatus") then
		return
	end
	local status = bs.GetRaidStatus()
	local live = type(status) == "table" and status.Active ~= false and type(status.BossId) == "string"
	if live and cfg().RaidThemes[status.BossId] ~= nil then
		if get("Event", "") ~= status.BossId then
			SkyService.SetEvent(status.BossId, "raid", status.BattleId)
		end
	elseif get("Event", "") ~= "" then
		SkyService.ClearEvent()
	end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------

local function wire(signal, handler)
	if type(signal) ~= "table" or not hasFn(signal, "Connect") or St.wired[signal] then
		return
	end
	St.wired[signal] = true
	signal:Connect(function(...)
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[SkyService] " .. tostring(err))
		end
	end)
end

function SkyService.Init(deps)
	deps = type(deps) == "table" and deps or {}
	local es, bs = deps.EventService, deps.BattleService
	if type(es) == "table" then
		wire(es.EventStarted, onEventStarted)
		wire(es.EventEnded, onEventEnded)
	end
	if type(bs) == "table" then
		wire(bs.BattleEnded, onBattleEnded)
		St.battle = bs
	end
	if St.initialized then
		return
	end
	St.initialized = true
	local t = now()
	set("Epoch", t)
	set("Speed", cfg().Speed.Default)
	set("Offset", 0)
	set("Event", "")
	set("EventAt", t)
	task.spawn(function()
		while true do
			task.wait(cfg().EventWatch)
			local ok, err = pcall(watch)
			if not ok then
				warn("[SkyService] watchdog: " .. tostring(err))
			end
		end
	end)
end

return SkyService
