"""cal_axes: the first asset ever uploaded (recipe section 3 item 9 / 4.7 step 1).  One look at it in Studio answers
yaw, mirror, scale, vertex colours, part names, Anchored and PackageLink before any pet goes up:

    ArrowF    a blue "F"-shaped arrow lying flat, pointing to -Z (Roblox forward); the F reads correctly from above
              only when nothing is mirrored
    BarX      a red bar along +X (3 studs), BarY a green bar along +Y (3 studs)
    Cube      a 2-stud cube centred at (0, 1, 0) with a vertex-colour gradient (black corner at -X -Y -Z, red grows
              with +X, green with +Y, blue with +Z): checks colour layer + orientation per face
    Head_Att  a 0.5-stud white cube at (0, 3.5, 0): an importer turns objects named *_Att into Attachments
Pivot = the origin; every size is a whole number of 0.25-stud voxels, so measured sizes reveal the import scale.
"""
from nvox.build import ModelSpec
from nvox.parts import add_baked

VS = 0.25


def build_cal_axes(entry):
    m = ModelSpec(entry.get("key", "cal_axes"), "calibration", VS, 1.0)
    cube = {}
    for x in range(-4, 4):
        for y in range(0, 8):
            for z in range(-4, 4):
                cube[(x, y, z)] = ((x + 4) / 7.0, (y) / 7.0, (z + 4) / 7.0)
    add_baked(m, cube, "Cube", vs=VS, offset=(VS / 2, VS / 2, VS / 2))
    add_baked(m, {(x, 0, 0): (1.0, 0.16, 0.16) for x in range(5, 17)}, "BarX", vs=VS, offset=(0, VS / 2, 0))
    add_baked(m, {(0, y, 0): (0.16, 0.85, 0.24) for y in range(9, 21)}, "BarY", vs=VS)
    arrow = {}
    for z in range(-20, -5):  # the stem towards -Z
        arrow[(0, 0, z)] = (0.2, 0.42, 1.0)
        arrow[(1, 0, z)] = (0.2, 0.42, 1.0)
    for x in range(1, 7):  # the F's top bar at the tip and a shorter middle bar, both towards +X
        arrow[(x, 0, -20)] = (0.2, 0.42, 1.0)
        arrow[(x, 0, -19)] = (0.2, 0.42, 1.0)
    for x in range(1, 5):
        arrow[(x, 0, -14)] = (0.2, 0.42, 1.0)
        arrow[(x, 0, -13)] = (0.2, 0.42, 1.0)
    for d in range(1, 4):  # arrow head barbs at the tip
        arrow[(-d, 0, -20 + d)] = (0.2, 0.42, 1.0)
    add_baked(m, arrow, "ArrowF", vs=VS, offset=(0, VS / 2, 0))
    add_baked(m, {(x, y, z): (1.0, 1.0, 1.0) for x in (0, 1) for y in (0, 1) for z in (0, 1)}, "Head_Att", vs=VS,
              offset=(0, 3.5 - VS / 2, 0))
    m.groups = {}
    m.attachments = {}
    m.meta = {"class": "calibration", "expect": {
        "ArrowF": "tip at -Z, the F's bars towards +X", "BarX": "+X", "BarY": "+Y",
        "Cube": "2 x 2 x 2 studs, black corner at -X -Y -Z", "Head_Att": "may arrive as an Attachment"}}
    return m
