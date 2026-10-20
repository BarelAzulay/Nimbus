"""The lupa bridge: runs the game's own sculpt code (src/shared/Voxel.lua + PetBuilder.lua / BossBuilder.lua) inside
tools/robloxmock.lua at a chosen MESH resolution K and returns the shaded voxel grids, hinges, palette and anchors.

Nothing in src/ is edited, at run time or otherwise: the game modules expose two read-only hooks for the kit,
    PetBuilder._Blueprint(petDef, detail, k)  -> bp (+ bp.Anchors)      (no part budget, nothing cached)
    BossBuilder._Blueprint(bossId, k)         -> { Grids, Order, Joints, Palette, ... }
and the bridge's Lua driver only WRAPS Voxel.Shade / Voxel.Merge (on the shared Voxel table, restored afterwards) to
read the grids instead of the merged boxes.  The game never calls the hooks (smoke petbuilder / p3_evolved prove it).

    from bridge import Bridge
    br = Bridge()                                     # boots one mock world (~2 s), reused for every call
    bp = br.pet("pebble_pup", k=1.38)                 # PetBlueprint (groups with grids, palette, anchors)
    bp = br.pet("pebble_pup", k=1.38, look={"Accessory": "Crown"})
    pal = br.palette_probe("pebble_pup", looks=[...]) # palettes of the same pet with other Look colours
    boss = br.boss("lava_golem", k=1.5)

Coordinates: grids are integer voxels (x right, y up, z BACK = Roblox +Z; the pet faces -Z), voxel size =
VOXEL / group K studs (pets: VOXEL = 0.1 stud = 1 design unit).  Hinges are CFrames in DESIGN units (pets).
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, "tools"))

PET_VOXEL = 0.1  # PetBuilder VOXEL (studs per design unit)
BOSS_VOXEL = 0.5  # BossBuilder VOXEL

_DRIVER = r"""
local RS = game:GetService('ReplicatedStorage')
local Shared = RS:FindFirstChild('Shared')
local Voxel = require(Shared.Voxel)
local PB = require(Shared.PetBuilder)
local BB = require(Shared.BossBuilder)
local Cat = require(Shared.PetCatalog)

local D = {}

local function c3(v)
	if typeof(v) == 'Color3' then return v end
	if type(v) == 'table' then return Color3.fromRGB(v[1], v[2], v[3]) end
	return v
end

local function petDef(id, look, stage)
	local base = Cat.Get and Cat.Get(id) or (Cat.ById and Cat.ById[id])
	assert(base, 'pet not found ' .. tostring(id))
	local def = {}
	for k, v in pairs(base) do def[k] = v end
	local L = {}
	for k, v in pairs(base.Look or {}) do L[k] = v end
	if look then
		for k, v in pairs(look) do
			if v == false then L[k] = nil
			elseif k == 'Primary' or k == 'Secondary' or k == 'Eye' or k == 'WingColor' then L[k] = c3(v)
			else L[k] = v end
		end
	end
	def.Look = L
	def.Evolved = (stage and stage > 0) and stage or nil
	return def
end

-- "x y z keyIndex" lines; keys list
local function serialize(cells, keyIndex, keys)
	local out = {}
	for packed, key in pairs(cells) do
		local idx = keyIndex[key]
		if not idx then
			keys[#keys + 1] = key
			idx = #keys
			keyIndex[key] = idx
		end
		local x, y, z = Voxel.Unpack(packed)
		out[#out + 1] = x .. ' ' .. y .. ' ' .. z .. ' ' .. idx
	end
	table.sort(out)
	return table.concat(out, '\n')
end

local function cfList(cf)
	if not cf then return nil end
	return { cf:GetComponents() }
end

local function styleOf(entry)
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

local function paletteOf(pal)
	local out = {}
	for k, v in pairs(pal) do
		local s = styleOf(v)
		if s then out[k] = s end
	end
	return out
end

-- runs fn with Voxel.Shade / Voxel.Merge wrapped; returns fn's result, shade log, merge log
local function recording(fn)
	local shadeLog, mergeLog, order = {}, {}, {}
	local realShade, realMerge = Voxel.Shade, Voxel.Merge
	Voxel.Shade = function(grid, opts)
		if not shadeLog[grid] then
			local pre = {}
			for k, v in pairs(grid.Cells) do pre[k] = v end
			shadeLog[grid] = { Pre = pre, Opts = opts }
		end
		return realShade(grid, opts)
	end
	Voxel.Merge = function(grid, opts)
		local boxes = {}
		mergeLog[boxes] = grid
		return boxes
	end
	local ok, res = pcall(fn)
	Voxel.Shade, Voxel.Merge = realShade, realMerge
	if not ok then error(res, 0) end
	return res, shadeLog, mergeLog
end

function D.pet(id, look, stage, detail, k, wantPre)
	local def = petDef(id, look, stage)
	local bp, shadeLog, mergeLog = recording(function() return PB._Blueprint(def, detail, k) end)
	local keys, keyIndex = {}, {}
	local groups = {}
	local gridOf = {}
	for gi, gr in ipairs(bp.Groups) do
		local g = { Name = gr.Name, Kind = gr.Kind, Side = gr.Side, Amp = gr.Amp, Index = gr.Index, K = gr.K or bp.K,
			Hinge = cfList(gr.Hinge) }
		local grid = mergeLog[gr.Boxes]
		if grid then
			gridOf[gr.Name] = grid
			g.Cells = serialize(grid.Cells, keyIndex, keys)
			local sl = shadeLog[grid]
			if sl and wantPre then g.Pre = serialize(sl.Pre, keyIndex, keys) end
			if sl then
				local o = {}
				for kk, vv in pairs(sl.Opts or {}) do
					if type(vv) ~= 'table' then o[kk] = vv end
				end
				g.ShadeOpts = o
			end
		elseif gr.Name == 'WingR' or gr.Name == 'Wing2R' then
			g.MirrorOf = (gr.Name == 'WingR') and 'WingL' or 'Wing2L'
		elseif gr.Boxes then
			local b = {}
			for i, bx in ipairs(gr.Boxes) do b[i] = { bx.X0, bx.Y0, bx.Z0, bx.X1, bx.Y1, bx.Z1, bx.Key } end
			g.Boxes = b
		end
		groups[gi] = g
	end
	local A = bp.Anchors or {}
	local eyes = {}
	for i, e in ipairs(A.Eyes or {}) do
		local rows = {}
		for r, cols in ipairs(e.Mask) do
			local s = {}
			for c, ch in ipairs(cols) do s[c] = ch end
			rows[r] = table.concat(s)
		end
		eyes[i] = { XLeft = e.XLeft, Y = e.Y, Mask = rows }
	end
	local lids = {}
	for i, cells in ipairs(A.LidCells or {}) do
		local l = {}
		for j, c in ipairs(cells) do l[j] = { c[1], c[2], c[3], c[4] } end
		lids[i] = l
	end
	local function keyset(t)
		local o = {}
		for kk, vv in pairs(t or {}) do if vv then o[#o + 1] = kk end end
		table.sort(o)
		return o
	end
	local anchors = {}
	for kk, vv in pairs(A) do
		if kk ~= 'Eyes' and kk ~= 'LidCells' and kk ~= 'NoShade' and kk ~= 'Keep' then anchors[kk] = vv end
	end
	local pulse = {}
	for kk in pairs(bp.Pulse or {}) do pulse[#pulse + 1] = kk end
	table.sort(pulse)
	local look2 = bp.Look
	return {
		K = bp.K, Grow = bp.Grow or 1, Detail = bp.Detail, Finish = bp.Finish, Groups = groups, Keys = keys,
		Palette = paletteOf(bp.Pal), Anchors = anchors, Eyes = eyes, LidCells = lids, Pulse = pulse,
		NoShade = keyset(A.NoShade), Keep = keyset(A.Keep), Species = look2.Species, WingStyle = look2.WingStyle,
		Accessory = look2.Accessory, Rarity = look2.Rarity, Id = look2.Id, Evolved = look2.Evolved,
		Look = { Primary = styleOf(look2.Primary), Secondary = styleOf(look2.Secondary), Eye = styleOf(look2.Eye),
			WingColor = styleOf(look2.WingColor), Glow = look2.Glow },
	}
end

-- the palette only (colour probes): a coarse sculpt is enough
function D.palette(id, look, stage, detail, k)
	local def = petDef(id, look, stage)
	local bp = recording(function() return PB._Blueprint(def, detail, k) end)
	return paletteOf(bp.Pal)
end

function D.boss(id, k)
	local bp = BB._Blueprint(id, k)
	assert(bp, 'unknown boss ' .. tostring(id))
	local keys, keyIndex = {}, {}
	local groups = {}
	for i, name in ipairs(bp.Order) do
		local j = bp.Joints[name] or {}
		groups[i] = { Name = name, Cells = serialize(bp.Grids[name].Cells, keyIndex, keys), Pivot = j.Pivot,
			Parent = j.Parent or '' }
	end
	return { K = k, VoxelStuds = bp.VoxelStuds, Groups = groups, Keys = keys, Palette = paletteOf(bp.Palette) }
end

return D
"""


def lua2py(v):
    """lupa table -> python (arrays become lists, others dicts)."""
    if hasattr(v, "keys") and hasattr(v, "values"):
        ks = list(v.keys())
        if ks and all(isinstance(k, int) for k in ks):
            return [lua2py(v[k]) for k in sorted(ks)]
        if not ks:
            return []
        return {(k.decode() if isinstance(k, bytes) else k): lua2py(v[k]) for k in ks}
    if isinstance(v, bytes):
        return v.decode()
    return v


def parse_cells(text, keys):
    """'x y z idx' lines -> (N, 3) int array, list of key strings"""
    if not text:
        return np.zeros((0, 3), np.int32), []
    a = np.array(text.split(), np.int64).reshape(-1, 4)
    return a[:, :3].astype(np.int32), [keys[i - 1] for i in a[:, 3]]


def base_key(key):
    """Voxel.BaseKey: ('Fur', None) / ('Fur', 'Light') / ('Fur', 'Dark')"""
    if key.endswith("_Light"):
        return key[:-6], "Light"
    if key.endswith("_Dark"):
        return key[:-5], "Dark"
    return key, None


def cf_from_components(c):
    """CFrame:GetComponents() -> (pos (3,), R (3, 3))"""
    if not c:
        return np.zeros(3), np.eye(3)
    c = [float(x) for x in c]
    return np.array(c[:3]), np.array(c[3:12]).reshape(3, 3)


class GroupGrid:
    """One blueprint group: voxels (N, 3) ints + palette key per voxel (with _Light / _Dark variants)."""

    def __init__(self, name, xyz, keys, K, kind=None, side=1, amp=0, index=0, hinge=None, shade_opts=None, pre=None):
        self.name, self.xyz, self.keys, self.K = name, xyz, keys, float(K)
        self.kind, self.side, self.amp, self.index = kind, side, amp, index
        self.hinge = hinge  # (pos design units, R) or None
        self.shade_opts = shade_opts or {}
        self.pre = pre  # (xyz, keys) before Voxel.Shade, or None

    def as_dict(self):
        return {(int(x), int(y), int(z)): k for (x, y, z), k in zip(self.xyz.tolist(), self.keys)}

    def mirrored(self, name):
        xyz = self.xyz.copy()
        xyz[:, 0] *= -1
        g = GroupGrid(name, xyz, list(self.keys), self.K, self.kind, -self.side, self.amp, self.index, None, self.shade_opts)
        return g


class PetBlueprint:
    def __init__(self, raw):
        self.raw = raw
        self.K = float(raw["K"])
        self.grow = float(raw.get("Grow") or 1)
        self.palette = raw["Palette"]  # key -> [r, g, b (0..1), material, transparency]
        self.anchors = raw.get("Anchors") or {}
        self.eyes = raw.get("Eyes") or []
        self.lid_cells = raw.get("LidCells") or []
        self.no_shade = set(raw.get("NoShade") or [])
        self.keep = set(raw.get("Keep") or [])
        self.pulse = set(raw.get("Pulse") or [])
        self.species = raw.get("Species")
        self.id = raw.get("Id")
        self.finish = raw.get("Finish")
        self.groups = []
        keys = raw.get("Keys") or []
        by_name = {}
        for g in raw.get("Groups") or []:
            hinge = cf_from_components(g.get("Hinge")) if g.get("Hinge") else None
            if g.get("Cells") is not None:
                xyz, ks = parse_cells(g["Cells"], keys)
                pre = parse_cells(g["Pre"], keys) if g.get("Pre") else None
                gg = GroupGrid(g["Name"], xyz, ks, g.get("K") or self.K, g.get("Kind"), g.get("Side") or 1,
                               g.get("Amp") or 0, g.get("Index") or 0, hinge, g.get("ShadeOpts"), pre)
            elif g.get("MirrorOf"):
                src = by_name[g["MirrorOf"]]
                gg = src.mirrored(g["Name"])
                gg.hinge = hinge
                gg.side = g.get("Side") or -1
            else:
                boxes = g.get("Boxes") or []
                cells = {}
                for b in boxes:
                    for x in range(int(b[0]), int(b[3]) + 1):
                        for y in range(int(b[1]), int(b[4]) + 1):
                            for z in range(int(b[2]), int(b[5]) + 1):
                                cells[(x, y, z)] = b[6]
                xyz = np.array(list(cells.keys()), np.int32).reshape(-1, 3)
                gg = GroupGrid(g["Name"], xyz, list(cells.values()), g.get("K") or self.K, g.get("Kind"),
                               g.get("Side") or 1, g.get("Amp") or 0, g.get("Index") or 0, hinge)
            by_name.setdefault(gg.name, gg)
            self.groups.append(gg)

    def group(self, name):
        for g in self.groups:
            if g.name == name:
                return g
        return None

    def color(self, key):
        """(r, g, b) 0..1 of a palette key, resolving _Light / _Dark like Voxel.resolveStyle"""
        e = self.palette.get(key)
        if e is not None:
            return tuple(e[:3])
        b, v = base_key(key)
        if v is None:
            return (200 / 255, 200 / 255, 205 / 255)
        from nvox import colors as C
        c = self.color(b)
        return C.shade_light(c) if v == "Light" else C.shade_dark(c)

    def style(self, key):
        """(material, transparency) of a palette key (variants inherit their base)"""
        e = self.palette.get(key)
        if e is None:
            b, v = base_key(key)
            if v is not None:
                return self.style(b)
            return ("SmoothPlastic", 0.0)
        return (e[3], float(e[4]))


class Bridge:
    """One booted mock DataModel (server) with src/ mounted; the Lua driver above is loaded once."""

    def __init__(self, engine=None):
        import render_model as RM  # tools/render_model.py: the mock world loader (lupa)
        self.world = RM.LuaWorld("server", engine=engine)
        self.rt = self.world.rt
        self.rt.globals().KIT_DRIVER = _DRIVER
        self.D = self.rt.eval(
            "function() local load_ = loadstring or load; local f, e = load_(KIT_DRIVER, '=blender/kit/bridge.lua'); "
            "if not f then error(e, 0) end; return f() end")()
        self.engine = self.world.engine

    def _table(self, d):
        if d is None:
            return None
        t = {}
        for k, v in d.items():
            if isinstance(v, (list, tuple)):
                v = self.rt.table_from(list(v))
            t[k] = v
        return self.rt.table_from(t)

    def pet(self, pet_id, k, stage=0, detail="High", look=None, want_pre=False):
        res = self.D.pet(pet_id, self._table(look), int(stage), detail, float(k), bool(want_pre))
        return PetBlueprint(lua2py(res))

    def palette(self, pet_id, look=None, stage=0, detail="High", k=0.5):
        return lua2py(self.D.palette(pet_id, self._table(look), int(stage), detail, float(k)))

    def boss(self, boss_id, k):
        raw = lua2py(self.D.boss(boss_id, float(k)))
        keys = raw.get("Keys") or []
        out = {"K": raw["K"], "voxelStuds": raw["VoxelStuds"], "palette": raw["Palette"], "groups": []}
        for g in raw["Groups"]:
            xyz, ks = parse_cells(g["Cells"], keys)
            out["groups"].append({"name": g["Name"], "xyz": xyz, "keys": ks, "pivot": g.get("Pivot"),
                                  "parent": g.get("Parent") or ""})
        return out

    def errors(self):
        return self.world.script_errors()


if __name__ == "__main__":
    import json
    import time
    t0 = time.time()
    br = Bridge()
    t1 = time.time()
    pid = sys.argv[1] if len(sys.argv) > 1 else "pebble_pup"
    k = float(sys.argv[2]) if len(sys.argv) > 2 else 1.38
    bp = br.pet(pid, k)
    print(json.dumps({"boot_s": round(t1 - t0, 2), "pet_s": round(time.time() - t1, 2), "K": bp.K,
                      "groups": [(g.name, g.kind, len(g.keys), g.K) for g in bp.groups],
                      "anchors": {k2: v for k2, v in bp.anchors.items()}, "eyes": bp.eyes[:1]}, indent=1, default=str))
