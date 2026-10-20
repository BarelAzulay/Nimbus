"""Colour helpers that reproduce the game's Lua maths exactly (Color3 in 0..1 sRGB floats).

PetBuilder.lua: mix = Color3:Lerp, lighten = Lerp to white, darken = Lerp to black, luminance (Rec.601).
Voxel.lua:      shade_light / shade_dark = Voxel.Lighten / Voxel.Darken (the _Light / _Dark variants).

The runtime loader (Lua) must use the same formulas, so every recipe in a manifest is expressed with these ops.
"""
import colorsys

WHITE = (1.0, 1.0, 1.0)
BLACK = (0.0, 0.0, 0.0)


def rgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


def to255(c):
    return [int(round(max(0.0, min(1.0, v)) * 255)) for v in c[:3]]


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def lighten(c, t):
    return mix(c, WHITE, t)


def darken(c, t):
    return mix(c, BLACK, t)


def luminance(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def clamp01(v):
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


# Voxel.lua shade variants -------------------------------------------------------------------------------
def shade_light(c, t=0.15):
    """Voxel.Lighten: ~15% lighter, warm highlight (NOT a multiply -> needs its own MeshPart / tint)."""
    return (clamp01(c[0] + (1 - c[0]) * t), clamp01(c[1] + (0.98 - c[1]) * t), clamp01(c[2] + (0.9 - c[2]) * t * 0.9))


def shade_dark_factor(t=0.15):
    """Voxel.Darken is a pure per-channel MULTIPLY -> exact as a vertex colour on a MeshPart (Roblox multiplies the
    vertex colour with MeshPart.Color)."""
    return (1 - t * 1.05, 1 - t, 1 - t * 0.75)


def shade_dark(c, t=0.15):
    f = shade_dark_factor(t)
    return tuple(clamp01(c[i] * f[i]) for i in range(3))


def to_hsv(c):
    return colorsys.rgb_to_hsv(*c[:3])


def from_hsv(h, s, v):
    return colorsys.hsv_to_rgb(h % 1.0, s, v)


# A tiny recipe language (JSON friendly) so the Lua loader can recompute every region colour from a pet's Look.
#   ["Primary"] / ["Secondary"] / ["Eye"] / ["WingColor"]          a Look colour
#   ["rgb", r, g, b]                                                 a constant (0-255)
#   ["mix", A, B, t] / ["lighten", A, t] / ["darken", A, t]          PetBuilder ops (A, B are recipes)
#   ["cuteIris", A] / ["cutePupil", A] / ["cuteLash", A]           PetBuilder cuteEyes (HSV based)
#   ["ifLum<", A, threshold, THEN, ELSE]                             luminance switch (pale pets etc.)
#   ["shadeLight", A]                                                Voxel.Lighten(A) (the <Key>Light parts)
#   ["headroom", A]                                                  min(1, A / 0.87) (Low parts, decision 11)
def eval_recipe(rec, look):
    op = rec[0]
    if op in ("Primary", "Secondary", "Eye", "WingColor"):
        return look[op]
    if op == "rgb":
        return rgb(rec[1], rec[2], rec[3])
    if op == "mix":
        return mix(eval_recipe(rec[1], look), eval_recipe(rec[2], look), rec[3])
    if op == "lighten":
        return lighten(eval_recipe(rec[1], look), rec[2])
    if op == "darken":
        return darken(eval_recipe(rec[1], look), rec[2])
    if op == "cuteIris":
        e = eval_recipe(rec[1], look)
        h, s, v = to_hsv(e)
        if luminance(e) < 0.4:
            return from_hsv(h, clamp(s + 0.15, 0.4, 0.75), clamp(v + 0.4, 0.5, 0.66))
        return e
    if op == "cutePupil":
        e = eval_recipe(rec[1], look)
        h, s, v = to_hsv(e)
        glow = bool(rec[2]) if len(rec) > 2 else False
        return from_hsv(h, clamp(s * 0.8 + 0.25, 0.35, 0.8), 0.2 if glow else 0.12)
    if op == "cuteLash":
        e = eval_recipe(rec[1], look)
        h, s, v = to_hsv(e)
        return from_hsv(h, clamp(s * 0.6 + 0.15, 0.2, 0.6), 0.1)
    if op == "shadeLight":
        return shade_light(eval_recipe(rec[1], look))
    if op == "headroom":
        c = eval_recipe(rec[1], look)
        return tuple(min(1.0, x / 0.87) for x in c)
    if op == "ifLum<":
        a = eval_recipe(rec[1], look)
        return eval_recipe(rec[3] if luminance(a) < rec[2] else rec[4], look)
    raise ValueError("unknown recipe op %r" % (op,))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
