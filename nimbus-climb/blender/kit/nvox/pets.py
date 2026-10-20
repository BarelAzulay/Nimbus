"""Pet species, wings and accessories in the detailed fine-voxel style, sculpted from parameters.

The shapes are a line-for-line port of shared/PetBuilder.lua (same design coordinates: 1 design unit = 0.1 stud,
the pet faces -Z, +Y up, +X = its right hand, the root/pivot at design (0, 0, 0)), so a species built here has
today's proportions.  What is NEW is the grain and the detail: the grid is sculpted at K voxels per design unit
(K = 1 is today's game grain, ~29 voxels tall; K = 1.65 ~ 48 voxels tall) and every face feature is drawn
PROCEDURALLY in design units (eyes with lash line, pupil, lighter iris, two highlight sparkles and a lower glint;
nose with a shine; "w" mouth; blush; toe gaps), so the finer the grid, the more detail they get.

Palette keys are PetBuilder's (Fur, Belly, Muzzle, ...); colour RECIPES (nvox.colors.eval_recipe) say how each one
follows from a pet's Look (Primary / Secondary / Eye / WingColor), so one species mesh can be recoloured at run time.
"""
import math

from . import colors as C
from .grid import VoxelGrid, angles

TAU = 2 * math.pi
CREAM = ["rgb", 255, 242, 218]
P, S, E, W = ["Primary"], ["Secondary"], ["Eye"], ["WingColor"]

# Keys that are flat accents: never shaded (PetBuilder FLAT_KEYS)
FLAT_KEYS = {"EyeIris", "EyePupil", "EyeShine", "EyeGlint", "EyeRing", "Lash", "Nose", "Mouth", "Blush", "Nostril",
             "Tongue", "Tooth", "Gem", "GemB", "Spark", "Lid", "LidLine", "NoseShine"}


def base_recipes(look):
    """PetBuilder.makePalette as recipes (only the keys the prototype species use; the build wave adds the rest)."""
    dark = C.luminance(look["Primary"]) < 0.3
    WHITE = ["rgb", 255, 255, 255]
    r = {
        "Fur": P,
        "Accent": S,
        "AccentDark": ["darken", S, 0.3],
        "Belly": ["mix", S, ["rgb", 255, 250, 240], 0.45],
        "Muzzle": ["mix", P, ["rgb", 255, 250, 242], 0.6],
        "Stripe": ["mix", ["darken", P, 0.3], S, 0.12],
        "Patch": ["lighten", P, 0.35] if dark else ["darken", P, 0.62],
        "Inner": ["mix", ["rgb", 246, 164, 176], P, 0.15],
        "Nose": ["mix", ["rgb", 226, 118, 136], P, 0.1],
        "Mouth": ["mix", S, WHITE, 0.35] if dark else ["darken", ["mix", P, ["rgb", 120, 52, 64], 0.65], 0.5],
        "Blush": ["mix", ["rgb", 255, 130, 158], P, 0.25],
        "Claw": ["rgb", 250, 238, 216],
        "Horn": ["rgb", 244, 192, 72],
        "Gold": ["rgb", 244, 192, 72],
        "GoldDeep": ["rgb", 214, 148, 50],
        "Wing": W,
        "WingTrim": ["darken", W, 0.25],
        "WingEdge": ["lighten", W, 0.35],
        "WingVein": ["darken", W, 0.35],
        "Tongue": ["rgb", 236, 112, 128],
        "Tooth": ["rgb", 255, 252, 246],
        "Nostril": ["darken", P, 0.62],
        "Gem": ["rgb", 232, 72, 110],
        "GemB": ["rgb", 84, 172, 238],
        "Spark": ["rgb", 255, 250, 232],
        "Cloud": ["rgb", 246, 250, 255],
        "Lid": P,
        "LidLine": ["mix", S, WHITE, 0.2] if dark else ["darken", P, 0.55],
        # cuteEyes (Cat, Dog, Dragon and the other furry species)
        "EyeIris": ["cuteIris", E],
        "EyePupil": ["cutePupil", E, bool(look.get("Glow"))],
        "Lash": ["cuteLash", E],
        "EyeGlint": ["lighten", ["cuteIris", E], 0.5],
        "EyeShine": ["rgb", 252, 252, 255],
        "NoseShine": ["rgb", 255, 255, 255],
    }
    return r


class PetContext:
    def __init__(self, look, K):
        self.look = look
        self.K = K
        self.body = VoxelGrid(K, half=int(32 * K) + 8, name="Body")
        self.wing = VoxelGrid(K, half=int(24 * K) + 8, name="Wing")  # the LEFT wing, hinge-local (reaches -X)
        self.tail = None
        self.rec = base_recipes(look)
        self.eyes = []  # (cx, cy, rx, ry, kind) design units, centre of the pet's right eye (+X)
        self.wing_hinge = [3.8, -1.5, 4.2]
        self.wing_tilt = 0.38
        self.wing_sweep = 0.5
        self.tail_hinge = [0, -8.5, 6]
        self.tail_wag = 0.3
        self.head_c = [0, 6.5, -0.5]
        self.head_r = [8.6, 7, 7.2]
        self.head_top = 13.5
        self.ear_x = 6
        self.neck_y, self.neck_r, self.neck_z = 0, [6, 6], 1
        self.flower_at = [5.5, 11.5, -3]
        self.horn_base = None
        self.shade_opts = {}
        self.fine = True
        self.lid_cells = []

    # ---------------------------------------------------------------- face painting helpers (design units)
    def _cols(self, fn, x0, x1, y0, y1):
        g = self.body
        for X in range(g.vx(x0) - 1, g.vx(x1) + 2):
            for Y in range(g.vx(y0) - 1, g.vx(y1) + 2):
                k = fn(X / g.K, Y / g.K)
                if k:
                    yield X, Y, k

    def paint_front(self, X, Y, key, only=None, carve=False):
        g = self.body
        z = g.front_z(X, Y)
        if z is None:
            return None
        if only and g.get(X, Y, z) not in only:
            return None
        if carve:
            was = g.get(X, Y, z)
            g.set(X, Y, z, None)
            g.set(X, Y, z + 1, key)
            return (X, Y, z, was)
        g.set(X, Y, z, key)
        return (X, Y, z, None)

    def face_disc(self, key, c, r, only=None, carve=False, mirror=False):
        """paint (or carve 1 voxel into) the front surface inside an ellipse in the face plane."""
        out = []
        for s in ((1, -1) if mirror else (1,)):
            cx = c[0] * s
            fn = lambda x, y: key if ((x - cx) / r[0]) ** 2 + ((y - c[1]) / r[1]) ** 2 <= 1 else None
            for X, Y, k in self._cols(fn, cx - r[0], cx + r[0], c[1] - r[1], c[1] + r[1]):
                out.append(self.paint_front(X, Y, k, only, carve))
        return out

    def face_line(self, key, pts, width=0.5, only=None, carve=False, mirror=False):
        """a polyline drawn on the front surface: points snapped to voxels and joined voxel by voxel (never broken,
        at least one voxel wide; `width` design units -> round(width * K) voxels)."""
        g = self.body
        wv = max(1, int(round(width * g.K)))
        for s in ((1, -1) if mirror else (1,)):
            cells = []
            ps = [(p[0] * s * g.K, p[1] * g.K) for p in pts]
            for (ax, ay), (bx, by) in zip(ps, ps[1:]):
                n = int(max(abs(bx - ax), abs(by - ay)) * 4) + 1
                for i in range(n + 1):
                    t = i / n
                    X, Y = int(math.floor(ax + (bx - ax) * t + 0.5)), int(math.floor(ay + (by - ay) * t + 0.5))
                    for dx in range(wv):
                        c = (X + dx - (wv - 1) // 2, Y)
                        if c not in cells:
                            cells.append(c)
            for X, Y in cells:
                self.paint_front(X, Y, key, only, carve)

    def add_eyes(self, cx, cy, rx, ry, kind="Cute"):
        self.eyes.append((cx, cy, rx, ry, kind))

    def carve_eyes(self):
        """Procedural eyes, carved one voxel into the face (like PetBuilder.carveEyes): lash line on top, a dark pupil,
        a lighter iris in the lower half with a glint row, a big highlight top-left (viewer's view = +X) and a small
        one lower right.  The removed front voxels become the blink lids (EyeLids)."""
        g = self.body
        for (cx0, cy, rx, ry, kind) in self.eyes:
            for s in (1, -1):
                cx = cx0 * s
                lid = []
                big = kind == "Big"

                def key_at(x, y):
                    u, v = (x - cx) / rx, (y - cy) / ry  # u: +1 = towards +X (viewer's left)
                    if u * u + v * v > 1:
                        return None
                    # lash line: the top rim (and a little flick at the outer corner)
                    if v > 0.62 and u * u + v * v > 0.55:
                        return "Lash"
                    # highlights (same side on both eyes: one light source, upper left as seen by the viewer)
                    hu, hv = u - 0.32, v - 0.3
                    if (hu / 0.36) ** 2 + (hv / 0.33) ** 2 <= 1:
                        return "EyeShine"
                    su, sv = u + 0.38, v + 0.3
                    if (su / 0.17) ** 2 + (sv / 0.15) ** 2 <= 1:
                        return "EyeShine"
                    if v < -0.72:
                        return "EyeGlint"
                    if v < -0.28 and abs(u) > (0.18 if big else 0.1):
                        return "EyeIris"
                    if v < -0.5:
                        return "EyeIris"
                    return "EyePupil"
                for X in range(g.vx(cx - rx) - 1, g.vx(cx + rx) + 2):
                    for Y in range(g.vx(cy - ry) - 1, g.vx(cy + ry) + 2):
                        k = key_at(X / g.K, Y / g.K)
                        if k:
                            r = self.paint_front(X, Y, k, carve=True)
                            if r:
                                lid.append(r)
                self.lid_cells.append(lid)

    def blush(self, x0, y, w=3):
        self.face_disc("Blush", (x0 + (w - 1) / 2, y - 0.4), ((w + 0.4) / 2, 1.05), mirror=True)


# ---------------------------------------------------------------- shared anatomy (PetBuilder ports)
def head(ctx, key, c, r):
    ctx.body.ell(key, c, r)
    ctx.head_c, ctx.head_r = c, r
    ctx.head_top = c[1] + r[1]


def tri_ear(ctx, s, base, tip, r, inner_key="Inner", tip_key=None):
    g = ctx.body
    bx, by, bz = base[0] * s, base[1], base[2]
    tx, ty, tz = tip[0] * s, tip[1], tip[2]
    g.cone("Fur", (bx, by, bz), (tx, ty, tz), r, 0.35)
    if tip_key:
        g.paint(tip_key, "ellipsoid", only="Fur", center=(tx, ty - 0.8, tz), radius=(r * 0.9, 2.4, r * 0.9))
    g.paint(inner_key, "cone", only="Fur", a=(bx * 1.02, by + 0.6, bz - 1.1), b=(tx * 0.97, ty - 1.6, tz - 0.8), r=r * 0.62, rb=0.2)
    if ctx.fine:
        g.carve("cone", only=["Fur", inner_key], a=(bx * 1.02, by + 0.8, bz - 2.8), b=(tx * 0.97, ty - 1.8, tz - 2.1), r=r * 0.48, rb=0.1)


def sit_body(ctx, body_key="Fur", leg_key="Fur", paw_key=None, body_c=(0, -4.8, 1.5), body_r=(5.4, 5.8, 5.6),
             foot_y=-11.2, front_x=2.8, front_z=-2.6, hind_x=4.3, toes=True, toe_key="Lash"):
    g = ctx.body
    paw_key = paw_key or leg_key
    g.ell(body_key, body_c, body_r)
    for s in (1, -1):
        g.cap(leg_key, (s * front_x, -5.5, front_z + 0.6), (s * front_x, foot_y + 1.3, front_z), 1.75, 1.45)
        g.ell(paw_key, (s * front_x, foot_y + 0.7, front_z - 0.5), (1.65, 1.15, 1.85))
        g.ell(leg_key, (s * hind_x, foot_y + 3.4, 2.4), (2.4, 3, 3.1))
        g.ell(paw_key, (s * (hind_x + 0.1), foot_y + 0.7, 0.4), (1.7, 1.15, 2.4))
        if ctx.fine and toes:
            # two toe gaps on each front paw (and a softer pair on the hind feet), short vertical grooves
            for dx in (-0.62, 0.62):
                ctx.face_line(toe_key, [(s * front_x + dx, foot_y - 0.1), (s * front_x + dx, foot_y + 0.85)], width=0.35, only={paw_key})
    ctx.neck_y = body_c[1] + body_r[1] - 1.2
    ctx.neck_r = [body_r[0] + 0.6, body_r[2] + 0.4]
    ctx.neck_z = body_c[2] - 0.2


def new_tail(ctx, hinge, wag=0.3):
    ctx.tail = VoxelGrid(ctx.K, half=int(16 * ctx.K) + 6, name="Tail")
    ctx.tail_hinge, ctx.tail_wag = list(hinge), wag
    return ctx.tail


def shade_main(ctx, keys, light_only=False):
    # broad light tops / dark undersides (PetBuilder shadeMain) + a soft crease shade and a deep "AO" shade in
    # the tightest creases (neck, armpits, behind the ears): finer voxels can afford the extra colour bands
    for k in keys:
        ctx.shade_opts[k] = dict(light_at=0.62, dark_at=-0.5, crease=0.17, deep=0.12, dark=not light_only)


# ---------------------------------------------------------------- species
SPECIES = {}


def species(fn):
    SPECIES[fn.__name__.capitalize()] = fn
    return fn


@species
def cat(ctx):
    g, look = ctx.body, ctx.look
    head(ctx, "Fur", (0, 6.5, -0.5), (8.6, 7, 7.2))
    for s in (1, -1):
        g.ell("Fur", (s * 5.4, 3.5, -2.8), (3.8, 3, 3.6))
        g.cone("Fur", (s * 7.6, 3.4, -1.8), (s * 10.8, 1.4, -1.2), 1.7, 0.35)
        tri_ear(ctx, s, (5, 10.5, -0.5), (6.6, 17.5, 0), 3.2)
    for s in (1, -1):
        g.ell("Muzzle", (s * 1.4, 2.6, -6.7), (2, 1.6, 1.3))
    ctx.rec["Toe"] = ["darken", ctx.rec["Belly"], 0.32]
    sit_body(ctx, paw_key="Belly", toe_key="Toe")
    g.paint("Belly", "ellipsoid", only="Fur", center=(0, -3.6, -4.2), radius=(3.6, 4.6, 2.6))
    g.cone("Belly", (0, -0.6, -4.6), (0, -3.4, -6.4), 1.9, 0.4)
    # tabby markings: forehead "M", cheek lines, back bands
    for s in (1, -1):
        g.box("Stripe", (s * 1.5, 12.2, -4), (1, 2.6, 7), op="paint", only="Fur")
        for i in range(2):
            g.cap("Stripe", (s * 8.8, 6.5 - i * 2, -2), (s * 6.8, 6.2 - i * 2, -5), 0.55, 0.55, op="paint", only="Fur")
    g.box("Stripe", (0, 12.8, -3.5), (1, 2, 7), op="paint", only="Fur")
    pale = C.luminance(look["Primary"]) > 0.7
    if not pale:
        for i in range(2):
            g.box("Stripe", (0, -2 - i * 3, 6), (20, 1, 8), op="paint", only="Fur")
    ctx.add_eyes(3.5, 7.0, 2.05, 2.55, "Cute")
    shade_main(ctx, ["Fur"], look.get("WingStyle") == "Bat")
    # nose: a small pink triangle, mouth: a little "w"
    ctx.face_line("Nose", [(-0.9, 4.2), (0.9, 4.2)], width=0.75)
    ctx.face_line("Nose", [(-0.35, 3.5), (0.35, 3.5)], width=0.6)
    ctx.face_line("Mouth", [(-2.1, 2.2), (-1.0, 1.25), (0, 2.0), (1.0, 1.25), (2.1, 2.2)], width=0.45)
    ctx.face_line("Mouth", [(0, 3.2), (0, 2.1)], width=0.4)
    ctx.blush(5, 3.4, 3)
    t = new_tail(ctx, (0, -8.5, 6.2), 0.32)
    t.cap("Fur", (0, 0, 0), (0, 0.6, 5), 1.55, 1.4)
    t.cap("Fur", (0, 1, 5.8), (0, 10.4, 6.4), 1.45, 1.2)
    t.ell("Fur", (0, 11.4, 5.6), (1.3, 1.4, 1.4))
    for i in range(1, 4):
        t.box("Stripe", (0, 1.6 + i * 3.1, 7), (7, 1, 7), op="paint", only="Fur")
    if pale:
        ctx.rec["Stripe"] = ["mix", ["darken", P, 0.1], S, 0.55]
    ctx.ear_x, ctx.head_top, ctx.flower_at = 6.2, 13.2, [4, 13, -2.5]


@species
def dog(ctx):
    g, look = ctx.body, ctx.look
    corgi = "corgi" in look.get("Id", "").lower()
    head(ctx, "Fur", (0, 6.6, -0.4), (8, 6.8, 7.2))
    for s in (1, -1):
        g.ell("Fur", (s * 4.8, 3.8, -2.6), (3.6, 2.8, 3.4))
    g.ell("Muzzle", (0, 3, -6.4), (3.4, 2.6, 3))
    g.paint("Muzzle", "ellipsoid", only="Fur", center=(0, 8, -6.8), radius=(1.6 if corgi else 1.1, 3.6, 2))
    g.ell("Nose", (0, 4.3, -9.1), (1.7, 1.1, 0.9))
    # a glossy highlight on the nose (two voxels at the fine grain) and a "w" smile with the tip of a tongue
    ctx.face_disc("NoseShine", (-0.75, 4.85), (0.42, 0.3), only={"Nose"})
    ctx.face_line("Mouth", [(0, 3.15), (0, 2.1)], width=0.45)
    ctx.face_line("Mouth", [(-2.2, 2.3), (-1.1, 1.3), (0, 2.05), (1.1, 1.3), (2.2, 2.3)], width=0.45)
    ctx.face_disc("Tongue", (0, 0.95), (0.75, 0.6))
    if corgi:
        for s in (1, -1):
            tri_ear(ctx, s, (4.4, 10.4, 0), (7.4, 17.6, 0.8), 3.5)
    else:
        for s in (1, -1):
            g.ell("Ear", (s * 7.6, 7.4, 0), (1.7, 4.6, 2.8), rot=angles(0, 0, s * 0.28))
            g.ell("Ear", (s * 8.6, 3.6, -0.2), (1.6, 1.8, 2.4))
        g.paint("Ear", "ellipsoid", only="Fur", center=(3.8, 7.4, -6), radius=(2.8, 3, 3))
    # fine detail: a little cowlick tuft on top of the head and fluffy cheek tufts
    if not corgi:
        g.cone("Fur", (0.2, 12.6, -1.2), (1.1, 14.6, -0.9), 1.0, 0.25)
        g.cone("Fur", (-0.6, 12.8, -0.8), (-1.3, 14.1, -0.4), 0.8, 0.2)
        for s in (1, -1):
            g.cone("Fur", (s * 7.4, 2.6, -2.4), (s * 8.9, 1.5, -2.2), 1.1, 0.3)
    ctx.rec["Toe"] = ["darken", ["mix", S, ["rgb", 255, 250, 242], 0.4], 0.32]
    sit_body(ctx, paw_key="Belly", toe_key="Toe")
    g.paint("Belly", "ellipsoid", only="Fur", center=(0, -3.4, -4.4), radius=(3.8, 4.8, 2.6))
    ctx.add_eyes(3.5, 7.0, 2.05, 2.55, "Cute")
    shade_main(ctx, ["Fur", "Ear"])
    ctx.blush(5.4, 4, 3)
    t = new_tail(ctx, (0, -7.5, 6.2), 0.5)
    t.curve("Fur", [(0, 0, 0), (0, 2.6, 2.4), (0, 5.4, 2.6), (0, 6.8, 0.6)], 1.7, 1.1)
    t.ell("Belly", (0, 6.9, 0.4), (1.3, 1.3, 1.3))
    ctx.rec["Ear"] = ["darken", P, 0.22]
    ctx.rec["Nose"] = ["rgb", 54, 40, 42]
    ctx.rec["Muzzle"] = ["mix", S, ["rgb", 255, 250, 242], 0.4]
    ctx.ear_x = 6.4 if corgi else 7.5
    ctx.head_top = 13.4
    ctx.flower_at = [3, 11.8, -4.4] if corgi else [4.6, 12.6, -3]


@species
def dragon(ctx):
    g, look = ctx.body, ctx.look
    cloudy = look.get("WingStyle") == "Cloud"
    head(ctx, "Fur", (0, 6.8, -0.3), (8.6, 7.2, 7.2))
    for s in (1, -1):
        g.ell("Fur", (s * 5, 3.8, -2.4), (3.8, 3.1, 3.6))
    g.ell("Muzzle", (0, 2.6, -6.3), (4.6, 2.8, 2.6))
    g.ell("Muzzle", (0, 2.2, -5.2), (3.6, 2.6, 2.6))
    # two nostrils (small dark ovals) and an open smile with a tongue, carved into the snout
    ctx.face_disc("Nostril", (1.6, 4.8), (0.5, 0.42), mirror=True, only={"Muzzle"})
    mouth_cells = []

    def mouth(x, y):
        # the PetBuilder mask "M M M M M / M T T T M / . M T M ." as a smooth half-moon
        u, v = x / 2.5, (y - 2.1) / 1.6
        if v > 0.55 or u * u + (v - 0.55) ** 2 / 1.9 > 1:
            return None
        if v < -0.2 and abs(u) < 0.62 or (v < 0.3 and abs(u) < 0.45):
            return "Tongue"
        return "Mouth"
    for X in range(g.vx(-2.6) - 1, g.vx(2.6) + 2):
        for Y in range(g.vx(-0.2) - 1, g.vx(3.2) + 2):
            k = mouth(X / g.K, Y / g.K)
            if k:
                ctx.paint_front(X, Y, k, carve=True)
    # tooth nubs at the top corners of the smile
    ctx.face_disc("Tooth", (1.15, 2.55), (0.4, 0.38), mirror=True, only={"Mouth"})
    if cloudy:
        g.ell("Cloud", (0, 14, 0.4), (2.4, 1.9, 2.2))
        g.ell("Cloud", (1.9, 13.4, 0.8), (1.7, 1.5, 1.7))
        g.ell("Cloud", (-1.9, 13.4, 0.8), (1.7, 1.5, 1.7))
        g.ell("Cloud", (0, 13.2, 2.4), (1.8, 1.5, 1.8))
    else:
        for i in range(3):
            y, z = 13.6 - i * 1.6, 0.4 + i * 2.8
            g.box("Accent", (0, y, z), (3, 2, 3))
            g.box("Accent", (0, y + 1.5, z + 0.5), (3, 1, 2))
            g.box("Accent", (0, y + 2.5, z + 1), (1, 1, 1))
    if look.get("Accessory") != "Horns":
        for s in (1, -1):
            g.cone("Horn", (s * 4.2, 11.4, 0), (s * 5.6, 15.2, 1), 1.6, 0.45)
            # growth rings on the horn nubs (fine detail)
            g.paint("HornRing", "box", only="Horn", center=(s * 4.6, 12.6, 0.3), size=(4, 0.5, 4))
        ctx.rec["Horn"] = ["mix", CREAM, S, 0.25]
        ctx.rec["HornRing"] = ["darken", ["mix", CREAM, S, 0.25], 0.14]
    sit_body(ctx, body_key="Scale", leg_key="Scale", paw_key="Scale", body_r=(5.8, 6, 6), toe_key="Claw", foot_y=-11.4)
    g.paint("Belly", "ellipsoid", only="Scale", center=(0, -4.2, -4.2), radius=(4.2, 5.4, 2.8))
    for i in range(3):
        g.box("BellyLine", (0, -8 + i * 3, -6), (9, 1, 6), op="paint", only="Belly")
    if cloudy:
        for i in range(2):
            g.ell("Cloud", (0, 0.6 - i * 3.4, 6.8 + i * 0.4), (1.6, 1.5, 1.6))
    ctx.add_eyes(4.0, 7.5, 2.5, 3.0, "Big")
    shade_main(ctx, ["Fur", "Scale"] if cloudy else ["Fur"])
    ctx.blush(5.6, 4.4, 3)
    t = new_tail(ctx, (0, -8.6, 5.6), 0.3)
    t.cap("Scale", (0, 0, 0), (0, 0, 5.6), 1.8, 1.5)
    t.cap("Scale", (0, 0, 5.6), (5.6, 0, 5.6), 1.5, 1.2)
    t.cap("Scale", (5.6, 0, 5.6), (6.4, 3, 7.4), 1.2, 1)
    if cloudy:
        t.ell("Cloud", (7, 4, 7.6), (3, 2.5, 2.5))
    else:
        t.cone("Accent", (6.2, 3.6, 7.4), (9.2, 6.2, 8), 2.3, 0.2)
    if cloudy:
        ctx.rec["Fur"] = ["mix", P, S, 0.2]
        ctx.rec["Scale"] = ["mix", P, S, 0.72]
    else:
        ctx.rec["Scale"] = ["lighten", P, 0.1]
    ctx.rec["Belly"] = ["mix", CREAM, P, 0.1]
    ctx.rec["BellyLine"] = ["darken", ["mix", CREAM, P, 0.1], 0.14]
    ctx.rec["Muzzle"] = CREAM
    ctx.rec["Cloud"] = ["mix", ["rgb", 252, 253, 255], P, 0.2]
    ctx.rec["Mouth"] = ["rgb", 92, 44, 60]
    ctx.ear_x, ctx.head_top = 5, 13.4
    ctx.horn_base = [4.2, 11.2, 0]
    ctx.flower_at = [6.2, 11.8, -2.4]
    ctx.wing_hinge = [3.8, -1.2, 4.4]


# ---------------------------------------------------------------- wings (LEFT wing, hinge-local, reaches -X, back = +Z)
WINGS = {}


def feather(w, key, a, b, width, **kw):
    dx, dy = b[0] - a[0], b[1] - a[1]
    ln = math.sqrt(dx * dx + dy * dy)
    c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.5)
    return w.ell(key, c, (ln / 2, width, 0.75), rot=angles(0, 0, math.atan2(dy, dx)), **kw)


def wing_feather(ctx, w):
    tips = [(-14.2, 5), (-14.6, 1.6), (-13.4, -1.6), (-11, -4), (-7.6, -5)]
    for i, tp in enumerate(tips):
        feather(w, "WingTrim" if i % 2 == 1 else "Wing", (-2.6, 1.8), tp, 1.75)
        # a darker shaft line down each flight feather (fine detail)
        feather(w, "WingVein", (-3.4, 1.9), (tp[0] * 0.86, tp[1] * 0.86 + 0.25), 0.22, op="paint", only=["Wing", "WingTrim"])
    w.ell("Wing", (-6.2, 2, 0.5), (6.6, 2.8, 0.75))
    w.ell("WingEdge", (-5.2, 4, 0.5), (6, 2.2, 0.75))
    # a row of small covert feathers (scalloped) along the lower edge of the leading coverts
    for i in range(4):
        w.ell("WingEdge", (-2.6 - i * 2.6, 2.1 - i * 0.15, 0.5), (1.25, 0.9, 0.75), op="paint", only=["Wing", "WingTrim"])
    for tp in tips:
        w.ell("WingTip", (tp[0], tp[1], 0.5), (1.7, 1.7, 1.2), op="paint", only=["Wing", "WingTrim", "WingVein"])
    ctx.rec["WingTip"] = ["darken", W, 0.3]


WINGS["Feather"] = wing_feather


# ---------------------------------------------------------------- accessories: own grid, pivot = the attach point
ACCESSORIES = {}


def acc_crown(K):
    """the Crown, pivot = its base centre (attachment "Hat": (0, HeadTop, HeadC.z) of the species)."""
    g = VoxelGrid(K, half=int(9 * K) + 6, name="Crown")
    # PetBuilder: top = HeadTop - 0.6; band centre at top + 0.6 -> pivot = HeadTop
    g.torus("Gold", (0, 0, 0), 4.2, 1.1)
    g.box("Gold", (0, 0, 0), (8, 1.6, 8), keep=True)
    for i in range(5):
        a = (i / 5) * TAU + 0.3
        x, z = math.cos(a) * 4.2, math.sin(a) * 4.2
        g.cone("Gold", (x, 0.4, z), (x, 3.8, z), 1.2, 0.2)
        g.ell("Spark", (x, 4.0, z), (0.6, 0.6, 0.6))
    # fine detail: a darker gold rim line and little studs between the points
    g.paint("GoldDeep", "torus", only="Gold", center=(0, -0.55, 0), radius=4.2, thickness=1.25, thicknessB=1.25)
    for i in range(5):
        a = ((i + 0.5) / 5) * TAU + 0.3
        g.ell("Gold", (math.cos(a) * 5.1, 0.1, math.sin(a) * 5.1), (0.45, 0.45, 0.45))
    g.ell("Gem", (0, 0.4, -4.6), (1, 1, 0.8))
    for s in (1, -1):
        g.ell("GemB", (s * 3.4, 0.4, -3), (0.8, 0.8, 0.8))
    rec = {"Gold": ["rgb", 244, 192, 72], "GoldDeep": ["rgb", 214, 148, 50], "Spark": ["rgb", 255, 250, 232],
           "Gem": ["rgb", 232, 72, 110], "GemB": ["rgb", 84, 172, 238]}
    return g, rec


ACCESSORIES["Crown"] = acc_crown


def build_species(look, K):
    ctx = PetContext(look, K)
    SPECIES[look["Species"]](ctx)
    ctx.body.fill_pockets(skip_near=FLAT_KEYS)
    if ctx.tail is not None:
        ctx.tail.fill_pockets(skip_near=FLAT_KEYS)
    ctx.carve_eyes()
    return ctx
