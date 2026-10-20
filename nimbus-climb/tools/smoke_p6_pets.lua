-- smoke_p6_pets.lua: the Phase 6 pet MESH path (ARCHITECTURE_V3.md 6.3 "runtime-pets"; docs/phase6/recipe.md 4.8 "Pet
-- path" / 4.9; owner: runtime-pets, wave 2). Loaded by tools/smoke.py in BOTH worlds.
--
-- Two modes:
--   default (MeshIds empty)   every pet scenario runs today's Part build; p6pets_* below install their own fixture
--                             templates for a handful of keys, test, and take them away again (so they prove the mesh
--                             path in every run and leave nothing behind).
--   fixture mesh mode         `python3 tools/smoke.py --mesh` (env NC_MESH_FIXTURES=1): p6pets_mesh_on (server, right
--                             after load_modules) and client_p6pets_mesh_on (client, right after client_load) install
--                             fixture templates for EVERY pet-class key (pet_ / wing_ / acc_ / hyb_ / evo1_ / evo2_ /
--                             evowing_ / star_gold) built from the committed src/shared/MeshManifests through a fake
--                             MeshIds + Mock.AssetLoader (server: the real background loader + fit; client: the real
--                             preload), so the existing pet scenarios (petbuilder, evolved, p3evo_pets, p6evofx_*,
--                             p5looks, p5follow, p5wild, p5models ...) run on mesh pets. Asserts of voxel internals in
--                             those scenarios (part caps, shade counts) are expected to differ there (recipe 4.9).
--
--   p6pets_mesh_on     (server) fixture mesh mode only (no-op otherwise)
--   p6pets_default     (server) empty MeshIds: Active() false, Build = the Part build (no ML_Mesh, no MeshPart), the
--                      MeshKeys of dog / cat / corgi / dragon / crown / hybrid / Golden / evolved 1 + 2 / Low,
--                      NeedsMeshRebuild false, MeshVersion a number
--   p6pets_server      (server) fixture templates through the real loader (fake ids + Mock.AssetLoader built from the
--                      committed manifests: dog, cat, corgi, dragon, feather / fairy / bat wings, crown, horns, hybrid
--                      cat feature, Golden star, evolved forms): names (recipe 4.3), invisible Body root, PB_* attributes
--                      equal to the Part build's (PetId, PB_Seed, PB_Detail, PB_Evolved, PB_Scale with grow), PB_Rig in
--                      instantiate order, MeshParts only, Animate flaps (no NaN, no new instances) and its Clone too,
--                      PetFx on evolved forms (and not in viewports), Wild, Golden (Metal accents + GoldSpark stars),
--                      Rainbow (PB_Hue), hybrids (Hy* colours, the feature's tail replaces the body's), Low keys,
--                      a partially ready set falls back WHOLE, NeedsMeshRebuild + MeshVersion, the size of the mesh pet
--                      close to the Part pet, battle-unit scale, opts.Parts forces Parts; then everything removed again
--   client_p6pets_mesh_on (client) fixture mesh mode only
--   client_p6pets      (client) on a preloaded device: a follower built from Parts is rebuilt as a mesh pet once its
--                      keys are ready (PetController polls MeshVersion), PetController follows it (welded root),
--                      CloudUI.PetViewport builds with Viewport = true (no PetFx emitters in viewports) and swaps
--                      its Part model for the mesh one, a device preload failure keeps Parts; then everything removed
-- Plain Lua 5.1; deterministic (sorted keys, fixed defs, no RNG).

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local RS = game:GetService("ReplicatedStorage")
local fmt = string.format

local MESH_MODE = (os and os.getenv and os.getenv("NC_MESH_FIXTURES") == "1") or false
local PET_PREFIX = { "pet_", "wing_", "acc_", "hyb_", "evo1_", "evo2_", "evowing_" }

local function sharedModule(name)
	return Mock.GetPath(ROOTS.shared .. "/" .. name)
end

local function lib()
	return require(sharedModule("MeshLibrary"))
end

local function PB()
	return require(sharedModule("PetBuilder"))
end

local function catalog(id)
	local Cat = require(sharedModule("PetCatalog"))
	return Cat.Get(id)
end

local function copyDef(def, look)
	local out = {}
	for k, v in pairs(def) do
		out[k] = v
	end
	out.Look = {}
	for k, v in pairs(def.Look or {}) do
		out.Look[k] = v
	end
	for k, v in pairs(look or {}) do
		out.Look[k] = v
	end
	return out
end

local manifestCache = {}
local function manifest(key)
	if manifestCache[key] == nil then
		local folder = sharedModule("MeshManifests")
		local mod = folder and folder:FindFirstChild(key)
		local ok, t = false, nil
		if mod then
			ok, t = pcall(require, mod)
		end
		manifestCache[key] = (ok and type(t) == "table") and t or false
	end
	return manifestCache[key] or nil
end

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

-- What LoadAsset returns for a key: a wrapper Model holding one MeshPart per manifest part, imported with a 180-degree
-- yaw and an offset (the loader's fit puts it back), plus a PackageLink to strip.
local function fakeAsset(key)
	local man = manifest(key)
	local wrapper = Instance.new("Model")
	wrapper.Name = "LoadAssetWrapper"
	local inner = Instance.new("Model")
	inner.Name = "NC " .. key
	inner.Parent = wrapper
	local base = CFrame.new(2, 1, -3) * CFrame.Angles(0, math.pi, 0)
	for _, p in ipairs(man.Parts) do
		local part = Instance.new("MeshPart")
		part.Name = p.Name
		part.Size = v3(p.Size)
		part.CFrame = base * CFrame.new(v3(p.Center))
		part.Anchored = false
		part.Parent = inner
	end
	local link = Mock.MakeInstance("PackageLink")
	link.Parent = inner
	return wrapper
end

-- every pet-class key that has a committed manifest (sorted)
local function petKeys()
	local out = {}
	local folder = sharedModule("MeshManifests")
	for _, m in ipairs(folder and folder:GetChildren() or {}) do
		local name = m.Name
		local hit = (name == "star_gold")
		for _, p in ipairs(PET_PREFIX) do
			if string.sub(name, 1, #p) == p then
				hit = true
			end
		end
		if hit then
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return out
end

-- Installs fixture templates for `keys` into the REAL shared MeshLibrary (the one PetBuilder uses):
-- server = fake MeshIds + Mock.AssetLoader + the real background loader and fit; client = _Fit'ted templates under the
-- root + the real client Start (PreloadAsync -> ready on this device). Returns the root and the number of ready keys.
local installed = nil
local function install(keys)
	local ML = lib()
	ML._Reset()
	PB().ClearCache()
	local root = Instance.new("Folder")
	root.Name = "P6PetsMeshLibrary"
	root.Parent = RS
	local ids, byId = {}, {}
	for i, k in ipairs(keys) do
		ids[k] = 7100000 + i
		byId[7100000 + i] = k
	end
	local saved = Mock.AssetLoader
	ML._Configure({ Root = root, Ids = ids, RetryDelays = { 0.05 } })
	if IS_SERVER then
		Mock.AssetLoader = function(id)
			local key = byId[id]
			if not key or not manifest(key) then
				error("does not exist", 0)
			end
			return fakeAsset(key)
		end
	else
		for _, k in ipairs(keys) do
			local tpl = ML._Fit(k, fakeAsset(k))
			if tpl then
				tpl:SetAttribute("ML_Status", "ready")
				tpl.Parent = root
			end
		end
	end
	ML.Start()
	local ready = 0
	for _ = 1, 60 do
		Mock.Advance(0.5)
		ready = 0
		for _, k in ipairs(keys) do
			if ML.IsReady(k) then
				ready = ready + 1
			end
		end
		if ready == #keys then
			break
		end
	end
	installed = { Root = root, Saved = saved, Keys = keys }
	return root, ready
end

local function uninstall()
	local ML = lib()
	ML._Reset()
	if installed then
		Mock.AssetLoader = installed.Saved
		pcall(function()
			installed.Root:Destroy()
		end)
		installed = nil
	end
	PB().ClearCache()
end

-- [fix-runtime W2.5] like install(), but returns right after Start: the keys are still LOADING (what a server sees
-- while its builders run at boot). uninstall() takes them away again.
local function installLate(keys)
	local ML = lib()
	ML._Reset()
	PB().ClearCache()
	local root = Instance.new("Folder")
	root.Name = "P6PetsMeshLibrary"
	root.Parent = RS
	local ids, byId = {}, {}
	for i, k in ipairs(keys) do
		ids[k] = 7300000 + i
		byId[7300000 + i] = k
	end
	local saved = Mock.AssetLoader
	ML._Configure({ Root = root, Ids = ids, RetryDelays = { 0.05 } })
	Mock.AssetLoader = function(id)
		task.wait(0.3) -- LoadAsset yields: the keys stay 'loading' while the builders run
		local key = byId[id]
		if not key or not manifest(key) then
			error("does not exist", 0)
		end
		return fakeAsset(key)
	end
	ML.Start()
	installed = { Root = root, Saved = saved, Keys = keys }
	return root
end

local function advanceUntilReady(keys)
	local ML = lib()
	for _ = 1, 80 do
		if ML.IsReady(keys) then
			break
		end
		Mock.Advance(0.5)
	end
	Mock.Advance(0.1)
	return ML.IsReady(keys)
end

-- a scenario's own fixture set; in fixture mesh mode the global set stays (it already holds every pet key)
local function withFixtures(keys, fn)
	if MESH_MODE then
		-- [fix-meshlib W3b] order-independent: a scenario that ran before may have _Reset the shared MeshLibrary without
		-- putting the --mesh set back (seen: client_p6gates); reinstall it when these keys are not ready any more
		if not lib().IsReady(keys) then
			install(petKeys())
		end
		fn()
		return
	end
	install(keys)
	local ok, err = pcall(fn)
	uninstall()
	if not ok then
		error(err, 0)
	end
end

local function flushWarn(ctx)
	for i = 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and string.find(o.text, "[MeshLibrary]", 1, true) then
			o.kind = "print"
		end
	end
	local K = IS_SERVER and _G.K or _G.KC
	if K and K.flushWarnings then
		K.flushWarnings(ctx)
	end
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function countParts(model)
	local mesh, parts, other = 0, 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			mesh = mesh + 1
		elseif d:IsA("BasePart") then
			if d.Name == "Body" then
				parts = parts + 1
			else
				other = other + 1
			end
		end
	end
	return mesh, parts, other
end

local function rigNames(model)
	local names = {}
	for entry in string.gmatch(model:GetAttribute("PB_Rig") or "", "[^;]+") do
		local spec = string.match(entry, "^(.-)=") or entry
		names[#names + 1] = (string.match(spec, "^([^:]+):([^:]+)")) .. ":" .. (select(2, string.match(spec, "^([^:]+):([^:]+)")))
	end
	return table.concat(names, ",")
end

-- the test pets (catalog defs + made-up looks)
local function testDefs()
	local pup = catalog("pebble_pup")
	return {
		dog = pup,
		cat = catalog("mallow_kitten"),
		corgi = catalog("waffle_corgi"),
		dragon = catalog("twilight_dragon"),
		crown = catalog("sunbeam_bear"),
		golden = (function()
			local d = copyDef(pup, { Finish = "Golden" })
			d.Id = "pebble_pup@Golden"
			d.PetId = "pebble_pup"
			return d
		end)(),
		rainbow = (function()
			local d = copyDef(pup, { Finish = "Rainbow" })
			d.Id = "pebble_pup@Rainbow"
			d.PetId = "pebble_pup"
			return d
		end)(),
		hybrid = (function()
			local d = copyDef(pup, { Hybrid = true, StyleId = "mallow_kitten", Seed = 11, BodyId = "pebble_pup" })
			d.Id = "hy_pebble_pup_mallow_kitten_11"
			d.IsHybrid = true
			return d
		end)(),
	}
end

----------------------------------------------------------------------------------------------------------------------
-- server
----------------------------------------------------------------------------------------------------------------------
if IS_SERVER then
S.p6pets_mesh_on = guarded("p6pets_mesh_on", function()
	if not MESH_MODE then
		T.info("fixture mesh mode off (python3 tools/smoke.py --mesh turns it on)")
		return
	end
	local keys = petKeys()
	local t0 = os.clock()
	local _, ready = install(keys)
	T.check(ready == #keys, fmt("fixture mesh mode: %d / %d pet-class keys loaded + fitted by the real loader", ready, #keys))
	T.info(fmt("fixture install took %.1f s", os.clock() - t0))
	flushWarn("p6pets_mesh_on")
end)

S.p6pets_default = guarded("p6pets_default", function()
	local ML, Pets = lib(), PB()
	local D = testDefs()
	if MESH_MODE then
		T.info("fixture mesh mode: the default-mode checks are skipped")
	else
		T.check(not ML.Active(), "empty MeshIds: MeshLibrary.Active() is false (no template folder)")
		local m = Pets.Build(D.dog, { Detail = "High" })
		local mesh = countParts(m)
		T.check(m:GetAttribute("ML_Mesh") == nil and mesh == 0, "empty MeshIds: Build is today's Part build (no ML_Mesh, no MeshPart)")
		T.check(Pets.NeedsMeshRebuild(m) == false, "empty MeshIds: NeedsMeshRebuild is false")
		local e = Pets.Build(D.dragon, { Detail = "Low", Evolved = 2 })
		T.check(e:GetAttribute("ML_Mesh") == nil and countParts(e) == 0 and e:FindFirstChild("Body") ~= nil, "empty MeshIds: an evolved Low dragon is the Part build")
		m:Destroy()
		e:Destroy()
	end
	T.check(type(Pets.MeshVersion()) == "number", "PetBuilder.MeshVersion() is a number")
	local function keys(def, opts)
		local list = Pets.MeshKeys(def, opts)
		return list and table.concat(list, ",") or "nil"
	end
	T.eq(keys(D.dog, {}), "pet_dog,wing_feather_L,wing_feather_R", "MeshKeys: pebble pup = dog body + feather wings")
	T.eq(keys(D.dog, { Detail = "Low" }), "pet_dog_low,wing_feather_L_low,wing_feather_R_low", "MeshKeys: Low detail picks the _low keys")
	T.eq(keys(D.corgi, {}), "pet_dog_corgi,wing_feather_L,wing_feather_R,acc_flower", "MeshKeys: the corgi uses its species variant key (+ its flower at the Flower attachment)")
	T.eq(keys(D.cat, {}), "pet_cat,wing_fairy_L,wing_fairy_R", "MeshKeys: mallow kitten = cat body + fairy wings")
	T.eq(keys(D.dragon, {}), "pet_dragon,wing_bat_L,wing_bat_R,acc_horns", "MeshKeys: twilight dragon = dragon + bat wings + horns")
	T.eq(keys(D.crown, {}), "pet_bear,wing_feather_L,wing_feather_R,acc_crown", "MeshKeys: sunbeam bear wears the crown key")
	T.eq(keys(D.golden, {}), "pet_dog,wing_feather_L,wing_feather_R,star_gold", "MeshKeys: Golden adds the sparkle star key")
	T.eq(keys(D.hybrid, {}), "pet_dog,wing_feather_L,wing_feather_R,hyb_cat", "MeshKeys: a dog x cat hybrid adds hyb_cat")
	T.eq(keys(D.dog, { Evolved = 1 }), "evo1_pebble_pup,evowing_pebble_pup_1_L,evowing_pebble_pup_1_R", "MeshKeys: first evolution = evo1 body + its wings")
	T.eq(keys(D.dog, { Evolved = 2 }), "evo1_pebble_pup,evowing_pebble_pup_1_L,evowing_pebble_pup_1_R", "MeshKeys: a Common pet stops at its first evolution")
	local d2 = keys(D.dragon, { Evolved = 2, Detail = "Low" })
	T.check(string.find(d2, "^evo2_twilight_dragon_low,evowing_twilight_dragon_2_L_low,evowing_twilight_dragon_2_R_low") ~= nil,
		"MeshKeys: second evolution Low = evo2 _low body + stage-2 wings (+ the 2b pair when it exists)", d2)
	T.eq(keys(D.hybrid, { Evolved = 1 }), "nil", "MeshKeys: an evolved hybrid has no mesh design (species design = Part build)")
	T.eq(keys({ Id = "x", Look = { Species = "Cat", WingStyle = "Nope" } }, {}), "pet_cat,wing_feather_L,wing_feather_R", "MeshKeys: unknown values fall back like the sculpt (Cat / Feather)")
end)

S.p6pets_server = guarded("p6pets_server", function()
	local ML, Pets = lib(), PB()
	local D = testDefs()
	local need, seen = {}, {}
	local function want(def, opts)
		for _, k in ipairs(Pets.MeshKeys(def, opts) or {}) do
			if not seen[k] then
				seen[k] = true
				need[#need + 1] = k
			end
		end
	end
	for _, name in ipairs({ "dog", "cat", "corgi", "dragon", "crown", "golden", "rainbow", "hybrid" }) do
		want(D[name], {})
	end
	want(D.dog, { Detail = "Low" })
	want(D.dog, { Evolved = 1 })
	want(D.dragon, { Evolved = 2 })
	want(D.cat, { Evolved = 1, Detail = "Low" })
	table.sort(need)
	local partDog = Pets.Build(D.dog, { Parts = true })
	local before = nil
	if not MESH_MODE then
		before = Pets.Build(D.dog, {})
	end
	local v0 = Pets.MeshVersion()
	withFixtures(need, function()
		T.check(ML.IsReady(need), fmt("fixtures: %d keys ready through the real loader (fake MeshIds + Mock.AssetLoader)", #need))
		if before then
			T.check(Pets.MeshVersion() ~= v0, "MeshVersion changes when keys become ready")
			T.check(Pets.NeedsMeshRebuild(before) == true, "NeedsMeshRebuild: a Part-built pet whose keys are now ready")
		end
		-- 1. the dog: structure, names, attributes, rig
		local dog = Pets.Build(D.dog, {})
		local mesh, roots, other = countParts(dog)
		T.check(dog:GetAttribute("ML_Mesh") == true and mesh > 10 and roots == 1 and other == 0, "dog: a mesh pet (MeshParts only + the Body root)", fmt("mesh %d root %d other %d", mesh, roots, other))
		local body = dog:FindFirstChild("Body")
		T.check(dog.PrimaryPart == body and body:IsA("Part") and body.Transparency == 1 and not body.CanCollide, "dog: PrimaryPart = an invisible, non-colliding Body Part")
		T.check(body and (body.Size - Vector3.new(0.9, 1.1, 0.9)).Magnitude < 1e-3, "dog: Body root 0.9 x 1.1 x 0.9 at Scale 1 (as the Part build)")
		-- [fix-meshlib W3b, review3 runtime-2] a SERVER-built mesh pet carries its definition (PBD_*) + the
		-- PB_ServerMesh tag, so a device that cannot draw its meshes rebuilds the same Part pet (client MeshFallback)
		for _, name in ipairs({ "dog", "hybrid", "golden" }) do
			local sm = Pets.Build(D[name], { Scale = 2, Evolved = (name == "dog") and 1 or nil })
			local def, opts = Pets.ServerDef(sm)
			local CS = game:GetService("CollectionService")
			local sameLook = def ~= nil and def.Look ~= nil
			for k, v in pairs(D[name].Look or {}) do
				if typeof(v) ~= "table" and def and def.Look[k] ~= v then
					sameLook = false
				end
			end
			T.check(sm:GetAttribute("ML_Mesh") == true and CS:HasTag(sm, Pets.ServerMeshTag) and def and def.Id == D[name].Id and def.Rarity == D[name].Rarity
				and sameLook and opts.Parts == true and opts.NoFx == true and opts.Scale == 2 and opts.Evolved == ((name == "dog") and 1 or 0)
				and type(sm:GetAttribute("PBD_Keys")) == "string" and (name ~= "hybrid" or (def.IsHybrid == true and def.Look.Hybrid == true and def.Look.StyleId == "mallow_kitten" and def.Look.Seed == 11)),
				name .. ": a server-built mesh pet is stamped (PBD_* definition, keys, PB_ServerMesh tag) and PetBuilder.ServerDef reads it back")
			local copy = def and Pets.Build(def, opts)
			T.check(copy ~= nil and copy:GetAttribute("ML_Mesh") == nil and copy:GetAttribute("PB_Evolved") == sm:GetAttribute("PB_Evolved")
				and not CS:HasTag(copy, Pets.ServerMeshTag) and copy:GetAttribute("PBD_Detail") == nil,
				name .. ": Build(ServerDef(model)) = the same pet as a Part build (same stage), never stamped")
			sm:Destroy()
			if copy then
				copy:Destroy()
			end
		end
		local names = {}
		for _, c in ipairs(dog:GetChildren()) do
			names[c.Name] = c
		end
		T.check(names.Fur and names.EyeIris and names.EyePupil and names.EyeShine and names.WingL and names.WingR and names.Tail and names.EyeLid,
			"dog: recipe 4.3 names (Fur, EyeIris, EyePupil, EyeShine, WingL, WingR, Tail, EyeLid)")
		local mkOk = true
		for _, c in ipairs(dog:GetChildren()) do
			if c:IsA("MeshPart") and (type(c:GetAttribute("MK_Key")) ~= "string" or type(c:GetAttribute("ML_Key")) ~= "string") then
				mkOk = false
			end
			if c:IsA("BasePart") and (c.Anchored ~= true or c.CanCollide or c.CanTouch or c.CanQuery or c.CastShadow) then
				mkOk = false
			end
		end
		T.check(mkOk, "dog: every MeshPart carries MK_Key / ML_Key; anchored, no collisions / touch / query / shadow")
		for _, a in ipairs({ "PetId", "PB_Seed", "PB_Detail", "PB_Evolved", "PB_Scale" }) do
			T.eq(dog:GetAttribute(a), partDog:GetAttribute(a), "dog: " .. a .. " equals the Part build's")
		end
		T.eq(rigNames(dog), rigNames(partDog), "dog: PB_Rig has the Part build's groups in instantiate order")
		local lid = names.EyeLid
		T.check(lid and lid.Transparency == 1 and type(lid:GetAttribute("PB_T0")) == "number", "dog: eye lids hidden with PB_T0 (blink)")
		-- 2. Animate on the mesh pet and its clone
		local function animOk(m, t0)
			t0 = t0 or 0
			local count0 = #m:GetDescendants()
			local w = m:FindFirstChild("WingL")
			local c0 = w and w.CFrame
			local nan = false
			for i = 1, 12 do
				Pets.Animate(m, t0 + i * 0.07, { Flap = 1, Excited = 0.5 })
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						local p = d.Position
						if not (finite(p.X) and finite(p.Y) and finite(p.Z)) then
							nan = true
						end
					end
				end
			end
			local moved = w and c0 and (w.CFrame.Position - c0.Position).Magnitude > 1e-4 or false
			return (not nan) and moved and #m:GetDescendants() == count0
		end
		T.check(animOk(dog), "dog: Animate flaps the mesh wings (no NaN, no new instances)")
		local clone = dog:Clone()
		clone.Parent = workspace
		T.check(animOk(clone, 3.3), "dog: a Clone() animates too (rig rebuilt from attributes)")
		clone:Destroy()
		-- 3. the size is close to the Part pet
		local _, sm = dog:GetBoundingBox()
		local _, sp = partDog:GetBoundingBox()
		T.check(math.abs(sm.Y - sp.Y) / sp.Y < 0.25 and math.abs(sm.X - sp.X) / sp.X < 0.35, "dog: the mesh pet is about the Part pet's size",
			fmt("mesh %.2f x %.2f x %.2f, parts %.2f x %.2f x %.2f", sm.X, sm.Y, sm.Z, sp.X, sp.Y, sp.Z))
		-- 4. other species, variants, accessories
		for _, name in ipairs({ "cat", "corgi", "dragon", "crown" }) do
			local m = Pets.Build(D[name], {})
			local keys = m:GetAttribute("ML_Keys") or ""
			T.check(m:GetAttribute("ML_Mesh") == true and m:FindFirstChild("WingL") and m:FindFirstChild("WingR"), name .. ": mesh pet with both wings (" .. keys .. ")")
			m:Destroy()
		end
		local crown = Pets.Build(D.crown, {})
		local crownKey = false
		for _, c in ipairs(crown:GetChildren()) do
			if c:GetAttribute("ML_Key") == "acc_crown" then
				crownKey = true
			end
		end
		T.check(crownKey, "crown: the acc_crown parts sit on the pet (at the body's Hat attachment)")
		crown:Destroy()
		local dragon = Pets.Build(D.dragon, {})
		local neon = dragon:FindFirstChild("EyeIris")
		T.check(neon and neon.Material == Enum.Material.Neon, "dragon (Glow): EyeIris is Neon")
		dragon:Destroy()
		-- 5. Low detail
		local low = Pets.Build(D.dog, { Detail = "Low" })
		T.check(low:GetAttribute("ML_Mesh") == true and low:GetAttribute("PB_Detail") == "Low" and string.find(low:GetAttribute("ML_Keys"), "pet_dog_low", 1, true) ~= nil, "Low detail: built from the _low keys")
		low:Destroy()
		-- 6. Wild
		local wild = Pets.Build(D.dog, { Wild = { Tint = Color3.fromRGB(90, 40, 120), Eyes = Color3.fromRGB(255, 60, 60) } })
		local iris = wild:FindFirstChild("EyeIris")
		T.check(wild:GetAttribute("PB_Wild") == true and wild:GetAttribute("ML_Mesh") == true and iris and iris.Material == Enum.Material.Neon and iris.Color == Color3.fromRGB(255, 60, 60), "Wild: a mesh pet with Neon eyes in the floor colour")
		wild:Destroy()
		-- 7. Golden / Rainbow
		local gold = Pets.Build(D.golden, {})
		local spark, metal = gold:FindFirstChild("GoldSpark"), false
		for _, c in ipairs(gold:GetChildren()) do
			if c:IsA("BasePart") and c.Material == Enum.Material.Metal then
				metal = true
			end
		end
		T.check(gold:GetAttribute("PB_Finish") == "Golden" and spark and spark.Material == Enum.Material.Neon and type(spark:GetAttribute("PB_Pulse")) == "number" and metal and gold.Body:FindFirstChild("FinishSparkles") ~= nil,
			"Golden: PB_Finish, glowing GoldSpark stars that pulse, Metal accents, the gold sparkle emitter",
			fmt("finish %s spark %s metal %s keys %s", tostring(gold:GetAttribute("PB_Finish")), tostring(spark), tostring(metal), tostring(gold:GetAttribute("ML_Keys"))))
		gold:Destroy()
		local rb = Pets.Build(D.rainbow, {})
		local hue = 0
		for _, c in ipairs(rb:GetChildren()) do
			if type(c:GetAttribute("PB_Hue")) == "number" then
				hue = hue + 1
			end
		end
		T.check(rb:GetAttribute("PB_Finish") == "Rainbow" and hue > 0 and hue <= 10, "Rainbow: PB_Finish + 1..10 hue-cycling parts", "hue parts " .. hue)
		rb:Destroy()
		-- 8. hybrid
		local hy = Pets.Build(D.hybrid, {})
		local hyA, hyTail, bodyTail = nil, 0, 0
		for _, c in ipairs(hy:GetChildren()) do
			if c:GetAttribute("MK_Key") == "HyA" then
				hyA = c
			end
			if string.sub(c.Name, 1, 4) == "Tail" then
				if c:GetAttribute("ML_Key") == "hyb_cat" then
					hyTail = hyTail + 1
				else
					bodyTail = bodyTail + 1
				end
			end
		end
		local partHy = Pets.Build(D.hybrid, { Parts = true })
		T.check(hy:GetAttribute("PB_Hybrid") == true and hyA ~= nil and hy:GetAttribute("PB_Seed") == partHy:GetAttribute("PB_Seed"), "hybrid: PB_Hybrid, the hyb_cat feature (HyA) on the dog body")
		T.check(hyTail > 0 and bodyTail == 0, "hybrid: the cat feature's own tail replaces the body's tail", fmt("feature tail %d, body tail %d", hyTail, bodyTail))
		local hyPartA = nil
		for _, c in ipairs(partHy:GetChildren()) do
			if c.Name == "HyA" then
				hyPartA = c
			end
		end
		T.check(hyA and hyPartA and (Vector3.new(hyA.Color.R, hyA.Color.G, hyA.Color.B) - Vector3.new(hyPartA.Color.R, hyPartA.Color.G, hyPartA.Color.B)).Magnitude < 0.12,
			"hybrid: HyA has the Part build's hybrid colour (Style Primary + seed jitter)")
		hy:Destroy()
		partHy:Destroy()
		-- 9. evolved: PetFx, grow, viewport
		local e1 = Pets.Build(D.dog, { Evolved = 1 })
		T.check(e1:GetAttribute("ML_Mesh") == true and e1:GetAttribute("PB_Evolved") == 1, "evolved 1: a mesh pet with PB_Evolved = 1")
		local fx = e1:FindFirstChild("Body") and e1.Body:FindFirstChild("PetFx")
		T.check(fx ~= nil and fx:IsA("Attachment"), "evolved 1: PetFx on the mesh pet (Body.PetFx)")
		T.check(animOk(e1), "evolved 1: Animate works on the mesh form")
		e1:Destroy()
		local e2 = Pets.Build(D.dragon, { Evolved = 2 })
		local e2p = Pets.Build(D.dragon, { Evolved = 2, Parts = true })
		T.check(e2:GetAttribute("ML_Mesh") == true and e2:GetAttribute("PB_Evolved") == 2, "evolved 2: a mesh pet with PB_Evolved = 2")
		T.near(e2:GetAttribute("PB_Scale"), e2p:GetAttribute("PB_Scale"), 1e-6, "evolved 2: PB_Scale includes the second-evolution grow (as instantiate)")
		-- (the mesh may carry a group the budget-capped Part sculpt dropped, e.g. the Halo: the Part groups must be there,
		-- in the same order)
		local mr, pr = rigNames(e2), rigNames(e2p)
		local at, inOrder = 0, true
		for g in string.gmatch(pr, "[^,]+") do
			local f = string.find("," .. mr .. ",", "," .. g .. ",", at + 1, true)
			if not f then
				inOrder = false
			else
				at = f
			end
		end
		T.check(inOrder, "evolved 2: PB_Rig holds the Part build's groups in instantiate order", "mesh " .. mr .. " | parts " .. pr)
		local pulse = 0
		for _, c in ipairs(e2:GetChildren()) do
			if c:GetAttribute("PFX_Pulse") then
				pulse = pulse + 1
			end
		end
		T.check(e2.Body:FindFirstChild("PetFx") ~= nil, "evolved 2: PetFx effects on the mesh pet", "pulsing aura parts " .. pulse)
		e2:Destroy()
		e2p:Destroy()
		local vp = Pets.Build(D.dog, { Evolved = 1, Viewport = true })
		T.check(vp:GetAttribute("ML_Mesh") == true and not (vp.Body:FindFirstChild("PetFx") and #vp.Body.PetFx:GetChildren() > 0 and vp.Body.PetFx:FindFirstChildWhichIsA("ParticleEmitter")), "Viewport = true: no PetFx particles in a viewport build")
		vp:Destroy()
		-- 10. battle unit scale
		local unit = Pets.Build(D.cat, { Scale = 1.6, Detail = "Low", Evolved = 1 })
		T.check(unit:GetAttribute("ML_Mesh") == true and math.abs(unit:GetAttribute("PB_Scale") - 1.6) < 1e-6 and (unit.Body.Size - Vector3.new(0.9, 1.1, 0.9) * 1.6).Magnitude < 1e-3,
			"battle unit (Scale 1.6, Low, evolved): mesh pet scaled, Body root scaled",
			fmt("mesh %s scale %s body %s", tostring(unit:GetAttribute("ML_Mesh")), tostring(unit:GetAttribute("PB_Scale")), tostring(unit.Body.Size)))
		unit:Destroy()
		-- 11. opts.Parts forces the Part build; a partially ready set falls back whole
		local forced = Pets.Build(D.dog, { Parts = true })
		T.check(forced:GetAttribute("ML_Mesh") == nil and countParts(forced) == 0, "opts.Parts = true: the Part build")
		forced:Destroy()
		local root = installed and installed.Root or (RS:FindFirstChild("P6PetsMeshLibrary"))
		local wingR = root and root:FindFirstChild("wing_feather_R")
		if wingR then
			wingR:SetAttribute("ML_Status", "failed")
			local mixed = Pets.Build(D.dog, {})
			T.check(mixed:GetAttribute("ML_Mesh") == nil and countParts(mixed) == 0, "one key not usable (wing_feather_R failed): the WHOLE pet is the Part build, never a mix")
			T.check(Pets.NeedsMeshRebuild(mixed) == false, "NeedsMeshRebuild is false while a key is not usable")
			wingR:SetAttribute("ML_Status", "ready")
			T.check(Pets.NeedsMeshRebuild(mixed) == true, "NeedsMeshRebuild turns true once every key is usable again")
			mixed:Destroy()
		else
			T.fail("partial set test: no wing_feather_R template found")
		end
		dog:Destroy()
	end)
	if before then
		before:Destroy()
	end
	partDog:Destroy()
	if not MESH_MODE then
		T.check(not ML.Active() and Pets.Build(D.dog, {}):GetAttribute("ML_Mesh") == nil, "after the scenario: fixtures removed, Build is the Part build again")
	end

	-- [fix-runtime W2.5] a Golden PART pet wears the star_gold mesh once that key is ready (MESH.partStars)
	if not MESH_MODE then
		install({ "star_gold" })
		local okStars, errStars = pcall(function()
			local g = Pets.Build(D.golden, {})
			local ref = Pets.Build(D.golden, { Parts = true })
			local meshStars, partStars, refStars = {}, 0, {}
			for _, c in ipairs(g:GetChildren()) do
				if c:IsA("BasePart") and string.sub(c.Name, 1, 9) == "GoldSpark" and c:GetAttribute("PB_G") == nil then
					if c:GetAttribute("ML_Key") == "star_gold" then
						meshStars[#meshStars + 1] = c
					else
						partStars = partStars + 1
					end
				end
			end
			for _, c in ipairs(ref:GetChildren()) do
				if c:IsA("BasePart") and string.sub(c.Name, 1, 9) == "GoldSpark" and c:GetAttribute("PB_G") == nil then
					refStars[#refStars + 1] = c
				end
			end
			T.check(g:GetAttribute("ML_Mesh") == nil and #meshStars >= 2 and partStars == 0 and g:GetAttribute("PB_MeshStars") == #meshStars,
				fmt("star_gold ready, body keys not: a Golden Part pet's body sparkle stars are star_gold MeshParts (%d mesh, %d voxel left)", #meshStars, partStars))
			local far = 0
			for _, m in ipairs(meshStars) do
				local best = math.huge
				for _, r in ipairs(refStars) do
					best = math.min(best, (r.Position - m.Position).Magnitude)
				end
				if best > 0.35 then
					far = far + 1
				end
				if not (m.Material == Enum.Material.Neon and m:GetAttribute("PB_Star") == true and type(m:GetAttribute("PB_Pulse")) == "number") then
					far = far + 100
				end
			end
			T.check(far == 0, "mesh stars sit on the voxel stars' centres (Neon, PB_Star, PB_Pulse)", tostring(far))
			local okA = pcall(Pets.Animate, g, 1.5, {})
			T.check(okA and #refStars > 0 and ref:GetAttribute("PB_MeshStars") == nil, "the mesh-star pet animates; opts.Parts = true keeps the voxel stars")
			g:Destroy()
			ref:Destroy()
		end)
		uninstall()
		T.check(okStars, "Golden mesh-star checks ran", tostring(errStars))
		local back = Pets.Build(D.golden, {})
		T.check(back:GetAttribute("PB_MeshStars") == nil, "star_gold gone: the Golden Part pet has its voxel stars again")
		back:Destroy()
	end

	-- [fix-runtime W2.5] server-built pets become mesh pets when the keys load AFTER the build (MeshLibrary.Swap)
	if MESH_MODE then
		T.info("fixture mesh mode: the server's pets are mesh pets from the start (late-swap checks skipped)")
	else
		local okNs, NS = pcall(function()
			return require(Mock.GetPath(ROOTS.server .. "/Services/NpcService"))
		end)
		local recs = (okNs and type(NS) == "table" and type(NS.GetNpcs) == "function") and NS.GetNpcs() or {}
		if T.check(#recs > 0, "late swap: NpcService has its booted NPCs") then
			local spots, ids, lateKeys, seenK = {}, {}, {}, {}
			local function addKeys(def, opts)
				for _, k in ipairs((def and Pets.MeshKeys(def, opts)) or {}) do
					if not seenK[k] then
						seenK[k] = true
						lateKeys[#lateKeys + 1] = k
					end
				end
			end
			for i, r in ipairs(recs) do
				spots[i] = r.Spot
				ids[i] = r.Model:GetAttribute("PetId")
				addKeys(ids[i] and catalog(ids[i]), { Detail = "High" })
			end
			local storm = catalog("stormfang")
			addKeys(storm, { Detail = "High", Scale = 3 })
			table.sort(lateKeys)
			installLate(lateKeys)
			local okLate, errLate = pcall(function()
				T.check(not ML.IsReady(lateKeys), fmt("late swap: %d keys still loading while the builders run", #lateKeys))
				NS.Init({ NpcSpots = spots }, {})
				local folder = workspace:FindFirstChild("NimbusNpcs")
				local before = {}
				local partPets = 0
				for i, r in ipairs(NS.GetNpcs()) do
					before[i] = { Model = r.Model, Ped = r.Model:FindFirstChild("Pedestal") and r.Model.Pedestal:GetPivot().Position }
					if r.Pet and r.Pet:GetAttribute("ML_Mesh") == nil then
						partPets = partPets + 1
					end
				end
				T.check(partPets == #recs, fmt("late swap: NPCs built before the keys load have Part pets (%d / %d)", partPets, #recs))
				-- the Storm Altar flow: a placed showcase that rebuilds itself (Place = false: buildFn places it)
				local holder = Instance.new("Model")
				holder.Name = "P6LateShowcase"
				holder.Parent = workspace
				local opts = { Detail = "High", Scale = 3 }
				local show = Pets.Build(storm, opts)
				show.Name = "StormfangShowcase"
				show:PivotTo(CFrame.new(300, 40, 0))
				show.Parent = holder
				local gotFresh, gotOld = nil, nil
				local reg = Pets.SwapWhenReady(show, storm, opts, function()
					local m = Pets.Build(storm, opts)
					m.Name = "StormfangShowcase"
					m:PivotTo(CFrame.new(300, 44, 0))
					return m
				end, function(fresh, old)
					gotFresh, gotOld = fresh, old
				end)
				T.check(reg == true, "SwapWhenReady registers a Part pet whose keys are loading")
				T.check(advanceUntilReady(lateKeys), "late swap: the keys finished loading")
				local newShow = holder:FindFirstChild("StormfangShowcase")
				T.check(newShow ~= nil and newShow ~= show and newShow:GetAttribute("ML_Mesh") == true and show.Parent == nil and #holder:GetChildren() == 1,
					"SwapWhenReady: the Part showcase was replaced by the mesh one (same name and parent)")
				T.check(newShow ~= nil and (newShow:GetPivot().Position - Vector3.new(300, 44, 0)).Magnitude < 1e-3 and gotFresh == newShow and gotOld == show,
					"SwapWhenReady: the build placed itself (no PivotTo onto the old pivot) and onSwapped got (fresh, old)")
				T.check(Pets.SwapWhenReady(newShow, storm, opts, function()
					return nil
				end) == false, "SwapWhenReady: nothing to do for a mesh pet / ready keys")
				holder:Destroy()
				-- the NPCs (PetParts = every BasePart of the pet, its invisible root included: NpcController waits for it)
				local function allParts(model)
					local n = 0
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") then
							n = n + 1
						end
					end
					return n
				end
				local now = NS.GetNpcs()
				local bad = {}
				for i, r in ipairs(now) do
					local m = r.Model
					local why = nil
					if m == before[i].Model or m.Parent ~= folder or before[i].Model.Parent ~= nil then
						why = "model not replaced"
					elseif not r.Pet or r.Pet.Parent ~= m or r.Pet:GetAttribute("ML_Mesh") ~= true then
						why = "pet not mesh"
					elseif not m.PrimaryPart or m.PrimaryPart ~= r.Pet.PrimaryPart then
						why = "PrimaryPart"
					elseif m:GetAttribute("PetParts") ~= allParts(r.Pet) then
						why = "PetParts " .. tostring(m:GetAttribute("PetParts")) .. " vs " .. allParts(r.Pet)
					elseif not r.Prompt or not r.Prompt:IsDescendantOf(m) or not game:GetService("CollectionService"):HasTag(m, "NC_Npc") then
						why = "prompt / tag"
					elseif m:GetAttribute("Ready") ~= true or m:GetAttribute("PetId") ~= ids[i] then
						why = "attributes"
					end
					local ped = m:FindFirstChild("Pedestal")
					if not why and before[i].Ped and ped and (ped:GetPivot().Position - before[i].Ped).Magnitude >= 1e-3 then
						why = "pedestal moved"
					end
					if why then
						bad[#bad + 1] = tostring(r.Id) .. " (" .. why .. ")"
					end
				end
				T.check(#now == #recs and #bad == 0, "late swap: every NPC was rebuilt in place with its mesh pet (record, PrimaryPart, PetParts, prompt, tag, pedestal unmoved)", table.concat(bad, ", "))
				local named = 0
				for _, c in ipairs(folder:GetChildren()) do
					if string.sub(c.Name, 1, 4) == "Npc_" then
						named = named + 1
					end
				end
				T.check(named == #recs, fmt("late swap: one model per NPC in NimbusNpcs (%d)", named))
			end)
			uninstall()
			T.check(okLate, "late swap checks ran", tostring(errLate))
			-- put the booted (Part) NPCs back
			NS.Init({ NpcSpots = spots }, {})
			local mesh = 0
			for _, r in ipairs(NS.GetNpcs()) do
				if r.Pet and r.Pet:GetAttribute("ML_Mesh") == true then
					mesh = mesh + 1
				end
			end
			T.check(#NS.GetNpcs() == #recs and mesh == 0, "late swap: NPCs rebuilt from Parts afterwards")
			-- empty MeshIds (no template folder): SwapWhenReady does nothing at all
			local p = Pets.Build(D.dog, {})
			p.Parent = workspace
			T.check(Pets.SwapWhenReady(p, D.dog, {}, function()
				return Pets.Build(D.dog, {})
			end) == false and not ML.Active(), "empty MeshIds: SwapWhenReady = false, no state")
			p:Destroy()
			-- [fix-meshlib W3b, review3 world-3] a pet key that FAILED to load on the server: a podium / NPC rebuild never
			-- waits on it (SwapWhenReady = false, no OnReady closure kept), and its waiters from the loading time are gone
			local dogKeys = Pets.MeshKeys(D.dog, {}) or {}
			local failKey = dogKeys[#dogKeys]
			local fails = {}
			for _, k in ipairs(dogKeys) do
				fails[#fails + 1] = k
			end
			local savedLoader = Mock.AssetLoader
			ML._Reset()
			Pets.ClearCache()
			local froot = Instance.new("Folder")
			froot.Name = "P6PetsFailRoot"
			froot.Parent = RS
			local fids, fby = {}, {}
			for i, k in ipairs(fails) do
				fids[k] = 7400000 + i
				fby[7400000 + i] = k
			end
			ML._Configure({ Root = froot, Ids = fids, RetryDelays = { 0.05 } })
			Mock.AssetLoader = function(id)
				task.wait(0.3)
				local k = fby[id]
				if not k or k == failKey then
					error("Asset is not authorized for this place", 0)
				end
				return fakeAsset(k)
			end
			ML.Start()
			local early = Pets.Build(D.dog, {})
			early.Parent = workspace
			local regEarly = Pets.SwapWhenReady(early, D.dog, {}, function()
				return Pets.Build(D.dog, {})
			end)
			for _ = 1, 20 do
				Mock.Advance(0.5)
			end
			local waiting = 0
			for _, k in ipairs(fails) do
				waiting = waiting + ML._Waiters(k)
			end
			T.check(regEarly == true and ML.Status(failKey) == "failed" and waiting == 0 and early.Parent == workspace and early:GetAttribute("ML_Mesh") == nil,
				"world-3: the key failed while a swap waited: the Part pet stays and no waiter is left",
				fmt("registered %s, %s %s, %d waiting", tostring(regEarly), failKey, ML.Status(failKey), waiting))
			local late = Pets.Build(D.dog, {})
			late.Parent = workspace
			local calls = 0
			T.check(Pets.SwapWhenReady(late, D.dog, {}, function()
				calls = calls + 1
				return Pets.Build(D.dog, {})
			end) == false, "world-3: SwapWhenReady on a pet with a 'failed' key = false (nothing registered)")
			local after = 0
			for _, k in ipairs(fails) do
				after = after + ML._Waiters(k)
			end
			Mock.Advance(1)
			T.check(after == 0 and calls == 0 and late.Parent == workspace, "world-3: ...no OnReady closure kept, never rebuilt")
			early:Destroy()
			late:Destroy()
			Mock.AssetLoader = savedLoader
			ML._Reset()
			froot:Destroy()
			Pets.ClearCache()
		end
	end
	flushWarn("p6pets_server")
end)
end

----------------------------------------------------------------------------------------------------------------------
-- client
----------------------------------------------------------------------------------------------------------------------
if not IS_SERVER then
S.client_p6pets_mesh_on = guarded("client_p6pets_mesh_on", function()
	if not MESH_MODE then
		T.info("fixture mesh mode off (python3 tools/smoke.py --mesh turns it on)")
		return
	end
	local keys = petKeys()
	local _, ready = install(keys)
	T.check(ready == #keys, fmt("fixture mesh mode (client): %d / %d pet-class keys preloaded on this device", ready, #keys))
	flushWarn("client_p6pets_mesh_on")
end)

S.client_p6pets = guarded("client_p6pets", function()
	local ML, Pets = lib(), PB()
	local D = testDefs()
	local need = {}
	for _, k in ipairs(Pets.MeshKeys(D.dog, {}) or {}) do
		need[#need + 1] = k
	end
	for _, k in ipairs(Pets.MeshKeys(D.dog, { Detail = "Low" }) or {}) do
		need[#need + 1] = k
	end
	for _, k in ipairs(Pets.MeshKeys(D.dog, { Evolved = 1 }) or {}) do
		need[#need + 1] = k
	end
	for _, k in ipairs(Pets.MeshKeys(D.dog, { Evolved = 1, Detail = "Low" }) or {}) do
		need[#need + 1] = k
	end
	table.sort(need)
	-- a viewport built BEFORE the keys are ready (Part model), swapped once they are
	local CloudUI = nil
	pcall(function()
		CloudUI = require(Mock.GetPath(ROOTS.client .. "/UI/CloudUI"))
	end)
	local holder = Instance.new("ScreenGui")
	holder.Name = "P6PetsViewport"
	holder.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local handle = nil
	if CloudUI and not MESH_MODE then
		handle = CloudUI.PetViewport(holder, D.dog, UDim2.new(0, 200, 0, 200), { Evolved = 1 })
	end
	local partVp = handle and handle.Model
	T.check(not handle or (partVp and partVp:GetAttribute("ML_Mesh") == nil), "CloudUI.PetViewport before the keys are ready: the Part model")
	-- a follower (PetController) built BEFORE the keys are ready
	local KC = _G.KC
	local LocalPlayer = game:GetService("Players").LocalPlayer
	local pc = KC and (KC.M and KC.M.PetController) or nil
	if not pc then
		pcall(function()
			pc = require(Mock.GetPath(ROOTS.client .. "/Controllers/PetController"))
		end)
	end
	local follow = KC and pc and type(pc.GetFollowerInfo) == "function"
	local partFollower = nil
	if follow then
		KC.toClient("ProfileSync", {
			Tokens = 600, Pets = { pebble_pup = 1 }, Equipped = {}, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			SpotIndex = 1, Perks = {}, Discovered = { pebble_pup = 1 }, IndexClaimed = {},
			Tutorial = { Step = 99, Done = true, Gifted = true }, PetLevels = { pebble_pup = 3 }, PetGrowth = {},
		})
		KC.advance(0.2)
		LocalPlayer:SetAttribute("EquippedPets", "")
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(0.3)
		Mock.Teleport(LocalPlayer, Vector3.new(-300, 60, 300))
		LocalPlayer:SetAttribute("EquippedPets", "pebble_pup")
		KC.advance(2)
		local info = pc.GetFollowerInfo(LocalPlayer)
		partFollower = info[1] and info[1].Model
		T.check(partFollower ~= nil and (MESH_MODE or partFollower:GetAttribute("ML_Mesh") == nil), "a follower built before the keys are ready: the Part pet")
	else
		T.fail("PetController.GetFollowerInfo is not reachable from the client world")
	end
	-- [fix-meshlib W3b, review3 runtime-4] a lobby of Part-built followers: when the keys become ready (MeshVersion
	-- changes) every pet is due for its mesh rebuild in the same frame, but only BUILD_MAX are built per frame; no pet
	-- may lose its model while it waits (the old one stays until its own replacement is built)
	local lobby, blinkConn, worstMissing, lobbyPets = {}, nil, 0, 0
	local function followersOf()
		local all = { LocalPlayer }
		for _, o in ipairs(lobby) do
			all[#all + 1] = o
		end
		return all
	end
	if follow and not MESH_MODE then
		for i = 1, 3 do
			local o = Mock.AddPlayer("P6Lobby" .. i, 7700 + i)
			lobby[#lobby + 1] = o
		end
		KC.advance(0.5)
		for i, o in ipairs(lobby) do
			Mock.Teleport(o, Vector3.new(-300 + 6 * i, 60, 306))
			o:SetAttribute("EquippedInfo", "3:0,3:0,3:0")
			o:SetAttribute("EquippedPets", "pebble_pup,pebble_pup,pebble_pup")
		end
		KC.advance(3)
		for _, pl in ipairs(followersOf()) do
			for _, info in ipairs(pc.GetFollowerInfo(pl)) do
				if info.Model then
					lobbyPets = lobbyPets + 1
				end
			end
		end
		blinkConn = game:GetService("RunService").Heartbeat:Connect(function()
			local missing = 0
			for _, pl in ipairs(followersOf()) do
				for _, info in ipairs(pc.GetFollowerInfo(pl)) do
					if not info.Model and not info.Parked then
						missing = missing + 1
					end
				end
			end
			worstMissing = math.max(worstMissing, missing)
		end)
	end
	withFixtures(need, function()
		if blinkConn then
			KC.advance(1)
			blinkConn:Disconnect()
			blinkConn = nil
			local meshPets = 0
			for _, pl in ipairs(followersOf()) do
				for _, info in ipairs(pc.GetFollowerInfo(pl)) do
					if info.Model and info.Model:GetAttribute("ML_Mesh") == true then
						meshPets = meshPets + 1
					end
				end
			end
			T.check(lobbyPets >= 10 and meshPets == lobbyPets and worstMissing == 0,
				"PetController: a lobby of Part followers becomes mesh pets with no frame where a pet has no model (review3 runtime-4)",
				fmt("%d pets, %d mesh, at most %d without a model in a frame", lobbyPets, meshPets, worstMissing))
			for _, o in ipairs(lobby) do
				Mock.RemovePlayer(o)
			end
			lobby = {}
		end
		if follow and not MESH_MODE then
			KC.advance(1)
			local info = pc.GetFollowerInfo(LocalPlayer)
			local m = info[1] and info[1].Model
			T.check(m and m ~= partFollower and m:GetAttribute("ML_Mesh") == true and partFollower.Parent == nil,
				"PetController: the Part follower is rebuilt as the mesh pet once its keys are ready here (MeshVersion poll)")
			if m then
				local welded = 0
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("Weld") then
						welded = welded + 1
					end
				end
				Mock.Teleport(LocalPlayer, Vector3.new(-260, 60, 300))
				KC.advance(3)
				local r = KC.root().Position
				local off = m:GetPivot().Position - r
				T.check(welded > 0 and m.Parent ~= nil and Vector3.new(off.X, 0, off.Z).Magnitude < 8, "PetController: the mesh follower is welded to its root and follows its owner",
					fmt("welds %d, offset %.1f", welded, Vector3.new(off.X, 0, off.Z).Magnitude))
				local wing = m:FindFirstChild("WingL")
				local c0 = wing and wing.CFrame
				KC.advance(0.4)
				T.check(wing and c0 and (wing.CFrame.Position - c0.Position).Magnitude > 1e-4, "PetController: the mesh follower flaps (Animate)")
			end
		end
		T.check(ML.IsReady(need), fmt("client fixtures: %d keys preloaded on this device", #need))
		local m = Pets.Build(D.dog, { Detail = "Low" })
		T.check(m:GetAttribute("ML_Mesh") == true, "client: Build gives the mesh pet on a preloaded device")
		m:Destroy()
		-- the viewport swaps its model (CloudUI polls MeshVersion in its ticker)
		if handle then
			for _ = 1, 20 do
				Mock.Advance(0.1)
			end
			local vpModel = nil
			local frame = handle.Frame
			for _, d in ipairs(frame:GetChildren()) do
				if d:IsA("Model") then
					vpModel = d
				end
			end
			T.check(vpModel and vpModel:GetAttribute("ML_Mesh") == true and partVp.Parent == nil, "CloudUI.PetViewport: the Part model is swapped for the mesh pet once the keys are ready")
			T.check(vpModel and not (vpModel.Body:FindFirstChild("PetFx") and vpModel.Body.PetFx:FindFirstChildWhichIsA("ParticleEmitter")), "CloudUI.PetViewport builds with Viewport = true (no PetFx particles)")
			handle.Destroy()
		else
			local vp = CloudUI and CloudUI.PetViewport(holder, D.dog, UDim2.new(0, 200, 0, 200), { Evolved = 1 })
			T.check(vp and vp.Model and vp.Model:GetAttribute("ML_Mesh") == true, "CloudUI.PetViewport: a mesh pet in fixture mode")
			if vp then
				vp.Destroy()
			end
		end
		-- a device preload failure: that key is broken here, Build keeps Parts
		local saved = Mock.PreloadHook
		local ML2 = ML
		local broken = "wing_feather_L"
		local root = installed and installed.Root
		if root and not MESH_MODE then
			Mock.PreloadHook = function(list, cb)
				for _, inst in ipairs(list) do
					cb(inst.Name, (inst.Name == broken) and Enum.AssetFetchStatus.Failure or Enum.AssetFetchStatus.Success)
				end
			end
			-- [fix-meshlib W3b, review3 runtime-2] what the server replicated: a mesh pet it built (stamped with its
			-- definition, tagged PB_ServerMesh), one whose keys all work here, and the client's MeshFallback watcher
			local function serverMesh(name, keys, at)
				local sm = Pets.Build(D.dog, {})
				sm.Name = name
				for k, v in pairs(D.dog.Look or {}) do
					if typeof(v) ~= "table" then
						sm:SetAttribute("PBDL_" .. k, v)
					end
				end
				sm:SetAttribute("PBD_Id", D.dog.Id)
				sm:SetAttribute("PBD_Rarity", D.dog.Rarity)
				sm:SetAttribute("PBD_Detail", "High")
				sm:SetAttribute("PBD_Stage", 0)
				sm:SetAttribute("PBD_Scale", 1)
				sm:SetAttribute("PBD_Keys", keys)
				sm:SetAttribute("ML_Mesh", true) -- (the late one is built after the failure: it stands in for a replicated mesh pet)
				sm:PivotTo(at)
				sm.Parent = workspace
				game:GetService("CollectionService"):AddTag(sm, Pets.ServerMeshTag)
				return sm
			end
			local srvBroken = serverMesh("P6ServerPet", table.concat(Pets.MeshKeys(D.dog, {}) or {}, ","), CFrame.new(40, 8, 40))
			local srvOk = serverMesh("P6ServerPetOk", "pet_dog", CFrame.new(50, 8, 40))
			local okMF, MF = pcall(function()
				return require(Mock.GetPath(ROOTS.client .. "/Controllers/MeshFallback"))
			end)
			ML2._Reset()
			ML2._Configure({ Root = root, Ids = { [broken] = 1, pet_dog = 2, wing_feather_R = 3 } })
			if okMF and type(MF) == "table" then
				MF.Stop()
				MF.Start(true)
			end
			ML2.Start()
			Mock.Advance(1)
			local m2 = Pets.Build(D.dog, {})
			T.check(ML2.Status(broken) == "failed" and m2:GetAttribute("ML_Mesh") == nil, "a key that failed to download on THIS device: Build keeps the Part pet here")
			m2:Destroy()
			if T.check(okMF and type(MF) == "table" and type(MF.Check) == "function", "client/Controllers/MeshFallback loads") then
				local copy = srvBroken:FindFirstChild("ML_PartCopy")
				local shown, welded, loose = 0, 0, 0
				for _, d in ipairs(srvBroken:GetDescendants()) do
					if d:IsA("MeshPart") and not (copy and d:IsDescendantOf(copy)) and d.Transparency < 1 then
						shown = shown + 1
					end
				end
				for _, d in ipairs(copy and copy:GetDescendants() or {}) do
					if d:IsA("BasePart") then
						local w = d:FindFirstChildOfClass("WeldConstraint")
						if w and w.Part0 == srvBroken.PrimaryPart and w.Part1 == d and not d.Anchored then
							welded = welded + 1
						else
							loose = loose + 1
						end
					end
				end
				T.check(copy ~= nil and copy:GetAttribute("ML_Mesh") == nil and shown == 0 and welded > 10 and loose == 0
					and (copy:GetPivot().Position - srvBroken:GetPivot().Position).Magnitude < 1e-3,
					"runtime-2: a server-built mesh pet using a key broken on THIS device shows a local Part copy (mesh hidden here, copy welded to its root, same pivot)",
					fmt("copy %s, %d mesh parts shown, %d welded, %d loose", tostring(copy), shown, welded, loose))
				T.check(srvOk:FindFirstChild("ML_PartCopy") == nil, "runtime-2: a server-built mesh pet whose keys work here is left alone")
				if copy and srvBroken.PrimaryPart then
					srvBroken:PivotTo(CFrame.new(40, 12, 40))
					T.check((copy:GetPivot().Position - Vector3.new(40, 12, 40)).Magnitude < 1e-3, "runtime-2: the Part copy follows the server model")
				end
				T.check(MF.Check(srvBroken) == false and #srvBroken:GetChildren() > 0, "runtime-2: checked once (no second copy)")
				local late = serverMesh("P6ServerPetLate", broken, CFrame.new(60, 8, 40))
				Mock.Advance(0.1)
				T.check(late:FindFirstChild("ML_PartCopy") ~= nil, "runtime-2: a server mesh pet streamed in after the failure gets its copy (tag signal)")
				late:Destroy()
				MF.Stop()
			end
			srvBroken:Destroy()
			srvOk:Destroy()
			Mock.PreloadHook = saved
		end
	end)
	-- GraphicsQuality.Apply drives PetFx.SetQuality (Low = the evolved pets' light only, no particles)
	local okG, GQ = pcall(function()
		return require(Mock.GetPath(ROOTS.client .. "/GraphicsQuality"))
	end)
	local Fx = require(sharedModule("PetFx"))
	if okG and type(GQ) == "table" and type(GQ.Apply) == "function" and type(Fx.Quality) == "function" then
		local was = GQ.Effective and GQ.Effective() or "High"
		GQ.Apply("Low")
		local low = Fx.Quality()
		GQ.Apply("High")
		local high = Fx.Quality()
		GQ.Apply(was)
		T.check(low == "Low" and high == "High", "GraphicsQuality.Apply calls PetFx.SetQuality (Low / High)", tostring(low) .. " / " .. tostring(high))
	else
		T.fail("GraphicsQuality / PetFx.Quality not reachable in the client world")
	end
	holder:Destroy()
	if follow then
		LocalPlayer:SetAttribute("EquippedPets", "")
		KC.advance(0.5)
	end
	flushWarn("client_p6pets")
end)
end

_G.P6Pets = { Install = install, Uninstall = uninstall, PetKeys = petKeys, MeshMode = MESH_MODE }

return S
