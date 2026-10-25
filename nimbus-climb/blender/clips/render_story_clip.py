"""Nimbus Climb story clip, "Worthy of the Storm": 900 frames, 30 fps, 1920 x 1080, one MP4.

    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe blender/clips/render_story_clip.py --preview   # 6 stills -> play/clips/preview/
    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe blender/clips/render_story_clip.py --full      # 900 frames -> play/clips/nimbus_story_clip.mp4
    ... --frames 75,210 [--res 50] [--samples 16] [--cycles] [--rebuild-assets] [--save-blend]

Rules: blender/clips/CLIP_RULES.md.  Every pet, boss, coin, gate and station is the game's real mesh, built by
blender/build_all.py's Builder through clip_assets.py (read-only: nothing in src/, blender/out or the manifests is
written).  The Roblox Climber is a hand-built R6 rig (below).  All motion is baked by a "director" (one function per
actor per frame, written with anticipation / overshoot / settle easing) into BEZIER keys with AUTO_CLAMPED handles;
cameras are bound to timeline markers, so the whole film is one continuous render.

Acts (frames): 1 Rejected at the Storm Altar (1-150), 2 The Clenched Fist (151-270), 3 The Evolution Pillar
(271-450), 4 The Saint Sky-Dash (451-600), 5 Slaying the Hydra (601-750), 6 Stormfang's Oath (751-900).
"""
import argparse
import math
import os
import random
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # the project path has Hebrew letters
except Exception:
    pass

import numpy as np  # noqa: E402

import clip_assets as CA  # noqa: E402

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

FPS = 30
N = 900
PREVIEW_FRAMES = [75, 210, 390, 525, 675, 840]
OUT_DIR = os.path.join(REPO, "play", "clips")
PREVIEW_DIR = os.path.join(OUT_DIR, "preview")
FRAMES_DIR = os.path.join(OUT_DIR, "frames")
MP4 = os.path.join(OUT_DIR, "nimbus_story_clip.mp4")
SKY_DIR = os.path.join(REPO, "branding", "sky")
FONT = r"C:\Windows\Fonts\GOTHICB.TTF"  # Century Gothic Bold: closest local font to the game's GothamBold

# the four sets, far apart in one world (studs = Blender units)
ALTAR = Vector((0.0, 0.0, 0.0))
HOME = Vector((700.0, 0.0, 0.0))
SKY = Vector((0.0, 700.0, 0.0))
ARENA = Vector((-700.0, 0.0, 0.0))

TAU = math.pi * 2
V = Vector


# ================================================================================================ easing (PetPoses style)
def clamp01(x):
    return 0.0 if x < 0 else 1.0 if x > 1 else x


def seg(f, a, b):
    """0..1 progress of frame f through [a, b]"""
    return clamp01((f - a) / float(b - a)) if b != a else (1.0 if f >= b else 0.0)


def smooth(x):
    x = clamp01(x)
    return x * x * (3 - 2 * x)


def smoother(x):
    x = clamp01(x)
    return x * x * x * (x * (x * 6 - 15) + 10)


def out_cubic(x):
    x = clamp01(x)
    return 1 - (1 - x) ** 3


def in_cubic(x):
    x = clamp01(x)
    return x ** 3


def in_quad(x):
    x = clamp01(x)
    return x * x


def out_back(x, s=1.70158):
    x = clamp01(x) - 1
    return x * x * ((s + 1) * x + s) + 1


def settle(u, amp=0.12, cycles=1.5):
    """damped wobble after an arrival: 0 at u=0 and fading to 0 at u=1"""
    u = clamp01(u)
    return amp * math.sin(u * math.pi * 2 * cycles) * (1 - u) ** 2


def lerp(a, b, t):
    return a + (b - a) * t


def vlerp(a, b, t):
    return a.lerp(b, t)


def hop(p0, p1, t, h):
    """a jump arc from p0 to p1 (t 0..1), apex h studs above the higher end"""
    p = p0.lerp(p1, t)
    top = max(p0.z, p1.z) + h
    # parabola through p0.z, p1.z with the apex height ~top
    a = 4 * (top - (p0.z + p1.z) / 2)
    p.z = lerp(p0.z, p1.z, t) + a * t * (1 - t)
    return p


def yaw_to(d):
    """yaw (about +Z) that turns a model facing local -Y toward direction d: Rz(yaw) @ (0,-1,0) = (sin, -cos)"""
    return math.atan2(d.x, -d.y) if (abs(d.x) + abs(d.y)) > 1e-6 else 0.0


def fwd(yaw):
    return V((math.sin(yaw), -math.cos(yaw), 0.0))


def right(yaw):
    # forward x up: facing -Y (yaw 0), right is -X
    return V((-math.cos(yaw), -math.sin(yaw), 0.0))


assert (fwd(yaw_to(V((1, 2, 0)))) - V((1, 2, 0)).normalized()).length < 1e-9
assert (right(0.0) - V((-1, 0, 0))).length < 1e-9


def wrap_angle(a):
    return (a + math.pi) % TAU - math.pi


def ang_lerp(a, b, t):
    return a + wrap_angle(b - a) * t


RNG = random.Random(7)


# ================================================================================================ materials
def lin(c):
    c = c / 255.0 if c > 1.0 else c
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(r, g, b, a=1.0):
    return (lin(r), lin(g), lin(b), a)


def principled(name, color, rough=0.5, metal=0.0, coat=0.0, emit=None, emit_strength=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if coat:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.08
    if emit is not None:
        b.inputs["Emission Color"].default_value = emit
        b.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    m.diffuse_color = color
    return m


def emission(name, color, strength=4.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    if alpha < 1.0:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.inputs[0].default_value = alpha
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    else:
        nt.links.new(em.outputs[0], out.inputs["Surface"])
    m["strength_socket"] = 1
    return m


def mat_strength_socket(m):
    if m.node_tree.nodes.get("Emission"):
        return m.node_tree.nodes["Emission"].inputs["Strength"]
    return m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"]


def mat_alpha_socket(m):
    mix = m.node_tree.nodes.get("Mix Shader")
    return mix.inputs[0] if mix else None


# ================================================================================================ mesh helpers
def link(ob, coll, parent=None):
    coll.objects.link(ob)
    if parent is not None:
        ob.parent = parent
    return ob


def empty(name, coll, parent=None, loc=(0, 0, 0), size=0.4):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    e.location = loc
    return link(e, coll, parent)


def box(name, coll, size, center=(0, 0, 0), mat=None, bevel=0.06, parent=None, segs=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V((v.co.x * size[0] + center[0], v.co.y * size[1] + center[1], v.co.z * size[2] + center[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segs, affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    if mat is not None:
        me.materials.append(mat)
    return link(bpy.data.objects.new(name, me), coll, parent)


def mesh_from(name, coll, verts, faces, mat=None, parent=None, smooth_shade=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate()
    if smooth_shade:
        for p in me.polygons:
            p.use_smooth = True
    if mat is not None:
        me.materials.append(mat)
    return link(bpy.data.objects.new(name, me), coll, parent)


def ring_mesh(name, coll, r_in, r_out, n=64, z=0.0, mat=None, parent=None):
    verts, faces = [], []
    for i in range(n):
        a = TAU * i / n
        verts += [(math.cos(a) * r_in, math.sin(a) * r_in, z), (math.cos(a) * r_out, math.sin(a) * r_out, z)]
    for i in range(n):
        j = (i + 1) % n
        faces.append((2 * i, 2 * i + 1, 2 * j + 1, 2 * j))
    return mesh_from(name, coll, verts, faces, mat, parent)


def disc_mesh(name, coll, r, n=64, z=0.0, mat=None, parent=None):
    verts = [(0, 0, z)] + [(math.cos(TAU * i / n) * r, math.sin(TAU * i / n) * r, z) for i in range(n)]
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    return mesh_from(name, coll, verts, faces, mat, parent)


def tube_mesh(name, coll, r0, r1, h, n=24, mat=None, parent=None, cap=False):
    """an open tube along +Z (light pillars, beams): radius r0 at the bottom, r1 at the top"""
    verts, faces = [], []
    for i in range(n):
        a = TAU * i / n
        verts += [(math.cos(a) * r0, math.sin(a) * r0, 0.0), (math.cos(a) * r1, math.sin(a) * r1, h)]
    for i in range(n):
        j = (i + 1) % n
        faces.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
    return mesh_from(name, coll, verts, faces, mat, parent, smooth_shade=True)


def gem_mesh(name, coll, mat, size=0.5):
    """a brilliant-cut Prestige Gem: crown, girdle and pavilion (8 facets), hand-built"""
    n = 8
    verts = [(0, 0, 0.55 * size)]
    for i in range(n):
        a = TAU * (i + 0.5) / n
        verts.append((math.cos(a) * 0.32 * size, math.sin(a) * 0.32 * size, 0.42 * size))
    for i in range(n):
        a = TAU * i / n
        verts.append((math.cos(a) * 0.5 * size, math.sin(a) * 0.5 * size, 0.18 * size))
    verts.append((0, 0, -0.55 * size))
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((0, 1 + i, 1 + j))
        faces.append((1 + i, 1 + n + i, 1 + n + j, 1 + j) if False else (1 + i, 1 + n + j, 1 + j))
        faces.append((1 + i, 1 + n + i, 1 + n + j))
        faces.append((1 + n + i, 2 * n + 1, 1 + n + j))
    return mesh_from(name, coll, verts, faces, mat)


def bolt_mesh(name, coll, a, b, mat, width=0.35, kinks=9, jitter=1.6, seed=1, parent=None):
    """a jagged lightning ribbon from a to b (two crossed ribbons so it reads from any side)"""
    r = random.Random(seed)
    pts = [a]
    d = b - a
    side = d.cross(V((0, 0, 1)))
    if side.length < 1e-3:
        side = V((1, 0, 0))
    side.normalize()
    up = d.cross(side).normalized()
    for i in range(1, kinks):
        t = i / kinks
        pts.append(a + d * t + side * r.uniform(-jitter, jitter) + up * r.uniform(-jitter, jitter) * 0.6)
    pts.append(b)
    verts, faces = [], []
    for axis in (side, up):
        base = len(verts)
        for i, p in enumerate(pts):
            w = width * (1.0 - 0.6 * i / len(pts))
            verts += [p - axis * w, p + axis * w]
        for i in range(len(pts) - 1):
            faces.append((base + 2 * i, base + 2 * i + 1, base + 2 * i + 3, base + 2 * i + 2))
    return mesh_from(name, coll, verts, faces, mat, parent)


def instance_copy(src_root, name, coll):
    """a linked duplicate of an asset hierarchy (shared mesh data), returns the new root"""
    mapping = {}

    def dup(ob, parent):
        n = ob.copy()
        n.name = name + "_" + ob.name
        coll.objects.link(n)
        n.parent = parent
        if parent is not None:
            n.matrix_parent_inverse = ob.matrix_parent_inverse.copy()
        mapping[ob] = n
        for c in ob.children:
            dup(c, n)
        return n

    return dup(src_root, None)


# ================================================================================================ keyframe baking
class Baker:
    """collects per-frame values, then writes BEZIER / AUTO_CLAMPED keys (CONSTANT for on/off channels)"""

    def __init__(self):
        self.tracks = {}  # (id_data, path, index) -> [frames], [values], constant

    def key(self, idb, path, index, f, value, constant=False):
        if not isinstance(idb, bpy.types.ID):  # a node socket: key it on its node tree with the full path
            path = idb.path_from_id() + "." + path
            idb = idb.id_data
        t = self.tracks.get((idb, path, index))
        if t is None:
            t = self.tracks[(idb, path, index)] = ([], [], constant)
        t[0].append(f)
        t[1].append(float(value))

    def loc(self, ob, f, p):
        for i in range(3):
            self.key(ob, "location", i, f, p[i])

    def rot(self, ob, f, e):
        for i in range(3):
            self.key(ob, "rotation_euler", i, f, e[i])

    def scale(self, ob, f, s):
        s = (s, s, s) if isinstance(s, (int, float)) else s
        for i in range(3):
            self.key(ob, "scale", i, f, s[i])

    def show(self, ob, f, on):
        self.key(ob, "hide_render", -1, f, 0.0 if on else 1.0, constant=True)
        self.key(ob, "hide_viewport", -1, f, 0.0 if on else 1.0, constant=True)

    def write(self):
        n_keys = 0
        for (idb, path, index), (fr, va, constant) in self.tracks.items():
            if idb.animation_data is None:
                idb.animation_data_create()
            act = idb.animation_data.action
            if act is None:
                act = bpy.data.actions.new("A_" + idb.name)
                idb.animation_data.action = act
            fc = act.fcurve_ensure_for_datablock(idb, path, index=max(index, 0))
            # drop repeated values (keeps first/last of a hold) to keep the curves light
            co = []
            for i, (f, v) in enumerate(zip(fr, va)):
                if 0 < i < len(fr) - 1 and va[i - 1] == v == va[i + 1]:
                    continue
                co += [f, v]
            fc.keyframe_points.add(len(co) // 2)
            fc.keyframe_points.foreach_set("co", co)
            interp = "CONSTANT" if constant else "BEZIER"
            for k in fc.keyframe_points:
                k.interpolation = interp
                k.handle_left_type = "AUTO_CLAMPED"
                k.handle_right_type = "AUTO_CLAMPED"
            fc.update()
            n_keys += len(co) // 2
        return n_keys


# ================================================================================================ the Climber (hand-built R6 rig)
def hibiscus_tile(path, size=1024, seed=3):
    """a seamless Hawaiian print tile: magenta ground, dark leaves, white five-petal hibiscus with pink hearts"""
    from PIL import Image, ImageDraw
    r = random.Random(seed)
    big = Image.new("RGB", (size * 3, size * 3), (212, 34, 164))
    d = ImageDraw.Draw(big)
    flowers = [(r.uniform(0, size), r.uniform(0, size), r.uniform(70, 120), r.uniform(0, TAU)) for _ in range(7)]
    leaves = [(r.uniform(0, size), r.uniform(0, size), r.uniform(0, TAU)) for _ in range(16)]

    def ell(cx, cy, rx, ry, ang, col):
        pts = []
        for i in range(24):
            t = TAU * i / 24
            x, y = math.cos(t) * rx, math.sin(t) * ry
            pts.append((cx + x * math.cos(ang) - y * math.sin(ang), cy + x * math.sin(ang) + y * math.cos(ang)))
        d.polygon(pts, fill=col)

    for ox in (0, size, 2 * size):
        for oy in (0, size, 2 * size):
            for x, y, ang in leaves:
                ell(ox + x, oy + y, 70, 24, ang, (122, 12, 98))
                ell(ox + x, oy + y, 60, 6, ang, (150, 30, 120))
            for x, y, rad, ang in flowers:
                for k in range(5):
                    pa = ang + TAU * k / 5
                    ell(ox + x + math.cos(pa) * rad * 0.55, oy + y + math.sin(pa) * rad * 0.55, rad * 0.55, rad * 0.36,
                        pa, (252, 244, 250))
                ell(ox + x, oy + y, rad * 0.42, rad * 0.42, 0, (255, 150, 214))
                ell(ox + x, oy + y, rad * 0.14, rad * 0.14, 0, (255, 220, 90))
    big.crop((size, size, 2 * size, 2 * size)).save(path)
    return path


def hawaiian(name, tile_studs=2.4):
    """the magenta Hawaiian shirt: the painted hibiscus tile box-projected in object space"""
    path = os.path.join(CA.CACHE, "hibiscus.png")
    if not os.path.exists(path):
        os.makedirs(CA.CACHE, exist_ok=True)
        hibiscus_tile(path)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.5
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / tile_studs, 1 / tile_studs, 1 / tile_studs)
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(path)
    img.projection = "BOX"
    img.projection_blend = 0.15
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], img.inputs["Vector"])
    nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    m.diffuse_color = rgb(212, 34, 164)
    return m


class Climber:
    """The player's own avatar, hand-built as a blocky Roblox R6 rig: light skin, swoopy brown hair, purple shades,
    a magenta Hawaiian shirt with a gold striped tie, dark teal shorts, white sneakers, a brown leather satchel at the
    left hip, and the UFO hat (built separately in Film.build_ufo: it hovers upright above the head).
    Local frame: feet at the origin, facing -Y, up +Z, right = -X.
    Joints: Hip (body lean), Neck, ShoulderL/R, HipL/R, KnuckleR/L (fist curl)."""

    def __init__(self, coll):
        skin = principled("Climber_Skin", rgb(250, 212, 178), rough=0.32, coat=0.4)
        shirt = hawaiian("Climber_Shirt")
        tie = principled("Climber_Tie", rgb(236, 186, 48), rough=0.3, metal=0.2)
        tie2 = principled("Climber_TieStripe", rgb(176, 112, 20), rough=0.35)
        shorts = principled("Climber_Shorts", rgb(28, 70, 92), rough=0.65)
        shoe = principled("Climber_Shoe", rgb(242, 238, 228), rough=0.45)
        sole = principled("Climber_Sole", rgb(196, 160, 116), rough=0.6)
        hair = principled("Climber_Hair", rgb(92, 54, 30), rough=0.55)
        hair2 = principled("Climber_HairLight", rgb(124, 76, 42), rough=0.5)
        lens = principled("Climber_Shades", rgb(40, 18, 64), rough=0.05, coat=1.0, emit=rgb(140, 70, 255),
                          emit_strength=0.4)
        rim = principled("Climber_ShadesRim", rgb(150, 60, 200), rough=0.3, metal=0.6)
        mouth = principled("Climber_Mouth", rgb(40, 22, 22), rough=0.4)
        leather = principled("Climber_Leather", rgb(112, 68, 38), rough=0.45, coat=0.3)
        strap = principled("Climber_Strap", rgb(78, 46, 24), rough=0.6)
        self.mats = dict(skin=skin, shirt=shirt, shorts=shorts)
        self.root = empty("Climber", coll, size=1.0)
        r = self.root
        self.hip = empty("Climber_Hip", coll, r, (0, 0, 2.0))
        box("Climber_Torso", coll, (2.0, 1.0, 2.0), (0, 0, 1.0), shirt, 0.07, self.hip)
        # open collar (two lapels) and the gold striped tie down the front (-Y)
        for sx, rz in ((-0.3, 0.5), (0.3, -0.5)):
            box("Climber_Collar", coll, (0.55, 0.12, 0.42), (sx, -0.53, 1.82), shirt, 0.04, self.hip).rotation_euler = (0, rz, 0)
        box("Climber_Neck", coll, (0.5, 0.06, 0.3), (0, -0.51, 1.86), skin, 0.02, self.hip)
        box("Climber_Tie", coll, (0.3, 0.08, 1.45), (0, -0.55, 1.0), tie, 0.03, self.hip)
        for i in range(5):
            box("Climber_TieStripe", coll, (0.3, 0.09, 0.07), (0, -0.556, 0.45 + 0.27 * i), tie2, 0.01, self.hip)
        box("Climber_TieKnot", coll, (0.36, 0.12, 0.24), (0, -0.56, 1.72), tie2, 0.04, self.hip)
        # the satchel strap across the chest and the brown leather satchel on the left hip (+X)
        box("Climber_Strap", coll, (0.2, 1.06, 2.5), (0, 0, 1.0), strap, 0.03, self.hip).rotation_euler = (0, -0.68, 0)
        box("Climber_Satchel", coll, (0.45, 1.05, 0.95), (1.2, -0.05, 0.05), leather, 0.12, self.hip)
        box("Climber_SatchelFlap", coll, (0.5, 1.1, 0.35), (1.22, -0.05, 0.38), strap, 0.08, self.hip)
        self.neck = empty("Climber_Neck", coll, self.hip, (0, 0, 2.0))
        box("Climber_Head", coll, (1.25, 1.2, 1.2), (0, 0, 0.62), skin, 0.3, self.neck, segs=4)
        # purple shades and a smile (static: no facial acting)
        for ex in (-0.26, 0.26):
            box("Climber_Lens", coll, (0.42, 0.06, 0.26), (ex, -0.62, 0.74), lens, 0.05, self.neck)
        box("Climber_Bridge", coll, (0.2, 0.05, 0.06), (0, -0.63, 0.8), rim, 0.01, self.neck)
        for sx in (-0.55, 0.55):
            box("Climber_Temple", coll, (0.08, 0.6, 0.06), (sx * 1.1, -0.35, 0.8), rim, 0.01, self.neck)
        for i in range(5):
            a = math.radians(-50 + 25 * i)
            box("Climber_Smile", coll, (0.09, 0.05, 0.06), (0.26 * math.sin(a), -0.61, 0.42 - 0.08 * math.cos(a)), mouth,
                0.02, self.neck)
        # swoopy brown hair: a full cap, the back, long sides, bangs swept down to the shades, messy tufts on top
        box("Climber_HairCap", coll, (1.46, 1.4, 0.52), (0, 0.04, 1.2), hair, 0.16, self.neck)
        box("Climber_HairBack", coll, (1.44, 0.4, 1.1), (0, 0.55, 0.76), hair, 0.14, self.neck)
        for sx in (-0.7, 0.7):
            box("Climber_HairSide", coll, (0.22, 1.05, 0.82), (sx, 0.12, 0.86), hair, 0.09, self.neck)
        for x, z, w, ry, col in ((-0.38, 1.0, 0.5, -0.25, hair2), (0.05, 1.02, 0.48, 0.1, hair),
                                 (0.42, 0.98, 0.46, 0.3, hair2)):
            box("Climber_Bang", coll, (w, 0.28, 0.42), (x, -0.6, z), col, 0.1, self.neck).rotation_euler = (0.12, ry, 0)
        tufts = [(-0.45, 0.05, 1.5, 0.35, -0.25), (-0.12, -0.2, 1.56, -0.2, 0.3), (0.22, 0.02, 1.55, 0.25, -0.2),
                 (0.48, 0.2, 1.48, -0.4, 0.15), (-0.3, 0.42, 1.46, 0.3, 0.35), (0.12, 0.45, 1.48, -0.15, -0.35),
                 (0.0, -0.45, 1.44, 0.0, 0.45)]
        for i, (x, y, z, ry, rx) in enumerate(tufts):
            box("Climber_Tuft", coll, (0.42, 0.42, 0.42), (x, y, z), hair2 if i % 3 == 0 else hair, 0.13,
                self.neck).rotation_euler = (rx, ry, 0.4 * i)
        self.sh = {}
        self.knuckle = {}
        for side, sx in (("L", 1.5), ("R", -1.5)):
            s = empty("Climber_Shoulder" + side, coll, self.hip, (sx, 0, 1.85))
            box("Climber_Arm" + side, coll, (0.98, 0.98, 1.55), (0, 0, -0.72), skin, 0.08, s)
            box("Climber_Sleeve" + side, coll, (1.06, 1.06, 0.72), (0, 0, -0.25), shirt, 0.06, s)
            # the hand: a palm block and a finger block that curls at the knuckle (a chunky Roblox mitten)
            box("Climber_Palm" + side, coll, (0.98, 0.98, 0.32), (0, 0, -1.62), skin, 0.08, s)
            k = empty("Climber_Knuckle" + side, coll, s, (0, -0.25, -1.78))
            box("Climber_Fingers" + side, coll, (0.94, 0.5, 0.36), (0, 0.25, -0.16), skin, 0.1, k)
            box("Climber_Thumb" + side, coll, (0.24, 0.3, 0.36), (-0.52 if side == "L" else 0.52, -0.22, -1.6), skin,
                0.07, s)
            self.sh[side] = s
            self.knuckle[side] = k
        self.leg = {}
        for side, sx in (("L", 0.5), ("R", -0.5)):
            h = empty("Climber_Hip" + side, coll, r, (sx, 0, 2.0))
            box("Climber_Shorts" + side, coll, (1.02, 1.02, 1.0), (0, 0, -0.45), shorts, 0.06, h)
            box("Climber_Cuff" + side, coll, (1.06, 1.06, 0.14), (0, 0, -0.95), shorts, 0.03, h)
            box("Climber_Leg" + side, coll, (0.94, 0.94, 0.9), (0, 0, -1.4), skin, 0.06, h)
            box("Climber_Shoe" + side, coll, (1.02, 1.14, 0.36), (0, -0.06, -1.8), shoe, 0.1, h)
            box("Climber_Sole" + side, coll, (1.04, 1.16, 0.1), (0, -0.06, -1.97), sole, 0.03, h)
            self.leg[side] = h
        # the coin socket in the right hand, and the gem socket on the right palm
        self.hand_socket = empty("Climber_HandSocketR", coll, self.sh["R"], (0, -0.2, -2.0))

    def pose(self, bk, f, st):
        """st: pos, yaw, pitch (lie back < 0), roll, lean, legL/R, armL/R (pitch), armLs/armRs (out to the side),
        head, curlL/R"""
        bk.loc(self.root, f, st["pos"])
        bk.rot(self.root, f, (st.get("pitch", 0.0), st.get("roll", 0.0), st["yaw"]))
        bk.loc(self.hip, f, (0, 0, 2.0 + st.get("hipz", 0.0)))
        bk.rot(self.hip, f, (st.get("lean", 0.0), 0, st.get("twist", 0.0)))
        bk.rot(self.neck, f, (st.get("head", 0.0), 0, st.get("headturn", 0.0)))
        # limbs hang along -Z; a positive swing angle means FORWARD (-Y), so the X rotation is negated
        bk.rot(self.leg["L"], f, (-st.get("legL", 0.0), 0, 0))
        bk.rot(self.leg["R"], f, (-st.get("legR", 0.0), 0, 0))
        bk.rot(self.sh["L"], f, (-st.get("armL", 0.0), -st.get("armLs", 0.0), 0))
        bk.rot(self.sh["R"], f, (-st.get("armR", 0.0), st.get("armRs", 0.0), 0))
        bk.rot(self.knuckle["L"], f, (-st.get("curlL", 0.0) * math.radians(110), 0, 0))
        bk.rot(self.knuckle["R"], f, (-st.get("curlR", 0.0) * math.radians(110), 0, 0))


def walk_pose(phase, amp_leg=0.6, amp_arm=0.55, bob=0.12):
    s = math.sin(phase)
    return dict(legL=amp_leg * s, legR=-amp_leg * s, armL=-amp_arm * s, armR=amp_arm * s,
                hipz=-bob * abs(math.cos(phase)), twist=0.06 * s)


# ================================================================================================ pets
class Pet:
    """a game pet / boss asset with its hinge pivots (wings, tail, aura, halo)"""

    def __init__(self, name, specs, coll, prefix=None, scale=1.0):
        self.root, self.groups, self.atts = CA.spawn(name, specs, coll, prefix=prefix)
        self.scale = scale
        self.mover = empty((prefix or name) + "_Mover", coll, size=1.0)
        self.root.parent = self.mover
        self.root.scale = (scale, scale, scale)
        self.wings = [(g[0], k) for k, g in self.groups.items() if k.startswith("_pivot_Wing")]
        self.rest = {ob: ob.matrix_basis.copy() for ob, _ in self.wings}
        self.tail = (self.groups.get("_hinge_Tail") or [None])[0]
        self.aura = (self.groups.get("_hinge_Aura") or [None])[0]
        self.halo = (self.groups.get("_hinge_Halo") or [None])[0]
        self.halo_rest = self.halo.location.copy() if self.halo else None
        self.objects = [o for k, g in self.groups.items() if not k.startswith("_") for o in g]

    def head_world(self, st):
        a = self.atts.get("HeadCenter")
        p = a.translation if a is not None else V((0, -1.0, 1.0))
        R = Euler((st.get("pitch", 0.0), st.get("roll", 0.0), st["yaw"]), "XYZ").to_matrix()
        return st["pos"] + R @ (p * self.scale * st.get("scale", 1.0))

    def bake(self, bk, f, st):
        bk.loc(self.mover, f, st["pos"])
        bk.rot(self.mover, f, (st.get("pitch", 0.0), st.get("roll", 0.0), st["yaw"]))
        bk.scale(self.mover, f, st.get("scale", 1.0))
        flap = st.get("flap", 0.0)
        for ob, k in self.wings:
            side = 1.0 if k.endswith("L") else -1.0
            rest = self.rest[ob]
            # flap about the hinge's local forward axis (Blender -Y) on top of the rest hinge
            e = rest.to_euler("XYZ")
            bk.rot(ob, f, (e.x, e.y + side * flap, e.z))
        if self.tail is not None:
            bk.rot(self.tail, f, (0, 0, st.get("tail", 0.0)))
        if self.aura is not None:
            bk.rot(self.aura, f, (0, 0, st.get("aura", 0.0)))
        if self.halo is not None:
            bk.loc(self.halo, f, self.halo_rest + V((0, 0, st.get("halo_bob", 0.0))))
            bk.rot(self.halo, f, (0, 0, st.get("halo", 0.0)))


def pet_life(f, st, speed=0.0, bob=0.22, flap_amp=0.32, flap_hz=2.2, stage=0):
    """continuous secondary motion: sine bob, wing flap, tail wag, aura/halo spin"""
    t = f / FPS
    st = dict(st)
    st["pos"] = st["pos"] + V((0, 0, bob * math.sin(TAU * t / 1.6)))
    st["flap"] = flap_amp * math.sin(TAU * t * (flap_hz + 0.08 * speed))
    st["tail"] = 0.35 * math.sin(TAU * t * 1.3)
    st["aura"] = t * (2.4 if stage == 2 else 1.6)
    st["halo"] = t * 0.9
    st["halo_bob"] = 0.12 * math.sin(TAU * t / 1.2)
    return st


def lean_into(states, i, k_pitch=0.035, k_roll=0.05, lim=0.45):
    """pitch / roll toward the direction of travel, from the neighbouring frames"""
    a = states[max(i - 1, 0)]["pos"]
    b = states[min(i + 1, len(states) - 1)]["pos"]
    v = (b - a) * (FPS / 2.0)
    yaw = states[i]["yaw"]
    fv = v.dot(fwd(yaw))
    rv = v.dot(right(yaw))
    p = max(-lim, min(lim, -k_pitch * fv))
    r = max(-lim, min(lim, k_roll * rv))
    return p, r, v.length


# ================================================================================================ the world
class World:
    def __init__(self, args):
        self.args = args
        self.specs = CA.load_specs(rebuild=args.rebuild_assets)
        sc = bpy.context.scene
        self.sc = sc
        self.coll = sc.collection
        self.set_meshes = {"altar": [], "home": [], "sky": [], "arena": []}
        self.bk = Baker()

    # -------------------------------------------------------------------------------------- render + world
    def setup_render(self):
        sc, a = self.sc, self.args
        sc.render.fps = FPS
        sc.frame_start, sc.frame_end = 1, N
        sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
        sc.render.resolution_percentage = a.res
        if a.cycles:
            try:
                sc.render.engine = "CYCLES"
                sc.cycles.samples = a.samples or 64
                sc.cycles.use_denoising = True
                sc.cycles.device = "GPU"
            except Exception as exc:  # the bpy wheel may ship without Cycles
                print("[clip] Cycles not available (%s): EEVEE" % exc)
                sc.render.engine = "BLENDER_EEVEE"
        if sc.render.engine != "CYCLES":
            sc.render.engine = "BLENDER_EEVEE"  # EEVEE Next (the only EEVEE in Blender 5)
            ee = sc.eevee
            ee.taa_render_samples = a.samples or 32
            ee.use_raytracing = True
            try:
                ee.ray_tracing_options.resolution_scale = "1"
                ee.ray_tracing_options.trace_max_roughness = 0.4
            except Exception:
                pass
            ee.use_shadows = True
            try:
                ee.shadow_pool_size = "1024"
            except Exception:
                pass
            ee.volumetric_tile_size = "4"
            ee.volumetric_samples = 64
            ee.volumetric_start = 0.5
            ee.volumetric_end = 260.0
            ee.use_volumetric_shadows = True
            ee.bokeh_max_size = 60
            ee.motion_blur_steps = 1
        sc.render.use_motion_blur = True
        sc.render.motion_blur_shutter = 0.25
        sc.view_settings.view_transform = "AgX"
        try:
            sc.view_settings.look = "AgX - Medium High Contrast"
        except Exception:
            pass
        sc.view_settings.exposure = 0.0
        sc.render.film_transparent = False
        self.setup_compositor()

    def setup_compositor(self):
        sc = self.sc
        try:
            ng = bpy.data.node_groups.new("ClipComp", "CompositorNodeTree")
            ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
            rl = ng.nodes.new("CompositorNodeRLayers")
            gl = ng.nodes.new("CompositorNodeGlare")
            for key, val in (("Type", "Bloom"), ("Quality", "High"), ("Threshold", 1.2), ("Strength", 0.55),
                             ("Size", 0.75)):
                try:
                    gl.inputs[key].default_value = val
                except Exception:
                    pass
            out = ng.nodes.new("NodeGroupOutput")
            ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
            ng.links.new(gl.outputs[0], out.inputs[0])
            sc.compositing_node_group = ng
            sc.render.use_compositing = True
        except Exception as exc:
            print("[clip] compositor glare skipped:", exc)

    def sky_equirect(self):
        """the six branding/sky faces resampled into one equirect image (cached), then darkened in the shader"""
        path = os.path.join(CA.CACHE, "sky_equirect.png")
        if os.path.exists(path):
            return path
        from PIL import Image
        faces = {k: np.asarray(Image.open(os.path.join(SKY_DIR, "Skybox%s.png" % k)).convert("RGB"), np.float32)
                 for k in ("Bk", "Dn", "Ft", "Lf", "Rt", "Up")}
        W, H = 2048, 1024
        lon = (np.arange(W) + 0.5) / W * TAU - math.pi
        lat = math.pi / 2 - (np.arange(H) + 0.5) / H * math.pi
        lon, lat = np.meshgrid(lon, lat)
        # Blender world direction (x, y, z), z up; equirect u=0.5 looks along -Y in Blender's mapping (+X at u=0.5?)
        x = np.cos(lat) * np.cos(lon)
        y = np.cos(lat) * np.sin(lon)
        z = np.sin(lat)
        # Roblox sky directions: Ft = -Z_rbx, Bk = +Z_rbx, Rt = +X_rbx, Lf = -X_rbx, Up = +Y_rbx; blender = (-x, z, y)
        rx, ry, rz = -x, z, y
        out = np.zeros((H, W, 3), np.float32)
        ax, ay, az = np.abs(rx), np.abs(ry), np.abs(rz)
        size = faces["Ft"].shape[0]

        def sample(face, u, v, mask):
            img = faces[face]
            iu = np.clip(((u + 1) / 2 * (size - 1)).astype(int), 0, size - 1)
            iv = np.clip(((1 - (v + 1) / 2) * (size - 1)).astype(int), 0, size - 1)
            out[mask] = img[iv[mask], iu[mask]]

        m = (az >= ax) & (az >= ay) & (rz < 0)
        sample("Ft", rx / az, ry / az, m)
        m = (az >= ax) & (az >= ay) & (rz > 0)
        sample("Bk", -rx / az, ry / az, m)
        m = (ax > az) & (ax >= ay) & (rx > 0)
        sample("Rt", rz / ax, ry / ax, m)
        m = (ax > az) & (ax >= ay) & (rx < 0)
        sample("Lf", -rz / ax, ry / ax, m)
        m = (ay > ax) & (ay > az) & (ry > 0)
        sample("Up", rx / ay, rz / ay, m)
        m = (ay > ax) & (ay > az) & (ry < 0)
        sample("Dn", rx / ay, -rz / ay, m)
        Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(path)
        return path

    def setup_world(self):
        w = bpy.data.worlds.new("Twilight")
        self.sc.world = w
        try:
            w.use_nodes = True
        except Exception:
            pass
        nt = w.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out = nt.nodes.new("ShaderNodeOutputWorld")
        bg = nt.nodes.new("ShaderNodeBackground")
        env = nt.nodes.new("ShaderNodeTexEnvironment")
        env.image = bpy.data.images.load(self.sky_equirect())
        # twilight grade: multiply toward deep indigo, keep the pink band as a dusk glow
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = rgb(120, 92, 150)
        nt.links.new(env.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = 0.7
        nt.links.new(bg.outputs[0], out.inputs["Surface"])
        self.world_bg = bg
        # volumetric fog (rule 4): a fog box around each set keeps the sky visible behind it
        fogm = bpy.data.materials.new("Fog")
        fogm.use_nodes = True
        fnt = fogm.node_tree
        for n in list(fnt.nodes):
            fnt.nodes.remove(n)
        fo = fnt.nodes.new("ShaderNodeOutputMaterial")
        pv = fnt.nodes.new("ShaderNodeVolumePrincipled")
        pv.inputs["Density"].default_value = 0.012
        pv.inputs["Color"].default_value = rgb(196, 170, 214)
        pv.inputs["Anisotropy"].default_value = 0.35
        fnt.links.new(pv.outputs[0], fo.inputs["Volume"])
        self.fog_density = pv.inputs["Density"]
        for name, c, s in (("altar", ALTAR, (260, 260, 120)), ("home", HOME, (260, 260, 120)),
                           ("sky", SKY, (260, 260, 200)), ("arena", ARENA, (300, 300, 140))):
            fog = box("Fog_" + name, self.coll, s, (c.x, c.y, c.z + s[2] / 2 - 40), fogm, bevel=0)
            fog.visible_shadow = False

    # -------------------------------------------------------------------------------------- materials on game meshes
    def tune_asset(self, objs, floor=False, neon=4.0, floor_names=()):
        """game meshes: neon parts glow, stone floors become wet (roughness 0.15, rule 4)"""
        seen = set()
        for ob in objs:
            if ob.type != "MESH":
                continue
            for m in ob.data.materials:
                if m is None or m in seen:
                    continue
                seen.add(m)
                b = m.node_tree.nodes.get("Principled BSDF")
                if b is None:
                    continue
                if ob.get("clip_material") == "Neon":
                    b.inputs["Emission Strength"].default_value = neon
                if floor and (not floor_names or any(s in ob.name for s in floor_names)):
                    b.inputs["Roughness"].default_value = 0.15
                    b.inputs["Specular IOR Level"].default_value = 0.6

    def place(self, name, at, yaw=0.0, scale=1.0, prefix=None, set_name=None, floor=False, floor_names=()):
        root, groups, atts = CA.spawn(name, self.specs, self.coll, prefix=prefix)
        root.location = at
        root.rotation_euler = (0, 0, yaw)
        root.scale = (scale, scale, scale)
        objs = [o for k, g in groups.items() if not k.startswith("_") for o in g]
        self.tune_asset(objs, floor=floor, floor_names=floor_names)
        if set_name:
            self.set_meshes[set_name] += objs
        return root, groups, objs

    # -------------------------------------------------------------------------------------- ground ray casts
    def build_bvh(self):
        bpy.context.view_layer.update()
        self.bvh = {}
        for k, objs in self.set_meshes.items():
            verts, polys = [], []
            for ob in objs:
                mw = ob.matrix_world
                base = len(verts)
                verts += [mw @ v.co for v in ob.data.vertices]
                polys += [[base + i for i in p.vertices] for p in ob.data.polygons]
            if verts:
                self.bvh[k] = BVHTree.FromPolygons(verts, polys)

    def ground(self, set_name, x, y, top=200.0, default=0.0):
        t = self.bvh.get(set_name)
        if t is None:
            return default
        hit = t.ray_cast(V((x, y, top)), V((0, 0, -1)))
        return hit[0].z if hit[0] is not None else default


# ================================================================================================ the film
class Film(World):
    def build(self):
        t0 = time.time()
        self.setup_render()
        self.setup_world()
        self.build_altar()
        self.build_home()
        self.build_sky()
        self.build_arena()
        self.build_bvh()
        self.climber = Climber(self.coll)
        self.build_actors()
        self.build_fx()
        self.build_lights()
        print("[clip] scene built in %.1fs" % (time.time() - t0))

    # -------------------------------------------------------------------------------------- sets
    def build_altar(self):
        root, g, objs = self.place("altar", ALTAR, set_name="altar", floor=True,
                                   floor_names=("floor_altar_bridge", "floor_junction", "prop_altar_ring"))
        self.altar_objs = objs
        # the island top is the altar's stone: wet too (its cloud belly keeps its roughness via the Island group)
        for ob in objs:
            if "cloud_altar" in ob.name and ob.type == "MESH":
                for m in ob.data.materials:
                    b = m.node_tree.nodes.get("Principled BSDF")
                    if b:
                        b.inputs["Roughness"].default_value = 0.22
        self.portal_glow = [o for o in objs if "prop_altar_portal" in o.name]
        # practical lights: cyan crystals and the portal
        self.altar_lights = []
        for i in range(6):
            a = TAU * i / 6 + 0.3
            self.altar_lights.append(self.point("AltarCrystal%d" % i, ALTAR + V((math.cos(a) * 12, math.sin(a) * 12, 7)),
                                                rgb(80, 220, 255), 900, 40, radius=1.5))
        self.portal_light = self.point("AltarPortal", ALTAR + V((0, 0, 2.5)), rgb(90, 230, 255), 1500, 40, radius=3)

    def build_home(self):
        _, _, plot = self.place("plot", HOME, set_name="home")
        self.garden_c = HOME + V((0, 6, 0))
        _, _, gobjs = self.place("garden", self.garden_c, set_name="home")
        self.machine_c = HOME + V((20, -8, 0))
        self.machine_root, _, mobjs = self.place("foodmachine", self.machine_c, yaw=math.radians(-90), set_name="home")
        self.machine_objs = mobjs
        self.home_lights = [
            self.point("HomeLantern1", HOME + V((-14, -16, 6)), rgb(255, 170, 90), 1800, 60, radius=1.0),
            self.point("HomeLantern2", HOME + V((24, 8, 7)), rgb(255, 170, 90), 1500, 60, radius=1.0),
            self.point("HomeMachine", self.machine_c + V((0, -3, 5)), rgb(120, 230, 255), 600, 30, radius=1.0),
        ]

    def build_sky(self):
        """Act 4's Saint course: a spiral of the game's cloud steps, a summit pad and a pendulum blade"""
        self.steps = []
        R = 20.0
        step_mat = None
        n = 9
        for i in range(n):
            ang = math.radians(200 + i * 38 + (34 if i >= 6 else 0))
            z = i * 6.0 + (4.0 if i >= 6 else 0.0)
            c = SKY + V((math.cos(ang) * R, math.sin(ang) * R, z))
            sc = 0.55 if i == n - 1 else 0.28
            root, g, objs = self.place("cloud_step", c, yaw=ang, scale=sc, prefix="Step%d" % i, set_name="sky")
            self.steps.append(c)
            for ob in objs:  # storm-tinted cloud steps (the Saint level's dark storm palette)
                for m in ob.data.materials:
                    b = m.node_tree.nodes.get("Principled BSDF")
                    if b and step_mat is None:
                        pass
        # storm clouds around the course (the same cloud platform, big and dark)
        storm = principled("StormCloud", rgb(52, 50, 86), rough=0.9)
        for i in range(10):
            a = TAU * i / 10 + 0.2
            rr = RNG.uniform(70, 110)
            c = SKY + V((math.cos(a) * rr, math.sin(a) * rr, RNG.uniform(-20, 60)))
            root, g, objs = self.place("cloud_step", c, yaw=RNG.uniform(0, TAU), scale=RNG.uniform(1.6, 2.6),
                                       prefix="Storm%d" % i)
            for ob in objs:
                ob.data.materials.clear()
                ob.data.materials.append(storm)
        # summit ring of gold stars + a gold neon ring on the summit pad
        top = self.steps[-1]
        gold = emission("SummitGold", rgb(255, 200, 80), 6.0)
        self.summit_ring = ring_mesh("SummitRing", self.coll, 4.6, 5.2, 64, 0.0, gold)
        self.summit_ring.location = top + V((0, 0, 0.6))
        # the pendulum (hand-built: a chain arm and a crescent blade) over the dash gap between steps 5 and 6
        self.dash_a = self.steps[5]
        self.dash_b = self.steps[6]
        mid = (self.dash_a + self.dash_b) / 2
        self.pend_pivot_pos = mid + V((0, 0, 22))
        self.pend = empty("PendulumPivot", self.coll, None, tuple(self.pend_pivot_pos), 1.0)
        steel = principled("PendSteel", rgb(140, 146, 170), rough=0.2, metal=1.0)
        edge = emission("PendEdge", rgb(255, 60, 80), 6.0)
        box("PendArm", self.coll, (0.35, 0.35, 18.0), (0, 0, -9.0), steel, 0.05, self.pend)
        # crescent blade
        verts, faces = [], []
        nseg = 16
        for i in range(nseg + 1):
            a = math.radians(-70 + 140 * i / nseg)
            ro, ri = 5.0, 3.6
            for y in (-0.25, 0.25):
                verts.append((math.sin(a) * ro, y, -18 - math.cos(a) * ro + 5.0))
                verts.append((math.sin(a) * ri, y, -18 - math.cos(a) * ri + 5.0))
        for i in range(nseg):
            b0, b1 = 4 * i, 4 * (i + 1)
            faces += [(b0, b0 + 1, b1 + 1, b1), (b0 + 2, b1 + 2, b1 + 3, b0 + 3), (b0, b1, b1 + 2, b0 + 2),
                      (b0 + 1, b0 + 3, b1 + 3, b1 + 1)]
        blade = mesh_from("PendBlade", self.coll, verts, faces, steel, self.pend)
        verts2 = [(math.sin(math.radians(-70 + 140 * i / nseg)) * 5.08, 0, -18 - math.cos(math.radians(-70 + 140 * i / nseg)) * 5.08 + 5.0)
                  for i in range(nseg + 1)]
        ev, ef = [], []
        for i, p in enumerate(verts2):
            ev += [(p[0], -0.12, p[2]), (p[0], 0.12, p[2])]
        for i in range(nseg):
            ef.append((2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2))
        mesh_from("PendEdgeGlow", self.coll, ev, ef, edge, self.pend)
        self.pend_axis_yaw = yaw_to(self.dash_b - self.dash_a)
        self.sky_lights = [self.point("SkyStep%d" % i, s + V((0, 0, 5)), rgb(140, 120, 255), 700, 30, radius=1.0)
                           for i, s in enumerate(self.steps) if i % 2 == 0]
        self.sky_flash = self.sun("StormFlash", rgb(200, 210, 255), 0.0, (0.6, 0.3, 0.4))

    def build_arena(self):
        self.arena_objs = []
        _, _, objs = self.place("arena", ARENA, set_name="arena", floor=True, floor_names=("arena_floor",))
        # the colosseum ring: 16 segments (gates at 0 / 4 / 12, the boss gate at 8) and 16 pillars between them
        # (ArenaBuilder.buildColosseum): the cached spec of Segment_01 / _00 / _08 rotated by k * 22.5 deg
        hide = [o for o in objs if any(s in o.name for s in ("arena_seg_", "arena_pillar", "arena_torch"))]
        for o in hide:
            o.hide_render = True
            o.hide_viewport = True
        self.arena_objs = [o for o in objs if o not in hide]
        kinds = {0: "arena_seg_gate", 4: "arena_seg_gate", 12: "arena_seg_gate", 8: "arena_seg_bossgate"}
        src_root = bpy.data.objects.get("arena")
        from nvox import blend as B
        for k in range(16):
            key = kinds.get(k, "arena_seg_stand")
            spec = next(m for m, _ in self.specs["arena"] if m.name == key)
            self._ring_piece(spec, k * 22.5, "Seg%02d" % k)
            pil = next(m for m, _ in self.specs["arena"] if m.name == "arena_pillar")
            self._ring_piece(pil, (k + 0.5) * 22.5, "Pil%02d" % k, flame=(k % 2 == 0))

    def _ring_piece(self, spec, deg, name, flame=False):
        from nvox import blend as B
        made = B.make_objects(spec, CA.look_of(spec), collection=self.coll)
        piv = empty("Arena_" + name, self.coll, None, tuple(ARENA), 0.5)
        # Roblox CFrame.Angles(0, a, 0) about +Y_rbx  ==  about +Z in Blender with the angle negated (x -> -x)
        piv.rotation_euler = (0, 0, -math.radians(deg))
        for ob, g in zip(made, spec.objects.values()):
            ob.name = "Arena_%s_%s" % (name, g.name)
            ob["clip_material"] = g.material
            ob.parent = piv
        self.tune_asset(made)
        self.set_meshes["arena"] += made
        if flame:
            a = -math.radians(deg)
            # the pillar sits at radius ~94 (rbx -Z) -> blender +Y rotated
            p = ARENA + Matrix.Rotation(a, 3, "Z") @ V((0, 94, 24))
            self.point("ArenaTorch_" + name, p, rgb(255, 150, 70), 2600, 70, radius=1.2)

    # -------------------------------------------------------------------------------------- lights helpers
    def point(self, name, pos, color, watts, dist, radius=0.5):
        L = bpy.data.lights.new(name, "POINT")
        L.color = color[:3]
        L.energy = watts
        L.shadow_soft_size = radius
        L.use_shadow = False  # practicals glow only: the three-point rig casts the shadows (EEVEE shadow pool)
        try:
            L.use_custom_distance = True
            L.cutoff_distance = dist
        except Exception:
            pass
        ob = bpy.data.objects.new(name, L)
        ob.location = pos
        self.coll.objects.link(ob)
        return ob

    def area(self, name, color, watts, size, parent=None):
        L = bpy.data.lights.new(name, "AREA")
        L.color = color[:3]
        L.energy = watts
        L.shape = "DISK"
        L.size = size
        try:
            L.use_custom_distance = True
            L.cutoff_distance = 80
        except Exception:
            pass
        ob = bpy.data.objects.new(name, L)
        self.coll.objects.link(ob)
        if parent is not None:
            ob.parent = parent
        return ob

    def sun(self, name, color, strength, rot):
        L = bpy.data.lights.new(name, "SUN")
        L.color = color[:3]
        L.energy = strength
        L.angle = math.radians(3)
        ob = bpy.data.objects.new(name, L)
        ob.rotation_euler = rot
        self.coll.objects.link(ob)
        return ob

    def build_lights(self):
        """three-point rig that follows the hero and turns with the active camera: warm lantern key, cool purple
        fill, cyan / gold rim behind the subject"""
        self.rig = empty("LightRig", self.coll, None, (0, 0, 0), 1.0)
        self.key = self.area("Key", rgb(255, 204, 150), 1100, 4.0, self.rig)
        self.fill = self.area("Fill", rgb(170, 130, 255), 520, 6.0, self.rig)
        self.rim = self.area("Rim", rgb(90, 230, 255), 1400, 3.0, self.rig)
        self.moon = self.sun("Moon", rgb(150, 160, 255), 0.35, (math.radians(55), 0, math.radians(30)))

    # -------------------------------------------------------------------------------------- actors
    def build_actors(self):
        c = self.coll
        self.dragon0 = Pet("dragon0", self.specs, c, "Dragon0", scale=1.0)
        self.dragon2 = Pet("dragon2", self.specs, c, "Dragon2", scale=0.72)
        self.storm = Pet("stormfang", self.specs, c, "Stormfang", scale=1.0)  # x3 on the altar (st["scale"])
        self.hydra = Pet("hydra", self.specs, c, "Hydra", scale=1.45)
        for p in (self.dragon0, self.dragon2, self.storm, self.hydra):
            self.tune_asset(p.objects, neon=5.0)
        self.heads = [self.hydra.groups["_pivot_joint"][i] for i in range(3)] if "_pivot_joint" in self.hydra.groups else []
        self.heads_rest = [h.matrix_basis.copy() for h in self.heads]
        # the plain coin in the rookie's hand (Act 1)
        self.coin_root, _, _ = CA.spawn("cash", self.specs, c, prefix="HandCoin")
        self.coin = empty("HandCoinMover", c, None, (0, 0, 0), 0.5)
        self.coin_root.parent = self.coin
        self.coin_root.scale = (0.32, 0.32, 0.32)
        # Cloud Cash on the lawn (Act 3): linked copies of the game's coin meshes
        cash_src, _, _ = CA.spawn("cash", self.specs, c, prefix="CashSrc")
        lucky_src, _, _ = CA.spawn("lucky", self.specs, c, prefix="LuckySrc")
        for src in (cash_src, lucky_src):
            src.location = (0, 0, -500)
        self.coins = []
        for i in range(26):
            src = lucky_src if i % 8 == 3 else cash_src
            r = instance_copy(src, "Coin%02d" % i, c)
            ang = RNG.uniform(0, TAU)
            rad = RNG.uniform(4, 22)
            p = HOME + V((-22 + RNG.uniform(-10, 26), -14 + RNG.uniform(-10, 14), 0))
            p.z = self.ground("home", p.x, p.y) + 1.2
            self.coins.append(dict(root=r, home=p, spin=RNG.uniform(0, TAU), scale=RNG.uniform(0.42, 0.55),
                                   orbit=RNG.uniform(0, TAU), k=i))
        # Prestige Gems (Acts 5-6): a hand-cut gem mesh, linked copies
        self.gem_mat = principled("PrestigeGem", rgb(80, 235, 255), rough=0.05, metal=0.0, coat=1.0,
                                  emit=rgb(60, 220, 255), emit_strength=3.5)
        g0 = gem_mesh("GemSrc", c, self.gem_mat, size=0.9)
        g0.location = (0, 0, -600)
        self.gems = []
        for i in range(70):
            g = g0.copy()
            g.name = "Gem%02d" % i
            c.objects.link(g)
            self.gems.append(g)
        # prestige stars around the climber (Act 6): the game's star_gold
        self.stars = []
        for i in range(3):
            s, _, _ = CA.spawn("star", self.specs, c, prefix="PStar%d" % i)
            s.scale = (0.75, 0.75, 0.75)
            self.stars.append(s)

    # -------------------------------------------------------------------------------------- fx
    def build_fx(self):
        c = self.coll
        cyan = emission("BoltCyan", rgb(110, 240, 255), 6.0)
        self.bolt = bolt_mesh("StormBolt", c, V((0, 0, 0)), V((0, 1, 0)), cyan, 0.4, 9, 1.0, seed=3)
        self.bolt_mat = cyan
        self.bolt_light = self.point("BoltLight", V((0, 0, 0)), rgb(120, 230, 255), 0, 60, radius=0.5)
        # Act 1 + 2 rain: two stacked tiles of streaks that slide down and wrap
        rain_m = emission("Rain", rgb(170, 190, 255), 0.9, alpha=0.35)
        self.rain = []
        for k in range(2):
            verts, faces = [], []
            r = random.Random(11 + k)
            for i in range(1400):
                x, y, z = r.uniform(-28, 28), r.uniform(-28, 36), r.uniform(0, 40)
                ln = r.uniform(0.6, 1.2)
                b = len(verts)
                verts += [(x - 0.012, y, z), (x + 0.012, y, z), (x + 0.012 + 0.1, y, z + ln), (x - 0.012 + 0.1, y, z + ln)]
                faces.append((b, b + 1, b + 2, b + 3))
            self.rain.append(mesh_from("RainTile%d" % k, c, verts, faces, rain_m))
        # rain splash crowns near the hand (Act 2): small rings that pop and fade
        spl_m = emission("Splash", rgb(200, 215, 255), 2.5)
        self.splashes = [ring_mesh("Splash%d" % i, c, 0.05, 0.09, 16, 0.0, spl_m) for i in range(10)]
        # Act 3: evolution rune rings (two counter-rotating, 20 + 28 voxel runes), pillar, flash
        gold = emission("RuneGold", rgb(255, 205, 90), 8.0)
        self.rune_gold = gold
        self.runes = []
        for ring, (n, rad) in enumerate(((20, 5.2), (28, 7.4))):
            piv = empty("RuneRing%d" % ring, c, None, (0, 0, -300), 0.5)
            for i in range(n):
                a = TAU * i / n
                h = 0.5 + 0.4 * ((i * 7) % 3)
                box("Rune%d_%d" % (ring, i), c, (0.55, 0.32, 0.12), (math.cos(a) * rad, math.sin(a) * rad, 0.06), gold, 0.03,
                    piv).rotation_euler = (0, 0, a)
                if i % 2 == 0:
                    box("RuneTick%d_%d" % (ring, i), c, (0.18, 0.18, 0.18), (math.cos(a) * (rad + 0.6), math.sin(a) * (rad + 0.6), 0.09),
                        gold, 0.03, piv)
            ring_mesh("RuneBand%d" % ring, c, rad - 0.55, rad - 0.42, 96, 0.04, gold, piv)
            self.runes.append(piv)
        self.pillar_mat = emission("PillarGold", rgb(255, 214, 120), 3.0, alpha=0.28)
        self.pillar = tube_mesh("EvoPillar", c, 3.4, 2.4, 60, 32, self.pillar_mat)
        self.pillar_core = tube_mesh("EvoPillarCore", c, 1.2, 0.8, 60, 24, emission("PillarCore", rgb(255, 250, 230), 6.0, alpha=0.5))
        self.flash_mat = emission("EvoFlash", rgb(255, 255, 255), 30.0, alpha=0.9)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=24, ring_count=12)
        self.flash = bpy.context.active_object
        self.flash.name = "EvoFlashOrb"
        self.flash.data.materials.append(self.flash_mat)
        self.evo_light = self.point("EvoLight", V((0, 0, -300)), rgb(255, 214, 140), 0, 90, radius=2.0)
        self.shock_mat = emission("Shock", rgb(255, 230, 160), 8.0, alpha=0.8)
        self.shock = ring_mesh("ShockRing", c, 0.92, 1.0, 96, 0.0, self.shock_mat)
        self.sparks = []
        for i in range(34):
            s = box("Spark%d" % i, c, (0.22, 0.22, 0.22), (0, 0, 0), gold, 0.02)
            self.sparks.append(s)
        # Act 4: neon cyan dash trail (a ribbon rebuilt as a fixed path), storm bolts in the distance
        self.dash_mat = emission("DashCyan", rgb(80, 240, 255), 5.0, alpha=0.75)
        self.trail = None
        self.storm_bolts = []
        for i in range(4):
            a = TAU * i / 4 + 0.6
            p = SKY + V((math.cos(a) * 90, math.sin(a) * 90, 70))
            b = bolt_mesh("SkyBolt%d" % i, c, p, p + V((RNG.uniform(-10, 10), RNG.uniform(-10, 10), -80)),
                          emission("SkyBoltM%d" % i, rgb(190, 170, 255), 30.0), 0.5, 12, 4.0, seed=20 + i)
            self.storm_bolts.append(b)
        # Act 5: telegraph, beam, ghosts
        self.tele_mat = emission("Telegraph", rgb(255, 40, 60), 3.0, alpha=0.45)
        self.tele_edge = emission("TelegraphEdge", rgb(255, 60, 70), 9.0)
        self.tele_fill = disc_mesh("TeleFill", c, 1.0, 64, 0.0, self.tele_mat)
        self.tele_ring = ring_mesh("TeleRing", c, 0.94, 1.0, 96, 0.0, self.tele_edge)
        self.beam_mat = emission("BeamGold", rgb(255, 210, 90), 20.0, alpha=0.9)
        self.beam = tube_mesh("SpecialBeam", c, 0.7, 0.7, 1.0, 24, self.beam_mat)
        self.beam_core = tube_mesh("SpecialBeamCore", c, 0.28, 0.28, 1.0, 16, emission("BeamCore", rgb(255, 255, 235), 40.0))
        self.beam_light = self.point("BeamLight", V((0, 0, -300)), rgb(255, 200, 90), 0, 80, radius=1.0)
        self.hydra_light = self.point("HydraGlow", ARENA + V((0, -2, 16)), rgb(190, 110, 255), 9000, 70, radius=3.0)
        # ghost afterimages of the phase dodge: 3 static copies of the evolved dragon with a ghost material
        self.ghost_mats = [emission("Ghost%d" % i, rgb(120, 240, 255), 2.0, alpha=0.0) for i in range(3)]
        self.ghosts = []
        for i in range(3):
            g = instance_copy(self.dragon2.mover, "Ghost%d" % i, c)
            for ob in [g] + list(g.children_recursive):
                if ob.type == "MESH":
                    ob.material_slots[0].link = "OBJECT"
                    ob.material_slots[0].material = self.ghost_mats[i]
            self.ghosts.append(g)
        self.build_ufo()
        # Act 6 + finale: title
        self.title_mat = emission("TitleGold", rgb(255, 214, 110), 6.0, alpha=0.0)
        self.sub_mat = emission("TitleCyan", rgb(140, 240, 255), 4.0, alpha=0.0)
        font = bpy.data.fonts.load(FONT) if os.path.exists(FONT) else None
        self.title = self.text("Title", "NIMBUS CLIMB", self.title_mat, font, 1.0, 0.06)
        self.subtitle = self.text("Subtitle", "Climb the Storm. Together.", self.sub_mat, font, 0.36, 0.02)

    def build_ufo(self):
        """the avatar's UFO hat, hand-built: a grey saucer with a glass dome, a ring of blue lights, little fins,
        a blue tractor beam down to the head and glowing rings that travel down the body"""
        c = self.coll
        metal = principled("UFO_Metal", rgb(150, 156, 172), rough=0.22, metal=0.85)
        dark = principled("UFO_Dark", rgb(60, 64, 80), rough=0.3, metal=0.7)
        glass = principled("UFO_Dome", rgb(120, 220, 255), rough=0.05, emit=rgb(90, 200, 255), emit_strength=1.2,
                           alpha=0.6)
        blue = emission("UFO_Light", rgb(80, 170, 255), 8.0)
        self.ufo = empty("UFO", c, None, (0, 0, -400), 0.5)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=40, ring_count=16)
        hull = bpy.context.active_object
        hull.name = "UFO_Hull"
        hull.scale = (1.15, 1.15, 0.24)
        hull.data.materials.append(metal)
        hull.parent = self.ufo
        for p in hull.data.polygons:
            p.use_smooth = True
        ring_mesh("UFO_Band", c, 1.1, 1.24, 64, 0.0, dark, self.ufo)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.48, segments=24, ring_count=12, location=(0, 0, 0.12))
        dome = bpy.context.active_object
        dome.name = "UFO_Dome"
        dome.scale = (1, 1, 0.8)
        dome.data.materials.append(glass)
        dome.parent = self.ufo
        for i in range(10):
            a = TAU * i / 10
            box("UFO_Lamp", c, (0.12, 0.12, 0.08), (math.cos(a) * 1.02, math.sin(a) * 1.02, -0.1), blue, 0.03, self.ufo)
        for i in range(4):
            a = TAU * i / 4 + 0.4
            box("UFO_Fin", c, (0.1, 0.3, 0.22), (math.cos(a) * 0.7, math.sin(a) * 0.7, -0.26), dark, 0.03,
                self.ufo).rotation_euler = (0, 0, a)
        self.ufo_light = self.point("UFO_Glow", V((0, 0, -400)), rgb(90, 170, 255), 220, 12, radius=0.5)
        self.ufo_light.parent = self.ufo
        self.ufo_light.location = (0, 0, -0.6)
        self.beam_m = emission("UFO_Beam", rgb(110, 180, 255), 2.5, alpha=0.22)
        self.ufo_beam = tube_mesh("UFO_BeamCone", c, 0.62, 0.3, 0.95, 32, self.beam_m)
        self.ufo_rings = []
        for i in range(3):
            m = emission("UFO_RingM%d" % i, rgb(110, 170, 255), 7.0, alpha=0.0)
            ring = ring_mesh("UFO_Ring%d" % i, c, 0.93, 1.0, 72, 0.0, m)
            self.ufo_rings.append((ring, m))

    def head_world(self, st):
        """approximate world position of the top of the avatar's head from its baked state"""
        R = Matrix.Rotation(st["yaw"], 3, "Z") @ Matrix.Rotation(st.get("pitch", 0.0), 3, "X")
        lean = Matrix.Rotation(st.get("lean", 0.0), 3, "X")
        local = V((0, 0, 2.0 + st.get("hipz", 0.0))) + lean @ V((0, 0, 3.3))
        return st["pos"] + R @ local

    def direct_ufo(self, bk):
        cs = self.cs
        for f in range(1, N + 1):
            st = cs[f]
            t = f / FPS
            top = self.head_world(st)
            lying = 113 <= f <= 255
            ufo_p = top + V((0, 0, 1.45 + 0.12 * math.sin(TAU * t / 1.4)))
            bk.loc(self.ufo, f, ufo_p)
            bk.rot(self.ufo, f, (0.06 * math.sin(TAU * t / 2.1), 0.06 * math.cos(TAU * t / 1.7), t * 1.4))
            # the beam and the rings: only while standing (the UFO hovers on over a downed hero)
            bk.show(self.ufo_beam, f, not lying)
            bk.loc(self.ufo_beam, f, top + V((0, 0, 0.32)))
            body = st["pos"]
            for i, (ring, m) in enumerate(self.ufo_rings):
                u = ((f + i * 15) % 45) / 45.0
                z = top.z - 0.4 - u * (top.z - 0.4 - body.z)
                bk.show(ring, f, not lying)
                bk.loc(ring, f, V((body.x, body.y, z)))
                rad = 1.55 + 0.75 * u
                bk.scale(ring, f, (rad, rad, 1))
                bk.key(m.node_tree.nodes["Mix Shader"].inputs[0], "default_value", -1, f,
                       0.0 if lying else 0.85 * math.sin(math.pi * u))

    def text(self, name, body, mat, font, size, extrude):
        cu = bpy.data.curves.new(name, "FONT")
        cu.body = body
        if font:
            cu.font = font
        cu.size = size
        cu.extrude = extrude
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.materials.append(mat)
        ob = bpy.data.objects.new(name, cu)
        self.coll.objects.link(ob)
        return ob

    # ======================================================================================== the story (director)
    def climber_state(self, f):
        """the rookie's pose at frame f (all six acts)"""
        g = self.ground
        st = {}
        if f <= 150:  # ------------------------------------------------- Act 1: the bridge, the coin, the bolt
            y0, y1 = 52.0, 21.0
            u = seg(f, 1, 64)
            y = y0 - (y0 - y1) * (u * 0.82 + 0.18 * out_cubic(u)) if u < 1 else y1
            travelled = (y0 - y)
            # the tall crystal stands on the ring at (0, 12.4): the rookie drifts left of the bridge axis
            pos = V((lerp(-1.0, -3.0, (y0 - y) / (y0 - y1)), y, 0))
            st = dict(pos=pos, yaw=yaw_to(V((-2.0, -31.0, 0))) if f < 64 else yaw_to(ALTAR - V((-3.0, 21.0, 0))))
            stride = travelled / 2.5 * math.pi
            amt = 1.0 - smooth(seg(f, 58, 68))
            w = walk_pose(stride)
            for k in ("legL", "legR", "armL", "armR", "hipz", "twist"):
                st[k] = w[k] * amt
            st["lean"] = 0.08 * amt + settle(seg(f, 64, 80), 0.06)
            # the coin held out (overshoot, settle)
            r = out_back(seg(f, 62, 74), 2.2)
            st["armR"] = lerp(st["armR"], math.radians(78), r)
            st["armRs"] = math.radians(6) * r
            st["curlR"] = 0.55 * r
            st["head"] = math.radians(-4) * r
            # the bolt hits at 113: the rookie is thrown back and lands on the wet stone (back) at 138
            if f >= 106:
                flinch = smooth(seg(f, 106, 112))
                st["lean"] -= 0.12 * flinch
                st["armL"] = lerp(st.get("armL", 0), math.radians(25), flinch)
            if f >= 113:
                u = seg(f, 113, 138)
                land = V((-3.0, 28.0, 0))
                p = vlerp(V((-3.0, y1, 0)), land, out_cubic(u))
                p.z = 2.6 * math.sin(math.pi * min(u * 1.15, 1.0)) * (1 - u) + 0.0
                st["pos"] = p
                st["pitch"] = -math.radians(92) * smoother(u * 1.05) + math.radians(6) * settle(seg(f, 136, 150), 1.0)
                fl = math.sin(math.pi * clamp01(u * 1.2))
                st["armL"] = math.radians(150) * fl + math.radians(12) * (1 - fl)
                st["armR"] = math.radians(140) * fl
                st["armRs"] = math.radians(70) * smooth(seg(f, 126, 141))
                st["armLs"] = math.radians(35) * smooth(seg(f, 126, 141))
                st["legL"] = math.radians(35) * fl
                st["legR"] = math.radians(-20) * fl
                st["head"] = math.radians(25) * fl
                st["curlR"] = 0.55 * (1 - smooth(seg(f, 113, 120)))
                st["lean"] = -0.25 * fl
                # the hand slaps the stone at ~140 (the close-up): arm comes down with a small bounce
                st["armR"] += math.radians(14) * settle(seg(f, 139, 150), 1.0, 1.0)
            st["pos"].z += g("altar", st["pos"].x, st["pos"].y) + (0.5 if f >= 113 else 0) * smooth(seg(f, 128, 138))
            return st
        if f <= 270:  # ------------------------------------------------- Act 2: the clenched fist, standing up
            base = V((-3.0, 28.0, g("altar", -3.0, 28.0)))
            st = dict(pos=base + V((0, 0, 0.5)), yaw=yaw_to(ALTAR - V((-3.0, 21.0, 0))), pitch=-math.radians(92), armRs=math.radians(70),
                      armLs=math.radians(35), armR=math.radians(4), armL=math.radians(12))
            # breathing
            st["lean"] = 0.02 * math.sin(TAU * f / 70.0)
            # the fist: spread (anticipation) 168-174, curl with a squeeze overshoot 174-190
            spread = smooth(seg(f, 168, 174)) * (1 - smooth(seg(f, 174, 178)))
            curl = out_back(seg(f, 174, 190), 2.0)
            st["curlR"] = -0.15 * spread + 1.0 * curl
            st["armRs"] -= math.radians(8) * smooth(seg(f, 180, 205))  # drags in a little, knuckles pressed
            st["armR"] += math.radians(-6) * smooth(seg(f, 176, 186))
            # kip-up 233-256: anticipation (arms slam, pitch -96), then rise with a forward overshoot, settle
            if f >= 228:
                a = smooth(seg(f, 228, 236))
                rise = smoother(seg(f, 236, 250))
                st["pitch"] = lerp(-math.radians(92), -math.radians(97), a)
                st["pitch"] = lerp(st["pitch"], math.radians(7), rise) - math.radians(7) * smooth(seg(f, 250, 258))
                st["pos"] = base + V((0, -0.3 * rise, 0.5 * (1 - rise) + 1.4 * math.sin(math.pi * rise) * 0.5))
                st["armRs"] = lerp(st["armRs"], math.radians(8), rise)
                st["armLs"] = lerp(st["armLs"], math.radians(8), rise)
                st["armR"] = lerp(st["armR"], math.radians(-20), rise) + math.radians(20) * smooth(seg(f, 252, 262))
                st["armL"] = lerp(st["armL"], math.radians(-20), rise) + math.radians(20) * smooth(seg(f, 252, 262))
                st["legL"] = math.radians(40) * math.sin(math.pi * rise)
                st["legR"] = math.radians(-10) * math.sin(math.pi * rise)
                st["lean"] = 0.25 * math.sin(math.pi * rise) + settle(seg(f, 250, 268), 0.08)
                st["hipz"] = -0.25 * smooth(seg(f, 250, 255)) * (1 - smooth(seg(f, 255, 266)))
                st["curlR"] = 1.0
            return st
        if f <= 450:  # ------------------------------------------------- Act 3: sprint, coins, the evolution
            a, b = HOME + V((-36, -24, 0)), HOME + V((12, -10, 0))
            u = seg(f, 271, 326)
            d = (b - a)
            s = u * 0.9 + 0.1 * out_cubic(u)
            p = a + d * s
            st = dict(pos=p, yaw=yaw_to(d))
            stride = (d.length * s) / 3.6 * math.pi
            run = 1.0 - smooth(seg(f, 320, 330))
            w = walk_pose(stride, 1.0, 1.15, 0.25)
            for k in ("legL", "legR", "armL", "armR", "hipz", "twist"):
                st[k] = w[k] * run
            st["lean"] = 0.28 * run + settle(seg(f, 324, 344), 0.18)
            # throw the coin swirl into the machine: arm thrust 330-342
            look_m = yaw_to(self.machine_c - b)
            st["yaw"] = ang_lerp(st["yaw"], look_m, smooth(seg(f, 326, 334)))
            th = out_back(seg(f, 330, 340), 2.4) * (1 - smooth(seg(f, 350, 360)))
            st["armR"] = st.get("armR", 0) * (1 - th) + math.radians(85) * th
            st["lean"] += 0.12 * th
            # turn to the dragon for the evolution (it hovers at EVO)
            look_d = yaw_to(self.evo_c - b)
            st["yaw"] = ang_lerp(st["yaw"], look_d, smoother(seg(f, 352, 366)))
            # shield the eyes at the flash, then a fist pump at the reveal
            sh = smooth(seg(f, 372, 378)) * (1 - smooth(seg(f, 390, 398)))
            st["armL"] = st.get("armL", 0) + math.radians(150) * sh
            st["armLs"] = math.radians(-20) * sh
            st["lean"] -= 0.1 * sh
            pump = out_back(seg(f, 412, 424), 2.5) * (1 - smooth(seg(f, 440, 450)) * 0.0)
            st["armR"] = lerp(st["armR"], math.radians(170), pump)
            st["curlR"] = pump
            st["pos"] = V((p.x, p.y, g("home", p.x, p.y)))
            st["pos"].z += 0.18 * settle(seg(f, 412, 430), 1.0)
            return st
        if f <= 600:  # ------------------------------------------------- Act 4: the Saint spiral, the dash, the leap
            return self.sky_climber(f)
        if f <= 750:  # ------------------------------------------------- Act 5: the arena, the hydra, the gems
            land = ARENA + V((0, 34, 0))
            gz = g("arena", land.x, land.y)
            u = seg(f, 601, 611)
            p = land + V((0, 6 * (1 - u), gz + 26 * (1 - in_quad(u)) * (1 - u) + 0))
            p.z = gz + 26 * (1 - in_quad(u))
            st = dict(pos=V((land.x, land.y + 6 * (1 - u), p.z)), yaw=0.0)
            imp = seg(f, 611, 628)
            crouch = math.sin(math.pi * clamp01(imp * 1.6)) * (1 - imp)
            st["hipz"] = -0.7 * crouch
            st["lean"] = 0.45 * crouch + (0.25 if f < 611 else 0) + settle(imp, 0.08)
            st["legL"], st["legR"] = math.radians(28) * crouch, math.radians(-22) * crouch
            st["armL"], st["armR"] = math.radians(-35) * crouch + (math.radians(120) if f < 611 else 0), \
                math.radians(-35) * crouch + (math.radians(120) if f < 611 else 0)
            st["armLs"], st["armRs"] = math.radians(40) * crouch, math.radians(40) * crouch
            # brace against the slam shockwave
            br = smooth(seg(f, 618, 622)) * (1 - smooth(seg(f, 630, 640)))
            st["lean"] -= 0.15 * br
            st["armL"] += math.radians(60) * br
            # point the dragon at the boss for the special (668-674)
            pt = out_back(seg(f, 664, 674), 2.0) * (1 - smooth(seg(f, 700, 712)))
            st["armR"] += math.radians(90) * pt
            st["curlR"] = 0.4 * pt
            # catch the gems: palm up, the hand rises 716-730
            cg = out_back(seg(f, 714, 728), 1.6)
            st["armR"] = lerp(st["armR"], math.radians(62), cg)
            st["armRs"] = lerp(st.get("armRs", 0), math.radians(-12), cg)
            st["curlR"] = lerp(st.get("curlR", 0), 0.2, cg)
            st["head"] = math.radians(-14) * cg
            st["yaw"] = ang_lerp(0.0, math.radians(20), smooth(seg(f, 714, 730)))
            return st
        # ------------------------------------------------------------- Act 6: the oath
        a, b = V((-2.0, 32, 0)), V((-3.5, 18.5, 0))
        u = seg(f, 751, 786)
        s = u * 0.85 + 0.15 * out_cubic(u)
        p = vlerp(a, b, s)
        p.z = g("altar", p.x, p.y)
        st = dict(pos=p, yaw=yaw_to(ALTAR - b))
        walk = 1 - smooth(seg(f, 780, 790))
        w = walk_pose((a.y - p.y) / 2.6 * math.pi)
        for k in ("legL", "legR", "armL", "armR", "hipz", "twist"):
            st[k] = w[k] * walk
        st["lean"] = 0.05 * walk + settle(seg(f, 786, 800), 0.05)
        pour = out_back(seg(f, 788, 798), 2.0) * (1 - smooth(seg(f, 816, 826)))
        st["armR"] = st.get("armR", 0) + math.radians(70) * pour
        st["curlR"] = 0.25 * pour
        # the hero stance for the title: chest up, fist at the side, head up
        hero = smooth(seg(f, 852, 868))
        st["lean"] -= 0.08 * hero
        st["head"] = math.radians(-6) * hero
        st["armL"] = st.get("armL", 0) + math.radians(-8) * hero
        st["armLs"] = math.radians(10) * hero
        st["armRs"] = math.radians(14) * hero
        st["curlL"] = hero
        return st

    def sky_path(self):
        """Act 4 key poses: (frame, position) of every take-off / landing on the spiral"""
        top = lambda i: self.steps[i] + V((0, 0, 1.7 * (0.55 if i == len(self.steps) - 1 else 0.28) - 0.05))
        return top

    def sky_climber(self, f):
        top = self.sky_path()
        # hops: (from step, to step, takeoff frame, land frame)
        hops = [(1, 2, 444, 458), (2, 3, 462, 476), (3, 4, 480, 494), (4, 5, 498, 510), (5, 6, 514, 534),
                (6, 7, 540, 553), (7, 8, 557, 572)]
        pos, st = None, {}
        for i, (s0, s1, t0, t1) in enumerate(hops):
            nxt = hops[i + 1][2] if i + 1 < len(hops) else 999
            if f < t0 - 4 and i == 0:
                pos = top(s0)
                break
            if t0 - 4 <= f < t0:  # crouch before the leap (anticipation)
                pos = top(s0)
                c = smooth(seg(f, t0 - 4, t0))
                st.update(hipz=-0.55 * c, lean=0.35 * c, legL=math.radians(25) * c, legR=math.radians(-15) * c,
                          armL=math.radians(-40) * c, armR=math.radians(-40) * c)
                yaw = yaw_to(top(s1) - top(s0))
                break
            if t0 <= f < t1:
                u = seg(f, t0, t1)
                h = 3.5 if s0 != 5 else 6.0
                if s0 == 5:  # the dash: rise, then a straight neon burst past the blade, then the drop onto step 6
                    k = smoother(u)
                    pos = hop(top(s0), top(s1), k, h)
                else:
                    pos = hop(top(s0), top(s1), smooth(u * 0.6 + 0.4 * u * u), h)
                air = math.sin(math.pi * u)
                st.update(legL=math.radians(-30) * air, legR=math.radians(35) * air, armL=math.radians(140) * air,
                          armR=math.radians(-40) * air, lean=0.2 * air, hipz=0.0)
                if s0 == 5:
                    d = smooth(seg(f, 519, 523)) * (1 - smooth(seg(f, 530, 534)))
                    st.update(lean=0.2 * air + 0.75 * d, armL=lerp(st["armL"], math.radians(-70), d),
                              armR=lerp(st["armR"], math.radians(-70), d), legL=lerp(st["legL"], math.radians(-45), d),
                              legR=lerp(st["legR"], math.radians(-10), d))
                yaw = yaw_to(top(s1) - top(s0))
                break
            if t1 <= f < nxt - 4 or (i == len(hops) - 1 and f >= t1):
                pos = top(s1)
                l = seg(f, t1, t1 + 8)
                c = math.sin(math.pi * clamp01(l * 1.4)) * (1 - l)
                st.update(hipz=-0.5 * c + settle(l, 0.05), lean=0.3 * c, legL=math.radians(20) * c, legR=math.radians(-12) * c,
                          armL=math.radians(-30) * c, armR=math.radians(-30) * c)
                nyaw = yaw_to(top(hops[i + 1][1]) - top(hops[i + 1][0])) if i + 1 < len(hops) else yaw_to(top(s1) - top(s0))
                yaw = ang_lerp(yaw_to(top(s1) - top(s0)), nyaw, smooth(seg(f, t1, nxt - 4)))
                break
        if pos is None:
            pos, yaw = top(1), 0.0
        # summit: a fist pump 574-582, then the leap off toward the arena 584-600
        if f >= 572:
            out = (top(8) - SKY)
            out.z = 0
            out.normalize()
            yaw = yaw_to(out)
            pump = out_back(seg(f, 572, 580), 2.4) * (1 - smooth(seg(f, 582, 586)))
            st["armR"] = lerp(st.get("armR", 0), math.radians(170), pump)
            st["curlR"] = pump
            if f >= 584:
                c = smooth(seg(f, 584, 588))
                u = seg(f, 588, 600)
                pos = top(8) + out * (14 * out_cubic(u)) + V((0, 0, 4 * math.sin(math.pi * min(u * 1.6, 1)) - 26 * in_quad(u)))
                air = smooth(u)
                st.update(hipz=-0.5 * c * (1 - air), lean=0.35 * c * (1 - air) + 0.5 * air,
                          armL=math.radians(150) * air, armR=math.radians(150) * air, legL=math.radians(-25) * air,
                          legR=math.radians(30) * air)
        st["pos"] = pos.copy()
        st["yaw"] = yaw
        return st

    def dragon_state(self, f, cs_at):
        """the Cloudy Dragon: (stage, state). It follows the hero's left shoulder (the hero's position a few frames
        ago, so it trails like a pet), except in its scripted beats."""
        lag = 7
        c = cs_at(max(1, f - lag))
        stage = 0 if f < 381 else 2
        left = -right(c["yaw"])
        if stage == 0:
            off = left * 2.4 + fwd(c["yaw"]) * -1.2 + V((0, 0, 2.2))
        else:
            off = left * 5.4 + fwd(c["yaw"]) * 0.6 + V((0, 0, 3.4))
        st = dict(pos=c["pos"] + off, yaw=c["yaw"], scale=1.0)
        if 113 <= f <= 150:  # Act 1: tumbles back with the rookie and lands by the hand
            u = seg(f, 113, 140)
            p0 = V((-0.6, 22.0, 2.2))
            p1 = self.hand_rest + V((0.4, -2.3, 0.4))
            p = hop(p0, p1, out_cubic(u), 1.4)
            st = dict(pos=p, yaw=math.radians(-150) * smooth(u), roll=math.radians(85) * smooth(seg(f, 120, 136)),
                      scale=1.0)
        elif 150 < f <= 232:  # Act 2: lying on its side, then it gets back up (195-226) and narrows its gaze
            p = self.hand_rest + V((0.4, -2.3, 0.4))
            u = seg(f, 196, 220)
            up = out_back(u, 1.6)
            st = dict(pos=p + V((0.6 * up, -0.4 * up, 0.55 * up)), yaw=lerp(math.radians(-150), math.radians(-178), up),
                      roll=math.radians(85) * (1 - up), scale=1.0)
            # crouch: the windup pose (head low, wings folded tight)
            w = smooth(seg(f, 220, 228))
            st["pitch"] = math.radians(12) * w
            st["pos"] = st["pos"] + V((0, 0, -0.25 * w))
        elif 232 < f <= 270:
            pass
        elif 330 <= f < 450:  # Act 3: flies to the evolution spot, charges, transforms, hovers
            u = smooth(seg(f, 338, 352))
            st["pos"] = vlerp(st["pos"], self.evo_c + V((0, 0, 3.0)), u)
            st["yaw"] = ang_lerp(st["yaw"], yaw_to(self.climber_pos_at(f) - self.evo_c), u)
            ch = seg(f, 352, 379)
            st["pos"] = st["pos"] + V((0, 0, 4.0 * smoother(ch)))
            st["yaw"] += TAU * 3.5 * in_cubic(ch)  # spins faster and faster
            if stage == 0:
                st["scale"] = 1.0 - 0.96 * smooth(seg(f, 376, 381))
            else:
                r = seg(f, 381, 397)
                st["scale"] = max(0.04, out_back(r, 2.6))
                spin_down = 1 - out_cubic(seg(f, 381, 420))
                st["yaw"] = yaw_to(self.climber_pos_at(f) - self.evo_c) + TAU * 1 * spin_down
                st["pos"] = self.evo_c + V((0, 0, 3.0 + 4.0 * (1 - smooth(seg(f, 404, 430))) + 1.2))
        elif 451 <= f <= 600:  # Act 4: flies beside the hero, bigger offset outward from the spiral
            out = (c["pos"] - SKY)
            out.z = 0
            if out.length > 0:
                out.normalize()
            st["pos"] = c["pos"] + out * 4.5 + V((0, 0, 3.5)) + fwd(c["yaw"]) * -1.0
            if f >= 584:
                cam, _ = self.summit_cam(f)
                d = c["pos"] - cam
                d.z = 0
                d.normalize()
                side = V((d.y, -d.x, 0))  # camera right
                st["pos"] = c["pos"] + side * 6.5 + d * 2.0 + V((0, 0, 3.6))
        elif 601 <= f <= 750:  # Act 5
            cl = self.climber_pos_at(f)
            p = cl + V((4.5, -5.0, 3.2))
            st["yaw"] = 0.0
            if f < 614:
                p = cl + V((4.0, 2.0, 5.0 + 10 * (1 - seg(f, 601, 614))))
            # telegraph under the dragon 632-660; phase-dodge sideways 656-664
            dodge = smoother(seg(f, 656, 664))
            p = p + V((10.0 * dodge, 1.5 * dodge, 0))
            st["pos"] = p
            # face the boss for the special
            hb = ARENA + V((0, -12, 12))
            st["yaw"] = ang_lerp(0.0, yaw_to(hb - p), smooth(seg(f, 664, 672)))
            if f >= 712:  # back to the shoulder
                u = smooth(seg(f, 712, 730))
                st["pos"] = vlerp(p, cl + left * 5.4 + V((0, 0, 3.4)) + fwd(c["yaw"]) * 0.6, u)
                st["yaw"] = ang_lerp(st["yaw"], c["yaw"], u)
        elif f >= 751:  # Act 6: at the left shoulder
            pass
        return stage, st

    def climber_pos_at(self, f):
        return self.cs[max(1, min(N, int(f)))]["pos"]

    def storm_state(self, f):
        """Stormfang: prowls over the portal, roars the bolt (Act 1); bows, leaps to the right shoulder (Act 6)"""
        t = f / FPS
        base = ALTAR + V((0, 0, self.ground("altar", 0, 0) + 7.0))
        if f < 751:
            a = t * 0.45
            p = base + V((math.cos(a) * 3.2, math.sin(a) * 3.2, 0))
            yaw = a + math.pi  # walks tangentially
            yaw = yaw_to(V((-math.sin(a), math.cos(a), 0)))
            st = dict(pos=p, yaw=yaw, scale=3.0)
            if 84 <= f <= 150:  # stops and turns to the rookie, windup crouch, roar (strike), recoil
                u = smooth(seg(f, 84, 98))
                st["pos"] = vlerp(p, base + V((-0.4, 2.0, 0)), u)
                st["yaw"] = ang_lerp(yaw, yaw_to(V((-3.0, 21.0, 0)) - base), u)
                wind = smooth(seg(f, 100, 112)) * (1 - smooth(seg(f, 112, 114)))
                strike = out_back(seg(f, 112, 118), 2.0) * (1 - smooth(seg(f, 122, 136)))
                st["pos"] = st["pos"] + V((0, -1.0 * wind + 3.0 * strike, -0.9 * wind + 0.5 * strike))
                st["pitch"] = math.radians(10) * wind - math.radians(16) * strike
            return st
        # Act 6
        face = yaw_to(V((-3.5, 18.5, 0)) - base)
        st = dict(pos=base + V((0, 2.0, 0)), yaw=face, scale=3.0)
        bow = smooth(seg(f, 812, 822)) * (1 - smooth(seg(f, 826, 832)))
        st["pitch"] = math.radians(28) * bow
        st["pos"] = st["pos"] + V((0, 0, -1.6 * bow))
        crouch = smooth(seg(f, 828, 834)) * (1 - smooth(seg(f, 834, 836)))
        st["pos"] = st["pos"] + V((0, 0, -1.0 * crouch))
        st["pitch"] += math.radians(10) * crouch
        if f >= 834:
            cs = self.cs[min(f, N)]
            shoulder = cs["pos"] + right(cs["yaw"]) * 2.5 + V((0, 0, 4.6)) + fwd(cs["yaw"]) * 0.3
            u = seg(f, 834, 848)
            st["pos"] = hop(base + V((0, 2.0, 0)), shoulder, out_cubic(u), 4.0)
            st["pitch"] = math.radians(-20) * math.sin(math.pi * u)
            st["yaw"] = ang_lerp(face, cs["yaw"], smooth(u))
            st["scale"] = lerp(3.0, 1.0, out_cubic(seg(f, 836, 846)))  # the guardian becomes a companion
            # Storm Pounce pose on the shoulder: a lunge forward and back (out-back), settle
            if f >= 848:
                pz = out_back(seg(f, 848, 856), 2.0) * (1 - smooth(seg(f, 860, 872)))
                st["pos"] = shoulder + fwd(cs["yaw"]) * (0.9 * pz) + V((0, 0, settle(seg(f, 848, 870), 0.4)))
                st["pitch"] = math.radians(14) * pz
                st["flap_boost"] = pz
        return st

    def hydra_state(self, f):
        base = ARENA + V((0, -14, 0))
        gz = self.ground("arena", base.x, base.y)
        if f < 604 or f > 750:
            return dict(pos=V((0, 0, -400)), yaw=0, scale=1.0), False
        u = seg(f, 604, 617)
        z = gz + 70 * (1 - in_quad(u))
        imp = seg(f, 617, 630)
        sq = 1.0 - 0.12 * math.sin(math.pi * clamp01(imp * 2)) * (1 - imp)
        st = dict(pos=V((base.x, base.y, z)), yaw=math.pi, scale=sq)
        # shake while the beam burns
        if 690 <= f < 705:
            j = 0.25 * (f - 690) / 15
            st["pos"] = st["pos"] + V((RNG.uniform(-j, j), RNG.uniform(-j, j), 0))
        return st, f < 705

    # ---------------------------------------------------------------------------------------- shots
    def shots(self):
        """(start, end, lens, f-stop, handheld, fn(f) -> (camera pos, focus pos))"""
        cs = self.cs
        S = []
        g = self.ground

        def cl(f, dz=2.6):
            return cs[f]["pos"] + V((0, 0, dz))

        # Act 1
        S.append((1, 58, 35, 2.8, 0.06, lambda f: (V((cs[f]["pos"].x + 3.2, cs[f]["pos"].y + 12 - 4 * seg(f, 1, 58), 3.4)),
                                                   V((cs[f]["pos"].x - 0.6, cs[f]["pos"].y - 12, 4.6)),
                                                   cs[f]["pos"] + V((0, 0, 3.0)))))
        S.append((59, 108, 85, 2.0, 0.02, lambda f: (V((-27.0, 58.0 - 4.0 * smooth(seg(f, 59, 108)), 9.5)),
                                                     vlerp(self.hand_pos(f), self.storm.head_world(self.storm_state(f)), 0.5)
                                                     + V((0, 0, -0.6)),
                                                     vlerp(self.hand_pos(f), self.storm.head_world(self.storm_state(f)),
                                                           smooth(seg(f, 84, 100))))))
        S.append((109, 135, 35, 2.8, 0.18, lambda f: (V((-24, 26, 6.0)), V((-2, 15 + 8 * seg(f, 109, 135), 4.0)))))
        S.append((136, 150, 85, 2.0, 0.03, lambda f: (self.hand_cam(f, 0), self.hand_pos(f))))
        # Act 2
        S.append((151, 232, 85, 2.0, 0.01, lambda f: (self.hand_cam(f, 1), vlerp(self.hand_pos(f), self.hand_rest + V((0.9, -2.7, 1.0)),
                                                                             smooth(seg(f, 196, 210))))))
        S.append((233, 270, 35, 2.8, 0.08, lambda f: self.whip(f)))
        # Act 3
        S.append((271, 318, 35, 2.8, 0.14, lambda f: (cl(f) + right(cs[f]["yaw"]) * 11 + fwd(cs[f]["yaw"]) * 5 + V((0, 0, 0.8)),
                                                      cl(f, 2.4) + fwd(cs[f]["yaw"]) * 3)))
        S.append((319, 352, 35, 2.8, 0.05, lambda f: (cl(f) + right(cs[f]["yaw"]) * 12 + fwd(cs[f]["yaw"]) * -4 + V((0, 0, 2.6)),
                                                      vlerp(cl(f, 4.6), self.machine_c + V((0, 0, 4)), 0.35 * smooth(seg(f, 330, 348))),
                                                      cl(f, 4.0))))
        S.append((353, 450, 35, 2.5, 0.04, lambda f: (self.evo_cam(f), self.evo_c + V((0, 0, 5.5 + 1.5 * smooth(seg(f, 360, 384)))))))
        # Act 4
        S.append((451, 505, 35, 2.8, 0.12, lambda f: self.sky_follow(f, 14, 4.0)))
        S.append((506, 545, 35, 2.5, 0.10, lambda f: self.dash_cam(f)))
        S.append((546, 600, 35, 2.8, 0.12, lambda f: self.summit_cam(f)))
        # Act 5
        S.append((601, 628, 35, 2.8, 0.22, lambda f: (ARENA + V((-10, 49, 1.8)), vlerp(cl(f, 2.4), ARENA + V((0, 30, 4.5)), 0.25),
                                                      cl(f, 2.4))))
        S.append((629, 668, 35, 2.8, 0.10, lambda f: (cl(f) + V((-6, 11, 2.4)), vlerp(self.ds[f]["pos"], ARENA + V((0, -12, 9)), 0.3))))
        S.append((669, 712, 35, 2.5, 0.16, lambda f: (self.ds[f]["pos"] + V((9.0, 15.0, 2.0)), vlerp(self.ds[f]["pos"], ARENA + V((0, -14, 14)), 0.6))))
        S.append((713, 750, 85, 2.0, 0.02, lambda f: (self.gem_hand(f) + V((-8.0 + 1.5 * smooth(seg(f, 713, 750)), -1.2, 0.5)),
                                                      self.gem_hand(f))))
        # Act 6
        S.append((751, 812, 85, 2.0, 0.02, lambda f: (cl(f) + V((-8.0, 25.0, 3.2)), vlerp(cl(f, 3.4), ALTAR + V((0, 0, 4)), smooth(seg(f, 786, 806)) * 0.5))))
        S.append((813, 852, 35, 2.8, 0.05, lambda f: (V((-17, 27, 6.5)), vlerp(V((-1.0, 9.0, 7.0)), cl(f, 4.2), smooth(seg(f, 836, 848)) * 0.7),
                                                      self.storm_state(f)["pos"])))
        S.append((853, 900, 35, 2.8, 0.0, lambda f: (cl(853, 0) + V((-1.2, 15.5 + 2.0 * smooth(seg(f, 853, 900)), 1.4)),
                                                     cl(853, 4.4) + V((0.3, -4.0, 1.0)), cl(853, 3.6))))
        return S

    def hand_pos(self, f):
        if not hasattr(self, "_hand"):
            self._hand = {}
        if f not in self._hand:
            bpy.context.scene.frame_set(f)
            self._hand[f] = self.climber.hand_socket.matrix_world.translation.copy()
        return self._hand[f]

    def hand_cam(self, f, which):
        h = self.hand_rest
        if which == 0:
            return h + V((-3.8, 6.8, 1.0))
        u = smooth(seg(f, 151, 232))
        return h + V((-4.6 + 0.4 * u, 8.6 - 0.8 * u, 1.2))

    def whip(self, f):
        cs = self.cs
        p = cs[f]["pos"]
        u = smooth(seg(f, 256, 270))
        base = p + V((3.2, 9.5, 1.1))
        tgt = p + V((0, -2, 3.4)) + V((0, 0, -1.6 * (1 - smooth(seg(f, 233, 252)))))
        # whip-pan: the target swings 90 deg to the right in 10 frames (motion blur sells the cut to home)
        a = math.radians(95) * in_cubic(u)
        d = tgt - base
        d = Matrix.Rotation(-a, 3, "Z") @ d
        return base, base + d

    def evo_cam(self, f):
        c = self.evo_c
        u = smooth(seg(f, 353, 450))
        a = math.radians(-35 - 18 * u)
        return c + V((math.sin(a) * 21, -math.cos(a) * 21 - 0, 3.0 + 1.0 * u))

    def sky_follow(self, f, dist, h):
        cs = self.cs
        p = cs[f]["pos"]
        out = p - SKY
        out.z = 0
        out.normalize()
        tang = V((-out.y, out.x, 0))
        cam = p + out * dist + tang * -6 + V((0, 0, h - 2))
        return cam, p + V((0, 0, 2.6)) + tang * 2

    def dash_cam(self, f):
        a, b = self.steps[5], self.steps[6]
        mid = (a + b) / 2
        d = (b - a)
        d.z = 0
        d.normalize()
        side = V((-d.y, d.x, 0))
        out = (mid - SKY)
        out.z = 0
        out.normalize()
        if side.dot(out) < 0:
            side = -side
        cs = self.cs
        p = cs[f]["pos"]
        cam = p - d * 10.0 + side * 7.0 + V((0, 0, 3.5))
        return cam, p + V((0, 0, 2.4)) + d * 4.0

    def summit_cam(self, f):
        top = self.steps[-1]
        out = (top - SKY)
        out.z = 0
        out.normalize()
        tang = V((-out.y, out.x, 0))
        cs = self.cs
        p = cs[f]["pos"]
        cam = top + tang * 17 + out * -4 + V((0, 0, 6.5 - 12 * smooth(seg(f, 588, 600))))
        return cam, p + V((0, 0, 2.6))

    def gem_hand(self, f):
        return self.gem_anchor[f]

    # ---------------------------------------------------------------------------------------- bake everything
    def direct(self, frames_for_cams=None):
        bk = self.bk
        t0 = time.time()
        self.evo_c = HOME + V((-2, -18, 0))
        self.evo_c.z = self.ground("home", self.evo_c.x, self.evo_c.y)
        # 1. the hero, every frame (pure functions), and the pet trail from it
        self.cs = {f: self.climber_state(f) for f in range(1, N + 1)}
        self.cs[0] = self.cs[1]
        for f in range(1, N + 1):
            self.climber.pose(bk, f, self.cs[f])
        bk.write()
        bk.tracks.clear()
        # rest hand position for the close-ups (frame 150)
        bpy.context.scene.frame_set(150)
        self.hand_rest = self.climber.hand_socket.matrix_world.translation.copy()
        cs_at = lambda f: self.cs[max(1, min(N, f))]
        # 2. the dragon: two stages share one trail (stage 0 until 385, stage 2 from 386)
        raw = {}
        for f in range(1, N + 1):
            stage, st = self.dragon_state(f, cs_at)
            raw[f] = (stage, st)
        self.ds = {}
        lst = [raw[f][1] for f in range(1, N + 1)]
        for i, f in enumerate(range(1, N + 1)):
            stage, st = raw[f]
            p, r, speed = lean_into(lst, i)
            st = dict(st)
            st.setdefault("pitch", 0.0)
            st.setdefault("roll", 0.0)
            if not (113 <= f <= 232):
                st["pitch"] += p
                st["roll"] += r
            st = pet_life(f, st, speed, bob=0.0 if 113 <= f <= 232 else 0.22, stage=stage,
                          flap_amp=0.05 if 113 <= f <= 232 else 0.32)
            self.ds[f] = st
            for pet, on in ((self.dragon0, stage == 0), (self.dragon2, stage == 2)):
                bk.show(pet.mover, f, on)
                for ob in pet.objects:
                    bk.show(ob, f, on)
                if on:
                    pet.bake(bk, f, st)
                else:
                    bk.loc(pet.mover, f, st["pos"])
        # 3. Stormfang
        for f in range(1, N + 1):
            st = self.storm_state(f)
            st = pet_life(f, st, 0.0, bob=0.18, flap_amp=0.25 + 0.4 * st.get("flap_boost", 0.0))
            self.storm.bake(bk, f, st)
        # 4. the hydra (Act 5) + its heads swaying, the head-2 slam into the telegraph
        for f in range(1, N + 1):
            st, alive = self.hydra_state(f)
            bk.show(self.hydra.mover, f, alive)
            for ob in self.hydra.objects:
                bk.show(ob, f, alive)
            self.hydra.bake(bk, f, st)
            for i, h in enumerate(self.heads):
                e = self.heads_rest[i].to_euler("XYZ")
                t = f / FPS
                sway = 0.12 * math.sin(TAU * t * 0.6 + i * 2.1)
                pitch = 0.0
                if i == 1:
                    rear = smooth(seg(f, 640, 656)) * (1 - smooth(seg(f, 656, 660)))
                    slam = smooth(seg(f, 656, 661)) * (1 - smooth(seg(f, 668, 684)))
                    pitch = -0.5 * rear + 0.85 * slam
                if 670 <= f < 705:
                    pitch -= 0.25 * smooth(seg(f, 672, 680))
                bk.rot(h, f, (e.x + pitch, e.y, e.z + sway))
        # 5. props and fx
        self.direct_fx(bk)
        self.direct_ufo(bk)
        # 6. cameras + the light rig
        self.direct_cameras(bk)
        n = bk.write()
        print("[clip] directed %d keys in %.1fs" % (n, time.time() - t0))

    def direct_fx(self, bk):
        cs = self.cs
        # coin in hand (Act 1): in the right hand until the bolt, then it spins away and clatters on the stone
        for f in range(1, N + 1):
            on = f <= 150
            bk.show(self.coin, f, on)
            for ob in self.coin_root.children_recursive:
                bk.show(ob, f, on)
        coin_track = {}
        for f in range(1, 151):
            coin_track[f] = self.hand_pos(f)
        drop0 = coin_track[113]
        for f in range(1, 151):
            if f < 113:
                p = coin_track[f]
                rot = (0, 0, math.radians(90))
            else:
                u = seg(f, 113, 135)
                p = hop(drop0, V((1.8, 23.5, self.ground("altar", 1.8, 23.5) + 0.6)), out_cubic(u), 2.5)
                p.z += 0.4 * abs(settle(seg(f, 135, 150), 1.0))
                rot = (TAU * 3 * out_cubic(u), 0, math.radians(90))
            bk.loc(self.coin, f, p)
            bk.rot(self.coin, f, rot)
        # Stormfang's bolt (Act 1), on 113-121 with a flicker
        storm_mouth = self.storm.head_world(self.storm_state(113)) + V((0, 0.6, 0))
        feet = V((-2.7, 19.4, self.ground("altar", -2.7, 19.4) + 0.1))
        bolt_on = lambda f: 113 <= f <= 121 and f not in (116, 119)
        d = feet - storm_mouth
        for f in range(1, N + 1):
            on = bolt_on(f)
            bk.show(self.bolt, f, on)
        # the bolt mesh is built from (0,0,0)->(0,1,0): place + scale + aim it once (static during its 9 frames)
        self.bolt.location = storm_mouth
        self.bolt.rotation_euler = V((0, 1, 0)).rotation_difference(d.normalized()).to_euler()
        self.bolt.scale = (1.8, d.length, 1.8)
        for f in range(1, N + 1):
            on = 113 <= f <= 123
            k = (1.0 - seg(f, 113, 124)) * (0.4 if f in (116, 119) else 1.0) if on else 0.0
            bk.key(self.bolt_light.data, "energy", -1, f, 14000 * k)
            bk.loc(self.bolt_light, f, feet + V((0, 0, 2)))
        # rain (Acts 1-2 and 6, the altar): the two tiles slide down 34 studs/s and wrap
        for f in range(1, N + 1):
            on = f <= 270 or f >= 751
            for k, tile in enumerate(self.rain):
                z = (40.0 * k - (f * 34.0 / FPS)) % 80.0 - 40.0
                cs_f = cs[min(f, 270)] if f <= 270 else cs[f]
                bk.loc(tile, f, V((0, 18 if f <= 270 else 12, z + 3)))
                bk.show(tile, f, on)
        # splashes on the hand / stone (Act 2): each pops (scale up) and fades over 6 frames, staggered
        hand = self.hand_rest
        r = random.Random(5)
        for i, s in enumerate(self.splashes):
            off = V((r.uniform(-2.0, 2.0), r.uniform(-1.6, 1.6), 0))
            period = r.randint(9, 15)
            ph = r.randint(0, period)
            z = self.ground("altar", hand.x + off.x, hand.y + off.y) + 0.03
            on_hand = i < 3
            for f in range(1, N + 1):
                on = 136 <= f <= 232
                u = ((f + ph) % period) / 6.0
                vis = on and u <= 1.0
                bk.show(s, f, vis)
                pos = hand + V((r.uniform(-0.3, 0.3), 0, 0.05)) if on_hand else V((hand.x + off.x, hand.y + off.y, z))
                if vis:
                    bk.loc(s, f, pos if not on_hand else V((hand.x + off.x * 0.2, hand.y + off.y * 0.2, hand.z + 0.2)))
                    bk.scale(s, f, 0.3 + 3.2 * out_cubic(u))
        # Cloud Cash (Act 3): idle spin, magnet pull to the hero, a swirl that pours into the Food Machine
        hopper = self.machine_c + V((0, 0, 7.5))
        for c in self.coins:
            pick = None
            for f in range(271, 331):
                if (cs[f]["pos"] - c["home"]).length < 15:
                    pick = f
                    break
            if pick is None:
                pick = 300 + c["k"] % 20
            pour = 332 + (c["k"] % 13)
            for f in range(1, N + 1):
                on = 271 <= f <= pour + 12
                bk.show(c["root"], f, on)
                for ob in c["root"].children_recursive:
                    bk.show(ob, f, on)
                if not on:
                    continue
                t = f / FPS
                spin = c["spin"] + t * 2.4
                if f < pick:
                    p = c["home"] + V((0, 0, 0.25 * math.sin(TAU * t / 1.4 + c["spin"])))
                elif f < pour:
                    u = seg(f, pick, pick + 9)
                    orbit = c["orbit"] + t * 7.0
                    hero = cs[f]["pos"] + V((math.cos(orbit) * 2.0, math.sin(orbit) * 2.0, 7.4 + 0.4 * math.sin(orbit * 2)))
                    p = vlerp(c["home"], hero, in_quad(u) if u < 1 else 1.0)
                    if u < 1:
                        p.z += 2.0 * math.sin(math.pi * u)
                    spin += 8 * u
                else:
                    u = seg(f, pour, pour + 10)
                    orbit = c["orbit"] + t * 7.0
                    hero = cs[pour]["pos"] + V((math.cos(orbit) * 2.0, math.sin(orbit) * 2.0, 7.4))
                    p = hop(hero, hopper, in_quad(u), 3.0)
                bk.loc(c["root"], f, p)
                bk.rot(c["root"], f, (0, 0, spin))
                orb = smooth(seg(f, pick, pick + 9)) if f >= pick else 0.0
                bk.scale(c["root"], f, c["scale"] * (1 - 0.45 * orb) * (1 - 0.6 * smooth(seg(f, pour + 8, pour + 12))))
        # food machine glow while it eats
        for f in range(1, N + 1):
            k = smooth(seg(f, 332, 338)) * (1 - smooth(seg(f, 352, 366)))
            bk.key(self.home_lights[2].data, "energy", -1, f, 600 + 9000 * k)
        # evolution (Act 3): rune rings ignite, pillar erupts, flash, shock ring, sparks
        ec = self.evo_c
        for f in range(1, N + 1):
            ig = out_back(seg(f, 352, 366), 1.4)
            fade = 1 - smooth(seg(f, 432, 446))
            on = 352 <= f <= 450
            for i, piv in enumerate(self.runes):
                bk.show(piv, f, on)
                for ob in piv.children:
                    bk.show(ob, f, on)
                bk.loc(piv, f, ec + V((0, 0, 0.12 + 0.02 * i)))
                bk.rot(piv, f, (0, 0, (1 if i == 0 else -1) * (f / FPS) * (0.9 + 1.2 * smooth(seg(f, 360, 384)))))
                bk.scale(piv, f, max(0.01, ig) * (1 + 0.08 * smooth(seg(f, 386, 392))))
            pil = smoother(seg(f, 360, 374)) * fade
            for ob, core in ((self.pillar, False), (self.pillar_core, True)):
                k = pil * (1 - smooth(seg(f, 380, 386))) if core else pil * (1 - 0.8 * smooth(seg(f, 381, 389)))
                bk.show(ob, f, on and k > 0.01)
                bk.loc(ob, f, ec + V((0, 0, 0.1)))
                flare = 1 + 0.5 * smooth(seg(f, 375, 381)) * (1 - smooth(seg(f, 383, 395)))
                bk.scale(ob, f, (max(0.01, k) * flare, max(0.01, k) * flare, max(0.01, k)))
            bk.key(self.pillar_mat.node_tree.nodes["Emission"].inputs["Strength"], "default_value", -1, f,
                   3.0 + 9.0 * smooth(seg(f, 375, 381)) * (1 - smooth(seg(f, 383, 398))))
            # the flash: 376-388 (the burst), and the match-cut flash 438-450
            fl1 = smooth(seg(f, 376, 381)) * (1 - smooth(seg(f, 381, 388)))
            fl2 = in_cubic(seg(f, 438, 450)) if f <= 450 else 0.0
            fl = max(fl1, fl2)
            bk.show(self.flash, f, fl > 0.02)
            bk.loc(self.flash, f, ec + V((0, 0, 7.2)) if f < 430 else self.ds[f]["pos"] + V((0, 0, 1)))
            bk.scale(self.flash, f, 0.3 + 3.0 * fl if f < 430 else 0.3 + 9.0 * fl)
            bk.key(self.evo_light.data, "energy", -1, f, (0 if not on else 2500 * ig + 3500 * pil + 18000 * fl))
            bk.loc(self.evo_light, f, ec + V((0, 0, 7)))
            sh = seg(f, 381, 405)
            bk.show(self.shock, f, 381 <= f <= 405)
            bk.loc(self.shock, f, ec + V((0, 0, 0.2)))
            bk.scale(self.shock, f, (0.5 + 16 * out_cubic(sh), 0.5 + 16 * out_cubic(sh), 1))
        bk.key(self.shock_mat.node_tree.nodes["Mix Shader"].inputs[0], "default_value", -1, 381, 0.9)
        bk.key(self.shock_mat.node_tree.nodes["Mix Shader"].inputs[0], "default_value", -1, 405, 0.0)
        r = random.Random(9)
        for i, s in enumerate(self.sparks):
            d = V((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(0.3, 1.4))).normalized() * r.uniform(8, 16)
            spin = V((r.uniform(-9, 9), r.uniform(-9, 9), r.uniform(-9, 9)))
            for f in range(1, N + 1):
                on = 381 <= f <= 415
                bk.show(s, f, on)
                if on:
                    t = (f - 381) / FPS
                    p = ec + V((0, 0, 7)) + d * t + V((0, 0, -16 * t * t))
                    bk.loc(s, f, p)
                    bk.rot(s, f, spin * t)
                    bk.scale(s, f, max(0.05, 1 - seg(f, 400, 415)))
        # Act 4: pendulum swing (blade passes the dash line right after the hero, ~527), storm flashes, dash trail
        swing_axis = self.pend_axis_yaw
        for f in range(1, N + 1):
            t = (f - 527) / FPS
            ang = math.radians(62) * math.sin(TAU * t / 2.4)
            bk.rot(self.pend, f, (0, ang, swing_axis))
            fl = 0.0
            for c in (468, 471, 520, 562, 566):
                if c <= f <= c + 3:
                    fl = max(fl, 1 - (f - c) / 4)
            bk.key(self.sky_flash.data, "energy", -1, f, 7.0 * fl)
            for i, b in enumerate(self.storm_bolts):
                bk.show(b, f, 451 <= f <= 600 and fl > 0.5 and (f + i) % 2 == 0)
        self.build_trail()
        for f in range(1, N + 1):
            on = 518 <= f <= 548
            for born, ob in self.trail_segs:
                bk.show(ob, f, born <= f <= 548 and f >= 515)
            if on:
                bk.key(self.dash_mat.node_tree.nodes["Mix Shader"].inputs[0], "default_value", -1, f,
                       0.9 * (1 - smooth(seg(f, 532, 548))))
        # Act 5: telegraph under the dragon (fill 632-660, flash red), the beam, the shatter into gems
        tele_c = None
        for f in range(1, N + 1):
            on = 630 <= f <= 664
            p = self.ds[min(max(f, 630), 656)]["pos"].copy()
            p.z = self.ground("arena", p.x, p.y) + 0.12
            if f == 630:
                tele_c = p
            bk.show(self.tele_fill, f, on)
            bk.show(self.tele_ring, f, on)
            if on:
                R = 6.0
                fill = smooth(seg(f, 632, 660))
                bk.loc(self.tele_fill, f, p)
                bk.loc(self.tele_ring, f, p + V((0, 0, 0.02)))
                bk.scale(self.tele_fill, f, (max(0.01, R * fill), max(0.01, R * fill), 1))
                bk.scale(self.tele_ring, f, (R, R, 1))
                bk.key(self.tele_edge.node_tree.nodes["Emission"].inputs["Strength"], "default_value", -1, f,
                       9.0 + (30.0 if f >= 657 and f % 2 == 0 else 0.0))
        # ghosts trailing the dodge
        for i, gh in enumerate(self.ghosts):
            lagf = [658, 660, 662][i]
            for f in range(1, N + 1):
                on = 657 <= f <= 676
                bk.show(gh, f, on)
                for ob in gh.children_recursive:
                    bk.show(ob, f, on)
                if on:
                    st = self.ds[lagf]
                    bk.loc(gh, f, st["pos"])
                    bk.rot(gh, f, (st.get("pitch", 0), st.get("roll", 0), st["yaw"]))
                    bk.scale(gh, f, 1.0)
            m = self.ghost_mats[i].node_tree.nodes["Mix Shader"].inputs[0]
            bk.key(m, "default_value", -1, lagf - 1, 0.0)
            bk.key(m, "default_value", -1, lagf, 0.55 - 0.12 * i)
            bk.key(m, "default_value", -1, 676, 0.0)
        # the beam: from the dragon's mouth to the hydra's chest 670-704
        target = ARENA + V((0, -13, 11))
        for f in range(1, N + 1):
            on = 671 <= f <= 704
            bk.show(self.beam, f, on)
            bk.show(self.beam_core, f, on)
            mouth = self.dragon2.head_world(self.ds[f]) if on else V((0, 0, -300))
            d = target - mouth
            ext = out_cubic(seg(f, 671, 676))
            if on:
                rot = V((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
                w = (1 + 0.25 * math.sin(f * 1.7)) * (1 - smooth(seg(f, 698, 704)))
                for ob, k in ((self.beam, 1.0), (self.beam_core, 1.0)):
                    bk.loc(ob, f, mouth)
                    bk.rot(ob, f, rot)
                    bk.scale(ob, f, (max(0.05, w), max(0.05, w), max(0.05, d.length * ext)))
            bk.loc(self.beam_light, f, target if on else V((0, 0, -300)))
            bk.key(self.beam_light.data, "energy", -1, f, 25000 * ext if on else 0)
            bk.key(self.hydra_light.data, "energy", -1, f, 9000 if f < 704 else 0)
        # gems: burst from the hydra 704, fall and bounce; 5 of them rise into the hero's palm 716-740
        self.gem_anchor = {}
        r = random.Random(4)
        center = ARENA + V((0, -14, 9))
        for f in range(713, 751):
            self.gem_anchor[f] = self.hand_pos(f) + V((0, 0, 0.6))
        for i, g in enumerate(self.gems):
            vel = V((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(0.6, 1.6))).normalized() * r.uniform(10, 22)
            spinv = V((r.uniform(-6, 6), r.uniform(-6, 6), r.uniform(-6, 6)))
            palm = i < 5
            for f in range(1, N + 1):
                act5 = 704 <= f <= 750
                act6 = 790 <= f <= 812 and i < 40
                on = act5 or act6
                bk.show(g, f, on)
                if not on:
                    continue
                if act5:
                    t = (f - 704) / FPS
                    p = center + vel * t + V((0, 0, -22 * t * t))
                    floor = self.ground("arena", p.x, p.y) + 0.45
                    if p.z < floor:
                        p.z = floor + abs(math.sin(t * 9)) * 0.6 * max(0, 1 - t)
                    if palm and f >= 714:
                        u = smoother(seg(f, 714 + i, 730 + i))
                        k = self.gem_anchor[f] + V((math.cos(i * 1.26 + f * 0.08) * 0.5, math.sin(i * 1.26 + f * 0.08) * 0.5, 0.3 * i % 0.6))
                        p = vlerp(p, k, u)
                    bk.loc(g, f, p)
                    bk.rot(g, f, spinv * t)
                    bk.scale(g, f, 0.8 if not palm else 0.55)
                else:  # Act 6: the stream of gems from the hand into the altar vortex (arcs, one after another)
                    start = 790 + (i % 20)
                    u = seg(f, start, start + 12)
                    hand = self.hand_pos(f)
                    p = hop(hand, ALTAR + V((r.uniform(-1, 1), r.uniform(-1, 1), self.ground("altar", 0, 0) + 0.6)), smooth(u), 5.0)
                    bk.show(g, f, 0.0 < u < 1.0)
                    bk.loc(g, f, p)
                    bk.rot(g, f, spinv * (f / FPS))
                    bk.scale(g, f, 0.45 * (1 - 0.7 * smooth(seg(u, 0.8, 1.0))))
        # the altar vortex flares as the gems pour in, and again when Stormfang lands
        for f in range(1, N + 1):
            k = smooth(seg(f, 792, 806)) * (1 - smooth(seg(f, 830, 860))) + 0.5 * smooth(seg(f, 846, 852)) * (1 - smooth(seg(f, 852, 880)))
            bk.key(self.portal_light.data, "energy", -1, f, 1500 + 40000 * k)
        # prestige stars orbit the hero's head (Act 6)
        for i, s in enumerate(self.stars):
            for f in range(1, N + 1):
                on = f >= 751
                bk.show(s, f, on)
                for ob in s.children_recursive:
                    bk.show(ob, f, on)
                if on:
                    a = f / FPS * 1.6 + TAU * i / 3
                    c = cs[f]["pos"] + V((math.cos(a) * 1.5, math.sin(a) * 1.5, 5.9 + 0.2 * math.sin(a * 2)))
                    bk.loc(s, f, c)
                    bk.rot(s, f, (math.radians(90), 0, a + math.pi / 2))
        # title (853-900): rises and fades in
        for f in range(1, N + 1):
            u = smooth(seg(f, 858, 876))
            v = smooth(seg(f, 870, 888))
            bk.key(self.title_mat.node_tree.nodes["Mix Shader"].inputs[0], "default_value", -1, f, u)
            bk.key(self.sub_mat.node_tree.nodes["Mix Shader"].inputs[0], "default_value", -1, f, v)
            bk.show(self.title, f, f >= 856)
            bk.show(self.subtitle, f, f >= 868)

    def build_trail(self):
        """the neon cyan dash ribbon: one short segment per frame of the dash (514-533), each appearing when the
        hero has passed it, so the trail only ever lies BEHIND the hero"""
        self.trail_segs = []
        for f in range(514, 534):
            a = self.cs[f]["pos"] + V((0, 0, 2.6))
            b = self.cs[f + 1]["pos"] + V((0, 0, 2.6))
            t0, t1 = (f - 514) / 20.0, (f - 513) / 20.0
            w0 = 0.3 * math.sin(math.pi * t0) + 0.04
            w1 = 0.3 * math.sin(math.pi * t1) + 0.04
            verts = [a + V((0, 0, -w0)), a + V((0, 0, w0)), b + V((0, 0, w1)), b + V((0, 0, -w1))]
            ob = mesh_from("DashTrail%02d" % (f - 514), self.coll, verts, [(0, 1, 2, 3)], self.dash_mat)
            self.trail_segs.append((f + 1, ob))
        self.trail = self.trail_segs[0][1]

    def direct_cameras(self, bk):
        self.cams = []
        shots = self.shots()
        sc = self.sc
        sc.timeline_markers.clear()
        for k, (a, b, lens, fstop, shake, fn) in enumerate(shots):
            cd = bpy.data.cameras.new("Cam%02d" % k)
            cd.lens = lens
            cd.sensor_width = 36
            cd.clip_start = 0.1
            cd.clip_end = 1500
            cd.dof.use_dof = True
            cd.dof.aperture_fstop = fstop
            cam = bpy.data.objects.new("Cam%02d" % k, cd)
            self.coll.objects.link(cam)
            aim = empty("CameraTarget%02d" % k, self.coll, None, (0, 0, 0), 0.3)
            focus = empty("CameraFocus%02d" % k, self.coll, None, (0, 0, 0), 0.3)
            con = cam.constraints.new("TRACK_TO")
            con.target = aim
            con.track_axis = "TRACK_NEGATIVE_Z"
            con.up_axis = "UP_Y"
            cd.dof.focus_object = focus
            for f in range(a, b + 1):
                r = fn(f)
                cp, tp = r[0], r[1]
                fp = r[2] if len(r) > 2 else tp
                bk.loc(cam, f, cp)
                bk.loc(aim, f, tp)
                bk.loc(focus, f, fp)
                # the light rig: on the hero, turned so the rim sits behind the subject (away from the camera)
                d = (tp - cp)
                d.z = 0
                yaw = math.atan2(d.y, d.x)
                bk.loc(self.rig, f, tp)
                bk.rot(self.rig, f, (0, 0, yaw))
            m = sc.timeline_markers.new("S%02d" % k, frame=a)
            m.camera = cam
            self.cams.append((cam, focus, shake, a, b))
        # rig layout (local: +X = from the camera toward the subject)
        self.key.location = (-7, 5, 6)
        self.key.rotation_euler = V((7, -5, -6)).to_track_quat("-Z", "Y").to_euler()
        self.fill.location = (-6, -7, 2)
        self.fill.rotation_euler = V((6, 7, -2)).to_track_quat("-Z", "Y").to_euler()
        self.rim.location = (7, -2.5, 5.5)
        self.rim.rotation_euler = V((-7, 2.5, -5.5)).to_track_quat("-Z", "Y").to_euler()
        # gold rim in the warm acts (3, 6 finale), cyan elsewhere
        for f in range(1, N + 1):
            gold = (271 <= f <= 450) or f >= 751 or (669 <= f <= 712)
            col = rgb(255, 200, 90) if gold else rgb(90, 230, 255)
            for i in range(3):
                bk.key(self.rim.data, "color", i, f, col[i])

    def add_handheld(self):
        """procedural handheld noise on action cameras (rule 4): Noise F-modifiers on the location curves"""
        for cam, focus, shake, a, b in self.cams:
            if shake <= 0 or cam.animation_data is None:
                continue
            for fc in cam.animation_data.action.fcurves if hasattr(cam.animation_data.action, "fcurves") else []:
                pass
            act = cam.animation_data.action
            for i in range(3):
                fc = act.fcurve_ensure_for_datablock(cam, "location", index=i)
                m = fc.modifiers.new("NOISE")
                m.scale = 9.0
                m.strength = shake * (0.6 if i == 2 else 1.0)
                m.phase = 10 * i + a
                m.blend_type = "ADD" if hasattr(m, "blend_type") else m.blend_type

    def place_title(self):
        """the title floats in front of the last shot's camera at its focus distance (sharp under DOF)"""
        cam, focus, *_ = self.cams[-1]
        self.sc.frame_set(880)
        cm = cam.matrix_world
        fwdv = (focus.matrix_world.translation - cm.translation).normalized()
        dist = (focus.matrix_world.translation - cm.translation).length
        upv = (cm.to_3x3() @ V((0, 1, 0))).normalized()
        rightv = (cm.to_3x3() @ V((1, 0, 0))).normalized()
        base = cm.translation + fwdv * (dist * 0.7)
        rot = cm.to_euler()
        h = 2 * dist * 0.7 * math.tan(math.atan(12 / 35.0))  # visible height at that depth (24 mm tall frame, 35 mm)
        self.title.location = base + upv * (h * 0.33)
        self.title.rotation_euler = rot
        self.title.data.size = h * 0.12
        self.subtitle.location = base + upv * (h * 0.22)
        self.subtitle.rotation_euler = rot
        self.subtitle.data.size = h * 0.045
        self.title_dist = dist * 0.7

    def avatar_sheet(self):
        """the player's avatar alone on a dark stage, to compare with their Roblox picture"""
        self.setup_render()
        self.sc.render.resolution_percentage = 50
        w = bpy.data.worlds.new("Stage")
        self.sc.world = w
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Color"].default_value = rgb(34, 30, 52)
        self.climber = Climber(self.coll)
        self.build_ufo()
        self.cs = {f: dict(pos=V((0, 0, 0)), yaw=0.0, armR=0.12, armL=-0.1, armRs=0.08, armLs=0.08) for f in range(0, N + 1)}
        bk = self.bk
        for f in (1, 2):
            self.climber.pose(bk, f, self.cs[f])
        self.direct_ufo(bk)
        bk.write()
        for name, pos, col, wt in (("K", (-6, -8, 9), rgb(255, 236, 214), 2600), ("F", (8, -6, 4), rgb(200, 190, 255), 900),
                                   ("R", (0, 9, 8), rgb(140, 220, 255), 2200)):
            L = bpy.data.lights.new(name, "AREA")
            L.energy, L.size, L.color = wt, 5, col[:3]
            ob = bpy.data.objects.new(name, L)
            ob.location = pos
            ob.rotation_euler = (V((0, 0, 3)) - V(pos)).to_track_quat("-Z", "Y").to_euler()
            self.coll.objects.link(ob)
        cd = bpy.data.cameras.new("AvCam")
        cd.lens = 50
        cam = bpy.data.objects.new("AvCam", cd)
        self.coll.objects.link(cam)
        self.sc.camera = cam
        self.sc.frame_set(12)
        for name, ang in (("front", 0), ("threequarter", 40), ("back", 180)):
            a = math.radians(ang)
            cam.location = V((math.sin(a) * -17, -math.cos(a) * 17, 4.8))
            cam.rotation_euler = (V((0, 0, 3.9)) - cam.location).to_track_quat("-Z", "Y").to_euler()
            self.sc.render.filepath = os.path.join(PREVIEW_DIR, "avatar_%s.png" % name)
            bpy.ops.render.render(write_still=True)
            print("[clip] avatar", name)

    # ---------------------------------------------------------------------------------------- render
    def render_frames(self, frames, out_dir, name="frame_%04d.png"):
        os.makedirs(out_dir, exist_ok=True)
        sc = self.sc
        sc.render.image_settings.file_format = "PNG"
        times = []
        for f in frames:
            t0 = time.time()
            sc.frame_set(f)
            sc.render.filepath = os.path.join(out_dir, name % f)
            bpy.ops.render.render(write_still=True)
            times.append(time.time() - t0)
            print("[clip] frame %d  %.1fs  -> %s" % (f, times[-1], sc.render.filepath))
        return times

    def encode(self):
        """the PNG frames -> one H.264 MP4 through Blender's own FFmpeg (a VSE image strip; no external ffmpeg)"""
        files = sorted(f for f in os.listdir(FRAMES_DIR) if f.endswith(".png"))
        sc = bpy.data.scenes.new("Encode")
        sc.render.fps = FPS
        sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
        sc.render.resolution_percentage = 100
        sc.frame_start, sc.frame_end = 1, len(files)
        se = sc.sequence_editor_create()
        strips = getattr(se, "strips", None) or se.sequences
        st = strips.new_image("frames", os.path.join(FRAMES_DIR, files[0]), 1, 1)
        for fn in files[1:]:
            st.elements.append(fn)
        st.frame_final_duration = len(files)
        sc.render.image_settings.file_format = "FFMPEG"
        sc.render.ffmpeg.format = "MPEG4"
        sc.render.ffmpeg.codec = "H264"
        sc.render.ffmpeg.constant_rate_factor = "HIGH"
        sc.render.ffmpeg.ffmpeg_preset = "GOOD"
        sc.render.use_sequencer = True
        sc.render.use_compositing = False
        tmp = os.path.join(OUT_DIR, "encode_")
        sc.render.filepath = tmp
        bpy.context.window_manager  # noqa
        with bpy.context.temp_override(scene=sc):
            bpy.ops.render.render(animation=True, scene=sc.name)
        made = [f for f in os.listdir(OUT_DIR) if f.startswith("encode_") and f.endswith(".mp4")]
        if not made:
            raise RuntimeError("encode: no MP4 written")
        if os.path.exists(MP4):
            os.remove(MP4)
        shutil.move(os.path.join(OUT_DIR, made[0]), MP4)
        print("[clip] MP4 ->", MP4)


def main():
    argv = sys.argv[1:]
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    ap = argparse.ArgumentParser(description="Render the Nimbus Climb story clip")
    ap.add_argument("--preview", action="store_true", help="render the 6 check frames to play/clips/preview/")
    ap.add_argument("--full", action="store_true", help="render all 900 frames and encode play/clips/nimbus_story_clip.mp4")
    ap.add_argument("--frames", help="comma list of frames to render (preview folder)")
    ap.add_argument("--res", type=int, default=100, help="resolution percentage (default 100)")
    ap.add_argument("--samples", type=int, default=0, help="render samples (EEVEE default 32, preview 16)")
    ap.add_argument("--cycles", action="store_true", help="Cycles (64 samples + denoiser) instead of EEVEE")
    ap.add_argument("--rebuild-assets", action="store_true", help="rebuild the cached game meshes")
    ap.add_argument("--save-blend", action="store_true", help="also save play/clips/nimbus_story_clip.blend")
    ap.add_argument("--look", help="debug camera: x,y,z,tx,ty,tz[,lens[,frame]] -> play/clips/preview/look.png")
    ap.add_argument("--probe", help="print the hero / dragon / camera state at these frames (comma list)")
    ap.add_argument("--sheet", action="store_true", help="low-res contact sheet: 2 frames per shot -> play/clips/preview/sheet_*.png")
    ap.add_argument("--avatar", action="store_true", help="render the avatar alone (front, 3/4, back) to play/clips/preview/")
    ap.add_argument("--encode-only", action="store_true", help="only encode the frames already in play/clips/frames/")
    a = ap.parse_args(argv)
    if not (a.preview or a.full or a.frames or a.encode_only):
        a.preview = True
    if a.preview and not a.samples:
        a.samples = 16
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    film = Film(a)
    if a.avatar:
        film.avatar_sheet()
        return
    if a.encode_only:
        film.encode()
        return
    film.build()
    film.direct()
    film.add_handheld()
    film.place_title()
    if a.probe:
        for f in [int(x) for x in a.probe.split(",")]:
            film.sc.frame_set(f)
            cam = film.sc.camera
            foc = cam.constraints[0].target if cam and cam.constraints else None
            print("[probe] f%d hero %s yaw %.0f | dragon %s | cam %s %s -> %s | hand %s" % (
                f, tuple(round(v, 1) for v in film.cs[f]["pos"]), math.degrees(film.cs[f]["yaw"]),
                tuple(round(v, 1) for v in film.ds[f]["pos"]), cam.name if cam else None,
                tuple(round(v, 1) for v in cam.matrix_world.translation) if cam else None,
                tuple(round(v, 1) for v in foc.matrix_world.translation) if foc else None,
                tuple(round(v, 1) for v in film.climber.hand_socket.matrix_world.translation)))
    if a.look:
        film.sc.timeline_markers.clear()
        for i, spec in enumerate(a.look.split(";")):
            v = [float(x) for x in spec.split(",")]
            cd = bpy.data.cameras.new("Look%d" % i)
            cd.lens = v[6] if len(v) > 6 else 24
            cd.clip_end = 3000
            cam = bpy.data.objects.new("Look%d" % i, cd)
            film.coll.objects.link(cam)
            cam.location = v[:3]
            cam.rotation_euler = (V(v[3:6]) - V(v[:3])).to_track_quat("-Z", "Y").to_euler()
            film.sc.camera = cam
            film.sc.frame_set(int(v[7]) if len(v) > 7 else 1)
            film.sc.render.filepath = os.path.join(PREVIEW_DIR, "look%d.png" % i)
            bpy.ops.render.render(write_still=True)
        return
    if a.save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "nimbus_story_clip.blend"))
    if a.sheet:
        from PIL import Image, ImageDraw
        frames = []
        for cam, focus, shake, s0, s1 in film.cams:
            frames += [s0 + (s1 - s0) // 4, s0 + 3 * (s1 - s0) // 4]
        tmp = os.path.join(PREVIEW_DIR, "sheet_tmp")
        film.render_frames(frames, tmp)
        cols, w, h = 4, 480, 270
        for page in range(0, len(frames), 20):
            chunk = frames[page:page + 20]
            rows = (len(chunk) + cols - 1) // cols
            sheet = Image.new("RGB", (cols * w, rows * h), (0, 0, 0))
            dr = ImageDraw.Draw(sheet)
            for i, f in enumerate(chunk):
                im = Image.open(os.path.join(tmp, "frame_%04d.png" % f)).convert("RGB").resize((w, h))
                sheet.paste(im, ((i % cols) * w, (i // cols) * h))
                dr.text(((i % cols) * w + 6, (i // cols) * h + 4), "f%d" % f, fill=(255, 255, 0))
            sheet.save(os.path.join(PREVIEW_DIR, "sheet_%d.png" % (page // 20)))
        print("[clip] sheet frames", frames)
        return
    if a.preview or a.frames:
        frames = [int(x) for x in a.frames.split(",")] if a.frames else PREVIEW_FRAMES
        film.render_frames(frames, PREVIEW_DIR)
    if a.full:
        todo = [f for f in range(1, N + 1) if not os.path.exists(os.path.join(FRAMES_DIR, "%04d.png" % f))]
        film.render_frames(todo, FRAMES_DIR, "%04d.png")
        film.encode()
    print("[clip] done in %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
