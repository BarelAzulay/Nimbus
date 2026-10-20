#!/usr/bin/env python3
"""The gate vortex textures (Phase 6 W2b, the player's "magical moving circle" inside every gate hoop).

Writes white RGB + alpha PNG layers (512 x 512, tinted in game with ImageLabel.ImageColor3 by PortalFxController) to
blender/textures/vortex/ and the uploader index blender/textures/textures.json (key -> png, contentHash = the PNG's
sha256, structureHash = its size + pixel format; any content change uploads as a NEW image asset). Procedural
(numpy + Pillow), seeded: the same script gives the same bytes. Nothing here is uploaded; tools/upload_assets.py
--textures uploads them later (dry run by default) and writes src/shared/TextureIds.lua.

    python3 blender/textures/build_vortex.py            # build every layer + textures.json
    python3 blender/textures/build_vortex.py --sheet x.png   # + a contact sheet of the layers on a dark ground

Layers (r = distance from the centre, 1 = the image edge):
    vortex_disc      the filled disc behind everything (soft edge at r 0.95)
    vortex_core      the depth in the middle: dense at the centre, gone by r 0.5 (tinted dark)
    vortex_arms      four broad streaky spiral arms winding into the centre
    vortex_fine      many thin light streaks along a tighter spiral (the fast layer)
    vortex_streaks   short light dashes scattered over the disc (scaled inward in game: pulled to the middle)
    vortex_rim       the bright glowing rim at r 0.83 (just inside the hoop's glow ring) with a soft inner glow
    vortex_crackle_1..4  small lightning crackles along the rim (one frame each; the game flickers them)
"""
import hashlib
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "vortex")
INDEX = os.path.join(HERE, "textures.json")
N = 512
SEED = 20261020

yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
cx = cy = (N - 1) / 2.0
dx, dy = (xx - cx) / (N / 2.0), (cy - yy) / (N / 2.0)  # y up
R = np.sqrt(dx * dx + dy * dy)
TH = np.arctan2(dy, dx)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def noise1d(rng, n, smooth):
    """periodic smooth 1-D noise of n samples (0..1)"""
    v = rng.random(n)
    k = np.exp(-0.5 * (np.arange(-3 * smooth, 3 * smooth + 1) / max(smooth, 1e-6)) ** 2)
    k /= k.sum()
    pad = len(k) // 2
    w = np.concatenate([v[-pad:], v, v[:pad]])
    s = np.convolve(w, k, mode="valid")[:n]
    s = (s - s.min()) / max(s.max() - s.min(), 1e-9)
    return s


def sample(arr, u):
    """periodic lookup of a 1-D array at continuous coordinate u (in samples)"""
    n = len(arr)
    i0 = np.floor(u).astype(np.int64)
    f = u - i0
    return arr[i0 % n] * (1 - f) + arr[(i0 + 1) % n] * f


def save(name, alpha):
    a = np.clip(alpha, 0.0, 1.0)
    rgba = np.zeros((N, N, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(a * 255).astype(np.uint8)
    path = os.path.join(OUT, name + ".png")
    Image.fromarray(rgba, "RGBA").save(path, optimize=False)
    return path


def spiral_u(tightness):
    """a coordinate that is constant along a log spiral winding clockwise into the centre"""
    return TH + tightness * np.log(np.maximum(R, 1e-3))


def build():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(SEED)
    paths = {}
    inside = 1.0 - smoothstep(0.9, 0.97, R)

    # the filled disc
    paths["vortex_disc"] = save("vortex_disc", 0.94 * inside)

    # the depth in the middle
    paths["vortex_core"] = save("vortex_core", 0.92 * (1.0 - smoothstep(0.0, 0.5, R)) ** 1.4)

    # four broad streaky arms
    u = spiral_u(2.3)
    arms = 0.5 + 0.5 * np.cos(5 * u)
    arms = arms ** 1.25
    streak = sample(noise1d(rng, 2048, 2.0), (u % (2 * math.pi)) / (2 * math.pi) * 2048)
    radial_streak = 0.75 + 0.25 * sample(noise1d(rng, 512, 6.0), R * 300 + 40 * np.sin(u))
    a = arms * (0.55 + 0.45 * streak ** 1.5) * radial_streak
    a *= smoothstep(0.04, 0.3, R) * (1.0 - smoothstep(0.86, 0.95, R))
    paths["vortex_arms"] = save("vortex_arms", 0.95 * a / max(a.max(), 1e-9))

    # many thin streaks on a tighter spiral
    u2 = spiral_u(3.1)
    fine = sample(noise1d(rng, 4096, 1.2), (u2 % (2 * math.pi)) / (2 * math.pi) * 4096)
    fine = smoothstep(0.45, 0.9, fine)
    breaks = sample(noise1d(rng, 1024, 4.0), R * 700 + 90 * u2)
    f = fine * (0.35 + 0.65 * smoothstep(0.3, 0.8, breaks))
    f *= smoothstep(0.06, 0.35, R) * (1.0 - smoothstep(0.84, 0.93, R))
    paths["vortex_fine"] = save("vortex_fine", 0.9 * f / max(f.max(), 1e-9))

    # short light dashes (tangent-ish, a little inward), glowing
    img = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(img)
    for _ in range(38):
        r = 0.14 + 0.72 * rng.random() ** 0.8
        th = rng.random() * 2 * math.pi
        x0, y0 = cx + r * math.cos(th) * N / 2, cy - r * math.sin(th) * N / 2
        ang = th - math.pi / 2 - 0.45  # clockwise, bending inward
        length = (6 + 14 * rng.random()) * (0.5 + r)
        x1, y1 = x0 + math.cos(ang) * length, y0 - math.sin(ang) * length
        d.line([(x0, y0), (x1, y1)], fill=int(170 + 85 * rng.random()), width=2)
    glow = img.filter(ImageFilter.GaussianBlur(2.2))
    s = np.maximum(np.asarray(img, np.float64) / 255.0, np.asarray(glow, np.float64) / 255.0 * 1.6)
    paths["vortex_streaks"] = save("vortex_streaks", np.clip(s, 0, 1) * inside)

    # the bright rim with a soft inner glow
    ring = np.exp(-0.5 * ((R - 0.83) / 0.028) ** 2) + 0.6 * np.exp(-0.5 * ((R - 0.9) / 0.03) ** 2)
    inner = np.exp(-np.maximum(0.83 - R, 0) / 0.11) * (R < 0.83) * 0.65
    rim = np.clip(np.maximum(ring, inner), 0, 1) * (1.0 - smoothstep(0.93, 0.985, R))
    paths["vortex_rim"] = save("vortex_rim", rim)

    # lightning crackles along the rim (three per frame)
    for frame in range(1, 5):
        img = Image.new("L", (N, N), 0)
        d = ImageDraw.Draw(img)
        for _ in range(3):
            th = rng.random() * 2 * math.pi
            span = math.radians(18 + 22 * rng.random())
            steps = 22
            pts = []
            for k in range(steps + 1):
                t = th + span * k / steps
                r = 0.8 + 0.022 * (rng.random() - 0.5) * 2
                pts.append((cx + r * math.cos(t) * N / 2, cy - r * math.sin(t) * N / 2))
            d.line(pts, fill=255, width=2)
            # a small fork inward
            k = int(rng.integers(3, steps - 3))
            fx, fy = pts[k]
            ang = math.atan2(cy - fy, cx - fx) + (rng.random() - 0.5) * 0.9
            fork = [(fx, fy)]
            for j in range(1, 4):
                fork.append((fx + math.cos(ang) * 7 * j + (rng.random() - 0.5) * 6, fy + math.sin(ang) * 7 * j + (rng.random() - 0.5) * 6))
            d.line(fork, fill=210, width=1)
        glow = img.filter(ImageFilter.GaussianBlur(3.0))
        c = np.maximum(np.asarray(img, np.float64) / 255.0, np.asarray(glow, np.float64) / 255.0 * 1.8)
        name = "vortex_crackle_%d" % frame
        paths[name] = save(name, np.clip(c, 0, 1))

    # the uploader index
    index = {"comment": "GENERATED by blender/textures/build_vortex.py: Image assets for tools/upload_assets.py --textures", "keys": {}}
    for key in sorted(paths):
        with open(paths[key], "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        index["keys"][key] = {
            "png": os.path.relpath(paths[key], os.path.dirname(os.path.dirname(HERE))).replace(os.sep, "/"),
            "displayName": "NC " + key.replace("_", " "),
            "description": "Nimbus Climb gate vortex layer " + key,
            "contentHash": digest,
            "structureHash": image_structure(paths[key]),
        }
    with open(INDEX, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(index, indent=2, sort_keys=True) + "\n")
    return paths


def image_structure(path):
    """the image's 'structure': size + pixel format (review3 tooling-1). Informational for the uploader: Open Cloud
    cannot update an image's content in place, so tools/upload_assets.py --textures makes a NEW asset for ANY content
    change (same size or not); this hash only tells the log whether the size / format changed too."""
    with Image.open(path) as im:
        sig = "png %dx%d %s" % (im.size[0], im.size[1], im.mode)
    return hashlib.sha256(sig.encode("utf-8")).hexdigest()[:32]


def sheet(paths, out):
    keys = sorted(paths)
    cell = 200
    im = Image.new("RGB", (cell * 4, cell * ((len(keys) + 3) // 4)), (20, 18, 40))
    for i, k in enumerate(keys):
        layer = Image.open(paths[k]).resize((cell - 10, cell - 10))
        bg = Image.new("RGB", layer.size, (30, 24, 60))
        bg.paste(Image.new("RGB", layer.size, (230, 200, 255)), (0, 0), layer)
        im.paste(bg, ((i % 4) * cell + 5, (i // 4) * cell + 5))
        ImageDraw.Draw(im).text(((i % 4) * cell + 8, (i // 4) * cell + 6), k, fill=(255, 255, 255))
    im.save(out)


if __name__ == "__main__":
    built = build()
    print("wrote %d layers to %s and %s" % (len(built), os.path.relpath(OUT), os.path.relpath(INDEX)))
    if "--sheet" in sys.argv:
        sheet(built, sys.argv[sys.argv.index("--sheet") + 1])
