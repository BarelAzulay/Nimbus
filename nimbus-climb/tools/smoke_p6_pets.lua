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

-- a scenario's own fixture set; in fixture mesh mode the global set stays (it already holds every pet key)
local function withFixtures(keys, fn)
	if MESH_MODE then
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
	withFixtures(need, function()
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
			ML2._Reset()
			ML2._Configure({ Root = root, Ids = { [broken] = 1, pet_dog = 2, wing_feather_R = 3 } })
			ML2.Start()
			Mock.Advance(1)
			local m2 = Pets.Build(D.dog, {})
			T.check(ML2.Status(broken) == "failed" and m2:GetAttribute("ML_Mesh") == nil, "a key that failed to download on THIS device: Build keeps the Part pet here")
			m2:Destroy()
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
