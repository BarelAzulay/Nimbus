-- NpcDialog: the six NPC pets of the lobby and what they say (ARCHITECTURE_V3.md section 5). Data only, no
-- Instances, so the server (NpcService builds the NPCs) and the client (NpcController shows the dialog) share it.
--
--   NpcDialog.Npcs            array in lobby-spot order: { Id, Name, Title, PetId, Species, Scale, Accent, Keywords,
--                             ColorWords (optional: word -> Color3), Lines = { "...", ... } }   (3-5 short lines each)
--   NpcDialog.ById[id]        the same entries by id
--   NpcDialog.Get(id) -> entry | nil
--   NpcDialog.GetLines(id) -> { line, ... }   (empty table for an unknown id)
--   NpcDialog.Tag             "NC_Npc", the CollectionService tag of every NPC model (attribute NpcId = entry.Id)
--   NpcDialog.Settings        shared numbers (scale, prompt / close distances, hover gap)
--
-- The tips quote the game's real numbers: prices, bonuses, odds and rewards are read from Config /
-- TycoonCatalog / PetCatalog / BattleCatalog when this module loads, so they stay correct when those change. Phase 4
-- tips (pets make the money): claiming a home, the Pet Garden's rainbow coins, the food plants, Prestige and the home
-- portal (Mayor Panda), the Food Machine, Feed and EVOLVE (Granny Owl), the Training Place and the Champion Ring
-- (Coach Corgi), the Fusion Machine, Gems and the Secret roulette at the Storm Altar (Professor Axolotl). Phase 3 tips
-- (pet battles): the battle controls (Sparky Fox), Boss Raids and the safe zones (Captain Penguin), the Trial Portal
-- and battle teams (Coach Corgi), elements and team synergy in battle (Professor Axolotl), all quoting BattleCatalog.
-- Phase 5 ("Phase 5 build contract" 8): the Berry Farm, the Food Bowl, Cloud Cash and the Berry Basket (Mayor Panda,
-- Granny Owl), evolved pets growing faster and looking evolved (Granny Owl, PetCatalog.EvolutionBonusOf), the Dungeon
-- (Coach Corgi, BattleCatalog.Dungeon.Floors), the team of a fighter + 2 helpers and the battle keys (Coach Corgi,
-- Sparky Fox), the ONE Obby portal with its level picker and DASH out of telegraphs (Captain Penguin). No Trial, no
-- four plants, no Coin Magnet, no RETREAT.
-- Nimbus the Cloudy Dragon is NOT an NPC: it is
-- the tutorial guide. `Keywords` are phrases the dialog box highlights (numbers are highlighted automatically),
-- `ColorWords` words it paints in their own colour (the element names).
-- Lines never contain "<", ">" or "&" (the client renders them as rich text).
-- Plain Lua 5.1-compatible syntax only.

local Config = require(script.Parent:WaitForChild("Config"))

local TycoonCatalog = nil
do
	local ok, mod = pcall(function()
		return require(script.Parent:WaitForChild("TycoonCatalog", 5))
	end)
	if ok and type(mod) == "table" then
		TycoonCatalog = mod
	end
end

-- Phase 4: evolution levels and boosts, the Economy role bonus (PetCatalog); optional
local PetCatalog = nil
do
	local module = script.Parent:FindFirstChild("PetCatalog")
	if module then
		local ok, mod = pcall(require, module)
		if ok and type(mod) == "table" then
			PetCatalog = mod
		end
	end
end

-- Phase 3: the battle numbers (raid schedule, trial count, trophies, synergy); optional
local BattleCatalog = nil
do
	local module = script.Parent:FindFirstChild("BattleCatalog")
	if module then
		local ok, mod = pcall(require, module)
		if ok and type(mod) == "table" then
			BattleCatalog = mod
		end
	end
end

local NpcDialog = {}

NpcDialog.Tag = "NC_Npc"

NpcDialog.Settings = {
	Scale = 2.2, -- PetBuilder scale of every NPC pet
	PromptDistance = 10, -- ProximityPrompt.MaxActivationDistance
	CloseDistance = 16, -- the dialog closes when the player walks this far from the NPC
	HoverGap = 1.0, -- studs between the pedestal cushion and the lowest voxel of the pet
}

----------------------------------------------------------------------
-- Number helpers (the tips quote Config)
----------------------------------------------------------------------
local TOKEN = "\226\152\129" -- the cloud glyph used for Cloud Tokens everywhere

local function commas(n)
	local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

local function tokens(n)
	return commas(n) .. " " .. TOKEN
end

local function percent(fraction)
	local p = (tonumber(fraction) or 0) * 100
	if math.abs(p - math.floor(p + 0.5)) < 0.05 then
		return tostring(math.floor(p + 0.5)) .. "%"
	end
	return string.format("%.1f%%", p)
end

local function number(n)
	n = tonumber(n) or 0
	if math.abs(n - math.floor(n + 0.5)) < 1e-6 then
		return tostring(math.floor(n + 0.5))
	end
	return (string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", ""))
end

local function shortName(roulette)
	if type(roulette.Id) == "string" and roulette.Id ~= "" then
		return roulette.Id
	end
	return (tostring(roulette.DisplayName or "?"):gsub(" Roulette$", ""))
end

-- "A, B and C"
local function joinAnd(list)
	if #list == 0 then
		return ""
	elseif #list == 1 then
		return list[1]
	end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

----------------------------------------------------------------------
-- Lines built from Config
----------------------------------------------------------------------
local P = Config.Physics or {}
local M = Config.Match or {}
local T = Config.Tokens or {}
local D = Config.Damage or {}

-- "Cloud 50 ☁ up to Celestial 5,000 ☁": the cheapest and the priciest token roulette
local function rouletteRange()
	local low, high = nil, nil
	for _, r in ipairs(Config.Roulettes or {}) do
		if tonumber(r.Price) then
			if not low or r.Price < low.Price then
				low = r
			end
			if not high or r.Price > high.Price then
				high = r
			end
		end
	end
	if not low then
		return "the roulettes"
	end
	if low == high then
		return shortName(low) .. " " .. tokens(low.Price)
	end
	return shortName(low) .. " " .. tokens(low.Price) .. " up to " .. shortName(high) .. " " .. tokens(high.Price)
end

-- "Sky (3%) and Celestial (15%)": every roulette that can roll a Mythic, with its chance
local function mythicChances()
	local parts = {}
	for _, r in ipairs(Config.Roulettes or {}) do
		local odds = r.Odds or {}
		local total = 0
		for _, w in pairs(odds) do
			total = total + (tonumber(w) or 0)
		end
		local w = tonumber(odds.Mythic) or 0
		if w > 0 and total > 0 then
			parts[#parts + 1] = shortName(r) .. " (" .. percent(w / total) .. ")"
		end
	end
	return joinAnd(parts)
end

-- Index rewards of the lowest and the highest token-roulette rarity ("50 ☁ for Commons up to 5,000 ☁ for Mythics")
local function indexRewardRange()
	local rewards = (Config.Index and Config.Index.Rewards) or {}
	local low, high = nil, nil
	for _, rarity in ipairs(Config.Rarities or {}) do
		local r = rewards[rarity.Id]
		if rarity.Id ~= "Secret" and type(r) == "table" and tonumber(r.Tokens) then
			if not low then
				low = { rarity.Id, r.Tokens }
			end
			high = { rarity.Id, r.Tokens }
		end
	end
	if not low then
		return "a big token prize"
	end
	return tokens(low[2]) .. " for " .. low[1] .. "s up to " .. tokens(high[2]) .. " for " .. high[1] .. "s"
end

-- The element wheel as "A beats B" pairs, starting at Water, plus the two-way rivals.
local function elementWheel()
	local E = Config.Elements or {}
	local strong = E.Strong or {}
	local order = E.Order or {}
	local pairsList = {}
	local seen = {}
	local start = order[1] or "Water"
	local cur = start
	for _ = 1, #order do
		local beats = strong[cur] and strong[cur][1]
		if not beats or seen[cur] then
			break
		end
		seen[cur] = true
		pairsList[#pairsList + 1] = cur .. " beats " .. beats
		cur = beats
		if cur == start then
			break
		end
	end
	local rivals = {}
	for _, id in ipairs(order) do
		local beats = strong[id] and strong[id][1]
		if beats and not seen[id] and strong[beats] and strong[beats][1] == id and not seen[beats] then
			seen[id] = true
			seen[beats] = true
			rivals[#rivals + 1] = { id, beats }
		end
	end
	return pairsList, rivals
end

local wheel, rivals = elementWheel()
local half = math.ceil(#wheel / 2)
local wheelA, wheelB = {}, {}
for i, text in ipairs(wheel) do
	if i <= half then
		wheelA[#wheelA + 1] = text
	else
		wheelB[#wheelB + 1] = text
	end
end
local rivalLine
if rivals[1] then
	rivalLine = rivals[1][1] .. " and " .. rivals[1][2] .. " beat each other!"
else
	rivalLine = "Some elements are rivals and beat each other!"
end
-- element name -> its colour (the dialog paints the element names in their own colours)
local function elementColors()
	local out = {}
	local info = (Config.Elements and Config.Elements.Info) or {}
	for name, e in pairs(info) do
		if type(e) == "table" and typeof(e.Color) == "Color3" then
			out[name] = e.Color
		end
	end
	return out
end

local strongMul = number((Config.Elements and Config.Elements.StrongMultiplier) or 1.5)
local weakMul = number((Config.Elements and Config.Elements.WeakMultiplier) or 0.75)

----------------------------------------------------------------------
-- Phase 2 numbers (TycoonCatalog: the home stations, food, the Gym, house tiers, Prestige, the Fusion Machine)
----------------------------------------------------------------------
local TC = TycoonCatalog or {}
local G = Config.Gems or {}

-- "Attack Speed, Physique, Ability or Defense" (BattleCatalog.TrainingSkills, read below)
local function trainLine(skills)
	return "Your Training Place makes pets tougher: train " .. skills .. ". They rest at home while they train!"
end

local PR = type(TC.Prestige) == "table" and TC.Prestige or {}
local prestigeLevel = number(PR.HomeLevel or 40)
local prestigeMul = number(PR.IncomeMultiplier or 1.25)
local prestigeGems = commas(PR.GemReward or 100)
local castleName = "Sky Castle"
do
	local tiers = type(TC.HouseTiers) == "table" and TC.HouseTiers or nil
	local last = tiers and tiers[#tiers]
	if type(last) == "table" and type(last.Name) == "string" then
		castleName = last.Name
	end
end
local tierMul = type(TC.TierMultiplier) == "table" and TC.TierMultiplier or {}
local goldenMul = number(tierMul.Golden or 1.5)
local rainbowMul = number(tierMul.Rainbow or 2.5)
local fusionCopies = number((type(TC.Fusion) == "table" and TC.Fusion.Copies) or 3)
local fusionWhen = "After your first Prestige"
if tonumber(PR.FusionUnlock) and tonumber(PR.FusionUnlock) ~= 1 then
	fusionWhen = "From Prestige " .. number(PR.FusionUnlock)
end
local secretRoulette = type(G.SecretRoulette) == "table" and G.SecretRoulette or {}
local secretPrice = commas(secretRoulette.GemPrice or 1500)
local cheapGemSpin = nil
do
	local prices = type(G.RouletteGemPrices) == "table" and G.RouletteGemPrices or {}
	for _, r in ipairs(Config.Roulettes or {}) do
		if tonumber(prices[r.Id]) and not cheapGemSpin then
			cheapGemSpin = shortName(r) .. " spin costs just " .. commas(prices[r.Id]) .. " Gems"
		end
	end
end
-- Phase 4 numbers (PetCatalog: evolution; TycoonCatalog: Prestige garden places; BattleCatalog: the ring record)
local PC = PetCatalog or {}
local evoLevels = type(PC.EvolutionLevels) == "table" and PC.EvolutionLevels or { 20, 50 }
-- Phase 5 (3.1): EVOLVE multiplies the level bonus (PetCatalog.EvolutionBonusOf: x1.5 / x1.875)
local evoBonusOf = type(PC.EvolutionBonusOf) == "function" and tonumber(PC.EvolutionBonusOf(1)) or 1.5
-- "50%": how much faster an evolved pet's level bonus grows (EvolutionBonusOf(1) = 1.5 -> 50%)
local evoFaster = percent(math.max(0, evoBonusOf - 1))
local placesPerStar = tonumber(PR.GardenSlotsPerStar) or 1
local placeWord = placesPerStar == 1 and "one more garden place" or (number(placesPerStar) .. " more garden places")

----------------------------------------------------------------------
-- Phase 3 numbers (BattleCatalog: raids, trials, trophies, synergy)
----------------------------------------------------------------------
local BC = BattleCatalog or {}
local skillNames = {}
do
	local list = type(BC.TrainingSkills) == "table" and BC.TrainingSkills or {}
	for _, skill in ipairs(list) do
		if type(skill) == "table" and type(skill.Name or skill.Id) == "string" then
			skillNames[#skillNames + 1] = skill.Name or skill.Id
		end
	end
	if #skillNames == 0 then
		skillNames = { "Attack Speed", "Physique", "Ability", "Defense" }
	end
end
local skillList = table.concat(skillNames, ", ", 1, math.max(1, #skillNames - 1))
if #skillNames > 1 then
	skillList = skillList .. " or " .. skillNames[#skillNames]
end
local recordWord = "triple"
do
	local mult = type(BC.Ring) == "table" and tonumber(BC.Ring.RecordMult) or 3
	if mult == 2 then
		recordWord = "double"
	elseif mult ~= 3 then
		recordWord = "x" .. number(mult)
	end
end
local raidMinutes, floorCount, trophyWin, synergyPair = 20, 12, 20, "10%"
do
	local events = type(BC.Events) == "table" and BC.Events or {}
	local first = type(events.Schedule) == "table" and events.Schedule[1] or nil
	if type(first) == "table" and tonumber(first.EveryMinutes) then
		raidMinutes = math.floor(tonumber(first.EveryMinutes))
	end
	-- Phase 5: the Dungeon's floors (BattleCatalog.Dungeon.Floors, a count; DungeonFloors as a fallback)
	local dungeon = type(BC.Dungeon) == "table" and BC.Dungeon or {}
	if tonumber(dungeon.Floors) then
		floorCount = math.floor(tonumber(dungeon.Floors))
	elseif type(BC.DungeonFloors) == "table" and #BC.DungeonFloors > 0 then
		floorCount = #BC.DungeonFloors
	end
	if type(BC.Trophies) == "table" and tonumber(BC.Trophies.Win) then
		trophyWin = math.floor(tonumber(BC.Trophies.Win))
	end
	local rules = type(BC.SynergyRules) == "table" and BC.SynergyRules or nil
	if rules and type(rules.SameElement) == "table" and tonumber(rules.SameElement[2]) then
		synergyPair = percent(rules.SameElement[2])
	end
end

----------------------------------------------------------------------
-- The NPCs (order = lobbyInfo.NpcSpots order: the two by the portals, the two beside the boardwalk to the
-- shop, then the two on the lawns towards the shop)
----------------------------------------------------------------------
NpcDialog.Npcs = {
	{
		Id = "sparky_fox",
		Name = "Sparky Fox",
		Title = "Movement Trainer",
		PetId = "aurora_fox",
		Species = "Fox",
		Accent = Color3.fromRGB(64, 188, 192),
		Keywords = { "Shift", "RUN", "DASH!", "DASH", "Q", "checkpoint", "ATTACK", "ELEMENT", "SPECIAL", "helper", "SWAP" },
		Lines = {
			"Zap! Hold Shift to run (the RUN button on phones; Ctrl in a battle). Running drains stamina, walking refills it.",
			"Press Q to dash (DASH on phones). It costs " .. number(P.DashStaminaCost or 35) .. " stamina, recharges in "
				.. number(P.DashCooldown or 1.6) .. " seconds and works in mid-air!",
			"See a DASH! sign? That gap is too wide for a jump alone: jump first, then dash while you are in the air.",
			-- HUD cleanup: the obby items are gone; the checkpoint heal is the way back up
			"Low on health in a climb? Reach the next checkpoint: everyone still up heals "
				.. percent(Config.Damage.CheckpointHealFraction) .. " there.",
			"Pets attack by themselves! F = ATTACK picks who, E = ELEMENT, Q = SPECIAL, Shift = DASH, 1 or 2 = a helper, hold it to SWAP!",
		},
	},
	{
		Id = "captain_penguin",
		Name = "Captain Penguin",
		Title = "Co-op Captain",
		PetId = "frostling_penguin",
		Species = "Penguin",
		Accent = Color3.fromRGB(88, 148, 226),
		Keywords = { "Obby portal", "level", "next checkpoint", "Boss Raid", "DASH", "safe zone", "Battle Arena", "Dungeon" },
		Lines = {
			"Ahoy! Hop on the Obby portal pad together: up to " .. number(M.MaxPlayers or 4) .. " climbers sail one course. Beat a level to unlock the next!",
			"Teammate down? Keep climbing! Reaching the next checkpoint revives everyone who is down.",
			"A fallen teammate comes back at the next checkpoint with half health, so keep climbing and ring it for them!",
			"A Boss Raid starts every " .. raidMinutes .. " minutes in the arena: everyone fights one giant boss together!",
			"Outside the Battle Arena, the rings and the Dungeon it's a safe zone: no battles. In a fight, DASH out of glowing circles!",
		},
	},
	{
		Id = "granny_owl",
		Name = "Granny Owl",
		Title = "Pet Expert",
		PetId = "sleepy_owl",
		Species = "Owl",
		Accent = Color3.fromRGB(160, 126, 222),
		Keywords = { "roulette", "shop island", "Mythic", "Pet Index", "Gems", "Berry Basket", "Food Machine", "Feed", "EVOLVE", "evolved" },
		Lines = {
			"Hoo-hoo! New pets hatch from the roulettes on the shop island: " .. rouletteRange() .. ". Pricier means rarer!",
			"Mythic pets only appear in the " .. mythicChances() .. " roulettes. "
				.. (cheapGemSpin and ("Gems buy spins too: a " .. cheapGemSpin .. "!") or "The shop shows every chance."),
			"Every pet you find fills the Pet Index. Complete a rarity group for a reward: " .. indexRewardRange() .. "!",
			"Your farm fills the Berry Basket. Press E at the Food Machine, pick a pet and press Feed: berries become XP!",
			"At level " .. number(evoLevels[1] or 20) .. " press EVOLVE for a new look! Evolved pets grow " .. evoFaster
				.. " faster per level. Epic+ evolve again at " .. number(evoLevels[2] or 50) .. ".",
		},
	},
	{
		Id = "coach_corgi",
		Name = "Coach Corgi",
		Title = "Token Coach",
		PetId = "waffle_corgi",
		Species = "Dog",
		Accent = Color3.fromRGB(240, 174, 70),
		Keywords = { "yours to keep", "Dungeon", "Training Place", "Champion Ring", "record", "Team", "trophies", "fighter", "helpers" },
		Lines = {
			"Woof! Coins you grab on a climb are yours to keep. Tap Team, then duel friends in the arena: +" .. trophyWin .. " trophies a win!",
			"The Dungeon portal on the plaza has " .. floorCount .. " floors of rooms, waves and bosses. Every first clear pays big token bonuses and Gems!",
			trainLine(skillList),
			"Try the Champion Ring on the plaza: one champion after another, each stronger. Beat your record for "
				.. recordWord .. " Cash!",
			"Your team is a fighter and two helpers. Your fighter attacks by itself: ATTACK picks who; tap a helper for its buff!",
		},
	},
	{
		Id = "mayor_panda",
		Name = "Mayor Panda",
		Title = "Village Mayor",
		PetId = "bamboo_panda",
		Species = "Panda",
		Accent = Color3.fromRGB(100, 184, 112),
		Keywords = { "free gate", "press E", "Food Bowl", "Cloud Cash", "Berry Farm", "Food Machine", "Home Level", "Prestige", "portal" },
		Lines = {
			"Welcome to Nimbus Village! Tap Home, then Claim a home: a portal takes you to a free gate. Walk in and press E there!",
			"Your garden pets roam your yard, eat at the Food Bowl and poop Cloud Cash. Only you can scoop it: walk over it!",
			"Level up your Berry Farm: bigger berries make bigger Cloud Cash, and more berries for the Food Machine!",
			"Home Level " .. prestigeLevel .. " and a " .. castleName .. "? Prestige! You get x" .. prestigeMul
				.. " coins forever, " .. prestigeGems .. " Gems and " .. placeWord .. ".",
			"Tap Home in the menu to see your stations. Go home opens a magic portal just for you and your pets!",
		},
	},
	{
		Id = "professor_axolotl",
		Name = "Professor Axolotl",
		Title = "Element Scholar",
		PetId = "nebula_axolotl",
		Species = "Axolotl",
		Accent = Color3.fromRGB(226, 112, 170),
		Keywords = { "Element", "battles", "Power", "Fusion Machine", "Golden", "Rainbow", "hybrid", "Storm Altar", "Secret pets", "Gems", "Prestige" },
		ColorWords = elementColors(),
		Lines = {
			"Blub! Every pet has an Element. " .. joinAnd(wheelA) .. ".",
			joinAnd(wheelB) .. ". " .. rivalLine,
			"In battles a strong element hits x" .. strongMul .. ", a weak one x" .. weakMul .. ". Two of one element: +"
				.. synergyPair .. " Power!",
			fusionWhen .. ", build the Fusion Machine: " .. fusionCopies .. " copies make a Golden pet (x" .. goldenMul
				.. "), " .. fusionCopies .. " Golden a Rainbow one (x" .. rainbowMul .. ")!",
			"It also mixes two pets into a one-of-a-kind hybrid. Secret pets like Stormfang come from the Storm Altar for "
				.. secretPrice .. " Gems!",
		},
	},
}

NpcDialog.List = NpcDialog.Npcs

NpcDialog.ById = {}
for _, npc in ipairs(NpcDialog.Npcs) do
	npc.Scale = npc.Scale or NpcDialog.Settings.Scale
	NpcDialog.ById[npc.Id] = npc
end

function NpcDialog.Get(id)
	if type(id) ~= "string" then
		return nil
	end
	return NpcDialog.ById[id]
end

function NpcDialog.GetLines(id)
	local npc = NpcDialog.Get(id)
	if npc and type(npc.Lines) == "table" then
		return npc.Lines
	end
	return {}
end

return NpcDialog
