"""The shop's roulette machine, card A "Gumball Globe" (shop-area 2026-11-09, docs/superpowers/specs/2026-11-07-lobby-shop-
design.md 16.17.1; the owner's pick, ported from the pitch's scripts/machines.py design_a on scripts/mkit.py MSculpt).

  * "lobby_roulette_globe"  prop_roulette_globe: ONE mesh for the four roulettes (Cloud / Storm / Sky / Celestial).  A
                            cast-iron claw-foot gumball machine as the cloud shop's tinkers would have made it: an iron
                            plinth with a pale lip, four ball-and-claw feet and a little cloud bank (six puffs) tucked round
                            its sides and back; the cabinet in the roulette colour (Primary) with a gold step, a lower and
                            an upper gold trim that both fade into the cabinet through a pastel row (BodyLight = the
                            roulette's own pale colour: GoldLight / Gold / BodyLight on top, BodyLight / Gold below),
                            BodyDark fluting down the rounded corners; marquee bulbs on the upper trim (front, sides,
                            back); the navy lit sign on the front with a Neon rim (Glow) and ONE four-point star emblem
                            (Neon, Secondary = the roulette's top rarity colour, 2 studs across) with two twinkles; a
                            brass crank with a rubber knob (the viewer's right) and a gold coin plate with its slot and a
                            return button (the viewer's left); the chute at the bottom front: a dark mouth in a gold
                            frame with its flap, a gold tray on the step; cream side panels in gold frames with three
                            painted egg silhouettes each (BodyLight with a BodyDark band); an access door on the back with
                            hinges and a lock.  On top a gold neck, collar and floor, a gold seat ring holding a clear
                            glass globe (0.5-stud cells as the old dome, Transparency 0.70), a gold lid and the winged-
                            cloud finial (a cloud on a gold collar, two gold wings swept back and up, the Glow ball on
                            top).  Nothing above y 14.4; the 9 x 7 footprint (the puffs and the feet stay inside it: the
                            shop's egg row comes close to the Cloud machine's side).
                            The eggs are NOT in the mesh: twelve attachments Egg1..Egg12 (pivot = the egg's bottom
                            centre in machine studs, rot = its turn) carry the real egg_<rarity> keys the game places
                            (LobbyMachineBuilder.GlobeEggs, ML_Scale Meta.eggScale 0.42, the chase egg Egg1 at
                            Meta.chaseScale 0.44): a ring of seven on the floor leaning in, a second layer of four, the
                            chase egg on top at the front.
                            Parts (8): Body (Primary), BodyLight (lighten Primary 0.3), BodyDark (darken Primary 0.3),
                            Glow (Neon, lighten Primary 0.25), Bulb (Neon), Emblem (Neon, Secondary), Glass, Fixed (every
                            constant colour baked).  The tinted keys keep their dark shade (a vertex colour) but no light
                            shade (a light shade is a part of its own: it would make a ninth).
                            0.25-stud cells (K 4); pivot = ground centre, front -Z (the customer).

Deterministic (no RNG).  Python + numpy only (no bpy).
"""
import math

import numpy as np

from props import prop
from props.lobby import Sculpt, finish
from props.lobby_shop import star4

K = 4.0                      # 0.25-stud cells for the machine
GK = 2.0                     # 0.5-stud cells for the glass (a sphere of fine glass cells costs thousands of tris)
EXTENT = 8.0                 # grid half extent round ORIGIN (studs)
ORIGIN = (0.0, 7.0, 0.0)     # the grids' centre (the pivot stays the model origin)
EGG_SCALE = 0.42             # 2.2 x 3 x 2.2 egg -> 0.92 x 1.26 x 0.92 studs
CHASE_SCALE = 0.44
FLOOR_Y = 7.5                # the globe floor's top, flush with the collar's lip (the whole pile shows over the gold)
GLOBE_C = (0.0, 9.75, 0.0)   # the glass sphere: centre, outer and inner radius, cut below / above
GLOBE_R = (3.3, 2.8)
GLOBE_Y = (7.3, 12.3)
GLASS_RGB = (224, 240, 255)
GLASS_T = 0.70

PAL = {
    "Iron": (64, 70, 92), "IronLight": (96, 104, 130), "IronDark": (44, 48, 66),
    "Gold": (244, 198, 84), "GoldDark": (206, 154, 62), "GoldLight": (255, 226, 140),
    "Brass": (222, 172, 82), "BrassDark": (170, 120, 52),
    "Cream": (246, 234, 210), "CreamShade": (226, 212, 186), "Navy": (34, 42, 76), "Ink": (22, 26, 48),
    "Cloud": (236, 241, 250), "CloudShade": (200, 214, 238), "Rubber": (52, 52, 64),
}


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def spot_rot(yaw, tilt_x=0.0, tilt_z=0.0):
    return rot_y(yaw) @ rot_x(tilt_x) @ rot_z(tilt_z)


class MachineSculpt(Sculpt):
    """lobby.Sculpt with this module's palette and cell-exact stud masks (cell i covers origin + [i, i + 1] * vs; the
    mesh offset is origin + vs / 2), the pitch's MSculpt: box / rrect / rrect_front / cyl / ring / cyl_z / ell /
    shell / capsule / tube / front2d.  Coordinates = machine studs: +Y up, front -Z, +X = the viewer's LEFT."""

    def __init__(self, kit, K, extent, origin=(0.0, 0.0, 0.0), name="grid"):
        Sculpt.__init__(self, kit, K, extent, name=name)
        self.vs = 1.0 / K
        self.origin = np.asarray(origin, float)
        self.no_light = set()  # tinted keys without a light shade (a light shade is a MeshPart of its own)
        h = self.g.half
        c = (np.arange(2 * h + 1) - h + 0.5) * self.vs
        self.X = (self.origin[0] + c)[:, None, None]
        self.Y = (self.origin[1] + c)[None, :, None]
        self.Z = (self.origin[2] + c)[None, None, :]

    def recipes(self):
        rec = {}
        for k in self.g.keys:
            if k is None:
                continue
            if k in self.tint:
                rec[k] = self.tint[k]
            elif k in self.neon:
                rec[k] = self.neon[k]
            elif k in self.glass:
                rec[k] = self.glass[k][0]
            else:
                rec[k] = ["rgb"] + list(PAL[k])
        return rec

    def mesh_at(self, m, group, used):
        """Sculpt.mesh with the shade options of `no_light` (and the grid's cell offset)"""
        self.detach_glass()
        rec = self.recipes()
        mats = {}
        for k in self.neon:
            mats[k] = ("Neon", 0.0)
        for k, (r, t) in self.glass.items():
            mats[k] = ("Glass", t)
        fixed = [k for k in rec if k not in self.tint and k not in self.neon and k not in self.glass]
        g = self.g
        for k in fixed:  # baked keys take the "lb" prefix (tools/mesh_names.py: no game-referenced name in Fixed)
            i = g.ids.pop(k)
            g.keys[i] = "lb" + k
            g.ids["lb" + k] = i
            rec["lb" + k] = rec.pop(k)
        fixed = ["lb" + k for k in fixed]
        flat = set(self.flat) | set(self.neon) | set(self.glass)
        opts = {k: {"light": False} for k in self.no_light}
        return self.kit.mesh(m, g, recipes=rec, group=group, vs=self.vs, flat=flat, materials=mats, fixed_keys=fixed,
                             offset=tuple(float(v) for v in self.origin + self.vs / 2), shade_opts=opts,
                             used=used if used is not None else {})

    # ---------------------------------------------------------------- writing
    def put(self, key, mask, only=None, empty=False):
        L = self.g.L
        m = np.broadcast_to(mask, L.shape).copy()
        if only is not None:
            only = [only] if isinstance(only, str) else list(only)
            m &= np.isin(L, [self.g.ids[k] for k in only if k in self.g.ids] or [-1])
        if empty:
            m &= L == 0
        L[m] = self.g.kid(key)

    def cut(self, mask):
        self.g.L[np.broadcast_to(mask, self.g.L.shape)] = 0

    def has(self, key):
        """the cells holding `key` now (a mask)"""
        i = self.g.ids.get(key)
        return (self.g.L == i) if i is not None else np.zeros(self.g.L.shape, bool)

    # ---------------------------------------------------------------- stud-space masks
    def box(self, x0, x1, y0, y1, z0, z1):
        X, Y, Z = self.X, self.Y, self.Z
        return (X > x0) & (X < x1) & (Y > y0) & (Y < y1) & (Z > z0) & (Z < z1)

    def rrect(self, cx, cz, hx, hz, r, y0, y1):
        """a box with rounded vertical edges (corner radius r)"""
        dx = np.maximum(np.abs(self.X - cx) - (hx - r), 0)
        dz = np.maximum(np.abs(self.Z - cz) - (hz - r), 0)
        return (dx * dx + dz * dz <= r * r) & (self.Y > y0) & (self.Y < y1)

    def rrect_front(self, cx, cy, hx, hy, r, z0, z1):
        """a plate facing the front (an XY rounded rect) from z0 to z1"""
        dx = np.maximum(np.abs(self.X - cx) - (hx - r), 0)
        dy = np.maximum(np.abs(self.Y - cy) - (hy - r), 0)
        return (dx * dx + dy * dy <= r * r) & (self.Z > z0) & (self.Z < z1)

    def cyl(self, cx, cz, r, y0, y1):
        return ((self.X - cx) ** 2 + (self.Z - cz) ** 2 <= r * r) & (self.Y > y0) & (self.Y < y1)

    def ring(self, cx, cz, r0, r1, y0, y1):
        d = (self.X - cx) ** 2 + (self.Z - cz) ** 2
        return (d <= r1 * r1) & (d >= r0 * r0) & (self.Y > y0) & (self.Y < y1)

    def cyl_z(self, cx, cy, r, z0, z1):
        """a cylinder along Z (a disc facing the front)"""
        return ((self.X - cx) ** 2 + (self.Y - cy) ** 2 <= r * r) & (self.Z > z0) & (self.Z < z1)

    def ell(self, cx, cy, cz, rx, ry=None, rz=None):
        ry = rx if ry is None else ry
        rz = rx if rz is None else rz
        return ((self.X - cx) / rx) ** 2 + ((self.Y - cy) / ry) ** 2 + ((self.Z - cz) / rz) ** 2 <= 1.0

    def shell(self, cx, cy, cz, r_out, r_in):
        d = (self.X - cx) ** 2 + (self.Y - cy) ** 2 + (self.Z - cz) ** 2
        return (d <= r_out * r_out) & (d >= r_in * r_in)

    def capsule(self, a, b, r):
        a, b = np.asarray(a, float), np.asarray(b, float)
        d = b - a
        L2 = float(d @ d) or 1e-9
        t = np.clip(((self.X - a[0]) * d[0] + (self.Y - a[1]) * d[1] + (self.Z - a[2]) * d[2]) / L2, 0, 1)
        return (self.X - a[0] - t * d[0]) ** 2 + (self.Y - a[1] - t * d[1]) ** 2 + (self.Z - a[2] - t * d[2]) ** 2 <= r * r

    def front2d(self, fn, z0, z1):
        """extrude a picture-plane shape fn(u, v) (u = the viewer's right = -X, v = up, studs) between z0 and z1"""
        return fn(-self.X, self.Y) & (self.Z > z0) & (self.Z < z1)


def star4_mask(cu, cv, s, sharp=0.55, heart=0.1):
    """the emblem: a four-point star (half size s) as a picture-plane shape fn(u, v); the egg paint's star4 with
    pointier arms (its exponent 0.65 read as a blunt cross at 0.25-stud cells) and a round heart"""
    def fn(U, V):
        a, b = np.abs(U - cu) / s, np.abs(V - cv) / s
        return (a ** sharp + b ** sharp <= 1.0) | (a * a + b * b <= heart) | star4(U, V, cu, cv, s * 0.55)
    return fn


# ---------------------------------------------------------------------------------------------- the egg spots
# (pos = the egg's bottom centre in machine studs, yaw, tilt_x, tilt_z, scale): index 0 = the chase spot (the top rarity,
# whole in the front view), then the floor ring of seven (leaning in), then the second layer of four.  Tuned with
# blender/pitches/shop_area_globe.py --check (every egg inside the glass and off its cells, off the seat, on the floor or
# resting on the eggs below, none sunk into another by more than 0.03, the chase egg's face 100 % clear from the front,
# about half of the globe's lower half covered from the front):
#   the floor ring = spec 16.17.1 (a_k = k 2 pi / 7 + 0.35 at r 1.3, yaw a + 0.4, leaning in 0.2) on the floor, raised
#   from the spec's 6.95 to 7.5 = the collar's lip (at 6.95 the collar hid the ring's lower half from every angle);
#   the second layer at a_k = k pi / 2 + 0.5, r 0.85, each with its own small lean, dropped until it rests on the ring
#   (the spec's r 0.75 / lean 0.35 sank 0.15 - 0.26 stud into its neighbours);
#   the chase egg at (-0.2, -1.05) leaning to the front, dropped onto the pile: it crowns it at the front.
EGG_SPOTS = [
    ((-0.2, 9.36, -1.05), -0.3, -0.3, 0.0, CHASE_SCALE),
    ((0.446, FLOOR_Y, -1.221), 0.75, 0.188, -0.069, EGG_SCALE),
    ((1.233, FLOOR_Y, -0.413), 1.648, 0.064, -0.19, EGG_SCALE),
    ((1.091, FLOOR_Y, 0.706), 2.545, -0.109, -0.168, EGG_SCALE),
    ((0.128, FLOOR_Y, 1.294), 3.443, -0.199, -0.02, EGG_SCALE),
    ((-0.931, FLOOR_Y, 0.907), 4.34, -0.14, 0.143, EGG_SCALE),
    ((-1.29, FLOOR_Y, -0.163), 5.238, 0.025, 0.198, EGG_SCALE),
    ((-0.677, FLOOR_Y, -1.11), 6.136, 0.171, 0.104, EGG_SCALE),
    ((0.408, 8.62, -0.746), 1.7, 0.12, -0.1, EGG_SCALE),
    ((0.746, 8.66, 0.408), 3.271, -0.1, -0.14, EGG_SCALE),
    ((-0.408, 8.67, 0.746), 4.842, 0.14, 0.08, EGG_SCALE),
    ((-0.746, 8.49, -0.408), 6.412, -0.08, 0.16, EGG_SCALE),
]


def egg_attachments():
    """Egg1..Egg12 -> {pos, rot} (rounded: stable manifests)"""
    att = {}
    for i, (pos, yaw, tx, tz, _s) in enumerate(EGG_SPOTS):
        R = spot_rot(yaw, tx, tz)
        att["Egg%d" % (i + 1)] = {"pos": [round(float(v), 4) for v in pos],
                                  "rot": [[round(float(v), 6) for v in row] for row in R]}
    return att


# ---------------------------------------------------------------------------------------------- the machine
def _tints(S):
    S.tint["Body"] = ["Primary"]
    S.tint["BodyLight"] = ["lighten", ["Primary"], 0.3]
    S.tint["BodyDark"] = ["darken", ["Primary"], 0.3]
    S.neon["Glow"] = ["lighten", ["Primary"], 0.25]
    S.neon["Bulb"] = ["rgb", 255, 222, 150]
    S.neon["Emblem"] = ["Secondary"]
    S.flat |= {"Glow", "Bulb", "Emblem"}
    S.no_light |= {"Body", "BodyLight", "BodyDark"}


def _plinth(S):
    """the cast-iron plinth (8.5 x 6.5) on four ball-and-claw feet, a pale lip, a moulding line, the cloud bank"""
    X, Y, Z = S.X, S.Y, S.Z
    S.put("Iron", S.rrect(0, 0, 4.25, 3.25, 1.1, 0.0, 0.9))
    S.put("IronLight", S.rrect(0, 0, 4.25, 3.25, 1.1, 0.65, 0.9) & ~S.rrect(0, 0, 4.0, 3.0, 0.9, 0.0, 1.0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = sx * 3.75, sz * 2.75
            S.put("IronDark", S.ell(cx, 0.3, cz, 0.62, 0.42, 0.62) & (Y > 0.0))                 # the ball
            for a in (0.0, 1.05, -1.05):                                                      # three claws over it
                d = math.atan2(sz, sx) + a * 0.8
                tip = (cx + 0.62 * math.cos(d), 0.12, cz + 0.62 * math.sin(d))
                S.put("Iron", S.capsule((cx + 0.2 * math.cos(d), 0.62, cz + 0.2 * math.sin(d)), tip, 0.14) & (Y > 0.0))
    # the cloud bank: six puffs round the sides and the back (the front stays clear for the chute and the prompt),
    # lapping over the plinth's lip; the shade on their undersides
    puffs = ((3.75, 0.8, -1.0, 0.75, 0.62, 0.95), (3.75, 0.85, 1.15, 0.75, 0.66, 0.95),
             (-3.75, 0.8, -1.0, 0.75, 0.62, 0.95), (-3.75, 0.85, 1.15, 0.75, 0.66, 0.95),
             (1.5, 0.8, 2.85, 0.95, 0.62, 0.65), (-1.5, 0.85, 2.85, 0.95, 0.66, 0.65))
    for cx, cy, cz, rx, ry, rz in puffs:
        S.put("Cloud", S.ell(cx, cy, cz, rx, ry, rz) & (Y > 0.0))
        S.put("CloudShade", S.ell(cx, cy, cz, rx, ry, rz) & (Y < cy - 0.3), only="Cloud")


def _cabinet(S):
    X, Y, Z = S.X, S.Y, S.Z
    S.put("GoldDark", S.rrect(0, 0, 3.9, 2.9, 0.9, 0.9, 1.25))                 # the step
    S.put("Body", S.rrect(0, 0, 3.6, 2.6, 0.9, 1.25, 5.75))
    # BodyDark fluting down the four rounded corners (flush paint on the shell, 45 degrees round each corner)
    shell = S.has("Body") & ~S.rrect(0, 0, 3.35, 2.35, 0.65, 0.0, 9.0)
    corner = (np.abs(X) > 2.7) & (np.abs(Z) > 1.7)
    S.put("BodyDark", shell & corner & (np.abs((np.abs(X) - 2.7) - (np.abs(Z) - 1.7)) < 0.2) & (Y > 1.75) & (Y < 5.0))
    # the trims fade into the cabinet through the roulette's pale colour: below BodyLight / Gold, on top
    # BodyLight / Gold / GoldLight (rows of 0.25, full slabs one cell proud of the body)
    S.put("Gold", S.rrect(0, 0, 3.8, 2.8, 0.9, 1.25, 1.5))
    S.put("BodyLight", S.rrect(0, 0, 3.8, 2.8, 0.9, 1.5, 1.75))
    S.put("BodyLight", S.rrect(0, 0, 3.8, 2.8, 0.9, 5.0, 5.25))
    S.put("Gold", S.rrect(0, 0, 3.8, 2.8, 0.9, 5.25, 5.5))
    S.put("GoldLight", S.rrect(0, 0, 3.8, 2.8, 0.9, 5.5, 5.75))


def _front(S):
    """the lit sign with the star, the coin plate (viewer's left), the crank (viewer's right), the chute and tray"""
    X, Y, Z = S.X, S.Y, S.Z
    navy = S.rrect_front(0, 3.625, 2.25, 1.125, 0.3, -2.75, -2.25)              # 4.5 x 2.25 (y 2.5 .. 4.75)
    S.put("Navy", navy)
    rim = S.rrect_front(0, 3.625, 2.5, 1.375, 0.4, -2.75, -2.5) & ~navy        # the Neon rim, one cell
    S.put("Glow", rim)
    # the star centred on a cell (x 0.125, y 3.625): on a cell boundary its thin vertical arms lost their tips
    S.put("Emblem", S.front2d(star4_mask(-0.125, 3.625, 1.0), -3.0, -2.75) & S.rrect_front(0, 3.625, 2.2, 1.1, 0.3, -4, -2))
    for u, v in ((-1.625, 4.375), (1.625, 2.875)):                              # two twinkles: plus marks on cells
        S.put("Emblem", S.front2d(lambda U, V, u=u, v=v: ((np.abs(U - u) < 0.13) & (np.abs(V - v) < 0.38))
                                  | ((np.abs(U - u) < 0.38) & (np.abs(V - v) < 0.13)), -3.0, -2.75))
    # the coin plate: a gold plate with a slot and a return button
    plate = S.rrect_front(3.05, 4.0, 0.45, 0.65, 0.15, -3.0, -2.55)
    S.put("Gold", plate)
    S.put("GoldDark", S.rrect_front(3.05, 4.0, 0.45, 0.65, 0.15, -3.0, -2.55) & ~S.rrect_front(3.05, 4.0, 0.35, 0.55, 0.1, -4, -2))
    S.put("Ink", S.box(2.875, 3.125, 4.25, 4.5, -3.05, -2.75))
    S.put("GoldLight", S.box(2.875, 3.125, 3.5, 3.75, -3.05, -2.75))
    # the crank: a brass disc with a dark rim, the arm up to the rubber knob (inside the footprint: z >= -3.5)
    S.put("Brass", S.cyl_z(-3.05, 3.75, 0.55, -2.95, -2.55))
    S.put("BrassDark", S.cyl_z(-3.05, 3.75, 0.6, -2.75, -2.55) & ~S.cyl_z(-3.05, 3.75, 0.45, -4, -2))
    S.put("BrassDark", S.cyl_z(-3.05, 3.75, 0.15, -3.05, -2.9))
    S.put("Brass", S.box(-3.175, -2.925, 3.75, 4.5, -3.2, -2.95))
    S.put("Rubber", S.cyl_z(-3.05, 4.375, 0.2, -3.5, -3.0))
    # the chute: a dark mouth in a gold frame with its flap, the tray on the step
    S.put("GoldDark", S.box(-1.25, 1.25, 1.0, 2.25, -3.0, -2.5))
    S.put("Ink", S.box(-1.0, 1.0, 1.25, 2.0, -3.1, -2.0))
    S.put("Gold", S.box(-0.875, 0.875, 1.75, 2.0, -3.0, -2.75))
    S.put("Gold", S.rrect(0, -3.0, 1.25, 0.45, 0.2, 0.9, 1.25))
    S.put("GoldDark", S.rrect(0, -3.0, 1.0, 0.25, 0.1, 1.0, 1.3))
    del X, Y, Z


def _sides_back(S):
    X, Y, Z = S.X, S.Y, S.Z
    for sx in (-1, 1):
        side = (np.abs(X - sx * 3.6) < 0.3) & (np.abs(Z) < 1.6) & (Y > 2.25) & (Y < 4.75) & (np.abs(X) < 3.65)
        frame = (np.abs(X - sx * 3.6) < 0.3) & (np.abs(Z) < 1.85) & (Y > 2.0) & (Y < 5.0) & ~side & (np.abs(X) < 3.65)
        S.put("Cream", side)
        S.put("Gold", frame)
        for z in (-1.0, 0.0, 1.0):    # painted egg silhouettes in the cabinet colour: wider below the middle, a dark band
            t = np.clip((Y - 3.5) / 0.6, -1.0, 1.0)  # (half width <= 0.36: a clear cell of cream between neighbours)
            half = 0.34 * np.sqrt(np.clip(1.0 - t * t, 0.0, 1.0)) * (1.0 - 0.18 * t)
            egg = side & (np.abs(Y - 3.5) < 0.6) & (np.abs(Z - z) <= half)
            S.put("Body", egg)
            S.put("BodyDark", egg & (np.abs(Y - 3.375) < 0.13))
    # the access door on the back: a BodyDark outline, gold hinges and a lock
    back = (Z > 2.25) & (Z < 2.55)
    door = back & (np.abs(X) < 1.6) & (Y > 1.75) & (Y < 4.75)
    inner = back & (np.abs(X) < 1.35) & (Y > 2.0) & (Y < 4.5)
    S.put("BodyDark", (door & ~inner) & S.has("Body"))
    S.put("Gold", S.box(1.35, 1.85, 2.25, 2.75, 2.25, 2.75) | S.box(1.35, 1.85, 3.75, 4.25, 2.25, 2.75))
    S.put("GoldDark", S.box(-1.25, -0.75, 3.0, 3.5, 2.25, 2.75))


def _bulbs(S):
    for x in (-3.0, -1.5, 0.0, 1.5, 3.0):
        S.put("Bulb", S.ell(x, 5.375, -2.85, 0.3, 0.3, 0.22))
    for sx in (-1, 1):
        for z in (-1.4, 0.0, 1.4):
            S.put("Bulb", S.ell(sx * 3.85, 5.375, z, 0.22, 0.3, 0.3))


def _neck_globe(S, G):
    S.put("Gold", S.cyl(0, 0, 2.3, 5.75, 6.5))                                    # the neck
    S.put("GoldDark", S.ring(0, 0, 1.95, 2.65, 6.5, 7.5))                         # the collar the glass sits on
    S.put("GoldLight", S.ring(0, 0, 1.95, 2.65, 7.25, 7.5))                       # ...its pale lip
    S.put("Gold", S.cyl(0, 0, 1.95, 6.5, FLOOR_Y))                                # the floor, flush with the lip
    # the glass globe on its own 0.5-stud grid, clear of the seat and the lid
    G.glass["Glass"] = (["rgb"] + list(GLASS_RGB), GLASS_T)
    G.flat |= {"Glass"}
    cx, cy, cz = GLOBE_C
    G.put("Glass", G.shell(cx, cy, cz, GLOBE_R[0], GLOBE_R[1]) & (G.Y > GLOBE_Y[0]) & (G.Y < GLOBE_Y[1]))
    # the lid over the glass's top opening
    S.put("GoldDark", S.cyl(0, 0, 2.2, 12.5, 12.75))


def _finial(S):
    """the winged-cloud finial: a gold collar, a cloud, two gold wings swept back and up, the Glow ball"""
    S.put("Gold", S.cyl(0, 0, 0.5, 12.75, 13.0))
    S.put("GoldLight", S.cyl(0, 0, 0.75, 12.75, 13.0) & ~S.cyl(0, 0, 0.5, 0, 99))
    cloud = S.ell(0, 13.4, 0, 0.8, 0.55, 0.7) | S.ell(0.62, 13.25, 0.05, 0.5, 0.4, 0.5) | S.ell(-0.62, 13.25, 0.05, 0.5, 0.4, 0.5)
    S.put("Cloud", cloud)
    S.put("CloudShade", cloud & (S.Y < 13.1), only="Cloud")
    for sx in (-1, 1):
        _wing(S, sx)
    S.put("Glow", S.ell(0, 13.95, 0, 0.45, 0.45, 0.45))


# the wing plate: its root at the cloud's side, swept back (degrees about Y), three feathers (length, degrees up from the
# plate's horizontal), the feather half width at its root, the plate's half thickness
WING = {"Root": (0.7, 13.4, 0.1), "Sweep": 25.0, "Feathers": ((1.8, 24.0), (1.55, -4.0), (1.2, -32.0)),
        "Width": 0.25, "Half": 0.16}


def _wing(S, sx):
    """one gold wing: three feathers fanned from the root in a plate one to two cells thick, the plate facing the
    customer and swept back (so the front sees the fan and the side sees it at an angle), the top feather pale"""
    rx, ry, rz = WING["Root"]
    root = np.array([sx * rx, ry, rz])
    sw = math.radians(WING["Sweep"])
    out = np.array([sx * math.cos(sw), 0.0, math.sin(sw)])                       # outward, swept back
    up = np.array([0.0, 1.0, 0.0])
    normal = np.cross(out, up)
    normal /= np.linalg.norm(normal)
    dx, dy, dz = S.X - root[0], S.Y - root[1], S.Z - root[2]
    u0 = dx * out[0] + dy * out[1] + dz * out[2]                                 # along the plate's horizontal
    v0 = dy                                                                       # up
    w = dx * normal[0] + dy * normal[1] + dz * normal[2]
    thin = np.abs(w) <= WING["Half"]
    for i, (length, deg) in enumerate(WING["Feathers"]):
        a = math.radians(deg)
        cu, cv = math.cos(a), math.sin(a)
        fu = u0 * cu + v0 * cv                                                    # along the feather
        fv = -u0 * cv + v0 * cu                                                   # across it
        t = fu / length
        feather = thin & (t > 0.0) & (t < 1.0) & (np.abs(fv) <= WING["Width"] * np.sqrt(np.clip(1.0 - t, 0, 1)) * (0.75 + 0.6 * t))
        S.put("GoldLight" if i == 0 else "Gold", feather, empty=True)
        S.put("GoldDark", feather & (t > 0.72), only=("GoldLight", "Gold"))      # the darker feather tips


def design_globe(S, G):
    _plinth(S)
    _cabinet(S)
    _front(S)
    _sides_back(S)
    _bulbs(S)
    _neck_globe(S, G)
    _finial(S)


@prop("lobby_roulette_globe")
def lobby_roulette_globe(entry, kit):
    S = MachineSculpt(kit, K, EXTENT, origin=ORIGIN, name="Globe")
    G = MachineSculpt(kit, GK, EXTENT, origin=ORIGIN, name="GlobeGlass")
    _tints(S)
    design_globe(S, G)
    m = kit.model(entry["key"], "prop", vs=S.vs, K=K)
    S.mesh_at(m, "Machine", {})
    G.mesh_at(m, "Glass", {})
    finish(m, {"source": "LobbyBuilder buildMachine (spec 16.17.1)", "pivot": "ground centre, front -Z"},
           look={"Primary": [120, 190, 235], "Secondary": [176, 108, 232]})
    m.attachments = egg_attachments()
    m.meta["eggScale"] = EGG_SCALE
    m.meta["chaseScale"] = CHASE_SCALE
    return m
