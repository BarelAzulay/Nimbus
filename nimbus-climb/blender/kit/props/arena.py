"""Arena + dungeon keys baked from the game's OWN builds (wave 2 art-arenadungeon; catalog
blender/catalog/arenadungeon.json; ARCHITECTURE_V3 6.3 / recipe 4.8 "World path").

The kit boots the mock world (bridge), sets ArenaBuilder._Kit / DungeonBuilder._Kit and runs LobbyBuilder.Build(),
ArenaBuilder.Build(lobbyInfo), ArenaBuilder.BuildPocket(1), every DungeonBuilder template and one dungeon run (the
portcullis frames are made at PlaceRoom).  Every Mesh.tag call in the two builders is recorded as {Key, Target,
Origin, Look, Keep, Scale}; the first target of a key is the one baked (every other target of that key must have the
same LayoutSig, D.run checks it and the build fails otherwise).

  * "ad_baked"   a piece re-voxeled FINER from its Part build (props/arena_style.py: 0.25-1 stud voxels, the cute P4
                 look with bricks, flagstones, planks, leaves, puffs, light tops / dark undersides), Keep parts left
                 out (they stay visible over the mesh: flames, glows, sign panels, door bars), tint parts (Seat /
                 Banner / Wall ...) as their own MeshPart coloured per instance (ML_Primary / ML_Secondary).
                 Pivot = the Tag origin.  LayoutSig = the Part build's signature unless args.sig is false (scaled
                 pieces: crates, stalagmites, trees).
  * dungeon.py   the designed pieces (voxel cave rocks, floor cracks).

Deterministic: the mock world is seeded like the game, every random pick in the bake is a hash of the cell.
"""
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
local fmt = string.format
local state = nil
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
			out[#out + 1] = fmt('%s %s %s %.4f %.4f %.4f %d %d %d %s %.3f %s %s', d.ClassName, shape, comps(inv * d.CFrame),
				d.Size.X, d.Size.Y, d.Size.Z, math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5),
				math.floor(c.B * 255 + 0.5), d.Material.Name, d.Transparency, d.Name, d.Parent and d.Parent.Name or '')
		end
	end
	table.sort(out)
	return table.concat(out, '\n')
end
local function color(v)
	if typeof(v) == 'Color3' then return { v.R, v.G, v.B } end
	return nil
end
function D.run()
	if state then return state end
	local LB = require(find('LobbyBuilder'))
	local AB = require(find('ArenaBuilder'))
	local DB = require(find('DungeonBuilder'))
	AB._Kit = { Targets = {} }
	DB._Kit = { Targets = {} }
	local info = LB.Build()
	AB.Build(info)
	AB.BuildPocket(1)
	DB.Build(info)
	DB.EnsureTemplates()
	local okRun, pocket = pcall(DB.BuildRun, 1, 1, 7)
	if okRun and type(pocket) == 'table' then
		pcall(DB.PlaceRoom, pocket, 2)
	end
	local recs = {}
	for _, r in ipairs(AB._Kit.Targets) do r.Mesh = AB._Mesh; recs[#recs + 1] = r end
	for _, r in ipairs(DB._Kit.Targets) do r.Mesh = DB._Mesh; recs[#recs + 1] = r end
	AB._Kit, DB._Kit = nil, nil
	local targets, count, bad = {}, {}, {}
	local first = {}
	local targetSet = {}
	for _, r in ipairs(recs) do targetSet[r.Target] = true end
	local nested = {}
	for _, r in ipairs(recs) do
		local a = r.Target.Parent
		while a do
			if targetSet[a] then nested[#nested + 1] = r.Key .. ' in ' .. a.Name; break end
			a = a.Parent
		end
	end
	local places = {}
	for _, r in ipairs(recs) do
		local key = r.Key
		count[key] = (count[key] or 0) + 1
		local look = {}
		for k, v in pairs(r.Look or {}) do look[k] = color(v) end
		local keepSet = {}
		for _, k in ipairs(r.Keep or {}) do keepSet[k] = true end
		places[#places + 1] = { Key = key, Origin = comps(r.Origin), Look = look, Scale = r.Scale or 1, Path = r.Target:GetFullName(),
			Kept = (next(keepSet) ~= nil) and boxes(r.Target, CFrame.new(), function(d) return not keepSet[d.Name] end) or '' }
		local n, a, b = r.Mesh.Signature(r.Target, r.Origin, r.Scale, r.Keep)
		local f = first[key]
		if f and not f[4] then
			local tol = 0.05 + n * 1e-4
			if (r.Scale or 1) == 1 and (n ~= f[1] or math.abs(a - f[2]) > tol or math.abs(b - f[3]) > tol) then
				bad[#bad + 1] = fmt('%s: %s (%d %.3f %.3f) vs (%d %.3f %.3f)', key, r.Target:GetFullName(), n, a, b, f[1], f[2], f[3])
			end
		else
			first[key] = { n, a, b, (r.Scale or 1) ~= 1 }
			local look = {}
			for k, v in pairs(r.Look or {}) do look[k] = color(v) end
			local keep = {}
			for _, k in ipairs(r.Keep or {}) do keep[#keep + 1] = k end
			targets[#targets + 1] = {
				Key = key, Name = r.Target.Name, Class = r.Target.ClassName, Origin = comps(r.Origin), Sig = { n, a, b },
				Boxes = boxes(r.Target, r.Origin), Look = look, Keep = table.concat(keep, ','), Scale = r.Scale or 1,
				Pivot = comps(r.Target:IsA('BasePart') and r.Target.CFrame or r.Target:GetPivot()),
			}
		end
	end
	state = { Targets = targets, Count = count, Bad = bad, Nested = nested, Places = places }
	return state
end
return D
"""

_STATE = {}


def driver():
    if "drv" not in _STATE:
        from bridge import Bridge
        br = _STATE.setdefault("br", Bridge())
        br.rt.globals().ARENA_DRIVER = _DRIVER
        _STATE["drv"] = br.rt.eval(
            "function() local load_ = loadstring or load; local f, e = load_(ARENA_DRIVER, '=props/arena.lua'); "
            "if not f then error(e, 0) end; return f() end")()
    return _STATE["drv"]


def world():
    if "world" not in _STATE:
        from bridge import lua2py
        w = lua2py(driver().run())
        bad = list((w.get("Bad") or {}).values()) if isinstance(w.get("Bad"), dict) else list(w.get("Bad") or [])
        nested = list((w.get("Nested") or {}).values()) if isinstance(w.get("Nested"), dict) else list(w.get("Nested") or [])
        if nested:
            raise RuntimeError("nested Mesh.tag targets (a dress would hide the other): %s" % nested[:6])
        w["BadList"] = bad
        _STATE["world"] = w
    return _STATE["world"]


def targets():
    t = world()["Targets"]
    return list(t.values()) if isinstance(t, dict) else list(t)


def target(key):
    for t in targets():
        if t["Key"] == key:
            return t
    raise KeyError("no Mesh.tag target recorded for %s (ArenaBuilder / DungeonBuilder)" % key)


def placements():
    """key -> number of tagged targets (tools/mesh_budget scene)"""
    return dict(world()["Count"])


def places():
    """every tagged target: {Key, Origin (CFrame components), Look, Scale, Kept (the keep parts' boxes, world space)}"""
    p = world()["Places"]
    return list(p.values()) if isinstance(p, dict) else list(p)


def parse_boxes(text, scale=1.0):
    out = []
    for line in (text or "").split("\n"):
        if not line:
            continue
        f = line.split(" ")
        v = [float(x) for x in f[2:14]]
        R = np.array([[v[3], v[4], v[5]], [v[6], v[7], v[8]], [v[9], v[10], v[11]]])
        out.append({"cls": f[0], "shape": f[1], "pos": np.array(v[:3]) / scale, "R": R,
                    "size": np.array([float(x) for x in f[14:17]]) / scale,
                    "rgb": (int(f[17]), int(f[18]), int(f[19])), "mat": f[20], "tr": float(f[21]), "name": f[22],
                    "parent": f[23] if len(f) > 23 else ""})
    return out


def layout_sig(sig):
    n, a, b = sig
    return {"pos": [int(n), round(float(a), 4), round(float(b), 4)], "rot": np.eye(3).tolist()}


def budget_tris(entry, default):
    import json
    import os
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "catalog",
                        "arenadungeon.json")
    if "budgets" not in _STATE:
        with open(path) as fh:
            _STATE["budgets"] = json.load(fh).get("budgets", {})
    b = _STATE["budgets"].get(entry.get("budget") or "", {})
    return int(b.get("tris") or default)


# names the dungeon signature leaves out (random protruding stones: the mesh draws its own)
SKIP = {"Brick"}


@prop("ad_baked")
def ad_baked(entry, kit):
    """one tagged piece baked from its own Part build (pivot = the Tag origin)"""
    from props import arena_style as AS
    a = entry.get("args") or {}
    t = target(a.get("target") or entry["key"])
    scale = float(t.get("Scale") or 1)
    keep = set(x for x in (t.get("Keep") or "").split(",") if x)
    bx = [b for b in parse_boxes(t["Boxes"], scale) if b["name"] not in keep and b["name"] not in SKIP]
    glow = sorted(set(b["name"] for b in bx if b["mat"] == "Neon"))
    if glow:
        raise RuntimeError("%s: Neon parts %s are not in the Tag keep list (they would be hidden)" % (entry["key"], glow))
    look = t.get("Look") or {}
    tints = {}
    for name, slot in (a.get("tints") or {}).items():
        if slot not in look:
            raise RuntimeError("%s: tint %s needs look %s (Mesh.tag look has %s)" % (entry["key"], name, slot, sorted(look)))
        tints[name] = slot
    vs = float(a.get("vs", 0.25))
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    stats = AS.bake(m, bx, vs, budget=budget_tris(entry, 4000), opts=dict(a, tints=tints))
    m.groups = {}
    m.attachments = {}
    if a.get("sig", True):
        bad = [x for x in world()["BadList"] if x.startswith(entry["key"] + ":")]
        if bad:
            raise RuntimeError("%s: tagged targets differ from the baked one (LayoutSig would reject them): %s"
                               % (entry["key"], bad[:3]))
        m.attachments["LayoutSig"] = layout_sig(t["Sig"])
    m.meta = {"source": "%s %s (Mesh.tag target)" % (t["Class"], t["Name"]), "pivot": "the Tag origin",
              "keep": sorted(keep), "tints": tints, "scale": scale, "bake": stats,
              "previewLook": {k: [round(float(x) * 255) for x in v[:3]] for k, v in look.items()}}
    return m
