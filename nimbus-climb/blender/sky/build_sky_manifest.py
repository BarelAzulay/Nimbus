#!/usr/bin/env python3
"""The living sky's painted faces for the keyed upload (plan docs/superpowers/plans/2026-10-30-living-sky.md Task 3).

Copies the player's 7 picked themes (sky_themes.py renders, 1024 x 1024, in the MAIN Nimbus folder's
.superpowers/sky-final/<theme>/Skybox<Face>.png, not committed) to blender/textures/sky/<theme>/Skybox<Face>.png and adds
the 42 keys sky_<theme>_<Face> to the uploader index blender/textures/textures.json (png, displayName "NC sky <theme>
<Face>", contentHash = the PNG's sha256, structureHash = its size + pixel format, as build_vortex.py writes them). The
other keys (the gate vortex layers) are kept as they are, and so is the file's format (CRLF or LF, the indent, sorted
keys, the trailing newline), so a re-run with the same renders leaves the file byte-identical. Nothing is uploaded:
tools/upload_assets.py --textures does that from the owner's keyed session (dry run by default) and writes
src/shared/TextureIds.lua, which shared/SkyFaces reads.

    py -3.12 blender/sky/build_sky_manifest.py               # copy the 42 faces + update textures.json
    py -3.12 blender/sky/build_sky_manifest.py --dry-run     # check the renders and print the plan, write nothing
    py -3.12 blender/sky/build_sky_manifest.py --src DIR     # another render folder (DIR/<theme>/Skybox<Face>.png)

All or nothing: every one of the 42 renders must exist as a 1024 x 1024 PNG, or the run refuses (exit 2) before it
copies or writes anything. NOTE: build_vortex.py rewrites textures.json with the vortex keys only; run this script
again after it.
"""
import argparse
import hashlib
import json
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME_ROOT = os.path.dirname(os.path.dirname(HERE))  # nimbus-climb
# the player's picks (docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md): Config.Sky.Themes + RaidThemes
THEMES = ["day_vivid", "dusk_amber", "night_aurora", "storm_teal", "lava_obsidian", "frost_glacial", "shadow_eclipse"]
FACES = ["Bk", "Dn", "Ft", "Lf", "Rt", "Up"]  # the Roblox Sky's Skybox<Face> names (shared/SkyFaces order)
SIZE = 1024
MODES = ("RGB", "RGBA")
BUILD = "py -3.12 blender/sky/build_sky_manifest.py  (%s)"  # the uploader's "missing PNG" hint (it fills in the key)


class Refusal(Exception):
    pass


def default_src(here=HERE):
    """<main Nimbus>/.superpowers/sky-final: the renders live in the main folder, not in a worktree (as sky_themes.py)"""
    repo = os.path.dirname(os.path.dirname(os.path.dirname(here)))  # .../Nimbus (or the worktree root)
    parts = repo.replace("\\", "/").split("/")
    if ".worktrees" in parts:
        repo = "/".join(parts[:parts.index(".worktrees")])
    return os.path.join(repo, ".superpowers", "sky-final")


def sha256(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def image_structure(path):
    """the image's size + pixel format, hashed exactly like build_vortex.image_structure (informational for the
    uploader: any content change uploads a NEW image asset)"""
    with Image.open(path) as im:
        sig = "png %dx%d %s" % (im.size[0], im.size[1], im.mode)
    return hashlib.sha256(sig.encode("utf-8")).hexdigest()[:32]


def check_sources(src):
    """every theme x face render, checked before anything is written: {key: (theme, face, path)}"""
    if not os.path.isdir(src):
        raise Refusal("no render folder %s (render the 1024 faces first: blender/sky/README.md)" % src)
    found, bad = {}, []
    for theme in THEMES:
        for face in FACES:
            path = os.path.join(src, theme, "Skybox%s.png" % face)
            if not os.path.isfile(path):
                bad.append("%s/Skybox%s.png missing" % (theme, face))
                continue
            try:
                with Image.open(path) as im:
                    fmt, size, mode = im.format, im.size, im.mode
            except OSError as e:
                bad.append("%s/Skybox%s.png unreadable (%s)" % (theme, face, e))
                continue
            if fmt != "PNG" or size != (SIZE, SIZE) or mode not in MODES:
                bad.append("%s/Skybox%s.png is %s %dx%d %s (want PNG %dx%d RGB / RGBA)" % (theme, face, fmt, size[0], size[1], mode, SIZE, SIZE))
                continue
            found["sky_%s_%s" % (theme, face)] = (theme, face, path)
    if bad:
        shown = "; ".join(bad[:6]) + (" ... (%d more)" % (len(bad) - 6) if len(bad) > 6 else "")
        raise Refusal("%d of %d sky faces are not ready in %s: %s" % (len(bad), len(THEMES) * len(FACES), src, shown))
    return found


def read_index(path):
    """(data, format) of textures.json; format = newline, indent, sort_keys, trailing newline of the file as it is"""
    fmt = {"newline": "\n", "indent": 2, "sort_keys": True, "trailing": True}
    if not os.path.isfile(path):
        return {"comment": "Image assets for tools/upload_assets.py --textures", "keys": {}}, fmt
    with open(path, "rb") as fh:
        raw = fh.read().decode("utf-8")
    if "\r\n" in raw:
        fmt["newline"] = "\r\n"
    text = raw.replace("\r\n", "\n")
    fmt["trailing"] = text.endswith("\n")
    data = json.loads(text)
    if not isinstance(data, dict) or not isinstance(data.get("keys", {}), dict):
        raise Refusal("%s: expected { \"keys\": { key: {...} } }" % path)
    data.setdefault("keys", {})
    for line in text.split("\n")[1:]:
        stripped = line.lstrip(" ")
        if stripped and stripped != line:
            fmt["indent"] = len(line) - len(stripped)
            break
    body = text.rstrip("\n")
    if json.dumps(data, indent=fmt["indent"], sort_keys=False) == body and json.dumps(data, indent=fmt["indent"], sort_keys=True) != body:
        fmt["sort_keys"] = False  # a hand-ordered file keeps its order (new keys go at the end)
    return data, fmt


def write_index(path, data, fmt):
    text = json.dumps(data, indent=fmt["indent"], sort_keys=fmt["sort_keys"]) + ("\n" if fmt["trailing"] else "")
    blob = text.replace("\n", fmt["newline"]).encode("utf-8")
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(blob)
    os.replace(tmp, path)


def build(src, root=GAME_ROOT, dry_run=False, log=None):
    """copy the 42 faces and index them; returns {key: entry} of the sky keys. Raises Refusal before writing anything."""
    log = log or (lambda msg: None)
    found = check_sources(src)
    index_path = os.path.join(root, "blender", "textures", "textures.json")
    data, fmt = read_index(index_path)
    entries, copied = {}, 0
    for key in sorted(found):
        theme, face, path = found[key]
        rel = "blender/textures/sky/%s/Skybox%s.png" % (theme, face)
        dest = os.path.join(root, *rel.split("/"))
        same = os.path.isfile(dest) and sha256(dest) == sha256(path)
        if not same:
            copied += 1
            if not dry_run:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copyfile(path, dest)
        entries[key] = {
            "png": rel,
            "displayName": "NC sky %s %s" % (theme, face),
            "description": "Nimbus Climb living sky face %s of the %s sky (blender/sky/sky_themes.py, %d px)" % (face, theme, SIZE),
            "contentHash": sha256(path),
            "structureHash": image_structure(path),
            "build": BUILD,
        }
    changed = sorted(k for k in entries if data["keys"].get(k) != entries[k])
    log("%d faces checked in %s: %d to copy, %d index entries new or changed" % (len(entries), src, copied, len(changed)))
    if changed and not dry_run:
        data["keys"].update(entries)
        write_index(index_path, data, fmt)
    return entries


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default=default_src(), help="the render folder (<theme>/Skybox<Face>.png)")
    ap.add_argument("--root", default=GAME_ROOT, help=argparse.SUPPRESS)  # tests: a temp game root
    ap.add_argument("--dry-run", action="store_true", help="check the renders and print the plan; write nothing")
    args = ap.parse_args(argv)
    try:
        entries = build(args.src, args.root, args.dry_run, log=print)
    except Refusal as r:
        print("refused: %s" % r, file=sys.stderr)
        return 2
    where = os.path.join("blender", "textures")
    print("%s %d sky keys (%d themes x %d faces) in %s" % ("dry run: would index" if args.dry_run else "indexed", len(entries), len(THEMES), len(FACES), where))
    return 0


if __name__ == "__main__":
    sys.exit(main())
