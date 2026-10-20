-- smoke_p6_lod.lua: the Phase 6 plot LOD (ARCHITECTURE_V3.md "## Phase 6" 6.5 "busiest phone view <= 300k tris";
-- owner: perf-plots, wave 3). Loaded by tools/smoke.py in the client world; runs the same in the default mode and in
-- --mesh mode because it never touches the shared MeshLibrary: it builds a PRIVATE copy (own MeshIds, manifests and
-- template root) and hands it to HomeFx through HomeFx._SetMeshLib, then gives the shared one back.
--   client_p6lod   (client)
--     * empty MeshIds: a plot whose stations carry ML_DressKey but were never dressed is untouched (no ML_Mesh, every
--       Transparency as built, no ML_Lod* attribute); without a template folder HomeFx never even picks a tier;
--       MeshLibrary.SetLod on an undressed target returns false
--     * MeshLibrary.LowKey: "<key>_low" only when usable here AND baked from the same layout (LayoutSig); a stale low
--       manifest (other LayoutSig) and a key without a _low are refused
--     * a dressed max-tier-style plot (house, farm, fence, garden + a nested bed piece, the lobby's Plot base) seen from
--       40 / 150 / 300 studs: near = every mesh on its High key; Low = the house on home_house_4_low (rebuilt ML_Mesh,
--       same pivot), the farm / fence / bed piece on their High keys (no _low uploaded), the garden's stale _low refused,
--       nothing hidden; Far = only the house + the plot base: farm, garden, fence and the nested bed piece hidden (mesh
--       parts and kept glow Parts at Transparency 1, the old value kept in ML_LodT); back near = everything exactly as
--       dressed (High key, transparencies restored, no ML_LodT left)
--     * hysteresis: Far holds at 190 (inside LOD_FAR, outside LOD_FAR - LOD_HYST), Low at 170; High holds at 135, Low at 145
--     * no per-frame work: with a still camera 3 s pass with zero SetLod calls and no re-scan; a tier change costs one
--       SetLod per target; HomeFx only checks every K.NEAR_CHECK
--     * tools/mesh_budget.py mirrors HomeFx's K.LOD_HIGH / LOD_FAR / LOD_HYST (the budget figure applies the same rule)
-- Deterministic: fixed positions, sorted names, no RNG; everything it makes is destroyed at the end.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local fmt = string.format

if IS_SERVER then
	return S
end

local KEYS = { "home_house_4", "home_farm_40", "home_fence_3", "home_garden_8", "home_bed_frame", "prop_plot" }

local function sharedInst(path)
	local ok, inst = pcall(Mock.GetPath, ROOTS.shared .. "/" .. path)
	return ok and inst or nil
end

local function manifestSource(key)
	local inst = sharedInst("MeshManifests/" .. key)
	return inst and inst.Source or nil
end

local function readFile(rel)
	for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
		local fh = io.open(prefix .. rel, "r")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
		end
	end
	return nil
end

-- a private MeshLibrary next to its own MeshIds + MeshManifests (sources: { key = Lua source })
local counter = 0
local function newLib(ids, sources, noRoot)
	counter = counter + 1
	local box = Instance.new("Folder")
	box.Name = "P6LodLib" .. counter
	local lib = sharedInst("MeshLibrary"):Clone()
	lib.Parent = box
	local idsMod = Instance.new("ModuleScript")
	idsMod.Name = "MeshIds"
	local keys = {}
	for k in pairs(ids) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local lines = { "return {" }
	for _, k in ipairs(keys) do
		lines[#lines + 1] = fmt("\t[%q] = %d,", k, ids[k])
	end
	lines[#lines + 1] = "}"
	idsMod.Source = table.concat(lines, "\n")
	idsMod.Parent = box
	local mans = Instance.new("Folder")
	mans.Name = "MeshManifests"
	mans.Parent = box
	local names = {}
	for k in pairs(sources) do
		names[#names + 1] = k
	end
	table.sort(names)
	for _, k in ipairs(names) do
		local m = Instance.new("ModuleScript")
		m.Name = k
		m.Source = sources[k]
		m.Parent = mans
	end
	local root = Instance.new("Folder")
	root.Name = "MeshLibrary"
	root.Parent = box
	box.Parent = RS
	local ML = require(lib)
	if not noRoot then
		ML._Configure({ Root = root })
	end
	return ML, root, box
end

-- what the server's fit leaves for a key: a canonical template (one MeshPart per manifest part), status ready
local function installTemplate(ML, root, key)
	local man = ML.Manifest(key)
	local wrapper = Instance.new("Model")
	local inner = Instance.new("Model")
	inner.Name = "NC " .. key
	inner.Parent = wrapper
	for _, p in ipairs(man.Parts) do
		local part = Instance.new("MeshPart")
		part.Name = p.name
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		part.CFrame = CFrame.new(p.center[1], p.center[2], p.center[3])
		part.Parent = inner
	end
	local tpl = ML._Fit(key, wrapper)
	if tpl then
		tpl:SetAttribute("ML_Status", "ready")
		tpl.Parent = root
	end
	return tpl
end

local function part(parent, name, cf, size, transparency, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CFrame = cf
	p.Size = size or Vector3.new(4, 4, 4)
	p.Transparency = transparency or 0
	if material then
		p.Material = material
	end
	p.Parent = parent
	return p
end

-- a station model the way HomeBuilder tags it: ML_DressKey + ML_Offset (identity) + ML_Keep
local function station(home, id, key, cf, keep)
	local m = Instance.new("Model")
	m.Name = "Station_" .. id
	part(m, "Wall", cf, Vector3.new(8, 6, 8))
	part(m, "Roof", cf * CFrame.new(0, 4, 0), Vector3.new(9, 2, 9))
	local glow = part(m, "Lantern", cf * CFrame.new(0, 6, 0), Vector3.new(1, 1, 1), 0.2, Enum.Material.Neon)
	m.PrimaryPart = m.Wall
	m:SetAttribute("StationId", id)
	m:SetAttribute("Level", 1)
	m:SetAttribute("ML_DressKey", key)
	m:SetAttribute("ML_Keep", keep or "Lantern")
	m.Parent = home
	return m, glow
end

local function meshParts(target)
	local mesh = target:FindFirstChild("ML_Mesh")
	local list = {}
	for _, d in ipairs(mesh and mesh:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			list[#list + 1] = d
		end
	end
	return list, mesh
end

local function allHidden(target)
	local list, mesh = meshParts(target)
	if not mesh or #list == 0 then
		return false
	end
	for _, p in ipairs(list) do
		if p.Transparency < 0.999 then
			return false
		end
	end
	return true
end

local function anyHidden(target)
	for _, p in ipairs((meshParts(target))) do
		if p.Transparency >= 0.999 and p:GetAttribute("ML_LodT") ~= nil then
			return true
		end
	end
	return false
end

local function lodAttrs(root)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:GetAttribute("ML_LodT") ~= nil or d:GetAttribute("ML_LodHidden") ~= nil then
			n = n + 1
		end
	end
	return n
end

S.client_p6lod = guarded("client_p6lod", function()
	local KCm = rawget(_G, "KC")
	local HF = KCm and KCm.M and KCm.M.HomeFx
	if not HF then
		pcall(function()
			HF = require(Mock.GetPath(ROOTS.client .. "/Controllers/HomeFx"))
		end)
	end
	if not T.check(type(HF) == "table" and type(HF._SetMeshLib) == "function" and type(HF.Lod) == "function" and type(HF._LodK) == "table",
		"p6 lod: HomeFx exposes Lod / _SetMeshLib / _LodK") then
		return
	end
	local K = HF._LodK
	HF.Init()
	local cam = workspace.CurrentCamera
	local savedCam = cam and cam.CFrame
	local world = Instance.new("Folder")
	world.Name = "P6LodWorld"
	world.Parent = workspace
	local boxes = {}
	local center = Vector3.new(-6400, 220, 6400)
	local plotCF = CFrame.new(center)
	local function look(dist)
		cam.CFrame = CFrame.new(center + Vector3.new(0, 12, dist), center)
		Mock.Advance(K.Check + 0.15)
	end

	-- a plot like the lobby lays it out: Spot folder > Plot (the lobby's base, dressed by its own key) + Home (NC_Home)
	local function makePlot(name, pos)
		local spot = Instance.new("Folder")
		spot.Name = name
		spot.Parent = world
		local base = Instance.new("Model")
		base.Name = "Plot"
		part(base, "Lawn", CFrame.new(pos), Vector3.new(72, 2, 72))
		part(base, "PodiumBase", CFrame.new(pos + Vector3.new(0, 2, 30)), Vector3.new(4, 1, 4))
		base.PrimaryPart = base.Lawn
		base:SetAttribute("ML_DressKey", "prop_plot")
		base:SetAttribute("ML_Keep", "PodiumBase")
		base.Parent = spot
		local home = Instance.new("Folder")
		home.Name = "Home"
		home:SetAttribute("PlotCFrame", CFrame.new(pos))
		home:SetAttribute("OwnerUserId", 0)
		home.Parent = spot
		local st = {}
		st.House, st.HouseGlow = station(home, "House", "home_house_4", CFrame.new(pos + Vector3.new(-20, 4, -20)))
		st.Farm, st.FarmGlow = station(home, "Press1", "home_farm_40", CFrame.new(pos + Vector3.new(20, 4, -20)))
		st.Fence = station(home, "DecorFence", "home_fence_3", CFrame.new(pos + Vector3.new(0, 4, 34)), "")
		st.Garden, st.GardenGlow = station(home, "Garden", "home_garden_8", CFrame.new(pos + Vector3.new(20, 4, 20)))
		local bed = part(st.Garden, "Bed", CFrame.new(pos + Vector3.new(24, 2, 24)), Vector3.new(3, 1, 4))
		bed:SetAttribute("ML_DressKey", "home_bed_frame")
		st.Bed = bed
		st.Base = base
		CollectionService:AddTag(home, "NC_Home")
		return spot, home, st
	end

	local ok, err = pcall(function()
		if not T.check(cam ~= nil, "p6 lod: a camera in the client world") then
			return
		end
		------------------------------------------------------------------------------------------------
		-- empty MeshIds: nothing happens
		------------------------------------------------------------------------------------------------
		local E, _, ebox = newLib({}, {}, true) -- like the shipped game: no root configured, ReplicatedStorage.MeshLibrary only if a server made one
		boxes[#boxes + 1] = ebox
		E.Start()
		local eSpot, eHome, eSt = makePlot("Spot_P6LodEmpty", center + Vector3.new(400, 0, 0))
		local before = {}
		for _, d in ipairs(eSpot:GetDescendants()) do
			if d:IsA("BasePart") then
				before[d] = d.Transparency
			end
		end
		HF._SetMeshLib(E)
		cam.CFrame = CFrame.new(center + Vector3.new(400, 12, 300), center + Vector3.new(400, 0, 0))
		Mock.Advance(1.2)
		local changed = 0
		for p, t0 in pairs(before) do
			if p.Transparency ~= t0 then
				changed = changed + 1
			end
		end
		local info = HF.Lod(eHome)
		T.check(info ~= nil and changed == 0 and lodAttrs(eSpot) == 0 and eSt.House:FindFirstChild("ML_Mesh") == nil,
			"p6 lod, empty MeshIds: a tagged but undressed plot stays exactly as built (no mesh, no transparency, no ML_Lod*)",
			fmt("%d parts changed, %d attrs", changed, lodAttrs(eSpot)))
		if E.Active() then
			T.info("p6 lod, empty MeshIds: ReplicatedStorage.MeshLibrary exists in this world (--mesh mode), the tier check is skipped")
		else
			T.check(info ~= nil and info.Tier == nil,
				"p6 lod, empty MeshIds: no template folder = HomeFx never picks a tier", info and tostring(info.Tier))
		end
		T.check(E.SetLod(eSt.House, "Hide") == false and eSt.House.Wall.Transparency == 0, "p6 lod: SetLod on an undressed target = false, nothing touched")
		eSpot:Destroy()

		------------------------------------------------------------------------------------------------
		-- fixture mode: templates from the committed manifests + a home_house_4_low (same layout) + a stale farm _low
		------------------------------------------------------------------------------------------------
		local sources, ids = {}, {}
		for i, key in ipairs(KEYS) do
			sources[key] = manifestSource(key)
			ids[key] = 9700 + i
		end
		if not T.check(sources.home_house_4 and sources.prop_plot and sources.home_bed_frame, "p6 lod: the committed manifests home_house_4 / prop_plot / home_bed_frame exist") then
			return
		end
		sources.home_house_4_low = sources.home_house_4 -- same LayoutSig: a valid low key
		ids.home_house_4_low = 9790
		-- a garden _low baked from another layout (LayoutSig changed): must be refused
		sources.home_garden_8_low = string.gsub(sources.home_garden_8, "(LayoutSig%s*=%s*{%s*Pos%s*=%s*{%s*)(%d+)", function(a, n)
			return a .. tostring(tonumber(n) + 7)
		end, 1)
		ids.home_garden_8_low = 9791
		local ML, root, box = newLib(ids, sources)
		boxes[#boxes + 1] = box
		local names = {}
		for k in pairs(ids) do
			names[#names + 1] = k
		end
		table.sort(names)
		for _, key in ipairs(names) do
			installTemplate(ML, root, key)
		end
		ML.Start()
		Mock.Advance(1)
		T.check(ML.IsReady(names), "p6 lod fixtures: every key ready on this device")
		T.check(ML.LowKey("home_house_4") == "home_house_4_low", "LowKey: a usable _low with the same LayoutSig")
		T.check(sources.home_garden_8_low ~= sources.home_garden_8 and ML.LowKey("home_garden_8") == nil, "LowKey: a _low baked from another layout is refused")
		T.check(ML.LowKey("home_farm_40") == nil, "LowKey: no _low uploaded = nil (the High key stays)")

		local spot, home, st = makePlot("Spot_P6Lod", center)
		HF._SetMeshLib(ML)
		for _, target in ipairs({ st.Base, st.House, st.Farm, st.Fence, st.Garden, st.Bed }) do
			ML.Dress(target, target:GetAttribute("ML_DressKey"))
		end
		Mock.Advance(0.3)
		local dressed = 0
		for _, target in ipairs({ st.Base, st.House, st.Farm, st.Fence, st.Garden, st.Bed }) do
			if target:FindFirstChild("ML_Mesh") then
				dressed = dressed + 1
			end
		end
		T.check(dressed == 6, "p6 lod: the plot base, 4 stations and the nested bed piece are dressed", dressed .. "/6")
		local glowT = st.HouseGlow.Transparency

		-- count SetLod calls (the per-frame check)
		local calls = 0
		local realSetLod = ML.SetLod
		ML.SetLod = function(...)
			calls = calls + 1
			return realSetLod(...)
		end

		-- near: High
		look(40)
		info = HF.Lod(home)
		T.check(info and info.Tier == "High" and #info.Targets == 6, "p6 lod near (40 studs): tier High, 6 targets (plot base + 4 stations + the bed piece)",
			info and (tostring(info.Tier) .. " " .. #info.Targets))
		local houseMesh = st.House:FindFirstChild("ML_Mesh")
		T.check(houseMesh and houseMesh:GetAttribute("ML_LodKey") == nil and not anyHidden(st.Fence) and not anyHidden(st.Bed)
			and lodAttrs(spot) == 0, "p6 lod near: every mesh on its High key, nothing hidden")

		-- Low
		look(150)
		info = HF.Lod(home)
		houseMesh = st.House:FindFirstChild("ML_Mesh")
		local houseCount = 0
		for _, c in ipairs(st.House:GetChildren()) do
			if c.Name == "ML_Mesh" then
				houseCount = houseCount + 1
			end
		end
		T.check(info and info.Tier == "Low", "p6 lod 150 studs: tier Low", info and tostring(info.Tier))
		T.check(houseMesh and houseMesh:GetAttribute("ML_LodKey") == "home_house_4_low" and houseCount == 1,
			"p6 lod Low: the house shows home_house_4_low (one ML_Mesh, rebuilt)", houseMesh and tostring(houseMesh:GetAttribute("ML_LodKey")))
		local lp = houseMesh and meshParts(st.House)[1]
		local ml = lp and lp:GetAttribute("ML_Key")
		T.check(ml == "home_house_4_low", "p6 lod Low: the low mesh's parts carry ML_Key = the low key", tostring(ml))
		T.check(not anyHidden(st.Farm) and st.Farm.ML_Mesh:GetAttribute("ML_LodKey") == nil, "p6 lod Low: the farm (no _low uploaded) keeps its High mesh, shown")
		T.check(not anyHidden(st.Garden) and st.Garden.ML_Mesh:GetAttribute("ML_LodKey") == nil, "p6 lod Low: the garden (stale _low refused) keeps its High mesh, shown")
		T.check(not anyHidden(st.Fence) and not anyHidden(st.Bed) and st.Fence:GetAttribute("ML_LodHidden") == nil and lodAttrs(spot) == 0,
			"p6 lod Low: decor shown on its High key (no _low uploaded), nothing hidden")
		T.check(not anyHidden(st.Base) and st.HouseGlow.Transparency == glowT, "p6 lod Low: the plot base and the house's kept glow stay")

		-- Far
		look(300)
		info = HF.Lod(home)
		T.check(info and info.Tier == "Far", "p6 lod 300 studs: tier Far", info and tostring(info.Tier))
		T.check(allHidden(st.Farm) and allHidden(st.Garden) and allHidden(st.Fence) and allHidden(st.Bed) and st.Fence:GetAttribute("ML_LodHidden") == true,
			"p6 lod Far: farm, garden, fence and the nested bed piece hidden")
		T.check(st.FarmGlow.Transparency == 1 and st.FarmGlow:GetAttribute("ML_LodT") ~= nil and st.GardenGlow.Transparency == 1,
			"p6 lod Far: the hidden stations' kept glow Parts are hidden too (old value in ML_LodT)")
		T.check(not anyHidden(st.House) and st.House.ML_Mesh:GetAttribute("ML_LodKey") == "home_house_4_low" and not anyHidden(st.Base)
			and st.HouseGlow.Transparency == glowT, "p6 lod Far: only the landmarks stay: the house (low) and the plot base")
		T.check(st.Farm.Wall.Transparency == 1 and st.Farm.Wall:GetAttribute("ML_LodT") == nil, "p6 lod Far: Parts Dress already hid are left alone (no ML_LodT)")

		-- no per-frame work: a still camera
		local applied0, scans0 = info.Applied, info.Scans
		calls = 0
		Mock.Advance(3)
		info = HF.Lod(home)
		T.check(calls == 0 and info.Applied == applied0 and info.Scans == scans0, "p6 lod: a still camera for 3 s = zero SetLod calls, no re-scan",
			fmt("%d calls, applied %d -> %d", calls, applied0, info.Applied))

		-- hysteresis
		calls = 0
		look(190)
		T.check(HF.Lod(home).Tier == "Far" and calls == 0, "p6 lod hysteresis: Far holds at 190 studs (leaves only inside LOD_FAR - LOD_HYST)")
		look(170)
		info = HF.Lod(home)
		T.check(info.Tier == "Low" and not anyHidden(st.Fence) and not anyHidden(st.Bed) and not anyHidden(st.Farm) and not anyHidden(st.Garden)
			and st.House.ML_Mesh:GetAttribute("ML_LodKey") == "home_house_4_low", "p6 lod hysteresis: Low at 170 studs (everything back, the house still low)")
		T.check(calls >= 6 and calls <= 6 * 2, "p6 lod: a tier change = one SetLod per target", calls .. " calls")
		look(110)
		T.check(HF.Lod(home).Tier == "High", "p6 lod hysteresis: High at 110")
		look(135)
		T.check(HF.Lod(home).Tier == "High", "p6 lod hysteresis: High holds at 135 (leaves only beyond LOD_HIGH + LOD_HYST)")
		look(145)
		T.check(HF.Lod(home).Tier == "Low", "p6 lod hysteresis: Low at 145")

		-- back near: exactly as dressed
		look(30)
		info = HF.Lod(home)
		houseMesh = st.House:FindFirstChild("ML_Mesh")
		local visibleMeshes = 0
		for _, target in ipairs({ st.Base, st.House, st.Farm, st.Fence, st.Garden, st.Bed }) do
			if not anyHidden(target) and #meshParts(target) > 0 then
				visibleMeshes = visibleMeshes + 1
			end
		end
		T.check(info.Tier == "High" and houseMesh and houseMesh:GetAttribute("ML_LodKey") == nil and visibleMeshes == 6 and lodAttrs(spot) == 0
			and st.HouseGlow.Transparency == glowT and st.FarmGlow.Transparency == glowT and st.Farm.Wall.Transparency == 1,
			"p6 lod back near: every mesh on its High key and shown, kept glow restored, Dress-hidden Parts still hidden, no ML_Lod* left",
			fmt("%d visible, %d attrs", visibleMeshes, lodAttrs(spot)))

		-- a station placed while the plot is Far is picked up at the next checks (no per-frame scan)
		look(300)
		local late = station(home, "Vault", "home_farm_40", CFrame.new(center + Vector3.new(-20, 4, 20)))
		ML.Dress(late, "home_farm_40")
		Mock.Advance(K.Check * 2 + 2.2)
		T.check(allHidden(late), "p6 lod: a station added on a Far plot gets hidden once its mesh is on (re-scan on the new tag)")

		ML.SetLod = realSetLod
		HF._SetMeshLib(nil)
		ML._Reset()
		spot:Destroy()
	end)
	T.check(ok, "client_p6lod ran to the end", tostring(err))
	HF._SetMeshLib(nil)
	if cam and savedCam then
		cam.CFrame = savedCam
	end
	world:Destroy()
	for _, b in ipairs(boxes) do
		b:Destroy()
	end

	-- the budget tool applies the same rule
	local src = readFile("tools/mesh_budget.py") or ""
	local hi, far, hy = string.match(src, "\nLOD_HIGH = (%d+)"), string.match(src, "\nLOD_FAR = (%d+)"), string.match(src, "\nLOD_HYST = (%d+)")
	T.check(tonumber(hi) == K.High and tonumber(far) == K.Far and tonumber(hy) == K.Hyst,
		"p6 lod: tools/mesh_budget.py LOD_HIGH / LOD_FAR / LOD_HYST = HomeFx K.LOD_*", fmt("%s/%s/%s vs %d/%d/%d", tostring(hi), tostring(far), tostring(hy), K.High, K.Far, K.Hyst))
end)

return S
