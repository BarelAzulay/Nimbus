-- smoke_p5_data.lua: Phase 5 "Data" (ARCHITECTURE_V3.md "Phase 5 build contract" section 9: the schema additions, the
-- one-time P5 migrations of Phase 4 saves, the cross-server merge rules, the rollout with Phase 4 servers still running)
-- of server/Services/DataService.lua. Server world only (booted; listed in server_files of tools/smoke.py):
--   p5data_team3        a stored 4-key preset loads with 3 (4.8), TeamsChanged once, Cash / Gems / PetLevels / PetGrowth
--                       byte-equal before and after, the 4th pet still owned, SetTeam > 3 keys refused ("Teams have 3
--                       pets: a fighter and two helpers"), the merge of two sessions, the ProfileSync shape (Slots 3,
--                       Dungeon / Berries / Settings present)
--   p5data_evo_untouched  PetGrowth[key].Evo and the levels survive the P5 migrations byte-identical
--   p5dgn_data          the Dungeon record: defaults, MutateDungeon rules (Best never down, Cleared only grows, `first`,
--                       junk, rollback), the stored encoding (dense Cleared, left out while default), junk in the store
--                       cleaned, the merges against a REAL second server (Best max, Cleared union, Runs / Clears deltas,
--                       never below 0), provisional (Runs only), the synced record, ResetFields({ Dungeon })
--   p5dgn_migrate       a Phase 4 save with TrialBest 15 -> Best 5, Cleared 1-5, Clears 5, Runs 0, the marker, the
--                       Migrated signal + MigratedNow; every other stored field byte-identical; idempotent (a second
--                       load); TrialBest 0 / 1 / 2 / 30 -> 0 / 0 / 0 / 10; two servers migrating the same save do not
--                       double Clears (m15); it runs on ProfileRebased after a provisional load
--   p5data_berries      AddBerries / SpendBerries / GetBerries (whole numbers, flooring, junk, check-then-subtract), the
--                       Berries attribute (<= 2 writes/s, trailing), no ProfileSync on a Berries-only change (C14),
--                       the +/- delta merge clamped at 0 against a second server, stored only while > 0, provisional
--                       (Add allowed, Spend refused)
--   p5data_berries_merge  two servers converting ONE unmigrated Phase 4 save's Food into berries (the m15 twin: a store
--                       another server already marked P5Home holds its conversion, so the session's own is left out of
--                       the merge): A saves first / B first, later earns and spends, a failed save retried, the berries
--                       spent before any save, a provisional load recovering onto a migrated / an unmigrated store, and
--                       the rest of the fold (Berry Farm level, LegacyMagnet, DecorCredit) equal to a one-server fold
--   p5data_settings     per-key defaults, SetSetting validation (types, ranges, SeenNotes only up, the key whitelist),
--                       malformed stored settings, the SettingsSet remote (6/s burst 6; junk dropped), the live session
--                       wins the merge, left out of the store while default, always in the snapshot
--   p5home_fold_data    the P5Home step: without TycoonCatalog.FoldLegacy nothing runs and the marker stays unset (the
--                       step retries on the next load); with it (a stub when the economy's is not there yet) it is
--                       called once with firstTime = true inside one MutateHome, the marker is set in the same step,
--                       Food is converted to berries once (one Feast = 6400) and zeroed, removed station keys travel as
--                       `false`, a fold that errors marks nothing, a marked home with nothing to fold is left alone, a
--                       Phase 4 key sold after the marker is folded again (firstTime = false)
--   p5home_rollout      tools/fixtures/DataService_phase4.lua (the frozen Phase 4 release) as a second module on the
--                       same mock store saves a Phase 5 profile: Berries, Settings, Home.DecorCredit / LegacyMagnet /
--                       LegacyMagnetStar come back untouched, Press1 = 13 is not clamped on return, a 4-key preset it
--                       writes loads with 3 here
--   p5dgn_rollout       the same fixture keeps Dungeon and Migrations.P5*; a Trial clear it writes after the migration
--                       grows TrialBest without re-deriving the Dungeon
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance, mod, config = K.advance, K.mod, K.config

local S = {}

local FIXTURE = "DataService_phase4.lua"

local function count(map)
	local n = 0
	for _ in pairs(map or {}) do
		n = n + 1
	end
	return n
end

local function listText(list)
	local out = {}
	for i, v in ipairs(list or {}) do
		out[i] = tostring(v)
	end
	return "{" .. table.concat(out, ",") .. "}"
end

local function sameList(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function deepEqual(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
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

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepCopy(x)
	end
	return out
end

local function storeKey(userId)
	return config().Tokens.DataStoreName .. "/u_" .. userId
end

local function stored(userId)
	return Mock.DataStore.Data[storeKey(userId)]
end

local function statsOf()
	return { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} }
end

local function join(name, userId)
	local p = Mock.AddPlayer(name, userId)
	advance(1.0)
	return p
end

local function leave(players)
	K.removePlayers(players)
	advance(3)
end

local function lastSnapshot(player, fromIndex)
	local list = K.remotesFor("ProfileSync", player.UserId, fromIndex or 0)
	local e = list[#list]
	return e and e.args[1] or nil
end

local function syncCount(player, fromIndex)
	return #K.remotesFor("ProfileSync", player.UserId, fromIndex or 0)
end

-- the paths of every sparse array or mixed table inside a value (DataStores and remotes mangle both)
local function sparsePaths(value, path, out)
	out = out or {}
	if type(value) ~= "table" then
		return out
	end
	local numeric, other, top = 0, 0, 0
	for k in pairs(value) do
		if type(k) == "number" then
			numeric = numeric + 1
			if k > top then
				top = k
			end
		else
			other = other + 1
		end
	end
	if numeric > 0 and (other > 0 or top ~= numeric) then
		out[#out + 1] = path
	end
	for k, v in pairs(value) do
		sparsePaths(v, path .. "." .. tostring(k), out)
	end
	return out
end

-- `n` catalog pet ids (Common ones first, no event pets)
local function petIds(n)
	local PC = K.M["shared/PetCatalog"]
	local out = {}
	for _, pass in ipairs({ "Common", "other" }) do
		for _, def in ipairs(PC.Pets) do
			if #out >= n then
				break
			end
			local common = def.Rarity == "Common"
			if type(def.Id) == "string" and def.EventOnly ~= true and ((pass == "Common") == common) then
				out[#out + 1] = def.Id
			end
		end
	end
	return out
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

-- the frozen Phase 4 DataService as a second module ("a Phase 4 server"), or nil + reason
local function phase4Server()
	local src = nil
	for _, candidate in ipairs({ "tools/fixtures/" .. FIXTURE, "fixtures/" .. FIXTURE, "../tools/fixtures/" .. FIXTURE, "nimbus-climb/tools/fixtures/" .. FIXTURE }) do
		local fh = io.open(candidate, "r")
		if fh then
			src = fh:read("*a")
			fh:close()
			break
		end
	end
	if not src or #src < 1000 then
		return nil, "tools/fixtures/" .. FIXTURE .. " not found from the working directory"
	end
	local knownTop = string.match(src, "local KNOWN_TOP = (%b{})") or ""
	local knownHome = string.match(src, "local KNOWN_HOME = (%b{})") or ""
	T.check(knownTop ~= "" and not knownTop:find("Dungeon", 1, true) and not knownTop:find("Berries", 1, true) and not knownTop:find("Settings", 1, true),
		"p5 rollout: the fixture's KNOWN_TOP has no Dungeon / Berries / Settings (foreign keys to a Phase 4 server)")
	T.check(knownHome ~= "" and not knownHome:find("DecorCredit", 1, true) and not knownHome:find("LegacyMagnet", 1, true), "p5 rollout: ...nor DecorCredit / LegacyMagnet in its KNOWN_HOME")
	T.check(src:find("local function keepForeign", 1, true) ~= nil and src:find("MAX_SLOTS = 4", 1, true) ~= nil, "p5 rollout: ...and it has keepForeign and the Phase 4 4th team slot")
	local inst = K.moduleInstance("server/Services/DataService")
	local fixture = Instance.new("ModuleScript")
	fixture.Name = "DataServicePhase4Fixture"
	fixture.Source = src
	fixture.Parent = inst.Parent
	local marks = connectionMarks()
	local okReq, P4DS = pcall(require, fixture)
	if not okReq or type(P4DS) ~= "table" or type(P4DS.Load) ~= "function" then
		fixture:Destroy()
		dropHooks(marks)
		return nil, tostring(P4DS)
	end
	return P4DS, function()
		fixture:Destroy()
		return dropHooks(marks)
	end
end

-- counts Migrated firings while connected
local function migratedWatcher(DataS)
	local fired = {}
	local conn = DataS.Migrated and DataS.Migrated:Connect(function(who, name, info)
		fired[#fired + 1] = { who = who, name = name, info = info }
	end)
	return {
		mark = function()
			return #fired
		end,
		since = function(p, mark, name)
			local out = {}
			for i = mark + 1, #fired do
				if fired[i].who == p and (name == nil or fired[i].name == name) then
					out[#out + 1] = fired[i]
				end
			end
			return out
		end,
		stop = function()
			if conn then
				conn:Disconnect()
			end
		end,
	}
end

local function teamsWatcher(DataS)
	local fired = {}
	local conn = DataS.TeamsChanged:Connect(function(who)
		fired[#fired + 1] = who
	end)
	return {
		mark = function()
			return #fired
		end,
		since = function(p, mark)
			local n = 0
			for i = mark + 1, #fired do
				if fired[i] == p then
					n = n + 1
				end
			end
			return n
		end,
		stop = function()
			if conn then
				conn:Disconnect()
			end
		end,
	}
end

local function homeOf(prestige, extra)
	local h = { Level = 0, Prestige = prestige or 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0, LastSeen = 0 }
	for k, v in pairs(extra or {}) do
		h[k] = v
	end
	return h
end

-- a canonical Phase 4 record (already P4-migrated; every map in its stored shape) with `extra` fields replacing
local function phase4Record(ids, extra)
	local a, b, c, d = ids[1], ids[2], ids[3], ids[4]
	local rec = {
		Version = 2, Tokens = 10, Pets = { [a] = 1, [b] = 1, [c] = 1, [d] = 1 }, Equipped = { b }, Items = {}, Stats = statsOf(),
		Discovered = { [a] = true, [b] = true, [c] = true, [d] = true }, IndexClaimed = {}, Tutorial = { Step = 19, Done = false, Gifted = true },
		Cash = 777, Gems = 3,
		Home = { Level = 9, Prestige = 1, Stations = { Press1 = 5, Garden = 6, Kitchen = 1 }, Garden = { a, b }, Gym = {}, CollectorCash = 500, LastSeen = 1700000000, LegacySlots = 6, LegacyPrices = true },
		PetLevels = { [a] = { Level = 57, Xp = 500 }, [b] = { Level = 100, Xp = 0 }, [d] = { Level = 33, Xp = 10 } },
		Teams = { Presets = { { b, c } }, Active = 1 },
		Battle = { Trophies = 40, TrialBest = 15, TrialCleared = { true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }, Raids = 2, RaidBestDamage = 900, PvPWins = 3, PvPLosses = 1, EventPets = {} },
		PetGrowth = { [a] = { Evo = 1, Speed = 3 }, [b] = { Evo = 2, Speed = 10, Physique = 10, Ability = 10, Defense = 10 }, [d] = { Evo = 1 } },
		Ring = { Best = 21, Runs = 4 },
		Migrations = { P4 = true },
	}
	for k, v in pairs(extra or {}) do
		rec[k] = v
	end
	return rec
end

local function dungeonText(d)
	if type(d) ~= "table" then
		return tostring(d)
	end
	local floors = {}
	for f, v in pairs(d.Cleared or {}) do
		floors[#floors + 1] = tostring(f) .. "=" .. tostring(v)
	end
	table.sort(floors)
	return "{Best " .. tostring(d.Best) .. " Runs " .. tostring(d.Runs) .. " Clears " .. tostring(d.Clears) .. " Cleared " .. table.concat(floors, ",") .. "}"
end

local function clearedSet(d)
	local out = {}
	for f, v in pairs(d and d.Cleared or {}) do
		if v == true then
			out[tonumber(f) or f] = true
		end
	end
	return out
end

local function floorsExactly(d, n)
	local set = clearedSet(d)
	if count(set) ~= n then
		return false
	end
	for f = 1, n do
		if not set[f] then
			return false
		end
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- scenario: Teams of 3
----------------------------------------------------------------------------------------------------
S.p5data_team3 = guarded("p5data_team3", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local data = Mock.DataStore.Data
	local ids = petIds(6)
	local a, b, c, d, e, f = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]
	local UID = 955001
	local rec = phase4Record(ids, {
		Pets = { [a] = 1, [b] = 1, [c] = 1, [d] = 1, [e] = 1, [f] = 1 },
		Teams = { Presets = { { a, b, c, d }, { e, f } }, Active = 1 },
	})
	data[storeKey(UID)] = rec
	local before = deepCopy(rec)
	local watch = teamsWatcher(DataS)
	local m0 = watch.mark()
	local p = join("P5Team3", UID)
	local teams = DataS.GetTeams(p)
	T.check(type(teams) == "table" and teams.Slots == 3 and sameList(teams.Presets[1], { a, b, c }) and sameList(teams.Presets[2], { e, f }) and teams.Active == 1,
		"p5 team3: a stored 4-key preset loads with its first 3 keys (slot 1 = the fighter); Slots is 3", listText((teams or {}).Presets and teams.Presets[1]))
	T.eq(watch.since(p, m0), 1, "p5 team3: TeamsChanged fired exactly once on that load")
	local prof = DataS.GetProfile(p)
	T.check(prof.Pets[d] == 1 and prof.Cash == before.Cash and prof.Gems == before.Gems and deepEqual(prof.PetLevels, before.PetLevels),
		"p5 team3: the 4th pet is still owned; Cash / Gems / PetLevels are byte-equal to the stored save")
	T.check(DataS.GetGrowth(p, d).Evo == 1 and DataS.GetGrowth(p, a).Speed == 3 and DataS.GetGrowth(p, b).Evo == 2, "p5 team3: PetGrowth (Evo, ranks) is untouched")
	local ok, why = DataS.SetTeam(p, 2, { a, b, c, d })
	T.check(ok == false and why == "Teams have 3 pets: a fighter and two helpers", "p5 team3: SetTeam with 4 keys is refused with 'Teams have 3 pets: a fighter and two helpers'", tostring(why))
	ok, why = DataS.SetTeam(p, 2, { a, "", "", d })
	T.check(ok == false and why == "Teams have 3 pets: a fighter and two helpers", "p5 team3: ...a key alone in slot 4 too", tostring(why))
	ok, why = DataS.SetTeam(p, 2, { d, b, a, "" })
	T.check(ok == true and sameList(DataS.GetTeams(p).Presets[2], { d, b, a }), "p5 team3: 3 keys (an empty 4th) are accepted; the 4th pet of the old preset can be the fighter of another", tostring(why))
	T.check(DataS.SetTeam(p, 1, { a, b, c }) == true, "p5 team3: (precondition) preset 1 set to a, b, c")
	-- a Prestige no longer unlocks anything
	T.check(DataS.MutateHome(p, function(home)
		home.Prestige = 3
	end) == true and DataS.GetTeams(p).Slots == 3, "p5 team3: Slots stays 3 at Prestige 3 (the prestige unlock is gone)")
	ok, why = DataS.SetTeam(p, 3, { e, f, c, a })
	T.check(ok == false and type(why) == "string" and why:find("3 pets", 1, true) ~= nil, "p5 team3: ...and 4 keys are still refused there", tostring(why))
	-- the snapshot shape
	local mark = K.logSize()
	DataS.Sync(p)
	local snap = lastSnapshot(p, mark)
	T.check(type(snap) == "table" and snap.Teams.Slots == 3 and sameList(snap.Teams.Presets[1], { a, b, c }) and type(snap.Dungeon) == "table" and type(snap.Dungeon.Cleared) == "table"
		and type(snap.Berries) == "number" and type(snap.Settings) == "table" and snap.Settings.Music == 6 and snap.Settings.Gfx == "Auto",
		"p5 team3: ProfileSync carries Teams (Slots 3), Dungeon, Berries and Settings")
	T.eq(#sparsePaths(snap, "snapshot"), 0, "p5 team3: ...with no sparse array anywhere in it", table.concat(sparsePaths(snap, "snapshot"), " "))
	-- two sessions: each saves its own preset
	local B, cloneB, releaseB = secondServer("DataServiceP5TeamB")
	if T.check(B ~= nil and type(B.SetTeam) == "function", "p5 team3: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		T.eq(DataS.Save(p), true, "p5 team3: server A saves its presets")
		local okB, errB = pcall(function()
			B.Load(p)
			T.check(B.GetTeams(p) ~= nil and B.GetTeams(p).Slots == 3 and sameList(B.GetTeams(p).Presets[1], { a, b, c }), "p5 team3: server B reads 3 slots and A's preset 1")
			T.check(DataS.SetTeam(p, 1, { b, c, a }) == true and B.SetTeam(p, 3, { f }) == true, "p5 team3: A rotates preset 1 (b is the fighter now), B sets preset 3")
			T.check(DataS.Save(p) == true and B.Save(p) == true, "p5 team3: both save")
			local st = (stored(UID) or {}).Teams or {}
			T.check(type(st.Presets) == "table" and sameList(st.Presets[1], { b, c, a }) and sameList(st.Presets[3], { f }) and sameList(st.Presets[2], { d, b, a }),
				"p5 team3: the store holds A's preset 1 and B's preset 3 (per-preset merge)", listText(st.Presets and st.Presets[1]) .. listText(st.Presets and st.Presets[3]))
		end)
		releaseB()
		if not okB then
			error(errB, 0)
		end
	end
	local st = stored(UID) or {}
	T.check(st.Pets[d] == 1 and deepEqual(st.PetLevels, before.PetLevels) and st.Cash == before.Cash and st.Gems == before.Gems and deepEqual(st.PetGrowth, before.PetGrowth),
		"p5 team3: after the saves the store still holds the 4th pet, every level, Cash, Gems and PetGrowth as before")
	watch.stop()
	leave({ p })
	K.flushErrors("p5data_team3")
	K.flushWarnings("p5data_team3", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: evolution stages untouched
----------------------------------------------------------------------------------------------------
S.p5data_evo_untouched = guarded("p5data_evo_untouched", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local data = Mock.DataStore.Data
	local ids = petIds(4)
	local a, b, d = ids[1], ids[2], ids[4]
	local UID = 955002
	local rec = phase4Record(ids)
	data[storeKey(UID)] = rec
	local growthBefore = deepCopy(rec.PetGrowth)
	local levelsBefore = deepCopy(rec.PetLevels)
	local p = join("P5EvoKeep", UID)
	T.check(DataS.IsMigrated(p, "P5Dungeon") == true, "p5 evo: (precondition) the P5 migrations ran on this load")
	T.check(DataS.GetGrowth(p, a).Evo == 1 and DataS.GetGrowth(p, b).Evo == 2 and DataS.GetGrowth(p, d).Evo == 1 and DataS.GetEvolution(p, b) == 2,
		"p5 evo: PetGrowth[key].Evo is untouched by the migrations (1 / 2 / 1)")
	T.check((DataS.GetPetLevel(p, a)) == 57 and (DataS.GetPetLevel(p, b)) == 100 and select(2, DataS.GetPetLevel(p, a)) == 500, "p5 evo: the levels and XP are untouched")
	DataS.AddTokens(p, 1)
	T.eq(DataS.Save(p), true, "p5 evo: the session saves")
	local st = stored(UID) or {}
	T.check(deepEqual(st.PetGrowth, growthBefore) and deepEqual(st.PetLevels, levelsBefore), "p5 evo: the stored PetGrowth and PetLevels are byte-identical after the save")
	leave({ p })
	K.flushErrors("p5data_evo_untouched")
	K.flushWarnings("p5data_evo_untouched", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the Dungeon record
----------------------------------------------------------------------------------------------------
S.p5dgn_data = guarded("p5dgn_data", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local DSt = Mock.DataStore
	local data = DSt.Data
	T.check(type(DataS.GetDungeon) == "function" and type(DataS.MutateDungeon) == "function", "p5 dungeon: GetDungeon / MutateDungeon exist")
	local UID = 955101
	local p = join("P5DgnNew", UID)
	local d = DataS.GetDungeon(p)
	T.check(type(d) == "table" and d.Best == 0 and d.Runs == 0 and d.Clears == 0 and count(d.Cleared) == 0, "p5 dungeon: a new profile's record is { 0, {}, 0, 0 }", dungeonText(d))
	T.check(DataS.IsMigrated(p, "P5Dungeon") == true and DataS.MigratedNow(p, "P5Dungeon") ~= nil and DataS.MigratedNow(p, "P5Dungeon").Best == 0,
		"p5 dungeon: a new profile is marked P5Dungeon at its first load (Best 0: nothing to credit)")
	DataS.AddTokens(p, 1)
	T.eq(DataS.Save(p), true, "p5 dungeon: (the first save)")
	local st = stored(UID) or {}
	T.check(st.Dungeon == nil and st.Berries == nil and st.Settings == nil, "p5 dungeon: a default Dungeon / 0 Berries / default Settings are left out of the store")
	-- MutateDungeon
	local ok, first = DataS.MutateDungeon(p, function(rec)
		rec.Cleared[1] = true
		rec.Clears = rec.Clears + 1
		rec.Runs = rec.Runs + 1
	end)
	d = DataS.GetDungeon(p)
	T.check(ok == true and first == true and d.Best == 1 and d.Cleared[1] == true and d.Clears == 1 and d.Runs == 1, "p5 dungeon: a first clear of floor 1 -> ok, first = true, Best 1", dungeonText(d))
	ok, first = DataS.MutateDungeon(p, function(rec)
		rec.Cleared[1] = true
		rec.Runs = rec.Runs + 1
	end)
	T.check(ok == true and first == false and DataS.GetDungeon(p).Runs == 2, "p5 dungeon: clearing floor 1 again -> first = false (Runs counts)")
	ok, first = DataS.MutateDungeon(p, function(rec)
		rec.Best = 0
		rec.Cleared[1] = nil
	end)
	d = DataS.GetDungeon(p)
	T.check(ok == true and first == false and d.Best == 1 and d.Cleared[1] == true, "p5 dungeon: Best never goes down and Cleared only grows", dungeonText(d))
	ok, first = DataS.MutateDungeon(p, function(rec)
		rec.Cleared[3] = true
		rec.Clears = rec.Clears + 1
	end)
	d = DataS.GetDungeon(p)
	T.check(ok == true and first == true and d.Best == 3 and d.Cleared[3] == true and d.Cleared[2] == nil and d.Clears == 2, "p5 dungeon: floor 3 cleared -> Best 3 (floor 2 stays open)", dungeonText(d))
	ok = DataS.MutateDungeon(p, function(rec)
		rec.Cleared["x"] = true
		rec.Cleared[0] = true
		rec.Cleared[2.5] = true
		rec.Cleared[101] = true
		rec.Runs = -5
		rec.Clears = 2.7
		rec.Best = 1e12
	end)
	d = DataS.GetDungeon(p)
	T.check(ok == true and count(d.Cleared) == 2 and d.Runs == 0 and d.Clears == 2 and d.Best == 100, "p5 dungeon: junk floors dropped, Runs clamped at 0, Clears whole, Best <= 100", dungeonText(d))
	local before = DataS.GetDungeon(p)
	ok = DataS.MutateDungeon(p, function(rec)
		rec.Cleared[7] = true
		error("boom")
	end)
	T.check(ok == false and deepEqual(DataS.GetDungeon(p), before), "p5 dungeon: an erroring fn restores the record")
	ok = DataS.MutateDungeon(p, function(rec)
		rec.Cleared[8] = true
		return false
	end)
	T.check(ok == false and deepEqual(DataS.GetDungeon(p), before), "p5 dungeon: fn returning false restores the record")
	T.check(DataS.MutateDungeon(nil, function() end) == false and DataS.MutateDungeon(p, "x") == false and DataS.GetDungeon(nil) == nil, "p5 dungeon: the API refuses a nil player / a non-function")
	-- the snapshot and the store
	local mark = K.logSize()
	DataS.Sync(p)
	local snap = lastSnapshot(p, mark)
	T.check(type(snap) == "table" and type(snap.Dungeon) == "table" and snap.Dungeon.Best == 100 and snap.Dungeon.Cleared[1] == true and snap.Dungeon.Cleared[2] == false and snap.Dungeon.Cleared[3] == true and #snap.Dungeon.Cleared == 3,
		"p5 dungeon: the synced record carries Cleared as a dense boolean array", dungeonText(snap and snap.Dungeon))
	T.eq(DataS.Save(p), true, "p5 dungeon: the record saves")
	st = stored(UID) or {}
	T.check(type(st.Dungeon) == "table" and st.Dungeon.Best == 100 and #st.Dungeon.Cleared == 3 and st.Dungeon.Cleared[2] == false and st.Dungeon.Runs == 0 and st.Dungeon.Clears == 2 and #sparsePaths(st.Dungeon, "Dungeon") == 0,
		"p5 dungeon: the stored record is dense too", dungeonText(st.Dungeon))
	-- ResetFields({ Dungeon }) beats the max / union merge
	local live = DataS.GetProfile(p).Dungeon
	live.Best, live.Runs, live.Clears = 0, 0, 0
	for k in pairs(live.Cleared) do
		live.Cleared[k] = nil
	end
	T.eq(DataS.ResetFields(p, { Dungeon = true }), true, "p5 dungeon: ResetFields({ Dungeon }) is accepted")
	DataS.MarkDirty(p)
	T.eq(DataS.Save(p), true, "p5 dungeon: ...and saves")
	st = stored(UID) or {}
	T.check(st.Dungeon == nil and DataS.GetDungeon(p).Best == 0, "p5 dungeon: the reset record is written over the store (Best max / Cleared union do not bring it back)", dungeonText(st.Dungeon))
	leave({ p })

	-- junk in the store is cleaned on load
	local JUNK = 955102
	local ids = petIds(2)
	data[storeKey(JUNK)] = phase4Record(petIds(4), { Battle = nil, Dungeon = { Best = "x", Cleared = { [1] = true, [7] = true, [8] = "yes", x = true }, Runs = -3, Clears = 2.5 }, Migrations = { P4 = true, P5Dungeon = true } })
	local j = join("P5DgnJunk", JUNK)
	d = DataS.GetDungeon(j)
	T.check(d.Best == 7 and d.Cleared[1] == true and d.Cleared[7] == true and count(d.Cleared) == 2 and d.Runs == 0 and d.Clears == 2, "p5 dungeon: junk in the store is cleaned (Best >= the highest cleared floor, whole numbers >= 0)", dungeonText(d))
	leave({ j })

	-- the merges against a REAL second server
	local B, cloneB, releaseB = secondServer("DataServiceP5DgnB")
	if T.check(B ~= nil and type(B.MutateDungeon) == "function", "p5 dungeon: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		local TWO = 955103
		data[storeKey(TWO)] = phase4Record(petIds(4), { Dungeon = { Best = 2, Cleared = { true, true }, Runs = 1, Clears = 2 }, Migrations = { P4 = true, P5Dungeon = true } })
		local okB, errB = pcall(function()
			local tp = join("P5DgnTwo", TWO)
			B.Load(tp)
			T.check(DataS.GetDungeon(tp).Best == 2 and B.GetDungeon(tp).Best == 2, "p5 two servers: both hold the stored record (Best 2)")
			T.check(DataS.MutateDungeon(tp, function(rec)
				rec.Cleared[3] = true
				rec.Clears = rec.Clears + 1
				rec.Runs = rec.Runs + 1
			end) == true and B.MutateDungeon(tp, function(rec)
				rec.Cleared[4] = true
				rec.Clears = rec.Clears + 1
				rec.Runs = rec.Runs + 2
			end) == true, "p5 two servers: A clears floor 3, B clears floor 4 (each a run)")
			T.check(DataS.Save(tp) == true and B.Save(tp) == true, "p5 two servers: both save")
			local sd = (stored(TWO) or {}).Dungeon or {}
			T.check(sd.Best == 4 and floorsExactly(sd, 4) and sd.Runs == 4 and sd.Clears == 4, "p5 two servers: the store holds Best 4 (max), Cleared 1-4 (union), Runs 1 + 1 + 2, Clears 2 + 1 + 1", dungeonText(sd))
			DataS.AddTokens(tp, 1)
			T.eq(DataS.Save(tp), true, "p5 two servers: A saves a token (it adopts the store)")
			advance(0.3)
			T.check(DataS.GetDungeon(tp).Best == 4 and DataS.GetDungeon(tp).Cleared[4] == true and B.GetDungeon(tp) and B.GetDungeon(tp).Cleared[3] == true,
				"p5 two servers: both read the union back", dungeonText(DataS.GetDungeon(tp)) .. " / " .. dungeonText(B.GetDungeon(tp)))
			-- never below 0: both drop Runs to 0 (a -4 each)
			T.check(DataS.MutateDungeon(tp, function(rec)
				rec.Runs = 0
			end) == true and B.MutateDungeon(tp, function(rec)
				rec.Runs = 0
			end) == true and DataS.Save(tp) == true and B.Save(tp) == true, "p5 two servers: both zero Runs")
			sd = (stored(TWO) or {}).Dungeon or {}
			T.check(sd.Runs == 0 and sd.Best == 4, "p5 two servers: Runs never goes below 0 in the merge", dungeonText(sd))
			leave({ tp })
		end)
		releaseB()
		if not okB then
			error(errB, 0)
		end
	end

	-- provisional: Runs only
	local PV = 955104
	data[storeKey(PV)] = phase4Record(petIds(4), { Dungeon = { Best = 3, Cleared = { true, true, true }, Runs = 2, Clears = 3 }, Migrations = { P4 = true, P5Dungeon = true } })
	DSt.Fail = true
	local v = Mock.AddPlayer("P5DgnOutage", PV)
	advance(4)
	T.check(DataS.IsProvisional(v) == true, "p5 dungeon: (precondition) the outage makes the profile provisional")
	T.check(DataS.GetDungeon(v) == nil, "p5 dungeon: GetDungeon is nil while provisional")
	local okP, why = DataS.MutateDungeon(v, function(rec)
		rec.Cleared[1] = true
	end)
	T.check(okP == false and why == "Your save is still loading", "p5 dungeon: a first clear is refused while provisional: 'Your save is still loading'", tostring(why))
	okP = DataS.MutateDungeon(v, function(rec)
		rec.Runs = rec.Runs + 1
	end)
	T.check(okP == true and DataS.GetProfile(v).Dungeon.Runs == 1, "p5 dungeon: Runs may change while provisional")
	DSt.Fail = false
	local recovered = K.waitFor(function()
		return not DataS.IsProvisional(v)
	end, 40)
	T.check(recovered, "p5 dungeon: (the recovery reads the real save)")
	advance(1)
	d = DataS.GetDungeon(v)
	T.check(d ~= nil and d.Best == 3 and floorsExactly(d, 3) and d.Runs == 3 and d.Clears == 3, "p5 dungeon: after the recovery the stored record is intact and the provisional run joined it (Runs 2 + 1)", dungeonText(d))
	leave({ v })
	K.flushErrors("p5dgn_data")
	K.flushWarnings("p5dgn_data", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the P5Dungeon migration
----------------------------------------------------------------------------------------------------
S.p5dgn_migrate = guarded("p5dgn_migrate", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local DSt = Mock.DataStore
	local data = DSt.Data
	local ids = petIds(4)
	local watch = migratedWatcher(DataS)
	local UID = 955201
	local rec = phase4Record(ids)
	data[storeKey(UID)] = rec
	local before = deepCopy(rec)
	local m0 = watch.mark()
	local p = join("P5DgnMigrate", UID)
	local d = DataS.GetDungeon(p)
	T.check(d ~= nil and d.Best == 5 and floorsExactly(d, 5) and d.Clears == 5 and d.Runs == 0, "p5 migrate: TrialBest 15 -> Best 5, Cleared 1-5 (exactly), Clears 5, Runs 0", dungeonText(d))
	T.eq(DataS.IsMigrated(p, "P5Dungeon"), true, "p5 migrate: Migrations.P5Dungeon is set")
	local fired = watch.since(p, m0, "P5Dungeon")
	local info = DataS.MigratedNow(p, "P5Dungeon")
	T.check(#fired == 1 and type(fired[1].info) == "table" and fired[1].info.Best == 5 and fired[1].info.TrialBest == 15 and type(info) == "table" and info.Best == 5,
		"p5 migrate: Migrated(player, 'P5Dungeon', { TrialBest 15, Best 5 }) fired once; MigratedNow answers it")
	T.check(DataS.GetBattle(p).TrialBest == 15 and count(DataS.GetBattle(p).TrialCleared) == 15 and DataS.GetCash(p) == 777 and DataS.GetGems(p) == 3 and DataS.GetTokens(p) == 10,
		"p5 migrate: TrialBest / TrialCleared are kept; no Cash, Gems or Tokens change")
	T.eq(DataS.Save(p), true, "p5 migrate: the migrated profile saves")
	local st = stored(UID) or {}
	-- (Teams is re-encoded with its two empty presets and Tutorial belongs to TutorialService at the join: checked apart)
	-- The same load runs the P5Home step (9.2 step 3) on this Phase 4 home: its ONLY allowed effect is the fold itself
	-- (here Press1 5 -> the Berry Farm food floor), so the expected Home is the stored one put through
	-- TycoonCatalog.FoldLegacy(home, true) (p5home_fold_data proves the fold); this record holds no Food, so no Berries.
	-- Without FoldLegacy the step is skipped and the Home must be untouched.
	local TCat = K.M["shared/TycoonCatalog"]
	local expected = deepCopy(before)
	local folds = TCat and type(TCat.FoldLegacy) == "function"
	if folds then
		TCat.FoldLegacy(expected.Home, true)
	end
	local differs = {}
	for key, value in pairs(expected) do
		if key ~= "Migrations" and key ~= "Teams" and key ~= "Tutorial" and not deepEqual(st[key], value) then
			differs[#differs + 1] = key
		end
	end
	for key in pairs(st) do
		if expected[key] == nil and key ~= "Dungeon" and key ~= "UpdatedAt" then
			differs[#differs + 1] = "+" .. key
		end
	end
	-- the fold never touches anything but Home.Stations (and the folded credits): every other Home key byte-identical
	local homeDiffers = {}
	local sth = type(st.Home) == "table" and st.Home or {}
	for key, value in pairs(before.Home) do
		if key ~= "Stations" and not deepEqual(sth[key], value) then
			homeDiffers[#homeDiffers + 1] = key
		end
	end
	for id, lv in pairs(before.Home.Stations) do
		if id ~= "Press1" and (type(sth.Stations) ~= "table" or sth.Stations[id] ~= lv) then
			homeDiffers[#homeDiffers + 1] = "Stations." .. id
		end
	end
	local farm = type(sth.Stations) == "table" and sth.Stations.Press1 or nil
	T.check(#differs == 0, "p5 migrate: every other stored field is byte-identical (only Dungeon, Migrations.P5Dungeon / P5Home, UpdatedAt and the P5Home fold of the Home changed)", table.concat(differs, ", "))
	T.check(#homeDiffers == 0 and type(farm) == "number" and farm >= before.Home.Stations.Press1 and (st.Migrations or {}).P5Home == (folds and true or nil),
		"p5 migrate: ...the P5Home fold changed only the Berry Farm level (never lower), every other Home key and station is byte-identical; P5Home marked with the fold",
		table.concat(homeDiffers, ", ") .. " Press1 " .. tostring(farm))
	T.check(type(st.Teams) == "table" and sameList(st.Teams.Presets[1], before.Teams.Presets[1]) and st.Teams.Active == 1 and type(st.Tutorial) == "table" and st.Tutorial.Gifted == true,
		"p5 migrate: ...the preset and the tutorial gift are kept too")
	T.check(type(st.Migrations) == "table" and st.Migrations.P4 == true and st.Migrations.P5Dungeon == true and type(st.Dungeon) == "table" and st.Dungeon.Clears == 5 and #st.Dungeon.Cleared == 5,
		"p5 migrate: the store holds both markers and the dense record")
	-- idempotent: a second load
	leave({ p })
	m0 = watch.mark()
	p = join("P5DgnMigrate", UID)
	d = DataS.GetDungeon(p)
	T.check(d.Best == 5 and d.Clears == 5 and floorsExactly(d, 5) and DataS.MigratedNow(p, "P5Dungeon") == nil and #watch.since(p, m0, "P5Dungeon") == 0,
		"p5 migrate: the second load changes nothing (no signal, MigratedNow nil, Clears still 5)", dungeonText(d))
	DataS.AddTokens(p, 1)
	DataS.Save(p)
	T.eq(((stored(UID) or {}).Dungeon or {}).Clears, 5, "p5 migrate: ...and its save keeps Clears 5")
	leave({ p })

	-- TrialBest 0 / 1 / 2 / 30 -> 0 / 0 / 0 / 10
	local cases = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 30, 10 }, { 3, 1 }, { 18, 6 }, { 60, 10 } }
	local bad = {}
	for i, case in ipairs(cases) do
		local uid = 955210 + i
		local cleared = {}
		for f = 1, case[1] do
			cleared[f] = true
		end
		data[storeKey(uid)] = phase4Record(ids, { Battle = { Trophies = 0, TrialBest = case[1], TrialCleared = cleared, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} } })
		local q = join("P5DgnCase" .. i, uid)
		local dq = DataS.GetDungeon(q)
		if not (dq.Best == case[2] and floorsExactly(dq, case[2]) and dq.Clears == case[2] and DataS.IsMigrated(q, "P5Dungeon") == true) then
			bad[#bad + 1] = "TrialBest " .. case[1] .. " -> " .. dungeonText(dq)
		end
		leave({ q })
	end
	T.check(#bad == 0, "p5 migrate: TrialBest 0 / 1 / 2 / 30 / 3 / 18 / 60 -> Best 0 / 0 / 0 / 10 / 1 / 6 / 10 (floor(TrialBest / 3), at most 10; marker always set)", table.concat(bad, "; "))

	-- two servers migrate the same save: Clears is not doubled (m15)
	local B, cloneB, releaseB = secondServer("DataServiceP5MigB")
	if T.check(B ~= nil and type(B.GetDungeon) == "function", "p5 migrate: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		local TWO = 955230
		data[storeKey(TWO)] = phase4Record(ids)
		local okB, errB = pcall(function()
			local tp = join("P5MigTwo", TWO)
			B.Load(tp)
			T.check(DataS.GetDungeon(tp).Clears == 5 and B.GetDungeon(tp).Clears == 5 and B.MigratedNow(tp, "P5Dungeon") ~= nil, "p5 migrate two servers: both servers migrated the same unmigrated save (Clears 5 each)")
			T.check(DataS.Save(tp) == true and B.Save(tp) == true, "p5 migrate two servers: both save")
			local sd = (stored(TWO) or {}).Dungeon or {}
			T.check(sd.Clears == 5 and sd.Best == 5 and floorsExactly(sd, 5), "p5 migrate two servers: the store holds Clears 5 (not 10), Best 5, Cleared 1-5", dungeonText(sd))
			advance(0.3)
			T.check(DataS.GetDungeon(tp).Clears == 5 and B.GetDungeon(tp).Clears == 5, "p5 migrate two servers: both read Clears 5 back")
			-- a real first clear after that counts once
			local okC, first = DataS.MutateDungeon(tp, function(rec)
				rec.Cleared[6] = true
				rec.Clears = rec.Clears + 1
				rec.Runs = rec.Runs + 1
			end)
			T.check(okC == true and first == true and DataS.Save(tp) == true, "p5 migrate two servers: server A clears floor 6 for the first time and saves")
			sd = (stored(TWO) or {}).Dungeon or {}
			T.check(sd.Clears == 6 and sd.Best == 6 and sd.Runs == 1, "p5 migrate two servers: the store holds Clears 6, Best 6, Runs 1", dungeonText(sd))
			T.check(B.Save(tp) == true and ((stored(TWO) or {}).Dungeon or {}).Clears == 6, "p5 migrate two servers: B's next save (nothing new) leaves Clears 6")
			leave({ tp })
		end)
		releaseB()
		if not okB then
			error(errB, 0)
		end
	end

	-- provisional: the migration waits for the real save (ProfileRebased)
	local PV = 955240
	data[storeKey(PV)] = phase4Record(ids)
	DSt.Fail = true
	local m3 = watch.mark()
	local pv = Mock.AddPlayer("P5DgnOutageVet", PV)
	advance(4)
	T.check(DataS.IsProvisional(pv) == true and DataS.IsMigrated(pv, "P5Dungeon") == nil and DataS.MigratedNow(pv, "P5Dungeon") == nil and #watch.since(pv, m3, "P5Dungeon") == 0,
		"p5 migrate: a provisional profile is not migrated (stand-in defaults; no signal)")
	DSt.Fail = false
	local recovered = K.waitFor(function()
		return not DataS.IsProvisional(pv)
	end, 40)
	T.check(recovered, "p5 migrate: (the recovery reads the real save)")
	advance(1)
	d = DataS.GetDungeon(pv)
	T.check(#watch.since(pv, m3, "P5Dungeon") == 1 and d ~= nil and d.Best == 5 and d.Clears == 5 and DataS.IsMigrated(pv, "P5Dungeon") == true,
		"p5 migrate: ...it runs on the recovery (ProfileRebased): one signal, Best 5, the marker", dungeonText(d))
	T.eq(DataS.Save(pv), true, "p5 migrate: ...and saves")
	T.eq(((stored(PV) or {}).Dungeon or {}).Clears, 5, "p5 migrate: ...Clears 5 in the store")
	leave({ pv })
	watch.stop()
	K.flushErrors("p5dgn_migrate")
	K.flushWarnings("p5dgn_migrate", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: berries
----------------------------------------------------------------------------------------------------
S.p5data_berries = guarded("p5data_berries", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local Config = config()
	local DSt = Mock.DataStore
	local data = DSt.Data
	local ATTR = Config.Attr.Berries
	T.check(type(DataS.GetBerries) == "function" and type(DataS.AddBerries) == "function" and type(DataS.SpendBerries) == "function" and ATTR == "Berries",
		"p5 berries: GetBerries / AddBerries / SpendBerries exist; Config.Attr.Berries = 'Berries'")
	local UID = 955301
	local p = join("P5Berries", UID)
	T.check(DataS.GetBerries(p) == 0 and p:GetAttribute(ATTR) == 0, "p5 berries: a new profile has 0 berries and the attribute is 0 after the load")
	local mark = K.logSize()
	T.check(DataS.AddBerries(p, 10) == true and DataS.GetBerries(p) == 10, "p5 berries: AddBerries(10) -> 10")
	T.eq(p:GetAttribute(ATTR), 10, "p5 berries: the first attribute write goes out at once")
	T.check(DataS.AddBerries(p, 0.9) == false and DataS.AddBerries(p, 2.7) == true and DataS.GetBerries(p) == 12, "p5 berries: amounts are floored (0.9 -> refused, 2.7 -> +2)")
	T.check(DataS.AddBerries(p, -1) == false and DataS.AddBerries(p, 0 / 0) == false and DataS.AddBerries(p, 1 / 0) == false and DataS.AddBerries(p, "5") == false and DataS.AddBerries(nil, 5) == false and DataS.GetBerries(p) == 12,
		"p5 berries: junk amounts / a nil player are refused and change nothing")
	-- the attribute throttle: <= 2 writes/s, trailing
	T.eq(p:GetAttribute(ATTR), 10, "p5 berries: the later adds within the same half second have not written the attribute yet (trailing write)")
	advance(0.6)
	T.eq(p:GetAttribute(ATTR), 12, "p5 berries: ...it catches up at the end of the window (12)")
	T.eq(syncCount(p, mark), 0, "p5 berries: a Berries-only change never triggers a ProfileSync (C14)")
	T.check(DataS.SpendBerries(p, 13) == false and DataS.GetBerries(p) == 12, "p5 berries: spending more than owned is refused (nothing taken)")
	T.check(DataS.SpendBerries(p, 0) == false and DataS.SpendBerries(p, -3) == false and DataS.SpendBerries(p, 0 / 0) == false and DataS.GetBerries(p) == 12, "p5 berries: junk spends are refused")
	T.check(DataS.SpendBerries(p, 12) == true and DataS.GetBerries(p) == 0 and DataS.SpendBerries(p, 1) == false, "p5 berries: SpendBerries(12) empties the basket; one more is refused")
	advance(0.6)
	T.eq(p:GetAttribute(ATTR), 0, "p5 berries: the attribute follows the spend")
	-- the store: left out while 0, present while > 0
	T.eq(DataS.Save(p), true, "p5 berries: saves with 0 berries")
	T.eq((stored(UID) or {}).Berries, nil, "p5 berries: 0 berries are left out of the store")
	DataS.AddBerries(p, 250)
	T.eq(DataS.Save(p), true, "p5 berries: saves with 250")
	T.eq((stored(UID) or {}).Berries, 250, "p5 berries: ...stored as a whole number")
	-- the snapshot carries it
	mark = K.logSize()
	DataS.Sync(p)
	T.eq((lastSnapshot(p, mark) or {}).Berries, 250, "p5 berries: ProfileSync carries Berries")
	leave({ p })

	-- the merge: a +/- delta clamped at 0
	local B, cloneB, releaseB = secondServer("DataServiceP5BerryB")
	if T.check(B ~= nil and type(B.SpendBerries) == "function", "p5 berries: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		local TWO = 955302
		data[storeKey(TWO)] = phase4Record(petIds(4), { Berries = 100, Migrations = { P4 = true, P5Dungeon = true } })
		local okB, errB = pcall(function()
			local tp = join("P5BerryTwo", TWO)
			B.Load(tp)
			T.check(DataS.GetBerries(tp) == 100 and B.GetBerries(tp) == 100, "p5 berries two servers: both read 100")
			T.check(DataS.AddBerries(tp, 50) == true and B.SpendBerries(tp, 80) == true and DataS.Save(tp) == true and B.Save(tp) == true, "p5 berries two servers: A adds 50, B spends 80, both save")
			T.eq((stored(TWO) or {}).Berries, 70, "p5 berries two servers: the store holds 100 + 50 - 80 = 70")
			DataS.AddTokens(tp, 1)
			T.eq(DataS.Save(tp), true, "p5 berries two servers: A saves a token (it adopts the store)")
			advance(0.3)
			T.check(DataS.GetBerries(tp) == 70 and B.GetBerries(tp) == 70, "p5 berries two servers: both read 70 back", tostring(DataS.GetBerries(tp)) .. "/" .. tostring(B.GetBerries(tp)))
			T.check(DataS.SpendBerries(tp, 70) == true and B.SpendBerries(tp, 70) == true and DataS.Save(tp) == true and B.Save(tp) == true, "p5 berries two servers: both spend the same 70 (a race)")
			T.eq((stored(TWO) or {}).Berries, nil, "p5 berries two servers: the store clamps at 0 (never negative: the race costs at most one feed)")
			leave({ tp })
		end)
		releaseB()
		if not okB then
			error(errB, 0)
		end
	end

	-- provisional: Add allowed, Spend refused
	local PV = 955303
	data[storeKey(PV)] = phase4Record(petIds(4), { Berries = 40, Migrations = { P4 = true, P5Dungeon = true } })
	DSt.Fail = true
	local v = Mock.AddPlayer("P5BerryOutage", PV)
	advance(4)
	T.check(DataS.IsProvisional(v) == true, "p5 berries: (precondition) the outage makes the profile provisional")
	T.check(DataS.AddBerries(v, 5) == true and DataS.GetBerries(v) == 5, "p5 berries: AddBerries is allowed while provisional (a + delta merges safely)")
	T.check(DataS.SpendBerries(v, 1) == false and DataS.GetBerries(v) == 5, "p5 berries: SpendBerries is refused while provisional")
	DSt.Fail = false
	local recovered = K.waitFor(function()
		return not DataS.IsProvisional(v)
	end, 40)
	T.check(recovered, "p5 berries: (the recovery reads the real save)")
	advance(1)
	T.eq(DataS.GetBerries(v), 45, "p5 berries: after the recovery the stored 40 and the provisional +5 are both there")
	leave({ v })
	K.flushErrors("p5data_berries")
	K.flushWarnings("p5data_berries", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: two servers converting one Phase 4 save's Food into berries (the m15 twin, every interleaving)
----------------------------------------------------------------------------------------------------
-- the store (the real mock DataStore record) and its Home, both never nil
local function storedBerries(uid)
	return (stored(uid) or {}).Berries or 0
end

S.p5data_berries_merge = guarded("p5data_berries_merge", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local DSt = Mock.DataStore
	local data = DSt.Data
	local TC = K.M["shared/TycoonCatalog"]
	if not T.check(type(TC) == "table" and type(TC.FoldLegacy) == "function", "p5 berry merge: (precondition) TycoonCatalog.FoldLegacy exists (the real P5Home fold)") then
		return
	end
	local ids = petIds(4)
	local FOOD = { Snack = 1, Meal = 1 } -- 200 + 1200 = 1400 berries once
	local CONV = 1400
	local B, cloneB, releaseB = secondServer("DataServiceP5BerryMergeB")
	if not T.check(B ~= nil and type(B.AddBerries) == "function", "p5 berry merge: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	local okRun, errRun = pcall(function()
		-- 1. both load the unmigrated save; A saves first, B (which migrated before A's save) saves later; then both
		--    earn / spend and save again; a third save of each
		local ONE = 955601
		data[storeKey(ONE)] = phase4Record(ids, { Food = FOOD })
		local p = join("P5BerryMergeOne", ONE)
		B.Load(p)
		T.check(DataS.GetBerries(p) == CONV and B.GetBerries(p) == CONV and DataS.IsMigrated(p, "P5Home") == true and B.IsMigrated(p, "P5Home") == true,
			"p5 berry merge: both servers converted the same Snack + Meal (1400 berries each, both marked)", tostring(DataS.GetBerries(p)) .. "/" .. tostring(B.GetBerries(p)))
		T.check(DataS.AddBerries(p, 50) == true and DataS.Save(p) == true, "p5 berry merge: A adds 50 and saves first")
		T.eq(storedBerries(ONE), CONV + 50, "p5 berry merge: the store holds 1400 + 50")
		T.check(DataS.AddBerries(p, 5) == true and DataS.Save(p) == true and storedBerries(ONE) == CONV + 55, "p5 berry merge: A's second save (+5) lands on top (1455): its conversion is not subtracted again")
		T.check(B.AddBerries(p, 100) == true and B.Save(p) == true, "p5 berry merge: B adds 100 and saves after A")
		T.eq(storedBerries(ONE), CONV + 155, "p5 berry merge: the store holds 1400 + 55 + 100 = 1555, NOT 2955 (B's own conversion is left out: the store already held one)")
		advance(0.3)
		T.check(DataS.GetBerries(p) == CONV + 55 and B.GetBerries(p) == CONV + 155, "p5 berry merge: A still sees 1455 (it has not read the store), B adopted 1555")
		-- A earns 10 and spends 60 after the merge: its next save adopts the store and lands only the +10 - 60
		T.check(DataS.AddBerries(p, 10) == true and DataS.SpendBerries(p, 60) == true and DataS.Save(p) == true, "p5 berry merge: A earns 10, spends 60, saves (its third save)")
		T.eq(storedBerries(ONE), CONV + 105, "p5 berry merge: the store holds 1555 + 10 - 60 = 1505")
		advance(0.3)
		T.check(DataS.GetBerries(p) == CONV + 105, "p5 berry merge: A adopted the merged berries (1505)", tostring(DataS.GetBerries(p)))
		T.check(B.SpendBerries(p, 500) == true and B.Save(p) == true and storedBerries(ONE) == CONV + 105 - 500, "p5 berry merge: B spends 500 and saves: 1005 (a plain delta now)")
		T.check(B.Save(p) == true and DataS.Save(p) == true and storedBerries(ONE) == CONV + 105 - 500, "p5 berry merge: empty saves of both change nothing")
		T.check((stored(ONE) or {}).Food == nil, "p5 berry merge: the Food is gone from the store (converted once)")
		leave({ p })

		-- 2. the other order: B saves first (nothing but its migration), A (loaded before B's save) saves +0 after a
		--    failed attempt (the DataStore down; the migration's part stays pending until a save lands)
		local TWO = 955602
		data[storeKey(TWO)] = phase4Record(ids, { Food = FOOD })
		p = join("P5BerryMergeTwo", TWO)
		B.Load(p)
		T.check(B.Save(p) == true and storedBerries(TWO) == CONV, "p5 berry merge: B saves its migration first (1400)")
		DSt.Fail = true
		T.check(DataS.Save(p) == false, "p5 berry merge: A's save fails while the DataStore is down")
		DSt.Fail = false
		T.check(DataS.Save(p) == true and storedBerries(TWO) == CONV, "p5 berry merge: A's retried save lands: the store still holds 1400 (not 2800)")
		advance(0.3)
		T.check(DataS.GetBerries(p) == CONV and B.GetBerries(p) == CONV, "p5 berry merge: both read 1400")
		leave({ p })

		-- 3. the player spent the converted berries on A before anyone saved: B's conversion lands, A's spend lands
		local THREE = 955603
		data[storeKey(THREE)] = phase4Record(ids, { Food = FOOD })
		p = join("P5BerryMergeThree", THREE)
		B.Load(p)
		T.check(DataS.SpendBerries(p, CONV) == true and DataS.GetBerries(p) == 0, "p5 berry merge: A's player spends all 1400 converted berries before any save")
		T.check(B.Save(p) == true and storedBerries(THREE) == CONV, "p5 berry merge: B saves first (1400)")
		T.check(DataS.Save(p) == true and storedBerries(THREE) == 0, "p5 berry merge: A's save takes the 1400 the player spent: the store holds 0 (never 1400 again, never negative)")
		leave({ p })

		-- 4. a provisional load on A (the DataStore down) recovers onto a store B already migrated: no second conversion
		local FOUR = 955604
		data[storeKey(FOUR)] = phase4Record(ids, { Food = FOOD })
		local q = Mock.AddPlayer("P5BerryMergeFour", FOUR)
		advance(1.0)
		B.Load(q)
		T.check(B.GetBerries(q) == CONV and B.Save(q) == true and storedBerries(FOUR) == CONV, "p5 berry merge: B migrated and saved (1400) while A...")
		leave({ q })
		DSt.Fail = true
		q = Mock.AddPlayer("P5BerryMergeFour", FOUR)
		advance(4)
		T.check(DataS.IsProvisional(q) == true and DataS.GetBerries(q) == 0 and DataS.IsMigrated(q, "P5Home") ~= true, "p5 berry merge: ...loads provisionally (0 berries, no migration on a stand-in)")
		T.check(DataS.AddBerries(q, 5) == true, "p5 berry merge: the provisional session earns 5 berries")
		DSt.Fail = false
		T.check(K.waitFor(function()
			return not DataS.IsProvisional(q)
		end, 40), "p5 berry merge: (the recovery reads the real save)")
		advance(1)
		T.check(DataS.GetBerries(q) == CONV + 5 and DataS.MigratedNow(q, "P5Home") == nil, "p5 berry merge: the recovery adopts B's 1400 + the 5 (no second conversion: the store was marked)", tostring(DataS.GetBerries(q)))
		T.check(DataS.Save(q) == true and storedBerries(FOUR) == CONV + 5, "p5 berry merge: ...and saves 1405")
		leave({ q })

		-- 5. a provisional load on A whose recovery reads the UNMIGRATED save (A converts on ProfileRebased) while
		--    B loaded the same save meanwhile and holds its own conversion in memory (no leave: B's PlayerRemoving
		--    hook would save it)
		local FIVE = 955605
		data[storeKey(FIVE)] = phase4Record(ids, { Food = FOOD })
		DSt.Fail = true
		q = Mock.AddPlayer("P5BerryMergeFive", FIVE)
		advance(4)
		T.check(DataS.IsProvisional(q) == true and DataS.AddBerries(q, 7) == true, "p5 berry merge: A loads provisionally (the DataStore down) and earns 7")
		DSt.Fail = false
		B.Load(q)
		T.check(B.GetBerries(q) == CONV and B.IsMigrated(q, "P5Home") == true, "p5 berry merge: B loads the same unmigrated save and converts it in memory (1400)")
		T.check(storedBerries(FIVE) == 0 and ((stored(FIVE) or {}).Migrations or {}).P5Home == nil, "p5 berry merge: (precondition) the store is still the unmigrated Phase 4 save")
		T.check(K.waitFor(function()
			return not DataS.IsProvisional(q)
		end, 40), "p5 berry merge: (the recovery reads the unmigrated save)")
		advance(1)
		T.check(DataS.GetBerries(q) == CONV + 7 and DataS.IsMigrated(q, "P5Home") == true, "p5 berry merge: A converts on the recovery (1400 + 7, marked)", tostring(DataS.GetBerries(q)))
		local afterRecovery = storedBerries(FIVE)
		T.check(afterRecovery == 0 or afterRecovery == CONV + 7, "p5 berry merge: the store holds the Phase 4 save or A's recovered save (1407), nothing else", tostring(afterRecovery))
		T.check(DataS.Save(q) == true and B.Save(q) == true and DataS.Save(q) == true and storedBerries(FIVE) == CONV + 7,
			"p5 berry merge: A saves, B saves its in-memory conversion, A saves again: the store holds 1407 (one conversion + the 7)", tostring(storedBerries(FIVE)))
		advance(0.3)
		T.check(B.GetBerries(q) == CONV + 7, "p5 berry merge: B adopted 1407", tostring(B.GetBerries(q)))
		leave({ q })

		-- 6. the rest of the fold is idempotent across two servers: the Berry Farm level, LegacyMagnet, DecorCredit
		--    and the removed keys equal what ONE server's fold stores
		local function oldHome()
			return { Level = 12, Prestige = 1, Stations = { Press1 = 6, Press2 = 4, Press3 = 2, Collector = 3, Garden = 6, DecorFlowers = 2, DecorLamps = 2, DecorFence = 1 }, Garden = { ids[1] }, Gym = {}, CollectorCash = 500, LastSeen = 1700000000 }
		end
		local SOLO, DUO = 955606, 955607
		data[storeKey(SOLO)] = phase4Record(ids, { Home = oldHome(), Food = FOOD })
		data[storeKey(DUO)] = phase4Record(ids, { Home = oldHome(), Food = FOOD })
		local ps = join("P5BerryMergeSolo", SOLO)
		T.check(DataS.Save(ps) == true, "p5 berry merge: one server folds the old home and saves")
		leave({ ps })
		local pd = join("P5BerryMergeDuo", DUO)
		B.Load(pd)
		T.check(DataS.Save(pd) == true and B.Save(pd) == true and DataS.AddBerries(pd, 1) == true and DataS.Save(pd) == true, "p5 berry merge: two servers fold the same old home and both save (A twice)")
		local sh, dh = (stored(SOLO) or {}).Home or {}, (stored(DUO) or {}).Home or {}
		local diffs = {}
		for _, key in ipairs({ "Level", "Prestige", "DecorCredit", "LegacyMagnet", "LegacyMagnetStar" }) do
			if sh[key] ~= dh[key] then
				diffs[#diffs + 1] = key .. " " .. tostring(sh[key]) .. "/" .. tostring(dh[key])
			end
		end
		local stationsSame = deepEqual(sh.Stations, dh.Stations)
		local function homeText(h)
			local keys, out = {}, {}
			for k in pairs(h) do
				keys[#keys + 1] = k
			end
			table.sort(keys)
			for _, k in ipairs(keys) do
				local v = h[k]
				if k == "Stations" then
					local sk, parts = {}, {}
					for id in pairs(v) do
						sk[#sk + 1] = id
					end
					table.sort(sk)
					for _, id in ipairs(sk) do
						parts[#parts + 1] = id .. "=" .. tostring(v[id])
					end
					v = "{" .. table.concat(parts, ",") .. "}"
				elseif type(v) == "table" then
					v = "#" .. tostring(#v)
				end
				out[#out + 1] = k .. "=" .. tostring(v)
			end
			return table.concat(out, " ")
		end
		T.check(#diffs == 0 and stationsSame and dh.Stations.Press2 == nil and dh.Stations.Press3 == nil and dh.Stations.Collector == nil and dh.Stations.DecorFlowers == nil and dh.Stations.DecorLamps == nil and (dh.DecorCredit or 0) > 0 and dh.LegacyMagnet == 3,
			"p5 berry merge: the two-server fold stores the same Level / Stations / DecorCredit / LegacyMagnet(Star) as the one-server fold (per-key replace, nothing doubled)",
			table.concat(diffs, "; ") .. (stationsSame and "" or " stations differ") .. " solo[" .. homeText(sh) .. "] duo[" .. homeText(dh) .. "]")
		T.check(storedBerries(DUO) == storedBerries(SOLO) + 1, "p5 berry merge: ...and the berries of the two-server save are the one-server conversion + 1")
		leave({ pd })
	end)
	T.check(releaseB() == true, "p5 berry merge: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p5data_berries_merge")
	K.flushWarnings("p5data_berries_merge", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: settings
----------------------------------------------------------------------------------------------------
S.p5data_settings = guarded("p5data_settings", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local data = Mock.DataStore.Data
	T.check(type(DataS.GetSettings) == "function" and type(DataS.SetSetting) == "function", "p5 settings: GetSettings / SetSetting exist")
	local UID = 955401
	local p = join("P5Settings", UID)
	local s = DataS.GetSettings(p)
	T.check(type(s) == "table" and s.Music == 6 and s.Sfx == 8 and s.Gfx == "Auto" and s.Shake == true and s.SeenNotes == 0, "p5 settings: the defaults are { 6, 8, 'Auto', true, 0 }")
	T.eq(DataS.Save(p), true, "p5 settings: (a save)")
	T.eq((stored(UID) or {}).Settings, nil, "p5 settings: default settings are left out of the store")
	local okAll = DataS.SetSetting(p, "Music", 3) and DataS.SetSetting(p, "Sfx", 10) and DataS.SetSetting(p, "Gfx", "Low") and DataS.SetSetting(p, "Shake", false) and DataS.SetSetting(p, "SeenNotes", 5)
	s = DataS.GetSettings(p)
	T.check(okAll == true and s.Music == 3 and s.Sfx == 10 and s.Gfx == "Low" and s.Shake == false and s.SeenNotes == 5, "p5 settings: SetSetting stores every valid key")
	local bad = {}
	for _, case in ipairs({
		{ "Music", 11 }, { "Music", -1 }, { "Music", 2.5 }, { "Music", "3" }, { "Music", 0 / 0 }, { "Sfx", 1 / 0 }, { "Gfx", "Ultra" }, { "Gfx", 1 },
		{ "Shake", 1 }, { "Shake", "true" }, { "SeenNotes", 4 }, { "SeenNotes", 1001 }, { "SeenNotes", 5.5 }, { "Volume", 3 }, { 3, 3 }, { nil, 3 }, { "Music", nil },
	}) do
		if DataS.SetSetting(p, case[1], case[2]) ~= false then
			bad[#bad + 1] = tostring(case[1]) .. "=" .. tostring(case[2])
		end
	end
	s = DataS.GetSettings(p)
	T.check(#bad == 0 and s.Music == 3 and s.Sfx == 10 and s.Gfx == "Low" and s.Shake == false and s.SeenNotes == 5, "p5 settings: junk keys / types / ranges and a lower SeenNotes are refused and change nothing", table.concat(bad, ", "))
	T.check(DataS.SetSetting(p, "SeenNotes", 5) == true and DataS.SetSetting(p, "SeenNotes", 9) == true and DataS.GetSettings(p).SeenNotes == 9, "p5 settings: SeenNotes only goes up (equal is fine)")
	T.check(DataS.SetSetting(nil, "Music", 1) == false, "p5 settings: a nil player is refused")
	T.eq(DataS.Save(p), true, "p5 settings: saves")
	local st = (stored(UID) or {}).Settings
	T.check(type(st) == "table" and st.Music == 3 and st.Sfx == 10 and st.Gfx == "Low" and st.Shake == false and st.SeenNotes == 9 and count(st) == 5, "p5 settings: the store holds the five keys")
	-- the snapshot always has them
	local mark = K.logSize()
	DataS.Sync(p)
	local snap = lastSnapshot(p, mark)
	T.check(type(snap) == "table" and type(snap.Settings) == "table" and snap.Settings.Gfx == "Low" and snap.Settings.Shake == false, "p5 settings: ProfileSync carries Settings")
	-- the SettingsSet remote
	local folder = K.remoteFolder and K.remoteFolder()
	local remote = folder and folder:FindFirstChild("SettingsSet")
	if T.check(remote ~= nil, "p5 settings: the SettingsSet remote exists (Config.Remotes)") then
		Mock.FromClient(remote, p, "Music", 2)
		T.eq(DataS.GetSettings(p).Music, 2, "p5 settings: SettingsSet('Music', 2) from the client lands")
		Mock.FromClient(remote, p, "Music", 99)
		Mock.FromClient(remote, p, "Gfx", { "Low" })
		Mock.FromClient(remote, p, 42, 1)
		Mock.FromClient(remote, p)
		T.eq(DataS.GetSettings(p).Music, 2, "p5 settings: junk through the remote is dropped silently")
		-- the rate limit: 6/s with a burst of 6 (the bucket already paid 5 calls above)
		advance(2)
		local landed = 0
		for i = 1, 20 do
			Mock.FromClient(remote, p, "Sfx", i % 11)
			if DataS.GetSettings(p).Sfx == i % 11 then
				landed = landed + 1
			end
		end
		T.check(landed >= 5 and landed <= 7, "p5 settings: 20 rapid SettingsSet calls land about 6 (the burst), the rest are dropped", "landed " .. landed)
		advance(1.1)
		Mock.FromClient(remote, p, "Sfx", 4)
		T.eq(DataS.GetSettings(p).Sfx, 4, "p5 settings: a second later the bucket refilled and the next call lands")
	end
	leave({ p })

	-- malformed stored settings: per-key defaults
	local JUNK = 955402
	data[storeKey(JUNK)] = phase4Record(petIds(4), { Settings = { Music = 99, Sfx = "x", Gfx = "Mega", Shake = "yes", SeenNotes = -3 }, Migrations = { P4 = true, P5Dungeon = true } })
	local j = join("P5SettingsJunk", JUNK)
	s = DataS.GetSettings(j)
	T.check(s.Music == 6 and s.Sfx == 8 and s.Gfx == "Auto" and s.Shake == true and s.SeenNotes == 0, "p5 settings: malformed stored values fall back per key")
	data[storeKey(JUNK + 1)] = phase4Record(petIds(4), { Settings = { Music = 1, Sfx = "x" }, Migrations = { P4 = true, P5Dungeon = true } })
	leave({ j })
	j = join("P5SettingsHalf", JUNK + 1)
	s = DataS.GetSettings(j)
	T.check(s.Music == 1 and s.Sfx == 8 and s.Gfx == "Auto", "p5 settings: a partial stored table keeps its valid keys and defaults the rest")
	leave({ j })

	-- the merge: the live session wins
	local B, cloneB, releaseB = secondServer("DataServiceP5SetB")
	if T.check(B ~= nil and type(B.SetSetting) == "function", "p5 settings: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		local TWO = 955403
		data[storeKey(TWO)] = phase4Record(petIds(4), { Settings = { Music = 6, Sfx = 8, Gfx = "High", Shake = true, SeenNotes = 2 }, Migrations = { P4 = true, P5Dungeon = true } })
		local okB, errB = pcall(function()
			local tp = join("P5SetTwo", TWO)
			B.Load(tp)
			T.check(DataS.SetSetting(tp, "Music", 1) == true and DataS.Save(tp) == true, "p5 settings two servers: A sets Music 1 and saves")
			T.check(B.SetSetting(tp, "Sfx", 2) == true and B.Save(tp) == true, "p5 settings two servers: B (which still has Music 6) sets Sfx 2 and saves")
			local ss = (stored(TWO) or {}).Settings or {}
			T.check(ss.Music == 6 and ss.Sfx == 2 and ss.Gfx == "High", "p5 settings two servers: the live session (B) wins whole: Music 6, Sfx 2 (not progress: no merge)", tostring(ss.Music) .. "/" .. tostring(ss.Sfx))
			DataS.AddTokens(tp, 1)
			T.check(DataS.Save(tp) == true, "p5 settings two servers: A saves a token")
			advance(0.3)
			T.check(DataS.GetSettings(tp).Sfx == 2 and DataS.GetSettings(tp).Music == 6, "p5 settings two servers: A adopts the stored settings on its next save (no change of its own)")
			leave({ tp })
		end)
		releaseB()
		if not okB then
			error(errB, 0)
		end
	end
	K.flushErrors("p5data_settings")
	K.flushWarnings("p5data_settings", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the P5Home step (the fold call + Food -> berries)
----------------------------------------------------------------------------------------------------
S.p5home_fold_data = guarded("p5home_fold_data", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local data = Mock.DataStore.Data
	local TC = K.M["shared/TycoonCatalog"]
	if not T.check(type(TC) == "table", "p5 fold: TycoonCatalog loads") then
		return
	end
	local ids = petIds(4)
	local realFold = rawget(TC, "FoldLegacy")
	local watch = migratedWatcher(DataS)
	local function oldHome()
		return { Level = 12, Prestige = 1, Stations = { Press1 = 6, Press2 = 4, Collector = 3, Garden = 6, Flowers = 2, Fence = 1 }, Garden = { ids[1] }, Gym = {}, CollectorCash = 500, LastSeen = 1700000000 }
	end
	local okRun, errRun = pcall(function()
		-- 1. without FoldLegacy: nothing runs, the marker stays unset, Food and Berries untouched
		TC.FoldLegacy = nil
		local NOFOLD = 955501
		data[storeKey(NOFOLD)] = phase4Record(ids, { Home = oldHome(), Food = { Feast = 1, Snack = 2 } })
		local m0 = watch.mark()
		local p = join("P5NoFold", NOFOLD)
		local home = DataS.GetHome(p)
		T.check(DataS.IsMigrated(p, "P5Home") == false and DataS.MigratedNow(p, "P5Home") == nil and #watch.since(p, m0, "P5Home") == 0, "p5 fold: without TycoonCatalog.FoldLegacy the P5Home step is skipped (no marker, no signal)")
		T.check(home.Stations.Press2 == 4 and home.Stations.Collector == 3 and DataS.GetFood(p, "Feast") == 1 and DataS.GetBerries(p) == 0, "p5 fold: ...the old stations, the Food and the berries are untouched")
		T.check(DataS.IsMigrated(p, "P5Dungeon") == true, "p5 fold: ...while the P5Dungeon step ran (the steps are independent)")
		leave({ p })
		T.check((stored(NOFOLD) or {}).Food ~= nil and (stored(NOFOLD) or {}).Food.Feast == 1 and ((stored(NOFOLD) or {}).Migrations or {}).P5Home == nil, "p5 fold: ...and the store still holds the Food, no P5Home marker")

		-- 2. a stub fold (the economy's real one is tested in smoke_p5_home.lua): the shape of the contract 9.2 step 3
		local calls = {}
		TC.FoldLegacy = function(home, firstTime)
			calls[#calls + 1] = { firstTime = firstTime, press2 = home.Stations.Press2 }
			local changed = false
			local sum = 0
			local any = false
			for i = 1, 4 do
				local key = "Press" .. i
				local level = home.Stations[key]
				if type(level) == "number" then
					sum = sum + math.min(level, 10)
					if i > 1 then
						any = true
						home.Stations[key] = nil
					end
				end
			end
			if any or firstTime then
				local level = math.min(40, sum)
				if level ~= home.Stations.Press1 then
					home.Stations.Press1 = level > 0 and level or nil
					changed = true
				end
			end
			local magnet = home.Stations.Collector
			if type(magnet) == "number" and magnet > 0 then
				home.LegacyMagnet = math.max(home.LegacyMagnet or 0, magnet)
				home.LegacyMagnetStar = home.Prestige
				home.Stations.Collector = nil
				changed = true
			end
			local flowers = home.Stations.Flowers or 0
			if flowers > 0 then
				local fence = home.Stations.Fence or 0
				home.Stations.Fence = math.max(fence, flowers)
				home.DecorCredit = (home.DecorCredit or 0) + math.min(fence, flowers)
				home.Stations.Flowers = nil
				changed = true
			end
			return changed or any
		end
		local FOLD = 955502
		data[storeKey(FOLD)] = phase4Record(ids, { Home = oldHome(), Food = { Feast = 1, Snack = 2 } })
		m0 = watch.mark()
		p = join("P5Fold", FOLD)
		home = DataS.GetHome(p)
		T.check(#calls >= 1 and calls[#calls].firstTime == true, "p5 fold: FoldLegacy was called with firstTime = true on the first load", tostring(#calls))
		local mutating = 0
		for _, c in ipairs(calls) do
			if c.press2 ~= nil then
				mutating = mutating + 1
			end
		end
		T.check(mutating <= 2, "p5 fold: ...at most twice (a pure probe on a copy, then once inside MutateHome)", tostring(#calls))
		T.check(home.Stations.Press1 == 10 and home.Stations.Press2 == nil and home.Stations.Collector == nil and home.Stations.Flowers == nil and home.Stations.Fence == 2 and home.LegacyMagnet == 3 and home.LegacyMagnetStar == 1 and home.DecorCredit == 1,
			"p5 fold: the live home is folded (Press1 10, no Press2 / Collector / Flowers, Fence 2, LegacyMagnet 3 @ star 1, DecorCredit 1)")
		T.check(DataS.IsMigrated(p, "P5Home") == true, "p5 fold: Migrations.P5Home is set in the same step")
		local fired = watch.since(p, m0, "P5Home")
		local info = DataS.MigratedNow(p, "P5Home")
		T.check(#fired == 1 and type(info) == "table" and info.FirstTime == true and info.Folded == true and info.Berries == 6800 and info.Food.Feast == 1 and info.Food.Snack == 2 and info.Veteran == true,
			"p5 fold: Migrated(player, 'P5Home', info) fired once; MigratedNow has { FirstTime, Folded, Berries 6800, Food, Veteran }")
		T.check(DataS.GetBerries(p) == 6800 and DataS.GetFood(p, "Feast") == 0 and DataS.GetFood(p, "Snack") == 0 and count(DataS.GetFood(p)) == 0, "p5 fold: one Feast + two Snacks = 6400 + 400 = 6800 berries; Food is zeroed")
		T.check(p:GetAttribute("Berries") == 6800, "p5 fold: the Berries attribute follows at once")
		T.check(DataS.GetCash(p) == 777 and DataS.GetGems(p) == 3, "p5 fold: no Cash or Gems are paid by the migration")
		T.eq(DataS.Save(p), true, "p5 fold: the folded profile saves")
		local st = stored(FOLD) or {}
		local sh = st.Home or {}
		T.check(sh.Stations.Press1 == 10 and sh.Stations.Press2 == nil and sh.Stations.Collector == nil and sh.Stations.Flowers == nil and sh.Stations.Fence == 2 and sh.Stations.Garden == 6,
			"p5 fold: the removed keys travelled as `false` (gone in the store); Press1 / Fence / Garden hold their levels")
		T.check(sh.LegacyMagnet == 3 and sh.LegacyMagnetStar == 1 and sh.DecorCredit == 1 and st.Berries == 6800 and st.Food == nil and (st.Migrations or {}).P5Home == true,
			"p5 fold: the store holds LegacyMagnet 3 @ 1, DecorCredit 1, Berries 6800, no Food, the marker")
		-- idempotent: a second load with nothing to fold -> the fold is only probed, nothing changes, no signal
		leave({ p })
		local n0 = #calls
		m0 = watch.mark()
		p = join("P5Fold", FOLD)
		T.check(#calls == n0 + 1 and calls[#calls].firstTime == false, "p5 fold: the second load probes the fold once with firstTime = false", tostring(#calls - n0))
		T.check(DataS.GetBerries(p) == 6800 and DataS.MigratedNow(p, "P5Home") == nil and #watch.since(p, m0, "P5Home") == 0 and DataS.GetHome(p).Stations.Press1 == 10,
			"p5 fold: ...nothing changes (berries 6800 once, no signal, MigratedNow nil)")
		-- a Phase 4 server sold a Carrot Patch meanwhile (Press2 = 3 lands in the store): the next load folds it too
		leave({ p })
		local rec = stored(FOLD)
		rec.Home.Stations.Press2 = 3
		rec.Food = { Snack = 1 } -- (a Phase 4 server cannot make food any more; a leftover is NOT converted twice)
		m0 = watch.mark()
		p = join("P5Fold", FOLD)
		home = DataS.GetHome(p)
		T.check(home.Stations.Press1 == 13 and home.Stations.Press2 == nil and calls[#calls].firstTime == false, "p5 fold: a Press2 sold by a Phase 4 server after the marker is folded on the next load (Press1 10 + 3 = 13; firstTime = false)")
		T.check(DataS.GetBerries(p) == 6800 and DataS.GetFood(p, "Snack") == 1 and #watch.since(p, m0, "P5Home") == 1 and DataS.MigratedNow(p, "P5Home") == nil,
			"p5 fold: ...the Food -> berries step does not run again (Snack kept, berries 6800); the signal names the fold, MigratedNow stays nil (not a first time)")
		T.eq(DataS.Save(p), true, "p5 fold: saves")
		T.check(((stored(FOLD) or {}).Home.Stations or {}).Press2 == nil and (stored(FOLD) or {}).Home.Stations.Press1 == 13, "p5 fold: the store lost Press2 and holds Press1 13")
		leave({ p })

		-- 3. a fold that errors marks nothing (the step retries on the next load)
		TC.FoldLegacy = function()
			error("fold exploded")
		end
		local BOOM = 955503
		data[storeKey(BOOM)] = phase4Record(ids, { Home = oldHome(), Food = { Feast = 1 } })
		p = join("P5FoldBoom", BOOM)
		T.check(DataS.IsMigrated(p, "P5Home") == false and DataS.GetFood(p, "Feast") == 1 and DataS.GetBerries(p) == 0 and DataS.GetHome(p).Stations.Press2 == 4,
			"p5 fold: a FoldLegacy that errors leaves the marker unset, the Food and the home untouched")
		leave({ p })
		K.flushWarnings("p5home_fold_data", { "[DataService] TycoonCatalog.FoldLegacy failed" })
		-- 4. a fresh home (nothing to fold) is still marked on its first load, with no berries
		TC.FoldLegacy = function(_, firstTime)
			return false
		end
		local FRESH = 955504
		p = join("P5FoldFresh", FRESH)
		T.check(DataS.IsMigrated(p, "P5Home") == true and DataS.GetBerries(p) == 0 and DataS.MigratedNow(p, "P5Home") ~= nil and DataS.MigratedNow(p, "P5Home").Folded == false and DataS.MigratedNow(p, "P5Home").Veteran == false,
			"p5 fold: a new player's home is marked P5Home at once (Folded false, Veteran false, 0 berries)")
		leave({ p })
	end)
	TC.FoldLegacy = realFold
	watch.stop()
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p5home_fold_data")
	K.flushWarnings("p5home_fold_data", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the rollout (a Phase 4 server saving a Phase 5 profile)
----------------------------------------------------------------------------------------------------
local function phase5Record(ids)
	local a, b, c, d = ids[1], ids[2], ids[3], ids[4]
	return phase4Record(ids, {
		Home = { Level = 14, Prestige = 1, Stations = { Press1 = 13, Garden = 6, Fence = 2, Fountain = 1 }, Garden = { a, b }, Gym = {}, CollectorCash = 500, LastSeen = 1700000000, LegacySlots = 6, LegacyPrices = true, DecorCredit = 4, LegacyMagnet = 3, LegacyMagnetStar = 1 },
		Teams = { Presets = { { b, c } }, Active = 1 },
		Dungeon = { Best = 5, Cleared = { true, true, true, true, true }, Runs = 7, Clears = 5 },
		Berries = 6800,
		Settings = { Music = 2, Sfx = 8, Gfx = "Low", Shake = false, SeenNotes = 5 },
		Migrations = { P4 = true, P5Dungeon = true, P5Home = true },
	})
end

S.p5home_rollout = guarded("p5home_rollout", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local data = Mock.DataStore.Data
	local P4DS, release = phase4Server()
	if not T.check(P4DS ~= nil, "p5 home rollout: the frozen Phase 4 DataService loads as a second module (a 'Phase 4 server')", tostring(release)) then
		return
	end
	local ids = petIds(4)
	local a, b, c, d = ids[1], ids[2], ids[3], ids[4]
	local ROLL = 955601
	data[storeKey(ROLL)] = phase5Record(ids)
	local okRun, errRun = pcall(function()
		local p = join("P5HomeRollout", ROLL)
		T.check(DataS.GetBerries(p) == 6800 and DataS.GetHome(p).DecorCredit == 4 and DataS.GetHome(p).LegacyMagnet == 3 and DataS.GetSettings(p).Gfx == "Low" and DataS.MigratedNow(p, "P5Home") == nil,
			"p5 home rollout: (precondition) the Phase 5 server loads the Phase 5 profile (already migrated)")
		local tokens5 = DataS.GetTokens(p)
		local p4prof = P4DS.Load(p)
		T.check(type(p4prof) == "table" and p4prof.Berries == nil and p4prof.Settings == nil and p4prof.Home.DecorCredit == nil and p4prof.Home.LegacyMagnet == nil,
			"p5 home rollout: the Phase 4 server's live profile knows nothing of Berries / Settings / DecorCredit / LegacyMagnet")
		T.check(p4prof.Home.Stations.Press1 == 13 and p4prof.Home.Level == 14 and P4DS.GetHome(p).Stations.Press1 == 13, "p5 home rollout: it reads Press1 = 13 as it is (the data layer clamps nothing; TycoonCatalog clamps on display)")
		T.check(P4DS.GetTeams(p) ~= nil and P4DS.GetTeams(p).Slots == 4, "p5 home rollout: (the Phase 4 server offers 4 team slots at Prestige 1)")
		-- it plays: tokens, a 4-key preset, a food item (its old API still exists), it saves
		P4DS.AddTokens(p, 5)
		local okTeam, whyTeam = P4DS.SetTeam(p, 1, { a, b, c, d })
		T.check(okTeam == true, "p5 home rollout: the Phase 4 server stores a 4-key preset", tostring(whyTeam))
		P4DS.AddFood(p, "Snack", 1)
		T.eq(P4DS.Save(p), true, "p5 home rollout: the Phase 4 server saves")
		local st = stored(ROLL) or {}
		local sh = st.Home or {}
		T.check(st.Berries == 6800 and type(st.Settings) == "table" and st.Settings.Music == 2 and st.Settings.Gfx == "Low" and st.Settings.Shake == false, "p5 home rollout: Berries and Settings come back untouched (keepForeign)")
		T.check(sh.DecorCredit == 4 and sh.LegacyMagnet == 3 and sh.LegacyMagnetStar == 1 and sh.LegacySlots == 6 and sh.LegacyPrices == true, "p5 home rollout: Home.DecorCredit / LegacyMagnet / LegacyMagnetStar come back untouched (foreign Home keys)")
		T.check(sh.Stations.Press1 == 13 and sh.Stations.Fence == 2 and sh.Stations.Fountain == 1 and sh.Stations.Garden == 6 and count(sh.Stations) == 4 and sh.Level == 14, "p5 home rollout: Press1 = 13 is not clamped on return; the other stations and the Home Level are unchanged")
		T.check(type(st.Teams) == "table" and #st.Teams.Presets[1] == 4 and st.Tokens == 15 and type(st.Food) == "table" and st.Food.Snack == 1, "p5 home rollout: ...with the Phase 4 server's own changes (tokens + 5, the 4-key preset, a Snack)")
		T.check(type(st.Migrations) == "table" and st.Migrations.P5Home == true and st.Migrations.P5Dungeon == true, "p5 home rollout: the P5 markers come back")
		-- the Phase 5 server reads it back: 3 keys, TeamsChanged once, nothing re-migrated
		local watch = teamsWatcher(DataS)
		local m0 = watch.mark()
		DataS.AddTokens(p, 1)
		T.eq(DataS.Save(p), true, "p5 home rollout: the Phase 5 server saves a token and adopts the store")
		advance(0.3)
		T.check(sameList(DataS.GetTeams(p).Presets[1], { a, b, c }) and DataS.GetTeams(p).Slots == 3, "p5 home rollout: the 4-key preset reads as its first 3 keys here", listText(DataS.GetTeams(p).Presets[1]))
		T.check(DataS.GetProfile(p).Pets[d] == 1, "p5 home rollout: ...the 4th pet is still owned")
		T.check(DataS.GetBerries(p) == 6800 and DataS.GetHome(p).DecorCredit == 4 and DataS.GetHome(p).LegacyMagnet == 3 and DataS.GetHome(p).Stations.Press1 == 13 and DataS.GetSettings(p).Music == 2,
			"p5 home rollout: Phase 5 reads Berries / DecorCredit / LegacyMagnet / Press1 13 / Settings back unchanged")
		T.check(DataS.GetTokens(p) == tokens5 + 5 + 1 and DataS.MigratedNow(p, "P5Home") == nil and DataS.IsMigrated(p, "P5Home") == true, "p5 home rollout: the tokens of both servers land once; the home step does not run again")
		T.check(DataS.GetFood(p, "Snack") == 1, "p5 home rollout: the Phase 4 Snack is kept as Food (the Food -> berries step ran already; the care service decides what to do with a leftover)")
		watch.stop()
		leave({ p })
		local final = stored(ROLL) or {}
		T.check(final.Berries == 6800 and final.Home.DecorCredit == 4 and final.Home.LegacyMagnet == 3 and #final.Teams.Presets[1] == 3 and final.Settings.Gfx == "Low",
			"p5 home rollout: after both servers saved at the leave the record holds every Phase 5 field and a 3-key preset")
	end)
	T.check(release() == true, "p5 home rollout: the Phase 4 module's hooks are dropped with it (no leaked connections)")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p5home_rollout")
	K.flushWarnings("p5home_rollout", { "[DataService]" })
end)

S.p5dgn_rollout = guarded("p5dgn_rollout", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local data = Mock.DataStore.Data
	local P4DS, release = phase4Server()
	if not T.check(P4DS ~= nil, "p5 dungeon rollout: the frozen Phase 4 DataService loads as a second module (a 'Phase 4 server')", tostring(release)) then
		return
	end
	local ids = petIds(4)
	local ROLL = 955602
	data[storeKey(ROLL)] = phase5Record(ids)
	local okRun, errRun = pcall(function()
		local p = join("P5DgnRollout", ROLL)
		local d = DataS.GetDungeon(p)
		T.check(d ~= nil and d.Best == 5 and d.Runs == 7 and d.Clears == 5 and DataS.MigratedNow(p, "P5Dungeon") == nil, "p5 dungeon rollout: (precondition) the Phase 5 server loads the migrated record (Best 5, Runs 7)")
		local p4prof = P4DS.Load(p)
		T.check(type(p4prof) == "table" and p4prof.Dungeon == nil and type(p4prof.Migrations) == "table" and p4prof.Migrations.P5Dungeon == true,
			"p5 dungeon rollout: the Phase 4 server's live profile has no Dungeon; it keeps the markers (its own Migrations set)")
		-- it plays: a Trial clear (TrialBest 15 -> 16), a trophy, it saves
		T.check(P4DS.MutateBattle(p, function(battle)
			battle.TrialBest = 16
			battle.TrialCleared[16] = true
		end) == true, "p5 dungeon rollout: the Phase 4 server records a Trial 16 clear")
		P4DS.AddTrophies(p, 2)
		T.eq(P4DS.Save(p), true, "p5 dungeon rollout: the Phase 4 server saves")
		local st = stored(ROLL) or {}
		T.check(type(st.Dungeon) == "table" and st.Dungeon.Best == 5 and st.Dungeon.Runs == 7 and st.Dungeon.Clears == 5 and #st.Dungeon.Cleared == 5, "p5 dungeon rollout: the Dungeon record comes back untouched (keepForeign)")
		T.check(type(st.Migrations) == "table" and st.Migrations.P5Dungeon == true and st.Migrations.P5Home == true and st.Migrations.P4 == true, "p5 dungeon rollout: Migrations.P5* come back")
		T.check(st.Battle.TrialBest == 16 and st.Battle.Trophies == 42, "p5 dungeon rollout: ...with the Phase 4 server's Trial 16 and trophies 42")
		-- the Phase 5 server reads it back: TrialBest grew, the Dungeon is not re-derived
		DataS.AddTokens(p, 1)
		T.eq(DataS.Save(p), true, "p5 dungeon rollout: the Phase 5 server saves a token and adopts the store")
		advance(0.3)
		d = DataS.GetDungeon(p)
		T.check(DataS.GetBattle(p).TrialBest == 16 and d.Best == 5 and d.Clears == 5 and d.Runs == 7 and DataS.MigratedNow(p, "P5Dungeon") == nil,
			"p5 dungeon rollout: TrialBest 16 is read; the Dungeon stays Best 5 / Clears 5 (already migrated, never re-derived)", dungeonText(d))
		-- a Phase 5 first clear while the Phase 4 server also saves: lands once
		local okC, first = DataS.MutateDungeon(p, function(rec)
			rec.Cleared[6] = true
			rec.Clears = rec.Clears + 1
			rec.Runs = rec.Runs + 1
		end)
		P4DS.AddTokens(p, 1)
		T.check(okC == true and first == true and P4DS.Save(p) == true and DataS.Save(p) == true, "p5 dungeon rollout: Phase 5 clears floor 6, both servers save")
		st = stored(ROLL) or {}
		T.check(st.Dungeon.Best == 6 and st.Dungeon.Clears == 6 and st.Dungeon.Runs == 8 and #st.Dungeon.Cleared == 6, "p5 dungeon rollout: the store holds Best 6, Clears 6, Runs 8", dungeonText(st.Dungeon))
		leave({ p })
		local final = stored(ROLL) or {}
		T.check(type(final.Dungeon) == "table" and final.Dungeon.Best == 6 and final.Migrations.P5Dungeon == true and final.Battle.TrialBest == 16, "p5 dungeon rollout: after both servers saved at the leave the record holds the Dungeon, the markers and TrialBest 16")
	end)
	T.check(release() == true, "p5 dungeon rollout: the Phase 4 module's hooks are dropped with it (no leaked connections)")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p5dgn_rollout")
	K.flushWarnings("p5dgn_rollout", { "[DataService]" })
end)

return S
