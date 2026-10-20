"""art-pets detail passes for the base pet bodies (Phase 6 W2, recipe 4.1 "detail passes").

Catalog entries name them as "passes": ["pets:cute"]; build_pet_body runs them on the Body group's cells after the
Lua face is restored and the mouth / blush / teeth are re-drawn at the mesh K, and BEFORE the procedural eyes are
carved (faces.carve_eyes), so nothing here may touch the eye area.

    cute(bp, cells, entry)   soft round cheeks, toe lines on the paw fronts, paw pads on the soles, a small fur tuft

Rules (the runtime name contract, recipe 4.3 / 4.4):
  * only palette keys the pet already has (a new key would have no colour recipe); shade variants are the
    `<Key>_Light` / `<Key>_Dark` suffixes Voxel.Shade uses, so the dark toe lines stay in the paw's own MeshPart
    (vertex colour) and no new MeshPart appears;
  * cells are recoloured or added, never removed from the outline, so every group stays closed;
  * deterministic: no RNG, every loop runs over sorted cells.
Coordinates: (x, y, z) voxels at the mesh K (design unit x K), +Y up, the pet faces -Z, x > 0 is the pet's right.
Options per entry: "cute": {"cheeks": bool, "toes": bool, "pads": bool, "tuft": bool} (all default on where the
species table allows them), plus the MeshPart economy used to keep a catalog set at <= 40 MeshParts (recipe 4.2):
"merge": {"Inner": "Blush"} paints one key with a near-identical one (one part fewer), "foldLight": ["Accent"] folds
a minor key's light shade into its base (no `<Key>Light` part).
"""
from detail.faces import FLAT_EYE, _base, front_map

# species -> which details suit it (a frog has no toes to split, a slime has no feet, the armoured lynx keeps its
# plates clean; owls / phoenixes / penguins have bird feet)
SPECIES = {
    "Dog": {"tuft": "Fur", "toes": True, "pads": True},
    "Cat": {"tuft": "Fur", "toes": True, "pads": True},
    "Fox": {"tuft": "Fur", "toes": True, "pads": True},
    "Bunny": {"toes": True, "pads": True},
    "Bear": {"toes": True, "pads": True},
    "Panda": {"toes": True, "pads": True},
    "Penguin": {"tuft": "Fur"},
    "Unicorn": {"toes": False},
    "Dragon": {"toes": True},
    "Owl": {},
    "Phoenix": {},
    "Slime": {},
    "Frog": {},
    "Axolotl": {"toes": True},
    "Stormfang": {"cheeks": False},
}
FACE = FLAT_EYE | {"Mouth", "Tongue", "Tooth", "Nose", "Nostril", "Blush", "Lash", "LidLine", "Lid", "Beak",
                   "BeakLow", "Spark", "Horn", "Gold", "GoldDeep", "Inner"}
SKIN_DARK_OK = ("_Light", "")


def _opts(bp, entry):
    sp = SPECIES.get(bp.species, {})
    o = dict(entry.get("cute") or {})
    return {
        "cheeks": o.get("cheeks", sp.get("cheeks", True)),
        "toes": o.get("toes", sp.get("toes", False)),
        "pads": o.get("pads", sp.get("pads", False)) and entry.get("lod", "High") != "Low",
        "tuft": o.get("tuft", True) and sp.get("tuft"),
    }


def _has_key(bp, key):
    return key in (bp.palette or {})


# ----------------------------------------------------------------------------------------------- soft cheeks
def soft_cheeks(bp, cells, K, eyes):
    """the Lua blush is a short stroke of design cells at the face's edge; make each cheek a soft round oval
    (wider than tall) on the face front just under and a little outside each eye (the kawaii placement), kept
    clear of the eyes, mouth and nose; the old stroke goes back to the surrounding face colour"""
    if not _has_key(bp, "Blush") or not eyes:
        return 0
    old = sorted(p for p, k in cells.items() if _base(k) == "Blush")
    for p in old:
        cells[p] = _surround(cells, p)
    fm = front_map(cells)
    rx = max(1.5, 2.0 * K)  # voxels: ~4 x 2.5 design units
    ry = max(1.0, 1.25 * K)
    boxes = [_eye_box(e, K) for e in eyes]
    made = 0
    for (ecx, ecy, erx, ery, kind, mask) in eyes:
        cx = (ecx + (0.45 if ecx > 0 else -0.45) * erx) * K
        cy = (ecy - ery * 1.0 - 1.5) * K
        zc = fm.get((int(round(cx)), int(round(cy))))
        if zc is None:
            continue
        for X in range(int(cx - rx) - 1, int(cx + rx) + 2):
            for Y in range(int(cy - ry) - 1, int(cy + ry) + 2):
                u, v = (X - cx) / rx, (Y - cy) / ry
                if u * u + v * v > 1.0:
                    continue
                if any(x0 <= X <= x1 and y0 <= Y <= y1 for (x0, x1, y0, y1) in boxes):
                    continue
                z = fm.get((X, Y))
                if z is None or abs(z - zc) > 2:
                    continue  # only the face plane (not the head's side)
                cur = cells.get((X, Y, z))
                if cur is None or _base(cur) in FACE:
                    continue
                cells[(X, Y, z)] = "Blush"
                made += 1
    return made


def _eye_box(e, K):
    cx, cy, rx, ry = e[0], e[1], e[2], e[3]
    return (int((cx - rx * 1.12) * K), int((cx + rx * 1.12) * K),
            int((cy - ry * 1.12) * K), int((cy + ry * 1.12) * K))


def _surround(cells, p):
    x, y, z = p
    counts = {}
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)):
        k = cells.get((x + dx, y + dy, z))
        if k is not None and _base(k) not in FACE:
            counts[k] = counts.get(k, 0) + 1
    if not counts:
        return cells[p]
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]


# ----------------------------------------------------------------------------------------------- paws
def _paws(cells):
    """the feet: connected footprints (x, z) of the lowest layer (the rounded paw bottoms) -> (y0, [comp])"""
    y0 = min(p[1] for p in cells)
    foot = set((x, z) for (x, y, z) in cells if y == y0)
    seen, out = set(), []
    for start in sorted(foot):
        if start in seen:
            continue
        stack, comp = [start], []
        seen.add(start)
        while stack:
            c = stack.pop()
            comp.append(c)
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (c[0] + d[0], c[1] + d[1])
                if n in foot and n not in seen:
                    seen.add(n)
                    stack.append(n)
        out.append(sorted(comp))
    return y0, out


def toe_lines(bp, cells, K, main_key):
    """two short vertical grooves on the front of every paw: three little toes, like the approved pup preview
    (the dark shade of the paw's own key, so no new MeshPart).  The paw is found from its rounded bottom (one
    footprint of the lowest layer); its front is the frontmost cell of each column in the lowest ~1.3 units."""
    y0, paws = _paws(cells)
    y1 = y0 + max(1, int(round(1.3 * K)))
    made = 0
    for comp in paws:
        xs = [x for x, _ in comp]
        zs = [z for _, z in comp]
        x_lo, x_hi = min(xs) - 1, max(xs) + 1  # the bottom is rounded: the paw is a voxel wider each side
        w = x_hi - x_lo + 1
        if w < 5:
            continue  # too small to split (Low LOD, bird feet)
        z_lo, z_hi = min(zs) - 3, max(zs) + 1
        for frac in (1 / 3.0, 2 / 3.0):
            X = x_lo + int(round(w * frac - 0.5))
            for Y in range(y0, y1 + 1):
                col = [z for z in range(z_lo, z_hi + 1) if (X, Y, z) in cells]
                if not col:
                    continue
                p = (X, Y, col[0])
                cur = cells[p]
                b = _base(cur)
                if b in FACE:
                    continue
                cells[p] = (b + "_Dark") if not cur.endswith("_Dark") else main_key
                made += 1
    return made


def paw_pads(bp, cells, K):
    """a pink bean in the middle of every sole: the paw-bottom cells with neighbours on all four sides (they show
    their bottom face alone, so the paw's sides keep their colour)"""
    if not _has_key(bp, "Blush") or K < 1.0:
        return 0
    y0, paws = _paws(cells)
    made = 0
    for comp in paws:
        cs = set(comp)
        for (x, z) in comp:
            if all((x + dx, z + dz) in cs for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))) and \
                    (x, y0 + 1, z) in cells and _base(cells[(x, y0, z)]) not in FACE:
                cells[(x, y0, z)] = "Blush"
                made += 1
    return made


# ----------------------------------------------------------------------------------------------- tuft
# a cowlick drawn in the head's YZ plane (design units: dz forward is negative, dy up), root to tip
TUFT = ((0.0, 0.5), (0.0, 1.2), (-0.4, 1.9), (-1.1, 2.4), (-1.9, 2.4), (-2.5, 1.9))


def fur_tuft(bp, cells, K, key):
    """a little hooked cowlick on top of the head (3 voxels wide at the root, 1 at the tip), in the light shade of
    the head-top's key"""
    if not _has_key(bp, key):
        return 0
    a = bp.anchors or {}
    hc = a.get("HeadC") or [0, 6.5, -0.5]
    zc = int(round(float(hc[2]) * K))
    best = None
    for (x, y, z), k in sorted(cells.items()):
        if x in (0, -1) and abs(z - zc) <= 1 and _base(k) == key:
            if best is None or y > best[1]:
                best = (x, y, z)
    if best is None:
        return 0
    _, top, z0 = best
    if any(p[1] > top and abs(p[0]) <= 2 and abs(p[2] - z0) <= 2 for p in cells):
        return 0  # something already sits there (ears that meet, a crest)
    shade = key + "_Light"
    made = 0
    pts = []
    n = len(TUFT)
    for i, (dz, dy) in enumerate(TUFT):
        Y = top + max(1, int(round(dy * K)))
        Z = z0 + int(round(dz * K))
        xs = (-1, 0, 1) if i < n - 3 else (0,)  # 3 voxels wide at the root, 1 at the hooked tip
        for X in xs:
            pts.append((X, Y, Z))
    # fill the gaps between consecutive points (a connected strand at any K)
    full = []
    for p, q in zip(pts, pts[1:]):
        full.append(p)
        if abs(q[1] - p[1]) + abs(q[2] - p[2]) > 1:
            full.append((p[0], q[1], p[2]))
    full.append(pts[-1])
    for p in full:
        if p not in cells:
            cells[p] = shade
            made += 1
    return made


# ----------------------------------------------------------------------------------------------- part economy
def economy(cells, opts):
    """merge near-identical keys / fold minor light shades (see the module doc); deterministic, recolour only"""
    merge = opts.get("merge") or {}
    fold = set(opts.get("foldLight") or [])
    if not merge and not fold:
        return 0
    n = 0
    for p in sorted(cells):
        k = cells[p]
        b = _base(k)
        if b in merge:
            cells[p] = merge[b] + ("_Dark" if k.endswith("_Dark") else "")
            n += 1
        elif b in fold and k.endswith("_Light"):
            cells[p] = b
            n += 1
    return n


# ----------------------------------------------------------------------------------------------- entry
def cute(bp, cells, entry):
    """soft round cheeks + toe lines + paw pads + a fur tuft (per species, see SPECIES)"""
    if not cells:
        return {}
    K = float(bp.K)
    o = _opts(bp, entry)
    main = "Fur" if _has_key(bp, "Fur") else _base(sorted(cells.values())[0])
    stats = {}
    economy(cells, (entry.get("cute") or {}))
    if o["cheeks"]:
        from detail.faces import eye_specs
        stats["cheeks"] = soft_cheeks(bp, cells, K, eye_specs(bp))
    if o["toes"]:
        stats["toes"] = toe_lines(bp, cells, K, main)
    if o["pads"]:
        stats["pads"] = paw_pads(bp, cells, K)
    if o["tuft"]:
        stats["tuft"] = fur_tuft(bp, cells, K, o["tuft"])
    return stats
