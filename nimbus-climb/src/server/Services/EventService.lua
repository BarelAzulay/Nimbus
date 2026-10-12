-- EventService (Phase 3, events): the arena's special events (ARCHITECTURE_V3.md "Phase 3: Pet battles" -> "Special
-- events system", the "Phase 3 build contract" and its "Interfaces between the Phase 3 modules").
--
--   EventService.Init(deps)        deps = { DataService, BattleService, PetCareService, ArenaInfo } (all optional; players
--                                  already in the game get the ArenaState at once)
--   EventService.StartNow(kind, bossId|nil) -> ok, message      start an event at once (developer tools: /raid, the
--                                  DEV panel's "Start Boss Raid"): kind = "BossRaid" | "DoubleRewards"
--   EventService.RewardMultiplier() -> n                         BattleCatalog.Events.DoubleRewardsMultiplier during a
--                                  Double Rewards hour, else 1 (BattleService multiplies battle Tokens by it)
--   EventService.IsDoubleRewards() -> bool, EventService.GetDouble() -> { Active, EndsIn } | nil
--   EventService.GetState() -> the ArenaState table (below), EventService.Broadcast() sends it now
--   Extras: EndNow(kind) -> ok, message (ends a running event), SecondsUntil(kind) -> seconds to the next one
--   EventService.RaidTierFor(share, won) -> BattleCatalog.RaidTier(...) with the Tokens of this moment (Double Rewards)
--   Signals (exist at module load, Util.Signal): EventAnnounced(kind, info), EventStarted(kind, info),
--   EventEnded(kind, info). info = { Kind, BossId, Name, StartsIn | Seconds, Won, Players, ... }
--
-- The scheduler (numbers from BattleCatalog.Events, never duplicated here):
--   * Boss Raid: every Schedule.BossRaid.EveryMinutes (20), the first FirstAfterSeconds (300) after the server starts.
--     AnnounceSeconds (120) before, every player gets a side toast (Notify, never centred) naming the boss, a reminder
--     30 s before, and the ArenaState countdown (the event board in the arena shows it too). At the time,
--     BattleService.StartRaid(bossId) opens the raid on the colosseum floor (the roster rotates: BattleCatalog.NextBoss);
--     players join inside the arena during JoinWindowSeconds. BattleService runs and ends the fight; EventService
--     watches it (a raid still open DurationSeconds + the join window + RAID_GRACE after its start is closed with
--     BattleService.EndRaid) and, on BattleService.BattleEnded (Mode "Raid"), tells everyone how it went and who won
--     an event pet. A raid that is due while one still runs (a developer started one) waits for it to end.
--   * Double Rewards: a DurationSeconds (1 hour) window every EveryMinutes (180), the first one EveryMinutes after the
--     server starts (or the entry's FirstAfterSeconds when the catalog adds one). Announced like the raid; while it
--     runs RewardMultiplier() is 2, the Workspace attribute DoubleRewards is true (clients / boards) and BattleService
--     is told with SetDoubleRewards(true, seconds).
--   * More kinds later (e.g. King of the Ring): add a KINDS entry + a BattleCatalog.Events.Schedule row.
-- Raid rewards (paid exactly once): BattleService pays the tiers by damage share (BattleCatalog.RaidTier: Tokens x
--   RewardMultiplier(), pet XP, a GemChance of Gems, an EventPetChance of one of the EventOnly pets of PetCatalog the
--   player has not won yet) while BattleService.PayRaidRewards is true (its default: its "End" message shows them).
--   When a BattleService build leaves them unpaid (PayRaidRewards == false, result.RewardsPaid ~= true), EventService
--   pays the same tiers itself from the BattleEnded result, once per (battle, player): the record is marked first.
-- ArenaState (remote, server -> client, one table): broadcast every BROADCAST_FAST s while a countdown (the last
--   AnnounceSeconds) or a raid runs, else every BROADCAST_SLOW s, and to every player who joins:
--   { Next = { Kind, BossId, Name, StartsIn, Announced } | nil   (the soonest scheduled event)
--     Raid = BattleService.GetRaidStatus() -> { Active, BossId, Hp, MaxHp, Players, EndsIn, ... } | nil
--     Double = { Active, EndsIn } | nil
--     Leaderboard = { { UserId, Name, Trophies } x 10 }   (the players in this server, by Battle.Trophies)
--     -- extras: NextRaid = { BossId, Name, StartsIn } | nil, LastRaid = { BossId, Name, Won, Players, Top = {
--        { UserId, Name, Damage, Tier }... }, Ago } | nil, Multiplier = n }
--   The same table is drawn on the arena's event board + trophy leaderboard (ArenaBuilder.ApplyArenaState) whenever
--   what they show changes (the boards tick their countdowns themselves), at least every BOARD_KEEPALIVE s.
-- Plain Lua 5.1-compatible syntax only; task.* only; no client -> server remote (nothing to trust).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local EventService = {}
EventService.EventAnnounced = Util.Signal()
EventService.EventStarted = Util.Signal()
EventService.EventEnded = Util.Signal()

local function loadShared(name)
	local inst = Shared:FindFirstChild(name)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	warn("[EventService] could not load " .. name .. ": " .. tostring(result))
	return nil
end

local BattleCatalog = loadShared("BattleCatalog")
local PetCatalog = loadShared("PetCatalog")
local PetKeys = loadShared("PetKeys")

----------------------------------------------------------------------
-- Local constants (not in Config / BattleCatalog; see the deviations list)
----------------------------------------------------------------------
local TICK = 1 -- scheduler step (seconds)
local BROADCAST_FAST = 1 -- ArenaState period while a countdown or a raid runs
local BROADCAST_SLOW = 5 -- ... otherwise
local REMINDER_SECONDS = 30 -- the second raid toast
local RAID_GRACE = 30 -- seconds past DurationSeconds + the join window before a raid is closed by force
local POSTPONE = 30 -- a raid due while another raid runs waits this long, then checks again
local TOAST_SECONDS = 6
local LEADERS = 10

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local St = {
	initialized = false,
	running = false,
	deps = {},
	slots = {}, -- [kind] = { Kind, At, Announced, Reminded, Entry, BossId }
	raidIndex = 0, -- the rotation position of the last boss that was scheduled
	raid = nil, -- { BossId, StartedAt, Id } while a raid we started (or saw) is open
	double = nil, -- { EndsAt, StartedAt }
	lastRaid = nil,
	lastBroadcast = -math.huge,
	paid = {}, -- [battleId] = { [userId] = true } (fallback payer)
	rng = Random.new(),
	leaders = nil,
	leadersAt = -math.huge,
}

local function now()
	return os.clock()
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function hasFn(m, name)
	return type(m) == "table" and type(m[name]) == "function"
end

local function try(m, name, ...)
	if not hasFn(m, name) then
		return nil
	end
	local ok, a, b, c = pcall(m[name], ...)
	if not ok then
		warn("[EventService] " .. name .. " failed: " .. tostring(a))
		return nil
	end
	return a, b, c
end

local function services()
	local folder = script.Parent
	return folder
end

local lazyModules = {}
local function lazyService(name)
	local dep = St.deps[name]
	if type(dep) == "table" then
		return dep
	end
	if lazyModules[name] == nil then
		lazyModules[name] = false
		local inst = services() and services():FindFirstChild(name)
		if inst then
			local ok, mod = pcall(require, inst)
			if ok and type(mod) == "table" then
				lazyModules[name] = mod
			end
		end
	end
	return lazyModules[name] or nil
end

local function battleService()
	return lazyService("BattleService")
end
local function dataService()
	return lazyService("DataService")
end
local function petCareService()
	return lazyService("PetCareService")
end

local function eventsConfig()
	local e = BattleCatalog and BattleCatalog.Events
	return type(e) == "table" and e or {}
end

local function scheduleEntry(kind)
	for _, entry in ipairs(eventsConfig().Schedule or {}) do
		if type(entry) == "table" and entry.Kind == kind then
			return entry
		end
	end
	return nil
end

local function bossName(bossId)
	local boss = BattleCatalog and type(BattleCatalog.Bosses) == "table" and BattleCatalog.Bosses[bossId]
	return (boss and boss.Name) or tostring(bossId or "the boss")
end

local function petName(petId)
	local def = PetCatalog and hasFn(PetCatalog, "Get") and PetCatalog.Get(petId)
	return (def and def.Name) or tostring(petId)
end

local function isPlayer(p)
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function displayName(player)
	if not isPlayer(player) then
		return "?"
	end
	local n = player.DisplayName
	if type(n) ~= "string" or n == "" then
		n = player.Name
	end
	return n
end

local function getRemote(name)
	local ok, remote = pcall(Remotes.Get, name)
	if ok then
		return remote
	end
	return nil
end

local function clip(text)
	if #text > 90 then
		text = text:sub(1, 89) .. "."
	end
	return text
end

local function notify(player, text, kind, seconds)
	local remote = getRemote("Notify")
	if remote and isPlayer(player) then
		pcall(function()
			remote:FireClient(player, clip(text), kind or "info", seconds or TOAST_SECONDS)
		end)
	end
end

local function notifyAll(text, kind, seconds)
	for _, player in ipairs(Players:GetPlayers()) do
		notify(player, text, kind, seconds)
	end
end

local function minutesText(seconds)
	local m = math.floor((seconds + 30) / 60)
	if m <= 1 then
		return "1 minute"
	end
	return m .. " minutes"
end

----------------------------------------------------------------------
-- Double Rewards
----------------------------------------------------------------------
local function doubleMultiplier()
	local m = tonumber(eventsConfig().DoubleRewardsMultiplier) or 2
	if not finite(m) or m < 1 then
		m = 2
	end
	return m
end

function EventService.IsDoubleRewards()
	local d = St.double
	return d ~= nil and now() < d.EndsAt
end

function EventService.GetDouble()
	local d = St.double
	if not d or now() >= d.EndsAt then
		return nil
	end
	return { Active = true, EndsIn = math.max(0, math.ceil(d.EndsAt - now())) }
end

function EventService.RewardMultiplier()
	if EventService.IsDoubleRewards() then
		return doubleMultiplier()
	end
	return 1
end

function EventService.RaidTierFor(share, won)
	if not BattleCatalog or not hasFn(BattleCatalog, "RaidTier") then
		return nil
	end
	local tier = BattleCatalog.RaidTier(share, won)
	if type(tier) ~= "table" then
		return nil
	end
	local out = {}
	for k, v in pairs(tier) do
		out[k] = v
	end
	out.Tokens = math.floor((tonumber(tier.Tokens) or 0) * EventService.RewardMultiplier() + 0.5)
	return out
end

local function setDoubleAttribute(on)
	pcall(function()
		Workspace:SetAttribute("DoubleRewards", on == true)
	end)
end

local function startDouble(seconds, source)
	seconds = tonumber(seconds) or 3600
	local t = now()
	if St.double and t < St.double.EndsAt then
		St.double.EndsAt = math.max(St.double.EndsAt, t + seconds)
	else
		St.double = { StartedAt = t, EndsAt = t + seconds }
	end
	setDoubleAttribute(true)
	try(battleService(), "SetDoubleRewards", true, St.double.EndsAt - t)
	notifyAll("Double Rewards for " .. minutesText(St.double.EndsAt - t) .. "! Battles pay x" .. doubleMultiplier() .. " tokens.", "good", 7)
	EventService.EventStarted:Fire("DoubleRewards", { Kind = "DoubleRewards", Seconds = St.double.EndsAt - t, Source = source })
	return true
end

local function endDouble()
	if not St.double then
		return
	end
	St.double = nil
	setDoubleAttribute(false)
	try(battleService(), "SetDoubleRewards", nil)
	notifyAll("Double Rewards are over. Thanks for battling!", "info", 5)
	EventService.EventEnded:Fire("DoubleRewards", { Kind = "DoubleRewards" })
end

----------------------------------------------------------------------
-- Boss raids
----------------------------------------------------------------------
local function raidStatus()
	local bs = battleService()
	if not hasFn(bs, "GetRaidStatus") then
		return nil
	end
	local ok, status = pcall(bs.GetRaidStatus)
	if ok and type(status) == "table" then
		return status
	end
	return nil
end

local function raidsPossible()
	local bs = battleService()
	return hasFn(bs, "StartRaid") and BattleCatalog ~= nil and type(BattleCatalog.Bosses) == "table"
end

local function nextBossId()
	St.raidIndex = St.raidIndex + 1
	if BattleCatalog and hasFn(BattleCatalog, "NextBoss") then
		return BattleCatalog.NextBoss(St.raidIndex)
	end
	return nil
end

local function joinWindow()
	return tonumber(eventsConfig().JoinWindowSeconds) or 60
end

local function startRaid(bossId, source)
	local bs = battleService()
	if not hasFn(bs, "StartRaid") then
		return false, "battles are not ready"
	end
	if raidStatus() then
		return false, "a raid is already running"
	end
	local ok, okStart, idOrWhy = pcall(bs.StartRaid, bossId)
	if not ok then
		warn("[EventService] StartRaid failed: " .. tostring(okStart))
		return false, "the raid could not start"
	end
	if okStart ~= true then
		return false, string.lower(tostring(idOrWhy or "the raid could not start"))
	end
	local status = raidStatus()
	local realBoss = (status and status.BossId) or bossId
	St.raid = { BossId = realBoss, StartedAt = now(), Id = idOrWhy }
	notifyAll("Boss Raid! " .. bossName(realBoss) .. " is in the Battle Arena. Join within " .. joinWindow() .. " s!", "good", 7)
	EventService.EventStarted:Fire("BossRaid", { Kind = "BossRaid", BossId = realBoss, Name = bossName(realBoss), BattleId = idOrWhy, Source = source })
	return true, idOrWhy
end

----------------------------------------------------------------------
-- The schedule
----------------------------------------------------------------------
local function everySeconds(entry)
	local m = tonumber(entry.EveryMinutes) or 20
	if not finite(m) or m <= 0 then
		m = 20
	end
	return m * 60
end

local function announceSeconds(entry)
	local a = tonumber(entry.AnnounceSeconds) or 120
	if not finite(a) or a < 0 then
		a = 120
	end
	return a
end

local KINDS = {}

KINDS.BossRaid = {
	Possible = raidsPossible,
	FirstAfter = function(entry)
		return tonumber(entry.FirstAfterSeconds) or tonumber(eventsConfig().FirstAfterSeconds) or 300
	end,
	Prepare = function(slot)
		slot.BossId = nextBossId()
	end,
	Announce = function(slot, secondsLeft)
		notifyAll("Boss Raid in " .. minutesText(secondsLeft) .. ": " .. bossName(slot.BossId) .. "! Gather at the Battle Arena.", "info", 7)
	end,
	Remind = function(slot, secondsLeft)
		notifyAll(bossName(slot.BossId) .. " arrives in " .. math.max(1, math.floor(secondsLeft + 0.5)) .. " s at the Battle Arena!", "info", 5)
	end,
	-- -> "started" | "wait" | "skip"
	Start = function(slot)
		if raidStatus() then
			return "wait"
		end
		local ok = startRaid(slot.BossId, "schedule")
		return ok and "started" or "skip"
	end,
}

KINDS.DoubleRewards = {
	Possible = function()
		return true
	end,
	FirstAfter = function(entry)
		return tonumber(entry.FirstAfterSeconds) or everySeconds(entry)
	end,
	Prepare = function() end,
	Announce = function(_, secondsLeft)
		notifyAll("Double Rewards hour in " .. minutesText(secondsLeft) .. "! Battle tokens x" .. doubleMultiplier() .. ".", "info", 7)
	end,
	Start = function(slot)
		startDouble(tonumber(slot.Entry.DurationSeconds) or 3600, "schedule")
		return "started"
	end,
}

local function buildSlots()
	St.slots = {}
	local t = now()
	for _, entry in ipairs(eventsConfig().Schedule or {}) do
		local kind = type(entry) == "table" and KINDS[entry.Kind]
		if kind then
			local slot = { Kind = entry.Kind, Entry = entry, At = t + kind.FirstAfter(entry), Announced = false, Reminded = false }
			kind.Prepare(slot)
			St.slots[entry.Kind] = slot
		end
	end
end

-- moves a slot to its next occurrence (counted from now, so a stalled server never fires a burst)
local function reschedule(slot, from)
	local kind = KINDS[slot.Kind]
	slot.At = (from or now()) + everySeconds(slot.Entry)
	slot.Announced = false
	slot.Reminded = false
	kind.Prepare(slot)
end

local function tickSlot(slot, t)
	local kind = KINDS[slot.Kind]
	if not kind or not kind.Possible() then
		return
	end
	local left = slot.At - t
	local announce = announceSeconds(slot.Entry)
	if not slot.Announced and left <= announce and left > 0 then
		slot.Announced = true
		kind.Announce(slot, left)
		EventService.EventAnnounced:Fire(slot.Kind, { Kind = slot.Kind, BossId = slot.BossId, Name = slot.BossId and bossName(slot.BossId) or nil, StartsIn = math.ceil(left) })
	end
	if kind.Remind and not slot.Reminded and left <= REMINDER_SECONDS and left > 0 then
		slot.Reminded = true
		kind.Remind(slot, left)
	end
	if left <= 0 then
		local result = kind.Start(slot)
		if result == "wait" then
			slot.At = t + POSTPONE
		else
			reschedule(slot, t)
		end
	end
end

----------------------------------------------------------------------
-- Leaderboard + ArenaState
----------------------------------------------------------------------
local function trophiesOf(player)
	local battle = try(dataService(), "GetBattle", player)
	if type(battle) == "table" and finite(tonumber(battle.Trophies)) then
		return math.max(0, math.floor(tonumber(battle.Trophies)))
	end
	return nil
end

local function leaderboard()
	local t = now()
	if St.leaders and t - St.leadersAt < BROADCAST_SLOW - 0.5 then
		return St.leaders
	end
	local rows = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local trophies = trophiesOf(player)
		if trophies then
			rows[#rows + 1] = { UserId = player.UserId, Name = displayName(player), Trophies = trophies }
		end
	end
	table.sort(rows, function(a, b)
		if a.Trophies ~= b.Trophies then
			return a.Trophies > b.Trophies
		end
		return a.Name < b.Name
	end)
	local out = {}
	for i = 1, math.min(LEADERS, #rows) do
		out[i] = rows[i]
	end
	St.leaders = out
	St.leadersAt = t
	return out
end

local function nextEvent()
	local best = nil
	for _, slot in pairs(St.slots) do
		local kind = KINDS[slot.Kind]
		if kind and kind.Possible() and (not best or slot.At < best.At) then
			best = slot
		end
	end
	return best
end

local function slotInfo(slot, t)
	if not slot then
		return nil
	end
	return {
		Kind = slot.Kind,
		BossId = slot.BossId,
		Name = slot.BossId and bossName(slot.BossId) or nil,
		StartsIn = math.max(0, math.ceil(slot.At - t)),
		Announced = slot.Announced == true,
	}
end

function EventService.GetState()
	local t = now()
	local state = {
		Next = slotInfo(nextEvent(), t),
		Raid = raidStatus(),
		Double = EventService.GetDouble(),
		Leaderboard = leaderboard(),
		Multiplier = EventService.RewardMultiplier(),
	}
	local raidSlot = St.slots.BossRaid
	if raidSlot and KINDS.BossRaid.Possible() then
		state.NextRaid = { BossId = raidSlot.BossId, Name = bossName(raidSlot.BossId), StartsIn = math.max(0, math.ceil(raidSlot.At - t)) }
	end
	if St.lastRaid then
		local lr = {}
		for k, v in pairs(St.lastRaid) do
			lr[k] = v
		end
		lr.Ago = math.floor(t - (St.lastRaid.EndedAt or t))
		lr.EndedAt = nil
		state.LastRaid = lr
	end
	return state
end

-- what the boards show, with countdowns as absolute times (ArenaBuilder ticks them down by itself between two
-- states): the boards are redrawn only when this changes, or every BOARD_KEEPALIVE s (it falls back to its own
-- schedule after ~20 s of silence)
local BOARD_KEEPALIVE = 12
local function boardSignature(state, t)
	local parts = {}
	local function add(v)
		parts[#parts + 1] = tostring(v)
	end
	local function at(seconds)
		return math.floor((t + (tonumber(seconds) or 0)) / 2 + 0.5)
	end
	local n = state.Next
	if type(n) == "table" then
		add(n.Kind)
		add(n.BossId)
		add(at(n.StartsIn))
	end
	local r = state.Raid
	if type(r) == "table" then
		add(r.Active)
		add(r.BossId)
		add(r.Hp)
		add(r.MaxHp)
		add(r.Players)
		add(at(r.EndsIn))
	end
	local d = state.Double
	if type(d) == "table" then
		add(d.Active)
		add(at(d.EndsIn))
	end
	for _, row in ipairs(state.Leaderboard or {}) do
		add(row.UserId)
		add(row.Name)
		add(row.Trophies)
	end
	return table.concat(parts, "|")
end

local function applyBoards(state)
	local t = now()
	local sig = boardSignature(state, t)
	if sig == St.boardSig and St.boardAt and t - St.boardAt < BOARD_KEEPALIVE then
		return
	end
	St.boardSig = sig
	St.boardAt = t
	local info = St.deps.ArenaInfo
	local apply = type(info) == "table" and info.ApplyArenaState
	if type(apply) ~= "function" then
		local ab = lazyService("ArenaBuilder")
		apply = hasFn(ab, "ApplyArenaState") and ab.ApplyArenaState or nil
	end
	if apply then
		local ok, err = pcall(apply, state)
		if not ok then
			warn("[EventService] ApplyArenaState failed: " .. tostring(err))
		end
	end
end

function EventService.Broadcast(player)
	local state = EventService.GetState()
	local remote = getRemote("ArenaState")
	if remote then
		pcall(function()
			if player then
				if isPlayer(player) then
					remote:FireClient(player, state)
				end
			else
				remote:FireAllClients(state)
			end
		end)
	end
	if not player then
		St.lastBroadcast = now()
		applyBoards(state)
	end
	return state
end

local function fastMode(t)
	if raidStatus() then
		return true
	end
	for _, slot in pairs(St.slots) do
		if slot.Announced and slot.At - t <= announceSeconds(slot.Entry) + 1 then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Raid results: the everyone-toast, the event pet shout-out, the fallback payer
----------------------------------------------------------------------
local function grantEventPet(player)
	if not BattleCatalog or not hasFn(BattleCatalog, "EventPets") or not PetKeys or not PetCatalog then
		return nil
	end
	local list = BattleCatalog.EventPets()
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local DS = dataService()
	local profile = try(DS, "GetProfile", player)
	if type(profile) ~= "table" then
		return nil
	end
	local chosen = nil
	local ok = try(DS, "MutateBattle", player, function(rec)
		if type(rec.EventPets) ~= "table" then
			rec.EventPets = {}
		end
		local candidates = {}
		for _, id in ipairs(list) do
			if type(id) == "string" and rec.EventPets[id] ~= true and PetCatalog.Get(id) then
				candidates[#candidates + 1] = id
			end
		end
		if #candidates == 0 then
			return false
		end
		chosen = candidates[St.rng:NextInteger(1, #candidates)]
		rec.EventPets[chosen] = true
	end)
	if ok ~= true or not chosen then
		return nil
	end
	local okAdd, added = pcall(PetKeys.Add, profile, chosen, 1)
	if not okAdd or not added then
		return nil
	end
	try(DS, "MarkDiscovered", player, chosen)
	try(DS, "MarkDirty", player)
	if hasFn(DS, "SyncSoon") then
		try(DS, "SyncSoon", player)
	else
		try(DS, "Sync", player)
	end
	return chosen
end

-- pays one raider's tier when BattleService did not (see the header). Marked before anything is paid.
local function payRaider(battleId, result, uid, won)
	local paid = St.paid[battleId]
	if not paid then
		paid = {}
		St.paid[battleId] = paid
	end
	if paid[uid] then
		return nil
	end
	paid[uid] = true
	local player = Players:GetPlayerByUserId(uid)
	if not isPlayer(player) then
		return nil
	end
	local share = (type(result.Shares) == "table" and tonumber(result.Shares[uid] or result.Shares[tostring(uid)])) or 0
	local damage = (type(result.Damage) == "table" and tonumber(result.Damage[uid] or result.Damage[tostring(uid)])) or 0
	local tier = EventService.RaidTierFor(share, won)
	if not tier then
		return nil
	end
	local DS = dataService()
	try(DS, "MutateBattle", player, function(rec)
		rec.Raids = (tonumber(rec.Raids) or 0) + 1
		if damage > (tonumber(rec.RaidBestDamage) or 0) then
			rec.RaidBestDamage = math.floor(damage)
		end
	end)
	local eventPet = nil
	if (tonumber(tier.EventPetChance) or 0) > 0 and St.rng:NextNumber() < tier.EventPetChance then
		eventPet = grantEventPet(player)
	end
	if (tonumber(tier.Tokens) or 0) > 0 then
		try(DS, "AddTokens", player, tier.Tokens)
	end
	local gems = 0
	if (tonumber(tier.GemChance) or 0) > 0 and St.rng:NextNumber() < tier.GemChance then
		gems = tonumber(tier.Gems) or 0
		if gems > 0 and try(DS, "AddGems", player, gems) ~= true then
			gems = 0
		end
	end
	local xp = tonumber(tier.Xp) or 0
	if xp > 0 then
		local keys = try(DS, "ActiveTeamKeys", player) or {}
		local care = petCareService()
		for _, key in ipairs(keys) do
			if hasFn(care, "GrantXp") then
				try(care, "GrantXp", player, key, xp, "Raid")
			else
				try(DS, "AddPetXp", player, key, xp)
			end
		end
	end
	local text = (won and "Boss defeated! " or "The boss won this time. ") .. tostring(tier.Id) .. " tier: +" .. tier.Tokens .. " tokens"
	if gems > 0 then
		text = text .. ", +" .. gems .. " gems"
	end
	notify(player, text, won and "good" or "info", 6)
	if eventPet then
		notify(player, "Event pet! " .. petName(eventPet) .. " joined your pets!", "good", 7)
	end
	return { Tier = tier.Id, Tokens = tier.Tokens, Gems = gems, Xp = xp, EventPet = eventPet }
end

local function onBattleEnded(battleId, result)
	if type(result) ~= "table" or result.Mode ~= "Raid" then
		return
	end
	local bossId = result.BossId or (St.raid and St.raid.BossId)
	local won = type(result.Winners) == "table" and #result.Winners > 0
	local participants = {}
	if type(result.Participants) == "table" then
		for _, uid in ipairs(result.Participants) do
			participants[#participants + 1] = tonumber(uid)
		end
	end
	if #participants == 0 and type(result.Damage) == "table" then
		for uid in pairs(result.Damage) do
			participants[#participants + 1] = tonumber(uid)
		end
	end
	-- the raiders who were still in at the end (result.Fighters; leavers are not counted): the toast and LastRaid.Players
	local fighters = {}
	if type(result.Fighters) == "table" then
		for _, uid in ipairs(result.Fighters) do
			fighters[#fighters + 1] = tonumber(uid)
		end
	else
		fighters = participants
	end
	-- fallback payer: only when BattleService did not pay (never both)
	local rewards = type(result.Rewards) == "table" and result.Rewards or {}
	local bs = battleService()
	if result.RewardsPaid ~= true and type(bs) == "table" and bs.PayRaidRewards == false then
		for _, uid in ipairs(participants) do
			if uid then
				local rw = payRaider(battleId, result, uid, won)
				if rw then
					rewards[uid] = rw
				end
			end
		end
	end
	-- the summary everyone sees on the boards + one toast
	local top = {}
	for _, uid in ipairs(participants) do
		if uid then
			local player = Players:GetPlayerByUserId(uid)
			local dmg = type(result.Damage) == "table" and tonumber(result.Damage[uid] or result.Damage[tostring(uid)]) or 0
			local rw = rewards[uid] or rewards[tostring(uid)]
			top[#top + 1] = { UserId = uid, Name = player and displayName(player) or tostring(uid), Damage = math.floor(dmg or 0), Tier = type(rw) == "table" and rw.Tier or nil }
		end
	end
	table.sort(top, function(a, b)
		return a.Damage > b.Damage
	end)
	while #top > 5 do
		table.remove(top)
	end
	St.lastRaid = { BossId = bossId, Name = bossName(bossId), Won = won, Players = #fighters, Top = top, EndedAt = now() }
	St.raid = nil
	local raidSlot = St.slots.BossRaid
	local nextText = ""
	if raidSlot then
		nextText = " Next raid in " .. minutesText(math.max(60, raidSlot.At - now())) .. "."
	end
	if #participants == 0 then
		notifyAll("Nobody fought " .. bossName(bossId) .. "." .. nextText, "info", 5)
	elseif won then
		notifyAll(bossName(bossId) .. " was defeated by " .. #fighters .. (#fighters == 1 and " raider!" or " raiders!") .. nextText, "good", 6)
	else
		notifyAll(bossName(bossId) .. " won this time." .. nextText, "info", 6)
	end
	-- shout-out for every event pet won (BattleService or the fallback payer)
	for uid, rw in pairs(rewards) do
		if type(rw) == "table" and type(rw.EventPet) == "string" then
			local player = Players:GetPlayerByUserId(tonumber(uid) or -1)
			local who = player and displayName(player) or "A raider"
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player then
					notify(other, who .. " won the event pet " .. petName(rw.EventPet) .. "!", "good", 6)
				end
			end
		end
	end
	EventService.EventEnded:Fire("BossRaid", { Kind = "BossRaid", BossId = bossId, Name = bossName(bossId), Won = won, Players = #fighters, BattleId = battleId })
	EventService.Broadcast()
end

----------------------------------------------------------------------
-- StartNow (developer tools)
----------------------------------------------------------------------
function EventService.StartNow(kind, bossId)
	if kind == nil or kind == "raid" or kind == "Raid" then
		kind = "BossRaid"
	elseif kind == "double" or kind == "Double" then
		kind = "DoubleRewards"
	end
	if kind == "BossRaid" then
		if not raidsPossible() then
			return false, "boss raids are not ready in this build"
		end
		if raidStatus() then
			return false, "a raid is already running"
		end
		local slot = St.slots.BossRaid
		local boss = nil
		if type(bossId) == "string" and BattleCatalog.Bosses[bossId] then
			boss = bossId
		elseif slot and slot.BossId then
			boss = slot.BossId
		else
			boss = nextBossId()
		end
		local ok, why = startRaid(boss, "dev")
		if not ok then
			return false, why
		end
		-- the cycle restarts from now (the announced boss was used, the next one is queued)
		if slot then
			reschedule(slot, now())
		end
		EventService.Broadcast()
		return true, "raid started: " .. bossName(boss) .. " (join at the Arena within " .. joinWindow() .. " s)"
	elseif kind == "DoubleRewards" then
		local entry = scheduleEntry("DoubleRewards") or {}
		startDouble(tonumber(entry.DurationSeconds) or 3600, "dev")
		EventService.Broadcast()
		return true, "Double Rewards for " .. minutesText(St.double.EndsAt - now())
	end
	return false, "unknown event " .. tostring(kind)
end

-- extra (developer tools / tests): ends a running event now -> ok, message
function EventService.EndNow(kind)
	if kind == "DoubleRewards" or kind == "double" then
		if not EventService.IsDoubleRewards() then
			return false, "no Double Rewards running"
		end
		endDouble()
		EventService.Broadcast()
		return true, "Double Rewards ended"
	elseif kind == nil or kind == "BossRaid" or kind == "raid" then
		if not raidStatus() then
			return false, "no raid running"
		end
		try(battleService(), "EndRaid", "Ended")
		EventService.Broadcast()
		return true, "raid ended"
	end
	return false, "unknown event " .. tostring(kind)
end

----------------------------------------------------------------------
-- The loop
----------------------------------------------------------------------
local function tick()
	local t = now()
	if St.double and t >= St.double.EndsAt then
		endDouble()
	end
	-- a raid that outlived every limit is closed (BattleService normally ends it itself)
	local status = raidStatus()
	if status and not St.raid then
		St.raid = { BossId = status.BossId, StartedAt = t, Id = status.BattleId }
	end
	if St.raid and status then
		local boss = BattleCatalog and BattleCatalog.Bosses and BattleCatalog.Bosses[St.raid.BossId]
		local limit = (scheduleEntry("BossRaid") or {}).DurationSeconds or (boss and boss.TimeLimit) or 330
		if t - St.raid.StartedAt > limit + joinWindow() + RAID_GRACE then
			try(battleService(), "EndRaid", "Timeout")
		end
	elseif St.raid and not status and t - St.raid.StartedAt > 5 then
		St.raid = nil -- ended without a BattleEnded we heard (should not happen)
	end
	for _, slot in pairs(St.slots) do
		local ok, err = pcall(tickSlot, slot, t)
		if not ok then
			warn("[EventService] " .. tostring(slot.Kind) .. " failed: " .. tostring(err))
			reschedule(slot, t)
		end
	end
	local period = fastMode(t) and BROADCAST_FAST or BROADCAST_SLOW
	if t - St.lastBroadcast >= period - 0.05 then
		EventService.Broadcast()
	end
end

function EventService.Init(deps)
	if St.initialized then
		return
	end
	St.initialized = true
	St.deps = type(deps) == "table" and deps or {}
	if not BattleCatalog then
		warn("[EventService] BattleCatalog missing: no events")
	end
	buildSlots()
	setDoubleAttribute(false)
	local bs = battleService()
	if type(bs) == "table" and type(bs.BattleEnded) == "table" and hasFn(bs.BattleEnded, "Connect") then
		bs.BattleEnded:Connect(function(battleId, result)
			local ok, err = pcall(onBattleEnded, battleId, result)
			if not ok then
				warn("[EventService] raid result failed: " .. tostring(err))
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		St.leaders = nil -- a new face on the leaderboard
		EventService.Broadcast(player)
	end)
	Players.PlayerRemoving:Connect(function()
		St.leaders = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		EventService.Broadcast(player)
	end
	St.running = true
	task.spawn(function()
		while St.running do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[EventService] tick failed: " .. tostring(err))
			end
		end
	end)
	EventService.Broadcast()
end

-- extra (tests): the scheduled time of a kind, seconds from now (nil when not scheduled)
function EventService.SecondsUntil(kind)
	local slot = St.slots[kind]
	if not slot then
		return nil
	end
	return slot.At - now()
end

return EventService
