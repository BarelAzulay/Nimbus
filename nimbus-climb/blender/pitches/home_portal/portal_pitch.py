"""Home-portal design pitch: three concept mock-ups for Nimbus Climb's personal home portal, rendered in Blender.

    python portal_pitch.py <out_dir> [--res 100] [--samples 32]

Writes option_a.png, option_b.png, option_c.png (each 3/4 view with a 5-stud player for scale) and lineup.png.
1 Blender unit = 1 Roblox stud. Every portal faces -Y; its swirl is a Neon-like emissive disc inside the frame.
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector as V

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
RES = int(sys.argv[sys.argv.index("--res") + 1]) if "--res" in sys.argv else 100
SAMPLES = int(sys.argv[sys.argv.index("--samples") + 1]) if "--samples" in sys.argv else 32
TAU = math.tau
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # the project path has Hebrew letters
except Exception:
    pass
os.makedirs(OUT, exist_ok=True)


def rgb(r, g, b, a=1.0):
    f = lambda c: (c / 255.0) ** 2.2
    return (f(r), f(g), f(b), a)


_mats = {}


def mat(name, col, rough=0.6, metal=0.0, emit=None, strength=0.0):
    key = (name, col, rough, metal, emit, strength)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = rgb(*col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = rgb(*emit)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = rgb(*col)
    _mats[key] = m
    return m


def box(coll, size, loc, m, bevel=0.08, rot=(0, 0, 0), parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=2,
                        affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new("box")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(m)
    ob = bpy.data.objects.new("box", me)
    ob.location = loc
    ob.rotation_euler = rot
    coll.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


def swirl(coll, loc, rx, rz, name="Swirl", rect=False):
    """the portal surface: an emissive disc (or rounded rectangle) facing -Y with banded swirl rings"""
    n = 48
    verts = [(0, 0, 0)]
    for i in range(n):
        a = TAU * i / n
        if rect:
            c, s = math.cos(a), math.sin(a)
            k = 1.0 / max(abs(c), abs(s)) ** 0.85
            verts.append((c * rx * min(k, 1.25), 0, s * rz * min(k, 1.25)))
        else:
            verts.append((math.cos(a) * rx, 0, math.sin(a) * rz))
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])

    def op(kind, a, b=None, val=None):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = kind
        nt.links.new(a, n.inputs[0])
        if b is not None:
            nt.links.new(b, n.inputs[1])
        elif val is not None:
            n.inputs[1].default_value = val
        return n.outputs[0]

    ang = op("ARCTAN2", sep.outputs["Z"], sep.outputs["X"])
    rad = op("SQRT", op("ADD", op("MULTIPLY", sep.outputs["X"], sep.outputs["X"]),
                        op("MULTIPLY", sep.outputs["Z"], sep.outputs["Z"])))
    spiral = op("SINE", op("ADD", op("MULTIPLY", ang, val=3.0), op("MULTIPLY", rad, val=-2.6)))
    fac = op("ADD", op("MULTIPLY", spiral, val=0.5), val=0.5)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = rgb(30, 110, 235)
    ramp.color_ramp.elements[1].color = rgb(120, 225, 255)
    nt.links.new(fac, ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.1
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    coll.objects.link(ob)
    L = bpy.data.lights.new(name + "Glow", "POINT")
    L.energy, L.color, L.shadow_soft_size = 900, (0.45, 0.8, 1.0), 2.0
    lo = bpy.data.objects.new(name + "Glow", L)
    lo.location = V(loc) + V((0, -1.5, 0))
    coll.objects.link(lo)
    return ob


def arch_blocks(coll, cx, cz, R, n, size, m, a0=0.0, a1=math.pi, y=0.0, jitter=0.0, rng=None):
    for i in range(n):
        a = a0 + (a1 - a0) * (i + 0.5) / n
        p = (cx + R * math.cos(a), y, cz + R * math.sin(a))
        j = (rng.uniform(-jitter, jitter) if rng else 0.0)
        box(coll, size, p, m, 0.1, rot=(0, a - math.pi / 2 + j, 0))


def player(coll, loc):
    """a neutral 5-stud blocky player for scale"""
    x, y, z = loc
    skin = mat("PlayerSkin", (232, 200, 170), 0.5)
    shirt = mat("PlayerShirt", (120, 130, 160), 0.7)
    pants = mat("PlayerPants", (70, 76, 96), 0.7)
    for sx in (-0.5, 0.5):
        box(coll, (0.95, 0.95, 2.0), (x + sx, y, z + 1.0), pants, 0.1)
    box(coll, (2.0, 1.0, 2.0), (x, y, z + 3.0), shirt, 0.12)
    for sx in (-1.5, 1.5):
        box(coll, (0.95, 0.95, 2.0), (x + sx, y, z + 3.0), skin, 0.1)
    box(coll, (1.2, 1.2, 1.2), (x, y, z + 4.62), skin, 0.3)


# ================================================================================ option A: Homestead Trellis
def option_a(coll, ox):
    rng = random.Random(1)
    oak = mat("Oak", (160, 105, 55), 0.7)
    oak2 = mat("OakDark", (122, 78, 40), 0.75)
    stone = mat("Stone", (196, 192, 200), 0.85)
    stone2 = mat("StoneDark", (150, 146, 160), 0.9)
    plaster = mat("Plaster", (240, 240, 235), 0.8)
    roof = mat("Roof", (196, 84, 70), 0.7)
    leaf = mat("Leaf", (85, 170, 85), 0.7)
    leaf2 = mat("Leaf2", (60, 140, 70), 0.75)
    brass = mat("Brass", (214, 170, 70), 0.35, 0.8)
    iron = mat("Iron", (60, 62, 70), 0.5, 0.6)
    # stone steps
    box(coll, (10.5, 4.0, 0.6), (ox, 0.4, 0.3), stone2, 0.12)
    box(coll, (8.6, 2.0, 0.5), (ox, -1.4, 0.85), stone, 0.12)
    # pillars of offset stacked stones
    for sx in (-3.6, 3.6):
        for k in range(6):
            w = 2.1 if k % 2 == 0 else 1.9
            box(coll, (w, 2.0, 1.15), (ox + sx + rng.uniform(-0.06, 0.06), 0, 1.2 + k * 1.15),
                stone if (k + int(sx > 0)) % 3 else stone2, 0.12)
        box(coll, (2.5, 2.4, 0.5), (ox + sx, 0, 8.25), stone2, 0.1)
    # the wooden arch (two layers, the back one darker) springing from the pillar caps
    arch_blocks(coll, ox, 8.5, 3.6, 13, (0.95, 1.2, 0.8), oak, y=-0.3)
    arch_blocks(coll, ox, 8.5, 3.6, 13, (0.95, 1.0, 0.8), oak2, y=0.75)
    # iron corner brackets where the arch meets the pillars
    for sx in (-1, 1):
        box(coll, (0.8, 0.3, 1.1), (ox + sx * 3.6, -1.15, 8.75), iron, 0.04)
    # the swirl
    swirl(coll, (ox, 0.2, 6.0), 2.75, 4.6, "SwirlA")
    # cottage crest: plaster walls, a red stepped roof, a door, a chimney
    cz = 12.6
    box(coll, (2.8, 1.8, 1.6), (ox, 0, cz), plaster, 0.1)
    for k in range(3):
        box(coll, (3.3 - k * 1.05, 2.1, 0.45), (ox, 0, cz + 1.0 + k * 0.42), roof, 0.08)
    box(coll, (0.7, 0.2, 1.0), (ox, -0.92, cz - 0.3), oak2, 0.05)
    box(coll, (0.45, 0.45, 0.9), (ox + 0.9, 0.2, cz + 1.9), stone2, 0.06)
    box(coll, (0.5, 0.15, 0.5), (ox - 0.85, -0.92, cz + 0.2), mat("Window", (255, 220, 140), 0.3, emit=(255, 200, 110), strength=2.0), 0.03)
    # brass "HOME" plate hanging askew on one chain
    box(coll, (2.2, 0.15, 0.7), (ox + 0.2, -1.4, 10.5), brass, 0.06, rot=(0, 0.12, 0))
    box(coll, (0.08, 0.08, 0.7), (ox - 0.7, -1.4, 11.1), iron, 0.0)
    # ivy creeping up the left pillar
    for k in range(10):
        box(coll, (0.55, 0.4, 0.55), (ox - 4.4 + rng.uniform(-0.3, 0.6), -1.05, 1.2 + k * 0.75 + rng.uniform(-0.2, 0.2)),
            leaf if k % 2 else leaf2, 0.08, rot=(0, rng.uniform(-0.5, 0.5), 0))
    # a little carved bird on the arch
    box(coll, (0.6, 0.4, 0.4), (ox + 2.0, -0.4, 11.55), mat("Bird", (120, 170, 220), 0.6), 0.1)
    box(coll, (0.3, 0.3, 0.3), (ox + 2.3, -0.5, 11.85), mat("Bird", (120, 170, 220), 0.6), 0.08)


# ================================================================================ option B: Cloud-Potter's Gate
def option_b(coll, ox):
    rng = random.Random(2)
    terra = mat("Terracotta", (204, 119, 85), 0.8)
    terra2 = mat("TerracottaDark", (170, 92, 64), 0.85)
    vine = mat("Vine", (96, 190, 120), 0.7)
    vine2 = mat("VineDark", (66, 150, 96), 0.75)
    mint = mat("Mint", (152, 230, 160), 0.7)
    sun = mat("Sunflower", (255, 214, 90), 0.6)
    sun2 = mat("SunflowerCore", (120, 72, 40), 0.8)
    dirt = mat("Dirt", (110, 74, 50), 0.95)
    daisy = mat("Daisy", (250, 250, 245), 0.6)
    brass = mat("Brass", (214, 170, 70), 0.35, 0.8)
    oak = mat("Oak", (160, 105, 55), 0.7)
    # the long terracotta planter (rim, body, a darker band) the vines grow from
    box(coll, (11.0, 4.2, 0.6), (ox, 0, 2.55), terra2, 0.15)
    box(coll, (10.2, 3.6, 2.2), (ox, 0, 1.25), terra, 0.15)
    box(coll, (10.4, 3.7, 0.35), (ox, 0, 0.7), terra2, 0.08)
    box(coll, (10.4, 3.4, 0.3), (ox, 0, 2.95), dirt, 0.05)
    # painted daisies on the pot
    for k, x in enumerate((-3.5, -1.2, 1.4, 3.6)):
        for a in range(5):
            t = TAU * a / 5
            box(coll, (0.35, 0.08, 0.35), (ox + x + math.cos(t) * 0.35, -1.83, 1.4 + math.sin(t) * 0.35), daisy, 0.03)
        box(coll, (0.25, 0.1, 0.25), (ox + x, -1.86, 1.4), sun, 0.03)
    # two vine columns that arch and meet: chunky blocks with leaves
    for side in (-1, 1):
        for k in range(8):
            box(coll, (1.3, 1.3, 1.0), (ox + side * (3.7 + 0.15 * math.sin(k)), 0, 3.6 + k * 0.95),
                vine if k % 2 else vine2, 0.15, rot=(0, 0.08 * side * math.sin(k * 1.3), 0))
    arch_blocks(coll, ox, 11.0, 3.7, 9, (1.4, 1.3, 1.1), vine, jitter=0.08, rng=rng)
    for k in range(14):
        a = rng.uniform(0.0, math.pi)
        side = rng.choice((-1, 1))
        if k < 8:
            p = (ox + side * rng.uniform(4.3, 4.7), rng.uniform(-0.6, 0.3), rng.uniform(4.0, 10.5))
        else:
            p = (ox + 3.9 * math.cos(a), rng.uniform(-0.6, 0.3), 11.0 + 3.9 * math.sin(a))
        box(coll, (0.9, 0.25, 0.55), p, mint, 0.08, rot=(0, rng.uniform(-0.8, 0.8), 0))
    # the swirl, a droplet between the vines
    swirl(coll, (ox, 0.0, 8.4), 2.9, 4.8, "SwirlB")
    # oversized sunflower crest
    cz = 16.3
    for a in range(12):
        t = TAU * a / 12
        box(coll, (1.1, 0.35, 0.6), (ox + math.cos(t) * 1.55, -0.2, cz + math.sin(t) * 1.55), sun, 0.12, rot=(0, -t, 0))
    box(coll, (1.9, 0.6, 1.9), (ox, -0.35, cz), sun2, 0.25)
    box(coll, (0.6, 0.6, 1.6), (ox, 0, cz - 2.0), vine2, 0.1)
    # spilled dirt, a trowel, a watering-can spout
    for k in range(6):
        box(coll, (0.6, 0.6, 0.35), (ox - 4.0 + rng.uniform(-1.0, 1.0), -2.6 + rng.uniform(-0.6, 0.4), 0.18), dirt, 0.1)
    box(coll, (0.35, 0.25, 1.6), (ox + 5.6, -1.6, 1.0), oak, 0.05, rot=(0, -0.35, 0))
    box(coll, (0.6, 0.12, 0.8), (ox + 5.95, -1.6, 0.25), mat("Steel", (190, 196, 205), 0.3, 0.8), 0.04, rot=(0, -0.35, 0))
    box(coll, (0.3, 0.3, 1.4), (ox + 4.6, -0.2, 9.2), brass, 0.06, rot=(0, -0.9, 0))


# ================================================================================ option C: Waypoint Mailbox
def option_c(coll, ox):
    rng = random.Random(3)
    red = mat("PostRed", (200, 50, 50), 0.45)
    red2 = mat("PostRedDark", (150, 34, 40), 0.5)
    slate = mat("Slate", (100, 110, 120), 0.6, 0.4)
    brass = mat("Brass", (214, 170, 70), 0.35, 0.8)
    paper = mat("Paper", (246, 240, 226), 0.8)
    wax = mat("Wax", (180, 30, 50), 0.4)
    stone = mat("Stone", (196, 192, 200), 0.85)
    # base plinth and the slate post
    box(coll, (8.0, 3.6, 0.8), (ox, 0, 0.4), stone, 0.12)
    box(coll, (1.4, 1.4, 2.2), (ox, 0, 1.9), slate, 0.1)
    # the open-letterbox frame: red box frame with rounded corners
    W, H, cz = 8.0, 9.4, 7.9
    box(coll, (W, 2.4, 1.1), (ox, 0, cz + H / 2), red, 0.3)
    box(coll, (W, 2.4, 1.1), (ox, 0, cz - H / 2), red, 0.3)
    for sx in (-1, 1):
        box(coll, (1.1, 2.4, H), (ox + sx * W / 2, 0, cz), red, 0.3)
    box(coll, (W + 0.4, 0.4, 0.5), (ox, -1.1, cz + H / 2 - 0.15), red2, 0.08)
    # brass rivets
    for k in range(7):
        for z in (cz + H / 2, cz - H / 2):
            box(coll, (0.25, 0.2, 0.25), (ox - W / 2 + 0.9 + k * (W - 1.8) / 6, -1.25, z), brass, 0.06)
    # glowing number plate on the lintel
    box(coll, (2.4, 0.2, 0.7), (ox, -1.3, cz + H / 2 + 0.05), mat("Plate", (40, 40, 60), 0.4, emit=(255, 220, 140), strength=1.2), 0.05)
    # the swirl, flush like a magic mail slot
    swirl(coll, (ox, 0.0, cz), 3.1, 3.9, "SwirlC", rect=True)
    # the red flag on the side
    box(coll, (0.25, 0.25, 2.4), (ox + W / 2 + 0.75, 0, cz + 1.2), slate, 0.05)
    box(coll, (1.4, 0.15, 0.9), (ox + W / 2 + 1.5, 0, cz + 2.0), red, 0.05)
    # envelope crest with a wax seal
    ez = cz + H / 2 + 1.9
    box(coll, (4.0, 0.5, 2.5), (ox, 0, ez), paper, 0.1)
    for side in (-1, 1):
        box(coll, (2.35, 0.1, 0.3), (ox + side * 0.95, -0.28, ez + 0.35), mat("PaperFold", (220, 210, 190), 0.8), 0.03,
            rot=(0, side * 0.55, 0))
    box(coll, (0.8, 0.2, 0.8), (ox, -0.35, ez - 0.15), wax, 0.25)
    # a stack of dropped letters and a small gear on the back
    for k in range(4):
        box(coll, (1.4, 0.9, 0.12), (ox - 2.8 + rng.uniform(-0.4, 0.4), -2.4 + rng.uniform(-0.3, 0.3), 0.86 + k * 0.13),
            paper, 0.03, rot=(0, 0, rng.uniform(-0.6, 0.6)))
    for a in range(8):
        t = TAU * a / 8
        box(coll, (0.4, 0.3, 0.4), (ox + 2.4 + math.cos(t) * 0.9, 1.3, cz - 2.5 + math.sin(t) * 0.9), brass, 0.05, rot=(0, -t, 0))


# ================================================================================ stage, lights, cameras
def stage():
    sc = bpy.context.scene
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    sc.render.engine = "BLENDER_EEVEE"
    sc.eevee.taa_render_samples = SAMPLES
    try:
        sc.eevee.use_raytracing = True
    except Exception:
        pass
    sc.view_settings.view_transform = "AgX"
    sc.render.resolution_x, sc.render.resolution_y = 1280, 960
    sc.render.resolution_percentage = RES
    w = bpy.data.worlds.new("Twilight")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = rgb(250, 206, 222)
    ramp.color_ramp.elements[1].color = rgb(118, 128, 226)
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[1].position = 0.22
    nt.links.new(tc.outputs["Normal"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.9
    coll = sc.collection
    # plaza floor: pale stone tiles
    t1, t2 = mat("Tile", (226, 224, 236), 0.35), mat("Tile2", (210, 208, 226), 0.35)
    for i in range(-16, 17):
        for j in range(-26, 9):
            box(coll, (3.9, 3.9, 0.4), (i * 4.0, j * 4.0, -0.2), t1 if (i + j) % 2 else t2, 0.05)
    for name, rot, energy, col in (("Sun", (0.85, 0.2, -0.6), 3.2, (1.0, 0.92, 0.84)),
                                   ("Fill", (1.1, 0.0, 2.6), 0.9, (0.72, 0.74, 1.0))):
        L = bpy.data.lights.new(name, "SUN")
        L.energy, L.color, L.angle = energy, col, 0.12
        ob = bpy.data.objects.new(name, L)
        ob.rotation_euler = rot
        coll.objects.link(ob)
    return coll


def shoot(path, cam_loc, target, lens=40):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = cam_loc
    cam.rotation_euler = (V(target) - V(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[pitch]", path)


coll = stage()
SP = 26.0
option_a(coll, -SP)
option_b(coll, 0.0)
option_c(coll, SP)
for x in (-SP, 0.0, SP):
    player(coll, (x - 6.6, -1.5, 0.0))
for i, x in enumerate((-SP, 0.0, SP)):
    shoot(os.path.join(OUT, "option_%s.png" % "abc"[i]), (x - 17.0, -33.0, 8.0), (x - 1.6, 0, 8.6), 50)
shoot(os.path.join(OUT, "lineup.png"), (0, -78.0, 12.0), (0, 0, 8.5), 42)
