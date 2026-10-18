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
    server_files.append("smoke_p4_garden.lua"); client_files.append("smoke_p4_garden.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p4garden_coins", "p4garden_scoop", "p4garden_ledger"]  # Phase 4 rainbow coins (ARCHITECTURE_V3.md "Phase 4 build contract" 3.1-3.3, 5.3, X1-X6 / X20): the free Pet Garden, a meal every 8 s per open place with a pet (Economy x1.6, the stored evolution stage, Lucky coins by Garden level, the pile cap -> the pet naps), the coin ledger exactly once (Home.CollectorCash is the bank, the 0.25 s owner-proximity scoop within ScoopRadius, a second player on the lawn scoops nothing, Cash + bank constant, CoinsScooped), GardenSet for any role with the training / battle refusals and the X5 timer rule, resting keys above the open count, LegacySlots, the Welcome-back pile across leave + rejoin / offline coins / a rebase / a provisional load / a DataStore outage, Prestige mid-pile (Garden kept at L1, +1 place), the veteran welcome toast once, ClearCoins; the client half (client_p4garden_*) is added in wave 3 (smoke_p4_garden.lua: both worlds, server scenarios booted)
    server_files.append("smoke_p4_portal.lua"); client_files.append("smoke_p4_portal.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p4portal_home", "p4portal_refusals"]  # Phase 4 home portal (3.10 / 3.11 / X18): HomeAction "GoHome" writes HomePortal "x,y,z,yaw,closesAt" 6 studs ahead for 10 s with no server part, only the owner walking in is teleported within 6 studs of SpawnCFrame (PortalArrived, PortalUsed), another player at the point stays, expiry, the 3 s cooldown, GoToSpot / GoHome without a home open it toward a free gate; refused in a match / InBattle / a portal party / dead, an open portal closes when the owner enters a battle, SpotService.Teleport and GoToSpot refuse InBattle, junk arguments; the client half (client_p4portal_*) is added in wave 3 (smoke_p4_portal.lua: both worlds, server scenarios booted)
    server_files.append("smoke_p2_homeworld.lua"); client_files.append("smoke_p2_homeworld.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p2home_art", "p2home_plot"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2home")  # Phase 2 home world: HomeBuilder station art per level (growth, budgets), a test plot (claim gate, pads, presses + conveyor, collector, fusion, layout sanity, <= 900 parts, no server animation) and HomeFx on the client (owner-only prompts, pop-in, press puffs + blocks, collector screen, pooling) (smoke_p2_homeworld.lua: both worlds)
    server_files.append("smoke_p2_care.lua"); pure_scenarios += ["p2care_stats"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2care_stats")  # pet stats: PetCatalog.GetStats(petId, level, tier), the Phase 4 coin power (TycoonCatalog.PetPower: Economy / Combat 1.6, the stored evolution stage) and the level caps (every rarity 100) (smoke_p2_care.lua: server world, pure)
    server_files.append("smoke_p4_care.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p4care_feed", "p4care_evolve", "p4care_train", "p4care_load", "p4care_exploits"]  # Phase 4 pet care (ARCHITECTURE_V3.md "Phase 4 build contract" 3.4-3.7 / 5.1-5.4 / 7): the Food Machine (no machine refused before paying, FeedPrice / FeedXp per level and machine level, "Level up" batches priced feed by feed, leftovers first and free, the cap 100, a failed XP write refunds, Fed, ONE toast per XP grant with "Ready to evolve!", Cook / GymSet answer one toast, the FeedPrompt / TrainPrompt), EVOLVE (19 / 20 / 49 / 50 x rarities, Common never stage 2, the stored stage, Evolved, OpenPanel("Evolve") to that client only, EquippedInfo, refusals, a training pet may evolve), the Training Place (Train pays / unequips every copy / clears the Garden slot / remembers From, the lock in Equip / GardenSet / ActiveTeamKeys with the preset kept, spots, rank 10, completion by the tick returning the pet, Stop refunds once, a due job stops into a completion), the load paths (a rejoin finishes the job with "Training done while you were away!", two servers completing one job = one rank on a real second DataService copy, a prestige keeps the job, Home.Gym emptied once with one toast, ClearSessions) and exploit attempts (junk / spam / someone else's pets and prompts / Cash never negative) (smoke_p4_care.lua: server world, booted)
    server_files.append("smoke_p2_fusion.lua"); client_files.append("smoke_p2_fusion.lua"); pure_scenarios += ["p2fusion_looks"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2fusion_looks"); server_scenarios[server_scenarios.index("p2care_kitchen" if "p2care_kitchen" in server_scenarios else "shutdown"):server_scenarios.index("p2care_kitchen" if "p2care_kitchen" in server_scenarios else "shutdown")] = ["p2fusion_upgrade", "p2fusion_mix", "p2fusion_exploits"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2fusion")  # Phase 2 Fusion Machine (Phase 4: no Gym placement of a fused result, training inputs refused, the evolution stage and training ranks carried): PetBuilder Golden / Rainbow finishes + hybrid looks (budgets, traits, seeds, nothing floats), FusionService Upgrade / Mix (requirements, costs, records, equipped / Garden copies, atomic, remote junk / spam / proximity) and the FusionController window (smoke_p2_fusion.lua: both worlds)
    server_files.append("smoke_p2_gems.lua"); pure_scenarios += ["p2gems_odds"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2gems_odds"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p2gems_receipts", "p2gems_policy", "p2gems_roulettes", "p2gems_altar"]  # (before the care block: p2care_exploits leaves a dish cooking for p2care_shutdown, and these scenarios advance the clock past its cook time) Phase 2 gems: GemService (gem packs: id 0 hidden, idempotent ProcessReceipt with GemReceipts incl. loading / provisional profiles and failed saves, validated PromptPurchase), PolicyService paid-random-items checks, gem-priced roulettes + the gems-only Secret roulette (Secret pets only from it), the Storm Altar prompt (smoke_p2_gems.lua: server world)
    server_files.append("smoke_p2_ui.lua"); client_files.append("smoke_p2_ui.lua"); pure_scenarios += ["p2ui_content"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2ui_content"); server_scenarios.insert(server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"), "p2ui_tutorial"); client_scenarios.insert(client_scenarios.index("client_final"), "client_p2ui"); mobile_scenarios.append("client_p2ui_mobile")  # Phase 2 UI: the home chapter of the tutorial + NPC tips (content), the tutorial flow claim -> press -> collect -> kitchen (pad path) -> feed on the booted game (before the care block, which leaves a dish cooking for its shutdown check), the Home window / Pets actions / Feed picker / Shop Gems tab / Index Fusions tab on the client and the same windows on a 390x844 phone (smoke_p2_ui.lua: both worlds)
    server_files.append("smoke_p2_flow.lua"); client_files.append("smoke_p2_flow.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p2flow_arrive", "p2flow_build", "p2flow_prestige", "p2flow_fusion_gems", "p2flow_rejoin"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2flow")  # Phase 2 end-to-end flow: three players (new, restricted, a migrated v3 save) through the tutorial, claims, presses, Collector, Garden, Kitchen + feeding, Gym, house tiers, prestige, the DataStore merge after a prestige (both ways), Fusion after prestige, gem receipts, the Secret roulette, leave + rejoin restoring the build on another plot (server world, before the care block); on the client the tutorial card after the finale (a restarted tutorial shows again) (smoke_p2_flow.lua: both worlds)
    server_files.append("smoke_p2_visual.lua"); client_files.append("smoke_p2_visual.lua"); server_scenarios[server_scenarios.index("shutdown"):server_scenarios.index("shutdown")] = ["p2visual_art", "p2visual_plot"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p2visual")  # Phase 2 visual pass: the reworked art (Fusion Machine contract parts + look per level, Garden seedlings, Gym ropes off the front, the Sky Castle rose window), the staked-out house lot, hologram ghosts, the Prestige pad sign, and on the client the locked-pad signs shown only up close, Garden vs Gym pet scale, the opaque Fusion lock card + corner pick marks, the Secret roulette one-line hint (smoke_p2_visual.lua: both worlds)
    server_files.append("smoke_fix_server.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["fixsrv_training_prestige", "fixsrv_receipt_merge", "fixsrv_prestige_merge", "fixsrv_prestige_pad"]  # review fixes (server): a prestige keeps the running training jobs, clears the coin piles and keeps the Garden at L1 (no refund, no double rank), a gem purchase granted once across servers (+ thanks after the save), Cash / prestige Gems follow the prestige rule in the cross-server merge, the Prestige pad only opens the confirmation (smoke_fix_server.lua: server world)
    server_files.append("smoke_fix_leave.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["fixleave_refund", "fixleave_rejoin"]  # leave save order (server): DataService's leave save runs after the other PlayerRemoving handlers, so a leave-time write made when nothing else was unsaved (the Kitchen refund, a late handler's write) is saved instead of lost with the dropped entry, also through an outage (orphan retry); a rejoin in the same frame keeps the entry (smoke_fix_leave.lua: server world, before the care block: these advance the clock past cook times)
    client_files.append("smoke_p2_fix_client.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p2fix_signs", "client_p2fix_pets"]; mobile_scenarios.append("client_p2fix_signs_mobile")  # review fixes (client, HomeFx): pad signs laid out on the screen so none covers another's text (real perspective projection, 1920x1080 + 844x390, no flicker, rebuilt signs keep their answer, lock reasons up close) nor goes under the HUD (menu column, currency pills, vitals, hotbar, touch buttons: 844x390 in the client world and on a touch phone), garden / gym pets built under a per-frame budget (<= 3 a frame, first-time builds alone, the 4 ms time cap) with a pool for homes going out of range (smoke_p2_fix_client.lua: client world)
    server_files.append("smoke_p2_final.lua"); pure_scenarios += ["p2final_docs"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p2final_docs")  # Phase 2 release ("final"): README.md matches the game it documents: the Phase 2 section covers every asked-for part, and its numbers (stations, house tiers, foods, Gym, Garden, Vault, prestige, fusion, roulette / gem prices and odds, the Config.Gems.Products sample, developer tools, tutorial) equal TycoonCatalog / Config / PetCatalog / DevService / TutorialService; every src script is in the project layout, every #anchor resolves (smoke_p2_final.lua: server world, pure)
    server_files.append("smoke_p3_data.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3data_teams", "p3data_battle", "p3data_save"]  # Phase 3 data: DataService battle teams (presets, validation: owned / unique / not in the Garden or Gym / slot 4 at Prestige 1, stale keys pruned after a fusion or a Garden placement, TeamsChanged, ProfileSync Teams with Slots) and the battle record (AddTrophies floor 0, MutateBattle rules, TrialCleared as a dense boolean array), migration from Phase 2, the cross-server merge rules, provisional profiles and the developer /reset of both surviving an autosave (smoke_p3_data.lua: server world, before the care block: p3data_save advances the clock past an autosave)
    server_files.append("smoke_p4_data.lua"); server_scenarios[server_scenarios.index("p3data_save") + 1:server_scenarios.index("p3data_save") + 1] = ["p4data_growth", "p4data_save", "p4data_migrate", "p4data_dev", "p4data_rollout"]  # Phase 4 data (ARCHITECTURE_V3.md "Phase 4 build contract" section 4): PetGrowth (evolution stages, training ranks, the running Job) / Ring / Migrations schema and cleaning, MutateGrowth / MutateRing rules, provisional refusals, the cross-server merges (two servers completing one rank = one rank, Evo max, a stale Job dropped, Ring Best max / Runs delta, Migrations union, LegacySlots / LegacyPrices with the Home) on a REAL second copy of the module, the read-time training lock (ActiveTeamKeys / FieldableKeys / normalizeEquipped skip, presets kept), P3.placedCopies = Gym only, the one-time P4 migration (LegacySlots / LegacyPrices / Gym cleared / marker, idempotent, two servers, after a provisional load, the next prestige), snapshot fields, the developer /reset and /petlevel, and p4data_rollout: the frozen Phase 3 DataService (tools/fixtures/DataService_phase3.lua) saving a Phase 4 profile through the same mock store (smoke_p4_data.lua: server world, booted, right after p3data_save and before the care block: p4data_dev advances the clock past an autosave)
    server_files.append("smoke_p3_battlecore.lua"); pure_scenarios += ["p3battle_catalog", "p3battle_sim", "p4battle_catalog", "p4battle_sim", "p3battle_balance"]; server_scenarios[server_scenarios.index("petbuilder") + 1:server_scenarios.index("petbuilder") + 1] = ["p3battle_catalog", "p3battle_sim", "p4battle_catalog", "p4battle_sim", "p3battle_balance"]  # Phase 3 + 4 battle core (pure; Phase 4: training / evolution / Boost in UnitStats, the loss-XP gate, the Champion Ring data + ChampionTeam + RingRewards, the Ring mode, Defense, the meter rate, overtime and the duel hit cap): BattleCatalog (profiles, specials, synergy, UnitPower / TeamPower, 30 trials, bosses, events, trophies, Validate), BattleSim (determinism, snapshots, commands, retreat, every special, elements, synergy, results, telegraphs, waves, enrage, join / leave, performance), and tools/sim_battle.lua as a library for a short balance subset (smoke_p3_battlecore.lua: server world)
    server_files.append("smoke_p3_arenaworld.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3arena_world", "p3arena_boards", "p3arena_pockets", "p3arena_teleport"]  # Phase 3 arena world: ArenaBuilder (ArenaInfo contract shape, <= 2500 parts, NC_BattleZone zones sized by BattleCatalog.Zones that fit their floors at any rotation, duel pads + Portal_Trials with OpenPanel prompts, placement clear of the lobby, the bridge / portal link, readable world text), the event board + trophy leaderboard (ApplyArenaState, ticking countdowns, junk), private trial pockets (BuildPocket / FreePocket, <= 250 parts, far out in the sky) and the home Arena Gate teleport (owner only, near the gate, refused in a match / battle / cooldown) (smoke_p3_arenaworld.lua: server world, booted, before the care block)
    server_files.append("smoke_p3_battleservice.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3bs_contract", "p3bs_trial", "p3bs_duel", "p3bs_queue", "p3bs_raid", "p3bs_exploits", "p3bs_net"]  # Phase 3 BattleService with 2-8 simulated players: the API + BattleEnded at module load, a full trial (pocket teleport, Start / 10 Hz dense snapshots / End, first-clear and repeat rewards once, the return, forfeit, disconnect, the pocket leash), duels (challenge / decline / expiry / accept, "Lobby" payloads, ring pads, spectators in range only, rewards + PvP counters, forfeits early and late, the pair limit, a disconnect saved as a loss), the quick queue (trophy allowance), boss raids (StartRaid / status / join window / join + leave scaling the boss, EndRaid timeout loss, Double Rewards, a raid nobody joined, a full raid paid by damage tiers), exploit attempts (junk args, other units, bad slots, outside the zone, spam, two battles, teleport tricks, obby match, portal lock, rewards once) and the traffic per client (trial / duel / 8-player raid bytes per second, ~10 Hz, payload hygiene) (smoke_p3_battleservice.lua: server world, booted, before the care block: the raids advance the clock by minutes)
    server_files.append("smoke_p3_events.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3events_pets", "p3events_bosses", "p3events_schedule", "p3events_raid"]  # Phase 3 events: the EventOnly pets (catalog + Index, never in any roulette incl. the gems-only Secret roulette), BossBuilder (four detailed-voxel bosses at High / Low, named joints, budgets, effect points, every pose, enrage glow, telegraph colours), the EventService scheduler (ArenaState on join, the raid announced ~2 min ahead with a toast + fast ArenaState, opened through BattleService, a raid nobody joined), StartNow / EndNow, Double Rewards, the fallback raid payer (once), the event pet shout-out and the developer /raid (smoke_p3_events.lua: server world, booted, before the care block: the schedule advances the clock by minutes)
    server_files.append("smoke_p3_ui.lua"); client_files.append("smoke_p3_ui.lua"); pure_scenarios += ["p3ui_content"]; server_scenarios.insert(server_scenarios.index("petbuilder") + 1, "p3ui_content"); server_scenarios.insert(server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"), "p3ui_tutorial"); client_scenarios.insert(client_scenarios.index("client_final"), "client_p3ui"); mobile_scenarios.append("client_p3ui_mobile")  # Phase 3 UI: tutorial chapter 3 + the battle NPC tips (content), the chapter on the booted game (arena -> team -> trial -> raid, the arrows from ArenaInfo, the reward once), the Team window (presets, slots, slot 4 at Prestige 1, picker, synergy, element wheel, power, TeamSet / TeamSelect), the Stats battle record, ArenaController (Trial window, Arena panel tabs, prompts, side cards: invites, queue, raid, countdown) on the client and the same windows on a 390x844 phone (smoke_p3_ui.lua: both worlds)
    server_files.append("smoke_p3_flow.lua"); client_files.append("smoke_p3_flow.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3flow_arrive", "p3flow_trials", "p3flow_duels", "p3flow_reset", "p3flow_raid", "p3flow_rejoin", "p3flow_solo"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p3flow")  # Phase 3 end-to-end flow with 3-8 players through the remotes: teams (slot 4 at Prestige 1, Garden / Gym pets busy and pruned), a migrated Phase 2 save (its home claimed, the Arena Gate bought and used) + tutorial chapter 3 (arena -> team -> trial -> raid, the reward once), Trials 1-3 won / a trial lost / a repeat, duels by challenge (a spectator, the leaderboard + trophy board) and by queue (a forfeit, a disconnect saved as a loss), the developer /reset between battles (refused while fighting, survives the autosave), Double Rewards (developer start and the scheduled hour), the scheduled Boss Raid from the announcement to the rewards (late joiner, early leavers by LeaveRaid and by disconnect, too late, a spectator, damage tiers, gems, event pets, pet XP, paid once), rejoins restoring teams + records, a Studio Play Solo raid from the DEV button; on the client the flow's real messages replayed as Ava (BattleController trial + raid HUD and result cards, ArenaController Sent card + raid countdown, State teams / record) and Cy's real chapter-3 TutorialState (smoke_p3_flow.lua: both worlds, server chapters before the care block: they advance the clock by up to a few hours)
    server_files.append("smoke_p3_visual.lua"); client_files.append("smoke_p3_visual.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3visual_arena", "p3visual_bosses"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p3visual"); mobile_scenarios.append("client_p3visual_mobile")  # Phase 3 visual pass: crafted arena floors (sand drifts on the boss floor inside the gold line, framed element marks, worn / warm forum paving, ring drifts under the painted circle, pocket drifts, budgets kept, sign titles that fit), bosses that keep their shading and colour regions (belly, frost, ash...) within High <= 1000 / Low <= 760, and on the client the telegraph rim in the attack's saturated colour (gone after the battle), white pet names on the tinted Team / Trial cards and wide enemy cards on a portrait phone (smoke_p3_visual.lua: both worlds)
    server_files.append("smoke_p3_evolved.lua"); client_files.append("smoke_p3_evolved.lua"); pure_scenarios.append("p3evo_pets"); server_scenarios.insert(server_scenarios.index("evolved") + 1, "p3evo_pets"); server_scenarios.insert(server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"), "p3evo_devtools"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p3evo_panel", "client_p3evo_lineup"]; mobile_scenarios.append("client_p3evo_panel_mobile")  # Phase 3 event pets' evolved forms + the merged developer tools: Magma Cub / Rime Wyrmling / Hydralotl have bespoke Evolved and Evolved II looks that echo their boss (signature parts at High and Low, a same-Look twin gets the generic form, caps, wings, aura, animation, EvolutionColors, Golden / Rainbow copies, hybrids, nothing leaks to other pets); Studio Play Solo dev tools (every command has a handler + a TextChatCommand, /pets 0-2 include the event pets, /raid next to the showcase, /devhelp's two toasts list every command and fit); the DEV panel lists every button in order and scrolls at 1920x1080 / 1280x720 / 390x844 / 844x390, Start Boss Raid sends DevCommand('raid'), the help toasts show whole and readable; DevPetShow's Evolved II lineup with the event pets (smoke_p3_evolved.lua: both worlds)
    server_files.append("smoke_p3_fix_server.lua"); client_files.append("smoke_p3_fix_server.lua"); pure_scenarios.append("p3fixsrv_retreat"); server_scenarios.insert(server_scenarios.index("p3battle_balance") + 1, "p3fixsrv_retreat"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3fixsrv_trial1", "p3fixsrv_duel", "p3fixsrv_raid", "p3fixsrv_leave", "p3fixsrv_net16"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p3fixsrv_wire")  # Phase 3 review fixes (server): a timely RETREAT escapes Lines and Circles (lines end past their target, parked teams step aside, a player team resumes ATTACK by itself), Trial 1 = one handicapped pet every single level-1 pet beats + the honest tutorial "team" step, practice duels / no rewards for stomping an idle loser, no raid reward under Raid.MinShare + a weighted head count + Fighters in the raid toast, a void duel when both leave + BattleService.Shutdown, the delta snapshot wire form (16 raiders under 20 KB/s, spectators at 5 Hz, decode round trip) and its decoding in BattleController (smoke_p3_fix_server.lua: both worlds, server chapters before the care block: the raids advance the clock by minutes)
    client_files.append("smoke_p3_fix_client.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p3fixcli_telegraph", "client_p3fixcli_retreat", "client_p3fixcli_landscape", "client_p3fixcli_devhelp", "client_p3fixcli_tutorial"]; mobile_scenarios.append("client_p3fixcli_mobile")  # Phase 3 review fixes (client): telegraph fill completes at the dodge deadline (render delay + round trip + run-out) then flashes, RETREAT! while a telegraph covers my pets; ATTACK! pulse + RESTING countdown to the sim's auto resume, SPECIAL cards say why they wait, the auto Order restores the HUD; practice / tier None / void result lines; on an 844x390 screen (window and touch phone) the team cards take the left edge where the menu tiles step aside, nothing in the screen centre, portrait / wide unchanged; the two /devhelp toasts both readable on a landscape phone (a pushed-out toast waits); an opened tutorial card never covers the vitals or the hotbar and hides behind compact battle cards (smoke_p3_fix_client.lua: client + phone worlds)
    server_files.append("smoke_p3_fixcheck.lua"); client_files.append("smoke_p3_fixcheck.lua"); server_scenarios[server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown"):server_scenarios.index("p2care_kitchen") if "p2care_kitchen" in server_scenarios else server_scenarios.index("shutdown")] = ["p3fixchk_practice", "p3fixchk_wire"]; client_scenarios.insert(client_scenarios.index("client_final"), "client_p3fixchk_join")  # Phase 3 fix re-checks (fixcheck): a practice duel counts for nothing either way (leaving it costs no trophies / PvP loss, a double leave refunds nothing it never took), the delta snapshot stream of every receiver (fighter from the start, a spectator who joins as the 16th raider, a late spectator) equals BattleSim:Snapshot() at every T through a leaver and two minion waves, spectators ~5 Hz, a fighter under 20 KB/s through the waves; on the client a raid spectator who joins (second Start, full snapshot, deltas), a team leaving and a minion wave all drawn where the sim has them (smoke_p3_fixcheck.lua: both worlds, server chapters before the care block)
    if args.list:
        print("server:", ", ".join(server_scenarios))
        print("client:", ", ".join(client_scenarios + mobile_scenarios))
        print("files: ", ", ".join(["smoke_common.lua"] + server_files + client_files))
        return 0

    # every tools/smoke_*.lua must be loaded by one of the worlds, otherwise its scenarios silently never run
    client_files.append("smoke_p3_battleclient.lua"); client_scenarios[client_scenarios.index("client_final"):client_scenarios.index("client_final")] = ["client_p3battle_trial", "client_p3battle_raid", "client_p3battle_spectate"]; mobile_scenarios.append("client_p3battle_mobile")  # Phase 3 BattleController (client): a real BattleSim fed through BattleState like BattleService sends it; followers parked while InBattle, the battle HUD only while fighting, intact welded unit models, smooth 60 fps interpolation of 10 Hz snapshots, world damage numbers (pixel billboards, never centred), F / R / 1-4 via ContextActionService only in battle, throttle + regroup lock + full-meter specials, focus by chip / world tap, raid boss + telegraphs that fill and vanish + minions + enrage + leavers, effect caps, spectators without controls, junk messages, the result card, the compact touch HUD on a phone (smoke_p3_battleclient.lua: client + phone worlds)
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
