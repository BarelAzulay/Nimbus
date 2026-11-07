"""Lobby-shop art (mission lobby-shop 2026-11-07, pitch cards egglook A / gemlook A / portal C; catalog
blender/catalog/lobby.json): the seven rarity eggs the roulettes now roll, the world gem over the Storm Altar, and the
standing return-portal ring on the altar island.  Same fine-voxel family as the rest of the lobby (props/lobby.py
Sculpt, props/lobby_trove.py cell-exact masks): SmoothPlastic with baked light / dark shading, constant colours baked
into one Fixed part per grid, Neon only for glows.  Nothing here needs a texture or an upload to read.

  * "lobby_egg"         egg_<rarity> (common, uncommon, rare, epic, legendary, mythic, secret): ONE egg shape
                        (2.2 x 3 x 2.2 studs, wider below the middle, pointed top), PAINTED (owner pick egglook A, "more
                        coolness and details"): patterns that wrap right round the egg and grow richer with rarity, the
                        shell = the Config.Rarities colour, a cartoon shine (the shell's light tone) upper left on the
                        front and the back:
                          common     simple spots: darker grey spots in three sizes + little white dots
                          uncommon   a cream zigzag band with a dark green outline, lime spots in its bays, white dots
                          rare       two white bands edged in navy, ringed white dots between them, pale dots
                          epic       a deep violet star band between two raised gold Neon trims (GlowTrim), white Neon
                                     4-point stars in it (GlowStar), white dots above, gold dots below
                          legendary  a white-gold crown (band + eight points, deep amber outline) against a crimson
                                     velvet ring, a Neon gold trim under it and a Neon ball on every point (GlowCrown),
                                     ruby / sapphire Neon gems in the band (GlowRuby, GlowSapphire) with amber studs
                                     between, cream filigree swags under the cap with pearls at their joins
                          mythic     flowing gradient bands (violet / plum foot, blush / pale cap, wavy edges), a Neon
                                     violet wave ribbon (GlowWave), eight teal Neon fiddlehead swirls springing up and
                                     down off it (GlowSwirl), sparkles (GlowStar)
                          secret     night shell with a violet dusk at the foot, violet Neon cracks running down from the
                                     tip (GlowCrack, inlaid) into a ring of magenta Neon runes (GlowRune, inlaid: two
                                     lines + eight 5 x 7 rune marks), white Neon stars (GlowStar), pin-prick stars
                        Neon from Epic up, each Neon detail its own part named Glow<What> (the game attaches its VFX,
                        lights and particles to parts whose name starts with "Glow"); raised details stand one cell
                        proud of the shell.  Every star is the GUI eggs' twinkle (Egg.star): one-cell arms round a
                        small heart, centred on a cell so its arms match (Task 28's inspection: boundary-centred stars
                        read as crosses).  0.1-stud cells (EGG_K 10: the hatch cutscene shows the egg big).  Pivot =
                        bottom centre (it stands), front -Z.  Attachment Center (the middle, for spins and wobbles).
  * "lobby_gem"         gem_world[_low]: a cut gem, 6 studs across the girdle: octagonal crown (8 facets + table) and
                        pavilion (8 facets split into kite halves) in the GUI gem's three tones (light rgb(186,236,255),
                        mid rgb(84,196,246), deep rgb(40,136,214)), a navy girdle as the outline, dark facet edges, and
                        a white Neon star glint on the front-left crown facet.  Pivot = girdle centre; attachment
                        Center (the bounding-box middle).  _low: 0.5-stud voxels, no edges, for 1.5-stud drops.
  * "lobby_portal_ring" portal_ring: the standing return portal on the altar island, 7.8 wide x 9 tall: a charcoal
                        voussoir ring (13 stones, mortar seams, light bevels) on a two-step plinth with side buttresses,
                        a keystone that carries a navy sign board, two cyan crystals on the shoulders (Neon spine), and
                        on the inner face a Neon rim (tinted: Primary, the Arena Return-gate green rgb(96,190,140))
                        standing 0.25 stud proud of the stone so the opening reads as a lit ring.  A Primary-tinted trim
                        line on the plinth's front edge and round the sign board.  Pivot = ground centre, front -Z.
                        Attachments: PortalCenter (centre of the opening: the game's swirl), SignFace (the board's
                        front face centre, facing -Z: the game's SurfaceGui / text part), Pad (on the plinth top).

Deterministic (hash picks only, no RNG state).
"""
import math

import numpy as np

from props import prop
from props.lobby import finish, hsh
from props.lobby_trove import TroveSculpt

SPAL = {
    # eggs (shells = Config.Rarities colours; ShellLight = the shell's shine tone)
    "ComShell": (168, 178, 194), "ComShellLight": (204, 211, 224), "ComSpot": (104, 114, 138),
    "ComDot": (246, 248, 252),
    "UncShell": (104, 196, 128), "UncShellLight": (150, 222, 164), "UncEdge": (38, 110, 66),
    "UncZig": (246, 252, 230), "UncSpot": (204, 244, 96), "UncDot": (246, 255, 248),
    "RarShell": (88, 158, 232), "RarShellLight": (140, 194, 248), "RarEdge": (28, 64, 140),
    "RarBand": (244, 250, 255), "RarDot": (178, 222, 255),
    "EpiShell": (176, 108, 232), "EpiShellLight": (208, 156, 246), "EpiBand": (84, 40, 146),
    "EpiDot": (248, 240, 255), "EpiGold": (240, 192, 84),
    "LegShell": (242, 182, 68), "LegShellLight": (252, 214, 122), "LegEdge": (172, 90, 18),
    "LegCream": (255, 242, 200), "LegFili": (196, 112, 28),
    "LegCrown": (255, 228, 138), "LegVelvet": (168, 30, 62), "LegPearl": (255, 253, 244),
    "MytShell": (238, 98, 140), "MytShellLight": (250, 150, 182), "MytBlush": (246, 140, 178),
    "MytPale": (252, 196, 220), "MytPlum": (200, 74, 176), "MytViolet": (138, 78, 222),
    "SecShell": (40, 40, 52), "SecShellLight": (60, 58, 84), "SecDusk": (60, 42, 116), "SecViolet": (98, 56, 188),
    "SecDot": (226, 222, 255),
    # gem
    "GemGlow": (186, 236, 255), "GemMid": (84, 196, 246), "GemDeep": (40, 136, 214), "GemEdge": (26, 84, 168),
    "GemNavy": (24, 46, 112),
    # portal (StormAltar.lua C: charcoal stone, crystals, sign navy)
    "StoneDeep": (42, 44, 51), "Stone": (75, 77, 87), "StoneB": (66, 68, 78), "StoneC": (84, 87, 98),
    "StoneLight": (112, 115, 126), "Bevel": (163, 166, 174), "Crystal": (70, 172, 252), "SignNavy": (24, 34, 78),
}
NEONS = {
    "GemGlint": (255, 255, 255), "CrystalCore": (63, 200, 255),
}
RETURN_GREEN = (96, 190, 140)    # WorldStyle Green: the arena's Return gate


class ShopSculpt(TroveSculpt):
    """TroveSculpt (cell-exact stud masks) with this module's palette"""

    def recipes(self):
        rec = {}
        for k in self.g.keys:
            if k is None:
                continue
            if k in self.tint:
                rec[k] = self.tint[k]
            elif k in self.neon:
                rec[k] = self.neon[k]
            else:
                rec[k] = ["rgb"] + list(SPAL[k])
        return rec

    def glow(self, key, mask, only=None):
        self.neon[key] = ["rgb"] + list(NEONS[key])
        self.put(key, mask, only=only)


# ---------------------------------------------------------------------------------------------- 2D shape kit
# (u, v) = the picture plane: u = the viewer's right, v = up (studs, egg space)
def disc(U, V, cu, cv, r):
    return (U - cu) ** 2 + (V - cv) ** 2 <= r * r


def poly(U, V, pts):
    """even-odd point in polygon"""
    inside = np.zeros(np.broadcast(U, V).shape, bool)
    n = len(pts)
    for i in range(n):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
        if y0 == y1:
            continue
        cond = (V >= min(y0, y1)) & (V < max(y0, y1))
        xc = x0 + (V - y0) * (x1 - x0) / (y1 - y0)
        inside ^= cond & (U < xc)
    return inside


def stroke(U, V, pts, w):
    """within w of the polyline pts"""
    out = np.zeros(np.broadcast(U, V).shape, bool)
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy or 1e-9
        t = np.clip(((U - x0) * dx + (V - y0) * dy) / L2, 0, 1)
        out |= (U - x0 - t * dx) ** 2 + (V - y0 - t * dy) ** 2 <= w * w
    return out


def star4(U, V, cu, cv, s):
    """a fat 4-point star of half-size s (a concave diamond with a round heart: reads at a few pixels)"""
    a, b = np.abs(U - cu) / s, np.abs(V - cv) / s
    return (a ** 0.65 + b ** 0.65 <= 1.0) | (a * a + b * b <= 0.14)


def ring_dirs(d):
    return [(d * math.cos(a), d * math.sin(a)) for a in np.arange(8) * math.pi / 4]


def outline(fn, U, V, d):
    """a band of width ~d round the shape fn(U, V)"""
    grown = np.zeros(np.broadcast(U, V).shape, bool)
    for du, dv in ring_dirs(d):
        grown |= fn(U + du, V + dv)
    return grown & ~fn(U, V)


# ---------------------------------------------------------------------------------------------- eggs
EGG_H, EGG_A, EGG_TILT = 3.0, 1.1, 0.14
EGG_K = 10.0                     # 0.1-stud cells: 30 rows tall (the hatch cutscene shows the egg big)
TAU = 2 * math.pi
GOLDEN = math.pi * (3 - math.sqrt(5))


def egg_r(Y, grow=0.0):
    t = (Y - EGG_H / 2) / (EGG_H / 2)
    return EGG_A * np.sqrt(np.clip(1 - t * t, 0, None)) * (1 - EGG_TILT * t) + grow


def wrap(a):
    return (a + math.pi) % TAU - math.pi


def tooth(phi, n):
    """a triangle wave round the egg with n teeth: 0 in a tooth's middle (phi = (k + 1/2) * TAU / n), 1 between
    two teeth (phi = k * TAU / n)"""
    return 2 * np.abs((phi * n / TAU) % 1.0 - 0.5)


def mid(k, n):
    """the angle of tooth k's middle"""
    return (k + 0.5) * TAU / n


class Egg:
    """surface coordinates on one egg grid: phi = the angle round the egg (0 = the front, -Z; + towards +X, which is
    the viewer's left from the front), Y = height; local(phi0, y0) = a picture plane (u, v) in studs on the surface"""

    def __init__(self, S):
        self.S, self.vs = S, S.vs
        X, Y, Z = np.broadcast_arrays(S.X, S.Y, S.Z)
        self.X, self.Y, self.Z = X, Y, Z
        self.oy = float(S.origin[1])
        self.rr = np.sqrt(X * X + Z * Z)
        self.phi = np.arctan2(X, -Z)
        self.inside = self.rr <= egg_r(Y)
        # one cell proud of the shell: raised details (Neon) stand on this layer
        self.proud = (self.rr <= egg_r(Y, S.vs)) & (Y > S.vs) & (Y < EGG_H - S.vs)

    def surf(self, phi0, y0):
        r = float(egg_r(y0))
        return np.array([r * math.sin(phi0), y0, -r * math.cos(phi0)])

    def local(self, phi0, y0):
        return wrap(self.phi - phi0) * float(egg_r(y0)), self.Y - y0

    def spot(self, phi0, y0, r):
        """a round spot of radius r on the shell at (phi0, y0) (a ball round the surface point)"""
        p = self.surf(phi0, y0)
        return (self.X - p[0]) ** 2 + (self.Y - p[1]) ** 2 + (self.Z - p[2]) ** 2 <= r * r

    def rows(self, y0, n):
        """exactly n cell rows starting at the cell boundary nearest y0"""
        b = self.oy + round((y0 - self.oy) / self.vs) * self.vs
        return (self.Y > b) & (self.Y < b + (n - 0.01) * self.vs + 0.01 * self.vs)

    def ring(self, y, half):
        return np.abs(self.Y - y) < half

    def line(self, pts, w):
        """within w of the surface polyline through the (phi, y) points (3D segments between surface points)"""
        out = np.zeros(self.X.shape, bool)
        P = [self.surf(p, y) for p, y in pts]
        for a, b in zip(P[:-1], P[1:]):
            d = b - a
            L2 = float(d @ d) or 1e-9
            t = np.clip(((self.X - a[0]) * d[0] + (self.Y - a[1]) * d[1] + (self.Z - a[2]) * d[2]) / L2, 0, 1)
            out |= ((self.X - a[0] - t * d[0]) ** 2 + (self.Y - a[1] - t * d[1]) ** 2
                    + (self.Z - a[2] - t * d[2]) ** 2) <= w * w
        return out

    def star(self, phi0, y0, s):
        """a twinkle star of half-size s, the GUI eggs' twinkle (UI/EggArt): four arms one cell wide out to the tips
        round a small diamond heart.  s 0.35 -> a 7 x 7 sparkle (rows 1 1 3 7 3 1 1), s 0.25 -> a 5 x 5 plus,
        s 0.16 -> a 3 x 3 plus.  Its middle sits on a cell centre and it is measured flat on the surface (the tangent
        plane at the middle), so on the four axis faces every row and column is an odd number of cells and opposite
        arms match.  (Task 28: centred on a cell boundary, the old star came out as two-cell bars with one arm longer,
        which read as a cross, not a star.)"""
        vs, o = self.vs, self.S.origin
        tx, tz = math.cos(phi0), math.sin(phi0)                     # round the egg, in x / z
        yc = o[1] + (math.floor((y0 - o[1]) / vs) + 0.5) * vs       # the middle row's centre
        p = self.surf(phi0, yc)
        cx, cz = float(p[0]), float(p[2])
        if abs(tx) >= abs(tz):                                      # x runs along the surface: an x cell centre
            cx = o[0] + (math.floor((cx - o[0]) / vs) + 0.5) * vs
        else:
            cz = o[2] + (math.floor((cz - o[2]) / vs) + 0.5) * vs
        u = (self.X - cx) * tx + (self.Z - cz) * tz
        au, av = np.abs(u), np.abs(self.Y - yc)
        hw = 0.5 * vs * max(abs(tx), abs(tz))                       # half a cell along the surface: one-cell arms
        near = (np.abs(wrap(self.phi - phi0)) < math.pi / 2) & (self.rr >= egg_r(self.Y) - 2 * vs)   # the outer skin
        across = (av < 0.5 * vs) & (au <= s)
        down = (au < hw) & (av <= s)
        heart = au + av <= 0.6 * s
        return near & (across | down | heart)

    def glow(self, key, rgb, mask, raised=True):
        """a Neon detail: its own part named `key` (the game's VFX hook), raised one cell or inlaid flush"""
        self.S.neon[key] = ["rgb"] + list(rgb)
        self.S.put(key, mask & (self.proud if raised else self.inside))


SHINE_AT = ((0.6, 2.2), (math.pi + 0.6, 2.2))      # the cartoon shine: upper left from the front and from the back


def _shine(E, S, light, shells):
    """a leaning oval of the shell's light tone, top tipped outwards (like a lit ball), on the front and the back"""
    a = math.radians(24)
    for ph, y0 in SHINE_AT:
        u, v = E.local(ph, y0)
        x = u * math.cos(a) - v * math.sin(a)
        y = u * math.sin(a) + v * math.cos(a)
        S.put(light, E.inside & ((x / 0.17) ** 2 + (y / 0.32) ** 2 <= 1), only=shells)


def _clear_of_shine(ph, y, d=0.5):
    return all(abs(wrap(ph - p0)) * 1.1 > d or abs(y - y0) > d for p0, y0 in SHINE_AT)


def _spiral(n, y0, y1, sizes, shift=0.0):
    """n (phi, y, r) spots on a golden-angle spiral from y0 up to y1 (sizes cycle), the ones on the shine left out"""
    out = []
    for i in range(n):
        yy = y0 + (i + 0.5) / n * (y1 - y0)
        pp = wrap(i * GOLDEN + shift)
        if _clear_of_shine(pp, yy):
            out.append((pp, yy, sizes[i % len(sizes)]))
    return out


def _egg_common(E, S):
    """simple spots: darker slate spots in three sizes and little white dots"""
    for ph, y, r in _spiral(13, 0.35, 2.75, (0.32, 0.22, 0.26), shift=1.3):
        S.put("ComSpot", E.inside & E.spot(ph, y, r))
    for ph, y, r in _spiral(10, 0.5, 2.6, (0.11,), shift=2.1):
        S.put("ComDot", E.inside & E.spot(ph, y, r), only="ComShell")


def _egg_uncommon(E, S):
    """a cream zigzag band right round the middle with a dark green outline, lime spots in its bays, white dots"""
    vs = E.vs
    c = 1.36 + 0.21 * (1 - 2 * tooth(E.phi, 8))      # tooth middles up (1.57), between teeth down (1.15)
    d = np.abs(E.Y - c)
    S.put("UncEdge", E.inside & (d <= 0.17 + 1.5 * vs))
    S.put("UncZig", E.inside & (d <= 0.17))
    for k in range(8):
        S.put("UncSpot", E.inside & E.spot(k * TAU / 8, 1.86, 0.16))          # above the band's low points
        S.put("UncSpot", E.inside & E.spot(mid(k, 8), 0.96, 0.16))            # below its high points
        S.put("UncDot", E.inside & E.spot(mid(k, 8), 2.4, 0.09), only="UncShell")
        S.put("UncDot", E.inside & E.spot(k * TAU / 8, 0.5, 0.09), only="UncShell")


def _egg_rare(E, S):
    """two white bands edged in navy, a row of big ringed white dots between them and pale dots above and below"""
    vs = E.vs
    for y in (0.98, 1.92):
        S.put("RarEdge", E.inside & E.ring(y, 0.12 + 1.4 * vs))
        S.put("RarBand", E.inside & E.ring(y, 0.12))
    for k in range(8):
        S.put("RarEdge", E.inside & E.spot(k * TAU / 8, 1.45, 0.17 + vs))
        S.put("RarBand", E.inside & E.spot(k * TAU / 8, 1.45, 0.17))
        S.put("RarDot", E.inside & E.spot(mid(k, 8), 1.45, 0.09))
        S.put("RarDot", E.inside & E.spot(mid(k, 8), 2.42, 0.1), only="RarShell")
        S.put("RarDot", E.inside & E.spot(k * TAU / 8, 0.5, 0.1), only="RarShell")


def _egg_epic(E, S):
    """a deep violet star band between two raised gold Neon trims, white Neon 4-point stars (big / small) in it,
    white dots above and gold dots below.  The band holds nine free rows between the trims (y 1.1 - 2.0) and the
    stars stand on its middle row (y 1.55): a 7-row big star keeps one violet row clear above and below"""
    S.put("EpiBand", E.inside & E.rows(0.9, 13))
    E.glow("GlowTrim", EGG_NEON["epic"]["GlowTrim"], E.rows(0.9, 2) | E.rows(2.0, 2))
    stars = np.zeros(E.X.shape, bool)
    for k in range(4):
        stars |= E.star(k * TAU / 4, 1.55, 0.35) | E.star(k * TAU / 4 + TAU / 8, 1.55, 0.25)
    E.glow("GlowStar", EGG_NEON["epic"]["GlowStar"], stars)
    for k in range(6):
        S.put("EpiDot", E.inside & E.spot(mid(k, 6), 2.5, 0.1), only="EpiShell")
        S.put("EpiGold", E.inside & E.spot(k * TAU / 6, 0.6, 0.11), only="EpiShell")


def _egg_legendary(E, S):
    """a Faberge crown band: a white-gold crown (band + eight tall points, outlined in deep amber) standing against
    a crimson velvet ring, a raised Neon gold trim under it and a Neon gold ball on every point (GlowCrown), raised
    ruby / sapphire Neon gems set in the band with amber filigree studs between, cream filigree swags hanging under
    the cap with pearls at their joins"""
    vs = E.vs
    spike = 0.62 * (1 - tooth(E.phi, 8))                           # straight-sided crown points
    zone = E.inside & (E.Y > 0.8) & (E.Y < 2.1)
    S.put("LegVelvet", zone)
    S.put("LegEdge", zone & (E.Y <= 1.45 + 1.6 * vs + spike))
    S.put("LegEdge", E.inside & E.rows(2.1, 1))
    S.put("LegCrown", zone & (E.Y <= 1.45 + spike))
    neon = EGG_NEON["legendary"]
    balls = np.zeros(E.X.shape, bool)
    for k in range(8):
        balls |= E.spot(mid(k, 8), 2.16, 0.15)
    E.glow("GlowCrown", neon["GlowCrown"], E.rows(0.8, 2) | balls)
    gems = {"GlowRuby": np.zeros(E.X.shape, bool), "GlowSapphire": np.zeros(E.X.shape, bool)}
    for k in range(8):
        gems["GlowRuby" if k % 2 == 0 else "GlowSapphire"] |= E.spot(mid(k, 8), 1.24, 0.2)
        S.put("LegFili", E.inside & E.spot(k * TAU / 8, 1.22, 0.08), only="LegCrown")
    for key in ("GlowRuby", "GlowSapphire"):
        E.glow(key, neon[key], gems[key])
    # swags: eight festoons hanging between the points' columns under the cap, a pearl at every join
    frac = (E.phi * 8 / TAU + 0.5) % 1.0                           # 0 at a point's column
    S.put("LegCream", E.inside & (np.abs(E.Y - (2.5 - 0.14 * np.sin(math.pi * frac))) < 0.055), only="LegShell")
    for k in range(8):
        S.put("LegPearl", E.inside & E.spot(mid(k, 8), 2.5, 0.09))


def _tendril(u, v, hand, up, w):
    """a fiddlehead curl springing from (0, 0): a stem that rises and curls over in 0.8 of a turn, tightening"""
    cx, cy = 0.2, 0.28
    a0 = math.atan2(-cy, -cx)
    r0 = math.hypot(cx, cy)
    pts = []
    for i in range(33):
        s = i / 32
        a = a0 - s * 1.6 * math.pi                                  # clockwise: up the left, over the top
        r = r0 + (0.06 - r0) * s
        pts.append((hand * (cx + r * math.cos(a)), up * (cy + r * math.sin(a))))
    return stroke(u, v, pts, w)


def _egg_mythic(E, S):
    """flowing gradient bands (violet / plum at the foot, blush / pale at the cap, wavy edges), a raised lavender
    Neon wave ribbon round the middle, teal Neon fiddlehead swirls springing up and down off it, white Neon
    sparkles on the cap"""
    w = lambda ph: 0.08 * np.sin(3 * E.phi + ph)                     # noqa: E731
    S.put("MytBlush", E.inside & (E.Y > 2.08 + w(0.0)))
    S.put("MytPale", E.inside & (E.Y > 2.45 + w(1.2)))
    S.put("MytPlum", E.inside & (E.Y < 0.95 + w(2.2)))
    S.put("MytViolet", E.inside & (E.Y < 0.6 + w(3.4)))
    neon = EGG_NEON["mythic"]
    rib = lambda ph: 1.36 + 0.1 * np.sin(2 * ph)                     # noqa: E731
    E.glow("GlowWave", neon["GlowWave"], np.abs(E.Y - rib(E.phi)) < 0.09)
    sw = np.zeros(E.X.shape, bool)
    for k in range(8):
        ph = k * TAU / 8 + TAU / 16
        u, v = E.local(ph, float(rib(ph)))
        sw |= _tendril(u, v, 1 if k % 4 < 2 else -1, 1 if k % 2 == 0 else -1, 0.06)
    E.glow("GlowSwirl", neon["GlowSwirl"], sw & ~(np.abs(E.Y - rib(E.phi)) < 0.09))
    st = np.zeros(E.X.shape, bool)
    for k in range(4):
        # on the axis faces between the swirl columns, at two heights (two on the blush, two on the pale cap), so no two
        # side by side read as a pair of eyes from above
        st |= E.star(k * TAU / 4, (2.25, 2.45)[k % 2], 0.25)
    E.glow("GlowStar", neon["GlowStar"], st)


RUNES = (  # 5 x 7 rune marks, rows top -> bottom (Algiz, Tiwaz, Othala, Dagaz, Ingwaz, Sowilo-ish, Fehu, Hagalaz)
    ("1.1.1", "1.1.1", ".111.", "..1..", "..1..", "..1..", "..1.."),
    ("..1..", ".111.", "1.1.1", "..1..", "..1..", "..1..", "..1.."),
    ("..1..", ".1.1.", "1...1", ".1.1.", "..1..", ".1.1.", "1...1"),
    ("1...1", "11.11", "1.1.1", "1.1.1", "1.1.1", "11.11", "1...1"),
    (".....", "..1..", ".1.1.", "1...1", ".1.1.", "..1..", "....."),
    ("...1.", "..1..", ".1...", "..1..", "...1.", "..1..", ".1..."),
    ("1....", "1..1.", "1.1..", "11..1", "1..1.", "1.1..", "1...."),
    ("1...1", "1...1", "11..1", "1.1.1", "1..11", "1...1", "1...1"),
)
CRACKS = ((0.0, 0.16, -0.06, 0.18, 0.02), (0.0, -0.14, 0.1, -0.16, 0.04),
          (0.0, 0.12, -0.12, 0.1, -0.03), (0.0, -0.1, 0.16, -0.08, 0.05))                # phi wiggles down a crack
CRACK_Y = (2.96, 2.7, 2.48, 2.26, 2.0)


def _egg_secret(E, S):
    """night shell with a violet dusk at the foot (wavy edges), glowing violet Neon cracks running down from the tip
    into a ring of magenta Neon runes round the middle, short cracks rising from the foot, raised white Neon 4-point
    stars and pin-prick stars"""
    vs = E.vs
    S.put("SecDusk", E.inside & (E.Y < 0.72 + 0.07 * np.sin(3 * E.phi)))
    S.put("SecViolet", E.inside & (E.Y < 0.4 + 0.06 * np.sin(3 * E.phi + 1.0)))
    neon = EGG_NEON["secret"]
    # the rune ring: two one-row lines and eight 5 x 7 runes between them (one gap row each side), inlaid
    runes = E.rows(0.9, 1) | E.rows(1.9, 1)
    row = np.floor((E.Y - 1.1) / vs + 1e-6).astype(int)              # 0 = the runes' bottom row (y 1.1 - 1.2)
    for k, glyph in enumerate(RUNES):
        u, _ = E.local(k * TAU / 8, 1.45)
        col = np.floor(u / vs + 3.0).astype(int)        # columns on cell boundaries, not centres
        for r in range(7):
            for c in range(5):
                if glyph[6 - r][c] == "1":
                    runes |= (row == r) & (col == c)
    E.glow("GlowRune", neon["GlowRune"], runes, raised=False)
    # the cracks: from the tip (where four meet in a glowing spot) down to the upper rune line, each with a branch;
    # three short ones rise from the foot to the lower line
    cr = E.spot(0.0, 2.985, 0.16)
    for k, wig in enumerate(CRACKS):
        p0 = k * TAU / 4 + TAU / 8
        pts = [(p0 + dp, y) for dp, y in zip(wig, CRACK_Y)]
        cr |= E.line(pts, 0.085)
        bp, by = pts[2]
        sgn = 1 if k % 2 else -1
        cr |= E.line([(bp, by), (bp + 0.18 * sgn, by - 0.1), (bp + 0.28 * sgn, by - 0.2)], 0.065)
    for k in range(3):
        p0 = k * TAU / 3 + 0.5
        cr |= E.line([(p0, 0.22), (p0 + 0.12, 0.45), (p0 - 0.05, 0.66), (p0 + 0.06, 0.88)], 0.075)
    E.glow("GlowCrack", neon["GlowCrack"], cr, raised=False)
    st = np.zeros(E.X.shape, bool)
    for k in range(4):
        # between the cracks at two heights: the same height on both sides of a crack read as two eyes and a nose
        st |= E.star(k * TAU / 4, (2.55, 2.35)[k % 2], 0.25)
    for k in range(3):
        st |= E.star(k * TAU / 3 + 0.5 + TAU / 6, 0.56, 0.16)
    E.glow("GlowStar", neon["GlowStar"], st)
    for ph, y, r in _spiral(12, 2.1, 2.8, (0.07,), shift=0.9) + _spiral(6, 0.3, 0.8, (0.07,), shift=2.3):
        S.put("SecDot", E.inside & E.spot(ph, y, r), only=("SecShell", "SecDusk", "SecViolet"))


EGGS = {
    # rarity: (shell, shine, painter)
    "common": ("ComShell", "ComShellLight", _egg_common),
    "uncommon": ("UncShell", "UncShellLight", _egg_uncommon),
    "rare": ("RarShell", "RarShellLight", _egg_rare),
    "epic": ("EpiShell", "EpiShellLight", _egg_epic),
    "legendary": ("LegShell", "LegShellLight", _egg_legendary),
    "mythic": ("MytShell", "MytShellLight", _egg_mythic),
    "secret": ("SecShell", "SecShellLight", _egg_secret),
}
# Neon details per egg: part name -> colour (the part names are the game's VFX hooks: every Neon part starts "Glow")
EGG_NEON = {
    "epic": {"GlowTrim": (255, 206, 72), "GlowStar": (255, 248, 220)},
    "legendary": {"GlowCrown": (255, 222, 96), "GlowRuby": (255, 52, 96), "GlowSapphire": (52, 150, 255)},
    "mythic": {"GlowWave": (156, 92, 255), "GlowSwirl": (60, 236, 212), "GlowStar": (255, 246, 252)},
    "secret": {"GlowCrack": (150, 70, 255), "GlowRune": (226, 82, 255), "GlowStar": (255, 248, 220)},
}


@prop("lobby_egg")
def lobby_egg(entry, kit):
    a = entry.get("args") or {}
    rarity = a["rarity"]
    shell, light, paint = EGGS[rarity]
    K = float(a.get("K", EGG_K))
    S = ShopSculpt(kit, K, 1.75, origin=(0.0, EGG_H / 2, 0.0), name="egg")
    E = Egg(S)
    S.put(shell, E.inside)
    paint(E, S)
    _shine(E, S, light, (shell,))
    m = kit.model(entry["key"], "prop", vs=S.vs, K=K)
    S.mesh_at(m, "Egg", {})
    finish(m, {"source": "designed (lobby-shop pitch egglook A, owner: more detail + VFX): the %s rarity painted egg"
               % rarity, "pivot": "bottom centre, front -Z", "rarity": rarity,
               "glowParts": sorted(EGG_NEON.get(rarity, {}))})
    m.attachments = {"Center": {"pos": [0.0, EGG_H / 2, 0.0], "rot": np.eye(3).tolist()}}
    return m


# ---------------------------------------------------------------------------------------------- gem
GEM_R, GEM_G, GEM_TOP, GEM_RT, GEM_CULET = 3.0, 0.25, 1.55, 1.75, -3.05


@prop("lobby_gem")
def lobby_gem(entry, kit):
    a = entry.get("args") or {}
    low = bool(a.get("low", False))
    K = 2.0 if low else 4.0
    S = ShopSculpt(kit, K, 3.4, origin=(0.0, -0.75, 0.0), name="gem")
    vs = S.vs
    X, Y, Z = S.X, S.Y, S.Z
    th = np.arange(8) * math.pi / 4                               # facet normals; k = 6 faces the front (-Z)
    rho = np.stack([X * math.cos(t) + Z * math.sin(t) for t in th])   # (8, n, 1, n)
    rmax = rho.max(0)
    k = rho.argmax(0)
    srt = np.sort(rho, 0)
    gap = srt[-1] - srt[-2]                                       # small = near a facet edge
    crown_r = GEM_R - (GEM_R - GEM_RT) * (Y - GEM_G) / (GEM_TOP - GEM_G)
    pav_r = GEM_R * (Y - GEM_CULET) / (-GEM_G - GEM_CULET)
    crown = (Y >= GEM_G) & (Y < GEM_TOP) & (rmax <= crown_r)
    girdle = (Y >= -GEM_G) & (Y < GEM_G) & (rmax <= GEM_R)
    pav = (Y >= GEM_CULET) & (Y < -GEM_G) & (rmax <= pav_r)
    S.put("GemNavy", girdle)
    # crown: facets alternate light / mid, the table on top light
    S.put("GemGlow", crown & (k % 2 == 0))
    S.put("GemMid", crown & (k % 2 == 1))
    S.put("GemGlow", crown & (Y > GEM_TOP - vs) & (rmax <= GEM_RT - 0.4))
    # pavilion: each facet split into two kite halves (mid / deep, alternating round the gem)
    phi = np.arctan2(Z, X)
    kk = np.take_along_axis(np.broadcast_to(th[:, None, None, None], rho.shape), k[None], 0)[0]
    d = (phi - kk + math.pi) % (2 * math.pi) - math.pi
    half = (d > 0)
    S.put("GemMid", pav & (half ^ (k % 2 == 1)))
    S.put("GemDeep", pav & ~(half ^ (k % 2 == 1)))
    if not low:
        # dark facet edges (where two facet planes meet) on crown and pavilion, the table's rim
        # (only on the facet skins: at the table's middle every plane ties, which is no edge)
        skin = (crown & (rmax > crown_r - 1.5 * vs)) | (pav & (rmax > pav_r - 1.5 * vs))
        S.put("GemEdge", skin & (gap < 0.6 * vs))
    # the star glint on the front-left crown facet (k = 7: the viewer's upper left), Neon white, proud of the facet
    gx, gy = 1.55, 0.95
    s = 0.62 if not low else 0.8
    skin = (Y >= GEM_G) & (Y < GEM_TOP - vs) & (rmax <= crown_r + vs) & (rmax > crown_r - vs) & (Z < 0)
    S.glow("GemGlint", star4(X, Y, gx, gy, s) & skin)
    m = kit.model(entry["key"], "prop", vs=vs, K=K)
    S.mesh_at(m, "Gem", {})
    finish(m, {"source": "designed (lobby-shop pitch gemlook A): the world gem, cut crown + pavilion",
               "pivot": "girdle centre; crown up, pavilion down; front -Z"})
    m.attachments = {"Center": {"pos": [0.0, (GEM_TOP + GEM_CULET) / 2, 0.0], "rot": np.eye(3).tolist()}}
    return m


# ---------------------------------------------------------------------------------------------- portal ring
# (all boxes on the 0.25-stud cell grid: cell centres sit at .125 / .375 / .625 / .875)
RING_YC, RING_RO, RING_RI, RING_RIM, RING_D = 4.5, 3.5, 2.75, 2.5, 0.75
RING_N = 13
SIGN = (-2.0, 2.0, 7.75, 8.75)            # the navy board (x0, x1, y0, y1): 4 x 1 studs
SIGN_Z = -1.25                            # its front face (the frame stands one cell prouder)


@prop("lobby_portal_ring")
def lobby_portal_ring(entry, kit):
    K = 4.0
    S = ShopSculpt(kit, K, 5.25, origin=(0.0, 4.5, 0.0), name="portal")
    vs = S.vs
    X, Y, Z = S.X, S.Y, S.Z
    az = np.abs(Z)
    dy = Y - RING_YC
    rr = np.sqrt(X * X + dy * dy)
    al = np.arctan2(X, dy)                                         # 0 = the top, + towards +X
    # plinth: two steps, the upper one with a light lip
    S.put("StoneDeep", S.B(-3.5, 3.5, 0, 0.5, -1.5, 1.5))
    S.put("Stone", S.B(-3.0, 3.0, 0.5, 1.0, -1.25, 1.25))
    S.put("StoneLight", S.B(-3.0, 3.0, 0.75, 1.0, -1.25, 1.25) & ~S.B(-2.75, 2.75, 0, 2, -1.0, 1.0))
    # the ring: 13 voussoirs (the keystone at the top), a tone each, mortar seams, light bevels front and back
    ring = (rr <= RING_RO) & (rr >= RING_RI) & (az <= RING_D)
    step = 2 * math.pi / RING_N
    u = (al + step / 2) / step
    b = np.floor(u).astype(np.int64)                               # block 0 centred on the top
    for i in range(-RING_N, RING_N + 1):
        S.put(("Stone", "StoneB", "StoneC")[int(hsh(i % RING_N, 11) * 2.999)], ring & (b == i))
    bd = (u - np.floor(u)) * step * rr                             # studs past the block's start (along the arc)
    S.put("StoneDeep", ring & (bd < vs))
    S.put("StoneLight", ring & (az > RING_D - vs) & ((rr > RING_RO - 0.3) | (rr < RING_RI + 0.3)),
          only=("Stone", "StoneB", "StoneC"))
    # buttresses at the ring's feet, capped
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 1.75, sx * 2.75))
        S.put("StoneB", S.B(x0, x1, 1.0, 2.25, -1.0, 1.0) & (rr >= RING_RI))
        S.put("Bevel", S.B(x0, x1, 2.0, 2.25, -1.0, 1.0) & (rr >= RING_RI))
    # the Neon rim on the inner face (tinted Primary: the return-gate green): a cell proud of the stone, 1 stud deep
    S.neon["PortalRim"] = ["Primary"]
    S.put("PortalRim", (rr < RING_RI) & (rr >= RING_RIM) & (az <= 0.5) & (Y > 1.0))
    # the keystone crest that carries the sign: on the ring top, its underside follows the arch
    key = S.B(-2.75, 2.75, 7.0, 9.25, -1.0, 1.0) & (rr >= RING_RI + 0.25)
    S.put("StoneC", key)
    # its cap overhangs one cell all round, and a dark course under the cap
    S.put("Bevel", S.B(-3.0, 3.0, 9.25, 9.5, -1.25, 1.25))
    S.put("StoneDeep", key & (Y > 9.0))
    # the sign: a light stone frame (2 cells proud), a tinted trim line and the navy board (1 cell proud); the game
    # puts its text ("To the Plaza") on SignFace
    x0, x1, y0, y1 = SIGN
    S.put("StoneLight", S.B(x0 - 0.5, x1 + 0.5, y0 - 0.5, y1 + 0.5, -1.5, -1.0)
          & ~S.B(x0 - 0.25, x1 + 0.25, y0 - 0.25, y1 + 0.25, -2, -1.25))
    S.tint["Trim"] = ["Primary"]
    S.put("Trim", S.B(x0 - 0.25, x1 + 0.25, y0 - 0.25, y1 + 0.25, -1.25, -1.0))
    S.put("SignNavy", S.B(x0, x1, y0, y1, -1.25, -1.0))
    # the trim line along the plinth's front top edge
    S.put("Trim", S.B(-3.0, 3.0, 0.75, 1.0, -1.25, -1.0))
    # two crystals on the shoulders (60 degrees from the top), pointing outwards: a diamond section (turned 45
    # degrees like the altar's crystals) on a light stone collar, a Neon spine down the front and back ridges
    for sa in (-1, 1):
        A = sa * math.radians(60)
        dx, dyy = math.sin(A), math.cos(A)
        px, py = (RING_RO - 0.2) * dx, RING_YC + (RING_RO - 0.2) * dyy
        along = (X - px) * dx + (Y - py) * dyy
        across = -(X - px) * dyy + (Y - py) * dx
        L = 2.3
        w = np.where(along < 1.2, 0.6, 0.6 * np.clip((L - along) / (L - 1.2), 0, 1))
        cry = (along >= 0) & (along <= L) & (np.abs(across) + az <= w) & (rr > RING_RO - 0.3)
        S.put("Crystal", cry)
        S.glow("CrystalCore", cry & (np.abs(across) <= 0.13))
        S.put("Bevel", (along >= -0.3) & (along < 0.25) & (np.abs(across) <= 0.75) & (az <= 0.75)
              & (rr <= RING_RO + 0.3) & (rr >= RING_RO - 0.5))
    m = kit.model(entry["key"], "prop", vs=vs, K=K)
    S.mesh_at(m, "Portal", {})
    finish(m, {"source": "designed (lobby-shop pitch portal C): the standing return-portal ring on the altar island",
               "pivot": "ground centre, front -Z", "opening": [RING_RIM * 2, RING_RIM * 2]},
           look={"Primary": list(RETURN_GREEN)})
    eye = np.eye(3).tolist()
    m.attachments = {
        "PortalCenter": {"pos": [0.0, RING_YC, 0.0], "rot": eye},
        "SignFace": {"pos": [0.0, (SIGN[2] + SIGN[3]) / 2, SIGN_Z], "rot": eye},
        "Pad": {"pos": [0.0, 1.0, 0.0], "rot": eye},
    }
    return m
