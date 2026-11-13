"""The obby's voxel cloud set (kit-b B1, slop-audit round 3; catalog blender/catalog/obby.json).

Same recipe as the lobby's clouds (props/lobby_world.py "lobby_cloud"): a VX.Cloud spec (tiers from the top down,
soft Puffs, bright Rim puffs, a Carve) voxelled by the game's own LobbyBuilder._CloudGrid at V studs per voxel, shaded
by Voxel.Shade, coloured with the lobby's soft gradient and baked into one SmoothPlastic MeshPart "Cloud".  The specs
are new designs (DESIGNS below), not recorded lobby clouds, so no LayoutSig: the OBBY lane tags them by key.

  far_*    distant cumulus: a flat base (cumulus have one), a tower or crowns on top, misty lumps underneath;
           pivot = the base tier's top centre (the lowest voxel V under it)
  sea_*    the cloud sea under the route: a flat deck, billows on top (at most 3 voxels), a scalloped edge, a misty
           belly; pivot = the deck's top centre
  under_*  the puff a platform's slab sits in: pivot = attachment Seat = the slab's underside centre (X = the long side);
           a rim one voxel high hugs the slab footprint (hollow above the Seat), so at any scale up to 1.4 it stays
           under a 2-stud slab's walking top; the belly hangs below; nothing reaches more than 2.5 studs past the
           slab, so at scale 1.4 the puff still stops inside Easy's 4-stud gap (CourseBuilder Mesh.under keeps it)
  storm    a dark heavy cumulus for a Storm step: storm palette (StormAltar's), darkest at the flat base;
           pivot = the base's bottom centre, short enough to sit StormBase over a step under the head clearance
"""
import random

import numpy as np

from props import prop

_DRIVER = r"""
local D = {}
local function find(name)
	for _, d in ipairs(game:GetDescendants()) do
		if d.Name == name and d:IsA('ModuleScript') then return d end
	end
	error('module not found: ' .. name)
end
-- spec source (a Lua table literal) -> the cells of LobbyBuilder._CloudGrid(spec, V) as "x y z key" lines
function D.grid(src, V)
	local LB = require(find('LobbyBuilder'))
	local Voxel = require(game:GetService('ReplicatedStorage').Shared.Voxel)
	local load_ = loadstring or load
	local spec = assert(load_('return ' .. src))()
	local c = spec.Cut or {}
	spec.Cut = nil
	-- Cut in voxel levels (level 0 = the top tier, spanning V under the pivot; level 1 = the first above it): Lo / Hi
	-- keep levels Lo..Hi; Hollow = { hx, hz, level } empties |x| < hx, |z| < hz (studs) from that level up
	spec.Carve = function(x, y, z)
		local level = math.floor(y / V + 0.5)
		if c.Lo and level < c.Lo then return true end
		if c.Hi and level > c.Hi then return true end
		if c.Hollow and level >= c.Hollow[3] and math.abs(x) < c.Hollow[1] and math.abs(z) < c.Hollow[2] then return true end
		return false
	end
	local grid = LB._CloudGrid(spec, V)
	local out = {}
	for packed, key in pairs(grid.Cells) do
		local x, y, z = Voxel.Unpack(packed)
		out[#out + 1] = x .. ' ' .. y .. ' ' .. z .. ' ' .. tostring(key)
	end
	table.sort(out)
	return table.concat(out, '\n')
end
return D
"""

_STATE = {}


def driver():
    if "drv" not in _STATE:
        from bridge import Bridge
        from props import lobby_world as LW
        br = LW._STATE.setdefault("br", Bridge())  # one mock world for the lobby and the obby props
        br.rt.globals().OBBY_DRIVER = _DRIVER
        _STATE["drv"] = br.rt.eval(
            "function() local load_ = loadstring or load; local f, e = load_(OBBY_DRIVER, '=props/obby.lua'); "
            "if not f then error(e, 0) end; return f() end")()
    return _STATE["drv"]


def lua_literal(v):
    if isinstance(v, dict):
        return "{" + ", ".join("%s = %s" % (k, lua_literal(v[k])) for k in sorted(v)) + "}"
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_literal(x) for x in v) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    return repr(float(v))


# ---------------------------------------------------------------------------------------------- designs (studs)
def far(sx, sz, rnd, rim, puffs, seed):
    """a cumulus: a flat Mist base tier one voxel thick (inside the heads' footprint, so no ledge shows), bright Rim
    heads stacked into a rounded cauliflower top, misty Puff lumps under the sides; nothing under level 0"""
    return {"Tiers": [{"SX": sx, "SZ": sz, "Round": rnd, "H": 1, "Key": "Mist"}], "Rim": rim, "Puffs": puffs,
            "Seed": seed, "Cut": {"Lo": 0}}


def sea(sx, sz, rnd, sx2, sz2, billows, belly, seed):
    """a flat deck one voxel thick, a smaller Mist tier under it, low Rim billows on top (at most 3 voxels), a misty
    Puff belly"""
    return {"Tiers": [{"SX": sx, "SZ": sz, "Round": rnd, "H": 1, "Key": "Cloud"},
                      {"SX": sx2, "SZ": sz2, "Round": rnd * 0.8, "H": 1, "Key": "Mist"}],
            "Rim": billows, "Puffs": belly, "Seed": seed, "Cut": {"Hi": 3}}


def under(hx, hz, depth, seed, margin=1.3):
    """the slab's puff: a plate one voxel under the Seat, a lumpy rim round the slab footprint (2hx x 2hz, hollow over
    the Seat, one voxel high), a lumpy misty belly about `depth` studs deep; lumps jittered by `seed` so the four
    sizes never mirror each other.  Nothing reaches more than about margin + 1 studs past the slab: CourseBuilder
    Mesh.under shrinks a puff whose box reaches the next step, and Easy's gaps start at 4 (selftest obby)"""
    r = random.Random(seed)

    def j(v, a):
        return v * (1 + r.uniform(-a, a))
    rim = []
    ex, ez = hx + 0.3, hz + 0.3
    # the lumps are round bulges centred a stud under the Seat (the Cut keeps one voxel of them over it), so the rim
    # reads as puffs round the slab, not as a flat collar
    for sx_, sz_ in ((-1, -1), (1, -1), (1, 1), (-1, 1)):  # corners: the fattest lumps, centred on the slab's corner
        rim.append([sx_ * (hx + r.uniform(-0.5, 0.0)), -1.0, sz_ * (hz + r.uniform(-0.5, 0.0)), j(margin + 0.4, 0.12),
                    j(3.0, 0.15), j(margin + 0.3, 0.12)])
    for half, e, along in ((hx, ez, "x"), (hz, ex, "z")):  # each side: a lump every ~6 studs
        n = max(1, int(round(2 * half / 6.0)))
        step = 2 * half / n
        for k in (-1, 1):
            for i in range(n):
                t = -half + (i + 0.5) * step + r.uniform(-0.2, 0.2) * step
                w, d = j(step * 0.45 + 1.0, 0.2), j(margin, 0.15)
                w = min(w, half + 1.0 - abs(t))  # an end lump stops a stud past the corner (the corner lump rounds it)
                if along == "x":
                    rim.append([t, -1.0, k * e, w, j(2.5, 0.15), d])
                else:
                    rim.append([k * e, -1.0, t, d, j(2.5, 0.15), w])
    belly = [
        [0.0, -depth * 0.28, 0.0, hx * 0.92, depth * 0.36, hz * 0.88],
        [-hx * r.uniform(0.35, 0.55), -depth * 0.42, -hz * 0.25, hx * 0.5, depth * 0.42, hz * 0.5],
        [hx * r.uniform(0.4, 0.6), -depth * 0.5, hz * 0.3, hx * 0.45, depth * 0.48, hz * 0.45],
        [-hx * 0.1, -depth * 0.72, hz * r.uniform(0.2, 0.45), hx * 0.32, depth * 0.3, hz * 0.32],
        [hx * 0.25, -depth * 0.3, -hz * 0.6, hx * 0.45, depth * 0.3, hz * 0.35],
    ]
    return {"Tiers": [{"SX": 2 * hx + 1.0, "SZ": 2 * hz + 1.0, "Round": 3.0, "H": 1, "Key": "Cloud"}],
            "Rim": rim, "Puffs": belly, "Seed": seed,
            "Cut": {"Hi": 1, "Hollow": [hx, hz, 1]}, "_seat": True, "_slab": [hx, hz]}


DESIGNS = {
    # a tall tower with a two-headed crown, 60 wide
    "far_tower": far(40, 20, 10, [
        [0, 7, 0, 24, 9, 14], [-15, 14, 2, 11, 10, 10], [14, 13, -2, 12, 10, 10], [1, 21, 0, 13, 12, 11],
        [-6, 31, 2, 8.5, 7.5, 7.5], [8, 30, -2, 8.5, 7.5, 7.5], [1, 37, 0, 5.5, 4, 5.5], [-26, 4, 0, 7, 5.5, 8],
        [27, 3, 2, 6, 5, 7], [-3, 12, 9, 10, 8, 6], [6, 14, -9, 10, 9, 6]], [
        [-12, 1, 6, 10, 3, 6], [12, 1, -6, 10, 3, 6]], 11),
    # two cauliflower heads over a high saddle, shoulders stepping out at their sides, 72 wide
    "far_twin": far(50, 18, 9, [
        [0, 10, 0, 30, 10, 15], [-15, 16, 0, 14, 10, 11], [-13, 26, 1, 9, 6, 8], [-18, 31, 2, 5, 3.5, 5],
        [-8, 30, -1, 5, 3.5, 5], [16, 15, -1, 13, 10, 10], [20, 22, -2, 10, 6, 8], [14, 26, 1, 5, 3.5, 5], [27, 13, 0, 8, 7, 8],
        [-28, 9, 0, 8, 7, 9], [29, 7, 1, 8, 6, 9], [-35, 3, 0, 5, 4, 7], [36, 2, 1, 5, 3, 7],
        [2, 12, 8, 9, 7, 6]], [
        [-18, 1, 8, 12, 3, 6], [18, 1, -8, 12, 3, 6]], 12),
    # broad, many heads, the crown off centre, 90 wide
    "far_lump": far(64, 28, 14, [
        [-4, 7, 0, 36, 9, 18], [-26, 12, 3, 13, 10, 12], [-10, 15, -3, 13, 11, 12], [12, 18, 0, 15, 14, 13],
        [16, 29, -2, 10, 9, 9], [10, 35, 1, 6, 4, 6], [30, 11, 2, 11, 9, 10], [-38, 4, -2, 7, 5, 9],
        [41, 3, 1, 6, 4, 8], [-14, 8, -15, 11, 7, 6], [6, 9, 15, 12, 7, 6]], [
        [-22, 1, 10, 15, 3, 7], [20, 1, -12, 15, 3, 7]], 13),
    # a long low bank: a chain of rounded heads of different heights (no long body, which terraces), 120 wide
    "far_bank": far(92, 20, 10, [
        [-47, 4, 0, 9, 6, 9], [-36, 8, 2, 12, 9, 11], [-20, 10, -2, 12, 10, 11], [-4, 13, 1, 13, 12, 12],
        [4, 22, -1, 8, 7, 7], [14, 11, 2, 12, 10, 11], [30, 9, -2, 12, 9, 10], [45, 7, 1, 10, 8, 10],
        [53, 2, 1, 5, 4, 7], [-22, 18, 1, 7, 5, 6], [32, 16, 0, 7, 5, 6], [-10, 6, 9, 12, 6, 6],
        [22, 6, -9, 12, 6, 6]], [
        [-30, 1, 10, 18, 3, 7], [28, 1, -10, 18, 3, 7]], 14),
    # the cloud sea: a wide deck under rolling billows, scalloped by lumps round its edge, 110 wide
    "sea_wide": sea(96, 56, 24, 76, 42, [
        [-32, 0, 10, 16, 7, 13], [-6, 0, -14, 18, 8, 13], [20, 0, 6, 17, 7, 14], [42, 0, -14, 11, 6, 9],
        [-44, 0, -16, 10, 5, 8], [6, 0, 22, 12, 5, 8], [46, 0, 18, 8, 4, 7], [-20, 0, 26, 8, 4, 6],
        [-52, -1, 2, 9, 5, 12], [52, -1, -2, 9, 5, 12], [-4, -1, 31, 16, 5, 7], [-12, -1, -30, 16, 5, 7],
        [30, -1, 27, 10, 4, 6], [28, -1, -28, 12, 4, 6]], [
        [-22, -8, 0, 22, 5, 15], [20, -8, 4, 20, 5, 14], [0, -10, -8, 16, 5, 11]], 21),
    # a long drift: a narrow deck, its outline made by a row of billows, 140 wide
    "sea_long": sea(112, 34, 16, 92, 26, [
        [-58, -1, 4, 12, 6, 12], [-42, 0, -8, 14, 7, 12], [-24, 0, 6, 16, 8, 14], [-4, 0, -6, 18, 9, 14],
        [16, 0, 8, 16, 8, 13], [34, 0, -6, 15, 7, 12], [52, -1, 4, 13, 6, 12], [64, -2, -4, 8, 4, 8],
        [-66, -2, -2, 7, 4, 8], [-30, 6, 0, 7, 4, 6], [8, 7, 2, 8, 4, 6]], [
        [-40, -8, 0, 24, 5, 12], [8, -9, 2, 26, 5, 13], [50, -7, -4, 14, 4, 10]], 22),
    "under_s": under(6.25, 5.0, 6.0, 31),
    "under_m": under(7.75, 6.25, 7.5, 32),
    "under_l": under(9.5, 7.75, 9.0, 33),
    "under_pad": under(15.0, 15.0, 11.0, 34, margin=1.6),
    # a dark heavy cumulus, about 14 x 9 and 6 tall: a flat base under a wide low body, three domed heads of
    # different heights with dips between them (so no profile reads as a block)
    "storm": {"Tiers": [{"SX": 10, "SZ": 6, "Round": 3, "H": 1, "Key": "Mist"}], "Rim": [
        [-4.6, 1.2, 0.3, 2.8, 2.8, 3.0], [0.4, 2.8, -0.3, 3.0, 3.2, 3.2], [5, 0.8, 0, 2.6, 2.6, 2.8],
        [0, 0.2, 0, 6.0, 2.0, 3.8], [0.5, 0.8, 3.0, 3.0, 1.8, 1.6], [-2, 0.8, -3.0, 3.0, 1.8, 1.6]],
        "Puffs": [[-2, -0.5, 1.5, 4, 1.2, 2.5], [3, -0.5, -1.5, 4, 1.2, 2.5]],
        "Seed": 41, "Cut": {"Lo": 0, "Hi": 5}, "_storm": True},
}

# StormAltar's storm palette (StormAltar.lua C.Storm*), mapped onto the cloud keys the lobby recipe produces
STORM_RGB = {
    "CloudLight": (107, 119, 168), "Cloud": (68, 80, 127), "CloudShade": (54, 66, 110), "Mist": (40, 49, 86),
    "MistDark": (34, 43, 78),
}


def storm_color(key):
    from nvox import colors as C
    base = key.replace("_Light", "").replace("_Dark", "")
    c = C.rgb(*STORM_RGB.get(base, STORM_RGB["Cloud"]))
    if key.endswith("_Light"):
        return C.shade_light(c)
    if key.endswith("_Dark"):
        return C.shade_dark(c)
    return c


def colours(cells, storm):
    """the lobby's soft cloud gradient (lit crowns lighter, undersides misty), plus a height gradient: the lowest
    third cools toward the base colour (Mist; StormDeep for the storm cloud, whose crowns also lift toward StormTop)"""
    from nvox import colors as C
    from props.lobby_world import CLOUD_RGB, cloud_color, soften
    cols = soften(cells, storm_color if storm else cloud_color)
    ys = [y for (_, y, _) in cells]
    y0, y1 = min(ys), max(ys)
    span = max(1, y1 - y0)
    low = C.rgb(*(STORM_RGB["MistDark"] if storm else CLOUD_RGB["Mist"]))
    top = C.rgb(*STORM_RGB["CloudLight"])
    out = {}
    for (x, y, z), c in cols.items():
        t = (y - y0) / span
        if t < 0.34:
            c = C.mix(c, low, (0.34 - t) / 0.34 * (0.55 if storm else 0.3))
        elif storm and t > 0.6:
            c = C.mix(c, top, (t - 0.6) / 0.4 * 0.35)
        out[(x, y, z)] = c
    return out


def design_cells(design, V):
    from bridge import lua2py
    from props.lobby_world import parse_cells
    spec = {k: v for k, v in DESIGNS[design].items() if not k.startswith("_")}
    spec["V"] = V
    return parse_cells(lua2py(driver().grid(lua_literal(spec), float(V))))


def pieces(cells):
    """the 6-connected pieces of a cell set, biggest first (a voxel touching only by an edge or corner floats)"""
    left = set(cells)
    out = []
    while left:
        seed = min(left)
        left.discard(seed)
        part, todo = {seed}, [seed]
        while todo:
            x, y, z = todo.pop()
            for n in ((x + 1, y, z), (x - 1, y, z), (x, y + 1, z), (x, y - 1, z), (x, y, z + 1), (x, y, z - 1)):
                if n in left:
                    left.discard(n)
                    part.add(n)
                    todo.append(n)
        out.append(part)
    out.sort(key=lambda p: (-len(p), min(p)))
    return out


def solid_cells(design, V):
    """the design's cells with every piece but the biggest dropped (no floating voxel), and how many were dropped"""
    cells = design_cells(design, V)
    parts = pieces(cells)
    keep = parts[0] if parts else set()
    return {c: k for c, k in cells.items() if c in keep}, len(cells) - len(keep)


@prop("obby_cloud")
def obby_cloud(entry, kit):
    """an obby cloud from DESIGNS[args.design] at args.V studs per voxel (one baked part "Cloud")"""
    from nvox.parts import add_baked
    args = entry.get("args") or {}
    design, V = args["design"], float(args.get("V", 1.0))
    d = DESIGNS[design]
    cells, dropped = solid_cells(design, V)
    if not cells:
        raise ValueError("%s: design %s made no voxels" % (entry["key"], design))
    m = kit.model(entry["key"], "prop", vs=V, K=1.0 / V)
    # voxel (0, 0, 0) sits V/2 under the pivot (VX.CloudModel); the storm cloud's pivot is its base's bottom centre
    off = np.array([0.0, -V / 2.0, 0.0])
    if d.get("_storm"):
        off[1] = -(min(y for (_, y, _) in cells) - 0.5) * V
    add_baked(m, colours(cells, d.get("_storm", False)), "Cloud", group="Cloud", vs=V, offset=off, key="Cloud")
    m.groups = {}
    m.attachments = {"Seat": {"pos": [0.0, 0.0, 0.0], "rot": np.eye(3).tolist()}} if d.get("_seat") else {}
    pivot = ("Seat: the slab's underside centre" if d.get("_seat") else
             "the base's bottom centre" if d.get("_storm") else
             "the deck's top centre" if design.startswith("sea") else "the base tier's top centre")
    m.meta = {"source": "obby design %s (VX.Cloud via LobbyBuilder._CloudGrid) at V %.2f" % (design, V), "pivot": pivot,
              "floatingDropped": dropped}
    return m
