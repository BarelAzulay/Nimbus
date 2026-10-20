"""Colour recipes FITTED from the game's own palette code (bridge probes), so a mesh can be recoloured per pet.

PetBuilder builds every palette colour from the pet's Look (Primary / Secondary / Eye / WingColor) with Lerp-based
helpers (mix / lighten / darken), HSV helpers (cuteEyes) and luminance switches.  Instead of porting that code, the
kit sculpts the same pet with many probe Looks (bridge.palette, coarse K: only the palette matters) and fits each
palette key to the recipe language of nvox/colors.py (the runtime's MeshLibrary.EvalColor uses the same ops):

    ["rgb", r, g, b]                 constant                     ["Primary"] (Secondary / Eye / WingColor)
    ["mix", A, B, t]                 A + (B - A) t                ["lighten", A, t] / ["darken", A, t]
    ["cuteIris"|"cuteLash", E]       ["cutePupil", E, glow]       ["ifLum<", A, threshold, THEN, ELSE]

Fit order: constant -> one atom (w * A + b) -> two atoms -> a luminance switch on one Look colour with a threshold
taken from the Lua source, each side fitted again.  Every candidate is checked on ALL probes (max error <= 2/255).
A key that fits nothing keeps the reference colour as a constant and is reported (manifest "colorFit").
"""
import itertools
import math
import os
import random
import re

import numpy as np

from . import colors as C

LOOK_ATOMS = ("Primary", "Secondary", "Eye", "WingColor")
TOL = 1.6 / 255
_THRESH = None


def lua_thresholds(repo):
    """luminance thresholds used by the Lua palette code (luminance(x) < 0.3 ...)"""
    global _THRESH
    if _THRESH is None:
        found = set()
        for f in ("src/shared/PetBuilder.lua",):
            txt = open(os.path.join(repo, f), encoding="utf-8").read()
            for m in re.finditer(r"luminance\([^)]*\)\s*[<>]=?\s*([0-9.]+)", txt):
                found.add(round(float(m.group(1)), 3))
        _THRESH = sorted(found) or [0.3, 0.45]
    return _THRESH


def _rand_color(rng, lum):
    """a random colour with roughly the given luminance (Rec.601)"""
    for _ in range(40):
        h, s = rng.random(), rng.random() ** 0.7
        v = min(1.0, max(0.02, lum / max(0.05, 0.299 * 0.6 + 0.587 * 0.7 + 0.114 * 0.5)))
        c = C.from_hsv(h, s, rng.random())
        L = C.luminance(c)
        if L > 1e-3:
            k = lum / L
            c2 = tuple(min(1.0, x * k) for x in c)
            if abs(C.luminance(c2) - lum) < 0.03:
                return c2
    return (lum, lum, lum)


def probe_looks(n=40, seed=7, thresholds=(0.3, 0.45)):
    """deterministic probe Looks; luminances spread over 0..1 and packed around every threshold"""
    rng = random.Random(seed)
    lums = [i / (n - 1) for i in range(n)]
    looks = []
    for i in range(n):
        lk = {}
        for j, a in enumerate(LOOK_ATOMS):
            L = lums[(i * (j * 7 + 3) + j * 11) % n]
            lk[a] = _rand_color(rng, 0.03 + 0.94 * L)
        looks.append(lk)
    for th in thresholds:
        for d in (-0.04, -0.012, 0.012, 0.04):
            for a in LOOK_ATOMS:
                lk = {b: _rand_color(rng, 0.2 + 0.6 * rng.random()) for b in LOOK_ATOMS}
                lk[a] = _rand_color(rng, min(0.98, max(0.02, th + d)))
                looks.append(lk)
    return looks


def to255(look):
    return {k: [int(round(x * 255)) for x in v] for k, v in look.items()}


def quantize(look):
    """the probe colours as the game sees them (Color3.fromRGB bytes)"""
    return {k: tuple(int(round(x * 255)) / 255 for x in v) for k, v in look.items()}


def atom_values(name, look, glow=False):
    if name in LOOK_ATOMS:
        return np.array(look[name], float)
    if name == "cuteIris":
        return np.array(C.eval_recipe(["cuteIris", ["Eye"]], look), float)
    if name == "cutePupil":
        return np.array(C.eval_recipe(["cutePupil", ["Eye"], False], look), float)
    if name == "cutePupilGlow":
        return np.array(C.eval_recipe(["cutePupil", ["Eye"], True], look), float)
    if name == "cuteLash":
        return np.array(C.eval_recipe(["cuteLash", ["Eye"]], look), float)
    raise KeyError(name)


def atom_recipe(name, glow=False):
    if name in LOOK_ATOMS:
        return [name]
    if name == "cutePupil":
        return ["cutePupil", ["Eye"], False]
    if name == "cutePupilGlow":
        return ["cutePupil", ["Eye"], True]
    return [name, ["Eye"]]


ATOMS = LOOK_ATOMS + ("cuteIris", "cutePupil", "cutePupilGlow", "cuteLash")


def _affine_to_recipe(names, w, b, glow):
    """sum w_i * atom_i + b  ->  nested mix recipe, or None when it is not expressible with mix/rgb"""
    w = [float(x) for x in w]
    b = np.asarray(b, float)
    if any(x < -1e-4 for x in w):
        return None
    s = sum(w)
    if s > 1 + 1e-3:
        return None
    inner = None
    acc = 0.0
    for nm, wi in zip(names, w):
        if wi <= 1e-5:
            continue
        r = atom_recipe(nm, glow)
        if inner is None:
            inner, acc = r, wi
        else:
            acc += wi
            inner = ["mix", inner, r, round(wi / acc, 5)]
    if inner is None:
        return ["rgb"] + [int(round(x * 255)) for x in np.clip(b, 0, 1)]
    if s > 1 - 1e-4:
        return inner if np.abs(b).max() < 1e-3 else None
    t = 1 - s
    cst = b / t
    if (cst < -0.01).any() or (cst > 1.01).any():
        return None
    cst = np.clip(cst, 0, 1)
    rgb = [int(round(x * 255)) for x in cst]
    if rgb == [0, 0, 0]:
        return ["darken", inner, round(t, 5)]
    if rgb == [255, 255, 255]:
        return ["lighten", inner, round(t, 5)]
    return ["mix", inner, ["rgb"] + rgb, round(t, 5)]


def _check(rec, looks, Y):
    try:
        got = np.array([C.eval_recipe(rec, lk) for lk in looks], float)
    except Exception:
        return math.inf
    return float(np.abs(got - Y).max())


def _fit_affine(names, looks, Y, glow):
    X = np.array([[atom_values(n, lk, glow) for n in names] for lk in looks], float)  # (N, A, 3)
    N = len(looks)
    # unknowns: w (A, shared over channels) + b (3)
    rows, rhs = [], []
    for i in range(N):
        for ch in range(3):
            row = np.zeros(len(names) + 3)
            row[:len(names)] = X[i, :, ch]
            row[len(names) + ch] = 1.0
            rows.append(row)
            rhs.append(Y[i, ch])
    sol, *_ = np.linalg.lstsq(np.array(rows), np.array(rhs), rcond=None)
    w, b = sol[:len(names)], sol[len(names):]
    # snap tiny / round numbers (the Lua uses 2-3 decimal constants)
    w = np.where(np.abs(w) < 2e-4, 0.0, w)
    return w, b


def fit_one(looks, Y, glow=False, allow_switch=True, thresholds=(0.3,)):
    """recipe for one palette key from probe colours Y (N, 3); (recipe, max error)"""
    Y = np.asarray(Y, float)
    if np.abs(Y - Y[0]).max() <= TOL:
        rec = ["rgb"] + [int(round(x * 255)) for x in Y.mean(0)]
        return rec, _check(rec, looks, Y)
    best = (None, math.inf)
    for n_atoms in (1, 2, 3):
        level = (None, math.inf)
        for names in itertools.combinations(ATOMS, n_atoms):
            if sum(1 for n in names if n not in LOOK_ATOMS) > 1:
                continue
            w, b = _fit_affine(names, looks, Y, glow)
            rec = _affine_to_recipe(names, w, b, glow)
            if rec is None:
                continue
            err = _check(rec, looks, Y)
            if err < level[1]:
                level = (rec, err)
        if level[1] < best[1]:
            best = level
        if level[1] <= TOL:
            return level
    if allow_switch:
        for a in LOOK_ATOMS:
            lum = np.array([C.luminance(lk[a]) for lk in looks])
            for th in thresholds:
                lo, hi = lum < th, lum >= th
                if lo.sum() < 3 or hi.sum() < 3:
                    continue
                r_lo, e_lo = fit_one([lk for lk, m in zip(looks, lo) if m], Y[lo], glow, False)
                if e_lo > TOL:
                    continue
                r_hi, e_hi = fit_one([lk for lk, m in zip(looks, hi) if m], Y[hi], glow, False)
                if e_hi > TOL:
                    continue
                rec = ["ifLum<", [a], th, r_lo, r_hi]
                err = _check(rec, looks, Y)
                if err <= TOL:
                    return rec, err
    return best


class RecipeFitter:
    """Fits every palette key of one pet (and stage) once; cached per (pet, stage)."""

    def __init__(self, bridge, repo, n=40, seed=7):
        self.bridge = bridge
        self.repo = repo
        self.n, self.seed = n, seed
        self.cache = {}

    def fit(self, pet_id, stage=0, detail="High", look_extra=None, glow=False):
        ck = (pet_id, stage, detail, repr(sorted((look_extra or {}).items())))
        if ck in self.cache:
            return self.cache[ck]
        ths = lua_thresholds(self.repo)
        looks = [quantize(lk) for lk in probe_looks(self.n, self.seed, ths)]
        pals = []
        for lk in looks:
            req = to255(lk)
            if look_extra:
                req.update(look_extra)
            pals.append(self.bridge.palette(pet_id, look=req, stage=stage, detail=detail))
        keys = sorted(set().union(*[set(p) for p in pals]))
        out = {}
        for key in keys:
            if not all(key in p for p in pals):
                out[key] = {"recipe": None, "error": None, "note": "key missing on some probe looks"}
                continue
            Y = np.array([p[key][:3] for p in pals], float)
            mats = sorted(set(p[key][3] for p in pals))
            rec, err = fit_one(looks, Y, glow, True, ths)
            out[key] = {"recipe": rec, "error": round(float(err), 5) if err != math.inf else None,
                        "ok": err <= TOL, "materials": mats}
        self.cache[ck] = out
        return out
