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
  * "lobby_altar_ring"  portal_altar_ring: the summon ring that turns on the Storm Altar's portal disc (StormAltar
                        PortalGlow.GlowRing, the Part ring it dresses: 16 cyan Neon segments on r 6.0, 0.1 - 0.6 up):
                        16 crystal-cyan Neon bars (GlowBar, the altar's CrystalCore rgb(63,200,255)) with a pale Neon
                        ridge on top (GlowBarHeart, the glow disc's heart rgb(186,236,255)) and chamfered ends, so
                        each reads as a crystal blade; each stands in its own charcoal stone collar (the altar's
                        Stone / StoneB / StoneC, a hash pick per collar) with a light lip, rounded corners, a few worn
                        dark lip cells and a dark mason's tick on the face towards the disc centre; an even 0.2-stud
                        joint between collars shows the disc.  The collars are straight (a 16-gon like the Part
                        ring), each voxeled on a grid of its own aligned with it and turned into place, so their
                        walls are flat (arcs on one grid stair-stepped to 8.7k tris).  The bars stand on r 5.65 and
                        the stone ends at r 6.0 (the outer corners), inside the Portal rim's nearest stone face at
                        r 6.1: the ring turns, so it never grinds through the rim.  The collars sink 0.15 under the
                        pivot (into the old disc under the glow disc), so nothing floats.  11.8 x 0.8 x 11.8 studs,
                        0.1-stud cells.  Pivot = the disc centre on the glow disc's top (GlowRing's pivot; it turns
                        about +Y), front -Z.  Attachment Center (the pivot).
  * "lobby_board_lb"    prop_board_lb: the global leaderboard's board on the south lawn (LobbyBoardBuilder.Leaderboard,
                        spec 5.10 "World"), put up by the same carpenters as the plaza's notice boards (props/lobby.py
                        lobby_board) and dressed up a little for the champions.  Everything round the game's Face part
                        (16 x 13, centred 9.5 up, front z -0.2; NOT in the mesh: the PlayerGui SurfaceGui adorns it): the
                        opening is exactly 16 x 13.  A 0.6-stud plank frame (rails top and bottom, stiles between, a tone
                        per bar, grain, flush nails, a dark inner edge round the navy face) one cell proud of the Face, a
                        plank back of 1.2-stud boards with two battens and a centre batten (an H), brass corner caps
                        (rivets) over the four joints front and back; two planed timber posts (seam, grain, iron bolts
                        at the rails, a damp dark band at the foot) on cream stone feet (planed top, a chipped corner, a
                        hairline crack, a ground stain and moss on the shady back); a small stepped rose shingle roof
                        (staggered shingles in three tones, notched eaves, a plank soffit with rafter tails, a ridge
                        with brass end caps) and a gold trophy cup (1.4 tall) standing on the ridge.  No light, no Neon
                        (spec 5.10).  0.2-stud cells on a grid whose cell faces fall on every 0.2, so the opening and
                        the frame land on the Part build exactly; where a Part size is not a whole number of cells the
                        mesh takes the nearest cells round it (posts 1.2 deep for the Part's 1, feet 1.8 wide for 1.6,
                        eaves 9.4 for 9.3; the hidden Parts still collide), and the feet sink 0.2 into the lawn.  About
                        19.6 x 19.2 x 2.4 studs.  Pivot = ground centre, front -Z.  Attachment FaceCenter = the Face's
                        front centre (0, 9.5, -0.2).

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
    # leaderboard board (the lobby's own tones: props/lobby.py PAL planks / cream stone / rose roofs, props/lobby_trove.py
    # TPAL brass; Bd* so the charcoal altar Stone above keeps its name)
    "BdPlank": (196, 146, 98), "BdPlankLight": (214, 166, 114), "BdPlankWarm": (204, 150, 96),
    "BdPlankDark": (152, 108, 72), "BdPlankWet": (118, 84, 58), "BdSeam": (128, 90, 60), "BdGrain": (178, 130, 86),
    "BdStone": (208, 202, 190), "BdStoneLight": (226, 221, 209), "BdStoneDark": (172, 164, 154),
    "BdStoneEdge": (146, 138, 132), "BdMoss": (86, 160, 76), "BdMossLight": (112, 182, 88),
    "BdRose": (234, 120, 146), "BdRoseDark": (206, 96, 124), "BdRoseLight": (244, 150, 172),
    "BdBrass": (236, 186, 80), "BdBrassDark": (200, 148, 60), "BdBrassLight": (252, 220, 132), "BdIron": (64, 70, 92),
    "BdGold": (244, 198, 84), "BdGoldLight": (255, 226, 140), "BdGoldDark": (206, 154, 62),
}
NEONS = {
    "GemGlint": (255, 255, 255), "CrystalCore": (63, 200, 255),
    "GlowBar": (63, 200, 255), "GlowBarHeart": (186, 236, 255),     # the summon ring (StormAltar C.CrystalCore / GlowHeart)
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
        """a round spot of radius r on the shell at (phi0, y0) (a ball round the surface point; on the low egg's coarse
        cells a little bigger, so a dot still catches a surface cell)"""
        if getattr(self, "low", False):
            r = r + 0.35 * self.vs
        p = self.surf(phi0, y0)
        return (self.X - p[0]) ** 2 + (self.Y - p[1]) ** 2 + (self.Z - p[2]) ** 2 <= r * r

    def rows(self, y0, n):
        """exactly n cell rows starting at the cell boundary nearest y0 (n counts the 0.1-stud rows of EGG_K: on a
        coarser grid, egg_<rarity>_pile, the same height in its own rows, at least one; at EGG_K exactly n)"""
        if self.vs != 1.0 / EGG_K:
            n = max(1, int(round(n * (1.0 / EGG_K) / self.vs)))
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
    if getattr(E, "low", False):
        # egg_secret_pile: a 5 x 7 rune is 1.25 x 1.75 studs on 0.25 cells; eight marks (a 2 x 3-cell bar each) instead
        for k in range(8):
            u, v = E.local(k * TAU / 8, 1.45)
            runes |= (np.abs(u) < 0.13) & (np.abs(v) < 0.3)
    row = np.floor((E.Y - 1.1) / vs + 1e-6).astype(int)              # 0 = the runes' bottom row (y 1.1 - 1.2)
    for k, glyph in enumerate(RUNES if not getattr(E, "low", False) else ()):
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


EGG_LOW_K = 4.0                  # egg_<rarity>_pile: 0.25-stud cells (12 rows tall)


@prop("lobby_egg")
def lobby_egg(entry, kit):
    a = entry.get("args") or {}
    rarity = a["rarity"]
    low = bool(a.get("low", False))
    shell, light, paint = EGGS[rarity]
    K = float(a.get("K", EGG_LOW_K if low else EGG_K))
    S = ShopSculpt(kit, K, 1.75, origin=(0.0, EGG_H / 2, 0.0), name="egg")
    E = Egg(S)
    E.low = low
    S.put(shell, E.inside)
    paint(E, S)
    _shine(E, S, light, (shell,))
    if low:
        # egg_<rarity>_pile (shop-area polish 2026-11-09: the Gumball Globe's pile, 1.1 x 1.5 studs in the glass): the
        # same egg and paint on 0.25-stud cells, the Neon details baked as plain colours into the one Fixed part (no
        # Glow* part, no VFX hook: a still pile; one MeshPart per egg instead of up to four)
        for k in list(S.neon):
            SPAL[k] = tuple(int(v) for v in S.neon.pop(k)[1:4])
    m = kit.model(entry["key"], "prop", vs=S.vs, K=K)
    S.mesh_at(m, "Egg", {})
    if low:
        finish(m, {"source": "designed (shop-area polish: the low egg of the Gumball Globe's pile): the %s rarity painted "
                   "egg on 0.25-stud cells, its Neon baked flat" % rarity, "pivot": "bottom centre, front -Z",
                   "rarity": rarity, "glowParts": []})
    else:
        finish(m, {"source": "designed (lobby-shop pitch egglook A, owner: more detail + VFX): the %s rarity painted egg"
                   % rarity, "pivot": "bottom centre, front -Z", "rarity": rarity,
                   "glowParts": sorted(EGG_NEON.get(rarity, {}))})
    m.attachments = {"Center": {"pos": [0.0, EGG_H / 2, 0.0], "rot": np.eye(3).tolist()}}
    return m


# ---------------------------------------------------------------------------------------------- egg halves
# The hatch cutscene's crack (owner pick 2026-11-08 "3D egg + 3D crack"): the same painted egg split along one jagged
# cartoon crack into a top cap and a bottom cup.  Both halves come from the very grid of lobby_egg (same K, origin and
# paint), so together they ARE the whole egg cell for cell, and their pivot is the whole egg's (bottom centre): placed
# at the same CFrame they line up exactly; the GUI swaps them in at the crack and tweens them apart.
# The halves are hollow (a real shell, EGG_WALL thick), so the cup shows its inside when the cap flies off; every face
# the split opens (the cut rim and the cavity) is the lighter inner shell tone, the outer skin keeps its paint.
EGG_SEAM = 1.66                  # the crack's mean height (a little above the middle: a cup and a cap)
EGG_WALL = 0.2                   # the shell thickness of the halves (2 cells)
# the zig-zag: (phi of a tip in tooth widths, height above / below the seam).  Eight bold tips round the egg, a little
# uneven, a deep V right on the front (phi 0) so the crack reads straight away
CRACK_TIPS = ((0.0, -0.3), (1.06, 0.24), (1.97, -0.22), (3.04, 0.29), (3.95, -0.25),
              (5.02, 0.22), (6.05, -0.28), (6.97, 0.26))


def crack_y(phi):
    """the crack's height at the angle phi round the egg (piecewise linear through CRACK_TIPS, periodic)"""
    n = len(CRACK_TIPS)
    xp = np.array([t * TAU / n for t, _ in CRACK_TIPS])
    fp = np.array([EGG_SEAM + d for _, d in CRACK_TIPS])
    return np.interp(np.asarray(phi) % TAU, xp, fp, period=TAU)


def _inner_tones(shell):
    """(rim, cavity) colours of a shell: its inside, lighter (towards a warm white), the cavity a touch deeper"""
    s = np.array(SPAL[shell], float)
    # towards a warm white; the night shell towards lavender (its inside stays in the Starry Night mood, not grey)
    target = (206.0, 192.0, 250.0) if shell == "SecShell" else (255.0, 250.0, 238.0)
    rim = s + (np.array(target) - s) * 0.6
    cav = rim * 0.9
    return tuple(int(round(v)) for v in rim), tuple(int(round(v)) for v in cav)


def _neighbours(mask):
    """cells with a 6-neighbour in mask"""
    out = np.zeros_like(mask)
    for ax in range(3):
        for d in (1, -1):
            out |= np.roll(mask, d, axis=ax)
    return out


@prop("lobby_egg_half")
def lobby_egg_half(entry, kit):
    a = entry.get("args") or {}
    rarity, half = a["rarity"], a["half"]
    if half not in ("top", "bot"):
        raise ValueError("lobby_egg_half: half must be top or bot, not %r" % half)
    shell, light, paint = EGGS[rarity]
    K = float(a.get("K", EGG_K))
    S = ShopSculpt(kit, K, 1.75, origin=(0.0, EGG_H / 2, 0.0), name="egg")
    E = Egg(S)
    S.put(shell, E.inside)
    paint(E, S)
    _shine(E, S, light, (shell,))
    L = S.g.L
    solid = L != 0
    above = np.broadcast_to(E.Y > crack_y(E.phi), L.shape)
    # the hollow: the shell eroded by EGG_WALL in every direction (26-neighbour steps), so the wall is never thinner
    # than two cells, also where the floor meets the wall (a radial cut left a 1-cell rim there that kept its paint)
    cavity = np.broadcast_to(E.inside, L.shape).copy()
    for _ in range(int(round(EGG_WALL / S.vs))):
        core = cavity.copy()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    if dx or dy or dz:
                        core &= np.roll(cavity, (dx, dy, dz), axis=(0, 1, 2))
        cavity = core
    # raised details (Neon trims, stars) stop one cell short of the crack on both halves, so the cut edge is the
    # clean shell and no half-star hangs off a rim (the first render: star stubs read as debris on the rim)
    raised = np.broadcast_to(~E.inside, L.shape) & solid
    near_crack = np.broadcast_to(np.abs(E.Y - crack_y(E.phi)) < 1.5 * S.vs, L.shape)
    keep = solid & (above if half == "top" else ~above) & ~cavity & ~(raised & near_crack)
    air = ~solid | (raised & near_crack)                     # the outside (the painted skin faces it)
    gone = solid & ~keep & ~air                              # the other half and the hollow: faces open onto these
    rim_key, cav_key = shell + "Rim", shell + "Cavity"
    SPAL[rim_key], SPAL[cav_key] = _inner_tones(shell)
    open_to_gone = keep & _neighbours(gone) & ~_neighbours(air)
    cav_wall = open_to_gone & _neighbours(cavity & solid)
    L[~keep] = 0
    S.put(cav_key, cav_wall)
    S.put(rim_key, open_to_gone & ~cav_wall)
    m = kit.model(entry["key"], "prop", vs=S.vs, K=K)
    S.mesh_at(m, "Egg", {})
    finish(m, {"source": "designed (lobby-shop, owner pick 3D egg + 3D crack): the %s half of the %s painted egg, split "
               "along a jagged crack, hollow, the inner shell lighter" % (half, rarity),
               "pivot": "bottom centre of the WHOLE egg (the halves line up with egg_%s exactly), front -Z" % rarity,
               "rarity": rarity, "half": half, "glowParts": sorted(k for k in EGG_NEON.get(rarity, {}) if k in m.objects)})
    zs = np.nonzero(keep.any(axis=(0, 2)))[0]
    oy, vs = float(S.origin[1]), S.vs
    h = S.g.half
    y0, y1 = oy + (zs.min() - h) * vs, oy + (zs.max() - h + 1) * vs
    m.attachments = {
        "Center": {"pos": [0.0, round((y0 + y1) / 2, 4), 0.0], "rot": np.eye(3).tolist()},   # this half's middle: spins
        "Seam": {"pos": [0.0, EGG_SEAM, 0.0], "rot": np.eye(3).tolist()},                     # the crack's mean height
    }
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


# ---------------------------------------------------------------------------------------------- summon ring
# Studs over the pivot (the glow disc's top).  Under it: the old navy disc's top at -0.092 and the glow disc's star
# (points out to r 5.94) at 0, so the collars' foot at -0.15 sinks into the old disc.  The Portal rim's stones stand
# from r 6.1 (their middles) to 6.31 (their joints).  The collars are straight (a 16-gon, like the Part ring), so
# their outer corners are the farthest stone: the outer face at 5.9 puts those corners at 6.0.
ALT_N, ALT_R = 16, 5.65                   # the collars' and bars' centre line, studs from the pivot
ALT_COLLAR = (0.25, 0.1, -0.15, 0.25)     # half width (across the ring), half joint (each end), foot, top
ALT_BAR = (0.15, 0.2, 0.05, 0.55)         # the bar (and the collar's groove): half width, end clearance, foot, top
ALT_RIDGE = (0.06, 0.6, 0.65)             # the pale ridge on the bar: half width, end clearance, top
ALT_TONES = ("Stone", "StoneB", "StoneC")
ALT_K = 10.0


def _altar_collar(kit, i):
    """collar i with its bar and ridge, straight, centred on the front (-Z) at ALT_R, on a grid of its own aligned
    with it (cell faces on its sides: flat walls, no staircase); its ends are mitred to the radial joint lines"""
    S = ShopSculpt(kit, ALT_K, 1.4, origin=(0.0, 0.25, -ALT_R + 0.05), name="altarring%d" % i)  # rows on -0.15, -0.05..
    vs = S.vs
    X, Y, Z = S.X, S.Y, S.Z
    half = math.pi / ALT_N
    d = np.abs(-Z - ALT_R)                                                     # studs across the ring
    e = (-Z) * math.sin(half) - np.abs(X) * math.cos(half)                     # studs from the nearer joint line
    cw, cj, c0, c1 = ALT_COLLAR
    bw, be, b0, b1 = ALT_BAR
    collar = (d < cw) & (e > cj) & (Y > c0) & (Y < c1)                         # joints of an even 0.2 stud
    groove = (d < bw) & (e > be) & (Y > b0)
    # its own stone tone (no dark footing course: it would sit under the old disc)
    S.put(ALT_TONES[int(hsh(i, 29) * 2.999)], collar & ~groove)
    # the lip: the top row light, its four corners rounded off, a worn dark cell or two here and there (old stone;
    # worn, not cut: the walls are one cell thick, so a hole would show the bar's glow through the stone)
    lip = collar & ~groove & (Y > c1 - vs)
    S.put("StoneLight", lip)
    S.cut(lip & (e < be) & (d > bw))
    for k in range(2):
        if hsh(i, k, 31) < 0.45:
            side = 1 if hsh(i, k, 37) < 0.5 else -1                            # the outer or the inner wall
            at = (hsh(i, k, 41) - 0.5) * 1.4                                   # studs along the collar
            S.put("StoneDeep", lip & (np.sign(-Z - ALT_R) == side) & (np.abs(X - at) < 0.1))
    # a mason's tick on the face towards the disc centre: a dark notch two rows tall at the collar's middle
    S.put("StoneDeep", collar & (-Z < ALT_R - cw + vs) & (np.abs(X) < 0.1) & (Y > c0 + vs) & (Y < c0 + 3 * vs))
    # the bar: a crystal blade standing in the groove, its ends chamfered at 45 degrees above the collar
    S.glow("GlowBar", (d < bw) & (Y > b0) & (Y < b1) & (e > be + np.clip(Y - c1, 0, None)))
    rw, re_, r1 = ALT_RIDGE
    S.glow("GlowBarHeart", (d < rw) & (e > re_) & (Y > b1) & (Y < r1))
    return S


def _merge_turned(m, part, rot):
    """add the parts of the model `part` to `m`, turned by the 3x3 `rot` about the model origin (same names merge
    into one part: one Fixed, one GlowBar, one GlowBarHeart)"""
    R = np.asarray(rot, float)
    for name, o in part.objects.items():
        dst = m.obj(name, group=o.group, region=o.region, shade=o.shade, recipe=o.recipe, material=o.material,
                    baked=o.baked)
        dst.keys |= o.keys
        for attr in ("key", "transparency"):
            if hasattr(o, attr):
                setattr(dst, attr, getattr(o, attr))
        if hasattr(o, "fixed_keys"):
            dst.fixed_keys = sorted(set(getattr(dst, "fixed_keys", [])) | set(o.fixed_keys))
        dst.quads.extend((np.asarray(cs, float) @ R.T, col) for cs, col in o.quads)
    m.stats.setdefault("grids", []).extend(part.stats.get("grids", []))


@prop("lobby_altar_ring")
def lobby_altar_ring(entry, kit):
    vs = 1.0 / ALT_K
    m = kit.model(entry["key"], "prop", vs=vs, K=ALT_K)
    for i in range(ALT_N):
        part = kit.model(entry["key"], "prop", vs=vs, K=ALT_K)
        _altar_collar(kit, i).mesh_at(part, "Ring", {})
        t = -i * TAU / ALT_N                       # collar i centred at i * 22.5 degrees round from the front, to +X
        _merge_turned(m, part, [[math.cos(t), 0.0, math.sin(t)], [0.0, 1.0, 0.0], [-math.sin(t), 0.0, math.cos(t)]])
    finish(m, {"source": "designed (lobby-shop pitch portal C, spec 5.11 b): the summon ring that turns on the Storm "
               "Altar's portal disc", "pivot": "the disc centre on the glow disc's top (GlowRing's pivot); turns about +Y"})
    m.attachments = {"Center": {"pos": [0.0, 0.0, 0.0], "rot": np.eye(3).tolist()}}
    return m


# ---------------------------------------------------------------------------------------------- leaderboard board
# Studs from the pivot (the ground centre, front -Z), LobbyBoardBuilder.Leaderboard's layout.  0.2-stud cells; the grid's
# origin (0, 9, 0) puts a cell face on every multiple of 0.2 (x, y and z), so B() boxes land on exact cell faces.
BRD_K = 5.0
BRD_OPEN = (8.0, 3.0, 16.0)               # the opening = the game's Face (16 x 13 centred 9.5 up): half width, bottom, top
BRD_RIM = 0.6                             # the frame round it
BRD_FRAME_Z = (-0.4, 0.2)                 # the frame: its front one cell proud of the Face's front (-0.2), back = the Face's
BRD_BACK_Z = (0.2, 0.6)                   # the plank back (its battens stand one cell behind it)
BRD_POST = (8.4, 9.4, 0.6, 0.8, 16.8)     # |x| from / to, half depth, foot (on the stone), top (inside the soffit)
BRD_FOOT = (8.0, 9.8, 0.8, -0.2, 0.8)     # |x| from / to, half depth, bottom (sunk into the lawn), top
BRD_ROOF = (16.6, 16.8, 17.0, 17.2, 17.6)  # soffit bottom (the frame's top), course A, course B, ridge, ridge top
BRD_EAVE = 9.4                            # the roof's half width (the Part roof 9.3)
BRD_BOARD = 1.2                           # the back boards' width (14 between the posts)
BRD_TONES = ("BdPlank", "BdPlankLight", "BdPlankWarm", "BdPlank")
BRD_ROSES = ("BdRose", "BdRose", "BdRoseDark", "BdRose", "BdRoseLight")


def _chash(a, b, seed):
    """a 0..1 hash per (a, b) integer cell index (numpy arrays; deterministic)"""
    h = (np.asarray(a, np.int64) * 73856093) ^ (np.asarray(b, np.int64) * 19349663) ^ (seed * 83492791)
    h = ((h ^ (h >> 13)) & 0xFFFFFFFF) * 1274126177
    h = (h ^ (h >> 16)) & 0xFFFFFFFF
    return (h & 0xFFFF) / 65535.0


@prop("lobby_board_lb")
def lobby_board_lb(entry, kit):
    S = ShopSculpt(kit, BRD_K, 10.0, origin=(0.0, 9.0, 0.0), name="boardlb")
    vs = S.vs
    X, Y, Z = S.X, S.Y, S.Z
    ax, az = np.abs(X), np.abs(Z)
    IX, IY, IZ = (np.floor(A / vs + 1e-6).astype(np.int64) for A in (X, Y, Z))
    ow, ob, ot = BRD_OPEN
    rim = BRD_RIM
    fz0, fz1 = BRD_FRAME_Z
    bz0, bz1 = BRD_BACK_Z
    px0, px1, pd, py0, py1 = BRD_POST
    kx0, kx1, kd, ky0, ky1 = BRD_FOOT
    r0, rA, rB, rR, rT = BRD_ROOF
    pxc = (px0 + px1) / 2                                                    # 8.9: the post's middle

    # ------------------------------------------------------------------ the stone feet
    foot = (ax > kx0) & (ax < kx1) & (az < kd) & (Y > ky0) & (Y < ky1)
    edge_ring = (ax < kx0 + vs) | (ax > kx1 - vs) | (az > kd - vs)
    S.put("BdStoneDark", foot)
    S.cut(foot & (Y > ky1 - vs) & edge_ring)                                 # the top course planed off round the edge
    S.put("BdStone", foot & (Y > ky1 - vs) & ~edge_ring)
    S.put("BdStoneLight", foot & (Y > ky1 - 2 * vs) & (Y < ky1 - vs) & edge_ring)   # the ledge that leaves
    # the ground stain: a ragged damp band round the bottom (the part above the lawn), moss on the shady back
    col = _chash(IX, IZ, 3)
    S.put("BdStoneEdge", foot & (Y < 0.1 + 0.3 * col) & edge_ring)
    # moss grows in clumps (2 x 2 cell patches), on the shady back and round the post's foot, rarely in front
    clump = _chash(IX // 2, IY // 2, 5)
    S.put("BdMoss", foot & (Z > kd - vs) & (Y < 0.6) & (clump < 0.55))
    S.put("BdMossLight", foot & (Z > kd - vs) & (_chash(IX, IY, 11) > 0.75), only="BdMoss")
    for s in (-1, 1):
        top = (X * s > kx0) & (X * s < kx1) & (Y > ky1 - 2 * vs) & (Y < ky1) & (az < kd)
        near = (X * s > px0 - 2 * vs) & (X * s < px1 + 2 * vs)
        S.put("BdMoss", top & near & (_chash(IX // 2, IZ // 2, 13 + s) < np.where(Z > 0, 0.6, 0.12)),
              only=("BdStone", "BdStoneLight"))
        # a chipped top corner, away from the post
        cx = s * (kx1 - 0.2 if hsh(s, 17) < 0.5 else kx0 + 0.2)
        cz = (kd - 0.2) * (1 if hsh(s, 19) < 0.5 else -1)
        S.cut(foot & (np.abs(X - cx) < 0.25) & (np.abs(Z - cz) < 0.25) & (Y > ky1 - 0.4))
    # a hairline crack down the front of the +X foot
    for j, dx in enumerate((0, 1, 1, 2, 1)):
        S.put("BdStoneEdge", S.cell(8.7 + dx * vs, ky1 - (j + 0.5) * vs, -kd + vs / 2),
              only=("BdStoneDark", "BdStoneLight"))

    # ------------------------------------------------------------------ the posts
    post = (ax > px0) & (ax < px1) & (az < pd) & (Y > py0) & (Y < py1)
    S.put("BdPlankDark", post)
    S.cut(post & ((ax < px0 + vs) | (ax > px1 - vs)) & (az > pd - vs))      # planed long edges
    skin_f = post & (az > pd - vs)                                           # the front and back faces' cells
    S.put("BdSeam", skin_f & (np.abs(ax - pxc) < 0.05))                      # the two-piece timber's joint
    for s in (-1, 1):
        for face in range(3):                                                # front, back, the outer side
            for k in range(2):
                y0 = 3.0 + hsh(s, face, k, 23) * 10.5
                ln = 1.4 + hsh(s, face, k, 29) * 2.4
                if face < 2:
                    cxs = pxc + (0.2 if hsh(s, face, k, 31) < 0.5 else -0.2)
                    run = (Z * (1 if face else -1) > pd - vs) & (np.abs(ax - cxs) < 0.05)
                else:
                    czs = (-0.3, -0.1, 0.1, 0.3)[int(hsh(s, k, 37) * 3.999)]
                    run = (ax > px1 - vs) & (np.abs(Z - czs) < 0.05)
                S.put("BdGrain", post & (X * s > 0) & run & (Y > y0) & (Y < y0 + ln), only="BdPlankDark")
    # the damp dark band at the foot, ragged
    S.put("BdPlankWet", post & (Y < py0 + 0.4 + 0.5 * _chash(IX, IZ, 41)))
    # iron bolts through the posts at the rails (front and back), flush heads
    rail_mid = (ob - rim / 2, ot + rim / 2)                                  # the rails' middle cell rows (2.7, 16.3)
    for s in (-1, 1):
        for yb in rail_mid:
            for zb in (-pd + vs / 2, pd - vs / 2):
                S.put("BdIron", S.cell(s * pxc, yb, zb))

    # ------------------------------------------------------------------ the frame (round the opening) and the back
    outer = (ax < ow + rim) & (Y > ob - rim) & (Y < ot + rim)
    opening = (ax < ow) & (Y > ob) & (Y < ot)
    frame = outer & ~opening & (Z > fz0) & (Z < fz1)
    rails = frame & ((Y < ob) | (Y > ot))                                    # top and bottom, full width
    S.put("BdPlank", frame)
    for i, bar in enumerate((rails & (Y < ob), rails & (Y > ot), frame & ~rails & (X < 0), frame & ~rails & (X > 0))):
        S.put(BRD_TONES[int(hsh(i, 43) * 3.999)], bar)
        # one grain streak on its front
        front = bar & (Z < fz0 + vs)
        if i < 2:
            gx = -6.0 + hsh(i, 47) * 9.0
            gy = rail_mid[i] + vs * (1 if hsh(i, 51) < 0.5 else -1)          # beside the nail row
            S.put("BdGrain", front & (np.abs(Y - gy) < 0.05) & (X > gx) & (X < gx + 2.2 + 1.6 * hsh(i, 53)))
        else:
            gy = 4.5 + hsh(i, 59) * 7.0
            S.put("BdGrain", front & (np.abs(ax - (ow + 2.5 * vs)) < 0.05) & (Y > gy)
                  & (Y < gy + 2.6 + 1.4 * hsh(i, 61)))
    # the dark inner edge round the navy face
    S.put("BdPlankDark", frame & (ax < ow + vs) & (Y > ob - vs) & (Y < ot + vs))
    # flush nails along the rails and the stiles
    for xn in (1.1, 3.1, 5.1, 7.1):
        for s in (-1, 1):
            for yn in rail_mid:
                S.put("BdIron", S.cell(s * xn, yn, fz0 + vs / 2))
    for yn in (6.1, 9.5, 12.9):
        for s in (-1, 1):
            S.put("BdIron", S.cell(s * (ow + rim / 2), yn, fz0 + vs / 2))
    # the plank back: 1.2-stud boards (14 between the posts), a tone each, a seam at each board's edge, a grain streak
    back = outer & (Z > bz0) & (Z < bz1)
    bi = np.floor((X + (px0 - vs / 2)) / BRD_BOARD).astype(np.int64)       # board 0 starts at the -X post's face
    S.put("BdPlank", back)
    for k in range(-1, 15):
        board = back & (bi == k)
        S.put(BRD_TONES[int(hsh(k, 67) * 3.999)], board)
        x0 = -px0 + k * BRD_BOARD
        S.put("BdSeam", board & (X < x0 + vs) & (Z > bz1 - vs))
        gy = ob + 0.5 + hsh(k, 71) * 8.0
        gx = x0 + (2 + int(hsh(k, 73) * 2.999)) * vs + vs / 2
        S.put("BdGrain", board & (Z > bz1 - vs) & (np.abs(X - gx) < 0.05) & (Y > gy)
              & (Y < gy + 2.0 + 2.0 * hsh(k, 79)))
    # two battens across the back between the posts and a straight one up the middle between them (an H: a diagonal
    # brace stair-steps on 0.2-stud cells and cost ~700 tris), nailed to every other board
    bat = (ax < px0) & (Z > bz1) & (Z < bz1 + vs)
    battens = bat & (((Y > 4.4) & (Y < 5.2)) | ((Y > 13.8) & (Y < 14.6)))
    S.put("BdPlankWarm", bat & (ax < 0.4) & (Y > 5.2) & (Y < 13.8))
    S.put("BdPlank", battens)
    for k in range(0, 14, 2):
        xn = -px0 + k * BRD_BOARD + 0.7
        for yn in (4.9, 14.1):
            S.put("BdIron", S.cell(xn, yn, bz1 + vs / 2))
    # brass corner caps over the four joints, front (one cell proud of the frame) and back (on the plank back)
    for s in (-1, 1):
        for yc0, yc1 in ((ob - rim, ob + 0.2), (ot - 0.2, ot + rim)):
            sq = (X * s > ow - 0.2) & (X * s < ow + rim) & (Y > yc0) & (Y < yc1) & ~opening
            S.put("BdBrass", sq & (Z > fz0 - vs) & (Z < fz0))
            S.put("BdBrass", (X * s > px0 - 0.8) & (X * s < px0) & (Y > yc0) & (Y < yc1) & (Z > bz1) & (Z < bz1 + vs))
            yr = rail_mid[0] if yc0 < ob else rail_mid[1]
            S.put("BdBrassLight", S.cell(s * (ow + rim / 2), yr, fz0 - vs / 2))
            S.put("BdBrassLight", S.cell(s * (px0 - 0.3), yr, bz1 + vs / 2))

    # ------------------------------------------------------------------ the roof
    S.put("BdPlankDark", (ax < BRD_EAVE) & (Y > r0) & (Y < rA) & (az < 1.2))                     # the soffit
    for k in range(-5, 6):                                                                     # rafter tails
        S.put("BdPlankDark", (np.abs(X - k * 1.6) < 0.2) & (Y > r0 - vs) & (Y < r0) & (az > 0.8) & (az < 1.2))
    courseA = (ax < BRD_EAVE) & (Y > rA) & (Y < rB) & (az < 1.2)
    courseB = (ax < BRD_EAVE) & (Y > rB) & (Y < rR) & (az < 0.8)
    for ci, (course, off) in enumerate(((courseA, 0.0), (courseB, 0.4))):
        si = np.floor((X + BRD_EAVE + off) / 0.8 + 1e-6).astype(np.int64)                     # shingles 0.8 wide, staggered
        for side in (-1, 1):
            half = course & (Z * side > 0)
            for k in range(-1, 26):
                S.put(BRD_ROSES[int(hsh(ci, side, k, 83) * 4.999)], half & (si == k))
        if ci == 0:
            # notched eaves: a cell cut at every shingle joint on the front and back edges
            joint = np.mod(X + BRD_EAVE, 0.8) < vs                                              # the cell after a joint
            S.cut(course & (az > 1.2 - vs) & joint & (ax < BRD_EAVE - vs))
    ridge = (ax < 9.0) & (Y > rR) & (Y < rT) & (az < 0.4)
    S.put("BdRose", ridge)
    S.put("BdRoseDark", ridge & (Y > rT - vs) & (az < 0.2))
    S.put("BdRoseDark", ridge & (Y < rR + vs) & (az > 0.2))
    S.put("BdBrass", ridge & (ax > 8.6))                                                       # brass end caps
    S.put("BdBrassLight", ridge & (ax > 8.6) & (Y > rT - vs))
    # the trophy cup on the ridge's middle (the board's sign from across the plaza), 7 rows (1.4 studs) of 0.2: a base,
    # a stem, a knot, a bowl flaring out over three rows, a hollow rim, and a loop handle each side
    row = lambda r: (Y > rT + r * vs) & (Y < rT + (r + 1) * vs)                                # noqa: E731
    cup = ((row(0) & (ax < 0.6) & (az < 0.4)) | (row(1) & (ax < 0.2) & (az < 0.2)) | (row(2) & (ax < 0.4) & (az < 0.2))
           | (row(3) & (ax < 0.4) & (az < 0.4)) | (row(4) & (ax < 0.6) & (az < 0.4))
           | ((row(5) | row(6)) & (ax < 0.8) & (az < 0.4)))
    S.put("BdGold", cup)
    S.put("BdGoldDark", cup & (row(0) | row(1)))
    S.put("BdGoldLight", cup & row(6))
    S.cut(row(6) & (ax < 0.6) & (az < 0.2))                                                   # the hollow
    S.put("BdGoldDark", cup & row(5) & (ax < 0.6) & (az < 0.2))                               # the shade inside it
    S.put("BdGoldLight", cup & (row(4) | row(5)) & (np.abs(X - 0.3) < 0.05) & (az > 0.2))     # the shine (the viewer's left)
    ear = (az < 0.2) & ((row(5) & (ax > 0.8) & (ax < 1.2)) | (row(4) & (ax > 1.0) & (ax < 1.2))
                        | (row(3) & (ax > 0.4) & (ax < 1.2)))
    S.put("BdGold", ear)

    m = kit.model(entry["key"], "prop", vs=vs, K=BRD_K)
    S.mesh_at(m, "Board", {})
    finish(m, {"source": "designed (lobby-shop spec 5.10 'World', pitch board A): the global leaderboard's board",
               "pivot": "ground centre, front -Z", "opening": [2 * ow, ot - ob]})
    m.attachments = {"FaceCenter": {"pos": [0.0, (ob + ot) / 2, -0.2], "rot": np.eye(3).tolist()}}
    return m
