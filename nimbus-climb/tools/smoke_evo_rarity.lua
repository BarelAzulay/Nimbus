-- smoke_evo_rarity.lua: the rarity moves of evolved forms (docs/superpowers/specs/2026-11-01-evolved-forms-design.md; plan Task 3), loaded by
-- tools/smoke.py in the server world:
--   evo_rarity_stats   Candy Unicorn is a Legendary and rises by rarity alone; Magma Cub and Hydralotl are Mythic with StatRarity "Secret":
--                      their garden stats, garden coins, feed and training prices and battle stats stay exactly what they were
--   evo_rarity_odds    the hatch odds per roulette after the move; the raid drops stay in no roulette
--   evo_rarity_index   the Index groups: Epic 3, Legendary 4, Mythic 4, Secret 5; the rewards untouched
--   evo_rarity_sig     Signatures[p].Rarity follows the catalog, Unit() reads the new rarity
--   evo_rarity_ring    a Legendary Candy Unicorn champions Ring rounds 20-29; the raid drops never do
--   evo_rarity_docs    README.md says the new counts, names Candy Unicorn a Legendary, the raid drops keep "Secret-grade stats"
--   evo_rarity_saves   (booted) what a player already owns: a claimed reward stays claimed, the Secret group no longer needs the two
--                      raid pets, a stored hybrid keeps its stored rarity, a new fusion of a raid pet keeps Secret-grade stats; that
--                      fused hybrid evolves through PetCareService.Evolve and fights a Champion Ring round with Form 1 (the kind's
--                      generic name, never its body's own: hybrids get forms, the owner's answer of 2026-11-02)
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local abs = math.abs
local fmt = string.format

local S = {}
local K = _G.K

local function req(path)
	local inst = K.moduleInstance(path)
	if not inst then
		return nil
	end
	local ok, m = pcall(require, inst)
	return ok and type(m) == "table" and m or nil
end

local function shared(name)
	return req("shared/" .. name)
end

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

-- BattleService's St (the upvalue of IsInBattle; white-box, tests only: smoke_ring_noheal.lua's fixture)
local function svcState(bs)
	local f = bs and bs.IsInBattle
	if type(f) ~= "function" then
		return nil
	end
	for i = 1, 80 do
		local name, v = debug.getupvalue(f, i)
		if not name then
			break
		end
		if name == "St" and type(v) == "table" and type(v.battles) == "table" then
			return v
		end
	end
	return nil
end

-- a home for the Champion Ring's first check, then the player at its portal (smoke_ring_noheal.lua's fixtures)
local function claimHome(p)
	local Ty = req("server/Services/TycoonService")
	local SS = req("server/Services/SpotService")
	local spots = (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
	for i = 1, K.config().Lobby.SpotCount do
		if spots[i] and not (SS and SS.GetOwner(i)) then
			if Ty.Claim(p, i) then
				K.advance(0.6)
				Ty.Buy(p, "Garden")
				K.advance(0.3)
				return i
			end
		end
	end
	return nil
end

local function toRing(p)
	local AB = req("server/Services/ArenaBuilder")
	local info = AB and AB.GetInfo and AB.GetInfo()
	local portal = info and info.RingPortal
	if type(portal) == "table" then
		portal = portal.Model or portal.Pad or portal.Part
	end
	if typeof(portal) ~= "Instance" then
		portal = workspace:FindFirstChild("Portal_Ring", true)
	end
	if typeof(portal) ~= "Instance" then
		return false
	end
	local pos = portal:IsA("BasePart") and portal.Position or portal:GetPivot().Position
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 6)))
	K.advance(0.05)
	return true
end

-- "rb": Windows text mode stops at byte 0x1A
local function readFile(rel)
	for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
		local fh = io.open(prefix .. rel, "rb")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
		end
	end
	return nil
end

-- a copy of a catalog pet with other fields: the "what it was" twin of a moved pet
local function cloneDef(PC, petId, changes)
	local def = {}
	for k, v in pairs(PC.Get(petId)) do
		def[k] = v
	end
	def.Id = petId .. "_test"
	for k, v in pairs(changes) do
		def[k] = v
	end
	return def
end

-- the chance of a pet in a roulette: the sum over its rows (0 when it has none)
local function chanceOf(PC, rouletteId, petId)
	local sum = 0
	for _, row in ipairs(PC.GetOdds(rouletteId) or {}) do
		if row.PetId == petId then
			sum = sum + row.Chance
		end
	end
	return sum
end

local function idsOf(list)
	local out = {}
	for i, def in ipairs(list) do
		out[i] = def.Id
	end
	return out
end

local function groupOf(PC, id)
	for _, g in ipairs(PC.IndexGroups()) do
		if g.Id == id then
			return g
		end
	end
	return nil
end

local function has(list, id)
	for _, v in ipairs(list) do
		if v == id then
			return true
		end
	end
	return false
end

-- the numbers the commit message and the morning report quote (-v prints them)
local function report(PC, BC, TC)
	for _, id in ipairs({ "candy_unicorn", "magma_cub", "hydralotl" }) do
		local def = PC.Get(id)
		local g1, g50 = PC.GetStats(id, 1), PC.GetStats(id, 50, nil, 2)
		local b1, b50 = BC.BattleStatsOf(id, 1, nil, 0), BC.BattleStatsOf(id, 50, nil, 2)
		T.info(fmt("%s: %s; garden L1 income %.1f power %.1f health %.1f, L50 e2 income %.0f; battle L1 power %.2f health %.1f, L50 e2 power %.1f health %.0f; garden coins L1 PetPower %.2f, L50 e2 %.1f; feed L1 %s berries, train rank 1 $%s",
			id, tostring(def.Rarity), g1.Income, g1.Power, g1.Health, g50.Income, b1.Power, b1.Health, b50.Power, b50.Health,
			TC.PetPower(def, 1, "Normal", 0), TC.PetPower(def, 50, "Normal", 2), tostring(TC.FeedBerries(def, 1)), tostring(TC.TrainCost(def, 1))))
	end
	for _, rid in ipairs({ "Cloud", "Storm", "Sky", "Celestial" }) do
		T.info(fmt("%s odds: candy_unicorn %.4f, aurora_fox %.4f, ember_phoenix %.4f, cloudy_dragon %.4f",
			rid, chanceOf(PC, rid, "candy_unicorn"), chanceOf(PC, rid, "aurora_fox"), chanceOf(PC, rid, "ember_phoenix"), chanceOf(PC, rid, "cloudy_dragon")))
	end
	local sizes = {}
	for _, g in ipairs(PC.IndexGroups()) do
		sizes[#sizes + 1] = g.Id .. " " .. #g.Pets
	end
	T.info("Index groups: " .. table.concat(sizes, ", "))
end

S.evo_rarity_stats = guarded("evo_rarity_stats", function()
	local PC, BC, TC, PK = shared("PetCatalog"), shared("BattleCatalog"), shared("TycoonCatalog"), shared("PetKeys")
	if not T.check(PC and BC and TC and PK, "evo rarity: the catalogs load") then
		return
	end
	report(PC, BC, TC)
	local magma, hydra, candy = PC.Get("magma_cub"), PC.Get("hydralotl"), PC.Get("candy_unicorn")
	if not T.check(magma.Rarity == "Mythic" and magma.StatRarity == "Secret" and hydra.Rarity == "Mythic" and hydra.StatRarity == "Secret",
		"evo rarity: the raid drops are Mythic with Secret stats", tostring(magma.Rarity) .. " / " .. tostring(hydra.Rarity)) then
		return
	end
	T.check(magma.EventOnly == true and hydra.EventOnly == true, "evo rarity: ...and stay event pets")
	-- every number stays what it was at Secret: the same base stats as a Secret-rarity twin, everywhere a rarity scale is read
	T.check(near(PC.GetStats("magma_cub", 1).Power, 12 * 13, 1e-9) and near(PC.GetStats("hydralotl", 1).Income, 12 * 13, 1e-9),
		"evo rarity: the garden stats keep the Secret scale (x13), exactly as before")
	local keep = T.tally("evo rarity: a raid drop's numbers match a Secret-rarity twin to 1e-9 (GetStats, garden coins, feed, training, battle; L1, L50 e2, L100 e2)")
	for _, id in ipairs({ "magma_cub", "hydralotl" }) do
		local def, twin = PC.Get(id), cloneDef(PC, id, { Rarity = "Secret" })
		twin.StatRarity = nil
		for _, row in ipairs({ { 1, 0 }, { 50, 2 }, { 100, 2 } }) do
			local level, evo = row[1], row[2]
			local g, gt = PC.StatsOf(def, level, nil, evo), PC.StatsOf(twin, level, nil, evo)
			local b, bt = BC.BattleStatsOf(def, level, nil, evo), BC.BattleStatsOf(twin, level, nil, evo)
			keep:case(near(g.Income, gt.Income, 1e-9) and near(g.Power, gt.Power, 1e-9) and near(g.Health, gt.Health, 1e-9), id .. " garden stats at L" .. level)
			keep:case(near(b.Power, bt.Power, 1e-9) and near(b.Health, bt.Health, 1e-9), id .. " battle stats at L" .. level)
			keep:case(near(TC.PetPower(def, level, "Normal", evo), TC.PetPower(twin, level, "Normal", evo), 1e-9), id .. " garden coins at L" .. level)
		end
		keep:case(TC.FeedPrice(def, 1) == TC.FeedPrice(twin, 1), id .. " feed price " .. tostring(TC.FeedPrice(def, 1)) .. " vs " .. tostring(TC.FeedPrice(twin, 1)))
		keep:case(TC.TrainCost(def, 3) == TC.TrainCost(twin, 3), id .. " training price")
		-- by id and by key too: the service paths pass strings, not defs
		keep:case(near(TC.PetPower(id, 7, "Normal", 0), TC.PetPower(twin, 7, "Normal", 0), 1e-9), id .. " garden coins by id")
		keep:case(TC.FeedPrice(id, 2) == TC.FeedPrice(twin, 2), id .. " feed price by id")
		keep:case(near(BC.BattleStatsOf(id, 7, nil, 0).Power, BC.BattleStatsOf(twin, 7, nil, 0).Power, 1e-9), id .. " battle stats by id")
		-- a Golden copy is a shallow copy of the def: it keeps StatRarity
		local gold = PK.DefOf(id .. "@Golden")
		keep:case(gold and gold.Rarity == "Mythic" and gold.StatRarity == "Secret", id .. "@Golden keeps Mythic + StatRarity")
		keep:case(gold and near(PC.GetStats(gold, 5).Power, PC.StatsOf(twin, 5, "Golden").Power, 1e-9), id .. "@Golden's stats")
		keep:case(gold and near(TC.PetPower(gold, 5), TC.PetPower(twin, 5, "Golden"), 1e-9), id .. "@Golden's garden coins")
		keep:case(gold and near(BC.BattleStatsOf(gold, 5).Power, BC.BattleStatsOf(twin, 5, "Golden").Power, 1e-9), id .. "@Golden's battle stats")
	end
	keep:report()
	-- Candy Unicorn: base stats unchanged, the rarity scale alone lifts it
	T.check(candy.Rarity == "Legendary" and candy.StatRarity == nil, "evo rarity: Candy Unicorn is a Legendary", tostring(candy.Rarity))
	T.check(near(PC.GetStats("candy_unicorn", 1).Income, 12 * 5.5, 1e-9) and near(BC.BattleStatsOf("candy_unicorn", 1, nil, 0).Power, 4 * 2.8, 1e-9),
		"evo rarity: Candy Unicorn rises by rarity alone (garden x5.5, battle x2.8): base stats unchanged")
	T.check(candy.Stats.Income == 12 and candy.Stats.Power == 4 and candy.Stats.Health == 30 and candy.Stats.Speed == 11, "evo rarity: Candy Unicorn's base stats are the same numbers")
	local sun = PC.Get("sunbeam_bear")
	T.check(candy.Stats.Income == sun.Stats.Income and candy.Stats.Power == sun.Stats.Power and candy.Stats.Health < sun.Stats.Health and candy.Stats.Speed > sun.Stats.Speed,
		"evo rarity: next to Sunbeam Bear its Income and Power match, Health is lower, Speed higher")
	T.check(PC.Get("rime_wyrmling").Rarity == "Secret" and PC.Get("rime_wyrmling").StatRarity == nil, "evo rarity: Rime Wyrmling stays Secret")
	T.check(select(1, PC.Validate()) == true and select(1, BC.Validate()) == true, "evo rarity: both catalogs validate (the Secret perk rule groups by StatRarity)")
	-- a typo in StatRarity must not pass quietly (it would read as x1)
	local badDef = cloneDef(PC, "magma_cub", { Id = "t_badstat", Name = "Bad Stat Rarity", StatRarity = "Sekret" })
	table.insert(PC.Pets, badDef)
	PC.ById[badDef.Id] = badDef
	local okBad, problems = PC.Validate()
	table.remove(PC.Pets)
	PC.ById[badDef.Id] = nil
	T.check(okBad == false and table.concat(problems, " | "):find("StatRarity", 1, true) ~= nil, "evo rarity: Validate catches an unknown StatRarity")
	-- every pet id survives (saves are safe), the list stays sorted
	local sorted = true
	local rank = {}
	for _, r in ipairs(shared("Config").Rarities) do
		rank[r.Id] = r.Order
	end
	local at = {}
	for i, def in ipairs(PC.Pets) do
		at[def.Id] = i
		local prev = PC.Pets[i - 1]
		if prev then
			local a, b = rank[prev.Rarity], rank[def.Rarity]
			if a > b or (a == b and not prev.Signature and not def.Signature and prev.Name > def.Name) then
				sorted = false
			end
		end
	end
	T.check(sorted and PC.TotalCount() == 35, "evo rarity: PC.Pets stays sorted by rarity, then Name; 35 pets, every id kept", tostring(PC.TotalCount()))
	T.check(at.candy_unicorn < at.ember_phoenix and at.cloudy_dragon < at.hydralotl and at.hydralotl < at.magma_cub and at.magma_cub < at.starlight_unicorn and at.starlight_unicorn < at.stormfang,
		"evo rarity: Candy Unicorn before Ember Phoenix; Cloudy Dragon, Hydralotl, Magma Cub, Starlight Unicorn; then the Secrets, Stormfang first")
end)

S.evo_rarity_odds = guarded("evo_rarity_odds", function()
	local PC = shared("PetCatalog")
	if not T.check(PC ~= nil, "evo odds: PetCatalog loads") then
		return
	end
	local function chance(rid, id)
		return chanceOf(PC, rid, id)
	end
	T.check(chance("Cloud", "candy_unicorn") == 0 and near(chance("Storm", "candy_unicorn"), 0.0125) and near(chance("Sky", "candy_unicorn"), 0.0425) and near(chance("Celestial", "candy_unicorn"), 0.10),
		"evo odds: Candy Unicorn leaves Cloud; Storm 1.25%, Sky 4.25%, Celestial 10%", fmt("%.4f %.4f %.4f %.4f", chance("Cloud", "candy_unicorn"), chance("Storm", "candy_unicorn"), chance("Sky", "candy_unicorn"), chance("Celestial", "candy_unicorn")))
	T.check(near(chance("Cloud", "aurora_fox"), 0.02 / 3) and near(chance("Celestial", "ember_phoenix"), 0.40 / 4),
		"evo odds: the other Epics split their weight 3 ways (x1.33), the Legendaries 4 ways (x0.75)")
	T.check(near(chance("Sky", "cloudy_dragon"), 0.03 / 2), "evo odds: a roulette's Mythics are still Cloudy Dragon and Starlight Unicorn, each half of the weight")
	local total = T.tally("evo odds: every roulette's rows still sum to 1")
	for _, rid in ipairs({ "Cloud", "Storm", "Sky", "Celestial" }) do
		local sum = 0
		for _, row in ipairs(PC.GetOdds(rid)) do
			sum = sum + row.Chance
		end
		total:case(near(sum, 1, 1e-9), rid .. " " .. tostring(sum))
	end
	total:report()
	T.check(chance("Secret", "magma_cub") == 0 and chance("Secret", "hydralotl") == 0 and #PC.ListByRarity("Mythic") == 2 and #PC.ListByRarity("Mythic", true) == 4,
		"evo odds: the raid drops are in no roulette (EventOnly), Mythic lists them only with includeEvent")
	T.check(not PC.IsRollable("magma_cub") and not PC.IsRollable("hydralotl") and PC.IsRollable("candy_unicorn"), "evo odds: IsRollable: not the raid drops, Candy Unicorn still")
	local leak = T.tally("evo odds: PossiblePets of every roulette never lists a raid drop")
	for _, rid in ipairs({ "Cloud", "Storm", "Sky", "Celestial" }) do
		local ids = idsOf(PC.PossiblePets(rid))
		leak:case(not has(ids, "magma_cub") and not has(ids, "hydralotl"), rid)
	end
	leak:report()
end)

S.evo_rarity_index = guarded("evo_rarity_index", function()
	local PC, Config = shared("PetCatalog"), shared("Config")
	if not T.check(PC ~= nil and Config ~= nil, "evo index: the modules load") then
		return
	end
	local epic, legendary, mythic, secret = groupOf(PC, "Epic"), groupOf(PC, "Legendary"), groupOf(PC, "Mythic"), groupOf(PC, "Secret")
	T.check(#epic.Pets == 3 and #legendary.Pets == 4 and #mythic.Pets == 4 and #secret.Pets == 5, "evo index: Epic 3, Legendary 4, Mythic 4, Secret 5", fmt("%d %d %d %d", #epic.Pets, #legendary.Pets, #mythic.Pets, #secret.Pets))
	local legendaryIds, mythicIds, secretIds = idsOf(legendary.Pets), idsOf(mythic.Pets), idsOf(secret.Pets)
	T.check(has(legendaryIds, "candy_unicorn") and not has(idsOf(epic.Pets), "candy_unicorn"), "evo index: Candy Unicorn is in the Legendary group, not the Epic one")
	T.check(has(mythicIds, "magma_cub") and has(mythicIds, "hydralotl") and not has(secretIds, "magma_cub") and not has(secretIds, "hydralotl"), "evo index: the Mythic group needs both raid drops, the Secret group neither")
	T.check(has(secretIds, "rime_wyrmling"), "evo index: Rime Wyrmling still counts for the Secret group")
	T.check(mythicIds[1] == "cloudy_dragon" and mythicIds[2] == "starlight_unicorn" and mythicIds[3] == "hydralotl" and mythicIds[4] == "magma_cub", "evo index: the roulette pets first, then the raid pets", table.concat(mythicIds, ","))
	T.check(Config.Index.Rewards.Mythic.Tokens == 5000 and Config.Index.Rewards.Secret.Tokens == 10000 and mythic.Reward.Tokens == 5000 and secret.Reward.Tokens == 10000, "evo index: the rewards are untouched (Mythic 5000, Secret 10000)")
end)

S.evo_rarity_sig = guarded("evo_rarity_sig", function()
	local PC, C = shared("PetCatalog"), shared("AttackFxCatalog")
	if not T.check(PC ~= nil and C ~= nil, "evo sig: the modules load") then
		return
	end
	T.check(C.Signatures.magma_cub.Rarity == "Mythic" and C.Signatures.hydralotl.Rarity == "Mythic", "evo sig: the two raid drops' signatures say Mythic")
	local same = T.tally("evo sig: every signature's Rarity is its pet's catalog rarity")
	local n = 0
	for id, sig in pairs(C.Signatures) do
		n = n + 1
		local def = PC.Get(id)
		same:case(def ~= nil and sig.Rarity == def.Rarity, id .. ": " .. tostring(sig.Rarity) .. " vs " .. tostring(def and def.Rarity))
	end
	same:report(n .. " signatures")
	local unit = C.Unit({ petId = "magma_cub" })
	T.check(unit.Rarity == "Mythic" and C.SizeOf(unit.Rarity, 0) == 1.55 and C.BandOf(unit.Rarity) == 3, "evo sig: a Magma Cub unit draws at Mythic (Sizes 1.55, band 3)", tostring(unit.Rarity))
	T.check(C.Unit({ petId = "candy_unicorn" }).Rarity == "Legendary" and C.SizeOf("Legendary", 0) == 1.5, "evo sig: a Candy Unicorn unit draws at Legendary (Sizes 1.5, band 3)")
end)

S.evo_rarity_ring = guarded("evo_rarity_ring", function()
	local BC = shared("BattleCatalog")
	if not T.check(BC ~= nil and type(BC.ChampionTeam) == "function", "evo ring: BattleCatalog.ChampionTeam exists") then
		return
	end
	-- the curve's highest level up to each round (a champion's level is the curve, raised by at most Ring.MaxLevelRaise)
	local highest, top = {}, 0
	for r = 1, 38 do
		top = math.max(top, BC.ChampionLevel(r))
		highest[r] = top
	end
	local raise = BC.Ring.MaxLevelRaise
	local candyIn20s, raidEver, candyIn30s, levels = 0, 0, 0, true
	for seed = 1, 300 do
		for r = 20, 38 do
			local team = BC.ChampionTeam(r, seed)
			for _, pet in ipairs(team and team.Pets or {}) do
				if pet.PetId == "magma_cub" or pet.PetId == "hydralotl" then
					raidEver = raidEver + 1
				end
			end
			if team and team.Pets[1] then
				if team.Pets[1].PetId == "candy_unicorn" then
					if r <= 29 then
						candyIn20s = candyIn20s + 1
					else
						candyIn30s = candyIn30s + 1
					end
				end
				if team.Pets[1].Level < BC.ChampionLevel(r) or team.Pets[1].Level > highest[r] + raise then
					levels = false
				end
			end
		end
	end
	-- how an Economy champion sits among the band's Combat ones (the spec asks to look): -v prints it
	for r = 20, 29 do
		local n, levelSum, powerSum, otherN, otherPowerSum = 0, 0, 0, 0, 0
		for seed = 1, 300 do
			local team = BC.ChampionTeam(r, seed)
			if team.Pets[1].PetId == "candy_unicorn" then
				n, levelSum, powerSum = n + 1, levelSum + team.Pets[1].Level, powerSum + team.Power
			else
				otherN, otherPowerSum = otherN + 1, otherPowerSum + team.Power
			end
		end
		T.info(fmt("ring round %d: Candy Unicorn %d of 300 seeds, level %.1f, power %.0f (the band's other champions %.0f)", r, n, n > 0 and levelSum / n or 0, n > 0 and powerSum / n or 0, otherN > 0 and otherPowerSum / otherN or 0))
	end
	T.check(candyIn20s > 0, "evo ring: over seeds 1..300 a Candy Unicorn champions rounds 20-29", tostring(candyIn20s))
	T.check(candyIn30s == 0, "evo ring: ...never rounds 30-38", tostring(candyIn30s))
	T.check(raidEver == 0, "evo ring: no champion team of rounds 20-38 names a raid drop (EventOnly)", tostring(raidEver))
	T.check(levels, "evo ring: a Candy Unicorn champion or not, its level is the curve's, within Ring.MaxLevelRaise")
end)

S.evo_rarity_docs = guarded("evo_rarity_docs", function()
	local readme = readFile("README.md")
	if not T.check(readme ~= nil, "evo docs: README.md loads") then
		return
	end
	T.check(readme:find("Epic 3, Legendary 4, Mythic 4 and Secret 5", 1, true) ~= nil, "evo docs: the README counts Epic 3, Legendary 4, Mythic 4 and Secret 5")
	T.check(readme:find("Epic 4, Legendary 3", 1, true) == nil and readme:find("Secret 7", 1, true) == nil, "evo docs: ...and no longer the old counts")
	T.check(readme:find("Legendaries are[^\n]-Candy Unicorn") ~= nil, "evo docs: the README names Candy Unicorn among the Legendaries")
	T.check(readme:find("Secret-grade stats", 1, true) ~= nil, "evo docs: the README says the raid drops keep Secret-grade stats")
	T.check(readme:find("three Boss Raid Secrets", 1, true) == nil and readme:find("listed with the Secret pets", 1, true) == nil, "evo docs: the README no longer calls all three raid pets Secrets")
	T.check(readme:find("needs both raid", 1, true) ~= nil, "evo docs: the README says the Mythic group's reward needs both raid drops")
end)

-- what a player already owns, on a real profile (booted)
S.evo_rarity_saves = guarded("evo_rarity_saves", function()
	if not K.needBoot() then
		return
	end
	local PC, BC, TC, PK, Config = shared("PetCatalog"), shared("BattleCatalog"), shared("TycoonCatalog"), shared("PetKeys"), shared("Config")
	local DataS, IS = K.mod("DataService"), K.mod("IndexService")
	if not T.check(PC and BC and TC and PK and DataS and IS, "evo saves: the modules load") then
		return
	end
	local players = K.freshPlayers(2, "EvoRarity")
	local veteran, newcomer = players[1], players[2]
	K.advance(0.3)

	-- a veteran: both raid pets owned, every old Secret discovered, the Secret reward claimed long ago
	local prof = DataS.GetProfile(veteran)
	if not T.check(type(prof) == "table", "evo saves: the veteran's profile loaded") then
		return
	end
	prof.Pets.magma_cub = 1
	prof.Pets.hydralotl = 1
	for _, id in ipairs({ "stormfang", "eclipse_dragon", "obsidian_phoenix", "phantom_kitsune", "magma_cub", "rime_wyrmling", "hydralotl" }) do
		prof.Discovered[id] = true
	end
	prof.IndexClaimed.Secret = true
	local tokens = DataS.GetTokens(veteran)
	local progress = IS.GetProgress(veteran)
	T.check(progress.Secret.Claimed == true and progress.Secret.Complete == true and progress.Secret.Total == 5, "evo saves: a claimed Secret reward stays claimed, its group is complete (5 of 5)", fmt("%s of %s", tostring(progress.Secret.Found), tostring(progress.Secret.Total)))
	T.check(progress.Mythic.Found == 2 and progress.Mythic.Total == 4 and progress.Mythic.Claimed == false, "evo saves: ...and the two raid pets count for the Mythic group now (2 of 4)", fmt("%s of %s", tostring(progress.Mythic.Found), tostring(progress.Mythic.Total)))
	local okClaim, why = IS.Claim(veteran, "Secret")
	T.check(okClaim == false and DataS.GetTokens(veteran) == tokens, "evo saves: claiming Secret again is refused and pays nothing", tostring(why))
	T.check(PK.Count(prof, "magma_cub") == 1 and PK.Count(prof, "hydralotl") == 1, "evo saves: the veteran still owns both raid pets by the same ids")
	-- the Mythic reward: claimed before the two raid pets joined the group, it stays claimed at 2 of 4 and pays nothing again
	prof.IndexClaimed.Mythic = true
	progress = IS.GetProgress(veteran)
	local okMythic = IS.CanClaim(veteran, "Mythic")
	T.check(progress.Mythic.Claimed == true and okMythic == false, "evo saves: a Mythic reward claimed before the move stays claimed, nothing to pay again")

	-- a newcomer: the Secret reward no longer needs the two raid pets; the Mythic reward does
	prof = DataS.GetProfile(newcomer)
	for _, id in ipairs({ "stormfang", "eclipse_dragon", "obsidian_phoenix", "phantom_kitsune", "rime_wyrmling", "cloudy_dragon", "starlight_unicorn" }) do
		prof.Discovered[id] = true
	end
	T.check(IS.CanClaim(newcomer, "Secret") == true, "evo saves: the Secret reward no longer needs Magma Cub or Hydralotl")
	T.check(IS.CanClaim(newcomer, "Mythic") == false, "evo saves: the Mythic reward needs both raid drops now")

	-- hybrids: Body / Style records live in the save; StatRarity never does, it is read off the parents
	local function hybrid(rec, tag)
		local profile = { Pets = {}, Tiers = {}, Hybrids = { [tag] = rec } }
		return PK.DefOf("hyb:" .. tag, profile), rec
	end
	local function secretScaled(hdef)
		local gardenScale, battleScale = Config.PetStats.RarityScale.Secret, BC.BattleStats.RarityScale.Secret
		return near(PC.StatsOf(hdef, 1).Power, hdef.Stats.Power * gardenScale, 1e-9)
			and near(BC.BattleStatsOf(hdef, 1, nil, 0).Power, hdef.Stats.Power * battleScale, 1e-9)
			and near(TC.PetPower(hdef, 1, "Normal", 0) / TC.PetPower(PC.Get("stormfang"), 1, "Normal", 0) * (PC.RoleMultiplier(PC.Get("stormfang")) / PC.RoleMultiplier(hdef)), 1, 1e-9)
	end
	local stored, storedRec = hybrid({ Body = "magma_cub", Style = "pip_penguin", Rarity = "Secret", Tier = "Normal" }, "evo1")
	T.check(stored and stored.Rarity == "Secret" and stored.StatRarity == nil and secretScaled(stored), "evo saves: a hybrid stored as Secret keeps Rarity Secret and Secret stats")
	local fresh = hybrid({ Body = "magma_cub", Style = "pip_penguin", Tier = "Normal" }, "evo2")
	T.check(fresh and fresh.Rarity == "Mythic" and fresh.StatRarity == "Secret" and secretScaled(fresh), "evo saves: a new hybrid of magma_cub + pip_penguin (no stored Rarity) is Mythic with StatRarity Secret")
	-- FusionService stores the higher LISTED rarity on every new record: that is the case a real fusion makes
	local fused, fusedRec = hybrid({ Body = "magma_cub", Style = "pip_penguin", Rarity = "Mythic", Tier = "Normal" }, "evo3")
	T.check(fused and fused.Rarity == "Mythic" and fused.StatRarity == "Secret" and secretScaled(fused), "evo saves: a new fusion's record stores Mythic: it keeps Secret-grade stats too")
	T.check(storedRec.StatRarity == nil and fusedRec.StatRarity == nil, "evo saves: StatRarity is never written to a saved record")
	local oldCandy = hybrid({ Body = "candy_unicorn", Style = "pip_penguin", Rarity = "Epic", Tier = "Normal" }, "evo4")
	T.check(oldCandy and oldCandy.Rarity == "Epic" and oldCandy.StatRarity == nil and near(PC.StatsOf(oldCandy, 1).Income, oldCandy.Stats.Income * Config.PetStats.RarityScale.Epic, 1e-9),
		"evo saves: a hybrid stored as Epic stays Epic (a stored record's rarity is kept)")
	local newCandy = hybrid({ Body = "candy_unicorn", Style = "pip_penguin", Tier = "Normal" }, "evo5")
	T.check(newCandy and newCandy.Rarity == "Legendary" and newCandy.StatRarity == nil, "evo saves: a new Candy Unicorn hybrid is a plain Legendary")
	local plain = hybrid({ Body = "cloudy_dragon", Style = "pip_penguin", Rarity = "Mythic", Tier = "Normal" }, "evo6")
	T.check(plain and plain.Rarity == "Mythic" and plain.StatRarity == nil, "evo saves: a hybrid with no raid parent has no StatRarity")
	local withSecret = hybrid({ Body = "magma_cub", Style = "stormfang", Rarity = "Secret", Tier = "Normal" }, "evo7")
	T.check(withSecret and withSecret.Rarity == "Secret" and withSecret.StatRarity == nil, "evo saves: Magma Cub + a real Secret is simply Secret")

	-- a real Mix of a raid pet, through FusionService: what lands in the profile keeps Secret-grade stats and a clean record
	local Fusion = req("server/Services/FusionService")
	if Fusion and type(Fusion.Mix) == "function" then
		local p = veteran
		prof = DataS.GetProfile(p)
		DataS.MutateHome(p, function(h)
			h.Prestige = 1
			h.Stations.FusionMachine = 1
		end)
		PK.Add(prof, "pip_penguin", 1)
		DataS.MarkDirty(p)
		DataS.AddGems(p, TC.FusionCost("Mix", "Mythic", nil, 1).Gems)
		-- lobby shop (spec 5.2): a gem Mix waits for the settle read after the join; the veteran joined a moment ago
		if type(DataS._SettleForTest) == "function" then
			T.eq(DataS._SettleForTest(veteran), true, "evo saves: (setup) the gem settle hold ends (DataService._SettleForTest)")
		end
		local okMix, key = Fusion.Mix(p, "magma_cub", "pip_penguin")
		if T.check(okMix == true, "evo saves: Fusion.Mix of a raid pet works", tostring(key)) then
			local hdef = PK.DefOf(key, prof)
			local rec = prof.Hybrids[PK.Parse(key).HybridId]
			T.check(rec and rec.Rarity == "Mythic" and rec.StatRarity == nil and hdef.Rarity == "Mythic" and hdef.StatRarity == "Secret" and secretScaled(hdef),
				"evo saves: a real fusion of Magma Cub stores Mythic, shows Mythic and keeps Secret-grade stats", tostring(rec and rec.Rarity))
			-- (2026-11-03) hybrids evolve, so they get forms: PetCareService.Evolve stores the stage by key (DataService.SetEvolution /
			-- GetEvolution), BattleService's team spec hands it to the sim as Evo, unitInfo.special.Form reads it (BattleCatalog.FormStageOf)
			local Care, BSvc = K.mod("PetCareService"), K.mod("BattleService")
			if T.check(Care and type(Care.Evolve) == "function" and BSvc and type(BSvc.StartRing) == "function" and svcState(BSvc) ~= nil, "evo saves: PetCareService.Evolve, BattleService.StartRing and its St load") then
				prof.PetLevels[key] = { Level = 20, Xp = 0 }
				DataS.MarkDirty(p)
				local okEvo, stage = Care.Evolve(p, key)
				T.check(okEvo == true and stage == 1 and DataS.GetEvolution(p, key) == 1 and DataS.GetGrowth(p, key).Evo == 1,
					"evo saves: PetCareService.Evolve evolves the fused hybrid at level 20 (DataService stores Evo 1 by its key)", fmt("%s %s %s", tostring(okEvo), tostring(stage), tostring(DataS.GetEvolution(p, key))))
				local okTeam = DataS.SetTeam(p, 1, { key })
				local home = claimHome(p)
				local atRing = toRing(p)
				local okR, id = BSvc.StartRing(p)
				if T.check(okTeam and home ~= nil and atRing and okR == true and type(id) == "string", "evo saves: (setup) the evolved hybrid starts a Champion Ring round", tostring(id)) then
					local St = svcState(BSvc)
					local b = St.battles[id]
					local team = b and b.Sim and b.Sim.teamByOwner and b.Sim.teamByOwner[p.UserId]
					local unit = nil
					for _, u in ipairs(team and team.units or {}) do
						if u.key == key then
							unit = u
						end
					end
					local info = nil
					for _, i in ipairs(b and b.Sim and b.Sim:StaticUnits() or {}) do
						if unit and i.id == unit.id then
							info = i
						end
					end
					local kind = hdef.Special and hdef.Special.Kind
					local generic = kind and BC.Forms[kind] and BC.Forms[kind][1] and BC.Forms[kind][1].Id
					T.check(unit ~= nil and unit.evo == 1 and info ~= nil and info.evo == 1 and type(info.special) == "table" and info.special.Form == 1,
						"evo saves: the hybrid fighter's unitInfo.special.Form == 1 (its real stage, through BattleService)", info and info.special and tostring(info.special.Form))
					T.check(info and info.special and info.special.Name == generic and info.special.Name ~= BC.FormNames.magma_cub[1] and info.key == key and info.petId == key,
						"evo saves: ...named by its kind (" .. tostring(generic) .. "), never its body's own " .. tostring(BC.FormNames.magma_cub[1]) .. "; it carries its own key", info and info.special and fmt("%s / %s", tostring(info.special.Name), tostring(info.petId)))
					if BSvc.IsInBattle(p) then
						BSvc.Forfeit(p)
					end
					K.advance(5.5)
				end
			end
		end
	else
		T.fail("evo saves: FusionService.Mix is loaded")
	end
	K.removePlayers(players)
	K.advance(0.3)
end)

return S
