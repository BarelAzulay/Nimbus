-- smoke_redo_daily.lua: the daily 10-minute unlock and the hold (docs/superpowers/specs/2026-11-06-window-redo-design.md 5.3
-- "The 10-minute rule", "The hold", 6 (Daily), 9 (daily_unlock*); plan docs/superpowers/plans/2026-11-06-window-redo.md
-- Task 4). A streak claim (the paid one, the Week Wisp, the first ever, a VIP's, the repair) needs Config.Daily.UnlockSeconds
-- (600) counted play seconds of the current play-day (Daily.PlaySec on the live PlayStart: the play-time clock, its AFK rule,
-- its 20 h reset). The step-back gap is measured at keepAt (the hold): the live PlayStart, or this session's held seconds
-- (counting ticks while the gift was due and still locked), so the wait never costs a streak day. UnlockSeconds = 0 turns
-- both off (today's rule). Server world only, booted:
--   daily_unlock       ready but locked: refused with "Play 10 more min to unlock today's gift!", nothing written; the
--                      payload's Unlock { Need, Left }; still ticks add nothing, moves and an active remote count; the tick
--                      that reaches 600 s sends one payload with Left 0 and the claim pays; the repair ("...to repair your
--                      streak!"), a VIP and the first claim ever wait too; a play-day reset restarts the count;
--                      UnlockSeconds = 0: no lock, Need 0 / Left 0, and a 48 h + 1 s gap steps back (no hold)
--   daily_unlock_hold  A join at 47 h 55 m, 10 min of play, claim at 48 h 05 m -> kept; B join at 49 h -> one step back;
--                      C a play-day started at 30 h, back at 49 h 05 m -> kept (StaleAt = PlayStart + DaySeconds); D the
--                      play-day resets 7 min into the unlock (a 1 min visit at 28 h 05 m, back at 47 h 58 m) -> the claim
--                      after the new day's 10 min is kept (the held seconds, about 17 min; StaleAt = rule(keepAt) + Sec
--                      after the reset; "Day resets" before it: DayEnds - ServerNow < Left); E as D, then 3 min standing
--                      still -> one step back; the last payload before each claim agrees with the claim; a claim drops
--                      the held seconds, a changed stamp starts them over; UnlockSeconds = 600 with a play-day an hour old
--                      keeps a 48 h + 1 s gap (the contrast of daily_unlock's last case)
--   daily_unlock_hop   6 min of play on one server session, the player leaves (saved), 4 min on the next session (a hop:
--                      no held seconds there, only the stored play-day) -> unlocked; the claim past 48 h is kept by the
--                      stored PlayStart and pays once
-- White-box: the booted helpers of smoke_daily.lua. The mock's os.time() is floor(EPOCH + clock); alignTicks lands 5 s after a
-- loop tick, so every tick() (10 s) holds exactly one tick. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local advance, config, mod = K.advance, K.config, K.mod
local ALLOWED_WARNINGS = { "[DataService]", "[TycoonService]", "[PetCareService]", "[SpotService]" }
local HOUR = 3600
local LOCKED = "Play 10 more min to unlock today's gift!"
local LOCKED_REPAIR = "Play 10 more min to repair your streak!"

----------------------------------------------------------------------------------------------------
-- helpers (smoke_daily.lua's shapes)
----------------------------------------------------------------------------------------------------
local function DS()
	return mod("DataService")
end

local function DSV()
	return mod("DailyService")
end

local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 986300 + userSeq
end

local function join(prefix, uid)
	local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
	advance(1.2)
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.8)
end

local function loaded(p)
	return K.waitFor(function()
		return DS().GetDaily(p) ~= nil
	end, 10)
end

local function storeKey(uid)
	return config().Tokens.DataStoreName .. "/u_" .. uid
end

local function stored(uid)
	return Mock.DataStore.Data[storeKey(uid)]
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function request(p, ...)
	Mock.FromClient(remote("DailyRequest"), p, ...)
end

-- fires DailyRequest "Claim" FIRST (at the current os.time(), returned) and lets the 1 req/s window pass AFTER. No play time
-- is added here: these scenarios test the lock itself.
local function claim(p)
	local t = os.time()
	request(p, "Claim")
	advance(1.05)
	return t
end

local function setDaily(p, fields)
	return DS().MutateDaily(p, function(d)
		for k, v in pairs(fields) do
			d[k] = v
		end
		return true
	end)
end

local function lastState(p)
	local e = K.lastRemote("DailyState", p.UserId)
	return e and e.args[1] or nil
end

local function states(p, mark)
	return K.remotesFor("DailyState", p.UserId, mark or 0)
end

local function toastCount(p, needle, mark)
	local n = 0
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		if string.find(tostring(e.args[1]), needle, 1, true) then
			n = n + 1
		end
	end
	return n
end

local function toastTexts(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	return table.concat(out, " | ")
end

-- a 3-stud move each call, back and forth (the player never walks off the lobby)
local flip = 1
local function moveRoot(p, studs)
	local r = K.root(p)
	if r then
		flip = -flip
		Mock.Teleport(p, r.Position + Vector3.new(studs * flip, 0, 0))
	end
end

-- lands right after a loop tick, then half a tick later: every advance(10) from here holds exactly one tick
local function alignTicks()
	local D = DSV()
	local mark = D._tickAt and D._tickAt() or -1
	K.waitFor(function()
		return (D._tickAt and D._tickAt() or -1) > mark
	end, 15)
	advance(5)
end

local function tick(n)
	advance(10 * (n or 1))
end

-- n counting ticks (a 3-stud move before each)
local function play(p, n)
	for _ = 1, n do
		moveRoot(p, 3)
		tick()
	end
end

local function describeDaily(d)
	if type(d) ~= "table" then
		return tostring(d)
	end
	return "Streak " .. tostring(d.Streak) .. " Paid " .. tostring(d.Paid) .. " LastClaimAt " .. tostring(d.LastClaimAt) .. " PlayStart " .. tostring(d.PlayStart) .. " PlaySec " .. tostring(d.PlaySec)
end

local function unlockText(st)
	if type(st) ~= "table" then
		return "no payload"
	end
	local u = st.Unlock
	return "Unlock " .. (type(u) == "table" and (tostring(u.Need) .. "/" .. tostring(u.Left)) or tostring(u)) .. " Cell " .. tostring(st.Cell) .. " Repair " .. tostring(st.Repair) .. " StaleAt " .. tostring(st.StaleAt) .. " ServerNow " .. tostring(st.ServerNow)
end

local function leftOf(st)
	return type(st) == "table" and type(st.Unlock) == "table" and st.Unlock.Left or nil
end

local function holdsOf(p)
	local D = DSV()
	if type(D._holds) ~= "function" then
		return nil
	end
	return D._holds(p)
end

local function holdText(p)
	local h = holdsOf(p)
	return h and ("hold Last " .. tostring(h.Last) .. " Sec " .. tostring(h.Sec)) or "no hold"
end

local function finish(name, ...)
	for _, q in ipairs({ ... }) do
		leave(q)
	end
	K.flushErrors(name)
	K.flushWarnings(name, ALLOWED_WARNINGS)
end

-- today's StaleAt rule of DailyService evaluated at t for the stamp `last` (spec 5.3 "StaleAt": the keep deadline passing,
-- KeepUntil + 1, then each further missed day)
local function rule(t, last)
	local keep = config().Daily.KeepSeconds
	if t - last > keep then
		return last + keep + 86400 * (math.floor((t - last - keep) / 86400) + 1)
	end
	return last + keep + 1
end

----------------------------------------------------------------------------------------------------
-- daily_unlock
----------------------------------------------------------------------------------------------------
S.daily_unlock = guarded("daily_unlock", function()
	if not K.needBoot() then
		return
	end
	local C = config().Daily
	local D = DSV()
	T.check(C.UnlockSeconds == 600, "daily unlock: Config.Daily.UnlockSeconds = 600", tostring(C.UnlockSeconds))
	local p = join("Unlock", newUserId())
	loaded(p)
	alignTicks()
	-- a ready gift (21 h after day 3) on a play-day that just started: locked, refused, nothing written
	local now = os.time()
	setDaily(p, { Streak = 3, Paid = 3, Weeks = 0, LastClaimAt = now - 21 * HOUR, PlayStart = now, PlaySec = 0, PlayClaimed = { true } })
	local d0 = DS().GetDaily(p)
	local before = { Streak = d0.Streak, Paid = d0.Paid, LastClaimAt = d0.LastClaimAt, PlayStart = d0.PlayStart, PlaySec = d0.PlaySec }
	local cash0, tokens0, gems0 = DS().GetCash(p), DS().GetTokens(p), DS().GetGems(p)
	D.Send(p)
	local st = lastState(p)
	T.check(st ~= nil and type(st.Unlock) == "table" and st.Unlock.Need == 600 and st.Unlock.Left == 600,
		"daily unlock: the payload carries Unlock { Need = 600, Left = 600 } on a fresh play-day", unlockText(st))
	local mark = K.logSize()
	claim(p)
	local d = DS().GetDaily(p)
	T.check(toastCount(p, LOCKED, mark) == 1, "daily unlock: a ready claim with 0 s played is refused: '" .. LOCKED .. "'", toastTexts(p, mark))
	T.check(d.Streak == before.Streak and d.Paid == before.Paid and d.LastClaimAt == before.LastClaimAt and d.PlayStart == before.PlayStart and d.PlaySec == before.PlaySec
		and DS().GetCash(p) == cash0 and DS().GetTokens(p) == tokens0 and DS().GetGems(p) == gems0,
		"daily unlock: ...nothing written (Streak, Paid, LastClaimAt, the play clock) and nothing paid", describeDaily(d))
	-- the counter is the play clock: still ticks add nothing; moves and an active remote count
	tick(6)
	st = D.State(p)
	T.check(leftOf(st) == 600, "daily unlock: 6 still ticks leave Left at 600", unlockText(st))
	play(p, 30)
	st = D.State(p)
	T.check(leftOf(st) == 300 and DS().GetDaily(p).PlaySec == 300, "daily unlock: 30 ticks with a 3-stud move each -> Left 300", unlockText(st) .. " " .. describeDaily(DS().GetDaily(p)))
	Mock.FromClient(remote("PetCare"), p, "Nope")
	tick(18)
	st = D.State(p)
	T.check(leftOf(st) == 120, "daily unlock: a PetCare remote, then 18 still ticks inside 180 s count (Left 120)", unlockText(st))
	-- the crossing: the tick that reaches 600 s sends the payload with Left 0 (tier 1 is already claimed here, so no tier
	-- crossing sends it); 11 moving ticks first (Left 10), then the crossing tick on its own
	play(p, 11)
	st = D.State(p)
	T.check(leftOf(st) == 10, "daily unlock: (setup) 11 more ticks -> Left 10", unlockText(st))
	mark = K.logSize()
	play(p, 1)
	local sent = states(p, mark)
	local zero = 0
	for _, e in ipairs(sent) do
		if leftOf(e.args[1]) == 0 then
			zero = zero + 1
		end
	end
	T.check(#sent == 1 and zero == 1, "daily unlock: the tick that reaches 600 s sends exactly one payload, with Unlock.Left == 0", "payloads " .. #sent .. ", Left 0: " .. zero)
	mark = K.logSize()
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 4 and d.Paid == 4 and DS().GetCash(p) == cash0 + 1000 and toastCount(p, "+$1,000 Cash! Day 4 of 7", mark) == 1,
		"daily unlock: unlocked, the claim pays day 4 ($1,000 at income 0)", describeDaily(d) .. " toasts: " .. toastTexts(p, mark))
	-- the repair claim waits too (Paid 5 > Streak 3, a missed day: the claim would only repair)
	now = os.time()
	setDaily(p, { Streak = 3, Paid = 5, LastClaimAt = now - 50 * HOUR, PlayStart = now, PlaySec = 0, PlayClaimed = { true } })
	mark = K.logSize()
	claim(p)
	d = DS().GetDaily(p)
	T.check(toastCount(p, LOCKED_REPAIR, mark) == 1 and d.Streak == 3 and d.Paid == 5 and d.LastClaimAt == now - 50 * HOUR,
		"daily unlock: a repair claim while locked is refused: '" .. LOCKED_REPAIR .. "', nothing written", describeDaily(d) .. " toasts: " .. toastTexts(p, mark))
	-- a VIP waits like everyone
	local deps = D._deps()
	local savedStore = deps.StoreService
	local okVip, errVip = pcall(function()
		deps.StoreService = {
			Owns = function()
				return true
			end,
			PassState = function()
				return "Owned"
			end,
		}
		now = os.time()
		setDaily(p, { Streak = 4, Paid = 4, LastClaimAt = now - 21 * HOUR, PlayStart = now, PlaySec = 0, PlayClaimed = { true } })
		mark = K.logSize()
		claim(p)
		d = DS().GetDaily(p)
		T.check(toastCount(p, LOCKED, mark) == 1 and d.Streak == 4 and d.LastClaimAt == now - 21 * HOUR, "daily unlock: a VIP's ready claim waits too", describeDaily(d) .. " toasts: " .. toastTexts(p, mark))
	end)
	deps.StoreService = savedStore
	if not okVip then
		error(errVip, 0)
	end
	-- the first claim ever waits too
	local q = join("UnlockNew", newUserId())
	loaded(q)
	advance(0.5)
	st = lastState(q)
	local qCash = DS().GetCash(q)
	T.check(st ~= nil and type(st.Unlock) == "table" and st.Unlock.Need == 600 and st.Unlock.Left == 600, "daily unlock: a new player's join payload: Left 600 (no play-day yet)", unlockText(st))
	mark = K.logSize()
	claim(q)
	T.check(toastCount(q, LOCKED, mark) == 1 and DS().GetDaily(q).Streak == 0 and DS().GetCash(q) == qCash, "daily unlock: the first claim ever waits too", describeDaily(DS().GetDaily(q)) .. " toasts: " .. toastTexts(q, mark))
	-- a play-day reset restarts the count (an unclaimed gift needs 10 minutes of the new play-day)
	alignTicks()
	now = os.time()
	setDaily(p, { Streak = 4, Paid = 4, LastClaimAt = now - 21 * HOUR, PlayStart = now - C.Play.DaySeconds + 5, PlaySec = 590, PlayClaimed = { true } })
	st = D.State(p)
	T.check(leftOf(st) == 10, "daily unlock: (setup) 590 s on a play-day 5 s from its end: Left 10", unlockText(st))
	mark = K.logSize()
	tick()
	d = DS().GetDaily(p)
	st = lastState(p)
	T.check(#states(p, mark) >= 1 and (leftOf(st) == 600 or leftOf(st) == 590) and d.PlayStart > now - C.Play.DaySeconds + 5 and d.PlaySec <= 10,
		"daily unlock: the reset tick restarts the count: its payload says Left 600 (or 590 when that tick counted)", unlockText(st) .. " " .. describeDaily(d))
	mark = K.logSize()
	claim(p)
	T.check(toastCount(p, "more min to unlock today's gift!", mark) == 1 and DS().GetDaily(p).Streak == 4, "daily unlock: ...and the claim is locked again", toastTexts(p, mark))
	-- UnlockSeconds = 0: today's rule (no lock, no hold)
	local savedNeed = C.UnlockSeconds
	local okOff, errOff = pcall(function()
		C.UnlockSeconds = 0
		now = os.time()
		setDaily(p, { Streak = 4, Paid = 4, LastClaimAt = now - 21 * HOUR, PlayStart = now, PlaySec = 0, PlayClaimed = { true } })
		D.Send(p)
		st = lastState(p)
		T.check(st ~= nil and type(st.Unlock) == "table" and st.Unlock.Need == 0 and st.Unlock.Left == 0, "daily unlock: UnlockSeconds 0: the payload says Need 0, Left 0", unlockText(st))
		local tok = DS().GetTokens(p)
		mark = K.logSize()
		claim(p)
		d = DS().GetDaily(p)
		T.check(d.Streak == 5 and DS().GetTokens(p) == tok + 250 and toastCount(p, "Day 5 of 7", mark) == 1, "daily unlock: UnlockSeconds 0: a claim with 0 s played pays (day 5, 250 Tokens)", describeDaily(d) .. " toasts: " .. toastTexts(p, mark))
		now = os.time()
		setDaily(p, { Streak = 5, Paid = 5, LastClaimAt = now - C.KeepSeconds - 1, PlayStart = now - HOUR, PlaySec = 0, PlayClaimed = { true } })
		local ok, info = D.Claim(p)
		advance(1.05)
		d = DS().GetDaily(p)
		T.check(ok == true and type(info) == "table" and info.StepBack == 1 and d.Streak == 5 and d.Paid == 5,
			"daily unlock: UnlockSeconds 0: 48 h + 1 s with a play-day an hour old steps back one day (no hold)", tostring(ok) .. " " .. (type(info) == "table" and ("StepBack " .. tostring(info.StepBack)) or tostring(info)) .. " " .. describeDaily(d))
	end)
	C.UnlockSeconds = savedNeed
	if not okOff then
		error(errOff, 0)
	end
	finish("daily_unlock", p, q)
end)

----------------------------------------------------------------------------------------------------
-- daily_unlock_hold
----------------------------------------------------------------------------------------------------
-- a fresh player, ticks aligned, the stored claim `ago` seconds back (Streak 3 / Paid 3: kept = day 4, one step back =
-- the repair of day 3), no play-day yet; a case sets its own play-day right after (no clock advance in between)
local function holdPlayer(prefix, ago)
	local p = join(prefix, newUserId())
	loaded(p)
	alignTicks()
	local L = os.time() - ago
	setDaily(p, { Streak = 3, Paid = 3, Weeks = 0, LastClaimAt = L, PlayStart = 0, PlaySec = 0, PlayClaimed = {} })
	return p, L
end

-- the last payload before a claim agrees with the claim's StepBack (Streak 3 / Paid 3)
local function agrees(st, stepBack)
	if type(st) ~= "table" then
		return false
	end
	if stepBack == 0 then
		return st.Repair == false and st.Cell == 4
	end
	return st.Repair == true and st.Cell == 3
end

-- moving ticks until the live play-day has UnlockSeconds counted after a reset (when `reset`), else until it has them at all;
-- answers { ticks, resetAt, resetPayload, resetSec }
local function playToUnlock(p, maxTicks, wantReset)
	local need = config().Daily.UnlockSeconds or 600
	local info = { ticks = 0 }
	for _ = 1, maxTicks do
		local start = DS().GetDaily(p).PlayStart
		local mark = K.logSize()
		play(p, 1)
		info.ticks = info.ticks + 1
		local d = DS().GetDaily(p)
		if wantReset and info.resetAt == nil and d.PlayStart ~= start and start > 0 then
			info.resetAt = d.PlayStart
			local list = states(p, mark)
			info.resetPayload = list[#list] and list[#list].args[1] or nil
			local h = holdsOf(p)
			info.resetSec = h and h.Sec or nil
		end
		if d.PlaySec >= need and (not wantReset or info.resetAt ~= nil) then
			break
		end
	end
	return info
end

S.daily_unlock_hold = guarded("daily_unlock_hold", function()
	if not K.needBoot() then
		return
	end
	local C = config().Daily
	local KEEP, READY, DAY = C.KeepSeconds, C.ReadySeconds, C.Play.DaySeconds
	local D = DSV()
	local players = {}
	local function claimNow(p)
		local ok, info = D.Claim(p)
		advance(1.05)
		return ok, info
	end
	local function infoText(ok, info)
		return tostring(ok) .. " " .. (type(info) == "table" and ("Streak " .. tostring(info.Streak) .. " StepBack " .. tostring(info.StepBack)) or tostring(info))
	end

	-- A: back at 47 h 55 m (no play-day yet), 10 min of play, the claim at 48 h 05 m: kept
	local p, L = holdPlayer("HoldA", 47 * HOUR + 55 * 60)
	players[#players + 1] = p
	play(p, 60)
	local st = lastState(p)
	T.check(DS().GetDaily(p).PlaySec == 600 and math.abs(os.time() - L - (48 * HOUR + 5 * 60)) <= 2, "daily unlock hold A: (setup) 60 counting ticks, now L + 48 h 05 m", describeDaily(DS().GetDaily(p)) .. " now - L " .. tostring(os.time() - L))
	local ok, info = claimNow(p)
	T.check(ok == true and type(info) == "table" and info.StepBack == 0 and info.Streak == 4, "daily unlock hold A: joined at 47 h 55 m, 10 min of play, claimed at 48 h 05 m -> kept (StepBack 0, Streak 4)", infoText(ok, info))
	T.check(agrees(st, 0), "daily unlock hold A: ...the last payload before the claim said so (Repair false, Cell 4)", unlockText(st))

	-- B: back at 49 h, 10 min of play: one step back (the hold never pays more than today's rule)
	p, L = holdPlayer("HoldB", 49 * HOUR)
	players[#players + 1] = p
	play(p, 60)
	st = lastState(p)
	ok, info = claimNow(p)
	T.check(ok == true and type(info) == "table" and info.StepBack == 1 and info.Streak == 3, "daily unlock hold B: joined at 49 h -> one step back (StepBack 1, the repair of day 3)", infoText(ok, info))
	T.check(agrees(st, 1), "daily unlock hold B: ...the last payload before the claim said so (Repair true, Cell 3)", unlockText(st))

	-- C: a play-day started at 30 h, back at 49 h 05 m in the same play-day: kept by its PlayStart
	p, L = holdPlayer("HoldC", 49 * HOUR + 5 * 60)
	players[#players + 1] = p
	setDaily(p, { PlayStart = L + 30 * HOUR, PlaySec = 0 })
	local P = DS().GetDaily(p).PlayStart
	play(p, 60)
	st = lastState(p)
	T.check(DS().GetDaily(p).PlayStart == P and DS().GetDaily(p).PlaySec == 600, "daily unlock hold C: (setup) the same play-day, 600 s", describeDaily(DS().GetDaily(p)))
	T.check(st ~= nil and st.StaleAt == P + DAY, "daily unlock hold C: the payload before the claim has StaleAt = PlayStart + DaySeconds", unlockText(st) .. " expected " .. tostring(P + DAY))
	ok, info = claimNow(p)
	T.check(ok == true and type(info) == "table" and info.StepBack == 0 and info.Streak == 4, "daily unlock hold C: a play-day started at 30 h, claimed at 49 h 15 m -> kept", infoText(ok, info))
	T.check(agrees(st, 0), "daily unlock hold C: ...the last payload before the claim said so", unlockText(st))

	-- D (the review case): a 1 min visit at 28 h 05 m started a play-day; back at 47 h 58 m, playing without a stop; that
	-- play-day resets 7 min in; 10 more min of the new day unlock; the claim is kept by this session's held seconds
	local function caseD(prefix)
		local q, Lq = holdPlayer(prefix, 47 * HOUR + 58 * 60)
		setDaily(q, { PlayStart = os.time() - (DAY - 7 * 60), PlaySec = 60 })
		local st0 = D.Send(q)
		return q, Lq, st0
	end
	local Ld, st0
	p, Ld, st0 = caseD("HoldD")
	players[#players + 1] = p
	T.check(st0 ~= nil and type(st0.Unlock) == "table" and st0.Play.DayEnds - st0.ServerNow < st0.Unlock.Left,
		"daily unlock hold D: before the reset the payload lets the window say 'Day resets in N min' (DayEnds - ServerNow < Left)", st0 and ("DayEnds - ServerNow " .. tostring(st0.Play.DayEnds - st0.ServerNow) .. " " .. unlockText(st0)) or "no payload")
	local t0 = os.time()
	local run = playToUnlock(p, 200, true)
	T.check(run.resetAt ~= nil and run.resetAt - t0 >= 7 * 60 and run.resetAt - t0 <= 7 * 60 + 10, "daily unlock hold D: (setup) the play-day reset 7 min in", "reset at +" .. tostring(run.resetAt and run.resetAt - t0))
	local rp = run.resetPayload
	if T.check(rp ~= nil and run.resetSec ~= nil, "daily unlock hold D: (setup) the reset tick sent a payload and the session holds seconds", tostring(run.resetSec)) then
		local now = rp.ServerNow
		local from = math.min(run.resetAt, now - run.resetSec)
		local keepAt = math.min(now, math.max(from, Ld + READY))
		T.check(rp.StaleAt == rule(keepAt, Ld) + run.resetSec, "daily unlock hold D: after the reset StaleAt = rule(keepAt) + Sec",
			"StaleAt " .. tostring(rp.StaleAt) .. " expected " .. tostring(rule(keepAt, Ld) + run.resetSec) .. " (keepAt - L " .. tostring(keepAt - Ld) .. ", Sec " .. tostring(run.resetSec) .. ")")
		T.check(agrees(rp, 0), "daily unlock hold D: ...and it still shows the kept streak (Cell 4)", unlockText(rp))
	end
	local h = holdsOf(p)
	T.check(DS().GetDaily(p).PlaySec == 600 and h ~= nil and h.Sec >= 1000 and h.Sec <= 1040 and h.Last == Ld,
		"daily unlock hold D: unlocked after the new day's 10 min; the session held about 17 min (every locked counting tick)", describeDaily(DS().GetDaily(p)) .. " " .. holdText(p))
	T.check(os.time() - Ld > KEEP and run.resetAt - Ld > KEEP, "daily unlock hold D: (precondition) now and the new PlayStart are both past 48 h", "now - L " .. tostring(os.time() - Ld) .. " PlayStart - L " .. tostring(run.resetAt - Ld))
	st = lastState(p)
	ok, info = claimNow(p)
	T.check(ok == true and type(info) == "table" and info.StepBack == 0 and info.Streak == 4, "daily unlock hold D: the claim after the new day's 10 min is kept (StepBack 0)", infoText(ok, info))
	T.check(agrees(st, 0), "daily unlock hold D: ...the last payload before the claim said so", unlockText(st))
	h = holdsOf(p)
	T.check(h == nil or h.Sec == 0, "daily unlock hold D: the claim drops the held seconds (a new stamp)", holdText(p))

	-- E: as D, then 3 min standing still after the unlock: now - Sec passes 48 h -> one step back
	p, Ld, st0 = caseD("HoldE")
	players[#players + 1] = p
	run = playToUnlock(p, 200, true)
	T.check(run.resetAt ~= nil and DS().GetDaily(p).PlaySec == 600, "daily unlock hold E: (setup) the reset and the unlock as in D", describeDaily(DS().GetDaily(p)))
	tick(18)
	h = holdsOf(p)
	T.check(h ~= nil and h.Sec >= 1000 and h.Sec <= 1040, "daily unlock hold E: standing still adds no held seconds", holdText(p))
	T.check(h ~= nil and os.time() - h.Sec - Ld > KEEP, "daily unlock hold E: (precondition) now - Sec is past L + 48 h", h and ("now - Sec - L " .. tostring(os.time() - h.Sec - Ld)) or "no hold")
	st = lastState(p)
	ok, info = claimNow(p)
	T.check(ok == true and type(info) == "table" and info.StepBack == 1 and info.Streak == 3, "daily unlock hold E: 3 min still after the unlock, then the claim -> one step back", infoText(ok, info))
	T.check(agrees(st, 1), "daily unlock hold E: ...the last payload before the claim said so (the tick re-sent it at StaleAt)", unlockText(st))

	-- F: a changed stamp starts the held seconds over
	p, L = holdPlayer("HoldF", 30 * HOUR)
	players[#players + 1] = p
	play(p, 10)
	h = holdsOf(p)
	T.check(h ~= nil and h.Sec == 100 and h.Last == L, "daily unlock hold F: 10 locked counting ticks hold 100 s for the stamp", holdText(p))
	local L2 = L - 3600
	setDaily(p, { LastClaimAt = L2 })
	play(p, 1)
	h = holdsOf(p)
	T.check(h ~= nil and h.Sec == 10 and h.Last == L2, "daily unlock hold F: a changed stamp (a rebase, another server's claim) starts them over", holdText(p))

	-- G: the contrast of daily_unlock's UnlockSeconds = 0 case: with the rule on, a 48 h + 1 s gap on a play-day an hour old
	-- (unlocked) is kept by that PlayStart
	p, L = holdPlayer("HoldG", KEEP + 1)
	players[#players + 1] = p
	setDaily(p, { PlayStart = os.time() - HOUR, PlaySec = 600, PlayClaimed = { true } })
	ok, info = claimNow(p)
	T.check(ok == true and type(info) == "table" and info.StepBack == 0 and info.Streak == 4, "daily unlock hold G: 48 h + 1 s, a play-day started an hour ago, unlocked -> kept by its PlayStart", infoText(ok, info))
	finish("daily_unlock_hold", unpack(players))
end)

----------------------------------------------------------------------------------------------------
-- daily_unlock_hop
----------------------------------------------------------------------------------------------------
S.daily_unlock_hop = guarded("daily_unlock_hop", function()
	if not K.needBoot() then
		return
	end
	local KEEP = config().Daily.KeepSeconds
	local D = DSV()
	local uid = newUserId()
	local p = join("Hop", uid)
	loaded(p)
	alignTicks()
	local L = os.time() - (47 * HOUR + 55 * 60)
	setDaily(p, { Streak = 3, Paid = 3, Weeks = 0, LastClaimAt = L, PlayStart = 0, PlaySec = 0, PlayClaimed = {} })
	-- server A: 6 min of play, then the player leaves (the leave save)
	play(p, 36)
	local dA = DS().GetDaily(p)
	local P = dA.PlayStart
	T.check(dA.PlaySec == 360 and P > 0, "daily unlock hop: (setup) 6 min on server A", describeDaily(dA))
	local st = D.State(p)
	T.check(leftOf(st) == 240, "daily unlock hop: Left 240 on A", unlockText(st))
	leave(p)
	local rec = stored(uid) or {}
	T.check(type(rec.Daily) == "table" and rec.Daily.PlayStart == P and rec.Daily.PlaySec == 360, "daily unlock hop: A's leave save stores the play-day (PlayStart, 360 s)", describeDaily(rec.Daily))
	local cashStored = rec.Cash or 0
	-- server B: the next session reads the stored play-day only (no held seconds of A's session)
	local mark = K.logSize()
	p = join("Hop", uid)
	loaded(p)
	advance(0.5)
	local first = nil
	for _, e in ipairs(states(p, mark)) do
		if type(e.args[1]) == "table" and e.args[1].Loading ~= true then
			first = e.args[1]
			break
		end
	end
	T.check(leftOf(first) == 240, "daily unlock hop: B's join payload says Left 240 (A's 6 min count)", unlockText(first))
	T.check(holdsOf(p) == nil, "daily unlock hop: B holds no seconds at the join", holdText(p))
	alignTicks()
	local n = 0
	for _ = 1, 40 do
		play(p, 1)
		n = n + 1
		if leftOf(D.State(p)) == 0 then
			break
		end
	end
	local d = DS().GetDaily(p)
	T.check(d.PlaySec == 600 and d.PlayStart == P and n <= 26, "daily unlock hop: 4 min of play on B unlock the gift (the same play-day, 600 s)", describeDaily(d) .. " ticks " .. n)
	local h = holdsOf(p)
	T.check(os.time() - L > KEEP and h ~= nil and os.time() - h.Sec - L > KEEP and P - L < KEEP,
		"daily unlock hop: (precondition) past 48 h, B's own held seconds alone would step back, the stored PlayStart is before 48 h",
		"now - L " .. tostring(os.time() - L) .. " " .. holdText(p) .. " PlayStart - L " .. tostring(P - L))
	local cash0 = DS().GetCash(p)
	mark = K.logSize()
	local ok, info = D.Claim(p)
	advance(1.05)
	d = DS().GetDaily(p)
	T.check(ok == true and type(info) == "table" and info.StepBack == 0 and d.Streak == 4 and DS().GetCash(p) == cash0 + 1000 and toastCount(p, "Day 4 of 7", mark) == 1,
		"daily unlock hop: the claim on B after 48 h is kept by the stored PlayStart and pays day 4 once", tostring(ok) .. " " .. describeDaily(d) .. " cash +" .. tostring(DS().GetCash(p) - cash0))
	T.check(DS().Save(p) == true and (stored(uid) or {}).Daily ~= nil and stored(uid).Daily.Streak == 4 and stored(uid).Cash == cashStored + 1000,
		"daily unlock hop: ...and the save stores Streak 4 and the $1,000 once", describeDaily((stored(uid) or {}).Daily) .. " cash " .. tostring((stored(uid) or {}).Cash) .. " (before " .. cashStored .. ")")
	finish("daily_unlock_hop", p)
end)

return S
