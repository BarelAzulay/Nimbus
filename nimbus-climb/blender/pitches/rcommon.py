"""Shared Blender (bpy as a module) stage for the shop-area pitch renders: the lobby's pastel sky, a cream stone court,
sun + fill, a 5-stud player for scale, the kit's ModelSpec -> objects (nvox.blend.make_objects) with pitch materials
(glass see-through, Neon bright), cameras, and screen-space marker positions for the PIL labels.

1 Blender unit = 1 stud.  Kit models are Roblox space (front -Z, up +Y); nvox.blend maps them to Blender (front -Y,
up +Z).  Everything placed here by hand uses Blender space: (x, depth y, up z).

(Copied from .superpowers/lobby-shop/pitch-shoparea/scripts/rcommon.py for the shop-area T1 evidence renders
blender/pitches/shop_area_globe.py; the only change: the kit is blender/kit, one folder up.)
"""
import json
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector as V, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "kit"))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # the project path has Hebrew letters
except Exception:
    pass

from nvox import blend as B   # noqa: E402

TAU = math.tau
_mats = {}


def lin(r, g, b, a=1.0):
    f = lambda c: (c / 255.0) ** 2.2   # noqa: E731
    return (f(r), f(g), f(b), a)


def mat(name, col, rough=0.6, metal=0.0, emit=None, strength=0.0, alpha=1.0):
    key = (name, col, rough, metal, emit, strength, alpha)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(*col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = lin(*emit)
        b.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            m.blend_method = "BLEND"
    m.diffuse_color = lin(*col)
    _mats[key] = m
    return m


def box(size, loc, m, bevel=0.06, rot=(0, 0, 0), name="box", coll=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=2, affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = bevel > 0
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = rot
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def cyl(r, h, loc, m, segs=24, name="cyl", rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=h)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = rot
    bpy.context.scene.collection.objects.link(ob)
    return ob


def prism(r, h, loc, m, segs=4, rot=(0, 0, 0), name="prism"):
    """a square prism turned so it reads as a diamond (the altar's crystals)"""
    return cyl(r, h, loc, m, segs=segs, rot=rot, name=name)


def player(loc, shirt=(120, 130, 160), name="Player"):
    """a neutral 5-stud blocky player for scale (feet on loc)"""
    x, y, z = loc
    skin = mat("PlayerSkin", (232, 200, 170), 0.5)
    sh = mat("PlayerShirt" + str(shirt), shirt, 0.7)
    pants = mat("PlayerPants", (70, 76, 96), 0.7)
    for sx in (-0.5, 0.5):
        box((0.95, 0.95, 2.0), (x + sx, y, z + 1.0), pants, 0.1, name=name)
    box((2.0, 1.0, 2.0), (x, y, z + 3.0), sh, 0.12, name=name)
    for sx in (-1.5, 1.5):
        box((0.95, 0.95, 2.0), (x + sx, y, z + 3.0), skin, 0.1, name=name)
    box((1.2, 1.2, 1.2), (x, y, z + 4.62), skin, 0.3, name=name)


def stage(res=(1200, 900), samples=48, sky=((240, 232, 222), (96, 150, 236)), engine="BLENDER_EEVEE", raytrace=False):
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    try:
        sc.render.engine = engine
        sc.eevee.taa_render_samples = int(os.environ.get("PITCH_SAMPLES", samples))
        sc.eevee.shadow_ray_count = 4
        sc.eevee.shadow_step_count = 8
        sc.eevee.use_shadow_jitter_viewport = False
        try:
            sc.eevee.use_raytracing = raytrace
            sc.eevee.use_shadows = True
        except Exception:
            pass
    except Exception:
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = samples
        sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = 0.35
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = lin(*sky[0])
    ramp.color_ramp.elements[1].color = lin(*sky[1])
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[1].position = 0.22
    nt.links.new(tc.outputs["Normal"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    # key from the front-left-above (the customer's side), a cool fill from the back-right
    for name, d, energy, col in (("Sun", (0.45, 0.55, -0.7), 5.0, (1.0, 0.95, 0.88)),
                                 ("Fill", (-0.5, -0.4, -0.75), 1.2, (0.76, 0.8, 1.0))):
        L = bpy.data.lights.new(name, "SUN")
        L.energy, L.color, L.angle = energy, col, 0.12
        ob = bpy.data.objects.new(name, L)
        ob.rotation_euler = V(d).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(ob)
    return sc


def court(radius=34.0, tones=((236, 232, 222), (222, 216, 204)), cell=2.0, z=0.0, ring=None):
    """the shop court: a big stone disc with a 2-stud checker and an optional gold ring inlay (r0, r1)"""
    m = bpy.data.materials.new("Court")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.8
    tc = nt.nodes.new("ShaderNodeTexCoord")
    ck = nt.nodes.new("ShaderNodeTexChecker")
    ck.inputs["Scale"].default_value = 1.0 / cell
    ck.inputs["Color1"].default_value = lin(*tones[0])
    ck.inputs["Color2"].default_value = lin(*tones[1])
    nt.links.new(tc.outputs["Object"], ck.inputs["Vector"])
    nt.links.new(ck.outputs["Color"], b.inputs["Base Color"])
    ob = cyl(radius, 0.4, (0, 0, z - 0.2), m, segs=64, name="Court")
    if ring:
        r0, r1 = ring
        gm = mat("CourtGold", (206, 154, 62), 0.6, 0.2)
        rg = cyl(r1, 0.44, (0, 0, z - 0.2), gm, segs=64, name="Inlay")
        # a thin ring: cut the middle by a slightly smaller, taller cylinder of the court tone (cheap: two discs)
        inner = cyl(r0, 0.46, (0, 0, z - 0.2), m, segs=64, name="InlayInner")
        del rg, inner
    return ob


def add_model(model, look, at=(0, 0, 0), yaw=0.0, glass_alpha=0.22, neon=3.0, glass_rgb=(170, 210, 250), glass_rough=0.35):
    """the kit ModelSpec -> Blender objects at Blender position `at`, turned yaw radians about Z (0 = facing -Y)
    (shop-area polish: glass_rgb / glass_rough, the glass's own colour and a glossier finish for the clear globe)"""
    M = Matrix.Translation(V(at)) @ Matrix.Rotation(yaw, 4, "Z")
    made = B.make_objects(model, look, matrix=np.array(M))
    made2 = []
    specs = list(model.objects.values())          # make_objects keeps this order (bpy renames duplicates: Glass.001)
    for o, ob in zip(specs, made):
        m = ob.active_material
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if o is not None and o.material == "Glass":
            if os.environ.get("PITCH_NOGLASS"):
                bpy.data.objects.remove(ob)
                continue
            bsdf.inputs["Base Color"].default_value = lin(*glass_rgb)
            bsdf.inputs["Alpha"].default_value = float(os.environ.get("PITCH_GLASS", glass_alpha))
            bsdf.inputs["Roughness"].default_value = glass_rough
            bsdf.inputs["Specular IOR Level"].default_value = 0.12
            try:
                m.surface_render_method = "BLENDED"
            except Exception:
                m.blend_method = "BLEND"
            m.show_transparent_back = False
            m.use_backface_culling = True
            try:
                ob.visible_shadow = False          # EEVEE's stochastic transparent shadows stipple the eggs inside
            except Exception:
                pass
        elif o is not None and o.material == "Neon":
            bsdf.inputs["Emission Strength"].default_value = neon
            bsdf.inputs["Roughness"].default_value = 0.4
        else:
            bsdf.inputs["Roughness"].default_value = 0.62
        for p in ob.data.polygons:
            p.use_smooth = False
        made2.append(ob)
    return made2


def camera(loc, target, lens=40, name="Cam"):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.clip_end = 600
    cam = bpy.data.objects.new(name, cd)
    sc.collection.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = (V(target) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return cam


def shoot(path, loc, target, lens=40, markers=None):
    """render to path; markers = {name: (x, y, z)} -> writes path + '.json' with their pixel positions"""
    cam = camera(loc, target, lens)
    sc = bpy.context.scene
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    if markers:
        from bpy_extras.object_utils import world_to_camera_view as w2c
        w, h = sc.render.resolution_x, sc.render.resolution_y
        px = {}
        for k, p in markers.items():
            c = w2c(sc, cam, V(p))
            px[k] = [round(c.x * w, 1), round((1 - c.y) * h, 1), c.z > 0]
        with open(path + ".json", "w") as fh:
            json.dump(px, fh)
    print("[render]", path, flush=True)
    bpy.data.objects.remove(cam)
