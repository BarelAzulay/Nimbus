"""Face detail pass for bridge pets: the Lua eyes are fixed-pixel masks (they shrink at a finer mesh K), so the
kit puts the carved face back, then carves PROCEDURAL eyes sized in design units (they gain detail with K) and makes
the blink lids from what it carved.

API (cells = dict (x, y, z) -> palette key of the Body group, sculpted voxels at mesh K):
    restore_carved_eyes(cells, lid_cells)            undo PetBuilder.carveEyes (uses bp.lid_cells)
    eyes = eye_specs(bp)                             [(cx, cy, rx, ry, kind, mask)] design units, one per eye
    lids = carve_eyes(cells, eyes, K, style)         carve them; returns per-eye lid cell lists [(x, y, z, key)]
    lid_groups(lids, single=False)                   -> [{x,y,z: key}] PetBuilder lidBoxes layout per eye
Eye styles ("cute" default): lash rim on top, a big dark pupil, a lighter iris crescent below, a glint row, a large
highlight upper-left (as the viewer sees it) and a small one lower-right; masks with a ring (Owl) or a slanted brow
(Fierce) are scaled up from the Lua mask instead (nearest neighbour), so their shape stays exactly the game's.
"""
import math

EYE_KEYS = {"L": "Lash", "I": "EyeIris", "P": "EyePupil", "S": "EyeShine", "G": "EyeGlint", "R": "EyeRing"}
FLAT_EYE = set(EYE_KEYS.values())


def _base(k):
    if k.endswith("_Light"):
        return k[:-6]
    if k.endswith("_Dark"):
        return k[:-5]
    return k


def front_map(cells):
    """(x, y) -> smallest z (the front surface: the pet faces -Z)"""
    fm = {}
    for (x, y, z) in cells:
        cur = fm.get((x, y))
        if cur is None or z < cur:
            fm[(x, y)] = z
    return fm


def restore_carved_eyes(cells, lid_cells):
    """PetBuilder.carveEyes moved every eye voxel one step back: put the face surface back."""
    for eye in lid_cells:
        col_key = {}
        for (x, y, z, k) in eye:
            if k not in ("LidLine", "Lid"):
                col_key.setdefault(x, k)
        for (x, y, z, k) in eye:
            key = k if k not in ("LidLine", "Lid") else col_key.get(x) or next(iter(col_key.values()), "Fur")
            cells[(x, y, z)] = key
            cells[(x, y, z + 1)] = key


def eye_specs(bp):
    """procedural eye ellipses (design units) from the Lua eye anchors"""
    K = bp.K
    out = []
    for e in bp.eyes:
        mask = e["Mask"]
        rows, w = len(mask), max(len(r) for r in mask)
        xl, ytop = float(e["XLeft"]), float(e["Y"])
        cv = xl - (w - 1) / 2.0
        if cv >= 0:
            cx = xl / K - (w - 1) / 2.0
        else:
            cx = (xl - (w - 1)) / K + (w - 1) / 2.0
        cy = ytop / K - (rows - 1) / 2.0
        chars = "".join(mask)
        kind = "mask" if ("R" in chars or chars.count("L") > 2) else ("big" if w >= 5 else "cute")
        out.append((cx, cy, w / 2.0, rows / 2.0, kind, mask))
    return out


def _cute_key(u, v, big):
    """u: +1 = towards +X (the viewer's LEFT on a pet that faces -Z), v: +1 = up; inside the unit disc"""
    if v > 0.62 and u * u + v * v > 0.55:
        return "Lash"
    hu, hv = u - 0.30, v - 0.28
    if (hu / 0.36) ** 2 + (hv / 0.34) ** 2 <= 1:
        return "EyeShine"
    su, sv = u + 0.40, v + 0.32
    if (su / 0.18) ** 2 + (sv / 0.16) ** 2 <= 1:
        return "EyeShine"
    if v < -0.72:
        return "EyeGlint"
    if v < -0.30 and abs(u) > (0.16 if big else 0.08):
        return "EyeIris"
    if v < -0.52:
        return "EyeIris"
    return "EyePupil"


SMALL_EYE_STYLE = "B"  # (W2.5 polish) the Low pixel-eye layout, see _small_key


def _small_key(i, j, w, h):
    """pixel eye for coarse grids (Low LOD): i = column from the viewer's left (+X), j = row from the top.
    W2.5: a calm dark eye with ONE highlight (upper-left, like the High eyes); no lash row and no iris pixel on the
    3-wide eyes (at Low size those single coloured pixels read as noise).  The rounded rim cuts the corners: the top
    corners always, the bottom ones on eyes 4+ tall and 4+ wide.  Wider eyes (>= 4) keep an iris crescent in the
    bottom row and a second, small glint."""
    last_i, last_j = w - 1, h - 1
    corner_i = i == 0 or i == last_i
    if j == 0 and corner_i and w >= 3:
        return None
    if j == last_j and corner_i and w >= 4 and h >= 4:
        return None
    if j == 1 and i == (1 if w == 3 else 0):
        return "EyeShine"  # (a 3-wide eye keeps its highlight inside the dark: an edge pixel melts into a pale face)
    if w >= 4 and h >= 4 and j == 1 and i == 1:
        return "EyeShine"
    if w >= 4 and j == last_j:
        return "EyeIris"
    if w >= 4 and h >= 5 and j == last_j - 1 and i == last_i - 1:
        return "EyeGlint"
    if SMALL_EYE_STYLE == "A" and j == last_j and corner_i and w >= 3:
        return None
    return "EyePupil"


def carve_eyes(cells, eyes, K, scale=1.0, inflate=0.0):
    """carve every eye one voxel into the face (like PetBuilder.carveEyes); returns lid cells per eye.
    Big enough eyes (>= 5 voxels tall) are drawn procedurally (lash rim, pupil, iris crescent, glint, two
    highlights); smaller ones (Low LOD) get a pixel eye that keeps one clear highlight."""
    fm = front_map(cells)
    lids = []
    for (cx, cy, rx0, ry0, kind, mask) in eyes:
        rx, ry = rx0 * scale + inflate, ry0 * scale + inflate
        if kind != "mask" and 2 * ry * K < 5.0:
            kind, rx, ry = "small", rx0, ry0  # pixel eyes keep the game's eye size
        lid = []
        x0, x1 = int(math.floor((cx - rx) * K)) - 1, int(math.ceil((cx + rx) * K)) + 1
        y0, y1 = int(math.floor((cy - ry) * K)) - 1, int(math.ceil((cy + ry) * K)) + 1
        rows, w = len(mask), max(len(r) for r in mask)
        mirror = cx < 0
        if kind == "small":
            w = max(2, int(round(2 * rx * K)))
            h = max(3, int(round(2 * ry * K)))
            X_hi = int(round(cx * K + (w - 1) / 2.0))  # the viewer's left column (+X)
            Y_hi = int(round(cy * K + (h - 1) / 2.0))
            x0, x1, y0, y1 = X_hi - w + 1, X_hi, Y_hi - h + 1, Y_hi
        for X in range(x0, x1 + 1):
            for Y in range(y0, y1 + 1):
                x, y = X / K, Y / K
                u, v = (x - cx) / rx, (y - cy) / ry
                if kind == "small":
                    key = _small_key(X_hi - X, Y_hi - Y, w, h)
                elif u * u + v * v > 1.0 and kind != "mask":
                    continue
                elif kind == "mask":
                    # screen column 1 = the largest x of the right eye (the viewer's left)
                    if abs(u) > 1 or abs(v) > 1:
                        continue
                    col = int((1 - u) / 2 * w) if not mirror else int((1 - u) / 2 * w)
                    row = int((1 - v) / 2 * rows)
                    col, row = min(w - 1, max(0, col)), min(rows - 1, max(0, row))
                    ch = mask[row][col] if col < len(mask[row]) else "."
                    key = EYE_KEYS.get(ch)
                elif kind != "small":
                    # the highlight sits upper-left as seen by the viewer on both eyes: no mirror
                    key = _cute_key(u, v, kind == "big")
                if not key:
                    continue
                z = fm.get((X, Y))
                if z is None:
                    continue
                was = cells.get((X, Y, z))
                if was is None or _base(was) in FLAT_EYE:
                    continue
                del cells[(X, Y, z)]
                cells[(X, Y, z + 1)] = key
                fm[(X, Y)] = z + 1
                lid.append((X, Y, z, _base(was)))
        lids.append((lid, int(round(cy * K))))
    return lids


def lid_groups(lids, single=False):
    """PetBuilder lidBoxes as cells: rows above the lash line in the lid colour, the LidLine row, rows below"""
    out = []
    for lid, line_y in lids:
        if not lid:
            out.append({})
            continue
        counts = {}
        for (_, _, _, k) in lid:
            counts[k] = counts.get(k, 0) + 1
        key = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
        g = {}
        for (x, y, z, _) in lid:
            g[(x, y, z)] = key if (single or y != line_y) else "LidLine"
        out.append(g)
    return out


FACE_KEYS = ("Blush", "Mouth", "Tongue", "Tooth")
_NB8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx, dy) != (0, 0)]


def _block(d, K):
    """voxel range covered by design cell d (cells tile without gaps at any K)"""
    return range(int(round((d - 0.5) * K)), int(round((d + 0.5) * K)))


def rescale_face_features(cells, K, keys=FACE_KEYS):
    """PetBuilder paints mouths, blush and teeth as design-unit cells with dot() (and carves the open mouth from a
    voxel mask); at a finer K the dots spread apart (gappy lines) and the masks shrink.  Re-draw them as design
    cells rasterised at K: every design cell becomes the block of voxels it covers, so strokes stay connected and
    keep their design size.  Painted cells go on the front surface, carved ones (open mouths) one voxel in."""
    if K <= 1.05:
        return
    fm = front_map(cells)
    found = {}
    for (x, y, z), k in list(cells.items()):
        b = _base(k)
        if b in keys:
            found.setdefault(b, []).append((x, y, z))
    if not found:
        return
    feature = set(keys) | FLAT_EYE

    def fill_key(x, y, z):
        counts = {}
        for dx, dy in _NB8:
            k = cells.get((x + dx, y + dy, z))
            if k is not None and _base(k) not in feature:
                counts[k] = counts.get(k, 0) + 1
        if not counts:
            return None
        return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]

    plan = []
    for key in keys:
        vox = found.get(key, [])
        if not vox:
            continue
        painted, carved = [], []
        for (x, y, z) in vox:
            deeper = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                         if fm.get((x + dx, y + dy)) is not None and fm[(x + dx, y + dy)] < z)
            (carved if (cells.get((x, y, z - 1)) is None and deeper >= 2) else painted).append((x, y, z))
        dcells = set((int(round(x / K)), int(round(y / K))) for (x, y, z) in painted)
        cc = set()
        if carved:
            top = max(y for (_, y, _) in carved)
            for (x, y, z) in carved:
                cc.add((x, int(round(top / K)) - (top - y)))
        plan.append((key, dcells, cc, vox))
    # 1) take the old feature voxels out (painted ones get the surrounding surface colour back)
    for key, dcells, cc, vox in plan:
        for (x, y, z) in vox:
            k = fill_key(x, y, z)
            if k is not None:
                cells[(x, y, z)] = k
    fm = front_map(cells)
    # 2) paint / carve the design cells at K
    for key, dcells, cc, vox in plan:
        for (dx, dy) in sorted(dcells):
            for X in _block(dx, K):
                for Y in _block(dy, K):
                    z = fm.get((X, Y))
                    if z is None:
                        continue
                    cur = cells.get((X, Y, z))
                    if cur is not None and _base(cur) in FLAT_EYE:
                        continue
                    cells[(X, Y, z)] = key
        for (dx, dy) in sorted(cc):
            for X in _block(dx, K):
                for Y in _block(dy, K):
                    z = fm.get((X, Y))
                    if z is None:
                        continue
                    cur = cells.get((X, Y, z))
                    if cur is None or _base(cur) in FLAT_EYE or _base(cur) in keys:
                        continue
                    del cells[(X, Y, z)]
                    cells[(X, Y, z + 1)] = key
                    fm[(X, Y)] = z + 1
