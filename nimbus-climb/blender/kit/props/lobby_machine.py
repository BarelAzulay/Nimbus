"""The shop's roulette machine, card A "Gumball Globe" (shop-area 2026-11-09, docs/superpowers/specs/2026-11-07-lobby-shop-
design.md 16.17.1; the owner's pick, ported from the pitch's scripts/machines.py design_a on scripts/mkit.py MSculpt).

  * "lobby_roulette_globe"  prop_roulette_globe: ONE mesh for the four roulettes (Cloud / Storm / Sky / Celestial).  A
                            cast-iron claw-foot gumball machine as the cloud shop's tinkers would have made it: an iron
                            plinth with a pale lip, four ball-and-claw feet and a little cloud bank (six puffs) tucked round
                            its sides and back; the cabinet in the roulette colour (Primary) with a dark gold step, a lower
                            and an upper gold trim that both fade into the cabinet through a pastel row (BodyLight = the
                            roulette's own pale colour: GoldLight / GoldDark / BodyLight on top, BodyLight / GoldLight
                            over the step below: a dark gold line on every cabinet colour, Sky's orange included),
                            BodyDark fluting down the rounded corners; marquee bulbs on the upper trim (front, sides,
                            back); the navy lit sign on the front with a Neon rim (Glow) and ONE four-point sparkle star
                            emblem (Neon, Secondary = the roulette's top rarity colour, 2.75 x 2.25 studs, a diamond
                            heart tapering to one-cell tips) with two one-cell twinkles; a
                            brass crank with a rubber knob (the viewer's right) and a gold coin plate with its slot and a
                            return button (the viewer's left); the chute at the bottom front: a dark mouth in a gold
                            frame with its flap, a gold tray on the step; cream side panels in gold frames with three
                            ONE bigger painted egg each (shop-area polish, SIDE_EGG: BodyDark with a Cream band); an
                            access door on the back with hinges and a lock.  On top a gold neck, collar and floor with a
                            cloud bed (CUSHION) the eggs rest on, a gold seat ring holding a clear glass globe (0.5-stud
                            cells as the old dome, GLASS_RGB at Transparency 0.80), a gold lid and the sunburst finial
                            (SUN: a rising sun, the Bulb half disc in a GoldDark rim, five pointed Gold rays).  ONE
                            face-connected piece with the glass (shop_area_globe.py --check).  Nothing above y 14.25; the
                            9 x 7 footprint (the puffs and the feet stay inside it: the shop's egg row comes close to the
                            Cloud machine's side).
                            The eggs are NOT in the mesh: eighteen attachments Egg1..Egg18 (EGG_SPOTS; pivot = the egg's
                            bottom centre in machine studs, rot = its turn) where LobbyMachineBuilder.GlobeEggs places
                            the game's eggs (ML_Scale Meta.eggScale 0.5, the pile on the low-poly egg_<rarity>_pile keys; the
                            chase egg Egg1 at Meta.chaseScale 0.54 on the full egg_<rarity>, on top at the front): a
                            natural pile settled by shop_area_globe.py --settle.
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

K = 4.0                      # 0.25-stud cells for the machine
GK = 2.0                     # 0.5-stud cells for the glass (a sphere of fine glass cells costs thousands of tris)
EXTENT = 8.0                 # grid half extent round ORIGIN (studs)
ORIGIN = (0.0, 7.0, 0.0)     # the grids' centre (the pivot stays the model origin)
EGG_SCALE = 0.5              # 2.2 x 3 x 2.2 egg -> 1.1 x 1.5 x 1.1 studs (polish: was 0.42; 18 eggs fill the globe)
CHASE_SCALE = 0.54
FLOOR_Y = 7.5                # the globe floor's top, flush with the collar's lip (the whole pile shows over the gold)
GLOBE_C = (0.0, 9.75, 0.0)   # the glass sphere: centre, outer and inner radius, cut below / above
GLOBE_R = (3.3, 2.8)
GLOBE_Y = (7.3, 12.3)
GLASS_RGB = (212, 234, 255)  # polish 2026-11-09: a faint cool tint, clearer (was 224,240,255 at 0.70: read foggy grey)
GLASS_T = 0.80

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


def star4_mask(cu, cv, sh, sv, sharp=0.6, heart=0.45):
    """the emblem: a four-point sparkle star (half sizes sh across, sv up) as a picture-plane shape fn(u, v): concave
    arms (exponent `sharp`) round a diamond heart (|a| + |b| <= heart), so at 0.25-stud cells it steps 1 / 3 / 5 / 11
    cells from the tips to the middle.  Review round 1: the old round heart and star4 core drew arms a constant 1-2
    cells wide (a thick '+', a first-aid sign from the plaza)."""
    def fn(U, V):
        a, b = np.abs(U - cu) / sh, np.abs(V - cv) / sv
        return (a ** sharp + b ** sharp <= 1.0) | (a + b <= heart)
    return fn


# ---------------------------------------------------------------------------------------------- the egg spots
# (pos = the egg's bottom centre in machine studs, yaw, tilt_x, tilt_z, scale): index 0 = the chase spot (the top rarity,
# whole in the front view), then the pile.  Polish 2026-11-09 (the 12-egg heap read ~25 % full): poured by
# `blender/pitches/shop_area_globe.py --settle 17 --scale 0.5 --chase 0.54` (deterministic): each pile egg drops at the
# lowest free spot of a 0.2-stud xz grid until it touches the floor, the cloud bed, the glass (0.04 clear) or an egg, the
# chase egg last at the lowest front spot (z <= -0.8, |x| <= 1) whose face stays >= 90 % clear from the front.  --check:
# 18 eggs, the globe's inner disc 51 % eggs / 62 % eggs + cloud bed from the front, the chase egg 90 % clear.
EGG_SPOTS = [
    ((0.0, 9.758, -1.2), -0.3, -0.18, 0.0, CHASE_SCALE),
    ((0.0, 7.91, -1.6), 2.4, 0.008, 0.034, EGG_SCALE),
    ((-1.2, 7.978, -1.0), 4.8, 0.076, -0.058, EGG_SCALE),
    ((1.2, 7.993, -1.0), 0.917, -0.015, 0.011, EGG_SCALE),
    ((1.8, 8.199, 0.0), 3.317, 0.053, 0.079, EGG_SCALE),
    ((-1.8, 8.375, 0.0), 5.717, -0.038, -0.012, EGG_SCALE),
    ((1.6, 8.598, 1.0), 1.833, 0.03, 0.056, EGG_SCALE),
    ((-1.6, 8.665, 1.0), 4.233, -0.061, -0.036, EGG_SCALE),
    ((-0.4, 8.784, -0.6), 0.35, 0.007, 0.033, EGG_SCALE),
    ((-0.8, 8.78, -1.8), 2.75, 0.075, -0.059, EGG_SCALE),
    ((0.8, 8.905, -1.8), 5.15, -0.016, 0.01, EGG_SCALE),
    ((0.8, 8.951, 1.8), 1.267, 0.052, 0.078, EGG_SCALE),
    ((-0.8, 9.021, 1.8), 3.667, -0.039, -0.013, EGG_SCALE),
    ((1.0, 9.019, -0.2), 6.067, 0.029, 0.055, EGG_SCALE),
    ((-0.6, 9.288, 0.6), 2.184, -0.062, -0.036, EGG_SCALE),
    ((-1.8, 9.394, -0.8), 4.584, 0.006, 0.032, EGG_SCALE),
    ((0.4, 9.29, 0.8), 0.7, 0.075, -0.059, EGG_SCALE),
    ((1.8, 9.461, -0.8), 3.1, -0.017, 0.009, EGG_SCALE),
]


def egg_attachments():
    """Egg1..Egg18 -> {pos, rot} (rounded: stable manifests)"""
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
    # the trims fade into the cabinet through the roulette's pale colour: below BodyLight / GoldLight over the dark
    # step, on top BodyLight / GoldDark / GoldLight (rows of 0.25, full slabs one cell proud of the body).  Review round
    # 1: the trims' Gold rows (244,198,84) sat within ~20 RGB of the Sky machine's cabinet (240,180,90) and its pale row
    # beside GoldLight, so Sky read as one orange-cream block; a GoldDark row in each gold band (the step under the
    # lower trim, the middle of the upper) now draws a dark line between trim and cabinet on every Primary, recoloured
    # rows only (no new boundary, no tris)
    S.put("GoldLight", S.rrect(0, 0, 3.8, 2.8, 0.9, 1.25, 1.5))
    S.put("BodyLight", S.rrect(0, 0, 3.8, 2.8, 0.9, 1.5, 1.75))
    S.put("BodyLight", S.rrect(0, 0, 3.8, 2.8, 0.9, 5.0, 5.25))
    S.put("GoldDark", S.rrect(0, 0, 3.8, 2.8, 0.9, 5.25, 5.5))
    S.put("GoldLight", S.rrect(0, 0, 3.8, 2.8, 0.9, 5.5, 5.75))


def _front(S):
    """the lit sign with the star, the coin plate (viewer's left), the crank (viewer's right), the chute and tray"""
    X, Y, Z = S.X, S.Y, S.Z
    navy = S.rrect_front(0, 3.625, 2.25, 1.125, 0.3, -2.75, -2.25)              # 4.5 x 2.25 (y 2.5 .. 4.75)
    S.put("Navy", navy)
    rim = S.rrect_front(0, 3.625, 2.5, 1.375, 0.4, -2.75, -2.5) & ~navy        # the Neon rim, one cell
    S.put("Glow", rim)
    # the star centred on a cell (x 0.125, y 3.625): on a cell boundary its thin arms lost their tips
    S.put("Emblem", S.front2d(star4_mask(-0.125, 3.625, 1.35, 1.12), -3.0, -2.75) & S.rrect_front(0, 3.625, 2.2, 1.1, 0.3, -4, -2))
    for u, v in ((-1.625, 4.375), (1.625, 2.875)):                              # two twinkles: one lit cell each
        S.put("Emblem", S.front2d(lambda U, V, u=u, v=v: (np.abs(U - u) < 0.13) & (np.abs(V - v) < 0.13), -3.0, -2.75))
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


# the painted egg on each side panel (polish 2026-11-09: ONE bigger egg per panel; three thin ones read as three bars from
# the plaza): its middle (z, y), half width at the widest, half height, the narrower top (the egg profile's taper), the
# Cream band's rows (y from, to)
SIDE_EGG = {"Mid": (0.0, 3.5), "HalfW": 0.7, "HalfH": 1.0, "Taper": 0.2, "Band": (3.25, 3.5)}


def side_egg_mask(Y, Z):
    """the side panel's painted egg (z = across the panel, y = up): 1.4 wide x 2.0 tall, wider below the middle"""
    zc, yc = SIDE_EGG["Mid"]
    t = np.clip((Y - yc) / SIDE_EGG["HalfH"], -1.0, 1.0)
    half = SIDE_EGG["HalfW"] * np.sqrt(np.clip(1.0 - t * t, 0.0, 1.0)) * (1.0 - SIDE_EGG["Taper"] * t)
    return (np.abs(Y - yc) < SIDE_EGG["HalfH"]) & (np.abs(Z - zc) <= half)


def _sides_back(S):
    X, Y, Z = S.X, S.Y, S.Z
    for sx in (-1, 1):
        side = (np.abs(X - sx * 3.6) < 0.3) & (np.abs(Z) < 1.6) & (Y > 2.25) & (Y < 4.75) & (np.abs(X) < 3.65)
        frame = (np.abs(X - sx * 3.6) < 0.3) & (np.abs(Z) < 1.85) & (Y > 2.0) & (Y < 5.0) & ~side & (np.abs(X) < 3.65)
        S.put("Cream", side)
        S.put("Gold", frame)
        # one painted egg in the cabinet's dark shade with a Cream band across its middle (reads as an egg at 25 studs)
        egg = side & side_egg_mask(Y, Z)
        S.put("BodyDark", egg)
        S.put("Cream", egg & (Y > SIDE_EGG["Band"][0]) & (Y < SIDE_EGG["Band"][1]))
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
    _cushion(S)
    # the glass globe on its own 0.5-stud grid, clear of the seat and the lid
    G.glass["Glass"] = (["rgb"] + list(GLASS_RGB), GLASS_T)
    G.flat |= {"Glass"}
    cx, cy, cz = GLOBE_C
    G.put("Glass", G.shell(cx, cy, cz, GLOBE_R[0], GLOBE_R[1]) & (G.Y > GLOBE_Y[0]) & (G.Y < GLOBE_Y[1]))
    # the lid over the glass's top opening
    S.put("GoldDark", S.cyl(0, 0, 2.2, 12.5, 12.75))


# The cloud bed inside the globe (polish 2026-11-09: the 12-egg heap read ~25 % full): cloud fluff on the floor that the
# pile rests on, a thin layer over the whole floor (so no empty glass shows under the front eggs from the plaza) and a
# stepped mound set back towards the rear, so the eggs climb towards the back like a shop display and the globe reads
# about 60 % full from the front with 18 eggs (a real heap that full would take ~60).  Where a gap between eggs shows it,
# it reads as packing fluff.  Tiers (centre z, radius, top y) stacked from the floor: flat tops and upright sides mesh to
# a fraction of a round mound's triangles (the eggs hide nearly all of it); every cell clear of the glass's inner sphere
# by BED_CLEAR.
CUSHION = ((0.0, 1.95, 7.85), (0.35, 1.6, 8.1), (0.55, 1.25, 8.7), (0.75, 0.8, 9.3))
BED_CLEAR = 0.3


def cushion_mask(S):
    m = np.zeros(S.g.L.shape, bool)
    for cz, r, top in CUSHION:
        m |= np.broadcast_to(S.cyl(0.0, cz, r, FLOOR_Y - 0.01, top), m.shape)
    inside = ((S.X - GLOBE_C[0]) ** 2 + (S.Y - GLOBE_C[1]) ** 2 + (S.Z - GLOBE_C[2]) ** 2) < (GLOBE_R[1] - BED_CLEAR) ** 2
    return m & np.broadcast_to(S.Y > FLOOR_Y, m.shape) & np.broadcast_to(inside, m.shape)


def _cushion(S):
    S.put("Cloud", cushion_mask(S))


# The finial (polish 2026-11-09: round 1's swept three-feather wings read as "messy bits" from the plaza, and a flat
# winged cloud at 0.25-stud cells came out as blocky horns): a SUNBURST, ONE silhouette facing the customer, the deco
# topper of an old shop machine.  Review round 2: the first sunburst (seven thin rays, a 0.62 sun) read as a cream crown
# with a white block from the plaza, so: a rising sun, a half disc on the lid (the warm Neon Bulb, the marquee colour)
# inside a one-cell GoldDark rim that keeps it round against the rays, and FIVE Gold rays, each a triangle from a wide
# base at the rim to a pointed tip (never thinner than the stroke whose cells still touch by a face, so no tip floats),
# the tips on the flat ellipse Reach (the price tag stands at 14.2 over the machine: the rays fan out sideways, the
# middle one stays short).  The fan is a plate two cells thick (z -0.25 .. 0.25); nothing above y 14.25; every ray
# touches the rim: one face-connected piece.  SUN: the hub (y), the tips' ellipse (studs, x / y), the rays' angles
# (degrees from +x), the half width at the base / tip, the plate's half thickness, the sun's radius, the rim's width.
SUN = {"Hub": 12.75, "Reach": (3.1, 1.5), "Rays": (14.0, 50.0, 90.0, 130.0, 166.0), "Base": 0.4, "Tip": 0.0,
       "Half": 0.25, "Sun": 0.75, "Rim": 0.25}


def sunburst(S):
    """-> (rays, sun, rim) masks of the finial (picture plane: u = x, v = y - hub).  Each ray a straight wedge from the
    hub to its tip on the ellipse Reach, its half width tapering from Base at the rim to Tip at the tip"""
    U, V = S.X, S.Y - SUN["Hub"]
    plate = (np.abs(S.Z) < SUN["Half"]) & (V > -0.01) & (S.Y < 14.25)
    r2 = U ** 2 + V ** 2
    r0 = SUN["Sun"] + SUN["Rim"]
    sun = plate & (r2 <= SUN["Sun"] ** 2)
    rim = plate & (r2 <= r0 ** 2) & ~sun
    rays = np.zeros(np.broadcast(U, V, S.Z).shape, bool)
    rx, ry = SUN["Reach"]
    for a in SUN["Rays"]:
        tx, ty = rx * math.cos(math.radians(a)), ry * math.sin(math.radians(a))
        L = math.hypot(tx, ty)
        ux, uy = tx / L, ty / L
        s = U * ux + V * uy                                   # along the ray, from the hub
        d = np.abs(U * uy - V * ux)                           # across it
        t = np.clip((s - r0) / (L - r0), 0.0, 1.0)
        thin = 0.5 * S.vs * (abs(ux) + abs(uy)) + 0.01        # the thinnest stroke still face-connected this way
        w = np.maximum(SUN["Base"] * (1 - t) + SUN["Tip"] * t, thin)
        rays |= plate & (d <= w) & (s >= 0.0) & (s <= L)
    shape = S.g.L.shape
    disc = sun | rim
    return np.broadcast_to(rays & ~disc, shape), np.broadcast_to(sun, shape), np.broadcast_to(rim, shape)


def _finial(S):
    """the sunburst finial: five Gold rays, the GoldDark rim, the Neon sun at its hub"""
    rays, sun, rim = sunburst(S)
    S.put("Gold", rays)
    S.put("GoldDark", rim)
    S.put("Bulb", sun)

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