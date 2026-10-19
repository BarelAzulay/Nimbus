-- TycoonCatalog: every number of the tycoon homes (ARCHITECTURE_V3.md "Phase 4 build contract" 3.1-3.5, 3.7, 3.12,
-- 5.4 and the "Phase 5 build contract" 3.1, 3.3-3.5, 9.2): the 11 stations and their buy pads, prices (and the star
-- price rule), effects per level, house tiers, prestige, the Cloud Cash of the Pet Garden, berries, the Food Machine,
-- the Training Place, fusion costs, the pet XP curve, the one-time Phase 5 fold of old homes and where everything
-- stands on the 72 x 72 stud yard (+ the roaming layout HomeRoam builds its walk graph from).
-- Pure data + pure functions: no Instances, no services, no yields; safe on the server and the client.
-- Plain Lua 5.1-compatible syntax only.
--
-- PHASE 5 IN ONE PARAGRAPH: the home got simpler. ONE Berry Farm (id Press1, 40 levels, Kind "Farm": Effects.Food)
-- replaces the four plants; the Coin Magnet is merged into the Pet Garden (Effects.Radius / PileSeconds by Garden
-- level); three decor stations (Yard Fence, Fountain, Pet Podium) at 0.4x the Phase 4 price. Garden pets roam the yard
-- (shared/HomeRoam.lua builds its walk graph from RoamLayout()), eat at the Food Bowl and poop Cloud Cash worth
-- CoinValue x Coins.PoopMeals; every coin also grows Berries.Share berries into the Berry Basket (BasketCap). Feeding
-- at the Food Machine spends FeedBerries berries (no Cash). Station prices are the Phase 4 prices x1.25 (House and
-- decor not scaled). FoldLegacy(home, firstTime) turns a Phase 4 home into a Phase 5 one (DataService P5Home step).
--
-- BALANCE: the numbers come from tools/sim_tycoon.py (the home design's sim_p5.py model: 120 Monte Carlo players, 3
-- prestige runs each; `--ring 0.08 --dungeon 0.1` must print ALL TARGETS MET). Change a number here -> change the same
-- number in the constants block of tools/sim_tycoon.py (`--check`); tools/smoke_p4_economy.lua fails while they differ.
--
-- API (the contract):
--   Get(id) -> StationDef | nil (READ-ONLY; "Prestige" = the prestige pseudo-station), PriceFor(id, level), PriceAt(id,
--     level, home) = floor(PriceFor x StarPriceMultiplier), StarPriceMultiplier(home) = 1.5 ^ stars (1 with
--     LegacyPrices), AvailablePads(home) -> { pad... } (pad = { StationId, NextLevel, Price, BasePrice, Locked, Level,
--     MaxLevel, Name, Title, Kind, Icon, LevelText, Prestige }; a fresh home shows ONE pad, the free Pet Garden; the
--     Prestige pad once the Sky Castle is built), CheckPurchase(home, id) -> ok, price, reason,
--     StationsAfterPrestige(stations) (decor kept, the Garden at ResetLevel 1)
--   HomeLevelOf(home) = sum of station levels + (home.DecorCredit or 0) + LegacyMagnetLevel(home)
--   LegacyMagnetLevel(home) -> home.LegacyMagnet (1..5) while home.LegacyMagnetStar == home.Prestige, else 0
--   SignedPads(pads, cash, maxSigns) -> { [stationId] = true }   the pads that show a sign (3.3): the Prestige pad when
--     not Locked; then the maxSigns (SignRules.MaxSigns 3) cheapest not-Locked pads with Price <= cash; none affordable
--     -> the single cheapest not-Locked pad. Locked pads never get a sign.
--   FoldLegacy(home, firstTime) -> changed   (9.2 step 3; pure, mutates `home`): Press1-4 -> one Berry Farm (the food
--     floor on firstTime), Collector -> LegacyMagnet / LegacyMagnetStar, old decor -> Fence / Fountain + DecorCredit
--   Cloud Cash: FoodOf(home) (0 without a Garden, else Coins.GrassFood + the Farm's Food), PetPower(entry, level, tier,
--     stage) = RarityScale x PetCatalog.LevelFactor(level, stage) x TierMultiplier x RoleMult (stage = the STORED stage
--     cleaned by PetCatalog.EvolutionStage), GardenSlots(home), IncomePerSecond(home, entries, prestige) -> cash/s,
--     parts, LuckyChance, LuckyEV, CoinValue(home, power, prestige), ScoopRadius(home) = max(Garden Radius,
--     LegacyMagnet radius) (Coins.BaseRadius without a Garden), PileSeconds(home) = max(Garden PileSeconds, LegacyMagnet
--     pile) + Vault, OfflineEarnings(home, seconds, incomePerSecond)
--   Berries: BasketCap(home, incomePerSecond) = max(BasketMin, floor(ips x Share x 60 x BasketMinutes)),
--     FeedBerries(def, level) = round(XpToNext(level) x RarityScale x FeedBase) (= FeedPrice: 1 berry = the old $1)
--   Food Machine / training / XP: FeedXp(level, machineLevel), FeedPrice(def, level), TrainCost(def, rank),
--     TrainSeconds(rank), TrainingSlots(home), XpToNext(level), XpForLevel(level)
--   RoamLayout() -> { Half, Cell, Blocked = { {x0, z0, x1, z1, pad = n}... }, Beds = { {x, z}... }, Bowl = { X, Z, R },
--     EatRing, Welcome = {x, z}, Entrance = { X, Z, Width } }   plot-local; EVERY station footprint (built or not) +1,
--     every pad +0.5, the garden fence ring (entrance open), the bowl, the 12 beds: HomeRoam.Build() reads it
--   Validate() -> ok, { problem... }
-- Data: Stations (array in display order, also Stations.Press1) / ById / Order, Kinds, HouseTiers, Prestige, Coins,
--   Berries, SignRules, LegacyMagnet, LegacyPlants, FeedShare, FeedBase, Training, Fusion, PetXp, Layout.
--   Coins = { MealSeconds 8 (the income unit), GrassFood 12, LuckyMult 5, BaseRadius 6, BasePileSeconds 240,
--             PoopMeals 3 (one poop = 3 meals), DropsPerPet 3, DropStages {1, 2, 4, 8} (a drop's stage by poops) }
--   Berries = { Share 0.25, BasketMinutes 30, BasketMin 500, LegacyFood = { Snack 200, Meal 1200, Feast 6400 } }
--   StationDef = { Id, Name, Kind, Icon, Blurb, MaxLevel, Requires = { <stationId> = level, HomeLevel, House, Prestige },
--     LevelRequires = { [level] = { HomeLevel } }, TierCaps = { Cottage, Villa, Manor, SkyCastle }, Price, Effects,
--     Slot = { CFrame, Footprint, Pad, Walkable?, Perimeter?, Spots? (Training), Bowl / Beds / Fence / Entrance /
--     WelcomePile (Garden) }, KeepOnPrestige, ResetLevel, ComingSoon }
--   Effects by Kind: Farm { Food }, Garden { Lucky, Radius, PileSeconds }, FoodMachine { FeedShare }, Training
--     { Slots }, Vault { PileSeconds, OfflinePercent, OfflineHours }, House { Tier, TierIndex, Name }, Fusion
--     { TokenDiscount }, Arena { Battles }, Decor { Pieces, Style, ... build hints for HomeBuilder }
-- Slots (plot-local studs): origin = the yard centre on the ground (SpotInfo.PlotCFrame), -Z = the gate / street side,
--   +Z = the back fence. A station model goes at PlotCFrame * Slot.CFrame; its LookVector is its FRONT (pad side);
--   Footprint = (width along the front, height, depth). The Garden (station frame, -Z = its entrance / pad side):
--   Bowl = { Center (0, 0, 0), Radius 2.5 } (the Food Bowl), Beds = 12 bed centres (slot order, nearest the entrance
--   first), Fence = 0.6-stud ring on the footprint edge, Entrance = { Center (0, 0, -10), Width 4 }; WelcomePile =
--   PLOT-local (13.5, 0, 2.5), outside the fence beside the entrance.
-- Extras: HouseTierOf, HouseTier, MaxLevelAt, StationLevel, PrestigeMultiplier, PrestigeGems, CanPrestige, EffectsOf,
--   PadLevelText, FormatCash, ReachablePads, FootprintRect, PadRect, LocalRect, TierMultiplier, Icons, PrestigePad,
--   MaxPetLevel, StartCash, OfflineMinSeconds, PlotSize, Version (5).
--
-- Notes for the services: a Price of 0 is FREE (the Pet Garden). Prestige keeps the decor (KeepOnPrestige) and the
-- Garden at its ResetLevel, resets the rest (StationsAfterPrestige). Berries, training and roulettes never scale with
-- stars; station prices do (PriceAt).

local Shared = script.Parent
local Config = require(Shared.Config)

local TycoonCatalog = {}

local floor, max, min, huge = math.floor, math.max, math.min, math.huge

local PLOT = (type(Config.Lobby) == "table" and tonumber(Config.Lobby.PlotSize)) or 72
local HALF = PLOT / 2

TycoonCatalog.Version = 5 -- Phase 5: one Berry Farm, roaming pets, berries
TycoonCatalog.PlotSize = PLOT
TycoonCatalog.StartCash = 0 -- Cash of a brand-new profile; the Pet Garden is free
TycoonCatalog.OfflineMinSeconds = 120 -- shorter absences pay nothing (no rejoin farming)
TycoonCatalog.Kinds = { "Farm", "Garden", "FoodMachine", "Training", "Vault", "House", "Fusion", "Arena", "Decor" }
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
-- place (3 + stars, at most 12), a Gems reward and the Fusion Machine at 1 star. After every
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
	GardenSlotsBase = 3, -- garden places without a star ("at the start you can put up to 3 pets")
	GardenSlotsPerStar = 1, -- +1 place per star ("prestige 1 can put 4 and so on")
	GardenSlotsMax = 12, -- the places drawn in the garden (Garden.Slot.Spots)
	PriceStep = 0.5, -- station prices x(1 + PriceStep) ^ stars: x1.5, x2.25, x3.38 ...
	Icon = ICON.Star,
}

----------------------------------------------------------------------
-- Cloud Cash (Phase 4 3.2, Phase 5 3.5). Every open garden place with a pet eats one meal every MealSeconds (the income
-- unit: IncomePerSecond = Food / MealSeconds x Pets x LuckyEV x 1.25 ^ stars). A roaming pet poops one drop per
-- HomeRoam cycle worth CoinValue x PoopMeals (a Lucky drop x LuckyMult); a slot keeps at most DropsPerPet drops on the
-- lawn (more merge into the nearest); a drop's stage (CoinDrops attribute, HomeFx coin size) by its value in poops:
-- 1 (1), 2 (2-3), 3 (4-7), 4 (8+). The lawn of a slot holds PileSeconds(home) of its coins; the owner scoops drops
-- within ScoopRadius(home).
----------------------------------------------------------------------
TycoonCatalog.Coins = {
	MealSeconds = 8, -- the income unit: one meal per open place every 8 s
	GrassFood = 12, -- the Food of a built Garden before the Berry Farm
	LuckyMult = 5, -- a Lucky drop is worth 5 drops
	BaseRadius = 6, -- scoop radius (studs) without a Garden
	BasePileSeconds = 240, -- a slot's lawn holds 4 minutes of coins without a Garden
	PoopMeals = 3, -- one poop = 3 meals (HomeRoam.Cycle 24 s = 3 x MealSeconds)
	DropsPerPet = 3, -- drops of one slot on the lawn; a 4th poop merges into the nearest drop
	DropStages = { 1, 2, 4, 8 }, -- drop stage 1..4 from that many poops of value
}

----------------------------------------------------------------------
-- Berries (Phase 5 3.4): ONE food. Every Cloud Cash poop of value V adds V x Share berries to Profile.Berries (the
-- server ledger keeps the fraction), clamped so the poop never lifts the berries above BasketCap (30 minutes of
-- berries, at least BasketMin). A feed at the Food Machine costs FeedBerries(def, level) berries (= the Phase 4
-- FeedPrice in Cash: 1 berry = $1 of food). LegacyFood: the berries one leftover Phase 2-4 food is worth (the
-- DataService P5Home step converts Profile.Food once).
----------------------------------------------------------------------
TycoonCatalog.Berries = {
	Share = 0.25,
	BasketMinutes = 30,
	BasketMin = 500,
	LegacyFood = { Snack = 200, Meal = 1200, Feast = 6400 },
}

-- Pad signs (3.3): only the next affordable pads get a sign (SignedPads)
TycoonCatalog.SignRules = { MaxSigns = 3 }

----------------------------------------------------------------------
-- Pet XP curve: XpToNext(level) = round(Base * level ^ Exponent / Round) * Round, up to MaxLevel.
-- Pet stats grow +10% per level (PetCatalog.GetStats), so a level-50 pet earns 5.9x its level-1 coins and a level-100
-- pet 10.9x. Phase 4: every pet levels up to 100 (the player's rule); the evolutions stay at 20 and 50; each level
-- takes more XP than the one before (20 XP for L1 -> 2, 10,125 for L49 -> 50, 31,190 for L99 -> 100).
----------------------------------------------------------------------
TycoonCatalog.PetXp = { MaxLevel = 100, Base = 20, Exponent = 1.6, Round = 5 }
TycoonCatalog.MaxPetLevel = TycoonCatalog.PetXp.MaxLevel -- DataService.AddPetXp caps levels here

----------------------------------------------------------------------
-- The Food Machine (Phase 4 3.4, Phase 5 3.4): one feed fills FeedShare[machine level] of the pet's current XP bar (the
-- Kitchen's Effects.FeedShare, copied into TycoonCatalog.FeedShare below) and costs XpToNext(level) x RarityScale x
-- FeedBase BERRIES (FeedBerries), the same at every machine level (the upgrade gives more XP for the same berries).
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
-- nothing is placed outside |x|, |z| <= HALF - 1.5 except along-the-fence decor. (Phase 5: the Berry Farm fills the
-- four old press slots beside the PressLane path; the Coin Magnet corner and the old decor strips are lawn.)
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

-- The Pet Garden interior (Phase 5 3.3), in its station frame: X along the front, -Z = the entrance / pad side. The
-- Food Bowl in the middle, 12 beds (slot order = nearest the entrance first) along the sides and the back, a 0.6-stud
-- fence on the footprint edge with a 4-stud entrance at the front.
local GARDEN_BOWL = { Center = V3(0, 0, 0), Radius = 2.5 }
local GARDEN_BEDS = {
	V3(-9, 0, -6.5), V3(9, 0, -6.5), V3(-9, 0, -2.5), V3(9, 0, -2.5), V3(-9, 0, 1.5), V3(9, 0, 1.5),
	V3(-9, 0, 5.5), V3(9, 0, 5.5), V3(-6, 0, 7.8), V3(6, 0, 7.8), V3(-2, 0, 7.8), V3(2, 0, 7.8),
}
local GARDEN_BED_SIZE = 2.5 -- beds are 2.5 x 2.5 studs
local GARDEN_FENCE = 0.6 -- fence thickness on the footprint edge
local GARDEN_ENTRANCE = { Center = V3(0, 0, -10), Width = 4 }

-- The Berry Farm (Phase 5 3.3, home design 2.1): price TO level 1..40 and the Food of every level (piecewise geometric
-- through the old cumulative plant food at the tier-cap boundaries 10 / 22 / 37 / 40)
local FARM_PRICE = {
	15, 70, 160, 450, 520, 1400, 1500, 3100, 4400, 7500, 11000, 19000, 22000, 25000, 28000, 31000, 45000, 48000, 110000,
	120000, 150000, 160000, 200000, 220000, 320000, 340000, 360000, 380000, 460000, 510000, 610000, 790000, 850000,
	1000000, 1400000, 1500000, 1800000, 2200000, 2800000, 4000000,
}
local FARM_FOOD = {
	7, 9, 12, 15, 19, 25, 32, 41, 54, 69, 77, 90, 105, 122, 143, 166, 194, 227, 264, 309, 360, 420, 444, 483, 526, 573,
	624, 680, 740, 806, 878, 956, 1041, 1133, 1234, 1344, 1463, 1585, 1838, 2132,
}

-- The Phase 4 data the fold and the legacy magnet still need (READ-ONLY; no station uses it): the Food of the four old
-- plants by level (FoldLegacy's food floor) and the old Coin Magnet's scoop radius / pile seconds by level (a folded
-- Home.LegacyMagnet keeps them until the next Prestige).
TycoonCatalog.LegacyPlants = {
	Press1 = { 7, 9, 12, 16, 21, 27, 35, 45, 59, 76 },
	Press2 = { 19, 24, 32, 42, 53, 69, 91, 118, 153, 199 },
	Press3 = { 49, 63, 82, 107, 140, 180, 235, 302, 396, 518 },
	Press4 = { 127, 164, 215, 278, 360, 468, 612, 792, 1030, 1339 },
}
TycoonCatalog.LegacyMagnet = {
	MaxLevel = 5,
	Radius = { 9, 12, 16, 20, 26 },
	PileSeconds = { 300, 360, 420, 480, 600 },
}
-- old station ids FoldLegacy folds away (the decor ones by their new home)
local LEGACY_PLANTS = { "Press2", "Press3", "Press4" }
local LEGACY_DECOR = { DecorFence = { "DecorFlowers", "DecorBanners" }, DecorFountain = { "DecorLamps" } }

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

local function gardenEffects(lucky, radius, pile)
	local out = {}
	for i = 1, #lucky do
		out[i] = { Lucky = lucky[i], Radius = radius[i], PileSeconds = pile[i] }
	end
	return out
end

local STATIONS = {
	----------------------------------------------------------------- the Berry Farm (the four old plants in one)
	{
		Id = "Press1", Name = "Berry Farm", Kind = "Farm", Icon = ICON.Berry,
		Blurb = "Grows berries for your pets: bigger Cloud Cash.",
		MaxLevel = 40, TierCaps = caps(10, 22, 37, 40),
		Requires = { Garden = 1 },
		Price = FARM_PRICE,
		Effects = effectsOf("Food", FARM_FOOD),
		Slot = { CFrame = at(-26.5, 0.25, -90), Footprint = V3(36, 12, 7), Pad = padAt(-19, 0, -26.5, 0) },
	},
	----------------------------------------------------------------- pets at home
	{
		Id = "Garden", Name = "Pet Garden", Kind = "Garden", Icon = ICON.Seedling,
		Blurb = "Your pets eat at the Food Bowl, roam the yard and poop Cloud Cash.",
		MaxLevel = 8, TierCaps = caps(2, 4, 6, 8),
		Requires = {},
		ResetLevel = 1, -- Prestige keeps the Garden built (at this level): the coins never stop
		Price = { 0, 15000, 38000, 140000, 360000, 750000, 1500000, 3000000 },
		Effects = gardenEffects(
			{ 0, 0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.15 },
			{ 8, 10, 12, 14, 16, 19, 22, 26 },
			{ 300, 330, 360, 390, 420, 480, 540, 600 }
		),
		Slot = {
			CFrame = at(24, -1, 90), Footprint = V3(22, 4, 20), Pad = padAt(10, -1, 24, -1),
			Bowl = GARDEN_BOWL, -- the Food Bowl (station frame)
			Beds = GARDEN_BEDS, -- 12 beds (station frame), slot order
			BedSize = GARDEN_BED_SIZE,
			Fence = GARDEN_FENCE, -- fence thickness on the footprint edge
			Entrance = GARDEN_ENTRANCE, -- the gap in the fence (station frame)
			WelcomePile = V3(13.5, 0, 2.5), -- PLOT-local: the Welcome-back pile beside the entrance, off the pad
		},
	},
	{
		Id = "Kitchen", Name = "Food Machine", Kind = "FoodMachine", Icon = ICON.Stew,
		Blurb = "Feed berries to your pets for XP. Upgrades give bigger meals.",
		MaxLevel = 5, TierCaps = caps(1, 2, 4, 5),
		Requires = { Press1 = 1 },
		Price = { 300, 44000, 400000, 850000, 2400000 },
		Effects = effectsOf("FeedShare", { 0.25, 0.30, 0.35, 0.42, 0.50 }),
		-- the pad sits 1 stud nearer the gate than the contract's padAt(-19, 22.5): a 10-deep machine at z 29 starts
		-- at z 24, and the 4-stud pad at 22.5 would reach into it (Validate "pad overlaps")
		Slot = { CFrame = at(-24, 29, 0), Footprint = V3(16, 10, 10), Pad = padAt(-19, 21.5, -24, 29) },
	},
	{
		Id = "Gym", Name = "Training Place", Kind = "Training", Icon = ICON.Muscle,
		Blurb = "Train Attack Speed, Physique, Ability or Defense.",
		MaxLevel = 5, TierCaps = caps(1, 2, 4, 5),
		Requires = { Kitchen = 1 },
		Price = { 3800, 140000, 520000, 1200000, 2800000 },
		Effects = effectsOf("Slots", { 1, 2, 3, 4, 5 }),
		Slot = {
			CFrame = at(25, 24, 0), Footprint = V3(18, 10, 9), Pad = padAt(19.5, 14.5, 25, 24),
			Spots = { V3(-6, 0, 0), V3(-3, 0, 0), V3(0, 0, 0), V3(3, 0, 0), V3(6, 0, 0) },
		},
	},
	{
		Id = "Vault", Name = "Vault", Kind = "Vault", Icon = ICON.Bank,
		Blurb = "Your lawn holds more Cloud Cash, and coins while you are away.",
		MaxLevel = 5, TierCaps = caps(1, 2, 4, 5),
		Requires = { Press1 = 6 },
		Price = { 11000, 110000, 460000, 1000000, 2500000 },
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
		Requires = { Press1 = 2 },
		LevelRequires = { [2] = { HomeLevel = 10 }, [3] = { HomeLevel = 20 }, [4] = { HomeLevel = 30 } },
		Price = { 180, 24000, 200000, 880000 }, -- NOT scaled x1.25 (the Villa stays $24,000)
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
		Price = { 31000, 420000, 1800000 },
		Effects = { { TokenDiscount = 0 }, { TokenDiscount = 0.1 }, { TokenDiscount = 0.2 } },
		Slot = { CFrame = at(11, -25, 180), Footprint = V3(10, 12, 10), Pad = padAt(11, -16, 11, -25) },
	},
	{
		Id = "ArenaGate", Name = "Arena Gate", Kind = "Arena", Icon = ICON.Swords,
		Blurb = "Opens the way to pet battles.",
		MaxLevel = 1, TierCaps = caps(1, 1, 1, 1),
		Requires = { Gym = 1 },
		Price = { 320000 },
		Effects = { { Battles = true } },
		Slot = { CFrame = at(32, 14.5, 90), Footprint = V3(7, 12, 4), Pad = padAt(27, 14.5, 32, 14.5) },
	},
	----------------------------------------------------------------- decor (kept on prestige, +1 Home Level each)
	{
		Id = "DecorFence", Name = "Yard Fence", Kind = "Decor", Icon = ICON.Garden,
		Blurb = "A prettier fence with flowers and banners around your yard.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3), KeepOnPrestige = true,
		Requires = { Garden = 1 },
		Price = { 2800, 19000, 200000 },
		Effects = {
			{ Pieces = 1, Style = "Picket", Flowers = "Tulips" },
			{ Pieces = 2, Style = "Hedge", Banners = "Cloth" },
			{ Pieces = 3, Style = "Cloudstone", Banners = "Royal", Flowers = "Starflowers" },
		},
		Slot = { CFrame = at(0, 0, 0), Footprint = V3(PLOT, 4, PLOT), Perimeter = true, Pad = padAt(8, -10, 3, -10) },
	},
	{
		Id = "DecorFountain", Name = "Fountain", Kind = "Decor", Icon = ICON.Fountain,
		Blurb = "A splashing fountain with lanterns in the middle of the yard.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3), KeepOnPrestige = true,
		Requires = { Kitchen = 1 },
		Price = { 18000, 200000, 600000 },
		Effects = {
			{ Pieces = 1, Style = "Basin", Lanterns = 4, LanternStyle = "Wood" },
			{ Pieces = 2, Style = "Tiered", Lanterns = 6, LanternStyle = "Brass" },
			{ Pieces = 3, Style = "Sky", Lanterns = 8, LanternStyle = "Crystal" },
		},
		Slot = { CFrame = at(0, -1, 0), Footprint = V3(9, 8, 9), Pad = padAt(-7, -1, 0, -1) },
	},
	{
		Id = "DecorPodium", Name = "Pet Podium", Kind = "Decor", Icon = ICON.Trophy,
		Blurb = "Shows off your favourite pet by the gate.",
		MaxLevel = 3, TierCaps = caps(1, 2, 3, 3), KeepOnPrestige = true,
		Requires = { Garden = 1 },
		Price = { 3600, 38000, 230000 },
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

-- mirrors of PetCatalog's Phase 5 data (used only when PetCatalog cannot be loaded; the smoke test pins them equal)
local MIRROR = {
	LevelBonus = 0.1,
	EvolutionBonus = { [0] = 1, [1] = 1.5, [2] = 1.875 }, -- multiplies the LEVEL BONUS (PetCatalog.EvolutionBonus)
	RoleMult = { Economy = 1.6, Combat = 1 },
	EvolveTwice = { Epic = true, Legendary = true, Mythic = true, Secret = true },
	MaxLevel = 100,
}
TycoonCatalog.Mirror = MIRROR -- READ-ONLY (tests compare it with PetCatalog)

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

-- the STORED evolution stage that counts (0..MaxEvolution of the rarity); the level alone never evolves a pet
local function evolutionStage(def, level, stage)
	if stage == nil then
		return 0
	end
	local pc = getPetCatalog()
	if pc and type(pc.EvolutionStage) == "function" then
		local ok, s = pcall(pc.EvolutionStage, def, level, stage)
		if ok and finite(s) and s >= 0 then
			return floor(s)
		end
		return 0
	end
	local s = int(stage)
	if not s or s < 1 then
		return 0
	end
	return min(s, MIRROR.EvolveTwice[def.Rarity] and 2 or 1)
end

-- PetCatalog.LevelFactor(level, stage) = 1 + LevelBonus x (level - 1) x EvolutionBonus[stage] (or the mirror)
local function levelFactor(level, stage)
	local pc = getPetCatalog()
	if pc and type(pc.LevelFactor) == "function" then
		local ok, f = pcall(pc.LevelFactor, level, stage)
		if ok and finite(f) and f > 0 then
			return f
		end
	end
	local lv = max(1, min(int(level) or 1, MIRROR.MaxLevel))
	return 1 + MIRROR.LevelBonus * (lv - 1) * (MIRROR.EvolutionBonus[stage] or 1)
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

-- the old Coin Magnet level a folded home keeps until its next Prestige (0 once the stars moved on)
function TycoonCatalog.LegacyMagnetLevel(home)
	if type(home) ~= "table" then
		return 0
	end
	local lv = int(home.LegacyMagnet)
	if not lv or lv < 1 then
		return 0
	end
	if sanitizeStars(home.LegacyMagnetStar) ~= starsOf(home) or int(home.LegacyMagnetStar) == nil then
		return 0
	end
	return min(lv, TycoonCatalog.LegacyMagnet.MaxLevel)
end

local MAX_DECOR_CREDIT = 18 -- Home.DecorCredit 0..18 (the old decor levels that did not fit, 9.1)

local function decorCreditOf(home)
	local c = int(type(home) == "table" and home.DecorCredit or nil)
	if not c or c < 0 then
		return 0
	end
	return min(c, MAX_DECOR_CREDIT)
end

-- sum of every station level + the folded credits (DecorCredit, the legacy magnet while its star holds)
function TycoonCatalog.HomeLevelOf(home)
	local total = 0
	for _, def in ipairs(STATIONS) do
		total = total + levelOf(home, def.Id)
	end
	return total + decorCreditOf(home) + TycoonCatalog.LegacyMagnetLevel(home)
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
-- Cloud Cash: food, pet power, garden places, income, piles, scoop radius, offline earnings
----------------------------------------------------------------------
-- the Food of every meal: 0 without a Garden, else GrassFood + the Berry Farm's Effects.Food
function TycoonCatalog.FoodOf(home)
	if levelOf(home, "Garden") < 1 then
		return 0
	end
	local total = TycoonCatalog.Coins.GrassFood
	for _, def in ipairs(STATIONS) do
		if def.Kind == "Farm" then
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
	local power = scale * levelFactor(lv, evolutionStage(def, lv, stage)) * tierMultiplier(mult) * roleMultiplier(def)
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

-- the old Coin Magnet's effect of a folded home (nil without one / after the next Prestige)
local function legacyMagnetEffect(home, key)
	local lv = TycoonCatalog.LegacyMagnetLevel(home)
	if lv < 1 then
		return nil
	end
	return TycoonCatalog.LegacyMagnet[key][lv]
end

-- max(Garden Radius, LegacyMagnet radius); Coins.BaseRadius without a Garden
function TycoonCatalog.ScoopRadius(home)
	local lv = levelOf(home, "Garden")
	local r = TycoonCatalog.Coins.BaseRadius
	if lv >= 1 then
		r = BY_ID.Garden.Effects[lv].Radius
	end
	local legacy = legacyMagnetEffect(home, "Radius")
	if legacy and legacy > r then
		r = legacy
	end
	return r
end

-- max(Garden PileSeconds, LegacyMagnet pile) + Vault PileSeconds: a slot's lawn holds this many seconds of its coins
function TycoonCatalog.PileSeconds(home)
	local lv = levelOf(home, "Garden")
	local s = TycoonCatalog.Coins.BasePileSeconds
	if lv >= 1 then
		s = BY_ID.Garden.Effects[lv].PileSeconds
	end
	local legacy = legacyMagnetEffect(home, "PileSeconds")
	if legacy and legacy > s then
		s = legacy
	end
	local vault = levelOf(home, "Vault")
	if vault >= 1 then
		s = s + (BY_ID.Vault.Effects[vault].PileSeconds or 0)
	end
	return s
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

----------------------------------------------------------------------
-- Berries (Phase 5 3.4)
----------------------------------------------------------------------
-- the Berry Basket: max(BasketMin, floor(incomePerSecond x Share x 60 x BasketMinutes)) whole berries (30 minutes of
-- the berries the garden grows); junk income counts as 0. `home` is accepted for symmetry (the cap needs no station).
function TycoonCatalog.BasketCap(home, incomePerSecond)
	local B = TycoonCatalog.Berries
	local ips = tonumber(incomePerSecond)
	if not finite(ips) or ips < 0 then
		ips = 0
	end
	local cap = floor(ips * B.Share * 60 * B.BasketMinutes + 1e-9)
	if not finite(cap) or cap > 1e15 then
		cap = 1e15
	end
	return max(B.BasketMin, cap)
end

-- berries of one Food Machine feed for a pet (def / rarity / pet id / key) at `level`: round(XpToNext(level) x
-- RarityScale x FeedBase), the Phase 4 FeedPrice; nil at the top level or for junk
function TycoonCatalog.FeedBerries(def, level)
	return TycoonCatalog.FeedPrice(def, level)
end

----------------------------------------------------------------------
-- Pad signs (Phase 5 3.3): SignedPads(pads, cash, maxSigns) -> { [stationId] = true }
----------------------------------------------------------------------
function TycoonCatalog.SignedPads(pads, cash, maxSigns)
	local out = {}
	if type(pads) ~= "table" then
		return out
	end
	local money = tonumber(cash)
	if not finite(money) then
		money = 0
	end
	local limit = int(maxSigns) or TycoonCatalog.SignRules.MaxSigns
	if limit < 0 then
		limit = 0
	end
	-- open (not Locked) station pads in pad order; the cheapest first, ties by pad order (deterministic)
	local open = {}
	for i, pad in ipairs(pads) do
		if type(pad) == "table" and type(pad.StationId) == "string" and not pad.Locked then
			if pad.Prestige or pad.StationId == PRESTIGE_PAD.Id then
				out[pad.StationId] = true
			else
				local price = tonumber(pad.Price)
				if finite(price) then
					open[#open + 1] = { Id = pad.StationId, Price = price, Index = i }
				end
			end
		end
	end
	table.sort(open, function(a, b)
		if a.Price ~= b.Price then
			return a.Price < b.Price
		end
		return a.Index < b.Index
	end)
	local signed = 0
	for _, item in ipairs(open) do
		if signed >= limit then
			break
		end
		if item.Price <= money then
			out[item.Id] = true
			signed = signed + 1
		end
	end
	if signed == 0 and open[1] then
		out[open[1].Id] = true
	end
	return out
end

----------------------------------------------------------------------
-- The one-time Phase 5 fold (9.2 step 3): FoldLegacy(home, firstTime) -> changed (pure; mutates `home`)
----------------------------------------------------------------------
-- a station level as a whole number in 0..top (junk -> 0)
local function clampLevel(v, top)
	local n = int(v)
	if not n or n < 0 then
		return 0
	end
	return min(n, top)
end

-- the food the four Phase 4 plants gave at these levels (FoldLegacy's food floor)
local function legacyPlantFood(levels)
	local total = 0
	for _, id in ipairs({ "Press1", "Press2", "Press3", "Press4" }) do
		local lv = levels[id] or 0
		local table_ = TycoonCatalog.LegacyPlants[id]
		if lv >= 1 and table_[lv] then
			total = total + table_[lv]
		end
	end
	return total
end

-- the smallest Berry Farm level whose Food reaches `food` (MaxLevel when none does)
local function farmLevelForFood(food)
	local def = BY_ID.Press1
	for lv = 1, def.MaxLevel do
		if (def.Effects[lv].Food or 0) >= food then
			return lv
		end
	end
	return def.MaxLevel
end

local function present(v)
	return v ~= nil and v ~= false
end

-- (a) Farm: sum = Press1..Press4 (Press2-4 clamped 0..10; Press1 0..10 on the first fold, 0..40 after it: a folded
-- farm keeps its level when a Phase 4 server sold a Carrot Patch meanwhile); if any of Press2-4 is present or
-- firstTime: Press1 = min(40, max(sum, the smallest L whose Food >= the old plant food (firstTime only))), Press2-4
-- removed. (b) Magnet: Collector > 0 -> LegacyMagnet = max(the live LegacyMagnet, Collector) clamped 1..5,
-- LegacyMagnetStar = Prestige; Collector removed. (c) Decor: Fence = max(Fence, Flowers, Banners), Fountain =
-- max(Fountain, Lamps), DecorCredit += the levels that did not fit (at most 18), the three keys removed. Returns true
-- when the home changed. No Cash, Gems or berries (the Food -> berries step is DataService's).
function TycoonCatalog.FoldLegacy(home, firstTime)
	if type(home) ~= "table" then
		return false
	end
	local st = home.Stations
	if type(st) ~= "table" then
		return false
	end
	local changed = false
	local legacyTop = 10
	local farmDef = BY_ID.Press1
	-- (a) the Berry Farm
	local anyOld = false
	for _, id in ipairs(LEGACY_PLANTS) do
		if present(st[id]) then
			anyOld = true
		end
	end
	if anyOld or firstTime then
		local levels = { Press1 = clampLevel(st.Press1, firstTime and legacyTop or farmDef.MaxLevel) }
		local sum = levels.Press1
		for _, id in ipairs(LEGACY_PLANTS) do
			levels[id] = clampLevel(st[id], legacyTop)
			sum = sum + levels[id]
			if st[id] ~= nil then
				st[id] = nil
				changed = true
			end
		end
		local level = sum
		if firstTime then
			local food = legacyPlantFood(levels)
			if food > 0 then
				level = max(level, farmLevelForFood(food))
			end
		end
		level = min(farmDef.MaxLevel, level)
		local old = st.Press1
		if level > 0 then
			if old ~= level then
				st.Press1 = level
				changed = true
			end
		elseif old ~= nil and int(old) ~= nil and int(old) <= 0 then
			st.Press1 = nil
			changed = true
		end
	end
	-- (b) the Coin Magnet -> the legacy magnet (counts + keeps its radius until the next Prestige)
	if st.Collector ~= nil then
		local lv = clampLevel(st.Collector, TycoonCatalog.LegacyMagnet.MaxLevel)
		st.Collector = nil
		changed = true
		if lv > 0 then
			local live = TycoonCatalog.LegacyMagnetLevel(home)
			home.LegacyMagnet = max(live, lv)
			home.LegacyMagnetStar = starsOf(home)
		end
	end
	-- (c) the old decor -> the Yard Fence / the Fountain + DecorCredit
	local credit = decorCreditOf(home)
	local creditBefore = credit
	for _, pair in ipairs({ { "DecorFence", LEGACY_DECOR.DecorFence }, { "DecorFountain", LEGACY_DECOR.DecorFountain } }) do
		local target, sources = pair[1], pair[2]
		local any = false
		for _, id in ipairs(sources) do
			if st[id] ~= nil then
				any = true
			end
		end
		if any then
			local top = BY_ID[target].MaxLevel
			local best = clampLevel(st[target], top)
			local total = best
			for _, id in ipairs(sources) do
				local lv = clampLevel(st[id], 3)
				total = total + lv
				if lv > best then
					best = lv
				end
				st[id] = nil
			end
			changed = true
			credit = credit + (total - best)
			if best > 0 then
				st[target] = best
			end
		end
	end
	if credit ~= creditBefore then
		home.DecorCredit = min(credit, MAX_DECOR_CREDIT)
	end
	return changed
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

----------------------------------------------------------------------
-- The roaming layout (Phase 5 3.5): what HomeRoam builds its walk graph from (plot-local rects; pure, a fresh table)
----------------------------------------------------------------------
TycoonCatalog.Roam = {
	Half = 33, -- the walkable square |x|, |z| <= Half
	Cell = 2, -- studs per grid cell
	StationPad = 1, -- clearance around every station footprint
	PadPad = 0.5, -- clearance around every buy pad
	FencePad = 0.6, -- clearance around the garden fence and the bowl
	BedPad = 0.3, -- clearance around the beds
	EatRing = 5, -- the eat points: the bowl centre + EatRing studs at (slot - 1) x 30 degrees
}

local function rectOf(r, pad)
	return { r[1], r[3], r[2], r[4], pad = pad } -- {x0, x1, z0, z1} -> {x0, z0, x1, z1}
end

function TycoonCatalog.RoamLayout()
	local R = TycoonCatalog.Roam
	local blocked = {}
	-- every station footprint, built or not (the graph never depends on what is built); walk-through decor and the
	-- yard fence decor (Perimeter) are not obstacles; the Garden is its fence + bowl + beds below
	for _, def in ipairs(STATIONS) do
		local slot = def.Slot
		if def.Id ~= "Garden" and not walkThrough(slot) then
			blocked[#blocked + 1] = rectOf(footprintRect(slot.CFrame, slot.Footprint), R.StationPad)
		end
	end
	-- every buy pad (the Prestige pad too)
	for _, def in ipairs(STATIONS) do
		blocked[#blocked + 1] = rectOf(padRect(def.Slot.Pad), R.PadPad)
	end
	blocked[#blocked + 1] = rectOf(padRect(PRESTIGE_PAD.Slot.Pad), R.PadPad)
	-- the garden fence: four sides on the footprint edge, the entrance side split around the gap
	local g = BY_ID.Garden.Slot
	local fp = g.Footprint
	local hx, hz, t = fp.X / 2, fp.Z / 2, g.Fence
	local e = g.Entrance
	local function localRectOf(cx, cz, sx, sz, pad)
		blocked[#blocked + 1] = rectOf(localRect(g.CFrame, V3(cx, 0, cz), V3(sx, 0, sz)), pad)
	end
	localRectOf(0, hz - t / 2, fp.X, t, R.FencePad) -- back
	localRectOf(-hx + t / 2, 0, t, fp.Z, R.FencePad) -- left side
	localRectOf(hx - t / 2, 0, t, fp.Z, R.FencePad) -- right side
	local gap0, gap1 = e.Center.X - e.Width / 2, e.Center.X + e.Width / 2
	localRectOf((-hx + gap0) / 2, -hz + t / 2, gap0 + hx, t, R.FencePad) -- front, left of the entrance
	localRectOf((gap1 + hx) / 2, -hz + t / 2, hx - gap1, t, R.FencePad) -- front, right of the entrance
	-- the Food Bowl and the beds
	local b = g.Bowl
	localRectOf(b.Center.X, b.Center.Z, 2 * b.Radius, 2 * b.Radius, R.FencePad)
	local beds = {}
	for i, v in ipairs(g.Beds) do
		localRectOf(v.X, v.Z, g.BedSize, g.BedSize, R.BedPad)
		local w = g.CFrame * v
		beds[i] = { w.X, w.Z }
	end
	local bowl = g.CFrame * b.Center
	local entrance = g.CFrame * e.Center
	local wp = g.WelcomePile
	return {
		Half = R.Half,
		Cell = R.Cell,
		EatRing = R.EatRing,
		Blocked = blocked,
		Beds = beds,
		Bowl = { X = bowl.X, Z = bowl.Z, R = b.Radius },
		Welcome = { wp.X, wp.Z },
		Entrance = { X = entrance.X, Z = entrance.Z, Width = e.Width },
	}
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
	if kind == "Farm" then
		local food = effectValues(def, "Food")
		if not food or food[1] <= 0 or not rising(food, true) then
			bad(id .. ": Effects.Food must be positive and rising")
		end
	elseif kind == "Garden" then
		local lucky = effectValues(def, "Lucky")
		if not lucky or lucky[1] < 0 or lucky[#lucky] > 0.5 or not rising(lucky, false) then
			bad(id .. ": Effects.Lucky must be a chance in 0..0.5 that never drops")
		end
		local beds = def.Slot and def.Slot.Beds
		if type(beds) ~= "table" or #beds ~= TycoonCatalog.Prestige.GardenSlotsMax then
			bad(id .. ": needs " .. TycoonCatalog.Prestige.GardenSlotsMax .. " Beds (Prestige.GardenSlotsMax)")
		end
		local reset = def.ResetLevel
		if reset ~= nil and (int(reset) ~= reset or reset < 1 or reset > def.MaxLevel) then
			bad(id .. ": ResetLevel must be a level of the station")
		end
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

-- the roaming graph check (a light copy of HomeRoam.Build: the same grid and obstacles, 4-neighbours): the number of
-- walkable nodes and whether every bed and every eat point has a reachable node next to it
local function roamReach(layout)
	local half, cell = layout.Half, layout.Cell
	local n = floor(2 * half / cell) + 1
	local free = {}
	local count = 0
	local function pos(i)
		return -half + (i - 1) * cell
	end
	for i = 1, n do
		for j = 1, n do
			local x, z = pos(i), pos(j)
			local ok = z > -half + 2
			if ok then
				for _, r in ipairs(layout.Blocked) do
					local pad = r.pad or 0
					if x >= r[1] - pad and x <= r[3] + pad and z >= r[2] - pad and z <= r[4] + pad then
						ok = false
						break
					end
				end
			end
			if ok then
				free[(i - 1) * n + j] = true
				count = count + 1
			end
		end
	end
	local function nearest(x, z)
		local best, bd = nil, huge
		for key in pairs(free) do
			local i = floor((key - 1) / n) + 1
			local j = key - (i - 1) * n
			local d = (pos(i) - x) ^ 2 + (pos(j) - z) ^ 2
			if d < bd or (d == bd and key < best) then
				best, bd = key, d
			end
		end
		return best, bd
	end
	local b = layout.Bowl
	local eat = {}
	for slot = 1, 12 do
		local a = math.rad((slot - 1) * 30)
		eat[slot] = { b.X + math.cos(a) * layout.EatRing, b.Z + math.sin(a) * layout.EatRing }
	end
	local start = nearest(eat[1][1], eat[1][2])
	local seen = {}
	if start then
		seen[start] = true
		local queue, head = { start }, 1
		while head <= #queue do
			local key = queue[head]
			head = head + 1
			local i = floor((key - 1) / n) + 1
			local j = key - (i - 1) * n
			for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local a, c = i + d[1], j + d[2]
				if a >= 1 and a <= n and c >= 1 and c <= n then
					local k2 = (a - 1) * n + c
					if free[k2] and not seen[k2] then
						seen[k2] = true
						queue[#queue + 1] = k2
					end
				end
			end
		end
	end
	local problems = {}
	local function reached(what, x, z, within)
		local key, d2 = nearest(x, z)
		if not key or not seen[key] or d2 > within * within then
			problems[#problems + 1] = what
		end
	end
	for slot, p in ipairs(eat) do
		reached("eat point " .. slot, p[1], p[2], 2.5)
	end
	for slot, p in ipairs(layout.Beds) do
		reached("bed " .. slot, p[1], p[2], 4)
	end
	return count, problems
end

-- the garden of Phase 5 3.3: bowl, 12 beds, fence + entrance, the Welcome-back pile, the roaming graph
local function checkGardenLayout(bad)
	local garden = BY_ID.Garden
	local slot = garden and garden.Slot
	if type(slot) ~= "table" or typeof(slot.CFrame) ~= "CFrame" or typeof(slot.Footprint) ~= "Vector3" then
		bad("Garden: no slot")
		return
	end
	local fp = slot.Footprint
	local fr = footprintRect(slot.CFrame, fp)
	local bowl = slot.Bowl
	local e = slot.Entrance
	if type(bowl) ~= "table" or typeof(bowl.Center) ~= "Vector3" or not finite(bowl.Radius) then
		bad("Garden: Slot.Bowl needs Center and Radius")
		return
	end
	if type(e) ~= "table" or typeof(e.Center) ~= "Vector3" or not finite(e.Width) then
		bad("Garden: Slot.Entrance needs Center and Width")
		return
	end
	if math.abs(math.abs(e.Center.Z) - fp.Z / 2) > 1e-6 or math.abs(e.Center.X) + e.Width / 2 > fp.X / 2 then
		bad("Garden: the entrance must sit on the front fence")
	end
	if not finite(slot.Fence) or slot.Fence <= 0 or slot.Fence > 1 then
		bad("Garden: Slot.Fence must be a thin ring (0..1 stud)")
	end
	local beds = slot.Beds or {}
	local half = (slot.BedSize or 2.5) / 2
	for i, v in ipairs(beds) do
		if math.abs(v.X) + half > fp.X / 2 - (slot.Fence or 0) or math.abs(v.Z) + half > fp.Z / 2 - (slot.Fence or 0) then
			bad("Garden: bed " .. i .. " leaves the footprint")
		end
		local dx, dz = v.X - bowl.Center.X, v.Z - bowl.Center.Z
		if math.sqrt(dx * dx + dz * dz) < bowl.Radius + 1.5 then
			bad("Garden: bed " .. i .. " is too close to the Food Bowl")
		end
		if math.abs(v.X - e.Center.X) < e.Width / 2 + half and math.abs(v.Z - e.Center.Z) < 3 then
			bad("Garden: bed " .. i .. " blocks the entrance")
		end
		for j = 1, i - 1 do
			if (beds[j] - v).Magnitude < 3 then
				bad("Garden: beds " .. j .. " and " .. i .. " are closer than 3 studs")
			end
		end
	end
	-- the Welcome-back pile: plot-local, inside the yard, outside the garden fence, off every pad and station
	local wp = slot.WelcomePile
	if typeof(wp) ~= "Vector3" then
		bad("Garden: Slot.WelcomePile is missing")
	else
		if math.abs(wp.X) > HALF - 1 or math.abs(wp.Z) > HALF - 1 then
			bad("Garden: the Welcome-back pile leaves the yard")
		end
		if inside(fr, wp.X, wp.Z) then
			bad("Garden: the Welcome-back pile lies inside the garden fence")
		end
		local pads = {}
		for _, def in ipairs(STATIONS) do
			pads[#pads + 1] = { def.Id, padRect(def.Slot.Pad) }
		end
		pads[#pads + 1] = { "Prestige", padRect(PRESTIGE_PAD.Slot.Pad) }
		for _, p in ipairs(pads) do
			if inside(p[2], wp.X, wp.Z, 0.25) then
				bad("Garden: the Welcome-back pile lies on the " .. p[1] .. " pad")
			end
		end
		for _, def in ipairs(STATIONS) do
			if def ~= garden and not walkThrough(def.Slot) and inside(footprintRect(def.Slot.CFrame, def.Slot.Footprint), wp.X, wp.Z) then
				bad("Garden: the Welcome-back pile lies inside " .. def.Id)
			end
		end
	end
	-- the roaming graph: >= 300 walkable nodes, every bed and eat point reachable
	local count, problems = roamReach(TycoonCatalog.RoamLayout())
	if count < 300 then
		bad("RoamLayout: only " .. count .. " walkable nodes (needs >= 300)")
	end
	for _, what in ipairs(problems) do
		bad("RoamLayout: " .. what .. " cannot be reached")
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
		"Press1", "Garden", "Kitchen", "Gym", "Vault", "House", "FusionMachine", "ArenaGate",
		"DecorFence", "DecorFountain", "DecorPodium",
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
	local ds = C.DropStages
	if type(ds) ~= "table" or #ds ~= 4 or ds[1] ~= 1 or not rising(ds, true) then
		bad("Coins.DropStages must be 4 rising poop counts starting at 1")
	end
	for _, k in ipairs({ "PoopMeals", "DropsPerPet" }) do
		if int(C[k]) ~= C[k] or C[k] < 1 then
			bad("Coins." .. k .. " must be a whole number >= 1")
		end
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

	-- berries (one food) and the pad signs
	local B = TycoonCatalog.Berries
	if type(B) ~= "table" or not finite(B.Share) or B.Share <= 0 or B.Share > 1 or not finite(B.BasketMinutes)
		or B.BasketMinutes <= 0 or int(B.BasketMin) ~= B.BasketMin or B.BasketMin < 1 then
		bad("Berries needs Share in 0..1, positive BasketMinutes and a whole BasketMin >= 1")
	else
		for _, id in ipairs({ "Snack", "Meal", "Feast" }) do
			local v = type(B.LegacyFood) == "table" and B.LegacyFood[id]
			if int(v) ~= v or v < 1 then
				bad("Berries.LegacyFood." .. id .. " must be a whole number of berries")
			end
		end
	end
	if int(TycoonCatalog.SignRules.MaxSigns) ~= TycoonCatalog.SignRules.MaxSigns or TycoonCatalog.SignRules.MaxSigns < 1 then
		bad("SignRules.MaxSigns must be a whole number >= 1")
	end
	for id, food in pairs(TycoonCatalog.LegacyPlants) do
		if #food ~= 10 or not rising(food, true) then
			bad("LegacyPlants." .. id .. " must be the 10 rising Phase 4 food values")
		end
	end
	local lm = TycoonCatalog.LegacyMagnet
	if #lm.Radius ~= lm.MaxLevel or #lm.PileSeconds ~= lm.MaxLevel then
		bad("LegacyMagnet needs a Radius and a PileSeconds per level")
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
