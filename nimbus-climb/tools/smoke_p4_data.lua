-- smoke_p4_data.lua: Phase 4 "Data" (ARCHITECTURE_V3.md "Phase 4 build contract" section 4: schema, the one-time
-- migration of Phase 3 saves, the cross-server merge rules, the rollout with Phase 3 servers still running, the
-- developer reset and /petlevel) of server/Services/DataService.lua and server/Services/DevService.lua. Server world
-- only (listed in server_files of tools/smoke.py); the scenarios run in the p3data slot, before the care block:
--   p4data_growth    (booted) the Phase 4 API exists and Migrated is created at module load; a new profile's defaults
--                    (no growth, Ring 0 / 0, migrated at its first load); MutateGrowth edits + cleaning (clamps, junk
--                    keys, the Job rules: Stat, Rank = rank + 1, Ends, Slot, From, Paid; an all-zero entry goes),
--                    rollback on error / false, no Evo / rank down (an owned entry removed keeps its numbers, an
--                    unowned one may go), copies handed out; TrainingKeys is the read-time lock: FieldableKeys and
--                    ActiveTeamKeys skip a training pet while SetTeam / the preset keep it; P3.placedCopies counts
--                    Home.Garden + Home.Gym (bug batch 2 #18: a garden pet is busy, leaves its team and is refused);
--                    GetEvolution / SetEvolution (only up, PetCatalog.MaxEvolution per rarity, owned keys); GetRing /
--                    MutateRing (Best only up, Runs whole >= 0, rollback); IsMigrated / MarkMigrated; SetPetLevel
--                    (1..the curve's max level 100); the synced PetGrowth (zero numbers left out) and Ring
--   p4data_save      (booted, DataStore) a Phase 3 save loads with the defaults; the stored encoding (defaults left
--                    out, zero numbers left out, the Job stored, no sparse array, Version 2, ~80 bytes per key: 150
--                    fully trained keys < 12 KB); junk in the store cleaned on load; the merge against a concurrent
--                    server (Evo and ranks keep the higher value: two servers completing one rank = one rank; a stale
--                    Job dropped; Job replace / false / untouched; a removed key; Ring Best max / Runs delta, never
--                    below 0; Migrations union; LegacySlots / LegacyPrices per key, a higher Prestige dropping them);
--                    normalizeEquipped drops a training key on load; ResetFields({ PetGrowth, Ring }); provisional
--                    refusals; a REAL second server (a second copy of the module on the same mock store) completing
--                    the same job and evolving the pet while the first server completed it; a late save that ends an
--                    old job, or a third server's stale start, never wipes the NEWER paid job another server started
--                    (P4.newerJob: same skill, higher target rank), and two completions still give one rank
--   p4data_migrate   (booted, DataStore) P4.migrate on a Phase 3 veteran (LegacySlots above 3 + stars, LegacyPrices
--                    after a prestige, the Gym emptied with its keys reported, Migrations.P4, the Migrated signal and
--                    MigratedNow, Home Level / tier / Garden untouched, no Cash payout), the small cases (a Garden at
--                    the free count, no prestige, a new player), idempotent (a second load, a Gym pet put back),
--                    after a provisional load it runs on the recovery (ProfileRebased), two servers migrating the
--                    same save merge to one result, the next prestige clears the extras, a Phase 3 prestige keeps them
--   p4data_dev       (booted, live game) the owner's /reset wipes PetGrowth, zeroes Ring, keeps Migrations, calls
--                    PetCareService.ClearSessions / TycoonService.ClearCoins when they exist and survives the next
--                    autosave (ResetFields); /petlevel <1..100> sets every equipped pet's level (handler, chat, refusals,
--                    help, TextChatCommand, provisional)
--   p4data_rollout   (booted, DataStore) tools/fixtures/DataService_phase3.lua (the frozen Phase 3 release) runs as a
--                    second module against the same mock store: it loads and saves a Phase 4 profile and PetGrowth,
--                    Ring, Migrations, Home.LegacySlots / LegacyPrices, the station levels, the Home Level and a
--                    level-57 pet come back untouched; a training key it equipped is dropped by the Phase 4 load; its
--                    AddPetXp with the Phase 3 cap (50) keeps a level-57 pet at 57 and only zeroes its XP
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance, mod, config = K.advance, K.mod, K.config

local S = {}

local STATS = { "Speed", "Physique", "Ability", "Defense" }

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

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
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

-- rough serialized (JSON-like) size in bytes of a plain value
local function sizeOf(value)
	if type(value) == "table" then
		local n = 2
		for k, v in pairs(value) do
			n = n + #tostring(k) + 4 + sizeOf(v)
		end
		return n
	end
	return #tostring(value)
end

-- a growth entry as text (for failure details)
local function growthText(e)
	if type(e) ~= "table" then
		return tostring(e)
	end
	local job = "-"
	if type(e.Job) == "table" then
		job = tostring(e.Job.Stat) .. "/" .. tostring(e.Job.Rank) .. "/" .. tostring(e.Job.Ends) .. "/" .. tostring(e.Job.Slot) .. "/" .. tostring(e.Job.From) .. "/" .. tostring(e.Job.Paid)
	end
	return "{Evo " .. tostring(e.Evo) .. " S" .. tostring(e.Speed) .. " P" .. tostring(e.Physique) .. " A" .. tostring(e.Ability) .. " D" .. tostring(e.Defense) .. " Job " .. job .. "}"
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

-- one Epic-or-rarer catalog pet (it evolves twice)
local function epicId()
	local PC = K.M["shared/PetCatalog"]
	for _, def in ipairs(PC.Pets) do
		if type(def.Id) == "string" and def.EventOnly ~= true and (def.Rarity == "Epic" or def.Rarity == "Legendary" or def.Rarity == "Mythic") then
			return def.Id
		end
	end
	return nil
end

-- The signals a DataService copy hooks on its first Load (DataService.hook: the leave save on Players.PlayerRemoving
-- and the RequestProfile resync); a thrown-away copy must drop them again, or final_checks counts them as leaked
-- connections (the mock keeps every signal's connections in its `_conns` list).
local function hookedSignals()
	local out = { game:GetService("Players").PlayerRemoving }
	local folder = K.remoteFolder and K.remoteFolder()
	for _, name in ipairs({ "RequestProfile", "SettingsSet" }) do -- (Phase 5: DataService.hook also connects SettingsSet)
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

-- disconnects every connection made on the hooked signals since `marks`; true when each list is back at its mark
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

-- a second, independent copy of DataService (its own cache, the same mock DataStore): "another server". Returns the
-- module, its ModuleScript and release(): destroys the clone and drops the hooks it connected (true when none leaked).
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
		since = function(p, mark)
			local out = {}
			for i = mark + 1, #fired do
				if fired[i].who == p and fired[i].name == "P4" then -- (Phase 5 fires "P5Dungeon" / "P5Home" on the same loads)
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

local function now()
	return os.time()
end

----------------------------------------------------------------------------------------------------
-- scenario: the growth / ring / migration API and the read-time training lock
----------------------------------------------------------------------------------------------------
S.p4data_growth = guarded("p4data_growth", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local missing = {}
	for _, fn in ipairs({ "GetGrowth", "GetGrowthMap", "MutateGrowth", "TrainingKeys", "GetEvolution", "SetEvolution", "GetRing", "MutateRing", "IsMigrated", "MarkMigrated", "MigratedNow", "SetPetLevel" }) do
		if type(DataS[fn]) ~= "function" then
			missing[#missing + 1] = fn
		end
	end
	if not T.check(#missing == 0, "p4 growth: DataService has GetGrowth / GetGrowthMap / MutateGrowth / TrainingKeys / GetEvolution / SetEvolution / GetRing / MutateRing / IsMigrated / MarkMigrated / MigratedNow / SetPetLevel", table.concat(missing, ", ")) then
		return
	end
	local signal = DataS.Migrated
	T.check(type(signal) == "table" and type(signal.Connect) == "function" and type(signal.Fire) == "function", "p4 growth: DataService.Migrated is a Util.Signal")
	local inst = K.moduleInstance("server/Services/DataService")
	local source = inst and inst.Source or ""
	T.check(string.find("\n" .. source, "\nDataService%.Migrated = Util%.Signal%(%)") ~= nil, "p4 growth: ...created at module load (a top-level statement)")

	local mark = K.logSize()
	local p = join("P4Growth", 954001)
	local prof = DataS.GetProfile(p)
	if not T.check(prof ~= nil, "p4 growth: (precondition) the profile loads") then
		return
	end
	-- defaults
	local g0 = DataS.GetGrowth(p, "pebble_pup")
	T.check(type(g0) == "table" and g0.Evo == 0 and g0.Speed == 0 and g0.Physique == 0 and g0.Ability == 0 and g0.Defense == 0 and g0.Job == nil,
		"p4 growth: GetGrowth of a pet without growth is all zeros without a Job", growthText(g0))
	T.check(count(DataS.GetGrowthMap(p)) == 0 and count(DataS.TrainingKeys(p)) == 0, "p4 growth: GetGrowthMap / TrainingKeys of a new profile are empty")
	local ring0 = DataS.GetRing(p)
	T.check(type(ring0) == "table" and ring0.Best == 0 and ring0.Runs == 0, "p4 growth: GetRing of a new profile is { Best 0, Runs 0 }")
	T.check(type(prof.PetGrowth) == "table" and type(prof.Ring) == "table" and prof.Ring.Best == 0 and type(prof.Migrations) == "table",
		"p4 growth: the live profile holds PetGrowth, Ring { Best, Runs } and Migrations")
	T.check(DataS.IsMigrated(p, "P4") == true and prof.Migrations.P4 == true, "p4 growth: a brand-new profile is marked Migrations.P4 at its first load (nothing old to migrate)")
	local info0 = DataS.MigratedNow(p, "P4")
	T.check(type(info0) == "table" and info0.Veteran == false and info0.GymPets == 0 and info0.LegacySlots == nil and info0.LegacyPrices == false,
		"p4 growth: MigratedNow(player, 'P4') of a new player says Veteran = false (no welcome toast)")
	local snap = lastSnapshot(p, mark)
	T.check(type(snap) == "table" and type(snap.PetGrowth) == "table" and count(snap.PetGrowth) == 0 and type(snap.Ring) == "table" and snap.Ring.Best == 0 and snap.Ring.Runs == 0,
		"p4 growth: ProfileSync carries PetGrowth {} and Ring { Best, Runs } from the join on")

	-- pets: two copies of a (Common), one b, one c, one Epic
	local ids = petIds(5)
	local a, b, c, d = ids[1], ids[2], ids[3], ids[4]
	local epic = epicId()
	prof.Pets[a] = 2
	prof.Pets[b] = 1
	prof.Pets[c] = 1
	prof.Pets[d] = 1
	if epic then
		prof.Pets[epic] = 1
	end
	DataS.MarkDirty(p)
	local t0 = now()

	-- MutateGrowth: edits + cleaning
	local ok = DataS.MutateGrowth(p, function(g)
		g[a] = { Evo = 1, Speed = 3, Physique = 12, Ability = -2, Defense = 2.7, Job = { Stat = "Speed", Ends = t0 + 60, Rank = 4, Slot = 1, From = "Follow", Paid = 1200.5 } }
		g[b] = { Evo = 0, Speed = 0 } -- all zero, no job: not kept
		g[""] = { Evo = 1 }
		g[string.rep("x", 60)] = { Evo = 1 }
		g[5] = { Evo = 1 }
		g[c] = "junk"
	end)
	local ga = DataS.GetGrowth(p, a)
	T.check(ok == true and ga.Evo == 1 and ga.Speed == 3 and ga.Physique == 10 and ga.Ability == 0 and ga.Defense == 2,
		"p4 growth: MutateGrowth edits the live map; numbers are whole and clamped (Evo 0..2, ranks 0..10)", growthText(ga))
	T.check(type(ga.Job) == "table" and ga.Job.Stat == "Speed" and ga.Job.Ends == t0 + 60 and ga.Job.Rank == 4 and ga.Job.Slot == 1 and ga.Job.From == "Follow" and ga.Job.Paid == 1200,
		"p4 growth: ...a Job { Stat, Ends, Rank = the stat's rank + 1, Slot, From, Paid (whole Cash) } is kept", growthText(ga))
	local map = DataS.GetGrowthMap(p)
	T.check(count(map) == 1 and map[a] ~= nil, "p4 growth: ...an all-zero entry without a Job, junk keys ('' / 60 chars / a number) and a non-table entry are dropped", tostring(count(map)))
	T.check(prof.PetGrowth[b] == nil and prof.PetGrowth[c] == nil and prof.PetGrowth[5] == nil, "p4 growth: ...in place (the live map is clean too)")
	-- the Job rules
	local function jobOf(key, job, extra)
		DataS.MutateGrowth(p, function(g)
			g[key] = g[key] or {}
			for k, v in pairs(extra or {}) do
				g[key][k] = v
			end
			g[key].Job = job
		end)
		return DataS.GetGrowth(p, key).Job
	end
	T.eq(jobOf(a, { Stat = "Speed", Ends = t0 + 60, Rank = 6, Slot = 1 }), nil, "p4 growth: a Job whose Rank is not the stat's rank + 1 is dropped (Speed 3, Rank 6)")
	T.eq(jobOf(a, { Stat = "Speed", Ends = t0 + 60, Rank = 3, Slot = 1 }), nil, "p4 growth: ...also a Rank at or below the stored rank (Speed 3, Rank 3: completed elsewhere)")
	T.eq(jobOf(a, { Stat = "Luck", Ends = t0 + 60, Rank = 1, Slot = 1 }), nil, "p4 growth: a Job with a Stat other than Speed / Physique / Ability / Defense is dropped")
	T.eq(jobOf(a, { Stat = "Ability", Ends = 0, Rank = 1, Slot = 1 }), nil, "p4 growth: a Job without a sane Ends time is dropped")
	T.eq(jobOf(a, { Stat = "Ability", Ends = t0 + 5, Rank = 1, Slot = 6 }), nil, "p4 growth: a Job on a mat other than 1..5 is dropped")
	T.eq(jobOf(a, { Stat = "Ability", Ends = t0 + 5, Rank = 1, Slot = "2" }), nil, "p4 growth: ...and a non-numeric Slot")
	local longFrom = jobOf(a, { Stat = "Ability", Ends = t0 + 5, Rank = 1, Slot = 2, From = string.rep("G", 30), Paid = -5 })
	T.check(type(longFrom) == "table" and longFrom.From == nil and longFrom.Paid == 0 and longFrom.Rank == 1 and longFrom.Slot == 2,
		"p4 growth: an over-long From is dropped from the Job (the Job stays); Paid never below 0", growthText(DataS.GetGrowth(p, a)))
	T.check(jobOf(a, nil) == nil and DataS.GetGrowth(p, a).Speed == 3, "p4 growth: Job = nil clears the job and keeps the ranks")
	-- rollback
	ok = DataS.MutateGrowth(p, function(g)
		g[a].Speed = 9
		error("boom", 0)
	end)
	T.check(ok == false and DataS.GetGrowth(p, a).Speed == 3, "p4 growth: an error inside fn restores the map (-> false)")
	ok = DataS.MutateGrowth(p, function(g)
		g[a].Speed = 9
		g[d] = { Evo = 1 }
		return false
	end)
	T.check(ok == false and DataS.GetGrowth(p, a).Speed == 3 and DataS.GetGrowth(p, d).Evo == 0, "p4 growth: fn returning false restores it too")
	-- no Evo / rank down
	ok = DataS.MutateGrowth(p, function(g)
		g[a].Speed = 1
		g[a].Evo = 0
		g[a].Defense = 5
	end)
	ga = DataS.GetGrowth(p, a)
	T.check(ok == true and ga.Speed == 3 and ga.Evo == 1 and ga.Defense == 5, "p4 growth: no Evo / rank may go down through MutateGrowth (the store merges them as the higher value); a rise counts", growthText(ga))
	ok = DataS.MutateGrowth(p, function(g)
		g[a] = nil
	end)
	ga = DataS.GetGrowth(p, a)
	T.check(ok == true and ga.Speed == 3 and ga.Evo == 1 and ga.Job == nil, "p4 growth: an owned pet's entry that fn removed keeps its numbers (a trained pet is never wiped by mistake)", growthText(ga))
	DataS.MutateGrowth(p, function(g)
		g.ghost_of_a_fused_pet = { Evo = 2, Speed = 10 }
	end)
	T.eq(DataS.GetGrowth(p, "ghost_of_a_fused_pet").Evo, 2, "p4 growth: (precondition) an entry of a key the player does not own")
	DataS.MutateGrowth(p, function(g)
		g.ghost_of_a_fused_pet = nil
	end)
	T.check(DataS.GetGrowth(p, "ghost_of_a_fused_pet").Evo == 0 and DataS.GetGrowthMap(p).ghost_of_a_fused_pet == nil, "p4 growth: ...the entry of a key no longer owned (fused away, released) may be removed")
	-- copies
	local copy = DataS.GetGrowth(p, a)
	copy.Speed = 10
	local mapCopy = DataS.GetGrowthMap(p)
	mapCopy[a].Evo = 2
	T.check(DataS.GetGrowth(p, a).Speed == 3 and DataS.GetGrowth(p, a).Evo == 1, "p4 growth: GetGrowth / GetGrowthMap hand out copies")
	T.check(DataS.MutateGrowth(p, nil) == false and DataS.MutateGrowth(nil, function() end) == false and DataS.MutateGrowth(p, "fn") == false and deepEqual(DataS.GetGrowth(nil, a), DataS.GetGrowth(p, "nope")),
		"p4 growth: junk arguments are refused (a nil player reads as zeros)")

	-- the training lock: a READ-TIME filter
	T.check(DataS.SetTeam(p, 1, { a, b, c }) == true and DataS.SelectTeam(p, 1) == true, "p4 growth: (precondition) team 1 = { a, b, c }")
	ok = DataS.MutateGrowth(p, function(g)
		g[b] = { Job = { Stat = "Physique", Ends = t0 + 120, Rank = 1, Slot = 1, From = "Follow", Paid = 300 } }
	end)
	local training = DataS.TrainingKeys(p)
	T.check(ok == true and training[b] == true and count(training) == 1, "p4 growth: TrainingKeys lists a key with a running Job (an entry of zeros + Job is kept)", listText(DataS.ActiveTeamKeys(p)))
	T.check(sameList(DataS.ActiveTeamKeys(p), { a, c }) and sameList(DataS.GetTeams(p).Presets[1], { a, b, c }),
		"p4 growth: ActiveTeamKeys skips the training pet at read time while the preset keeps it (no pruning)", listText(DataS.ActiveTeamKeys(p)) .. " / " .. listText(DataS.GetTeams(p).Presets[1]))
	local fieldable = DataS.FieldableKeys(p)
	local hasB, hasA = false, false
	for _, key in ipairs(fieldable) do
		hasB = hasB or key == b
		hasA = hasA or key == a
	end
	T.check(not hasB and hasA, "p4 growth: FieldableKeys skips the training pet (the Team picker does not offer it)", listText(fieldable))
	local okTeam, whyTeam = DataS.SetTeam(p, 2, { b, d })
	T.check(okTeam == true and sameList(DataS.GetTeams(p).Presets[2], { b, d }), "p4 growth: SetTeam still ACCEPTS a training pet in a preset (P3.checkTeam is not taught about training)", tostring(whyTeam))
	DataS.MutateGrowth(p, function(g)
		g[b].Job = nil
	end)
	T.check(count(DataS.TrainingKeys(p)) == 0 and sameList(DataS.ActiveTeamKeys(p), { a, b, c }) and DataS.GetGrowthMap(p)[b] == nil,
		"p4 growth: the job done, the pet is back in the active team at once (its empty entry goes)", listText(DataS.ActiveTeamKeys(p)))
	-- bug batch 2 #18: garden pets are busy again (P3.placedCopies counts Home.Garden + Home.Gym); a Gym copy still is
	T.check(DataS.MutateHome(p, function(home)
		home.Garden[1] = c
	end) == true and sameList(DataS.GetTeams(p).Presets[1], { a, b }) and sameList(DataS.ActiveTeamKeys(p), { a, b }),
		"p4 growth: a pet whose only copy goes to the Garden leaves its team (bug batch 2 #18: busy gardening)", listText(DataS.GetTeams(p).Presets[1]))
	okTeam, whyTeam = DataS.SetTeam(p, 3, { c })
	T.check(okTeam == false and tostring(whyTeam):find("gardening", 1, true) ~= nil, "p4 growth: ...and SetTeam refuses a garden pet ('gardening')", tostring(whyTeam))
	DataS.MutateHome(p, function(home)
		home.Garden[1] = nil
	end)
	T.check(DataS.MutateHome(p, function(home)
		home.Gym[1] = d
	end) == true and sameList(DataS.GetTeams(p).Presets[2], { b }), "p4 growth: a pet whose only copy sits in the (retired) Gym still leaves its team (Phase 3 data written during the rollout stays understood)", listText(DataS.GetTeams(p).Presets[2]))
	DataS.MutateHome(p, function(home)
		home.Gym[1] = nil
	end)

	-- evolution
	T.eq(DataS.GetEvolution(p, a), 1, "p4 growth: GetEvolution reads the stored stage")
	T.eq(DataS.GetEvolution(p, "nothing_here"), 0, "p4 growth: ...0 for a pet without growth")
	T.check(DataS.SetEvolution(p, a, 1) == false and DataS.SetEvolution(p, a, 0) == false, "p4 growth: SetEvolution refuses a stage not above the stored one")
	T.check(DataS.SetEvolution(p, a, 2) == false and DataS.GetEvolution(p, a) == 1, "p4 growth: a Common pet has no second evolution (PetCatalog.MaxEvolution)")
	T.check(DataS.SetEvolution(p, b, 1) == true and DataS.GetEvolution(p, b) == 1, "p4 growth: SetEvolution raises the stage of an owned pet (0 -> 1)")
	if epic then
		T.check(DataS.SetEvolution(p, epic, 2) == true and DataS.GetEvolution(p, epic) == 2, "p4 growth: an Epic pet reaches stage 2 (" .. epic .. ")")
		T.check(DataS.SetEvolution(p, epic, 3) == false and DataS.SetEvolution(p, epic, 1.5) == false, "p4 growth: stage 3 and a fraction are refused")
	end
	T.check(DataS.SetEvolution(p, "no_such_pet", 1) == false and DataS.SetEvolution(p, "", 1) == false and DataS.SetEvolution(nil, a, 1) == false,
		"p4 growth: SetEvolution refuses a key not owned, junk and a nil player")
	DataS.MutateGrowth(p, function(g)
		g[b].Evo = 0
	end)
	T.eq(DataS.GetEvolution(p, b), 1, "p4 growth: a stage never goes down through MutateGrowth either")

	-- the Champion Ring record
	ok = DataS.MutateRing(p, function(ring)
		ring.Best = 5
		ring.Runs = 1
	end)
	local ring = DataS.GetRing(p)
	T.check(ok == true and ring.Best == 5 and ring.Runs == 1, "p4 growth: MutateRing edits the live record", tostring(ring.Best) .. "/" .. tostring(ring.Runs))
	ok = DataS.MutateRing(p, function(r)
		r.Best = 2
		r.Runs = r.Runs + 1.7
	end)
	ring = DataS.GetRing(p)
	T.check(ok == true and ring.Best == 5 and ring.Runs == 2, "p4 growth: Best never goes down (the store keeps the higher), Runs is a whole number", tostring(ring.Best) .. "/" .. tostring(ring.Runs))
	ok = DataS.MutateRing(p, function(r)
		r.Runs = -4
		r.Best = "lots"
	end)
	ring = DataS.GetRing(p)
	T.check(ok == true and ring.Runs == 0 and ring.Best == 5, "p4 growth: Runs never below 0; junk Best reads as 0 and loses against the stored 5")
	ok = DataS.MutateRing(p, function(r)
		r.Best = 50
		error("boom", 0)
	end)
	T.check(ok == false and DataS.GetRing(p).Best == 5, "p4 growth: an error inside fn restores the record (-> false)")
	ok = DataS.MutateRing(p, function(r)
		r.Best = 50
		return false
	end)
	T.check(ok == false and DataS.GetRing(p).Best == 5, "p4 growth: fn returning false restores it too")
	local ringCopy = DataS.GetRing(p)
	ringCopy.Best = 99
	T.check(DataS.GetRing(p).Best == 5 and prof.Ring.Best == 5, "p4 growth: GetRing hands out a copy; the live record is clean")
	T.check(DataS.MutateRing(p, nil) == false and DataS.MutateRing(nil, function() end) == false and DataS.GetRing(nil) == nil, "p4 growth: MutateRing / GetRing refuse junk")

	-- migration markers
	T.check(DataS.IsMigrated(p, "Later") == false and DataS.MarkMigrated(p, "Later") == true and DataS.IsMigrated(p, "Later") == true and prof.Migrations.Later == true,
		"p4 growth: MarkMigrated records a marker (IsMigrated follows)")
	T.check(DataS.MarkMigrated(p, "Later") == true and DataS.MarkMigrated(p, "") == false and DataS.MarkMigrated(p, 5) == false and DataS.IsMigrated(p, "") == nil and DataS.IsMigrated(nil, "P4") == nil,
		"p4 growth: MarkMigrated is idempotent and refuses junk; IsMigrated is nil for junk / a nil player")

	-- SetPetLevel (developer tools)
	local TC = K.M["shared/TycoonCatalog"]
	local cap = TC and (type(TC.PetXp) == "table" and TC.PetXp.MaxLevel or TC.MaxPetLevel) or 100
	T.eq(cap, 100, "p4 growth: (the curve's max level is 100: the player's rule)")
	T.check(DataS.SetPetLevel(p, a, 57) == true and (DataS.GetPetLevel(p, a)) == 57 and select(2, DataS.GetPetLevel(p, a)) == 0, "p4 growth: SetPetLevel(key, 57) writes { Level 57, Xp 0 } for an owned pet")
	T.check(DataS.SetPetLevel(p, a, cap) == true and (DataS.GetPetLevel(p, a)) == cap, "p4 growth: ...up to the curve's max level (" .. cap .. ")")
	T.check(DataS.SetPetLevel(p, a, cap + 1) == false and DataS.SetPetLevel(p, a, 0) == false and DataS.SetPetLevel(p, a, 20.5) == false and DataS.SetPetLevel(p, "no_such_pet", 5) == false
		and DataS.SetPetLevel(p, a, 0 / 0) == false and (DataS.GetPetLevel(p, a)) == cap,
		"p4 growth: SetPetLevel refuses a level past the cap, 0, a fraction, nan and a key not owned")
	T.check(DataS.SetPetLevel(p, a, 1) == true and (DataS.GetPetLevel(p, a)) == 1, "p4 growth: ...and goes down too (a developer tool, not a reward)")

	-- the synced shape
	DataS.MutateGrowth(p, function(g)
		g[c] = { Defense = 2, Job = { Stat = "Defense", Ends = t0 + 180, Rank = 3, Slot = 3, From = "Garden:1", Paid = 2700 } }
	end)
	mark = K.logSize()
	DataS.Sync(p)
	snap = lastSnapshot(p, mark)
	local sg = type(snap) == "table" and snap.PetGrowth or {}
	T.check(type(sg[a]) == "table" and sg[a].Evo == 1 and sg[a].Speed == 3 and sg[a].Physique == 10 and sg[a].Defense == 5 and sg[a].Ability == nil and sg[a].Job == nil,
		"p4 growth: ProfileSync sends a growth entry without its zero numbers (Ability 0 left out; the client fills them)", growthText(sg[a]))
	T.check(type(sg[c]) == "table" and sg[c].Defense == 2 and type(sg[c].Job) == "table" and sg[c].Job.Stat == "Defense" and sg[c].Job.Rank == 3 and sg[c].Job.From == "Garden:1" and sg[c].Job.Paid == 2700 and sg[c].Job.Ends == t0 + 180,
		"p4 growth: ...with the running Job (Stat, Ends, Rank, Slot, From, Paid)", growthText(sg[c]))
	T.check(type(snap) == "table" and type(snap.Ring) == "table" and snap.Ring.Best == 5 and snap.Ring.Runs == 0, "p4 growth: ...and the Ring record")
	T.check(type(snap) == "table" and snap.Migrations == nil, "p4 growth: ...the migration markers stay on the server")
	local holes = sparsePaths(type(snap) == "table" and snap or {}, "snapshot")
	T.check(type(snap) == "table" and #holes == 0, "p4 growth: the snapshot holds no sparse array or mixed table", table.concat(holes, ", "))
	local problems = K.V and type(K.V.profileSync) == "function" and K.V.profileSync(snap) or {}
	T.check(#problems == 0, "p4 growth: the snapshot passes the ProfileSync validator", table.concat(problems, " | "))

	K.removePlayers({ p })
	advance(2)
	K.flushErrors("p4data_growth")
	K.flushWarnings("p4data_growth", { "[DataService] MutateGrowth callback errored", "[DataService] MutateRing callback errored" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the store, the merge rules, provisional profiles, a real second server
----------------------------------------------------------------------------------------------------
S.p4data_save = guarded("p4data_save", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	if type(DataS.MutateGrowth) ~= "function" or type(DataS.MutateRing) ~= "function" then
		T.fail("p4 save: DataService has no MutateGrowth / MutateRing")
		return
	end
	local DSt = Mock.DataStore
	local data = DSt.Data
	local ids = petIds(6)
	local a, b, c, d, e, f = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]
	local t0 = now()
	local function homeOf(prestige, extra)
		local h = { Level = 0, Prestige = prestige or 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0, LastSeen = 0 }
		for k, v in pairs(extra or {}) do
			h[k] = v
		end
		return h
	end
	local function record(userId, extra)
		local rec = {
			Version = 2, Tokens = 0, Pets = { [a] = 1, [b] = 1, [c] = 1, [d] = 1, [e] = 1, [f] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(),
			Discovered = {}, IndexClaimed = {}, Tutorial = { Step = 1, Done = false, Gifted = false }, Cash = 0, Gems = 0, Home = homeOf(0), PetLevels = {},
			Migrations = { P4 = true },
		}
		for k, v in pairs(extra or {}) do
			rec[k] = v
		end
		data[storeKey(userId)] = rec
		return rec
	end

	-- a Phase 3 save (no Phase 4 fields) loads with the defaults; its first save adds only the marker
	local P3 = 954101
	record(P3, { Migrations = nil })
	local m = join("P4FromP3", P3)
	T.check(count(DataS.GetGrowthMap(m)) == 0 and DataS.GetRing(m).Best == 0 and DataS.GetRing(m).Runs == 0 and DataS.IsMigrated(m, "P4") == true,
		"p4 save: a Phase 3 save loads with no growth, Ring 0 / 0 and gets the P4 marker")
	K.removePlayers({ m })
	advance(2)
	local s3 = stored(P3) or {}
	T.check(s3.PetGrowth == nil and s3.Ring == nil and type(s3.Migrations) == "table" and s3.Migrations.P4 == true and s3.Version == 2,
		"p4 save: the save leaves the default PetGrowth / Ring out and holds Migrations { P4 = true }; Version stays 2")

	-- the stored encoding and a round trip
	local RT = 954102
	record(RT)
	local r = join("P4RoundTrip", RT)
	DataS.MutateGrowth(r, function(g)
		g[a] = { Evo = 1, Speed = 3, Job = { Stat = "Speed", Ends = t0 + 90, Rank = 4, Slot = 2, From = "Garden:3", Paid = 4800 } }
		g[b] = { Defense = 7 }
	end)
	DataS.MutateRing(r, function(ring)
		ring.Best = 12
		ring.Runs = 3
	end)
	DataS.MarkMigrated(r, "Extra")
	K.removePlayers({ r })
	advance(2)
	local sr = stored(RT) or {}
	local spg = type(sr.PetGrowth) == "table" and sr.PetGrowth or {}
	T.check(type(spg[a]) == "table" and spg[a].Evo == 1 and spg[a].Speed == 3 and spg[a].Physique == nil and spg[a].Ability == nil and spg[a].Defense == nil,
		"p4 save: the store holds PetGrowth entries without their zero numbers (~80 bytes per trained key)", growthText(spg[a]))
	T.check(type(spg[a]) == "table" and type(spg[a].Job) == "table" and spg[a].Job.Stat == "Speed" and spg[a].Job.Ends == t0 + 90 and spg[a].Job.Rank == 4 and spg[a].Job.Slot == 2 and spg[a].Job.From == "Garden:3" and spg[a].Job.Paid == 4800,
		"p4 save: ...with the running Job", growthText(spg[a]))
	T.check(type(spg[b]) == "table" and spg[b].Defense == 7 and spg[b].Evo == nil and spg[b].Job == nil, "p4 save: ...a trained pet without a job has its ranks only")
	T.check(type(sr.Ring) == "table" and sr.Ring.Best == 12 and sr.Ring.Runs == 3, "p4 save: ...Ring { Best, Runs }")
	T.check(type(sr.Migrations) == "table" and sr.Migrations.P4 == true and sr.Migrations.Extra == true, "p4 save: ...Migrations as a set")
	local holes = sparsePaths(sr, "record")
	T.check(#holes == 0 and sr.Version == 2, "p4 save: no sparse array or mixed table anywhere in the record; Version stays 2", table.concat(holes, ", "))
	local r2 = join("P4RoundTrip", RT)
	local back = DataS.GetGrowth(r2, a)
	T.check(back.Evo == 1 and back.Speed == 3 and back.Physique == 0 and type(back.Job) == "table" and back.Job.Rank == 4 and back.Job.From == "Garden:3" and DataS.GetGrowth(r2, b).Defense == 7
		and DataS.GetRing(r2).Best == 12 and DataS.GetRing(r2).Runs == 3 and DataS.IsMigrated(r2, "Extra") == true and DataS.TrainingKeys(r2)[a] == true,
		"p4 save: ...and it reads back the same (round trip; the zeros filled in; the training lock back)", growthText(back))
	T.check(DataS.MigratedNow(r2, "P4") == nil, "p4 save: a profile migrated earlier is not reported as migrated now")
	K.removePlayers({ r2 })
	advance(2)

	-- size: 150 fully trained, evolved keys
	local BIG = 954103
	local big = {}
	for i = 1, 150 do
		big["big_pet_" .. i .. "@Rainbow"] = { Evo = 2, Speed = 10, Physique = 10, Ability = 10, Defense = 10 }
	end
	record(BIG, { PetGrowth = big })
	local bp = join("P4Big", BIG)
	DataS.AddTokens(bp, 1)
	T.eq(DataS.Save(bp), true, "p4 save: (precondition) the big profile saves")
	local sbig = (stored(BIG) or {}).PetGrowth or {}
	local bytes = sizeOf(sbig)
	-- (JSON-like bytes: ~83 per fully trained, evolved key with a 19-character "<petId>@Rainbow" key, ~12.2 KB for 150: the
	-- contract's "~80 bytes / ~12 KB"; the DataStore limit is 4 MB)
	T.check(count(sbig) == 150 and bytes < 12800, "p4 save: 150 fully trained and evolved keys store under ~12.5 KB (" .. bytes .. " bytes, " .. math.floor(bytes / 150) .. " per key)")
	K.removePlayers({ bp })
	advance(2)

	-- junk in the store is cleaned on load
	local JK = 954104
	record(JK, {
		PetGrowth = {
			[a] = { Evo = 5, Speed = 11, Physique = -1, Ability = "x", Defense = 2.9, Job = { Stat = "Speed", Ends = t0 + 3600, Rank = 12, Slot = 1 } },
			[b] = { Speed = 2, Job = { Stat = "Speed", Ends = t0 + 3600, Rank = 2, Slot = 1, Paid = 100 } }, -- stale: completed elsewhere
			[c] = { Evo = 0 },
			[""] = { Evo = 1 },
			[d] = { Physique = 1, Job = { Stat = "Physique", Ends = t0 + 3600, Rank = 2, Slot = 5, From = "Free", Paid = 300 } },
		},
		Ring = { Best = 1e12, Runs = -3 },
		Migrations = { P4 = true, [""] = true, Bad = 5, "ListEntry" },
	})
	local j = join("P4Junk", JK)
	local ja = DataS.GetGrowth(j, a)
	T.check(ja.Evo == 2 and ja.Speed == 10 and ja.Physique == 0 and ja.Ability == 0 and ja.Defense == 2 and ja.Job == nil,
		"p4 save: stored junk is cleaned on load (Evo 5 -> 2, rank 11 -> 10, negative / text -> 0, a Job past rank 10 dropped)", growthText(ja))
	T.check(DataS.GetGrowth(j, b).Speed == 2 and DataS.GetGrowth(j, b).Job == nil, "p4 save: a stored Job whose Rank is not above the stored rank (completed elsewhere) is dropped")
	T.check(DataS.GetGrowthMap(j)[c] == nil and DataS.GetGrowthMap(j)[""] == nil and DataS.GetGrowth(j, d).Job ~= nil and DataS.GetGrowth(j, d).Job.Rank == 2,
		"p4 save: an all-zero entry and a junk key are dropped; a sane Job (Physique 1 -> 2) is kept")
	T.check(DataS.GetRing(j).Best == 100000 and DataS.GetRing(j).Runs == 0, "p4 save: Ring.Best is capped at 100000 and Runs never below 0")
	local nonP5 = 0
	for name in pairs(DataS.GetProfile(j).Migrations or {}) do
		-- (Phase 5 adds its own P5Dungeon / P5Home markers on the load, bug batch 2 #18 its B2GardenSolo marker, the HUD
		-- cleanup its B3ItemsRefund marker)
		if string.sub(tostring(name), 1, 2) ~= "P5" and name ~= "B2GardenSolo" and name ~= "B3ItemsRefund" then
			nonP5 = nonP5 + 1
		end
	end
	T.check(DataS.IsMigrated(j, "P4") == true and DataS.IsMigrated(j, "ListEntry") == true and DataS.IsMigrated(j, "Bad") == false and nonP5 == 2,
		"p4 save: Migrations reads as a set (a list entry counts, junk values do not)")
	K.removePlayers({ j })
	advance(2)

	-- the merge against a concurrent server (the store edited directly)
	local MG = 954105
	record(MG, {
		PetGrowth = {
			[a] = { Evo = 1, Speed = 2, Job = { Stat = "Speed", Ends = t0 + 30, Rank = 3, Slot = 1, From = "Follow", Paid = 2700 } },
			[b] = { Physique = 1 },
			[e] = { Ability = 1 },
		},
		Ring = { Best = 5, Runs = 2 },
		Home = homeOf(1, { Level = 10, Stations = { Press1 = 5, Garden = 5 }, LegacySlots = 6, LegacyPrices = true }),
	})
	local q = join("P4Merge", MG)
	T.check(DataS.GetGrowth(q, a).Job ~= nil and DataS.GetHome(q).LegacySlots == 6 and DataS.GetHome(q).LegacyPrices == true, "p4 save: (precondition) the stored growth and the veteran Home keys load")
	-- this session: a's job completes (rank 3), b trains Physique 2 and evolves, d starts a Defense job, e is left alone,
	-- the ring record grows (Best 7, one more run), LegacySlots is cleared (the Garden shrank), a new marker
	DataS.MutateGrowth(q, function(g)
		g[a].Speed = g[a].Job.Rank
		g[a].Job = nil
		g[b].Evo = 1
		g[b].Job = { Stat = "Physique", Ends = t0 + 120, Rank = 2, Slot = 2, From = "Free", Paid = 1200 }
		g[d] = { Job = { Stat = "Defense", Ends = t0 + 60, Rank = 1, Slot = 3, From = "Free", Paid = 300 } }
	end)
	DataS.MutateRing(q, function(ring)
		ring.Best = 7
		ring.Runs = ring.Runs + 1
	end)
	DataS.MutateHome(q, function(home)
		home.LegacySlots = nil
	end)
	DataS.MarkMigrated(q, "Mine")
	-- another server meanwhile: a's job completed there too (rank 3, no job), b evolved to stage 2, d's job completed
	-- (Defense 1, no job), e got a new job, f appeared, 2 more runs with a record of 6, another marker
	local other = data[storeKey(MG)]
	other.PetGrowth[a] = { Evo = 1, Speed = 3 }
	other.PetGrowth[b] = { Evo = 2, Physique = 1 }
	other.PetGrowth[d] = { Defense = 1 }
	other.PetGrowth[e] = { Ability = 1, Job = { Stat = "Ability", Ends = t0 + 300, Rank = 2, Slot = 4, From = "Follow", Paid = 1200 } }
	other.PetGrowth[f] = { Speed = 4 }
	other.Ring = { Best = 6, Runs = 4 }
	other.Migrations.Theirs = true
	T.eq(DataS.Save(q), true, "p4 save: (precondition) the session saves onto the changed store")
	local sq = stored(MG) or {}
	local pg = type(sq.PetGrowth) == "table" and sq.PetGrowth or {}
	T.check(type(pg[a]) == "table" and pg[a].Speed == 3 and pg[a].Job == nil and pg[a].Evo == 1,
		"p4 save: two servers completing the same job give ONE rank (Speed 3, not 4: ranks are target values, merged as the higher)", growthText(pg[a]))
	T.check(type(pg[b]) == "table" and pg[b].Evo == 2 and pg[b].Physique == 1 and type(pg[b].Job) == "table" and pg[b].Job.Rank == 2 and pg[b].Job.Slot == 2,
		"p4 save: Evo keeps the higher value (2 from the other server); the session's Job replaces", growthText(pg[b]))
	T.check(type(pg[d]) == "table" and pg[d].Defense == 1 and pg[d].Job == nil,
		"p4 save: a stale Job is dropped: the session started Defense 0 -> 1 while the other server completed it (rank 1 stays, no job, no double rank)", growthText(pg[d]))
	T.check(type(pg[e]) == "table" and type(pg[e].Job) == "table" and pg[e].Job.Rank == 2 and pg[e].Job.Slot == 4, "p4 save: a Job the session never touched is left alone (another server started it)", growthText(pg[e]))
	T.check(type(pg[f]) == "table" and pg[f].Speed == 4, "p4 save: a key only the other server has is kept")
	T.check(type(sq.Ring) == "table" and sq.Ring.Best == 7 and sq.Ring.Runs == 5, "p4 save: Ring.Best keeps the higher (7 here vs 6 there); Runs merges as a delta (2 -> 4 there, +1 here = 5)",
		type(sq.Ring) == "table" and (tostring(sq.Ring.Best) .. "/" .. tostring(sq.Ring.Runs)) or "no ring")
	T.check(type(sq.Migrations) == "table" and sq.Migrations.P4 == true and sq.Migrations.Mine == true and sq.Migrations.Theirs == true, "p4 save: Migrations merge as a union")
	local sh = type(sq.Home) == "table" and sq.Home or {}
	T.check(sh.LegacySlots == nil and sh.LegacyPrices == true, "p4 save: LegacySlots cleared by the session is gone; LegacyPrices (untouched) stays (per-key Home merge)")
	advance(0.5)
	T.check(DataS.GetGrowth(q, b).Evo == 2 and DataS.GetGrowth(q, a).Speed == 3 and DataS.GetRing(q).Runs == 5 and DataS.IsMigrated(q, "Theirs") == true and DataS.TrainingKeys(q)[e] == true,
		"p4 save: the live profile adopts the merged store (Evo 2, one rank, 5 runs, the other marker, e's job)")
	-- the session clears a job the store still has (Stop): false travels and clears it; a stored run count never below 0
	DataS.MutateGrowth(q, function(g)
		g[e].Job = nil
	end)
	DataS.MutateRing(q, function(ring)
		ring.Runs = 0
	end)
	other = data[storeKey(MG)]
	other.Ring.Runs = 2
	DataS.Save(q)
	sq = stored(MG) or {}
	T.check(type(sq.PetGrowth[e]) == "table" and sq.PetGrowth[e].Job == nil and sq.PetGrowth[e].Ability == 1, "p4 save: a job the session stopped travels as false and clears the stored one")
	T.eq(sq.Ring.Runs, 0, "p4 save: Runs never goes below 0 in the merge (2 stored, -5 here)")
	-- a removed entry of a key no longer owned travels as false
	local qp = DataS.GetProfile(q)
	qp.Pets[f] = nil
	DataS.MutateGrowth(q, function(g)
		g[f] = nil
	end)
	DataS.Save(q)
	T.check((stored(MG) or {}).PetGrowth[f] == nil, "p4 save: the entry of a key the session removed (no copies owned) leaves the store")
	-- a lower Best in the session never lowers the store; a higher stored Prestige wins the whole Home (its extras gone)
	other = data[storeKey(MG)]
	other.Ring.Best = 20
	other.Home = homeOf(2, { Level = 0, Stations = {} })
	DataS.MutateHome(q, function(home)
		home.LegacySlots = 7
		home.Stations.Press1 = 6
	end)
	DataS.AddTokens(q, 1)
	DataS.Save(q)
	sq = stored(MG) or {}
	T.check(sq.Ring.Best == 20 and sq.Home.Prestige == 2 and sq.Home.LegacySlots == nil and sq.Home.LegacyPrices == nil and sq.Home.Stations.Press1 == nil,
		"p4 save: a higher stored Prestige wins the whole Home (the session's LegacySlots and stations are void); Best keeps the higher (20)")
	K.removePlayers({ q })
	advance(2)

	-- normalizeEquipped drops a training key on load (a Phase 3 server may have equipped it)
	local EQ = 954106
	record(EQ, {
		Equipped = { a, b },
		PetGrowth = { [a] = { Job = { Stat = "Speed", Ends = t0 + 600, Rank = 1, Slot = 1, From = "Follow", Paid = 300 } } },
		Teams = { Presets = { { a, b } }, Active = 1 },
	})
	local eq = join("P4Equipped", EQ)
	local ep = DataS.GetProfile(eq)
	T.check(sameList(ep.Equipped, { b }) and DataS.TrainingKeys(eq)[a] == true, "p4 save: a training key is dropped from Equipped on load (the pet stays owned)", listText(ep.Equipped))
	T.check(sameList(DataS.GetTeams(eq).Presets[1], { a, b }) and sameList(DataS.ActiveTeamKeys(eq), { b }), "p4 save: ...its preset keeps it (P3.prune is not taught about training); ActiveTeamKeys skips it")
	K.removePlayers({ eq })
	advance(2)

	-- ResetFields({ PetGrowth, Ring }): stages, ranks and Best would merge back otherwise
	local RS = 954107
	record(RS, { PetGrowth = { [a] = { Evo = 1, Speed = 5, Defense = 2 } }, Ring = { Best = 30, Runs = 9 } })
	local rr = join("P4Reset", RS)
	local function wipeLive()
		local rp = DataS.GetProfile(rr)
		for key in pairs(rp.PetGrowth) do
			rp.PetGrowth[key] = nil
		end
		rp.Ring.Best, rp.Ring.Runs = 0, 0
		DataS.MarkDirty(rr)
	end
	-- without ResetFields: lower numbers lose against the stored ones (Evo / ranks / Best only rise; Runs is a delta)
	local rp0 = DataS.GetProfile(rr)
	rp0.PetGrowth[a] = { Evo = 0, Speed = 1, Defense = 1 }
	rp0.Ring.Best, rp0.Ring.Runs = 0, 0
	DataS.MarkDirty(rr)
	DataS.Save(rr)
	local srs = stored(RS) or {}
	T.check(type(srs.PetGrowth) == "table" and srs.PetGrowth[a] ~= nil and srs.PetGrowth[a].Speed == 5 and srs.PetGrowth[a].Defense == 2 and srs.PetGrowth[a].Evo == 1
		and type(srs.Ring) == "table" and srs.Ring.Best == 30 and srs.Ring.Runs == 0,
		"p4 save: (without ResetFields lowered stages / ranks / Best come back: they only rise; Runs follows as a delta, 9 - 9 = 0)", growthText((srs.PetGrowth or {})[a]) .. " " .. (type(srs.Ring) == "table" and tostring(srs.Ring.Best) .. "/" .. tostring(srs.Ring.Runs) or "-"))
	advance(0.5)
	T.check(DataS.GetGrowth(rr, a).Speed == 5 and DataS.GetGrowth(rr, a).Evo == 1 and DataS.GetRing(rr).Best == 30, "p4 save: ...and the live profile takes the stored values back")
	-- (a key deleted from the live map travels as false and leaves the store: the rule for a pet fused away or released;
	-- MutateGrowth keeps an OWNED key's numbers, so only a raw wipe or an unowned key gets here)
	wipeLive()
	DataS.Save(rr)
	srs = stored(RS) or {}
	T.check(srs.PetGrowth == nil and type(srs.Ring) == "table" and srs.Ring.Best == 30, "p4 save: a key deleted from the live map leaves the store (false in the delta); Best still comes back without ResetFields")
	advance(0.5)
	wipeLive()
	T.eq(DataS.ResetFields(rr, { PetGrowth = true, Ring = true }), true, "p4 save: ResetFields accepts PetGrowth and Ring")
	DataS.Save(rr)
	srs = stored(RS) or {}
	T.check(srs.PetGrowth == nil and srs.Ring == nil, "p4 save: ...and the empty map / zero record are written over the stored ones (then left out as defaults)")
	advance(0.5)
	T.check(count(DataS.GetGrowthMap(rr)) == 0 and DataS.GetRing(rr).Best == 0, "p4 save: ...and the save did not merge the old values back into the live profile")
	K.removePlayers({ rr })
	advance(2)

	-- provisional profiles: no growth / evolution / ring / level decisions from stand-in data
	local PV = 954108
	record(PV, { PetGrowth = { [a] = { Evo = 1, Speed = 2 } }, Ring = { Best = 4, Runs = 1 }, Migrations = { P4 = true } })
	DSt.Fail = true
	local v = Mock.AddPlayer("P4Outage", PV)
	advance(4)
	T.check(DataS.IsProvisional(v) == true, "p4 save: (precondition) the outage makes the profile provisional")
	T.check(DataS.MutateGrowth(v, function(g)
		g[a] = { Evo = 1 }
	end) == false and count(DataS.GetGrowthMap(v)) == 0 and count(DataS.TrainingKeys(v)) == 0, "p4 save: MutateGrowth is refused while provisional; GetGrowthMap / TrainingKeys answer {}")
	T.check(DataS.GetGrowth(v, a).Evo == 0, "p4 save: GetGrowth reads zeros while provisional (display only)")
	T.check(DataS.SetEvolution(v, a, 1) == false and DataS.GetEvolution(v, a) == 0, "p4 save: SetEvolution is refused while provisional")
	T.check(DataS.GetRing(v) == nil and DataS.MutateRing(v, function(ring)
		ring.Best = 9
	end) == false, "p4 save: GetRing is nil and MutateRing refused while provisional (the ring does not start)")
	T.check(DataS.SetPetLevel(v, a, 20) == false, "p4 save: SetPetLevel is refused while provisional")
	T.check(DataS.IsMigrated(v, "P4") == nil and DataS.MigratedNow(v, "P4") == nil, "p4 save: IsMigrated is nil (not decidable) and nothing was migrated from stand-in defaults")
	T.eq(DataS.MarkMigrated(v, "Outage"), true, "p4 save: MarkMigrated (a union) is allowed while provisional")
	DSt.Fail = false
	local recovered = K.waitFor(function()
		return not DataS.IsProvisional(v)
	end, 40)
	T.check(recovered, "p4 save: (the recovery reads the real save)")
	advance(1)
	T.check(DataS.GetGrowth(v, a).Evo == 1 and DataS.GetGrowth(v, a).Speed == 2 and DataS.GetRing(v) ~= nil and DataS.GetRing(v).Best == 4 and DataS.IsMigrated(v, "P4") == true and DataS.IsMigrated(v, "Outage") == true,
		"p4 save: after the recovery the stored growth / ring are intact and the in-outage marker joined them")
	T.check(DataS.MigratedNow(v, "P4") == nil, "p4 save: ...and the already-migrated save was not migrated again")
	K.removePlayers({ v })
	advance(3)

	-- a REAL second server: a second copy of the module on the same mock store
	local B, cloneB, releaseB = secondServer("DataServiceP4ServerB")
	if T.check(B ~= nil and type(B.MutateGrowth) == "function", "p4 save: a second copy of DataService loads as 'server B' (own cache, same store)", tostring(cloneB)) then
		local TWO = 954109
		-- (the jobs here end an hour out: server A runs PetCareService, whose tick completes a due job by itself; the
		-- completions below are the test's, written the way each server's tick writes them, at a moment it controls)
		record(TWO, { PetGrowth = { [a] = { Speed = 2, Job = { Stat = "Speed", Ends = t0 + 3630, Rank = 3, Slot = 1, From = "Free", Paid = 2700 } } } })
		local okB, errB = pcall(function()
			local tp = join("P4TwoServers", TWO)
			B.Load(tp)
			T.check(DataS.GetGrowth(tp, a).Job ~= nil and B.GetGrowth(tp, a).Job ~= nil and B.GetGrowth(tp, a).Job.Rank == 3, "p4 two servers: both servers hold the running job (rank 2 -> 3)")
			local function complete(DS)
				return DS.MutateGrowth(tp, function(g)
					g[a].Speed = g[a].Job.Rank
					g[a].Job = nil
				end)
			end
			T.check(complete(DataS) == true and complete(B) == true, "p4 two servers: both servers complete the same job (as each tick does once the clock passes Ends)")
			T.check(DataS.Save(tp) == true and B.Save(tp) == true, "p4 two servers: both save")
			local st = (stored(TWO) or {}).PetGrowth or {}
			T.check(type(st[a]) == "table" and st[a].Speed == 3 and st[a].Job == nil, "p4 two servers: the store holds rank 3 exactly once (not 4) and no job", growthText(st[a]))
			-- server B evolves a and starts the next job while server A (stale: it still thinks the job is running after a
			-- fresh load) completes it again later: B's whole entry travels, A's completion lands on the same rank
			T.check(B.SetEvolution(tp, a, 1) == true and B.MutateGrowth(tp, function(g)
				g[a].Job = { Stat = "Speed", Ends = t0 + 3690, Rank = 4, Slot = 1, From = "Free", Paid = 4800 }
			end) == true and B.Save(tp) == true, "p4 two servers: server B evolves the pet and starts rank 4")
			DataS.AddTokens(tp, 1)
			T.eq(DataS.Save(tp), true, "p4 two servers: server A saves a token (it adopts the store)")
			advance(0.3)
			local ga = DataS.GetGrowth(tp, a)
			T.check(ga.Evo == 1 and ga.Speed == 3 and type(ga.Job) == "table" and ga.Job.Rank == 4, "p4 two servers: server A sees B's evolution and B's new job after its save", growthText(ga))
			-- a stale job on server A: A loads an old record (the job to rank 4), B completes it (Speed 4) and A then
			-- only evolves the pet further... a Common cannot: A touches the entry (Defense 1), so its whole entry travels
			T.check(B.MutateGrowth(tp, function(g)
				g[a].Speed = 4
				g[a].Job = nil
			end) == true and B.Save(tp) == true, "p4 two servers: server B completes rank 4")
			T.check(DataS.MutateGrowth(tp, function(g)
				g[a].Defense = 1
			end) == true and DataS.Save(tp) == true, "p4 two servers: server A (still holding the rank-4 job) changes the entry and saves")
			st = (stored(TWO) or {}).PetGrowth or {}
			T.check(type(st[a]) == "table" and st[a].Speed == 4 and st[a].Job == nil and st[a].Defense == 1 and st[a].Evo == 1,
				"p4 two servers: A's stale Job (rank 4, completed by B) is dropped by the merge; the rank is 4, not 5; Defense 1 and the stage stay", growthText(st[a]))
			-- a LATE save must not wipe a newer job: B completes Defense 1 -> 2 and starts 2 -> 3 (and pays); A, still holding
			-- the 1 -> 2 job, completes it afterwards (its tick) and saves later: B's paid rank-3 job survives, the rank is 2
			B.AddTokens(tp, 1)
			T.check(B.Save(tp) == true and B.GetGrowth(tp, a).Defense == 1, "p4 two servers: (precondition) server B adopts A's Defense 1 through its own save")
			T.check(B.MutateGrowth(tp, function(g)
				g[a].Job = { Stat = "Defense", Ends = t0 + 3620, Rank = 2, Slot = 2, From = "Free", Paid = 1200 }
			end) == true and B.Save(tp) == true, "p4 two servers: (precondition) server B starts Defense 1 -> 2 and saves")
			DataS.AddTokens(tp, 1)
			T.check(DataS.Save(tp) == true and DataS.GetGrowth(tp, a).Job ~= nil and DataS.GetGrowth(tp, a).Job.Rank == 2, "p4 two servers: (precondition) server A adopts that job")
			T.check(B.MutateGrowth(tp, function(g)
				g[a].Defense = 2
				g[a].Job = { Stat = "Defense", Ends = t0 + 3800, Rank = 3, Slot = 2, From = "Free", Paid = 2700 }
			end) == true and B.Save(tp) == true, "p4 two servers: server B completes Defense 2 and starts the rank-3 job in one step, then saves")
			T.check(DataS.MutateGrowth(tp, function(g)
				g[a].Defense = g[a].Job.Rank
				g[a].Job = nil
			end) == true and DataS.Save(tp) == true, "p4 two servers: server A completes its (stale) rank-2 job afterwards and saves")
			st = (stored(TWO) or {}).PetGrowth or {}
			T.check(type(st[a]) == "table" and st[a].Defense == 2 and type(st[a].Job) == "table" and st[a].Job.Rank == 3 and st[a].Job.Paid == 2700 and st[a].Job.Ends == t0 + 3800,
				"p4 two servers: A's late clear names the job it ended (Defense -> 2): B's NEWER paid rank-3 job survives; the rank is 2 once", growthText(st[a]))
			advance(0.3)
			T.check(DataS.GetGrowth(tp, a).Job ~= nil and DataS.GetGrowth(tp, a).Job.Rank == 3 and DataS.TrainingKeys(tp)[a] == true, "p4 two servers: ...and server A adopts B's job (the lock is back on A)")
			-- a STALE start must not wipe it either: A thinks Defense is 2 with no job and starts 2 -> 3 itself? it cannot
			-- (A holds B's job now), so a fresh server C that loaded before B's save stands in: its base has no job
			local C, cloneC, releaseC = secondServer("DataServiceP4ServerC")
			if T.check(C ~= nil, "p4 two servers: a third copy of DataService loads as 'server C'", tostring(cloneC)) then
				local okC, errC = pcall(function()
					local rec = data[storeKey(TWO)]
					local keptJob = rec.PetGrowth[a].Job
					rec.PetGrowth[a].Job = nil -- C loads an older picture of the store: Defense 2, no job
					C.Load(tp)
					T.check(C.GetGrowth(tp, a).Job == nil and C.GetGrowth(tp, a).Defense == 2, "p4 two servers: (precondition) server C sees Defense 2 and no job")
					rec.PetGrowth[a].Job = keptJob -- B's save is in the store again
					T.check(C.MutateGrowth(tp, function(g)
						g[a].Job = { Stat = "Defense", Ends = t0 + 4000, Rank = 3, Slot = 1, From = "Follow", Paid = 2700 }
					end) == true and C.Save(tp) == true, "p4 two servers: server C starts its own Defense 2 -> 3 job (the player paid twice on two servers) and saves")
					st = (stored(TWO) or {}).PetGrowth or {}
					T.check(type(st[a]) == "table" and st[a].Defense == 2 and type(st[a].Job) == "table" and st[a].Job.Rank == 3 and st[a].Job.Ends == t0 + 4000 and st[a].Job.Slot == 1,
						"p4 two servers: a job at the SAME target replaces the stored one (the session's value; the same job, not a newer one): one rank-3 job, never two ranks", growthText(st[a]))
					T.check(C.MutateGrowth(tp, function(g)
						g[a].Defense = 3
						g[a].Job = nil
					end) == true and C.Save(tp) == true, "p4 two servers: server C completes rank 3")
					T.check(B.MutateGrowth(tp, function(g)
						g[a].Defense = 3
						g[a].Job = nil
					end) == true and B.Save(tp) == true, "p4 two servers: server B completes its copy of the same job")
					st = (stored(TWO) or {}).PetGrowth or {}
					T.check(type(st[a]) == "table" and st[a].Defense == 3 and st[a].Job == nil, "p4 two servers: Defense 3 exactly once, no job left (two servers, two completions, one rank)", growthText(st[a]))
					DataS.AddTokens(tp, 1)
					DataS.Save(tp)
					advance(0.3)
					T.check(DataS.GetGrowth(tp, a).Defense == 3 and DataS.GetGrowth(tp, a).Job == nil, "p4 two servers: ...server A agrees after its save")
				end)
				if not okC then
					T.fail("p4 two servers (server C): scenario errored", tostring(errC))
				end
				T.check(releaseC() == true, "p4 two servers: server C's hooks are dropped with it (no leaked connections)")
			end
			-- the ring on two servers: Best max, Runs delta
			T.check(DataS.MutateRing(tp, function(ring)
				ring.Best, ring.Runs = 9, 1
			end) == true and B.MutateRing(tp, function(ring)
				ring.Best, ring.Runs = 6, 2
			end) == true and DataS.Save(tp) == true and B.Save(tp) == true, "p4 two servers: both servers finish ring runs")
			local sring = (stored(TWO) or {}).Ring or {}
			T.check(sring.Best == 9 and sring.Runs == 3, "p4 two servers: Ring.Best is the higher (9), Runs the sum of both deltas (1 + 2)", tostring(sring.Best) .. "/" .. tostring(sring.Runs))
			K.removePlayers({ tp })
			advance(3)
		end)
		if not okB then
			T.fail("p4 two servers: scenario errored", tostring(errB))
		end
		T.check(releaseB() == true, "p4 two servers: server B's leave-save / resync hooks are dropped with it (no leaked connections)")
	end
	K.flushErrors("p4data_save")
	K.flushWarnings("p4data_save", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the one-time Phase 4 migration
----------------------------------------------------------------------------------------------------
S.p4data_migrate = guarded("p4data_migrate", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	if type(DataS.MigratedNow) ~= "function" or type(DataS.Migrated) ~= "table" then
		T.fail("p4 migrate: DataService has no MigratedNow / Migrated")
		return
	end
	local DSt = Mock.DataStore
	local data = DSt.Data
	local ids = petIds(8)
	local a, b, c, d, e, f, g, h = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7], ids[8]
	local function veteran(userId, home, extra)
		local rec = {
			Version = 2, Tokens = 50, Pets = { [a] = 1, [b] = 1, [c] = 1, [d] = 1, [e] = 1, [f] = 1, [g] = 1, [h] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(),
			Discovered = {}, IndexClaimed = {}, Tutorial = { Step = 15, Done = false, Gifted = true }, Cash = 5000, Gems = 20, Home = home,
			PetLevels = { [g] = { Level = 25, Xp = 10 } }, Food = { Feast = 3 },
		}
		for k, v in pairs(extra or {}) do
			rec[k] = v
		end
		data[storeKey(userId)] = rec
		return rec
	end
	local function bigHome()
		return {
			Level = 20, Prestige = 1, Stations = { Press1 = 5, Press2 = 3, Collector = 4, Garden = 6, Kitchen = 1, Gym = 2 },
			Garden = { a, b, c, d, e, f }, Gym = { g, "", h }, CollectorCash = 1234, LastSeen = 1700000000,
		}
	end
	local watch = migratedWatcher(DataS)

	-- a veteran with 6 garden places at Prestige 1 (3 + 1 by right), two gym pets, Cash on the Collector
	local VET = 954201
	veteran(VET, bigHome())
	local m0 = watch.mark()
	local mark = K.logSize()
	local v = join("P4Veteran", VET)
	local fired = watch.since(v, m0)
	T.check(#fired == 1 and fired[1].name == "P4" and type(fired[1].info) == "table", "p4 migrate: Migrated fires once with (player, 'P4', info) at the first Phase 4 load")
	local info = DataS.MigratedNow(v, "P4")
	T.check(type(info) == "table" and info.Veteran == true and info.LegacySlots == 6 and info.LegacyPrices == true and info.GymPets == 2 and sameList(info.GymKeys, { g, h }) and info.CollectorCash == 1234,
		"p4 migrate: MigratedNow(player, 'P4') = { Veteran, LegacySlots 6, LegacyPrices, GymKeys {g, h} in slot order, GymPets 2, CollectorCash 1234 }",
		info and (tostring(info.Veteran) .. "/" .. tostring(info.LegacySlots) .. "/" .. tostring(info.LegacyPrices) .. "/" .. listText(info.GymKeys) .. "/" .. tostring(info.CollectorCash)) or "nil")
	T.check(deepEqual(fired[1] and fired[1].info, info), "p4 migrate: ...the signal carries the same info")
	local home = DataS.GetHome(v)
	T.check(home.LegacySlots == 6 and home.LegacyPrices == true, "p4 migrate: 1 + 2: Home.LegacySlots = the old Garden level (6 > 3 + 1 star) and LegacyPrices = true (Prestige > 0)")
	T.check(count(home.Gym) == 0, "p4 migrate: 3: the old Gym is emptied (those pets are free again)")
	T.check(DataS.IsMigrated(v, "P4") == true, "p4 migrate: 4: Migrations.P4 = true")
	T.check(DataS.IsMigrated(v, "P4Veteran") == true and DataS.IsMigrated(v, "P4Welcome") == false,
		"p4 migrate: ...and Migrations.P4Veteran (persisted: the welcome toast is owed on the first claim, in any session); P4Welcome is TycoonService's to set")
	-- (Phase 5: the same load also runs the one-time P5Home fold, ARCHITECTURE_V3.md "Phase 5 build contract" 9.2 step 3:
	-- Press1 5 + Press2 3 = 8, raised to the Berry Farm food floor (old plant food 21 + 32 = 53 -> FARM_FOOD[9] = 54) =
	-- Press1 9; the Coin Magnet 4 -> LegacyMagnet 4 at star 1. Every station the Phase 4 migration knows is unchanged
	-- and the Home Level never drops: 9 + 6 + 1 + 2 + LegacyMagnet 4 = 22 >= the old 21)
	local TCat = K.M["shared/TycoonCatalog"]
	local oldLevels = 5 + 3 + 4 + 6 + 1 + 2
	local liveLevel = TCat and type(TCat.HomeLevelOf) == "function" and TCat.HomeLevelOf(home) or -1
	T.check(home.Level == 20 and home.Prestige == 1 and home.Stations.Press1 == 9 and home.Stations.Press2 == nil and home.Stations.Collector == nil and home.LegacyMagnet == 4 and home.LegacyMagnetStar == 1
		and home.Stations.Garden == 6 and home.Stations.Kitchen == 1 and home.Stations.Gym == 2 and count(home.Stations) == 4 and liveLevel >= oldLevels
		and sameList({ home.Garden[1], home.Garden[2], home.Garden[3], home.Garden[4], home.Garden[5], home.Garden[6] }, { a, b, c, d, e, f }) and home.CollectorCash == 1234 and home.LastSeen == 1700000000,
		"p4 migrate: nothing else changes: Home Level, Prestige, every station level (Garden 6, Gym 2 included), the 6 garden pets, CollectorCash, LastSeen (the Phase 5 fold: Press1 5 + Press2 3 -> Berry Farm 9, Collector 4 -> LegacyMagnet 4, HomeLevelOf never lower)",
		"Press1 " .. tostring(home.Stations.Press1) .. " LegacyMagnet " .. tostring(home.LegacyMagnet) .. "/" .. tostring(home.LegacyMagnetStar) .. " stations " .. count(home.Stations) .. " HomeLevelOf " .. tostring(liveLevel))
	-- (Phase 5: the leftover food is converted once by P5Home into berries: Feast 3 x LegacyFood.Feast 6400, Food zeroed)
	local legacyFeast = TCat and type(TCat.Berries) == "table" and type(TCat.Berries.LegacyFood) == "table" and TCat.Berries.LegacyFood.Feast or 6400
	T.check(DataS.GetCash(v) == 5000 and DataS.GetGems(v) == 20 and DataS.GetTokens(v) == 50 and (DataS.GetPetLevel(v, g)) == 25 and DataS.GetFood(v, "Feast") == 0
		and legacyFeast == 6400 and DataS.GetBerries(v) == 3 * legacyFeast,
		"p4 migrate: no one-time payout: Cash, Gems, Tokens, the gym pet's level are as stored; the leftover food (Feast 3) is converted exactly into 3 x 6400 berries by P5Home",
		tostring(DataS.GetFood(v, "Feast")) .. " Feast / " .. tostring(DataS.GetBerries(v)) .. " berries")
	-- bug batch 2 #18: the freed gym pets can join a team; the 6 garden pets are busy gardening (not fieldable)
	local fieldV = {}
	for _, key in ipairs(DataS.FieldableKeys(v)) do
		fieldV[key] = true
	end
	T.check(count(fieldV) == 2 and fieldV[g] and fieldV[h] and DataS.SetTeam(v, 1, { g, h }) == true and DataS.SetTeam(v, 2, { a }) == false,
		"p4 migrate: the freed gym pets can join a team; the garden pets are busy gardening (bug batch 2 #18)", listText(DataS.FieldableKeys(v)))
	local snap = lastSnapshot(v, mark)
	T.check(type(snap) == "table" and type(snap.Home) == "table" and snap.Home.LegacySlots == 6 and snap.Home.LegacyPrices == true and type(snap.Home.Gym) == "table" and #snap.Home.Gym == 0,
		"p4 migrate: the first ProfileSync already shows LegacySlots / LegacyPrices and the empty Gym")
	K.removePlayers({ v })
	advance(2)
	local sv = stored(VET) or {}
	local svh = type(sv.Home) == "table" and sv.Home or {}
	T.check(type(sv.Migrations) == "table" and sv.Migrations.P4 == true and sv.Migrations.P4Veteran == true and svh.LegacySlots == 6 and svh.LegacyPrices == true and type(svh.Gym) == "table" and #svh.Gym == 0 and svh.Level == 20
		and svh.Stations.Garden == 6 and type(svh.Garden) == "table" and #svh.Garden == 6 and svh.CollectorCash == 1234,
		"p4 migrate: the save holds the marker, LegacySlots / LegacyPrices, an empty Gym and everything else unchanged")
	-- idempotent: a second load changes nothing and fires nothing; a Gym pet put back stays (the migration never runs again)
	local m1 = watch.mark()
	local v2 = join("P4Veteran", VET)
	T.check(#watch.since(v2, m1) == 0 and DataS.MigratedNow(v2, "P4") == nil and DataS.IsMigrated(v2, "P4") == true and DataS.GetHome(v2).LegacySlots == 6,
		"p4 migrate: a second load migrates nothing (no signal, MigratedNow nil, the extras as stored)")
	DataS.MutateHome(v2, function(h2)
		h2.Gym[1] = g
	end)
	DataS.AddTokens(v2, 1)
	DataS.Save(v2)
	advance(0.5)
	T.check(DataS.GetHome(v2).Gym[1] == g and ((stored(VET) or {}).Home.Gym or {})[1] == g, "p4 migrate: ...a Gym slot written afterwards is kept by the data layer (PetCareService empties it on its home load)")
	K.removePlayers({ v2 })
	advance(2)

	-- the small cases
	local SMALL = 954202
	veteran(SMALL, { Level = 4, Prestige = 0, Stations = { Press1 = 1, Garden = 3 }, Garden = { a, b, c }, Gym = {}, CollectorCash = 0, LastSeen = 0 })
	local s = join("P4SmallVet", SMALL)
	info = DataS.MigratedNow(s, "P4")
	T.check(type(info) == "table" and info.Veteran == true and info.LegacySlots == nil and info.LegacyPrices == false and info.GymPets == 0
		and DataS.GetHome(s).LegacySlots == nil and DataS.GetHome(s).LegacyPrices == nil and DataS.IsMigrated(s, "P4") == true,
		"p4 migrate: a Garden at the free count (3 at Prestige 0) and no prestige: a veteran without extras, still marked")
	K.removePlayers({ s })
	advance(2)
	local EDGE = 954203
	veteran(EDGE, { Level = 12, Prestige = 1, Stations = { Press1 = 8, Garden = 4 }, Garden = { a, b, c, d }, Gym = {}, CollectorCash = 0, LastSeen = 0 })
	local ed = join("P4EdgeVet", EDGE)
	info = DataS.MigratedNow(ed, "P4")
	T.check(type(info) == "table" and info.LegacySlots == nil and info.LegacyPrices == true and DataS.GetHome(ed).LegacySlots == nil and DataS.GetHome(ed).LegacyPrices == true,
		"p4 migrate: a Garden of 4 at Prestige 1 is exactly the new count (no LegacySlots); the prestige gives LegacyPrices")
	K.removePlayers({ ed })
	advance(2)
	local NEW = 954204
	data[storeKey(NEW)] = nil
	local m2 = watch.mark()
	local n = join("P4Newbie", NEW)
	fired = watch.since(n, m2)
	info = DataS.MigratedNow(n, "P4")
	T.check(#fired == 1 and type(info) == "table" and info.Veteran == false and info.LegacySlots == nil and info.LegacyPrices == false and info.GymPets == 0 and info.CollectorCash == 0 and DataS.IsMigrated(n, "P4") == true
		and DataS.IsMigrated(n, "P4Veteran") == false,
		"p4 migrate: a brand-new player is marked at once with Veteran = false and no P4Veteran marker (TycoonService shows no welcome toast)")
	K.removePlayers({ n })
	advance(2)

	-- provisional: the migration waits for the real save (ProfileRebased)
	local PV = 954205
	veteran(PV, bigHome())
	DSt.Fail = true
	local m3 = watch.mark()
	local pv = Mock.AddPlayer("P4OutageVet", PV)
	advance(4)
	T.check(DataS.IsProvisional(pv) == true and DataS.IsMigrated(pv, "P4") == nil and DataS.MigratedNow(pv, "P4") == nil and #watch.since(pv, m3) == 0,
		"p4 migrate: a provisional profile is not migrated (stand-in defaults; no signal)")
	DSt.Fail = false
	local recovered = K.waitFor(function()
		return not DataS.IsProvisional(pv)
	end, 40)
	T.check(recovered, "p4 migrate: (the recovery reads the real save)")
	advance(1)
	fired = watch.since(pv, m3)
	info = DataS.MigratedNow(pv, "P4")
	T.check(#fired == 1 and type(info) == "table" and info.Veteran == true and info.LegacySlots == 6 and DataS.GetHome(pv).LegacySlots == 6 and count(DataS.GetHome(pv).Gym) == 0 and DataS.IsMigrated(pv, "P4") == true,
		"p4 migrate: ...it runs on the recovery (ProfileRebased): one signal, the extras, the Gym emptied, the marker")
	K.removePlayers({ pv })
	advance(3)

	-- two servers migrate the same save: one result
	local B, cloneB, releaseB = secondServer("DataServiceP4MigrateB")
	if T.check(B ~= nil, "p4 migrate: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		local TWO = 954206
		veteran(TWO, bigHome())
		local okB, errB = pcall(function()
			local m4 = watch.mark()
			local tp = join("P4TwoMigrate", TWO)
			B.Load(tp) -- B reads the store before A saved: it migrates too
			local infoA, infoB = DataS.MigratedNow(tp, "P4"), B.MigratedNow(tp, "P4")
			T.check(type(infoA) == "table" and type(infoB) == "table" and infoA.LegacySlots == 6 and infoB.LegacySlots == 6 and infoB.GymPets == 2,
				"p4 two servers: both servers ran the migration on the same old save")
			T.check(DataS.Save(tp) == true and B.Save(tp) == true, "p4 two servers: both save")
			local st = stored(TWO) or {}
			local sth = type(st.Home) == "table" and st.Home or {}
			T.check(sth.LegacySlots == 6 and sth.LegacyPrices == true and type(sth.Gym) == "table" and #sth.Gym == 0 and sth.Level == 20 and sth.Prestige == 1 and sth.Stations.Garden == 6 and sth.Stations.Gym == 2
				and #sth.Garden == 6 and sth.CollectorCash == 1234 and st.Migrations.P4 == true and st.Cash == 5000,
				"p4 two servers: the merged save is the same as one migration (LegacySlots 6 once, Gym empty, Home Level 20, Cash 5000, the marker)")
			DataS.AddTokens(tp, 1)
			DataS.Save(tp)
			advance(0.3)
			T.check(DataS.GetHome(tp).LegacySlots == 6 and count(DataS.GetHome(tp).Gym) == 0 and DataS.GetHome(tp).Level == 20 and #watch.since(tp, m4) == 1,
				"p4 two servers: server A's live Home agrees after adopting the store; its signal fired once")
			K.removePlayers({ tp })
			advance(3)
		end)
		if not okB then
			T.fail("p4 two servers (migration): scenario errored", tostring(errB))
		end
		T.check(releaseB() == true, "p4 two servers (migration): server B's hooks are dropped with it (no leaked connections)")
	end

	-- the next prestige ends the extras; a Phase 3 prestige on the store keeps them (foreign keys) until a Phase 4 one
	local PR = 954207
	veteran(PR, bigHome())
	local pr = join("P4PrestigeVet", PR)
	T.check(DataS.GetHome(pr).LegacySlots == 6 and DataS.GetHome(pr).LegacyPrices == true, "p4 migrate: (precondition) a migrated veteran with both extras")
	T.check(DataS.MutateHome(pr, function(h3)
		h3.Prestige = h3.Prestige + 1
		for key in pairs(h3.Stations) do
			h3.Stations[key] = nil
		end
		h3.Level = 0
		h3.CollectorCash = 0
	end) == true, "p4 migrate: (precondition) the home prestiges (MutateHome)")
	home = DataS.GetHome(pr)
	T.check(home.Prestige == 2 and home.LegacySlots == nil and home.LegacyPrices == nil, "p4 migrate: the next Prestige clears LegacySlots and LegacyPrices (MutateHome does it whenever Prestige rises)")
	DataS.Save(pr)
	local sph = (stored(PR) or {}).Home or {}
	T.check(sph.Prestige == 2 and sph.LegacySlots == nil and sph.LegacyPrices == nil, "p4 migrate: ...and the save agrees")
	-- a Phase 3 server prestiges the stored home during the rollout: keepForeign keeps the extras there; a higher
	-- stored Prestige wins the whole Home, so they come back to this session until its own next Prestige
	local other = data[storeKey(PR)]
	other.Home = { Level = 0, Prestige = 3, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0, LastSeen = 0, LegacySlots = 6, LegacyPrices = true }
	DataS.AddTokens(pr, 1)
	DataS.Save(pr)
	advance(0.3)
	home = DataS.GetHome(pr)
	T.check(home.Prestige == 3 and home.LegacySlots == 6 and home.LegacyPrices == true, "p4 migrate: a Phase 3 prestige on the store keeps the extras as foreign keys (the whole Home wins); harmless until the next Phase 4 prestige")
	K.removePlayers({ pr })
	advance(2)
	watch.stop()
	K.flushErrors("p4data_migrate")
	K.flushWarnings("p4data_migrate", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the developer reset and /petlevel
----------------------------------------------------------------------------------------------------
S.p4data_dev = guarded("p4data_dev", function()
	if not K.needBoot() then
		return
	end
	local DataS, PS = mod("DataService"), mod("PetService")
	local Config = config()
	local DSt = Mock.DataStore
	local data = DSt.Data
	local devModule = K.moduleInstance("server/Services/DevService")
	local Dev = devModule and require(devModule)
	if not T.check(Dev and type(Dev.Run) == "function" and type(Dev.Commands) == "table", "p4 dev: DevService loads (Run, Commands)") then
		return
	end
	local listed = false
	for _, name in ipairs(Dev.Commands) do
		listed = listed or name == "petlevel"
	end
	T.check(listed, "p4 dev: DevService.Commands lists 'petlevel'")
	local src = devModule.Source or ""
	local handlers = string.match(src, "local HANDLERS = (%b{})") or ""
	T.check(string.find(handlers, "\n%s*petlevel%s*=%s*cmd") ~= nil, "p4 dev: 'petlevel' has a handler")
	local fnStart = string.find(src, "local function makeChatCommands", 1, true)
	local fnEnd = fnStart and string.find(src, "\nend\n", fnStart, true)
	local body = fnStart and string.sub(src, fnStart, fnEnd or #src) or ""
	T.check(string.find(body, "for _, name in ipairs(DevService.Commands) do", 1, true) ~= nil and string.find(body, 'Instance.new("TextChatCommand")', 1, true) ~= nil,
		"p4 dev: every DevService.Commands name (petlevel among them) gets a TextChatCommand")
	local ids = petIds(3)
	local a, b, c = ids[1], ids[2], ids[3]
	local TC = K.M["shared/TycoonCatalog"]
	local cap = TC and (type(TC.PetXp) == "table" and TC.PetXp.MaxLevel or TC.MaxPetLevel) or 100

	local OWNER = 954301
	data[storeKey(OWNER)] = {
		Version = 2, Tokens = 100, Pets = { [a] = 1, [b] = 1, [c] = 1 }, Equipped = {}, Items = {}, Stats = statsOf(),
		Home = { Level = 10, Prestige = 1, Stations = { Press1 = 5, Garden = 5 }, Garden = { a }, Gym = {}, CollectorCash = 0, LastSeen = 0 },
		PetGrowth = { [a] = { Evo = 1, Speed = 4, Job = { Stat = "Speed", Ends = now() + 600, Rank = 5, Slot = 1, From = "Follow", Paid = 7500 } }, [b] = { Defense = 2 } },
		Ring = { Best = 14, Runs = 6 }, Migrations = { P4 = true },
	}
	local Care, Tycoon = mod("PetCareService"), mod("TycoonService")
	local saved = { Studio = Mock.Options.Studio, CreatorId = game.CreatorId, CreatorType = game.CreatorType, Enabled = Config.Dev.Enabled, Admins = Config.Dev.Admins }
	local stubs = { sessions = 0, coins = 0, sessionsOld = Care and rawget(Care, "ClearSessions"), coinsOld = Tycoon and rawget(Tycoon, "ClearCoins") }
	local joined = {}
	local okRun, errRun = pcall(function()
		Mock.Options.Studio = false
		game.CreatorType = Enum.CreatorType.User
		game.CreatorId = OWNER
		Config.Dev.Enabled = true
		-- the wave-2 hooks, stood in for when they are not there yet (DevService calls them when they exist)
		if Care and stubs.sessionsOld == nil then
			Care.ClearSessions = function(player)
				if player.UserId == OWNER then
					stubs.sessions = stubs.sessions + 1
				end
			end
		end
		if Tycoon and stubs.coinsOld == nil then
			Tycoon.ClearCoins = function(player)
				if player.UserId == OWNER then
					stubs.coins = stubs.coins + 1
				end
			end
		end
		local owner = Mock.AddPlayer("P4DevOwner", OWNER)
		joined[#joined + 1] = owner
		advance(1.5)
		T.check(DataS.GetGrowth(owner, a).Evo == 1 and DataS.TrainingKeys(owner)[a] == true and DataS.GetRing(owner).Best == 14 and DataS.IsMigrated(owner, "P4") == true,
			"p4 dev: (precondition) the owner's save has growth, a running job, a ring record and the P4 marker")
		local function run(command, arg)
			advance(0.6)
			return Dev.Run(owner, command, arg, "smoke")
		end
		local function chat(text)
			advance(0.6)
			local mark = K.logSize()
			Mock.FireSignal(owner, "Chatted", text)
			advance(0.2)
			return mark
		end
		local function lastToast(mark)
			local list = K.remotesFor("Notify", OWNER, mark)
			for i = #list, 1, -1 do
				local text = tostring(list[i].args[1])
				if text:sub(1, 4) == "DEV:" then
					return { text = text, kind = list[i].args[2], duration = list[i].args[3] }
				end
			end
			return { text = "(no DEV toast)" }
		end

		-- /reset
		T.eq((run("reset")), true, "p4 dev: /reset runs for the owner in the live game")
		local prof = DataS.GetProfile(owner)
		T.check(count(prof.PetGrowth) == 0 and count(DataS.GetGrowthMap(owner)) == 0 and count(DataS.TrainingKeys(owner)) == 0, "p4 dev: /reset wipes PetGrowth (stages, ranks, the running job)")
		T.check(prof.Ring.Best == 0 and prof.Ring.Runs == 0 and DataS.GetRing(owner).Best == 0, "p4 dev: ...sets Ring to { Best 0, Runs 0 }")
		T.check(prof.Migrations.P4 == true and DataS.IsMigrated(owner, "P4") == true, "p4 dev: ...and keeps Migrations (a reset player is not migrated again)")
		if Care and stubs.sessionsOld == nil then
			T.eq(stubs.sessions, 1, "p4 dev: ...calls PetCareService.ClearSessions(player) once when it exists")
		end
		if Tycoon and stubs.coinsOld == nil then
			T.eq(stubs.coins, 1, "p4 dev: ...and TycoonService.ClearCoins(player) once when it exists")
		end
		advance((Config.Tokens.AutosaveSeconds or 90) + 5)
		local st = stored(OWNER) or {}
		T.check(st.PetGrowth == nil and st.Ring == nil and type(st.Migrations) == "table" and st.Migrations.P4 == true,
			"p4 dev: after the next autosave the STORED profile has no growth and no ring record (ResetFields: they only rise in the merge) and keeps the marker")
		T.check(count(DataS.GetGrowthMap(owner)) == 0 and DataS.GetRing(owner).Best == 0, "p4 dev: ...and the live profile agrees (nothing merged back)")

		-- /petlevel
		prof.Pets[a], prof.Pets[b], prof.Pets[c] = 1, 1, 1
		DataS.MarkDirty(owner)
		advance(0.3)
		local mark = run("petlevel", 20)
		local okLevel = mark
		T.check(okLevel == false, "p4 dev: /petlevel with no pet equipped is refused")
		T.check(PS.Equip(owner, a) == true, "p4 dev: (precondition) a is equipped")
		advance(0.3)
		T.check(PS.Equip(owner, b) == true, "p4 dev: (precondition) b is equipped too")
		local okSet, msg = run("petlevel", 20)
		T.check(okSet == true and (DataS.GetPetLevel(owner, a)) == 20 and (DataS.GetPetLevel(owner, b)) == 20 and (DataS.GetPetLevel(owner, c)) == 1,
			"p4 dev: /petlevel 20 sets every EQUIPPED pet's level to 20 (XP 0); a pet not equipped is untouched", tostring(msg))
		T.check(select(2, DataS.GetPetLevel(owner, a)) == 0, "p4 dev: ...Xp is 0")
		local okCap = run("petlevel", cap)
		T.check(okCap == true and (DataS.GetPetLevel(owner, a)) == cap, "p4 dev: /petlevel " .. cap .. " (the curve's max level) works")
		local okOver = run("petlevel", cap + 1)
		T.check(okOver == false and (DataS.GetPetLevel(owner, a)) == cap, "p4 dev: /petlevel " .. (cap + 1) .. " is refused (above the cap)")
		T.check((run("petlevel", 0)) == false and (run("petlevel", 2.5)) == false and (run("petlevel", "20")) == false and (DataS.GetPetLevel(owner, a)) == cap,
			"p4 dev: /petlevel 0, 2.5 and a text are refused")
		mark = chat("/petlevel 50")
		local toast = lastToast(mark)
		T.check((DataS.GetPetLevel(owner, a)) == 50 and (DataS.GetPetLevel(owner, b)) == 50 and toast.kind == "good", "p4 dev: chat '/petlevel 50' sets both equipped pets to 50 with a good toast", toast.text)
		mark = chat("/petlevel 1")
		T.check((DataS.GetPetLevel(owner, a)) == 1 and lastToast(mark).kind == "good", "p4 dev: '/petlevel 1' goes down too (a developer tool)")
		advance(0.5)
		local syncs = K.remotesFor("ProfileSync", OWNER, mark)
		local snap = syncs[#syncs] and syncs[#syncs].args[1]
		T.check(type(snap) == "table" and type(snap.PetLevels) == "table" and snap.PetLevels[a] and snap.PetLevels[a].Level == 1, "p4 dev: ...the menu is synced (ProfileSync carries the new level)")
		mark = chat("/petlevel lots")
		toast = lastToast(mark)
		T.check((DataS.GetPetLevel(owner, a)) == 1 and toast.kind == "bad" and toast.text:find("petlevel", 1, true) ~= nil, "p4 dev: '/petlevel lots' is refused with a bad toast naming the command", toast.text)
		-- the help lists it (three toasts that fit)
		mark = chat("/devhelp")
		local help, fits = {}, true
		for _, e in ipairs(K.remotesFor("Notify", OWNER, mark)) do
			local text = tostring(e.args[1])
			if text:sub(1, 4) == "DEV:" then
				help[#help + 1] = text
				if #text > 90 then
					fits = false
				end
			end
		end
		local all = table.concat(help, " ")
		T.check(#help == 3 and fits and all:find("/petlevel", 1, true) ~= nil and all:find("/devhelp", 1, true) ~= nil and all:find("/reset", 1, true) ~= nil,
			"p4 dev: /devhelp's three toasts (<= 90 characters each) list /petlevel", all)
	end)
	K.removePlayers(joined)
	if Care and stubs.sessionsOld == nil then
		Care.ClearSessions = nil
	end
	if Tycoon and stubs.coinsOld == nil then
		Tycoon.ClearCoins = nil
	end
	Mock.Options.Studio = saved.Studio
	game.CreatorType = saved.CreatorType
	game.CreatorId = saved.CreatorId
	Config.Dev.Enabled = saved.Enabled
	Config.Dev.Admins = saved.Admins
	advance(2)
	if not okRun then
		error(errRun, 0)
	end

	-- /petlevel while provisional is refused (an admin whose load failed)
	local ADMIN = 954302
	data[storeKey(ADMIN)] = { Version = 2, Tokens = 0, Pets = { [a] = 1 }, Equipped = { a }, Items = {}, Stats = statsOf(), PetLevels = { [a] = { Level = 30, Xp = 0 } } }
	local okProv, errProv = pcall(function()
		Mock.Options.Studio = false
		Config.Dev.Enabled = true
		Config.Dev.Admins = { ADMIN }
		DSt.Fail = true
		local adm = Mock.AddPlayer("P4DevOutage", ADMIN)
		joined = { adm }
		advance(4)
		T.check(DataS.IsProvisional(adm) == true, "p4 dev: (precondition) the admin's profile is provisional")
		advance(0.6)
		local markP = K.logSize()
		local okP, msgP = Dev.Run(adm, "petlevel", 20, "smoke")
		local toastP = "(no DEV toast)"
		for _, e in ipairs(K.remotesFor("Notify", ADMIN, markP)) do
			if tostring(e.args[1]):sub(1, 4) == "DEV:" then
				toastP = tostring(e.args[1])
			end
		end
		T.check(okP == false and tostring(msgP):lower():find("provisional", 1, true) ~= nil and toastP:lower():find("still loading", 1, true) ~= nil,
			"p4 dev: /petlevel is refused while provisional (reason 'profile provisional', toast 'your data is still loading')", tostring(msgP) .. " / " .. toastP)
		DSt.Fail = false
		K.waitFor(function()
			return not DataS.IsProvisional(adm)
		end, 40)
		advance(1)
		T.eq((DataS.GetPetLevel(adm, a)), 30, "p4 dev: ...and the stored level is intact after the recovery")
	end)
	DSt.Fail = false
	K.removePlayers(joined)
	Mock.Options.Studio = saved.Studio
	Config.Dev.Enabled = saved.Enabled
	Config.Dev.Admins = saved.Admins
	advance(2)
	if not okProv then
		error(errProv, 0)
	end
	K.flushErrors("p4data_dev")
	K.flushWarnings("p4data_dev", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- scenario: the rollout with a Phase 3 server (the frozen fixture) saving a Phase 4 profile
----------------------------------------------------------------------------------------------------
S.p4data_rollout = guarded("p4data_rollout", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local DSt = Mock.DataStore
	local data = DSt.Data
	local src = nil
	for _, candidate in ipairs({ "tools/fixtures/DataService_phase3.lua", "fixtures/DataService_phase3.lua", "../tools/fixtures/DataService_phase3.lua", "nimbus-climb/tools/fixtures/DataService_phase3.lua" }) do
		local fh = io.open(candidate, "r")
		if fh then
			src = fh:read("*a")
			fh:close()
			break
		end
	end
	if not T.check(src ~= nil and #src > 1000, "p4 rollout: tools/fixtures/DataService_phase3.lua (the frozen Phase 3 release) is found from the working directory") then
		return
	end
	-- the frozen file must not know the Phase 4 keys (otherwise it is not the Phase 3 release)
	local knownTop = string.match(src, "local KNOWN_TOP = (%b{})") or ""
	local knownHome = string.match(src, "local KNOWN_HOME = (%b{})") or ""
	T.check(knownTop ~= "" and not knownTop:find("PetGrowth", 1, true) and not knownTop:find("Ring", 1, true) and not knownTop:find("Migrations", 1, true),
		"p4 rollout: the fixture's KNOWN_TOP has no PetGrowth / Ring / Migrations (they are foreign keys to a Phase 3 server)")
	T.check(knownHome ~= "" and not knownHome:find("LegacySlots", 1, true) and not knownHome:find("LegacyPrices", 1, true), "p4 rollout: ...nor LegacySlots / LegacyPrices in its KNOWN_HOME")
	T.check(src:find("local function keepForeign", 1, true) ~= nil, "p4 rollout: ...and it has keepForeign (unknown keys are written back untouched)")
	local inst = K.moduleInstance("server/Services/DataService")
	local fixture = Instance.new("ModuleScript")
	fixture.Name = "DataServicePhase3Fixture"
	-- HUD cleanup: the frozen release read Config.Items.MaxCarry (5), which this build's Config no longer has (that
	-- server shipped its own Config): the copy loaded here reads the old value instead (the file stays untouched)
	fixture.Source = (string.gsub(src, "Config%.Items%.MaxCarry", "5"))
	fixture.Parent = inst.Parent
	local marks = connectionMarks() -- the fixture hooks PlayerRemoving / RequestProfile on its first Load: dropped below
	local okReq, P3DS = pcall(require, fixture)
	if not T.check(okReq and type(P3DS) == "table" and type(P3DS.Load) == "function", "p4 rollout: the fixture loads as a second module (a 'Phase 3 server')", tostring(P3DS)) then
		fixture:Destroy()
		dropHooks(marks)
		return
	end
	local ids = petIds(6)
	local a, b, c, d, e, f = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]
	local t0 = now()
	local ROLL = 954401
	local growth = {
		[a] = { Evo = 1, Speed = 3, Job = { Stat = "Speed", Ends = t0 + 600, Rank = 4, Slot = 1, From = "Follow", Paid = 4800 } },
		[b] = { Evo = 2, Speed = 10, Physique = 10, Ability = 10, Defense = 10 },
	}
	local function copyGrowth()
		local out = {}
		for k, v in pairs(growth) do
			out[k] = {}
			for kk, vv in pairs(v) do
				if type(vv) == "table" then
					out[k][kk] = {}
					for j, x in pairs(vv) do
						out[k][kk][j] = x
					end
				else
					out[k][kk] = vv
				end
			end
		end
		return out
	end
	data[storeKey(ROLL)] = {
		Version = 2, Tokens = 10, Pets = { [a] = 1, [b] = 1, [c] = 1, [d] = 1, [e] = 1, [f] = 1 }, Equipped = { b }, Items = {}, Stats = statsOf(),
		Discovered = {}, IndexClaimed = {}, Tutorial = { Step = 19, Done = false, Gifted = true }, Cash = 777, Gems = 3,
		Home = {
			Level = 20, Prestige = 1, Stations = { Press1 = 5, Press2 = 3, Collector = 4, Garden = 6, Kitchen = 1, Gym = 1 },
			Garden = { a, b, c, d, e, f }, Gym = {}, CollectorCash = 500, LastSeen = 1700000000, LegacySlots = 6, LegacyPrices = true,
		},
		PetLevels = { [a] = { Level = 57, Xp = 500 }, [b] = { Level = 100, Xp = 0 } },
		Teams = { Presets = { { b, c } }, Active = 1 },
		Battle = { Trophies = 40, TrialBest = 12, TrialCleared = { true, true, true, true, true, true, true, true, true, true, true, true }, Raids = 2, RaidBestDamage = 900, PvPWins = 3, PvPLosses = 1, EventPets = {} },
		PetGrowth = copyGrowth(),
		Ring = { Best = 21, Runs = 4 },
		Migrations = { P4 = true },
	}
	local okRun, errRun = pcall(function()
		local p = join("P4Rollout", ROLL)
		T.check(DataS.GetGrowth(p, a).Job ~= nil and DataS.GetRing(p).Best == 21 and DataS.GetHome(p).LegacySlots == 6 and DataS.MigratedNow(p, "P4") == nil,
			"p4 rollout: (precondition) the Phase 4 server loads the Phase 4 profile (already migrated)")
		-- (other services may grant tokens on the join, e.g. a tutorial finish for a step past the steps this build knows:
		-- the token checks below are relative to what the Phase 4 session holds now; the Phase 3 server's base is the store)
		local tokens4 = DataS.GetTokens(p)
		-- the Phase 3 server loads the same player
		local p3prof = P3DS.Load(p)
		T.check(type(p3prof) == "table" and p3prof.PetGrowth == nil and p3prof.Ring == nil and p3prof.Migrations == nil and p3prof.Home.LegacySlots == nil,
			"p4 rollout: the Phase 3 server's live profile knows nothing of PetGrowth / Ring / Migrations / LegacySlots")
		T.check(p3prof.PetLevels[a] ~= nil and p3prof.PetLevels[a].Level == 57 and p3prof.PetLevels[b].Level == 100,
			"p4 rollout: ...it keeps a level 57 and a level 100 pet as they are (cleanPetLevel never clamps a stored level down)")
		T.check(p3prof.Home.Level == 20 and p3prof.Home.Stations.Garden == 6 and #p3prof.Equipped == 1, "p4 rollout: ...the Home Level, the Garden level and the equipped pet read the same")
		-- it plays: a token, a trophy, it equips the TRAINING pet a (Phase 3 knows no lock), it banks nothing new
		P3DS.AddTokens(p, 5)
		P3DS.AddTrophies(p, 2)
		table.insert(p3prof.Equipped, a)
		P3DS.MarkDirty(p)
		T.eq(P3DS.Save(p), true, "p4 rollout: the Phase 3 server saves")
		local st = stored(ROLL) or {}
		T.check(deepEqual(st.PetGrowth, copyGrowth()), "p4 rollout: PetGrowth comes back untouched (keepForeign)", growthText((st.PetGrowth or {})[a]))
		T.check(type(st.Ring) == "table" and st.Ring.Best == 21 and st.Ring.Runs == 4 and type(st.Migrations) == "table" and st.Migrations.P4 == true, "p4 rollout: Ring and Migrations come back untouched")
		local sh = type(st.Home) == "table" and st.Home or {}
		T.check(sh.LegacySlots == 6 and sh.LegacyPrices == true, "p4 rollout: Home.LegacySlots / LegacyPrices come back untouched (foreign Home keys)")
		T.check(sh.Level == 20 and sh.Prestige == 1 and sh.Stations.Press1 == 5 and sh.Stations.Press2 == 3 and sh.Stations.Collector == 4 and sh.Stations.Garden == 6 and sh.Stations.Kitchen == 1 and sh.Stations.Gym == 1
			and count(sh.Stations) == 6 and sh.CollectorCash == 500,
			"p4 rollout: the station levels, the Home Level, Prestige and CollectorCash are unchanged")
		T.check(type(st.PetLevels) == "table" and st.PetLevels[a].Level == 57 and st.PetLevels[a].Xp == 500 and st.PetLevels[b].Level == 100,
			"p4 rollout: a level-57 pet (above the Phase 3 cap of 50) and a level-100 pet are stored back as they are")
		T.check(st.Tokens == 15 and type(st.Battle) == "table" and st.Battle.Trophies == 42 and st.Cash == 777, "p4 rollout: ...with the Phase 3 server's own changes (tokens 10 + 5, trophies 40 + 2, Cash 777)",
			tostring(st.Tokens) .. "/" .. tostring(type(st.Battle) == "table" and st.Battle.Trophies or "no Battle") .. "/" .. tostring(st.Cash))
		T.check(type(st.Equipped) == "table" and #st.Equipped == 2, "p4 rollout: the Phase 3 server stored the training pet as equipped (it knows no lock)")
		-- the Phase 4 server reads it back (its next save adopts the store)
		DataS.AddTokens(p, 1)
		T.eq(DataS.Save(p), true, "p4 rollout: the Phase 4 server saves a token and adopts the store")
		advance(0.3)
		local ga = DataS.GetGrowth(p, a)
		T.check(ga.Evo == 1 and ga.Speed == 3 and type(ga.Job) == "table" and ga.Job.Rank == 4 and ga.Job.Paid == 4800 and DataS.GetGrowth(p, b).Evo == 2 and DataS.GetGrowth(p, b).Defense == 10,
			"p4 rollout: Phase 4 reads PetGrowth back unchanged", growthText(ga))
		T.check(DataS.GetRing(p).Best == 21 and DataS.GetRing(p).Runs == 4 and DataS.IsMigrated(p, "P4") == true and DataS.MigratedNow(p, "P4") == nil,
			"p4 rollout: ...Ring and Migrations too; the migration does not run again")
		local home = DataS.GetHome(p)
		-- (Phase 5: this server's load also ran the one-time P5Home fold on the Phase 4 home, 9.2 step 3: Press1 5 + Press2 3
		-- -> Berry Farm 9 (the food floor: 21 + 32 = 53 -> FARM_FOOD[9] 54), Collector 4 -> LegacyMagnet 4 at star 1; the
		-- Phase 3 server wrote Press2 / Collector back unchanged, so the fold's removals win the per-key merge)
		local stationText = {}
		for id, lv in pairs(home.Stations) do
			stationText[#stationText + 1] = id .. "=" .. tostring(lv)
		end
		table.sort(stationText)
		T.check(home.LegacySlots == 6 and home.LegacyPrices == true and home.Level == 20 and home.Stations.Garden == 6 and home.Stations.Kitchen == 1 and home.Stations.Gym == 1
			and home.Stations.Press1 == 9 and home.Stations.Press2 == nil and home.Stations.Collector == nil and home.LegacyMagnet == 4 and home.LegacyMagnetStar == 1 and count(home.Stations) == 4,
			"p4 rollout: ...the legacy Home keys, the Home Level and the station levels (as the Phase 5 fold left them: Berry Farm 9, LegacyMagnet 4)",
			table.concat(stationText, ",") .. " LegacyMagnet " .. tostring(home.LegacyMagnet) .. "/" .. tostring(home.LegacyMagnetStar))
		T.check(DataS.GetTokens(p) == tokens4 + 5 + 1 and (stored(ROLL) or {}).Tokens == tokens4 + 5 + 1 and (DataS.GetBattle(p) or {}).Trophies == 42,
			"p4 rollout: ...and the Phase 3 server's tokens and trophies (its +5 and this session's +1 both land once; trophies 42)",
			tostring(DataS.GetTokens(p)) .. "/" .. tostring((DataS.GetBattle(p) or {}).Trophies) .. " stored " .. tostring((stored(ROLL) or {}).Tokens) .. "/" .. tostring(((stored(ROLL) or {}).Battle or {}).Trophies) .. " session had " .. tostring(tokens4))
		local prof = DataS.GetProfile(p)
		T.check(sameList(prof.Equipped, { b }) and DataS.TrainingKeys(p)[a] == true, "p4 rollout: the training pet the Phase 3 server equipped is dropped by the Phase 4 load (the lock returns)", listText(prof.Equipped))
		T.check((DataS.GetPetLevel(p, a)) == 57 and select(2, DataS.GetPetLevel(p, a)) == 500 and (DataS.GetPetLevel(p, b)) == 100, "p4 rollout: the level-57 pet keeps its level and XP")
		-- what a Phase 3 server does with XP for a pet above its own cap (recorded for the notes): its AddPetXp reads
		-- the catalog's MaxLevel (50 on a Phase 3 server). It never lowers a stored level; at or above its cap it
		-- grants no level and ZEROES the pet's XP (the "top of the curve" rule). PetCareService.GrantXp on a Phase 3
		-- server refuses XP for a pet above its cap before that, so in practice a Phase 3 server leaves such a pet
		-- alone: at worst the few minutes of a rollout cost a level-57 pet its partial XP toward 58, never a level.
		local TC = K.M["shared/TycoonCatalog"]
		if TC and type(TC.PetXp) == "table" then
			local savedMax, savedField = TC.PetXp.MaxLevel, rawget(TC, "MaxPetLevel")
			local okCap, errCap = pcall(function()
				TC.PetXp.MaxLevel = 50
				if savedField ~= nil then
					TC.MaxPetLevel = 50
				end
				local gained = P3DS.AddPetXp(p, a, 10)
				local lv, xp = P3DS.GetPetLevel(p, a)
				T.check(gained == 0 and lv == 57 and xp == 0, "p4 rollout: a Phase 3 server (cap 50) granting XP to a level-57 pet gains no level, keeps level 57 and zeroes its XP (recorded; GrantXp refuses it earlier)", tostring(gained) .. "/" .. tostring(lv) .. "/" .. tostring(xp))
			end)
			TC.PetXp.MaxLevel = savedMax
			if savedField ~= nil then
				TC.MaxPetLevel = savedField
			end
			if not okCap then
				error(errCap, 0)
			end
			P3DS.Save(p)
			DataS.AddTokens(p, 1)
			DataS.Save(p)
			advance(0.3)
			T.check((DataS.GetPetLevel(p, a)) == 57, "p4 rollout: ...and Phase 4 still reads level 57 (a Phase 3 server never lowers a level)")
		else
			T.warn("p4 rollout: TycoonCatalog.PetXp is missing: the Phase 3 cap check was skipped")
		end
		-- the Phase 3 server puts a pet in the Gym and fills slot 8 of the Garden: the data layer keeps both
		local p3live = P3DS.GetProfile(p)
		p3live.Home.Gym[1] = c
		p3live.Home.Garden[8] = d
		P3DS.MarkDirty(p)
		P3DS.Save(p)
		DataS.AddTokens(p, 1)
		DataS.Save(p)
		-- the Gym slot is read from the record this save wrote (its rebase lets PetCareService empty the live Gym)
		local rh = (stored(ROLL) or {}).Home or {}
		local rgym = type(rh.Gym) == "table" and rh.Gym or {}
		advance(0.3)
		home = DataS.GetHome(p)
		T.check(rgym[1] == c and type(rh.Garden) == "table" and rh.Garden[8] == d and home.Garden[8] == d and home.LegacySlots == 6,
			"p4 rollout: a Phase 3 Gym placement and an 8th garden pet arrive intact (PetCareService empties the Gym on its home load; extra garden keys rest)", listText(rgym))
		K.removePlayers({ p })
		advance(3)
		local final = stored(ROLL) or {}
		T.check(type(final.PetGrowth) == "table" and final.PetGrowth[a] ~= nil and final.PetGrowth[a].Job ~= nil and final.Ring.Best == 21 and final.Home.LegacySlots == 6 and final.Migrations.P4 == true,
			"p4 rollout: after both servers saved at the leave the record still holds every Phase 4 field")
	end)
	fixture:Destroy()
	T.check(dropHooks(marks) == true, "p4 rollout: the Phase 3 module's leave-save / resync hooks are dropped with it (no leaked connections)")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p4data_rollout")
	K.flushWarnings("p4data_rollout", { "[DataService]" })
end)

return S
