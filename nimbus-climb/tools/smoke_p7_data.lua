-- smoke_p7_data.lua: the Robux Store data layer (docs/superpowers/specs/2026-11-04-shop-retention-design.md section 6;
-- plan docs/superpowers/plans/2026-11-04-store.md Task 5, W1-data): DataService's helper table P7 (the Store / Daily /
-- Trove fields, their cross-server merges and the receipt-grant twin rule), the provisional refusals and the dev reset.
-- Server world only, booted (DataStores on).
--   p7data_fields       the defaults on a new profile; MarkBought once; AddBoost from now, stacking in TIME onto a running
--                       potion, restarting from now once expired; MarkPassSeen; MutateDaily commits (GetDaily copies) and
--                       rolls back on an error; MarkTrove once; the stored record (PlayClaimed a dense boolean array,
--                       Version 2); an untouched profile stores no Store / Daily / Trove key
--   p7data_store_merge  the Starter pack across servers (the fixsrv_receipt_merge shape): A marks + grants, its save
--                       FAILS, the player leaves (an orphan); B grants the SAME purchase id and saves; A's orphan retry
--                       lands: ONE pet copy, +1000 Cash once, one potion hour, Bought once, the receipt stored
--   p7data_daily_merge  the (LastClaimAt, Streak) pair across servers: a claim less than ReadySeconds after the STORED
--                       claim was paid elsewhere (its grant dropped, the stored pair stays); a later claim wins the pair
--                       and keeps its grant; the Play group: a tier claimed on both servers pays once, PlaySec adds up at
--                       the same PlayStart; a stand-in save never touches the stored Play group
--   p7data_trove_merge  one Trove ask granted on two servers pays once (union + the twin rule)
--   p7data_provisional  a profile whose load failed (the store reachable) refuses MarkBought / AddBoost / MutateDaily /
--                       MarkTrove / NoteReceiptGrant (false), MarkReceipt (nil), GetStore / GetDaily / GetTrove (nil);
--                       MarkPassSeen (a union) is allowed; after the recovery GetStore answers the stored Store
--   p7data_reset        the developer /reset wipes Daily and Trove (absent in the store after the save) and keeps
--                       Store.Bought (Robux)
-- White-box: the booted helpers of smoke_fix_server.lua; "server B" is a second copy of DataService against the same mock
-- store (the smoke_p5_data.lua secondServer shape). Plain Lua 5.1 syntax only.

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
local ID_STARTER = "p7-starter-1"

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local function DS()
	return mod("DataService")
end

local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 984100 + userSeq
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

local function count(map)
	local n = 0
	for _ in pairs(type(map) == "table" and map or {}) do
		n = n + 1
	end
	return n
end

local function provisional(D, p)
	return type(D.IsProvisional) == "function" and D.IsProvisional(p) == true
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

-- the Starter pack's grant on one server's copy of DataService (the five writes StoreService.ApplyGrant makes, in one
-- non-yielding step): the receipt, +1000 Cash, one Storm Tabby (the add path), one potion hour, Bought.Starter and
-- the grant record. Returns the potion's end.
local function grantStarter(D, p)
	T.eq(D.MarkReceipt(p, ID_STARTER), true, "p7 store merge: MarkReceipt answers true (a new receipt) on this server")
	D.AddCash(p, 1000)
	local profile = D.GetProfile(p)
	profile.Pets.storm_tabby = (profile.Pets.storm_tabby or 0) + 1
	D.MarkDirty(p)
	local okBoost, ends = D.AddBoost(p, "XpPotion", 3600)
	T.check(okBoost == true and ends == os.time() + 3600, "p7 store merge: AddBoost grants one potion hour from now")
	T.eq(D.MarkBought(p, "Starter"), true, "p7 store merge: MarkBought Starter")
	T.eq(D.NoteReceiptGrant(p, ID_STARTER, { Cash = 1000, Pets = { storm_tabby = 1 }, Boost = { XpPotion = 3600 } }), true,
		"p7 store merge: NoteReceiptGrant records what the receipt granted")
	return ends
end

----------------------------------------------------------------------------------------------------
-- p7data_fields
----------------------------------------------------------------------------------------------------
S.p7data_fields = guarded("p7data_fields", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local uid = newUserId()
	local p = join("P7Fields", uid)
	K.waitFor(function()
		return D.GetProfile(p) ~= nil
	end, 10)
	local prof = D.GetProfile(p)
	if not T.check(prof ~= nil, "p7 fields: (precondition) the profile loaded") then
		return
	end
	T.check(type(prof.Store) == "table" and type(prof.Store.Bought) == "table" and type(prof.Daily) == "table" and prof.Daily.Streak == 0 and prof.Daily.Pet == false and type(prof.Trove) == "table",
		"p7 fields: defaults on a new profile")
	T.check(type(D.MarkBought) == "function" and D.MarkBought(p, "Starter") == true and D.MarkBought(p, "Starter") == false and D.GetStore(p).Bought.Starter == os.time(),
		"p7 fields: MarkBought once")
	T.check(D.MarkBought(p, "") == false and D.MarkBought(p, 12) == false and D.MarkBought(nil, "Starter") == false, "p7 fields: MarkBought refuses junk keys and no player")
	local okB, ends = D.AddBoost(p, "XpPotion", 3600)
	T.check(okB and ends == os.time() + 3600, "p7 fields: AddBoost from now")
	advance(600)
	local _, ends2 = D.AddBoost(p, "XpPotion", 3600)
	T.eq(ends2, ends + 3600, "p7 fields: a second potion stacks in TIME onto the running one")
	advance(8000)
	local _, ends3 = D.AddBoost(p, "XpPotion", 60)
	T.eq(ends3, os.time() + 60, "p7 fields: an expired potion restarts from now")
	T.check(D.AddBoost(p, "XpPotion", 0) == false and D.AddBoost(p, "XpPotion", -5) == false and D.AddBoost(p, "", 60) == false, "p7 fields: AddBoost refuses junk seconds / keys")
	T.check(D.MarkPassSeen(p, "VIP") and D.GetStore(p).Passes.VIP ~= nil, "p7 fields: MarkPassSeen")
	local copy = D.GetStore(p)
	copy.Bought.Starter = nil
	T.check(D.GetStore(p).Bought.Starter ~= nil, "p7 fields: GetStore answers a copy (editing it changes nothing)")
	T.check(D.MutateDaily(p, function(d)
		d.Streak = 3
		d.LastClaimAt = os.time()
		d.PlayClaimed[2] = true
		return true
	end, { Kind = "Day", Tokens = 50 }) == true and D.GetDaily(p).Streak == 3 and D.GetDaily(p).PlayClaimed[2] == true, "p7 fields: MutateDaily commits and GetDaily copies")
	T.check(D.MutateDaily(p, function(d)
		d.Streak = 99
		error("boom")
	end) == false and D.GetDaily(p).Streak == 3, "p7 fields: an error inside fn rolls the Daily back")
	T.check(D.MutateDaily(p, function(d)
		d.Streak = 77
		return false
	end) == false and D.GetDaily(p).Streak == 3, "p7 fields: fn returning false rolls the Daily back too")
	T.check(D.MutateDaily(p, function(d)
		d.Streak = -4
		d.Pet = "yes"
		d.PlayClaimed[99] = true
		return true
	end) == true and D.GetDaily(p).Streak == 0 and D.GetDaily(p).Pet == false and D.GetDaily(p).PlayClaimed[99] == nil and D.GetDaily(p).PlayClaimed[2] == true,
		"p7 fields: the committed Daily is sanitised in place (whole numbers >= 0, Pet a boolean, tiers 1..16)")
	T.check(D.MutateDaily(p, function(d)
		d.Streak = 3
		return true
	end) == true, "p7 fields: (setup) Streak back to 3")
	T.check(D.MarkTrove(p, "Group", { Cash = 2000, Tokens = 200 }) == true and D.MarkTrove(p, "Group", {}) == false and D.GetTrove(p).Group == true, "p7 fields: MarkTrove once")
	T.eq(D.Save(p), true, "p7 fields: the profile saves")
	local rec = stored(uid)
	T.check(type(rec) == "table" and type(rec.Store) == "table" and rec.Store.Bought.Starter ~= nil and rec.Store.Boosts.XpPotion == ends3 and type(rec.Daily) == "table" and rec.Daily.Streak == 3
		and rec.Daily.PlayClaimed[2] == true and rec.Daily.PlayClaimed[1] == false and type(rec.Trove) == "table" and rec.Trove.Group == true,
		"p7 fields: stored as written; PlayClaimed a dense boolean array")
	T.check(rec and rec.Version == 2, "p7 fields: Version stays 2")
	T.check(rec and rec.Store.Passes.VIP ~= nil, "p7 fields: the pass seen is stored")
	-- the next save without a change writes nothing new (the delta is empty: the clean forms agree with the store)
	local writes = Mock.DataStore.Writes
	T.check(D.Save(p) == true and Mock.DataStore.Writes == writes, "p7 fields: a second save without a change writes nothing (the delta is empty)")
	-- a rejoin reads the record back in the live shape (PlayClaimed a set, Pet a boolean)
	leave(p)
	local back = join("P7Fields", uid)
	local daily = D.GetDaily(back)
	local store = D.GetStore(back)
	T.check(daily ~= nil and daily.Streak == 3 and daily.PlayClaimed[2] == true and daily.PlayClaimed[1] == nil and daily.Pet == false
		and store ~= nil and store.Bought.Starter ~= nil and store.Boosts.XpPotion == ends3 and D.GetTrove(back).Group == true,
		"p7 fields: a rejoin reads the stored record back (PlayClaimed a set again)")
	leave(back)

	-- an untouched new profile saved: the stored record has no Store / Daily / Trove keys (left out while default)
	local uid2 = newUserId()
	local q = join("P7Plain", uid2)
	D.AddTokens(q, 1)
	T.eq(D.Save(q), true, "p7 fields: an untouched profile saves")
	local rec2 = stored(uid2)
	T.check(type(rec2) == "table" and rec2.Store == nil and rec2.Daily == nil and rec2.Trove == nil, "p7 fields: ...without Store / Daily / Trove keys (left out while default)")
	leave(q)
	K.flushErrors("p7data_fields")
	K.flushWarnings("p7data_fields", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p7data_store_merge
----------------------------------------------------------------------------------------------------
S.p7data_store_merge = guarded("p7data_store_merge", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local DSt = Mock.DataStore
	local B, cloneB, releaseB = secondServer("DataServiceP7StoreB")
	if not T.check(B ~= nil and type(B.MarkBought) == "function", "p7 store merge: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	local saved = { Studio = Mock.Options.Studio, Fail = DSt.Fail }
	local okRun, errRun = pcall(function()
		Mock.Options.Studio = false
		local uid = newUserId()
		local p = join("P7StoreA", uid)
		D.AddTokens(p, 1)
		T.eq(D.Save(p), true, "p7 store merge: (setup) the player's first save")
		local before = (stored(uid) or {}).Cash or 0
		-- server A grants the Starter pack; its save fails; the player leaves (the leave save fails too: an orphan)
		local aEnds = grantStarter(D, p)
		DSt.Fail = true
		T.eq(D.Save(p), false, "p7 store merge: (server A, store failing) the save fails")
		leave(p)
		DSt.Fail = false
		local rec = stored(uid) or {}
		T.check((rec.Cash or 0) == before and (type(rec.GemReceipts) ~= "table" or rec.GemReceipts[ID_STARTER] == nil) and rec.Store == nil,
			"p7 store merge: (precondition) none of A's saves reached the store")
		-- server B: the player rejoins there, Roblox re-sends the receipt, B grants and saves
		B.Load(p)
		advance(0.2)
		local bEnds = grantStarter(B, p)
		T.check(bEnds >= aEnds, "p7 store merge: (precondition) B's potion ends no earlier than A's")
		T.eq(B.Save(p), true, "p7 store merge: server B saves its grant")
		rec = stored(uid) or {}
		T.check(rec.Pets and rec.Pets.storm_tabby == 1 and rec.Cash == before + 1000 and rec.Store and rec.Store.Boosts.XpPotion == bEnds and rec.Store.Bought.Starter ~= nil
			and type(rec.GemReceipts) == "table" and rec.GemReceipts[ID_STARTER] ~= nil, "p7 store merge: the store holds B's grant once")
		-- A's orphan retry (10 s, then backoff) lands on top
		advance(25)
		rec = stored(uid) or {}
		T.check(rec.Pets and rec.Pets.storm_tabby == 1 and rec.Cash == before + 1000 and rec.Store and rec.Store.Boosts.XpPotion <= bEnds and rec.Store.Bought.Starter ~= nil,
			"p7 store merge: ONE pet copy, +1000 Cash once, one potion hour, Bought once after the orphan retry",
			"pets " .. tostring(rec.Pets and rec.Pets.storm_tabby) .. " cash " .. tostring(rec.Cash) .. " (before " .. before .. ") potion " .. tostring(rec.Store and rec.Store.Boosts.XpPotion) .. " vs " .. tostring(bEnds))
		T.check(type(rec.GemReceipts) == "table" and rec.GemReceipts[ID_STARTER] ~= nil, "p7 store merge: ...the receipt stays stored")
		T.check(rec.Tokens == 1, "p7 store merge: ...A's token is stored (the orphan retry did land)", tostring(rec.Tokens))

		-- the other order: B loaded before A's save with the same receipt landed; the re-sent receipt on B says "new",
		-- but B's save finds it in the store: nothing is added again and B's balance follows the store
		local uid2 = newUserId()
		local q = join("P7StoreC", uid2)
		D.AddTokens(q, 1)
		T.eq(D.Save(q), true, "p7 store merge: (setup) the second player's first save")
		B.Load(q)
		local before2 = (stored(uid2) or {}).Cash or 0
		grantStarter(D, q)
		T.eq(D.Save(q), true, "p7 store merge: A grants and saves first")
		grantStarter(B, q)
		T.eq(B.Save(q), true, "p7 store merge: B (loaded before A's save) grants the same receipt and saves")
		local rec2 = stored(uid2) or {}
		T.check(rec2.Pets and rec2.Pets.storm_tabby == 1 and rec2.Cash == before2 + 1000 and rec2.Store and rec2.Store.Bought.Starter ~= nil,
			"p7 store merge: the stale copy's save adds nothing (one pet, +1000 Cash once, Bought once)",
			"pets " .. tostring(rec2.Pets and rec2.Pets.storm_tabby) .. " cash " .. tostring(rec2.Cash) .. " (before " .. before2 .. ")")
		advance(0.3)
		T.check(B.GetCash(q) == before2 + 1000 and B.GetProfile(q).Pets.storm_tabby == 1, "p7 store merge: ...and B's live balance follows the store")
		leave(q)
	end)
	Mock.Options.Studio = saved.Studio
	DSt.Fail = saved.Fail
	advance(12)
	T.check(releaseB() == true, "p7 store merge: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p7data_store_merge")
	K.flushWarnings("p7data_store_merge", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p7data_daily_merge
----------------------------------------------------------------------------------------------------
S.p7data_daily_merge = guarded("p7data_daily_merge", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local DSt = Mock.DataStore
	local Config = config()
	local READY = (type(Config.Daily) == "table" and Config.Daily.ReadySeconds) or 72000
	local B, cloneB, releaseB = secondServer("DataServiceP7DailyB")
	if not T.check(B ~= nil and type(B.MutateDaily) == "function", "p7 daily merge: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	local function claim(Dx, p, streak, at, tokens)
		local ok = Dx.MutateDaily(p, function(d)
			d.Streak = streak
			d.LastClaimAt = at
			return true
		end, { Kind = "Day", Tokens = tokens })
		if ok then
			Dx.AddTokens(p, tokens)
		end
		return ok
	end
	local function claimPlay(Dx, p, start, sec, tier, cash)
		local ok = Dx.MutateDaily(p, function(d)
			d.PlayStart = start
			d.PlaySec = sec
			d.PlayClaimed[tier] = true
			return true
		end, { Kind = "Play", Tier = tier, Cash = cash })
		if ok then
			Dx.AddCash(p, cash)
		end
		return ok
	end
	local okRun, errRun = pcall(function()
		local uid = newUserId()
		local p = join("P7DailyA", uid)
		D.AddTokens(p, 1)
		T.eq(D.Save(p), true, "p7 daily merge: (setup) the first save")
		B.Load(p) -- B loaded before A's claim
		local tokens0 = (stored(uid) or {}).Tokens or 0
		local tA = os.time()
		T.check(claim(D, p, 1, tA, 50) and D.Save(p) == true, "p7 daily merge: A claims day 1 (Streak 1, LastClaimAt tA, 50 Tokens) and saves")
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tA and rec.Daily.Streak == 1 and rec.Tokens == tokens0 + 50, "p7 daily merge: the store holds (tA, 1) and the 50 Tokens")
		-- B claims 1 h later: less than ReadySeconds after the STORED claim, so it was paid elsewhere
		advance(3600)
		local tB = os.time()
		T.check(claim(B, p, 1, tB, 50) and B.Save(p) == true, "p7 daily merge: B claims 1 h later (its copy knew no claim) and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tA and rec.Daily.Streak == 1 and rec.Tokens == tokens0 + 50,
			"p7 daily merge: the stored pair stays (tA, 1) and the 50 Tokens are paid once (B's grant dropped)",
			"LastClaimAt " .. tostring(rec.Daily and rec.Daily.LastClaimAt) .. " vs tA " .. tA .. ", Streak " .. tostring(rec.Daily and rec.Daily.Streak) .. ", Tokens " .. tostring(rec.Tokens) .. " (base " .. tokens0 .. ")")
		advance(0.3)
		local bDaily = B.GetDaily(p)
		T.check(bDaily ~= nil and bDaily.LastClaimAt == tA and bDaily.Streak == 1 and B.GetTokens(p) == tokens0 + 50, "p7 daily merge: B adopted the store's pair and balance")
		-- B claims 21 h after tA: ready; the higher LastClaimAt wins the pair and the grant stays
		advance(READY)
		local tC = os.time()
		T.check(tC - tA >= READY, "p7 daily merge: (precondition) 21 h passed since tA")
		T.check(claim(B, p, 2, tC, 50) and B.Save(p) == true, "p7 daily merge: B claims day 2 at tC and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tC and rec.Daily.Streak == 2 and rec.Tokens == tokens0 + 100,
			"p7 daily merge: the stored pair is B's (tC, 2) and the Tokens are +50 more",
			"LastClaimAt " .. tostring(rec.Daily and rec.Daily.LastClaimAt) .. " vs tC " .. tC .. ", Streak " .. tostring(rec.Daily and rec.Daily.Streak) .. ", Tokens " .. tostring(rec.Tokens))
		T.check(B.Save(p) == true and (stored(uid) or {}).Tokens == tokens0 + 100, "p7 daily merge: an empty save of B changes nothing")

		-- the Play group: A (its copy still at (tA, 1), PlayStart 0) claims tier 1 at PlayStart P and saves; B (same P)
		-- claims tier 1 too and saves: Cash +200 once, PlayClaimed[1] true, PlaySec 300 + 120
		local P = os.time()
		local cash0 = (stored(uid) or {}).Cash or 0
		T.check(claimPlay(D, p, P, 300, 1, 200) and D.Save(p) == true, "p7 daily merge: A claims play tier 1 (PlayStart P, 300 s) and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.PlayStart == P and rec.Daily.PlaySec == 300 and rec.Daily.PlayClaimed[1] == true and rec.Cash == cash0 + 200
			and rec.Daily.LastClaimAt == tC and rec.Daily.Streak == 2,
			"p7 daily merge: the store holds A's Play group (+200 Cash) and still B's pair (A's older pair did not win)",
			"PlayStart " .. tostring(rec.Daily and rec.Daily.PlayStart) .. " PlaySec " .. tostring(rec.Daily and rec.Daily.PlaySec) .. " Cash " .. tostring(rec.Cash) .. " pair " .. tostring(rec.Daily and rec.Daily.LastClaimAt) .. "/" .. tostring(rec.Daily and rec.Daily.Streak))
		T.check(claimPlay(B, p, P, 120, 1, 200) and B.Save(p) == true, "p7 daily merge: B claims tier 1 at the same PlayStart (120 s) and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.PlayStart == P and rec.Daily.PlaySec == 420 and rec.Daily.PlayClaimed[1] == true and rec.Cash == cash0 + 200,
			"p7 daily merge: Cash +200 once, PlayClaimed[1] true, PlaySec 300 + 120 = 420",
			"PlaySec " .. tostring(rec.Daily and rec.Daily.PlaySec) .. " Cash " .. tostring(rec.Cash) .. " (base " .. cash0 .. ")")
		advance(0.3)
		T.check(B.GetCash(p) == cash0 + 200 and B.GetDaily(p).PlaySec == 420, "p7 daily merge: B adopted the merged Play group and balance")
		-- a newer play-day on B wins the whole group
		advance(Config.Daily.Play.DaySeconds + 60)
		local P2 = os.time()
		T.check(claimPlay(B, p, P2, 30, 1, 200) and B.Save(p) == true, "p7 daily merge: B starts a new play-day (PlayStart P2) and claims tier 1 again")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.PlayStart == P2 and rec.Daily.PlaySec == 30 and rec.Daily.PlayClaimed[1] == true and rec.Cash == cash0 + 400,
			"p7 daily merge: the higher PlayStart wins the whole Play group (30 s, tier 1 of the new day paid)",
			"PlayStart " .. tostring(rec.Daily and rec.Daily.PlayStart) .. " PlaySec " .. tostring(rec.Daily and rec.Daily.PlaySec) .. " Cash " .. tostring(rec.Cash))
		leave(p)

		-- a stand-in save (B provisional, PlayStart = now in its stand-in) never touches the stored Play group
		local uid2 = newUserId()
		DSt.Data[storeKey(uid2)] = {
			Version = 2, Tokens = 3, Pets = {}, Equipped = {}, Items = {}, Stats = statsOf(),
			Daily = { Streak = 2, Paid = 2, LastClaimAt = tC, Weeks = 0, Pet = false, PlayStart = P, PlaySec = 420, PlayClaimed = { true } },
		}
		local q = join("P7DailyQ", uid2)
		DSt.Fail = true
		B.Load(q)
		advance(0.5)
		T.check(provisional(B, q) and B.GetDaily(q) == nil and B.MutateDaily(q, function(d)
			d.PlayStart = os.time()
			return true
		end) == false, "p7 daily merge: B's copy loads provisionally (the store down): GetDaily nil, MutateDaily refused")
		local standIn = B.GetProfile(q)
		standIn.Daily.PlayStart = os.time()
		standIn.Daily.PlaySec = 50
		standIn.Daily.Streak = 1
		B.MarkDirty(q)
		DSt.Fail = false
		T.eq(B.Save(q), true, "p7 daily merge: B's save recovers the real record first and lands")
		rec = stored(uid2) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.PlayStart == P and rec.Daily.PlaySec == 420 and rec.Daily.PlayClaimed[1] == true and rec.Daily.Streak == 2 and rec.Daily.LastClaimAt == tC,
			"p7 daily merge: the stand-in's Play group and pair never reached the store",
			"PlayStart " .. tostring(rec.Daily and rec.Daily.PlayStart) .. " PlaySec " .. tostring(rec.Daily and rec.Daily.PlaySec) .. " Streak " .. tostring(rec.Daily and rec.Daily.Streak))
		local qDaily = B.GetDaily(q)
		T.check(qDaily ~= nil and qDaily.PlayStart == P and qDaily.PlaySec == 420, "p7 daily merge: ...and B's live Daily is the stored one now")
		leave(q)
	end)
	DSt.Fail = false
	advance(12)
	T.check(releaseB() == true, "p7 daily merge: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p7data_daily_merge")
	K.flushWarnings("p7data_daily_merge", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p7data_trove_merge
----------------------------------------------------------------------------------------------------
S.p7data_trove_merge = guarded("p7data_trove_merge", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local B, cloneB, releaseB = secondServer("DataServiceP7TroveB")
	if not T.check(B ~= nil and type(B.MarkTrove) == "function", "p7 trove merge: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	local function grantTrove(Dx, p)
		local ok = Dx.MarkTrove(p, "Group", { Cash = 2000, Tokens = 200 })
		if ok then
			Dx.AddCash(p, 2000)
			Dx.AddTokens(p, 200)
		end
		return ok
	end
	local okRun, errRun = pcall(function()
		local uid = newUserId()
		local p = join("P7TroveA", uid)
		D.AddTokens(p, 1)
		T.eq(D.Save(p), true, "p7 trove merge: (setup) the first save")
		B.Load(p) -- loaded before A's grant
		local rec = stored(uid) or {}
		local cash0, tokens0 = rec.Cash or 0, rec.Tokens or 0
		T.check(grantTrove(D, p) == true and D.Save(p) == true, "p7 trove merge: A marks Group, grants 2000 Cash + 200 Tokens and saves")
		rec = stored(uid) or {}
		T.check(rec.Cash == cash0 + 2000 and rec.Tokens == tokens0 + 200 and type(rec.Trove) == "table" and rec.Trove.Group == true, "p7 trove merge: the store holds A's grant and the ask")
		T.check(grantTrove(B, p) == true, "p7 trove merge: B (its copy knew no ask) marks Group and grants too")
		T.eq(B.Save(p), true, "p7 trove merge: B saves")
		rec = stored(uid) or {}
		T.check(rec.Cash == cash0 + 2000 and rec.Tokens == tokens0 + 200 and type(rec.Trove) == "table" and rec.Trove.Group == true,
			"p7 trove merge: stored Cash +2000 once, Tokens +200 once, Trove.Group true (union + the twin rule)",
			"Cash " .. tostring(rec.Cash) .. " (base " .. cash0 .. ") Tokens " .. tostring(rec.Tokens) .. " (base " .. tokens0 .. ")")
		advance(0.3)
		T.check(B.GetTrove(p).Group == true and B.GetCash(p) == cash0 + 2000 and B.GetTokens(p) == tokens0 + 200 and B.MarkTrove(p, "Group", {}) == false,
			"p7 trove merge: B adopted the store (the ask set, the balance once) and refuses the ask now")
		T.check(D.GetTrove(p).Group == true and D.MarkTrove(p, "Like", { Tokens = 50 }) == true and (D.AddTokens(p, 50) or true) and D.Save(p) == true and (stored(uid) or {}).Tokens == tokens0 + 250,
			"p7 trove merge: a second ask (Like) on A pays normally (+50)")
		leave(p)
	end)
	advance(12)
	T.check(releaseB() == true, "p7 trove merge: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p7data_trove_merge")
	K.flushWarnings("p7data_trove_merge", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p7data_provisional
----------------------------------------------------------------------------------------------------
S.p7data_provisional = guarded("p7data_provisional", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local DSt = Mock.DataStore
	local uid = newUserId()
	DSt.Data[storeKey(uid)] = {
		Version = 2, Tokens = 5, Pets = {}, Equipped = {}, Items = {}, Stats = statsOf(),
		Store = { Bought = { Starter = 123 } },
	}
	local p = nil
	local okRun, errRun = pcall(function()
		DSt.Fail = true
		p = Mock.AddPlayer("P7Prov" .. tostring(uid % 1000), uid)
		advance(4)
		if not T.check(D.GetProfile(p) ~= nil and provisional(D, p), "p7 provisional: a profile whose load failed while the store is reachable is provisional") then
			return
		end
		T.check(D.MarkBought(p, "Starter") == false and D.AddBoost(p, "XpPotion", 60) == false and D.MarkTrove(p, "Group", { Cash = 1 }) == false
			and D.MutateDaily(p, function(d)
				d.Streak = 1
				return true
			end) == false and D.NoteReceiptGrant(p, "p7-prov-1", { Gems = 5 }) == false, "p7 provisional: MarkBought / AddBoost / MutateDaily / MarkTrove / NoteReceiptGrant answer false")
		T.eq(D.MarkReceipt(p, "p7-prov-1", { Gems = 5 }), nil, "p7 provisional: MarkReceipt answers nil (NotProcessedYet)")
		T.check(D.GetStore(p) == nil and D.GetDaily(p) == nil and D.GetTrove(p) == nil, "p7 provisional: GetStore / GetDaily / GetTrove answer nil")
		T.eq(D.MarkPassSeen(p, "VIP"), true, "p7 provisional: MarkPassSeen is allowed (a union)")
		local prof = D.GetProfile(p)
		T.check(prof.Store.Bought.Starter == nil and prof.Daily.Streak == 0 and next(prof.Trove) == nil, "p7 provisional: ...nothing else was written to the stand-in")
		DSt.Fail = false
		T.check(K.waitFor(function()
			return not provisional(D, p)
		end, 40), "p7 provisional: (the recovery reads the real save)")
		advance(1)
		local store = D.GetStore(p)
		T.check(store ~= nil and store.Bought.Starter == 123 and store.Passes.VIP ~= nil, "p7 provisional: after the recovery GetStore answers the stored Store (Bought.Starter) with the pass seen kept",
			store and ("Starter " .. tostring(store.Bought.Starter) .. " VIP " .. tostring(store.Passes.VIP)) or "nil")
		T.check(D.MarkBought(p, "Starter") == false and D.GetDaily(p) ~= nil and D.GetTrove(p) ~= nil, "p7 provisional: ...and the real record decides (Starter already bought)")
		T.eq(D.Save(p), true, "p7 provisional: the profile saves")
		local rec = stored(uid) or {}
		T.check(type(rec.Store) == "table" and rec.Store.Bought.Starter == 123 and rec.Store.Passes.VIP ~= nil, "p7 provisional: the store keeps Bought.Starter = 123 and gains Passes.VIP")
	end)
	DSt.Fail = false
	if p then
		leave(p)
	end
	advance(2)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p7data_provisional")
	K.flushWarnings("p7data_provisional", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p7data_reset
----------------------------------------------------------------------------------------------------
S.p7data_reset = guarded("p7data_reset", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local Config = config()
	local Dev = require(K.moduleInstance("server/Services/DevService"))
	if not T.check(type(Dev) == "table" and type(Dev.Run) == "function", "p7 reset: (precondition) DevService.Run exists") then
		return
	end
	local uid = newUserId()
	local saved = { Studio = Mock.Options.Studio, Admins = Config.Dev.Admins, Enabled = Config.Dev.Enabled }
	local p = nil
	local okRun, errRun = pcall(function()
		Mock.Options.Studio = false
		Config.Dev.Enabled = true
		Config.Dev.Admins = { uid }
		p = join("P7Reset", uid)
		T.check(D.MarkBought(p, "Starter") == true and D.MutateDaily(p, function(d)
			d.Streak = 3
			d.LastClaimAt = os.time()
			d.PlayStart = os.time()
			d.PlaySec = 400
			d.PlayClaimed[1] = true
			return true
		end) == true and D.MarkTrove(p, "Group", { Cash = 2000 }) == true, "p7 reset: (setup) a bought pack, a streak, a play-day and a Trove ask")
		T.eq(D.Save(p), true, "p7 reset: (setup) saved")
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.Streak == 3 and type(rec.Trove) == "table" and rec.Trove.Group == true and type(rec.Store) == "table", "p7 reset: (precondition) the store holds Daily, Trove and Store")
		advance(0.6)
		local okReset, msg = Dev.Run(p, "reset", nil, "smoke")
		T.check(okReset == true, "p7 reset: /reset runs for a developer in the live game", tostring(msg))
		local daily, trove, store = D.GetDaily(p), D.GetTrove(p), D.GetStore(p)
		T.check(daily ~= nil and daily.Streak == 0 and daily.LastClaimAt == 0 and daily.PlayStart == 0 and daily.PlaySec == 0 and next(daily.PlayClaimed) == nil and daily.Pet == false,
			"p7 reset: the live Daily is a new player's", daily and ("Streak " .. tostring(daily.Streak) .. " PlayStart " .. tostring(daily.PlayStart)) or "nil")
		T.check(trove ~= nil and next(trove) == nil, "p7 reset: the live Trove is empty")
		T.check(store ~= nil and store.Bought.Starter ~= nil, "p7 reset: the live Store keeps Bought.Starter (Robux)")
		T.eq(D.Save(p), true, "p7 reset: the save after the reset lands")
		rec = stored(uid) or {}
		T.check(rec.Daily == nil and rec.Trove == nil, "p7 reset: the stored Daily and Trove are absent (wiped, written over the union / maxima)",
			"Daily " .. tostring(rec.Daily and rec.Daily.Streak) .. " Trove " .. tostring(rec.Trove and count(rec.Trove)))
		T.check(type(rec.Store) == "table" and rec.Store.Bought.Starter ~= nil, "p7 reset: ...and the stored Store keeps Bought.Starter")
		T.check(D.MarkTrove(p, "Group", { Cash = 2000 }) == true and D.Save(p) == true and type((stored(uid) or {}).Trove) == "table" and stored(uid).Trove.Group == true,
			"p7 reset: the ask can be earned again after the reset and is stored")
	end)
	Mock.Options.Studio = saved.Studio
	Config.Dev.Admins = saved.Admins
	Config.Dev.Enabled = saved.Enabled
	if p then
		leave(p)
	end
	advance(2)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p7data_reset")
	K.flushWarnings("p7data_reset", ALLOWED_WARNINGS)
end)

return S
