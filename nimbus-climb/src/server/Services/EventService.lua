-- EventService (Phase 3, events): the arena's special events (ARCHITECTURE_V3.md "Phase 3: Pet battles" -> "Special
-- events system", the "Phase 3 build contract" and its "Interfaces between the Phase 3 modules").
--
--   EventService.Init(deps)        deps = { DataService, BattleService, PetCareService, ArenaInfo } (all optional; players
--                                  already in the game get the ArenaState at once)
--   EventService.StartNow(kind, bossId|nil) -> ok, message      start an event at once (developer tools: /raid, the DEV panel's
--                                  "Next raid boss"): kind = "BossRaid" (the next boss now, or when the running fights end) | "DoubleRewards"
--   EventService.RewardMultiplier() -> n                         BattleCatalog.Events.DoubleRewardsMultiplier during a
--                                  Double Rewards hour, else 1 (BattleService multiplies battle Tokens by it)
--   EventService.IsDoubleRewards() -> bool, EventService.GetDouble() -> { Active, EndsIn } | nil
--   EventService.GetState() -> the ArenaState table (below), EventService.Broadcast() sends it now
--   Extras: EndNow(kind) -> ok, message (ends a running event), SecondsUntil(kind) -> seconds to the next one
--   EventService.RaidTierFor(share, won, tierId) -> BattleCatalog.RaidTier(...) with the Tokens of this moment (Double Rewards)
--   EventService.RaidFloorStarted(info): BattleService tells a floor fight began; fires EventStarted("BossRaid", info)
--   Signals (exist at module load, Util.Signal): EventAnnounced(kind, info), EventStarted(kind, info),
--   EventEnded(kind, info). info = { Kind, BossId, Name, StartsIn | Seconds, Won, Players, ... }
--
-- The scheduler (numbers from BattleCatalog.Events, never duplicated here):
--   * Boss Raid: the boss is always there (BattleService runs the fights, see its header), so the BossRaid slot is only the ROTATION:
--     every Schedule.BossRaid.EveryMinutes (20), the first FirstAfterSeconds (300) after the server starts,
--     BattleService.SetRaidBoss(the next of BattleCatalog.NextBoss) changes the boss, at once or when the running fights end. No
--     announcement, no toast. On BattleService.BattleEnded (Mode "Raid"), a win is told to everyone with who won an event pet;
--     EventStarted / EventEnded("BossRaid") follow the FLOOR fight only (the server-wide sky and the boards).
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
--   { Next = { Kind, BossId, Name, StartsIn, Announced } | nil   (the soonest event players are told about; the silent boss rotation is Raid.NextBoss)
--     Raid = BattleService.GetRaidStatus() -> { BossId, Name, Active, BattleId, FloorTier, FloorHiddenIn, Fights, Closed } + NextBossIn,
--            NextBoss (the rotation) | nil
--     Double = { Active, EndsIn } | nil
--     Leaderboard = { { UserId, Name, Trophies } x 10 }   (the players in this server, by Battle.Trophies)
--     -- extras: LastRaid = { BossId, Name, Tier, Won, Players, Top = { { UserId, Name, Damage, Tier }... }, Ago } | nil, Multiplier = n }
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
local BROADCAST_FAST = 1 -- ArenaState period while a countdown or a raid fight runs
local BROADCAST_SLOW = 5 -- ... otherwise
local TOAST_SECONDS = 6
local LEADERS = 10

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local St = {
	initialized = false,
	running = false,
	deps = {},
	slots = {}, -- [kind] = { Kind, At, Announced, Entry, BossId }
	raidIndex = 1, -- the rotation position of the last boss that was scheduled (BossOrder[1] waits from the start: BattleService.Init)
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

function EventService.RaidTierFor(share, won, tierId)
	if not BattleCatalog or not hasFn(BattleCatalog, "RaidTier") then
		return nil
	end
	local tier = BattleCatalog.RaidTier(share, won, tierId)
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
	return hasFn(bs, "SetRaidBoss") and BattleCatalog ~= nil and type(BattleCatalog.Bosses) == "table"
end

local function nextBossId()
	St.raidIndex = St.raidIndex + 1
	if BattleCatalog and hasFn(BattleCatalog, "NextBoss") then
		return BattleCatalog.NextBoss(St.raidIndex)
	end
	return nil
end

-- the rotation's step -> ok, "set" | "queued" | why
local function setRaidBoss(bossId)
	local ok, okSet, how = pcall(battleService().SetRaidBoss, bossId)
	if not ok then
		warn("[EventService] SetRaidBoss failed: " .. tostring(okSet))
		return false, "the boss could not change"
	end
	if okSet ~= true then
		return false, string.lower(tostring(how or "the boss could not change"))
	end
	return true, how
end

-- BattleService: a fight began on the real floor (the server-wide sky and the boards follow that one)
function EventService.RaidFloorStarted(info)
	EventService.EventStarted:Fire("BossRaid", info)
	EventService.Broadcast()
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
	Silent = true, -- the rotation: no toast, no EventAnnounced, no fast ArenaState
	FirstAfter = function(entry)
		return tonumber(entry.FirstAfterSeconds) or tonumber(eventsConfig().FirstAfterSeconds) or 300
	end,
	Prepare = function(slot)
		slot.BossId = nextBossId()
	end,
	Start = function(slot)
		setRaidBoss(slot.BossId)
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
	end,
}

local function buildSlots()
	St.slots = {}
	local t = now()
	for _, entry in ipairs(eventsConfig().Schedule or {}) do
		local kind = type(entry) == "table" and KINDS[entry.Kind]
		if kind then
			local slot = { Kind = entry.Kind, Entry = entry, At = t + kind.FirstAfter(entry), Announced = false }
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
	kind.Prepare(slot)
end

local function tickSlot(slot, t)
	local kind = KINDS[slot.Kind]
	if not kind or not kind.Possible() then
		return
	end
	local left = slot.At - t
	local announce = announceSeconds(slot.Entry)
	if not kind.Silent and not slot.Announced and left <= announce and left > 0 then
		slot.Announced = true
		kind.Announce(slot, left)
		EventService.EventAnnounced:Fire(slot.Kind, { Kind = slot.Kind, BossId = slot.BossId, Name = slot.BossId and bossName(slot.BossId) or nil, StartsIn = math.ceil(left) })
	end
	if left <= 0 then
		kind.Start(slot)
		reschedule(slot, t)
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
		if kind and not kind.Silent and kind.Possible() and (not best or slot.At < best.At) then
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
	if state.Raid and raidSlot and KINDS.BossRaid.Possible() then
		state.Raid.NextBoss = raidSlot.BossId
		state.Raid.NextBossIn = math.max(0, math.ceil(raidSlot.At - t))
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
		add(r.FloorTier)
		add(at(r.NextBossIn))
		for _, tierId in ipairs((BattleCatalog and BattleCatalog.RaidTierOrder) or {}) do
			local f = type(r.Fights) == "table" and r.Fights[tierId]
			if type(f) == "table" then
				add(tierId)
				add(f.Hp)
				add(f.MaxHp)
				add(f.Players)
				add(at(f.EndsIn))
			end
		end
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
	local raid = raidStatus()
	if raid and type(raid.Fights) == "table" and next(raid.Fights) ~= nil then
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
	-- the same reward clocks as BattleService's payer: nothing while the limit runs, a payment stamps it
	local clocks = try(battleService(), "RaidRewardStatus", player)
	if type(clocks) == "table" and ((won and clocks.WinIn > 0) or (not won and clocks.LossIn > 0)) then
		return nil
	end
	local share = (type(result.Shares) == "table" and tonumber(result.Shares[uid] or result.Shares[tostring(uid)])) or 0
	local damage = (type(result.Damage) == "table" and tonumber(result.Damage[uid] or result.Damage[tostring(uid)])) or 0
	local tier = EventService.RaidTierFor(share, won, result.RaidTier)
	if not tier then
		return nil
	end
	local DS = dataService()
	try(DS, "MutateBattle", player, function(rec)
		rec.Raids = (tonumber(rec.Raids) or 0) + 1
		if damage > (tonumber(rec.RaidBestDamage) or 0) then
			rec.RaidBestDamage = math.floor(damage)
		end
		if type(clocks) == "table" and won then
			rec.RaidRewardAt = clocks.Now
		elseif type(clocks) == "table" then
			rec.RaidLossAt = clocks.Now
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
	local bossId = result.BossId
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
	St.lastRaid = { BossId = bossId, Name = bossName(bossId), Tier = result.RaidTier, Won = won, Players = #fighters, Top = top, EndedAt = now() }
	if won then
		local who = bossName(bossId) .. (result.RaidTier and (" (" .. tostring(result.RaidTier) .. ")") or "")
		notifyAll(who .. " was defeated by " .. #fighters .. (#fighters == 1 and " raider!" or " raiders!"), "good", 6)
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
	if result.RaidFloor == true then
		EventService.EventEnded:Fire("BossRaid", { Kind = "BossRaid", BossId = bossId, Name = bossName(bossId), Tier = result.RaidTier, Won = won, Players = #fighters, BattleId = battleId })
	end
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
		local slot = St.slots.BossRaid
		local boss = nil
		if type(bossId) == "string" and BattleCatalog.Bosses[bossId] then
			boss = bossId
		elseif slot and slot.BossId then
			boss = slot.BossId
		else
			boss = nextBossId()
		end
		local ok, how = setRaidBoss(boss)
		if not ok then
			return false, how
		end
		-- the cycle restarts from now (the waiting boss was used, the next one is queued)
		if slot then
			reschedule(slot, now())
		end
		EventService.Broadcast()
		return true, "next boss: " .. bossName(boss) .. (how == "set" and " (now)" or " (when the fights end)")
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
		local ended = try(battleService(), "EndRaids", "Ended")
		if not ended or ended <= 0 then
			return false, "no raid running"
		end
		EventService.Broadcast()
		return true, ended == 1 and "raid ended" or (ended .. " raids ended")
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
