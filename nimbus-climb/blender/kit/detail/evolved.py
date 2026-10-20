"""Evolved-form detail passes (W2 art-evolved; ARCHITECTURE_V3.md 6.0.4 "evolved pets look the best: auras and
effects").  Catalog entries name them as passes: ["evolved:body", "evolved:aura"] (blender/catalog/evolved.json,
written by detail/evolved_catalog.py).  Each is fn(bp, cells, entry) and runs inside petkit.face_pass, before the
body is meshed and before the blueprint's other groups are read, so a pass may:
  * edit `cells` (the Body group's voxels at mesh K: (x, y, z) -> palette key with _Light / _Dark variants), and
  * add or extend groups in bp.groups (nvox GroupGrid) and add palette keys to bp.palette (constant colours: the
    kit's Styles fall back to an "rgb" recipe for keys the colour fit does not know).

body  gem inlays (a white Neon glint and a deep gold bezel on every gem), armour trims (a bright gold edge on the
      top rims of gold plates, a deep line where the gold meets fur), all sized in design units so High and Low match.
aura  the evolved aura meshes (6.0.4): a dashed ring of light that orbits the pet (group `Aura`, kind orbit: the
      existing Animate orbit + PetFx's Neon pulse find it by name), stage 1 = gold ring with gem-coloured diamonds
      and white twinkles, stage 2 = a double ring in the pet's Glow / GlowB colours around its element bits (the
      second evolution's own Aura group is extended, so there is still exactly one Aura group); plus a crown of light
      (group `Halo`, kind bob) above the head of second evolutions that have no Halo of their own.
Names stay inside the 4.3 contract: aura parts are `Aura`, `Aura2`... (MK_Key AuraA / AuraB / AuraC), the crown parts
`Halo`... (MK_Key HaloGlow / Glow / GlowB); the new body keys are `GemGlint` (Neon) and the existing gold keys.
Deterministic: no random numbers, set iteration is always sorted.
"""
import math

import numpy as np

from bridge import GroupGrid
from detail import faces

GEM_KEYS = ("Gem", "GemB", "HydraEye")
GOLD_KEYS = ("Gold", "Armor", "GoldLight")
GOLD_EDGE = "GoldLight"
GOLD_DEEP = "GoldDeep"
STAGE1_GOLD = (255 / 255, 214 / 255, 90 / 255)
AURA_STUDS_LOW = 0.2
AURA_STUDS = 0.15  # voxel size of a new (first evolution) aura group: chunky light pixels that read from afar
WHITE = (1.0, 1.0, 1.0)
N6 = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))


def _base(k):
    if k.endswith("_Light"):
        return k[:-6], "_Light"
    if k.endswith("_Dark"):
        return k[:-5], "_Dark"
    return k, ""


def _stage(entry):
    return int(entry.get("stage", 0) or 0)


def _low(entry):
    return entry.get("lod") == "Low"


def _mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _neon(rgb):
    return [float(rgb[0]), float(rgb[1]), float(rgb[2]), "Neon", 0.0]


def _pal_rgb(bp, key, default=None):
    e = bp.palette.get(key)
    if e is None:
        return default
    return (float(e[0]), float(e[1]), float(e[2]))


def _components(cells, keys):
    """connected (6-neighbour) clusters of the cells whose base key is in keys; sorted, deterministic"""
    todo = sorted(p for p, k in cells.items() if _base(k)[0] in keys)
    left = set(todo)
    out = []
    for p in todo:
        if p not in left:
            continue
        left.discard(p)
        comp, stack = [], [p]
        while stack:
            q = stack.pop()
            comp.append(q)
            for d in N6:
                r = (q[0] + d[0], q[1] + d[1], q[2] + d[2])
                if r in left:
                    left.discard(r)
                    stack.append(r)
        out.append(sorted(comp))
    return out


def _exposed(cells, p):
    return any((p[0] + d[0], p[1] + d[1], p[2] + d[2]) not in cells for d in N6)


# ---------------------------------------------------------------------------------------------------- Lua eyes
_LUA_LIDS = {}
_MARK = "__evolved_lua_lids__"


def _install_eye_hooks():
    """petkit.face_pass runs the catalog passes only on its procedural-eye path, and then always carves procedural
    eyes.  These wrappers hand back the game's own Lua lids instead, but ONLY for a cells dict that lua_eyes()
    registered in the same face_pass call; every other caller gets the original functions."""
    if getattr(faces.carve_eyes, "_evolved", False):
        return
    orig_carve, orig_groups = faces.carve_eyes, faces.lid_groups

    def carve_eyes(cells, specs, K, *a, **kw):
        lids = _LUA_LIDS.pop(id(cells), None)
        if lids is not None:
            return (_MARK, lids)
        return orig_carve(cells, specs, K, *a, **kw)

    def lid_groups(lids, *a, **kw):
        if isinstance(lids, tuple) and len(lids) == 2 and lids[0] == _MARK:
            return lids[1]
        return orig_groups(lids, *a, **kw)

    carve_eyes._evolved = True
    faces.carve_eyes, faces.lid_groups = carve_eyes, lid_groups


def lua_eyes(bp, cells, entry):
    """undo faces.restore_carved_eyes (the evolved heads keep PetBuilder's carved eyes, sized for them) and make
    face_pass return PetBuilder's own lid cells, exactly like the kit's "eyes": "lua" option (which skips passes)"""
    body0 = bp.group("Body")
    orig = {(int(x), int(y), int(z)): k for (x, y, z), k in zip(body0.xyz.tolist(), body0.keys)}
    for eye in bp.lid_cells:
        for (x, y, z, k) in eye:
            for p in ((int(x), int(y), int(z)), (int(x), int(y), int(z) + 1)):
                if p in orig:
                    cells[p] = orig[p]
                else:
                    cells.pop(p, None)
    _install_eye_hooks()
    _LUA_LIDS[id(cells)] = [dict(((int(x), int(y), int(z)), k) for (x, y, z, k) in lid) for lid in bp.lid_cells]
    return None


# ---------------------------------------------------------------------------------------------------- body pass
def body(bp, cells, entry):
    """gem inlays + armour trims on the Body voxels"""
    K = bp.K
    low = _low(entry)
    bp.palette.setdefault("GemGlint", _neon(WHITE))
    # gem inlays: a deep gold bezel ring around each gem, a white glint at its upper-front-left (viewer's left = +x,
    # the pet faces -Z), two voxels on big gems
    for comp in _components(cells, GEM_KEYS):
        if len(comp) < (3 if low else 6):
            continue
        cs = set(comp)
        front = [p for p in comp if (p[0], p[1], p[2] - 1) not in cells]
        if not front:
            front = [p for p in comp if _exposed(cells, p)]
        if not front:
            continue
        xs = [p[0] for p in front]
        ys = [p[1] for p in front]
        cx, cy = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
        span = max(max(xs) - min(xs), max(ys) - min(ys)) + 1
        # the glint: the front voxel nearest the upper-left point of the gem face
        tx, ty = cx + span * 0.22, cy + span * 0.22
        best = min(front, key=lambda p: ((p[0] - tx) ** 2 + (p[1] - ty) ** 2, p))
        cells[best] = "GemGlint"
        if span >= (4 if low else 7):
            second = (best[0] - 1, best[1] + 1, best[2])
            if second in cs:
                cells[second] = "GemGlint"
        # the bezel: body voxels touching the gem on its face plane become deep gold (only around the front rim)
        if span >= 3:
            for p in front:
                for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0)):
                    r = (p[0] + d[0], p[1] + d[1], p[2] + d[2])
                    k = cells.get(r)
                    if k is None or r in cs:
                        continue
                    b, v = _base(k)
                    if b in GOLD_KEYS or b == GOLD_DEEP:
                        cells[r] = GOLD_DEEP + ("_Dark" if v == "_Dark" else "")
    # armour trims: gold voxels on a plate's upper rim (open above, fur next to them) get the bright gold edge; gold
    # voxels whose lower neighbour is fur get the deep line (the plate reads as a separate, thick piece of armour)
    trims = []
    for p in sorted(cells):
        b, v = _base(cells[p])
        if b not in ("Gold", "Armor"):
            continue
        up = (p[0], p[1] + 1, p[2])
        dn = (p[0], p[1] - 1, p[2])
        side_fur = False
        for d in ((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, 1, 0), (0, -1, 0)):
            k2 = cells.get((p[0] + d[0], p[1] + d[1], p[2] + d[2]))
            if k2 is not None and _base(k2)[0] not in GOLD_KEYS + (GOLD_DEEP,) + GEM_KEYS + ("GemGlint",):
                side_fur = True
                break
        if not side_fur:
            continue
        if up not in cells:
            trims.append((p, GOLD_EDGE))
        elif not low and dn in cells and _base(cells[dn])[0] not in GOLD_KEYS + (GOLD_DEEP,) + GEM_KEYS:
            trims.append((p, GOLD_DEEP))
    for p, k in trims:
        cells[p] = k
    return None


# ---------------------------------------------------------------------------------------------------- aura pass
def _ring(out, key, R, y, width, height, K, dash=0, gap=0.0, phase=0.0, tilt=0.0):
    """a flat ring (design units: radius R at height y, radial width, height) as voxels at K; dash > 0 cuts it
    into `dash` arcs with `gap` (0..1) of each period left open; tilt (radians) tips it about the x axis"""
    Rv, wv, hv = R * K, max(1.0, width * K), max(1.0, height * K)
    lim = int(math.ceil(Rv + wv + 2))
    ct, st = math.cos(tilt), math.sin(tilt)
    yv = y * K
    for x in range(-lim, lim + 1):
        for z in range(-lim, lim + 1):
            r = math.hypot(x, z)
            if abs(r - Rv) > wv / 2.0:
                continue
            if dash:
                a = (math.atan2(z, x) / (2 * math.pi) + 1.0 + phase) % 1.0
                if (a * dash) % 1.0 < gap:
                    continue
            for j in range(int(math.ceil(hv))):
                yy = j - (hv - 1) / 2.0
                # tip about x: (y, z) -> rotated
                py = yy * ct - z * st
                pz = yy * st + z * ct
                out[(x, int(round(py + yv)), int(round(pz)))] = key


def _diamond(out, key, c, r, K, tall=1.4):
    """an octahedron gem (|x| + |y| / tall + |z| <= r) at design point c"""
    rv = r * K
    lim = int(math.ceil(rv * tall)) + 1
    cx, cy, cz = (int(round(c[0] * K)), int(round(c[1] * K)), int(round(c[2] * K)))
    for x in range(-lim, lim + 1):
        for y in range(-lim, lim + 1):
            for z in range(-lim, lim + 1):
                if abs(x) + abs(y) / tall + abs(z) <= rv + 0.25:
                    out[(cx + x, cy + y, cz + z)] = key


def _star(out, key, c, r, K):
    """a small 4-point twinkle (a plus with a 1-voxel core), facing every way"""
    rv = max(1, int(round(r * K)))
    cx, cy, cz = (int(round(c[0] * K)), int(round(c[1] * K)), int(round(c[2] * K)))
    for i in range(-rv, rv + 1):
        out[(cx + i, cy, cz)] = key
        out[(cx, cy + i, cz)] = key
        out[(cx, cy, cz + i)] = key
    if rv >= 2:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    if abs(dx) + abs(dy) + abs(dz) <= 1:
                        out[(cx + dx, cy + dy, cz + dz)] = key


def _body_bounds(cells, K):
    a = np.array(sorted(cells), float) / K
    return a.min(0), a.max(0), a


def _reach(arr, y0, y1, centre):
    """largest horizontal distance from centre (x, z) of body voxels with y0 <= y <= y1 (design units)"""
    m = (arr[:, 1] >= y0) & (arr[:, 1] <= y1)
    if not m.any():
        return 0.0
    d = np.hypot(arr[m, 0] - centre[0], arr[m, 2] - centre[1])
    return float(d.max())


def _group_cells(g):
    return {(int(x), int(y), int(z)): k for (x, y, z), k in zip(g.xyz.tolist(), g.keys)}


def _set_group_cells(g, cells):
    pts = sorted(cells)
    g.xyz = np.array(pts, np.int32).reshape(-1, 3)
    g.keys = [cells[p] for p in pts]


def aura(bp, cells, entry):
    """orbiting ring(s) of light + element bits (group Aura) and, on second evolutions, a crown of light (Halo)"""
    stage = _stage(entry)
    if stage < 1:
        return None
    low = _low(entry)
    K = bp.K
    lo, hi, arr = _body_bounds(cells, K)
    height = hi[1] - lo[1]
    if stage == 1:
        gold = STAGE1_GOLD
        gem = _pal_rgb(bp, "Gem", (232 / 255, 60 / 255, 100 / 255))
        # (a Secret pet's own first-stage aura bits take the evolution's gold and gem colours too)
        bp.palette["AuraA"] = _neon(gold)
        bp.palette["AuraB"] = _neon(gem)
        bp.palette["AuraC"] = _neon(_mix(gold, WHITE, 0.6))
    else:
        glow = _pal_rgb(bp, "Glow", (1.0, 0.85, 0.4))
        bp.palette.setdefault("AuraA", _neon(glow))
        bp.palette.setdefault("AuraB", _neon(_pal_rgb(bp, "GlowB", glow)))
        bp.palette.setdefault("AuraC", _neon(_mix(glow, WHITE, 0.55)))
    g = bp.group("Aura")
    if g is not None:
        hinge = np.asarray(g.hinge[0], float)
        acells = _group_cells(g)
        gK = g.K
    else:
        # a new orbit group centred under the body (the hinge is where Animate spins and bobs it); its voxels are
        # AURA_STUDS big so the ring still reads from the follow camera
        cz = float((lo[2] + hi[2]) / 2.0)
        hinge = np.array([0.0, float(lo[1] + height * 0.3), cz])
        acells = {}
        gK = 0.1 / (AURA_STUDS_LOW if low else AURA_STUDS)
    centre = (0.0, float(hinge[2]))
    # ring height: low around the legs (it never cuts the face), clear of every body voxel near that height
    ry = float(lo[1] + height * (0.16 if stage == 1 else 0.2)) - hinge[1]
    reach = _reach(arr, hinge[1] + ry - 3, hinge[1] + ry + 3, centre)
    R = reach + (3.4 if stage == 1 else 4.0)
    if g is not None:
        # outside the element bits too
        bits = np.array(sorted(acells), float) / gK
        if len(bits):
            R = max(R, float(np.hypot(bits[:, 0], bits[:, 2]).max()) + 2.5)
    vox = 1.0 / gK  # design units per aura voxel
    if stage == 1:
        dash = 8
        _ring(acells, "AuraA", R, ry, vox, vox, gK, dash=dash, gap=0.2, phase=0.0)
        # a white twinkle in the middle of every gap, a slim gem floating over every second dash
        for i in range(dash):
            a = (i + 0.1) / dash * 2 * math.pi
            p = (math.cos(a) * R * gK, ry * gK, math.sin(a) * R * gK)
            acells[(int(round(p[0])), int(round(p[1])), int(round(p[2])))] = "AuraC"
            if not low:
                acells[(int(round(p[0])), int(round(p[1])) + 1, int(round(p[2])))] = "AuraC"
        n = 4
        for i in range(n):
            a = (i + 0.6) / n * 2 * math.pi
            _diamond(acells, "AuraB", (math.cos(a) * R, ry + 2.4 * vox, math.sin(a) * R), 1.0 * vox, gK, tall=2.2)
    else:
        th = max(vox, 0.18) if low else max(2 * vox, 1.6)
        _ring(acells, "AuraA", R, ry, th, th, gK, dash=12, gap=0.18, phase=0.02)
        if not low:
            _ring(acells, "AuraB", R + 2.6, ry - 0.2, vox, vox, gK, dash=6, gap=0.5, phase=0.3)
            n = 6
            for i in range(n):
                a = (i + 0.25) / n * 2 * math.pi
                _star(acells, "AuraC", (math.cos(a) * (R + 1.3), ry + 3.6 + (i % 2) * 1.8, math.sin(a) * (R + 1.3)),
                      1.4, gK)
    if g is not None:
        _set_group_cells(g, acells)
    else:
        pts = sorted(acells)
        ng = GroupGrid("Aura", np.array(pts, np.int32).reshape(-1, 3), [acells[p] for p in pts], gK, "orbit", 1, 0.8,
                       0, (hinge, np.eye(3)))
        _insert_group(bp, ng)
    if stage == 2 and bp.group("Halo") is None:
        _crown(bp, cells, entry, lo, hi)
    return None


def _insert_group(bp, g):
    """keep PetBuilder's instantiate order: ... Tail, Halo, Aura, EyeLid"""
    order = {"Body": 0, "WingL": 1, "WingR": 2, "Wing2L": 3, "Wing2R": 4, "Tail": 5, "Halo": 6, "Aura": 7, "EyeLid": 8}
    want = order.get(g.name, 7)
    for i, other in enumerate(bp.groups):
        if order.get(other.name, 9) > want:
            bp.groups.insert(i, g)
            return
    bp.groups.append(g)


def _crown(bp, cells, entry, lo, hi):
    """a floating crown of light above the head: a tilted ring of Glow with GlowB points (group Halo, kind bob)"""
    low = _low(entry)
    K = bp.K
    head_top = float(bp.anchors.get("HeadTop") or hi[1])
    hc = bp.anchors.get("HeadC") or [0, head_top - 6, -8]
    # above the highest body voxel over the head (crests and horns reach up there)
    arr = np.array(sorted(cells), float) / K
    near = arr[np.hypot(arr[:, 0], arr[:, 2] - float(hc[2])) < 11]
    top = float(near[:, 1].max()) if len(near) else head_top
    at = np.array([0.0, max(top, head_top) + 3.5, float(hc[2])])
    bp.palette.setdefault("HaloGlow", _neon(_pal_rgb(bp, "Glow", STAGE1_GOLD)))
    hcells = {}
    R = 4.2
    _ring(hcells, "HaloGlow", R, 0.0, 1.0 if low else 0.8, 1.0 if low else 0.8, K, tilt=-0.35)
    if not low:
        n = 5
        for i in range(n):
            a = (i + 0.5) / n * 2 * math.pi
            x, z = math.cos(a) * R, math.sin(a) * R
            y = -z * math.sin(-0.35)
            zz = z * math.cos(-0.35)
            _diamond(hcells, "AuraB" if i % 2 else "AuraC", (x, y + 1.3, zz), 0.8, K, tall=1.8)
    pts = sorted(hcells)
    g = GroupGrid("Halo", np.array(pts, np.int32).reshape(-1, 3), [hcells[p] for p in pts], K, "bob", 1, 0.6, 0,
                  (at, np.eye(3)))
    _insert_group(bp, g)
