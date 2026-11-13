#!/usr/bin/env python3
"""Offline tests of tools/verify_place.py's "$properties" check (the Lighting Sky faces of default.project.json).

Rojo 7.7.1 stores the six faces of a Sky under their Content names (SkyboxBk -> SkyboxBackContent, ...) as
<Content name="..."><uri>rbxassetid://...</uri></Content>; the project names them SkyboxBk ... SkyboxUp. Small place files
are written to a temp folder; nothing else is read or built. Exit code 0 = all passed.

    py -3.12 tools/test_verify_place.py
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_place as V  # noqa: E402

FACES = {
    "SkyboxBk": "rbxassetid://1001", "SkyboxDn": "rbxassetid://1002", "SkyboxFt": "rbxassetid://1003",
    "SkyboxLf": "rbxassetid://1004", "SkyboxRt": "rbxassetid://1005", "SkyboxUp": "rbxassetid://1006",
}
STORED = {
    "SkyboxBk": "SkyboxBackContent", "SkyboxDn": "SkyboxDownContent", "SkyboxFt": "SkyboxFrontContent",
    "SkyboxLf": "SkyboxLeftContent", "SkyboxRt": "SkyboxRightContent", "SkyboxUp": "SkyboxUpContent",
}
WANTED = dict(FACES, StarCount=0, CelestialBodiesShown=False)

failures = []


def check(ok, label, detail=""):
    print(("ok   " if ok else "FAIL ") + label + ("" if ok or not detail else "  (" + str(detail) + ")"))
    if not ok:
        failures.append(label)


def place(faces_xml):
    """A place file with Lighting (Technology) and its Sky (the given face elements, StarCount, CelestialBodiesShown)."""
    text = """<roblox version="4">
  <Item class="Lighting" referent="0">
    <Properties>
      <string name="Name">Lighting</string>
      <token name="Technology">3</token>
    </Properties>
    <Item class="Sky" referent="1">
      <Properties>
        <string name="Name">Sky</string>
        <bool name="CelestialBodiesShown">false</bool>
%s
        <int name="StarCount">0</int>
      </Properties>
    </Item>
  </Item>
</roblox>
""" % faces_xml
    fd, path = tempfile.mkstemp(suffix=".rbxlx")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    return path


def rojo771(faces):
    """The faces as Rojo 7.7.1 writes them: the Content name, the id in a <uri> child."""
    return "\n".join('        <Content name="%s">\n          <uri>%s</uri>\n        </Content>' % (STORED[k], v)
                     for k, v in sorted(faces.items()))


def legacy(faces):
    """The faces under the project's own names, the id in a <url> child (an older Rojo)."""
    return "\n".join('        <Content name="%s"><url>%s</url></Content>' % (k, v) for k, v in sorted(faces.items()))


def run(faces_xml):
    path = place(faces_xml)
    try:
        index, _ = V.read_place(path)
    finally:
        os.remove(path)
    return V.check_properties([(("Lighting", "Sky"), WANTED), (("Lighting",), {"Technology": "ShadowMap"})], index)


# 1. Rojo 7.7.1's names: all six faces found, no problems
problems, lines = run(rojo771(FACES))
check(problems == [], "Rojo 7.7.1 Content names (SkyboxBackContent ...) match the project's SkyboxBk ...", problems)
check(any("SkyboxBk = rbxassetid://1001" in l and "'rbxassetid://1001'" in l for l in lines),
      "the stored face id is read from the <uri> child", lines)

# 2. one face with another id is a problem that names the face
wrong = dict(FACES, SkyboxLf="rbxassetid://9999")
problems, _ = run(rojo771(wrong))
check(len(problems) == 1 and "SkyboxLf" in problems[0] and "9999" in problems[0] and "1004" in problems[0],
      "a face with another id than the project's is one problem naming it", problems)

# 3. Left / Right swapped in the place is two problems
swapped = dict(FACES, SkyboxLf=FACES["SkyboxRt"], SkyboxRt=FACES["SkyboxLf"])
problems, _ = run(rojo771(swapped))
check(len(problems) == 2 and all(("SkyboxLf" in p) != ("SkyboxRt" in p) for p in problems),
      "Lf / Rt swapped in the place: two problems", problems)

# 4. a missing face is a problem
missing = {k: v for k, v in FACES.items() if k != "SkyboxUp"}
problems, _ = run(rojo771(missing))
check(len(problems) == 1 and "SkyboxUp" in problems[0] and "not in the place" in problems[0],
      "a face that is not in the place is one problem", problems)

# 5. the legacy names (an older Rojo, <url> child) still pass
problems, _ = run(legacy(FACES))
check(problems == [], "the project's own names with a <url> child still match", problems)

# 6. the real default.project.json: its Lighting Sky node's six faces are among the checked properties
_, wanted_props = V.project_mounts(os.path.join(V.ROOT, "default.project.json"))
skies = [(path, props) for path, props in wanted_props if path[:1] == ("Lighting",) and len(path) == 2]
check(len(skies) == 1 and all(k in skies[0][1] for k in FACES), "default.project.json has one Lighting Sky with six faces",
      [p for p, _ in skies])

print("%d failed" % len(failures) if failures else "all passed")
sys.exit(1 if failures else 0)
