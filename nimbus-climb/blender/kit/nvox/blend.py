"""Blender side (bpy 5.x as a module, headless): ModelSpec -> mesh objects -> FBX, re-import check, preview PNG.

Axes.  The manifest and every number in it are in ROBLOX space (+X right, +Y up, -Z forward, studs).  Inside
Blender the kit uses Blender's own convention (front = -Y, up = +Z):  blender = (-x, z, y)  (a proper rotation).
The FBX is written with Roblox's documented Blender settings (create.roblox.com/docs/art/blender):
  Unit System None, scale 1  ->  1 Blender unit = 1 stud;  Apply Scalings = "FBX Unit Scale";  Forward = Z, Up = Y
which maps blender (-x, z, y) back to (x, y, z): the FBX's raw vertex coordinates ARE Roblox studs (checked by
verify_fbx's raw read).
"""
import math
import os

import bpy
import numpy as np

from . import colors as C

PM = np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])  # roblox -> blender (PM is its own inverse)


def to_bl(p):
    return PM @ np.asarray(p, float)


def cf_to_bl(R, p):
    M = np.eye(4)
    M[:3, :3] = PM @ np.asarray(R, float) @ PM
    M[:3, 3] = to_bl(p)
    return M


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    sc.unit_settings.scale_length = 1.0
    return sc


def _material(name, color, metallic=0.0, emit=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    lin = [C.srgb_to_linear(c) for c in color[:3]] + [1.0]
    mul.inputs[6].default_value = lin
    nt.links.new(attr.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    bsdf.inputs["Metallic"].default_value = metallic
    if emit:
        nt.links.new(mul.outputs[2], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.2
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mat.diffuse_color = lin
    return mat


def make_objects(model, look, collection=None, matrix=None, export=False):
    """one Blender mesh object per ObjectSpec; vertices welded per object, a CORNER byte colour layer "Col".
    export=True: every object gets the one shared white material M_Vertex (recipe 4.4); otherwise a preview
    material in the part's colour for `look` (recipes evaluated like the runtime)."""
    col = collection or bpy.context.scene.collection
    made = []
    for o in model.objects.values():
        verts, index, faces, fcols = [], {}, [], []
        for corners, vc in o.quads:
            f = []
            for p in corners:
                q = to_bl(p)
                k = (round(q[0], 5), round(q[1], 5), round(q[2], 5))
                i = index.get(k)
                if i is None:
                    i = len(verts)
                    index[k] = i
                    verts.append(k)
                f.append(i)
            faces.append(f)
            fcols.append(vc)
        me = bpy.data.meshes.new(o.name)
        me.from_pydata(verts, [], faces)
        me.validate()
        attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        counts = [len(f) for f in faces]
        data = np.repeat(np.array([list(c) + [1.0] for c in fcols], np.float32), counts, axis=0)
        # BYTE_COLOR stores sRGB bytes; .color takes linear floats, .color_srgb sRGB floats
        attr.data.foreach_set("color_srgb", data.ravel())
        me.color_attributes.active_color = attr
        ob = bpy.data.objects.new(o.name, me)
        col.objects.link(ob)
        if matrix is not None:
            from mathutils import Matrix
            ob.matrix_world = Matrix(matrix.tolist())
        if export:
            mat = bpy.data.materials.get("M_Vertex") or _material("M_Vertex", (1.0, 1.0, 1.0))
        else:
            if o.baked or o.recipe is None:
                base = (1.0, 1.0, 1.0)
            else:
                base = C.eval_recipe(o.recipe, look)
            mat = _material("M_" + model.name + "_" + o.name, base, emit=(o.material == "Neon"),
                            metallic=0.25 if o.material == "Metal" else 0.0)
            tr = getattr(o, "transparency", None)
            if tr:
                bsdf = mat.node_tree.nodes.get("Principled BSDF")
                if bsdf is not None:
                    bsdf.inputs["Alpha"].default_value = max(0.05, 1.0 - float(tr))
        me.materials.append(mat)
        made.append(ob)
    return made


def export_fbx(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS",
        global_scale=1.0, apply_unit_scale=True, axis_forward="Z", axis_up="Y", use_mesh_modifiers=False,
        mesh_smooth_type="FACE", colors_type="SRGB", add_leaf_bones=False, bake_anim=False,
        use_custom_props=False, path_mode="STRIP", use_space_transform=True, bake_space_transform=True,
    )
    zero_timestamp(path)
    return os.path.getsize(path)


TIMESTAMP_FIELDS = ((b"Year", 2000), (b"Month", 1), (b"Day", 1), (b"Hour", 0), (b"Minute", 0), (b"Second", 0),
                    (b"Millisecond", 0))


def zero_timestamp(path):
    """Make the FBX bytes deterministic: the exporter's CreationTimeStamp (Year..Millisecond int32 properties) gets
    fixed values.  (Blender already writes a constant FileId and CreationTime string; checked by verify_fbx:
    exporting the same model twice gives the same bytes.)"""
    import struct
    data = bytearray(open(path, "rb").read())
    head = bytes(data[:4096])
    start = head.find(b"CreationTimeStamp")
    if start < 0:
        return False
    for name, value in TIMESTAMP_FIELDS:
        pat = bytes([len(name)]) + name + b"I"
        i = head.find(pat, start)
        if i < 0:
            continue
        j = i + len(pat)
        data[j:j + 4] = struct.pack("<i", value)
    with open(path, "wb") as fh:
        fh.write(bytes(data))
    return True


def _mesh_stats(ob):
    me = ob.data
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    co = np.array([ob.matrix_world @ v.co for v in me.vertices])
    return tris, co


def verify_fbx(path, model):
    """Re-import the FBX twice in a clean scene: (1) a normal import (round trip: names, sizes, triangles, colour
    layer) and (2) a RAW read (no axis / unit conversion) whose coordinates must equal the manifest's Roblox studs."""
    report = {"file": os.path.basename(path), "ok": True, "problems": []}
    expect = {}
    for o in model.objects.values():
        a = np.concatenate([q[0] for q in o.quads])
        expect[o.name] = (a.min(0), a.max(0), o.tris())
    for mode in ("roundtrip", "raw", "header"):
        reset_scene()
        if mode == "roundtrip":
            bpy.ops.import_scene.fbx(filepath=path, axis_forward="Z", axis_up="Y", use_manual_orientation=True)
        elif mode == "header":
            # honour the file's own axis header (what a generic importer does): the front must land at -Y
            bpy.ops.import_scene.fbx(filepath=path)
        else:
            # forward Y / up Z = Blender's own axes: no conversion, Blender coordinates == the file's raw coordinates
            bpy.ops.import_scene.fbx(filepath=path, use_manual_orientation=True, axis_forward="Y", axis_up="Z",
                                     global_scale=1.0, bake_space_transform=False)
        got = {}
        for ob in bpy.context.scene.objects:
            if ob.type != "MESH":
                continue
            tris, co = _mesh_stats(ob)
            got[ob.name] = (co, tris, len(ob.data.color_attributes))
        if set(got) != set(expect):
            report["ok"] = False
            report["problems"].append("%s: object names differ: missing %s extra %s" % (
                mode, sorted(set(expect) - set(got)), sorted(set(got) - set(expect))))
        worst = 0.0
        for name, (lo, hi, tris) in expect.items():
            if name not in got:
                continue
            co, gtris, ncol = got[name]
            if mode in ("roundtrip", "header"):
                rob = co @ PM.T  # back to roblox space (front -Z <-> blender -Y)
            else:
                rob = co  # the file's raw coordinates must already be Roblox studs
            err = max(np.abs(rob.min(0) - lo).max(), np.abs(rob.max(0) - hi).max())
            worst = max(worst, err)
            if gtris != tris:
                report["ok"] = False
                report["problems"].append("%s %s: %d tris, expected %d" % (mode, name, gtris, tris))
            if ncol < 1:
                report["ok"] = False
                report["problems"].append("%s %s: no colour layer" % (mode, name))
        report[mode + "_max_error_studs"] = round(float(worst), 6)
        if worst > 1e-3:
            report["ok"] = False
            report["problems"].append("%s: positions differ by %.4f studs" % (mode, worst))
        report[mode + "_objects"] = len(got)
        report[mode + "_tris"] = int(sum(v[1] for v in got.values()))
    return report


# ---------------------------------------------------------------- preview rendering (Cycles CPU, orthographic)
VIEWS = {
    # name: (yaw degrees around the model's up axis, pitch degrees) ; yaw 0 = looking at the face
    "front": (0, 8), "threequarter": (-38, 22), "side": (-90, 6), "back": (180, 10), "hero": (-28, 14),
}


def setup_render(res=520, samples=48):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    try:
        sc.cycles.use_denoising = True
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        sc.cycles.use_denoising = False
        sc.cycles.samples = samples * 3
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.new("W")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.92, 0.95, 1.0, 1)
    bg.inputs["Strength"].default_value = 0.75
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 1.5
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("Sun", sun)
    sc.collection.objects.link(so)
    # key light from the upper front-left (like tools/render_model.py)
    so.rotation_euler = (math.radians(50), 0, math.radians(-35))
    return sc


def render_views(objs_bounds, out_png, views=("front", "threequarter", "side", "back"), res=520, label=None):
    lo, hi = objs_bounds
    centre = (np.asarray(lo) + np.asarray(hi)) / 2
    ext = float(np.max(np.asarray(hi) - np.asarray(lo)))
    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ext * 1.22
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    tiles = []
    tmp = out_png + ".tile.png"
    from mathutils import Vector
    c_bl = Vector(to_bl(centre).tolist())
    for v in views:
        yaw, pitch = VIEWS[v]
        # camera direction: from the front (-Y in blender) rotated by yaw around Z, raised by pitch
        y, p = math.radians(yaw), math.radians(pitch)
        d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
        cam.location = c_bl + d * (ext * 4)
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        px = np.array(img.pixels[:], np.float32).reshape(res, res, 4)
        # alpha over a soft sky gradient (bottom-up rows: row 0 is the bottom)
        t = np.linspace(0, 1, res, dtype=np.float32)[:, None, None]
        top, bottom = np.array([172, 208, 246], np.float32) / 255, np.array([236, 244, 252], np.float32) / 255
        bg = bottom * (1 - t) + top * t
        a = px[:, :, 3:4]
        rgb = px[:, :, :3] * a + bg * (1 - a)
        tiles.append(np.concatenate([rgb, np.ones_like(a)], 2))
        bpy.data.images.remove(img)
    os.remove(tmp)
    n = len(tiles)
    cols = 2 if n == 4 else n
    rows = (n + cols - 1) // cols
    sheet = np.ones((rows * res, cols * res, 4), np.float32)
    for i, t in enumerate(tiles):
        r, c = i // cols, i % cols
        # blender pixels are bottom-up; the sheet is built bottom-up too
        sheet[(rows - 1 - r) * res:(rows - r) * res, c * res:(c + 1) * res] = t
    img = bpy.data.images.new("sheet", cols * res, rows * res, alpha=True)
    img.pixels.foreach_set(sheet.ravel())
    img.filepath_raw = out_png
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return out_png
