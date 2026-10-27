"""Dungeon rooms design pitch (bug #5): today's boss room + three art directions for the whole dungeon kit, in Blender.

    python -I dungeon_pitch.py <out_dir> [--res 100] [--samples 32] [--only today,a,b,c] [--shots main,close,themes]
                                         [--no-composite]

Every style builds the SAME room: DungeonBuilder.Rooms.Throne (60 x 72 studs, walls 15 high, the dais / stairs /
throne / braziers / statues / arches / banners / torches at the Lua positions; the ceiling is left off so the camera
can look in). Per style three shots:
  main    the boss room from above the entrance arch (the screenshot's room)
  close   a wall close-up (torch, banner, pillar) with the 5.3-stud player, to judge the baked "texture"
  themes  one wall module dressed for three floors (Mossy Cellar / Frozen Crypt / Ember Forge): how the style varies
and composites them into today_render.png / option_a.png / option_b.png / option_c.png, plus lineup.png (the four main
shots side by side).

Coordinates are written in Roblox space (Y up, a room heads +Z, LookVector = -Z of a frame, CFrame.Angles = Rx Ry Rz)
and mapped to Blender (Z up) by P. 1 unit = 1 stud. Everything is a (chamfered) box with a per-face colour: the
blocky voxel rule; the "texture" is per-brick colour, mortar gaps, chips, moss, soot and frost, exactly what a baked
vertex-colour mesh can carry with SmoothPlastic.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # the project path has Hebrew letters
except Exception:
    pass


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else ".")
RES = int(arg("--res", 100))
SAMPLES = int(arg("--samples", 32))
ONLY = [s for s in arg("--only", "today,a,b,c").split(",") if s]
SHOTS = set(arg("--shots", "main,close,themes").split(","))
COMPOSITE = "--no-composite" not in sys.argv
os.makedirs(OUT, exist_ok=True)
PI = math.pi

P = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox (x, y, z) -> Blender (x, -z, y)


def CF(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def ANG(rx=0.0, ry=0.0, rz=0.0):
    return Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rz, 4, "Z")


def lin(c):
    return tuple((max(0, min(255, v)) / 255.0) ** 2.2 for v in c)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def jit(c, rng, n=8):
    d = rng.randint(-n, n)
    return tuple(max(0, min(255, v + d + rng.randint(-2, 2))) for v in c)


def shade(c, k):
    return tuple(max(0, min(255, v * k)) for v in c)


# ------------------------------------------------------------------------------------------------ box geometry
def _templates():
    corners = [(sx, sy, sz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    idx, verts = {}, []
    for c in corners:
        for ax in range(3):
            idx[(c, ax)] = len(verts)
            verts.append((c, ax))
    faces = []
    for ax in range(3):
        o = [i for i in range(3) if i != ax]
        for s in (-1, 1):
            ring = []
            for p, q in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                c = [0, 0, 0]
                c[ax], c[o[0]], c[o[1]] = s, p, q
                ring.append(idx[(tuple(c), ax)])
            faces.append(ring)
    for a3 in range(3):
        a1, a2 = [i for i in range(3) if i != a3]
        for s1 in (-1, 1):
            for s2 in (-1, 1):
                cm = [0, 0, 0]
                cm[a1], cm[a2], cm[a3] = s1, s2, -1
                cp = list(cm)
                cp[a3] = 1
                cm, cp = tuple(cm), tuple(cp)
                faces.append([idx[(cm, a1)], idx[(cp, a1)], idx[(cp, a2)], idx[(cm, a2)]])
    for c in corners:
        faces.append([idx[(c, 0)], idx[(c, 1)], idx[(c, 2)]])

    def pos(h, e):
        return [Vector([c[i] * h[i] if i == ax else c[i] * (h[i] - e) for i in range(3)]) for (c, ax) in verts]

    def fix(fs, ps):
        out = []
        for f in fs:
            n = Vector((0, 0, 0))
            for i in range(len(f)):
                a, b = ps[f[i]], ps[f[(i + 1) % len(f)]]
                n += a.cross(b)
            cen = sum((ps[i] for i in f), Vector((0, 0, 0))) / len(f)
            out.append(list(reversed(f)) if n.dot(cen) < 0 else f)
        return out

    ch_faces = fix(faces, pos((1.0, 1.3, 1.6), 0.2))
    pverts = corners
    pfaces = []
    for ax in range(3):
        o = [i for i in range(3) if i != ax]
        for s in (-1, 1):
            ring = []
            for p, q in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                c = [0, 0, 0]
                c[ax], c[o[0]], c[o[1]] = s, p, q
                ring.append(pverts.index(tuple(c)))
            pfaces.append(ring)
    pp = [Vector((c[0], c[1] * 1.3, c[2] * 1.6)) for c in pverts]
    pfaces = fix(pfaces, pp)
    return verts, ch_faces, pverts, pfaces


CH_V, CH_F, PL_V, PL_F = _templates()

KINDS = {
    "stone": dict(rough=0.86),
    "satin": dict(rough=0.66),
    "wood": dict(rough=0.75),
    "cloth": dict(rough=0.95),
    "metal": dict(rough=0.35, metal=0.75),
    "glow": dict(rough=0.5, emit=2.0),
    "glowsoft": dict(rough=0.5, emit=1.4),
    "glass": dict(rough=0.05, alpha=0.45),
}


class Geo:
    """boxes per material kind, each face with its own colour (one mesh per kind per group at the end)"""

    def __init__(self):
        self.k = {}
        self.lights = []

    def box(self, M, size, col, kind="stone", ch=0.1):
        h = (abs(size[0]) / 2, abs(size[1]) / 2, abs(size[2]) / 2)
        if min(h) <= 0:
            return
        e = min(ch, min(h) * 0.55)
        Mw = P @ M
        v, f, c = self.k.setdefault(kind, ([], [], []))
        base = len(v)
        if e > 0.015:
            for (cc, ax) in CH_V:
                v.append(Mw @ Vector([cc[i] * h[i] if i == ax else cc[i] * (h[i] - e) for i in range(3)]))
            tf = CH_F
        else:
            for cc in PL_V:
                v.append(Mw @ Vector((cc[0] * h[0], cc[1] * h[1], cc[2] * h[2])))
            tf = PL_F
        lc = lin(col)
        for face in tf:
            f.append([base + i for i in face])
            c.append(lc)

    def light(self, M, x, y, z, col, energy, radius=0.4, dist=34.0):
        self.lights.append(((P @ M) @ Vector((x, y, z)), lin(col), energy, radius, dist))

    def tris(self):
        n = 0
        for v, f, c in self.k.values():
            n += sum(len(ff) - 2 for ff in f)
        return n

    def build(self, name):
        objs = []
        for kind, (v, f, c) in self.k.items():
            me = bpy.data.meshes.new(name + "_" + kind)
            me.from_pydata([tuple(p) for p in v], [], f)
            at = me.color_attributes.new("Col", "FLOAT_COLOR", "FACE")
            flat = []
            for col in c:
                flat.extend((col[0], col[1], col[2], 1.0))
            at.data.foreach_set("color", flat)
            me.materials.append(kind_mat(kind))
            ob = bpy.data.objects.new(name + "_" + kind, me)
            bpy.context.scene.collection.objects.link(ob)
            objs.append(ob)
        for i, (p, col, energy, radius, dist) in enumerate(self.lights):
            L = bpy.data.lights.new("%s_L%d" % (name, i), "POINT")
            L.energy, L.color, L.shadow_soft_size = energy, col, radius
            try:
                L.use_custom_distance = True
                L.cutoff_distance = dist
            except Exception:
                pass
            lo = bpy.data.objects.new(L.name, L)
            lo.location = p
            bpy.context.scene.collection.objects.link(lo)
        return objs


_kmats = {}


def kind_mat(kind):
    if kind in _kmats:
        return _kmats[kind]
    spec = KINDS[kind]
    m = bpy.data.materials.new("K_" + kind)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "Col"
    nt.links.new(at.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = spec.get("rough", 0.8)
    b.inputs["Metallic"].default_value = spec.get("metal", 0.0)
    if spec.get("emit"):
        nt.links.new(at.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = spec["emit"]
    if spec.get("alpha"):
        b.inputs["Alpha"].default_value = spec["alpha"]
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            m.blend_method = "BLEND"
    _kmats[kind] = m
    return m


# ------------------------------------------------------------------------------------------------ shared helpers
def lay_bricks(G, M, L, y0, y1, ch_h, lens, depth, zc, colfn, rng, kind="stone", gap=0.14, ch=0.12, holes=(),
               tilt=0.0):
    """staggered brick courses on a wall (local X along, Y up, front -Z); colfn(x, y, rng) -> rgb"""
    y = y0
    while y + 0.25 < y1:
        hh = min(ch_h, y1 - y)
        x = -L / 2 - rng.uniform(0, lens[0])
        while x < L / 2:
            ln = rng.uniform(*lens)
            xa, xb = max(x, -L / 2), min(x + ln, L / 2)
            cx, cy = (xa + xb) / 2, y + hh / 2
            if xb - xa > 0.35 and not any(hl(xa, xb, y, y + hh) for hl in holes):
                rot = ANG(0, 0, rng.uniform(-tilt, tilt)) if tilt else Matrix.Identity(4)
                dz = rng.uniform(-0.04, 0.04)
                G.box(M @ CF(cx, cy, zc + dz) @ rot, (xb - xa - gap, hh - gap, depth), colfn(cx, cy, rng), kind, ch)
            x += ln
        y += hh


def door_hole(dx, dw, dh):
    return lambda xa, xb, ya, yb: xb > dx - dw / 2 - 0.2 and xa < dx + dw / 2 + 0.2 and ya < dh


def circle_hole(cx, cy, r):
    return lambda xa, xb, ya, yb: (max(xa, min(cx, xb)) - cx) ** 2 + (max(ya, min(cy, yb)) - cy) ** 2 < r * r


def body_with_door(G, M, L, h, col, door, kind="stone", z=0.0, th=1.0):
    if door:
        dx, dw = door.get("X", 0), door.get("W", 8)
        dh = door.get("H", 8)
        left = (dx - dw / 2) + L / 2
        right = L / 2 - (dx + dw / 2)
        if left > 0.3:
            G.box(M @ CF(-L / 2 + left / 2, h / 2, z), (left, h, th), col, kind, 0.02)
        if right > 0.3:
            G.box(M @ CF(L / 2 - right / 2, h / 2, z), (right, h, th), col, kind, 0.02)
        G.box(M @ CF(dx, (h + dh) / 2, z), (dw, h - dh, th), col, kind, 0.02)
    else:
        G.box(M @ CF(0, h / 2, z), (L, h, th), col, kind, 0.02)


def ring(G, M, r, n, size, col, kind="metal", a0=0.0, a1=2 * PI, ch=0.08):
    """a ring of boxes in the local XY plane (box X tangential)"""
    for i in range(n):
        a = a0 + (a1 - a0) * (i + 0.5) / n
        G.box(M @ CF(r * math.cos(a), r * math.sin(a), 0) @ ANG(0, 0, a + PI / 2), size, col, kind, ch)


def octo(G, M, w, h, col, kind="stone", ch=0.1):
    """an octagonal prism (two boxes, one turned 45 degrees), base at y 0"""
    G.box(M @ CF(0, h / 2, 0), (w, h, w * 0.83), col, kind, ch)
    G.box(M @ CF(0, h / 2, 0) @ ANG(0, PI / 4, 0), (w * 0.83, h, w), col, kind, ch)
    G.box(M @ CF(0, h / 2, 0), (w * 0.83, h, w), col, kind, ch)


def player(G, M):
    """a 5.3-stud R15-proportioned blocky player (legs 2.0, torso 2.0, head 1.2); front = -Z"""
    skin, shirt, pants, shoe, hair = (234, 196, 160), (90, 140, 210), (60, 66, 90), (40, 40, 48), (90, 60, 40)
    for sx in (-0.5, 0.5):
        G.box(M @ CF(sx, 0.175, -0.05), (0.95, 0.35, 1.0), shoe, "satin", 0.08)
        G.box(M @ CF(sx, 0.775, 0), (0.9, 0.85, 0.9), pants, "cloth", 0.08)
        G.box(M @ CF(sx, 1.6, 0), (0.95, 0.85, 0.95), pants, "cloth", 0.08)
    G.box(M @ CF(0, 2.225, 0), (2.0, 0.45, 1.0), pants, "cloth", 0.08)
    G.box(M @ CF(0, 3.225, 0), (2.0, 1.55, 1.0), shirt, "cloth", 0.1)
    for sx in (-1.5, 1.5):
        G.box(M @ CF(sx, 3.55, 0), (0.95, 0.85, 0.95), shirt, "cloth", 0.08)
        G.box(M @ CF(sx, 2.75, 0), (0.9, 0.8, 0.9), skin, "satin", 0.08)
        G.box(M @ CF(sx, 2.15, 0), (0.85, 0.4, 0.85), skin, "satin", 0.08)
    G.box(M @ CF(0, 4.7, 0), (1.2, 1.2, 1.2), skin, "satin", 0.25)
    G.box(M @ CF(0, 5.15, 0.04), (1.26, 0.35, 1.26), hair, "cloth", 0.12)
    for sx in (-0.22, 0.22):
        G.box(M @ CF(sx, 4.78, -0.61), (0.14, 0.22, 0.05), (30, 30, 40), "satin", 0.0)


# the room's frames (DungeonBuilder.roomShell for the 60 x 72 Throne): wall centre frames, local -Z into the room
HW, HD, WALL_H = 30, 36, 15
WALLS = {
    "entrance": (CF(0, 0, -HD - 0.5) @ ANG(0, PI, 0), 62, {"X": 0, "W": 8}),
    "back": (CF(0, 0, HD + 0.5), 62, {"X": 20, "W": 8}),
    "left": (CF(-HW - 0.5, 0, 0) @ ANG(0, -PI / 2, 0), 72, None),
    "right": (CF(HW + 0.5, 0, 0) @ ANG(0, PI / 2, 0), 72, None),
}
TORCH_Z = (-27, -9, 9, 27)  # roomShell: 4 torches per side wall on the 72-deep room
NATURE, FROST, FLAME = (104, 190, 86), (150, 222, 248), (240, 108, 56)
THEMES = (("moss", "Mossy Cellar", NATURE), ("frost", "Frozen Crypt", FROST), ("ember", "Ember Forge", FLAME))


def side_frame(sx, z, y=0.0):
    """a frame on a side wall's FACE (x = +-30), local -Z into the room"""
    return CF(sx * HW, y, z) @ ANG(0, sx * PI / 2, 0)


def back_frame(x, y=0.0):
    return CF(x, y, HD) @ ANG(0, 0, 0)


# ================================================================================================ TODAY (Part build)
class Today:
    """DungeonBuilder.Rooms.Throne as built today (Lua numbers), lilac brick like the baked wall mesh in the shot"""
    name = "today"
    STONE, DARK, LIGHT = (170, 160, 212), (130, 120, 182), (198, 190, 236)
    FLAG, FLAGD = (232, 210, 166), (210, 184, 140)
    IRON, WOOD, PLANK, GOLD = (74, 82, 108), (150, 100, 66), (196, 146, 98), (244, 198, 84)
    FLAMEC, CARPET, BONE, MARBLE, HAY = (255, 184, 96), (206, 72, 150), (246, 240, 226), (240, 238, 248), (250, 214, 120)
    PUDDLE, MOSS = (120, 190, 240), (110, 200, 120)
    accent = NATURE
    light_col = (255, 190, 120)

    def __init__(self):
        self.rng = random.Random(5)

    def wall(self, G, M, L, door=None, theme=None, holes=()):
        h = WALL_H
        r = self.rng
        G.box(M @ CF(0, 0.6, -0.35), (L, 1.2, 1.7), self.DARK, "stone", 0.02)
        body_with_door(G, M, L, h, self.STONE, door)
        hl = list(holes)
        if door:
            hl.append(door_hole(door.get("X", 0), door.get("W", 8), 8))
        # the baked mesh's brick read (fine lilac bricks, barely proud)
        lay_bricks(G, M, L, 1.2, h, 0.8, (1.8, 2.8), 0.1, -0.53, lambda x, y, rr: jit(self.STONE, rr, 7), r,
                   gap=0.08, ch=0.0, holes=hl)
        G.box(M @ CF(0, h + 0.4, -0.3), (L, 0.8, 1.6), self.DARK, "stone", 0.02)
        if not door:
            G.box(M @ CF(0, 3.4, -0.6), (L, 0.5, 0.2), self.DARK, "stone", 0.0)
            G.box(M @ CF(0, 7.2, -0.55), (L, 0.4, 0.12), self.DARK, "stone", 0.0)
            G.box(M @ CF(0, 11, -0.55), (L, 0.4, 0.12), self.DARK, "stone", 0.0)
        else:
            G.box(M @ CF(0, 11.4, -0.55), (L, 0.4, 0.12), self.DARK, "stone", 0.0)
        for i in range(max(4, min(8, int(L / 5)))):
            x, y = -L / 2 + 2 + r.random() * (L - 4), 1.6 + r.random() * (h - 4)
            if door and abs(x - door.get("X", 0)) < 5.2 and y < 8.5:
                continue
            G.box(M @ CF(x, y, -0.6), (1.8 + r.random() * 1.4, 1.0, 0.4),
                  jit(self.DARK if i % 3 == 0 else self.LIGHT, r, 6), "stone", 0.0)

    def floor(self, G, M, w, d, theme=None):
        nx, nz = round(w / 6), round(d / 6)
        tw, td = w / nx, d / nz
        r = random.Random(7)
        for i in range(1, nx + 1):
            for j in range(1, nz + 1):
                lift = 0.05 if (i + j) % 2 == 0 else -0.05
                c = self.FLAGD if (i * 7 + j * 3) % 6 == 0 else self.FLAG
                G.box(M @ CF(-w / 2 + (i - 0.5) * tw, -0.5 + lift, -d / 2 + (j - 0.5) * td), (tw, 1, td),
                      jit(c, r, 6), "stone", 0.0)
        for k in range(max(2, nx * nz // 12)):
            x, z = -w / 2 + 4 + r.random() * (w - 8), -d / 2 + 4 + r.random() * (d - 8)
            G.box(M @ CF(x, 0.06, z) @ ANG(0, r.random() * PI, 0), (2.5 + r.random() * 3, 0.12, 0.25), (110, 70, 50),
                  "stone", 0.0)

    def pillar(self, G, M, h, col=None):
        G.box(M @ CF(0, 0.5, 0), (2.6, 1, 2.6), self.DARK, "stone", 0.02)
        G.box(M @ CF(0, h / 2, 0), (2, h, 2), col or self.STONE, "stone", 0.02)
        G.box(M @ CF(0, h - 0.4, 0), (2.6, 0.8, 2.6), self.DARK, "stone", 0.02)

    def torch(self, G, M, lua=True):
        # Kit.torch at the Lua mount point (0.5 stud in front of the wall face)
        M = M @ CF(0, 0, -0.5) if lua else M
        G.box(M @ CF(0, 0.6, -0.1), (1.2, 2.2, 0.2), self.IRON, "metal", 0.02)
        G.box(M @ CF(0, 0, -0.3), (0.5, 0.7, 0.6), self.IRON, "metal", 0.02)
        G.box(M @ CF(0, 0.7, -0.75) @ ANG(-0.35, 0, 0), (0.3, 1.8, 0.3), self.WOOD, "wood", 0.02)
        G.box(M @ CF(0, 1.9, -1.05), (0.8, 1.3, 0.8), self.FLAMEC, "glow", 0.0)
        G.light(M, 0, 1.9, -1.6, self.light_col, 260, 0.4, 24)

    def banner(self, G, M, col):
        # Kit.banner at the Lua mount point (0.6 stud in front of the wall face)
        M = M @ CF(0, 0, -0.6)
        G.box(M @ CF(0, 0, -0.5), (4.4, 0.3, 0.3), self.WOOD, "wood", 0.0)
        G.box(M @ CF(0, -2.8, -0.45), (3.6, 5.4, 0.25), col, "cloth", 0.0)

    def room(self, G, O):
        for key, (M, L, door) in WALLS.items():
            self.wall(G, O @ M, L, door)
        self.floor(G, O, 60, 72)
        for sx in (-1, 1):
            for sz in (-1, 1):
                self.pillar(G, O @ CF(sx * (HW - 1.4), 0, sz * (HD - 1.4)), 15.5)
            for z in TORCH_Z:
                self.torch(G, O @ side_frame(sx, z, 6.5))
            self.torch(G, O @ CF(sx * 7, 7, -HD) @ ANG(0, PI, 0))
            for z in (-20, 4):
                self.pillar(G, O @ CF(sx * 19, 0, z), 15, self.LIGHT)
            for z in (-10, 6):  # the banners (z -10 hangs over the torch at z -9: bug)
                self.banner(G, O @ side_frame(sx, z, 12), self.accent)
        # carpet + runes
        G.box(O @ CF(0, 0.1, -4), (8, 0.2, 56), self.CARPET, "cloth", 0.0)
        for sx in (-4.3, 4.3):
            G.box(O @ CF(sx, 0.08, -4), (0.5, 0.16, 56), self.accent, "glow", 0.0)
        dz = 28
        G.box(O @ CF(0, 1.2, dz), (24, 2.4, 14), self.LIGHT, "stone", 0.02)
        G.box(O @ CF(0, 2.5, dz), (6, 0.2, 10), self.CARPET, "cloth", 0.0)
        G.box(O @ CF(0, 2.6, dz - 7.2), (24, 0.4, 0.6), self.DARK, "stone", 0.0)
        for i in range(1, 4):
            G.box(O @ CF(0, (i - 0.5) * 0.8, dz - 11.8 + (i - 0.5) * 1.6), (10, 0.8, 1.6), jit(self.LIGHT, self.rng, 5),
                  "stone", 0.02)
        tz = dz + 3
        G.box(O @ CF(0, 3.4, tz), (3.4, 2, 2.4), self.DARK, "stone", 0.02)
        G.box(O @ CF(0, 6.2, tz + 1), (3.4, 7.6, 0.6), self.DARK, "stone", 0.02)
        for sx in (-1.7, 1.7):
            G.box(O @ CF(sx, 4.6, tz), (0.4, 2.4, 2.4), self.DARK, "stone", 0.02)
        G.box(O @ CF(0, 10.4, tz + 1), (1.6, 1, 0.5), self.GOLD, "metal", 0.02)
        G.box(O @ CF(0, 4.6, tz - 0.2), (2.6, 0.5, 2), self.CARPET, "cloth", 0.02)
        for sx in (-8, 8):
            B = O @ CF(sx, 2.4, dz - 2)
            G.box(B @ CF(0, 0.3, 0), (2, 0.6, 2), self.IRON, "metal", 0.02)
            G.box(B @ CF(0, 1.6, 0), (0.5, 2, 0.5), self.IRON, "metal", 0.02)
            G.box(B @ CF(0, 3.0, 0), (3.2, 1.1, 3.2), self.IRON, "metal", 0.02)
            G.box(B @ CF(0, 4.3, 0), (1.8, 1.8, 1.8), self.FLAMEC, "glow", 0.0)
            G.light(B, 0, 5.2, 0, self.light_col, 420, 0.6, 26)
        for z in (-20, -2):
            A = O @ CF(0, 0, z)
            for sx in (-6, 6):
                self.pillar(G, A @ CF(sx, 0, 0), 10.5, self.LIGHT)
            G.box(A @ CF(0, 11.9, 0), (14.6, 1.2, 2.2), self.LIGHT, "stone", 0.02)
            G.box(A @ CF(-4.4, 10.3, 0) @ ANG(0, 0, 0.75), (2, 1, 2), self.LIGHT, "stone", 0.02)
            G.box(A @ CF(4.4, 10.3, 0) @ ANG(0, 0, -0.75), (2, 1, 2), self.LIGHT, "stone", 0.02)
            G.box(A @ CF(0, 13.1, 0), (4, 1.2, 2.4), self.STONE, "stone", 0.02)
        for sx in (-9, 9):
            S = O @ CF(sx, 0, 14)
            G.box(S @ CF(0, 0.6, 0), (3, 1.2, 3), self.DARK, "stone", 0.02)
            G.box(S @ CF(0, 3.2, 0), (1.8, 4, 1.4), self.LIGHT, "stone", 0.02)
            G.box(S @ CF(0, 5.8, 0), (1.2, 1.2, 1.2), self.LIGHT, "stone", 0.02)
            G.box(S @ CF(-1.3, 3.6, 0), (0.6, 2.6, 0.6), self.LIGHT, "stone", 0.02)
            G.box(S @ CF(1.3, 4.0, -0.4) @ ANG(0.5, 0, 0), (0.6, 2.6, 0.6), self.LIGHT, "stone", 0.02)
            G.box(S @ CF(1.3, 5.4, -1.2), (0.3, 3.4, 0.3), self.IRON, "metal", 0.0)
        for sx in (-6, 6):
            for i in (-1, 0, 1):
                G.box(O @ CF(sx + i * 0.7, 2.75, dz + 5), (0.3, 0.7, 0.3), self.MARBLE, "satin", 0.0)
                G.box(O @ CF(sx + i * 0.7, 3.25, dz + 5), (0.25, 0.3, 0.25), self.FLAMEC, "glow", 0.0)
        Sh = O @ CF(0, 10, HD - 0.6)
        G.box(Sh @ CF(0, 0, -0.3), (2.6, 3.2, 0.3), self.IRON, "metal", 0.02)
        G.box(Sh @ CF(0, 0, -0.5), (1.6, 2, 0.15), self.accent, "cloth", 0.0)
        for a in (0.75, -0.75):
            G.box(Sh @ CF(0, 0, -0.65) @ ANG(0, 0, a), (4, 0.25, 0.2), self.GOLD, "metal", 0.0)
        # the clutter pasted into the throne room
        G.box(O @ CF(27, 0.55, 0), (4.4, 1.1, 3.6), self.HAY, "cloth", 0.02)
        G.box(O @ CF(27.5, 1.35, -0.3) @ ANG(0, 0.4, 0), (2.6, 0.6, 2), self.HAY, "cloth", 0.02)
        G.box(O @ CF(16, 0.07, 10), (4, 0.14, 3), self.PUDDLE, "glass", 0.0)
        G.box(O @ CF(24, 0.1, -14), (4, 0.2, 3), self.MOSS, "stone", 0.0)
        G.box(O @ CF(-26, 1.6, 28) @ ANG(0, 0, PI / 2), (3.2, 2.8, 2.8), self.WOOD, "wood", 0.02)
        G.box(O @ CF(-26, 1.3, 32), (2.6, 2.6, 2.6), self.PLANK, "wood", 0.02)
        G.box(O @ CF(26, 2.5, -30), (7, 0.45, 3), self.PLANK, "wood", 0.02)
        door_bars(G, O @ back_frame(20), self.DARK, self.IRON)

    def theme_segment(self, G, M, theme, accent):
        self.wall(G, M @ CF(0, 0, 0.5), 14)
        self.floor(G, M @ CF(0, 0, -4), 14, 8)
        self.torch(G, M @ CF(-4, 6.5, 0))
        self.banner(G, M @ CF(2.5, 12, 0), accent)


def door_bars(G, M, frame, iron, w=8, h=8):
    """Kit.door at a doorway (M on the wall face line, -Z into the room): jambs, lintel, portcullis bars"""
    for sx in (-1, 1):
        G.box(M @ CF(sx * (w / 2 + 0.5), h / 2, -0.3), (1, h, 1.6), frame, "stone", 0.05)
    G.box(M @ CF(0, h + 0.5, -0.3), (w + 2, 1, 1.6), frame, "stone", 0.05)
    n = max(3, int(w / 1.6))
    for i in range(n):
        G.box(M @ CF(-w / 2 + (i + 0.5) * (w / n), h / 2, -0.3), (0.35, h, 0.35), iron, "metal", 0.03)


# ================================================================================================ shared room layout
class Style:
    """the shared Throne layout; a style fills in the pieces"""
    proud = 0.3  # how far the wall's surface stands proud of the wall face (wall props mount in front of it)
    accent = NATURE

    def room(self, G, O):
        for key, (M, L, door) in WALLS.items():
            holes = self.wall_holes(key)
            self.wall(G, O @ M, L, door, holes=holes, key=key)
        self.floor(G, O, 60, 72)
        for sx in (-1, 1):
            for sz in (-1, 1):
                self.pillar(G, O @ CF(sx * (HW - 1.4), 0, sz * (HD - 1.4)), 15.5)
            for z in TORCH_Z:
                self.torch(G, O @ side_frame(sx, z, 6.5) @ CF(0, 0, -self.proud))
            self.torch(G, O @ CF(sx * 7, 7, -HD) @ ANG(0, PI, 0) @ CF(0, 0, -self.proud))
            for z in (-20, 4):
                self.pillar(G, O @ CF(sx * 19, 0, z), 15)
            # fixed: the banners hang BETWEEN the torches (z 0 and 18) and on the wall, not 0.9 stud in front of it
            for i, z in enumerate((0, 18)):
                self.banner(G, O @ side_frame(sx, z, 12.6) @ CF(0, 0, -self.proud), askew=(sx > 0 and i == 1))
        self.carpet(G, O)
        dz = 28
        self.dais(G, O, dz)
        self.throne(G, O @ CF(0, 2.4, dz + 3))
        for sx in (-8, 8):
            self.brazier(G, O @ CF(sx, 2.4, dz - 2))
        for z in (-20, -2):
            self.arch(G, O @ CF(0, 0, z))
        for sx in (-9, 9):
            self.statue(G, O @ CF(sx, 0, 14), sx)
        self.exit_door(G, O @ back_frame(20) @ CF(0, 0, -0.0))
        self.extras(G, O)

    def wall_holes(self, key):
        return ()

    def theme_segment(self, G, M, theme, accent):
        self.wall(G, M @ CF(0, 0, 0.5), 14, None, theme=theme, key="theme")
        self.floor(G, M @ CF(0, 0, -4), 14, 8, theme=theme)
        self.torch(G, M @ CF(-4, 6.5, -self.proud))
        self.banner(G, M @ CF(2.6, 12.6, -self.proud), accent=accent)
        self.theme_dress(G, M, theme)


# ================================================================================================ A: Cloudkeep Undercroft
class StyleA(Style):
    """the first sky-kings' castle cellars, carved into the underside of a floating island: the castle done properly"""
    name = "a"
    proud = 0.32
    LIME, LIME2, LIME3 = (236, 226, 204), (222, 208, 184), (246, 240, 224)
    MORTAR = (150, 136, 122)
    SLATE, SLATE2 = (94, 112, 146), (74, 90, 122)
    FLAG, FLAG2, GROUT = (204, 192, 172), (186, 172, 150), (108, 98, 92)
    CARPET, CARPETW, GOLD = (172, 38, 52), (206, 98, 104), (224, 184, 84)
    IRON, WOOD, MOSS, MOSS2 = (66, 68, 80), (140, 96, 62), (104, 168, 84), (78, 140, 70)
    SOOT, FLAMEC, EMBER, SKY = (60, 54, 58), (255, 196, 96), (255, 120, 50), (176, 214, 255)
    BLUE = (66, 98, 168)
    light_col = (255, 196, 130)

    def __init__(self):
        self.rng = random.Random(11)

    def wall_holes(self, key):
        return (circle_hole(0, 10.8, 3.4),) if key == "back" else ()

    def wall(self, G, M, L, door=None, holes=(), key="", theme=None):
        r = self.rng
        h = WALL_H
        body_with_door(G, M, L, h, self.MORTAR, door)
        hl = list(holes)
        if door:
            hl.append(door_hole(door.get("X", 0), door.get("W", 8) + 1.6, 8))

        def col(x, y, rr):
            c = rr.choice((self.LIME, self.LIME, self.LIME2, self.LIME3))
            if rr.random() < 0.06:
                c = (214, 200, 196)  # a pinkish stone from another quarry
            if theme == "frost":
                c = mix(c, (210, 228, 246), 0.45 + 0.3 * (y / h))
            elif theme == "ember":
                c = mix(c, (60, 50, 52), max(0.0, (y - 8) / 9) * 0.8)  # soot climbing up from the forge
                c = mix(c, (238, 200, 170), 0.25)
            elif theme == "moss" and y < 4 and rr.random() < 0.3:
                c = mix(c, self.MOSS, 0.35)
            return jit(c, rr, 6)

        # slate-blue plinth of big blocks
        lay_bricks(G, M, L, 0, 1.6, 1.6, (2.6, 3.6), 1.3, -0.95, lambda x, y, rr: jit(self.SLATE, rr, 6), r,
                   gap=0.16, ch=0.16, holes=hl)
        # the limestone courses (mortar shows in the gaps, a few blocks tilt a hair: hand-laid)
        lay_bricks(G, M, L, 1.6, h - 0.8, 1.25, (1.9, 3.6), 0.5, -0.57, col, r, gap=0.15, ch=0.13, holes=hl, tilt=0.012)
        # cornice + corbels
        G.box(M @ CF(0, h - 0.2, -0.75), (L, 0.9, 1.9), self.SLATE, "stone", 0.12)
        for i in range(int(L / 3)):
            x = -L / 2 + 1.5 + i * 3
            if not any(hh(x - 0.4, x + 0.4, h - 1.4, h - 0.7) for hh in hl):
                G.box(M @ CF(x, h - 1.05, -0.95), (0.7, 0.8, 0.9), self.SLATE2, "stone", 0.08)
        # moss in the low joints and on the plinth
        for i in range(int(L / (2.2 if theme == "moss" else 5.5))):
            x = -L / 2 + r.random() * L
            if any(hh(x - 0.5, x + 0.5, 0, 3) for hh in hl):
                continue
            y = r.choice((1.6, 2.85, 0.0 + 1.62))
            G.box(M @ CF(x, y + 0.08, -1.05 if y < 1.7 else -0.85), (0.5 + r.random() * 1.2, 0.28, 0.5),
                  r.choice((self.MOSS, self.MOSS2)), "stone", 0.08)

    def floor(self, G, M, w, d, theme=None):
        r = random.Random(23)
        G.box(M @ CF(0, -0.35, 0), (w, 0.6, d), self.GROUT, "stone", 0.0)
        z = -d / 2
        row = 0
        while z < d / 2 - 0.1:
            td = min(r.choice((4.5, 6.0)), d / 2 - z)
            x = -w / 2 - (1.5 if row % 2 else 0)
            while x < w / 2:
                tw = r.choice((3.0, 4.5, 6.0))
                xa, xb = max(x, -w / 2), min(x + tw, w / 2)
                cx, cz = (xa + xb) / 2, z + td / 2
                c = r.choice((self.FLAG, self.FLAG, self.FLAG2))
                if abs(cx) < 4.5:
                    c = mix(c, (226, 214, 192), 0.5)  # worn pale down the aisle
                if theme == "frost":
                    c = mix(c, (214, 230, 244), 0.5)
                elif theme == "ember":
                    c = mix(c, (150, 128, 116), 0.5)
                lift = r.uniform(-0.04, 0.04)
                if r.random() < 0.08 and xb - xa > 2.5:  # a cracked flagstone in two pieces
                    G.box(M @ CF(cx - (xb - xa) / 4, -0.2 + lift, cz) @ ANG(0, 0.03, 0),
                          ((xb - xa) / 2 - 0.25, 0.42, td - 0.2), jit(c, r, 6), "stone", 0.1)
                    G.box(M @ CF(cx + (xb - xa) / 4, -0.22, cz), ((xb - xa) / 2 - 0.25, 0.42, td - 0.2),
                          jit(c, r, 6), "stone", 0.1)
                else:
                    G.box(M @ CF(cx, -0.2 + lift, cz), (xb - xa - 0.18, 0.42, td - 0.18), jit(c, r, 6), "stone", 0.12)
                if theme == "ember" and r.random() < 0.2:
                    G.box(M @ CF(xa, 0.0, cz), (0.1, 0.06, td * 0.8), self.EMBER, "glow", 0.0)
                x += tw
            z += td
            row += 1

    def pillar(self, G, M, h, col=None):
        G.box(M @ CF(0, 0.6, 0), (3.0, 1.2, 3.0), self.SLATE, "stone", 0.15)
        y = 1.2
        r = self.rng
        while y < h - 1.4:
            dh = min(2.4, h - 1.4 - y)
            octo(G, M @ CF(0, y + 0.06, 0), 2.2, dh - 0.12, jit(r.choice((self.LIME, self.LIME2, self.LIME3)), r, 5),
                 "stone", 0.12)
            y += dh
        G.box(M @ CF(0, h - 1.1, 0), (2.7, 0.6, 2.7), self.SLATE2, "stone", 0.1)
        G.box(M @ CF(0, h - 0.45, 0), (3.1, 0.7, 3.1), self.SLATE, "stone", 0.12)

    def torch(self, G, M):
        # an iron cage sconce on a back plate, and the soot it has left on the stone above
        G.box(M @ CF(0, 0.4, -0.08), (0.9, 1.8, 0.16), self.IRON, "metal", 0.05)
        G.box(M @ CF(0, -0.1, -0.5), (0.35, 0.35, 0.9), self.IRON, "metal", 0.04)
        for dx in (-0.4, 0.4):
            for dz in (-0.55, -1.35):
                G.box(M @ CF(dx, 0.75, dz), (0.12, 1.0, 0.12), self.IRON, "metal", 0.0)
        G.box(M @ CF(0, 0.2, -0.95), (1.0, 0.18, 1.0), self.IRON, "metal", 0.04)
        G.box(M @ CF(0, 0.55, -0.95), (0.6, 0.5, 0.6), (255, 150, 60), "glow", 0.05)
        G.box(M @ CF(0, 1.05, -0.95), (0.42, 0.6, 0.42), self.FLAMEC, "glow", 0.05)
        G.box(M @ CF(0, 1.45, -0.95), (0.2, 0.3, 0.2), (255, 236, 170), "glow", 0.03)
        for i, (w, y) in enumerate(((1.1, 2.0), (1.5, 2.7), (1.2, 3.4), (0.7, 4.0))):
            G.box(M @ CF(0.1 * (i % 2), y, 0.0), (w, 0.7, 0.05), self.SOOT, "stone", 0.0)
        G.light(M, 0, 1.2, -1.6, self.light_col, 300, 0.4, 26)

    def banner(self, G, M, askew=False, accent=None):
        accent = accent or self.accent
        R = M @ ANG(0, 0, 0.045 if askew else 0)
        for dx in (-1.6, 1.6):
            G.box(M @ CF(dx, 0.1, -0.35), (0.25, 0.6, 0.7), self.IRON, "metal", 0.04)  # wall brackets (nailed)
        G.box(R @ CF(0, 0, -0.6), (4.3, 0.28, 0.28), self.WOOD, "wood", 0.06)
        for dx in (-2.2, 2.2):
            G.box(R @ CF(dx, 0, -0.6), (0.35, 0.45, 0.45), self.GOLD, "metal", 0.06)
        C = R @ CF(0, 0, -0.6)
        G.box(C @ CF(0, -2.6, 0.02), (3.4, 4.8, 0.16), self.BLUE, "cloth", 0.03)
        for dx in (-1.05, 1.05):
            G.box(C @ CF(dx, -5.55, 0.02), (1.3, 1.2, 0.16), self.BLUE, "cloth", 0.03)  # the swallow tails
        G.box(C @ CF(0, -4.4, -0.06), (3.4, 0.6, 0.06), accent, "cloth", 0.0)
        for dx in (-1.6, 1.6):
            G.box(C @ CF(dx, -2.6, -0.06), (0.14, 4.8, 0.05), self.GOLD, "metal", 0.0)
        for dx, dy, s in ((-0.5, -2.1, 0.9), (0.4, -1.9, 1.1), (0.0, -2.5, 1.5), (0.8, -2.5, 0.8), (-0.9, -2.5, 0.7)):
            G.box(C @ CF(dx, dy, -0.08), (s, s * 0.7, 0.06), (246, 246, 250), "cloth", 0.0)  # the cloud crest

    def carpet(self, G, O):
        r = random.Random(31)
        G.box(O @ CF(0, 0.06, -8), (7, 0.12, 48.4), self.CARPET, "cloth", 0.02)
        for sx in (-3.25, 3.25):
            G.box(O @ CF(sx, 0.14, -8), (0.38, 0.05, 48.4), self.GOLD, "cloth", 0.0)
        z = -31
        while z < 15:
            G.box(O @ CF(0, 0.14, z) @ ANG(0, PI / 4, 0), (0.9, 0.04, 0.9), self.GOLD, "cloth", 0.0)
            z += 4
        z = -30
        while z < 15:  # the pale strip worn down the middle, patchy
            ln = r.uniform(1.5, 4.5)
            G.box(O @ CF(r.uniform(-0.3, 0.3), 0.125, z + ln / 2), (r.uniform(1.6, 2.6), 0.03, ln), self.CARPETW,
                  "cloth", 0.0)
            z += ln + r.uniform(0.3, 2.0)
        # a sewn-on patch of a different red, with its stitches
        P0 = O @ CF(1.4, 0.15, 6.5) @ ANG(0, 0.12, 0)
        G.box(P0, (1.8, 0.04, 1.6), (148, 46, 74), "cloth", 0.0)
        for i in range(5):
            G.box(P0 @ CF(-0.8 + i * 0.4, 0.02, 0.85), (0.16, 0.03, 0.12), (240, 220, 200), "cloth", 0.0)
        # up the stairs and across the dais to the throne
        for i in range(1, 4):
            G.box(O @ CF(0, i * 0.8 + 0.05, 16.2 + (i - 0.5) * 1.6), (7, 0.1, 1.6), self.CARPET, "cloth", 0.0)
        G.box(O @ CF(0, 2.45, 25), (7, 0.1, 8), self.CARPET, "cloth", 0.02)
        for sx in (-3.25, 3.25):
            G.box(O @ CF(sx, 2.52, 25), (0.38, 0.05, 8), self.GOLD, "cloth", 0.0)

    def dais(self, G, O, dz):
        r = random.Random(41)
        G.box(O @ CF(0, 1.1, dz), (24, 2.2, 14), self.LIME2, "stone", 0.1)
        G.box(O @ CF(0, 2.3, dz), (24.4, 0.2, 14.4), self.SLATE, "stone", 0.06)
        G.box(O @ CF(0, 2.36, dz + 0.4), (22.8, 0.12, 12.8), self.LIME3, "stone", 0.04)
        for i in range(12):  # face blocks of the dais front
            G.box(O @ CF(-11 + i * 2, 1.1, dz - 7.08), (1.85, 2.0, 0.2), jit(self.LIME, r, 6), "stone", 0.06)
        for i in range(1, 4):
            G.box(O @ CF(0, (i - 0.5) * 0.8, dz - 11.8 + (i - 0.5) * 1.6), (10.6, 0.78, 1.58), jit(self.SLATE, r, 5),
                  "stone", 0.1)
            G.box(O @ CF(0, i * 0.8 + 0.01, dz - 11.8 + (i - 0.5) * 1.6), (3.0, 0.02, 1.2), (124, 140, 170), "stone",
                  0.0)  # worn pale where everyone steps
        # candles along the dais edge; their wax has run down the front
        for x in (-10.5, -8.6, 8.6, 10.5):
            for k, dx in enumerate((-0.3, 0.35)):
                hgt = 0.8 + 0.4 * k
                G.box(O @ CF(x + dx, 2.4 + hgt / 2, dz - 6.4), (0.32, hgt, 0.32), (246, 240, 226), "satin", 0.04)
                G.box(O @ CF(x + dx, 2.5 + hgt, dz - 6.4), (0.16, 0.26, 0.16), self.FLAMEC, "glow", 0.0)
            for j in range(2):
                G.box(O @ CF(x + r.uniform(-0.4, 0.4), 1.9 - j * 0.4, dz - 7.2), (0.22, 0.9 - j * 0.3, 0.08),
                      (246, 240, 226), "satin", 0.02)

    def throne(self, G, T):
        G.box(T @ CF(0, 0.7, 0), (4.6, 1.4, 3.6), self.LIME2, "stone", 0.15)
        G.box(T @ CF(0, 1.6, -0.1), (4.0, 0.5, 3.0), self.LIME, "stone", 0.12)
        G.box(T @ CF(0, 2.0, -0.2), (3.0, 0.45, 2.4), self.CARPET, "cloth", 0.15)
        G.box(T @ CF(0, 4.6, 1.4), (4.0, 6.4, 0.9), self.LIME, "stone", 0.15)
        G.box(T @ CF(0, 4.4, 0.92), (2.8, 4.8, 0.12), self.CARPET, "cloth", 0.03)
        for sx in (-1, 1):
            G.box(T @ CF(sx * 2.05, 4.6, 1.4), (0.35, 6.6, 1.05), self.SLATE, "stone", 0.08)
            G.box(T @ CF(sx * 2.1, 2.6, 0), (0.7, 1.4, 3.2), self.LIME3, "stone", 0.12)
            G.box(T @ CF(sx * 2.1, 3.2, -1.45), (0.9, 0.9, 0.9), self.LIME3, "stone", 0.25)  # scroll ends
        for dx, dy, s in ((0, 8.6, 2.0), (-1.2, 8.1, 1.4), (1.2, 8.1, 1.4), (-0.6, 9.3, 1.2), (0.7, 9.2, 1.3)):
            G.box(T @ CF(dx, dy, 1.4), (s, s * 0.8, 1.1), (248, 246, 240), "satin", 0.3)  # the carved cloud crest
        ring(G, T @ CF(0, 10.2, 1.4), 0.75, 8, (0.6, 0.22, 0.22), self.GOLD, "metal")
        # the toy wooden sword some kid left leaning on the throne
        G.box(T @ CF(2.9, 1.0, -1.4) @ ANG(0, 0.3, -0.25), (0.18, 1.8, 0.08), (186, 140, 92), "wood", 0.03)
        G.box(T @ CF(2.75, 0.45, -1.36) @ ANG(0, 0.3, -0.25), (0.7, 0.14, 0.12), (150, 100, 66), "wood", 0.03)

    def brazier(self, G, B):
        for a in range(3):
            t = a * 2 * PI / 3
            G.box(B @ CF(math.cos(t) * 0.9, 1.1, math.sin(t) * 0.9) @ ANG(0, -t, 0) @ ANG(0, 0, 0.25),
                  (0.22, 2.3, 0.22), self.IRON, "metal", 0.04)
        for k, (w, y) in enumerate(((1.6, 2.2), (2.3, 2.55), (2.6, 2.85))):
            G.box(B @ CF(0, y, 0) @ ANG(0, PI / 4 * (k % 2), 0), (w, 0.36, w), self.IRON, "metal", 0.08)
        G.box(B @ CF(0, 3.05, 0), (2.0, 0.2, 2.0), (255, 120, 50), "glow", 0.05)
        for dx, dz, s, hh in ((0, 0, 1.0, 1.4), (0.4, 0.3, 0.6, 0.9), (-0.45, -0.2, 0.55, 0.8)):
            G.box(B @ CF(dx, 3.2 + hh / 2, dz), (s, hh, s), self.FLAMEC, "glow", 0.08)
        G.light(B, 0, 4.6, 0, self.light_col, 520, 0.6, 28)

    def arch(self, G, A):
        for sx in (-6, 6):
            G.box(A @ CF(sx, 0.5, 0), (2.8, 1.0, 2.8), self.SLATE, "stone", 0.12)
            y = 1.0
            while y < 7.4:
                G.box(A @ CF(sx, y + 0.55, 0), (2.1, 1.0, 2.2), jit(self.LIME, self.rng, 6), "stone", 0.12)
                y += 1.15
            G.box(A @ CF(sx, 7.6, 0), (2.6, 0.5, 2.5), self.SLATE, "stone", 0.08)
        n = 11
        for i in range(n):
            a = PI * (i + 0.5) / n
            col = self.LIME3 if i == n // 2 else jit(self.LIME, self.rng, 6)
            G.box(A @ CF(6 * math.cos(a), 7.85 + 6 * math.sin(a), 0) @ ANG(0, 0, a - PI / 2),
                  (1.55, 2.0 if i != n // 2 else 2.5, 2.0), col, "stone", 0.12)
        ring(G, A @ CF(0, 7.85, 0), 7.15, 15, (1.45, 0.32, 2.3), self.SLATE, "stone", 0.0, PI, 0.06)  # slate hood
        for dx, dy, s in ((0, 14.6, 1.0), (-0.6, 14.3, 0.7), (0.6, 14.3, 0.7)):
            G.box(A @ CF(dx, dy, -1.15), (s, s * 0.8, 0.3), (250, 250, 252), "satin", 0.1)

    def statue(self, G, S, sx):
        r = self.rng
        G.box(S @ CF(0, 0.7, 0), (3.2, 1.4, 3.2), self.SLATE, "stone", 0.15)
        st = (226, 220, 210)
        G.box(S @ CF(0, 2.6, 0), (1.9, 2.4, 1.5), st, "stone", 0.15)  # robe
        G.box(S @ CF(0, 4.4, 0), (2.2, 1.5, 1.4), st, "stone", 0.15)  # chest
        G.box(S @ CF(0, 5.55, 0), (1.25, 1.2, 1.2), st, "stone", 0.25)  # head
        G.box(S @ CF(0, 6.25, 0), (1.35, 0.35, 1.3), (200, 196, 190), "stone", 0.12)  # helm
        G.box(S @ CF(0, 6.7, 0.1), (0.3, 0.6, 1.2), (200, 196, 190), "stone", 0.1)  # crest
        G.box(S @ CF(-1.35, 4.0, -0.2), (0.6, 2.0, 0.6), st, "stone", 0.12)
        G.box(S @ CF(1.35, 4.3, -0.4), (0.6, 1.6, 0.6), st, "stone", 0.12)
        G.box(S @ CF(1.35, 5.0, -0.85), (0.22, 5.5, 0.22), (120, 110, 100), "stone", 0.0)  # a stone spear
        G.box(S @ CF(1.35, 7.95, -0.85), (0.5, 0.8, 0.16), (120, 110, 100), "stone", 0.05)
        G.box(S @ CF(-1.75, 3.9, -0.45) @ ANG(0, 0.2, 0), (0.25, 1.9, 1.5), (210, 204, 196), "stone", 0.12)
        for dx, dy, s in ((0, 0, 0.6), (-0.3, -0.15, 0.45), (0.3, -0.15, 0.45)):
            G.box(S @ CF(-1.9, 4.0 + dy, -0.45 + dx), (0.08, s * 0.8, s), (240, 240, 244), "satin", 0.03)
        for i in range(3):  # moss creeping on the plinth
            G.box(S @ CF(r.uniform(-1.4, 1.4), 1.45, r.uniform(-1.4, 1.4)), (r.uniform(0.5, 1.2), 0.18, 0.6),
                  self.MOSS, "stone", 0.06)

    def exit_door(self, G, D):
        for sx in (-1, 1):
            y = 0
            while y < 8:
                G.box(D @ CF(sx * 4.8, y + 0.6, -0.5), (1.6 if (y // 1.2) % 2 else 1.2, 1.15, 1.3), self.SLATE, "stone",
                      0.12)
                y += 1.2
        for i in range(9):
            a = PI * (i + 0.5) / 9
            G.box(D @ CF(4.8 * math.cos(a), 8 + 4.8 * math.sin(a) * 0.55, -0.5) @ ANG(0, 0, a - PI / 2),
                  (1.4, 1.4, 1.3), self.SLATE, "stone", 0.12)
        for i in range(5):
            G.box(D @ CF(-3.2 + i * 1.6, 4.0, -0.5), (0.3, 8, 0.3), self.IRON, "metal", 0.04)
        for y in (2, 5.5):
            G.box(D @ CF(0, y, -0.5), (8, 0.3, 0.3), self.IRON, "metal", 0.04)

    def extras(self, G, O):
        # the sky window behind the throne (the castle hangs under an island: the window looks out at open sky)
        W = O @ back_frame(0, 10.8)
        for k in range(14):
            yy = -3.2 + (k + 0.5) * 6.4 / 14
            ww = 2 * math.sqrt(max(0.0, 3.2 ** 2 - yy ** 2))
            G.box(W @ CF(0, yy, -0.1), (ww, 6.4 / 14 + 0.02, 0.1), mix(self.SKY, (240, 248, 255), max(0, yy) / 4),
                  "glowsoft", 0.0)
        ring(G, W @ CF(0, 0, -0.5), 3.55, 14, (1.6, 0.9, 1.1), self.SLATE, "stone")
        G.box(W @ CF(0, 0, -0.3), (0.25, 6.4, 0.25), self.IRON, "metal", 0.0)
        G.box(W @ CF(0, 0, -0.3), (6.4, 0.25, 0.25), self.IRON, "metal", 0.0)
        for dx, dy, s in ((1.4, -1.2, 1.2), (2.0, -1.6, 0.9), (0.8, -1.7, 0.8), (-1.8, 1.2, 0.8), (-1.3, 1.0, 0.6)):
            G.box(W @ CF(dx, dy, -0.2), (s * 1.3, s * 0.7, 0.05), (255, 255, 255), "glowsoft", 0.05)  # passing clouds
        G.light(W, 0, 0, -3, (190, 220, 255), 900, 2.5, 40)
        # mop and bucket: somebody still keeps the place clean
        Bk = O @ CF(26.6, 0, 22)
        G.box(Bk @ CF(0, 0.6, 0), (1.3, 1.2, 1.3), (150, 110, 70), "wood", 0.08)
        for y in (0.25, 0.95):
            G.box(Bk @ CF(0, y, 0), (1.38, 0.12, 1.38), self.IRON, "metal", 0.03)
        G.box(Bk @ CF(0, 1.12, 0), (1.1, 0.08, 1.1), (130, 170, 200), "glass", 0.0)
        G.box(Bk @ CF(1.6, 2.4, 0.9) @ ANG(0.25, 0, 0.12), (0.16, 4.6, 0.16), (196, 150, 100), "wood", 0.02)
        G.box(Bk @ CF(1.35, 0.25, 0.4), (0.9, 0.5, 0.9), (220, 214, 196), "cloth", 0.1)
        # a broken flagstone replaced with planks by the left wall
        for i in range(3):
            G.box(O @ CF(-24 + i * 1.0, 0.02, -2), (0.92, 0.12, 4.0), (166, 118, 74), "wood", 0.04)

    def theme_dress(self, G, M, theme):
        r = random.Random(3 + len(theme))
        if theme == "frost":
            for i in range(10):  # icicles under the cornice
                x = -6.5 + i * 1.4 + r.uniform(-0.2, 0.2)
                ln = r.uniform(0.6, 1.8)
                G.box(M @ CF(x, 14.3 - ln / 2, -1.55), (0.3, ln, 0.3), (220, 240, 255), "satin", 0.06)
            G.box(M @ CF(0, 15.35, -0.8), (14, 0.25, 2.0), (240, 248, 255), "satin", 0.08)
            for i in range(6):
                G.box(M @ CF(r.uniform(-6, 6), 0.06, -r.uniform(1.5, 7)), (r.uniform(1, 2.5), 0.08, r.uniform(0.8, 2)),
                      (232, 244, 255), "satin", 0.03)
        elif theme == "ember":
            for i in range(5):
                G.box(M @ CF(-6 + i * 3 + r.uniform(-0.5, 0.5), 1.65, -1.62), (r.uniform(0.6, 1.6), 0.08, 0.08),
                      self.EMBER, "glow", 0.0)
            G.box(M @ CF(5.5, 0.4, -2.2), (2.0, 0.8, 1.6), (90, 70, 60), "stone", 0.15)  # an ash heap
            G.box(M @ CF(5.5, 0.85, -2.2), (1.2, 0.2, 1.0), self.EMBER, "glow", 0.05)
        else:
            for i in range(7):
                G.box(M @ CF(r.uniform(-6.5, 6.5), 0.12, -r.uniform(1.4, 3)), (r.uniform(0.8, 1.8), 0.24, 0.8),
                      r.choice((self.MOSS, self.MOSS2)), "stone", 0.08)
            for i in range(4):  # little mushrooms in the plinth joints
                x = r.uniform(-6, 6)
                G.box(M @ CF(x, 1.75, -1.3), (0.12, 0.3, 0.12), (240, 236, 220), "satin", 0.0)
                G.box(M @ CF(x, 1.95, -1.3), (0.4, 0.14, 0.4), (220, 120, 90), "satin", 0.05)


# ================================================================================================ B: The Weatherworks
class StyleB(Style):
    """the Cloud-Smiths' guild built the machine halls inside the island to make the sky's weather; they left, the
    machines still hiss"""
    name = "b"
    proud = 0.3
    WHITE, WHITE2, SEAM = (236, 238, 244), (220, 224, 236), (128, 138, 164)
    PLINTH, PLINTH2 = (62, 76, 108), (50, 62, 92)
    COPPER, COPPERD, BRASS = (74, 172, 142), (54, 136, 112), (222, 172, 72)
    IRON, FLOOR, FLOOR2 = (72, 78, 96), (128, 140, 168), (112, 124, 154)
    CYAN, NAVY, CANVAS = (130, 226, 255), (64, 82, 136), (238, 232, 216)
    GIRDER = (84, 104, 146)  # storm-blue painted iron
    WARM = (255, 200, 130)
    light_col = (176, 226, 255)

    def __init__(self):
        self.rng = random.Random(13)

    def wall(self, G, M, L, door=None, holes=(), key="", theme=None):
        r = self.rng
        h = WALL_H
        body_with_door(G, M, L, h, self.SEAM, door)
        hl = list(holes)
        if door:
            hl.append(door_hole(door.get("X", 0), door.get("W", 8) + 2.0, 8.6))
        lay_bricks(G, M, L, 0, 1.8, 1.8, (3.0, 3.0), 1.2, -0.95, lambda x, y, rr: jit(self.PLINTH, rr, 4), r,
                   gap=0.12, ch=0.12, holes=hl)
        G.box(M @ CF(0, 1.9, -1.6), (L, 0.2, 0.3), self.BRASS, "metal", 0.04)  # brass rail on the plinth

        def col(x, y, rr):
            c = rr.choice((self.WHITE, self.WHITE, self.WHITE2))
            if theme == "frost":
                c = mix(c, (210, 232, 250), 0.5)
            elif theme == "ember":
                c = mix(c, (70, 60, 64), max(0.0, (y - 6) / 9) * 0.75)
            elif theme == "moss" and y < 5:
                c = mix(c, (150, 190, 140), 0.25)
            return jit(c, rr, 4)

        # big dressed panels with rivets at the corners
        y = 1.8
        while y < h - 1.0:
            hh = min(3.3, h - 1.0 - y)
            x = -L / 2
            while x < L / 2 - 0.3:
                ww = min(4.0, L / 2 - x)
                if not any(hx(x, x + ww, y, y + hh) for hx in hl):
                    G.box(M @ CF(x + ww / 2, y + hh / 2, -0.62), (ww - 0.2, hh - 0.2, 0.25), col(x, y, r), "satin", 0.12)
                    for cx in (x + 0.35, x + ww - 0.35):
                        for cy in (y + 0.35, y + hh - 0.35):
                            G.box(M @ CF(cx, cy, -0.78), (0.2, 0.2, 0.1), self.BRASS, "metal", 0.04)
                x += ww
            y += hh
        G.box(M @ CF(0, h - 0.5, -0.7), (L, 1.0, 1.6), self.IRON, "metal", 0.08)  # the iron girder on top
        for i in range(int(L / 2)):
            G.box(M @ CF(-L / 2 + 1 + i * 2, h - 0.5, -1.52), (0.18, 0.18, 0.08), self.BRASS, "metal", 0.03)
        # pipes: two runs on stand-off brackets, brass flanges every 6 studs, drops every 18
        pipe = self.COPPER
        if theme == "ember":
            pipe = (226, 120, 70)
        for py in (4.2, 12.2):
            segs = [(-L / 2, L / 2)]
            for hx in hl:
                if hx(-1, 1, py - 0.4, py + 0.4) or hx(-L / 2, L / 2, py - 0.4, py + 0.4):
                    pass
            if door:
                dx, dw = door.get("X", 0), door.get("W", 8) + 2.2
                if py < 9.5:
                    segs = [(-L / 2, dx - dw / 2), (dx + dw / 2, L / 2)]
            for a, b in segs:
                if b - a < 1:
                    continue
                G.box(M @ CF((a + b) / 2, py, -1.25), (b - a, 0.75, 0.75), pipe, "metal", 0.26)
                x = a + 1.5
                while x < b - 1:
                    G.box(M @ CF(x, py, -1.25), (0.3, 1.05, 1.05), self.BRASS, "metal", 0.1)
                    G.box(M @ CF(x, py, -0.75), (0.25, 0.3, 0.6), self.IRON, "metal", 0.04)
                    x += 6
        x = -L / 2 + 5
        while x < L / 2 - 2:
            if not any(hx(x - 0.5, x + 0.5, 4, 12) for hx in hl):
                G.box(M @ CF(x, 8.2, -1.25), (0.75, 8.0, 0.75), pipe, "metal", 0.26)
                # a pressure gauge
                Gm = M @ CF(x + 1.6, 8.2, -1.0)
                ring(G, Gm, 0.7, 8, (0.62, 0.22, 0.4), self.BRASS, "metal", ch=0.06)
                G.box(Gm @ CF(0, 0, 0.05), (1.1, 1.1, 0.15), (240, 244, 236), "glowsoft", 0.2)
                G.box(Gm @ CF(0.18, 0.12, -0.08) @ ANG(0, 0, -0.7), (0.1, 0.6, 0.05), (200, 50, 50), "satin", 0.0)
            x += 18

    def floor(self, G, M, w, d, theme=None):
        r = random.Random(29)
        nx, nz = round(w / 6), round(d / 6)
        tw, td = w / nx, d / nz
        G.box(M @ CF(0, -0.4, 0), (w, 0.6, d), (60, 66, 84), "stone", 0.0)
        for i in range(nx):
            for j in range(nz):
                cx, cz = -w / 2 + (i + 0.5) * tw, -d / 2 + (j + 0.5) * td
                c = self.FLOOR if (i + j) % 2 else self.FLOOR2
                if theme == "frost":
                    c = mix(c, (220, 236, 250), 0.45)
                elif theme == "ember":
                    c = mix(c, (110, 96, 96), 0.4)
                G.box(M @ CF(cx, -0.2, cz), (tw - 0.2, 0.4, td - 0.2), jit(c, r, 5), "satin", 0.12)
                G.box(M @ CF(cx, 0.02, cz), (tw - 1.4, 0.04, td - 1.4), jit(mix(c, (255, 255, 255), 0.12), r, 3),
                      "satin", 0.0)
        # brass-edged grates across the room every 12 studs, a faint cyan hum under the slots
        z = -d / 2 + 6
        while z < d / 2 - 3:
            for e in (-0.75, 0.75):
                G.box(M @ CF(0, -0.0, z + e), (w, 0.08, 0.16), self.BRASS, "metal", 0.0)
            G.box(M @ CF(0, -0.06, z), (w - 0.4, 0.06, 1.1), (34, 78, 100), "glowsoft", 0.0)
            x = -w / 2 + 0.4
            while x < w / 2:
                G.box(M @ CF(x, 0.0, z), (0.22, 0.08, 1.2), (52, 58, 74), "metal", 0.0)
                x += 0.6
            z += 12

    def pillar(self, G, M, h, col=None):
        G.box(M @ CF(0, 0.7, 0), (3.0, 1.4, 3.0), self.PLINTH, "stone", 0.15)
        G.box(M @ CF(0, h / 2, 0), (2.2, h - 1.0, 2.2), self.WHITE, "satin", 0.25)
        for y in (3.0, 7.5, 12.0):
            if y < h - 1.5:
                G.box(M @ CF(0, y, 0), (2.5, 0.45, 2.5), self.COPPER, "metal", 0.1)
                for a in range(4):
                    G.box(M @ CF(0, y, 0) @ ANG(0, a * PI / 2, 0) @ CF(0, 0, -1.28), (0.18, 0.18, 0.08),
                          self.BRASS, "metal", 0.03)
        G.box(M @ CF(0, h - 0.4, 0), (3.0, 0.8, 3.0), self.BRASS, "metal", 0.12)

    def torch(self, G, M):
        # a brass storm lantern with a bottled spark of lightning
        G.box(M @ CF(0, 0, -0.1), (0.8, 1.2, 0.2), self.IRON, "metal", 0.04)
        G.box(M @ CF(0, 0.5, -0.55), (0.25, 0.25, 0.9), self.BRASS, "metal", 0.04)
        L = M @ CF(0, -0.1, -1.1)
        G.box(L @ CF(0, -0.75, 0), (0.95, 0.25, 0.95), self.BRASS, "metal", 0.06)
        G.box(L @ CF(0, 0.85, 0), (1.0, 0.25, 1.0), self.BRASS, "metal", 0.06)
        G.box(L @ CF(0, 1.15, 0), (0.5, 0.35, 0.5), self.BRASS, "metal", 0.06)
        for dx in (-0.42, 0.42):
            for dz in (-0.42, 0.42):
                G.box(L @ CF(dx, 0.05, dz), (0.1, 1.4, 0.1), self.BRASS, "metal", 0.0)
        G.box(L @ CF(0, 0.05, 0), (0.7, 1.3, 0.7), (190, 230, 255), "glass", 0.05)
        G.box(L @ CF(0, 0.05, 0), (0.32, 0.7, 0.32), self.CYAN, "glow", 0.05)
        G.box(L @ CF(0.05, 0.2, 0) @ ANG(0, 0, 0.6), (0.06, 0.5, 0.06), (255, 255, 255), "glow", 0.0)
        G.light(L, 0, 0, -0.5, self.light_col, 300, 0.3, 26)

    def banner(self, G, M, askew=False, accent=None):
        accent = accent or self.accent
        G.box(M @ CF(0, 0, -0.3), (4.4, 0.25, 0.6), self.BRASS, "metal", 0.06)  # the rail, bolted on
        for dx in (-1.9, 1.9):
            G.box(M @ CF(dx, 0, -0.08), (0.4, 0.4, 0.16), self.IRON, "metal", 0.04)
        C = M @ CF(0, 0, -0.55) @ ANG(0, 0, 0.03 if askew else 0)
        G.box(C @ CF(0, -2.6, 0), (3.4, 5.0, 0.12), self.CANVAS, "cloth", 0.03)
        G.box(C @ CF(0, -4.7, -0.05), (3.4, 0.7, 0.05), accent, "cloth", 0.0)
        for dx, dy, s in ((-0.4, -1.8, 1.0), (0.4, -1.7, 1.2), (0.0, -2.2, 1.6)):
            G.box(C @ CF(dx, dy, -0.07), (s, s * 0.6, 0.04), self.NAVY, "cloth", 0.0)
        for i, (dx, dy) in enumerate(((0.1, -2.9), (-0.15, -3.3), (0.1, -3.7))):
            G.box(C @ CF(dx, dy, -0.08) @ ANG(0, 0, 0.6 if i % 2 == 0 else -0.6), (0.18, 0.55, 0.04), (250, 210, 60),
                  "cloth", 0.0)
        for i in range(3):  # grommets on top
            G.box(C @ CF(-1.2 + i * 1.2, -0.25, -0.07), (0.2, 0.2, 0.04), self.BRASS, "metal", 0.0)

    def carpet(self, G, O):
        G.box(O @ CF(0, 0.07, -8), (7, 0.14, 48.4), self.NAVY, "cloth", 0.03)
        for sx in (-3.4, 3.4):
            G.box(O @ CF(sx, 0.1, -8), (0.3, 0.16, 48.4), self.BRASS, "metal", 0.03)
        z = -31
        while z < 15:
            for s in (-1, 1):
                G.box(O @ CF(s * 0.75, 0.15, z) @ ANG(0, s * 0.75, 0), (2.0, 0.03, 0.4), (226, 232, 244), "cloth", 0.0)
            z += 3
        for i in range(1, 4):
            G.box(O @ CF(0, i * 0.8 + 0.05, 16.2 + (i - 0.5) * 1.6), (7, 0.1, 1.6), self.NAVY, "cloth", 0.0)
            G.box(O @ CF(0, i * 0.8 + 0.12, 16.2 + (i - 1) * 1.6 + 0.12), (7.2, 0.08, 0.24), self.BRASS, "metal", 0.0)
        G.box(O @ CF(0, 2.45, 25), (7, 0.1, 8), self.NAVY, "cloth", 0.02)

    def dais(self, G, O, dz):
        G.box(O @ CF(0, 1.1, dz), (24, 2.2, 14), self.WHITE2, "satin", 0.12)
        G.box(O @ CF(0, 2.3, dz), (24.4, 0.2, 14.4), self.BRASS, "metal", 0.05)
        G.box(O @ CF(0, 2.36, dz + 0.3), (23.4, 0.12, 13.4), self.WHITE2, "satin", 0.04)
        for i in range(12):
            G.box(O @ CF(-11 + i * 2, 1.2, dz - 7.08), (0.2, 0.2, 0.1), self.BRASS, "metal", 0.03)
        G.box(O @ CF(0, 0.45, dz - 7.1), (24, 0.12, 0.12), self.BRASS, "metal", 0.0)
        for i in range(1, 4):
            G.box(O @ CF(0, (i - 0.5) * 0.8, dz - 11.8 + (i - 0.5) * 1.6), (10.6, 0.78, 1.58), self.PLINTH, "stone", 0.1)

    def throne(self, G, T):
        # the lightning-rod throne, with the guild's weather astrolabe turning behind it
        G.box(T @ CF(0, 0.6, 0), (4.4, 1.2, 3.4), self.IRON, "metal", 0.12)
        G.box(T @ CF(0, 1.5, -0.1), (3.8, 0.6, 3.0), self.BRASS, "metal", 0.1)
        G.box(T @ CF(0, 1.95, -0.2), (3.0, 0.4, 2.4), self.NAVY, "cloth", 0.15)
        G.box(T @ CF(0, 4.4, 1.3), (3.8, 5.2, 0.5), self.IRON, "metal", 0.1)
        for sx in (-1, 1):
            G.box(T @ CF(sx * 1.85, 4.4, 1.3), (0.3, 5.4, 0.7), self.BRASS, "metal", 0.06)
            G.box(T @ CF(sx * 2.1, 2.5, 0), (0.6, 1.2, 3.0), self.BRASS, "metal", 0.08)
        G.box(T @ CF(0, 4.6, 1.0), (2.6, 3.6, 0.12), self.NAVY, "cloth", 0.03)
        G.box(T @ CF(0, 8.4, 1.5), (0.35, 6.0, 0.35), self.COPPER, "metal", 0.1)  # the rod
        G.box(T @ CF(0, 11.6, 1.5), (0.8, 0.8, 0.8), self.BRASS, "metal", 0.3)
        G.box(T @ CF(0, 11.6, 1.5), (0.4, 1.2, 0.4), self.CYAN, "glow", 0.05)
        A = T @ CF(0, 7.0, 3.6)
        ring(G, A, 5.2, 28, (1.25, 0.45, 0.45), self.BRASS, "metal")
        ring(G, A @ ANG(0, 1.1, 0), 4.4, 24, (1.2, 0.4, 0.4), self.COPPER, "metal")
        ring(G, A @ ANG(1.2, 0, 0.3), 3.6, 20, (1.2, 0.35, 0.35), self.BRASS, "metal")
        for dx, dy, dz, s in ((0, 0, 0, 2.2), (-1.1, -0.3, 0.2, 1.5), (1.1, -0.2, -0.2, 1.6), (0.3, 0.9, 0.1, 1.4),
                              (-0.6, 0.7, -0.4, 1.1)):
            G.box(A @ CF(dx, dy, dz), (s, s * 0.85, s), (246, 248, 255), "satin", 0.35)  # the captured cloud
        G.box(A @ CF(0, -0.1, -0.9), (0.9, 0.9, 0.5), self.CYAN, "glow", 0.1)
        G.box(A @ CF(0, -5.3, 0), (0.9, 1.6, 0.9), self.IRON, "metal", 0.1)
        G.light(A, 0, 0, -2.5, self.CYAN, 700, 1.0, 30)

    def brazier(self, G, B):
        # a condenser coil instead of a fire bowl
        G.box(B @ CF(0, 0.4, 0), (2.2, 0.8, 2.2), self.IRON, "metal", 0.1)
        for k in range(7):
            G.box(B @ CF(0, 1.0 + k * 0.38, 0), (1.6, 0.22, 1.6), self.COPPER if k % 2 else self.BRASS, "metal", 0.08)
        G.box(B @ CF(0, 2.2, 0), (0.9, 2.6, 0.9), self.IRON, "metal", 0.05)
        G.box(B @ CF(0, 4.0, 0), (1.5, 1.1, 1.5), (200, 236, 255), "glass", 0.3)
        G.box(B @ CF(0, 4.0, 0), (0.7, 0.7, 0.7), self.CYAN, "glow", 0.2)
        G.light(B, 0, 4.6, 0, self.light_col, 420, 0.5, 26)

    def arch(self, G, A):
        for sx in (-6, 6):
            G.box(A @ CF(sx, 0.6, 0), (2.6, 1.2, 2.6), self.PLINTH, "stone", 0.12)
            G.box(A @ CF(sx, 4.6, 0), (0.5, 7.0, 1.8), self.GIRDER, "satin", 0.05)  # I-beam web
            for dz in (-0.85, 0.85):
                G.box(A @ CF(sx, 4.6, dz), (1.6, 7.0, 0.22), self.GIRDER, "satin", 0.05)
            for y in range(2, 8, 2):
                for dz in (-0.98, 0.98):
                    for dx in (-0.55, 0.55):
                        G.box(A @ CF(sx + dx, y, dz), (0.2, 0.2, 0.1), self.BRASS, "metal", 0.03)
        n = 16  # the riveted girder: an elliptical arch of I-beam segments (web + two flanges)
        for i in range(n):
            a0, a1 = PI * i / n, PI * (i + 1) / n
            p0 = (6 * math.cos(a0), 8.1 + 5.0 * math.sin(a0))
            p1 = (6 * math.cos(a1), 8.1 + 5.0 * math.sin(a1))
            ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
            M = A @ CF((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, 0) @ ANG(0, 0, math.atan2(p1[1] - p0[1], p1[0] - p0[0]))
            G.box(M, (ln + 0.05, 1.3, 0.5), self.GIRDER, "satin", 0.03)
            for dz in (-0.85, 0.85):
                G.box(M @ CF(0, 0, dz), (ln + 0.05, 1.6, 0.22), self.GIRDER, "satin", 0.03)
            G.box(M @ CF(0, 0, -0.98), (0.2, 0.2, 0.08), self.BRASS, "metal", 0.03)
        G.box(A @ CF(0, 13.0, -1.0), (2.6, 0.9, 0.12), self.BRASS, "metal", 0.04)  # sector plate
        G.box(A @ CF(0, 13.0, -1.08), (2.0, 0.4, 0.04), self.NAVY, "satin", 0.0)
        # a hanging weathervane rooster, a small guild joke
        G.box(A @ CF(0, 11.7, 0), (0.12, 1.4, 0.12), self.IRON, "metal", 0.0)
        G.box(A @ CF(0, 10.9, 0), (1.4, 0.12, 0.12), self.BRASS, "metal", 0.0)
        G.box(A @ CF(0.2, 10.3, 0), (0.9, 0.7, 0.12), self.BRASS, "metal", 0.04)
        G.box(A @ CF(0.65, 10.75, 0), (0.35, 0.45, 0.12), self.BRASS, "metal", 0.04)

    def statue(self, G, S, sx):
        # a retired weather automaton (barometer head, anemometer cups) still standing guard
        G.box(S @ CF(0, 0.6, 0), (3.0, 1.2, 3.0), self.PLINTH, "stone", 0.15)
        for dx in (-0.55, 0.55):
            G.box(S @ CF(dx, 1.5, -0.1), (0.8, 0.6, 1.3), self.IRON, "metal", 0.1)
            G.box(S @ CF(dx, 2.2, 0), (0.55, 1.1, 0.55), self.COPPERD, "metal", 0.08)
        G.box(S @ CF(0, 3.7, 0), (2.0, 2.2, 1.6), self.BRASS, "metal", 0.35)
        for y in (3.0, 4.4):
            G.box(S @ CF(0, y, 0), (2.1, 0.18, 1.7), self.COPPER, "metal", 0.06)
        for dx in (-1.25, 1.25):
            G.box(S @ CF(dx, 3.6, 0), (0.45, 1.6, 0.45), self.COPPERD, "metal", 0.08)
            G.box(S @ CF(dx, 2.6, 0), (0.6, 0.5, 0.6), self.IRON, "metal", 0.1)
        Hd = S @ CF(0, 5.6, 0)
        G.box(Hd, (1.5, 1.5, 1.0), self.BRASS, "metal", 0.4)
        G.box(Hd @ CF(0, 0, -0.5), (1.1, 1.1, 0.08), (244, 240, 226), "glowsoft", 0.25)
        G.box(Hd @ CF(0.12, 0.12, -0.56) @ ANG(0, 0, -0.9 if sx < 0 else 0.6), (0.08, 0.5, 0.04), (40, 40, 50),
              "satin", 0.0)
        G.box(Hd @ CF(0, 1.1, 0), (0.12, 0.8, 0.12), self.IRON, "metal", 0.0)
        for a in range(3):
            t = a * 2 * PI / 3 + (0.4 if sx > 0 else 0)
            G.box(Hd @ CF(math.cos(t) * 0.35, 1.5, math.sin(t) * 0.35) @ ANG(0, -t, 0), (0.7, 0.06, 0.06), self.IRON,
                  "metal", 0.0)
            G.box(Hd @ CF(math.cos(t) * 0.7, 1.5, math.sin(t) * 0.7), (0.24, 0.24, 0.24), self.COPPER, "metal", 0.08)

    def exit_door(self, G, D):
        G.box(D @ CF(-4.9, 4.4, -0.55), (1.4, 8.8, 1.2), self.IRON, "metal", 0.08)
        G.box(D @ CF(4.9, 4.4, -0.55), (1.4, 8.8, 1.2), self.IRON, "metal", 0.08)
        G.box(D @ CF(0, 8.9, -0.55), (11.2, 1.2, 1.2), self.IRON, "metal", 0.08)
        for y in range(1, 9):
            for sx in (-1, 1):
                G.box(D @ CF(sx * 4.9, y, -1.2), (0.22, 0.22, 0.1), self.BRASS, "metal", 0.03)
        for i in range(5):
            G.box(D @ CF(-3.2 + i * 1.6, 4.0, -0.4), (0.32, 8, 0.32), self.IRON, "metal", 0.04)
        for y in (2, 5.5):
            G.box(D @ CF(0, y, -0.4), (8, 0.3, 0.3), self.IRON, "metal", 0.04)
        # sooty handprints on the hatch frame (somebody pushes here every day)
        for dx, dy in ((3.4, 4.6), (3.9, 4.1)):
            G.box(D @ CF(dx + 1.5, dy, -1.18), (0.5, 0.6, 0.04), (52, 48, 52), "stone", 0.0)

    def extras(self, G, O):
        # the big valve wheel on the back wall, with a chalk arrow; a wrench left on the floor beneath
        V0 = O @ back_frame(-14, 7) @ CF(0, 0, -0.9)
        ring(G, V0, 1.6, 12, (0.85, 0.3, 0.3), (200, 60, 60), "metal")
        for a in range(3):
            G.box(V0 @ ANG(0, 0, a * PI / 3), (3.2, 0.2, 0.2), (200, 60, 60), "metal", 0.0)
        G.box(V0 @ CF(0, 0, 0.3), (0.6, 0.6, 0.6), self.BRASS, "metal", 0.1)
        G.box(V0 @ CF(2.6, 0.9, 0.55), (1.4, 0.12, 0.02), (250, 250, 250), "satin", 0.0)
        G.box(V0 @ CF(3.15, 1.15, 0.55) @ ANG(0, 0, 0.8), (0.6, 0.12, 0.02), (250, 250, 250), "satin", 0.0)
        G.box(O @ CF(-12.6, 0.1, 33.8) @ ANG(0, 0.5, 0), (1.8, 0.16, 0.4), (170, 176, 190), "metal", 0.04)
        # a leaking pipe on the right wall with a bucket and a puddle under it
        Lk = O @ side_frame(1, 14, 0)
        G.box(Lk @ CF(0, 3.95, -1.25), (0.3, 0.3, 1.1), self.COPPERD, "metal", 0.06)  # a cracked spout
        G.box(Lk @ CF(0, 2.9, -1.75), (0.08, 1.6, 0.08), (150, 220, 255), "glass", 0.0)
        G.box(Lk @ CF(0, 0.55, -1.75), (1.1, 1.1, 1.1), (130, 136, 150), "metal", 0.08)
        G.box(Lk @ CF(0, 1.0, -1.75), (0.9, 0.08, 0.9), (120, 190, 240), "glass", 0.0)
        G.box(Lk @ CF(0.6, 0.04, -2.9), (2.6, 0.06, 1.6), (120, 190, 240), "glass", 0.0)
        # the maintenance clipboard hanging on the right wall's pipe
        Cb = O @ side_frame(1, 22, 11.4) @ CF(0, 0, -1.2)
        G.box(Cb, (0.9, 1.2, 0.06), (170, 120, 80), "wood", 0.02)
        G.box(Cb @ CF(0, -0.05, -0.04), (0.75, 0.95, 0.02), (250, 248, 240), "satin", 0.0)
        for i in range(4):
            G.box(Cb @ CF(-0.05, 0.25 - i * 0.18, -0.06), (0.5, 0.04, 0.01), (60, 70, 110), "satin", 0.0)

    def theme_dress(self, G, M, theme):
        r = random.Random(7 + len(theme))
        if theme == "frost":
            for py in (4.2, 12.2):  # frost caps on the pipes, icicles under them
                G.box(M @ CF(0, py + 0.45, -1.25), (14, 0.2, 0.9), (236, 246, 255), "satin", 0.06)
                for i in range(7):
                    ln = r.uniform(0.4, 1.3)
                    G.box(M @ CF(-6 + i * 2 + r.uniform(-0.3, 0.3), py - 0.4 - ln / 2, -1.25), (0.25, ln, 0.25),
                          (220, 240, 255), "satin", 0.05)
            Cv = M @ CF(5.2, 3.0, -1.6)  # a cryo valve
            G.box(Cv, (1.6, 1.6, 0.8), self.IRON, "metal", 0.15)
            G.box(Cv @ CF(0, 0, -0.45), (1.0, 1.0, 0.1), (140, 220, 255), "glow", 0.1)
        elif theme == "ember":
            Fd = M @ CF(5.0, 0, -0.9)  # the boiler's fire door
            G.box(Fd @ CF(0, 1.6, 0), (3.0, 3.2, 1.0), self.IRON, "metal", 0.12)
            G.box(Fd @ CF(0, 1.4, -0.52), (1.8, 1.0, 0.1), (255, 130, 50), "glow", 0.05)
            for i in range(4):
                G.box(Fd @ CF(-0.65 + i * 0.43, 1.4, -0.6), (0.12, 1.0, 0.08), self.IRON, "metal", 0.0)
            G.light(Fd, 0, 1.4, -1.5, (255, 140, 60), 260, 0.4, 14)
        else:
            Tk = M @ CF(5.0, 0, -1.6)  # a rain tank, moss creeping up its copper bands
            G.box(Tk @ CF(0, 2.6, 0), (2.6, 5.0, 2.0), (150, 210, 240), "glass", 0.2)
            G.box(Tk @ CF(0, 1.6, 0), (2.3, 2.6, 1.7), (90, 160, 210), "glass", 0.1)
            for y in (0.4, 2.6, 4.9):
                G.box(Tk @ CF(0, y, 0), (2.75, 0.3, 2.15), self.COPPER, "metal", 0.06)
            for i in range(6):
                G.box(M @ CF(r.uniform(-6.5, 3), r.choice((4.6, 12.6)), -1.25), (r.uniform(0.6, 1.4), 0.25, 0.8),
                      (96, 160, 80), "stone", 0.08)


# ================================================================================================ C: Root Conservatory
class StyleC(Style):
    """the island's gardeners dug a seed vault into the island's soil; the island's own roots broke in and it went wild"""
    name = "c"
    proud = 0.26
    TERRA, TERRA2, TERRA3 = (198, 118, 84), (176, 100, 70), (212, 136, 98)
    MORTAR, SOIL, SOIL2 = (122, 96, 80), (104, 82, 66), (88, 70, 56)
    ROOT, ROOT2 = (124, 86, 56), (100, 68, 44)
    LEAF, LEAF2, LEAF3 = (88, 164, 82), (64, 134, 72), (126, 190, 98)
    RIB, BULB, BURLAP = (228, 234, 224), (255, 226, 130), (204, 178, 132)
    FLAG, FLAG2 = (148, 150, 128), (132, 136, 116)
    light_col = (255, 214, 140)

    def __init__(self):
        self.rng = random.Random(17)

    def wall(self, G, M, L, door=None, holes=(), key="", theme=None):
        r = self.rng
        h = WALL_H
        body_with_door(G, M, L, h, self.MORTAR, door)
        hl = list(holes)
        if door:
            hl.append(door_hole(door.get("X", 0), door.get("W", 8) + 1.6, 8.6))
        lay_bricks(G, M, L, 0, 2.4, 1.2, (1.6, 3.2), 1.0, -0.8, lambda x, y, rr: jit(rr.choice((self.SOIL, self.SOIL2)),
                                                                                      rr, 6), r, gap=0.12, ch=0.15,
                   holes=hl, tilt=0.03)

        def col(x, y, rr):
            c = rr.choice((self.TERRA, self.TERRA, self.TERRA2, self.TERRA3))
            if theme == "frost":
                c = mix(c, (220, 226, 236), 0.35)
            elif theme == "ember":
                c = mix(c, (80, 56, 50), max(0.0, (y - 7) / 8) * 0.7)
            return jit(c, rr, 7)

        lay_bricks(G, M, L, 2.4, h - 0.6, 0.8, (1.4, 2.0), 0.4, -0.6, col, r, gap=0.1, ch=0.08, holes=hl)
        G.box(M @ CF(0, h - 0.3, -0.7), (L, 0.6, 1.6), self.RIB, "satin", 0.1)  # the glasshouse sill
        # glasshouse ribs every 9 studs, rising into the (missing) glass roof
        x = -L / 2 + 4.5
        while x < L / 2 - 1:
            if not any(hx(x - 0.3, x + 0.3, 0, h) for hx in hl):
                G.box(M @ CF(x, 9.0, -1.0), (0.4, 12.0, 0.4), self.RIB, "satin", 0.08)
                G.box(M @ CF(x, h + 0.9, -1.6) @ ANG(-0.6, 0, 0), (0.4, 2.6, 0.4), self.RIB, "satin", 0.08)
                if theme is None and key != "back" and int(x) % 2 == 0:  # a star-bulb hung off the rib tip
                    self.bulb(G, M @ CF(x, h - 0.8, -2.33), r, light=(int(x) % 4 == 0), cord=2.75)
            x += 9
        # roots breaking in from the top and crawling down; leaves along them; star-bulbs hanging off them
        n = max(1, int(L / 11))
        rootc = self.ROOT
        if theme == "frost":
            rootc = (190, 196, 210)
        elif theme == "ember":
            rootc = (60, 44, 40)
        for k in range(n):
            x = -L / 2 + (k + 0.5) * L / n + r.uniform(-2, 2)
            if any(hx(x - 3, x + 3, 0, h) for hx in hl):
                continue
            y = h - 0.2
            th = 1.1
            while y > 2.5 and th > 0.3:
                dx = r.uniform(-0.9, 0.9)
                seg = r.uniform(1.0, 1.8)
                G.box(M @ CF(x + dx / 2, y - seg / 2, -0.95) @ ANG(0, 0, math.atan2(dx, seg)),
                      (th, seg + 0.3, th * 0.9), jit(rootc, r, 5), "wood", 0.15)
                if r.random() < 0.45:
                    side = r.choice((-1, 1))
                    G.box(M @ CF(x + side * 0.9, y - 0.4, -0.9) @ ANG(0, 0, side * 1.0), (0.4, 1.6, 0.4),
                          jit(rootc, r, 5), "wood", 0.08)
                if r.random() < 0.7:
                    self.leaves(G, M @ CF(x + r.uniform(-1, 1), y - 0.5, -1.25), r, theme)
                x += dx
                y -= seg
                th *= 0.9
            if theme is None and r.random() < 0.8:
                self.bulb(G, M @ CF(x + 0.3, y + 2.2, -1.25), r)

    def leaves(self, G, M, r, theme=None, n=4):
        for i in range(n):
            c = r.choice((self.LEAF, self.LEAF2, self.LEAF3))
            if theme == "frost":
                c = r.choice(((214, 236, 250), (180, 214, 236), (240, 248, 255)))
            elif theme == "ember":
                c = r.choice(((240, 108, 56), (255, 170, 60), (200, 60, 50)))
            G.box(M @ CF(r.uniform(-0.6, 0.6), r.uniform(-0.6, 0.6), r.uniform(-0.2, 0.1)) @
                  ANG(r.uniform(-0.4, 0.4), r.uniform(-0.5, 0.5), r.uniform(-0.8, 0.8)),
                  (r.uniform(0.6, 1.0), 0.45, 0.14), c, "glowsoft" if theme == "ember" and i == 0 else "satin", 0.06)

    def bulb(self, G, M, r, light=False, cord=1.4):
        G.box(M @ CF(0, cord / 2, 0), (0.06, cord, 0.06), (90, 70, 50), "wood", 0.0)
        G.box(M, (0.55, 0.65, 0.55), self.BULB, "glow", 0.18)
        G.box(M @ CF(0, 0.38, 0), (0.35, 0.15, 0.35), self.LEAF2, "satin", 0.03)
        if light:
            G.light(M, 0, 0, 0, self.light_col, 120, 0.3, 16)

    def floor(self, G, M, w, d, theme=None):
        r = random.Random(37)
        G.box(M @ CF(0, -0.35, 0), (w, 0.6, d), (70, 80, 56), "stone", 0.0)
        z = -d / 2
        row = 0
        while z < d / 2 - 0.1:
            td = min(r.choice((3.0, 4.0)), d / 2 - z)
            x = -w / 2 - r.uniform(0, 2)
            while x < w / 2:
                tw = r.choice((2.5, 3.5, 4.5))
                xa, xb = max(x, -w / 2), min(x + tw, w / 2)
                c = r.choice((self.FLAG, self.FLAG2))
                if theme == "frost":
                    c = mix(c, (220, 232, 244), 0.5)
                elif theme == "ember":
                    c = mix(c, (96, 86, 82), 0.5)
                if xb - xa > 0.4:
                    G.box(M @ CF((xa + xb) / 2, -0.2 + r.uniform(-0.03, 0.03), z + td / 2) @ ANG(0, r.uniform(-0.03, 0.03), 0),
                          (xb - xa - 0.3, 0.42, td - 0.3), jit(c, r, 7), "stone", 0.14)
                    if r.random() < 0.35 and theme != "ember":  # grass in the joints
                        G.box(M @ CF(xa, 0.05, z + td / 2), (0.28, 0.16, td * r.uniform(0.3, 0.8)),
                              (220, 236, 250) if theme == "frost" else self.LEAF2, "satin", 0.0)
                x += tw
            z += td
            row += 1

    def pillar(self, G, M, h, col=None):
        r = self.rng
        G.box(M @ CF(0, 0.8, 0), (3.0, 1.6, 3.0), self.TERRA2, "stone", 0.2)  # a planter at the foot
        G.box(M @ CF(0, 1.55, 0), (2.6, 0.1, 2.6), (80, 60, 46), "stone", 0.0)
        y = 1.6
        k = 0
        while y < h - 0.8:
            G.box(M @ CF(0, y + 0.4, 0) @ ANG(0, (k % 2) * 0.02, 0), (2.0 + (k % 2) * 0.15, 0.72, 2.0 + ((k + 1) % 2) * 0.15),
                  jit(r.choice((self.TERRA, self.TERRA2, self.TERRA3)), r, 6), "stone", 0.08)
            y += 0.8
            k += 1
        G.box(M @ CF(0, h - 0.35, 0), (2.8, 0.7, 2.8), self.RIB, "satin", 0.1)
        # a root spiralling up
        for i in range(int((h - 3.0) / 0.85)):
            a = i * 0.7
            G.box(M @ CF(math.cos(a) * 1.15, 1.8 + i * 0.85, math.sin(a) * 1.15) @ ANG(0, -a, 0.3),
                  (0.55, 1.2, 0.55), jit(self.ROOT, r, 5), "wood", 0.12)
            if i % 3 == 1:
                self.leaves(G, M @ CF(math.cos(a) * 1.5, 2.0 + i * 0.85, math.sin(a) * 1.5), r, None, 3)

    def torch(self, G, M):
        # a jar lantern on an iron hook: a star-bulb in a glass jar
        G.box(M @ CF(0, 1.2, -0.1), (0.3, 0.3, 0.2), (60, 60, 66), "metal", 0.04)
        G.box(M @ CF(0, 1.2, -0.55), (0.18, 0.18, 0.9), (60, 60, 66), "metal", 0.03)
        G.box(M @ CF(0, 0.9, -1.0), (0.16, 0.6, 0.16), (60, 60, 66), "metal", 0.0)
        J = M @ CF(0, -0.1, -1.0)
        G.box(J @ CF(0, 0.65, 0), (0.85, 0.25, 0.85), (150, 104, 66), "wood", 0.06)
        G.box(J, (1.0, 1.2, 1.0), (220, 236, 230), "glass", 0.2)
        G.box(J @ CF(0, -0.1, 0), (0.5, 0.6, 0.5), self.BULB, "glow", 0.15)
        G.box(J @ CF(0, -0.55, 0), (0.8, 0.12, 0.8), (130, 100, 70), "stone", 0.03)
        G.light(J, 0, 0, -0.5, self.light_col, 280, 0.4, 26)

    def banner(self, G, M, askew=False, accent=None):
        # a seed-sack banner on a branch pole hung by twine
        accent = accent or self.accent
        G.box(M @ CF(0, 0.8, -0.1), (0.3, 0.3, 0.2), (60, 60, 66), "metal", 0.04)
        for dx in (-1.6, 1.6):
            G.box(M @ CF(dx * 0.5, 0.4, -0.4) @ ANG(0, 0, -dx * 0.35), (0.05, 1.0, 0.05), (180, 160, 120), "cloth", 0.0)
        C = M @ CF(0, 0, -0.45) @ ANG(0, 0, 0.04 if askew else -0.02)
        G.box(C, (4.4, 0.32, 0.32), self.ROOT2, "wood", 0.1)
        G.box(C @ CF(-2.1, 0.25, 0) @ ANG(0, 0, 0.7), (0.18, 0.6, 0.18), self.ROOT2, "wood", 0.04)
        G.box(C @ CF(0, -2.5, 0.05), (3.4, 4.6, 0.14), self.BURLAP, "cloth", 0.04)
        for i in range(4):
            G.box(C @ CF(-1.3 + i * 0.85, -4.95, 0.05), (0.7, 0.3 + (i % 2) * 0.2, 0.14), self.BURLAP, "cloth", 0.02)
        L0 = C @ CF(0, -2.2, -0.04)
        G.box(L0 @ ANG(0, 0, 0.6), (1.2, 2.2, 0.04), accent, "cloth", 0.0)  # a painted leaf
        G.box(L0 @ ANG(0, 0, 0.6), (0.1, 2.0, 0.03), shade(accent, 0.7), "cloth", 0.0)
        G.box(C @ CF(1.1, -3.8, -0.04) @ ANG(0, 0, 0.1), (0.8, 0.7, 0.03), (172, 140, 96), "cloth", 0.0)  # a patch

    def carpet(self, G, O):
        # a terracotta tile path laid in a herringbone, moss creeping into its joints
        r = random.Random(53)
        G.box(O @ CF(0, -0.02, -8), (7.4, 0.1, 48.4), (90, 70, 58), "stone", 0.0)
        z = -32
        k = 0
        while z < 15.8:
            for i in range(4):
                x = -2.7 + i * 1.8
                if (i + k) % 2:
                    G.box(O @ CF(x, 0.05, z + 0.45), (1.6, 0.1, 0.8), jit(self.TERRA3, r, 8), "stone", 0.05)
                else:
                    G.box(O @ CF(x - 0.4, 0.05, z + 0.45), (0.75, 0.1, 0.8), jit(self.TERRA, r, 8), "stone", 0.05)
                    G.box(O @ CF(x + 0.4, 0.05, z + 0.45), (0.75, 0.1, 0.8), jit(self.TERRA2, r, 8), "stone", 0.05)
                if r.random() < 0.12:
                    G.box(O @ CF(x + 0.8, 0.07, z + 0.45), (0.2, 0.08, 0.8), self.LEAF2, "satin", 0.0)
            z += 0.9
            k += 1
        for sx in (-3.75, 3.75):
            G.box(O @ CF(sx, 0.07, -8), (0.3, 0.14, 48.4), self.SOIL, "stone", 0.05)
        for i in range(1, 4):
            G.box(O @ CF(0, i * 0.8 + 0.05, 16.2 + (i - 0.5) * 1.6), (7, 0.1, 1.6), self.TERRA, "stone", 0.03)
        G.box(O @ CF(0, 2.45, 25), (7, 0.1, 8), self.TERRA3, "stone", 0.03)

    def dais(self, G, O, dz):
        r = random.Random(61)
        G.box(O @ CF(0, 1.1, dz), (24, 2.2, 14), self.SOIL, "stone", 0.12)
        G.box(O @ CF(0, 2.3, dz), (24.4, 0.2, 14.4), (96, 150, 80), "stone", 0.08)  # a moss lawn on top
        for i in range(12):
            G.box(O @ CF(-11 + i * 2, 1.1, dz - 7.1), (1.85, 2.0, 0.2), jit(self.TERRA2, r, 6), "stone", 0.06)
        for i in range(1, 4):
            G.box(O @ CF(0, (i - 0.5) * 0.8, dz - 11.8 + (i - 0.5) * 1.6), (10.6, 0.78, 1.58), jit(self.SOIL2, r, 5),
                  "stone", 0.1)
        for x in (-11, -9.5, 9.5, 11):  # ferns along the dais edge
            for a in range(5):
                G.box(O @ CF(x, 2.9, dz - 6.2) @ ANG(0, a * 1.25, 0.9) @ CF(0, 0.6, 0), (0.35, 1.3, 0.12),
                      self.LEAF if a % 2 else self.LEAF3, "satin", 0.04)

    def throne(self, G, T):
        r = random.Random(71)
        # a hollow stump with the front cut away to make the seat
        for k in range(8):
            a = k * 2 * PI / 8
            if k == 6:
                continue  # the open front (local -Z)
            hh = 5.5 + r.uniform(-0.4, 1.2) if k != 2 else 7.2
            G.box(T @ ANG(0, -a, 0) @ CF(2.2, hh / 2, 0), (1.0, hh, 1.9), jit(self.ROOT, r, 6), "wood", 0.15)
            G.box(T @ ANG(0, -a, 0) @ CF(2.75, hh / 2 - 0.3, 0), (0.15, hh - 0.6, 1.2), self.ROOT2, "wood", 0.0)
        G.box(T @ CF(0, 0.8, 0), (3.6, 1.6, 3.6), (150, 112, 74), "wood", 0.1)
        G.box(T @ CF(0, 1.75, 0), (3.2, 0.4, 3.2), (178, 140, 96), "wood", 0.08)  # the rings of the cut
        ring(G, T @ CF(0, 1.96, 0) @ ANG(PI / 2, 0, 0), 0.9, 10, (0.55, 0.06, 0.06), (150, 110, 70), "wood")
        G.box(T @ CF(0, 2.15, -0.1), (2.6, 0.45, 2.5), (96, 160, 80), "satin", 0.18)  # moss cushion
        for k in range(5):  # roots spreading over the dais
            a = PI * 0.2 + k * PI * 0.3
            G.box(T @ ANG(0, a, 0) @ CF(3.4, 0.25, 0) @ ANG(0, 0, -0.15), (2.4, 0.6, 0.7), self.ROOT2, "wood", 0.15)
        for i in range(9):  # a crown of leaves and star-bulbs on the stump rim
            a = i * PI / 8 + PI
            self.leaves(G, T @ CF(math.cos(a) * 2.1, 6.4 + r.uniform(0, 1.2), math.sin(a) * 2.1 + 0.6), r, None, 3)
        self.bulb(G, T @ CF(-1.6, 6.0, 1.6), r, light=True)
        self.bulb(G, T @ CF(1.5, 5.4, 1.4), r)
        G.box(T @ CF(0.8, 8.6, 1.4) @ ANG(0, 0, -0.3), (0.3, 2.6, 0.3), self.ROOT, "wood", 0.08)
        G.box(T @ CF(1.3, 9.8, 1.4), (1.0, 1.0, 1.0), self.BULB, "glow", 0.3)  # the one star-flower
        for a in range(5):
            G.box(T @ CF(1.3, 9.8, 1.4) @ ANG(0, 0, a * 2 * PI / 5) @ CF(0, 0.75, 0), (0.45, 0.7, 0.2),
                  (255, 246, 210), "satin", 0.08)

    def brazier(self, G, B):
        # a glowing pitcher plant in a big pot
        G.box(B @ CF(0, 0.7, 0), (2.4, 1.4, 2.4), self.TERRA2, "stone", 0.2)
        G.box(B @ CF(0, 1.45, 0), (2.7, 0.3, 2.7), self.TERRA, "stone", 0.1)
        for k, (w, y, hh) in enumerate(((1.2, 2.2, 1.0), (1.5, 3.1, 1.0), (1.7, 4.0, 1.0), (1.4, 4.8, 0.6))):
            G.box(B @ CF(0, y, 0) @ ANG(0, k * 0.2, 0), (w, hh, w), self.LEAF if k % 2 else self.LEAF2, "satin", 0.18)
        G.box(B @ CF(0, 5.0, 0), (1.0, 0.3, 1.0), self.BULB, "glow", 0.1)
        G.box(B @ CF(0.2, 5.7, 0.5) @ ANG(-0.7, 0, 0), (1.5, 0.12, 1.3), (180, 60, 90), "satin", 0.05)  # the lid
        for a in range(4):
            G.box(B @ ANG(0, a * PI / 2 + 0.4, 0) @ CF(1.3, 1.9, 0) @ ANG(0, 0, -0.6), (1.4, 0.15, 0.6), self.LEAF3,
                  "satin", 0.04)
        G.light(B, 0, 5.6, 0, self.light_col, 420, 0.6, 26)

    def arch(self, G, A):
        r = random.Random(83)
        for sx in (-6, 6):
            G.box(A @ CF(sx, 0.8, 0), (2.8, 1.6, 2.8), self.TERRA2, "stone", 0.2)
            G.box(A @ CF(sx, 1.6, 0), (2.4, 0.1, 2.4), (80, 60, 46), "stone", 0.0)
        # two roots grown up out of the planters and woven into an arch (each crosses the top a little)
        n = 18
        for side, off in ((-1, 0.0), (1, 0.35)):
            prev = None
            for i in range(n + 1):
                t = i / n * 1.08
                if t < 0.4:
                    x, y = side * 6.0, 1.7 + (7.6 - 1.7) * t / 0.4
                else:
                    a = (t - 0.4) / 0.6 * PI / 2
                    x, y = side * 6.0 * math.cos(a), 7.6 + 5.4 * math.sin(min(a, PI / 2))
                x += r.uniform(-0.12, 0.12)
                if prev:
                    mx, my = (x + prev[0]) / 2, (y + prev[1]) / 2
                    ln = math.hypot(x - prev[0], y - prev[1])
                    G.box(A @ CF(mx, my, off - 0.2) @ ANG(0, 0, -math.atan2(x - prev[0], y - prev[1])),
                          (1.1 - 0.35 * min(t, 1), ln + 0.35, 1.0 - 0.3 * min(t, 1)),
                          jit(self.ROOT if side < 0 else self.ROOT2, r, 6), "wood", 0.15)
                prev = (x, y)
                if i % 3 == 1 and 0.15 < t < 0.85:
                    self.leaves(G, A @ CF(x, y, -0.5), r, None, 3)
        for dx in (-2.5, 0.5, 3.0):
            ya = 7.6 + 5.4 * math.sqrt(max(0.0, 1 - (dx / 6) ** 2)) - 0.4
            self.bulb(G, A @ CF(dx, ya - 1.8, -0.2), r, cord=1.8)

    def statue(self, G, S, sx):
        # a topiary knight in a planter; one still has the gardener's shears jammed in it
        r = random.Random(97 + int(sx))
        G.box(S @ CF(0, 0.8, 0), (3.2, 1.6, 3.2), self.TERRA2, "stone", 0.2)
        G.box(S @ CF(0, 1.62, 0), (2.8, 0.1, 2.8), (80, 60, 46), "stone", 0.0)
        G.box(S @ CF(0, 1.9, 0), (0.6, 0.6, 0.6), self.ROOT2, "wood", 0.05)
        for (dx, dy, w, hh, dd) in ((0, 3.2, 2.0, 2.2, 1.7), (0, 4.7, 2.3, 1.1, 1.6), (0, 5.8, 1.3, 1.2, 1.3),
                                    (0, 6.7, 0.5, 0.8, 1.2), (-1.4, 4.1, 0.7, 1.8, 0.7), (1.4, 4.4, 0.7, 1.4, 0.7)):
            for k in range(3):  # each block is a clump of leaf boxes, a little shaggy
                G.box(S @ CF(dx + r.uniform(-0.08, 0.08), dy + r.uniform(-0.08, 0.08), r.uniform(-0.08, 0.08)) @
                      ANG(0, r.uniform(-0.1, 0.1), 0), (w - k * 0.06, hh - k * 0.05, dd - k * 0.04),
                      jit(r.choice((self.LEAF, self.LEAF2)), r, 8), "satin", 0.18)
        G.box(S @ CF(-1.9, 4.0, -0.4), (0.4, 2.0, 1.6), self.LEAF2, "satin", 0.18)  # the hedge shield
        if sx > 0:
            for a in (0.25, -0.25):
                G.box(S @ CF(0.6, 5.0, -0.95) @ ANG(0.9, 0, a), (0.12, 1.4, 0.3), (190, 196, 206), "metal", 0.02)
                G.box(S @ CF(0.6, 5.85, -1.6) @ ANG(0.9, 0, a), (0.2, 1.0, 0.2), (200, 60, 50), "satin", 0.05)

    def exit_door(self, G, D):
        for sx in (-1, 1):
            G.box(D @ CF(sx * 4.8, 4.4, -0.6), (1.2, 8.8, 1.2), self.RIB, "satin", 0.1)
        G.box(D @ CF(0, 8.9, -0.6), (10.8, 1.0, 1.2), self.RIB, "satin", 0.1)
        for i in range(5):
            G.box(D @ CF(-3.2 + i * 1.6, 4.0, -0.4), (0.3, 8, 0.3), (60, 60, 66), "metal", 0.04)
        for y in (2, 5.5):
            G.box(D @ CF(0, y, -0.4), (8, 0.3, 0.3), (60, 60, 66), "metal", 0.04)
        r = random.Random(5)
        for i in range(6):  # ivy over the lintel
            self.leaves(G, D @ CF(-4 + i * 1.6, 9.3 - (i % 2) * 0.6, -1.2), r, None, 3)

    def extras(self, G, O):
        r = random.Random(101)
        # a cracked pot spilled by the right wall, a little heap of soil, a patched watering can
        Pt = O @ CF(26.5, 0, 21)
        G.box(Pt @ CF(0, 0.6, 0) @ ANG(0, 0, 1.3), (1.6, 1.2, 1.6), self.TERRA, "stone", 0.15)
        G.box(Pt @ CF(-1.0, 0.25, 0.3), (1.6, 0.5, 1.3), (92, 66, 48), "stone", 0.2)
        G.box(Pt @ CF(0.9, 0.2, -1.0) @ ANG(0, 0.6, 0), (0.7, 0.3, 0.5), self.TERRA2, "stone", 0.05)
        Wc = O @ CF(-11.5, 2.4, 33)
        G.box(Wc @ CF(0, 0.55, 0), (1.3, 1.1, 0.9), (150, 170, 176), "metal", 0.12)
        G.box(Wc @ CF(0.95, 0.75, 0) @ ANG(0, 0, -0.9), (0.2, 1.2, 0.2), (150, 170, 176), "metal", 0.04)
        G.box(Wc @ CF(-0.1, 0.5, -0.46), (0.5, 0.4, 0.05), (196, 160, 90), "metal", 0.02)  # the solder patch
        # a board of seed packets on the right wall (the one the main camera faces)
        Sb = O @ side_frame(1, 23.5, 5.5) @ CF(0, 0, -self.proud - 0.1)
        G.box(Sb, (3.0, 2.2, 0.15), (150, 104, 66), "wood", 0.05)
        for i in range(6):
            G.box(Sb @ CF(-1.0 + (i % 3) * 1.0, 0.5 - (i // 3) * 1.0, -0.1) @ ANG(0, 0, r.uniform(-0.12, 0.12)),
                  (0.7, 0.85, 0.04), r.choice(((240, 200, 90), (220, 120, 140), (130, 180, 230), (150, 210, 120))),
                  "cloth", 0.0)
        # moss mounds against the walls (never on the fight floor)
        for i in range(10):
            sx = r.choice((-1, 1))
            G.box(O @ CF(sx * r.uniform(27.2, 28.6), 0.15, r.uniform(-30, 30)), (r.uniform(1, 2.4), 0.3, r.uniform(1, 3)),
                  r.choice((self.LEAF, self.LEAF2)), "satin", 0.12)

    def theme_dress(self, G, M, theme):
        r = random.Random(11 + len(theme))
        if theme == "frost":
            for i in range(5):  # frost-flowers: crystal petals
                Fm = M @ CF(-5.5 + i * 2.8, 0, -1.6 - r.uniform(0, 1))
                G.box(Fm @ CF(0, 0.5, 0), (0.15, 1.0, 0.15), (190, 214, 230), "satin", 0.0)
                for a in range(5):
                    G.box(Fm @ CF(0, 1.1, 0) @ ANG(0, a * 1.25, 0.7) @ CF(0, 0.3, 0), (0.25, 0.7, 0.1),
                          (220, 240, 255), "glowsoft", 0.04)
        elif theme == "ember":
            for i in range(5):  # fire-blooms
                Fm = M @ CF(-5.5 + i * 2.8, 0, -1.6 - r.uniform(0, 1))
                G.box(Fm @ CF(0, 0.5, 0), (0.15, 1.0, 0.15), (60, 44, 40), "wood", 0.0)
                for a in range(5):
                    G.box(Fm @ CF(0, 1.1, 0) @ ANG(0, a * 1.25, 0.7) @ CF(0, 0.3, 0), (0.3, 0.7, 0.1),
                          (255, 120 + a * 20, 50), "glow", 0.04)
            for i in range(6):
                G.box(M @ CF(r.uniform(-6, 6), 0.05, -r.uniform(1.5, 7)), (r.uniform(0.8, 2), 0.08, 1.0), (70, 64, 62),
                      "stone", 0.0)
        else:
            for i in range(4):  # ferns and a mushroom ring
                Fm = M @ CF(-5.5 + i * 3.4, 0, -1.6 - r.uniform(0, 0.6))
                for a in range(6):
                    G.box(Fm @ ANG(0, a * 1.05, 0.9) @ CF(0, 0.7, 0), (0.35, 1.5, 0.12),
                          self.LEAF if a % 2 else self.LEAF3, "satin", 0.04)
            for i in range(5):
                x = r.uniform(-5, 5)
                G.box(M @ CF(x, 0.2, -4), (0.14, 0.4, 0.14), (240, 236, 220), "satin", 0.0)
                G.box(M @ CF(x, 0.45, -4), (0.5, 0.18, 0.5), (220, 110, 90), "satin", 0.06)


# ================================================================================================ scene, cameras, render
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
    sc.view_settings.view_transform = "AgX"
    try:
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    sc.render.resolution_percentage = RES
    w = bpy.data.worlds.new("DungeonAmbient")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = lin((92, 82, 118)) + (1.0,)  # DungeonController's violet ambient, a bit lifted
    bg.inputs["Strength"].default_value = 1.0


def fill(ox, oz, sx=60, sz=72, energy=9000, oy=0.0):
    """a soft overhead fill for the cut-away room (stands in for the game's Ambient + OutdoorAmbient)"""
    L = bpy.data.lights.new("Fill", "AREA")
    L.shape, L.size = "RECTANGLE", sx
    L.size_y = sz
    L.energy, L.color = energy, (0.98, 0.93, 0.92)
    try:
        L.use_shadow = False
    except Exception:
        pass
    ob = bpy.data.objects.new("Fill", L)
    ob.location = (ox, -oz, oy + 40)
    bpy.context.scene.collection.objects.link(ob)


def shoot(path, cam_R, tgt_R, lens, size):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = size
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cd.clip_end = 600
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    c, t = P @ Vector(cam_R), P @ Vector(tgt_R)
    cam.location = c
    cam.rotation_euler = (t - c).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[pitch]", path, flush=True)


STYLES = {"today": Today, "a": StyleA, "b": StyleB, "c": StyleC}
SP = 150.0  # rooms side by side along X (Roblox)
XS = {"today": -1.5 * SP, "a": -0.5 * SP, "b": 0.5 * SP, "c": 1.5 * SP}
THEME_Z = 260.0
THEME_Y = -300.0  # far below the rooms: no camera sees another set
MAIN = ((-17.0, 26.0, -16.0), (5.0, 2.0, 20.0), 24, (1280, 800))
CLOSE_OPT = ((13.0, 7.5, -10.0), (29.0, 7.0, 3.0), 30, (640, 420))
CLOSE_TODAY = ((13.0, 7.5, 2.0), (29.0, 7.5, -10.0), 30, (640, 420))
THEMES_CAM = ((0.0, 9.5, -40.0), (0.0, 7.0, 0.0), 30, (640, 420))


def build_all():
    stage()
    stats = {}
    for key in ONLY:
        S = STYLES[key]()
        G = Geo()
        ox = XS[key]
        O = CF(ox, 0, 0)
        S.room(G, O)
        # the player for scale: on the carpet before the statues, turned toward the main camera
        player(G, O @ CF(-2.6, 0, 8.0) @ ANG(0, 0.55, 0))
        # and by the right wall for the close-up
        if key == "today":
            player(G, O @ CF(26.0, 0, -15.0) @ ANG(0, -2.2, 0))
        else:
            player(G, O @ CF(24.5, 0, 8.0) @ ANG(0, -1.1, 0))
        room_tris = G.tris()
        # the theme row: one wall module per floor theme
        T = CF(ox, THEME_Y, THEME_Z)
        for i, (theme, label, accent) in enumerate(THEMES):
            Mseg = T @ CF(15.5 - i * 15.5, 0, 0)  # +X is screen-left for a camera looking +Z
            S.theme_segment(G, Mseg, theme, accent)
        player(G, T @ CF(10.5, 0, -3.0) @ ANG(0, -0.3, 0))
        G.build(key)
        fill(ox, 0)
        fill(ox, THEME_Z - 4, 50, 16, 9000 * 800 / 4320, THEME_Y)
        stats[key] = room_tris
        print("[pitch] %s room tris (mock-up, whole room) = %d" % (key, room_tris), flush=True)
    return stats


def render_all():
    paths = {}
    for key in ONLY:
        ox = XS[key]
        out = {}
        if "main" in SHOTS:
            c, t, lens, size = MAIN
            p = os.path.join(OUT, "_%s_main.png" % key)
            shoot(p, (c[0] + ox, c[1], c[2]), (t[0] + ox, t[1], t[2]), lens, size)
            out["main"] = p
        if "close" in SHOTS:
            c, t, lens, size = CLOSE_TODAY if key == "today" else CLOSE_OPT
            p = os.path.join(OUT, "_%s_close.png" % key)
            shoot(p, (c[0] + ox, c[1], c[2]), (t[0] + ox, t[1], t[2]), lens, size)
            out["close"] = p
        if "themes" in SHOTS:
            c, t, lens, size = THEMES_CAM
            p = os.path.join(OUT, "_%s_themes.png" % key)
            shoot(p, (c[0] + ox, c[1] + THEME_Y, c[2] + THEME_Z), (t[0] + ox, t[1] + THEME_Y, t[2] + THEME_Z), lens, size)
            out["themes"] = p
        paths[key] = out
    return paths


TITLES = {
    "today": "TODAY  (rebuilt from DungeonBuilder's numbers)",
    "a": "A  The Cloudkeep Undercroft",
    "b": "B  The Weatherworks",
    "c": "C  The Root Conservatory",
}


def composite(paths):
    from PIL import Image, ImageDraw, ImageFont

    def font(sz):
        for f in ("C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf", "arial.ttf"):
            try:
                return ImageFont.truetype(f, sz)
            except Exception:
                pass
        return ImageFont.load_default()

    def label(dr, xy, text, sz=22):
        f = font(sz)
        x, y = xy
        bb = dr.textbbox((x, y), text, font=f)
        dr.rectangle((bb[0] - 8, bb[1] - 5, bb[2] + 8, bb[3] + 6), fill=(24, 22, 36))
        dr.text((x, y), text, font=f, fill=(250, 246, 236))

    for key, p in paths.items():
        if not all(k in p for k in ("main", "close", "themes")):
            continue
        main = Image.open(p["main"]).convert("RGB")
        W = main.width
        close = Image.open(p["close"]).convert("RGB").resize((W // 2, int(W / 2 * 420 / 640)))
        th = Image.open(p["themes"]).convert("RGB").resize((W // 2, int(W / 2 * 420 / 640)))
        sheet = Image.new("RGB", (W, main.height + close.height), (24, 22, 36))
        sheet.paste(main, (0, 0))
        sheet.paste(close, (0, main.height))
        sheet.paste(th, (W // 2, main.height))
        dr = ImageDraw.Draw(sheet)
        s = W / 1280.0
        label(dr, (int(16 * s), int(14 * s)), TITLES[key] + "  -  the boss room", int(26 * s))
        label(dr, (int(16 * s), main.height + int(12 * s)), "close-up: wall, torch, banner (player 5.3 studs)", int(18 * s))
        label(dr, (W // 2 + int(16 * s), main.height + int(12 * s)), "one wall module, three floors", int(18 * s))
        for i, (_, name, _) in enumerate(THEMES):
            f = font(int(16 * s))
            tw_ = dr.textbbox((0, 0), name, font=f)[2]
            label(dr, (W // 2 + int((i + 0.5) * W / 6) - tw_ // 2, sheet.height - int(34 * s)), name, int(16 * s))
        sheet.save(os.path.join(OUT, "today_render.png" if key == "today" else "option_%s.png" % key))
    have = [k for k in ("today", "a", "b", "c") if k in paths and "main" in paths[k]]
    if len(have) == 4:
        tiles = [Image.open(paths[k]["main"]).convert("RGB") for k in have]
        tw, th_ = tiles[0].width // 2, tiles[0].height // 2
        sheet = Image.new("RGB", (tw * 2, th_ * 2), (24, 22, 36))
        dr = ImageDraw.Draw(sheet)
        for i, (k, im) in enumerate(zip(have, tiles)):
            x, y = (i % 2) * tw, (i // 2) * th_
            sheet.paste(im.resize((tw, th_)), (x, y))
        for i, k in enumerate(have):
            x, y = (i % 2) * tw, (i // 2) * th_
            label(dr, (x + 12, y + 10), TITLES[k].split("  (")[0], 20)
        sheet.save(os.path.join(OUT, "lineup.png"))


if __name__ == "__main__":
    stats = build_all()
    paths = render_all()
    if COMPOSITE:
        composite(paths)
    print("[pitch] stats", stats, flush=True)
