"""Pet attack VFX flipbook sheets (spec docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md, style A).

    blender.exe -b -P blender/vfx/render_textures.py -- --out blender/vfx/out [--key fx_flame ...]

Reads blender/vfx/textures.json and renders one 1024x1024 RGBA PNG per key: 16 frames in a 4x4 grid (left to right,
top to bottom; Roblox FlipbookLayout Grid4x4). Every key is ONE EEVEE render: an orthographic camera looks down on a
4 x 4 unit board, and each frame's geometry sits in its own 1 x 1 cell. All looks are emission shaders over a
transparent film: a white-hot core -> the element colour (Config.Elements) -> a soft edge, built as node trees by the
small expression helpers below (S = a float socket; + - * / ** make Math nodes). Flat planes carry shader "fields"
(flame, rings, slash...), small planes carry sprites (embers, petals...), strips carry bolts and cracks, and real 3D
meshes (voxel rock chunks, ice shards, glass) are toon shaded from their normals with an inverted-hull outline.
Per-object custom properties t / a / c / b / s feed the shaders (Attribute node, type Object).

After the render: pixels within 2 px of a cell border are cleared (a frame must never bleed into its neighbour;
the bleed is logged), then every alpha-0 pixel gets RGB (30, 38, 72) (never a gray checkerboard; Storm Altar lesson),
and the sheet is written with a tiny deterministic PNG writer. Fixed seeds: the same script gives the same pixels.
Check with: py -3.12 tools/vfx_textures_check.py   (contact sheet: --sheet)
"""
import json
import math
import os
import random
import struct
import sys
import time
import zlib

import bmesh
import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "textures.json")
SIZE = 1024
GRID = 4
CELL = SIZE // GRID
DARK = (30, 38, 72)
TAU = 2.0 * math.pi
SEED = 20261023

EL = {
    "Water": (64, 148, 236), "Flame": (240, 108, 56), "Frost": (150, 222, 248), "Nature": (104, 190, 86),
    "Earth": (178, 128, 80), "Storm": (110, 128, 255), "Celestial": (255, 212, 104), "Shadow": (128, 72, 178),
}
WHITE = (255, 255, 255)


# ---------------------------------------------------------------- colour helpers
def _lin1(v):
    v = v / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def lin(c):
    return (_lin1(c[0]), _lin1(c[1]), _lin1(c[2]), 1.0)


def blend(a, b, f):
    return tuple(a[i] + (b[i] - a[i]) * f for i in range(3))


def hot_stops(el, deep=0.68, light=0.55):
    """white-hot core -> element colour -> deeper soft edge, over h in 0..1"""
    c = EL[el] if isinstance(el, str) else el
    return [(0.0, tuple(v * deep for v in c)), (0.32, c), (0.68, blend(c, WHITE, light)), (0.9, blend(c, WHITE, 0.9)), (1.0, WHITE)]


NEUTRAL = [(0.0, (196, 199, 208)), (0.35, (226, 228, 234)), (0.7, (250, 250, 252)), (1.0, WHITE)]


# ---------------------------------------------------------------- shader expression helpers
class _T:
    tree = None


def _node(kind, **kw):
    n = _T.tree.nodes.new(kind)
    for k, v in kw.items():
        setattr(n, k, v)
    return n


class S:
    """a float socket; arithmetic makes Math nodes"""
    __slots__ = ("o",)

    def __init__(self, o):
        self.o = o

    def __add__(a, b): return M("ADD", a, b)
    def __radd__(a, b): return M("ADD", b, a)
    def __sub__(a, b): return M("SUBTRACT", a, b)
    def __rsub__(a, b): return M("SUBTRACT", b, a)
    def __mul__(a, b): return M("MULTIPLY", a, b)
    def __rmul__(a, b): return M("MULTIPLY", b, a)
    def __truediv__(a, b): return M("DIVIDE", a, b)
    def __rtruediv__(a, b): return M("DIVIDE", b, a)
    def __neg__(a): return M("MULTIPLY", a, -1.0)
    def __pow__(a, b): return M("POWER", a, b)


class C:
    """a colour socket"""
    __slots__ = ("o",)

    def __init__(self, o):
        self.o = o


def _feed(sock, v):
    if isinstance(v, (S, C)):
        _T.tree.links.new(v.o, sock)
    elif isinstance(v, (tuple, list)):
        sock.default_value = lin(v) if len(v) == 3 else v
    else:
        sock.default_value = float(v)


_FOLD2 = {"ADD": lambda a, b: a + b, "SUBTRACT": lambda a, b: a - b, "MULTIPLY": lambda a, b: a * b,
          "DIVIDE": lambda a, b: a / b if b else 0.0, "MINIMUM": min, "MAXIMUM": max,
          "POWER": lambda a, b: a ** b if a >= 0 else 0.0, "ARCTAN2": math.atan2}
_FOLD1 = {"SINE": math.sin, "COSINE": math.cos, "ABSOLUTE": abs, "SQRT": lambda a: math.sqrt(max(a, 0.0)),
          "FLOOR": math.floor, "FRACT": lambda a: a - math.floor(a), "EXPONENT": math.exp}


def M(op, a, b=None, clamp=False):
    if not isinstance(a, S) and not isinstance(b, S) and not clamp:
        if b is None and op in _FOLD1:
            return _FOLD1[op](float(a))
        if b is not None and op in _FOLD2:
            return _FOLD2[op](float(a), float(b))
    n = _node("ShaderNodeMath", operation=op, use_clamp=clamp)
    _feed(n.inputs[0], a)
    if b is not None:
        _feed(n.inputs[1], b)
    return S(n.outputs[0])


def sin(x): return M("SINE", x)
def cos(x): return M("COSINE", x)
def ab(x): return M("ABSOLUTE", x)
def sqrt(x): return M("SQRT", M("MAXIMUM", x, 0.0))
def floor(x): return M("FLOOR", x)
def fract(x): return M("FRACT", x)
def mn(a, b): return M("MINIMUM", a, b)
def mx(a, b): return M("MAXIMUM", a, b)
def clamp01(x): return M("ADD", x, 0.0, clamp=True)
def atan2(y, x): return M("ARCTAN2", y, x)
def mix(a, b, t): return a + (b - a) * t
def length(x, y): return sqrt(x * x + y * y)


def _maprange(interp, e0, e1, x):
    n = _node("ShaderNodeMapRange", interpolation_type=interp, clamp=True)
    _feed(n.inputs[0], x)
    _feed(n.inputs[1], e0)
    _feed(n.inputs[2], e1)
    n.inputs[3].default_value = 0.0
    n.inputs[4].default_value = 1.0
    return S(n.outputs[0])


def sstep(e0, e1, x):
    """smoothstep; e0 > e1 gives the falling edge"""
    return _maprange("SMOOTHSTEP", e0, e1, x)


def lstep(e0, e1, x):
    return _maprange("LINEAR", e0, e1, x)


def smin(a, b, k):
    h = clamp01(0.5 + 0.5 * (b - a) / k)
    return mix(b, a, h) - k * h * (1 - h)


def noise(x, y, z=0.0, w=0.0, scale=1.0, detail=2.0, rough=0.5):
    cmb = _node("ShaderNodeCombineXYZ")
    _feed(cmb.inputs[0], x)
    _feed(cmb.inputs[1], y)
    _feed(cmb.inputs[2], z)
    n = _node("ShaderNodeTexNoise", noise_dimensions="4D")
    _T.tree.links.new(cmb.outputs[0], n.inputs["Vector"])
    _feed(n.inputs["W"], w)
    _feed(n.inputs["Scale"], scale)
    _feed(n.inputs["Detail"], detail)
    _feed(n.inputs["Roughness"], rough)
    return S(n.outputs["Fac"])


def lnoise(x, y, t, scale, detail=2.0, radius=0.55, seed=0.0):
    """noise that loops when t goes 0 -> 1 (a circle in the 3rd / 4th dimensions)"""
    return noise(x, y, cos(t * TAU) * radius + seed, sin(t * TAU) * radius, scale, detail)


def coords():
    tc = _node("ShaderNodeTexCoord")
    sp = _node("ShaderNodeSeparateXYZ")
    _T.tree.links.new(tc.outputs["Object"], sp.inputs[0])
    return S(sp.outputs[0]), S(sp.outputs[1])


def uvs():
    tc = _node("ShaderNodeTexCoord")
    sp = _node("ShaderNodeSeparateXYZ")
    _T.tree.links.new(tc.outputs["UV"], sp.inputs[0])
    return S(sp.outputs[0]), S(sp.outputs[1])


def attr(name):
    n = _node("ShaderNodeAttribute", attribute_type="OBJECT", attribute_name=name)
    return S(n.outputs["Fac"])


def normal_dot(v):
    g = _node("ShaderNodeNewGeometry")
    d = _node("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    _T.tree.links.new(g.outputs["Normal"], d.inputs[0])
    d.inputs[1].default_value = v
    return S(d.outputs["Value"])


def ramp(h, stops, interp="LINEAR"):
    n = _node("ShaderNodeValToRGB")
    cr = n.color_ramp
    cr.interpolation = interp
    stops = sorted(stops)
    els = cr.elements
    els[0].position, els[0].color = stops[0][0], lin(stops[0][1])
    els[1].position, els[1].color = stops[-1][0], lin(stops[-1][1])
    for p, c in stops[1:-1]:
        e = els.new(p)
        e.color = lin(c)
    _feed(n.inputs["Fac"], h)
    return C(n.outputs["Color"])


def rgb(c):
    n = _node("ShaderNodeRGB")
    n.outputs[0].default_value = lin(c)
    return C(n.outputs[0])


def mixc(a, b, f):
    n = _node("ShaderNodeMix", data_type="RGBA", clamp_factor=True)
    ins = {s.identifier: s for s in n.inputs}
    _feed(ins["Factor_Float"], f)
    _feed(ins["A_Color"], a)
    _feed(ins["B_Color"], b)
    return C([o for o in n.outputs if o.identifier == "Result_Color"][0])


def finish(color, alpha, strength=1.0):
    em = _node("ShaderNodeEmission")
    _feed(em.inputs["Color"], color)
    _feed(em.inputs["Strength"], strength)
    tr = _node("ShaderNodeBsdfTransparent")
    ms = _node("ShaderNodeMixShader")
    _feed(ms.inputs[0], clamp01(alpha))
    _T.tree.links.new(tr.outputs[0], ms.inputs[1])
    _T.tree.links.new(em.outputs[0], ms.inputs[2])
    out = _node("ShaderNodeOutputMaterial")
    _T.tree.links.new(ms.outputs[0], out.inputs["Surface"])


def finish_opaque(color):
    em = _node("ShaderNodeEmission")
    _feed(em.inputs["Color"], color)
    out = _node("ShaderNodeOutputMaterial")
    _T.tree.links.new(em.outputs[0], out.inputs["Surface"])


def cellmask(X, Y, a=0.43, b=0.48):
    """fades a full-cell field out before the cell border"""
    return sstep(b, a, mx(ab(X), ab(Y)))


_MATS = {}


def material(name, build, blended=True, cull=False):
    if name in _MATS:
        return _MATS[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    _T.tree = nt
    build()
    m.surface_render_method = "BLENDED" if blended else "DITHERED"
    m.use_backface_culling = cull
    _MATS[name] = m
    return m


# ---------------------------------------------------------------- scene objects
_QUAD = {}


def _link(o):
    bpy.context.scene.collection.objects.link(o)
    return o


def _props(o, props):
    for k, v in props.items():
        o[k] = float(v)


def quad_mesh(mat):
    if mat.name in _QUAD:
        return _QUAD[mat.name]
    me = bpy.data.meshes.new("q_" + mat.name)
    vs = [(-0.5, -0.5, 0.0), (0.5, -0.5, 0.0), (0.5, 0.5, 0.0), (-0.5, 0.5, 0.0)]
    me.from_pydata(vs, [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        x, y, _ = vs[lp.vertex_index]
        uv.data[lp.index].uv = (x + 0.5, y + 0.5)
    me.materials.append(mat)
    _QUAD[mat.name] = me
    return me


def sprite(mat, x, y, w, h=None, rot=0.0, z=0.0, **props):
    o = bpy.data.objects.new("sp", quad_mesh(mat))
    o.location = (x, y, z)
    o.scale = (w, h if h is not None else w, 1.0)
    o.rotation_euler = (0.0, 0.0, rot)
    _props(o, props)
    return _link(o)


def cellplane(mat, f, z=0.0, **props):
    props.setdefault("t", f.t)
    return sprite(mat, f.cx, f.cy, 1.0, z=z, **props)


def strip(mat, pts, widths, z=0.0, **props):
    """a ribbon along a polyline (world xy); UV u along, v across (0..1)"""
    n = len(pts)
    seg = [(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(n - 1)]
    seg = [(dx / (math.hypot(dx, dy) or 1), dy / (math.hypot(dx, dy) or 1)) for dx, dy in seg]
    acc = [0.0]
    for i in range(n - 1):
        acc.append(acc[-1] + math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]))
    total = acc[-1] or 1.0
    vs, uvd = [], []
    for i in range(n):
        if i == 0:
            tx, ty = seg[0]
            k = 1.0
        elif i == n - 1:
            tx, ty = seg[-1]
            k = 1.0
        else:
            tx, ty = seg[i - 1][0] + seg[i][0], seg[i - 1][1] + seg[i][1]
            L = math.hypot(tx, ty) or 1.0
            tx, ty = tx / L, ty / L
            k = 1.0 / max(0.45, tx * seg[i][0] + ty * seg[i][1])
        nx, ny = -ty, tx
        w = widths[i] * k
        vs.append((pts[i][0] + nx * w, pts[i][1] + ny * w, z))
        vs.append((pts[i][0] - nx * w, pts[i][1] - ny * w, z))
        uvd += [(acc[i] / total, 1.0), (acc[i] / total, 0.0)]
    faces = [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(n - 1)]
    me = bpy.data.meshes.new("strip")
    me.from_pydata(vs, [], faces)
    uv = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        uv.data[lp.index].uv = uvd[lp.vertex_index]
    me.materials.append(mat)
    o = bpy.data.objects.new("strip", me)
    _props(o, props)
    return _link(o)


def mesh_from_bm(bm, name, mat):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    me.materials.append(mat)
    return me


def hull_mesh(me_src, w, mat):
    """inverted hull: the mesh pushed out along vertex normals with its faces flipped (backface-culled outline)"""
    bm = bmesh.new()
    bm.from_mesh(me_src)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * w
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(me_src.name + "_hull")
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(mat)
    return me


def solid(me, hull, x, y, z, rot, scale=1.0, mode="XYZ"):
    objs = []
    for m in (me, hull):
        if m is None:
            continue
        o = bpy.data.objects.new("solid", m)
        # the outline hull sits a hair behind: no depth ties with the mesh at the silhouette (keeps renders bit-exact)
        o.location = (x, y, z - (0.02 if m is hull else 0.0))
        o.rotation_mode = mode
        o.rotation_euler = rot
        o.scale = (scale, scale, scale)
        objs.append(_link(o))
    return objs


LIGHT = (-0.42, 0.52, 0.744)


def mat_toon(name, stops):
    def sh():
        finish_opaque(ramp(normal_dot(LIGHT), stops, "CONSTANT"))
    return material(name, sh, blended=False)


def mat_flat(name, c, cull=False):
    def sh():
        finish_opaque(rgb(c))
    return material(name, sh, blended=False, cull=cull)


# ---------------------------------------------------------------- shared sprite materials
def mat_glowdot(name, stops, halo=0.55, pw=1.4):
    """a soft glowing dot / ember; c = heat 0..1, a = alpha"""
    def sh():
        X, Y = coords()
        A, hot = attr("a"), attr("c")
        d = (ab(X * 2) ** pw + ab(Y * 2) ** pw) ** (1.0 / pw)
        core = sstep(0.52, 0.44, d)
        hal = (1 - sstep(0.3, 1.0, d)) ** 2
        h = clamp01(1 - d / 0.52) * (0.55 + 0.45 * hot) * core + hal * 0.2
        finish(ramp(h, stops), mx(core, hal * halo) * A)
    return material(name, sh)


def mat_glint(name, stops):
    """a four-point star glint (astroid) with a small diagonal cross and a glow; a = alpha"""
    def sh():
        X, Y = coords()
        A = attr("a")
        q = sqrt(ab(X) / 0.48) + sqrt(ab(Y) / 0.48)
        xr, yr = (X + Y) * 0.7071, (X - Y) * 0.7071
        q2 = sqrt(ab(xr) / 0.22) + sqrt(ab(yr) / 0.22)
        h = mx(1 - q, (1 - q2) * 0.75)
        core = sstep(0.0, 0.05, h)
        r = length(X, Y)
        glow = (1 - sstep(0.0, 0.3, r)) ** 2 * 0.5
        finish(ramp(clamp01(h * 1.8 + glow * 0.4), stops), mx(core, glow) * A)
    return material(name, sh)


def mat_strip(name, stops, soft=0.6, pw=1.3):
    """glowing ribbon: white core along the middle of a strip, soft edges; a = alpha"""
    def sh():
        U, V = uvs()
        A = attr("a")
        h = 1 - ab(V * 2 - 1)
        finish(ramp(h, stops), sstep(0.02, soft, h) ** pw * A)
    return material(name, sh)


# ---------------------------------------------------------------- frames
class Fr:
    def __init__(self, i, t):
        self.i, self.t = i, t
        self.cx = (i % GRID) - 1.5
        self.cy = 1.5 - (i // GRID)


def ease_out(x):
    x = min(max(x, 0.0), 1.0)
    return 1 - (1 - x) ** 2


def smooth(e0, e1, x):
    x = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return x * x * (3 - 2 * x)


BUILD = {}


def reg(key):
    def deco(fn):
        BUILD[key] = fn
        return fn
    return deco


# ================================================================= FLAME
def scroll_noise(x, y, t, speed, scale, detail, seed=0.0):
    """noise scrolling upward (features rise) that still loops over t = 0 -> 1: two scrolls one period apart,
    cross-faded, with the contrast restored"""
    na = noise(x, y - t * speed, seed, 0.0, scale, detail)
    nb = noise(x, y - (t - 1.0) * speed, seed, 0.0, scale, detail)
    k = sqrt((1 - t) * (1 - t) + t * t)
    return 0.5 + (mix(na, nb, t) - 0.5) / k


@reg("fx_flame")
def b_flame(F, rng):
    """rising flame tongues (the classic fbm flame field): rising noise pushes a tapered field upward into separate
    licks that tear off at the top; soft alpha; heat = noise x field: white-hot core -> yellow -> element orange ->
    deep red at the feathered edge"""
    def sh():
        X, Y = coords()
        t = attr("t")
        n = scroll_noise(X * 1.0, Y * 0.7, t, 0.9, 3.2, 4.0)
        qx = X * 0.6
        qy = (Y + 0.3) * 0.95
        L = length(qx * (1.8 + qy * 1.5), qy * 0.75)
        c = clamp01(1 - 16 * mx(L - n * mx(qy + 0.25, 0.0) * 0.8, 0.0) ** 1.2)
        heat = clamp01(n * c * 1.4 * (1 - 0.6 * clamp01(qy * 1.2)))
        col = ramp(heat, [(0.0, (206, 46, 20)), (0.35, EL["Flame"]), (0.6, (255, 146, 40)), (0.8, (255, 198, 78)),
                          (0.93, (255, 240, 190)), (1.0, WHITE)])
        finish(col, c * (1 - sstep(0.12, 0.44, Y)) * cellmask(X, Y))
    m = material("flame", sh)
    for f in F:
        cellplane(m, f)


@reg("fx_embers")
def b_embers(F, rng):
    m = mat_glowdot("ember", [(0.0, (222, 66, 34)), (0.2, EL["Flame"]), (0.5, (255, 160, 56)), (0.8, (255, 220, 120)), (1.0, (255, 250, 222))], halo=0.7)
    embers = [dict(p=(k + rng.uniform(0.0, 0.6)) / 6.0, x0=rng.uniform(-0.2, 0.2), sp=1, amp=rng.uniform(0.03, 0.06),
                   fq=rng.choice((1, 2)), ph=rng.random(), size=rng.uniform(0.17, 0.22), fl=rng.random()) for k in range(6)]
    for f in F:
        for k, e in enumerate(embers):
            g = (e["p"] + f.t * e["sp"]) % 1.0
            y = -0.3 + 0.58 * g
            x = e["x0"] + e["amp"] * math.sin(TAU * (f.t * e["fq"] + e["ph"]))
            vx = e["amp"] * math.cos(TAU * (f.t * e["fq"] + e["ph"])) * TAU * e["fq"]
            fade = smooth(0.0, 0.1, g) * (1 - smooth(0.75, 1.0, g))
            s = e["size"] * (1 - 0.4 * g)
            a = fade * (0.8 + 0.2 * math.sin(TAU * (3 * f.t + e["fl"])))
            sprite(m, f.cx + x, f.cy + y, s, s * 1.5, rot=-math.atan2(vx, 0.7 * e["sp"] + 0.3) * 0.6, z=0.01 * k,
                   a=a, c=1 - 0.8 * g)


def mat_puffball(name, tones=None, outline=None, soft=None, sil=False):
    """one round cartoon puff lobe filling its sprite: cel-lit (highlight top-left, shadow crescent bottom-right,
    thin outline) or soft (soft=ramp stops, for mist). b = dissolve 0..1 (noise erosion), s = noise seed,
    c = flash (mix to white), a = alpha"""
    def sh():
        X, Y = coords()
        A, Bd, Sd, Fl = attr("a"), attr("b"), attr("s"), attr("c")
        r = length(X, Y)
        n = noise(X, Y, Sd, 0.0, 3.2, 2.0) - 0.5
        edge = 0.47 + n * 0.035 - Bd * (0.32 + 0.5 * n)
        d = r - edge
        if soft:
            col = ramp(clamp01(-d / 0.3 + Y * 0.35), soft)
            a = sstep(0.02, -0.22, d) * 0.92
        else:
            lit = 1 - sstep(0.27, 0.285, length(X + 0.1, Y - 0.11))
            shd = sstep(0.465, 0.48, length(X + 0.07, Y - 0.08))
            col = mixc(mixc(rgb(tones[1]), rgb(tones[0]), lit), rgb(tones[2]), shd * (1 - lit))
            if sil:
                col = rgb(outline)
            a = sstep(0.006, -0.006, d)
        col = mixc(col, rgb(WHITE), Fl)
        finish(col, a * A)
    return material(name, sh)


def puff_frames(F, rng, mat, lobes, grow, spread, rise, dissolve, z0=0.0, sil=None):
    """lay out lobes (x, y, r) per frame; front (lower) lobes draw on top. sil: an outline-coloured copy of every
    lobe, a little bigger, drawn behind all of them (one outline around the whole puff, none between lobes)"""
    seeds = [rng.uniform(0, 50) for _ in lobes]
    order = [rng.random() for _ in lobes]
    for f in F:
        t = f.t
        for k, (x, y, r) in enumerate(lobes):
            g = grow(t, order[k])
            sp = spread(t)
            px, py = x * sp, y * sp + rise * t
            sprite(mat, f.cx + px, f.cy + py, 2.0 * r * g, z=z0 + 0.5 - py * 0.5 + 0.001 * k,
                   a=1.0, b=dissolve(t, order[k]), s=seeds[k], c=0.0)
            if sil is not None:
                sprite(sil, f.cx + px, f.cy + py, 2.0 * r * g + 0.024, z=z0 - 0.3 + 0.001 * k,
                       a=1.0, b=dissolve(t, order[k]), s=seeds[k], c=0.0)


def _puff_grow(lo, until):
    return lambda t, o: lo + (1 - lo) * ease_out(t / (until + 0.15 * o))


def mat_softpuff(name, stops, alpha=1.0):
    """one soft round puff filling its sprite: noisy feathered edge, light from the top-left, inner billows.
    a = alpha, b = thin-out 0..1 (only the dense billows stay), s = noise seed, c = flash (mix to white)"""
    def sh():
        X, Y = coords()
        A, Bt, Sd, Fl = attr("a"), attr("b"), attr("s"), attr("c")
        r = length(X, Y) * 2
        n = clamp01((noise(X, Y, Sd, 0.0, 2.0, 1.5, 0.45) - 0.5) * 2.4 + 0.5)
        rr = r + (n - 0.5) * 0.4
        body = 1 - sstep(0.2, 0.98, rr)
        body = body * (1 - Bt * (1 - sstep(0.35, 0.8, n)))
        shade = clamp01(0.5 + (Y - X) * 0.55 + (n - 0.5) * 0.45)
        col = mixc(ramp(shade, stops), rgb(WHITE), Fl)
        finish(col, body * alpha * A)
    return material(name, sh)


def puff_burst(F, rng, mat, n, d0, d1, s0, s1, rise, thin_from, a_end, squash=1.0):
    """n soft puffs: born clustered, drifting outward and growing (OneShot), thinning out after thin_from"""
    puffs = [dict(a=TAU * k / n + rng.uniform(-0.3, 0.3), d=rng.uniform(0.75, 1.15), s=rng.uniform(0.85, 1.15),
                  seed=rng.uniform(0, 50), z=rng.random()) for k in range(n)]
    for f in F:
        t = f.t
        e = ease_out(t / 0.8)
        for p in puffs:
            d = (d0 + (d1 - d0) * e) * p["d"]
            sz = (s0 + (s1 - s0) * e) * p["s"]
            x = math.cos(p["a"]) * d
            y = math.sin(p["a"]) * d * squash + rise * t
            th = smooth(thin_from, 1.0, t)
            sprite(mat, f.cx + x, f.cy + y, sz, sz * (0.85 + 0.15 * squash), z=p["z"] * 0.1, a=1 - (1 - a_end) * t, b=th * 0.8,
                   s=p["seed"], c=0.0)
        # a centre puff so the burst never has a hole
        sprite(mat, f.cx, f.cy + rise * t, (s0 + (s1 - s0) * e) * 1.1, z=0.05, a=1 - (1 - a_end) * t, b=smooth(thin_from, 1.0, t) * 0.8,
               s=7.0, c=0.0)


@reg("fx_smoke")
def b_smoke(F, rng):
    m = mat_softpuff("smoke", [(0.0, (150, 152, 164)), (0.5, (208, 210, 218)), (1.0, (250, 250, 252))])
    puff_burst(F, rng, m, 6, 0.05, 0.2, 0.3, 0.52, 0.06, 0.3, 0.55)


@reg("fx_dust")
def b_dust(F, rng):
    tones = [(246, 224, 186), (214, 178, 128), (166, 126, 84)]
    m = mat_puffball("dust", tones, (126, 90, 56))
    sil = mat_puffball("dustsil", tones, (126, 90, 56), sil=True)
    lobes = [(0.0, -0.04, 0.13), (-0.15, -0.08, 0.11), (0.15, -0.08, 0.11), (-0.28, -0.12, 0.08), (0.28, -0.12, 0.08),
             (-0.07, 0.06, 0.1), (0.08, 0.05, 0.09), (-0.02, -0.16, 0.08), (-0.38, -0.15, 0.05), (0.38, -0.15, 0.05)]
    puff_frames(F, rng, m, lobes, _puff_grow(0.45, 0.45), lambda t: 0.6 + 0.45 * ease_out(t / 0.6), 0.04,
                lambda t, o: 0.85 * smooth(0.3 + 0.25 * o, 1.0, t), sil=sil)


@reg("fx_stormcloud")
def b_cloud(F, rng):
    """soft billowing dark storm puffs with a faint electric glow living inside (between the back and front puffs),
    flashing on frames 4-5 / 11-12. Neutral greys: tinted per element at runtime"""
    m = mat_softpuff("cloud", [(0.0, (60, 64, 82)), (0.5, (108, 112, 132)), (1.0, (172, 176, 194))], alpha=0.95)
    glow = mat_softglow("cloudglow", [(0.0, (190, 200, 235)), (1.0, WHITE)], alpha=1.0, radius=0.5)
    back = [(-0.2, 0.06, 0.4, 0.0), (0.05, 0.1, 0.46, 0.4), (0.24, 0.03, 0.36, 0.7)]
    front = [(-0.26, -0.06, 0.32, 0.2), (-0.08, -0.06, 0.4, 0.55), (0.13, -0.07, 0.38, 0.85), (0.29, -0.05, 0.28, 0.1)]
    seeds = [rng.uniform(0, 50) for _ in range(len(back) + len(front))]
    flashes = {3: (1.0, -0.12), 4: (0.5, -0.12), 10: (0.9, 0.13), 11: (0.4, 0.13)}
    for f in F:
        fa, fx = flashes.get(f.i, (0.0, 0.08 * math.sin(TAU * f.t)))
        for k, (x, y, sz, ph) in enumerate(back + front):
            bob = 0.012 * math.sin(TAU * (f.t + ph))
            grow = 1 + 0.05 * math.sin(TAU * (f.t + ph * 1.7 + 0.25))
            fl = fa * max(0.0, 1 - abs(x - fx) / 0.25) * 0.55 if k >= len(back) else 0.0
            z = 0.0 + 0.01 * k if k < len(back) else 0.4 + 0.01 * k
            sprite(m, f.cx + x, f.cy + y + bob, sz * grow, sz * grow * 0.86, z=z, a=1.0, b=0.15, s=seeds[k], c=fl)
        pulse = 0.3 + 0.12 * math.sin(TAU * 2 * f.t)
        sprite(glow, f.cx + fx, f.cy + 0.0, 0.42 + 0.2 * fa, 0.36 + 0.15 * fa, z=0.2, a=min(1.0, pulse + fa))


@reg("fx_frostmist")
def b_frostmist(F, rng):
    """soft cold mist puffs that swell, drift apart and thin out, with tiny glints"""
    m = mat_softpuff("frostmist", [(0.0, (122, 194, 240)), (0.5, (180, 232, 251)), (1.0, (246, 253, 255))], alpha=0.85)
    puff_burst(F, rng, m, 7, 0.06, 0.22, 0.3, 0.5, 0.03, 0.3, 0.6, squash=0.7)
    gl = mat_glint("frostglint", [(0.0, EL["Frost"]), (0.5, (220, 246, 255)), (1.0, WHITE)])
    glints = [dict(x=rng.uniform(-0.22, 0.22), y=rng.uniform(-0.14, 0.16), t0=rng.uniform(0.0, 0.55), s=rng.uniform(0.09, 0.14)) for _ in range(6)]
    for f in F:
        for k, gq in enumerate(glints):
            u = (f.t - gq["t0"]) / 0.4
            if 0.0 < u < 1.0:
                sprite(gl, f.cx + gq["x"], f.cy + gq["y"], gq["s"] * math.sin(math.pi * u), z=2.0 + 0.01 * k, a=1.0)


# ================================================================= WATER
WATER = [(0.0, (36, 98, 204)), (0.3, EL["Water"]), (0.7, (118, 194, 252)), (1.0, (196, 232, 255))]


def mat_waterblob():
    def sh():
        X, Y = coords()
        A = attr("a")
        d = length(X, Y) * 2
        inside = sstep(0.985, 0.95, d)
        dep = clamp01(1 - d)
        inner = clamp01(1 - length(X * 1.1, Y + 0.14) * 2.6)
        col = ramp(clamp01(dep * 0.5 + inner * 0.65), WATER)
        col = mixc(col, rgb((32, 92, 200)), sstep(0.8, 0.92, d) * 0.75)
        hl = sstep(0.1, 0.075, length((X + 0.15) * 1.0, (Y - 0.16) * 1.35))
        hl2 = sstep(0.045, 0.03, length(X - 0.19, Y + 0.12))
        col = mixc(col, rgb(WHITE), mx(hl, hl2 * 0.8))
        finish(col, inside * A)
    return material("waterblob", sh)


def mat_ring(name, stops):
    """a ring that fills a sprite; c = thickness (fraction of the radius), a = alpha"""
    def sh():
        X, Y = coords()
        A, th = attr("a"), attr("c")
        r = length(X, Y) * 2
        prof = 1 - ab(r - (0.97 - th)) / th
        finish(ramp(clamp01(prof), stops), sstep(0.0, 0.18, prof) * A)
    return material(name, sh)


@reg("fx_splash")
def b_splash(F, rng):
    """one liquid body: a smooth union of tapered capsules (the jets) and a mound; the jet heads detach as droplets"""
    blob = mat_waterblob()
    B = (0.0, -0.3)
    tongues = []
    for k in range(7):
        th = math.radians(-62 + k * (124 / 6) + rng.uniform(-6, 6))
        L = 0.4 - 0.17 * abs(th) / 1.1 + rng.uniform(-0.03, 0.03)
        tongues.append(dict(th=th, L=L, w=rng.uniform(0.078, 0.094), vy=rng.uniform(0.5, 0.75)))

    def sh():
        X, Y = coords()
        t = attr("t")
        g = 0.3 + 0.7 * (1 - (1 - clamp01(t / 0.32)) ** 2)
        u = clamp01((t - 0.4) / 0.6)
        early = 1 - sstep(0.39, 0.41, t)
        grow = early * g + (1 - early) * (1 - 0.85 * sstep(0.0, 0.8, u))
        thin = 1 - 0.5 * u

        def sdf(px, py):
            qx, qy = px - B[0], py - B[1]
            d = None
            for tg in tongues:
                dx, dy = math.sin(tg["th"]), math.cos(tg["th"])
                L = tg["L"] * grow
                h = clamp01((qx * dx + qy * dy) / L)
                di = length(qx - dx * L * h, qy - dy * L * h) - (0.02 + (tg["w"] * 0.5 - 0.02) * h * h) * thin
                d = di if d is None else smin(d, di, 0.04)
            hgt = mx(0.15 * g * (1 - 0.75 * sstep(0.35, 0.9, t)), 0.02)
            wid = 0.13 + 0.05 * g
            mound = (length(qx / wid, qy / hgt) - 1) * hgt
            d = smin(d, mound, 0.04)
            return mx(d, -qy)
        d0 = sdf(X, Y)
        lit = sstep(-0.003, 0.003, sdf(X - 0.022, Y + 0.022))
        dep = clamp01(-d0 / 0.045)
        col = ramp(dep, [(0.0, (36, 98, 204)), (0.4, EL["Water"]), (1.0, (104, 184, 250))])
        col = mixc(col, rgb((30, 88, 198)), sstep(-0.012, -0.004, d0))
        col = mixc(col, rgb((236, 248, 255)), lit * sstep(-0.004, -0.009, d0) * 0.9)
        finish(col, sstep(0.003, -0.003, d0) * cellmask(X, Y))
    body = material("splash", sh)

    def crown_sh():
        X, Y = coords()
        t = attr("t")
        g = 1 - (1 - clamp01(t / 0.5)) ** 2
        rx = 0.1 + 0.27 * g
        ry = rx * 0.3
        e = length(X / rx, (Y + 0.3) / ry)
        dd = ab(e - 1) * ry
        th = 0.024 * (1 - 0.5 * t)
        prof = 1 - dd / th
        col = mixc(ramp(clamp01(prof), WATER), rgb(WHITE), sstep(0.0, 0.01, Y + 0.3) * sstep(0.5, 0.9, prof))
        finish(col, sstep(0.0, 0.2, prof) * (1 - 0.6 * sstep(0.5, 1.0, t)) * cellmask(X, Y))
    crown = material("watercrown", crown_sh)
    for f in F:
        t = f.t
        cellplane(crown, f, z=0.0)
        cellplane(body, f, z=0.1)
        if t > 0.34:
            u = t - 0.34
            for k, tg in enumerate(tongues):
                dx, dy = math.sin(tg["th"]), math.cos(tg["th"])
                hx = B[0] + dx * tg["L"] + dx * 0.35 * u
                hy = B[1] + dy * tg["L"] + tg["vy"] * dy * 0.5 * u - 1.4 * u * u
                s = tg["w"] * 1.25 * (1 - 0.25 * u)
                if abs(hx) < 0.44 and -0.44 < hy < 0.44:
                    sprite(blob, f.cx + hx, f.cy + hy, s, s * 1.12, z=0.2 + 0.01 * k, a=1.0)


@reg("fx_droplets")
def b_droplets(F, rng):
    blob = mat_waterblob()
    ring = mat_ring("waterring", WATER)
    G = -0.3
    seq = [(0.3, 0.4, 0.48), (0.18, 0.39, 0.5), (0.06, 0.4, 0.48), (0.0, 0.52, 0.32), (0.0, 0.6, 0.24),
           (0.04, 0.4, 0.5), (0.14, 0.42, 0.44), (0.18, 0.44, 0.42), (0.12, 0.43, 0.44), (0.0, 0.5, 0.34), (0.0, 0.62, 0.22)]
    dirs = [math.radians(a) for a in (-75, -45, -15, 15, 45, 75)]
    for f in F:
        if f.i < len(seq):
            hgt, sx, sy = seq[f.i]
            sprite(blob, f.cx, f.cy + G + sy * 0.4 + hgt, sx * 0.8, sy * 0.8, a=1.0)
        else:
            u = (f.i - len(seq) + 1) / 5.0
            rr = 0.1 + 0.26 * ease_out(u)
            for k, a in enumerate(dirs):
                x = math.sin(a) * rr
                y = G + 0.1 + math.cos(a) * rr * 0.8 + 0.12 * u - 0.3 * u * u
                s = 0.13 - 0.04 * u
                sprite(blob, f.cx + x, f.cy + y, s, s, z=0.1 + 0.01 * k, a=1.0)
            if u < 0.7:
                rs = 0.2 + 0.5 * u
                sprite(ring, f.cx, f.cy + G + 0.06, rs, rs * 0.4, z=0.0, a=1 - u, c=0.18)


@reg("fx_ripple")
def b_ripple(F, rng):
    def sh():
        X, Y = coords()
        t = attr("t")
        r = length(X, Y) + (noise(X, Y, 0.0, 0.0, 4.0, 1.0) - 0.5) * 0.012
        body, crest = None, None
        for s0 in (0.0, 0.2, 0.4):
            tk = clamp01((t - s0) / (1 - s0))
            act = sstep(s0 - 0.001, s0 + 0.03, t)
            R = 0.1 + 0.33 * (1 - (1 - tk) * (1 - tk))
            th = 0.075 * (1 - 0.6 * tk) + 0.014
            dr = (r - R) / th
            k = act * (1 - 0.55 * tk * tk)
            b = sstep(-1.0, -0.55, dr) * sstep(0.12, 0.02, dr) * k
            c = (1 - sstep(0.0, 0.22, ab(dr + 0.08))) * k
            body = b if body is None else mx(body, b)
            crest = c if crest is None else mx(crest, c)
        dot = (1 - sstep(0.07, 0.085, r)) * (1 - sstep(0.1, 0.35, t))
        body = mx(body, dot)
        col = mixc(ramp(clamp01(body * 0.55 + 0.1), WATER), rgb((232, 247, 255)), crest)
        finish(col, mx(body * 0.85, crest) * cellmask(X, Y))
    m = material("ripple", sh)
    for f in F:
        cellplane(m, f)


# ================================================================= FROST
def _shard_mesh(rng, mat, L1, L2, r, sides=6):
    bm = bmesh.new()
    ring = []
    for k in range(sides):
        a = TAU * k / sides + rng.uniform(-0.15, 0.15)
        rr = r * rng.uniform(0.82, 1.08)
        ring.append(bm.verts.new((math.cos(a) * rr, rng.uniform(-0.02, 0.02), math.sin(a) * rr)))
    top = bm.verts.new((0.0, L1, 0.0))
    bot = bm.verts.new((0.0, -L2, 0.0))
    for k in range(sides):
        a, b = ring[k], ring[(k + 1) % sides]
        bm.faces.new((a, b, top))
        bm.faces.new((b, a, bot))
    me = mesh_from_bm(bm, "shard", mat)
    bm.free()
    return me


def mat_softglow(name, stops, alpha=0.4, radius=0.46):
    def sh():
        X, Y = coords()
        A = attr("a")
        r = length(X, Y) / radius
        g = (1 - sstep(0.0, 1.0, r)) ** 1.8
        finish(ramp(clamp01(g * 1.2), stops), g * alpha * A)
    return material(name, sh)


@reg("fx_iceshards")
def b_iceshards(F, rng):
    toon = mat_toon("ice", [(0.0, (62, 138, 208)), (0.38, (108, 190, 240)), (0.6, EL["Frost"]), (0.8, (214, 245, 255)), (0.93, WHITE)])
    line = mat_flat("iceline", (40, 104, 186), cull=True)
    glow = mat_softglow("iceglow", [(0.0, EL["Frost"]), (1.0, (230, 248, 255))], alpha=0.4)
    shards = []
    for (x, y, sc, tilt, nspin, nz) in ((0.0, 0.03, 1.35, 0.35, 1, 0), (-0.27, 0.22, 0.6, -0.4, 2, 1), (0.27, -0.24, 0.55, 0.6, -2, -1)):
        me = _shard_mesh(rng, toon, 0.3, 0.12, 0.085)
        shards.append(dict(me=me, hull=hull_mesh(me, 0.012 / sc, line), x=x, y=y, sc=sc, tilt=tilt, ns=nspin, nz=nz,
                           z0=rng.uniform(0, TAU), s0=rng.uniform(0, TAU)))
    for f in F:
        sprite(glow, f.cx, f.cy, 1.0, z=-0.5, a=1.0)
        for s in shards:
            spin = s["s0"] + TAU * f.t * s["ns"]
            rz = s["z0"] + TAU * f.t * s["nz"]
            solid(s["me"], s["hull"], f.cx + s["x"], f.cy + s["y"], 1.0 + 0.5 * shards.index(s), (s["tilt"], spin, rz), s["sc"], mode="YXZ")


@reg("fx_snow")
def b_snow(F, rng):
    def sh():
        X, Y = coords()
        t, A = attr("t"), attr("a")
        k = 1.0 / 0.37
        px, py = X * k, Y * k
        r = length(px, py)
        seg = TAU / 6
        th = atan2(py, px) + t * seg
        af = (fract(th / seg + 0.5) - 0.5) * seg
        u, v = r * cos(af), r * ab(sin(af))
        d_arm = length(u - clamp01(u * (1 / 0.95)) * 0.95, v) - 0.075

        def branch(b, L):
            dx, dy = 0.5, 0.866
            s = clamp01(((u - b) * dx + v * dy) / L) * L
            return length(u - b - s * dx, v - s * dy) - 0.055
        d = mn(mn(d_arm, branch(0.42, 0.3)), branch(0.68, 0.2))
        d = mn(d, ab(r - 0.24) - 0.05)
        d = mn(d, r - 0.11)
        inner = sstep(0.0, -0.05, d)
        core = sstep(0.012, -0.012, d)
        glow = (1 - sstep(0.0, 0.3, d)) ** 2 * 0.5
        col = ramp(clamp01(inner * 0.7 + core * 0.3 + glow * 0.2), [(0.0, EL["Frost"]), (0.35, (196, 238, 255)), (1.0, WHITE)])
        finish(col, mx(core, glow) * A * cellmask(X, Y), strength=1.0)
    m = material("snow", sh)
    for f in F:
        pulse = 0.92 + 0.08 * math.cos(TAU * f.t)
        sprite(m, f.cx, f.cy, pulse, t=f.t, a=0.9 + 0.1 * math.cos(TAU * 2 * f.t))


# ================================================================= NATURE
def mat_petal():
    """cherry petal: oval, pointed base, notch at the top; c 0 pink / 1 yellow, b backside shade, a alpha"""
    pink = [(0.0, (232, 96, 156)), (0.45, (255, 150, 196)), (1.0, (255, 230, 240))]
    yel = [(0.0, (238, 164, 36)), (0.45, (255, 214, 82)), (1.0, (255, 248, 210))]

    def sh():
        X, Y = coords()
        Cc, Bk, A = attr("c"), attr("b"), attr("a")
        wx = 0.38 * (1 - 0.6 * clamp01(-Y / 0.45))
        d = length(X / wx, (Y - 0.02) / 0.44) - 1
        notch = 1 - length(X, Y - 0.48) / 0.1
        d = mx(d, notch)
        g = clamp01((Y + 0.45) / 0.9)
        dep = clamp01(-d / 0.35)
        v = clamp01((1 - g) * 0.55 + dep * 0.45)
        col = mixc(ramp(v, pink), ramp(v, yel), Cc)
        ol = sstep(-0.16, -0.11, d)
        col = mixc(col, mixc(rgb((176, 46, 112)), rgb((178, 104, 14)), Cc), ol)
        vein = sstep(0.022, 0.01, ab(X)) * sstep(0.1, -0.2, Y) * (1 - ol)
        col = mixc(col, rgb((255, 246, 250)), vein * 0.7)
        col = mixc(col, rgb((70, 40, 60)), Bk * 0.22)
        finish(col, sstep(0.02, -0.02, d) * A)
    return material("petal", sh)


def _flutter(F, rng, mat, items, extra=None):
    for f in F:
        for k, p in enumerate(items):
            ph = TAU * (f.t + p["ph"])
            x = p["x"] + 0.07 * math.cos(ph)
            y = p["y"] + 0.05 * math.sin(2 * ph)
            fl = math.cos(TAU * (f.t * p["nf"] + p["pf"]))
            sx = p["s"] * (0.3 + 0.7 * abs(fl))
            props = dict(a=1.0, b=0.0 if fl >= 0 else 1.0, c=p.get("c", 0.0))
            sprite(mat, f.cx + x, f.cy + y, sx, p["s"], rot=p["r0"] + TAU * f.t * p["nr"], z=0.01 * k, **props)


@reg("fx_petals")
def b_petals(F, rng):
    m = mat_petal()
    items = [dict(x=-0.15, y=0.12, s=0.3, c=0.0), dict(x=0.16, y=0.1, s=0.27, c=1.0), dict(x=0.0, y=-0.17, s=0.29, c=0.0)]
    for p in items:
        p.update(ph=rng.random(), nf=rng.choice((1, 1, 2)), pf=rng.random(), r0=rng.uniform(0, TAU), nr=rng.choice((1, -1)))
    _flutter(F, rng, m, items)


@reg("fx_leaves")
def b_leaves(F, rng):
    def sh():
        X, Y = coords()
        Bk, A = attr("b"), attr("a")
        w = 0.33 * clamp01(1 - (Y / 0.44) ** 2) ** 0.85
        d = ab(X) - w
        stem = mx(ab(X) - 0.025, mx(-0.5 - Y, Y + 0.38))
        d = mn(mx(d, ab(Y) - 0.44), stem)
        side = sstep(-0.01, 0.01, X)
        dep = clamp01(-d / 0.12)
        col = mixc(rgb((156, 222, 112)), rgb((84, 166, 66)), side)
        col = mixc(rgb((60, 132, 52)), col, sstep(0.0, 0.5, dep))
        vein = mx(sstep(0.024, 0.012, ab(X)) * sstep(0.42, 0.3, Y),
                  sstep(0.035, 0.015, ab(fract((Y - ab(X) * 0.75) * 3.2 + 0.5) - 0.5) * 0.16) * 0.5 * sstep(0.03, 0.07, ab(X)) * sstep(0.0, 0.3, dep))
        col = mixc(col, rgb((214, 244, 150)), vein * 0.7)
        ol = sstep(-0.035, -0.018, d)
        col = mixc(col, rgb((30, 84, 34)), ol)
        col = mixc(col, rgb((40, 60, 30)), Bk * 0.2)
        finish(col, sstep(0.008, -0.008, d) * A)
    m = material("leaf", sh)
    items = [dict(x=-0.13, y=0.08, s=0.38), dict(x=0.15, y=-0.1, s=0.34)]
    for p in items:
        p.update(ph=rng.random(), nf=1, pf=rng.random(), r0=rng.uniform(0, TAU), nr=rng.choice((1, -1)))
    _flutter(F, rng, m, items)


@reg("fx_thorn")
def b_thorn(F, rng):
    def sh():
        X, Y = coords()
        t = attr("t")
        yp = 0.12 * sin(X * 5.2 + 0.7) - 0.02
        head = -0.12 + 0.54 * (1 - (1 - clamp01(t / 0.35)) ** 2)
        tail = -0.44 + 0.52 * sstep(0.3, 1.0, t)
        s = clamp01((X - tail) / mx(head - tail, 0.05))
        thin = 1 - 0.4 * sstep(0.4, 1.0, t)
        th = (0.016 + 0.04 * s ** 0.6) * thin
        dy = Y - yp
        dd = ab(dy)
        idx = floor((X + 0.5) * 8)
        par = fract(idx * 0.5) * 2
        is_top = sstep(-0.001, 0.001, dy)
        match = 1 - ab(par - is_top)
        ph = fract((X + 0.5) * 8)
        ht = 0.07 * (0.4 + 0.6 * s) * thin * clamp01(1 - ph / 0.62) * match * sstep(0.0, 0.12, ph)
        m = sstep(tail, tail + 0.05, X) * sstep(head + 0.012, head - 0.02, X)
        body = sstep(0.003, -0.003, dd - th) * m
        thorn = sstep(0.003, -0.003, dd - th - ht) * m * (1 - body)
        olm = sstep(0.003, -0.003, dd - th - ht - 0.014) * m
        glow = (1 - sstep(0.0, 0.08, dd - th - ht)) ** 2 * m * 0.55
        c = clamp01(1 - dd / mx(th, 0.001))
        top = sstep(0.0, 0.4, dy / mx(th, 0.001))
        vine = ramp(c, [(0.0, (34, 98, 40)), (0.45, (76, 160, 60)), (1.0, (128, 206, 84))])
        vine = mixc(vine, rgb((186, 236, 118)), top * sstep(0.3, 0.6, c))
        col = mixc(vine, rgb((244, 238, 170)), thorn)
        col = mixc(rgb((24, 70, 30)), col, mx(body, thorn))
        col = mixc(rgb((214, 252, 128)), col, olm)
        hd = (1 - sstep(0.0, 0.08, length(X - head, Y - yp))) * (1 - sstep(0.35, 0.6, t))
        col = mixc(col, rgb((252, 255, 224)), hd)
        finish(col, mx(mx(olm, glow), hd) * cellmask(X, Y))
    m = material("thorn", sh)
    for f in F:
        cellplane(m, f)


# ================================================================= EARTH
def _cube_mesh(mat, bevel=0.1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    me = mesh_from_bm(bm, "cube", mat)
    bm.free()
    return me


@reg("fx_rock")
def b_rock(F, rng):
    toon = mat_toon("rock", [(0.0, (92, 60, 38)), (0.337, (126, 86, 52)), (0.613, EL["Earth"]), (0.833, (228, 186, 134))])
    line = mat_flat("rockline", (66, 42, 26), cull=True)
    me = _cube_mesh(toon, 0.09)
    hull = hull_mesh(me, 0.05, line)
    chunks = []
    for (x, y, s) in ((-0.15, 0.13, 0.25), (0.17, 0.11, 0.2), (-0.1, -0.17, 0.17), (0.17, -0.16, 0.14), (0.02, 0.0, 0.08)):
        chunks.append(dict(x=x, y=y, s=s, r0=[rng.uniform(0, TAU) for _ in range(3)], n=[rng.choice((1, -1, 0)), rng.choice((1, -1)), rng.choice((1, 0, -1))]))
    for f in F:
        for k, c in enumerate(chunks):
            rot = tuple(c["r0"][j] + TAU * f.t * c["n"][j] for j in range(3))
            # each chunk on its own depth layer: chunks never intersect in 3D (no depth ties, bit-exact renders)
            solid(me, hull, f.cx + c["x"], f.cy + c["y"], 1.0 + 0.5 * k, rot, c["s"])


@reg("fx_crack")
def b_crack(F, rng):
    def stripmat(name, cols, soft):
        def sh():
            U, V = uvs()
            A, heat = attr("a"), attr("c")
            h = 1 - ab(V * 2 - 1)
            col = mixc(rgb(cols[0]), rgb(cols[1]), heat)
            finish(col, sstep(0.0, soft, h) * A)
        return material(name, sh)
    lip = stripmat("cracklip", ((222, 190, 142), (222, 190, 142)), 0.5)
    rim = stripmat("crackrim", ((84, 54, 32), (84, 54, 32)), 0.25)
    core = stripmat("crackcore", ((40, 24, 14), (255, 196, 92)), 0.4)
    glow = mat_strip("crackglow", [(0.0, (240, 110, 40)), (1.0, (255, 200, 110))], soft=0.95, pw=2.2)

    def dimple_sh():
        X, Y = coords()
        t = attr("t")
        r = length(X, Y)
        a = (1 - sstep(0.03, 0.1, r)) * 0.6
        col = rgb((70, 44, 26))
        finish(col, a * (1 - 0.3 * t) * cellmask(X, Y))
    dimple = material("crackdimple", dimple_sh)
    lines = []
    n = 7
    for k in range(n):
        a0 = TAU * k / n + rng.uniform(-0.25, 0.25)
        L = rng.uniform(0.34, 0.42)
        pts = [(0.0, 0.0)]
        segs = 6
        for j in range(1, segs + 1):
            rr = L * j / segs
            aj = a0 + rng.uniform(-0.18, 0.18)
            pts.append((math.cos(aj) * rr, math.sin(aj) * rr))
        lines.append((pts, 0.016, 0.0))
        for _ in range(rng.choice((1, 2))):
            j = rng.randint(2, 4)
            bx, by = pts[j]
            ba = a0 + rng.choice((-1, 1)) * rng.uniform(0.5, 0.9)
            bl = rng.uniform(0.1, 0.16)
            bp = [(bx, by)]
            for q in range(1, 4):
                rr = bl * q / 3
                aq = ba + rng.uniform(-0.2, 0.2)
                bp.append((bx + math.cos(aq) * rr, by + math.sin(aq) * rr))
            lines.append((bp, 0.009, (L * j / segs) / L))

    def cut(pts, frac):
        tot = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(len(pts) - 1))
        want = tot * frac
        out = [pts[0]]
        acc = 0.0
        for i in range(len(pts) - 1):
            sl = math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            if acc + sl >= want:
                u = (want - acc) / sl if sl else 0
                out.append((pts[i][0] + (pts[i + 1][0] - pts[i][0]) * u, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * u))
                return out
            out.append(pts[i + 1])
            acc += sl
        return out
    for f in F:
        g = 0.25 + 0.75 * ease_out(f.t / 0.45)
        heat = 1 - smooth(0.15, 0.85, f.t)
        cellplane(dimple, f, z=0.0)
        for (pts, w0, start) in lines:
            frac = (g - start) / max(1 - start, 1e-3) if start else g
            if frac <= 0.05:
                continue
            p = cut(pts, min(frac, 1.0))
            if len(p) < 2:
                continue
            nn = len(p)
            ws = [w0 * (1 - 0.75 * i / (nn - 1)) for i in range(nn)]
            wp = [(f.cx + x, f.cy + y) for x, y in p]
            strip(lip, wp, [w * 2.0 + 0.006 for w in ws], z=0.05, a=0.55, c=0.0)
            strip(rim, wp, [w * 1.5 + 0.003 for w in ws], z=0.1, a=1.0, c=0.0)
            strip(core, wp, [w * 0.7 for w in ws], z=0.2, a=1.0, c=heat)
            if heat > 0.05:
                strip(glow, wp, [w * 2.0 + 0.006 for w in ws], z=0.3, a=heat * 0.45)


# ================================================================= STORM
def _bolt(rng, p0, p1, levels, amp, fine=0, lim=(0.43, 0.46)):
    pts = [p0, p1]
    for lv in range(levels + fine):
        if lv >= levels:
            amp = 0.1
        new = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy) or 1.0
            off = rng.uniform(-1, 1) * amp * L
            new.append(((a[0] + b[0]) / 2 - dy / L * off, (a[1] + b[1]) / 2 + dx / L * off))
            new.append(b)
        pts = new
    return [(max(-lim[0], min(lim[0], x)), max(-lim[1], min(lim[1], y))) for x, y in pts]


STRIP_P = 4.0  # a strip's width in world units (= the image width): tiles repeat every STRIP_P along x


def _tile(pts):
    """a polyline from x = -2 to x = +2 (same y at both ends) repeated at -4 / 0 / +4: the copies meet exactly, so the
    ribbon at the image's left and right edges is the same geometry (the strip tiles along U)"""
    out = [(x - STRIP_P, y) for x, y in pts[:-1]] + [(x, y) for x, y in pts[:-1]] + [(x + STRIP_P, y) for x, y in pts]
    return out


@reg("fx_lightning")
def b_lightning(F, rng):
    """Beam strip (grid 1): a horizontal bolt + a thin second strand + branches, tileable along U"""
    m = mat_strip("bolt", [(0.0, (70, 84, 236)), (0.4, EL["Storm"]), (0.66, (170, 184, 255)), (0.8, WHITE), (1.0, WHITE)], soft=0.4, pw=1.0)
    r = random.Random(SEED + 97)
    lim = (99.0, 0.34)
    main = _tile(_bolt(r, (-2.0, 0.0), (2.0, 0.0), 4, 0.36, fine=1, lim=lim))
    ws = [0.05 * (0.85 + 0.15 * math.cos(TAU * x * 3 / STRIP_P)) for x, y in main]
    strip(m, main, ws, z=0.2, a=1.0)
    second = _tile(_bolt(r, (-2.0, 0.0), (2.0, 0.0), 4, 0.3, fine=1, lim=lim))
    strip(m, second, [0.02 for _ in second], z=0.1, a=0.7)
    src = main[len(main) // 3: 2 * len(main) // 3]
    for b in range(5):
        sx, sy = src[r.randint(2, len(src) - 3)]
        side = 1 if b % 2 else -1
        ex, ey = sx + r.uniform(0.25, 0.5) * r.choice((-1, 1)), max(-0.4, min(0.4, sy + side * r.uniform(0.18, 0.3)))
        br = _bolt(r, (sx, sy), (ex, ey), 2, 0.4, fine=1, lim=(99.0, 0.4))
        nb = len(br)
        bw = [0.026 * (1 - 0.75 * i / (nb - 1)) + 0.004 for i in range(nb)]
        for off in (-STRIP_P, 0.0, STRIP_P):
            strip(m, [(x + off, y) for x, y in br], bw, z=0.05 + 0.01 * b, a=0.9)


@reg("fx_sparks")
def b_sparks(F, rng):
    m = mat_strip("sparkzig", [(0.0, (196, 200, 212)), (0.5, (232, 235, 242)), (0.72, WHITE), (1.0, WHITE)], soft=0.85, pw=1.6)
    dot = mat_glowdot("sparkdot", NEUTRAL, halo=0.6)
    for f in F:
        r = random.Random(SEED + 31 * f.i)
        base = r.uniform(0, TAU)
        for k in range(r.choice((3, 4))):
            a = base + TAU * k / 3.5 + r.uniform(-0.3, 0.3)
            x, y = math.cos(a) * 0.05, math.sin(a) * 0.05
            pts = [(x, y)]
            sgn = r.choice((-1, 1))
            for j in range(r.randint(4, 6)):
                sl = r.uniform(0.055, 0.08)
                aj = a + sgn * r.uniform(0.6, 1.0)
                sgn = -sgn
                x, y = x + math.cos(aj) * sl, y + math.sin(aj) * sl
                pts.append((max(-0.42, min(0.42, x)), max(-0.42, min(0.42, y))))
            n = len(pts)
            strip(m, [(f.cx + px, f.cy + py) for px, py in pts], [0.034 * (1 - 0.6 * i / (n - 1)) for i in range(n)], z=0.1 + 0.01 * k, a=1.0)
        for k in range(3):
            a = r.uniform(0, TAU)
            rr = r.uniform(0.18, 0.36)
            s = r.uniform(0.06, 0.1)
            sprite(dot, f.cx + math.cos(a) * rr, f.cy + math.sin(a) * rr, s, z=0.3 + 0.01 * k, a=1.0, c=1.0)


# ================================================================= CELESTIAL
@reg("fx_stars")
def b_stars(F, rng):
    """a glowing burst star: five long spikes tapering from a white-hot core, five short ones between, a soft gold
    glow; turns 1/5 per loop and pulses, with two blinking glints"""
    def sh():
        X, Y = coords()
        A = attr("a")
        r = length(X, Y)
        th = atan2(X, Y)

        def spikes(n, off, L, w0):
            k = th * (n / TAU) + off
            fk = ab(k - floor(k + 0.5))
            wd = w0 * clamp01(1 - r / L)
            dr = wd - fk * (TAU / n) * r
            return clamp01(dr / mx(wd, 0.004)) ** 0.8 * clamp01(1 - r / L) ** 0.5
        s1 = spikes(5, 0.0, 0.46, 0.055)
        s2 = spikes(5, 0.5, 0.25, 0.04)
        core = 1 - sstep(0.02, 0.08, r)
        glow = (1 - sstep(0.0, 0.42, r)) ** 2.2
        h = mx(mx(s1, s2 * 0.8), core)
        col = ramp(clamp01(h * 1.1 + glow * 0.35), [(0.0, (242, 150, 40)), (0.3, (255, 198, 86)), (0.5, EL["Celestial"]),
                                                   (0.75, (255, 240, 196)), (0.9, (255, 252, 238)), (1.0, WHITE)])
        finish(col, clamp01(sstep(0.0, 0.18, h) + glow * 0.7) * A)
    m = material("star", sh)
    gl = mat_glint("starglint", [(0.0, EL["Celestial"]), (0.5, (255, 244, 200)), (1.0, WHITE)])
    seg = TAU / 5
    for f in F:
        s = 0.86 + 0.1 * math.cos(TAU * f.t)
        sprite(m, f.cx, f.cy, s, rot=-seg * f.t, z=0.0, a=1.0)
        for k, (gx, gy, ph) in enumerate(((0.3, 0.28, 0.0), (-0.3, -0.27, 0.5))):
            p = 0.5 + 0.5 * math.cos(TAU * (f.t + ph))
            sprite(gl, f.cx + gx, f.cy + gy, 0.1 + 0.1 * p, z=0.1 + 0.01 * k, a=0.4 + 0.6 * p)


@reg("fx_rays")
def b_rays(F, rng):
    N = 12

    def sh():
        X, Y = coords()
        t = attr("t")
        r = length(X, Y)
        th = atan2(Y, X) + t * 0.3
        k = th * (N / TAU)
        idx = floor(k + 0.5)
        fk = ab(k - idx)
        par = fract(idx * 0.5) * 2
        grow = 0.3 + 0.7 * (1 - (1 - clamp01(t / 0.3)) ** 2)
        Lr = mix(0.44, 0.29, par) * grow
        w0 = 0.055 * (1 - 0.65 * sstep(0.3, 1.0, t))
        dr = w0 * clamp01(1 - r / Lr) - fk * (TAU / N) * r
        ray = sstep(-0.002, 0.004, dr) * sstep(Lr, Lr - 0.02, r)
        h = clamp01(1 - r / Lr) * ray
        halo = (1 - sstep(-0.03, 0.0, -dr)) * 0.0 + sstep(-0.025, 0.0, dr) * clamp01(1 - r / Lr) * 0.35
        rc = 0.12 * (1 - 0.65 * t)
        core = 1 - sstep(rc * 0.6, rc, r)
        cglow = (1 - sstep(0.0, rc * 2.2, r)) ** 2 * 0.6
        hv = mx(h, mx(core, cglow * 0.7))
        col = ramp(hv, [(0.0, (242, 164, 48)), (0.35, EL["Celestial"]), (0.75, (255, 244, 200)), (1.0, WHITE)])
        finish(col, mx(mx(ray, halo), mx(core, cglow)) * cellmask(X, Y))
    m = material("rays", sh)
    for f in F:
        cellplane(m, f)


@reg("fx_sparkle")
def b_sparkle(F, rng):
    m = mat_glint("sparkle", NEUTRAL)
    for f in F:
        p = 0.5 + 0.5 * math.cos(TAU * f.t)
        sprite(m, f.cx, f.cy, 0.5 + 0.42 * p, rot=(math.pi / 2) * f.t, a=1.0)


# ================================================================= SHADOW
SHADOW = [(0.0, (52, 18, 92)), (0.35, EL["Shadow"]), (0.7, (192, 142, 242)), (0.9, (238, 220, 255)), (1.0, WHITE)]


@reg("fx_wisps")
def b_wisps(F, rng):
    """rising shadow tendrils: tapered S-curves with a travelling wave (loops), lavender core -> purple -> dark edge"""
    m = mat_strip("wisp", [(0.0, (60, 22, 108)), (0.4, EL["Shadow"]), (0.72, (172, 116, 230)), (0.9, (226, 200, 255)), (1.0, (246, 236, 255))], soft=0.45, pw=1.0)
    dot = mat_glowdot("wispdot", SHADOW, halo=0.6)
    tendrils = [dict(x0=-0.15, A=0.1, ph=0.0, w=0.05, top=0.36), dict(x0=0.02, A=0.12, ph=0.42, w=0.062, top=0.44),
                dict(x0=0.18, A=0.07, ph=0.71, w=0.04, top=0.24)]
    for f in F:
        for k, td in enumerate(tendrils):
            pts, ws = [], []
            n = 22
            for i in range(n):
                s = i / (n - 1)
                y = -0.4 + (td["top"] + 0.4) * s
                x = td["x0"] + td["A"] * math.sin(TAU * (s * 0.95 - f.t + td["ph"])) * (0.35 + 0.65 * s)
                curl = max(0.0, s - 0.78) / 0.22
                x += 0.07 * curl * curl * (1 if k % 2 else -1)
                y -= 0.04 * curl * curl
                pts.append((f.cx + max(-0.42, min(0.42, x)), f.cy + y))
                ws.append(td["w"] * (math.sin(math.pi * min(1.0, s * 1.15)) ** 0.7) * (1 - 0.35 * s) + 0.004)
            strip(m, pts, ws, z=0.1 + 0.01 * k, a=1.0)
        for k in range(3):
            g = (k / 3.0 + f.t) % 1.0
            x = -0.2 + 0.2 * k + 0.05 * math.sin(TAU * (f.t + k * 0.3))
            sprite(dot, f.cx + x, f.cy - 0.32 + 0.66 * g, 0.1 * (1 - 0.5 * g), z=0.3 + 0.01 * k, a=math.sin(math.pi * g), c=0.6)


@reg("fx_voidring")
def b_voidring(F, rng):
    def sh():
        X, Y = coords()
        t = attr("t")
        r = length(X, Y)
        th = atan2(Y, X)
        e = t * t
        R = 0.4 - 0.33 * e
        w = 0.03 + 0.035 * e
        dist = ab(r - R)
        ring = 1 - sstep(0.0, w, dist)
        void = (1 - sstep(R - 0.01, R, r)) * (0.35 + 0.45 * e)
        k = th * (28 / TAU)
        idx = floor(k)
        fk = fract(k)
        rnd = noise(idx * 1.37, 0.5, 0.0, 0.0, 1.0, 0.0)
        rnd2 = noise(idx * 2.11, 3.5, 0.0, 0.0, 1.0, 0.0)
        Ls = (0.1 + 0.16 * rnd2) * (1 - 0.5 * e)
        off = R + 0.02 + (0.04 + 0.1 * rnd) * (1 - t)
        su = clamp01((r - off) / Ls)
        streak = sstep(0.5, 0.56, rnd + 0.2) * (1 - sstep(0.0, 0.2 * (1 - su), ab(fk - 0.5))) * sstep(-0.005, 0.0, r - off) * (1 - sstep(0.95, 1.0, su))
        flash = sstep(0.7, 1.0, t) * (1 - sstep(0.0, 0.11, r))
        h = mx(mx(ring, streak * 0.62), flash)
        col = ramp(h, [(0.0, (26, 8, 46)), (0.3, EL["Shadow"]), (0.62, (196, 146, 246)), (1.0, (246, 232, 255))])
        a = mx(void, sstep(0.05, 0.35, h))
        finish(col, a * cellmask(X, Y))
    m = material("voidring", sh)
    for f in F:
        cellplane(m, f)


@reg("fx_darkglass")
def b_darkglass(F, rng):
    def glass_sh():
        X, Y = coords()
        d = normal_dot(LIGHT)
        col = ramp(d, [(0.0, (22, 8, 38)), (0.5, (40, 18, 66)), (0.86, (96, 56, 156)), (0.96, (240, 228, 255))], "CONSTANT")
        sheen = 1 - sstep(0.008, 0.014, ab((X + Y) * 0.7 - 0.02))
        col = mixc(col, rgb((214, 186, 255)), sheen * sstep(0.2, 0.5, d))
        finish_opaque(col)
    toon = material("glass", glass_sh, blended=False)
    line = mat_flat("glassline", (184, 116, 252), cull=True)
    glow = mat_softglow("glassglow", [(0.0, (90, 40, 150)), (1.0, (170, 110, 235))], alpha=0.32)
    shards = []
    for (x, y, sc) in ((-0.11, 0.11, 1.0), (0.2, -0.05, 0.8), (-0.11, -0.21, 0.7)):
        bm = bmesh.new()
        nv = rng.choice((3, 4))
        a0 = rng.uniform(0, TAU)
        ring = []
        for k in range(nv):
            a = a0 + TAU * k / nv + rng.uniform(-0.35, 0.35)
            rr = rng.uniform(0.13, 0.2)
            ring.append((math.cos(a) * rr, math.sin(a) * rr))
        top = [bm.verts.new((px, py, 0.015)) for px, py in ring]
        bot = [bm.verts.new((px, py, -0.015)) for px, py in ring]
        bm.faces.new(top)
        bm.faces.new(list(reversed(bot)))
        for k in range(nv):
            bm.faces.new((top[k], bot[k], bot[(k + 1) % nv], top[(k + 1) % nv]))
        me = mesh_from_bm(bm, "glass", toon)
        bm.free()
        shards.append(dict(me=me, hull=hull_mesh(me, 0.014 / sc, line), x=x, y=y, sc=sc,
                           r0=[rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, TAU)],
                           n=[rng.choice((1, -1)), rng.choice((0, 1, -1)), rng.choice((1, -1))]))
    for f in F:
        sprite(glow, f.cx, f.cy, 1.0, z=-0.5, a=1.0)
        for s in shards:
            rot = (s["r0"][0] + 0.5 * math.sin(TAU * f.t * s["n"][0]), s["r0"][1] + TAU * f.t * s["n"][1], s["r0"][2] + TAU * f.t * s["n"][2] * 0.5 * 2)
            solid(s["me"], s["hull"], f.cx + s["x"], f.cy + s["y"], 1.0 + 0.5 * shards.index(s), rot, s["sc"])


# ================================================================= SHARED (runtime tint)
@reg("fx_slash")
def b_slash(F, rng):
    """crescent swipe: bright leading rim fading to the inner edge, speed streaks, sweeps left -> right then dissolves"""
    def sh():
        X, Y = coords()
        t = attr("t")
        ya = Y + 0.1
        dA = length(X, ya)
        dB = length(X, Y + 0.26)
        dout = 0.4 - dA
        din = dB - 0.36
        inside = sstep(-0.003, 0.003, mn(dout, din))
        s = clamp01(dout / mx(dout + din, 0.001))
        phi = atan2(X, ya)
        a = (phi + 2.02) / 4.04
        hd = 0.32 + 0.82 * (1 - (1 - clamp01(t / 0.3)) ** 2)
        tl = -0.12 + 0.72 * sstep(0.2, 1.0, t)
        vis = sstep(tl, tl + 0.18, a) * sstep(hd + 0.01, hd - 0.05, a)
        b = clamp01((a - tl) / mx(hd - tl, 0.01))
        streak = noise(dA * 40, phi * 1.2, 0.0, 0.0, 1.0, 1.0)
        brk = noise(X, Y, 3.0, 0.0, 7.0, 2.0)
        h = (1 - s) ** 0.9 * (0.4 + 0.6 * b ** 0.7) * (0.85 + 0.6 * (streak - 0.5))
        h = h - sstep(0.45, 1.0, t) * 0.5 * brk
        col = ramp(clamp01(h * 1.3), [(0.0, (176, 178, 190)), (0.4, (226, 228, 236)), (0.72, WHITE), (1.0, WHITE)])
        body = sstep(0.05, 0.2, h) * inside
        rim = (1 - sstep(0.0, 0.03, ab(dout))) * (1 - inside) * 0.35 * b
        finish(col, mx(body, rim) * vis * cellmask(X, Y))
    m = material("slash", sh)
    for f in F:
        cellplane(m, f)


@reg("fx_shock")
def b_shock(F, rng):
    def sh():
        X, Y = coords()
        t = attr("t")
        r = length(X, Y)
        R = 0.07 + 0.36 * (1 - (1 - t) * (1 - t))
        th = 0.1 * (1 - 0.72 * t) + 0.014
        q = (R - r) / th
        ring = sstep(-0.12, 0.0, q) * sstep(1.0, 0.0, q) ** 1.5 * sstep(1.05, 0.95, q)
        fill = (1 - sstep(R * 0.8, R, r)) * 0.08 * (1 - t)
        fade = 1 - 0.5 * t
        col = ramp(clamp01(ring), NEUTRAL)
        finish(col, mx(ring * fade, fill) * cellmask(X, Y))
    m = material("shock", sh)
    for f in F:
        cellplane(m, f)


@reg("fx_glow")
def b_glow(F, rng):
    def sh():
        X, Y = coords()
        t = attr("t")
        pulse = 1 + 0.07 * sin(t * TAU)
        r = length(X, Y) / (0.45 * pulse)
        g = (1 - sstep(0.0, 1.0, r)) ** 1.6
        core = 1 - sstep(0.0, 0.4, r)
        finish(ramp(clamp01(g * 0.7 + core * 0.5), NEUTRAL), g * cellmask(X, Y))
    m = material("glow", sh)
    for f in F:
        cellplane(m, f)


@reg("fx_streak")
def b_streak(F, rng):
    def sh():
        X, Y = coords()
        xt, wb = attr("c"), attr("b")
        xh = 0.34
        s = clamp01((X - xt) / (xh - xt))
        w = 0.062 * wb * s ** 1.3 + 0.002
        db = mx(mx(ab(Y) - w, xt - X), X - xh)
        dh = length(X - xh, Y) - 0.062 * wb
        d = mn(db, dh)
        h = clamp01(1 - ab(Y) / mx(w, 0.004)) * sstep(0.004, -0.004, d)
        glow = (1 - sstep(0.0, 0.06, d)) ** 2 * 0.45 * (0.3 + 0.7 * s)
        col = ramp(clamp01(h * 1.2), NEUTRAL)
        finish(col, mx(sstep(0.003, -0.003, d), glow) * cellmask(X, Y))
    m = material("streak", sh)
    dot = mat_glowdot("streakdot", NEUTRAL, halo=0.5)
    dots = [dict(x0=rng.uniform(-0.3, 0.1), y=rng.uniform(-0.06, 0.06), sp=rng.choice((1, 2)), s=rng.uniform(0.04, 0.07)) for _ in range(3)]
    for f in F:
        xt = -0.42 + 0.05 * math.sin(TAU * 2 * f.t) + 0.03 * math.sin(TAU * 3 * f.t + 1)
        wb = 0.9 + 0.12 * math.sin(TAU * 4 * f.t + 0.5)
        cellplane(m, f, c=xt, b=wb)
        for k, d in enumerate(dots):
            g = (d["x0"] + 0.5 + f.t * d["sp"]) % 1.0
            x = 0.3 - 0.75 * g
            sprite(dot, f.cx + x, f.cy + d["y"], d["s"] * (1 - 0.5 * g), z=0.1 + 0.01 * k, a=1 - g, c=1.0)


@reg("fx_speedlines")
def b_speedlines(F, rng):
    """Beam strip (grid 1): tapered speed-line dashes in lanes, each repeated at -4 / 0 / +4 so the strip tiles along U"""
    def sh():
        X, Y = coords()
        A = attr("a")
        s = ab(X * 2)
        front = 0.65 + 0.35 * clamp01(0.5 - X)
        w = 0.5 * clamp01(1 - s) ** 0.6 * front
        d = ab(Y) - w
        h = clamp01(1 - ab(Y) / mx(w, 0.01))
        finish(ramp(h, NEUTRAL), sstep(0.03, -0.03, d) * A)
    m = material("speedline", sh)
    lanes = [-0.36, -0.26, -0.15, -0.05, 0.05, 0.15, 0.26, 0.36]
    for k, y in enumerate(lanes):
        x = rng.uniform(-2.0, 2.0)
        for j in range(rng.choice((2, 3))):
            L = rng.uniform(0.45, 1.2)
            th = rng.uniform(0.028, 0.044)
            yy = y + rng.uniform(-0.015, 0.015)
            a = rng.uniform(0.65, 1.0)
            for off in (-STRIP_P, 0.0, STRIP_P):
                sprite(m, x + off, yy, L, th, z=0.01 * k + 0.001 * j, a=a)
            x += L + rng.uniform(0.2, 0.7)


@reg("fx_hexshield")
def b_hexshield(F, rng):
    def sh():
        X, Y = coords()
        t = attr("t")
        r = length(X, Y)
        Rd = 0.44
        mask = sstep(Rd, Rd - 0.008, r)
        hs = 0.1
        qx, qy = X / hs, Y / hs
        rx, ry = 1.0, 1.7320508

        def fmod(v, m):
            return v - m * floor(v / m)
        ax, ay = fmod(qx, rx) - rx / 2, fmod(qy, ry) - ry / 2
        bx, by = fmod(qx - rx / 2, rx) - rx / 2, fmod(qy - ry / 2, ry) - ry / 2
        pick = sstep(-0.0001, 0.0001, (bx * bx + by * by) - (ax * ax + ay * ay))
        gx, gy = mix(bx, ax, pick), mix(by, ay, pick)
        hd = mx(ab(gx) * 0.5 + ab(gy) * 0.8660254, ab(gx))
        edge = 0.5 - hd
        w = 0.5 - t * 0.0
        wave = r - (t * 0.62 - 0.06)
        rip = (1 - sstep(0.0, 0.07, ab(wave)))
        lw = 0.05 + 0.05 * rip
        line = sstep(lw + 0.02, lw, edge)
        rim = sstep(0.22, 0.44, r)
        border = 1 - sstep(0.008, 0.016, ab(r - (Rd - 0.014)))
        a = (0.14 + 0.22 * rim + line * (0.45 + 0.35 * rim + 0.4 * rip) + rip * 0.25) * mask
        a = mx(a, border * mask)
        h = clamp01(line * 0.7 + rip * 0.5 + border + rim * 0.2)
        finish(ramp(h, [(0.0, (190, 196, 210)), (0.5, (236, 240, 248)), (1.0, WHITE)]), a)
    m = material("hexshield", sh)
    for f in F:
        cellplane(m, f)


# ================================================================= render + output
def setup_scene(width=SIZE, height=SIZE):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()
    _QUAD.clear()
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = width
    sc.render.resolution_y = height
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.filter_size = 1.2
    sc.render.dither_intensity = 0.0
    sc.render.use_compositing = False
    sc.render.use_sequencer = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.render.image_settings.compression = 15
    sc.display_settings.display_device = "sRGB"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    sc.eevee.taa_render_samples = 32
    w = bpy.data.worlds.new("w")
    w.color = (0, 0, 0)
    sc.world = w
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = float(GRID)
    cam.clip_start = 0.1
    cam.clip_end = 100.0
    co = bpy.data.objects.new("cam", cam)
    co.location = (0.0, 0.0, 30.0)
    sc.collection.objects.link(co)
    sc.camera = co
    return sc


def write_png(path, rgba):
    h, w, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def post(tmp, out_path, key, grid=GRID):
    img = bpy.data.images.load(tmp, check_existing=False)
    w, h = img.size
    buf = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    a = np.ascontiguousarray(np.round(buf.reshape(h, w, 4)[::-1] * 255.0).clip(0, 255).astype(np.uint8))
    band = np.zeros((h, w), bool)
    if grid == GRID:
        for k in range(GRID + 1):
            lo, hi = max(0, k * CELL - 2), min(SIZE, k * CELL + 2)
            band[lo:hi, :] = True
            band[:, lo:hi] = True
    else:
        band[:2, :] = True
        band[-2:, :] = True
        al = a[..., 3].astype(np.float64)
        seam = float(np.abs(al[:, -1] - al[:, 0]).mean())
        step = float(np.abs(al[:, 1:] - al[:, :-1]).mean())
        print("  %s strip seam: |last col - first col| %.2f vs mean neighbour step %.2f" % (key, seam, step))
    bleed = int(a[..., 3][band].max())
    if bleed > 8:
        print("  WARN %s: alpha %d within 2 px of a cell / strip border (cleared)" % (key, bleed))
    a[band, 3] = 0
    clear = a[..., 3] == 0
    a[clear, 0], a[clear, 1], a[clear, 2] = DARK
    write_png(out_path, a)
    return bleed


def render_key(entry, out_dir):
    key = entry["key"]
    grid = entry["grid"]
    if grid == 1:
        # a Beam strip: one frame, size x height pixels = 4 x (4 * height / size) world units, centred on the origin
        setup_scene(entry["size"], entry["height"])
        f = Fr(0, 0.0)
        f.cx = f.cy = 0.0
        F = [f]
    else:
        setup_scene()
        n = GRID * GRID
        loop = entry["mode"] == "Loop"
        F = [Fr(i, i / n if loop else i / (n - 1)) for i in range(n)]
    rng = random.Random(SEED + zlib.crc32(key.encode()))
    BUILD[key](F, rng)
    tmp = os.path.join(out_dir, "_render_%s.png" % key)
    bpy.context.scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    bleed = post(tmp, os.path.join(out_dir, key + ".png"), key, grid)
    os.remove(tmp)
    return bleed


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.join(HERE, "out")
    keys = []
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 2
        elif argv[i] == "--key":
            keys.append(argv[i + 1])
            i += 2
        else:
            raise SystemExit("unknown argument %r" % argv[i])
    out = os.path.abspath(out)
    os.makedirs(out, exist_ok=True)
    with open(MANIFEST, "rb") as f:
        man = json.loads(f.read().decode("utf-8"))
    entries = man["textures"]
    missing = [e["key"] for e in entries if e["key"] not in BUILD]
    if missing:
        raise SystemExit("no builder for %s" % ", ".join(missing))
    if keys:
        unknown = [k for k in keys if k not in {e["key"] for e in entries}]
        if unknown:
            raise SystemExit("unknown key(s) %s" % ", ".join(unknown))
        entries = [e for e in entries if e["key"] in keys]
    t0 = time.time()
    for e in entries:
        t1 = time.time()
        bleed = render_key(e, out)
        print("VFX %-14s %5.1fs  border alpha %d" % (e["key"], time.time() - t1, bleed))
    print("VFX rendered %d sheet(s) in %.1fs -> %s" % (len(entries), time.time() - t0, out))


if __name__ == "__main__":
    main()
