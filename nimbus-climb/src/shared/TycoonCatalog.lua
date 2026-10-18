-- TycoonCatalog: every number of the tycoon homes (ARCHITECTURE_V3.md "Phase 2 build contract" and the "Phase 4 build
-- contract" sections 3.1-3.5, 3.7, 3.12 and 5.4): the stations and their buy pads, prices (and the star price rule),
-- effects per level, house tiers, prestige, the rainbow coins of the Pet Garden, the Food Machine, the Training Place,
-- the leftover foods, fusion costs, the pet XP curve and where everything stands on the 72 x 72 stud yard.
-- Pure data + pure functions: no Instances, no services, no yields; safe on the server and the client.
-- Plain Lua 5.1-compatible syntax only.
--
-- PHASE 4 IN ONE PARAGRAPH: pets make the money. Pets in the Pet Garden (the free first pad) eat one meal every
-- Coins.MealSeconds and pop out a rainbow coin worth Food(home) x PetPower(pet) x 1.25 ^ stars (a Lucky coin x5).
-- The four old Cloud Presses are FOOD PLANTS under the same ids (Press1 Berry Bush, Press2 Carrot Patch, Press3 Cloud
-- Melons, Press4 Starfruit Tree: Effects.Food), the Collector is the COIN MAGNET (scoop radius + bigger piles), the
-- Kitchen is the FOOD MACHINE (one feed fills FeedShare of the pet's XP bar for FeedPrice Cash), the Gym is the
-- TRAINING PLACE (Slots = pets training at once; TrainCost / TrainSeconds), the Vault makes piles bigger and pays
-- offline coins. The 18 ids, slots and tier caps are unchanged, so Home Level, house tiers and prestige are too.
--
-- BALANCE: the numbers below come from the progression simulation tools/sim_tycoon.py (an active player who buys the
-- best-value pad, scoops every ~20 s, spends a quarter of the coins on food for the pet closest to evolving, gets pets
-- from typical roulette luck; pets level up to 100). Change a number here -> change the same number in the constants
-- block of tools/sim_tycoon.py and re-run it (`python3 tools/sim_tycoon.py`, `--check`); the smoke check
-- (tools/smoke_p4_economy.lua, scenario p2_economy) fails while the two disagree. Targets proven by the sim (Monte
-- Carlo 120 players, 3 prestige runs each): the first paid pad within a minute, a purchase every 1-3 minutes early on,
-- the Villa after 25-40 min, the first Prestige after 2-3 h, later runs faster but never shorter than 12 min, prestige
-- Gems <= 135 an hour, never more than 6 minutes with nothing to buy, the first EVOLVE after 40-100 min.
--
-- API (the contract):
--   TycoonCatalog.Get(id) -> StationDef | nil            READ-ONLY (shared table). "Prestige" returns the prestige
--                                                        pseudo-station (Kind "Prestige", see below)
--   TycoonCatalog.PriceFor(id, level) -> cash | nil      BASE price of building / upgrading TO `level`
--   TycoonCatalog.PriceAt(id, level, home) -> cash | nil the price the home pays: floor(PriceFor x StarPriceMultiplier)
--   TycoonCatalog.StarPriceMultiplier(home) -> n         (1 + Prestige.PriceStep) ^ stars (x1.5, x2.25, x3.375 ...);
--                                                        1 for a home with LegacyPrices = true (a Phase 3 veteran, until
--                                                        the next Prestige). A plain number counts as a star count.
--   TycoonCatalog.AvailablePads(home) -> { pad... }      the pads to show on the yard, in station order:
--       pad = { StationId, NextLevel, Price (= PriceAt, the star price), BasePrice (= PriceFor), Locked = reason | nil,
--               Level (current), MaxLevel, Name, Title, Kind, Icon, LevelText ("Build" | "Lv 2 -> 3"), Prestige }
--       * a station shows a pad once its STATION prerequisites are built (the tree; a fresh home shows ONE pad: the
--         free Pet Garden); maxed stations show no pad
--       * Locked (shown on the sign) when the next level needs more: "Reach Home Level 10", "Needs the Villa",
--         "Unlocks at Prestige 1", "Coming soon". Price is always the real (star) price.
--       * once the Sky Castle is built the list also holds the PRESTIGE pad: { StationId = "Prestige",
--         Kind = "Prestige", Prestige = true, Price = 0, NextLevel = stars + 1, Locked = "Reach Home Level 40" | nil }.
--         TycoonService routes it to its Prestige() (never to a station purchase).
--   TycoonCatalog.CheckPurchase(home, stationId) -> ok, price, reason   (the pad's star price)
--   TycoonCatalog.HomeLevelOf(home) -> n                 sum of every station level (each purchase or upgrade = +1)
--   TycoonCatalog.StationsAfterPrestige(stations)        decor (KeepOnPrestige) kept, the Garden set to its ResetLevel
--                                                        (1: the coins never stop), everything else reset
--   Rainbow coins (section 3.2; constants in TycoonCatalog.Coins):
--   TycoonCatalog.FoodOf(home) -> food                   0 without a Garden; else Coins.GrassFood + the Effects.Food of
--                                                        every built plant (Press1-4)
--   TycoonCatalog.PetPower(entry, level, tier, stage) -> power   RarityScale x (1 + 0.1 x (level - 1)) x tier
--       (Normal 1 / Golden 1.5 / Rainbow 2.5) x RoleMult (Economy 1.6 / Combat 1) x EvolutionBoost[stage] (1 / 1.25 /
--       1.5; the STORED stage, cleaned by PetCatalog.EvolutionStage: a Common never counts stage 2). entry = a PetDef
--       (or a PetKeys.DefOf def: hybrids carry their role and rarity), { Def, Level, Tier, Stage } (Evo also read), a
--       pet key string ("cat", "cat@Golden"; hybrids "hyb:..." need their def -> 0), a number (already a power) or
--       { Power = n }. level / tier / stage arguments win over the entry's. Junk -> 0.
--   TycoonCatalog.GardenSlots(home) -> n                 the open garden places: 0 without a Garden, else
--       min(GardenSlotsMax 12, max(GardenSlotsBase 3 + GardenSlotsPerStar x stars, home.LegacySlots or 0))
--   TycoonCatalog.IncomePerSecond(home, entries, prestige) -> cash/s, { Food, Pets, Lucky, Multiplier }
--       = Food / MealSeconds x Pets x Lucky x Multiplier, where Pets = the sum of PetPower over the OPEN places only
--       (entries[1 .. GardenSlots(home)]: an array or a slot -> entry map; keys above the open count rest and do not
--       eat), Lucky = the Lucky expected value 1 + (LuckyMult - 1) x LuckyChance(home), Multiplier = 1.25 ^ stars
--       (prestige or home.Prestige). No Collector condition.
--   TycoonCatalog.LuckyChance(home) -> 0..1             the chance that a coin is Lucky (Garden Effects.Lucky)
--   TycoonCatalog.ScoopRadius(home) -> studs             Coin Magnet Radius (Coins.BaseRadius without a Magnet)
--   TycoonCatalog.PileSeconds(home) -> seconds           Magnet PileSeconds (Coins.BasePileSeconds without) + Vault
--                                                        PileSeconds: a place's pile holds this many seconds of coins
--   TycoonCatalog.CoinPoint(slot) -> Vector3 | nil       where garden place `slot`'s pile lies, in the Garden's station
--                                                        frame (Garden.Slot.CFrame); Garden.Slot.WelcomePile is the
--                                                        plot-local point of the Welcome-back pile
--   TycoonCatalog.OfflineEarnings(home, seconds, incomePerSecond) -> cash, { Seconds, Percent, MaxHours }
--       the Vault pays OfflinePercent of the income for up to OfflineHours (0 without a Vault, 0 for absences
--       shorter than OfflineMinSeconds). Phase 4 pays it INTO the Welcome-back pile (Home.CollectorCash).
--   Food Machine (section 3.4) and Training Place (section 3.7):
--   TycoonCatalog.FeedXp(level, machineLevel) -> xp      max(1, round(XpToNext(level) x FeedShare[machineLevel]));
--                                                        0 at the top level or without a machine (machineLevel < 1)
--   TycoonCatalog.FeedPrice(def, level) -> cash | nil    round(XpToNext(level) x RarityScale(def) x FeedBase): the
--                                                        same price at every machine level; nil at the top level or
--                                                        for an unknown pet. def = a def, a rarity id, a pet id / key
--   TycoonCatalog.TrainCost(def, rank) -> cash | nil     round(Training.CostBase x rank ^ 2 x RarityScale(def)), rank
--                                                        1..Training.MaxRank (never scaled by stars)
--   TycoonCatalog.TrainSeconds(rank) -> seconds | nil    rank x Training.MinutesPerRank x 60 ("Rank 3 takes 3 minutes")
--   TycoonCatalog.TrainingSlots(home) -> n               pets training at once (the Training Place level; 0 unbuilt)
--   TycoonCatalog.XpToNext(level) -> xp                  pet XP from `level` to level + 1; math.huge at PetXp.MaxLevel
--   TycoonCatalog.Validate() -> ok, { problem... }       data self-check (prices, caps, tree, no dead end, per-kind
--                                                        effects, the garden layout and coin points, slots inside the
--                                                        yard without overlaps, every pad reachable)
-- Data (the contract): Stations (array, display order) / ById / Order, HouseTiers, Prestige, Coins, FeedShare,
--   FeedBase, Training, Foods, Fusion, PetXp, Layout, Kinds. Stations, HouseTiers and Foods are ordered arrays that
--   also answer an id (Stations.Press1, HouseTiers.Villa, Foods.Snack); Fusion.Upgrade[rarity].Golden / .Rainbow,
--   Fusion.Mix[rarity] (also Fusion[rarity]).
--   Coins    = { MealSeconds 8, GrassFood 12, LuckyMult 5, BaseRadius 6, BasePileSeconds 240,
--                HeapStages {1, 3, 6, 12, 24} (CoinPiles heap stage 1..5 from that many coins) }
--   Prestige = { HomeLevel 40, House SkyCastle, IncomeMultiplier 1.25, GemReward 100 / Step 10 / Min 25,
--                FusionUnlock 1, TeamSlotUnlock 1, GardenSlotsBase 3, GardenSlotsPerStar 1, GardenSlotsMax 12,
--                PriceStep 0.5 }
--   FeedShare = { .25, .30, .35, .42, .50 } (by Food Machine level; = the Kitchen's Effects.FeedShare), FeedBase 2.0
--   Training  = { MaxRank 10, CostBase 300, MinutesPerRank 1 }
--   StationDef = { Id, Name, Kind, Icon, Blurb, MaxLevel,
--       Requires = { <stationId> = level, HomeLevel = n, House = tierId, Prestige = n },  -- station keys = the tree
--       LevelRequires = { [level] = { HomeLevel = n } },   -- per-level extra gate (the House: 10 / 20 / 30)
--       TierCaps = { Cottage = n, Villa = n, Manor = n, SkyCastle = n },  -- max level allowed by the house tier
--       Price = { [level] = cash }, Effects = { [level] = {...} },
--       Slot = { CFrame, Footprint, Pad, Walkable?, Perimeter?, Spots?, CoinPoints?, WelcomePile? },  -- see Layout
--       KeepOnPrestige = true | nil, ResetLevel = n | nil (the Garden: 1), ComingSoon = true | nil }
--   NOTE: `Requires.House` is the house TIER (id "Villa" or tier index 2), never the House station level.
-- Effects by Kind (TycoonCatalog.Kinds):
--   Plant       { Food }                (Press1-4)       Magnet   { Radius, PileSeconds }   (Collector)
--   Garden      { Lucky }               (Garden)         FoodMachine { FeedShare }          (Kitchen)
--   Training    { Slots }               (Gym)            Vault    { PileSeconds, OfflinePercent, OfflineHours }
--   House       { Tier, TierIndex, Name }                Fusion   { TokenDiscount }
--   Arena       { Battles = true }                       Decor    { Pieces, Style }  (build hints for HomeBuilder)
-- Slots (plot-local, studs): origin = centre of the yard ON the ground (SpotInfo.PlotCFrame), -Z = the gate /
--   street side (PlotCFrame.LookVector), +Z = the back fence, X across. A station model goes at
--   PlotCFrame * Slot.CFrame; its LookVector is the station's FRONT (the side its pad is on). Footprint =
--   Vector3(width along the front, height, depth) in the station's own axes. Slot.Pad = the buy pad (centre on the
--   ground, Layout.PadSize, LookVector toward the station). Walkable = true: a decor zone with small pieces the
--   player walks through (lamp posts beside the path); Perimeter = follows the fence line (DecorFence); Spots =
--   local positions (in the station frame) of the Garden / Training pet places.
--   The Garden (section 3.3, station frame, -Z = its front toward the pad): Spots = 12 places on a 3 x 4 grid
--   (X -7.5 / -2.5 / 2.5 / 7.5; Z -7 front row = places 1-4, 0 middle = 5-8, +7 back = 9-12); Walkable = the sand
--   walks { Name, Center, Size } (3 studs wide at Z -3.5 and +3.5, joined at both ends, and the 3-stud entrance gap
--   at X 0 between the front cushions); CoinPoints[slot] = the pile of each place (front row on the front walk at
--   Z -2.6, middle row at Z -4.4, back row on the back walk at Z +3.5); WelcomePile = plot-local (13.5, 0, 2.5)
--   beside the entrance, off the pad. Layout.Paths = stone paths that keep every pad reachable from the gate.
-- Extras (nothing depends on them): HouseTierOf, HouseTier, MaxLevelAt, StationLevel, PrestigeMultiplier,
--   PrestigeGems, CanPrestige, EffectsOf, LuckyEV, CoinValue, HeapStage, FoodById, FusionCost, XpForLevel,
--   PadLevelText, FormatCash, ReachablePads, FootprintRect, PadRect, LocalRect, TierMultiplier, Icons, FoodsById,
--   PrestigePad, MaxPetLevel, StartCash, OfflineMinSeconds, PlotSize, Version.
-- Phase 3 compat: all deleted in wave 4 (the Kitchen Effects' Queue, the Gym Effects' XpPerMinute, PetIncome,
--   GardenIncome, PressIncome, CollectorCap, KitchenSpeed, CookSecondsFor, FoodsFor, GymSlots, GymXpPerMinute, the
--   Kitchen Effects' Recipes and the IncomePerSecond parts Press / Garden.
--
-- Notes for the services: a Price of 0 is FREE (the Pet Garden: the first purchase right after claiming; Cash starts
-- at 0), so skip SpendCash or call it with 0. Prestige keeps every station whose KeepOnPrestige is true (the decor:
-- "decor choices kept") and the Garden at its ResetLevel, resets the rest (StationsAfterPrestige does it). Food,
-- training and roulettes never scale with stars; station prices do (PriceAt).

local Shared = script.Parent
local Config = require(Shared.Config)

local TycoonCatalog = {}

local floor, max, min, huge = math.floor, math.max, math.min, math.huge

local PLOT = (type(Config.Lobby) == "table" and tonumber(Config.Lobby.PlotSize)) or 72
local HALF = PLOT / 2

TycoonCatalog.Version = 4 -- Phase 4: pets make the money
TycoonCatalog.PlotSize = PLOT
TycoonCatalog.StartCash = 0 -- Cash of a brand-new profile; the Pet Garden is free
TycoonCatalog.OfflineMinSeconds = 120 -- shorter absences pay nothing (no rejoin farming)
TycoonCatalog.Kinds = { "Plant", "Magnet", "Garden", "FoodMachine", "Training", "Vault", "House", "Fusion", "Arena", "Decor" }
TycoonCatalog.TierMultiplier = { Normal = 1, Golden = 1.5, Rainbow = 2.5 } -- PetKeys.StatMultiplier

-- Icons (UTF-8 emoji, drawn as text on pad signs and in the Home window).
local ICON = {
	Cloud = "\226\152\129",
	Money = "\240\159\146\176",
	Seedling = "\240\159\140\177",
	Cook = "\240\159\141\179",
	Stew = "\240\159\141\178",
	Muscle = "\240\159\146\170",
	Bank = "\240\159\143\166",
	House = "\240\159\143\160",
	Castle = "\240\159\143\176",
	Crystal = "\240\159\148\174",
	Swords = "\226\154\148",
	Lantern = "\240\159\143\174",
	Garden = "\240\159\143\161",
	Tulip = "\240\159\140\183",
	Fountain = "\226\155\178",
	Flag = "\240\159\154\169",
	Trophy = "\240\159\143\134",
	Star = "\226\173\144",
	Berry = "\240\159\141\147",
	Carrot = "\240\159\165\149",
	Melon = "\240\159\141\136",
	Tree = "\240\159\140\179",
	Magnet = "\240\159\167\178",
}
TycoonCatalog.Icons = ICON

----------------------------------------------------------------------
-- House tiers (the House station's level IS the tier index; a home without a House counts as the Cottage tier)
----------------------------------------------------------------------
TycoonCatalog.HouseTiers = {
	{ Id = "Cottage", Name = "Cottage", Index = 1, HomeLevel = 0, Icon = ICON.House },
	{ Id = "Villa", Name = "Villa", Index = 2, HomeLevel = 10, Icon = ICON.House },
	{ Id = "Manor", Name = "Manor", Index = 3, HomeLevel = 20, Icon = ICON.House },
	{ Id = "SkyCastle", Name = "Sky Castle", Index = 4, HomeLevel = 30, Icon = ICON.Castle },
}
local TIERS = TycoonCatalog.HouseTiers
local TIER_INDEX = {}
local TIER_BY_ID = {}
for i, t in ipairs(TIERS) do
	TIER_INDEX[t.Id] = i
	TIER_BY_ID[t.Id] = t
end
setmetatable(TIERS, { __index = TIER_BY_ID }) -- HouseTiers.Villa works too

----------------------------------------------------------------------
-- Prestige: at Home Level 40 with the Sky Castle. Resets Cash, the coins on the lawn and every station that is not
-- KeepOnPrestige (the Garden stays at its ResetLevel 1). Gains +1 star: coins x1.25 per star (compounding), +1 garden
-- place (3 + stars, at most 12), a Gems reward, the Fusion Machine and the 4th battle-team slot at 1 star. After every
-- Prestige station prices go up by half again: x(1 + PriceStep) ^ stars (LegacyPrices homes exempt for one run).
----------------------------------------------------------------------
TycoonCatalog.Prestige = {
	Id = "Prestige",
	HomeLevel = 40,
	House = "SkyCastle",
	IncomeMultiplier = 1.25, -- per star: PrestigeMultiplier(stars) = 1.25 ^ stars (coins)
	GemReward = 100, -- the first prestige; PrestigeGems(stars) lowers it by GemRewardStep per later star
	GemRewardStep = 10,
	GemRewardMin = 25,
	FusionUnlock = 1, -- the Fusion Machine pad unlocks at this many stars
	TeamSlotUnlock = 1, -- the 4th battle-team slot (Phase 3)
	GardenSlotsBase = 3, -- garden places without a star ("at the start you can put up to 3 pets")
	GardenSlotsPerStar = 1, -- +1 place per star ("prestige 1 can put 4 and so on")
	GardenSlotsMax = 12, -- the places drawn in the garden (Garden.Slot.Spots)
	PriceStep = 0.5, -- station prices x(1 + PriceStep) ^ stars: x1.5, x2.25, x3.38 ...
	Icon = ICON.Star,
}

----------------------------------------------------------------------
-- Rainbow coins (section 3.2). Every open garden place with a pet eats one meal every MealSeconds; a meal pops out
-- one coin worth Food(home) x PetPower(pet) x 1.25 ^ stars (a Lucky coin x LuckyMult). A place's pile holds
-- PileSeconds(home) of that pet's coins; the owner scoops piles within ScoopRadius(home).
----------------------------------------------------------------------
TycoonCatalog.Coins = {
	MealSeconds = 8, -- one meal (= one coin) per open place every 8 s
	GrassFood = 12, -- the Food of a built Garden before any plant
	LuckyMult = 5, -- a Lucky coin is worth 5 coins
	BaseRadius = 6, -- scoop radius (studs) without a Coin Magnet
	BasePileSeconds = 240, -- a pile holds 4 minutes of coins without a Coin Magnet
	HeapStages = { 1, 3, 6, 12, 24 }, -- the CoinPiles heap stage 1..5 starts at this many coins (0 coins = stage 0)
}

----------------------------------------------------------------------
-- Leftover pet food (Phase 2 / 3 Kitchen dishes). Phase 4 cooks nothing: Profile.Food leftovers are fed first and for
-- free by the Food Machine (Xp 25 / 150 / 800). Price / CookSeconds / KitchenLevel are kept as data only.
----------------------------------------------------------------------
TycoonCatalog.Foods = {
	{ Id = "Snack", Name = "Snack", Price = 50, Xp = 25, CookSeconds = 6, KitchenLevel = 1, Blurb = "A crunchy cloud cookie." },
	{ Id = "Meal", Name = "Meal", Price = 600, Xp = 150, CookSeconds = 20, KitchenLevel = 2, Blurb = "A warm bowl of sky stew." },
	{ Id = "Feast", Name = "Feast", Price = 6000, Xp = 800, CookSeconds = 45, KitchenLevel = 4, Blurb = "A whole starfruit pie." },
}
local FOOD_BY_ID = {}
for _, f in ipairs(TycoonCatalog.Foods) do
	FOOD_BY_ID[f.Id] = f
end
TycoonCatalog.FoodsById = FOOD_BY_ID
-- Foods is an ordered array; Foods.Snack also works (read-only lookup, pairs / ipairs still see each food once)
setmetatable(TycoonCatalog.Foods, { __index = FOOD_BY_ID })

----------------------------------------------------------------------
-- Pet XP curve: XpToNext(level) = round(Base * level ^ Exponent / Round) * Round, up to MaxLevel.
-- Pet stats grow +10% per level (PetCatalog.GetStats), so a level-50 pet earns 5.9x its level-1 coins and a level-100
-- pet 10.9x. Phase 4: every pet levels up to 100 (the player's rule); the evolutions stay at 20 and 50; each level
-- takes more XP than the one before (20 XP for L1 -> 2, 10,125 for L49 -> 50, 31,190 for L99 -> 100).
----------------------------------------------------------------------
TycoonCatalog.PetXp = { MaxLevel = 100, Base = 20, Exponent = 1.6, Round = 5 }
TycoonCatalog.MaxPetLevel = TycoonCatalog.PetXp.MaxLevel -- DataService.AddPetXp caps levels here

----------------------------------------------------------------------
-- The Food Machine (section 3.4): one feed fills FeedShare[machine level] of the pet's current XP bar (the Kitchen's
-- Effects.FeedShare, copied into TycoonCatalog.FeedShare below) and costs XpToNext(level) x RarityScale x FeedBase
-- Cash, the same at every machine level (the upgrade gives more XP for the same money).
----------------------------------------------------------------------
TycoonCatalog.FeedBase = 2.0

----------------------------------------------------------------------
-- The Training Place (section 3.7): rank r of a skill costs CostBase x r ^ 2 x RarityScale Cash and takes
-- r x MinutesPerRank minutes; ranks 1..MaxRank. Prices never scale with stars. (The skill effects live in
-- BattleCatalog.Training.)
----------------------------------------------------------------------
TycoonCatalog.Training = { MaxRank = 10, CostBase = 300, MinutesPerRank = 1 }

----------------------------------------------------------------------
-- Fusion Machine costs (section 11), by rarity (a Mix pays for the HIGHER rarity of its two inputs).
--   Upgrade[rarity].Golden  = 3 Normal copies -> 1 Golden;  Upgrade[rarity].Rainbow = 3 Golden -> 1 Rainbow
--   Mix[rarity]             = two different pets -> a hybrid; Mythic / Secret inputs cost Gems
----------------------------------------------------------------------
TycoonCatalog.Fusion = {
	Copies = 3,
	Upgrade = {
		Common = { Golden = { Tokens = 150 }, Rainbow = { Tokens = 450 } },
		Uncommon = { Golden = { Tokens = 300 }, Rainbow = { Tokens = 900 } },
		Rare = { Golden = { Tokens = 750 }, Rainbow = { Tokens = 2250 } },
		Epic = { Golden = { Tokens = 1800 }, Rainbow = { Tokens = 5400 } },
		Legendary = { Golden = { Tokens = 4500 }, Rainbow = { Tokens = 13500 } },
		Mythic = { Golden = { Tokens = 10000 }, Rainbow = { Tokens = 30000 } },
		Secret = { Golden = { Tokens = 25000 }, Rainbow = { Tokens = 75000 } },
	},
	Mix = {
		Common = { Tokens = 200 },
		Uncommon = { Tokens = 400 },
		Rare = { Tokens = 1000 },
		Epic = { Tokens = 2500 },
		Legendary = { Tokens = 6000 },
		Mythic = { Gems = 60 },
		Secret = { Gems = 150 },
	},
}
-- Fusion.ByRarity[rarity] = { Golden = cost, Rainbow = cost, Mix = cost } (also reachable as Fusion[rarity])
do
	local byRarity = {}
	for rarity, row in pairs(TycoonCatalog.Fusion.Upgrade) do
		byRarity[rarity] = { Golden = row.Golden, Rainbow = row.Rainbow, Mix = TycoonCatalog.Fusion.Mix[rarity] }
	end
	TycoonCatalog.Fusion.ByRarity = byRarity
	setmetatable(TycoonCatalog.Fusion, { __index = byRarity })
end

----------------------------------------------------------------------
-- Layout of the yard (plot-local studs, see the header). The yard is PlotSize x PlotSize inside the lobby fence;
-- nothing is placed outside |x|, |z| <= HALF - 1.5 except along-the-fence decor. (Phase 4: the press conveyor is
-- gone; the PressLane path stays beside the food plants.)
----------------------------------------------------------------------
local function V3(x, y, z)
	return Vector3.new(x, y, z)
end

-- yaw: 0 = the front faces the gate (-Z), 180 = faces the back fence, 90 = faces -X, -90 = faces +X
local function at(x, z, yaw)
	return CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

-- a pad on the ground at (x, z) looking toward (tx, tz) (the station it buys)
local function padAt(x, z, tx, tz)
	local from = V3(x, 0, z)
	local to = V3(tx, 0, tz)
	if (to - from).Magnitude < 1e-3 then
		return CFrame.new(from)
	end
	return CFrame.lookAt(from, to)
end

TycoonCatalog.Layout = {
	PlotSize = PLOT,
	Half = HALF,
	Margin = 1.5, -- stations keep this far from the fence line
	PadSize = V3(4, 0.6, 4), -- buy pads (flat, walkable)
	Gate = V3(0, 0, -HALF), -- centre of the gate opening (the lobby builds the gate; its pillars stand at x = +-7.2)
	GateWidth = 12, -- clear opening between the pillars
	Spawn = V3(0, 0, -12), -- the lobby's home spawn point (kept clear)
	-- stone paths (centre line + width); every pad touches one
	Paths = {
		{ Name = "Main", Start = V3(0, 0, -HALF), Finish = V3(0, 0, -7), Width = 6 },
		{ Name = "FountainWest", Start = V3(-7, 0, -7), Finish = V3(-7, 0, 5), Width = 4 },
		{ Name = "FountainEast", Start = V3(7, 0, -7), Finish = V3(7, 0, 5), Width = 4 },
		{ Name = "FountainSouth", Start = V3(-7, 0, -7), Finish = V3(7, 0, -7), Width = 4 },
		{ Name = "FountainNorth", Start = V3(-7, 0, 5), Finish = V3(7, 0, 5), Width = 4 },
		{ Name = "HouseWalk", Start = V3(0, 0, 5), Finish = V3(0, 0, 15), Width = 6 },
		{ Name = "FrontCross", Start = V3(-15, 0, -19), Finish = V3(26, 0, -19), Width = 4 },
		{ Name = "GateWalk", Start = V3(-14, 0, -32.5), Finish = V3(14, 0, -32.5), Width = 3 },
		{ Name = "PressLane", Start = V3(-15, 0, -24), Finish = V3(-15, 0, 23), Width = 4 },
		{ Name = "BackCross", Start = V3(-15, 0, 12), Finish = V3(29, 0, 12), Width = 4 },
		{ Name = "GardenWalk", Start = V3(7, 0, -1), Finish = V3(12, 0, -1), Width = 4 },
	},
	-- the strip in front of the Garden (toward its pad) where the Welcome-back pile may lie (Validate)
	GardenEntranceDepth = 6,
}

-- The Garden's 12 places (section 3.3), in its station frame: X along the front, Z -7 = the front row (places 1-4,
-- next to the entrance), 0 = the middle row (5-8), +7 = the back row (9-12)
local GARDEN_X = { -7.5, -2.5, 2.5, 7.5 }
local GARDEN_ROWS = { -7, 0, 7 }
local GARDEN_COIN_Z = { -4.4, -2.6, 3.5 } -- the pile of each row, 2.6 studs from its own cushion: front + middle rows on the front walk, back row on the back walk
local GARDEN_SPOTS = {}
local GARDEN_COINS = {}
for row, z in ipairs(GARDEN_ROWS) do
	for _, x in ipairs(GARDEN_X) do
		GARDEN_SPOTS[#GARDEN_SPOTS + 1] = V3(x, 0, z)
		GARDEN_COINS[#GARDEN_COINS + 1] = V3(x, 0, GARDEN_COIN_Z[row])
	end
end
-- the sand walks (station frame, Center + Size on the ground): two 3-stud walks joined at both ends, and the 3-stud
-- entrance gap between the front-row cushions at X = 0 (the Garden's pad faces it)
local GARDEN_WALKS = {
	{ Name = "FrontWalk", Center = V3(0, 0, -3.5), Size = V3(20, 0, 3) },
	{ Name = "BackWalk", Center = V3(0, 0, 3.5), Size = V3(20, 0, 3) },
	{ Name = "WestJoin", Center = V3(-10, 0, 0), Size = V3(2, 0, 10) },
	{ Name = "EastJoin", Center = V3(10, 0, 0), Size = V3(2, 0, 10) },
	{ Name = "Entrance", Center = V3(0, 0, -7.5), Size = V3(3, 0, 5) },
}

----------------------------------------------------------------------
-- Stations. Price[level] = BASE Cash to build / upgrade TO that level (PriceAt adds the star price rule).
-- TierCaps = the max level each house tier allows.
----------------------------------------------------------------------
local function caps(c, v, m, s)
	return { Cottage = c, Villa = v, Manor = m, SkyCastle = s }
end

local function effectsOf(key, values)
	local out = {}
	for i, v in ipairs(values) do
		out[i] = { [key] = v }
	end
	return out
end

local function magnetEffects(radius, pile)
	local out = {}
	for i = 1, #radius do
		out[i] = { Radius = radius[i], PileSeconds = pile[i] }
	end
	return out
end

local STATIONS = {
	----------------------------------------------------------------- the food plants (the old Cloud Presses)
	{
		Id = "Press1", Name = "Berry Bush", Kind = "Plant", Icon = ICON.Berry,
		Blurb = "Sweet berries for your garden pets: bigger coins.",
		MaxLevel = 10, TierCaps = caps(6, 8, 9, 10),
		Requires = { Garden = 1 },
		Price = { 15, 55, 130, 360, 1200, 3500, 9000, 20000, 100000, 270000 },
		Effects = effectsOf("Food", { 7, 9, 12, 16, 21, 27, 35, 45, 59, 76 }),
		Slot = { CFrame = at(-26.5, -14, -90), Footprint = V3(7, 10, 7), Pad = padAt(-19, -14, -26.5, -14) },
	},
	{
		Id = "Press2", Name = "Carrot Patch", Kind = "Plant", Icon = ICON.Carrot,
		Blurb = "Crunchy carrots make every coin bigger.",
		MaxLevel = 10, TierCaps = caps(6, 8, 9, 10),
		Requires = { Press1 = 2 },
		Price = { 420, 1100, 2500, 6000, 15000, 22000, 38000, 120000, 260000, 680000 },
		Effects = effectsOf("Food", { 19, 24, 32, 42, 53, 69, 91, 118, 153, 199 }),
		Slot = { CFrame = at(-26.5, -4.5, -90), Footprint = V3(7, 11, 7), Pad = padAt(-19, -4.5, -26.5, -4.5) },
	},
	{
		Id = "Press3", Name = "Cloud Melons", Kind = "Plant", Icon = ICON.Melon,
		Blurb = "Juicy cloud melons: much bigger coins.",
		MaxLevel = 10, TierCaps = caps(0, 6, 8, 10),
		Requires = { Press2 = 3, House = "Villa" },
		Price = { 18000, 25000, 36000, 88000, 130000, 180000, 290000, 410000, 1100000, 1800000 },
		Effects = effectsOf("Food", { 49, 63, 82, 107, 140, 180, 235, 302, 396, 518 }),
		Slot = { CFrame = at(-26.5, 5, -90), Footprint = V3(7, 12, 7), Pad = padAt(-19, 5, -26.5, 5) },
	},
	{
		Id = "Press4", Name = "Starfruit Tree", Kind = "Plant", Icon = ICON.Tree,
		Blurb = "The tastiest food in the sky: huge coins.",
		MaxLevel = 10, TierCaps = caps(0, 0, 8, 10),
		Requires = { Press3 = 3, House = "Manor" },
		Price = { 160000, 300000, 370000, 490000, 630000, 820000, 1100000, 1400000, 2200000, 3200000 },
		Effects = effectsOf("Food", { 127, 164, 215, 278, 360, 468, 612, 792, 1030, 1339 }),
		Slot = { CFrame = at(-26.5, 14.5, -90), Footprint = V3(7, 13, 7), Pad = padAt(-19, 14.5, -26.5, 14.5) },
	},
	{
		Id = "Collector", Name = "Coin Magnet", Kind = "Magnet", Icon = ICON.Magnet,
		Blurb = "Coins fly to you from farther away, and piles hold more.",
		MaxLevel = 5, TierCaps = caps(2, 3, 4, 5),
		Requires = { Press1 = 1 },
		Price = { 90, 6000, 45000, 410000, 1400000 },
		Effects = magnetEffects({ 9, 12, 16, 20, 26 }, { 300, 360, 420, 480, 600 }),
		Slot = { CFrame = at(-27.5, -26.5, -90), Footprint = V3(9, 8, 13), Pad = padAt(-17, -26.5, -27.5, -26.5) },
	},
	----------------------------------------------------------------- pets at home
	{
		Id = "Garden", Name = "Pet Garden", Kind = "Garden", Icon = ICON.Seedling,
		Blurb = "Your pets eat here and pop out rainbow coins.",
		MaxLevel = 8, TierCaps = caps(2, 4, 6, 8),
		Requires = {},
		ResetLevel = 1, -- Prestige keeps the Garden built (at this level): the coins never stop
		Price = { 0, 12000, 30000, 110000, 290000, 600000, 1200000, 2400000 },
		Effects = effectsOf("Lucky", { 0, 0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.15 }),
		Slot = {
			CFrame = at(24, -1, 90), Footprint = V3(22, 4, 20), Pad = padAt(10, -1, 24, -1),
			Spots = GARDEN_SPOTS, -- 12 pet places (station frame: X along the front, -Z toward the front)
			CoinPoints = GARDEN_COINS, -- the pile of each place (CoinPoint(slot))
			Walkable = GARDEN_WALKS, -- the sand walks
			WelcomePile = V3(13.5, 0, 2.5), -- PLOT-local: the Welcome-back pile beside the entrance, off the pad
		},
	},
	{
		Id = "Kitchen", Name = "Food Machine", Kind = "FoodMachine", Icon = ICON.Stew,
		Blurb = "Feed your pets for XP. Upgrades give bigger meals.",
		MaxLevel = 5, TierCaps = caps(1, 2, 4, 5),
		Requires = { Press1 = 1 },
		Price = { 240, 35000, 320000, 680000, 1900000 },
		Effects = effectsOf("FeedShare", { 0.25, 0.30, 0.35, 0.42, 0.50 }),
		Slot = { CFrame = at(25, 24, 0), Footprint = V3(16, 10, 10), Pad = padAt(19.5, 14.5, 25, 24) },
	},
	{
		Id = "Gym", Name = "Training Place", Kind = "Training", Icon = ICON.Muscle,
		Blurb = "Train Attack Speed, Physique, Ability or Defense.",
		MaxLevel = 5, TierCaps = caps(1, 2, 4, 5),
		Requires = { Kitchen = 1 },
		Price = { 3000, 110000, 420000, 920000, 2200000 },
		Effects = effectsOf("Slots", { 1, 2, 3, 4, 5 }),
		Slot = {
			CFrame = at(-24, 29, 0), Footprint = V3(18, 10, 9), Pad = padAt(-19, 22.5, -24, 29),
			Spots = { V3(-6, 0, 0), V3(-3, 0, 0), V3(0, 0, 0), V3(3, 0, 0), V3(6, 0, 0) },
		},
	},
	{
		Id = "Vault", Name = "Vault", Kind = "Vault", Icon = ICON.Bank,
		Blurb = "Bigger coin piles, and coins while you are away.",
		MaxLevel = 5, TierCaps = caps(1, 2, 4, 5),
		Requires = { Press2 = 2 },
		Price = { 9000, 85000, 370000, 820000, 2000000 },
		Effects = {
			{ PileSeconds = 300, OfflinePercent = 0.1, OfflineHours = 1 },
			{ PileSeconds = 600, OfflinePercent = 0.15, OfflineHours = 2 },
			{ PileSeconds = 900, OfflinePercent = 0.2, OfflineHours = 3 },
			{ PileSeconds = 1200, OfflinePercent = 0.25, OfflineHours = 4 },
			{ PileSeconds = 1800, OfflinePercent = 0.3, OfflineHours = 4 },
		},
		Slot = { CFrame = at(-10.5, -27, 180), Footprint = V3(7, 9, 8), Pad = padAt(-10.5, -19, -10.5, -27) },
	},
	{
		Id = "House", Name = "House", Kind = "House", Icon = ICON.House,
		Blurb = "Your home. Each new house raises every station's max level.",
		MaxLevel = 4, TierCaps = caps(4, 4, 4, 4),
		Requires = { Collector = 1 },
		LevelRequires = { [2] = { HomeLevel = 10 }, [3] = { HomeLevel = 20 }, [4] = { HomeLevel = 30 } },
		Price = { 180, 24000, 200000, 880000 },
		Effects = {
			{ Tier = "Cottage", TierIndex = 1, Name = "Cottage" },
			{ Tier = "Villa", TierIndex = 2, Name = "Villa" },
			{ Tier = "Manor", TierIndex = 3, Name = "Manor" },
			{ Tier = "SkyCastle", TierIndex = 4, Name = "Sky Castle" },
		},
		Slot = { CFrame = at(0, 25, 0), Footprint = V3(26, 30, 18), Pad = padAt(0, 12, 0, 25) },
	},
	{
		Id = "FusionMachine", Name = "Fusion Machine", Kind = "Fusion", Icon = ICON.Crystal,
		Blurb = "Fuse 3 copies into Golden or Rainbow, or mix two pets.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3),
		Requires = { Kitchen = 1, Prestige = 1 },
		Price = { 25000, 340000, 1400000 },
		Effects = { { TokenDiscount = 0 }, { TokenDiscount = 0.1 }, { TokenDiscount = 0.2 } },
		Slot = { CFrame = at(11, -25, 180), Footprint = V3(10, 12, 10), Pad = padAt(11, -16, 11, -25) },
	},
	{
		Id = "ArenaGate", Name = "Arena Gate", Kind = "Arena", Icon = ICON.Swords,
		Blurb = "Opens the way to pet battles.",
		MaxLevel = 1, TierCaps = caps(1, 1, 1, 1),
		Requires = { Gym = 1 },
		Price = { 260000 },
		Effects = { { Battles = true } },
		Slot = { CFrame = at(32, 14.5, 90), Footprint = V3(7, 12, 4), Pad = padAt(27, 14.5, 32, 14.5) },
	},
	----------------------------------------------------------------- decor (kept on prestige, +1 Home Level each)
	{
		Id = "DecorLamps", Name = "Lanterns", Kind = "Decor", Icon = ICON.Lantern,
		Blurb = "Warm lanterns along your path.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3), KeepOnPrestige = true,
		Requires = { Collector = 1 },
		Price = { 1800, 27000, 360000 },
		Effects = { { Pieces = 4, Style = "Wood" }, { Pieces = 6, Style = "Brass" }, { Pieces = 8, Style = "Crystal" } },
		Slot = { CFrame = at(0, -21, 0), Footprint = V3(9, 7, 26), Walkable = true, Pad = padAt(-8, -12, -3, -12) },
	},
	{
		Id = "DecorFence", Name = "Garden Fence", Kind = "Decor", Icon = ICON.Garden,
		Blurb = "A prettier fence around your whole yard.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3), KeepOnPrestige = true,
		Requires = { Press2 = 2 },
		Price = { 7000, 48000, 490000 },
		Effects = { { Pieces = 1, Style = "Picket" }, { Pieces = 2, Style = "Hedge" }, { Pieces = 3, Style = "Cloudstone" } },
		Slot = { CFrame = at(0, 0, 0), Footprint = V3(PLOT, 4, PLOT), Perimeter = true, Pad = padAt(8, -10, 3, -10) },
	},
	{
		Id = "DecorFlowers", Name = "Flower Beds", Kind = "Decor", Icon = ICON.Tulip,
		Blurb = "Colourful flower beds along the front fence.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3), KeepOnPrestige = true,
		Requires = { Garden = 1 },
		Price = { 2700, 36000, 410000 },
		Effects = { { Pieces = 3, Style = "Tulips" }, { Pieces = 5, Style = "Roses" }, { Pieces = 7, Style = "Starflowers" } },
		Slot = { CFrame = at(-25, -34.3, 180), Footprint = V3(18, 2, 2.2), Pad = padAt(-12.5, -33.3, -25, -34.3) },
	},
	{
		Id = "DecorFountain", Name = "Fountain", Kind = "Decor", Icon = ICON.Fountain,
		Blurb = "A splashing fountain in the middle of the yard.",
		MaxLevel = 3, TierCaps = caps(0, 1, 2, 3), KeepOnPrestige = true,
		Requires = { Kitchen = 1, House = "Villa" },
		Price = { 45000, 490000, 1500000 },
		Effects = { { Pieces = 1, Style = "Basin" }, { Pieces = 2, Style = "Tiered" }, { Pieces = 3, Style = "Sky" } },
		Slot = { CFrame = at(0, -1, 0), Footprint = V3(9, 8, 9), Pad = padAt(-7, -1, 0, -1) },
	},
	{
		Id = "DecorBanners", Name = "Banners", Kind = "Decor", Icon = ICON.Flag,
		Blurb = "Banners in your colours along the front fence.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3), KeepOnPrestige = true,
		Requires = { Vault = 1 },
		Price = { 12000, 110000, 650000 },
		Effects = { { Pieces = 2, Style = "Cloth" }, { Pieces = 4, Style = "Gold" }, { Pieces = 6, Style = "Royal" } },
		Slot = { CFrame = at(25, -34.3, 180), Footprint = V3(18, 6, 2.2), Pad = padAt(12.5, -33.3, 25, -34.3) },
	},
	{
		Id = "DecorPodium", Name = "Pet Podium", Kind = "Decor", Icon = ICON.Trophy,
		Blurb = "Shows off your favourite pet by the gate.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3), KeepOnPrestige = true,
		Requires = { Garden = 1 },
		Price = { 9000, 95000, 580000 },
		Effects = { { Pieces = 1, Style = "Stone" }, { Pieces = 2, Style = "Gold" }, { Pieces = 3, Style = "Crystal" } },
		-- the lobby's podium (SpotInfo.PodiumCFrame, the pet faces the street) stands at (24, -26): this decor dresses
		-- it up; its front (and pad) face the yard
		Slot = { CFrame = at(24, -26, 180), Footprint = V3(8, 6, 8), Pad = padAt(24, -17.5, 24, -26) },
	},
}

TycoonCatalog.Stations = STATIONS
local BY_ID = {}
local ORDER = {}
for i, def in ipairs(STATIONS) do
	def.Order = i
	def.Requires = def.Requires or {}
	def.LevelRequires = def.LevelRequires or {}
	BY_ID[def.Id] = def
	ORDER[i] = def.Id
end
TycoonCatalog.ById = BY_ID
TycoonCatalog.Order = ORDER
setmetatable(STATIONS, { __index = BY_ID }) -- Stations.Press1 works too (the array part stays the display order)

-- FeedShare by Food Machine level (the Kitchen's Effects, so the two never disagree)
do
	local share = {}
	for i, eff in ipairs(BY_ID.Kitchen.Effects) do
		share[i] = eff.FeedShare
	end
	TycoonCatalog.FeedShare = share
end

-- tier caps also live on the tiers: HouseTiers[i].Caps[stationId] = max level
for i, tier in ipairs(TIERS) do
	tier.Caps = {}
	for _, def in ipairs(STATIONS) do
		tier.Caps[def.Id] = def.TierCaps[tier.Id] or 0
	end
	tier.Order = i
end

-- The prestige pad (not a station: TycoonService handles it with its Prestige()). Get("Prestige") returns this.
local PRESTIGE_PAD = {
	Id = "Prestige", Name = "Prestige", Kind = "Prestige", Icon = ICON.Star, IsPrestige = true,
	Blurb = "Start over with +1 star: x1.25 coins forever, +1 garden place and Gems.",
	MaxLevel = 1, TierCaps = caps(0, 0, 0, 1), Requires = { House = "SkyCastle" },
	LevelRequires = {}, Price = { 0 }, Effects = { {} },
	Slot = { CFrame = at(-8, 18, 0), Footprint = V3(4, 1, 4), Walkable = true, Pad = padAt(-8, 12, -8, 18) },
}
TycoonCatalog.PrestigePad = PRESTIGE_PAD

----------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------
local function finite(v)
	return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function int(v)
	v = tonumber(v)
	if not v or v ~= v or v == huge or v == -huge then
		return nil
	end
	return floor(v)
end

local function stationsOf(home)
	local st = type(home) == "table" and home.Stations
	if type(st) == "table" then
		return st
	end
	return nil
end

-- current level of a station in a home (0 for junk; clamped to 0..MaxLevel)
local function levelOf(home, id)
	local def = BY_ID[id]
	local st = stationsOf(home)
	if not def or not st then
		return 0
	end
	local v = int(st[id])
	if not v or v < 0 then
		return 0
	end
	if v > def.MaxLevel then
		return def.MaxLevel
	end
	return v
end

local MAX_STARS = 1000 -- corrupt data guard: 1.25 ^ 1000 and 1.5 ^ 1000 are still finite numbers

local function sanitizeStars(v)
	v = int(v)
	if not v or v < 0 then
		return 0
	end
	return min(v, MAX_STARS)
end

local function starsOf(home)
	return sanitizeStars(type(home) == "table" and home.Prestige or nil)
end

-- tier index from an id ("Villa"), an index (2) or nil
local function tierIndexOf(value)
	if type(value) == "string" then
		return TIER_INDEX[value]
	end
	local n = int(value)
	if n and n >= 1 and n <= #TIERS then
		return n
	end
	return nil
end

local function commas(n)
	local s = tostring(floor(n))
	local neg = s:sub(1, 1) == "-"
	if neg then
		s = s:sub(2)
	end
	local out = s
	while true do
		local k
		out, k = out:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return (neg and "-" or "") .. out
end

-- lazily resolved PetCatalog (pet ids / keys, roles, evolution stages); TycoonCatalog works without it (the sim and
-- the pure tests load it alone): then the local mirrors below are used
local petCatalog, petCatalogResolved = nil, false
local function getPetCatalog()
	if not petCatalogResolved then
		petCatalogResolved = true
		local module = Shared:FindFirstChild("PetCatalog")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				petCatalog = result
			end
		end
	end
	return petCatalog
end

-- mirrors of PetCatalog's Phase 4 data (used only when PetCatalog cannot be loaded; the smoke test pins them equal)
local MIRROR = {
	LevelBonus = 0.1,
	RoleMult = { Economy = 1.6, Combat = 1 },
	EvolutionBoost = { 1.25, 1.5 },
	EvolveTwice = { Epic = true, Legendary = true, Mythic = true, Secret = true },
}

local function rarityScaleOf(rarity)
	local ps = Config.PetStats
	local scales = type(ps) == "table" and ps.RarityScale
	local s = type(scales) == "table" and type(rarity) == "string" and tonumber(scales[rarity]) or nil
	if finite(s) and s > 0 then
		return s
	end
	return nil
end

local function tierMultiplier(tier)
	if finite(tier) and tier > 0 then
		return tier
	end
	return TycoonCatalog.TierMultiplier[tier] or 1
end

-- a PetDef from a pet id or key ("cat", "cat@Golden" -> def, "Golden"); hybrids ("hyb:...") need the profile -> nil
local function defOfKey(key)
	if type(key) ~= "string" or key == "" or key:sub(1, 4) == "hyb:" then
		return nil, nil
	end
	local petId, suffix = key:match("^([^@]+)@(%a+)$")
	petId = petId or key
	local pc = getPetCatalog()
	local def = pc and type(pc.Get) == "function" and pc.Get(petId) or nil
	if type(def) ~= "table" then
		return nil, nil
	end
	return def, suffix
end

-- RarityScale of a def / {Def} entry / rarity id / pet id / pet key, or nil
local function scaleOfSubject(subject)
	if type(subject) == "table" then
		if type(subject.Def) == "table" then
			subject = subject.Def
		end
		return rarityScaleOf(subject.Rarity)
	end
	if type(subject) == "string" then
		local s = rarityScaleOf(subject)
		if s then
			return s
		end
		local def = defOfKey(subject)
		return def and rarityScaleOf(def.Rarity) or nil
	end
	return nil
end

local function roleMultiplier(def)
	local pc = getPetCatalog()
	if pc and type(pc.RoleMultiplier) == "function" then
		local ok, m = pcall(pc.RoleMultiplier, def)
		if ok and finite(m) and m > 0 then
			return m
		end
	end
	local m = MIRROR.RoleMult[def.Role]
	return finite(m) and m or 1
end

-- the evolution multiplier of a def's STORED stage (1 / 1.25 / 1.5); a stage the rarity cannot reach is cut down
local function evolutionMultiplier(def, level, stage)
	if stage == nil then
		return 1
	end
	local pc = getPetCatalog()
	if pc and type(pc.EvolutionStage) == "function" and type(pc.EvolutionMultiplier) == "function" then
		local ok, s = pcall(pc.EvolutionStage, def, level, stage)
		if ok and finite(s) then
			local ok2, m = pcall(pc.EvolutionMultiplier, s)
			if ok2 and finite(m) and m > 0 then
				return m
			end
		end
		return 1
	end
	local s = int(stage)
	if not s or s < 1 then
		return 1
	end
	local top = MIRROR.EvolveTwice[def.Rarity] and 2 or 1
	return MIRROR.EvolutionBoost[min(s, top)] or 1
end

local function levelBonus()
	local pc = getPetCatalog()
	local b = pc and tonumber(pc.LevelBonus)
	if finite(b) and b >= 0 then
		return b
	end
	return MIRROR.LevelBonus
end

----------------------------------------------------------------------
-- basic lookups
----------------------------------------------------------------------
function TycoonCatalog.Get(id)
	if id == "Prestige" then
		return PRESTIGE_PAD
	end
	return BY_ID[id]
end

function TycoonCatalog.PriceFor(id, level)
	local def = TycoonCatalog.Get(id)
	local lv = int(level)
	if not def or not lv or lv < 1 or lv > def.MaxLevel then
		return nil
	end
	return def.Price[lv]
end

-- (1 + PriceStep) ^ stars; 1 for a LegacyPrices home (a Phase 3 veteran's run). home may be a star count.
function TycoonCatalog.StarPriceMultiplier(home)
	local stars
	if type(home) == "table" then
		if home.LegacyPrices == true then
			return 1
		end
		stars = starsOf(home)
	else
		stars = sanitizeStars(home)
	end
	local step = tonumber(TycoonCatalog.Prestige.PriceStep) or 0
	return (1 + step) ^ stars
end

-- the price this home pays for `level` of `id` (whole Cash), nil when there is no such level
function TycoonCatalog.PriceAt(id, level, home)
	local base = TycoonCatalog.PriceFor(id, level)
	if base == nil then
		return nil
	end
	return floor(base * TycoonCatalog.StarPriceMultiplier(home) + 1e-9)
end

function TycoonCatalog.EffectsOf(id, level)
	local def = BY_ID[id]
	local lv = int(level)
	if not def or not lv or lv < 1 then
		return nil
	end
	return def.Effects[min(lv, def.MaxLevel)]
end

function TycoonCatalog.StationLevel(home, id)
	return levelOf(home, id)
end

function TycoonCatalog.HomeLevelOf(home)
	local total = 0
	for _, def in ipairs(STATIONS) do
		total = total + levelOf(home, def.Id)
	end
	return total
end

-- house tier index (1 = Cottage .. 4 = Sky Castle) and its def; a home without a House is a Cottage
function TycoonCatalog.HouseTierOf(home)
	local i = max(1, levelOf(home, "House"))
	return i, TIERS[i]
end

function TycoonCatalog.HouseTier(idOrIndex)
	local i = tierIndexOf(idOrIndex)
	return i and TIERS[i] or nil
end

-- the max level the current house tier allows for a station
function TycoonCatalog.MaxLevelAt(id, home)
	local def = BY_ID[id]
	if not def then
		return 0
	end
	local tier = TycoonCatalog.HouseTierOf(home)
	return def.TierCaps[TIERS[tier].Id] or 0
end

-- first tier whose cap allows `level` (nil if none)
local function tierAllowing(def, level)
	for i, tier in ipairs(TIERS) do
		if (def.TierCaps[tier.Id] or 0) >= level then
			return i
		end
	end
	return nil
end

-- the coin multiplier of a star count: 1.25 ^ stars
function TycoonCatalog.PrestigeMultiplier(stars)
	return TycoonCatalog.Prestige.IncomeMultiplier ^ sanitizeStars(stars)
end

-- Gems for reaching `newStars` (1 = the first prestige)
function TycoonCatalog.PrestigeGems(newStars)
	local p = TycoonCatalog.Prestige
	local n = max(1, sanitizeStars(newStars))
	return max(p.GemRewardMin, p.GemReward - p.GemRewardStep * (n - 1))
end

----------------------------------------------------------------------
-- requirements, lock reasons and pads
----------------------------------------------------------------------
local function treeMet(def, home)
	for key, need in pairs(def.Requires) do
		if BY_ID[key] and key ~= "House" then
			if levelOf(home, key) < (int(need) or 0) then
				return false
			end
		end
	end
	return true
end

-- why `nextLevel` of `def` cannot be bought yet (nil = it can, given the cash)
local function lockReason(def, nextLevel, home, homeLevel, tier, stars)
	if def.ComingSoon then
		return "Coming soon"
	end
	local req = def.Requires
	local needStars = int(req.Prestige)
	if needStars and stars < needStars then
		return "Unlocks at Prestige " .. needStars
	end
	local needTier = req.House ~= nil and tierIndexOf(req.House) or nil
	if needTier and tier < needTier then
		return "Needs the " .. TIERS[needTier].Name
	end
	local needHL = int(req.HomeLevel)
	local lr = def.LevelRequires[nextLevel]
	if type(lr) == "table" and int(lr.HomeLevel) and (not needHL or int(lr.HomeLevel) > needHL) then
		needHL = int(lr.HomeLevel)
	end
	if needHL and homeLevel < needHL then
		return "Reach Home Level " .. needHL
	end
	local cap = def.TierCaps[TIERS[tier].Id] or 0
	if nextLevel > cap then
		local t = tierAllowing(def, nextLevel)
		if t then
			return "Needs the " .. TIERS[t].Name
		end
		return "Maxed"
	end
	return nil
end

function TycoonCatalog.PadLevelText(currentLevel, nextLevel)
	local cur = int(currentLevel) or 0
	if cur <= 0 then
		return "Build"
	end
	return "Lv " .. cur .. " -> " .. (int(nextLevel) or (cur + 1))
end

-- ok, reason: can this home prestige right now?
function TycoonCatalog.CanPrestige(home)
	local p = TycoonCatalog.Prestige
	local tier = TycoonCatalog.HouseTierOf(home)
	local need = tierIndexOf(p.House) or #TIERS
	if tier < need or levelOf(home, "House") < need then
		return false, "Needs the " .. TIERS[need].Name
	end
	if TycoonCatalog.HomeLevelOf(home) < p.HomeLevel then
		return false, "Reach Home Level " .. p.HomeLevel
	end
	return true, nil
end

function TycoonCatalog.AvailablePads(home)
	local pads = {}
	local homeLevel = TycoonCatalog.HomeLevelOf(home)
	local tier = TycoonCatalog.HouseTierOf(home)
	local stars = starsOf(home)
	local priceMult = TycoonCatalog.StarPriceMultiplier(type(home) == "table" and home or 0)
	for _, def in ipairs(STATIONS) do
		local level = levelOf(home, def.Id)
		if level < def.MaxLevel and treeMet(def, home) then
			local nextLevel = level + 1
			local title = def.Name
			if def.Kind == "House" then
				title = (TIERS[nextLevel] and TIERS[nextLevel].Name) or def.Name
			end
			local base = def.Price[nextLevel]
			pads[#pads + 1] = {
				StationId = def.Id,
				NextLevel = nextLevel,
				Price = floor(base * priceMult + 1e-9),
				BasePrice = base,
				Locked = lockReason(def, nextLevel, home, homeLevel, tier, stars),
				Level = level,
				MaxLevel = def.MaxLevel,
				Name = def.Name,
				Title = title,
				Kind = def.Kind,
				Icon = def.Icon,
				LevelText = TycoonCatalog.PadLevelText(level, nextLevel),
			}
		end
	end
	local castle = tierIndexOf(TycoonCatalog.Prestige.House) or #TIERS
	if levelOf(home, "House") >= castle then
		local ok, reason = TycoonCatalog.CanPrestige(home)
		pads[#pads + 1] = {
			StationId = PRESTIGE_PAD.Id,
			NextLevel = stars + 1,
			Price = 0,
			BasePrice = 0,
			Locked = (not ok) and reason or nil,
			Level = stars,
			MaxLevel = stars + 1,
			Name = PRESTIGE_PAD.Name,
			Title = "Prestige " .. (stars + 1),
			Kind = PRESTIGE_PAD.Kind,
			Icon = PRESTIGE_PAD.Icon,
			LevelText = stars .. " -> " .. (stars + 1) .. " " .. ICON.Star,
			Prestige = true,
		}
	end
	return pads
end

-- Server-side purchase check: ok, price | nil, reason. The price is the home's star price (PriceAt).
-- (TycoonService still re-checks the Cash atomically.)
function TycoonCatalog.CheckPurchase(home, stationId)
	if type(stationId) ~= "string" or not BY_ID[stationId] then
		return false, nil, "Unknown station"
	end
	for _, pad in ipairs(TycoonCatalog.AvailablePads(home)) do
		if pad.StationId == stationId then
			if pad.Locked then
				return false, pad.Price, pad.Locked
			end
			return true, pad.Price, nil
		end
	end
	local def = BY_ID[stationId]
	if levelOf(home, stationId) >= def.MaxLevel then
		return false, nil, "Maxed"
	end
	return false, nil, "Not unlocked yet"
end

-- The Stations table after a prestige: decor (KeepOnPrestige) stays, a station with a ResetLevel (the Garden) is set
-- to it (so the coins never stop), everything else resets.
function TycoonCatalog.StationsAfterPrestige(stations)
	local out = {}
	if type(stations) == "table" then
		for id, level in pairs(stations) do
			local def = BY_ID[id]
			local lv = int(level)
			if def and def.KeepOnPrestige and lv and lv > 0 then
				out[id] = min(lv, def.MaxLevel)
			end
		end
	end
	for _, def in ipairs(STATIONS) do
		local reset = int(def.ResetLevel)
		if reset and reset > 0 and not def.KeepOnPrestige then
			out[def.Id] = min(reset, def.MaxLevel)
		end
	end
	return out
end

----------------------------------------------------------------------
-- rainbow coins: food, pet power, garden places, income, piles, scoop radius, offline earnings
----------------------------------------------------------------------
-- the Food of every meal: 0 without a Garden, else GrassFood + the built plants' Effects.Food
function TycoonCatalog.FoodOf(home)
	if levelOf(home, "Garden") < 1 then
		return 0
	end
	local total = TycoonCatalog.Coins.GrassFood
	for _, def in ipairs(STATIONS) do
		if def.Kind == "Plant" then
			local lv = levelOf(home, def.Id)
			if lv > 0 then
				total = total + (def.Effects[lv].Food or 0)
			end
		end
	end
	return total
end

-- the coin power of one garden entry (any of the shapes listed in the header); prestige NOT applied
function TycoonCatalog.PetPower(entry, level, tier, stage)
	if type(entry) == "number" then
		if finite(entry) and entry > 0 then
			return entry
		end
		return 0
	end
	local def = entry
	if type(entry) == "string" then
		local suffix
		def, suffix = defOfKey(entry)
		if not def then
			return 0
		end
		if tier == nil then
			tier = suffix
		end
	end
	if type(def) ~= "table" then
		return 0
	end
	if type(def.Def) == "table" then
		if level == nil then
			level = def.Level
		end
		if tier == nil then
			tier = def.Tier
		end
		if stage == nil then
			stage = def.Stage
			if stage == nil then
				stage = def.Evo
			end
		end
		def = def.Def
	elseif def.Rarity == nil and def.Power ~= nil then
		local v = tonumber(def.Power)
		if finite(v) and v > 0 then
			return v
		end
		return 0
	end
	local scale = rarityScaleOf(def.Rarity)
	if not scale then
		return 0
	end
	local top = TycoonCatalog.PetXp.MaxLevel
	local lv = int(level)
	if lv == nil then
		lv = int(def.Level) or 1
	end
	lv = max(1, min(lv, top))
	local mult = tier
	if mult == nil then
		mult = def.StatMultiplier or def.Tier or (type(def.Look) == "table" and def.Look.Finish) or nil
	end
	if stage == nil then
		stage = def.Stage
	end
	local power = scale * (1 + levelBonus() * (lv - 1)) * tierMultiplier(mult) * roleMultiplier(def) * evolutionMultiplier(def, lv, stage)
	if not finite(power) or power < 0 then
		return 0
	end
	return power
end

-- the open garden places: 0 without a Garden, else min(Max, max(Base + PerStar x stars, LegacySlots))
function TycoonCatalog.GardenSlots(home)
	if levelOf(home, "Garden") < 1 then
		return 0
	end
	local p = TycoonCatalog.Prestige
	local open = p.GardenSlotsBase + p.GardenSlotsPerStar * starsOf(home)
	local legacy = int(type(home) == "table" and home.LegacySlots or nil)
	if legacy and legacy > open then
		open = legacy
	end
	return max(0, min(p.GardenSlotsMax, open))
end

function TycoonCatalog.LuckyChance(home)
	local lv = levelOf(home, "Garden")
	if lv < 1 then
		return 0
	end
	local c = tonumber(BY_ID.Garden.Effects[lv].Lucky) or 0
	return max(0, min(1, c))
end

-- the Lucky expected value: one coin is worth this many plain coins on average
function TycoonCatalog.LuckyEV(home)
	return 1 + (TycoonCatalog.Coins.LuckyMult - 1) * TycoonCatalog.LuckyChance(home)
end

-- the sum of PetPower over the open places (entries[1 .. open]; the rest rest)
local function gardenPower(entries, open)
	local total = 0
	if type(entries) ~= "table" then
		return 0
	end
	for slot = 1, open do
		local e = entries[slot]
		if e ~= nil then
			total = total + TycoonCatalog.PetPower(e)
		end
	end
	return total
end

function TycoonCatalog.IncomePerSecond(home, entries, prestige)
	local stars = prestige
	if stars == nil then
		stars = starsOf(home)
	end
	local mult = TycoonCatalog.PrestigeMultiplier(stars)
	local food = TycoonCatalog.FoodOf(home)
	local pets = gardenPower(entries, TycoonCatalog.GardenSlots(home))
	local lucky = TycoonCatalog.LuckyEV(home)
	local total = food / TycoonCatalog.Coins.MealSeconds * pets * lucky * mult
	if not finite(total) or total < 0 then
		total = 0
	end
	return total, { Food = food, Pets = pets, Lucky = lucky, Multiplier = mult }
end

-- one plain (not Lucky) coin of a pet with `power`: Food x power x 1.25 ^ stars
function TycoonCatalog.CoinValue(home, power, prestige)
	local stars = prestige
	if stars == nil then
		stars = starsOf(home)
	end
	local p = tonumber(power)
	if not finite(p) or p <= 0 then
		return 0
	end
	local v = TycoonCatalog.FoodOf(home) * p * TycoonCatalog.PrestigeMultiplier(stars)
	return finite(v) and v or 0
end

-- the CoinPiles heap stage (0..5) of a pile holding `coins` coins (Coins.HeapStages)
function TycoonCatalog.HeapStage(coins)
	local n = tonumber(coins)
	if not finite(n) or n < 1 then
		return 0
	end
	local stage = 0
	for i, need in ipairs(TycoonCatalog.Coins.HeapStages) do
		if n >= need then
			stage = i
		end
	end
	return stage
end

function TycoonCatalog.ScoopRadius(home)
	local lv = levelOf(home, "Collector")
	if lv < 1 then
		return TycoonCatalog.Coins.BaseRadius
	end
	return BY_ID.Collector.Effects[lv].Radius
end

function TycoonCatalog.PileSeconds(home)
	local lv = levelOf(home, "Collector")
	local s = TycoonCatalog.Coins.BasePileSeconds
	if lv >= 1 then
		s = BY_ID.Collector.Effects[lv].PileSeconds
	end
	local vault = levelOf(home, "Vault")
	if vault >= 1 then
		s = s + (BY_ID.Vault.Effects[vault].PileSeconds or 0)
	end
	return s
end

-- the pile point of garden place `slot` (1..12) in the Garden's station frame, or nil
function TycoonCatalog.CoinPoint(slot)
	local n = int(slot)
	if not n or n ~= tonumber(slot) then
		return nil
	end
	return GARDEN_COINS[n]
end

function TycoonCatalog.OfflineEarnings(home, seconds, incomePerSecond)
	local vault = levelOf(home, "Vault")
	local s = tonumber(seconds)
	local income = tonumber(incomePerSecond)
	if vault < 1 or not s or s ~= s or not income or income ~= income or income <= 0 or income == huge then
		return 0, { Seconds = 0, Percent = 0, MaxHours = 0 }
	end
	local ve = BY_ID.Vault.Effects[vault]
	local info = { Seconds = 0, Percent = ve.OfflinePercent, MaxHours = ve.OfflineHours }
	if s < TycoonCatalog.OfflineMinSeconds then
		return 0, info
	end
	local counted = min(s, ve.OfflineHours * 3600)
	info.Seconds = counted
	return floor(income * counted * ve.OfflinePercent), info
end

----------------------------------------------------------------------
-- the Food Machine, the Training Place, food, fusion, XP
----------------------------------------------------------------------
function TycoonCatalog.XpToNext(level)
	local px = TycoonCatalog.PetXp
	local lv = int(level)
	if not lv or lv < 1 then
		lv = 1
	end
	if lv >= px.MaxLevel then
		return huge
	end
	local raw = px.Base * lv ^ px.Exponent
	return max(px.Round, floor(raw / px.Round + 0.5) * px.Round)
end

-- total XP from level 1 to `level`
function TycoonCatalog.XpForLevel(level)
	local lv = int(level) or 1
	local total = 0
	for l = 1, min(lv, TycoonCatalog.PetXp.MaxLevel) - 1 do
		total = total + TycoonCatalog.XpToNext(l)
	end
	return total
end

-- XP of one machine feed for a pet at `level` (0 at the top level or without a machine)
function TycoonCatalog.FeedXp(level, machineLevel)
	local ml = int(machineLevel)
	if not ml or ml < 1 then
		return 0
	end
	ml = min(ml, #TycoonCatalog.FeedShare)
	local need = TycoonCatalog.XpToNext(level)
	if need == huge then
		return 0
	end
	return max(1, floor(need * TycoonCatalog.FeedShare[ml] + 0.5))
end

-- Cash of one machine feed for a pet (def / rarity / pet id / key) at `level`; nil at the top level or for junk
function TycoonCatalog.FeedPrice(def, level)
	local scale = scaleOfSubject(def)
	local need = TycoonCatalog.XpToNext(level)
	if not scale or need == huge then
		return nil
	end
	return floor(need * scale * TycoonCatalog.FeedBase + 0.5)
end

-- Cash for rank `rank` (1..MaxRank) of any skill for a pet (def / rarity / pet id / key); nil for junk
function TycoonCatalog.TrainCost(def, rank)
	local tr = TycoonCatalog.Training
	local r = int(rank)
	local scale = scaleOfSubject(def)
	if not r or r ~= tonumber(rank) or r < 1 or r > tr.MaxRank or not scale then
		return nil
	end
	return floor(tr.CostBase * r * r * scale + 0.5)
end

-- seconds rank `rank` (1..MaxRank) takes; nil for junk
function TycoonCatalog.TrainSeconds(rank)
	local tr = TycoonCatalog.Training
	local r = int(rank)
	if not r or r ~= tonumber(rank) or r < 1 or r > tr.MaxRank then
		return nil
	end
	return r * tr.MinutesPerRank * 60
end

-- pets training at once (the Training Place level's Slots; 0 while it is not built)
function TycoonCatalog.TrainingSlots(home)
	local lv = levelOf(home, "Gym")
	if lv < 1 then
		return 0
	end
	return BY_ID.Gym.Effects[lv].Slots
end

function TycoonCatalog.FoodById(id)
	return FOOD_BY_ID[id]
end

-- cost table ({Tokens = n} or {Gems = n}) of a fusion, or nil.
--   FusionCost("Upgrade", rarity, "Golden" | "Rainbow", fusionLevel?)   (target tier)
--   FusionCost("Mix", rarity, nil, fusionLevel?)                         (the higher rarity of both inputs)
-- The Fusion Machine's TokenDiscount (by level) lowers Token prices; Gem prices never change.
function TycoonCatalog.FusionCost(action, rarity, tier, fusionLevel)
	local F = TycoonCatalog.Fusion
	local base
	if action == "Upgrade" then
		local row = F.Upgrade[rarity]
		base = row and row[tier or "Golden"]
	elseif action == "Mix" then
		base = F.Mix[rarity]
	end
	if type(base) ~= "table" then
		return nil
	end
	local discount = 0
	local lv = int(fusionLevel)
	if lv and lv >= 1 then
		local eff = BY_ID.FusionMachine.Effects[min(lv, BY_ID.FusionMachine.MaxLevel)]
		discount = eff.TokenDiscount or 0
	end
	local out = {}
	for k, v in pairs(base) do
		if k == "Tokens" then
			out[k] = floor(v * (1 - discount) + 0.5)
		else
			out[k] = v
		end
	end
	return out
end

-- "$950", "$12.5K", "$3.2M"
function TycoonCatalog.FormatCash(n)
	local v = tonumber(n) or 0
	if v ~= v then
		v = 0
	end
	local a = math.abs(v)
	local sign = v < 0 and "-" or ""
	if a < 10000 then
		return sign .. "$" .. commas(a)
	end
	local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, u in ipairs(units) do
		if a >= u[1] then
			local x = a / u[1]
			local s
			if x >= 100 then
				s = string.format("%d", floor(x))
			else
				s = string.format("%.1f", floor(x * 10) / 10)
				s = s:gsub("%.0$", "")
			end
			return sign .. "$" .. s .. u[2]
		end
	end
	return sign .. "$" .. commas(a)
end

----------------------------------------------------------------------
-- Validate (data self-check): ok, { problem... }
----------------------------------------------------------------------
-- world-aligned rectangle {x0, x1, z0, z1} of a slot footprint (yaw in 90 degree steps)
local function footprintRect(cf, size)
	local look = cf.LookVector
	local alongX = math.abs(look.X) > 0.7 -- the front faces +-X: the width runs along Z
	local w, d = size.X, size.Z
	local sx, sz = w, d
	if alongX then
		sx, sz = d, w
	end
	local p = cf.Position
	return { p.X - sx / 2, p.X + sx / 2, p.Z - sz / 2, p.Z + sz / 2 }
end
TycoonCatalog.FootprintRect = footprintRect

local function padRect(cf)
	local s = TycoonCatalog.Layout.PadSize
	local p = cf.Position
	return { p.X - s.X / 2, p.X + s.X / 2, p.Z - s.Z / 2, p.Z + s.Z / 2 }
end
TycoonCatalog.PadRect = padRect

-- plot-local rectangle {x0, x1, z0, z1} of a rectangle given in a station frame (centre + size, e.g. a garden walk)
local function localRect(slotCFrame, center, size)
	return footprintRect(slotCFrame * CFrame.new(center.X, center.Y, center.Z), size)
end
TycoonCatalog.LocalRect = localRect

local function overlap(a, b, gap)
	gap = gap or 0
	return a[1] < b[2] + gap and b[1] < a[2] + gap and a[3] < b[4] + gap and b[3] < a[4] + gap
end

local function inside(rect, x, z, pad)
	pad = pad or 0
	return x >= rect[1] - pad and x <= rect[2] + pad and z >= rect[3] - pad and z <= rect[4] + pad
end

-- a walk-through zone (true) vs a solid station (the Garden's Walkable is a list of walks INSIDE its solid footprint)
local function walkThrough(slot)
	return slot.Walkable == true or slot.Perimeter == true
end

-- Which pads can a player (about 2 studs wide) walk to from the gate? Returns { [padName] = true } for reachable
-- pads and the grid size. Obstacles: every station footprint that is not a walk-through zone, grown by `radius`.
function TycoonCatalog.ReachablePads(radius, cell)
	radius = radius or 1
	cell = cell or 1
	local n = floor(PLOT / cell)
	local blocked = {}
	local rects = {}
	for _, def in ipairs(STATIONS) do
		local slot = def.Slot
		if slot and not walkThrough(slot) then
			rects[#rects + 1] = footprintRect(slot.CFrame, slot.Footprint)
		end
	end
	local function cellCentre(i)
		return -HALF + (i - 0.5) * cell
	end
	for ix = 1, n do
		for iz = 1, n do
			local x, z = cellCentre(ix), cellCentre(iz)
			local b = math.abs(x) > HALF - radius or math.abs(z) > HALF - radius
			if not b then
				for _, r in ipairs(rects) do
					if x > r[1] - radius and x < r[2] + radius and z > r[3] - radius and z < r[4] + radius then
						b = true
						break
					end
				end
			end
			if b then
				blocked[(ix - 1) * n + iz] = true
			end
		end
	end
	-- flood from the gate (the cells just inside the opening)
	local seen = {}
	local queue = {}
	local gate = TycoonCatalog.Layout.Gate
	for ix = 1, n do
		local x = cellCentre(ix)
		if math.abs(x - gate.X) < TycoonCatalog.Layout.GateWidth / 2 - radius then
			for iz = 1, 3 do
				local key = (ix - 1) * n + iz
				if not blocked[key] and not seen[key] then
					seen[key] = true
					queue[#queue + 1] = key
				end
			end
		end
	end
	local head = 1
	while head <= #queue do
		local key = queue[head]
		head = head + 1
		local ix = floor((key - 1) / n) + 1
		local iz = key - (ix - 1) * n
		local nbs = { { ix + 1, iz }, { ix - 1, iz }, { ix, iz + 1 }, { ix, iz - 1 } }
		for _, nb in ipairs(nbs) do
			local a, b = nb[1], nb[2]
			if a >= 1 and a <= n and b >= 1 and b <= n then
				local k2 = (a - 1) * n + b
				if not blocked[k2] and not seen[k2] then
					seen[k2] = true
					queue[#queue + 1] = k2
				end
			end
		end
	end
	local reachable = {}
	local all = {}
	for _, def in ipairs(STATIONS) do
		all[#all + 1] = { def.Id, def.Slot.Pad }
	end
	all[#all + 1] = { PRESTIGE_PAD.Id, PRESTIGE_PAD.Slot.Pad }
	for _, item in ipairs(all) do
		local r = padRect(item[2])
		local ok = false
		for ix = 1, n do
			local x = cellCentre(ix)
			if x > r[1] and x < r[2] then
				for iz = 1, n do
					local z = cellCentre(iz)
					if z > r[3] and z < r[4] and seen[(ix - 1) * n + iz] then
						ok = true
						break
					end
				end
			end
			if ok then
				break
			end
		end
		reachable[item[1]] = ok
	end
	return reachable, n
end

-- per-kind effect rules (section 5.4): bad(msg) for every problem of one station
local function rising(values, strict)
	for i = 2, #values do
		if strict and values[i] <= values[i - 1] then
			return false
		elseif not strict and values[i] < values[i - 1] then
			return false
		end
	end
	return true
end

local function effectValues(def, key)
	local out = {}
	for lv = 1, def.MaxLevel do
		local e = def.Effects[lv]
		local v = type(e) == "table" and e[key] or nil
		if not finite(v) then
			return nil
		end
		out[lv] = v
	end
	return out
end

local function checkKindEffects(def, bad)
	local id, kind = def.Id, def.Kind
	local C = TycoonCatalog.Coins
	if kind == "Plant" then
		local food = effectValues(def, "Food")
		if not food or food[1] <= 0 or not rising(food, true) then
			bad(id .. ": Effects.Food must be positive and rising")
		end
	elseif kind == "Garden" then
		local lucky = effectValues(def, "Lucky")
		if not lucky or lucky[1] < 0 or lucky[#lucky] > 0.5 or not rising(lucky, false) then
			bad(id .. ": Effects.Lucky must be a chance in 0..0.5 that never drops")
		end
		local spots = def.Slot and def.Slot.Spots
		if type(spots) ~= "table" or #spots < TycoonCatalog.Prestige.GardenSlotsMax then
			bad(id .. ": needs " .. TycoonCatalog.Prestige.GardenSlotsMax .. " Spots (Prestige.GardenSlotsMax)")
		end
		local reset = def.ResetLevel
		if reset ~= nil and (int(reset) ~= reset or reset < 1 or reset > def.MaxLevel) then
			bad(id .. ": ResetLevel must be a level of the station")
		end
	elseif kind == "Magnet" then
		local radius = effectValues(def, "Radius")
		local pile = effectValues(def, "PileSeconds")
		if not radius or radius[1] <= C.BaseRadius or not rising(radius, true) then
			bad(id .. ": Effects.Radius must rise above Coins.BaseRadius")
		end
		if not pile or pile[1] <= C.BasePileSeconds or not rising(pile, true) then
			bad(id .. ": Effects.PileSeconds must rise above Coins.BasePileSeconds")
		end
	elseif kind == "FoodMachine" then
		local share = effectValues(def, "FeedShare")
		if not share or share[1] <= 0 or share[#share] > 1 or not rising(share, true) then
			bad(id .. ": Effects.FeedShare must rise and stay in 0..1")
		end
	elseif kind == "Training" then
		local slots = effectValues(def, "Slots")
		if not slots or slots[1] < 1 or not rising(slots, true) then
			bad(id .. ": Effects.Slots must be >= 1 and rising")
		end
		local spots = def.Slot and def.Slot.Spots
		if slots and (type(spots) ~= "table" or #spots < slots[#slots]) then
			bad(id .. ": needs a Spot for every training slot")
		end
	elseif kind == "Vault" then
		local pile = effectValues(def, "PileSeconds")
		local pct = effectValues(def, "OfflinePercent")
		local hours = effectValues(def, "OfflineHours")
		if not pile or pile[1] <= 0 or not rising(pile, true) then
			bad(id .. ": Effects.PileSeconds must be positive and rising")
		end
		if not pct or not hours or pct[1] <= 0 or pct[#pct] > 1 or hours[1] <= 0 or not rising(pct, true) or not rising(hours, false) then
			bad(id .. ": Effects.OfflinePercent / OfflineHours must be positive and rising")
		end
	elseif kind == "Fusion" then
		local d = effectValues(def, "TokenDiscount")
		if not d or d[1] < 0 or d[#d] >= 1 or not rising(d, false) then
			bad(id .. ": Effects.TokenDiscount must be in 0..1 and never drop")
		end
	end
end

-- the garden layout of section 3.3: 12 places, the walks, the coin points and the Welcome-back pile
local function checkGardenLayout(bad)
	local garden = BY_ID.Garden
	local slot = garden and garden.Slot
	if type(slot) ~= "table" or typeof(slot.CFrame) ~= "CFrame" or typeof(slot.Footprint) ~= "Vector3" then
		bad("Garden: no slot")
		return
	end
	local fp = slot.Footprint
	local fr = footprintRect(slot.CFrame, fp)
	-- the entrance strip: the band in front of the footprint (toward the Garden's pad)
	local look = slot.CFrame.LookVector
	local depth = TycoonCatalog.Layout.GardenEntranceDepth or 6
	local strip = { fr[1], fr[2], fr[3], fr[4] }
	if look.X < -0.7 then
		strip = { fr[1] - depth, fr[1], fr[3], fr[4] }
	elseif look.X > 0.7 then
		strip = { fr[2], fr[2] + depth, fr[3], fr[4] }
	elseif look.Z < -0.7 then
		strip = { fr[1], fr[2], fr[3] - depth, fr[3] }
	elseif look.Z > 0.7 then
		strip = { fr[1], fr[2], fr[4], fr[4] + depth }
	end
	local pads = {}
	for _, def in ipairs(STATIONS) do
		pads[#pads + 1] = { def.Id, padRect(def.Slot.Pad) }
	end
	pads[#pads + 1] = { "Prestige", padRect(PRESTIGE_PAD.Slot.Pad) }
	local function onPad(x, z)
		for _, p in ipairs(pads) do
			if inside(p[2], x, z, 0.25) then
				return p[1]
			end
		end
		return nil
	end
	local function inYard(x, z)
		return math.abs(x) <= HALF - 1 and math.abs(z) <= HALF - 1
	end
	-- the places: inside the footprint, apart, never on a walk
	local spots = slot.Spots or {}
	local walks = type(slot.Walkable) == "table" and slot.Walkable or {}
	if #walks == 0 then
		bad("Garden: Slot.Walkable must list the sand walks")
	end
	local walkRects = {}
	for i, w in ipairs(walks) do
		if type(w) ~= "table" or typeof(w.Center) ~= "Vector3" or typeof(w.Size) ~= "Vector3" then
			bad("Garden: walk " .. i .. " needs Center and Size")
		else
			walkRects[#walkRects + 1] = localRect(slot.CFrame, w.Center, w.Size)
			if math.abs(w.Center.X) + w.Size.X / 2 > fp.X / 2 + 1e-6 or math.abs(w.Center.Z) + w.Size.Z / 2 > fp.Z / 2 + 1e-6 then
				bad("Garden: walk " .. tostring(w.Name or i) .. " leaves the footprint")
			end
		end
	end
	local function onWalk(x, z)
		for _, r in ipairs(walkRects) do
			if inside(r, x, z) then
				return true
			end
		end
		return false
	end
	local spotWorld = {}
	for i, v in ipairs(spots) do
		if math.abs(v.X) > fp.X / 2 - 1.5 or math.abs(v.Z) > fp.Z / 2 - 1.5 then
			bad("Garden: place " .. i .. " leaves the footprint")
		end
		local w = slot.CFrame * v
		spotWorld[i] = w
		if onWalk(w.X, w.Z) then
			bad("Garden: place " .. i .. " sits on a walk")
		end
		for j = 1, i - 1 do
			if (spots[j] - v).Magnitude < 4 then
				bad("Garden: places " .. j .. " and " .. i .. " are closer than 4 studs")
			end
		end
	end
	-- the coin points: one per place, inside the yard, >= 1.5 studs apart, on a walk inside the footprint, on no pad,
	-- off every cushion bed
	local coins = slot.CoinPoints or {}
	if #coins < #spots then
		bad("Garden: needs a coin point for every place")
	end
	local coinWorld = {}
	for i = 1, #spots do
		local v = TycoonCatalog.CoinPoint(i)
		if typeof(v) ~= "Vector3" then
			bad("Garden: CoinPoint(" .. i .. ") is missing")
		else
			local w = slot.CFrame * v
			coinWorld[#coinWorld + 1] = w
			if not inYard(w.X, w.Z) then
				bad("Garden: coin point " .. i .. " leaves the yard")
			end
			if not (inside(fr, w.X, w.Z) or inside(strip, w.X, w.Z)) then
				bad("Garden: coin point " .. i .. " lies outside the garden and its entrance")
			end
			if not onWalk(w.X, w.Z) then
				bad("Garden: coin point " .. i .. " is not on a walk")
			end
			local padId = onPad(w.X, w.Z)
			if padId then
				bad("Garden: coin point " .. i .. " lies on the " .. padId .. " pad")
			end
			for j, s in ipairs(spotWorld) do
				if math.abs(s.X - w.X) < 1.5 and math.abs(s.Z - w.Z) < 1.5 then
					bad("Garden: coin point " .. i .. " lies on the bed of place " .. j)
				end
			end
			for j = 1, #coinWorld - 1 do
				if (coinWorld[j] - w).Magnitude < 1.5 then
					bad("Garden: coin points " .. j .. " and " .. i .. " are closer than 1.5 studs")
				end
			end
		end
	end
	if TycoonCatalog.CoinPoint(#spots + 1) ~= nil or TycoonCatalog.CoinPoint(0) ~= nil then
		bad("Garden: CoinPoint answers only the places 1.." .. #spots)
	end
	-- the Welcome-back pile: plot-local, inside the yard and the entrance strip, off every pad, apart from the piles
	local wp = slot.WelcomePile
	if typeof(wp) ~= "Vector3" then
		bad("Garden: Slot.WelcomePile is missing")
	else
		if not inYard(wp.X, wp.Z) then
			bad("Garden: the Welcome-back pile leaves the yard")
		end
		if not (inside(strip, wp.X, wp.Z) or inside(fr, wp.X, wp.Z)) then
			bad("Garden: the Welcome-back pile is not beside the garden entrance")
		end
		local padId = onPad(wp.X, wp.Z)
		if padId then
			bad("Garden: the Welcome-back pile lies on the " .. padId .. " pad")
		end
		for i, w in ipairs(coinWorld) do
			if (w - wp).Magnitude < 1.5 then
				bad("Garden: the Welcome-back pile touches coin point " .. i)
			end
		end
		for _, def in ipairs(STATIONS) do
			if def ~= garden and not walkThrough(def.Slot) and inside(footprintRect(def.Slot.CFrame, def.Slot.Footprint), wp.X, wp.Z) then
				bad("Garden: the Welcome-back pile lies inside " .. def.Id)
			end
		end
	end
end

function TycoonCatalog.Validate()
	local problems = {}
	local function bad(msg)
		problems[#problems + 1] = msg
	end
	local kindSet = {}
	for _, k in ipairs(TycoonCatalog.Kinds) do
		kindSet[k] = true
	end
	local contractIds = {
		"Press1", "Press2", "Press3", "Press4", "Collector", "Garden", "Kitchen", "Gym", "Vault", "House",
		"FusionMachine", "ArenaGate", "DecorLamps", "DecorFence", "DecorFlowers", "DecorFountain", "DecorBanners", "DecorPodium",
	}
	for _, id in ipairs(contractIds) do
		if not BY_ID[id] then
			bad("missing station " .. id)
		end
	end
	if #STATIONS ~= #contractIds then
		bad("expected " .. #contractIds .. " stations, found " .. #STATIONS)
	end
	if #TIERS ~= 4 then
		bad("expected 4 house tiers")
	end

	local seen = {}
	for _, def in ipairs(STATIONS) do
		local id = tostring(def.Id)
		if seen[id] then
			bad("duplicate station id " .. id)
		end
		seen[id] = true
		if type(def.Name) ~= "string" or def.Name == "" then
			bad(id .. ": missing Name")
		end
		if not kindSet[def.Kind] then
			bad(id .. ": unknown Kind " .. tostring(def.Kind))
		end
		if type(def.Icon) ~= "string" or def.Icon == "" then
			bad(id .. ": missing Icon")
		end
		local maxLevel = int(def.MaxLevel)
		if not maxLevel or maxLevel < 1 or maxLevel ~= def.MaxLevel then
			bad(id .. ": MaxLevel must be a whole number >= 1")
			maxLevel = 0
		end
		-- prices: whole, >= 0, rising
		local last = -1
		for lv = 1, maxLevel do
			local p = def.Price[lv]
			if type(p) ~= "number" or p < 0 or p ~= floor(p) then
				bad(id .. ": Price[" .. lv .. "] must be a whole number >= 0")
			elseif p < last or (p == last and p > 0) then
				bad(id .. ": Price[" .. lv .. "] must be higher than the level before")
			else
				last = p
			end
			if type(def.Effects[lv]) ~= "table" then
				bad(id .. ": Effects[" .. lv .. "] missing")
			end
		end
		if def.Price[maxLevel + 1] ~= nil or def.Effects[maxLevel + 1] ~= nil then
			bad(id .. ": Price / Effects go past MaxLevel")
		end
		if maxLevel > 0 then
			checkKindEffects(def, bad)
		end
		-- tier caps: 0..MaxLevel, never dropping, the Sky Castle allows MaxLevel
		local lastCap = 0
		for _, tier in ipairs(TIERS) do
			local c = def.TierCaps[tier.Id]
			if type(c) ~= "number" or c < 0 or c > maxLevel or c ~= floor(c) then
				bad(id .. ": TierCaps." .. tier.Id .. " must be a whole number in 0.." .. maxLevel)
			elseif c < lastCap then
				bad(id .. ": TierCaps drop at " .. tier.Id)
			else
				lastCap = c
			end
		end
		if def.TierCaps.SkyCastle ~= maxLevel then
			bad(id .. ": the Sky Castle must allow MaxLevel")
		end
		-- requirement keys
		for key, need in pairs(def.Requires) do
			if key == "HomeLevel" or key == "Prestige" then
				if int(need) == nil or need < 0 then
					bad(id .. ": Requires." .. key .. " must be a whole number")
				end
			elseif key == "House" then
				if not tierIndexOf(need) then
					bad(id .. ": Requires.House must be a house tier id")
				end
			elseif BY_ID[key] then
				if key == id then
					bad(id .. ": requires itself")
				elseif int(need) == nil or need < 1 or need > BY_ID[key].MaxLevel then
					bad(id .. ": Requires." .. key .. " out of range")
				end
			else
				bad(id .. ": unknown requirement " .. tostring(key))
			end
		end
		-- slot
		local slot = def.Slot
		local slotOk = type(slot) == "table" and typeof(slot.CFrame) == "CFrame" and typeof(slot.Footprint) == "Vector3"
		if not slotOk or typeof(slot.Pad) ~= "CFrame" then
			bad(id .. ": Slot needs CFrame, Footprint and Pad")
		end
	end

	-- the House levels follow the tiers
	local house = BY_ID.House
	if house then
		for i, tier in ipairs(TIERS) do
			if house.Effects[i] and house.Effects[i].Tier ~= tier.Id then
				bad("House.Effects[" .. i .. "].Tier must be " .. tier.Id)
			end
			if i >= 2 then
				local lr = house.LevelRequires[i]
				if type(lr) ~= "table" or lr.HomeLevel ~= tier.HomeLevel then
					bad("House level " .. i .. " must need Home Level " .. tier.HomeLevel)
				end
			end
		end
	end
	local lastHL = -1
	for _, tier in ipairs(TIERS) do
		if type(tier.HomeLevel) ~= "number" or tier.HomeLevel <= lastHL then
			bad("HouseTiers HomeLevel must rise")
		end
		lastHL = tier.HomeLevel or lastHL
	end

	-- a fresh home shows exactly one pad: the free Pet Garden (the root of the tree)
	local fresh = TycoonCatalog.AvailablePads({ Stations = {}, Prestige = 0 })
	if #fresh ~= 1 or fresh[1].StationId ~= "Garden" or fresh[1].Price ~= 0 or fresh[1].Locked ~= nil then
		bad("a fresh home must show exactly one pad: the free, open Pet Garden (" .. #fresh .. " pads)")
	end

	-- no dead ends: buying every unlocked pad (cheapest first, cash unlimited) reaches the Sky Castle, Home Level
	-- 40 and the prestige; with 1 star, every station but the "Coming soon" ones reaches MaxLevel
	local function buildOut(stars)
		local home = { Stations = {}, Prestige = stars }
		for _ = 1, 400 do
			local best = nil
			for _, pad in ipairs(TycoonCatalog.AvailablePads(home)) do
				if not pad.Locked and not pad.Prestige and (not best or pad.Price < best.Price) then
					best = pad
				end
			end
			if not best then
				break
			end
			home.Stations[best.StationId] = best.NextLevel
		end
		return home
	end
	local first = buildOut(0)
	local okPrestige, why = TycoonCatalog.CanPrestige(first)
	if not okPrestige then
		bad("dead end: a fresh home cannot reach the prestige (" .. tostring(why) .. ")")
	end
	local later = buildOut(1)
	for _, def in ipairs(STATIONS) do
		if not def.ComingSoon and levelOf(later, def.Id) < def.MaxLevel then
			bad("dead end: " .. def.Id .. " stops at level " .. levelOf(later, def.Id) .. " of " .. def.MaxLevel)
		end
	end
	-- a prestige keeps the coins going: the stations after it still give a garden (and its pad tree)
	local after = TycoonCatalog.StationsAfterPrestige(first.Stations)
	if levelOf({ Stations = after }, "Garden") < 1 then
		bad("Prestige must keep the Garden built (ResetLevel)")
	end
	-- each tier's caps allow enough Home Level for the next tier (else the house could never be upgraded)
	for i = 1, #TIERS - 1 do
		local total = 0
		for _, def in ipairs(STATIONS) do
			if not def.ComingSoon and not (def.Requires.Prestige and def.Requires.Prestige > 0) then
				total = total + (def.TierCaps[TIERS[i].Id] or 0)
			end
		end
		if total < TIERS[i + 1].HomeLevel then
			local nextTier = TIERS[i + 1]
			bad(TIERS[i].Id .. " caps add up to Home Level " .. total .. ", below the " .. nextTier.Id .. "'s " .. nextTier.HomeLevel)
		end
	end

	-- coins, garden places, star prices, the Food Machine and the Training Place
	local C = TycoonCatalog.Coins
	for _, k in ipairs({ "MealSeconds", "GrassFood", "LuckyMult", "BaseRadius", "BasePileSeconds" }) do
		if not finite(C[k]) or C[k] <= 0 then
			bad("Coins." .. k .. " must be positive")
		end
	end
	if not finite(C.LuckyMult) or C.LuckyMult <= 1 then
		bad("Coins.LuckyMult must be above 1")
	end
	local hs = C.HeapStages
	if type(hs) ~= "table" or #hs ~= 5 or hs[1] ~= 1 or not rising(hs, true) then
		bad("Coins.HeapStages must be 5 rising coin counts starting at 1")
	end
	local p = TycoonCatalog.Prestige
	if int(p.GardenSlotsBase) ~= p.GardenSlotsBase or p.GardenSlotsBase < 1 then
		bad("Prestige.GardenSlotsBase must be a whole number >= 1")
	end
	if int(p.GardenSlotsPerStar) ~= p.GardenSlotsPerStar or p.GardenSlotsPerStar < 0 then
		bad("Prestige.GardenSlotsPerStar must be a whole number >= 0")
	end
	if int(p.GardenSlotsMax) ~= p.GardenSlotsMax or p.GardenSlotsMax < p.GardenSlotsBase then
		bad("Prestige.GardenSlotsMax must be a whole number >= GardenSlotsBase")
	end
	if not finite(p.PriceStep) or p.PriceStep < 0 then
		bad("Prestige.PriceStep must be >= 0")
	end
	local share = TycoonCatalog.FeedShare
	if type(share) ~= "table" or #share ~= BY_ID.Kitchen.MaxLevel then
		bad("FeedShare needs one share per Food Machine level")
	end
	if not finite(TycoonCatalog.FeedBase) or TycoonCatalog.FeedBase <= 0 then
		bad("FeedBase must be positive")
	end
	local tr = TycoonCatalog.Training
	if type(tr) ~= "table" or int(tr.MaxRank) ~= tr.MaxRank or tr.MaxRank < 1 or not finite(tr.CostBase) or tr.CostBase <= 0
		or not finite(tr.MinutesPerRank) or tr.MinutesPerRank <= 0 then
		bad("Training needs a whole MaxRank >= 1 and positive CostBase / MinutesPerRank")
	end
	if TycoonCatalog.Layout.Conveyor ~= nil then
		bad("Layout.Conveyor is gone in Phase 4 (no presses, no belt)")
	end

	-- leftover foods (fed for free by the Food Machine)
	local lastXp = 0
	for i, f in ipairs(TycoonCatalog.Foods) do
		if type(f.Id) ~= "string" or type(f.Name) ~= "string" then
			bad("Foods[" .. i .. "] needs Id and Name")
		end
		for _, k in ipairs({ "Price", "Xp", "CookSeconds", "KitchenLevel" }) do
			if type(f[k]) ~= "number" or f[k] <= 0 then
				bad("Foods[" .. i .. "]." .. k .. " must be positive")
			end
		end
		if type(f.KitchenLevel) == "number" and BY_ID.Kitchen and f.KitchenLevel > BY_ID.Kitchen.MaxLevel then
			bad("Foods[" .. i .. "] needs a Kitchen level that does not exist")
		end
		if type(f.Xp) == "number" and f.Xp <= lastXp then
			bad("Foods: better food must give more XP")
		end
		lastXp = tonumber(f.Xp) or lastXp
	end
	for _, id in ipairs({ "Snack", "Meal", "Feast" }) do
		if not FOOD_BY_ID[id] then
			bad("missing food " .. id)
		end
	end

	-- XP curve
	local px = TycoonCatalog.PetXp
	local prev = 0
	for lv = 1, px.MaxLevel - 1 do
		local x = TycoonCatalog.XpToNext(lv)
		if type(x) ~= "number" or x < prev or x <= 0 or x == huge then
			bad("XpToNext(" .. lv .. ") must be positive and never drop")
			break
		end
		prev = x
	end
	if TycoonCatalog.XpToNext(px.MaxLevel) ~= huge then
		bad("XpToNext(MaxLevel) must be math.huge")
	end
	if TycoonCatalog.MaxPetLevel ~= px.MaxLevel then
		bad("MaxPetLevel must equal PetXp.MaxLevel")
	end

	-- fusion costs for every rarity
	for _, r in ipairs(Config.Rarities or {}) do
		local up = TycoonCatalog.Fusion.Upgrade[r.Id]
		if type(up) ~= "table" or type(up.Golden) ~= "table" or type(up.Rainbow) ~= "table" then
			bad("Fusion.Upgrade." .. tostring(r.Id) .. " needs Golden and Rainbow")
		end
		local mix = TycoonCatalog.Fusion.Mix[r.Id]
		if type(mix) ~= "table" or (type(mix.Tokens) ~= "number" and type(mix.Gems) ~= "number") then
			bad("Fusion.Mix." .. tostring(r.Id) .. " needs Tokens or Gems")
		end
	end

	-- prestige
	if not tierIndexOf(p.House) then
		bad("Prestige.House must be a house tier")
	end
	if type(p.IncomeMultiplier) ~= "number" or p.IncomeMultiplier <= 1 then
		bad("Prestige.IncomeMultiplier must be above 1")
	end
	if type(p.GemReward) ~= "number" or p.GemReward < 0 then
		bad("Prestige.GemReward must be >= 0")
	end

	-- layout: inside the yard, no overlaps between stations / pads, every pad reachable from the gate
	local margin = TycoonCatalog.Layout.Margin
	local rects = {}
	for _, def in ipairs(STATIONS) do
		local slot = def.Slot
		local slotOk = type(slot) == "table" and typeof(slot.CFrame) == "CFrame" and typeof(slot.Footprint) == "Vector3"
		if slotOk and typeof(slot.Pad) == "CFrame" then
			local r = footprintRect(slot.CFrame, slot.Footprint)
			local limit = HALF - margin
			local outside = r[1] < -HALF or r[2] > HALF or r[3] < -HALF or r[4] > HALF
			local inMargin = r[1] < -limit or r[2] > limit or r[3] < -limit or r[4] > limit
			-- the fence decor follows the fence line; other decor may line the fence; stations keep the margin
			if not slot.Perimeter and (outside or (def.Kind ~= "Decor" and inMargin)) then
				bad(def.Id .. ": footprint leaves the yard")
			end
			local pr = padRect(slot.Pad)
			if pr[1] < -HALF or pr[2] > HALF or pr[3] < -HALF or pr[4] > HALF then
				bad(def.Id .. ": pad outside the yard")
			end
			rects[#rects + 1] = { Id = def.Id, R = r, Pad = pr, Walk = walkThrough(slot) }
		end
	end
	local pp = padRect(PRESTIGE_PAD.Slot.Pad)
	rects[#rects + 1] = { Id = "Prestige", R = nil, Pad = pp, Walk = true }
	for i = 1, #rects do
		local a = rects[i]
		for j = i + 1, #rects do
			local b = rects[j]
			if a.R and b.R and not a.Walk and not b.Walk and overlap(a.R, b.R) then
				bad("slots overlap: " .. a.Id .. " and " .. b.Id)
			end
			if overlap(a.Pad, b.Pad, 0.5) then
				bad("pads too close: " .. a.Id .. " and " .. b.Id)
			end
		end
		for j = 1, #rects do
			local b = rects[j]
			if b.R and not b.Walk and overlap(a.Pad, b.R) then
				bad("pad of " .. a.Id .. " overlaps " .. b.Id)
			end
		end
	end
	checkGardenLayout(bad)
	local reach = TycoonCatalog.ReachablePads(1, 1)
	for id, ok in pairs(reach) do
		if not ok then
			bad("pad of " .. id .. " cannot be reached from the gate")
		end
	end
	return #problems == 0, problems
end

return TycoonCatalog
