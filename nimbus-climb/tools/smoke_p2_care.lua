-- smoke_p2_care.lua: pet stats and level caps (ARCHITECTURE_V3.md "Phase 2: Tycoon homes" items 3-4, Phase 4 contract
-- 3.2 / 3.5 / 8.2): shared/PetCatalog.GetStats / levels and TycoonCatalog.PetPower. Loaded by tools/smoke.py in the
-- SERVER world:
--   p2care_stats      (pure) PetCatalog.GetStats(petId, level, tier) = base x RarityScale x level factor x tier for
--                     every pet, keys ("cat@Golden"), defs (tier copies, hybrids), junk levels / tiers; the Phase 4
--                     coin power (TycoonCatalog.PetPower: Economy / Combat == 1.6 at equal rarity / level / tier, the
--                     stored evolution stage x1.25 / x1.5, GetStats stays the pure level formula); LevelCap by rarity
--                     (every rarity 100, the top of the XP curve), MaxPetLevel, LevelFactor, TierMultiplier
-- The Phase 2 kitchen / feed / gym / exploits / shutdown scenarios moved to tools/smoke_p4_care.lua (Phase 4: the Food
-- Machine, EVOLVE and the Training Place).
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local abs, floor = math.abs, math.floor
local config = K.config

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
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

local function TC()
	return requireAt("shared/TycoonCatalog")
end
local function PK()
	return requireAt("shared/PetKeys")
end
local function PC()
	return requireAt("shared/PetCatalog")
end

----------------------------------------------------------------------------------------------------
-- p2care_stats (pure)
----------------------------------------------------------------------------------------------------
S.p2care_stats = guarded("p2care_stats", function()
	local Config = config()
	local PCat, Cat, Keys = PC(), TC(), PK()
	if not T.check(PCat ~= nil and type(PCat.GetStats) == "function", "care stats: PetCatalog.GetStats loads") then
		return
	end
	for _, fn in ipairs({ "LevelCap", "MaxPetLevel", "LevelFactor", "TierMultiplier", "StatsOf" }) do
		T.check(type(PCat[fn]) == "function", "care stats: PetCatalog." .. fn .. " is a function")
	end
	local top = PCat.MaxPetLevel()
	T.eq(top, Cat and Cat.MaxPetLevel or PCat.MaxLevel, "care stats: MaxPetLevel() is the top of the XP curve (TycoonCatalog.MaxPetLevel)")

	-- the formula: every pet, several levels, three tiers
	local tiers = { Normal = 1, Golden = 1.5, Rainbow = 2.5 }
	local formula = T.tally("care stats: GetStats(petId, level, tier) = base x RarityScale x (1 + 0.1 x (level - 1)) x tier (every pet; levels 1, 2, 7, top; 3 tiers)")
	for _, def in ipairs(PCat.Pets) do
		local scale = Config.PetStats.RarityScale[def.Rarity] or 1
		for _, level in ipairs({ 1, 2, 7, top }) do
			for tier, m in pairs(tiers) do
				local got = PCat.GetStats(def.Id, level, tier)
				local ok = type(got) == "table"
				for _, stat in ipairs({ "Income", "Power", "Health", "Speed" }) do
					local want = def.Stats[stat] * scale * (1 + 0.1 * (level - 1)) * m
					ok = ok and T.finite(got[stat]) and abs(got[stat] - want) <= 1e-6 * math.max(1, want)
				end
				formula:case(ok, def.Id .. " Lv " .. level .. " " .. tier)
			end
		end
	end
	formula:report()

	local def = PCat.Pets[1]
	local id = def.Id
	local function same(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for _, stat in ipairs({ "Income", "Power", "Health", "Speed" }) do
			if not near(a[stat], b[stat], 1e-9 * math.max(1, abs(b[stat] or 0))) then
				return false
			end
		end
		return true
	end
	T.check(same(PCat.GetStats(id, 3), PCat.GetStats(id, 3, "Normal")) and same(PCat.GetStats(id, 3, nil), PCat.GetStats(id, 3, "Normal")),
		"care stats: no tier = Normal (the Phase 1 two-argument form is unchanged)")
	T.check(same(PCat.GetStats(id .. "@Golden", 3), PCat.GetStats(id, 3, "Golden")) and same(PCat.GetStats(id .. "@Rainbow", 3), PCat.GetStats(id, 3, "Rainbow")),
		"care stats: a pet key carries its tier ('" .. id .. "@Golden')")
	T.check(same(PCat.GetStats(id .. "@Golden", 3, "Rainbow"), PCat.GetStats(id, 3, "Rainbow")), "care stats: an explicit tier wins over the key's")
	T.check(same(PCat.GetStats(id, top + 25), PCat.GetStats(id, top)) and same(PCat.GetStats(id, 1e9), PCat.GetStats(id, top)),
		"care stats: levels above the top of the curve count as the top (like TycoonCatalog.PetPower)")
	local junkLevels = T.tally("care stats: junk levels (0, -3, NaN, -inf, inf, 'abc', false, {}) count as level 1; 2.9 counts as 2, '5' as 5")
	for _, lv in ipairs({ 0, -3, 0 / 0, -1 / 0, 1 / 0, "abc", false }) do
		junkLevels:case(same(PCat.GetStats(id, lv), PCat.GetStats(id, 1)), tostring(lv))
	end
	junkLevels:case(same(PCat.GetStats(id, {}), PCat.GetStats(id, 1)), "table")
	junkLevels:case(same(PCat.GetStats(id, 2.9), PCat.GetStats(id, 2)), "2.9")
	junkLevels:case(same(PCat.GetStats(id, "5"), PCat.GetStats(id, 5)), "'5' (tonumber, like Phase 1)")
	junkLevels:report()
	local junkTiers = T.tally("care stats: unknown tiers count as Normal, a number is a multiplier, NaN / negative count as x1")
	junkTiers:case(same(PCat.GetStats(id, 2, "Diamond"), PCat.GetStats(id, 2)), "Diamond")
	junkTiers:case(same(PCat.GetStats(id, 2, 0 / 0), PCat.GetStats(id, 2)), "NaN")
	junkTiers:case(same(PCat.GetStats(id, 2, -2), PCat.GetStats(id, 2)), "-2")
	local x2 = PCat.GetStats(id, 2, 2)
	junkTiers:case(x2 and near(x2.Power, PCat.GetStats(id, 2).Power * 2, 1e-9), "2")
	junkTiers:report()
	local okNil1, r1 = pcall(PCat.GetStats, "ghost_pet", 3)
	local okNil2, r2 = pcall(PCat.GetStats, nil)
	local okNil3, r3 = pcall(PCat.GetStats, 42, 2, "Golden")
	local okNil4, r4 = pcall(PCat.GetStats, "hyb:h1", 2)
	T.check(okNil1 and okNil2 and okNil3 and okNil4 and r1 == nil and r2 == nil and r3 == nil and r4 == nil,
		"care stats: unknown pets, nil, numbers and hybrid keys without their profile answer nil (never raise)")

	-- defs: tier copies and hybrids (PetKeys.DefOf)
	if Keys then
		local gdef = Keys.DefOf(id .. "@Golden")
		T.check(gdef ~= nil and same(PCat.GetStats(gdef, 4), PCat.GetStats(id, 4, "Golden")) and same(PCat.StatsOf(gdef, 4), PCat.GetStats(id, 4, "Golden")),
			"care stats: a tier copy's def (PetKeys.DefOf) gets its tier (StatMultiplier) through GetStats / StatsOf")
		local other = nil
		for _, d in ipairs(PCat.Pets) do
			if d.Rarity ~= def.Rarity and d.Rarity ~= "Secret" then
				other = d
				break
			end
		end
		local profile = { Pets = {}, Tiers = {}, Hybrids = {} }
		Keys.Add(profile, "hyb:care1", 1, { Body = id, Style = other.Id, Tier = "Normal" })
		local hdef = Keys.DefOf("hyb:care1", profile)
		local hs = hdef and PCat.GetStats(hdef, 5)
		local ok = hs ~= nil
		if ok then
			local scale = Config.PetStats.RarityScale[hdef.Rarity] or 1
			for _, stat in ipairs({ "Income", "Power", "Health", "Speed" }) do
				ok = ok and near(hs[stat], hdef.Stats[stat] * scale * 1.4, 1e-6 * math.max(1, hs[stat]))
			end
		end
		T.check(ok, "care stats: a fused hybrid's def: its averaged base stats x the higher rarity's scale x level")
		T.eq(PCat.LevelCap(hdef), PCat.LevelCap(hdef.Rarity), "care stats: a hybrid's level cap is its (higher) rarity's")
	end

	-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" 3.2 / 8.2): the Garden pays coins by TycoonCatalog.PetPower, not by
	-- GetStats(...).Income: Economy pets earn RoleMult (1.6) times what Combat pets of the same rarity / level / tier earn,
	-- and the level factor / tier multiplier of GetStats carry over
	if Cat and type(Cat.PetPower) == "function" and type(PCat.RoleMultiplier) == "function" then
		local roleMult = PCat.RoleMultiplier("Economy") / PCat.RoleMultiplier("Combat")
		T.check(near(roleMult, 1.6, 1e-9) and PCat.RoleMult ~= nil and PCat.RoleMult.Economy == 1.6 and PCat.RoleMult.Combat == 1,
			"care stats: PetCatalog.RoleMult = { Economy 1.6, Combat 1 } (Economy pets make 60% more)")
		local ratio = T.tally("care stats: PetPower(Economy) / PetPower(Combat) == 1.6 at equal rarity, level and tier; PetPower follows LevelFactor x TierMultiplier")
		local byRarity = {}
		for _, d in ipairs(PCat.Pets) do
			if d.EventOnly ~= true and d.Rarity ~= "Secret" then
				byRarity[d.Rarity] = byRarity[d.Rarity] or {}
				byRarity[d.Rarity][d.Role] = byRarity[d.Rarity][d.Role] or d
			end
		end
		for rarity, pair in pairs(byRarity) do
			if pair.Economy and pair.Combat then
				for _, level in ipairs({ 1, 5, 20, top }) do
					for tier in pairs(tiers) do
						local e = Cat.PetPower(pair.Economy, level, tier)
						local c = Cat.PetPower(pair.Combat, level, tier)
						ratio:case(near(e / c, 1.6, 1e-9) and near(e, Cat.PetPower(pair.Economy, 1, "Normal") * PCat.LevelFactor(level) * PCat.TierMultiplier(tier), 1e-9 * e),
							rarity .. " Lv " .. level .. " " .. tier .. ": " .. tostring(e) .. " vs " .. tostring(c))
					end
				end
			end
		end
		ratio:report()
		local econ = nil
		for _, d in ipairs(PCat.Pets) do
			if d.Role == "Economy" and d.EventOnly ~= true then
				econ = d
				break
			end
		end
		if econ then
			-- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" 3.1): an evolution multiplies the LEVEL BONUS, not the
			-- stat: PetPower = ... x LevelFactor(level, stage), LevelFactor = 1 + 0.1 x (level - 1) x {1, 1.5, 1.875}[stage],
			-- the stage cut by MaxEvolution (Common / Uncommon / Rare evolve once). So level 1 is never boosted (nobody
			-- gets weaker) and the ratio to the unevolved pet grows with the level.
			local bonus = { [0] = 1, [1] = 1.5, [2] = 1.875 }
			local evo = T.tally("care stats: PetPower carries the STORED evolution stage (LevelFactor: level bonus x1.5 / x1.875, cut by MaxEvolution), GetStats never does without a stage")
			local seen = {}
			for _, d in ipairs(PCat.Pets) do
				local maxEvo = d.Role == "Economy" and d.EventOnly ~= true and PCat.MaxEvolution(d) or nil
				if maxEvo and not seen[maxEvo] then
					seen[maxEvo] = true
					for _, level in ipairs({ 1, 20, 50, top }) do
						local base = Cat.PetPower(d, level, "Normal", 0)
						for stage = 1, 3 do
							local cut = math.min(stage, maxEvo)
							local want = (1 + 0.1 * (level - 1) * bonus[cut]) / (1 + 0.1 * (level - 1))
							local got = Cat.PetPower(d, level, "Normal", stage) / base
							evo:case(near(got, want, 1e-9),
								d.Id .. " (max evo " .. maxEvo .. ") Lv " .. level .. " stage " .. stage .. ": x" .. tostring(got) .. " want x" .. tostring(want))
						end
					end
				end
			end
			evo:case(seen[1] == true and seen[2] == true, "economy pets of both evolution counts (1 and 2) were checked")
			evo:report()
			local s0, s1 = PCat.GetStats(econ.Id, 20), PCat.GetStats(econ.Id, 20)
			T.check(same(s0, s1) and near(PCat.GetStats(econ.Id, 20).Power, econ.Stats.Power * (Config.PetStats.RarityScale[econ.Rarity] or 1) * PCat.LevelFactor(20), 1e-9 * s0.Power),
				"care stats: GetStats at Lv 20 is the pure level formula (the evolution boost lives in PetPower / UnitStats only)")
		end
	end

	-- level caps by rarity
	local lastCap, capsOk, capText = 0, true, {}
	local rarities = {}
	for _, r in ipairs(Config.Rarities) do
		rarities[#rarities + 1] = r
	end
	table.sort(rarities, function(a, b)
		return a.Order < b.Order
	end)
	for _, r in ipairs(rarities) do
		local cap = PCat.LevelCap(r.Id)
		capText[#capText + 1] = r.Id .. " " .. tostring(cap)
		if type(cap) ~= "number" or cap < 1 or cap > top or cap ~= floor(cap) or cap < lastCap then
			capsOk = false
		else
			lastCap = cap
		end
	end
	T.check(capsOk, "care caps: every rarity has a whole level cap in 1..top that never drops with rarity", table.concat(capText, ", "))
	-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" 3.5): every rarity grows to level 100; the evolutions come at
	-- 20 (every pet) and 50 (Epic and rarer), so a Common still grows after its one evolution
	local all50 = true
	for _, r in ipairs(rarities) do
		if PCat.LevelCap(r.Id) ~= 100 or PCat.LevelCap(r.Id) ~= top then
			all50 = false
		end
	end
	T.check(all50, "care caps: every rarity grows to level 100, the top of the XP curve (" .. table.concat(capText, ", ") .. ")")
	local capForms = T.tally("care caps: LevelCap(rarity) == LevelCap(petId) == LevelCap(key) == LevelCap(def) for every pet")
	for _, d in ipairs(PCat.Pets) do
		local c = PCat.LevelCap(d.Rarity)
		capForms:case(PCat.LevelCap(d.Id) == c and PCat.LevelCap(d.Id .. "@Rainbow") == c and PCat.LevelCap(d) == c, d.Id)
	end
	capForms:report()
	T.check(PCat.LevelCap("ghost_pet") == nil and PCat.LevelCap(nil) == nil and PCat.LevelCap(5) == nil,
		"care caps: unknown pets / junk answer nil")

	-- small helpers
	T.check(PCat.LevelFactor(1) == 1 and near(PCat.LevelFactor(11), 2, 1e-9) and PCat.LevelFactor(top + 9) == PCat.LevelFactor(top) and PCat.LevelFactor(-4) == 1,
		"care stats: LevelFactor = 1 + 0.1 x (level - 1), clamped like GetStats")
	T.check(PCat.TierMultiplier("Normal") == 1 and PCat.TierMultiplier("Golden") == 1.5 and PCat.TierMultiplier("Rainbow") == 2.5
		and PCat.TierMultiplier(id .. "@Rainbow") == 2.5 and PCat.TierMultiplier(nil) == 1 and PCat.TierMultiplier("Diamond") == 1
		and PCat.TierMultiplier({ Tier = "Golden" }) == 1.5 and PCat.TierMultiplier({ Look = { Finish = "Rainbow" } }) == 2.5,
		"care stats: TierMultiplier(tier | key | def) = 1 / 1.5 / 2.5")
	local agree = true
	for tier, m in pairs(PCat.TierMultipliers) do
		if Keys and Keys.TierMultiplier[tier] ~= m then
			agree = false
		end
		if Cat and Cat.TierMultiplier[tier] ~= m then
			agree = false
		end
	end
	T.check(agree, "care stats: PetCatalog.TierMultipliers == PetKeys.TierMultiplier == TycoonCatalog.TierMultiplier")
end)

return S
