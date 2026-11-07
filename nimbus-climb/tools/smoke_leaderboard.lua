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
--   lb_world     (Task 11, spec 5.10 "World") the LobbyLeaderboard board on the south lawn: exactly one, in the Plaza
--                folder, its pivot (the ground centre) at polar 295 degrees r 48 from Config.Lobby.Origin (+-0.5) on the
--                lawn, facing the plaza centre; the board layout Task 30's prop_board_lb mesh shares: Face 16 x 13 (+-0.01)
--                9.5 studs up (navy SmoothPlastic, not colliding, queryable so the client SurfaceGui's tabs take taps), two
--                colliding 1 x 17 x 1 posts at local x +-8.9, a 0.6-stud frame around the face (four bars, their area
--                exactly the ring), the 18.6 x 0.6 x 2.4 roof at y 16.9 with a ridge on it, no light; distances: fountain
--                centre >= 24, every LobbyInfo.NpcSpots entry >= 14, every Bench >= 12.5, every FlowerBed >= 13, the spawn
--                >= 30; nothing else of the lobby standing above the lawn inside the board's footprint (posts, feet, roof;
--                0.25 stud margin); no "plaza decor skipped" / "leaderboard board failed" warn; the dress request read from
--                a rebuild with LobbyBuilder._Kit: one prop_board_lb record on the model at its pivot, Keep = { "Face" };
--                ML_DressKey only where MeshLibrary.Status("prop_board_lb") ~= "missing" (in --mesh the scenario gives the
--                key a fixture holder, as lobby_trove_plaza does for the eggs, so the check runs there); the prop_board_lb
--                manifest (Task 30) against the booted board: attachment FaceCenter at (0, 9.5, -0.2), its bounds cover
--                the hidden Part build (every part but the Face, 0.3 slack), reach at most 0.6 past it across / in depth
--                and 1.4 over the ridge (the trophy cup), its foot seated on the lawn (sunk <= 0.25), one Fixed SmoothPlastic part (no
--                Neon), <= 4,000 tris (propBig)
--   lb_titles    (Task 18, spec 16.6 "Server" / "Tests", server half; Review Focus 5) Config.Attr.Title / TitleRank and
--                Config.Leaderboard.RankTitles; a no-store copy ("Server" scope): a player ranked first in this server gets no
--                Top title, the owner still gets Creator; the booted service over a 100-entry Trophies store: rank 3 ->
--                Top10 / 3 / "Top 10", rank 57 -> Top100 / 57 / "Top 100", outside -> none / ""; leaderstats children Tokens
--                then Rank (a StringValue); the owner of a User game -> Creator at once, and at rank 3 with TitleRank 3; an
--                Admin who is not the owner -> no Creator (Top10 at rank 5); the next read moves rank 3 to 12 -> Top100, a
--                read with nothing changed writes nothing (S.TitleWrites, AttributeChanged, Rank.Changed), the read after
--                that drops the player out -> none; Rank missing: the attributes at once, the text at the next pass after
--                the 10 s wait; a group game: GetRankInGroup 255 -> Creator, erroring -> none (IsOwner nil, IsAllowed
--                still false, a boolean), not asked again before the next Trophies refresh, then Creator; LeaderboardService's
--                join handler run by hand before PlayerService's makes no leaderstats, the children are still Tokens then
--                Rank and Rank holds the title's text; a player leaving while a Trophies read is in flight -> no error,
--                S.Titles / S.Owner dropped
-- White-box: LeaderboardService._S (Recs, Pages, Writes, NoStore, Titles, Owner, TitleWrites), _StopForTest, _CloseForTest,
-- _JoinForTest; the mock's Mock.DataStore.Sorted / SortedLog / Budget / FailOnly, Mock.Users / UserServiceFail /
-- UserServiceCalls, Mock.GroupRanks / GroupRankFail, Mock._onJoin; game.CreatorType / CreatorId. Clones follow the
-- polish_data_outage pattern and are stopped and destroyed in every path. lb_world's rebuild follows smoke_p6_lobby.lua /
-- smoke_lobby_shop_world.lua (the booted lobby set aside and put back; _Kit, the Meadow stats and the fixture holder restored
-- in every path). Deterministic: mock clock only. Plain Lua 5.1.

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
-- [Task 18] spec 16.6 "Config"
local RANK_TITLES = {
	Stat = "Trophies",
	Rainbow = 10,
	Gold = 100,
	Column = "Rank",
	ColumnText = { Creator = "Creator", Top10 = "Top 10", Top100 = "Top 100" },
	Tag = { Creator = "CREATOR", Top10 = "TOP 10", Top100 = "TOP 100" },
}
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
	RankTitles = RANK_TITLES, -- [Task 18] the titles (lb_titles checks them)
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
	T.check(deepEq(cfg, EXPECTED_CFG), "lb config: Config.Leaderboard is the plan's table (Ring best, no Wins, Task 18's RankTitles)", cfgDiff(cfg, EXPECTED_CFG))
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

----------------------------------------------------------------------------------------------------
-- lb_world (Task 11): the leaderboard board on the south lawn
----------------------------------------------------------------------------------------------------
local MESH_MODE = (os and os.getenv and os.getenv("NC_MESH_FIXTURES") == "1") or false
-- the spec's board (5.10 "World") and Task 11's layout; FountainD = LobbyBuilder's G.FountainD (the fountain roundabout's
-- distance from the origin towards the shop)
local WB = { Key = "prop_board_lb", Angle = 295, R = 48, LAWN = 0.4, FountainD = 66, Navy = Color3.fromRGB(34, 42, 76) }

local function wreq(path)
	local inst = K.moduleInstance(path)
	if not inst then
		return nil
	end
	local ok, m = pcall(require, inst)
	return (ok and type(m) == "table") and m or nil
end

local function hdist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function flatUnit(v)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-6 then
		return nil
	end
	return f.Unit
end

local function boardsIn(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") and d.Name == "LobbyLeaderboard" then
			out[#out + 1] = d
		end
	end
	return out
end

local function badWarns(from)
	local out = {}
	for i = (from or 0) + 1, #Mock.Output do
		local t = tostring(Mock.Output[i].text)
		if string.find(t, "plaza decor skipped", 1, true) or string.find(t, "leaderboard board failed", 1, true) then
			out[#out + 1] = t
		end
	end
	return out
end

-- a part's footprint as an XZ rectangle (lobby parts turn about Y only; a part on its side falls back to a circle)
local function footprint(p)
	local r, l = flatUnit(p.CFrame.RightVector), flatUnit(p.CFrame.LookVector)
	local c = Vector3.new(p.Position.X, 0, p.Position.Z)
	if not r or not l or math.abs(p.CFrame.UpVector.Y) < 0.99 then
		local h = math.max(p.Size.X, p.Size.Y, p.Size.Z) / 2
		return { C = c, A = { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }, H = { h, h } }
	end
	return { C = c, A = { r, l }, H = { p.Size.X / 2, p.Size.Z / 2 } }
end

-- the largest gap between two footprints along their four edge normals (> 0: apart; <= 0: they overlap)
local function rectSeparation(a, b)
	local best = -math.huge
	for _, axis in ipairs({ a.A[1], a.A[2], b.A[1], b.A[2] }) do
		local function radius(rc)
			return math.abs(rc.A[1]:Dot(axis)) * rc.H[1] + math.abs(rc.A[2]:Dot(axis)) * rc.H[2]
		end
		local gap = math.abs((b.C - a.C):Dot(axis)) - radius(a) - radius(b)
		best = math.max(best, gap)
	end
	return best
end

-- the checks of one built board
local function checkBoard(label, board, info, root)
	local Config = K.config()
	local o = Config.Lobby.Origin
	local cf = board:GetPivot()
	local spot = Vector3.new(o.X + math.cos(math.rad(WB.Angle)) * WB.R, o.Y, o.Z + math.sin(math.rad(WB.Angle)) * WB.R)
	T.check(hdist(cf.Position, spot) <= 0.5, label .. ": the board's pivot stands at polar 295 degrees, r 48 from the origin (+-0.5)",
		string.format("%.2f off", hdist(cf.Position, spot)))
	T.check(math.abs(cf.Position.Y - (o.Y - WB.LAWN)) <= 0.05 and cf.UpVector.Y > 0.999, label .. ": the pivot is the ground centre on the plaza lawn (Origin.Y - 0.4), upright",
		string.format("y %.2f", cf.Position.Y - o.Y))
	local toC = flatUnit(o - cf.Position)
	T.check(toC ~= nil and cf.LookVector:Dot(toC) > 0.99, label .. ": the board faces the plaza centre (front -Z)", toC and string.format("dot %.4f", cf.LookVector:Dot(toC)) or "")
	T.check(board.Parent ~= nil and board.Parent.Name == "Plaza", label .. ": the board stands in the Plaza folder", board.Parent and board.Parent.Name or "nil")

	-- the layout Task 23's mesh shares (pivot = ground centre, front -Z)
	local face = board:FindFirstChild("Face")
	if T.check(face ~= nil and face:IsA("BasePart"), label .. ": a Face part") then
		T.check(math.abs(face.Size.X - 16) <= 0.01 and math.abs(face.Size.Y - 13) <= 0.01, label .. ": Face.Size is 16 x 13 (+-0.01)", tostring(face.Size))
		local lf = cf:ToObjectSpace(face.CFrame)
		T.check((lf.Position - Vector3.new(0, 9.5, 0)).Magnitude <= 0.05 and face.CFrame.LookVector:Dot(cf.LookVector) > 0.999,
			label .. ": the Face's centre is 9.5 studs over the pivot, its Front face toward the plaza", tostring(lf.Position))
		T.check(face.Material == Enum.Material.SmoothPlastic and math.abs(face.Color.R - WB.Navy.R) < 0.006 and math.abs(face.Color.G - WB.Navy.G) < 0.006
			and math.abs(face.Color.B - WB.Navy.B) < 0.006 and face.Transparency == 0, label .. ": the Face is navy SmoothPlastic and visible")
		T.check(face.CanCollide == false and face.CanQuery == true, label .. ": the Face does not collide but stays queryable (the client SurfaceGui's tabs take taps)")
	end
	local posts, frames, xs, postsOk = {}, {}, {}, true
	for _, c in ipairs(board:GetChildren()) do
		if c:IsA("BasePart") and c.Name == "Post" then
			posts[#posts + 1] = c
			local l = cf:PointToObjectSpace(c.Position)
			xs[#xs + 1] = l.X
			postsOk = postsOk and (c.Size - Vector3.new(1, 17, 1)).Magnitude <= 0.01 and math.abs(l.Y - 8.5) <= 0.05 and math.abs(l.Z) <= 0.05 and c.CanCollide == true
		elseif c:IsA("BasePart") and c.Name == "Frame" then
			frames[#frames + 1] = c
		end
	end
	table.sort(xs)
	T.check(#posts == 2 and postsOk and math.abs(xs[1] + 8.9) <= 0.05 and math.abs(xs[2] - 8.9) <= 0.05,
		label .. ": two colliding 1 x 17 x 1 posts at local x -8.9 and +8.9", #posts .. " posts at " .. table.concat(xs, ", "))
	-- the frame: every bar inside the outer rectangle (x +-8.6, y 2.4 .. 16.6) and outside the face (x +-8, y 3 .. 16),
	-- their area exactly the ring between the two
	local area, inRing = 0, true
	for _, fr in ipairs(frames) do
		local l = cf:ToObjectSpace(fr.CFrame)
		local hx, hy = fr.Size.X / 2, fr.Size.Y / 2
		local x0, x1, y0, y1 = l.X - hx, l.X + hx, l.Y - hy, l.Y + hy
		area = area + fr.Size.X * fr.Size.Y
		local outer = x0 >= -8.6 - 0.01 and x1 <= 8.6 + 0.01 and y0 >= 2.4 - 0.01 and y1 <= 16.6 + 0.01
		local clear = x1 <= -8 + 0.01 or x0 >= 8 - 0.01 or y1 <= 3 + 0.01 or y0 >= 16 - 0.01
		inRing = inRing and outer and clear and math.abs(l.Z) <= 0.35 and fr.CFrame.LookVector:Dot(cf.LookVector) > 0.999
	end
	T.check(#frames == 4 and inRing and math.abs(area - (17.2 * 14.2 - 16 * 13)) <= 0.05,
		label .. ": a 0.6-stud frame around the face (four bars filling exactly the ring)", string.format("%d bars, area %.2f", #frames, area))
	local roof, ridge = board:FindFirstChild("Roof"), board:FindFirstChild("Ridge")
	local lr = roof and roof:IsA("BasePart") and cf:PointToObjectSpace(roof.Position)
	T.check(lr and (roof.Size - Vector3.new(18.6, 0.6, 2.4)).Magnitude <= 0.01 and math.abs(lr.Y - 16.9) <= 0.05 and math.abs(lr.X) <= 0.05 and math.abs(lr.Z) <= 0.05,
		label .. ": the roof is 18.6 x 0.6 x 2.4 at y 16.9", roof and tostring(roof.Size) or "no Roof")
	local lg = ridge and ridge:IsA("BasePart") and cf:PointToObjectSpace(ridge.Position)
	T.check(lg and roof and math.abs((lg.Y - ridge.Size.Y / 2) - (16.9 + 0.3)) <= 0.05 and ridge.Size.X < roof.Size.X, label .. ": a ridge sits on the roof")
	local lights, parts = 0, 0
	for _, d in ipairs(board:GetDescendants()) do
		if d:IsA("Light") then
			lights = lights + 1
		elseif d:IsA("BasePart") then
			parts = parts + 1
		end
	end
	T.check(lights == 0 and parts <= 16, label .. ": no light, a small Part build (<= 16 parts)", lights .. " lights, " .. parts .. " parts")

	-- distances (spec 5.10: the clearance 9 checked against the fountain, NPC spots, benches, flower beds, the spawn)
	local p = cf.Position
	local off = Config.Lobby.ShopOffset
	local fountain = o + flatUnit(off) * WB.FountainD
	T.check(hdist(p, fountain) >= 24, label .. ": the fountain's centre is >= 24 studs away", string.format("%.1f", hdist(p, fountain)))
	local npcMin = math.huge
	for _, s in ipairs(info.NpcSpots or {}) do
		npcMin = math.min(npcMin, hdist(p, s.Position))
	end
	T.check(#(info.NpcSpots or {}) >= 6 and npcMin >= 14, label .. ": every NPC spot is >= 14 studs away", string.format("%d spots, nearest %.1f", #(info.NpcSpots or {}), npcMin))
	local mins, counts = { Bench = math.huge, FlowerBed = math.huge }, { Bench = 0, FlowerBed = 0 }
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") and mins[d.Name] then
			counts[d.Name] = counts[d.Name] + 1
			mins[d.Name] = math.min(mins[d.Name], hdist(p, d:GetPivot().Position))
		end
	end
	T.check(counts.Bench >= 4 and mins.Bench >= 12.5, label .. ": every Bench is >= 12.5 studs away", string.format("%d benches, nearest %.1f", counts.Bench, mins.Bench))
	T.check(counts.FlowerBed >= 1 and mins.FlowerBed >= 13, label .. ": every FlowerBed is >= 13 studs away", string.format("%d beds, nearest %.1f", counts.FlowerBed, mins.FlowerBed))
	local spawn = info.SpawnCFrame and info.SpawnCFrame.Position
	T.check(spawn ~= nil and hdist(p, spawn) >= 30, label .. ": the spawn is >= 30 studs away", spawn and string.format("%.1f", hdist(p, spawn)) or "no SpawnCFrame")

	-- nothing else standing above the lawn inside the board's footprint (posts, feet, frame, roof), 0.25 stud margin
	local mine = {}
	for _, d in ipairs(board:GetDescendants()) do
		if d:IsA("BasePart") then
			mine[#mine + 1] = footprint(d)
		end
	end
	local lawnTop = o.Y - WB.LAWN
	local hits, seen, nearest, nearestName = {}, 0, math.huge, "-"
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and not d:IsDescendantOf(board) and d.Transparency < 1 and hdist(d.Position, p) < 40
			and d.Position.Y + d.Size.Y / 2 > lawnTop + 0.2 and d.Position.Y - d.Size.Y / 2 < cf.Position.Y + 18 then
			seen = seen + 1
			local fp = footprint(d)
			local gap = math.huge
			for _, m in ipairs(mine) do
				gap = math.min(gap, rectSeparation(m, fp))
			end
			if gap < 0.25 then
				hits[#hits + 1] = d:GetFullName()
			end
			if gap < nearest then
				nearest, nearestName = gap, d.Name
			end
		end
	end
	T.check(seen > 0 and #hits == 0, label .. ": nothing else of the lobby stands above the lawn inside the board's footprint (paths, borders, props)", table.concat(hits, ", "))
	T.info(string.format("*%s: fountain %.1f, NPC spot %.1f, bench %.1f, flower bed %.1f, spawn %.1f studs; %d parts above the lawn within 40 studs, the nearest (%s) %.2f studs off the footprint",
		label, hdist(p, fountain), npcMin, mins.Bench, mins.FlowerBed, spawn and hdist(p, spawn) or -1, seen, nearestName, nearest))
end

-- the prop_board_lb manifest (Task 30) against a built board: the mesh a client dresses LobbyLeaderboard with. Dressing
-- hides the Part build locally but it still collides, and the Face stays (Keep, the SurfaceGui), so the mesh stands where
-- those Parts stand: it covers every hidden Part (WB.Cover slack: no invisible wall), reaches at most WB.Reach past them
-- across and in depth (nothing shows where a player walks through it), its top at most WB.Crest over the ridge (the
-- trophy crest), its feet seated on the lawn (sunk at most WB.Sink); one baked Fixed part, no Neon (the board has no light
-- and no glow, spec 5.10), within the propBig budget. The 16 x 13 opening itself is a voxel fact the manifest does not
-- carry: Task 30 checks it on the built mesh (evidence/blender/t30).
WB.Cover, WB.Reach, WB.Crest, WB.Sink, WB.Tris = 0.3, 0.6, 1.4, 0.25, 4000

local function checkBoardMesh(label, board, ML)
	local man = ML and ML.Manifest(WB.Key)
	local b = man and man.Bounds
	local lo, hi = b and (b.Min or b.min), b and (b.Max or b.max)
	if not T.check(type(lo) == "table" and type(hi) == "table", label .. ": the prop_board_lb manifest exists (Task 30) with its bounds") then
		return
	end
	local att = man.Attachments and man.Attachments.FaceCenter
	local fp = att and (att.Pos or att.pos)
	T.check(type(fp) == "table" and math.abs(fp[1]) < 0.01 and math.abs(fp[2] - 9.5) < 0.01 and math.abs(fp[3] + 0.2) < 0.01,
		label .. ": ...attachment FaceCenter at (0, 9.5, -0.2), the Face's front centre", type(fp) == "table" and table.concat(fp, ", ") or "none")
	-- the hidden Part build's envelope (every part but the Face) in the board's pivot space
	local cf = board:GetPivot()
	local elo, ehi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for _, d in ipairs(board:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Face" then
			local h = d.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local q = cf:PointToObjectSpace(d.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
						local v = { q.X, q.Y, q.Z }
						for i = 1, 3 do
							elo[i], ehi[i] = math.min(elo[i], v[i]), math.max(ehi[i], v[i])
						end
					end
				end
			end
		end
	end
	local function box(a, z)
		return string.format("x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f", a[1], z[1], a[2], z[2], a[3], z[3])
	end
	local covers = true
	for i = 1, 3 do
		covers = covers and lo[i] <= elo[i] + WB.Cover and hi[i] >= ehi[i] - WB.Cover
	end
	T.check(covers, label .. ": ...it covers the hidden Part build (every part but the Face, " .. WB.Cover .. " stud slack): no invisible wall",
		"mesh " .. box(lo, hi) .. "; parts " .. box(elo, ehi))
	T.check(lo[1] >= elo[1] - WB.Reach and hi[1] <= ehi[1] + WB.Reach and lo[3] >= elo[3] - WB.Reach and hi[3] <= ehi[3] + WB.Reach
		and hi[2] <= ehi[2] + WB.Crest, label .. ": ...and reaches at most " .. WB.Reach .. " stud past it across and in depth, " .. WB.Crest .. " over the ridge",
		"mesh " .. box(lo, hi) .. "; parts " .. box(elo, ehi))
	T.check(lo[2] <= 0.01 and lo[2] >= -WB.Sink, label .. ": ...seated on the lawn (its foot at the pivot, sunk at most " .. WB.Sink .. ")", string.format("foot %.3f", lo[2]))
	local fixed, bad = 0, {}
	for _, p in ipairs(man.Parts or {}) do
		local name, mat = tostring(p.name or p.Name), p.material or p.Material
		if name == "Fixed" and mat == "SmoothPlastic" then
			fixed = fixed + 1
		else
			bad[#bad + 1] = name .. " " .. tostring(mat)
		end
	end
	T.check(fixed == 1 and #bad == 0, label .. ": ...one baked Fixed SmoothPlastic part, no Neon (no light, no glow)", fixed .. " Fixed; " .. table.concat(bad, ", "))
	local raw = man.Raw or {}
	local tris = tonumber(raw.Tris or raw.tris)
	T.check(tris ~= nil and tris <= WB.Tris, label .. ": ...within the propBig budget (<= " .. WB.Tris .. " tris)", tostring(tris))
end

S.lb_world = guarded("lb_world", function()
	if not K.needBoot() then
		return
	end
	local info = K.W.lobbyInfo
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local LB = wreq("server/Services/LobbyBuilder")
	local LBB = wreq("server/Services/LobbyBoardBuilder")
	local ML = wreq("shared/MeshLibrary")
	if not T.check(info ~= nil and lobby ~= nil and LB ~= nil and ML ~= nil, "lb world: (precondition) the booted lobby, LobbyBuilder and MeshLibrary") then
		return
	end
	T.check(LBB ~= nil and type(LBB.Leaderboard) == "function", "lb world: LobbyBoardBuilder.Leaderboard exists")

	------------------------------------------------------------------ the booted board
	local boards = boardsIn(lobby)
	T.eq(#boards, 1, "lb world: exactly one LobbyLeaderboard in the booted lobby")
	if boards[1] then
		checkBoard("lb world", boards[1], info, lobby)
		checkBoardMesh("lb board mesh", boards[1], ML)
	end
	local warned = badWarns(0)
	T.check(#warned == 0, "lb world: no 'plaza decor skipped' / 'leaderboard board failed' warn in the build log", table.concat(warned, " | "))

	------------------------------------------------------------------ rebuild: the dress request
	local MK = LB._Meadow and LB._Meadow.K
	local savedStats, savedLast = MK and MK.Stats, MK and MK.Last
	local undo = {}
	lobby.Name = "NimbusLobby_LbWorldKeep"
	local cursor = #Mock.Output
	local okRun, errRun = pcall(function()
		LB._Kit = { Targets = {}, Clouds = {} }
		if MESH_MODE then
			-- --mesh: a fixture holder for the key in the fixture MeshLibrary's root (Status -> "loading"), removed after
			local root = game:GetService("ReplicatedStorage"):FindFirstChild("P6PetsMeshLibrary")
			if T.check(root ~= nil, "lb world (--mesh): the fixture MeshLibrary root exists") then
				local h = Instance.new("Folder")
				h.Name = WB.Key
				h.Parent = root
				undo[#undo + 1] = function()
					h:Destroy()
				end
			end
		end
		local okBuild, built = pcall(LB.Build)
		if not T.check(okBuild and type(built) == "table" and typeof(built.Folder) == "Instance", "lb world rebuild: LobbyBuilder.Build() ran", tostring(built)) then
			return
		end
		undo[#undo + 1] = function()
			built.Folder:Destroy()
		end
		local list = boardsIn(built.Folder)
		T.eq(#list, 1, "lb world rebuild: exactly one LobbyLeaderboard")
		local board = list[1]
		local recs = {}
		for _, rec in ipairs(LB._Kit and LB._Kit.Targets or {}) do
			if rec.Key == WB.Key then
				recs[#recs + 1] = rec
			end
		end
		local rec = recs[1]
		local keepFace = false
		for _, name in ipairs(rec and type(rec.Keep) == "table" and rec.Keep or {}) do
			keepFace = keepFace or name == "Face"
		end
		T.check(#recs == 1 and board ~= nil and rec.Target == board and keepFace, "lb world: one prop_board_lb dress request on the LobbyLeaderboard model, Keep holding 'Face'",
			#recs .. " records")
		T.check(rec ~= nil and board ~= nil and typeof(rec.Origin) == "CFrame" and (rec.Origin.Position - board:GetPivot().Position).Magnitude <= 0.01
			and rec.Origin.LookVector:Dot(board:GetPivot().LookVector) > 0.9999, "lb world: ...its origin is the board's pivot (the ground centre, front -Z)")
		local okSt, st = pcall(ML.Status, WB.Key)
		if okSt and st ~= "missing" then
			T.check(board ~= nil and board:GetAttribute("ML_DressKey") == WB.Key, "lb world: ML_DressKey = prop_board_lb on the model (the key is " .. tostring(st) .. ")")
		elseif MESH_MODE then
			T.fail("lb world (--mesh): the fixture holder should make prop_board_lb's status not 'missing'", tostring(st))
		else
			T.check(board ~= nil and board:GetAttribute("ML_DressKey") == nil, "lb world: no ML_DressKey while prop_board_lb is missing (the Part build shows; --mesh checks the tag)")
		end
		local sk = badWarns(cursor)
		T.check(#sk == 0, "lb world rebuild: no 'plaza decor skipped' / 'leaderboard board failed' warn", table.concat(sk, " | "))
	end)
	for i = #undo, 1, -1 do
		pcall(undo[i])
	end
	LB._Kit = nil
	if MK then
		MK.Stats, MK.Last = savedStats, savedLast
	end
	lobby.Name = "NimbusLobby"
	T.check(okRun, "lb world: the rebuild checks ran", tostring(errRun))
	T.check(LB._Kit == nil and workspace:FindFirstChild("NimbusLobby") == lobby and #boardsIn(lobby) == 1, "lb world: the hook is back to nil and the booted lobby is back")
	K.flushErrors("lb_world")
	K.flushWarnings("lb_world", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- lb_titles (Task 18): the Trophies rank titles and the owner's Creator title, written by the server
----------------------------------------------------------------------------------------------------
local function attrTitle(p)
	return p:GetAttribute("Title"), p:GetAttribute("TitleRank")
end
local function rankValue(p)
	local ls = p:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Rank") or nil
end
local function rankText(p)
	local v = rankValue(p)
	return v and v.Value or nil
end
local function statNames(p)
	local ls = p:FindFirstChild("leaderstats")
	if not ls then
		return "no leaderstats"
	end
	local out = {}
	for _, ch in ipairs(ls:GetChildren()) do
		out[#out + 1] = ch.Name
	end
	return table.concat(out, ",")
end
-- "Top10/3/Top 10": the two attributes and the Rank text of a player
local function titleText(p)
	local kind, rank = attrTitle(p)
	return tostring(kind) .. "/" .. tostring(rank) .. "/" .. tostring(rankText(p))
end
-- a 100-entry Trophies store: at[rank] = userId, every other row a stranger (70000 + rank)
local function fillTrophies(at)
	local store = {}
	for i = 1, 100 do
		store[tostring(at[i] or (70000 + i))] = 2010 - 10 * i
	end
	Mock.DataStore.Sorted[STORES.Trophies] = store
end
-- the booted service's next Trophies read, now (true once it landed)
local function readTrophiesNow(LB)
	local page = LB._S.Pages.Trophies
	K.waitFor(function()
		return page.Reading ~= true
	end, 10)
	page.DueAt = serverNow()
	K.advance(1.5)
	return page.Good == true and page.Reading ~= true
end

S.lb_titles = guarded("lb_titles", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local cfg = Config.Leaderboard
	local LB, D, Dev = LBmod(), DS(), K.mod("DevService")
	T.check(Config.Attr.Title == "Title" and Config.Attr.TitleRank == "TitleRank", "titles config: Config.Attr.Title = 'Title', Config.Attr.TitleRank = 'TitleRank'",
		tostring(Config.Attr.Title) .. " / " .. tostring(Config.Attr.TitleRank))
	local rt = type(cfg) == "table" and cfg.RankTitles or nil
	T.check(deepEq(rt, RANK_TITLES), "titles config: Config.Leaderboard.RankTitles is spec 16.6's table",
		type(rt) == "table" and cfgDiff(rt, RANK_TITLES) or ("RankTitles is " .. type(rt)))
	if not T.check(type(LB) == "table" and type(LB.TitleOf) == "function" and type(LB._JoinForTest) == "function" and type(LB._S) == "table"
		and type(LB._S.Titles) == "table" and type(LB._S.Owner) == "table" and type(LB._S.TitleWrites) == "number"
		and type(Dev) == "table" and type(Dev.IsOwner) == "function" and type(cfg) == "table",
		"titles: LeaderboardService.TitleOf / _JoinForTest / _S.Titles / _S.Owner / _S.TitleWrites and DevService.IsOwner exist") then
		return
	end
	local Dst = DSt()
	local saved = {
		CreatorType = game.CreatorType, CreatorId = game.CreatorId, Admins = Config.Dev.Admins, Studio = Mock.Options.Studio,
		GroupRanks = Mock.GroupRanks, GroupRankFail = Mock.GroupRankFail, Trophies = Dst.Sorted[STORES.Trophies], Latency = Dst.Latency,
		Unavailable = Dst.Unavailable, OnJoin = Mock._onJoin,
	}
	local players, clone, conns = {}, nil, {}
	local function track(p)
		players[#players + 1] = p
		return p
	end
	local okRun, errRun = pcall(function()
		local errs0 = #Mock.Errors
		------------------------------------------------------------------------------------------------
		-- part 1: no store (the "Server" scope): no Top titles, Creator still
		------------------------------------------------------------------------------------------------
		local ownerId = newUserId()
		game.CreatorType = Enum.CreatorType.User
		game.CreatorId = ownerId
		Dst.Unavailable = true
		clone = newClone("LeaderboardServiceSmokeTitles")
		local okInit = clone ~= nil and clone.mod ~= nil and pcall(clone.mod.Init, { DataService = D, DevService = Dev })
		Dst.Unavailable = saved.Unavailable
		if T.check(okInit and clone.mod._S.NoStore == true and clone.mod.Scope() == "Server", "titles no store: (setup) a copy with no OrderedDataStore, Scope Server") then
			local C = clone.mod
			local q = track(join("LbTitleQ", newUserId()))
			local so = track(join("LbTitleOwnerS", ownerId))
			T.check(loaded(q) and D.AddTrophies(q, 500) == true, "titles no store: (setup) Q is loaded with 500 trophies")
			K.advance(cfg.FallbackRefresh + 1.5)
			local qRank = C.State(q).Stats.Trophies.You.Rank
			local kq, rq = C.TitleOf(q)
			T.check(qRank ~= nil and kq == nil and rq == nil and titleText(q) == "nil/nil/", "titles no store: a player ranked in this server's list (Server scope) gets no Top title",
				"server rank " .. tostring(qRank) .. ", TitleOf " .. tostring(kq) .. "/" .. tostring(rq) .. ", " .. titleText(q))
			local ko, ro = C.TitleOf(so)
			T.check(ko == "Creator" and ro == nil and titleText(so) == "Creator/nil/Creator", "titles no store: the owner still gets Creator (no TitleRank)",
				tostring(ko) .. "/" .. tostring(ro) .. ", " .. titleText(so))
			Mock.RemovePlayer(q)
			Mock.RemovePlayer(so)
		end
		dropClone(clone)
		clone = nil
		K.advance(1)

		------------------------------------------------------------------------------------------------
		-- part 2: the booted service over a 100-entry Trophies store: ranks 3 / 57 / outside
		------------------------------------------------------------------------------------------------
		local a = track(join("LbTitleA", newUserId()))
		local b = track(join("LbTitleB", newUserId()))
		local c = track(join("LbTitleC", newUserId()))
		T.check(titleText(a) == "nil/nil/" and titleText(b) == "nil/nil/", "titles: (setup) before the read none of them has a title", titleText(a) .. ", " .. titleText(b))
		fillTrophies({ [3] = a.UserId, [57] = b.UserId })
		T.check(readTrophiesNow(LB), "titles: (setup) the booted service read the 100-entry Trophies store")
		T.eq(titleText(a), "Top10/3/Top 10", "titles: rank 3 -> Title Top10, TitleRank 3, leaderstats.Rank 'Top 10'")
		T.eq(titleText(b), "Top100/57/Top 100", "titles: rank 57 -> Top100 / 57 / 'Top 100'")
		T.eq(titleText(c), "nil/nil/", "titles: outside the 100 -> no title, no TitleRank, Rank ''")
		local ka, ra = LB.TitleOf(a)
		local kc, rc = LB.TitleOf(c)
		T.check(ka == "Top10" and ra == 3 and kc == nil and rc == nil, "titles: TitleOf answers the kind and the rank (Top10 / 3; nil / nil)",
			tostring(ka) .. "/" .. tostring(ra) .. "; " .. tostring(kc) .. "/" .. tostring(rc))
		local rv = rankValue(a)
		T.check(statNames(a) == "Tokens,Rank" and rv ~= nil and rv:IsA("StringValue"), "titles: leaderstats holds Tokens then Rank (a StringValue)", statNames(a))

		------------------------------------------------------------------------------------------------
		-- part 3: the owner of a User game, an Admin who is not the owner, ranks moving, writes only on change
		------------------------------------------------------------------------------------------------
		local adminId = newUserId()
		Config.Dev.Admins = { adminId }
		local o = track(join("LbTitleOwner", ownerId))
		local d = track(join("LbTitleAdmin", adminId))
		T.eq(titleText(o), "Creator/nil/Creator", "titles: the owner of a User game (UserId == CreatorId) gets Creator at join")
		local isO, isD, allowD = Dev.IsOwner(o), Dev.IsOwner(d), Dev.IsAllowed(d)
		T.check(isO == true and isD == false and allowD == true, "titles: DevService.IsOwner: the owner true, an Admin false (IsAllowed still lets the Admin use the tools)",
			tostring(isO) .. " / " .. tostring(isD) .. " / " .. tostring(allowD))
		T.eq(titleText(d), "nil/nil/", "titles: an Admin who is not the owner gets no Creator")
		local count = {} -- [player] = Title / TitleRank attribute changes + Rank.Changed
		local function watch(p)
			count[p] = 0
			conns[#conns + 1] = p.AttributeChanged:Connect(function(name)
				if name == "Title" or name == "TitleRank" then
					count[p] = count[p] + 1
				end
			end)
			local v = rankValue(p)
			if v then
				conns[#conns + 1] = v.Changed:Connect(function()
					count[p] = count[p] + 1
				end)
			end
		end
		for _, p in ipairs({ a, b, c, o, d }) do
			watch(p)
		end
		local function counts()
			return string.format("A %d, B %d, C %d, owner %d, Admin %d", count[a], count[b], count[c], count[o], count[d])
		end
		fillTrophies({ [3] = ownerId, [5] = adminId, [12] = a.UserId, [57] = b.UserId })
		T.check(readTrophiesNow(LB), "titles: (setup) the next read")
		T.eq(titleText(o), "Creator/3/Creator", "titles: the owner at rank 3 stays Creator, with TitleRank 3")
		T.eq(titleText(a), "Top100/12/Top 100", "titles: the next read moves rank 3 to 12 -> Top100 / 12 / 'Top 100'")
		T.eq(titleText(d), "Top10/5/Top 10", "titles: the Admin at rank 5 -> Top10, not Creator")
		T.check(count[b] == 0 and count[c] == 0, "titles: no attribute or Rank write for the players whose title did not change (B at 57, C outside)", counts())
		T.check(count[o] == 1 and count[a] == 3 and count[d] == 3, "titles: ...and only the changed values written (owner: TitleRank; A, Admin: Title, TitleRank, Rank)", counts())
		local w0 = LB._S.TitleWrites
		local before = {}
		for p, n in pairs(count) do
			before[p] = n
		end
		T.check(readTrophiesNow(LB), "titles: (setup) a read with nothing changed")
		local same = true
		for p, n in pairs(count) do
			same = same and n == before[p]
		end
		T.check(LB._S.TitleWrites == w0 and same, "titles: a read with nothing changed writes nothing (S.TitleWrites, AttributeChanged, Rank.Changed)",
			"TitleWrites +" .. tostring(LB._S.TitleWrites - w0) .. "; " .. counts())
		fillTrophies({ [3] = ownerId, [5] = adminId, [57] = b.UserId })
		T.check(readTrophiesNow(LB), "titles: (setup) the read after that")
		T.eq(titleText(a), "nil/nil/", "titles: ...then A drops out of the 100 (3 -> 12 -> out) -> no title, Rank ''")

		-- Rank missing: the attributes at once, the text at the next pass after the 10 s wait
		local cls, crank = c:FindFirstChild("leaderstats"), rankValue(c)
		if T.check(cls ~= nil and crank ~= nil, "titles: (setup) C has leaderstats.Rank") then
			crank.Parent = nil
			fillTrophies({ [3] = ownerId, [5] = adminId, [20] = c.UserId, [57] = b.UserId })
			readTrophiesNow(LB)
			local k1, r1 = attrTitle(c)
			T.check(k1 == "Top100" and r1 == 20 and rankValue(c) == nil, "titles: with leaderstats.Rank missing the attributes are written at once (Top100 / 20)",
				tostring(k1) .. "/" .. tostring(r1))
			K.advance(11)
			crank.Parent = cls
			T.eq(crank.Value, "", "titles: ...the task waiting for Rank gives up after 10 s (a Rank put back later is not written by it)")
			readTrophiesNow(LB)
			T.eq(titleText(c), "Top100/20/Top 100", "titles: ...and the next pass writes the text")
			T.eq(statNames(c), "Tokens,Rank", "titles: ...LeaderboardService made no Rank of its own meanwhile")
		end

		------------------------------------------------------------------------------------------------
		-- part 4: a group game
		------------------------------------------------------------------------------------------------
		local G = 424242
		local gId = newUserId()
		Mock.GroupRanks = { [gId] = 255 }
		Mock.GroupRankFail = true
		game.CreatorType = Enum.CreatorType.Group
		game.CreatorId = G
		local g = track(join("LbTitleGroup", gId))
		T.check(not pcall(function()
			return g:GetRankInGroup(G)
		end), "titles mock: Player:GetRankInGroup errors while Mock.GroupRankFail")
		T.eq(titleText(g), "nil/nil/", "titles: a group game whose GetRankInGroup errors -> no title (and no error)")
		local isG = Dev.IsOwner(g)
		T.check(isG == nil, "titles: DevService.IsOwner answers nil when the group call failed", tostring(isG))
		Mock.Options.Studio = false
		local allowedG = Dev.IsAllowed(g)
		Mock.Options.Studio = saved.Studio
		T.check(allowedG == false, "titles: DevService.IsAllowed still answers a boolean (false) when the group call errors", tostring(allowedG) .. " (" .. type(allowedG) .. ")")
		Mock.GroupRankFail = false
		local rg, rc0 = g:GetRankInGroup(G), c:GetRankInGroup(G)
		T.check(rg == 255 and rc0 == 0, "titles mock: GetRankInGroup answers Mock.GroupRanks[userId], else 0", tostring(rg) .. " / " .. tostring(rc0))
		K.advance(10)
		T.eq(g:GetAttribute("Title"), nil, "titles: a failed owner answer is not asked again before the next Trophies refresh")
		T.check(readTrophiesNow(LB), "titles: (setup) the next Trophies refresh")
		T.eq(titleText(g), "Creator/nil/Creator", "titles: ...asked again at the next Trophies refresh -> Creator (group rank 255)")

		------------------------------------------------------------------------------------------------
		-- part 5: LeaderboardService's join handler run before PlayerService's
		------------------------------------------------------------------------------------------------
		game.CreatorType = Enum.CreatorType.User
		game.CreatorId = ownerId
		local eId = newUserId()
		fillTrophies({ [3] = ownerId, [5] = adminId, [8] = eId, [20] = c.UserId, [57] = b.UserId })
		T.check(readTrophiesNow(LB), "titles order: (setup) the store ranks the next player 8th")
		local atHand = "not run"
		local prevJoin = Mock._onJoin
		Mock._onJoin = function(p)
			if prevJoin then
				prevJoin(p)
			end
			if p.UserId == eId then
				local okJ, errJ = pcall(LB._JoinForTest, p)
				atHand = (not okJ and ("error " .. tostring(errJ))) or (p:FindFirstChild("leaderstats") and "made leaderstats") or "none"
			end
		end
		local e = track(Mock.AddPlayer("LbTitleEarly" .. tostring(eId % 1000), eId))
		Mock._onJoin = prevJoin
		T.eq(atHand, "none", "titles order: LeaderboardService's join handler, run by hand before PlayerService's, makes no leaderstats")
		local ke, re = attrTitle(e)
		T.check(ke == "Top10" and re == 8, "titles order: ...it sets the attributes at once (Top10 / 8)", tostring(ke) .. "/" .. tostring(re))
		K.advance(1.2)
		T.eq(statNames(e), "Tokens,Rank", "titles order: ...leaderstats still holds Tokens then Rank")
		T.eq(rankText(e), "Top 10", "titles order: ...and Rank holds the title's text once PlayerService made it")

		------------------------------------------------------------------------------------------------
		-- part 6: a player leaving while a Trophies read is in flight (Review Focus 5)
		------------------------------------------------------------------------------------------------
		Dst.Latency = 2
		local page = LB._S.Pages.Trophies
		page.DueAt = serverNow()
		K.advance(1.1)
		T.check(page.Reading == true, "titles churn: (setup) a Trophies read is in flight (the store takes 2 s)")
		Mock.RemovePlayer(b)
		K.advance(3)
		Dst.Latency = saved.Latency
		T.check(page.Reading ~= true and LB._S.Titles[b] == nil and LB._S.Owner[b] == nil,
			"titles churn: a player leaving while a Trophies read is in flight: S.Titles / S.Owner dropped and not made again by the refresh")
		T.check(LB._S.Titles[a] ~= nil and LB._S.Titles[o] ~= nil, "titles churn: ...the players still here keep their records")
		T.eq(#Mock.Errors, errs0, "titles: nothing raised")
	end)
	for _, conn in ipairs(conns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	dropClone(clone)
	Mock._onJoin = saved.OnJoin
	game.CreatorType = saved.CreatorType
	game.CreatorId = saved.CreatorId
	Config.Dev.Admins = saved.Admins
	Mock.Options.Studio = saved.Studio
	Mock.GroupRanks = saved.GroupRanks
	Mock.GroupRankFail = saved.GroupRankFail
	Dst.Latency = saved.Latency
	Dst.Unavailable = saved.Unavailable
	Dst.Sorted[STORES.Trophies] = saved.Trophies
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(1)
	pcall(readTrophiesNow, LB) -- the booted page back from the restored store
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("lb_titles")
	K.flushWarnings("lb_titles", ALLOWED_WARNINGS)
end)

return S
