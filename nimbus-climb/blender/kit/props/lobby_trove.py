"""The Sky Trove (shop retention spec 2026-11-04 sections 5.3 / 9; catalog blender/catalog/lobby.json): the big
treasure chest that replaces the boarded-up Item Shop stall on the shop island (LobbyBuilder buildItemStall, shop
local (-21, -8)), in the shop island's own family: warm planks with seams, brass bands and corner caps (the dungeon
chest's gold straps + gold corners, props/arena_style.py fam_wood "Chest"), rose / cream / navy / gold accents.

  * "lobby_trove_body"  prop_trove_body[_low]: the chest body, 9 x 4 x 6 studs (9.5 wide over the handle bars; over-scaled):
                        four planks a side with seams, end joints and grain, two brass bands, two brass straps front and
                        back, eight brass corner caps (the bottom four are its feet), side handles, a brass lock with a
                        keyhole, the hinge knuckles on the back, and inside a heap of coins and gems with warm Neon
                        glows (the light in the gap when the lid stands open), two coins spilled in front.
                        Pivot = ground centre, front -Z.  Attachments: LidHinge (the lid pivot, closed pose), LidOpen
                        (the spec's 18 degree rest pose), GapGlow (a spot for the game's PointLight + sparkle emitter).
  * "lobby_trove_lid"   prop_trove_lid[_low]: its own key (the game tweens it from 18 to 70 degrees).  Built CLOSED with
                        its origin ON the hinge line (the back-bottom edge; body space (0, 4, 3)): a barrel lid
                        9 x 2 x 6 studs (flat front 1.25, dome 0.75), dome planks, a brass rim band, straps over the dome
                        down to the hinge leaves, corner caps, notches for the body's knuckles and the "SKY TROVE" plate
                        (navy enamel, brass rim, raised gold 3 x 5 pixel letters on a 0.125-stud grid of its own).
                        Opening = CFrame.Angles(+angle, 0, 0) about the origin (+X axis): every lid voxel has local
                        y >= 0 and z <= 0, so it only swings up and back, never into the body; the voxels round the
                        knuckle notches stay >= 0.5 stud from the axis (the knuckles reach 0.36).
  * "lobby_trove_sign"  prop_trove_sign[_low]: a small two-post board sign (like the shop island's post signs: dark
                        posts, a plank board with a dark frame and nails, a rose cap) with a cream panel reading
                        "FREE GIFT" in raised rose letters and a rose gift bow on top; 6 x 5.2 x 1.5 studs, the board
                        2.25 - 4 studs up (eye height).  Pivot = ground centre, front -Z.

`_low` twins (args {"low": true}, catalog "lod": "Low"): the same shapes at 0.5-stud voxels (no seams, grain, rivets,
handle bars or spilled coins), the plates' letters painted flush instead of raised.  Colours are constant (one baked
Fixed part per grid, keys prefixed "lb" by lobby.Sculpt) plus the Neon glow part; no per-instance look.
Deterministic (hash picks only, no RNG state).
"""
import math

import numpy as np

from nvox.grid import angles
from props import prop
from props.lobby import Sculpt, finish, hsh

TPAL = {
    "Plank": (196, 146, 98), "PlankLight": (214, 166, 114), "PlankWarm": (204, 150, 96), "PlankDark": (152, 108, 72),
    "Seam": (128, 90, 60), "Grain": (178, 130, 86),
    "Brass": (236, 186, 80), "BrassDark": (200, 148, 60), "BrassLight": (252, 220, 132),
    "Iron": (64, 70, 92),
    "Gold": (244, 198, 84), "GoldLight": (255, 226, 140), "GoldDark": (214, 160, 64),
    "Ruby": (236, 92, 122), "Sapphire": (96, 160, 240), "Emerald": (92, 204, 142),
    "Navy": (34, 42, 76), "Cream": (246, 234, 210), "Rose": (234, 120, 146), "RoseDark": (206, 96, 124),
}
GLOW = ["rgb", 255, 236, 170]
WOOD = ("Plank", "PlankLight", "PlankWarm", "PlankDark")
TONES = ("Plank", "PlankLight", "PlankWarm", "Plank")

# the sign's gift bow, rows bottom -> top, 0.25-stud cells (X ribbon, k knot / folds)
BOW = ("XXX....XXX", "XkXXkkXXkX", "XXXXkkXXXX", "XXX....XXX")

# 3 x 5 pixel letters (rows top -> bottom)
FONT = {
    "S": ("111", "100", "111", "001", "111"), "K": ("101", "101", "110", "101", "101"),
    "Y": ("101", "101", "010", "010", "010"), "T": ("111", "010", "010", "010", "010"),
    "R": ("110", "101", "110", "101", "101"), "O": ("111", "101", "101", "101", "111"),
    "V": ("101", "101", "101", "101", "010"), "E": ("111", "100", "110", "100", "111"),
    "F": ("111", "100", "110", "100", "100"), "G": ("011", "100", "101", "101", "011"),
    "I": ("111", "010", "010", "010", "111"),
}


class TroveSculpt(Sculpt):
    """lobby.Sculpt with the trove palette and cell-exact masks: voxel index i covers origin + [i, i + 1] * vs (mesh
    offset = origin + vs / 2), so boxes given in studs land on exact voxel boundaries"""

    def __init__(self, kit, K, extent, origin=(0.0, 0.0, 0.0), name="grid"):
        Sculpt.__init__(self, kit, K, extent, name=name)
        self.vs = 1.0 / K
        self.origin = np.asarray(origin, float)
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
            rec[k] = self.neon[k] if k in self.neon else ["rgb"] + list(TPAL[k])
        return rec

    def B(self, x0, x1, y0, y1, z0, z1):
        """cells whose centres lie inside the stud box"""
        X, Y, Z = self.X, self.Y, self.Z
        return (X > x0) & (X < x1) & (Y > y0) & (Y < y1) & (Z > z0) & (Z < z1)

    def cell(self, x, y, z):
        """the one cell whose centre is (x, y, z) (studs; a cell centre)"""
        e = self.vs * 0.4
        return (np.abs(self.X - x) < e) & (np.abs(self.Y - y) < e) & (np.abs(self.Z - z) < e)

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

    def mesh_at(self, m, group, used):
        return self.mesh(m, group=group, offset=tuple(float(v) for v in self.origin + self.vs / 2), used=used)


def text_cells(text, gap_word=4):
    """pixel cells (col, row from the top) of `text` in the 3 x 5 font: 1 column between letters, `gap_word` empty
    columns between words; returns (cells, width)"""
    cells, x = [], 0
    for ch in text:
        if ch == " ":
            x += gap_word - 1
            continue
        for r, row in enumerate(FONT[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    cells.append((x + c, r))
        x += 4
    return cells, x - 1


def plate(kit, text, x0, y0, zback, cols, rows, field, rim, ink, low, K=8.0):
    """an enamel plate of cols x rows cells (1 / K stud) with its back-bottom-left corner at (x0, y0, zback): 2 cells
    deep in front of zback, a 1-cell `rim` (None: no rim), `ink` letters centred, raised 1 cell (low: painted flush)"""
    vs = 1.0 / K
    P = TroveSculpt(kit, K, max(cols, rows) * vs + 0.6, origin=(x0, y0, zback - 3 * vs), name="plate")
    ox, oy, oz = P.origin
    xa, xb, ya, yb = ox, ox + cols * vs, oy, oy + rows * vs
    P.put(field, P.B(xa, xb, ya, yb, oz + vs, oz + 3 * vs))
    if rim:
        P.put(rim, P.B(xa, xb, ya, yb, oz + vs, oz + 3 * vs) & ~P.B(xa + vs, xb - vs, ya + vs, yb - vs, oz, oz + 4 * vs))
    cells, w = text_cells(text)
    cx0, cy0 = (cols - w) // 2, (rows - 5) // 2
    z0 = oz + vs if low else oz
    for (c, r) in cells:
        # the front faces -Z: seen from the front, +X is on the viewer's left, so the text runs towards -X
        i, j = cols - 1 - (cx0 + c), cy0 + (4 - r)
        P.put(ink, P.B(ox + i * vs, ox + (i + 1) * vs, oy + j * vs, oy + (j + 1) * vs, z0, oz + 2 * vs))
    return P


def _planks(S, faces, rows, seed, low):
    """a tone per plank (face, row); High: seams under every row but the first, one end joint and a grain streak per
    plank"""
    vs = S.vs
    for fi, (fmask, axis, lo_, hi_) in enumerate(faces):
        A = S.X if axis == 0 else S.Z
        for ri, (y0, y1) in enumerate(rows):
            band = fmask & (S.Y > y0) & (S.Y < y1)
            S.put(TONES[int(hsh(fi, ri, seed) * 3.999)], band, only=WOOD)
            if low:
                continue
            if ri > 0:
                S.put("Seam", fmask & (S.Y > y0) & (S.Y < y0 + vs), only=WOOD)
            j = round((lo_ + 1.0 + hsh(fi, ri, seed + 1) * (hi_ - lo_ - 2.0)) / vs) * vs
            S.put("Seam", band & (A > j) & (A < j + vs), only=WOOD)
            g0 = lo_ + 0.5 + hsh(fi, ri, seed + 2) * (hi_ - lo_ - 3.0)
            gy = round(((y0 + y1) / 2) / vs) * vs
            S.put("Grain", band & (A > g0) & (A < g0 + 1.25 + hsh(fi, ri, seed + 3)) & (S.Y > gy - vs) & (S.Y < gy),
                  only=WOOD)


# ---------------------------------------------------------------------------------------------- body
W, D, H = 4.5, 3.0, 4.0          # body half width, half depth, height (studs)
HINGE = (0.0, 4.0, 3.0)          # the lid pivot in body space: the back-top edge on the caps plane
OPEN_DEG = 18.0
STRAP = (2.75, 3.25)             # |x| of the brass straps
KNUCKLE = (2.5, 3.5)             # |x| of the hinge knuckles
IW = 0.5                         # wood planes sit 0.5 stud inside the caps plane; High bands 0.25, Low bands flush


def _heap_top(x, z, ix, iz):
    u = np.clip(1 - (x / ix) ** 2, 0, 1) ** 0.6 * np.clip(1 - (z / iz) ** 2, 0, 1) ** 0.6
    return 3.3 + 0.62 * u


@prop("lobby_trove_body")
def lobby_trove_body(entry, kit):
    a = entry.get("args") or {}
    low = bool(a.get("low", False))
    K = 2.0 if low else 4.0
    S = TroveSculpt(kit, K, 5.5)
    vs = S.vs
    ib = 0.0 if low else 0.25
    wx, wz = W - IW, D - IW              # wood planes
    bx, bz = W - ib, D - ib              # band planes
    t = 0.5                              # wall thickness
    X, Y, Z = S.X, S.Y, S.Z
    ax, az = np.abs(X), np.abs(Z)
    # the plank shell, hollow above a 1-stud floor
    S.put("Plank", S.B(-wx, wx, 0, H, -wz, wz))
    S.cut(S.B(-wx + t, wx - t, 1.0, H + 1, -wz + t, wz - t))
    faces = [(S.B(-wx, wx, 0, H, -wz, -wz + t), 0, -wx, wx), (S.B(-wx, wx, 0, H, wz - t, wz), 0, -wx, wx),
             (S.B(-wx, -wx + t, 0, H, -wz + t, wz - t), 2, -wz, wz), (S.B(wx - t, wx, 0, H, -wz + t, wz - t), 2, -wz, wz)]
    rows = [(0.5, 1.5), (1.5, 2.5), (2.5, 3.5)] if low else [(0.5, 1.25), (1.25, 2.0), (2.0, 2.75), (2.75, 3.5)]
    _planks(S, faces, rows, 7, low)
    # dark corner posts
    S.put("PlankDark", (ax > wx - t) & (az > wz - t), only=WOOD + ("Seam", "Grain"))
    # brass on the band plane (a 1-voxel shell round the wood): two bands, two straps front and back
    ring = S.B(-bx, bx, 0, H, -bz, bz) & ~S.B(-wx, wx, -1, H + 1, -wz, wz)
    for (y0, y1) in ((0.0, 0.5), (3.5, 4.0)):
        S.put("Brass", ring & (Y > y0) & (Y < y1))
    S.put("Brass", ring & (ax > STRAP[0]) & (ax < STRAP[1]) & (az > wz))
    # side handles: a brass plate on the band plane and (High) a pull bar beyond the caps plane
    for sx in (-1, 1):
        S.put("Brass", ring & (X * sx > 0) & (ax > wx) & (az < 0.75) & (Y > 2.25) & (Y < 3.25))
        if not low:
            S.put("BrassDark", (X * sx > W) & (X * sx < W + 0.25) & (az < 0.75) & (Y > 2.0) & (Y < 2.25))
            S.put("BrassDark", (X * sx > bx) & (X * sx < W + 0.25) & (az > 0.5) & (az < 0.75) & (Y > 2.0) & (Y < 2.5))
    # corner caps 0.75 stud, top and bottom (the bottom four are the feet), a rivet on each face (High)
    cap = (ax > W - 0.75) & (az > D - 0.75) & (ax < W) & (az < D)
    cap_y = ((0.0, 0.75), (H - 0.75, H)) if not low else ((0.0, 1.0), (H - 1.0, H))
    for (y0, y1) in cap_y:
        S.put("Brass" if not low else "BrassDark", cap & (Y > y0) & (Y < y1))
        if not low:
            yc = (y0 + y1) / 2
            for sx in (-1, 1):
                for sz in (-1, 1):
                    S.put("BrassLight", S.cell(sx * (W - 0.375), yc, sz * (D - 0.125)))
                    S.put("BrassLight", S.cell(sx * (W - 0.125), yc, sz * (D - 0.375)))
    if not low:
        # a shadow line under the planks between the feet
        S.cut((Y < vs) & ~cap)
    # the lock: a brass plate on the front centre up to the rim, round bottom corners, a keyhole
    if low:
        S.put("Brass", S.B(-1.0, 1.0, 2.5, H, -D - 0.6, -wz))
        S.put("Iron", S.B(-0.5, 0.5, 2.5, 3.0, -D - 0.6, -D))
    else:
        S.put("Brass", S.B(-0.75, 0.75, 2.5, H, -D, -wz))
        S.cut(S.B(-0.75, -0.5, 2.5, 2.75, -D, -bz) | S.B(0.5, 0.75, 2.5, 2.75, -D, -bz))
        S.put("Iron", S.B(-0.25, 0.25, 2.75, 3.25, -D, -bz))
        S.put("BrassLight", S.B(-0.75, 0.75, H - 0.25, H, -D, -bz))
    # hinge knuckles on the back: centred on the hinge axis (High), just under and behind it (Low)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * KNUCKLE[0], sx * KNUCKLE[1]))
        if low:
            S.put("BrassDark", S.B(x0, x1, 3.5, 4.0, 3.0, 3.5))
        else:
            S.put("BrassDark", S.B(x0, x1, 3.75, 4.25, 2.75, 3.25))
    # the treasure: a heap of coins (2-cell coin blocks in three golds), gems and warm Neon glows, all under the rim
    ix, iz = wx - t, wz - t
    inside = S.B(-ix, ix, 0.9, H, -iz, iz)
    top = np.minimum(_heap_top(X, Z, ix, iz) + 0.12 * np.sin(X * 2.1 + 0.5) * np.cos(Z * 1.7), H - 0.05)
    heap = inside & (Y < top)
    S.put("Gold", heap)
    blk = vs * (1 if low else 2)
    ii, jj, kk = (np.floor(A / blk).astype(np.int64) for A in (X, Y, Z))
    hm = (((ii * 73856093) ^ (jj * 19349663) ^ (kk * 83492791)) & 0xFFFF) / 65535.0
    S.put("GoldLight", heap & (hm > 0.62) & (hm < 0.86), only="Gold")
    S.put("GoldDark", heap & (hm >= 0.86), only="Gold")
    for (gk, gx, gz, gr) in (("Ruby", -2.3, -0.6, 0.38), ("Sapphire", 2.2, 0.7, 0.38), ("Emerald", 0.9, -1.1, 0.32),
                             ("Ruby", 1.4, 1.2, 0.3), ("Sapphire", -0.9, 1.0, 0.32)):
        r = max(gr, vs * 0.75)
        gy = min(float(_heap_top(gx, gz, ix, iz)), H - r - 0.02)
        S.put(gk, inside & ((X - gx) ** 2 + (Y - gy) ** 2 + (Z - gz) ** 2 <= r * r))
    glows = [(-1.2, -0.7, 0.75), (1.4, -0.3, 0.62), (0.2, 0.9, 0.62)] if not low else [(-1.25, -0.75, 0.75), (1.25, 0.25, 0.7)]
    for (gx, gz, gr) in glows:
        gy = float(_heap_top(gx, gz, ix, iz))  # centred on the heap's skin, its top clipped under the rim
        S.put("Glow", inside & ((X - gx) ** 2 + ((Y - gy) * 1.2) ** 2 + (Z - gz) ** 2 <= gr * gr) & (Y < H - 0.05))
    S.neon["Glow"] = GLOW
    if not low:
        # two coins spilled on the ground at the front left
        for (cx, cz) in ((-3.1, -3.55), (-2.45, -3.85)):
            S.put("Gold", ((X - cx) ** 2 + (Z - cz) ** 2 <= 0.33 ** 2) & (Y > 0) & (Y < vs))
    m = kit.model(entry["key"], "prop", vs=vs, K=K)
    S.mesh_at(m, "Chest", {})
    finish(m, {"source": "designed (shop retention spec 5.3 / 9): the Sky Trove chest body",
               "pivot": "ground centre, front -Z"})
    m.attachments = {
        "LidHinge": {"pos": list(HINGE), "rot": np.eye(3).tolist()},
        "LidOpen": {"pos": list(HINGE), "rot": angles(math.radians(OPEN_DEG), 0, 0).tolist()},
        "GapGlow": {"pos": [0.0, 3.9, -1.0], "rot": np.eye(3).tolist()},
    }
    return m


# ---------------------------------------------------------------------------------------------- lid
LID_F, LID_R = 1.25, 0.75        # flat front height, dome rise


@prop("lobby_trove_lid")
def lobby_trove_lid(entry, kit):
    a = entry.get("args") or {}
    low = bool(a.get("low", False))
    K = 2.0 if low else 4.0
    S = TroveSculpt(kit, K, 6.5)
    vs = S.vs
    X, Y, Z = S.X, S.Y, S.Z
    ax = np.abs(X)
    zc = -D                              # the lid's centre line (local z; the hinge is at z 0)

    def prof(inset, lift):
        """inside the barrel profile shrunk by `inset` at the sides / front / back, its top raised by `lift`"""
        hz = D - inset
        uz = np.clip(1 - ((Z - zc) / hz) ** 2, 0, 1)
        return (ax < W - inset) & (np.abs(Z - zc) < hz) & (Y > 0) & (Y < LID_F + lift + LID_R * np.sqrt(uz))

    wood = prof(IW, 0.0)
    S.put("Plank", wood)
    # dome planks run side to side: a tone per plank, seams between them and grain (High)
    edges = [-2 * D - 1, -5.0, -4.0, -3.0, -2.0, -1.0, 1.0]
    for pi_ in range(len(edges) - 1):
        z0, z1 = edges[pi_], edges[pi_ + 1]
        S.put(TONES[int(hsh(pi_, 5) * 3.999)], wood & (Z > z0) & (Z < z1) & (Y > LID_F - 0.25), only=WOOD)
        if not low:
            if pi_ > 0:
                S.put("Seam", wood & (Z > z0 - vs) & (Z < z0) & (Y > LID_F - 0.25), only=WOOD)
            gx = -3.5 + hsh(pi_, 6) * 5.0
            zm = round(((z0 + z1) / 2) / vs) * vs
            S.put("Grain", wood & (Z > zm - vs) & (Z < zm) & (X > gx) & (X < gx + 1.5) & (Y > LID_F), only=WOOD)
    if not low:
        S.put("Seam", wood & (Y > LID_F - 0.25) & (Y < LID_F) & ((Z < -2 * D + IW + 0.5) | (Z > -IW - 0.5)), only=WOOD)
    # dark end boards on both sides
    S.put("PlankDark", wood & (ax > W - IW - vs), only=WOOD + ("Seam", "Grain"))
    # brass: the rim band and the straps on the band shell, corner caps on the caps plane
    shell = (prof(0.25, 0.25) if not low else prof(0.0, 0.5)) & ~wood
    S.put("Brass", shell & (Y < 0.5))
    S.put("Brass", shell & (ax > STRAP[0]) & (ax < STRAP[1]))
    corner = (ax > W - 0.75) & ((Z < -2 * D + 0.75) | (Z > -0.75)) & (Y < (0.75 if not low else 1.0))
    S.put("Brass" if not low else "BrassDark", corner & prof(0.0, 0.5) & ~wood)
    if not low:
        for sx in (-1, 1):
            for zf, s in ((-2 * D, 1), (0.0, -1)):
                S.put("BrassLight", S.cell(sx * (W - 0.375), 0.375, zf + s * 0.125))
                S.put("BrassLight", S.cell(sx * (W - 0.125), 0.375, zf + s * 0.375))
    # knuckle notches at the back-bottom edge (the body's hinge knuckles sit in them)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * KNUCKLE[0], sx * KNUCKLE[1]))
        S.cut(S.B(x0, x1, -1, 0.5, -0.5, 1))
    # the plate's place on the front band (no band in front of the wood where the plate grid sits)
    if low:
        S.cut(S.B(-2.5, 2.5, -1, 0.5, -2 * D - 1, -2 * D + IW))
        py = 0.0
    else:
        S.cut(S.B(-2.5, 2.5, 0.25, 0.5, -2 * D - 1, -2 * D + IW))
        py = 0.25
    m = kit.model(entry["key"], "prop", vs=vs, K=K)
    used = {}
    S.mesh_at(m, "Lid", used)
    # the SKY TROVE plate: 40 x 9 cells (5 x 1.125 studs) on the wood front plane, flush with the band
    P = plate(kit, "SKY TROVE", -2.5, py, -2 * D + IW, 40, 9, "Navy", "Brass", "Gold", low)
    P.mesh_at(m, "LidPlate", used)
    finish(m, {"source": "designed (shop retention spec 5.3 / 9): the Sky Trove lid, built closed",
               "pivot": "the hinge line (body attachment LidHinge, body space (0, 4, 3)); open = CFrame.Angles(+a, 0, 0)"
                        " about +X: 18 deg at rest, 70 deg open"})
    return m


# ---------------------------------------------------------------------------------------------- sign
@prop("lobby_trove_sign")
def lobby_trove_sign(entry, kit):
    a = entry.get("args") or {}
    low = bool(a.get("low", False))
    K = 2.0 if low else 4.0
    S = TroveSculpt(kit, K, 4.5)
    vs = S.vs
    X, Y, Z = S.X, S.Y, S.Z
    top = 4.0                            # board top = cap bottom
    by = 2.25 if not low else 2.0        # board bottom
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 1.5, sx * 2.0))
        S.put("PlankDark", S.B(x0, x1, 0, top, 0.0, 0.5))
        if not low:  # the post tops poke through the cap, bevelled
            S.put("PlankDark", S.B(x0, x1, top, 4.5, 0.0, 0.5) & ~(S.B(x0, x1, 4.25, 4.5, 0, 0.5)
                                                                  & ~S.B(x0 + vs, x1 - vs, 4.25, 4.5, vs, 0.5 - vs)))
    # the board with a dark frame and nails into the posts (High), a rose cap
    S.put("Plank", S.B(-2.5, 2.5, by, top, -0.5, 0.0))
    if not low:
        S.put("PlankDark", S.B(-2.5, 2.5, by, top, -0.5, 0.0) & ~S.B(-2.25, 2.25, by + 0.25, top - 0.25, -1, 1),
              only="Plank")
        for sx in (-1, 1):
            for y in (by + 0.125, top - 0.125):
                S.put("Iron", S.cell(sx * 1.875, y, -0.375))
        S.cut(S.B(-2.5, -2.25, by, by + 0.25, -1, 1))  # a chipped corner
    capt = top + (0.25 if not low else 0.5)
    S.put("Rose", S.B(-3.0, 3.0, top, capt, -0.75 if not low else -0.5, 0.25 if not low else 0.5))
    if not low:
        S.put("RoseDark", S.B(-3.0, 3.0, top, capt, -0.75, -0.5) & (np.floor((X + 3.0) / 0.5) % 2 == 0), only="Rose")
    # a gift bow on the cap: a solid pixel bow-tie (wings widening outwards, a fold in each wing, a dark knot), 2 cells
    # deep on the cap's middle
    if not low:
        for r, row in enumerate(BOW):
            for c, ch in enumerate(row):
                if ch != ".":
                    x0 = -1.25 + c * 0.25
                    S.put("Rose" if ch == "X" else "RoseDark", S.B(x0, x0 + 0.25, capt + r * 0.25, capt + (r + 1) * 0.25,
                                                                  -0.5, 0.0))
    else:
        for sx in (-1, 1):
            S.put("Rose", S.B(*sorted((sx * 0.5, sx * 1.5)), capt, capt + 1.0, -0.5, 0.5))
        S.put("RoseDark", S.B(-0.5, 0.5, capt, capt + 0.5, -0.5, 0.5))
    m = kit.model(entry["key"], "prop", vs=vs, K=K)
    used = {}
    S.mesh_at(m, "Sign", used)
    # the FREE GIFT panel: 36 x 9 cells (4.5 x 1.125 studs) inside the frame
    P = plate(kit, "FREE GIFT", -2.25, (by + top) / 2 - 0.5625, -0.5, 36, 9, "Cream", None, "Rose", low)
    P.mesh_at(m, "SignText", used)
    finish(m, {"source": "designed (shop retention spec 9): the Sky Trove's FREE GIFT post sign",
               "pivot": "ground centre, front -Z"})
    return m
