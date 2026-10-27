"""Lobby fountain / waterfall design pitch (bug #13): three concept mock-ups + today's fountain, rendered in Blender.

    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe -I waterfall_pitch.py <out_dir> [--res 100] [--samples 32]
        [--only today,a,b,c,lineup,motion] [--kit <nimbus-climb/blender/kit>]

Writes today_render.png (the kit's real prop_fountain + prop_fountain_water), option_a/b/c.png (3/4 view, 5.3-stud
R15-proportioned player for scale), lineup.png (today + A + B + C), motion_a/b/c.png (4-frame contact sheets of the
water animation) and lineup/motion labels via PIL. 1 Blender unit = 1 stud, Z up. Read-only for game code: the kit is
imported to build today's meshes in memory only (nothing is exported or written into the repo).
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector as V

ARGS = sys.argv[1:]
OUT = ARGS[0] if ARGS and not ARGS[0].startswith("--") else "."


def arg(name, default):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default


RES = int(arg("--res", 100))
SAMPLES = int(arg("--samples", 32))
ONLY = set(arg("--only", "today,a,b,c,lineup,motion").split(","))
KIT = arg("--kit", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "kit"))
TAU = math.tau
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # the project path has Hebrew letters
except Exception:
    pass
os.makedirs(OUT, exist_ok=True)


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


# ================================================================================ materials
_mats = {}


def kind_mat(kind):
    """vertex-coloured materials per surface kind (the game: SmoothPlastic + baked shading, Glass water, Neon)"""
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
        b.inputs["Metallic"].default_value = 0.55
        b.inputs["Roughness"].default_value = 0.35
    elif kind == "water":
        b.inputs["Roughness"].default_value = 0.22
        b.inputs["Alpha"].default_value = 0.62
        nt.links.new(vc.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 0.15
    elif kind == "foam":
        b.inputs["Alpha"].default_value = 0.85
        b.inputs["Roughness"].default_value = 0.4
    elif kind == "glow":
        nt.links.new(vc.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 1.6
    if kind in ("water", "foam"):
        try:
            m.use_transparent_shadow = True
        except Exception:
            pass
    _mats[kind] = m
    return m


def flat_mat(name, col, rough=0.6, metal=0.0, alpha=1.0, emit=0.0):
    key = (name, col, rough, metal, alpha, emit)
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
    try:
        m.use_transparent_shadow = alpha < 1.0
    except Exception:
        pass
    _mats[key] = m
    return m


SCROLL = []  # (mapping node, studs per cycle): the falling-water texture offset, moved per motion frame


def sheet_mat(name, deep, light, alpha=0.78, scale=1.4):
    """falling-water sheet: wobbly foam bands along the fall (UV v = studs along the fall) scrolled by phase"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.wave_type = "BANDS"
    wv.bands_direction = "Y"
    wv.inputs["Scale"].default_value = scale
    wv.inputs["Distortion"].default_value = 5.0
    wv.inputs["Detail"].default_value = 2.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.38
    ramp.color_ramp.elements[0].color = rgb(*deep)
    ramp.color_ramp.elements[1].position = 0.72
    ramp.color_ramp.elements[1].color = rgb(*light)
    nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], wv.inputs["Vector"])
    nt.links.new(wv.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = 0.25
    b.inputs["Roughness"].default_value = 0.15
    b.inputs["Alpha"].default_value = alpha
    try:
        m.use_transparent_shadow = True
    except Exception:
        pass
    SCROLL.append((mp, 2.0))
    return m


# ================================================================================ voxels
class Vox:
    """a voxel sculpt: cells (i, j, k) -> palette key; built as one mesh per surface kind with per-face colours"""

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

    def box(self, lo, hi, key):
        self.fill((lo[0], hi[0]), (lo[1], hi[1]), (lo[2], hi[2]), lambda x, y, z: True, key)

    def ring(self, cx, cy, r0, r1, z0, z1, key, oct=False):
        def d(x, y):
            dx, dy = abs(x - cx), abs(y - cy)
            return max(dx, dy, (dx + dy) / 1.38) if oct else math.hypot(dx, dy)
        self.fill((cx - r1 - 1, cx + r1 + 1), (cy - r1 - 1, cy + r1 + 1), (z0, z1), lambda x, y, z: r0 <= d(x, y) <= r1, key)

    def disc(self, cx, cy, r, z0, z1, key, oct=False):
        self.ring(cx, cy, -1, r, z0, z1, key, oct)

    def ell(self, ctr, rad, key):
        cx, cy, cz = ctr
        rx, ry, rz = rad
        self.fill((cx - rx, cx + rx), (cy - ry, cy + ry), (cz - rz, cz + rz),
                  lambda x, y, z: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1.0, key)

    def cone(self, cx, cy, z0, z1, r0, r1, key, thick=None):
        def f(x, y, z):
            t = (z - z0) / (z1 - z0)
            r = r0 + (r1 - r0) * t
            d = math.hypot(x - cx, y - cy)
            return d <= r and (thick is None or d >= r - thick)
        R = max(r0, r1)
        self.fill((cx - R, cx + R), (cy - R, cy + R), (z0, z1), f, key)

    def paint(self, key, fn, only=None, prob=1.0, seed=1):
        c = self.c
        for (i, j, k), kk in list(self.v.items()):
            if only and kk not in only:
                continue
            if fn((i + 0.5) * c, (j + 0.5) * c, (k + 0.5) * c) and hsh(i, j, k, seed) < prob:
                self.v[(i, j, k)] = key

    def build(self, coll, name, loc=(0, 0, 0), jitter=0.06):
        c = self.c
        groups = {}
        for cell, key in self.v.items():
            groups.setdefault(self.pal[key][1] if len(self.pal[key]) > 1 else "solid", []).append(cell)
        opaque = lambda kk: (self.pal[kk][1] if len(self.pal[kk]) > 1 else "solid") in ("solid", "metal", "glow")
        made = []
        dirs = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
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
                selfop = kind in ("solid", "metal", "glow")
                base = self.pal[key][0]
                f = 1.0 + (hsh(i, j, k, self.seed) - 0.5) * 2 * (0.0 if kind == "water" else jitter)
                colr = (lin(min(255, base[0] * f)), lin(min(255, base[1] * f)), lin(min(255, base[2] * f)), 1.0)
                for d in dirs:
                    nb = self.v.get((i + d[0], j + d[1], k + d[2]))
                    if nb is not None and (not selfop or opaque(nb)):
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
                    shade = 0.82 if d[2] < 0 else 1.0
                    for lp in face.loops:
                        lp[col] = (colr[0] * shade, colr[1] * shade, colr[2] * shade, 1.0)
            me = bpy.data.meshes.new(name + "_" + kind)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(kind_mat(kind))
            ob = bpy.data.objects.new(name + "_" + kind, me)
            ob.location = loc
            coll.objects.link(ob)
            made.append(ob)
        return made


def box(coll, size, loc, m, bevel=0.06, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=1, affect="EDGES")
    me = bpy.data.meshes.new("box")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    ob = bpy.data.objects.new("box", me)
    ob.location = loc
    ob.rotation_euler = rot
    coll.objects.link(ob)
    return ob


def beam(coll, a, b, w, m, bevel=0.05):
    """a square timber / pipe from a to b"""
    a, b = V(a), V(b)
    d = b - a
    ob = box(coll, (w, w, d.length), (a + b) / 2, m, bevel)
    ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return ob


def ribbon(coll, pts, widths, side, m, bow=0.18):
    """a falling-water sheet along `pts` (centre line), `side` = horizontal width direction; UV v = studs along"""
    side = V(side).normalized()
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UV")
    rows, L = [], 0.0
    for n, p in enumerate(pts):
        p = V(p)
        if n:
            L += (p - V(pts[n - 1])).length
        t = (pts[min(n + 1, len(pts) - 1)] if n < len(pts) - 1 else p)
        fwd = (V(t) - p) if n < len(pts) - 1 else (p - V(pts[n - 1]))
        out = side.cross(fwd.normalized()) if fwd.length > 1e-6 else V((0, 0, 1))
        row = []
        for s in (-1.0, -0.5, 0.0, 0.5, 1.0):
            q = p + side * (s * widths[n] / 2) + out * (bow * (1 - s * s))
            row.append((bm.verts.new(q), (s + 1) / 2, L))
        rows.append(row)
    for n in range(len(rows) - 1):
        for s in range(4):
            a, b, c2, d = rows[n][s], rows[n][s + 1], rows[n + 1][s + 1], rows[n + 1][s]
            f = bm.faces.new((a[0], b[0], c2[0], d[0]))
            for lp, src in zip(f.loops, (a, b, c2, d)):
                lp[uv].uv = (src[1], src[2])
    me = bpy.data.meshes.new("Fall")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(m)
    ob = bpy.data.objects.new("Fall", me)
    coll.objects.link(ob)
    return ob


def fall_path(p0, direction, throw, drop, lip=0.5, n=14):
    """parabolic fall: leaves the lip horizontally, throw = horizontal distance, drop = height"""
    d = V((direction[0], direction[1], 0)).normalized()
    p0 = V(p0)
    pts = [p0 - d * lip, p0]
    for k in range(1, n + 1):
        s = k / n
        pts.append(p0 + d * (throw * s) - V((0, 0, drop * s * s)))
    return pts


# ================================================================================ characters
def player(coll, loc, face=0.0):
    """a 5.3-stud R15-proportioned blocky player (legs 2.0, torso 2.0, neck 0.1, head 1.2)"""
    x, y, z = loc
    skin = flat_mat("Skin", (234, 196, 160), 0.55)
    shirt = flat_mat("Shirt", (90, 140, 210), 0.7)
    pants = flat_mat("Pants", (60, 66, 90), 0.75)
    shoe = flat_mat("Shoe", (40, 40, 48), 0.6)
    hair = flat_mat("Hair", (90, 60, 40), 0.7)
    parts = []
    for sx in (-0.5, 0.5):
        parts.append(box(coll, (0.95, 1.0, 0.35), (sx, -0.05, 0.175), shoe, 0.08))      # foot
        parts.append(box(coll, (0.9, 0.9, 0.85), (sx, 0, 0.775), pants, 0.08))          # lower leg
        parts.append(box(coll, (0.95, 0.95, 0.85), (sx, 0, 1.6), pants, 0.08))          # upper leg
    parts.append(box(coll, (2.0, 1.0, 0.45), (0, 0, 2.225), pants, 0.08))               # lower torso
    parts.append(box(coll, (2.0, 1.0, 1.55), (0, 0, 3.225), shirt, 0.1))                # upper torso
    for sx in (-1.5, 1.5):
        parts.append(box(coll, (0.95, 0.95, 0.85), (sx, 0, 3.55), shirt, 0.08))         # upper arm
        parts.append(box(coll, (0.9, 0.9, 0.8), (sx, 0, 2.75), skin, 0.08))             # lower arm
        parts.append(box(coll, (0.85, 0.85, 0.4), (sx, 0, 2.15), skin, 0.08))           # hand
    parts.append(box(coll, (1.2, 1.2, 1.2), (0, 0, 4.7), skin, 0.3))                    # head (top = 5.3)
    parts.append(box(coll, (1.26, 1.26, 0.35), (0, 0.04, 5.15), hair, 0.12))
    eye = flat_mat("Eye", (30, 30, 40), 0.4)
    for sx in (-0.22, 0.22):
        parts.append(box(coll, (0.14, 0.05, 0.22), (sx, -0.61, 4.78), eye, 0.0))
    root = bpy.data.objects.new("Player", None)
    coll.objects.link(root)
    for p in parts:
        p.parent = root
    root.location = (x, y, z)
    root.rotation_euler = (0, 0, face)
    return root


NIMBUS_PAL = {
    "W": ((246, 250, 255),), "Wb": ((214, 230, 252),), "Blue": ((120, 176, 240),), "Navy": ((34, 44, 92),),
    "Pink": ((246, 130, 170),), "Gold": ((246, 200, 70), "metal"), "Gem": ((90, 170, 255), "glow"),
    "Hi": ((255, 255, 255), "glow"),
}


def nimbus(coll, loc, face=0.0, scale=1.0, pose="sit"):
    """Nimbus the Cloudy Dragon stand-in (white cloud dragon, blue belly + wing tips, gold crown); faces -Y"""
    vx = Vox(NIMBUS_PAL, 0.2, seed=7)
    up = 0.5 if pose == "spit" else 0.0
    vx.ell((0, 0.1, 1.5), (1.25, 1.35, 1.35), "W")
    vx.paint("Wb", lambda x, y, z: y < -0.6 and abs(x) < 0.9 and z < 2.3, only={"W"})
    for sx in (-0.75, 0.75):
        for sy in (-0.6, 0.75):
            vx.ell((sx, sy, 0.35), (0.45, 0.5, 0.4), "W")
    hy, hz = -0.75 - up * 0.3, 3.35 + up
    vx.ell((0, hy, hz), (1.05, 0.95, 0.9), "W")
    vx.ell((0, hy - 0.85, hz - 0.25 + up * 0.25), (0.65, 0.55, 0.45), "W")  # snout
    vx.box((-0.35, hy - 1.45, hz - 0.45 + up * 0.2), (0.35, hy - 1.0, hz - 0.15 + up * 0.2), "Pink")  # open mouth
    for sx in (-0.42, 0.42):
        vx.box((sx - 0.17, hy - 0.95, hz + 0.05), (sx + 0.17, hy - 0.65, hz + 0.5), "Navy")
        vx.box((sx - 0.02, hy - 0.97, hz + 0.3), (sx + 0.12, hy - 0.85, hz + 0.45), "Hi")
        vx.ell((sx * 1.4, hy + 0.2, hz + 0.75), (0.18, 0.18, 0.4), "Blue")  # little horns
    # crown
    vx.ring(0, hy + 0.1, 0.35, 0.62, hz + 0.75, hz + 1.0, "Gold")
    for a in range(5):
        t = TAU * a / 5
        vx.box((math.cos(t) * 0.5 - 0.1, hy + 0.1 + math.sin(t) * 0.5 - 0.1, hz + 1.0),
               (math.cos(t) * 0.5 + 0.1, hy + 0.1 + math.sin(t) * 0.5 + 0.1, hz + 1.4), "Gold")
    vx.box((-0.12, hy - 0.55, hz + 0.78), (0.12, hy - 0.4, hz + 1.0), "Gem")
    # cloud wings (puffs) and the curled tail
    for sx in (-1, 1):
        for (px, py, pz, r) in ((1.35, 0.5, 2.5, 0.55), (1.85, 0.75, 2.85, 0.5), (2.2, 1.0, 2.35, 0.45), (1.6, 0.9, 2.0, 0.42)):
            vx.ell((sx * px, py, pz), (r, r * 0.8, r), "W")
        vx.paint("Blue", lambda x, y, z: x * sx > 1.8 and z < 2.5, only={"W"})
    for n in range(7):
        t = n / 6
        vx.ell((0.3 * math.sin(t * 3), 1.3 + t * 1.2, 0.5 + t * t * 1.6), (0.4 - t * 0.15,) * 3, "W" if n < 6 else "Blue")
    objs = vx.build(coll, "Nimbus")
    root = bpy.data.objects.new("NimbusRoot", None)
    coll.objects.link(root)
    for o in objs:
        o.parent = root
    root.location = loc
    root.rotation_euler = (0, 0, face)
    root.scale = (scale,) * 3
    return root


def mouth_world(loc, face, scale, pose="spit"):
    up = 0.5 if pose == "spit" else 0.0
    hy, hz = -0.75 - up * 0.3, 3.35 + up
    p = V((0, hy - 1.4, hz - 0.3 + up * 0.2)) * scale
    c, s = math.cos(face), math.sin(face)
    return V((loc[0] + p.x * c - p.y * s, loc[1] + p.x * s + p.y * c, loc[2] + p.z))


# ================================================================================ FX (rebuilt per motion frame)
FX = []
DYN = []  # (object, fn(t)) transforms per frame


def fx_clear():
    for ob in FX:
        bpy.data.objects.remove(ob, do_unlink=True)
    FX.clear()


def fx_box(coll, size, loc, m, rot=(0, 0, 0)):
    ob = box(coll, size, loc, m, 0.04, rot)
    FX.append(ob)
    return ob


def droplets(coll, pts, t, n, m, size=0.32, seed=0, jit=0.25):
    """n drops spaced along a path, advanced by phase t"""
    rng = random.Random(seed)
    L = len(pts) - 1
    for k in range(n):
        s = ((k + rng.random() * 0.4) / n + t) % 1.0
        f = s * L
        i = min(int(f), L - 1)
        p = V(pts[i]).lerp(V(pts[i + 1]), f - i)
        p += V((rng.uniform(-jit, jit), rng.uniform(-jit, jit), rng.uniform(-jit, jit)))
        fx_box(coll, (size,) * 3, p, m, (rng.random(), rng.random(), rng.random()))


def splash(coll, ctr, t, m_foam, m_drop, r=1.2, n=10, seed=0, hmax=1.6):
    """a foam ring that grows with t + droplets thrown up in little arcs"""
    rng = random.Random(seed)
    ctr = V(ctr)
    for ring_t in ((t % 1.0), ((t + 0.5) % 1.0)):
        rr = r * (0.35 + ring_t)
        for a in range(14):
            ang = TAU * a / 14 + seed
            if hsh(a, seed, int(ring_t * 10)) < 0.2:
                continue
            fx_box(coll, (0.45, 0.45, 0.12), ctr + V((math.cos(ang) * rr, math.sin(ang) * rr, 0.05)), m_foam, (0, 0, ang))
    for k in range(n):
        ang = rng.uniform(0, TAU)
        ph = (rng.random() + t) % 1.0
        dist = r * 0.9 * ph
        z = 4 * hmax * ph * (1 - ph) * rng.uniform(0.5, 1.0)
        fx_box(coll, (0.26,) * 3, ctr + V((math.cos(ang) * dist, math.sin(ang) * dist, z + 0.1)), m_drop,
               (rng.random(), rng.random(), 0))
    for k in range(5):  # foam blocks churning at the impact
        fx_box(coll, (0.55, 0.55, 0.3), ctr + V((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0.1 + 0.12 * math.sin(TAU * (t + k / 5)))),
               m_foam, (0, 0, rng.uniform(0, 3)))


def ripples(coll, ctr, t, m, r0=1.6, r1=4.5, z=0.0):
    for ph in (t % 1.0, (t + 0.5) % 1.0):
        rr = r0 + (r1 - r0) * ph
        n = max(10, int(rr * 5))
        for a in range(n):
            ang = TAU * a / n
            if hsh(a, int(rr * 3)) < 0.25:
                continue
            fx_box(coll, (0.5, 0.18, 0.06), V(ctr) + V((math.cos(ang) * rr, math.sin(ang) * rr, z)), m, (0, 0, ang + math.pi / 2))


# ================================================================================ shared palettes
WATER = (96, 186, 240)
WATER_DEEP = (52, 128, 210)
FOAM = (236, 248, 255)


def mats_fx():
    return flat_mat("FoamFx", FOAM, 0.4, alpha=0.9, emit=0.2), flat_mat("DropFx", (200, 236, 255), 0.1, alpha=0.85, emit=0.3)


# ================================================================================ TODAY: the kit's real meshes
def today(coll, ox):
    sys.path.insert(0, os.path.abspath(KIT))
    sys.dont_write_bytecode = True
    import props
    from nvox import blend as B
    reg = props.load_all()
    made = []
    for e in ({"key": "prop_fountain", "prop": "lobby_fountain"},
              {"key": "prop_fountain_water", "prop": "lobby_fountain", "args": {"water": True}}):
        m = reg["lobby_fountain"](e, props.PropKit())
        made += B.make_objects(m, None, collection=coll)
    for ob in made:
        ob.location = (ox, 0, 0)
    # the statue: LobbyBuilder puts the pet's lowest point at TOP + 10.0 (topY 9.4 + 0.6)
    nimbus(coll, (ox, 0, 10.0), face=0.0, scale=1.25)
    return made


# ================================================================================ option A: The Rain-Catcher
PAL_A = {
    "Cob": ((150, 150, 162),), "CobL": ((182, 180, 190),), "CobD": ((118, 118, 132),), "Moss": ((112, 164, 86),),
    "Cap": ((214, 210, 214),), "Floor": ((96, 104, 120),), "Water": (WATER, "water"),
    "Cu": ((206, 124, 72), "metal"), "CuD": ((168, 94, 56), "metal"), "Pat": ((108, 190, 168),),
    "Brass": ((222, 178, 80), "metal"), "Wood": ((150, 102, 60),), "WoodD": ((112, 76, 46),),
    "Cloud": ((248, 250, 255),), "CloudS": ((214, 226, 246),), "Slate": ((60, 66, 80),), "Chalk": ((240, 240, 236),),
    "Rope": ((206, 184, 136),), "Sail": ((250, 246, 236),),
}


def option_a(coll, ox, t=0.0, fx=True):
    vx = Vox(PAL_A, 0.5, seed=11)
    # octagonal stone trough (settlers' cobbles, a pale cap course, moss in the joints)
    vx.ring(0, 0, 8.6, 10.2, 0, 2.0, "Cob", oct=True)
    vx.paint("CobL", lambda x, y, z: True, only={"Cob"}, prob=0.3, seed=3)
    vx.paint("CobD", lambda x, y, z: True, only={"Cob"}, prob=0.15, seed=4)
    vx.paint("Moss", lambda x, y, z: z < 0.8, only={"Cob", "CobL", "CobD"}, prob=0.35, seed=5)
    vx.ring(0, 0, 8.4, 10.5, 2.0, 2.5, "Cap", oct=True)
    vx.paint("Moss", lambda x, y, z: True, only={"Cap"}, prob=0.06, seed=6)
    vx.disc(0, 0, 8.6, 0, 0.5, "Floor", oct=True)
    vx.disc(0, 0, 8.6, 0.5, 1.6, "Water", oct=True)
    # the central stone plinth
    vx.box((-1.75, -1.75, 0), (1.75, 1.75, 2.5), "Cob")
    vx.paint("CobL", lambda x, y, z: True, only={"Cob"}, prob=0.25, seed=8)
    vx.box((-2.0, -2.0, 2.5), (2.0, 2.0, 3.0), "Cap")
    # copper funnel with patina streaks and a riveted rim
    vx.cone(0, 0, 11.0, 14.5, 1.0, 4.6, "Cu", thick=0.55)
    vx.paint("CuD", lambda x, y, z: True, only={"Cu"}, prob=0.25, seed=9)
    vx.paint("Pat", lambda x, y, z: hsh(int(math.atan2(y, x) * 6), 1) < 0.45 and z < 13.5, only={"Cu", "CuD"}, prob=0.8, seed=10)
    vx.ring(0, 0, 4.3, 5.0, 14.5, 15.0, "CuD")
    vx.disc(0, 0, 4.0, 13.6, 14.2, "Water")   # the caught rainwater
    # the down-pipe, elbow and chute that feeds the wheel; a brass spigot on the rim
    vx.ring(0, 0, 0, 0.55, 8.6, 11.2, "Cu")
    vx.box((0, -0.5, 8.6), (3.2, 0.5, 9.6), "Cu")
    vx.box((2.6, -0.8, 8.4), (4.0, 0.8, 8.8), "CuD")
    vx.box((2.6, -0.8, 8.8), (4.0, -0.5, 9.2), "CuD")
    vx.box((2.6, 0.5, 8.8), (4.0, 0.8, 9.2), "CuD")
    vx.paint("Pat", lambda x, y, z: z < 9.2 and x > 1, only={"Cu"}, prob=0.4, seed=12)
    vx.box((-0.5, -10.9, 1.3), (0.5, -9.8, 1.9), "Brass")
    vx.box((-0.25, -11.2, 0.9), (0.25, -10.7, 1.4), "Brass")
    # an overflow spout on the plinth (west), the old stone lip
    vx.box((-2.6, -0.8, 2.2), (-1.75, 0.8, 2.7), "CobD")
    # the captive rain-cloud, tied down with a rope, dripping into the funnel
    for (px, py, pz, r) in ((2.5, 3.1, 21.2, 2.0), (0.6, 2.7, 20.7, 1.6), (4.2, 2.5, 20.6, 1.5), (2.4, 1.9, 22.3, 1.5), (1.6, 3.9, 20.9, 1.3)):
        vx.ell((px, py, pz), (r, r * 0.85, r * 0.75), "Cloud")
    vx.paint("CloudS", lambda x, y, z: z < 20.4, only={"Cloud"})
    sculpt = vx.build(coll, "RainCatcher", loc=(ox, 0, 0))
    # timber frame (posts, rails, braces), the wheel A-frame, rope, a maintenance ladder
    wood, woodd = flat_mat("Timber", (150, 102, 60), 0.75), flat_mat("TimberD", (112, 76, 46), 0.8)
    rope = flat_mat("Rope", (206, 184, 136), 0.9)
    o = lambda z: 1.3 + 0.9 * (z - 3.0) / 10.0  # the four posts lean out to meet the funnel wall at z 13
    for sx in (-1, 1):
        for sy in (-1, 1):
            beam(coll, (ox + sx * o(3.0), sy * o(3.0), 3.0), (ox + sx * o(13.0), sy * o(13.0), 13.0), 0.55, wood)
    for z in (6.6, 10.4):
        for s in (-1, 1):
            beam(coll, (ox + s * o(z), -o(z) - 0.2, z), (ox + s * o(z), o(z) + 0.2, z), 0.4, woodd)
            beam(coll, (ox - o(z) - 0.2, s * o(z), z), (ox + o(z) + 0.2, s * o(z), z), 0.4, woodd)
    beam(coll, (ox - o(3.3), -o(3.3) - 0.05, 3.3), (ox + o(6.4), -o(6.4) - 0.05, 6.4), 0.3, woodd)
    beam(coll, (ox - o(6.8), -o(6.8) - 0.05, 6.8), (ox + o(10.2), -o(10.2) - 0.05, 10.2), 0.3, woodd)
    for sy in (-1.0, 1.0):  # A-frame standing in the pool, holding the wheel's outer axle end
        beam(coll, (ox + 8.25, sy * 1.6, 0.5), (ox + 8.25, sy * 0.35, 5.0), 0.45, wood)
    beam(coll, (ox + 1.75, 0, 4.6), (ox + 8.5, 0, 4.6), 0.35, flat_mat("Iron", (70, 72, 80), 0.5, 0.6))
    for sx in (-0.45, 0.45):  # ladder leaning on the frame (north side): pool floor -> the top rail
        beam(coll, (ox + sx, 4.4, 0.5), (ox + sx, o(10.4) + 0.3, 10.6), 0.18, woodd)
    for k in range(11):
        z = 1.3 + k * 0.85
        yy = 4.4 - (z - 0.5) / (10.6 - 0.5) * (4.4 - o(10.4) - 0.3)
        box(coll, (1.1, 0.14, 0.14), (ox, yy, z), wood, 0.02)
    beam(coll, (ox + 3.6, 3.0, 15.0), (ox + 2.6, 2.9, 19.8), 0.12, rope)
    rivet = flat_mat("Rivet", (222, 178, 80), 0.35, 0.6)
    for a in range(20):  # brass rivets round the funnel rim
        ang = TAU * a / 20
        box(coll, (0.22, 0.22, 0.12), (ox + math.cos(ang) * 4.65, math.sin(ang) * 4.65, 15.05), rivet, 0.03)
    # the water wheel (rotates about the axle: one object)
    wv = Vox({"Wood": ((150, 102, 60),), "WoodD": ((112, 76, 46),), "Iron": ((80, 82, 92), "metal")}, 0.25, seed=13)
    for yy in (-0.55, 0.55):
        wv.fill((-3.0, 3.0), (yy - 0.12, yy + 0.12), (-3.0, 3.0), lambda x, y, z: 2.35 <= math.hypot(x, z) <= 2.8, "WoodD")
    wv.fill((-0.4, 0.4), (-0.7, 0.7), (-0.4, 0.4), lambda x, y, z: True, "Iron")
    for s in range(4):
        ang = TAU * s / 8
        wv.fill((-2.5, 2.5), (-0.3, 0.3), (-2.5, 2.5),
                lambda x, y, z, ang=ang: abs(-math.sin(ang) * x + math.cos(ang) * z) < 0.16 and math.hypot(x, z) < 2.4, "Wood")
    for p in range(8):
        ang = TAU * p / 8
        cx, cz = math.cos(ang) * 2.7, math.sin(ang) * 2.7
        wv.fill((cx - 0.8, cx + 0.8), (-0.75, 0.75), (cz - 0.8, cz + 0.8),
                lambda x, y, z, ang=ang, cx=cx, cz=cz: abs(math.cos(ang) * (z - cz) - math.sin(ang) * (x - cx)) < 0.14 and abs(math.cos(ang) * (x - cx) + math.sin(ang) * (z - cz)) < 0.55, "Wood")
    wheel = bpy.data.objects.new("WheelRoot", None)
    coll.objects.link(wheel)
    for o in wv.build(coll, "Wheel"):
        o.parent = wheel
    wheel.location = (ox + 4.6, 0, 4.6)
    wheel.rotation_euler = (0, t * TAU / 8, 0)
    # Nimbus perched on the funnel rim like a weathervane, a slate tally board, a bucket, the toy boat
    nimbus(coll, (ox - 0.4, -4.3, 15.0), face=-0.25, scale=1.05)
    slate = flat_mat("Slate", (58, 64, 78), 0.8)
    chalk = flat_mat("Chalk", (240, 240, 236), 0.9, emit=0.1)
    box(coll, (2.0, 0.2, 1.4), (ox - 4.2, -10.85, 1.25), slate, 0.04, rot=(0.25, 0, 0))
    for k in range(5):
        box(coll, (0.07, 0.05, 0.8), (ox - 4.85 + k * 0.22, -11.02, 1.25), chalk, 0.0, rot=(0.25, 0, 0))
    box(coll, (1.25, 0.05, 0.07), (ox - 4.4, -11.03, 1.25), chalk, 0.0, rot=(0.25, 0, 0.55))
    box(coll, (0.07, 0.05, 0.6), (ox - 3.55, -11.02, 1.3), chalk, 0.0, rot=(0.25, 0, 0))
    bucket = flat_mat("Bucket", (130, 90, 56), 0.75)
    hoop = flat_mat("Hoop", (80, 82, 92), 0.5, 0.6)
    box(coll, (1.1, 1.1, 1.0), (ox, -11.2, 0.5), bucket, 0.15)
    box(coll, (1.18, 1.18, 0.12), (ox, -11.2, 0.75), hoop, 0.03)
    box(coll, (0.9, 0.9, 0.05), (ox, -11.2, 0.88), flat_mat("BucketWater", WATER, 0.1, alpha=0.8), 0.0)
    boat_t = 0.06 * math.sin(TAU * t)
    hull = flat_mat("BoatHull", (196, 74, 64), 0.6)
    box(coll, (1.6, 0.7, 0.45), (ox - 5.0, -4.6, 1.8 + boat_t), hull, 0.15, rot=(0, 0, 0.6))
    box(coll, (0.08, 0.08, 1.2), (ox - 5.0, -4.6, 2.5 + boat_t), woodd, 0.0)
    box(coll, (0.8, 0.05, 0.9), (ox - 5.0 + 0.3, -4.6 - 0.2, 2.55 + boat_t), flat_mat("Sail", (250, 246, 236), 0.8), 0.0, rot=(0, 0, -0.6))
    if fx:
        option_a_fx(coll, ox, t)
    return sculpt


def option_a_fx(coll, ox, t):
    foam, drop = mats_fx()
    sm = sheet_mat("SheetA", WATER, FOAM, 0.82, 1.6)
    # chute -> wheel top (lands on the paddles), the overflow lip -> pool
    ribbon(coll, fall_path((ox + 4.0, 0, 8.85), (1, 0, 0), 0.9, 0.95, lip=1.0, n=6), [1.5] * 8, (0, 1, 0), sm)
    splash(coll, (ox + 4.9, 0, 7.95), t, foam, drop, r=0.6, n=6, seed=7, hmax=0.6)
    sm2 = sheet_mat("SheetA2", WATER, FOAM, 0.82, 1.4)
    ribbon(coll, fall_path((ox - 2.6, 0, 2.55), (-1, 0, 0), 0.9, 1.0, lip=0.6, n=6), [1.4 - 0.05 * k for k in range(8)], (0, 1, 0), sm2)
    # paddles shed water: drops falling off the wheel's far side, splash where they land
    for k, (dx, dz) in enumerate(((2.9, 0.0), (2.4, -1.4), (2.0, 1.6))):
        p0 = V((ox + 4.6 + dx, 0, 4.6 + dz))
        droplets(coll, [p0, p0 + V((0.6, 0, -1.2)), p0 + V((0.9, 0, -(p0.z - 1.6)))], t, 4, drop, 0.28, seed=k)
    splash(coll, (ox + 7.0, 0, 1.6), t, foam, drop, r=1.0, n=8, seed=2, hmax=1.0)
    splash(coll, (ox - 3.6, 0, 1.6), t + 0.3, foam, drop, r=0.9, n=6, seed=3, hmax=0.8)
    ripples(coll, (ox + 4.6, 0, 0), t, foam, 3.0, 4.2, z=1.62)
    # rain from the captive cloud into the funnel, the spigot's trickle into the bucket
    rng = random.Random(4)
    for k in range(14):
        x, y = rng.uniform(0.2, 3.6), rng.uniform(1.0, 3.6)
        ph = (rng.random() + t) % 1.0
        fx_box(coll, (0.12, 0.12, 0.55), (ox + x, y, 19.6 - ph * 5.4), drop)
    droplets(coll, [V((ox, -11.0, 1.0)), V((ox, -11.2, 0.95))], t, 3, drop, 0.18, seed=5, jit=0.02)


# ================================================================================ option B: Nimbus' Bath
PAL_B = {
    "Sand": ((234, 218, 192),), "SandS": ((206, 186, 160),), "SandL": ((246, 236, 216),),
    "Tile": ((84, 196, 208),), "TileD": ((46, 146, 172),), "TileW": ((240, 248, 248),),
    "Gold": ((246, 200, 70), "metal"), "Water": ((110, 214, 236), "water"),
    "Rock": ((176, 168, 160),), "RockD": ((140, 134, 130),), "Moss": ((112, 170, 96),),
}


def option_b(coll, ox, t=0.0, fx=True):
    vx = Vox(PAL_B, 0.5, seed=21)
    # the raised, waist-high bath (2.6 studs) with a mosaic band and a worn sandstone cap
    vx.ring(0, 0, 8.8, 10.4, 0, 2.2, "Sand")
    vx.paint("SandS", lambda x, y, z: True, only={"Sand"}, prob=0.3, seed=2)
    vx.paint("Tile", lambda x, y, z: 0.9 < z < 1.6 and math.hypot(x, y) > 10.0, only={"Sand", "SandS"})
    vx.paint("TileW", lambda x, y, z: (int(math.atan2(y, x) * 16) % 2 == 0), only={"Tile"})
    vx.ring(0, 0, 8.6, 10.6, 2.2, 2.7, "SandL")
    vx.fill((-11, 11), (-11, 11), (2.2, 2.7), lambda x, y, z: math.hypot(x, y) > 10.1 and hsh(int(x * 2), int(y * 2), 9) < 0.18, None)  # chipped cap
    # the bathers' steps on the front, the middle worn down
    vx.box((-2.6, -12.0, 0), (2.6, -10.2, 0.8), "SandS")
    vx.box((-2.6, -11.1, 0.8), (2.6, -10.2, 1.6), "Sand")
    vx.fill((-1.0, 1.0), (-12.0, -10.2), (0.6, 1.6), lambda x, y, z: (z > 1.4 and y > -11.1) or (0.6 < z < 0.8 and y < -11.1), None)
    # the mosaic floor (turquoise / white, a gold sun in the middle), lucky coins on the bottom
    vx.disc(0, 0, 8.8, 0, 0.4, "Tile")
    vx.paint("TileD", lambda x, y, z: (int(x / 1.0) + int(y / 1.0)) % 2 == 0, only={"Tile"})
    vx.paint("TileW", lambda x, y, z: 6.4 < math.hypot(x, y) < 7.2, only={"Tile", "TileD"})
    vx.disc(0, 0, 8.8, 0.4, 1.9, "Water")
    # Nimbus's bathing rock, mossy where the water hits
    for (px, py, pz, rx, ry, rz) in ((0, 0.4, 1.2, 2.9, 2.7, 1.8), (-0.6, 0.8, 2.8, 2.0, 2.0, 1.4), (0.8, -0.2, 2.4, 1.6, 1.5, 1.2), (0.0, 0.6, 3.9, 1.5, 1.4, 0.9)):
        vx.ell((px, py, pz), (rx, ry, rz), "Rock")
    vx.paint("RockD", lambda x, y, z: True, only={"Rock"}, prob=0.3, seed=7)
    vx.paint("Moss", lambda x, y, z: z < 2.6, only={"Rock", "RockD"}, prob=0.35, seed=8)
    vx.paint("Water", lambda x, y, z: z < 1.9 and math.hypot(x, y) > 3.2, only={"Rock", "RockD", "Moss"})
    rng = random.Random(5)
    for k in range(22):  # lucky coins on the bottom (tossed by players)
        a, r = rng.uniform(0, TAU), rng.uniform(3.6, 8.2)
        vx.box((math.cos(a) * r - 0.25, math.sin(a) * r - 0.25, 0.4), (math.cos(a) * r + 0.25, math.sin(a) * r + 0.25, 0.5), "Gold")
    sculpt = vx.build(coll, "Bath", loc=(ox, 0, 0))
    # Nimbus up on the rock, head raised, spitting an arc at the front-left of the pool
    nl, nf, ns = (ox + 0.0, 0.5, 4.5), 1.04, 1.25
    nimbus(coll, nl, face=nf, scale=ns, pose="spit")
    # towel rail + striped towel, scrub brush, soap, three lily pads and a rubber duck
    brass = flat_mat("Brass", (222, 178, 80), 0.35, 0.6)
    pa, pb = V((math.cos(1.02) * 9.6, math.sin(1.02) * 9.6, 0)), V((math.cos(0.7) * 9.6, math.sin(0.7) * 9.6, 0))
    for p in (pa, pb):
        beam(coll, (ox + p.x, p.y, 2.7), (ox + p.x, p.y, 4.6), 0.18, brass)
    beam(coll, (ox + pa.x, pa.y, 4.5), (ox + pb.x, pb.y, 4.5), 0.16, brass)
    tang = math.atan2(pb.y - pa.y, pb.x - pa.x)
    for k in range(6):
        p = pa.lerp(pb, 0.2 + k * 0.12)
        box(coll, (0.4, 0.12, 1.6), (ox + p.x, p.y - 0.12, 3.75), flat_mat("Towel%d" % (k % 2), (236, 110, 120) if k % 2 else (252, 248, 244), 0.9), 0.02, rot=(0, 0, tang))
    box(coll, (1.0, 0.45, 0.3), (ox + 9.3, 3.8, 2.85), flat_mat("Brush", (170, 116, 70), 0.7), 0.06, rot=(0, 0, 0.6))
    box(coll, (0.6, 0.4, 0.3), (ox + 4.3, 8.9, 2.85), flat_mat("Soap", (250, 200, 220), 0.4), 0.1)
    bob = 0.06 * math.sin(TAU * t)
    pad = flat_mat("Lily", (98, 182, 92), 0.6)
    pad2 = flat_mat("LilyD", (70, 150, 76), 0.65)
    for k, (x, y, r) in enumerate(((4.4, 4.6, 1.5), (-5.6, 3.0, 1.3), (-2.6, -6.6, 1.2))):
        pv = Vox({"L": ((98, 182, 92),), "D": ((70, 150, 76),)}, 0.25, seed=30 + k)
        pv.fill((-r, r), (-r, r), (0, 0.25), lambda xx, yy, zz: math.hypot(xx, yy) <= r and not (xx > 0 and abs(yy) < xx * 0.35), "L")
        pv.paint("D", lambda xx, yy, zz: math.hypot(xx, yy) < r * 0.45, only={"L"})
        for o in pv.build(coll, "Pad%d" % k, loc=(ox + x, y, 1.88 + bob * (1 if k % 2 else -1))):
            o.rotation_euler = (0, 0, k * 2.1)
    box(coll, (0.5, 0.5, 0.5), (ox - 5.6, 3.0, 2.45 + bob), flat_mat("Lotus", (250, 160, 196), 0.6), 0.15)
    duck = flat_mat("Duck", (255, 214, 60), 0.4)
    dx, dy = ox - 5.6, -2.6
    box(coll, (1.1, 0.8, 0.6), (dx, dy, 2.1 + bob), duck, 0.25)
    box(coll, (0.6, 0.6, 0.6), (dx + 0.35, dy, 2.6 + bob), duck, 0.22)
    box(coll, (0.35, 0.3, 0.15), (dx + 0.75, dy, 2.55 + bob), flat_mat("Beak", (250, 130, 40), 0.5), 0.05)
    box(coll, (0.3, 0.32, 0.2), (dx - 0.6, dy, 2.4 + bob), duck, 0.06, rot=(0, -0.6, 0))
    if fx:
        option_b_fx(coll, ox, t, nl, nf, ns)
    return sculpt


def option_b_fx(coll, ox, t, nl, nf, ns):
    foam, drop = mats_fx()
    m0 = mouth_world(nl, nf, ns)
    # the arc: leaves the mouth up-and-out, lands ~6.5 studs out at the front-left
    d = V((math.sin(nf), -math.cos(nf), 0)).normalized()
    land = V((m0.x + d.x * 6.0, m0.y + d.y * 6.0, 1.9))
    pts = []
    for k in range(17):
        s = k / 16
        p = m0.lerp(land, s)
        p.z = m0.z + (land.z - m0.z) * s + 2.6 * 4 * s * (1 - s)
        pts.append(p)
    side = V((d.y, -d.x, 0))
    sm = sheet_mat("ArcB", (120, 200, 245), FOAM, 0.85, 2.2)
    ribbon(coll, pts, [0.55 + 0.25 * k / 16 for k in range(17)], side, sm, bow=0.2)
    droplets(coll, pts, t, 9, drop, 0.26, seed=1, jit=0.35)
    splash(coll, land, t, foam, drop, r=1.5, n=12, seed=4, hmax=1.4)
    ripples(coll, land, t, foam, 1.8, 4.8, z=1.92)
    # a foam collar where the bath laps at the rock
    for a in range(18):
        ang = TAU * a / 18
        r = 3.35 + 0.15 * math.sin(TAU * (t + a / 6))
        fx_box(coll, (0.6, 0.35, 0.12), (ox + math.cos(ang) * r, 0.4 + math.sin(ang) * r, 1.93), foam, (0, 0, ang + 1.57))


# ================================================================================ option C: Sky-Oasis Steps
PAL_C = {
    "Rock": ((170, 170, 186),), "RockD": ((132, 132, 152),), "RockL": ((200, 200, 212),),
    "Grass": ((112, 200, 92),), "GrassL": ((150, 222, 112),), "Dirt": ((150, 106, 72),), "DirtD": ((116, 80, 56),),
    "Root": ((122, 86, 56),), "Water": (WATER, "water"), "Floor": ((86, 100, 118),),
    "Twig": ((140, 98, 60),), "Flower": ((250, 150, 190),), "FlowerY": ((252, 216, 90),), "Leaf": ((86, 176, 96),),
    "LeafL": ((122, 202, 110),), "Trunk": ((120, 84, 54),), "Plank": ((182, 132, 82),),
}
FLOWERS = []
ROOTS = []
ISL = ((-2.2, 1.0, 5.0, 4.0), (2.2, 1.6, 9.0, 3.1), (-0.4, 2.6, 12.6, 2.4))  # (x, y, top z, radius)


def island(vx, cx, cy, top, r, seed):
    vx.cone(cx, cy, top - r * 0.85, top - 0.5, 0.7, r, "Dirt")
    vx.paint("DirtD", lambda x, y, z: True, only={"Dirt"}, prob=0.3, seed=seed)
    vx.paint("Rock", lambda x, y, z: True, only={"Dirt", "DirtD"}, prob=0.12, seed=seed + 1)
    vx.disc(cx, cy, r + 0.15, top - 0.5, top, "Grass")
    vx.paint("GrassL", lambda x, y, z: True, only={"Grass"}, prob=0.3, seed=seed + 2)
    for k in range(5):  # hanging roots under the rim
        a = TAU * hsh(k, seed) + k
        rr = r * 0.7
        x0, y0 = cx + math.cos(a) * rr, cy + math.sin(a) * rr
        L = 1.0 + 1.6 * hsh(k, seed, 3)
        ROOTS.append((x0, y0, top - r * 0.5 - L * 0.6, top - r * 0.3))


def channel(vx, a, b, top, w=0.5):
    """a shallow stream cut into an island's grass from a to b"""
    ax, ay = a
    bx, by = b

    def near(x, y, z):
        vx_, vy_ = bx - ax, by - ay
        L2 = vx_ * vx_ + vy_ * vy_
        s = max(0.0, min(1.0, ((x - ax) * vx_ + (y - ay) * vy_) / L2))
        return math.hypot(x - (ax + vx_ * s), y - (ay + vy_ * s)) <= w
    vx.fill((min(ax, bx) - 1, max(ax, bx) + 1), (min(ay, by) - 1, max(ay, by) + 1), (top - 0.5, top), near, "Water")


def option_c(coll, ox, t=0.0, fx=True):
    vx = Vox(PAL_C, 0.5, seed=31)
    # the pool: a ring of natural stones with grass tufts on top
    vx.ring(0, 0, 8.8, 10.4, 0, 1.6, "Rock")
    vx.paint("RockD", lambda x, y, z: True, only={"Rock"}, prob=0.3, seed=1)
    vx.paint("RockL", lambda x, y, z: True, only={"Rock"}, prob=0.2, seed=2)
    vx.fill((-11, 11), (-11, 11), (1.6, 2.1), lambda x, y, z: 8.8 <= math.hypot(x, y) <= 10.4 and hsh(int(x * 2), int(y * 2), 4) < 0.55, "Rock")
    vx.paint("Grass", lambda x, y, z: z > 1.5 and hsh(int(x), int(y), 5) < 0.45, only={"Rock", "RockD", "RockL"})
    vx.disc(0, 0, 8.8, 0, 0.4, "Floor")
    vx.disc(0, 0, 8.8, 0.4, 1.2, "Water")
    # stone pillars: pool floor -> island 1, island 1 -> 2, island 2 -> 3
    vx.cone(-2.2, 1.0, 0, 2.2, 1.8, 1.2, "Rock")
    vx.cone(1.5, 1.8, 4.9, 6.7, 1.0, 0.8, "RockD")
    vx.cone(0.3, 2.4, 8.9, 10.8, 0.9, 0.7, "Rock")
    for k, (cx, cy, top, r) in enumerate(ISL):
        island(vx, cx, cy, top, r, 40 + k * 7)
    # the spring on top: a little rock outcrop the water wells out of, and the nest around Nimbus
    vx.ell((-1.3, 3.6, 13.0), (0.9, 0.8, 0.7), "RockL")
    vx.ring(-0.6, 2.4, 1.0, 1.7, 12.6, 13.2, "Twig")
    channel(vx, (-1.0, 3.2), (1.9, 2.6), 12.6)
    channel(vx, (2.0, 2.8), (2.1, -1.3), 9.0, w=0.8)
    channel(vx, (-1.9, 0.6), (-4.9, -1.6), 5.0)
    # blocky tree on island 1, flower tufts
    vx.box((-4.6, 2.2, 5.0), (-3.9, 2.9, 7.4), "Trunk")
    vx.ell((-4.25, 2.55, 8.2), (1.5, 1.4, 1.2), "Leaf")
    vx.paint("LeafL", lambda x, y, z: z > 8.4, only={"Leaf"}, prob=0.6, seed=3)
    rng = random.Random(9)
    for k in range(14):
        i = k % 3
        cx, cy, top, r = ISL[i]
        a, rr = rng.uniform(0, TAU), rng.uniform(0.6, r - 0.4)
        x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr
        if vx.v.get((math.floor(x / 0.5), math.floor(y / 0.5), math.floor((top - 0.25) / 0.5))) == "Water":
            continue
        FLOWERS.append((x, y, top, k))
    sculpt = vx.build(coll, "SkyOasis", loc=(ox, 0, 0))
    for (x, y, top, k) in FLOWERS:
        box(coll, (0.12, 0.12, 0.45), (ox + x, y, top + 0.22), flat_mat("Stem", (80, 160, 80), 0.8), 0.0)
        box(coll, (0.42, 0.42, 0.22), (ox + x, y, top + 0.5), flat_mat("Bloom%d" % (k % 2), (250, 150, 190) if k % 2 else (252, 216, 90), 0.6), 0.06)
    FLOWERS.clear()
    root = flat_mat("RootC", (112, 80, 52), 0.85)
    for (x0, y0, z0, z1) in ROOTS:
        beam(coll, (ox + x0, y0, z1), (ox + x0 * 1.06, y0 * 1.06, z0), 0.2, root)
    ROOTS.clear()
    # the mini climb: stepping stones in the pool -> island 1, a ladder to 2, a knotted rope to 3
    stone = flat_mat("StepStone", (190, 190, 202), 0.8)
    for k, (x, y, z) in enumerate(((-6.6, -6.4, 1.9), (-6.6, -3.8, 2.8), (-6.4, -1.4, 3.8))):
        box(coll, (2.0, 1.8, z), (ox + x, y, z / 2), stone, 0.15)
        box(coll, (1.6, 1.4, 0.18), (ox + x - 0.1, y + 0.1, z + 0.05), flat_mat("Tuft", (120, 204, 96), 0.8), 0.05)
    plank = flat_mat("Plank", (182, 132, 82), 0.75)
    for sx in (-0.45, 0.45):
        beam(coll, (ox + 0.2 + sx, -1.4, 5.0), (ox + 0.4 + sx, -0.6, 9.1), 0.18, plank)
    for k in range(5):
        z = 5.6 + k * 0.75
        box(coll, (1.1, 0.14, 0.14), (ox + 0.3, -1.4 + (z - 5.0) / 4.1 * 0.8, z), plank, 0.02)
    rope = flat_mat("RopeC", (210, 190, 140), 0.9)
    beam(coll, (ox + 0.9, 1.0, 12.7), (ox + 1.0, 0.2, 9.0), 0.16, rope)
    for k in range(4):
        box(coll, (0.32, 0.32, 0.32), (ox + 0.92 + k * 0.025, 0.85 - k * 0.2, 12.0 - k * 0.8), rope, 0.1)
    # lantern post on island 2, a wooden sign on the rim, a paper boat in the pool
    post = flat_mat("Post", (110, 76, 48), 0.8)
    box(coll, (0.25, 0.25, 2.2), (ox + 3.6, 3.2, 10.1), post, 0.03)
    box(coll, (0.6, 0.6, 0.7), (ox + 3.6, 3.2, 11.4), flat_mat("Lamp", (255, 214, 140), 0.3, emit=2.5), 0.08)
    box(coll, (0.25, 0.25, 1.6), (ox - 9.6, -3.4, 2.4), post, 0.03)
    box(coll, (1.9, 0.18, 0.9), (ox - 9.6, -3.6, 3.2), plank, 0.05, rot=(0, 0.05, -0.6))
    bob = 0.05 * math.sin(TAU * t)
    paper = flat_mat("Paper", (250, 248, 240), 0.8)
    box(coll, (1.1, 0.5, 0.3), (ox + 5.0, -5.6, 1.35 + bob), paper, 0.05, rot=(0, 0, 0.4))
    box(coll, (0.5, 0.05, 0.6), (ox + 5.0, -5.6, 1.75 + bob), paper, 0.0, rot=(0, 0, 0.4))
    # Nimbus in the nest on the top island
    nimbus(coll, (ox - 0.6, 2.4, 12.7), face=-0.35, scale=1.0)
    if fx:
        option_c_fx(coll, ox, t)
    return sculpt


def option_c_fx(coll, ox, t):
    foam, drop = mats_fx()
    # three falls: island 3 -> 2 (east), island 2 -> pool (front, the big one), island 1 -> pool (west)
    sm1 = sheet_mat("FallC1", WATER, FOAM, 0.82, 1.5)
    ribbon(coll, fall_path((ox + 1.95, 2.6, 12.55), (1, -0.15, 0), 0.6, 3.5, lip=0.6, n=10), [0.9 + 0.03 * k for k in range(12)], (0.15, 1, 0), sm1)
    sm2 = sheet_mat("FallC2", WATER, FOAM, 0.82, 1.3)
    ribbon(coll, fall_path((ox + 2.1, -1.45, 8.95), (0, -1, 0), 1.6, 7.7, lip=0.6, n=14), [1.7 + 0.05 * k for k in range(16)], (1, 0, 0), sm2)
    sm3 = sheet_mat("FallC3", WATER, FOAM, 0.82, 1.4)
    ribbon(coll, fall_path((ox - 5.0, -1.65, 4.95), (-0.8, -0.6, 0), 1.0, 3.7, lip=0.6, n=10), [1.0 + 0.04 * k for k in range(12)], (0.6, -0.8, 0), sm3)
    splash(coll, (ox + 2.6, 2.5, 9.05), t + 0.2, foam, drop, r=0.8, n=6, seed=1, hmax=0.7)
    splash(coll, (ox + 2.1, -3.05, 1.25), t, foam, drop, r=1.5, n=12, seed=2, hmax=1.6)
    splash(coll, (ox - 5.8, -2.3, 1.25), t + 0.5, foam, drop, r=1.1, n=8, seed=3, hmax=1.0)
    ripples(coll, (ox + 2.1, -3.05, 0), t, foam, 1.8, 4.6, z=1.24)
    # mist puffs drifting off the big fall
    mist = flat_mat("Mist", (240, 248, 255), 0.6, alpha=0.18)
    rng = random.Random(6)
    for k in range(6):
        ph = (rng.random() + t) % 1.0
        fx_box(coll, (0.9 + ph, 0.9 + ph, 0.7 + ph * 0.5), (ox + 2.1 + rng.uniform(-1.5, 1.5), -3.2 - ph * 1.5, 1.6 + ph * 2.2), mist, (0, 0, rng.random()))


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
    sc.view_settings.view_transform = "AgX"
    sc.render.resolution_x, sc.render.resolution_y = 1280, 960
    sc.render.resolution_percentage = RES
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = rgb(186, 220, 255)
    ramp.color_ramp.elements[1].color = rgb(84, 150, 236)
    ramp.color_ramp.elements[1].position = 0.45
    nt.links.new(tc.outputs["Normal"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    coll = sc.collection
    # lawn (checker of two greens like the plaza grass), a paved pad per fountain, the boardwalk behind
    gm = bpy.data.materials.new("Lawn")
    gm.use_nodes = True
    gnt = gm.node_tree
    ck = gnt.nodes.new("ShaderNodeTexChecker")
    ck.inputs["Scale"].default_value = 60.0
    ck.inputs["Color1"].default_value = rgb(104, 196, 84)
    ck.inputs["Color2"].default_value = rgb(96, 186, 78)
    gnt.links.new(ck.outputs["Color"], gnt.nodes["Principled BSDF"].inputs["Base Color"])
    gnt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    box(coll, (300, 300, 1.0), (0, 40, -0.75), gm, 0.0)
    walk = flat_mat("Boardwalk", (196, 150, 104), 0.75)
    walk2 = flat_mat("Boardwalk2", (176, 132, 90), 0.75)
    for k in range(-80, 80):
        box(coll, (1.9, 7.0, 0.3), (k * 2.0, 24.0, -0.1), walk if k % 2 else walk2, 0.05)
    return coll


def pad(coll, ox):
    pv = Vox({"P": ((214, 214, 222),), "P2": ((196, 196, 206),), "E": ((166, 166, 180),)}, 1.0, seed=int(ox) + 99)
    pv.fill((-15, 15), (-15, 15), (-0.25, 0), lambda x, y, z: max(abs(x), abs(y), (abs(x) + abs(y)) / 1.38) <= 13.6, "P")
    pv.paint("P2", lambda x, y, z: True, only={"P"}, prob=0.35)
    pv.paint("E", lambda x, y, z: max(abs(x), abs(y), (abs(x) + abs(y)) / 1.38) > 12.6, only={"P", "P2"})
    pv.build(coll, "Pad", loc=(ox, 0, 0), jitter=0.03)


def sun():
    coll = bpy.context.scene.collection
    for name, rot, energy, col in (("Sun", (0.75, 0.15, -0.7), 3.6, (1.0, 0.95, 0.86)),
                                   ("Fill", (1.2, 0.0, 2.5), 0.9, (0.75, 0.82, 1.0))):
        L = bpy.data.lights.new(name, "SUN")
        L.energy, L.color, L.angle = energy, col, 0.1
        ob = bpy.data.objects.new(name, L)
        ob.rotation_euler = rot
        coll.objects.link(ob)


def shoot(path, cam_loc, target, lens=40, res=None, size=(1280, 960)):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = res or RES
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = cam_loc
    cam.rotation_euler = (V(target) - V(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[pitch]", path, flush=True)


VIEW = {"today": (1.0, 7.5), "a": (1.1, 9.5), "b": (0.85, 3.2), "c": (1.0, 7.5)}


def view(ox, key):
    """the 3/4 plaza view (the bug screenshot's angle: from the front-left, looking down ~30 deg)"""
    d, tz = VIEW[key]
    return (ox - 26.0 * d, -37.0 * d, tz + 16.5 * d), (ox + 0.5, 0.0, tz)


# ================================================================================ main
SP = 36.0
XS = {"today": -1.5 * SP, "a": -0.5 * SP, "b": 0.5 * SP, "c": 1.5 * SP}
BUILD = {"a": option_a, "b": option_b, "c": option_c}
coll = stage()
sun()
for key, x in XS.items():
    if ONLY & {key, "lineup"}:
        pad(coll, x)
        player(coll, (x - 12.2, -6.8, 0.0), face=-1.0)
if ONLY & {"today", "lineup"}:
    today(coll, XS["today"])
for key in "abc":
    if ONLY & {key, "lineup"}:
        BUILD[key](coll, XS[key], 0.0, fx=True)
for mp, per in SCROLL:
    mp.inputs["Location"].default_value[1] = 0.0

if "today" in ONLY:
    cl, tg = view(XS["today"], "today")
    shoot(os.path.join(OUT, "today_render.png"), cl, tg, 40)
for key in "abc":
    if key in ONLY:
        cl, tg = view(XS[key], key)
        shoot(os.path.join(OUT, "option_%s.png" % key), cl, tg, 40)
if "lineup" in ONLY:
    shoot(os.path.join(OUT, "lineup.png"), (0, -124.0, 26.0), (0, 0, 7.0), 32, size=(1600, 600))

FRAMES = (0.0, 0.25, 0.5, 0.75)
CLOSE = {"a": ((1.0, -17.0, 14.5), (4.8, 0.0, 6.2), 36),
         "b": ((-3.0, -21.0, 11.0), (3.0, -1.0, 4.5), 36),
         "c": ((-6.0, -24.0, 12.0), (1.0, -1.0, 6.5), 34)}
MKEYS = [k for k in "abc" if ONLY & {"motion", "motion_" + k}]
if MKEYS:
    MX = 1000.0  # the motion builds live away from the stills
    pad(coll, MX)
    for key in MKEYS:
        for fi, t in enumerate(FRAMES):
            names = set(o.name for o in bpy.data.objects)
            SCROLL.clear()
            FX.clear()
            BUILD[key](coll, MX, t, fx=True)
            for mp, per in SCROLL:
                mp.inputs["Location"].default_value[1] = -t * per
            cl, tg, lens = CLOSE[key]
            shoot(os.path.join(OUT, "_m_%s_%d.png" % (key, fi)), (cl[0] + MX, cl[1], cl[2]), (tg[0] + MX, tg[1], tg[2]),
                  lens, size=(640, 480))
            for o in [o for o in bpy.data.objects if o.name not in names]:
                bpy.data.objects.remove(o, do_unlink=True)
            FX.clear()

# labels + contact sheets (PIL ships with the bpy env)
try:
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("arialbd.ttf", 26)
        small = ImageFont.truetype("arialbd.ttf", 20)
    except Exception:
        font = small = ImageFont.load_default()

    def tag(d, xy, text, f):
        x, y = xy
        w = d.textlength(text, font=f)
        sz = getattr(f, "size", 12)
        d.rounded_rectangle((x - 8, y - 6, x + w + 8, y + sz + 8), 8, fill=(20, 28, 48, 210))
        d.text((x, y), text, font=f, fill=(255, 255, 255))
    lp = os.path.join(OUT, "lineup.png")
    if "lineup" in ONLY and os.path.isfile(lp):
        im = Image.open(lp).convert("RGBA")
        ov = Image.new("RGBA", im.size)
        d = ImageDraw.Draw(ov)
        W = im.size[0]
        for i, name in enumerate(("TODAY", "A  Rain-Catcher", "B  Nimbus' Bath", "C  Sky-Oasis Steps")):
            cx = int(W * (0.5 + (i - 1.5) * SP / 141.0))
            tag(d, (cx - int(d.textlength(name, font=font) / 2), 18), name, font)
        Image.alpha_composite(im, ov).convert("RGB").save(lp)
    for key in "abc":
        fr = [os.path.join(OUT, "_m_%s_%d.png" % (key, i)) for i in range(len(FRAMES))]
        if not all(os.path.isfile(f) for f in fr):
            continue
        ims = [Image.open(f).convert("RGBA") for f in fr]
        w, h = ims[0].size
        sheet = Image.new("RGBA", (w * 2 + 6, h * 2 + 6), (20, 28, 48, 255))
        for i, im in enumerate(ims):
            ov = Image.new("RGBA", im.size)
            d = ImageDraw.Draw(ov)
            tag(d, (14, 12), "%d/4   t = %.2f s" % (i + 1, FRAMES[i] * 0.8), small)
            sheet.paste(Image.alpha_composite(im, ov), ((i % 2) * (w + 6), (i // 2) * (h + 6)))
        sheet.convert("RGB").save(os.path.join(OUT, "motion_%s.png" % key))
        for f in fr:
            os.remove(f)
        print("[pitch] motion sheet", key, flush=True)
except ImportError:
    print("[pitch] PIL missing: no labels / contact sheets", flush=True)
print("[pitch] done", flush=True)
