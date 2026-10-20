"""art-pets: hybrid feature keys hyb_<style> (Phase 6 W2; PetBuilder HYBRID.* + applyHybrid through the bridge).

A fused hybrid is its Body parent's species with the Style parent's signature feature grown out of the body surface
(fox tail + cheek ruffs, bunny ears, unicorn horn + mane, cat tabby bands ...).  The kit has no hybrid key type, so a
hyb_<style> key is a `pet` entry of the reference body with a hybrid Look plus this pass:

    {"key": "hyb_fox", "type": "pet", "pet": "pebble_pup", "look": {"Hybrid": true, "StyleId": "maple_fox",
     "Seed": 7}, "passes": ["pets_hyb:isolate"], ...}

`isolate` keeps only what the hybrid adds to the plain reference body:
  * every voxel the feature grows (ears, ruffs, horn, mane, crest, gills ...) with its own palette key;
  * the feature's PAINTED patterns (tabby bands, spots, eye patches, tuxedo, a penguin's feet: any key the hybrid
    paints over the plain body's voxels, Hy* or not; face keys excepted) raised one fine voxel off the body
    surface (they would z-fight as a recolour of the body's own voxels in a separate mesh); never in front of the eyes;
  * the hybrid's own tail group when the trait swaps the tail (else the Tail group is dropped: the body key's tail
    stays);
  * no eyes, no lids (bp.eyes is emptied, so faces.carve_eyes does nothing).
The model pivot is the reference body's root (`Body`), and the manifest carries the reference body's attachments
(HeadCenter, Hat, Neck, Tail ...), so the runtime can map head features and the tail onto other species' anchors.
Hy* keys (HyA / HyB / HyTip / HyHorn / HyGlow) depend on the Style parent's Primary + the hybrid seed, which the
Look recipe ops cannot express: their manifest colour is the reference hybrid's constant; the runtime sets them from
PetBuilder's hybrid palette.  Deterministic (fixed Seed in the catalog, sorted loops).
"""
from detail.faces import _base, eye_specs, front_map, rescale_face_features, restore_carved_eyes

HY_KEYS = ("HyA", "HyB", "HyTip", "HyHorn", "HyGlow")
# keys a hybrid never paints as a feature (eye / lid / mouth carving can differ by a voxel between the hybrid and the
# plain body: those differences are not part of the feature)
FACE_ONLY = frozenset(("EyeIris", "EyePupil", "EyeShine", "EyeGlint", "EyeRing", "Lash", "Lid", "LidLine", "Mouth",
                       "Tongue", "Tooth", "Nose", "Blush"))
LOOK_HYBRID = ("Hybrid", "StyleId", "Seed", "BodyId")
_BRIDGE = []


def _bridge():
    if not _BRIDGE:
        from bridge import Bridge
        _BRIDGE.append(Bridge())
    return _BRIDGE[0]


def _cells(g):
    if g is None:
        return {}
    return {(int(x), int(y), int(z)): k for (x, y, z), k in zip(g.xyz.tolist(), g.keys)}


def plain_blueprint(bp, entry):
    """the same reference pet at the same K without the hybrid Look fields"""
    look = dict(entry.get("look") or {})
    for f in LOOK_HYBRID:
        look.pop(f, None)
    for f in entry.get("strip", []):
        look[f] = False
    return _bridge().pet(entry["pet"], k=float(bp.K), stage=int(entry.get("stage", 0)),
                         detail=entry.get("detail", "High"), look=look, want_pre=False)


def _in_eyes(bp, K, x, y, pad=1.2):
    for (cx, cy, rx, ry, kind, mask) in eye_specs(bp):
        u = (x / K - cx) / (rx * pad)
        v = (y / K - cy) / (ry * pad)
        if u * u + v * v <= 1.0:
            return True
    return False


def isolate(bp, cells, entry):
    """reduce the Body cells to the hybrid feature (see the module doc); returns counts"""
    K = float(bp.K)
    plain = plain_blueprint(bp, entry)
    base = _cells(plain.group("Body"))
    restore_carved_eyes(base, plain.lid_cells)
    opts = entry.get("face", {})
    if opts.get("features", True):
        rescale_face_features(base, plain.K)
    added = {}
    for p in sorted(cells):
        if p not in base:
            added[p] = cells[p]
    raised = {}
    for p in sorted(cells):
        k = cells[p]
        if p not in base or _base(k) == _base(base[p]) or _base(k) in FACE_ONLY:
            continue
        if _base(k) not in HY_KEYS and not entry.get("raiseAll", True):
            continue
        x, y, z = p
        for d in ((0, 0, -1), (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1), (0, -1, 0)):
            q = (x + d[0], y + d[1], z + d[2])
            if q in cells or q in added or q in raised:
                continue
            if d[2] == -1 and _in_eyes(bp, K, x, y):
                continue  # the eye patch frames the eye, it never covers it
            raised[q] = k
    # nothing may sit in front of the eyes (the Lua carve of a patched face can differ from the plain one by a
    # voxel, which would leave a stray layer over the eye)
    fm = front_map(base)
    out = {}
    for p, k in list(added.items()) + list(raised.items()):
        x, y, z = p
        front = fm.get((x, y))
        if _in_eyes(bp, K, x, y, pad=1.25) and (front is None or z <= front):
            continue
        out[p] = k
    cells.clear()
    cells.update(out)
    # keep the tail only when the trait grew its own (hyTail); drop groups identical to the plain body's
    keep = []
    for g in bp.groups:
        if g.name == "Body":
            keep.append(g)
            continue
        pg = plain.group(g.name)
        if pg is not None and _cells(pg) == _cells(g):
            continue
        keep.append(g)
    bp.groups = keep
    bp.eyes = []  # no eyes / lids in a feature key
    return {"added": len(added), "raised": len(raised), "kept": len(out), "groups": [g.name for g in keep]}
