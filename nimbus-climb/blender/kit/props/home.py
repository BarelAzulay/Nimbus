"""Home plot keys (wave 2 art-home; catalog blender/catalog/home.json; ARCHITECTURE_V3 6.3 / recipe 4.8 "World path").

Every station of a tycoon home at every visual level (home_<stem>_<level>: farm 1-40, garden 1-8, foodmachine 1-5,
training 1-5, vault 1-5, house 1-4, fusion 1-3, arena 1, fence 1-3, fountain 1-3, podium 1-3) is baked from the
game's OWN Part build: the kit boots the mock world (bridge), calls HomeBuilder.BuildStationModel(id, level) and
re-voxels every visible box at a finer grain (0.25 stud; the yard fence 0.33) with the cute P4 detail the Part build
cannot afford (props/home_style.py: rounded bushes and berries, brick courses, plank seams, stepped shingles, grass
tufts, light top skins and dark undersides like Voxel.Shade).  The parts HomeBuilder keeps visible over a dressed
station (HomeBuilder._Mesh.keepOf: Neon / ForceField glow, the Fusion Swirl, SurfaceGui sign boards, the Garden's bed
pieces) are left out, so mesh + kept parts = the whole station.  The Garden's bed pieces are per-Part keys
(home_bed_<piece>, pivot = the part).  Pivot of a station key = the station's origin (front -Z, ground y 0).

Colours never change at run time (HomeBuilder ignores the plot accent), so every key bakes its colours: one
SmoothPlastic part "Fixed" (+ "Fixed2"... when one part would pass 10k triangles) and one "Glass" part per glass
transparency.  Each key carries the attachment "LayoutSig" = HomeBuilder._Mesh.signature of the Part build it was
baked from: HomeBuilder tags a key only while the live build still matches.
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
local HB = require(find('HomeBuilder'))
local TC = require(find('TycoonCatalog'))
local Mesh = HB._Mesh
local fmt = string.format
local function comps(cf)
	local t = { cf:GetComponents() }
	for i = 1, #t do t[i] = fmt('%.6f', t[i]) end
	return table.concat(t, ' ')
end
local function defOf(id)
	for _, s in ipairs(TC.Stations) do
		if s.Id == id then return s end
	end
	error('no station ' .. tostring(id))
end
local function boxes(model, origin, skip)
	local inv = origin:Inverse()
	local out = {}
	local list = model:GetDescendants()
	list[#list + 1] = model
	for _, d in ipairs(list) do
		if d:IsA('BasePart') and d.Transparency < 0.99 and not (skip and skip[d.Name]) then
			local shape = 'Block'
			if d:IsA('Part') then shape = d.Shape.Name end
			local c = d.Color
			local par = d.Parent and d.Parent.Name or ''
			out[#out + 1] = fmt('%s %s %s %.4f %.4f %.4f %d %d %d %s %.3f %s %s', d.ClassName, shape, comps(inv * d.CFrame),
				d.Size.X, d.Size.Y, d.Size.Z, math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5),
				math.floor(c.B * 255 + 0.5), d.Material.Name, d.Transparency, d.Name, par)
		end
	end
	table.sort(out)
	return table.concat(out, '\n')
end
function D.stations()
	local out = {}
	for i, s in ipairs(TC.Stations) do
		out[i] = { Id = s.Id, Kind = s.Kind, Max = s.MaxLevel, Stem = Mesh.Stems[s.Id] or Mesh.Stems[s.Kind] or '' }
	end
	return out
end
function D.station(id, level, open)
	local def = defOf(id)
	local m = HB.BuildStationModel(id, level, nil, open)
	local elements = Mesh.elementsOf(def)
	local keepList, keepSet = Mesh.keepOf(m, elements)
	local n, a, b = Mesh.signature(m, CFrame.new(), keepSet)
	local ext = m:GetExtentsSize()
	local res = { Boxes = boxes(m, CFrame.new(), keepSet), Kept = boxes(m, CFrame.new(), nil), Keep = table.concat(keepList, ','),
		Sig = { n, a, b }, Parts = #m:GetDescendants() }
	m:Destroy()
	return res
end
-- one element part (the first one named `name` in station `id` at level / open) in its own frame
function D.element(id, level, open, name)
	local m = HB.BuildStationModel(id, level, nil, open)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA('BasePart') and d.Name == name and d.Transparency < 0.99 then
			local n, a, b = Mesh.signature(d, d.CFrame)
			local res = { Boxes = boxes(d, d.CFrame, nil), Sig = { n, a, b } }
			m:Destroy()
			return res
		end
	end
	error('no part ' .. name .. ' in ' .. id)
end
return D
"""

_STATE = {}


def driver():
    if "drv" not in _STATE:
        from props.creatures import bridge
        br = bridge()
        br.rt.globals().HOME_DRIVER = _DRIVER
        _STATE["drv"] = br.rt.eval(
            "function() local load_ = loadstring or load; local f, e = load_(HOME_DRIVER, '=props/home.lua'); "
            "if not f then error(e, 0) end; return f() end")()
    return _STATE["drv"]


def station(sid, level, open_=None):
    from bridge import lua2py
    k = ("st", sid, int(level), open_)
    if k not in _STATE:
        _STATE[k] = lua2py(driver().station(sid, int(level), open_))
    return _STATE[k]


def element(sid, level, open_, name):
    from bridge import lua2py
    k = ("el", sid, int(level), open_, name)
    if k not in _STATE:
        _STATE[k] = lua2py(driver().element(sid, int(level), open_, name))
    return _STATE[k]


def stations():
    from bridge import lua2py
    if "stations" not in _STATE:
        _STATE["stations"] = lua2py(driver().stations())
    return _STATE["stations"]


def parse_boxes(text):
    out = []
    for line in (text or "").split("\n"):
        if not line:
            continue
        f = line.split(" ")
        v = [float(x) for x in f[2:14]]
        R = np.array([[v[3], v[4], v[5]], [v[6], v[7], v[8]], [v[9], v[10], v[11]]])
        out.append({"cls": f[0], "shape": f[1], "pos": np.array(v[:3]), "R": R,
                    "size": np.array([float(x) for x in f[14:17]]),
                    "rgb": (int(f[17]), int(f[18]), int(f[19])), "mat": f[20], "tr": float(f[21]), "name": f[22],
                    "parent": f[23] if len(f) > 23 else ""})
    return out


def layout_sig(sig):
    n, a, b = sig
    return {"pos": [int(n), round(float(a), 4), round(float(b), 4)], "rot": np.eye(3).tolist()}


def budget_tris(entry, default):
    """the catalog budget of this key (build_all resolves the same entry; the bake steps its detail down to fit)"""
    import json
    import os
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "catalog",
                        "home.json")
    if "budgets" not in _STATE:
        with open(path) as fh:
            _STATE["budgets"] = json.load(fh).get("budgets", {})
    b = _STATE["budgets"].get(entry.get("budget") or "", {})
    return int(b.get("tris") or default)


def finish(m, sig, meta):
    m.groups = {}
    m.attachments = {"LayoutSig": layout_sig(sig)}
    m.meta = meta
    return m


@prop("home_station")
def home_station(entry, kit):
    """one station level baked from HomeBuilder's own Part build (pivot = the station origin)"""
    from props import home_style as HS
    a = entry.get("args") or {}
    st = station(a["station"], a["level"], a.get("open"))
    bx = parse_boxes(st["Boxes"])
    vs = float(a.get("vs", 0.25))
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    stats = HS.bake(m, bx, vs, budget=budget_tris(entry, 4000), opts=a)
    return finish(m, st["Sig"], {"source": "HomeBuilder.BuildStationModel(%s, %s) Part build" % (a["station"], a["level"]),
                                 "pivot": "station origin", "keep": st["Keep"], "bake": stats})


@prop("home_element")
def home_element(entry, kit):
    """one Garden bed piece baked from its own Part (pivot = the part)"""
    from props import home_style as HS
    a = entry.get("args") or {}
    el = element(a.get("station", "Garden"), a.get("level", 8), a.get("open", 6), a["part"])
    bx = parse_boxes(el["Boxes"])
    vs = float(a.get("vs", 0.125))
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    stats = HS.bake(m, bx, vs, budget=budget_tris(entry, 600), opts=dict(a, name=a["part"]))
    return finish(m, el["Sig"], {"source": "HomeBuilder %s part %s" % (a.get("station", "Garden"), a["part"]),
                                 "pivot": "the part", "bake": stats})
