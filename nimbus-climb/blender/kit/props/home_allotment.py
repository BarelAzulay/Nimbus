"""Berry Farm style "allotment" (bug #20, the player's pick B "Sky-Sailor's Allotment").

The crew of a retired cloud-ship hauled three lifeboats onto the island, filled them with soil and laid the ship's deck
under them; the cabin wears an upturned lifeboat as its roof.  HomeBuilder's Part build (Art.Farm) is the collider and
the fallback: boxes only.  This module turns those boxes into the shapes the Part build cannot afford, right before
the home bake (props/home_style.py) rasters them:

    expand(boxes, vs) -> boxes        (catalog args "style": "allotment"; the farm keys and home_farm_propeller)

* Hull        planked lifeboat beds: rounded ends, a raised gunwale (navy) over a white stripe with brass rivets,
              wood strakes; hollow above the soil (HullSoil / HullGrass, rounded ends too)
* Bush        a leafy dome (flat underside) with two leaf clumps; every Berry becomes a hanging cluster on a stalk
* Vine        a twisting stem with alternating leaves; GoldBerry a cluster
* Oar         shaft + blade (navy tip) + rope lashing; the Rope sags between the oars; the Mast gets a brass cap and
              a red pennant
* Tub         the old crow's-nest tub: round, navy rim, brass band, staves, soil inside
* Cabin       white planks over a navy base band; Porthole glass in a round brass rim with a dark inside; the Door a
              brass knob; the Bell a flared ship's bell on a bracket with its lanyard; the lantern a wall bracket
* HullRoof    (both boxes) one upturned lifeboat: red bottom paint up, white waterline, strakes, navy gunwale
* Anchor      shank, stock, ring, curved arms, red-painted flukes; RopeCoil a coil; Crate a strapped sea chest
* Propeller   (the element key) a hub and four blades with red tips; VanePost a collar and a tail fin
* ShipDeck    deck planks with staggered butt joints

Only box geometry is added (the Part build, its LayoutSig and its colliders are untouched).  Deterministic.
"""
import math

import numpy as np

from props import home_style as HS

NAVY = (70, 130, 180)
SAIL = (242, 240, 230)
BRASS = (230, 197, 92)
ANTI = (196, 70, 64)
HULL = (193, 138, 93)
HULL2 = (170, 118, 78)
ROPE = (222, 204, 158)
STALK = (66, 112, 52)
DARKWOOD = (120, 84, 56)
PORT_DARK = (44, 62, 92)
ANCHOR_RING = (230, 197, 92)


def _box(name, pos, size, rgb, R=None, mat="SmoothPlastic", tr=0.0, shp=None, fam=None):
    b = {"cls": "Part", "shape": "Block", "pos": np.asarray(pos, float), "R": np.eye(3) if R is None else np.asarray(R, float),
         "size": np.asarray(size, float), "rgb": tuple(int(c) for c in rgb), "mat": mat, "tr": float(tr), "name": name,
         "parent": "style"}
    if shp is not None:
        b["shp"] = shp
    if fam is not None:
        b["fam"] = fam
    return b


def _rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def _shade(rgb, f):
    return tuple(max(0, min(255, int(round(c * f)))) for c in rgb)


def _top(b):
    return b["pos"][1] + b["size"][1] / 2


def _bottom(b):
    return b["pos"][1] - b["size"][1] / 2


def _at(b, local):
    """a point in the box's own frame -> world (template) space"""
    return b["pos"] + b["R"] @ np.asarray(local, float)


# ------------------------------------------------------------------------------------------------ shapes
def _stadium(L, h, inset=0.0):
    """rounded ends along the box's longer horizontal axis (radius = half the short side)"""
    if h[0] >= h[2]:
        lo, sh = np.abs(L[..., 0]), np.abs(L[..., 2])
        hl, hs = h[0] - inset, h[2] - inset
    else:
        lo, sh = np.abs(L[..., 2]), np.abs(L[..., 0])
        hl, hs = h[2] - inset, h[0] - inset
    hs = max(hs, 1e-6)
    straight = hl - hs
    ex = np.maximum(0.0, lo - straight)
    return (ex / hs) ** 2 + (sh / hs) ** 2 <= 1.0 + 1e-6


def shape_stadium(R, b, L, h, shp):
    return _stadium(L, h)


def shape_trough(R, b, L, h, shp):
    """a hull: stadium outline, hollow inside (one shell of max(vs, 0.25)) above `depth` below the rim"""
    t = max(R.vs, 0.25)
    outer = _stadium(L, h)
    inner = _stadium(L, h, inset=t) & (L[..., 1] > h[1] - shp[1])
    return outer & ~inner


def shape_tub(R, b, L, h, shp):
    """a round tub: circle footprint, hollow inside above `depth` below the rim"""
    t = max(R.vs, 0.25)
    if len(shp) > 2 and shp[2] > 1:
        g = R.vs * shp[2]
        L = L.copy()
        for a in (0, 2):
            L[..., a] = (np.floor((L[..., a] + h[a]) / g) + 0.5) * g - h[a]
    r = np.hypot(L[..., 0] / h[0], L[..., 2] / h[2])
    outer = r <= 1.0 + 1e-6
    ri = np.hypot(L[..., 0] / max(h[0] - t, 1e-6), L[..., 2] / max(h[2] - t, 1e-6))
    inner = (ri <= 1.0) & (L[..., 1] > h[1] - shp[1])
    return outer & ~inner


def shape_dome(R, b, L, h, shp):
    """a bush: a rounded dome with a flatter underside (blocks of shp[2] voxels decide the outline)"""
    p = shp[1]
    q = np.maximum(h, R.vs)
    Lc = L
    if len(shp) > 2 and shp[2] > 1:
        g = R.vs * shp[2]
        Lc = (np.floor((L + q) / g) + 0.5) * g - q
    up = np.maximum(Lc[..., 1], 0.0) / q[1]
    down = np.maximum(-Lc[..., 1], 0.0) / q[1]
    r = (np.abs(Lc[..., 0]) / q[0]) ** p + (np.abs(Lc[..., 2]) / q[2]) ** p + up ** p + down ** 6
    return r <= 1.0 + 1e-6


def shape_round(R, b, L, h, shp):
    """round in the box's two larger dimensions (portholes, the anchor ring)"""
    thin = int(np.argmin(b["size"]))
    ax = [a for a in range(3) if a != thin]
    q = np.maximum(h, R.vs * 0.5)
    p = shp[1] if len(shp) > 1 else 2.0
    r = (np.abs(L[..., ax[0]]) / q[ax[0]]) ** p + (np.abs(L[..., ax[1]]) / q[ax[1]]) ** p
    return r <= 1.0 + 1e-6


def shape_coil(R, b, L, h, shp):
    r = np.hypot(L[..., 0] / h[0], L[..., 2] / h[2])
    return (r <= 1.0 + 1e-6) & (r >= shp[1])


def shape_bell(R, b, L, h, shp):
    """a ship's bell: a round crown on top, flaring toward the lip"""
    yr = np.clip((L[..., 1] + h[1]) / (2 * h[1]), 0.0, 1.0)  # 0 at the lip .. 1 at the crown
    rad = h[0] * (1.0 - 0.38 * yr ** 1.4)
    crown = yr > 0.82
    rad = np.where(crown, rad * np.sqrt(np.maximum(0.0, 1 - ((yr - 0.82) / 0.18) ** 2)) + R.vs * 0.5, rad)
    return np.hypot(L[..., 0], L[..., 2]) <= rad + 1e-6


def shape_boat(R, b, L, h, shp):
    """the upturned lifeboat roof: a half-ellipse across x (keel up), the ends taper to the stems over shp[1]"""
    taper = shp[1]
    if len(shp) > 2 and shp[2] > 1:
        g = R.vs * shp[2]  # decide the outline on blocks of shp[2] voxels across (chunkier steps, fewer faces)
        L = L.copy()
        L[..., 0] = (np.floor((L[..., 0] + h[0]) / g) + 0.5) * g - h[0]
    zt = np.maximum(0.0, np.abs(L[..., 2]) - (h[2] - taper)) / taper
    w = h[0] * np.sqrt(np.maximum(0.0, 1 - zt ** 2)) + R.vs * 0.5
    yr = (L[..., 1] + h[1]) / (2 * h[1])
    return (L[..., 0] / w) ** 2 + yr ** 2 <= 1.0 + 1e-6


HS.EXTRA_SHAPES.update({"stadium": shape_stadium, "trough": shape_trough, "tub": shape_tub, "dome": shape_dome,
                        "round": shape_round, "coil": shape_coil, "bell": shape_bell, "boat": shape_boat})


# ------------------------------------------------------------------------------------------------ families
def _rows_from_top(D, b, cells):
    L, q = D._local(b, cells)
    n = int(round(b["size"][1] / D.R.vs))
    return L, q, (n - 1) - q[:, 1], n


def fam_hull(D, b, pi, cells):
    """navy gunwale, a white stripe with brass rivets, wood strakes (colour bands at every detail level)"""
    L, q, k, n = _rows_from_top(D, b, cells)
    top, bottom, sx, sz = D._faces(cells)
    D._toward(cells[k == 0], np.array(NAVY) / 255.0, 1.0)
    if D.R.vs >= 0.5:
        # the _low key (0.5-stud cells, seen from 120-200 studs): a white stripe + rivets one cell high would blend the
        # navy rim into light blue at that distance; the rim alone keeps the High key's read (review fix round)
        D._scale(cells, np.where((k >= 1) & (((k - 1) // 2) % 2 == 1), 0.92, 1.0))
        return
    stripe = (k == 1) & ~top
    D._toward(cells[stripe], np.array(SAIL) / 255.0, 1.0)
    if D.level >= 1:
        u = np.where(sz, q[:, 0], q[:, 2])
        rivet = stripe & (u % 6 == 2)
        D._toward(cells[rivet], np.array(BRASS) / 255.0, 1.0)
    f = np.ones(len(cells))
    f[(k >= 2) & (((k - 2) // 2) % 2 == 1)] = 0.92  # strakes two voxels high
    f[(k >= 2) & bottom] *= 0.9
    D._scale(cells, f)


def fam_boatroof(D, b, pi, cells):
    """keel up: red bottom paint, a white waterline, wood strakes, the navy gunwale at the eave"""
    L, q = D._local(b, cells)
    top, bottom, sx, sz = D._faces(cells)
    yr = (L[:, 1] + b["size"][1] / 2) / b["size"][1]
    red = yr > 0.6
    white = (yr > 0.48) & ~red
    gun = yr < 0.14
    D._toward(cells[red], np.array(ANTI) / 255.0, 1.0)
    D._toward(cells[white], np.array(SAIL) / 255.0, 1.0)
    D._toward(cells[gun], np.array(NAVY) / 255.0, 1.0)
    f = np.ones(len(cells))
    strake = ~red & ~white & ~gun & ((q[:, 1] // 2) % 2 == 1) & (D.level >= 2)
    f[strake] = 0.9
    if D.level >= 2:
        n = HS._hash_arr(q[:, 0] // 2, q[:, 2] // 3, pi)
        f[red & (n < 0.15)] = 0.94
    D._scale(cells, f)


def fam_cabin(D, b, pi, cells):
    """white planks (a seam every 3 rows) over a navy base band"""
    L, q = D._local(b, cells)
    top, bottom, sx, sz = D._faces(cells)
    base = q[:, 1] < max(1, int(round(0.5 / D.R.vs)))
    D._toward(cells[base & ~top], np.array(NAVY) / 255.0, 1.0)
    if D.level >= 1:
        f = np.ones(len(cells))
        f[(sx | sz) & ~top & ~base & (q[:, 1] % 3 == 0)] = 0.9
        D._scale(cells, f)


def fam_tub(D, b, pi, cells):
    L, q, k, n = _rows_from_top(D, b, cells)
    D._toward(cells[k == 0], np.array(NAVY) / 255.0, 1.0)
    band = (k == max(2, n // 2))
    D._toward(cells[band], np.array(BRASS) / 255.0, 1.0)
    if D.level >= 2:
        ang = np.arctan2(L[:, 2], L[:, 0])
        stave = np.floor((ang + math.pi) / (2 * math.pi) * 22).astype(int)
        seam = np.abs(((ang + math.pi) / (2 * math.pi) * 22) - np.round((ang + math.pi) / (2 * math.pi) * 22)) < 0.12
        f = np.where(seam & (k > 0) & ~band, 0.88, np.where(stave % 2 == 0, 0.97, 1.0))
        D._scale(cells, f)


def fam_chest(D, b, pi, cells):
    """a sea chest: two navy straps, a lid seam, plank seams"""
    L, q = D._local(b, cells)
    top, bottom, sx, sz = D._faces(cells)
    vs = D.R.vs
    strap = (np.abs(np.abs(L[:, 0]) - b["size"][0] * 0.28) < vs * 0.55)
    D._toward(cells[strap], np.array(NAVY) / 255.0, 1.0)
    if D.level >= 1:
        f = np.ones(len(cells))
        lid = (np.abs(L[:, 1] - b["size"][1] * 0.22) < vs * 0.5) & ~top
        f[lid] = 0.8
        f[(sx | sz) & ~top & ~lid & (q[:, 1] % 2 == 1)] *= 0.95
        D._scale(cells, f)


def fam_deck(D, b, pi, cells):
    """deck planks along x (0.5 wide) with staggered butt joints"""
    if D.level < 2:
        return
    L, q = D._local(b, cells)
    top, bottom, sx, sz = D._faces(cells)
    per = max(1, int(round(0.5 / D.R.vs)))
    pz = q[:, 2] // per
    f = np.where(pz % 2 == 0, 1.0, 0.93)
    if D.level >= 3:
        butt = ((q[:, 0] + pz * 7) % (16 if per > 1 else 8) == 0)
        f = np.where(top & butt, f * 0.86, f)
    D._scale(cells, f)


def fam_coil(D, b, pi, cells):
    if D.level < 2:
        return
    L, q = D._local(b, cells)
    r = np.hypot(L[:, 0], L[:, 2]) / D.R.vs
    D._scale(cells, np.where(np.floor(r).astype(int) % 2 == 0, 0.88, 1.0))


def fam_lowberry(D, b, pi, cells):
    """a _low berry (one or two 0.5-stud cells): the High berry's look averaged (its colour with a little of the white
    shine mixed in), never the High's full-white shine cell, which would cover the whole berry (review fix round)"""
    D._toward(cells, (1.0, 1.0, 1.0), 0.18)


HS.EXTRA_FAMILIES.update({"lowberry": fam_lowberry, "hull": fam_hull, "boatroof": fam_boatroof, "cabin": fam_cabin, "tub": fam_tub,
                          "chest": fam_chest, "deck": fam_deck, "coil": fam_coil})


# ------------------------------------------------------------------------------------------------ expand
def _berry_cluster(b, out, seed, lean=False):
    """a Berry / GoldBerry cube -> 2-3 berries hanging on a stalk (the first keeps the box's colour)"""
    p, s = b["pos"], float(b["size"][0])
    col = b["rgb"]
    dark = _shade(col, 0.86)
    if b["name"] == "Berry" and seed % 2 == 0 and not lean:  # (a stalk on every other cluster: the triangle budget at 38-40)
        out.append(_box("Stalk", (p[0], p[1] + s * 0.55, p[2] + 0.1), (0.12, s * 0.7, 0.12), STALK, fam="plain"))
    out.append(_box(b["name"], p, (s, s, s), col, fam="berry", shp=("blob", 2.0, 1.0)))
    side = 1 if (seed % 2 == 0) else -1
    small = max(0.3, s * 0.68)
    if b["name"] == "GoldBerry" or seed % 2 == 1 or p[2] > -1.2 or lean:
        return  # gold, blue and every other red berry hang alone (the triangle budget at 38-40)
    out.append(_box(b["name"], (p[0] + side * s * 0.55, p[1] - s * 0.45, p[2] - 0.04), (small, small, small), dark, fam="berry"))


def _oar(b, out):
    x, z = b["pos"][0], b["pos"][2]
    y0, y1 = _bottom(b), _top(b)
    blade = 1.25
    out.append(_box("OarShaft", (x, (y0 - 0.2 + y1 - blade) / 2, z), (0.22, y1 - blade - y0 + 0.2, 0.22), HULL2, fam="wood"))
    out.append(_box("OarBlade", (x, y1 - blade / 2, z), (0.55, blade, 0.14), HULL, fam="wood"))
    out.append(_box("OarTip", (x, y1 - 0.18, z), (0.57, 0.36, 0.16), NAVY, fam="plain"))


def _rope(rope, oars, out, vs):
    xs = sorted(o["pos"][0] for o in oars)
    y, z = rope["pos"][1], rope["pos"][2]
    for xa, xb in zip(xs[:-1], xs[1:]):
        n = 4
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            tm = (t0 + t1) / 2
            sag = 0.32 * 4 * tm * (1 - tm)
            d = abs(0.32 * 4 * (t1 * (1 - t1) - t0 * (1 - t0)))
            out.append(_box("RopeSeg", (xa + (xb - xa) * tm, y - sag, z), ((xb - xa) / n + 0.02, d + 0.15, 0.15), ROPE, fam="plain"))


def _rigging(b, out):
    """a long diagonal rope -> about one axis-aligned segment per stud (a stepped line: far fewer faces than a
    voxelised diagonal)"""
    L = float(b["size"][2])
    a = _at(b, (0, 0, -L / 2))
    c = _at(b, (0, 0, L / 2))
    n = max(2, int(round(abs(c[0] - a[0]) / 1.4)))
    for i in range(n):
        p0 = a + (c - a) * (i / n)
        p1 = a + (c - a) * ((i + 1) / n)
        mid = (p0 + p1) / 2
        # each step as tall as its drop: the steps touch, so the rope reads as one line (never loose dashes)
        out.append(_box("RigSeg", mid, (abs(p1[0] - p0[0]) + 0.02, abs(p1[1] - p0[1]) + 0.13, 0.13), ROPE, fam="plain"))


def _vine(b, out, seed, sparse=False):
    x, z = b["pos"][0], b["pos"][2]
    y0, y1 = _bottom(b), _top(b)
    col = b["rgb"]
    n = max(2, int(round((y1 - y0) / 0.75)))
    step = (y1 - y0) / n
    for k in range(n):
        off = 0.0  # a straight stem: the alternating leaves make the twist
        yc = y0 + step * (k + 0.5)
        out.append(_box("VineStem", (x + off, yc, z), (0.25, step + 0.08, 0.25), _shade(col, 0.8), fam="plain"))
        side = 1 if (k + seed) % 2 == 0 else -1
        if sparse and k % 2 == 1:
            continue  # 38-40: the Starberry tree takes the leaf budget (every other joint)
        out.append(_box("VineLeaf", (x + off + side * 0.28, yc + 0.1, z - 0.04), (0.4, 0.26, 0.3),
                        _shade(col, 1.0 + 0.06 * ((k % 3) - 1)), fam="leaf"))


def _bush(b, out, seed, lumps=True):
    d, hgt = float(b["size"][0]), float(b["size"][1])
    p = b["pos"]
    out.append(_box("FarmBush", p, b["size"], b["rgb"], fam="leaf", shp=("dome", 2.0, 1)))
    side = 1 if seed % 2 == 0 else -1
    lump = _shade(b["rgb"], 1.05)
    if d < 1.7 or seed % 4 != 0 or not lumps:
        return  # one dome; every fourth grown bush gets a leaf clump while the budget allows (1-22)
    out.append(_box("FarmBush", (p[0] + side * d * 0.26, p[1] + hgt * 0.2, p[2] + d * 0.06), (d * 0.5, hgt * 0.62, d * 0.5), lump,
                    fam="leaf", shp=("dome", 2.2, 1)))


def _anchor(b, out):
    R = b["R"]
    col = b["rgb"]

    def part(name, local, size, rgb, rot=None, shp=None, fam="plain"):
        RR = R if rot is None else R @ rot
        out.append(_box(name, _at(b, local), size, rgb, R=RR, shp=shp, fam=fam))
    part("AnchorShank", (0, -0.02, 0), (0.22, 1.5, 0.2), col)
    part("AnchorStock", (0, 0.52, 0), (0.9, 0.18, 0.2), _shade(col, 1.1))
    part("AnchorRing", (0, 0.82, 0), (0.42, 0.42, 0.12), ANCHOR_RING, shp=("round", 2.0))
    for s in (-1, 1):
        part("AnchorArm", (s * 0.27, -0.62, 0), (0.66, 0.2, 0.2), col, rot=_rz(s * math.radians(40)))
        part("AnchorFluke", (s * 0.5, -0.36, 0), (0.3, 0.3, 0.22), ANTI)
    part("AnchorCrown", (0, -0.82, 0), (0.34, 0.2, 0.22), col)


def expand(boxes, vs):
    """the allotment's style pass (see the module doc); unknown boxes pass through unchanged"""
    out = []
    by = {}
    for b in boxes:
        by.setdefault(b["name"], []).append(b)
    cabin = (by.get("Cabin") or [None])[0]
    front = cabin["pos"][2] - cabin["size"][2] / 2 if cabin is not None else None
    roofs = by.get("HullRoof") or []
    seed = 0
    low = vs >= 0.5  # the plot-LOD _low keys (seen from 120-200 studs): the plain shapes, fewer triangles
    for b in boxes:
        seed += 1
        n = b["name"]
        if n == "Hull":
            nb = dict(b)
            nb["size"] = b["size"] + np.array([0.0, 0.3, 0.0])
            nb["pos"] = b["pos"] + np.array([0.0, 0.15, 0.0])
            nb["shp"] = ("trough", 0.5)  # hollow down to about the soil box's bottom (the soil fills it)
            nb["fam"] = "hull"
            out.append(nb)
        elif n in ("Soil", "Grass"):
            nb = dict(b)
            nb["name"] = "HullSoil" if n == "Soil" else "HullGrass"
            nb["fam"] = "soil" if n == "Soil" else "grass"
            nb["shp"] = ("stadium",)
            out.append(nb)
        elif n == "Bush" and low:
            out.append(dict(b, name="FarmBush", fam="leaf", shp=("dome", 2.4, 2)))
        elif n in ("Berry", "GoldBerry") and low:
            # one or two cells at 0.5 studs: the berry family's white shine would cover the whole berry (pale pink /
            # pale gold from afar), so the _low berries keep their colour with only a hint of the shine mixed in
            out.append(dict(b, fam="lowberry"))
        elif n in ("Vine", "Rope") and low:
            out.append(b)
        elif n == "Bush":
            _bush(b, out, seed, lumps=not by.get("Oar"))  # leaf clumps while the triangle budget allows (1-22)
        elif n in ("Berry", "GoldBerry"):
            _berry_cluster(b, out, seed, lean=bool(by.get("Oar")))  # 23-40: single berries (triangle budget)
        elif n == "Vine":
            _vine(b, out, seed, sparse=bool(by.get("Trunk")))
        elif n == "Oar":
            _oar(b, out)
        elif n == "Rope":
            if by.get("Oar"):
                _rope(b, by["Oar"], out, vs)
            else:
                out.append(b)
        elif n == "Mast":
            out.append(dict(b, fam="wood"))
            x, z, y1 = b["pos"][0], b["pos"][2], _top(b)
            out.append(_box("MastCap", (x, y1 + 0.1, z), (0.62, 0.2, 0.62), BRASS, fam="plain"))
            for i, ln in enumerate((1.35, 0.95, 0.55)):
                out.append(_box("Pennant", (x + 0.25 + ln / 2, y1 - 0.25 - 0.15 * i, z), (ln, 0.16, 0.08),
                                ANTI if i != 1 else _shade(ANTI, 1.12), fam="plain"))
        elif n == "Tub":
            nb = dict(b)
            nb["size"] = b["size"] + np.array([0.0, 0.1, 0.0])
            nb["pos"] = b["pos"] + np.array([0.0, 0.05, 0.0])
            nb["shp"] = ("tub", 0.5, 2)
            nb["fam"] = "tub"
            out.append(nb)
            t = _top(nb)
            out.append(_box("TubSoil", (b["pos"][0], t - 0.38, b["pos"][2]), (b["size"][0] - 0.5, 0.26, b["size"][2] - 0.5),
                            (110, 78, 58), fam="soil", shp=("tub", 0.0)))
        elif n == "Crown":
            # chunkier puffs (the triangle budget at 38-40; the biggest crown, at 40, the chunkiest)
            out.append(dict(b, shp=("blob", 2.4, 1.0, 4 if b["size"][0] > 4.4 else 3)))
        elif n == "Rigging":
            _rigging(b, out)
        elif n == "Cabin":
            out.append(dict(b, fam="cabin"))
        elif n == "HullRoof":
            if b is roofs[0]:
                lo = np.min([r["pos"] - r["size"] / 2 for r in roofs], axis=0)
                hi = np.max([r["pos"] + r["size"] / 2 for r in roofs], axis=0)
                out.append(_box("BoatRoof", (lo + hi) / 2, hi - lo, HULL, shp=("boat", 1.4, 2), fam="boatroof"))
        elif n == "Keel":
            nb = dict(b, fam="wood")
            if roofs:
                lz = max(r["size"][2] for r in roofs)
                nb["size"] = np.array([b["size"][0], b["size"][1], lz])
            out.append(nb)
        elif n == "Porthole":
            p = b["pos"]
            out.append(_box("PortholeRim", (p[0] + 0.02, p[1], p[2]), (0.16, 1.15, 1.15), BRASS, shp=("round", 2.0), fam="plain"))
            out.append(_box("PortholeBack", (p[0] - 0.2, p[1], p[2]), (0.3, 0.78, 0.78), PORT_DARK, shp=("round", 2.0), fam="plain"))
            out.append(dict(b, shp=("round", 2.0), size=np.array([b["size"][0], 0.78, 0.78])))
        elif n == "Door":
            out.append(b)
            p, s = b["pos"], b["size"]
            out.append(_box("DoorKnob", (p[0] + s[0] * 0.32, p[1] - 0.05, p[2] - s[2] / 2 - 0.06), (0.16, 0.16, 0.14), BRASS, fam="plain"))
            out.append(_box("DoorTrim", (p[0], p[1] + s[1] / 2 + 0.06, p[2]), (s[0] + 0.3, 0.14, s[2] + 0.04), _shade(HULL2, 0.95), fam="plain"))
        elif n == "Bell":
            p, s = b["pos"], b["size"]
            out.append(_box("ShipBell", p, s, b["rgb"], shp=("bell",), fam="berry"))
            yt = p[1] + s[1] / 2
            if front is not None:
                out.append(_box("BellArm", (p[0], yt + 0.2, (front + p[2]) / 2 - 0.05), (0.14, 0.14, abs(p[2] - front) + 0.2), DARKWOOD, fam="plain"))
            out.append(_box("BellRope", (p[0], yt + 0.08, p[2]), (0.1, 0.18, 0.1), ROPE, fam="plain"))
            out.append(_box("BellRope", (p[0], p[1] - s[1] / 2 - 0.12, p[2]), (0.1, 0.26, 0.1), ROPE, fam="plain"))
        elif n == "LanternCap":
            out.append(b)
            p = b["pos"]
            if front is not None and abs(p[2] - front) < 1.0:
                out.append(_box("LanternArm", (p[0], p[1] + 0.12, (front + p[2]) / 2), (0.12, 0.12, abs(p[2] - front) + 0.06), DARKWOOD, fam="plain"))
        elif n == "Anchor":
            _anchor(b, out)
        elif n == "RopeCoil":
            out.append(dict(b, shp=("coil", 0.3), fam="coil"))
            p = b["pos"]
            out.append(_box("RopeEnd", (p[0] + b["size"][0] * 0.42, _top(b) + 0.05, p[2] + 0.1), (0.14, 0.14, 0.4), ROPE, fam="plain"))
        elif n == "Crate":
            out.append(dict(b, name="SeaChest", fam="chest"))
        elif n == "ShipDeck":
            out.append(dict(b, fam="deck"))
        elif n == "VanePost":
            out.append(dict(b, fam="wood"))
            p, y1 = b["pos"], _top(b)
            out.append(_box("VaneCollar", (p[0], y1 - 0.1, p[2]), (0.34, 0.14, 0.34), BRASS, fam="plain"))
            out.append(_box("VaneFin", (p[0], y1 - 0.15, p[2] + 0.5), (0.08, 0.5, 0.75), NAVY, fam="plain"))
        elif n == "Propeller":
            # the element key (pivot = the part): a brass hub and four blades with red tips in the part's x / y plane
            p, R = b["pos"], b["R"]
            out.append(_box("Propeller", p, (0.36, 0.36, 0.28), BRASS, R=R, fam="plain"))
            for k in range(4):
                a = math.radians(20 + 90 * k)
                rot = R @ _rz(a)
                dirv = rot @ np.array([1.0, 0.0, 0.0])
                out.append(_box("Propeller", p + dirv * 0.5, (0.72, 0.26, 0.1), SAIL, R=rot, fam="plain"))
                out.append(_box("Propeller", p + dirv * 0.88, (0.18, 0.28, 0.12), ANTI, R=rot, fam="plain"))
        else:
            out.append(b)
    return out
