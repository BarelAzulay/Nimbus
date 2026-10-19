"""Nimbus Climb skybox (Phase 5, ARCHITECTURE_V3.md "Phase 5 build contract" 6.5; the look of the player's image 23.png):
soft pink / purple / blue clouds with small stars.

ONE Cycles WORLD shader (no geometry) that is a function of the view direction only, rendered by a 90-degree camera into
the six cube faces, so the four side faces always meet without a seam:
  * sky colour: a ramp by elevation (light blue below -> pink haze at the horizon -> lavender -> violet -> deep blue zenith)
  * clouds: fBm noise on the view direction squashed x1.8 (wider than tall) + one larger octave (rounder heaps), in a band
    of -32..+32 degrees, lit from above (the noise sampled a little lower), pinker toward +X (the sun side)
  * stars: 3D Voronoi cells, 14% of them lit, only above 10 degrees and never in front of a cloud
Up / Dn carry no clouds and no azimuth tint (only the elevation ramp + tiny stars), so their rotation convention can
never show a seam in Roblox.

Usage (the owner never needs this: the six PNGs are committed in branding/sky/):
    /tmp/claude-0/bpyenv/bin/python blender/sky/render_sky.py [OUTDIR] [RES] [SAMPLES] [PREVIEW]
    defaults: OUTDIR = branding/sky, RES = 1024, SAMPLES = 24, PREVIEW = blender/sky/preview_cross.png
Writes SkyboxBk / Dn / Ft / Lf / Rt / Up.png (RES x RES) + a preview cross (Up on top, Lf Ft Rt Bk, Dn below) and prints the
seam score (mean RGB difference across the 4 vertical side edges vs. two neighbouring inner columns).
Convention (Roblox, Y up): Ft looks -Z, Bk +Z, Rt +X, Lf -X, Up +Y, Dn -Y. In Studio, if left and right look swapped,
swap the Lf and Rt ids in Config.Sky.Faces (nothing else).
Plain Python 3 + bpy (tested with bpy 5.2) + numpy (ships with bpy).
"""
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
argv = sys.argv[1:]
OUT = argv[0] if len(argv) > 0 else os.path.join(ROOT, "branding", "sky")
RES = int(argv[1]) if len(argv) > 1 else 1024
SAMPLES = int(argv[2]) if len(argv) > 2 else 24
PREVIEW = argv[3] if len(argv) > 3 else os.path.join(HERE, "preview_cross.png")
os.makedirs(OUT, exist_ok=True)

# ---- the look in one place (sRGB 0..255; positions on the ramp: 0 = straight down, 0.5 = horizon, 1 = zenith) ------
SKY_STOPS = [
    (0.00, (164, 176, 240)),  # nadir: soft periwinkle (seen below the sky islands)
    (0.30, (142, 200, 250)),  # light sky blue under the cloud sea (23.png bottom)
    (0.46, (190, 210, 252)),  # pale haze
    (0.50, (226, 206, 246)),  # a soft lavender-white horizon
    (0.56, (176, 156, 236)),  # lavender
    (0.66, (118, 108, 222)),  # violet-blue
    (0.80, (80, 82, 204)),    # blue-violet (23.png top)
    (1.00, (54, 60, 172)),    # deep blue zenith
]
CLOUD_SHADE = [
    (0.00, (170, 128, 222)),  # shaded undersides: soft violet (never a dark bruise)
    (0.30, (222, 148, 226)),  # body: pink
    (0.60, (248, 192, 236)),  # light pink
    (0.90, (255, 238, 250)),  # sunlit tops: pale pink-white
]
CLOUD_SCALE = 1.25        # the fBm (detail) octave
CLOUD_BIG_SCALE = 0.9    # the larger octave: rounder, bigger heaps
CLOUD_BIG_WEIGHT = 0.6   # its share of the density
CLOUD_SQUASH = 1.8        # clouds are wider than tall
CLOUD_THRESHOLD = 0.465    # higher = fewer clouds
CLOUD_LOW_BONUS = 0.05    # more cover toward the horizon
CLOUD_SOFTNESS = 10.0      # edge sharpness of the puffs
BAND = math.radians(32)   # clouds only between -32 and +32 degrees
STAR_SCALE_PER_PX = 0.11  # Voronoi cells per pixel of face width (small stars at every resolution)
STAR_FRACTION = 0.14      # share of the cells that hold a star
STAR_MIN_ELEVATION = math.radians(10)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = False
scene.cycles.seed = 7  # deterministic renders
scene.render.resolution_x = RES
scene.render.resolution_y = RES
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGB"
scene.render.image_settings.compression = 90

world = bpy.data.worlds.new("NimbusSky")
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
nt = world.node_tree
N, L = nt.nodes, nt.links
for n in list(N):
    N.remove(n)


def node(kind, **props):
    n = N.new(kind)
    for k, v in props.items():
        setattr(n, k, v)
    return n


def op(operation, a=None, b=None):
    n = node("ShaderNodeMath", operation=operation)
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            L.new(v, n.inputs[i])
    return n.outputs[0]


def srgb(r, g, b):
    def lin(c):
        c = c / 255.0
        return ((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92
    return (lin(r), lin(g), lin(b), 1.0)


def ramp(value_socket, stops):
    n = node("ShaderNodeValToRGB")
    L.new(value_socket, n.inputs[0])
    els = n.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], srgb(*stops[0][1])
    els[1].position, els[1].color = stops[-1][0], srgb(*stops[-1][1])
    for pos, c in stops[1:-1]:
        e = els.new(pos)
        e.color = srgb(*c)
    return n.outputs["Color"]


def smooth(value_socket, a, b):
    """0 at a, 1 at b (a > b allowed: falls), smoothstep."""
    n = node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
    L.new(value_socket, n.inputs["Value"])
    n.inputs["From Min"].default_value = a
    n.inputs["From Max"].default_value = b
    return n.outputs["Result"]


def remap(value_socket, a, b):
    n = node("ShaderNodeMapRange")
    L.new(value_socket, n.inputs["Value"])
    n.inputs["From Min"].default_value = a
    n.inputs["From Max"].default_value = b
    return n.outputs["Result"]


def noise(vec_socket, scale, detail, rough, offset=(0.0, 0.0, 0.0)):
    mp = node("ShaderNodeMapping")
    L.new(vec_socket, mp.inputs["Vector"])
    mp.inputs["Location"].default_value = offset
    nz = node("ShaderNodeTexNoise", noise_dimensions="3D")
    L.new(mp.outputs[0], nz.inputs["Vector"])
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    nz.inputs["Roughness"].default_value = rough
    return nz.outputs["Fac"]


def mix(fac, a, b, blend="MIX"):
    n = node("ShaderNodeMix", data_type="RGBA", blend_type=blend)
    if isinstance(fac, (int, float)):
        n.inputs[0].default_value = fac
    else:
        L.new(fac, n.inputs[0])
    for idx, v in ((6, a), (7, b)):
        if isinstance(v, tuple):
            n.inputs[idx].default_value = v
        else:
            L.new(v, n.inputs[idx])
    return n.outputs[2]


# the view direction (Blender world: Z up). Normalised so the elevation is exact on every face.
coord = node("ShaderNodeTexCoord")
nrm = node("ShaderNodeVectorMath", operation="NORMALIZE")
L.new(coord.outputs["Generated"], nrm.inputs[0])
D = nrm.outputs[0]
sep = node("ShaderNodeSeparateXYZ")
L.new(D, sep.inputs[0])
X, Z = sep.outputs[0], sep.outputs[2]

# ---- sky gradient by elevation -------------------------------------------------------------------------------------
height01 = remap(Z, -1.0, 1.0)
SKY = ramp(height01, SKY_STOPS)

# ---- clouds ----------------------------------------------------------------------------------------------------------
squash = node("ShaderNodeMapping")
L.new(D, squash.inputs["Vector"])
squash.inputs["Scale"].default_value = (1.0, 1.0, CLOUD_SQUASH)
V = squash.outputs[0]
fine = noise(V, CLOUD_SCALE, 4, 0.45)
fine_up = noise(V, CLOUD_SCALE, 4, 0.45, offset=(0.0, 0.0, 0.09))   # sampled toward the light: the puffs are lit from above
big = noise(V, CLOUD_BIG_SCALE, 1, 0.5, offset=(3.1, 1.7, 0.0))      # the one larger octave (rounder heaps)
base = op("ADD", op("MULTIPLY", fine, 1.0 - CLOUD_BIG_WEIGHT), op("MULTIPLY", big, CLOUD_BIG_WEIGHT))
sinBand = math.sin(BAND)
low = smooth(op("ABSOLUTE", Z), sinBand * 0.85, 0.0)  # 1 at the horizon, 0 near the band edge
cover = op("MULTIPLY", low, CLOUD_LOW_BONUS)
dens = op("MULTIPLY", op("SUBTRACT", base, op("SUBTRACT", CLOUD_THRESHOLD, cover)), CLOUD_SOFTNESS)
dens = op("MINIMUM", op("MAXIMUM", dens, 0.0), 1.0)
# the band: nothing above / below 32 degrees, so the Up / Dn faces stay cloud-free (rotation-proof)
top = smooth(Z, sinBand, sinBand * 0.72)
bot = smooth(Z, -sinBand, -sinBand * 0.55)
dens = op("MULTIPLY", op("MULTIPLY", dens, top), bot)
# lighting: >0 where a puff's top faces the light; thicker cloud slightly darker
shade = op("SUBTRACT", fine, fine_up)
shade = op("ADD", op("MULTIPLY", shade, 7.0), 0.52)
shade = op("ADD", shade, op("MULTIPLY", op("SUBTRACT", base, CLOUD_THRESHOLD + 0.1), -0.6))
shade = op("MINIMUM", op("MAXIMUM", shade, 0.0), 1.0)
CLOUD = ramp(shade, CLOUD_SHADE)
# cooler (violet-blue) high up, warmer (pink-white) low: a multiply tint by elevation
CLOUD = mix(1.0, CLOUD, ramp(height01, [(0.42, (255, 240, 248)), (0.56, (250, 232, 255)), (0.66, (200, 186, 255))]), "MULTIPLY")
# pinker toward +X (the sun side), a touch bluer on the far side
CLOUD = mix(1.0, CLOUD, ramp(remap(X, -1.0, 1.0), [(0.0, (214, 204, 255)), (1.0, (255, 244, 250))]), "MULTIPLY")
COL = mix(dens, SKY, CLOUD)

# ---- stars -------------------------------------------------------------------------------------------------------------
vor = node("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature="F1")
L.new(D, vor.inputs["Vector"])
vor.inputs["Scale"].default_value = max(60.0, RES * STAR_SCALE_PER_PX)
cell = node("ShaderNodeSeparateColor")
L.new(vor.outputs["Color"], cell.inputs[0])
pick = op("GREATER_THAN", cell.outputs[0], 1.0 - STAR_FRACTION)
core = smooth(vor.outputs["Distance"], 0.16, 0.04)
star = op("MULTIPLY", core, pick)
star = op("MULTIPLY", star, smooth(Z, math.sin(STAR_MIN_ELEVATION), math.sin(STAR_MIN_ELEVATION) + 0.3))
star = op("MULTIPLY", star, op("SUBTRACT", 1.0, dens))
star = op("MULTIPLY", star, op("ADD", op("MULTIPLY", cell.outputs[1], 0.8), 0.4))  # each star its own brightness
COL = mix(star, COL, (1.0, 0.97, 1.0, 1.0), "ADD")

bg = node("ShaderNodeBackground")
L.new(COL, bg.inputs["Color"])
bg.inputs["Strength"].default_value = 1.0
out_node = node("ShaderNodeOutputWorld")
L.new(bg.outputs[0], out_node.inputs["Surface"])

# ---- a 90-degree square camera at the origin, one render per face ---------------------------------------------------------
cam_data = bpy.data.cameras.new("Cam")
cam_data.sensor_fit = "HORIZONTAL"
cam_data.angle = math.radians(90)
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
# Roblox (Y up, -Z forward) -> Blender (Z up): Roblox -Z (Ft) = Blender +Y, Roblox +X (Rt) = Blender +X, Roblox +Y = Blender +Z.
# A Blender camera looks down its local -Z; rotation (90, 0, yaw) looks horizontally.
r = math.radians
FACES = [
    ("Ft", (r(90), 0, r(0))),     # looks +Y (Roblox -Z)
    ("Rt", (r(90), 0, r(-90))),   # looks +X (Roblox +X)
    ("Bk", (r(90), 0, r(180))),   # looks -Y (Roblox +Z)
    ("Lf", (r(90), 0, r(90))),    # looks -X (Roblox -X)
    ("Up", (r(180), 0, r(0))),    # looks +Z, image top toward -Y (Roblox +Z)
    ("Dn", (0, 0, r(0))),         # looks -Z, image top toward +Y (Roblox -Z)
]
pixels = {}
for name, rot in FACES:
    cam.rotation_euler = rot
    path = os.path.join(OUT, "Skybox%s.png" % name)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(RES, RES, img.channels)[::-1, :, :3]  # top row first
    pixels[name] = arr * 255.0
    bpy.data.images.remove(img)

# ---- seam score + preview cross ------------------------------------------------------------------------------------------------
order = ["Ft", "Rt", "Bk", "Lf"]  # turning right (clockwise seen from above)
seams = []
for i in range(4):
    a, b = pixels[order[i]][:, -1], pixels[order[(i + 1) % 4]][:, 0]
    seams.append(float(np.abs(a - b).mean()))
inner = float(np.abs(pixels["Ft"][:, RES // 2] - pixels["Ft"][:, RES // 2 + 1]).mean())
print("SEAMS side edges Ft|Rt Rt|Bk Bk|Lf Lf|Ft: %s  inner column: %.2f" % (" ".join("%.2f" % s for s in seams), inner))

cross = np.full((3 * RES, 4 * RES, 3), 235.0, dtype=np.float32)
cross[0:RES, RES:2 * RES] = pixels["Up"]
cross[2 * RES:3 * RES, RES:2 * RES] = pixels["Dn"]
for i, k in enumerate(("Lf", "Ft", "Rt", "Bk")):
    cross[RES:2 * RES, i * RES:(i + 1) * RES] = pixels[k]
step = max(1, RES // 256)  # the preview stays small (256 px per face)
small = cross[::step, ::step]
h, w = small.shape[0], small.shape[1]
pv = bpy.data.images.new("preview", width=w, height=h, alpha=False)
rgba = np.ones((h, w, 4), dtype=np.float32)
rgba[:, :, :3] = small[::-1] / 255.0
pv.pixels[:] = rgba.ravel()
pv.filepath_raw = PREVIEW
pv.file_format = "PNG"
pv.save()
print("done", OUT, PREVIEW)
