"""Writes blender/catalog/evolved.json (W2 art-evolved; ARCHITECTURE_V3.md 6.0.4 / 6.2 / 6.3, recipe 4.2 / 4.6).

    python3 blender/kit/detail/evolved_catalog.py            # rewrite the catalog from src/shared/PetCatalog.lua
    python3 blender/kit/detail/evolved_catalog.py --check    # exit 1 when the committed catalog is stale

Every pet gets a first evolution, Epic / Legendary / Mythic / Secret pets (PetCatalog.EvolveTwice) a second one:

    evo1_<petId>[_low]                  body (+ Tail, Halo, Aura, EyeLid groups) at the root pivot, K 1.25 / Low 0.65
    evo2_<petId>[_low]                  the same for the second evolution, K 1.125 / Low 0.55
    evowing_<petId>_1_<L|R>[_low]       stage 1 wings (group Wing; pivot = the body's WingL / WingR attachment)
    evowing_<petId>_2_<L|R>[_low]       stage 2 first pair (group Wing)
    evowing_<petId>_2b_<L|R>[_low]      stage 2 second, lower pair (group Wing2; pivot = Wing2L / Wing2R)
                                        (phantom_kitsune has no second pair: its nine tails replace it)

The aura meshes (orbiting rings, element bits, light crowns) are the body key's own `Aura` (kind orbit) and
`Halo` (kind bob) groups, made by kit/detail/evolved.py; their colours are per pet constants, so they live with
the body instead of shared aura_<kind> keys.  Evolved colours are per pet constants too (EVO.Look / ASC.Look), so
each pet has its own wing keys.  k is ABSOLUTE (PetBuilder._Blueprint), budgets are recipe 4.2 per set.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CATALOG = os.path.join(REPO, "blender", "catalog", "evolved.json")
PET_CATALOG = os.path.join(REPO, "src", "shared", "PetCatalog.lua")

K = {(1, "High"): 1.25, (1, "Low"): 0.65, (2, "High"): 1.125, (2, "Low"): 0.55}
PASSES = ["evolved:body", "evolved:aura"]
PASSES_LOW = ["evolved:body", "evolved:aura"]  # Low: the kit's pixel eyes read better than the Lua masks
# the evolved faces keep the game's own carved Lua eyes and mouth (drawn for the evolved heads; the kit's procedural
# eyes mis-read them): "eyes": "lua" (petkit.face_pass runs the passes on that path too since W2.5; the old
# evolved:lua_eyes hook gave byte-identical keys and was removed)
FACE = {"eyes": "lua", "features": False}

# recipe 4.2: evolved 1 <= 15k / 50 parts (Low 4.5k / 16), evolved 2 <= 20k / 60 (Low 6k / 18) per SET (body + wings);
# keys get a share so the K step-down happens on the body first.  Part counts: see the doc string of BUDGETS_DOC.
BUDGETS = {
    "evo1Body": {"tris": 11500, "parts": 44, "maxPartTris": 10000},
    "evo1BodyLow": {"tris": 3700, "parts": 36, "maxPartTris": 10000},
    "evo1Wing": {"tris": 1750, "parts": 12},
    "evo1WingLow": {"tris": 400, "parts": 8},
    "evo1WingLowBat": {"tris": 550, "parts": 8},
    "evo1BodyLowBat": {"tris": 3400, "parts": 36, "maxPartTris": 10000},
    "evo2Body": {"tris": 14800, "parts": 50, "maxPartTris": 10000},
    "evo2BodyLow": {"tris": 4500, "parts": 40, "maxPartTris": 10000},
    "evo2Wing": {"tris": 1700, "parts": 16},
    "evo2WingLow": {"tris": 450, "parts": 10},
    "evo2Wing2": {"tris": 900, "parts": 14},
    "evo2Wing2Low": {"tris": 300, "parts": 10},
    "evo1": {"tris": 15000, "parts": 64},
    "evo1Low": {"tris": 4500, "parts": 52},
    "evo2": {"tris": 20000, "parts": 110},
    "evo2Low": {"tris": 6000, "parts": 84},
}
BUDGETS_DOC = ("Sets (body + wings) keep the recipe 4.2 triangle budgets (evo1 15k / Low 4.5k, evo2 20k / Low 6k). "
               "MeshPart counts follow the 4.3 name contract (one part per group, key and shade; wings are separate "
               "L / R keys, up to 16 parts per wing), so the set part caps are 64 / Low 52 (evo1) and 110 / Low 84 "
               "(evo2) instead of 50 / 16 and 60 / 18 (the same deviation as the kit's base-pet Low sets). Still far "
               "below the Part build (1500-2000 parts High). evo1 bodies may take 44 parts: keys the game or a test "
               "looks up by name (tools/mesh_names.py: Spark, Frost, CrystalDeep, Basalt, HydraHead ...) are never "
               "baked into Fixed (recipe 4.3).")
NO_WING2 = {"phantom_kitsune"}
# first evolutions whose Low bat wings are big (828 tris at K 0.65): the wings get more, the body less
LOW_BAT = {"twilight_dragon", "eclipse_dragon", "hydralotl"}
PREVIEWS1 = ["pebble_pup", "maple_fox", "twilight_dragon", "ember_phoenix", "phantom_kitsune", "magma_cub"]
PREVIEWS2 = ["aurora_fox", "twilight_dragon", "candy_unicorn", "stormfang", "phantom_kitsune", "hydralotl"]


def read_pets():
    src = open(PET_CATALOG).read()
    pets = re.findall(r'Id = "([a-z_]+)", Name = "[^"]*", Rarity = "([A-Za-z]+)"', src)
    m = re.search(r"EvolveTwice\s*=\s*\{([^}]*)\}", src)
    twice = set(re.findall(r"([A-Za-z]+)\s*=\s*true", m.group(1))) if m else {"Epic", "Legendary", "Mythic", "Secret"}
    return [(pid, rar, 2 if rar in twice else 1) for pid, rar in pets]


def sfx(lod):
    return "_low" if lod == "Low" else ""


def wing_key(pid, style, side, lod):
    return "evowing_%s_%s_%s%s" % (pid, style, side, sfx(lod))


def entries():
    keys, sets, previews = [], [], []
    pets = read_pets()
    for stage in (1, 2):
        for pid, rar, top in pets:
            if stage > top:
                continue
            for lod in ("High", "Low"):
                low = lod == "Low"
                k = K[(stage, lod)]
                body = "evo%d_%s%s" % (stage, pid, sfx(lod))
                e = {"key": body, "type": "pet", "pet": pid, "stage": stage, "k": k,
                     "budget": "evo%dBody%s" % (stage, "Low" if low else ""), "passes": PASSES_LOW if low else PASSES,
                     "face": {} if low else FACE,
                     "description": "Evolved pet: %s, %s evolution, %s" % (
                         pid.replace("_", " "), "first" if stage == 1 else "second", lod)}
                # evolved colours are per pet constants: every constant key nothing looks up by name is baked into one
                # `Fixed` part (fewer MeshParts; Neon and referenced keys stay their own parts)
                e["fixed"] = True
                if low:
                    e["lod"] = "Low"
                    if stage == 1 and pid in LOW_BAT:
                        e["budget"] = "evo1BodyLowBat"
                keys.append(e)
                set_keys = [body]
                pairs = [("Wing", str(stage))]
                if stage == 2 and pid not in NO_WING2:
                    pairs.append(("Wing2", "2b"))
                for group, style in pairs:
                    for side in ("L", "R"):
                        wk = wing_key(pid, style, side, lod)
                        w = {"key": wk, "type": "wing", "pet": pid, "stage": stage, "side": side, "k": k,
                             "group": group, "budget": "evo%d%s%s" % (stage, "Wing2" if group == "Wing2" else "Wing",
                                                                      "Low" if low else ""),
                             "description": "Evolved wing: %s, stage %d, %s %s, %s" % (
                                 pid.replace("_", " "), stage, group, side, lod)}
                        if low:
                            w["lod"] = "Low"
                            if stage == 1 and pid in LOW_BAT:
                                w["budget"] = "evo1WingLowBat"
                        keys.append(w)
                        set_keys.append(wk)
                sets.append({"name": body, "keys": set_keys, "budget": "evo%d%s" % (stage, "Low" if low else "")})
                if not low and pid in (PREVIEWS1 if stage == 1 else PREVIEWS2):
                    previews.append({"name": body, "body": body, "attach": set_keys[1:], "res": 400})
    return keys, sets, previews


def catalog():
    keys, sets, previews = entries()
    return {
        "class": "evolved",
        "owner": "W2 art-evolved",
        "doc": ("GENERATED by blender/kit/detail/evolved_catalog.py (edit that, then run it). Keys: evo1_<petId>[_low], "
                "evo2_<petId>[_low] (body + Tail / Halo / Aura / EyeLid groups), evowing_<petId>_<1|2|2b>_<L|R>[_low] "
                "(1 = stage 1 Wing pair, 2 = stage 2 Wing pair, 2b = stage 2 Wing2 pair; pivot = the body's WingL/R or "
                "Wing2L/R attachment). Aura meshes are the body's Aura (orbit) and Halo (bob) groups (kit/detail/"
                "evolved.py). k is absolute (1.25 / 1.125, Low 0.65 / 0.55). " + BUDGETS_DOC),
        "budgets": BUDGETS,
        "keys": keys,
        "sets": sets,
        "previews": previews,
    }


def main():
    text = json.dumps(catalog(), indent=1) + "\n"
    if "--check" in sys.argv:
        cur = open(CATALOG).read() if os.path.exists(CATALOG) else ""
        if cur != text:
            print("blender/catalog/evolved.json is stale: run python3 blender/kit/detail/evolved_catalog.py")
            return 1
        print("evolved.json up to date")
        return 0
    with open(CATALOG, "w") as fh:
        fh.write(text)
    k, s, p = entries()
    print("wrote %s: %d keys, %d sets, %d previews" % (os.path.relpath(CATALOG, REPO), len(k), len(s), len(p)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
