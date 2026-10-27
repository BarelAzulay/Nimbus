-- smoke_bug2_garden.lua: bug batch 2, lane-garden (player report #18 "pets putted in the garden shouldnt be able to use
-- for other things (combat, follow etc)"; the player picked option B "Remote recall"). Server world only (listed in
-- server_files of tools/smoke.py, run before "shutdown"):
--   bug2garden_lock     a pet in the Garden is busy: GardenSet of an equipped pet that is in two presets takes it off
--                       the player (EquippedPets), out of both presets (TeamsChanged) with a toast that says so; the
--                       garden still earns (IncomePerSecond > 0); PetService.Equip / the EquipPet remote refuse it
--                       ("... is gardening! Take it out of the garden first"); SetTeam / CheckTeam refuse it
--                       ("gardening"); FieldableKeys leaves it out, GardenBusyKeys / PlacedCopies list it; the battle
--                       team spec without it asks for a team; copies count (2 copies, 1 in the Garden: one may follow,
--                       the second is refused, and it is NOT busy); a training key is still refused by GardenSet (a pet
--                       is never in the Garden and the Training Place at once); fix round: mid-match (InMatch) the
--                       following copy cannot go to the Garden ("Finish your match first"), a non-following pet can;
--                       the toast names only the job left ("It left your side:" / "It left your team:" / both)
--   bug2garden_recall   HomeAction "GardenRecall": { Key, To = "Equip" } takes the pet out of the Garden AND equips it in
--                       one request (toast); { Key, To = "Team", Preset, Keys } takes it out AND stores that team; every
--                       refusal leaves the pet in the Garden and changes nothing: all follow slots full, a match running
--                       (InMatch), the Key missing from Keys, an unowned key in Keys, a pet not in the Garden, junk
--                       arguments (NaN preset, preset 4, a huge Keys table, a non-table, an unknown To); a second request
--                       inside the 0.5 s cooldown is ignored (rate limit)
--   bug2garden_oldsave  a stored Phase 4 profile with pets BOTH in the Garden and equipped / in a preset: on load they
--                       stay equipped / in the team and leave the Garden (their highest place first; a pet with a spare
--                       copy and a garden-only pet stay in the Garden); Migrated fires once with ("B2GardenSolo",
--                       { Keys }) and MigratedNow answers it; the marker Migrations.B2GardenSolo is set; ONE toast names
--                       the pets; the save writes the repaired Garden; a rejoin moves nothing, fires nothing and shows no
--                       toast (never loops); a profile without an overlap gets the marker but no event / toast
--   bug2garden_fusion   (fix round) a fusion does one job at a time too: an Upgrade / Mix uses the gardening copies
--                       before the following ones, so a player whose only followers are copies of the inputs keeps
--                       them (the result takes the freed garden place); when the inputs free an equipped place AND a
--                       garden place the result follows and the garden place is left free (toast)
-- Deterministic: mock clock only, no RNG. Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance, mod, config = K.advance, K.mod, K.config

local S = {}

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

local function has(list, value)
	for _, v in ipairs(type(list) == "table" and list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function count(list, value)
	local n = 0
	for _, v in ipairs(type(list) == "table" and list or {}) do
		if v == value then
			n = n + 1
		end
	end
	return n
end

local function requireAt(key)
	local inst = K.moduleInstance(key)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

local function storeKey(userId)
	return config().Tokens.DataStoreName .. "/u_" .. userId
end

-- n Common catalog pets (no event pets)
local function petIds(n)
	local PC = K.M["shared/PetCatalog"]
	local out = {}
	for _, def in ipairs(PC.Pets) do
		if #out >= n then
			break
		end
		if type(def.Id) == "string" and def.EventOnly ~= true and def.Rarity == "Common" then
			out[#out + 1] = def.Id
		end
	end
	return out
end

local function nameOf(key)
	local def = K.M["shared/PetCatalog"].Get(key)
	return def and (def.DisplayName or def.Name) or key
end

local userSeq = 0
local function join(prefix, userId)
	userSeq = userSeq + 1
	local p = Mock.AddPlayer(prefix .. userSeq, userId or (987000 + userSeq))
	advance(1.0)
	return p
end

local function leave(p)
	if p and p.Parent then
		K.removePlayers({ p })
	end
	advance(1.0)
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

-- a loaded player whose home has the Pet Garden (3 places) and owns `keys` (one copy each unless `copies` says so)
local function gardener(prefix, keys, copies)
	local DataS = mod("DataService")
	local p = join(prefix)
	local prof = DataS.GetProfile(p)
	for _, key in ipairs(keys) do
		prof.Pets[key] = (copies and copies[key]) or 1
	end
	DataS.MarkDirty(p)
	DataS.MutateHome(p, function(home)
		home.Stations.Garden = 1
	end)
	DataS.Sync(p)
	advance(0.3)
	return p, prof
end

local function equippedAttr(p)
	return tostring(p:GetAttribute(config().Attr.EquippedPets) or "")
end

----------------------------------------------------------------------------------------------------
S.bug2garden_lock = guarded("bug2garden_lock", function()
	if not K.needBoot() then
		return
	end
	local DataS, Pets = mod("DataService"), mod("PetService")
	local Ty = requireAt("server/Services/TycoonService")
	local BS = requireAt("server/Services/BattleService")
	if not T.check(Ty and type(Ty.GardenSet) == "function" and type(DataS.PlacedCopies) == "function" and type(DataS.GardenBusyKeys) == "function"
		and type(DataS.CheckTeam) == "function" and type(Pets.CanEquip) == "function", "bug2 garden lock: the API is there (GardenSet, PlacedCopies, GardenBusyKeys, CheckTeam, CanEquip)") then
		return
	end
	local ids = petIds(5)
	local a, b, c, d, e = ids[1], ids[2], ids[3], ids[4], ids[5]
	local p, prof = gardener("GardenLock", { a, b, c, d, e }, { [e] = 2 })
	local changed = 0
	local conn = DataS.TeamsChanged:Connect(function(who)
		if who == p then
			changed = changed + 1
		end
	end)

	-- a is equipped and in two presets; b, c fill the team
	T.check(Pets.Equip(p, a) == true and DataS.SetTeam(p, 1, { a, b, c }) == true and DataS.SetTeam(p, 2, { a }) == true,
		"bug2 garden lock: (setup) a follows the player and is in teams 1 and 2")
	local income0 = Ty.IncomePerSecond(p)
	local mark = K.logSize()
	local changed0 = changed
	local ok, why = Ty.GardenSet(p, 1, a)
	advance(0.3)
	T.check(ok == true and (Ty.GetHome(p).Garden or {})[1] == a, "bug2 garden lock: GardenSet puts the equipped pet in the Garden", tostring(why))
	T.check(not has(prof.Equipped, a) and not equippedAttr(p):find(a, 1, true), "bug2 garden lock: ...it stops following (Equipped and the EquippedPets attribute lose it)", listText(prof.Equipped) .. " / " .. equippedAttr(p))
	T.check(sameList(DataS.GetTeams(p).Presets[1], { b, c }) and #DataS.GetTeams(p).Presets[2] == 0 and changed > changed0,
		"bug2 garden lock: ...it leaves BOTH teams (the pets behind move up) and TeamsChanged fires", listText(DataS.GetTeams(p).Presets[1]) .. " / " .. listText(DataS.GetTeams(p).Presets[2]))
	T.check(K.notified(p, "working in your Garden! It left your side and your team", "good", mark), "bug2 garden lock: ...the toast says it left your side and your team")
	T.check(Ty.IncomePerSecond(p) > income0, "bug2 garden lock: ...and it earns in the Garden (IncomePerSecond rose)", tostring(income0) .. " -> " .. tostring(Ty.IncomePerSecond(p)))

	-- the locks
	ok, why = Pets.Equip(p, a)
	T.check(ok == false and tostring(why) == nameOf(a) .. " is gardening! Take it out of the garden first" and not has(prof.Equipped, a),
		"bug2 garden lock: PetService.Equip refuses it ('<pet> is gardening! Take it out of the garden first')", tostring(why))
	mark = K.logSize()
	Mock.FromClient(remote("EquipPet"), p, a)
	advance(0.4)
	T.check(not has(prof.Equipped, a) and K.notified(p, "is gardening", "bad", mark), "bug2 garden lock: ...the EquipPet remote too (a 'bad' toast, nothing equipped)")
	ok, why = DataS.SetTeam(p, 3, { a })
	T.check(ok == false and tostring(why):find("gardening", 1, true) ~= nil and #DataS.GetTeams(p).Presets[3] == 0, "bug2 garden lock: SetTeam refuses it ('gardening')", tostring(why))
	ok, why = DataS.CheckTeam(p, 3, { a })
	T.check(ok == false and tostring(why):find("gardening", 1, true) ~= nil, "bug2 garden lock: CheckTeam answers the same without writing", tostring(why))
	T.check(DataS.CheckTeam(p, 3, { a }, a) == true and #DataS.GetTeams(p).Presets[3] == 0, "bug2 garden lock: ...and passes once one copy counts as recalled (freeKey), still writing nothing")
	mark = K.logSize()
	Mock.FromClient(remote("BattleRequest"), p, "TeamSet", 3, { a })
	advance(0.6)
	T.check(#DataS.GetTeams(p).Presets[3] == 0, "bug2 garden lock: the TeamSet remote cannot put it in a team either")
	T.check(not has(DataS.FieldableKeys(p), a) and has(DataS.FieldableKeys(p), b), "bug2 garden lock: FieldableKeys leaves it out (the Team picker does not offer it)", listText(DataS.FieldableKeys(p)))
	T.check(DataS.GardenBusyKeys(p)[a] == true and DataS.GardenBusyKeys(p)[b] == nil and DataS.PlacedCopies(p)[a] == 1,
		"bug2 garden lock: GardenBusyKeys / PlacedCopies list it (the 'gardening' badge data)")
	if BS and type(BS.TeamSpec) == "function" then
		DataS.SelectTeam(p, 2)
		local spec, reason = BS.TeamSpec(p)
		T.check(spec == nil and tostring(reason):find("team", 1, true) ~= nil, "bug2 garden lock: a battle with only the garden pet's team asks for a team (it never fights)", tostring(reason))
		DataS.SelectTeam(p, 1)
	end

	-- copies count: e has 2 copies, one goes to the Garden: one may follow and fight, the second is refused
	ok = Ty.GardenSet(p, 2, e)
	advance(0.3)
	T.check(ok == true and Pets.Equip(p, e) == true and DataS.SetTeam(p, 2, { e }) == true and DataS.GardenBusyKeys(p)[e] == nil,
		"bug2 garden lock: a pet with a spare copy: one copy gardens, the other may follow and fight (not busy)")
	ok, why = Pets.Equip(p, e)
	T.check(ok == false and tostring(why):find("is gardening", 1, true) ~= nil and count(prof.Equipped, e) == 1,
		"bug2 garden lock: ...the copy in the Garden cannot follow too", tostring(why))
	-- placing a copy that is not needed elsewhere leaves the player alone (plain toast)
	mark = K.logSize()
	ok = Ty.GardenSet(p, 3, d)
	advance(0.3)
	T.check(ok == true and K.notified(p, "working in your Garden!", "good", mark) and not K.notified(p, "It left your side", nil, mark) and count(prof.Equipped, e) == 1,
		"bug2 garden lock: a pet that was not following / fighting gets the plain toast")
	-- training and gardening are exclusive: GardenSet refuses a training key
	if type(DataS.MutateGrowth) == "function" then
		Ty.GardenSet(p, 3, nil)
		DataS.MutateGrowth(p, function(growth)
			growth[d] = { Job = { Stat = "Physique", Ends = os.time() + 120, Rank = 1, Slot = 1, From = "Free", Paid = 300 } }
		end)
		ok, why = Ty.GardenSet(p, 3, d)
		T.check(ok == false and tostring(why):find("is training", 1, true) ~= nil and (Ty.GetHome(p).Garden or {})[3] == nil,
			"bug2 garden lock: a training pet cannot garden (never in the Garden and the Training Place at once)", tostring(why))
		DataS.MutateGrowth(p, function(growth)
			growth[d] = nil
		end)
	end
	-- taking it out frees it again
	Ty.GardenSet(p, 1, nil)
	advance(0.3)
	T.check(Pets.Equip(p, a) == true and DataS.SetTeam(p, 3, { a }) == true, "bug2 garden lock: out of the Garden it may follow and fight again")

	-- fix round: during an obby match the copy that follows cannot go to work (its perks would drop mid-run, like
	-- Unequip); a pet that does not follow still can
	p:SetAttribute(config().Attr.InMatch, true)
	ok, why = Ty.GardenSet(p, 1, a)
	advance(0.3)
	T.check(ok == false and tostring(why) == "Finish your match first" and has(prof.Equipped, a) and (Ty.GetHome(p).Garden or {})[1] == nil,
		"bug2 garden lock: mid-match, GardenSet of the following pet is refused ('Finish your match first'); it keeps following", tostring(why) .. " / " .. listText(prof.Equipped))
	ok, why = Ty.GardenSet(p, 3, d)
	advance(0.3)
	T.check(ok == true and (Ty.GetHome(p).Garden or {})[3] == d, "bug2 garden lock: ...a pet that does not follow may still go to work mid-match", tostring(why))
	Ty.GardenSet(p, 3, nil)
	p:SetAttribute(config().Attr.InMatch, false)
	advance(0.3)

	-- fix round: the toast names only the job the pet left
	T.check(Pets.Equip(p, d) == true, "bug2 garden lock: (setup) d follows, in no team")
	mark = K.logSize()
	ok = Ty.GardenSet(p, 3, d)
	advance(0.3)
	T.check(ok == true and K.notified(p, "working in your Garden! It left your side: one job at a time.", "good", mark) and not K.notified(p, "your team", nil, mark),
		"bug2 garden lock: a pet that only followed: the toast says it left your side (not your team)")
	mark = K.logSize()
	ok = Ty.GardenSet(p, 1, c)
	advance(0.3)
	T.check(ok == true and K.notified(p, "working in your Garden! It left your team: one job at a time.", "good", mark) and not K.notified(p, "your side", nil, mark),
		"bug2 garden lock: a pet that was only in a team: the toast says it left your team (not your side)")
	conn:Disconnect()
	leave(p)
end)

----------------------------------------------------------------------------------------------------
S.bug2garden_recall = guarded("bug2garden_recall", function()
	if not K.needBoot() then
		return
	end
	local DataS, Pets = mod("DataService"), mod("PetService")
	local Ty = requireAt("server/Services/TycoonService")
	if not T.check(Ty and type(Ty.GardenRecall) == "function", "bug2 garden recall: TycoonService.GardenRecall exists") then
		return
	end
	local ids = petIds(6)
	local a, b, c, d, e, f = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]
	local p, prof = gardener("GardenRecall", { a, b, c, d, e, f })
	local function garden()
		return Ty.GetHome(p).Garden or {}
	end
	local function recall(arg)
		Mock.FromClient(remote("HomeAction"), p, "GardenRecall", arg)
		advance(0.6) -- past the 0.5 s recall cooldown
	end
	Ty.GardenSet(p, 1, a)
	Ty.GardenSet(p, 2, b)
	advance(0.3)
	T.check(garden()[1] == a and garden()[2] == b, "bug2 garden recall: (setup) a and b work in the Garden")

	-- Equip: one request, out of the Garden AND following
	local mark = K.logSize()
	recall({ Key = a, To = "Equip" })
	T.check(garden()[1] == nil and has(prof.Equipped, a) and equippedAttr(p):find(a, 1, true) ~= nil,
		"bug2 garden recall: { To = 'Equip' } takes the pet out of the Garden and equips it in one request", listText(prof.Equipped))
	T.check(K.notified(p, "left the garden and follows you now", "good", mark), "bug2 garden recall: ...with a toast")

	-- Team: one request, out of the Garden AND in the team (the other keys as sent)
	mark = K.logSize()
	recall({ Key = b, To = "Team", Preset = 2, Keys = { c, b } })
	T.check(garden()[2] == nil and sameList(DataS.GetTeams(p).Presets[2], { c, b }),
		"bug2 garden recall: { To = 'Team', Preset, Keys } takes the pet out of the Garden and stores that team", listText(DataS.GetTeams(p).Presets[2]))
	T.check(K.notified(p, "left the garden and joined Team 2", "good", mark), "bug2 garden recall: ...with a toast")

	-- refusals: the pet stays in the Garden, nothing else changes
	Ty.GardenSet(p, 1, d)
	advance(0.3)
	T.check(Pets.Equip(p, e) == true and Pets.Equip(p, f) == true and #prof.Equipped == 3, "bug2 garden recall: (setup) every follow slot is taken")
	local team2 = listText(DataS.GetTeams(p).Presets[2])
	local function unchanged(label, arg, reasonText)
		local before = listText(prof.Equipped)
		local m = K.logSize()
		recall(arg)
		T.check(garden()[1] == d and listText(prof.Equipped) == before and listText(DataS.GetTeams(p).Presets[2]) == team2
			and (reasonText == nil or K.notified(p, reasonText, "bad", m)),
			"bug2 garden recall: " .. label .. ": refused, the pet stays in the Garden and nothing changes", listText(prof.Equipped) .. " / " .. tostring(garden()[1]))
	end
	unchanged("all follow slots full", { Key = d, To = "Equip" }, "slots are full")
	Pets.Unequip(p, f)
	p:SetAttribute(config().Attr.InMatch, true)
	unchanged("a match running (pets locked)", { Key = d, To = "Equip" }, "locked during a match")
	p:SetAttribute(config().Attr.InMatch, false)
	unchanged("the Key missing from the Keys", { Key = d, To = "Team", Preset = 2, Keys = { c } }, "not valid")
	unchanged("an unowned key in the Keys", { Key = d, To = "Team", Preset = 2, Keys = { d, "no_such_pet" } }, "own")
	unchanged("a pet that is not in the Garden", { Key = c, To = "Equip" }, "not in your garden")
	unchanged("a NaN preset", { Key = d, To = "Team", Preset = 0 / 0, Keys = { d } })
	unchanged("preset 4", { Key = d, To = "Team", Preset = 4, Keys = { d } })
	local huge = {}
	for i = 1, 40 do
		huge[i] = d
	end
	unchanged("a huge Keys table", { Key = d, To = "Team", Preset = 2, Keys = huge })
	unchanged("an unknown To", { Key = d, To = "Fight" })
	local before = listText(prof.Equipped)
	Mock.FromClient(remote("HomeAction"), p, "GardenRecall", "junk")
	Mock.FromClient(remote("HomeAction"), p, "GardenRecall", nil)
	advance(0.6)
	T.check(garden()[1] == d and listText(prof.Equipped) == before, "bug2 garden recall: a non-table argument is ignored")

	-- rate limit: a second request inside the cooldown is ignored
	Ty.GardenSet(p, 2, f)
	advance(0.6)
	Mock.FromClient(remote("HomeAction"), p, "GardenRecall", { Key = d, To = "Team", Preset = 3, Keys = { d } })
	Mock.FromClient(remote("HomeAction"), p, "GardenRecall", { Key = f, To = "Team", Preset = 3, Keys = { f } })
	advance(0.2)
	T.check(garden()[1] == nil and garden()[2] == f and sameList(DataS.GetTeams(p).Presets[3], { d }),
		"bug2 garden recall: two requests inside the 0.5 s cooldown: only the first runs", tostring(garden()[2]) .. " / " .. listText(DataS.GetTeams(p).Presets[3]))
	advance(0.6)
	leave(p)
end)

----------------------------------------------------------------------------------------------------
-- fix round (FusionService): one job at a time inside a fusion too
S.bug2garden_fusion = guarded("bug2garden_fusion", function()
	if not K.needBoot() then
		return
	end
	local DataS, Pets = mod("DataService"), mod("PetService")
	local Ty = requireAt("server/Services/TycoonService")
	local Fu = requireAt("server/Services/FusionService")
	local PK = requireAt("shared/PetKeys")
	if not T.check(Ty and Fu and PK and type(Fu.Upgrade) == "function" and type(Fu.Mix) == "function", "bug2 garden fusion: the API is there (FusionService.Upgrade / Mix)") then
		return
	end
	local ids = petIds(6)
	local a, b, c, d, x = ids[1], ids[2], ids[3], ids[4], ids[5]
	local function fuser(prefix, keys, copies)
		local p, prof = gardener(prefix, keys, copies)
		DataS.MutateHome(p, function(home)
			home.Prestige = 1
			home.Stations.FusionMachine = 1
		end)
		DataS.AddTokens(p, 1000000)
		advance(0.3)
		return p, prof
	end
	local function garden(p)
		return Ty.GetHome(p).Garden or {}
	end

	-- 1. Upgrade: the ONLY followers are two copies of a; two more copies garden, one is spare. The fusion must use the
	-- gardening copies (one job each), never leave the player with no follower
	local p, prof = fuser("GardenFuseA", { a }, { [a] = 5 })
	Ty.GardenSet(p, 1, a)
	Ty.GardenSet(p, 2, a)
	Pets.Equip(p, a)
	Pets.Equip(p, a)
	advance(0.3)
	T.check(count(prof.Equipped, a) == 2 and garden(p)[1] == a and garden(p)[2] == a and PK.Count(prof, a) == 5,
		"bug2 garden fusion: (setup) 5 copies: 2 follow (the only followers), 2 garden, 1 spare", listText(prof.Equipped))
	local ok, res = Fu.Upgrade(p, a)
	advance(0.5)
	local golden = PK.Make(a, "Golden")
	T.check(ok == true and count(prof.Equipped, a) == 2 and #prof.Equipped == 2 and equippedAttr(p) == a .. "," .. a,
		"bug2 garden fusion: Upgrade keeps BOTH followers (the gardening copies were used, never a following one)", tostring(res) .. " / " .. listText(prof.Equipped))
	T.check(garden(p)[1] == golden and garden(p)[2] == nil and PK.Count(prof, golden) == 1,
		"bug2 garden fusion: ...the Golden result takes the first freed garden place (it does not follow)", tostring(garden(p)[1]) .. "," .. tostring(garden(p)[2]))
	leave(p)

	-- 2. Mix: the only followers are b and c, each with its second copy in the Garden
	p, prof = fuser("GardenFuseB", { b, c }, { [b] = 2, [c] = 2 })
	Ty.GardenSet(p, 1, b)
	Ty.GardenSet(p, 2, c)
	Pets.Equip(p, b)
	Pets.Equip(p, c)
	advance(0.3)
	T.check(sameList(prof.Equipped, { b, c }) and garden(p)[1] == b and garden(p)[2] == c, "bug2 garden fusion: (setup) b and c follow, their second copies garden", listText(prof.Equipped))
	local hybrid
	ok, hybrid = Fu.Mix(p, b, c)
	advance(0.5)
	T.check(ok == true and sameList(prof.Equipped, { b, c }) and equippedAttr(p) == b .. "," .. c,
		"bug2 garden fusion: Mix keeps both followers (it used the gardening copies)", tostring(hybrid) .. " / " .. listText(prof.Equipped))
	T.check(garden(p)[1] == hybrid and garden(p)[2] == nil, "bug2 garden fusion: ...the hybrid takes the first freed garden place", tostring(garden(p)[1]) .. "," .. tostring(garden(p)[2]))
	leave(p)

	-- 3. Upgrade whose inputs free an equipped place AND a garden place: the result follows (the player keeps a
	-- follower) and does NOT also take the garden place; the toast says the place is free
	p, prof = fuser("GardenFuseC", { d, x }, { [d] = 3 })
	Ty.GardenSet(p, 1, d)
	Pets.Equip(p, d)
	Pets.Equip(p, x)
	advance(0.3)
	T.check(sameList(prof.Equipped, { d, x }) and garden(p)[1] == d, "bug2 garden fusion: (setup) d: 1 follows, 1 gardens, 1 spare; x follows too", listText(prof.Equipped))
	local mark = K.logSize()
	ok = Fu.Upgrade(p, d)
	advance(0.5)
	local goldenD = PK.Make(d, "Golden")
	T.check(ok == true and sameList(prof.Equipped, { goldenD, x }) and equippedAttr(p) == goldenD .. "," .. x,
		"bug2 garden fusion: the Golden result takes the freed equipped place and keeps following", listText(prof.Equipped) .. " / " .. equippedAttr(p))
	T.check(garden(p)[1] == nil and K.notified(p, "It follows you, so its garden place is free", "good", mark),
		"bug2 garden fusion: ...and NOT also the garden place (one job at a time); the toast says the place is free", tostring(garden(p)[1]))
	leave(p)
end)

----------------------------------------------------------------------------------------------------
S.bug2garden_oldsave = guarded("bug2garden_oldsave", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local data = Mock.DataStore.Data
	local ids = petIds(6)
	local a, b, c, d, e, x = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]
	local events = {}
	local conn = DataS.Migrated:Connect(function(who, name, info)
		events[#events + 1] = { who = who, name = name, info = info }
	end)
	local function fired(player, name)
		local out = {}
		for _, ev in ipairs(events) do
			if ev.who == player and ev.name == name then
				out[#out + 1] = ev
			end
		end
		return out
	end
	-- a (equipped) in places 1 and 3 with 2 copies, b (in team 1) in place 2, c garden-only in place 4, d: 2 copies,
	-- one equipped and one in place 5 (no overlap), e: equipped and owned once but NOT in the Garden
	local OLD = 987501
	data[storeKey(OLD)] = {
		Version = 2, Tokens = 0, Pets = { [a] = 2, [b] = 1, [c] = 1, [d] = 2, [e] = 1, [x] = 1 }, Equipped = { a, d, e }, Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		Home = { Level = 1, Prestige = 1, Stations = { Garden = 1 }, Garden = { a, b, a, c, d }, Gym = {}, CollectorCash = 0, LastSeen = 0 },
		Teams = { Presets = { { b, x }, {}, {} }, Active = 1 },
		Migrations = { P4 = true, P5Dungeon = true, P5Home = true, P5MouseLock = true },
	}
	local mark = K.logSize()
	local p = join("OldSave", OLD)
	local prof = DataS.GetProfile(p)
	local home = DataS.GetHome(p) or {}
	local g = home.Garden or {}
	T.check(sameList(prof.Equipped, { a, d, e }) and sameList(DataS.GetTeams(p).Presets[1], { b, x }),
		"bug2 garden old save: the equipped pets and the team stay as stored (no player loses a fighter)", listText(prof.Equipped) .. " / " .. listText(DataS.GetTeams(p).Presets[1]))
	T.check(g[1] == a and g[3] == nil and g[2] == nil and g[4] == c and g[5] == d,
		"bug2 garden old save: a (one equipped copy of 2) leaves its HIGHEST place only, b (in a team) leaves the Garden; the garden-only c and d's spare copy stay",
		tostring(g[1]) .. "," .. tostring(g[2]) .. "," .. tostring(g[3]) .. "," .. tostring(g[4]) .. "," .. tostring(g[5]))
	local ev = fired(p, "B2GardenSolo")
	T.check(#ev == 1 and type(ev[1].info) == "table" and sameList(ev[1].info.Keys, (a < b) and { a, b } or { b, a }),
		"bug2 garden old save: Migrated fires once with ('B2GardenSolo', { Keys = the pets that left the Garden })", ev[1] and listText(ev[1].info and ev[1].info.Keys) or "not fired")
	local now = DataS.MigratedNow(p, "B2GardenSolo")
	T.check(type(now) == "table" and #now.Keys == 2, "bug2 garden old save: ...MigratedNow answers it")
	T.check(DataS.IsMigrated(p, "B2GardenSolo") == true, "bug2 garden old save: the marker Migrations.B2GardenSolo is set")
	advance(5)
	T.check(K.notified(p, "a pet does one job at a time", "info", mark) and K.notified(p, nameOf(b), "info", mark),
		"bug2 garden old save: ONE toast explains it and names the pets")
	local toasts = 0
	for _, e2 in ipairs(K.remotesFor("Notify", p.UserId, mark)) do
		if tostring(e2.args[1]):find("one job at a time", 1, true) then
			toasts = toasts + 1
		end
	end
	T.eq(toasts, 1, "bug2 garden old save: ...exactly one")
	leave(p)
	advance(1)
	local sg = ((data[storeKey(OLD)] or {}).Home or {}).Garden or {}
	local storedGarden = {}
	for i = 1, 5 do
		storedGarden[i] = (sg[i] == nil or sg[i] == "") and "-" or sg[i]
	end
	T.check(storedGarden[1] == a and storedGarden[2] == "-" and storedGarden[3] == "-" and storedGarden[4] == c and storedGarden[5] == d,
		"bug2 garden old save: the save writes the repaired Garden", table.concat(storedGarden, ","))
	T.check(((data[storeKey(OLD)] or {}).Migrations or {}).B2GardenSolo == true, "bug2 garden old save: ...and the marker")

	-- a rejoin: nothing moves, nothing fires, no toast (never loops)
	mark = K.logSize()
	local n0 = #fired(p, "B2GardenSolo")
	local p2 = join("OldSave", OLD)
	advance(5)
	T.check(#fired(p2, "B2GardenSolo") == 0 and DataS.MigratedNow(p2, "B2GardenSolo") == nil and not K.notified(p2, "one job at a time", nil, mark) and n0 == 1,
		"bug2 garden old save: a rejoin moves nothing, fires nothing and shows no toast")
	T.check(sameList(DataS.GetProfile(p2).Equipped, { a, d, e }) and sameList(DataS.GetTeams(p2).Presets[1], { b, x }), "bug2 garden old save: ...the team and the followers are still there")
	leave(p2)

	-- a profile without an overlap: the marker, no event, no toast
	local CLEAN = 987502
	data[storeKey(CLEAN)] = {
		Version = 2, Tokens = 0, Pets = { [a] = 1, [b] = 1 }, Equipped = { a }, Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		Home = { Level = 1, Prestige = 0, Stations = { Garden = 1 }, Garden = { b }, Gym = {}, CollectorCash = 0, LastSeen = 0 },
		Migrations = { P4 = true, P5Dungeon = true, P5Home = true, P5MouseLock = true },
	}
	mark = K.logSize()
	local q = join("CleanSave", CLEAN)
	advance(5)
	T.check(DataS.IsMigrated(q, "B2GardenSolo") == true and #fired(q, "B2GardenSolo") == 0 and not K.notified(q, "one job at a time", nil, mark)
		and (DataS.GetHome(q).Garden or {})[1] == b and sameList(DataS.GetProfile(q).Equipped, { a }),
		"bug2 garden old save: a profile without an overlap gets the marker, no event and no toast; nothing moves")
	leave(q)
	conn:Disconnect()
end)

return S
