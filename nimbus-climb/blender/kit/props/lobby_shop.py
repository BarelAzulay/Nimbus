"""Lobby-shop art (mission lobby-shop 2026-11-07, pitch cards egglook C / gemlook A / portal C; catalog
blender/catalog/lobby.json): the seven rarity eggs the roulettes now roll, the world gem over the Storm Altar, and the
standing return-portal ring on the altar island.  Same fine-voxel family as the rest of the lobby (props/lobby.py
Sculpt, props/lobby_trove.py cell-exact masks): SmoothPlastic with baked light / dark shading, constant colours baked
into one Fixed part per grid, Neon only for glows.  Nothing here needs a texture or an upload to read.

  * "lobby_egg"         egg_<rarity> (common, uncommon, rare, epic, legendary, mythic, secret): ONE egg shape
                        (2.2 x 3 x 2.2 studs, wider below the middle, pointed top) with seven paint sets of sky-weather
                        pictures, drawn BIG on the front and again on the back (each reads the right way round from
                        its side), raised one voxel and ringed by a dark outline so they read at 30 px:
                          common     grey shell (Pet Index 168,178,194), a big white cloud + a small one
                          uncommon   green shell, a white breeze swirl with a gust tail and a lime leaf
                          rare       blue shell, three pale raindrops with white highlights
                          epic       purple shell, a gold lightning bolt (Neon)
                          legendary  gold shell, a sun: warm yellow Neon disc + orange rays
                          mythic     pink shell, three wavy aurora bands right round the egg (Neon teal / green / violet)
                          secret     near-black night shell with a violet horizon at the bottom, a crescent moon and
                                     4-point stars (Neon), pin-prick stars
                        The glow grows with rarity: no Neon up to Rare, the picture is Neon from Epic up.  Pivot =
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
    # eggs (shells = Config.Rarities colours; Light / Dark = the shell's own tones)
    "ComShell": (168, 178, 194), "ComShellLight": (196, 204, 218), "ComEdge": (92, 104, 128),
    "ComCloud": (250, 251, 255), "ComCloudShade": (222, 230, 244),
    "UncShell": (104, 196, 128), "UncShellLight": (140, 216, 156), "UncEdge": (38, 110, 66),
    "UncSwirl": (240, 255, 244), "UncLeaf": (196, 240, 92), "UncVein": (88, 150, 52),
    "RarShell": (88, 158, 232), "RarShellLight": (128, 186, 244), "RarEdge": (30, 74, 152),
    "RarDrop": (214, 240, 255), "RarShine": (255, 255, 255),
    "EpiShell": (176, 108, 232), "EpiShellLight": (202, 146, 244), "EpiEdge": (76, 34, 128),
    "LegShell": (242, 182, 68), "LegShellLight": (250, 210, 112), "LegEdge": (150, 84, 22), "LegRay": (240, 112, 44),
    "MytShell": (238, 98, 140), "MytShellLight": (248, 142, 176), "MytEdge": (150, 40, 88),
    "SecShell": (40, 40, 52), "SecShellLight": (58, 56, 82), "SecDusk": (64, 44, 120), "SecViolet": (104, 60, 196),
    "SecEdge": (18, 16, 30), "SecDot": (226, 222, 255),
    # gem
    "GemGlow": (186, 236, 255), "GemMid": (84, 196, 246), "GemDeep": (40, 136, 214), "GemEdge": (26, 84, 168),
    "GemNavy": (24, 46, 112),
    # portal (StormAltar.lua C: charcoal stone, crystals, sign navy)
    "StoneDeep": (42, 44, 51), "Stone": (75, 77, 87), "StoneB": (66, 68, 78), "StoneC": (84, 87, 98),
    "StoneLight": (112, 115, 126), "Bevel": (163, 166, 174), "Crystal": (70, 172, 252), "SignNavy": (24, 34, 78),
}
NEONS = {
    "EpiBolt": (250, 214, 92), "LegSun": (255, 212, 72),
    "MytTeal": (56, 222, 204), "MytGreen": (150, 250, 150), "MytViolet": (124, 84, 255),
    "SecMoon": (255, 238, 160), "SecStar": (255, 250, 222),
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


def egg_r(Y, grow=0.0):
    t = (Y - EGG_H / 2) / (EGG_H / 2)
    return EGG_A * np.sqrt(np.clip(1 - t * t, 0, None)) * (1 - EGG_TILT * t) + grow


def _cloud(U, V):
    # a flat-bottomed cloud with three clear puffs (the middle one tallest) and a small cloud above-left
    base = poly(U, V, [(-0.70, 0.98), (0.70, 0.98), (0.70, 1.34), (-0.70, 1.34)])
    ends = disc(U, V, -0.70, 1.16, 0.18) | disc(U, V, 0.70, 1.16, 0.18)
    main = base | ends | disc(U, V, -0.48, 1.34, 0.32) | disc(U, V, 0.0, 1.56, 0.44) | disc(U, V, 0.50, 1.38, 0.32)
    main &= V >= 0.98
    small = (disc(U, V, -0.56, 2.30, 0.16) | disc(U, V, -0.33, 2.40, 0.21) | disc(U, V, -0.10, 2.30, 0.15)) & (V >= 2.18)
    return main | small


def _gust(x0, x1, y, cx, cy, r, a0, a1):
    """the wind icon's stroke: a straight line from (x0, y) to (x1, y) that ends in a curl (an arc round (cx, cy)
    from angle a0 to a1, degrees)"""
    pts = [(x0, y), (x1, y)]
    for i in range(1, 25):
        a = math.radians(a0 + (a1 - a0) * i / 24)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# two gusts: the upper one curls up and back over itself, the lower one curls down
GUSTS = (_gust(-0.78, 0.28, 2.02, 0.28, 2.30, 0.28, -90, 160),
         _gust(-0.86, 0.42, 1.52, 0.42, 1.25, 0.27, 90, -120))


def _breeze(U, V):
    out = np.zeros(np.broadcast(U, V).shape, bool)
    for g in GUSTS:
        out |= stroke(U, V, g, 0.13)
    return out


def _leaf_frame(U, V):
    # the leaf: a lens 1 stud long tilted 20 degrees, at the lower left
    a = math.radians(20)
    du, dv = U + 0.45, V - 0.80
    x = du * math.cos(a) + dv * math.sin(a)
    y = -du * math.sin(a) + dv * math.cos(a)
    return x, y


def _leaf(U, V):
    x, y = _leaf_frame(U, V)
    return (np.abs(x) <= 0.5) & (np.abs(y) <= 0.27 * np.sqrt(np.clip(1 - (x / 0.5) ** 2, 0, None)) + 0.02)


def _leaf_vein(U, V):
    x, y = _leaf_frame(U, V)
    return (np.abs(y) <= 0.05) & (x > -0.42) & (x < 0.36)


def _uncommon(U, V):
    return _breeze(U, V) | _leaf(U, V)


def _drop(U, V, cu, cv, r):
    body = disc(U, V, cu, cv, r)
    h = (V - cv) / (1.9 * r)
    tip = (V >= cv) & (h <= 1) & (np.abs(U - cu) <= r * np.clip(1 - h, 0, 1) ** 1.25)
    return body | tip


DROPS = ((0.02, 1.18, 0.46), (-0.50, 2.00, 0.26), (0.52, 2.08, 0.27))


def _rain(U, V):
    out = np.zeros(np.broadcast(U, V).shape, bool)
    for d in DROPS:
        out |= _drop(U, V, *d)
    return out


def _rain_shine(U, V):
    out = np.zeros(np.broadcast(U, V).shape, bool)
    for (cu, cv, r) in DROPS:
        out |= disc(U, V, cu - 0.4 * r, cv - 0.05 * r, 0.3 * r)
    return out


BOLT = [(-0.06, 2.66), (0.62, 2.66), (0.16, 1.86), (0.62, 1.86), (-0.42, 0.38), (-0.06, 1.46), (-0.52, 1.46)]


def _bolt(U, V):
    return poly(U, V, BOLT)


SUN_C, SUN_R = (0.0, 1.52), 0.44


def _sun_rays(U, V):
    du, dv = U - SUN_C[0], V - SUN_C[1]
    rho = np.sqrt(du * du + dv * dv)
    ang = np.arctan2(dv, du)
    k = np.round(ang / (math.pi / 4)) * (math.pi / 4)        # 8 rays
    off = np.abs(ang - k)
    half = 0.21 * (1 - (rho - 0.56) / 0.44)                  # each ray tapers from 0.21 rad to a point
    return (rho >= 0.56) & (rho <= 1.0) & (off <= np.clip(half, 0, None) + 0.05)


def _sun_disc(U, V):
    return disc(U, V, SUN_C[0], SUN_C[1], SUN_R)


def _sun(U, V):
    return _sun_rays(U, V) | _sun_disc(U, V)


def _moon(U, V):
    return disc(U, V, -0.14, 1.68, 0.58) & ~disc(U, V, 0.14, 1.88, 0.48)


STARS = ((0.56, 1.10, 0.30), (0.50, 2.34, 0.25), (-0.56, 0.72, 0.19), (-0.52, 2.62, 0.15))
DOTS = ((0.08, 0.62), (0.78, 1.66), (-0.82, 1.18), (0.12, 2.68), (-0.28, 2.32), (0.86, 0.72))


def _stars(U, V):
    out = np.zeros(np.broadcast(U, V).shape, bool)
    for s in STARS:
        out |= star4(U, V, *s)
    return out


def _night(U, V):
    return _moon(U, V) | _stars(U, V)


EGGS = {
    # rarity: (shell, light, edge, picture fn, [(key, fn, neon?)] painted in order on the raised picture)
    "common": ("ComShell", "ComShellLight", "ComEdge", _cloud,
               [("ComCloud", _cloud, False)]),
    "uncommon": ("UncShell", "UncShellLight", "UncEdge", _uncommon,
                 [("UncSwirl", _breeze, False), ("UncLeaf", _leaf, False), ("UncVein", _leaf_vein, False)]),
    "rare": ("RarShell", "RarShellLight", "RarEdge", _rain,
             [("RarDrop", _rain, False), ("RarShine", _rain_shine, False)]),
    "epic": ("EpiShell", "EpiShellLight", "EpiEdge", _bolt,
             [("EpiBolt", _bolt, True)]),
    "legendary": ("LegShell", "LegShellLight", "LegEdge", _sun,
                  [("LegRay", _sun_rays, False), ("LegSun", _sun_disc, True)]),
    "mythic": ("MytShell", "MytShellLight", "MytEdge", None, None),
    "secret": ("SecShell", "SecShellLight", "SecEdge", _night,
               [("SecMoon", _moon, True), ("SecStar", _stars, True)]),
}
AURORA = (("MytTeal", 0.98, 0.0), ("MytGreen", 1.52, 1.3), ("MytViolet", 2.06, 2.4))   # key, height, wave phase


@prop("lobby_egg")
def lobby_egg(entry, kit):
    a = entry.get("args") or {}
    rarity = a["rarity"]
    shell, light, edge, pic, layers = EGGS[rarity]
    K = float(a.get("K", 8.0))
    S = ShopSculpt(kit, K, 1.75, origin=(0.0, EGG_H / 2, 0.0), name="egg")
    vs = S.vs
    X, Y, Z = S.X, S.Y, S.Z
    rr = np.sqrt(X * X + Z * Z)
    inside = rr <= egg_r(Y)
    raised = (rr <= egg_r(Y, vs)) & (Y > vs) & (Y < EGG_H - vs)
    S.put(shell, inside)
    # a soft sheen: the shell's light tone on the upper third, dithered into the base at its edge
    t = (Y - EGG_H / 2) / (EGG_H / 2)
    dith = ((np.floor(X / vs) + np.floor(Y / vs) + np.floor(Z / vs)) % 2 == 0)
    S.put(light, inside & ((t > 0.62) | ((t > 0.5) & dith)))
    front = (Z < 0) & (np.abs(Z) >= 0.55 * rr)
    back = (Z > 0) & (np.abs(Z) >= 0.55 * rr)
    Y2 = Y + 0 * X                                               # (n, n, 1) picture-plane arrays
    Uf, Ub = -X + 0 * Y, X + 0 * Y
    od = 1.25 * vs                                               # outline width
    if rarity == "mythic":
        # aurora bands right round the egg: v wave around the angle; outlines between and round them
        phi = np.arctan2(X, -Z)
        for key, h, ph in AURORA:
            c = h + 0.16 * np.sin(2 * phi + ph)
            band = np.abs(Y - c) <= 0.18
            ring = (np.abs(Y - c) > 0.18) & (np.abs(Y - c) <= 0.18 + od)
            S.put(edge, inside & ring, only=(shell, light))
            S.glow(key, raised & band)
    else:
        for side, U in ((front, Uf), (back, Ub)):
            S.put(edge, inside & side & outline(pic, U, Y2, od), only=(shell, light))
            for key, fn, neon in layers:
                m = raised & side & fn(U, Y2)
                if neon:
                    S.glow(key, m)
                else:
                    S.put(key, m)
            if rarity == "common":
                # the cloud's underside a touch darker (it reads as a puff, not a sticker)
                S.put("ComCloudShade", raised & side & _cloud(U, Y2) & ~_cloud(U, Y2 - 2 * vs), only="ComCloud")
            if rarity == "secret":
                for (du, dv) in DOTS:
                    S.put("SecDot", inside & side & (np.abs(U - du) < vs) & (np.abs(Y2 - dv) < vs), only=(shell, light))
    if rarity == "secret":
        # the violet glow: a night horizon at the bottom (dusk dithered into the shell)
        S.put("SecDusk", inside & ((t < -0.38) | ((t < -0.26) & dith)), only=(shell, light))
        S.put("SecViolet", inside & ((t < -0.66) | ((t < -0.55) & dith)), only=(shell, light, "SecDusk"))
    m = kit.model(entry["key"], "prop", vs=vs, K=K)
    S.mesh_at(m, "Egg", {})
    finish(m, {"source": "designed (lobby-shop pitch egglook C): the %s rarity egg, sky-weather picture" % rarity,
               "pivot": "bottom centre, front -Z", "rarity": rarity})
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
