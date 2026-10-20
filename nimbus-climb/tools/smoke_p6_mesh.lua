-- smoke_p6_mesh.lua: the Phase 6 runtime mesh loader (ARCHITECTURE_V3.md "## Phase 6"; docs/phase6/recipe.md 4.8 /
-- 4.9; owner: runtime, wave 1). Loaded by tools/smoke.py in BOTH worlds:
--   p6mesh_noop     (server) the shipped MeshIds holds numbers only and is empty in this wave: Start() on the real
--                   module creates nothing (no ReplicatedStorage.MeshLibrary, no thread, no connection); a fresh copy
--                   with an empty id table does the same; Status "missing", IsReady false, Assemble nil
--   p6mesh_fit      (server) the fit + validation step on fixture assets built from tools/fixtures/mesh/*.lua: yaw 0 /
--                   90 / 180 / 270, scale 100 and 0.01 corrected to the canonical template (manifest Size / centre,
--                   pivot = identity, anchored, no collisions, Massless, Color white, manifest material); PackageLink /
--                   scripts / SurfaceAppearance stripped; a missing part, a duplicated name, a mirrored asset and a
--                   misplaced part are refused; every kit manifest in shared/MeshManifests fits a 180-degree import
--   p6mesh_server   (server) the background loader on a private copy of the module (fixture MeshIds + manifests, the
--                   mock asset store Mock.AssetLoader): <= 4 loads at once, LoadAssetAsync then InsertService:LoadAsset,
--                   retries after 2 / 5 / 12 s, no retry on "not authorized" or on a structure failure, a key with no
--                   manifest never loads, id 0 / string ids ignored; templates under the root with ML_Status / ML_Error /
--                   ML_LoadMs; OnReady + Changed; Assemble (recipe 4.3 names, MK_Key / ML_Key / ML_Part, PB_* rig
--                   attributes, colours from the recipes, attachments) animated by the real PetBuilder.Animate (no NaN,
--                   no new instances, Clone animates); partially ready keys -> nil (the Part build, never a mix); Swap
--                   now / deferred / never; Tag attributes; EvalColor parity with Voxel.Lighten and the recipe ops
--   client_p6mesh   (client) a private copy in client mode over installed fixture templates: PreloadAsync per template,
--                   a Failure marks the key broken on THIS device only (Status failed, Assemble nil, its targets keep
--                   their Parts), RenderFidelity Precise / Automatic, Changed, Dress of targets tagged before and after
--                   Start (Keep parts stay visible, colours from the ML_* look, pivot on the target), a removed template
--                   is not ready any more, an empty id table does nothing
-- Ports the 23 checks of the research prototype (docs/phase6/proto/test_meshlibrary.py) into these four scenarios.
-- Every scenario uses its own copy of the module and its own root folder and restores Mock.AssetLoader /
-- Mock.PreloadHook, so nothing leaks into the game or into another scenario. Plain Lua 5.1; deterministic.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local fmt = string.format
local abs = math.abs

local FIXTURES = { "pet_dog", "wing_feather_L", "wing_feather_R", "acc_crown", "prop_arch" }

-- manifest fields come Capitalised from the kit (Name / Center / Size ...) and lower-case in hand-made fixtures
local function pf(t, k)
	local v = t[k]
	if v == nil then
		v = t[string.upper(string.sub(k, 1, 1)) .. string.sub(k, 2)]
	end
	return v
end

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
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

local fixtureSrc = {}
local function fixtureSource(name)
	if fixtureSrc[name] == nil then
		fixtureSrc[name] = readFile("tools/fixtures/mesh/" .. name .. ".lua") or false
	end
	return fixtureSrc[name] or nil
end

local function manifestOf(name)
	local src = fixtureSource(name)
	if not src then
		return nil
	end
	local fn = loadstring(src)
	return fn and fn() or nil
end

local function sharedModule(name)
	return Mock.GetPath(ROOTS.shared .. "/" .. name)
end

local function near(a, b, eps)
	return (a - b).Magnitude <= (eps or 1e-3)
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A private copy of MeshLibrary next to its own MeshIds + MeshManifests; templates go to `root`.
--   ids: the id table (written into the copy's MeshIds module as numbers / junk on purpose)
--   manifests: { key = fixtureName }
local testCounter = 0
local function newLib(ids, manifests)
	testCounter = testCounter + 1
	local box = Instance.new("Folder")
	box.Name = "P6MeshTest" .. testCounter
	local lib = sharedModule("MeshLibrary"):Clone()
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
		local v = ids[k]
		lines[#lines + 1] = fmt("\t[%q] = %s,", k, type(v) == "string" and fmt("%q", v) or tostring(v))
	end
	lines[#lines + 1] = "}"
	idsMod.Source = table.concat(lines, "\n")
	idsMod.Parent = box
	local mans = Instance.new("Folder")
	mans.Name = "MeshManifests"
	mans.Parent = box
	for key, fixture in pairs(manifests or {}) do
		local m = Instance.new("ModuleScript")
		m.Name = key
		m.Source = (typeof(fixture) == "Instance" and fixture.Source) or fixtureSource(fixture) or "return nil"
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

-- What LoadAsset returns for a fixture key: a wrapper Model holding the uploaded Model with one MeshPart per
-- manifest part, placed with a yaw / scale / mirror / offset (what an import with wrong axes would give).
-- [fix-meshlib W3b, review3 runtime-0] opts.Mode says how the yaw reaches each part:
--   "rotated" the part CFrame carries the yaw, Size = the manifest size (geometry unrotated in the part's frame)
--   "baked"   the yaw is BAKED into the vertices (what blender/kit/nvox/manifest.py says Roblox's importer does: every
--             MeshPart recentred on its bounds, identity rotation): identity part rotation, the centre rotated, the
--             AABB size (X / Z swapped at 90 / 270)
--   nil       mixed: odd parts baked, even parts rotated (so every yawed fixture exercises a non-identity template
--             rotation; the old all-"rotated" fixture made it the identity and passed even when Assemble dropped it)
-- Each part records FX_GeoYaw: the yaw of its geometry inside its own frame (baked: the yaw, rotated: 0), so a test can
-- tell where the mesh's own +X / +Z end up (geoErr).
local function fakeAsset(key, opts)
	opts = opts or {}
	local man = opts.Manifest or manifestOf(opts.Fixture or key)
	local wrapper = Instance.new("Model")
	wrapper.Name = "LoadAssetWrapper"
	local inner = Instance.new("Model")
	inner.Name = "NC " .. key
	inner.Parent = wrapper
	local yaw = CFrame.Angles(0, math.rad(opts.Yaw or 0), 0)
	local scale = opts.Scale or 1
	local offset = opts.Offset or Vector3.new(3, 1, -2)
	for i, p in ipairs(man.Parts) do
		if pf(p, "name") ~= opts.Missing then
			local c = v3(pf(p, "center"))
			if opts.Mirror then
				c = Vector3.new(-c.X, c.Y, c.Z)
			end
			if opts.Jitter and i == 1 then
				c = c + Vector3.new(0, 1.5, 0)
			end
			local part = Instance.new("MeshPart")
			part.Name = pf(p, "name")
			local baked = opts.Mode == "baked" or (opts.Mode == nil and i % 2 == 1)
			if baked then
				local sz = yaw:VectorToWorldSpace(v3(pf(p, "size")) * scale)
				part.Size = Vector3.new(abs(sz.X), abs(sz.Y), abs(sz.Z))
				part.CFrame = CFrame.new(offset + yaw:VectorToWorldSpace(c * scale))
				part:SetAttribute("FX_GeoYaw", opts.Yaw or 0)
			else
				part.Size = v3(pf(p, "size")) * scale
				part.CFrame = CFrame.new(offset) * yaw * CFrame.new(c * scale)
				part:SetAttribute("FX_GeoYaw", 0)
			end
			part.Anchored = false
			part.CanCollide = true
			part.Color = Color3.fromRGB(163, 162, 165)
			part.Parent = inner
			if i == 1 then
				local att = Instance.new("Attachment")
				att.Name = "Head_Att"
				att.Parent = part
			end
		end
	end
	if opts.Duplicate then
		local first = inner:FindFirstChildWhichIsA("MeshPart")
		first:Clone().Parent = inner
	end
	if opts.Junk ~= false then
		local link = Mock.MakeInstance("PackageLink")
		link.Parent = inner
		local s = Instance.new("Script")
		s.Parent = inner
		local sa = Instance.new("SurfaceAppearance")
		sa.Parent = inner:FindFirstChildWhichIsA("MeshPart")
	end
	return wrapper
end

local function installTemplate(ML, root, key, opts)
	local tpl = ML._Fit(key, fakeAsset(key, opts))
	if tpl then
		tpl:SetAttribute("ML_Status", "ready")
		tpl.Parent = root
	end
	return tpl
end

-- the world AABB size of a box (cf, size)
local function extentOf(cf, size)
	local r, u, b = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(abs(r.X) * size.X + abs(u.X) * size.Y + abs(b.X) * size.Z, abs(r.Y) * size.X + abs(u.Y) * size.Y + abs(b.Y) * size.Z,
		abs(r.Z) * size.X + abs(u.Z) * size.Y + abs(b.Z) * size.Z)
end

-- how far the part's GEOMETRY (its frame * FX_GeoYaw) is from the world rotation `want` (identity by default)
local function geoErr(part, want)
	local g = part.CFrame * CFrame.Angles(0, math.rad(part:GetAttribute("FX_GeoYaw") or 0), 0)
	local w = want or CFrame.new()
	return math.max((g.RightVector - w.RightVector).Magnitude, (g.LookVector - w.LookVector).Magnitude, (g.UpVector - w.UpVector).Magnitude)
end

local function canonicalOk(ML, key, tpl, manOverride)
	local man = manOverride or manifestOf(key)
	local worst, flags, junk = 0, true, false
	for _, p in ipairs(man.Parts) do
		local part = tpl and tpl:FindFirstChild(pf(p, "name"))
		if not part then
			return false, "no part " .. tostring(pf(p, "name"))
		end
		worst = math.max(worst, (part.Position - v3(pf(p, "center"))).Magnitude)
		-- [fix-meshlib W3b] the template part may be rotated (a baked yaw): its WORLD box is the manifest size and its
		-- geometry faces the manifest's axes
		worst = math.max(worst, (extentOf(part.CFrame, part.Size) - v3(pf(p, "size"))).Magnitude)
		worst = math.max(worst, geoErr(part))
		if not (part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch and part.Massless and part.Color == Color3.new(1, 1, 1)) then
			flags = false
		end
	end
	for _, d in ipairs(tpl:GetDescendants()) do
		if d:IsA("PackageLink") or d:IsA("Script") or d:IsA("SurfaceAppearance") then
			junk = true
		end
	end
	local ok = worst < 2e-3 and flags and not junk and near(tpl.WorldPivot.Position, Vector3.new(0, 0, 0))
	return ok, fmt("worst %.4f flags %s junk %s", worst, tostring(flags), tostring(junk))
end

-- the loader's own expected warn() lines ("[MeshLibrary] ... keeps the Part build") are part of these scenarios:
-- turned into prints so the world's flushWarnings only reports foreign warnings
local function flushWarn(world, ctx, from)
	for i = (from or 0) + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and string.find(o.text, "[MeshLibrary]", 1, true) then
			o.kind = "print"
		end
	end
	local K = world == "server" and _G.K or _G.KC
	if K and K.flushWarnings then
		K.flushWarnings(ctx)
	end
	if K and K.flushErrors then
		K.flushErrors(ctx)
	end
end

----------------------------------------------------------------------------------------------------------------------
-- server: empty ids = today's game
----------------------------------------------------------------------------------------------------------------------
if IS_SERVER then
S.p6mesh_noop = guarded("p6mesh_noop", function()
	local out0 = #Mock.Output
	-- the shipped id table: numbers only, empty in this wave
	local idsInst = sharedModule("MeshIds")
	local okIds, shipped = pcall(require, idsInst)
	local onlyNumbers = okIds and type(shipped) == "table"
	if onlyNumbers then
		for k, v in pairs(shipped) do
			if type(k) ~= "string" or type(v) ~= "number" then
				onlyNumbers = false
			end
		end
	end
	T.check(onlyNumbers, "shared/MeshIds is a table of [string] = number")
	local hadFolder = RS:FindFirstChild("MeshLibrary") ~= nil
	local conns0 = Mock.LiveConnections()
	local tasks0 = Mock.PendingTasks and Mock.PendingTasks() or 0
	local real = require(sharedModule("MeshLibrary"))
	if next(shipped or {}) == nil then
		real.Start()
		T.check(RS:FindFirstChild("MeshLibrary") == nil or hadFolder, "empty MeshIds: Start() creates no ReplicatedStorage.MeshLibrary")
		T.check(Mock.LiveConnections() == conns0, "empty MeshIds: Start() connects nothing", conns0 .. " -> " .. Mock.LiveConnections())
		T.check((Mock.PendingTasks and Mock.PendingTasks() or 0) <= tasks0, "empty MeshIds: Start() spawns no thread")
		T.check(real.Status("pet_dog") == "missing" and not real.IsReady("pet_dog"), "empty MeshIds: every key is 'missing' and not ready")
		T.check(real.Assemble("pet_dog", {}) == nil, "empty MeshIds: Assemble returns nil (the caller builds Parts)")
		-- [runtime-pets, W2] the cheap gates PetBuilder polls
		T.check(type(real.Active) == "function" and real.Active() == false, "empty MeshIds: Active() is false (PetBuilder skips every key lookup)")
		T.check(type(real.Version) == "function" and type(real.Version()) == "number", "Version() is a number (bumped when keys become usable / unusable)")
	else
		T.info("shared/MeshIds has ids", "the real-module no-op check is skipped (uploads exist)")
	end
	-- LEAD REQUEST (runtime W1): Main.server.lua / Main.client.lua are lead-owned; both must call MeshLibrary.Start()
	-- (a no-op while MeshIds is empty). Fails until the two lines from the W1 runtime report are in.
	local mainS = readFile("src/server/Main.server.lua") or ""
	local mainC = readFile("src/client/Main.client.lua") or ""
	T.check(string.find(mainS, "MeshLibrary", 1, true) ~= nil and string.find(mainS, ".Start()", 1, true) ~= nil,
		"LEAD REQUEST: src/server/Main.server.lua starts MeshLibrary (after line 21: pcall(require, Shared.MeshLibrary) -> .Start())")
	T.check(string.find(mainC, "MeshLibrary", 1, true) ~= nil,
		"LEAD REQUEST: src/client/Main.client.lua starts MeshLibrary (after `local client = script.Parent`)")
	-- a private copy with an empty table and with junk only (0, a string, a negative id)
	local ML, root, box = newLib({ zero = 0, str = "123", neg = -5, frac = 1.5 }, { pet_dog = "pet_dog" })
	ML.Start()
	Mock.Advance(1)
	T.check(#root:GetChildren() == 0, "ids 0 / string / negative / fractional are ignored: nothing loads")
	T.check(ML.Status("zero") == "missing" and ML.Status("str") == "missing" and ML.Status("pet_dog") == "missing", "...and those keys stay 'missing'")
	ML._Reset()
	box:Destroy()
	flushWarn("server", "p6mesh_noop", out0)
end)

----------------------------------------------------------------------------------------------------------------------
-- server: fit + validate
----------------------------------------------------------------------------------------------------------------------
S.p6mesh_fit = guarded("p6mesh_fit", function()
	local out0 = #Mock.Output
	local ML, _, box = newLib({}, { pet_dog = "pet_dog", wing_feather_L = "wing_feather_L", prop_arch = "prop_arch", acc_crown = "acc_crown" })
	for _, case in ipairs({
		{ "pet_dog", { Yaw = 0 } }, { "pet_dog", { Yaw = 180 } }, { "pet_dog", { Yaw = 90 } }, { "pet_dog", { Yaw = 270 } },
		{ "wing_feather_L", { Yaw = 180, Scale = 100 } }, { "prop_arch", { Scale = 0.01 } }, { "acc_crown", { Yaw = 90, Scale = 100 } },
	}) do
		local key, opts = case[1], case[2]
		local tpl, why = ML._Fit(key, fakeAsset(key, opts))
		local ok, detail = false, why
		if tpl then
			ok, detail = canonicalOk(ML, key, tpl)
		end
		T.check(ok, fmt("fit %s yaw %d scale %g -> the canonical template (manifest sizes / centres, flags, junk stripped)", key, opts.Yaw or 0, opts.Scale or 1), detail)
		if tpl then
			T.check(tpl:GetAttribute("ML_Yaw") == (opts.Yaw or 0) and tpl:GetAttribute("ML_Scale") == (opts.Scale or 1),
				fmt("fit %s records the solved yaw / scale", key), tostring(tpl:GetAttribute("ML_Yaw")) .. " / " .. tostring(tpl:GetAttribute("ML_Scale")))
			local head = tpl:FindFirstChild("Head_Att", true)
			T.check(head ~= nil and head:IsA("Attachment"), fmt("fit %s keeps the parts' attachments (*_Att)", key))
			tpl:Destroy()
		end
	end
	local function refused(label, key, opts, pattern)
		local tpl, why = ML._Fit(key, fakeAsset(key, opts))
		T.check(tpl == nil and type(why) == "string" and string.find(why, pattern, 1, true) ~= nil, "fit refuses " .. label, tostring(why))
	end
	refused("a missing part", "pet_dog", { Missing = "EyeIris" }, "missing part EyeIris")
	refused("a name used twice (merged / duplicated meshes)", "pet_dog", { Duplicate = true }, "used twice")
	refused("a mirrored asset", "prop_arch", { Mirror = true }, "mirrored")
	refused("a mirrored asset (left / right eye lids swapped) at yaw 90", "pet_dog", { Mirror = true, Yaw = 90 }, "mirrored")
	refused("a misplaced part (over 2% of the bounds)", "prop_arch", { Jitter = true }, "fit error")
	-- every manifest the kit generated so far (src/shared/MeshManifests) fits through the same loader
	local dir = sharedModule("MeshManifests")
	if dir then
		local mods, tested, bad = {}, 0, {}
		for _, m in ipairs(dir:GetChildren()) do
			if m:IsA("ModuleScript") then
				mods[m.Name] = m
			end
		end
		local KL, _, kbox = newLib({}, mods)
		local names = {}
		for name in pairs(mods) do
			names[#names + 1] = name
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local okReq, man = pcall(require, mods[name])
			if okReq and type(man) == "table" and type(pf(man, "parts")) == "table" then
				local tpl, why = KL._Fit(name, fakeAsset(name, { Manifest = man, Yaw = 180, Junk = false }))
				tested = tested + 1
				local okC, detail = false, why
				if tpl then
					okC, detail = canonicalOk(KL, name, tpl, man)
					tpl:Destroy()
				end
				if not okC then
					bad[#bad + 1] = name .. ": " .. tostring(detail)
				end
			else
				bad[#bad + 1] = name .. ": does not load as a manifest"
			end
		end
		T.check(#bad == 0, "every kit manifest in shared/MeshManifests (" .. tested .. ") fits a 180-degree import back to its canonical template", table.concat(bad, "; "))
		KL._Reset()
		kbox:Destroy()
	else
		T.info("no shared/MeshManifests yet", "the kit has not generated manifests")
	end
	local tpl, why = ML._Fit("no_such_key", fakeAsset("pet_dog"))
	T.check(tpl == nil and string.find(tostring(why), "no manifest", 1, true) ~= nil, "fit refuses a key without a manifest", tostring(why))
	ML._Reset()
	box:Destroy()
	-- [fix-meshlib W3b, review3 runtime-0] a yaw BAKED into the vertices (identity part rotation, centre rotated, AABB
	-- swapped): the fit rotates each template part by inv(yaw) with its local size, and Assemble must keep both (it used
	-- to rebuild every part unrotated at the world-axis manifest size: each piece turned 90 / 180 degrees and stretched)
	for _, yawDeg in ipairs({ 90, 180 }) do
		local BL, broot, bbox = newLib({}, { pet_dog = "pet_dog" })
		local btpl, bwhy = BL._Fit("pet_dog", fakeAsset("pet_dog", { Yaw = yawDeg, Mode = "baked", Junk = false }))
		T.check(btpl ~= nil and btpl:GetAttribute("ML_Yaw") == yawDeg, fmt("baked yaw %d: the import fits (ML_Yaw %d)", yawDeg, yawDeg), tostring(bwhy))
		if btpl then
			local okC, detail = canonicalOk(BL, "pet_dog", btpl)
			T.check(okC, fmt("baked yaw %d: the template's world boxes = the manifest sizes, its geometry faces the manifest axes", yawDeg), detail)
			local turned, swapped = 0, 0
			for _, p in ipairs(manifestOf("pet_dog").Parts) do
				local tp = btpl:FindFirstChild(pf(p, "name"))
				if tp and (tp.CFrame.RightVector - Vector3.new(1, 0, 0)).Magnitude > 0.5 then
					turned = turned + 1
				end
				local ms = v3(pf(p, "size"))
				if tp and abs(ms.X - ms.Z) > 0.05 and (tp.Size - ms).Magnitude > 0.05 then
					swapped = swapped + 1
				end
			end
			T.check(turned > 0 and (yawDeg == 180 or swapped > 0), fmt("baked yaw %d: the fixture really turns the template parts (%d turned, %d with a local size != the manifest's)", yawDeg, turned, swapped))
			btpl:SetAttribute("ML_Status", "ready")
			btpl.Parent = broot
			local at = CFrame.new(4, 2, -6) * CFrame.Angles(0, math.rad(30), 0)
			for _, case in ipairs({ { Spec = "pet_dog", Opts = { Scale = 1.5 }, Want = CFrame.new(), Label = "rooted, scale 1.5" },
				{ Spec = { Name = "ML_Mesh", Root = false, Parts = { { Key = "pet_dog" } } }, Opts = { At = at }, Want = at, Label = "rootless At (Dress)" } }) do
				local m = BL.Assemble(case.Spec, {}, case.Opts)
				local sc = case.Opts.Scale or 1
				local worstRot, worstSize, worstGeo, worstBox, worstPos, n = 0, 0, 0, 0, 0, 0
				for _, d in ipairs(m and m:GetDescendants() or {}) do
					local mp = d:IsA("BasePart") and d:GetAttribute("ML_Part")
					local tp = mp and btpl:FindFirstChild(mp)
					if tp then
						n = n + 1
						local want = case.Want * (tp.CFrame - tp.CFrame.Position)
						worstRot = math.max(worstRot, (d.CFrame.RightVector - want.RightVector).Magnitude, (d.CFrame.LookVector - want.LookVector).Magnitude)
						worstSize = math.max(worstSize, (d.Size - tp.Size * sc).Magnitude)
						worstGeo = math.max(worstGeo, geoErr(d, case.Want))
						local mpart = nil
						for _, p in ipairs(manifestOf("pet_dog").Parts) do
							if pf(p, "name") == mp then
								mpart = p
							end
						end
						if mpart and case.Want == CFrame.new() then
							worstBox = math.max(worstBox, (extentOf(d.CFrame, d.Size) - v3(pf(mpart, "size")) * sc).Magnitude)
						end
						if mpart then
							worstPos = math.max(worstPos, (d.Position - case.Want:PointToWorldSpace(v3(pf(mpart, "center")) * sc)).Magnitude)
						end
					end
				end
				T.check(m ~= nil and n == #manifestOf("pet_dog").Parts and worstRot < 1e-3 and worstSize < 1e-3,
					fmt("baked yaw %d, %s: Assemble keeps each template part's rotation and local size (x scale)", yawDeg, case.Label),
					fmt("%d parts, rotation off %.4f, size off %.4f", n, worstRot, worstSize))
				T.check(m ~= nil and worstGeo < 1e-3 and worstBox < 1e-3 and worstPos < 1e-3,
					fmt("baked yaw %d, %s: every assembled piece faces the manifest axes at its manifest centre / box", yawDeg, case.Label),
					fmt("geometry off %.4f, box off %.4f, centre off %.4f", worstGeo, worstBox, worstPos))
				if m then
					m:Destroy()
				end
			end
		end
		BL._Reset()
		bbox:Destroy()
	end
	flushWarn("server", "p6mesh_fit", out0)
end)

----------------------------------------------------------------------------------------------------------------------
-- server: background loading, Assemble, Swap, Tag, EvalColor
----------------------------------------------------------------------------------------------------------------------
end -- IS_SERVER (p6mesh_noop / p6mesh_fit)

local LOOK = { Primary = Color3.fromRGB(190, 154, 114), Secondary = Color3.fromRGB(238, 222, 196), Eye = Color3.fromRGB(50, 36, 32), WingColor = Color3.fromRGB(226, 208, 182) }

local function petSpec(withCrown)
	local parts = {
		{ Key = "pet_dog" },
		{ Key = "wing_feather_L", At = "WingL" },
		{ Key = "wing_feather_R", At = "WingR" },
	}
	if withCrown then
		parts[#parts + 1] = { Key = "acc_crown", At = "Hat" }
	end
	return { Name = "Pet_pebble_pup", Parts = parts, Attributes = { PetId = "pebble_pup", PB_Seed = 4242, PB_Detail = "High" } }
end

local function checkAssembled(ML, model, scale, label)
	local man = manifestOf("pet_dog")
	local names = {}
	local animated, lids, lidHidden, mk, mlTags, badFlags = 0, 0, true, true, true, 0
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			names[d.Name] = d
			if d.Name ~= "Body" then
				if not d:GetAttribute("ML_Key") or not d:GetAttribute("ML_Part") then
					mlTags = false
				end
				if not d:GetAttribute("MK_Key") then
					mk = false
				end
			end
			if d:GetAttribute("PB_G") then
				animated = animated + 1
				if type(d:GetAttribute("PB_Base")) ~= "string" then
					animated = -1e9
				end
			end
			if string.sub(d.Name, 1, 6) == "EyeLid" then
				lids = lids + 1
				if d.Transparency ~= 1 or type(d:GetAttribute("PB_T0")) ~= "number" then
					lidHidden = false
				end
			end
			if d.Anchored ~= true or d.CanCollide or d.CanQuery or d.CanTouch then
				badFlags = badFlags + 1
			end
		end
	end
	local root = names.Body
	T.check(root ~= nil and model.PrimaryPart == root and root.Transparency == 1 and near(root.Size, Vector3.new(0.9, 1.1, 0.9) * scale),
		label .. ": the invisible Body root is the PrimaryPart (0.9 x 1.1 x 0.9 x scale)")
	local want = { "Fur", "FurLight", "Belly", "EyeIris", "EyePupil", "EyeShine", "EyeGlint", "Muzzle", "Nose", "Tail", "Tail2", "WingL", "WingL7", "WingR", "WingR7", "EyeLid", "EyeLid4" }
	local missing = {}
	for _, n in ipairs(want) do
		if not names[n] then
			missing[#missing + 1] = n
		end
	end
	T.check(#missing == 0, label .. ": recipe 4.3 names (palette keys for the body, group names for Tail / WingL / WingR / EyeLid)", table.concat(missing, ", "))
	T.check(mk and mlTags, label .. ": every mesh part has MK_Key (palette key), ML_Key (asset) and ML_Part (manifest name)")
	T.check(names.Tail and names.Tail:GetAttribute("MK_Key") ~= nil and names.WingL and names.WingL:GetAttribute("MK_Key") ~= nil, label .. ": group parts carry their palette key")
	T.check(animated > 0 and lids == 4 and lidHidden, label .. ": PB_G / PB_Base on animated parts, lids hidden with PB_T0", animated .. " animated, " .. lids .. " lids")
	local rig = model:GetAttribute("PB_Rig") or ""
	T.check(string.find(rig, "Tail:tail:", 1, true) ~= nil and string.find(rig, "WingL:wing:1:", 1, true) ~= nil and string.find(rig, "WingR:wing:-1:", 1, true) ~= nil,
		label .. ": PB_Rig holds the Tail and both wing hinges", rig)
	T.check(model:GetAttribute("PB_Scale") == scale and model:GetAttribute("PetId") == "pebble_pup" and model:GetAttribute("PB_Seed") == 4242, label .. ": PB_Scale + the spec's attributes")
	T.check(badFlags == 0, label .. ": every part anchored with no collisions / touch / query", badFlags .. " bad")
	-- colours from the recipes
	local furRec, irisRec, furC, furS = nil, nil, nil, nil
	for _, p in ipairs(man.Parts) do
		if pf(p, "name") == "Fur" then
			furRec, furC, furS = pf(p, "color"), v3(pf(p, "center")) * scale, v3(pf(p, "size")) * scale
		elseif pf(p, "name") == "EyeIris" then
			irisRec = pf(p, "color")
		end
	end
	T.check(names.Fur and names.Fur.Color == ML.EvalColor(furRec, LOOK) and names.Fur.Color == LOOK.Primary, label .. ": Fur = the Look's Primary")
	T.check(names.EyeIris and names.EyeIris.Color == ML.EvalColor(irisRec, LOOK), label .. ": EyeIris = cuteIris(Eye)")
	-- placement: Fur at its manifest centre x scale, wings at the species' attachments
	T.check(names.Fur and near(names.Fur.Position, furC) and near(extentOf(names.Fur.CFrame, names.Fur.Size), furS), label .. ": parts placed at manifest centre / size x scale")
	local wingAt = pf(man.Attachments.WingL, "pos")
	local hingeRig = string.match(rig, "WingL:wing:1:[^=]*=([^;]+)")
	local hx = hingeRig and tonumber(string.match(hingeRig, "^([^,]+)"))
	T.check(hx ~= nil and abs(hx - wingAt[1] * scale) < 1e-3, label .. ": the left wing hinges on the species' WingL attachment", tostring(hingeRig))
	return names
end

if IS_SERVER then
S.p6mesh_server = guarded("p6mesh_server", function()
	local out0 = #Mock.Output
	local manifests = { pet_dog = "pet_dog", wing_feather_L = "wing_feather_L", wing_feather_R = "wing_feather_R", acc_crown = "acc_crown", prop_arch = "prop_arch", pet_dog_low = "pet_dog" }
	local ids = { pet_dog = 111, wing_feather_L = 222, acc_crown = 333, prop_arch = 444, pet_dog_low = 555, evo1_nomanifest = 666, wing_feather_R = 777, zero = 0 }
	local ML, root, box = newLib(ids, manifests)
	local calls, active, peak = {}, 0, 0
	local function count(id, via)
		calls[id] = calls[id] or { AssetService = 0, InsertService = 0 }
		local k = string.find(via, "AssetService", 1, true) and "AssetService" or "InsertService"
		calls[id][k] = calls[id][k] + 1
		return calls[id][k]
	end
	local savedLoader = Mock.AssetLoader
	Mock.AssetLoader = function(id, via)
		local n = count(id, via)
		active = active + 1
		peak = math.max(peak, active)
		task.wait(0.5)
		active = active - 1
		if id == 111 then
			return fakeAsset("pet_dog", { Yaw = 0 })
		elseif id == 222 then
			if string.find(via, "AssetService", 1, true) then
				error("HTTP 500 (Internal Server Error)")
			end
			if n < 3 then
				error("HTTP 503 (Service Unavailable)")
			end
			return fakeAsset("wing_feather_L", { Yaw = 180 })
		elseif id == 333 then
			return fakeAsset("acc_crown", { Scale = 100, Yaw = 90 })
		elseif id == 444 then
			error("User is not authorized to access Asset.")
		elseif id == 777 then
			return fakeAsset("wing_feather_R", { Yaw = 270 })
		elseif id == 555 then
			return fakeAsset("pet_dog_low", { Fixture = "pet_dog", Missing = "Fur" })
		end
		error("unexpected id " .. tostring(id))
	end
	local ok, err = pcall(function()
		-- before Start nothing is ready: the Part build is used
		T.check(not ML.IsReady("pet_dog") and ML.Assemble(petSpec(true), LOOK) == nil, "before Start: IsReady false, Assemble nil (Part build)")
		local readyFired, changed = {}, {}
		ML.OnReady("pet_dog", function(k)
			readyFired[k] = (readyFired[k] or 0) + 1
		end)
		local conn = ML.Changed:Connect(function(k)
			changed[k] = (changed[k] or 0) + 1
		end)
		-- a server-built Part model waiting for its keys (Swap deferred)
		local holder = Instance.new("Folder")
		holder.Name = "P6MeshSwap"
		holder.Parent = workspace
		local old = Instance.new("Model")
		old.Name = "PetSlot1"
		local op = Instance.new("Part")
		op.Name = "Body"
		op.CFrame = CFrame.new(10, 5, 0)
		op.Parent = old
		old.PrimaryPart = op
		old:SetAttribute("PetParts", 12)
		old:SetAttribute("Owner", "Ann")
		old.Parent = holder
		ML.Swap(old, function()
			return ML.Assemble(petSpec(true), LOOK)
		end, { "pet_dog", "wing_feather_L", "wing_feather_R", "acc_crown" })
		local never = old:Clone()
		never.Name = "NeverSwapped"
		never.Parent = holder
		ML.Swap(never, function()
			return ML.Assemble("prop_arch", LOOK)
		end, { "prop_arch" })

		ML.Start()
		T.check(ML.Status("pet_dog") == "loading" and root:FindFirstChild("pet_dog") ~= nil, "while LoadAsset yields: Status 'loading' and a replicated holder")
		Mock.Advance(1)
		T.check(peak <= 4 and peak >= 2, "at most 4 loads at once (" .. peak .. ")")
		Mock.Advance(30)
		local tpl = root:FindFirstChild("pet_dog")
		T.check(tpl and tpl:GetAttribute("ML_Status") == "ready" and type(tpl:GetAttribute("ML_LoadMs")) == "number" and tpl:GetAttribute("ML_AssetId") == 111,
			"pet_dog: template under the root with ML_Status ready, ML_LoadMs, ML_AssetId")
		T.check(tpl and canonicalOk(ML, "pet_dog", tpl), "pet_dog: the template is canonical (unwrapped, anchored, no collisions, white, PackageLink / scripts stripped)")
		T.check(readyFired.pet_dog == 1 and (changed.pet_dog or 0) >= 1, "OnReady fired once, Changed fired")
		T.check(ML.Status("wing_feather_L") == "ready" and calls[222].InsertService == 3 and calls[222].AssetService == 3,
			"wing_feather_L: LoadAssetAsync then InsertService:LoadAsset, retried after 2 / 5 s until it worked", calls[222] and (calls[222].AssetService .. "/" .. calls[222].InsertService))
		T.check(ML.Status("acc_crown") == "ready" and root.acc_crown:GetAttribute("ML_Scale") == 100 and root.acc_crown:GetAttribute("ML_Yaw") == 90,
			"acc_crown: a 100x / 90-degree import is fitted at load")
		local broken = root:FindFirstChild("prop_arch")
		T.check(ML.Status("prop_arch") == "failed" and calls[444].AssetService == 1 and broken and broken:GetAttribute("ML_Status") == "failed"
			and string.find(tostring(broken:GetAttribute("ML_Error")), "not authorized", 1, true) ~= nil,
			"prop_arch: 'not authorized' is permanent (one call, no retry), the holder records ML_Error")
		T.check(ML.Status("pet_dog_low") == "failed" and calls[555].AssetService == 1 and string.find(tostring(root.pet_dog_low:GetAttribute("ML_Error")), "missing part Fur", 1, true) ~= nil,
			"pet_dog_low: a structure failure (missing part) is not retried")
		T.check(ML.Status("evo1_nomanifest") == "failed" and calls[666] == nil, "a key without a manifest never calls LoadAsset")
		T.check(ML.Status("zero") == "missing" and root:FindFirstChild("zero") == nil, "id 0 is never loaded")
		T.check(ML.IsReady("pet_dog", "wing_feather_L") and ML.IsReady({ "pet_dog", "acc_crown" }) and not ML.IsReady("pet_dog", "prop_arch"), "IsReady takes several keys / a list; one failed key = not ready")

		-- Assemble
		local model = ML.Assemble(petSpec(true), LOOK, { Scale = 1.2 })
		T.check(model ~= nil, "Assemble builds the mesh pet when every key is ready")
		if model then
			local names = checkAssembled(ML, model, 1.2, "Assemble")
			local hat = v3(pf(manifestOf("pet_dog").Attachments.Hat, "pos"))
			local goldC = nil
			for _, p in ipairs(manifestOf("acc_crown").Parts) do
				if pf(p, "name") == "Gold" then
					goldC = v3(pf(p, "center"))
				end
			end
			T.check(names.Gold and goldC and near(names.Gold.Position, (hat + goldC) * 1.2), "accessory: placed at the species' Hat attachment x scale",
				names.Gold and (tostring(names.Gold.Position) .. " vs " .. tostring((hat + (goldC or Vector3.new())) * 1.2)))
			-- the real PetBuilder.Animate drives the mesh rig
			local PB = require(sharedModule("PetBuilder"))
			local count0 = #model:GetDescendants()
			local wl = names.WingL
			local c0 = wl.CFrame
			local nan, moved = false, false
			for i = 1, 40 do
				PB.Animate(model, i / 30, { Flap = 1 })
				for _, d in ipairs(model:GetChildren()) do
					if d:IsA("BasePart") then
						local p = d.Position
						if not (finite(p.X) and finite(p.Y) and finite(p.Z)) then
							nan = true
						end
					end
				end
				if not near(wl.CFrame.Position, c0.Position, 1e-4) or (wl.CFrame.LookVector - c0.LookVector).Magnitude > 1e-4 then
					moved = true
				end
			end
			T.check(not nan and moved and #model:GetDescendants() == count0, "PetBuilder.Animate flaps the mesh wings: no NaN, no new instances")
			local clone = model:Clone()
			local cw = clone:FindFirstChild("WingL")
			local cc0 = cw and cw.CFrame
			for i = 1, 20 do
				PB.Animate(clone, 2 + i / 30, { Flap = 1 })
			end
			T.check(cw and (cw.CFrame.LookVector - cc0.LookVector).Magnitude > 1e-4, "a Clone of the mesh pet animates (rig rebuilt from attributes)")
			clone:Destroy()
			model:Destroy()
		end
		-- partial readiness: never a mix
		T.check(ML.Assemble({ Parts = { { Key = "pet_dog" }, { Key = "prop_arch" } } }, LOOK) == nil, "a partially ready set returns nil (the whole Part build)")
		T.check(ML.Assemble("prop_arch", LOOK) == nil and ML.Assemble({ Parts = {} }, LOOK) == nil and ML.Assemble(nil, LOOK) == nil, "failed key / empty spec / junk -> nil")
		local single = ML.Assemble("acc_crown", { Secondary = Color3.new(0, 0, 1) })
		local goldAt = nil
		for _, p in ipairs(manifestOf("acc_crown").Parts) do
			if pf(p, "name") == "Gold" then
				goldAt = v3(pf(p, "center"))
			end
		end
		T.check(single ~= nil and single.PrimaryPart == nil and single:FindFirstChild("Gold") ~= nil and near(single.Gold.Position, goldAt), "Assemble(key) = a rootless model, parts at their manifest centres (pivot identity)")

		-- Swap
		local swapped = holder:FindFirstChild("PetSlot1")
		T.check(swapped ~= nil and swapped ~= old and swapped:GetAttribute("ML_Mesh") == true and swapped:GetAttribute("Owner") == "Ann" and swapped:GetAttribute("PetParts") == 12
			and near(swapped:GetPivot().Position, Vector3.new(10, 5, 0)), "Swap (deferred until the keys were ready): same Name / Parent / pivot / attributes, now the mesh")
		T.check(holder:FindFirstChild("NeverSwapped") == never and never:GetAttribute("ML_Mesh") == nil, "Swap waiting on a failed key keeps the Part model")
		local now = ML.Swap(swapped, function()
			return ML.Assemble(petSpec(false), LOOK)
		end)
		T.check(now ~= nil and now.Parent == holder and now:FindFirstChild("Gold") == nil, "Swap without keys rebuilds at once")
		T.check(ML.Swap(now, function()
			error("boom")
		end) == nil and now.Parent == holder, "a failing build keeps the old model")
		-- [fix-runtime W2.5] Swap opts: OnSwapped (callers that hold the model take the new one), Place = false
		local got = {}
		local placed = ML.Swap(now, function()
			local m = ML.Assemble(petSpec(false), LOOK)
			m:PivotTo(CFrame.new(50, 7, 0))
			return m
		end, nil, { Place = false, OnSwapped = function(fresh, old2)
			got.Fresh, got.Old = fresh, old2
		end })
		T.check(placed ~= nil and near(placed:GetPivot().Position, Vector3.new(50, 7, 0)) and got.Fresh == placed and got.Old == now and now.Parent == nil,
			"Swap opts { Place = false, OnSwapped }: the build keeps its own placement, the callback gets (fresh, old)")
		local short = nil
		local again = ML.Swap(placed, function()
			return ML.Assemble(petSpec(false), LOOK)
		end, nil, function(fresh)
			short = fresh
		end)
		T.check(again ~= nil and short == again and near(again:GetPivot().Position, Vector3.new(50, 7, 0)), "Swap opts as a function = OnSwapped (and the default PivotTo the old pivot)")
		local calls = 0
		T.check(ML.Swap(again, function()
			calls = calls + 1
			return ML.Assemble(petSpec(false), LOOK)
		end, { "pet_never_uploaded" }) == nil and ML.Status("pet_never_uploaded") == "missing", "Swap on a key with no id (after Start) returns nil")
		Mock.Advance(1)
		T.check(calls == 0 and again.Parent == holder, "... and never rebuilds (nothing waits on a missing key)")

		-- Tag (server side of dressing)
		local target = Instance.new("Model")
		target.Name = "LobbyArch"
		target.Parent = holder
		ML.Tag(target, "prop_arch", { Primary = Color3.new(1, 0, 0), Secondary = Color3.new(0, 1, 0), Stars = 3, Variant = "Gold" }, { "SignBoard", "PromptAnchor" })
		T.check(target:GetAttribute("ML_DressKey") == "prop_arch" and target:GetAttribute("ML_Keep") == "PromptAnchor,SignBoard" and target:GetAttribute("ML_Primary") == Color3.new(1, 0, 0)
			and target:GetAttribute("ML_Stars") == 3 and target:GetAttribute("ML_Variant") == "Gold" and CollectionService:HasTag(target, "ML_Dress"),
			"Tag: ML_DressKey / ML_Keep / ML_* look attributes + the ML_Dress tag")
		conn:Disconnect()
		holder:Destroy()
	end)
	Mock.AssetLoader = savedLoader
	T.check(ok, "p6mesh_server ran to the end", tostring(err))

	-- EvalColor (blender/kit/nvox/colors.py ops)
	local Voxel = require(sharedModule("Voxel"))
	local worst = 0
	for i = 0, 9 do
		local c = Color3.fromHSV(i / 10, 0.3 + i * 0.05, 0.4 + i * 0.05)
		local a, b = ML.EvalColor({ "shadeLight", { "Primary" } }, { Primary = c }), Voxel.Lighten(c)
		worst = math.max(worst, abs(a.R - b.R), abs(a.G - b.G), abs(a.B - b.B))
	end
	T.check(worst < 1e-6, "EvalColor shadeLight == Voxel.Lighten", fmt("%.2g", worst))
	local p, s = Color3.fromRGB(200, 100, 50), Color3.fromRGB(20, 40, 60)
	local L = { Primary = p, Secondary = s, Eye = { 10, 20, 30 } }
	T.check(ML.EvalColor({ "mix", { "Primary" }, { "Secondary" }, 0.25 }, L) == p:Lerp(s, 0.25), "EvalColor mix = Color3:Lerp")
	T.check(ML.EvalColor({ "lighten", { "Primary" }, 0.3 }, L) == p:Lerp(Color3.new(1, 1, 1), 0.3) and ML.EvalColor({ "darken", { "Primary" }, 0.3 }, L) == p:Lerp(Color3.new(0, 0, 0), 0.3), "EvalColor lighten / darken")
	T.check(ML.EvalColor({ "rgb", 1, 2, 3 }, L) == Color3.fromRGB(1, 2, 3) and ML.EvalColor({ "Eye" }, L) == Color3.fromRGB(10, 20, 30), "EvalColor rgb + a {r,g,b} Look colour")
	T.check(ML.EvalColor({ "ifLum<", { "Secondary" }, 0.3, { "rgb", 255, 0, 0 }, { "rgb", 0, 0, 255 } }, L) == Color3.fromRGB(255, 0, 0)
		and ML.EvalColor({ "ifLum<", { "Primary" }, 0.3, { "rgb", 255, 0, 0 }, { "rgb", 0, 0, 255 } }, L) == Color3.fromRGB(0, 0, 255), "EvalColor ifLum< picks by luminance")
	local h = ML.EvalColor({ "headroom", { "rgb", 87, 174, 255 } }, L)
	T.check(abs(h.R - math.min(1, 87 / 255 / 0.87)) < 1e-6 and h.B == 1, "EvalColor headroom = min(1, c / 0.87)")
	local pupil = ML.EvalColor({ "cutePupil", { "Eye" }, true }, L)
	local _, _, v = pupil:ToHSV()
	T.check(abs(v - 0.2) < 1e-3, "EvalColor cutePupil (glow) has value 0.2")
	T.check(ML.EvalColor({ "bogus" }, L) == Color3.new(1, 1, 1) and ML.EvalColor(nil, nil) == Color3.new(1, 1, 1), "EvalColor: unknown op / junk -> white")
	ML._Reset()
	box:Destroy()
	flushWarn("server", "p6mesh_server", out0)
end)

end -- IS_SERVER

----------------------------------------------------------------------------------------------------------------------
-- client: preload, per-device failure, RenderFidelity, Dress
----------------------------------------------------------------------------------------------------------------------
local function partTarget(parent, name, key, pivot)
	local m = Instance.new("Model")
	m.Name = name
	for _, n in ipairs({ "Stone", "Trim", "SignBoard" }) do
		local p = Instance.new("Part")
		p.Name = n
		p.Anchored = true
		p.CFrame = pivot
		p.Parent = m
		local d = Instance.new("Decal")
		d.Parent = p
	end
	m.PrimaryPart = m.Stone
	m:SetAttribute("ML_DressKey", key)
	m:SetAttribute("ML_Keep", "SignBoard")
	m:SetAttribute("ML_Primary", Color3.fromRGB(120, 200, 255))
	m:SetAttribute("ML_Secondary", Color3.fromRGB(255, 240, 200))
	m.Parent = parent
	return m
end

if not IS_SERVER then
S.client_p6mesh = guarded("client_p6mesh", function()
	local out0 = #Mock.Output
	-- empty ids: nothing at all
	local conns0 = Mock.LiveConnections()
	local E, _, ebox = newLib({}, {})
	E.Start()
	T.check(Mock.LiveConnections() == conns0 and E.Status("pet_dog") == "missing", "client, empty MeshIds: Start() connects nothing, keys 'missing'")
	E._Reset()
	ebox:Destroy()

	local ids = { pet_dog = 111, wing_feather_L = 222, wing_feather_R = 223, acc_crown = 333, prop_arch = 444 }
	local ML, root, box = newLib(ids, { pet_dog = "pet_dog", wing_feather_L = "wing_feather_L", wing_feather_R = "wing_feather_R", acc_crown = "acc_crown", prop_arch = "prop_arch" })
	-- what the server replicated: four ready templates (fixture assets run through the same fit)
	for _, key in ipairs(FIXTURES) do
		installTemplate(ML, root, key, { Yaw = 0 })
	end
	local world = Instance.new("Folder")
	world.Name = "P6MeshDress"
	world.Parent = workspace
	local before = partTarget(world, "ArchBefore", "prop_arch", CFrame.new(20, 3, -4))
	CollectionService:AddTag(before, "ML_Dress")
	local onBroken = partTarget(world, "CrownStand", "acc_crown", CFrame.new(0, 3, 9))
	CollectionService:AddTag(onBroken, "ML_Dress")
	local savedHook = Mock.PreloadHook
	local preloaded = {}
	Mock.PreloadHook = function(list, cb)
		task.wait(0.2)
		local name = list[1].Name
		preloaded[#preloaded + 1] = name
		if cb then
			cb("rbxassetid://0", name == "acc_crown" and Enum.AssetFetchStatus.Failure or Enum.AssetFetchStatus.Success)
		end
	end
	local ok, err = pcall(function()
		local changed = {}
		local conn = ML.Changed:Connect(function(k)
			changed[k] = true
		end)
		ML.Start()
		Mock.Advance(0.05)
		T.check(ML.Status("pet_dog") == "loading" and not ML.IsReady("pet_dog"), "client: a replicated template is 'loading' until its mesh data is on this device")
		Mock.Advance(3)
		T.check(#preloaded == 5, "client: PreloadAsync once per template (" .. #preloaded .. ")")
		T.check(ML.IsReady("pet_dog", "wing_feather_L", "wing_feather_R", "prop_arch") and changed.pet_dog and changed.prop_arch, "client: preloaded keys are ready and Changed fired")
		T.check(ML.Status("acc_crown") == "failed" and not ML.IsReady("acc_crown") and ML.Assemble(petSpec(true), LOOK) == nil,
			"client: a failed download marks the key broken on this device; a pet that needs it stays all Parts")
		T.check(ML.Assemble(petSpec(false), LOOK) ~= nil, "client: a pet without the broken key assembles")
		T.check(root.pet_dog.Fur.RenderFidelity == Enum.RenderFidelity.Precise and root.prop_arch.Stone.RenderFidelity == Enum.RenderFidelity.Automatic,
			"client: RenderFidelity set locally (Precise for creatures, Automatic for world props)")
		-- Dress
		local mesh = before:FindFirstChild("ML_Mesh")
		T.check(mesh ~= nil and mesh:FindFirstChild("Stone") ~= nil, "client: a target tagged before Start is dressed")
		T.check(before.Stone.Transparency == 1 and before.Trim.Transparency == 1 and before.SignBoard.Transparency == 0 and before.Stone.Decal.Transparency == 1,
			"client: dressed Parts (and their decals) hidden locally, Keep parts stay visible")
		T.check(mesh and mesh.Stone.Color == Color3.fromRGB(120, 200, 255) and mesh.Trim.Color == Color3.fromRGB(255, 240, 200), "client: the mesh colours come from the ML_* look")
		T.check(mesh and mesh.Glow.Material == Enum.Material.Neon and type(mesh.Glow:GetAttribute("PB_Pulse")) == "number" and mesh.Stone.Material == Enum.Material.SmoothPlastic,
			"client: manifest materials (Neon glow, SmoothPlastic) and PB_Pulse on pulsing parts")
		T.check(mesh and near(mesh.Stone.Position, Vector3.new(20 - 3, 3 + 4, -4)) and mesh.Stone.Transparency == 0, "client: the mesh sits on the target's pivot",
			mesh and (tostring(mesh.Stone.Position) .. " T=" .. mesh.Stone.Transparency .. " pivot " .. tostring(before:GetPivot().Position)))
		T.check(onBroken:FindFirstChild("ML_Mesh") == nil and onBroken.Stone.Transparency == 0, "client: a target whose key failed on this device keeps its Parts")
		local after = partTarget(world, "ArchAfter", "prop_arch", CFrame.new(-8, 2, 0))
		CollectionService:AddTag(after, "ML_Dress")
		Mock.Advance(0.2)
		T.check(after:FindFirstChild("ML_Mesh") ~= nil and after.Stone.Transparency == 1, "client: a target tagged later (streamed in) is dressed through the tag signal")
		ML.Dress(after, "prop_arch")
		Mock.Advance(0.2)
		local meshes = 0
		for _, c in ipairs(after:GetChildren()) do
			if c.Name == "ML_Mesh" then
				meshes = meshes + 1
			end
		end
		T.check(meshes == 1, "client: dressing twice keeps one mesh")
		-- [fix-runtime W2.5] hide-list mode (ML_Hide): only the named parts go transparent, later extras stay
		local hideT = partTarget(world, "ArchHide", "prop_arch", CFrame.new(40, 3, 0))
		hideT:SetAttribute("ML_Keep", "")
		hideT:SetAttribute("ML_Hide", "Stone")
		ML.Dress(hideT, "prop_arch")
		Mock.Advance(0.2)
		T.check(hideT:FindFirstChild("ML_Mesh") ~= nil and hideT.Stone.Transparency == 1 and hideT.Trim.Transparency == 0 and hideT.SignBoard.Transparency == 0,
			"client: ML_Hide = 'Stone' hides only Stone (Trim / SignBoard stay)")
		local tagT = Instance.new("Model")
		ML.Tag(tagT, "prop_arch", { Hide = { "Trim", "Stone" } })
		T.check(tagT:GetAttribute("ML_Hide") == "Stone,Trim", "Tag look.Hide -> ML_Hide (sorted csv)")
		-- a dressed target nested in another one: the outer Dress never hides the inner mesh
		local outer = partTarget(world, "Outer", "prop_arch", CFrame.new(60, 3, 0))
		local inner = partTarget(outer, "Inner", "prop_arch", CFrame.new(64, 3, 0))
		ML.Dress(inner, "prop_arch")
		Mock.Advance(0.2)
		ML.Dress(outer, "prop_arch")
		Mock.Advance(0.2)
		local innerMesh = inner:FindFirstChild("ML_Mesh")
		T.check(innerMesh ~= nil and outer:FindFirstChild("ML_Mesh") ~= nil and innerMesh.Stone.Transparency == 0 and inner.Stone.Transparency == 1,
			"client: an outer Dress leaves a nested target's ML_Mesh visible")
		-- ML_Weld on a BasePart target (TokenFx coins): the mesh is unanchored + welded to the moving root
		local coin = Instance.new("Part")
		coin.Name = "Coin"
		coin.Anchored = true
		coin.CFrame = CFrame.new(5, 6, 7)
		local halo = Instance.new("Part")
		halo.Name = "Halo"
		halo.Anchored = true
		halo.CFrame = coin.CFrame
		halo.Parent = coin
		coin:SetAttribute("ML_Keep", "Halo")
		coin:SetAttribute("ML_Weld", true)
		coin.Parent = world
		ML.Dress(coin, "prop_arch")
		Mock.Advance(0.2)
		local cm = coin:FindFirstChild("ML_Mesh")
		local loose, welded = 0, 0
		for _, d in ipairs(cm and cm:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				local w = d:FindFirstChildOfClass("WeldConstraint")
				if d.Anchored then
					loose = loose + 1
				end
				if w and w.Part0 == coin and w.Part1 == d then
					welded = welded + 1
				end
			end
		end
		T.check(cm ~= nil and loose == 0 and welded > 0 and coin.Transparency == 1 and halo.Transparency == 0,
			"client: an ML_Weld Part target is dressed; every mesh part unanchored + WeldConstraint Part0 = the target, Halo kept", fmt("%d anchored, %d welded", loose, welded))
		T.check(cm ~= nil and cm:FindFirstChild("Stone") ~= nil and near(cm.Stone.Position, Vector3.new(5 - 3, 6 + 4, 7)), "client: the Part target's mesh sits on its CFrame")
		-- HomeFx: a mesh-dressed station appears without the Part pop (which would bring the hidden Parts back)
		local KCm = rawget(_G, "KC")
		local HF = KCm and KCm.M and KCm.M.HomeFx
		if not HF then
			pcall(function()
				HF = require(Mock.GetPath(ROOTS.client .. "/Controllers/HomeFx"))
			end)
		end
		if T.check(type(HF) == "table" and type(HF._StartPop) == "function", "HomeFx._StartPop test hook") then
			local st = partTarget(world, "Station_Farm", "prop_arch", CFrame.new(0, 3, 30))
			local t0 = st.Trim.Transparency
			T.check(HF._StartPop(st, nil) == nil and st.Trim.Transparency == t0, "HomeFx.startPop: an ML_DressKey station never pops")
		end
		root.wing_feather_L:Destroy()
		Mock.Advance(0.1)
		T.check(not ML.IsReady("wing_feather_L") and ML.Assemble(petSpec(false), LOOK) == nil, "client: a removed template is not ready any more")
		conn:Disconnect()
	end)
	Mock.PreloadHook = savedHook
	T.check(ok, "client_p6mesh ran to the end", tostring(err))
	ML._Reset()
	world:Destroy()
	box:Destroy()
	flushWarn("client", "client_p6mesh", out0)
end)

end -- not IS_SERVER

return S
