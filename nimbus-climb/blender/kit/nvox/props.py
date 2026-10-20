"""World kit pieces (design unit = 1 stud, ground at y = 0, the front faces -Z like every Roblox model).

* portal(K):  the lobby portal gate EXACTLY as LobbyBuilder built it at the Phase 4 release (git 7aa0df2,
  gateBoxes / buildPortal: 1-stud voxels) re-sculpted at K voxels per stud with more detail: stone courses and
  mortar on the pillars, a two-tone spiral in the swirl, gold studs on the ring, a faceted keystone gem, a tiled
  ready pad with bevelled tiles and a glowing diamond, and the two lanterns.  Tint per difficulty: the Trim / Glow /
  Swirl / pad regions follow Look.Primary (= the difficulty colour); Star1..Star5 are separate parts so the loader
  lights the first <stars> of them (gold Neon) and dims the rest (StarOff).
* cloud_platform(K): a puffy voxel cloud island (Phase 4 VX.Cloud tiers + puffs) with the lobby's cloud shades.
"""
import math

from .grid import VoxelGrid, angles

P4 = {  # LobbyBuilder C palette at 7aa0df2
    "CloudLight": (244, 247, 252), "Cloud": (232, 238, 249), "CloudShade": (212, 222, 241), "Mist": (194, 211, 240),
    "MistDark": (170, 190, 228), "Stone": (208, 202, 190), "StoneLight": (226, 221, 209), "StoneDark": (172, 164, 154),
    "StoneEdge": (146, 138, 132), "Iron": (64, 70, 92), "IronLight": (96, 104, 130), "Gold": (244, 198, 84),
    "GoldDark": (206, 154, 62), "StarOff": (96, 104, 136), "Lamp": (255, 214, 140),
}


def RGB(name):
    return ["rgb"] + list(P4[name])


def p4_roundrect(g, key, cx, cz, sx, sz, rnd, y0, y1, **kw):
    """VX.RoundRect of the 1-stud lobby grid (integer voxel rows y0..y1 sit on [y, y + 1] in world studs)."""
    g.rbox(key, (cx, (y0 + y1 + 1) / 2.0, cz), (sx + 1, y1 - y0 + 1, sz + 1), round=rnd + 0.5, **kw)


def p4_fill(g, key, x0, x1, y0, y1, z0, z1, **kw):
    g.box(key, ((x0 + x1) / 2.0, (y0 + y1 + 1) / 2.0, (z0 + z1) / 2.0), (x1 - x0 + 1, y1 - y0 + 1, z1 - z0 + 1), **kw)


PAD_SHIFT = (0.125, 0.125, 0.125)  # half a pad voxel (studs): voxel faces on stud lines, the top at 0.25


def portal(K=2.0):
    """returns (gate grid, pad grid, lantern grid, recipes, translucent, neon keys); pivot = pad centre on the ground,
    the gate stands 9.5 studs behind it (+Z), facing the plaza (-Z)."""
    GZ = 9.5
    g = VoxelGrid(K, half=int(26 * K) + 4, name="Gate")
    ring = angles(math.pi / 2, 0, 0)
    eps = 0.5 / K * 0.5  # the old 1-stud grid's 0.25-voxel bias, minus ours
    # base slab and plinth (StoneDark under Stone)
    p4_roundrect(g, "StoneDark", 0, GZ, 22, 5, 1.5, 0, 0)
    p4_roundrect(g, "Stone", 0, GZ, 20, 4, 1.2, 1, 1)
    for s in (-1, 1):
        # pillar with stone courses: alternate rows of slightly inset darker mortar lines every 1.5 studs
        p4_roundrect(g, "Stone", s * 9, GZ, 3, 3.4, 0.8, 2, 10)
        # (positions on the voxel lattice: y * K and x * K integers)
        for i in range(6):
            y = round((2.5 + i * 1.5) * K) / K
            g.box("Mortar", (s * 9, y, GZ), (5, 1.0 / K, 5), op="paint", only="Stone")
        # vertical joints, staggered per course
        for i in range(5):
            y = round((3.25 + i * 1.5) * K) / K
            off = 0.5 if i % 2 else -0.5
            g.box("Mortar", (s * 9 + off, y, GZ), (1.0 / K, 1.0, 5), op="paint", only="Stone")
        p4_roundrect(g, "Trim", s * 9, GZ, 4, 4.2, 1, 11, 11)
        p4_fill(g, "Glow", s * 9, s * 9, 12, 13, 0 + GZ, 0 + GZ)
        p4_fill(g, "Trim", s * 9, s * 9, 3, 3, -2 + GZ, -2 + GZ)
        # pillar foot: a little cloud puff on each side of the pillar (cute, P4 lobby clouds)
        for dx, dz, r in ((-1.7, -1.6, 1.1), (1.6, -1.8, 0.9), (0.2, -2.2, 0.8)):
            g.ell("Puff", (s * 9 + dx, 2.4, GZ + dz), (r * 1.25, r * 0.8, r), keep=True)
    cy = 11.5
    g.torus("Frame", (0, cy, GZ), 7.6, 1.6 + eps, rot=ring)
    g.torus("Glow", (0, cy, GZ), 5.9, 0.5 + eps, rot=ring)
    # swirl: a two-tone spiral (Swirl / SwirlB) in the translucent disc
    def spiral(x, y, z, cur):
        out = []
        for xi, yi in zip(x, y):
            dx, dy = xi, yi - cy
            r = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            band = (a + r * 0.75) % (math.pi * 2 / 3)
            out.append("SwirlB" if band < 0.75 else None)
        return out
    g.ell("Swirl", (0, cy, GZ), (5.3, 5.3, 0.2 + 1.0 / K), keep=True, pattern=spiral)
    # the outer band of the frame takes the difficulty colour
    def band(x, y, z, cur):
        return ["Trim" if math.hypot(xi, yi - cy) >= 8.6 else False for xi, yi in zip(x, y)]
    g.torus("Trim", (0, cy, GZ), 7.6, 2.2 + eps, rot=ring, op="paint", only="Frame", pattern=band)
    # gold studs around the ring face (front and back)
    for i in range(12):
        a = i / 12 * math.pi * 2 + math.pi / 12
        for zz in (-1.75, 1.75):
            g.ell("Gold", (math.cos(a) * 7.6, cy + math.sin(a) * 7.6, GZ + zz), (0.42, 0.42, 0.3))
    # keystone with a faceted gold gem facing the plaza
    p4_roundrect(g, "Trim", 0, GZ, 4, 3, 0.8, 19, 20)
    # ready pad: the old 14 x 14 one-stud tiles, at PK = 4 voxels per stud, set voxel by voxel (tile edges must fall
    # on voxel boundaries: the mesh is shifted by half a voxel, see PAD_SHIFT) with a darker groove between tiles
    PK = 4
    pad = VoxelGrid(PK, half=7 * PK + 4, name="Pad")
    for n in range(-7 * PK, 7 * PK):
        for m in range(-7 * PK, 7 * PK):
            i, k = n // PK, m // PK
            ring_i = min(i + 7, 6 - i, k + 7, 6 - k)
            di = abs(i + 0.5) + abs(k + 0.5)
            key = "PadStone" if (i + k) % 2 == 0 else "PadStoneB"
            if ring_i == 0:
                key = "Trim"
            elif ring_i == 1:
                key = "StoneLight"
            elif di <= 1.5:
                key = "GlowCore"
            elif di <= 2.5:
                key = "Glow"
            if key in ("PadStone", "PadStoneB", "StoneLight") and (n % PK == PK - 1 or m % PK == PK - 1):
                key = "Groove"
            pad.set(n, 0, m, key)
    # gold corner studs on the trim ring (one voxel proud)
    for sx in (-1, 1):
        for sz in (-1, 1):
            for dn in (0, 1):
                for dm in (0, 1):
                    pad.set(int(sx * 6.5 * PK) - 1 + dn, 1, int(sz * 6.5 * PK) - 1 + dm, "Gold")

    # lanterns on the two front corners of the pad
    lan = VoxelGrid(K * 2, half=int(26 * K * 2) + 4, name="Detail")
    for sx in (-1, 1):
        bx, bz = sx * 7.9, -7.9
        lan.box("Iron", (bx, 0.15, bz), (1.0, 0.3, 1.0))
        lan.box("Iron", (bx, 1.6, bz), (0.6, 3.0, 0.6))
        lan.box("IronLight", (bx, 3.1, bz), (0.9, 0.2, 0.9))
        lan.box("Lamp", (bx, 3.6, bz), (0.75, 0.8, 0.75))
        for cx in (-1, 1):
            for cz in (-1, 1):
                lan.box("Iron", (bx + cx * 0.4, 3.6, bz + cz * 0.4), (0.15, 0.85, 0.15))
        lan.rbox("IronLight", (bx, 4.15, bz), (1.15, 0.3, 1.15), round=0.1)
        lan.cone("Iron", (bx, 4.3, bz), (bx, 4.85, bz), 0.45, 0.05)
    # keystone gem and star crest at the fine grain too (crisp diamonds)
    lan.ell("Gem", (0, 20.0, GZ - 2.0), (0.75, 1.15, 0.55))
    lan.ell("GemLight", (0.25, 20.4, GZ - 2.3), (0.3, 0.35, 0.3), op="paint", only="Gem")
    # star crest: post, bar and five star gems (separate parts; the loader lights the first <stars>)
    lan.box("GoldDark", (0, 21.6, GZ), (0.8, 1.3, 0.6))
    lan.box("GoldDark", (0, 22.45, GZ), (11.6, 0.5, 0.5))
    for sidx in range(1, 6):
        gx = (3 - sidx) * 2.6
        lan.box("Star%d" % sidx, (gx, 23.6, GZ), (1.5, 1.5, 0.8), rot=angles(0, 0, math.radians(45)))
        lan.box("Star%d" % sidx, (gx, 23.6, GZ - 0.3), (0.8, 0.8, 0.5), rot=angles(0, 0, math.radians(45)))


    P = ["Primary"]
    rec = {
        "Stone": RGB("StoneLight"), "StoneDark": RGB("Stone"), "Mortar": RGB("StoneDark"), "Frame": RGB("CloudLight"),
        "Puff": RGB("Cloud"), "Trim": P, "Glow": P, "GlowCore": ["mix", P, ["rgb", 255, 255, 255], 0.45],
        "Swirl": ["mix", P, ["rgb", 255, 255, 255], 0.35], "SwirlB": ["mix", P, ["rgb", 255, 255, 255], 0.6],
        "Gold": RGB("Gold"), "GoldDark": RGB("GoldDark"), "Gem": RGB("Gold"), "GemLight": ["rgb", 255, 240, 190],
        "PadStone": RGB("Stone"), "PadStoneB": ["rgb", 214, 208, 196], "StoneLight": RGB("StoneLight"),
        "Groove": RGB("StoneDark"), "Iron": RGB("Iron"), "IronLight": RGB("IronLight"), "Lamp": P,
    }
    for sidx in range(1, 6):
        rec["Star%d" % sidx] = RGB("Gold")
    translucent = {"Swirl": 0.62, "SwirlB": 0.5}
    neon = {"Glow", "GlowCore", "Swirl", "SwirlB", "Gem", "GemLight", "Lamp"} | {"Star%d" % i for i in range(1, 6)}
    return g, pad, lan, rec, translucent, neon


def cloud_platform(K=1.5, seed=3):
    """a walkable cloud island ~20 x 16 studs, top surface at y = 0 (Phase 4 VX.Cloud: tiers + puffs + rim)."""
    g = VoxelGrid(K, half=int(16 * K) + 6, name="Cloud")
    # rounded body: a flattened ellipsoid cut flat at the walking surface (y = 0) plus a smaller lower lobe
    g.ell("Cloud", (0, -1.2, 0), (10.2, 3.0, 8.2))
    g.ell("Cloud", (0.6, -3.6, -0.4), (7.2, 2.6, 5.6))
    g.carve("box", center=(0, 3, 0), size=(40, 6, 40))
    g.paint("Top", "box", only="Cloud", center=(0, -0.25, 0), size=(40, 0.5, 40))
    rnd = [((i * 7919 + seed * 104729) % 1000) / 1000.0 for i in range(64)]
    # side puffs (soft bulges, shaded) around the rim and under it
    n = 14
    for i in range(n):
        a = i / n * math.pi * 2
        rx, rz = 9.6 * math.cos(a), 7.6 * math.sin(a)
        r = 1.7 + rnd[i] * 1.2
        g.ell("Puff", (rx, -1.4 - rnd[i + 20] * 1.2, rz), (r * 1.15, r * 0.9, r), keep=True)
    for i in range(7):
        a = i / 7 * math.pi * 2 + 0.3
        g.ell("Puff", (6.0 * math.cos(a), -4.6 - rnd[i + 40] * 1.0, 4.6 * math.sin(a)), (2.4, 1.6, 2.2), keep=True)
    # rim puffs that rise a little above the walking surface at the back and sides (not in the front)
    for i, (x, z, r) in enumerate([(-8.6, 3.5, 1.6), (-4.5, 6.6, 1.9), (0.5, 7.3, 1.7), (5.2, 6.4, 1.8), (8.8, 2.6, 1.5)]):
        g.ell("Rim", (x, 0.2, z), (r * 1.2, r * 0.85, r), keep=True)
    rec = {"Top": ["rgb", 244, 247, 252], "Cloud": ["rgb", 232, 238, 249], "Puff": ["rgb", 232, 238, 249],
           "Rim": ["rgb", 232, 238, 249]}
    # the lobby's explicit cloud shades (VX.Cloud Remap): light -> CloudLight, dark -> Mist / CloudShade
    shade_rgb = {
        "Puff": {1: P4["CloudLight"], -1: P4["Mist"], -2: P4["MistDark"]},
        "Rim": {1: P4["CloudLight"], -1: P4["CloudShade"], -2: P4["Mist"]},
        "Cloud": {1: P4["CloudLight"], -1: P4["CloudShade"], -2: P4["Mist"]},
        "Top": {1: P4["CloudLight"], -1: P4["CloudShade"], -2: P4["Mist"]},
    }
    return g, rec, shade_rgb
