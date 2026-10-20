-- smoke_p6_gates.lua: the Phase 6 Blender gate meshes (ARCHITECTURE_V3.md "## Phase 6" 6.0.3 / 6.3 art-gates;
-- owner: art-gates, wave 2). Loaded by tools/smoke.py in BOTH worlds.
--   p6gates_server   (server) the committed manifests gate_<obby|ring|arena|dungeon|home|altar> (recipe 4.2 budget:
--                    <= 8k tris, <= 20 MeshParts; no Neon part and no Glow / Swirl / Gem name: those stay Parts);
--                    WorldStyle.BuildGate tags every gate (ML_DressKey by glyph / shape, ML_Primary = the gate colour,
--                    ML_Offset puts the mesh on the site, ML_Keep = every visible non-mesh part incl. the Neon bits,
--                    the pad, the lanterns, the anchors) and a later builder extra joins ML_Keep; the tagged gate has
--                    EXACTLY the parts (names, classes, count) of the same gate built by an untagged copy of
--                    WorldStyle (no MeshLibrary next to it)
--   client_p6gates   (client) fixture mode (templates from the committed manifests, preloaded on this device): a
--                    BuildGate gate is dressed: the stone / frame / trim / crest voxels go transparent locally, the
--                    Neon glow / swirl / gems / star gems, the pad and a torch added after the tag stay visible, the
--                    mesh sits on the site (Trim part centre = site * manifest centre) in the gate colour
-- Deterministic: fixed specs and sites, sorted names.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local fmt = string.format

local KEYS = { "gate_obby", "gate_ring", "gate_arena", "gate_dungeon", "gate_home", "gate_altar" }
-- every BuildGate spec the game uses (lobby, arena, dungeon) + the reference sample's Home + a crown-glyph hoop
local SPECS = {
	{ Id = "Obby", Color = "Blue", Glyph = "cloud", Pad = true, Stars = 3, Key = "gate_obby" },
	{ Id = "Dungeon", Color = "Purple", Glyph = "torch", Pad = true, Key = "gate_dungeon" },
	{ Id = "Ring", Color = "Gold", Glyph = "crown", Pad = true, Key = "gate_ring" },
	{ Id = "Arena", Color = "Red", Glyph = "swords", Pad = false, Key = "gate_arena" },
	{ Id = "Altar", Color = "Cyan", Glyph = "bolt", Pad = false, Key = "gate_altar" },
	{ Id = "Return", Color = "Green", Glyph = "house", Pad = false, Key = "gate_home" },
	{ Id = "Home", Color = "Yellow", Glyph = "house", Pad = false, Key = "gate_home" },
	{ Id = "HoopCrown", Color = "Pink", Glyph = "crown", Shape = "Hoop", Pad = false, Key = "gate_obby" },
}
local NEON_NAMES = { Glow = true, Swirl = true, Gem = true, StarGem = true, CrestEye = true, CrestWindow = true, CrestBolt = true, PadTileGlow = true, LanternGlow = true }

local function req(path)
	local ok, inst = pcall(Mock.GetPath, ROOTS.shared .. "/" .. path)
	if not ok or not inst then
		return nil, nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil, inst
end

local function partsOf(model)
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			list[#list + 1] = d
		end
	end
	return list
end

-- "Name:Class" multiset as a sorted string
local function signature(model)
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		list[#list + 1] = d.Name .. ":" .. d.ClassName
	end
	table.sort(list)
	return table.concat(list, ",")
end

local function siteOf(i)
	return CFrame.new(4000 + i * 40, 500, 3000) * CFrame.Angles(0, (i % 4) * math.pi / 2, 0)
end

local function build(WS, folder, i, sp)
	return WS.BuildGate(folder, siteOf(i), { Id = sp.Id, Title = sp.Id, Info = "", Color = sp.Color, Glyph = sp.Glyph, Pad = sp.Pad, Stars = sp.Stars, Shape = sp.Shape, Name = "Portal_" .. sp.Id })
end

-- an untagged WorldStyle: a copy next to copies of Voxel and Theme, with no MeshLibrary beside it
local function untaggedWorldStyle()
	local _, wsInst = req("WorldStyle")
	local _, vInst = req("Voxel")
	local _, tInst = req("Theme")
	if not (wsInst and vInst and tInst) then
		return nil, nil
	end
	local box = Instance.new("Folder")
	box.Name = "P6GatesNoMesh"
	box.Parent = RS
	local ws = wsInst:Clone()
	ws.Parent = box
	vInst:Clone().Parent = box
	tInst:Clone().Parent = box
	local ok, mod = pcall(require, ws)
	return ok and type(mod) == "table" and mod or nil, box
end

local function installTemplate(ML, root, key)
	local man = ML.Manifest(key)
	if not man then
		return nil
	end
	local tpl = Instance.new("Model")
	tpl.Name = key
	for _, p in ipairs(man.Parts) do
		local part = Instance.new("MeshPart")
		part.Name = p.name
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		part.CFrame = CFrame.new(p.center[1], p.center[2], p.center[3])
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Parent = tpl
	end
	tpl:SetAttribute("ML_Status", "ready")
	tpl.Parent = root
	return tpl
end

----------------------------------------------------------------------------------------------------------------------
if IS_SERVER then
S.p6gates_server = guarded("p6gates_server", function()
	local ML = req("MeshLibrary")
	local WS = req("WorldStyle")
	if not T.check(ML and WS and type(ML.Manifest) == "function" and type(WS.BuildGate) == "function" and type(WS.GateMeshKey) == "function",
		"p6 gates: MeshLibrary.Manifest, WorldStyle.BuildGate + GateMeshKey load") then
		return
	end
	ML._Reset()
	-- 1. the committed manifests: budget, names, no Neon
	for _, key in ipairs(KEYS) do
		local man = ML.Manifest(key)
		if T.check(man ~= nil and #man.Parts > 0, "p6 gates: committed manifest " .. key) then
			local tris, bad = 0, {}
			for _, p in ipairs(man.Parts) do
				if p.material == "Neon" or p.name == "Glow" or p.name == "Swirl" or p.name == "Gem" then
					bad[#bad + 1] = p.name
				end
			end
			for _, p in ipairs(man.Raw.Parts or {}) do
				tris = tris + (tonumber(p.Tris) or 0)
			end
			T.check(tris > 0 and tris <= 8000, fmt("p6 gates: %s <= 8000 tris (%d)", key, tris))
			T.check(#man.Parts <= 20, fmt("p6 gates: %s <= 20 MeshParts (%d)", key, #man.Parts))
			T.check(#bad == 0, "p6 gates: " .. key .. " has no Neon / Glow / Swirl / Gem part (they stay Parts)", table.concat(bad, ","))
			local trim = false
			for _, p in ipairs(man.Parts) do
				if p.name == "Trim" and type(p.color) == "table" and p.color[1] == "Primary" then
					trim = true
				end
			end
			T.check(trim, "p6 gates: " .. key .. " has a Trim part tinted by ML_Primary")
		end
	end
	-- 2. tags on every BuildGate gate, parts identical to an untagged build
	local WS0, box0 = untaggedWorldStyle()
	T.check(WS0 ~= nil and WS0 ~= WS, "p6 gates: an untagged WorldStyle copy loads (no MeshLibrary beside it)")
	local folder = Instance.new("Folder")
	folder.Name = "P6Gates"
	folder.Parent = workspace
	local ok, err = pcall(function()
		for i, sp in ipairs(SPECS) do
			local label = "p6 gates " .. sp.Id
			local model = build(WS, folder, i, sp)
			if T.check(model ~= nil, label .. ": BuildGate returns the gate") then
				T.eq(model:GetAttribute("ML_DressKey"), sp.Key, label .. ": ML_DressKey")
				T.check(CollectionService:HasTag(model, "ML_Dress"), label .. ": the ML_Dress tag")
				local color = WS.Palette.Accent[sp.Color]
				T.check(model:GetAttribute("ML_Primary") == color, label .. ": ML_Primary = the gate colour")
				local off = model:GetAttribute("ML_Offset")
				T.check(type(off) == "string" and off ~= "", label .. ": ML_Offset is set")
				if sp.Glyph == "cloud" then
					T.eq(model:GetAttribute("ML_Stars"), sp.Stars, label .. ": ML_Stars = the lit stars")
				end
				-- the mesh origin = the site: pivot (GlowCore) * offset
				local core = model:FindFirstChild("GlowCore")
				T.check(core ~= nil and model.PrimaryPart == core, label .. ": GlowCore is the PrimaryPart")
				if core then
					local y = core.CFrame:PointToObjectSpace(siteOf(i).Position)
					T.check(math.abs(y.X) < 1e-3 and math.abs(y.Z) < 1e-3 and math.abs(y.Y + 11.5) < 1e-3, label .. ": the site is 11.5 under GlowCore (ML_Offset (0, -11.5, 0))")
				end
				local keep = {}
				for name in string.gmatch(model:GetAttribute("ML_Keep") or "", "[^,]+") do
					keep[name] = true
				end
				local missing, leaked = {}, {}
				for _, p in ipairs(partsOf(model)) do
					if WS.GATE_MESH_HIDE[p.Name] then
						if keep[p.Name] then
							leaked[#leaked + 1] = p.Name
						end
					elseif not keep[p.Name] then
						missing[#missing + 1] = p.Name
					end
				end
				table.sort(missing)
				T.check(#missing == 0, label .. ": ML_Keep holds every part the mesh does not replace", table.concat(missing, ","))
				T.check(#leaked == 0, label .. ": ML_Keep holds no mesh-replaced name", table.concat(leaked, ","))
				for name in pairs(NEON_NAMES) do
					if model:FindFirstChild(name) then
						T.check(keep[name] == true, label .. ": the Neon part " .. name .. " stays visible")
					end
				end
				local hidden = 0
				for _, p in ipairs(partsOf(model)) do
					if WS.GATE_MESH_HIDE[p.Name] then
						hidden = hidden + 1
					end
				end
				T.check(hidden > 0, label .. ": the mesh replaces some voxels (" .. hidden .. ")")
				if WS0 then
					local plain = WS0.BuildGate(folder, siteOf(i) * CFrame.new(0, 0, 200), { Id = sp.Id, Title = sp.Id, Info = "", Color = sp.Color, Glyph = sp.Glyph, Pad = sp.Pad, Stars = sp.Stars, Shape = sp.Shape, Name = "Plain_" .. sp.Id })
					T.check(plain:GetAttribute("ML_DressKey") == nil, label .. ": the copy without MeshLibrary does not tag")
					T.eq(#partsOf(model), #partsOf(plain), label .. ": part count unchanged by the tag")
					T.check(signature(model) == signature(plain), label .. ": same instances (names, classes) as the untagged gate")
					plain:Destroy()
				end
				-- a builder extra after the tag (DungeonBuilder torch, ArenaBuilder pedestal) joins ML_Keep; a voxel name does not
				local extra = Instance.new("Part")
				extra.Name = "TorchFoot"
				extra.Parent = model
				local stone = Instance.new("Part")
				stone.Name = "Stone"
				stone.Parent = model
				local keep2 = model:GetAttribute("ML_Keep") or ""
				T.check(string.find("," .. keep2 .. ",", ",TorchFoot,", 1, true) ~= nil, label .. ": a part added later joins ML_Keep")
				T.check(string.find("," .. keep2 .. ",", ",Stone,", 1, true) == nil, label .. ": a later 'Stone' stays mesh-replaced")
			end
		end
		T.eq(WS.GateMeshKey("Arch", "cloud"), "gate_ring", "p6 gates: GateMeshKey(Arch) = gate_ring")
		T.eq(WS.GateMeshKey("Hoop", "nope"), "gate_obby", "p6 gates: GateMeshKey(unknown glyph) = gate_obby")
		-- 3. empty MeshIds: nothing is ready, so no client would dress (the Part gate stays as it is)
		for _, key in ipairs(KEYS) do
			T.check(not ML.IsReady(key), "p6 gates default: " .. key .. " is not ready with the shipped (empty) MeshIds")
		end
	end)
	T.check(ok, "p6gates_server ran to the end", tostring(err))
	folder:Destroy()
	if box0 then
		box0:Destroy()
	end
end)
end

----------------------------------------------------------------------------------------------------------------------
if not IS_SERVER then
S.client_p6gates = guarded("client_p6gates", function()
	local ML = req("MeshLibrary")
	local WS = req("WorldStyle")
	if not T.check(ML and WS and type(ML._Configure) == "function", "p6 gates client: MeshLibrary + WorldStyle load") then
		return
	end
	ML._Reset()
	local root = Instance.new("Folder")
	root.Name = "P6GatesMeshes"
	root.Parent = RS
	local ids = {}
	for i, key in ipairs(KEYS) do
		ids[key] = 9100 + i
		installTemplate(ML, root, key)
	end
	ML._Configure({ Root = root, Ids = ids })
	local world = Instance.new("Folder")
	world.Name = "P6GatesClient"
	world.Parent = workspace
	local ok, err = pcall(function()
		ML.Start()
		Mock.Advance(1)
		T.check(ML.IsReady(KEYS), "p6 gates client fixtures: every gate key ready after the preload")
		for i, sp in ipairs({ SPECS[1], SPECS[2], SPECS[3], SPECS[4], SPECS[5], SPECS[6] }) do
			local label = "p6 gates client " .. sp.Id
			local model = build(WS, world, i, sp)
			-- a builder extra added after BuildGate (DungeonBuilder's torches)
			local torch = Instance.new("Part")
			torch.Name = "Sconce"
			torch.Anchored = true
			torch.Parent = model
			local before = {}
			for _, p in ipairs(partsOf(model)) do
				before[p] = p.Transparency
			end
			ML.Dress(model, model:GetAttribute("ML_DressKey"))
			Mock.Advance(0.3)
			local mesh = model:FindFirstChild("ML_Mesh")
			if T.check(mesh ~= nil, label .. ": dressed (ML_Mesh under the gate)") then
				local wrong = {}
				for p, t0 in pairs(before) do
					local hide = WS.GATE_MESH_HIDE[p.Name] == true
					if hide and p.Transparency ~= 1 then
						wrong[#wrong + 1] = "visible " .. p.Name
					elseif not hide and p.Transparency ~= t0 then
						wrong[#wrong + 1] = "hidden " .. p.Name
					end
				end
				table.sort(wrong)
				T.check(#wrong == 0, label .. ": only the stone / frame / trim / crest voxels are hidden", table.concat(wrong, ","))
				T.check(torch.Transparency == 0, label .. ": a part added after the tag stays visible")
				local trim = mesh:FindFirstChild("Trim")
				local man = ML.Manifest(sp.Key)
				local c = nil
				for _, p in ipairs(man and man.Parts or {}) do
					if p.name == "Trim" then
						c = p.center
					end
				end
				if T.check(trim ~= nil and c ~= nil, label .. ": the mesh has its Trim part") then
					T.check(trim.Color == WS.Palette.Accent[sp.Color], label .. ": Trim = the gate colour")
					local want = siteOf(i) * CFrame.new(c[1], c[2], c[3])
					T.check(trim.Position:FuzzyEq(want.Position, 1e-3), label .. ": the mesh sits on the gate site", tostring(trim.Position) .. " vs " .. tostring(want.Position))
				end
				local neon = mesh:FindFirstChild("Glow") or mesh:FindFirstChild("Swirl") or mesh:FindFirstChild("Gem")
				T.check(neon == nil, label .. ": the mesh brings no Glow / Swirl / Gem (the Neon Parts animate)")
			end
		end
	end)
	T.check(ok, "client_p6gates fixture mode ran to the end", tostring(err))
	ML._Reset()
	root:Destroy()
	world:Destroy()
end)
end

return S
