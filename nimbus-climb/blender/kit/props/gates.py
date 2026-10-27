"""The Gate Court gates (ARCHITECTURE_V3 6.0.3 / 6.3 art-gates; recipe 4.2 "Gate", 4.3 names, 4.10 mapping).

One prop builder, "gate", makes every gate key from the W1 Part gate of src/shared/WorldStyle.lua (BuildGate:
hoopVoxels / archVoxels + the Crest.* glyphs), re-sculpted finer (0.5-stud gate voxels, 0.25-stud crests):

    gate_obby     hoop + 5-star crest (cloud glyph)        gate_arena    hoop + shield and crossed swords (swords)
    gate_ring     the crowned square arch (crown)          gate_dungeon  hoop + skull over crossed bones (torch)
    gate_altar    hoop + storm cloud (bolt)

gate_home (the arena's green Return gate, glyph "house") is built by props/gates_homestead.py (prop "gate_homestead",
polish 2026-10-27: the homestead family of gate_homeportal) on this same BuildGate contract; its old cartoon cottage
crest is gone.

The mesh replaces ONLY the Part voxels the client hides when it dresses the gate (WorldStyle.GATE_MESH_HIDE):
the stone base / pillars (Stone, StoneDark), the white cloud frame (Frame), the coloured band / caps / keystone /
crown (Trim) and the crest bodies.  The Neon glow ring, the swirl, the gems, the star gems, the skull's eyes, the
house windows (CrestWindow) and the storm bolt stay SEPARATE Neon Parts (PortalFxController animates them), so this mesh leaves
their cells free and sits flush around them.

Frame: the gate's site (ground under the gate centre, front = -Z), exactly the Part gate's frame: Part voxel
(x, y, z) of BuildGate covers x-0.5..x+0.5, y..y+1, z-0.5..z+0.5 studs.  WorldStyle tags the gate model with
ML_Offset = CFrame.new(0, -11.5, 0) (the model pivot is GlowCore, 11.5 up), so the mesh origin lands on the site.

Colour: Trim (and the Arena shield) follow ML_Primary = the gate colour (["Primary"]); every other key is a P4
palette constant.  Keys that nothing looks up by name are baked into the `Fixed` part (tools/mesh_names.py).
"""
import math

import numpy as np

from props import prop

# WorldStyle.Palette (the P4 world) + the gate palette of BuildGate (gatePalette)
PAL = {
    "Stone": (226, 221, 209),       # Palette.StoneLight: the pillars (gate key "Stone")
    "SlabStone": (208, 202, 190),   # Palette.Stone: the base slab (gate key "StoneDark")
    "Mortar": (206, 199, 186),      # a soft course line (between StoneLight and Stone)
    "Edge": (172, 164, 154),        # Palette.StoneDark: the slab's lower lip
    "Frame": (244, 247, 252),       # Palette.CloudLight: the white cloud frame
    "CloudPuff": (232, 238, 249),   # Palette.Cloud
    "Gold": (244, 198, 84),
    "GoldDark": (206, 154, 62),
    "Steel": (206, 214, 228),
    "SteelDark": (150, 160, 184),
    "Bone": (240, 236, 226),
    "BoneDark": (214, 206, 190),
    "Navy": (34, 42, 76),
    "Cream": (246, 234, 210),
    "RoofCoral": (232, 104, 112),   # Palette.RoofRed (the P4 coral)
    "RoofCoralLight": (240, 140, 146),
    "Plank": (196, 146, 98),
    "PlankDark": (152, 108, 72),
    "Mist": (194, 211, 240),
    "MistDark": (170, 190, 228),
    "StormTop": (232, 238, 249),
}
# keys the runtime colours per instance (never baked)
TINTED = {"Trim": ["Primary"], "CrestShield": ["mix", ["Primary"], ["rgb", 34, 42, 76], 0.2]}
# keys looked up by name somewhere (tools/mesh_names.py) or worth their own part: never baked
OWN = {"Stone", "Frame", "Gold"}

# gate kind -> (shape, crest, preview colour = the WorldStyle accent the game passes)
KINDS = {
    "obby": ("Hoop", "cloud", (96, 160, 224)),
    "ring": ("Arch", None, (250, 190, 56)),
    "arena": ("Hoop", "swords", (222, 74, 80)),
    "dungeon": ("Hoop", "torch", (150, 110, 220)),
    "altar": ("Hoop", "bolt", (64, 196, 222)),
}

RING_Y = 11.5  # the hoop's ring centre (BuildGate: voxel row 11, voxel centres 0.5 up)
RING = {"Glow": 5.7, "Inner": 6.6, "Band": 8.6, "Outer": 9.6}  # WorldStyle RING radii (studs)


class Lat:
    """A VoxelGrid seen as a lattice of cell centres in gate studs: cell i spans [i / K, (i + 1) / K) + origin."""

    def __init__(self, kit, K, origin, half_studs, name):
        self.K = float(K)
        self.origin = np.asarray(origin, float)
        self.g = kit.grid(K=K, half=int(math.ceil(half_studs * K)) + 2, name=name)
        h = self.g.half
        c = (np.arange(-h, h + 1) + 0.5) / self.K
        self.X, self.Y, self.Z = np.meshgrid(c + self.origin[0], c + self.origin[1], c + self.origin[2], indexing="ij")
        self.L = self.g.L

    def ids(self, keys):
        if isinstance(keys, str):
            keys = [keys]
        return [self.g.ids[k] for k in keys if k in self.g.ids]

    def put(self, key, mask, only=None, keep=False, empty_ok=True):
        m = np.asarray(mask, bool)
        if only is not None:
            m = m & np.isin(self.L, self.ids(only))
        if keep:
            m = m & (self.L == 0)
        if key is None:
            self.L[m] = 0
        else:
            self.L[m] = self.g.kid(key)
        return int(m.sum())

    def paint(self, key, mask, only=None):
        return self.put(key, np.asarray(mask, bool) & (self.L != 0), only=only)

    def carve(self, mask):
        return self.put(None, mask)

    # ---------------------------------------------------------------- masks (face bounds in studs)
    def box(self, x0, x1, y0, y1, z0, z1):
        e = 1e-6
        return ((self.X > x0 + e) & (self.X < x1 - e) & (self.Y > y0 + e) & (self.Y < y1 - e)
                & (self.Z > z0 + e) & (self.Z < z1 - e))

    def cbox(self, c, s):
        return self.box(c[0] - s[0] / 2, c[0] + s[0] / 2, c[1] - s[1] / 2, c[1] + s[1] / 2, c[2] - s[2] / 2, c[2] + s[2] / 2)

    def rrect(self, cx, cz, hx, hz, r, y0, y1):
        """rounded rectangle prism (half extents hx / hz, corner radius r) between heights y0 and y1"""
        qx = np.abs(self.X - cx) - (hx - r)
        qz = np.abs(self.Z - cz) - (hz - r)
        d = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qz, 0) ** 2) + np.minimum(np.maximum(qx, qz), 0)
        return (d < r - 1e-6) & (self.Y > y0 + 1e-6) & (self.Y < y1 - 1e-6)

    def ell(self, c, r):
        return (((self.X - c[0]) / r[0]) ** 2 + ((self.Y - c[1]) / r[1]) ** 2 + ((self.Z - c[2]) / r[2]) ** 2) <= 1.0

    def rot2(self, cx, cy, ang):
        """local (u, v) coordinates in the XY plane, rotated by ang (radians, counter-clockwise) about (cx, cy)"""
        dx, dy = self.X - cx, self.Y - cy
        ca, sa = math.cos(ang), math.sin(ang)
        return dx * ca + dy * sa, -dx * sa + dy * ca

    def radius(self, cy=RING_Y):
        return np.sqrt(self.X ** 2 + (self.Y - cy) ** 2)

    def offset(self):
        return tuple(self.origin + 0.5 / self.K)


# ---------------------------------------------------------------------------------------------------------------
# the gate body (0.5-stud voxels)
# ---------------------------------------------------------------------------------------------------------------
def base_slab(G):
    """the P4 base: StoneDark slab 23 x 5 (rounded) under a Stone plinth 21 x 4, tile seams and a darker lip"""
    G.put("SlabStone", G.rrect(0, 0, 11.5, 2.5, 1.5, 0, 1))
    G.put("Edge", G.rrect(0, 0, 11.5, 2.5, 1.5, 0, 0.5) & ~G.rrect(0, 0, 11.0, 2.0, 1.0, 0, 0.5))
    G.put("Stone", G.rrect(0, 0, 10.5, 2.0, 1.0, 1, 2))
    # tile seams on the slab's top and front (every 2 studs) and the plinth's front (staggered)
    for x in np.arange(-10, 10.01, 2.0):
        G.paint("Mortar", G.box(x - 0.5, x, 0.5, 1.0, -9, 9), only="SlabStone")
    for x in np.arange(-9, 9.01, 3.0):
        G.paint("Mortar", G.box(x - 0.5, x, 1, 2, -9, 9), only="Stone")


def pillar(G, s, top):
    """a 3 x 3 stone pillar at x = 9s from y 2 to `top`: a foot moulding, stone courses (mortar lines every 1.5 studs,
    staggered joints) and softened vertical edges"""
    cx = 9.0 * s
    G.put("Stone", G.rrect(cx, 0, 1.5, 1.5, 0.5, 2, top))
    G.put("Stone", G.rrect(cx, 0, 2.0, 2.0, 0.5, 2, 2.5))  # foot moulding
    i = 0
    for y in np.arange(4.0, top - 0.6, 2.0):
        G.paint("Mortar", G.box(cx - 3, cx + 3, y, y + 0.5, -3, 3), only="Stone")
        # vertical joints of the course above, staggered
        jx = cx + (0.5 if i % 2 else -0.5)
        G.paint("Mortar", G.box(jx - 0.25, jx + 0.25, y + 0.5, min(y + 2.0, top - 0.5), -3, 3) & (np.abs(G.Z) > 1.0), only="Stone")
        G.paint("Mortar", G.box(jx - 0.25, jx + 0.25, y + 0.5, min(y + 2.0, top - 0.5), -1.0, 1.0) & (np.abs(G.X - cx) > 1.0), only="Stone")
        i += 1


def puffs(G, s):
    """little cloud puffs at the pillar foot (the approved kit portal's cute touch)"""
    cx = 9.0 * s
    for dx, dy, dz, r in ((-1.0, 2.35, -2.35, 1.0), (0.9, 2.25, -2.45, 0.8), (1.9, 2.2, -1.6, 0.65)):
        G.put("CloudPuff", G.ell((cx + dx * s, dy, dz), (r * 1.2, r * 0.8, r)) & (G.Y > 1.0) & (np.abs(G.X - cx) < 2.6), keep=True)


def hoop(G):
    base_slab(G)
    for s in (-1, 1):
        cx = 9.0 * s
        pillar(G, s, 11)
        puffs(G, s)
        # the coloured cap: a 5 x 5 slab with a 4 x 4 step on it, and a gold collar holding the Neon glow block
        G.put("Trim", G.rrect(cx, 0, 2.5, 2.5, 0.5, 11, 11.5))
        G.put("Trim", G.rrect(cx, 0, 2.0, 2.0, 0.5, 11.5, 12))
        G.put("Gold", G.box(cx - 1.0, cx + 1.0, 12, 12.5, -1.0, 1.0) & ~G.box(cx - 0.5, cx + 0.5, 12, 12.5, -0.5, 0.5))
        # a gold-rimmed coloured plaque low on the pillar front (the Part gate's Trim voxel at y 3)
        G.put("Gold", G.box(cx - 0.75, cx + 0.75, 2.75, 4.25, -2.0, -1.5))
        G.put("Trim", G.box(cx - 0.5, cx + 0.5, 3.0, 4.0, -2.5, -1.5))
    # the ring: a stepped pixel band in the gate colour around the white cloud frame; the frame is a shallow channel
    # between an inner lip and the band, filled with soft cloud bumps
    r = G.radius()
    az = np.abs(G.Z)
    band = (r >= RING["Band"]) & (r < RING["Outer"]) & (az < 1.5)
    lip = (r >= RING["Inner"]) & (r < RING["Inner"] + 0.55) & (az < 1.5)
    channel = (r >= RING["Inner"]) & (r < RING["Band"]) & (az < 1.0)
    G.put("Frame", channel | lip)
    ang = np.arctan2(G.Y - RING_Y, G.X)
    for i in range(14):
        a = (i + 0.5) / 14 * 2 * math.pi
        cx, cy = math.cos(a) * 7.6, RING_Y + math.sin(a) * 7.6
        for zs in (-1, 1):
            G.put("Frame", G.ell((cx, cy, zs * 0.95), (0.95, 0.95, 0.55)) & (r >= RING["Inner"]) & (r < RING["Band"]))
    G.put("Trim", band)
    # the band's outer edge: one step proud on the front and back every other 30 degrees (chunky pixel teeth)
    teeth = (np.floor((ang + math.pi) / (math.pi / 12)) % 2 == 0) & (r >= RING["Outer"] - 0.5) & (r < RING["Outer"]) & (az < 1.75)
    G.put("Trim", teeth & (G.Y > 3))
    # gold studs on the band (front and back), on the voxel lattice
    for i in range(12):
        a = i / 12 * 2 * math.pi + math.pi / 12
        px, py = round(math.cos(a) * 9.1 * 2) / 2, round((RING_Y + math.sin(a) * 9.1) * 2) / 2
        if py < 3:
            continue
        for zs in (-1, 1):
            z0, z1 = (-2.0, -1.5) if zs < 0 else (1.5, 2.0)
            G.put("Gold", G.box(px - 0.5, px + 0.5, py - 0.5, py + 0.5, z0, z1))
    # the keystone: a wedge in the gate colour, a gold frame around the Neon gem's socket (the gem is a Part at
    # x -0.5..0.5, y 19..21, z -2.5..-1.5)
    for y0, hx in ((19.0, 2.0), (19.5, 2.25), (20.0, 2.5), (20.5, 2.75)):
        G.put("Trim", G.rrect(0, 0, hx, 1.5, 0.25, y0, y0 + 0.5))
    G.put("Trim", G.rrect(0, 0, 3.0, 1.5, 0.25, 21.0, 21.5))
    G.put("Gold", G.box(-1.0, 1.0, 18.5, 21.5, -2.0, -1.5) & ~G.box(-0.5, 0.5, 19, 21, -2.5, -1.5))


def arch(G):
    """the crowned square arch (P4 Champion Ring): stone pillars between gold bands, a gold lintel on a stone course,
    and a crown with five points (the violet Neon gems are Parts)"""
    base_slab(G)
    for s in (-1, 1):
        x0, x1 = sorted((s * 6.5, s * 9.5))
        cx = (x0 + x1) / 2
        G.put("Stone", G.box(x0, x1, 2, 17, -1.5, 1.5))
        # courses + staggered joints on the front / back / outer faces
        for i, y in enumerate(np.arange(4.0, 15.0, 1.5)):
            G.paint("Mortar", G.box(x0 - 1, x1 + 1, y, y + 0.5, -3, 3), only="Stone")
            jx = cx + (0.75 if i % 2 else -0.75)
            G.paint("Mortar", G.box(jx - 0.25, jx + 0.25, y + 0.5, y + 1.5, -3, 3) & (np.abs(G.Z) > 1.0), only="Stone")
        # gold bands (bottom and top), bevelled: the outer half-stud steps in
        for yb in (2.0, 15.0):
            G.put("Trim", G.box(x0 - 1, x1 + 1, yb, yb + 1, -2.5, 2.5) & ~(G.box(x0 - 1, x1 + 1, yb + 0.5, yb + 1, -3, 3)
                                                                          & ~G.box(x0 - 0.5, x1 + 0.5, yb, yb + 1, -2.0, 2.0)))
        G.put("Trim", G.box(x0 - 0.5, x1 + 0.5, 16, 16.5, -2.0, 2.0))
        # gem sockets: gold rims around the three violet gems (Parts at x 8s, y 6 / 9 / 12, z -2.5..-1.5)
        for y in (6, 9, 12):
            gx = 8.0 * s
            G.put("Gold", G.box(gx - 1.0, gx + 1.0, y - 0.5, y + 1.5, -2.0, -1.5) & ~G.box(gx - 0.5, gx + 0.5, y, y + 1, -3, 3))
        puffs(G, s)
    # lintel: a gold beam (y 17..18) on a stone course (y 18..19), with a darker seam
    G.put("Trim", G.box(-10.5, 10.5, 17, 18, -1.5, 1.5))
    G.put("Stone", G.box(-10.5, 10.5, 18, 19, -1.5, 1.5))
    G.put("Stone", G.box(-11.0, 11.0, 18.5, 19, -2.0, 2.0))
    for x in np.arange(-9, 9.01, 3.0):
        G.paint("Mortar", G.box(x - 0.25, x + 0.25, 18, 18.5, -3, 3), only="Stone")
    # the crown: a band (y 19..21) with a rim, three big points (middle tallest) and two small ones
    G.put("Trim", G.box(-7.5, 7.5, 19, 21, -1.5, 1.5))
    G.put("Gold", G.box(-8.0, 8.0, 19, 19.5, -2.0, 2.0))
    G.put("Gold", G.box(-7.5, 7.5, 20.5, 21, -1.75, 1.75) & ~G.box(-7.0, 7.0, 20.5, 21, -1.5, 1.5) | G.box(-8.0, 8.0, 19, 19.5, -2, 2))
    for px, top in ((-6.0, 23.0), (0.0, 24.0), (6.0, 23.0)):
        # stepped point: 3 wide at the bottom, 2 then 1 wide, gem (Part) on the tip at y top..top+1
        G.put("Trim", G.box(px - 1.5, px + 1.5, 21, 22, -1.5, 1.5))
        G.put("Trim", G.box(px - 1.0, px + 1.0, 22, top - 0.5, -1.0, 1.0))
        G.put("Trim", G.box(px - 0.5, px + 0.5, 22, top, -1.5, 1.5) & ~G.box(px - 0.5, px + 0.5, top - 0.5, top, -0.5, 0.5))
        G.put("Gold", G.box(px - 1.0, px + 1.0, top - 0.5, top, -1.0, 1.0) & ~G.box(px - 0.5, px + 0.5, top - 0.5, top + 1, -0.5, 0.5))
    for px in (-3.0, 3.0):
        G.put("Trim", G.box(px - 0.75, px + 0.75, 21, 21.5, -1.0, 1.0))
        G.put("Trim", G.box(px - 0.5, px + 0.5, 21, 22, -0.5, 0.5))
    # gem settings on the band's front (gems: Parts at x -4 / 0 / 4, y 20, z -2.5..-1.5)
    for gx in (-4.0, 0.0, 4.0):
        G.put("Gold", G.box(gx - 1.0, gx + 1.0, 19.5, 21.5, -2.0, -1.5) & ~G.box(gx - 0.5, gx + 0.5, 20, 21, -3, 3))


# ---------------------------------------------------------------------------------------------------------------
# the crests (0.25-stud voxels; the Part crests of WorldStyle Crest.*: same places, the Neon bits stay Parts)
# ---------------------------------------------------------------------------------------------------------------
def crest_post(C, h0=20.95, h1=22.25, w=0.8):
    C.put("GoldDark", C.box(-w / 2, w / 2, h0, h1, -0.3, 0.3))
    C.put("Gold", C.box(-w / 2 - 0.25, w / 2 + 0.25, h0, h0 + 0.25, -0.5, 0.5))


def crest_cloud(C):
    """Obby: a gold post and bar with five little cradles; the five star gems (Parts, 1.5-stud diamonds at y 23.6,
    x = +-5.2 / +-2.6 / 0) sit in them"""
    crest_post(C)
    C.put("Gold", C.box(-5.75, 5.75, 22.25, 22.75, -0.25, 0.25))
    C.put("GoldDark", C.box(-5.75, 5.75, 22.25, 22.5, -0.25, 0.25))
    for end in (-1, 1):
        C.put("Gold", C.ell((end * 6.0, 22.5, 0), (0.45, 0.45, 0.45)))
    for i in range(5):
        gx = (2 - i) * 2.6
        # a V cradle (two little arms) under each star
        for sx in (-1, 1):
            C.put("Gold", C.box(gx + sx * 0.5 - 0.125, gx + sx * 0.5 + 0.125, 22.75, 23.0, -0.25, 0.25))
            C.put("Gold", C.box(gx + sx * 0.75 - 0.125, gx + sx * 0.75 + 0.125, 23.0, 23.25, -0.25, 0.25))


def crest_swords(C):
    """Arena: a heater shield in the gate colour (navy-tinted) with a gold rim, two crossed steel swords in front"""
    crest_post(C)
    # shield: flat top, rounded sides narrowing to a point at the bottom (2.4 wide, y 22.1..24.7)
    u = np.abs(C.X)
    y = C.Y
    shape = (y > 22.0) & (y < 24.85) & (u < np.where(y > 23.4, 1.45, 1.45 - (23.4 - y) * 0.95))
    inner = (y > 22.35) & (y < 24.6) & (u < np.where(y > 23.4, 1.2, 1.2 - (23.4 - y) * 0.95))
    C.put("Gold", shape & (C.Z > -0.25) & (C.Z < 0.5))
    C.put("CrestShield", inner & (C.Z > -0.45) & (C.Z < 0.4))
    # a little gold chevron on the shield face
    C.put("Gold", inner & (np.abs(y - 23.9 + u * 0.6) < 0.14) & (C.Z > -0.55) & (C.Z < -0.3) & (u < 0.9))
    for s in (-1, 1):
        ang = math.radians(s * 42)
        uu, vv = C.rot2(0.0, 23.6, ang)  # vv along the blade (up), uu across
        zf = (C.Z > -0.75) & (C.Z < -0.45)
        blade = (vv > -1.75) & (vv < 3.1) & (np.abs(uu) < np.where(vv > 2.4, 0.2 - (vv - 2.4) * 0.28, 0.2))
        C.put("Steel", blade & zf)
        C.put("SteelDark", blade & zf & (uu * s > 0.05) & (vv < 2.4))
        C.put("Gold", (vv > -2.1) & (vv < -1.75) & (np.abs(uu) < 0.8) & (C.Z > -0.8) & (C.Z < -0.4))
        C.put("PlankDark", (vv > -2.95) & (vv < -2.1) & (np.abs(uu) < 0.16) & zf)
        C.put("Gold", ((uu ** 2 + (vv + 3.1) ** 2) < 0.24 ** 2 * 1.6) & zf)


def crest_torch(C):
    """Dungeon: a cute rounded skull (dark sockets around the gate-coloured Neon eyes, which are Parts at x +-0.8,
    y 23.75, z -0.83..-0.71), a little navy nose, a tooth row on the jaw, over two crossed knobbly bones"""
    for s in (-1, 1):
        uu, vv = C.rot2(0.0, 23.4, math.radians(s * 45))
        zb = (C.Z > 0.3) & (C.Z < 0.75)
        C.put("Bone", (np.abs(uu) < 0.28) & (np.abs(vv) < 2.75) & zb)
        for e in (-1, 1):
            for k in (-1, 1):
                C.put("Bone", (((uu - k * 0.3) ** 2 + (vv - e * 2.85) ** 2) < 0.36 ** 2) & zb)
    # cranium: a rounded box (x +-1.8, y 22.2..25.5), flatter at the front (z -0.75)
    q = C.rrect(0, 0, 1.8, 0.75, 0.3, 22.4, 25.0) | C.ell((0, 24.4, 0), (1.85, 1.15, 0.72))
    C.put("Bone", q & (C.Z > -0.75))
    C.put("BoneDark", C.box(-1.85, 1.85, 22.2, 22.45, -0.65, 0.65))  # cheek shadow line
    for s in (-1, 1):
        ex = s * 0.8
        C.put("Navy", C.box(ex - 0.6, ex + 0.6, 23.15, 24.35, -0.8, -0.5) & ~C.box(ex - 0.45, ex + 0.45, 23.3, 24.2, -1, 0) & (C.L != 0))
        C.carve(C.box(ex - 0.45, ex + 0.45, 23.3, 24.2, -1, -0.55))
    C.put("Navy", C.box(-0.25, 0.25, 22.55, 23.05, -0.85, -0.5) & (np.abs(C.X) < (23.1 - C.Y) * 0.6 + 0.05))
    # jaw with a tooth row (x +-1.2, y 21.4..22.2)
    C.put("Bone", C.box(-1.2, 1.2, 21.4, 22.2, -0.65, 0.65))
    C.put("BoneDark", C.box(-1.2, 1.2, 21.7, 21.95, -0.75, -0.55) & ((np.floor(C.X * 4 + 0.5) % 2) == 0))


def crest_bolt(C):
    """Altar: a puffy storm cloud on a gold post (light top, misty underside); the gold Neon bolt (Parts at
    z -0.9..-0.7) strikes down its face"""
    crest_post(C, 21.0, 22.7)
    blobs = [((0, 23.75, 0), (2.6, 0.9, 0.62)), ((-1.35, 24.35, 0), (1.25, 1.0, 0.66)), ((0.35, 24.75, 0), (1.15, 0.95, 0.66)),
             ((1.65, 24.3, 0), (1.05, 0.8, 0.62)), ((-2.35, 23.65, 0), (0.75, 0.6, 0.55)), ((2.45, 23.6, 0), (0.75, 0.6, 0.55))]
    m = np.zeros(C.L.shape, bool)
    for c, r in blobs:
        m |= C.ell(c, r)
    m &= C.Y > 22.75
    C.put("StormTop", m)
    C.paint("Mist", m & (C.Y < 23.55))
    C.paint("MistDark", m & (C.Y < 23.1))
    C.carve(C.Z < -0.7)  # the bolt's face stays clear


CRESTS = {"cloud": crest_cloud, "swords": crest_swords, "torch": crest_torch, "bolt": crest_bolt}


def recipes_for(keys):
    rec = {}
    for k in keys:
        if k in TINTED:
            rec[k] = TINTED[k]
        else:
            rec[k] = ["rgb"] + list(PAL[k])
    return rec


@prop("gate")
def build_gate(entry, kit):
    """catalog args: {"kind": obby | ring | arena | dungeon | home | altar, "K": 2.0, "KC": 4.0}"""
    args = entry.get("args") or {}
    kind = args.get("kind", "obby")
    shape, crest, preview = KINDS[kind]
    K = float(args.get("K", 2.0))  # fixed: the lattice lines up with the Part voxels at K 2 (no K steps)
    KC = float(args.get("KC", 4.0))
    m = kit.model(entry["key"], "gate", vs=1.0 / K, K=K)
    used = {}
    G = Lat(kit, K, (0, 13.5, 0), 14.0, "Gate")
    (arch if shape == "Arch" else hoop)(G)
    gkeys = [k for k in G.g.keys if k]
    rec = recipes_for(gkeys)
    fixed = tuple(k for k in gkeys if k not in TINTED and k not in OWN)
    kit.mesh(m, G.g, recipes=rec, group="Gate", vs=1.0 / K, offset=G.offset(), fixed_keys=fixed, used=used,
             shade_opts={"Gold": dict(dark=False), "Frame": dict(dark=False)})
    if crest:
        C = Lat(kit, KC, (0, 24.0, 0), 6.75, "Crest")
        CRESTS[crest](C)
        ckeys = [k for k in C.g.keys if k and np.any(C.L == C.g.ids[k])]
        crec = recipes_for(ckeys)
        cfixed = tuple(k for k in ckeys if k not in TINTED and k not in OWN)
        kit.mesh(m, C.g, recipes=crec, group="Crest", vs=1.0 / KC, offset=C.offset(), fixed_keys=cfixed, used=used,
                 shade_opts={"Gold": dict(dark=False)})
    m.meta = {
        "source": "WorldStyle.BuildGate (%s, %s) at Phase 6 W1" % (shape, crest or "crown"),
        "pivot": "the gate site: ground under the gate centre, front = -Z (WorldStyle tags ML_Offset (0, -11.5, 0))",
        "previewLook": {"Primary": list(preview), "Secondary": [255, 255, 255]},
        "dressHides": "Stone, StoneDark, Frame, Trim + the crest bodies (WorldStyle GATE_MESH_HIDE)",
    }
    return m
