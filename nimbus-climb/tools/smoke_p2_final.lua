-- smoke_p2_final.lua: the Phase 2 release pass ("final"), loaded by tools/smoke.py in the SERVER world as a pure
-- content scenario (no boot needed):
--   p2final_docs  README.md, the guide of the players and the owner, matches the game it describes:
--                 * the "## Tycoon homes" section is there and covers every part the player asked for (claiming with E,
--                   buy pads, the stations, house tiers every 10 Home Levels, the Pet Garden and its coins, the Food
--                   Machine + feeding, EVOLVE, the Training Place, the Vault + offline coins, prestige, homes from before
--                   Phase 4, fusion after Prestige 1, the Home window + portal, Gems, the Developer Products setup,
--                   the Secret Roulette at the Storm Altar);
--                 * its numbers are the modules' numbers: the station table (one row per TycoonCatalog station: levels,
--                   requirements, first / top price and the effects), the max level per house tier, the house prices
--                   and Home Levels, the Vault's piles and offline pay, fusion costs and discounts, prestige (Home Level,
--                   multiplier, gem reward, fusion unlock), roulette token / gem prices and odds, the Secret Roulette,
--                   the Config.Gems.Products sample, the developer tool buttons / commands / defaults, the tutorial
--                   rewards and step counts;
--                 * every script of src/ is named in the project layout, the place-file instructions name the Rojo
--                   build and tools/verify_place.py, and every "#anchor" link points at a heading.
--                 * Phase 3 (pet battles): the "## Pet battles" section covers what the player asked for (the arena
--                   by the plaza bridge and the home Arena Gate, the Team screen and slot 4 at Prestige 1, ATTACK /
--                   RETREAT / SPECIAL with F / R / 1-4 and touch, RETREAT's auto resume, Trials 1-30, duels by
--                   challenge and queue, practice duels, trophies and the leaderboard, Boss Raids and dodging, Double
--                   Rewards, the Boss Raid pets, elements and synergy, /raid + Start Boss Raid, Studio's Clients and
--                   Servers) and its numbers are BattleCatalog's (team size, RETREAT, specials, synergy, the Trial
--                   chapters / rewards / first-clear Gems, the trophy table, BattleService's fair-play constants, the
--                   raid schedule, the boss table, enrage and time limit, the reward tiers, Double Rewards) and
--                   BattleController's key bindings; the rest of the README no longer calls battles "coming", counts
--                   the Index pets and gives tutorial chapter 3's step count and reward.
--                 * Phase 4 (pets make the money): checkPhase4 reads every number from the catalogs: the "What's new in
--                   phase 4" bullets, the Pet Garden (3 places + 1 per Prestige, a meal every 8 s, the coin example,
--                   Economy x1.6, Lucky coins per Garden level, scoop radius, pile minutes, owner-only scooping), the Food
--                   Machine (FeedShare, the price rule and examples, MAX_FEEDS, leftovers), levels to 100 with the XP
--                   curve and totals, XP from every fight, evolution (20 / 50, +25 % / +50 %, which rarities evolve
--                   twice), the Training Place (skills, cost 300 x N x N x rarity, N minutes, spots, the lock), "Homes
--                   from before Phase 4" (plants, kept places and prices, leftovers, the Welcome pile, the toasts), the
--                   Champion Ring table (Cash floor and XP per round, bosses every 10th, rarity bands, record x3, boss
--                   tokens), the NPC table against NpcDialog, tutorial chapters 2 and 4, the controls, pet cards,
--                   /petlevel, the owner's "Publish, then Migrate to Latest Update" and no stale Phase 2-3 wording.
--                   The Phase 2 checks follow the Phase 4 catalog (food plants, Coin Magnet, Food Machine, Training
--                   Place, the Vault's bigger piles, star prices and the Welcome-back toast quoted from TycoonService).
--                 * Phase 5 (the Big Sky Update): checkPhase5 reads the "## Phase 5: the Big Sky Update" bullets (teams of 3
--                   and the battle keys F / E / Q / Tab / Shift + 1 / 2 for the helpers, Supporters, the Dungeon's floors
--                   and party size, the Gate Court and the obby level picker, the Berry Farm / berries / Feed, roaming
--                   pets and Cloud Cash, 11 stations, evolved looks, followers, the sky, stamina from Config.Physics, the
--                   loading screen / main menu / settings), the owner checklist "## Phase 5: owner checklist" numbered
--                   0-7 exactly like ARCHITECTURE_V3.md 10.6 with one needle per step (rojo serve, Migrate to Latest
--                   Update, Bulk Import, Config.Audio, Config.Icons, ShadowMap, Developer Products, Output) plus the
--                   six Config.Sky.Faces keys and the branding/sky images, the /berries [n] and /menu rows, and that no
--                   "4th slot opens at Prestige" line is left. The Phase 2-4 checks follow the Phase 5 catalogs: 11
--                   stations (TycoonCatalog Version 5), the Berry Farm house caps, Cloud Cash and berries in the garden
--                   and Food Machine texts, the fighter / helper battle rules and keys (BattleController's bindings),
--                   the Dungeon (floors, loot, first clears) instead of the Trials, homes from older versions.
--                 A failure says what the README states and what the game has: update README.md (or the module).
-- README.md, DevService.lua, TutorialService.lua, TycoonService.lua, PetCareService.lua, HomeFx.lua, MenuController.lua,
-- BattleService.lua and BattleController.lua are read as text from the working directory (smoke.py /
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
-- PetCatalog.EvolutionBonusOf(stage) as text: 1.5 -> "1.5", 1.875 -> "1.875"
local function bonusText(PC, stage)
	local v = type(PC.EvolutionBonusOf) == "function" and tonumber(PC.EvolutionBonusOf(stage)) or 1
	local s = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

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
	{ "buy pads", { "buy pad", "hold **E**", "Only you see and use your own pads", "free Pet Garden" } },
	{ "Home Level", { "Home Level" } },
	{ "house tiers every 10 Home Levels", { "every 10 Home Levels", "Cottage", "Villa", "Manor", "Sky Castle" } },
	{ "the Pet Garden and its Cloud Cash", { "Pet Garden", "Put a pet here", "Economy", "Cloud Cash", "Food Bowl", "Only you can scoop" } },
	{ "the Berry Farm and the Berry Basket", { "Berry Farm", "Berry Basket", "berries" } },
	{ "the Food Machine and feeding", { "Food Machine", "*Feed pets*", "**Feed**" } },
	{ "evolution", { "EVOLVE", "Ready to evolve!" } },
	{ "the Training Place", { "Training Place", "*Train pets*", "**Stop**" } },
	{ "the Vault and offline coins", { "Vault", "Welcome-back pile" } },
	{ "prestige", { "Prestige", "Starts over", "You keep", "You get" } },
	{ "homes from older versions", { "Homes from older versions", "until your next Prestige" } },
	{ "fusion after Prestige 1", { "Fusion Machine", "Unlocks at Prestige 1", "UPGRADE", "MIX", "Golden", "Rainbow", "hybrid" } },
	{ "the Home window and the home portal", { "Home window", "Go home", "portal" } },
	{ "Gems", { "Gems", "Gem packs", "Robux" } },
	{ "the Developer Products setup", { "Developer Products", "Creator Hub", "Config.Gems.Products", "src/shared/Config.lua", "Migrate to Latest Update" } },
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
	if def.Kind == "Farm" or def.Kind == "Plant" then
		out[#out + 1] = "+" .. num(e1.Food) .. " -> +" .. num(eN.Food) .. " food per meal"
	elseif def.Kind == "Garden" then
		local P = TC.Prestige or {}
		out[#out + 1] = "(" .. num(P.GardenSlotsBase) .. " places + " .. num(P.GardenSlotsPerStar) .. " per Prestige"
		-- Phase 5 (3.3): the Coin Magnet's reach and pile time live in the Garden's levels
		if e1.Radius and eN.Radius then
			out[#out + 1] = "scoops from " .. num(e1.Radius) .. " -> " .. num(eN.Radius) .. " studs"
		end
		if e1.PileSeconds and eN.PileSeconds then
			out[#out + 1] = "the lawn holds " .. num(e1.PileSeconds / 60) .. " -> " .. num(eN.PileSeconds / 60) .. " min of coins"
		end
		out[#out + 1] = "Lucky coins " .. num((e1.Lucky or 0) * 100) .. " % -> " .. num((eN.Lucky or 0) * 100) .. " %"
	elseif def.Kind == "FoodMachine" then
		out[#out + 1] = "a feed fills " .. num((e1.FeedShare or 0) * 100) .. " % -> " .. num((eN.FeedShare or 0) * 100) .. " % of the XP bar"
	elseif def.Kind == "Training" then
		out[#out + 1] = num(e1.Slots) .. " -> " .. num(eN.Slots) .. " pets train at once"
	elseif def.Kind == "Vault" then
		out[#out + 1] = "piles +" .. num((e1.PileSeconds or 0) / 60) .. " -> +" .. num((eN.PileSeconds or 0) / 60) .. " min"
		out[#out + 1] = "offline coins"
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
-- Phase 5 (3.3, TycoonCatalog Version 5): 11 stations; the Arena Gate and the House have no row
local TIER_ROWS = {
	{ "Berry Farm", { "Press1" } },
	{ "Pet Garden", { "Garden" } },
	{ "Food Machine, Training Place, Vault", { "Kitchen", "Gym", "Vault" } },
	{ "Fusion Machine", { "FusionMachine" } },
	{ "Yard Fence, Fountain, Pet Podium", { "DecorFence", "DecorFountain", "DecorPodium" } },
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
-- the Vault
----------------------------------------------------------------------------------------------------
local function checkVault(TC, lines, vaultText, tycoonSource)
	local t = T.tally("docs: the Vault table, offline coins and the Welcome-back toast match TycoonCatalog / TycoonService", 6)
	local vault = TC.ById.Vault
	local rows, header = tableRows(lines, "| Vault level |")
	if t:case(rows ~= nil, "no Vault table (| Vault level | 1 | 2 | ...)") then
		t:case(#header == vault.MaxLevel + 1, "the Vault table has " .. (#header - 1) .. " level columns, the Vault " .. vault.MaxLevel .. " levels")
		local byName = rowsByName(rows)
		local piles, share, hours = byName["Bigger piles"], byName["Share of your income"], byName["For up to"]
		if t:case(piles ~= nil and share ~= nil and hours ~= nil, "the Vault table needs the rows 'Bigger piles', 'Share of your income' and 'For up to'") then
			for lv = 1, vault.MaxLevel do
				local e = vault.Effects[lv] or {}
				local pile = "+" .. num((e.PileSeconds or 0) / 60) .. " min"
				t:case(piles[lv + 1] == pile, "Vault " .. lv .. ": piles " .. show(piles[lv + 1]) .. " vs " .. show(pile))
				t:case(share[lv + 1] == num((e.OfflinePercent or 0) * 100) .. " %", "Vault " .. lv .. ": share " .. show(share[lv + 1])
					.. " vs " .. num((e.OfflinePercent or 0) * 100) .. " %")
				t:case(hours[lv + 1] == num(e.OfflineHours) .. " h", "Vault " .. lv .. ": hours " .. show(hours[lv + 1]) .. " vs " .. num(e.OfflineHours))
			end
		end
	end
	local f = flat(vaultText)
	local minText = "absences under " .. num((TC.OfflineMinSeconds or 120) / 60) .. " minutes"
	t:case(has(f, minText), "the Vault text should say " .. show(minText))
	t:case(has(f, "**Welcome-back pile**"), "the Vault text should name the **Welcome-back pile**")
	-- the toast is quoted with $X where TycoonService puts the amount
	local src = tycoonSource or ""
	local pre, post = src:match('"(Welcome back! Your pets made )"%s*%.%.%s*[%w_%.]+%b()%s*%.%.%s*"([^"]*)"')
	if not pre then
		-- Phase 5: "... made $X" .. extra .. " while you were away ..." (extra = " and N berries" or "")
		pre, post = src:match('"(Welcome back! Your pets made )"%s*%.%.%s*[%w_%.]+%b()%s*%.%.%s*[%w_]+%s*%.%.%s*"([^"]*)"')
	end
	if t:case(pre ~= nil, "TycoonService.lua has the 'Welcome back! Your pets made ...' toast") then
		local quote = pre .. "$X" .. post
		t:case(has(f, quote), "the Vault text should quote the toast " .. show(quote))
	end
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
	t:case(has(f, "**x" .. num(m) .. " coins** per star"), "the text should say x" .. num(m) .. " coins per star")
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
	-- Phase 4: one more garden place per star, the Garden stays, prices go up by PriceStep per star
	t:case(has(f, "**+" .. num(P.GardenSlotsPerStar) .. " garden place**"), "the text should say +" .. num(P.GardenSlotsPerStar) .. " garden place")
	t:case(has(f, "except the decor and the Pet Garden") and (TC.ById.Garden or {}).ResetLevel ~= nil,
		"the text should say the Pet Garden stays (Garden.ResetLevel)")
	local step = 1 + (tonumber(P.PriceStep) or 0)
	local prices = "**x" .. num(step) .. "** at 1 star, x" .. num(step ^ 2) .. " at 2 stars, x" .. num(step ^ 3) .. " at 3 stars"
	t:case(has(f, prices), "the text should say " .. show(prices))
	if type(TC.StarPriceMultiplier) == "function" then
		t:case(math.abs(TC.StarPriceMultiplier(2) - step ^ 2) < 1e-9, "StarPriceMultiplier follows Prestige.PriceStep as documented")
	end
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
		for _, key in ipairs({ "Enabled", "AllowInStudio", "StudioAutoGrant", "GrantTokens", "GrantCash", "GrantGems", "GrantBerries", "MaxTokensPerCommand" }) do
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
	for _, top in ipairs({ "shared", "server", "client", "first" }) do
		local path = ROOTS[top]
		local root = path and Mock.GetPath(path)
		if root then
			for _, inst in ipairs(root:GetDescendants()) do
				if inst:IsA("ModuleScript") and inst.Parent and inst.Parent.Name == "MeshManifests" then
					-- generated by blender/build_all.py: the layout names the folder once
				elseif inst:IsA("ModuleScript") then
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
-- Phase 3: pet battles (the "## Pet battles" section and the battle bits of the rest of the README)
----------------------------------------------------------------------------------------------------
local TOPICS3 = {
	{ "getting to the arena: the Arena gate, the bridge and the home Arena Gate", { "Battle Arena", "Arena gate", "bridge", "BATTLE ARENA", "**Arena Gate**", "press **E**" } },
	{ "the Team screen (a fighter and two helpers)", { "**Team**", "Use this team", "team power", "**FIGHTER**", "**HELPERS**", "Set as fighter" } },
	{ "the battle buttons and keys", { "**ATTACK**", "**ELEMENT**", "**SPECIAL**", "**DASH**", "**SWAP**", "`F`", "`E`", "`Q`", "`Shift`", "`Tab`", "`1` / `2`", "Phone", "ENERGY" } },
	{ "lives and the bench", { "3 lives", "steps in by itself" } },
	{ "helpers and Supporters", { "Helper buff", "**Support**", "Who gives it" } },
	{ "the Dungeon", { "Dungeon", "**SOLO**", "**PARTY**", "**READY**", "**START**", "boss room", "first clear", "chest", "LEAVE" } },
	{ "duels: challenge, the quick queue, practice duels", { "duel rings", "Challenge", "Accept", "Find a match", "practice duel" } },
	{ "trophies and the leaderboard", { "Trophies", "leaderboard", "top 10" } },
	{ "Boss Raids: joining and dodging", { "Boss Raid", "JOIN RAID", "circle or line", "**DASH** out of it", "minion waves", "enraged" } },
	{ "Double Rewards", { "Double Rewards" } },
	{ "elements and team synergy in battle", { "synergy", "Balanced" } },
	{ "the developer raid tools", { "/raid", "Start Boss Raid" } },
	{ "testing duels in Studio", { "Test", "Clients and Servers", "2 players" } },
}

local function minutesText(seconds)
	seconds = floor((tonumber(seconds) or 0) + 0.5)
	local m, s = floor(seconds / 60), seconds % 60
	if s == 0 then
		return m .. (m == 1 and " minute" or " minutes")
	end
	return m .. " min " .. s .. " s"
end

local function hoursText(minutes)
	local h = (tonumber(minutes) or 0) / 60
	return num(h) .. (h == 1 and " hour" or " hours")
end

local function scheduleOf(BC, kind)
	for _, row in ipairs(((BC.Events or {}).Schedule) or {}) do
		if row.Kind == kind then
			return row
		end
	end
	return {}
end

-- the elements that are strong against `element` (Config.Elements.Strong)
local function strongAgainst(Config, element)
	local out = {}
	local E = Config.Elements or {}
	for _, attacker in ipairs(E.Order or {}) do
		for _, victim in ipairs((E.Strong or {})[attacker] or {}) do
			if victim == element then
				out[#out + 1] = attacker
			end
		end
	end
	return out
end

local function sourceNumber(src, name)
	return src and tonumber(src:match("%f[%w_]" .. name .. "%s*=%s*(%d+%.?%d*)")) or nil
end

local function checkBattleTopics(p3)
	local f = flat(p3)
	local t = T.tally("docs: the README's Pet battles section covers every part the player asked for", 6)
	for _, topic in ipairs(TOPICS3) do
		for _, word in ipairs(topic[2]) do
			t:case(has(f, word), topic[1] .. ": the section never says " .. show(word))
		end
	end
	t:report()
end

-- sorted keys of a table (deterministic messages; never depend on pairs() order)
local function sortedKeys(tbl)
	local out = {}
	for k in pairs(tbl or {}) do
		out[#out + 1] = k
	end
	table.sort(out, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return out
end

-- Phase 5 (4.1-4.8): a team of 3 (a fighter + two helpers), the fighter's kit, helper buffs, Supporters, specials,
-- element attacks, synergy and the keys BattleController binds
local function checkBattleRules(BC, Config, TC, p3, text, controllerSource)
	local t = T.tally("docs: the fighter, helpers, buffs, specials, elements, synergy and battle keys match BattleCatalog / BattleController", 6)
	local f = flat(p3)
	local F = BC.Fighter or {}
	-- the team
	t:case(has(f, "A team is **" .. tostring(BC.TeamSize) .. " pets**"), "a team is " .. tostring(BC.TeamSize) .. " pets ('A team is **N pets**')")
	t:case(BC.TeamSize == 3 and BC.MaxTeamSize == nil and (TC.Prestige or {}).TeamSlotUnlock == nil,
		"BattleCatalog.TeamSize 3, no MaxTeamSize and no TycoonCatalog.Prestige.TeamSlotUnlock (the 4th slot is gone)")
	for _, stale in ipairs({ "4th slot", "slot opens at Prestige", "slot 4 opens" }) do
		t:case(not has(text, stale), "the README still says " .. show(stale) .. " (teams have 3 pets since phase 5)")
	end
	-- the fighter's kit
	t:case(has(f, "**" .. num(F.Lives) .. " lives:**"), "the fighter has " .. tostring(F.Lives) .. " lives")
	t:case(has(f, "then a **" .. num(F.ElementCooldown) .. " s** cooldown"), "ELEMENT cools down " .. tostring(F.ElementCooldown) .. " s")
	t:case(has(f, "one dash every **" .. num(F.DashCooldown) .. " s**"), "a battle dash every " .. tostring(F.DashCooldown) .. " s")
	t:case(has(f, "(every **" .. num(F.SwapCooldown) .. " s**)"), "SWAP every " .. tostring(F.SwapCooldown) .. " s")
	t:case(has(f, "**ENERGY** bar is full (" .. num(F.SpecialMeterMax) .. ")"), "SPECIAL at a full ENERGY bar (" .. tostring(F.SpecialMeterMax) .. ")")
	t:case(has(f, "(up to " .. num((F.BenchRegenCap or 0) * 100) .. " % of their health)"), "benched helpers heal up to "
		.. num((F.BenchRegenCap or 0) * 100) .. " %")
	t:case(has(f, "(**" .. num(F.SupportCooldown) .. " s** for a Support pet's buff, **" .. num(F.HelperCooldown) .. " s** for an element buff)"),
		"buff cooldowns " .. tostring(F.SupportCooldown) .. " s (Support) / " .. tostring(F.HelperCooldown) .. " s (element)")
	-- Supporters
	local S = (BC.Roles or {}).Support or {}
	t:case(has(f, "it hits with x" .. num(S.Power) .. " power and x" .. num(S.Health) .. " health"), "Support pets: x" .. num(S.Power)
		.. " power and x" .. num(S.Health) .. " health")
	for _, kind in ipairs(BC.SupportKinds or {}) do
		t:case(has(f, "**" .. kind .. "**"), "the Support kind " .. kind .. " is not named")
	end
	-- the buff table: one row per BattleCatalog.Buffs entry, its name, giver and text
	local rows = rowsByName(tableRows(splitLines(p3), "| Buff | Who gives it |"))
	local supports = {}
	for _, kind in ipairs(BC.SupportKinds or {}) do
		supports[kind] = true
	end
	local count = 0
	for _, id in ipairs(sortedKeys(BC.Buffs)) do
		local buff = BC.Buffs[id]
		count = count + 1
		local row = rows[buff.Name]
		local who = supports[id] and ("Support pets with " .. id) or (id .. " pets")
		if t:case(row ~= nil, "no buff row " .. show(buff.Name) .. " (BattleCatalog.Buffs." .. id .. ")") then
			t:case(row[2] == who and row[3] == buff.Text, buff.Name .. ": the README says " .. show(row[2]) .. " / " .. show(row[3])
				.. ", BattleCatalog " .. show(who) .. " / " .. show(buff.Text))
		end
	end
	local n = 0
	for _ in pairs(rows) do
		n = n + 1
	end
	t:case(n == count, "the buff table has " .. n .. " rows, BattleCatalog.Buffs " .. count)
	-- element attacks and specials
	for _, el in ipairs(sortedKeys(BC.ElementAttacks)) do
		local a = BC.ElementAttacks[el]
		t:case(has(f, "**" .. tostring(a.Name) .. "** (" .. el), "the ELEMENT attack " .. tostring(a.Name) .. " (" .. el .. ") is not named")
	end
	local kinds = BC.SpecialKinds or {}
	for _, kind in ipairs(kinds) do
		t:case(has(f, "**" .. kind .. "**"), "the special kind " .. kind .. " is not named")
	end
	t:case(NUMBER_WORDS[#kinds] ~= nil and has(f, "The " .. NUMBER_WORDS[#kinds]:lower() .. " kinds"), "the section counts " .. #kinds .. " special kinds")
	-- elements and synergy
	local E = Config.Elements or {}
	t:case(has(f, "**x" .. num(E.StrongMultiplier) .. "**") and has(f, "**x" .. num(E.WeakMultiplier) .. "**"),
		"the battle section should give the element multipliers x" .. num(E.StrongMultiplier) .. " / x" .. num(E.WeakMultiplier))
	local R = BC.SynergyRules or {}
	local same = R.SameElement or {}
	t:case(has(f, "**+" .. num((same[2] or 0) * 100) .. " % Power**"), "synergy: 2 of one element give +" .. num((same[2] or 0) * 100) .. " % Power")
	for k = 3, BC.TeamSize or 3 do
		local want = "**" .. k .. " of one element +" .. num((same[k] or 0) * 100) .. " %"
		t:case(same[k] ~= nil and has(f, want), "synergy: the section should say " .. show(want))
	end
	t:case(same[(BC.TeamSize or 3) + 1] == nil and not has(f, "4 of one element"), "synergy: no '4 of one element' line in a team of 3")
	local balanced = "**" .. tostring(R.BalancedElements) .. " or more different elements:**"
	t:case(has(f, balanced), "synergy: the section should say " .. show(balanced))
	t:case(has(f, "**+" .. num((R.BalancedHealth or 0) * 100) .. " % Health**"), "synergy: Balanced gives +" .. num((R.BalancedHealth or 0) * 100) .. " % Health")
	-- the keys: the controls table and the section quote what BattleController binds (4.7)
	local src = controllerSource or ""
	local function bound(action, key)
		return src:find("BindActionAtPriority%(K%." .. action .. ",[^\n]*Enum%.KeyCode%." .. key .. "[,%)]") ~= nil
	end
	local controls = tableRows(splitLines(text), "| Action | PC |") or {}
	local function controlRow(prefix)
		for _, row in ipairs(controls) do
			if row[1]:sub(1, #prefix) == prefix then
				return row
			end
		end
		return nil
	end
	for _, spec in ipairs({
		{ "ACTION_ATTACK", "F", "ButtonX", "X", "Battle: **ATTACK**" },
		{ "ACTION_ELEMENT", "E", "ButtonY", "Y", "Battle: **ELEMENT**" },
		{ "ACTION_SPECIAL", "Q", "ButtonR1", "RB", "Battle: **SPECIAL**" },
		{ "ACTION_TARGET", "Tab", "ButtonR2", "RT", "Battle: pick the next enemy" },
	}) do
		t:case(bound(spec[1], spec[2]) and bound(spec[1], spec[3]), "BattleController binds " .. spec[1] .. " to " .. spec[2] .. " and " .. spec[3])
		local row = controlRow(spec[5])
		t:case(row ~= nil and row[2]:sub(1, #spec[2] + 2) == "`" .. spec[2] .. "`" and row[4]:sub(1, #spec[4] + 2) == "`" .. spec[4] .. "`",
			"the controls table row " .. show(spec[5]) .. " should start with `" .. spec[2] .. "` / `" .. spec[4] .. "`")
		t:case(has(f, "`" .. spec[2] .. "`"), "the battle section names the key `" .. spec[2] .. "`")
	end
	for i, key in ipairs({ "One", "Two" }) do
		t:case(src:find("%[Enum%.KeyCode%." .. key .. "%]%s*=%s*" .. i) ~= nil, "BattleController maps key " .. i .. " to helper " .. i)
	end
	local helperRow = controlRow("Battle: a helper's buff")
	t:case(helperRow ~= nil and helperRow[2] == "`1` / `2`", "the controls table's helper row reads `1` / `2`")
	t:case(src:find("SetDashKeys, { Enum%.KeyCode%.LeftShift") ~= nil, "BattleController makes Shift the battle dash (SetDashKeys)")
	local dashRow = controlRow("Battle: **DASH**")
	t:case(dashRow ~= nil and dashRow[2] == "`Shift`", "the controls table's battle DASH row reads `Shift`")
	t:case(not src:find("ACTION_RETREAT", 1, true) and not has(f, "RETREAT"), "RETREAT is gone (BattleController and the battle section)")
	t:report()
end

-- Phase 5 (5.1-5.3): the Dungeon replaces the Trials
local function checkDungeon(BC, lines, dText, serviceSource, dataSource)
	local t = T.tally("docs: the Dungeon (floors, party, rooms, loot, first clears, chests, the Trial credit) matches BattleCatalog / DungeonService", 6)
	local f = flat(dText)
	local D = BC.Dungeon or {}
	t:case(has(f, "**" .. tostring(D.Floors) .. " floors**"), "the Dungeon has " .. tostring(D.Floors) .. " floors")
	t:case(has(f, "A floor is **" .. #(D.RoomSeconds or {}) .. " rooms**"), "a floor is " .. #(D.RoomSeconds or {}) .. " rooms")
	local maxParty = sourceNumber(serviceSource, "MAX_PARTY")
	t:case(maxParty ~= nil and has(f, "a party for up to **" .. num(maxParty) .. "** players"), "a party of up to " .. tostring(maxParty) .. " (DungeonService MAX_PARTY)")
	t:case(has(f, "Unready members get " .. num(D.ReadyTimeout) .. " seconds") and has(serviceSource, "press READY"),
		"the READY clock is " .. tostring(D.ReadyTimeout) .. " seconds")
	t:case(has(f, "You have **" .. minutesText(D.RoomTime) .. "** per room (**" .. minutesText(D.Floor1RoomTime) .. "** on floor 1)"),
		"a room lasts " .. minutesText(D.RoomTime) .. " (" .. minutesText(D.Floor1RoomTime) .. " on floor 1)")
	t:case(has(f, "(at least " .. num((D.MinShare or 0) * 100) .. " % of the party's damage"), "loot needs " .. num((D.MinShare or 0) * 100) .. " % of the damage")
	t:case(has(f, "\"Clear floor 6 first\"") and has(serviceSource, '"Clear floor " .. '), "the unlock toast 'Clear floor N first'")
	t:case(has(f, "Train your team and try again!") and has(serviceSource, "Train your team and try again!"), "the wipe toast is quoted")
	-- the floor table
	local rows = tableRows(lines, "| Floor | Name | Element |")
	if t:case(rows ~= nil, "no floor table (| Floor | Name | Element |)") then
		t:case(#rows == #(BC.DungeonFloors or {}) and #rows == D.Floors, "the floor table has " .. #rows .. " rows, BattleCatalog " .. tostring(D.Floors))
		for i, fl in ipairs(BC.DungeonFloors or {}) do
			local row = rows[i] or {}
			t:case(row[1] == tostring(i) and row[2] == fl.Name and row[3] == fl.Element, "floor " .. i .. ": the README says " .. show(row[2]) .. " "
				.. show(row[3]) .. ", BattleCatalog " .. tostring(fl.Name) .. " " .. tostring(fl.Element))
		end
	end
	-- loot per room: the formulas, cross-checked against DungeonRewards
	local loot = rowsByName(tableRows(lines, "| Reward | Every room |"))
	local secs = D.RoomSeconds or {}
	local cash = "the bigger of $" .. num(D.CashBase) .. " + $" .. num(D.CashPerFloor) .. " x the floor and what your garden makes in "
		.. num(secs[1]) .. " / " .. num(secs[2]) .. " / " .. num(secs[3]) .. " seconds (rooms 1-3) or " .. num(secs[4]) .. " seconds (the boss room)"
	t:case((loot.Cash or {})[2] == cash, "the Cash row should read " .. show(cash))
	local tb = "(" .. num(D.TokenBase) .. " + " .. num(D.TokenPerFloor) .. " x the floor)"
	local tokens = tb .. " x the waves / 2; the boss room " .. tb .. " x 2 (x2 during Double Rewards)"
	t:case((loot["Cloud Tokens"] or {})[2] == tokens, "the Tokens row should read " .. show(tokens))
	local xp = num(D.XpBase) .. " + " .. num(D.XpPerFloor) .. " x the floor for every wave (the boss room counts " .. num(D.BossRoomWaves) .. ")"
	t:case((loot["XP for every team pet"] or {})[2] == xp, "the XP row should read " .. show(xp))
	if type(BC.DungeonRewards) == "function" then
		local r1, r4 = BC.DungeonRewards(3, 1, 2, 0, false), BC.DungeonRewards(3, 4, 1, 1000, true)
		local base = D.TokenBase + D.TokenPerFloor * 3
		t:case(r1.Cash == D.CashBase + D.CashPerFloor * 3 and r1.Tokens == floor(base * 2 / 2) and r1.Xp == (D.XpBase + D.XpPerFloor * 3) * 2,
			"DungeonRewards(floor 3, room 1, 2 waves) follows the documented formulas")
		t:case(r4.Cash == 1000 * secs[4] and r4.Tokens == base * 2 * 2 and r4.Xp == (D.XpBase + D.XpPerFloor * 3) * D.BossRoomWaves,
			"DungeonRewards(floor 3, the boss room, Double Rewards) follows the documented formulas")
	end
	-- first clears
	t:case(has(f, "**" .. num(D.FirstClearTokens) .. " x the floor Cloud Tokens**"), "a first clear pays " .. tostring(D.FirstClearTokens) .. " x the floor tokens")
	local gemRows, header = tableRows(lines, "| First clear of floor |")
	if t:case(gemRows ~= nil and gemRows[1] ~= nil, "no first-clear Gems table (| First clear of floor | 1 | 2 | ...)") then
		t:case(#header == D.Floors + 1, "the first-clear table has " .. (#header - 1) .. " floors, BattleCatalog " .. tostring(D.Floors))
		for fl = 1, D.Floors do
			local fc = BC.DungeonFirstClear(fl)
			t:case(header[fl + 1] == tostring(fl) and gemRows[1][fl + 1] == num(fc.Gems) and fc.Tokens == D.FirstClearTokens * fl,
				"first clear of floor " .. fl .. ": the README says " .. show(gemRows[1][fl + 1]) .. ", BattleCatalog " .. num(fc.Gems) .. " Gems")
		end
	end
	-- the treasure
	t:case(has(f, "from floor " .. num((D.ChestLowFloors or 2) + 1) .. " on sometimes Gems"), "chests give Gems from floor " .. num((D.ChestLowFloors or 2) + 1))
	t:case(has(f, "wait " .. num(D.TreasureSeconds) .. " seconds"), "the treasure room closes after " .. tostring(D.TreasureSeconds) .. " seconds")
	-- the Trial credit (9.2 step 2, DataService's P5 constants)
	local per, top = sourceNumber(dataSource, "TRIALS_PER_FLOOR"), sourceNumber(dataSource, "MIGRATE_MAX_FLOOR")
	if t:case(per ~= nil and top ~= nil, "DataService's TRIALS_PER_FLOOR / MIGRATE_MAX_FLOOR are readable") then
		t:case(has(f, "every " .. num(per) .. " Trial levels you cleared before phase 5 unlocked one floor (up to floor " .. num(top) .. ")"),
			"the Trial credit: every " .. num(per) .. " Trial levels one floor, up to floor " .. num(top))
	end
	t:case(BC.TrialRewards == nil and BC.TrialCount == nil, "BattleCatalog has no Trials any more (TrialRewards / TrialCount)")
	t:report()
end

local function checkDuels(BC, lines, duelText, serviceSource)
	local t = T.tally("docs: duels, trophies and the fair-play rules match BattleCatalog.Trophies / BattleService", 6)
	local f = flat(duelText)
	local TR = BC.Trophies or {}
	local function signed(n)
		n = tonumber(n) or 0
		return (n > 0 and "+" or "") .. num(n)
	end
	local rows = tableRows(lines, "| Result | Trophies |")
	if t:case(rows ~= nil, "no trophy table (| Result | Trophies | Cloud Tokens | XP for every team pet |)") then
		local byName = rowsByName(rows)
		t:case(#rows == 3, "the trophy table should have the rows Win, Draw, Loss")
		for _, spec in ipairs({ { "Win", TR.Win, TR.Tokens.Win, TR.Xp.Win }, { "Draw", TR.Draw, TR.Tokens.Draw, TR.Xp.Loss }, { "Loss", TR.Loss, TR.Tokens.Loss, TR.Xp.Loss } }) do
			local row = byName[spec[1]]
			if t:case(row ~= nil, "no trophy row " .. spec[1]) then
				t:case(row[2] == signed(spec[2]), spec[1] .. ": trophies " .. show(row[2]) .. " vs " .. signed(spec[2]))
				t:case(row[3] == num(spec[3]), spec[1] .. ": tokens " .. show(row[3]) .. " vs " .. num(spec[3]))
				t:case(row[4] == num(spec[4]), spec[1] .. ": XP " .. show(row[4]) .. " vs " .. num(spec[4]))
			end
		end
	end
	t:case(TR.Forfeit == TR.Loss and has(f, "during a duel counts as a loss"), "a leaver loses like a loss (Forfeit = Loss)")
	t:case(has(f, "Trophies never drop below " .. num(TR.Floor)), "the trophy floor " .. tostring(TR.Floor))
	t:case(has(f, "A duel lasts up to **" .. minutesText((BC.TimeLimits or {}).Duel) .. "**"), "a duel lasts " .. minutesText((BC.TimeLimits or {}).Duel))
	local pairLimit, pairWindow = sourceNumber(serviceSource, "PAIR_LIMIT"), sourceNumber(serviceSource, "PAIR_WINDOW")
	local early, gap = sourceNumber(serviceSource, "FORFEIT_MIN_SECONDS"), sourceNumber(serviceSource, "DUEL_POWER_GAP")
	-- Phase 5 (4.2): BattleService takes the practice gap from BattleCatalog.Duel.PowerGap when it is there
	if type(BC.Duel) == "table" and type(BC.Duel.PowerGap) == "number" then
		gap = BC.Duel.PowerGap
	end
	local invite = sourceNumber(serviceSource, "CHALLENGE_TIMEOUT")
	if t:case(pairLimit and pairWindow and early and gap and invite, "BattleService's PAIR_LIMIT / PAIR_WINDOW / FORFEIT_MIN_SECONDS / DUEL_POWER_GAP / CHALLENGE_TIMEOUT are readable") then
		local pairText = "**" .. num(pairLimit) .. " duels every " .. num(pairWindow / 60) .. " minutes**"
		t:case(has(f, pairText), "the pair limit should read " .. show(pairText))
		t:case(has(f, "the first **" .. num(early) .. " seconds**"), "the early-forfeit rule should say " .. num(early) .. " seconds")
		t:case(has(f, "more than **" .. num(gap) .. " times** stronger"), "the practice rule should say more than " .. num(gap) .. " times stronger")
		t:case(has(f, "**Decline** (" .. num(invite) .. " seconds)"), "an invite lasts " .. num(invite) .. " seconds")
	end
	t:report()
end

local function checkRaids(BC, PC, Config, lines, raidText, doubleText)
	local t = T.tally("docs: Boss Raids (schedule, bosses, timings, reward tiers, raid pets) and Double Rewards match BattleCatalog", 6)
	local f = flat(raidText)
	local ev = BC.Events or {}
	local raid = scheduleOf(BC, "BossRaid")
	t:case(has(f, "**every " .. num(raid.EveryMinutes) .. " minutes**"), "a raid every " .. tostring(raid.EveryMinutes) .. " minutes")
	t:case(has(f, "the first one " .. minutesText(ev.FirstAfterSeconds) .. " after a server starts"), "the first raid " .. minutesText(ev.FirstAfterSeconds) .. " after the start")
	t:case(has(f, "**" .. minutesText(raid.AnnounceSeconds) .. "** before"), "the raid is announced " .. minutesText(raid.AnnounceSeconds) .. " before")
	t:case(has(f, "**first " .. num(ev.JoinWindowSeconds) .. " seconds**"), "joining is open the first " .. tostring(ev.JoinWindowSeconds) .. " seconds")
	local rows = tableRows(lines, "| Boss | Element |")
	if t:case(rows ~= nil, "no boss table (| Boss | Element | Strong pets against it | Its big attacks |)") then
		t:case(#rows == #(BC.BossOrder or {}), "the boss table has " .. #rows .. " rows, BattleCatalog " .. #(BC.BossOrder or {}) .. " bosses")
		for i, id in ipairs(BC.BossOrder or {}) do
			local boss = BC.Bosses[id] or {}
			local row = rows[i] or {}
			t:case(plain(row[1]) == boss.Name, "boss " .. i .. " of the rotation: the README says " .. show(plain(row[1])) .. ", BattleCatalog " .. tostring(boss.Name))
			t:case(row[2] == boss.Element, tostring(boss.Name) .. ": element " .. show(row[2]) .. " vs " .. tostring(boss.Element))
			t:case(row[3] == table.concat(strongAgainst(Config, boss.Element), ", "), tostring(boss.Name) .. ": strong pets " .. show(row[3]) .. " vs "
				.. table.concat(strongAgainst(Config, boss.Element), ", "))
			for _, a in ipairs(boss.Attacks or {}) do
				t:case(has(row[4], a.Name), tostring(boss.Name) .. ": the attack " .. show(a.Name) .. " is not named")
			end
			t:case(boss.EnrageAt == BC.Bosses[BC.BossOrder[1]].EnrageAt and boss.TimeLimit == BC.Bosses[BC.BossOrder[1]].TimeLimit,
				tostring(boss.Name) .. ": every boss shares the documented enrage time and time limit")
		end
		local first = BC.Bosses[(BC.BossOrder or {})[1]] or {}
		t:case(has(f, "**enraged** after **" .. minutesText(first.EnrageAt) .. "**"), "the enrage comes after " .. minutesText(first.EnrageAt))
		t:case(((BC.BossRules or {}).Enrage or {}).Damage == 2 and has(f, "hits twice as hard"), "enraged bosses hit x" .. tostring(((BC.BossRules or {}).Enrage or {}).Damage))
		t:case(has(f, "after **" .. minutesText(first.TimeLimit) .. "**"), "a raid ends after " .. minutesText(first.TimeLimit))
	end
	local R = BC.Raid or {}
	local tiers = tableRows(lines, "| Tier | Your share of the damage |")
	if t:case(tiers ~= nil, "no raid tier table (| Tier | Your share of the damage | ...)") then
		t:case(#tiers == #(R.Tiers or {}), "the tier table has " .. #tiers .. " rows, BattleCatalog " .. #(R.Tiers or {}))
		for i, tier in ipairs(R.Tiers or {}) do
			local row = tiers[i] or {}
			local gems = (tier.Gems or 0) > 0 and (num(tier.Gems) .. " (" .. num(tier.GemChance * 100) .. " % chance)") or "-"
			local shareText = (tier.MinShare or 0) > 0 and (num(tier.MinShare * 100) .. " % or more") or "any hit on the boss"
			local want = { tier.Id, shareText, num(tier.Tokens), num(tier.Xp), gems, num(tier.EventPetChance * 100) .. " %" }
			for c = 1, 6 do
				local got = c == 1 and plain(row[1]) or row[c]
				t:case(got == want[c], tier.Id .. " column " .. c .. ": the README says " .. show(got) .. ", BattleCatalog " .. show(want[c]))
			end
		end
	end
	if (R.MinShare or 0) > 0 then
		t:case(has(f, "dealt at least " .. num(R.MinShare * 100) .. " %") and has(f, "Under " .. num(R.MinShare * 100) .. " % of the damage"),
			"the minimum share " .. num(R.MinShare * 100) .. " % (no reward below it)")
	else
		t:case(has(f, "everyone whose pets hit it") and has(f, "never") and has(f, "hit the boss gets no reward"),
			"every raider whose pets hit the boss is rewarded; only no hits at all earns nothing")
	end
	t:case(has(f, "**" .. num(R.LossTokens) .. " tokens** and **" .. num(R.LossXp) .. " XP**"), "a lost raid pays " .. tostring(R.LossTokens) .. " tokens and "
		.. tostring(R.LossXp) .. " XP")
	local pets = type(PC.EventPets) == "function" and PC.EventPets() or {}
	t:case(#pets >= 2, "PetCatalog has the Boss Raid pets")
	for _, def in ipairs(pets) do
		t:case(has(f, "**" .. def.Name .. "** (" .. tostring(def.Element)), "the Boss Raid pet " .. def.Name .. " (" .. tostring(def.Element) .. ") is not named")
	end
	t:case(has(f, "**The " .. NUMBER_WORDS[#pets]:lower() .. " Boss Raid pets**"), "the section should count " .. #pets .. " Boss Raid pets")
	-- Double Rewards
	local d = flat(doubleText)
	local double = scheduleOf(BC, "DoubleRewards")
	t:case(has(d, "Every **" .. hoursText(double.EveryMinutes) .. "**"), "Double Rewards every " .. hoursText(double.EveryMinutes))
	t:case(has(d, "for **" .. hoursText((double.DurationSeconds or 0) / 60) .. "**"), "Double Rewards last " .. hoursText((double.DurationSeconds or 0) / 60))
	t:case(has(d, "**x" .. num(ev.DoubleRewardsMultiplier) .. " Cloud Tokens**"), "Double Rewards pay x" .. num(ev.DoubleRewardsMultiplier))
	t:case(has(d, "(announced " .. minutesText(double.AnnounceSeconds) .. " before"), "Double Rewards are announced " .. minutesText(double.AnnounceSeconds) .. " before")
	t:report()
end

local function checkBattleDrift(Config, PC, Steps, text, tutorialText, tutorialSource)
	local t = T.tally("docs: the rest of the README knows Phase 5 (tutorial chapter 3, Index count, no Trials or RETREAT in the battle rules)", 6)
	local f = flat(text)
	for _, stale in ipairs({ "coming Pet Battles", "in the next update", "come in the next update", "Coming soon* until phase 3", "This build is **v3 phase 2**",
		"This build is **v3 phase 3**", "This build is **v3 phase 4**", "## Pet battles (phase 3)", "### Trials 1-30", "## The five portals" }) do
		t:case(not has(text, stale), "the README still says " .. show(stale))
	end
	t:case(has(f, "This build is **v3 phase 5**"), "the intro names this build v3 phase 5")
	if type(PC.TotalCount) == "function" then
		t:case(has(f, "\"Unlocked: x/" .. PC.TotalCount() .. "\""), "the Pet Index footer counts " .. PC.TotalCount() .. " pets")
	end
	local counts, ids = 0, {}
	for _, step in ipairs((type(Steps) == "table" and Steps.Steps) or {}) do
		if step.Chapter == 3 then
			counts = counts + 1
			ids[step.Id] = true
		end
	end
	local tf = flat(tutorialText)
	t:case(counts > 0 and has(tf, "third chapter teaches pet battles in " .. string.lower(NUMBER_WORDS[counts] or "?") .. " steps"),
		"tutorial chapter 3 has " .. counts .. " steps")
	t:case(ids.dungeon == true and ids.trial == nil and has(tf, "press **E** at the Dungeon gate and clear floor 1"),
		"tutorial chapter 3 clears Dungeon floor 1 (TutorialSteps id 'dungeon', no 'trial')")
	local tokens = tutorialSource and tonumber(tutorialSource:match("local ARENA_FINISH_TOKENS = (%d+)"))
	if t:case(tokens ~= nil, "TutorialService.lua has ARENA_FINISH_TOKENS") then
		t:case(has(tf, "**" .. commas(tokens) .. " Cloud Tokens** at the end. Players who finished the first two chapters"),
			"the battle chapter reward of " .. commas(tokens) .. " Cloud Tokens")
	end
	t:report()
end

local function checkPhase3(Config, PC, TC, Steps, lines, text, sub)
	local BC, err = requireModule("shared/BattleCatalog")
	if not T.check(BC ~= nil, "docs: shared/BattleCatalog loads", err) then
		return
	end
	local p3 = sub("## Pet battles")
	if p3 == "" then
		return
	end
	checkBattleTopics(p3)
	checkBattleRules(BC, Config, TC, p3, text, (readFile("src/client/Controllers/BattleController.lua")))
	checkDungeon(BC, lines, sub("### The Dungeon"), (readFile("src/server/Services/DungeonService.lua")), (readFile("src/server/Services/DataService.lua")))
	checkDuels(BC, lines, sub("### Duels and trophies"), (readFile("src/server/Services/BattleService.lua")))
	checkRaids(BC, PC, Config, lines, sub("### Boss Raids"), sub("### Double Rewards"))
	checkBattleDrift(Config, PC, Steps, text, sub("## First steps"), (readFile("src/server/Services/TutorialService.lua")))
end

----------------------------------------------------------------------------------------------------
-- Phase 4: pets make the money (the README's Phase 4 bullets, the Garden, the Food Machine and pet levels,
-- evolution, the Training Place, homes from before Phase 4, the Champion Ring, pet cards, NPCs, the tutorial's
-- chapters 2 and 4, /petlevel and the owner's publish steps). Every number is read from the catalogs.
----------------------------------------------------------------------------------------------------
local TOPICS4 = {
	{ "the Pet Garden and rainbow coins", { "Pet Garden", "rainbow coins", "only YOU can scoop", "Economy pets make 60 % more" } },
	{ "food plants and the Coin Magnet", { "food plants", "Berry Bush", "Carrot Patch", "Cloud Melons", "Starfruit Tree", "Coin Magnet" } },
	{ "piles, naps and the Welcome-back pile", { "nap (Zzz)", "Welcome-back pile", "Lucky coin" } },
	{ "the Food Machine", { "Food Machine", "**Feed**", "Leftover" } },
	{ "XP from every fight", { "Every fight gives XP", "a loss a third" } },
	{ "evolution", { "EVOLVE", "Ready to evolve!", "level 50", "**level 100**" } },
	{ "the Training Place", { "Training Place", "Attack Speed", "Physique", "Ability", "Defense", "Rank 3 takes 3 minutes", "**Stop**" } },
	{ "the Champion Ring", { "Champion Ring", "giant boss", "new record pays triple Cash", "100 Tokens" } },
	{ "pet cards and following", { "Pet cards", "**behind**" } },
	{ "the home portal", { "Portal home", "**Go home**" } },
	{ "safe zones", { "Safe zones" } },
	{ "prestige", { "+1 garden place", "prices go up by half", "until their next Prestige" } },
	{ "the owner's tools", { "/petlevel", "Publishing an update" } },
}

local function lowerHas(text, needle)
	return type(text) == "string" and text:lower():find(needle:lower(), 1, true) ~= nil
end

-- a pet definition of this rarity (and role), for the price examples; nil when the catalog has none
local function samplePet(PC, rarity, role)
	for _, def in ipairs(PC.Pets or {}) do
		if def.Rarity == rarity and (role == nil or def.Role == role) and not def.EventOnly then
			return def
		end
	end
	return nil
end

local function rarityRange(Config)
	local scale = (Config.PetStats or {}).RarityScale or {}
	local ids = rarityIds(Config)
	return "(" .. ids[1] .. " x" .. num(scale[ids[1]] or 1) .. " up to " .. ids[#ids] .. " x" .. num(scale[ids[#ids]] or 1) .. ")"
end

local function checkTopics4(whatsNew)
	local f = flat(whatsNew)
	local t = T.tally("docs: the README's 'What's new in phase 4' covers every part the player asked for", 6)
	for _, topic in ipairs(TOPICS4) do
		for _, word in ipairs(topic[2]) do
			t:case(has(f, word), topic[1] .. ": the section never says " .. show(word))
		end
	end
	t:report()
end

local function checkGarden(TC, PC, Config, lines, gardenText, homeFxSource)
	local t = T.tally("docs: the Pet Garden (places, roaming, Cloud Cash value, Economy x1.6, Lucky coins, the lawn, scooping, berries) matches TycoonCatalog / PetCatalog / HomeRoam", 6)
	local f = flat(gardenText)
	local P, C, B = TC.Prestige or {}, TC.Coins or {}, TC.Berries or {}
	t:case(has(f, "**" .. num(P.GardenSlotsBase) .. " places**"), "the Garden starts with " .. tostring(P.GardenSlotsBase) .. " places")
	t:case(has(f, "**+" .. num(P.GardenSlotsPerStar) .. " every Prestige**"), "+" .. tostring(P.GardenSlotsPerStar) .. " place every Prestige")
	t:case(has(f, "(up to " .. num(P.GardenSlotsMax) .. " places)"), "at most " .. tostring(P.GardenSlotsMax) .. " places")
	t:case(has(f, "**one meal every " .. num(C.MealSeconds) .. " seconds**"), "a meal every " .. tostring(C.MealSeconds) .. " seconds")
	-- roaming (3.5): one poop per HomeRoam cycle, worth PoopMeals meals
	local HR = requireModule("shared/HomeRoam")
	local cycle = HR and tonumber(HR.Cycle)
	t:case(cycle ~= nil and has(f, "one poop every **" .. num(cycle) .. " seconds** is worth **" .. num(C.PoopMeals) .. " meals**")
		and math.abs(cycle - (C.PoopMeals or 0) * (C.MealSeconds or 0)) < 1e-9, "one poop every " .. tostring(cycle) .. " seconds = "
		.. tostring(C.PoopMeals) .. " meals (HomeRoam.Cycle, Coins.PoopMeals)")
	for _, word in ipairs({ "**Food Bowl**", "poops **Cloud Cash**" }) do
		t:case(has(f, word), "the Garden text should say " .. show(word))
	end
	t:case(has(f, "gives " .. num(C.GrassFood) .. " food"), "the grass gives " .. tostring(C.GrassFood) .. " food")
	-- the worked example: a new Garden with a level-1 Berry Farm and a level-1 Common Combat pet
	local home = { Stations = { Garden = 1, Press1 = 1 }, Prestige = 0 }
	local food = TC.FoodOf(home)
	t:case(has(f, "has " .. num(food) .. " food"), "a Garden + Berry Farm Lv 1 has " .. num(food) .. " food")
	local def = samplePet(PC, rarityIds(Config)[1], "Combat")
	if t:case(def ~= nil, "PetCatalog has a Common Combat pet for the example") then
		local coin = TC.CoinValue(home, TC.PetPower(def, 1, "Normal", 0), 0)
		local want = "**$" .. commas(coin) .. " every " .. num(C.MealSeconds) .. " seconds**"
		t:case(has(f, want), "the example coin should read " .. show(want))
		local poop = "one Cloud Cash poop of $" .. commas(coin * (C.PoopMeals or 0)) .. " every " .. num(cycle) .. " seconds"
		t:case(has(f, poop), "the example poop should read " .. show(poop))
		local berries = floor(coin * (C.PoopMeals or 0) * (B.Share or 0))
		t:case(has(f, "(a $" .. commas(coin * (C.PoopMeals or 0)) .. " poop gives " .. commas(berries) .. " berries"), "the berry example: a $"
			.. commas(coin * (C.PoopMeals or 0)) .. " poop gives " .. commas(berries) .. " berries")
	end
	t:case(has(f, rarityRange(Config)), "the Garden text should say " .. show(rarityRange(Config)))
	local mult = TC.TierMultiplier or {}
	local tierText = "(Golden x" .. num(mult.Golden) .. ", Rainbow x" .. num(mult.Rainbow) .. ")"
	t:case(has(f, tierText), "the Garden text should say " .. show(tierText))
	local step = (PC.LevelFactor(2) - PC.LevelFactor(1)) * 100
	t:case(has(f, "(+" .. num(step) .. " % per level)"), "every level adds " .. num(step) .. " %")
	local eco = (PC.RoleMult or {}).Economy or 1
	t:case(has(f, "**Economy pets x" .. num(eco) .. "**") and has(f, num((eco - 1) * 100) .. " % more than Combat pets"),
		"Economy pets x" .. num(eco) .. " (" .. num((eco - 1) * 100) .. " % more)")
	-- Phase 5 (3.1): EVOLVE multiplies the level bonus (EvolutionBonusOf); the old flat boost table is gone
	local evo = "Level bonus x" .. bonusText(PC, 1) .. " after the first EVOLVE, x" .. bonusText(PC, 2) .. " after the second"
	t:case(PC.EvolutionBoost == nil and has(f, evo), "the Garden text should say " .. show(evo) .. " (and PetCatalog.EvolutionBoost is gone)")
	t:case(has(f, "x" .. num(P.IncomeMultiplier) .. " coins per star"), "x" .. num(P.IncomeMultiplier) .. " coins per star")
	t:case(has(f, "**Lucky coin** pops out, worth x" .. num(C.LuckyMult)), "a Lucky coin is worth x" .. tostring(C.LuckyMult))
	local garden = TC.ById.Garden
	local rows, header = tableRows(lines, "| Garden level |")
	if t:case(rows ~= nil and rows[1] ~= nil, "no Lucky table (| Garden level | 1 | 2 | ...)") then
		t:case(#header == garden.MaxLevel + 1, "the Lucky table has " .. (#header - 1) .. " columns, the Garden " .. garden.MaxLevel .. " levels")
		t:case(plain(rows[1][1]) == "Lucky coin chance", "the Lucky table's row is 'Lucky coin chance'")
		for lv = 1, garden.MaxLevel do
			local want = num(((garden.Effects[lv] or {}).Lucky or 0) * 100) .. " %"
			t:case(header[lv + 1] == tostring(lv) and rows[1][lv + 1] == want, "Garden " .. lv .. ": Lucky " .. show(rows[1][lv + 1]) .. " vs " .. want)
		end
	end
	-- scooping and the lawn: the Garden's own Radius / PileSeconds (the Coin Magnet folded into it, 3.3)
	local e1, eN = garden.Effects[1] or {}, garden.Effects[garden.MaxLevel] or {}
	t:case(has(f, "within " .. num(C.BaseRadius) .. " studs"), "without a Garden you scoop within " .. tostring(C.BaseRadius) .. " studs")
	t:case(has(f, "(" .. num(e1.Radius) .. " studs at level 1, up to " .. num(eN.Radius) .. " studs at level " .. garden.MaxLevel .. ")"),
		"the Garden reaches " .. tostring(e1.Radius) .. " -> " .. tostring(eN.Radius) .. " studs")
	t:case(TC.ScoopRadius({ Stations = { Garden = garden.MaxLevel } }) == eN.Radius, "ScoopRadius follows the Garden level as documented")
	t:case(has(f, num((e1.PileSeconds or 0) / 60) .. " minutes at Garden level 1, up to " .. num((eN.PileSeconds or 0) / 60) .. " minutes at level "
		.. garden.MaxLevel), "a pet's coins hold " .. num((e1.PileSeconds or 0) / 60) .. " -> " .. num((eN.PileSeconds or 0) / 60) .. " minutes")
	t:case(TC.PileSeconds({ Stations = { Garden = 1 } }) == e1.PileSeconds, "PileSeconds at Garden 1 = Garden.Effects[1].PileSeconds")
	t:case(has(f, "**at most " .. num(C.DropsPerPet) .. " coins**"), "each pet keeps at most " .. tostring(C.DropsPerPet) .. " coins on the lawn")
	t:case(TC.ById.Collector == nil and not has(f, "Coin Magnet pulls"), "the Coin Magnet station is gone")
	t:case(has(f, "**Only you can scoop your own coins**") and has(f, "\"Zzz\""), "scooping is owner-only and full lawns nap (Zzz)")
	local hint = "Only the owner can pick these up"
	t:case(has(f, hint) and has(homeFxSource, hint), "the README and HomeFx share the hint " .. show(hint))
	-- berries (3.4)
	t:case(has(f, "**" .. num((B.Share or 0) * 100) .. " % of its value in berries**"), "a poop adds " .. num((B.Share or 0) * 100) .. " % of its value in berries")
	t:case(has(f, "**" .. num(B.BasketMinutes) .. " minutes** of berries (at least **" .. commas(B.BasketMin or 0) .. "**)")
		and TC.BasketCap(nil, 0) == B.BasketMin, "the Berry Basket holds " .. tostring(B.BasketMinutes) .. " minutes (at least " .. tostring(B.BasketMin) .. ")")
	t:case(has(f, "\"Basket full! Feed your pets\""), "the full-basket toast is quoted")
	t:report()
end

local function checkFoodMachine(TC, PC, BC, Config, lines, fmText, careSource)
	local t = T.tally("docs: the Food Machine (berries, one Feed button), levels to 100, the XP curve and XP from fights match the catalogs", 6)
	local f = flat(fmText)
	local share = TC.FeedShare or {}
	local machine = TC.ById.Kitchen
	local shareText = num((share[1] or 0) * 100) .. " % of the XP bar at Food Machine level 1, up to " .. num((share[machine.MaxLevel] or 0) * 100)
		.. " % at level " .. machine.MaxLevel
	t:case(has(f, shareText), "the Food Machine text should say " .. show(shareText))
	local priceRule = "x its rarity " .. rarityRange(Config) .. " x " .. num(TC.FeedBase) .. " berries"
	t:case(has(f, priceRule), "the berry rule should read " .. show(priceRule))
	local common = samplePet(PC, rarityIds(Config)[1])
	if t:case(common ~= nil and type(TC.FeedBerries) == "function", "PetCatalog has a Common pet and TycoonCatalog.FeedBerries exists") then
		for i, lv in ipairs({ 1, (PC.EvolutionLevels or {})[1] - 1 }) do
			local want = "level-" .. lv .. " Common " .. (i == 1 and "eats " or "") .. "**" .. commas(TC.FeedBerries(common, lv)) .. " berries** for **"
				.. commas(TC.FeedXp(lv, 1)) .. " XP**"
			t:case(has(f, want), "the feed example should read " .. show(want))
		end
	end
	for _, word in ipairs({ "ONE button", "**Feed** spends berries", "**Food never costs Cash**", "**Berry Basket**", "Your garden pets grow more!" }) do
		t:case(has(f, word), "the Food Machine text should say " .. show(word))
	end
	t:case(has(careSource, "Your garden pets grow more!"), "PetCareService has the 'Not enough berries ... Your garden pets grow more!' toast")
	for _, stale in ipairs({ "**Level up**", "Leftover food", "free Feast", "MAX_FEEDS" }) do
		t:case(not has(f, stale), "the Food Machine text still says " .. show(stale) .. " (one Feed button since phase 5)")
	end
	t:case(TC.Foods == nil or #TC.Foods == 0, "TycoonCatalog has no Foods any more (berries are the one food)")
	local legacy = (TC.Berries or {}).LegacyFood or {}
	local old = "a Snack " .. commas(legacy.Snack or 0) .. ", a Meal " .. commas(legacy.Meal or 0) .. " and a Feast " .. commas(legacy.Feast or 0) .. " berries"
	t:case(has(f, old), "the old food conversion should read " .. show(old))
	-- levels
	local cap = PC.MaxPetLevel
	if type(cap) == "function" then
		cap = cap()
	end
	cap = tonumber(cap) or TC.MaxPetLevel
	for _, id in ipairs(rarityIds(Config)) do
		t:case(PC.LevelCap(id) == cap, id .. ": its level cap " .. tostring(PC.LevelCap(id)) .. " is the README's one cap " .. tostring(cap))
	end
	t:case(has(f, "every pet can reach level **" .. cap .. "**"), "every pet reaches level " .. tostring(cap))
	local step = (PC.LevelFactor(2) - PC.LevelFactor(1)) * 100
	t:case(has(f, "**Every level adds " .. num(step) .. " %**"), "every level adds " .. num(step) .. " %")
	local evoLv = PC.EvolutionLevels or {}
	local factors = "(a level-" .. evoLv[2] .. " pet has x" .. num(PC.LevelFactor(evoLv[2])) .. ", a level-" .. cap .. " pet x" .. num(PC.LevelFactor(cap)) .. ")"
	t:case(has(f, factors), "the level factors should read " .. show(factors))
	local twice = "x" .. bonusText(PC, 1) .. " of the bonus after the first EVOLVE, x" .. bonusText(PC, 2) .. " after the second (a level-" .. cap
		.. " pet evolved twice has x" .. num(PC.LevelFactor(cap, 2)) .. ")"
	t:case(has(f, twice), "the evolved level factors should read " .. show(twice))
	local curve = tableRows(lines, "| Level up | XP needed |")
	if t:case(curve ~= nil and #curve >= 4, "no XP curve table (| Level up | XP needed |)") then
		local last = 0
		for _, row in ipairs(curve) do
			local a, b = plain(row[1]):match("^(%d+) %-> (%d+)$")
			a, b = tonumber(a), tonumber(b)
			if t:case(a ~= nil and b == a + 1, "XP curve row " .. show(row[1]) .. " reads 'n -> n+1'") then
				t:case(row[2] == commas(TC.XpToNext(a)), row[1] .. ": " .. show(row[2]) .. " vs " .. commas(TC.XpToNext(a)) .. " XP")
				last = a
			end
		end
		t:case(last == cap - 1, "the XP curve table ends at " .. (cap - 1) .. " -> " .. cap)
	end
	local totals = commas(TC.XpForLevel(evoLv[1])) .. " XP in total to reach level " .. evoLv[1] .. ", " .. commas(TC.XpForLevel(evoLv[2]))
		.. " to reach level " .. evoLv[2] .. " and " .. commas(TC.XpForLevel(cap)) .. " to reach level " .. cap
	t:case(has(f, totals), "the XP totals should read " .. show(totals))
	-- XP from every fight (Phase 5: Dungeon rooms instead of Trials)
	local D, L = BC.Dungeon or {}, BC.LossRules or {}
	local TR, Raid, Ring = BC.Trophies or {}, BC.Raid or {}, BC.Ring or {}
	local src = rowsByName(tableRows(lines, "| Where | XP for every team pet |"))
	local function cell(name)
		return (src[name] or {})[2] or ""
	end
	local room = num(D.XpBase) .. " + " .. num(D.XpPerFloor) .. " x the floor for every wave (the boss room counts " .. num(D.BossRoomWaves) .. ")"
	t:case(cell("A Dungeon room") == room, "Dungeon room XP " .. show(cell("A Dungeon room")) .. " vs " .. show(room))
	t:case(math.abs((tonumber(L.LossShare) or 0) - 1 / 3) < 1e-6 and has(cell("A lost Dungeon room"), "a third of its XP")
		and has(cell("A lost Dungeon room"), num(L.LossMinSeconds) .. " seconds or more") and has(cell("A lost Dungeon room"), num((L.LossMinDamage or 0) * 100) .. " %"),
		"lost room XP " .. show(cell("A lost Dungeon room")))
	t:case(cell("A duel") == num(TR.Xp.Win) .. " for a win, " .. num(TR.Xp.Loss) .. " for a draw or a loss", "duel XP " .. show(cell("A duel")))
	local lo, hi = math.huge, 0
	for _, tier in ipairs(Raid.Tiers or {}) do
		lo, hi = math.min(lo, tier.Xp), math.max(hi, tier.Xp)
	end
	t:case(cell("A Boss Raid") == num(lo) .. " up to " .. num(hi) .. " by your tier (" .. num(Raid.LossXp) .. " when the boss wins)", "raid XP " .. show(cell("A Boss Raid")))
	t:case(has(cell("A Champion Ring round"), Ring.XpBase .. " + " .. Ring.XpPerRound .. " x the round") and has(cell("A Champion Ring round"), "pays a third"),
		"ring XP " .. show(cell("A Champion Ring round")))
	t:case(src["A Trial win"] == nil and src["A lost Trial"] == nil, "the XP table has no Trial rows any more")
	t:report()
end

local function checkEvolution(PC, Config, evoText)
	local t = T.tally("docs: evolution (levels, boosts, which rarities evolve twice) matches PetCatalog", 6)
	local f = flat(evoText)
	local lv = PC.EvolutionLevels or {}
	local b1, b2 = bonusText(PC, 1), bonusText(PC, 2)
	t:case(has(f, "At level **" .. tostring(lv[1]) .. "** every pet is \"Ready to evolve!\""), "the first evolution at level " .. tostring(lv[1]))
	t:case(has(f, "**EVOLVE!**") and has(f, "**EVOLVE**"), "the EVOLVE! pill and the EVOLVE button are named")
	t:case(PC.EvolutionBoost == nil and PC.EvolutionMultiplier == nil and has(f, "Level bonus x" .. b1), "evolved pets: Level bonus x" .. b1 .. " (the old flat boost is gone)")
	t:case(has(f, "at level **" .. tostring(lv[2]) .. "**") and has(f, "x" .. b2),
		"the second evolution at level " .. tostring(lv[2]) .. " (Level bonus x" .. b2 .. ")")
	local twice, once = {}, {}
	for _, id in ipairs(rarityIds(Config)) do
		if (PC.MaxEvolution({ Rarity = id }) or 0) >= 2 then
			twice[#twice + 1] = id
		else
			once[#once + 1] = id
		end
	end
	t:case(#twice > 0 and has(f, "**" .. andList(twice) .. "** pets evolve a second time"), "evolving twice: " .. andList(twice))
	t:case(#once > 0 and has(f, andList(once) .. " pets evolve once"), "evolving once: " .. andList(once))
	t:report()
end

local function checkTraining(TC, BC, PC, Config, lines, trainText)
	local t = T.tally("docs: the Training Place (skills, ranks, cost, time, spots, the lock) matches BattleCatalog / TycoonCatalog", 6)
	local f = flat(trainText)
	local TR = BC.Training or {}
	local skills = BC.TrainingSkills or {}
	local rows, header = tableRows(lines, "| Skill | Each rank |")
	if t:case(rows ~= nil, "no skill table (| Skill | Each rank | At rank N |)") then
		t:case(header[3] == "At rank " .. tostring(TR.MaxRank), "the skill table's last column is 'At rank " .. tostring(TR.MaxRank) .. "'")
		t:case(#rows == #skills, "the skill table has " .. #rows .. " rows, BattleCatalog " .. #skills .. " skills")
		for i, sk in ipairs(skills) do
			local row = rows[i] or {}
			local sign = sk.Id == "Defense" and "-" or "+"
			local want = sign .. num((TR[sk.Id] or 0) * (TR.MaxRank or 0) * 100) .. " %"
			t:case(plain(row[1]) == sk.Name and row[2] == sk.Text and row[3] == want, "skill " .. i .. ": the README says "
				.. show(row[1]) .. " / " .. show(row[2]) .. " / " .. show(row[3]) .. ", BattleCatalog " .. sk.Name .. " / " .. sk.Text .. " / " .. want)
		end
	end
	local C = TC.Training or {}
	t:case(has(f, "goes up to rank " .. tostring(TR.MaxRank)) and C.MaxRank == TR.MaxRank, "every skill goes up to rank " .. tostring(TR.MaxRank))
	t:case(has(f, "**" .. num(C.CostBase) .. " x N x N** Cash x the pet's rarity"), "rank N costs " .. tostring(C.CostBase) .. " x N x N")
	local common = samplePet(PC, rarityIds(Config)[1])
	if common then
		local all = 0
		for _ = 1, #skills do
			for r = 1, TR.MaxRank do
				all = all + TC.TrainCost(common, r)
			end
		end
		local want = "a Common pays $" .. commas(TC.TrainCost(common, 1)) .. " for rank 1 and $" .. commas(TC.TrainCost(common, TR.MaxRank)) .. " for rank "
			.. TR.MaxRank .. ", all " .. (#skills * TR.MaxRank) .. " ranks together $" .. commas(all)
		t:case(has(f, want), "the cost example should read " .. show(want))
	end
	local scale = (Config.PetStats or {}).RarityScale or {}
	t:case(has(f, "a Legendary x" .. num(scale.Legendary)), "a Legendary pays x" .. num(scale.Legendary))
	local m3 = TC.TrainSeconds(3) / 60
	t:case(has(f, "takes N minutes: **Rank 3 takes " .. num(m3) .. " minutes**") and m3 == 3 * (C.MinutesPerRank or 1), "rank N takes N minutes")
	local gym = TC.ById.Gym
	t:case(has(f, "(1 to " .. num(gym.Effects[gym.MaxLevel].Slots) .. ")") and gym.Effects[1].Slots == 1, "the Training Place trains 1 to "
		.. tostring(gym.Effects[gym.MaxLevel].Slots) .. " pets at once")
	for _, word in ipairs({ "cannot follow you, fight or be fused", "comes back by itself", "**Stop**", "all the Cash back", "Training done while you were away!" }) do
		t:case(has(f, word), "the Training Place text should say " .. show(word))
	end
	t:report()
end

local function checkLegacy(TC, legacyText, tycoonSource, menuSource)
	local t = T.tally("docs: 'Homes from older versions' (the Phase 5 fold, berries, teams, floors, the Phase 4 kept places) matches the game", 6)
	local f = flat(legacyText)
	-- the Phase 5 fold (9.2 step 3, TycoonCatalog.FoldLegacy)
	t:case(type(TC.FoldLegacy) == "function" and (TC.ById.Press2 == nil and TC.ById.Collector == nil and TC.ById.DecorLamps == nil),
		"TycoonCatalog folds the old plants, the Coin Magnet and the old decor (FoldLegacy; no Press2 / Collector / DecorLamps)")
	for _, word in ipairs({ "one **Berry Farm**", "the sum of your old plant levels", "**The Coin Magnet**", "until your next Prestige",
		"**your Home Level never drops**", "**Teams of 3:**", "**Trials became Dungeon floors:**", "**From before phase 4:**" }) do
		t:case(has(f, word), "the section should say " .. show(word))
	end
	local legacy = (TC.Berries or {}).LegacyFood or {}
	local food = "(a Snack " .. commas(legacy.Snack or 0) .. ", a Meal " .. commas(legacy.Meal or 0) .. ", a Feast " .. commas(legacy.Feast or 0) .. ")"
	t:case(has(f, food), "the section should say " .. show(food))
	local names = {}
	for _, id in ipairs({ "DecorFence", "DecorFountain" }) do
		names[#names + 1] = (TC.ById[id] or {}).Name or "?"
	end
	t:case(has(f, "went into the " .. names[1] .. ", the Lanterns into the " .. names[2]), "the old decor went into the " .. names[1] .. " and the " .. names[2])
	local toast = (tycoonSource or ""):match('"(Your home got simpler![^"]*)"')
	if t:case(toast ~= nil, "TycoonService.lua has the 'Your home got simpler!' toast") then
		t:case(has(f, toast), "the section should quote the toast " .. show(toast))
	end
	-- the Phase 4 kept places and prices (still shown by the Home window)
	t:case(has(f, "(up to " .. TC.ById.Garden.MaxLevel .. ")") and has(f, "more than " .. num((TC.Prestige or {}).GardenSlotsBase) .. " + your"),
		"old Garden levels (up to " .. TC.ById.Garden.MaxLevel .. ") above " .. tostring((TC.Prestige or {}).GardenSlotsBase) .. " + stars are kept")
	t:case(has(menuSource, '"Kept from your old home: "') and has(menuSource, '" places and old prices until your next Prestige."')
		and has(f, "\"Kept from your old home: 6 places and old prices until your next Prestige.\""), "the Home window's kept-places tip is quoted as MenuController writes it")
	t:report()
end

local function checkRing(BC, PC, lines, ringText)
	local t = T.tally("docs: the Champion Ring (rounds, bosses, Cash per win, record, XP, tokens) matches BattleCatalog.Ring", 6)
	local f = flat(ringText)
	local R = BC.Ring or {}
	t:case(has(f, "**every " .. tostring(R.BossEvery) .. "th round is a giant boss**"), "a giant boss every " .. tostring(R.BossEvery) .. "th round")
	t:case(has(f, "**" .. num(R.TimeLimit) .. " seconds**") and (BC.TimeLimits or {}).Ring == R.TimeLimit, "a round lasts " .. tostring(R.TimeLimit) .. " seconds")
	t:case(has(f, "you get " .. num(R.Intermission) .. " seconds"), tostring(R.Intermission) .. " seconds between rounds")
	local cash = "the bigger of $" .. R.CashFloorBase .. " + $" .. R.CashFloorPerRound .. " x the round and what your garden makes in "
		.. num(R.SecondsBase) .. " + " .. num(R.SecondsPerRound) .. " x the round seconds (at most " .. num(R.SecondsMax) .. " seconds)"
	t:case(has(f, cash), "the Cash rule should read " .. show(cash))
	t:case(has(f, R.XpBase .. " + " .. R.XpPerRound .. " x the round XP"), "the XP rule " .. tostring(R.XpBase) .. " + " .. tostring(R.XpPerRound) .. " x the round")
	t:case(has(f, "**new record** round pays **x" .. num(R.RecordMult) .. " Cash**"), "a record pays x" .. tostring(R.RecordMult))
	t:case(has(f, "**" .. commas(R.BossTokens) .. " Cloud Tokens**"), "the first boss clear pays " .. tostring(R.BossTokens) .. " tokens")
	t:case(BC.RingRewards(R.BossEvery, 0, true).Tokens == R.BossTokens and BC.RingRewards(R.BossEvery, 0, false).Tokens == 0,
		"RingRewards pays the boss tokens only on a new record boss round, as documented")
	t:case(has(f, "a home and one pet") and has(f, "round 1, or any boss round you have beaten"), "the entry rules and the start picker")
	local rows = tableRows(lines, "| Round | Champion |")
	if t:case(rows ~= nil and #rows >= 5, "no ring table (| Round | Champion | Cash per win (at least) | XP for every team pet |)") then
		local sawBoss = false
		for _, row in ipairs(rows) do
			local r = tonumber(plain(row[1]))
			if t:case(r ~= nil, "ring row " .. show(row[1]) .. " starts with a round number") then
				local rr = BC.RingRewards(r, 0, false)
				t:case(row[3] == "$" .. commas(rr.Cash), "round " .. r .. ": Cash " .. show(row[3]) .. " vs $" .. commas(rr.Cash))
				t:case(row[4] == num(rr.Xp), "round " .. r .. ": XP " .. show(row[4]) .. " vs " .. num(rr.Xp))
				local easy = (R.EasyRounds or {})[r]
				if r % R.BossEvery == 0 then
					sawBoss = true
					t:case(has(row[2], "**Boss:**") and has(row[2], "giant"), "round " .. r .. " is a giant boss round")
				elseif easy then
					local def = PC.Get(easy.PetId)
					t:case(def ~= nil and has(row[2], def.Name), "round " .. r .. ": the champion is " .. tostring(def and def.Name))
				end
				if not easy then
					for _, band in ipairs(R.Bands or {}) do
						if r >= band.From and (band.To == nil or r <= band.To) then
							for _, rarity in ipairs(band.Rarities) do
								t:case(has(row[2], rarity), "round " .. r .. ": the champion should be " .. table.concat(band.Rarities, " or "))
							end
						end
					end
				end
			end
		end
		t:case(sawBoss, "the ring table shows a boss round")
	end
	t:report()
end

local function checkNpcs(lines)
	local t = T.tally("docs: the NPC table names every NpcDialog NPC and its Phase 4-5 topics", 6)
	local N, err = requireModule("shared/NpcDialog")
	if not t:case(N ~= nil and type(N.Npcs) == "table", "shared/NpcDialog loads: " .. tostring(err)) then
		return t:report()
	end
	local rows = tableRows(lines, "| NPC | Talks about |")
	if t:case(rows ~= nil, "no NPC table (| NPC | Talks about |)") then
		t:case(#rows == #N.Npcs, "the NPC table has " .. #rows .. " rows, NpcDialog " .. #N.Npcs .. " NPCs")
		local byName = {}
		for _, row in ipairs(rows) do
			byName[row[1]] = row
		end
		local phase4 = { "Pet Garden", "Economy pets", "Food Machine", "Feed", "EVOLVE", "Training Place", "Champion Ring", "record", "safe zone",
			"portal", "Berry Farm", "Food Bowl", "Cloud Cash", "Berry Basket", "Dungeon", "fighter", "helpers", "ELEMENT", "SWAP", "Obby portal" }
		for _, npc in ipairs(N.Npcs) do
			local row = byName["**" .. npc.Name .. "**, " .. npc.Title]
			if t:case(row ~= nil, "no NPC row '**" .. npc.Name .. "**, " .. npc.Title .. "'") then
				for _, kw in ipairs(npc.Keywords or {}) do
					for _, p4 in ipairs(phase4) do
						if kw == p4 then
							t:case(lowerHas(row[2], kw), npc.Name .. " talks about " .. show(kw) .. " (NpcDialog keyword): the row never says it")
						end
					end
				end
			end
		end
	end
	t:report()
end

local function checkTutorial4(Steps, tutorialText, tutorialSource)
	local t = T.tally("docs: the tutorial's chapters 2 and 4 (steps, titles, rewards) match TutorialSteps / TutorialService", 6)
	local f = flat(tutorialText)
	local count = {}
	for _, step in ipairs((type(Steps) == "table" and Steps.Steps) or {}) do
		local c = step.Chapter or 1
		count[c] = (count[c] or 0) + 1
		if c == 2 or c == 4 then
			t:case(has(f, "*" .. tostring(step.Title) .. "*"), "chapter " .. c .. "'s step " .. show(step.Title) .. " is not named")
		end
	end
	t:case(count[4] ~= nil and has(f, "fourth chapter teaches the phase 4 pet care in " .. string.lower(NUMBER_WORDS[count[4]] or "?") .. " steps"),
		"chapter 4 has " .. tostring(count[4]) .. " steps")
	local tokens = tutorialSource and tonumber(tutorialSource:match("local RING_FINISH_TOKENS = (%d+)"))
	if t:case(tokens ~= nil, "TutorialService.lua has RING_FINISH_TOKENS") then
		t:case(has(f, "**" .. commas(tokens) .. " Cloud Tokens** at the end. Players who had finished the whole tutorial before phase 4"),
			"the chapter 4 reward of " .. commas(tokens) .. " Cloud Tokens")
	end
	t:report()
end

local function checkOwner4(TC, text, lines, petCardText, devSource)
	local t = T.tally("docs: controls, pet cards, /petlevel, the publish steps and no stale Phase 2-3 wording", 6)
	local f = flat(text)
	-- controls
	local controls = tableRows(lines, "| Action | PC |") or {}
	local all = {}
	for _, row in ipairs(controls) do
		all[#all + 1] = table.concat(row, " | ")
	end
	local c = table.concat(all, "\n")
	for _, word in ipairs({ "put a pet on a pet bed", "the Food Machine (*Feed pets*)", "the Training Place (*Train pets*)", "the Champion Ring",
		"a gate of the Gate Court", "the Obby level picker", "a dungeon chest", "Scoop your Cloud Cash | walk over it", "**Go home**", "**EVOLVE!** pill",
		"**PLAY**" }) do
		t:case(has(c, word), "the controls table should say " .. show(word))
	end
	t:case(not has(c, "Cook") and not has(c, "Collector") and not has(c, "RETREAT") and not has(c, "Trial Portal"),
		"the controls table no longer cooks, banks the Collector, RETREATs or opens the Trial Portal")
	-- pet cards
	local p = flat(petCardText)
	for _, word in ipairs({ "keeping its distance from you and from the others", "Big pets keep further back", "**Lv 12**", "(★ / ★★)", "blue XP bar",
		"**EVOLVE!** pill", "purple timer bar", "SPECIAL bar" }) do
		t:case(has(p, word), "the pet card text should say " .. show(word))
	end
	-- /petlevel
	local cap = TC.MaxPetLevel
	local row = rowsByName(tableRows(lines, "| Command | What it does |"))["/petlevel 20"]
	t:case(row ~= nil and has(row[2], "(1-" .. tostring(cap)), "the /petlevel row should give the range 1-" .. tostring(cap))
	t:case(devSource ~= nil and devSource:find('"petlevel"', 1, true) ~= nil, "DevService has the petlevel command")
	-- the owner's publish steps
	for _, word in ipairs({ "Publish to Roblox", "**Migrate to Latest Update**", "**Shut Down All Servers**", "old and new servers run side by side" }) do
		t:case(has(f, word), "the publish steps should say " .. show(word))
	end
	-- stale wording from Phase 2 / 3 (and nothing about any website)
	for _, stale in ipairs({ "While you were away:", "Train in Gym", "Cook Snack", "Place in Garden", "fly beside", "flies beside", "bank the Collector",
		"Cloud Presses puff", "button for players comes later", "level 50 cap", "Scoop your rainbow coins", "Level up** buys", "Leftover food |" }) do
		t:case(not has(f, stale), "the README still says " .. show(stale))
	end
	t:case(not lowerHas(text, "etsemiq"), "the README never names the Etsemiq website (the game has nothing to do with it)")
	t:report()
end

local function checkPhase4(Config, PC, TC, Steps, lines, text, sub)
	local BC, err = requireModule("shared/BattleCatalog")
	if not T.check(BC ~= nil, "docs: shared/BattleCatalog loads (Phase 4)", err) then
		return
	end
	local tycoonSource = readFile("src/server/Services/TycoonService.lua")
	checkTopics4(sub("## What's new in phase 4"))
	checkGarden(TC, PC, Config, lines, sub("### The Pet Garden"), (readFile("src/client/Controllers/HomeFx.lua")))
	checkFoodMachine(TC, PC, BC, Config, lines, sub("### The Food Machine"), (readFile("src/server/Services/PetCareService.lua")))
	checkEvolution(PC, Config, sub("### Evolution"))
	checkTraining(TC, BC, PC, Config, lines, sub("### The Training Place"))
	checkLegacy(TC, sub("### Homes from older versions"), tycoonSource, (readFile("src/client/Controllers/MenuController.lua")))
	checkRing(BC, PC, lines, sub("### The Champion Ring"))
	checkNpcs(lines)
	checkTutorial4(Steps, sub("## First steps"), (readFile("src/server/Services/TutorialService.lua")))
	checkOwner4(TC, text, lines, sub("### Pet cards and following"), (readFile("src/server/Services/DevService.lua")))
end

----------------------------------------------------------------------------------------------------
-- Phase 5: the Big Sky Update (the "## Phase 5: the Big Sky Update" bullets with the catalogs' numbers) and the owner
-- checklist "## Phase 5: owner checklist" (ARCHITECTURE_V3.md 10.6: steps 0-7, one needle per step; judge M9)
----------------------------------------------------------------------------------------------------
local TOPICS5 = {
	{ "teams of 3: a fighter and two helpers", { "**FIGHTER**", "**HELPERS**", "**buff**", "**SWAP**", "three lives", "RETREAT is gone" } },
	{ "the new battle controls (keys and touch)", { "**ATTACK**", "**ELEMENT**", "**SPECIAL**", "**DASH**", "`F`", "`E`", "`Q`", "`Shift`", "`Tab`", "`1` / `2`", "big touch buttons" } },
	{ "helpers / Supporters", { "Supporters", "**Heal**", "**Shield**", "**Rally**", "**Haste**", "about 70 %", "battle power" } },
	{ "levels and evolutions", { "+10 %", "EVOLVE", "Nobody gets weaker" } },
	{ "the Dungeon (floors, party, loot)", { "**The Dungeon**", "boss room", "loot", "first time pays big Tokens and Gems", "Trial record" } },
	{ "one obby portal with a level picker", { "**level picker**", "Easy, Medium, Hard, Extreme or Saint", "beating a level unlocks the next" } },
	{ "the Gate Court", { "Gate Court", "Home, Obby, Dungeon, Champion Ring, Arena and Storm Altar" } },
	{ "the Berry Farm, one food and Feed", { "**Berry Farm**", "**Berry Basket**", "ONE button, **Feed**", "never costs Cash" } },
	{ "roaming pets pooping Cloud Cash", { "roam the yard", "Food Bowl", "poop **Cloud Cash**", "only you can" } },
	{ "fewer, cheaper decor", { "three decorations", "Yard Fence", "Fountain", "Pet Podium", "much cheaper" } },
	{ "evolved looks everywhere", { "**Evolved pets look evolved everywhere:**" } },
	{ "followers spaced", { "**Pets follow better.**", "keeps its distance", "out of the camera's way" } },
	{ "the sky and the new look", { "pink-purple cloud sky with stars", "bigger plaza", "never cover the whole screen" } },
	{ "loading screen, main menu, settings", { "loading screen", "main menu", "**PLAY**", "**SETTINGS**", "**UPDATES**", "camera shake" } },
	{ "nothing is lost", { "**Nothing is lost.**", "Berry Farm, old snacks became berries", "4th team pet" } },
	{ "the owner's new tools", { "`/berries [n]`", "`/menu`", "owner checklist" } },
}

-- 10.6: the step number, its needle (in the step's own text) and the extra words the step must give
local CHECKLIST = {
	{ 0, "rojo serve", { "src/shared/Config.lua", "play/NimbusClimb.rbxlx", "Connect", "rojo build" } },
	{ 1, "Migrate to Latest Update", { "Publish to Roblox", "create.roblox.com", "phase 4 and phase 5 servers run together" } },
	{ 2, "Bulk Import", { "Asset Manager", "branding/sky/", "IMAGES", "a Decal id would NOT work", "moderation", "Copy ID", "Config.Sky.Faces", "Swap the `Lf` and `Rt` ids" } },
	{ 3, "Config.Audio", { "Toolbox", "Copy Asset ID", "Empty = silent" } },
	{ 4, "Config.Icons", { "emoji" } },
	{ 5, "ShadowMap", { "default.project.json", "\"Technology\": \"ShadowMap\"", "Graphics: **Low**" } },
	{ 6, "Developer Products", { "Config.Gems.Products", "Product ID" } },
	{ 7, "Output", { "[Config]", "[LightingService]" } },
}

local function checkTopics5(p5)
	local f = flat(p5)
	local t = T.tally("docs: the README's 'Phase 5: the Big Sky Update' covers every part the player asked for", 6)
	for _, topic in ipairs(TOPICS5) do
		for _, word in ipairs(topic[2]) do
			t:case(has(f, word), topic[1] .. ": the section never says " .. show(word))
		end
	end
	t:report()
end

local function checkFacts5(Config, PC, TC, BC, p5, text, lines)
	local t = T.tally("docs: the Phase 5 numbers (team, stamina, Dungeon, stations, evolution) and owner rows match Config / the catalogs / the services", 6)
	local f = flat(p5)
	t:case(BC ~= nil and has(f, "Your battle team is **" .. tostring(BC.TeamSize) .. " pets**"), "the team is " .. tostring(BC and BC.TeamSize) .. " pets")
	local lives = BC and (BC.Fighter or {}).Lives
	t:case(lives ~= nil and NUMBER_WORDS[lives] ~= nil and has(f, NUMBER_WORDS[lives]:lower() .. " lives"), "the fighter has " .. tostring(lives) .. " lives")
	local P = Config.Physics or {}
	local dashes = floor((P.MaxStamina or 0) / (P.DashStaminaCost or 1))
	t:case(has(f, "**More stamina:** **" .. num(P.MaxStamina) .. "**") and has(f, dashes .. " dashes from full"),
		"stamina " .. tostring(P.MaxStamina) .. ", " .. dashes .. " dashes from full (Config.Physics)")
	local refill = string.format("%.1f", (P.MaxStamina or 0) / (P.StaminaRegen or 1))
	t:case(has(f, "refills in about " .. refill .. " seconds"), "the bar refills in about " .. refill .. " seconds")
	local D = (BC and BC.Dungeon) or {}
	t:case(has(f, "**" .. tostring(D.Floors) .. " floors**"), "the Dungeon has " .. tostring(D.Floors) .. " floors")
	local maxParty = sourceNumber((readFile("src/server/Services/DungeonService.lua")), "MAX_PARTY")
	t:case(maxParty ~= nil and has(f, "a party of up to **" .. num(maxParty) .. "** players"), "a party of up to " .. tostring(maxParty) .. " players")
	t:case(TC.Version == 5 and has(f, "**" .. #TC.Stations .. " stations**") and has(text, "A home has **" .. #TC.Stations .. " stations**"),
		"TycoonCatalog Version 5 with " .. #TC.Stations .. " stations ('**N stations**')")
	t:case(has(f, "grows x" .. bonusText(PC, 1) .. ", after the second x" .. bonusText(PC, 2)), "the level bonus grows x" .. bonusText(PC, 1) .. " / x" .. bonusText(PC, 2))
	local S = (BC and (BC.Roles or {}).Support) or {}
	local ratio = (S.Power or 0) > 0 and has(f, "about 70 %")
	t:case(ratio, "Support pets hit for about 70 % (BattleCatalog.Roles.Support)")
	-- the developer rows
	local cmds = rowsByName(tableRows(lines, "| Command | What it does |"))
	t:case(cmds["/berries [n]"] ~= nil and has(text, "`/berries [n]`"), "the chat command table has a '/berries [n]' row")
	local devController = readFile("src/client/Controllers/DevController.lua")
	t:case(cmds["/menu"] ~= nil and has(devController, "/menu"), "the chat command table has a '/menu' row (DevController's /menu)")
	t:case(not has(text, "4th slot") and not has(text, "slot 4 opens") and not has(text, "slot opens at Prestige"), "no 'slot 4 opens at Prestige 1' line")
	-- the main menu and settings: what the README names exists
	local U = requireModule("shared/UpdateNotes")
	t:case(U ~= nil and tonumber(U.Latest) == 5, "UpdateNotes.Latest is 5 (the Big Sky Update)")
	t:case((Config.Loading or {}).SkipAfter ~= nil and has(flat(text), "**SKIP** appears after " .. num((Config.Loading or {}).SkipAfter) .. " seconds"),
		"the loading screen's SKIP after " .. tostring((Config.Loading or {}).SkipAfter) .. " seconds (Config.Loading.SkipAfter)")
	t:report()
end

local function checkChecklist5(Config, ownerText)
	local t = T.tally("docs: 'Phase 5: owner checklist' is numbered 0-7 like ARCHITECTURE_V3.md 10.6, one needle per step", 6)
	-- the numbered steps (a line "N. ..." at column 0) and their text up to the next step
	local steps, order = {}, {}
	local cur = nil
	for _, line in ipairs(splitLines(ownerText or "")) do
		local n = line:match("^(%d+)%. ")
		if n then
			cur = tonumber(n)
			order[#order + 1] = cur
			steps[cur] = line
		elseif cur ~= nil and line:match("^%s+%S") then
			steps[cur] = steps[cur] .. " " .. line
		elseif line:match("^%S") then
			cur = nil
		end
	end
	t:case(#order == #CHECKLIST, "the checklist has " .. #order .. " numbered steps, 10.6 has " .. #CHECKLIST)
	for i, spec in ipairs(CHECKLIST) do
		local step = steps[spec[1]]
		if t:case(order[i] == spec[1] and step ~= nil, "step " .. spec[1] .. " is the checklist's step number " .. i .. " (got " .. tostring(order[i]) .. ")") then
			local fs = flat(step)
			t:case(has(fs, spec[2]), "step " .. spec[1] .. " has its needle " .. show(spec[2]))
			for _, word in ipairs(spec[3]) do
				t:case(has(fs, word), "step " .. spec[1] .. " should say " .. show(word))
			end
		end
	end
	-- step 2: the six face keys of Config.Sky.Faces, the images in branding/sky/
	local faces = sortedKeys((Config.Sky or {}).Faces)
	local s2 = flat(steps[2] or "")
	t:case(#faces == 6 and has(s2, "(" .. table.concat(faces, " ") .. ")"), "step 2 names the six Config.Sky.Faces keys (" .. table.concat(faces, " ") .. ")")
	for _, key in ipairs(faces) do
		local png = readFile("branding/sky/Skybox" .. key .. ".png")
		t:case(png ~= nil and #png > 1000 and has(s2, "`Skybox" .. key .. "`"), "branding/sky/Skybox" .. key .. ".png exists and step 2 names it")
	end
	-- step 3: every music and sound name of Config.Audio
	local A = Config.Audio or {}
	local s3 = flat(steps[3] or "")
	for _, group in ipairs({ "Music", "Sfx" }) do
		for _, key in ipairs(sortedKeys(A[group])) do
			t:case(has(s3, "`" .. key .. "`") or has(s3, "." .. key .. "`"), "step 3 names Config.Audio." .. group .. "." .. key)
		end
	end
	t:case(type(Config.Icons) == "table", "Config.Icons exists (step 4)")
	-- step 5: the project file says ShadowMap (phase 6: back to the bright cartoon look)
	local project = readFile("default.project.json")
	t:case(has(project, "\"Technology\": \"ShadowMap\""), "default.project.json has the line '\"Technology\": \"ShadowMap\"' that step 5 quotes")
	-- step 6: the sample is the first Config.Gems.Products pack
	local first = ((Config.Gems or {}).Products or {})[1] or {}
	t:case(has(flat(steps[6] or ""), "{ Id = ..., Gems = " .. tostring(first.Gems) .. ", Name = \"" .. tostring(first.Name) .. "\" }"),
		"step 6 quotes the first Config.Gems.Products pack")
	t:report()
end

local function checkPhase5(Config, PC, TC, lines, text, sub)
	local BC = requireModule("shared/BattleCatalog")
	local p5 = sub("## Phase 5: the Big Sky Update")
	if p5 ~= "" then
		checkTopics5(p5)
		checkFacts5(Config, PC, TC, BC, p5, text, lines)
	end
	local owner = sub("## Phase 5: owner checklist")
	if owner ~= "" then
		checkChecklist5(Config, owner)
	end
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
	checkVault(TC, lines, sub("### The Vault"), (readFile("src/server/Services/TycoonService.lua")))
	checkPrestige(TC, sub("### Prestige"))
	checkFusion(TC, Config, lines, sub("### The Fusion Machine"))
	checkGems(Config, PC, lines, sub("### Gems"), sub("### Selling Gems"), text)
	checkDev(Config, Theme, lines, (readFile("src/server/Services/DevService.lua")))
	checkTutorial(Config, Steps, sub("## First steps"), (readFile("src/server/Services/TutorialService.lua")))
	checkLayout(sub("## Project layout"), sub("## Rebuilding the place file"))
	checkAnchors(lines, fences, text)
	checkPhase3(Config, PC, TC, Steps, lines, text, sub)
	checkPhase4(Config, PC, TC, Steps, lines, text, sub)
	checkPhase5(Config, PC, TC, lines, text, sub)
	T.eq(#game:GetDescendants(), before, "docs: the checks are pure (no Instances created)")
	K.flushErrors("p2final_docs")
end)

return S
