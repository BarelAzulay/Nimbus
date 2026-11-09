"""The strip cards' egg pictures (egg-cards, spec docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.18 "Egg cards +
x3 3D"; the owner's pick 2026-11-09: "card eggs = pictures of the real Blender eggs").

    %USERPROFILE%/.bpyenv/Scripts/python.exe blender/textures/build_egg_cards.py [--key egg_card_epic] [--sheet x.png]
    ... build_egg_cards.py --sheet-only --sheet x.png      (the contact sheet of the PNGs already built: no render)
    (PYTHONHASHSEED=0, as build_all.py runs its builds: the contentHash check against the committed manifests)

Every picture is a Cycles render of the shelf egg itself: the lobby catalog's key egg_<rarity> (prop lobby_egg,
blender/kit/props/lobby_shop.py) built here by blender/build_all.py's own Builder (nothing is written to meshes.json or
src/shared/MeshManifests), and its contentHash must equal the committed manifest's ContentHash
(src/shared/MeshManifests/egg_<rarity>.lua): the exact geometry and vertex colours of the uploaded egg meshes.

The view is client/UI/Egg3D's camera at the cutscene's rise: FieldOfView 20 (vertical), 8 degrees above, the egg turned
-28 degrees about its upright axis (EggStage K.EGG3D.Turn), seen from the front (-Z in Roblox, -Y in Blender).  The
camera is pulled back until the egg's projected box is FILL (0.9, HatchLook.Metrics.EGG_PIC.Fill) of the picture's
height and shifted so that box is centred: the game draws the picture as a square of (egg px) / FILL centred on the
painted egg's box.  Light: a soft key (a sun with a wide 25-degree disc) from Egg3D's DIR (upper left, in front) over
a world fill; no ground, no shadow catcher: a transparent 512 x 512 RGBA PNG.  Fully clear pixels carry the card face's
navy as RGB, so a scaled ImageLabel never shows a light fringe.  Fixed Cycles seed and sample count.

(review round 1) The light per rarity is Egg3D's own: K.LIGHT is read from src/client/UI/Egg3D.lua (Ambient -> the world
fill's colour, LightColor -> the key's colour, both sRGB -> linear), so the picture and the ViewportFrame egg it lifts into
at the rise share each rarity's tint and its level against the others (Legendary warm gold, Secret a dimmer violet night)
by construction.  The overall level and the key / fill split stay the first build's (scaled so the Common egg's fill and
key keep that build's luminance: WORLD_LUM, KEY_ENERGY); how close they come to a Roblox ViewportFrame's Ambient +
LightColor x LIGHT_AMOUNT is a Studio check (BUILD_STATE), and these two numbers are the knobs if it is off.

Outputs: blender/textures/eggs/egg_card_<rarity>.png and the keys egg_card_<rarity> merged into the uploader index
blender/textures/textures.json (other keys stay as they are; png, displayName, description, contentHash = the PNG's
sha256, structureHash = size + pixel format, as build_store.py writes them).  Nothing is uploaded here:
tools/upload_assets.py --textures does that in the owner's keyed session and writes TextureIds.lua.
"""
import hashlib
import json
import math
import os
import re
import struct
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.dirname(HERE)
REPO = os.path.dirname(BLENDER_DIR)
KIT = os.path.join(BLENDER_DIR, "kit")
for p in (KIT, BLENDER_DIR, os.path.join(REPO, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)
sys.dont_write_bytecode = True

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

from nvox import blend as B  # noqa: E402

OUT = os.path.join(HERE, "eggs")
INDEX = os.path.join(HERE, "textures.json")
MANIFESTS = os.path.join(REPO, "src", "shared", "MeshManifests")
RARITIES = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
SEED = 20261109
RES = 512
SAMPLES = 128
FILL = 0.9                      # HatchLook.Metrics.EGG_PIC.Fill: the egg's projected height share of the picture
FOV = 20.0                      # Egg3D K.FOV (vertical, degrees)
PITCH = 8.0                     # Egg3D K.PITCH (degrees above)
TURN = -28.0                    # EggStage K.EGG3D.Turn (degrees about the egg's upright axis)
LIGHT_DIR = (-0.55, -1.0, 0.7)  # Egg3D K.DIR (Roblox: the direction the light travels)
CLEAR_RGB = (17, 25, 68)        # the card face's foot (HatchLook card face 37,51,122 -> 17,25,68)
EGG3D = os.path.join(REPO, "src", "client", "UI", "Egg3D.lua")
WORLD_LUM = 0.7 * (0.2126 * 0.93 + 0.7152 * 0.95 + 0.0722 * 1.0)  # the first build's fill (0.93, 0.95, 1) x 0.7, as luminance
KEY_ENERGY = 2.1                # the first build's white key (sun energy), given to Common's LightColor luminance


def srgb_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def egg3d_light():
    """Egg3D's K.LIGHT read from the Lua: {rarity: ((Ambient rgb), (LightColor rgb))}, so the two rigs cannot drift"""
    with open(EGG3D, encoding="utf-8") as fh:
        src = fh.read()
    rows = re.findall(r"(\w+)\s*=\s*\{\s*rgb\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\),\s*rgb\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\)\s*\}", src)
    out = {r[0]: (tuple(int(v) for v in r[1:4]), tuple(int(v) for v in r[4:7])) for r in rows}
    missing = [r for r in RARITIES if r not in out]
    if missing:
        raise SystemExit("Egg3D.lua K.LIGHT: no row for %s" % ", ".join(missing))
    return out


def rig(rarity):
    """the world fill (linear rgb) and the key (linear rgb, energy) of this rarity: Egg3D's Ambient and LightColor, scaled
    so Common keeps the first build's fill luminance (WORLD_LUM) and key energy (KEY_ENERGY)"""
    light = egg3d_light()
    amb_c = [srgb_lin(v) for v in light["Common"][0]]
    key_c = [srgb_lin(v) for v in light["Common"][1]]
    amb = [srgb_lin(v) for v in light[rarity][0]]
    key = [srgb_lin(v) for v in light[rarity][1]]
    k = WORLD_LUM / luminance(amb_c)
    return [v * k for v in amb], key, KEY_ENERGY / luminance(key_c)


def key_of(rarity):
    return "egg_card_" + rarity.lower()


def manifest_hash(mesh_key):
    with open(os.path.join(MANIFESTS, mesh_key + ".lua"), encoding="utf-8") as fh:
        m = re.search(r'ContentHash\s*=\s*"([0-9a-f]+)"', fh.read())
    return m.group(1) if m else None


def build_egg(rarity):
    """the lobby catalog's egg_<rarity>, built by build_all's Builder (no index / manifest written) -> ModelSpec"""
    import build_all
    from nvox.manifest import hashes
    mesh_key = "egg_" + rarity.lower()
    cats = build_all.load_catalogs()
    cat = cats["lobby"]
    entry = next(k for k in cat["keys"] if k["key"] == mesh_key)
    entry = dict(entry, _class="lobby")
    m = build_all.Builder(export=False, verbose=False).build(entry, build_all.resolve_budget(cat, entry))
    got, want = hashes(m)[0], manifest_hash(mesh_key)
    if got != want:
        raise SystemExit("%s: built contentHash %s != the committed manifest's %s (not the uploaded egg)" % (mesh_key, got, want))
    return m, got


def scene(rarity):
    sc = B.reset_scene()
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.seed = SEED
    try:
        sc.cycles.use_denoising = True
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        sc.cycles.use_denoising = False
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    fill, key, energy = rig(rarity)
    world = bpy.data.worlds.new("W")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (fill[0], fill[1], fill[2], 1)
    bg.inputs["Strength"].default_value = 1.0
    # the soft key: a sun with a wide disc from Egg3D's DIR (Roblox -> Blender: (-x, z, y)) in this rarity's LightColor
    sun = bpy.data.lights.new("Key", "SUN")
    sun.color = (key[0], key[1], key[2])
    sun.energy = energy
    sun.angle = math.radians(25)
    so = bpy.data.objects.new("Key", sun)
    sc.collection.objects.link(so)
    travel = Vector(B.to_bl(LIGHT_DIR).tolist()).normalized()
    so.rotation_euler = travel.to_track_quat("-Z", "Y").to_euler()
    return sc


def frame_camera(sc, objs):
    """Egg3D's camera direction; distance and lens shift so the projected box is FILL of the height, centred"""
    from bpy_extras.object_utils import world_to_camera_view
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "PERSP"
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(FOV)
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    look = Vector((0.0, 0.0, 1.5))  # the egg's middle (Roblox (0, 1.5, 0))
    p = math.radians(PITCH)
    pts = [ob.matrix_world @ v.co for ob in objs for v in ob.data.vertices]
    d = 1.5 / math.tan(math.radians(FOV) / 2)
    for _ in range(4):
        cam.location = look + Vector((0.0, -math.cos(p) * d, math.sin(p) * d))
        cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam_data.shift_x = cam_data.shift_y = 0.0
        bpy.context.view_layer.update()
        ys = [world_to_camera_view(sc, cam, q).y for q in pts]
        h = max(ys) - min(ys)
        d *= h / FILL
    cam.location = look + Vector((0.0, -math.cos(p) * d, math.sin(p) * d))
    cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    ndc = [world_to_camera_view(sc, cam, q) for q in pts]
    xs, ys = [q.x for q in ndc], [q.y for q in ndc]
    cam_data.shift_x = ((max(xs) + min(xs)) / 2 - 0.5)
    cam_data.shift_y = ((max(ys) + min(ys)) / 2 - 0.5)
    bpy.context.view_layer.update()
    ndc = [world_to_camera_view(sc, cam, q) for q in pts]
    xs, ys = [q.x for q in ndc], [q.y for q in ndc]
    return {"x": (min(xs), max(xs)), "y": (min(ys), max(ys)), "dist": d}


def write_png(path, rgba):
    h, w, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def render(rarity):
    t0 = time.time()
    m, chash = build_egg(rarity)
    sc = scene(rarity)
    objs = B.make_objects(m, None)
    for ob in objs:
        ob.rotation_euler = (0.0, 0.0, math.radians(TURN))  # Roblox Ry(t) = Blender Rz(t) about the pivot (bottom centre)
    bpy.context.view_layer.update()
    box = frame_camera(sc, objs)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, key_of(rarity) + ".png")
    tmp = path + ".tmp.png"
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    from PIL import Image
    im = Image.open(tmp).convert("RGBA")
    a8 = np.array(im, dtype=np.uint8)
    im.close()
    os.remove(tmp)
    clear = a8[..., 3] == 0
    a8[clear, 0], a8[clear, 1], a8[clear, 2] = CLEAR_RGB
    write_png(path, np.ascontiguousarray(a8))
    # the drawn box in the PNG (alpha > 8): the game's placement assumes FILL of the height, centred
    ys, xs = np.nonzero(a8[..., 3] > 8)
    drawn = {"top": int(ys.min()), "bottom": int(ys.max()), "left": int(xs.min()), "right": int(xs.max())}
    print("EGGCARD %-18s %5.1fs  hash %s  ndc y %.3f..%.3f x %.3f..%.3f  png rows %d..%d cols %d..%d" % (
        key_of(rarity), time.time() - t0, chash, box["y"][0], box["y"][1], box["x"][0], box["x"][1],
        drawn["top"], drawn["bottom"], drawn["left"], drawn["right"]))
    return path


def image_structure(path):
    with open(path, "rb") as f:
        head = f.read(33)
    w, h = struct.unpack(">II", head[16:24])
    return hashlib.sha256(("png %dx%d %s" % (w, h, "RGBA")).encode("utf-8")).hexdigest()[:32]


def write_index(paths):
    with open(INDEX, "rb") as f:
        index = json.loads(f.read().decode("utf-8"))
    for key in sorted(paths):
        rarity = key[len("egg_card_"):].capitalize()
        with open(paths[key], "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        index["keys"][key] = {
            "png": os.path.relpath(paths[key], REPO).replace(os.sep, "/"),
            "displayName": "NC " + key.replace("_", " "),
            "description": "Nimbus Climb egg card picture: the %s egg (egg_%s, the shelf / hatch mesh) at the hatch "
                           "camera's three-quarter view, transparent" % (rarity, rarity.lower()),
            "contentHash": digest,
            "structureHash": image_structure(paths[key]),
            "build": "blender/textures/build_egg_cards.py (Blender 5.2 headless, Cycles seed %d)" % SEED,
        }
    with open(INDEX, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(index, indent=2, sort_keys=True) + "\n")


def sheet(paths, out):
    """the seven pictures on the card face (navy 37,51,122 -> 17,25,68) at full size and at the strip's sizes: PC x1
    160 px, PC x3 130, phone x1 104, phone x3 48 (the painted egg's height there; the picture is that / FILL)"""
    from PIL import Image, ImageDraw
    keys = [key_of(r) for r in RARITIES if key_of(r) in paths]
    cw, chh = 300, 560
    im = Image.new("RGB", (cw * len(keys), chh), (8, 12, 32))
    d = ImageDraw.Draw(im)
    for i, k in enumerate(keys):
        x0 = i * cw
        face = Image.new("RGB", (cw - 12, chh - 12))
        fd = ImageDraw.Draw(face)
        for yy in range(chh - 12):
            t = yy / (chh - 12)
            fd.line([(0, yy), (cw - 12, yy)], fill=(int(37 - 20 * t), int(51 - 26 * t), int(122 - 54 * t)))
        art = Image.open(paths[k]).convert("RGBA")
        big = art.resize((276, 276), Image.LANCZOS)
        face.paste(big, (0, 18), big)
        # the strip's sizes side by side: 160 (PC x1) on the left, 104 (phone x1) and 48 (phone x3) on the right
        for egg_px, at in ((160, (4, 300)), (104, (180, 300)), (48, (208, 430))):
            s = int(round(egg_px / FILL))
            small = art.resize((s, s), Image.LANCZOS)
            face.paste(small, at, small)
        im.paste(face, (x0 + 6, 6))
        d.text((x0 + 12, 8), k, fill=(255, 255, 255))
    im.save(out)


def main():
    argv = sys.argv[1:]
    keys, sheet_out, only_sheet = [], None, False
    i = 0
    while i < len(argv):
        if argv[i] == "--key":
            keys.append(argv[i + 1])
            i += 2
        elif argv[i] == "--sheet":
            sheet_out = argv[i + 1]
            i += 2
        elif argv[i] == "--sheet-only":
            only_sheet = True
            i += 1
        else:
            raise SystemExit("unknown argument %r" % argv[i])
    todo = [r for r in RARITIES if not keys or key_of(r) in keys]
    if keys and len(todo) != len(keys):
        raise SystemExit("unknown key(s) in %s (known: %s)" % (keys, ", ".join(key_of(r) for r in RARITIES)))
    if not only_sheet:
        t0 = time.time()
        paths = {key_of(r): render(r) for r in todo}
        write_index(paths)
        print("EGGCARD rendered %d picture(s) in %.1fs -> %s (+ %s)" % (len(paths), time.time() - t0,
                                                                       os.path.relpath(OUT, REPO), os.path.relpath(INDEX, REPO)))
    if sheet_out:
        allp = {key_of(r): os.path.join(OUT, key_of(r) + ".png") for r in RARITIES
                if os.path.exists(os.path.join(OUT, key_of(r) + ".png"))}
        sheet(allp, sheet_out)
        print("EGGCARD sheet", sheet_out)


if __name__ == "__main__":
    main()
