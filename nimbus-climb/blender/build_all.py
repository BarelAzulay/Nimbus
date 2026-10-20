"""Build the Blender mesh keys of Nimbus Climb (Phase 6; ARCHITECTURE_V3.md 6.1 A4 / A5, recipe 4.1 - 4.6).

    /tmp/claude-0/bpyenv/bin/python blender/build_all.py --class pets            # one catalog (blender/catalog/pets.json)
    /tmp/claude-0/bpyenv/bin/python blender/build_all.py --key pet_dog --key acc_crown
    /tmp/claude-0/bpyenv/bin/python blender/build_all.py --all --preview
    python3 blender/build_all.py --key pet_dog --no-export                          # numbers + manifests only, no bpy

Per key: build the model (bridge / props / calibration), check the class budgets (too many triangles -> K x 0.9,
up to 2 times, then the build FAILS; too many MeshParts or > 10k triangles in one part -> FAILS), check geometry
(no zero-area quads, every group closed), export blender/out/<key>.fbx (Roblox's Blender settings, deterministic
bytes) and verify it (3 re-imports), then write
    blender/out/<key>.manifest.json, blender/out/<key>.tris.json.gz        (not committed: rebuilt from here)
    src/shared/MeshManifests/<key>.lua                                       (committed, generated)
    blender/meshes.json                                                      (committed: the uploader's index)
--preview renders the catalog's preview sets (Cycles) to blender/out/previews/<name>.png.
Same input -> same contentHash / bytes.  Needs lupa (+ bpy for export): see blender/README.md.
"""
import argparse
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
KIT = os.path.join(HERE, "kit")
sys.path.insert(0, KIT)
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.dont_write_bytecode = True

import numpy as np  # noqa: E402

CATALOG_DIR = os.path.join(HERE, "catalog")
OUT = os.path.join(HERE, "out")
LUA_DIR = os.path.join(REPO, "src", "shared", "MeshManifests")
INDEX = os.path.join(HERE, "meshes.json")
PART_TRIS_SOFT = 10000  # recipe 4.2: per MeshPart (the hard Roblox limit is 20k)
K_STEP, K_STEPS = 0.9, 2


class BuildError(Exception):
    pass


def load_catalogs():
    cats = {}
    for path in sorted(glob.glob(os.path.join(CATALOG_DIR, "*.json"))):
        with open(path) as fh:
            c = json.load(fh)
        cls = c.get("class") or os.path.splitext(os.path.basename(path))[0]
        c["_path"] = path
        cats[cls] = c
    return cats


def display_name(key):
    return "NC " + " ".join(w.capitalize() for w in key.split("_"))


class Builder:
    def __init__(self, export=True, verbose=True):
        self.export = export
        self.verbose = verbose
        self._bridge = None
        self._fitter = None
        self._names = None
        self.B = None
        if export:
            from nvox import blend as B
            self.B = B

    @property
    def bridge(self):
        if self._bridge is None:
            from bridge import Bridge
            self._bridge = Bridge()
        return self._bridge

    @property
    def fitter(self):
        if self._fitter is None:
            from nvox.recipes import RecipeFitter
            self._fitter = RecipeFitter(self.bridge, REPO)
        return self._fitter

    def referenced(self):
        if self._names is None:
            import mesh_names
            self._names = mesh_names.referenced_names(REPO)[0]
        return self._names

    def fixed_keys(self, entry, bp_palette, fit):
        """constant-colour keys nothing looks up by name (tools/mesh_names.py) - only when the entry asks for it"""
        if not entry.get("fixed"):
            return ()
        names = self.referenced()
        out = set()
        for key, f in (fit or {}).items():
            rec = f.get("recipe") if isinstance(f, dict) else None
            if rec and rec[0] == "rgb" and key not in names:
                out.add(key)
        return tuple(sorted(out))

    # ------------------------------------------------------------------ one model at one K
    def make(self, entry, k):
        t = entry["type"]
        lod = entry.get("lod", "High")
        headroom = lod == "Low"
        if t in ("pet", "wing", "acc"):
            import petkit
            fit = self.fitter.fit(entry["pet"], int(entry.get("stage", 0)), entry.get("detail", "High"))
            if t == "pet":
                fixed = self.fixed_keys(entry, None, fit)
                m, bp = petkit.build_pet_body(self.bridge, fit, entry, k, fixed_keys=fixed, headroom=headroom)
            elif t == "wing":
                m, bp = petkit.build_pet_wing(self.bridge, fit, entry, k, headroom=headroom)
            else:
                fixed = self.fixed_keys(entry, None, fit)
                m, bp = petkit.build_pet_accessory(self.bridge, fit, entry, k, headroom=headroom, fixed_keys=fixed)
            bad = sorted(kk for kk, f in fit.items() if not f.get("ok") and any(getattr(o, "key", None) == kk for o in m.objects.values()))
            m.meta["colorFit"] = {"probes": self.fitter.n, "unfitted": bad}
            look = bp.raw.get("Look") or {}
            m.meta["previewLook"] = {a: [round(float(x) * 255) for x in v[:3]] for a, v in look.items()
                                     if isinstance(v, list)}
            return m
        if t == "boss":
            import bosskit
            return bosskit.build_boss_joint(self.bridge, entry, k)
        if t == "cal":
            import calib
            return calib.build_cal_axes(entry)
        if t == "prop":
            import props
            reg = props.load_all()
            fn = reg.get(entry["prop"])
            if fn is None:
                raise BuildError("%s: unknown prop builder %r (props/*.py registers: %s)" % (
                    entry["key"], entry["prop"], ", ".join(sorted(reg))))
            return fn(entry, props.PropKit())
        raise BuildError("%s: unknown type %r" % (entry["key"], t))

    # ------------------------------------------------------------------ budgets + K steps
    def build(self, entry, budget):
        k = float(entry.get("k", 1.0))
        tries = []
        for step in range(K_STEPS + 1):
            m = self.make(entry, k)
            tris = m.tris()
            worst = max([o.tris() for o in m.objects.values()] or [0])
            tries.append({"K": round(k, 4), "tris": tris, "parts": len(m.objects), "maxPartTris": worst})
            over_tris = budget.get("tris") is not None and tris > budget["tris"]
            over_part = worst > budget.get("maxPartTris", PART_TRIS_SOFT)
            if not (over_tris or over_part):
                break
            if step == K_STEPS or entry.get("type") in ("cal",):
                raise BuildError("%s over budget after %d K steps: %s (budget %s)" % (entry["key"], step, tries, budget))
            k *= K_STEP
        if budget.get("parts") is not None and len(m.objects) > budget["parts"]:
            raise BuildError("%s: %d MeshParts > budget %d (%s)" % (entry["key"], len(m.objects), budget["parts"],
                                                                    sorted(m.objects)))
        m.meta["kSteps"] = tries
        m.meta["budget"] = budget
        m.meta["class"] = entry.get("_class")
        m.meta["lod"] = entry.get("lod", "High")
        return m

    # ------------------------------------------------------------------ geometry checks
    @staticmethod
    def check_geometry(m):
        problems = []
        per_group = {}
        for o in m.objects.values():
            for corners, _ in o.quads:
                c = np.asarray(corners, float)
                n = np.cross(c[1] - c[0], c[3] - c[0])
                area = float(np.linalg.norm(n))
                if area < 1e-9:
                    problems.append("%s: zero-area quad" % o.name)
                    break
                per_group.setdefault(o.group, np.zeros(3))
                per_group[o.group] += n  # (corners are CCW from outside: n points out, |n| = area)
        for g, s in per_group.items():
            if np.abs(s).max() > 1e-6:
                problems.append("group %s not closed (net face area %s)" % (g, np.round(s, 6).tolist()))
        return problems

    # ------------------------------------------------------------------ one key end to end
    def run(self, entry, budget):
        from nvox.manifest import write_manifest, write_tris
        from manifest_to_lua import to_lua_source
        t0 = time.time()
        m = self.build(entry, budget)
        probs = self.check_geometry(m)
        if probs:
            raise BuildError("%s geometry: %s" % (entry["key"], "; ".join(probs[:6])))
        key = entry["key"]
        os.makedirs(OUT, exist_ok=True)
        fbx_name = key + ".fbx"
        verify = None
        if self.export:
            B = self.B
            B.reset_scene()
            objs = B.make_objects(m, None, export=True)
            size = B.export_fbx(objs, os.path.join(OUT, fbx_name))
            verify = B.verify_fbx(os.path.join(OUT, fbx_name), m)
            verify["bytes"] = size
            if not verify["ok"]:
                raise BuildError("%s FBX verify failed: %s" % (key, verify["problems"]))
        data = write_manifest(m, os.path.join(OUT, key + ".manifest.json"), fbx_name, verify)
        write_tris(m, os.path.join(OUT, key + ".tris.json.gz"))
        if entry.get("upload", True) is False:
            # kit test keys: blender/out only (no generated module, not in the uploader's index)
            if self.verbose:
                print("%-22s K %-6s tris %6d parts %3d  (test key: blender/out only)" % (
                    key, round(m.K, 3), data["tris"]["total"], data["tris"]["parts"]))
            return None, data
        os.makedirs(LUA_DIR, exist_ok=True)
        with open(os.path.join(LUA_DIR, key + ".lua"), "w") as fh:
            fh.write(to_lua_source(data))
        entry_out = {
            "class": entry.get("_class"), "fbx": "blender/out/" + fbx_name, "displayName": display_name(key),
            "description": entry.get("description") or ("Nimbus Climb mesh " + key + " (Blender kit, voxel style)"),
            "maxTrianglesPerMesh": data["tris"]["maxPerPart"], "tris": data["tris"]["total"],
            "parts": data["tris"]["parts"], "contentHash": data["contentHash"], "structureHash": data["structureHash"],
            "manifest": "src/shared/MeshManifests/" + key + ".lua",
        }
        if self.verbose:
            print("%-22s K %-6s tris %6d parts %3d maxPart %5d  %s  %.1fs" % (
                key, round(m.K, 3), data["tris"]["total"], data["tris"]["parts"], data["tris"]["maxPerPart"],
                "fbx ok" if verify else "no fbx", time.time() - t0))
        return entry_out, data


def resolve_budget(cat, entry):
    b = entry.get("budget")
    if isinstance(b, dict):
        return b
    return dict((cat.get("budgets") or {}).get(b or entry["type"], {}))


def write_index(updates):
    # several builds (one per catalog class) may run at once: read-merge-write under a lock
    import fcntl
    with open(INDEX + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        idx = {}
        if os.path.exists(INDEX):
            with open(INDEX) as fh:
                idx = json.load(fh)
        keys = idx.get("keys", {})
        keys.update(updates)
        out = {"comment": "Generated by blender/build_all.py: one entry per mesh key (uploader index, recipe 4.6). "
                          "FBX files live in blender/out/ (not committed; rebuild with build_all.py).",
               "keys": {k: keys[k] for k in sorted(keys)}}
        tmp = INDEX + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(out, fh, indent=1, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, INDEX)


def check_sets(cat, built):
    problems = []
    for s in cat.get("sets", []):
        b = resolve_budget(cat, {"budget": s.get("budget"), "type": "set"})
        tris = parts = 0
        missing = []
        for k in s["keys"]:
            d = built.get(k)
            if d is None:
                p = os.path.join(OUT, k + ".manifest.json")
                if os.path.exists(p):
                    with open(p) as fh:
                        d = json.load(fh)
            if d is None:
                missing.append(k)
                continue
            tris += d["tris"]["total"]
            parts += d["tris"]["parts"]
        if missing:
            continue
        line = "set %-24s tris %6d / %s  parts %3d / %s" % (s["name"], tris, b.get("tris"), parts, b.get("parts"))
        print(line)
        if (b.get("tris") and tris > b["tris"]) or (b.get("parts") and parts > b["parts"]):
            problems.append(line)
    return problems


def render_previews(cat, names=None):
    from nvox import blend as B
    from nvox import colors as C
    from nvox.build import ModelSpec
    os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)
    for pv in cat.get("previews", []):
        if names and pv["name"] not in names:
            continue
        mans = {}
        for k in [pv["body"]] + pv.get("attach", []):
            with open(os.path.join(OUT, k + ".tris.json.gz"), "rb") as fh:
                import gzip
                mans[k] = (json.loads(gzip.decompress(fh.read())), json.load(open(os.path.join(OUT, k + ".manifest.json"))))
        body_tris, body_man = mans[pv["body"]]
        look = {a: C.rgb(*v) for a, v in (body_man["meta"].get("previewLook") or {}).items()}
        if "WingColor" not in look and "Primary" in look:
            look["WingColor"] = C.lighten(look["Primary"], 0.4)
        B.reset_scene()
        B.setup_render(pv.get("res", 480))
        made = []

        def add(tris, man, matrix=None):
            m = ModelSpec(man["key"], man["kind"], 0.1, 1)
            for p in man["parts"]:
                if p["group"] == "EyeLid":
                    continue
                t = tris["parts"][p["name"]]
                o = m.obj(p["name"], group=p["group"], region=p["key"], shade=p["shade"],
                          recipe=None if p["color"] == "vertex" else p["color"], material=p["material"],
                          baked=p["color"] == "vertex")
                if p.get("transparency"):
                    o.transparency = p["transparency"]
                v = np.asarray(t["v"], float).reshape(-1, 3, 3) + np.asarray(t["center"], float)
                for tri, col in zip(v, t["c"]):
                    o.quads.append((tri, tuple(c / 255 for c in col)))
            return B.make_objects(m, look, matrix=matrix)

        made += add(body_tris, body_man)
        att = body_man.get("attachments", {})
        for k in pv.get("attach", []):
            tris, man = mans[k]
            where = pv.get("at", {}).get(k) or man["meta"].get("attach") or man["groups"].get(next(iter(man["groups"]), ""), {}).get("attach")
            a = att.get(where) if where else None
            mat = B.cf_to_bl(a["rot"], a["pos"]) if a else None
            made += add(tris, man, mat)
        pts = np.array([list(ob.matrix_world @ v.co) for ob in made for v in ob.data.vertices])
        lo_r, hi_r = B.PM @ pts.min(0), B.PM @ pts.max(0)
        png = os.path.join(OUT, "previews", pv["name"] + ".png")
        B.render_views((np.minimum(lo_r, hi_r), np.maximum(lo_r, hi_r)), png, res=pv.get("res", 480))
        print("preview", png)


def main():
    if os.environ.get("PYTHONHASHSEED") != "0":
        # Blender's FBX exporter derives object UIDs from Python string hashes: a fixed hash seed keeps the FBX bytes
        # identical from run to run (the manifests' contentHash never depends on it)
        env = dict(os.environ, PYTHONHASHSEED="0")
        os.execve(sys.executable, [sys.executable] + sys.argv, env)
    ap = argparse.ArgumentParser(description="Build Nimbus Climb mesh keys (blender/catalog/*.json)")
    ap.add_argument("--class", dest="classes", action="append", default=[])
    ap.add_argument("--key", dest="keys", action="append", default=[])
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--no-export", action="store_true", help="no bpy: manifests + numbers only (no FBX)")
    ap.add_argument("--preview", nargs="*", help="render the catalogs' preview sets (optionally by name)")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    cats = load_catalogs()
    todo = []
    for cls, cat in cats.items():
        for e in cat.get("keys", []):
            e = dict(e)
            e["_class"] = cls
            if a.all or cls in a.classes or e["key"] in a.keys:
                todo.append((cat, e))
    if a.list:
        for cls, cat in cats.items():
            print("%-14s %3d keys  %s" % (cls, len(cat.get("keys", [])), os.path.relpath(cat["_path"], REPO)))
            for e in cat.get("keys", []):
                print("   ", e["key"], e["type"])
        return 0
    missing = [k for k in a.keys if k not in {e["key"] for _, e in todo}]
    if missing:
        print("unknown keys:", missing)
        return 2
    export = not a.no_export
    if export:
        try:
            import bpy  # noqa: F401
        except ImportError:
            print("no bpy in this python: run with /tmp/claude-0/bpyenv/bin/python (or pass --no-export)")
            return 2
    b = Builder(export=export)
    updates, built, errors = {}, {}, []
    for cat, e in todo:
        try:
            out, data = b.run(e, resolve_budget(cat, e))
            if out is not None:
                updates[e["key"]] = out
            built[e["key"]] = data
        except BuildError as err:
            errors.append(str(err))
            print("FAIL", err)
    if updates:
        write_index(updates)
    for cls, cat in cats.items():
        errors += check_sets(cat, built)
    if a.preview is not None and export:
        for cls, cat in cats.items():
            if a.all or cls in a.classes or any(e["key"] in a.keys for e in cat.get("keys", [])):
                render_previews(cat, a.preview or None)
    if errors:
        print("%d key(s) failed" % len(errors))
        return 1
    print("built %d key(s)" % len(updates))
    return 0


if __name__ == "__main__":
    sys.exit(main())
