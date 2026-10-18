-- smoke_p3_data.lua: Phase 3 "Data" (ARCHITECTURE_V3.md "Phase 3 build contract": Data + "Interfaces between the
-- Phase 3 modules"): the battle teams and the battle record of server/Services/DataService.lua, and the developer
-- reset of both (server/Services/DevService.lua). Server world only (listed in server_files of tools/smoke.py); the
-- scenarios run before the Phase 2 care block (p3data_save advances the clock past an autosave):
--   p3data_teams   (booted) the API exists and TeamsChanged is created at module load; a new profile's defaults
--                  (3 empty presets, preset 1 active, 3 slots) in GetTeams, the live profile and ProfileSync;
--                  SetTeam validation (preset 1..3, junk lists, the 4th slot only from Prestige 1, a key once per
--                  team, owned copies only, copies busy in the Gym counted per copy (Phase 4: a garden pet may fight,
--                  and a TRAINING pet is skipped at read time by FieldableKeys / ActiveTeamKeys while its preset keeps
--                  it), canonical keys, tier and hybrid keys, empty slots compacted, an empty list clears the preset);
--                  SelectTeam; ActiveTeamKeys; GetTeams / ActiveTeamKeys hand out copies; TeamsChanged after SetTeam /
--                  SelectTeam; stale keys pruned after a copy vanishes (next Sync), after a Gym placement (MutateHome;
--                  a Garden placement prunes nothing since Phase 4) and after a real fusion (FusionService.Upgrade);
--                  the synced Teams { Presets, Active, Slots } stay plain and small
--   p3data_battle  (booted) GetBattle copies; AddTrophies (whole numbers, negative, never below 0, junk refused,
--                  synced); MutateBattle (edits, rollback on error / false, whole numbers >= 0, TrialCleared and
--                  EventPets only grow, TrialBest / RaidBestDamage never drop, TrialBest >= the highest cleared
--                  level, junk levels dropped); the synced Battle (TrialCleared as a dense array of booleans)
--   p3data_save    (booted, DataStore) migration of Phase 2 profiles (no Teams / Battle, the reserved Teams shape),
--                  the stored encoding (defaults left out, Presets / TrialCleared as dense arrays, no sparse array
--                  or mixed table anywhere, Version 2), a round trip, the merge against a concurrent server (presets
--                  per preset, Active, trophy / PvP / raid deltas, TrialCleared / EventPets union, best values both
--                  ways, a key the other server fused away pruned, trophies never below 0), the 4th slot and the
--                  Garden follow the stored Home, ResetFields({ Teams, Battle }), provisional profiles (no team edits
--                  and no first-clear decisions from stand-in data; trophies and counters still count) and the
--                  owner's /reset in the live game surviving the next autosave
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance, mod, config = K.advance, K.mod, K.config

local S = {}

local function count(map)
	local n = 0
	for _, v in pairs(type(map) == "table" and map or {}) do
		if v then
			n = n + 1
		end
	end
	return n
end

local function listText(list)
	local out = {}
	for i, v in ipairs(type(list) == "table" and list or {}) do
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

local function contains(list, value)
	for _, v in ipairs(type(list) == "table" and list or {}) do
		if v == value then
			return true
		end
	end
	return false
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

local function lastSnapshot(player, fromIndex)
	local list = K.remotesFor("ProfileSync", player.UserId, fromIndex or 0)
	local e = list[#list]
	return e and e.args[1] or nil
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

-- rough serialized size (characters) of a plain value
local function sizeOf(value)
	if type(value) == "table" then
		local n = 2
		for k, v in pairs(value) do
			n = n + #tostring(k) + 2 + sizeOf(v)
		end
		return n
	end
	return #tostring(value)
end

-- the levels a TrialCleared array / set marks as cleared, sorted
local function clearedLevels(cleared)
	local out = {}
	for k, v in pairs(type(cleared) == "table" and cleared or {}) do
		if v == true and type(k) == "number" then
			out[#out + 1] = k
		end
	end
	table.sort(out)
	return out
end

-- `n` catalog pet ids (Common ones first: the fusion check upgrades the first of them)
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

-- counts TeamsChanged firings per player while connected
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
			conn:Disconnect()
		end,
	}
end

----------------------------------------------------------------------------------------------------
-- scenario: the team API, validation, pruning, signals, sync
----------------------------------------------------------------------------------------------------
S.p3data_teams = guarded("p3data_teams", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local missing = {}
	for _, fn in ipairs({ "GetTeams", "SetTeam", "SelectTeam", "ActiveTeamKeys", "GetBattle", "MutateBattle", "AddTrophies" }) do
		if type(DataS[fn]) ~= "function" then
			missing[#missing + 1] = fn
		end
	end
	if not T.check(#missing == 0, "p3 teams: DataService has GetTeams / SetTeam / SelectTeam / ActiveTeamKeys / GetBattle / MutateBattle / AddTrophies", table.concat(missing, ", ")) then
		return
	end
	local signal = DataS.TeamsChanged
	T.check(type(signal) == "table" and type(signal.Connect) == "function" and type(signal.Fire) == "function", "p3 teams: DataService.TeamsChanged is a Util.Signal")
	local inst = K.moduleInstance("server/Services/DataService")
	local source = inst and inst.Source or ""
	T.check(string.find("\n" .. source, "\nDataService%.TeamsChanged = Util%.Signal%(%)") ~= nil,
		"p3 teams: ...created at module load (a top-level statement), so other services can connect before any Init")

	local watch = teamsWatcher(DataS)
	local mark = K.logSize()
	local p = join("P3Teams", 953001)
	local prof = DataS.GetProfile(p)
	if not T.check(prof ~= nil, "p3 teams: (precondition) the profile loads") then
		watch.stop()
		return
	end
	local teams = DataS.GetTeams(p)
	T.check(type(teams) == "table" and type(teams.Presets) == "table" and #teams.Presets == 3 and #teams.Presets[1] == 0 and #teams.Presets[2] == 0
		and #teams.Presets[3] == 0 and teams.Active == 1 and teams.Slots == 3,
		"p3 teams: a new profile has 3 empty presets, preset 1 active, 3 slots (GetTeams)")
	T.check(type(prof.Teams) == "table" and type(prof.Teams.Presets) == "table" and prof.Teams.Active == 1 and type(prof.Battle) == "table" and prof.Battle.Trophies == 0,
		"p3 teams: ...the live profile holds Teams { Presets, Active } and a Battle record")
	local keys0 = DataS.ActiveTeamKeys(p)
	T.check(type(keys0) == "table" and #keys0 == 0, "p3 teams: ActiveTeamKeys of an empty team is {}")
	local snap = lastSnapshot(p, mark)
	T.check(type(snap) == "table" and type(snap.Teams) == "table" and type(snap.Teams.Presets) == "table" and #snap.Teams.Presets == 3 and snap.Teams.Active == 1
		and snap.Teams.Slots == 3 and type(snap.Battle) == "table" and snap.Battle.Trophies == 0 and type(snap.Battle.TrialCleared) == "table",
		"p3 teams: ProfileSync carries Teams { Presets, Active, Slots = 3 } and Battle from the join on")

	-- pets to build teams from: one copy each, two of `e` (one may work while the other fights), a Golden `a`, a hybrid
	local ids = petIds(7)
	local a, b, c, d, e, f, g = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7]
	for _, id in ipairs(ids) do
		prof.Pets[id] = 1
	end
	prof.Pets[e] = 2
	prof.Tiers[a] = { Golden = 1 }
	prof.Hybrids.p3h = { Body = a, Style = b, Elements = {}, Name = "Testmix", Rarity = "Common", Tier = "Normal" }
	DataS.MarkDirty(p)

	-- SetTeam
	local m0 = watch.mark()
	local ok, why = DataS.SetTeam(p, 1, { a, b, c })
	T.check(ok == true and sameList(DataS.GetTeams(p).Presets[1], { a, b, c }) and sameList(DataS.ActiveTeamKeys(p), { a, b, c }),
		"p3 teams: SetTeam(1, {a, b, c}) stores the preset (GetTeams, ActiveTeamKeys in slot order)", tostring(why))
	T.eq(watch.since(p, m0), 1, "p3 teams: ...and fires TeamsChanged once")
	local bad = {}
	for _, preset in ipairs({ 0, 4, 1.5, -1, "1", 0 / 0, math.huge }) do
		local okBad, reason = DataS.SetTeam(p, preset, { d })
		if okBad ~= false or type(reason) ~= "string" then
			bad[#bad + 1] = tostring(preset)
		end
	end
	local okNil = DataS.SetTeam(p, nil, { d })
	T.check(#bad == 0 and okNil == false and sameList(DataS.GetTeams(p).Presets[1], { a, b, c }),
		"p3 teams: SetTeam refuses presets other than 1..3 (0, 4, 1.5, -1, '1', nan, inf, nil) with a reason", table.concat(bad, ", "))
	bad = {}
	local junkLists = {
		{ "a string", "x" }, { "a number", 5 }, { "a boolean", true }, { "a number key", { 5 } }, { "a nested table", { {} } },
		{ "a named field", { foo = a } }, { "slot 5", { [5] = a } }, { "slot 0", { [0] = a } }, { "slot 1.5", { [1.5] = a } },
		{ "five pets", { a, b, c, d, e } }, { "a non-canonical key", { a .. "@Normal" } }, { "an over-long key", { string.rep("x", 60) } },
	}
	for _, case in ipairs(junkLists) do
		local okBad, reason = DataS.SetTeam(p, 2, case[2])
		if okBad ~= false or type(reason) ~= "string" then
			bad[#bad + 1] = case[1]
		end
	end
	T.check(#bad == 0 and #DataS.GetTeams(p).Presets[2] == 0, "p3 teams: SetTeam refuses junk lists (" .. #junkLists .. " shapes) with a reason; nothing is stored", table.concat(bad, ", "))
	ok, why = DataS.SetTeam(p, 2, { a, b, c, d })
	T.check(ok == false and type(why) == "string" and why:find("Prestige", 1, true) ~= nil, "p3 teams: a 4th pet is refused before Prestige 1 (the reason names the unlock)", tostring(why))
	ok, why = DataS.SetTeam(p, 2, { a, "", "", d })
	T.check(ok == false and type(why) == "string" and why:find("Prestige", 1, true) ~= nil, "p3 teams: ...also alone in slot 4 (the empty slots before it do not move it up)", tostring(why))
	ok, why = DataS.SetTeam(p, 2, { a, a })
	T.check(ok == false and type(why) == "string" and why:find("once", 1, true) ~= nil, "p3 teams: the same key twice is refused", tostring(why))
	ok, why = DataS.SetTeam(p, 2, { a, "no_such_pet" })
	T.check(ok == false and type(why) == "string" and why:find("own", 1, true) ~= nil, "p3 teams: a key the player does not own is refused", tostring(why))
	ok, why = DataS.SetTeam(p, 2, { a .. "@Rainbow" })
	T.check(ok == false and type(why) == "string" and why:find("own", 1, true) ~= nil, "p3 teams: ...also a tier the player does not own", tostring(why))
	T.check(DataS.MutateHome(p, function(home)
		home.Garden[1] = d
		home.Gym[2] = e
	end) == true, "p3 teams: (precondition) d works in the Garden, one of the two e copies trains in the Gym")
	-- Phase 4: a garden pet earns at home while it follows you and fights (P3.placedCopies counts Home.Gym only); the
	-- only busy state is a running training Job, and that is a READ-TIME filter (TrainingKeys): the preset keeps the pet
	ok, why = DataS.SetTeam(p, 2, { d })
	T.check(ok == true and sameList(DataS.GetTeams(p).Presets[2], { d }), "p3 teams: a pet whose only copy works in the Garden CAN fight (Phase 4: garden pets are not busy)", tostring(why))
	if type(DataS.MutateGrowth) == "function" and type(DataS.TrainingKeys) == "function" then
		local okJob = DataS.MutateGrowth(p, function(growth)
			growth[d] = { Job = { Stat = "Physique", Ends = os.time() + 120, Rank = 1, Slot = 1, From = "Garden:1", Paid = 300 } }
		end)
		local fieldable = {}
		for _, key in ipairs(DataS.FieldableKeys(p)) do
			fieldable[key] = true
		end
		T.check(okJob == true and DataS.TrainingKeys(p)[d] == true and sameList(DataS.GetTeams(p).Presets[2], { d }) and fieldable[d] == nil,
			"p3 teams: a TRAINING pet (a running Job) is skipped at read time: FieldableKeys leaves it out while its preset keeps it", listText(DataS.FieldableKeys(p)))
		local okKeep, whyKeep = DataS.SetTeam(p, 2, { d, b })
		T.check(okKeep == true and sameList(DataS.GetTeams(p).Presets[2], { d, b }), "p3 teams: ...and SetTeam still accepts it in a preset (P3.checkTeam is not taught about training)", tostring(whyKeep))
		T.check(DataS.SelectTeam(p, 2) == true and sameList(DataS.ActiveTeamKeys(p), { b }), "p3 teams: ...ActiveTeamKeys skips it (compacted) while the job runs", listText(DataS.ActiveTeamKeys(p)))
		DataS.MutateGrowth(p, function(growth)
			growth[d] = nil
		end)
		T.check(DataS.TrainingKeys(p)[d] == nil and sameList(DataS.ActiveTeamKeys(p), { d, b }), "p3 teams: ...the job gone, the pet is back in the active team at once (nothing was pruned)", listText(DataS.ActiveTeamKeys(p)))
		DataS.SelectTeam(p, 1)
	end
	ok, why = DataS.SetTeam(p, 2, { e })
	T.check(ok == true and sameList(DataS.GetTeams(p).Presets[2], { e }), "p3 teams: ...a pet with a second, free copy can (copies are counted)", tostring(why))
	ok, why = DataS.SetTeam(p, 3, { a .. "@Golden", "hyb:p3h", a })
	T.check(ok == true and sameList(DataS.GetTeams(p).Presets[3], { a .. "@Golden", "hyb:p3h", a }), "p3 teams: tier keys and hybrid keys join teams (a Golden copy and the Normal one are different keys)", tostring(why))
	ok = DataS.SetTeam(p, 2, { b, "", c })
	local okSparse = DataS.SetTeam(p, 2, { [1] = b, [3] = c })
	T.check(ok == true and okSparse == true and sameList(DataS.GetTeams(p).Presets[2], { b, c }),
		"p3 teams: empty slots ('' or holes from a remote) are compacted: the pets behind move up", listText(DataS.GetTeams(p).Presets[2]))
	ok = DataS.SetTeam(p, 2, { false, c })
	T.check(ok == true and sameList(DataS.GetTeams(p).Presets[2], { c }), "p3 teams: false marks an empty slot too")
	ok = DataS.SetTeam(p, 2, {})
	T.check(ok == true and #DataS.GetTeams(p).Presets[2] == 0, "p3 teams: an empty list clears the preset")

	-- SelectTeam + copies
	local m1 = watch.mark()
	ok = DataS.SelectTeam(p, 3)
	T.check(ok == true and DataS.GetTeams(p).Active == 3 and sameList(DataS.ActiveTeamKeys(p), { a .. "@Golden", "hyb:p3h", a }),
		"p3 teams: SelectTeam(3) makes preset 3 the active one (ActiveTeamKeys follows)")
	T.eq(watch.since(p, m1), 1, "p3 teams: ...and fires TeamsChanged once")
	bad = {}
	for _, preset in ipairs({ 0, 4, 2.5, "2" }) do
		local okBad, reason = DataS.SelectTeam(p, preset)
		if okBad ~= false or type(reason) ~= "string" then
			bad[#bad + 1] = tostring(preset)
		end
	end
	T.check(#bad == 0 and DataS.SelectTeam(p, nil) == false and DataS.GetTeams(p).Active == 3, "p3 teams: SelectTeam refuses presets other than 1..3", table.concat(bad, ", "))
	local copy = DataS.GetTeams(p)
	copy.Presets[3][1] = "junk"
	copy.Active = 2
	local keysCopy = DataS.ActiveTeamKeys(p)
	keysCopy[1] = "junk"
	T.check(DataS.GetTeams(p).Presets[3][1] == a .. "@Golden" and DataS.GetTeams(p).Active == 3 and DataS.ActiveTeamKeys(p)[1] == a .. "@Golden",
		"p3 teams: GetTeams and ActiveTeamKeys hand out copies")
	T.check(DataS.SetTeam(nil, 1, { a }) == false and DataS.SelectTeam(nil, 1) == false and DataS.GetTeams(nil) == nil and #DataS.ActiveTeamKeys(nil) == 0,
		"p3 teams: the API refuses a nil player")

	-- slot 4 from Prestige 1
	T.check(DataS.MutateHome(p, function(home)
		home.Prestige = 1
	end) == true, "p3 teams: (precondition) the home prestiges")
	T.eq(DataS.GetTeams(p).Slots, 4, "p3 teams: at Prestige 1 a team has 4 slots")
	mark = K.logSize()
	ok, why = DataS.SetTeam(p, 1, { a, b, c, f })
	T.check(ok == true and sameList(DataS.GetTeams(p).Presets[1], { a, b, c, f }), "p3 teams: ...and takes a 4th pet", tostring(why))
	advance(0.5)
	snap = lastSnapshot(p, mark)
	T.check(type(snap) == "table" and snap.Teams.Slots == 4 and sameList(snap.Teams.Presets[1], { a, b, c, f }) and snap.Teams.Active == 3,
		"p3 teams: ProfileSync shows Slots = 4 and the new preset")

	-- pruning: a copy vanishes (released, consumed elsewhere): the next Sync drops the key everywhere
	local m2 = watch.mark()
	mark = K.logSize()
	prof.Pets[b] = nil
	DataS.Sync(p)
	T.check(sameList(DataS.GetTeams(p).Presets[1], { a, c, f }) and sameList(prof.Teams.Presets[1], { a, c, f }),
		"p3 teams: a key whose copy is gone leaves the presets at the next Sync (the live profile too); the pets behind move up", listText(prof.Teams.Presets[1]))
	T.check(watch.since(p, m2) >= 1, "p3 teams: ...TeamsChanged fires")
	snap = lastSnapshot(p, mark)
	T.check(type(snap) == "table" and sameList(snap.Teams.Presets[1], { a, c, f }), "p3 teams: ...and that very snapshot is pruned")
	-- Phase 4: the last free copy going to the Garden prunes NOTHING (garden pets fight); the Gym still does
	DataS.MutateHome(p, function(home)
		home.Garden[2] = c
	end)
	T.check(sameList(DataS.GetTeams(p).Presets[1], { a, c, f }) and sameList(DataS.GetTeams(p).Presets[3], { a .. "@Golden", "hyb:p3h", a }),
		"p3 teams: a pet whose last free copy goes to the Garden STAYS in its team (Phase 4: P3.placedCopies counts Home.Gym only)",
		listText(DataS.GetTeams(p).Presets[1]) .. " / " .. listText(DataS.GetTeams(p).Presets[3]))
	ok = DataS.SetTeam(p, 2, { e, f })
	T.check(ok == true and sameList(DataS.GetTeams(p).Presets[2], { e, f }), "p3 teams: (precondition) team 2 holds e (its free copy) and f")
	DataS.MutateHome(p, function(home)
		home.Gym[3] = e
	end)
	T.check(sameList(DataS.GetTeams(p).Presets[2], { f }), "p3 teams: ...the same for the Gym (the second e copy now trains too)", listText(DataS.GetTeams(p).Presets[2]))

	-- pruning after a real fusion: 3 copies of g -> 1 Golden g; g leaves the team
	local fusionModule = K.moduleInstance("server/Services/FusionService")
	local okFusion, Fusion = pcall(require, fusionModule)
	if not okFusion then
		Fusion = nil
	end
	if Fusion and type(Fusion.Upgrade) == "function" then
		prof.Pets[g] = 3
		DataS.AddTokens(p, 10000000)
		DataS.MutateHome(p, function(home)
			home.Stations.FusionMachine = 1
		end)
		ok, why = DataS.SetTeam(p, 1, { a, g })
		T.check(ok == true, "p3 teams: (precondition) g joins team 1", tostring(why))
		local m4 = watch.mark()
		mark = K.logSize()
		local fused, result = Fusion.Upgrade(p, g)
		T.check(fused == true and result == g .. "@Golden", "p3 teams: (precondition) FusionService.Upgrade turns 3 g into a Golden g", tostring(result))
		advance(0.3)
		T.check(sameList(DataS.GetTeams(p).Presets[1], { a }) and watch.since(p, m4) >= 1,
			"p3 teams: a key the fusion consumed is dropped from the team and TeamsChanged fires", listText(DataS.GetTeams(p).Presets[1]))
		snap = lastSnapshot(p, mark)
		T.check(type(snap) == "table" and sameList(snap.Teams.Presets[1], { a }), "p3 teams: ...the fusion's ProfileSync already shows it")
		ok = DataS.SetTeam(p, 1, { a, g .. "@Golden" })
		T.check(ok == true, "p3 teams: ...and the Golden result can join instead")
	else
		T.warn("p3 teams: FusionService.Upgrade is missing: the fusion pruning check was skipped")
	end

	-- the snapshot stays plain and small
	DataS.SelectTeam(p, 1)
	DataS.AddTrophies(p, 1234)
	DataS.MutateBattle(p, function(battle)
		for level = 1, 30 do
			battle.TrialCleared[level] = true
		end
		battle.EventPets.storm_titan_pup, battle.EventPets.lava_whelp, battle.EventPets.frost_wyrmling = true, true, true
	end)
	mark = K.logSize()
	DataS.Sync(p)
	snap = lastSnapshot(p, mark)
	local holes = sparsePaths(type(snap) == "table" and snap or {}, "snapshot")
	T.check(type(snap) == "table" and #holes == 0, "p3 teams: the snapshot holds no sparse array or mixed table (remotes would mangle them)", table.concat(holes, ", "))
	local size = type(snap) == "table" and (sizeOf(snap.Teams) + sizeOf(snap.Battle)) or math.huge
	T.check(size < 900, "p3 teams: Teams + Battle stay a small part of the snapshot (" .. size .. " chars with a 4-pet team, 30 cleared trials, 3 event pets)")
	local problems = K.V and type(K.V.profileSync) == "function" and K.V.profileSync(snap) or {}
	T.check(#problems == 0, "p3 teams: the snapshot passes the ProfileSync validator", table.concat(problems, " | "))

	watch.stop()
	K.removePlayers({ p })
	advance(2)
	K.flushErrors("p3data_teams")
	K.flushWarnings("p3data_teams", { "[DataService]", "[FusionService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the battle record API
----------------------------------------------------------------------------------------------------
S.p3data_battle = guarded("p3data_battle", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	if type(DataS.GetBattle) ~= "function" or type(DataS.MutateBattle) ~= "function" or type(DataS.AddTrophies) ~= "function" then
		T.fail("p3 battle: DataService has no GetBattle / MutateBattle / AddTrophies")
		return
	end
	local p = join("P3Battle", 953101)
	local rec = DataS.GetBattle(p)
	T.check(type(rec) == "table" and rec.Trophies == 0 and rec.TrialBest == 0 and count(rec.TrialCleared) == 0 and rec.Raids == 0 and rec.RaidBestDamage == 0
		and rec.PvPWins == 0 and rec.PvPLosses == 0 and count(rec.EventPets) == 0,
		"p3 battle: a new record is all zero (Trophies, TrialBest, TrialCleared, Raids, RaidBestDamage, PvPWins, PvPLosses, EventPets)")

	-- AddTrophies
	local ok, total = DataS.AddTrophies(p, 10)
	T.check(ok == true and total == 10 and DataS.GetBattle(p).Trophies == 10, "p3 battle: AddTrophies(10) -> true, 10", tostring(total))
	ok, total = DataS.AddTrophies(p, -3)
	T.check(ok == true and total == 7, "p3 battle: AddTrophies(-3) takes trophies (7)", tostring(total))
	ok, total = DataS.AddTrophies(p, -100)
	T.check(ok == true and total == 0 and DataS.GetBattle(p).Trophies == 0, "p3 battle: ...never below 0 (AddTrophies(-100) -> 0)", tostring(total))
	DataS.AddTrophies(p, 2.4)
	DataS.AddTrophies(p, 2.6)
	ok, total = DataS.AddTrophies(p, -1.6)
	T.check(ok == true and total == 3, "p3 battle: amounts are rounded to whole trophies (2.4 + 2.6 - 1.6 -> 2 + 3 - 2 = 3)", tostring(total))
	local refused = true
	for _, junk in ipairs({ 0 / 0, math.huge, -math.huge, "5", {}, true }) do
		if DataS.AddTrophies(p, junk) ~= false then
			refused = false
		end
	end
	T.check(refused and DataS.AddTrophies(p) == false and DataS.AddTrophies(nil, 5) == false and DataS.GetBattle(p).Trophies == 3,
		"p3 battle: AddTrophies refuses junk (nan, inf, '5', tables, booleans, nil) and a nil player")
	local copy = DataS.GetBattle(p)
	copy.Trophies = 999
	copy.TrialCleared[7] = true
	copy.EventPets.junk = true
	rec = DataS.GetBattle(p)
	T.check(rec.Trophies == 3 and not rec.TrialCleared[7] and not rec.EventPets.junk, "p3 battle: GetBattle hands out a copy")

	-- MutateBattle
	ok = DataS.MutateBattle(p, function(battle)
		battle.TrialCleared[1] = true
		battle.TrialCleared[2] = true
		battle.TrialBest = 2
		battle.Raids = battle.Raids + 1
		battle.RaidBestDamage = 1234.7
		battle.PvPWins = 2
		battle.EventPets.storm_titan_pup = true
	end)
	rec = DataS.GetBattle(p)
	T.check(ok == true and rec.TrialCleared[1] == true and rec.TrialCleared[2] == true and rec.TrialBest == 2 and rec.Raids == 1 and rec.RaidBestDamage == 1234
		and rec.PvPWins == 2 and rec.EventPets.storm_titan_pup == true,
		"p3 battle: MutateBattle edits the live record (whole numbers)")
	ok = DataS.MutateBattle(p, function(battle)
		battle.PvPWins = 50
		error("boom", 0)
	end)
	T.check(ok == false and DataS.GetBattle(p).PvPWins == 2, "p3 battle: an error inside fn restores the record (-> false)")
	ok = DataS.MutateBattle(p, function(battle)
		battle.PvPWins = 50
		battle.TrialCleared[9] = true
		return false
	end)
	T.check(ok == false and DataS.GetBattle(p).PvPWins == 2 and not DataS.GetBattle(p).TrialCleared[9], "p3 battle: fn returning false restores it too")
	ok = DataS.MutateBattle(p, function(battle)
		battle.TrialCleared[2] = nil
		battle.TrialBest = 1
		battle.RaidBestDamage = 5
		battle.EventPets.storm_titan_pup = nil
	end)
	rec = DataS.GetBattle(p)
	T.check(ok == true and rec.TrialCleared[2] == true and rec.TrialBest == 2 and rec.RaidBestDamage == 1234 and rec.EventPets.storm_titan_pup == true,
		"p3 battle: cleared trials and event pets never disappear and TrialBest / RaidBestDamage never drop (the store merges them so)")
	ok = DataS.MutateBattle(p, function(battle)
		battle.PvPLosses = -4
		battle.Raids = "lots"
		battle.PvPWins = 3.9
		battle.TrialCleared[5] = true
		battle.TrialCleared[0] = true
		battle.TrialCleared[100000] = true
		battle.TrialCleared[2.5] = true
		battle.TrialCleared.x = true
		battle.EventPets[""] = true
	end)
	rec = DataS.GetBattle(p)
	T.check(ok == true and rec.PvPLosses == 0 and rec.Raids == 0 and rec.PvPWins == 3 and sameList(clearedLevels(rec.TrialCleared), { 1, 2, 5 }) and rec.TrialBest == 5
		and count(rec.EventPets) == 1,
		"p3 battle: the record is sanitised (counters whole and >= 0, junk levels / ids dropped, TrialBest >= the highest cleared level)",
		listText(clearedLevels(rec.TrialCleared)) .. " best " .. tostring(rec.TrialBest))
	local prof = DataS.GetProfile(p)
	T.check(type(prof.Battle) == "table" and prof.Battle.PvPWins == 3 and prof.Battle.TrialCleared[100000] == nil, "p3 battle: ...in place (the live table is clean too)")
	T.check(DataS.MutateBattle(p, nil) == false and DataS.MutateBattle(nil, function() end) == false and DataS.MutateBattle(p, "fn") == false,
		"p3 battle: MutateBattle refuses junk arguments")

	-- the synced record: TrialCleared as a dense array of booleans
	local mark = K.logSize()
	DataS.AddTrophies(p, 4)
	advance(0.5)
	local snap = lastSnapshot(p, mark)
	local sb = type(snap) == "table" and snap.Battle or {}
	local tc = type(sb.TrialCleared) == "table" and sb.TrialCleared or {}
	T.check(#tc == 5 and tc[1] == true and tc[2] == true and tc[3] == false and tc[4] == false and tc[5] == true and #sparsePaths(sb, "Battle") == 0,
		"p3 battle: ProfileSync sends TrialCleared as a dense array of booleans ({true, true, false, false, true}: reads like the set)", listText(tc))
	T.check(sb.Trophies == 7 and sb.TrialBest == 5 and sb.PvPWins == 3 and sb.RaidBestDamage == 1234 and type(sb.EventPets) == "table" and sb.EventPets.storm_titan_pup == true,
		"p3 battle: ...with the trophies (synced after AddTrophies), counters, best values and event pets")
	K.removePlayers({ p })
	advance(2)
	K.flushErrors("p3data_battle")
	K.flushWarnings("p3data_battle", { "[DataService] MutateBattle callback errored" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: saves, migration, merge rules, provisional profiles, the developer reset
----------------------------------------------------------------------------------------------------
S.p3data_save = guarded("p3data_save", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	if type(DataS.GetTeams) ~= "function" or type(DataS.GetBattle) ~= "function" then
		T.fail("p3 save: DataService has no GetTeams / GetBattle")
		return
	end
	local Config = config()
	local DSt = Mock.DataStore
	local data = DSt.Data
	local ids = petIds(6)
	local a, b, c, d, e = ids[1], ids[2], ids[3], ids[4], ids[5]
	local function homeOf(prestige, garden)
		return { Level = 0, Prestige = prestige or 0, Stations = {}, Garden = garden or {}, Gym = {}, CollectorCash = 0, LastSeen = 0 }
	end

	-- migration: a Phase 2 profile has no Teams / Battle
	local MIG = 953201
	data[storeKey(MIG)] = {
		Version = 2, Tokens = 5, Pets = { [a] = 1, [b] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(), Cash = 10, Gems = 0,
		Discovered = {}, IndexClaimed = {}, Tutorial = { Step = 1, Done = false, Gifted = false }, Home = homeOf(0), PetLevels = {},
	}
	local m = join("P3Migrate", MIG)
	local t = DataS.GetTeams(m)
	T.check(type(t) == "table" and #t.Presets == 3 and #t.Presets[1] == 0 and t.Active == 1 and t.Slots == 3,
		"p3 save: a Phase 2 profile (no Teams) loads with 3 empty presets, preset 1 active")
	local rec = DataS.GetBattle(m)
	T.check(type(rec) == "table" and rec.Trophies == 0 and count(rec.TrialCleared) == 0, "p3 save: ...and a zeroed battle record")
	T.check(DataS.SetTeam(m, 1, { a, b }) == true and DataS.SelectTeam(m, 1) == true, "p3 save: (precondition) a team is set")
	DataS.AddTrophies(m, 12)
	DataS.MutateBattle(m, function(battle)
		battle.TrialCleared[1], battle.TrialCleared[2], battle.TrialCleared[4] = true, true, true
		battle.TrialBest = 4
		battle.EventPets[b] = true
	end)
	K.removePlayers({ m })
	advance(2)
	local sm = stored(MIG) or {}
	local smt = type(sm.Teams) == "table" and sm.Teams or {}
	local smp = type(smt.Presets) == "table" and smt.Presets or {}
	T.check(#smp == 3 and sameList(smp[1], { a, b }) and type(smp[2]) == "table" and #smp[2] == 0 and type(smp[3]) == "table" and smt.Active == 1,
		"p3 save: the save holds Teams { Presets = 3 lists, Active }", listText(smp[1]))
	local smb = type(sm.Battle) == "table" and sm.Battle or {}
	T.check(smb.Trophies == 12 and smb.TrialBest == 4 and type(smb.TrialCleared) == "table" and #smb.TrialCleared == 4 and smb.TrialCleared[3] == false
		and smb.TrialCleared[4] == true and type(smb.EventPets) == "table" and smb.EventPets[b] == true,
		"p3 save: ...and Battle with TrialCleared as a dense array of booleans", listText(smb.TrialCleared))
	local holes = sparsePaths(sm, "record")
	T.check(#holes == 0 and sm.Version == 2, "p3 save: no sparse array or mixed table anywhere in the record; Version stays 2", table.concat(holes, ", "))
	local m2 = join("P3Migrate", MIG)
	local t2, rec2 = DataS.GetTeams(m2), DataS.GetBattle(m2)
	T.check(t2 and sameList(t2.Presets[1], { a, b }) and rec2 and rec2.Trophies == 12 and rec2.TrialCleared[4] == true and rec2.TrialCleared[3] == nil and rec2.EventPets[b] == true,
		"p3 save: ...and it reads back the same (round trip)")
	K.removePlayers({ m2 })
	advance(2)

	-- the reserved Phase 2 shape (a bare list of keys) is read leniently; keys the profile does not own are dropped
	local RES = 953202
	data[storeKey(RES)] = {
		Version = 2, Tokens = 0, Pets = { [a] = 1, [c] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(), Teams = { a, c, "ghost_pet" },
	}
	local r = join("P3Reserve", RES)
	T.check(sameList(DataS.GetTeams(r).Presets[1], { a, c }), "p3 save: a bare list of keys becomes preset 1 (the pet the profile does not own is dropped)",
		listText(DataS.GetTeams(r).Presets[1]))
	K.removePlayers({ r })
	advance(2)

	-- defaults are left out of the record
	local NEW = 953203
	data[storeKey(NEW)] = nil
	local n = join("P3Fresh", NEW)
	DataS.AddTokens(n, 1)
	DataS.Save(n)
	local sn = stored(NEW) or {}
	T.check(sn.Tokens == 1 and sn.Teams == nil and sn.Battle == nil, "p3 save: default Teams / Battle are left out of the record (small saves)")
	K.removePlayers({ n })
	advance(2)

	-- the merge against a concurrent server
	local MG = 953204
	data[storeKey(MG)] = {
		Version = 2, Tokens = 0, Pets = { [a] = 1, [b] = 1, [c] = 1, [d] = 1, [e] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(), Home = homeOf(0),
		Teams = { Presets = { { a }, {}, {} }, Active = 1 },
		Battle = { Trophies = 10, TrialBest = 1, TrialCleared = { true }, Raids = 1, RaidBestDamage = 300, PvPWins = 2, PvPLosses = 1, EventPets = { [a] = true } },
	}
	local watch = teamsWatcher(DataS)
	local q = join("P3Merge", MG)
	-- this session: preset 2, preset 2 active, +3 trophies, a PvP win, trial 2, a big raid
	DataS.SetTeam(q, 2, { b })
	DataS.SelectTeam(q, 2)
	DataS.AddTrophies(q, 3)
	DataS.MutateBattle(q, function(battle)
		battle.PvPWins = battle.PvPWins + 1
		battle.TrialCleared[2] = true
		battle.TrialBest = 2
		battle.RaidBestDamage = 900
	end)
	-- another server meanwhile: presets 1 and 3, +5 trophies, a PvP loss, trial 3, another raid, an event pet
	local other = data[storeKey(MG)]
	other.Teams = { Presets = { { a, c }, {}, { d } }, Active = 1 }
	other.Battle.Trophies = 15
	other.Battle.PvPLosses = 2
	other.Battle.Raids = 2
	other.Battle.TrialCleared = { true, false, true }
	other.Battle.TrialBest = 3
	other.Battle.RaidBestDamage = 700
	other.Battle.EventPets[e] = true
	local m1 = watch.mark()
	DataS.Save(q)
	local sq = stored(MG) or {}
	local sqt = type(sq.Teams) == "table" and sq.Teams or {}
	local sqp = type(sqt.Presets) == "table" and sqt.Presets or {}
	T.check(sameList(sqp[1], { a, c }) and sameList(sqp[2], { b }) and sameList(sqp[3], { d }) and sqt.Active == 2,
		"p3 save: presets merge per preset (1 and 3 from the other server, 2 and Active from this one)", listText(sqp[1]) .. listText(sqp[2]) .. listText(sqp[3]) .. " active " .. tostring(sqt.Active))
	local sqb = type(sq.Battle) == "table" and sq.Battle or {}
	T.eq(sqb.Trophies, 18, "p3 save: trophies merge as a delta (10 + 5 elsewhere + 3 here)")
	T.check(sqb.PvPWins == 3 and sqb.PvPLosses == 2 and sqb.Raids == 2, "p3 save: PvP / raid counters merge as deltas (wins 2 + 1, losses 1 + 1 elsewhere, raids 1 + 1 elsewhere)",
		tostring(sqb.PvPWins) .. "/" .. tostring(sqb.PvPLosses) .. "/" .. tostring(sqb.Raids))
	T.check(sameList(clearedLevels(sqb.TrialCleared), { 1, 2, 3 }) and sqb.TrialBest == 3, "p3 save: TrialCleared only grows (union of 1, 2 here and 1, 3 there); TrialBest keeps the higher (3)",
		listText(clearedLevels(sqb.TrialCleared)))
	T.check(sqb.RaidBestDamage == 900 and type(sqb.EventPets) == "table" and sqb.EventPets[a] == true and sqb.EventPets[e] == true,
		"p3 save: RaidBestDamage keeps the higher (900 here vs 700 there); EventPets only grow (union)")
	advance(0.5)
	local qt, qb = DataS.GetTeams(q), DataS.GetBattle(q)
	T.check(qt and sameList(qt.Presets[1], { a, c }) and sameList(qt.Presets[3], { d }) and qt.Active == 2 and qb and qb.Trophies == 18 and qb.TrialCleared[3] == true,
		"p3 save: the live profile adopts the merged store")
	T.check(watch.since(q, m1) >= 1, "p3 save: ...and TeamsChanged fires (the presets came from another server)")
	-- a key the other server fused away is pruned by the merge
	other = data[storeKey(MG)]
	other.Pets[c] = nil
	DataS.AddTrophies(q, 1)
	local m2t = watch.mark()
	DataS.Save(q)
	sq = stored(MG) or {}
	sqp = type(sq.Teams) == "table" and type(sq.Teams.Presets) == "table" and sq.Teams.Presets or {}
	T.check(sameList(sqp[1], { a }), "p3 save: a key the other server fused away leaves the merged presets", listText(sqp[1]))
	advance(0.5)
	T.check(sameList(DataS.GetTeams(q).Presets[1], { a }) and watch.since(q, m2t) >= 1, "p3 save: ...the live team follows and TeamsChanged fires")
	-- trophies never go below 0 across servers
	other = data[storeKey(MG)]
	other.Battle.Trophies = 4
	DataS.AddTrophies(q, -10)
	DataS.Save(q)
	T.eq(((stored(MG) or {}).Battle or {}).Trophies, 0, "p3 save: trophies never go below 0 in the merge (4 stored, -10 here)")
	watch.stop()
	K.removePlayers({ q })
	advance(2)

	-- the 4th slot and the Garden follow the stored Home
	local P4 = 953205
	data[storeKey(P4)] = {
		Version = 2, Tokens = 0, Pets = { [a] = 1, [b] = 1, [c] = 1, [d] = 1, [e] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(), Home = homeOf(1),
		Teams = { Presets = { { a, b, c, d } }, Active = 1 },
	}
	local s4 = join("P3Slots", P4)
	T.check(sameList(DataS.GetTeams(s4).Presets[1], { a, b, c, d }) and DataS.GetTeams(s4).Slots == 4, "p3 save: a stored 4-pet team loads whole at Prestige 1")
	K.removePlayers({ s4 })
	advance(2)
	data[storeKey(P4)].Home = homeOf(0, { "", b })
	s4 = join("P3Slots", P4)
	T.check(sameList(DataS.GetTeams(s4).Presets[1], { a, b, c }) and DataS.GetTeams(s4).Slots == 3,
		"p3 save: ...without the prestige only 3 pets stay (slot 4 dropped); a pet working in the stored Garden ('' = empty slot) STAYS (Phase 4: garden pets fight)", listText(DataS.GetTeams(s4).Presets[1]))
	K.removePlayers({ s4 })
	advance(2)

	-- ResetFields({ Teams, Battle }): cleared trials, event pets and best values would merge back otherwise
	local RS = 953206
	data[storeKey(RS)] = {
		Version = 2, Tokens = 0, Pets = { [a] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(), Teams = { Presets = { { a } }, Active = 1 },
		Battle = { Trophies = 50, TrialBest = 6, TrialCleared = { true, true, true, true, true, true }, Raids = 3, RaidBestDamage = 900, PvPWins = 4, PvPLosses = 4, EventPets = { [a] = true } },
	}
	local rr = join("P3Reset", RS)
	local function wipeLive()
		local rp = DataS.GetProfile(rr)
		rp.Teams = { Presets = { {}, {}, {} }, Active = 1 }
		rp.Battle = { Trophies = 0, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} }
		DataS.MarkDirty(rr)
	end
	wipeLive()
	DataS.Save(rr)
	local srb = (stored(RS) or {}).Battle or {}
	T.check(srb.TrialBest == 6 and #clearedLevels(srb.TrialCleared) == 6 and srb.RaidBestDamage == 900 and srb.Trophies == 0,
		"p3 save: (without ResetFields the cleared trials / best values come back: they only grow; trophies follow as a delta)")
	advance(0.5)
	wipeLive()
	T.eq(DataS.ResetFields(rr, { Teams = true, Battle = true }), true, "p3 save: ResetFields accepts Teams and Battle")
	DataS.Save(rr)
	local sr = stored(RS) or {}
	T.check(sr.Teams == nil and sr.Battle == nil, "p3 save: ...and the empty team and record are written over the stored ones (then left out as defaults)")
	advance(0.5)
	T.check(#DataS.GetTeams(rr).Presets[1] == 0 and DataS.GetBattle(rr).TrialBest == 0 and count(DataS.GetBattle(rr).TrialCleared) == 0,
		"p3 save: ...and the save did not merge the old record back into the live profile")
	K.removePlayers({ rr })
	advance(2)

	-- provisional profiles: no team edits and no first-clear decisions from stand-in data; trophies still count
	local PV = 953207
	data[storeKey(PV)] = {
		Version = 2, Tokens = 0, Pets = { [a] = 1, [b] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(), Teams = { Presets = { { a } }, Active = 1 },
		Battle = { Trophies = 20, TrialBest = 2, TrialCleared = { true, true }, Raids = 0, RaidBestDamage = 0, PvPWins = 1, PvPLosses = 0, EventPets = {} },
	}
	DSt.Fail = true
	local v = Mock.AddPlayer("P3Outage", PV)
	advance(4)
	local provisional = type(DataS.IsProvisional) == "function" and DataS.IsProvisional(v)
	T.check(provisional, "p3 save: (precondition) the outage makes the profile provisional")
	T.eq(DataS.GetTeams(v), nil, "p3 save: GetTeams is nil while provisional")
	T.eq(#DataS.ActiveTeamKeys(v), 0, "p3 save: ActiveTeamKeys is {} while provisional")
	local okT, whyT = DataS.SetTeam(v, 1, { b })
	T.check(okT == false and type(whyT) == "string", "p3 save: SetTeam refuses while provisional", tostring(whyT))
	T.eq((DataS.SelectTeam(v, 2)), false, "p3 save: ...so does SelectTeam")
	T.eq(DataS.GetBattle(v), nil, "p3 save: GetBattle is nil (stand-in data never decides a first clear)")
	local firstClear = false
	local okClear = DataS.MutateBattle(v, function(battle)
		if not battle.TrialCleared[1] then
			battle.TrialCleared[1] = true
			firstClear = true
		end
	end)
	T.check(okClear == false and firstClear == true, "p3 save: MutateBattle rolls a trial clear back while provisional (-> false: the caller pays no first-clear bonus)")
	T.eq(DataS.MutateBattle(v, function(battle)
		battle.PvPWins = battle.PvPWins + 1
		battle.Trophies = battle.Trophies + 2
	end), true, "p3 save: ...but counters (they merge as deltas) still count")
	T.eq((DataS.AddTrophies(v, 3)), true, "p3 save: AddTrophies works while provisional")
	DSt.Fail = false
	local recovered = K.waitFor(function()
		return not DataS.IsProvisional(v)
	end, 40)
	T.check(recovered, "p3 save: (the recovery reads the real save)")
	advance(1)
	local vb = DataS.GetBattle(v)
	T.check(vb and vb.Trophies == 25 and vb.PvPWins == 2 and vb.TrialBest == 2 and sameList(clearedLevels(vb.TrialCleared), { 1, 2 }),
		"p3 save: after the recovery the stored record is intact with the outage's deltas on top (20 + 2 + 3 trophies, a win)",
		vb and (tostring(vb.Trophies) .. " / " .. tostring(vb.PvPWins)) or "no record")
	T.check(DataS.GetTeams(v) and sameList(DataS.GetTeams(v).Presets[1], { a }), "p3 save: ...and the stored team is back")
	K.removePlayers({ v })
	advance(3)

	-- the owner's /reset in the live game (DataStores on) survives the next autosave
	local devModule = K.moduleInstance("server/Services/DevService")
	local Dev = devModule and require(devModule)
	if Dev and type(Dev.Run) == "function" then
		local OWNER = 953208
		data[storeKey(OWNER)] = {
			Version = 2, Tokens = 100, Pets = { [a] = 1, [b] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(), Teams = { Presets = { { a, b } }, Active = 1 },
			Battle = { Trophies = 30, TrialBest = 3, TrialCleared = { true, true, true }, Raids = 1, RaidBestDamage = 400, PvPWins = 2, PvPLosses = 0, EventPets = { [b] = true } },
		}
		local saved = { Studio = Mock.Options.Studio, CreatorId = game.CreatorId, CreatorType = game.CreatorType, Enabled = Config.Dev.Enabled }
		local joined = {}
		local okRun, errRun = pcall(function()
			Mock.Options.Studio = false
			game.CreatorType = Enum.CreatorType.User
			game.CreatorId = OWNER
			Config.Dev.Enabled = true
			local owner = Mock.AddPlayer("P3ResetOwner", OWNER)
			joined[#joined + 1] = owner
			advance(1.5)
			T.check(#DataS.ActiveTeamKeys(owner) == 2 and (DataS.GetBattle(owner) or {}).TrialBest == 3, "p3 dev reset: (precondition) the owner's save has a team and a battle record")
			advance(0.6)
			T.eq((Dev.Run(owner, "reset", nil, "smoke")), true, "p3 dev reset: /reset runs for the owner in the live game")
			advance((Config.Tokens.AutosaveSeconds or 90) + 5)
			local s = stored(OWNER) or {}
			T.check(s.Teams == nil and s.Battle == nil and count(s.Pets) == 0,
				"p3 dev reset: after the next autosave the STORED profile has no team and no battle record (cleared trials, event pets and best values do not merge back)")
			local live = DataS.GetBattle(owner)
			T.check(live and live.TrialBest == 0 and live.Trophies == 0 and count(live.TrialCleared) == 0 and count(live.EventPets) == 0 and #DataS.ActiveTeamKeys(owner) == 0,
				"p3 dev reset: ...and the live profile agrees")
		end)
		K.removePlayers(joined)
		Mock.Options.Studio = saved.Studio
		game.CreatorType = saved.CreatorType
		game.CreatorId = saved.CreatorId
		Config.Dev.Enabled = saved.Enabled
		if not okRun then
			error(errRun, 0)
		end
		advance(2)
	else
		T.warn("p3 dev reset: DevService is missing: the live-game reset check was skipped")
	end
	K.flushErrors("p3data_save")
	K.flushWarnings("p3data_save", { "[DataService]" })
end)

return S
