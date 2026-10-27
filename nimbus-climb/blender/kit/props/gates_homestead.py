"""gate_home in the homestead family (polish 2026-10-27, player-approved): the arena's green Return gate keeps its
Gate Court size, hoop and role (WorldStyle.BuildGate, glyph "house"), but drops the cartoon cottage crest and the
cloud-frame toy look for the home portal's craft language (props/gates_homeportal.py, key gate_homeportal):

    coursed stone pillars (joints recessed one cell, staggered, warm odd stones, chipped corners, grime at the foot)
    under stone impost caps with bronze collars round the Neon cap glows; the hoop as a bent oak ring (12 even
    segments, butt joints every 30 degrees) inside the band in the gate colour (["Primary"], the Trim part), bound by four
    flat bronze straps with brass rivets; a dark-oak keystone with a bronze cap and a brass rim round the Neon gem;
    on top, a dark-oak post carrying a brass-rimmed enamel plate (the gate colour pulled to navy) with an
    embossed brass cottage (pitched roof, chimney, door, two windows; no lettering), flanked by two bronze porch
    lanterns on bracket arms whose glass is the gate's own Neon CrestWindow Parts; ivy on the -X pillar (the viewer's right), a
    tuft and a loose stone at the +X foot.

The contract with WorldStyle.BuildGate is unchanged (see props/gates.py): the frame is the gate's site (front -Z,
ML_Offset (0, -11.5, 0)); the mesh replaces ONLY the GATE_MESH_HIDE Parts (Stone, StoneDark, Frame, Trim, the crest
bodies); the Neon glow ring (r 5.7..6.6), the swirl / PortalVortex, the cap glows (x +-9, y 12..14), the keystone
gems (x -0.5..0.5, y 19..21, z -2.5..-1.5) and the two CrestWindows (x +-1.25, y 23.35..24.05, z -0.725..-0.575)
stay Parts, so this mesh leaves their cells free and sits around them.  The oak ring + band cover the hidden ring
voxels (r 6.6..9.6, |z| < 1.5), so the invisible collision Parts stay inside the visible mesh.

Lattices: slab, caps, ring and keystone on the Gate Court gates' 0.5 cells (K 2, the Part lattice: the same stepped
hoop as its siblings), the pillars and ivy on 0.25 cells (KP 4: where players stand close), the crest on 0.125 cells
(KC 8, x cell centres on multiples of 0.125 so the odd-width plate and emblem are centred on x 0).
"""
import math

import numpy as np

from props import prop
from props.gates import Lat, RING, RING_Y, base_slab
from props.gates_homeportal import PAL as HPAL

PAL = dict(HPAL)
PAL.update({
    "SlabStone": (208, 202, 190),   # the Gate Court base slab (Palette.Stone), as the other gates
    "Edge": (172, 164, 154),
})
TINTED = {"Trim": ["Primary"], "Enamel": ["mix", ["Primary"], ["rgb", 34, 42, 76], 0.65]}
OWN = {"Stone"}

PILLAR_X = 9.0
PILLAR_H = 1.5          # pillar half width (3 x 3 studs, as the Part pillar)
SHAFT_Y0, SHAFT_Y1 = 2.5, 11.0
OAK_Z = 1.25            # the oak ring's half depth (the band in the gate colour stands 0.25 prouder)
BAND_Z = 1.5
KEY_ROWS = ((19.0, 2.0), (19.5, 2.25), (20.0, 2.5), (20.5, 2.75))  # the keystone wedge (as the Part keystone)
WIN_X = 1.25            # the Neon CrestWindows' centres (WorldStyle Crest.house)
CV = 0.125              # crest cell


def cc(v, step):
    return math.floor(v / step + 1e-9) * step + step / 2


def on_ray(G, cx, cy, deg, step):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    dx, dy = G.X - cx, G.Y - cy
    return (np.abs(-s * dx + c * dy) < step / 2 * (abs(c) + abs(s))) & (c * dx + s * dy > 0)


# ---------------------------------------------------------------------------------------------------------------
# the body (0.25 cells)
# ---------------------------------------------------------------------------------------------------------------
def pillar(G, s, r):
    """a 3 x 3 coursed stone pillar at x = 9s: a foot moulding, courses of 1.5 (a 1.0 string course under the cap),
    joints recessed one cell and staggered course by course, warm odd stones, chipped vertical corners, splash grime
    on the two lowest courses"""
    V = 1.0 / G.K
    cx = PILLAR_X * s
    x0, x1 = cx - PILLAR_H, cx + PILLAR_H
    G.put("Stone", G.rrect(cx, 0, 2.0, 2.0, 0.5, 2.0, SHAFT_Y0))  # foot moulding (the Part pillar's)
    shaft = G.box(x0, x1, SHAFT_Y0, SHAFT_Y1, -PILLAR_H, PILLAR_H)
    G.put("Stone", shaft)
    shell = shaft & ((G.X < x0 + V) | (G.X > x1 - V) | (np.abs(G.Z) > PILLAR_H - V))
    joints = np.zeros(G.L.shape, bool)
    ys = [SHAFT_Y0 + 1.5 * i for i in range(6)] + [SHAFT_Y1]
    for i, (y, top) in enumerate(zip(ys, ys[1:])):
        band = shaft & (G.Y > y) & (G.Y < top)
        if i > 0:
            joints |= shaft & (G.Y > y) & (G.Y < y + V)
        jx = cx + (-0.5 if i % 2 == 0 else 0.75)
        jz = -0.75 if i % 2 == 0 else 0.5
        joints |= band & (np.abs(G.X - cc(jx, V)) < V / 2) & (np.abs(G.Z) > PILLAR_H - 2 * V)
        joints |= band & (np.abs(G.Z - cc(jz, V)) < V / 2) & ((G.X < x0 + 2 * V) | (G.X > x1 - 2 * V))
        if r.random() < 0.75:
            sx = (G.X < cc(jx, V)) if r.random() < 0.5 else (G.X > cc(jx, V))
            sz = (G.Z < cc(jz, V)) if r.random() < 0.5 else (G.Z > cc(jz, V))
            G.paint("StoneWarm", band & sx & sz & ~joints, only="Stone")
    G.paint("StoneGrime", shaft & (G.Y < SHAFT_Y0 + 2.0) & ~joints, only=["Stone", "StoneWarm"])
    G.put("Mortar", joints & ~shell)
    G.carve(joints & shell)
    for _ in range(14):
        y = SHAFT_Y0 + (SHAFT_Y1 - SHAFT_Y0 - 0.5) * r.random() ** 1.5
        ex = (x0 + V / 2) if r.random() < 0.5 else (x1 - V / 2)
        ez = (-PILLAR_H + V / 2) if r.random() < 0.65 else (PILLAR_H - V / 2)
        for k in range(1 + int(r.integers(0, 3))):
            G.carve(G.cbox((cc(ex, V), cc(y, V) + k * V, cc(ez, V)), (V * 0.9,) * 3))


def cap(G, s):
    """the impost cap where the Part cap stood (0.5 cells): a moulded stone slab with a darker lip, a bronze collar
    round the Neon glow block"""
    cx = PILLAR_X * s
    G.put("SlabStone", G.rrect(cx, 0, 2.5, 2.5, 0.5, 11.0, 11.5))
    G.paint("Edge", G.rrect(cx, 0, 2.5, 2.5, 0.5, 11.0, 11.5) & ~G.rrect(cx, 0, 2.0, 2.0, 0.5, 11.0, 11.5))
    G.put("SlabStone", G.rrect(cx, 0, 2.0, 2.0, 0.5, 11.5, 12.0))
    G.put("Bronze", G.box(cx - 1.0, cx + 1.0, 12.0, 12.5, -1.0, 1.0) & ~G.box(cx - 0.5, cx + 0.5, 12.0, 12.5, -0.5, 0.5))


def ring(G):
    """the hoop on the Gate Court gates' 0.5 lattice (the same stepped curve as its siblings; 0.25 cells cost ~2.5k
    more triangles): a bent oak ring (r 6.6..8.6, 12 even segments, butt joints every 30 degrees) inside the band
    in the gate colour (r 8.6..9.6), four flat bronze straps (45 / 135 / 225 / 315 degrees) with brass rivets.
    Where the ring passes the pillar shafts (the 0.25 grid) it stops at the shaft (no coplanar faces)."""
    V = 1.0 / G.K
    r = G.radius()
    az = np.abs(G.Z)
    clear = ~((np.abs(np.abs(G.X) - PILLAR_X) < PILLAR_H) & (G.Y < SHAFT_Y1))
    oak = (r >= RING["Inner"]) & (r < RING["Band"]) & (az < OAK_Z) & clear
    G.put("Oak", oak)
    G.put("Trim", (r >= RING["Band"]) & (r < RING["Outer"]) & (az < BAND_Z) & clear)
    face = az > OAK_Z - V
    # the butt joints: 12 even segments (every 30 degrees, the crown one under the keystone), a groove across the
    # faces, dark at the bottom; the straps fall halfway between them.  (Staggering the plies' joints every 15
    # degrees read as scattered dark blotches at 0.5 cells: dropped.)
    for k in range(12):
        c = 30.0 * k
        if k == 3:
            continue
        line = oak & on_ray(G, 0.0, RING_Y, c, V)
        G.carve(line & face)
        G.paint("OakDark", line & ~face)
    for a in (45.0, 135.0, 225.0, 315.0):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        hug = np.where(r < RING["Band"], OAK_Z, BAND_Z) + V   # the strap hugs the oak and the band, one cell proud
        strap = (r >= RING["Inner"]) & (r < RING["Outer"] + V) & on_ray(G, 0.0, RING_Y, a, V) & (az < hug)
        G.put("Bronze", strap)
        for rr in (7.6, 9.1):
            px, py = c * rr, RING_Y + s * rr
            zr = (OAK_Z if rr < RING["Band"] else BAND_Z) + 1.5 * V
            for z in (-zr, zr):
                G.put("Brass", G.cbox((px, py, z), (V * 0.9,) * 3))


def keystone(G):
    """dark oak (the Part keystone's wedge), a bronze cap, a brass rim round the Neon gem socket"""
    for y0, hx in KEY_ROWS:
        G.put("OakDark", G.rrect(0, 0, hx, 1.5, 0.25, y0, y0 + 0.5))
    G.put("Bronze", G.rrect(0, 0, 3.0, 1.5, 0.25, 21.0, 21.5))
    G.put("Brass", G.box(-1.0, 1.0, 18.5, 21.5, -2.0, -1.5) & ~G.box(-0.5, 0.5, 19.0, 21.0, -2.5, -1.5))
    G.carve(G.box(-0.5, 0.5, 19.0, 21.0, -2.5, -1.5))  # the gem's cell stays free
    for s in (-1, 1):  # the Neon cap glow blocks (x +-9, y 12..14) keep their cells: no mesh inside them
        G.carve(G.box(s * PILLAR_X - 0.5, s * PILLAR_X + 0.5, 12.0, 14.0, -0.5, 0.5))


def ivy(G, r):
    """ivy climbing the -X pillar's front face near its outer edge to ~8 studs (leaves round the corner on the outer
    face, a spray at the top), a tuft and a loose stone at the +X pillar's foot"""
    V = 1.0 / G.K
    cx = -PILLAR_X
    zf = -PILLAR_H - V / 2
    xs = cx - PILLAR_H - V / 2

    def leaf(x, y, z=None, side=False, w=2):
        key = "IvyTip" if r.random() < 0.35 else "IvyBase"
        if side:
            G.put(key, G.box(cc(xs, V) - V / 2, cc(xs, V) + V / 2, cc(y, V) - V / 2, cc(y, V) + (w - 0.5) * V,
                             cc(z, V) - V / 2, cc(z, V) + (w - 0.5) * V), keep=True)
        else:
            G.put(key, G.box(cc(x, V) - V / 2, cc(x, V) + (w - 0.5) * V, cc(y, V) - V / 2, cc(y, V) + (w - 0.5) * V,
                             cc(zf, V) - V / 2, cc(zf, V) + V / 2), keep=True)

    x = cx - PILLAR_H + 2.5 * V
    y = 2.25
    while y < 8.25:
        G.put("IvyStem", G.cbox((cc(x, V), cc(y, V), cc(zf, V)), (V * 0.9,) * 3), keep=True)
        if r.random() < 0.55:
            leaf(x + r.choice((-2 * V, V)), y)
        if r.random() < 0.4:
            leaf(None, y, -PILLAR_H + V * int(r.integers(0, 6)), side=True)
        y += V
        x = min(cx + 0.25, max(cx - PILLAR_H + V / 2, x + r.choice((-V, 0, 0, V))))
    for dx, dy in ((0.0, 8.25), (0.75, 8.0), (-0.25, 7.5), (1.0, 7.25), (0.5, 8.5)):
        leaf(cx - PILLAR_H + 0.75 + dx, dy, w=2 + int(r.integers(0, 2)))
    G.put("IvyBase", G.box(cx - PILLAR_H - 2 * V, cx - PILLAR_H + 1.0, 2.0, 2.25, -PILLAR_H - 3 * V, -PILLAR_H), keep=True)
    # the +X pillar: a tuft at the foot and a loose stone on the plinth beside it
    cx2 = PILLAR_X
    for dx, dy, key in ((0.25, 2.5, "IvyBase"), (0.75, 2.5, "IvyTip"), (0.5, 2.75, "IvyBase"), (1.0, 2.5, "IvyBase")):
        G.put(key, G.box(cx2 + PILLAR_H - dx - V, cx2 + PILLAR_H - dx + V, dy, dy + V, -PILLAR_H - V, -PILLAR_H), keep=True)
    G.put("StoneWarm", G.box(cx2 - 3.0, cx2 - 2.5, 2.0, 2.5, -2.0, -1.25))
    G.put("StoneWarm", G.box(cx2 - 2.5, cx2 - 2.25, 2.0, 2.25, -1.75, -1.25))


def body(G, r):
    """the 0.5-cell part: base slab, caps, ring, keystone"""
    base_slab(G)
    for s in (-1, 1):
        cap(G, s)
    ring(G)
    keystone(G)


def pillars(P, r):
    """the 0.25-cell part (where players stand close): the coursed pillars, the ivy, the loose stone"""
    for s in (-1, 1):
        pillar(P, s, r)
    ivy(P, r)
    cling(P)


def cling(G):
    """drop ivy cells that touch nothing but air or other leaves' air (a leaf over a recessed joint or a chip, or a
    spray cell past the pillar): every kept ivy cell has stone, mortar or stem beside it, or ivy that does
    (Gemini round 1: the top spray looked like it hovered off the stone).  Two passes settle chains of leaves."""
    ivy = np.isin(G.L, G.ids(["IvyBase", "IvyTip", "IvyStem"]))
    solid = (G.L != 0) & ~ivy
    for _ in range(3):
        held = np.zeros_like(ivy)
        for ax in range(3):
            for d in (-1, 1):
                held |= np.roll(solid, d, axis=ax)
        keep = ivy & held
        grow = np.zeros_like(ivy)
        for ax in range(3):
            for d in (-1, 1):
                grow |= np.roll(keep, d, axis=ax)
        keep |= ivy & grow
        G.L[ivy & ~keep] = 0
        ivy = keep


# ---------------------------------------------------------------------------------------------------------------
# the crest (0.125 cells): post, enamel plate with the brass cottage, two porch lanterns
# ---------------------------------------------------------------------------------------------------------------
# the plate: 13 x 17 cells (1.625 x 2.125 studs), one string per row from the top; B brass rim, E enamel.  EMBLEM:
# "@" two cells proud (roof, chimney), "#" one cell proud (walls), "." the enamel (door, windows).  Drawn as seen
# from the front.  The same cottage as the home portal's plate, at gate size (two windows by the door).
PLATE = ["B" * 13] + ["B" + "E" * 11 + "B"] * 15 + ["B" * 13]
EMBLEM = ["." * 13,
          "." * 13,
          ".........@...",       # the chimney, rising from the right slope (well clear of the ridge)
          ".........@...",
          "......@..@...",       # the ridge
          ".....@@@.@...",
          "....@@@@@@...",
          "...@@@@@@@@..",
          "..@@@@@@@@@@.",       # the eaves, wider than the walls
          "...#######...",
          "...#.###.#...",       # two windows
          "...#.###.#...",
          "...###.###...",       # the door (Gemini round 1: kept below a solid lintel, not up to the eaves)
          "...###.###...",
          "...###.###...",
          "." * 13,
          "." * 13]
POST_HX, POST_Z = 0.4375, 0.25
POST_Y0, POST_Y1 = 21.375, 25.25
BACK_HX, BACK_Y0, BACK_Y1 = 0.9375, 22.625, 25.0   # the dark-oak backing one cell round the plate
PLATE_TOP = 24.875


def crest(C):
    """a dark-oak post standing on the keystone cap with a bronze collar and a bronze finial; on its face a
    dark-oak backing with the brass-rimmed enamel plate and the embossed cottage; two bronze porch lanterns on
    bracket arms either side (their glass is the gate's Neon CrestWindow Parts)"""
    S = CV
    C.put("OakDark", C.box(-POST_HX, POST_HX, POST_Y0, POST_Y1, -POST_Z, POST_Z))
    C.put("Bronze", C.box(-0.5625, 0.5625, 21.5, 21.75, -0.375, 0.375))
    C.put("Bronze", C.box(-0.5625, 0.5625, POST_Y1, POST_Y1 + S, -0.375, 0.375))
    C.put("Bronze", C.box(-0.3125, 0.3125, POST_Y1 + S, POST_Y1 + 2 * S, -0.25, 0.25))
    C.put("Brass", C.box(-0.1875, 0.1875, POST_Y1 + 2 * S, POST_Y1 + 3 * S, -0.125, 0.125))
    C.put("OakDark", C.box(-BACK_HX, BACK_HX, BACK_Y0, BACK_Y1, -POST_Z, POST_Z))
    # the plate on the backing's front face
    zp = -POST_Z - S / 2
    ncol = len(PLATE[0])
    for row in range(len(PLATE)):
        y = PLATE_TOP - (row + 0.5) * S
        for col in range(ncol):
            x = ((ncol - 1) / 2 - col) * S   # +X is the viewer's left (front = -Z)
            k = PLATE[row][col]
            C.put("Brass" if k == "B" else "Enamel", C.cbox((x, y, zp), (S * 0.9,) * 3))
            lift = {"#": 1, "@": 2}.get(EMBLEM[row][col], 0)
            if k == "B":
                lift = max(lift, 1)
            for k2 in range(1, lift + 1):
                C.put("Brass", C.cbox((x, y, zp - k2 * S), (S * 0.9,) * 3))
    # the porch lanterns round the Neon windows (x +-1.25, y 23.35..24.05, z -0.725..-0.575): a tray and finial, two
    # corner posts each side of the glass, a back plate, a cap and a stepped hood, hung from a bracket arm off the
    # backing (crest z cell bounds are multiples of 0.125: the glass sits inside the posts' depth)
    for sx in (-1, 1):
        def bx(a, b, y0, y1, z0, z1, key="Bronze"):
            xa, xb = sorted((sx * a, sx * b))
            C.put(key, C.box(xa, xb, y0, y1, z0, z1))
        bx(0.8125, 1.6875, 23.25, 23.375, -0.875, -0.375)                    # tray (one cell proud of the glass)
        bx(1.1875, 1.3125, 23.125, 23.25, -0.625, -0.5, "Brass")             # finial
        for a, b in ((0.8125, 0.9375), (1.5625, 1.6875)):
            bx(a, b, 23.375, 24.0, -0.75, -0.625)                            # front posts
            bx(a, b, 23.375, 24.0, -0.5, -0.375)                             # back posts
        bx(0.9375, 1.5625, 23.375, 24.0, -0.625, -0.5)                       # back plate (behind the glass face)
        bx(0.8125, 1.6875, 24.0, 24.125, -0.875, -0.375)                     # cap (one cell proud of the glass)
        bx(1.1875, 1.3125, 23.375, 24.0, -0.875, -0.75)                      # glazing bars in front of the glass
        bx(0.9375, 1.5625, 23.625, 23.75, -0.875, -0.75)                     # (Gemini round 1: caged, not glued on)
        for a, b in ((0.8125, 0.9375), (1.5625, 1.6875)):
            bx(a, b, 23.375, 24.0, -0.875, -0.75)                            # the front corner posts, flush with them
        bx(0.9375, 1.5625, 24.125, 24.25, -0.75, -0.375)                     # hood
        bx(1.0625, 1.4375, 24.25, 24.375, -0.625, -0.5)
        bx(1.1875, 1.3125, 24.375, 24.5, -0.625, -0.5, "Brass")              # the hanger ring
        bx(BACK_HX, 1.4375, 24.5, 24.625, -0.625, -0.5)                      # the bracket arm
        bx(BACK_HX, 1.0625, 24.5, 24.625, -0.5, 0.125)                       # its foot, fixed to the backing's side
        bx(1.4375, 1.5625, 24.375, 24.625, -0.625, -0.5)                     # the arm's curled tip
        bx(BACK_HX, 1.0625, 24.0, 24.5, -0.625, -0.5)                        # the brace under the arm
    C.carve(C.box(-1.6, -0.9, 23.35, 24.05, -0.725, -0.575) | C.box(0.9, 1.6, 23.35, 24.05, -0.725, -0.575))


def recipes(keys):
    return {k: (TINTED[k] if k in TINTED else ["rgb"] + list(PAL[k])) for k in keys}


@prop("gate_homestead")
def build_gate_homestead(entry, kit):
    """catalog args: {"K": 2.0, "KP": 4.0, "KC": 8.0, "seed": 11}"""
    args = entry.get("args") or {}
    K = float(args.get("K", 2.0))
    KP = float(args.get("KP", 4.0))
    KC = float(args.get("KC", 8.0))
    r = np.random.default_rng(int(args.get("seed", 11)))
    m = kit.model(entry["key"], "gate", vs=1.0 / K, K=K)
    used = {}
    G = Lat(kit, K, (0, 13.5, 0), 14.0, "Gate")
    body(G, r)
    gkeys = [k for k in G.g.keys if k and np.any(G.L == G.g.ids[k])]
    fixed = tuple(k for k in gkeys if k not in TINTED and k not in OWN)
    kit.mesh(m, G.g, recipes=recipes(gkeys), group="Gate", vs=1.0 / K, offset=G.offset(), fixed_keys=fixed, used=used,
             flat=("Oak", "OakDark", "Bronze"), shade_opts={"Brass": dict(dark=False)})
    P = Lat(kit, KP, (0, 6.5, 0), 11.5, "Pillars")
    pillars(P, r)
    pkeys = [k for k in P.g.keys if k and np.any(P.L == P.g.ids[k])]
    pfixed = tuple(k for k in pkeys if k not in TINTED and k not in OWN)
    kit.mesh(m, P.g, recipes=recipes(pkeys), group="Pillars", vs=1.0 / KP, offset=P.offset(), fixed_keys=pfixed,
             used=used, shade_opts={"IvyTip": dict(dark=False)})
    C = Lat(kit, KC, (-CV / 2, 24.0, 0), 3.0, "Crest")
    crest(C)
    ckeys = [k for k in C.g.keys if k and np.any(C.L == C.g.ids[k])]
    cfixed = tuple(k for k in ckeys if k not in TINTED and k not in OWN)
    kit.mesh(m, C.g, recipes=recipes(ckeys), group="Crest", vs=1.0 / KC, offset=C.offset(), fixed_keys=cfixed,
             used=used, flat=("Oak", "OakDark", "Bronze"),
             shade_opts={"Brass": dict(dark=False), "Enamel": dict(dark=False, light=False)})
    m.meta = {
        "source": "WorldStyle.BuildGate (Hoop, house) in the homestead family of gate_homeportal (polish 2026-10-27)",
        "pivot": "the gate site: ground under the gate centre, front = -Z (WorldStyle tags ML_Offset (0, -11.5, 0))",
        "previewLook": {"Primary": [96, 190, 140], "Secondary": [255, 255, 255]},
        "dressHides": "Stone, StoneDark, Frame, Trim + the crest bodies (WorldStyle GATE_MESH_HIDE)",
    }
    return m
