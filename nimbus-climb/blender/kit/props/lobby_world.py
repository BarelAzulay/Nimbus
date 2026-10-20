"""Lobby keys baked from the game's OWN build (wave 2 art-lobby; catalog blender/catalog/lobby.json; ARCHITECTURE_V3 6.3).

The kit boots the mock world (bridge), sets LobbyBuilder._Kit / StormAltar._Kit and runs LobbyBuilder.Build() +
StormAltar.Build(): every Mesh.tag call in the builders is recorded as {Key, Target, Origin}, every VX.CloudModel as
its cloud spec.  Two builders use that record:

  * "lobby_cloud"  a voxel cloud island / puff re-voxeled FINER from the very spec the game uses
                   (LobbyBuilder._CloudGrid(spec, V): same tiers, puffs, rim and carve, V studs per voxel), colours
                   baked (one MeshPart "Cloud"), pivot = the cloud's top centre (the Tag origin).
  * "lobby_boxes"  a layout piece (floor layers, courts, kerbs, plank decks, the altar's stones / crystals / bridge)
                   meshed from the Part build's own boxes: exactly the same shapes (walk heights and colliders match),
                   one baked MeshPart per material (+ one per Neon colour), pivot = the Tag origin.
  * "altar_island" the Storm Altar island: the walking top boxes + the rim billows and the belly re-voxeled finer
                   (StormAltar._Blueprint).

Every key built here carries the attachment "LayoutSig" = (part count, position sum, size sum) of the Part build in
origin space (LobbyBuilder Mesh.Signature): the builders only tag a key while the live build still matches it.
"""
import math

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
local state = nil
local specs = nil
local fmt = string.format
local function comps(cf)
	local t = { cf:GetComponents() }
	for i = 1, #t do t[i] = fmt('%.6f', t[i]) end
	return table.concat(t, ' ')
end
local function boxes(target, origin, skip)
	local inv = origin:Inverse()
	local out = {}
	local list = target:GetDescendants()
	list[#list + 1] = target
	for _, d in ipairs(list) do
		if d:IsA('BasePart') and d.Transparency < 0.99 and not (skip and skip(d)) then
			local shape = 'Block'
			if d:IsA('Part') then shape = d.Shape.Name end
			local c = d.Color
			out[#out + 1] = fmt('%s %s %s %.4f %.4f %.4f %d %d %d %s %.3f %s', d.ClassName, shape, comps(inv * d.CFrame),
				d.Size.X, d.Size.Y, d.Size.Z, math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5),
				math.floor(c.B * 255 + 0.5), d.Material.Name, d.Transparency, d.Name)
		end
	end
	table.sort(out)
	return table.concat(out, '\n')
end
local function cells(grid)
	local Voxel = require(game:GetService('ReplicatedStorage').Shared.Voxel)
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
function D.run()
	if state then return state end
	local LB = require(find('LobbyBuilder'))
	local SA = require(find('StormAltar'))
	LB._Kit = { Targets = {}, Clouds = {} }
	SA._Kit = { Targets = {} }
	local info = LB.Build()
	SA.Build(info)
	local kitL, kitS = LB._Kit, SA._Kit
	LB._Kit, SA._Kit = nil, nil
	local targets, count, clouds = {}, {}, {}
	local cloudList = {}
	for model, rec in pairs(kitL.Clouds) do
		cloudList[#cloudList + 1] = { Model = model, Rec = rec }
	end
	table.sort(cloudList, function(a, b)
		return (a.Rec.Template or '') .. a.Rec.Name .. comps(a.Rec.CF) < (b.Rec.Template or '') .. b.Rec.Name .. comps(b.Rec.CF)
	end)
	local cloudOf = {}
	for i, c in ipairs(cloudList) do
		clouds[i] = { Template = c.Rec.Template or '', Name = c.Rec.Name or '', CF = comps(c.Rec.CF), V = c.Rec.Spec.V or 3 }
		cloudOf[c.Model] = i
	end
	state = { Targets = targets, Count = count, Clouds = clouds }
	specs = cloudList
	local targetSet = {}
	for _, rec in ipairs(kitL.Targets) do targetSet[rec.Target] = true end
	for _, rec in ipairs(kitS.Targets) do targetSet[rec.Target] = true end
	local function add(rec, Mesh)
		local key = rec.Key
		count[key] = (count[key] or 0) + 1
		if count[key] > 1 then return end
		local n, a, b = Mesh.Signature(rec.Target, rec.Origin)
		local look = {}
		for k, v in pairs(rec.Look or {}) do
			if typeof(v) == 'Color3' then look[k] = { v.R, v.G, v.B } end
		end
		targets[#targets + 1] = {
			Key = key, Name = rec.Target.Name, Origin = comps(rec.Origin), Sig = { n, a, b },
			Boxes = boxes(rec.Target, rec.Origin, function(d)
				-- parts of a nested target (a bridge's puff) belong to that target's own mesh
				local a = d.Parent
				while a and a ~= rec.Target do
					if targetSet[a] then return true end
					a = a.Parent
				end
				return false
			end), Cloud = cloudOf[rec.Target] or 0, Look = look,
			Keep = table.concat(rec.Keep or {}, ','),
		}
	end
	for _, rec in ipairs(kitL.Targets) do add(rec, LB._Mesh) end
	for _, rec in ipairs(kitS.Targets) do add(rec, SA._Mesh) end
	-- the altar island without its voxel children (the walking top polygons only)
	local altar = workspace:FindFirstChild('StormAltar', true)
	local island = altar and altar:FindFirstChild('Island')
	if island then
		state.AltarTop = boxes(island, altar.PrimaryPart.CFrame, function(d) return d.Parent ~= island end)
		state.AltarCF = comps(altar.PrimaryPart.CFrame)
		local rim = island:FindFirstChild('RimClouds')
		state.GapProbe = rim and #rim:GetChildren() or 0
	end
	return state
end
function D.cloud(i, V)
	local LB = require(find('LobbyBuilder'))
	D.run()
	local rec = specs[i].Rec
	return cells(LB._CloudGrid(rec.Spec, V))
end
-- the gap angle the game used (the island's rim leaves it open): the dock bearing in altar space
function D.altar(bv, f)
	local SA = require(find('StormAltar'))
	local altar = workspace:FindFirstChild('StormAltar', true)
	local A = altar.PrimaryPart.CFrame
	local bridge = altar:FindFirstChild('Bridge')
	local gap = 180
	if bridge then
		local sum, n = Vector3.new(), 0
		for _, d in ipairs(bridge:GetDescendants()) do
			if d:IsA('BasePart') and d.Name == 'Deck' then sum = sum + d.Position; n = n + 1 end
		end
		if n > 0 then
			local p = A:PointToObjectSpace(sum / n)
			gap = math.deg(math.atan2(p.X, -p.Z)) % 360
		end
	end
	local bp = SA._Blueprint(gap, bv, f)
	local pal = {}
	for k, v in pairs(bp.Palette) do pal[k] = style(v) end
	return { Rim = cells(bp.Rim), Belly = cells(bp.Belly), Palette = pal, Gap = gap }
end
return D
"""

_STATE = {}


def driver():
    if "drv" not in _STATE:
        from bridge import Bridge
        br = _STATE.setdefault("br", Bridge())
        br.rt.globals().LOBBY_DRIVER = _DRIVER
        _STATE["drv"] = br.rt.eval(
            "function() local load_ = loadstring or load; local f, e = load_(LOBBY_DRIVER, '=props/lobby_world.lua'); "
            "if not f then error(e, 0) end; return f() end")()
    return _STATE["drv"]


def world():
    if "world" not in _STATE:
        from bridge import lua2py
        _STATE["world"] = lua2py(driver().run())
    return _STATE["world"]


def target(key):
    for t in world()["Targets"]:
        if t["Key"] == key:
            return t
    raise KeyError("no Mesh.tag target recorded for %s (LobbyBuilder / StormAltar)" % key)


def placements():
    """key -> number of tagged targets in the lobby (tools/mesh_budget scene)"""
    return dict(world()["Count"])


def cf_matrix(text):
    v = [float(x) for x in text.split()]
    R = np.array([[v[3], v[4], v[5]], [v[6], v[7], v[8]], [v[9], v[10], v[11]]])
    return R, np.array(v[:3])


def parse_cells(text):
    out = {}
    for line in (text or "").split("\n"):
        if line:
            x, y, z, k = line.split(" ")
            out[(int(x), int(y), int(z))] = k
    return out


def layout_sig(t):
    n, a, b = t["Sig"]
    return {"pos": [int(n), round(float(a), 4), round(float(b), 4)], "rot": np.eye(3).tolist()}


# ---------------------------------------------------------------------------------------------- box meshing
_UNIT = [  # outward CCW unit faces (nvox.mesher convention): +X, -X, +Y, -Y, +Z, -Z
    [[0.5, -0.5, -0.5], [0.5, 0.5, -0.5], [0.5, 0.5, 0.5], [0.5, -0.5, 0.5]],
    [[-0.5, -0.5, 0.5], [-0.5, 0.5, 0.5], [-0.5, 0.5, -0.5], [-0.5, -0.5, -0.5]],
    [[-0.5, 0.5, -0.5], [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5], [0.5, 0.5, -0.5]],
    [[0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], [-0.5, -0.5, -0.5]],
    [[-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [0.5, 0.5, 0.5], [-0.5, 0.5, 0.5]],
    [[-0.5, 0.5, -0.5], [0.5, 0.5, -0.5], [0.5, -0.5, -0.5], [-0.5, -0.5, -0.5]],
]
_UNIT = np.array(_UNIT, float)
# P4 face shading for the flat Part look (top a touch lighter, sides / bottom a touch darker), as vertex colours
_FACE_SHADE = [0.93, 0.93, 1.0, 0.8, 0.9, 0.9]


def parse_boxes(text):
    out = []
    for line in (text or "").split("\n"):
        if not line:
            continue
        f = line.split(" ")
        cls, shape = f[0], f[1]
        v = [float(x) for x in f[2:14]]
        R = np.array([[v[3], v[4], v[5]], [v[6], v[7], v[8]], [v[9], v[10], v[11]]])
        out.append({"cls": cls, "shape": shape, "pos": np.array(v[:3]), "R": R,
                    "size": np.array([float(x) for x in f[14:17]]),
                    "rgb": tuple(int(x) / 255.0 for x in f[17:20]), "mat": f[20], "tr": float(f[21]), "name": f[22]})
    return out


def add_boxes(m, boxes, group, used_names, R0=None, p0=None, shade_faces=True):
    """one baked part per material class: SmoothPlastic -> "Fixed" (vertex colours), Glass -> "Glass",
    Neon -> one part per colour ("Glow", "Glow2", ...) coloured by recipe (Neon ignores vertex colours)"""
    R0 = np.eye(3) if R0 is None else R0
    p0 = np.zeros(3) if p0 is None else p0
    neon = {}
    for b in boxes:
        if b["cls"] not in ("Part", "SpawnLocation", "Seat", "TrussPart") or b["shape"] != "Block":
            continue  # (wedges / balls / cylinders: none in the baked targets; they would need their own meshes)
        if b["mat"] == "Neon":
            col = b["rgb"]
            name = neon.get(col)
            if name is None:
                n = len(neon) + 1
                name = "Glow" if n == 1 else "Glow%d" % n
                neon[col] = name
            o = m.obj(name, group=group, region=name, shade="base",
                      recipe=["rgb"] + [int(round(c * 255)) for c in col], material="Neon", baked=False)
            vcol = (1.0, 1.0, 1.0)
            o.key = name
            o.keys.add(name)
        elif b["mat"] == "Glass" or b["tr"] > 0.02:
            o = m.obj("Glass", group=group, region="Fixed", shade="fixed", recipe=None,
                      material="Glass" if b["mat"] == "Glass" else "SmoothPlastic", baked=True)
            o.transparency = max(getattr(o, "transparency", 0) or 0, b["tr"] or 0.3)
            o.key = "Glass"
            o.keys.add("Glass")
            vcol = b["rgb"]
        else:
            o = m.obj("Fixed", group=group, region="Fixed", shade="fixed", recipe=None, material="SmoothPlastic",
                      baked=True)
            o.key = "Fixed"
            o.keys.add("Fixed")
            vcol = b["rgb"]
        R = R0 @ b["R"]
        p = R0 @ b["pos"] + p0
        for fi, face in enumerate(_UNIT):
            cs = (face * b["size"]) @ R.T + p
            f = _FACE_SHADE[fi] if (shade_faces and o.material != "Neon") else 1.0
            c = tuple(round(min(1.0, x * f) * 255) / 255 for x in vcol)
            o.quads.append((cs, c))
    for o in m.objects.values():
        dedupe_quads(o)


def dedupe_quads(o):
    """coincident quads (two boxes touching face to face, or the same box twice) break the FBX round trip (Blender
    merges them): a back-to-back pair is dropped (it was inside anyway), a same-facing duplicate is kept once"""
    seen = {}
    for i, (cs, c) in enumerate(o.quads):
        c4 = np.asarray(cs, float)
        key = tuple(sorted(tuple(np.round(v, 3)) for v in c4))
        n = np.cross(c4[1] - c4[0], c4[3] - c4[0])
        seen.setdefault(key, []).append((i, n))
    drop = set()
    for key, lst in seen.items():
        if len(lst) < 2:
            continue
        pos = [i for i, n in lst if np.dot(n, lst[0][1]) > 0]
        neg = [i for i, n in lst if np.dot(n, lst[0][1]) <= 0]
        k = min(len(pos), len(neg))
        drop.update(pos[:k])
        drop.update(neg[:k])
        drop.update(pos[k:][1:])
        drop.update(neg[k:][1:])
    if drop:
        o.quads = [q for i, q in enumerate(o.quads) if i not in drop]


def finish(m, t, meta):
    m.groups = {}
    m.attachments = {"LayoutSig": layout_sig(t)}
    m.meta = meta
    return m


@prop("lobby_boxes")
def lobby_boxes(entry, kit):
    """a layout piece meshed from its own Part boxes (exact shapes; pivot = the Tag origin)"""
    t = target(entry["key"])
    m = kit.model(entry["key"], "prop", vs=0.25, K=1.0)
    add_boxes(m, parse_boxes(t["Boxes"]), "Floor", {})
    return finish(m, t, {"source": "%s (%s) Part boxes" % (t["Name"], entry["key"]), "pivot": "Tag origin"})


# ---------------------------------------------------------------------------------------------- clouds
# LobbyBuilder C (P4) cloud colours; the shaded variants as VX.Cloud remaps them
CLOUD_RGB = {
    "CloudLight": (244, 247, 252), "Cloud": (232, 238, 249), "CloudShade": (212, 222, 241), "Mist": (194, 211, 240),
    "MistDark": (170, 190, 228),
}


def cloud_color(key):
    from nvox import colors as C
    base = key.replace("_Light", "").replace("_Dark", "")
    c = C.rgb(*CLOUD_RGB.get(base, CLOUD_RGB["Cloud"]))
    if key.endswith("_Light"):
        return C.shade_light(c)
    if key.endswith("_Dark"):
        return C.shade_dark(c)
    return c


def soften(cells, color_of, rng_seed=1):
    """cell -> colour with a soft P4 cloud gradient: undersides cool (Mist), lit crowns warm white; exposed-down cells
    darken a step, cells with open sky above lighten a step"""
    from nvox import colors as C
    occ = set(cells)
    out = {}
    for (x, y, z), k in cells.items():
        c = color_of(k)
        up = (x, y + 1, z) not in occ
        down = (x, y - 1, z) not in occ
        if up and not down:
            c = C.lighten(c, 0.25)
        elif down and not up:
            c = C.mix(c, C.rgb(*CLOUD_RGB["Mist"]), 0.55)
        out[(x, y, z)] = c
    return out


def cloud_cells(index, V):
    from bridge import lua2py
    return parse_cells(lua2py(driver().cloud(int(index), float(V))))


def find_cloud(template=None, index=None):
    for i, c in enumerate(world()["Clouds"], 1):
        if (index is not None and i == index) or (template is not None and c["Template"] == template):
            return i, c
    raise KeyError("no recorded cloud (template %r)" % template)


def add_cloud(m, index, V, R0=None, p0=None, name="Cloud", group="Cloud"):
    """the recorded cloud `index` at V studs per voxel as one baked part; voxel (0,0,0) sits V/2 under the cloud's
    top centre (VX.CloudModel); R0 / p0 place the cloud's own CF in the key's space"""
    from nvox.parts import add_baked
    cells = cloud_cells(index, V)
    cols = soften(cells, cloud_color)
    off = np.array([0.0, -V / 2.0, 0.0])
    R0 = np.eye(3) if R0 is None else R0
    p0 = np.zeros(3) if p0 is None else p0
    o = add_baked(m, cols, name, group=group, vs=V, rot=R0, offset=R0 @ off + p0, key=name)
    if o is not None and o.tris() > 9000:
        # one MeshPart stays under 10k triangles: split the island into a west and an east half (closed shells)
        del m.objects[name]
        west = {c: v for c, v in cols.items() if c[0] < 0}
        east = {c: v for c, v in cols.items() if c[0] >= 0}
        add_baked(m, west, name, group=group, vs=V, rot=R0, offset=R0 @ off + p0, key=name)
        o = add_baked(m, east, name + "2", group=group, vs=V, rot=R0, offset=R0 @ off + p0, key=name)
    return o


@prop("lobby_cloud")
def lobby_cloud(entry, kit):
    """a cloud island / puff from the game's own spec at a finer grain (args.V studs per voxel)"""
    args = entry.get("args") or {}
    V = float(args.get("V", 1.5))
    t = target(entry["key"])
    idx = t["Cloud"] or find_cloud(template=args.get("template"))[0]
    m = kit.model(entry["key"], "prop", vs=V, K=1.0 / V)
    add_cloud(m, idx, V)
    return finish(m, t, {"source": "VX.Cloud spec of %s at V %.2f" % (t["Name"], V), "pivot": "cloud top centre"})


# ---------------------------------------------------------------------------------------------- storm altar island
@prop("altar_island")
def altar_island(entry, kit):
    from bridge import lua2py
    from nvox import colors as C
    from nvox.parts import add_baked
    args = entry.get("args") or {}
    bv, f = float(args.get("bv", 1.0)), float(args.get("f", 2.0))
    t = target(entry["key"])
    w = world()
    data = lua2py(driver().altar(bv, f))
    pal = data["Palette"]

    def col(k):
        base = k.replace("_Light", "").replace("_Dark", "")
        e = pal.get(k) or pal.get(base)
        c = tuple(e[:3]) if e else C.rgb(86, 98, 143)
        if k not in pal and k.endswith("_Light"):
            c = C.shade_light(c)
        elif k not in pal and k.endswith("_Dark"):
            c = C.shade_dark(c)
        return c
    m = kit.model(entry["key"], "prop", vs=bv, K=1.0 / bv)
    add_boxes(m, parse_boxes(w["AltarTop"]), "Island", {})
    rim = parse_cells(data["Rim"])
    add_baked(m, {k: col(v) for k, v in rim.items()}, "Rim", group="Island", vs=bv, key="Rim")
    belly = parse_cells(data["Belly"])
    bvox = 3.0 / f
    add_baked(m, {k: col(v) for k, v in belly.items()}, "Belly", group="Island", vs=bvox,
              offset=(0.0, -2.55, 0.0), key="Belly")
    return finish(m, t, {"source": "StormAltar island (gap %.1f deg), rim %.2f / belly %.2f studs" % (
        data["Gap"], bv, bvox), "pivot": "the altar CFrame A (walking top)"})
