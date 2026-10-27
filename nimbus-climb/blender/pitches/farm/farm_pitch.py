"""Berry Farm design pitch (bug #20 "the farm design bugs"): today's farm + three concept mock-ups, rendered in Blender.

    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe -I farm_pitch.py <out_dir> [--res 100] [--samples 32]
        [--only today,a,b,c,lineup,growth] [--kit <nimbus-climb/blender/kit>] [--level 30]

Writes
  today_render.png  the kit's own Lv 18 builds side by side: the Part build (HomeBuilder.BuildStationModel boxes), the
                    High key home_farm_18 and the Low key home_farm_18_low, all baked in memory from the game's code
  option_a/b/c.png  main 3/4 view at --level (default 30: every row planted) with a 5.3-stud R15 player on the buy pad,
                    a close-up of the shed + first bushes, and a growth strip (Lv 5 / 18 / 30 / 40)
  lineup.png        today's High key + A + B + C at Lv 18 (the player's level in the screenshot), same camera each
Coordinates: 1 Blender unit = 1 stud, Z up, the game's PM mapping (roblox x -> -x, y -> z, z -> y): the field's front
row faces -Y, the shed sits at +X (x 15.6) like the Part build, plants are placed with HomeBuilder's own formulas
(Farm.ROWS, Farm.age, bush sizes). Read-only for game code: the kit is imported only to rebuild today's keys in memory.
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector as V, Matrix

ARGS = sys.argv[1:]
OUT = os.path.abspath(ARGS[0] if ARGS and not ARGS[0].startswith("--") else ".")


def arg(name, default):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default


RES = int(arg("--res", 100))
SAMPLES = int(arg("--samples", 32))
ONLY = set(arg("--only", "today,a,b,c,lineup,growth").split(","))
LEVEL = int(arg("--level", 30))
KIT = os.path.abspath(arg("--kit", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "kit")))
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # the project path has Hebrew letters
except Exception:
    pass
os.makedirs(OUT, exist_ok=True)
TRIS = {}


def lin(c):
    return (max(0.0, c) / 255.0) ** 2.2


def hsh(*a):
    x = 0
    for i, v in enumerate(a):
        x ^= (int(v) * (73856093, 19349663, 83492791, 2654435761, 97)[i % 5]) & 0xFFFFFFFF
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    return (x % 10007) / 10007.0


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
    b.inputs["Roughness"].default_value = 0.66
    if kind == "metal":
        b.inputs["Metallic"].default_value = 0.5
        b.inputs["Roughness"].default_value = 0.35
    elif kind == "glass":
        b.inputs["Roughness"].default_value = 0.08
        b.inputs["Alpha"].default_value = 0.38
        try:
            m.use_transparent_shadow = True
        except Exception:
            pass
    elif kind == "glow":
        nt.links.new(vc.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 2.0
    _mats[kind] = m
    return m


def flat_mat(name, col, rough=0.6, metal=0.0, emit=0.0):
    key = (name, col)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (lin(col[0]), lin(col[1]), lin(col[2]), 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (lin(col[0]), lin(col[1]), lin(col[2]), 1.0)
        b.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


# ================================================================================ voxels (0.25 stud, like the kit)
OPAQUE = ("solid", "metal", "glow")


class Vox:
    """cells (i, j, k) -> (rgb, kind); one mesh per kind, per-face colours with a little per-cell jitter"""

    def __init__(self, c=0.25, seed=0):
        self.c, self.v, self.seed = c, {}, seed

    def _r(self, lo, hi):
        return range(math.floor(lo / self.c + 1e-6), math.ceil(hi / self.c - 1e-6))

    def put(self, x, y, z, col, kind="solid"):
        c = self.c
        self.v[(math.floor(x / c), math.floor(y / c), math.floor(z / c))] = (col, kind)

    def fillf(self, xr, yr, zr, fn):
        """fn(x, y, z) -> (rgb, kind) | rgb | None per cell centre"""
        c = self.c
        for i in self._r(*xr):
            x = (i + 0.5) * c
            for j in self._r(*yr):
                y = (j + 0.5) * c
                for k in self._r(*zr):
                    r = fn(x, y, (k + 0.5) * c)
                    if r is None:
                        continue
                    if r == "clear":
                        self.v.pop((i, j, k), None)
                        continue
                    self.v[(i, j, k)] = r if isinstance(r[0], tuple) else (r, "solid")

    def box(self, lo, hi, col, kind="solid"):
        self.fillf((lo[0], hi[0]), (lo[1], hi[1]), (lo[2], hi[2]), lambda x, y, z: (col, kind))

    def ell(self, ctr, rad, fn):
        cx, cy, cz = ctr
        rx, ry, rz = rad
        self.fillf((cx - rx, cx + rx), (cy - ry, cy + ry), (cz - rz, cz + rz),
                   lambda x, y, z: fn(x, y, z) if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1.0 else None)

    def line(self, a, b, col, kind="solid", w=0.25):
        a, b = V(a), V(b)
        n = max(1, int((b - a).length / (self.c * 0.5)))
        for s in range(n + 1):
            p = a.lerp(b, s / n)
            if w <= self.c:
                self.put(p.x, p.y, p.z, col, kind)
            else:
                h = w / 2
                self.box((p.x - h, p.y - h, p.z - h), (p.x + h, p.y + h, p.z + h), col, kind)

    def build(self, coll, name, loc=(0, 0, 0), jitter=0.05):
        c = self.c
        groups = {}
        for cell, (col, kind) in self.v.items():
            groups.setdefault(kind, []).append(cell)
        made = []
        dirs = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
        tris = 0
        for kind, cells in groups.items():
            bm = bmesh.new()
            colay = bm.loops.layers.float_color.new("Col")
            vmap = {}

            def vert(p):
                vv = vmap.get(p)
                if vv is None:
                    vv = vmap[p] = bm.verts.new((p[0] * c, p[1] * c, p[2] * c))
                return vv
            for (i, j, k) in cells:
                base, _ = self.v[(i, j, k)]
                f = 1.0 + (hsh(i, j, k, self.seed) - 0.5) * 2 * jitter
                for d in dirs:
                    nb = self.v.get((i + d[0], j + d[1], k + d[2]))
                    if nb is not None and (nb[1] == kind or (kind != "glass" and nb[1] in OPAQUE) or
                                           (kind == "glass" and nb[1] in OPAQUE)):
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
                    # baked shading like Voxel.Shade: light tops, darker undersides and sides
                    sh = 1.06 if d[2] > 0 else (0.74 if d[2] < 0 else (0.92 if d[0] != 0 else 0.97))
                    cc = tuple(lin(min(255, base[q] * f * sh)) for q in range(3)) + (1.0,)
                    for lp in face.loops:
                        lp[colay] = cc
            tris += 2 * len(bm.faces)
            me = bpy.data.meshes.new(name + "_" + kind)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(kind_mat(kind))
            ob = bpy.data.objects.new(name + "_" + kind, me)
            ob.location = loc
            coll.objects.link(ob)
            made.append(ob)
        return made, tris


def shade(c, f):
    return tuple(max(0, min(255, int(round(v * f)))) for v in c)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


# ================================================================================ the game's planting rules
# HomeBuilder.lua Art.Farm (:828-905): rows (roblox z -> blender y), RED 10 / BLUE 12 / VINES 15, x mirrored (PM)
ROWS = [(-2.25, 0.75), (0.0, 1.15), (2.25, 1.55)]
X0, X1 = -10.8, 13.2
SPAN = (X1 - X0) - 1.2
SHED_X, SHED_Y = 15.6, 0.6
TREE_X = -15.7


def age(level, at, span=6):
    return max(0.0, min(1.0, (level - at) / span))


def plants(level):
    """(row, blender x, size, berries, g) per plant at `level`, with the game's own formulas"""
    out = []
    for i in range(1, min(level, 10) + 1):
        g = age(level, i)
        out.append((0, -(X0 + 0.6 + (i - 0.5) * SPAN / 10), 1.45 + 0.5 * g, 2 if g >= 0.5 else 1, g, i))
    for i in range(1, min(level - 10, 12) + 1):
        g = age(level, 10 + i)
        out.append((1, -(X0 + 0.6 + (i - 0.5) * SPAN / 12), 1.35 + 0.45 * g, 2 if g >= 0.5 else 1, g, 20 + i))
    return out


def vines(level):
    out = []
    for j in range(1, min(level - 22, 15) + 1):
        g = age(level, 22 + j, 5)
        h = (1.7 if j % 2 == 0 else 2.2) + 1.0 * g
        out.append((-(X0 + 0.7 + (j - 0.5) * ((X1 - X0) - 1.4) / 15), h, g, j))
    return out


# ================================================================================ shared shapes
def bush(vx, x, row, d, n, g, seed, P, style):
    """a berry bush as a stepped voxel dome with leaf clumps and hanging berry clusters (never a cube)"""
    y0, top = ROWS[row]
    rng = random.Random(seed * 31 + row)
    r = d * 0.55
    cz = top + r * 0.78
    leafD, leafL = P["leafD"], P["leafL"]
    if row == 1:
        leafD, leafL = shade(leafD, 0.92), shade(leafL, 0.94)
    berry, berry2 = (P["red"], P["red2"]) if row == 0 else (P["blue"], P["blue2"])
    # a short woody stem into the soil
    vx.box((x - 0.125, y0 - 0.125, top - 0.25), (x + 0.125, y0 + 0.125, cz), P["stem"])

    def leaf(xx, yy, zz):
        t = (zz - (cz - r * 0.6)) / (r * 1.4)
        c = mix(leafD, leafL, max(0.0, min(1.0, t)))
        if hsh(int(xx * 4), int(yy * 4), int(zz * 4), seed) < 0.12:
            c = shade(c, 1.12)
        return c
    if style == "manicured":
        # clipped topiary: three stacked, tidy rounded slabs
        for k, (fr, fz) in enumerate(((1.0, 0.55), (0.82, 0.5), (0.55, 0.4))):
            zc = cz - r * 0.35 + k * r * 0.48
            vx.ell((x, y0, zc), (r * fr, r * fr * 0.9, r * fz), leaf)
    else:
        vx.ell((x, y0, cz), (r, r * 0.88, r * 0.82), leaf)
        nclump = 4 if style == "wild" else 3
        for q in range(nclump):
            a = rng.uniform(0, math.tau)
            rr = r * rng.uniform(0.45, 0.6)
            ox, oy = math.cos(a) * r * 0.6, math.sin(a) * r * 0.5
            oz = rng.uniform(-0.1, 0.45) * r
            if style == "wild" and q == 0:
                oy, oz = -r * 0.7, -r * 0.35  # a heavy clump drooping over the front edge
            vx.ell((x + ox, y0 + oy, cz + oz), (rr, rr, rr * 0.85), leaf)
    # berries: clusters of 2-3 berries hanging under the canopy edge on the yard side (front, -Y)
    clusters = n + (1 if g >= 0.9 else 0)
    spots = [(-0.45, -0.1), (0.4, 0.15), (0.0, -0.35), (-0.15, 0.3)]
    for k in range(clusters):
        sx, sz = spots[k % len(spots)]
        bx = x + sx * r
        by = y0 - r * 0.88 + 0.05
        bz = cz + sz * r
        col = berry if k % 2 == 0 else berry2
        vx.put(bx, by + 0.12, bz + 0.3, P["stem"])  # the little stalk it hangs from
        for (ux, uz) in ((0, 0), (0.25, -0.25), (-0.25, -0.25)) if k % 2 == 0 else ((0, 0), (0.25, -0.25)):
            vx.box((bx + ux - 0.125, by - 0.125, bz + uz - 0.125), (bx + ux + 0.125, by + 0.125, bz + uz + 0.125), col)
        vx.put(bx, by - 0.1, bz + 0.05, shade(col, 1.45))  # the highlight


def player(coll, loc, face=0.0):
    """a 5.3-stud R15-proportioned blocky player (legs 2.0, torso 2.0, head 1.2)"""
    def bx(size, at, m, bev=0.06):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bev, min(size) * 0.45), segments=1, affect="EDGES")
        me = bpy.data.meshes.new("pl")
        bm.to_mesh(me)
        bm.free()
        me.materials.append(m)
        ob = bpy.data.objects.new("pl", me)
        ob.location = at
        coll.objects.link(ob)
        return ob
    skin, shirt = flat_mat("Skin", (234, 196, 160)), flat_mat("Shirt", (90, 140, 210))
    pants, shoe = flat_mat("Pants", (60, 66, 90)), flat_mat("Shoe", (40, 40, 48))
    hair, eye = flat_mat("Hair", (90, 60, 40)), flat_mat("Eye", (30, 30, 40))
    parts = []
    for sx in (-0.5, 0.5):
        parts += [bx((0.95, 1.0, 0.35), (sx, -0.05, 0.175), shoe), bx((0.9, 0.9, 0.85), (sx, 0, 0.775), pants),
                  bx((0.95, 0.95, 0.85), (sx, 0, 1.6), pants)]
    parts += [bx((2.0, 1.0, 0.45), (0, 0, 2.225), pants), bx((2.0, 1.0, 1.55), (0, 0, 3.225), shirt, 0.1)]
    for sx in (-1.5, 1.5):
        parts += [bx((0.95, 0.95, 0.85), (sx, 0, 3.55), shirt), bx((0.9, 0.9, 0.8), (sx, 0, 2.75), skin),
                  bx((0.85, 0.85, 0.4), (sx, 0, 2.15), skin)]
    parts += [bx((1.2, 1.2, 1.2), (0, 0, 4.7), skin, 0.3), bx((1.26, 1.26, 0.35), (0, 0.04, 5.15), hair, 0.12)]
    for sx in (-0.22, 0.22):
        parts.append(bx((0.14, 0.05, 0.22), (sx, -0.61, 4.78), eye, 0.0))
    root = bpy.data.objects.new("Player", None)
    coll.objects.link(root)
    for p in parts:
        p.parent = root
    root.location = loc
    root.rotation_euler = (0, 0, face)
    return [root] + parts


def crate(vx, x, y, z, rot, berry, P, wood=None):
    wood = wood or P["crate"]
    h = 0.55
    vx.fillf((x - 0.6, x + 0.6), (y - 0.6, y + 0.6), (z, z + 1.1),
             lambda xx, yy, zz: (shade(wood, 0.8) if (abs(xx - x) > 0.45 and abs(yy - y) > 0.45) or zz > z + 0.85
                                 else (shade(wood, 0.95 if int((zz - z) / 0.25) % 2 else 1.05))))
    vx.ell((x, y, z + 1.1), (0.5, 0.5, 0.25), lambda xx, yy, zz: berry if hsh(int(xx * 8), int(yy * 8), 3) > 0.2 else shade(berry, 1.4))


def starberry_tree(vx, level, x, y, z0, P, planter=None):
    if level < 30:
        return
    if level < 38:
        vx.box((x - 0.125, y - 0.125, z0), (x + 0.125, y + 0.125, z0 + 1.6), P["stem"])
        vx.ell((x, y, z0 + 2.0), (0.75, 0.7, 0.6), lambda *a: P["teal"])
        return
    t = level - 37
    th = 2.6 + 0.7 * t
    cr = 3.0 + 0.55 * t
    vx.fillf((x - 0.6, x + 0.6), (y - 0.6, y + 0.6), (z0, z0 + th),
             lambda xx, yy, zz: shade(P["trunk"], 0.9 + 0.2 * hsh(int(zz * 4), 7)) if abs(xx - x) + abs(yy - y) < 0.75 + 0.3 * max(0, 1 - (zz - z0)) else None)
    cz = z0 + th + cr * 0.3
    tl = lambda xx, yy, zz: mix(P["teal"], shade(P["teal"], 1.25), max(0, min(1, (zz - cz + cr * 0.3) / cr)))
    vx.ell((x, y, cz), (cr * 0.5, cr * 0.45, cr * 0.42), tl)
    vx.ell((x - cr * 0.32, y - 0.3, cz - cr * 0.22), (cr * 0.33, cr * 0.33, cr * 0.28), tl)
    vx.ell((x + cr * 0.32, y + 0.3, cz - cr * 0.18), (cr * 0.31, cr * 0.31, cr * 0.27), tl)
    for k, (ox, oz, oy) in enumerate(((-0.35, -0.05, -0.5), (0.3, 0.2, -0.48), (0.0, 0.42, -0.36), (0.42, -0.25, -0.3))[:t + 1]):
        sx, sz, sy = x + ox * cr, cz + oz * cr, y + oy * cr
        for d in ((0, 0, 0), (0.25, 0, 0), (-0.25, 0, 0), (0, 0, 0.25), (0, 0, -0.25)):
            vx.put(sx + d[0], sy - 0.1, sz + d[2], P["star"], "glow")


def ground(coll):
    gm = bpy.data.materials.new("Lawn")
    gm.use_nodes = True
    nt = gm.node_tree
    ck = nt.nodes.new("ShaderNodeTexChecker")
    ck.inputs["Scale"].default_value = 80.0
    ck.inputs["Color1"].default_value = (lin(112), lin(200), lin(90), 1)
    ck.inputs["Color2"].default_value = (lin(104), lin(192), lin(84), 1)
    nt.links.new(ck.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, 0))
    g = bpy.context.object
    g.data.materials.append(gm)
    return g


def pad_and_path(vx, P):
    # the buy pad 7.5 studs in front of the field centre (TycoonCatalog Press1 Pad)
    vx.fillf((-2.4, 2.4), (-9.9, -5.1), (0.0, 0.25),
             lambda x, y, z: (222, 228, 236) if math.hypot(x, y + 7.5) < 2.2 else None)
    vx.fillf((-2.4, 2.4), (-9.9, -5.1), (0.25, 0.5),
             lambda x, y, z: ((120, 220, 140), "glow") if 1.75 < math.hypot(x, y + 7.5) < 2.0 else None)


# ================================================================================ A: Heritage Sky-Croft
PA = {"leafD": (58, 128, 58), "leafL": (122, 190, 82), "red": (214, 44, 70), "red2": (240, 92, 104),
      "blue": (64, 98, 214), "blue2": (112, 152, 240), "stem": (104, 76, 50), "crate": (214, 168, 116),
      "teal": (70, 182, 168), "star": (255, 222, 96), "trunk": (128, 92, 60), "gold": (255, 206, 60)}
A_STONE, A_STONE2, A_MORTAR, A_MOSS = (184, 178, 166), (160, 154, 146), (122, 116, 108), (104, 156, 72)
A_SOIL, A_SOIL2 = (110, 74, 48), (88, 58, 38)
A_RED, A_RED2, A_WHITE, A_ROOF, A_ROOF2 = (190, 64, 62), (168, 52, 52), (244, 238, 226), (92, 112, 156), (76, 94, 136)
A_WOOD, A_WOODD, A_STRAW = (150, 104, 66), (110, 76, 50), (226, 192, 104)


def stone_wall(vx, x0, x1, y0, y1, z0, z1, seed, moss=0.35):
    def f(x, y, z):
        course = int(math.floor((z - z0) / 0.5))
        off = 0.55 * (course % 2) + 0.2 * hsh(course, seed)
        L = 1.1
        sidx = int(math.floor((x + off) / L))
        u = (x + off) - sidx * L
        if u < 0.25 or (z - z0) - course * 0.5 < 0.1:
            return A_MORTAR
        c = A_STONE if hsh(sidx, course, seed) > 0.4 else A_STONE2
        c = shade(c, 0.92 + 0.16 * hsh(sidx, course, seed, 2))
        if z > z1 - 0.26 and hsh(int(x * 4), int(y * 4), seed) < moss:
            return A_MOSS
        return c
    vx.fillf((x0, x1), (y0, y1), (z0, z1), f)


def croft(vx, level, ox=0.0):
    P = PA
    x_lo, x_hi = -(X1) - 0.3, -(X0) + 0.3  # -13.5 .. 11.1
    # stone footing under the whole field
    stone_wall(vx, x_lo, x_hi, -3.6, 3.6, 0.0, 0.25, 1, moss=0.0)
    # soil steps: front row low, back high; unplanted rows are grass with a few tufts
    for r, (y0, top) in enumerate(ROWS):
        planted = r == 0 or (r == 1 and level > 10) or (r == 2 and level > 22)

        def soil(x, y, z, r=r, top=top, planted=planted):
            if z > top - 0.26:
                if not planted:
                    return (116, 190, 90) if hsh(int(x * 4), int(y * 4), r) > 0.2 else (134, 206, 100)
                return A_SOIL2 if int(x * 4) % 4 == 0 else (A_SOIL if hsh(int(x * 4), int(y * 4)) > 0.1 else (150, 140, 128))
            return A_SOIL2
        vx.fillf((x_lo + 0.5, x_hi - 0.5), (y0 - 1.0, y0 + 1.0), (0.25, top), soil)
    # dry-stone terrace walls (front 0.85, steps 1.25 / 1.65, back 1.65) and the two ends
    for (yy, h, s) in ((-3.35, 0.85, 2), (-1.12, 1.25, 3), (1.12, 1.65, 4), (3.35, 1.65, 5)):
        stone_wall(vx, x_lo, x_hi, yy - 0.25, yy + 0.25, 0.25, h + 0.25, s)
    for xx in (x_lo + 0.25, x_hi - 0.25):
        stone_wall(vx, xx - 0.25, xx + 0.25, -3.6, 3.6, 0.25, 1.9, 6)
    # plants
    for (row, x, d, n, g, seed) in plants(level):
        bush(vx, x, row, d, n, g, seed, P, "wild")
    vs = vines(level)
    if vs:
        y = ROWS[2][0] + 0.45
        top = ROWS[2][1]
        for k in range(6):  # bent branch posts, tied with rope
            px = x_hi - 0.6 - k * (x_hi - x_lo - 1.2) / 5
            for s in range(15):
                z = top + s * 0.25
                vx.put(px + 0.12 * math.sin(s * 0.9 + k), y, z, shade(A_WOOD, 0.9 + 0.15 * hsh(s, k)))
            vx.put(px, y - 0.25, top + 3.35, (222, 206, 160))
        for s in range(int((x_hi - x_lo - 1.0) / 0.25)):
            xx = x_lo + 0.5 + s * 0.25
            vx.put(xx, y, top + 3.4 + 0.1 * math.sin(xx * 0.7), A_WOOD)
        for (vxp, h, g, j) in vs:
            for s in range(int(h / 0.25)):
                z = top + s * 0.25
                wob = 0.25 * math.sin(s * 0.8 + j)
                vx.put(vxp + wob, y - 0.25, z, mix(P["leafD"], P["leafL"], s * 0.25 / h))
                if s % 2 == 0:
                    vx.put(vxp + wob + (0.25 if s % 4 else -0.25), y - 0.25, z, P["leafL"])
            gz = top + h * 0.62
            vx.box((vxp - 0.25, y - 0.75, gz - 0.25), (vxp + 0.25, y - 0.5, gz + 0.25), P["gold"], "metal")
    # the mound (mossy stones) and the Starberry tree
    vx.fillf((TREE_X - 2.2, TREE_X + 2.2), (-2.2, 2.2), (0, 0.6),
             lambda x, y, z: (A_MOSS if z > 0.35 else A_STONE2) if math.hypot(x - TREE_X, y) < 2.2 - (z * 0.8) else None)
    starberry_tree(vx, level, TREE_X, 0.0, 0.6, P)
    croft_barn(vx, level)


def croft_barn(vx, level):
    bx, by = SHED_X, SHED_Y
    hw, hd, wall = 2.4, 2.7, 3.4
    z0 = 0.5
    stone_wall(vx, bx - hw - 0.25, bx + hw + 0.25, by - hd - 0.25, by + hd + 0.25, 0.0, z0, 9, moss=0.15)

    def walls(x, y, z):
        if abs(x - bx) > hw - 0.3 and abs(y - by) > hd - 0.3:
            return A_WHITE  # corner trim
        if z > z0 + wall - 0.25:
            return A_WHITE  # eave trim
        u = (x if abs(y - by) > hd - 0.3 else y)
        board = int(math.floor(u / 0.5))
        c = A_RED if board % 2 else A_RED2
        return shade(c, 0.95 + 0.1 * hsh(board, int(z * 2)))
    vx.fillf((bx - hw, bx + hw), (by - hd, by + hd), (z0, z0 + wall), walls)
    vx.fillf((bx - hw + 0.25, bx + hw - 0.25), (by - hd + 0.25, by + hd - 0.25), (z0 + 0.25, z0 + wall - 0.25), lambda *a: "clear")
    fy = by - hd  # front face
    # the door (brown planks, white X brace), the lantern, the loft door with hay
    dw, dh = 1.0, 2.5

    def door(x, y, z):
        u, v = (x - bx) / dw, (z - z0) / dh
        if abs(u) > 0.88 or v > 0.92:
            return A_WOODD
        if abs(abs(u) - abs(v * 2 - 1)) < 0.2:
            return A_WHITE
        return shade(A_WOOD, 0.9 if int((x - bx) * 2) % 2 else 1.0)
    vx.fillf((bx - dw, bx + dw), (fy - 0.25, fy), (z0, z0 + dh), door)
    vx.box((bx - 1.4 - 0.25, fy - 0.5, z0 + 2.55), (bx - 1.4 + 0.25, fy - 0.25, z0 + 2.8), (46, 52, 72))
    vx.box((bx - 1.4 - 0.25, fy - 0.5, z0 + 2.05), (bx - 1.4 + 0.25, fy - 0.25, z0 + 2.55), (255, 214, 120), "glow")
    # gable roof, ridge front-to-back, sagging a little in the middle (old timbers)
    rise, ov = 2.0, 0.45
    ztop = z0 + wall

    def roof_z(x, y):
        t = 1 - abs(x - bx) / (hw + ov)
        sag = 0.3 * math.sin(math.pi * max(0, min(1, (y - (by - hd - ov)) / (2 * (hd + ov))))) * t
        return ztop - 0.25 + rise * t - sag

    def roof(x, y, z):
        zr = roof_z(x, y)
        if zr - 0.5 <= z <= zr:
            row = int(math.floor(abs(x - bx) / 0.5))
            c = A_ROOF if row % 2 else A_ROOF2
            if hsh(row, int(y * 2), 3) < 0.08:
                c = shade(c, 0.82)  # a patched shingle
            return shade(c, 0.96 + 0.08 * hsh(row, int(y * 4)))
        return None
    vx.fillf((bx - hw - ov, bx + hw + ov), (by - hd - ov, by + hd + ov), (ztop - 0.5, ztop + rise + 0.5), roof)
    vx.fillf((bx - 0.375, bx + 0.375), (by - hd - ov, by + hd + ov), (ztop + rise - 0.8, ztop + rise + 0.5),
             lambda x, y, z: A_WOODD if roof_z(x, y) - 0.15 < z < roof_z(x, y) + 0.26 else None)
    # gable ends (red boards) with the loft door and hay poking out
    for gy in (by - hd, by + hd - 0.25):
        vx.fillf((bx - hw, bx + hw), (gy, gy + 0.25), (ztop, ztop + rise),
                 lambda x, y, z: (A_RED if int(x * 2) % 2 else A_RED2) if z < roof_z(x, y) - 0.4 else None)
    vx.fillf((bx - 0.5, bx + 0.5), (fy - 0.25, fy), (ztop + 0.2, ztop + 1.1),
             lambda x, y, z: (A_WOODD if abs(x - bx) > 0.3 or z > ztop + 0.9 else (A_STRAW if hsh(int(x * 4), int(z * 4)) > 0.25 else (196, 160, 80))))
    for k in range(5):
        vx.put(bx - 0.25 + k * 0.125, fy - 0.4, ztop + 0.3 + 0.1 * (k % 2), A_STRAW)
    # sign board (white, the "Berry Farm Lv N" BillboardGui sits on it)
    vx.box((bx - 1.4, fy - 0.35, ztop - 0.7), (bx + 1.4, fy - 0.1, ztop - 0.15), A_WHITE)
    # swallows' nest under the front-left eave
    vx.ell((bx - hw - 0.1, fy - 0.15, ztop - 0.15), (0.35, 0.3, 0.25), lambda *a: (150, 120, 84))
    # crates (red / blue / gold by level), the straw sun hat on top, a step stool and a watering can
    cx = SHED_X - 3.35
    crate(vx, cx, -2.6, 0.0, 0, PA["red"], PA)
    if level >= 11:
        crate(vx, cx, -1.3, 0.0, 0, PA["blue"], PA)
    if level >= 23:
        crate(vx, cx, -1.95, 1.1, 0, PA["gold"], PA)
    hz = 2.45 if level >= 23 else 1.35
    hy = -1.95 if level >= 23 else -2.6
    vx.fillf((cx - 0.75, cx + 0.75), (hy - 0.75, hy + 0.75), (hz, hz + 0.6),
             lambda x, y, z: (A_STRAW if z < hz + 0.2 and math.hypot(x - cx, y - hy) < 0.75 else
                              ((200, 60, 60) if z < hz + 0.35 and math.hypot(x - cx, y - hy) < 0.45 else
                               (A_STRAW if math.hypot(x - cx, y - hy) < 0.4 else None))))
    vx.box((cx + 0.9, -3.6, 0.0), (cx + 1.6, -2.9, 0.75), shade(A_WOOD, 1.1))
    wx = -(X1) + 2.0
    vx.box((wx - 0.4, -3.6, 1.1), (wx + 0.35, -3.1, 1.6), (120, 150, 140), "metal")
    vx.line((wx + 0.35, -3.35, 1.5), (wx + 0.9, -3.35, 1.85), (120, 150, 140), "metal")
    vx.line((wx - 0.35, -3.35, 1.65), (wx + 0.25, -3.35, 1.65), (100, 126, 118), "metal")


# ================================================================================ B: Sky-Sailor's Allotment
PB = {"leafD": (56, 130, 60), "leafL": (110, 196, 80), "red": (228, 60, 89), "red2": (246, 110, 120),
      "blue": (60, 102, 206), "blue2": (110, 156, 240), "stem": (110, 80, 52), "crate": (206, 160, 106),
      "teal": (70, 182, 168), "star": (255, 222, 96), "trunk": (128, 92, 60), "gold": (255, 206, 60)}
B_HULL, B_HULL2, B_NAVY, B_SAIL, B_BRASS = (193, 138, 93), (170, 118, 78), (70, 130, 180), (242, 240, 230), (230, 197, 92)
B_DECK, B_DECK2, B_ANTI, B_ROPE = (214, 178, 128), (196, 160, 112), (196, 70, 64), (222, 204, 158)


def trough(vx, y0, top, x_lo, x_hi, seed, planted):
    """a planked lifeboat hull as a raised bed: rounded ends, wood strakes, navy gunwale, brass rivets"""
    half = 1.07
    xm = (x_lo + x_hi) / 2
    L = (x_hi - x_lo) / 2

    def inside(x, y, shrink=0.0):
        ex = max(0.0, abs(x - xm) - (L - 1.4))
        return (ex / (1.4 - shrink)) ** 2 + (abs(y - y0) / (half - shrink)) ** 2 <= 1.0

    def f(x, y, z):
        if not inside(x, y):
            return None
        shell = not inside(x, y, 0.3)
        if not shell:
            if z > top - 0.26:
                if not planted:
                    return (116, 190, 90) if hsh(int(x * 4), int(y * 4), seed) > 0.2 else (134, 206, 100)
                return (104, 70, 46) if int(x * 4) % 4 else (84, 56, 38)
            return (84, 56, 38)
        if z > top - 0.26:
            return B_NAVY
        if z > top - 0.51:
            if int((x + y) * 4) % 8 == 0:
                return B_BRASS, "metal"
            return B_SAIL
        strake = int(math.floor(z / 0.25))
        return shade(B_HULL if strake % 2 else B_HULL2, 0.95 + 0.1 * hsh(strake, int(x), seed))
    vx.fillf((x_lo, x_hi), (y0 - half, y0 + half), (0.25, top), f)


def allotment(vx, level, ox=0.0):
    P = PB
    x_lo, x_hi = -(X1) - 0.3, -(X0) + 0.3
    # a deck of planks under the whole station (the old ship's deck boards)
    vx.fillf((x_lo - 0.5, SHED_X + 3.0), (-3.6, 3.6), (0.0, 0.25),
             lambda x, y, z: (B_DECK2 if int(math.floor(y / 0.5)) % 2 else B_DECK) if (x + 3 * int(math.floor(y / 0.5))) % 4.0 > 0.25 else shade(B_DECK2, 0.8))
    for r, (y0, top) in enumerate(ROWS):
        planted = r == 0 or (r == 1 and level > 10) or (r == 2 and level > 22)
        trough(vx, y0, top + 0.1, x_lo, x_hi, r, planted)
    for (row, x, d, n, g, seed) in plants(level):
        bush(vx, x, row, d, n, g, seed, P, "round")
    vs = vines(level)
    top = ROWS[2][1] + 0.1
    y = ROWS[2][0] + 0.35
    if vs:
        # oars stuck blade-up in the back hull as posts, a rope between them; the old mast in the middle with rigging
        for k in range(6):
            px = x_hi - 0.8 - k * (x_hi - x_lo - 1.6) / 5
            vx.box((px - 0.125, y - 0.125, top), (px + 0.125, y + 0.125, top + 2.6), B_HULL2)
            vx.box((px - 0.25, y - 0.125, top + 2.6), (px + 0.25, y + 0.125, top + 3.6), B_NAVY)
        vx.line((x_lo + 0.8, y, top + 3.0), (x_hi - 0.8, y, top + 3.0), B_ROPE)
        mx = (x_lo + x_hi) / 2
        vx.box((mx - 0.25, y + 0.25, top), (mx + 0.25, y + 0.75, top + 7.5), B_HULL)
        vx.box((mx - 2.0, y + 0.25, top + 6.25), (mx + 2.0, y + 0.5, top + 6.5), B_HULL2)
        vx.box((mx - 0.5, y + 0.0, top + 7.5), (mx + 0.5, y + 1.0, top + 7.75), B_BRASS, "metal")
        for ex in (x_lo + 0.8, x_hi - 0.8):
            vx.line((mx, y + 0.5, top + 6.3), (ex, y, top + 3.0), B_ROPE)
        # the ship's bell hangs from the yard arm (it calls the pets to dinner)
        vx.ell((mx + 1.6, y - 0.1, top + 5.6), (0.35, 0.35, 0.45), lambda *a: (B_BRASS, "metal"))
        vx.line((mx + 1.6, y + 0.3, top + 6.25), (mx + 1.6, y, top + 6.0), B_ROPE)
        for (vxp, h, g, j) in vs:
            for s in range(int(h / 0.25)):
                z = top + s * 0.25
                wob = 0.25 * math.sin(s * 0.8 + j)
                vx.put(vxp + wob, y - 0.25, z, mix(P["leafD"], P["leafL"], s * 0.25 / h))
                if s % 2 == 0:
                    vx.put(vxp + wob + (0.25 if s % 4 else -0.25), y - 0.25, z, P["leafL"])
            gz = top + h * 0.62
            vx.box((vxp - 0.25, y - 0.75, gz - 0.25), (vxp + 0.25, y - 0.5, gz + 0.25), P["gold"], "metal")
    # the Starberry tree grows in the old crow's nest tub
    tx = TREE_X
    vx.fillf((tx - 1.8, tx + 1.8), (-1.8, 1.8), (0.0, 1.25),
             lambda x, y, z: ((B_NAVY if z > 1.0 else (B_BRASS, "metal") if 0.5 < z < 0.75 else B_HULL2)
                              if 1.45 < math.hypot(x - tx, y) < 1.8 else ((96, 64, 42) if math.hypot(x - tx, y) <= 1.45 and z < 1.0 else None)))
    starberry_tree(vx, level, tx, 0.0, 1.0, P)
    sailor_shed(vx, level)


def sailor_shed(vx, level):
    bx, by = SHED_X, SHED_Y
    hw, hd, wall = 2.4, 2.7, 3.0
    z0 = 0.25

    def walls(x, y, z):
        if abs(x - bx) > hw - 0.5 and abs(y - by) > hd - 0.5:
            return B_NAVY
        if z < z0 + 0.5:
            return B_NAVY
        row = int(math.floor((z - z0) / 0.5))
        return shade(B_SAIL, 0.93 + 0.07 * (row % 2) + 0.04 * hsh(row, int(x + y)))
    vx.fillf((bx - hw, bx + hw), (by - hd, by + hd), (z0, z0 + wall), walls)
    vx.fillf((bx - hw + 0.25, bx + hw - 0.25), (by - hd + 0.25, by + hd - 0.25), (z0 + 0.25, z0 + wall), lambda *a: "clear")
    fy = by - hd
    # door (navy, brass handle) and portholes (brass rings, blue glass)
    vx.fillf((bx - 0.9, bx + 0.9), (fy - 0.25, fy), (z0, z0 + 2.4),
             lambda x, y, z: B_HULL2 if abs(x - bx) > 0.7 or z > z0 + 2.2 else shade(B_NAVY, 0.9 if int(x * 4) % 2 else 1.0))
    vx.put(bx + 0.5, fy - 0.3, z0 + 1.2, B_BRASS, "metal")
    for (px, py, face) in ((bx + 1.75, fy, "y"), (bx + hw, by + 0.4, "x"), (bx + hw, by - 1.4, "x")):
        pz = z0 + 1.9
        if face == "y":
            vx.fillf((px - 0.6, px + 0.6), (py - 0.25, py), (pz - 0.6, pz + 0.6),
                     lambda x, y, z: ((B_BRASS, "metal") if 0.3 < math.hypot(x - px, z - pz) < 0.6 else ((150, 210, 240), "glass") if math.hypot(x - px, z - pz) <= 0.3 else None))
        else:
            vx.fillf((px - 0.25, px + 0.25), (py - 0.6, py + 0.6), (pz - 0.6, pz + 0.6),
                     lambda x, y, z: ((B_BRASS, "metal") if 0.3 < math.hypot(y - py, z - pz) < 0.6 else ((150, 210, 240), "glass") if math.hypot(y - py, z - pz) <= 0.3 else None))
    # the roof: the ship's lifeboat turned upside down: red bottom paint on top, white waterline, wood strakes, keel ridge
    ztop = z0 + wall
    R = hw + 0.6

    def roof(x, y, z):
        t = abs(x - bx) / R
        if t > 1:
            return None
        endf = max(0.0, (abs(y - by) - (hd - 0.4)) / 1.2)
        zr = ztop - 0.25 + 2.1 * math.sqrt(max(0.0, 1 - t * t)) * (1 - 0.5 * endf * endf)
        if zr - 0.5 <= z <= zr:
            depth = (zr - ztop) / 2.1
            if depth > 0.62:
                return shade(B_ANTI, 0.95 + 0.1 * hsh(int(x * 2), int(y)))
            if depth > 0.5:
                return B_SAIL
            strake = int(math.floor(t * 8))
            return B_HULL if strake % 2 else B_HULL2
        return None
    vx.fillf((bx - R, bx + R), (by - hd - 0.6, by + hd + 0.6), (ztop - 0.5, ztop + 2.6), roof)
    vx.box((bx - 0.25, by - hd - 0.6, ztop + 1.85), (bx + 0.25, by + hd + 0.6, ztop + 2.1), B_HULL2)
    # gable infill under the hull (white boards) at front and back
    for gy in (fy, by + hd - 0.25):
        vx.fillf((bx - hw, bx + hw), (gy, gy + 0.25), (ztop, ztop + 2.0),
                 lambda x, y, z: B_SAIL if z < ztop - 0.3 + 2.0 * math.sqrt(max(0, 1 - (abs(x - bx) / R) ** 2)) else None)
    # sign board, propeller weathervane on the keel
    vx.box((bx - 1.4, fy - 0.35, ztop + 0.05), (bx + 1.4, fy - 0.1, ztop + 0.6), B_SAIL)
    vx.box((bx - 0.125, by - 0.125, ztop + 2.1), (bx + 0.125, by + 0.125, ztop + 3.2), B_HULL2)
    vx.box((bx - 0.25, by - 0.5, ztop + 3.0), (bx + 0.25, by - 0.25, ztop + 3.3), B_BRASS, "metal")
    for a in (0.3, 0.3 + math.pi / 2, 0.3 + math.pi, 0.3 + 1.5 * math.pi):
        vx.line((bx, by - 0.6, ztop + 3.15), (bx + 1.0 * math.cos(a), by - 0.6, ztop + 3.15 + 1.0 * math.sin(a)), B_NAVY, "solid")
    # anchor (painted, bright) and a coiled mooring rope by the front-right corner
    ax, ay = bx + hw + 0.5, fy + 0.6
    vx.box((ax - 0.125, ay - 0.125, 0.25), (ax + 0.125, ay + 0.125, 2.5), (60, 70, 96), "metal")
    vx.box((ax - 0.5, ay - 0.125, 2.2), (ax + 0.5, ay + 0.125, 2.45), (60, 70, 96), "metal")
    vx.fillf((ax - 0.9, ax + 0.9), (ay - 0.125, ay + 0.125), (0.25, 1.2),
             lambda x, y, z: ((60, 70, 96), "metal") if 0.65 < math.hypot(x - ax, z - 1.15) < 0.9 and z < 1.0 else None)
    vx.fillf((ax - 0.9, ax + 0.9), (ay - 2.1, ay - 0.6), (0.25, 0.75),
             lambda x, y, z: shade(B_ROPE, 0.9 + 0.2 * (int(z * 4) % 2)) if 0.25 < math.hypot(x - ax, y - (ay - 1.35)) < 0.7 else None)
    # crates (sea chests)
    cx = SHED_X - 3.35
    crate(vx, cx, -2.6, 0.25, 0, PB["red"], PB, (196, 150, 98))
    if level >= 11:
        crate(vx, cx, -1.3, 0.25, 0, PB["blue"], PB, (196, 150, 98))
    if level >= 23:
        crate(vx, cx, -1.95, 1.35, 0, PB["gold"], PB, (196, 150, 98))
    vx.fillf((cx - 0.6, cx + 0.6), (-0.6, 0.6), (0.25, 1.1),
             lambda x, y, z: B_NAVY if abs(z - 0.75) < 0.12 or abs(x - cx) > 0.45 else (B_HULL if z < 1.0 else B_HULL2))


# ================================================================================ C: Cloud-Catcher Glasshouse
PC = {"leafD": (50, 132, 74), "leafL": (100, 190, 104), "red": (214, 48, 74), "red2": (240, 96, 110),
      "blue": (45, 85, 200), "blue2": (96, 140, 236), "stem": (100, 74, 50), "crate": (222, 214, 196),
      "teal": (70, 182, 168), "star": (255, 222, 96), "trunk": (128, 92, 60), "gold": (255, 206, 60)}
C_WHITE, C_BRASS, C_LOAM, C_GLASS, C_BRICK, C_GRAVEL = (248, 248, 246), (212, 175, 70), (78, 54, 40), (175, 236, 232), (232, 228, 220), (196, 192, 184)


def planter(vx, y0, top, x_lo, x_hi, planted, seed):
    def f(x, y, z):
        edge = abs(y - y0) > 0.82 or x < x_lo + 0.25 or x > x_hi - 0.25
        if edge:
            if z > top - 0.13:
                return (C_BRASS, "metal")
            if (x < x_lo + 0.5 or x > x_hi - 0.5) and abs(y - y0) > 0.82:
                return (C_BRASS, "metal") if z > top - 0.4 else C_WHITE
            board = int(math.floor((z - 0.25) / 0.5))
            return shade(C_WHITE, 0.94 + 0.06 * (board % 2))
        if z > top - 0.26:
            if not planted:
                return (116, 190, 90) if hsh(int(x * 4), int(y * 4), seed) > 0.2 else (134, 206, 100)
            return C_LOAM if hsh(int(x * 4), int(y * 4), seed) > 0.08 else (120, 160, 210)
        return C_LOAM
    vx.fillf((x_lo, x_hi), (y0 - 1.0, y0 + 1.0), (0.25, top), f)


def glasshouse_farm(vx, level, ox=0.0):
    P = PC
    x_lo, x_hi = -(X1) - 0.3, -(X0) + 0.3
    # a raked gravel base, three separate white raised planters with brass caps
    vx.fillf((x_lo - 0.5, x_hi + 0.5), (-3.6, 3.6), (0.0, 0.25),
             lambda x, y, z: shade(C_GRAVEL, 0.92 + 0.14 * hsh(int(x * 4), int(y * 4), 9)))
    for r, (y0, top) in enumerate(ROWS):
        planted = r == 0 or (r == 1 and level > 10) or (r == 2 and level > 22)
        planter(vx, y0, top + 0.1, x_lo, x_hi, planted, r)
    for (row, x, d, n, g, seed) in plants(level):
        bush(vx, x, row, d, n, g, seed, P, "manicured")
    # a brass rain gauge staked in the front row
    gx = -(X1) + 1.0
    vx.box((gx - 0.125, -2.9, ROWS[0][1]), (gx + 0.125, -2.65, ROWS[0][1] + 1.6), C_BRASS, "metal")
    vx.box((gx - 0.25, -3.0, ROWS[0][1] + 0.9), (gx + 0.25, -2.55, ROWS[0][1] + 1.9), (190, 230, 250), "glass")
    vs = vines(level)
    top = ROWS[2][1] + 0.1
    y = ROWS[2][0] + 0.2
    if vs:
        # five brass hoops over the back planter; vines climb them
        n = 5
        for k in range(n):
            cx = x_lo + 1.2 + (k + 0.5) * (x_hi - x_lo - 2.4) / n
            rr = (x_hi - x_lo - 2.4) / n / 2 - 0.1
            for s in range(41):
                a = math.pi * s / 40
                vx.put(cx + rr * math.cos(a), y, top + 1.6 + rr * 0.9 * math.sin(a), C_BRASS, "metal")
            for sx in (cx - rr, cx + rr):
                vx.box((sx - 0.125, y - 0.125, top), (sx + 0.125, y + 0.125, top + 1.6), C_BRASS, "metal")
        for (vxp, h, g, j) in vs:
            for s in range(int(h / 0.25)):
                z = top + s * 0.25
                vx.put(vxp, y - 0.25, z, mix(P["leafD"], P["leafL"], s * 0.25 / h))
                if s % 3 == 0:
                    vx.box((vxp - 0.25, y - 0.5, z), (vxp + 0.25, y - 0.25, z + 0.25), P["leafL"])
            gz = top + h * 0.62
            vx.box((vxp - 0.25, y - 0.75, gz - 0.25), (vxp + 0.25, y - 0.5, gz + 0.25), P["gold"], "metal")
    # the Starberry tree in a round white planter with a brass band
    tx = TREE_X
    vx.fillf((tx - 1.8, tx + 1.8), (-1.8, 1.8), (0.0, 1.0),
             lambda x, y, z: ((C_BRASS, "metal") if z > 0.75 else C_WHITE) if 1.4 < math.hypot(x - tx, y) < 1.75 else (C_LOAM if math.hypot(x - tx, y) <= 1.4 and z < 0.75 else None))
    starberry_tree(vx, level, tx, 0.0, 0.75, P)
    glasshouse(vx, level)


def glasshouse(vx, level):
    bx, by = SHED_X, SHED_Y
    hw, hd = 2.4, 2.7
    knee, wall, rise = 0.9, 3.2, 2.3
    z0 = 0.25
    fy = by - hd

    def frame(x, y, z):
        ex = abs(x - bx) > hw - 0.25
        ey = abs(y - by) > hd - 0.25
        if not (ex or ey):
            return "clear"
        if z < z0 + knee:
            course = int(math.floor((z - z0) / 0.25))
            return shade(C_BRICK, 0.9 if (int((x + y) * 2) + course) % 4 == 0 else 1.0)
        u = (y - by) if ex else (x - bx)
        if abs(u % 1.2) < 0.25 or z > z0 + wall - 0.25 or z < z0 + knee + 0.25 or (ex and ey):
            return C_WHITE
        return (C_GLASS, "glass")
    vx.fillf((bx - hw, bx + hw), (by - hd, by + hd), (z0, z0 + wall), frame)
    # glass gable roof with white glazing bars (ridge front to back)
    ztop = z0 + wall

    def roof(x, y, z):
        t = 1 - abs(x - bx) / (hw + 0.25)
        zr = ztop + rise * t
        if zr - 0.3 <= z <= zr:
            if abs((y - by) % 1.2) < 0.25 or t < 0.08 or abs(y - by) > hd - 0.25 or t > 0.93:
                return C_WHITE
            return (C_GLASS, "glass")
        return None
    vx.fillf((bx - hw - 0.25, bx + hw + 0.25), (by - hd, by + hd), (ztop - 0.3, ztop + rise + 0.25), roof)
    for gy in (fy, by + hd - 0.25):
        vx.fillf((bx - hw, bx + hw), (gy, gy + 0.25), (ztop, ztop + rise),
                 lambda x, y, z: (C_WHITE if abs(x - bx) < 0.2 or z < ztop + 0.25 else (C_GLASS, "glass")) if z < ztop + rise * (1 - abs(x - bx) / (hw + 0.25)) - 0.3 else None)
    # the door (white frame, glass), a rolled canvas awning above it
    vx.fillf((bx - 0.9, bx + 0.9), (fy - 0.25, fy), (z0, z0 + 2.6),
             lambda x, y, z: C_WHITE if abs(x - bx) > 0.65 or z > z0 + 2.35 or abs(x - bx) < 0.12 or z < z0 + 0.4 else (C_GLASS, "glass"))
    vx.put(bx + 0.4, fy - 0.3, z0 + 1.3, C_BRASS, "metal")
    for k in range(int(2.4 / 0.25)):
        x = bx - 1.2 + k * 0.25
        vx.box((x, fy - 0.75, ztop - 0.25), (x + 0.25, fy - 0.25, ztop + 0.25), (240, 232, 210) if (k // 2) % 2 else (96, 160, 140))
    vx.box((bx - 1.3, fy - 0.85, ztop - 0.05), (bx + 1.3, fy - 0.75, ztop + 0.05), (150, 120, 80))
    # sign board on the knee wall above the door frame? it sits under the awning
    vx.box((bx - 1.4, fy - 0.35, ztop + 0.3), (bx + 1.4, fy - 0.1, ztop + 0.8), C_WHITE)
    # inside: potting shelf with seedling pots, visible through the glass
    vx.box((bx - hw + 0.25, by + hd - 1.0, z0 + 1.2), (bx + hw - 0.25, by + hd - 0.25, z0 + 1.4), (176, 136, 96))
    for k in range(7):
        px = bx - hw + 0.6 + k * 0.62
        vx.box((px - 0.2, by + hd - 0.8, z0 + 1.4), (px + 0.2, by + hd - 0.45, z0 + 1.8), (196, 106, 70))
        vx.put(px, by + hd - 0.6, z0 + 1.9, PC["leafL"])
    # the cloud-catcher on the ridge: a brass hoop net with a little cloud caught in it, a gutter to the rain barrel
    rz = ztop + rise
    for s in range(33):
        a = math.tau * s / 32
        vx.put(bx + 1.3 * math.cos(a), by + 1.0, rz + 1.6 + 1.3 * math.sin(a), C_BRASS, "metal")
    vx.box((bx - 0.125, by + 0.875, rz), (bx + 0.125, by + 1.125, rz + 0.4), C_BRASS, "metal")
    for gx in (-0.75, 0.0, 0.75):
        vx.line((bx + gx, by + 1.0, rz + 0.55), (bx + gx, by + 1.0, rz + 2.65), (226, 214, 180))
    for gz in (-0.75, 0.0, 0.75):
        vx.line((bx - 1.05, by + 1.0, rz + 1.6 + gz), (bx + 1.05, by + 1.0, rz + 1.6 + gz), (226, 214, 180))
    cloud = lambda x, y, z: (250, 252, 255) if z > rz + 1.6 else (226, 234, 248)
    vx.ell((bx + 0.2, by + 0.75, rz + 1.6), (0.7, 0.35, 0.45), cloud)
    vx.ell((bx - 0.45, by + 0.75, rz + 1.45), (0.45, 0.3, 0.35), cloud)
    gxp = bx + hw + 0.4
    vx.line((bx + hw + 0.25, by - 1.5, ztop + 0.0), (gxp, by - 1.5, ztop - 0.1), C_BRASS, "metal")
    vx.box((gxp - 0.125, by - 1.625, 1.35), (gxp + 0.125, by - 1.375, ztop), C_BRASS, "metal")
    # rain barrel: staves + brass hoops, water at the top
    bxr, byr = gxp + 0.2, by - 1.5
    vx.fillf((bxr - 0.85, bxr + 0.85), (byr - 0.85, byr + 0.85), (0.0, 1.4),
             lambda x, y, z: (((C_BRASS, "metal") if abs(z - 0.35) < 0.12 or abs(z - 1.05) < 0.12 else shade((150, 104, 66), 0.9 + 0.2 * (int(math.atan2(y - byr, x - bxr) * 4) % 2)))
                              if 0.55 < math.hypot(x - bxr, y - byr) < 0.85 else (((110, 170, 220), "glass") if math.hypot(x - bxr, y - byr) <= 0.55 and z > 1.1 else None)))
    # crates (painted white), a dented watering can on the front planter edge
    cx = SHED_X - 3.35
    crate(vx, cx, -2.6, 0.25, 0, PC["red"], PC)
    if level >= 11:
        crate(vx, cx, -1.3, 0.25, 0, PC["blue"], PC)
    if level >= 23:
        crate(vx, cx, -1.95, 1.35, 0, PC["gold"], PC)


# ================================================================================ scene
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
    sc.view_settings.view_transform = "AgX"
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (lin(196), lin(226), lin(255), 1)
    ramp.color_ramp.elements[1].color = (lin(92), lin(158), lin(238), 1)
    ramp.color_ramp.elements[1].position = 0.45
    nt.links.new(tc.outputs["Normal"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    coll = sc.collection
    ground(coll)
    for name, rot, energy, col in (("Sun", (0.78, 0.12, -0.55), 3.6, (1.0, 0.95, 0.86)),
                                   ("Fill", (1.2, 0.0, 2.6), 0.9, (0.75, 0.82, 1.0))):
        L = bpy.data.lights.new(name, "SUN")
        L.energy, L.color, L.angle = energy, col, 0.12
        ob = bpy.data.objects.new(name, L)
        ob.rotation_euler = rot
        coll.objects.link(ob)
    return coll


def shoot(path, cam_loc, target, lens=35, size=(1280, 720)):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = RES
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cd.clip_end = 2000
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = cam_loc
    cam.rotation_euler = (V(target) - V(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    print("[pitch]", path, flush=True)


BUILD = {"a": croft, "b": allotment, "c": glasshouse_farm}
NAMES = {"a": "A  Heritage Sky-Croft", "b": "B  Sky-Sailor's Allotment", "c": "C  Cloud-Catcher Glasshouse"}


def make_farm(coll, key, level, ox, with_player=True):
    vx = Vox(0.25, seed=hash(key) % 97)
    BUILD[key](vx, level)
    pad_and_path(vx, PA)
    made, tris = vx.build(coll, "farm_%s_%d" % (key, level), loc=(ox, 0, 0))
    if with_player:
        made += player(coll, (ox + 0.0, -7.5, 0.5), face=math.pi)
    return made, tris


def clear(objs):
    for o in objs:
        try:
            bpy.data.objects.remove(o, do_unlink=True)
        except Exception:
            pass


KIT_STATE = {}


def kit_today(coll, level, which, ox):
    """the game's own Lv N Berry Farm: 'parts' = HomeBuilder's Part build boxes, 'high' / 'low' = the kit's bake"""
    sys.path.insert(0, KIT)
    sys.dont_write_bytecode = True
    import numpy as np
    import props
    from props import home as H
    from nvox import blend as Bl
    PM = np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])
    made = []
    if which == "parts":
        st = H.station("Press1", level)
        pm = {}
        for b in H.parse_boxes(st["Boxes"]):
            R = PM @ b["R"] @ PM
            M = Matrix(((R[0][0], R[0][1], R[0][2], 0), (R[1][0], R[1][1], R[1][2], 0), (R[2][0], R[2][1], R[2][2], 0), (0, 0, 0, 1)))
            s = b["size"]
            p = PM @ b["pos"]
            me = bpy.data.meshes.new("pb")
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bm.to_mesh(me)
            bm.free()
            col = b["rgb"]
            if col not in pm:
                pm[col] = flat_mat("PB%d_%d_%d" % col, col, 0.7, emit=1.5 if b["mat"] == "Neon" else 0.0)
            me.materials.append(pm[col])
            ob = bpy.data.objects.new("pb_" + b["name"], me)
            ob.matrix_world = Matrix.Translation(V((p[0] + ox, p[1], p[2]))) @ M @ Matrix.Diagonal((s[0], s[2], s[1], 1))
            coll.objects.link(ob)
            made.append(ob)
        return made
    if "reg" not in KIT_STATE:
        KIT_STATE["reg"] = props.load_all()
    reg = KIT_STATE["reg"]
    args = {"station": "Press1", "level": level}
    key = "home_farm_%d" % level
    if which == "low":
        args.update({"vs": 0.5, "detail": 1})
        key += "_low"
    e = {"key": key, "prop": "home_station", "args": args, "budget": "stationBig"}
    m = reg["home_station"](e, props.PropKit())
    obs = Bl.make_objects(m, None, collection=coll)
    for o in obs:
        o.location = (ox, 0, 0)
        TRIS[key] = len(o.data.polygons) * 2
    return obs


def kit_ground(coll, ox):
    vx = Vox(0.25)
    pad_and_path(vx, PA)
    made, _ = vx.build(coll, "kitground", loc=(ox, 0, 0))
    return made + player(coll, (ox, -7.5, 0.5), face=math.pi)


MAIN_CAM = ((-13.0, -25.0, 15.5), (0.5, 0.5, 1.8), 27)
CLOSE_CAM = ((24.0, -14.0, 7.5), (12.5, -0.5, 2.6), 34)
GROW_CAM = ((1.0, -33.0, 13.0), (0.5, 0.0, 2.2), 28)

coll = stage()

if "today" in ONLY:
    for which in ("parts", "high", "low"):
        objs = kit_today(coll, 18, which, 0.0) + kit_ground(coll, 0.0)
        shoot(os.path.join(OUT, "_t_%s.png" % which), *MAIN_CAM[:2], MAIN_CAM[2], size=(1280, 720))
        clear(objs)

for key in "abc":
    if key not in ONLY:
        continue
    objs, tris = make_farm(coll, key, LEVEL, 0.0)
    TRIS["%s_L%d" % (key, LEVEL)] = tris
    shoot(os.path.join(OUT, "_o_%s_main.png" % key), *MAIN_CAM[:2], MAIN_CAM[2], size=(1280, 720))
    shoot(os.path.join(OUT, "_o_%s_close.png" % key), *CLOSE_CAM[:2], CLOSE_CAM[2], size=(640, 400))
    clear(objs)
    if "growth" in ONLY:
        for lv in (5, 18, 30, 40):
            objs, tris = make_farm(coll, key, lv, 0.0, with_player=True)
            TRIS["%s_L%d" % (key, lv)] = tris
            shoot(os.path.join(OUT, "_g_%s_%d.png" % (key, lv)), *GROW_CAM[:2], GROW_CAM[2], size=(640, 360))
            clear(objs)

if "lineup" in ONLY:
    objs = kit_today(coll, 18, "high", 0.0) + kit_ground(coll, 0.0)
    shoot(os.path.join(OUT, "_l_today.png"), *MAIN_CAM[:2], MAIN_CAM[2], size=(800, 450))
    clear(objs)
    for key in "abc":
        objs, _ = make_farm(coll, key, 18, 0.0)
        shoot(os.path.join(OUT, "_l_%s.png" % key), *MAIN_CAM[:2], MAIN_CAM[2], size=(800, 450))
        clear(objs)

print("[pitch] tris", TRIS, flush=True)

# ================================================================================ composites (PIL ships with the bpy env)
from PIL import Image, ImageDraw, ImageFont
try:
    font = ImageFont.truetype("arialbd.ttf", 26)
    small = ImageFont.truetype("arialbd.ttf", 18)
except Exception:
    font = small = ImageFont.load_default()


def tag(d, xy, text, f):
    x, y = xy
    w = d.textlength(text, font=f)
    sz = getattr(f, "size", 12)
    d.rounded_rectangle((x - 8, y - 6, x + w + 8, y + sz + 8), 8, fill=(20, 28, 48, 215))
    d.text((x, y), text, font=f, fill=(255, 255, 255))


def labelled(path, text, f=font):
    im = Image.open(path).convert("RGBA")
    ov = Image.new("RGBA", im.size)
    tag(ImageDraw.Draw(ov), (16, 12), text, f)
    return Image.alpha_composite(im, ov)


def p(name):
    return os.path.join(OUT, name)


if all(os.path.isfile(p("_t_%s.png" % w)) for w in ("parts", "high", "low")):
    a = labelled(p("_t_parts.png"), "Lv 18 Part build (HomeBuilder Art.Farm): what shows without the mesh")
    b = labelled(p("_t_high.png"), "Lv 18 mesh home_farm_18 (High, 0.25 voxels), rebuilt by the kit", small)
    c = labelled(p("_t_low.png"), "Lv 18 mesh home_farm_18_low (plot LOD, 0.5 voxels)", small)
    W, H = a.size
    sheet = Image.new("RGBA", (W, H + H // 2 + 6), (20, 28, 48, 255))
    sheet.paste(a, (0, 0))
    sheet.paste(b.resize((W // 2 - 3, H // 2)), (0, H + 6))
    sheet.paste(c.resize((W // 2 - 3, H // 2)), (W // 2 + 3, H + 6))
    sheet.convert("RGB").save(p("today_render.png"))
    for w in ("parts", "high", "low"):
        os.remove(p("_t_%s.png" % w))

for key in "abc":
    if not os.path.isfile(p("_o_%s_main.png" % key)):
        continue
    main = labelled(p("_o_%s_main.png" % key), "%s   (Lv %d, player 5.3 studs on the buy pad)" % (NAMES[key], LEVEL))
    close = labelled(p("_o_%s_close.png" % key), "close-up: the shed and the first bushes", small)
    W, H = main.size
    sheet = Image.new("RGBA", (W, H + 400 + 6), (20, 28, 48, 255))
    sheet.paste(main, (0, 0))
    sheet.paste(close, (0, H + 6))
    gs = [p("_g_%s_%d.png" % (key, lv)) for lv in (5, 18, 30, 40)]
    if all(os.path.isfile(g) for g in gs):
        for i, (g, lv) in enumerate(zip(gs, (5, 18, 30, 40))):
            im = labelled(g, "Lv %d" % lv, small).resize((317, 197))
            sheet.paste(im, (646 + (i % 2) * 320, H + 6 + (i // 2) * 203))
            os.remove(g)
    sheet.convert("RGB").save(p("option_%s.png" % key))
    os.remove(p("_o_%s_main.png" % key))
    os.remove(p("_o_%s_close.png" % key))

ls = [p("_l_%s.png" % k) for k in ("today", "a", "b", "c")]
if all(os.path.isfile(x) for x in ls):
    names = ("TODAY (the mesh as baked, Lv 18)", NAMES["a"], NAMES["b"], NAMES["c"])
    ims = [labelled(x, n) for x, n in zip(ls, names)]
    w, h = ims[0].size
    sheet = Image.new("RGBA", (w * 2 + 6, h * 2 + 6), (20, 28, 48, 255))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % 2) * (w + 6), (i // 2) * (h + 6)))
    sheet.convert("RGB").save(p("lineup.png"))
    for x in ls:
        os.remove(x)
print("[pitch] done", flush=True)
