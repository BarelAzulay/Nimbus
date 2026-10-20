#!/usr/bin/env python3
"""Triangle / MeshPart budget of a scene, summed from the generated mesh manifests (Phase 6, recipe 4.2).

    python3 tools/mesh_budget.py                 the key table + the default scene (the busiest phone view)
    python3 tools/mesh_budget.py --scene my.json --check

Reads src/shared/MeshManifests/<key>.lua (Tris + Parts) and blender/meshes.json.  A scene says how many copies of
what are in view:
    {"name": "lobby16", "budget": {"tris": 300000, "parts": 400},
     "pets": {"High": 3, "Low": 45},          # pet sets (body + wings + accessory), the heaviest built set per LOD
     "petClasses": ["pets"],                  # catalogs whose sets count as pet sets (default: pets; never bosses)
     "keys": {"gate_obby": 1, "cloud_big_1": 12},   # placements of world keys (missing keys are listed, not counted)
     "include": [{"scene": "docs/phase6/review/home/plot_scene.json", "count": 4}]}   # other scenes' keys x count
The default scene is the contract's worst case: 16 players x 3 pets in the lobby (own 3 pets High, 45 others Low)
plus every gate / lobby key built so far once, plus the home plots a phone sees from the plaza (the 16 plots stand
on the 340-stud spot ring: a ~90 degree view takes in a quarter of it = 4 max-tier plots; the line "all 16 plots"
gives the whole ring).  MeshParts approximate draw calls (one per part and material).
--check exits 1 when the scene is over its budget.

Plot LOD (perf-plots, Phase 6 W3): the default run also prints the busiest views with the client plot LOD that
src/client/Controllers/HomeFx.lua applies (LOD_* below mirror its K.LOD_*; tools/smoke_p6_lod.lua checks the parity):
a plot closer than LOD_HIGH studs to the camera shows every High key; a "Low" plot shows every mesh on its `<key>_low`
key (the High key while no _low key exists); a "Far" plot (>= LOD_FAR) shows only the landmarks (house + the lobby's
plot base, prop_plot, one per plot) on _low keys, stations and decor hidden.  Two views: the contract's
(4 plots seen from the plaza centre, 340 studs) and the worst phone view sampled over the plaza (a 70-degree vertical
FOV at 19.5:9 = 113 degrees across, the camera 13 studs behind a player anywhere on the plaza, any yaw).  Each is shown
before the rule, with the rule on today's keys, and with the rule plus the requested _low keys (real manifests when
they exist, else docs/phase6/review/home/low_keys_estimate.json, measured with the kit in a scratch run).
    --lod-check    exit 1 when the contract view with the rule and the requested _low keys is over its budget
"""
import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAN_DIR = os.path.join(ROOT, "src", "shared", "MeshManifests")
CATALOG_DIR = os.path.join(ROOT, "blender", "catalog")

PLOT_SCENE = "docs/phase6/review/home/plot_scene.json"
LOW_ESTIMATE = "docs/phase6/review/home/low_keys_estimate.json"
PLOT_BASE = "prop_plot"  # the lobby's plot island (one per spot; LobbyBuilder tags it, HomeFx's LOD drives it)
# [perf-plots] the client plot LOD (HomeFx K.LOD_*): tier by camera distance to the plot centre
LOD_HIGH = 120
LOD_FAR = 200
LOD_HYST = 20
LOD_CLASS = [("prop_plot", "landmark"), ("home_house_", "landmark"), ("home_fence_", "decor"), ("home_fountain_", "decor"),
             ("home_podium_", "decor"), ("home_bed_", "decor")]
LOD_LEVEL = {"High": {"landmark": "High", "station": "High", "decor": "High"},
             "Low": {"landmark": "Low", "station": "Low", "decor": "Low"},
             "Far": {"landmark": "Low", "station": "Hide", "decor": "Hide"}}
# the phone camera on the plaza (Roblox default FieldOfView 70 is vertical; a 19.5:9 landscape phone)
PHONE_VFOV, PHONE_ASPECT, CAM_BACK, PLOT_RADIUS = 70.0, 19.5 / 9.0, 13.0, 50.0
# [perf-plots] proposed part budget for contract 6.5 (see part_budget()): MeshParts in view and distinct mesh batches
PART_BUDGET = {"instances": 3000, "batches": 700}
PLOTS_IN_VIEW = 4  # of Config.Lobby.SpotCount = 16 on the spot ring (a quarter of the ring in a phone view)
DEFAULT_SCENE = {"name": "lobby16 (16 players x 3 pets, phone)", "budget": {"tris": 300000, "parts": 400},
                 "pets": {"High": 3, "Low": 45}, "petClasses": ["pets"], "keys": {},
                 "worldClasses": ["gates", "lobby"], "include": [{"scene": PLOT_SCENE, "count": PLOTS_IN_VIEW}]}


def read_manifests():
    out = {}
    for path in sorted(glob.glob(os.path.join(MAN_DIR, "*.lua"))):
        txt = open(path, encoding="utf-8").read()
        key = os.path.splitext(os.path.basename(path))[0]
        m = re.search(r"^\tTris = (\d+),", txt, re.M)
        parts = len(re.findall(r"^\t\t\{\n\t\t\tCenter = ", txt, re.M)) or len(re.findall(r"\bShade = \"", txt))
        out[key] = {"tris": int(m.group(1)) if m else 0, "parts": parts}
    return out


def catalog_sets():
    sets = []
    for path in sorted(glob.glob(os.path.join(CATALOG_DIR, "*.json"))):
        c = json.load(open(path))
        for s in c.get("sets", []):
            sets.append(dict(s, cls=c.get("class")))
    return sets


def catalog_keys(classes):
    keys = []
    for path in sorted(glob.glob(os.path.join(CATALOG_DIR, "*.json"))):
        c = json.load(open(path))
        if c.get("class") in classes:
            keys += [e["key"] for e in c.get("keys", [])]
    return keys


def scene_total(scene, mans):
    rows, missing = [], []
    tris = parts = 0
    pet_classes = set(scene.get("petClasses") or ["pets"])
    # pet sets only (body + wings + accessory of a catalog pet): boss / dragon / creature sets are not pets
    sets = [s for s in catalog_sets() if s.get("cls") in pet_classes]
    for lod, n in sorted((scene.get("pets") or {}).items()):
        best = None
        for s in sets:
            low = s["name"].endswith("_low")
            if (lod == "Low") != low:
                continue
            if all(k in mans for k in s["keys"]):
                t = sum(mans[k]["tris"] for k in s["keys"])
                p = sum(mans[k]["parts"] for k in s["keys"])
                if best is None or t > best[1]:
                    best = (s["name"], t, p)
        if best is None:
            missing.append("pet set %s" % lod)
            continue
        rows.append(("%d x pet set %s (%s)" % (n, lod, best[0]), n * best[1], n * best[2]))
        tris += n * best[1]
        parts += n * best[2]
    keys = dict(scene.get("keys") or {})
    for k in catalog_keys(scene.get("worldClasses", [])):
        keys.setdefault(k, 1)
    for k, n in sorted(keys.items()):
        if k not in mans:
            missing.append(k)
            continue
        rows.append(("%d x %s" % (n, k), n * mans[k]["tris"], n * mans[k]["parts"]))
        tris += n * mans[k]["tris"]
        parts += n * mans[k]["parts"]
    for inc in scene.get("include") or []:
        path = inc["scene"] if os.path.isabs(inc["scene"]) else os.path.join(ROOT, inc["scene"])
        sub = json.load(open(path))
        sub = dict(sub, pets={})  # an included scene adds its world keys only (the pets are counted above)
        n = int(inc.get("count", 1))
        _, t, p, miss = scene_total(sub, mans)
        rows.append(("%d x scene: %s" % (n, sub.get("name", inc["scene"])), n * t, n * p))
        tris += n * t
        parts += n * p
        missing += ["%s (in %s)" % (m, os.path.basename(path)) for m in miss]
    return rows, tris, parts, missing


def lod_class(key):
    for prefix, cls in LOD_CLASS:
        if key.startswith(prefix):
            return cls
    return "station"


def lod_tier(dist, prev=None):
    """HomeFx G.lodTier: hysteresis keeps a plot in High until LOD_HIGH + LOD_HYST and in Far until LOD_FAR - LOD_HYST"""
    high = LOD_HIGH + LOD_HYST if prev == "High" else LOD_HIGH
    far = LOD_FAR - LOD_HYST if prev == "Far" else LOD_FAR
    return "High" if dist < high else ("Low" if dist < far else "Far")


def low_estimates():
    path = os.path.join(ROOT, LOW_ESTIMATE)
    try:
        return json.load(open(path)).get("keys", {})
    except (OSError, ValueError):
        return {}


def plot_keys():
    keys = dict(json.load(open(os.path.join(ROOT, PLOT_SCENE))).get("keys") or {})
    keys[PLOT_BASE] = 1
    return keys


def plot_cost(tier, mans, est=None):
    """(tris, parts, missing) of one max-tier plot + its base at a LOD tier; est = the _low estimates (None: real keys
    only, a missing _low key keeps its High key exactly like MeshLibrary.LowKey does)"""
    tris = parts = 0
    missing = []
    for key, n in sorted(plot_keys().items()):
        if key not in mans:
            continue
        level = LOD_LEVEL[tier][lod_class(key)]
        if level == "Hide":
            continue
        use = mans[key]
        if level == "Low":
            low = key + "_low"
            if low in mans:
                use = mans[low]
            elif est is not None and low in est:
                use = est[low]
            elif not key.startswith("home_bed_"):  # bed pieces (<= 120 tris each) keep their High key: no _low asked
                missing.append(low)
        tris += n * use["tris"]
        parts += n * use["parts"]
    return tris, parts, missing


def config_number(name, default):
    try:
        txt = open(os.path.join(ROOT, "src", "shared", "Config.lua"), encoding="utf-8").read()
        m = re.search(r"\b%s = ([0-9.]+)" % name, txt)
        return float(m.group(1)) if m else default
    except OSError:
        return default


def plaza_views():
    """every sampled phone view on the plaza: (player radius, yaw degrees, sorted plot distances in view)"""
    import math
    ring, count, plaza = config_number("SpotRingRadius", 340), int(config_number("SpotCount", 16)), config_number("PlazaRadius", 150)
    half = math.atan(math.tan(math.radians(PHONE_VFOV / 2)) * PHONE_ASPECT)
    views = []
    for r in range(0, int(plaza) + 1, 10):
        for yaw in range(0, 360, 3):
            ya = math.radians(yaw)
            cx, cz = r - CAM_BACK * math.cos(ya), -CAM_BACK * math.sin(ya)
            ds = []
            for i in range(count):
                t = 2 * math.pi * i / count + 0.1
                dx, dz = ring * math.cos(t) - cx, ring * math.sin(t) - cz
                d = math.hypot(dx, dz)
                off = abs((math.atan2(dz, dx) - ya + math.pi) % (2 * math.pi) - math.pi)
                if off - math.asin(min(1.0, PLOT_RADIUS / d)) <= half:
                    ds.append(d)
            views.append((r, yaw, sorted(ds)))
    return views


def base_scene():
    """the default scene without its plots and without the one prop_plot the lobby keys count (it goes per plot)"""
    sc = dict(DEFAULT_SCENE, include=[], keys={PLOT_BASE: 0})
    return sc


def scene_with_plots(mans, dists, mode, est):
    """base + plots at distances `dists`; mode "before" (no LOD, every plot High), "today" (rule, real keys),
    "requested" (rule + _low estimates for keys not built yet)"""
    rows, t, p, _ = scene_total(base_scene(), mans)
    plots = []
    for d in dists:
        tier = "High" if mode == "before" else lod_tier(d)
        pt, pp, _ = plot_cost(tier, mans, est if mode == "requested" else None)
        t += pt
        p += pp
        plots.append((d, tier, pt))
    return t, p, plots


def part_budget(mans, views_parts):
    """MeshParts in view (instances) and distinct (key, part) batches: Roblox instances identical meshes, so draw calls
    follow distinct mesh assets, not copies (Studio's MicroProfiler is the final word)"""
    sets = [s for s in catalog_sets() if s.get("cls") == "pets"]
    low_keys, high_keys = set(), set()
    for s in sets:
        if all(k in mans for k in s["keys"]):
            (low_keys if s["name"].endswith("_low") else high_keys).update(s["keys"])
    world = set(catalog_keys(["gates", "lobby"])) | set(plot_keys())
    batches = sum(mans[k]["parts"] for k in (low_keys | world) if k in mans)
    # 3 own pets: the 3 heaviest High sets
    best = sorted((sum(mans[k]["parts"] for k in s["keys"]), s["name"]) for s in sets
                  if not s["name"].endswith("_low") and all(k in mans for k in s["keys"]))[-3:]
    batches += sum(b[0] for b in best)
    return views_parts, batches


def lod_report(mans):
    est = low_estimates()
    budget = DEFAULT_SCENE["budget"]
    print()
    print("plot LOD (HomeFx K.LOD_*: High < %d studs, Far >= %d, hysteresis %d): one max-tier plot + its %s"
          % (LOD_HIGH, LOD_FAR, LOD_HYST, PLOT_BASE))
    missing_low = set()
    for tier in ("High", "Low", "Far"):
        t1, p1, miss = plot_cost(tier, mans)
        t2, p2, _ = plot_cost(tier, mans, est)
        missing_low |= set(miss)
        print("  %-5s %8d tris %4d parts  (with the requested _low keys: %6d tris %4d parts)" % (tier, t1, p1, t2, p2))
    if missing_low:
        print("  _low keys not built yet (requested; their High key stays until then):", ", ".join(sorted(missing_low)))
    views = plaza_views()
    contract = [config_number("SpotRingRadius", 340)] * PLOTS_IN_VIEW
    worst_n = max(views, key=lambda v: (len(v[2]), -v[2][0] if v[2] else 0))
    # the worst view after the rule: the most triangles with the requested keys
    worst_t = max(views, key=lambda v: scene_with_plots(mans, v[2], "requested", est)[0])
    print()
    print("busiest phone views (budget %d tris):" % budget["tris"])
    out = {}
    for label, dists in (("contract view: %d plots from the plaza centre" % len(contract), contract),
                         ("most plots in view (r %d, yaw %d): %d plots" % (worst_n[0], worst_n[1], len(worst_n[2])), worst_n[2]),
                         ("most triangles after the rule (r %d, yaw %d): %d plots" % (worst_t[0], worst_t[1], len(worst_t[2])), worst_t[2])):
        print("  " + label + " at " + ", ".join("%d" % d for d in dists) + " studs")
        for mode, text in (("before", "before (no LOD)"), ("today", "LOD rule, today's keys"),
                           ("requested", "LOD rule + requested _low keys (estimate)")):
            t, p, plots = scene_with_plots(mans, dists, mode, est)
            tiers = "/".join(x[1][0] for x in plots)
            print("    %-44s %8d tris %5d parts  [%s]%s" % (text, t, p, tiers, "  OVER" if t > budget["tris"] else ""))
            out[(label[:8], mode)] = (t, p)
    inst = scene_with_plots(mans, worst_n[2], "requested", est)[1]
    _, _, evo_parts, _ = scene_total(dict(base_scene(), petClasses=["evolved"]), mans)
    evo_parts += sum(plot_cost(lod_tier(d), mans, est)[1] for d in worst_n[2])
    _, batches = part_budget(mans, inst)
    print()
    print("part budget (proposed for contract 6.5, replaces '400 parts'): <= %d MeshParts in view (worst view %d, every"
          " pet a second evolution %d) and <= %d distinct mesh batches (every Low pet set + 3 High sets + every lobby /"
          " gate / plot key once: %d)" % (PART_BUDGET["instances"], inst, evo_parts, PART_BUDGET["batches"], batches))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scene", help="scene JSON (default: the 16-player lobby)")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--keys", action="store_true", help="also print every key")
    ap.add_argument("--lod-check", action="store_true", help="exit 1 when the contract view with the plot LOD and the"
                    " requested _low keys is over budget")
    a = ap.parse_args()
    mans = read_manifests()
    scene = json.load(open(a.scene)) if a.scene else DEFAULT_SCENE
    if a.keys or not a.scene:
        print("%-24s %7s %6s" % ("key", "tris", "parts"))
        for k in sorted(mans):
            print("%-24s %7d %6d" % (k, mans[k]["tris"], mans[k]["parts"]))
        print()
    rows, tris, parts, missing = scene_total(scene, mans)
    print("scene:", scene.get("name"))
    for label, t, p in rows:
        print("  %-52s %8d tris %5d parts" % (label, t, p))
    b = scene.get("budget") or {}
    print("  %-52s %8d / %s tris %5d / %s parts" % ("TOTAL", tris, b.get("tris"), parts, b.get("parts")))
    if missing:
        print("  not built yet (not counted):", ", ".join(missing))
    if not a.scene:
        # the whole spot ring and the evolved worst case, for reference (not part of the default scene's check)
        ring = dict(DEFAULT_SCENE, include=[{"scene": PLOT_SCENE, "count": 16}])
        evo = dict(DEFAULT_SCENE, petClasses=["evolved"])
        for label, sc in (("all 16 plots in view", ring), ("every pet a second evolution (evolved sets)", evo)):
            _, t2, p2, _ = scene_total(sc, mans)
            print("  %-52s %8d tris %5d parts" % ("(if " + label + ")", t2, p2))
    if not a.scene:
        lod = lod_report(mans)
        if a.lod_check and lod[("contract", "requested")][0] > DEFAULT_SCENE["budget"]["tris"]:
            print("OVER BUDGET (contract view with the plot LOD)")
            return 1
    over = (b.get("tris") and tris > b["tris"]) or (b.get("parts") and parts > b["parts"])
    if a.check and over:
        print("OVER BUDGET")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
