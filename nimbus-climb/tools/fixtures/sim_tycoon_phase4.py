#!/usr/bin/env python3
"""Nimbus Climb: tycoon economy simulation (ARCHITECTURE_V3.md "Phase 4 build contract" sections 3.1-3.7 and 3.12).

Phase 4: pets make the money. Pets in the Pet Garden eat a meal every MealSeconds and pop out rainbow coins worth
Food(home) x PetPower(pet) x 1.25 ^ stars; the four plants (the old presses) raise the Food, the Coin Magnet (the old
Collector) and the Vault make piles bigger, the Food Machine (the old Kitchen) turns Cash into XP, pets EVOLVE at
level 20 (x1.25) and 50 (Epic and rarer, x1.5) and grow to level 100. This file is the port of the design prototype
`scratchpad/p4design/synth/sim_synth.py` onto the real catalog numbers (the constants block below).

HOW TO RUN (from the repo root; Python 3.8+, no packages needed for the simulation itself)
    python3 tools/sim_tycoon.py                  timeline of one typical player + Monte Carlo + target check
    python3 tools/sim_tycoon.py --quiet          summary only (no purchase-by-purchase timeline)
    python3 tools/sim_tycoon.py --seed 7         another typical player (different roulette luck)
    python3 tools/sim_tycoon.py --runs 6         follow 6 prestiges in the timeline
    python3 tools/sim_tycoon.py --mode combat    the timeline player only ever gets Combat pets (they earn 1/1.6)
    python3 tools/sim_tycoon.py --mc 400         Monte Carlo size (default 120 players, 3 prestige runs each)
    python3 tools/sim_tycoon.py --ring 0.08      a kid who climbs the Champion Ring regularly (+8% Cash)
    python3 tools/sim_tycoon.py --feed 0.5       the share of the coins the kid spends at the Food Machine (0.25)
    python3 tools/sim_tycoon.py --check          compare the constants below with src/shared/TycoonCatalog.lua
                                                 (effect tables, AvailablePads incl. PriceAt with stars, income,
                                                 feeding, training) and run its Validate() (needs `pip install lupa`)
    python3 tools/sim_tycoon.py --migrate        300 Phase 3 homes (tools/fixtures/sim_tycoon_phase3.py, frozen)
                                                 on their first Phase 4 login: Home Level, dead ends, coin and
                                                 pad-time ratios by house tier and stars
    python3 tools/sim_tycoon.py --plan plan.png  draw the yard layout of TycoonCatalog.lua from above (lupa + Pillow)
Exit status 1 when a target is missed (or --check / --migrate finds a problem).

WHAT IT SIMULATES (one second per step)
  * An ACTIVE player claims a home at t = 0 with 0 Cash, scoops the coin piles every SCOOP_EVERY seconds and spends
    BUY_OVERHEAD seconds walking to each pad.
  * Buying: the best-value pad (coins gained per Cash; a pad without coins counts as a small share of the current
    income, a new house as HOUSE_WEIGHT of it, the first Food Machine as FOOD_MACHINE_WEIGHT) among the pads it
    could afford within PATIENCE seconds, saving for it while buying any affordable pad that costs at most FILLER of
    that target. While the next house waits for Home Level (or the Sky Castle for Home Level 40) every level gets a
    bonus. Prices are x(1 + PRESTIGE_PRICE_STEP) ^ stars.
  * Pets: roulette rolls on a schedule (ROLLS), each with the real odds of Config.Roulettes and the real share of
    Economy / Combat pets per rarity; the best pets (by PetPower) fill the open garden places (3 + stars, at most 12).
  * Feeding: the kid spends FEED_INCOME_SHARE of the coins at the Food Machine (one feed = FEED_SHARE of the bar for
    XpToNext x RarityScale x FEED_BASE Cash), the pet closest to an evolution first; it presses EVOLVE at once.
  * Prestige as soon as the Sky Castle stands and the Home Level is 40: stations reset except the decor and the
    Garden (back to level 1), Cash and the coins on the lawn reset, pets keep their levels and evolutions, +1 star
    (coins x1.25, +1 garden place, Gems).

THE CONSTANTS BLOCK below must equal src/shared/TycoonCatalog.lua (and the pet data of PetCatalog / Config):
tools/smoke_p4_economy.lua (smoke scenario p2_economy) reads the block and fails on any difference, and `--check`
does the same from Python. Tune here, run the sim, then copy the numbers into the catalog (or the other way round).
"""
import argparse
import importlib
import importlib.util
import math
import os
import random
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# ==== BEGIN SIM CONSTANTS ====
# Read by tools/smoke_p4_economy.lua: exactly one `NAME = value` per line, value = a number, a list of numbers or a
# "string"; '#' starts a comment. Station constants are named <KIND>_<StationId>.
# PRICE_<id>: BASE Cash to build / upgrade TO level 1, 2, ...   CAPS_<id>: max level at Cottage, Villa, Manor, Sky Castle
# REQ_<id>: "<stationId>=level ... House=<tier> Prestige=n" (station keys hide the pad until built)
PRICE_Press1 = [15, 55, 130, 360, 1200, 3500, 9000, 20000, 100000, 270000]
PRICE_Press2 = [420, 1100, 2500, 6000, 15000, 22000, 38000, 120000, 260000, 680000]
PRICE_Press3 = [18000, 25000, 36000, 88000, 130000, 180000, 290000, 410000, 1100000, 1800000]
PRICE_Press4 = [160000, 300000, 370000, 490000, 630000, 820000, 1100000, 1400000, 2200000, 3200000]
PRICE_Collector = [90, 6000, 45000, 410000, 1400000]
PRICE_Garden = [0, 12000, 30000, 110000, 290000, 600000, 1200000, 2400000]
PRICE_Kitchen = [240, 35000, 320000, 680000, 1900000]
PRICE_Gym = [3000, 110000, 420000, 920000, 2200000]
PRICE_Vault = [9000, 85000, 370000, 820000, 2000000]
PRICE_House = [180, 24000, 200000, 880000]
PRICE_FusionMachine = [25000, 340000, 1400000]
PRICE_ArenaGate = [260000]
PRICE_DecorLamps = [1800, 27000, 360000]
PRICE_DecorFence = [7000, 48000, 490000]
PRICE_DecorFlowers = [2700, 36000, 410000]
PRICE_DecorFountain = [45000, 490000, 1500000]
PRICE_DecorBanners = [12000, 110000, 650000]
PRICE_DecorPodium = [9000, 95000, 580000]
CAPS_Press1 = [6, 8, 9, 10]
CAPS_Press2 = [6, 8, 9, 10]
CAPS_Press3 = [0, 6, 8, 10]
CAPS_Press4 = [0, 0, 8, 10]
CAPS_Collector = [2, 3, 4, 5]
CAPS_Garden = [2, 4, 6, 8]
CAPS_Kitchen = [1, 2, 4, 5]
CAPS_Gym = [1, 2, 4, 5]
CAPS_Vault = [1, 2, 4, 5]
CAPS_House = [4, 4, 4, 4]
CAPS_FusionMachine = [1, 2, 3, 3]
CAPS_ArenaGate = [1, 1, 1, 1]
CAPS_DecorLamps = [1, 2, 3, 3]
CAPS_DecorFence = [1, 2, 3, 3]
CAPS_DecorFlowers = [1, 2, 3, 3]
CAPS_DecorFountain = [0, 1, 2, 3]
CAPS_DecorBanners = [1, 2, 3, 3]
CAPS_DecorPodium = [1, 2, 3, 3]
REQ_Press1 = "Garden=1"
REQ_Press2 = "Press1=2"
REQ_Press3 = "Press2=3 House=Villa"
REQ_Press4 = "Press3=3 House=Manor"
REQ_Collector = "Press1=1"
REQ_Garden = ""  # the root: a fresh home shows only the free Pet Garden
REQ_Kitchen = "Press1=1"
REQ_Gym = "Kitchen=1"
REQ_Vault = "Press2=2"
REQ_House = "Collector=1"
REQ_FusionMachine = "Kitchen=1 Prestige=1"
REQ_ArenaGate = "Gym=1"
REQ_DecorLamps = "Collector=1"
REQ_DecorFence = "Press2=2"
REQ_DecorFlowers = "Garden=1"
REQ_DecorFountain = "Kitchen=1 House=Villa"
REQ_DecorBanners = "Vault=1"
REQ_DecorPodium = "Garden=1"
KEEP_ON_PRESTIGE = "DecorLamps DecorFence DecorFlowers DecorFountain DecorBanners DecorPodium"
RESET_LEVEL = "Garden=1"  # stations a Prestige sets to this level instead of 0 (the Garden: the coins never stop)
COMING_SOON = ""  # none since Phase 3
# effects (by station level)
PLANT_FOOD_Press1 = [7, 9, 12, 16, 21, 27, 35, 45, 59, 76]  # Berry Bush Effects.Food
PLANT_FOOD_Press2 = [19, 24, 32, 42, 53, 69, 91, 118, 153, 199]  # Carrot Patch
PLANT_FOOD_Press3 = [49, 63, 82, 107, 140, 180, 235, 302, 396, 518]  # Cloud Melons
PLANT_FOOD_Press4 = [127, 164, 215, 278, 360, 468, 612, 792, 1030, 1339]  # Starfruit Tree
GARDEN_LUCKY = [0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.12, 0.15]  # chance a coin is Lucky (x LuckyMult)
MAGNET_RADIUS = [9, 12, 16, 20, 26]  # Coin Magnet (Collector) scoop radius, studs
MAGNET_PILE_SECONDS = [300, 360, 420, 480, 600]  # Coin Magnet pile size, seconds of coins
FEED_SHARE = [0.25, 0.3, 0.35, 0.42, 0.5]  # Food Machine (Kitchen): share of the XP bar per feed
TRAINING_SLOTS = [1, 2, 3, 4, 5]  # Training Place (Gym): pets training at once
VAULT_PILE_SECONDS = [300, 600, 900, 1200, 1800]  # added to the pile size
VAULT_OFFLINE_PERCENT = [0.1, 0.15, 0.2, 0.25, 0.3]
VAULT_OFFLINE_HOURS = [1, 2, 3, 4, 4]
OFFLINE_MIN_SECONDS = 120
FUSION_TOKEN_DISCOUNT = [0, 0.1, 0.2]
HOUSE_HOME_LEVEL = [0, 10, 20, 30]
PRESTIGE_HOME_LEVEL = 40
PRESTIGE_MULTIPLIER = 1.25  # coins x1.25 per star
PRESTIGE_GEMS = [100, 10, 25]  # first reward, minus per later star, floor
PRESTIGE_GARDEN_SLOTS = [3, 1, 12]  # GardenSlotsBase, GardenSlotsPerStar, GardenSlotsMax
PRESTIGE_PRICE_STEP = 0.5  # station prices x(1 + step) ^ stars
COINS = [8, 12, 5, 6, 240]  # MealSeconds, GrassFood, LuckyMult, BaseRadius, BasePileSeconds
COINS_HEAP_STAGES = [1, 3, 6, 12, 24]
FEED_BASE = 2.0  # one feed costs XpToNext(level) x RarityScale x FEED_BASE
TRAINING = [10, 300, 1]  # MaxRank, CostBase (rank r costs CostBase x r^2 x RarityScale), MinutesPerRank
# leftover foods (fed first and free): Price, Xp, CookSeconds, KitchenLevel (data kept from Phase 3)
FOOD_Snack = [50, 25, 6, 1]
FOOD_Meal = [600, 150, 20, 2]
FOOD_Feast = [6000, 800, 45, 4]
PET_XP = [100, 20, 1.6, 5]  # MaxLevel, Base, Exponent, Round: XpToNext(L) = round(Base * L ^ Exponent / Round) * Round
TIER_MULTIPLIER = [1, 1.5, 2.5]  # Normal, Golden, Rainbow
# pets (from Config + PetCatalog; the smoke check verifies them): rarity order Common .. Secret
RARITY_SCALE = [1, 1.5, 2.3, 3.5, 5.5, 8.5, 13]
LEVEL_CAPS = [100, 100, 100, 100, 100, 100, 100]  # PetCatalog.LevelCap by rarity (the player's rule: every pet to 100)
ROLE_MULT = [1.6, 1]  # PetCatalog.RoleMult Economy, Combat
EVOLUTION_LEVELS = [20, 50]  # PetCatalog.EvolutionLevels
EVOLUTION_BOOST = [1.25, 1.5]  # PetCatalog.EvolutionBoost
EVOLVE_TWICE = [0, 0, 0, 1, 1, 1, 1]  # PetCatalog.MaxEvolution(rarity) == 2 (Epic and rarer)
PET_ROLLABLE = [6, 6, 5, 4, 3, 2]  # rollable pets per rarity, Common .. Mythic (Secret pets are not in these roulettes)
PET_ECON_ROLLABLE = [3, 3, 3, 2, 1, 1]  # ...of which Economy pets (the rest are Combat)
ODDS_Cloud = [60, 28, 10, 2, 0, 0]  # Config.Roulettes weights, Common .. Mythic
ODDS_Storm = [0, 35, 40, 20, 5, 0]
ODDS_Sky = [0, 0, 35, 45, 17, 3]
ODDS_Celestial = [0, 0, 0, 45, 40, 15]
# ==== END SIM CONSTANTS ====

STATION_ORDER = [
    "Press1", "Press2", "Press3", "Press4", "Collector", "Garden", "Kitchen", "Gym", "Vault", "House",
    "FusionMachine", "ArenaGate", "DecorLamps", "DecorFence", "DecorFlowers", "DecorFountain", "DecorBanners", "DecorPodium",
]
KIND = {
    "Press1": "Plant", "Press2": "Plant", "Press3": "Plant", "Press4": "Plant", "Collector": "Magnet",
    "Garden": "Garden", "Kitchen": "FoodMachine", "Gym": "Training", "Vault": "Vault", "House": "House",
    "FusionMachine": "Fusion", "ArenaGate": "Arena",
}
NAMES = {"Press1": "Berry Bush", "Press2": "Carrot Patch", "Press3": "Cloud Melons", "Press4": "Starfruit Tree",
         "Collector": "Coin Magnet", "Garden": "Pet Garden", "Kitchen": "Food Machine", "Gym": "Training Place"}
PLANTS = ("Press1", "Press2", "Press3", "Press4")
TIERS = ["Cottage", "Villa", "Manor", "SkyCastle"]
TIER_NAMES = ["Cottage", "Villa", "Manor", "Sky Castle"]
RARITIES = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
FOODS = ["Snack", "Meal", "Feast"]
MEAL_SECONDS, GRASS_FOOD, LUCKY_MULT, BASE_RADIUS, BASE_PILE_SECONDS = COINS
GARDEN_BASE, GARDEN_PER_STAR, GARDEN_MAX = PRESTIGE_GARDEN_SLOTS

# ---- the player model (assumptions, not catalog data) ----
SCOOP_EVERY = 20  # seconds between scoops (the kid walks through the garden)
BUY_OVERHEAD = 4  # seconds to walk to a pad and hold E
PATIENCE = 300  # seconds of income the player is willing to save for one target
FILLER = 0.3  # while saving, buy any affordable pad costing at most this share of the target
HOUSE_WEIGHT = 0.3  # a new house is worth this share of the current income per second
CHORE_WEIGHT = 0.03  # a pad without coins (decor, training, vault...) is worth this share
FOOD_MACHINE_WEIGHT = 0.1  # the first Food Machine (feeding unlocks)
HL_PUSH = 0.2  # extra share for any level while the next house waits for Home Level
FEED_INCOME_SHARE = 0.25  # the kid spends a quarter of the coins at the Food Machine (--feed)
RING_BONUS = 0.0  # extra Cash per second as a share of garden income (a regular Champion Ring climber: --ring 0.08)
# roulette rolls: (minutes after the first claim, roulette). The tutorial gives one Cloud roll and its match pays
# another; afterwards an obby run every ~15-30 minutes buys a roll (Storm / Sky as the token income grows).
ROLLS = [(0, "Cloud"), (0, "Cloud"), (12, "Cloud"), (25, "Cloud"), (40, "Cloud"), (55, "Storm"), (75, "Cloud"),
         (95, "Storm"), (115, "Cloud"), (135, "Storm"), (160, "Storm"), (190, "Sky"), (220, "Storm"), (250, "Sky"),
         (280, "Storm"), (320, "Sky"), (360, "Storm"), (400, "Sky"), (440, "Storm"), (480, "Sky"), (540, "Sky"),
         (600, "Celestial"), (660, "Sky"), (720, "Celestial")]

# ---- targets (ARCHITECTURE_V3.md "Phase 4 build contract" 3.12 / 8.3) ----
TARGETS = dict(
    first_paid_s=60,  # every player: the first paid pad (after the free Garden) within a minute
    early_mean_gap=(0.5, 3.0),  # median player, first 30 minutes: a purchase every 0.5-3 min
    early_p90=3.0,  # 90% of the first-30-minute gaps of the median player
    villa=(25, 40),  # Monte Carlo median, minutes
    p1=(120, 180),  # first prestige: Monte Carlo median, minutes ("about 2-3 hours of active play")
    run_floor_min=12,  # every run of the first 10 (seed player) lasts at least this long
    gems_per_hour=135,  # prestige Gems per hour on runs 2-10 (Phase 3 ran 100-133)
    dead=6.0,  # longest stretch with NOTHING affordable, every player incl. a Combat-only one
    combat_p1=240,  # a Combat-pets-only player still prestiges within this many minutes
    evolve_min=(40, 100),  # the first EVOLVE moment (Monte Carlo median), minutes
    pile_scoops=10,  # an active player never fills a pile: the smallest pile >= 10x the scoop gap
    offline_hours=2.0,  # the best Vault pays at most 2 h of income (and more than nothing)
)


# ------------------------------------------------------------------------------------------------
# catalog model
# ------------------------------------------------------------------------------------------------
def parse_req(text):
    out = {}
    for tok in text.split():
        k, v = tok.split("=")
        out[k] = v if k == "House" else int(v)
    return out


class Station:
    def __init__(self, sid):
        g = globals()
        self.id = sid
        self.kind = KIND.get(sid, "Decor")
        self.price = list(g["PRICE_" + sid])
        self.max = len(self.price)
        self.caps = list(g["CAPS_" + sid])
        self.req = parse_req(g["REQ_" + sid])
        self.keep = sid in KEEP_ON_PRESTIGE.split()
        self.soon = sid in COMING_SOON.split()
        self.reset = parse_req(RESET_LEVEL).get(sid, 0)
        self.food = list(g.get("PLANT_FOOD_" + sid, []))


STATIONS = {sid: Station(sid) for sid in STATION_ORDER}
FOOD = {f: dict(zip(["price", "xp", "cook", "kitchen"], globals()["FOOD_" + f])) for f in FOODS}


def xp_to_next(level):
    max_level, base, exp, rnd = PET_XP
    if level >= max_level:
        return math.inf
    return max(rnd, int(math.floor(base * level ** exp / rnd + 0.5)) * rnd)


def feed_xp(level, machine_level):
    """TycoonCatalog.FeedXp: max(1, round(XpToNext x FeedShare[machine])), 0 at the top level / without a machine."""
    if machine_level < 1:
        return 0
    need = xp_to_next(level)
    if need == math.inf:
        return 0
    return max(1, int(math.floor(need * FEED_SHARE[min(machine_level, len(FEED_SHARE)) - 1] + 0.5)))


def feed_price(rarity_index, level):
    """TycoonCatalog.FeedPrice: round(XpToNext x RarityScale x FeedBase); None at the top level."""
    need = xp_to_next(level)
    if need == math.inf:
        return None
    return int(math.floor(need * RARITY_SCALE[rarity_index] * FEED_BASE + 0.5))


def train_cost(rarity_index, rank):
    return int(math.floor(TRAINING[1] * rank * rank * RARITY_SCALE[rarity_index] + 0.5))


def train_seconds(rank):
    return rank * TRAINING[2] * 60


def tier_of(st):
    return max(1, st.get("House", 0))


def home_level(st):
    return sum(min(max(int(v), 0), STATIONS[k].max) for k, v in st.items() if k in STATIONS)


def food(st):
    if st.get("Garden", 0) < 1:
        return 0
    total = GRASS_FOOD
    for sid in PLANTS:
        lv = st.get(sid, 0)
        if lv:
            total += STATIONS[sid].food[lv - 1]
    return total


def lucky_chance(st):
    g = st.get("Garden", 0)
    return GARDEN_LUCKY[g - 1] if g else 0.0


def lucky_ev(st):
    return 1 + (LUCKY_MULT - 1) * lucky_chance(st)


def max_evolution(rarity_index):
    return 2 if EVOLVE_TWICE[rarity_index] else 1


def power(p):
    """TycoonCatalog.PetPower: RarityScale x level factor x tier x RoleMult x EvolutionBoost[stage]."""
    evo = min(p["evo"], max_evolution(p["r"]))
    boost = EVOLUTION_BOOST[evo - 1] if evo >= 1 else 1.0
    level = max(1, min(p["level"], PET_XP[0]))
    return (RARITY_SCALE[p["r"]] * (1 + 0.1 * (level - 1)) * p["tier"] * (ROLE_MULT[0] if p["econ"] else ROLE_MULT[1])
            * boost)


def slots(stars, legacy=0, garden_level=1):
    """TycoonCatalog.GardenSlots (0 without a Garden)."""
    if garden_level < 1:
        return 0
    return min(GARDEN_MAX, max(GARDEN_BASE + GARDEN_PER_STAR * stars, legacy or 0))


def garden(pets, stars, legacy=0):
    """The kid fills the open places with the best pets (any role)."""
    return sorted(pets, key=lambda p: -power(p))[:slots(stars, legacy)]


def income(st, pets, stars, legacy=0):
    """TycoonCatalog.IncomePerSecond: Food / MealSeconds x sum(PetPower of the open places) x LuckyEV x 1.25 ^ stars."""
    return (food(st) / MEAL_SECONDS * sum(power(p) for p in garden(pets, stars, legacy)) * lucky_ev(st)
            * PRESTIGE_MULTIPLIER ** stars)


def pile_seconds(st):
    c, v = st.get("Collector", 0), st.get("Vault", 0)
    s = MAGNET_PILE_SECONDS[c - 1] if c else BASE_PILE_SECONDS
    return s + (VAULT_PILE_SECONDS[v - 1] if v else 0)


def scoop_radius(st):
    c = st.get("Collector", 0)
    return MAGNET_RADIUS[c - 1] if c else BASE_RADIUS


def star_factor(stars, legacy_prices=False):
    """TycoonCatalog.StarPriceMultiplier: (1 + step) ^ stars, 1 while LegacyPrices."""
    if legacy_prices:
        return 1.0
    return (1 + PRESTIGE_PRICE_STEP) ** stars


def price_of(sid, lvl, stars, legacy_prices=False):
    """TycoonCatalog.PriceAt: floor(base price x star factor)."""
    return int(math.floor(STATIONS[sid].price[lvl - 1] * star_factor(stars, legacy_prices) + 1e-9))


def gem_reward(stars):
    first, step, floor_ = PRESTIGE_GEMS
    return max(floor_, first - step * (max(1, stars) - 1))


def stations_after_prestige(st):
    out = {k: v for k, v in st.items() if k in STATIONS and STATIONS[k].keep and v > 0}
    for sid in STATION_ORDER:
        s = STATIONS[sid]
        if s.reset and not s.keep:
            out[sid] = min(s.reset, s.max)
    return out


def offline_earnings(st, seconds, inc):
    v = st.get("Vault", 0)
    if v < 1 or seconds < OFFLINE_MIN_SECONDS:
        return 0
    return math.floor(inc * min(seconds, VAULT_OFFLINE_HOURS[v - 1] * 3600) * VAULT_OFFLINE_PERCENT[v - 1])


def pads(st, stars, legacy_prices=False):
    """[(id, nextLevel, price, lockReason|None)] exactly like TycoonCatalog.AvailablePads (without the prestige pad)."""
    hl = home_level(st)
    tier = tier_of(st)
    out = []
    for sid in STATION_ORDER:
        s = STATIONS[sid]
        lv = st.get(sid, 0)
        if lv >= s.max:
            continue
        if any(k in STATIONS and k != "House" and st.get(k, 0) < v for k, v in s.req.items()):
            continue
        nxt = lv + 1
        lock = None
        if s.soon:
            lock = "Coming soon"
        elif s.req.get("Prestige", 0) > stars:
            lock = "Unlocks at Prestige %d" % s.req["Prestige"]
        elif "House" in s.req and TIERS.index(s.req["House"]) + 1 > tier:
            lock = "Needs the " + TIER_NAMES[TIERS.index(s.req["House"])]
        elif sid == "House" and HOUSE_HOME_LEVEL[nxt - 1] > hl:
            lock = "Reach Home Level %d" % HOUSE_HOME_LEVEL[nxt - 1]
        elif nxt > s.caps[tier - 1]:
            lock = "Needs the " + next(TIER_NAMES[i] for i in range(4) if s.caps[i] >= nxt)
        out.append((sid, nxt, price_of(sid, nxt, stars, legacy_prices), lock))
    return out


def can_prestige(st):
    return tier_of(st) >= 4 and st.get("House", 0) >= 4 and home_level(st) >= PRESTIGE_HOME_LEVEL


# ------------------------------------------------------------------------------------------------
# pets
# ------------------------------------------------------------------------------------------------
def new_pet(rarity_index, econ):
    return {"r": rarity_index, "econ": econ, "level": 1, "xp": 0, "tier": 1.0, "evo": 0}


def roll(rng, roulette, mode):
    weights = globals()["ODDS_" + roulette]
    r = rng.random() * sum(weights)
    ri = 0
    for i, w in enumerate(weights):
        r -= w
        if r < 0:
            ri = i
            break
    econ = rng.randrange(PET_ROLLABLE[ri]) < PET_ECON_ROLLABLE[ri] and mode != "combat"
    return new_pet(ri, econ)


# ------------------------------------------------------------------------------------------------
# the simulation
# ------------------------------------------------------------------------------------------------
class Result:
    def __init__(self):
        self.log = []  # (t, text, price, income, homeLevel, run)
        self.ms = {}  # milestone -> seconds (since the run start for house tiers / runs, absolute for P<n>)
        self.gaps = []  # (gap seconds, t, id, level, run, t_in_run)
        self.dead = (0, 0)  # longest stretch with nothing affordable: (seconds, t)
        self.feed_cash = 0
        self.feeds = 0
        self.evolve_t = None
        self.evolve2_t = None
        self.inc_at = {}  # minute -> income (first run)
        self.levels_at = {}  # every 30 min of the first run: the top-3 pet levels
        self.pile_ratio_min = math.inf  # smallest pile / scoop gap
        self.gems = 0
        self.pets = []
        self.stars = 0
        self.total_t = 0
        self.final_stations = {}


def pick_feed_pet(g):
    """The pet the kid feeds next: one that can evolve soon first, then the strongest."""
    def key(p):
        first = p["evo"] == 0 and p["level"] >= 10
        second = p["level"] >= EVOLUTION_LEVELS[0] and max_evolution(p["r"]) >= 2 and p["evo"] == 1
        return (first, second, power(p))
    return max(g, key=key)


def grow(p, xp, t, res):
    """Add XP (level-ups along XpToNext up to the cap); the kid presses EVOLVE as soon as it is offered."""
    cap = LEVEL_CAPS[p["r"]]
    p["xp"] += xp
    while p["level"] < cap and p["xp"] >= xp_to_next(p["level"]):
        p["xp"] -= xp_to_next(p["level"])
        p["level"] += 1
        if p["level"] >= EVOLUTION_LEVELS[0] and p["evo"] == 0:
            p["evo"] = 1
            if res.evolve_t is None:
                res.evolve_t = t
        if p["level"] >= EVOLUTION_LEVELS[1] and p["evo"] == 1 and max_evolution(p["r"]) >= 2:
            p["evo"] = 2
            if res.evolve2_t is None:
                res.evolve2_t = t
    if p["level"] >= cap:
        p["xp"] = 0


def simulate(seed=1, runs=3, mode="random", max_minutes=900, ring=None, feed_share=None):
    ring = RING_BONUS if ring is None else ring
    feed_share = FEED_INCOME_SHARE if feed_share is None else feed_share
    rng = random.Random(seed)
    res = Result()
    t = stars = run = run_start = last_buy = roll_i = 0
    st, pets = {}, []
    cash = lawn = feed_budget = 0.0
    next_scoop = 3  # the player walks from the gate to the first pad
    dead_start = None
    cache_key = None
    cheapest = math.inf
    inc = 0.0
    dirty = True
    while t < max_minutes * 60 and run < runs:
        while roll_i < len(ROLLS) and ROLLS[roll_i][0] * 60 <= t:
            if mode in ("random", "combat"):
                pets.append(roll(rng, ROLLS[roll_i][1], mode))
                dirty = True
            elif mode == "one" and not pets:
                pets.append(new_pet(0, False))
                dirty = True
            roll_i += 1
        if dirty:
            inc = income(st, pets, stars)
            dirty = False
        if run == 0 and t % 60 == 0:
            res.inc_at[t // 60] = inc
            if t % 1800 == 0:
                res.levels_at[t // 60] = sorted([p["level"] for p in pets], reverse=True)[:3]
        lawn += inc
        cash += inc * ring
        feed_budget += inc * feed_share
        t += 1
        key = (tuple(sorted(st.items())), stars)
        if key != cache_key:
            cache_key = key
            cheapest = min([p[2] for p in pads(st, stars) if p[3] is None] or [math.inf])
        if cheapest < math.inf and cheapest > cash + lawn:
            if dead_start is None:
                dead_start = t
        elif dead_start is not None:
            if t - dead_start > res.dead[0]:
                res.dead = (t - dead_start, t)
            dead_start = None
        if t < next_scoop:
            continue
        res.pile_ratio_min = min(res.pile_ratio_min, pile_seconds(st) / SCOOP_EVERY)
        next_scoop = t + SCOOP_EVERY
        cash += lawn
        lawn = 0
        kl = st.get("Kitchen", 0)
        # --- feeding: the kid spends a share of the coins at the Food Machine ---
        if kl:
            guard = 0
            while guard < 40:
                guard += 1
                g = [p for p in garden(pets, stars) if p["level"] < LEVEL_CAPS[p["r"]]]
                if not g:
                    break
                bp = pick_feed_pet(g)
                price = feed_price(bp["r"], bp["level"])
                if price is None or price > feed_budget or price > cash:
                    break
                cash -= price
                feed_budget -= price
                res.feed_cash += price
                res.feeds += 1
                grow(bp, feed_xp(bp["level"], kl), t, res)
                dirty = True
            feed_budget = min(feed_budget, cash)
        # --- buying ---
        while True:
            hl = home_level(st)
            if can_prestige(st):
                stars += 1
                run += 1
                res.gems += gem_reward(stars)
                res.ms["P%d" % stars] = t
                res.ms["run%d" % stars] = t - run_start
                res.log.append((t, "PRESTIGE -> %d stars (run %s, Home Level %d)" % (stars, fmt(t - run_start), hl), 0, inc, hl, run - 1))
                run_start = t
                st = stations_after_prestige(st)
                cash = lawn = 0
                feed_budget = 0
                last_buy = t
                dirty = True
                inc = income(st, pets, stars)
                break
            open_pads = [p for p in pads(st, stars) if p[3] is None]
            cur = max(income(st, pets, stars), 0.5)
            best, best_score = None, -1.0
            if open_pads:
                reach = [p for p in open_pads if p[2] - cash <= PATIENCE * cur] or [min(open_pads, key=lambda p: p[2])]
                push = HOUSE_HOME_LEVEL[min(st.get("House", 0), 3)] > hl if st.get("House", 0) < 4 else hl < PRESTIGE_HOME_LEVEL
                for sid, lvl, price, _ in reach:
                    st2 = dict(st)
                    st2[sid] = lvl
                    gain = income(st2, pets, stars) - cur
                    kind = STATIONS[sid].kind
                    if kind == "House":
                        value = cur * HOUSE_WEIGHT
                    elif gain > 1e-9:
                        value = gain
                    elif kind == "FoodMachine" and lvl == 1:
                        value = cur * FOOD_MACHINE_WEIGHT
                    else:
                        value = cur * CHORE_WEIGHT
                    if push:
                        value += cur * HL_PUSH
                    score = value / max(price, 1)
                    if score > best_score:
                        best, best_score = (sid, lvl, price), score
            if best and best[2] > cash:
                fillers = [p for p in open_pads if p[2] <= best[2] * FILLER and p[2] <= cash]
                if fillers:
                    f = min(fillers, key=lambda p: p[2])
                    best = (f[0], f[1], f[2])
            if not best or best[2] > cash:
                break
            sid, lvl, price = best
            cash -= price
            st[sid] = lvl
            t += BUY_OVERHEAD
            dirty = True
            res.gaps.append((t - last_buy, t, sid, lvl, run, t - run_start))
            last_buy = t
            res.log.append((t, "%s L%d" % (NAMES.get(sid, sid), lvl), price, income(st, pets, stars), home_level(st), run))
            if sid == "House":
                res.ms["%s%d" % (TIERS[lvl - 1], run)] = t - run_start
            if "first_paid" not in res.ms and price > 0:
                res.ms["first_paid"] = t
    res.pets = pets
    res.stars = stars
    res.total_t = t
    res.final_stations = st
    return res


# ------------------------------------------------------------------------------------------------
# reporting
# ------------------------------------------------------------------------------------------------
def fmt(seconds):
    s = int(round(seconds))
    if s >= 3600:
        return "%d:%02d:%02d" % (s // 3600, (s % 3600) // 60, s % 60)
    return "%d:%02d" % (s // 60, s % 60)


def money(n):
    return "{:,}".format(int(n))


def pct(values, q):
    v = sorted(values)
    if not v:
        return float("nan")
    return v[min(len(v) - 1, max(0, int(round(q * (len(v) - 1)))))]


def pet_text(p):
    return "%s%s L%d%s" % (RARITIES[p["r"]][:3], "E" if p["econ"] else "C", p["level"], "*" * p["evo"])


def print_timeline(res):
    run = -1
    for (t, text, price, inc, hl, r) in res.log:
        if r != run:
            run = r
            print("\n  -- run %d --" % (run + 1))
        print("  %9s  %-46s %12s   %10.1f Cash/s   Home Level %d" % (fmt(t), text, money(price) if price else "", inc, hl))


def offline_table():
    rows = []
    for v in range(1, len(VAULT_OFFLINE_HOURS) + 1):
        st = {"Vault": v}
        cells = []
        for hours in (1, 4, 12):
            got = offline_earnings(st, hours * 3600, 1.0)  # in seconds of income at 1 Cash/s
            cells.append("%3d min" % round(got / 60))
        rows.append("    Vault L%d (%2d%% for up to %dh): away 1h -> %s, 4h -> %s, 12h -> %s of active income"
                    % (v, VAULT_OFFLINE_PERCENT[v - 1] * 100, VAULT_OFFLINE_HOURS[v - 1], cells[0], cells[1], cells[2]))
    return rows


def xp_road_lines():
    """What the Food Machine charges to raise a pet (machine Lv1 / Lv5) and how much XP the roads take."""
    lines = []
    for target in (EVOLUTION_LEVELS[0], EVOLUTION_LEVELS[1], PET_XP[0]):
        xp = sum(xp_to_next(l) for l in range(1, target))
        cash = {}
        for kl in (1, len(FEED_SHARE)):
            total, lv, have = 0, 1, 0
            while lv < target:
                total += feed_price(0, lv)
                have += feed_xp(lv, kl)
                while lv < target and have >= xp_to_next(lv):
                    have -= xp_to_next(lv)
                    lv += 1
            cash[kl] = total
        lines.append("    L1 -> %d: %s XP; a Common pays %s at a Lv1 Food Machine, %s at Lv5 (Legendary x%.1f)"
                     % (target, money(xp), "$" + money(cash[1]), "$" + money(cash[len(FEED_SHARE)]), RARITY_SCALE[4]))
    return lines


def run_report(args):
    failures = []

    def check(ok, text):
        print("  [%s] %s" % ("ok" if ok else "MISSED", text))
        if not ok:
            failures.append(text)

    ring, share = args.ring, args.feed
    one = simulate(seed=args.seed, runs=args.runs, mode=args.mode, ring=ring, feed_share=share)
    if not args.quiet:
        print("Timeline of one %s player (seed %d), %d prestige run(s), ring bonus %.2f, feeding %.0f%% of the coins:"
              % (args.mode, args.seed, args.runs, ring, share * 100))
        print_timeline(one)
        print("\n  pets: " + ", ".join(pet_text(p) for p in one.pets))
        print("  feeds: %d (Cash %s), first EVOLVE at %s, first 2nd evolution at %s" % (
            one.feeds, money(one.feed_cash), fmt(one.evolve_t) if one.evolve_t else "never",
            fmt(one.evolve2_t) if one.evolve2_t else "never"))
    print("\nThis player: income/s by minute: " + ", ".join(
        "%d: %.0f" % (m, one.inc_at[m]) for m in (1, 5, 10, 20, 30, 60, 90, 120, 150) if m in one.inc_at))
    print("  top-3 pet levels every 30 min of run 1: %s" % one.levels_at)

    # Monte Carlo over pet luck
    n = args.mc
    ms = {}
    em, ep, dead, evo, evo2, piles = [], [], [], [], [], []
    for seed in range(1000, 1000 + n):
        r = simulate(seed=seed, runs=3, ring=ring, feed_share=share)
        for k, v in r.ms.items():
            ms.setdefault(k, []).append(v)
        eg = [g[0] for g in r.gaps if g[4] == 0 and g[5] <= 1800]
        em.append(sum(eg) / len(eg) if eg else 1e9)
        ep.append(pct(eg, 0.9) if eg else 1e9)
        dead.append(r.dead[0])
        evo.append(r.evolve_t if r.evolve_t else 1e9)
        evo2.append(r.evolve2_t if r.evolve2_t else 1e9)
        piles.append(r.pile_ratio_min)
    print("\nMonte Carlo: %d typical players (roulette luck varies), 3 prestige runs each" % n)
    for key, label in [("first_paid", "first paid buy"), ("Cottage0", "Cottage"), ("Villa0", "Villa"), ("Manor0", "Manor"),
                       ("SkyCastle0", "Sky Castle"), ("run1", "1st prestige"), ("run2", "2nd run"), ("run3", "3rd run")]:
        v = ms.get(key, [])
        if v:
            print("  %-16s p10 %9s   median %9s   p90 %9s   (%d players)" % (label, fmt(pct(v, .1)), fmt(pct(v, .5)), fmt(pct(v, .9)), len(v)))
    never = lambda v: "never" if v >= 1e9 else fmt(v)
    print("  %-16s p10 %9s   median %9s   p90 %9s" % ("first EVOLVE", never(pct(evo, .1)), never(pct(evo, .5)), never(pct(evo, .9))))
    e2 = [x for x in evo2 if x < 1e9]
    print("  second evolution (Epic+, level 50) within 3 runs: %d of %d players%s" % (
        len(e2), n, (" (median %s)" % fmt(pct(e2, .5))) if e2 else ""))
    print("  early purchase gap (first 30 min): median player mean %.2f min, 90th pct gap %.2f min" % (pct(em, .5) / 60, pct(ep, .5) / 60))
    print("  longest stretch with nothing affordable: median %.1f min, worst %.1f min" % (pct(dead, .5) / 60, max(dead) / 60))

    combat = simulate(seed=1, runs=2, mode="combat", ring=ring, feed_share=share)
    onepet = simulate(seed=1, runs=1, mode="one", max_minutes=600, ring=ring, feed_share=share)
    long = simulate(seed=args.seed, runs=10, max_minutes=3000, ring=ring, feed_share=share)
    runs = [long.ms["run%d" % i] / 60 for i in range(1, 11) if "run%d" % i in long.ms]
    print("\nLater runs (seed %d): %s" % (args.seed, ", ".join("P%d %s" % (i + 1, fmt(x * 60)) for i, x in enumerate(runs))))
    gph = [gem_reward(i + 1) / (x / 60) for i, x in enumerate(runs)]
    print("  prestige Gems per hour by run: %s" % ", ".join("P%d %.0f" % (i + 1, g) for i, g in enumerate(gph)))
    total_h = sum(runs) / 60 if runs else 0
    if total_h:
        print("  Gems over %d runs: %d in %.1f h = %.0f per hour" % (len(runs), long.gems, total_h, long.gems / total_h))
    top = sorted(long.pets, key=lambda p: -p["level"])[:5]
    print("  after %d runs the best pets are %s; %d of %d pets above level %d" % (
        len(runs), ", ".join(pet_text(p) for p in top), sum(1 for p in long.pets if p["level"] > EVOLUTION_LEVELS[1]),
        len(long.pets), EVOLUTION_LEVELS[1]))
    print("  a Combat-pets-only player: 1st prestige %s, worst dead time %.1f min" % (
        fmt(combat.ms["run1"]) if "run1" in combat.ms else "never", combat.dead[0] / 60))
    print("  a one-Common-pet-forever player: prestige %s, worst dead time %.1f min" % (
        fmt(onepet.ms["run1"]) if "run1" in onepet.ms else "never in 10 h", onepet.dead[0] / 60))
    print("\nThe Food Machine roads (FeedBase %.1f; every pet grows to level %d):" % (FEED_BASE, PET_XP[0]))
    for line in xp_road_lines():
        print(line)
    print("\nOffline earnings (the Vault; 0 without one, nothing for absences under %d s; paid into the Welcome-back pile):" % OFFLINE_MIN_SECONDS)
    for row in offline_table():
        print(row)

    print("\nTargets:")
    firsts = ms.get("first_paid", [])
    check(bool(firsts) and len(firsts) == n and max(firsts) <= TARGETS["first_paid_s"],
          "first paid purchase within %d s (worst %s)" % (TARGETS["first_paid_s"], fmt(max(firsts or [0]))))
    lo, hi = TARGETS["early_mean_gap"]
    check(lo <= pct(em, .5) / 60 <= hi, "a purchase every %.1f-%.0f min early on (median mean gap %.2f min)" % (lo, hi, pct(em, .5) / 60))
    check(pct(ep, .5) / 60 <= TARGETS["early_p90"], "early gaps short (p90 %.2f min <= %.0f)" % (pct(ep, .5) / 60, TARGETS["early_p90"]))
    v = pct(ms.get("Villa0", [1e9]), .5) / 60
    check(TARGETS["villa"][0] <= v <= TARGETS["villa"][1], "Villa at %d-%d min (median %.1f)" % (TARGETS["villa"] + (v,)))
    p1 = pct(ms.get("run1", [1e9]), .5) / 60
    check(TARGETS["p1"][0] <= p1 <= TARGETS["p1"][1], "first Prestige after 2-3 h (median %.0f min)" % p1)
    r2, r3 = pct(ms.get("run2", [1e9]), .5) / 60, pct(ms.get("run3", [1e9]), .5) / 60
    check(r2 < p1 and r3 < r2, "later prestiges faster (%.0f -> %.0f -> %.0f min)" % (p1, r2, r3))
    check(len(runs) == 10 and min(runs) >= TARGETS["run_floor_min"],
          "no throw-away prestiges: every run of 10 >= %d min (shortest %.1f)" % (TARGETS["run_floor_min"], min(runs or [0])))
    check(len(gph) > 1 and max(gph[1:]) <= TARGETS["gems_per_hour"],
          "prestige Gems <= %d per hour on runs 2-10 (max %.0f/h; Phase 3 ran 100-133)" % (TARGETS["gems_per_hour"], max(gph[1:] or [0])))
    wd = max(max(dead), combat.dead[0]) / 60
    check(wd <= TARGETS["dead"], "never more than %.0f min with nothing to buy (worst %.1f, combat-only player included)" % (TARGETS["dead"], wd))
    cp1 = combat.ms.get("run1", 1e9) / 60
    check(cp1 <= TARGETS["combat_p1"], "a Combat-pets-only player still prestiges (%.0f min <= %d)" % (cp1, TARGETS["combat_p1"]))
    e = pct(evo, .5) / 60
    check(TARGETS["evolve_min"][0] <= e <= TARGETS["evolve_min"][1], "first EVOLVE moment after %d-%d min (median %.0f min)" % (TARGETS["evolve_min"] + (e,)))
    check(min(piles) >= TARGETS["pile_scoops"],
          "an active player (scoops every %d s) never fills a pile (smallest pile = %.0fx the gap)" % (SCOOP_EVERY, min(piles)))
    best = max(offline_earnings({"Vault": v}, 48 * 3600, 1.0) for v in range(1, 6)) / 3600
    check(0 < best <= TARGETS["offline_hours"], "offline coins meaningful but capped (best Vault: %.1f h of income)" % best)
    print("\n%s" % ("ALL TARGETS MET" if not failures else "%d TARGET(S) MISSED" % len(failures)))
    return 0 if not failures else 1


# ------------------------------------------------------------------------------------------------
# --check / --plan: load the Lua catalog with lupa and tiny Roblox stand-ins
# ------------------------------------------------------------------------------------------------
LUA_STUBS = r"""
local function vec(x, y, z) return setmetatable({X = x, Y = y, Z = z}, VecMT) end
VecMT = {
  __add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
  __sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
  __mul = function(a, b) if type(a) == "number" then return vec(a * b.X, a * b.Y, a * b.Z) end
                         if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
                         return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end,
  __index = function(v, k) if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end end,
}
Vector3 = { new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end }
-- CFrames are position + yaw (the catalog only turns about Y)
local function rot(yaw, x, z) local c, s = math.cos(yaw), math.sin(yaw) return x * c + z * s, -x * s + z * c end
local function cf(x, y, z, yaw) return setmetatable({x = x, y = y, z = z, yaw = yaw or 0}, CfMT) end
CfMT = {
  __mul = function(a, b)
    if getmetatable(b) == VecMT then local rx, rz = rot(a.yaw, b.X, b.Z) return vec(a.x + rx, a.y + b.Y, a.z + rz) end
    local rx, rz = rot(a.yaw, b.x, b.z) return cf(a.x + rx, a.y + b.y, a.z + rz, a.yaw + b.yaw)
  end,
  __index = function(c, k)
    if k == "Position" then return vec(c.x, c.y, c.z) end
    if k == "LookVector" then local x, z = rot(c.yaw, 0, -1) return vec(x, 0, z) end
    if k == "Yaw" then return c.yaw end
  end,
}
CFrame = {
  new = function(x, y, z) if type(x) == "table" then return cf(x.X, x.Y, x.Z, 0) end return cf(x or 0, y or 0, z or 0, 0) end,
  Angles = function(rx, ry, rz) return cf(0, 0, 0, ry or 0) end,
  lookAt = function(a, b) local dx, dz = b.X - a.X, b.Z - a.Z return cf(a.X, a.Y, a.Z, math.atan2(-dx, -dz)) end,
}
local colorMT = {}
Color3 = { fromRGB = function(r, g, b) return setmetatable({R = r / 255, G = g / 255, B = b / 255}, colorMT) end,
           new = function(r, g, b) return setmetatable({R = r, G = g, B = b}, colorMT) end }
function typeof(v)
  local mt = getmetatable(v)
  if mt == VecMT then return "Vector3" elseif mt == CfMT then return "CFrame" elseif mt == colorMT then return "Color3" end
  return type(v)
end
warn = function() end
"""


def load_catalog(with_pets=False):
    """(runtime, TycoonCatalog[, PetCatalog, Config]) loaded with lupa. with_pets also loads PetCatalog, which
    TycoonCatalog then resolves through Shared:FindFirstChild("PetCatalog") like in the game."""
    runtime = None
    for name in ("lupa.luajit21", "lupa.luajit20", "lupa.lua51", "lupa"):  # Lua 5.1 semantics first, like smoke.py
        try:
            runtime = importlib.import_module(name).LuaRuntime
            break
        except (ImportError, AttributeError):
            continue
    if runtime is None:
        sys.exit("--check / --plan need lupa:  pip install lupa")
    rt = runtime(unpack_returned_tuples=True)
    rt.execute("math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end")
    rt.execute(LUA_STUBS)
    g = rt.globals()
    shared = os.path.join(ROOT, "src", "shared")
    g.CONFIG_SRC = open(os.path.join(shared, "Config.lua"), encoding="utf-8").read()
    g.CATALOG_SRC = open(os.path.join(shared, "TycoonCatalog.lua"), encoding="utf-8").read()
    g.PETS_SRC = open(os.path.join(shared, "PetCatalog.lua"), encoding="utf-8").read() if with_pets else ""
    rt.execute(r"""
      local load_ = loadstring or load
      local Config = assert(load_(CONFIG_SRC, "=Config"))()
      local loaded = { Config = Config }
      local Shared = { Config = "Config" }
      function Shared:FindFirstChild(name)
        if loaded[name] ~= nil and name ~= "Config" then return name end
        return nil
      end
      script = { Parent = Shared }
      require = function(m)
        if loaded[m] ~= nil then return loaded[m] end
        error("no module " .. tostring(m))
      end
      if PETS_SRC ~= "" then
        loaded.PetCatalog = assert(load_(PETS_SRC, "=PetCatalog"))()
      end
      CATALOG = assert(load_(CATALOG_SRC, "=TycoonCatalog"))()
      loaded.TycoonCatalog = CATALOG
      PETS = loaded.PetCatalog
      CONFIG = Config
    """)
    if with_pets:
        return rt, g.CATALOG, g.PETS, g.CONFIG
    return rt, g.CATALOG


def lua_list(t):
    out = []
    i = 1
    while t[i] is not None:
        out.append(t[i])
        i += 1
    return out


def run_check():
    rt, cat, pc, config = load_catalog(with_pets=True)
    problems = []

    def same(name, a, b, tol=1e-9):
        if isinstance(a, list) and isinstance(b, list):
            def eq(x, y):
                if isinstance(x, (int, float)) and isinstance(y, (int, float)):
                    return abs(float(x) - float(y)) <= tol * max(1.0, abs(float(x)))
                return x == y
            ok = len(a) == len(b) and all(eq(x, y) for x, y in zip(a, b))
        elif isinstance(a, (int, float)) and isinstance(b, (int, float)):
            ok = abs(float(a) - float(b)) <= tol * max(1.0, abs(float(a)))
        else:
            ok = a == b
        if not ok:
            problems.append("%s: sim %r, catalog %r" % (name, a, b))

    by_id = cat.ById
    order = lua_list(cat.Order)
    same("station order", STATION_ORDER, order)
    kinds = lua_list(cat.Kinds)
    for sid in STATION_ORDER:
        d = by_id[sid]
        if d is None:
            problems.append("catalog has no " + sid)
            continue
        s = STATIONS[sid]
        same("PRICE_" + sid, s.price, lua_list(d.Price))
        same("CAPS_" + sid, s.caps, [d.TierCaps[t] for t in TIERS])
        req = {}
        for k, v in d.Requires.items():
            req[k] = v
        same("REQ_" + sid, s.req, req)
        same("KEEP " + sid, s.keep, bool(d.KeepOnPrestige))
        same("COMING_SOON " + sid, s.soon, bool(d.ComingSoon))
        same("RESET_LEVEL " + sid, s.reset, d.ResetLevel or 0)
        same("KIND " + sid, s.kind, d.Kind)
        if d.Kind not in kinds:
            problems.append("%s: Kind %s is not in TycoonCatalog.Kinds" % (sid, d.Kind))
        if s.kind == "Plant":
            same("PLANT_FOOD_" + sid, s.food, [e.Food for e in lua_list(d.Effects)])
    eff = lambda sid, key: [e[key] for e in lua_list(by_id[sid].Effects)]
    same("GARDEN_LUCKY", GARDEN_LUCKY, eff("Garden", "Lucky"))
    same("MAGNET_RADIUS", MAGNET_RADIUS, eff("Collector", "Radius"))
    same("MAGNET_PILE_SECONDS", MAGNET_PILE_SECONDS, eff("Collector", "PileSeconds"))
    same("FEED_SHARE", FEED_SHARE, eff("Kitchen", "FeedShare"))
    same("FEED_SHARE (TycoonCatalog.FeedShare)", FEED_SHARE, lua_list(cat.FeedShare))
    same("TRAINING_SLOTS", TRAINING_SLOTS, eff("Gym", "Slots"))
    same("VAULT_PILE_SECONDS", VAULT_PILE_SECONDS, eff("Vault", "PileSeconds"))
    same("VAULT_OFFLINE_PERCENT", VAULT_OFFLINE_PERCENT, eff("Vault", "OfflinePercent"))
    same("VAULT_OFFLINE_HOURS", VAULT_OFFLINE_HOURS, eff("Vault", "OfflineHours"))
    same("FUSION_TOKEN_DISCOUNT", FUSION_TOKEN_DISCOUNT, eff("FusionMachine", "TokenDiscount"))
    same("OFFLINE_MIN_SECONDS", OFFLINE_MIN_SECONDS, cat.OfflineMinSeconds)
    same("HOUSE_HOME_LEVEL", HOUSE_HOME_LEVEL, [t.HomeLevel for t in lua_list(cat.HouseTiers)])
    p = cat.Prestige
    same("PRESTIGE_HOME_LEVEL", PRESTIGE_HOME_LEVEL, p.HomeLevel)
    same("PRESTIGE_MULTIPLIER", PRESTIGE_MULTIPLIER, p.IncomeMultiplier)
    same("PRESTIGE_GEMS", PRESTIGE_GEMS, [p.GemReward, p.GemRewardStep, p.GemRewardMin])
    same("PRESTIGE_GARDEN_SLOTS", PRESTIGE_GARDEN_SLOTS, [p.GardenSlotsBase, p.GardenSlotsPerStar, p.GardenSlotsMax])
    same("PRESTIGE_PRICE_STEP", PRESTIGE_PRICE_STEP, p.PriceStep)
    c = cat.Coins
    same("COINS", COINS, [c.MealSeconds, c.GrassFood, c.LuckyMult, c.BaseRadius, c.BasePileSeconds])
    same("COINS_HEAP_STAGES", COINS_HEAP_STAGES, lua_list(c.HeapStages))
    same("FEED_BASE", FEED_BASE, cat.FeedBase)
    tr = cat.Training
    same("TRAINING", TRAINING, [tr.MaxRank, tr.CostBase, tr.MinutesPerRank])
    for f in FOODS:
        food_ = cat.FoodsById[f]
        same("FOOD_" + f, globals()["FOOD_" + f], [food_.Price, food_.Xp, food_.CookSeconds, food_.KitchenLevel])
    px = cat.PetXp
    same("PET_XP", PET_XP, [px.MaxLevel, px.Base, px.Exponent, px.Round])
    tm = cat.TierMultiplier
    same("TIER_MULTIPLIER", TIER_MULTIPLIER, [tm.Normal, tm.Golden, tm.Rainbow])
    same("RARITY_SCALE", RARITY_SCALE, [config.PetStats.RarityScale[r] for r in RARITIES])
    same("LEVEL_CAPS", LEVEL_CAPS, [pc.LevelCap(r) for r in RARITIES])
    same("ROLE_MULT", ROLE_MULT, [pc.RoleMult.Economy, pc.RoleMult.Combat])
    same("EVOLUTION_LEVELS", EVOLUTION_LEVELS, lua_list(pc.EvolutionLevels))
    same("EVOLUTION_BOOST", EVOLUTION_BOOST, lua_list(pc.EvolutionBoost))
    same("EVOLVE_TWICE", EVOLVE_TWICE, [1 if pc.MaxEvolution(r) == 2 else 0 for r in RARITIES])
    for lv in range(1, PET_XP[0] + 1):
        a, b = xp_to_next(lv), cat.XpToNext(lv)
        if a != b:
            problems.append("XpToNext(%d): sim %r, catalog %r" % (lv, a, b))
            break
    # the Food Machine and the Training Place
    for ri, rarity in enumerate(RARITIES):
        for lv in range(1, PET_XP[0] + 1):
            if feed_price(ri, lv) != cat.FeedPrice(rarity, lv):
                problems.append("FeedPrice(%s, %d): sim %r, catalog %r" % (rarity, lv, feed_price(ri, lv), cat.FeedPrice(rarity, lv)))
                break
        for rank in range(1, TRAINING[0] + 1):
            if train_cost(ri, rank) != cat.TrainCost(rarity, rank):
                problems.append("TrainCost(%s, %d): sim %r, catalog %r" % (rarity, rank, train_cost(ri, rank), cat.TrainCost(rarity, rank)))
                break
    for kl in range(0, len(FEED_SHARE) + 1):
        for lv in range(1, PET_XP[0] + 1):
            if feed_xp(lv, kl) != cat.FeedXp(lv, kl):
                problems.append("FeedXp(%d, %d): sim %r, catalog %r" % (lv, kl, feed_xp(lv, kl), cat.FeedXp(lv, kl)))
                break
    same("TrainSeconds", [train_seconds(r) for r in range(1, TRAINING[0] + 1)], [cat.TrainSeconds(r) for r in range(1, TRAINING[0] + 1)])
    # random homes: pads (ids, next levels, star prices, lock reasons), PriceAt, food, slots, income, piles, offline
    rng = random.Random(7)
    lua_home = rt.eval("function(stars, legacyPrices, legacySlots) return { Stations = {}, Prestige = stars, "
                       "LegacyPrices = legacyPrices, LegacySlots = legacySlots } end")
    lua_entry = rt.eval("function(rarity, role, level, tier, stage) return { Def = { Rarity = rarity, Role = role }, "
                        "Level = level, Tier = tier, Stage = stage } end")
    lua_table = rt.eval("function() return {} end")
    tier_names = {1.0: "Normal", 1.5: "Golden", 2.5: "Rainbow"}
    pad_diffs = income_diffs = 0
    for trial in range(400):
        st = {}
        stars = rng.choice([0, 0, 0, 1, 2, 3, 5])
        legacy_prices = stars > 0 and rng.random() < 0.3
        legacy_slots = rng.choice([None, None, rng.randint(1, 8)])
        for sid in STATION_ORDER:
            if rng.random() < 0.7:
                st[sid] = rng.randint(0, STATIONS[sid].max)
        h = lua_home(stars, legacy_prices or None, legacy_slots)
        for k, v in st.items():
            h.Stations[k] = v
        want = [(sid, nxt, price, lock) for (sid, nxt, price, lock) in pads(st, stars, legacy_prices)]
        got = [(q.StationId, q.NextLevel, q.Price, q.Locked) for q in lua_list(cat.AvailablePads(h)) if q.StationId != "Prestige"]
        if want != got:
            pad_diffs += 1
            if pad_diffs <= 3:
                problems.append("pads differ for %r (stars %d, legacy prices %s):\n      sim     %r\n      catalog %r" % (st, stars, legacy_prices, want, got))
        for sid in STATION_ORDER:
            for lvl in range(1, STATIONS[sid].max + 1):
                if price_of(sid, lvl, stars, legacy_prices) != cat.PriceAt(sid, lvl, h):
                    pad_diffs += 1
                    if pad_diffs <= 3:
                        problems.append("PriceAt(%s, %d) stars %d legacy %s: sim %r, catalog %r" % (
                            sid, lvl, stars, legacy_prices, price_of(sid, lvl, stars, legacy_prices), cat.PriceAt(sid, lvl, h)))
        pets = []
        for _ in range(rng.randint(0, 14)):
            ri = rng.randrange(7)
            pet = new_pet(ri, rng.random() < 0.5)
            pet["level"] = rng.randint(1, PET_XP[0])
            pet["tier"] = rng.choice([1.0, 1.0, 1.5, 2.5])
            pet["evo"] = rng.choice([0, 0, 1, 2])
            pets.append(pet)
        entries = lua_table()
        for i, pet in enumerate(sorted(pets, key=lambda q: -power(q))):
            entries[i + 1] = lua_entry(RARITIES[pet["r"]], "Economy" if pet["econ"] else "Combat", pet["level"], tier_names[pet["tier"]], pet["evo"])
        a = income(st, pets, stars, legacy_slots or 0)
        b, parts = cat.IncomePerSecond(h, entries)
        checks = [("IncomePerSecond", a, b), ("FoodOf", food(st), cat.FoodOf(h)), ("LuckyChance", lucky_chance(st), cat.LuckyChance(h)),
                  ("GardenSlots", slots(stars, legacy_slots or 0, st.get("Garden", 0)), cat.GardenSlots(h)),
                  ("PileSeconds", pile_seconds(st), cat.PileSeconds(h)), ("ScoopRadius", scoop_radius(st), cat.ScoopRadius(h)),
                  ("TrainingSlots", TRAINING_SLOTS[st["Gym"] - 1] if st.get("Gym", 0) else 0, cat.TrainingSlots(h)),
                  ("OfflineEarnings", offline_earnings(st, 5000, 37.5), cat.OfflineEarnings(h, 5000, 37.5)[0])]
        for name, x, y in checks:
            if abs(float(x) - float(y)) > 1e-6 * max(1.0, abs(float(x))):
                income_diffs += 1
                if income_diffs <= 5:
                    problems.append("%s differs for %r (stars %d, legacy slots %r): sim %r, catalog %r" % (name, st, stars, legacy_slots, x, y))
        after = {}
        for k, v in cat.StationsAfterPrestige(h.Stations).items():
            after[k] = v
        want_after = stations_after_prestige({k: v for k, v in st.items() if v > 0})
        if after != want_after:
            income_diffs += 1
            if income_diffs <= 5:
                problems.append("StationsAfterPrestige(%r): sim %r, catalog %r" % (st, want_after, after))
    ok, probs = cat.Validate()
    if not ok:
        for pr in lua_list(probs):
            problems.append("Validate: " + pr)
    if problems:
        print("sim_tycoon --check: %d difference(s)" % len(problems))
        for pr in problems:
            print("  " + pr)
        return 1
    print("sim_tycoon --check: the catalog matches the sim constants (%d stations, the effect tables, Coins, Prestige, "
          "Food Machine, Training, pet data); AvailablePads (with star prices and LegacyPrices), PriceAt, FoodOf, "
          "GardenSlots, IncomePerSecond, PileSeconds, ScoopRadius, OfflineEarnings and StationsAfterPrestige match "
          "the sim on 400 random homes; FeedXp / FeedPrice / TrainCost / TrainSeconds match at every level and rank; "
          "Validate() passes" % len(order))
    return 0


# ------------------------------------------------------------------------------------------------
# --migrate: Phase 3 homes on their first Phase 4 login (the port of synth/veteran_check.py)
# ------------------------------------------------------------------------------------------------
def load_phase3_sim():
    """The frozen Phase 3 sim (tools/fixtures/sim_tycoon_phase3.py), imported by path. It computes HERE / ROOT from
    its own location (tools/fixtures), which only its --check / --plan loaders use; --migrate calls its pure model
    functions only (simulate, home_level, income, pads, GARDEN_SLOTS, RARITY_SCALE)."""
    path = os.path.join(HERE, "fixtures", "sim_tycoon_phase3.py")
    spec = importlib.util.spec_from_file_location("sim_tycoon_phase3", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_out(st, stars, legacy_prices):
    """No dead end: buying every unlocked pad (cheapest first, cash unlimited) reaches the prestige."""
    st = dict(st)
    for _ in range(400):
        if can_prestige(st):
            return True
        open_pads = [q for q in pads(st, stars, legacy_prices) if q[3] is None]
        if not open_pads:
            break
        best = min(open_pads, key=lambda q: q[2])
        st[best[0]] = best[1]
    return can_prestige(st)


def run_migrate(n=300, seed=5):
    OLD = load_phase3_sim()
    rng = random.Random(seed)
    rows = []
    for _ in range(n):
        runs = rng.choice([1, 1, 1, 2, 3])
        minutes = rng.randint(3, 160)
        res = OLD.simulate(seed=rng.randint(1, 10 ** 6), runs=runs, max_minutes=(runs - 1) * 90 + minutes)
        st = dict(res.final_stations)
        stars = res.stars
        old_pets = res.pets  # Phase 3: Economy pets only ({rarity, base, level}); Combat pets earned nothing there
        old_hl = OLD.home_level(st)
        old_inc = OLD.income(st, old_pets, stars)
        # the one-time migration (section 4.3)
        old_slots = OLD.GARDEN_SLOTS[st["Garden"] - 1] if st.get("Garden", 0) else 0
        legacy_slots = old_slots if old_slots > GARDEN_BASE + GARDEN_PER_STAR * stars else 0
        legacy_prices = stars > 0
        new_hl = home_level(st)
        pets = [new_pet(RARITIES.index(p["rarity"]), True) for p in old_pets]
        for p, op in zip(pets, old_pets):
            p["level"] = op["level"]
        open_slots = slots(stars, legacy_slots, st.get("Garden", 0))
        # the pets the old garden held (its slots, best old incomes first) keep their places; Combat pets are ignored
        kept = sorted(pets, key=lambda p: -power(p))[:min(old_slots, len(pets))][:open_slots]
        inc_kept = food(st) / MEAL_SECONDS * sum(power(p) for p in kept) * lucky_ev(st) * PRESTIGE_MULTIPLIER ** stars
        # after the welcome toast the veteran fills every open place with their best Economy pets
        best = sorted(pets, key=lambda p: -power(p))[:open_slots]
        inc_best = food(st) / MEAL_SECONDS * sum(power(p) for p in best) * lucky_ev(st) * PRESTIGE_MULTIPLIER ** stars
        old_open = [q for q in OLD.pads(st, stars) if q[3] is None]
        new_open = [q for q in pads(st, stars, legacy_prices) if q[3] is None]
        rows.append(dict(hl=old_hl, hl_new=new_hl, tier=tier_of(st), stars=stars, old_inc=old_inc, inc_kept=inc_kept,
                         inc_best=inc_best, kept=len(kept), legacy=max(0, legacy_slots - (GARDEN_BASE + GARDEN_PER_STAR * stars)),
                         pets=len(pets), garden=st.get("Garden", 0),
                         old_cheapest=min([q[2] for q in old_open] or [0]), cheapest=min([q[2] for q in new_open] or [0]),
                         dead_end=not build_out(st, stars, legacy_prices)))
    failures = []
    changed = sum(1 for r in rows if r["hl"] != r["hl_new"])
    dead = sum(1 for r in rows if r["dead_end"])
    print("sim_tycoon --migrate: %d Phase 3 homes (tools/fixtures/sim_tycoon_phase3.py, stopped at random moments) on their first Phase 4 login" % len(rows))
    print("  Home Level unchanged in %d / %d homes" % (len(rows) - changed, len(rows)))
    print("  no dead end (cheapest-first build-out reaches the prestige) in %d / %d homes" % (len(rows) - dead, len(rows)))
    print("  homes with no garden pet placed (coins 0 until they place one; the welcome toast says so): %d (of which no Garden yet: %d, no Economy pet: %d)" % (
        sum(1 for r in rows if r["kept"] == 0), sum(1 for r in rows if r["garden"] == 0), sum(1 for r in rows if r["pets"] == 0)))
    legacy = [r["legacy"] for r in rows if r["legacy"] > 0]
    print("  homes keeping extra (legacy) garden places: %d (median extra %s)" % (len(legacy), statistics.median(legacy) if legacy else 0))
    if changed:
        failures.append("Home Level changed in %d homes" % changed)
    if dead:
        failures.append("%d homes hit a dead end" % dead)
    by = {}
    for r in rows:
        by.setdefault((r["tier"], min(r["stars"], 2)), []).append(r)

    def q(v, f):
        return v[min(len(v) - 1, int(f * (len(v) - 1)))] if v else float("nan")

    print("\n  kept garden pets only (coins/s new / old):")
    print("  tier stars homes  HL(med)  old inc/s  new inc/s  ratio p10 / med / p90")
    for key in sorted(by):
        rs = [r for r in by[key] if r["kept"] > 0 and r["old_inc"] > 0]
        ratios = sorted(r["inc_kept"] / r["old_inc"] for r in rs)
        print("   %d     %d    %4d    %4.0f   %9.0f  %9.0f   %5.2f / %5.2f / %5.2f" % (
            key[0], key[1], len(by[key]), statistics.median([r["hl"] for r in by[key]]),
            statistics.median([r["old_inc"] for r in rs]) if rs else 0, statistics.median([r["inc_kept"] for r in rs]) if rs else 0,
            q(ratios, .1), q(ratios, .5), q(ratios, .9)))
    print("\n  after the veteran fills every open place with their best Economy pets (Combat pets ignored):")
    print("  tier stars homes  old inc/s  new inc/s  ratio p10 / med / p90   pad-time ratio (new price/new inc)/(old price/old inc) med")
    for key in sorted(by):
        rs = [r for r in by[key] if r["pets"] > 0 and r["old_inc"] > 0]
        if not rs:
            continue
        ratios = sorted(r["inc_best"] / r["old_inc"] for r in rs)
        tt = sorted((r["cheapest"] / max(r["inc_best"], 1e-9)) / max(1e-9, r["old_cheapest"] / r["old_inc"])
                    for r in rs if r["old_cheapest"] > 0 and r["cheapest"] > 0)
        med = q(tt, .5)
        print("   %d     %d    %4d   %8.0f   %8.0f   %5.2f / %5.2f / %5.2f        %5.2f %s" % (
            key[0], key[1], len(rs), statistics.median([r["old_inc"] for r in rs]), statistics.median([r["inc_best"] for r in rs]),
            q(ratios, .1), q(ratios, .5), q(ratios, .9), med, "" if (not tt or med <= 1.0) else "<- slower"))
        if tt and med > 1.0:
            failures.append("tier %d / stars %d: median pad-time ratio %.2f > 1.0" % (key[0], key[1], med))
    print("\n%s" % ("MIGRATION OK (Home Level unchanged, no dead end, median pad-time ratio <= 1.0 in every tier / star bucket)"
                    if not failures else "MIGRATION PROBLEMS: " + "; ".join(failures)))
    return 0 if not failures else 1


# ------------------------------------------------------------------------------------------------
# --plan: the yard from above
# ------------------------------------------------------------------------------------------------
def run_plan(path):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        sys.exit("--plan needs Pillow:  pip install Pillow")
    rt, cat = load_catalog()
    mul = rt.eval("function(cf, v) return cf * v end")  # CFrame * Vector3 in Lua (lupa tables have no Python operators)
    S = 12  # pixels per stud
    half = cat.Layout.Half
    pad_size = cat.Layout.PadSize
    margin = 70
    size = int(2 * half * S + 2 * margin)
    img = Image.new("RGB", (size, size + 40), (52, 120, 70))
    dr = ImageDraw.Draw(img)

    def font(px):
        for name in ("DejaVuSans-Bold.ttf", "DejaVuSans.ttf"):
            try:
                return ImageFont.truetype(name, px)
            except OSError:
                continue
        return ImageFont.load_default()

    f_small, f_mid, f_big = font(11), font(13), font(18)

    # plot-local (x, z) -> image: the gate (-Z) at the BOTTOM, +X to the right
    def P(x, z):
        return (margin + (x + half) * S, margin + (half - z) * S)

    def rect(x0, x1, z0, z1, **kw):
        a, b = P(x0, z1), P(x1, z0)
        dr.rectangle([a[0], a[1], b[0], b[1]], **kw)

    rect(-half, half, -half, half, fill=(98, 170, 92))
    for i in range(6):  # mowed stripes
        z0 = -half + i * 2 * half / 6
        if i % 2:
            rect(-half, half, z0, z0 + 2 * half / 6, fill=(110, 182, 100))
    # paths
    for p in lua_list(cat.Layout.Paths):
        a, b, w = p.Start, p.Finish, p.Width
        x0, x1 = min(a.X, b.X) - (w / 2 if a.X == b.X else 0), max(a.X, b.X) + (w / 2 if a.X == b.X else 0)
        z0, z1 = min(a.Z, b.Z) - (w / 2 if a.Z == b.Z else 0), max(a.Z, b.Z) + (w / 2 if a.Z == b.Z else 0)
        rect(x0, x1, z0, z1, fill=(196, 188, 170))
    # fence + gate
    a, b = P(-half, half), P(half, -half)
    dr.rectangle([a[0], a[1], b[0], b[1]], outline=(110, 80, 50), width=4)
    gw = cat.Layout.GateWidth
    rect(-gw / 2, gw / 2, -half - 0.6, -half + 0.6, fill=(196, 188, 170))
    for s in (-1, 1):
        rect(s * 7.2 - 1.3, s * 7.2 + 1.3, -half - 1.3, -half + 1.3, fill=(150, 150, 160))
    gx, gy = P(0, -half - 3)
    dr.text((gx, gy), "GATE (street side)", fill=(255, 255, 255), font=f_mid, anchor="mt")
    sp = cat.Layout.Spawn
    sx, sy = P(sp.X, sp.Z)
    dr.ellipse([sx - 6, sy - 6, sx + 6, sy + 6], outline=(255, 255, 255), width=2)
    dr.text((sx + 9, sy), "spawn", fill=(255, 255, 255), font=f_small, anchor="lm")

    palette = {"Plant": (120, 200, 110), "Magnet": (240, 196, 80), "Garden": (70, 150, 70), "FoodMachine": (232, 140, 90),
               "Training": (200, 90, 90), "Vault": (150, 150, 170), "House": (226, 214, 190), "Fusion": (170, 110, 220),
               "Arena": (210, 70, 70), "Decor": (250, 160, 200)}
    defs = [cat.ById[sid] for sid in lua_list(cat.Order)] + [cat.PrestigePad]
    rect_fn = cat.FootprintRect
    for d in defs:
        slot = d.Slot
        r = rect_fn(slot.CFrame, slot.Footprint)
        col = palette.get(d.Kind, (255, 255, 255))
        if slot.Perimeter:
            a, b = P(r[1] + 0.8, r[4] - 0.8), P(r[2] - 0.8, r[3] + 0.8)
            dr.rectangle([a[0], a[1], b[0], b[1]], outline=col, width=3)
        elif d.Kind == "Prestige":
            pass
        elif slot.Walkable is True:
            a, b = P(r[1], r[4]), P(r[2], r[3])
            dr.rectangle([a[0], a[1], b[0], b[1]], outline=col, width=2)
        else:
            rect(r[1], r[2], r[3], r[4], fill=col, outline=(40, 40, 40))
        if d.Id == "Garden":
            # the sand walks, the 12 places, the coin points and the Welcome-back pile
            for w in lua_list(slot.Walkable):
                wr = cat.LocalRect(slot.CFrame, w.Center, w.Size)
                rect(wr[1], wr[2], wr[3], wr[4], fill=(232, 214, 160))
            for i, v in enumerate(lua_list(slot.Spots)):
                c = mul(slot.CFrame, v)
                rect(c.X - 1.5, c.X + 1.5, c.Z - 1.5, c.Z + 1.5, fill=(130, 90, 60))
                cx, cy = P(c.X, c.Z)
                dr.text((cx, cy), str(i + 1), fill=(255, 255, 255), font=f_small, anchor="mm")
            for i in range(1, len(lua_list(slot.Spots)) + 1):
                c = mul(slot.CFrame, cat.CoinPoint(i))
                cx, cy = P(c.X, c.Z)
                dr.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(255, 210, 60), outline=(120, 80, 0))
            wp = slot.WelcomePile
            cx, cy = P(wp.X, wp.Z)
            dr.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=(255, 120, 200), outline=(120, 0, 80))
        if d.Kind != "Prestige" and not slot.Perimeter:
            c = slot.CFrame.Position
            lk = slot.CFrame.LookVector
            cx, cy = P(c.X, c.Z)
            dr.text((cx - lk.X * 14, cy + lk.Z * 14), d.Id, fill=(20, 20, 20), font=f_mid, anchor="mm")
            # an arrow from the label toward the station's front (its pad side)
            sx0, sy0 = P(c.X + lk.X * 1.2, c.Z + lk.Z * 1.2)
            ex, ey = P(c.X + lk.X * 3.6, c.Z + lk.Z * 3.6)
            dr.line([sx0, sy0, ex, ey], fill=(20, 20, 20), width=3)
            ox, oz = -lk.Z, lk.X  # perpendicular
            h1 = P(c.X + lk.X * 2.6 + ox * 0.8, c.Z + lk.Z * 2.6 + oz * 0.8)
            h2 = P(c.X + lk.X * 2.6 - ox * 0.8, c.Z + lk.Z * 2.6 - oz * 0.8)
            dr.polygon([h1, h2, (ex, ey)], fill=(20, 20, 20))
        # pad
        pc = slot.Pad.Position
        hx, hz = pad_size.X / 2, pad_size.Z / 2
        rect(pc.X - hx, pc.X + hx, pc.Z - hz, pc.Z + hz, fill=(255, 236, 90) if d.Kind != "Prestige" else (255, 140, 40), outline=(90, 70, 10))
        px, py = P(pc.X, pc.Z)
        label = d.Id.replace("Decor", "").replace("Machine", "")[:9]
        dr.text((px, py), label, fill=(30, 30, 30), font=f_small, anchor="mm")
    # reachability
    reach = cat.ReachablePads(1, 1)[0]
    bad = [k for k, v in reach.items() if not v]
    ok, probs = cat.Validate()
    status = "Validate: %s   unreachable pads: %s" % ("ok" if ok else "%d problem(s)" % len(lua_list(probs)), ", ".join(bad) or "none")
    dr.text((margin, size + 8), status, fill=(255, 255, 255), font=f_big)
    dr.text((margin, 18), "Nimbus Climb home yard (TycoonCatalog.Layout, %d x %d studs, 1 stud = %d px)" % (2 * half, 2 * half, S), fill=(255, 255, 255), font=f_big)
    dr.text((margin, 42), "yellow = buy pads, sand = garden walks, gold dots = coin piles, pink = Welcome-back pile", fill=(230, 240, 230), font=f_mid)
    img.save(path)
    print("wrote %s (%s)" % (path, status))
    if not ok:
        for pr in lua_list(probs):
            print("  " + pr)
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="Nimbus Climb tycoon economy simulation (Phase 4: pets make the money)")
    ap.add_argument("--seed", type=int, default=3, help="roulette luck of the timeline player (default 3)")
    ap.add_argument("--runs", type=int, default=3, help="prestige runs in the timeline (default 3)")
    ap.add_argument("--mc", type=int, default=120, help="Monte Carlo players (default 120)")
    ap.add_argument("--mode", choices=["random", "combat", "one"], default="random",
                    help="the timeline player's pets: random rolls, Combat pets only, or one Common pet forever")
    ap.add_argument("--ring", type=float, default=RING_BONUS, help="Champion Ring Cash as a share of garden income (default 0)")
    ap.add_argument("--feed", type=float, default=FEED_INCOME_SHARE, help="share of the coins spent on food (default 0.25)")
    ap.add_argument("--quiet", action="store_true", help="no purchase-by-purchase timeline")
    ap.add_argument("--check", action="store_true", help="compare with src/shared/TycoonCatalog.lua (lupa) and Validate()")
    ap.add_argument("--migrate", nargs="?", const=300, type=int, metavar="N",
                    help="Phase 3 homes on their first Phase 4 login (default 300)")
    ap.add_argument("--plan", metavar="PNG", help="draw the yard layout of TycoonCatalog.lua")
    args = ap.parse_args()
    if args.check:
        return run_check()
    if args.migrate:
        return run_migrate(args.migrate)
    if args.plan:
        return run_plan(args.plan)
    return run_report(args)


if __name__ == "__main__":
    sys.exit(main())
