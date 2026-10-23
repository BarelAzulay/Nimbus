#!/usr/bin/env python3
"""Verify a Rojo-built place file against src/.

    python3 tools/verify_place.py                       # checks play/NimbusClimb.rbxlx
    python3 tools/verify_place.py path/to/other.rbxlx

Reads the mounts from default.project.json (every "$path" folder, e.g. src/shared -> ReplicatedStorage.Shared) and
checks, the way Rojo 7 maps files:
  * every src/**/*.lua is in the place at its path with the right class
    (*.server.lua -> Script, *.client.lua -> LocalScript, any other *.lua -> ModuleScript)
    and a Source that is byte-for-byte the file on disk,
  * every sub-folder is a Folder, no two siblings share a name (scripts would find the wrong one),
  * the place holds no script that src/ does not have (a stale copy would still run),
  * the "$properties" of default.project.json made it into the place (printed).
Exit status 0 when everything matches, 1 otherwise. Needs only Python 3.
"""
import json
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT_CLASSES = ("Script", "LocalScript", "ModuleScript")


def script_class(filename):
    """(instance name, class) for a .lua file, as Rojo 7 maps it."""
    if filename.endswith(".server.lua"):
        return filename[: -len(".server.lua")], "Script"
    if filename.endswith(".client.lua"):
        return filename[: -len(".client.lua")], "LocalScript"
    return filename[: -len(".lua")], "ModuleScript"


def project_mounts(project_file):
    """[(instance path tuple, folder on disk)] and [(instance path tuple, {property: value})] from the project."""
    with open(project_file, encoding="utf-8") as f:
        project = json.load(f)
    mounts, props = [], []

    def walk(node, path):
        if not isinstance(node, dict):
            return
        if "$path" in node:
            mounts.append((path, os.path.normpath(os.path.join(ROOT, node["$path"]))))
        if isinstance(node.get("$properties"), dict):
            props.append((path, node["$properties"]))
        for key, child in node.items():
            if not key.startswith("$"):
                walk(child, path + (key,))

    walk(project.get("tree", {}), ())
    return mounts, props


def read_place(place):
    """{path tuple: (class, {property: text})} for every Item, plus the list of duplicate sibling paths."""
    top = ET.parse(place).getroot()  # raises on malformed XML
    index, duplicates = {}, []

    def props_of(item):
        out = {}
        node = item.find("Properties")
        if node is not None:
            for child in node:
                out[child.get("name")] = child.text if child.text is not None else ""
        return out

    def walk(item, path):
        pr = props_of(item)
        here = path + (pr.get("Name", item.get("class")),)
        if here in index:
            duplicates.append(here)
        index[here] = (item.get("class"), pr)
        for child in item.findall("Item"):
            walk(child, here)

    for item in top.findall("Item"):
        walk(item, ())
    return index, duplicates


def main():
    place = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "play", "NimbusClimb.rbxlx")
    project_file = os.path.join(ROOT, "default.project.json")
    if not os.path.isfile(place):
        print("no place file at " + place + " (build it: rojo build default.project.json -o play/NimbusClimb.rbxlx)")
        return 1
    mounts, wanted_props = project_mounts(project_file)
    index, duplicates = read_place(place)

    problems = []
    expected = set()
    counts = {"Script": 0, "LocalScript": 0, "ModuleScript": 0, "Folder": 0}
    for mount, folder in mounts:
        shown = ".".join(mount)
        got = index.get(mount)
        if got is None:
            problems.append("missing mount " + shown)
            continue
        expected.add(mount)
        for dirpath, dirnames, filenames in os.walk(folder):
            dirnames.sort()
            rel_dir = os.path.relpath(dirpath, folder)
            parts = () if rel_dir == "." else tuple(rel_dir.split(os.sep))
            if parts:
                path = mount + parts
                expected.add(path)
                got = index.get(path)
                if got is None:
                    problems.append("missing folder " + ".".join(path))
                elif got[0] != "Folder":
                    problems.append("folder %s is a %s" % (".".join(path), got[0]))
                else:
                    counts["Folder"] += 1
            for filename in sorted(filenames):
                if not filename.endswith(".lua"):
                    continue
                name, cls = script_class(filename)
                path = mount + parts + (name,)
                expected.add(path)
                rel = os.path.relpath(os.path.join(dirpath, filename), ROOT)
                with open(os.path.join(dirpath, filename), "rb") as f:
                    # XML parsing turns CRLF into LF, so a Windows (autocrlf) checkout compares on LF too
                    disk = f.read().decode("utf-8").replace("\r\n", "\n")
                got = index.get(path)
                if got is None:
                    problems.append("MISSING %s (expected %s %s)" % (rel, cls, ".".join(path)))
                    continue
                if got[0] != cls:
                    problems.append("CLASS %s: expected %s, the place has %s" % (rel, cls, got[0]))
                    continue
                source = got[1].get("Source")
                if source is None:
                    problems.append("NO SOURCE " + rel)
                elif source != disk:
                    at = next((i for i, (a, b) in enumerate(zip(source, disk)) if a != b), min(len(source), len(disk)))
                    line = disk[:at].count("\n") + 1
                    problems.append("SOURCE DIFFERS %s (place %d chars, disk %d chars, first difference on line %d):"
                                    " rebuild the place" % (rel, len(source), len(disk), line))
                else:
                    counts[cls] += 1

    for path, (cls, _) in sorted(index.items()):
        if cls in SCRIPT_CLASSES and path not in expected:
            problems.append("EXTRA %s %s in the place (not in src/)" % (cls, ".".join(path)))
    for path in duplicates:
        problems.append("DUPLICATE name " + ".".join(path))

    for path, wanted in wanted_props:
        got = index.get(path)
        if got is None:
            problems.append("missing " + ".".join(path))
            continue
        for key, value in sorted(wanted.items()):
            if key not in got[1]:
                problems.append("%s.%s (%s in default.project.json) is not in the place" % (".".join(path), key, value))
            else:
                print("%s.%s = %s (stored as %r)" % (".".join(path), key, value, got[1][key]))

    shown_place = os.path.abspath(place)
    if shown_place.startswith(ROOT + os.sep):
        shown_place = os.path.relpath(shown_place, ROOT)
    print("place: %s (%d instances)" % (shown_place, len(index)))
    print("matched: %d ModuleScript, %d Script, %d LocalScript, %d Folder" % (
        counts["ModuleScript"], counts["Script"], counts["LocalScript"], counts["Folder"]))
    if problems:
        print("PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    total = counts["ModuleScript"] + counts["Script"] + counts["LocalScript"]
    print("OK: all %d src/**/*.lua files are in the place with the right class and identical Source; no extra scripts"
          % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
