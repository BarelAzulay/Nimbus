-- smoke_p4_economy.lua: the Phase 4 coin economy catalog (ARCHITECTURE_V3.md "Phase 4 build contract" sections 3.1-3.5,
-- 3.7, 3.12, 5.4 and 8.1; shared/TycoonCatalog.lua). It replaces smoke_p2_economy.lua and keeps its scenario name so
-- the anchors of tools/smoke.py hold. Loaded by tools/smoke.py in the SERVER world as a pure content scenario:
--   p2_economy   TycoonCatalog loads (twice = the same table, no Instances created) with the Phase 4 API and data;
--                the 18 contract station ids with the contract's names, kinds, caps (sums 29 / 51 / 78 / 91), tree,
--                prices and effects (table 3.1), their Phase 3 slots unchanged; a fresh home shows ONE pad (the free
--                Pet Garden) and the re-rooted tree ("Needs the Villa" for Cloud Melons, "Unlocks at Prestige 1" for
--                the Fusion Machine, "Reach Home Level 10", the prestige pad only with the Sky Castle); star prices
--                (PriceAt = PriceFor x 1.5 ^ stars, LegacyPrices exempt, pads + CheckPurchase agree); prestige keeps
--                the decor and the Garden at level 1; rainbow coins: FoodOf, PetPower (Economy / Combat == 1.6,
--                rarity, level to 100, Golden / Rainbow, EVOLVE x1.25 / x1.5 from the STORED stage, every entry
--                shape), IncomePerSecond (Lucky expected value, stars, resting keys above the open count, no Collector
--                condition), GardenSlots (3 / 4 at one star / 12 max / LegacySlots), LuckyChance, PileSeconds and
--                ScoopRadius by Magnet + Vault, CoinPoint, HeapStage, OfflineEarnings; the Food Machine (FeedShare,
--                FeedXp, FeedPrice, the contract's example prices and roads); the Training Place (TrainCost,
--                TrainSeconds, TrainingSlots); the XP curve to level 100; the PetCatalog mirrors (a copy loaded without
--                PetCatalog gives the same PetPower); the Phase 3 compat aliases still work; junk never errors;
--                Validate() passes and catches every per-kind rule it owns; the layout (12 garden places on the 3 x 4
--                grid, walks, coin points on the walks and off pads, the Welcome-back pile, no Conveyor, every pad
--                reachable); and the parity with the constants block of tools/sim_tycoon.py (every constant checked,
--                >= 60 of them, plus the sim's formulas on 300 pseudo-random homes: pads with star prices, food,
--                slots, piles, radius, income, offline, feeding, training).
-- tools/sim_tycoon.py and src/shared/TycoonCatalog.lua are read from the working directory (smoke.py / run_checks.sh
-- run from the repo root). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local abs, floor, huge, min, max = math.abs, math.floor, math.huge, math.min, math.max

local S = {}

local TIER_IDS = { "Cottage", "Villa", "Manor", "SkyCastle" }
local CONTRACT_IDS = {
	"Press1", "Press2", "Press3", "Press4", "Collector", "Garden", "Kitchen", "Gym", "Vault", "House",
	"FusionMachine", "ArenaGate", "DecorLamps", "DecorFence", "DecorFlowers", "DecorFountain", "DecorBanners", "DecorPodium",
}
local KINDS = { "Plant", "Magnet", "Garden", "FoodMachine", "Training", "Vault", "House", "Fusion", "Arena", "Decor" }
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local PLANTS = { "Press1", "Press2", "Press3", "Press4" }

-- ARCHITECTURE_V3.md "Phase 4 build contract" table 3.1 (Caps = Cottage, Villa, Manor, Sky Castle)
local CONTRACT = {
	Garden = { Name = "Pet Garden", Kind = "Garden", Max = 8, Caps = { 2, 4, 6, 8 }, Req = {},
		Price = { 0, 12000, 30000, 110000, 290000, 600000, 1200000, 2400000 },
		Eff = { Lucky = { 0, 0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.15 } } },
	Press1 = { Name = "Berry Bush", Kind = "Plant", Max = 10, Caps = { 6, 8, 9, 10 }, Req = { Garden = 1 },
		Price = { 15, 55, 130, 360, 1200, 3500, 9000, 20000, 100000, 270000 },
		Eff = { Food = { 7, 9, 12, 16, 21, 27, 35, 45, 59, 76 } } },
	Press2 = { Name = "Carrot Patch", Kind = "Plant", Max = 10, Caps = { 6, 8, 9, 10 }, Req = { Press1 = 2 },
		Price = { 420, 1100, 2500, 6000, 15000, 22000, 38000, 120000, 260000, 680000 },
		Eff = { Food = { 19, 24, 32, 42, 53, 69, 91, 118, 153, 199 } } },
	Press3 = { Name = "Cloud Melons", Kind = "Plant", Max = 10, Caps = { 0, 6, 8, 10 }, Req = { Press2 = 3, House = "Villa" },
		Price = { 18000, 25000, 36000, 88000, 130000, 180000, 290000, 410000, 1100000, 1800000 },
		Eff = { Food = { 49, 63, 82, 107, 140, 180, 235, 302, 396, 518 } } },
	Press4 = { Name = "Starfruit Tree", Kind = "Plant", Max = 10, Caps = { 0, 0, 8, 10 }, Req = { Press3 = 3, House = "Manor" },
		Price = { 160000, 300000, 370000, 490000, 630000, 820000, 1100000, 1400000, 2200000, 3200000 },
		Eff = { Food = { 127, 164, 215, 278, 360, 468, 612, 792, 1030, 1339 } } },
	Collector = { Name = "Coin Magnet", Kind = "Magnet", Max = 5, Caps = { 2, 3, 4, 5 }, Req = { Press1 = 1 },
		Price = { 90, 6000, 45000, 410000, 1400000 },
		Eff = { Radius = { 9, 12, 16, 20, 26 }, PileSeconds = { 300, 360, 420, 480, 600 } } },
	Kitchen = { Name = "Food Machine", Kind = "FoodMachine", Max = 5, Caps = { 1, 2, 4, 5 }, Req = { Press1 = 1 },
		Price = { 240, 35000, 320000, 680000, 1900000 },
		Eff = { FeedShare = { 0.25, 0.30, 0.35, 0.42, 0.50 } } },
	Gym = { Name = "Training Place", Kind = "Training", Max = 5, Caps = { 1, 2, 4, 5 }, Req = { Kitchen = 1 },
		Price = { 3000, 110000, 420000, 920000, 2200000 },
		Eff = { Slots = { 1, 2, 3, 4, 5 } } },
	Vault = { Name = "Vault", Kind = "Vault", Max = 5, Caps = { 1, 2, 4, 5 }, Req = { Press2 = 2 },
		Price = { 9000, 85000, 370000, 820000, 2000000 },
		Eff = { PileSeconds = { 300, 600, 900, 1200, 1800 }, OfflinePercent = { 0.1, 0.15, 0.2, 0.25, 0.3 }, OfflineHours = { 1, 2, 3, 4, 4 } } },
	House = { Name = "House", Kind = "House", Max = 4, Caps = { 4, 4, 4, 4 }, Req = { Collector = 1 },
		Price = { 180, 24000, 200000, 880000 } },
	FusionMachine = { Name = "Fusion Machine", Kind = "Fusion", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Kitchen = 1, Prestige = 1 },
		Price = { 25000, 340000, 1400000 }, Eff = { TokenDiscount = { 0, 0.1, 0.2 } } },
	ArenaGate = { Name = "Arena Gate", Kind = "Arena", Max = 1, Caps = { 1, 1, 1, 1 }, Req = { Gym = 1 }, Price = { 260000 } },
	DecorLamps = { Name = "Lanterns", Kind = "Decor", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Collector = 1 }, Price = { 1800, 27000, 360000 } },
	DecorFence = { Name = "Garden Fence", Kind = "Decor", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Press2 = 2 }, Price = { 7000, 48000, 490000 } },
	DecorFlowers = { Name = "Flower Beds", Kind = "Decor", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Garden = 1 }, Price = { 2700, 36000, 410000 } },
	DecorFountain = { Name = "Fountain", Kind = "Decor", Max = 3, Caps = { 0, 1, 2, 3 }, Req = { Kitchen = 1, House = "Villa" }, Price = { 45000, 490000, 1500000 } },
	DecorBanners = { Name = "Banners", Kind = "Decor", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Vault = 1 }, Price = { 12000, 110000, 650000 } },
	DecorPodium = { Name = "Pet Podium", Kind = "Decor", Max = 3, Caps = { 1, 2, 3, 3 }, Req = { Garden = 1 }, Price = { 9000, 95000, 580000 } },
}

-- the Phase 3 slots (unchanged by Phase 4): x, z, yaw, footprint w / h / d, pad x / z (0 = the plot size)
local P3_SLOTS = {
	Press1 = { -26.5, -14, -90, 7, 10, 7, -19, -14 },
	Press2 = { -26.5, -4.5, -90, 7, 11, 7, -19, -4.5 },
	Press3 = { -26.5, 5, -90, 7, 12, 7, -19, 5 },
	Press4 = { -26.5, 14.5, -90, 7, 13, 7, -19, 14.5 },
	Collector = { -27.5, -26.5, -90, 9, 8, 13, -17, -26.5 },
	Garden = { 24, -1, 90, 22, 4, 20, 10, -1 },
	Kitchen = { 25, 24, 0, 16, 10, 10, 19.5, 14.5 },
	Gym = { -24, 29, 0, 18, 10, 9, -19, 22.5 },
	Vault = { -10.5, -27, 180, 7, 9, 8, -10.5, -19 },
	House = { 0, 25, 0, 26, 30, 18, 0, 12 },
	FusionMachine = { 11, -25, 180, 10, 12, 10, 11, -16 },
	ArenaGate = { 32, 14.5, 90, 7, 12, 4, 27, 14.5 },
	DecorLamps = { 0, -21, 0, 9, 7, 26, -8, -12 },
	DecorFence = { 0, 0, 0, 0, 4, 0, 8, -10 },
	DecorFlowers = { -25, -34.3, 180, 18, 2, 2.2, -12.5, -33.3 },
	DecorFountain = { 0, -1, 0, 9, 8, 9, -7, -1 },
	DecorBanners = { 25, -34.3, 180, 18, 6, 2.2, 12.5, -33.3 },
	DecorPodium = { 24, -26, 180, 8, 6, 8, 24, -17.5 },
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

-- every station of a tier bought up to that tier's caps (no prestige-only stations unless the stars allow them)
local function builtTo(TC, tierIndex, prestige)
	local st = {}
	local tierId = TIER_IDS[tierIndex]
	for _, def in ipairs(TC.Stations) do
		if not def.ComingSoon and not (def.Requires.Prestige and def.Requires.Prestige > (prestige or 0)) then
			st[def.Id] = def.TierCaps[tierId]
		end
	end
	st.House = tierIndex
	return home(st, prestige)
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

-- "Press2=3 House=Villa" -> { Press2 = 3, House = "Villa" }
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

-- the sim's model (tools/sim_tycoon.py) written from its constants alone
local function simModel(sim, order)
	local M = {}
	local tiers = { Cottage = 1, Villa = 2, Manor = 3, SkyCastle = 4 }
	local tierNames = { "Cottage", "Villa", "Manor", "Sky Castle" }
	local coins = sim.COINS or {}
	local meal, grass, luckyMult, baseRadius, basePile = coins[1], coins[2], coins[3], coins[4], coins[5]
	local slotsT = sim.PRESTIGE_GARDEN_SLOTS or {}
	local keep, soon = {}, {}
	for _, w in ipairs(words(sim.KEEP_ON_PRESTIGE)) do
		keep[w] = true
	end
	for _, w in ipairs(words(sim.COMING_SOON)) do
		soon[w] = true
	end
	local reset = parseReq(sim.RESET_LEVEL)
	M.order = order
	function M.food(st)
		if (st.Garden or 0) < 1 then
			return 0
		end
		local total = grass
		for _, id in ipairs(PLANTS) do
			local lv = st[id] or 0
			if lv > 0 then
				total = total + sim["PLANT_FOOD_" .. id][lv]
			end
		end
		return total
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
		local c, v = st.Collector or 0, st.Vault or 0
		local s = c > 0 and sim.MAGNET_PILE_SECONDS[c] or basePile
		return s + (v > 0 and sim.VAULT_PILE_SECONDS[v] or 0)
	end
	function M.radius(st)
		local c = st.Collector or 0
		return c > 0 and sim.MAGNET_RADIUS[c] or baseRadius
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
		return n
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
		local boost = stage >= 1 and sim.EVOLUTION_BOOST[stage] or 1
		local lv = max(1, min(level, sim.PET_XP[1]))
		return sim.RARITY_SCALE[ri] * (1 + 0.1 * (lv - 1)) * tierMult * (econ and sim.ROLE_MULT[1] or sim.ROLE_MULT[2]) * boost
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
	function M.feedPrice(ri, level)
		local need = M.xpToNext(level)
		if need == huge then
			return nil
		end
		return floor(need * sim.RARITY_SCALE[ri] * sim.FEED_BASE + 0.5)
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
		"StationsAfterPrestige", "CanPrestige", "FoodOf", "PetPower", "GardenSlots", "IncomePerSecond", "LuckyChance",
		"ScoopRadius", "PileSeconds", "CoinPoint", "OfflineEarnings", "FeedXp", "FeedPrice", "TrainCost", "TrainSeconds",
		"TrainingSlots", "XpToNext", "Validate",
	}
	local missing = {}
	for _, name in ipairs(fns) do
		if type(TC[name]) ~= "function" then
			missing[#missing + 1] = name
		end
	end
	T.check(#missing == 0, "economy: TycoonCatalog has the Phase 4 API (contract 5.4: FoodOf, PetPower, GardenSlots, IncomePerSecond, LuckyChance, ScoopRadius, PileSeconds, CoinPoint, OfflineEarnings, FeedXp, FeedPrice, TrainCost, TrainSeconds, TrainingSlots, StarPriceMultiplier, PriceAt, XpToNext, Validate, ...)", table.concat(missing, ", "))
	local fields = { "Stations", "ById", "Order", "HouseTiers", "Prestige", "Coins", "FeedShare", "Training", "Foods", "Fusion", "PetXp", "Layout", "Kinds" }
	missing = {}
	for _, name in ipairs(fields) do
		if type(TC[name]) ~= "table" then
			missing[#missing + 1] = name
		end
	end
	T.check(#missing == 0 and type(TC.FeedBase) == "number", "economy: ...and the contract data (Stations, HouseTiers, Prestige, Coins, FeedShare, FeedBase, Training, Foods, Fusion, PetXp, Layout, Kinds)", table.concat(missing, ", "))
	T.check(listEq(TC.Kinds, KINDS), "economy: Kinds = Plant, Magnet, Garden, FoodMachine, Training, Vault, House, Fusion, Arena, Decor", show(TC.Kinds))

	-- the 18 contract stations with the contract fields, names, kinds, caps, tree, prices and effects
	local tally = T.tally("economy: the 18 contract stations exist with Id, Name, Kind, MaxLevel, Requires, Price, Effects, Slot (CFrame + Footprint + Pad)")
	for _, id in ipairs(CONTRACT_IDS) do
		local def = TC.Get(id)
		local ok = type(def) == "table" and def.Id == id and type(def.Name) == "string" and type(def.Kind) == "string"
			and type(def.MaxLevel) == "number" and type(def.Requires) == "table" and type(def.Price) == "table"
			and type(def.Effects) == "table" and type(def.Slot) == "table" and typeof(def.Slot.CFrame) == "CFrame"
			and typeof(def.Slot.Footprint) == "Vector3" and typeof(def.Slot.Pad) == "CFrame"
		tally:case(ok, id)
	end
	tally:report()
	T.eq(#TC.Stations, #CONTRACT_IDS, "economy: ...and no other station")
	local orderOk = true
	for i, id in ipairs(CONTRACT_IDS) do
		orderOk = orderOk and TC.Stations[i] and TC.Stations[i].Id == id and TC.Order[i] == id and TC.ById[id] == TC.Stations[i]
	end
	T.check(orderOk, "economy: the stations keep the Phase 3 display order (Order / ById agree)")
	T.check(TC.Get("Nope") == nil and TC.PriceFor("Nope", 1) == nil and TC.PriceAt("Nope", 1, home()) == nil, "economy: unknown ids give nil")

	local names = T.tally("economy: names and kinds follow contract table 3.1 (Berry Bush / Carrot Patch / Cloud Melons / Starfruit Tree = Plant, Coin Magnet = Magnet, Food Machine = FoodMachine, Training Place = Training, ...)")
	local capsT = T.tally("economy: MaxLevel and tier caps unchanged (Cottage / Villa / Manor / Sky Castle per table 3.1)")
	local reqT = T.tally("economy: the re-rooted tree (Requires) follows table 3.1")
	local priceT = T.tally("economy: prices follow table 3.1 (the Pet Garden is free)")
	local effT = T.tally("economy: effects follow table 3.1 (Food, Lucky, Radius / PileSeconds, FeedShare, Slots, Vault, TokenDiscount)")
	for _, id in ipairs(CONTRACT_IDS) do
		local def, want = TC.Get(id), CONTRACT[id]
		if def then
			names:case(def.Name == want.Name and def.Kind == want.Kind, id .. ": " .. tostring(def.Name) .. " / " .. tostring(def.Kind))
			local caps = {}
			for i, t in ipairs(TIER_IDS) do
				caps[i] = def.TierCaps[t]
			end
			capsT:case(def.MaxLevel == want.Max and listEq(caps, want.Caps), id .. ": " .. tostring(def.MaxLevel) .. " " .. show(caps))
			reqT:case(setEq(def.Requires, want.Req), id .. ": '" .. reqText(def.Requires) .. "' vs '" .. reqText(want.Req) .. "'")
			local prices = {}
			for lv = 1, def.MaxLevel do
				prices[lv] = def.Price[lv]
			end
			priceT:case(listEq(prices, want.Price), id .. ": " .. show(prices))
			for key, list in pairs(want.Eff or {}) do
				effT:case(listEq(effectList(def, key), list), id .. "." .. key .. ": " .. show(effectList(def, key)))
			end
		end
	end
	names:report()
	capsT:report()
	reqT:report()
	priceT:report()
	effT:report()
	T.check(TC.Get("Garden").ResetLevel == 1, "economy: the Garden has ResetLevel = 1 (Prestige keeps it built: the coins never stop)")
	-- tier-cap sums (without the prestige-gated Fusion Machine) stay 29 / 51 / 78 / 91
	local sums = {}
	for i, t in ipairs(TIER_IDS) do
		local total = 0
		for _, def in ipairs(TC.Stations) do
			if not (def.Requires.Prestige and def.Requires.Prestige > 0) then
				total = total + (def.TierCaps[t] or 0)
			end
		end
		sums[i] = total
	end
	T.check(listEq(sums, { 29, 51, 78, 91 }), "economy: the tier-cap sums stay 29 / 51 / 78 / 91 (Home Level, house tiers and prestige unchanged)", show(sums))

	-- house tiers + prestige + coins + food machine + training data per the contract
	local tiers = TC.HouseTiers
	local okTiers = #tiers == 4
	local wantHL = { 0, 10, 20, 30 }
	for i = 1, 4 do
		okTiers = okTiers and tiers[i] and tiers[i].Id == TIER_IDS[i] and tiers[i].HomeLevel == wantHL[i]
	end
	T.check(okTiers, "economy: HouseTiers = Cottage (start), Villa (Home Level 10), Manor (20), Sky Castle (30)")
	local p = TC.Prestige
	T.check(p.HomeLevel == 40 and p.House == "SkyCastle" and p.IncomeMultiplier == 1.25 and p.GemReward == 100 and p.GemRewardStep == 10
		and p.GemRewardMin == 25 and p.FusionUnlock == 1 and p.TeamSlotUnlock == 1,
		"economy: Prestige = { HomeLevel 40, House SkyCastle, IncomeMultiplier 1.25, Gems 100 - 10 per star (floor 25), FusionUnlock 1, TeamSlotUnlock 1 } (unchanged)")
	T.check(p.GardenSlotsBase == 3 and p.GardenSlotsPerStar == 1 and p.GardenSlotsMax == 12 and p.PriceStep == 0.5,
		"economy: Prestige.GardenSlotsBase 3, GardenSlotsPerStar 1, GardenSlotsMax 12, PriceStep 0.5 (contract 3.1)")
	local c = TC.Coins
	T.check(c.MealSeconds == 8 and c.GrassFood == 12 and c.LuckyMult == 5 and c.BaseRadius == 6 and c.BasePileSeconds == 240
		and listEq(c.HeapStages, { 1, 3, 6, 12, 24 }),
		"economy: Coins = { MealSeconds 8, GrassFood 12, LuckyMult 5, BaseRadius 6, BasePileSeconds 240, HeapStages {1, 3, 6, 12, 24} }")
	T.check(listEq(TC.FeedShare, { 0.25, 0.30, 0.35, 0.42, 0.50 }) and listEq(TC.FeedShare, effectList(TC.Get("Kitchen"), "FeedShare")) and TC.FeedBase == 2.0,
		"economy: FeedShare .25 / .30 / .35 / .42 / .50 (= the Food Machine's Effects) and FeedBase 2.0")
	local tr = TC.Training
	T.check(tr.MaxRank == 10 and tr.CostBase == 300 and tr.MinutesPerRank == 1, "economy: Training = { MaxRank 10, CostBase 300, MinutesPerRank 1 }")
	local foodsOk = true
	for _, id in ipairs({ "Snack", "Meal", "Feast" }) do
		local f = TC.FoodsById and TC.FoodsById[id]
		foodsOk = foodsOk and type(f) == "table" and type(f.Price) == "number" and type(f.Xp) == "number"
	end
	T.check(foodsOk and TC.FoodsById.Snack.Xp == 25 and TC.FoodsById.Meal.Xp == 150 and TC.FoodsById.Feast.Xp == 800,
		"economy: the leftover Foods stay as data (Snack 25 / Meal 150 / Feast 800 XP; fed first and free by the Food Machine)")
	T.check(TC.Foods.Snack == TC.FoodsById.Snack and TC.Stations.Press1 == TC.Get("Press1") and TC.HouseTiers.Villa == TC.HouseTiers[2]
		and TC.Fusion.Rare and TC.Fusion.Rare.Golden == TC.Fusion.Upgrade.Rare.Golden,
		"economy: Stations / HouseTiers / Foods / Fusion also answer ids (Stations.Press1, Foods.Snack...) without extra pairs entries")
	local n = 0
	for _ in pairs(TC.Foods) do
		n = n + 1
	end
	T.eq(n, #TC.Foods, "economy: ...pairs(Foods) still sees each food once")
	T.eq(TC.MaxPetLevel, TC.PetXp.MaxLevel, "economy: MaxPetLevel = PetXp.MaxLevel (DataService.AddPetXp reads it)")
	T.eq(TC.PetXp.MaxLevel, 100, "economy: pets level up to 100 (the player's later rule)")
end

local function padChecks(TC)
	-- a fresh home: only the free Pet Garden pad
	local fresh = TC.AvailablePads(home())
	local g = padOf(fresh, "Garden")
	T.check(#fresh == 1 and g ~= nil and g.Price == 0 and g.BasePrice == 0 and g.Locked == nil and g.NextLevel == 1 and g.LevelText == "Build"
		and g.Name == "Pet Garden" and g.Kind == "Garden",
		"economy: a freshly claimed home shows exactly ONE pad: the Pet Garden, free and open ('Build')", #fresh .. " pads: " .. idList(padIds(fresh)))
	T.eq(TC.PriceFor("Garden", 1), 0, "economy: PriceFor(Garden, 1) = 0 (free)")
	local okFree, priceFree = TC.CheckPurchase(home(), "Garden")
	T.check(okFree == true and priceFree == 0, "economy: CheckPurchase(fresh home, Garden) = ok, 0")
	local okP1, _, why = TC.CheckPurchase(home(), "Press1")
	T.check(okP1 == false and why == "Not unlocked yet", "economy: ...and nothing else can be bought on a fresh home", tostring(why))

	-- the re-rooted tree, step by step
	local function step(stations, prestige, want, label)
		local pads = TC.AvailablePads(home(stations, prestige))
		local got = padIds(pads)
		T.check(setEq(got, want), "economy: tree: " .. label, "pads: " .. idList(got))
		return pads
	end
	local s1 = step({ Garden = 1 }, 0, { Garden = true, Press1 = true, DecorFlowers = true, DecorPodium = true },
		"the Garden opens the Berry Bush, the Flower Beds and the Pet Podium")
	local b = padOf(s1, "Press1")
	T.check(b and b.Price == 15 and b.Locked == nil and b.Title == "Berry Bush" and b.LevelText == "Build", "economy: ...the Berry Bush pad costs $15 (the first paid buy)")
	local g2 = padOf(s1, "Garden")
	T.check(g2 and g2.NextLevel == 2 and g2.Price == 12000 and g2.LevelText == "Lv 1 -> 2" and g2.Locked == nil, "economy: ...and the Garden stays on as an upgrade pad (Lv 1 -> 2, $12,000: more Lucky coins)")
	step({ Garden = 1, Press1 = 1 }, 0, { Garden = true, Press1 = true, Collector = true, Kitchen = true, DecorFlowers = true, DecorPodium = true },
		"the Berry Bush opens the Coin Magnet and the Food Machine")
	local s3 = step({ Garden = 1, Press1 = 1, Collector = 1 }, 0,
		{ Garden = true, Press1 = true, Collector = true, Kitchen = true, House = true, DecorLamps = true, DecorFlowers = true, DecorPodium = true },
		"the Coin Magnet opens the House and the Lanterns")
	local house = padOf(s3, "House")
	T.check(house and house.Price == 180 and house.Title == "Cottage" and house.Locked == nil, "economy: ...the Cottage costs $180")
	local s4 = step({ Garden = 1, Press1 = 1, Kitchen = 1 }, 0,
		{ Garden = true, Press1 = true, Collector = true, Kitchen = true, Gym = true, FusionMachine = true, DecorFountain = true, DecorFlowers = true, DecorPodium = true },
		"the Food Machine opens the Training Place, the Fusion Machine (locked) and the Fountain (locked)")
	local fm = padOf(s4, "FusionMachine")
	T.check(fm and fm.Locked == "Unlocks at Prestige 1", "economy: the Fusion Machine pad says 'Unlocks at Prestige 1' before the first prestige", fm and tostring(fm.Locked))
	local fountain = padOf(s4, "DecorFountain")
	T.check(fountain and fountain.Locked == "Needs the Villa", "economy: the Fountain says 'Needs the Villa' in a Cottage", fountain and tostring(fountain.Locked))
	local gym = padOf(s4, "Gym")
	T.check(gym and gym.Price == 3000 and gym.Title == "Training Place" and gym.Locked == nil, "economy: the Training Place pad costs $3,000 after the Food Machine")
	fm = padOf(TC.AvailablePads(home({ Garden = 1, Press1 = 1, Kitchen = 1 }, 1)), "FusionMachine")
	T.check(fm and fm.Locked == nil, "economy: ...and the Fusion Machine opens with 1 prestige star")
	local s5 = TC.AvailablePads(home({ Garden = 1, Press1 = 2, Press2 = 2, Collector = 1 }))
	T.check(padOf(s5, "Press2") and padOf(s5, "Vault") and padOf(s5, "DecorFence") and padOf(s5, "Vault").Price == 9000,
		"economy: the Berry Bush at level 2 opens the Carrot Patch; the Carrot Patch at 2 opens the Vault ($9,000) and the Garden Fence")
	T.check(padOf(TC.AvailablePads(home({ Garden = 1, Press1 = 2, Press2 = 2, Vault = 1 })), "DecorBanners") ~= nil, "economy: the Vault opens the Banners")
	local ag = padOf(TC.AvailablePads(home({ Garden = 1, Press1 = 1, Kitchen = 1, Gym = 1 })), "ArenaGate")
	T.check(ag and ag.Locked == nil and ag.Price == 260000, "economy: the Training Place opens the Arena Gate ($260,000)", ag and tostring(ag.Locked))
	-- Cloud Melons need the Villa, the Starfruit Tree the Manor
	local h3 = home({ Garden = 1, Press1 = 6, Press2 = 3, Collector = 2, House = 1 })
	local p3 = padOf(TC.AvailablePads(h3), "Press3")
	T.check(p3 and p3.Locked == "Needs the Villa" and p3.Title == "Cloud Melons", "economy: Cloud Melons show 'Needs the Villa' in a Cottage", p3 and tostring(p3.Locked))
	local villa = builtTo(TC, 2, 0)
	local p3v = padOf(TC.AvailablePads(villa), "Press3")
	local p4v = padOf(TC.AvailablePads(villa), "Press4")
	T.check(p3v == nil or p3v.Locked ~= "Needs the Villa", "economy: ...and open in the Villa")
	T.check(p4v and p4v.Locked == "Needs the Manor" and p4v.Title == "Starfruit Tree", "economy: the Starfruit Tree shows 'Needs the Manor' in the Villa", p4v and tostring(p4v.Locked))
	-- the House waits for the Home Level
	local hh = home({ Garden = 1, Press1 = 2, Collector = 1, House = 1 })
	local hp = padOf(TC.AvailablePads(hh), "House")
	T.check(hp and hp.Locked == "Reach Home Level 10" and hp.Title == "Villa" and hp.Price == TC.PriceFor("House", 2),
		"economy: the House pad shows 'Reach Home Level 10' for the Villa until Home Level 10", hp and tostring(hp.Locked))
	-- tier caps
	local capped = padOf(TC.AvailablePads(h3), "Press1")
	T.check(capped and capped.Locked == "Needs the Villa" and capped.NextLevel == 7, "economy: the Berry Bush at its Cottage cap shows 'Needs the Villa'", capped and tostring(capped.Locked))
	local p1v = padOf(TC.AvailablePads(villa), "Press1")
	T.check(p1v and p1v.Locked == "Needs the Manor", "economy: ...and 'Needs the Manor' at the Villa cap", p1v and tostring(p1v.Locked))
	-- prestige pad only with the Sky Castle; locked below Home Level 40
	local manor = builtTo(TC, 3, 0)
	T.check(padOf(TC.AvailablePads(manor), "Prestige") == nil, "economy: no prestige pad before the Sky Castle")
	local castleLow = home({ Garden = 1, Press1 = 1, Collector = 1, House = 4 })
	local pp = padOf(TC.AvailablePads(castleLow), "Prestige")
	T.check(pp and pp.Prestige == true and pp.Locked == "Reach Home Level 40" and pp.Price == 0, "economy: with the Sky Castle the prestige pad shows 'Reach Home Level 40' until Home Level 40", pp and tostring(pp.Locked))
	local castle = builtTo(TC, 4, 0)
	T.check(TC.HomeLevelOf(castle) >= 40, "economy: a fully built Sky Castle home reaches Home Level 40 (" .. TC.HomeLevelOf(castle) .. ")")
	pp = padOf(TC.AvailablePads(castle), "Prestige")
	T.check(pp and pp.Locked == nil and pp.NextLevel == 1 and TC.CanPrestige(castle) == true, "economy: ...its prestige pad is open and CanPrestige agrees")
	local def = TC.Get("Prestige")
	T.check(type(def) == "table" and def.Kind == "Prestige" and typeof(def.Slot.Pad) == "CFrame", "economy: Get('Prestige') gives the prestige pad's slot (Kind Prestige)")
	-- maxed stations have no pad
	T.check(padOf(TC.AvailablePads(home({ Garden = 8, Press1 = 10, Collector = 1, House = 4 })), "Press1") == nil, "economy: a maxed station shows no pad")

	-- star prices: x1.5 per star, LegacyPrices exempt; pads and CheckPurchase use them
	T.check(TC.StarPriceMultiplier(0) == 1 and near(TC.StarPriceMultiplier(1), 1.5) and near(TC.StarPriceMultiplier(2), 2.25)
		and near(TC.StarPriceMultiplier(3), 3.375) and near(TC.StarPriceMultiplier(4), 5.0625),
		"economy: StarPriceMultiplier = 1.5 ^ stars (x1.5, x2.25, x3.38, x5.06: 'after every Prestige things cost half as much again')")
	T.check(near(TC.StarPriceMultiplier(home({}, 2)), 2.25) and TC.StarPriceMultiplier(home({}, 3, { LegacyPrices = true })) == 1
		and TC.StarPriceMultiplier(home({}, 0, { LegacyPrices = true })) == 1,
		"economy: ...read from home.Prestige; a home with LegacyPrices = true (a Phase 3 veteran) pays base prices")
	local starT = T.tally("economy: PriceAt(id, level, home) = floor(PriceFor x 1.5 ^ stars) for every station and level, 0..5 stars; LegacyPrices = PriceFor")
	for _, sd in ipairs(TC.Stations) do
		for lv = 1, sd.MaxLevel do
			for stars = 0, 5 do
				local want = floor(TC.PriceFor(sd.Id, lv) * 1.5 ^ stars + 1e-9)
				starT:case(TC.PriceAt(sd.Id, lv, home({}, stars)) == want, sd.Id .. " L" .. lv .. " stars " .. stars)
				if stars > 0 then
					starT:case(TC.PriceAt(sd.Id, lv, home({}, stars, { LegacyPrices = true })) == TC.PriceFor(sd.Id, lv), sd.Id .. " L" .. lv .. " legacy")
				end
			end
		end
	end
	starT:report()
	T.check(TC.PriceAt("Garden", 1, home({}, 5)) == 0, "economy: the free Pet Garden stays free at any star count")
	local star2 = home({ Garden = 1, Press1 = 3, Collector = 1, Kitchen = 1 }, 2)
	local legacy2 = home({ Garden = 1, Press1 = 3, Collector = 1, Kitchen = 1 }, 2, { LegacyPrices = true })
	local b2 = padOf(TC.AvailablePads(star2), "Press1")
	local bl = padOf(TC.AvailablePads(legacy2), "Press1")
	T.check(b2 and b2.Price == floor(360 * 2.25) and b2.BasePrice == 360 and bl and bl.Price == 360 and bl.BasePrice == 360,
		"economy: pads show Price = the star price (Berry Bush L4 at 2 stars: $810) and BasePrice = PriceFor; LegacyPrices pads show the base price")
	local mismatch = {}
	for _, h in ipairs({ star2, legacy2, builtTo(TC, 2, 1), builtTo(TC, 3, 3) }) do
		for _, pad in ipairs(TC.AvailablePads(h)) do
			if pad.StationId ~= "Prestige" then
				if pad.Price ~= TC.PriceAt(pad.StationId, pad.NextLevel, h) or pad.BasePrice ~= TC.PriceFor(pad.StationId, pad.NextLevel) then
					mismatch[#mismatch + 1] = pad.StationId .. " price"
				end
				local ok, price, reason = TC.CheckPurchase(h, pad.StationId)
				if (pad.Locked == nil) ~= (ok == true) or (ok and price ~= pad.Price) or (not ok and reason ~= pad.Locked) then
					mismatch[#mismatch + 1] = pad.StationId .. " check"
				end
			end
		end
	end
	T.check(#mismatch == 0, "economy: pad prices = PriceAt and CheckPurchase agrees with the pads (price, lock reason) at 1-3 stars and with LegacyPrices", table.concat(mismatch, ", "))

	-- Home Level and the prestige reset
	T.eq(TC.HomeLevelOf(home({ Garden = 1, Press1 = 3, Collector = 1, DecorLamps = 1 })), 6, "economy: Home Level = the sum of station levels (each purchase = +1)")
	T.eq(TC.HomeLevelOf(home({ Press1 = 99, Bogus = 5, Collector = -3, Garden = "2" })), 10 + 2, "economy: Home Level ignores unknown stations / negatives and clamps to MaxLevel")
	local after = TC.StationsAfterPrestige({ Press1 = 8, House = 4, DecorLamps = 2, DecorFountain = 1, Garden = 6, Kitchen = 3, Bogus = 2 })
	T.check(setEq(after, { DecorLamps = 2, DecorFountain = 1, Garden = 1 }),
		"economy: StationsAfterPrestige keeps the decor (KeepOnPrestige), sets the Garden to level 1 (ResetLevel) and resets everything else")
	local fresh2 = TC.AvailablePads(home(after, 1))
	T.check(padOf(fresh2, "Press1") ~= nil and padOf(fresh2, "Press1").Price == floor(15 * 1.5) and TC.FoodOf(home(after, 1)) == TC.Coins.GrassFood,
		"economy: ...so after a prestige the garden still feeds (Food 12) and the Berry Bush pad is back at the star price ($22)")
end

local function coinChecks(TC, PC, Config)
	local scale = Config.PetStats.RarityScale
	-- FoodOf
	T.eq(TC.FoodOf(home({ Press1 = 5, Press2 = 3 })), 0, "economy: FoodOf = 0 without a Garden (no garden, no meals), whatever plants stand")
	T.eq(TC.FoodOf(home({ Garden = 1 })), 12, "economy: FoodOf = GrassFood 12 for a built Garden")
	T.eq(TC.FoodOf(home({ Garden = 1, Press1 = 1 })), 19, "economy: ...+ the Berry Bush's Food (L1: 19, the contract's example)")
	T.eq(TC.FoodOf(home({ Garden = 8, Press1 = 10, Press2 = 10, Press3 = 10, Press4 = 10 })), 2144, "economy: a fully built home has Food 2144 per meal")
	T.eq(TC.FoodOf(home({ Garden = 3, Press1 = 4, Press3 = 2, Collector = 5, Vault = 5 })), 12 + 16 + 63, "economy: FoodOf adds every built plant; the Garden level, the Magnet and the Vault add no food")

	-- PetPower: rarity x level factor x tier x role x evolution (the STORED stage)
	local ce, cc = findPet(PC, "Common", "Economy"), findPet(PC, "Common", "Combat")
	local ee, ec = findPet(PC, "Epic", "Economy"), findPet(PC, "Epic", "Combat")
	local le = findPet(PC, "Legendary", "Economy")
	if not T.check(ce and cc and ee and ec and le, "economy: PetCatalog has Common / Epic Economy + Combat pets and a Legendary Economy pet to test with") then
		return
	end
	T.check(near(TC.PetPower(cc), 1) and near(TC.PetPower(ce), 1.6), "economy: PetPower: a level-1 Common Combat pet = 1, a Common Economy pet = 1.6")
	local ratio = T.tally("economy: PetPower Economy / Combat == 1.6 at equal rarity / level / tier / stage (the player's 'economic pets produce 60% more')")
	for _, rarity in ipairs(RARITY_ORDER) do
		for _, lv in ipairs({ 1, 20, 50, 77, 100 }) do
			for _, tier in ipairs({ "Normal", "Golden", "Rainbow" }) do
				for stage = 0, 2 do
					local a = TC.PetPower({ Def = { Rarity = rarity, Role = "Economy" }, Level = lv, Tier = tier, Stage = stage })
					local bb = TC.PetPower({ Def = { Rarity = rarity, Role = "Combat" }, Level = lv, Tier = tier, Stage = stage })
					ratio:case(bb > 0 and near(a / bb, 1.6), rarity .. " L" .. lv .. " " .. tier .. " stage " .. stage .. ": " .. fmt(a, 3) .. " / " .. fmt(bb, 3))
				end
			end
		end
	end
	ratio:report()
	local scaleT = T.tally("economy: PetPower = RarityScale x (1 + 0.1 x (level - 1)) x tier (Normal 1 / Golden 1.5 / Rainbow 2.5) for every rarity, levels 1..100")
	for _, rarity in ipairs(RARITY_ORDER) do
		for _, lv in ipairs({ 1, 2, 10, 20, 49, 50, 51, 57, 99, 100 }) do
			for tier, m in pairs({ Normal = 1, Golden = 1.5, Rainbow = 2.5 }) do
				local want = scale[rarity] * (1 + 0.1 * (lv - 1)) * m
				scaleT:case(near(TC.PetPower({ Def = { Rarity = rarity, Role = "Combat" }, Level = lv, Tier = tier }), want), rarity .. " L" .. lv .. " " .. tier)
			end
		end
	end
	scaleT:report()
	T.check(TC.PetPower(cc, 57) > TC.PetPower(cc, 50) and near(TC.PetPower(cc, 150), TC.PetPower(cc, 100)) and near(TC.PetPower(cc, 100), 10.9),
		"economy: levels past 50 keep counting (every pet grows to 100: L100 = x10.9); above 100 counts as 100")
	-- evolution: the stored stage, cut to what the rarity can reach
	T.check(near(TC.PetPower(ce, 20, nil, 1) / TC.PetPower(ce, 20, nil, 0), 1.25) and near(TC.PetPower(ee, 50, nil, 2) / TC.PetPower(ee, 50, nil, 0), 1.5)
		and near(TC.PetPower(ee, 50, nil, 1) / TC.PetPower(ee, 50, nil, 0), 1.25),
		"economy: EVOLVE x1.25 (stage 1) and x1.5 (stage 2, Epic and rarer)")
	T.check(near(TC.PetPower(ce, 50, nil, 2) / TC.PetPower(ce, 50, nil, 0), 1.25), "economy: a Common counts at most stage 1 (Common / Uncommon / Rare evolve once)")
	T.check(near(TC.PetPower(ce, 25), TC.PetPower(ce, 25, nil, 0)) and near(TC.PetPower(ee, 60, nil, nil), TC.PetPower(ee, 60, nil, 0)),
		"economy: the level alone never evolves a pet (no stage = x1: the boost counts only after EVOLVE was pressed)")
	T.check(near(TC.PetPower(ce, 20, "Normal", 1), 5.8), "economy: a Common Economy at level 20 evolved has PetPower 5.8 (the contract's example)")
	T.check(near(TC.PetPower(le, 50, "Rainbow", 2), 5.5 * 5.9 * 2.5 * 1.6 * 1.5), "economy: a Legendary Economy L50 Rainbow Evolved II = 5.5 x 5.9 x 2.5 x 1.6 x 1.5 = 194.7")
	-- every entry shape
	local base = TC.PetPower({ Def = ce, Level = 7, Tier = "Golden", Stage = 1 })
	T.check(near(base, scale.Common * 1.6 * 1.5 * 1.25 * 1.6), "economy: PetPower({ Def, Level, Tier, Stage })")
	T.check(near(TC.PetPower({ Def = ce, Level = 7, Tier = "Golden", Evo = 1 }), base), "economy: ...Evo is read like Stage (PetGrowth[key].Evo)")
	T.check(near(TC.PetPower({ Def = ce, Level = 3, Tier = "Normal", Stage = 0 }, 7, "Golden", 1), base), "economy: ...the level / tier / stage arguments win over the entry's")
	T.check(near(TC.PetPower(ce.Id .. "@Golden", 7, nil, 1), base) and near(TC.PetPower(ce.Id, 7, "Golden", 1), base),
		"economy: pet key strings resolve through PetCatalog (\"" .. ce.Id .. "@Golden\" = x1.5)")
	T.check(near(TC.PetPower({ Rarity = "Rare", Role = "Economy", StatMultiplier = 1.5 }, 4), scale.Rare * 1.3 * 1.5 * 1.6),
		"economy: a PetKeys.DefOf-style def (a hybrid's merged def: Rarity, Role, StatMultiplier) works")
	T.check(TC.PetPower("hyb:abcdef") == 0, "economy: a hybrid key without its def counts 0 (callers pass PetKeys.DefOf)")
	T.check(near(TC.PetPower(7.5), 7.5) and near(TC.PetPower({ Power = 4 }), 4), "economy: numbers and { Power = n } entries count as that power")
	local junkPowers = { nil, false, "nope", {}, { Def = 5 }, { Rarity = "Nope", Role = "Economy" }, 0 / 0, -4, 1 / 0, { Power = 1 / 0 }, { Power = -1 } }
	local junkOk = true
	for i = 1, 11 do
		local ok, v = pcall(TC.PetPower, junkPowers[i])
		junkOk = junkOk and ok and v == 0
	end
	T.check(junkOk, "economy: junk PetPower entries (nil, strings, NaN, negatives, inf, unknown rarities) count 0 without errors")

	-- coin value + income
	local h = home({ Garden = 1, Press1 = 1 })
	T.check(near(TC.CoinValue(h, TC.PetPower(cc)), 19) and near(TC.CoinValue(h, TC.PetPower(ce)), 30.4)
		and near(TC.CoinValue(h, TC.PetPower({ Def = { Rarity = "Rare", Role = "Economy" } })), 69.92)
		and near(TC.CoinValue(h, TC.PetPower({ Def = { Rarity = "Legendary", Role = "Economy" } })), 167.2),
		"economy: one coin = Food x PetPower (Berry Bush L1: Common Combat $19, Common Economy $30, Rare Economy $70, Legendary Economy $167)")
	T.check(near(TC.IncomePerSecond(h, { cc }), 19 / 8) and near(TC.IncomePerSecond(h, { ce }), 30.4 / 8),
		"economy: IncomePerSecond = Food / MealSeconds x PetPower (2.4/s for a Common Combat, 3.8/s for a Common Economy)")
	local inc, parts = TC.IncomePerSecond(h, { ce, cc })
	T.check(type(parts) == "table" and parts.Food == 19 and near(parts.Pets, 2.6) and parts.Lucky == 1 and parts.Multiplier == 1 and near(inc, 19 / 8 * 2.6),
		"economy: ...returns { Food, Pets, Lucky, Multiplier }")
	T.check(TC.IncomePerSecond(h, {}) == 0 and TC.IncomePerSecond(home({ Press1 = 4 }), { ce }) == 0, "economy: no garden pet or no Garden = no coins")
	T.check(TC.IncomePerSecond(home({ Garden = 1 }), { ce }) > 0, "economy: no Collector condition (a lone Garden already earns: GrassFood 12)")
	local h8 = home({ Garden = 8, Press1 = 1 })
	local i8, p8 = TC.IncomePerSecond(h8, { ce })
	T.check(near(TC.LuckyChance(h8), 0.15) and near(p8.Lucky, 1.6) and near(i8, 19 / 8 * 1.6 * 1.6),
		"economy: the Lucky expected value: 1 + (LuckyMult 5 - 1) x Lucky (Garden L8: 15% Lucky coins = x1.6 on average)")
	T.check(near(TC.IncomePerSecond(h, { ce }, 1), 30.4 / 8 * 1.25) and near(TC.IncomePerSecond(h, { ce }, 2), 30.4 / 8 * 1.5625),
		"economy: coins x1.25 per prestige star (compounding)")
	T.check(near(TC.IncomePerSecond(home({ Garden = 1, Press1 = 1 }, 2), { ce }), 30.4 / 8 * 1.5625), "economy: ...taken from home.Prestige when the argument is nil")
	-- open places: 3 + stars; keys above the open count rest
	local four = { ce, ce, ce, ce }
	T.check(near(TC.IncomePerSecond(h, four), 3 * 30.4 / 8), "economy: only the open garden places eat (3 at the start: a 4th key rests)")
	T.check(near(TC.IncomePerSecond(home({ Garden = 1, Press1 = 1 }, 1), four, 0), 4 * 30.4 / 8), "economy: ...4 places at 1 star")
	T.check(near(TC.IncomePerSecond(home({ Garden = 1, Press1 = 1 }, 0, { LegacySlots = 4 }), four), 4 * 30.4 / 8), "economy: ...LegacySlots open extra places")
	T.check(near(TC.IncomePerSecond(h, { [1] = ce, [5] = ce }), 30.4 / 8) and near(TC.IncomePerSecond(home({ Garden = 1, Press1 = 1 }, 2), { [1] = ce, [5] = ce }, 0), 2 * 30.4 / 8),
		"economy: a slot -> entry map works too: slot 5 rests with 3 places and eats with 5")

	-- GardenSlots
	T.eq(TC.GardenSlots(home({})), 0, "economy: GardenSlots = 0 while the Garden is not built")
	T.eq(TC.GardenSlots(home({ Garden = 1 })), 3, "economy: GardenSlots = 3 at the start ('at the start you can put up to 3 pets')")
	T.eq(TC.GardenSlots(home({ Garden = 1 }, 1)), 4, "economy: ...4 at one star ('prestige 1 can put 4')")
	T.check(TC.GardenSlots(home({ Garden = 1 }, 9)) == 12 and TC.GardenSlots(home({ Garden = 1 }, 40)) == 12, "economy: ...12 at most (12 places are drawn)")
	T.eq(TC.GardenSlots(home({ Garden = 8 })), 3, "economy: the Garden level does not open places (it raises the Lucky chance)")
	T.check(TC.GardenSlots(home({ Garden = 1 }, 0, { LegacySlots = 6 })) == 6 and TC.GardenSlots(home({ Garden = 1 }, 5, { LegacySlots = 6 })) == 8
		and TC.GardenSlots(home({ Garden = 1 }, 0, { LegacySlots = 15 })) == 12 and TC.GardenSlots(home({}, 0, { LegacySlots = 6 })) == 0,
		"economy: GardenSlots = min(12, max(3 + stars, LegacySlots)) (a veteran keeps old extra places until the next Prestige)")
	-- Lucky by Garden level
	local lucky = {}
	for lv = 1, 8 do
		lucky[lv] = TC.LuckyChance(home({ Garden = lv }))
	end
	T.check(listEq(lucky, { 0, 0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.15 }) and TC.LuckyChance(home({})) == 0 and near(TC.LuckyEV(home({ Garden = 5 })), 1.32),
		"economy: LuckyChance by Garden level 0 / 2 / 4 ... 15% (0 without a Garden); LuckyEV = 1 + 4 x chance")
	-- piles and the scoop radius
	T.eq(TC.PileSeconds(home({ Garden = 1 })), 240, "economy: PileSeconds = 240 without a Coin Magnet")
	T.check(TC.PileSeconds(home({ Collector = 1 })) == 300 and TC.PileSeconds(home({ Collector = 5 })) == 600, "economy: ...the Coin Magnet's PileSeconds 300 .. 600")
	T.check(TC.PileSeconds(home({ Vault = 1 })) == 540 and TC.PileSeconds(home({ Collector = 5, Vault = 5 })) == 2400 and TC.PileSeconds(home({ Collector = 2, Vault = 3 })) == 360 + 900,
		"economy: ...+ the Vault's PileSeconds (bigger piles)")
	T.check(TC.ScoopRadius(home({})) == 6 and TC.ScoopRadius(home({ Collector = 1 })) == 9 and TC.ScoopRadius(home({ Collector = 5, Vault = 5 })) == 26
		and TC.ScoopRadius(home({ Vault = 5 })) == 6,
		"economy: ScoopRadius = 6 studs without a Coin Magnet, 9 .. 26 with it (the Vault does not change it)")
	T.check(TC.PileSeconds(home({})) / 20 >= 10, "economy: the smallest pile holds >= 10 scoops of a kid walking through every 20 s")
	-- heaps
	local heaps = {}
	for i, coins in ipairs({ 0, 1, 2, 3, 5, 6, 11, 12, 23, 24, 500 }) do
		heaps[i] = TC.HeapStage(coins)
	end
	T.check(listEq(heaps, { 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 }), "economy: HeapStage(coins) = the CoinPiles heap stage 0..5 from HeapStages {1, 3, 6, 12, 24}", show(heaps))

	-- offline earnings (unchanged API)
	local hv = home({ Garden = 1, Vault = 2 })
	T.eq(TC.OfflineEarnings(home({ Garden = 1 }), 3600, 100), 0, "economy: no Vault, no offline coins")
	T.eq(TC.OfflineEarnings(hv, 60, 100), 0, "economy: absences shorter than OfflineMinSeconds (120 s) pay nothing")
	T.eq(TC.OfflineEarnings(hv, 1800, 100), floor(100 * 1800 * 0.15), "economy: offline pays OfflinePercent of the income")
	T.eq(TC.OfflineEarnings(hv, 48 * 3600, 100), floor(100 * 2 * 3600 * 0.15), "economy: ...for at most OfflineHours")
	local amount, info = TC.OfflineEarnings(hv, 7200, 50)
	T.check(type(info) == "table" and info.Seconds == 7200 and info.Percent == 0.15 and info.MaxHours == 2 and amount > 0,
		"economy: OfflineEarnings also returns { Seconds, Percent, MaxHours }")
	local best = TC.Get("Vault").Effects[TC.Get("Vault").MaxLevel]
	T.check(best.OfflinePercent * best.OfflineHours <= 2 and best.OfflinePercent * best.OfflineHours >= 0.5,
		"economy: the best Vault pays between 30 min and 2 h of active income (meaningful but capped): " .. fmt(best.OfflinePercent * best.OfflineHours * 60, 0) .. " min")
end

local function careChecks(TC, PC)
	-- the XP curve to 100
	local px = TC.PetXp
	T.check(px.MaxLevel == 100 and px.Base == 20 and px.Exponent == 1.6 and px.Round == 5, "economy: PetXp = { MaxLevel 100, Base 20, Exponent 1.6, Round 5 }")
	T.check(TC.XpToNext(1) == 20 and TC.XpToNext(49) == 10125 and TC.XpToNext(99) == 31190 and TC.XpToNext(100) == huge,
		"economy: XpToNext: 20 XP at L1, 10,125 at L49, 31,190 at L99, math.huge at 100")
	T.check(TC.XpForLevel(20) == 17375 and TC.XpForLevel(50) == 195880 and TC.XpForLevel(100) == 1203340,
		"economy: the roads: 17,375 XP to level 20, 195,880 to 50, 1,203,340 to 100")
	local prev, okXp = 0, true
	for lv = 1, px.MaxLevel - 1 do
		local x = TC.XpToNext(lv)
		okXp = okXp and x >= prev and x > 0
		prev = x
	end
	T.check(okXp and TC.XpToNext(0) == TC.XpToNext(1) and TC.XpToNext(nil) == TC.XpToNext(1) and TC.XpToNext(1e9) == huge,
		"economy: XpToNext keeps rising to 100 and treats junk as level 1 / huge levels as the top")
	if type(PC.MaxPetLevel) == "function" then
		T.eq(PC.MaxPetLevel(), TC.MaxPetLevel, "economy: PetCatalog.MaxPetLevel() reads TycoonCatalog's 100")
	end

	-- the Food Machine
	T.check(TC.FeedXp(1, 1) == 5 and TC.FeedPrice("Common", 1) == 40, "economy: Food Machine Lv1, a level-1 Common: feed $40 for 5 XP (the contract's example)")
	T.check(TC.FeedXp(10, 1) == 199 and TC.FeedPrice("Common", 10) == 1590, "economy: ...level 10: $1,590 for 199 XP")
	T.check(TC.FeedXp(19, 1) == 556 and TC.FeedPrice("Common", 19) == 4450, "economy: ...level 19: $4,450 for 556 XP")
	local shareT = T.tally("economy: FeedXp(level, machine) = max(1, round(XpToNext x FeedShare[machine])) at every level and machine level")
	for ml = 1, 5 do
		for lv = 1, 99 do
			local want = max(1, floor(TC.XpToNext(lv) * TC.FeedShare[ml] + 0.5))
			shareT:case(TC.FeedXp(lv, ml) == want, "L" .. lv .. " machine " .. ml)
		end
	end
	shareT:report()
	T.check(TC.FeedXp(5, 0) == 0 and TC.FeedXp(100, 3) == 0 and TC.FeedXp(5, 9) == TC.FeedXp(5, 5) and TC.FeedXp(99, 1) == 7798,
		"economy: FeedXp = 0 without a machine and at level 100; levels past 50 keep feeding (L99: 7,798 XP)")
	local ee = findPet(PC, "Epic", "Economy")
	local priceT = T.tally("economy: FeedPrice(pet, level) = round(XpToNext x RarityScale x FeedBase 2.0) for every rarity (def / rarity id / pet id / key), the same at every machine level")
	local scale = K.config().PetStats.RarityScale
	for _, rarity in ipairs(RARITY_ORDER) do
		for _, lv in ipairs({ 1, 2, 19, 20, 49, 50, 77, 99 }) do
			priceT:case(TC.FeedPrice(rarity, lv) == floor(TC.XpToNext(lv) * scale[rarity] * 2 + 0.5), rarity .. " L" .. lv)
		end
	end
	if ee then
		priceT:case(TC.FeedPrice(ee, 12) == TC.FeedPrice("Epic", 12) and TC.FeedPrice(ee.Id, 12) == TC.FeedPrice("Epic", 12)
			and TC.FeedPrice(ee.Id .. "@Rainbow", 12) == TC.FeedPrice("Epic", 12) and TC.FeedPrice({ Def = ee }, 12) == TC.FeedPrice("Epic", 12),
			"subject shapes")
	end
	priceT:report()
	T.check(TC.FeedPrice("Common", 100) == nil and TC.FeedPrice("Nope", 3) == nil and TC.FeedPrice(nil, 3) == nil and TC.FeedPrice("hyb:abc", 3) == nil,
		"economy: FeedPrice = nil at level 100 and for unknown pets")
	-- the roads (contract 3.4): L1 -> 20 $139K at a Lv1 machine / $69.5K at Lv5; L1 -> 50 $1.57M / $784K
	local function road(target, ml)
		local total, lv, have = 0, 1, 0
		while lv < target do
			total = total + TC.FeedPrice("Common", lv)
			have = have + TC.FeedXp(lv, ml)
			while lv < target and have >= TC.XpToNext(lv) do
				have = have - TC.XpToNext(lv)
				lv = lv + 1
			end
		end
		return total
	end
	local r20, r20b, r50, r50b = road(20, 1), road(20, 5), road(50, 1), road(50, 5)
	T.check(near(r20, 139000, 0.01) and near(r20b, 69500, 0.01) and near(r50, 1570000, 0.01) and near(r50b, 784000, 0.01),
		"economy: a Common's road at the Food Machine: L1 -> 20 $" .. r20 .. " (Lv1) / $" .. r20b .. " (Lv5); L1 -> 50 $" .. r50 .. " / $" .. r50b .. " (contract: $139K / $69.5K, $1.57M / $784K)")

	-- the Training Place
	local trT = T.tally("economy: TrainCost(pet, rank) = round(300 x rank^2 x RarityScale) for ranks 1..10, every rarity (never scaled by stars)")
	for _, rarity in ipairs(RARITY_ORDER) do
		for r = 1, 10 do
			trT:case(TC.TrainCost(rarity, r) == floor(300 * r * r * scale[rarity] + 0.5), rarity .. " rank " .. r)
		end
	end
	trT:report()
	local all = 0
	for r = 1, 10 do
		all = all + 4 * TC.TrainCost("Common", r)
	end
	T.check(TC.TrainCost("Common", 1) == 300 and TC.TrainCost("Common", 10) == 30000 and all == 462000 and TC.TrainCost("Legendary", 1) == 1650,
		"economy: Common 300 ... 30,000 per rank, all 40 ranks $462K, Legendary x5.5")
	T.check(TC.TrainCost("Common", 0) == nil and TC.TrainCost("Common", 11) == nil and TC.TrainCost("Common", 1.5) == nil and TC.TrainCost("Nope", 1) == nil
		and TC.TrainCost(nil, 2) == nil and TC.TrainCost("Common", "x") == nil,
		"economy: TrainCost = nil for ranks outside 1..10, fractions and unknown pets")
	T.check(TC.TrainSeconds(1) == 60 and TC.TrainSeconds(3) == 180 and TC.TrainSeconds(10) == 600 and TC.TrainSeconds(0) == nil and TC.TrainSeconds(11) == nil
		and TC.TrainSeconds(2.5) == nil,
		"economy: TrainSeconds(rank) = rank minutes ('Rank 3 takes 3 minutes'); nil outside 1..10")
	local slots = {}
	for lv = 0, 5 do
		slots[#slots + 1] = TC.TrainingSlots(home({ Gym = lv }))
	end
	T.check(listEq(slots, { 0, 1, 2, 3, 4, 5 }), "economy: TrainingSlots = the Training Place level (pets training at once; 0 unbuilt)", show(slots))
end

-- PetCatalog's Phase 4 data == TycoonCatalog's mirrors: a copy of TycoonCatalog loaded WITHOUT PetCatalog (the sim /
-- pure-tool path) gives the same PetPower as the game copy
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
	-- Lua 5.1 / LuaJIT: loadstring + setfenv; Lua 5.2+: load with an environment
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
	local tally = T.tally("economy: PetPower without PetCatalog (the local mirrors of LevelBonus / RoleMult / EvolutionBoost / EvolveTwice) == PetPower with it, every pet x level x tier x stage")
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
	T.check(PC.LevelBonus == 0.1 and PC.RoleMult.Economy == 1.6 and PC.RoleMult.Combat == 1 and listEq(PC.EvolutionBoost, { 1.25, 1.5 })
		and listEq(PC.EvolutionLevels, { 20, 50 }),
		"economy: PetCatalog's wave-0 data: LevelBonus 0.1, RoleMult Economy 1.6 / Combat 1, EvolutionLevels {20, 50}, EvolutionBoost {1.25, 1.5}")
	local okV, valid = pcall(solo.Validate)
	T.check(okV and valid == true, "economy: ...and the PetCatalog-less copy passes Validate() too")
end

local function compatChecks(TC, PC)
	local ce = findPet(PC, "Common", "Economy")
	local h = home({ Garden = 1, Press1 = 1, Collector = 1, Kitchen = 2, Gym = 3 })
	-- Phase 3 compat, removed in wave 4: the old services and clients keep booting on these
	local missing = {}
	for _, name in ipairs({ "PetIncome", "GardenIncome", "PressIncome", "CollectorCap", "KitchenSpeed", "CookSecondsFor", "FoodsFor", "FoodById", "GymSlots", "GymXpPerMinute" }) do
		if type(TC[name]) ~= "function" then
			missing[#missing + 1] = name
		end
	end
	T.check(#missing == 0, "economy: the Phase 3 compat aliases exist until wave 4 (PetIncome, GardenIncome, PressIncome, CollectorCap, KitchenSpeed, CookSecondsFor, FoodsFor, FoodById, GymSlots, GymXpPerMinute)", table.concat(missing, ", "))
	if #missing > 0 then
		return
	end
	local stat = PC.GetStats(ce.Id, 5, "Golden").Income
	T.check(near(TC.PetIncome({ Def = ce, Level = 5, Tier = "Golden" }), stat) and near(TC.PetIncome(ce.Id .. "@Golden", 5), stat),
		"economy: compat PetIncome(entry) = the Phase 3 stat (GetStats Income: p2care_stats keeps pinning it)")
	T.check(near(TC.PetIncome(ce, 1, nil, h), TC.PetPower(ce) * TC.FoodOf(h) / 8), "economy: compat PetIncome(entry, level, tier, home) = PetPower x FoodOf / 8 (contract 5.4)")
	local inc, parts = TC.IncomePerSecond(h, { ce })
	T.check(TC.PressIncome(h) == 0 and parts.Press == 0 and near(parts.Garden, inc) and near(TC.GardenIncome(h, { ce }), inc),
		"economy: compat PressIncome = 0, IncomePerSecond parts Press 0 / Garden = the total, GardenIncome = the garden's cash/s")
	T.eq(TC.CollectorCap(h, 10), floor(TC.PileSeconds(h) * 10), "economy: compat CollectorCap(home, income) = PileSeconds x income")
	T.check(TC.CollectorCap(home({ Garden = 1, Press1 = 1 }, 0, { Garden = { [1] = ce.Id } })) > 0, "economy: ...counting the pets in home.Garden when no income is passed")
	T.check(TC.GymSlots(h) == TC.TrainingSlots(h) and TC.GymSlots(h) == 3 and TC.GymXpPerMinute(h) > 0 and TC.GymXpPerMinute(home({})) == 0,
		"economy: compat GymSlots = TrainingSlots, GymXpPerMinute keeps the Phase 3 numbers")
	T.check(TC.KitchenSpeed(h) >= 1 and TC.CookSecondsFor("Snack", 1) == TC.FoodsById.Snack.CookSeconds and TC.CookSecondsFor("Feast", 1) == nil
		and #TC.FoodsFor(2) == 2 and TC.FoodById("Feast") == TC.FoodsById.Feast,
		"economy: compat KitchenSpeed / CookSecondsFor / FoodsFor / FoodById keep the Phase 3 cooking data")
	local ke, ge = TC.Get("Kitchen").Effects[3], TC.Get("Gym").Effects[2]
	T.check(type(ke.Queue) == "number" and type(ke.Recipes) == "table" and type(ge.XpPerMinute) == "number",
		"economy: compat effect fields: the Food Machine's Queue / Recipes and the Training Place's XpPerMinute (Phase 3 PetCareService / NpcDialog)")
end

local function junkChecks(TC)
	local junk = { nil, false, 5, "x", {}, { Stations = "x" }, { Stations = { Press1 = "abc", House = 99, Collector = 0 / 0, Garden = -1 }, Prestige = "z" },
		{ Stations = { House = 4, Garden = 3 }, Prestige = -3, LegacySlots = "q", LegacyPrices = "yes" }, { Stations = { Garden = 1 }, Prestige = 1e12, LegacySlots = 1 / 0 } }
	local errors = {}
	for i = 1, 9 do
		local h = junk[i]
		local calls = {
			function() return TC.AvailablePads(h) end,
			function() return TC.HomeLevelOf(h) end,
			function() return TC.IncomePerSecond(h, { "nope", false, { Def = 5 }, 0 / 0, -4, { Power = 1 / 0 } }, "q") end,
			function() return TC.IncomePerSecond(h, "x", 0 / 0) end,
			function() return TC.CollectorCap(h, "x") end,
			function() return TC.OfflineEarnings(h, 0 / 0, -1) end,
			function() return TC.OfflineEarnings(h, 99999, 1 / 0) end,
			function() return TC.CheckPurchase(h, 7) end,
			function() return TC.StationsAfterPrestige(h) end,
			function() return TC.FoodOf(h) end,
			function() return TC.GardenSlots(h) end,
			function() return TC.LuckyChance(h) end,
			function() return TC.PileSeconds(h) end,
			function() return TC.ScoopRadius(h) end,
			function() return TC.TrainingSlots(h) end,
			function() return TC.StarPriceMultiplier(h) end,
			function() return TC.PriceAt("Press1", 2, h) end,
			function() return TC.CoinValue(h, "x") end,
		}
		for j, fn in ipairs(calls) do
			local ok, err = pcall(fn)
			if not ok then
				errors[#errors + 1] = "junk home " .. i .. " call " .. j .. ": " .. tostring(err)
			end
		end
	end
	local extra = {
		function() return TC.PriceFor("Press1", 0) end, function() return TC.PriceFor("Press1", 11) end,
		function() return TC.PriceFor(nil, nil) end, function() return TC.XpToNext("x") end,
		function() return TC.FusionCost("Nope", "Rare") end, function() return TC.FusionCost("Mix", "Nope") end,
		function() return TC.Get(nil) end, function() return TC.FormatCash(1234567) end,
		function() return TC.FeedXp("x", "y") end, function() return TC.FeedXp(nil, nil) end, function() return TC.FeedPrice({}, -5) end,
		function() return TC.TrainCost({}, 0 / 0) end, function() return TC.TrainSeconds(1 / 0) end, function() return TC.CoinPoint("x") end,
		function() return TC.HeapStage(0 / 0) end, function() return TC.PetPower({ Def = {}, Level = "x" }, 0 / 0, {}, "z") end,
	}
	for j, fn in ipairs(extra) do
		local ok, err = pcall(fn)
		if not ok then
			errors[#errors + 1] = "extra " .. j .. ": " .. tostring(err)
		end
	end
	T.check(#errors == 0, "economy: junk input never errors (pads, Home Level, income, piles, slots, star prices, feeding, training, coin points)", table.concat(errors, " | "))
	T.check(TC.PriceFor("Press1", 0) == nil and TC.PriceFor("Press1", 11) == nil and TC.PriceAt("Press1", 11, home()) == nil, "economy: PriceFor / PriceAt are nil outside 1..MaxLevel")
	local nan = TC.IncomePerSecond({ Stations = { Garden = 1, Press1 = 1 } }, { 0 / 0, -4, { Power = 1 / 0 } }, 0)
	T.check(nan == 0, "economy: NaN / negative / infinite garden entries earn nothing", tostring(nan))
	local big = TC.IncomePerSecond({ Stations = { Garden = 1, Press1 = 1 }, Prestige = 1e12 }, { 2 })
	T.check(big == big and big ~= huge and big > 0, "economy: an absurd prestige count still gives a finite income", tostring(big))
	local bigPrice = TC.PriceAt("House", 4, { Stations = {}, Prestige = 1e12 })
	T.check(bigPrice == bigPrice and bigPrice ~= huge, "economy: ...and a finite star price", tostring(bigPrice))
	T.eq(TC.OfflineEarnings({ Stations = { Vault = 1 } }, 99999, 1 / 0), 0, "economy: an infinite income pays no offline coins")
	T.check(TC.GardenSlots({ Stations = { Garden = 1 }, Prestige = 0, LegacySlots = 1 / 0 }) == 3 and TC.GardenSlots({ Stations = { Garden = 1 }, Prestige = -3 }) == 3,
		"economy: junk LegacySlots / negative stars open the normal 3 places")
end

-- Validate passes, and each Phase 4 rule it owns really catches a broken catalog (mutate, check, restore)
local function validateChecks(TC)
	local ok, valid, problems = pcall(TC.Validate)
	T.check(ok and valid == true and type(problems) == "table" and #problems == 0, "economy: TycoonCatalog.Validate() passes",
		ok and table.concat(problems or {}, " | ") or tostring(valid))
	local garden, magnet, kitchen, gym, vault, press1 = TC.Get("Garden"), TC.Get("Collector"), TC.Get("Kitchen"), TC.Get("Gym"), TC.Get("Vault"), TC.Get("Press1")
	local V3 = Vector3.new
	local cases = {
		{ "Plant Food rising", function() local o = press1.Effects[3].Food press1.Effects[3].Food = press1.Effects[2].Food return function() press1.Effects[3].Food = o end end, "Press1: Effects.Food" },
		{ "Garden Lucky <= 0.5", function() local o = garden.Effects[8].Lucky garden.Effects[8].Lucky = 0.6 return function() garden.Effects[8].Lucky = o end end, "Garden: Effects.Lucky" },
		{ "Garden Lucky never drops", function() local o = garden.Effects[4].Lucky garden.Effects[4].Lucky = 0.01 return function() garden.Effects[4].Lucky = o end end, "Garden: Effects.Lucky" },
		{ "Garden >= 12 Spots", function()
			local o = garden.Slot.Spots
			local eight = {}
			for i = 1, 8 do
				eight[i] = o[i]
			end
			garden.Slot.Spots = eight
			return function() garden.Slot.Spots = o end
		end, "Garden: needs 12 Spots" },
		{ "Magnet Radius above the base", function() local o = magnet.Effects[1].Radius magnet.Effects[1].Radius = 5 return function() magnet.Effects[1].Radius = o end end, "Collector: Effects.Radius" },
		{ "Magnet PileSeconds rising", function() local o = magnet.Effects[2].PileSeconds magnet.Effects[2].PileSeconds = magnet.Effects[1].PileSeconds return function() magnet.Effects[2].PileSeconds = o end end, "Collector: Effects.PileSeconds" },
		{ "FeedShare <= 1", function() local o = kitchen.Effects[5].FeedShare kitchen.Effects[5].FeedShare = 1.2 return function() kitchen.Effects[5].FeedShare = o end end, "Kitchen: Effects.FeedShare" },
		{ "Training Slots rising", function() local o = gym.Effects[3].Slots gym.Effects[3].Slots = 2 return function() gym.Effects[3].Slots = o end end, "Gym: Effects.Slots" },
		{ "Vault PileSeconds rising", function() local o = vault.Effects[2].PileSeconds vault.Effects[2].PileSeconds = vault.Effects[1].PileSeconds return function() vault.Effects[2].PileSeconds = o end end, "Vault: Effects.PileSeconds" },
		{ "coin points off pads", function()
			local o = garden.Slot.CoinPoints[1]
			garden.Slot.CoinPoints[1] = V3(0, 0, -14) -- the Garden's own pad at plot (10, -1)
			return function() garden.Slot.CoinPoints[1] = o end
		end, "coin point 1 lies on the Garden pad" },
		{ "coin points apart", function()
			local o = garden.Slot.CoinPoints[2]
			garden.Slot.CoinPoints[2] = garden.Slot.CoinPoints[1] + V3(0.5, 0, 0)
			return function() garden.Slot.CoinPoints[2] = o end
		end, "closer than 1.5 studs" },
		{ "Welcome-back pile off pads", function() local o = garden.Slot.WelcomePile garden.Slot.WelcomePile = V3(10, 0, -1) return function() garden.Slot.WelcomePile = o end end, "the Welcome-back pile lies on the Garden pad" },
		{ "no Conveyor", function() TC.Layout.Conveyor = { Start = V3(-32.5, 0, 18.5), Finish = V3(-32.5, 0, -22), Width = 3 } return function() TC.Layout.Conveyor = nil end end, "Layout.Conveyor" },
		{ "Coins positive", function() local o = TC.Coins.GrassFood TC.Coins.GrassFood = 0 return function() TC.Coins.GrassFood = o end end, "Coins.GrassFood" },
		{ "the Garden is the root", function() local o = garden.Requires garden.Requires = { Press1 = 1 } return function() garden.Requires = o end end, "a fresh home must show exactly one pad" },
		{ "the Garden survives Prestige", function() garden.ResetLevel = nil return function() garden.ResetLevel = 1 end end, "Prestige must keep the Garden built" },
		{ "one FeedShare per machine level", function() local o = TC.FeedShare TC.FeedShare = { 0.25 } return function() TC.FeedShare = o end end, "FeedShare needs one share per Food Machine level" },
	}
	local tally = T.tally("economy: Validate catches each Phase 4 rule (Plant Food, Garden Lucky + 12 Spots, Magnet, FeedShare, Training Slots, Vault piles, coin points, Welcome-back pile, no Conveyor, the root Garden, ResetLevel)")
	for _, case in ipairs(cases) do
		local restore = case[2]()
		local okc, v, probs = pcall(TC.Validate)
		restore()
		local hit = false
		if okc and type(probs) == "table" then
			for _, msg in ipairs(probs) do
				if tostring(msg):find(case[3], 1, true) then
					hit = true
				end
			end
		end
		tally:case(okc and v == false and hit, case[1] .. ": " .. (okc and table.concat(probs or {}, " | ") or tostring(v)))
	end
	tally:report()
	local ok2, valid2 = pcall(TC.Validate)
	T.check(ok2 and valid2 == true, "economy: ...and passes again once every mutation is undone")
end

local function layoutChecks(TC, Config)
	local L = TC.Layout
	local half = L.Half
	T.eq(L.PlotSize, Config.Lobby.PlotSize, "layout: the yard is Config.Lobby.PlotSize studs (" .. tostring(L.PlotSize) .. ")")
	T.check(L.Conveyor == nil, "layout: Layout.Conveyor is gone (no presses, no belt)")
	T.check(type(L.Paths) == "table" and #L.Paths == 11 and typeof(L.PadSize) == "Vector3" and typeof(L.Spawn) == "Vector3" and L.GateWidth == 12,
		"layout: the rest of Layout stays (11 stone paths incl. the PressLane beside the plants, PadSize, Gate, Spawn)")
	-- the slots are the Phase 3 ones
	local slotT = T.tally("layout: every station keeps its Phase 3 slot (position, facing, footprint, pad)")
	for _, id in ipairs(CONTRACT_IDS) do
		local def, want = TC.Get(id), P3_SLOTS[id]
		local cf, fp, pad = def.Slot.CFrame, def.Slot.Footprint, def.Slot.Pad.Position
		local yaw = math.rad(want[3])
		local look = cf.LookVector
		local w = want[4] == 0 and L.PlotSize or want[4]
		local d = want[6] == 0 and L.PlotSize or want[6]
		local ok = abs(cf.Position.X - want[1]) < 1e-6 and abs(cf.Position.Z - want[2]) < 1e-6
			and abs(look.X + math.sin(yaw)) < 1e-6 and abs(look.Z + math.cos(yaw)) < 1e-6
			and abs(fp.X - w) < 1e-6 and abs(fp.Y - want[5]) < 1e-6 and abs(fp.Z - d) < 1e-6
			and abs(pad.X - want[7]) < 1e-6 and abs(pad.Z - want[8]) < 1e-6
		slotT:case(ok, id)
	end
	slotT:report()
	local function rect(def)
		return TC.FootprintRect(def.Slot.CFrame, def.Slot.Footprint)
	end
	local function pos(def)
		return def.Slot.CFrame.Position
	end
	local house = TC.Get("House")
	T.check(pos(house).Z > half * 0.5 and rect(house)[4] <= half, "layout: the house stands at the back of the yard (z " .. fmt(pos(house).Z) .. ")")
	local side = true
	for _, id in ipairs({ "Press1", "Press2", "Press3", "Press4", "Collector" }) do
		side = side and rect(TC.Get(id))[2] < 0
	end
	T.check(side, "layout: the food plants + the Coin Magnet on one side (-X, the old press row)")
	T.check(rect(TC.Get("Garden"))[1] > 0, "layout: the Pet Garden on the opposite side (+X)")
	for _, id in ipairs({ "DecorFlowers", "DecorBanners" }) do
		T.check(rect(TC.Get(id))[3] <= -half + 3, "layout: " .. id .. " lines the front fence")
	end
	T.check(TC.Get("DecorFence").Slot.Perimeter == true, "layout: the fence decor follows the whole fence line")
	-- pads in front of their stations (non-decor)
	local front = T.tally("layout: every station's pad is in front of it (the side its CFrame looks at)")
	for _, def in ipairs(TC.Stations) do
		if def.Kind ~= "Decor" then
			front:case((def.Slot.Pad.Position - pos(def)):Dot(def.Slot.CFrame.LookVector) > 0, def.Id)
		end
	end
	front:report()
	-- the gate opening and the spawn stay clear
	local blockers = {}
	for _, def in ipairs(TC.Stations) do
		local slot = def.Slot
		if slot.Walkable ~= true and not slot.Perimeter then
			local r = rect(def)
			if r[1] < L.GateWidth / 2 and r[2] > -L.GateWidth / 2 and r[3] < -half + 6 then
				blockers[#blockers + 1] = def.Id
			end
			if L.Spawn.X > r[1] and L.Spawn.X < r[2] and L.Spawn.Z > r[3] and L.Spawn.Z < r[4] then
				blockers[#blockers + 1] = def.Id .. " (spawn)"
			end
		end
	end
	T.check(#blockers == 0, "layout: nothing solid blocks the gate opening or the home spawn", table.concat(blockers, ", "))

	-- the garden of section 3.3: 12 places on a 3 x 4 grid, the walks, the coin points, the Welcome-back pile
	local garden = TC.Get("Garden")
	local gs = garden.Slot
	local spots = gs.Spots or {}
	local spotOk = #spots == 12
	local xs, zs = { -7.5, -2.5, 2.5, 7.5 }, { -7, 0, 7 }
	for row = 1, 3 do
		for col = 1, 4 do
			local v = spots[(row - 1) * 4 + col]
			spotOk = spotOk and typeof(v) == "Vector3" and abs(v.X - xs[col]) < 1e-6 and abs(v.Z - zs[row]) < 1e-6 and v.Y == 0
		end
	end
	T.check(spotOk, "layout: Garden.Slot.Spots = 12 places: X -7.5 / -2.5 / 2.5 / 7.5 x Z -7 (front, places 1-4) / 0 (5-8) / +7 (back, 9-12)", #spots .. " spots")
	T.check(#spots >= TC.Prestige.GardenSlotsMax, "layout: a place for every open garden place (GardenSlotsMax 12)")
	local walks = type(gs.Walkable) == "table" and gs.Walkable or {}
	local function walkAt(z)
		for _, w in ipairs(walks) do
			if abs(w.Center.Z - z) < 1e-6 and abs(w.Size.Z - 3) < 1e-6 and w.Size.X >= 18 then
				return true
			end
		end
		return false
	end
	local entrance = false
	for _, w in ipairs(walks) do
		if abs(w.Center.X) < 1e-6 and abs(w.Size.X - 3) < 1e-6 and w.Center.Z < -6 then
			entrance = true
		end
	end
	T.check(walkAt(-3.5) and walkAt(3.5) and entrance, "layout: two 3-stud sand walks at Z -3.5 / +3.5 and the 3-stud entrance gap at X 0 (Garden.Slot.Walkable)")
	local coinZ = { -4.4, -2.6, 3.5 }
	local cpT = T.tally("layout: CoinPoint(slot) = the contract's points (front row Z -2.6, middle -4.4, back +3.5; X of the place)")
	for i = 1, 12 do
		local v = TC.CoinPoint(i)
		local row, col = floor((i - 1) / 4) + 1, (i - 1) % 4 + 1
		cpT:case(typeof(v) == "Vector3" and abs(v.X - xs[col]) < 1e-6 and abs(v.Z - coinZ[row]) < 1e-6 and v.Y == 0 and gs.CoinPoints[i] == v, "slot " .. i)
	end
	cpT:report()
	T.check(TC.CoinPoint(0) == nil and TC.CoinPoint(13) == nil and TC.CoinPoint(1.5) == nil and TC.CoinPoint("x") == nil and TC.CoinPoint(nil) == nil,
		"layout: CoinPoint answers only the places 1..12")
	-- every coin point inside the yard, on a walk, off every pad and cushion, apart
	local padRects = {}
	for _, def in ipairs(TC.Stations) do
		padRects[#padRects + 1] = { def.Id, TC.PadRect(def.Slot.Pad) }
	end
	padRects[#padRects + 1] = { "Prestige", TC.PadRect(TC.Get("Prestige").Slot.Pad) }
	local function onPad(x, z)
		for _, pr in ipairs(padRects) do
			local r = pr[2]
			if x >= r[1] - 0.25 and x <= r[2] + 0.25 and z >= r[3] - 0.25 and z <= r[4] + 0.25 then
				return pr[1]
			end
		end
		return nil
	end
	local placeT = T.tally("layout: every coin point lies inside the yard, inside the garden, off every pad and >= 1.5 studs from the other piles")
	local fr = TC.FootprintRect(gs.CFrame, gs.Footprint)
	local worlds = {}
	for i = 1, 12 do
		local w = gs.CFrame * TC.CoinPoint(i)
		local apart = true
		for _, o in ipairs(worlds) do
			apart = apart and (o - w).Magnitude >= 1.5
		end
		worlds[#worlds + 1] = w
		placeT:case(abs(w.X) <= half - 1 and abs(w.Z) <= half - 1 and w.X >= fr[1] and w.X <= fr[2] and w.Z >= fr[3] and w.Z <= fr[4]
			and onPad(w.X, w.Z) == nil and apart, "slot " .. i .. " at (" .. fmt(w.X) .. ", " .. fmt(w.Z) .. ")")
	end
	placeT:report()
	local wp = gs.WelcomePile
	T.check(typeof(wp) == "Vector3" and abs(wp.X - 13.5) < 1e-6 and abs(wp.Z - 2.5) < 1e-6 and onPad(wp.X, wp.Z) == nil and abs(wp.X) <= half - 1,
		"layout: Garden.Slot.WelcomePile = plot-local (13.5, 0, 2.5): beside the garden entrance, off the pad")
	local gym = TC.Get("Gym")
	T.check(#(gym.Slot.Spots or {}) >= 5, "layout: the Training Place keeps a mat (Spot) for each of the 5 training slots")
	-- paths touch every pad
	local onPath = T.tally("layout: every pad touches a stone path (Layout.Paths)")
	local function nearPath(p)
		for _, path in ipairs(L.Paths) do
			local a, b, w = path.Start, path.Finish, path.Width
			local x0, x1 = math.min(a.X, b.X) - w / 2 - 3, math.max(a.X, b.X) + w / 2 + 3
			local z0, z1 = math.min(a.Z, b.Z) - w / 2 - 3, math.max(a.Z, b.Z) + w / 2 + 3
			if p.X >= x0 and p.X <= x1 and p.Z >= z0 and p.Z <= z1 then
				return true
			end
		end
		return false
	end
	for _, def in ipairs(TC.Stations) do
		onPath:case(nearPath(def.Slot.Pad.Position), def.Id)
	end
	onPath:case(nearPath(TC.Get("Prestige").Slot.Pad.Position), "Prestige")
	onPath:report()
	local reach = TC.ReachablePads(1, 1)
	local unreachable = {}
	for id, ok in pairs(reach) do
		if not ok then
			unreachable[#unreachable + 1] = id
		end
	end
	T.check(#unreachable == 0, "layout: a player (2 studs wide) can walk from the gate to every pad", table.concat(unreachable, ", "))
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

	-- stations: prices, caps, requirements, flags, plant food
	local keep, soon = {}, {}
	for _, w in ipairs(words(get("KEEP_ON_PRESTIGE"))) do
		keep[w] = true
	end
	for _, w in ipairs(words(get("COMING_SOON"))) do
		soon[w] = true
	end
	local reset = parseReq(get("RESET_LEVEL"))
	local prices = T.tally("economy: sim PRICE_<id> == catalog Price for every station", 4)
	local capsT = T.tally("economy: sim CAPS_<id> == catalog TierCaps (Cottage, Villa, Manor, Sky Castle)", 4)
	local reqT = T.tally("economy: sim REQ_<id> == catalog Requires (the re-rooted tree)", 4)
	local flagT = T.tally("economy: sim KEEP_ON_PRESTIGE / COMING_SOON / RESET_LEVEL == catalog KeepOnPrestige / ComingSoon / ResetLevel", 4)
	local foodT = T.tally("economy: sim PLANT_FOOD_<plant> == catalog Effects.Food (Berry Bush .. Starfruit Tree)", 4)
	for _, def in ipairs(TC.Stations) do
		local id = def.Id
		local sp = get("PRICE_" .. id)
		local cp = {}
		for lv = 1, def.MaxLevel do
			cp[lv] = def.Price[lv]
		end
		prices:case(listEq(sp, cp), id .. ": sim " .. show(sp) .. " vs catalog " .. show(cp))
		local caps = {}
		for i, t in ipairs(TIER_IDS) do
			caps[i] = def.TierCaps[t]
		end
		capsT:case(listEq(get("CAPS_" .. id), caps), id .. ": sim " .. show(sim["CAPS_" .. id]) .. " vs " .. show(caps))
		local sr = get("REQ_" .. id)
		reqT:case(type(sr) == "string" and setEq(parseReq(sr), def.Requires), id .. ": sim '" .. tostring(sr) .. "' vs '" .. reqText(def.Requires) .. "'")
		flagT:case((keep[id] == true) == (def.KeepOnPrestige == true) and (soon[id] == true) == (def.ComingSoon == true) and (reset[id] or 0) == (def.ResetLevel or 0), id)
		if def.Kind == "Plant" then
			foodT:case(listEq(get("PLANT_FOOD_" .. id), effectList(def, "Food")), id .. ": sim " .. show(sim["PLANT_FOOD_" .. id]) .. " vs " .. show(effectList(def, "Food")))
		end
	end
	prices:report()
	capsT:report()
	reqT:report()
	flagT:report()
	foodT:report()
	local extra = {}
	for _, name in ipairs(order) do
		local id = name:match("^PRICE_(.+)$") or name:match("^CAPS_(.+)$") or name:match("^REQ_(.+)$") or name:match("^PLANT_FOOD_(.+)$")
		if id and not TC.Get(id) then
			extra[#extra + 1] = id
		end
	end
	T.check(#extra == 0, "economy: the sim prices no station the catalog lacks", table.concat(extra, ", "))

	-- effect tables
	local byId = TC.ById
	local effects = {
		{ "GARDEN_LUCKY", "Garden", "Lucky" }, { "MAGNET_RADIUS", "Collector", "Radius" }, { "MAGNET_PILE_SECONDS", "Collector", "PileSeconds" },
		{ "FEED_SHARE", "Kitchen", "FeedShare" }, { "TRAINING_SLOTS", "Gym", "Slots" }, { "VAULT_PILE_SECONDS", "Vault", "PileSeconds" },
		{ "VAULT_OFFLINE_PERCENT", "Vault", "OfflinePercent" }, { "VAULT_OFFLINE_HOURS", "Vault", "OfflineHours" },
		{ "FUSION_TOKEN_DISCOUNT", "FusionMachine", "TokenDiscount" },
	}
	local effT = T.tally("economy: sim effect tables == catalog Effects (Garden Lucky, Magnet Radius / PileSeconds, FeedShare, Training Slots, Vault, Fusion Machine)", 4)
	for _, e in ipairs(effects) do
		local got = effectList(byId[e[2]], e[3])
		effT:case(listEq(get(e[1]), got), e[1] .. ": sim " .. show(sim[e[1]]) .. " vs " .. show(got))
	end
	effT:case(listEq(sim.FEED_SHARE, TC.FeedShare), "FEED_SHARE vs TycoonCatalog.FeedShare")
	effT:report()
	local hl = {}
	for i, t in ipairs(TC.HouseTiers) do
		hl[i] = t.HomeLevel
	end
	T.check(listEq(get("HOUSE_HOME_LEVEL"), hl), "economy: sim HOUSE_HOME_LEVEL == HouseTiers Home Levels", show(sim.HOUSE_HOME_LEVEL) .. " vs " .. show(hl))
	local p = TC.Prestige
	T.check(get("PRESTIGE_HOME_LEVEL") == p.HomeLevel and near(get("PRESTIGE_MULTIPLIER"), p.IncomeMultiplier)
		and listEq(get("PRESTIGE_GEMS"), { p.GemReward, p.GemRewardStep, p.GemRewardMin })
		and listEq(get("PRESTIGE_GARDEN_SLOTS"), { p.GardenSlotsBase, p.GardenSlotsPerStar, p.GardenSlotsMax })
		and near(get("PRESTIGE_PRICE_STEP"), p.PriceStep),
		"economy: sim PRESTIGE_* == catalog Prestige (Home Level, x1.25 coins, Gems, garden places 3 + 1 per star up to 12, PriceStep 0.5)")
	T.eq(get("OFFLINE_MIN_SECONDS"), TC.OfflineMinSeconds, "economy: sim OFFLINE_MIN_SECONDS == catalog")
	local c = TC.Coins
	T.check(listEq(get("COINS"), { c.MealSeconds, c.GrassFood, c.LuckyMult, c.BaseRadius, c.BasePileSeconds }) and listEq(get("COINS_HEAP_STAGES"), c.HeapStages),
		"economy: sim COINS / COINS_HEAP_STAGES == catalog Coins (MealSeconds, GrassFood, LuckyMult, BaseRadius, BasePileSeconds, HeapStages)", show(sim.COINS))
	T.check(near(get("FEED_BASE"), TC.FeedBase), "economy: sim FEED_BASE == catalog FeedBase")
	local tr = TC.Training
	T.check(listEq(get("TRAINING"), { tr.MaxRank, tr.CostBase, tr.MinutesPerRank }), "economy: sim TRAINING == catalog Training (MaxRank, CostBase, MinutesPerRank)", show(sim.TRAINING))
	local foodsT = T.tally("economy: sim FOOD_<id> == catalog Foods (Price, Xp, CookSeconds, KitchenLevel)")
	for _, f in ipairs(TC.Foods) do
		local got = { f.Price, f.Xp, f.CookSeconds, f.KitchenLevel }
		foodsT:case(listEq(get("FOOD_" .. f.Id), got), f.Id .. ": sim " .. show(sim["FOOD_" .. f.Id]) .. " vs " .. show(got))
	end
	foodsT:report()
	local px = TC.PetXp
	T.check(listEq(get("PET_XP"), { px.MaxLevel, px.Base, px.Exponent, px.Round }), "economy: sim PET_XP == catalog PetXp (MaxLevel 100)", show(sim.PET_XP))
	local tm = TC.TierMultiplier
	T.check(listEq(get("TIER_MULTIPLIER"), { tm.Normal, tm.Golden, tm.Rainbow }), "economy: sim TIER_MULTIPLIER == catalog TierMultiplier (1 / 1.5 / 2.5)")
	local pkInst = K.moduleInstance("shared/PetKeys")
	if pkInst then
		local ok, PK = pcall(require, pkInst)
		if ok and type(PK) == "table" and type(PK.StatMultiplier) == "function" then
			T.check(PK.StatMultiplier("Golden") == tm.Golden and PK.StatMultiplier("Rainbow") == tm.Rainbow and PK.StatMultiplier("Normal") == tm.Normal,
				"economy: ...and agrees with PetKeys.StatMultiplier")
		end
	end

	-- the pet data the sim assumes is the real catalog
	local scale = Config.PetStats.RarityScale
	local scales, caps, twice = {}, {}, {}
	for i, r in ipairs(RARITY_ORDER) do
		scales[i] = scale[r]
		caps[i] = PC.LevelCap(r)
		twice[i] = PC.MaxEvolution(r) == 2 and 1 or 0
	end
	T.check(listEq(get("RARITY_SCALE"), scales), "economy: sim RARITY_SCALE == Config.PetStats.RarityScale", show(sim.RARITY_SCALE) .. " vs " .. show(scales))
	T.check(listEq(get("LEVEL_CAPS"), caps), "economy: sim LEVEL_CAPS == PetCatalog.LevelCap by rarity (100 for every rarity)", show(sim.LEVEL_CAPS) .. " vs " .. show(caps))
	T.check(listEq(get("ROLE_MULT"), { PC.RoleMult.Economy, PC.RoleMult.Combat }), "economy: sim ROLE_MULT == PetCatalog.RoleMult (Economy 1.6, Combat 1)")
	T.check(listEq(get("EVOLUTION_LEVELS"), PC.EvolutionLevels) and listEq(get("EVOLUTION_BOOST"), PC.EvolutionBoost),
		"economy: sim EVOLUTION_LEVELS / EVOLUTION_BOOST == PetCatalog ({20, 50}, {1.25, 1.5})")
	T.check(listEq(get("EVOLVE_TWICE"), twice), "economy: sim EVOLVE_TWICE == PetCatalog.MaxEvolution(rarity) == 2 (Epic and rarer)", show(sim.EVOLVE_TWICE) .. " vs " .. show(twice))
	T.check(PC.LevelBonus == 0.1, "economy: the sim's level factor (1 + 0.1 x (level - 1)) == PetCatalog.LevelBonus")
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
	T.check(listEq(get("PET_ROLLABLE"), rollable), "economy: sim PET_ROLLABLE == rollable pets per rarity in PetCatalog (Common .. Mythic)", show(sim.PET_ROLLABLE) .. " vs " .. show(rollable))
	T.check(listEq(get("PET_ECON_ROLLABLE"), econ), "economy: sim PET_ECON_ROLLABLE == rollable Economy pets per rarity", show(sim.PET_ECON_ROLLABLE) .. " vs " .. show(econ))
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

	-- the sim's formulas == the catalog's on pseudo-random homes
	local M = simModel(sim, order)
	local xpT = T.tally("economy: the sim's XpToNext / FeedXp / FeedPrice / TrainCost / TrainSeconds == the catalog's at every level, machine level and rank")
	for lv = 1, sim.PET_XP[1] do
		xpT:case(TC.XpToNext(lv) == M.xpToNext(lv), "XpToNext " .. lv)
		for ml = 0, 5 do
			xpT:case(TC.FeedXp(lv, ml) == M.feedXp(lv, ml), "FeedXp " .. lv .. " / " .. ml)
		end
		for ri, rarity in ipairs(RARITY_ORDER) do
			xpT:case(TC.FeedPrice(rarity, lv) == M.feedPrice(ri, lv), "FeedPrice " .. rarity .. " " .. lv)
		end
	end
	for r = 1, sim.TRAINING[1] do
		xpT:case(TC.TrainSeconds(r) == M.trainSeconds(r), "TrainSeconds " .. r)
		for ri, rarity in ipairs(RARITY_ORDER) do
			xpT:case(TC.TrainCost(rarity, r) == M.trainCost(ri, r), "TrainCost " .. rarity .. " " .. r)
		end
	end
	xpT:report()
	local rnd = makeRandom(20251014)
	local padT = T.tally("economy: AvailablePads == the sim's pads (ids, next levels, star prices, LegacyPrices, lock reasons) on 300 pseudo-random homes", 3)
	local priceT = T.tally("economy: PriceAt == the sim's price_of (x1.5 ^ stars, LegacyPrices) for every station / level on those homes", 3)
	local homeT = T.tally("economy: FoodOf / LuckyChance / GardenSlots / PileSeconds / ScoopRadius / IncomePerSecond / OfflineEarnings / StationsAfterPrestige == the sim on those homes", 3)
	local tierNames = { "Normal", "Golden", "Rainbow" }
	local tierMults = { 1, 1.5, 2.5 }
	for trial = 1, 300 do
		local st = {}
		for _, id in ipairs(CONTRACT_IDS) do
			if rnd(10) < 7 then
				st[id] = rnd(#sim["PRICE_" .. id] + 1)
			end
		end
		local starsList = { 0, 0, 0, 1, 2, 3, 5 }
		local stars = starsList[rnd(#starsList) + 1]
		local legacyPrices = stars > 0 and rnd(10) < 3
		local legacySlots = nil
		if rnd(3) == 0 then
			legacySlots = rnd(8) + 1
		end
		local h = home({}, stars, { LegacyPrices = legacyPrices or nil, LegacySlots = legacySlots })
		for k, v in pairs(st) do
			h.Stations[k] = v
		end
		local want = M.pads(st, stars, legacyPrices)
		local got = {}
		for _, pad in ipairs(TC.AvailablePads(h)) do
			if pad.StationId ~= "Prestige" then
				got[#got + 1] = pad
			end
		end
		local same = #want == #got
		for i = 1, math.min(#want, #got) do
			local a, b = want[i], got[i]
			same = same and a[1] == b.StationId and a[2] == b.NextLevel and a[3] == b.Price and a[4] == b.Locked
		end
		padT:case(same, "home " .. trial .. " (stars " .. stars .. (legacyPrices and ", legacy prices" or "") .. ")")
		for _, id in ipairs(CONTRACT_IDS) do
			for lvl = 1, #sim["PRICE_" .. id] do
				priceT:case(TC.PriceAt(id, lvl, h) == M.priceAt(id, lvl, stars, legacyPrices), id .. " L" .. lvl .. " home " .. trial)
			end
		end
		-- random garden pets (sorted by the sim's power, best first, like the kid fills the places)
		local pets = {}
		for _ = 1, rnd(15) do
			local ri = rnd(7) + 1
			local ti = rnd(4)
			ti = ti == 0 and 1 or ti
			pets[#pets + 1] = { ri = ri, econ = rnd(2) == 0, level = rnd(sim.PET_XP[1]) + 1, ti = ti, evo = rnd(3) }
		end
		for _, pt in ipairs(pets) do
			pt.power = M.power(pt.ri, pt.econ, pt.level, tierMults[pt.ti], pt.evo)
		end
		table.sort(pets, function(a, b2)
			return a.power > b2.power
		end)
		local entries, powers = {}, {}
		for i, pt in ipairs(pets) do
			entries[i] = { Def = { Rarity = RARITY_ORDER[pt.ri], Role = pt.econ and "Economy" or "Combat" }, Level = pt.level, Tier = tierNames[pt.ti], Stage = pt.evo }
			powers[i] = pt.power
		end
		local incWant = M.income(st, powers, stars, legacySlots)
		local after = TC.StationsAfterPrestige(h.Stations)
		local cleanSt = {}
		for k, v in pairs(st) do
			if v > 0 then
				cleanSt[k] = v
			end
		end
		local checks = {
			{ "FoodOf", TC.FoodOf(h), M.food(st) }, { "LuckyChance", TC.LuckyChance(h), M.lucky(st) },
			{ "GardenSlots", TC.GardenSlots(h), M.slots(stars, legacySlots, st.Garden or 0) }, { "PileSeconds", TC.PileSeconds(h), M.pile(st) },
			{ "ScoopRadius", TC.ScoopRadius(h), M.radius(st) }, { "IncomePerSecond", (TC.IncomePerSecond(h, entries)), incWant },
			{ "OfflineEarnings", (TC.OfflineEarnings(h, 5000, 37.5)), M.offline(st, 5000, 37.5) },
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
	priceT:report()
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
	T.eq(TC.Version, 4, "economy: TycoonCatalog.Version 4 (Phase 4: pets make the money)")
	apiChecks(TC)
	validateChecks(TC)
	if type(PC) == "table" and type(Config) == "table" then
		padChecks(TC)
		coinChecks(TC, PC, Config)
		careChecks(TC, PC)
		mirrorChecks(TC, PC, Config)
		compatChecks(TC, PC)
		simChecks(TC, PC, Config)
	else
		T.fail("economy: PetCatalog and Config are loaded (load_modules)")
	end
	junkChecks(TC)
	layoutChecks(TC, Config)
	T.eq(#game:GetDescendants(), before, "economy: the catalog is pure (no Instances created)")
	K.flushErrors("p2_economy")
end)

return S
