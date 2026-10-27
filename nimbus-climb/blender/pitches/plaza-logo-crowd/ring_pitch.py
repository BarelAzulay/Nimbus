"""Champion Ring floor emblem + crowd pitch (bug #11): today's ring + three directions, rendered in Blender.

    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe -I ring_pitch.py <out_dir> [--res 100] [--samples 32]
        [--only today,a,b,c,lineup,motion,bake] [--kit <nimbus-climb/blender/kit>]

today_render.png  the kit's REAL arena_pocket bake (props/arena.py runs ArenaBuilder in the mock world, then
                  arena_style.bake at 0.5-stud voxels, exactly what ships) + its Keep parts (the Neon gems / glows),
                  plus a close-up of the baked emblem (the "E").
option_a/b/c.png  the same ring baked WITHOUT the emblem and the crowd (Emblem* / Puff* boxes left out of the bake),
                  with each direction's emblem (a 0.25-stud voxel inlay key) and crowd on the existing stone bleacher.
                  Main 3/4 view + a crowd close-up + an emblem top view, composited into one sheet.
motion_a/b/c.png  4 frames of the crowd: idle, big hit, round won, boss round (the tween poses), with the sound cue.
lineup.png        today + A + B + C, same camera, labelled.
bake_check.png    (--only bake) the emblem directions baked at 0.5 studs, to check they survive the game's bake.
1 Blender unit = 1 stud, Z up; Roblox -> Blender is the kit's PM (x -> -x, z -> y, y -> z): the champion's side
(Roblox +Z) is Blender +Y, the crowd faces -Y. The player is R15-proportioned and 5.3 studs tall. Read-only for game
code: the kit is imported to bake in memory; nothing is exported or written into the repo.
"""
import math
import os
import random
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector as V

ARGS = sys.argv[1:]
OUT = os.path.abspath(ARGS[0] if ARGS and not ARGS[0].startswith("--") else ".")


def arg(name, default):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default


RES = int(arg("--res", 100))
SAMPLES = int(arg("--samples", 32))
ONLY = set(arg("--only", "today,a,b,c,lineup,motion").split(","))
KIT = os.path.abspath(arg("--kit", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "kit")))
TAU = math.tau
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # the project path has Hebrew letters
except Exception:
    pass
os.makedirs(OUT, exist_ok=True)
sys.path.insert(0, KIT)
sys.dont_write_bytecode = True


def lin(c):
    return (c / 255.0) ** 2.2


def rgb(r, g, b, a=1.0):
    return (lin(r), lin(g), lin(b), a)


def hsh(*a):
    x = 0
    for i, v in enumerate(a):
        x ^= (int(v) * (73856093, 19349663, 83492791, 2654435761, 97)[i % 5]) & 0xFFFFFFFF
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    return (x % 10007) / 10007.0


# the baked ring floor's surface: arena_style.align_y puts the 0.5-stud grid at y offset 0.3125 for this pocket,
# so the mesh top sits 0.31 above the Part floor (0..0.028); inlays and the player stand on the mesh surface here
FLOOR_Z = 0.3125
GOLD = (250, 190, 56)
GOLD_D = (214, 150, 40)
GOLD_L = (255, 222, 120)
VIOLET = (156, 96, 238)
VIOLET_D = (112, 66, 186)
INK = (40, 36, 56)

# ================================================================================ materials
_mats = {}


def kind_mat(kind):
    if kind in _mats:
        return _mats[kind]
    m = bpy.data.materials.new("K_" + kind)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.62
    if kind == "metal":
        b.inputs["Metallic"].default_value = 0.45
        b.inputs["Roughness"].default_value = 0.4
    elif kind == "glow":
        nt.links.new(vc.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 1.6
    _mats[kind] = m
    return m


def flat_mat(name, col, rough=0.6, metal=0.0, alpha=1.0, emit=0.0):
    key = (name, tuple(col), rough, metal, alpha, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = rgb(*col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Alpha"].default_value = alpha
    if emit:
        b.inputs["Emission Color"].default_value = rgb(*col)
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = rgb(*col)
    _mats[key] = m
    return m


def M(col, **kw):
    return flat_mat("F%d_%d_%d" % tuple(col), col, **kw)


# ================================================================================ voxels
class Vox:
    """a voxel sculpt: cells (i, j, k) -> palette key; one mesh per surface kind with per-face colours"""

    def __init__(self, pal, c=0.5, seed=0):
        self.pal, self.c, self.v, self.seed = pal, c, {}, seed

    def _r(self, lo, hi):
        return range(math.floor(lo / self.c), math.ceil(hi / self.c))

    def fill(self, xr, yr, zr, fn, key):
        c = self.c
        for i in self._r(*xr):
            for j in self._r(*yr):
                for k in self._r(*zr):
                    p = ((i + 0.5) * c, (j + 0.5) * c, (k + 0.5) * c)
                    if fn(*p):
                        if key is None:
                            self.v.pop((i, j, k), None)
                        else:
                            self.v[(i, j, k)] = key

    def flat(self, R, k, fn, key):
        """one layer k of a 2D shape: fn(x, y) -> bool"""
        c = self.c
        for i in self._r(-R, R):
            for j in self._r(-R, R):
                x, y = (i + 0.5) * c, (j + 0.5) * c
                if fn(x, y):
                    self.v[(i, j, k)] = key

    def ell(self, ctr, rad, key):
        cx, cy, cz = ctr
        rx, ry, rz = rad
        self.fill((cx - rx, cx + rx), (cy - ry, cy + ry), (cz - rz, cz + rz),
                  lambda x, y, z: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1.0, key)

    def paint(self, key, fn, only=None, prob=1.0, seed=1):
        c = self.c
        for (i, j, k), kk in list(self.v.items()):
            if only and kk not in only:
                continue
            if fn((i + 0.5) * c, (j + 0.5) * c, (k + 0.5) * c) and hsh(i, j, k, seed) < prob:
                self.v[(i, j, k)] = key

    def build(self, coll, name, loc=(0, 0, 0), jitter=0.05, zscale=1.0, shade_bottom=True):
        c = self.c
        groups = {}
        for cell, key in self.v.items():
            groups.setdefault(self.pal[key][1] if len(self.pal[key]) > 1 else "solid", []).append(cell)
        made = []
        dirs = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
        if self.v:
            kmin = min(k for (_, _, k) in self.v)
            kmax = max(k for (_, _, k) in self.v)
        for kind, cells in groups.items():
            bm = bmesh.new()
            col = bm.loops.layers.float_color.new("Col")
            vmap = {}

            def vert(p):
                vv = vmap.get(p)
                if vv is None:
                    vv = vmap[p] = bm.verts.new((p[0] * c, p[1] * c, p[2] * c))
                return vv
            for (i, j, k) in cells:
                key = self.v[(i, j, k)]
                base = self.pal[key][0]
                f = 1.0 + (hsh(i, j, k, self.seed) - 0.5) * 2 * jitter
                if shade_bottom and kmax > kmin:
                    f *= 0.86 + 0.14 * (k - kmin) / (kmax - kmin)  # baked: darker toward the bottom
                colr = (lin(min(255, base[0] * f)), lin(min(255, base[1] * f)), lin(min(255, base[2] * f)))
                for d in dirs:
                    if (i + d[0], j + d[1], k + d[2]) in self.v:
                        continue
                    ax = [a for a in range(3) if d[a] != 0][0]
                    o = [i, j, k]
                    if d[ax] > 0:
                        o[ax] += 1
                    u, w = [a for a in range(3) if a != ax]
                    quad = []
                    for du, dw in ((0, 0), (1, 0), (1, 1), (0, 1)):
                        p = list(o)
                        p[u] += du
                        p[w] += dw
                        quad.append(vert(tuple(p)))
                    try:
                        face = bm.faces.new(quad if (d[ax] > 0) ^ (ax == 1) else quad[::-1])
                    except ValueError:
                        continue
                    shade = 0.78 if d[2] < 0 else (1.0 if d[2] > 0 else 0.92)
                    for lp in face.loops:
                        lp[col] = (colr[0] * shade, colr[1] * shade, colr[2] * shade, 1.0)
            me = bpy.data.meshes.new(name + "_" + kind)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(kind_mat(kind))
            ob = bpy.data.objects.new(name + "_" + kind, me)
            ob.location = loc
            ob.scale = (1, 1, zscale)
            coll.objects.link(ob)
            made.append(ob)
        return made


def box(coll, size, loc, m, bevel=0.06, rot=(0, 0, 0), name="box"):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=1, affect="EDGES")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = rot
    coll.objects.link(ob)
    return ob


def beam(coll, a, b, w, m, bevel=0.05):
    a, b = V(a), V(b)
    d = b - a
    ob = box(coll, (w, w, d.length), (a + b) / 2, m, bevel)
    ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return ob


def group(coll, name, parts, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    root = bpy.data.objects.new(name, None)
    coll.objects.link(root)
    for p in parts:
        p.parent = root
    root.location = loc
    root.rotation_euler = rot
    root.scale = scale
    return root


# ================================================================================ the player (5.3 studs, R15)
def player(coll, loc, face=0.0):
    x, y, z = loc
    skin = M((234, 196, 160), rough=0.55)
    shirt = M((90, 140, 210), rough=0.7)
    pants = M((60, 66, 90), rough=0.75)
    shoe = M((40, 40, 48))
    hair = M((90, 60, 40), rough=0.7)
    parts = []
    for sx in (-0.5, 0.5):
        parts.append(box(coll, (0.95, 1.0, 0.35), (sx, -0.05, 0.175), shoe, 0.08))
        parts.append(box(coll, (0.9, 0.9, 0.85), (sx, 0, 0.775), pants, 0.08))
        parts.append(box(coll, (0.95, 0.95, 0.85), (sx, 0, 1.6), pants, 0.08))
    parts.append(box(coll, (2.0, 1.0, 0.45), (0, 0, 2.225), pants, 0.08))
    parts.append(box(coll, (2.0, 1.0, 1.55), (0, 0, 3.225), shirt, 0.1))
    for sx in (-1.5, 1.5):
        parts.append(box(coll, (0.95, 0.95, 0.85), (sx, 0, 3.55), shirt, 0.08))
        parts.append(box(coll, (0.9, 0.9, 0.8), (sx, 0, 2.75), skin, 0.08))
        parts.append(box(coll, (0.85, 0.85, 0.4), (sx, 0, 2.15), skin, 0.08))
    parts.append(box(coll, (1.2, 1.2, 1.2), (0, 0, 4.7), skin, 0.3))
    parts.append(box(coll, (1.26, 1.26, 0.35), (0, 0.04, 5.15), hair, 0.12))
    eye = M(INK, rough=0.4)
    for sx in (-0.22, 0.22):
        parts.append(box(coll, (0.14, 0.05, 0.22), (sx, -0.61, 4.78), eye, 0.0))
    return group(coll, "Player", parts, (x, y, z), (0, 0, face))


# ================================================================================ the kit: today's real bake
_K = {}
PM = np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])
KEEP_COL = {}


def kit_target():
    if "t" not in _K:
        import props
        props.load_all()
        from props import arena
        _K["arena"] = arena
        _K["t"] = arena.target("arena_pocket")
        _K["props"] = props
    return _K["t"]


def baked(clean):
    """the arena_pocket ModelSpec: clean = without the emblem and the crowd puffs (the options' ring)"""
    k = "clean" if clean else "full"
    if k in _K:
        return _K[k]
    t = kit_target()
    arena = _K["arena"]
    from props import arena_style as AS
    keep = set(x for x in (t.get("Keep") or "").split(",") if x)
    allb = arena.parse_boxes(t["Boxes"], 1.0)
    bx = [b for b in allb if b["name"] not in keep]
    if clean:
        bx = [b for b in bx if not (b["name"].startswith("Emblem") or b["name"].startswith("Puff"))]
    m = _K["props"].PropKit().model("arena_pocket", "prop", vs=0.5, K=1.0)
    stats = AS.bake(m, bx, 0.5, budget=24000, opts={"vs": 0.5, "aligny": True, "soften": 1})
    print("[pitch] bake", k, stats["level"], stats["tries"], flush=True)
    _K[k] = (m, [b for b in allb if b["name"] in keep])
    return _K[k]


def kept_box(coll, b, ox):
    """a Keep part (Neon) as a box in Blender space"""
    h = b["size"] / 2
    corners = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                p = b["pos"] + b["R"] @ (h * np.array([sx, sy, sz]))
                q = PM @ p
                corners.append((q[0] + ox, q[1], q[2]))
    me = bpy.data.meshes.new(b["name"])
    idx = lambda sx, sy, sz: ((sx > 0) * 4 + (sy > 0) * 2 + (sz > 0))
    faces = []
    for ax in range(3):
        for s in (-1, 1):
            quad = []
            for u, w in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                c = [0, 0, 0]
                c[ax] = s
                o = [a for a in range(3) if a != ax]
                c[o[0]], c[o[1]] = u, w
                quad.append(idx(*c))
            faces.append(quad if s > 0 else quad[::-1])
    me.from_pydata(corners, [], faces)
    me.validate()
    me.normals_split_custom_set(None) if False else None
    col = b["rgb"]
    me.materials.append(M(col, emit=1.3 if b["mat"] == "Neon" else 0.0))
    ob = bpy.data.objects.new(b["name"], me)
    coll.objects.link(ob)
    return ob


def ring(coll, ox, clean, gems=True):
    from nvox import blend as B
    m, kept = baked(clean)
    made = B.make_objects(m, None, collection=coll)
    for ob in made:
        ob.location = (ox, 0, 0)
    for b in kept:
        if b["name"] == "EmblemGem" and (clean or not gems):
            continue
        made.append(kept_box(coll, b, ox))
    return made


# ================================================================================ shared crowd pieces
STAND_Y = 33.0 + 4.6  # Ring.FloorA + 4.6 (Roblox z) -> Blender y
FRONT = [(-12, 1.35, 1.9), (-4, 1.35, 1.9), (4, 1.35, 1.9), (12, 1.35, 1.9)]
BACK = [(-8, 3.35, 5.7), (0, 3.35, 5.7), (8, 3.35, 5.7)]
SEATS = FRONT + BACK  # (x, seat top z, stand-local depth)


def seat(i, ox):
    x, z, d = SEATS[i]
    return V((ox + x, STAND_Y + d, z))


def cloud_vox(pal_key_col, seed, w=3.4, h=3.0, dpt=2.4, c=0.25, bumps=3):
    """a cloud body: a fat base + bumps on top (local origin = bottom centre)"""
    vx = Vox({"B": (pal_key_col,)}, c, seed)
    rng = random.Random(seed)
    vx.ell((0, 0, h * 0.36), (w / 2, dpt / 2, h * 0.38), "B")
    for k in range(bumps):
        bx = (k - (bumps - 1) / 2) * (w / bumps) * 0.9 + rng.uniform(-0.2, 0.2)
        r = rng.uniform(0.7, 0.95) * w / 3.2
        vx.ell((bx, rng.uniform(-0.15, 0.15), h * 0.62 + rng.uniform(0, 0.3)), (r, r * 0.95, r * 0.9), "B")
    vx.ell((0, 0, h * 0.78), (w * 0.26, dpt * 0.3, h * 0.24), "B")
    return vx


def face(coll, at, mood, eye=INK, w=1.0):
    """eyes + mouth on the front (-Y) of a body; mood: smile | o | grump | sleepy | wide"""
    parts = []
    ink = M(eye, rough=0.4)
    mouth = M((196, 70, 104), rough=0.5)
    x, y, z = at
    for sx in (-1, 1):
        if mood == "sleepy":
            parts.append(box(coll, (0.42 * w, 0.1, 0.14), (x + sx * 0.55 * w, y, z), ink, 0.0))
        elif mood == "wide":
            parts.append(box(coll, (0.42 * w, 0.1, 0.62), (x + sx * 0.55 * w, y, z), ink, 0.0))
        else:
            parts.append(box(coll, (0.34 * w, 0.1, 0.55), (x + sx * 0.55 * w, y, z), ink, 0.0))
        if mood == "grump":
            parts.append(box(coll, (0.62 * w, 0.12, 0.16), (x + sx * 0.55 * w, y - 0.02, z + 0.42), ink, 0.0,
                             rot=(0, sx * 0.35, 0)))
    if mood in ("o", "wide"):
        parts.append(box(coll, (0.46 * w, 0.1, 0.46), (x, y, z - 0.62), mouth, 0.0))
    elif mood == "grump":
        parts.append(box(coll, (0.6 * w, 0.1, 0.16), (x, y, z - 0.62), ink, 0.0))
    else:
        parts.append(box(coll, (0.66 * w, 0.1, 0.3), (x, y, z - 0.6), mouth, 0.0))
    return parts


def arm(coll, base, side, up, col, length=1.5, w=0.6):
    """a stubby arm from the body side; up = 0 (down) .. 1 (straight up)"""
    ang = side * (0.35 + up * 2.4)
    d = V((side * math.sin(0.35 + up * 2.4), 0, -math.cos(0.35 + up * 2.4)))
    a = V(base)
    return beam(coll, a, a + d * length, w, M(col), 0.12), a + d * length


# ================================================================================ TODAY
def today(coll, ox):
    ring(coll, ox, clean=False)
    player(coll, (ox - 9.0, -6.5, FLOOR_Z), face=0.6)


# ================================================================================ A: Sky-Sailors' Ring (compass star)
def emblem_a(coll, ox, c=0.25, zs=0.4):
    pal = {"V": (VIOLET,), "VD": (VIOLET_D,), "Rim": ((206, 160, 80), "metal"), "RimD": ((168, 124, 58), "metal"),
           "G": (GOLD, "metal"), "GD": (GOLD_D, "metal"), "C": ((250, 236, 200),), "CD": ((222, 204, 166),),
           "Rope": ((214, 180, 120),), "RopeD": ((170, 134, 84),), "Patch": ((150, 154, 162), "metal"),
           "Rivet": ((80, 82, 92), "metal"), "Dot": (GOLD, "metal")}
    vx = Vox(pal, c, seed=11)
    R = 7.6
    rr = lambda x, y: math.hypot(x, y)
    vx.flat(R, 0, lambda x, y: rr(x, y) <= 7.5, "V")
    # brass rim + rope coil (alternating diagonal strands)
    vx.flat(R, 1, lambda x, y: 6.75 <= rr(x, y) <= 7.5, "Rim")
    vx.flat(R, 1, lambda x, y: 5.9 <= rr(x, y) < 6.75, "Rope")
    vx.paint("RopeD", lambda x, y, z: (int((math.atan2(y, x) * 6.75 / 0.55) + rr(x, y) / 0.3) % 2 == 0), only={"Rope"})

    def star(x, y, n, rlong, rshort, rot):
        a = (math.atan2(y, x) - rot) % (TAU / n)
        a = abs(a - TAU / (2 * n)) / (TAU / (2 * n))  # 0 at the gap mid, 1 at a point
        r = rr(x, y)
        lim = rshort + (rlong - rshort) * a ** 2.2
        return r <= lim

    # 4 long cardinal points (N toward the champion, +Y), 4 short diagonal points; each point two-tone (rose shading)
    def ptkey(x, y, light, dark):
        ang = math.atan2(y, x)
        sector = (ang + TAU) % (TAU / 4)
        return light if sector < TAU / 8 else dark
    for (i, j, k), kk in list(vx.v.items()):
        pass
    cells = {}
    for i in vx._r(-R, R):
        for j in vx._r(-R, R):
            x, y = (i + 0.5) * c, (j + 0.5) * c
            if star(x, y, 4, 5.85, 1.25, 0.0) and rr(x, y) < 5.9:
                ang = (math.atan2(y, x) + TAU) % (TAU / 4)
                cells[(i, j, 1)] = "G" if ang < TAU / 8 else "GD"
            elif star(x, y, 4, 4.1, 1.25, math.pi / 4) and rr(x, y) < 5.9:
                ang = (math.atan2(y, x) + TAU / 8 + TAU) % (TAU / 4)
                cells[(i, j, 1)] = "C" if ang < TAU / 8 else "CD"
    vx.v.update(cells)
    # the repair plate: the south-east short point is a grey steel plate with rivets (a newer repair)
    # a riveted steel plate bolted over the south-west point's base (a later repair, a different metal)
    pc = (-2.35, -2.35)
    rot = lambda x, y: ((x - pc[0] + y - pc[1]) / 1.414, (y - pc[1] - x + pc[0]) / 1.414)
    vx.flat(R, 2, lambda x, y: max(abs(rot(x, y)[0]), abs(rot(x, y)[1])) <= 0.95, "Patch")
    for (u, w) in ((-0.6, -0.6), (0.6, -0.6), (-0.6, 0.6), (0.6, 0.6)):
        px = pc[0] + (u - w) / 1.414
        py = pc[1] + (u + w) / 1.414
        vx.v[(math.floor(px / c), math.floor(py / c), 3)] = "Rivet"
    # centre boss: a gold hub with a violet pin
    vx.flat(R, 2, lambda x, y: rr(x, y) <= 1.15, "Dot")
    vx.flat(R, 2, lambda x, y: rr(x, y) <= 0.5, "VD")
    return vx.build(coll, "EmblemA", (ox, 0, FLOOR_Z), jitter=0.04, zscale=zs, shade_bottom=False)


SAILOR_CAP = None


def cap(coll, top, tilt=0.0, captain=False, fly=0.0):
    white = M((246, 248, 252))
    navy = M((40, 54, 110))
    gold = M(GOLD, metal=0.4, rough=0.4)
    x, y, z = top
    z += fly
    parts = []
    if captain:
        parts.append(box(coll, (1.9, 1.6, 0.55), (x, y, z + 0.3), navy, 0.12))
        parts.append(box(coll, (2.0, 0.6, 0.12), (x, y - 0.95, z + 0.08), navy, 0.04))
        parts.append(box(coll, (1.95, 1.65, 0.2), (x, y, z + 0.1), gold, 0.05))
        parts.append(box(coll, (0.5, 0.1, 0.4), (x, y - 0.82, z + 0.35), gold, 0.03))
    else:
        parts.append(box(coll, (1.6, 1.4, 0.45), (x, y, z + 0.25), white, 0.14))
        parts.append(box(coll, (1.65, 1.45, 0.18), (x, y, z + 0.06), navy, 0.05))
        parts.append(box(coll, (0.3, 0.3, 0.2), (x, y, z + 0.55), M((220, 60, 70)), 0.08))
    for p in parts:
        p.rotation_euler = (0, tilt, 0)
    return parts


def crowd_a(coll, ox, pose="idle", t=0.0):
    """retired weather clouds in sailor caps; pose: idle | hit | won | boss"""
    made = []
    specs = [  # seat, name, colour, mood, w, h, extra
        (0, "Rain", (176, 196, 222), "smile", 3.2, 2.8, "rain"),
        (1, "Captain", (118, 124, 150), "grump", 3.8, 3.2, "thunder"),
        (2, "Sun", (255, 232, 160), "smile", 3.2, 2.8, "sun"),
        (3, "Snow", (246, 250, 255), "smile", 3.0, 2.7, "snow"),
        (4, "Breeze", (204, 244, 216), "smile", 3.0, 2.7, "breeze"),
        (5, "Fog", (226, 216, 246), "sleepy", 3.4, 2.9, "spyglass"),
        (6, "Drizzle", (196, 222, 246), "smile", 2.4, 2.2, "kid"),
    ]
    drop = M((120, 180, 240), emit=0.2)
    for si, name, colr, mood, w, h, extra in specs:
        base = seat(si, ox)
        sw = 1.0 + 0.04 * math.sin(TAU * (t + si * 0.17))
        lift, lean, up = 0.0, 0.0, 0.15
        if pose == "won":
            sw, lift, up = 1.15, 1.0 + 0.3 * (si % 2), 1.0
            mood = "wide" if mood != "grump" else "smile"
        elif pose == "hit":
            lean, up = 0.22, 0.45
            mood = "o" if name != "Captain" else "wide"
        elif pose == "boss":
            lean, up = -0.12, 0.3
            colr = tuple(int(cc * 0.72 + 70 * 0.28) for cc in colr)
            mood = "grump" if name == "Captain" else "o"
        if name == "Captain" and pose == "hit":
            colr = (190, 196, 220)  # the flash
        parts = []
        vx = cloud_vox(colr, seed=si * 7 + 3, w=w, h=h, dpt=2.4)
        parts += vx.build(coll, name, (0, 0, 0), jitter=0.03)
        fz = h * 0.42
        parts += face(coll, (0, -1.22, fz), mood, w=w / 3.4)
        for side in (-1, 1):
            a, _ = arm(coll, (side * w * 0.42, 0, h * 0.4), side, up, tuple(int(cc * 0.9) for cc in colr), 1.3, 0.55)
            parts.append(a)
        top = (0.05, 0.0, h * 0.93)
        if name == "Captain":
            parts += cap(coll, top, -0.08, captain=True, fly=0.5 if pose == "won" else 0.0)
        elif name in ("Rain", "Sun", "Breeze", "Drizzle"):
            parts += cap(coll, top, 0.12 if si % 2 else -0.12, fly=0.6 if pose == "won" else 0.0)
        if extra == "rain":  # drizzle under it (falls through the seat line: loops in the game)
            n = 6 if pose in ("idle", "won") else 10
            for k in range(n):
                ph = (k / n + t * 1.7) % 1.0
                parts.append(box(coll, (0.16, 0.16, 0.42), ((k % 3 - 1) * 0.8 + 0.2 * (k % 2), -1.4, h * 0.15 - ph * 1.0),
                                 drop, 0.03))
        if extra == "snow":
            sc = M((236, 70, 70))
            parts.append(box(coll, (w * 0.82, 2.3, 0.45), (0, 0, h * 0.3), sc, 0.12))
            parts.append(box(coll, (0.55, 0.3, 1.1), (0.7, -1.2, h * 0.08), sc, 0.08))
            for k in range(3):
                parts.append(box(coll, (0.3, 0.3, 0.3), (-1.4 + k * 1.3, -1.6, h + 0.3 + ((k * 0.37 - t) % 1.0) * -1.0),
                                 M((250, 252, 255), emit=0.3), 0.05, rot=(0, 0.7, 0.7)))
        if extra == "sun":
            ray = M((250, 170, 70))
            for k in range(7):
                a = math.pi * (k / 6.0)
                parts.append(box(coll, (0.5, 0.3, 0.9), (math.cos(a) * (w * 0.62), 0.6, h * 0.5 + math.sin(a) * h * 0.55),
                                 ray, 0.08, rot=(0, -(a - math.pi / 2), 0)))
        if extra == "thunder" and pose in ("hit", "boss"):
            bolt = M((255, 226, 80), emit=1.5)
            for k, (bx, bz) in enumerate(((0.0, 0.0), (-0.7, -1.1), (0.0, -2.2))):  # a chunky zig-zag bolt over him
                parts.append(box(coll, (0.7, 0.35, 1.5), (-w * 0.2 + bx, -0.9, h + 2.9 + bz), bolt, 0.05,
                                 rot=(0, 0.55 if k % 2 else -0.55, 0)))
            if pose == "hit":
                glow = M((255, 250, 210), emit=0.6, alpha=1.0)
                for k in range(6):  # the flash: spark blocks round his body
                    a = TAU * k / 6
                    parts.append(box(coll, (0.35, 0.35, 0.35), (math.cos(a) * w * 0.7, -0.9, h * 0.5 + math.sin(a) * h * 0.6),
                                     glow, 0.05, rot=(0, 0.78, 0)))
        if extra == "spyglass":
            brass = M((206, 160, 80), metal=0.45, rough=0.4)
            parts.append(beam(coll, (0.9, -1.3, h * 0.45), (1.9, -2.2, h * 0.75), 0.4, brass, 0.06))
        if pose == "boss":  # everyone drizzles in a boss round
            for k in range(4):
                parts.append(box(coll, (0.16, 0.16, 0.42), ((k - 1.5) * 0.8, -1.3, -0.2 - ((k * 0.3 + t) % 1.0) * 0.8),
                                 drop, 0.03))
        g = group(coll, "Crowd_" + name, parts, base + V((0, 0, lift)), (lean, 0, 0), (sw, sw, 1.0 / sw ** 0.5))
        made.append(g)
    # props: the ship's bell and a life ring on the west flag mast, the signal-flag line, a rope coil
    wood = M((150, 104, 66))
    brass = M((214, 168, 82), metal=0.5, rough=0.35)
    bx0 = ox - 15.0  # the bell and the life ring hang on the west flag mast
    by = STAND_Y + 7.4 - 0.45
    # (the mast itself is built with the flag line below)
    made.append(box(coll, (2.2, 0.5, 0.5), (bx0 + 0.8, by, 8.3), wood, 0.08))
    swing = 0.5 if pose == "won" else (0.25 if pose == "boss" else 0.0)
    bell = [box(coll, (1.2, 1.2, 1.3), (0, 0, -0.9), brass, 0.25), box(coll, (1.6, 1.6, 0.35), (0, 0, -1.55), brass, 0.12),
            box(coll, (0.3, 0.3, 0.5), (0, 0, -2.0), M((90, 70, 50)), 0.05)]
    made.append(group(coll, "Bell", bell, (bx0 + 1.6, by, 8.05), (0, swing, 0)))
    lr = M((236, 72, 70))
    lw = M((250, 250, 250))
    for k in range(8):
        a = TAU * k / 8
        made.append(box(coll, (0.9, 0.35, 0.5), (bx0 + math.cos(a) * 0.95, by - 0.55, 4.2 + math.sin(a) * 0.95),
                        lr if k % 2 else lw, 0.1, rot=(0, -a, 0)))
    # flag line between two masts behind the back row
    mast_x = (ox - 15.0, ox + 15.0)
    my = STAND_Y + 7.4
    for mx in mast_x:
        made.append(box(coll, (0.6, 0.6, 10.0), (mx, my, 5.0), wood, 0.1))
    flags = [(236, 72, 70), (250, 250, 250), (60, 110, 210), (250, 200, 60), (236, 72, 70), (60, 110, 210),
             (250, 250, 250), (250, 200, 60), (60, 110, 210), (236, 72, 70)]
    n = len(flags)
    for k in range(n + 1):
        s = k / n
        x = mast_x[0] + (mast_x[1] - mast_x[0]) * s
        z = 9.6 - 1.6 * math.sin(math.pi * s)
        if k < n:
            s2 = (k + 1) / n
            x2 = mast_x[0] + (mast_x[1] - mast_x[0]) * s2
            z2 = 9.6 - 1.6 * math.sin(math.pi * s2)
            made.append(beam(coll, (x, my, z), (x2, my, z2), 0.12, M((90, 70, 50)), 0.02))
            fx = (x + x2) / 2
            fz = (z + z2) / 2 - 0.75
            flap = 0.25 * math.sin(TAU * (t + k * 0.13)) if pose != "won" else 0.5
            made.append(box(coll, (1.1, 0.12, 1.2), (fx, my + 0.05, fz), M(flags[k]), 0.04, rot=(flap * 0.3, 0, 0)))
    # rope coil on the front step
    rope = M((206, 172, 112))
    for k in range(10):
        a = TAU * k / 10
        made.append(box(coll, (0.7, 0.4, 0.4), (ox + 16.0 + math.cos(a) * 0.8, STAND_Y + 1.0 + math.sin(a) * 0.8, 1.55),
                        rope, 0.12, rot=(0, 0, a + math.pi / 2)))
    return made


# ================================================================================ B: Grandpaws' Ring (star paw)
def star_fn(n, rlong, rshort, rot=math.pi / 2):
    def f(x, y):
        a = (math.atan2(y, x) - rot) % (TAU / n)
        a = abs(a - TAU / (2 * n)) / (TAU / (2 * n))
        return math.hypot(x, y) <= rshort + (rlong - rshort) * a ** 1.5
    return f


def emblem_b(coll, ox, c=0.25, zs=0.4):
    pal = {"V": (VIOLET,), "Cream": ((246, 230, 196),), "CreamD": ((222, 200, 160),), "G": (GOLD, "metal"),
           "GD": (GOLD_D, "metal"), "GL": (GOLD_L, "metal"), "Scr": ((88, 48, 150),)}
    vx = Vox(pal, c, seed=21)
    R = 7.6
    rr = lambda x, y: math.hypot(x, y)
    vx.flat(R, 0, lambda x, y: rr(x, y) <= 7.5, "V")
    vx.flat(R, 1, lambda x, y: 6.6 <= rr(x, y) <= 7.5, "Cream")
    vx.paint("CreamD", lambda x, y, z: True, only={"Cream"}, prob=0.3, seed=4)
    st = star_fn(5, 3.4, 1.75)
    vx.flat(R, 1, lambda x, y: st(x, y + 1.3), "G")
    vx.paint("GD", lambda x, y, z: x > 0.3 and z > c, only={"G"})
    # four toe beans (ovals) in an arc toward the champion (+Y)
    for ang, rad_, sz in ((112, 4.6, 1.15), (68, 4.6, 1.15), (148, 3.9, 1.0), (32, 3.9, 1.0)):
        a = math.radians(ang)
        cx, cy = math.cos(a) * rad_, math.sin(a) * rad_ + 0.2
        vx.flat(R, 1, lambda x, y, cx=cx, cy=cy, sz=sz: ((x - cx) / sz) ** 2 + ((y - cy) / (sz * 1.25)) ** 2 <= 1.0, "G")
    vx.paint("GL", lambda x, y, z: z > c and hsh(int(x * 4), int(y * 4)) < 0.12, only={"G"})
    # three old scratch grooves across the violet (claw marks from the first sparring pets)
    for k in range(3):
        vx.paint("Scr", lambda x, y, z, k=k: abs((x * 0.8 - y) - (-7.6 + k * 0.8)) < 0.26 and x < -2.2, only={"V"})
    return vx.build(coll, "EmblemB", (ox, 0, FLOOR_Z), jitter=0.04, zscale=zs, shade_bottom=False)


def paw_trail(coll, ox):
    """worn paw prints in the sand from the fighter's pad to the emblem (darker sand, flush)"""
    pal = {"P": ((204, 172, 124),)}
    vx = Vox(pal, 0.25, seed=5)
    for k in range(5):
        y = -24.0 + k * 3.0
        x = (1.1 if k % 2 else -1.1) + 3.0
        vx.fill((x - 0.8, x + 0.8), (y - 0.7, y + 0.7), (0, 0.25), lambda a, b, cz, x=x, y=y: ((a - x) / 0.75) ** 2 + ((b - y) / 0.6) ** 2 <= 1, "P")
        for dx in (-0.8, 0.0, 0.8):
            vx.fill((x + dx - 0.3, x + dx + 0.3), (y + 0.95, y + 1.6), (0, 0.25), lambda a, b, cz: True, "P")
    return vx.build(coll, "PawTrail", (ox, 0, FLOOR_Z - 0.08), jitter=0.05, zscale=0.4, shade_bottom=False)


def pet(coll, kind, col, scale, pose, t, si, prop=None):
    """a blocky pet spectator (body + head + ears), local origin = bottom centre, facing -Y"""
    parts = []
    body = M(col)
    dark = M(tuple(int(c * 0.82) for c in col))
    belly = M(tuple(min(255, int(c * 0.6 + 255 * 0.4)) for c in col))
    s = scale
    parts.append(box(coll, (1.9 * s, 1.6 * s, 1.7 * s), (0, 0, 0.85 * s), body, 0.2 * s))
    parts.append(box(coll, (1.2 * s, 0.1, 1.1 * s), (0, -0.82 * s, 0.8 * s), belly, 0.0))
    hz = 2.55 * s
    parts.append(box(coll, (2.2 * s, 1.9 * s, 1.8 * s), (0, -0.1 * s, hz), body, 0.25 * s))
    mood = {"idle": "smile", "hit": "wide", "won": "smile", "boss": "o"}[pose]
    fparts = face(coll, (0, -1.07 * s, hz + 0.1 * s), mood, w=0.75 * s)
    parts += fparts
    if kind == "cat":
        for sx in (-1, 1):
            parts.append(box(coll, (0.6 * s, 0.4 * s, 0.7 * s), (sx * 0.7 * s, -0.1 * s, hz + 1.1 * s), body, 0.05, rot=(0, sx * 0.2, 0)))
            parts.append(box(coll, (0.5 * s, 0.1, 0.12 * s), (sx * 1.05 * s, -1.1 * s, hz - 0.25 * s), dark, 0.0))
    elif kind == "pup":
        for sx in (-1, 1):
            parts.append(box(coll, (0.5 * s, 0.9 * s, 1.3 * s), (sx * 1.25 * s, 0.0, hz - 0.1 * s), dark, 0.12 * s, rot=(0, sx * 0.15, 0)))
        parts.append(box(coll, (0.9 * s, 0.6 * s, 0.6 * s), (0, -1.2 * s, hz - 0.45 * s), belly, 0.12 * s))
        parts.append(box(coll, (0.4 * s, 0.15, 0.3 * s), (0, -1.52 * s, hz - 0.3 * s), M(INK), 0.05))
    elif kind == "bunny":
        for sx in (-1, 1):
            parts.append(box(coll, (0.55 * s, 0.4 * s, 1.8 * s), (sx * 0.5 * s, 0.0, hz + 1.7 * s), body, 0.15 * s, rot=(0, sx * 0.12, 0)))
            parts.append(box(coll, (0.3 * s, 0.1, 1.3 * s), (sx * 0.5 * s, -0.21 * s, hz + 1.7 * s), M((246, 170, 196)), 0.0, rot=(0, sx * 0.12, 0)))
    elif kind == "duck":
        parts.append(box(coll, (1.1 * s, 0.7 * s, 0.4 * s), (0, -1.25 * s, hz - 0.3 * s), M((246, 150, 60)), 0.1 * s))
        parts.append(box(coll, (0.4 * s, 0.4 * s, 0.5 * s), (0.2 * s, 0, hz + 1.05 * s), body, 0.1 * s))
    elif kind == "hamster":
        for sx in (-1, 1):
            parts.append(box(coll, (0.55 * s, 0.3 * s, 0.5 * s), (sx * 0.75 * s, -0.1 * s, hz + 0.95 * s), M((246, 170, 180)), 0.12 * s))
            parts.append(box(coll, (0.5 * s, 0.1, 0.32 * s), (sx * 0.85 * s, -1.08 * s, hz - 0.35 * s), M((246, 170, 196)), 0.05))
    # arms / paws
    up = {"idle": 0.2, "hit": 0.0, "won": 1.0, "boss": 0.55}[pose]
    for side in (-1, 1):
        if pose == "hit":  # paws over the eyes
            parts.append(box(coll, (0.6 * s, 0.6 * s, 0.6 * s), (side * 0.55 * s, -1.25 * s, hz + 0.12 * s), dark, 0.15 * s))
            parts.append(beam(coll, (side * 1.0 * s, -0.5 * s, 1.3 * s), (side * 0.6 * s, -1.2 * s, hz), 0.5 * s, dark, 0.1))
            continue
        a, tip = arm(coll, (side * 1.0 * s, -0.2 * s, 1.35 * s), side, up, tuple(int(c * 0.82) for c in col), 1.2 * s, 0.5 * s)
        parts.append(a)
        if prop == "foam" and side == 1:
            fm = M(GOLD)
            parts.append(box(coll, (1.3, 0.35, 1.5), tip + V((0, -0.1, 0.7)), fm, 0.2))
            for k in range(3):
                parts.append(box(coll, (0.38, 0.35, 0.5), tip + V(((k - 1) * 0.42, -0.1, 1.65)), fm, 0.12))
            parts.append(box(coll, (0.5, 0.36, 0.6), tip + V((0.7, -0.1, 0.9)), fm, 0.12))
            # a violet star painted on the foam
            parts.append(box(coll, (0.5, 0.08, 0.5), tip + V((0, -0.3, 0.75)), M(VIOLET), 0.0, rot=(0, 0.78, 0)))
    if prop == "drum":
        drum = M((214, 76, 76))
        parts.append(box(coll, (1.8 * s, 1.4 * s, 1.0 * s), (0, -1.6 * s, 0.9 * s), drum, 0.18 * s))
        parts.append(box(coll, (1.7 * s, 1.3 * s, 0.12), (0, -1.6 * s, 1.43 * s), M((246, 236, 212)), 0.05))
        for side in (-1, 1):
            hit = (math.sin(TAU * (t * 4 + side * 0.25)) > 0) if pose in ("boss", "idle") else (pose == "won")
            parts.append(beam(coll, (side * 0.8 * s, -1.0 * s, 1.5 * s), (side * 0.4 * s, -1.9 * s, (1.5 if hit else 2.4) * s),
                              0.18, M((150, 104, 66)), 0.03))
    return parts


def crowd_b(coll, ox, pose="idle", t=0.0):
    """pet families with homemade banners, a foam paw and a little drummer"""
    made = []
    specs = [  # seat, kind, colour, scale, prop
        (0, "cat", (246, 170, 90), 1.0, "foam"),
        (1, "pup", (196, 146, 100), 1.05, None),
        (2, "bunny", (246, 244, 250), 0.95, None),
        (3, "duck", (252, 222, 90), 0.9, "foam"),
        (4, "hamster", (236, 200, 150), 0.95, None),
        (5, "pup", (150, 110, 80), 0.85, "drum"),
        (6, "cat", (180, 180, 196), 1.0, None),
    ]
    for si, kind, col, sc, prop in specs:
        base = seat(si, ox)
        sway = 0.12 * math.sin(TAU * (t + si * 0.21)) if pose == "idle" else 0.0
        lift = {"idle": 0.0, "hit": -0.1, "won": 0.9 + 0.3 * (si % 2), "boss": 0.35}[pose]
        lean = {"idle": 0.0, "hit": 0.18, "won": -0.05, "boss": -0.15}[pose]
        parts = pet(coll, kind, col, sc, pose, t, si, prop)
        made.append(group(coll, "Pet_%d" % si, parts, base + V((0, 0, lift)), (lean, sway, 0)))
    # the homemade banner: a violet bedsheet painted with a gold paw, held up between the back-row pets
    cloth = M((168, 112, 236))
    paint = M(GOLD)
    stick = M((150, 104, 66))
    shake = {"idle": 0.0, "hit": 0.0, "won": 0.1, "boss": 0.18}[pose] * (1 if int(t * 4) % 2 else -1)
    bz = 9.0 + (0.8 if pose in ("won", "boss") else 0.0)
    by = STAND_Y + 7.0
    bparts = []
    for sx in (-4.0, 4.0):
        bparts.append(box(coll, (0.3, 0.3, 6.0), (sx, 0, -1.6), stick, 0.05))
    bparts.append(box(coll, (7.6, 0.15, 2.8), (0, 0, 0.0), cloth, 0.04))
    # the painted paw (uneven, by hand)
    bparts.append(box(coll, (1.4, 0.1, 1.0), (0, -0.1, -0.4), paint, 0.1, rot=(0, 0.06, 0)))
    for k, (px, pz) in enumerate(((-0.95, 0.5), (-0.32, 0.85), (0.35, 0.82), (0.95, 0.45))):
        bparts.append(box(coll, (0.45, 0.1, 0.55), (px, -0.1, pz), paint, 0.08, rot=(0, k * 0.1, 0)))
    for k, sx in enumerate((-3.2, 2.8)):  # little hearts / stars painted in the corners
        bparts.append(box(coll, (0.5, 0.1, 0.5), (sx, -0.1, 0.7 - k * 1.3), M((255, 255, 255)), 0.05, rot=(0, 0.78, 0)))
    made.append(group(coll, "Banner", bparts, (ox, by, bz), (0, shake, 0)))
    # second banner on the left (a pennant of stitched patches)
    pparts = [box(coll, (0.25, 0.25, 6.5), (0, 0, 0), stick, 0.04)]
    for k, colr in enumerate(((250, 200, 60), (236, 110, 140), (120, 196, 236))):
        pparts.append(box(coll, (1.4 - k * 0.4, 0.1, 0.9), (0.85 - k * 0.2, 0, 2.6 - k * 0.9), M(colr), 0.04))
    made.append(group(coll, "Pennant", pparts, (ox - 15.4, STAND_Y + 2.2, 4.4), (0, -0.12 + shake, 0)))
    # the brass water bowl at the stand's foot + a little mat
    brass = M((214, 168, 82), metal=0.5, rough=0.35)
    made.append(box(coll, (2.0, 2.0, 0.6), (ox + 18.6, STAND_Y - 1.6, 0.3), brass, 0.2))
    made.append(box(coll, (1.6, 1.6, 0.1), (ox + 18.6, STAND_Y - 1.6, 0.56), M((110, 180, 236), emit=0.15), 0.02))
    made.append(box(coll, (3.2, 2.8, 0.08), (ox + 18.6, STAND_Y - 1.6, 0.04), M((196, 92, 92)), 0.02))
    return made


# ================================================================================ C: Cloud Fair Ring (forged rosette)
def emblem_c(coll, ox, c=0.25, zs=0.4):
    pal = {"V": (VIOLET,), "VD": (VIOLET_D,), "G": (GOLD, "metal"), "GD": (GOLD_D, "metal"), "GL": (GOLD_L, "metal"),
           "Rib": ((176, 116, 246),), "RibD": ((132, 80, 210),)}
    vx = Vox(pal, c, seed=31)
    R = 12.0
    rr = lambda x, y: math.hypot(x, y)

    def scallop(x, y):
        a = math.atan2(y, x)
        r = rr(x, y)
        edge = 6.7 + 0.8 * abs(math.cos(a * 8))
        return r <= edge
    # ribbon tails first (under the rosette), toward the fighter's side (-Y) with V-notched ends
    for sx in (-1, 1):
        def tail(x, y, sx=sx):
            u = (x - sx * 1.5) * math.cos(0.32 * sx) - (y + 0) * math.sin(0.32 * sx) * -1
            # a strip from the centre down-and-out, 2.6 wide, to y = -11.5
            cx = sx * (1.4 + (-y) * 0.32)
            if not (-11.6 <= y <= -4.0):
                return False
            w = abs(x - cx)
            notch = (y < -10.4) and (w < (y + 11.6) * 1.1 * -1 + 1.32)
            return w <= 1.3 and not (y < -10.4 and w < 1.32 - (y + 11.6) * 1.1)
        vx.flat(R, 0, tail, "Rib")
    vx.paint("RibD", lambda x, y, z: (x > 0) == (int(-y * 1.0) % 2 == 0), only={"Rib"})
    vx.flat(R, 0, scallop, "G")
    vx.flat(R, 1, lambda x, y: scallop(x, y) and rr(x, y) > 5.9, "G")
    vx.paint("GD", lambda x, y, z: z > c and rr(x, y) > 6.6 and (math.atan2(y, x) * 8 / math.pi) % 1.0 < 0.5, only={"G"})
    vx.flat(R, 1, lambda x, y: rr(x, y) <= 5.9, "V")
    vx.flat(R, 1, lambda x, y: 5.3 <= rr(x, y) <= 5.9, "VD")
    st = star_fn(5, 4.1, 1.9)
    vx.flat(R, 2, st, "G")
    vx.paint("GL", lambda x, y, z: z > 2 * c - 0.01 and x < -0.2, only={"G"})
    return vx.build(coll, "EmblemC", (ox, 0, FLOOR_Z), jitter=0.04, zscale=zs, shade_bottom=False)


def crowd_c(coll, ox, pose="idle", t=0.0):
    """cloud kids on their parents' shoulders, pennants, popcorn, a hand bell, a chalk scoreboard"""
    made = []
    big = [(0, (250, 250, 255)), (1, (255, 214, 228)), (2, (204, 228, 255)), (3, (226, 214, 255)),
           (4, (214, 244, 222)), (5, (255, 240, 210)), (6, (250, 250, 255))]
    kids = {0: ((255, 236, 200), "pennant"), 1: ((204, 228, 255), "popcorn"), 3: ((255, 214, 228), "pennant"),
            4: ((255, 250, 220), "popcorn"), 6: ((214, 244, 222), "pennant")}
    for si, col in big:
        base = seat(si, ox)
        parts = []
        lift = {"idle": 0.0, "hit": 0.0, "won": 0.4, "boss": 0.9}[pose]
        mood = {"idle": "smile", "hit": "o", "won": "wide", "boss": "o"}[pose]
        vx = cloud_vox(col, seed=si * 5 + 1, w=3.6, h=3.0)
        parts += vx.build(coll, "Big%d" % si, (0, 0, 0), jitter=0.03)
        parts += face(coll, (0, -1.22, 1.3), mood, w=1.0)
        up = {"idle": 0.15, "hit": 0.5, "won": 0.9, "boss": 0.6}[pose]
        bell = (si == 5)
        for side in (-1, 1):
            u = up if not (bell and side == 1) else (1.0 if pose in ("won", "boss") else 0.55)
            a, tip = arm(coll, (side * 1.55, 0, 1.2), side, u, tuple(int(c * 0.9) for c in col), 1.3, 0.6)
            parts.append(a)
            if bell and side == 1:
                brass = M((214, 168, 82), metal=0.5, rough=0.35)
                ring_ = 0.6 if pose in ("won", "boss") else 0.0
                parts.append(beam(coll, tip, tip + V((0.2, 0, 0.7)), 0.3, M((150, 104, 66)), 0.05))
                parts.append(box(coll, (0.9, 0.9, 0.9), tip + V((0.45, 0, 1.25)), brass, 0.2, rot=(0, ring_, 0)))
        if si in kids:
            kc, kp = kids[si]
            kparts = []
            kb = {"idle": 0.25 * abs(math.sin(TAU * (t + si * 0.3))), "hit": -1.6, "won": 1.2, "boss": 0.5}[pose]
            kvx = cloud_vox(kc, seed=si * 9 + 2, w=1.9, h=1.7, dpt=1.5, bumps=2)
            kparts += kvx.build(coll, "Kid%d" % si, (0, 0, 0), jitter=0.03)
            kparts += face(coll, (0, -0.77, 0.75), "wide" if pose in ("won", "hit") else "smile", w=0.55)
            kup = {"idle": 0.6, "hit": 0.2, "won": 1.0, "boss": 0.8}[pose]
            for side in (-1, 1):
                a, tip = arm(coll, (side * 0.85, 0, 0.7), side, kup, tuple(int(c * 0.9) for c in kc), 0.8, 0.35)
                kparts.append(a)
                if side == 1 and kp == "pennant":
                    kparts.append(beam(coll, tip, tip + V((0.1, 0, 2.2)), 0.12, M((150, 104, 66)), 0.02))
                    wav = 0.35 * math.sin(TAU * (t * 2 + si * 0.2)) if pose != "hit" else 0.0
                    kparts.append(box(coll, (1.4, 0.08, 0.8), tip + V((0.8, 0, 1.75)), M(VIOLET if si % 2 else GOLD), 0.03,
                                      rot=(0, 0, wav)))
                if side == -1 and kp == "popcorn":
                    tub = M((236, 72, 80))
                    kparts.append(box(coll, (0.8, 0.8, 0.9), tip + V((-0.1, -0.2, 0.3)), tub, 0.08))
                    for k in range(2):
                        kparts.append(box(coll, (0.18, 0.84, 0.9), tip + V((-0.3 + k * 0.4, -0.2, 0.3)), M((250, 250, 250)), 0.02))
                    kparts.append(box(coll, (0.85, 0.85, 0.3), tip + V((-0.1, -0.2, 0.85)), M((255, 244, 200)), 0.12))
                    if pose == "won":  # popcorn pops out
                        rng = random.Random(si)
                        for k in range(9):
                            kparts.append(box(coll, (0.28, 0.28, 0.28), tip + V((rng.uniform(-1.2, 1.0), rng.uniform(-1.0, 0.4), 1.2 + rng.uniform(0, 2.4))),
                                              M((255, 244, 200)), 0.08, rot=(rng.random(), rng.random(), 0)))
            # the kid rides on the shoulders, or hides behind the parent's head on a big hit
            parts.append(group(coll, "Kid_%d" % si, kparts, (0, 0.3 if pose != "hit" else 1.3, (2.6 + kb) if pose != "hit" else 1.5)))
        made.append(group(coll, "Fan_%d" % si, parts, base + V((0, 0, lift)), (0.12 if pose == "hit" else 0.0, 0, 0)))
    # bunting between two striped fair poles behind the stand
    pole_x = (ox - 16.0, ox + 16.0)
    py = STAND_Y + 7.6
    for k, px in enumerate(pole_x):
        for s in range(10):
            made.append(box(coll, (0.7, 0.7, 1.0), (px, py, 0.5 + s), M((236, 72, 80)) if s % 2 else M((250, 250, 250)), 0.05))
        made.append(box(coll, (1.1, 1.1, 0.6), (px, py, 10.3), M(GOLD, metal=0.4), 0.2))
    n = 12
    cols = [(236, 72, 80), (250, 200, 60), VIOLET, (120, 196, 236)]
    for k in range(n):
        s0, s1 = k / n, (k + 1) / n
        x0 = pole_x[0] + (pole_x[1] - pole_x[0]) * s0
        x1 = pole_x[0] + (pole_x[1] - pole_x[0]) * s1
        z0 = 9.6 - 1.8 * math.sin(math.pi * s0)
        z1 = 9.6 - 1.8 * math.sin(math.pi * s1)
        made.append(beam(coll, (x0, py, z0), (x1, py, z1), 0.1, M((240, 236, 226)), 0.02))
        fz = (z0 + z1) / 2
        flap = 0.25 * math.sin(TAU * (t + k * 0.11))
        for r in range(3):  # a stepped triangle flag
            w = 1.6 - r * 0.5
            made.append(box(coll, (w, 0.1, 0.4), ((x0 + x1) / 2, py - 0.05, fz - 0.3 - r * 0.4), M(cols[k % 4]), 0.02, rot=(flap * 0.2, 0, 0)))
    # the chalk scoreboard on an easel (round tallies: "|||| ||")
    sbx = ox + 19.0
    sby = STAND_Y + 1.0
    wood = M((150, 104, 66))
    made.append(beam(coll, (sbx - 1.4, sby + 0.6, 0), (sbx - 0.9, sby, 5.4), 0.3, wood, 0.05))
    made.append(beam(coll, (sbx + 1.4, sby + 0.6, 0), (sbx + 0.9, sby, 5.4), 0.3, wood, 0.05))
    made.append(beam(coll, (sbx, sby + 1.6, 0), (sbx, sby + 0.2, 5.0), 0.3, wood, 0.05))
    made.append(box(coll, (3.6, 0.3, 2.8), (sbx, sby - 0.15, 3.6), M((52, 70, 64)), 0.06))
    made.append(box(coll, (3.9, 0.35, 0.3), (sbx, sby - 0.15, 5.05), wood, 0.05))
    made.append(box(coll, (3.9, 0.35, 0.3), (sbx, sby - 0.15, 2.15), wood, 0.05))
    chalk = M((240, 240, 236), emit=0.1)
    tallies = 6 if pose != "won" else 7
    for k in range(tallies):
        if k == 4:
            made.append(box(coll, (1.6, 0.06, 0.16), (sbx - 0.9, sby - 0.32, 3.9), chalk, 0.0, rot=(0, 0.5, 0)))
            continue
        made.append(box(coll, (0.14, 0.06, 1.1), (sbx - 1.4 + k * 0.32 + (0.4 if k > 4 else 0), sby - 0.32, 3.9), chalk, 0.0))
    made.append(box(coll, (2.6, 0.06, 0.14), (sbx, sby - 0.32, 2.9), chalk, 0.0))
    # the popcorn cart wheel / sign could go here; keep it lean
    return made


# ================================================================================ stage, lights, cameras
def stage():
    sc = bpy.context.scene
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    sc.render.engine = "BLENDER_EEVEE"
    sc.eevee.taa_render_samples = SAMPLES
    try:
        sc.eevee.use_raytracing = True
    except Exception:
        pass
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = rgb(200, 220, 246)
    ramp.color_ramp.elements[1].color = rgb(110, 160, 230)
    ramp.color_ramp.elements[1].position = 0.45
    nt.links.new(tc.outputs["Normal"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.75
    coll = sc.collection
    for name, rot, energy, col in (("Sun", (0.75, 0.15, -0.7), 2.3, (1.0, 0.95, 0.86)),
                                   ("Fill", (1.2, 0.0, 2.5), 0.6, (0.75, 0.82, 1.0))):
        L = bpy.data.lights.new(name, "SUN")
        L.energy, L.color, L.angle = energy, col, 0.1
        ob = bpy.data.objects.new(name, L)
        ob.rotation_euler = rot
        coll.objects.link(ob)
    return coll


def clear_meshes():
    for ob in list(bpy.data.objects):
        if ob.type in ("MESH", "EMPTY", "CAMERA"):
            bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def shoot(path, cam_loc, target, lens=40, size=(1280, 960)):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = RES
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cd.clip_end = 1000
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = cam_loc
    cam.rotation_euler = (V(target) - V(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[pitch]", path, flush=True)


# the screenshot's angle: from the fighter's side-east, high, the crowd at the back right
MAIN = ((25.0, -21.0, 23.0), (0.0, 15.0, 1.0), 26)
CROWD = ((0.0, 24.0, 15.5), (0.0, 41.0, 3.4), 24)
TOP = ((0.0, -6.5, 30.0), (0.0, 0.0, 0.0), 40)
EMB_CLOSE = ((14.0, -16.0, 14.0), (0.0, 0.0, 0.0), 40)

EMBLEM = {"a": emblem_a, "b": emblem_b, "c": emblem_c}
CROWD_FN = {"a": crowd_a, "b": crowd_b, "c": crowd_c}


def build(key, coll, pose="idle", t=0.0):
    if key == "today":
        today(coll, 0.0)
        return
    ring(coll, 0.0, clean=True)
    EMBLEM[key](coll, 0.0)
    if key == "b":
        paw_trail(coll, 0.0)
    CROWD_FN[key](coll, 0.0, pose, t)
    player(coll, (-9.0, -6.5, FLOOR_Z), face=0.6)


coll = stage()
TMP = os.path.join(OUT, "_tmp")
os.makedirs(TMP, exist_ok=True)
shots = {}
for key in ("today", "a", "b", "c"):
    if not (ONLY & {key, "lineup"}):
        continue
    clear_meshes()
    build(key, coll)
    p = os.path.join(TMP, "%s_main.png" % key)
    shoot(p, *MAIN[:2], MAIN[2])
    shots.setdefault(key, {})["main"] = p
    if key in ONLY:
        for nm, (cl, tg, lens) in (("crowd", CROWD), ("emblem", TOP if key != "today" else EMB_CLOSE)):
            p = os.path.join(TMP, "%s_%s.png" % (key, nm))
            shoot(p, cl, tg, lens, size=(800, 600))
            shots[key][nm] = p

POSES = (("idle", 0.0), ("hit", 0.3), ("won", 0.5), ("boss", 0.75))
MOTION = []
for key in "abc":
    if not (ONLY & {"motion", "motion_" + key}):
        continue
    MOTION.append(key)
    for pose, t in POSES:
        clear_meshes()
        ring(coll, 0.0, clean=True)
        CROWD_FN[key](coll, 0.0, pose, t)
        shoot(os.path.join(TMP, "m_%s_%s.png" % (key, pose)), *CROWD[:2], CROWD[2], size=(800, 600))

if "bake" in ONLY:
    # do the three emblems survive the game's 0.5-stud bake? voxelise each at 0.5 and render top-down
    clear_meshes()
    for i, key in enumerate("abc"):
        ox = (i - 1) * 18.0
        EMBLEM[key](coll, ox, c=0.5, zs=0.2)
    shoot(os.path.join(TMP, "bake.png"), (0.0, -2.5, 66.0), (0.0, -2.0, 0.0), 35, size=(1200, 600))

# ================================================================================ sheets (PIL)
from PIL import Image, ImageDraw, ImageFont
try:
    FONT = ImageFont.truetype("arialbd.ttf", 30)
    SMALL = ImageFont.truetype("arialbd.ttf", 20)
except Exception:
    FONT = SMALL = ImageFont.load_default()


def tag(d, xy, text, f):
    x, y = xy
    w = d.textlength(text, font=f)
    sz = getattr(f, "size", 12)
    d.rounded_rectangle((x - 8, y - 6, x + w + 8, y + sz + 8), 8, fill=(20, 28, 48, 215))
    d.text((x, y), text, font=f, fill=(255, 255, 255))


def labelled(path, text, f=SMALL):
    im = Image.open(path).convert("RGBA")
    ov = Image.new("RGBA", im.size)
    tag(ImageDraw.Draw(ov), (14, 12), text, f)
    return Image.alpha_composite(im, ov)


TITLES = {"today": "TODAY  (the real arena_pocket bake)", "a": "A  Sky-Sailors' Ring", "b": "B  Grandpaws' Ring",
          "c": "C  Cloud Fair Ring"}
SIDE = {"today": ("crowd: static, no sound", "the baked emblem (the 'E')"),
        "a": ("crowd: retired weather clouds", "emblem: compass star (top view)"),
        "b": ("crowd: pet families", "emblem: star paw (top view)"),
        "c": ("crowd: cloud kids on shoulders", "emblem: forged rosette (top view)")}
for key, s in shots.items():
    if "main" not in s:
        continue
    main = labelled(s["main"], TITLES[key], FONT)
    if "crowd" in s and "emblem" in s:
        W, H = main.size
        sh = H // 2
        sw = int(sh * 4 / 3)
        sheet = Image.new("RGBA", (W + sw + 8, H), (20, 28, 48, 255))
        sheet.paste(main, (0, 0))
        c1 = labelled(s["crowd"], SIDE[key][0]).resize((sw, sh - 4), Image.LANCZOS)
        c2 = labelled(s["emblem"], SIDE[key][1]).resize((sw, sh - 4), Image.LANCZOS)
        sheet.paste(c1, (W + 8, 0))
        sheet.paste(c2, (W + 8, sh + 4))
        out = "today_render.png" if key == "today" else "option_%s.png" % key
        sheet.convert("RGB").save(os.path.join(OUT, out))
        print("[pitch] sheet", out, flush=True)
if "lineup" in ONLY and all(k in shots for k in ("today", "a", "b", "c")):
    ims = [labelled(shots[k]["main"], TITLES[k], FONT) for k in ("today", "a", "b", "c")]
    w, h = ims[0].size
    w2, h2 = w // 2, h // 2
    sheet = Image.new("RGBA", (w2 * 2 + 6, h2 * 2 + 6), (20, 28, 48, 255))
    for i, im in enumerate(ims):
        sheet.paste(im.resize((w2, h2), Image.LANCZOS), ((i % 2) * (w2 + 6), (i // 2) * (h2 + 6)))
    sheet.convert("RGB").save(os.path.join(OUT, "lineup.png"))
    print("[pitch] lineup", flush=True)
CUES = {
    "a": {"idle": "idle: breathing swell, rain drips  |  loop: wind + rigging creak",
          "hit": "big hit: the thunder captain flashes  |  'rumble-oooh'",
          "won": "round won: puff up, caps fly, bell  |  ship's bell + rain-patter applause",
          "boss": "boss round: darken, lean in, drizzle  |  low thunder roll"},
    "b": {"idle": "idle: pets sway, drummer taps  |  loop: soft mews + yips murmur",
          "hit": "big hit: paws over eyes  |  gasp 'awww'",
          "won": "round won: foam paws up, hop  |  cheer (random pitch per pet)",
          "boss": "boss round: stand, banner shakes  |  drum roll"},
    "c": {"idle": "idle: kids bounce, pennants wave  |  loop: soft fair organ",
          "hit": "big hit: kids hide behind parents  |  'oooh'",
          "won": "round won: popcorn, bell, tally +1  |  popcorn pops + hand bell",
          "boss": "boss round: all stand and stomp  |  stomp-stomp + party horn"},
}
for key in MOTION:
    fr = [os.path.join(TMP, "m_%s_%s.png" % (key, p)) for p, _ in POSES]
    if not all(os.path.isfile(f) for f in fr):
        continue
    ims = []
    for i, f in enumerate(fr):
        what, snd = CUES[key][POSES[i][0]].split("  |  ")
        im = labelled(f, "%d/4  %s" % (i + 1, what))
        ov = Image.new("RGBA", im.size)
        dd = ImageDraw.Draw(ov)
        tag(dd, (14, im.size[1] - 40), "sound: " + snd, SMALL)
        ims.append(Image.alpha_composite(im, ov))
    w, h = ims[0].size
    sheet = Image.new("RGBA", (w * 2 + 6, h * 2 + 6), (20, 28, 48, 255))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % 2) * (w + 6), (i // 2) * (h + 6)))
    sheet.convert("RGB").save(os.path.join(OUT, "motion_%s.png" % key))
    print("[pitch] motion", key, flush=True)
if os.path.isfile(os.path.join(TMP, "bake.png")):
    im = Image.open(os.path.join(TMP, "bake.png")).convert("RGBA")
    ov = Image.new("RGBA", im.size)
    d = ImageDraw.Draw(ov)
    tag(d, (14, 12), "the three emblems voxelised at the game's 0.5-stud bake: A / B / C", SMALL)
    Image.alpha_composite(im, ov).convert("RGB").save(os.path.join(OUT, "bake_check.png"))
print("[pitch] done", flush=True)
