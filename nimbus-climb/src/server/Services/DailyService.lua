-- DailyService (store 2026-11-04; docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.2 / 6 / 7 Z8-Z9 / 13b.2-4):
-- the daily gifts behind the one Gifts button: the 7-day streak and the per-day play-time tiers (Config.Daily). Every
-- grant is server-decided, written with its claim in ONE non-yielding DataService.MutateDaily step (the merge's
-- DailyClaims record) and paid right after; the client reads only DailyState.
--
-- The streak (5.2, 13b.2-3)
--   * Ready ReadySeconds (20 h) after the last claim on the SERVER clock (os.time()); kept when claimed within
--     KeepSeconds (48 h): Streak = kept days, cumulative; a claim makes it Streak + 1 and pays cell ((Streak - 1) % 7) + 1
--     of the NEW value (claim 8 = cell 1 of week 2). Weeks = max(Weeks, floor(Streak / 7)) never drops.
--   * A miss steps back one day per missed day at the next claim: stepBack = 1 + floor((gap - 48 h) / 86400),
--     Streak = max(0, Streak - stepBack) + 1. Exactly 48 h is still kept; the boundary is a strict '>'.
--   * Re-earned, never re-paid: Paid = the highest Streak ever paid; a claim pays only when the new Streak > Paid, else
--     "Streak repaired! Day N of 7" and nothing. A miss costs one gift per missed day, never the week. State says what
--     the next claim does before it (re-review 1 and 2): Repair = (the streak it builds on + 1 <= Paid), Claim's own
--     rule, for EVERY claim: the step-back claim and the kept claims after it that climb back to Paid, and a VIP's
--     while Paid > Streak; the Days' Claimed / Today come from that streak (Today on the repair cell, flagged Repair),
--     never a gift the claim will not pay. StaleAt = the moment that view changes by itself (the keep deadline passing,
--     KeepUntil + 1, then each further missed day; 0 = never): the tick re-sends the payload then, and a VIP answer that
--     changes Vip (StoreService.Changed) re-sends it at once. The wait before such a claim names no gift either
--     (re-review 3): a claim sent before it is ready is refused with "Streak repair in 4h 12m" (the window counts down
--     the same text), "Next gift in 4h 12m" only before a claim that pays.
--   * VIP (StoreService.Owns(player, "VIP")) never steps back and gets x2 (Config.Store.Perks.Vip.DailyMult) on the
--     Cash and Tokens cells only (never Gems, the pet or the play tiers). A pass still "Checking" with a step-back due
--     holds the claim ("Checking your VIP pass, one moment", nothing written); no StoreService or an Unavailable pass
--     = never VIP, never held. Attributes are never read for the pass (Z3).
--   * Day 7 of every kept week grants week_wisp through PetService.GrantPet (13b.2); the stack room is checked BEFORE
--     the claim: a full stack resolves the cell's Else (40 Gems). Daily.Pet turns true with the first pet grant.
--   * Cash cells are income-minutes with a floor: max(Min, floor(TycoonService.IncomePerSecond x Minutes x 60)),
--     resolved at state time (the payload carries numbers, 13b.3) and again at the claim (the claim pays its own
--     value). Berries = "Basket" fills the Berry Basket to TycoonCatalog.BasketCap(home, income) minus what is owned.
--   * Z8: a stored LastClaimAt more than FutureClockSlack ahead of now (a wrong clock: the server that wrote it ran
--     fast, or this one runs behind) counts as the now of its FIRST SIGHT (State at the join, so the join's ReadyAt is
--     now + 20 h and the window counts down to a claim; or a claim, which is then refused once with "Next gift in 20h
--     0m"): the player is never locked out for hours. LastClaimAt itself is NEVER written (re-review 1: a bare clamp in
--     the store would let a server whose clock runs behind pull the next gift earlier on every other server, visit after
--     visit). The first sight is noted next to it (re-review 2): Daily.ClampFrom = the stamp, ClampAt = that now,
--     ClampJob = this server's game.JobId (one MutateDaily, NO grant, only when the record holds no first sight of this
--     stamp from this server), so a later session on THIS server counts from the same moment instead of starting the
--     20 h over (a rejoin here). A sight another server noted is never reused (re-review 3): it is a reading of another
--     clock, and a slower one would start the countdown early; that session counts from its own first sight and notes
--     it in its place. A server that sees the stamp as past uses the stamp itself: a slow server's first sight of a
--     correct claim never pulls the gift earlier there. The costs (accepted, spec Z8): a session on another server
--     starts the 20 h over while the stamp still reads ahead there (bounded by the stamp's lead); when a fast server's
--     stamp falls behind the clocks before the countdown ends, a NEW session counts from the stamp (at most that clock's
--     offset later than the window said); the session that saw it keeps its countdown. A changed stamp (a claim, a
--     rebase) drops the session's clamp; a claim clears ClampFrom / ClampAt / ClampJob. A second request finds
--     LastClaimAt = now. Two servers: the section 6 merge (a claim
--     less than ReadySeconds after a STORED claim it did not build on loses its grant; the grant's Prev names the stamp
--     it built on, so a claim after a clamp is no exception). The claim's one `now` is its LastClaimAt AND its grant's At
--     (MutateDaily's `now` argument): a second ticking inside Claim never splits the pair from its grant in the merge.
--
-- Play time (5.2, 13b.4, Q17, Z9)
--   * Per play-day on the rolling PlayStart clock: a Tick every TickSeconds (10 s) counts for a player whose root moved
--     more than MoveStuds since the last sample OR whose client fired one of Play.ActiveRemotes within ActiveWindow
--     (180 s; this service adds its own OnServerEvent listener to each). The first tick >= DaySeconds (20 h) after
--     PlayStart starts a new day, counting or not: PlayStart = now, PlaySec = 0, PlayClaimed = {} (unclaimed tiers are
--     LOST, Q17); until that tick runs (no root) State shows no tier Ready and ClaimPlay refuses ("That play day is
--     over!"). A first PlayStart is set by the first COUNTING tick only.
--     PlaySec caps at MaxDaySeconds (10 h). Matches count as play; a provisional profile never ticks (its stand-in's
--     PlayStart would win the stored Play group).
--   * No root (no Character, no HumanoidRootPart) or a dead Humanoid (between respawns): nothing happens: no seconds,
--     no PlayStart reset, no sample (Review Focus 4).
--   * Play.Active (the paused clock, 13b.4) is sent on each CHANGE, never per tick; a tier crossing or a day reset
--     sends too (the pip shake).
--   * ClaimPlay(tier): PlaySec >= Tiers[tier].Min x 60 and not yet claimed: the flag and the grant in one step
--     ({ Kind = "Play", Tier }), paid right after; two servers at one PlayStart pay once (the (PlayStart, tier) merge).
--
-- The 10-minute unlock and the hold (gui-redo, docs/superpowers/specs/2026-11-06-window-redo-design.md 5.3)
--   * Every streak claim (a paid day, the Week Wisp, the first ever, a VIP's, the repair) needs Config.Daily.UnlockSeconds
--     (600) counted play seconds of the current play-day: the play clock above (PlaySec on a live PlayStart; a play-day
--     not started or over counts 0; its AFK rule; its 20 h reset restarts the count; a provisional profile never ticks).
--     Claim order: loaded -> not ready (the texts above) -> LOCKED: refused, nothing written, "Play 6 more min to unlock
--     today's gift!" / "Play 6 more min to repair your streak!" (a claim that would only repair; minutes = ceil(left / 60))
--     -> VIP "Checking" -> the step-back -> commit and pay. Play tiers and the Trove are not affected. 0 = the rule off.
--   * The hold: the step-back gap is measured at keepAt, never later than now (keepOf, shared by State and Claim): from =
--     min(the live PlayStart, now - this session's held seconds for this stamp), keepAt = min(now, max(from, last +
--     ReadySeconds)). The held seconds (holds[player] = { Last = the stamp, Sec }, in memory only, dropped on leave and by
--     a claim) grow by TickSeconds on each COUNTING tick that finds the gift due and still locked (PlaySec after any reset,
--     before the tick's add, < UnlockSeconds); a changed stamp (a claim, a rebase, another server's claim) starts them at
--     0. So playing toward the unlock never counts as time away, even across a play-day reset or a hop (the stored
--     PlayStart). UnlockSeconds 0: keepAt = now (today's step-backs exactly).
--   * State uses keepAt for the missed streak, Repair, Cell and Today; StaleAt: held by PlayStart -> its play-day's end
--     (PlayStart + DaySeconds); held by the session's seconds -> today's rule at keepAt + Sec; else today's rule at now.
--   * Payload: Unlock = { Need = UnlockSeconds, Left = max(0, Need - live PlaySec) } (Loading: Left = Need). The tick sends
--     a payload when the live PlaySec crosses UnlockSeconds (before < Need <= after), so CLAIM shows on time.
--
-- Remote DailyRequest(action, tier): "Claim" (no second argument) / "ClaimPlay" (a whole 1..7). isPlayer, one request
-- per second per action, type checks, refused InMatch with a toast; junk is dropped without an answer (Z12).
-- ProfileLoaded / ProfileRebased -> Send(player) (a Loading payload while provisional), NO Notify on load: nothing is
-- announced on join (the client's pip waits PipDelaySeconds). The tick re-sends a payload whose StaleAt has passed;
-- StoreService.Changed re-sends it when the VIP answer differs from the last payload's Vip.
--
-- Public API
--   DailyService.Init(deps)              deps = { DataService, StoreService?, PetService, TycoonService?, TutorialService? }
--   DailyService.Resolve(player, reward, vip) -> { Kind = "Cash"|"Tokens"|"Gems"|"Berries"|"Pet"|"None", Amount, PetId }
--   DailyService.State(player) -> payload | nil (nil until the profile is loaded; Loading = true while provisional)
--   DailyService.Send(player)            fires DailyState(State(player)) to that client
--   DailyService.Claim(player) -> ok, { Cell, Streak, Grant, StepBack } | reason
--   DailyService.ClaimPlay(player, tier) -> ok, { Tier, Grant } | reason
--   DailyService.Tick()                  one play-time tick over every player
--   DailyService.Claimed                 Util.Signal Fire(player, "Day" | "Play", cellOrTier, grant)
--   DailyService._deps()                 test-only: the live deps table (a test swaps deps.StoreService for a double)
--   DailyService._tickAt()               test-only: os.clock() of the last loop tick
--   DailyService._holds(player)          test-only: this session's held seconds { Last, Sec } | nil (the hold)
--
-- Plain Lua 5.1-compatible syntax only. Nothing here yields between a check and its write.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local TycoonCatalog = require(Shared.TycoonCatalog)
local PetCatalog = require(Shared.PetCatalog)

local DailyService = {}
DailyService.Claimed = Util.Signal() -- Fire(player, "Day" | "Play", cellOrTier, grant)

local WEEK = 7
local REQUEST_GAP = 1 -- seconds between two DailyRequests of one action by one player
local TEXT = {
	Loading = "Your save is still loading",
	InMatch = "Finish your match first!",
	Checking = "Checking your VIP pass, one moment",
	Next = "Next gift in %dh %dm",
	RepairNext = "Streak repair in %dh %dm", -- the wait before a claim that only repairs (re-review 3)
	Repaired = "Streak repaired! Day %d of 7",
	Week = "WEEK DONE! %s is yours!",
	Day = "%s Day %d of 7",
	Play = "%s %d min played",
	Full = "Your Berry Basket is full!",
	Already = "You already claimed that!",
	NotYet = "Play %d more minutes!",
	DayOver = "That play day is over!",
	Unavailable = "Player unavailable",
	Locked = "Play %d more min to unlock today's gift!", -- a ready streak claim before UnlockSeconds of play (gui-redo 5.3)
	LockedRepair = "Play %d more min to repair your streak!", -- ...when that claim would only repair
}

local deps = {}
local active = {} -- [player] = { On = bool, LastRemote = os.clock() | nil }
local sample = {} -- [player] = the root's Vector3 at the last tick
local lastRequest = {} -- [player] = { [action] = os.clock() }
local stepBacks = {} -- [player] = the last claim's step-back, sent once
local clamps = {} -- [player] = { From = the stored future LastClaimAt, At = the now of its first sight } (Z8)
local sent = {} -- [player] = { Vip = the last payload's Vip, StaleAt = its StaleAt } (the re-sends)
local holds = {} -- [player] = { Last = the stamp, Sec = counting seconds while it was due and locked } (the hold, 5.3)
local started = false
local tickAt = -1

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function cfg()
	return type(Config.Daily) == "table" and Config.Daily or {}
end

local function playCfg()
	local c = cfg()
	return type(c.Play) == "table" and c.Play or {}
end

local function num(v, default)
	v = tonumber(v)
	if v == nil or v ~= v then
		return default
	end
	return v
end

local function whole(n)
	n = num(n, 0)
	if n < 0 then
		return 0
	end
	return math.floor(n + 1e-9)
end

local function isLivePlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function attr(player, key)
	local name = Config.Attr and Config.Attr[key]
	if type(name) ~= "string" then
		return nil
	end
	return player:GetAttribute(name)
end

local function fire(name, player, ...)
	local ok, remote = pcall(Remotes.Get, name)
	if ok and remote and isLivePlayer(player) then
		remote:FireClient(player, ...)
	end
end

local function notify(player, text, kind)
	fire("Notify", player, text, kind or "info", 4)
end

local function commas(n)
	local s = tostring(math.floor(num(n, 0)))
	while true do
		local k
		s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return s
end

local function dailyMult()
	local store = type(Config.Store) == "table" and Config.Store or {}
	local perks = type(store.Perks) == "table" and store.Perks or {}
	local vip = type(perks.Vip) == "table" and perks.Vip or {}
	return math.max(1, num(vip.DailyMult, 2))
end

-- the clean Daily record, or nil until loaded and while provisional
local function dailyOf(player)
	local DS = deps.DataService
	if not DS or type(DS.GetDaily) ~= "function" then
		return nil
	end
	local ok, d = pcall(DS.GetDaily, player)
	if ok and type(d) == "table" then
		return d
	end
	return nil
end

local function provisional(player)
	local DS = deps.DataService
	return DS ~= nil and type(DS.IsProvisional) == "function" and DS.IsProvisional(player) == true
end

local function income(player)
	local Ty = deps.TycoonService
	if not Ty or type(Ty.IncomePerSecond) ~= "function" then
		return 0
	end
	local ok, v = pcall(Ty.IncomePerSecond, player)
	v = ok and num(v, 0) or 0
	if v < 0 then
		return 0
	end
	return v
end

local function homeOf(player)
	local Ty = deps.TycoonService
	if not Ty or type(Ty.GetHome) ~= "function" then
		return nil
	end
	local ok, home = pcall(Ty.GetHome, player)
	return ok and home or nil
end

local function berriesOf(player)
	local DS = deps.DataService
	if not DS or type(DS.GetBerries) ~= "function" then
		return 0
	end
	local ok, n = pcall(DS.GetBerries, player)
	return ok and whole(n) or 0
end

-- copies of petId the player holds (0 without a readable profile)
local function petCount(player, petId)
	local DS = deps.DataService
	if not DS or type(DS.GetProfile) ~= "function" then
		return 0
	end
	local ok, profile = pcall(DS.GetProfile, player)
	if ok and type(profile) == "table" and type(profile.Pets) == "table" then
		return whole(profile.Pets[petId])
	end
	return 0
end

local function stackRoom(player, petId)
	return num(Config.Pets and Config.Pets.MaxPerStack, 99) - petCount(player, petId)
end

local function ownsVip(player)
	local SS = deps.StoreService
	if not SS or type(SS.Owns) ~= "function" then
		return false
	end
	local ok, owns = pcall(SS.Owns, player, "VIP")
	return ok and owns == true
end

local function vipState(player)
	local SS = deps.StoreService
	if not SS or type(SS.PassState) ~= "function" then
		return "Unavailable"
	end
	local ok, state = pcall(SS.PassState, player, "VIP")
	return ok and tostring(state) or "Unavailable"
end

local function activeOf(player)
	local a = active[player]
	if not a then
		a = { On = false, LastRemote = nil }
		active[player] = a
	end
	return a
end

local function limited(player, action)
	local record = lastRequest[player]
	if not record then
		record = {}
		lastRequest[player] = record
	end
	local now = os.clock()
	local last = record[action]
	if last and now - last < REQUEST_GAP then
		return true
	end
	record[action] = now
	return false
end

local function validTier(tier)
	local tiers = playCfg().Tiers
	local n = type(tiers) == "table" and #tiers or 0
	return type(tier) == "number" and tier == tier and tier >= 1 and tier <= n and tier == math.floor(tier)
end

-- the refusal of a claim that is not ready yet: "Next gift in 4h 12m", or "Streak repair in 4h 12m" when that claim
-- will only repair (`repair`), so the wait never names a gift the claim will not pay
local function nextText(seconds, repair)
	seconds = math.max(0, whole(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h == 0 and m == 0 and seconds > 0 then
		m = 1
	end
	return string.format(repair and TEXT.RepairNext or TEXT.Next, h, m)
end

-- the grant record of a resolved reward ({ Kind, Tier, Cash | Tokens | Gems | Berries | Pets }), nil when nothing is paid
local function grantOf(r, kind, tier)
	if type(r) ~= "table" then
		return nil
	end
	local g = { Kind = kind, Tier = tier }
	if r.Kind == "Pet" and type(r.PetId) == "string" then
		g.Pets = { [r.PetId] = 1 }
	elseif (r.Kind == "Cash" or r.Kind == "Tokens" or r.Kind == "Gems" or r.Kind == "Berries") and whole(r.Amount) >= 1 then
		g[r.Kind] = whole(r.Amount)
	else
		return nil
	end
	return g
end

-- pays a resolved reward (after its claim committed); answers the toast's amount text
local function pay(player, r)
	local DS = deps.DataService
	local amount = whole(r.Amount)
	if r.Kind == "Cash" then
		if amount >= 1 then
			DS.AddCash(player, amount)
		end
		return "+$" .. commas(amount) .. " Cash!"
	elseif r.Kind == "Tokens" then
		if amount >= 1 then
			DS.AddTokens(player, amount)
		end
		return "+" .. commas(amount) .. " Tokens!"
	elseif r.Kind == "Gems" then
		if amount >= 1 then
			DS.AddGems(player, amount)
		end
		return "+" .. commas(amount) .. " Gems!"
	elseif r.Kind == "Berries" then
		if amount >= 1 then
			DS.AddBerries(player, amount)
			return "+" .. commas(amount) .. " Berries!"
		end
		return TEXT.Full
	elseif r.Kind == "Pet" then
		local PS = deps.PetService
		local ok, result = false, "no PetService"
		if PS and type(PS.GrantPet) == "function" then
			ok, result = PS.GrantPet(player, r.PetId, { Count = 1 })
		end
		if not ok then
			warn("[DailyService] GrantPet " .. tostring(r.PetId) .. " failed after the claim: " .. tostring(result))
		end
		local def = type(PetCatalog.Get) == "function" and PetCatalog.Get(r.PetId) or nil
		return string.format(TEXT.Week, def and def.Name or tostring(r.PetId))
	end
	return nil
end

local function readyCount(d, tiers)
	local n = 0
	for i, t in ipairs(tiers) do
		if d.PlaySec >= num(t.Min, 0) * 60 and d.PlayClaimed[i] ~= true then
			n = n + 1
		end
	end
	return n
end

-- true when the record's play-day has run its DaySeconds (its tiers are lost; the next tick starts a new day)
local function dayOver(d, now)
	local start = num(d.PlayStart, 0)
	return start > 0 and now >= start + num(playCfg().DaySeconds, 72000)
end

-- the counted play seconds a streak claim needs on the current play-day (5.3); 0 = the rule is off (no lock, no hold)
local function unlockNeed()
	return whole(cfg().UnlockSeconds)
end

-- the counted play seconds of the LIVE play-day: PlaySec when it started and is not over, else 0
local function livePlaySec(d, now)
	if num(d.PlayStart, 0) > 0 and not dayOver(d, now) then
		return whole(d.PlaySec)
	end
	return 0
end

-- The hold (5.3): the moment a claim's step-back gap is measured at -> keepAt, source ("PlayStart" | "Held" | nil), the held
-- seconds. from = min(the live PlayStart, now - this session's held seconds for this stamp); keepAt = min(now, max(from,
-- last + ReadySeconds)); now with no source when nothing holds it, the rule is off or there is no claim yet.
local function keepOf(player, d, last, now)
	if unlockNeed() <= 0 or last <= 0 then
		return now, nil, 0
	end
	local from, source = nil, nil
	if num(d.PlayStart, 0) > 0 and not dayOver(d, now) then
		from, source = num(d.PlayStart, 0), "PlayStart"
	end
	local h = holds[player]
	local sec = (h and h.Last == last) and num(h.Sec, 0) or 0
	if sec > 0 and (from == nil or now - sec < from) then
		from, source = now - sec, "Held"
	end
	if from == nil then
		return now, nil, sec
	end
	local at = math.max(from, last + num(cfg().ReadySeconds, 72000))
	if at >= now then
		return now, nil, sec
	end
	return at, source, sec
end

-- today's StaleAt rule at the moment t for the stamp `last`: the keep deadline passing (KeepUntil + 1), then each further
-- missed day
local function staleRule(t, last, keep)
	if t - last > keep then
		return last + keep + 86400 * (math.floor((t - last - keep) / 86400) + 1)
	end
	return last + keep + 1
end

-- this server's game.JobId (the clock a Z8 first sight was read on; "" in Studio or when unreadable)
local function jobId()
	local ok, id = pcall(function()
		return game.JobId
	end)
	return (ok and type(id) == "string") and id or ""
end

-- Z8: this session's LastClaimAt. A stored stamp more than FutureClockSlack ahead of now counts as the now of its
-- first sight ON THIS SERVER'S CLOCK: the record's ClampAt when this server noted one for this stamp (ClampFrom ==
-- LastClaimAt and ClampJob == game.JobId: a rejoin here; never later than now), else this call's now, which is then
-- noted in the record in place of any other (ClampFrom / ClampAt / ClampJob, no grant; LastClaimAt is never touched).
-- A sight another server noted is never reused (re-review 3): it is a reading of that server's clock, and a slower
-- clock's sight would start the countdown early here. The session keeps that value until the stored stamp changes (a
-- claim, a rebase), also after the stamp falls behind now. A stamp this server sees as past is used as it is (see the
-- header). Answers the stamp and true when this call started the session's clamp.
local function lastClaimOf(player, d, now)
	local stored = d.LastClaimAt
	local c = clamps[player]
	if c and c.From == stored then
		return c.At, false
	end
	clamps[player] = nil
	if stored <= now + num(cfg().FutureClockSlack, 300) then
		return stored, false
	end
	local at = now
	local seen = num(d.ClampAt, 0)
	local job = jobId()
	if num(d.ClampFrom, 0) == stored and seen > 0 and d.ClampJob == job then
		at = math.min(seen, now)
	else
		local DS = deps.DataService
		if DS and type(DS.MutateDaily) == "function" then
			pcall(DS.MutateDaily, player, function(live)
				if num(live.LastClaimAt, 0) ~= stored then
					return false
				end
				live.ClampFrom = stored
				live.ClampAt = now
				live.ClampJob = job
				return true
			end)
		end
	end
	clamps[player] = { From = stored, At = at }
	return at, true
end

local function defaultDaily()
	return { Streak = 0, Paid = 0, LastClaimAt = 0, Weeks = 0, Pet = false, PlayStart = 0, PlaySec = 0, PlayClaimed = {}, ClampFrom = 0, ClampAt = 0, ClampJob = "" }
end

----------------------------------------------------------------------
-- public: Resolve / State / Send
----------------------------------------------------------------------
-- A reward entry of Config.Daily (a cell or a play tier) -> what it pays THIS player now: { Kind, Amount, PetId }.
-- Cash = max(Min, floor(income x Minutes x 60)) and Tokens take the VIP multiplier when `vip`; Gems never; Berries
-- fill the Basket; a Pet with no stack room resolves the entry's Else.
function DailyService.Resolve(player, reward, vip)
	reward = type(reward) == "table" and reward or {}
	local mult = vip and dailyMult() or 1
	if type(reward.Pet) == "string" then
		if stackRoom(player, reward.Pet) > 0 then
			return { Kind = "Pet", Amount = 1, PetId = reward.Pet }
		end
		if type(reward.Else) == "table" then
			return DailyService.Resolve(player, reward.Else, vip)
		end
		return { Kind = "None", Amount = 0 }
	end
	if reward.Cash ~= nil then
		local amount
		if type(reward.Cash) == "table" then
			local minutes = math.max(0, num(reward.Cash.Minutes, 0))
			local floor = math.max(0, num(reward.Cash.Min, 0))
			amount = math.max(floor, math.floor(income(player) * minutes * 60 + 1e-9))
		else
			amount = math.max(0, num(reward.Cash, 0))
		end
		return { Kind = "Cash", Amount = whole(amount * mult) }
	end
	if reward.Tokens ~= nil then
		return { Kind = "Tokens", Amount = whole(math.max(0, num(reward.Tokens, 0)) * mult) }
	end
	if reward.Gems ~= nil then
		return { Kind = "Gems", Amount = whole(reward.Gems) }
	end
	if reward.Berries ~= nil then
		local amount
		if reward.Berries == "Basket" then
			amount = TycoonCatalog.BasketCap(homeOf(player), income(player)) - berriesOf(player)
		else
			amount = num(reward.Berries, 0)
		end
		return { Kind = "Berries", Amount = whole(math.max(0, amount)) }
	end
	return { Kind = "None", Amount = 0 }
end

-- The DailyState payload (DailyController's shape), or nil until the profile is loaded. While provisional it carries
-- Loading = true (the client hides CLAIM and the pip) with ReadyAt = now + ReadySeconds.
function DailyService.State(player)
	if not isLivePlayer(player) or not deps.DataService then
		return nil
	end
	local C = cfg()
	local P = playCfg()
	local now = os.time()
	local d = dailyOf(player)
	local loading = false
	if not d then
		if not provisional(player) then
			return nil
		end
		loading = true
		d = defaultDaily()
	end
	local last = loading and 0 or lastClaimOf(player, d, now) -- Z8: this session's stamp (LastClaimAt never written here)
	local ready = num(C.ReadySeconds, 72000)
	local keep = num(C.KeepSeconds, 172800)
	local vip = ownsVip(player)
	-- the hold (5.3): the gap is measured at keepAt, as Claim measures it, so the window never promises what the claim
	-- will not do
	local keepAt, source, held = now, nil, 0
	if not loading then
		keepAt, source, held = keepOf(player, d, last, now)
	end
	-- the streak the claim will build on: a step-back due (Claim's rule; never for a VIP) lowers it first. The claim
	-- re-earns a paid day whenever that streak + 1 <= Paid (Claim's pays = streak > Paid): a repair, so Today moves to
	-- the repair cell and no gift is promised. Every claim: the step-back one, the kept ones that climb back to Paid,
	-- a VIP's while Paid > Streak (re-review 1 and 2)
	local streak = d.Streak
	local missed = not loading and not vip and last > 0 and keepAt - last > keep
	if missed then
		streak = math.max(0, d.Streak - (1 + math.floor((keepAt - last - keep) / 86400)))
	end
	local repair = (not loading) and streak + 1 <= d.Paid
	-- StaleAt: when this view changes with no claim: the keep deadline passing (Claim's strict '>'), then each further
	-- missed day while the streak can still fall; 0 = never (loading, a VIP, no claim yet, a streak already at 0). Held by
	-- the live PlayStart the view can only change when that play-day ends; held by the session's seconds, today's rule at
	-- keepAt shifted by them (the moment now - Sec passes the next boundary if the player stood still from now on)
	local staleAt = 0
	if not loading and not vip and last > 0 and streak > 0 then
		if source == "PlayStart" then
			staleAt = d.PlayStart + num(P.DaySeconds, 72000)
		elseif source == "Held" then
			staleAt = staleRule(keepAt, last, keep) + held
		else
			staleAt = staleRule(now, last, keep)
		end
	end
	local cell = (streak % WEEK) + 1
	local days = {}
	for i, reward in ipairs(type(C.Days) == "table" and C.Days or {}) do
		local r = DailyService.Resolve(player, reward, vip)
		local claimed = streak > 0 and i <= ((streak - 1) % WEEK) + 1 and d.Paid >= math.floor((streak - 1) / WEEK) * WEEK + i
		local today = (i == cell) and not claimed
		days[i] = { Kind = r.Kind, Amount = r.Amount, PetId = r.PetId, Claimed = claimed, Today = today, Repair = (repair and today) or nil }
	end
	local tiers = {}
	local over = dayOver(d, now)
	for i, t in ipairs(type(P.Tiers) == "table" and P.Tiers or {}) do
		local r = DailyService.Resolve(player, t, false)
		local claimed = d.PlayClaimed[i] == true
		tiers[i] = { Min = num(t.Min, 0), Kind = r.Kind, Amount = r.Amount, PetId = r.PetId, Claimed = claimed, Ready = (not loading) and (not over) and d.PlaySec >= num(t.Min, 0) * 60 and not claimed }
	end
	local readyAt = now
	if loading then
		readyAt = now + ready
	elseif last > 0 then
		readyAt = last + ready
	end
	local dayEnds = now + num(P.DaySeconds, 72000)
	if d.PlayStart > 0 then
		dayEnds = d.PlayStart + num(P.DaySeconds, 72000)
	end
	local a = active[player]
	local stepBack = stepBacks[player] or 0
	stepBacks[player] = nil
	local need = unlockNeed()
	return {
		Loading = loading or nil,
		Streak = d.Streak,
		Paid = d.Paid,
		Weeks = d.Weeks,
		Cell = cell,
		Repair = repair, -- the next claim repairs the streak and pays nothing (Today = the repair cell)
		StaleAt = staleAt, -- this view (Repair, Cell, Today) stops being true at this server time; 0 = never
		ReadyAt = readyAt,
		KeepUntil = last > 0 and last + keep or 0,
		ServerNow = now,
		Vip = vip,
		StepBack = stepBack,
		-- the 10-minute unlock (5.3): Left 0 = a ready claim may go; Need 0 = the rule is off
		Unlock = { Need = need, Left = loading and need or math.max(0, need - livePlaySec(d, now)) },
		Days = days,
		Play = {
			Seconds = d.PlaySec,
			DayEnds = dayEnds,
			Active = a ~= nil and a.On == true,
			Tiers = tiers,
		},
	}
end

function DailyService.Send(player)
	local state = DailyService.State(player)
	if state then
		sent[player] = { Vip = state.Vip == true, StaleAt = num(state.StaleAt, 0) }
		fire("DailyState", player, state)
	end
	return state
end

----------------------------------------------------------------------
-- public: Claim / ClaimPlay
----------------------------------------------------------------------
function DailyService.Claim(player)
	if not isLivePlayer(player) then
		return false, TEXT.Unavailable
	end
	local DS = deps.DataService
	local d = dailyOf(player)
	if not DS or not d then
		return false, TEXT.Loading
	end
	local C = cfg()
	local now = os.time()
	local ready = num(C.ReadySeconds, 72000)
	local keep = num(C.KeepSeconds, 172800)
	-- Z8: a wrong-clock stamp counts as the session's first sight of it (never written); a claim that starts the clamp
	-- is refused with "Next gift in 20h 0m" and sends the payload that counts down from now
	local last, clamped = lastClaimOf(player, d, now)
	if last > 0 and now - last < ready then
		if clamped then
			DailyService.Send(player)
		end
		-- not ready means no step-back is due (gap < ReadySeconds < KeepSeconds): the claim builds on d.Streak
		return false, nextText(ready - (now - last), num(d.Streak, 0) + 1 <= num(d.Paid, 0))
	end
	-- the hold (5.3): the gap is measured at keepAt (never later than now), as State shows it
	local gap = keepOf(player, d, last, now) - last
	local stepBack = 0
	if last > 0 and gap > keep then
		stepBack = 1 + math.floor((gap - keep) / 86400)
	end
	local vip = ownsVip(player)
	-- locked (5.3): a ready claim waits for UnlockSeconds of the live play-day; refused, nothing written
	local left = unlockNeed() - livePlaySec(d, now)
	if left > 0 then
		local repair = math.max(0, num(d.Streak, 0) - (vip and 0 or stepBack)) + 1 <= num(d.Paid, 0)
		return false, string.format(repair and TEXT.LockedRepair or TEXT.Locked, math.ceil(left / 60))
	end
	if stepBack > 0 and not vip and vipState(player) == "Checking" then
		return false, TEXT.Checking
	end
	if vip then
		stepBack = 0
	end
	local streak = math.max(0, d.Streak - stepBack) + 1
	local cell = ((streak - 1) % WEEK) + 1
	local pays = streak > d.Paid
	local reward = type(C.Days) == "table" and C.Days[cell] or nil
	local r = (pays and reward) and DailyService.Resolve(player, reward, vip) or nil
	local grant = r and grantOf(r, "Day") or nil
	local ok = DS.MutateDaily(player, function(live)
		live.Streak = streak
		live.LastClaimAt = now
		live.ClampFrom = 0 -- the Z8 first sight belonged to the stamp this claim replaces
		live.ClampAt = 0
		live.ClampJob = ""
		live.Paid = math.max(num(live.Paid, 0), streak)
		live.Weeks = math.max(num(live.Weeks, 0), math.floor(streak / WEEK))
		if r and r.Kind == "Pet" then
			live.Pet = true
		end
		return true
	end, grant, now) -- the grant's At is this claim's now: the merge pairs them by that one stamp
	if not ok then
		return false, TEXT.Loading
	end
	-- nothing yields between the commit and the pay
	local text
	if r then
		local head = pay(player, r)
		if r.Kind == "Pet" then
			text = head
		elseif head then
			text = string.format(TEXT.Day, head, cell)
		end
	else
		text = string.format(TEXT.Repaired, cell)
	end
	if stepBack > 0 then
		stepBacks[player] = stepBack
	end
	holds[player] = nil -- the held seconds belonged to the stamp this claim replaces
	if text then
		notify(player, text, "good")
	end
	DailyService.Claimed:Fire(player, "Day", cell, grant)
	DailyService.Send(player)
	return true, { Cell = cell, Streak = streak, Grant = grant, StepBack = stepBack }
end

function DailyService.ClaimPlay(player, tier)
	if not isLivePlayer(player) then
		return false, TEXT.Unavailable
	end
	if not validTier(tier) then
		return false, "Unknown tier"
	end
	local DS = deps.DataService
	local d = dailyOf(player)
	if not DS or not d then
		return false, TEXT.Loading
	end
	local t = playCfg().Tiers[tier]
	local need = num(t.Min, 0) * 60
	if dayOver(d, os.time()) then
		return false, TEXT.DayOver
	end
	if d.PlayClaimed[tier] == true then
		return false, TEXT.Already
	end
	if d.PlaySec < need then
		return false, string.format(TEXT.NotYet, math.ceil((need - d.PlaySec) / 60))
	end
	local r = DailyService.Resolve(player, t, false)
	local grant = grantOf(r, "Play", tier)
	local ok = DS.MutateDaily(player, function(live)
		if type(live.PlayClaimed) ~= "table" then
			live.PlayClaimed = {}
		end
		live.PlayClaimed[tier] = true
		return true
	end, grant)
	if not ok then
		return false, TEXT.Loading
	end
	local head = pay(player, r)
	if head then
		notify(player, string.format(TEXT.Play, head, num(t.Min, 0)), "good")
	end
	DailyService.Claimed:Fire(player, "Play", tier, grant)
	DailyService.Send(player)
	return true, { Tier = tier, Grant = grant }
end

----------------------------------------------------------------------
-- public: Tick
----------------------------------------------------------------------
local function tickPlayer(player, P, now, clock)
	local DS = deps.DataService
	local d = dailyOf(player) -- nil until loaded and while provisional: no tick
	if not d then
		return
	end
	local root = Util.GetRoot(player)
	if not root then
		return
	end
	local hum = Util.GetHumanoid(player)
	if hum and num(hum.Health, 0) <= 0 then
		return
	end
	local pos = root.Position
	local last = sample[player]
	local moved = last ~= nil and (pos - last).Magnitude > num(P.MoveStuds, 2)
	sample[player] = pos
	local a = activeOf(player)
	local remoteRecent = a.LastRemote ~= nil and clock - a.LastRemote < num(P.ActiveWindow, 180)
	local on = moved or remoteRecent
	local send = false
	if on ~= a.On then
		a.On = on
		send = true
	end
	-- a finished play-day resets on this tick even when it does not count (Q17: its tiers are never banked)
	if on or dayOver(d, now) then
		local tiers = type(P.Tiers) == "table" and P.Tiers or {}
		local readyBefore = readyCount(d, tiers)
		local reset = false
		local daySeconds = num(P.DaySeconds, 72000)
		local need = unlockNeed()
		-- the stamp the hold counts for: this session's (Z8) stamp, read BEFORE the step (lastClaimOf may write the first
		-- sight itself)
		local stamp = (on and need > 0) and lastClaimOf(player, d, now) or 0
		local counted = nil -- the play-day's seconds after any reset, before this tick's add
		local ok = DS.MutateDaily(player, function(live)
			local start = num(live.PlayStart, 0)
			if (on and start == 0) or (start > 0 and now >= start + daySeconds) then
				live.PlayStart = now
				live.PlaySec = 0
				live.PlayClaimed = {}
				reset = true
			end
			counted = num(live.PlaySec, 0)
			if on then
				live.PlaySec = math.min(num(P.MaxDaySeconds, 36000), num(live.PlaySec, 0) + num(P.TickSeconds, 10))
			end
			return true
		end)
		if ok then
			local after = dailyOf(player)
			if reset or (after and readyCount(after, tiers) > readyBefore) then
				send = true
			end
			if on and need > 0 and counted ~= nil and counted < need then
				-- the hold (5.3): a counting tick while the streak gift is due and still locked
				if stamp > 0 and now >= stamp + num(cfg().ReadySeconds, 72000) then
					local h = holds[player]
					if not h or h.Last ~= stamp then
						h = { Last = stamp, Sec = 0 }
						holds[player] = h
					end
					h.Sec = h.Sec + num(P.TickSeconds, 10)
				end
				-- the unlock crossing (before < Need <= after): CLAIM shows on time
				if after and num(after.PlaySec, 0) >= need then
					send = true
				end
			end
		end
	end
	if send then
		DailyService.Send(player)
	end
end

function DailyService.Tick()
	if not deps.DataService then
		return
	end
	local P = playCfg()
	local now = os.time()
	local clock = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, err = pcall(tickPlayer, player, P, now, clock)
		if not ok then
			warn("[DailyService] tick failed for " .. tostring(player.Name) .. ": " .. tostring(err))
		end
		-- the last payload's view went stale (the keep deadline or another missed day passed): send the fresh one
		local s = sent[player]
		if s and s.StaleAt > 0 and now >= s.StaleAt then
			local okS, errS = pcall(DailyService.Send, player)
			if not okS then
				warn("[DailyService] re-send failed for " .. tostring(player.Name) .. ": " .. tostring(errS))
			end
		end
	end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
local function onRequest(player, action, tier, extra)
	if not isLivePlayer(player) or extra ~= nil then
		return
	end
	if action == "Claim" then
		if tier ~= nil then
			return -- junk
		end
	elseif action == "ClaimPlay" then
		if not validTier(tier) then
			return
		end
	else
		return
	end
	if limited(player, action) then
		return
	end
	if attr(player, "InMatch") == true then
		notify(player, TEXT.InMatch, "bad")
		return
	end
	local ok, success, info
	if action == "Claim" then
		ok, success, info = pcall(DailyService.Claim, player)
	else
		ok, success, info = pcall(DailyService.ClaimPlay, player, tier)
	end
	if not ok then
		warn("[DailyService] " .. action .. " errored: " .. tostring(success))
		notify(player, "Something went wrong, try again", "bad")
		return
	end
	if success == false and type(info) == "string" and isLivePlayer(player) then
		notify(player, info, "info")
	end
end

function DailyService.Init(given)
	if type(given) == "table" then
		for k, v in pairs(given) do
			deps[k] = v
		end
	end
	if started then
		return
	end
	started = true
	local DS = deps.DataService
	if DS then
		if DS.ProfileLoaded then
			DS.ProfileLoaded:Connect(function(player)
				DailyService.Send(player)
			end)
		end
		if DS.ProfileRebased then
			DS.ProfileRebased:Connect(function(player)
				DailyService.Send(player)
			end)
		end
	else
		warn("[DailyService] Init without DataService: nothing can be claimed")
	end
	-- a VIP answer after the payload was built (a pass still Checking at the join): re-send when Vip changed
	local SS = deps.StoreService
	if type(SS) == "table" and type(SS.Changed) == "table" and type(SS.Changed.Connect) == "function" then
		SS.Changed:Connect(function(player)
			local s = sent[player]
			if s and isLivePlayer(player) and ownsVip(player) ~= s.Vip then
				local okS, errS = pcall(DailyService.Send, player)
				if not okS then
					warn("[DailyService] VIP re-send failed: " .. tostring(errS))
				end
			end
		end)
	end
	local okRemote, remote = pcall(Remotes.Get, "DailyRequest")
	if okRemote and remote then
		remote.OnServerEvent:Connect(onRequest)
	else
		warn("[DailyService] DailyRequest remote is unavailable: " .. tostring(remote))
	end
	for _, name in ipairs(type(playCfg().ActiveRemotes) == "table" and playCfg().ActiveRemotes or {}) do
		local okA, r = pcall(Remotes.Get, name)
		if okA and r then
			r.OnServerEvent:Connect(function(player)
				if isLivePlayer(player) then
					activeOf(player).LastRemote = os.clock()
				end
			end)
		else
			warn("[DailyService] activity remote " .. tostring(name) .. " is unavailable")
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		sample[player] = nil
		lastRequest[player] = nil
		stepBacks[player] = nil
		clamps[player] = nil
		sent[player] = nil
		holds[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(num(playCfg().TickSeconds, 10))
			tickAt = os.clock()
			local ok, err = pcall(DailyService.Tick)
			if not ok then
				warn("[DailyService] Tick errored: " .. tostring(err))
			end
		end
	end)
end

function DailyService._deps()
	return deps
end

function DailyService._tickAt()
	return tickAt
end

function DailyService._holds(player)
	return holds[player]
end

return DailyService
