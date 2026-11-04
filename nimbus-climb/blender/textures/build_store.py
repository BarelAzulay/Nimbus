"""Card art of the Robux Store, the daily gifts and the Sky Trove (spec docs/superpowers/specs/
2026-11-04-shop-retention-design.md section 9 "Art list", the card look of 5.1 / 8: saturated, glossy, thick dark
outlines).

    blender.exe -b --python-expr "import sys, runpy; sys.argv=['blender/textures/build_store.py']; \
        runpy.run_path('blender/textures/build_store.py', run_name='__main__')"
    ... sys.argv=['blender/textures/build_store.py', '--key', 'store_pro', '--sheet', 'x.png']   (one key + a sheet)
    (PYTHONPATH must hold the kit's lupa + Pillow, e.g. %LOCALAPPDATA%/NimbusClimb/bpydeps; README "Build")

Every picture is a Cycles render of Blender geometry made here from the mesh kit: the game's own pets through the
bridge (kit/petkit.py: storm_tabby; the Crown Phoenix = ember_phoenix's rig + the Crown accessory in gold / white;
the Week Wisp = sleepy_owl's rig in gold / white), the kit's props (token_cloud / token_cash coins, the Sky Trove's
prop_trove_body + prop_trove_lid) and new fine-voxel pieces built below in the kit's style
(nvox grids, kit.mesh shading: light tops, dark undersides, deep creases): gems, cash bundles, potion flasks, a
cushion, a gift box with the Trove sign's bow, the WEEK badge, the "x2" glyphs and the seven flat tab icons.  No
image goes in: no textures, no downloads, nothing generated.

The outline is drawn from the render itself: an id pass (one flat emission colour per placed piece, 1 sample, 2x
size) gives the inner lines where two pieces meet, and the silhouette is dilated into the thick outer line
(Theme.TextStroke navy).  Fully transparent pixels get that navy as RGB so a scaled ImageLabel never shows a light
fringe.  Fixed Cycles seed + sample count, a deterministic PNG writer: the same script gives the same bytes on the
same machine.

Outputs: blender/textures/store/<key>.png (cards 512 x 512, icons 128 x 128, RGBA) and the keys in the uploader
index blender/textures/textures.json (merged: other keys stay as they are; png, displayName, description,
contentHash = the PNG's sha256, structureHash = size + pixel format, as build_vortex.py writes them).  Nothing is
uploaded here: tools/upload_assets.py --textures does that in the keyed session and writes TextureIds.lua.
"""
import hashlib
import json
import math
import os
import struct
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.dirname(HERE)
REPO = os.path.dirname(BLENDER_DIR)
KIT = os.path.join(BLENDER_DIR, "kit")
for p in (KIT, BLENDER_DIR):
    if p not in sys.path:
        sys.path.insert(0, p)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

from nvox import blend as B  # noqa: E402
from nvox import colors as C  # noqa: E402

OUT = os.path.join(HERE, "store")
INDEX = os.path.join(HERE, "textures.json")
SEED = 20261104
CARD = 512
ICON = 128
SAMPLES = 96
ICON_SAMPLES = 48
INK = (16, 22, 50)          # Theme.TextStroke: the outline navy
OUTER_PX = 11               # outer outline width at 512 px
INNER_PX = 3.2              # inner line half width at 512 px (a ~6 px line)
ICON_OUTER_PX = 22          # icons render at 512 and shrink 4x: ~5.5 px at 128

# ------------------------------------------------------------------------------------------------ palette (0..255)
SP = {
    # the Sky Trove's family (props/lobby_trove.py TPAL), reused so the cards match the chest and its sign
    "Gold": (244, 198, 84), "GoldLight": (255, 228, 140), "GoldDark": (210, 152, 58), "GoldDeep": (176, 118, 40),
    "Rose": (234, 120, 146), "RoseDark": (206, 96, 124), "RoseLight": (250, 168, 186),
    "Cream": (246, 234, 210), "Navy": (34, 42, 76), "Ink": (16, 22, 50),
    # currencies (Theme.Palette Cash / Gem, Theme.Neon)
    "Gem": (84, 196, 246), "GemLight": (150, 226, 255), "GemDark": (40, 134, 214), "GemDeep": (30, 92, 178),
    "GemGlow": (214, 246, 255), "GemMid": (58, 166, 238), "GemInk": (26, 70, 150),
    "Bill": (112, 204, 98), "BillLight": (170, 232, 140), "BillDark": (64, 150, 70), "BillInk": (40, 112, 52),
    "Band": (246, 226, 160),
    # potions (x2 Pet XP = Theme.Neon.Purple)
    "Brew": (176, 104, 255), "BrewLight": (214, 166, 255), "BrewDark": (122, 62, 214),
    "BrewDeep": (104, 46, 186), "BrewDeepLight": (156, 96, 240), "BrewDeepDark": (72, 30, 140),
    "Glass": (228, 236, 252), "GlassShade": (190, 204, 236), "Shine": (255, 255, 255),
    "Cork": (176, 120, 76), "CorkDark": (136, 88, 54),
    # VIP cushion
    "Velvet": (132, 64, 206), "VelvetLight": (166, 102, 236), "VelvetDark": (96, 44, 160),
    "Cap": (206, 44, 76), "CapLight": (240, 92, 116),
    "Ruby": (236, 72, 104), "Sapphire": (80, 150, 246), "Emerald": (72, 204, 132),
    # gift box
    "Box": (88, 170, 250), "BoxLight": (140, 202, 255), "BoxDark": (54, 122, 214),
    "White": (250, 252, 255), "Star": (255, 214, 72), "StarLight": (255, 240, 160), "StarDark": (230, 160, 40),
    # icons
    "Bolt": (255, 212, 64), "BoltDark": (240, 150, 40), "Ticket": (255, 196, 64), "TicketDark": (226, 146, 40),
    "Red": (255, 86, 108), "Green": (84, 214, 120), "Blue": (72, 168, 255), "Purple": (176, 104, 255),
    "Orange": (255, 150, 48), "Yellow": (255, 214, 64), "Crate": (150, 104, 226), "CrateDark": (110, 70, 186),
}
NEON = {"Glow": (255, 236, 170), "GlowHot": (255, 248, 220), "GemNeon": (190, 240, 255)}


def kit_props():
    import props
    return props, props.PropKit()


def sculpt(K, extent, name="card"):
    """a fine voxel grid in studs with the store palette (props/lobby_trove.py TroveSculpt: cell-exact boxes)"""
    from props.lobby_trove import TroveSculpt
    _, kit = kit_props()

    class StoreSculpt(TroveSculpt):
        def recipes(self):
            rec = {}
            for k in self.g.keys:
                if k is None:
                    continue
                rec[k] = self.neon[k] if k in self.neon else ["rgb"] + list(SP[k])
            return rec

    S = StoreSculpt(kit, K, extent, name=name)
    for k, c in NEON.items():
        S.neon[k] = ["rgb"] + list(c)
    return S


def model_of(S, key, group="Prop"):
    _, kit = kit_props()
    m = kit.model(key, "prop", vs=S.vs, K=S.K)
    S.mesh_at(m, group, {})
    m.groups, m.attachments, m.meta = {}, {}, {}
    return m


# ------------------------------------------------------------------------------------------------ the kit's pieces
_BRIDGE = []


def bridge():
    if not _BRIDGE:
        from bridge import Bridge
        _BRIDGE.append(Bridge())
    return _BRIDGE[0]


def pet_pieces(pet_id, look=None, k=1.38):
    """body + both wings of a catalog pet (optionally with Look overrides), coloured with the game's own palette for
    that Look (the bridge's PetBuilder palette; empty recipe fit = the exact palette colours).  Pieces in Roblox
    model space: [(ModelSpec, roblox 4x4 or None)]"""
    import petkit
    entry = {"key": "card_" + pet_id, "type": "pet", "pet": pet_id, "k": k, "passes": ["pets:cute"],
             "look": dict(look or {})}
    br = bridge()
    body, bp = petkit.build_pet_body(br, {}, entry, k)
    for name in [n for n, o in body.objects.items() if o.group == "EyeLid"]:   # the blink lids (hidden in game)
        del body.objects[name]
    pieces = [(body, None)]
    for side in ("L", "R"):
        e = dict(entry, key="card_%s_wing%s" % (pet_id, side), side=side)
        try:
            w, _ = petkit.build_pet_wing(br, {}, e, k)
        except KeyError:
            continue
        a = body.attachments.get("Wing" + side)
        pieces.append((w, B.cf_to_bl(a["rot"], a["pos"]) if a else None))
    return pieces


def prop_piece(name, key, args=None):
    props, kit = kit_props()
    reg = props.load_all()
    m = reg[name]({"key": key, "type": "prop", "prop": name, "args": args or {}}, kit)
    return m


# ------------------------------------------------------------------------------------------------ new voxel pieces
def gem_model(key="card_gem", K=10.0, R=1.0, hc=0.5, rt=0.56, hp=1.05):
    """a cut gem: an octagonal crown (table + 8 facets alternating light / mid) on a girdle and a pavilion of 8
    facets (mid / dark) to the culet; Theme Gem blue.  Girdle at y 0, centred."""
    S = sculpt(K, R + 0.3, "gem")
    X, Y, Z = S.X, S.Y, S.Z
    ang = np.arctan2(Z, X)
    sector = np.floor((ang + math.pi / 8) / (math.pi / 4)).astype(np.int64) % 8
    cen = sector * (math.pi / 4)
    r_oct = X * np.cos(cen) + Z * np.sin(cen)
    crown = (Y >= 0) & (Y <= hc) & (r_oct <= R - (R - rt) * np.clip(Y / hc, 0, 1))
    pav = (Y < 0) & (Y >= -hp) & (r_oct <= R * (1 + Y / hp))
    odd = (sector % 2) == 1
    # saturated Theme Gem blue: crown facets Gem / GemMid, pavilion GemDark / GemDeep, a pale table with one
    # sparkle, a light girdle line (round 2 had far too much white: it read as ice)
    S.put("GemDark", pav & ~odd)
    S.put("GemDeep", pav & odd)
    S.put("GemInk", pav & (Y < -hp * 0.7))
    S.put("Gem", crown & ~odd)
    S.put("GemMid", crown & odd)
    S.put("GemLight", crown & (Y > hc - 1.5 / K))
    S.put("Gem", crown & (Y > hc - 1.5 / K) & (r_oct > rt - 1.6 / K))
    S.put("GemGlow", crown & (Y > hc - 1.5 / K) & (np.abs(X + 0.18) < 1.2 / K) & (np.abs(Z + 0.18) < 1.2 / K))
    S.put("GemLight", (crown | pav) & (Y >= -0.6 / K) & (Y < 0.6 / K) & (r_oct > R - 1.5 / K))   # the girdle line
    S.flat.update(["Gem", "GemMid", "GemDark", "GemDeep", "GemInk", "GemLight", "GemGlow"])
    return model_of(S, key)


def bills_model(key="card_bills"):
    """a cash bundle: a stack of green bills (paper layers on the sides), a cream band, a "$" on the top bill"""
    K = 8.0
    S = sculpt(K, 1.9, "bills")
    X, Y, Z = S.X, S.Y, S.Z
    W, H, D = 1.75, 0.62, 0.9
    body = (np.abs(X) < W) & (Y > 0) & (Y < H) & (np.abs(Z) < D)
    S.put("Bill", body)
    layer = (np.floor(Y * K).astype(np.int64) % 2 == 0)
    side = body & ((np.abs(X) > W - 1.0 / K) | (np.abs(Z) > D - 1.0 / K))
    S.put("BillLight", side & layer & (Y < H - 1.0 / K))
    top = body & (Y > H - 1.0 / K)
    S.put("BillLight", top & ((np.abs(X) > W - 2.0 / K) | (np.abs(Z) > D - 2.0 / K)))
    S.put("Band", (np.abs(X) < 0.32) & (Y > -0.01) & (Y < H + 1.0 / K) & (np.abs(Z) < D + 1.0 / K))
    # a "$" on the top bill, beside the band, raised one cell (5 x 7 cells)
    dollar = ("..1..", ".1111", "1.1..", ".111.", "..1.1", "1111.", "..1..")
    for r, row in enumerate(dollar):
        for c, ch in enumerate(row):
            if ch != "1":
                continue
            x = 1.05 - (c - 2) / K
            z = (3 - r) / K
            S.put("BillInk", S.B(x - 0.5 / K, x + 0.5 / K, H - 0.01, H + 1.0 / K, z - 0.5 / K, z + 0.5 / K))
    return model_of(S, key)


def potion_model(key, big=False):
    """a round potion flask: purple brew (3 h: deeper purple, a gold cap band) under clear glass, a white shine, a
    neck, a lip and a cork"""
    K = 10.0 if not big else 9.0
    r = 1.0 if not big else 1.25
    S = sculpt(K, r + 1.6, "potion")
    X, Y, Z = S.X, S.Y, S.Z
    cy = r
    ball = (X ** 2 + (Y - cy) ** 2 + Z ** 2) <= r * r
    nr = 0.36 * r
    neck = (X ** 2 + Z ** 2 <= nr * nr) & (Y > cy + 0.6 * r) & (Y < cy + 1.42 * r)
    lip = (X ** 2 + Z ** 2 <= (nr + 1.6 / K) ** 2) & (Y > cy + 1.3 * r) & (Y < cy + 1.48 * r)
    cork = (X ** 2 + Z ** 2 <= (nr - 0.8 / K) ** 2) & (Y > cy + 1.4 * r) & (Y < cy + 1.85 * r)
    base, light, dark = ("BrewDeep", "BrewDeepLight", "BrewDeepDark") if big else ("Brew", "BrewLight", "BrewDark")
    level = cy + 0.28 * r
    S.put("Glass", ball | neck)
    S.put("GlassShade", (ball | neck) & (Z > 0.2 * r) & (X > 0.25 * r))
    S.put(base, ball & (Y < level))
    S.put(light, ball & (Y < level) & (Y > level - 1.6 / K))
    S.put(dark, ball & (Y < cy - 0.55 * r))
    # bubbles in the brew (fixed spots)
    for (bx, by, bs) in ((-0.32, 0.92, 1.4), (0.18, 0.62, 1.0), (-0.05, 1.05, 0.9), (0.38, 1.0, 0.8)):
        S.put(light, ((X - bx * r) ** 2 + (Y - by * r) ** 2 + (Z + 0.9 * r) ** 2) <= (bs * 1.2 / K) ** 2, only=base)
    # the shine: a curved streak on the upper left of the glass, front
    sh = ball & (Z < -0.3 * r) & (X > 0.25 * r) & (X < 0.55 * r) & (Y > cy + 0.15 * r) & (Y < cy + 0.62 * r)
    S.put("Shine", sh)
    S.put("Shine", ball & (Z < -0.3 * r) & (np.abs(X - 0.62 * r) < 1.0 / K) & (np.abs(Y - cy + 0.05 * r) < 1.0 / K))
    S.put("Glass", lip)
    if big:
        S.put("Gold", lip)
    S.put("Cork", cork)
    S.put("CorkDark", cork & (Y > cy + 1.78 * r))
    S.flat.update(["Shine"])
    return model_of(S, key)


def cushion_model(key="card_cushion"):
    """a plump velvet cushion: a rounded slab, a tufted gold button in the middle, gold piping, gold tassels"""
    K = 8.0
    S = sculpt(K, 2.6, "cushion")
    X, Y, Z = S.X, S.Y, S.Z
    W, H = 2.0, 0.75
    rad = np.maximum(np.abs(X), np.abs(Z))
    soft = (np.abs(X) ** 4 + np.abs(Z) ** 4) ** 0.25
    top = H * (1.0 - 0.32 * (soft / W) ** 2)          # puffy: high in the middle, low at the edges
    body = (soft < W) & (Y > 0) & (Y < top)
    S.put("Velvet", body)
    S.put("VelvetLight", body & (Y > top - 1.5 / K) & (soft < W * 0.7))
    S.put("VelvetDark", body & (Y < 0.22))
    # the tuft dimple + gold button
    S.cut((X ** 2 + Z ** 2 < 0.18) & (Y > top - 2.0 / K))
    S.put("Gold", (X ** 2 + Z ** 2 < 0.06) & (Y > top - 2.5 / K) & (Y < top - 0.5 / K))
    # gold piping around the seam
    pipe = (np.abs(soft - (W - 0.5 / K)) < 0.9 / K) & (np.abs(Y - 0.3) < 1.0 / K)
    S.put("Gold", pipe)
    # tassels at the four corners
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = sx * W * 0.80, sz * W * 0.80
            d = np.sqrt((X - cx) ** 2 + (Z - cz) ** 2)
            S.put("Gold", (d < 0.17) & (Y > 0.12) & (Y < 0.42))
            # the tassel skirt widens downwards
            S.put("GoldDark", (Y > -0.35) & (Y < 0.14) & (d < 0.12 + 0.2 * np.clip((0.14 - Y) / 0.5, 0, 1)))
    return model_of(S, key)


def crown_model(key="card_crown"):
    """the VIP crown: a gold band (light top lip, dark foot), five points with gold balls, a ruby / sapphire /
    emerald on the band, a purple velvet cap inside"""
    K = 10.0
    S = sculpt(K, 1.9, "crown")
    X, Y, Z = S.X, S.Y, S.Z
    rho = np.sqrt(X ** 2 + Z ** 2)
    th = np.arctan2(X, -Z)                       # 0 = the front (-Z)
    Ro, Ri, Hb = 1.35, 1.08, 0.7
    shell = (rho < Ro) & (rho > Ri)
    S.put("Gold", shell & (Y > 0) & (Y < Hb))
    S.put("GoldDark", shell & (Y > 0) & (Y < 1.5 / K))
    S.put("GoldLight", shell & (Y > Hb - 1.5 / K) & (Y < Hb))
    seg = 2 * math.pi / 5
    a = np.abs(np.mod(th + seg / 2, seg) - seg / 2) / (seg / 2)        # 0 at a point, 1 in a valley
    S.put("Gold", shell & (Y >= Hb) & (Y < Hb + 0.95 * (1 - a)))
    S.put("GoldLight", shell & (Y >= Hb) & (Y < Hb + 0.95 * (1 - a)) & (rho > Ro - 1.2 / K) & (a < 0.25))
    for k in range(5):
        t = k * seg
        bx, bz = math.sin(t) * (Ro + Ri) / 2, -math.cos(t) * (Ro + Ri) / 2
        S.put("GoldLight", ((X - bx) ** 2 + (Y - Hb - 1.05) ** 2 + (Z - bz) ** 2) < 0.19 ** 2)
    for t, gem in ((0.0, "Ruby"), (seg, "Sapphire"), (-seg, "Emerald"), (2 * seg, "Sapphire"), (-2 * seg, "Emerald")):
        gx, gz = math.sin(t) * Ro, -math.cos(t) * Ro
        S.put(gem, ((X - gx) ** 2 + (Y - Hb / 2) ** 2 + (Z - gz) ** 2) < 0.2 ** 2)
    cap = (rho <= Ri) & (Y > 0.2) & (Y < 0.2 + 0.85 * np.sqrt(np.clip(1 - (rho / Ri) ** 2, 0, 1)) + 0.25)
    S.put("Cap", cap)
    S.put("CapLight", cap & (Y > 0.95))
    return model_of(S, key)


BOW = ("XXX....XXX", "XkXXkkXXkX", "XXXXkkXXXX", "XXX....XXX")   # the Trove sign's bow (props/lobby_trove.py)


def gift_box_model(key, part):
    """a gift box (blue paper, a rose ribbon cross) made of two pieces: part "box" (the open-topped box with its
    glow inside) or "lid" (the lid with the ribbon and the Trove sign's rose bow: the same pixel bow, 0.25-stud
    cells, standing on the lid like the sign's cap)"""
    K = 8.0
    S = sculpt(K, 2.4, "gift_" + part)
    X, Y, Z = S.X, S.Y, S.Z
    W, H = 1.6, 2.6
    rw = 0.36
    if part == "box":
        body = (np.abs(X) < W) & (Y > 0) & (Y < H) & (np.abs(Z) < W)
        S.put("Box", body)
        S.put("BoxLight", body & ((np.floor((X + Z) * 1.6).astype(np.int64) % 3) == 0) & (Y > 0.25))   # paper dots
        S.put("BoxDark", body & (Y < 0.25))
        S.put("Rose", body & ((np.abs(X) < rw) | (np.abs(Z) < rw)))
        S.put("RoseDark", body & ((np.abs(np.abs(X) - rw) < 0.6 / K) | (np.abs(np.abs(Z) - rw) < 0.6 / K))
              & ((np.abs(X) < rw + 0.1) | (np.abs(Z) < rw + 0.1)) & (Y > 0.25), only="Rose")
        inside = (np.abs(X) < W - 0.25) & (np.abs(Z) < W - 0.25) & (Y > 0.5)
        S.cut(inside)
        S.put("Glow", (np.abs(X) < W - 0.25) & (np.abs(Z) < W - 0.25) & (Y > 0.5) & (Y < 0.5 + 1.0 / K))
        S.put("GlowHot", (X ** 2 + Z ** 2 < 0.8) & (Y > 0.5) & (Y < 0.5 + 1.0 / K))
    else:
        lw, lh = W + 0.22, 0.6
        lid = (np.abs(X) < lw) & (Y > 0) & (Y < lh) & (np.abs(Z) < lw)
        S.put("Box", lid)
        S.put("BoxLight", lid & (Y > lh - 1.0 / K))
        S.put("BoxDark", lid & (Y < 1.0 / K))
        S.put("Rose", lid & ((np.abs(X) < rw) | (np.abs(Z) < rw)))
        # the bow: the sign's pixel bow (0.25-stud cells, here 2 x 2 voxels each) standing on the lid, 3 cells deep
        cw = 0.25
        for r, row in enumerate(BOW):
            for c, ch in enumerate(row):
                if ch == ".":
                    continue
                x0 = (c - 5) * cw * 1.25
                y0 = lh + r * cw * 1.25
                S.put("Rose" if ch == "X" else "RoseDark",
                      S.B(x0, x0 + cw * 1.25, y0, y0 + cw * 1.25, -0.4, 0.4))
        S.put("RoseLight", S.B(-1.6, 1.6, lh + 3 * cw * 1.25, lh + 4 * cw * 1.25, -0.4, 0.4), only="Rose")
        # the tails: two ribbon ends hanging off the knot over the front
        for sx in (-1, 1):
            for i in range(5):
                x = sx * (0.2 + 0.11 * i)
                S.put("Rose", S.B(min(x, x + sx * 0.2), max(x, x + sx * 0.2), lh - 0.02 - 0.0 * i, lh + 0.14,
                                  -0.42 - 0.12 * i, -0.3 - 0.12 * i))
    return model_of(S, key)


def star_model(key, palette=("Star", "StarLight", "StarDark"), K=8.0, R=1.0, depth=0.34, points=5, inner=0.5):
    """a chunky puffed 5-point star facing -Z (front), light on its upper half, a rounded bulge"""
    S = sculpt(K, R + 0.3, "star")
    X, Y, Z = S.X, S.Y, S.Z
    ang = np.arctan2(X, Y)  # 0 = up
    seg = math.pi / points
    a = np.mod(ang + seg, 2 * seg) - seg
    # star polygon radius at this angle: linear between tip (R) and valley (inner R)
    t = np.abs(a) / seg
    rr = 1.0 / ((1 - t) / R + t / (R * inner))
    rho = np.sqrt(X ** 2 + Y ** 2)
    edge = np.clip(1 - rho / np.maximum(rr, 1e-6), 0, 1)
    th = depth * (0.35 + 0.65 * np.sqrt(edge))
    body = (rho < rr) & (np.abs(Z) < th)
    base, light, dark = palette
    S.put(base, body)
    S.put(light, body & (Y > 0.05) & (X > -0.1) & (Z < 0))
    S.put(dark, body & (Y < -0.35 * R))
    return model_of(S, key)


# pixel glyphs (rows top -> bottom; one char = one pixel; '.' empty)
X2_X = ("11...11", "111.111", ".11111.", "..111..", ".11111.", "111.111", "11...11")
X2_2 = (".11111.", "1111111", "11...11", ".....11", "....111", "..1111.", ".111...", "111....", "1111111",
        "1111111")
WEEK = {"W": ("1...1", "1...1", "1.1.1", "11.11", "1...1"), "E": ("111", "1..", "11.", "1..", "111"),
        "K": ("1.1", "1.1", "11.", "1.1", "1.1")}


def glyph_model(key, layers, K, depth, px=1.0, shade=True, flat=()):
    """pixel art as voxels: layers = [(rows, {char: palette key}, (x0, y0) pixel offset, z0, depth)], one pixel =
    px studs square (K voxels per stud), extruded towards +Z from z0 (front faces -Z, seen from the front +X is the
    viewer's LEFT, so columns run towards -X)"""
    w = max(len(r[0][0]) + r[2][0] for r in layers)
    h = max(len(r[0]) + r[2][1] for r in layers)
    S = sculpt(K, max(w, h) * px / 2 + depth + 1.0, "glyph")
    for rows, cmap, (ox, oy), z0, d in layers:
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                if ch == "." or ch not in cmap:
                    continue
                x = -((c + ox) - w / 2.0) * px
                y = ((h - 1 - (r + oy)) - h / 2.0) * px
                S.put(cmap[ch], S.B(x - px, x, y, y + px, z0, z0 + d))
    S.flat.update(flat)
    if not shade:
        S.flat.update(k for k in S.g.keys if k)
    return model_of(S, key)


def text_layers(text_glyphs, gap=1):
    """[(rows)] side by side, bottoms aligned -> one rows block"""
    h = max(len(g) for g in text_glyphs)
    out = [""] * h
    for i, g in enumerate(text_glyphs):
        pad = h - len(g)
        w = len(g[0])
        for r in range(h):
            row = g[r - pad] if r >= pad else "." * w
            out[r] += row + ("." * gap if i < len(text_glyphs) - 1 else "")
    return tuple(out)


def x2_model(key, fill="White", edge="Navy"):
    rows = text_layers([X2_X, X2_2], gap=1)
    return glyph_model(key, [(rows, {"1": fill}, (0, 0), -0.5, 1.0)], K=4.0, depth=1.0, px=0.5)


def badge_model(key="card_week_badge"):
    """the WEEK badge: a gold medallion (a stepped rim, a sunburst ring of studs), a cream field with WEEK in raised
    navy letters, a small gold star over them"""
    K = 10.0
    S = sculpt(K, 2.8, "badge")
    X, Y, Z = S.X, S.Y, S.Z
    rho = np.sqrt(X ** 2 + Y ** 2)
    R = 2.5
    disc = (rho < R) & (Z > -0.25) & (Z < 0.25)
    S.put("Gold", disc)
    S.put("GoldDark", disc & (rho > R - 1.5 / K))
    S.put("GoldLight", (rho < R - 0.18) & (rho > R - 0.42) & (Z > -0.35) & (Z < 0.25))
    ang = np.arctan2(Y, X)
    studs = (np.abs(rho - (R - 0.3)) < 0.1) & (np.mod(ang * 16 / math.pi, 2) < 1.0) & (Z > -0.42) & (Z < 0)
    S.put("GoldLight", studs)
    S.cut((rho < R - 0.55) & (Z < -0.1))
    S.put("Cream", (rho < R - 0.55) & (Z >= -0.1) & (Z < 0.25))
    S.put("GoldDark", (np.abs(rho - (R - 0.55)) < 0.6 / K) & (Z >= -0.2) & (Z < 0.25))
    # WEEK, 2 x 2 voxels per pixel, raised 2 voxels
    rows = text_layers([WEEK["W"], WEEK["E"], WEEK["E"], WEEK["K"]], gap=1)
    pw = 0.2
    w, h = len(rows[0]), len(rows)
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch != "1":
                continue
            x = -(c - w / 2.0) * pw
            y = (h - 1 - r - h / 2.0) * pw - 0.25
            S.put("Navy", S.B(x - pw, x, y, y + pw, -0.32, -0.05))
    # a small star above the word
    ang2 = np.arctan2(X, Y - 0.95)
    seg = math.pi / 5
    a = np.mod(ang2 + seg, 2 * seg) - seg
    t = np.abs(a) / seg
    rr = 1.0 / ((1 - t) / 0.42 + t / 0.2)
    S.put("Gold", (np.sqrt(X ** 2 + (Y - 0.95) ** 2) < rr) & (Z > -0.32) & (Z < -0.05))
    return model_of(S, key)


def ribbon_tails_model(key="card_ribbon_tails"):
    """two rose ribbon tails hanging from behind the badge, notched ends"""
    K = 8.0
    S = sculpt(K, 2.6, "tails")
    X, Y, Z = S.X, S.Y, S.Z
    for sx in (-1, 1):
        # a slanted strip from (sx*0.5, 0) down to (sx*1.4, -2.2)
        u = (Y - 0.0) / -2.2
        cx = sx * (0.5 + 0.9 * u)
        strip = (u > 0) & (u < 1) & (np.abs(X - cx) < 0.42) & (Z > 0.0) & (Z < 0.25)
        notch = (u > 0.82) & (np.abs(X - cx) < 0.42 * (u - 0.82) / 0.18)
        S.put("Rose", strip & ~notch)
        S.put("RoseDark", strip & ~notch & (np.abs(X - cx) > 0.3))
    return model_of(S, key)


# ------------------------------------------------------------------------------------------------ icons (pixel art)
ICONS = {
    # 16 x 16; one char per pixel
    "icon_tab_packs": ((
        "................",
        "......SS........",
        ".....SLLS.......",
        "..ccccSScccccc..",
        ".cCCCCCCCCCCCCc.",
        ".cCCCCCSSCCCCCc.",
        ".cCCCCSLLSCCCCc.",
        ".cCCCSLLLLSCCCc.",
        ".cCSSLLLLLLSSCc.",
        ".cCCSLLLLLLSCCc.",
        ".cCCCSLLLLSCCCc.",
        ".cCCCSLSSLSCCCc.",
        ".cCCCSSCCSSCCCc.",
        ".cCCCCCCCCCCCCc.",
        ".cdddddddddddc..",
        "................"), {"C": "Crate", "c": "CrateDark", "d": "CrateDark", "S": "StarDark", "L": "Star"}),
    "icon_tab_passes": ((
        "................",
        "................",
        "..TTTTTTTTTTTT..",
        ".TTTTTTTTTTTTTT.",
        ".TTTT.TTTTTTTTT.",
        "TTTTT.TTTTTTTTTT",
        ".TTTTTTTTSSTTTT.",
        "..TTT.TTSLLSTT..",
        "..TTTTTSLLLLST..",
        ".TTTT.TTSLLSTTT.",
        "TTTTTTTTTSSTTTTT",
        ".TTTT.TTTTTTTTT.",
        ".TTTTTTTTTTTTTT.",
        "..dddddddddddd..",
        "................",
        "................"), {"T": "Ticket", "d": "TicketDark", "S": "Rose", "L": "RoseLight"}),
    "icon_tab_boosts": ((
        "................",
        ".........YYYY...",
        "........YYYYY...",
        ".......YYYYY....",
        "......YYYYY.....",
        ".....YYYYY......",
        "....YYYYYYYYYY..",
        "...YYYYYYYYYYY..",
        "...OOOOOOOYYY...",
        ".........YYY....",
        "........YYY.....",
        ".......YYO......",
        "......YYO.......",
        ".....YOO........",
        ".....OO.........",
        "................"), {"Y": "Bolt", "O": "BoltDark"}),
    "icon_tab_currency": ((
        "................",
        "................",
        "....GGGGGGGG....",
        "...GLLGLLGLLG...",
        "..GLLLGLLGLLLG..",
        ".GGGGGGGGGGGGGG.",
        ".DGGGDGGGGDGGGD.",
        "..DGGDGGGGDGGD..",
        "...DGGDGGDGGD...",
        "....DGDGGDGD....",
        ".....DGDDGD.....",
        "......DGGD......",
        ".......DD.......",
        "................",
        "................",
        "................"), {"G": "Gem", "L": "GemGlow", "D": "GemDark"}),
    "icon_tab_roulettes": None,   # procedural wheel below
    "icon_gifts": ((
        "................",
        "...RRR....RRR...",
        "..RLLRR..RRLLR..",
        "..RLLRRrrRRLLR..",
        "...RRRRrrRRRR...",
        ".BBBBBBRRBBBBBB.",
        ".BBBBBBRRBBBBBB.",
        ".bbbbbbRRbbbbbb.",
        "..BBBBBRRBBBBB..",
        "..BBBBBRRBBBBB..",
        "..BBBBBRRBBBBB..",
        "..BBBBBRRBBBBB..",
        "..BBBBBRRBBBBB..",
        "..bbbbbRRbbbbb..",
        "................",
        "................"), {"B": "Box", "b": "BoxDark", "R": "Rose", "r": "RoseDark", "L": "RoseLight"}),
    "icon_vip_crown": ((
        "................",
        "................",
        ".L......L.....L.",
        ".G.....GLG....G.",
        ".GG...GGGGG..GG.",
        ".GGG.GGGGGGGGGG.",
        ".GGGGGGGGGGGGGG.",
        ".GGGGGGGGGGGGGG.",
        ".GGRRGGSSGGEEGG.",
        ".GGRRGGSSGGEEGG.",
        ".GGGGGGGGGGGGGG.",
        ".dddddddddddddd.",
        ".GGGGGGGGGGGGGG.",
        "................",
        "................",
        "................"), {"G": "Gold", "L": "GoldLight", "d": "GoldDark", "R": "Ruby", "S": "Sapphire",
                              "E": "Emerald"}),
}


def icon_wheel_model(key):
    """the roulette wheel glyph: six coloured wedges, a gold rim and hub, a red pointer on top (pixel voxels)"""
    K = 4.0
    S = sculpt(K, 9.5, "wheel")
    X, Y, Z = S.X, S.Y, S.Z
    rho = np.sqrt(X ** 2 + (Y + 0.5) ** 2)
    ang = np.arctan2(X, Y + 0.5)
    R = 6.6
    disc = (rho < R) & (Z > -0.5) & (Z < 0.5)
    cols = ("Red", "Yellow", "Blue", "Green", "Purple", "Orange")
    wedge = np.floor((ang + math.pi) / (math.pi / 3)).astype(np.int64) % 6
    for i, c in enumerate(cols):
        S.put(c, disc & (wedge == i))
    S.put("Gold", disc & (rho > R - 1.2))
    S.put("Gold", (rho < 1.4) & (Z > -0.9) & (Z < 0.5))
    S.put("GoldLight", (rho < 0.7) & (Z > -0.9) & (Z < 0.5))
    # pointer: a downward triangle above the rim
    tri = (Y > R - 1.6) & (Y < R + 1.6) & (np.abs(X) < (Y - (R - 1.6)) * 0.55) & (Z > -0.9) & (Z < 0.5)
    S.put("Red", tri)
    S.flat.update(cols)
    return model_of(S, key)


# ------------------------------------------------------------------------------------------------ the scene
class Card:
    """one picture: placed pieces (each with an outline id), a framed orthographic camera, Cycles"""

    def __init__(self, key, icon=False):
        self.key = key
        self.icon = icon
        B.reset_scene()
        self.objs = []
        self.next_id = 1

    @staticmethod
    def _bounds(pieces):
        pts = []
        for m, M in pieces:
            for o in m.objects.values():
                if not o.quads:
                    continue
                c = np.concatenate([np.asarray(q[0], float) for q in o.quads]) @ B.PM.T
                if M is not None:
                    c = c @ np.asarray(M)[:3, :3].T + np.asarray(M)[:3, 3]
                pts.append(c)
        a = np.concatenate(pts)
        return a.min(0), a.max(0)

    def place(self, pieces, at=(0, 0, 0), height=None, width=None, scale=None, rot=(0, 0, 0), anchor="bottom",
              same_id=False, glossy=True):
        """pieces in Roblox model space -> world (blender: x right, -y towards the camera, z up).  The pieces'
        bottom-centre (or centre) is put at `at`, scaled to `height` / `width` (blender units), rotated by `rot`
        (degrees, blender XYZ euler, applied about the anchor)"""
        if not isinstance(pieces, list):
            pieces = [(pieces, None)]
        lo, hi = self._bounds(pieces)
        size = hi - lo
        s = scale or (height / size[2] if height else (width / size[0] if width else 1.0))
        piv = (lo + hi) / 2
        if anchor == "bottom":
            piv[2] = lo[2]
        T = Matrix.Translation(Vector(at)) @ Euler([math.radians(v) for v in rot], "XYZ").to_matrix().to_4x4() \
            @ Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-piv).tolist()))
        made = []
        first = self.next_id
        for i, (m, M) in enumerate(pieces):
            mat = np.array(T) @ (np.asarray(M) if M is not None else np.eye(4))
            obs = B.make_objects(m, {}, matrix=mat)
            pid = first if same_id else first + i
            for ob in obs:
                ob["sid"] = pid
                ob["gloss"] = glossy
            made += obs
        self.next_id = first + (1 if same_id else len(pieces))
        self.objs += made
        return made

    # -------------------------------------------------------------- render
    def _materials(self):
        """glossy toy plastic: lower roughness, a clear coat; Neon stays emissive"""
        for mat in bpy.data.materials:
            if not mat.use_nodes:
                continue
            b = mat.node_tree.nodes.get("Principled BSDF")
            if b is None:
                continue
            b.inputs["Roughness"].default_value = 0.42
            try:
                b.inputs["Coat Weight"].default_value = 0.55
                b.inputs["Coat Roughness"].default_value = 0.12
                b.inputs["Specular IOR Level"].default_value = 0.55
            except KeyError:
                pass

    def _frame(self, yaw, pitch, margin_px, res, zoom=1.0):
        sc = bpy.context.scene
        y, p = math.radians(yaw), math.radians(pitch)
        d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))  # towards the camera
        rot = (-d).to_track_quat("-Z", "Y").to_matrix()
        right, up = rot.col[0], rot.col[1]
        pts = []
        for ob in self.objs:
            me = ob.data
            n = len(me.vertices)
            co = np.empty(n * 3, np.float32)
            me.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            Mw = np.array(ob.matrix_world)
            pts.append(co @ Mw[:3, :3].T + Mw[:3, 3])
        P = np.concatenate(pts)
        u = P @ np.array(right)
        v = P @ np.array(up)
        w = P @ np.array(d)
        cu, cv = (u.min() + u.max()) / 2, (v.min() + v.max()) / 2
        ext = max(u.max() - u.min(), v.max() - v.min())
        ortho = ext / (1.0 - 2.0 * margin_px / res) / zoom
        cam_d = bpy.data.cameras.new("Cam")
        cam_d.type = "ORTHO"
        cam_d.ortho_scale = ortho
        cam_d.clip_start = 0.01
        cam_d.clip_end = 1000
        cam = bpy.data.objects.new("Cam", cam_d)
        sc.collection.objects.link(cam)
        centre = Vector(np.array(right) * cu + np.array(up) * cv) + d * float(w.max() + 10)
        cam.location = centre
        cam.rotation_euler = rot.to_euler()
        sc.camera = cam
        return d

    def _lights(self, d, icon):
        sc = bpy.context.scene
        world = bpy.data.worlds.new("W")
        sc.world = world
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1)
        bg.inputs["Strength"].default_value = 0.85 if icon else 0.8

        def sun(name, energy, rx, rz, angle=10):
            L = bpy.data.lights.new(name, "SUN")
            L.energy = energy
            L.angle = math.radians(angle)
            o = bpy.data.objects.new(name, L)
            sc.collection.objects.link(o)
            o.rotation_euler = (math.radians(rx), 0, math.radians(rz))
            return o
        # key from the upper front-left, a cool rim from behind-right (the glossy toy edge), a soft fill
        sun("Key", 3.4 if not icon else 1.6, 48, -38)
        sun("Rim", 2.2 if not icon else 0.8, -62, -150, 6)
        sun("Fill", 0.6, 70, 60, 30)

    def _cycles(self, res, samples):
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = samples
        sc.cycles.seed = SEED
        sc.cycles.use_animated_seed = False
        sc.cycles.use_adaptive_sampling = False
        sc.cycles.use_denoising = True
        try:
            sc.cycles.denoiser = "OPENIMAGEDENOISE"
        except TypeError:
            pass
        sc.cycles.max_bounces = 6
        sc.cycles.transparent_max_bounces = 8
        sc.render.threads_mode = "FIXED"
        sc.render.threads = 8
        sc.render.resolution_x = res
        sc.render.resolution_y = res
        sc.render.resolution_percentage = 100
        sc.render.film_transparent = True
        sc.render.filter_size = 1.5
        sc.render.dither_intensity = 0.0
        sc.render.use_compositing = False
        sc.render.use_sequencer = False
        sc.render.image_settings.file_format = "PNG"
        sc.render.image_settings.color_mode = "RGBA"
        sc.render.image_settings.color_depth = "16"
        sc.render.image_settings.compression = 0
        sc.display_settings.display_device = "sRGB"
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "None"

    @staticmethod
    def _read(path):
        img = bpy.data.images.load(path, check_existing=False)
        w, h = img.size
        buf = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(buf)
        bpy.data.images.remove(img)
        return buf.reshape(h, w, 4)[::-1].copy()   # top row first

    def _id_pass(self, res, tmp):
        """flat emission per placed piece id, 1 sample, no filter -> (h, w) int ids (0 = empty)"""
        sc = bpy.context.scene
        mats = {}
        for ob in self.objs:
            sid = int(ob["sid"])
            m = mats.get(sid)
            if m is None:
                m = bpy.data.materials.new("ID_%d" % sid)
                m.use_nodes = True
                nt = m.node_tree
                for n in list(nt.nodes):
                    nt.nodes.remove(n)
                e = nt.nodes.new("ShaderNodeEmission")
                o = nt.nodes.new("ShaderNodeOutputMaterial")
                r, g = (sid % 12) * 20 / 255.0, (sid // 12) * 20 / 255.0
                e.inputs["Color"].default_value = (C.srgb_to_linear(r), C.srgb_to_linear(g), 0.0, 1.0)
                e.inputs["Strength"].default_value = 1.0
                nt.links.new(e.outputs[0], o.inputs[0])
                mats[sid] = m
            ob.data.materials.clear()
            ob.data.materials.append(m)
        sc.cycles.samples = 1
        sc.cycles.use_denoising = False
        sc.render.filter_size = 0.01
        sc.cycles.max_bounces = 0
        sc.render.resolution_x = sc.render.resolution_y = res
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        px = self._read(tmp)
        os.remove(tmp)
        srgb = np.round(px[..., :3] * 255.0 / 20.0)
        ids = (srgb[..., 0] + 12 * srgb[..., 1]).astype(np.int64)
        ids[px[..., 3] < 0.5] = 0
        return ids

    def render(self, yaw=-28, pitch=16, res=None, samples=None, exposure=0.0, zoom=1.0):
        icon = self.icon
        res = res or (512 if icon else CARD)
        outer = ICON_OUTER_PX if icon else OUTER_PX
        samples = samples or (ICON_SAMPLES if icon else SAMPLES)
        self._materials()
        d = self._frame(yaw, pitch, outer + (16 if icon else 6), res, zoom)   # icons: ~4 px of air at 128
        self._lights(d, icon)
        self._cycles(res, samples)
        bpy.context.scene.view_settings.exposure = exposure
        os.makedirs(OUT, exist_ok=True)
        tmp = os.path.join(OUT, "_render_%s.png" % self.key)
        bpy.context.scene.render.filepath = tmp
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        base = self._read(tmp)
        os.remove(tmp)
        ids = self._id_pass(res * 2, tmp)
        rgba = compose(base, ids, outer, INNER_PX * (4 if icon else 1))
        if icon:
            rgba = shrink(rgba, res // ICON)
        rgba8 = finish(rgba)
        path = os.path.join(OUT, self.key + ".png")
        write_png(path, rgba8)
        return path, time.time() - t0


# ------------------------------------------------------------------------------------------------ 2-D post (numpy)
def _disc_max(a, r):
    """anti-aliased dilation of a (h, w) 0..1 map by a disc of radius r px"""
    out = a.copy()
    R = int(math.ceil(r + 1))
    h, w = a.shape
    pad = np.pad(a, R)
    for dy in range(-R, R + 1):
        for dx in range(-R, R + 1):
            dist = math.hypot(dx, dy)
            wgt = min(1.0, max(0.0, r + 0.5 - dist))
            if wgt <= 0 or (dx == 0 and dy == 0):
                continue
            sh = pad[R + dy:R + dy + h, R + dx:R + dx + w]
            np.maximum(out, sh * wgt, out=out)
    return out


def compose(base, ids, outer_px, inner_px):
    """base (h, w, 4) straight alpha 0..1, ids (2h, 2w): inner lines where two piece ids meet, the thick outer
    line around the whole silhouette, all in INK"""
    ink = np.array(INK, np.float32) / 255.0
    # inner lines, found at 2x and shrunk (anti-aliased)
    e = np.zeros(ids.shape, bool)
    a, b = ids[:, 1:], ids[:, :-1]
    m = (a != b) & (a > 0) & (b > 0)
    e[:, 1:] |= m
    e[:, :-1] |= m
    a, b = ids[1:, :], ids[:-1, :]
    m = (a != b) & (a > 0) & (b > 0)
    e[1:, :] |= m
    e[:-1, :] |= m
    line = _disc_max(e.astype(np.float32), inner_px * 2 - 1)
    h, w = base.shape[:2]
    line = line.reshape(h, 2, w, 2).mean(axis=(1, 3))
    rgb, al = base[..., :3], base[..., 3]
    line = line * al
    rgb = rgb * (1 - line[..., None]) + ink * line[..., None]
    # the outer line under everything
    ring = _disc_max(np.clip(al, 0, 1), outer_px)
    A = al + ring * (1 - al)
    out_rgb = (rgb * al[..., None] + ink * (ring * (1 - al))[..., None]) / np.maximum(A, 1e-6)[..., None]
    return np.concatenate([out_rgb, A[..., None]], axis=2)


def shrink(rgba, f):
    """box-filter down by f (premultiplied)"""
    h, w = rgba.shape[:2]
    pm = rgba.copy()
    pm[..., :3] *= pm[..., 3:4]
    pm = pm.reshape(h // f, f, w // f, f, 4).mean(axis=(1, 3))
    a = pm[..., 3:4]
    pm[..., :3] = pm[..., :3] / np.maximum(a, 1e-6)
    return pm


def finish(rgba):
    a8 = np.round(np.clip(rgba, 0, 1) * 255.0).astype(np.uint8)
    clear = a8[..., 3] == 0
    a8[clear, 0], a8[clear, 1], a8[clear, 2] = INK
    return np.ascontiguousarray(a8)


def write_png(path, rgba):
    h, w, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


# ------------------------------------------------------------------------------------------------ the cards
GOLD_LOOK = {"Primary": [246, 196, 72], "Secondary": [255, 248, 232], "Eye": [92, 52, 20],
             "WingColor": [255, 214, 100]}
CARDS = {}


def card(key, desc):
    def deco(fn):
        CARDS[key] = (fn, desc)
        return fn
    return deco


def coin_dims(coin):
    """(thickness, diameter) of a kit coin standing on its edge (faces local +-X)"""
    lo, hi = Card._bounds([(coin, None)])
    size = hi - lo
    return float(size[0]), float(size[2])


def coin_lay(c, coin, at, diam, spin=0.0, tilt=90.0):
    """one coin lying flat (tilt 90) or leaning (tilt < 90), `diam` across"""
    thick, d0 = coin_dims(coin)
    s = diam / d0
    lift = 0.5 * (thick * math.sin(math.radians(tilt)) + d0 * math.cos(math.radians(tilt))) * s
    c.place(coin, at=(at[0], at[1], at[2] + lift), scale=s, anchor="center", rot=(0, tilt, spin))


def coin_stack(c, n, at, coin, diam, spin=0.0):
    """n coins lying flat in a slightly jittered stack (each its own outline piece), `diam` across"""
    thick, d0 = coin_dims(coin)
    s = diam / d0
    h_each = thick * s * 0.92
    x, y, z = at
    for i in range(n):
        jx = 0.05 * diam * math.sin(i * 2.3 + x)
        jy = 0.05 * diam * math.cos(i * 1.7 + y)
        c.place(coin, at=(x + jx, y + jy, z + (i + 0.5) * h_each), scale=s, anchor="center",
                rot=(0, 90, spin + 23 * i))


@card("store_starter", "Starter Pack: Storm Tabby, a cash stack and an x2 Pet XP potion")
def c_starter(c):
    c.place(pet_pieces("storm_tabby"), at=(0, 0.6, 0), height=4.2)
    bills = bills_model()
    c.place(bills, at=(-2.35, -1.2, 0), width=2.4, rot=(0, 0, 18))
    c.place(bills, at=(-2.3, -1.25, 0.52), width=2.4, rot=(0, 0, 8))
    c.place(potion_model("card_potion"), at=(2.35, -1.1, 0), height=2.5, rot=(0, 0, -10))
    return dict(yaw=-14, pitch=12, exposure=0.35)


@card("store_pro", "Pro Pack: the Crown Phoenix and a stack of Cloud Tokens")
def c_pro(c):
    look = dict(GOLD_LOOK, Accessory="Crown")
    c.place(pet_pieces("ember_phoenix", look), at=(0.4, 0.6, 0), height=4.6)
    coin = prop_piece("token", "card_token_cloud", {"palette": "Cloud"})
    coin_stack(c, 5, (-2.7, -0.7, 0), coin, 1.15)
    coin_stack(c, 3, (-1.7, -1.8, 0), coin, 1.15, spin=40)
    return dict(yaw=-14, pitch=12, exposure=-0.12)


@card("store_vip", "VIP pass: a gold crown on a purple velvet cushion")
def c_vip(c):
    c.place(cushion_model(), at=(0, 0, 0), width=4.6)
    c.place(crown_model(), at=(0, 0, 0.95), width=3.1)
    return dict(yaw=-20, pitch=16)


@card("store_x2cash", "x2 Cash pass: a cash coin with a big x2")
def c_x2cash(c):
    coin = prop_piece("token", "card_token_cash", {"palette": "Cash"})
    c.place(coin, at=(-0.5, 0.3, 0.0), height=4.0, rot=(0, 0, 90 - 18), anchor="center")
    c.place(x2_model("card_x2"), at=(1.3, -1.4, -1.1), width=3.0, anchor="center", rot=(0, 0, 8))
    return dict(yaw=-10, pitch=8)


@card("store_x2xp", "x2 Pet XP pass: a puffy purple XP star with a big x2")
def c_x2xp(c):
    c.place(star_model("card_xpstar", ("Brew", "BrewLight", "BrewDark"), R=1.0), at=(-0.4, 0.4, 0.0), height=4.2,
            anchor="center", rot=(0, 0, 12))
    c.place(x2_model("card_x2"), at=(1.3, -1.4, -1.2), width=3.0, anchor="center", rot=(0, 0, 8))
    return dict(yaw=-10, pitch=8)


@card("store_potion_1h", "x2 Pet XP potion, 1 hour")
def c_potion1(c):
    c.place(potion_model("card_potion"), at=(0, 0, 0), height=3.0, rot=(0, 0, -12))
    return dict(yaw=-12, pitch=14, zoom=0.8)


@card("store_potion_3h", "x2 Pet XP potion, 3 hours: the bigger, deeper brew")
def c_potion3(c):
    c.place(potion_model("card_potion3", big=True), at=(0, 0, 0), height=3.0, rot=(0, 0, -12))
    return dict(yaw=-12, pitch=14)


# deterministic gem heaps: (x, y, z, size, rx, rz) in heap units
def _heap(n, radius, height, seed):
    out = []
    golden = 2.399963
    for i in range(n):
        t = (i + 0.5) / n
        r = radius * math.sqrt(1 - t) * (0.9 + 0.2 * math.sin(i * 7.1 + seed))
        a = i * golden + seed
        x, y = r * math.cos(a), r * math.sin(a) * 0.75
        z = height * (t ** 0.8) * max(0.0, 1 - (r / max(radius, 1e-6)) ** 2) ** 0.5
        s = 0.85 + 0.3 * ((i * 37 + seed * 11) % 7) / 6.0
        out.append((x, y, z, s, 18 * math.sin(i * 3.3), 40 * i + seed * 5))
    return out


def gem_heap(c, gem, n, radius, height, seed, size=1.0, centre=(0, 0, 0)):
    spots = _heap(n, radius, height, seed)
    spots.sort(key=lambda s: -s[1])   # back first (no effect on the result, ids follow it)
    for (x, y, z, s, rx, rz) in spots:
        c.place(gem, at=(centre[0] + x, centre[1] + y, centre[2] + z), height=size * s, anchor="center",
                rot=(rx, 0, rz))


@card("store_gems_1", "Gems pack 1: one gem")
def c_gems1(c):
    c.place(gem_model(), at=(0, 0, 0), height=3.0, anchor="center", rot=(0, 0, 22))
    return dict(yaw=-10, pitch=14)


@card("store_gems_2", "Gems pack 2: a handful of gems")
def c_gems2(c):
    g = gem_model()
    for (x, y, z, s, rx, rz) in ((-1.0, 0.3, 0.6, 1.2, 0, 20), (1.0, 0.4, 0.6, 1.15, 0, -15),
                                 (0.0, 0.9, 1.1, 1.3, 0, 8), (-0.45, -0.6, 0.5, 1.05, 12, 40),
                                 (0.6, -0.55, 0.5, 1.0, -10, -30)):
        c.place(g, at=(x, y, z), height=s, anchor="center", rot=(rx, 0, rz))
    return dict(yaw=-10, pitch=22)


@card("store_gems_3", "Gems pack 3: a chest-top heap of gems on a gold dish")
def c_gems3(c):
    c.place(dish_model(), at=(0, 0, 0), width=5.0)
    gem_heap(c, gem_model(), 14, 1.9, 1.6, 3, size=1.0, centre=(0, 0, 0.55))
    return dict(yaw=-14, pitch=24)


@card("store_gems_4", "Gems pack 4: a vault heap of gems with gold coins")
def c_gems4(c):
    coin = prop_piece("token", "card_token_golden", {"palette": "Golden"})
    for i, (x, y, rz) in enumerate(((-2.2, -0.6, 10), (2.3, -0.4, -30), (-1.4, -1.5, 50), (1.5, -1.5, 80))):
        coin_lay(c, coin, (x, y, 0), 1.2, spin=rz)
    gem_heap(c, gem_model(), 26, 2.6, 2.4, 7, size=1.05, centre=(0, 0.2, 0))
    return dict(yaw=-14, pitch=22)


def dish_model(key="card_dish"):
    """a shallow gold dish with a raised rim and a foot"""
    K = 8.0
    S = sculpt(K, 2.8, "dish")
    X, Y, Z = S.X, S.Y, S.Z
    rho = np.sqrt(X ** 2 + Z ** 2)
    R = 2.5
    bowl = (rho < R) & (Y > 0.15) & (Y < 0.15 + 0.5 * (rho / R) ** 2 + 0.14)
    S.put("Gold", bowl)
    S.put("GoldLight", bowl & (rho > R - 0.25))
    S.put("GoldDark", (rho < 1.2) & (Y > 0) & (Y <= 0.2))
    return model_of(S, key)


@card("store_tokens_1", "Cloud Tokens pack 1: a small stack of tokens")
def c_tok1(c):
    coin = prop_piece("token", "card_token_cloud", {"palette": "Cloud"})
    coin_stack(c, 4, (-0.8, 0.4, 0), coin, 2.0)
    c.place(coin, at=(1.1, -0.7, 0.0), height=2.3, rot=(0, 0, 90 - 20), anchor="bottom")
    return dict(yaw=-12, pitch=14)


@card("store_tokens_2", "Cloud Tokens pack 2: a handful of token stacks")
def c_tok2(c):
    coin = prop_piece("token", "card_token_cloud", {"palette": "Cloud"})
    coin_stack(c, 7, (-1.1, 0.6, 0), coin, 1.6)
    coin_stack(c, 5, (0.9, 0.7, 0), coin, 1.6, spin=30)
    coin_stack(c, 3, (-0.2, -1.0, 0), coin, 1.6, spin=60)
    c.place(coin, at=(1.9, -1.0, 0.0), height=1.9, rot=(0, 0, 90 - 25), anchor="bottom")
    return dict(yaw=-12, pitch=18)


@card("store_tokens_3", "Cloud Tokens pack 3: a big heap of tokens")
def c_tok3(c):
    coin = prop_piece("token", "card_token_cloud", {"palette": "Cloud"})
    coin_stack(c, 9, (-1.7, 1.0, 0), coin, 1.5)
    coin_stack(c, 11, (0.2, 1.3, 0), coin, 1.5, spin=20)
    coin_stack(c, 7, (1.9, 0.6, 0), coin, 1.5, spin=40)
    coin_stack(c, 5, (-0.8, -0.4, 0), coin, 1.5, spin=60)
    coin_stack(c, 4, (1.0, -0.6, 0), coin, 1.5, spin=80)
    coin_stack(c, 3, (-2.6, -0.2, 0), coin, 1.5, spin=10)
    for (x, y, rz, tilt) in ((-2.0, -1.6, 20, 70), (2.5, -1.4, -40, 65), (0.1, -1.9, 70, 78)):
        coin_lay(c, coin, (x, y, 0.0), 1.5, spin=rz, tilt=tilt)
    return dict(yaw=-12, pitch=22)


@card("daily_gift_closed", "Daily gift, closed: a blue gift box with the Trove sign's rose bow")
def c_gift_closed(c):
    c.place(gift_box_model("card_gift_box", "box"), at=(0, 0, 0), width=3.2)
    c.place(gift_box_model("card_gift_lid", "lid"), at=(0, 0, 3.2 * 2.6 / 3.2 - 0.12), width=3.64)
    return dict(yaw=-26, pitch=18)


@card("daily_gift_open", "Daily gift, open: the lid pops up, light and stars burst out")
def c_gift_open(c):
    c.place(gift_box_model("card_gift_box", "box"), at=(0, 0, 0), width=3.2)
    c.place(gift_box_model("card_gift_lid", "lid"), at=(0.5, 0.2, 3.9), width=3.64, rot=(0, -22, 8))
    st = star_model("card_star")
    for (x, y, z, h, rz) in ((-1.25, -0.4, 3.0, 0.9, 18), (1.45, -0.5, 2.95, 0.7, -14), (-0.2, -0.6, 3.25, 0.62, 4)):
        c.place(st, at=(x, y, z), height=h, anchor="center", rot=(0, 0, rz))
    return dict(yaw=-26, pitch=16)


@card("daily_week_badge", "Daily streak: the round WEEK badge")
def c_week(c):
    c.place(ribbon_tails_model(), at=(0, 0.3, -3.6), height=2.6, anchor="bottom")
    c.place(badge_model(), at=(0, 0, 0), height=5.0, anchor="center")
    return dict(yaw=-14, pitch=6)


@card("daily_week_wisp", "Daily day 7: the Week Wisp (sleepy_owl's rig in gold / white)")
def c_wisp(c):
    c.place(pet_pieces("sleepy_owl", GOLD_LOOK), at=(0, 0, 0), height=4.5)
    return dict(yaw=-20, pitch=10, exposure=-0.1)


@card("trove_card", "The Sky Trove: the open chest, three-quarter view")
def c_trove(c):
    body = prop_piece("lobby_trove_body", "card_trove_body")
    lid = prop_piece("lobby_trove_lid", "card_trove_lid")
    a = body.attachments["LidOpen"]
    # open wider than the in-world 18 degrees: the same hinge axis, 58 degrees
    R18 = Matrix(np.asarray(a["rot"], float).tolist())
    axis, ang = R18.to_quaternion().to_axis_angle()
    from mathutils import Quaternion
    R = np.array(Quaternion(axis, ang * 58.0 / 18.0).to_matrix())
    c.place([(body, None), (lid, B.cf_to_bl(R.tolist(), a["pos"]))], at=(0, 0, 0), height=4.0)
    return dict(yaw=-32, pitch=20)


def _icon(key):
    def fn(c):
        if key == "icon_tab_roulettes":
            m = icon_wheel_model("card_" + key)
        else:
            rows, cmap = ICONS[key]
            m = glyph_model("card_" + key, [(rows, cmap, (0, 0), -0.5, 1.5)], K=4.0, depth=1.5, px=1.0)
        c.place(m, at=(0, 0, 0), height=4.0, anchor="center")
        return dict(yaw=-10, pitch=8)
    return fn


ICON_DESC = {
    "icon_tab_packs": "Store tab Packs: a purple pack box with a gold star",
    "icon_tab_passes": "Store tab Passes: a gold ticket with a rose star",
    "icon_tab_boosts": "Store tab Boosts: a lightning bolt",
    "icon_tab_currency": "Store tab Currency: a cut gem",
    "icon_tab_roulettes": "Store tab Roulettes: a roulette wheel",
    "icon_gifts": "HUD Gifts button: a gift box with a rose bow",
    "icon_vip_crown": "VIP crown glyph",
}
for _k, _d in ICON_DESC.items():
    CARDS[_k] = (_icon(_k), _d)


# ------------------------------------------------------------------------------------------------ index + sheet
def image_structure(path):
    """size + pixel format (as build_vortex.py: informational, any content change is a new image asset)"""
    with open(path, "rb") as f:
        head = f.read(33)
    w, h = struct.unpack(">II", head[16:24])
    sig = "png %dx%d %s" % (w, h, "RGBA")
    return hashlib.sha256(sig.encode("utf-8")).hexdigest()[:32]


def write_index(paths):
    with open(INDEX, "rb") as f:
        index = json.loads(f.read().decode("utf-8"))
    for key in sorted(paths):
        with open(paths[key], "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        index["keys"][key] = {
            "png": os.path.relpath(paths[key], REPO).replace(os.sep, "/"),
            "displayName": "NC " + key.replace("_", " "),
            "description": "Nimbus Climb store art: " + CARDS[key][1],
            "contentHash": digest,
            "structureHash": image_structure(paths[key]),
            "build": "blender/textures/build_store.py (Blender 5.2 headless, Cycles seed %d)" % SEED,
        }
    with open(INDEX, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(index, indent=2, sort_keys=True) + "\n")


def sheet(paths, out):
    """a contact sheet on a dark card gradient: each picture at card size (120 px), full size, and 20 px"""
    from PIL import Image, ImageDraw
    keys = sorted(paths)
    cols = 4
    cw, chh = 420, 300
    im = Image.new("RGB", (cw * cols, chh * ((len(keys) + cols - 1) // cols)), (12, 15, 38))
    d = ImageDraw.Draw(im)
    for i, k in enumerate(keys):
        x0, y0 = (i % cols) * cw, (i // cols) * chh
        bg = Image.new("RGB", (cw - 8, chh - 8), (26, 32, 72))
        for yy in range(chh - 8):
            t = yy / (chh - 8)
            ImageDraw.Draw(bg).line([(0, yy), (cw - 8, yy)], fill=(int(70 + 120 * t), int(60 + 60 * t), int(170 - 60 * t)))
        art = Image.open(paths[k]).convert("RGBA")
        big = art.resize((256, 256), Image.LANCZOS)
        bg.paste(big, (6, 24), big)
        small = art.resize((120, 120), Image.LANCZOS)
        bg.paste(small, (272, 24), small)
        tiny = art.resize((20, 20), Image.LANCZOS)
        bg.paste(tiny, (272, 160), tiny)
        im.paste(bg, (x0 + 4, y0 + 4))
        d.text((x0 + 10, y0 + 8), k, fill=(255, 255, 255))
    im.save(out)


def main():
    argv = sys.argv[1:]
    keys, sheet_out = [], None
    i = 0
    while i < len(argv):
        if argv[i] == "--key":
            keys.append(argv[i + 1])
            i += 2
        elif argv[i] == "--sheet":
            sheet_out = argv[i + 1]
            i += 2
        else:
            raise SystemExit("unknown argument %r" % argv[i])
    todo = keys or list(CARDS)
    unknown = [k for k in todo if k not in CARDS]
    if unknown:
        raise SystemExit("unknown key(s): %s" % ", ".join(unknown))
    t0 = time.time()
    paths = {}
    for k in todo:
        fn, _ = CARDS[k]
        c = Card(k, icon=k.startswith("icon_"))
        view = fn(c) or {}
        path, dt = c.render(**view)
        paths[k] = path
        print("STORE %-20s %5.1fs  %s" % (k, dt, os.path.relpath(path, REPO)))
    write_index(paths)
    print("STORE rendered %d picture(s) in %.1fs -> %s (+ %s)" % (len(paths), time.time() - t0,
                                                                  os.path.relpath(OUT, REPO),
                                                                  os.path.relpath(INDEX, REPO)))
    if sheet_out:
        allp = {k: os.path.join(OUT, k + ".png") for k in CARDS if os.path.exists(os.path.join(OUT, k + ".png"))}
        sheet(allp, sheet_out)
        print("STORE sheet", sheet_out)


if __name__ == "__main__":
    main()
