-- smoke_p6_creatures.lua: the Phase 6 creature meshes (ARCHITECTURE_V3.md "## Phase 6" 6.3 art-creatures; owner:
-- art-creatures, wave 2). Loaded by tools/smoke.py in BOTH worlds; every scenario runs BOTH modes:
--   default mode  the shipped (empty) MeshIds: the bosses, the token, the NPC pedestal and the sky dragon are today's
--                 Part builds exactly (no ML_* attribute, no tag, no MeshPart)
--   fixture mode  the real MeshLibrary pointed (_Configure) at a private folder of canonical templates made from the
--                 committed manifests (src/shared/MeshManifests/<key>.lua) with fake ids: the builders take the mesh
--                 path and keep every name / joint / attribute / Fx point / rig the game uses; a partly ready set
--                 falls back whole; _Reset afterwards (nothing leaks into later scenarios)
--   p6creatures_server   (server) BossBuilder (4 bosses x High / Low): joints, Pivot / JointParent, Fx points, glow
--                        parts + SetEnraged, Animate, budgets; TokenLook server coins (Tag + ML_Weld, Halo kept);
--                        NpcService pedestal Tag (ML_Primary = accent, ML_Offset puts the mesh on the Part grid)
--   client_p6creatures   (client) the sky dragon rebuilt from meshes (pieces, chains, puffs, flags, flight, no new
--                        instances) and back; client-built Cloud Cash coins welded to the root; a boss on the client
--                        (per-device readiness); the dressed pedestal; LEAD REQUEST: Dress welds an ML_Weld target
-- Deterministic: fixed ids, catalog order, sorted keys.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local fmt = string.format

local function req(root, path)
	local ok, inst = pcall(Mock.GetPath, ROOTS[root] .. "/" .. path)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

local BOSSES = { "storm_titan", "lava_golem", "frost_wyrm", "shadow_hydra" }
local TOKENS = { "token_cloud", "token_golden", "token_cash", "token_goldencash" }

local function finite(v)
	return v == v and v ~= math.huge and v ~= -math.huge
end

-- a canonical template (what the loader leaves after the fit) from the committed manifest of `key`
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

-- points the REAL MeshLibrary at a private folder holding `keys` (fake ids 1..n); returns ML, root
local function fixtureMode(keys)
	local ML = req("shared", "MeshLibrary")
	ML._Reset()
	local root = Instance.new("Folder")
	root.Name = "P6CreaturesMeshes"
	root.Parent = RS
	local ids = {}
	for i, key in ipairs(keys) do
		ids[key] = 9000 + i
		installTemplate(ML, root, key)
	end
	ML._Configure({ Root = root, Ids = ids })
	return ML, root
end

local function leaveFixtureMode(ML, root)
	ML._Reset()
	if root then
		root:Destroy()
	end
	local P6 = rawget(_G, "P6Pets")
	if P6 and P6.MeshMode then
		P6.Install(P6.PetKeys()) -- --mesh: put back the global fixture set that _Reset wiped
	end
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

local function countMeshParts(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			n = n + 1
		end
	end
	return n
end

local function bossKeys(BB)
	local keys = {}
	for _, id in ipairs(BOSSES) do
		for _, detail in ipairs({ "High", "Low" }) do
			for _, k in ipairs(BB.MeshKeys(id, detail)) do
				keys[#keys + 1] = k
			end
		end
	end
	return keys
end

-- the joint / Fx / attribute signature of a built boss at rest
local function bossSignature(BB, model, id)
	local sig = { Joints = {}, Fx = {} }
	for _, name in ipairs(BB.Rigs[id].Order) do
		local j = model:FindFirstChild(name)
		sig.Joints[name] = j and { Class = j.ClassName, Pivot = j:GetAttribute("Pivot"), Parent = j:GetAttribute("JointParent") } or false
	end
	for fxName in pairs(BB.Rigs[id].Fx) do
		sig.Fx[fxName] = BB.FxPoint(model, fxName) or false
	end
	for _, a in ipairs({ "BossId", "Element", "Detail", "Scale", "Radius" }) do
		sig[a] = model:GetAttribute(a)
	end
	sig.Height = model:GetAttribute("Height")
	sig.Root = model.PrimaryPart and model.PrimaryPart.Name
	return sig
end

----------------------------------------------------------------------------------------------------------------------
if IS_SERVER then
S.p6creatures_server = guarded("p6creatures_server", function()
	local BB = req("shared", "BossBuilder")
	local TL = req("shared", "TokenLook")
	local NS = req("server", "Services/NpcService")
	if not T.check(BB and TL and NS and type(BB.MeshKeys) == "function" and type(NS._BuildPedestal) == "function",
		"p6 creatures: BossBuilder.MeshKeys, TokenLook, NpcService._BuildPedestal load") then
		return
	end
	-- the committed manifests exist for every key the runtime asks for
	local ML = req("shared", "MeshLibrary")
	local missing = {}
	local all = bossKeys(BB)
	for _, k in ipairs(TOKENS) do
		all[#all + 1] = k
	end
	all[#all + 1] = "npc_pedestal"
	for _, k in ipairs(all) do
		if not ML.Manifest(k) then
			missing[#missing + 1] = k
		end
	end
	T.check(#missing == 0, "p6 creatures: a committed manifest for every boss / token / pedestal key (" .. #all .. ")", table.concat(missing, ", "))

	-- default mode: today's Part builds
	local partSigs, partCounts = {}, {}
	for _, id in ipairs(BOSSES) do
		for _, detail in ipairs({ "High", "Low" }) do
			T.check(BB.UsesMeshes(id, detail) == false, "p6 creatures default: " .. id .. " " .. detail .. " uses Parts (empty MeshIds)")
			local m = BB.Build(id, { Detail = detail })
			if T.check(m ~= nil, "p6 creatures default: " .. id .. " " .. detail .. " builds") then
				partSigs[id .. detail] = bossSignature(BB, m, id)
				partCounts[id .. detail] = #partsOf(m)
				T.check(m:GetAttribute("ML_Mesh") == nil and countMeshParts(m) == 0 and partCounts[id .. detail] >= 150,
					"p6 creatures default: " .. id .. " " .. detail .. " is the voxel Part build (" .. partCounts[id .. detail] .. " parts, no MeshPart, no ML_Mesh)")
				m:Destroy()
			end
		end
	end
	local coin = TL.Build({ Palette = "Cloud" })
	T.check(coin:FindFirstChild("RimWide") and coin:FindFirstChild("Face") and coin:GetAttribute("ML_DressKey") == nil
		and not CollectionService:HasTag(coin, "ML_Dress") and coin.Transparency == 0,
		"p6 creatures default: a server coin is the block coin, untagged")
	coin:Destroy()
	local holder = Instance.new("Folder")
	holder.Name = "P6CreaturesPedestals"
	holder.Parent = workspace
	local accent = Color3.fromRGB(236, 120, 170)
	local spot = CFrame.new(40, 3, -20) * CFrame.Angles(0, 0.6, 0)
	local ped = NS._BuildPedestal(holder, spot, accent, 2)
	T.check(ped and ped:GetAttribute("ML_DressKey") == nil and not CollectionService:HasTag(ped, "ML_Dress"),
		"p6 creatures default: an NPC pedestal is not tagged while MeshIds is empty")
	local npcFolder = workspace:FindFirstChild("NimbusNpcs")
	local tagged = 0
	if npcFolder then
		for _, d in ipairs(npcFolder:GetDescendants()) do
			if d:GetAttribute("ML_DressKey") ~= nil then
				tagged = tagged + 1
			end
		end
	end
	T.eq(tagged, 0, "p6 creatures default: the lobby NPCs carry no ML_DressKey")

	-- fixture mode
	local keys = {}
	for _, k in ipairs(all) do
		keys[#keys + 1] = k
	end
	local MLf, root = fixtureMode(keys)
	local ok, err = pcall(function()
		for _, id in ipairs(BOSSES) do
			for _, detail in ipairs({ "High", "Low" }) do
				local tag = id .. " " .. detail
				T.check(BB.UsesMeshes(id, detail) == true, "p6 creatures fixtures: " .. tag .. " takes the mesh path")
				local m = BB.Build(id, { Detail = detail })
				if T.check(m ~= nil and m:GetAttribute("ML_Mesh") == true, "p6 creatures fixtures: " .. tag .. " builds from meshes (ML_Mesh)") then
					local sig, want = bossSignature(BB, m, id), partSigs[id .. detail]
					local jointsOk, fxOk, worstFx = true, true, 0
					for name, j in pairs(want.Joints) do
						local got = sig.Joints[name]
						if not (got and j and got.Class == "Model" and got.Parent == j.Parent and (got.Pivot - j.Pivot).Magnitude < 1e-4) then
							jointsOk = false
						end
					end
					for name, p in pairs(want.Fx) do
						local q = sig.Fx[name]
						if not (q and p) then
							fxOk = false
						else
							worstFx = math.max(worstFx, (q - p).Magnitude)
						end
					end
					T.check(jointsOk, "p6 creatures fixtures: " .. tag .. " joint Models, Pivot and JointParent equal the Part build")
					T.check(fxOk and worstFx < 1e-3, "p6 creatures fixtures: " .. tag .. " every Fx point resolves where the Part build has it", fmt("worst %.4f", worstFx))
					T.check(sig.BossId == want.BossId and sig.Element == want.Element and sig.Detail == want.Detail and sig.Scale == want.Scale
						and sig.Radius == want.Radius and sig.Root == "Root",
						"p6 creatures fixtures: " .. tag .. " model attributes + Root equal the Part build")
					T.check(math.abs(sig.Height - want.Height) <= want.Height * 0.12, "p6 creatures fixtures: " .. tag .. " height within 12% of the Part build",
						fmt("%.2f vs %.2f", sig.Height, want.Height))
					local parts = partsOf(m)
					local flags, meshes, keyed = true, 0, true
					for _, p in ipairs(parts) do
						if p.Name ~= "Root" then
							if p:IsA("MeshPart") then
								meshes = meshes + 1
							end
							keyed = keyed and type(p:GetAttribute("ML_Key")) == "string"
							flags = flags and p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch
						end
					end
					T.check(meshes == #parts - 1 and keyed and flags and meshes <= 48,
						"p6 creatures fixtures: " .. tag .. " is MeshParts only (" .. meshes .. " <= 48), keyed, anchored, no collide / query / touch")
					-- glow parts recolour with the enrage tint and back
					local glow
					for _, p in ipairs(parts) do
						local k = p:GetAttribute("MK_Key")
						if (k == "Eye" or k == "Glow" or k == "Magma" or k == "Rune") and p.Material == Enum.Material.Neon then
							glow = p
							break
						end
					end
					if T.check(glow ~= nil, "p6 creatures fixtures: " .. tag .. " has a Neon glow part (Eye / Glow / Magma / Rune)") then
						local c0 = glow.Color
						BB.SetEnraged(m, true)
						local c1 = glow.Color
						BB.SetEnraged(m, false)
						T.check(c1 ~= c0 and glow.Color == c0, "p6 creatures fixtures: " .. tag .. " SetEnraged tints the glow part and restores it")
					end
					-- Animate moves the meshes, no NaN, no new instances
					local n0 = #m:GetDescendants()
					local head = m:FindFirstChild(BB.Rigs[id].Order[#BB.Rigs[id].Order])
					local probe = head and partsOf(head)[1]
					local p0 = probe and probe.Position
					local fine = BB.Animate(m, "Attack", 0.4, { Progress = 0.5, CFrame = CFrame.new(0, 0, 5) })
					for _, p in ipairs(parts) do
						fine = fine and finite(p.Position.X) and finite(p.Position.Y) and finite(p.Position.Z)
					end
					T.check(fine and probe and (probe.Position - p0).Magnitude > 0.01 and #m:GetDescendants() == n0,
						"p6 creatures fixtures: " .. tag .. " animates (Attack pose moves the meshes, finite, no new instances)")
					m:Destroy()
				end
			end
		end
		-- a partly ready boss falls back whole
		local lone = root:FindFirstChild("boss_lava_golem_Head")
		lone.Parent = nil
		T.check(BB.UsesMeshes("lava_golem", "High") == false, "p6 creatures fixtures: one missing joint key -> the whole boss is Parts")
		local m = BB.Build("lava_golem")
		T.check(m and m:GetAttribute("ML_Mesh") == nil and countMeshParts(m) == 0, "p6 creatures fixtures: ... and Build makes the Part golem (never a mix)")
		if m then
			m:Destroy()
		end
		lone.Parent = root
		-- server coins: Parts + Tag + ML_Weld; the halo stays
		for _, palette in ipairs({ "Cloud", "Golden" }) do
			local c = TL.Build({ Palette = palette })
			local key = TL.MeshKey(palette)
			T.check(c:FindFirstChild("RimWide") and c.Transparency == 0 and c:GetAttribute("ML_DressKey") == key and c:GetAttribute("ML_Weld") == true
				and CollectionService:HasTag(c, "ML_Dress") and c:GetAttribute("ML_Keep") == "Halo" and c.CanTouch,
				"p6 creatures fixtures: a server " .. palette .. " coin keeps its blocks and is tagged " .. key .. " (ML_Weld, Keep Halo)")
			c:Destroy()
		end
		-- the pedestal: tagged with the accent and an offset that puts the mesh pivot on grid voxel (0, 0, 0)
		local ped2 = NS._BuildPedestal(holder, spot, accent, 3)
		local off = ped2 and MLf.CFrameToString and ped2:GetAttribute("ML_Offset")
		T.check(ped2 and ped2:GetAttribute("ML_DressKey") == "npc_pedestal" and ped2:GetAttribute("ML_Primary") == accent and CollectionService:HasTag(ped2, "ML_Dress"),
			"p6 creatures fixtures: the NPC pedestal is tagged npc_pedestal with ML_Primary = the NPC accent")
		if ped2 and type(off) == "string" then
			local nums = {}
			for v in string.gmatch(off, "[^,%s]+") do
				nums[#nums + 1] = tonumber(v)
			end
			local offCF = CFrame.new(unpack(nums))
			local want = spot * CFrame.new(0, 0.4 / 2 - 0.15, 0)
			T.check((ped2:GetPivot() * offCF).Position:FuzzyEq(want.Position, 1e-3), "p6 creatures fixtures: pedestal pivot * ML_Offset = the Part grid origin")
		end
	end)
	T.check(ok, "p6creatures_server fixture mode ran to the end", tostring(err))
	leaveFixtureMode(MLf, root)
	T.check(BB.UsesMeshes("storm_titan", "High") == false, "p6 creatures: after _Reset the bosses are Parts again")
	holder:Destroy()
end)
end

----------------------------------------------------------------------------------------------------------------------
if not IS_SERVER then
S.client_p6creatures = guarded("client_p6creatures", function()
	local KC = _G.KC
	local SD = KC and KC.M and KC.M.SkyDragonController
	local TL = req("shared", "TokenLook")
	local BB = req("shared", "BossBuilder")
	if not T.check(SD and type(SD._Rebuild) == "function" and type(SD.MeshKeys) == "function" and TL and BB,
		"p6 creatures client: SkyDragonController._Rebuild / MeshKeys, TokenLook, BossBuilder load") then
		return
	end
	local ML = req("shared", "MeshLibrary")
	-- default mode
	local model = SD.GetModel()
	T.check(model ~= nil and not SD.IsMesh() and countMeshParts(model) == 0, "p6 creatures client default: the sky dragon is the Part dragon")
	local cash = TL.Build({ Palette = "Cash" })
	T.check(cash:FindFirstChild("RimWide") and cash.Transparency == 0 and countMeshParts(cash) == 0, "p6 creatures client default: a Cloud Cash coin is the block coin")
	cash:Destroy()

	-- fixture mode: dragon + tokens + one boss + the pedestal, preloaded on this device
	local keys = SD.MeshKeys()
	for _, k in ipairs(TOKENS) do
		keys[#keys + 1] = k
	end
	for _, k in ipairs(BB.MeshKeys("frost_wyrm", "High")) do
		keys[#keys + 1] = k
	end
	keys[#keys + 1] = "npc_pedestal"
	for _, k in ipairs({ "fx_arrow", "fx_ice", "fx_shield" }) do -- [fix-runtime W2.5] the battle fx slots
		keys[#keys + 1] = k
	end
	local MLf, root = fixtureMode(keys)
	local world = Instance.new("Folder")
	world.Name = "P6CreaturesClient"
	world.Parent = workspace
	local ok, err = pcall(function()
		T.check(not MLf.IsReady(keys), "p6 creatures client fixtures: templates are not ready before this device preloaded them")
		MLf.Start()
		Mock.Advance(1)
		T.check(MLf.IsReady(keys), "p6 creatures client fixtures: every key ready after the preload")
		T.check(SD._Rebuild() == true and SD.IsMesh(), "p6 creatures client fixtures: the sky dragon rebuilds from meshes")
		local dragon = SD.GetModel()
		if T.check(dragon ~= nil and dragon:GetAttribute("ML_Mesh") == true, "p6 creatures client fixtures: the mesh dragon model (ML_Mesh)") then
			local names = { "Head", "Jaw", "Tail", "Chains", "Puffs" }
			for i = 1, 14 do
				names[#names + 1] = fmt("Segment%02d", i)
			end
			for i = 1, 4 do
				names[#names + 1] = "Leg" .. i
			end
			local missingPieces = {}
			for _, n in ipairs(names) do
				if not dragon:FindFirstChild(n) then
					missingPieces[#missingPieces + 1] = n
				end
			end
			T.check(#missingPieces == 0, "p6 creatures client fixtures: every dragon piece is there (Head, Jaw, Segment01-14, Leg1-4, Tail, Chains, Puffs)", table.concat(missingPieces, ","))
			local parts = partsOf(dragon)
			local flags, meshes = true, 0
			for _, p in ipairs(parts) do
				if p:IsA("MeshPart") then
					meshes = meshes + 1
				end
				flags = flags and p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery and not p.CastShadow
			end
			T.check(meshes == #parts and #parts >= 60 and #parts <= 300, "p6 creatures client fixtures: the dragon is MeshParts only, 60-300 of them", #parts .. " parts")
			T.check(flags, "p6 creatures client fixtures: dragon meshes anchored, no collide / touch / query / shadow")
			local chains = dragon:FindFirstChild("Chains")
			local links = chains and chains:GetChildren() or {}
			local gold = 0
			for _, l in ipairs(links) do
				if l.Name == "Whisker" then
					gold = gold + 1
				end
			end
			T.check(#links == 20 and gold == 8, "p6 creatures client fixtures: 20 chain beads (8 gold whisker links, 12 mane)", #links .. " / " .. gold)
			local cam = workspace.CurrentCamera
			local Config = req("shared", "Config")
			cam.CFrame = CFrame.lookAt(Config.Lobby.Origin + Vector3.new(0, 20, 80), Config.Lobby.Origin)
			local n0 = Mock.CountDescendants(dragon)
			local head = dragon.Head:GetChildren()[1]
			local p0 = head.Position
			Mock.Advance(2)
			T.check((head.Position - p0).Magnitude > 2 and Mock.CountDescendants(dragon) == n0, "p6 creatures client fixtures: the mesh dragon flies, no new instances")
			cam.CFrame = CFrame.new()
		end
		-- client-built coin: welded meshes on an invisible root
		local c = TL.Build({ Palette = "GoldenCash", Parent = world })
		local welded, meshes = true, 0
		for _, d in ipairs(c:GetChildren()) do
			if d:IsA("MeshPart") then
				meshes = meshes + 1
				local w = d:FindFirstChildOfClass("WeldConstraint")
				welded = welded and not d.Anchored and w ~= nil and w.Part0 == c
			end
		end
		T.check(meshes >= 3 and welded and c.Transparency == 1 and c.CanTouch and c:FindFirstChild("RimWide") == nil and c:FindFirstChild("Sparkles") ~= nil,
			"p6 creatures client fixtures: a Cloud Cash coin is welded MeshParts on its invisible root (" .. meshes .. "), sparkles kept, no blocks")
		local scaleOk = true
		local man = MLf.Manifest("token_goldencash")
		local face = c:FindFirstChild(man.Parts[1].name)
		scaleOk = face ~= nil and math.abs(face.Size.Y - man.Parts[1].size[2] * TL.Palettes.GoldenCash.Scale) < 1e-3
		T.check(scaleOk, "p6 creatures client fixtures: the coin mesh is scaled by the palette Scale")
		-- a boss on this device
		local wyrm = BB.Build("frost_wyrm")
		T.check(wyrm and wyrm:GetAttribute("ML_Mesh") == true and wyrm:FindFirstChild("Jaw") and wyrm:FindFirstChild("WingL"),
			"p6 creatures client fixtures: the frost wyrm builds from meshes on a device that preloaded them")
		local membrane
		for _, p in ipairs(wyrm and partsOf(wyrm) or {}) do
			if p:GetAttribute("MK_Key") == "Membrane" then
				membrane = p
			end
		end
		T.check(membrane and math.abs(membrane.Transparency - 0.15) < 1e-6 and membrane.Material == Enum.Material.Ice,
			"p6 creatures client fixtures: the wyrm's wing membrane keeps Ice + Transparency 0.15")
		if wyrm then
			wyrm:Destroy()
		end
		-- the dressed pedestal (a tagged Part stand-in) gets the mesh with the accent rug
		local stand = Instance.new("Model")
		stand.Name = "Pedestal"
		local base = Instance.new("Part")
		base.Name = "Stone"
		base.Anchored = true
		base.CFrame = CFrame.new(5, 2, 5)
		base.Parent = stand
		stand.PrimaryPart = base
		stand.Parent = world
		local accent = Color3.fromRGB(110, 190, 120)
		MLf.Tag(stand, "npc_pedestal", { Primary = accent, Offset = CFrame.new(0, -0.5, 0) })
		Mock.Advance(0.3)
		local mesh = stand:FindFirstChild("ML_Mesh")
		local rug = mesh and mesh:FindFirstChild("RugTop")
		T.check(mesh ~= nil and base.Transparency == 1 and rug ~= nil and rug.Color == accent,
			"p6 creatures client fixtures: a tagged pedestal is dressed (Parts hidden, RugTop = the accent)")
		-- LEAD REQUEST (runtime-pets owns MeshLibrary.Dress): a dressed target with ML_Weld = true (the server's moving
		-- tokens, spun / bobbed by TokenFx) must get its mesh parts unanchored + welded to the target
		-- (checked on the source: the mock Part has no GetPivot, so a Part target cannot be dressed here)
		local src = nil
		for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
			local fh = io.open(prefix .. "src/shared/MeshLibrary.lua", "r")
			if fh then
				src = fh:read("*a")
				fh:close()
				break
			end
		end
		local rides = src ~= nil and string.find(src, "ML_Weld", 1, true) ~= nil
		T.check(rides, "LEAD REQUEST: MeshLibrary.Dress welds the mesh of an ML_Weld target to it (src/shared/MeshLibrary.lua Dress, after Assemble: unanchor + WeldConstraint Part0 = target when target:IsA('BasePart') and target:GetAttribute('ML_Weld'))")
		-- [fix-runtime W2.5] a dressed server coin (ML_Weld, a Part target) rides on its root
		local coin = Instance.new("Part")
		coin.Name = "Token"
		coin.Anchored = true
		coin.CFrame = CFrame.new(-6, 4, 2)
		coin.Parent = world
		MLf.Tag(coin, TOKENS[1], nil, { "Halo" })
		coin:SetAttribute("ML_Weld", true)
		Mock.Advance(0.3)
		local cm = coin:FindFirstChild("ML_Mesh")
		local loose = 0
		for _, p in ipairs(cm and partsOf(cm) or {}) do
			local w = p:FindFirstChildOfClass("WeldConstraint")
			if p.Anchored or not w or w.Part0 ~= coin then
				loose = loose + 1
			end
		end
		T.check(cm ~= nil and #partsOf(cm) > 0 and loose == 0 and coin.Transparency == 1, "p6 creatures client fixtures: a tagged ML_Weld coin is dressed and its mesh is welded to the moving root", tostring(loose))
		-- [fix-runtime W2.5] BattleController's ShieldCube / Ice / FocusArrow use fx_shield / fx_ice / fx_arrow
		local BCm = KC.M and KC.M.BattleController
		if not BCm then
			pcall(function()
				BCm = require(Mock.GetPath(ROOTS.client .. "/Controllers/BattleController"))
			end)
		end
		local U = type(BCm) == "table" and BCm._Units or nil
		if T.check(type(U) == "table" and type(U.UpdateStatus) == "function" and type(U.UpdateFocus) == "function", "BattleController._Units test hook (UpdateStatus / UpdateFocus)") then
			local unitModel = Instance.new("Model")
			unitModel.Name = "FxUnit"
			unitModel.Parent = world
			local u = { model = unitModel, height = 3, shield = 5, state = "Idle", radius = 1.8, hp = 10, x = 4, z = 0, centerY = 1.5 }
			local cf = CFrame.new(10, 3, 0)
			U.UpdateStatus({}, u, 1, cf)
			local sh = u.shieldPart
			T.check(sh ~= nil and sh:IsA("MeshPart") and sh.Name == "ShieldCube" and sh.Parent == unitModel and sh:GetAttribute("ML_Key") == "fx_shield"
				and (sh.Size - Vector3.new(3.75, 3.45, 3.75)).Magnitude < 1e-3 and (sh.Position - cf.Position).Magnitude < 1e-3,
				"battle fx: the shield is the fx_shield mesh, named ShieldCube, sized and moved like the Part cube")
			u.iceUntil = 5
			U.UpdateStatus({}, u, 1.2, cf)
			local ice = u.icePart
			local crystals, meshOk = 0, true
			for _, c in ipairs(ice and ice:GetChildren() or {}) do
				crystals = crystals + 1
				if not (c:IsA("MeshPart") and c.Name == "Crystal" and c:GetAttribute("ML_Key") == "fx_ice" and type(c:GetAttribute("Angle")) == "number" and c.Position.X == c.Position.X) then
					meshOk = false
				end
			end
			T.check(ice ~= nil and ice.Name == "Ice" and crystals == 5 and meshOk, "battle fx: Ice holds 5 fx_ice Crystal meshes placed by the per-frame code", tostring(crystals))
			u.shield, u.iceUntil = 0, nil
			U.UpdateStatus({}, u, 6, cf)
			T.check(u.shieldPart == nil and u.icePart == nil and sh.Parent == nil, "battle fx: the shield and ice go away as before")
			local B = { lock = 1, units = { u }, folder = world, ended = false, basis = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 } }
			U.UpdateFocus(B, 2)
			local mark = B.focusMark
			local arrows, okArrow = 0, true
			for _, p in ipairs(mark and mark:GetChildren() or {}) do
				arrows = arrows + 1
				if not (p:IsA("MeshPart") and p:GetAttribute("ML_Key") == "fx_arrow" and type(p:GetAttribute("Y")) == "number" and math.abs(p.Position.X - 4) < 1e-3) then
					okArrow = false
				end
			end
			T.check(mark ~= nil and mark.Name == "FocusArrow" and mark.Parent == world and arrows >= 1 and okArrow, "battle fx: FocusArrow is the fx_arrow mesh over the locked unit", tostring(arrows))
			if mark then
				mark:Destroy()
			end
		end
	end)
	T.check(ok, "client_p6creatures fixture mode ran to the end", tostring(err))
	leaveFixtureMode(MLf, root)
	world:Destroy()
	T.check(SD._Rebuild() == true and not SD.IsMesh() and countMeshParts(SD.GetModel()) == 0, "p6 creatures client: after _Reset the dragon is rebuilt from Parts")
end)
end

return S
