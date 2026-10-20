"""Creature-class keys (wave 2 art-creatures; catalog blender/catalog/creatures.json; ARCHITECTURE_V3 6.3).

Shapes come from the game's own Lua wherever the game has a sculpt (one source of truth, so the Part fallback and the
mesh agree), run in the bridge's mock world through read-only hooks:
    SkyDragonController._Blueprint(k)   -> dragon_<piece>    (the sculpt re-run at k mesh voxels per 1-stud voxel)
    NpcService._Blueprint(seed, accent) -> npc_pedestal      (0.4-stud grid, refined here at 0.2 stud)
    BossBuilder._Blueprint(id, k)       -> boss_<id>_<Joint> (kit/bosskit.py; wings with a see-through membrane here)
TokenLook's coin, the battle effect props and the golden sparkle star are new fine-voxel designs (numpy masks).

Pivots: every key's manifest pivot is the origin of the Part piece it replaces (dragon piece origin, pedestal grid
voxel (0,0,0), coin centre, boss joint pivot), so the runtime places meshes exactly where the Parts were.
"""
import math

import numpy as np

from props import prop

# ---------------------------------------------------------------------------------------------- bridge + Lua driver
_DRIVER = r"""
local RS = game:GetService('ReplicatedStorage')
local Voxel = require(RS.Shared.Voxel)
local D = {}
local function find(name)
	for _, d in ipairs(game:GetDescendants()) do
		if d.Name == name and d:IsA('ModuleScript') then return d end
	end
	error('module not found: ' .. name)
end
local function cells(grid)
	local out = {}
	for packed, key in pairs(grid.Cells) do
		local x, y, z = Voxel.Unpack(packed)
		out[#out + 1] = x .. ' ' .. y .. ' ' .. z .. ' ' .. tostring(key)
	end
	table.sort(out)
	return table.concat(out, '\n')
end
local function style(entry)
	if entry == nil then return nil end
	local c, mat, tr = nil, 'SmoothPlastic', 0
	if typeof(entry) == 'Color3' then c = entry
	elseif type(entry) == 'table' then
		c = entry.Color
		if entry.Material then mat = tostring(entry.Material.Name or entry.Material) end
		tr = tonumber(entry.Transparency) or 0
	end
	if typeof(c) ~= 'Color3' then return nil end
	return { c.R, c.G, c.B, mat, tr }
end
local function pal(p)
	local out = {}
	for k, v in pairs(p) do out[k] = style(v) end
	return out
end
function D.dragon(k)
	local SD = require(find('SkyDragonController'))
	local bp = SD._Blueprint(k)
	local pieces, segs = {}, {}
	for name, g in pairs(bp.Pieces) do pieces[name] = cells(g) end
	for key, g in pairs(bp.Segments) do segs[key] = cells(g) end
	return { Pieces = pieces, Segments = segs, Palette = pal(bp.Palette), Offset = bp.Offset, VoxelStuds = bp.VoxelStuds }
end
function D.pedestal(seed)
	local NS = require(find('NpcService'))
	local bp = NS._Blueprint(seed, Color3.fromRGB(120, 180, 236))
	return { Cells = cells(bp.Grid), Palette = pal(bp.Palette), PV = bp.PV, Sink = bp.Sink, Top = bp.Top }
end
function D.tokens()
	local TL = require(RS.Shared.TokenLook)
	local out = {}
	for name, p in pairs(TL.Palettes) do
		out[name] = { Rim = style(p.Rim), Face = style(p.Face), Cloud = style(p.Cloud), Glow = style(p.Glow), Octagon = p.Octagon == true }
	end
	return out
end
return D
"""

_STATE = {}


def bridge():
    if "br" not in _STATE:
        from bridge import Bridge
        _STATE["br"] = Bridge()
    return _STATE["br"]


def driver():
    if "drv" not in _STATE:
        br = bridge()
        br.rt.globals().CREATURES_DRIVER = _DRIVER
        _STATE["drv"] = br.rt.eval(
            "function() local load_ = loadstring or load; local f, e = load_(CREATURES_DRIVER, '=props/creatures.lua'); "
            "if not f then error(e, 0) end; return f() end")()
    return _STATE["drv"]


def lua(fn, *args):
    from bridge import lua2py
    key = (fn,) + args
    if key not in _STATE:
        _STATE[key] = lua2py(getattr(driver(), fn)(*args))
    return _STATE[key]


def parse(text):
    out = {}
    for line in (text or "").split("\n"):
        if not line:
            continue
        x, y, z, k = line.split(" ")
        out[(int(x), int(y), int(z))] = k
    return out


def styles_from(palette, override=None):
    from nvox.parts import Styles
    pal = {k: list(v) for k, v in palette.items() if v}
    for k, v in (override or {}).items():
        pal[k] = v
    return Styles(pal)


def finish(m, meta):
    m.groups = {}
    m.attachments = {}
    m.meta = meta
    return m


# ---------------------------------------------------------------------------------------------- boss joints
@prop("boss_joint")
def boss_joint(entry, kit):
    """bosskit.build_boss_joint, but see-through keys (the frost wyrm's Ice membrane, T 0.15) are meshed as opaque
    (closed shells) and get their transparency back on the part afterwards."""
    from bridge import BOSS_VOXEL
    from nvox.build import ModelSpec
    from nvox.parts import add_cells
    a = entry.get("args") or {}
    boss, joint, k = a["boss"], a["joint"], float(a["k"])
    bp = bridge().boss(boss, k)
    g = next(x for x in bp["groups"] if x["name"] == joint)
    vs = BOSS_VOXEL / k
    pivot = np.asarray(g["pivot"] or [0, 0, 0], float) * BOSS_VOXEL
    m = ModelSpec(entry["key"], "boss", vs, k)
    cells = {(int(x), int(y), int(z)): kk for (x, y, z), kk in zip(g["xyz"].tolist(), g["keys"])}
    see = {kk: v[4] for kk, v in bp["palette"].items() if v and float(v[4]) > 0}
    opaque = {kk: list(bp["palette"][kk][:4]) + [0] for kk in see}
    made = add_cells(m, cells, styles_from(bp["palette"], opaque), group=joint, naming="key", vs=vs, offset=-pivot,
                     used={})
    for o in made:
        if o.key in see:
            o.transparency = float(see[o.key])
            o.meshed_closed = True  # meshed as an opaque closed shell: build_all's closure check still applies
    return finish(m, {"boss": boss, "joint": joint, "parent": g["parent"], "pivotStuds": [round(float(v), 4) for v in pivot],
                      "K": k, "seeThrough": sorted(see)})


# ---------------------------------------------------------------------------------------------- sky dragon
DRAGON_K = 3


def _dragon():
    return lua("dragon", DRAGON_K)


def _neigh_free(cells, p, d):
    return (p[0] + d[0], p[1] + d[1], p[2] + d[2]) not in cells


def dragon_scales(cells, key="Scale"):
    """scallop scales on the flanks: on every side-facing skin cell of the base shade, a staggered pattern of small
    "U" outlines (4 cells long, 3 tall = 1.3 x 1 stud) in the darker scale colour; the light back and the belly stay
    plain, so the dragon keeps its calm colour from far away and reads as scaly from close by."""
    out = dict(cells)
    for (x, y, z), k in cells.items():
        if k != key:
            continue
        side = 1 if x > 0 else -1
        if not _neigh_free(cells, (x, y, z), (side, 0, 0)):
            continue
        row = y // 3
        u = (z + 2 * (row % 2)) % 4
        v = y % 3
        if (v == 0 and u in (1, 2)) or (v == 1 and u in (0, 3)):
            out[(x, y, z)] = key + "_Dark"
    return out


def _dragon_piece(entry, kit, cells, name, scales=True):
    from nvox.parts import add_cells
    d = _dragon()
    vs = float(d["VoxelStuds"])
    off = -float(d["Offset"]) * vs
    m = kit.model(entry["key"], "dragon", vs=vs, K=DRAGON_K)
    if scales:
        cells = dragon_scales(cells)
    add_cells(m, cells, styles_from(d["Palette"]), group=name, naming="key", vs=vs, offset=(off, off, off), used={})
    return finish(m, {"piece": name, "K": DRAGON_K, "pivot": "the Part piece origin (SkyDragonController)"})


@prop("dragon_piece")
def dragon_piece(entry, kit):
    a = entry.get("args") or {}
    d = _dragon()
    if "segment" in a:
        cells = parse(d["Segments"][a["segment"]])
        return _dragon_piece(entry, kit, cells, "Segment", scales=True)
    piece = a["piece"]
    cells = parse(d["Pieces"][piece])
    return _dragon_piece(entry, kit, cells, piece, scales=piece in ("Head", "Leg"))


@prop("dragon_link")
def dragon_link(entry, kit):
    """one chain bead of the whiskers / mane (1 x 1 x 1 stud; the runtime resizes it per link and sets its colour):
    a pillowy rounded block with a lighter top (one MeshPart + its light part, colour = ML_Primary)."""
    from nvox.parts import Styles, add_cells
    n = 10
    idx = np.arange(-n // 2, n // 2)  # cell i sits at (i + 0.5) / n studs: 10 cells span -0.5 .. 0.5
    X, Y, Z = np.meshgrid(idx, idx, idx, indexing="ij")
    c = (np.stack([X, Y, Z]).astype(float) + 0.5) / n
    q = np.maximum(np.abs(c) - 0.28, 0)
    inside = np.sqrt((q ** 2).sum(0)) <= 0.22
    top = inside & (c[1] > 0.3)
    cells = {}
    for mask, key in ((inside & ~top, "Link"), (top, "Link_Light")):
        for i, j, k in zip(*np.nonzero(mask)):
            cells[(int(idx[i]), int(idx[j]), int(idx[k]))] = key
    st = Styles({"Link": [0.93, 0.77, 0.36, "SmoothPlastic", 0]}, {"Link": {"recipe": ["Primary"]}})
    m = kit.model(entry["key"], "dragon", vs=1.0 / n, K=n)
    add_cells(m, cells, st, group="Link", naming="key", vs=1.0 / n, offset=(0.5 / n,) * 3, used={})
    return finish(m, {"pivot": "bead centre; 1 stud cube, resized + recoloured per link"})


# ---------------------------------------------------------------------------------------------- NPC pedestal
@prop("npc_pedestal")
def npc_pedestal(entry, kit):
    """NpcService's stepped plinth (0.4-stud grid) at 0.2 stud: crisp P4 steps, stone blocks with mortar seams on
    the drum, a stitched rug border, shaded tops / undersides. Rug + band follow the NPC accent (ML_Primary)."""
    from nvox.grid import VoxelGrid
    a = entry.get("args") or {}
    p = lua("pedestal", int(a.get("seed", 1)))
    src = parse(p["Cells"])
    f = 2
    pv = float(p["PV"])
    vs = pv / f
    g = VoxelGrid(1.0, half=40)
    for (x, y, z), k in src.items():
        for dx in range(f):
            for dy in range(f):
                for dz in range(f):
                    g.set(x * f + dx, y * f + dy, z * f + dz, k)
    h = g.half
    L = g.L
    occ = L != 0
    # (no edge bevel: on the round tiers it leaves a saw-tooth rim; the P4 plinth keeps its crisp steps)
    # mortar seams on the drum: vertical every 30 degrees (offset per course) + a course line
    if "Stone" in g.ids:
        sid = g.kid("Stone")
        xs, ys, zs = np.nonzero(L == sid)
        for x, y, z in zip(xs, ys, zs):
            X, Y, Z = x - h, y - h, z - h
            exposed = not (occ[x + 1, y, z] and occ[x - 1, y, z] and occ[x, y, z + 1] and occ[x, y, z - 1])
            if not exposed:
                continue
            ang = math.degrees(math.atan2(Z + 0.5, X + 0.5)) % 360
            course = (Y // 2) % 2
            if (ang + 15 * course) % 30 < 4.5 or Y % 2 == 1 and False:
                L[x, y, z] = g.kid("Stone_Dark")
    # rug stitching: every other cell of the RugTrim border becomes RugCenter-gold
    if "RugTrim" in g.ids and "RugCenter" in g.ids:
        tid, cid = g.kid("RugTrim"), g.kid("RugCenter")
        xs, ys, zs = np.nonzero(L == tid)
        for x, y, z in zip(xs, ys, zs):
            if (x + z) % 4 == 0 and not occ[x, y + 1, z]:
                L[x, y, z] = cid
    pal = {k: v for k, v in p["Palette"].items() if v}
    navy = ["rgb", 26, 30, 52]
    recipes = {"Trim": ["mix", ["Primary"], navy, 0.3], "Rug": ["mix", ["Primary"], navy, 0.12], "RugTop": ["Primary"],
               "RugTrim": ["lighten", ["Primary"], 0.42]}
    from nvox.parts import Styles, add_cells
    from nvox.shade import shade as shade_grid
    from props import cells_from_grid
    S = shade_grid(g, {k: dict(light=True, dark=True) for k in ("Stone", "Base", "Cap", "Moss", "Leaf")},
                   skip=set(recipes) | {"Gold", "Plaque", "RugCenter", "Stone_Dark"}, default=dict(light=False, dark=False))
    S = np.where(S < -1, -1, S)
    cells = cells_from_grid(g, S)
    cells = {c: (k.replace("_Dark_Dark", "_Dark").replace("_Dark_Light", "_Dark")) for c, k in cells.items()}
    st = Styles({k: list(v) for k, v in pal.items()}, {k: {"recipe": r} for k, r in recipes.items()})
    m = kit.model(entry["key"], "npc", vs=vs, K=f)
    off = -0.5 * vs  # sub cell i of a 0.4-stud voxel sits at (i - 0.5) * 0.2 studs
    add_cells(m, cells, st, group="Pedestal", naming="key", vs=vs, offset=(off, off, off), used={})
    return finish(m, {"pivot": "grid voxel (0,0,0) = NpcService origin spot * (0, PV/2 - SINK, 0)", "top": p["Top"]})


# ---------------------------------------------------------------------------------------------- tokens
COIN_U = 0.32  # TokenLook.Voxel (studs per coin voxel at Scale 1)


def _coin_cells(octagon, n=4):
    """the coin standing on its edge, facing local X: design unit = one coin voxel, n mesh voxels per unit.
    Returns {cell: key} with keys Rim (Neon), Face, FaceDark (a recessed ring), Cloud."""
    R_RIM, R_FACE = 5.5, 3.9
    half = int(6 * n) + 2
    rng = np.arange(-half, half + 1)
    X, Y, Z = np.meshgrid(rng, rng, rng, indexing="ij")
    x, y, z = X / n, Y / n, Z / n  # cell centres (odd/even handled by the +0 offset: cells centred on the origin)
    r = np.sqrt(y ** 2 + z ** 2)
    if octagon:
        rf = np.maximum(np.maximum(np.abs(y), np.abs(z)), (np.abs(y) + np.abs(z)) / math.sqrt(2) * 1.04)
    else:
        rf = r
    out = np.zeros(X.shape, np.int8)  # 0 empty, 1 rim, 2 face, 3 face ring, 4 cloud, 5 rim studs
    # rim: a rounded torus-like band (thicker at the outside), 2 voxels thick
    rim_t = 1.0 - 0.35 * np.clip((r - (R_RIM - 1.0)) / 1.0, 0, 1) ** 2
    rim = (r <= R_RIM) & (np.abs(x) <= rim_t)
    out[rim] = 1
    # face plate, proud of the rim by half a voxel on both sides, with a soft bevel
    face_t = 1.5 - 0.25 * np.clip(rf - (R_FACE - 0.5), 0, 1)
    face = (rf <= R_FACE) & (np.abs(x) <= face_t)
    out[face] = 2
    ring = face & (rf >= R_FACE - 0.85) & (rf <= R_FACE - 0.45) & (np.abs(x) > face_t - 0.3)
    out[ring] = 3
    # cloud emblem in relief: three puffs on a flat base, 0.5 voxel proud of the face
    def blob(cy, cz, rr):
        return (y - cy) ** 2 + (z - cz) ** 2 <= rr ** 2
    # a puffy cloud: a round-ended base bar and four puffs (the biggest in the middle), like the lobby clouds
    base = (y >= -1.5) & (y <= -0.5) & (np.abs(z) <= 2.1)
    base |= ((y + 1.0) ** 2 + (z - 2.1) ** 2 <= 0.5 ** 2) | ((y + 1.0) ** 2 + (z + 2.1) ** 2 <= 0.5 ** 2)
    cloud2d = base | blob(-0.35, -1.6, 0.8) | blob(0.45, -0.25, 1.15) | blob(0.05, 1.3, 0.85)
    cloud2d &= y >= -1.5
    cloud = cloud2d & (np.abs(x) <= 2.0) & (np.abs(x) > 1.0)
    out[cloud] = 4
    # little studs on the rim (12 around), half a voxel proud
    ang = np.degrees(np.arctan2(z, y)) % 30
    studs = (r > R_RIM - 0.9) & (r <= R_RIM - 0.25) & ((ang < 6) | (ang > 24)) & (np.abs(x) <= 1.25) & (out == 1)
    out[studs] = 5
    names = {1: "Rim", 2: "Face", 3: "Face_Dark", 4: "Cloud", 5: "RimStud"}
    cells = {}
    for code, key in names.items():
        for i, j, k in zip(*np.nonzero(out == code)):
            cells[(int(i) - half, int(j) - half, int(k) - half)] = key
    return cells


@prop("token")
def token(entry, kit):
    from nvox.parts import Styles, add_cells
    a = entry.get("args") or {}
    pal = lua("tokens")[a["palette"]]
    n = 3
    cells = _coin_cells(bool(pal["Octagon"]), n)
    # light the upper half of the face / cloud, darken the lower edge (fixed per coin side)
    shaded = {}
    for (x, y, z), k in cells.items():
        if k in ("Face", "Cloud") and y >= 2.2 * n:
            k = k + "_Light"
        elif k == "Face" and y <= -3.0 * n:
            k = "Face_Dark"
        shaded[(x, y, z)] = k
    rim, face, cl = pal["Rim"], pal["Face"], pal["Cloud"]
    p = {"Rim": [rim[0], rim[1], rim[2], "Neon", 0], "RimStud": [min(1, rim[0] * 0.8 + 0.2), min(1, rim[1] * 0.8 + 0.2),
                                                             min(1, rim[2] * 0.8 + 0.2), "Neon", 0],
         "Face": [face[0], face[1], face[2], "SmoothPlastic", 0], "Cloud": [cl[0], cl[1], cl[2], "SmoothPlastic", 0]}
    vs = COIN_U / n
    m = kit.model(entry["key"], "token", vs=vs, K=n)
    add_cells(m, shaded, Styles(p), group="Coin", naming="key", vs=vs, used={})
    return finish(m, {"pivot": "coin centre (TokenLook root); faces local +-X; Scale 1 (x palette Scale at runtime)",
                      "palette": a["palette"]})


# ---------------------------------------------------------------------------------------------- battle effect props
def _grid_cells(mask, key, half):
    out = {}
    for i, j, k in zip(*np.nonzero(mask)):
        out[(int(i) - half, int(j) - half, int(k) - half)] = key
    return out


@prop("fx")
def fx(entry, kit):
    """fx_shield (a rounded ForceField shell, unit size: the runtime sizes it to the unit), fx_ice (one faceted ice
    crystal, unit height), fx_arrow (a chunky gold chevron, unit width)."""
    from nvox.parts import Styles, add_cells
    kind = (entry.get("args") or {})["kind"]
    if kind == "shield":
        n, half = 16, 9
        rng = np.arange(-half, half + 1) / (n / 2.0)
        X, Y, Z = np.meshgrid(rng, rng, rng, indexing="ij")
        q = np.maximum(np.abs(np.stack([X, Y, Z])) - 0.62, 0)
        d = np.sqrt((q ** 2).sum(0))
        shell = (d <= 0.36) & (d >= 0.24)
        edge = shell & ((np.abs(X) > 0.8).astype(int) + (np.abs(Y) > 0.8).astype(int) + (np.abs(Z) > 0.8).astype(int) >= 2)
        cells = _grid_cells(shell & ~edge, "Shield", half)
        cells.update(_grid_cells(edge, "ShieldEdge", half))
        p = {"Shield": [0.55, 0.85, 1.0, "ForceField", 0], "ShieldEdge": [0.75, 0.95, 1.0, "Neon", 0]}
        vs = 1.0 / (n / 2.0) / 2.0
        meta = {"pivot": "centre; 2 x 2 x 2 studs at scale 1 (runtime sizes it h * 1.25)"}
    elif kind == "ice":
        n, half = 10, 12
        rng = np.arange(-half, half + 1) / n
        X, Y, Z = np.meshgrid(rng, rng, rng, indexing="ij")
        # a hexagonal prism (0.3 wide) with a pointed tip and a short root, unit height (y -0.5 .. 0.5)
        hexr = np.maximum(np.abs(X) * 0.866 + np.abs(Z) * 0.5, np.abs(Z))
        taper = np.where(Y > 0.18, 1 - (Y - 0.18) / 0.34, 1.0)
        body = (hexr <= 0.17 * np.clip(taper, 0, 1)) & (Y >= -0.5) & (Y <= 0.52)
        light = body & ((X + Z) > 0.04)
        cells = _grid_cells(body & ~light, "Ice", half)
        cells.update(_grid_cells(light, "Ice_Light", half))
        p = {"Ice": [0.62, 0.86, 1.0, "Glass", 0], "Ice_Light": [0.85, 0.96, 1.0, "Glass", 0]}
        vs = 1.0 / n
        meta = {"pivot": "centre; 1 stud tall at scale 1", "transparency": 0.25}
    else:  # arrow
        n, half = 12, 8
        rng = np.arange(-half, half + 1) / n
        X, Y, Z = np.meshgrid(rng, rng, rng, indexing="ij")
        # a down-pointing chevron (V) 1 stud wide, 0.2 thick, with a bright rim
        v = (np.abs(Y + 0.25 - np.abs(X) * 0.9) <= 0.13) & (np.abs(X) <= 0.5) & (np.abs(Z) <= 0.1)
        rim = v & ((np.abs(Y + 0.25 - np.abs(X) * 0.9) > 0.07) | (np.abs(Z) > 0.05))
        cells = _grid_cells(v & ~rim, "Arrow", half)
        cells.update(_grid_cells(rim, "ArrowRim", half))
        p = {"Arrow": [1.0, 0.62, 0.1, "Neon", 0], "ArrowRim": [1.0, 0.84, 0.36, "Neon", 0]}
        vs = 1.0 / n
        meta = {"pivot": "chevron centre; 1 stud wide at scale 1"}
    m = kit.model(entry["key"], "fx", vs=vs, K=1.0 / vs)
    made = add_cells(m, cells, Styles(p), group="Fx", naming="key", vs=vs, used={})
    if meta.get("transparency"):
        for o in made:
            o.transparency = meta["transparency"]
    return finish(m, meta)


@prop("star")
def star(entry, kit):
    """star_gold: the Golden finish's sparkle star (4 long points + 4 short), Neon gold, 1 stud across at scale 1."""
    from nvox.parts import Styles, add_cells
    n, half = 16, 9
    rng = np.arange(-half, half + 1) / n
    X, Y, Z = np.meshgrid(rng, rng, rng, indexing="ij")
    ax, ay = np.abs(X), np.abs(Y)
    long_ = (ax * 4.2 + ay <= 0.5) | (ay * 4.2 + ax <= 0.5)
    diag = (np.abs(ax - ay) * 3.0 + (ax + ay) * 0.75 <= 0.3)
    shape2d = long_ | diag | (ax ** 2 + ay ** 2 <= 0.14 ** 2)
    thick = 0.09 - 0.12 * np.sqrt(ax ** 2 + ay ** 2)
    body = shape2d & (np.abs(Z) <= np.maximum(thick, 0.03))
    core = body & (ax ** 2 + ay ** 2 <= 0.12 ** 2)
    cells = _grid_cells(body & ~core, "Star", half)
    cells.update(_grid_cells(core, "StarCore", half))
    p = {"Star": [1.0, 0.84, 0.32, "Neon", 0], "StarCore": [1.0, 0.97, 0.82, "Neon", 0]}
    vs = 1.0 / n
    m = kit.model(entry["key"], "star", vs=vs, K=n)
    add_cells(m, cells, Styles(p), group="Star", naming="key", vs=vs, used={})
    return finish(m, {"pivot": "star centre; faces -Z; 1 stud across at scale 1"})
