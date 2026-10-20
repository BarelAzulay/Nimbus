"""Pet keys through the bridge: pet_<species>[_low], wing_<style>_<L|R>[_low], acc_<name>[_low] (and the evolved
keys of wave 2 through the same calls).  Shapes, shading, hinges and palette come from the game's PetBuilder
(bridge.Bridge.pet); the kit adds the procedural face (detail/faces.py), the name contract (nvox/parts.py) and the
colour recipes (nvox/recipes.py).

Every model is a nvox.build.ModelSpec in ROBLOX space (studs, +Y up, -Z forward) relative to its pivot:
  pet_*  pivot = PetBuilder's invisible root `Body` (design origin); groups Body, Tail, EyeLid (+ Halo / Aura)
  wing_* pivot = the wing hinge (the species' WingL / WingR attachment); one key per side
  acc_*  pivot = the species' `Hat` anchor (top of the head); accessory voxels = (pet with it) - (pet without it)
"""
import numpy as np

from bridge import PET_VOXEL, base_key
from detail import faces
from nvox.build import ModelSpec
from nvox.manifest import cf_json
from nvox.parts import Styles, add_cells

ATTACH_GROUPS = ("WingL", "WingR", "Wing2L", "Wing2R")


def lua_num(v):
    """Lua 5.1 tostring() of a number (for PB_G specs that must equal PetBuilder's)"""
    v = float(v)
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    s = "%.14g" % v
    return s


def group_spec(name, kind, side, amp, index):
    return ":".join([name, kind or "static", lua_num(side or 1), lua_num(amp or 0), lua_num(index or 0)])


def cf_string(pos, R):
    """PetBuilder cfToString (%.6g of the 12 components)"""
    c = list(pos) + list(np.asarray(R, float).ravel())
    return ",".join(("%.6g" % float(x)) for x in c)


def mirror_R(R):
    M = np.diag([-1.0, 1.0, 1.0])
    return M @ np.asarray(R, float) @ M


def _strip(look_over, entry):
    lk = dict(look_over or {})
    for f in entry.get("strip", []):
        lk[f] = False
    return lk


def pet_blueprint(br, entry, k, with_accessory=None):
    look = _strip(entry.get("look"), entry)
    if with_accessory is not None:
        look["Accessory"] = with_accessory
    return br.pet(entry["pet"], k=k, stage=int(entry.get("stage", 0)), detail=entry.get("detail", "High"),
                  look=look, want_pre=True)


def _styles(bp, fit):
    return Styles(bp.palette, fit)


def _cells_of(g):
    return {(int(x), int(y), int(z)): k for (x, y, z), k in zip(g.xyz.tolist(), g.keys)}


def run_passes(bp, body_cells, entry):
    """the entry's detail passes: "module:function" under kit/detail/, each called as fn(bp, body_cells, entry)"""
    import importlib
    for name in entry.get("passes", []):
        mod, fn = name.split(":")
        getattr(importlib.import_module("detail." + mod), fn)(bp, body_cells, entry)


def face_pass(bp, body_cells, entry):
    """procedural eyes + lids; returns lid groups (list of cell dicts).  The entry's passes run on every path: with
    face.eyes 'lua' (or a pet without Lua eye anchors) they run on the Lua-carved body and PetBuilder's own lids are
    returned; on the procedural path they run after the carved eyes are restored, before the kit carves its eyes."""
    opts = entry.get("face", {})
    if opts.get("eyes", "procedural") != "procedural" or not bp.eyes:
        run_passes(bp, body_cells, entry)
        return [dict(((x, y, z), k) for (x, y, z, k) in cells) for cells in bp.lid_cells]
    faces.restore_carved_eyes(body_cells, bp.lid_cells)
    if opts.get("features", True):
        faces.rescale_face_features(body_cells, bp.K, tuple(opts.get("featureKeys", faces.FACE_KEYS)))
    run_passes(bp, body_cells, entry)
    specs = faces.eye_specs(bp)
    lids = faces.carve_eyes(body_cells, specs, bp.K, scale=float(opts.get("eyeScale", 1.1)),
                            inflate=float(opts.get("eyeInflate", 0.0)))
    return faces.lid_groups(lids, single=bool(opts.get("singleLid", False)))


def build_pet_body(br, fit, entry, k, fixed_keys=(), headroom=False):
    """pet_<species>: Body (+ Tail, EyeLid, Halo, Aura) at the root pivot"""
    bp = pet_blueprint(br, entry, k)
    m = ModelSpec(entry["key"], "pet", PET_VOXEL / bp.K * bp.grow, bp.K)
    st = _styles(bp, fit)
    used = {"Body": 1}  # the invisible root part is "Body"
    design = PET_VOXEL * bp.grow  # studs per design unit (hinges)
    body = bp.group("Body")
    body_cells = _cells_of(body)
    lid_cells = face_pass(bp, body_cells, entry)
    add_cells(m, body_cells, st, group="Body", naming="key", vs=PET_VOXEL / body.K * bp.grow, headroom=headroom,
              fixed_keys=fixed_keys, used=used)
    groups = {}
    rig = []
    for g in bp.groups:
        if g.name in ("Body", "EyeLid") or g.name in ATTACH_GROUPS:
            continue
        pos, R = g.hinge if g.hinge is not None else (np.zeros(3), np.eye(3))
        hinge_pos = np.asarray(pos, float) * design
        made = add_cells(m, _cells_of(g), st, group=g.name, naming="group", vs=PET_VOXEL / g.K * bp.grow, rot=R,
                         offset=hinge_pos, headroom=headroom, fixed_keys=(), used=used)
        spec = group_spec(g.name, g.kind, g.side, g.amp, g.index)
        groups[g.name] = {"kind": g.kind or "static", "side": g.side, "amp": g.amp, "index": g.index, "spec": spec,
                          "hinge": cf_json(R, hinge_pos), "parts": [o.name for o in made]}
        if g.hinge is not None:
            rig.append(spec + "=" + cf_string(hinge_pos, R))
    for i, cells in enumerate(lid_cells, start=1):
        made = add_cells(m, cells, st, group="EyeLid", naming="group", vs=PET_VOXEL / body.K * bp.grow,
                         headroom=headroom, deep=False, used=used)
        spec = group_spec("EyeLid", "lid", 1, 0, i)
        groups["EyeLid" + ("" if i == 1 else str(i))] = {"kind": "lid", "side": 1, "amp": 0, "index": i, "spec": spec,
                                                         "hinge": None, "parts": [o.name for o in made],
                                                         "hiddenByDefault": True}
    m.groups = groups
    a = bp.anchors
    wh = np.asarray(a.get("Wing") or [3.8, -1.5, 4.2], float)
    tilt, sweep = float(a.get("WingTilt") or 0.38), float(a.get("WingSweep") or 0.5)
    from nvox.grid import angles
    R_R = angles(0, -sweep, 0) @ angles(0, 0, tilt)
    att = {
        "WingR": cf_json(R_R, wh * design),
        "WingL": cf_json(mirror_R(R_R), np.array([-wh[0], wh[1], wh[2]]) * design),
    }
    for g in bp.groups:  # the real hinges (second-evolution Wing2 pairs too)
        if g.name in ATTACH_GROUPS and g.hinge is not None:
            att[g.name] = cf_json(g.hinge[1], np.asarray(g.hinge[0], float) * design)
    for nm, src in (("Hat", "Hat"), ("Neck", "Neck"), ("Flower", "Flower"), ("HeadCenter", "HeadC"),
                    ("HornBase", "HornBase"), ("Tail", "Tail"), ("Halo", "Halo"), ("Aura", "Aura")):
        v = a.get(src)
        if v is not None:
            att[nm] = cf_json(np.eye(3), np.asarray(v, float) * design)
    for i, (cx, cy, rx, ry, kind, mask) in enumerate(faces.eye_specs(bp)):
        att["EyeR" if cx > 0 else "EyeL"] = cf_json(np.eye(3), np.array([cx, cy, 0.0]) * design)
    m.attachments = att
    m.rig = ";".join(rig)
    m.meta = {"pet": entry["pet"], "species": bp.species, "stage": int(entry.get("stage", 0)), "grow": bp.grow,
              "detail": entry.get("detail", "High"), "K": bp.K, "headroom": bool(headroom),
              "pulseKeys": sorted(bp.pulse), "rootSize": [0.9, 1.1, 0.9], "anchorsDesign": {
                  kk: vv for kk, vv in a.items() if isinstance(vv, (list, int, float))}}
    return m, bp


def build_pet_wing(br, fit, entry, k, headroom=False):
    """wing_<style>_<L|R>: the wing group in hinge-local space (pivot = the hinge)"""
    bp = pet_blueprint(br, entry, k)
    side = entry.get("side", "L")
    gname = entry.get("group", "Wing") + side
    g = bp.group(gname)
    if g is None:
        raise KeyError("%s: no %s group" % (entry["key"], gname))
    m = ModelSpec(entry["key"], "wing", PET_VOXEL / g.K * bp.grow, g.K)
    st = _styles(bp, fit)
    used = {}
    left = bp.group(entry.get("group", "Wing") + "L")
    # the right wing is the exact mirror image of the left one (PetBuilder MirrorBoxes): mesh the left wing and
    # mirror its quads (x -> -x, winding reversed), so both sides have identical triangles
    made = add_cells(m, _cells_of(left), st, group=gname, naming="group", vs=PET_VOXEL / g.K * bp.grow,
                     headroom=headroom, used=used)
    if side == "R":
        for o in made:
            o.quads = [((np.asarray(c, float) * np.array([-1.0, 1.0, 1.0]))[::-1], col) for c, col in o.quads]
    pos, R = g.hinge
    spec = group_spec(g.name, g.kind, g.side, g.amp, g.index)
    m.groups = {gname: {"kind": g.kind, "side": g.side, "amp": g.amp, "index": g.index, "spec": spec,
                        "hinge": cf_json(np.eye(3), np.zeros(3)), "attach": gname, "parts": [o.name for o in made]}}
    m.attachments = {}
    m.meta = {"pet": entry["pet"], "style": bp.raw.get("WingStyle"), "side": side, "K": g.K, "headroom": headroom,
              "pivot": "the wing hinge: place at the body's %s attachment" % gname,
              "restHinge": cf_json(R, np.asarray(pos, float) * PET_VOXEL * bp.grow)}
    return m, bp


def build_pet_accessory(br, fit, entry, k, headroom=False, fixed_keys=()):
    """acc_<name>: voxels the accessory adds to the body (pet with it minus pet without it), pivot = Hat"""
    acc = entry["accessory"]
    plain = pet_blueprint(br, entry, k, with_accessory=False)
    bp = pet_blueprint(br, entry, k, with_accessory=acc)
    m = ModelSpec(entry["key"], "accessory", PET_VOXEL / bp.K * bp.grow, bp.K)
    st = _styles(bp, fit)
    attach = entry.get("attach", "Hat")
    anchor = np.asarray(bp.anchors.get(attach) or bp.anchors.get("Hat"), float) * PET_VOXEL * bp.grow
    b0 = plain.group("Body")
    b1 = bp.group("Body")
    pre0 = {tuple(p): base_key(kk)[0] for p, kk in zip(b0.pre[0].tolist(), b0.pre[1])} if b0.pre else {}
    pre1 = {tuple(p): base_key(kk)[0] for p, kk in zip(b1.pre[0].tolist(), b1.pre[1])} if b1.pre else {}
    post1 = _cells_of(b1)
    cells = {p: post1.get(p, kk) for p, kk in pre1.items() if pre0.get(p) != kk}
    used = {}
    made = add_cells(m, cells, st, group="Accessory", naming="key", vs=PET_VOXEL / b1.K * bp.grow,
                     offset=-anchor, headroom=headroom, fixed_keys=fixed_keys, used=used, deep=False)
    groups = {}
    for g in bp.groups:  # groups only the accessory brings (the Halo accessory's bobbing ring)
        if plain.group(g.name) is not None or g.name in ATTACH_GROUPS:
            continue
        pos, R = g.hinge if g.hinge is not None else (np.zeros(3), np.eye(3))
        hp = np.asarray(pos, float) * PET_VOXEL * bp.grow - anchor
        mg = add_cells(m, _cells_of(g), st, group=g.name, naming="group", vs=PET_VOXEL / g.K * bp.grow, rot=R,
                       offset=hp, headroom=headroom, used=used)
        groups[g.name] = {"kind": g.kind, "side": g.side, "amp": g.amp, "index": g.index,
                          "spec": group_spec(g.name, g.kind, g.side, g.amp, g.index), "hinge": cf_json(R, hp),
                          "parts": [o.name for o in mg]}
    m.groups = groups
    m.attachments = {}
    m.meta = {"pet": entry["pet"], "accessory": acc, "attach": attach, "K": bp.K, "headroom": headroom,
              "pivot": "the body's %s attachment" % attach, "bodyParts": [o.name for o in made]}
    return m, bp
