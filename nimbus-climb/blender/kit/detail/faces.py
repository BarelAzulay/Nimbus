"""Face detail pass for bridge pets: the Lua eyes are fixed-pixel masks (they shrink at a finer mesh K), so the
kit puts the carved face back, then carves PROCEDURAL eyes sized in design units (they gain detail with K) and makes
the blink lids from what it carved.

API (cells = dict (x, y, z) -> palette key of the Body group, sculpted voxels at mesh K):
    restore_carved_eyes(cells, lid_cells, strict)    undo PetBuilder.carveEyes (uses bp.lid_cells)
    eyes = eye_specs(bp)                             [(cx, cy, rx, ry, kind, mask)] design units, one per eye
    eyes = low_eye_specs(bp, high_k)                 the same, drawing the game's Low eye masks 1:1 (kind "pixel"),
                                                     placed against the High mesh's eye (low_eye_place)
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


def _face_lid_key(k, strict=False):
    """a lid cell's key that is the face colour it covered: not the LidLine / Lid placeholders.  strict (the evolved
    Low keys, face eyes 'low'): not an eye key either (where two of the game's fixed-pixel eyes overlap - a big High
    eye on a coarse Low grid - the second eye was carved into the first and recorded the first eye's key as its lid;
    restored, those showed as stray eye pixels around the Low eye), except EyeRing: a painted ring under the eye (the
    evolved owls' gold disc) is face colour"""
    if k in ("LidLine", "Lid"):
        return False
    return not strict or _base(k) not in FLAT_EYE or _base(k) == "EyeRing"


def restore_carved_eyes(cells, lid_cells, strict=False):
    """PetBuilder.carveEyes moved every eye voxel one step back: put the face surface back.  strict: see
    _face_lid_key (the default keeps every other key's restore exactly as before)."""
    for eye in lid_cells:
        col_key = {}
        for (x, y, z, k) in eye:
            if _face_lid_key(k, strict):
                col_key.setdefault(x, k)
        for (x, y, z, k) in eye:
            key = k if _face_lid_key(k, strict) else col_key.get(x) or next(iter(col_key.values()), "Fur")
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


def low_eye_place(x_outer, y_top, mask, w, h, K, high_k, Y0, fits=None):
    """(R, Y): the outer column (voxels at K, > 0) and the top row of a w x h Low eye, against the High eye of the
    pet's High mesh: PetBuilder carves the High `mask` at high_k with its outer column at vx(x_outer) and its top row
    at vx(y_top) (design units).  The Low eye is wider than the High one (4 coarse voxels against 6 fine ones), so
    it cannot match both edges: it keeps at least half the High eyes' spacing (a single gap column put the nose
    against both eyes and the eye onto the snout) and, among those columns, sits nearest the High eye's centre; the
    row is the one nearest the High eye's centre (look review of 5cb4b2e: centred on eye_specs' design centre, which
    reads the 8 x 9 High mask grid as design units, the pair sat up to 1.4 Low voxels inside the High eye, cross-eyed,
    and up to 1.1 below it).  fits(R, Y): the whole eye lands on the face; a narrow head (evo1 obsidian phoenix: 9
    voxels wide) gives up the spacing before the fit.  Y0: the row eye_specs gives (the search is around it)."""
    X_h = int(math.floor(abs(x_outer) * high_k + 0.5))
    Y_h = int(math.floor(y_top * high_k + 0.5))
    xs = [X_h - c for c in range(max(len(r) for r in mask)) if any(c < len(r) and r[c] in EYE_KEYS for r in mask)]
    ys = [Y_h - r for r, line in enumerate(mask) if any(ch in EYE_KEYS for ch in line)]
    inner, outer = (min(xs) - 0.5) / high_k, (max(xs) + 0.5) / high_k  # design units (High and Low share the grow)
    cy = (min(ys) + max(ys)) / 2.0 / high_k
    best = None
    for R in range(w, w + 64):
        spaced = 2 * (R - w + 0.5) / K >= inner - 1e-9  # the Low gap >= half the High gap
        dx = abs((R - (w - 1) / 2.0) / K - (inner + outer) / 2.0)
        for Y in range(Y0 - 6, Y0 + 7):
            fit = fits is None or fits(R, Y)
            dy = abs((Y - (h - 1) / 2.0) / K - cy)
            score = (not fit, not spaced, round(dx, 9), round(dy, 9))
            if best is None or score < best[0]:
                best = (score, R, Y)
    return best[1], best[2]


def low_eye_specs(bp, high_k=None, cells=None):
    """face option {"eyes": "low"} (the evolved Low LOD keys): every eye that has a Low version in the game
    (PetBuilder EYE_MASKS <kind>Low, exported as LowMask by the bridge) is drawn with it, one mesh voxel per mask
    pixel.  Scaling a big High mask down to a coarse grid drops whole rows and columns (Pitch 2 item 7: the 6 x 7
    evolved eye lost its lash, glint or pupil at K 0.65); the game's own Low eye keeps every feature (lash, highlight,
    pupil, iris, glint, the fierce slant).  high_k (face option highK, the pet's High mesh K) places it by
    low_eye_place, on the face `cells` (the body before the carve); without it (or without the eye's XOuter / YTop)
    it is centred where eye_specs puts the High eye.  Eyes without a Low mask keep their eye_specs entry."""
    out = []
    fm = front_map(cells) if cells is not None else None
    for e, spec in zip(bp.eyes, eye_specs(bp)):
        low = e.get("LowMask")
        if not low:
            out.append(spec)
            continue
        w, h = max(len(r) for r in low), len(low)
        cx, cy = spec[0], spec[1]
        xo, yt = e.get("XOuter"), e.get("YTop")
        if high_k and xo is not None and yt is not None:
            def fits(R, Y, xo=xo, low=low, w=w):
                X_hi = R if xo > 0 else -R + w - 1
                return fm is None or all((X_hi - i, Y - j) in fm for j, line in enumerate(low)
                                         for i, ch in enumerate(line) if ch in EYE_KEYS)
            R, Y = low_eye_place(xo, yt, e["Mask"], w, h, bp.K, float(high_k), _pixel_box(cx, cy, w, h, bp.K)[1], fits)
            # _pixel_box gives back column R and row Y
            cx, cy = math.copysign((R - (w - 1) / 2.0) / bp.K, xo), (Y - (h - 1) / 2.0) / bp.K
        out.append((cx, cy, w / 2.0, h / 2.0, "pixel", list(low)))
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


def _pixel_box(cx, cy, w, h, K):
    """(X_hi, Y_hi): the viewer's-left column (+X) and the top row of a w x h pixel eye centred on (cx, cy).  The
    left eye (cx < 0) is placed as the exact mirror of a right eye at -cx, so the pair stays symmetric about x = 0
    even where the rounding hits a .5; eyes set close together (the phoenixes) keep the x = 0 column between them
    instead of sharing it"""
    Y_hi = int(round(cy * K + (h - 1) / 2.0))
    right = max(int(round(abs(cx) * K + (w - 1) / 2.0)), w)
    return (right if cx >= 0 else -right + w - 1), Y_hi


def carve_eyes(cells, eyes, K, scale=1.0, inflate=0.0):
    """carve every eye one voxel into the face (like PetBuilder.carveEyes); returns lid cells per eye.
    Big enough eyes (>= 5 voxels tall) are drawn procedurally (lash rim, pupil, iris crescent, glint, two
    highlights); smaller ones (Low LOD) get a pixel eye that keeps one clear highlight; "pixel" specs
    (low_eye_specs) draw their mask one voxel per pixel, and a painted EyeRing under a "pixel" eye (the evolved owls'
    gold disc) is a backdrop it is carved into, as PetBuilder.carveEyes does at High (the other kinds still skip
    every eye key, so their keys carve as before)."""
    fm = front_map(cells)
    lids = []
    carved = set()  # (X, Y) carved by this call: never carved twice, even where the eye left an EyeRing pixel
    for (cx, cy, rx0, ry0, kind, mask) in eyes:
        rx, ry = rx0 * scale + inflate, ry0 * scale + inflate
        if kind not in ("mask", "pixel") and 2 * ry * K < 5.0:
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
        elif kind == "pixel":
            X_hi, Y_hi = _pixel_box(cx, cy, w, rows, K)
            x0, x1, y0, y1 = X_hi - w + 1, X_hi, Y_hi - rows + 1, Y_hi
        for X in range(x0, x1 + 1):
            for Y in range(y0, y1 + 1):
                x, y = X / K, Y / K
                u, v = (x - cx) / rx, (y - cy) / ry
                if kind == "pixel":
                    # screen column 1 of the mask = the viewer's left (the largest x), row 1 = the top
                    line = mask[Y_hi - Y]
                    i = X_hi - X
                    key = EYE_KEYS.get(line[i]) if i < len(line) else None
                elif kind == "small":
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
                ring = kind == "pixel" and _base(was or "") == "EyeRing"
                if was is None or (X, Y) in carved or (_base(was) in FLAT_EYE and not ring):
                    continue
                del cells[(X, Y, z)]
                cells[(X, Y, z + 1)] = key
                fm[(X, Y)] = z + 1
                carved.add((X, Y))
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
