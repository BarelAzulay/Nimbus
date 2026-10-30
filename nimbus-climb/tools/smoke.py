#!/usr/bin/env python3
"""Smoke test for Nimbus Climb v2: runs the real Lua modules against a Roblox mock (tools/robloxmock.lua).

    pip install lupa
    python3 tools/smoke.py [--only SCENARIO[,SCENARIO...]] [--seeds N] [--quick] [-v] [--strict] [--json FILE] [--echo]

Two Lua worlds are booted (each its own state, so server and client cannot cheat by sharing globals):

  server world   smoke_server.lua   mock self-test, module loading, contract.json API check, boot of Main.server.lua, lobby,
                                    players, portals, damage rules, the fall rule (landing on a lower lap), the match lifecycle
                                    (victory / defeat / timeout / abandon / leave / death / concurrent slots), persistence, DataStore
                                    orphans (leaving during an outage), shutdown, whole-run invariants
                 smoke_content.lua  PetCatalog / ItemCatalog / roulette odds, Config shape, PetBuilder for every pet
                 smoke_course.lua   5 difficulties x N seeds of GenerateLayout + ValidateLayout + an independent audit with
                                    per-difficulty statistics, cannon ballistics, CourseBuilder.Build (budget, tags, attributes)
                 smoke_economy.lua  spots, DataService / PetService economy, items, match locks (items in the countdown, pets in
                                    matches), ProfileSync shape, v1 -> v2 migration,
                                    the match lifecycle on all five difficulties, pet perks inside matches
                 smoke_hazards.lua  HazardService on real generated courses (incl. pendulum, wind, cannon, golden tokens) and the
                                    TokenService no-animation rule (Config.Tokens.ClientAnimated)
  both worlds    smoke_dev.lua      owner-only developer tools (DevService / DevController)
                 smoke_storm.lua    the Stormfang round: pet elements and the damage chart, the Stormfang pet (catalog +
                                    PetBuilder High / Low), the Storm Altar on the real lobby (budget, overlaps, bridge
                                    walk, rate-limited toast), and on the client the element pills, the Index art banner
                                    and ShowcaseController
  client world   smoke_client.lua   Main.client.lua boot, movement, HUD, toasts / results, damage fx, replay of the exact
                                    server traffic, final invariants, touch layout (390x844 phone)
                 smoke_client_v2.lua CloudUI kit, State, menu + windows + roulette reveal, hotbar, pet followers, TokenFx
                                    (client coin spin/bob), and the "no text in the middle of the screen" rule at 1920x1080 and 390x844

`--list` prints the scenario names. Every tools/smoke_*.lua must be listed in `server_files` / `client_files` below and every
scenario function must be listed in the scenario lists (smoke.py reports a failure otherwise). A scenario that crashes or runs
longer than --scenario-timeout seconds is reported as one failed check; the other scenarios still run.

Exit status is 1 when any check fails or a script raised an error.
"""
import argparse
import json
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# ---------------------------------------------------------------------------------------------------
# Lua engine
# ---------------------------------------------------------------------------------------------------
try:
    import lupa  # noqa: F401
except ImportError:
    sys.exit("smoke.py needs lupa:  pip install lupa")

ENGINES = ["luajit21", "luajit20", "lua54", "lua53", "lua55", "lua52"]


def load_engine(preferred=None):
    """LuaJIT first: it has Lua 5.1 semantics like Luau and can yield across pcall."""
    import importlib

    order = ([preferred] if preferred else []) + [e for e in ENGINES if e != preferred]
    for name in order:
        try:
            module = importlib.import_module("lupa." + name)
            return name, module
        except Exception:
            continue
    sys.exit("no usable lupa Lua engine found (pip install --upgrade lupa)")


class Reporter:
    """Collects Lua-side results (T.results) and prints them as they appear."""

    ICONS = {"ok": "  ok    ", "fail": "  FAIL  ", "warn": "  warn  ", "info": "  ..    "}

    def __init__(self, verbose, quiet_ok):
        self.verbose = verbose
        self.fails = 0
        self.warns = 0
        self.oks = 0
        self.records = []
        self.section = None

    def emit(self, status, section, name, detail):
        rec = {"status": status, "section": section, "name": name, "detail": detail}
        self.records.append(rec)
        if status == "fail":
            self.fails += 1
        elif status == "warn":
            self.warns += 1
        elif status == "ok":
            self.oks += 1
        if status == "ok" and not self.verbose:
            return
        if status == "info" and not self.verbose and not name.startswith("*"):
            return
        text = name.lstrip("*")
        line = self.ICONS.get(status, "  ?     ") + text
        if detail:
            line += "  -- " + str(detail).replace("\n", "\n            ")
        print(line)
        sys.stdout.flush()


def lua_len(t):
    try:
        return len(t)
    except Exception:
        return 0


def drain(lua_results, start, reporter):
    """Print results[start+1 ..] of the Lua results table; returns the new length."""
    n = lua_len(lua_results)
    for i in range(start + 1, n + 1):
        r = lua_results[i]
        reporter.emit(r["status"], r["section"], r["name"], r["detail"])
    return n


# ---------------------------------------------------------------------------------------------------
# Project tree -> mock instances (Rojo rules)
# ---------------------------------------------------------------------------------------------------
def script_class(filename):
    if filename.endswith(".server.lua") or filename.endswith(".server.luau"):
        return "Script", filename.rsplit(".server.", 1)[0]
    if filename.endswith(".client.lua") or filename.endswith(".client.luau"):
        return "LocalScript", filename.rsplit(".client.", 1)[0]
    if filename.endswith(".lua") or filename.endswith(".luau"):
        return "ModuleScript", filename.rsplit(".", 1)[0]
    return None, None


def fs_node(path, name, relroot):
    """Convert a file or directory under src/ into a spec dict like Rojo would."""
    if os.path.isdir(path):
        spec = {"name": name or os.path.basename(path), "class": "Folder", "children": []}
        entries = sorted(os.listdir(path))
        init = None
        for e in entries:
            if e in ("init.lua", "init.server.lua", "init.client.lua"):
                init = e
        for e in entries:
            if e == init or e.startswith(".") or e.endswith(".meta.json"):
                continue
            child = fs_node(os.path.join(path, e), None, relroot)
            if child:
                spec["children"].append(child)
        if init:
            cls, _ = script_class(init)
            spec["class"] = cls
            spec["source"] = open(os.path.join(path, init), encoding="utf-8").read()
            spec["path"] = os.path.relpath(os.path.join(path, init), ROOT)
        return spec
    cls, stem = script_class(os.path.basename(path))
    if not cls:
        return None
    return {
        "name": name or stem,
        "class": cls,
        "source": open(path, encoding="utf-8").read(),
        "path": os.path.relpath(path, ROOT),
        "children": [],
    }


def project_mounts():
    """Read default.project.json -> list of (instance path under the DataModel, directory)."""
    mounts = []
    with open(os.path.join(ROOT, "default.project.json"), encoding="utf-8") as fh:
        project = json.load(fh)

    def walk(node, path):
        for key, value in node.items():
            if key.startswith("$"):
                continue
            sub = path + [key]
            if isinstance(value, dict):
                if "$path" in value:
                    mounts.append(("/".join(sub), os.path.join(ROOT, value["$path"])))
                walk(value, sub)

    walk(project["tree"], [])
    return mounts


# ---------------------------------------------------------------------------------------------------
# Lua value helpers
# ---------------------------------------------------------------------------------------------------
def to_lua(rt, value):
    """Recursively convert Python lists/dicts into Lua tables."""
    if isinstance(value, dict):
        return rt.table_from({k: to_lua(rt, v) for k, v in value.items()})
    if isinstance(value, (list, tuple)):
        return rt.table_from([to_lua(rt, v) for v in value])
    return value


def lua_to_py(value, depth=0):
    """Convert simple Lua tables back to Python (for the replay log)."""
    if depth > 6:
        return None
    t = type(value).__name__
    if t == "_LuaTable":
        keys = list(value.keys())
        if keys and all(isinstance(k, (int, float)) for k in keys):
            return [lua_to_py(value[k], depth + 1) for k in sorted(keys)]
        return {k: lua_to_py(value[k], depth + 1) for k in keys}
    return value


# ---------------------------------------------------------------------------------------------------
# A Lua world (one runtime = one server or one client)
# ---------------------------------------------------------------------------------------------------
class World:
    def __init__(self, engine_module, engine_name, context, args, api, contract, touch=False, viewport=None):
        self.context = context
        self.rt = engine_module.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
        self.engine = engine_name
        g = self.rt.globals()
        src = open(os.path.join(HERE, "robloxmock.lua"), encoding="utf-8").read()
        g.MOCK_SRC = src
        mock_loader = self.rt.eval(
            "function() local load_ = loadstring or load; local f, e = load_(MOCK_SRC, '=tools/robloxmock.lua'); "
            "if not f then error(e, 0) end; return f() end"
        )
        self.Mock = mock_loader()
        g.Mock = self.Mock
        self.Mock.Configure(
            self.rt.table_from(
                {
                    "creatableClasses": self.rt.table_from(api["creatableClasses"]),
                    "services": self.rt.table_from(api["services"]),
                    "options": self.rt.table_from(
                        {
                            "StrictMembers": bool(args.strict_members),
                            "Echo": bool(getattr(args, "echo", False)),
                            "Watchdog": not args.no_watchdog,
                            "StepSize": 1.0 / args.fps,
                            "SliceLimit": args.slice_limit,
                        }
                    ),
                }
            )
        )
        boot_opts = {"localName": "Tester", "localUserId": 4242, "touch": bool(touch)}
        self.Mock.Boot(context, self.rt.table_from(boot_opts))
        if viewport:
            self.Mock.SetViewport(viewport[0], viewport[1])
        if not args.no_watchdog:
            self.Mock.EnableMainWatchdog()
        self.mount_sources()
        g.CONTRACT = to_lua(self.rt, contract)
        g.ARGS = self.rt.table_from(
            {
                "seeds": args.seeds,
                "verbose": bool(args.verbose),
                "quick": bool(args.quick),
                "context": context,
            }
        )

    def mount_sources(self):
        """Mount src/ below the DataModel exactly where default.project.json says."""
        roots = {}
        for inst_path, directory in project_mounts():
            name = inst_path.split("/")[-1]
            parent_path = "/".join(inst_path.split("/")[:-1])
            if not os.path.isdir(directory):
                print("  warning: %s is mapped to %s which does not exist" % (inst_path, directory))
                continue
            spec = fs_node(directory, name, directory)
            parent = self.Mock.GetPath(parent_path, "Folder")
            self.Mock.Mount(parent, to_lua(self.rt, spec))
            roots[os.path.basename(directory)] = inst_path
        self.rt.globals().ROOTS = self.rt.table_from(roots)

    def load_scenarios(self, filenames):
        """Loads smoke_common.lua once, then every scenario file; the returned table merges them all."""
        if isinstance(filenames, str):
            filenames = [filenames]
        loader = self.rt.eval(
            "function(src, name) local load_ = loadstring or load; local f, e = load_(src, '='..name); "
            "if not f then error(e, 0) end; return f end"
        )
        merge = self.rt.eval("function(a, b) for k, v in pairs(b) do a[k] = v end return a end")
        if not getattr(self, "_common_loaded", False):
            common = open(os.path.join(HERE, "smoke_common.lua"), encoding="utf-8").read()
            loader(common, "tools/smoke_common.lua")()
            self._common_loaded = True
        merged = None
        for filename in filenames:
            src = open(os.path.join(HERE, filename), encoding="utf-8").read()
            chunk = loader(src, "tools/" + filename)
            part = chunk()
            merged = part if merged is None else merge(merged, part)
        return merged


def main():
    ap = argparse.ArgumentParser(description="Nimbus Climb smoke test (Roblox mock on lupa)")
    ap.add_argument("--only", help="comma separated scenario names (default: all)")
    ap.add_argument("--list", action="store_true", help="list scenario names and exit")
    ap.add_argument("--seeds", type=int, default=300, help="layout seeds per difficulty (default 300)")
    ap.add_argument("--quick", action="store_true", help="shorter runs (fewer seeds, skip the long timeout wait)")
    ap.add_argument("-v", "--verbose", action="store_true", help="print passing checks too")
    ap.add_argument("--strict", action="store_true", help="warnings fail the run")
    ap.add_argument("--echo", action="store_true", help="print the game's print() / warn() output and script errors as they happen (debugging)")
    ap.add_argument("--strict-members", action="store_true", help="unknown Instance members raise errors (like Roblox) instead of being recorded")
    ap.add_argument("--engine", help="lupa engine (luajit21, lua54, ...) default: luajit21")
    ap.add_argument("--fps", type=float, default=30.0, help="simulation steps per fake second (default 30)")
    ap.add_argument("--scenario-timeout", type=float, default=600.0, help="real seconds one scenario may run before it is aborted (default 600)")
    ap.add_argument("--slice-limit", type=float, default=30.0, help="real seconds a script may run without yielding")
    ap.add_argument("--no-watchdog", action="store_true", help="disable the runaway-loop debug hooks (faster)")
    ap.add_argument("--json", metavar="FILE", help="write all results as JSON")
    ap.add_argument("--root", metavar="DIR", help="project root to test (default: the repo this script lives in)")
    ap.add_argument("--mesh", action="store_true", help="fixture mesh mode: pet scenarios on Blender-mesh pets (fake MeshIds + templates from src/shared/MeshManifests; env NC_MESH_FIXTURES=1)")  # [owner: runtime-pets, Phase 6 W2]
    args = ap.parse_args()
    if args.root:
        global ROOT
        ROOT = os.path.abspath(args.root)
    if args.quick and args.seeds == 300:
        args.seeds = 40

    engine_name, engine = load_engine(args.engine)
    with open(os.path.join(HERE, "contract.json"), encoding="utf-8") as fh:
        contract = json.load(fh)
    with open(os.path.join(HERE, "roblox-api.json"), encoding="utf-8") as fh:
        api = json.load(fh)

    reporter = Reporter(args.verbose, True)
    started = time.time()
    print("Nimbus Climb smoke test  (Lua engine: %s, %d layout seeds/difficulty)" % (engine_name, args.seeds))

    only = set(x.strip() for x in args.only.split(",")) if args.only else None
    replication = None

    # -- server world ----------------------------------------------------------------------------
    # Pure content scenarios (need only the loaded modules):
    pure_scenarios = ["contract", "catalog", "config_shape", "petbuilder", "evolved", "layouts", "cannon", "courses"]
    server_scenarios = (
        ["mock_selftest", "load_modules"]
        + pure_scenarios
        + [
            "boot", "lobby", "players", "spots", "economy", "items", "match_locks", "profile_sync", "migration", "portals", "damage_rules",
            "fall_rule", "match_victory", "match_defeat", "match_timeout", "match_abandon", "match_leave", "match_death",
            "match_slots", "match_difficulties", "match_pets", "hazards", "persistence", "data_orphans", "dash_relay", "shutdown",
            "final_checks",
        ]
    )
    server_files = ["smoke_server.lua", "smoke_content.lua", "smoke_course.lua", "smoke_economy.lua", "smoke_hazards.lua"]
    client_scenarios = [
        "client_load", "client_ui_kit", "client_state", "client_input", "client_hud", "client_notify", "client_damage",
        "client_menu", "client_hotbar", "client_pets", "client_tokens", "client_layout_rule", "client_replay", "client_final",
    ]
    mobile_scenarios = ["client_mobile"]
    client_files = ["smoke_client.lua", "smoke_client_v2.lua"]
    server_files.append("smoke_dev.lua"); client_files.append("smoke_dev.lua"); server_scenarios.insert(server_scenarios.index("final_checks"), "dev_tools"); client_scenarios.insert(client_scenarios.index("client_final"), "client_dev"); client_scenarios.insert(client_scenarios.index("client_final"), "client_dev_pets"); mobile_scenarios.append("client_dev_mobile")  # owner-only developer tools (smoke_dev.lua: both worlds, ARGS.context picks the half)
    # the Stormfang round (smoke_storm.lua: both worlds, ARGS.context picks the half): elements + the Stormfang pet are
    # content scenarios (after petbuilder), the Storm Altar runs on the booted lobby (after lobby), client_storm checks
    # the element pills, the Index art banner and ShowcaseController
    server_files.append("smoke_storm.lua"); client_files.append("smoke_storm.lua")
    pure_scenarios += ["storm_elements", "storm_pet"]
    server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = ["storm_elements", "storm_pet"]
    server_scenarios.insert(server_scenarios.index("lobby") + 1, "storm_altar")
    client_scenarios.insert(client_scenarios.index("client_final"), "client_storm")
    server_files.append("smoke_polish_portals.lua"); client_files.append("smoke_polish_portals.lua"); server_scenarios.insert(server_scenarios.index("final_checks"), "polish_portals"); client_scenarios.insert(client_scenarios.index("client_final"), "client_polish_portals"); mobile_scenarios.append("client_polish_portals_mobile")  # portal lock-in + outside countdown (smoke_polish_portals.lua: both worlds)
    client_files.append("smoke_polish_guitool.lua"); client_scenarios.insert(client_scenarios.index("client_final"), "client_gui_dump")  # offline GUI renderer: tools/dump_gui.lua walks PlayerGui + the widget gallery (smoke_polish_guitool.lua: client world)
    client_files.append("smoke_polish_vitals.lua"); client_scenarios.insert(client_scenarios.index("client_final"), "client_polish_vitals"); mobile_scenarios.append("client_polish_vitals_mobile"); mobile_scenarios.append("client_polish_matchpanel_mobile")  # HP / stamina vitals card + the match panel on touch screens (smoke_polish_vitals.lua: client + phone worlds)
    server_files.append("smoke_polish_worldtext.lua"); client_files.append("smoke_polish_worldtext.lua"); server_scenarios.insert(server_scenarios.index("final_checks"), "polish_worldtext"); client_scenarios.insert(client_scenarios.index("client_final"), "client_polish_worldtext")  # World text rule: census of every BillboardGui / SurfaceGui, home nameplates (smoke_polish_worldtext.lua: both worlds)
    server_files.append("smoke_polish_data.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["polish_data_outage", "polish_data_dev_reset", "polish_data_fwdcompat"]  # save-system release fixes: provisional failed loads, dev reset overwrite, forward-compatible saves (smoke_polish_data.lua: server world only, before shutdown so the autosave / orphan retries still run)
    client_files.append("smoke_release_client.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_release_pets", "client_release_roulette"]; mobile_scenarios.append("client_release_touch_mobile")  # release pass (client): welded pet followers + build time budgets, Low roulette strip + pre-sculpted pools, touch menu vs thumbstick, tutorial vs HP card, menu pointer (smoke_release_client.lua: client + phone worlds)
    server_files.append("smoke_p2_data.lua"); client_files.append("smoke_p2_data.lua"); pure_scenarios += ["p2data_keys"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2data_keys"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p2data_profile", "p2data_save"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2data")  # Phase 2 pet keys + data: PetKeys, DataService schema / migration / merge rules / API, key-aware PetService, State + PetController (smoke_p2_data.lua: both worlds)
    server_files.append("smoke_p4_economy.lua"); pure_scenarios += ["p2_economy"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2_economy")  # Phase 4 economy (the scenario keeps its Phase 2 name for the anchors): TycoonCatalog API / Validate (+ each Phase 4 rule) / the 18 stations of contract table 3.1 / a fresh home shows only the free Pet Garden / the re-rooted tree / star prices + LegacyPrices / rainbow coins (FoodOf, PetPower, IncomePerSecond, GardenSlots, piles, radius, offline) / Food Machine / Training Place / compat aliases / garden layout, and the catalog == the constants and formulas of tools/sim_tycoon.py (smoke_p4_economy.lua: server world, pure)
    server_files.append("smoke_p2_tycoon.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p2tycoon_claim", "p2tycoon_progress", "p2tycoon_exploits", "p2tycoon_offline"]  # Phase 2 tycoon homes: claim by E at the gate, buy pads, income tick + Collector, house tiers, prestige, garden, offline earnings, exploit attempts (smoke_p2_tycoon.lua: server world, booted)
    server_files.append("smoke_p4_garden.lua"); client_files.append("smoke_p4_garden.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p4garden_coins", "p4garden_scoop", "p4garden_ledger"]; client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p4garden_heaps", "client_p4garden_scoop", "client_p4garden_cards"]  # Phase 4 rainbow coins (ARCHITECTURE_V3.md "Phase 4 build contract" 3.1-3.3, 5.3, X1-X6 / X20): the free Pet Garden, a meal every 8 s per open place with a pet (Economy x1.6, the stored evolution stage, Lucky coins by Garden level, the pile cap -> the pet naps), the coin ledger exactly once (Home.CollectorCash is the bank, the 0.25 s owner-proximity scoop within ScoopRadius, a second player on the lawn scoops nothing, Cash + bank constant, CoinsScooped), GardenSet for any role with the training / battle refusals and the X5 timer rule, resting keys above the open count, LegacySlots, the Welcome-back pile across leave + rejoin / offline coins / a rebase / a provisional load / a DataStore outage, Prestige mid-pile (Garden kept at L1, +1 place), the veteran welcome toast once, ClearCoins; on the client HomeFx's heaps following CoinPiles (others' dimmed and still, pools <= 40), the owner-only scoop zip + the "+$" label at the pile, the one-time visitor hint, the garden / training PetCards (smoke_p4_garden.lua: both worlds, server scenarios booted)
    server_files.append("smoke_p4_portal.lua"); client_files.append("smoke_p4_portal.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p4portal_home", "p4portal_refusals"]; client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p4portal_ring", "client_p4portal_mesh", "client_p4portal_dive"]  # Phase 4 home portal (3.10 / 3.11 / X18): HomeAction "GoHome" writes HomePortal "x,y,z,yaw,closesAt" 6 studs ahead for 10 s with no server part, only the owner walking in is teleported within 6 studs of SpawnCFrame (PortalArrived, PortalUsed), another player at the point stays, expiry, the 3 s cooldown, GoToSpot / GoHome without a home open it toward a free gate; refused in a match / InBattle / a portal party / dead, an open portal closes when the owner enters a battle, SpotService.Teleport and GoToSpot refuse InBattle, junk arguments; on the client HomePortalFx's ring from the attribute (owner / faded / far, shrink on use or expiry, the 22 px name tag), the arrival ring and the followers' dive (smoke_p4_portal.lua: both worlds, server scenarios booted)
    server_files.append("smoke_p2_homeworld.lua"); client_files.append("smoke_p2_homeworld.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p2home_art", "p2home_plot"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2home")  # Phase 2 + 4 + 5 home world: HomeBuilder station art per level (the 40-level Berry Farm, the Garden with 12 beds + the Food Bowl, Food Machine + MachineSign, Training mats, House tiers, Fusion, Arena Gate, Fence / Fountain looks; budgets of 3.6), a test plot (claim gate, pads, SetGarden / SetTraining, <= 950 parts, roaming paths clear, the 6.4 art rules, no server animation) and HomeFx on the client (smoke_p2_homeworld.lua: both worlds)
    server_files.append("smoke_p2_care.lua"); pure_scenarios += ["p2care_stats"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2care_stats")  # pet stats: PetCatalog.GetStats(petId, level, tier), the Phase 4 coin power (TycoonCatalog.PetPower: Economy / Combat 1.6, the stored evolution stage) and the level caps (every rarity 100) (smoke_p2_care.lua: server world, pure)
    server_files.append("smoke_p4_care.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p4care_feed", "p4care_evolve", "p4care_train", "p4care_load", "p4care_exploits"]  # Phase 4 pet care (ARCHITECTURE_V3.md "Phase 4 build contract" 3.4-3.7 / 5.1-5.4 / 7): the Food Machine (no machine refused before paying, FeedPrice / FeedXp per level and machine level, "Level up" batches priced feed by feed, leftovers first and free, the cap 100, a failed XP write refunds, Fed, ONE toast per XP grant with "Ready to evolve!", Cook / GymSet answer one toast, the FeedPrompt / TrainPrompt), EVOLVE (19 / 20 / 49 / 50 x rarities, Common never stage 2, the stored stage, Evolved, OpenPanel("Evolve") to that client only, EquippedInfo, refusals, a training pet may evolve), the Training Place (Train pays / unequips every copy / clears the Garden slot / remembers From, the lock in Equip / GardenSet / ActiveTeamKeys with the preset kept, spots, rank 10, completion by the tick returning the pet, Stop refunds once, a due job stops into a completion), the load paths (a rejoin finishes the job with "Training done while you were away!", two servers completing one job = one rank on a real second DataService copy, a prestige keeps the job, Home.Gym emptied once with one toast, ClearSessions) and exploit attempts (junk / spam / someone else's pets and prompts / Cash never negative) (smoke_p4_care.lua: server world, booted)
    server_files.append("smoke_p2_fusion.lua"); client_files.append("smoke_p2_fusion.lua"); pure_scenarios += ["p2fusion_looks"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2fusion_looks"); server_scenarios[server_scenarios.index("p2care_kitchen" if "p2care_kitchen" in server_scenarios else "shutdown"):server_scenarios.index("p2care_kitchen" if "p2care_kitchen" in server_scenarios else "shutdown")] = ["p2fusion_upgrade", "p2fusion_mix", "p2fusion_exploits"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2fusion")  # Phase 2 Fusion Machine (Phase 4: no Gym placement of a fused result, training inputs refused, the evolution stage and training ranks carried): PetBuilder Golden / Rainbow finishes + hybrid looks (budgets, traits, seeds, nothing floats), FusionService Upgrade / Mix (requirements, costs, records, equipped / Garden copies, atomic, remote junk / spam / proximity) and the FusionController window (smoke_p2_fusion.lua: both worlds)
    server_files.append("smoke_p2_gems.lua"); pure_scenarios += ["p2gems_odds"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2gems_odds"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p2gems_receipts", "p2gems_policy", "p2gems_roulettes", "p2gems_altar"]  # (before the care block: p2care_exploits leaves a dish cooking for p2care_shutdown, and these scenarios advance the clock past its cook time) Phase 2 gems: GemService (gem packs: id 0 hidden, idempotent ProcessReceipt with GemReceipts incl. loading / provisional profiles and failed saves, validated PromptPurchase), PolicyService paid-random-items checks, gem-priced roulettes + the gems-only Secret roulette (Secret pets only from it), the Storm Altar prompt (smoke_p2_gems.lua: server world)
    server_files.append("smoke_p2_ui.lua"); client_files.append("smoke_p2_ui.lua"); pure_scenarios += ["p2ui_content"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2ui_content"); server_scenarios.insert(server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"), "p2ui_tutorial"); client_scenarios.insert(client_scenarios.index("client_final"), "client_p2ui"); mobile_scenarios.append("client_p2ui_mobile")  # Phase 2 UI: the home chapter of the tutorial + NPC tips (content), the tutorial flow claim -> press -> collect -> kitchen (pad path) -> feed on the booted game (before the care block, which leaves a dish cooking for its shutdown check), the Home window / Pets actions / Feed picker / Shop Gems tab / Index Fusions tab on the client and the same windows on a 390x844 phone (smoke_p2_ui.lua: both worlds)
    server_files.append("smoke_p2_flow.lua"); client_files.append("smoke_p2_flow.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p2flow_arrive", "p2flow_build", "p2flow_prestige", "p2flow_fusion_gems", "p2flow_rejoin"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2flow")  # Phase 2 end-to-end flow: three players (new, restricted, a migrated v3 save) through the tutorial, claims, presses, Collector, Garden, Kitchen + feeding, Gym, house tiers, prestige, the DataStore merge after a prestige (both ways), Fusion after prestige, gem receipts, the Secret roulette, leave + rejoin restoring the build on another plot (server world, before the care block); on the client the tutorial card after the finale (a restarted tutorial shows again) (smoke_p2_flow.lua: both worlds)
    server_files.append("smoke_p2_visual.lua"); client_files.append("smoke_p2_visual.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p2visual_art", "p2visual_plot"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2visual")  # Phase 2 + 4 + 5 visual pass: the 6.4 art rules on every station level (materials, muted faces, NC_Detail decor), the farm berry rows, Fusion contract parts, Garden beds, Training front, Food Machine hopper, House roofs / rose window, the staked-out house lot, ghosts, the Prestige pad sign, and on the client HomeFx / Fusion window checks (smoke_p2_visual.lua: both worlds)
    server_files.append("smoke_fix_server.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["fixsrv_training_prestige", "fixsrv_receipt_merge", "fixsrv_prestige_merge", "fixsrv_prestige_pad"]  # review fixes (server): a prestige keeps the running training jobs, clears the coin piles and keeps the Garden at L1 (no refund, no double rank), a gem purchase granted once across servers (+ thanks after the save), Cash / prestige Gems follow the prestige rule in the cross-server merge, the Prestige pad only opens the confirmation (smoke_fix_server.lua: server world)
    server_files.append("smoke_fix_leave.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["fixleave_ring", "fixleave_rejoin"]  # leave save order (server): DataService's leave save runs after the other PlayerRemoving handlers, so a leave-time write made when nothing else was unsaved (Phase 4: BattleService's Ring.Runs + 1 for a run left between two rounds, a late handler's write) is saved instead of lost with the dropped entry, also through an outage (orphan retry); a rejoin in the same frame keeps the entry (smoke_fix_leave.lua: server world, before the care block: these advance the clock by a minute)
    client_files.append("smoke_p2_fix_client.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p2fix_signs", "client_p2fix_pets"]; mobile_scenarios.append("client_p2fix_signs_mobile")  # review fixes (client, HomeFx): pad signs laid out on the screen so none covers another's text (real perspective projection, 1920x1080 + 844x390, no flicker, rebuilt signs keep their answer, lock reasons up close) nor goes under the HUD (menu column, currency pills, vitals, hotbar, touch buttons: 844x390 in the client world and on a touch phone), garden / gym pets built under a per-frame budget (<= 3 a frame, first-time builds alone, the 4 ms time cap) with a pool for homes going out of range (smoke_p2_fix_client.lua: client world)
    server_files.append("smoke_p2_final.lua"); pure_scenarios += ["p2final_docs"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2final_docs")  # README.md matches the game it documents (smoke_p2_final.lua: server world, pure): every asked-for part of Phase 2, 3, 4 and 5 is covered (checkPhase5: the Big Sky Update section and the numbered owner checklist of ARCHITECTURE_V3.md 10.6) and its numbers (stations, house tiers, the Pet Garden, Food Machine, levels and XP, evolution, Training Place, Vault, prestige and star prices, homes from before Phase 4, fusion, roulette / gem prices, the Champion Ring, NPCs, developer tools, tutorial chapters 1-4) equal TycoonCatalog / BattleCatalog / PetCatalog / Config / NpcDialog / the services; every src script is in the project layout, every #anchor resolves
    server_files.append("smoke_p3_data.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3data_teams", "p3data_battle", "p3data_save"]  # Phase 3 data: DataService battle teams (presets, validation: owned / unique / not in the Garden or Gym / slot 4 at Prestige 1, stale keys pruned after a fusion or a Garden placement, TeamsChanged, ProfileSync Teams with Slots) and the battle record (AddTrophies floor 0, MutateBattle rules, TrialCleared as a dense boolean array), migration from Phase 2, the cross-server merge rules, provisional profiles and the developer /reset of both surviving an autosave (smoke_p3_data.lua: server world, before the care block: p3data_save advances the clock past an autosave)
    server_files.append("smoke_p4_data.lua"); server_scenarios[server_scenarios.index("p3data_save") + 1:server_scenarios.index("p3data_save") + 1] = ["p4data_growth", "p4data_save", "p4data_migrate", "p4data_dev", "p4data_rollout"]  # Phase 4 data (ARCHITECTURE_V3.md "Phase 4 build contract" section 4): PetGrowth (evolution stages, training ranks, the running Job) / Ring / Migrations schema and cleaning, MutateGrowth / MutateRing rules, provisional refusals, the cross-server merges (two servers completing one rank = one rank, Evo max, a stale Job dropped, Ring Best max / Runs delta, Migrations union, LegacySlots / LegacyPrices with the Home) on a REAL second copy of the module, the read-time training lock (ActiveTeamKeys / FieldableKeys / normalizeEquipped skip, presets kept), P3.placedCopies = Gym only, the one-time P4 migration (LegacySlots / LegacyPrices / Gym cleared / marker, idempotent, two servers, after a provisional load, the next prestige), snapshot fields, the developer /reset and /petlevel, and p4data_rollout: the frozen Phase 3 DataService (tools/fixtures/DataService_phase3.lua) saving a Phase 4 profile through the same mock store (smoke_p4_data.lua: server world, booted, right after p3data_save and before the care block: p4data_dev advances the clock past an autosave)
    server_files.append("smoke_p3_arenaworld.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3arena_world", "p3arena_boards", "p3arena_pockets", "p3arena_art", "p3arena_teleport"]  # Phase 3 arena world: ArenaBuilder (ArenaInfo contract shape, <= 2800 parts, Phase 5 art pass p3arena_art (6.4 rules on the island + ring pocket), NC_BattleZone zones sized by BattleCatalog.Zones that fit their floors at any rotation, duel pads + Portal_Trials with OpenPanel prompts, placement clear of the lobby, the bridge / portal link, readable world text), the event board + trophy leaderboard (ApplyArenaState, ticking countdowns, junk), private trial pockets (BuildPocket / FreePocket, <= 250 parts, far out in the sky), Phase 4: Portal_Ring (<= 70 parts, LobbyInfo.RingSite, RingPrompt OpenPanel = "Ring", the RingBoard pill), the Champion Ring pocket (BuildPocket(index, "Ring"): <= 220 parts, a Ring zone, ZoneAt), the safe-zone rule, and the home Arena Gate teleport (owner only, near the gate, refused in a match / battle / cooldown) (smoke_p3_arenaworld.lua: server world, booted, before the care block)
    server_files.append("smoke_p3_battleservice.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3bs_contract", "p3bs_duel", "p3bs_queue", "p3bs_raid", "p3bs_exploits", "p3bs_net"]  # Phase 3 BattleService with 2-8 simulated players: the API + BattleEnded at module load, a full trial (pocket teleport, Start / 10 Hz dense snapshots / End, first-clear and repeat rewards once, the return, forfeit, disconnect, the pocket leash), duels (challenge / decline / expiry / accept, "Lobby" payloads, ring pads, spectators in range only, rewards + PvP counters, forfeits early and late, the pair limit, a disconnect saved as a loss), the quick queue (trophy allowance), boss raids (StartRaid / status / join window / join + leave scaling the boss, EndRaid timeout loss, Double Rewards, a raid nobody joined, a full raid paid by damage tiers), exploit attempts (junk args, other units, bad slots, outside the zone, spam, two battles, teleport tricks, obby match, portal lock, rewards once) and the traffic per client (trial / duel / 8-player raid bytes per second, ~10 Hz, payload hygiene) (smoke_p3_battleservice.lua: server world, booted, before the care block: the raids advance the clock by minutes)
    server_files.append("smoke_p4_ring.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p4ring_start", "p4ring_run", "p4ring_rewards", "p4ring_ends", "p4ring_lossxp"]  # Phase 4 Champion Ring in BattleService (ARCHITECTURE_V3.md "Phase 4 build contract" 3.5 / 3.8 / 3.11 / 5.1-5.4 / X13-X17): the entry checks in order with their toasts (home, pet, fighters team -> equipped -> best owned, canBattle, the portal range, a provisional save, the start round), a single level-1 pet winning rounds 1-3 with no InBattle gap in one pocket, rewards once per round (Cash = seconds of the climber's garden income with the floor, the record x3 and the boss Tokens once, XP 20 + 6r, Ring.Best max / Runs delta, the checkpoint start, Double Rewards untouched), every end path (loss, Forfeit in an intermission vs in a fight, leave / respawn / leash / obby match / Shutdown between and during rounds: Runs + 1 once, the pocket freed, the result card data), the RingBoard attribute, the trial loss-XP gate (>= 20 s or 20% damage, never a forfeit) and EventService ignoring non-Raid results (smoke_p4_ring.lua: server world, booted, before the care block: the rounds advance the clock by minutes)
    server_files.append("smoke_p3_events.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3events_pets", "p3events_bosses", "p3events_schedule", "p3events_raid"]  # Phase 3 events: the EventOnly pets (catalog + Index, never in any roulette incl. the gems-only Secret roulette), BossBuilder (four detailed-voxel bosses at High / Low, named joints, budgets, effect points, every pose, enrage glow, telegraph colours), the EventService scheduler (ArenaState on join, the raid announced ~2 min ahead with a toast + fast ArenaState, opened through BattleService, a raid nobody joined), StartNow / EndNow, Double Rewards, the fallback raid payer (once), the event pet shout-out and the developer /raid (smoke_p3_events.lua: server world, booted, before the care block: the schedule advances the clock by minutes)
    server_files.append("smoke_p3_ui.lua"); client_files.append("smoke_p3_ui.lua"); pure_scenarios += ["p3ui_content"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p3ui_content"); server_scenarios.insert(server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"), "p3ui_tutorial"); client_scenarios.insert(client_scenarios.index("client_final"), "client_p3ui"); mobile_scenarios.append("client_p3ui_mobile")  # Phase 3 UI: tutorial chapter 3 + the battle NPC tips (content), the chapter on the booted game (arena -> team -> trial -> raid, the arrows from ArenaInfo, the reward once), the Team window (presets, slots, slot 4 at Prestige 1, picker, synergy, element wheel, power, TeamSet / TeamSelect), the Stats battle record, ArenaController (Trial window, Arena panel tabs, prompts, side cards: invites, queue, raid, countdown) on the client and the same windows on a 390x844 phone (smoke_p3_ui.lua: both worlds)
    server_files.append("smoke_p3_flow.lua"); client_files.append("smoke_p3_flow.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3flow_arrive", "p3flow_duels", "p3flow_reset", "p3flow_raid", "p3flow_rejoin", "p3flow_solo"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p3flow")  # Phase 3 end-to-end flow with 3-8 players through the remotes: teams (slot 4 at Prestige 1, Garden / Gym pets busy and pruned), a migrated Phase 2 save (its home claimed, the Arena Gate bought and used) + tutorial chapter 3 (arena -> team -> trial -> raid, the reward once), Trials 1-3 won / a trial lost / a repeat, duels by challenge (a spectator, the leaderboard + trophy board) and by queue (a forfeit, a disconnect saved as a loss), the developer /reset between battles (refused while fighting, survives the autosave), Double Rewards (developer start and the scheduled hour), the scheduled Boss Raid from the announcement to the rewards (late joiner, early leavers by LeaveRaid and by disconnect, too late, a spectator, damage tiers, gems, event pets, pet XP, paid once), rejoins restoring teams + records, a Studio Play Solo raid from the DEV button; on the client the flow's real messages replayed as Ava (BattleController trial + raid HUD and result cards, ArenaController Sent card + raid countdown, State teams / record) and Cy's real chapter-3 TutorialState (smoke_p3_flow.lua: both worlds, server chapters before the care block: they advance the clock by up to a few hours)
    server_files.append("smoke_p3_visual.lua"); client_files.append("smoke_p3_visual.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3visual_arena", "p3visual_bosses"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p3visual"); mobile_scenarios.append("client_p3visual_mobile")  # Phase 3 visual pass: crafted arena floors (sand drifts on the boss floor inside the gold line, framed element marks, worn / warm forum paving, ring drifts under the painted circle, pocket drifts, budgets kept, sign titles that fit), bosses that keep their shading and colour regions (belly, frost, ash...) within High <= 1000 / Low <= 760, and on the client the telegraph rim in the attack's saturated colour (gone after the battle), white pet names on the tinted Team / Trial cards and wide enemy cards on a portrait phone (smoke_p3_visual.lua: both worlds)
    server_files.append("smoke_p3_evolved.lua"); client_files.append("smoke_p3_evolved.lua"); pure_scenarios.append("p3evo_pets"); server_scenarios.insert(server_scenarios.index("evolved") + 1, "p3evo_pets"); server_scenarios.insert(server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"), "p3evo_devtools"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p3evo_panel", "client_p3evo_lineup"]; mobile_scenarios.append("client_p3evo_panel_mobile")  # Phase 3 event pets' evolved forms + the merged developer tools: Magma Cub / Rime Wyrmling / Hydralotl have bespoke Evolved and Evolved II looks that echo their boss (signature parts at High and Low, a same-Look twin gets the generic form, caps, wings, aura, animation, EvolutionColors, Golden / Rainbow copies, hybrids, nothing leaks to other pets); Studio Play Solo dev tools (every command has a handler + a TextChatCommand, /pets 0-2 include the event pets, /raid next to the showcase, /devhelp's two toasts list every command and fit); the DEV panel lists every button in order and scrolls at 1920x1080 / 1280x720 / 390x844 / 844x390, Start Boss Raid sends DevCommand('raid'), the help toasts show whole and readable; DevPetShow's Evolved II lineup with the event pets (smoke_p3_evolved.lua: both worlds)
    server_files.append("smoke_p3_fix_server.lua"); client_files.append("smoke_p3_fix_server.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3fixsrv_duel", "p3fixsrv_raid", "p3fixsrv_leave", "p3fixsrv_net16"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p3fixsrv_wire")  # Phase 3 review fixes (server): a timely RETREAT escapes Lines and Circles (lines end past their target, parked teams step aside, a player team resumes ATTACK by itself), Trial 1 = one handicapped pet every single level-1 pet beats + the honest tutorial "team" step, practice duels / no rewards for stomping an idle loser, no raid reward under Raid.MinShare + a weighted head count + Fighters in the raid toast, a void duel when both leave + BattleService.Shutdown, the delta snapshot wire form (16 raiders under 20 KB/s, spectators at 5 Hz, decode round trip) and its decoding in BattleController (smoke_p3_fix_server.lua: both worlds, server chapters before the care block: the raids advance the clock by minutes)
    client_files.append("smoke_p3_fix_client.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p3fixcli_telegraph", "client_p3fixcli_retreat", "client_p3fixcli_landscape", "client_p3fixcli_devhelp", "client_p3fixcli_tutorial"]; mobile_scenarios.append("client_p3fixcli_mobile")  # Phase 3 review fixes (client): telegraph fill completes at the dodge deadline (render delay + round trip + run-out) then flashes, RETREAT! while a telegraph covers my pets; ATTACK! pulse + RESTING countdown to the sim's auto resume, SPECIAL cards say why they wait, the auto Order restores the HUD; practice / tier None / void result lines; on an 844x390 screen (window and touch phone) the team cards take the left edge where the menu tiles step aside, nothing in the screen centre, portrait / wide unchanged; the two /devhelp toasts both readable on a landscape phone (a pushed-out toast waits); an opened tutorial card never covers the vitals or the hotbar and hides behind compact battle cards (smoke_p3_fix_client.lua: client + phone worlds)
    server_files.append("smoke_p3_fixcheck.lua"); client_files.append("smoke_p3_fixcheck.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3fixchk_practice", "p3fixchk_wire"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p3fixchk_join")  # Phase 3 fix re-checks (fixcheck): a practice duel counts for nothing either way (leaving it costs no trophies / PvP loss, a double leave refunds nothing it never took), the delta snapshot stream of every receiver (fighter from the start, a spectator who joins as the 16th raider, a late spectator) equals BattleSim:Snapshot() at every T through a leaver and two minion waves, spectators ~5 Hz, a fighter under 20 KB/s through the waves; on the client a raid spectator who joins (second Start, full snapshot, deltas), a team leaving and a minion wave all drawn where the sim has them (smoke_p3_fixcheck.lua: both worlds, server chapters before the care block)
    client_files.append("smoke_p4_pets_client.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p4pets_cards", "client_p4pets_follow", "client_p4pets_evolved", "client_p4pets_evolution", "client_p4pets_portal"]; mobile_scenarios.append("client_p4pets_mobile")  # Phase 4 pet cards + follow-behind (ARCHITECTURE_V3.md "Phase 4 build contract" 3.6 / 3.9 / 3.10): PetCard (modes, pixel sizes, "Lv" 22 px with a stroke, fills only on change, the EVOLVE! pill), own cards from State (XP = xp / XpToNext, EVOLVE! opens the Pets panel), other players' level cards from EquippedInfo (12 nearest, 60 studs), cards hidden InBattle, the trailing formation (behind at rest and while walking, lag / settle windows), evolved Low followers within petEvoLow / petEvo2Low and the 6-model / 40-stud rule for others, PlayEvolution park + restore, the home portal dive, card text >= 14 px on phones (smoke_p4_pets_client.lua: client + phone worlds)
    client_files.append("smoke_p4_careui.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p4careui_feed", "client_p4careui_garden", "client_p4careui_train", "client_p4careui_evolve", "client_p4careui_panels", "client_p4careui_sizes"]; mobile_scenarios.append("client_p4careui_mobile")  # Phase 4 pet-care UI (ARCHITECTURE_V3.md "Phase 4 build contract" 3.4-3.7 / 8.1, careui): CareController's Food Machine list (garden pets first, Feed / Level up prices from TycoonCatalog, leftovers first, EVOLVE + confirm, MAX LEVEL, the machine footer + Upgrade), the garden picker (any role, Coins $/s, GardenSet, Take out, the own GardenSpotPrompt), the Training Place (four skills, rank bars, cost / time, Train / Stop with a confirm, full spots, MAX), the EVOLVE moment (windows close, the follower parked, EvolutionFx on clones 5-6 studs ahead with confetti, nothing centred, queued), the Pets panel (Lv n / 100, evolution pill, Coins pill, Garden any role, Equip off while training, the card pill's EVOLVE) and the Home window (coins waiting, coins/min, places, legacy lines, no Collect, Phase 4 names and effects, prestige texts, Go home), text sizes at 1920x1080 / 1280x720 / 844x390 and on a 390x844 phone (smoke_p4_careui.lua: client + phone worlds)
    server_files.append("smoke_p4_ui.lua"); client_files.append("smoke_p4_ui.lua"); pure_scenarios += ["p4ui_content"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p4ui_content"); server_scenarios.insert(server_scenarios.index("shutdown"), "p4ui_tutorial"); client_scenarios.insert(client_scenarios.index("client_final"), "client_p4ui"); mobile_scenarios.append("client_p4ui_mobile")  # Phase 4 UI (ARCHITECTURE_V3.md "Phase 4 build contract" 3.8 / 3.11 / 9): tutorial chapter 2 rewritten in place (claim, garden, coins, machine, feed) + chapter 4 appended (train, ring, portal: the index rule, targets, texts, the new CompleteOn kinds, the 300-token reward once, mid-chapter resume of migrated saves, a finished Phase 3 tutorial resuming into chapter 4, skipped players), the Phase 4 NPC tips with the catalogs' numbers, and on the client ArenaController's Champion Ring window (record, start picker, fighters, next win, the server's best, refusals, START), the Team screen's ring line, the safe-zone toast and the ring window on phones (smoke_p4_ui.lua: both worlds)
    server_files.append("smoke_p4_flow.lua"); client_files.append("smoke_p4_flow.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p4flow_new", "p4flow_migrate", "p4flow_rejoin", "p4flow_merge"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p4flow")  # Phase 4 end-to-end flow (ARCHITECTURE_V3.md "Phase 4 build contract" 8.1) through the real remotes and prompts, every scenario with its own players: a new player (claim -> the free Pet Garden -> a pet -> coins scooped once, a visitor scoops nothing -> the Food Machine + FeedPrompt + a feed -> Champion Ring rounds 1-3 with one level-1 pet -> /petlevel 20 + EVOLVE -> Train with the lock and the automatic return -> Prestige with garden place 4 and the Garden still built), a migrated Phase 3 save (Home Level / tier unchanged, plants, the Welcome-back pile, LegacySlots / LegacyPrices, the Gym emptied, a leftover Feast fed, Ready to evolve) resuming tutorial chapter 4 (train -> ring -> portal, +300 once), leave + rejoin mid-training and mid-ring-run, the two-server merge (Ring Best max / Runs delta, ranks max, a running job kept); on the client the veteran's real chapter-4 TutorialState messages on the card (smoke_p4_flow.lua: both worlds, server scenarios booted, before shutdown)
    server_files.append("smoke_p4_fix_battle.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p4fixbat_forfeit", "p4fixbat_return"]  # Phase 4 review fixes in BattleService (fix:battle): BattleCommand("Forfeit") through the remote between two ring rounds ends the run (contract 5.1) + a client caller of Command("Forfeit"); every ring run ends in front of the Champion Ring portal (ArenaInfo.RingSite, contract 3.8), trials still at ReturnCFrame (smoke_p4_fix_battle.lua: server world, booted, before the care block)
    server_files.append("smoke_p4_fix_server.lua"); server_scenarios.insert(server_scenarios.index("shutdown"), "p4fixsrv_prestige_refund")  # Phase 4 review fixes (server): Cash parked in running training jobs does not cross a Prestige (Job.Paid cleared by TycoonService.Prestige, the jobs still finish for their rank, TrainStop after it returns 0 Cash; a Stop in the new run still refunds once) (smoke_p4_fix_server.lua: server world, booted, before shutdown)
    client_files.append("smoke_p4_fix_client.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p4fix_home_rows", "client_p4fix_leave"]; mobile_scenarios += ["client_p4fix_mobile", "client_p4fix_leave_mobile"]  # Phase 4 review fixes (client): the My Home window on landscape phones (740x360 / 812x375 / 667x375) stacks its station rows like portrait (whole names, the info line, the price clear of the level pips) and keeps the summary column; 1280x720 and wider keep one-line rows (smoke_p4_fix_client.lua: client + phone worlds); LEAVE in the battle HUD: a Champion Ring run / a Trial can be stopped with two taps (BattleCommand "Forfeit", also between two ring rounds), never in duels; laid out clear of every control at 1920x1080 / 1280x720 / 390x844 / 844x390 and on the phone

    # -- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" section 12; lead W0 placeholders) -------------------------
    # One line per new smoke file, live as soon as the file exists (p5()), so an owner only creates tools/smoke_p5_<x>.lua
    # and adjusts the scenario names on THEIR line (own line only; re-read this file right before the edit). Placement:
    # pure scenarios after "petbuilder", booted server scenarios before "shutdown", client ones before "client_final",
    # phone ones appended to mobile_scenarios. The owner moves a scenario that must run earlier (flows advance the clock).
    def p5(filename):
        return os.path.exists(os.path.join(HERE, filename))

    def ins(lst, before, names):
        i = lst.index(before)
        lst[i:i] = list(names)

    if p5("smoke_p5_data.lua"): server_files.append("smoke_p5_data.lua"); ins(server_scenarios, "shutdown", ["p5data_team3", "p5data_evo_untouched", "p5dgn_data", "p5dgn_migrate", "p5data_berries", "p5data_berries_merge", "p5data_settings", "p5home_fold_data", "p5home_rollout", "p5dgn_rollout"])  # [owner: data, W1] Phase 5 data (9.1-9.3): Teams 3, Dungeon / Berries / Settings fields + merges, the P5 migrations, the frozen Phase 4 DataService rollout (smoke_p5_data.lua: server world, booted)
    if p5("smoke_p5_battlecore.lua"): server_files.append("smoke_p5_battlecore.lua"); names = ["p5stats_formula", "p5roles", "p5sim_fighter", "p5sim_ai", "p5sim_modes", "p5sim_wire", "p5sim_determinism", "p5dgn_catalog", "p5battle_balance"]; pure_scenarios += names; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = names  # [owner: battlecore, W1] Phase 5 battle core (4.2 / 4.3 / 5.1; replaces smoke_p3_battlecore.lua, whose line above goes with it): LevelFactor table, Support roles, the real-time fighter sim, modes, wire form, determinism, the dungeon catalog, the sim_battle balance subset (smoke_p5_battlecore.lua: server world, pure)
    if p5("smoke_p5_home.lua"): server_files.append("smoke_p5_home.lua"); client_files.append("smoke_p5_home.lua"); names = ["p5home_catalog", "p5home_fold", "p5home_roam_shared"]; pure_scenarios += names; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = names; ins(server_scenarios, "shutdown", ["p5home_signs", "p5home_berries", "p5home_roam_server"]); ins(client_scenarios, "client_final", ["client_p5home_roam", "client_p5home_flow_ui"])  # [owner: economy+roam W1 (catalog / fold / roam_shared), tycoon+care W2 (signs / berries / roam_server), homefx+pets W3 (client)] Phase 5 home (3.3-3.5): 11 stations, FoldLegacy, signs, HomeRoam plans, berries, the roaming ledger, the client roam + Home strip (smoke_p5_home.lua: both worlds)
    if p5("smoke_p5_world.lua"): server_files.append("smoke_p5_world.lua"); client_files.append("smoke_p5_world.lua"); ins(server_scenarios, "shutdown", ["p5world_lighting", "p5world_style", "p5world_lobby", "p5world_gates", "p5obby_levels", "p5obby_migration", "p5world_client_total"]); ins(client_scenarios, "client_final", ["client_p5lightingstack", "client_p5obby"])  # [owner: worldstyle W1 (p5world_lighting / p5world_style helpers / client_p5lightingstack); W2 worldlobby: the lobby style pass in p5world_style + p5world_lobby, p5world_gates, p5obby_levels (its HighestUnlocked table is pure, the rest needs the booted lobby), p5obby_migration, p5world_client_total before "shutdown"; W4 dungeonclient adds "client_p5obby" before "client_final"] Phase 5 world (6.1-6.4, 10.3): Look Custom vs Fallback, LightingStack, the Gate Court, art rules, gate prompts, obby levels + migration, the client part total (smoke_p5_world.lua: both worlds)
    client_files.append("smoke_p5_gui.lua"); ins(client_scenarios, "client_final", ["client_p5neon", "client_p5stamina", "client_p5hud_pills", "client_p5gui_cover"])  # [owner: neonkit, W2; every window owner adds its cover scenes in its own block of the file] Phase 5 Neon kit + the window rule (6.6): Card / Tile / SideRect, 150 stamina + 4 ticks, HUD pills, the coverage check at 4 sizes (smoke_p5_gui.lua: client world; W0 placeholders report info only)
    if p5("smoke_p5_battleservice.lua"): server_files.append("smoke_p5_battleservice.lua"); ins(server_scenarios, "shutdown", ["p5svc_commands", "p5svc_position", "p5svc_position_legit", "p5svc_duel_fair", "p5svc_raid", "p5svc_ring", "p5svc_encounter", "p5svc_shutdown"])  # [owner: battleservice, W2] Phase 5 BattleService (4.4-4.6): the command ladder, the server fighter vs the character, duels / raids / ring on the new engine, the encounter API, shutdown (smoke_p5_battleservice.lua: server world, booted; before shutdown)
    if p5("smoke_p5_dungeon.lua"): server_files.append("smoke_p5_dungeon.lua"); client_files.append("smoke_p5_dungeon.lua"); ins(server_scenarios, "shutdown", ["p5dgn_party", "p5dgn_exclusive", "p5dgn_run", "p5dgn_loot", "p5dgn_ends", "p5dgn_world", "p5dgn_net"]); ins(client_scenarios, "client_final", ["client_p5dungeon"]); mobile_scenarios.append("client_p5dungeon_mobile")  # [owner: dungeon W3 (server), dungeonclient W4 (client)] Phase 5 Dungeon (5.1-5.6): parties, exclusivity, a solo floor 1 end to end, loot once, every end path, templates / budgets, network, the Dungeon window (smoke_p5_dungeon.lua: both worlds + phone)
    if p5("smoke_p5_battleclient.lua"): client_files.append("smoke_p5_battleclient.lua"); ins(client_scenarios, "client_final", ["client_p5hud_fighter", "client_p5hud_enemies", "client_p5input", "client_p5models", "client_p5result"]); mobile_scenarios += ["client_p5battle_mobile", "client_p5battle_landscape"]  # [owner: battleclient, W3] Phase 5 BattleController (4.7): the fighter HUD, enemy rows, the input map + predictions, models, the result card, phone layouts (smoke_p5_battleclient.lua: client + phone worlds)
    if p5("smoke_p5_follow.lua"): client_files.append("smoke_p5_follow.lua"); ins(client_scenarios, "client_final", ["client_p5follow_formation", "client_p5follow_motion", "client_p5wild"])  # [owner: homefx+pets, W3] Phase 5 followers (3.8) + the Wild look (C13): FormationFor, follow motion, PB_Evolved / Wild (smoke_p5_follow.lua: client world)
    if p5("smoke_p5_looks.lua"): server_files.append("smoke_p5_looks.lua"); client_files.append("smoke_p5_looks.lua"); ins(server_scenarios, "shutdown", ["p5looks_podium"]); ins(client_scenarios, "client_final", ["client_p5looks", "client_p5support_power", "client_p5team3", "client_p5menu_tiles"])  # [owner: careui, W3] Phase 5 evolved looks everywhere (3.7), Support battle power (m17), teams of 3 (4.8), the tile grid + Dock (6.6) (smoke_p5_looks.lua: both worlds)
    if p5("smoke_p5_menu.lua"): server_files.append("smoke_p5_menu.lua"); client_files.append("smoke_p5_menu.lua"); ins(server_scenarios, "shutdown", ["p5menu_spawn"]); ins(client_scenarios, "client_final", ["client_p5loading", "client_p5menu", "client_p5settings"]); mobile_scenarios.append("client_p5menu_mobile")  # [owner: menu, W3] Phase 5 loading screen, main menu before spawning, settings (7.1 / 7.2): the server-held spawn + fallback, the ReplicatedFirst screen, the UiGate deny-list, SettingsSet (smoke_p5_menu.lua: both worlds + phone)
    if p5("smoke_p5_tutorial.lua"): server_files.append("smoke_p5_tutorial.lua"); client_files.append("smoke_p5_tutorial.lua"); pure_scenarios += ["p5ui_content"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p5ui_content"); ins(server_scenarios, "shutdown", ["p5dgn_tutorial", "p5ui_tutorial_ch2", "p5ui_portal_obby"])  # [owner: tutorial, W4] Phase 5 tutorial chapters 2-4 + NPC tips (8): texts / targets / needles, the dungeon step, chapter 2 on a Phase 5 home, the Obby portal step, resume from every index (smoke_p5_tutorial.lua: both worlds)
    if p5("smoke_p5_flow.lua"): server_files.append("smoke_p5_flow.lua"); client_files.append("smoke_p5_flow.lua"); ins(server_scenarios, "shutdown", ["p5flow_new", "p5flow_migrate", "p5flow_dungeon", "p5flow_rejoin", "p5flow_merge"]); ins(client_scenarios, "client_final", ["client_p5flow"])  # [owner: flow, W4] Phase 5 end-to-end flows (12.1): a new player through the menu, obby, home, dungeon and ring; a Phase 4 save; 3 players in the dungeon; rejoin + two-server merges (smoke_p5_flow.lua: both worlds; the server chapters advance the clock by hours)

    if p5("smoke_p6_mesh.lua"): server_files.append("smoke_p6_mesh.lua"); client_files.append("smoke_p6_mesh.lua"); ins(server_scenarios, "shutdown", ["p6mesh_noop", "p6mesh_fit", "p6mesh_server"]); ins(client_scenarios, "client_final", ["client_p6mesh"])  # [owner: runtime, Phase 6 W1] MeshLibrary (recipe 4.8 / 4.9): empty-ids no-op, fit + validation, background loader, Assemble + rig, Swap, Tag, EvalColor (server); preload, per-device failure, RenderFidelity, Dress (client)
    if p5("smoke_p6_evofx.lua"): server_files.append("smoke_p6_evofx.lua"); client_files.append("smoke_p6_evofx.lua"); names = ["p6evofx_specs", "p6evofx_build"]; pure_scenarios += names; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = names; ins(client_scenarios, "client_final", ["client_p6evofx"])  # [owner: evofx, Phase 6 W1] PetFx (6.0.4 / A6 / 6.4): element particles + soft light + stage-2 aura and pulse on evolved pets, budgets (12 High / 4 Low), NoFx / Viewport skip, no Parts, idempotent on rebuild / Clone, Clear; GraphicsQuality Low = light only on the client (smoke_p6_evofx.lua: both worlds)
    if p5("smoke_p6_portalfx.lua"): server_files.append("smoke_p6_portalfx.lua"); client_files.append("smoke_p6_portalfx.lua"); pure_scenarios.append("p6portalfx_curves"); server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p6portalfx_curves"); ins(client_scenarios, "client_final", ["client_p6portalfx"])  # [owner: homeportal, Phase 6 W2b] PortalFxController: the gates' animation (curves in 0..1, smooth, the ring light runs, gems in turn; client: finds gates by GateId incl. streaming, Neon parts only, no parts created / moved, distance cull, <= 8 active, Low = static, removal) (smoke_p6_portalfx.lua: both worlds)
    if p5("smoke_p6_creatures.lua"): server_files.append("smoke_p6_creatures.lua"); client_files.append("smoke_p6_creatures.lua"); ins(server_scenarios, "shutdown", ["p6creatures_server"]); ins(client_scenarios, "client_final", ["client_p6creatures"])  # [owner: art-creatures, Phase 6 W2] creature meshes in both modes: empty MeshIds = the Part builds; fixture templates from the committed manifests = BossBuilder joints / Fx / rig / enrage, server coin Tag + ML_Weld, pedestal Tag (server); the mesh sky dragon + rebuild back, welded Cloud Cash coins, a boss + the dressed pedestal on a preloaded device, LEAD REQUEST Dress ML_Weld (client)
    if p5("smoke_p6_lobby.lua"): server_files.append("smoke_p6_lobby.lua"); ins(server_scenarios, "shutdown", ["p6lobby_server"])  # [owner: art-lobby, Phase 6 W2] lobby meshes: committed manifests + LayoutSig, empty ids = no tag on the booted lobby, the live Storm Altar matches its LayoutSig; fixture mode = a second LobbyBuilder.Build() tags every key (plots, shop, plaza layers, roads, gardens, sky, props) with keep lists / looks, no part added, stale layouts refused, Dress lands on the origin
    ins(server_scenarios, "shutdown", ["p3arena_mesh", "p5dgn_mesh"])  # [owner: art-arenadungeon, Phase 6 W2] arena + dungeon meshes (smoke_p3_arenaworld.lua / smoke_p5_dungeon.lua, already loaded): every tagged piece has its arena_* / dungeon_* key and every key is tagged, LayoutSig matches the live Part build, no nested targets, Neon parts kept, empty ids = no tag, ids = tagged with offset / look / keep, stale layouts refused, mesh budgets
    ins(server_scenarios, "shutdown", ["p2home_mesh"])  # [owner: art-home, Phase 6 W2] home meshes (smoke_p2_homeworld.lua, already loaded): every station level's key matches today's Part build (LayoutSig), empty ids = no tag, ids = stations + Garden bed pieces tagged with keep lists, stale layouts refused, the max plot <= 50k tris
    if p5("smoke_p6_gates.lua"): server_files.append("smoke_p6_gates.lua"); client_files.append("smoke_p6_gates.lua"); ins(server_scenarios, "shutdown", ["p6gates_server"]); ins(client_scenarios, "client_final", ["client_p6gates"])  # [owner: art-gates, Phase 6 W2] the Blender gate meshes: committed manifests (budget, no Neon), WorldStyle.BuildGate Tag (key by glyph, ML_Primary, ML_Offset, ML_Keep incl. later extras), parts identical to an untagged build (server); fixture mode: a gate is dressed, only the stone / frame / trim / crest voxels hide, the mesh sits on the site (client)
    if p5("smoke_p6_lod.lua"): client_files.append("smoke_p6_lod.lua"); ins(client_scenarios, "client_final", ["client_p6lod"])  # [owner: perf-plots, Phase 6 W3] the plot LOD (6.5 busiest view): HomeFx tiers High / Low / Far by camera distance with hysteresis, MeshLibrary.SetLod / LowKey (low key swap, decor + far stations hidden, kept glow too, everything restored near), empty ids = untouched, no per-frame work, mesh_budget.py parity (smoke_p6_lod.lua: client world, private MeshLibrary copy, runs the same with --mesh)
    if p5("smoke_p6_pets.lua"): server_files.append("smoke_p6_pets.lua"); client_files.append("smoke_p6_pets.lua"); server_scenarios.insert(server_scenarios.index("load_modules") + 1, "p6pets_mesh_on"); ins(server_scenarios, "shutdown", ["p6pets_default", "p6pets_server"]); client_scenarios.insert(client_scenarios.index("client_load") + 1, "client_p6pets_mesh_on"); ins(client_scenarios, "client_final", ["client_p6pets"])  # [owner: runtime-pets, Phase 6 W2] the pet mesh path (recipe 4.8 / 4.9): MeshKeys per look, the mesh pet (names, PB_* rig, Animate + Clone, PetFx, Wild, Golden, Rainbow, hybrid, evolved, Low, battle scale), whole fallback, NeedsMeshRebuild / MeshVersion (server); follower + viewport rebuild on a preloaded device, device failure keeps Parts (client); --mesh installs every pet-class key first (smoke_p6_pets.lua: both worlds)
    if p5("smoke_p6_fixworld.lua"): server_files.append("smoke_p6_fixworld.lua"); client_files.append("smoke_p6_fixworld.lua"); ins(server_scenarios, "shutdown", ["p6fixworld_board"]); ins(client_scenarios, "client_final", ["client_p6fixworld"])  # [owner: fix-world, Phase 6 W3b] review3 world-0 / world-1: the THE GATES GuideBoard lists the 5 real gates + the Go home hint (server); GraphicsQuality Low survives a mesh rebuild of the sky dragon (paused, no RenderStepped), High after it does not throw and runs PetFx.SetQuality (client)
    if p5("smoke_dgfix_mouse.lua"): server_files.append("smoke_dgfix_mouse.lua"); client_files.append("smoke_dgfix_mouse.lua"); ins(server_scenarios, "shutdown", ["dgfixmouse_data"]); ins(client_scenarios, "client_final", ["client_dgfix_mouse"])  # [owner: mouse-lock, dungeon-fixes decision 6] the MouseLock setting (default off, SettingsSet + rejoin, non-bool refused) and client/MouseLock.lua (LockCenter only when enabled with no hold, one RenderStep binding, holds: Dock windows / main menu / loading / result card / tutorial card / TextBox, the L key, touch no-op) (smoke_dgfix_mouse.lua: both worlds)
    if p5("smoke_dgfix_flow.lua"): server_files.append("smoke_dgfix_flow.lua"); client_files.append("smoke_dgfix_flow.lua"); ins(server_scenarios, "shutdown", ["dgfix_flow_solo", "dgfix_flow_party", "dgfix_flow_floor"]); ins(client_scenarios, "client_final", ["client_dgfix_flow"])  # [owner: dungeon-flow, dungeon-fixes decisions 1 + 2] room changes only by E at the door (per-player confirm, Transit lock, one enterRoom, Fade before the teleport, leaver / late joiner / Downed, no DoorTime / HallSeconds, the watchdog), the encounter centre on the floor (wave + boss room), waves 2 / 3, the treasure exit; the client fade overlay + side card texts (smoke_dgfix_flow.lua: both worlds)
    if p5("smoke_dgfix_client.lua"): client_files.append("smoke_dgfix_client.lua"); ins(client_scenarios, "client_final", ["client_dgfix_waves", "client_dgfix_arrive", "client_dgfix_attack", "client_dgfix_dash", "client_dgfix_prompt"])  # [owner: battle-client, dungeon-fixes decisions 1, 3, 4, 5 + the E rule of 6] SERVER order (Start, then the Wave event) draws every enemy (dungeon waves, boss + escort, ring rounds, raid adds), Wild look; EvolutionFx.Arrive (hidden until the flash, pop, pooled kits, cap, Low = flash + ring); ATTACK = one direct order (F / button / click, mouse-lock centre pick), no hold repeat; Shift = the pet's dash (no character impulse / stamina), own pet dash drawn; E passes to a shown ProximityPrompt
    if p5("smoke_dgfix_core.lua"): server_files.append("smoke_dgfix_core.lua"); names = ["dgfixcore_auto", "dgfixcore_direct", "dgfixcore_arrive", "dgfixcore_dash", "dgfixcore_heal", "dgfixcore_determinism"]; pure_scenarios += names; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = names  # [owner: battle-core, dungeon-fixes decisions 3, 4, 5, 7] the fighter auto-attack in every mode (never moves the unit, not while Stunned / Casting / Dashing), ATTACK directs (lock / nearest / cycle / OutOfReach / echo on change), enemy arrival (Arrive in Wave / Spawn infos, no acting, no hits, not targetable, the dungeon time limit pushed back), the Dash event { unit, dir, target }, no passive bench regen (fight + wave gap), the Heal special / Heal buff on the bench, determinism (smoke_dgfix_core.lua: server world, pure)
    if p5("smoke_bug2_dungeon.lua"): server_files.append("smoke_bug2_dungeon.lua"); client_files.append("smoke_bug2_dungeon.lua"); ins(server_scenarios, "shutdown", ["bug2dgn_colliders", "bug2dgn_doorlanes"]); ins(client_scenarios, "client_final", ["client_bug2dgn_zoom"])  # [owner: bug batch 2, lane-dungeon] #3 every room template: the Cellar CellBars collide, no visible prop a player can stand inside; #25 no colliding prop within 6 studs of a door centre line (12 studs in); #19 MovementController.SetZoomMax: 14 in a dungeon run, 40 again on every exit path (smoke_bug2_dungeon.lua: both worlds)
    if p5("smoke_bug5_dungeon.lua"): server_files.append("smoke_bug5_dungeon.lua"); client_files.append("smoke_bug5_dungeon.lua"); ins(server_scenarios, "shutdown", ["bug5dgn_styles", "bug5dgn_throne", "bug5dgn_review"]); ins(client_scenarios, "client_final", ["client_bug5dgn_spin", "client_bug5dgn_mood"])  # [owner: bug #5 dungeon-rooms, art wave] the look follows the floor (StyleTiers c 1-3 / b 4-8 / a 9-12, deeper = more serious + darker mood), the boss room per style: banners between the torches, wall-mounted props + brackets on the wall, designed pieces keyed, no cellar clutter, doorways 8 clear, markers unchanged, weathering off the props, sound tags; DungeonFx turns the astrolabe rings; review fix round: mood >= the P4 preset, no light dimming, tall weathering collides, astrolabe clears the ceiling, Style.Cur restored on errors, no cellar leftovers in b (smoke_bug5_dungeon.lua: both worlds)
    if p5("smoke_bug2_battle.lua"): server_files.append("smoke_bug2_battle.lua"); names = ["bug2bat_npc_specials", "bug2bat_raid_balance"]; pure_scenarios += names; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = names  # [owner: bug batch 2, lane-battle-balance] #27 enemy NPCs use specials (Damage.MeterOnHit 8 / MeterPerSecond 5 for NPC units, BattleCatalog.MeterStart: NPC 45-75, Ring champion + dungeon waves 2+ at 80, players 20-50; a 20 s Ring fight casts; most dungeon enemies cast; raid minions never; BattleSim.meterStart reads BattleCatalog.MeterStart) and #2 the boss raid floor (BossHp >= HpPerPlayer x BaselineDps, DamageGroup.Min 0.7, MinHp 2500; a Lv 5 solo loses, a Lv 40 solo and eight Lv 5 teams win; balance-5: lava_golem HpPerPlayer 85, a solo M5 loses, eight M5 teams win >= 10 of 16 seeds; wave 6: lava_golem back to 90, a solo M5 loses every boss while it parries) (smoke_bug2_battle.lua: server world, pure)
    if p5("smoke_p5_dungeon.lua"): ins(server_scenarios, "shutdown", ["bug2chest_pick"])  # [owner: bug batch 2 wave 2, lane-dungeon-chest] #14 pick ONE chest: no GUI chest button, a Chest request without a slot opens nothing, E at a chest opens THAT chest (its own roll: seed + slot x 7919, Opened / prompt off for everyone), one chest per member, taken / far / junk slots refused, spam rate limited, the 45 s exit gives the first free chest, chests >= a full party (smoke_p5_dungeon.lua, already loaded)
    if p5("smoke_bug2_tutset.lua"): server_files.append("smoke_bug2_tutset.lua"); client_files.append("smoke_bug2_tutset.lua"); ins(server_scenarios, "shutdown", ["bug2tut_raidstep", "bug2tut_mousedata"]); ins(client_scenarios, "client_final", ["client_bug2tut_portrait", "client_bug2tut_raidnext", "client_bug2tut_mouse"])  # [owner: bug batch 2, lane tutorial-settings] #24 the raid step completes on the raid floor / Next (AlsoNext, no countdown, a live raid = bonus toast, stored Step 18 not stuck); #21 MouseLock default ON (a stored nil -> true, a stored false stays false), the "Mouse lock (recommended)" row, holds for the roulette stage / odds popup / NPC dialog; #23 the folded tutorial bubble keeps animating at 1/15 s (smoke_bug2_tutset.lua: both worlds)
    if p5("smoke_bug2_lobby.lua"): server_files.append("smoke_bug2_lobby.lua"); client_files.append("smoke_bug2_lobby.lua"); ins(server_scenarios, "shutdown", ["bug2lobby_altarportal", "bug2lobby_benches"]); ins(client_scenarios, "client_final", ["client_bug2lobby_petsit"])  # [owner: bug batch 2, lane-lobby] #4 the Storm Altar return portal (StormAltar.GetReturnPad, GateService gate "Plaza" -> LobbyInfo.Gates.Altar.ReturnCFrame: placement, prompt, refusals, cooldown, rebuild); #7 sittable benches (2 Disabled BenchSeats + "Sit" prompts per bench, server-checked sit, free again on leave, refusals, teleport watchdog) and the followers settling on the ground in front of a sitting owner (lying, facing, no overlap, smooth, back on stand-up) (smoke_bug2_lobby.lua: both worlds)
    if p5("smoke_bug2_gui.lua"): client_files.append("smoke_bug2_gui.lua"); ins(client_scenarios, "client_final", ["client_bug2gui_layout", "client_bug2gui_stickemu", "client_bug2gui_empty"]); mobile_scenarios += ["client_bug2gui_mobile", "client_bug2gui_stick_mobile", "client_bug2gui_empty_mobile"]  # [owner: bug batch 2 wave 4a, lane-gui] #1 option A "Split & shift": ONE slim menu column at the left edge (56 px tiles at 1080p, Pets .. Settings), the arrow tab folds it against the edge (remembered, repeats a tile's red dot, a tutorial menu step unfolds it), the currencies as thin strips stacked top-right under the top bar, the vitals bottom-centre right above the hotbar, published BottomLeftTop / BottomCentreTop / TopRightBottom, nothing overlapping; on phones / tablets the tiles stay >= 44 px above the thumbstick zone and the vitals clear the stick, the jump button and RUN / DASH (smoke_bug2_gui.lua: client + phone worlds)
    if p5("smoke_bug2_garden.lua"): server_files.append("smoke_bug2_garden.lua"); ins(server_scenarios, "shutdown", ["bug2garden_lock", "bug2garden_recall", "bug2garden_fusion", "bug2garden_oldsave", "bug2garden_closed"])  # [owner: bug batch 2 wave 4a, lane-garden] #18 "Remote recall": a Garden pet is busy (no follow, no team, no fight; GardenSet unequips it and prunes its presets), HomeAction "GardenRecall" takes it out AND equips it / stores the team in one rate-limited request, old saves keep the pet with the player and take it out of the Garden once (marker B2GardenSolo + one toast); follow-up: a pet on a CLOSED place (above the open count) is not busy, equipping / teaming it empties that place silently
    if p5("smoke_p7vfx.lua"): server_files.append("smoke_p7vfx.lua"); pure_scenarios += ["p7vfx_ids", "p7vfx_catalog", "p7vfx_poses"]; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = ["p7vfx_ids", "p7vfx_catalog", "p7vfx_poses"]  # [owner: pet attack VFX, Tasks 3 + 4 + 5] the uploaded VFX ids: every blender/vfx/textures.json key in TextureIds as a positive integer Image id, no TextureIds key besides those + the vortex layers, every vfx_* key of blender/catalog/vfx.json in MeshIds; p7vfx_catalog: AttackFxCatalog bands / sizes / every element x attack x rarity x stage recipe / monotonic layers / density rules / 12 signatures / Unit on hybrids / Nature petals; p7vfx_poses: PetPoses (every pose finite, one-shots start / end at rest, Ko holds, the brief's shapes, no pops) + the PetBuilder.Animate opts.Pose hook on real builds (WingL / Tail move, wings mirrored, exact unposed frame without Pose, lids, no Instances) + PoseBody (smoke_p7vfx.lua: server world, pure)
    if p5("smoke_p7vfx_client.lua"): client_files.append("smoke_p7vfx_client.lua"); ins(client_scenarios, "client_final", ["client_p7vfx_engine", "client_p7vfx_battle", "client_p7vfx_storm", "client_p7vfx_precharge"])  # [owner: pet attack VFX, Tasks 6 + 7; client_p7vfx_storm: Task 11 fix round 2, a Storm special lands on exactly the enemies its zone hits (BattleController gathers them); client_p7vfx_precharge: Task 11b, the Special pre-charge (a press predicts the charge, hands it over or shatters; other Specials land late with their hits / KO held)] client/Controllers/AttackFx, the engine that plays the AttackFxCatalog recipes: every element x Melee / Ranged / Special / Element at High and gone after its beats, flipbooks, the MAX_LIVE budget + step-down + Play false, no pool leaks after 200 plays, Review Focus 1 / 3 / 5, missing texture = Play false, cores not ready = textures only, no camera punch for Mine = false; client_p7vfx_battle: BattleController plays AttackFx once per Hit / Special / Element / KO of a replayed raid (unit's element + rarity), cube Fx.* when Play is false, DODGED!, the caps, IdleBattle between attacks, Review Focus 4 (End: the killing blow lands, Live 0 + pools at keep size within 1 s; Leave: at once) (smoke_p7vfx_client.lua: client world)
    if p5("smoke_fight.lua"): server_files.append("smoke_fight.lua"); client_files.append("smoke_fight.lua"); pure_scenarios.append("fight_engage_core"); server_scenarios.insert(server_scenarios.index("p5sim_determinism") + 1, "fight_engage_core"); server_scenarios.insert(server_scenarios.index("p5svc_position_legit") + 1, "fight_engage_service"); client_scenarios.insert(client_scenarios.index("client_dgfix_attack") + 1, "client_fight_attack"); client_scenarios.insert(client_scenarios.index("client_dev") + 1, "client_fight_dev"); mobile_scenarios.insert(mobile_scenarios.index("client_dev_mobile") + 1, "client_fight_dev_mobile")  # [owner: wave 5 fight lane, bugs #16 + #22; rewritten for wave 6] the engage rule (wave 6: any enemy in the fight area, target order lock -> sticky engaged -> fresh threat -> nearest, the owner's walk never pulls the pet back, noEngage white-box hold, KO / Swap / Stun / no-Move, Validate refuses Engage*, determinism), Attack() keeps a live lock (no cycle, no echo); BattleService skips the leash while engaged (a 30-stud engage, an 8 s walk without leash, the run-off removal); hold F / X / ATTACK 0.4 s = Target(next), the ATTACK / NEXT caption, the Engage hop, the drawn pet where the server has it; the DEV tile clear of the battle HUD (smoke_fight.lua: both worlds + phone)
    if p5("smoke_wave6.lua"): server_files.append("smoke_wave6.lua"); client_files.append("smoke_wave6.lua"); w6_pure = ["w6_dash_parry", "w6_cheer_core"]; pure_scenarios += w6_pure; server_scenarios[server_scenarios.index("fight_engage_core") + 1:server_scenarios.index("fight_engage_core") + 1] = w6_pure; ins(server_scenarios, "shutdown", ["w6_cheer_service", "w6_podium_find", "w6_podium_lock", "w6_dgn_walkin_floors", "w6_dgn_cambox"]); ins(client_scenarios, "client_final", ["client_w6_podium_cheer", "client_w6_cheer_button", "client_w6_parry_fx", "client_w6_walkin_floors", "client_w6_cambox"]); mobile_scenarios += ["client_w6_cheer_mobile"]  # [owner: wave 6 fight focus] Dash = a sidestep out of the threat, a timed Dash parries (NPC wind-ups, boss telegraphs, the boss stagger + ParryBossGap, the no-threat / corner sidestep, Validate); Cheer up! (+5% 5 s, 20 s cooldown, no stacking, raid / dungeon only); the Cheer remote (own bucket, junk, spam, Start cooldowns); the podium (Ring SpawnPad / duel ChallengePad, the lock, its releases); the client cheer emote (podium loop, one play per Cheer); the Cheer up! button above the vitals card (PC + phone); PARRY! + the sidestep draw; the walk-in on every floor (the room payload before the next room's build, the fade waits 6 s); the dungeon camera box clamp (smoke_wave6.lua: both worlds + phone)
    if p5("smoke_wave6_bugs.lua"): server_files.append("smoke_wave6_bugs.lua"); client_files.append("smoke_wave6_bugs.lua"); pure_scenarios.append("w6bug_wings"); server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "w6bug_wings"); ins(client_scenarios, "client_final", ["client_w6bug_train"])  # [owner: wave 6 bugs] the owner's inbox: evolved wings never swing in front of the face while flying (every pet / stage, the beat turns about the pet's forward axis; --mesh: the mesh pets), a training pet appears on its mat when the mat attachment replicates after the station (smoke_wave6_bugs.lua: both worlds)
    if p5("smoke_wave5_dungeon.lua"): server_files.append("smoke_wave5_dungeon.lua"); client_files.append("smoke_wave5_dungeon.lua"); ins(server_scenarios, "shutdown", ["w5dgn_enter", "w5dgn_walkin_timeout", "w5dgn_infight", "w5dgn_crossing"]); ins(client_scenarios, "client_final", ["client_w5dgn_walkin", "client_w5dgn_enter", "client_w5pets_follow", "client_w5dgn_camera"])  # [owner: wave 5 dungeon lane, bugs #26 + #15] the dungeon entrance cover (Enter before the teleport, Transit lock, the leaver / endRun paths), the walk-in timeout 3 s and no yank at startFight, InFight only during a room's fight, a crossing starts at once; the client room walk-in (camera, MoveTo, skip, every exit path, Shake OFF static), the voxel-shatter entrance (grids, rush, reveal, skip, safety, Low), the followers shown outside fights + the 1 s hand-over, the dungeon shoulder / light shake / FOV punch (smoke_wave5_dungeon.lua: both worlds)
    if p5("smoke_audio.lua"): server_files.append("smoke_audio.lua"); client_files.append("smoke_audio.lua"); ins(server_scenarios, "shutdown", ["audio_ring_pocket"]); ins(client_scenarios, "client_final", ["client_audio_keys", "client_audio_silent", "client_audio_charge", "client_audio_music", "client_audio_ring"])  # [owner: original audio] Config.Audio <- shared/AudioIds.lua (tools/upload_assets.py --audio): every audio/audio.json key mapped, missing ids silent (no Sound, no warning), the slot volumes in one place, SoundFx NAMES; BattleController's charge plays Inhale (0.75 -> 1.35) / Shatter; the music layers (my battle -> Battle, a won ring round keeps it, a dungeon run -> Dungeon with its boss room Battle, back to Lobby), Reward on a win / a room's loot / the chest, the Music / Sfx settings on the music and the loops; RingAmbience's positional, looped CrowdCheer + DrumLoop at a ring pocket's crowd (InverseTapered, Config Min / Max), the Drummer / NC_RingCrowd hooks; on the server the real ring pocket has its "Crowd" within hearing of the fighter (smoke_audio.lua: both worlds)
    if p5("smoke_bug2_battle.lua"): server_files.append("smoke_bug2_battle.lua"); names = ["bug2bat_npc_specials", "bug2bat_raid_balance"]; pure_scenarios += names; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = names  # [owner: bug batch 2, lane-battle-balance] #27 enemy NPCs use specials (Damage.MeterOnHit 8 / MeterPerSecond 5 for NPC units, BattleCatalog.MeterStart: NPC 45-75, Ring champion + dungeon waves 2+ at 80, players 20-50; a 20 s Ring fight casts; most dungeon enemies cast; raid minions never; BattleSim.meterStart reads BattleCatalog.MeterStart) and #2 the boss raid floor (BossHp >= HpPerPlayer x BaselineDps, DamageGroup.Min 0.7, MinHp 2500; a Lv 5 solo loses, a Lv 40 solo and eight Lv 5 teams win) (smoke_bug2_battle.lua: server world, pure)
    if p5("smoke_bug13_fountain.lua"): server_files.append("smoke_bug13_fountain.lua"); client_files.append("smoke_bug13_fountain.lua"); ins(server_scenarios, "shutdown", ["bug13fountain_server"]); ins(client_scenarios, "client_final", ["client_bug13fountain_boat"])  # [owner: art wave, bug #13 waterfall] the Sky-Oasis fountain: no emitter inside the statue / no sparkle star / built-in textures only, three falls with scrolling streak Beams + splashes (drops, foam, flat ripples, mist), climbable trusses flush with the landings, statue on the nest floor, the boat root (OasisBoat, ML_Weld), the oasis manifests fit the layout; client FountainFx drifts the boat near the camera, rests it on Low / Stop / out of range (smoke_bug13_fountain.lua: both worlds)
    if p5("smoke_bug12_meadow.lua"): server_files.append("smoke_bug12_meadow.lua"); client_files.append("smoke_bug12_meadow.lua"); ins(server_scenarios, "shutdown", ["bug12meadow_server"]); ins(client_scenarios, "client_final", ["client_bug12meadow_sway"])  # [owner: art wave, bug #12 ground] the Wind-Sown Sky Meadow: no flat flower squares in the lawn layers, every published clump on lawn (never under a path / kerb / prop, off the edges and NPC spots), wild ring denser than the mown lawns, encode/decode, the seed sacks + downwind drifts + dandelion seeds, the meadow manifests; client MeadowFx: smooth bounded downwind sway about the foot, LOD near/far, local non-colliding parts, mesh swap on ready, Low / Stop clear (smoke_bug12_meadow.lua: both worlds)
    if p5("smoke_bug20_farm.lua"): server_files.append("smoke_bug20_farm.lua"); client_files.append("smoke_bug20_farm.lua"); ins(server_scenarios, "shutdown", ["bug20farm_server"]); ins(client_scenarios, "client_final", ["client_bug20farm"])  # [owner: art wave, bug #20 farm] the Sky-Sailor's Allotment: the Part build at every level (deck, hulls, cabin, boat roof, propeller, bell, glass portholes, anchor, tub; oars + mast from 23; seated bushes), the propeller element key, every farm manifest Fixed + Glass at the cabin end (the facing marker) <= 8000 tris with the live LayoutSig, the fit sees a 180 turn; client: a dressed farm keeps its Part build hidden (decor coming back, LOD rebuilds, kept parts joining while hidden), the propeller weathervane turns in place (smoke_bug20_farm.lua: both worlds)
    if p5("smoke_bug11_ring.lua"): server_files.append("smoke_bug11_ring.lua"); client_files.append("smoke_bug11_ring.lua"); ins(server_scenarios, "shutdown", ["bug11ring_server"]); ins(client_scenarios, "client_final", ["client_bug11ring_crowd"])  # [owner: art wave, bug #11 ring logo + crowd] the Sky-Sailors' Ring: no EmblemCrown / EmblemGem, the compass star is its own RingEmblem (arena_emblem) above the canvas, even on all four sides; one RingCrowd Model per cast cloud with ML_Weld / CrowdKey / CrowdOff roots, the drummer (Drum + two sticks), the Lua cast = the Blender attachments, seats on the steps facing the ring, the rigging, no nested targets, untagged without ids, the NC_RingCrowd / NC_RingDrummer sound hooks and no Config.Audio.Crowd (server); RingCrowdFx Pose / StickAngle in time, cues, a fake stand moves and returns exactly to rest (Low / range / Stop / untag), boss colours restored, HandleState with fake payloads, no Sound made (client)
    if p5("smoke_sky.lua"): server_files.append("smoke_sky.lua"); client_files.append("smoke_sky.lua"); sky_pure = ["sky_phase_math", "sky_blend_window", "sky_clock_no_wrap", "sky_floor", "sky_join_matches", "sky_bad_inputs", "sky_event_blend"]; pure_scenarios += sky_pure; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = sky_pure; ins(client_scenarios, "client_final", ["stack_setbase_under_preset", "stack_setbase_value", "stack_busy_skips", "stack_setbase_instant", "client_sky_first_instant", "client_sky_refresh", "client_sky_event", "client_sky_event_back_to_back", "client_sky_battle_lift", "client_sky_lamps", "client_sky_fireflies", "client_gfx_cloud_cap", "client_gfx_recap_keeps_tweens", "client_dungeon_density_follows"])  # [owner: living sky, Task 1 + Task 2] SkyCycle: the 20 min loop (Dawn 2 / Day 6 / Sunset 9 / Night 3 min) from (now, epoch, speed, offset) incl. the loop wrap and clock skew, the 75 s blend window, ClockTime monotonic per phase (no 24 -> 0, Sunset 16-17), the readability floor in every phase and raid look (Brightness >= 1, OutdoorAmbient >= 70, tint within 8 of white), a late joiner = a long-running client, junk speed / epoch / event inputs, the raid sky blend (midpoint, theme swap at 0.5); Task 2 LightingStack.SetBase (the moving base under the presets, Value, Busy while a Push / Pop fade runs, SetBase deferred then), whole numbers (StarCount) and the clock jump set at once; Task 5 SkyController (inert without SkyEpoch, the first apply instant, a 2 s loop with 2 s tweens that skips while Busy, no per-frame connection, the Sunset -> Night clock walked across the blend (monotonic, no jump: no one-frame horizon pop), the Night -> Dawn wrap set at once, the raid sky blend in / out over 3 s from SkyEventAt, back-to-back raids blended raid sky to raid sky (never back through the cycle), the battle lift at night (B.. only), the night lamps, the fireflies on High only), the GfxLow cloud cap following the cycle (Recap in place via LightingStack.Update: never cancels or re-eases the sky tweens), the dungeon haze on top of the current cycle density (smoke_sky.lua: server world, pure; the stack_* scenarios in the client world, last before client_final: they move the base)
    if p5("smoke_sky_faces.lua"): server_files.append("smoke_sky_faces.lua"); skyf_pure = ["skyfaces_none", "skyfaces_full", "skyfaces_partial", "skyfaces_preset_fallback"]; pure_scenarios += skyf_pure; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = skyf_pure  # [owner: living sky, Task 3] SkyFaces: the painted faces of the 7 sky themes from TextureIds "sky_<theme>_<Face>" (none uploaded -> nil, all six -> six rbxassetid:// strings, five of six or a junk id -> nil, so a half-uploaded theme never shows a grey face), SkyCycle.Preset carries no Skybox* keys without faces (the boot sky stays) and exactly the theme's six with them (smoke_sky_faces.lua: server world, pure)
    if p5("smoke_sky_server.lua"): server_files.append("smoke_sky_server.lua"); ins(server_scenarios, "shutdown", ["skysvc_attrs", "skysvc_raid_start_end", "skysvc_raid_end_reasons", "skysvc_dev_refuses"])  # [owner: living sky, Task 4] SkyService: the sky clock as Workspace attributes (SkyEpoch / SkySpeed / SkyOffset / SkyEvent / SkyEventAt, Init twice keeps them), the server-wide raid sky (EventStarted BossRaid on, every Raid end Reason off, back-to-back raids, non-Raid ends never clear, the EventWatch watchdog), DevService /sky (phases, speed clamp, raid preview / clear, refusals, /devhelp) (smoke_sky_server.lua: server world, booted, before shutdown)
    if getattr(args, "mesh", False) or os.environ.get("NC_MESH_FIXTURES") == "1": os.environ["NC_MESH_FIXTURES"] = "1"; only = only if only is not None else {"p6pets_mesh_on", "petbuilder", "evolved", "p3evo_pets", "p6evofx_build", "p2fusion_looks", "storm_pet", "p5looks_podium", "p6pets_default", "p6pets_server", "client_p6pets_mesh_on", "client_pets", "client_p4pets_follow", "client_p4pets_evolved", "client_p5follow_formation", "client_p5follow_motion", "client_p5wild", "client_p5looks", "client_p5models", "client_p6evofx", "client_p6pets", "client_p4pets_evolution", "client_p4careui_evolve", "client_p5home_roam", "client_p2home", "w6bug_wings", "client_w6bug_train", "client_p5hud_fighter", "client_p5team3", "client_p3evo_lineup", "client_p2fusion"}; only |= {"p6pets_mesh_on", "client_p6pets_mesh_on"}  # [owner: runtime-pets, Phase 6 W2] --mesh: the pet scenarios in fixture mesh mode (voxel-internal asserts of other owners may differ there, recipe 4.9)
    if args.list:
        print("server:", ", ".join(server_scenarios))
        print("client:", ", ".join(client_scenarios + mobile_scenarios))
        print("files: ", ", ".join(["smoke_common.lua"] + server_files + client_files))
        return 0

    # every tools/smoke_*.lua must be loaded by one of the worlds, otherwise its scenarios silently never run
    client_files.append("smoke_p3_battleclient.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p3battle_trial", "client_p3battle_raid", "client_p3battle_spectate", "client_p3battle_cards", "client_p3battle_ring"]; mobile_scenarios += ["client_p3battle_mobile", "client_p3battle_ring_mobile"]  # [owner: battleclient] BattleController brought to Phase 5 (a real BattleSim fed through BattleState like BattleService sends it, Start.Team + SnapshotDelta): dungeon rooms in place of the Trials (followers parked, the fighter card + 2 helper portraits, ATTACK / ELEMENT / SPECIAL / DASH via ContextActionService only in battle, intact welded models, smooth 60 fps interpolation, world damage numbers, ELEMENT cooldown refusals, full-meter SPECIAL, lock by TARGET row / world tap, KNOCKED OUT card), raid boss + telegraphs + boss bar + minions + leavers + effect caps, spectators (fighters only, no controls), junk messages; Phase 4 PetCards above every unit (fills only on change, evolved helpers within budgets), the Champion Ring HUD + next-round card + run result cards; the compact touch HUD on a phone (smoke_p3_battleclient.lua: client + phone worlds)
    wired = set(server_files + client_files + ["smoke_common.lua"])
    for name in sorted(os.listdir(HERE)):
        if name.startswith("smoke_") and name.endswith(".lua") and name not in wired:
            reporter.emit("fail", "smoke.py", "tools/%s is not wired into smoke.py" % name, "add it to server_files / client_files in tools/smoke.py")

    # scenarios build on each other: asking for one pulls in what it needs
    if only is not None:
        no_boot = {"mock_selftest", "load_modules", "boot"} | set(pure_scenarios)
        needs_boot = set(server_scenarios) - no_boot
        if only & needs_boot:
            only |= {"boot", "load_modules"}
        elif only & set(pure_scenarios):
            only |= {"load_modules"}
        if only & set(client_scenarios) - {"client_load"}:
            only |= {"client_load"}
        if only & (set(mobile_scenarios) - {"client_mobile"}):
            only |= {"client_mobile"}  # phone scenarios get the booted phone client, like client scenarios get client_load
        if "cannon" in only:
            only |= {"layouts"}  # the cannon audit reads the cannons the layouts scenario collected

    def wanted(name):
        return only is None or name in only

    run_server = any(wanted(n) for n in server_scenarios)
    run_client = any(wanted(n) for n in client_scenarios + mobile_scenarios)
    # the client replay feeds on the traffic of the whole server run
    if only is not None and wanted("client_replay") and not any(n in only for n in server_scenarios):
        run_server = True
        only = only | set(server_scenarios)

    def check_listed(table, names, label):
        """A scenario function that exists in the Lua files but is not in the lists above would never run."""
        listed = set(names) | {"export_replication"}
        for key in list(table.keys()):
            if isinstance(key, str) and key not in listed:
                reporter.emit("fail", "smoke.py", "%s scenario '%s' is defined but not listed in tools/smoke.py" % (label, key), "add it to the scenario lists")

    def run_scenarios(world, table, names, label):
        """Runs the wanted scenarios of one world; a crash in one never stops the rest."""
        results = world.rt.globals().T.results
        cursor = 0
        for name in names:
            if not wanted(name):
                continue
            fn = table[name]
            if fn is None:
                reporter.emit("fail", name, "scenario %s is missing" % name, "")
                continue
            print("\n== %s ==" % name)
            t0 = time.time()
            # a runaway scenario (or a game function it calls) is aborted instead of hanging the whole suite
            world.Mock["Deadline"] = world.Mock.RealClock() + args.scenario_timeout
            try:
                fn()
            except Exception as exc:  # a Lua error escaping a scenario (guarded() normally catches them)
                reporter.emit("fail", name, "scenario crashed", str(exc))
            world.Mock["Deadline"] = None
            try:
                cursor = drain(results, cursor, reporter)
            except Exception:
                reporter.emit("fail", name, "could not read the results of %s" % name, traceback.format_exc())
                cursor = lua_len(results)
            if args.verbose:
                print("   (%.1fs)" % (time.time() - t0))

    server = None
    if run_server:
        try:
            server = World(engine, engine_name, "server", args, api, contract)
            S = server.load_scenarios(server_files)
            check_listed(S, server_scenarios, "server")
            run_scenarios(server, S, server_scenarios, "server")
            replication = S["export_replication"]() if S["export_replication"] else None
        except Exception:
            reporter.emit("fail", "server", "server world crashed", traceback.format_exc())

    # -- client world ----------------------------------------------------------------------------
    if run_client and any(wanted(n) for n in client_scenarios):
        try:
            client = World(engine, engine_name, "client", args, api, contract, viewport=(1920, 1080))
            C = client.load_scenarios(client_files)
            check_listed(C, client_scenarios + mobile_scenarios, "client")
            if replication is not None:
                client.rt.globals().REPLICATION = replication_to_client(client.rt, server, replication)
            run_scenarios(client, C, client_scenarios, "client")
        except Exception:
            reporter.emit("fail", "client", "client world crashed", traceback.format_exc())

    if run_client and any(wanted(n) for n in mobile_scenarios):
        try:
            phone = World(engine, engine_name, "client", args, api, contract, touch=True, viewport=(390, 844))
            C = phone.load_scenarios(client_files)
            run_scenarios(phone, C, mobile_scenarios, "mobile")
        except Exception:
            reporter.emit("fail", "client_mobile", "mobile client world crashed", traceback.format_exc())

    # -- summary -----------------------------------------------------------------------------------
    elapsed = time.time() - started
    print(
        "\nsmoke test: %d passed, %d failed, %d warnings  (%.1fs)"
        % (reporter.oks, reporter.fails, reporter.warns, elapsed)
    )
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(reporter.records, fh, indent=2)
    failed = reporter.fails > 0 or (args.strict and reporter.warns > 0)
    return 1 if failed else 0


def replication_to_client(rt, server, replication):
    """The server world exports its replication log as a Lua table; client Lua just reads it, but it
    lives in another runtime, so copy it through plain Python data."""
    data = lua_to_py(replication)
    return to_lua(rt, data)


if __name__ == "__main__":
    sys.exit(main())
