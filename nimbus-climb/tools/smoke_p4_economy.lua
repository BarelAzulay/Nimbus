-- smoke_p4_economy.lua: the tycoon catalog of Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" 3.1, 3.3-3.5, 9.2
-- and the Phase 4 contract where Phase 5 is silent; shared/TycoonCatalog.lua). The scenario keeps its Phase 2 name
-- (p2_economy) so the anchors of tools/smoke.py hold. Loaded by tools/smoke.py in the SERVER world as a pure content
-- scenario:
--   p2_economy   TycoonCatalog loads (twice = the same table, no Instances created), Version 5, the Phase 5 API and
--                data; the 11 stations of contract table 3.3 (names, kinds, caps 24 / 45 / 72 / 80, tree, prices =
--                Phase 4 x1.25 with House and decor unscaled / decor 0.4x, effects), the deletions of 3.5; a fresh home
--                shows ONE pad (the free Pet Garden) and the re-rooted tree (House needs the Farm 2, Vault Farm 6,
--                "Unlocks at Prestige 1", "Reach Home Level 10", "Needs the Villa" for Farm 11, the prestige pad only
--                with the Sky Castle); star prices; StationsAfterPrestige; HomeLevelOf with DecorCredit and the legacy
--                magnet (only while its star holds); Cloud Cash: FoodOf, PetPower = RarityScale x LevelFactor(level,
--                stage) x tier x RoleMult (L20 evo 1 = 3.85, stage cleaned), IncomePerSecond, GardenSlots, ScoopRadius /
--                PileSeconds (Garden + LegacyMagnet + Vault), OfflineEarnings, CoinValue, Coins (PoopMeals, DropsPerPet,
--                DropStages); berries (BasketCap, FeedBerries == FeedPrice); FeedXp, TrainCost, TrainSeconds; SignedPads;
--                FoldLegacy basics (the fixtures live in smoke_p5_home.lua p5home_fold); the PetCatalog mirrors; junk
--                never errors; Validate() passes and catches its rules; the layout (slots, the Kitchen / Gym swap, the
--                Farm footprint, garden beds / bowl / entrance, every pad reachable); and the parity with the constants
--                block of tools/sim_tycoon.py (every constant checked, plus the sim's formulas on 300 pseudo-random
--                homes: pads with star prices, food, slots, piles, radius, income, offline, Home Level with credits).
-- tools/sim_tycoon.py and src/shared/TycoonCatalog.lua are read from the working directory (smoke.py / run_checks.sh
-- run from the repo root). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local abs, floor, huge, min, max = math.abs, math.floor, math.huge, math.min, math.max

local S = {}

local TIER_IDS = { "Cottage", "Villa", "Manor", "SkyCastle" }
local CONTRACT_IDS = {
	"Press1", "Garden", "Kitchen", "Gym", "Vault", "House", "FusionMachine", "ArenaGate",
	"DecorFence", "DecorFountain", "DecorPodium",
}
local KINDS = { "Farm", "Garden", "FoodMachine", "Training", "Vault", "House", "Fusion", "Arena", "Decor" }
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

local FARM_PRICE = {
	15, 70, 160, 450, 520, 1400, 1500, 3100, 4400, 7500, 11000, 19000, 22000, 25000, 28000, 31000, 45000, 48000, 110000,
	120000, 150000, 160000, 200000, 220000, 320000, 340000, 360000, 380000, 460000, 510000, 610000, 790000, 850000,
	1000000, 1400000, 1500000, 1800000, 2200000, 2800000, 4000000,
}
local FARM_FOOD = {
	7, 9, 12, 15, 19, 25, 32, 41, 54, 69, 77, 90, 105, 122, 143, 166, 194, 227, 264, 309, 360, 420, 444, 483, 526, 573,
	624, 680, 740, 806, 878, 956, 1041, 1133, 1234, 1344, 1463, 1585, 1838, 2132,
}

-- ARCHITECTURE_V3.md "Phase 5 build contract" table 3.3 (Caps = Cottage, Villa, Manor, Sky Castle)
local CONTRACT = {
	Press1 = { Name = "Berry Farm", Kind = "Farm", Max = 40, Caps = { 10, 22, 37, 40 }, Req = { Garden = 1 },
		Price = FARM_PRICE, Eff = { Food = FARM_FOOD } },
	Garden = { Name = "Pet Garden", Kind = "Garden", Max = 8, Caps = { 2, 4, 6, 8 }, Req = {},
		Price = { 0, 15000, 38000, 140000, 360000, 750000, 1500000, 3000000 },
		Eff = { Lucky = { 0, 0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.15 }, Radius = { 8, 10, 12, 14, 16, 19, 22, 26 },
			PileSeconds = { 300, 330, 360, 390, 420, 480, 540, 600 } } },
	Kitchen = { Name = "Food Machine", Kind = "FoodMachine", Max = 5, Caps = { 1, 2, 4, 5 }, Req = { Press1 = 1 },
		Price = { 300, 44000, 400000, 850000, 2400000 }, Eff = { FeedShare = { 0.25, 0.30, 0.35, 0.42, 0.50 } } },
	Gym = { Name = "Training Place", Kind = "Training", Max = 5, Caps = { 1, 2, 4, 5 }, Req = { Kitchen = 1 },
		Price = { 3800, 140000, 520000, 1200000, 2800000 }, Eff = { Slots = { 1, 2, 3, 4, 5 } } },
	Vault = { Name = "Vault", Kind = "Vault", Max = 5, Caps = { 1, 2, 4, 5 }, Req = { Press1 = 6 },
		Price = { 11000, 110000, 460000, 1000000, 2500000 },
		Eff = { PileSeconds = { 300, 600, 900, 1200, 1800 }, OfflinePercent = { 0.1, 0.15, 0.2, 0.25, 0.3 }, OfflineHours = { 1, 2, 3, 4, 4 } } },
	House = { Name = "House", Kind = "House", Max = 4, Caps = { 4, 4, 4, 4 }, Req = { Press1 = 2 }, Price = { 180, 24000, 200000, 880000 } },
	FusionMachine = { Name = "Fusion Machine", Kind = "Fusion", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Kitchen = 1, Prestige = 1 },
		Price = { 31000, 420000, 1800000 }, Eff = { TokenDiscount = { 0, 0.1, 0.2 } } },
	ArenaGate = { Name = "Arena Gate", Kind = "Arena", Max = 1, Caps = { 1, 1, 1, 1 }, Req = { Gym = 1 }, Price = { 320000 } },
	DecorFence = { Name = "Yard Fence", Kind = "Decor", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Garden = 1 }, Price = { 2800, 19000, 200000 } },
	DecorFountain = { Name = "Fountain", Kind = "Decor", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Kitchen = 1 }, Price = { 18000, 200000, 600000 } },
	DecorPodium = { Name = "Pet Podium", Kind = "Decor", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Garden = 1 }, Price = { 3600, 38000, 230000 } },
}

-- the Phase 4 prices (contract table 3.1 of Phase 4): stations x1.25 (House not scaled), decor x0.4
local P4_PRICE = {
	Garden = { 0, 12000, 30000, 110000, 290000, 600000, 1200000, 2400000 },
	Kitchen = { 240, 35000, 320000, 680000, 1900000 },
	Gym = { 3000, 110000, 420000, 920000, 2200000 },
	Vault = { 9000, 85000, 370000, 820000, 2000000 },
	House = { 180, 24000, 200000, 880000 },
	FusionMachine = { 25000, 340000, 1400000 },
	ArenaGate = { 260000 },
	DecorFence = { 7000, 48000, 490000 },
	DecorFountain = { 45000, 490000, 1500000 },
	DecorPodium = { 9000, 95000, 580000 },
}

-- slots (contract 3.3): x, z, yaw, footprint w / h / d, pad x / z (0 = the plot size)
local P5_SLOTS = {
	Press1 = { -26.5, 0.25, -90, 36, 12, 7, -19, 0 },
	Garden = { 24, -1, 90, 22, 4, 20, 10, -1 },
	Kitchen = { -24, 29, 0, 16, 10, 10, -19, 21.5 }, -- contract pad z 22.5 moved 1 stud (it reached into the machine)
	Gym = { 25, 24, 0, 18, 10, 9, 19.5, 14.5 },
	Vault = { -10.5, -27, 180, 7, 9, 8, -10.5, -19 },
	House = { 0, 25, 0, 26, 30, 18, 0, 12 },
	FusionMachine = { 11, -25, 180, 10, 12, 10, 11, -16 },
	ArenaGate = { 32, 14.5, 90, 7, 12, 4, 27, 14.5 },
	DecorFence = { 0, 0, 0, 0, 4, 0, 8, -10 },
	DecorFountain = { 0, -1, 0, 9, 8, 9, -7, -1 },
	DecorPodium = { 24, -26, 180, 8, 6, 8, 24, -17.5 },
}

local GARDEN_BEDS = {
	{ -9, -6.5 }, { 9, -6.5 }, { -9, -2.5 }, { 9, -2.5 }, { -9, 1.5 }, { 9, 1.5 },
	{ -9, 5.5 }, { 9, 5.5 }, { -6, 7.8 }, { 6, 7.8 }, { -2, 7.8 }, { 2, 7.8 },
}

local function fmt(v, n)
	return string.format("%." .. (n or 1) .. "f", tonumber(v) or 0)
end

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-9) * max(1, abs(b))
end

local function listEq(a, b, tol)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for i = 1, #a do
		if type(a[i]) == "number" or type(b[i]) == "number" then
			if not near(a[i], b[i], tol) then
				return false
			end
		elseif a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function show(list)
	if type(list) ~= "table" then
		return tostring(list)
	end
	local out = {}
	for i = 1, #list do
		out[i] = tostring(list[i])
	end
	return "[" .. table.concat(out, ", ") .. "]"
end

local function setEq(a, b)
	for k, v in pairs(a) do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in pairs(b) do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

local function reqText(r)
	local keys = {}
	for k in pairs(r or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		out[#out + 1] = k .. "=" .. tostring(r[k])
	end
	return table.concat(out, " ")
end

local function effectList(def, key)
	local out = {}
	for i, e in ipairs(def.Effects) do
		out[i] = e[key]
	end
	return out
end

local function loadCatalog()
	local inst = K.moduleInstance("shared/TycoonCatalog")
	if not inst then
		return nil, "no ModuleScript shared/TycoonCatalog"
	end
	local ok, result = pcall(require, inst)
	if not ok then
		return nil, tostring(result)
	end
	if type(result) ~= "table" then
		return nil, "returned " .. type(result)
	end
	return result, inst
end

-- a file of the repo, read from the working directory (or next to this test file)
local function readRepoFile(rel)
	local here = debug.getinfo(1, "S").source:match("^=(.*)smoke_p4_economy%.lua$")
	local candidates = { rel, "../" .. rel }
	if here and here ~= "" then
		table.insert(candidates, 1, here .. "../" .. rel)
	end
	for _, path in ipairs(candidates) do
		local fh = io.open(path, "r")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src, path
		end
	end
	return nil, rel .. " not found from the working directory (run tools/smoke.py from the repo root)"
end

-- a deterministic pseudo-random generator (Park-Miller): rnd(n) -> 0 .. n - 1
local function makeRandom(seed)
	local s = seed % 2147483647
	if s <= 0 then
		s = s + 2147483646
	end
	return function(n)
		s = (s * 16807) % 2147483647
		return s % n
	end
end

local function home(stations, prestige, extra)
	local h = { Stations = stations or {}, Prestige = prestige or 0, Garden = {}, Gym = {} }
	for k, v in pairs(extra or {}) do
		h[k] = v
	end
	return h
end

local function padOf(pads, id)
	for _, pad in ipairs(pads) do
		if pad.StationId == id then
			return pad
		end
	end
	return nil
end

local function padIds(pads)
	local out = {}
	for _, pad in ipairs(pads) do
		out[pad.StationId] = true
	end
	return out
end

local function idList(set)
	local out = {}
	for k in pairs(set) do
		out[#out + 1] = k
	end
	table.sort(out)
	return table.concat(out, ", ")
end

-- pets of PetCatalog by rarity and role (rollable ones first)
local function findPet(PC, rarity, role)
	for _, def in ipairs(PC.Pets) do
		if def.Rarity == rarity and def.Role == role and not def.EventOnly then
			return def
		end
	end
	for _, def in ipairs(PC.Pets) do
		if def.Rarity == rarity and def.Role == role then
			return def
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- tools/sim_tycoon.py constants block: one `NAME = value` per line (number, [numbers], "string")
----------------------------------------------------------------------------------------------------
local function parseSim(src)
	local block = src:match("# ==== BEGIN SIM CONSTANTS ====\n(.-)\n# ==== END SIM CONSTANTS ====")
	if not block then
		return nil, "no '# ==== BEGIN SIM CONSTANTS ====' ... '# ==== END SIM CONSTANTS ====' block"
	end
	local out, order, bad = {}, {}, {}
	for line in (block .. "\n"):gmatch("([^\n]*)\n") do
		if not line:match("^%s*#") and line:match("%S") then
			local body = line:gsub("%s+#.*$", "")
			local name, value = body:match("^([%w_]+)%s*=%s*(.-)%s*$")
			if not name then
				bad[#bad + 1] = line
			elseif value:sub(1, 1) == "[" then
				local list = {}
				for num in value:gmatch("[-%d%.eE]+") do
					list[#list + 1] = tonumber(num)
				end
				out[name] = list
				order[#order + 1] = name
			elseif value:sub(1, 1) == '"' then
				out[name] = value:match('^"(.*)"$') or ""
				order[#order + 1] = name
			elseif tonumber(value) then
				out[name] = tonumber(value)
				order[#order + 1] = name
			else
				bad[#bad + 1] = line
			end
		end
	end
	return out, order, bad
end

local function words(text)
	local out = {}
	for w in tostring(text or ""):gmatch("%S+") do
		out[#out + 1] = w
	end
	return out
end

-- "Press1=6 House=Villa" -> { Press1 = 6, House = "Villa" }
local function parseReq(text)
	local out = {}
	for _, tok in ipairs(words(text)) do
		local k, v = tok:match("^([%w_]+)=([%w_]+)$")
		if k then
			out[k] = (k == "House") and v or tonumber(v)
		end
	end
	return out
end

-- the sim's model (tools/sim_tycoon.py) written from its constants alone; a home = station levels + the extra keys
-- DecorCredit / LegacyMagnet (the fold credits, like the sim)
local function simModel(sim)
	local M = {}
	local tiers = { Cottage = 1, Villa = 2, Manor = 3, SkyCastle = 4 }
	local tierNames = { "Cottage", "Villa", "Manor", "Sky Castle" }
	local coins = sim.COINS
	local meal, grass, luckyMult, baseRadius, basePile = coins[1], coins[2], coins[3], coins[4], coins[5]
	local slotsT = sim.PRESTIGE_GARDEN_SLOTS
	local keep, soon = {}, {}
	for _, w in ipairs(words(sim.KEEP_ON_PRESTIGE)) do
		keep[w] = true
	end
	for _, w in ipairs(words(sim.COMING_SOON)) do
		soon[w] = true
	end
	local reset = parseReq(sim.RESET_LEVEL)
	function M.food(st)
		if (st.Garden or 0) < 1 then
			return 0
		end
		local lv = st.Press1 or 0
		return grass + (lv > 0 and sim.PLANT_FOOD_Press1[lv] or 0)
	end
	function M.lucky(st)
		local g = st.Garden or 0
		return g > 0 and sim.GARDEN_LUCKY[g] or 0
	end
	function M.slots(stars, legacy, gardenLevel)
		if (gardenLevel or 0) < 1 then
			return 0
		end
		return min(slotsT[3], max(slotsT[1] + slotsT[2] * stars, legacy or 0))
	end
	function M.pile(st)
		local g, v, m = st.Garden or 0, st.Vault or 0, st.LegacyMagnet or 0
		local s = g > 0 and sim.GARDEN_PILE_SECONDS[g] or basePile
		if m > 0 then
			s = max(s, sim.LEGACY_MAGNET_PILE_SECONDS[m])
		end
		return s + (v > 0 and sim.VAULT_PILE_SECONDS[v] or 0)
	end
	function M.radius(st)
		local g, m = st.Garden or 0, st.LegacyMagnet or 0
		local r = g > 0 and sim.GARDEN_RADIUS[g] or baseRadius
		if m > 0 then
			r = max(r, sim.LEGACY_MAGNET_RADIUS[m])
		end
		return r
	end
	function M.starFactor(stars, legacyPrices)
		if legacyPrices then
			return 1
		end
		return (1 + sim.PRESTIGE_PRICE_STEP) ^ stars
	end
	function M.priceAt(id, lvl, stars, legacyPrices)
		return floor(sim["PRICE_" .. id][lvl] * M.starFactor(stars, legacyPrices) + 1e-9)
	end
	function M.homeLevel(st)
		local n = 0
		for _, id in ipairs(CONTRACT_IDS) do
			n = n + (st[id] or 0)
		end
		return n + min(sim.DECOR_CREDIT_MAX, st.DecorCredit or 0) + (st.LegacyMagnet or 0)
	end
	function M.pads(st, stars, legacyPrices)
		local out = {}
		local hl = M.homeLevel(st)
		local tier = max(1, st.House or 0)
		for _, id in ipairs(CONTRACT_IDS) do
			local prices = sim["PRICE_" .. id]
			local caps = sim["CAPS_" .. id]
			local req = parseReq(sim["REQ_" .. id])
			local lv = st[id] or 0
			local treeOk = true
			for k, v in pairs(req) do
				if k ~= "House" and k ~= "Prestige" and k ~= "HomeLevel" and (st[k] or 0) < v then
					treeOk = false
				end
			end
			if lv < #prices and treeOk then
				local nxt = lv + 1
				local lock = nil
				if soon[id] then
					lock = "Coming soon"
				elseif (req.Prestige or 0) > stars then
					lock = "Unlocks at Prestige " .. req.Prestige
				elseif req.House and tiers[req.House] > tier then
					lock = "Needs the " .. tierNames[tiers[req.House]]
				elseif id == "House" and sim.HOUSE_HOME_LEVEL[nxt] > hl then
					lock = "Reach Home Level " .. sim.HOUSE_HOME_LEVEL[nxt]
				elseif nxt > caps[tier] then
					for i = 1, 4 do
						if caps[i] >= nxt then
							lock = "Needs the " .. tierNames[i]
							break
						end
					end
				end
				out[#out + 1] = { id, nxt, M.priceAt(id, nxt, stars, legacyPrices), lock }
			end
		end
		return out
	end
	function M.afterPrestige(st)
		local out = {}
		for id, lv in pairs(st) do
			if keep[id] and lv > 0 then
				out[id] = lv
			end
		end
		for id, lv in pairs(reset) do
			if not keep[id] then
				out[id] = lv
			end
		end
		return out
	end
	function M.power(ri, econ, level, tierMult, evo)
		local top = sim.EVOLVE_TWICE[ri] == 1 and 2 or 1
		local stage = min(evo or 0, top)
		local bonus = stage >= 1 and sim.EVOLUTION_BONUS[stage] or 1
		local lv = max(1, min(level, sim.PET_XP[1]))
		return sim.RARITY_SCALE[ri] * (1 + 0.1 * (lv - 1) * bonus) * tierMult * (econ and sim.ROLE_MULT[1] or sim.ROLE_MULT[2])
	end
	function M.income(st, powers, stars, legacy)
		local open = M.slots(stars, legacy, st.Garden or 0)
		local sum = 0
		for i = 1, min(open, #powers) do
			sum = sum + powers[i]
		end
		return M.food(st) / meal * sum * (1 + (luckyMult - 1) * M.lucky(st)) * sim.PRESTIGE_MULTIPLIER ^ stars
	end
	function M.offline(st, seconds, inc)
		local v = st.Vault or 0
		if v < 1 or seconds < sim.OFFLINE_MIN_SECONDS then
			return 0
		end
		return floor(inc * min(seconds, sim.VAULT_OFFLINE_HOURS[v] * 3600) * sim.VAULT_OFFLINE_PERCENT[v])
	end
	function M.xpToNext(level)
		local px = sim.PET_XP
		if level >= px[1] then
			return huge
		end
		return max(px[4], floor(px[2] * level ^ px[3] / px[4] + 0.5) * px[4])
	end
	function M.feedXp(level, machine)
		if machine < 1 then
			return 0
		end
		local need = M.xpToNext(level)
		if need == huge then
			return 0
		end
		return max(1, floor(need * sim.FEED_SHARE[min(machine, #sim.FEED_SHARE)] + 0.5))
	end
	function M.feedBerries(ri, level)
		local need = M.xpToNext(level)
		if need == huge then
			return nil
		end
		return floor(need * sim.RARITY_SCALE[ri] * sim.FEED_BASE + 0.5)
	end
	function M.basketCap(ips)
		return max(sim.BERRY_BASKET_MIN, floor(max(0, ips) * sim.BERRY[1] * 60 * sim.BERRY[2] + 1e-9))
	end
	function M.trainCost(ri, rank)
		return floor(sim.TRAINING[2] * rank * rank * sim.RARITY_SCALE[ri] + 0.5)
	end
	function M.trainSeconds(rank)
		return rank * sim.TRAINING[3] * 60
	end
	return M
end

----------------------------------------------------------------------------------------------------
-- checks
----------------------------------------------------------------------------------------------------
local function apiChecks(TC)
	local fns = {
		"Get", "PriceFor", "PriceAt", "StarPriceMultiplier", "AvailablePads", "CheckPurchase", "HomeLevelOf",
		"StationsAfterPrestige", "FoodOf", "PetPower", "GardenSlots", "IncomePerSecond", "LuckyChance", "LuckyEV",
		"CoinValue", "ScoopRadius", "PileSeconds", "OfflineEarnings", "XpToNext", "XpForLevel", "FeedXp", "FeedPrice",
		"TrainCost", "TrainSeconds", "TrainingSlots", "FusionCost", "FormatCash", "Validate", "ReachablePads",
		"SignedPads", "FoldLegacy", "BasketCap", "FeedBerries", "RoamLayout", "LegacyMagnetLevel",
	}
	local missing = {}
	for _, name in ipairs(fns) do
		if type(TC[name]) ~= "function" then
			missing[#missing + 1] = name
		end
	end
	T.check(#missing == 0, "economy: the Phase 5 API is complete (incl. SignedPads / FoldLegacy / BasketCap / FeedBerries / RoamLayout / LegacyMagnetLevel)", table.concat(missing, ", "))
	T.check(listEq(TC.Kinds, KINDS), "economy: Kinds = Farm, Garden, FoodMachine, Training, Vault, House, Fusion, Arena, Decor", show(TC.Kinds))
	T.check(#TC.Stations == #CONTRACT_IDS and listEq(TC.Order, CONTRACT_IDS), "economy: the 11 stations in the contract order", show(TC.Order))
	local defT = T.tally("economy: every station matches contract table 3.3 (name, kind, max, caps, tree, prices, effects)", 6)
	for _, id in ipairs(CONTRACT_IDS) do
		local c, d = CONTRACT[id], TC.Get(id)
		if not defT:case(d ~= nil, id .. " missing") then
			-- next
		else
			defT:case(d.Name == c.Name and d.Kind == c.Kind and d.MaxLevel == c.Max, id .. ": " .. tostring(d.Name) .. " / " .. tostring(d.Kind) .. " / " .. tostring(d.MaxLevel))
			defT:case(d.TierCaps.Cottage == c.Caps[1] and d.TierCaps.Villa == c.Caps[2] and d.TierCaps.Manor == c.Caps[3] and d.TierCaps.SkyCastle == c.Caps[4], id .. " caps")
			defT:case(reqText(d.Requires) == reqText(c.Req), id .. " Requires " .. reqText(d.Requires) .. " vs " .. reqText(c.Req))
			defT:case(listEq(d.Price, c.Price), id .. " Price " .. show(d.Price))
			for key, values in pairs(c.Eff or {}) do
				defT:case(listEq(effectList(d, key), values), id .. " Effects." .. key .. " " .. show(effectList(d, key)))
			end
		end
	end
	defT:report()
	-- caps sums 24 / 45 / 72 / 80
	local sums = {}
	for i, tier in ipairs(TIER_IDS) do
		local n = 0
		for _, def in ipairs(TC.Stations) do
			n = n + (def.TierCaps[tier] or 0)
		end
		sums[i] = n
	end
	T.check(listEq(sums, { 24, 45, 72, 80 }), "economy: tier-cap sums 24 / 45 / 72 / 80", show(sums))
	-- prices = Phase 4 x1.25 (House not scaled), decor = 0.4 x Phase 4
	local priceT = T.tally("economy: station prices = Phase 4 x1.25 (+-5%: rounded to 2 digits), the House unscaled, decor = 0.4 x Phase 4")
	for id, old in pairs(P4_PRICE) do
		local d = TC.Get(id)
		local def = TC.Get(id)
		local k = (id == "House") and 1 or (def and def.Kind == "Decor") and 0.4 or 1.25
		for lv, p in ipairs(old) do
			local got = d and d.Price[lv]
			priceT:case(type(got) == "number" and abs(got - p * k) <= 0.05 * max(1, p * k), id .. " L" .. lv .. ": " .. tostring(got) .. " vs " .. fmt(p * k, 0))
		end
	end
	priceT:report()
	-- the deletions of 3.5
	local gone = {}
	for _, name in ipairs({ "Foods", "FoodsById", "FoodById", "CollectorCap" }) do
		if TC[name] ~= nil then
			gone[#gone + 1] = name
		end
	end
	for _, id in ipairs({ "Press2", "Press3", "Press4", "Collector", "DecorLamps", "DecorFlowers", "DecorBanners" }) do
		if TC.Get(id) ~= nil then
			gone[#gone + 1] = id
		end
	end
	if TC.Coins.HeapStages ~= nil then
		gone[#gone + 1] = "Coins.HeapStages"
	end
	if TC.Prestige.TeamSlotUnlock ~= nil then
		gone[#gone + 1] = "Prestige.TeamSlotUnlock"
	end
	local gs = TC.Get("Garden").Slot
	if gs.Spots ~= nil or gs.CoinPoints ~= nil or gs.Walkable ~= nil then
		gone[#gone + 1] = "Garden.Slot.Spots / CoinPoints / Walkable"
	end
	T.check(#gone == 0, "economy: the Phase 5 deletions (old stations, Foods, CollectorCap, HeapStages, TeamSlotUnlock, garden walks / spots / coin points)", table.concat(gone, ", "))
	-- data
	local C, B = TC.Coins, TC.Berries
	T.check(C.MealSeconds == 8 and C.GrassFood == 12 and C.LuckyMult == 5 and C.BaseRadius == 6 and C.BasePileSeconds == 240
		and C.PoopMeals == 3 and C.DropsPerPet == 3 and listEq(C.DropStages, { 1, 2, 4, 8 }),
		"economy: Coins { MealSeconds 8, GrassFood 12, LuckyMult 5, BaseRadius 6, BasePileSeconds 240, PoopMeals 3, DropsPerPet 3, DropStages {1, 2, 4, 8} }")
	T.check(type(B) == "table" and B.Share == 0.25 and B.BasketMinutes == 30 and B.BasketMin == 500 and type(B.LegacyFood) == "table"
		and B.LegacyFood.Snack == 200 and B.LegacyFood.Meal == 1200 and B.LegacyFood.Feast == 6400,
		"economy: Berries { Share 0.25, BasketMinutes 30, BasketMin 500, LegacyFood Snack 200 / Meal 1200 / Feast 6400 }")
	T.check(TC.SignRules and TC.SignRules.MaxSigns == 3, "economy: SignRules.MaxSigns 3")
	T.check(listEq(TC.LegacyMagnet.Radius, { 9, 12, 16, 20, 26 }) and listEq(TC.LegacyMagnet.PileSeconds, { 300, 360, 420, 480, 600 }),
		"economy: LegacyMagnet = the Phase 4 Coin Magnet tables (radius 9..26, pile 300..600)")
	T.check(TC.Get("Garden").ResetLevel == 1 and TC.Get("Garden").Price[1] == 0, "economy: the Pet Garden is free and Prestige keeps it at level 1")
	T.check(TC.Prestige.HomeLevel == 40 and TC.Prestige.House == "SkyCastle" and TC.Prestige.PriceStep == 0.5 and TC.Prestige.IncomeMultiplier == 1.25,
		"economy: Prestige unchanged (Home Level 40 + Sky Castle, x1.25 coins, prices x1.5 per star)")
end

local function padChecks(TC)
	local fresh = TC.AvailablePads(home({}, 0))
	T.check(#fresh == 1 and fresh[1].StationId == "Garden" and fresh[1].Price == 0 and fresh[1].Locked == nil,
		"economy: a fresh home shows ONE pad, the free Pet Garden", idList(padIds(fresh)))
	local g1 = padIds(TC.AvailablePads(home({ Garden = 1 }, 0)))
	T.check(g1.Press1 and g1.DecorFence and g1.DecorPodium and g1.Garden and not g1.Kitchen and not g1.House and not g1.Vault,
		"economy: after the Garden: Berry Farm, Yard Fence, Pet Podium and Garden 2 (the Food Machine / House wait for the Farm)", idList(g1))
	local f1 = padIds(TC.AvailablePads(home({ Garden = 1, Press1 = 1 }, 0)))
	T.check(f1.Kitchen and not f1.House and not f1.Vault, "economy: Farm 1 opens the Food Machine; the House needs Farm 2", idList(f1))
	local f2 = padIds(TC.AvailablePads(home({ Garden = 1, Press1 = 2 }, 0)))
	T.check(f2.House and not f2.Vault, "economy: Farm 2 opens the House; the Vault needs Farm 6", idList(f2))
	T.check(padIds(TC.AvailablePads(home({ Garden = 1, Press1 = 6 }, 0))).Vault == true, "economy: Farm 6 opens the Vault")
	local k1 = TC.AvailablePads(home({ Garden = 1, Press1 = 1, Kitchen = 1 }, 0))
	T.check(padOf(k1, "FusionMachine") and padOf(k1, "FusionMachine").Locked == "Unlocks at Prestige 1" and padOf(k1, "DecorFountain") and padOf(k1, "Gym"),
		"economy: the Food Machine opens the Training Place, the Fountain and the Fusion Machine (\"Unlocks at Prestige 1\")")
	local h1 = TC.AvailablePads(home({ Garden = 1, Press1 = 2, House = 1 }, 0))
	T.eq(padOf(h1, "House") and padOf(h1, "House").Locked, "Reach Home Level 10", "economy: the Villa needs Home Level 10")
	local f10 = TC.AvailablePads(home({ Garden = 1, Press1 = 10, House = 1 }, 0))
	T.eq(padOf(f10, "Press1") and padOf(f10, "Press1").Locked, "Needs the Villa", "economy: Farm 11 at the Cottage: \"Needs the Villa\"")
	T.check(padOf(TC.AvailablePads(home({ Garden = 1, Press1 = 2, House = 3 }, 0)), "Prestige") == nil
		and padOf(TC.AvailablePads(home({ Garden = 1, Press1 = 2, House = 4 }, 0)), "Prestige") ~= nil,
		"economy: the prestige pad shows only with the Sky Castle")
	-- star prices
	local starT = T.tally("economy: PriceAt = floor(PriceFor x 1.5 ^ stars), LegacyPrices exempt, pads + CheckPurchase agree")
	for _, id in ipairs(CONTRACT_IDS) do
		for _, stars in ipairs({ 0, 1, 2, 5 }) do
			local base = TC.PriceFor(id, 1)
			starT:case(TC.PriceAt(id, 1, home({}, stars)) == floor(base * 1.5 ^ stars + 1e-9), id .. " stars " .. stars)
			starT:case(TC.PriceAt(id, 1, home({}, stars, { LegacyPrices = true })) == base, id .. " legacy")
		end
	end
	local h = home({ Garden = 1, Press1 = 3 }, 2)
	local ok, price = TC.CheckPurchase(h, "Press1")
	starT:case(ok and price == floor(450 * 2.25 + 1e-9) and padOf(TC.AvailablePads(h), "Press1").Price == price, "CheckPurchase Press1 L4 at 2 stars: " .. tostring(price))
	starT:report()
	-- prestige keeps the decor and the Garden
	local after = TC.StationsAfterPrestige({ Garden = 6, Press1 = 30, Kitchen = 3, DecorFence = 2, DecorPodium = 1, House = 4 })
	T.check(setEq(after, { Garden = 1, DecorFence = 2, DecorPodium = 1 }), "economy: StationsAfterPrestige keeps the decor and the Garden at 1")
	-- Home Level with the fold credits
	T.eq(TC.HomeLevelOf(home({ Garden = 2, Press1 = 5 }, 0, { DecorCredit = 3 })), 10, "economy: HomeLevelOf counts DecorCredit")
	T.eq(TC.HomeLevelOf(home({ Garden = 2 }, 1, { LegacyMagnet = 4, LegacyMagnetStar = 1 })), 6, "economy: ...and the legacy magnet while its star holds")
	T.eq(TC.HomeLevelOf(home({ Garden = 2 }, 2, { LegacyMagnet = 4, LegacyMagnetStar = 1 })), 2, "economy: ...and not after the next Prestige (LegacyMagnetStar ~= Prestige)")
	T.eq(TC.LegacyMagnetLevel(home({}, 0, { LegacyMagnet = 9, LegacyMagnetStar = 0 })), 5, "economy: LegacyMagnetLevel is clamped to 5")
	T.eq(TC.HomeLevelOf(home({}, 0, { DecorCredit = 99 })), 18, "economy: DecorCredit counts at most 18")
end

local function coinChecks(TC, PC, Config)
	T.eq(TC.FoodOf(home({ Press1 = 5 }, 0)), 0, "economy: FoodOf = 0 without a Garden")
	T.eq(TC.FoodOf(home({ Garden = 1 }, 0)), 12, "economy: FoodOf = GrassFood 12 with the Garden alone")
	T.eq(TC.FoodOf(home({ Garden = 1, Press1 = 40 }, 0)), 12 + 2132, "economy: FoodOf = 12 + the Farm's Food (L40 2,132: the old 2,144 meal)")
	-- PetPower = RarityScale x LevelFactor(level, stage) x tier x RoleMult
	local common = findPet(PC, "Common", "Combat")
	local epicE = findPet(PC, "Epic", "Economy")
	local powT = T.tally("economy: PetPower = RarityScale x LevelFactor(level, stage) x TierMultiplier x RoleMult (the stage cleaned by EvolutionStage)")
	if common and epicE then
		powT:case(near(TC.PetPower(common, 1, "Normal", 0), 1), "Common L1: " .. fmt(TC.PetPower(common, 1, "Normal", 0), 4))
		powT:case(near(TC.PetPower(common, 20, "Normal", 1), 3.85), "Common L20 evo 1 = 3.85: " .. fmt(TC.PetPower(common, 20, "Normal", 1), 4))
		powT:case(near(TC.PetPower(common, 20, "Normal", 2), 3.85), "Common at stored stage 2 counts stage 1")
		powT:case(near(TC.PetPower(common, 50, "Normal", nil), 5.9), "no stage = stage 0: L50 5.9")
		local scale = Config.PetStats.RarityScale.Epic
		powT:case(near(TC.PetPower(epicE, 50, "Golden", 2), scale * (1 + 0.1 * 49 * 1.875) * 1.5 * 1.6), "Epic Economy L50 Golden evo 2")
		powT:case(near(TC.PetPower(epicE, 50, "Golden", 2), scale * PC.LevelFactor(50, 2) * 1.5 * PC.RoleMult.Economy), "== PetCatalog.LevelFactor")
		powT:case(near(TC.PetPower({ Def = epicE, Level = 100, Tier = "Rainbow", Stage = 2 }), scale * 19.5625 * 2.5 * 1.6), "{Def, Level, Tier, Stage} entry")
		powT:case(near(TC.PetPower(epicE.Id .. "@Rainbow", 1), scale * 2.5 * 1.6), "pet key with a tier")
		powT:case(TC.PetPower(7.5) == 7.5 and TC.PetPower({ Power = 3 }) == 3 and TC.PetPower("hyb:x") == 0, "number / {Power} / hybrid key")
	else
		powT:case(false, "no Common Combat / Epic Economy pet in PetCatalog")
	end
	powT:report()
	-- income, slots, piles, radius
	local h = home({ Garden = 4, Press1 = 10, Vault = 2 }, 1)
	local inc, parts = TC.IncomePerSecond(h, { 2, 3, 5, 7, 11 })
	local want = (12 + 69) / 8 * (2 + 3 + 5 + 7) * (1 + 4 * 0.06) * 1.25
	T.check(near(inc, want) and parts.Pets == 17, "economy: IncomePerSecond = Food / 8 x the open places' power (4 at one star) x LuckyEV x 1.25 ^ stars", fmt(inc, 4) .. " vs " .. fmt(want, 4))
	T.check(TC.GardenSlots(home({ Garden = 1 }, 0)) == 3 and TC.GardenSlots(home({ Garden = 1 }, 1)) == 4 and TC.GardenSlots(home({ Garden = 1 }, 20)) == 12
		and TC.GardenSlots(home({}, 3)) == 0 and TC.GardenSlots(home({ Garden = 1 }, 0, { LegacySlots = 7 })) == 7,
		"economy: GardenSlots 3 / 4 at one star / 12 max / 0 without a Garden / LegacySlots")
	T.check(TC.ScoopRadius(home({}, 0)) == 6 and TC.ScoopRadius(home({ Garden = 1 }, 0)) == 8 and TC.ScoopRadius(home({ Garden = 8 }, 0)) == 26
		and TC.ScoopRadius(home({ Garden = 1 }, 0, { LegacyMagnet = 3, LegacyMagnetStar = 0 })) == 16
		and TC.ScoopRadius(home({ Garden = 1 }, 1, { LegacyMagnet = 3, LegacyMagnetStar = 0 })) == 8,
		"economy: ScoopRadius = max(Garden Radius, the legacy magnet while its star holds), 6 without a Garden")
	T.check(TC.PileSeconds(home({}, 0)) == 240 and TC.PileSeconds(home({ Garden = 3, Vault = 2 }, 0)) == 360 + 600
		and TC.PileSeconds(home({ Garden = 1 }, 0, { LegacyMagnet = 5, LegacyMagnetStar = 0 })) == 600,
		"economy: PileSeconds = max(Garden pile, legacy magnet pile) + Vault, 240 without a Garden")
	T.check(TC.OfflineEarnings(home({}, 0), 9999, 10) == 0 and TC.OfflineEarnings(home({ Vault = 1 }, 0), 100, 10) == 0
		and TC.OfflineEarnings(home({ Vault = 1 }, 0), 7200, 10) == 3600 and TC.OfflineEarnings(home({ Vault = 5 }, 0), 99999, 10) == floor(10 * 4 * 3600 * 0.3),
		"economy: OfflineEarnings (0 without a Vault, 0 under 120 s, capped by OfflineHours)")
	T.check(near(TC.CoinValue(home({ Garden = 1, Press1 = 1 }, 2), 2), 19 * 2 * 1.5625), "economy: CoinValue = Food x power x 1.25 ^ stars")
	T.check(TC.HeapStage == nil and TC.CoinPoint == nil, "economy: the deprecated HeapStage / CoinPoint are gone (W3 gate)")
	local bed = TC.ById.Garden.Slot.Beds[1]
	T.check(typeof(bed) == "Vector3" and bed.X == -9 and bed.Z == -6.5 and TC.ById.Garden.Slot.Beds[13] == nil,
		"economy: Garden.Slot.Beds[1] is the slot's bed (12 beds)")
end

local function careChecks(TC, PC)
	local tally = T.tally("economy: FeedBerries == FeedPrice == round(XpToNext x RarityScale x 2); FeedXp by machine level; nil at level 100")
	for _, rarity in ipairs(RARITY_ORDER) do
		for _, lv in ipairs({ 1, 2, 19, 20, 49, 99 }) do
			local fb, fp = TC.FeedBerries(rarity, lv), TC.FeedPrice(rarity, lv)
			tally:case(fb ~= nil and fb == fp, rarity .. " L" .. lv .. ": " .. tostring(fb) .. " vs " .. tostring(fp))
		end
		tally:case(TC.FeedBerries(rarity, 100) == nil, rarity .. " L100")
	end
	tally:case(TC.FeedBerries("Common", 1) == 40, "Common L1 = 40 berries: " .. tostring(TC.FeedBerries("Common", 1)))
	tally:case(TC.FeedXp(1, 0) == 0 and TC.FeedXp(1, 1) == 5 and TC.FeedXp(10, 5) == floor(TC.XpToNext(10) * 0.5 + 0.5), "FeedXp")
	tally:report()
	T.check(TC.BasketCap(nil, 0) == 500 and TC.BasketCap(nil, 1) == 500 and TC.BasketCap(nil, 10) == 4500 and TC.BasketCap(nil, 123.4) == floor(123.4 * 0.25 * 60 * 30 + 1e-9)
		and TC.BasketCap(nil, 0 / 0) == 500 and TC.BasketCap(nil, -5) == 500 and TC.BasketCap(nil, "x") == 500,
		"economy: BasketCap = max(500, floor(income x 0.25 x 60 x 30)); junk income -> 500")
	T.check(TC.TrainCost("Common", 1) == 300 and TC.TrainCost("Epic", 10) == floor(300 * 100 * 3.5 + 0.5) and TC.TrainCost("Common", 11) == nil
		and TC.TrainSeconds(3) == 180 and TC.TrainSeconds(0) == nil and TC.TrainingSlots(home({ Gym = 3 }, 0)) == 3,
		"economy: TrainCost / TrainSeconds / TrainingSlots unchanged")
end

local function signChecks(TC)
	local function pad(id, price, locked, prestige)
		return { StationId = id, Price = price, Locked = locked, Prestige = prestige }
	end
	local pads = { pad("Press1", 450), pad("Garden", 15000), pad("Kitchen", 300), pad("House", 24000, "Reach Home Level 10"),
		pad("DecorFence", 2800), pad("DecorPodium", 3600), pad("Prestige", 0, nil, true) }
	local function ids(set)
		return idList(set)
	end
	T.eq(ids(TC.SignedPads(pads, 5000)), "DecorFence, Kitchen, Press1, Prestige", "economy: SignedPads = the open Prestige pad + the 3 cheapest affordable open pads")
	T.eq(ids(TC.SignedPads(pads, 100)), "Kitchen, Prestige", "economy: ...none affordable -> the single cheapest open pad")
	T.eq(ids(TC.SignedPads(pads, 1e9, 1)), "Kitchen, Prestige", "economy: ...maxSigns honoured")
	pads[7].Locked = "Reach Home Level 40"
	T.eq(ids(TC.SignedPads(pads, 1e9)), "DecorFence, Kitchen, Press1", "economy: ...a Locked pad (the Prestige too) never gets a sign")
	T.eq(ids(TC.SignedPads({ pad("A", 5), pad("B", 5), pad("C", 5), pad("D", 5) }, 10)), "A, B, C", "economy: ...ties keep the pad order")
	T.eq(ids(TC.SignedPads(nil, 5)), "", "economy: ...junk pads -> no signs")
	local real = TC.SignedPads(TC.AvailablePads(home({}, 0)), 0)
	T.check(real.Garden == true, "economy: ...a fresh home signs the free Garden")
end

local function foldChecks(TC)
	local h = home({ Press1 = 6, Press2 = 4, Collector = 3, DecorLamps = 2, DecorFlowers = 1, DecorFence = 2, Garden = 3 }, 2)
	local changed = TC.FoldLegacy(h, true)
	T.check(changed == true and h.Stations.Press1 == 10 and h.Stations.Press2 == nil and h.Stations.Collector == nil
		and h.Stations.DecorFence == 2 and h.Stations.DecorFountain == 2 and h.Stations.DecorLamps == nil and h.Stations.DecorFlowers == nil
		and h.DecorCredit == 1 and h.LegacyMagnet == 3 and h.LegacyMagnetStar == 2,
		"economy: FoldLegacy: plants -> one farm, Collector -> LegacyMagnet at this Prestige, old decor -> Fence / Fountain + DecorCredit")
	T.check(TC.FoldLegacy(h, false) == false, "economy: ...a second fold changes nothing")
	T.check(TC.FoldLegacy(nil, true) == false and TC.FoldLegacy({}, true) == false and TC.FoldLegacy({ Stations = "x" }, true) == false,
		"economy: ...junk homes fold to nothing without errors")
end

local function mirrorChecks(TC, PC, Config)
	local src, path = readRepoFile("src/shared/TycoonCatalog.lua")
	if not T.check(src ~= nil, "economy: src/shared/TycoonCatalog.lua is readable", path) then
		return
	end
	local configInst = { Name = "Config" }
	local shared = { Config = configInst }
	function shared:FindFirstChild(name)
		return nil
	end
	local env = setmetatable({
		script = { Parent = shared },
		require = function(m)
			if m == configInst then
				return Config
			end
			error("no module " .. tostring(m))
		end,
	}, { __index = _G })
	local fn, err
	if setfenv and loadstring then
		fn, err = loadstring(src, "=TycoonCatalog(no PetCatalog)")
		if fn then
			setfenv(fn, env)
		end
	else
		fn, err = load(src, "=TycoonCatalog(no PetCatalog)", "t", env)
	end
	if not T.check(fn ~= nil, "economy: ...and compiles", err) then
		return
	end
	local ok, solo = pcall(fn)
	if not T.check(ok and type(solo) == "table" and solo ~= TC, "economy: a copy of TycoonCatalog loads without PetCatalog (the pure-tool path)", tostring(solo)) then
		return
	end
	local tally = T.tally("economy: PetPower without PetCatalog (the mirrors of LevelBonus / EvolutionBonus / RoleMult / EvolveTwice) == PetPower with it, every pet x level x tier x stage")
	for _, def in ipairs(PC.Pets) do
		for _, lv in ipairs({ 1, 20, 50, 100 }) do
			for _, tier in ipairs({ "Normal", "Rainbow" }) do
				for stage = 0, 3 do
					local a, b = solo.PetPower(def, lv, tier, stage), TC.PetPower(def, lv, tier, stage)
					tally:case(near(a, b), def.Id .. " L" .. lv .. " " .. tier .. " stage " .. stage .. ": " .. fmt(a, 3) .. " vs " .. fmt(b, 3))
				end
			end
		end
	end
	tally:report()
	local Mi = TC.Mirror
	T.check(type(Mi) == "table" and Mi.LevelBonus == PC.LevelBonus and Mi.EvolutionBonus[0] == PC.EvolutionBonus[0]
		and Mi.EvolutionBonus[1] == PC.EvolutionBonus[1] and Mi.EvolutionBonus[2] == PC.EvolutionBonus[2]
		and Mi.RoleMult.Economy == PC.RoleMult.Economy and Mi.RoleMult.Combat == PC.RoleMult.Combat,
		"economy: TycoonCatalog.Mirror == PetCatalog (LevelBonus 0.1, EvolutionBonus 1 / 1.5 / 1.875, RoleMult)")
	local okV, valid = pcall(solo.Validate)
	T.check(okV and valid == true, "economy: ...and the PetCatalog-less copy passes Validate() too")
end

local function junkChecks(TC)
	local junk = { nil, false, 0 / 0, math.huge, -1, "x", {}, { Stations = "x" }, { Stations = { Press1 = "x", Garden = 0 / 0 } },
		{ Stations = { Press1 = 1e9 }, Prestige = -5 }, { Prestige = 1e12, DecorCredit = "x", LegacyMagnet = {} } }
	local tally = T.tally("economy: junk homes / arguments never error")
	for i = 1, 11 do
		local h = junk[i]
		local ok, e = pcall(function()
			TC.AvailablePads(h)
			TC.HomeLevelOf(h)
			TC.FoodOf(h)
			TC.GardenSlots(h)
			TC.ScoopRadius(h)
			TC.PileSeconds(h)
			TC.IncomePerSecond(h, junk)
			TC.OfflineEarnings(h, "x", 0 / 0)
			TC.CheckPurchase(h, "Press1")
			TC.CheckPurchase(h, {})
			TC.LegacyMagnetLevel(h)
			TC.BasketCap(h, h)
			TC.FeedBerries(h, h)
			TC.SignedPads(h, h, h)
			TC.PetPower(h, h, h, h)
			TC.PriceAt("Press1", h, h)
			if type(h) == "table" then
				TC.FoldLegacy(h, true)
			end
		end)
		tally:case(ok, "case " .. i .. ": " .. tostring(e))
	end
	tally:report()
end

local function validateChecks(TC)
	local ok, problems = TC.Validate()
	T.check(ok == true, "economy: Validate() passes", table.concat(problems or {}, " | "))
	-- it catches its rules: break a copy of a few fields and restore them
	local garden = TC.Get("Garden")
	local bed = garden.Slot.Beds[12]
	garden.Slot.Beds[12] = Vector3.new(0, 0, 1)
	local ok2, p2 = TC.Validate()
	garden.Slot.Beds[12] = bed
	T.check(ok2 == false and table.concat(p2, " "):find("Food Bowl") ~= nil, "economy: Validate() catches a bed on the Food Bowl", table.concat(p2 or {}, " | "))
	local food = TC.Get("Press1").Effects[3].Food
	TC.Get("Press1").Effects[3].Food = 1
	local ok3 = TC.Validate()
	TC.Get("Press1").Effects[3].Food = food
	T.check(ok3 == false, "economy: Validate() catches a Farm Food that does not rise")
	local wp = garden.Slot.WelcomePile
	garden.Slot.WelcomePile = Vector3.new(24, 0, -1)
	local ok4 = TC.Validate()
	garden.Slot.WelcomePile = wp
	T.check(ok4 == false, "economy: Validate() catches a Welcome pile inside the garden fence")
	T.check(TC.Validate() == true, "economy: ...and passes again once restored")
end

local function layoutChecks(TC)
	local tally = T.tally("economy: every slot sits where contract 3.3 puts it (the Farm in the four press slots, Kitchen / Gym swapped)")
	for id, s in pairs(P5_SLOTS) do
		local slot = TC.Get(id).Slot
		local p, fp, pad = slot.CFrame.Position, slot.Footprint, slot.Pad.Position
		local w = s[4] == 0 and TC.PlotSize or s[4]
		local d = s[6] == 0 and TC.PlotSize or s[6]
		tally:case(near(p.X, s[1], 1e-6) and near(p.Z, s[2], 1e-6) and near(fp.X, w, 1e-6) and near(fp.Y, s[5], 1e-6) and near(fp.Z, d, 1e-6)
			and near(pad.X, s[7], 1e-6) and near(pad.Z, s[8], 1e-6), id .. ": " .. fmt(p.X) .. ", " .. fmt(p.Z) .. " pad " .. fmt(pad.X) .. ", " .. fmt(pad.Z))
	end
	tally:report()
	local g = TC.Get("Garden").Slot
	local bedsOk = #g.Beds == 12
	for i, b in ipairs(GARDEN_BEDS) do
		bedsOk = bedsOk and g.Beds[i] and g.Beds[i].X == b[1] and g.Beds[i].Z == b[2]
	end
	T.check(bedsOk and g.Bowl.Radius == 2.5 and g.Bowl.Center.Magnitude == 0 and g.Entrance.Width == 4 and g.Entrance.Center.Z == -10
		and g.Fence == 0.6 and g.WelcomePile.X == 13.5 and g.WelcomePile.Z == 2.5,
		"economy: the garden interior: 12 beds (entrance first), the Food Bowl r 2.5, a 0.6 fence with the 4-stud entrance, the Welcome pile (13.5, 2.5)")
	T.check(#TC.Get("Gym").Slot.Spots == 5, "economy: the Training Place keeps its 5 Spots")
	local reach = TC.ReachablePads(1, 1)
	local bad = {}
	for id, ok in pairs(reach) do
		if not ok then
			bad[#bad + 1] = id
		end
	end
	T.check(#bad == 0, "economy: every pad is reachable from the gate", table.concat(bad, ", "))
	local L = TC.RoamLayout()
	T.check(type(L) == "table" and #L.Beds == 12 and L.Bowl.X == 24 and L.Bowl.Z == -1 and L.Half == 33 and L.Cell == 2 and #L.Blocked >= 25
		and L.Welcome[1] == 13.5 and L.Welcome[2] == 2.5 and TC.RoamLayout() ~= L,
		"economy: RoamLayout(): beds, the bowl at (24, -1), Half 33, Cell 2, the blocked rects, the Welcome pile; a fresh table per call")
end

----------------------------------------------------------------------------------------------------
-- parity with tools/sim_tycoon.py
----------------------------------------------------------------------------------------------------
local function simChecks(TC, PC, Config)
	local src, path = readRepoFile("tools/sim_tycoon.py")
	if not T.check(src ~= nil, "economy: tools/sim_tycoon.py is readable", path) then
		return
	end
	local sim, order, bad = parseSim(src)
	if not T.check(sim ~= nil, "economy: the sim's constants block parses", order) then
		return
	end
	T.check(#bad == 0, "economy: ...every line of the block is NAME = number / [numbers] / \"string\"", table.concat(bad, " | "))
	T.check(#order >= 60, "economy: ...and it holds the whole economy (" .. #order .. " constants, >= 60)")
	local used = {}
	local function get(name)
		used[name] = true
		return sim[name]
	end
	local keep, soon = {}, {}
	for _, w in ipairs(words(get("KEEP_ON_PRESTIGE"))) do
		keep[w] = true
	end
	for _, w in ipairs(words(get("COMING_SOON"))) do
		soon[w] = true
	end
	local reset = parseReq(get("RESET_LEVEL"))
	local st = T.tally("economy: sim PRICE_ / CAPS_ / REQ_ <id>, KEEP_ON_PRESTIGE, COMING_SOON, RESET_LEVEL == the catalog's stations", 6)
	for _, id in ipairs(CONTRACT_IDS) do
		local d = TC.Get(id)
		st:case(listEq(get("PRICE_" .. id), d.Price), "PRICE_" .. id)
		st:case(listEq(get("CAPS_" .. id), { d.TierCaps.Cottage, d.TierCaps.Villa, d.TierCaps.Manor, d.TierCaps.SkyCastle }), "CAPS_" .. id)
		st:case(reqText(parseReq(get("REQ_" .. id))) == reqText(d.Requires), "REQ_" .. id)
		st:case((keep[id] == true) == (d.KeepOnPrestige == true) and (soon[id] == true) == (d.ComingSoon == true) and (reset[id] or 0) == (d.ResetLevel or 0), "flags " .. id)
	end
	st:report()
	local eff = function(id, key)
		return effectList(TC.Get(id), key)
	end
	local tables = {
		{ "PLANT_FOOD_Press1", eff("Press1", "Food") }, { "GARDEN_LUCKY", eff("Garden", "Lucky") },
		{ "GARDEN_RADIUS", eff("Garden", "Radius") }, { "GARDEN_PILE_SECONDS", eff("Garden", "PileSeconds") },
		{ "LEGACY_MAGNET_RADIUS", TC.LegacyMagnet.Radius }, { "LEGACY_MAGNET_PILE_SECONDS", TC.LegacyMagnet.PileSeconds },
		{ "FEED_SHARE", eff("Kitchen", "FeedShare") }, { "TRAINING_SLOTS", eff("Gym", "Slots") },
		{ "VAULT_PILE_SECONDS", eff("Vault", "PileSeconds") }, { "VAULT_OFFLINE_PERCENT", eff("Vault", "OfflinePercent") },
		{ "VAULT_OFFLINE_HOURS", eff("Vault", "OfflineHours") }, { "FUSION_TOKEN_DISCOUNT", eff("FusionMachine", "TokenDiscount") },
		{ "LEGACY_PLANT_FOOD_Press1", TC.LegacyPlants.Press1 }, { "LEGACY_PLANT_FOOD_Press2", TC.LegacyPlants.Press2 },
		{ "LEGACY_PLANT_FOOD_Press3", TC.LegacyPlants.Press3 }, { "LEGACY_PLANT_FOOD_Press4", TC.LegacyPlants.Press4 },
		{ "HOUSE_HOME_LEVEL", { TC.HouseTiers[1].HomeLevel, TC.HouseTiers[2].HomeLevel, TC.HouseTiers[3].HomeLevel, TC.HouseTiers[4].HomeLevel } },
		{ "PRESTIGE_GEMS", { TC.Prestige.GemReward, TC.Prestige.GemRewardStep, TC.Prestige.GemRewardMin } },
		{ "PRESTIGE_GARDEN_SLOTS", { TC.Prestige.GardenSlotsBase, TC.Prestige.GardenSlotsPerStar, TC.Prestige.GardenSlotsMax } },
		{ "COINS", { TC.Coins.MealSeconds, TC.Coins.GrassFood, TC.Coins.LuckyMult, TC.Coins.BaseRadius, TC.Coins.BasePileSeconds } },
		{ "COINS_POOP", { TC.Coins.PoopMeals, TC.Coins.DropsPerPet } }, { "COINS_DROP_STAGES", TC.Coins.DropStages },
		{ "TRAINING", { TC.Training.MaxRank, TC.Training.CostBase, TC.Training.MinutesPerRank } },
		{ "PET_XP", { TC.PetXp.MaxLevel, TC.PetXp.Base, TC.PetXp.Exponent, TC.PetXp.Round } },
		{ "TIER_MULTIPLIER", { TC.TierMultiplier.Normal, TC.TierMultiplier.Golden, TC.TierMultiplier.Rainbow } },
		{ "BERRY", { TC.Berries.Share, TC.Berries.BasketMinutes } },
		{ "BERRY_LEGACY_FOOD", { TC.Berries.LegacyFood.Snack, TC.Berries.LegacyFood.Meal, TC.Berries.LegacyFood.Feast } },
	}
	local tt = T.tally("economy: the sim's effect / data tables == the catalog's", 6)
	for _, row in ipairs(tables) do
		tt:case(listEq(get(row[1]), row[2]), row[1] .. ": sim " .. show(sim[row[1]]) .. " vs " .. show(row[2]))
	end
	local scalars = {
		{ "OFFLINE_MIN_SECONDS", TC.OfflineMinSeconds }, { "PRESTIGE_HOME_LEVEL", TC.Prestige.HomeLevel },
		{ "PRESTIGE_MULTIPLIER", TC.Prestige.IncomeMultiplier }, { "PRESTIGE_PRICE_STEP", TC.Prestige.PriceStep },
		{ "FEED_BASE", TC.FeedBase }, { "BERRY_BASKET_MIN", TC.Berries.BasketMin }, { "SIGN_MAX", TC.SignRules.MaxSigns },
		{ "DECOR_CREDIT_MAX", 18 },
	}
	for _, row in ipairs(scalars) do
		tt:case(near(get(row[1]), row[2]), row[1] .. ": sim " .. tostring(sim[row[1]]) .. " vs " .. tostring(row[2]))
	end
	tt:report()
	-- pet data
	local scales, caps, twice = {}, {}, {}
	for i, r in ipairs(RARITY_ORDER) do
		scales[i] = Config.PetStats.RarityScale[r]
		caps[i] = PC.LevelCap(r)
		twice[i] = PC.MaxEvolution(r) == 2 and 1 or 0
	end
	T.check(listEq(get("RARITY_SCALE"), scales), "economy: sim RARITY_SCALE == Config.PetStats.RarityScale", show(sim.RARITY_SCALE) .. " vs " .. show(scales))
	T.check(listEq(get("LEVEL_CAPS"), caps), "economy: sim LEVEL_CAPS == PetCatalog.LevelCap by rarity", show(sim.LEVEL_CAPS) .. " vs " .. show(caps))
	T.check(listEq(get("ROLE_MULT"), { PC.RoleMult.Economy, PC.RoleMult.Combat }), "economy: sim ROLE_MULT == PetCatalog.RoleMult")
	T.check(listEq(get("EVOLUTION_LEVELS"), PC.EvolutionLevels) and listEq(get("EVOLUTION_BONUS"), { PC.EvolutionBonus[1], PC.EvolutionBonus[2] }),
		"economy: sim EVOLUTION_LEVELS / EVOLUTION_BONUS == PetCatalog ({20, 50}, {1.5, 1.875})")
	T.check(listEq(get("EVOLVE_TWICE"), twice), "economy: sim EVOLVE_TWICE == PetCatalog.MaxEvolution(rarity) == 2", show(sim.EVOLVE_TWICE) .. " vs " .. show(twice))
	T.check(PC.LevelBonus == 0.1, "economy: the sim's level factor (1 + 0.1 x (level - 1) x bonus) == PetCatalog.LevelBonus")
	local rollable, econ = {}, {}
	for i = 1, 6 do
		rollable[i], econ[i] = 0, 0
	end
	for _, def in ipairs(PC.Pets) do
		if not def.EventOnly then
			for i = 1, 6 do
				if RARITY_ORDER[i] == def.Rarity then
					rollable[i] = rollable[i] + 1
					if def.Role == "Economy" then
						econ[i] = econ[i] + 1
					end
				end
			end
		end
	end
	T.check(listEq(get("PET_ROLLABLE"), rollable) and listEq(get("PET_ECON_ROLLABLE"), econ),
		"economy: sim PET_ROLLABLE / PET_ECON_ROLLABLE == rollable (Economy) pets per rarity in PetCatalog", show(rollable) .. " / " .. show(econ))
	local oddsT = T.tally("economy: sim ODDS_<roulette> == Config.Roulettes odds (Common .. Mythic)")
	for _, roulette in ipairs(Config.Roulettes) do
		local got = {}
		for i = 1, 6 do
			got[i] = roulette.Odds[RARITY_ORDER[i]] or 0
		end
		oddsT:case(listEq(get("ODDS_" .. roulette.Id), got), roulette.Id .. ": sim " .. show(sim["ODDS_" .. roulette.Id]) .. " vs " .. show(got))
	end
	oddsT:report()
	local unchecked = {}
	for _, name in ipairs(order) do
		if not used[name] then
			unchecked[#unchecked + 1] = name
		end
	end
	T.check(#unchecked == 0, "economy: every constant of the sim's block is checked against the game", table.concat(unchecked, ", "))

	-- the sim's formulas == the catalog's
	local M = simModel(sim)
	local xpT = T.tally("economy: the sim's XpToNext / FeedXp / FeedBerries / TrainCost / TrainSeconds / BasketCap == the catalog's")
	for lv = 1, sim.PET_XP[1] do
		xpT:case(TC.XpToNext(lv) == M.xpToNext(lv), "XpToNext " .. lv)
		for ml = 0, 5 do
			xpT:case(TC.FeedXp(lv, ml) == M.feedXp(lv, ml), "FeedXp " .. lv .. " / " .. ml)
		end
		for ri, rarity in ipairs(RARITY_ORDER) do
			xpT:case(TC.FeedBerries(rarity, lv) == M.feedBerries(ri, lv), "FeedBerries " .. rarity .. " " .. lv)
		end
	end
	for ri, rarity in ipairs(RARITY_ORDER) do
		for rank = 1, sim.TRAINING[1] do
			xpT:case(TC.TrainCost(rarity, rank) == M.trainCost(ri, rank), "TrainCost " .. rarity .. " " .. rank)
		end
	end
	for rank = 1, sim.TRAINING[1] do
		xpT:case(TC.TrainSeconds(rank) == M.trainSeconds(rank), "TrainSeconds " .. rank)
	end
	for _, ips in ipairs({ 0, 0.5, 3.3, 17, 250.25, 9999 }) do
		xpT:case(TC.BasketCap(nil, ips) == M.basketCap(ips), "BasketCap " .. ips)
	end
	xpT:report()

	local rnd = makeRandom(20251019)
	local padT = T.tally("economy: AvailablePads (ids, levels, star prices, lock reasons) == the sim's on 300 pseudo-random homes", 3)
	local homeT = T.tally("economy: HomeLevelOf / FoodOf / LuckyChance / GardenSlots / PileSeconds / ScoopRadius / IncomePerSecond / OfflineEarnings / StationsAfterPrestige == the sim's on 300 homes", 3)
	local tierName = { "Normal", "Golden", "Rainbow" }
	local tierMult = { 1, 1.5, 2.5 }
	for trial = 1, 300 do
		local stars = ({ 0, 0, 0, 1, 2, 3, 5 })[rnd(7) + 1]
		local legacyPrices = stars > 0 and rnd(10) < 3
		local legacySlots = rnd(3) == 0 and (rnd(8) + 1) or nil
		local sim_st, stations = {}, {}
		for _, id in ipairs(CONTRACT_IDS) do
			if rnd(10) < 7 then
				local lv = rnd(#sim["PRICE_" .. id] + 1)
				stations[id] = lv
				sim_st[id] = lv
			end
		end
		local credit = rnd(3) == 0 and (rnd(18) + 1) or nil
		local magnet = rnd(3) == 0 and (rnd(5) + 1) or nil
		sim_st.DecorCredit, sim_st.LegacyMagnet = credit, magnet
		local h = home(stations, stars, { LegacyPrices = legacyPrices or nil, LegacySlots = legacySlots, DecorCredit = credit,
			LegacyMagnet = magnet, LegacyMagnetStar = magnet and stars or nil })
		local want = M.pads(sim_st, stars, legacyPrices)
		local got = {}
		for _, p in ipairs(TC.AvailablePads(h)) do
			if p.StationId ~= "Prestige" then
				got[#got + 1] = p
			end
		end
		local same = #want == #got
		if same then
			for i = 1, #want do
				local w, g = want[i], got[i]
				if w[1] ~= g.StationId or w[2] ~= g.NextLevel or w[3] ~= g.Price or w[4] ~= g.Locked then
					same = false
				end
			end
		end
		padT:case(same, "home " .. trial)
		-- pets sorted by power (the catalog reads entries in slot order)
		local pets = {}
		for i = 1, rnd(14) do
			local ri = rnd(7) + 1
			local econ_ = rnd(2) == 0
			local level = rnd(100) + 1
			local ti = ({ 1, 1, 2, 3 })[rnd(4) + 1]
			local evo = ({ 0, 0, 1, 2 })[rnd(4) + 1]
			pets[i] = { ri = ri, econ = econ_, level = level, ti = ti, evo = evo, power = M.power(ri, econ_, level, tierMult[ti], evo) }
		end
		table.sort(pets, function(a, b)
			if a.power ~= b.power then
				return a.power > b.power
			end
			return a.ri < b.ri
		end)
		local entries, powers = {}, {}
		for i, p in ipairs(pets) do
			entries[i] = { Def = { Rarity = RARITY_ORDER[p.ri], Role = p.econ and "Economy" or "Combat" }, Level = p.level, Tier = tierName[p.ti], Stage = p.evo }
			powers[i] = p.power
		end
		local incWant = M.income(sim_st, powers, stars, legacySlots)
		local cleanSt = {}
		for k, v in pairs(stations) do
			if v > 0 then
				cleanSt[k] = v
			end
		end
		local after = TC.StationsAfterPrestige(stations)
		local checks = {
			{ "HomeLevelOf", TC.HomeLevelOf(h), M.homeLevel(sim_st) },
			{ "FoodOf", TC.FoodOf(h), M.food(sim_st) }, { "LuckyChance", TC.LuckyChance(h), M.lucky(sim_st) },
			{ "GardenSlots", TC.GardenSlots(h), M.slots(stars, legacySlots, sim_st.Garden or 0) }, { "PileSeconds", TC.PileSeconds(h), M.pile(sim_st) },
			{ "ScoopRadius", TC.ScoopRadius(h), M.radius(sim_st) }, { "IncomePerSecond", (TC.IncomePerSecond(h, entries)), incWant },
			{ "OfflineEarnings", (TC.OfflineEarnings(h, 5000, 37.5)), M.offline(sim_st, 5000, 37.5) },
		}
		local okAll, why = true, ""
		for _, ck in ipairs(checks) do
			if not near(ck[2], ck[3], 1e-9) then
				okAll = false
				why = why .. ck[1] .. " " .. tostring(ck[2]) .. " vs " .. tostring(ck[3]) .. "; "
			end
		end
		if not setEq(after, M.afterPrestige(cleanSt)) then
			okAll = false
			why = why .. "StationsAfterPrestige; "
		end
		homeT:case(okAll, "home " .. trial .. ": " .. why)
	end
	padT:report()
	homeT:report()
end

S.p2_economy = guarded("p2_economy", function()
	local Config = K.config()
	local PC = K.M["shared/PetCatalog"]
	local before = #game:GetDescendants()
	local TC, err = loadCatalog()
	if not T.check(TC ~= nil, "economy: shared/TycoonCatalog loads", err) then
		return
	end
	local again = loadCatalog()
	T.check(again == TC, "economy: requiring it twice gives the same table")
	T.eq(TC.Version, 5, "economy: TycoonCatalog.Version 5 (Phase 5: one Berry Farm, berries, roaming pets)")
	apiChecks(TC)
	validateChecks(TC)
	padChecks(TC)
	signChecks(TC)
	foldChecks(TC)
	careChecks(TC, PC)
	if type(PC) == "table" and type(Config) == "table" then
		coinChecks(TC, PC, Config)
		mirrorChecks(TC, PC, Config)
		simChecks(TC, PC, Config)
	else
		T.fail("economy: PetCatalog and Config are loaded (load_modules)")
	end
	junkChecks(TC)
	layoutChecks(TC)
	T.eq(#game:GetDescendants(), before, "economy: the catalog is pure (no Instances created)")
	K.flushErrors("p2_economy")
end)

return S
