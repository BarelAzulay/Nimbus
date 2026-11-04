-- smoke_fixr_daily.lua: the review fixes of DailyService (store 2026-11-04, review fix C; spec
-- docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.2 / 6 / 7 Z8 / 13 Q17). Server world only.
--   fixr_daily_playday_reset  a finished play-day resets on the first tick past DaySeconds even when the tick does not
--                             count (a still root, no remote); while no tick has run (no root) State shows no tier
--                             Ready and ClaimPlay refuses with the day-over text: a dead day's tiers are never banked (Q17)
--   fixr_daily_readyat        a stored LastClaimAt past FutureClockSlack (a wrong-clock server) is clamped where the
--                             payload is built: the join's payload has ReadyAt <= ServerNow + ReadySeconds, the clamp is
--                             this session's only (the record and the store keep the stamp), a claim then waits 20 h and
--                             pays; a stamp inside the slack is kept as it is (Z8)
--   fixr_daily_slow_clock     (re-review 1, finding 1) a store claim at r0 read by a server whose clock runs 2 h behind:
--                             the join's payload counts down from now, but neither the payload nor a hand-sent claim
--                             writes the clamp, so no save lowers the stored LastClaimAt; 20 h after the join the claim
--                             pays and its own pair (with its grant) is stored
--   fixr_daily_repair_state   (re-review 1, finding 2) after a missed day the payload shows what the claim will do: a
--                             repair (Repair = true, Today on the repair cell, no gift on it), never the next day's gift;
--                             the claim then repairs and pays nothing; a kept streak and a VIP (never steps back) still
--                             show the gift
--   fixr_daily_stamp_race     the claim's now and its grant's At are ONE stamp: a wall-clock second ticking inside
--                             Claim no longer lets a dropped claim's pair replace the stored one (the section 6 merge;
--                             needs DataService.MutateDaily's `now` argument)
-- White-box: the booted helpers of smoke_daily.lua ("server B" = a second DataService copy against the same mock store).
-- The mock's os.time() is floor(EPOCH + clock): a claim is fired FIRST and the clock advanced AFTER. Plain Lua 5.1 syntax.

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

----------------------------------------------------------------------------------------------------
-- helpers
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
	return 985700 + userSeq
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

-- fires DailyRequest "Claim" FIRST (at the current os.time(), returned) and lets the 1 req/s window pass AFTER
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

local function describeDaily(d)
	if type(d) ~= "table" then
		return tostring(d)
	end
	local claimed = {}
	for i in pairs(type(d.PlayClaimed) == "table" and d.PlayClaimed or {}) do
		claimed[#claimed + 1] = tostring(i)
	end
	return "Streak " .. tostring(d.Streak) .. " Paid " .. tostring(d.Paid) .. " LastClaimAt " .. tostring(d.LastClaimAt) .. " PlayStart " .. tostring(d.PlayStart) .. " PlaySec " .. tostring(d.PlaySec) .. " PlayClaimed {" .. table.concat(claimed, ",") .. "}"
end

local function anyReady(st)
	if type(st) ~= "table" or type(st.Play) ~= "table" then
		return nil
	end
	for _, t in ipairs(st.Play.Tiers or {}) do
		if t.Ready == true then
			return true
		end
	end
	return false
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

-- a second, independent copy of DataService (own cache, same mock store): "another server" (the smoke_p7_data shape)
local function secondServer(name)
	local inst = K.moduleInstance("server/Services/DataService")
	if not inst then
		return nil
	end
	local sigs = { game:GetService("Players").PlayerRemoving }
	for _, rn in ipairs({ "RequestProfile", "SettingsSet" }) do
		local r = remote(rn)
		if r then
			sigs[#sigs + 1] = r.OnServerEvent
		end
	end
	local marks = {}
	for _, sig in ipairs(sigs) do
		local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
		marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
	end
	local clone = inst:Clone()
	clone.Name = name
	clone.Parent = inst.Parent
	local ok, module = pcall(require, clone)
	if not ok then
		clone:Destroy()
		return nil, module
	end
	local function release()
		clone:Destroy()
		for _, m in ipairs(marks) do
			if m.conns then
				for i = #m.conns, m.n + 1, -1 do
					local conn = m.conns[i]
					if type(conn) == "table" and conn.Disconnect then
						conn:Disconnect()
					end
				end
			end
		end
		return true
	end
	return module, clone, release
end

local function finish(name, p, ...)
	for _, q in ipairs({ p, ... }) do
		leave(q)
	end
	K.flushErrors(name)
	K.flushWarnings(name, ALLOWED_WARNINGS)
end

----------------------------------------------------------------------------------------------------
-- fixr_daily_playday_reset (review finding 2, Q17)
----------------------------------------------------------------------------------------------------
S.fixr_daily_playday_reset = guarded("fixr_daily_playday_reset", function()
	if not K.needBoot() then
		return
	end
	local Pcfg = config().Daily.Play
	local D = DSV()
	local p = join("FxDay", newUserId())
	loaded(p)
	alignTicks()
	-- a still tick (no move, no remote) on a dead day: the reset runs anyway, nothing is counted, a payload goes out
	local cash0, gems0, tokens0 = DS().GetCash(p), DS().GetGems(p), DS().GetTokens(p)
	local P = os.time() - Pcfg.DaySeconds - 5
	setDaily(p, { PlayStart = P, PlaySec = 600, PlayClaimed = {} })
	local mark = K.logSize()
	local tTick = os.time()
	advance(10)
	local d = DS().GetDaily(p)
	T.check(d.PlayStart >= tTick and d.PlayStart <= tTick + 10 and d.PlaySec == 0 and next(d.PlayClaimed) == nil,
		"fixr daily playday reset: a still tick past the 20 h play-day starts a new one (PlayStart now, PlaySec 0, PlayClaimed {})", describeDaily(d))
	local st = lastState(p)
	T.check(#states(p, mark) >= 1 and st ~= nil and anyReady(st) == false and st.Play.Seconds == 0, "fixr daily playday reset: ...and sent a payload with no tier Ready", st and ("Seconds " .. tostring(st.Play.Seconds)) or "no payload")
	mark = K.logSize()
	request(p, "ClaimPlay", 1)
	advance(1.05)
	d = DS().GetDaily(p)
	T.check(d.PlayClaimed[1] == nil and DS().GetCash(p) == cash0 and DS().GetGems(p) == gems0 and DS().GetTokens(p) == tokens0 and toastCount(p, "more minute", mark) == 1,
		"fixr daily playday reset: tier 1 of the dead day cannot be claimed after that tick (nothing paid, 'Play 10 more minutes!')", describeDaily(d))
	-- before any tick has run (no root: the tick does nothing at all) State and ClaimPlay already treat the day as over
	P = os.time() - Pcfg.DaySeconds - 5
	setDaily(p, { PlayStart = P, PlaySec = 600, PlayClaimed = {} })
	local char = p.Character
	p.Character = nil
	D.Tick()
	d = DS().GetDaily(p)
	T.check(d.PlayStart == P and d.PlaySec == 600, "fixr daily playday reset: (setup) a tick with no Character resets nothing (Review Focus 4)", describeDaily(d))
	st = D.State(p)
	T.check(st ~= nil and anyReady(st) == false and st.Play.Tiers[1].Claimed == false, "fixr daily playday reset: State marks no tier of the dead day Ready (600 s, tier 1 unclaimed)", st and tostring(st.Play.Tiers[1].Ready) or "no payload")
	local ok, reason = D.ClaimPlay(p, 1)
	d = DS().GetDaily(p)
	T.check(ok == false and reason == "That play day is over!" and d.PlayClaimed[1] == nil and DS().GetCash(p) == cash0, "fixr daily playday reset: ClaimPlay on the dead day refuses with 'That play day is over!' and pays nothing", tostring(ok) .. " " .. tostring(reason) .. " " .. describeDaily(d))
	-- the live day is untouched: 1 s before its end tier 1 is still Ready and pays
	setDaily(p, { PlayStart = os.time() - Pcfg.DaySeconds + 30, PlaySec = 600, PlayClaimed = {} })
	st = D.State(p)
	T.check(st ~= nil and st.Play.Tiers[1].Ready == true, "fixr daily playday reset: 30 s before the day's end tier 1 is Ready")
	ok = D.ClaimPlay(p, 1)
	T.check(ok == true and DS().GetDaily(p).PlayClaimed[1] == true and DS().GetCash(p) == cash0 + 200, "fixr daily playday reset: ...and pays $200", "cash +" .. tostring(DS().GetCash(p) - cash0))
	p.Character = char
	if not (K.root(p) and K.hum(p)) then
		Mock.Respawn(p)
		advance(0.2)
	end
	finish("fixr_daily_playday_reset", p)
end)

----------------------------------------------------------------------------------------------------
-- fixr_daily_readyat (review finding 3, Z8)
----------------------------------------------------------------------------------------------------
S.fixr_daily_readyat = guarded("fixr_daily_readyat", function()
	if not K.needBoot() then
		return
	end
	local READY = config().Daily.ReadySeconds
	local uid = newUserId()
	local p = join("FxReady", uid)
	loaded(p)
	claim(p)
	T.eq(DS().GetDaily(p).Streak, 1, "fixr daily readyat: (setup) day 1 claimed")
	-- a wrong-clock server stored a claim 2 h ahead; the player rejoins a correct server
	local future = os.time() + 7200
	T.check(setDaily(p, { LastClaimAt = future }) and DS().Save(p) == true and (stored(uid) or {}).Daily ~= nil and stored(uid).Daily.LastClaimAt == future,
		"fixr daily readyat: (setup) the store holds a LastClaimAt 2 h ahead", tostring(stored(uid) and stored(uid).Daily and stored(uid).Daily.LastClaimAt))
	leave(p)
	local mark = K.logSize()
	p = join("FxReady", uid)
	loaded(p)
	advance(0.5)
	local first = nil
	for _, e in ipairs(states(p, mark)) do
		if type(e.args[1]) == "table" and e.args[1].Loading ~= true then
			first = e.args[1]
			break
		end
	end
	T.check(first ~= nil and first.ReadyAt <= first.ServerNow + READY, "fixr daily readyat: the join's payload has ReadyAt <= ServerNow + ReadySeconds (the clamp reaches the window)",
		first and ("ReadyAt " .. tostring(first.ReadyAt) .. " ServerNow " .. tostring(first.ServerNow) .. " (+" .. tostring(first.ReadyAt - first.ServerNow) .. ")") or "no payload")
	-- re-review 1 (finding 1): the clamp is this session's view only; a bare clamp in the store would let a server whose
	-- clock runs behind pull the next gift earlier on every other server
	local d = DS().GetDaily(p)
	T.check(first ~= nil and d.LastClaimAt == future and d.Streak == 1 and d.Paid == 1,
		"fixr daily readyat: ...the clamp is never written: the live record keeps the stored stamp (Streak / Paid kept)", describeDaily(d))
	T.check(DS().Save(p) == true and (stored(uid) or {}).Daily ~= nil and stored(uid).Daily.LastClaimAt == future, "fixr daily readyat: ...and a save leaves the stored stamp as it was",
		tostring(stored(uid) and stored(uid).Daily and stored(uid).Daily.LastClaimAt) .. " vs " .. tostring(future))
	local tokens0 = DS().GetTokens(p)
	mark = K.logSize()
	claim(p)
	T.check(DS().GetDaily(p).Streak == 1 and DS().GetTokens(p) == tokens0 and toastCount(p, "Next gift in", mark) == 1, "fixr daily readyat: a claim right after waits for the next gift", describeDaily(DS().GetDaily(p)))
	-- 20 h after the join (the clamp's now) the claim pays: the window's countdown was true
	advance(READY)
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 2 and DS().GetTokens(p) == tokens0 + 50, "fixr daily readyat: 20 h after the clamp the claim pays day 2", describeDaily(d))
	-- a stamp inside the slack is kept as it is
	local near = os.time() + 200
	setDaily(p, { LastClaimAt = near })
	local st = DSV().State(p)
	T.check(st ~= nil and st.ReadyAt == near + READY and DS().GetDaily(p).LastClaimAt == near, "fixr daily readyat: a LastClaimAt 200 s ahead (inside the slack) is kept: ReadyAt = it + 20 h", st and tostring(st.ReadyAt - near) or "no payload")
	finish("fixr_daily_readyat", p)
end)

----------------------------------------------------------------------------------------------------
-- fixr_daily_stamp_race (review finding 8)
----------------------------------------------------------------------------------------------------
S.fixr_daily_stamp_race = guarded("fixr_daily_stamp_race", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local DV = DSV()
	local B, cloneB, releaseB = secondServer("DataServiceFixrB")
	if not T.check(B ~= nil and type(B.MutateDaily) == "function", "fixr daily stamp race: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	local origResolve = DV.Resolve
	local okRun, errRun = pcall(function()
		local uid = newUserId()
		local p = join("FxRace", uid)
		loaded(p)
		T.eq(D.Save(p), true, "fixr daily stamp race: (setup) the first save")
		B.Load(p)
		advance(0.5)
		local cash0 = (stored(uid) or {}).Cash or 0
		-- B (loaded with A) claims day 1 first (its stamp 10 min back) and saves: the store holds (tB, 1) and +$400; A claims
		-- right after, before any save of A's could rebase it onto B's claim
		local tB = os.time() - 600
		T.check(B.MutateDaily(p, function(d)
			d.Streak = 1
			d.Paid = 1
			d.LastClaimAt = tB
			return true
		end, { Kind = "Day", Cash = 400 }) and B.AddCash(p, 400) and B.Save(p) == true, "fixr daily stamp race: (setup) B claims day 1 and saves")
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tB and rec.Cash == cash0 + 400, "fixr daily stamp race: (setup) the store holds (tB, 1) and +$400")
		-- A's DailyService still sees no claim: it pays day 1, and the wall clock ticks one second inside Claim (between
		-- its now and the MutateDaily commit; Resolve runs there)
		local bumped = false
		DV.Resolve = function(...)
			local r = origResolve(...)
			if not bumped then
				bumped = true
				Mock.Clock.now = Mock.Clock.now + 1
			end
			return r
		end
		local t0 = os.time()
		local ok, info = DV.Claim(p)
		DV.Resolve = origResolve
		local dA = D.GetDaily(p)
		T.check(ok == true and bumped and dA.LastClaimAt == t0 and os.time() == t0 + 1, "fixr daily stamp race: (setup) A's claim commits at its own now while the wall clock moved a second", tostring(ok) .. " " .. tostring(info) .. " " .. describeDaily(dA) .. " t0 " .. t0 .. " now " .. os.time())
		T.eq(D.Save(p), true, "fixr daily stamp race: A saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tB and rec.Daily.Streak == 1 and rec.Cash == cash0 + 400,
			"fixr daily stamp race: the store keeps B's pair (tB, 1) and the $400 once (A's grant dropped, its pair with it)",
			"pair " .. tostring(rec.Daily and rec.Daily.LastClaimAt) .. "/" .. tostring(rec.Daily and rec.Daily.Streak) .. " (tB " .. tB .. ", tA " .. t0 .. ") cash " .. tostring(rec.Cash) .. " (base " .. cash0 .. ")")
		leave(p)
	end)
	DV.Resolve = origResolve
	advance(12)
	T.check(releaseB() == true, "fixr daily stamp race: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixr_daily_stamp_race")
	K.flushWarnings("fixr_daily_stamp_race", ALLOWED_WARNINGS)
end)

-- the first non-Loading DailyState payload to p since the log mark
local function firstPayload(p, mark)
	for _, e in ipairs(states(p, mark)) do
		if type(e.args[1]) == "table" and e.args[1].Loading ~= true then
			return e.args[1]
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- fixr_daily_slow_clock (re-review round 1, finding 1: a slow server never pulls the stored claim earlier)
----------------------------------------------------------------------------------------------------
S.fixr_daily_slow_clock = guarded("fixr_daily_slow_clock", function()
	if not K.needBoot() then
		return
	end
	local READY, KEEP = config().Daily.ReadySeconds, config().Daily.KeepSeconds
	local uid = newUserId()
	local p = join("FxSlow", uid)
	loaded(p)
	claim(p)
	T.eq(DS().GetDaily(p).Streak, 1, "fixr daily slow clock: (setup) day 1 claimed")
	-- a correct server paid day 1 at r0; this server's os.time() runs 2 h (7200 s > FutureClockSlack) behind it, so the
	-- stored stamp reads 2 h ahead here
	local r0 = os.time() + 7200
	T.check(setDaily(p, { LastClaimAt = r0 }) and DS().Save(p) == true and (stored(uid) or {}).Daily ~= nil and stored(uid).Daily.LastClaimAt == r0,
		"fixr daily slow clock: (setup) the store holds the claim r0, 2 h ahead of this server's clock")
	leave(p)
	local mark = K.logSize()
	p = join("FxSlow", uid)
	loaded(p)
	advance(0.5)
	local first = firstPayload(p, mark)
	T.check(first ~= nil and first.ReadyAt <= first.ServerNow + READY and first.ReadyAt >= first.ServerNow + READY - 5,
		"fixr daily slow clock: the join's payload counts down from now (ReadyAt = ServerNow + 20 h, finding 3 stays fixed)",
		first and ("ReadyAt - ServerNow = " .. tostring(first.ReadyAt - first.ServerNow)) or "no payload")
	T.check(first ~= nil and first.KeepUntil <= first.ServerNow + KEEP, "fixr daily slow clock: ...and the keep window from the same clamped stamp",
		first and ("KeepUntil - ServerNow = " .. tostring(first.KeepUntil - first.ServerNow)) or "no payload")
	T.eq(DS().GetDaily(p).LastClaimAt, r0, "fixr daily slow clock: building the payload writes nothing (the live record keeps r0)")
	-- a hand-sent claim (the window never sends one now) is refused and writes nothing either
	local tokens0 = DS().GetTokens(p)
	mark = K.logSize()
	claim(p)
	local d = DS().GetDaily(p)
	T.check(d.LastClaimAt == r0 and d.Streak == 1 and DS().GetTokens(p) == tokens0 and toastCount(p, "Next gift in", mark) == 1,
		"fixr daily slow clock: a hand-sent claim is refused ('Next gift in ...') and leaves the record at r0", describeDaily(d))
	-- the autosave / leave save never lowers the stored stamp (the exploit: each visit to a slow server cut the next wait)
	T.check(DS().Save(p) == true and (stored(uid) or {}).Daily ~= nil and stored(uid).Daily.LastClaimAt == r0 and stored(uid).Daily.Streak == 1,
		"fixr daily slow clock: a save after the join and the refused claim leaves the stored LastClaimAt at r0",
		"stored " .. tostring(stored(uid) and stored(uid).Daily and stored(uid).Daily.LastClaimAt) .. " r0 " .. r0)
	-- 20 h after the join this session pays day 2 (never locked out), and that claim's pair lands with its grant
	advance(READY)
	T.eq(DS().Save(p), true, "fixr daily slow clock: (setup) a save before the claim")
	local storedTokens = (stored(uid) or {}).Tokens or 0
	tokens0 = DS().GetTokens(p)
	local t2 = claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 2 and d.LastClaimAt == t2 and DS().GetTokens(p) == tokens0 + 50, "fixr daily slow clock: 20 h after the join the claim pays day 2", describeDaily(d) .. " t2 " .. t2)
	T.check(DS().Save(p) == true and stored(uid).Daily.LastClaimAt == t2 and stored(uid).Daily.Streak == 2 and stored(uid).Tokens == storedTokens + 50,
		"fixr daily slow clock: ...and the save stores that claim's pair (t2, 2) and keeps its 50 Tokens",
		"pair " .. tostring(stored(uid).Daily.LastClaimAt) .. "/" .. tostring(stored(uid).Daily.Streak) .. " tokens " .. tostring(stored(uid).Tokens) .. " (before " .. storedTokens .. ")")
	finish("fixr_daily_slow_clock", p)
end)

----------------------------------------------------------------------------------------------------
-- fixr_daily_repair_state (re-review round 1, finding 2: the window shows the repair the claim will make)
----------------------------------------------------------------------------------------------------
S.fixr_daily_repair_state = guarded("fixr_daily_repair_state", function()
	if not K.needBoot() then
		return
	end
	local D = DSV()
	local deps = D._deps and D._deps() or nil
	if not T.check(type(deps) == "table", "fixr daily repair state: DailyService._deps() for the VIP double") then
		return
	end
	local p = join("FxRepair", newUserId())
	loaded(p)
	local function cellsText(st)
		local parts = {}
		for i, e in ipairs(st and st.Days or {}) do
			parts[#parts + 1] = i .. ":" .. (e.Claimed and "C" or "") .. (e.Today and "T" or "") .. (e.Repair and "R" or "") .. "=" .. tostring(e.Kind) .. "/" .. tostring(e.Amount)
		end
		return "Cell " .. tostring(st and st.Cell) .. " Repair " .. tostring(st and st.Repair) .. " " .. table.concat(parts, " ")
	end
	-- Streak 3 / Paid 3, the last claim 50 h ago (one missed day): the claim steps back to day 2 and re-earns day 3, unpaid
	local now = os.time()
	setDaily(p, { Streak = 3, Paid = 3, Weeks = 0, LastClaimAt = now - 50 * 3600 })
	local st = D.State(p)
	local days = st and st.Days or {}
	T.check(st ~= nil and st.Repair == true and st.Cell == 3 and st.ReadyAt <= st.ServerNow,
		"fixr daily repair state: one missed day (Streak 3, Paid 3, 50 h): the payload is a repair of day 3, claimable now", cellsText(st))
	T.check(days[3] ~= nil and days[3].Today == true and days[3].Repair == true and days[3].Claimed ~= true and days[4] ~= nil and days[4].Today ~= true and days[4].Repair ~= true,
		"fixr daily repair state: ...Today sits on the repair cell (day 3, flagged Repair), not on day 4's gift", cellsText(st))
	T.check(days[1] ~= nil and days[1].Claimed == true and days[2] ~= nil and days[2].Claimed == true and days[3] ~= nil and days[3].Claimed ~= true and days[4] ~= nil and days[4].Claimed ~= true,
		"fixr daily repair state: ...days 1-2 claimed (the stepped-back streak), day 3 open", cellsText(st))
	local cash0, tokens0, gems0 = DS().GetCash(p), DS().GetTokens(p), DS().GetGems(p)
	local mark = K.logSize()
	claim(p)
	local d = DS().GetDaily(p)
	T.check(d.Streak == 3 and d.Paid == 3 and DS().GetCash(p) == cash0 and DS().GetTokens(p) == tokens0 and DS().GetGems(p) == gems0 and toastCount(p, "Streak repaired! Day 3 of 7", mark) == 1,
		"fixr daily repair state: the claim does what the window said: 'Streak repaired! Day 3 of 7', nothing paid", describeDaily(d))
	st = lastState(p)
	T.check(st ~= nil and st.Repair ~= true and st.Cell == 4 and st.Days[3].Claimed == true and st.Days[4].Repair ~= true,
		"fixr daily repair state: ...the next payload: day 3 claimed, day 4 next, no repair", cellsText(st))
	-- three missed days (Streak 5, Paid 5, 98 h): the step-back is 3, the repair re-earns day 3
	now = os.time()
	setDaily(p, { Streak = 5, Paid = 5, LastClaimAt = now - 98 * 3600 })
	st = D.State(p)
	T.check(st ~= nil and st.Repair == true and st.Cell == 3 and st.Days[3].Today == true and st.Days[3].Repair == true and st.Days[2].Claimed == true and st.Days[3].Claimed ~= true and st.Days[6].Today ~= true,
		"fixr daily repair state: three missed days (Streak 5, Paid 5, 98 h): a repair of day 3", cellsText(st))
	-- a kept streak (30 h): the next day's gift, no repair
	setDaily(p, { Streak = 3, Paid = 3, LastClaimAt = now - 30 * 3600 })
	st = D.State(p)
	T.check(st ~= nil and st.Repair ~= true and st.Cell == 4 and st.Days[4].Today == true and st.Days[4].Repair ~= true and (st.Days[4].Amount or 0) >= 1,
		"fixr daily repair state: a kept streak (30 h) shows day 4's gift, no repair", cellsText(st))
	-- VIP never steps back: the same missed day shows the gift
	local realStore = deps.StoreService
	deps.StoreService = {
		Owns = function(_, key)
			return key == "VIP"
		end,
		PassState = function()
			return "Owned"
		end,
	}
	local okVip, errVip = pcall(function()
		setDaily(p, { Streak = 3, Paid = 3, LastClaimAt = now - 50 * 3600 })
		st = D.State(p)
		T.check(st ~= nil and st.Vip == true and st.Repair ~= true and st.Cell == 4 and st.Days[4].Today == true,
			"fixr daily repair state: a VIP (never steps back) with the same missed day sees day 4's gift", cellsText(st))
	end)
	deps.StoreService = realStore
	if not okVip then
		error(errVip, 0)
	end
	finish("fixr_daily_repair_state", p)
end)

return S
