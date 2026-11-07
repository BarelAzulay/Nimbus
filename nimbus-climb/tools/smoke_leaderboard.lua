-- smoke_leaderboard.lua: the lobby-shop global leaderboard (docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.10 with
-- section 15: the third page is Ring best, no Climb wins page; plan docs/superpowers/plans/2026-11-07-lobby-shop.md Task 9;
-- Task 11 adds the board in the world here). Server world only (booted):
--   lb_write     Config.Leaderboard (the plan's table) and the LeaderboardState remote after TroveState; ValueOf (Trophies =
--                Battle.Trophies, Pets = the Discovered keys that are pet ids, Ring = GetRing().Best; floored, clamped to
--                MaxValue, nil while loading / provisional); the writes of the booted service with WriteInStudio = true:
--                none before SeedDelay, the first at >= SeedDelay, none for a value of 0 at the seed, two changes 10 s apart
--                -> one write per stat per WriteEvery, a leave writes what changed once, the budget floor (19 no, 20 yes),
--                1e15 -> 1e12 and 12.7 -> 12, none for a provisional profile, zero SetAsync with WriteInStudio = false;
--                BindToClose stops waiting after 5 s (a clone)
--   lb_read      the mock's OrderedDataStore pages, budget call and UserService; the booted service: LeaderboardState on
--                profile load (the documented shape), +1 trophy -> one state within PollSeconds, no change -> none; a fresh
--                clone over a 100-entry store: Scope "Server" with live sorted values before the first good page, the three
--                boot reads a few seconds apart, Top 10 with Mock.Users display names (one batched call, cached), You.Rank
--                inside / nil outside the 100, You.Value live and nil while provisional, NextAt / UpdatedAt on
--                GetServerTimeNow(), a failing read keeps the last page and retries after 30 / 60 / 120 / 240 / 240 s, the
--                name fallbacks (GetNameFromUserIdAsync, then "Player"); a second clone: 2 failures before any good read ->
--                "Server", a GetSortedAsync budget under 2 waits 30 s without counting a failure, then "Global"
--   lb_fallback  no store (a clone Inited with Mock.DataStore.Unavailable = true): Scope "Server", live sorted values, a
--                refresh every 30 s, zero writes and no reads
-- White-box: LeaderboardService._S (Recs, Pages, Writes, NoStore), _StopForTest, _CloseForTest; the mock's
-- Mock.DataStore.Sorted / SortedLog / Budget / FailOnly, Mock.Users / UserServiceFail / UserServiceCalls. Clones follow the
-- polish_data_outage pattern and are stopped and destroyed in every path. Deterministic: mock clock only. Plain Lua 5.1.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local K = _G.K
local ALLOWED_WARNINGS = { "[DataService]", "[MeshLibrary]" }
local STORES = { Trophies = "NimbusClimb_LB_Trophies_v1", Pets = "NimbusClimb_LB_Pets_v1", Ring = "NimbusClimb_LB_Ring_v1" }
local EXPECTED_CFG = {
	Stores = { Trophies = "NimbusClimb_LB_Trophies_v1", Pets = "NimbusClimb_LB_Pets_v1", Ring = "NimbusClimb_LB_Ring_v1" },
	Pages = { "Trophies", "Pets", "Ring" },
	Labels = { Trophies = "Trophies", Pets = "Pets found", Ring = "Ring best" },
	Titles = { Trophies = "TOP TROPHIES", Pets = "TOP PETS FOUND", Ring = "TOP RING ROUND" },
	Top = 10,
	ReadSize = 100,
	RefreshSeconds = 240,
	WriteEvery = 120,
	SweepSeconds = 60,
	SeedDelay = 30,
	RetrySeconds = { 30, 60, 120, 240 },
	BudgetFloor = { Write = 20, Read = 2 },
	TurnSeconds = 15,
	FallbackRefresh = 30,
	PollSeconds = 5,
	MaxValue = 1e12,
	WriteInStudio = false,
}

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local function DS()
	return K.mod("DataService")
end
local function LBmod()
	return K.mod("LeaderboardService")
end
local function DSt()
	return Mock.DataStore
end
local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 996600 + userSeq
end
local function join(prefix, uid)
	local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
	K.advance(1.2)
	return p
end
local function loaded(p)
	return K.waitFor(function()
		return DS().GetProfile(p) ~= nil and DS().IsProvisional(p) ~= true
	end, 10)
end
local function serverNow()
	return workspace:GetServerTimeNow()
end
local function advanceTo(t)
	local d = t - serverNow()
	if d > 0 then
		K.advance(d)
	end
end
local function sortedLog()
	return Mock.DataStore.SortedLog or {}
end
local function logMark()
	return #sortedLog()
end
-- the OrderedDataStore SetAsync calls (done or failed) for one user since mark, optionally of one store
local function setsFor(uid, store, mark)
	local out = {}
	local L = sortedLog()
	for i = (mark or 0) + 1, #L do
		local e = L[i]
		if e.Op == "Set" and e.Key == tostring(uid) and (store == nil or e.Store == store) then
			out[#out + 1] = e
		end
	end
	return out
end
-- a GetSortedAsync call of a store since mark whose Time matches (within 0.05 s) and whose Ok matches
local function getAt(store, mark, time, ok)
	local L = sortedLog()
	for i = (mark or 0) + 1, #L do
		local e = L[i]
		if e.Op == "Get" and e.Store == store and e.Ok == ok and math.abs(e.Time - time) < 0.05 then
			return e
		end
	end
	return nil
end
local function setsText(list)
	local out = {}
	for _, e in ipairs(list) do
		out[#out + 1] = tostring(e.Store):gsub("NimbusClimb_LB_", "") .. "=" .. tostring(e.Value) .. (e.Ok and "" or "(failed)") .. "@" .. string.format("%.1f", e.Time)
	end
	return #out == 0 and "none" or table.concat(out, ", ")
end
local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end
local function deepEq(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEq(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end
local function cfgDiff(got, want)
	if type(got) ~= "table" then
		return "Config.Leaderboard is " .. type(got)
	end
	local out = {}
	for k, v in pairs(want) do
		if not deepEq(got[k], v) then
			out[#out + 1] = k
		end
	end
	for k in pairs(got) do
		if want[k] == nil then
			out[#out + 1] = "extra " .. tostring(k)
		end
	end
	return table.concat(out, ", ")
end
local function setRawTrophies(p, v)
	local prof = DS().GetProfile(p)
	if type(prof.Battle) ~= "table" then
		prof.Battle = {}
	end
	prof.Battle.Trophies = v
end
-- n pet ids the player has not discovered yet
local function freshPetIds(p, n)
	local PC = K.mod("PetCatalog")
	local found = (DS().GetProfile(p) or {}).Discovered or {}
	local ids = {}
	for id in pairs(PC.ById) do
		if found[id] ~= true then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local out = {}
	for i = 1, n do
		out[i] = ids[i]
	end
	return out
end
-- the test's own count: Discovered keys that are true and pet ids; plus the raw count of true keys
local function petCounts(p)
	local PC = K.mod("PetCatalog")
	local valid, raw = 0, 0
	for id, seen in pairs((DS().GetProfile(p) or {}).Discovered or {}) do
		if seen == true then
			raw = raw + 1
			if PC.Get(id) then
				valid = valid + 1
			end
		end
	end
	return valid, raw
end
local function newClone(name)
	local inst = K.moduleInstance("server/Services/LeaderboardService")
	if not inst then
		return nil
	end
	local cl = inst:Clone()
	cl.Name = name
	cl.Parent = inst.Parent
	local ok, mod = pcall(require, cl)
	return { inst = cl, mod = (ok and type(mod) == "table") and mod or nil }
end
local function dropClone(c)
	if c and c.mod and type(c.mod._StopForTest) == "function" then
		pcall(c.mod._StopForTest)
	end
	if c and c.inst and c.inst.Parent then
		c.inst:Destroy()
	end
end
-- the due times of a service's next sends (reads, and the Server refresh while the scope is Server)
local function dueTimes(LB)
	local out = {}
	for _, page in pairs(LB._S.Pages or {}) do
		if type(page.DueAt) == "number" then
			out[#out + 1] = page.DueAt
		end
	end
	if LB.Scope() == "Server" and type(LB._S.FallbackDueAt) == "number" then
		out[#out + 1] = LB._S.FallbackDueAt
	end
	return out
end
-- advances until no read / refresh of LB is due within the next len seconds (true when found)
local function quietWindow(LB, len)
	for _ = 1, 20 do
		local now = serverNow()
		local hit = nil
		for _, due in ipairs(dueTimes(LB)) do
			if due >= now - 1 and due <= now + len + 1.5 then
				hit = math.max(hit or due, due)
			end
		end
		local reading = false
		for _, page in pairs(LB._S.Pages or {}) do
			reading = reading or page.Reading == true
		end
		if not hit and not reading then
			return true
		end
		K.advance(hit and (hit - now + 1.5) or 0.5)
	end
	return false
end
-- the documented LeaderboardState shape: a list of problems
local function stateProblems(st, cfg)
	if type(st) ~= "table" then
		return { "state is " .. type(st) }
	end
	local out = {}
	if st.Scope ~= "Global" and st.Scope ~= "Server" then
		out[#out + 1] = "Scope " .. tostring(st.Scope)
	end
	if type(st.NextAt) ~= "number" or type(st.UpdatedAt) ~= "number" then
		out[#out + 1] = "NextAt / UpdatedAt " .. type(st.NextAt) .. " / " .. type(st.UpdatedAt)
	end
	if type(st.Stats) ~= "table" then
		out[#out + 1] = "Stats is " .. type(st.Stats)
		return out
	end
	local n = 0
	for _ in pairs(st.Stats) do
		n = n + 1
	end
	if n ~= #cfg.Pages then
		out[#out + 1] = n .. " stats, want " .. #cfg.Pages
	end
	for _, stat in ipairs(cfg.Pages) do
		local s = st.Stats[stat]
		if type(s) ~= "table" or type(s.Top) ~= "table" or type(s.You) ~= "table" then
			out[#out + 1] = stat .. ": Top / You missing"
		else
			if #s.Top > cfg.Top then
				out[#out + 1] = stat .. ": " .. #s.Top .. " rows"
			end
			for i, row in ipairs(s.Top) do
				if type(row) ~= "table" or type(row.UserId) ~= "number" or type(row.Name) ~= "string" or type(row.Value) ~= "number" then
					out[#out + 1] = stat .. " row " .. i .. " is not { UserId, Name, Value }"
				end
			end
			if s.You.Rank ~= nil and type(s.You.Rank) ~= "number" then
				out[#out + 1] = stat .. ": You.Rank " .. type(s.You.Rank)
			end
			if s.You.Value ~= nil and type(s.You.Value) ~= "number" then
				out[#out + 1] = stat .. ": You.Value " .. type(s.You.Value)
			end
		end
	end
	return out
end
local function sortedDesc(rows)
	for i = 2, #rows do
		if rows[i].Value > rows[i - 1].Value then
			return false
		end
	end
	return true
end
local function rankOf(mod, p, stat)
	local st = mod.State(p)
	return st and st.Stats and st.Stats[stat] and st.Stats[stat].You.Rank
end

----------------------------------------------------------------------------------------------------
-- lb_write
----------------------------------------------------------------------------------------------------
S.lb_write = guarded("lb_write", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local cfg = Config.Leaderboard
	T.check(deepEq(cfg, EXPECTED_CFG), "lb config: Config.Leaderboard is the plan's table (Ring best, no Wins)", cfgDiff(cfg, EXPECTED_CFG))
	local iTrove, iLb = indexOf(Config.Remotes, "TroveState"), indexOf(Config.Remotes, "LeaderboardState")
	T.check(iTrove ~= nil and iLb == iTrove + 1 and iLb == #Config.Remotes, "lb config: remote LeaderboardState is appended right after TroveState",
		tostring(iTrove) .. " / " .. tostring(iLb) .. " of " .. #Config.Remotes)
	local LB, D = LBmod(), DS()
	if not T.check(type(LB) == "table" and type(LB.ValueOf) == "function" and type(LB.State) == "function" and type(LB.Scope) == "function"
		and type(LB._S) == "table" and type(LB._S.Recs) == "table" and type(cfg) == "table",
		"lb write: LeaderboardService is booted (ValueOf / State / Scope, _S.Recs) and Config.Leaderboard exists") then
		return
	end
	local dss = game:GetService("DataStoreService")
	local okProbe, probe = pcall(function()
		return dss:GetOrderedDataStore("LbSmokeProbe")
	end)
	T.check(okProbe and not pcall(function() probe:SetAsync("1", 1.5) end) and pcall(function() probe:SetAsync("1", 2) end),
		"lb mock: OrderedDataStore:SetAsync takes whole numbers only")
	if type(DSt().Sorted) == "table" then
		DSt().Sorted.LbSmokeProbe = nil
	end

	local Dst = DSt()
	local saved = { WIS = cfg.WriteInStudio, Fail = Dst.Fail, Latency = Dst.Latency, FailOnly = Dst.FailOnly }
	local players = {}
	local clone, provPlayer = nil, nil
	local function track(p)
		players[#players + 1] = p
		return p
	end
	local okRun, errRun = pcall(function()
		local errs0 = #Mock.Errors
		cfg.WriteInStudio = true
		local mark0 = logMark()
		local a = track(join("LbWriteA", newUserId()))
		local b = track(join("LbWriteB", newUserId()))
		local e = track(join("LbWriteE", newUserId()))
		if not T.check(loaded(a) and loaded(b) and loaded(e), "lb write: (setup) three loaded players") then
			return
		end
		local recA, recB, recE = LB._S.Recs[a], LB._S.Recs[b], LB._S.Recs[e]
		if not T.check(recA and recB and recE and type(recA.LoadedAt) == "number", "lb write: each loaded player is tracked (a record with LoadedAt)") then
			return
		end
		-- the values
		T.check(D.AddTrophies(a, 50) == true and D.MutateRing(a, function(r) r.Best = 7 end) == true, "lb write: (setup) A has 50 trophies and Ring best 7")
		for _, id in ipairs(freshPetIds(a, 3)) do
			D.MarkDiscovered(a, id)
		end
		D.GetProfile(a).Discovered.NotAPet = true
		setRawTrophies(e, 1e15)
		local pets, raw = petCounts(a)
		T.check(pets >= 3 and raw == pets + 1 and LB.ValueOf(a, "Pets") == pets, "lb values: Pets = the Discovered keys that are pet ids ('NotAPet' is not counted)",
			tostring(LB.ValueOf(a, "Pets")) .. " vs " .. pets .. " (raw " .. raw .. ")")
		T.check(LB.ValueOf(a, "Trophies") == 50 and LB.ValueOf(a, "Ring") == 7, "lb values: Trophies = Battle.Trophies (50), Ring = GetRing().Best (7)",
			tostring(LB.ValueOf(a, "Trophies")) .. " / " .. tostring(LB.ValueOf(a, "Ring")))
		T.eq(LB.ValueOf(e, "Trophies"), 1e12, "lb values: 1e15 trophies -> MaxValue 1e12")
		T.check(LB.ValueOf(b, "Trophies") == 0 and LB.ValueOf(b, "Ring") == 0, "lb values: a new player has 0 trophies and Ring best 0")
		T.check(LB.ValueOf(a, "Wins") == nil and LB.ValueOf(a, nil) == nil and LB.ValueOf(nil, "Trophies") == nil and LB.ValueOf("x", "Trophies") == nil,
			"lb values: an unknown stat (Wins), a nil stat or a junk player -> nil")

		-- the seed
		local loadLast = math.max(recA.LoadedAt, recB.LoadedAt, recE.LoadedAt)
		advanceTo(recA.LoadedAt + cfg.SeedDelay - 1)
		T.check(#setsFor(a.UserId, nil, mark0) == 0 and #setsFor(b.UserId, nil, mark0) == 0 and #setsFor(e.UserId, nil, mark0) == 0,
			"lb write: no write before SeedDelay (29 s after the load)", setsText(setsFor(a.UserId, nil, mark0)))
		advanceTo(loadLast + cfg.SeedDelay + 1.5)
		local aT, aP, aR = setsFor(a.UserId, STORES.Trophies, mark0), setsFor(a.UserId, STORES.Pets, mark0), setsFor(a.UserId, STORES.Ring, mark0)
		T.check(#aT == 1 and aT[1].Ok and aT[1].Value == 50 and #aP == 1 and aP[1].Value == pets and #aR == 1 and aR[1].Value == 7,
			"lb write: the seed writes each stat once (Trophies 50, Pets, Ring 7)", setsText(setsFor(a.UserId, nil, mark0)))
		T.check(aT[1] ~= nil and aT[1].Time >= recA.LoadedAt + cfg.SeedDelay - 1e-6 and aP[1] ~= nil and aP[1].Time >= recA.LoadedAt + cfg.SeedDelay - 1e-6,
			"lb write: ...the first write at >= SeedDelay after the load", aT[1] and string.format("%.2f s after the load", aT[1].Time - recA.LoadedAt) or "no write")
		T.check(#setsFor(b.UserId, STORES.Trophies, mark0) == 0 and #setsFor(b.UserId, STORES.Ring, mark0) == 0,
			"lb write: no seed write for a value of 0 (B's Trophies and Ring)", setsText(setsFor(b.UserId, nil, mark0)))
		local eT = setsFor(e.UserId, STORES.Trophies, mark0)
		T.check(#eT == 1 and eT[1].Value == 1e12, "lb write: 1e15 trophies are written as 1e12", setsText(eT))

		-- two changes 10 s apart: one write per stat per WriteEvery
		local s0 = aT[1] and aT[1].Time or serverNow()
		D.AddTrophies(a, 5)
		K.advance(10)
		D.AddTrophies(a, 5)
		setRawTrophies(e, 12.7)
		T.eq(LB.ValueOf(e, "Trophies"), 12, "lb values: 12.7 trophies -> 12")
		advanceTo(s0 + cfg.WriteEvery - 1)
		T.eq(#setsFor(a.UserId, STORES.Trophies, mark0), 1, "lb write: two changes 10 s apart: no second write inside WriteEvery")
		advanceTo(s0 + cfg.WriteEvery + cfg.SweepSeconds + 1.5)
		aT = setsFor(a.UserId, STORES.Trophies, mark0)
		T.check(#aT == 2 and aT[2].Value == 60 and aT[2].Time >= s0 + cfg.WriteEvery - 1e-6, "lb write: ...one write after WriteEvery, with the latest value (60)", setsText(aT))
		T.check(#setsFor(a.UserId, STORES.Pets, mark0) == 1 and #setsFor(a.UserId, STORES.Ring, mark0) == 1, "lb write: ...unchanged stats are not written again",
			setsText(setsFor(a.UserId, nil, mark0)))
		eT = setsFor(e.UserId, STORES.Trophies, mark0)
		T.check(#eT == 2 and eT[2].Value == 12, "lb write: 12.7 trophies are written as 12 (a whole number)", setsText(eT))

		-- a leave writes what changed, once
		D.AddTrophies(a, 3)
		local aUid = a.UserId
		local markLeave = logMark()
		Mock.RemovePlayer(a)
		K.advance(1)
		local leaveT = setsFor(aUid, STORES.Trophies, markLeave)
		T.check(#leaveT == 1 and leaveT[1].Value == 63 and #setsFor(aUid, STORES.Pets, markLeave) == 0 and #setsFor(aUid, STORES.Ring, markLeave) == 0,
			"lb write: a leave writes what changed (Trophies 63) and nothing else", setsText(setsFor(aUid, nil, markLeave)))
		T.eq(LB._S.Recs[a], nil, "lb write: ...and the player's record goes with them")

		-- the budget floor
		local dd = track(join("LbWriteBudget", newUserId()))
		T.check(loaded(dd), "lb write: (setup) the budget player is loaded")
		Dst.Budget = { SetIncrementSortedAsync = 19 }
		D.AddTrophies(dd, 9)
		local recD = LB._S.Recs[dd]
		if T.check(recD ~= nil, "lb write: (setup) the budget player is tracked") then
			advanceTo(recD.LoadedAt + cfg.SeedDelay + cfg.SweepSeconds + 2)
			T.eq(#setsFor(dd.UserId, nil, mark0), 0, "lb write: SetIncrementSortedAsync budget 19: no write past the seed and a sweep")
			Dst.Budget = { SetIncrementSortedAsync = 20 }
			K.advance(cfg.SweepSeconds + 1.5)
			local dT = setsFor(dd.UserId, STORES.Trophies, mark0)
			T.check(#dT == 1 and dT[1].Value == 9, "lb write: ...back at 20, the next sweep writes it (9)", setsText(dT))
		end
		Dst.Budget = {}

		-- a loading profile: no value, no record
		Dst.Latency = 2
		local l = track(Mock.AddPlayer("LbWriteLoading" .. tostring(userSeq), newUserId()))
		K.advance(0.5)
		T.check(D.GetProfile(l) == nil and LB.ValueOf(l, "Trophies") == nil and LB._S.Recs[l] == nil, "lb write: a loading profile has no value and no record")
		Dst.Latency = saved.Latency
		T.check(loaded(l), "lb write: (setup) the slow load lands")

		-- a provisional profile: no value, no write (not even a failed try)
		Dst.Fail = true
		local v = track(join("LbWriteProv", newUserId()))
		provPlayer = v
		local isProv = K.waitFor(function()
			return D.IsProvisional(v) == true
		end, 10)
		if T.check(isProv, "lb write: (precondition) a load during an outage leaves a provisional profile") then
			setRawTrophies(v, 5) -- the stand-in holds a value: writing it would be wrong
			T.check(LB.ValueOf(v, "Trophies") == nil and LB.ValueOf(v, "Pets") == nil and LB.ValueOf(v, "Ring") == nil, "lb write: a provisional profile has no value")
			local markV = logMark()
			K.advance(cfg.SeedDelay + cfg.SweepSeconds + 2)
			T.eq(#setsFor(v.UserId, nil, markV), 0, "lb write: no write (not even a failed try) for a provisional profile past SeedDelay and a sweep")
		end
		Dst.Fail = saved.Fail

		-- WriteInStudio = false in Studio: zero SetAsync calls
		cfg.WriteInStudio = false
		local markW = logMark()
		local w = track(join("LbWriteStudio", newUserId()))
		T.check(loaded(w), "lb write: (setup) the Studio player is loaded")
		D.AddTrophies(w, 5)
		D.AddTrophies(b, 2)
		K.advance(cfg.SeedDelay + cfg.SweepSeconds + 2)
		local anySet = 0
		local L = sortedLog()
		for i = markW + 1, #L do
			if L[i].Op == "Set" then
				anySet = anySet + 1
			end
		end
		T.eq(anySet, 0, "lb write: WriteInStudio = false in Studio: zero SetAsync calls (a seed and a change due)")
		cfg.WriteInStudio = true

		-- BindToClose: writes what changed, stops waiting after 5 s (a clone, so the booted service keeps running)
		clone = newClone("LeaderboardServiceSmokeClose")
		if T.check(clone ~= nil and clone.mod ~= nil and type(clone.mod._CloseForTest) == "function" and type(clone.mod._StopForTest) == "function",
			"lb close: a fresh LeaderboardService copy has _CloseForTest / _StopForTest") then
			clone.mod.Init({ DataService = D })
			K.advance(0.2)
			D.AddTrophies(b, 4) -- changed after the copy's start
			Dst.Latency = 8
			local t0 = serverNow()
			local okClose = pcall(clone.mod._CloseForTest)
			local took = serverNow() - t0
			T.check(okClose and took >= 4.5 and took <= 5.3, "lb close: the BindToClose writes stop waiting after 5 s (a store that takes 8 s per write)", string.format("%.2f s", took))
			T.check(clone.mod._S.Writes >= 1, "lb close: ...it started the write of what changed (B's trophies)", tostring(clone.mod._S.Writes))
			Dst.Latency = saved.Latency
			K.advance(9)
		end
		T.eq(#setsFor(aUid, nil, markLeave), 1, "lb write: the leave wrote once (nothing more for that player afterwards)")
		T.eq(#Mock.Errors, errs0, "lb write: nothing raised")
	end)
	dropClone(clone)
	cfg.WriteInStudio = saved.WIS
	Dst.Budget = {}
	Dst.Fail = saved.Fail
	Dst.Latency = saved.Latency
	Dst.FailOnly = saved.FailOnly
	if provPlayer and provPlayer.Parent then
		K.waitFor(function()
			return DS().IsProvisional(provPlayer) ~= true
		end, 150)
	end
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(1)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("lb_write")
	K.flushWarnings("lb_write", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- lb_read
----------------------------------------------------------------------------------------------------
S.lb_read = guarded("lb_read", function()
	if not K.needBoot() then
		return
	end
	local cfg = K.config().Leaderboard
	local LB, D = LBmod(), DS()
	if not T.check(type(LB) == "table" and type(LB.State) == "function" and type(LB.Scope) == "function" and type(LB._S) == "table" and type(LB._S.Pages) == "table"
		and type(cfg) == "table", "lb read: LeaderboardService is booted (State / Scope, _S.Pages) and Config.Leaderboard exists") then
		return
	end
	local Dst = DSt()
	local Players = game:GetService("Players")

	-- part 0: the mock
	local dss = game:GetService("DataStoreService")
	local okMock, errMock = pcall(function()
		local probe = dss:GetOrderedDataStore("LbSmokeRead")
		probe:SetAsync("11", 5)
		probe:SetAsync("12", 9)
		probe:SetAsync("13", 1)
		local pages = probe:GetSortedAsync(false, 2)
		local cur = pages:GetCurrentPage()
		T.check(#cur == 2 and cur[1].key == "12" and cur[1].value == 9 and cur[2].key == "11" and pages.IsFinished == false,
			"lb mock: GetSortedAsync(false, 2) pages from high to low ({ key, value }, IsFinished)")
		local asc = probe:GetSortedAsync(true, 100):GetCurrentPage()
		T.check(#asc == 3 and asc[1].key == "13" and asc[3].key == "12", "lb mock: GetSortedAsync(true, 100) pages from low to high")
		T.check(not pcall(function() probe:GetSortedAsync(false, 101) end), "lb mock: a page size above 100 errors")
		T.eq(dss:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementSortedAsync), 100, "lb mock: the default request budget is 100")
		Dst.Budget = { GetSortedAsync = 1 }
		T.eq(dss:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync), 1, "lb mock: Mock.DataStore.Budget sets a budget")
		Dst.Budget = {}
		Dst.Sorted.LbSmokeRead = nil
		local US = game:GetService("UserService")
		Mock.Users[777001] = { Username = "lbmock_1", DisplayName = "Mock One" }
		local infos = US:GetUserInfosByUserIdsAsync({ 777001, 777002 })
		T.check(type(infos) == "table" and #infos == 1 and infos[1].Id == 777001 and infos[1].Username == "lbmock_1" and infos[1].DisplayName == "Mock One",
			"lb mock: UserService:GetUserInfosByUserIdsAsync answers the known ids from Mock.Users")
		Mock.UserServiceFail = true
		T.check(not pcall(function() US:GetUserInfosByUserIdsAsync({ 777001 }) end), "lb mock: ...and errors while Mock.UserServiceFail")
		Mock.UserServiceFail = false
		T.eq(Players:GetNameFromUserIdAsync(777001), "lbmock_1", "lb mock: Players:GetNameFromUserIdAsync answers the username from Mock.Users")
		T.check(not pcall(function() Players:GetNameFromUserIdAsync(777002) end), "lb mock: ...and errors for an unknown user")
		Mock.Users[777001] = nil
	end)
	Dst.Budget = {}
	Mock.UserServiceFail = false
	if not T.check(okMock, "lb mock: the OrderedDataStore / budget / UserService doubles work", tostring(errMock)) then
		return
	end

	local saved = { Fail = Dst.Fail, FailOnly = Dst.FailOnly, Sorted = {} }
	for _, name in pairs(STORES) do
		saved.Sorted[name] = Dst.Sorted[name]
	end
	local players, clones, users = {}, {}, {}
	local provPlayer = nil
	local function track(p)
		players[#players + 1] = p
		return p
	end
	local function addUser(id, username, display)
		Mock.Users[id] = { Username = username, DisplayName = display }
		users[#users + 1] = id
	end
	local okRun, errRun = pcall(function()
		local errs0 = #Mock.Errors
		------------------------------------------------------------------------------------------------
		-- part 1: the booted service's sends
		------------------------------------------------------------------------------------------------
		local markJoin = K.logSize()
		local r = track(join("LbReadR", newUserId()))
		if not T.check(loaded(r), "lb read: (setup) R is loaded") then
			return
		end
		K.advance(0.5)
		local first = K.remotesFor("LeaderboardState", r.UserId, markJoin)
		T.check(#first >= 1, "lb read: LeaderboardState is sent on profile load")
		local st1 = first[#first] and first[#first].args[1]
		local problems = stateProblems(st1, cfg)
		T.check(#problems == 0, "lb read: ...in the documented shape (Stats per page with Top / You, Scope, NextAt, UpdatedAt)", table.concat(problems, "; "))
		T.check(type(st1) == "table" and type(st1.Stats) == "table" and st1.Stats.Trophies and st1.Stats.Trophies.You.Value == LB.ValueOf(r, "Trophies"),
			"lb read: ...You.Value is the live value")
		T.check(quietWindow(LB, 12), "lb read: (setup) a window with no read or refresh due")
		local mark = K.logSize()
		D.AddTrophies(r, 1)
		K.advance(cfg.PollSeconds + 0.2)
		local got = K.remotesFor("LeaderboardState", r.UserId, mark)
		T.check(#got == 1 and got[1].args[1].Stats.Trophies.You.Value == LB.ValueOf(r, "Trophies"), "lb read: +1 trophy -> one LeaderboardState within PollSeconds, with the new value",
			#got .. " states")
		T.check(quietWindow(LB, 12), "lb read: (setup) another quiet window")
		mark = K.logSize()
		K.advance(11)
		T.eq(#K.remotesFor("LeaderboardState", r.UserId, mark), 0, "lb read: no change -> no LeaderboardState (11 s, nothing due)")

		------------------------------------------------------------------------------------------------
		-- part 2: a fresh copy over a 100-entry store
		------------------------------------------------------------------------------------------------
		local o = track(join("LbReadO", newUserId()))
		T.check(loaded(o) and D.AddTrophies(o, 3) == true, "lb read: (setup) O is loaded with 3 trophies")
		for _, name in pairs(STORES) do
			Dst.Sorted[name] = {}
		end
		local tro = Dst.Sorted[STORES.Trophies]
		for i = 1, 100 do
			tro[i == 37 and tostring(r.UserId) or tostring(50000 + i)] = 1010 - 10 * i
		end
		for i = 1, 12 do
			addUser(50000 + i, "lbuser_" .. i, "Lb Star " .. i)
		end
		local petsStore = Dst.Sorted[STORES.Pets]
		petsStore["50001"], petsStore["50002"], petsStore["50003"] = 40, 30, 20
		T.check(quietWindow(LB, 14), "lb read: (setup) the booted service reads nothing in the next 14 s")
		local calls0 = Mock.UserServiceCalls or 0
		local c = newClone("LeaderboardServiceSmokeRead")
		clones[#clones + 1] = c
		if not T.check(c ~= nil and c.mod ~= nil and type(c.mod.Init) == "function", "lb read: a fresh LeaderboardService copy loads") then
			return
		end
		local t0 = serverNow()
		c.mod.Init({ DataService = D })
		local C = c.mod
		local P = C._S.Pages
		T.eq(C.Scope(), "Server", "lb read: before the first good page the scope is Server")
		local st0 = C.State(r)
		local top0 = st0.Stats.Trophies.Top
		local rO, rR = st0.Stats and C.State(o).Stats.Trophies.You.Rank, st0.Stats.Trophies.You.Rank
		T.check(st0.Scope == "Server" and sortedDesc(top0) and rO ~= nil and rR ~= nil and rO < rR, "lb read: ...State shows this server's live values, sorted (O's 3 before R's 1)",
			tostring(rO) .. " / " .. tostring(rR))
		K.advance(3.6)
		T.check(P.Trophies.Good == true and P.Pets.Good ~= true and P.Ring.Good ~= true and C.Scope() == "Server",
			"lb read: 3 s after the start one stat is read, the others not yet (the scope stays Server)")
		advanceTo(t0 + 10.5)
		T.check(P.Trophies.Good and P.Pets.Good and P.Ring.Good and C.Scope() == "Global", "lb read: every stat read by +10 s -> Scope Global")
		local times = { P.Trophies.UpdatedAt or 0, P.Pets.UpdatedAt or 0, P.Ring.UpdatedAt or 0 }
		table.sort(times)
		T.check(times[2] - times[1] >= 2 and times[3] - times[2] >= 2, "lb read: the three boot reads happen at different times, a few seconds apart",
			string.format("%.2f / %.2f / %.2f", times[1] - t0, times[2] - t0, times[3] - t0))
		T.check(getAt(STORES.Trophies, 0, P.Trophies.UpdatedAt or 0, true) ~= nil and getAt(STORES.Pets, 0, P.Pets.UpdatedAt or 0, true) ~= nil
			and getAt(STORES.Ring, 0, P.Ring.UpdatedAt or 0, true) ~= nil, "lb read: ...each a GetSortedAsync call on its own store")
		local st = C.State(r)
		local rowsOk, rowsText = true, {}
		for i = 1, 10 do
			local row = st.Stats.Trophies.Top[i]
			if not row or row.UserId ~= 50000 + i or row.Value ~= 1010 - 10 * i or row.Name ~= "Lb Star " .. i then
				rowsOk = false
				rowsText[#rowsText + 1] = i .. ": " .. (row and (tostring(row.UserId) .. " " .. tostring(row.Name) .. " " .. tostring(row.Value)) or "missing")
			end
		end
		T.check(rowsOk and #st.Stats.Trophies.Top == 10, "lb read: Top = the store's first 10, with the Mock.Users display names", table.concat(rowsText, "; "))
		T.eq(st.Stats.Trophies.You.Rank, 37, "lb read: You.Rank for a player inside the 100 (37)")
		T.eq(st.Stats.Trophies.You.Value, LB.ValueOf(r, "Trophies"), "lb read: You.Value is the live value, not the stored one")
		local so = C.State(o)
		T.check(so.Stats.Trophies.You.Rank == nil and so.Stats.Trophies.You.Value == 3, "lb read: a player outside the 100 -> Rank nil, Value live (3)")
		T.check(#st.Stats.Pets.Top == 3 and st.Stats.Pets.Top[1].Name == "Lb Star 1" and st.Stats.Pets.Top[1].Value == 40 and #st.Stats.Ring.Top == 0
			and st.Stats.Ring.You.Rank == nil, "lb read: Pets has its 3 rows, Ring's empty store gives no rows and no rank")
		T.eq((Mock.UserServiceCalls or 0) - calls0, 1, "lb read: the names come from one batched UserService call (the Pets names were cached)")
		local maxU = math.max(P.Trophies.UpdatedAt, P.Pets.UpdatedAt, P.Ring.UpdatedAt)
		local minDue = math.min(P.Trophies.DueAt, P.Pets.DueAt, P.Ring.DueAt)
		T.check(st.UpdatedAt == maxU and st.NextAt == minDue and math.abs(P.Trophies.DueAt - (P.Trophies.UpdatedAt + cfg.RefreshSeconds)) < 1e-6,
			"lb read: UpdatedAt = the last good read, NextAt = the next read (each RefreshSeconds after its last good one)")
		local nowS = serverNow()
		T.check(math.abs(st.UpdatedAt - nowS) < 5 and st.NextAt > nowS and st.NextAt <= nowS + cfg.RefreshSeconds, "lb read: NextAt / UpdatedAt are GetServerTimeNow() times",
			string.format("UpdatedAt %+.2f, NextAt %+.2f", st.UpdatedAt - nowS, st.NextAt - nowS))
		-- a second read asks no names again
		T.check(quietWindow(LB, 6), "lb read: (setup) quiet window")
		local calls1 = Mock.UserServiceCalls or 0
		local u1 = P.Trophies.UpdatedAt
		P.Trophies.DueAt = serverNow()
		K.advance(1.5)
		T.check(P.Trophies.UpdatedAt > u1 and (Mock.UserServiceCalls or 0) == calls1, "lb read: a second read asks no names again (cached for the server's life)")

		-- You.Value nil while provisional
		Dst.Fail = true
		local v = track(join("LbReadProv", newUserId()))
		provPlayer = v
		local isProv = K.waitFor(function()
			return D.IsProvisional(v) == true
		end, 10)
		Dst.Fail = saved.Fail
		if T.check(isProv, "lb read: (precondition) a load during an outage leaves a provisional profile") then
			local sv = C.State(v)
			T.check(sv.Stats.Trophies.You.Value == nil and sv.Stats.Pets.You.Value == nil and sv.Stats.Ring.You.Value == nil, "lb read: You.Value is nil while the profile is provisional")
		end

		-- a failing read keeps the last page and retries after 30 / 60 / 120 / 240 s (the last repeats)
		Dst.FailOnly = "GetSortedAsync"
		Dst.Fail = true
		local entries0 = P.Trophies.Entries
		local function failed(k, retry, label)
			local markF = logMark()
			if P.Trophies.DueAt > serverNow() + 1 then
				advanceTo(P.Trophies.DueAt + 1.2)
			else
				P.Trophies.DueAt = serverNow()
				K.advance(1.2)
			end
			local found = getAt(STORES.Trophies, markF, (P.Trophies.DueAt or 0) - retry, false)
			T.check(P.Trophies.Fails == k and P.Trophies.Entries == entries0 and P.Trophies.Good == true and C.Scope() == "Global" and found ~= nil,
				"lb read: failed read " .. k .. ": the last page is kept (Scope Global) and the next try is " .. retry .. " s later" .. (label or ""),
				"Fails " .. tostring(P.Trophies.Fails) .. ", next " .. string.format("%.2f", (P.Trophies.DueAt or 0) - serverNow()) .. " s, failed call " .. tostring(found ~= nil))
		end
		P.Trophies.DueAt = serverNow() -- the next read now (the cadence itself is checked above: DueAt = UpdatedAt + RefreshSeconds)
		failed(1, 30)
		failed(2, 60)
		failed(3, 120)
		failed(4, 240)
		P.Trophies.DueAt = serverNow()
		failed(5, 240, " (the last step repeats)")
		Dst.Fail = saved.Fail
		Dst.FailOnly = saved.FailOnly
		T.check(quietWindow(LB, 4), "lb read: (setup) quiet window")
		local calls2 = Mock.UserServiceCalls or 0
		P.Trophies.DueAt = serverNow()
		K.advance(1.2)
		T.check(P.Trophies.Fails == 0 and P.Trophies.Entries ~= entries0 and math.abs(P.Trophies.DueAt - (P.Trophies.UpdatedAt + cfg.RefreshSeconds)) < 1e-6
			and (Mock.UserServiceCalls or 0) == calls2, "lb read: a good read after the failures resets the backoff (next in RefreshSeconds, names still cached)")

		-- the name fallbacks
		tro["60001"], tro["60002"] = 5000, 4000
		addUser(60001, "lbfallback_1", "Fallback One")
		Mock.UserServiceFail = true
		T.check(quietWindow(LB, 4), "lb read: (setup) quiet window")
		local calls3 = Mock.UserServiceCalls or 0
		P.Trophies.DueAt = serverNow()
		K.advance(1.2)
		local topF = C.State(r).Stats.Trophies.Top
		T.check(topF[1] and topF[1].UserId == 60001 and topF[1].Name == "lbfallback_1" and topF[2] and topF[2].UserId == 60002 and topF[2].Name == "Player"
			and (Mock.UserServiceCalls or 0) == calls3 + 1, "lb read: UserService failing -> Players:GetNameFromUserIdAsync (the username), then 'Player'",
			topF[1] and (tostring(topF[1].Name) .. " / " .. tostring(topF[2] and topF[2].Name)) or "no rows")
		Mock.UserServiceFail = false
		P.Trophies.DueAt = serverNow()
		K.advance(1.2)
		topF = C.State(r).Stats.Trophies.Top
		T.check(topF[1] and topF[1].Name == "lbfallback_1" and topF[2] and topF[2].Name == "Player" and (Mock.UserServiceCalls or 0) == calls3 + 2,
			"lb read: ...a found name stays for the server's life; 'Player' is not cached (asked again, still unknown)")
		dropClone(c)

		------------------------------------------------------------------------------------------------
		-- part 3: 2 failures before any good read -> "Server"; a low read budget waits without a failure
		------------------------------------------------------------------------------------------------
		Dst.FailOnly = "GetSortedAsync"
		Dst.Fail = true
		local c2 = newClone("LeaderboardServiceSmokeRead2")
		clones[#clones + 1] = c2
		local t2 = serverNow()
		c2.mod.Init({ DataService = D })
		local P2 = c2.mod._S.Pages
		advanceTo(t2 + 6.6)
		T.check(P2.Trophies.Fails == 1 and P2.Pets.Fails == 1 and P2.Trophies.Good ~= true and P2.Pets.Good ~= true and c2.mod.Scope() == "Server",
			"lb read: 2 failures in a row before any good read -> Scope Server", tostring(P2.Trophies.Fails) .. " / " .. tostring(P2.Pets.Fails))
		local s2 = c2.mod.State(o)
		T.check(s2.Scope == "Server" and sortedDesc(s2.Stats.Trophies.Top) and s2.Stats.Trophies.You.Rank ~= nil and s2.Stats.Trophies.You.Value == 3,
			"lb read: ...with this server's live values, sorted")
		Dst.Fail = saved.Fail
		Dst.FailOnly = saved.FailOnly
		Dst.Budget = { GetSortedAsync = 1 }
		local dueT = P2.Trophies.DueAt
		advanceTo(dueT + 1.2)
		T.check(P2.Trophies.Fails == 1 and P2.Trophies.Good ~= true and math.abs(P2.Trophies.DueAt - (dueT + cfg.RetrySeconds[1])) < 1.5,
			"lb read: a GetSortedAsync budget under 2 skips the read without counting a failure (tried again 30 s later)",
			"Fails " .. tostring(P2.Trophies.Fails) .. ", next " .. string.format("%.2f", P2.Trophies.DueAt - dueT) .. " s after the skipped one")
		Dst.Budget = {}
		advanceTo(math.max(P2.Trophies.DueAt, P2.Pets.DueAt, P2.Ring.DueAt) + 1.5)
		T.check(P2.Trophies.Good and P2.Pets.Good and P2.Ring.Good and c2.mod.Scope() == "Global", "lb read: ...the good reads after that -> Scope Global")
		dropClone(c2)
		T.eq(#Mock.Errors, errs0, "lb read: nothing raised")
	end)
	for _, c in ipairs(clones) do
		dropClone(c)
	end
	Dst.Fail = saved.Fail
	Dst.FailOnly = saved.FailOnly
	Dst.Budget = {}
	Mock.UserServiceFail = false
	for name, data in pairs(saved.Sorted) do
		Dst.Sorted[name] = data
	end
	for _, id in ipairs(users) do
		Mock.Users[id] = nil
	end
	if provPlayer and provPlayer.Parent then
		K.waitFor(function()
			return DS().IsProvisional(provPlayer) ~= true
		end, 90)
	end
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(1)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("lb_read")
	K.flushWarnings("lb_read", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- lb_fallback
----------------------------------------------------------------------------------------------------
S.lb_fallback = guarded("lb_fallback", function()
	if not K.needBoot() then
		return
	end
	local cfg = K.config().Leaderboard
	local D = DS()
	if not T.check(type(cfg) == "table" and K.moduleInstance("server/Services/LeaderboardService") ~= nil, "lb fallback: LeaderboardService and Config.Leaderboard exist") then
		return
	end
	local Dst = DSt()
	local saved = { Unavailable = Dst.Unavailable, WIS = cfg.WriteInStudio }
	local players, c = {}, nil
	local function track(p)
		players[#players + 1] = p
		return p
	end
	local okRun, errRun = pcall(function()
		local errs0 = #Mock.Errors
		local f1 = track(join("LbFallA", newUserId()))
		local f2 = track(join("LbFallB", newUserId()))
		local f3 = track(join("LbFallC", newUserId()))
		if not T.check(loaded(f1) and loaded(f2) and loaded(f3), "lb fallback: (setup) three loaded players") then
			return
		end
		D.AddTrophies(f1, 30)
		D.AddTrophies(f2, 10)
		D.AddTrophies(f3, 20)
		Dst.Unavailable = true
		c = newClone("LeaderboardServiceSmokeFallback")
		local okInit = c ~= nil and c.mod ~= nil and pcall(c.mod.Init, { DataService = D })
		Dst.Unavailable = saved.Unavailable
		if not T.check(okInit and c.mod._S.NoStore == true and c.mod.Scope() == "Server", "lb fallback: no OrderedDataStore -> no store, Scope Server") then
			return
		end
		local C = c.mod
		local t0 = serverNow()
		local st = C.State(f1)
		local r1, r2, r3 = rankOf(C, f1, "Trophies"), rankOf(C, f2, "Trophies"), rankOf(C, f3, "Trophies")
		T.check(st.Scope == "Server" and sortedDesc(st.Stats.Trophies.Top) and r1 and r2 and r3 and r1 < r3 and r3 < r2 and st.Stats.Trophies.You.Value == 30,
			"lb fallback: the live values of this server, sorted (30, 20, 10)", tostring(r1) .. " / " .. tostring(r3) .. " / " .. tostring(r2))
		T.check(math.abs(st.UpdatedAt - t0) < 0.5 and math.abs(st.NextAt - (st.UpdatedAt + cfg.FallbackRefresh)) < 1e-6, "lb fallback: UpdatedAt = the build time, NextAt = FallbackRefresh later",
			string.format("%+.2f / %+.2f", st.UpdatedAt - t0, st.NextAt - st.UpdatedAt))
		-- a refresh every 30 s
		D.AddTrophies(f2, 100)
		K.advance(1)
		local mid = C.State(f2)
		T.check(rankOf(C, f2, "Trophies") == r2 and mid.Stats.Trophies.You.Value == 110, "lb fallback: between refreshes the rows stay (B still last), You.Value is live (110)")
		advanceTo(st.NextAt + 1.2)
		local after = C.State(f2)
		local n2, n1 = rankOf(C, f2, "Trophies"), rankOf(C, f1, "Trophies")
		T.check(n2 and n1 and n2 < n1 and after.UpdatedAt >= st.NextAt - 1e-6 and after.UpdatedAt < st.NextAt + 1.1 and math.abs(after.NextAt - (after.UpdatedAt + cfg.FallbackRefresh)) < 1e-6,
			"lb fallback: the rows refresh FallbackRefresh later (B first with 110)", tostring(n2) .. " / " .. tostring(n1) .. string.format(", refreshed %+.2f", after.UpdatedAt - st.NextAt))
		-- no writes and no reads, even with writes allowed
		cfg.WriteInStudio = true
		K.advance(cfg.SeedDelay + cfg.SweepSeconds + 2)
		local later = C.State(f1)
		-- each rebuild runs at the scheduler's first 1 s pass after it is due, so a rebuild can be up to ~1.1 s late
		local gap = later.UpdatedAt - after.UpdatedAt
		local k = math.floor(gap / cfg.FallbackRefresh)
		T.check(k >= 2 and gap - k * cfg.FallbackRefresh <= k * 1.1 + 1e-6 and math.abs(later.NextAt - (later.UpdatedAt + cfg.FallbackRefresh)) < 1e-6,
			"lb fallback: ...and every FallbackRefresh after that", string.format("%.1f s later (%d refreshes)", gap, k))
		T.eq(C._S.Writes, 0, "lb fallback: zero writes without a store (WriteInStudio on, past SeedDelay and a sweep)")
		local read = false
		for _, page in pairs(C._S.Pages) do
			read = read or page.Good == true or (page.Fails or 0) > 0
		end
		T.check(not read and C.Scope() == "Server", "lb fallback: ...no reads either; the scope stays Server")
		T.eq(#Mock.Errors, errs0, "lb fallback: nothing raised")
	end)
	dropClone(c)
	cfg.WriteInStudio = saved.WIS
	Dst.Unavailable = saved.Unavailable
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(1)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("lb_fallback")
	K.flushWarnings("lb_fallback", ALLOWED_WARNINGS)
end)

return S
