"""
Pebble Pup for Nimbus Climb - a Blender script.

How to use (Blender 3.6 or newer):
  1. Open Blender. Click the "Scripting" tab at the top.
  2. Click "Open", pick this file (or paste it into a new text), then press "Run Script" (the play button).
  3. The pup appears in the 3D view. A ready-to-import FBX and its colour texture are saved in a
     "NimbusPets" folder on your Desktop (or in your home folder if there is no Desktop).
  4. Roblox Studio: Home > Import 3D > pick PebblePup.fbx. If the pup comes in grey, add a
     SurfaceAppearance to the MeshPart and set its ColorMap to PebblePup_color.png (upload it first).

Running it again rebuilds the pup; it only touches its own "PebblePup" collection.
"""

import math
import os

import bpy

# ---------------------------------------------------------------- settings
NAME = "PebblePup"
TRI_TARGET = 15000       # Roblox allows 20,000 triangles per mesh; the pup is built under this, so no slimming
TEXTURE_SIZE = 1024
BAKE_TEXTURE = True      # bake all colours into one texture (Roblox needs a texture for colours)
EXPORT_FBX = True


def srgb(r, g, b):
    """0-255 sRGB (the game's colours) -> Blender's linear colour."""
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), 1.0)


# The colours of Pebble Pup in the game (PetCatalog / PetBuilder)
COLORS = {
    "Fur": (srgb(190, 154, 114), 0.8),
    "FurDark": (srgb(148, 116, 84), 0.8),
    "Cream": (srgb(244, 232, 212), 0.85),
    "Nose": (srgb(54, 40, 42), 0.25),
    "Eye": (srgb(42, 30, 28), 0.15),
    "Shine": (srgb(255, 255, 255), 0.2),
    "Tongue": (srgb(240, 120, 140), 0.5),
    "Blush": (srgb(250, 160, 160), 0.7),
    "Wing": (srgb(214, 190, 158), 0.7),
}


# ---------------------------------------------------------------- scene helpers
def out_folder():
    home = os.path.expanduser("~")
    for cand in (os.path.join(home, "Desktop"), os.path.join(home, "OneDrive", "Desktop"), home):
        if os.path.isdir(cand):
            path = os.path.join(cand, "NimbusPets")
            os.makedirs(path, exist_ok=True)
            return path
    return bpy.app.tempdir


def fresh_collection():
    old = bpy.data.collections.get(NAME)
    if old:
        for ob in list(old.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.collections.remove(old)
    col = bpy.data.collections.new(NAME)
    bpy.context.scene.collection.children.link(col)
    layer = bpy.context.view_layer.layer_collection.children[col.name]
    bpy.context.view_layer.active_layer_collection = layer
    return col


def material(key):
    name = "PP_" + key
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    color, rough = COLORS[key]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    mat.diffuse_color = color  # the colour in Solid view
    return mat


def finish(ob, key, smooth=True):
    ob.data.materials.clear()
    ob.data.materials.append(material(key))
    if smooth:
        for poly in ob.data.polygons:
            poly.use_smooth = True
    return ob


def ball(key, loc, scale, rot=(0, 0, 0), detail=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=detail, ring_count=max(8, detail // 2), radius=1,
                                         location=loc, rotation=rot, scale=scale)
    return finish(bpy.context.active_object, key)


def tube(key, points, radius, tip=1.0, name="Tube"):
    """A smooth rounded tube through points, thinning to radius*tip at the end."""
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = 4
    data.use_fill_caps = True
    spline = data.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for i, p in enumerate(points):
        spline.points[i].co = (p[0], p[1], p[2], 1)
        spline.points[i].radius = 1 + (tip - 1) * i / (len(points) - 1)
    spline.order_u = 3
    spline.use_endpoint_u = True
    spline.resolution_u = 10
    ob = bpy.data.objects.new(name, data)
    bpy.context.view_layer.active_layer_collection.collection.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    return finish(bpy.context.active_object, key)


# ---------------------------------------------------------------- the pup (faces -Y, Z up, sits on Z = 0)
def build():
    # body: a sitting egg with a cream belly
    ball("Fur", (0, 0.15, 0.75), (0.62, 0.6, 0.72), detail=32)
    ball("Cream", (0, -0.22, 0.74), (0.34, 0.3, 0.5), detail=24)

    # big chibi head
    ball("Fur", (0, -0.05, 1.85), (0.85, 0.75, 0.72), detail=44)
    ball("Cream", (0, -0.68, 2.0), (0.11, 0.07, 0.26), detail=16)          # blaze up the forehead
    ball("Cream", (0, -0.62, 1.62), (0.38, 0.3, 0.27), detail=32)          # muzzle
    ball("Nose", (0, -0.9, 1.74), (0.15, 0.09, 0.1), detail=20)            # big glossy nose
    ball("Shine", (-0.05, -0.97, 1.79), (0.035, 0.02, 0.025), detail=10)
    ball("Tongue", (0, -0.86, 1.47), (0.06, 0.03, 0.05), detail=12)
    # the little "w" smile
    tube("Eye", [(-0.13, -0.86, 1.56), (-0.06, -0.9, 1.5), (0, -0.92, 1.57),
                 (0.06, -0.9, 1.5), (0.13, -0.86, 1.56)], 0.014, name="Mouth")

    # the darker patch around one eye, then the eyes with two shines each
    ball("FurDark", (0.33, -0.6, 1.97), (0.27, 0.12, 0.28), detail=20)
    for s in (-1, 1):
        ball("Eye", (s * 0.33, -0.665, 1.95), (0.16, 0.075, 0.2), rot=(0, 0, s * -0.38), detail=20)
        ball("Shine", (s * 0.33 - 0.05, -0.735, 2.03), (0.06, 0.025, 0.065), rot=(0, 0, s * -0.38), detail=14)
        ball("Shine", (s * 0.33 + 0.05, -0.73, 1.88), (0.028, 0.015, 0.03), rot=(0, 0, s * -0.38), detail=10)
        # rosy cheeks
        ball("Blush", (s * 0.52, -0.55, 1.66), (0.13, 0.035, 0.08), rot=(0, 0, s * -0.65), detail=12)
        # soft floppy ears hanging close to the head
        ball("FurDark", (s * 0.8, 0.02, 1.66), (0.14, 0.3, 0.5), rot=(-0.15, s * 0.22, 0), detail=24)

        # front legs with cream paws
        ball("Fur", (s * 0.34, -0.3, 0.34), (0.15, 0.15, 0.34), detail=16)
        ball("Cream", (s * 0.34, -0.42, 0.08), (0.17, 0.21, 0.1), detail=16)
        # back thighs and paws
        ball("Fur", (s * 0.5, 0.2, 0.32), (0.24, 0.36, 0.3), detail=24)
        ball("Cream", (s * 0.52, -0.08, 0.07), (0.15, 0.2, 0.08), detail=16)

        # little feather wings on the back, three feathers each
        for i, (length, ang) in enumerate(((0.62, 0.5), (0.54, 0.9), (0.44, 1.3), (0.34, 1.7))):
            ax, az = math.sin(ang), math.cos(ang)
            loc = (s * (0.3 + ax * length * 0.85), 0.66 + 0.035 * i, 1.22 + az * length * 0.85)
            ball("Wing", loc, (0.12, 0.05, length), rot=(-0.25, s * ang, 0), detail=16)

    # a happy tail curled up over the back, with a cream tip
    tube("Fur", [(0, 0.66, 0.5), (0, 0.98, 0.72), (0, 1.04, 1.06), (0, 0.86, 1.3)], 0.11, tip=0.75, name="Tail")
    ball("Cream", (0, 0.82, 1.32), (0.1, 0.1, 0.1), detail=14)


# ---------------------------------------------------------------- join, slim, bake, export
def select_only(objs, active):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = active


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def join_all(col):
    meshes = [ob for ob in col.objects if ob.type == "MESH"]
    select_only(meshes, meshes[0])
    bpy.ops.object.join()
    pup = bpy.context.active_object
    pup.name = NAME
    pup.data.name = NAME
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return pup


def slim(pup):
    tris = tri_count(pup)
    if tris > TRI_TARGET:
        mod = pup.modifiers.new("Slim", "DECIMATE")
        mod.ratio = TRI_TARGET / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    print("[PebblePup] triangles:", tris, "->", tri_count(pup))


def bake(pup, folder):
    select_only([pup], pup)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")

    img_name = NAME + "_color"
    old = bpy.data.images.get(img_name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(img_name, TEXTURE_SIZE, TEXTURE_SIZE)
    targets = []
    for mat in pup.data.materials:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        mat.node_tree.nodes.active = node
        targets.append((mat, node))

    scene = bpy.context.scene
    engine = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=8, use_clear=True)
    scene.render.engine = engine

    for mat, node in targets:
        mat.node_tree.nodes.remove(node)
    path = os.path.join(folder, img_name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()

    # one simple material with the baked texture: what Roblox imports
    baked = bpy.data.materials.get(NAME + "_Baked") or bpy.data.materials.new(NAME + "_Baked")
    baked.use_nodes = True
    nodes = baked.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    baked.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    pup.data.materials.clear()
    pup.data.materials.append(baked)
    for poly in pup.data.polygons:
        poly.material_index = 0
    print("[PebblePup] texture saved:", path)


def export(pup, folder):
    select_only([pup], pup)
    path = os.path.join(folder, NAME + ".fbx")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True)
    print("[PebblePup] FBX saved:", path)


def main():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    folder = out_folder()
    col = fresh_collection()
    build()
    pup = join_all(col)
    slim(pup)
    if BAKE_TEXTURE:
        bake(pup, folder)
    if EXPORT_FBX:
        export(pup, folder)
    select_only([pup], pup)
    print("[PebblePup] done! Files are in", folder)


main()
