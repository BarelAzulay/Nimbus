-- smoke_fixr_data.lua: review fix B of the Robux Store build (docs/superpowers/specs/2026-11-04-shop-retention-design.md
-- section 6 / Z2 / Z8 / Z11; plan docs/superpowers/plans/2026-11-04-store.md Task 5): DataService's cross-server merges
-- of the twin rules where the review found a hole. Server world only, booted (DataStores on).
--   fixr_data_wrongclock_day  a Day claim written by a server whose clock runs 600 s ahead (past FutureClockSlack)
--                             lands while server B (loaded before it) claims the same day: the gift is paid ONCE and
--                             the stored pair stays; B's clamp (no grant) then takes the pair; a save that never moved
--                             the pair (a play-time tick) leaves a wrong-clock pair alone; a session that SAW a far-future
--                             stored claim, clamped it and claims 20 h later keeps that grant
--   fixr_data_prestige_cash   a Trove ask paid on two servers that both prestiged to the same star (the orphan retry of
--                             the first lands last): the Cash earned since the prestiges is kept; the gift counts once
--                             when it was paid after a prestige, never twice, and a copy a prestige reset is never taken
--                             off the balance again
--   fixr_data_petlevel        the Starter pack (a Lv 5 pet) granted on two servers and fed to Lv 7 on the second: the
--                             orphan retry of the first keeps Lv 7 (the higher level per key after the receipt twin); a
--                             session that fed it higher still wins
--   fixr_data_daily_stamp     MutateDaily(player, fn, grant, now) stamps the grant's At with `now`: a clock second that
--                             ticks inside fn never splits a dropped claim from its pair (the stored pair stays); without
--                             `now` MutateDaily reads os.time() once; a number in the grant's place is `now`
--   fixr_data_clamp_twin      (re-review round 2, finding 1) a store stamp F 6 min ahead (a fast server wrote it): the
--                             session's Z8 clamp lets it claim 20 h after the join (less than 20 h after F), its final
--                             save fails (an orphan); another server loads the stale F and pays the same day; the
--                             orphan retry lands last: the day is paid ONCE (the clamp claim is no exception to the
--                             twin rule: its grant records the stamp it built on, Prev = F)
--   fixr_data_revert_twin     (re-review round 3, findings 1 / 4) a save that never moved its pair (a play-time tick, a
--                             noted Z8 first sight) lands late, after another server's claim replaced a stamp F that was
--                             30 h / 3 days ahead: the claim stays in the store (F never comes back), so a third
--                             server's claim built on F is still the twin and day 3 is paid ONCE; the stale first sight
--                             of F never comes back with it
-- White-box: the booted helpers of smoke_p7_data.lua; "server A" / "server B" are copies of DataService against the same
-- mock store (the smoke_p5_data.lua secondServer shape). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local advance, config, mod = K.advance, K.config, K.mod
local ALLOWED_WARNINGS = { "[DataService]" }
local ID_STARTER = "fixr-starter-1"

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local function DS()
	return mod("DataService")
end

local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 986500 + userSeq
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

local function storeKey(uid)
	return config().Tokens.DataStoreName .. "/u_" .. uid
end

local function stored(uid)
	return Mock.DataStore.Data[storeKey(uid)]
end

local function statsOf()
	return { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} }
end

local function dailyText(rec)
	local d = type(rec) == "table" and type(rec.Daily) == "table" and rec.Daily or {}
	return "pair (" .. tostring(d.LastClaimAt) .. ", " .. tostring(d.Streak) .. ") Paid " .. tostring(d.Paid) .. " Tokens " .. tostring(type(rec) == "table" and rec.Tokens)
end

local function hookedSignals()
	local out = { game:GetService("Players").PlayerRemoving }
	local folder = K.remoteFolder and K.remoteFolder()
	for _, name in ipairs({ "RequestProfile", "SettingsSet" }) do
		local remote = folder and folder:FindFirstChild(name)
		if remote then
			out[#out + 1] = remote.OnServerEvent
		end
	end
	return out
end

local function connectionMarks()
	local marks = {}
	for _, sig in ipairs(hookedSignals()) do
		local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
		marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
	end
	return marks
end

local function dropHooks(marks)
	local clean = true
	for _, m in ipairs(marks) do
		if m.conns then
			for i = #m.conns, m.n + 1, -1 do
				local conn = m.conns[i]
				if type(conn) == "table" and conn.Disconnect then
					conn:Disconnect()
				end
			end
			clean = clean and #m.conns == m.n
		else
			clean = false
		end
	end
	return clean
end

-- a second, independent copy of DataService (own cache, same mock store): "another server"
local function secondServer(name)
	local inst = K.moduleInstance("server/Services/DataService")
	if not inst then
		return nil
	end
	local marks = connectionMarks()
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
		return dropHooks(marks)
	end
	return module, clone, release
end

-- one Day claim on a copy of DataService: the MutateDaily write + grant DailyService.Claim makes, paid right after.
-- `at` is the claim's one clock (its LastClaimAt and, through MutateDaily's `now`, its grant's At); `inside` runs
-- inside fn (a clock second ticking there).
local function claimDay(Dx, p, streak, at, tokens, inside)
	local ok = Dx.MutateDaily(p, function(d)
		d.Streak = streak
		d.LastClaimAt = at
		d.Paid = math.max(d.Paid or 0, streak)
		if inside then
			inside()
		end
		return true
	end, { Kind = "Day", Tokens = tokens }, at)
	if ok then
		Dx.AddTokens(p, tokens)
	end
	return ok
end

-- DailyService's Z8 clamp: LastClaimAt rewritten to `at` with NO grant
local function clampDay(Dx, p, at)
	return Dx.MutateDaily(p, function(d)
		d.LastClaimAt = at
		return true
	end, nil, at)
end

-- the Sky Trove's Group ask on a copy of DataService (MarkTrove with its grant record, then the pay)
local function grantTrove(Dx, p)
	local ok = Dx.MarkTrove(p, "Group", { Cash = 2000, Tokens = 200 })
	if ok then
		Dx.AddCash(p, 2000)
		Dx.AddTokens(p, 200)
	end
	return ok
end

-- the star reward TycoonService.Prestige pays for star 1 (0 without TycoonCatalog)
local function starReward()
	local Cat = mod("TycoonCatalog")
	if type(Cat) == "table" and type(Cat.PrestigeGems) == "function" then
		local ok, gems = pcall(Cat.PrestigeGems, 1)
		if ok and type(gems) == "number" then
			return math.floor(gems)
		end
	end
	return 0
end

-- what TycoonService.Prestige writes through DataService: +1 star, Cash to 0, the star reward in Gems
local function prestige(Dx, p, reward)
	local before = Dx.GetHome(p)
	local ok = before ~= nil and Dx.MutateHome(p, function(h)
		h.Prestige = (h.Prestige or 0) + 1
		return true
	end)
	Dx.SpendCash(p, Dx.GetCash(p))
	if reward > 0 then
		Dx.AddGems(p, reward)
	end
	local after = Dx.GetHome(p)
	return ok == true and after ~= nil and after.Prestige == before.Prestige + 1 and Dx.GetCash(p) == 0
end

local function prestigeOf(rec)
	return type(rec) == "table" and type(rec.Home) == "table" and rec.Home.Prestige or 0
end

-- the Starter pack's grant on one copy of DataService (the writes StoreService.ApplyGrant makes in one non-yielding
-- step: the receipt, +1000 Cash, one Storm Tabby at Lv 5 through the add path, the grant record)
local function grantStarter(Dx, p, label)
	T.eq(Dx.MarkReceipt(p, ID_STARTER), true, label .. ": MarkReceipt answers true (a new receipt) on this server")
	Dx.AddCash(p, 1000)
	local profile = Dx.GetProfile(p)
	profile.Pets.storm_tabby = (profile.Pets.storm_tabby or 0) + 1
	Dx.MarkDirty(p)
	local level = Dx.GetPetLevel(p, "storm_tabby")
	T.check(Dx.SetPetLevel(p, "storm_tabby", math.max(level, 5)) == true, label .. ": the pack's Lv 5 is written (SetPetLevel(max(existing, Level)))")
	T.eq(Dx.NoteReceiptGrant(p, ID_STARTER, { Cash = 1000, Pets = { storm_tabby = 1 } }), true, label .. ": NoteReceiptGrant records what the receipt granted")
end

local function levelOf(rec, key)
	local entry = type(rec) == "table" and type(rec.PetLevels) == "table" and rec.PetLevels[key] or nil
	return type(entry) == "table" and entry.Level or nil
end

----------------------------------------------------------------------------------------------------
-- fixr_data_wrongclock_day (review finding 4; spec section 6 Daily row, Z8)
----------------------------------------------------------------------------------------------------
S.fixr_data_wrongclock_day = guarded("fixr_data_wrongclock_day", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local DSt = Mock.DataStore
	local Config = config()
	local daily = type(Config.Daily) == "table" and Config.Daily or {}
	local READY = daily.ReadySeconds or 72000
	local SLACK = daily.FutureClockSlack or 300
	local A, cloneA, releaseA = secondServer("DataServiceFixrClockA")
	local B, cloneB, releaseB = secondServer("DataServiceFixrClockB")
	if not T.check(A ~= nil and B ~= nil and type(B.MutateDaily) == "function", "wrong clock: two more copies of DataService load as 'server A' / 'server B'", tostring(cloneA) .. " / " .. tostring(cloneB)) then
		if releaseA then
			releaseA()
		end
		if releaseB then
			releaseB()
		end
		return
	end
	local saved = { Fail = DSt.Fail }
	local okRun, errRun = pcall(function()
		-- 1) A's clock runs 600 s ahead: its day-1 claim lands while B (loaded before it) claims day 1 too, 30 s later
		local uid = newUserId()
		local p = join("FixrClock", uid)
		D.AddTokens(p, 1)
		T.eq(D.Save(p), true, "wrong clock: (setup) the first save")
		A.Load(p)
		B.Load(p) -- both copies loaded before any claim
		advance(0.2)
		local tokens0 = (stored(uid) or {}).Tokens or 0
		local tFast = os.time() + 600
		T.check(tFast > os.time() + SLACK, "wrong clock: (precondition) 600 s ahead is past FutureClockSlack (" .. SLACK .. " s)")
		T.check(claimDay(A, p, 1, tFast, 50) and A.Save(p) == true, "wrong clock: server A (clock 600 s ahead) claims day 1 and saves")
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tFast and rec.Daily.Streak == 1 and rec.Tokens == tokens0 + 50,
			"wrong clock: (precondition) the store holds A's future claim (tFast, 1) and its 50 Tokens", dailyText(rec))
		advance(30)
		local tB = os.time()
		T.check(claimDay(B, p, 1, tB, 50) and B.Save(p) == true, "wrong clock: server B (its copy knew no claim) claims day 1 30 s later and saves")
		rec = stored(uid) or {}
		T.check(rec.Tokens == tokens0 + 50, "wrong clock: the day gift is paid ONCE (B's grant comes off by the twin rule; a wrong stored clock is no exception)",
			dailyText(rec) .. " (base Tokens " .. tokens0 .. ")")
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tFast and rec.Daily.Streak == 1 and rec.Daily.Paid == 1,
			"wrong clock: ...the stored pair stays A's (tFast, 1): B's claim was paid elsewhere", dailyText(rec) .. " tFast " .. tFast .. " tB " .. tB)
		advance(0.3)
		local bDaily = B.GetDaily(p)
		T.check(B.GetTokens(p) == tokens0 + 50 and bDaily ~= nil and bDaily.LastClaimAt == tFast, "wrong clock: ...and B adopted the store's balance and pair")
		-- B's Z8 clamp (no grant) takes the pair from the wrong clock; nothing is paid
		local tC = os.time()
		T.check(clampDay(B, p, tC) and B.Save(p) == true, "wrong clock: B clamps the future claim to now (no grant) and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tC and rec.Daily.Streak == 1 and rec.Tokens == tokens0 + 50,
			"wrong clock: the clamp lands (tC, 1), nothing paid", dailyText(rec) .. " tC " .. tC)
		leave(p)

		-- 2) a save whose Daily change never moved the pair (a play-time tick) leaves a wrong-clock stored pair alone
		local uid2 = newUserId()
		local q = join("FixrTick", uid2)
		D.AddTokens(q, 1)
		T.eq(D.Save(q), true, "wrong clock: (setup) the second player's first save")
		A.Load(q)
		B.Load(q)
		advance(0.2)
		local tFast2 = os.time() + 600
		T.check(claimDay(A, q, 1, tFast2, 50) and A.Save(q) == true, "wrong clock: A (clock 600 s ahead) claims day 1 and saves")
		local now2 = os.time()
		T.check(B.MutateDaily(q, function(d)
			d.PlayStart = now2
			d.PlaySec = 10
			return true
		end) and B.Save(q) == true, "wrong clock: B (loaded before) saves a play-time tick only (its pair untouched)")
		rec = stored(uid2) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tFast2 and rec.Daily.Streak == 1 and rec.Daily.PlayStart == now2,
			"wrong clock: the stored pair stays (tFast2, 1) (only a session that moved its pair takes it from a wrong clock); the tick's Play group lands",
			dailyText(rec) .. " PlayStart " .. tostring(type(rec.Daily) == "table" and rec.Daily.PlayStart))
		leave(q)

		-- 3) a session that SAW a far-future stored claim (its base holds it) clamps it, and claims 20 h later while
		--    the store still holds that clock: a new day, so its grant stays
		local uid3 = newUserId()
		local r = join("FixrFar", uid3)
		local tFar = os.time() + 30 * 3600
		DSt.Data[storeKey(uid3)] = {
			Version = 2, Tokens = 3, Pets = {}, Equipped = {}, Items = {}, Stats = statsOf(),
			Daily = { Streak = 2, Paid = 2, LastClaimAt = tFar, Weeks = 0, Pet = false, PlayStart = 0, PlaySec = 0, PlayClaimed = {} },
		}
		B.Load(r)
		advance(0.2)
		local rDaily = B.GetDaily(r)
		T.check(rDaily ~= nil and rDaily.LastClaimAt == tFar, "wrong clock: (precondition) B's copy loaded the far-future claim")
		T.check(clampDay(B, r, os.time()), "wrong clock: B clamps it (its clamp's save does not land)")
		advance(READY + 5)
		local t3 = os.time()
		T.check(t3 + SLACK < tFar, "wrong clock: (precondition) 20 h later the stored claim is still a wrong clock")
		T.check(claimDay(B, r, 3, t3, 50) and B.Save(r) == true, "wrong clock: B claims day 3 20 h after its clamp and saves")
		rec = stored(uid3) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == t3 and rec.Daily.Streak == 3 and rec.Tokens == 3 + 50,
			"wrong clock: the claim after the clamp keeps its 50 Tokens and takes the pair (t3, 3)", dailyText(rec) .. " t3 " .. t3)
		leave(r)
	end)
	DSt.Fail = saved.Fail
	advance(12)
	T.check(releaseA() == true and releaseB() == true, "wrong clock: servers A and B drop their hooks with them")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixr_data_wrongclock_day")
	K.flushWarnings("fixr_data_wrongclock_day", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixr_data_prestige_cash (review finding 9; the header's prestige rule for Cash + the twin rule)
----------------------------------------------------------------------------------------------------
S.fixr_data_prestige_cash = guarded("fixr_data_prestige_cash", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local DSt = Mock.DataStore
	local reward = starReward()
	local B, cloneB, releaseB = secondServer("DataServiceFixrStarB")
	if not T.check(B ~= nil and type(B.MarkTrove) == "function", "prestige cash: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	-- one round: the store at Prestige 0 with no ask; server A pays the Group ask before or after its prestige, earns
	-- 500, its saves fail and the player leaves (an orphan); server B (the same stale store) pays the ask again before
	-- or after its own prestige, earns 300 and saves; A's orphan retry lands last
	local function round(label, aAfter, bAfter, want, why)
		local uid = newUserId()
		local p = join("FixrStar", uid)
		D.AddTokens(p, 1)
		T.eq(D.Save(p), true, label .. ": (setup) the first save (Prestige 0, no ask)")
		local rec = stored(uid) or {}
		local tokens0, gems0 = rec.Tokens or 0, rec.Gems or 0
		local function side(Dx, after, earned)
			local ok = true
			if not after then
				ok = grantTrove(Dx, p) and ok
			end
			ok = prestige(Dx, p, reward) and ok
			if after then
				ok = grantTrove(Dx, p) and ok
			end
			Dx.AddCash(p, earned)
			return ok
		end
		T.check(side(D, aAfter, 500), label .. ": (setup) server A pays the ask " .. (aAfter and "after" or "before") .. " its prestige and earns 500")
		DSt.Fail = true
		T.eq(D.Save(p), false, label .. ": (server A, store failing) the save fails")
		leave(p)
		DSt.Fail = false
		rec = stored(uid) or {}
		T.check(prestigeOf(rec) == 0 and (rec.Trove == nil or rec.Trove.Group == nil), label .. ": (precondition) none of A's saves reached the store")
		B.Load(p)
		advance(0.2)
		T.check(side(B, bAfter, 300) and B.Save(p) == true, label .. ": server B pays the ask again " .. (bAfter and "after" or "before") .. " its own prestige, earns 300 and saves")
		rec = stored(uid) or {}
		T.check(prestigeOf(rec) == 1 and rec.Cash == 300 + (bAfter and 2000 or 0) and type(rec.Trove) == "table" and rec.Trove.Group == true,
			label .. ": (precondition) the store holds B's run (Prestige 1, Cash " .. (300 + (bAfter and 2000 or 0)) .. ", the ask)", "Cash " .. tostring(rec.Cash) .. " Prestige " .. tostring(prestigeOf(rec)))
		advance(25) -- A's orphan retry (10 s, then backoff)
		rec = stored(uid) or {}
		T.eq(rec.Cash, want, label .. ": " .. why)
		T.check(rec.Tokens == tokens0 + 200 and prestigeOf(rec) == 1 and rec.Gems == gems0 + reward,
			label .. ": ...Tokens +200 once, Prestige 1, the star reward once", "Tokens " .. tostring(rec.Tokens) .. " (base " .. tokens0 .. ") Gems " .. tostring(rec.Gems) .. " (base " .. gems0 .. " + " .. reward .. ")")
		advance(0.3)
	end
	local okRun, errRun = pcall(function()
		round("prestige cash (both paid before)", false, false, 800,
			"both prestiges reset both copies of the gift: the 500 + 300 earned since are kept (no copy is taken off a reset balance)")
		round("prestige cash (both paid after)", true, true, 2800,
			"both copies survived the prestiges: the gift counts once (2000) next to the 500 + 300 earned")
		round("prestige cash (A before, B after)", false, true, 2800,
			"A's copy went with A's prestige, the store's survived: the gift counts once next to the 500 + 300 earned")
		round("prestige cash (A after, B before)", true, false, 800,
			"the store's run paid the gift before its prestige (reset there): A's copy is the twin and comes off; the 500 + 300 earned are kept")
	end)
	DSt.Fail = false
	advance(12)
	T.check(releaseB() == true, "prestige cash: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixr_data_prestige_cash")
	K.flushWarnings("fixr_data_prestige_cash", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixr_data_petlevel (review finding 10; spec 5.4 GrantPet "SetPetLevel(max(existing, Level))")
----------------------------------------------------------------------------------------------------
S.fixr_data_petlevel = guarded("fixr_data_petlevel", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local DSt = Mock.DataStore
	local B, cloneB, releaseB = secondServer("DataServiceFixrLevelB")
	if not T.check(B ~= nil and type(B.SetPetLevel) == "function", "pet level: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	-- one round: A grants the Starter (Lv 5) and feeds to aLevel, its saves fail, the player leaves (an orphan); B
	-- grants the same receipt, feeds to bLevel and saves; A's orphan retry lands last
	local function round(label, aLevel, bLevel, want, why)
		local uid = newUserId()
		local p = join("FixrLevel", uid)
		D.AddTokens(p, 1)
		T.eq(D.Save(p), true, label .. ": (setup) the first save")
		local cash0 = (stored(uid) or {}).Cash or 0
		grantStarter(D, p, label .. " (server A)")
		D.AddTokens(p, 7) -- A's own Tokens: they show the orphan retry landed
		if aLevel > 5 then
			T.check(D.SetPetLevel(p, "storm_tabby", aLevel) == true, label .. ": (setup) A feeds the pet to Lv " .. aLevel)
		end
		DSt.Fail = true
		T.eq(D.Save(p), false, label .. ": (server A, store failing) the save fails")
		leave(p)
		DSt.Fail = false
		B.Load(p)
		advance(0.2)
		grantStarter(B, p, label .. " (server B)")
		T.check(B.SetPetLevel(p, "storm_tabby", bLevel) == true and B.Save(p) == true, label .. ": B feeds the pet to Lv " .. bLevel .. " and saves")
		local rec = stored(uid) or {}
		T.check(levelOf(rec, "storm_tabby") == bLevel and rec.Pets and rec.Pets.storm_tabby == 1 and rec.Tokens == 1, label .. ": (precondition) the store holds B's pet at Lv " .. bLevel .. " (A's Tokens not yet)")
		advance(25) -- A's orphan retry (10 s, then backoff)
		rec = stored(uid) or {}
		T.eq(levelOf(rec, "storm_tabby"), want, label .. ": " .. why)
		T.check(rec.Pets and rec.Pets.storm_tabby == 1 and rec.Cash == cash0 + 1000 and rec.Tokens == 1 + 7,
			label .. ": ...ONE pet copy and +1000 Cash once; A's 7 Tokens show the orphan retry landed",
			"pets " .. tostring(rec.Pets and rec.Pets.storm_tabby) .. " cash " .. tostring(rec.Cash) .. " (base " .. cash0 .. ") tokens " .. tostring(rec.Tokens))
	end
	local okRun, errRun = pcall(function()
		round("pet level (fed on B)", 5, 7, 7, "the store's Lv 7 stays (the twin's Lv 5 write never lowers it)")
		round("pet level (fed higher on A)", 9, 6, 9, "A's Lv 9 wins (the higher level per key)")
	end)
	DSt.Fail = false
	advance(12)
	T.check(releaseB() == true, "pet level: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixr_data_petlevel")
	K.flushWarnings("fixr_data_petlevel", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixr_data_daily_stamp (review findings 11 / 8: one clock per MutateDaily)
----------------------------------------------------------------------------------------------------
S.fixr_data_daily_stamp = guarded("fixr_data_daily_stamp", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local B, cloneB, releaseB = secondServer("DataServiceFixrStampB")
	if not T.check(B ~= nil and type(B.MutateDaily) == "function", "daily stamp: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	local okRun, errRun = pcall(function()
		local uid = newUserId()
		local p = join("FixrStamp", uid)
		D.AddTokens(p, 1)
		T.eq(D.Save(p), true, "daily stamp: (setup) the first save")
		B.Load(p) -- B loaded before A's claim
		advance(0.2)
		local tokens0 = (stored(uid) or {}).Tokens or 0
		local tA = os.time()
		T.check(claimDay(D, p, 1, tA, 50) and D.Save(p) == true, "daily stamp: A claims day 1 at tA and saves")
		advance(3600)
		-- B claims 1 h later (paid elsewhere); a clock second ticks between its fn and MutateDaily's stamp
		local tB = os.time()
		local ticked = false
		T.check(claimDay(B, p, 1, tB, 50, function()
			Mock.Clock.now = Mock.Clock.now + 1
			ticked = true
		end) and B.Save(p) == true, "daily stamp: B claims day 1 at tB (now = tB passed) while a second ticks inside fn, and saves")
		T.check(ticked and os.time() == tB + 1, "daily stamp: (precondition) the clock moved to tB + 1 inside the claim")
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tA and rec.Daily.Streak == 1 and rec.Tokens == tokens0 + 50,
			"daily stamp: the stored pair stays (tA, 1) and the 50 Tokens are paid once (B's grant At is its claim's now, so the dropped claim never wins the pair)",
			dailyText(rec) .. " tA " .. tA .. " tB " .. tB)
		advance(0.3)
		local bDaily = B.GetDaily(p)
		T.check(bDaily ~= nil and bDaily.LastClaimAt == tA and B.GetTokens(p) == tokens0 + 50, "daily stamp: ...and B adopted the store's pair and balance")

		-- without `now`: one os.time() read for the whole mutation
		local realTime = os.time
		local reads = 0
		local okCount, resCount = pcall(function()
			os.time = function(...)
				reads = reads + 1
				return realTime(...)
			end
			return D.MutateDaily(p, function(d)
				d.Weeks = d.Weeks
				return true
			end, { Kind = "Day", Tokens = 1 })
		end)
		os.time = realTime
		T.check(okCount and resCount == true and reads == 1, "daily stamp: without `now` MutateDaily reads os.time() once", "reads " .. reads .. " " .. tostring(resCount))
		-- a number in the grant's place is `now` (no grant): the old three-argument form keeps working
		local tN = os.time()
		T.check(D.MutateDaily(p, function(d)
			d.Weeks = d.Weeks
			return true
		end, tN) == true, "daily stamp: MutateDaily(player, fn, now) commits (a number is the clock, not a grant)")
		leave(p)
	end)
	advance(12)
	T.check(releaseB() == true, "daily stamp: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixr_data_daily_stamp")
	K.flushWarnings("fixr_data_daily_stamp", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixr_data_clamp_twin (re-review round 2, finding 1: a claim built on a session clamp keeps the twin rule)
----------------------------------------------------------------------------------------------------
S.fixr_data_clamp_twin = guarded("fixr_data_clamp_twin", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local DV = mod("DailyService")
	local DSt = Mock.DataStore
	local daily = type(config().Daily) == "table" and config().Daily or {}
	local READY = daily.ReadySeconds or 72000
	local SLACK = daily.FutureClockSlack or 300
	local C, cloneC, releaseC = secondServer("DataServiceFixrClampC")
	if not T.check(C ~= nil and type(C.MutateDaily) == "function" and type(DV) == "table" and type(DV.Claim) == "function",
		"clamp twin: a second copy of DataService loads as 'server C'; DailyService is booted", tostring(cloneC)) then
		if releaseC then
			releaseC()
		end
		return
	end
	local saved = { Fail = DSt.Fail }
	local okRun, errRun = pcall(function()
		-- the store: day 2 paid by a server whose clock ran 6 min fast (past the slack): F reads 6 min ahead here
		local uid = newUserId()
		local F = os.time() + SLACK + 60
		DSt.Data[storeKey(uid)] = {
			Version = 2, Tokens = 3, Gems = 5, Pets = {}, Equipped = {}, Items = {}, Stats = statsOf(),
			Daily = { Streak = 2, Paid = 2, LastClaimAt = F, Weeks = 0, Pet = false, PlayStart = 0, PlaySec = 0, PlayClaimed = {} },
		}
		-- server B (this one, with DailyService) loads it at T: the join's clamp counts from T for the session
		local p = join("FixrClamp", uid)
		local loaded = K.waitFor(function()
			return D.GetDaily(p) ~= nil
		end, 10)
		local T0 = os.time()
		local st = DV.State(p)
		T.check(loaded and st ~= nil and st.ReadyAt <= T0 + READY and D.GetDaily(p).LastClaimAt == F,
			"clamp twin: (precondition) B's clamp counts from the join (ReadyAt <= now + 20 h) while the record keeps F",
			st and ("ReadyAt - now " .. tostring(st.ReadyAt - T0)) or "no payload")
		-- 20 h after the join B pays day 3 (less than 20 h after F); then its saves fail and the player leaves
		advance(READY + 2)
		local gemsB = D.GetGems(p)
		local tB = os.time()
		local ok, info = DV.Claim(p)
		T.check(ok == true and type(info) == "table" and info.Streak == 3 and D.GetGems(p) == gemsB + 10 and tB - F < READY,
			"clamp twin: B claims day 3 (+10 Gems) 20 h after the join, " .. tostring(tB - F) .. " s after F", tostring(ok) .. " " .. tostring(type(info) == "table" and info.Streak or info))
		D.AddTokens(p, 7) -- B's own Tokens: they show the orphan retry landed
		DSt.Fail = true
		T.eq(D.Save(p), false, "clamp twin: (server B, store failing) the save fails")
		leave(p)
		advance(400) -- B's orphan retries at 10 .. 390 s fail too; the next is at 510 s
		DSt.Fail = false
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == F and rec.Daily.Streak == 2 and rec.Gems == 5 and rec.Tokens == 3,
			"clamp twin: (precondition) none of B's saves reached the store", dailyText(rec) .. " Gems " .. tostring(rec.Gems))
		-- server C loads the stale (F, 2) and pays day 3 again, at F + 20 h, and saves before B's retry
		C.Load(p)
		advance(0.2)
		local tC = os.time()
		T.check(tC - F >= READY, "clamp twin: (precondition) C's claim is a full 20 h after F")
		local okC = C.MutateDaily(p, function(d)
			d.Streak = 3
			d.Paid = math.max(d.Paid or 0, 3)
			d.LastClaimAt = tC
			return true
		end, { Kind = "Day", Gems = 10 }, tC)
		if okC then
			C.AddGems(p, 10)
		end
		T.check(okC and C.Save(p) == true, "clamp twin: server C (the stale F) pays day 3 again and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tC and rec.Daily.Streak == 3 and rec.Gems == 15,
			"clamp twin: (precondition) the store holds C's pair (tC, 3) and +10 Gems", dailyText(rec) .. " Gems " .. tostring(rec.Gems))
		advance(130) -- B's orphan retry lands last
		rec = stored(uid) or {}
		T.eq(rec.Tokens, 3 + 7, "clamp twin: B's orphan retry landed (its 7 Tokens)")
		T.check(rec.Gems == 15, "clamp twin: day 3 is paid ONCE: B's clamp claim (less than 20 h after F, but after C's stored claim) is the twin and comes off",
			"Gems " .. tostring(rec.Gems) .. " (5 + 10 once = 15)")
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tC and rec.Daily.Streak == 3 and rec.Daily.Paid == 3,
			"clamp twin: ...the stored pair stays C's (tC, 3), Paid 3", dailyText(rec) .. " tC " .. tC .. " tB " .. tB)
		advance(0.3)
	end)
	DSt.Fail = saved.Fail
	advance(12)
	T.check(releaseC() == true, "clamp twin: server C's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixr_data_clamp_twin")
	K.flushWarnings("fixr_data_clamp_twin", { "[DataService]", "[DailyService]", "[TycoonService]", "[PetCareService]", "[SpotService]" })
end)

----------------------------------------------------------------------------------------------------
-- fixr_data_revert_twin (re-review round 3, findings 1 / 4: a save that never moved its pair never takes it)
----------------------------------------------------------------------------------------------------
S.fixr_data_revert_twin = guarded("fixr_data_revert_twin", function()
	if not K.needBoot() then
		return
	end
	local DSt = Mock.DataStore
	local U, cloneU, releaseU = secondServer("DataServiceFixrRevertU")
	local V, cloneV, releaseV = secondServer("DataServiceFixrRevertT")
	local W, cloneW, releaseW = secondServer("DataServiceFixrRevertS")
	if not T.check(U ~= nil and V ~= nil and W ~= nil and type(U.MutateDaily) == "function",
		"revert twin: three more copies of DataService load as 'server U' / 'server T' / 'server S'", tostring(cloneU) .. " / " .. tostring(cloneV) .. " / " .. tostring(cloneW)) then
		for _, release in ipairs({ releaseU, releaseV, releaseW }) do
			if release then
				release()
			end
		end
		return
	end
	local function record(daily0)
		return { Version = 2, Tokens = 3, Pets = {}, Equipped = {}, Items = {}, Stats = statsOf(), Daily = daily0 }
	end
	local okRun, errRun = pcall(function()
		-- 1) the store holds F, 30 h ahead (a fast server's day-2 claim). U and S load it; U only ticks play time and
		--    saves late; T loads it and pays day 3 at tT (< F) first (finding 1)
		local uid = newUserId()
		local p = join("FixrRevert", uid)
		local F = os.time() + 30 * 3600
		DSt.Data[storeKey(uid)] = record({ Streak = 2, Paid = 2, LastClaimAt = F, Weeks = 0, Pet = false, PlayStart = 0, PlaySec = 0, PlayClaimed = {} })
		U.Load(p)
		W.Load(p)
		advance(0.2)
		T.check(U.GetDaily(p) ~= nil and U.GetDaily(p).LastClaimAt == F and W.GetDaily(p) ~= nil and W.GetDaily(p).LastClaimAt == F,
			"revert twin: (precondition) servers U and S loaded the stamp F, 30 h ahead")
		local tick = os.time()
		T.check(U.MutateDaily(p, function(d)
			d.PlayStart = tick
			d.PlaySec = 10
			return true
		end), "revert twin: server U counts play time only (its pair untouched, not saved yet)")
		V.Load(p)
		advance(0.2)
		local tT = os.time()
		T.check(claimDay(V, p, 3, tT, 10) and V.Save(p) == true, "revert twin: server T pays day 3 at tT (before F) and saves")
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tT and rec.Daily.Streak == 3 and rec.Daily.Paid == 3 and rec.Tokens == 13,
			"revert twin: (precondition) the store holds T's pair (tT, 3), Paid 3, +10 Tokens", dailyText(rec))
		T.eq(U.Save(p), true, "revert twin: server U's late save lands")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tT and rec.Daily.Streak == 3 and rec.Daily.Paid == 3 and rec.Daily.PlayStart == tick,
			"revert twin: a save that never moved its pair leaves T's claim (tT, 3) in the store (it never puts F back); its play time lands",
			dailyText(rec) .. " tT " .. tT .. " F " .. F)
		advance(5)
		local tS = os.time()
		T.check(claimDay(W, p, 3, tS, 10) and W.Save(p) == true, "revert twin: server S (it loaded F before T's claim) pays day 3 again and saves")
		rec = stored(uid) or {}
		T.check(rec.Tokens == 13, "revert twin: day 3 is paid ONCE: S's claim built on F, and F is no longer the stored stamp",
			"Tokens " .. tostring(rec.Tokens) .. " (3 + 10 once = 13)")
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tT and rec.Daily.Streak == 3 and rec.Daily.Paid == 3,
			"revert twin: ...the stored pair stays T's (tT, 3)", dailyText(rec) .. " tS " .. tS)
		leave(p)

		-- 2) a first sight noted on server U (ClampFrom / ClampAt, no claim) lands; U's later save carries only play time
		--    and lands after server T's claim built on that stamp: the claim stays (finding 4)
		local uid2 = newUserId()
		local q = join("FixrRevertB", uid2)
		local F2 = os.time() + 3 * 86400
		DSt.Data[storeKey(uid2)] = record({ Streak = 4, Paid = 4, LastClaimAt = F2, Weeks = 0, Pet = false, PlayStart = 0, PlaySec = 0, PlayClaimed = {} })
		U.Load(q)
		advance(0.2)
		local b0 = os.time()
		T.check(U.MutateDaily(q, function(d)
			d.ClampFrom = F2
			d.ClampAt = b0
			return true
		end) and U.Save(q) == true, "revert twin: server U notes its first sight of F2 (3 days ahead) and saves")
		rec = stored(uid2) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == F2 and rec.Daily.ClampFrom == F2 and rec.Daily.ClampAt == b0,
			"revert twin: (precondition) the store holds F2 and U's first sight of it", dailyText(rec))
		local tick2 = os.time()
		T.check(U.MutateDaily(q, function(d)
			d.PlayStart = tick2
			d.PlaySec = 10
			return true
		end), "revert twin: server U counts play time (not saved yet)")
		V.Load(q)
		advance(0.2)
		local tC = os.time()
		T.check(claimDay(V, q, 5, tC, 10) and V.Save(q) == true, "revert twin: server T pays day 5 at tC (before F2) and saves")
		rec = stored(uid2) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tC and rec.Daily.Streak == 5 and (rec.Daily.ClampFrom or 0) == 0,
			"revert twin: (precondition) the store holds T's pair (tC, 5) and no first sight", dailyText(rec))
		T.eq(U.Save(q), true, "revert twin: server U's late save lands")
		rec = stored(uid2) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tC and rec.Daily.Streak == 5 and rec.Daily.Paid == 5
			and (rec.Daily.ClampFrom or 0) == 0 and (rec.Daily.ClampAt or 0) == 0 and rec.Tokens == 13,
			"revert twin: ...the store keeps T's claim (tC, 5), Paid 5, and no first sight of F2 (the next claim is no repair)",
			dailyText(rec) .. " ClampFrom " .. tostring(type(rec.Daily) == "table" and rec.Daily.ClampFrom) .. " tC " .. tC)
		leave(q)
	end)
	advance(12)
	T.check(releaseU() == true and releaseV() == true and releaseW() == true, "revert twin: servers U, T and S drop their hooks with them")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixr_data_revert_twin")
	K.flushWarnings("fixr_data_revert_twin", { "[DataService]", "[DailyService]", "[TycoonService]", "[PetCareService]", "[SpotService]" })
end)

return S
