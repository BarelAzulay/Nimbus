-- smoke_bug20_farm.lua: bug #20 "the farm design bugs" (art wave; the player's pick B, Sky-Sailor's Allotment).
-- Loaded by tools/smoke.py in both worlds (ARGS.context picks the half).
--   bug20farm_server  (server)
--     * the Part build at every level 1-40: <= 150 parts; the deck, three lifeboat Hulls, the Cabin, the upturned
--       HullRoof + Keel, the Propeller + VanePost, the Bell, two glass Portholes, the Anchor + RopeCoil, the
--       crow's-nest Tub; oars, rope, mast, yard and rigging only from 23 (the gold vines); the fallback bushes are wider
--       than tall and sit on their soil (never a floating cube)
--     * the Propeller is the farm's element key (home_farm_propeller): kept visible over the station mesh, own manifest
--     * every farm key (home_farm_1..40 + _low): two MeshParts (Fixed + the Glass portholes at the cabin end, so the
--       fit can see which way the farm faces), <= 8000 triangles, LayoutSig = the live Part build
--     * the facing is certain now: a 180-degree import of home_farm_18 / _low fits back as ML_Yaw 180 (one part could
--       not tell; the "two farms" lead), a plain one as 0
--   client_bug20farm  (client)
--     * a dressed farm keeps its Part build hidden: decor that comes back later (GraphicsQuality's NC_Detail holder)
--       and parts restored by hand are hidden again (DescendantAdded, MeshLibrary.Rehide after every LOD rebuild);
--       exactly one ML_Mesh through High / Low / Hide / High; a kept part that joins while the LOD hides the farm is
--       hidden with it and comes back with it
--     * HomeFx turns the propeller weathervane about its own axis (the Part and its ML_Mesh together), in place
--   fix round (review): a placed station carries ML_At (its slot CFrame) and the server Bell the NC_FarmBell tag;
--     client: a farm dressed before its Cabin (PrimaryPart) replicated lands on the slot (the old pivot * ML_Offset
--     path is shown drifting), the late Cabin is hidden, the LOD rebuild uses ML_At too; the dress watcher is tracked
--     (re-dress / _Reset); a late Propeller still gets its weathervane
local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"
local abs, max, min = math.abs, math.max, math.min
local fmt = string.format

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function requireAt(key)
		local inst = K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	local function partsOf(m)
		local out = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				out[#out + 1] = d
			end
		end
		return out
	end

	local function count(list, name)
		local n = 0
		for _, p in ipairs(list) do
			if p.Name == name then
				n = n + 1
			end
		end
		return n
	end

	S.bug20farm_server = guarded("bug20farm_server", function()
		local HB = requireAt("server/Services/HomeBuilder")
		local ML = requireAt("shared/MeshLibrary")
		if not T.check(HB and type(HB.BuildStationModel) == "function" and type(HB._Mesh) == "table" and ML and type(ML._Fit) == "function",
			"bug20 farm: HomeBuilder.BuildStationModel / _Mesh and MeshLibrary._Fit load") then
			return
		end
		local Mesh = HB._Mesh
		local TOPS = { 0.75, 1.15, 1.55 }

		-- 1. the Part build at every level
		local build = T.tally("bug20 farm: the allotment's Part build at every level (<= 150 parts; deck, 3 hulls, cabin, boat roof + keel, propeller, bell, 2 glass portholes, anchor + coil, tub; the mast and oars from 23)")
		local seated = T.tally("bug20 farm: every fallback bush is wider than tall and sits on its soil (no floating cube)")
		local bells = T.tally("bug20 farm: the ship's Bell carries the CollectionService tag NC_FarmBell at every level (the audio branch's hook, no sound here)")
		local CS = game:GetService("CollectionService")
		for level = 1, 40 do
			local m = HB.BuildStationModel("Press1", level)
			local list = m and partsOf(m) or {}
			local glass = 0
			for _, p in ipairs(list) do
				if p.Name == "Porthole" and p.Material == Enum.Material.Glass and p.Transparency > 0.05 then
					glass = glass + 1
				end
			end
			local trellis = level >= 23
			local bellTagged = 0
			for _, p in ipairs(list) do
				if p.Name == "Bell" and CS:HasTag(p, "NC_FarmBell") then
					bellTagged = bellTagged + 1
				end
			end
			bells:case(bellTagged == 1, fmt("level %d: %d tagged bells", level, bellTagged))
			local ok = #list <= 150 and count(list, "ShipDeck") == 1 and count(list, "Hull") == 3 and count(list, "Cabin") == 1
				and count(list, "HullRoof") == 2 and count(list, "Keel") == 1 and count(list, "Propeller") == 1 and count(list, "VanePost") == 1
				and count(list, "Bell") == 1 and glass == 2 and count(list, "Anchor") == 1 and count(list, "RopeCoil") == 1 and count(list, "Tub") == 1
				and (count(list, "Oar") == (trellis and 6 or 0)) and (count(list, "Mast") == (trellis and 1 or 0))
				and (count(list, "Rigging") == (trellis and 2 or 0)) and count(list, "Barn") == 0
			build:case(ok, fmt("level %d: %d parts, %d oars, %d glass", level, #list, count(list, "Oar"), glass))
			for _, p in ipairs(list) do
				if p.Name == "Bush" then
					local bottom = p.Position.Y - p.Size.Y / 2
					local onSoil = false
					for _, top in ipairs(TOPS) do
						if bottom >= top - 0.2 and bottom <= top + 0.02 then
							onSoil = true
						end
					end
					seated:case(p.Size.X > p.Size.Y * 1.15 and onSoil, fmt("level %d bush at x %.2f: %.2f x %.2f, bottom %.2f", level, p.Position.X, p.Size.X, p.Size.Y, bottom))
				end
			end
			if m then
				m:Destroy()
			end
		end
		build:report()
		seated:report()
		bells:report()

		-- 2. the propeller element
		local def = nil
		local TC = requireAt("shared/TycoonCatalog")
		def = TC and TC.Get and TC.Get("Press1")
		local elements = Mesh.elementsOf(def)
		local m40 = HB.BuildStationModel("Press1", 40)
		local _, keepSet = Mesh.keepOf(m40, elements)
		local pm = ML.Manifest("home_farm_propeller")
		local pparts = pm and (pm.Parts or pm.parts) or {}
		T.check(elements.Propeller == "home_farm_propeller" and keepSet.Propeller == true and keepSet.Lantern == true and #pparts == 1
			and (pparts[1].name or pparts[1].Name) == "Propeller",
			"bug20 farm: the Propeller is its own element key (home_farm_propeller, one part 'Propeller'), kept over the station mesh with the Lantern")
		m40:Destroy()

		-- 2b. (fix round) a placed station is tagged with its world spot (ML_At = the slot CFrame), not only pivot *
		-- ML_Offset: a client dressing before the PrimaryPart (the Cabin, built last) replicates reads another pivot.
		-- The Status stub stands in for an uploaded id (the shipped MeshIds hold no home_farm id until the re-upload).
		local saved = Mesh.Lib
		local okPin, errPin = pcall(function()
			Mesh.Lib = setmetatable({ Status = function()
				return "ready"
			end }, { __index = ML })
			local tplModel = HB.BuildStationModel("Press1", 18)
			local tpl = { Model = tplModel }
			local slot = CFrame.new(-7300, 230.25, 7311.5) * CFrame.Angles(0, math.rad(90), 0)
			local placed = tplModel:Clone()
			placed:PivotTo(slot * tplModel:GetPivot()) -- what cloneAt does: every part moved by the slot CFrame
			local tags = Mesh.station(placed, def, 18, tpl, slot, true)
			local at = placed:GetAttribute("ML_At")
			local parsed = nil
			if type(at) == "string" then
				local n = {}
				for tok in string.gmatch(at, "[^,]+") do
					n[#n + 1] = tonumber(tok)
				end
				parsed = #n == 12 and CFrame.new(table.unpack(n)) or nil
			end
			local pinOk = parsed ~= nil and (parsed.Position - slot.Position).Magnitude < 1e-3 and parsed.LookVector:Dot(slot.LookVector) > 0.99999
				and placed:GetAttribute("ML_DressKey") == "home_farm_18" and tags >= 1
			local viaDressAt = pinOk and ML._DressAt and ML._DressAt(placed)
			T.check(pinOk and viaDressAt and (viaDressAt.Position - slot.Position).Magnitude < 1e-3,
				"bug20 farm: a placed farm is tagged with ML_At = its slot CFrame (the mesh spot no longer depends on which part replicated first)",
				fmt("ML_At %s, key %s, tags %d", tostring(at), tostring(placed:GetAttribute("ML_DressKey")), tags))
			local loose = tplModel:Clone()
			Mesh.station(loose, def, 18, tpl, CFrame.new())
			T.check(loose:GetAttribute("ML_At") == nil and loose:GetAttribute("ML_DressKey") == "home_farm_18",
				"bug20 farm: a station model that may still move (BuildStationModel: renders, previews) gets no ML_At (pivot * ML_Offset as before)")
			placed:Destroy()
			loose:Destroy()
			tplModel:Destroy()
		end)
		Mesh.Lib = saved
		T.check(okPin, "bug20 farm: the pinned-station scenario ran", tostring(errPin))

		-- 3. every farm manifest: Fixed + Glass at the cabin end, budget, LayoutSig = the live build
		local mans = T.tally("bug20 farm: every farm key (1-40 + _low) is two MeshParts (Fixed + Glass at the cabin end, the facing marker), <= 8000 triangles, baked from the live Part build (LayoutSig)")
		for level = 1, 40 do
			local m = HB.BuildStationModel("Press1", level)
			local _, kset = Mesh.keepOf(m, elements)
			local n, a, b = Mesh.signature(m, CFrame.new(), kset)
			m:Destroy()
			for _, key in ipairs({ "home_farm_" .. level, "home_farm_" .. level .. "_low" }) do
				local man = ML.Manifest(key)
				local parts = man and (man.Parts or man.parts) or {}
				local names, glassX, tris = {}, nil, 0
				for _, p in ipairs(parts) do
					local nm = p.name or p.Name
					names[#names + 1] = nm
					if nm == "Glass" then
						local c = p.center or p.Center
						glassX = c and c[1]
					end
				end
				tris = man and man.Raw and tonumber(man.Raw.Tris or man.Raw.tris) or 0
				table.sort(names)
				local ok = man ~= nil and #parts == 2 and names[1] == "Fixed" and names[2] == "Glass" and glassX ~= nil and glassX < -12
					and tris > 0 and tris <= 8000 and Mesh.sigOk(ML, key, n, a, b)
				mans:case(ok, fmt("%s: %s, glass x %s, %d tris", key, table.concat(names, "+"), tostring(glassX), tris))
			end
		end
		mans:report()

		-- 4. the fit can see a 180-degree turn now (a baked yaw: identity part rotation, the centres turned)
		local function fakeImport(key, yaw)
			local man = ML.Manifest(key)
			local wrapper = Instance.new("Model")
			local inner = Instance.new("Model")
			inner.Name = "NC " .. key
			inner.Parent = wrapper
			local R = CFrame.Angles(0, math.rad(yaw), 0)
			for _, p in ipairs(man.Parts or man.parts) do
				local c = p.center or p.Center
				local s = p.size or p.Size
				local part = Instance.new("MeshPart")
				part.Name = p.name or p.Name
				local w = R:VectorToWorldSpace(Vector3.new(s[1], s[2], s[3]))
				part.Size = Vector3.new(abs(w.X), abs(w.Y), abs(w.Z))
				part.CFrame = CFrame.new(R:VectorToWorldSpace(Vector3.new(c[1], c[2], c[3])))
				part.Parent = inner
			end
			return wrapper
		end
		local fits = T.tally("bug20 farm: the fit sees which way the farm faces (a 180-degree import fits back as ML_Yaw 180, a plain one as 0)")
		for _, key in ipairs({ "home_farm_18", "home_farm_18_low", "home_farm_40" }) do
			for _, yaw in ipairs({ 0, 180 }) do
				local tpl, why = ML._Fit(key, fakeImport(key, yaw))
				fits:case(tpl ~= nil and tpl:GetAttribute("ML_Yaw") == yaw, fmt("%s imported at %d: yaw %s %s", key, yaw, tostring(tpl and tpl:GetAttribute("ML_Yaw")), tostring(why or "")))
				if tpl then
					tpl:Destroy()
				end
			end
		end
		fits:report()

		local ids = requireAt("shared/MeshIds") or {}
		local stale = 0
		for k in pairs(ids) do
			if string.sub(k, 1, 10) == "home_farm_" then
				stale = stale + 1
			end
		end
		T.info(fmt("bug20 farm: %d home_farm ids in MeshIds (0 until the re-upload: the old ids held the old design, the Part build shows meanwhile)", stale))
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local RS = game:GetService("ReplicatedStorage")

	local function sharedInst(path)
		local ok, inst = pcall(Mock.GetPath, ROOTS.shared .. "/" .. path)
		return ok and inst or nil
	end

	-- a private MeshLibrary next to its own MeshIds + manifests (smoke_p6_lod's pattern)
	local function newLib(ids, sources)
		local box = Instance.new("Folder")
		box.Name = "Bug20FarmLib"
		local lib = sharedInst("MeshLibrary"):Clone()
		lib.Parent = box
		local idsMod = Instance.new("ModuleScript")
		idsMod.Name = "MeshIds"
		local lines = { "return {" }
		local keys = {}
		for k in pairs(ids) do
			keys[#keys + 1] = k
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			lines[#lines + 1] = fmt("\t[%q] = %d,", k, ids[k])
		end
		lines[#lines + 1] = "}"
		idsMod.Source = table.concat(lines, "\n")
		idsMod.Parent = box
		local mans = Instance.new("Folder")
		mans.Name = "MeshManifests"
		mans.Parent = box
		for k, src in pairs(sources) do
			local m = Instance.new("ModuleScript")
			m.Name = k
			m.Source = src
			m.Parent = mans
		end
		local root = Instance.new("Folder")
		root.Name = "MeshLibrary"
		root.Parent = box
		box.Parent = RS
		local ML = require(lib)
		ML._Configure({ Root = root })
		return ML, root, box
	end

	local function installTemplate(ML, root, key)
		local man = ML.Manifest(key)
		local wrapper = Instance.new("Model")
		local inner = Instance.new("Model")
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
		p.Size = size or Vector3.new(2, 2, 2)
		p.Transparency = transparency or 0
		if material then
			p.Material = material
		end
		p.Parent = parent
		return p
	end

	local function visibleBuild(target)
		local out = {}
		for _, d in ipairs(target:GetDescendants()) do
			if d:IsA("BasePart") and not d:FindFirstAncestor("ML_Mesh") and d.Transparency < 0.999 and d.Name ~= "Lantern" then
				out[#out + 1] = d.Name
			end
		end
		table.sort(out)
		return out
	end

	local function meshCount(target)
		local n = 0
		for _, c in ipairs(target:GetChildren()) do
			if c.Name == "ML_Mesh" then
				n = n + 1
			end
		end
		return n
	end

	S.client_bug20farm = guarded("client_bug20farm", function()
		local world = Instance.new("Folder")
		world.Name = "Bug20FarmWorld"
		world.Parent = workspace
		local box = nil
		local ok, err = pcall(function()
			local sources = {}
			for _, key in ipairs({ "home_farm_18", "home_farm_18_low" }) do
				local inst = sharedInst("MeshManifests/" .. key)
				sources[key] = inst and inst.Source
			end
			if not T.check(sources.home_farm_18 and sources.home_farm_18_low, "bug20 client: the farm manifests home_farm_18 / _low exist") then
				return
			end
			local ML, root
			ML, root, box = newLib({ home_farm_18 = 9801, home_farm_18_low = 9802 }, sources)
			installTemplate(ML, root, "home_farm_18")
			installTemplate(ML, root, "home_farm_18_low")
			ML.Start()
			Mock.Advance(1)
			T.check(ML.IsReady({ "home_farm_18", "home_farm_18_low" }) and ML.LowKey("home_farm_18") == "home_farm_18_low",
				"bug20 client: both farm keys ready here and the _low is a valid plot LOD")

			-- a farm the way HomeBuilder tags it: Part build + kept Lantern + an NC_Detail crate group
			local cf = CFrame.new(-7400, 230, 7400) * CFrame.Angles(0, math.rad(-90), 0)
			local farm = Instance.new("Model")
			farm.Name = "Station_Press1"
			local cabin = part(farm, "Cabin", cf * CFrame.new(-15.6, 1.9, 0.6), Vector3.new(4.8, 3.2, 5.4))
			part(farm, "Hull", cf * CFrame.new(1.2, 0.5, -2.25), Vector3.new(24.6, 0.4, 2.15))
			part(farm, "Bush", cf * CFrame.new(-9, 1.4, -2.25), Vector3.new(1.9, 1.5, 1.9))
			part(farm, "Lantern", cf * CFrame.new(-17.3, 2.85, -2.45), Vector3.new(0.45, 0.56, 0.45), 0, Enum.Material.Neon)
			local crates = Instance.new("Model")
			crates.Name = "Crates"
			crates.Parent = farm
			part(crates, "Crate", cf * CFrame.new(-12.25, 0.85, -0.9), Vector3.new(1.15, 1.1, 1.15))
			farm.PrimaryPart = cabin
			farm.WorldPivot = cf
			farm:SetAttribute("ML_DressKey", "home_farm_18")
			farm:SetAttribute("ML_Keep", "Lantern,SignBoard")
			farm.Parent = world
			ML.Dress(farm, "home_farm_18")
			Mock.Advance(0.3)
			local mesh = farm:FindFirstChild("ML_Mesh")
			T.check(mesh ~= nil and meshCount(farm) == 1 and #visibleBuild(farm) == 0 and farm.Lantern.Transparency == 0,
				"bug20 client: the dressed farm shows its mesh once, the Part build hidden, the Lantern kept", table.concat(visibleBuild(farm), ","))
			local fixed = mesh and mesh:FindFirstChild("Fixed")
			local glass = mesh and mesh:FindFirstChild("Glass")
			if fixed and glass then
				local gl = cf:PointToObjectSpace(glass.Position)
				T.check(gl.X < -12 and abs(gl.Z) < 3, "bug20 client: the glass portholes sit at the cabin end of the dressed farm (local x < -12)", fmt("%.2f, %.2f", gl.X, gl.Z))
			else
				T.check(false, "bug20 client: the dressed mesh has its Fixed + Glass parts")
			end

			-- GraphicsQuality's Low holds NC_Detail decor in a local folder; when High brings it back it must stay hidden
			local holder = Instance.new("Folder")
			holder.Parent = RS
			crates.Parent = holder
			crates.Crate.Transparency = 0 -- what a decor model looks like after a trip (never hidden there)
			crates.Parent = farm
			T.check(crates.Crate.Transparency >= 0.999, "bug20 client: decor that comes back to a dressed farm (GraphicsQuality High) is hidden again, not drawn over the mesh",
				tostring(crates.Crate.Transparency))
			holder:Destroy()
			local late = part(farm, "Soil", cf * CFrame.new(1.2, 0.6, 0), Vector3.new(24, 0.3, 1.6))
			T.check(late.Transparency >= 0.999, "bug20 client: a Part build part added after the dress is hidden too")

			-- the plot LOD: High -> Low (rebuilt from the _low key) -> Hide -> High: one ML_Mesh, the build stays hidden
			cabin.Transparency = 0 -- something restored a part by hand: the next rebuild hides it again (Rehide)
			T.check(ML.SetLod(farm, "Low") == true and meshCount(farm) == 1 and farm.ML_Mesh:GetAttribute("ML_LodKey") == "home_farm_18_low"
				and #visibleBuild(farm) == 0, "bug20 client: LOD Low rebuilds one ML_Mesh from home_farm_18_low and re-hides the Part build",
				table.concat(visibleBuild(farm), ","))
			T.check(ML.SetLod(farm, "Hide") == true and farm.Lantern.Transparency >= 0.999, "bug20 client: LOD Hide hides the farm with its kept Lantern")
			local lamp2 = part(farm, "Lantern", cf * CFrame.new(-14, 2.85, -2.45), Vector3.new(0.45, 0.56, 0.45), 0, Enum.Material.Neon)
			T.check(lamp2.Transparency >= 0.999 and lamp2:GetAttribute("ML_LodT") == 0, "bug20 client: a kept part that joins while the LOD hides the farm is hidden with it")
			T.check(ML.SetLod(farm, "High") == true and meshCount(farm) == 1 and farm.ML_Mesh:GetAttribute("ML_LodKey") == nil
				and farm.Lantern.Transparency == 0 and lamp2.Transparency == 0 and #visibleBuild(farm) == 0,
				"bug20 client: back to High: one ML_Mesh on home_farm_18, both lanterns back, the Part build still hidden", table.concat(visibleBuild(farm), ","))
			T.check(ML.Rehide(Instance.new("Model")) == false, "bug20 client: MeshLibrary.Rehide on a target it never dressed does nothing")

			-- (fix round) the farm dressed WHILE it replicates: every part is here but the Cabin, its PrimaryPart (the
			-- biggest part, built last), so the client's GetPivot() is cloneAt's WorldPivot (the slot), not the Cabin
			-- pivot the server computed ML_Offset from. ML_At pins the spot; the old path is shown off for contrast.
			ML._Configure({ DressTag = "Bug20FarmDress" }) -- Tag writes the attributes; no game listener reacts to this tag
			local slot = CFrame.new(-7300, 230.25, 7311.5) * CFrame.Angles(0, math.rad(90), 0)
			local cabinCF = slot * CFrame.new(-15.6, 1.9, 0.6)
			local function lateFarm(pinned)
				local f = Instance.new("Model")
				f.Name = "Station_Press1"
				part(f, "Hull", slot * CFrame.new(1.2, 0.5, -2.25), Vector3.new(24.6, 0.4, 2.15))
				part(f, "Bush", slot * CFrame.new(-9, 1.4, -2.25), Vector3.new(1.9, 1.5, 1.9))
				part(f, "Lantern", slot * CFrame.new(-17.3, 2.85, -2.45), Vector3.new(0.45, 0.56, 0.45), 0, Enum.Material.Neon)
				f.WorldPivot = slot -- cloneAt's WorldPivot replicates; the PrimaryPart reference resolves only with the Cabin
				ML.Tag(f, "home_farm_18", { Offset = cabinCF:Inverse() * slot, At = pinned and slot or nil }, { "Lantern", "SignBoard" })
				f.Parent = world
				ML.Dress(f, "home_farm_18")
				Mock.Advance(0.3)
				return f
			end
			local function near(a, b)
				return a and b and (a.Position - b.Position).Magnitude < 1e-3 and a.LookVector:Dot(b.LookVector) > 0.99999
			end
			local old = lateFarm(false)
			local oldMesh = old:FindFirstChild("ML_Mesh")
			local drift = oldMesh and (oldMesh:GetPivot().Position - slot.Position).Magnitude or 0
			T.check(drift > 5, "bug20 client: (the bug, reproduced) without ML_At a farm dressed before its Cabin arrives lands its mesh off the slot",
				fmt("%.1f studs off", drift))
			old:Destroy()
			local pin = lateFarm(true)
			local pm = pin:FindFirstChild("ML_Mesh")
			T.check(pm ~= nil and near(pm:GetPivot(), slot) and type(pin:GetAttribute("ML_At")) == "string",
				"bug20 client: with ML_At the farm dressed before its Cabin replicated puts its mesh exactly on the slot",
				pm and fmt("%.3f studs off", (pm:GetPivot().Position - slot.Position).Magnitude) or "no mesh")
			local lateCabin = part(pin, "Cabin", cabinCF, Vector3.new(4.8, 3.2, 5.4))
			pin.PrimaryPart = lateCabin
			T.check(lateCabin.Transparency >= 0.999 and meshCount(pin) == 1 and near(pin.ML_Mesh:GetPivot(), slot) and #visibleBuild(pin) == 0,
				"bug20 client: the late Cabin (the PrimaryPart) is hidden on arrival, one mesh, still on the slot", table.concat(visibleBuild(pin), ","))
			T.check(ML.SetLod(pin, "Low") == true and meshCount(pin) == 1 and near(pin.ML_Mesh:GetPivot(), slot) and lateCabin.Transparency >= 0.999,
				"bug20 client: the LOD rebuild (Low) also places the mesh on ML_At, the Cabin stays hidden")
			ML.SetLod(pin, "High")

			-- the dress watcher is tracked: a re-dress replaces it (never two handlers), _Reset releases it
			pin.ML_Mesh:Destroy()
			ML.Dress(pin, "home_farm_18")
			Mock.Advance(0.3)
			local probe = part(pin, "Soil", slot * CFrame.new(1.2, 0.6, 0), Vector3.new(24, 0.3, 1.6))
			T.check(meshCount(pin) == 1 and probe.Transparency >= 0.999, "bug20 client: a re-dressed farm has one mesh and still hides late parts")
			ML._Reset() -- the mesh stays; only a still-connected watcher could hide the next part
			local after = part(pin, "Soil", slot * CFrame.new(1.2, 0.7, 0), Vector3.new(24, 0.3, 1.6))
			T.check(after.Transparency == 0, "bug20 client: _Reset disconnects the dress watcher (dressSets[target].Conn), nothing stays connected", tostring(after.Transparency))
			pin:Destroy()
			ML._Reset()
		end)
		T.check(ok, "bug20 client: the dress scenario ran", tostring(err))
		if box then
			box:Destroy()
		end

		-- the propeller weathervane (HomeFx)
		local HF = KC and KC.M and KC.M.HomeFx
		if not HF then
			pcall(function()
				HF = require(Mock.GetPath(ROOTS.client .. "/Controllers/HomeFx"))
			end)
		end
		if T.check(type(HF) == "table" and type(HF._Vane) == "table" and type(HF._Vane.Find) == "function" and type(HF._Vane.Step) == "function",
			"bug20 client: HomeFx exposes the weathervane step (TESTS ONLY hook _Vane)") then
			local K = HF._Vane.K
			local st = Instance.new("Model")
			st.Name = "Station_Press1"
			st.Parent = world
			local base = CFrame.new(-7400, 236, 7400) * CFrame.Angles(0, math.rad(-90), 0)
			local prop = part(st, "Propeller", base, Vector3.new(1.9, 0.3, 0.15))
			local meshM = Instance.new("Model")
			meshM.Name = "ML_Mesh"
			local mp = part(meshM, "Propeller", base * CFrame.new(0.5, 0, 0), Vector3.new(0.7, 0.26, 0.1))
			meshM.WorldPivot = base
			meshM.Parent = prop
			local rec = { Model = st }
			HF._Vane.Find(rec)
			local okFind = rec.Vane ~= nil and rec.Vane.Part == prop
			-- (fix round) a Propeller that replicates after its station was registered still gets its vane record
			local st2 = Instance.new("Model")
			st2.Name = "Station_Press1"
			st2.Parent = world
			local farmRec = { Model = st2 }
			HF._Vane.Find(farmRec)
			local before = farmRec.Vane
			local late = part(st2, "Propeller", base * CFrame.new(0, 0, 4), Vector3.new(1.9, 0.3, 0.15))
			local lateOk = type(HF._Vane.Late) == "function" and HF._Vane.Late({ Farm = farmRec }, late) == true
			T.check(before == nil and lateOk and farmRec.Vane and farmRec.Vane.Part == late
				and HF._Vane.Late({ Farm = farmRec }, late) == false,
				"bug20 client: a late Propeller (arrives after its Station_ model) gets the weathervane record, once")
			st2:Destroy()
			local dt, steps = 1 / 30, 30
			for _ = 1, steps do
				HF._Vane.Step(rec, dt)
			end
			local rel = base:ToObjectSpace(prop.CFrame)
			local _, _, rz = rel:ToEulerAnglesXYZ()
			local turned = abs(rz) > 0.3 and abs(rz) < K.VANE_SPEED * (1 + K.VANE_GUST) + 0.05
			local axisOk = (prop.Position - base.Position).Magnitude < 1e-3 and abs(rel.LookVector:Dot(Vector3.new(0, 0, -1)) - 1) < 1e-3
			local follow = (prop.CFrame:ToObjectSpace(mp.CFrame).Position - Vector3.new(0.5, 0, 0)).Magnitude < 1e-3
			T.check(okFind and turned and axisOk and follow,
				"bug20 client: the weathervane turns slowly about its own axis in place, its mesh blade with it",
				fmt("find %s, angle %.2f rad in 1 s, in place %s, mesh follows %s", tostring(okFind), rz, tostring(axisOk), tostring(follow)))
		end
		world:Destroy()
		if KC and KC.flushErrors then
			KC.flushErrors("bug20farm")
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
