-- smoke_p6_lobby.lua: the Phase 6 lobby meshes (ARCHITECTURE_V3.md "## Phase 6" 6.3 art-lobby; owner: art-lobby,
-- wave 2). Server world only:
--   p6lobby_server
--     manifests   a committed manifest for every lobby key (blender/catalog/lobby.json), every part under 10k tris,
--                 the layout-baked keys (cloud_*, floor_*, the altar) carry their LayoutSig
--     default     the booted lobby with the shipped MeshIds: exactly the lobby keys with a shipped id are tagged (empty
--                 MeshIds = nothing tagged, nothing changes); the mock cannot load them, so the Parts stay visible
--     fixture     the real MeshLibrary pointed (_Configure) at canonical templates made from the committed manifests
--                 (fake ids) and a second LobbyBuilder.Build() (the booted lobby is set aside and put back): every
--                 key is tagged where the kit says (template clones, plots, shop, plaza layers, roads, gardens, sky),
--                 the LayoutSig of every layout key matches this very build (the kit and the game agree), keep lists
--                 (podium, sign boards) and looks (obelisk / banner / roulette / flower colours), no tagged subtree
--                 hides another one's parts, the part count is the same as an untagged build (<= 8000), a moved
--                 part makes a layout key refuse to tag (no stale mesh), and Dress puts the mesh at the Tag origin
--                 hiding the Parts but not the kept ones
--     altar       the live Storm Altar's pieces match their committed LayoutSig (read-only: nothing is tagged)
-- Deterministic: fixed ids in sorted key order, no RNG.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local fmt = string.format

local function req(root, path)
	local ok, inst = pcall(Mock.GetPath, ROOTS[root] .. "/" .. path)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

-- blender/catalog/lobby.json keys (layout-baked keys first: they carry LayoutSig)
local LAYOUT_KEYS = {
	"floor_plaza_lawn", "floor_plaza_lawnpatches", "floor_plaza_pathborders", "floor_plaza_paths", "floor_plaza_inlays",
	"floor_plaza_courts", "floor_plaza_walk", "floor_plaza_edges",
	"floor_shop_1", "floor_shop_2", "floor_shop_3", "floor_shop_4", "floor_shop_5",
	"floor_garden_blossom_1", "floor_garden_blossom_2", "floor_garden_blossom_3", "floor_garden_blossom_4",
	"floor_garden_pond_1", "floor_garden_pond_2", "floor_garden_pond_3", "floor_garden_pond_4",
	"floor_junction_plain", "floor_junction_spoke", "floor_junction_garden", "floor_junction_arena", "floor_junction_altar",
	"floor_spoke", "floor_garden_bridge",
	"cloud_plaza", "cloud_shop", "cloud_garden_blossom", "cloud_garden_pond", "cloud_puff_s", "cloud_sky_big",
	"cloud_sky_small", "prop_plot",
}
local ALTAR_KEYS = {
	Island = "cloud_altar", Ring = "prop_altar_ring", Portal = "prop_altar_portal", Crystals = "prop_altar_crystals",
	Bridge = "floor_altar_bridge", StormAltarSign = "prop_altar_sign",
}
local PROP_KEYS = {
	"prop_tree_round", "prop_tree_blossom", "prop_tree_pine", "prop_lamp", "prop_bench", "prop_flowerbed",
	"prop_fountain", "prop_fountain_water", "prop_welcome_arch", "prop_obelisk", "prop_banner", "prop_board_s",
	"prop_board_l", "prop_roulette", "prop_item_stall", "prop_token_statue", "prop_shop_arch", "prop_pond",
	"prop_pond_water",
}

local function allKeys()
	local list = {}
	for _, k in ipairs(LAYOUT_KEYS) do
		list[#list + 1] = k
	end
	for _, k in ipairs(PROP_KEYS) do
		list[#list + 1] = k
	end
	local altar = {}
	for _, k in pairs(ALTAR_KEYS) do
		altar[#altar + 1] = k
	end
	table.sort(altar)
	for _, k in ipairs(altar) do
		list[#list + 1] = k
	end
	list[#list + 1] = "cloud_storm_puff"
	return list
end

local function keySet()
	local set = {}
	for _, k in ipairs(allKeys()) do
		set[k] = true
	end
	return set
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
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = tpl
	end
	tpl:SetAttribute("ML_Status", "ready")
	tpl.Parent = root
	return tpl
end

local function partsOf(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

local function cfFromString(s)
	if type(s) ~= "string" then
		return nil
	end
	local v = {}
	for x in string.gmatch(s, "[^,%s]+") do
		v[#v + 1] = tonumber(x)
	end
	if #v ~= 12 then
		return nil
	end
	return CFrame.new((unpack or table.unpack)(v))
end

local function near(a, b, tol)
	return (a - b).Magnitude <= (tol or 0.05)
end

-- every tagged lobby target under `root`: key -> { targets }
local function tagged(root, set)
	local out = {}
	local list = root:GetDescendants()
	for _, d in ipairs(list) do
		local key = d:GetAttribute("ML_DressKey")
		if type(key) == "string" and set[key] then
			out[key] = out[key] or {}
			table.insert(out[key], d)
		end
	end
	return out
end

S.p6lobby_server = guarded("p6lobby_server", function()
	local LB = req("server", "Services/LobbyBuilder")
	local SA = req("server", "Services/StormAltar")
	local ML = req("shared", "MeshLibrary")
	if not T.check(LB and SA and ML and LB._Mesh and SA._Mesh and type(ML._Configure) == "function",
		"p6 lobby: LobbyBuilder._Mesh, StormAltar._Mesh, MeshLibrary._Configure load") then
		return
	end
	local set = keySet()
	local Config = req("shared", "Config")

	-- manifests
	local missing, heavy, nosig = {}, {}, {}
	for _, key in ipairs(allKeys()) do
		local man = ML.Manifest(key)
		if not man then
			missing[#missing + 1] = key
		else
			for _, p in ipairs(man.Parts) do
				local raw = man.Raw and man.Raw.Parts
				local tris = 0
				for _, rp in ipairs(raw or {}) do
					if rp.Name == p.name then
						tris = tonumber(rp.Tris) or 0
					end
				end
				if tris > 10000 then
					heavy[#heavy + 1] = key .. "." .. p.name
				end
			end
		end
	end
	for _, key in ipairs(LAYOUT_KEYS) do
		local man = ML.Manifest(key)
		if man and not (man.Attachments and man.Attachments.LayoutSig) then
			nosig[#nosig + 1] = key
		end
	end
	for _, key in pairs(ALTAR_KEYS) do
		local man = ML.Manifest(key)
		if man and not (man.Attachments and man.Attachments.LayoutSig) then
			nosig[#nosig + 1] = key
		end
	end
	T.check(#missing == 0, fmt("p6 lobby: a committed manifest for every lobby key (%d)", #allKeys()), table.concat(missing, ", "))
	T.check(#heavy == 0, "p6 lobby: every MeshPart under 10k triangles", table.concat(heavy, ", "))
	T.check(#nosig == 0, "p6 lobby: every layout-baked key carries its LayoutSig", table.concat(nosig, ", "))

	-- default mode: the booted lobby is untouched
	local live = Workspace:FindFirstChild("NimbusLobby")
	if not T.check(live ~= nil, "p6 lobby: the booted lobby exists") then
		return
	end
	local found = tagged(live, set)
	local n = 0
	for _ in pairs(found) do
		n = n + 1
	end
	-- a lobby piece is tagged once its key has a shipped id (Status ~= "missing") and its LayoutSig matches (the
	-- LobbyBuilder / StormAltar rule); the mock has no asset store, so shipped ids stay 'loading' (Parts stay visible)
	local function shipped(key)
		local okStatus, st = pcall(ML.Status, key)
		return okStatus and st ~= "missing"
	end
	local stray, idle = {}, {}
	for key in pairs(found) do
		if not shipped(key) then
			stray[#stray + 1] = key
		end
	end
	local nShipped = 0
	for _, key in ipairs(allKeys()) do
		if shipped(key) then
			nShipped = nShipped + 1
			if not found[key] then
				idle[#idle + 1] = key
			end
		end
	end
	table.sort(stray)
	T.check(#stray == 0, "p6 lobby default: only lobby keys with a shipped id are tagged", table.concat(stray, ", "))
	T.check(#idle == 0, fmt("p6 lobby default: every lobby key with a shipped id is tagged in the booted lobby (%d shipped, %d tagged)", nShipped, n),
		table.concat(idle, ", "))
	local liveTags, strayTags = 0, 0
	for _, d in ipairs(CollectionService:GetTagged("ML_Dress")) do
		local key = d:GetAttribute("ML_DressKey")
		if type(key) == "string" and set[key] then
			liveTags = liveTags + 1
			if not shipped(key) then
				strayTags = strayTags + 1
			end
		end
	end
	T.check(strayTags == 0 and (nShipped == 0) == (liveTags == 0),
		fmt("p6 lobby default: ML_Dress tags on lobby pieces only for shipped keys (%d tags)", liveTags))

	-- the live Storm Altar matches the committed LayoutSig of each piece (read-only)
	local altar = type(SA.GetModel) == "function" and SA.GetModel()
	if T.check(altar ~= nil and altar.PrimaryPart ~= nil, "p6 lobby altar: the live Storm Altar exists") then
		local A = altar.PrimaryPart.CFrame
		local bad = {}
		for name, key in pairs(ALTAR_KEYS) do
			local target = altar:FindFirstChild(name)
			local man = ML.Manifest(key)
			local att = man and man.Attachments and man.Attachments.LayoutSig
			local pos = att and (att.Pos or att.pos)
			if not (target and pos) then
				bad[#bad + 1] = name .. " (missing)"
			else
				local cnt, a, b = SA._Mesh.Signature(target, A)
				local tol = 0.05 + cnt * 1e-4
				if cnt ~= pos[1] or math.abs(a - pos[2]) > tol or math.abs(b - pos[3]) > tol then
					bad[#bad + 1] = fmt("%s (%d %.3f %.3f vs %s %s %s)", name, cnt, a, b, tostring(pos[1]), tostring(pos[2]), tostring(pos[3]))
				end
			end
		end
		table.sort(bad)
		T.check(#bad == 0, "p6 lobby altar: island / ring / portal / crystals / bridge / sign match their LayoutSig", table.concat(bad, "; "))
	end

	-- a second build next to the booted one (set aside, put back afterwards)
	live.Name = "NimbusLobby_P6Keep"
	ML._Reset() -- a true untagged build: under --mesh the global pet fixtures would turn the fountain statue into a mesh
	local okDefault, infoDefault = pcall(LB.Build)
	local defaultParts = (okDefault and infoDefault and infoDefault.Folder) and partsOf(infoDefault.Folder) or -1
	-- [fix-runtime W2.5] a place()d clone's pivot is where it was placed: Plot:GetPivot() == SpotInfo.PlotCFrame
	-- (TutorialController uses it as the plot's ground point)
	local pivotBad, pivotN = {}, 0
	for i, spot in ipairs((okDefault and infoDefault and infoDefault.Spots) or {}) do
		local plot = spot.Folder and spot.Folder:FindFirstChild("Plot")
		if plot and typeof(spot.PlotCFrame) == "CFrame" then
			pivotN = pivotN + 1
			local pv = plot:GetPivot()
			if (pv.Position - spot.PlotCFrame.Position).Magnitude > 1e-3 or (pv.LookVector - spot.PlotCFrame.LookVector).Magnitude > 1e-4 then
				pivotBad[#pivotBad + 1] = tostring(i)
			end
		end
	end
	T.check(pivotN > 0 and #pivotBad == 0, fmt("p6 lobby: every Plot:GetPivot() == SpotInfo.PlotCFrame (%d plots)", pivotN), table.concat(pivotBad, ", "))
	if okDefault and infoDefault and infoDefault.Folder then
		infoDefault.Folder:Destroy()
	end

	ML._Reset()
	local root = Instance.new("Folder")
	root.Name = "P6LobbyMeshes"
	root.Parent = RS
	local ids = {}
	for i, key in ipairs(allKeys()) do
		ids[key] = 9100 + i
		installTemplate(ML, root, key)
	end
	ML._Configure({ Root = root, Ids = ids })
	local okBuild, info = pcall(LB.Build)
	local okTests, err = pcall(function()
		if not T.check(okBuild and type(info) == "table" and info.Folder ~= nil, "p6 lobby fixture: LobbyBuilder.Build() with mesh ids", tostring(info)) then
			return
		end
		local lobby = info.Folder
		local parts = partsOf(lobby)
		T.check(parts == defaultParts and parts <= 8000, fmt("p6 lobby fixture: tagging adds no parts (%d tagged build, %d untagged, budget 8000)", parts, defaultParts))
		local got = tagged(lobby, set)
		local untagged = {}
		for _, key in ipairs(LAYOUT_KEYS) do
			if not got[key] then
				untagged[#untagged + 1] = key
			end
		end
		for _, key in ipairs(PROP_KEYS) do
			if not got[key] then
				untagged[#untagged + 1] = key
			end
		end
		T.check(#untagged == 0, "p6 lobby fixture: every lobby key is tagged (the live build matches every LayoutSig)", table.concat(untagged, ", "))
		local spots = #(info.Spots or {})
		T.check(got.prop_plot and #got.prop_plot == spots, fmt("p6 lobby fixture: every plot tagged (%d of %d)", got.prop_plot and #got.prop_plot or 0, spots))
		T.check(got.prop_roulette and #got.prop_roulette == #Config.Roulettes, "p6 lobby fixture: one roulette cabinet per roulette")
		T.check(got.prop_lamp and #got.prop_lamp >= 20, fmt("p6 lobby fixture: lamp clones tagged (%d)", got.prop_lamp and #got.prop_lamp or 0))

		-- origins: the plot mesh sits on SpotInfo.PlotCFrame, every Offset parses, the tag look / keep lists
		local badOrigin = 0
		for _, key in ipairs(allKeys()) do
			for _, target in ipairs(got[key] or {}) do
				if not cfFromString(target:GetAttribute("ML_Offset")) then
					badOrigin = badOrigin + 1
				end
			end
		end
		T.check(badOrigin == 0, "p6 lobby fixture: every tagged target has an ML_Offset")
		local plotOk = true
		for _, spot in ipairs(info.Spots or {}) do
			local plot = spot.Folder and spot.Folder:FindFirstChild("Plot")
			local off = plot and cfFromString(plot:GetAttribute("ML_Offset"))
			if not (off and near((plot:GetPivot() * off).Position, spot.PlotCFrame.Position) and plot:GetAttribute("ML_Keep") == "Accent,PodiumBase,PodiumTop") then
				plotOk = false
			end
		end
		T.check(plotOk, "p6 lobby fixture: plot meshes sit on PlotCFrame and keep the podium (ML_Keep)")
		local keeps = { prop_board_s = "Face", prop_board_l = "Face", prop_welcome_arch = "WelcomeSign", prop_shop_arch = "ShopSign" }
		for key, want in pairs(keeps) do
			local t = got[key] and got[key][1]
			T.check(t and t:GetAttribute("ML_Keep") == want, "p6 lobby fixture: " .. key .. " keeps " .. want)
		end
		local primaries = 0
		for _, key in ipairs({ "prop_obelisk", "prop_banner", "prop_roulette", "prop_flowerbed" }) do
			for _, t in ipairs(got[key] or {}) do
				if typeof(t:GetAttribute("ML_Primary")) == "Color3" then
					primaries = primaries + 1
				end
			end
		end
		local want = #(got.prop_obelisk or {}) + #(got.prop_banner or {}) + #(got.prop_roulette or {}) + #(got.prop_flowerbed or {})
		T.check(primaries == want and want > 0, fmt("p6 lobby fixture: obelisks / banners / roulettes / flower beds carry ML_Primary (%d/%d)", primaries, want))
		local roulettesOk = true
		for _, r in ipairs(Config.Roulettes) do
			local m = lobby:FindFirstChild("Roulette_" .. r.Id, true)
			local body = m and m:FindFirstChild("Machine")
			if not (body and body:GetAttribute("ML_DressKey") == "prop_roulette" and body:GetAttribute("ML_Primary") == r.Color) then
				roulettesOk = false
			end
		end
		T.check(roulettesOk, "p6 lobby fixture: each roulette's Machine is tagged in its own colour (PromptPart / tags stay outside)")

		-- no tagged subtree hides another's parts: a nested tagged piece's parts are all in the outer keep list
		local clash = {}
		for _, key in ipairs(allKeys()) do
			for _, target in ipairs(got[key] or {}) do
				local keep = {}
				for nm in string.gmatch(target:GetAttribute("ML_Keep") or "", "[^,]+") do
					keep[nm] = true
				end
				for _, d in ipairs(target:GetDescendants()) do
					if type(d:GetAttribute("ML_DressKey")) == "string" then
						for _, p in ipairs(d:GetDescendants()) do
							if p:IsA("BasePart") and not keep[p.Name] then
								clash[#clash + 1] = key .. ">" .. d.Name .. "." .. p.Name
								break
							end
						end
					end
				end
			end
		end
		T.check(#clash == 0, "p6 lobby fixture: tagged pieces never nest without keeping each other's parts", table.concat(clash, ", "))

		-- a stale layout refuses to tag: move one lawn part of a copy
		local lawn = got.floor_plaza_lawn and got.floor_plaza_lawn[1]
		if T.check(lawn ~= nil, "p6 lobby fixture: the lawn layer is tagged") then
			local origin = CFrame.new(Config.Lobby.Origin.X, Config.Lobby.Origin.Y, Config.Lobby.Origin.Z)
			local copy = lawn:Clone()
			copy:SetAttribute("ML_DressKey", nil)
			copy.Parent = Workspace
			local same = LB._Mesh.tag(copy, "floor_plaza_lawn", origin)
			local moved = copy:Clone()
			copy:Destroy()
			moved.Parent = Workspace
			for _, p in ipairs(moved:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CFrame = p.CFrame + Vector3.new(2, 0, 0)
					break
				end
			end
			local stale = LB._Mesh.tag(moved, "floor_plaza_lawn", origin)
			moved:Destroy()
			T.check(same == true and stale == false, "p6 lobby fixture: LayoutSig accepts the same layout, refuses a moved part")
		end

		-- Dress (the client path; usable on the server in the mock): the mesh lands at the Tag origin
		local lamp = got.prop_lamp and got.prop_lamp[1]
		local plot = got.prop_plot and got.prop_plot[1]
		if T.check(lamp ~= nil and plot ~= nil, "p6 lobby fixture: a lamp and a plot to dress") then
			local base = lamp:FindFirstChild("LampBase")
			local ground = base and (base.Position - Vector3.new(0, 0.6, 0))
			ML.Dress(lamp, "prop_lamp")
			ML.Dress(plot, "prop_plot")
			task.wait()
			task.wait()
			local mesh = lamp:FindFirstChild("ML_Mesh")
			T.check(mesh ~= nil and ground ~= nil and near(mesh:GetPivot().Position, ground, 0.05),
				"p6 lobby fixture: the dressed lamp mesh stands on the lamp's foot", mesh and tostring(mesh:GetPivot().Position) or "no mesh")
			T.check(base and base.Transparency == 1, "p6 lobby fixture: the lamp's Parts are hidden locally (still colliding)")
			local pmesh = plot:FindFirstChild("ML_Mesh")
			local podium = plot:FindFirstChild("Podium")
			local accent = podium and podium:FindFirstChild("Accent")
			local yard = plot:FindFirstChild("Yard")
			T.check(pmesh ~= nil and accent ~= nil and accent.Transparency == 0 and yard ~= nil and yard.Transparency == 1,
				"p6 lobby fixture: a dressed plot hides its yard but keeps the podium (live plot colour)")
		end
	end)
	-- put everything back
	if okBuild and type(info) == "table" and info.Folder then
		info.Folder:Destroy()
	end
	ML._Reset()
	root:Destroy()
	live.Name = "NimbusLobby"
	local P6 = rawget(_G, "P6Pets")
	if P6 and P6.MeshMode then
		P6.Install(P6.PetKeys()) -- --mesh: put back the global fixture set that _Reset wiped
	end
	T.check(okTests, "p6 lobby fixture: scenario ran", tostring(err))
end)

return S
