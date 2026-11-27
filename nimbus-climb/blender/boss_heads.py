"""Bake the raid boss head portraits of the battle top card (Pitch 2 item 06 A "One strip", Config.BossHeads).

    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe blender/boss_heads.py render [--boss storm_titan ...]
    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe blender/boss_heads.py compose --mock-dir <PITCH2/A_battle_hud dir>
    py -3.12 blender/boss_heads.py index      (after every render: the boss_head_* entries of textures.json)

render (needs bpy + lupa, the bpy venv of blender/README.md): per boss it builds every High joint key of that boss
(blender/catalog/creatures.json "boss_<id>_<Joint>", the SAME keys the game assembles) through build_all.Builder, so
the K steps and budgets are the build's own, and checks each model's contentHash against blender/meshes.json (the
mesh rendered = the mesh uploaded). The joints stand at rest on their BossBuilder pivots. Cycles, orthographic, a
front three-quarter view of the head and shoulders, a warm key from the upper front and a cool rim from behind,
transparent film, CELLS x RENDER_CELL px (4x the on-screen size). The cut: a premultiplied BOX average per cell,
alpha >= 0.5 -> opaque (no soft edge, so no halo on the navy well), NEAREST x CELL_PX -> 72 px, a 1 px clear margin
-> PORTRAIT x PORTRAIT px. Clear pixels carry the well's NavyLip so a resampler can only ever bleed navy.
    branding/boss_heads/boss_head_<id>.png      the portrait (74 x 74 RGBA: BattleController K.PORTRAIT, shown 1:1 on PC,
                                                ResampleMode Pixelated, the well's NavyLip behind it)
    build/BOSS_HEADS/raw/boss_head_<id>_4x.png  the 4x render it was cut from

compose (Pillow only): the contact sheet build/BOSS_HEADS/sheet.png (the four heads beside the approved mock's
Storm Titan crop, at 4x, 1:1, a phone's 59 px and 40 px) and build/BOSS_HEADS/card_boss_head_<id>.png: each head in a
crop of the approved mock's top card (06_boss_bar_optA_1920.png and _phone.png) at the portrait's own rect, drawn the
way the game draws it (Hud.portrait: a NavyLip Frame K.PORTRAIT square at the card's inner left, a 2 px wood UIStroke
outside it, the image Pixelated inside), the card's name line rewritten with the boss's name.

index (no bpy): writes / refreshes the four boss_head_* entries of blender/textures/textures.json (png, displayName,
description, build, contentHash = the PNG's sha256, structureHash = tools/upload_assets.png_structure) and keeps every
other entry as it was, so the Studio upload can be recorded with tools/upload_assets.py --textures --upload --set-id
boss_head_<id>=IMAGEID (.superpowers/release/combined-uploads.md section A). Run it after every render.
Nothing here uploads anything.
"""
import argparse
import json
import math
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True

OUT_DIR = os.path.join(REPO, "branding", "boss_heads")
BUILD_DIR = os.path.join(REPO, "build", "BOSS_HEADS")
FONT_DIR = os.path.join(REPO, "tools", "fixtures", "fonts")

PORTRAIT = 74  # BattleController K.PORTRAIT (design px; 1:1 screen px at 1920 x 1080)
CELLS = 24  # cells across: 3 px cells at PORTRAIT (the pitch's "3 px cells")
CELL_PX = 3
RENDER_CELL = 12  # render px per cell: 288 px = 4x the 72 px cell area
BEAUTY_SAMPLES = 128
GLOW_WIN = 0.28  # a cell whose area is at least this much lit Neon (eyes, runes, bolts, magma) takes the glow's colour
NAVY_LIP = (23, 28, 79)  # Theme.Sign.NavyLip, the well behind the image
PHONE_K = 0.8  # Theme.ScreenFactor on a phone

ORDER = ["storm_titan", "lava_golem", "frost_wyrm", "shadow_hydra"]
NAMES = {"storm_titan": "Storm Titan", "lava_golem": "Lava Golem", "frost_wyrm": "Frost Wyrm", "shadow_hydra": "Shadow Hydra"}

# per boss: the joints the frame is fitted around, the view (yaw: 0 = the face, negative = from the boss's right;
# pitch up), the frame (zoom x the focus box, dx / dy = the centre's shift in frame widths: + = right / down)
SHOTS = {
    "storm_titan": {"focus": ["Head"], "yaw": -16, "pitch": 6, "zoom": 1.2, "dx": 0.0, "dy": 0.05, "exposure": 0.0},
    # (level camera: the golem's back hump sinks behind its head instead of sitting on it like a hat)
    "lava_golem": {"focus": ["Head"], "yaw": -18, "pitch": 0, "zoom": 1.75, "dx": 0.0, "dy": 0.05, "exposure": 0.45},
    "frost_wyrm": {"focus": ["Head", "Jaw"], "yaw": -22, "pitch": 8, "zoom": 1.25, "dx": 0.0, "dy": 0.08, "exposure": 0.0},
    "shadow_hydra": {"focus": ["Head1", "Head2", "Head3"], "top": 0.4, "yaw": -14, "pitch": 10, "zoom": 1.1, "dx": -0.005, "dy": 0.2,
                     "exposure": 0.4, "rim": 1.8},  # (dark hide on the navy well: a stronger cool rim lifts its edges)
}

# lights (Blender space: the boss faces -Y, +Z up): direction TO the light, colour, sun strength
KEY = ((-0.55, -0.85, 0.95), (1.0, 0.86, 0.68), 3.2)  # warm, upper front, camera side
RIM = ((0.85, 0.75, 0.55), (0.55, 0.74, 1.0), 5.0)  # cool, behind on the far side
RIM2 = ((-0.9, 0.7, 0.45), (0.55, 0.74, 1.0), 3.0)  # cool, behind on the near side: both silhouette edges lift off the navy
FILL = ((0.9, -0.6, 0.1), (0.75, 0.82, 1.0), 0.8)  # soft cool fill so the far cheek is not black
WORLD = ((0.62, 0.68, 0.84), 0.55)


def head_key(boss):
    return "boss_head_" + boss


# ---------------------------------------------------------------------------------------------------- render (bpy)
def joint_entries(boss):
    with open(os.path.join(HERE, "catalog", "creatures.json"), encoding="utf-8") as fh:
        cat = json.load(fh)
    out = []
    for e in cat["keys"]:
        if e.get("type") == "boss" and e.get("boss") == boss and e.get("lod", "High") == "High":
            e = dict(e)
            e["_class"] = cat.get("class", "creatures")
            out.append((cat, e))
    if not out:
        raise SystemExit("no High boss keys for %s in catalog/creatures.json" % boss)
    return out


def build_joints(builder, boss):
    """the boss's High joint models exactly as build_all.py builds them; the contentHash must match meshes.json"""
    import build_all
    from nvox.manifest import hashes
    with open(os.path.join(HERE, "meshes.json"), encoding="utf-8") as fh:
        index = json.load(fh)["keys"]
    joints = []
    for cat, e in joint_entries(boss):
        m = builder.build(e, build_all.resolve_budget(cat, e))
        ch = hashes(m)[0]
        want = (index.get(e["key"]) or {}).get("contentHash")
        if want != ch:
            raise SystemExit("%s: contentHash %s is not meshes.json's %s: the kit or BossBuilder changed since the last "
                             "build; rebuild the boss keys first (blender/README.md)" % (e["key"], ch, want))
        joints.append((e["key"], e["joint"], m))
    return joints


def _sun(bpy, sc, name, d, color, energy):
    from mathutils import Vector
    li = bpy.data.lights.new(name, "SUN")
    li.energy = energy
    li.color = color
    li.angle = math.radians(6)
    ob = bpy.data.objects.new(name, li)
    sc.collection.objects.link(ob)
    v = Vector(d).normalized()
    ob.rotation_euler = (-v).to_track_quat("-Z", "Y").to_euler()
    return ob


def render_boss(builder, boss, tmp):
    import bpy
    import numpy as np
    from mathutils import Matrix, Vector
    from nvox import blend as B
    shot = SHOTS[boss]
    joints = build_joints(builder, boss)
    sc = B.reset_scene()
    made, glow = {}, set()
    for key, joint, m in joints:
        pivot = np.asarray(m.meta["pivotStuds"], float)
        mat = np.eye(4)
        mat[:3, 3] = B.to_bl(pivot)
        made[joint] = B.make_objects(m, {}, matrix=mat)
        for spec, ob in zip(m.objects.values(), made[joint]):
            if spec.material == "Neon":  # BossBuilder's glow keys (Eye, Rune, Bolt, Magma, Glow): Neon in the game
                glow.add(ob.name)
    bpy.context.view_layer.update()
    res = CELLS * RENDER_CELL
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = BEAUTY_SAMPLES
    try:
        sc.cycles.use_denoising = True
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        sc.cycles.use_denoising = False
    sc.cycles.filter_width = 1.0
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.new("W")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = WORLD[0] + (1.0,)
    bg.inputs["Strength"].default_value = WORLD[1]
    for name, (d, col, e) in (("Key", KEY), ("Rim", RIM), ("Rim2", RIM2), ("Fill", FILL)):
        _sun(bpy, sc, name, d, col, e * (shot.get("rim", 1.0) if name.startswith("Rim") else 1.0))
    sc.view_settings.exposure = shot.get("exposure", 0.0)  # the darkest hides (golem rock, hydra hide) lifted a little
    # the camera: orthographic, looking at the focus joints from the shot's yaw / pitch
    y, p = math.radians(shot["yaw"]), math.radians(shot["pitch"])
    d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
    rot = (-d).to_track_quat("-Z", "Y")
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    pts = [ob.matrix_world @ v.co for j in shot["focus"] for ob in made[j] for v in ob.data.vertices]
    allpts = [ob.matrix_world @ v.co for obs in made.values() for ob in obs for v in ob.data.vertices]
    if shot.get("top"):  # a joint that is mostly neck (the hydra's): fit the frame to its top part only
        u_all = [q.dot(up) for q in pts]
        cut_u = max(u_all) - shot["top"] * (max(u_all) - min(u_all))
        pts = [q for q, u in zip(pts, u_all) if u >= cut_u]
    rs = [q.dot(right) for q in pts]
    us = [q.dot(up) for q in pts]
    size = max(max(rs) - min(rs), max(us) - min(us)) * shot["zoom"]
    cr = (max(rs) + min(rs)) / 2 + shot["dx"] * size
    cu = (max(us) + min(us)) / 2 - shot["dy"] * size
    depth = max(abs(q.dot(d)) for q in allpts) + 50
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size
    cam_data.clip_start = 0.1
    cam_data.clip_end = depth * 3
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = right * cr + up * cu + d * depth
    cam.rotation_euler = rot.to_euler()
    raw = os.path.join(tmp, head_key(boss) + "_4x.png")
    sc.render.filepath = raw
    bpy.ops.render.render(write_still=True)
    # the glow mask: the same view with every Neon part flat white and everything else flat black (occlusion kept), so
    # the cut can let a lit eye / rune / bolt win its cell instead of averaging into the dark visor around it
    white = _flat(bpy, "MaskGlow", (1.0, 1.0, 1.0))
    black = _flat(bpy, "MaskBody", (0.0, 0.0, 0.0))
    for obs in made.values():
        for ob in obs:
            ob.data.materials.clear()
            ob.data.materials.append(white if ob.name in glow else black)
    for ob in sc.collection.objects:
        if ob.type == "LIGHT":
            ob.hide_render = True
    bg.inputs["Strength"].default_value = 0.0
    sc.cycles.samples = 16
    sc.cycles.use_denoising = False
    mask = os.path.join(tmp, head_key(boss) + "_glow.png")
    sc.render.filepath = mask
    bpy.ops.render.render(write_still=True)
    from nvox.manifest import hashes
    info = {"boss": boss, "keys": [k for k, _, _ in joints], "contentHash": {k: hashes(m)[0] for k, _, m in joints},
            "res": res, "samples": BEAUTY_SAMPLES, "orthoScaleStuds": round(size, 3), "yaw": shot["yaw"], "pitch": shot["pitch"],
            "tris": int(sum(len(pp.vertices) - 2 for obs in made.values() for ob in obs for pp in ob.data.polygons)),
            "glowParts": len(glow), "shot": shot}
    return raw, mask, info


def _flat(bpy, name, rgb):
    """an unlit flat colour (emission only) for the glow mask pass"""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = tuple(rgb) + (1.0,)
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return mat


def cut(raw_png, mask_png=None):
    """4x render -> CELLS x CELLS cells (premultiplied BOX, alpha >= 0.5 opaque) -> PORTRAIT px with CELL_PX cells.
    With the glow mask: a cell that is at least GLOW_WIN lit Neon takes the average of its glow pixels only (an eye one
    voxel tall stays a lit cell instead of a grey smear), and such a cell is opaque even at the silhouette (bolt tips)"""
    import numpy as np
    from PIL import Image
    im = np.asarray(Image.open(raw_png).convert("RGBA"), np.float32) / 255.0
    n, c = CELLS, RENDER_CELL
    assert im.shape[0] == n * c and im.shape[1] == n * c, im.shape
    a = im[..., 3:4]
    pre = np.concatenate([im[..., :3] * a, a], 2).reshape(n, c, n, c, 4).mean(axis=(1, 3))
    al = pre[..., 3:4]
    rgb = pre[..., :3] / np.maximum(al, 1e-4)
    opaque = al[..., 0] >= 0.5
    if mask_png:
        mk = np.asarray(Image.open(mask_png).convert("RGBA"), np.float32) / 255.0
        g = (mk[..., 0:1] * mk[..., 3:4]) * a  # lit Neon, seen (the mask is flat: white glow, black body)
        cov = g.reshape(n, c, n, c, 1).mean(axis=(1, 3))
        gsum = (im[..., :3] * g).reshape(n, c, n, c, 3).sum(axis=(1, 3))
        gw = g.reshape(n, c, n, c, 1).sum(axis=(1, 3))
        win = cov[..., 0] >= GLOW_WIN
        rgb = np.where(win[..., None], gsum / np.maximum(gw, 1e-4), rgb)
        opaque = opaque | win
    cells = np.zeros((n, n, 4), np.uint8)
    cells[..., :3] = np.where(opaque[..., None], np.clip(rgb * 255 + 0.5, 0, 255), np.array(NAVY_LIP, np.float32)).astype(np.uint8)
    cells[..., 3] = np.where(opaque, 255, 0)
    small = Image.fromarray(cells, "RGBA").resize((n * CELL_PX, n * CELL_PX), Image.NEAREST)
    out = Image.new("RGBA", (PORTRAIT, PORTRAIT), NAVY_LIP + (0,))
    m = (PORTRAIT - n * CELL_PX) // 2
    out.paste(small, (m, m))
    return out, cells


def cmd_render(args):
    import build_all
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.join(BUILD_DIR, "raw"), exist_ok=True)
    builder = build_all.Builder(export=False, verbose=False)
    tmp = tempfile.mkdtemp(prefix="boss_heads_")
    rpath = os.path.join(BUILD_DIR, "render_report.json")
    try:
        with open(rpath, encoding="utf-8") as fh:
            done = {r["boss"]: r for r in json.load(fh)}
    except (OSError, ValueError, KeyError, TypeError):
        done = {}
    try:
        for boss in args.boss or ORDER:
            raw, mask, info = render_boss(builder, boss, tmp)
            for f in (raw, mask):
                shutil.copyfile(f, os.path.join(BUILD_DIR, "raw", os.path.basename(f)))
            img, cells = cut(raw, mask)
            png = os.path.join(OUT_DIR, head_key(boss) + ".png")
            img.save(png, optimize=True)
            info["png"] = os.path.relpath(png, REPO).replace("\\", "/")
            info["size"] = list(img.size)
            info["opaqueCells"] = int((cells[..., 3] > 0).sum())
            done[boss] = info
            print(json.dumps(info))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    with open(rpath, "w", encoding="utf-8", newline="\n") as fh:
        json.dump([done[b] for b in ORDER if b in done], fh, indent=1)
        fh.write("\n")


# ---------------------------------------------------------------------------------------------------- compose (Pillow)
S = {"Stone": (255, 247, 230), "Wood": (140, 90, 46), "NavyLip": NAVY_LIP, "Text": (59, 36, 18),
     "TextMuted": (118, 84, 54), "Page": (236, 240, 248), "Ink": (40, 44, 60)}
# the approved mock's top card (pitch_battle_hud.boss_A): card origin, width and screen factor per image
CARDS = {
    "1920": {"file": "06_boss_bar_optA_1920.png", "origin": (640, 70), "w": 640, "k": 1.0, "crop": (630, 60, 1290, 226)},
    "phone": {"file": "06_boss_bar_optA_phone.png", "origin": (222, 68), "w": 500, "k": PHONE_K, "crop": (214, 60, 630, 192)},
}


def _font(px, face="FredokaOne-Regular.ttf"):
    from PIL import ImageFont
    return ImageFont.truetype(os.path.join(FONT_DIR, face), max(6, int(px + 0.5)))


def _X(v, k):
    return int(math.floor(v * k + 0.5))


def place_portrait(im, head, ox, oy, k):
    """as Hud.portrait draws it: the NavyLip square (K.PORTRAIT x k) at the card's inner left under row 1, a 2 px wood
    UIStroke outside it, the image Pixelated (nearest) to the square"""
    from PIL import ImageDraw
    x, y = ox + _X(13, k), oy + _X(13 + 34 + 8, k)
    s = _X(PORTRAIT, k)
    e = max(1, _X(2, k))
    d = ImageDraw.Draw(im)
    d.rectangle([x - e, y - e, x + s + e - 1, y + s + e - 1], fill=S["Wood"])
    d.rectangle([x, y, x + s - 1, y + s - 1], fill=S["NavyLip"])
    h = head if s == head.width else head.resize((s, s), 0)  # 0 = NEAREST
    im.alpha_composite(h, (x, y))
    return (x, y, s)


def rename(im, name, ox, oy, w, k):
    """row 1 of boss_A with another boss's name: RAID tag | name (24) + tier "Starter" (18, muted, when it fits)"""
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)

    def tw(s, size):
        return d.textlength(s, font=_font(size * k)) / k
    x0 = 13
    cw = w - 2 * x0
    lw = 84 if k >= 1 else 72
    tag = tw("RAID", 18) + 18
    nx = x0 + tag + 10
    tx = x0 + cw - lw - (14 if k >= 1 else 10) - tw("4:57", 24)
    clock_l = tx - 6 - 18
    d.rectangle([ox + _X(nx - 2, k), oy + _X(15, k), ox + _X(clock_l - 3, k), oy + _X(13 + 32, k)], fill=S["Stone"])
    d.text((ox + _X(nx, k), oy + _X(13 + 15, k)), name, font=_font(24 * k), fill=S["Text"], anchor="lm")
    tier_x = nx + tw(name, 24) + 10
    if tier_x + tw("Starter", 18) + 12 <= clock_l:
        d.text((ox + _X(tier_x, k), oy + _X(13 + 16, k)), "Starter", font=_font(18 * k), fill=S["TextMuted"], anchor="lm")


def well(head, s, pad=10, label=None):
    """the head in its navy well with the wood edge at s px (nearest), on the page"""
    from PIL import Image, ImageDraw
    t = Image.new("RGBA", (s + 4 + 2 * pad, s + 4 + 2 * pad + (22 if label else 0)), S["Page"] + (255,))
    d = ImageDraw.Draw(t)
    d.rectangle([pad, pad, pad + s + 3, pad + s + 3], fill=S["Wood"])
    d.rectangle([pad + 2, pad + 2, pad + s + 1, pad + s + 1], fill=S["NavyLip"])
    t.alpha_composite(head if head.width == s else head.resize((s, s), 0), (pad + 2, pad + 2))
    if label:
        d.text((pad, pad + s + 8), label, font=_font(15, "Nunito-Regular.ttf"), fill=S["Ink"])
    return t


def cmd_compose(args):
    from PIL import Image, ImageDraw
    mock = args.mock_dir
    heads = {b: Image.open(os.path.join(OUT_DIR, head_key(b) + ".png")).convert("RGBA") for b in ORDER}
    for b, h in heads.items():
        assert h.size == (PORTRAIT, PORTRAIT), (b, h.size)
    os.makedirs(BUILD_DIR, exist_ok=True)
    base = {n: Image.open(os.path.join(mock, c["file"])).convert("RGBA") for n, c in CARDS.items()}
    # the mock's own Storm Titan head: its 74 px well (wood edge inside) at the 1920 card's portrait rect
    c = CARDS["1920"]
    mx, my = c["origin"][0] + 13, c["origin"][1] + 13 + 34 + 8
    mock_head = base["1920"].crop((mx, my, mx + PORTRAIT, my + PORTRAIT))
    # ---- the sheet: rows = 4x, 1:1 (PC), phone 59 px, 40 px; columns = the mock's head, then the four bosses
    cols = [("mock: Storm Titan (approved)", mock_head, True)] + [(NAMES[b] + " (baked)", heads[b], False) for b in ORDER]
    sizes = [(PORTRAIT * 4, "4x (nearest)"), (PORTRAIT, "1:1 = PC 1920x1080"), (_X(PORTRAIT, PHONE_K), "phone 0.8 = 59 px"), (40, "40 px")]
    colw = PORTRAIT * 4 + 4 + 2 * 10 + 20
    rowh = [s + 4 + 2 * 10 + 6 for s, _ in sizes]
    W = 190 + colw * len(cols)
    H = 70 + sum(rowh) + 60
    sheet = Image.new("RGBA", (W, H), S["Page"] + (255,))
    d = ImageDraw.Draw(sheet)
    d.text((20, 18), "Boss head portraits (Config.BossHeads, Pitch 2 item 06 A): baked in Blender from the game's boss meshes",
           font=_font(24), fill=S["Ink"])
    y = 70
    for (s, lab), rh in zip(sizes, rowh):
        d.text((20, y + 10 + s // 2), lab, font=_font(15, "Nunito-Regular.ttf"), fill=S["Ink"], anchor="lm")
        for i, (name, h, is_mock) in enumerate(cols):
            x = 190 + i * colw
            if is_mock:  # already in its well (wood edge inside the 74): show it as drawn, at the same scale
                t = Image.new("RGBA", (s + 4 + 20, s + 4 + 20), S["Page"] + (255,))
                t.alpha_composite(h if s == PORTRAIT else h.resize((s, s), 0), (12, 12))
            else:
                t = well(h, s)
            sheet.alpha_composite(t, (x, y))
        y += rh
    for i, (name, _, _) in enumerate(cols):
        d.text((190 + i * colw + 10, y + 6), name, font=_font(16, "Nunito-Regular.ttf"), fill=S["Ink"])
    d.text((20, H - 26), "Each baked head: 74 x 74 PNG, 24 x 24 cells of 3 px, transparent on the well's NavyLip; the mock's crop has its 2 px "
           "wood edge inside the 74 (the game strokes it outside).", font=_font(14, "Nunito-Regular.ttf"), fill=S["Ink"])
    sheet.convert("RGB").save(os.path.join(BUILD_DIR, "sheet.png"), optimize=True)
    print("sheet", os.path.join(BUILD_DIR, "sheet.png"))
    # ---- the cards: each head in the approved mock's top card, PC and phone, + the PC card's left end at 3x
    for b in ORDER:
        tiles = []
        for n, c in CARDS.items():
            im = base[n].copy()
            ox, oy = c["origin"]
            place_portrait(im, heads[b], ox, oy, c["k"])
            if b != "storm_titan":
                rename(im, NAMES[b], ox, oy, c["w"], c["k"])
            note = "" if b == "storm_titan" else "  (name rewritten; the pills are still the mock's Storm Titan pills)"
            tiles.append(("%s top card at 1:1%s" % ("PC 1920x1080" if n == "1920" else "phone 844x390 at 0.8", note), im.crop(c["crop"])))
        pc = tiles[0][1]
        zoom = pc.crop((0, 0, 300, pc.height)).resize((900, pc.height * 3), 0)
        tiles.append(("PC card's left end at 3x (nearest)", zoom))
        W = max(t.width for _, t in tiles) + 40
        H = 50 + sum(t.height + 40 for _, t in tiles)
        out = Image.new("RGBA", (W, H), S["Page"] + (255,))
        d = ImageDraw.Draw(out)
        d.text((20, 14), "%s: baked head in the approved 06 A top card" % NAMES[b], font=_font(22), fill=S["Ink"])
        y = 50
        for lab, t in tiles:
            d.text((20, y + 4), lab, font=_font(15, "Nunito-Regular.ttf"), fill=S["Ink"])
            out.alpha_composite(t, (20, y + 26))
            y += t.height + 40
        p = os.path.join(BUILD_DIR, "card_%s.png" % head_key(b))
        out.convert("RGB").save(p, optimize=True)
        print("card", p)


TEXTURES = os.path.join(HERE, "textures", "textures.json")


def index_entry(boss):
    """the boss head's blender/textures/textures.json entry (no id: ids live in upload_state.json / TextureIds.lua,
    written by tools/upload_assets.py --textures --upload --set-id KEY=IMAGEID after the Studio upload)"""
    sys.path.insert(0, os.path.join(REPO, "tools"))
    from upload_assets import png_structure, sha256_file
    png = os.path.join(OUT_DIR, head_key(boss) + ".png")
    return {
        "build": "blender/boss_heads.py render --boss %s (Blender 5.2 bpy, Cycles, the game's boss_%s_* joint meshes); "
                 "uploaded from Studio as an Image" % (boss, boss),
        "contentHash": sha256_file(png),
        "description": "Nimbus Climb battle top card: the %s's baked pixel head portrait (74 x 74, 3 px cells, shown "
                       "Pixelated on the navy well; Config.BossHeads)" % NAMES[boss],
        "displayName": "NC boss head %s" % NAMES[boss],
        "png": "branding/boss_heads/%s.png" % head_key(boss),
        "structureHash": png_structure(png),
    }


def cmd_index(args):
    """adds / refreshes the four boss_head_* entries in textures.json; every other entry is kept byte for byte (the
    file is json.dumps(indent=2, sort_keys=True) + a newline). Never blender/textures/build_vortex.py: it rewrites the
    index with the vortex layers only"""
    with open(TEXTURES, encoding="utf-8") as fh:
        data = json.load(fh)
    for boss in ORDER:
        data["keys"][head_key(boss)] = index_entry(boss)
    with open(TEXTURES + ".tmp", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    os.replace(TEXTURES + ".tmp", TEXTURES)
    print("textures.json: %d entries (%s)" % (len(data["keys"]), ", ".join(head_key(b) for b in ORDER)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("--boss", action="append", choices=ORDER)
    c = sub.add_parser("compose")
    c.add_argument("--mock-dir", required=True, help=".superpowers/slop-audit/round3/build/PITCH2/A_battle_hud")
    sub.add_parser("index")
    a = ap.parse_args()
    if a.cmd == "render":
        sys.path.insert(0, os.path.join(HERE, "kit"))
        cmd_render(a)
    elif a.cmd == "index":
        cmd_index(a)
    else:
        cmd_compose(a)


if __name__ == "__main__":
    main()
