"""Lobby ground / lawn design pitch (bug #12): three ground-dressing mock-ups + today's lawn, rendered in Blender.

    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe -I ground_pitch.py <out_dir> [--res 100] [--samples 32]
        [--only today,a,b,c,lineup,motion] [--kit <nimbus-climb/blender/kit>]

Every patch is the same 56 x 56-stud corner of the plaza lawn: an L of cream cobble walks (path top = 0, border -0.1,
lawn top -0.4, exactly LobbyBuilder's layer heights), the kit's REAL lobby props (prop_tree_round, prop_lamp,
prop_bench, prop_flowerbed, built in memory by blender/kit, nothing exported), a 5.3-stud R15-proportioned player and
a 2.5-stud pet stand-in. Only the ground dressing differs:

  today_render.png  flat 2 x 2 x 0.1-stud colour squares (LobbyBuilder plazaCell "Flower<n>" lawn pixels)
  option_a.png      A  The Groundskeeper's Lawn  (mown stripes, clover + daisy edges, long tufts where the mower can't reach)
  option_b.png      B  Wind-Sown Sky Meadow      (wind-leaning tufts, flower drifts blown out of a torn seed sack)
  option_c.png      C  Settlers' Cottage Garden  (one-species clumps in stone rings, stepping stones, box hedge)
  lineup.png        2 x 2 grid of the four, same camera, labelled
  motion_b.png      4-frame contact sheet of B's wind sway (client-side sway, one gust loop)

1 Blender unit = 1 stud, Z up, the camera's side is -Y. Read-only for game code. Prints the dressing triangle counts
per option (the budget numbers in PITCH_PROGRESS.md).
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector as V

ARGS = sys.argv[1:]
OUT = os.path.abspath(ARGS[0] if ARGS and not ARGS[0].startswith("--") else ".")


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

LZ = -0.4  # lawn top (LobbyBuilder LAWN = 0.4 under TOP); paths at 0, borders -0.1, lawn patches -0.3
H = 28.0   # patch half size


def lin(c):
    return (max(0.0, c) / 255.0) ** 2.2


def rgb(r, g, b, a=1.0):
    return (lin(r), lin(g), lin(b), a)


def hsh(*a):
    x = 0
    for i, v in enumerate(a):
        x ^= (int(v) * (73856093, 19349663, 83492791, 2654435761, 97)[i % 5]) & 0xFFFFFFFF
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    return (x % 10007) / 10007.0


def vnoise(x, y, scale, seed):
    """bilinear value noise 0..1"""
    fx, fy = x / scale, y / scale
    ix, iy = math.floor(fx), math.floor(fy)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a, b = hsh(ix, iy, seed), hsh(ix + 1, iy, seed)
    c, d = hsh(ix, iy + 1, seed), hsh(ix + 1, iy + 1, seed)
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def shade(col, f):
    return tuple(min(255, c * f) for c in col)


def mixc(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# ================================================================================ materials
_mats = {}


def vc_mat(name, rough=0.7, emit=0.0):
    """vertex-coloured SmoothPlastic look (colours baked per corner, like the kit's Fixed parts)"""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    if emit:
        nt.links.new(vc.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = emit
    _mats[name] = m
    return m


def flat_mat(name, col, rough=0.6, metal=0.0):
    key = (name, col, rough, metal)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = rgb(*col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    _mats[key] = m
    return m


# ================================================================================ batched geometry
class Batch:
    """many small boxes in one mesh with per-corner colours (fast, and the triangle count is the real budget)"""

    def __init__(self, name):
        self.name, self.verts, self.faces, self.cols = name, [], [], []

    def box(self, c, s, col, top=None, rz=0.0, lean=(0.0, 0.0), taper=1.0, bottom=False, z_is_base=True):
        """c = (x, y, z) with z the BASE height (z_is_base) or the centre; s = (sx, sy, sz); col = bottom colour,
        top = top colour (gradient); lean shears the top by (dx, dy) studs; taper scales the top face"""
        x, y, z = c
        sx, sy, sz = s
        if not z_is_base:
            z -= sz / 2
        top = top or col
        cr, sr = math.cos(rz), math.sin(rz)
        base = len(self.verts)
        for k, (zz, sc, (dx, dy)) in enumerate(((z, 1.0, (0.0, 0.0)), (z + sz, taper, lean))):
            for ux, uy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                px, py = ux * sx / 2 * sc, uy * sy / 2 * sc
                self.verts.append((x + px * cr - py * sr + dx, y + px * sr + py * cr + dy, zz))
        cb, ct = rgb(*col), rgb(*top)
        quads = [((4, 5, 6, 7), (ct,) * 4),
                 ((0, 1, 5, 4), (cb, cb, ct, ct)), ((1, 2, 6, 5), (cb, cb, ct, ct)),
                 ((2, 3, 7, 6), (cb, cb, ct, ct)), ((3, 0, 4, 7), (cb, cb, ct, ct))]
        if bottom:
            quads.append(((3, 2, 1, 0), (cb,) * 4))
        for idx, cc in quads:
            self.faces.append(tuple(base + i for i in idx))
            self.cols.append(cc)

    def tris(self):
        return 2 * len(self.faces)

    def build(self, coll, mat):
        if not self.faces:
            return None
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.verts, [], self.faces)
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        flat = []
        for cc in self.cols:
            for c4 in cc:
                flat.extend(c4)
        attr.data.foreach_set("color", flat)
        me.materials.append(mat)
        ob = bpy.data.objects.new(self.name, me)
        coll.objects.link(ob)
        return ob


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


def beam(coll, a, b, w, m, bevel=0.04, d=None):
    a, b = V(a), V(b)
    dv = b - a
    ob = box(coll, (w, d or w, dv.length), (a + b) / 2, m, bevel)
    ob.rotation_euler = dv.to_track_quat("Z", "Y").to_euler()
    return ob


# ================================================================================ plants (all into a Batch)
G_ROOT = (70, 138, 62)
G_MID = (98, 172, 80)
G_TIP = (140, 204, 98)
LEAF = (84, 156, 72)
LEAF_L = (112, 182, 88)


def blade(B, x, y, z, h, w, ang, lean, root, tip):
    """one blocky grass blade: a tapered leaning prism (10 tris, no bottom)"""
    B.box((x, y, z), (w, w * 0.8, h), root, tip, rz=ang, lean=(lean[0], lean[1]), taper=0.35)


def tuft(B, x, y, z, h, rng, n=4, wind=None, lean_k=0.15, root=G_ROOT, tip=G_TIP, spread=0.32):
    """n blades round (x, y); wind=(dx, dy) leans every blade that way (B), otherwise they splay outwards"""
    for i in range(n):
        a = TAU * i / n + rng.uniform(-0.5, 0.5)
        r = spread * rng.uniform(0.2, 1.0)
        bx, by = x + math.cos(a) * r, y + math.sin(a) * r
        hh = h * rng.uniform(0.7, 1.12)
        if wind:
            lx, ly = wind[0] * hh, wind[1] * hh
            lx += math.cos(a) * hh * 0.08
            ly += math.sin(a) * hh * 0.08
        else:
            lx, ly = math.cos(a) * hh * lean_k * 2.2, math.sin(a) * hh * lean_k * 2.2
        tcol = tip if rng.random() > 0.25 else shade(tip, 0.92)
        blade(B, bx, by, z - 0.02, hh, rng.uniform(0.2, 0.27), rng.uniform(0, 3), (lx, ly), root, tcol)


def petals(B, x, y, z, col, r=0.2, size=0.2, n=4, heart=(250, 214, 92), rot=0.0, thick=0.08):
    for i in range(n):
        a = rot + TAU * i / n
        B.box((x + math.cos(a) * r, y + math.sin(a) * r, z), (size, size, thick), col, shade(col, 1.06), rz=a)
    B.box((x, y, z + 0.02), (size * 0.8, size * 0.8, thick + 0.04), heart)


def stem(B, x, y, z, h, lean=(0.0, 0.0), w=0.08, col=LEAF):
    B.box((x, y, z), (w, w, h), shade(col, 0.85), col, lean=lean)


def daisy(B, x, y, z, rng, h=0.28):
    B.box((x, y, z), (0.32, 0.12, 0.05), LEAF, LEAF, rz=rng.uniform(0, 3))
    B.box((x, y, z), (0.12, 0.3, 0.05), LEAF_L, LEAF_L, rz=rng.uniform(0, 3))
    stem(B, x, y, z, h, w=0.06)
    petals(B, x, y, z + h, (246, 246, 240), r=0.13, size=0.13, n=5, rot=rng.uniform(0, 3), thick=0.05)


def clover(B, x, y, z, rng, bloom=False):
    rot = rng.uniform(0, TAU)
    for i in range(3):
        a = rot + TAU * i / 3
        B.box((x + math.cos(a) * 0.15, y + math.sin(a) * 0.15, z + 0.1), (0.2, 0.2, 0.06),
              (88, 168, 74), (104, 184, 84), rz=a)
    stem(B, x, y, z, 0.12, w=0.05)
    if bloom:
        stem(B, x + 0.1, y, z, 0.3, w=0.05)
        B.box((x + 0.1, y, z + 0.3), (0.2, 0.2, 0.18), (246, 240, 240), (250, 214, 226))


def wildflower(B, x, y, z, col, rng, h=None, wind=(0.0, 0.0)):
    h = h or rng.uniform(0.45, 0.75)
    lx, ly = wind[0] * h, wind[1] * h
    stem(B, x, y, z, h, lean=(lx, ly), w=0.07)
    B.box((x + lx * 0.4, y + ly * 0.4, z + h * 0.35), (0.22, 0.08, 0.05), LEAF_L, rz=rng.uniform(0, 3))
    petals(B, x + lx, y + ly, z + h, col, r=0.14, size=0.16, n=4, rot=rng.uniform(0, 3),
           heart=(250, 214, 92) if col != (250, 214, 92) else (230, 140, 60))


def cornflower(B, x, y, z, rng, wind=(0.0, 0.0)):
    h = rng.uniform(0.55, 0.85)
    lx, ly = wind[0] * h, wind[1] * h
    stem(B, x, y, z, h, lean=(lx, ly), w=0.06)
    petals(B, x + lx, y + ly, z + h, (96, 140, 236), r=0.12, size=0.14, n=6, heart=(70, 60, 150),
           rot=rng.uniform(0, 3))


def dandelion(B, x, y, z, rng, clock=False, wind=(0.0, 0.0)):
    for i in range(3):  # toothed leaves flat on the ground
        a = rng.uniform(0, TAU)
        B.box((x + math.cos(a) * 0.22, y + math.sin(a) * 0.22, z), (0.5, 0.14, 0.05), (78, 150, 66), rz=a)
    h = rng.uniform(0.5, 0.8) if not clock else rng.uniform(0.8, 1.0)
    lx, ly = wind[0] * h * 0.6, wind[1] * h * 0.6
    stem(B, x, y, z, h, lean=(lx, ly), w=0.06, col=(120, 170, 90))
    if clock:
        B.box((x + lx, y + ly, z + h - 0.05), (0.34, 0.34, 0.34), (236, 238, 232), (250, 250, 248))
        for i in range(6):
            a = TAU * i / 6
            B.box((x + lx + math.cos(a) * 0.2, y + ly + math.sin(a) * 0.2, z + h + 0.03), (0.12, 0.12, 0.12),
                  (250, 250, 248))
    else:
        B.box((x + lx, y + ly, z + h), (0.3, 0.3, 0.14), (240, 190, 50), (252, 216, 70))


def tulip(B, x, y, z, col, rng):
    h = rng.uniform(0.8, 1.05)
    for s in (-1, 1):  # two long leaves
        a = rng.uniform(0, TAU)
        B.box((x + math.cos(a) * 0.1, y + math.sin(a) * 0.1, z), (0.16, 0.08, 0.55), LEAF, LEAF_L, rz=a,
              lean=(math.cos(a) * 0.18, math.sin(a) * 0.18), taper=0.5)
    stem(B, x, y, z, h, w=0.07)
    rot = rng.uniform(0, 1.5)
    for i in range(4):  # the cup
        a = rot + TAU * i / 4
        B.box((x + math.cos(a) * 0.1, y + math.sin(a) * 0.1, z + h - 0.06), (0.16, 0.16, 0.36), shade(col, 0.82), col,
              rz=a, lean=(math.cos(a) * 0.04, math.sin(a) * 0.04))
    B.box((x, y, z + h - 0.04), (0.2, 0.2, 0.3), shade(col, 0.7))


def lupin(B, x, y, z, col, rng):
    for i in range(5):  # palm leaves
        a = TAU * i / 5 + rng.uniform(-0.3, 0.3)
        B.box((x + math.cos(a) * 0.25, y + math.sin(a) * 0.25, z + 0.18), (0.36, 0.12, 0.05), LEAF, LEAF_L, rz=a)
    stem(B, x, y, z, 0.6, w=0.09)
    h0 = 0.55
    n = 7
    for k in range(n):
        t = k / (n - 1)
        s = 0.34 - 0.2 * t
        c = mixc(col, (250, 246, 250), t * 0.45)
        B.box((x, y, z + h0 + k * 0.19), (s, s, 0.2), shade(c, 0.85), c, rz=k * 0.5)


def forgetmenot(B, x, y, z, rng):
    B.box((x, y, z), (0.6, 0.6, 0.16), LEAF, (96, 170, 80), rz=rng.uniform(0, 3))
    for i in range(7):
        a, r = rng.uniform(0, TAU), rng.uniform(0, 0.3)
        B.box((x + math.cos(a) * r, y + math.sin(a) * r, z + 0.16), (0.11, 0.11, 0.07),
              (120, 170, 246) if i % 5 else (250, 230, 120))


def stone(B, x, y, z, w, d, h, rng, col=(178, 172, 162), moss=0.0):
    rz = rng.uniform(0, 3)
    top = shade(col, 1.08)
    B.box((x, y, z - 0.1), (w, d, h + 0.1), shade(col, 0.82), top, rz=rz, taper=0.86)
    if moss and rng.random() < moss:
        B.box((x + w * 0.15, y, z + h - 0.01), (w * 0.45, d * 0.4, 0.04), (98, 160, 76), rz=rz)


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


def pet(coll, loc, face=0.0):
    """a 2.5-stud blocky fox-cub stand-in (the lobby pets in the screenshot): body, head, ears, tail"""
    fur = flat_mat("PetFur", (236, 146, 70), 0.7)
    cream = flat_mat("PetCream", (250, 236, 214), 0.7)
    dark = flat_mat("PetDark", (40, 34, 40), 0.5)
    parts = [box(coll, (1.3, 1.6, 0.9), (0, 0.2, 0.75), fur, 0.15),
             box(coll, (1.5, 1.3, 1.25), (0, -0.85, 1.75), fur, 0.2),
             box(coll, (1.1, 0.3, 0.6), (0, -1.5, 1.5), cream, 0.1),
             box(coll, (0.5, 0.9, 0.5), (0, 1.3, 1.1), fur, 0.1),
             box(coll, (0.45, 0.5, 0.45), (0, 1.75, 1.35), cream, 0.1)]
    for sx in (-0.45, 0.45):
        parts.append(box(coll, (0.38, 0.3, 0.55), (sx, -0.85, 2.55), fur, 0.06))
        parts.append(box(coll, (0.18, 0.06, 0.24), (sx * 0.65, -1.52, 1.95), dark, 0.0))
        for sy in (-0.35, 0.75):
            parts.append(box(coll, (0.35, 0.35, 0.35), (sx * 0.9, sy, 0.175), fur, 0.06))
    root = bpy.data.objects.new("Pet", None)
    coll.objects.link(root)
    for p in parts:
        p.parent = root
    root.location = loc
    root.rotation_euler = (0, 0, face)
    return root


# ================================================================================ the shared patch
FLOWERS = [(246, 150, 188), (250, 214, 92), (244, 244, 248), (172, 142, 232), (236, 104, 108), (112, 172, 240)]
GRASS, GRASS_L, GRASS_D = (108, 186, 86), (132, 202, 98), (86, 160, 76)
STONE, STONE_L, STONE_EDGE = (208, 202, 190), (226, 221, 209), (146, 138, 132)

# local layout (studs; the camera looks from -Y, -X)
PATH_L = (-22.0, -15.0)   # the west walk, x range
PATH_B = (15.0, 22.0)     # the north walk, y range
TREE = (13.0, 0.0)
LAMP = (-12.6, 12.4)
BENCH = (7.0, 12.2)
BED = (-2.0, 9.0)
PLAYER = (-2.5, -4.0)
PET = (-6.5, -8.5)


def path_dist(x, y):
    """distance from (x, y) to the nearest walk (0 inside)"""
    dl = max(PATH_L[0] - x, x - PATH_L[1], 0.0)
    db = max(PATH_B[0] - y, y - PATH_B[1], 0.0)
    return min(dl, db)


def on_path(x, y, m=0.0):
    return (PATH_L[0] - m <= x <= PATH_L[1] + m) or (PATH_B[0] - m <= y <= PATH_B[1] + m)


def blocked(x, y, m=0.0):
    """props' footprints (+ margin m): nothing grows through them"""
    if on_path(x, y, m):
        return True
    if math.hypot(x - TREE[0], y - TREE[1]) < 2.3 + m:
        return True
    if math.hypot(x - LAMP[0], y - LAMP[1]) < 1.2 + m:
        return True
    if abs(x - BED[0]) < 3.2 + m and abs(y - BED[1]) < 2.2 + m:
        return True
    if abs(x - BENCH[0]) < 2.9 + m and BENCH[1] - 1.0 - m < y < BENCH[1] + 1.3 + m:
        return True
    return False


def lawn_cells(B, colfn):
    """the lawn: 2-stud cells (LobbyBuilder's ground grid), top at LZ"""
    n = int(H / 2)
    for i in range(-n, n):
        for k in range(-n, n):
            x, y = i * 2 + 1.0, k * 2 + 1.0
            if on_path(x, y):
                continue
            B.box((x, y, LZ - 2.0), (2.0, 2.0, 2.0), colfn(x, y), bottom=False)


def game_lawn_colour(x, y):
    n = vnoise(x + 400, y + 400, 14, 11)
    return GRASS_D if n < 0.2 else (GRASS_L if n > 0.8 else GRASS)


def walks(B):
    """cream cobble walks: StoneEdge borders (-0.1) 1 stud wide, cobbles (0) in two shades"""
    n = int(H)
    for i in range(-n, n):
        for k in range(-n, n):
            x, y = i + 0.5, k + 0.5
            if not on_path(x, y):
                continue
            inner_l = PATH_L[0] + 1 <= x <= PATH_L[1] - 1
            inner_b = PATH_B[0] + 1 <= y <= PATH_B[1] - 1
            in_l = PATH_L[0] <= x <= PATH_L[1]
            in_b = PATH_B[0] <= y <= PATH_B[1]
            surface = (in_l and inner_l) or (in_b and inner_b)
            if in_l and in_b:
                surface = inner_l or inner_b
            if surface and (i % 2 == 0) and (k % 2 == 0):
                c = STONE_L if vnoise(x + 1300, y + 1300, 9, 3) > 0.5 else STONE
                c = shade(c, 0.96 + 0.08 * hsh(i, k, 5))
                B.box((x + 0.5, y + 0.5, -1.0), (1.94, 1.94, 1.0), shade(c, 0.9), c)
            elif not surface:
                B.box((x, y, -1.1), (1.0, 1.0, 1.0), STONE_EDGE)


KIT_OBJS = {}


def kit_props():
    """the kit's real lobby props, built once in memory (nothing exported)"""
    if KIT_OBJS:
        return KIT_OBJS
    sys.path.insert(0, os.path.abspath(KIT))
    sys.dont_write_bytecode = True
    import props
    from nvox import blend as Bl
    reg = props.load_all()
    hold = bpy.data.collections.new("KitHold")  # not linked to the scene: templates only
    for key, prop, args, look in (("prop_tree_round", "lobby_tree", {"kind": "Round"}, None),
                                  ("prop_lamp", "lobby_lamp", None, None),
                                  ("prop_bench", "lobby_bench", None, None),
                                  ("prop_flowerbed", "lobby_flowerbed", None,
                                   {"Primary": (246 / 255, 150 / 255, 188 / 255),
                                    "Secondary": (250 / 255, 214 / 255, 92 / 255)})):
        e = {"key": key, "prop": prop}
        if args:
            e["args"] = args
        m = reg[prop](e, props.PropKit())
        KIT_OBJS[key] = Bl.make_objects(m, look, collection=hold)
    return KIT_OBJS


def place_kit(coll, key, loc, rz=0.0):
    for src in kit_props()[key]:
        ob = src.copy()
        coll.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (0, 0, rz)


def patch(coll, ox, name, lawn_colfn):
    B = Batch(name + "_ground")
    lawn_cells(B, lawn_colfn)
    walks(B)
    B.verts = [(v[0] + ox, v[1], v[2]) for v in B.verts]
    B.build(coll, vc_mat("Ground", 0.8))
    place_kit(coll, "prop_tree_round", (ox + TREE[0], TREE[1], LZ), 0.6)
    place_kit(coll, "prop_lamp", (ox + LAMP[0], LAMP[1], LZ))
    place_kit(coll, "prop_bench", (ox + BENCH[0], BENCH[1], LZ))
    place_kit(coll, "prop_flowerbed", (ox + BED[0], BED[1], LZ))
    player(coll, (ox + PLAYER[0], PLAYER[1], LZ), face=-0.45)
    pet(coll, (ox + PET[0], PET[1], LZ), face=-0.9)


def shifted(B, ox):
    B.verts = [(v[0] + ox, v[1], v[2]) for v in B.verts]
    return B


TRIS = {}
DRESS_MAT = None


def dress_mat():
    return vc_mat("Dressing", 0.65)


# ================================================================================ TODAY
def today(coll, ox):
    patch(coll, ox, "today", game_lawn_colour)
    B = Batch("today_pixels")
    n = int(H / 2)
    for i in range(-n, n):
        for k in range(-n, n):
            x, y = i * 2 + 1.0, k * 2 + 1.0
            if on_path(x, y, 0.5):
                continue
            meadow = vnoise(x + 900, y + 900, 12, 5) > 0.7
            h = hsh(i, k, 21)
            if (meadow and h < 0.12) or h < 0.035:
                B.box((x, y, LZ), (2.0, 2.0, 0.1), FLOWERS[int(hsh(i, k, 4) * 6)])
    # LobbyBuilder lays the flower pixels before the trees (plazaCell ignores the decor reserves): one under the roots
    B.box((TREE[0] - 1.0, TREE[1] - 3.0, LZ), (2.0, 2.0, 0.1), FLOWERS[0])
    TRIS["today"] = B.tris()
    shifted(B, ox).build(coll, dress_mat())


# ================================================================================ A: The Groundskeeper's Lawn
STRIPE_A, STRIPE_B = (126, 204, 96), (96, 172, 78)
SHORTCUT = ((-15.0, -9.0), (-8.0, 15.0))
SOIL, SOIL_D = (156, 122, 86), (132, 102, 72)


def shortcut_d(x, y):
    (ax, ay), (bx, by) = SHORTCUT
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - (ax + dx * t), y - (ay + dy * t))


def lawn_a(x, y):
    band = int(math.floor((y + H) / 4.0)) % 2
    c = STRIPE_A if band else STRIPE_B
    return shade(c, 0.98 + 0.04 * vnoise(x, y, 6, 2))


def option_a(coll, ox):
    patch(coll, ox, "a", lawn_a)
    B = Batch("a_dress")
    rng = random.Random(11)
    # the worn shortcut: players cut the corner between the two walks (1-stud soil cells, ragged edge)
    for i in range(-16, -5):
        for k in range(-12, 16):
            x, y = i + 0.5, k + 0.5
            if on_path(x, y):
                continue
            d = shortcut_d(x, y)
            w = 0.9 + 0.5 * vnoise(x, y, 3, 8)
            if d < w:
                c = SOIL if hsh(i, k, 3) > 0.35 else SOIL_D
                B.box((x, y, LZ - 0.05), (1.0, 1.0, 0.07), c, shade(c, 1.04))
            elif d < w + 0.9 and hsh(i, k, 9) < 0.45:  # trampled, thinner grass at its edge
                B.box((x + rng.uniform(-0.2, 0.2), y + rng.uniform(-0.2, 0.2), LZ - 0.02), (0.6, 0.6, 0.05),
                      (132, 170, 92))
    # clover + daisy edging along every lawn edge that meets a walk (0.4 .. 2.0 studs from the border)
    for i in range(int(-H * 2), int(H * 2)):
        for k in range(int(-H * 2), int(H * 2)):
            x, y = i * 0.5 + 0.25, k * 0.5 + 0.25
            if blocked(x, y, 0.2) or shortcut_d(x, y) < 1.8:
                continue
            d = path_dist(x, y)
            if 0.35 < d < 2.0:
                h = hsh(i, k, 31)
                p = 0.34 * (1 - d / 2.0) + 0.05
                if h < p * 0.55:
                    clover(B, x + rng.uniform(-0.15, 0.15), y + rng.uniform(-0.15, 0.15), LZ, rng, bloom=h < p * 0.12)
                elif h < p:
                    daisy(B, x + rng.uniform(-0.15, 0.15), y + rng.uniform(-0.15, 0.15), LZ, rng)
    # long tufts only where the mower can't reach: round the trunk, the lamp foot, the bench legs, the bed's sides
    long_root, long_tip = (66, 130, 58), (112, 182, 84)
    for i in range(18):
        a = TAU * i / 18 + rng.uniform(-0.12, 0.12)
        r = rng.uniform(2.2, 3.0)
        tuft(B, TREE[0] + math.cos(a) * r, TREE[1] + math.sin(a) * r, LZ, rng.uniform(0.8, 1.2), rng, 5,
             root=long_root, tip=long_tip)
    for i in range(8):
        a = TAU * i / 8 + rng.uniform(-0.2, 0.2)
        tuft(B, LAMP[0] + math.cos(a) * 1.25, LAMP[1] + math.sin(a) * 1.25, LZ, rng.uniform(0.7, 1.0), rng, 4,
             root=long_root, tip=long_tip)
    for sx in (-2.4, 2.4):
        for sy in (-0.75, 1.05):
            for j in range(2):
                tuft(B, BENCH[0] + sx + rng.uniform(-0.45, 0.45), BENCH[1] + sy + (-0.45 if sy < 0 else 0.45) * (j + 1) * 0.6,
                     LZ, rng.uniform(0.6, 0.9), rng, 4, root=long_root, tip=long_tip)
    for j in range(16):  # along the bed's planks, where the mower deck can't go
        t = j / 15
        if j % 2:
            x, y = BED[0] - 3.0 + t * 6.0, BED[1] - 2.35
        else:
            x, y = BED[0] - 3.35 + (6.7 if j % 4 == 0 else 0), BED[1] - 1.8 + t * 3.6
        tuft(B, x, y, LZ, rng.uniform(0.6, 0.95), rng, 4, root=long_root, tip=long_tip)
    # Gemini's detail: the lamp-lighter's swept pile of clippings at the lamp foot
    for j in range(46):
        a, r = rng.uniform(-1.2, 0.9), rng.uniform(1.4, 2.4)
        hgt = 0.25 * (1 - (r - 1.4) / 1.0) + 0.05
        B.box((LAMP[0] + math.cos(a) * r, LAMP[1] - 0.6 + math.sin(a) * r * 0.6, LZ),
              (0.24, 0.24, rng.uniform(0.05, max(0.06, hgt))), (150, 190, 96), (176, 206, 110), rz=rng.uniform(0, 3))
    TRIS["a"] = B.tris()
    shifted(B, ox).build(coll, dress_mat())
    # a rake leaning on the trunk; the ignored "keep off the grass" sign at the shortcut, knocked crooked
    wood = flat_mat("RakeWood", (176, 128, 84), 0.7)
    iron = flat_mat("RakeIron", (90, 96, 112), 0.4, 0.4)
    tx, ty = ox + TREE[0], TREE[1]
    base = V((tx - 3.4, ty - 1.4, LZ + 0.05))
    topp = V((tx - 1.05, ty - 0.55, LZ + 4.3))
    beam(coll, base, topp, 0.16, wood)
    head = box(coll, (1.3, 0.22, 0.16), base + V((0, 0, 0.1)), iron, 0.03)
    head.rotation_euler = (0, 0, math.atan2(topp.y - base.y, topp.x - base.x) + math.pi / 2)
    for j in range(6):
        u = (j - 2.5) * 0.22
        ang = head.rotation_euler.z
        box(coll, (0.06, 0.06, 0.2), base + V((math.cos(ang) * u, math.sin(ang) * u, -0.04)), iron, 0.0)
    sx, sy = ox - 13.0, -10.0
    post = beam(coll, (sx, sy, LZ - 0.2), (sx + 0.35, sy + 0.1, LZ + 2.3), 0.2, wood)
    board = box(coll, (1.9, 0.12, 0.85), (sx + 0.32, sy - 0.12, LZ + 2.15), flat_mat("SignBoard", (238, 228, 206), 0.7), 0.04)
    board.rotation_euler = (0.0, -0.16, -0.35)
    red = flat_mat("SignPaint", (196, 70, 64), 0.6)
    for j, (w, dz) in enumerate(((1.3, 0.2), (0.9, -0.05), (1.1, -0.25))):
        bar = box(coll, (w, 0.03, 0.1), (0, 0, 0), red, 0.0)
        bar.parent = board
        bar.location = (-(1.3 - w) / 2 + 0.0, -0.075, dz + 0.02)


# ================================================================================ B: Wind-Sown Sky Meadow
WIND = (0.25, -0.31)  # lean per stud of height (prevailing wind: east and toward the camera; DRIFT is its unit vector)
DRIFT = (0.62, -0.78)
SACK = (2.2, 7.0)


def lawn_b(x, y):
    n = vnoise(x + 400, y + 400, 14, 11)
    return (104, 182, 84) if n < 0.3 else ((122, 196, 92) if n > 0.72 else (112, 189, 88))


def wind_at(x, y, t):
    """gusts travel downwind (+X): lean multiplier per position and loop phase"""
    g = 1.0 + 0.75 * math.sin(TAU * (t - x / 22.0 + y / 70.0))
    return (WIND[0] * g, WIND[1] * g)


def option_b(coll, ox, t=0.0, props_too=True):
    if props_too:
        patch(coll, ox, "b", lawn_b)
    B = Batch("b_dress")
    rng = random.Random(23)
    straw_tip, tip, root = (196, 204, 120), (148, 208, 100), (72, 140, 62)
    # meadow tufts: jittered 1.25-stud grid, clumpy by noise, thinning to bare lawn within 2.5 studs of a walk
    step = 1.25
    n = int(H / step)
    for i in range(-n, n):
        for k in range(-n, n):
            x = i * step + (hsh(i, k, 1) - 0.5) * step * 0.9
            y = k * step + (hsh(i, k, 2) - 0.5) * step * 0.9
            if blocked(x, y, 0.25):
                continue
            d = path_dist(x, y)
            near = max(0.0, min(1.0, (d - 1.2) / 2.3))
            dens = (0.25 + 0.75 * vnoise(x + 50, y, 7, 4)) * near
            if hsh(i, k, 3) > dens * 0.75:
                continue
            h = (0.45 + 0.5 * vnoise(x, y + 70, 5, 6)) * (0.6 + 0.4 * near)
            w = wind_at(x, y, t)
            tuft(B, x, y, LZ, h, rng, 4 if h > 0.6 else 3, wind=w, root=root,
                 tip=straw_tip if vnoise(x - 30, y, 6, 9) > 0.68 else tip)
    # the drift: wildflowers blown out of the torn seed sack by the bed, a long comet downwind
    for j in range(150):
        s = rng.random() ** 1.6 * 24.0
        lat = rng.gauss(0, 0.6 + s * 0.22)
        x = SACK[0] + 1.0 + s * DRIFT[0] - lat * DRIFT[1]
        y = SACK[1] - 0.6 + s * DRIFT[1] + lat * DRIFT[0]
        if blocked(x, y, 0.3) or abs(x) > H - 0.5 or abs(y) > H - 0.5:
            continue
        col = (246, 150, 188) if rng.random() < 0.46 else ((250, 214, 92) if rng.random() < 0.85 else (244, 244, 248))
        wildflower(B, x, y, LZ, col, rng, wind=wind_at(x, y, t))
    # blue cornflowers and dandelions dotted through the meadow (the wind's other passengers)
    for j in range(60):
        x, y = rng.uniform(-H, H), rng.uniform(-H, H)
        if blocked(x, y, 0.4) or path_dist(x, y) < 1.5:
            continue
        if j % 3 == 0:
            dandelion(B, x, y, LZ, rng, clock=(j % 9 == 0), wind=wind_at(x, y, t))
            if j % 9 == 0:  # Gemini's detail: a few seeds already in the air, flying with the wind
                for q in range(4):
                    s = ((q + 0.3) / 4.0 + t) % 1.0
                    B.box((x + 0.3 + s * 6.5 * DRIFT[0], y + s * 6.5 * DRIFT[1], LZ + 1.0 + s * 1.6 + 0.35 * math.sin(TAU * (s * 2 + q * 0.3))),
                          (0.12, 0.12, 0.12), (250, 250, 248))
        else:
            cornflower(B, x, y, LZ, rng, wind=wind_at(x, y, t))
    # spilled seed in front of the sack
    for j in range(40):
        s = rng.random() * 2.6
        B.box((SACK[0] + 0.9 + s * DRIFT[0], SACK[1] - 0.5 + s * DRIFT[1] + rng.gauss(0, 0.25), LZ), (0.1, 0.1, 0.06), (214, 190, 130))
    TRIS["b"] = B.tris()
    dress = shifted(B, ox).build(coll, dress_mat())
    if props_too:
        # the torn seed sack slumped against the bed's corner (canvas, a rope tie, a tear on the downwind side)
        canvas = flat_mat("Canvas", (206, 184, 140), 0.85)
        canvas_d = flat_mat("CanvasDark", (170, 148, 108), 0.85)
        rope = flat_mat("Rope", (150, 116, 76), 0.8)
        sx, sy = ox + SACK[0], SACK[1]
        b1 = box(coll, (1.25, 0.95, 1.0), (sx, sy, LZ + 0.48), canvas, 0.3)
        b1.rotation_euler = (0.25, -0.35, 0.3)
        b2 = box(coll, (0.75, 0.6, 0.45), (sx - 0.35, sy + 0.12, LZ + 1.12), canvas_d, 0.18)
        b2.rotation_euler = (0.2, -0.6, 0.3)
        b3 = box(coll, (0.5, 0.4, 0.14), (sx - 0.52, sy + 0.16, LZ + 1.4), rope, 0.05)
        b3.rotation_euler = (0.2, -0.6, 0.3)
        tear = box(coll, (0.08, 0.5, 0.35), (sx + 0.64, sy - 0.08, LZ + 0.35), flat_mat("Seed", (214, 190, 130), 0.9), 0.02)
        tear.rotation_euler = (0, 0, 0.3)
    return dress


# ================================================================================ C: Settlers' Cottage Garden
TULIPS = (8.0, -6.5)
LUPINS = (-9.5, 3.0)
STEPS = [(-13.6, -1.2), (-10.6, -0.4), (-7.4, 0.4), (-4.2, 1.6), (-1.0, 3.2), (2.0, 5.0), (4.4, 7.3), (6.4, 9.6)]


def lawn_c(x, y):
    n = vnoise(x + 400, y + 400, 14, 11)
    return (100, 180, 82) if n < 0.25 else ((124, 196, 94) if n > 0.78 else (112, 188, 88))


def ring_of_stones(B, cx, cy, r, n, rng):
    for i in range(n):
        a = TAU * i / n + rng.uniform(-0.08, 0.08)
        stone(B, cx + math.cos(a) * r, cy + math.sin(a) * r, LZ, rng.uniform(0.55, 0.8), rng.uniform(0.45, 0.6),
              rng.uniform(0.2, 0.28), rng, moss=0.35)
    # the turned soil inside the ring
    B.box((cx, cy, LZ - 0.05), (r * 1.55, r * 1.55, 0.08), (120, 86, 64), (126, 92, 68), rz=0.4)


def option_c(coll, ox):
    patch(coll, ox, "c", lawn_c)
    B = Batch("c_dress")
    rng = random.Random(37)
    # 1. tulips: one species, one colour... and one yellow bulb that got mixed into the bag
    ring_of_stones(B, *TULIPS, 1.9, 13, rng)
    k = 0
    for i in range(-2, 3):
        for j in range(-2, 3):
            x, y = TULIPS[0] + i * 0.55 + rng.uniform(-0.1, 0.1), TULIPS[1] + j * 0.55 + rng.uniform(-0.1, 0.1)
            if math.hypot(x - TULIPS[0], y - TULIPS[1]) > 1.35:
                continue
            k += 1
            tulip(B, x, y, LZ, (250, 214, 92) if k == 7 else (224, 62, 72), rng)
    # 2. lupins (they come up mixed: violet, blue, pink) + the child's painted plant marker
    ring_of_stones(B, *LUPINS, 1.7, 12, rng)
    for i, (dx, dy) in enumerate(((0, 0), (0.6, 0.3), (-0.6, 0.2), (0.2, -0.6), (-0.4, -0.55), (0.55, -0.4),
                                  (-0.1, 0.7), (-0.75, -0.15))):
        lupin(B, LUPINS[0] + dx, LUPINS[1] + dy, LZ, ((150, 108, 222), (96, 132, 232), (236, 142, 186))[i % 3], rng)
    # 3. forget-me-nots between the tree's roots, inside a ring of stones
    ring_of_stones(B, *TREE, 3.2, 20, rng)
    for i in range(14):
        a = TAU * i / 14 + rng.uniform(-0.2, 0.2)
        r = rng.uniform(2.35, 2.75)
        forgetmenot(B, TREE[0] + math.cos(a) * r, TREE[1] + math.sin(a) * r, LZ, rng)
    # stepping stones from the west walk to the bench (0.18 proud: inside the lawn layers' 0.3-stud step rule)
    for i, (x, y) in enumerate(STEPS):
        r2 = random.Random(100 + i)
        B.box((x, y, LZ - 0.1), (1.55, 1.25, 0.28), (168, 162, 152), (196, 190, 178), rz=r2.uniform(-0.5, 0.5), taper=0.92)
        B.box((x + 0.35, y - 0.3, LZ + 0.17), (0.4, 0.3, 0.03), (104, 166, 80), rz=0.3)  # moss in a corner
    # low box hedge along the north walk (gaps at the bench and the lamp), 0.8 stud: never hides a pet
    for x0, x1 in ((-10.6, 2.6), (11.4, H)):
        x = x0
        while x < x1:
            w = min(0.9, x1 - x)
            c = (74, 146, 72) if hsh(int(x * 10), 1, 4) > 0.4 else (100, 170, 84)
            B.box((x + w / 2, 14.1, LZ), (w + 0.05, 1.05, 0.72 + 0.12 * hsh(int(x * 10), 2, 4)), shade(c, 0.8), c)
            x += w
    # short grass left standing against the stones and the hedge foot (the shears don't get in there)
    for (cx, cy, r, n) in ((TULIPS[0], TULIPS[1], 2.35, 12), (LUPINS[0], LUPINS[1], 2.15, 11), (TREE[0], TREE[1], 3.65, 16)):
        for i in range(n):
            a = TAU * (i + rng.random() * 0.6) / n
            tuft(B, cx + math.cos(a) * r, cy + math.sin(a) * r, LZ, rng.uniform(0.4, 0.6), rng, 3, spread=0.25)
    for i in range(26):
        x = rng.uniform(-10.4, H - 0.5)
        if 2.4 < x < 11.6:
            continue
        tuft(B, x, 13.45, LZ, rng.uniform(0.35, 0.55), rng, 3, spread=0.22)
    # a few self-seeded daisies the settlers leave alone
    for j in range(40):
        x, y = rng.uniform(-H, H), rng.uniform(-H, H)
        if blocked(x, y, 0.5) or path_dist(x, y) < 0.8 or math.hypot(x - TULIPS[0], y - TULIPS[1]) < 2.6 \
                or math.hypot(x - LUPINS[0], y - LUPINS[1]) < 2.4 or y > 13.2:
            continue
        daisy(B, x, y, LZ, rng)
    TRIS["c"] = B.tris()
    shifted(B, ox).build(coll, dress_mat())
    # the watering can by the tulips; the painted plant marker (Gemini: a child's crooked lupin doodle)
    zinc = flat_mat("Zinc", (126, 168, 150), 0.45, 0.3)
    zinc_d = flat_mat("ZincDark", (96, 132, 118), 0.45, 0.3)
    wx, wy = ox + TULIPS[0] - 2.4, TULIPS[1] - 1.5
    body = box(coll, (1.0, 0.68, 0.85), (wx, wy, LZ + 0.425), zinc, 0.1)
    body.rotation_euler = (0, 0, 0.5)
    beam(coll, (wx - 0.25, wy - 0.15, LZ + 0.35), (wx - 0.95, wy - 0.55, LZ + 0.95), 0.12, zinc_d)
    box(coll, (0.24, 0.24, 0.12), (wx - 0.98, wy - 0.57, LZ + 0.98), zinc_d, 0.03)
    beam(coll, (wx + 0.15, wy + 0.1, LZ + 0.7), (wx + 0.3, wy + 0.2, LZ + 1.05), 0.08, zinc_d)
    beam(coll, (wx + 0.3, wy + 0.2, LZ + 1.05), (wx - 0.15, wy - 0.05, LZ + 1.05), 0.08, zinc_d)
    mx, my = ox + LUPINS[0] - 1.25, LUPINS[1] - 1.0
    beam(coll, (mx, my, LZ - 0.2), (mx + 0.08, my, LZ + 1.15), 0.09, flat_mat("Stake", (176, 128, 84), 0.7))
    board = box(coll, (0.85, 0.08, 0.6), (mx + 0.07, my - 0.07, LZ + 1.25), flat_mat("MarkerBoard", (244, 236, 214), 0.7), 0.03)
    board.rotation_euler = (0.12, 0.0, 0.25)
    doodle = flat_mat("Doodle", (150, 108, 222), 0.6)
    for q, (dx, dz, s) in enumerate(((-0.05, -0.18, 0.13), (-0.02, -0.06, 0.11), (0.03, 0.05, 0.09), (0.07, 0.14, 0.07))):
        d = box(coll, (s, 0.03, 0.1), (0, 0, 0), doodle, 0.0)
        d.parent = board
        d.location = (dx - 0.12, -0.05, dz)
    st = box(coll, (0.04, 0.03, 0.3), (0, 0, 0), flat_mat("DoodleStem", (90, 150, 70), 0.6), 0.0)
    st.parent = board
    st.location = (-0.15, -0.05, -0.2)
    st.rotation_euler = (0, 0.25, 0)
    for q in range(3):  # a wobbly pencil-line border
        d = box(coll, (0.06, 0.03, 0.06), (0, 0, 0), flat_mat("Pencil", (70, 70, 84), 0.6), 0.0)
        d.parent = board
        d.location = (0.22, -0.05, -0.15 + q * 0.16)


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
    try:
        sc.eevee.use_shadows = True
    except Exception:
        pass
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
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
    bg.inputs["Strength"].default_value = 0.75
    coll = sc.collection
    # the lawn that continues beyond every patch (plain game grass, just under the patch tops)
    box(coll, (600, 400, 1.0), (0, 0, LZ - 0.55), flat_mat("FarLawn", GRASS, 0.85), 0.0)
    return coll


def sun():
    coll = bpy.context.scene.collection
    for name, rot, energy, col in (("Sun", (0.72, 0.18, -0.75), 2.6, (1.0, 0.95, 0.86)),
                                   ("Fill", (1.2, 0.0, 2.5), 0.5, (0.75, 0.82, 1.0))):
        L = bpy.data.lights.new(name, "SUN")
        L.energy, L.color, L.angle = energy, col, 0.08
        ob = bpy.data.objects.new(name, L)
        ob.rotation_euler = rot
        coll.objects.link(ob)


def shoot(path, cam_loc, target, lens=35, size=(1280, 960)):
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


def view(ox):
    """the bug screenshot's high 3rd-person angle: from the front-left, ~35 deg down, the player mid-frame"""
    return (ox - 14.0, -36.0, 24.0), (ox + 2.0, 2.5, 0.5)


# ================================================================================ main
SP = 70.0
XS = {"today": -1.5 * SP, "a": -0.5 * SP, "b": 0.5 * SP, "c": 1.5 * SP}
coll = stage()
sun()
need = {k for k in XS if ONLY & {k, "lineup"}}
if "today" in need:
    today(coll, XS["today"])
if "a" in need:
    option_a(coll, XS["a"])
if "b" in need:
    option_b(coll, XS["b"])
if "c" in need:
    option_c(coll, XS["c"])

lawn_area = sum(1 for i in range(-56, 56) for k in range(-56, 56) if not on_path(i * 0.5 + 0.25, k * 0.5 + 0.25)) * 0.25
print("[pitch] lawn area per patch %.0f sq studs" % lawn_area, flush=True)
for key, t in sorted(TRIS.items()):
    print("[pitch] dressing tris %s = %d  (%.0f per 100 sq studs)" % (key, t, t / lawn_area * 100), flush=True)

# close-ups (inset bottom-right of each image): local camera, local target, lens
CLOSE = {"today": ((5.0, -13.0, 5.0), (11.0, -3.5, -0.4), 34),
         "a": ((-4.0, -1.0, 5.5), (-11.0, 9.0, -0.4), 26),
         "b": ((-1.5, -3.5, 4.2), (6.0, 4.0, -0.2), 30),
         "c": ((-5.2, -3.6, 3.4), (-9.8, 3.4, 0.3), 34)}
for key in ("today", "a", "b", "c"):
    if key in ONLY or "lineup" in ONLY:
        cl, tg = view(XS[key])
        shoot(os.path.join(OUT, "_wide_%s.png" % key), cl, tg, 35)
        c, t, lens = CLOSE[key]
        ox = XS[key]
        shoot(os.path.join(OUT, "_close_%s.png" % key), (c[0] + ox, c[1], c[2]), (t[0] + ox, t[1], t[2]), lens,
              size=(640, 480))

FRAMES = (0.0, 0.25, 0.5, 0.75)
if "motion" in ONLY:
    MX = 220.0
    # the close-up: the drift downwind of the sack, the meadow round it (props built once, the dressing per frame)
    for fi, t in enumerate(FRAMES):
        dress = option_b(coll, MX, t, props_too=(fi == 0))
        shoot(os.path.join(OUT, "_m_b_%d.png" % fi), (MX - 0.6, -12.6, 2.6), (MX + 9.0, -5.0, -0.2), 40, size=(640, 480))
        bpy.data.objects.remove(dress, do_unlink=True)

# labels + the 2 x 2 lineup + the motion contact sheet (PIL ships with the bpy env)
try:
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("arialbd.ttf", 30)
        small = ImageFont.truetype("arialbd.ttf", 20)
    except Exception:
        font = small = ImageFont.load_default()

    def tag(d, xy, text, f):
        x, y = xy
        w = d.textlength(text, font=f)
        sz = getattr(f, "size", 12)
        d.rounded_rectangle((x - 10, y - 7, x + w + 10, y + sz + 9), 9, fill=(20, 28, 48, 215))
        d.text((x, y), text, font=f, fill=(255, 255, 255))
    # each option = the wide view + its close-up inset (bottom-right, white frame)
    for key in ("today", "a", "b", "c"):
        wf, cf = os.path.join(OUT, "_wide_%s.png" % key), os.path.join(OUT, "_close_%s.png" % key)
        if not (os.path.isfile(wf) and os.path.isfile(cf)):
            continue
        im = Image.open(wf).convert("RGBA")
        cl = Image.open(cf).convert("RGBA").resize((440, 330), Image.LANCZOS)
        W_, H_ = im.size
        x0, y0 = W_ - 440 - 18, H_ - 330 - 18
        frame = Image.new("RGBA", (448, 338), (255, 255, 255, 255))
        im.paste(frame, (x0 - 4, y0 - 4))
        im.paste(cl, (x0, y0))
        ov = Image.new("RGBA", im.size)
        d = ImageDraw.Draw(ov)
        tag(d, (x0 + 12, y0 + 10), "close-up", small)
        im = Image.alpha_composite(im, ov)
        name = "today_render.png" if key == "today" else "option_%s.png" % key
        im.convert("RGB").save(os.path.join(OUT, name))
        os.remove(wf)
        os.remove(cf)
    if "lineup" in ONLY:
        files = [os.path.join(OUT, f) for f in ("today_render.png", "option_a.png", "option_b.png", "option_c.png")]
        if all(os.path.isfile(f) for f in files):
            tiles = [Image.open(f).convert("RGBA").resize((960, 720), Image.LANCZOS) for f in files]
            sheet = Image.new("RGBA", (960 * 2 + 8, 720 * 2 + 8), (20, 28, 48, 255))
            for i, (im, name) in enumerate(zip(tiles, ("TODAY", "A  Groundskeeper's Lawn", "B  Wind-Sown Sky Meadow",
                                                       "C  Settlers' Cottage Garden"))):
                ov = Image.new("RGBA", im.size)
                d = ImageDraw.Draw(ov)
                tag(d, (22, 18), name, font)
                sheet.paste(Image.alpha_composite(im, ov), ((i % 2) * 968, (i // 2) * 728))
            sheet.convert("RGB").save(os.path.join(OUT, "lineup.png"))
            print("[pitch] lineup", flush=True)
    fr = [os.path.join(OUT, "_m_b_%d.png" % i) for i in range(len(FRAMES))]
    if all(os.path.isfile(f) for f in fr):
        ims = [Image.open(f).convert("RGBA") for f in fr]
        w, h = ims[0].size
        sheet = Image.new("RGBA", (w * 2 + 6, h * 2 + 6), (20, 28, 48, 255))
        for i, im in enumerate(ims):
            ov = Image.new("RGBA", im.size)
            d = ImageDraw.Draw(ov)
            tag(d, (14, 12), "%d/4   t = %.1f s   (one gust loop = 4 s)" % (i + 1, FRAMES[i] * 4.0), small)
            sheet.paste(Image.alpha_composite(im, ov), ((i % 2) * (w + 6), (i // 2) * (h + 6)))
        sheet.convert("RGB").save(os.path.join(OUT, "motion_b.png"))
        for f in fr:
            os.remove(f)
        print("[pitch] motion sheet b", flush=True)
except ImportError:
    print("[pitch] PIL missing: no labels / contact sheets", flush=True)
print("[pitch] done", flush=True)
