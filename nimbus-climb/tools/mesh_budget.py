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


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scene", help="scene JSON (default: the 16-player lobby)")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--keys", action="store_true", help="also print every key")
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
    over = (b.get("tris") and tris > b["tris"]) or (b.get("parts") and parts > b["parts"])
    if a.check and over:
        print("OVER BUDGET")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
