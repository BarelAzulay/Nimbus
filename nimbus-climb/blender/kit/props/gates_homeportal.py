"""The player's home portal (client/Controllers/HomePortalFx.lua; bug 2026-10-24 "improve home gate", the approved
pitch A "Homestead Trellis" with the player's note "less childy, more vortex style, not too big but enough for a
body size").

One key, `gate_homeportal`: a small homestead gate a player summons for 10 s. It is NOT a BuildGate gate (those are the
23-stud Gate Court gates in gates.py); HomePortalFx builds it on the client with MeshLibrary.Assemble and falls back
to its own Part copy of the same silhouette while the key is not usable.

    weathered stone pillars (coursed, staggered joints recessed one voxel, chipped corners, warm odd stones, grime at
    the foot) on plinths, impost caps, a laminated oak arch bound by two aged-bronze straps with brass rivets, an oak
    keystone with a brass-rimmed enamel plate (the player's portal colour, ["Primary"] darkened) and an embossed brass
    house, a worn threshold slab with a loose stone, asymmetric ivy (climbing the -X pillar: the RIGHT one as
    you face the portal; a tuft at the +X pillar's foot).
    No cartoon cottage, no bird, no toy colours.

Opening (walk-through): 4 studs wide (pillar inner faces at x = +-2), from the threshold top (y 0.5) to the arch
crown (y 7.5): 7 studs, an R15 avatar (~5.3 tall) passes with margin.  Overall ~8 x 9 x 3 studs (stone 7.5 wide).
The vortex (the Neon backdrop and core Parts + the Gate Court gates' PortalVortex) stays in HomePortalFx: this mesh leaves the
opening empty (pillar depth 2 = the recess the vortex sits in).

Frame: the floor point under the portal centre, front = -Z (HomePortalFx's frame faces the owner with -Z); 0.25-stud
voxels (K 4) for the body, 0.125 (K 8) for the plate.  HomePortalFx places the manifest pivot on the floor point
(Assemble At = frame * (0, -CENTER_Y, 0)).  Lat cells span [n V, (n + 1) V): every bound here is a multiple of V.
"""
import math

import numpy as np

from props import prop
from props.gates import Lat

PAL = {
    "Stone": (226, 221, 209),       # the Gate Court StoneLight (one family with the gates)
    "StoneWarm": (216, 208, 192),   # odd stones of another quarry batch
    "StoneGrime": (196, 189, 176),  # the foot course: splash dirt
    "Mortar": (186, 180, 170),
    "SlabStone": (206, 200, 188),   # threshold + plinths + caps (the gates' slab stone)
    "SlabWorn": (218, 213, 203),    # the threshold's middle, polished by feet
    "Edge": (168, 160, 150),        # the slab's lower lip
    "Oak": (165, 125, 85),          # Gemini: soft weathered oak
    "OakDark": (125, 85, 55),       # butt joints / the keystone
    "OakSeam": (150, 110, 74),      # the glue line between the arch plies (a hairline)
    "Bronze": (92, 76, 64),         # Gemini: aged bronze straps (not gothic black iron)
    "Brass": (196, 160, 86),        # muted brass (rivets, plate rim, emblem)
    "IvyBase": (106, 142, 100),
    "IvyTip": (150, 186, 136),
    "IvyStem": (96, 98, 70),
}
TINTED = {"Enamel": ["mix", ["Primary"], ["rgb", 34, 42, 76], 0.65]}  # dark enough for the brass house to pop (Gemini)
OWN = {"Stone"}

CENTER_X = 2.0          # pillar inner faces (half the opening)
PILLAR_OUT = 3.5        # pillar outer faces
PILLAR_Z = 1.0          # pillar half depth
PILLAR_TOP = 5.0
CAP_TOP = 5.5           # = the arch springing line (arch centre (0, 5.5))
ARCH_R0, ARCH_R1 = 2.0, 3.0
ARCH_Z = 0.75
THRESH_TOP = 0.5
V = 0.25                # body voxel (studs)
PV = 0.125              # plate voxel


def cc(v, step=V):
    """the centre of the cell that holds coordinate v"""
    return math.floor(v / step + 1e-9) * step + step / 2


def cell(G, key, x, y, z, keep=False):
    """one body voxel: the cell holding (x, y, z)"""
    G.put(key, G.cbox((cc(x), cc(y), cc(z)), (V * 0.9, V * 0.9, V * 0.9)), keep=keep)


def threshold(G):
    """a slab of three stones (seams), a darker lower lip, the middle polished by feet, a hairline crack, a loose stone
    resting against its +X end (the LEFT end as you face the portal)"""
    G.put("SlabStone", G.rrect(0, 0, 3.75, 1.5, 0.5, 0, THRESH_TOP))
    G.put("Edge", G.rrect(0, 0, 3.75, 1.5, 0.5, 0, 0.25) & ~G.rrect(0, 0, 3.5, 1.25, 0.25, 0, 0.25))
    for x in (-1.25, 1.0):
        G.paint("Mortar", G.box(x, x + V, 0.25, THRESH_TOP, -2, 2), only="SlabStone")
    G.paint("SlabWorn", G.ell((0, THRESH_TOP, -0.25), (1.6, 0.2, 1.1)) & (G.Y > 0.25), only="SlabStone")
    for x, z in ((1.5, -1.25), (1.75, -1.0), (1.75, -0.75), (2.0, -0.5)):
        G.paint("Mortar", G.box(x, x + V, 0.25, THRESH_TOP, z, z + V), only=["SlabStone", "SlabWorn"])
    G.put("StoneWarm", G.box(3.75, 4.25, 0, 0.5, -1.25, -0.75))
    G.put("StoneWarm", G.box(4.25, 4.5, 0, 0.25, -1.0, -0.75))


def pillar(G, s, r):
    """a coursed stone pillar (1.5 x 2 studs): plinth, five 0.75 courses with staggered joints recessed one voxel,
    a grimy foot course, a few warm stones, chipped vertical corners, the impost cap"""
    x0, x1 = sorted((s * CENTER_X, s * PILLAR_OUT))
    xin = x0 if s > 0 else x1   # the face toward the opening
    xout = x1 if s > 0 else x0
    G.put("SlabStone", G.box(x0 - V, x1 + V, THRESH_TOP, 1.25, -PILLAR_Z - V, PILLAR_Z + V))
    shaft = G.box(x0, x1, 1.25, PILLAR_TOP, -PILLAR_Z, PILLAR_Z)
    G.put("Stone", shaft)
    shell = shaft & ((G.X < x0 + V) | (G.X > x1 - V) | (np.abs(G.Z) > PILLAR_Z - V))
    joints = np.zeros(G.L.shape, bool)
    for i, y in enumerate(np.arange(1.25, PILLAR_TOP - 0.01, 0.75)):
        top = min(y + 0.75, PILLAR_TOP)
        band = shaft & (G.Y > y) & (G.Y < top)
        if i > 0:
            joints |= shaft & (G.Y > y) & (G.Y < y + V)
        # vertical joints, staggered course by course: the 1.5 width (6 cells) at cell 2 / 3, the 2-stud depth at 3 / 5
        jx = cc(x0 + (2 if i % 2 == 0 else 3) * V)
        jz = cc(-PILLAR_Z + (3 if i % 2 == 0 else 5) * V)
        joints |= band & (np.abs(G.X - jx) < V / 2) & (np.abs(G.Z) > PILLAR_Z - 2 * V)
        joints |= band & (np.abs(G.Z - jz) < V / 2) & ((G.X < x0 + 2 * V) | (G.X > x1 - 2 * V))
        # a warm stone now and then (one block of the course, chosen by the seed)
        if r.random() < 0.7:
            sx = (G.X < jx) if r.random() < 0.5 else (G.X > jx)
            sz = (G.Z < jz) if r.random() < 0.5 else (G.Z > jz)
            G.paint("StoneWarm", band & sx & sz & ~joints, only="Stone")
    G.paint("StoneGrime", shaft & (G.Y < 2.0) & ~joints, only=["Stone", "StoneWarm"])
    G.put("Mortar", joints & ~shell)
    G.carve(joints & shell)
    # chipped corners: single voxels off the vertical edges, more of them low down (weather + knocks)
    for _ in range(10):
        y = 1.25 + (PILLAR_TOP - 1.5) * r.random() ** 1.6
        ex = (x0 + V / 2) if r.random() < 0.5 else (x1 - V / 2)
        ez = (-PILLAR_Z + V / 2) if r.random() < 0.65 else (PILLAR_Z - V / 2)
        for k in range(1 + int(r.integers(0, 2))):
            G.carve(G.cbox((cc(ex), cc(y) + k * V, cc(ez)), (V * 0.9, V * 0.9, V * 0.9)))
    # impost cap: a moulding layer, then a cornice (0.25 over the opening, 0.5 outside); grime where the oak sits
    G.put("SlabStone", G.box(x0 - V, x1 + V, PILLAR_TOP, PILLAR_TOP + V, -PILLAR_Z - V, PILLAR_Z + V))
    ux0, ux1 = sorted((xin - V * s, xout + 2 * V * s))
    G.put("SlabStone", G.box(ux0, ux1, PILLAR_TOP + V, CAP_TOP, -PILLAR_Z - 2 * V, PILLAR_Z + 2 * V))
    ax0, ax1 = sorted((s * (ARCH_R0 - V), s * (ARCH_R1 + V)))
    G.paint("StoneGrime", G.box(ax0, ax1, CAP_TOP - V, CAP_TOP, -2, 2) & (np.abs(G.Z) > ARCH_Z), only="SlabStone")


AV = 0.125              # arch voxel (polish 2026-10-27: the 0.25 arch stair-stepped into lumps)
PLY = (ARCH_R0 + ARCH_R1) / 2   # the glue line between the two equal 0.5-stud plies
KEY_HW, KEY_Y0, KEY_Y1 = 0.875, 7.25, 9.0  # the keystone (1.75 wide, its front face 0.25 proud of the arch faces)


def on_circle(A, cx, cy, R):
    """the supercover of the circle r = R in the XY plane: every cell the curve passes through (a clean, gap-free
    1-cell line on any lattice; a plain |r - R| < AV / 2 test breaks into diagonal speckle)"""
    dx, dy = A.X - cx, A.Y - cy
    r = np.sqrt(dx ** 2 + dy ** 2) + 1e-9
    reach = AV / 2 * (np.abs(dx) + np.abs(dy)) / r
    return np.abs(r - R) < reach


def on_ray(A, cx, cy, deg):
    """the supercover of the ray from (cx, cy) at `deg` (0 = +X, counter-clockwise) in the XY plane"""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    dx, dy = A.X - cx, A.Y - cy
    reach = AV / 2 * (abs(c) + abs(s))
    return (np.abs(-s * dx + c * dy) < reach) & (c * dx + s * dy > 0)


def arch(A):
    """a bent-laminated oak arch on its own 0.125 lattice (a clean, even curve): two equal plies (a faint glue line at
    r 2.5), butt joints staggered between the plies (outer ply at 30 / 150 degrees, inner ply at 60 / 120, the crown
    joint under the keystone); bronze shoes where the timber stands on the stone caps; two flat aged-bronze straps at
    45 / 135 degrees binding both plies between the joints (proud on the faces and the back, the soffit line left
    clean) with two brass rivets on each face; a squared dark-oak keystone with a bronze cap.  Polish 2026-10-27:
    no planed-arris carve and flat oak shading (on a stair-stepped curve both made the blotchy, lumpy read)."""
    r = np.sqrt(A.X ** 2 + (A.Y - CAP_TOP) ** 2)
    ang = np.degrees(np.arctan2(A.Y - CAP_TOP, A.X))  # 0 = right springing, 90 = crown, 180 = left
    az = np.abs(A.Z)
    up = A.Y > CAP_TOP
    body = (r >= ARCH_R0) & (r < ARCH_R1) & up & (az < ARCH_Z)
    A.put("Oak", body)
    face = az > ARCH_Z - AV
    # the glue line between the plies, on the faces only (a hairline, not a groove)
    A.paint("OakSeam", body & face & on_circle(A, 0.0, CAP_TOP, PLY))
    # butt joints: a dark line drawn across the faces and the soffit of each ply, a 1-cell groove only on the
    # extrados skin (fix round 2026-10-27: a groove carved along a stair-stepped diagonal on the faces read as a
    # jagged notch beside each strap; on the back the step direction hides the groove)
    for c, inner in ((30.0, False), (150.0, False), (60.0, True), (120.0, True)):
        ply = (r < PLY) if inner else (r >= PLY)
        line = body & ply & on_ray(A, 0.0, CAP_TOP, c)
        ext = r >= ARCH_R1 - AV
        A.carve(line & ext)
        A.paint("OakDark", line & ~ext)
    # bronze shoes: the arch feet stand in a flat bronze band (one cell proud, 3 cells high) on the caps
    for s_ in (-1, 1):
        x0, x1 = sorted((s_ * (ARCH_R0 - AV), s_ * (ARCH_R1 + AV)))
        A.put("Bronze", A.box(x0, x1, CAP_TOP, CAP_TOP + 3 * AV, -ARCH_Z - AV, ARCH_Z + AV)
              & ~A.box(-ARCH_R0, ARCH_R0, 0, 99, -9, 9))
    # the straps: flat bronze bands 2 cells wide, one cell proud on the faces and the back; no lip under the soffit
    for a in (45.0, 135.0):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        along = -s * A.X + c * (A.Y - CAP_TOP)  # signed distance across the strap's centre line
        strap = (r >= ARCH_R0) & (r < ARCH_R1 + AV) & (np.abs(along) < AV) & (az < ARCH_Z + AV) & up
        A.put("Bronze", strap)
        for rr in (2.25, 2.75):
            px, py = c * rr, CAP_TOP + s * rr
            for z in (-ARCH_Z - 1.5 * AV, ARCH_Z + 1.5 * AV):
                A.put("Brass", A.cbox((px, py, z), (AV * 0.9,) * 3))
    # the keystone: dark oak, 1.75 x 1.75, its faces 0.25 proud of the arch faces, a bronze cap
    kz = ARCH_Z + 2 * AV
    A.put("OakDark", A.box(-KEY_HW, KEY_HW, KEY_Y0, KEY_Y1, -kz, kz))
    A.put("Bronze", A.box(-KEY_HW - AV, KEY_HW + AV, KEY_Y1, KEY_Y1 + AV, -kz, kz))


def ivy(G, r):
    """asymmetric ivy: a stem climbing the -X pillar's front face (the RIGHT pillar as you face the portal; front =
    -Z) near its outer edge to ~4.6 studs (leaves on the front and round the corner on the outer face), a spray at the
    top, a small tuft at the +X (left) pillar's foot"""
    zf = -PILLAR_Z - V / 2          # the cell layer just in front of the pillar face
    xs = -PILLAR_OUT - V / 2        # the cell layer just outside the outer face

    def leaf(x, y, z, side=False):
        key = "IvyTip" if r.random() < 0.35 else "IvyBase"
        if side:
            G.put(key, G.box(cc(xs) - V / 2, cc(xs) + V / 2, cc(y) - V / 2, cc(y) + 1.5 * V, cc(z) - V / 2, cc(z) + 1.5 * V), keep=True)
        else:
            G.put(key, G.box(cc(x) - V / 2, cc(x) + 1.5 * V, cc(y) - V / 2, cc(y) + 1.5 * V, cc(zf) - V / 2, cc(zf) + V / 2), keep=True)

    x = -PILLAR_OUT + 1.5 * V
    y = 1.25
    while y < 4.6:
        cell(G, "IvyStem", x, y, zf, keep=True)
        if r.random() < 0.5:
            leaf(x + r.choice((-2 * V, V)), y, zf)
        if r.random() < 0.4:
            leaf(xs, y, -PILLAR_Z + V * int(r.integers(0, 4)), side=True)
        y += V
        x = min(-CENTER_X - 2 * V, max(-PILLAR_OUT + V / 2, x + r.choice((-V, 0, 0, V))))
    for dx, dy in ((0.0, 4.75), (0.5, 4.5), (-0.25, 4.25), (0.75, 4.0)):
        leaf(-PILLAR_OUT + 0.5 + dx, dy, zf)
    # the vine wraps round the outer face onto the back (a few leaves near the back-outer corner: no barren back)
    zb = PILLAR_Z + V / 2
    for dx, dy in ((0.0, 2.0), (0.25, 2.75), (0.0, 3.5), (0.5, 3.25), (0.0, 4.25)):
        key = "IvyTip" if r.random() < 0.35 else "IvyBase"
        G.put(key, G.box(-PILLAR_OUT + dx, -PILLAR_OUT + dx + 2 * V, dy, dy + 2 * V, cc(zb) - V / 2, cc(zb) + V / 2), keep=True)
    # leaves spilling on the plinth
    G.put("IvyBase", G.box(-PILLAR_OUT - V, -PILLAR_OUT + 0.5, 1.25, 1.5, -PILLAR_Z - 2 * V, -PILLAR_Z - V), keep=True)
    # the +X pillar (the viewer's left): only a little tuft at the foot
    for dx, dy, key in ((0.25, 1.25, "IvyBase"), (0.75, 1.25, "IvyTip"), (0.5, 1.5, "IvyBase")):
        G.put(key, G.box(PILLAR_OUT - dx - V, PILLAR_OUT - dx + V, dy, dy + V, -PILLAR_Z - V, -PILLAR_Z), keep=True)


# the keystone plate, 0.125-stud voxels (11 x 12 cells: 1.375 x 1.5 studs on the 1.75 keystone), one string per row from the top: B brass rim, E enamel (the
# portal colour); EMBLEM is the embossed brass cottage drawn over the enamel: "@" two cells proud (the roof and the
# chimney), "#" one cell proud (the walls), "." the enamel showing (the door).  Polish 2026-10-27: the pentagon house
# on two legs read as a castle / rook; a cottage needs eaves wider than its walls, a chimney on the slope and a door.
PLATE = ["BBBBBBBBBBB"] + ["BEEEEEEEEEB"] * 10 + ["BBBBBBBBBBB"]
EMBLEM = ["...........",
          "...........",
          ".......@...",        # the chimney, rising from the right slope
          ".....@.@...",        # the ridge
          "....@@@@...",
          "...@@@@@@..",
          "..@@@@@@@..",        # the eaves, wider than the walls
          "...#####...",
          "...#####...",        # (Gemini round 1: a door up to the eaves split the house into two legs)
          "...##.##...",        # the door
          "...##.##...",
          "..........."]


def plate(C, top=8.875, zf=-ARCH_Z - 2 * AV, grid=(PLATE, EMBLEM), step=PV):
    """a brass-rimmed enamel plate in the portal colour with an embossed brass cottage; no lettering (Gemini: a
    literal HOME sign reads tacky; the name tag above already says whose portal it is).  `zf` is the face it sits on."""
    rows, emb = grid
    ncol = len(rows[0])
    zp = zf - step / 2               # the plate layer (enamel and rim)
    for row in range(len(rows)):
        y = top - (row + 0.5) * step
        for col in range(ncol):
            x = ((ncol - 1) / 2 - col) * step  # +X is the viewer's left (front = -Z): drawn as seen
            k = rows[row][col]
            C.put("Brass" if k == "B" else "Enamel", C.cbox((x, y, zp), (step * 0.9,) * 3))
            lift = {"#": 1, "@": 2}.get(emb[row][col], 0)
            if k == "B":
                lift = max(lift, 1)  # the rim stands one cell proud: the enamel sits in a shallow tray
            for k2 in range(1, lift + 1):
                C.put("Brass", C.cbox((x, y, zp - k2 * step), (step * 0.9,) * 3))


def recipes(keys):
    return {k: (TINTED[k] if k in TINTED else ["rgb"] + list(PAL[k])) for k in keys}


@prop("home_portal")
def build_home_portal(entry, kit):
    """catalog args: {"K": 4.0, "KA": 8.0, "KC": 8.0, "seed": 7}"""
    args = entry.get("args") or {}
    K = float(args.get("K", 4.0))
    KC = float(args.get("KC", 8.0))
    KA = float(args.get("KA", 8.0))
    r = np.random.default_rng(int(args.get("seed", 7)))
    m = kit.model(entry["key"], "gate", vs=1.0 / K, K=K)
    used = {}
    G = Lat(kit, K, (0, 4.5, 0), 5.0, "Gate")
    threshold(G)
    for s in (-1, 1):
        pillar(G, s, r)
    ivy(G, r)
    gkeys = [k for k in G.g.keys if k and np.any(G.L == G.g.ids[k])]
    fixed = tuple(k for k in gkeys if k not in TINTED and k not in OWN)
    kit.mesh(m, G.g, recipes=recipes(gkeys), group="Gate", vs=1.0 / K, offset=G.offset(), fixed_keys=fixed, used=used,
             shade_opts={"Brass": dict(dark=False), "IvyTip": dict(dark=False)})
    # the arch on a 0.125 lattice (cells span multiples of 0.125: its springing lines up with the 0.25 caps)
    A = Lat(kit, KA, (0, 7.25, 0), 3.5, "Arch")
    arch(A)
    akeys = [k for k in A.g.keys if k and np.any(A.L == A.g.ids[k])]
    afixed = tuple(k for k in akeys if k not in TINTED and k not in OWN)
    kit.mesh(m, A.g, recipes=recipes(akeys), group="Arch", vs=1.0 / KA, offset=A.offset(), fixed_keys=afixed, used=used,
             flat=("Oak", "OakSeam", "OakDark", "Bronze"), shade_opts={"Brass": dict(dark=False)})
    # the plate grid: x cell centres on multiples of 0.125 (origin x -1/16) so the 11-cell plate is centred on x 0
    C = Lat(kit, KC, (-PV / 2, 8.0, -1.0), 1.0, "Crest")
    plate(C)
    ckeys = [k for k in C.g.keys if k and np.any(C.L == C.g.ids[k])]
    cfixed = tuple(k for k in ckeys if k not in TINTED and k not in OWN)
    kit.mesh(m, C.g, recipes=recipes(ckeys), group="Crest", vs=1.0 / KC, offset=C.offset(), fixed_keys=cfixed, used=used,
             shade_opts={"Brass": dict(dark=False), "Enamel": dict(dark=False, light=False)})
    m.meta = {
        "source": "Homestead home portal (pitch A + the player's note), HomePortalFx",
        "pivot": "the floor point under the portal centre, front = -Z (HomePortalFx: Assemble At = frame * (0, -CENTER_Y, 0))",
        "previewLook": {"Primary": [120, 196, 255], "Secondary": [255, 255, 255]},
        "opening": "x -2..2, y 0.5..7.5 (round top: centre (0, 5.5), radius 2); the vortex is Neon Parts (HomePortalFx)",
    }
    return m
