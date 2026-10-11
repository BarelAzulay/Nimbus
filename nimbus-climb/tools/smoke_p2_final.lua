-- smoke_p2_final.lua: the Phase 2 release pass ("final"), loaded by tools/smoke.py in the SERVER world as a pure
-- content scenario (no boot needed):
--   p2final_docs  README.md, the guide of the players and the owner, matches the game it describes:
--                 * the Phase 2 section is there and covers every part the player asked for (claiming with E, buy pads,
--                   the stations, house tiers every 10 Home Levels, Garden, Kitchen + feeding, Gym, Vault + offline
--                   earnings, prestige, fusion after Prestige 1, the Home window, Gems, the Developer Products setup,
--                   the Secret Roulette at the Storm Altar);
--                 * its numbers are the modules' numbers: the station table (one row per TycoonCatalog station: levels,
--                   requirements, first / top price, press incomes and the other effects), the max level per house tier,
--                   the house prices and Home Levels, foods, the Kitchen queue and speed, pet level caps and XP, the Gym,
--                   the Garden multipliers, Vault offline pay, fusion costs and discounts, prestige (Home Level,
--                   multiplier, gem reward, fusion unlock), roulette token / gem prices and odds, the Secret Roulette,
--                   the Config.Gems.Products sample, the developer tool buttons / commands / defaults, the tutorial
--                   rewards and step counts;
--                 * every script of src/ is named in the project layout, the place-file instructions name the Rojo
--                   build and tools/verify_place.py, and every "#anchor" link points at a heading.
--                 A failure says what the README states and what the game has: update README.md (or the module).
-- README.md, DevService.lua and TutorialService.lua are read as text from the working directory (smoke.py /
-- run_checks.sh run from the repo root), like smoke_p2_economy.lua reads tools/sim_tycoon.py. The place file itself is
-- checked by tools/verify_place.py: it is rebuilt at release time, so it may lag behind src/ while people work.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local S = {}

local floor = math.floor

-- this file's folder ("tools/") from the chunk name smoke.py gives it ("=tools/smoke_p2_final.lua")
local HERE = (debug.getinfo(1, "S").source or ""):match("^=(.*)smoke_p2_final%.lua$") or ""

local NUMBER_WORDS = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve" }

----------------------------------------------------------------------------------------------------
-- text helpers
----------------------------------------------------------------------------------------------------
local function readFile(rel)
	local candidates = { rel, HERE .. "../" .. rel, "../" .. rel }
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

local function trim(s)
	return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function flat(s)
	return (tostring(s or ""):gsub("%s+", " "))
end

local function has(text, needle)
	return type(text) == "string" and text:find(needle, 1, true) ~= nil
end

local function commas(n)
	local s = tostring(floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- 6.5 -> "6.5", 1.25 -> "1.25", 40 -> "40", 1000 -> "1,000" (two decimals at most)
local function num(v)
	v = floor((tonumber(v) or 0) * 100 + 0.5) / 100
	if v == floor(v) then
		return commas(v)
	end
	local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

local function price(v)
	if (tonumber(v) or 0) == 0 then
		return "free"
	end
	return commas(v)
end

-- the first number in a table cell ("1,800", "150 tokens", "**60 Gems**")
local function cellNumber(cell)
	local digits = tostring(cell or ""):match("(%d[%d,]*)")
	return digits and tonumber((digits:gsub(",", ""))) or nil
end

local function splitLines(text)
	local lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end
	return lines
end

-- marks every line inside a ``` fence (headings in there are not headings)
local function fenceMap(lines)
	local inside, map = false, {}
	for i, line in ipairs(lines) do
		if line:match("^%s*```") then
			map[i] = true
			inside = not inside
		else
			map[i] = inside
		end
	end
	return map
end

-- the lines from the first heading starting with `prefix` (e.g. "## Tycoon homes") up to the next heading of the same
-- or a higher level, as a list and as one text; nil when there is no such heading
local function section(lines, fences, prefix)
	local level = #(prefix:match("^(#+)") or "#")
	local first, last = nil, #lines
	for i, line in ipairs(lines) do
		if not fences[i] then
			if first == nil then
				if line:sub(1, #prefix) == prefix then
					first = i
				end
			else
				local hashes = line:match("^(#+)%s")
				if hashes and #hashes <= level then
					last = i - 1
					break
				end
			end
		end
	end
	if not first then
		return nil, nil
	end
	local out = {}
	for i = first, last do
		out[#out + 1] = lines[i]
	end
	return out, table.concat(out, "\n")
end

local function cells(line)
	local body = trim(line):gsub("^|", ""):gsub("|$", "")
	local out = {}
	for cell in (body .. "|"):gmatch("([^|]*)|") do
		out[#out + 1] = trim(cell)
	end
	return out
end

local function plain(cell)
	return trim((tostring(cell or ""):gsub("%*%*", ""):gsub("`", "")))
end

-- rows (cell lists) of the markdown table whose header row starts with `header`; nil when there is none
local function tableRows(lines, header)
	for i, line in ipairs(lines) do
		if trim(line):sub(1, #header) == header then
			local rows = {}
			local j = i + 2 -- skip the |---| line
			while lines[j] and lines[j]:match("^%s*|") do
				rows[#rows + 1] = cells(lines[j])
				j = j + 1
			end
			return rows, cells(line)
		end
	end
	return nil
end

local function rowsByName(rows)
	local out = {}
	for _, row in ipairs(rows or {}) do
		out[plain(row[1])] = row
	end
	return out
end

local function show(cell)
	return "'" .. tostring(cell) .. "'"
end

local function requireModule(key)
	local inst = K.moduleInstance(key)
	if not inst then
		return nil, "no ModuleScript " .. key
	end
	local ok, result = pcall(require, inst)
	if not ok or type(result) ~= "table" then
		return nil, tostring(result)
	end
	return result
end

-- rarity ids in Config order
local function rarityIds(Config)
	local out = {}
	for _, r in ipairs(Config.Rarities or {}) do
		out[#out + 1] = r.Id
	end
	return out
end

-- "Common 60 %, Uncommon 28 %, ..." (relative weights as percentages, rarity order)
local function oddsText(Config, odds)
	local total = 0
	for _, w in pairs(odds or {}) do
		total = total + (tonumber(w) or 0)
	end
	local parts = {}
	for _, id in ipairs(rarityIds(Config)) do
		local w = tonumber((odds or {})[id])
		if w and w > 0 and total > 0 then
			parts[#parts + 1] = id .. " " .. num(w / total * 100) .. " %"
		end
	end
	return table.concat(parts, ", ")
end

local function andList(parts)
	if #parts <= 1 then
		return parts[1] or ""
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

----------------------------------------------------------------------------------------------------
-- the Phase 2 section: topics
----------------------------------------------------------------------------------------------------
local TOPICS = {
	{ "claiming a home with E at the gate", { "Claim Home", "press **E**", "Free home" } },
	{ "buy pads", { "buy pad", "hold **E**", "Only you see and use your own pads" } },
	{ "Home Level", { "Home Level" } },
	{ "house tiers every 10 Home Levels", { "every 10 Home Levels", "Cottage", "Villa", "Manor", "Sky Castle" } },
	{ "the Pet Garden", { "Pet Garden", "Place in Garden", "Economy" } },
	{ "the Kitchen and feeding", { "Kitchen", "Feed", "feeding bowl" } },
	{ "the Gym", { "Train in Gym", "Combat" } },
	{ "the Vault and offline earnings", { "Vault", "While you were away" } },
	{ "prestige", { "Prestige", "Starts over", "You keep", "You get" } },
	{ "fusion after Prestige 1", { "Fusion Machine", "Unlocks at Prestige 1", "UPGRADE", "MIX", "Golden", "Rainbow", "hybrid" } },
	{ "the Home window", { "Home window", "Go home", "Collect" } },
	{ "Gems", { "Gems", "Gem packs", "Robux" } },
	{ "the Developer Products setup", { "Developer Products", "Creator Hub", "Config.Gems.Products", "src/shared/Config.lua", "Shut Down All Servers" } },
	{ "the Secret Roulette at the Storm Altar", { "Secret Roulette", "Storm Altar" } },
}

local function checkTopics(p2)
	local f = flat(p2)
	local t = T.tally("docs: the README's Phase 2 section covers every part the player asked for", 6)
	for _, topic in ipairs(TOPICS) do
		for _, word in ipairs(topic[2]) do
			t:case(has(f, word), topic[1] .. ": the section never says " .. show(word))
		end
	end
	t:report()
end

----------------------------------------------------------------------------------------------------
-- stations
----------------------------------------------------------------------------------------------------
local function tierOf(TC, need)
	local tier = TC.HouseTiers[need]
	if type(tier) ~= "table" and type(need) == "number" then
		tier = TC.HouseTiers[need]
	end
	return tier
end

local function expectedNeeds(TC, def)
	local keys = {}
	for key in pairs(def.Requires or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local out = {}
	for _, key in ipairs(keys) do
		local need = def.Requires[key]
		if key == "House" then
			local tier = tierOf(TC, need)
			out[#out + 1] = "the " .. tostring(tier and tier.Name or need)
		elseif key == "Prestige" then
			out[#out + 1] = "Prestige " .. tostring(need)
		elseif key == "HomeLevel" then
			out[#out + 1] = "Home Level " .. tostring(need)
		elseif TC.ById[key] then
			local name = TC.ById[key].Name
			if (tonumber(need) or 1) > 1 then
				out[#out + 1] = name .. " Lv " .. tostring(need)
			else
				out[#out + 1] = name
			end
		end
	end
	if #out == 0 then
		out[1] = "claiming"
	end
	return out
end

local function expectedEffects(TC, def)
	local e1, eN = def.Effects[1] or {}, def.Effects[def.MaxLevel] or {}
	local out = {}
	if def.Kind == "Press" then
		out[#out + 1] = num(e1.Income) .. " -> " .. num(eN.Income) .. " Cash/s"
	elseif def.Kind == "Collector" then
		out[#out + 1] = "+" .. num((e1.Bonus or 0) * 100) .. " % -> +" .. num((eN.Bonus or 0) * 100) .. " % press income"
		out[#out + 1] = "holds " .. commas(e1.FlatCap or 0) .. " + " .. num((e1.CapSeconds or 0) / 60) .. " min of income -> "
			.. commas(eN.FlatCap or 0) .. " + " .. num((eN.CapSeconds or 0) / 60) .. " min"
	elseif def.Kind == "Garden" then
		out[#out + 1] = num(e1.Slots) .. " -> " .. num(eN.Slots) .. " places"
	elseif def.Kind == "Kitchen" then
		out[#out + 1] = "a queue of " .. num(e1.Queue or e1.Slots) .. " -> " .. num(eN.Queue or eN.Slots) .. " dishes"
		out[#out + 1] = "up to " .. num((eN.CookSpeed or 1) / (e1.CookSpeed or 1)) .. "x faster"
	elseif def.Kind == "Gym" then
		out[#out + 1] = num(e1.Slots) .. " -> " .. num(eN.Slots) .. " places"
		out[#out + 1] = num(e1.XpPerMinute) .. " -> " .. num(eN.XpPerMinute) .. " XP a minute"
	elseif def.Kind == "Fusion" then
		local cuts, levels = {}, {}
		for lv = 1, def.MaxLevel do
			local d = (def.Effects[lv] or {}).TokenDiscount or 0
			if d > 0 then
				cuts[#cuts + 1] = "-" .. num(d * 100) .. " %"
				levels[#levels + 1] = tostring(lv)
			end
		end
		if #cuts > 0 then
			out[#out + 1] = table.concat(cuts, " / ") .. " token costs at Lv " .. table.concat(levels, " / ")
		end
	elseif def.Kind == "House" then
		local names = {}
		for _, tier in ipairs(TC.HouseTiers) do
			names[#names + 1] = tier.Name
		end
		out[#out + 1] = table.concat(names, " -> ")
	end
	if def.ComingSoon then
		out[#out + 1] = "Coming soon"
	end
	return out
end

local function checkStations(TC, lines)
	local rows = tableRows(lines, "| Station | What it does |")
	if not T.check(rows ~= nil, "docs: the README has the station table (| Station | What it does | Levels | Needs | Price |)") then
		return
	end
	local byName = rowsByName(rows)
	local t = T.tally("docs: the station table matches TycoonCatalog (one row per station: levels, needs, prices, effects)", 6)
	local known = {}
	for _, def in ipairs(TC.Stations) do
		known[def.Name] = true
		local row = byName[def.Name]
		if t:case(row ~= nil and #row >= 5, def.Name .. ": no row for this station") then
			local max = def.MaxLevel
			t:case(row[3] == tostring(max), def.Name .. ": Levels says " .. show(row[3]) .. ", the catalog has " .. max)
			for _, word in ipairs(expectedNeeds(TC, def)) do
				t:case(has(row[4], word), def.Name .. ": Needs says " .. show(row[4]) .. " but the catalog needs " .. show(word))
			end
			local want = price(def.Price[1])
			if max > 1 then
				want = want .. " -> " .. price(def.Price[max])
			end
			t:case(row[5] == want, def.Name .. ": the price column says " .. show(row[5]) .. ", the catalog " .. show(want))
			for _, effect in ipairs(expectedEffects(TC, def)) do
				t:case(has(row[2], effect), def.Name .. ": " .. show(row[2]) .. " should say " .. show(effect))
			end
		end
	end
	for _, row in ipairs(rows) do
		t:case(known[plain(row[1])] == true, "the row " .. show(plain(row[1])) .. " is not a TycoonCatalog station")
	end
	t:report(#rows .. " rows")
end

----------------------------------------------------------------------------------------------------
-- house tiers
----------------------------------------------------------------------------------------------------
local TIER_ROWS = {
	{ "Cloud Press 1 and 2", { "Press1", "Press2" } },
	{ "Cloud Press 3", { "Press3" } },
	{ "Cloud Press 4", { "Press4" } },
	{ "Collector", { "Collector" } },
	{ "Pet Garden", { "Garden" } },
	{ "Kitchen, Gym, Vault", { "Kitchen", "Gym", "Vault" } },
	{ "Fusion Machine", { "FusionMachine" } },
	{ "Decor", { "DecorLamps", "DecorFence", "DecorFlowers", "DecorBanners", "DecorPodium" } },
	{ "Fountain", { "DecorFountain" } },
}

local function checkTiers(TC, lines, houseText)
	local rows, header = tableRows(lines, "| Max level with the")
	if not T.check(rows ~= nil, "docs: the README has the house tier table (| Max level with the ... |)") then
		return
	end
	local t = T.tally("docs: the house tier table matches TycoonCatalog (max station level per house)", 6)
	for i, tier in ipairs(TC.HouseTiers) do
		t:case(header[i + 1] == tier.Name, "column " .. (i + 1) .. " is " .. show(header[i + 1]) .. ", the tier " .. show(tier.Name))
	end
	local byName = rowsByName(rows)
	local covered = {}
	for _, spec in ipairs(TIER_ROWS) do
		local row = byName[spec[1]]
		if t:case(row ~= nil, "no row " .. show(spec[1])) then
			for _, id in ipairs(spec[2]) do
				local def = TC.ById[id]
				covered[id] = true
				if t:case(def ~= nil, spec[1] .. ": " .. id .. " is not a station") then
					for i, tier in ipairs(TC.HouseTiers) do
						local cap = def.TierCaps and def.TierCaps[tier.Id] or 0
						local want = cap > 0 and tostring(cap) or "-"
						t:case(row[i + 1] == want, spec[1] .. " with the " .. tier.Name .. ": the README says " .. show(row[i + 1])
							.. ", " .. id .. " allows " .. want)
					end
				end
			end
		end
	end
	for _, def in ipairs(TC.Stations) do
		if def.Kind ~= "House" and def.Kind ~= "Arena" then
			t:case(covered[def.Id] == true, def.Id .. " (" .. def.Name .. ") has no row in the house tier table")
		end
	end
	-- the house prices and Home Levels in the text
	local f = flat(houseText)
	local house = TC.ById.House
	t:case(has(f, "**" .. TC.HouseTiers[1].Name .. "** (" .. commas(house.Price[1]) .. " Cash)"),
		"the text should name the " .. TC.HouseTiers[1].Name .. " at " .. commas(house.Price[1]) .. " Cash")
	for i = 2, #TC.HouseTiers do
		local tier = TC.HouseTiers[i]
		t:case(has(f, "**" .. tier.Name .. "**") and has(f, "Home Level " .. tier.HomeLevel .. " (" .. commas(house.Price[i])),
			"the text should say the " .. tier.Name .. " needs Home Level " .. tier.HomeLevel .. " (" .. commas(house.Price[i]) .. ")")
		local gate = house.LevelRequires and house.LevelRequires[i]
		t:case(gate == nil or gate.HomeLevel == tier.HomeLevel, tier.Name .. ": HouseTiers and the House pad disagree on its Home Level")
	end
	t:report()
end

----------------------------------------------------------------------------------------------------
-- Kitchen, feeding, pet levels, Gym, Garden
----------------------------------------------------------------------------------------------------
local function checkCare(TC, PC, Config, lines, kitchenText, gymText, gardenText)
	local t = T.tally("docs: the Kitchen, feeding, Gym and Garden numbers match TycoonCatalog / PetCatalog", 6)
	local rows = tableRows(lines, "| Food | Cost | XP |")
	if t:case(rows ~= nil, "no food table (| Food | Cost | XP | ...)") then
		local byName = rowsByName(rows)
		t:case(#rows == #TC.Foods, "the food table has " .. #rows .. " rows, TycoonCatalog " .. #TC.Foods .. " foods")
		for _, food in ipairs(TC.Foods) do
			local row = byName[food.Name]
			if t:case(row ~= nil, "no row for " .. food.Name) then
				t:case(row[2] == commas(food.Price) .. " Cash", food.Name .. ": cost " .. show(row[2]) .. " vs " .. commas(food.Price))
				t:case(row[3] == num(food.Xp), food.Name .. ": XP " .. show(row[3]) .. " vs " .. num(food.Xp))
				t:case(row[4] == num(food.CookSeconds) .. " s", food.Name .. ": cook time " .. show(row[4]) .. " vs " .. num(food.CookSeconds))
				t:case(row[5] == num(food.KitchenLevel), food.Name .. ": Kitchen level " .. show(row[5]) .. " vs " .. num(food.KitchenLevel))
			end
		end
	end
	local kitchen = TC.ById.Kitchen
	local k1, k2, kN = kitchen.Effects[1], kitchen.Effects[2] or kitchen.Effects[1], kitchen.Effects[kitchen.MaxLevel]
	local kf = flat(kitchenText)
	local queue = "(" .. num(k1.Queue or k1.Slots) .. " dishes at Kitchen level 1, up to " .. num(kN.Queue or kN.Slots) .. ")"
	t:case(has(kf, queue), "the Kitchen text should say " .. show(queue))
	local speed = "x" .. num(k2.CookSpeed or 1) .. " at level 2 up to x" .. num(kN.CookSpeed or 1) .. " at level " .. kitchen.MaxLevel
	t:case(has(kf, speed), "the Kitchen text should say " .. show(speed))
	local firstXp = type(TC.XpToNext) == "function" and TC.XpToNext(1) or nil
	t:case(firstXp ~= nil and has(kf, "level 1 -> 2 takes " .. num(firstXp) .. " XP"), "the feeding text should say level 1 -> 2 takes "
		.. tostring(firstXp) .. " XP")
	if type(PC.LevelFactor) == "function" then
		local step = (PC.LevelFactor(2) - PC.LevelFactor(1)) * 100
		t:case(has(kf, "every level adds " .. num(step) .. " %"), "the feeding text should say every level adds " .. num(step) .. " %")
	end
	if type(PC.LevelCap) == "function" then
		local parts = {}
		for _, id in ipairs(rarityIds(Config)) do
			parts[#parts + 1] = id .. " " .. tostring(PC.LevelCap(id))
		end
		local caps = table.concat(parts, ", ")
		t:case(has(kf, caps), "the level caps should read " .. show(caps))
	end
	-- the Gym
	local gym = TC.ById.Gym
	local g1, gN = gym.Effects[1], gym.Effects[gym.MaxLevel]
	local gymLine = num(g1.XpPerMinute) .. " XP a minute at Gym level 1, up to " .. num(gN.XpPerMinute) .. " at level " .. gym.MaxLevel
		.. ", with " .. num(g1.Slots) .. " to " .. num(gN.Slots) .. " places"
	t:case(has(flat(gymText), gymLine), "the Gym text should say " .. show(gymLine))
	-- the Garden
	local gf = flat(gardenText)
	local scale = (Config.PetStats or {}).RarityScale or {}
	local ids = rarityIds(Config)
	local scaleText = "(" .. ids[1] .. " x" .. num(scale[ids[1]] or 1) .. " up to " .. ids[#ids] .. " x" .. num(scale[ids[#ids]] or 1) .. ")"
	t:case(has(gf, scaleText), "the Garden text should say " .. show(scaleText))
	local mult = TC.TierMultiplier or {}
	local tierText = "(Golden x" .. num(mult.Golden or 1.5) .. ", Rainbow x" .. num(mult.Rainbow or 2.5) .. ")"
	t:case(has(gf, tierText), "the Garden text should say " .. show(tierText))
	local garden = TC.ById.Garden
	local slots = "Garden level: " .. num(garden.Effects[1].Slots) .. " to " .. num(garden.Effects[garden.MaxLevel].Slots)
	t:case(has(gf, slots), "the Garden text should say " .. show(slots))
	t:report()
end

----------------------------------------------------------------------------------------------------
-- the Vault
----------------------------------------------------------------------------------------------------
local function checkVault(TC, lines, vaultText)
	local t = T.tally("docs: the Vault table and offline earnings match TycoonCatalog", 6)
	local vault = TC.ById.Vault
	local rows, header = tableRows(lines, "| Vault level |")
	if t:case(rows ~= nil, "no Vault table (| Vault level | 1 | 2 | ...)") then
		t:case(#header == vault.MaxLevel + 1, "the Vault table has " .. (#header - 1) .. " level columns, the Vault " .. vault.MaxLevel .. " levels")
		local byName = rowsByName(rows)
		local share, hours = byName["Share of your income"], byName["For up to"]
		if t:case(share ~= nil and hours ~= nil, "the Vault table needs the rows 'Share of your income' and 'For up to'") then
			for lv = 1, vault.MaxLevel do
				local e = vault.Effects[lv]
				t:case(share[lv + 1] == num(e.OfflinePercent * 100) .. " %", "Vault " .. lv .. ": share " .. show(share[lv + 1])
					.. " vs " .. num(e.OfflinePercent * 100) .. " %")
				t:case(hours[lv + 1] == num(e.OfflineHours) .. " h", "Vault " .. lv .. ": hours " .. show(hours[lv + 1]) .. " vs " .. num(e.OfflineHours))
			end
		end
	end
	local f = flat(vaultText)
	local minText = "absences under " .. num((TC.OfflineMinSeconds or 120) / 60) .. " minutes"
	t:case(has(f, minText), "the Vault text should say " .. show(minText))
	local v1, vN = vault.Effects[1], vault.Effects[vault.MaxLevel]
	local capText = "from +" .. commas(v1.FlatCap) .. " and " .. num(v1.CapSeconds / 60) .. " more minutes of income at level 1 to +"
		.. commas(vN.FlatCap) .. " and " .. num(vN.CapSeconds / 60) .. " more minutes at level " .. vault.MaxLevel
	t:case(has(f, capText), "the Vault text should say " .. show(capText))
	t:report()
end

----------------------------------------------------------------------------------------------------
-- prestige + fusion
----------------------------------------------------------------------------------------------------
local function checkPrestige(TC, prestigeText)
	local t = T.tally("docs: the prestige rules match TycoonCatalog.Prestige", 6)
	local P = TC.Prestige
	local f = flat(prestigeText)
	local castle = TC.HouseTiers[P.House]
	local need = "**Home Level " .. P.HomeLevel .. " and the " .. tostring(castle and castle.Name or P.House) .. "**"
	t:case(has(f, need), "the text should say " .. show(need))
	t:case(has(f, "Reach Home Level " .. P.HomeLevel), "the text should quote the pad's lock 'Reach Home Level " .. P.HomeLevel .. "'")
	local m = P.IncomeMultiplier
	t:case(has(f, "**x" .. num(m) .. " income** per star"), "the text should say x" .. num(m) .. " income per star")
	local function trunc2(v)
		return string.format("%.2f", floor(v * 100 + 1e-9) / 100)
	end
	local compound = "x" .. trunc2(m ^ 2) .. " at 2 stars, x" .. trunc2(m ^ 3) .. " at 3"
	t:case(has(f, compound), "the text should say " .. show(compound))
	local gems = "(" .. P.GemReward .. " for the first prestige, " .. P.GemRewardStep .. " fewer for each later one, never under "
		.. P.GemRewardMin .. ")"
	t:case(has(f, gems), "the text should say " .. show(gems))
	if type(TC.PrestigeGems) == "function" then
		t:case(TC.PrestigeGems(1) == P.GemReward and TC.PrestigeGems(2) == P.GemReward - P.GemRewardStep
			and TC.PrestigeGems(1000) == P.GemRewardMin, "PrestigeGems follows GemReward / GemRewardStep / GemRewardMin as documented")
	end
	t:case(has(f, "at Prestige " .. P.FusionUnlock .. " the **Fusion Machine** pad"), "the text should say the Fusion Machine pad comes at Prestige "
		.. P.FusionUnlock)
	t:report()
end

local function checkFusion(TC, Config, lines, fusionText)
	local t = T.tally("docs: the Fusion Machine table and rules match TycoonCatalog.Fusion", 6)
	local F = TC.Fusion
	local rows = tableRows(lines, "| Rarity | Upgrade to Golden |")
	if t:case(rows ~= nil, "no fusion cost table (| Rarity | Upgrade to Golden | Golden to Rainbow | Mix |)") then
		local byName = rowsByName(rows)
		for _, id in ipairs(rarityIds(Config)) do
			local row = byName[id]
			local up, mix = F.Upgrade[id], F.Mix[id]
			if up and mix and t:case(row ~= nil, "no row for " .. id) then
				t:case(cellNumber(row[2]) == up.Golden.Tokens, id .. ": Golden " .. show(row[2]) .. " vs " .. tostring(up.Golden.Tokens) .. " tokens")
				t:case(cellNumber(row[3]) == up.Rainbow.Tokens, id .. ": Rainbow " .. show(row[3]) .. " vs " .. tostring(up.Rainbow.Tokens) .. " tokens")
				if mix.Gems then
					t:case(cellNumber(row[4]) == mix.Gems and has(row[4], "Gems"), id .. ": Mix " .. show(row[4]) .. " vs " .. mix.Gems .. " Gems")
				else
					t:case(cellNumber(row[4]) == mix.Tokens and not has(row[4], "Gems"), id .. ": Mix " .. show(row[4]) .. " vs "
						.. tostring(mix.Tokens) .. " tokens")
				end
			end
		end
	end
	local f = flat(fusionText)
	local mult = TC.TierMultiplier or {}
	t:case(has(f, (F.Copies or 3) .. " copies of the same pet"), "the text should say " .. (F.Copies or 3) .. " copies of the same pet")
	t:case(has(f, "**Golden** (x" .. num(mult.Golden) .. " stats"), "the text should say Golden is x" .. num(mult.Golden))
	t:case(has(f, "**Rainbow** (x" .. num(mult.Rainbow)), "the text should say Rainbow is x" .. num(mult.Rainbow))
	local machine = TC.ById.FusionMachine
	local cuts = {}
	for lv = 1, machine.MaxLevel do
		local d = (machine.Effects[lv] or {}).TokenDiscount or 0
		if d > 0 then
			cuts[#cuts + 1] = num(d * 100) .. " %"
		end
	end
	local cutText = "take " .. andList(cuts) .. " off the token costs"
	t:case(has(f, cutText), "the text should say " .. show(cutText))
	t:case(has(f, "Unlocks at Prestige " .. TC.Prestige.FusionUnlock), "the text should quote the lock 'Unlocks at Prestige "
		.. TC.Prestige.FusionUnlock .. "'")
	t:report()
end

----------------------------------------------------------------------------------------------------
-- roulettes, Gems, the Secret Roulette, the Developer Products sample
----------------------------------------------------------------------------------------------------
local function checkGems(Config, PC, lines, gemsText, ownerText, text)
	local t = T.tally("docs: roulette prices / odds, Gems, the Secret Roulette and the products sample match Config", 6)
	local G = Config.Gems or {}
	local gemPrices = G.RouletteGemPrices or {}
	local SR = G.SecretRoulette or {}
	local rows = tableRows(lines, "| Roulette | Price |")
	if t:case(rows ~= nil, "no roulette table (| Roulette | Price | Odds ... |)") then
		local byName = rowsByName(rows)
		for _, r in ipairs(Config.Roulettes or {}) do
			local row = byName[r.Id]
			if t:case(row ~= nil, "no roulette row for " .. r.Id) then
				local want = commas(r.Price) .. " tokens"
				if gemPrices[r.Id] then
					want = want .. " (or " .. commas(gemPrices[r.Id]) .. " Gems)"
				end
				t:case(row[2] == want, r.Id .. ": price " .. show(row[2]) .. " vs " .. show(want))
				t:case(row[3] == oddsText(Config, r.Odds), r.Id .. ": odds " .. show(row[3]) .. " vs " .. show(oddsText(Config, r.Odds)))
			end
		end
		local secretRow = nil
		for _, row in ipairs(rows) do
			if plain(row[1]):sub(1, #tostring(SR.Id or "Secret")) == tostring(SR.Id or "Secret") then
				secretRow = row
			end
		end
		if t:case(secretRow ~= nil, "no roulette row for the Secret Roulette") then
			t:case(secretRow[2] == commas(SR.GemPrice or 0) .. " Gems only", "Secret: price " .. show(secretRow[2]) .. " vs "
				.. commas(SR.GemPrice or 0) .. " Gems")
			t:case(secretRow[3] == oddsText(Config, SR.Odds), "Secret: odds " .. show(secretRow[3]) .. " vs " .. show(oddsText(Config, SR.Odds)))
		end
	end
	-- the Gems section
	local f = flat(gemsText)
	local spins = {}
	for _, r in ipairs(Config.Roulettes or {}) do
		if gemPrices[r.Id] then
			spins[#spins + 1] = r.Id .. " " .. commas(gemPrices[r.Id])
		end
	end
	local spinText = andList(spins) .. " Gems a spin"
	t:case(has(f, spinText), "the Gems text should say " .. show(spinText))
	t:case(has(f, commas(SR.GemPrice or 0) .. " Gems a spin, **" .. oddsText(Config, SR.Odds) .. "**"),
		"the Gems text should give the Secret Roulette's price and odds (" .. commas(SR.GemPrice or 0) .. " Gems, " .. oddsText(Config, SR.Odds) .. ")")
	for _, def in ipairs(PC.Pets or {}) do
		if def.Rarity == "Secret" then
			t:case(has(f, def.Name), "the Gems text should list the Secret pet " .. show(def.Name))
		end
	end
	if type(PC.TotalCount) == "function" then
		t:case(has(text, "**" .. PC.TotalCount() .. " pets**"), "the README should count " .. PC.TotalCount() .. " pets")
	end
	-- the Developer Products sample in the owner's setup
	local sample = {}
	for gems, name in tostring(ownerText or ""):gmatch("Gems = (%d+), Name = \"([^\"]+)\"") do
		sample[#sample + 1] = { Gems = tonumber(gems), Name = name }
	end
	local products = G.Products or {}
	t:case(#sample == #products, "the Config.Gems.Products sample lists " .. #sample .. " packs, Config " .. #products)
	for i, p in ipairs(products) do
		local s = sample[i]
		t:case(s ~= nil and s.Gems == p.Gems and s.Name == p.Name, "pack " .. i .. ": the sample says " .. (s and (s.Gems .. " " .. show(s.Name)) or "nothing")
			.. ", Config " .. tostring(p.Gems) .. " " .. show(p.Name))
	end
	t:case(has(ownerText, "`0`") and has(flat(ownerText), "not created yet"), "the owner's setup should explain that id 0 means not created yet")
	t:report()
end

----------------------------------------------------------------------------------------------------
-- developer tools
----------------------------------------------------------------------------------------------------
local function checkDev(Config, Theme, lines, devSource)
	local t = T.tally("docs: the developer tools (buttons, commands, settings) match Config.Dev / DevService", 6)
	local D = Config.Dev or {}
	local rows = tableRows(lines, "| Setting | Default | Meaning |")
	if t:case(rows ~= nil, "no developer settings table") then
		local byName = rowsByName(rows)
		for _, key in ipairs({ "Enabled", "AllowInStudio", "StudioAutoGrant", "GrantTokens", "GrantCash", "GrantGems", "MaxTokensPerCommand" }) do
			local row = byName[key]
			if D[key] ~= nil and t:case(row ~= nil, "no settings row for " .. key) then
				t:case(plain(row[2]) == tostring(D[key]), key .. ": the README says " .. show(row[2]) .. ", Config " .. tostring(D[key]))
			end
		end
	end
	local short = function(n)
		if type(Theme) == "table" and type(Theme.ShortNumber) == "function" then
			local ok, s = pcall(Theme.ShortNumber, n)
			if ok and type(s) == "string" then
				return s
			end
		end
		return commas(n)
	end
	local buttons = tableRows(lines, "| Button | What it does |")
	if t:case(buttons ~= nil, "no DEV panel button table") then
		local byName = rowsByName(buttons)
		for _, spec in ipairs({ { "GrantTokens", "tokens" }, { "GrantCash", "Cash" }, { "GrantGems", "Gems" } }) do
			local n = tonumber(D[spec[1]])
			if n then
				local label = "+" .. short(n) .. " " .. spec[2]
				t:case(byName[label] ~= nil, "the DEV panel button " .. show(label) .. " (Config.Dev." .. spec[1] .. ") has no row")
			end
		end
	end
	local commands = tableRows(lines, "| Command | What it does |")
	local list = devSource and devSource:match("DevService%.Commands%s*=%s*(%b{})")
	if t:case(commands ~= nil and list ~= nil, "the chat command table and DevService.Commands are readable") then
		local firsts = {}
		for _, row in ipairs(commands) do
			firsts[#firsts + 1] = row[1]
		end
		local all = table.concat(firsts, " ")
		for name in list:gmatch("\"([%w_]+)\"") do
			t:case(has(all, "`/" .. name), "the chat command /" .. name .. " has no row")
		end
	end
	t:report()
end

----------------------------------------------------------------------------------------------------
-- tutorial
----------------------------------------------------------------------------------------------------
local function checkTutorial(Config, Steps, tutorialText, tutorialSource)
	local t = T.tally("docs: the tutorial paragraph matches TutorialSteps / Config.Tutorial / TutorialService", 6)
	local f = flat(tutorialText)
	local tut = Config.Tutorial or {}
	t:case(has(f, "**" .. commas(tut.GiftTokens or 0) .. " Cloud Tokens**"), "the gift of " .. tostring(tut.GiftTokens) .. " Cloud Tokens")
	local finish = (tut.FinishReward or {}).Tokens or 0
	t:case(has(f, "**" .. commas(finish) .. " Cloud Tokens**"), "the finish reward of " .. tostring(finish) .. " Cloud Tokens")
	local cash = tutorialSource and tonumber(tutorialSource:match("local HOME_FINISH_CASH = (%d+)"))
	if t:case(cash ~= nil, "TutorialService.lua has HOME_FINISH_CASH") then
		t:case(has(f, "**" .. commas(cash) .. " Cash**"), "the home chapter reward of " .. commas(cash) .. " Cash")
	end
	local counts = {}
	for _, step in ipairs((type(Steps) == "table" and Steps.Steps) or {}) do
		local c = step.Chapter or 1
		counts[c] = (counts[c] or 0) + 1
	end
	if t:case(counts[1] ~= nil and counts[2] ~= nil, "TutorialSteps has chapters 1 and 2") then
		local w1, w2 = NUMBER_WORDS[counts[1]], NUMBER_WORDS[counts[2]]
		t:case(w1 ~= nil and has(f, w1 .. " short steps"), "chapter 1 has " .. counts[1] .. " steps: '" .. tostring(w1) .. " short steps'")
		t:case(w2 ~= nil and has(f, string.lower(w2) .. " steps"), "chapter 2 has " .. counts[2] .. " steps: '" .. tostring(w2 and string.lower(w2)) .. " steps'")
	end
	t:report()
end

----------------------------------------------------------------------------------------------------
-- project layout, place-file instructions, anchors
----------------------------------------------------------------------------------------------------
local function scriptNames()
	local names = {}
	if type(Mock) ~= "table" or type(Mock.GetPath) ~= "function" or type(ROOTS) ~= "table" then
		return names
	end
	for _, top in ipairs({ "shared", "server", "client" }) do
		local path = ROOTS[top]
		local root = path and Mock.GetPath(path)
		if root then
			for _, inst in ipairs(root:GetDescendants()) do
				if inst:IsA("ModuleScript") then
					names[#names + 1] = { Name = inst.Name, Kind = "Module" }
				elseif inst:IsA("LocalScript") then
					names[#names + 1] = { Name = inst.Name, Kind = "client" }
				elseif inst:IsA("Script") then
					names[#names + 1] = { Name = inst.Name, Kind = "server" }
				end
			end
		end
	end
	return names
end

local function checkLayout(layoutText, placeText)
	local t = T.tally("docs: the project layout names every script of src/, the place-file steps name Rojo + verify_place.py", 6)
	local names = scriptNames()
	t:case(#names >= 40, "found " .. #names .. " scripts under the src mounts")
	for _, entry in ipairs(names) do
		local want = entry.Name
		if entry.Kind ~= "Module" then
			want = entry.Name .. "." .. entry.Kind .. ".lua"
		else
			local stripped = want:gsub("Service$", ""):gsub("Controller$", "")
			if stripped ~= "" then
				want = stripped
			end
			if want:match("^Course") then
				want = "Course"
			end
		end
		local found = layoutText ~= nil and (layoutText:find("%f[%w]" .. want:gsub("%.", "%%.") .. "%f[%W]") ~= nil)
		t:case(found, entry.Name .. ": the project layout should name " .. show(want))
	end
	t:case(has(placeText, "rojo build default.project.json -o play/NimbusClimb.rbxlx"), "the place-file section should give the Rojo build command")
	t:case(has(placeText, "tools/verify_place.py"), "the place-file section should name tools/verify_place.py")
	t:report(#names .. " scripts")
end

local function slug(heading)
	local s = heading:lower():gsub("[^%w%s%-_]", ""):gsub("%s", "-")
	return s
end

local function checkAnchors(lines, fences, text)
	local t = T.tally("docs: every #anchor link in README.md points at a heading", 6)
	local slugs = {}
	for i, line in ipairs(lines) do
		local title = (not fences[i]) and line:match("^#+%s+(.-)%s*$")
		if title then
			slugs[slug(title)] = true
		end
	end
	local n = 0
	for anchor in text:gmatch("%]%(#([^%)]+)%)") do
		n = n + 1
		t:case(slugs[anchor] == true, "#" .. anchor .. " is not a heading")
	end
	t:case(n >= 5, "found " .. n .. " anchor links")
	t:report(n .. " links")
end

----------------------------------------------------------------------------------------------------
-- scenario
----------------------------------------------------------------------------------------------------
S.p2final_docs = guarded("p2final_docs", function()
	local Config = K.config()
	local PC = K.M["shared/PetCatalog"]
	local Theme = K.M["shared/Theme"]
	local Steps = K.M["shared/TutorialSteps"]
	local before = #game:GetDescendants()
	local text, where = readFile("README.md")
	if not T.check(text ~= nil, "docs: README.md is readable", where) then
		return
	end
	local TC, err = requireModule("shared/TycoonCatalog")
	if not T.check(TC ~= nil, "docs: shared/TycoonCatalog loads", err) then
		return
	end
	if not T.check(type(Config) == "table" and type(PC) == "table", "docs: Config and PetCatalog are loaded (load_modules)") then
		return
	end
	local lines = splitLines(text)
	local fences = fenceMap(lines)
	local function sub(prefix)
		local _, body = section(lines, fences, prefix)
		T.check(body ~= nil, "docs: README.md has the heading " .. show(prefix .. " ..."))
		return body or ""
	end
	local p2 = sub("## Tycoon homes")
	if p2 ~= "" then
		checkTopics(p2)
	end
	checkStations(TC, lines)
	checkTiers(TC, lines, sub("### The house"))
	checkCare(TC, PC, Config, lines, sub("### The Kitchen"), sub("### The Gym"), sub("### The Pet Garden"))
	checkVault(TC, lines, sub("### The Vault"))
	checkPrestige(TC, sub("### Prestige"))
	checkFusion(TC, Config, lines, sub("### The Fusion Machine"))
	checkGems(Config, PC, lines, sub("### Gems"), sub("### Selling Gems"), text)
	checkDev(Config, Theme, lines, (readFile("src/server/Services/DevService.lua")))
	checkTutorial(Config, Steps, sub("## First steps"), (readFile("src/server/Services/TutorialService.lua")))
	checkLayout(sub("## Project layout"), sub("## Rebuilding the place file"))
	checkAnchors(lines, fences, text)
	T.eq(#game:GetDescendants(), before, "docs: the checks are pure (no Instances created)")
	K.flushErrors("p2final_docs")
end)

return S
