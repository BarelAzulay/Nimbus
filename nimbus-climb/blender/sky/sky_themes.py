"""Nimbus Climb sky themes: 21 painted skybox options (7 skies x 3 directions) from ONE shared world shader.

Same idea as render_sky.py (which stays the shipped sky): a Cycles WORLD shader with no geometry, a pure function of the
view direction, rendered by a 90-degree camera into the six cube faces (so the side faces always meet without a seam).
Every theme uses the same building blocks, so all 21 read as one family:
  * an elevation ramp from four palette colours (zenith, upper sky, horizon, below the islands), with a wide flat
    horizon plateau so the gameplay band (-10..+15 degrees) stays calm
  * the same fBm cloud language (a detail octave + one big octave, squashed wider than tall, lit from one side,
    optional rims, flat bottoms, facets, erosion), faded and hazed toward the horizon (aerial perspective)
  * Voronoi stars, a sun / moon / black-sun disc with halo, ring and corona
  * one or two signature features per theme (wind streaks, nebula ribbon, aurora, lightning, vortex, embers, lava
    veins, heat haze, light pillars, snow streaks, ice fracture, cosmic rift, nebula dust)

Run headless with Blender (bpy is not importable from plain Python here):
    blender.exe -b --factory-startup --python sky_themes.py -- [--themes all|id,id] [--res 512] [--samples 16]
                [--out DIR] [--skip-faces] [--skip-view] [--skip-pano] [--list]
  Writes DIR/<theme>/SkyboxBk/Dn/Ft/Lf/Rt/Up.png (RES x RES), view.jpg (1280x640, 75 deg FOV, 10 deg above the horizon,
  looking at the sun / feature side), view_up.jpg (same, 45 deg up: zenith features) and pano.jpg (1600x800
  equirectangular), and prints the seam scores.
  Default DIR: <repo>/.superpowers/sky-pitch (git-ignored, big).
Contact sheet (plain Python 3 with Pillow + numpy, no bpy):
    py -3.12 sky_themes.py --contact [--out DIR]     -> DIR/contact.jpg (every view.jpg, 3 columns, labelled)

Convention (Roblox, Y up): Ft looks -Z, Bk +Z, Rt +X, Lf -X, Up +Y, Dn -Y (Blender: Ft +Y, Rt +X, Up +Z).
Up / Dn: the image top of Up points to Roblox +Z (Bk side), the image top of Dn to Roblox -Z (Ft side). Themes with a
zenith or nadir feature (vortex, rift, lava veins, nebula ribbon) put detail on Up / Dn, so check those two faces'
rotation in Studio once (the script also prints an Up / Dn edge score for its own cube).
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))  # .../Nimbus (or the worktree root)


def default_out():
    # outputs live in the main Nimbus folder's .superpowers (not in a worktree), so every session finds them
    p = REPO
    parts = p.replace("\\", "/").split("/")
    if ".worktrees" in parts:
        p = "/".join(parts[:parts.index(".worktrees")])
    return os.path.join(p, ".superpowers", "sky-pitch")


def H(hexs):
    hexs = hexs.lstrip("#")
    return tuple(int(hexs[i:i + 2], 16) for i in (0, 2, 4))


def lerp3(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# ---- the 21 themes ----------------------------------------------------------------------------------------------------
# pal: zenith, upper sky, horizon, below (sRGB hex). clouds: overrides of CLOUD_DEFAULT. cc: cloud shadow, body, lit
# (+ rim). sun: a disc / halo / ring / corona. stars: star layers. fx: signature features. az: the feature side
# (degrees, 0 = Ft, + toward Rt). G = Gemini's favourite of the three.
SOFT_GAIN = 2.0  # all cloud edges: a painted, crisp outline (softness values below are x2)
CLOUD_DEFAULT = dict(
    scale=1.4, big_scale=0.9, big_weight=0.65, detail=7, rough=0.58, squash=1.8, threshold=0.49, softness=6.0,
    opacity=1.0, light=1.0, contrast=4.0, distortion=0.0, shear=0.0,
    layers=[(-38.0, 34.0, 12.0, 12.0)],  # (bottom deg, top deg, bottom fade, top fade)
    rim=0.0, rim_focus=6.0, rim_base=0.3, rim_width=0.05, facet=0.0, erode=0.0, flash=0.0,
    calm=0.3, haze=0.35,  # opacity cut and fade-to-sky inside the horizon band
)

THEMES = [
    # 1 DAY --------------------------------------------------------------------------------------------------------------
    dict(id="day_azure", name="Classic Azure", group="Day", pal=("#1A5276", "#2980B9", "#85C1E9", "#EBF5FB"),
         clouds=dict(threshold=0.47, softness=9.0, big_weight=0.7, rough=0.62, detail=8),
         cc=((150, 182, 214), (214, 230, 245), (255, 255, 255)),
         sun=dict(el=26, r=2.2, edge=1.2, disc=(255, 253, 240), disc_op=0.75, halo=(255, 255, 255), halo_size=42,
                  halo_op=0.33, halo_pow=2.2)),
    dict(id="day_breezy", name="Nimbus Breezy", group="Day", pal=("#3B82F6", "#60A5FA", "#93C5FD", "#EFF6FF"),
         clouds=dict(squash=2.6, threshold=0.5, softness=7.0, big_weight=0.8,
                     layers=[(15.0, 24.0, 1.6, 6.0), (24.0, 33.0, 1.6, 5.0), (-12.0, -3.0, 1.6, 5.0),
                             (-34.0, -15.0, 1.8, 6.0)]),
         cc=((176, 200, 236), (226, 236, 252), (255, 255, 255)),
         sun=dict(el=30, r=2.0, edge=1.0, disc=(255, 255, 245), disc_op=0.7, halo=(255, 255, 255), halo_size=30,
                  halo_op=0.25, halo_pow=2.5),
         fx=[dict(kind="wind_streaks", col=(255, 255, 255), op=0.16)]),
    dict(id="day_vivid", name="Vivid Skylands", group="Day", G=True, pal=("#0284C7", "#38BDF8", "#7DD3FC", "#E0F2FE"),
         clouds=dict(softness=40.0, threshold=0.46, contrast=7.0, detail=4),
         cc=((150, 204, 242), (222, 242, 255), (255, 255, 255)),
         sun=dict(el=21, r=5.5, edge=0.35, disc=(255, 251, 222), disc_op=1.0, halo=(255, 248, 210), halo_size=24,
                  halo_op=0.5, halo_pow=2.0, ring=9.5, ring_w=0.45, ring_op=0.7, ring_col=(255, 255, 240))),
    # 2 DAWN / SUNSET ----------------------------------------------------------------------------------------------------
    # copper: the owner's earlier pick; softened from the raw #9A3412/#D97706 into a warm copper-peach
    dict(id="dusk_copper", name="Copper Glow", group="Dawn / Sunset", pal=("#7C3A2E", "#C77B4E", "#F5C08C", "#FDEBD3"),
         clouds=dict(threshold=0.43, softness=8.0, detail=6, rough=0.55, rim=0.75, rim_focus=3.0, rim_base=0.25,
                     contrast=5.5, rim_width=0.025, calm=0.05, haze=0.05, big_weight=0.7, sun_clear=14.0,
                     layers=[(-28.0, 30.0, 8.0, 8.0)]),
         cc=((122, 60, 84), (180, 102, 112), (240, 170, 140), (255, 210, 140)),
         sun=dict(el=3, r=2.6, edge=1.6, disc=(255, 240, 205), disc_op=0.85, halo=(255, 196, 130), halo_size=26,
                  halo_op=0.26, halo_pow=2.2, bleed=0.2, bleed_col=(255, 186, 120))),
    dict(id="dusk_candy", name="Cotton Candy Dusk", group="Dawn / Sunset", G=True,
         pal=("#6B21A8", "#C026D3", "#F472B6", "#FFE4E6"),
         clouds=dict(threshold=0.43, softness=7.0, big_weight=0.75, contrast=4.0, calm=0.05, haze=0.1,
                     layers=[(-26.0, 30.0, 8.0, 8.0)]),
         cc=((150, 90, 190), (250, 186, 224), (255, 242, 250)),
         sun=dict(el=8, r=0.0, halo=(255, 214, 230), halo_size=40, halo_op=0.3, halo_pow=2.0),
         stars=[dict(scale=1.0, frac=0.08, size=0.10, bright=0.6, min_el=40)],
         fx=[dict(kind="ribbon", tilt=18.0, width=0.07, col=(240, 140, 250), core=(255, 220, 255), op=0.75,
                  min_el=2)]),
    dict(id="dusk_amber", name="Amber Burn", group="Dawn / Sunset", pal=("#7F1D1D", "#EA580C", "#F97316", "#FFEDD5"),
         clouds=dict(threshold=0.44, softness=9.0, rim=1.0, rim_focus=4.0, rim_base=0.15, contrast=2.0),
         cc=((96, 32, 30), (138, 50, 36), (178, 74, 40), (255, 214, 140)),
         sun=dict(el=4.5, r=3.2, edge=0.6, disc=(255, 238, 200), disc_op=1.0, halo=(255, 170, 80), halo_size=30,
                  halo_op=0.55, halo_pow=2.4, rays=0.35, rays_size=26, rays_col=(255, 190, 110))),
    # 3 NIGHT (properly dark: game readability comes from the world Lighting, not the sky picture) --------------------
    dict(id="night_violet", name="Midnight Violet", group="Night", pal=("#0A1236", "#141C52", "#2E3A82", "#0E1230"),
         clouds=dict(threshold=0.47, softness=4.0, opacity=1.0, detail=8, rough=0.62, squash=2.6, calm=0.1, haze=0.15,
                     layers=[(-30.0, 32.0, 10.0, 10.0)]),
         cc=((22, 22, 62), (52, 50, 112), (110, 104, 180)),
         stars=[dict(scale=1.2, frac=0.22, size=0.10, bright=0.8, min_el=4),
                dict(scale=0.45, frac=0.07, size=0.15, bright=1.0, min_el=8, col=(225, 230, 255)),
                dict(scale=0.18, frac=0.04, size=0.13, bright=1.0, min_el=12, col=(255, 245, 230))]),
    dict(id="night_aurora", name="Aurora Slumber", group="Night", G=True, pal=("#070C24", "#0E1A44", "#164C5E", "#0E1230"),
         clouds=dict(threshold=0.55, softness=3.0, opacity=0.4, calm=0.6),
         cc=((12, 24, 48), (22, 42, 70), (40, 72, 100)),
         ramp=[(-90, "below"), (-30, 0.15), (-8, 0.45), (0, "horizon"), (8, 0.35), (24, 0.8), (45, "upper"),
               (90, "zenith")],
         stars=[dict(scale=1.2, frac=0.22, size=0.10, bright=0.8, min_el=4),
                dict(scale=0.45, frac=0.07, size=0.15, bright=1.0, min_el=8, col=(225, 230, 255)),
                dict(scale=0.18, frac=0.04, size=0.13, bright=1.0, min_el=12, col=(255, 245, 230))],
         fx=[dict(kind="fog", col=(60, 170, 170), op=0.14, center=1.0, width=7.0),
             dict(kind="aurora", base=17.0, height=24.0, op=0.85)]),
    dict(id="night_lunar", name="Lunar Cobalt", group="Night", pal=("#0B1640", "#12224E", "#2A4A8A", "#0E1230"),
         clouds=dict(threshold=0.47, softness=9.0, big_weight=0.8, big_scale=0.75, rim=0.9, rim_focus=3.0,
                     rim_base=0.35, contrast=3.0, rim_width=0.025, calm=0.15, haze=0.2),
         cc=((18, 28, 60), (34, 52, 92), (70, 96, 140), (220, 232, 250)),
         sun=dict(el=21, r=4.2, edge=0.25, disc=(250, 252, 255), disc_op=1.0, moon=True, halo=(150, 190, 245),
                  halo_size=22, halo_op=0.45, halo_pow=2.0),
         stars=[dict(scale=1.2, frac=0.22, size=0.10, bright=0.8, min_el=4),
                dict(scale=0.45, frac=0.07, size=0.15, bright=1.0, min_el=8, col=(225, 230, 255)),
                dict(scale=0.18, frac=0.04, size=0.13, bright=1.0, min_el=12, col=(255, 245, 230))]),
    # 4 STORM TITAN raid ---------------------------------------------------------------------------------------------------
    dict(id="storm_teal", name="Thunderhead Teal", group="Storm Titan", pal=("#064E3B", "#0F766E", "#14B8A6", "#06342A"),
         clouds=dict(threshold=0.38, softness=5.0, big_weight=0.75, big_scale=0.7, contrast=3.5, opacity=0.95,
                     layers=[(-40.0, 40.0, 12.0, 12.0)]),
         cc=((12, 46, 46), (26, 86, 86), (74, 144, 138)),
         fx=[dict(kind="lightning", col=(214, 255, 246), glow=(90, 220, 200), op=1.0, min_el=13, max_el=50)]),
    dict(id="storm_indigo", name="Ominous Indigo", group="Storm Titan", G=True,
         pal=("#1E1B4B", "#312E81", "#6366F1", "#120F2E"),
         clouds=dict(threshold=0.42, softness=10.0, distortion=0.6, detail=7, rough=0.6, contrast=5.0, flash=0.85,
                     layers=[(-40.0, 38.0, 12.0, 12.0)]),
         cc=((26, 23, 62), (56, 52, 122), (112, 108, 192), (224, 220, 255))),
    dict(id="storm_slate", name="Tempest Slate", group="Storm Titan", pal=("#334155", "#475569", "#94A3B8", "#0F172A"),
         clouds=dict(threshold=0.41, softness=9.0, squash=3.4, contrast=6.0, big_weight=0.7, calm=0.05, haze=0.1,
                     layers=[(-36.0, 26.0, 10.0, 6.0)]),
         cc=((24, 30, 42), (62, 72, 88), (150, 162, 178)),
         fx=[dict(kind="vortex", twist=4.2, eye=0.13, reach=1.55, op=0.95)]),
    # 5 LAVA GOLEM raid ----------------------------------------------------------------------------------------------------
    dict(id="lava_core", name="Magma Core", group="Lava Golem", pal=("#450A0A", "#7F1D1D", "#DC2626", "#27272A"),
         clouds=dict(threshold=0.43, softness=5.0, detail=9, rough=0.68, distortion=0.35, light=-1.0, contrast=4.5,
                     rim=0.5, rim_focus=0.0, rim_base=1.0),
         cc=((38, 26, 26), (74, 46, 40), (196, 84, 40), (255, 140, 60)),
         sun=dict(el=-60, r=0.0, halo=(255, 90, 30), halo_size=60, halo_op=0.25, halo_pow=1.5),
         fx=[dict(kind="embers", col=(255, 170, 70), op=1.0)]),
    dict(id="lava_obsidian", name="Obsidian Furnace", group="Lava Golem", G=True,
         pal=("#27272A", "#3F3F46", "#EA580C", "#1A1214"),
         clouds=dict(threshold=0.46, softness=10.0, light=-1.0, contrast=5.0, rim=0.6, rim_focus=0.0, rim_base=1.0),
         cc=((18, 16, 18), (40, 36, 40), (120, 66, 44), (255, 120, 40)),
         fx=[dict(kind="lava_veins", col=(255, 120, 30), core=(255, 220, 120), op=1.0)]),
    dict(id="lava_cinder", name="Cinder Haze", group="Lava Golem", pal=("#3F1010", "#991B1B", "#F0603C", "#1C1917"),
         clouds=dict(threshold=0.42, softness=5.0, squash=4.2, detail=7, rough=0.6, opacity=0.95, light=-1.0,
                     calm=0.1),
         cc=((30, 14, 14), (62, 28, 26), (150, 64, 46)),
         fx=[dict(kind="heat_haze", col=(255, 190, 170), op=0.32), dict(kind="embers", col=(255, 170, 70), op=1.6, boost=1.8)]),
    # 6 FROST WYRM raid ----------------------------------------------------------------------------------------------------
    dict(id="frost_glacial", name="Glacial Void", group="Frost Wyrm", pal=("#083344", "#155E75", "#67E8F9", "#F8FAFC"),
         clouds=dict(threshold=0.45, softness=14.0, facet=0.45),
         cc=((92, 160, 186), (172, 226, 240), (242, 252, 255)),
         fx=[dict(kind="pillars", col=(220, 252, 255), op=0.6)]),
    dict(id="frost_blizzard", name="Boreal Blizzard", group="Frost Wyrm", G=True,
         pal=("#0B1A3A", "#1E3A8A", "#93C5FD", "#FFFFFF"),
         clouds=dict(threshold=0.43, softness=4.0, squash=3.6, shear=22.0, distortion=0.25),
         cc=((112, 140, 190), (192, 212, 242), (246, 250, 255)),
         fx=[dict(kind="snow_streaks", col=(255, 255, 255), op=0.6)]),
    dict(id="frost_mint", name="Permafrost Mint", group="Frost Wyrm", pal=("#064E3B", "#0D9488", "#5EEAD4", "#CCFBF1"),
         clouds=dict(threshold=0.41, softness=4.0, big_weight=0.8, squash=2.4, contrast=3.0, calm=0.15, haze=0.2,
                     layers=[(-36.0, 30.0, 10.0, 10.0)]),
         cc=((122, 190, 182), (192, 240, 230), (242, 255, 250)),
         fx=[dict(kind="ice_fracture", col=(220, 255, 245), op=0.12)]),
    # 7 SHADOW HYDRA raid (cosmic) -----------------------------------------------------------------------------------------
    dict(id="shadow_rift", name="Void Rift", group="Shadow Hydra", G=True, pal=("#07051A", "#1E1B4B", "#8B5CF6", "#0E0B1C"),
         clouds=dict(threshold=0.44, softness=5.0, erode=0.7, opacity=0.95),
         cc=((16, 13, 32), (36, 29, 66), (74, 58, 124)),
         stars=[dict(scale=1.0, frac=0.12, size=0.10, bright=0.7, min_el=14, col=(230, 220, 255))],
         fx=[dict(kind="rift", col=(150, 96, 255), core=(245, 230, 255), glow=(110, 60, 230), op=1.0)]),
    dict(id="shadow_nebula", name="Abyssal Nebula", group="Shadow Hydra", pal=("#0A0618", "#2E1065", "#C026D3", "#0A0614"),
         clouds=dict(threshold=0.5, softness=2.5, opacity=0.55, detail=8, rough=0.65, distortion=0.4),
         cc=((26, 12, 46), (60, 26, 96), (120, 56, 150)),
         stars=[dict(scale=1.1, frac=0.06, size=0.10, bright=0.8, min_el=12, cluster=0.5, col=(255, 210, 250)),
                dict(scale=0.5, frac=0.03, size=0.14, bright=1.0, min_el=12, cluster=0.35, col=(214, 190, 255))],
         fx=[dict(kind="nebula", op=1.0)]),
    dict(id="shadow_eclipse", name="Eclipse Shadow", group="Shadow Hydra", pal=("#18181B", "#27272A", "#71717A", "#0C0C10"),
         clouds=dict(threshold=0.45, softness=30.0, detail=8, rough=0.7, rim=1.0, rim_focus=5.0, rim_base=0.1,
                     contrast=2.0),
         cc=((12, 12, 15), (26, 26, 31), (44, 42, 52), (178, 146, 255)),
         sun=dict(el=24, r=4.6, edge=0.2, disc=(6, 4, 12), disc_op=1.0, black=True, halo=(150, 110, 255),
                  halo_size=18, halo_op=0.55, halo_pow=2.5, ring=4.75, ring_w=0.35, ring_op=1.0,
                  ring_col=(236, 220, 255), rays=0.8, rays_size=16, rays_col=(170, 120, 255))),
]
THEME_BY_ID = {t["id"]: t for t in THEMES}


# =========================================================================================================================
# contact sheet (plain Python, no bpy)
# =========================================================================================================================
def contact_sheet(out_root):
    from PIL import Image, ImageDraw, ImageFont
    cols, tw, th, lab = 3, 640, 320, 44
    rows = (len(THEMES) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw + (cols + 1) * 12, rows * (th + lab) + (rows + 1) * 12), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 20)
        small = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 16)
    except Exception:
        font = small = ImageFont.load_default()
    for i, t in enumerate(THEMES):
        r, c = divmod(i, cols)
        x, y = 12 + c * (tw + 12), 12 + r * (th + lab + 12)
        p = os.path.join(out_root, t["id"], "view.jpg")
        if os.path.exists(p):
            sheet.paste(Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS), (x, y + lab))
        else:
            d.rectangle([x, y + lab, x + tw, y + lab + th], outline=(200, 60, 60), width=3)
        star = "  (G)" if t.get("G") else ""
        d.text((x + 2, y + 2), "%d. %s%s" % (i + 1, t["name"], star), fill=(240, 240, 245), font=font)
        d.text((x + 2, y + 24), "%s  |  %s" % (t["group"], t["id"]), fill=(160, 160, 172), font=small)
    p = os.path.join(out_root, "contact.jpg")
    sheet.save(p, quality=90)
    print("contact sheet", p, sheet.size)


try:
    import bpy  # noqa: E402
except ImportError:
    bpy = None

if bpy is None:
    out = default_out()
    if "--out" in sys.argv:
        out = sys.argv[sys.argv.index("--out") + 1]
    if "--contact" in sys.argv:
        contact_sheet(out)
    else:
        print(__doc__)
    sys.exit(0)

# =========================================================================================================================
# Blender side
# =========================================================================================================================
import argparse  # noqa: E402

import numpy as np  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--themes", default="all")
ap.add_argument("--res", type=int, default=512)
ap.add_argument("--samples", type=int, default=16)
ap.add_argument("--out", default=default_out())
ap.add_argument("--skip-faces", action="store_true")
ap.add_argument("--skip-view", action="store_true")
ap.add_argument("--skip-pano", action="store_true")
ap.add_argument("--list", action="store_true")
ap.add_argument("--threads", type=int, default=8)
args = ap.parse_args(argv)
if args.list:
    for t in THEMES:
        print(t["id"], "-", t["name"])
    sys.exit(0)
ids = [t["id"] for t in THEMES] if args.themes == "all" else [s.strip() for s in args.themes.split(",") if s.strip()]

N = L = None  # the current world's nodes / links


def node(kind, **props):
    n = N.new(kind)
    for k, v in props.items():
        setattr(n, k, v)
    return n


def _feed(sock, v):
    if isinstance(v, (int, float)):
        sock.default_value = v
    elif isinstance(v, tuple):
        sock.default_value = v
    else:
        L.new(v, sock)


def op(operation, a=None, b=None, c=None):
    n = node("ShaderNodeMath", operation=operation)
    for i, v in enumerate((a, b, c)):
        if v is not None:
            _feed(n.inputs[i], v)
    return n.outputs[0]


def add(a, b):
    return op("ADD", a, b)


def sub(a, b):
    return op("SUBTRACT", a, b)


def mul(a, b):
    return op("MULTIPLY", a, b)


def clamp01(a):
    return op("MINIMUM", op("MAXIMUM", a, 0.0), 1.0)


def vop(operation, a, b=None, scale=None):
    n = node("ShaderNodeVectorMath", operation=operation)
    _feed(n.inputs[0], a)
    if b is not None:
        _feed(n.inputs[1], b)
    if scale is not None:
        _feed(n.inputs[3], scale)
    return n.outputs[1] if operation in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else n.outputs[0]


def srgb(c):
    def lin(x):
        x = x / 255.0
        return ((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92
    return (lin(c[0]), lin(c[1]), lin(c[2]), 1.0)


def ramp(value_socket, stops):
    n = node("ShaderNodeValToRGB")
    L.new(value_socket, n.inputs[0])
    els = n.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], srgb(stops[0][1])
    els[1].position, els[1].color = stops[-1][0], srgb(stops[-1][1])
    for pos, c in stops[1:-1]:
        e = els.new(pos)
        e.color = srgb(c)
    return n.outputs["Color"]


def smooth(value_socket, a, b):
    """0 at a, 1 at b (a > b allowed: falls), smoothstep."""
    n = node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
    _feed(n.inputs["Value"], value_socket)
    _feed(n.inputs["From Min"], a)
    _feed(n.inputs["From Max"], b)
    return n.outputs["Result"]


def mapping(vec, loc=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0)):
    mp = node("ShaderNodeMapping")
    L.new(vec, mp.inputs["Vector"])
    mp.inputs["Location"].default_value = loc
    mp.inputs["Rotation"].default_value = tuple(math.radians(r) for r in rot)
    mp.inputs["Scale"].default_value = scale
    return mp.outputs[0]


def noise(vec, scale, detail=2.0, rough=0.5, offset=(0.0, 0.0, 0.0), distortion=0.0, out="Fac"):
    v = mapping(vec, loc=offset) if any(offset) else vec
    nz = node("ShaderNodeTexNoise", noise_dimensions="3D")
    L.new(v, nz.inputs["Vector"])
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    nz.inputs["Roughness"].default_value = rough
    nz.inputs["Distortion"].default_value = distortion
    return nz.outputs[out]


def voronoi(vec, scale, feature="F1", detail=0.0, rough=0.5, randomness=1.0):
    vo = node("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature=feature)
    L.new(vec, vo.inputs["Vector"])
    vo.inputs["Scale"].default_value = scale
    vo.inputs["Randomness"].default_value = randomness
    if "Detail" in vo.inputs:
        vo.inputs["Detail"].default_value = detail
        vo.inputs["Roughness"].default_value = rough
    return vo


def mixc(fac, a, b, blend="MIX"):
    n = node("ShaderNodeMix", data_type="RGBA", blend_type=blend)
    _feed(n.inputs[0], fac)
    for idx, v in ((6, a), (7, b)):
        _feed(n.inputs[idx], srgb(v) if isinstance(v, tuple) and len(v) == 3 else v)
    return n.outputs[2]


def addc(col, fac, colour, strength=1.0):
    return mixc(mul(fac, strength) if strength != 1.0 else fac, col, colour, "ADD")


def sun_dir(az, el):
    a, e = math.radians(az), math.radians(el)
    return (math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e))


def build_world(t, star_res):
    global N, L
    old = bpy.context.scene.world
    world = bpy.data.worlds.new("Sky_" + t["id"])
    bpy.context.scene.world = world
    if old is not None:
        bpy.data.worlds.remove(old)
    try:
        world.use_nodes = True
    except Exception:
        pass
    nt = world.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    pal = dict(zip(("zenith", "upper", "horizon", "below"), (H(h) for h in t["pal"])))
    cl = dict(CLOUD_DEFAULT)
    cl.update(t.get("clouds", {}))
    az = t.get("az", 0.0)

    # ---- the view direction (Blender world: Z up) ---------------------------------------------------------------
    coord = node("ShaderNodeTexCoord")
    D = vop("NORMALIZE", coord.outputs["Generated"])
    sep = node("ShaderNodeSeparateXYZ")
    L.new(D, sep.inputs[0])
    X, Y, Z = sep.outputs[0], sep.outputs[1], sep.outputs[2]
    E = mul(op("ARCSINE", op("MINIMUM", op("MAXIMUM", Z, -1.0), 1.0)), 180.0 / math.pi)  # elevation, degrees
    comb = node("ShaderNodeCombineXYZ")
    L.new(X, comb.inputs[0])
    L.new(Y, comb.inputs[1])
    Hd = vop("NORMALIZE", comb.outputs[0])  # horizontal direction (azimuth only)
    e01 = add(mul(E, 1.0 / 180.0), 0.5)
    calm = mul(smooth(E, -17.0, -10.0), smooth(E, 22.0, 15.0))  # 1 inside the gameplay band
    near_h = smooth(op("ABSOLUTE", E), 24.0, 0.0)
    Sh = sun_dir(az, 0.0)
    face_side = clamp01(vop("DOT_PRODUCT", Hd, Sh))  # 1 toward the feature side

    # ---- sky gradient by elevation ------------------------------------------------------------------------------------
    rs = t.get("ramp") or [(-90, "below"), (-36, 0.25), (-12, 0.82), (0, "horizon"), (15, 0.3), (42, "upper"),
                           (90, "zenith")]
    stops = []
    for deg, v in rs:
        if isinstance(v, str):
            c = pal[v]
        elif deg < 0:
            c = lerp3(pal["below"], pal["horizon"], v)
        elif v <= 1.0 and deg <= 45:
            c = lerp3(pal["horizon"], pal["upper"], v)
        else:
            c = lerp3(pal["upper"], pal["zenith"], v)
        stops.append(((deg + 90.0) / 180.0, c))
    SKY = ramp(e01, stops)
    COL = SKY

    fx = t.get("fx", [])
    behind = [f for f in fx if f["kind"] in ("fog", "aurora", "ribbon", "rift", "nebula", "pillars")]
    front = [f for f in fx if f not in behind]

    # ---- features behind the clouds -------------------------------------------------------------------------------
    for f in behind:
        COL = feature(f, COL, D, X, Y, Z, E, Hd, calm, face_side, az, SKY)

    # ---- stars --------------------------------------------------------------------------------------------------------
    for i, s in enumerate(t.get("stars", [])):
        vo = voronoi(mapping(D, loc=(i * 7.3, i * 3.1, 0.0)), max(40.0, star_res * 0.11 * s["scale"]))
        cell = node("ShaderNodeSeparateColor")
        L.new(vo.outputs["Color"], cell.inputs[0])
        frac = s["frac"]
        if s.get("cluster"):
            cn = noise(D, 2.2, 3.0, 0.5, offset=(5.0, 1.0, 2.0))
            thr = sub(1.0, add(mul(smooth(cn, 0.45, 0.72), s["cluster"]), frac))
        else:
            thr = 1.0 - frac
        pick = op("GREATER_THAN", cell.outputs[0], thr)
        core = smooth(vo.outputs["Distance"], s["size"] * 1.6, s["size"] * 0.4)
        st = mul(core, pick)
        st = mul(st, smooth(E, s["min_el"], s["min_el"] + 18.0))
        st = mul(st, add(mul(cell.outputs[1], 0.75), 0.35))
        COL = addc(COL, st, s.get("col", (255, 250, 255)), s["bright"])

    # ---- sun / moon / black sun ---------------------------------------------------------------------------------------
    su = t.get("sun")
    if su:
        S = sun_dir(az, su["el"])
        cosang = vop("DOT_PRODUCT", D, S)
        ang = mul(op("ARCCOSINE", op("MINIMUM", op("MAXIMUM", cosang, -1.0), 1.0)), 180.0 / math.pi)
        if su.get("halo_op"):
            halo = op("POWER", smooth(ang, su["halo_size"], 0.0), su.get("halo_pow", 2.0))
            COL = addc(COL, halo, su["halo"], su["halo_op"])
        if su.get("bleed"):  # a halo smeared along the horizon
            b = op("POWER", clamp01(vop("DOT_PRODUCT", Hd, Sh)), 10.0)
            b = mul(b, smooth(op("ABSOLUTE", sub(E, su["el"])), 16.0, 0.0))
            COL = addc(COL, b, su["bleed_col"], su["bleed"])
        if su.get("rays"):  # radial streaks around the disc
            perp = vop("NORMALIZE", vop("SUBTRACT", D, vop("SCALE", S, scale=cosang)))
            streak = smooth(noise(perp, 9.0, 1.0, 0.5, offset=(2.0, 2.0, 2.0)), 0.45, 0.75)
            rays = mul(mul(streak, op("POWER", smooth(ang, su["rays_size"], su["r"]), 2.0)),
                       smooth(ang, su["r"] * 0.9, su["r"] * 1.05))
            COL = addc(COL, rays, su["rays_col"], su["rays"])
        if su.get("ring"):
            ring = smooth(op("ABSOLUTE", sub(ang, su["ring"])), su["ring_w"], 0.0)
            COL = addc(COL, ring, su["ring_col"], su["ring_op"])
        if su.get("r", 0) > 0:
            disc = mul(smooth(ang, su["r"] + su["edge"], su["r"]), su["disc_op"])
            if su.get("moon"):
                mare = add(mul(smooth(noise(D, 70.0, 3.0, 0.55), 0.35, 0.7), -0.2), 1.0)
                limb = add(mul(smooth(ang, 0.0, su["r"]), -0.12), 1.0)
                moon = mixc(1.0, srgb(su["disc"]), op("MULTIPLY", mare, limb), "MULTIPLY")
                COL = mixc(disc, COL, moon)
            else:
                COL = mixc(disc, COL, su["disc"])
        sunprox = op("POWER", clamp01(cosang), max(cl["rim_focus"], 0.001)) if cl["rim_focus"] > 0 else 1.0
        sun_ang = ang
    else:
        sunprox = op("POWER", face_side, max(cl["rim_focus"], 0.001)) if cl["rim_focus"] > 0 else 1.0

    # ---- clouds -------------------------------------------------------------------------------------------------------
    V = D
    if cl["shear"]:
        V = mapping(V, rot=(0.0, cl["shear"], 0.0))
    V = mapping(V, scale=(1.0, 1.0, cl["squash"]))
    up = 0.09 * cl["light"]
    fine = noise(V, cl["scale"], cl["detail"], cl["rough"], distortion=cl["distortion"])
    fine_up = noise(V, cl["scale"], cl["detail"], cl["rough"], offset=(0.0, 0.0, up), distortion=cl["distortion"])
    big = noise(V, cl["big_scale"], 1.0, 0.5, offset=(3.1, 1.7, 0.0))
    big_up = noise(V, cl["big_scale"], 1.0, 0.5, offset=(3.1, 1.7, up * 2.0))
    base = add(mul(fine, 1.0 - cl["big_weight"]), mul(big, cl["big_weight"]))
    if cl["facet"]:
        vo = voronoi(V, 9.0)
        cs = node("ShaderNodeSeparateColor")
        L.new(vo.outputs["Color"], cs.inputs[0])
        facet_val = cs.outputs[0]
    mask = None
    El = add(E, mul(sub(noise(D, 2.6, 2.0, 0.5, offset=(6.0, 2.0, 0.0)), 0.5), 9.0))  # layer edges wander a few degrees
    for (b0, t0, bf, tf) in cl["layers"]:
        m = mul(smooth(El, b0 - bf * 0.5, b0 + bf * 0.5), smooth(El, t0 + tf * 0.3, t0 - tf * 0.7))
        mask = m if mask is None else op("MAXIMUM", mask, m)
    # the band edges raise the threshold (clouds end with their own outlines, never a straight cut) ...
    thr = add(sub(cl["threshold"], mul(near_h, 0.04)), mul(sub(1.0, mask), 0.24))
    if cl.get("sun_clear") and su:
        ragged = add(sun_ang, mul(sub(noise(D, 4.0, 4.0, 0.6, offset=(2.0, 7.0, 1.0)), 0.5), cl["sun_clear"] * 1.2))
        thr = add(thr, mul(smooth(ragged, cl["sun_clear"] * 1.3, cl["sun_clear"] * 0.2), 0.18))
    dens = clamp01(mul(sub(base, thr), cl["softness"] * SOFT_GAIN))
    dens = mul(dens, smooth(mask, 0.0, 0.3))  # ... and nothing survives outside the band
    if cl["erode"]:
        ero = noise(D, 7.0, 4.0, 0.6, offset=(1.0, 4.0, 2.0))
        dens = mul(dens, smooth(ero, 0.5 * cl["erode"], 0.5 * cl["erode"] + 0.18))
    # lit where the density falls toward the light (fine puffs + the big heaps)
    shade = add(mul(sub(fine, fine_up), cl["contrast"]), 0.52)
    shade = add(shade, mul(sub(big, big_up), cl["contrast"] * 1.5 * cl["big_weight"]))
    shade = add(shade, mul(sub(base, cl["threshold"] + 0.1), -0.6))
    shade = clamp01(shade)
    if cl["facet"]:
        shade = op("ADD", mul(shade, 1.0 - cl["facet"] * 0.6), mul(facet_val, cl["facet"] * 0.6))
        shade = clamp01(shade)
    cc = t["cc"]
    CLOUD = ramp(shade, [(0.0, cc[0]), (0.35, cc[1]), (0.62, lerp3(cc[1], cc[2], 0.6)), (0.9, cc[2])])
    if cl["rim"]:
        # the rim: a band just inside each puff's soft edge (where the cloud is already opaque)
        ws = 1.0 / (cl["softness"] * SOFT_GAIN)
        ex = sub(base, thr)
        rim = mul(smooth(ex, 0.0, ws), smooth(ex, ws + cl["rim_width"], ws))
        rim = mul(rim, smooth(mask, 0.0, 0.3))
        rim = mul(rim, add(cl["rim_base"], mul(sunprox, 1.0 - cl["rim_base"])) if cl["rim_focus"] > 0 else 1.0)
        CLOUD = mixc(clamp01(mul(rim, cl["rim"] * 1.6)), CLOUD, cc[3])
    if cl["flash"]:  # lightning lighting up patches inside the clouds
        fl = smooth(noise(D, 2.4, 2.0, 0.5, offset=(7.0, 2.0, 1.0)), 0.6, 0.72)
        fl = mul(fl, smooth(fine, 0.45, 0.65))
        fl = mul(fl, smooth(E, 8.0, 20.0))
        CLOUD = mixc(clamp01(mul(fl, cl["flash"])), CLOUD, cc[3])
        CLOUD = addc(CLOUD, mul(fl, mul(dens, 0.4)), cc[3], cl["flash"])
    # aerial perspective: clouds near the horizon fade toward the sky colour, and thin out in the gameplay band
    CLOUD = mixc(mul(near_h, cl["haze"]), CLOUD, SKY)
    alpha = mul(mul(dens, cl["opacity"]), sub(1.0, mul(calm, cl["calm"])))
    COL = mixc(alpha, COL, CLOUD)

    # ---- features in front of the clouds ------------------------------------------------------------------------------
    for f in front:
        COL = feature(f, COL, D, X, Y, Z, E, Hd, calm, face_side, az, SKY, t=t)

    bg = node("ShaderNodeBackground")
    L.new(COL, bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    outn = node("ShaderNodeOutputWorld")
    L.new(bg.outputs[0], outn.inputs["Surface"])


def feature(f, COL, D, X, Y, Z, E, Hd, calm, face_side, az, SKY, t=None):
    k = f["kind"]
    quiet = sub(1.0, mul(calm, 0.75))  # features stay faint inside the gameplay band
    if k == "fog":
        fog = smooth(op("ABSOLUTE", sub(E, f["center"])), f["width"], 0.0)
        fog = mul(fog, add(mul(noise(mapping(D, scale=(1.0, 1.0, 6.0)), 1.5, 2.0, 0.5), 0.5), 0.75))
        return mixc(clamp01(mul(fog, f["op"])), COL, f["col"])
    if k == "wind_streaks":
        n = noise(mapping(D, scale=(1.2, 1.2, 16.0)), 1.4, 3.0, 0.5, offset=(1.0, 2.0, 0.0))
        s = smooth(n, 0.56, 0.68)
        s = mul(s, smooth(noise(D, 2.0, 2.0, 0.5, offset=(4.0, 0.0, 1.0)), 0.42, 0.6))
        s = mul(s, mul(smooth(E, 20.0, 28.0), smooth(E, 72.0, 52.0)))
        return addc(COL, s, f["col"], f["op"])
    if k == "ribbon":  # a nebula ribbon across the zenith, over the feature side
        # the great circle through a point low on the feature side and one high on the far side: diagonal in view
        p1, p2 = sun_dir(az - f["tilt"], 6.0), sun_dir(az + 125.0, 62.0)
        nrm = (p1[1] * p2[2] - p1[2] * p2[1], p1[2] * p2[0] - p1[0] * p2[2], p1[0] * p2[1] - p1[1] * p2[0])
        ln = math.sqrt(sum(c * c for c in nrm))
        nrm = tuple(c / ln for c in nrm)
        d = add(vop("DOT_PRODUCT", D, nrm), mul(sub(noise(D, 2.0, 2.0, 0.5, offset=(3.0, 3.0, 3.0)), 0.5), 0.22))
        d = op("ABSOLUTE", d)
        w = f["width"]
        body = op("POWER", smooth(d, w * 2.2, 0.0), 2.0)
        wisps = add(mul(smooth(noise(D, 7.0, 4.0, 0.6), 0.4, 0.7), 0.7), 0.3)
        body = mul(mul(body, wisps), smooth(E, f["min_el"], f["min_el"] + 14.0))
        COL = addc(COL, body, f["col"], f["op"])
        core = mul(smooth(d, w * 0.5, 0.0), smooth(E, f["min_el"], f["min_el"] + 14.0))
        core = mul(core, smooth(noise(D, 5.0, 3.0, 0.5, offset=(9.0, 1.0, 0.0)), 0.35, 0.65))
        return addc(COL, core, f["core"], f["op"] * 0.55)
    if k == "aurora":
        out = COL
        for j, (lift, strength) in enumerate(((0.0, 1.0), (13.0, 0.6))):
            c = add(f["base"] + lift, mul(sub(noise(Hd, 1.3, 2.0, 0.5, offset=(j * 5.0, 1.0, 0.0)), 0.5), 18.0))
            tt = op("DIVIDE", sub(E, c), f["height"])
            curtain = mul(smooth(tt, -0.04, 0.04), op("POWER", clamp01(sub(1.0, tt)), 2.2))
            rays = add(mul(smooth(noise(Hd, 16.0, 2.0, 0.5, offset=(j * 3.0, 0.0, 2.0)), 0.3, 0.75), 0.6), 0.4)
            amask = op("MAXIMUM", smooth(noise(Hd, 0.9, 1.0, 0.5, offset=(j * 2.0 + 8.0, 0.0, 0.0)), 0.42, 0.58),
                       op("POWER", face_side, 1.5))
            a = mul(mul(mul(curtain, rays), amask), strength)
            col = ramp(clamp01(tt), [(0.0, (120, 255, 190)), (0.25, (52, 222, 170)), (0.6, (34, 180, 200)),
                                     (1.0, (80, 90, 220))])
            out = mixc(1.0, out, mixc(clamp01(mul(a, f["op"])), (0, 0, 0), col), "ADD")
        return out
    if k == "lightning":
        warp = mapping(D, scale=(2.6, 2.6, 2.6))
        nzv = noise(D, 3.0, 3.0, 0.6, out="Color")
        warp = vop("ADD", warp, vop("SCALE", nzv, scale=0.55))
        vo = voronoi(warp, 1.0, feature="DISTANCE_TO_EDGE", detail=2.0, rough=0.55)
        dist = vo.outputs["Distance"]
        zone = smooth(noise(D, 1.7, 2.0, 0.5, offset=(11.0, 3.0, 0.0)), 0.53, 0.63)
        zone = mul(zone, mul(smooth(E, f["min_el"], f["min_el"] + 8.0), smooth(E, f["max_el"], f["max_el"] - 12.0)))
        line = mul(smooth(dist, 0.018, 0.0), zone)
        glow = mul(op("POWER", smooth(dist, 0.11, 0.0), 2.0), zone)
        COL = addc(COL, glow, f["glow"], 0.35 * f["op"])
        return addc(COL, line, f["col"], f["op"])
    if k == "vortex":  # eye of the storm at the zenith: clouds swirled around a clear eye
        r = op("ARCCOSINE", op("MINIMUM", op("MAXIMUM", Z, -1.0), 1.0))  # 0 at the zenith (radians)
        rot = node("ShaderNodeVectorRotate", rotation_type="Z_AXIS")
        L.new(D, rot.inputs["Vector"])
        L.new(mul(smooth(r, f["reach"], 0.0), f["twist"]), rot.inputs["Angle"])
        Rv = rot.outputs[0]
        rs = node("ShaderNodeSeparateXYZ")
        L.new(Rv, rs.inputs[0])
        ang = op("ARCTAN2", rs.outputs[1], rs.outputs[0])
        warp = mul(sub(noise(D, 2.6, 3.0, 0.55, offset=(6.0, 1.0, 2.0)), 0.5), 3.0)  # no straight arm edges
        arms = add(mul(op("SINE", add(add(mul(ang, 3.0), mul(r, 2.0)), warp)), 0.5), 0.5)
        n = noise(mapping(Rv, scale=(1.0, 1.0, 0.4)), 2.2, 5.0, 0.55)
        n2 = noise(Rv, 7.0, 6.0, 0.6, offset=(1.0, 3.0, 0.0))  # cloud texture inside the arms
        n2u = noise(Rv, 7.0, 6.0, 0.6, offset=(1.0, 3.0, 0.03))
        v = add(add(mul(n, 0.45), mul(arms, 0.35)), mul(n2, 0.3))
        dens = clamp01(mul(sub(v, 0.52), 6.0))
        dens = mul(dens, mul(smooth(r, f["eye"], f["eye"] + 0.08), smooth(r, f["reach"], f["reach"] - 0.35)))
        cc = t["cc"]
        lit = clamp01(add(add(mul(sub(n2, n2u), 6.0), 0.45), mul(smooth(r, f["eye"] + 0.3, f["eye"]), 0.35)))
        VC = ramp(lit, [(0.0, cc[0]), (0.45, cc[1]), (1.0, cc[2])])
        COL = mixc(clamp01(mul(dens, f["op"])), COL, VC)
        # the eye: a pale, calm opening (lighter sky seen through the storm)
        eye = smooth(r, f["eye"] + 0.02, f["eye"] - 0.1)
        return mixc(mul(eye, 0.55), COL, (176, 190, 210))
    if k == "embers":
        V = mapping(D, scale=(1.0, 1.0, 0.3))
        out = COL
        boost = f.get("boost", 1.0)  # more and bigger flecks
        for j, (sc, frac, br) in enumerate(((46.0, 0.10 * boost, 1.0), (24.0, 0.05 * boost, 0.8))):
            vo = voronoi(mapping(V, loc=(j * 4.0, j * 2.0, 0.0)), sc)
            cell = node("ShaderNodeSeparateColor")
            L.new(vo.outputs["Color"], cell.inputs[0])
            pick = op("GREATER_THAN", cell.outputs[0], 1.0 - frac)
            fl = mul(smooth(vo.outputs["Distance"], 0.2 * boost ** 0.5, 0.04), pick)
            fl = mul(fl, add(mul(cell.outputs[1], 0.8), 0.25))
            fl = mul(fl, smooth(E, 30.0, -8.0))
            fl = mul(fl, sub(1.0, mul(calm, 0.45)))
            out = addc(out, fl, f["col"], f["op"] * br)
        return out
    if k == "lava_veins":  # cracks of glowing lava across the nadir
        warp = vop("ADD", mapping(D, scale=(3.4, 3.4, 3.4)), vop("SCALE", noise(D, 2.5, 3.0, 0.6, out="Color"), scale=0.5))
        vo = voronoi(warp, 1.0, feature="DISTANCE_TO_EDGE", detail=1.5, rough=0.5)
        dist = vo.outputs["Distance"]
        m = smooth(E, -10.0, -24.0)
        heat = add(mul(smooth(noise(D, 3.0, 2.0, 0.5, offset=(2.0, 9.0, 0.0)), 0.35, 0.7), 0.7), 0.3)
        glow = mul(mul(op("POWER", smooth(dist, 0.13, 0.0), 2.0), m), heat)
        line = mul(mul(smooth(dist, 0.03, 0.005), m), heat)
        COL = addc(COL, glow, f["col"], 0.55 * f["op"])
        return addc(COL, line, f["core"], f["op"])
    if k == "heat_haze":
        V = mapping(D, scale=(1.0, 1.0, 22.0))
        ripple = noise(V, 3.0, 3.0, 0.5, distortion=0.8)
        band = smooth(op("ABSOLUTE", sub(E, 3.0)), 9.0, 0.0)
        hz = mul(band, add(mul(smooth(ripple, 0.35, 0.7), 0.6), 0.4))
        return mixc(clamp01(mul(hz, f["op"])), COL, f["col"])
    if k == "pillars":  # vertical light pillars rising from the horizon
        p = smooth(noise(Hd, 22.0, 1.0, 0.5, offset=(3.0, 0.0, 0.0)), 0.6, 0.76)
        p = mul(p, smooth(noise(Hd, 1.6, 1.0, 0.5, offset=(0.0, 6.0, 0.0)), 0.4, 0.55))
        rise = mul(smooth(E, -3.0, 5.0), op("POWER", smooth(E, 46.0, 4.0), 1.6))
        p = mul(p, rise)
        return addc(COL, p, f["col"], f["op"])
    if k == "snow_streaks":
        V = mapping(mapping(D, rot=(0.0, 12.0, 0.0)), scale=(2.2, 2.2, 70.0))
        n = noise(V, 2.4, 2.0, 0.5, offset=(0.0, 0.0, 3.0))
        s = smooth(n, 0.66, 0.76)
        s = mul(s, smooth(noise(D, 6.0, 2.0, 0.5, offset=(5.0, 5.0, 0.0)), 0.45, 0.62))
        s = mul(s, mul(smooth(E, 14.0, 22.0), smooth(E, 60.0, 42.0)))
        return addc(COL, s, f["col"], f["op"])
    if k == "ice_fracture":
        warp = vop("ADD", mapping(D, scale=(4.0, 4.0, 4.0)), vop("SCALE", noise(D, 2.0, 2.0, 0.5, out="Color"), scale=0.25))
        vo = voronoi(warp, 1.0, feature="DISTANCE_TO_EDGE", detail=1.0, rough=0.5)
        line = smooth(vo.outputs["Distance"], 0.011, 0.0)
        line = mul(line, mul(smooth(E, 18.0, 30.0), smooth(noise(D, 2.5, 2.0, 0.5, offset=(1.0, 1.0, 7.0)), 0.35, 0.6)))
        return addc(COL, line, f["col"], f["op"])
    if k == "rift":  # a glowing cosmic tear from the feature side over the zenith
        a = math.radians(az + 90.0)
        nrm = (math.sin(a), math.cos(a), 0.0)
        d = vop("DOT_PRODUCT", D, nrm)
        d = add(d, mul(sub(noise(D, 2.4, 2.0, 0.5, offset=(4.0, 0.0, 0.0)), 0.5), 0.2))
        d = add(d, mul(sub(noise(D, 14.0, 3.0, 0.6, offset=(0.0, 4.0, 0.0)), 0.5), 0.05))
        d = op("ABSOLUTE", d)
        w = add(0.02, mul(smooth(noise(D, 1.6, 1.0, 0.5, offset=(2.0, 2.0, 2.0)), 0.3, 0.7), 0.05))
        along = vop("DOT_PRODUCT", Hd, sun_dir(az, 0.0))
        m = mul(smooth(E, 13.0, 24.0), smooth(add(mul(along, op("ABSOLUTE", sub(1.0, Z))), Z), 0.25, 0.75))
        glow = mul(op("POWER", smooth(d, mul(w, 5.0), 0.0), 2.0), m)
        body = mul(smooth(d, w, mul(w, 0.6)), m)
        core = mul(smooth(d, mul(w, 0.35), 0.0), m)
        COL = addc(COL, glow, f["glow"], 0.5 * f["op"])
        COL = mixc(clamp01(body), COL, f["col"])
        return addc(COL, core, f["core"], f["op"])
    if k == "nebula":
        n = noise(D, 1.6, 8.0, 0.62, offset=(2.0, 0.0, 5.0), distortion=0.5)
        dust = op("POWER", smooth(n, 0.46, 0.78), 1.4)
        dust = mul(dust, smooth(E, 4.0, 18.0))
        hue = noise(D, 1.1, 2.0, 0.5, offset=(8.0, 8.0, 0.0))
        col = ramp(hue, [(0.3, (70, 40, 200)), (0.5, (150, 60, 220)), (0.7, (220, 60, 200))])
        COL = mixc(1.0, COL, mixc(clamp01(mul(dust, f["op"])), (0, 0, 0), col), "ADD")
        # dark dust lanes: contrast and depth in the band above the islands
        lanes = smooth(noise(mapping(D, scale=(1.0, 1.0, 1.8)), 2.2, 6.0, 0.6, offset=(4.0, 1.0, 3.0), distortion=0.4),
                       0.5, 0.68)
        lanes = mul(lanes, mul(smooth(E, 5.0, 14.0), smooth(E, 70.0, 40.0)))
        return mixc(mul(lanes, 0.6 * f["op"]), COL, (22, 8, 44))
    raise ValueError("unknown feature " + k)


# ---- scene + cameras ------------------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = args.samples
scene.cycles.use_denoising = False
scene.cycles.seed = 7
scene.render.threads_mode = "FIXED"
scene.render.threads = args.threads
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.render.dither_intensity = 1.0
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
r = math.radians
FACES = [
    ("Ft", (r(90), 0, r(0))),     # looks +Y (Roblox -Z)
    ("Rt", (r(90), 0, r(-90))),   # looks +X (Roblox +X)
    ("Bk", (r(90), 0, r(180))),   # looks -Y (Roblox +Z)
    ("Lf", (r(90), 0, r(90))),    # looks -X (Roblox -X)
    ("Up", (r(180), 0, r(0))),    # looks +Z, image top toward -Y (Roblox +Z)
    ("Dn", (0, 0, r(0))),         # looks -Z, image top toward +Y (Roblox -Z)
]


def render_to(path, w, h, fmt):
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.image_settings.file_format = fmt
    scene.render.image_settings.color_mode = "RGB"
    if fmt == "JPEG":
        scene.render.image_settings.quality = 92
    else:
        scene.render.image_settings.compression = 90
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_px(path, res):
    img = bpy.data.images.load(path)
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(res, res, img.channels)[::-1, :, :3] * 255.0
    bpy.data.images.remove(img)
    return arr


summary = []
for tid in ids:
    t = THEME_BY_ID[tid]
    out = os.path.join(args.out, tid)
    os.makedirs(out, exist_ok=True)
    build_world(t, args.res)
    az = t.get("az", 0.0)
    line = tid
    if not args.skip_faces:
        cam_data.type = "PERSP"
        cam_data.sensor_fit = "HORIZONTAL"
        cam_data.angle = math.radians(90)
        px = {}
        for name, rot in FACES:
            cam.rotation_euler = rot
            p = os.path.join(out, "Skybox%s.png" % name)
            render_to(p, args.res, args.res, "PNG")
            px[name] = load_px(p, args.res)
        R = args.res
        order = ["Ft", "Rt", "Bk", "Lf"]
        side = [float(np.abs(px[order[i]][:, -1] - px[order[(i + 1) % 4]][:, 0]).mean()) for i in range(4)]
        inner = float(np.abs(px["Ft"][:, R // 2] - px["Ft"][:, R // 2 + 1]).mean())
        up, dn = px["Up"], px["Dn"]
        # Up / Dn edges as this script lays them out (see the docstring): top rows of the sides vs Up, bottom rows vs Dn
        ups = [np.abs(px["Ft"][0] - up[-1]).mean(), np.abs(px["Bk"][0] - up[0][::-1]).mean(),
               np.abs(px["Rt"][0] - up[:, -1][::-1]).mean(), np.abs(px["Lf"][0] - up[:, 0]).mean()]
        dns = [np.abs(px["Ft"][-1] - dn[0]).mean(), np.abs(px["Bk"][-1] - dn[-1][::-1]).mean(),
               np.abs(px["Rt"][-1] - dn[:, -1]).mean(), np.abs(px["Lf"][-1] - dn[:, 0][::-1]).mean()]
        line = "%s SEAMS sides %s | up %s | dn %s | inner %.2f | max %.2f" % (
            tid, " ".join("%.2f" % s for s in side), " ".join("%.2f" % s for s in ups),
            " ".join("%.2f" % s for s in dns), inner, max(side + ups + dns))
        print(line)
    if not args.skip_view:
        cam_data.type = "PERSP"
        cam_data.sensor_fit = "HORIZONTAL"
        cam_data.angle = math.radians(75)
        cam.rotation_euler = (r(90 + 10), 0, r(-az))
        render_to(os.path.join(out, "view.jpg"), 1280, 640, "JPEG")
        cam.rotation_euler = (r(90 + 45), 0, r(-az))  # looking up: zenith features (vortex, rift, ribbon)
        render_to(os.path.join(out, "view_up.jpg"), 1280, 640, "JPEG")
    if not args.skip_pano:
        cam_data.type = "PANO"
        cam_data.panorama_type = "EQUIRECTANGULAR"
        cam.rotation_euler = (r(90), 0, r(-az))
        render_to(os.path.join(out, "pano.jpg"), 1600, 800, "JPEG")
    summary.append(line)

print("==== SUMMARY ====")
for s in summary:
    print(s)
