"""Checks of the evolved art keys (W2 art-evolved).  No bpy, no lupa: reads the catalog and the generated manifests.

    python3 blender/kit/detail/evolved_check.py        # exit 1 on any failure

* blender/catalog/evolved.json is what detail/evolved_catalog.py writes (not hand-edited, not stale)
* every evolved key has its generated src/shared/MeshManifests/<key>.lua and a blender/meshes.json entry
* body keys: Kind pet, Meta.stage 1|2, an `Aura` group (kind orbit) whose parts are Neon and named Aura..., stage 2
  bodies also a `Halo` group (kind bob); EyeLid groups present (blinks); the gem glint is Neon
* wing keys: one group (WingL / WingR / Wing2L / Wing2R) with Attach = that group name and parts named after it
* per set (body + wings): triangles within the recipe 4.2 budget, every part <= 10k triangles
A key that has no manifest yet (not built) is reported as missing.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, HERE)
LUA = os.path.join(REPO, "src", "shared", "MeshManifests")

FAILS = []


def check(cond, name, detail=""):
    if not cond:
        FAILS.append("%s %s" % (name, detail))
        print("FAIL", name, detail)
    return cond


def parse_manifest(key):
    """the few fields we need from the generated Lua (it is a plain, sorted table: regexes are enough)"""
    path = os.path.join(LUA, key + ".lua")
    if not os.path.exists(path):
        return None
    src = open(path).read()
    parts = []
    for m in re.finditer(r"\{\n\t\t\tCenter = .*?\n\t\t\},?\n", src, re.S):
        blk = m.group(0)
        g = lambda f: (re.search(r"\b%s = \"([^\"]*)\"" % f, blk) or [None, None])[1]  # noqa: E731
        t = re.search(r"\bTris = (\d+)", blk)
        parts.append({"Name": g("Name"), "Group": g("Group"), "Key": g("Key"), "Material": g("Material"),
                      "Tris": int(t.group(1)) if t else 0})
    groups = {}
    gm = re.search(r"\n\tGroups = \{\n(.*?)\n\t\},\n", src, re.S)
    if gm:
        for m in re.finditer(r"\n?\t\t(\w+) = \{\n(.*?)\n\t\t\},", gm.group(1), re.S):
            body = m.group(2)
            kind = re.search(r"Kind = \"(\w+)\"", body)
            att = re.search(r"Attach = \"(\w+)\"", body)
            groups[m.group(1)] = {"Kind": kind and kind.group(1), "Attach": att and att.group(1)}
    tris = re.search(r"\n\tTris = (\d+)", src)
    stage = re.search(r"\bstage = (\d+)", src)
    kind = re.search(r"\n\tKind = \"(\w+)\"", src)
    return {"Parts": parts, "Groups": groups, "Tris": int(tris.group(1)) if tris else 0,
            "Stage": int(stage.group(1)) if stage else None, "Kind": kind and kind.group(1)}


def main():
    import evolved_catalog as EC
    cat_path = EC.CATALOG
    want = json.dumps(EC.catalog(), indent=1) + "\n"
    check(os.path.exists(cat_path) and open(cat_path).read() == want,
          "catalog: blender/catalog/evolved.json is generated and up to date")
    cat = json.loads(want)
    idx = {}
    ip = os.path.join(REPO, "blender", "meshes.json")
    if os.path.exists(ip):
        idx = json.load(open(ip)).get("keys", {})
    mans = {}
    missing = []
    for e in cat["keys"]:
        m = parse_manifest(e["key"])
        if m is None:
            missing.append(e["key"])
            continue
        mans[e["key"]] = m
        check(e["key"] in idx, "index: %s in blender/meshes.json" % e["key"])
        names = [p["Name"] for p in m["Parts"]]
        check(len(names) == len(set(names)), "names: %s unique part names" % e["key"])
        check(max([p["Tris"] for p in m["Parts"]] or [0]) <= 10000, "budget: %s every part <= 10k tris" % e["key"])
        if e["type"] == "pet":
            st = int(e["stage"])
            check(m["Kind"] == "pet" and m["Stage"] == st, "body: %s Kind pet, stage %d" % (e["key"], st))
            aura = m["Groups"].get("Aura")
            check(aura is not None and aura["Kind"] == "orbit", "aura: %s has an Aura orbit group" % e["key"])
            ap = [p for p in m["Parts"] if p["Group"] == "Aura"]
            check(all(p["Name"].startswith("Aura") for p in ap) and sum(p["Material"] == "Neon" for p in ap) >= 1,
                  "aura: %s Aura parts named Aura..., at least one Neon (the pulse finds it)" % e["key"],
                  [(p["Name"], p["Material"]) for p in ap])
            if st == 2:
                h = m["Groups"].get("Halo")
                check(h is not None and h["Kind"] == "bob", "aura: %s (second evolution) has a Halo bob group" % e["key"])
            check(any(g.startswith("EyeLid") for g in m["Groups"]), "face: %s has blink lids" % e["key"])
            for p in m["Parts"]:
                if p["Key"] == "GemGlint":
                    check(p["Material"] == "Neon", "gems: %s GemGlint is Neon" % e["key"])
        else:
            gname = e.get("group", "Wing") + e["side"]
            g = m["Groups"].get(gname)
            check(g is not None and g["Attach"] == gname and len(m["Groups"]) == 1,
                  "wing: %s one group %s attached at %s" % (e["key"], gname, gname))
            check(all(p["Name"].startswith(gname) for p in m["Parts"]), "wing: %s parts named %s..." % (e["key"], gname))
    for s in cat["sets"]:
        if not all(k in mans for k in s["keys"]):
            continue
        b = cat["budgets"][s["budget"]]
        tris = sum(mans[k]["Tris"] for k in s["keys"])
        parts = sum(len(mans[k]["Parts"]) for k in s["keys"])
        check(tris <= b["tris"] and parts <= b["parts"], "set: %s %d / %d tris, %d / %d parts" % (
            s["name"], tris, b["tris"], parts, b["parts"]))
    check(not missing, "built: every evolved key has a generated manifest (missing %d)" % len(missing), missing[:12])
    print("evolved_check: %d keys, %d failures" % (len(cat["keys"]), len(FAILS)))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
