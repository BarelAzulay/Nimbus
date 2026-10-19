-- dump_model.lua: builds a model with the REAL game modules inside the Roblox mock and dumps every BasePart
-- (world position, full rotation matrix, Size, Color3 as 0-255, Material, Transparency, Shape / wedge class)
-- as JSON, so tools/render_model.py can draw it offline.
--
-- It runs under lupa with tools/robloxmock.lua, booted exactly like tools/smoke.py boots a world (render_model.py
-- does that: Mock.Configure + Mock.Boot(context) + src/ mounted where default.project.json says). Globals:
--   Mock    the booted mock
--   ROOTS   src directory name -> instance path ("shared" -> "ReplicatedStorage/Shared", ...)
--   DUMP    { target = "pet:stormfang:High", out = "file.json" | nil, box = { x0, y0, z0, x1, y1, z1 } | nil }
-- The chunk returns the JSON text (and writes it to DUMP.out when given).
--
-- Targets (several can be joined with "+", e.g. "lobby+npcs+storm-altar"; each becomes one entry of `models`):
--   pet:<petId>[:High|Low]          PetBuilder.Build with the catalog def (High by default)
--   species:<Species>[:High|Low]    PetBuilder.Build with a neutral sample Look of that species
--   pets[:High|Low]                 every catalog pet, one model each (render_model.py --grid)
--   species[:High|Low]              every species with the neutral sample Look, one model each
--   lobby                           LobbyBuilder.Build() (crop with DUMP.box)
--   npcs                            NpcService.Init(lobbyInfo) after the lobby (only the NPC folder is dumped)
--   storm-altar                     StormAltar.Build(lobbyInfo) after the lobby (server/Services/StormAltar.lua)
--   skydragon                       the Sage Dragon SkyDragonController builds (client world)
--   token[:golden]                  TokenService.MakeTokenPart (a normal or a golden coin)
--   home:<StationId>[:<level>|all[:<open>]]  a home station (HomeBuilder.BuildStationModel), see BUILDERS.home
--                                   (Press1..4 = the food plants, Collector = the Coin Magnet, Kitchen = the Food
--                                   Machine, Gym = the Training Place; <open> = the Garden's open places)
--   homerow:<StationId>[:<levels>[:<open>]]  levels side by side; homegardens[:<level>[:<opens>]] open counts side by side
--   homeplot[:<tier>[:pads]]        a fully built home plot on the lobby for house tier 1-4 or its name (Cottage, Villa,
--                                   Manor, SkyCastle), see BUILDERS.homeplot
--   homefree                        spot 1 prepared by HomeBuilder but unclaimed (gate, claim signpost)
--   homegarden[:<open>[:<level>]] / hometrain[:<level>] (homegym)  (client) the Pet Garden with a pet on every open place
--                                   and coin piles / the Training Place with a pet on every mat, drawn by the real HomeFx
--   pocket[:<index>|ring]           an ArenaBuilder pocket (pocket:ring = BuildPocket(1, "Ring"))
--   portal:home                     (client) the home portal HomePortalFx draws from the player's HomePortal attribute
--   module:<path>:<func>[:lobby]    generic: require src/<path> (e.g. shared/Foo, server/Services/Foo) and call
--                                   <func>() (or <func>(lobbyInfo) with :lobby); the result may be an Instance, a
--                                   table with Model / Folder / Root, or nothing (then the new Workspace children)
-- Every model records `facing` (the direction its front looks at: a pet's LookVector, a coin's face normal,
-- the dragon head's LookVector) so the renderer's "front" view looks the model in the face.
-- Plain Lua 5.1 syntax only.

local Workspace = game:GetService("Workspace")

local ARGS = DUMP or {}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function fail(msg)
	error("dump_model: " .. tostring(msg), 0)
end

-- plain-text split ("a:b::c" -> { "a", "b", "", "c" })
local function split(text, sep)
	local out = {}
	local pos = 1
	while true do
		local a, b = text:find(sep, pos, true)
		if not a then
			out[#out + 1] = text:sub(pos)
			return out
		end
		out[#out + 1] = text:sub(pos, a - 1)
		pos = b + 1
	end
end

-- "shared/PetBuilder" -> the ModuleScript instance (nil when it does not exist)
local function moduleInstance(key)
	local top, rest = key:match("^(%w+)/(.+)$")
	local rootPath = top and ROOTS[top]
	if not rootPath then
		return nil
	end
	local inst = Mock.GetPath(rootPath)
	for part in rest:gmatch("[^/]+") do
		inst = inst and inst:FindFirstChild(part)
	end
	return inst
end

local loaded = {}
local function req(key, optional)
	if loaded[key] then
		return loaded[key]
	end
	local inst = moduleInstance(key)
	if not inst then
		if optional then
			return nil
		end
		fail("src/" .. key .. ".lua does not exist")
	end
	local ok, result = pcall(require, inst)
	if not ok then
		fail("require " .. key .. " failed: " .. tostring(type(result) == "table" and (result.msg or result) or result))
	end
	if type(result) ~= "table" then
		fail(key .. " did not return a table")
	end
	loaded[key] = result
	return result
end

local function vec3(v)
	return { v.X, v.Y, v.Z }
end

local function isInstance(v)
	return typeof(v) == "Instance"
end

-- an Instance from whatever a builder returned
local function rootOf(result)
	if isInstance(result) then
		return result
	end
	if type(result) == "table" then
		for _, key in ipairs({ "Model", "Folder", "Root", "Instance", "Part" }) do
			if isInstance(result[key]) then
				return result[key]
			end
		end
		if isInstance(result[1]) then
			return result[1]
		end
	end
	return nil
end

local function lookOf(inst)
	if not isInstance(inst) then
		return nil
	end
	local part = nil
	if inst:IsA("Model") then
		part = inst.PrimaryPart
	elseif inst:IsA("BasePart") then
		part = inst
	end
	if part then
		return vec3(part.CFrame.LookVector)
	end
	return nil
end

-- every BasePart of root (root included); box = optional { x0, y0, z0, x1, y1, z1 } world crop
local function collectParts(root, box)
	local list = {}
	if root:IsA("BasePart") then
		list[1] = root
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			list[#list + 1] = d
		end
	end
	if not box then
		return list, #list
	end
	local x0, y0, z0 = math.min(box[1], box[4]), math.min(box[2], box[5]), math.min(box[3], box[6])
	local x1, y1, z1 = math.max(box[1], box[4]), math.max(box[2], box[5]), math.max(box[3], box[6])
	local kept = {}
	for _, p in ipairs(list) do
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
		local s = p.Size
		local ex = (math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z) / 2
		local ey = (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2
		local ez = (math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z) / 2
		if x + ex >= x0 and x - ex <= x1 and y + ey >= y0 and y - ey <= y1 and z + ez >= z0 and z - ez <= z1 then
			kept[#kept + 1] = p
		end
	end
	return kept, #list
end

----------------------------------------------------------------------
-- JSON
----------------------------------------------------------------------
local fmt = string.format

local function num(v)
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return "0"
	end
	local s = fmt("%.4f", v)
	s = s:gsub("%.?0+$", "")
	if s == "-0" or s == "" then
		return "0"
	end
	return s
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function str(v)
	local s = tostring(v)
	s = s:gsub('[%c"\\]', function(c)
		return ESC[c] or fmt("\\u%04x", c:byte())
	end)
	return '"' .. s .. '"'
end

local function arr(t)
	local out = {}
	for i = 1, #t do
		out[i] = num(t[i])
	end
	return "[" .. table.concat(out, ",") .. "]"
end

-- path of inst below root ("Pet.WingL3")
local function pathOf(inst, root)
	local names = {}
	local cur = inst
	local guard = 0
	while cur and cur ~= root and guard < 64 do
		table.insert(names, 1, cur.Name)
		cur = cur.Parent
		guard = guard + 1
	end
	if inst == root then
		return inst.Name
	end
	return table.concat(names, ".")
end

local function shapeOf(p)
	local cls = p.ClassName
	if cls == "WedgePart" then
		return "Wedge"
	elseif cls == "CornerWedgePart" then
		return "CornerWedge"
	elseif p:IsA("Part") then
		local ok, shape = pcall(function()
			return p.Shape
		end)
		if ok and shape ~= nil then
			local name = tostring(shape.Name or shape)
			if name == "Ball" or name == "Cylinder" or name == "Wedge" or name == "CornerWedge" then
				return name
			end
		end
		-- a SpecialMesh sphere turns a block into an ellipsoid
		local mesh = p:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			local okType, mt = pcall(function()
				return mesh.MeshType
			end)
			if okType and mt and tostring(mt.Name or mt) == "Sphere" then
				return "Ellipsoid"
			end
		end
	end
	return "Block"
end

local function partJson(p, root)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local c = p.Color
	local mat = p.Material
	local matName = tostring(mat and (mat.Name or mat) or "Plastic")
	return table.concat({
		"{\"path\":", str(pathOf(p, root)),
		",\"class\":", str(p.ClassName),
		",\"shape\":", str(shapeOf(p)),
		",\"pos\":", arr({ x, y, z }),
		",\"rot\":", arr({ r00, r01, r02, r10, r11, r12, r20, r21, r22 }),
		",\"size\":", arr({ p.Size.X, p.Size.Y, p.Size.Z }),
		",\"color\":[", tostring(math.floor(c.R * 255 + 0.5)), ",", tostring(math.floor(c.G * 255 + 0.5)), ",", tostring(math.floor(c.B * 255 + 0.5)), "]",
		",\"material\":", str(matName),
		",\"transparency\":", num(p.Transparency),
		"}",
	})
end

----------------------------------------------------------------------
-- builders (each returns { root = Instance, label, sub, facing })
----------------------------------------------------------------------
local lobbyInfo = nil
local function ensureLobby()
	if lobbyInfo then
		return lobbyInfo
	end
	local LobbyBuilder = req("server/Services/LobbyBuilder")
	local info = LobbyBuilder.Build()
	if type(info) ~= "table" or not isInstance(info.Folder) then
		fail("LobbyBuilder.Build() did not return a LobbyInfo with a Folder")
	end
	lobbyInfo = info
	return info
end

local function detailOf(value)
	if value == nil or value == "" then
		return "High"
	end
	local v = tostring(value):lower()
	if v == "low" then
		return "Low"
	elseif v == "high" then
		return "High"
	elseif v == "evolved" or v == "evo" then
		return "EvoHigh"
	elseif v == "evolvedlow" or v == "evolved-low" or v == "evolved_low" or v == "evolow" then
		return "EvoLow"
	elseif v == "evolved2" or v == "evo2" then
		return "Evo2High"
	elseif v == "evolved2low" or v == "evolved2-low" or v == "evolved2_low" or v == "evo2low" then
		return "Evo2Low"
	end
	fail("detail must be High or Low, got '" .. tostring(value) .. "'")
end

local function petModel(def, detail, label, sub)
	local PetBuilder = req("shared/PetBuilder")
	local evolved = detail:sub(1, 3) == "Evo"
	local stage = evolved and ((detail:sub(4, 4) == "2") and 2 or 1) or nil
	local model = PetBuilder.Build(def, { Detail = (detail:gsub("^Evo2?", "")), Evolved = stage })
	if not isInstance(model) then
		fail("PetBuilder.Build returned no model for " .. tostring(def.Id))
	end
	return { root = model, label = label, sub = sub, facing = lookOf(model) or { 0, 0, -1 } }
end

local function catalogPet(id, detail)
	local PetCatalog = req("shared/PetCatalog")
	local def = PetCatalog.Get(id)
	if not def then
		local ids = {}
		for _, d in ipairs(PetCatalog.Pets) do
			ids[#ids + 1] = d.Id
		end
		fail("unknown pet '" .. tostring(id) .. "'. Pets: " .. table.concat(ids, ", "))
	end
	local look = type(def.Look) == "table" and def.Look or {}
	local sub = tostring(def.Rarity) .. "  " .. tostring(look.Species) .. "  " .. detail
	if def.Element then
		sub = sub .. "  " .. tostring(def.Element)
	end
	return petModel(def, detail, tostring(def.Name or id), sub)
end

-- a neutral sample Look: calm beige fur, cream accents, dark eyes, pale wings
local function sampleDef(species)
	local wing = "Feather"
	if species == "Stormfang" then
		wing = "StormCloud"
	end
	return {
		Id = "sample_" .. species:lower(),
		Name = species,
		Rarity = "Common",
		Look = {
			Species = species,
			Primary = Color3.fromRGB(214, 190, 160),
			Secondary = Color3.fromRGB(246, 236, 220),
			Eye = Color3.fromRGB(46, 40, 62),
			Glow = false,
			WingStyle = wing,
			WingColor = Color3.fromRGB(232, 230, 244),
		},
	}
end

local function speciesList()
	local PetBuilder = req("shared/PetBuilder")
	if type(PetBuilder.Species) == "table" and #PetBuilder.Species > 0 then
		return PetBuilder.Species
	end
	return req("shared/PetCatalog").Species or {}
end

local function speciesPet(species, detail)
	local known = false
	local list = speciesList()
	for _, s in ipairs(list) do
		if s:lower() == tostring(species):lower() then
			species = s
			known = true
		end
	end
	if not known then
		fail("unknown species '" .. tostring(species) .. "'. Species: " .. table.concat(list, ", "))
	end
	return petModel(sampleDef(species), detail, species, "sample look  " .. detail)
end

local function workspaceSnapshot()
	local set = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		set[c] = true
	end
	return set
end

-- new Workspace children since `before` gathered under one Folder-like view (a plain table of roots)
local function newChildren(before)
	local out = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		if not before[c] and not c:IsA("Camera") and not c:IsA("Terrain") then
			out[#out + 1] = c
		end
	end
	return out
end

local BUILDERS = {}

BUILDERS.pet = function(a, b)
	if not a or a == "" then
		fail("usage: pet:<petId>[:High|Low]")
	end
	return { catalogPet(a, detailOf(b)) }
end

-- one entry of a batch (every pet / species): a model that fails to build becomes an empty, labelled entry
-- so the contact sheet still shows every other one
local function tryBuild(label, fn, ...)
	local ok, result = pcall(fn, ...)
	if ok then
		return result
	end
	local msg = tostring(type(result) == "table" and (result.msg or result) or result):gsub("^dump_model: ", "")
	return { root = nil, label = label, sub = "BUILD FAILED: " .. msg, facing = { 0, 0, -1 } }
end

BUILDERS.species = function(a, b)
	-- "species" alone (or "species:Low") = every species; "species:Cat[:Low]" = one
	if a == nil or a == "" or a:lower() == "high" or a:lower() == "low" then
		local detail = detailOf(a)
		local out = {}
		for _, s in ipairs(speciesList()) do
			out[#out + 1] = tryBuild(s, speciesPet, s, detail)
		end
		return out
	end
	return { speciesPet(a, detailOf(b)) }
end

BUILDERS.pets = function(a)
	local detail = detailOf(a)
	local second = detail:sub(1, 4) == "Evo2" -- the second evolution: only the pets that have one
	local out = {}
	for _, def in ipairs(req("shared/PetCatalog").Pets) do
		if not second or req("shared/PetBuilder").MaxEvolution(def) >= 2 then
			out[#out + 1] = tryBuild(tostring(def.Name or def.Id), catalogPet, def.Id, detail)
		end
	end
	return out
end

BUILDERS.lobby = function()
	local info = ensureLobby()
	return { { root = info.Folder, label = "Lobby", sub = "LobbyBuilder.Build()", facing = { 0, 0, -1 } } }
end

BUILDERS.npcs = function()
	local info = ensureLobby()
	local NpcService = req("server/Services/NpcService")
	NpcService.Init(info, {})
	Mock.Advance(0.2)
	local folder = Workspace:FindFirstChild("NimbusNpcs")
	if not folder then
		fail("NpcService.Init built no workspace.NimbusNpcs folder")
	end
	return { { root = folder, label = "NPCs", sub = "NpcService.Init(lobbyInfo)", facing = { 0, 0, -1 } } }
end

BUILDERS["storm-altar"] = function()
	local info = ensureLobby()
	local StormAltar = req("server/Services/StormAltar", true)
	if not StormAltar then
		fail("server/Services/StormAltar.lua does not exist yet")
	end
	if type(StormAltar.Build) ~= "function" then
		fail("StormAltar.Build is missing")
	end
	local result = StormAltar.Build(info)
	Mock.Advance(0.2)
	local root = rootOf(result)
	if not root or root.Name ~= "StormAltar" then
		root = Workspace:FindFirstChild("StormAltar", true) or root
	end
	if not root then
		fail("StormAltar.Build built no model named StormAltar")
	end
	local facing = lookOf(root)
	if not facing and typeof(info.AltarSite) == "CFrame" then
		facing = vec3(info.AltarSite.LookVector)
	end
	return { { root = root, label = "Storm Altar", sub = "StormAltar.Build(lobbyInfo)", facing = facing or { 0, 0, -1 } } }
end

BUILDERS.skydragon = function()
	local Sky = req("client/Controllers/SkyDragonController")
	Sky.Init()
	Mock.AdvanceUntil(function()
		return Sky.GetModel() ~= nil
	end, 30)
	local model = Sky.GetModel()
	if not model then
		fail("SkyDragonController built no model (is this the client world?)")
	end
	local facing = { 0, 0, -1 }
	local head = model:FindFirstChild("Head")
	if head then
		local part = head:IsA("BasePart") and head or head:FindFirstChildWhichIsA("BasePart", true)
		if part then
			facing = vec3(part.CFrame.LookVector)
		end
	end
	return { { root = model, label = "Sage Dragon", sub = "SkyDragonController (pose at t = 0)", facing = facing } }
end

BUILDERS.token = function(a)
	local Config = req("shared/Config")
	local TokenService = req("server/Services/TokenService")
	local golden = a ~= nil and a:lower() == "golden"
	local value = golden and Config.Tokens.GoldenValue or Config.Tokens.DefaultValue
	local token = TokenService.MakeTokenPart(Vector3.new(0, 0, 0), nil, value)
	if not isInstance(token) then
		fail("TokenService.MakeTokenPart returned no part")
	end
	-- the coin stands on its edge facing local X
	return { { root = token, label = golden and "Golden token" or "Cloud token", sub = "TokenService.MakeTokenPart", facing = vec3(token.CFrame.RightVector) } }
end

BUILDERS.module = function(path, func, extra)
	if not path or not func or path == "" or func == "" then
		fail("usage: module:<path>:<func>[:lobby]   e.g. module:server/Services/LobbyBuilder:Build")
	end
	path = path:gsub("^src/", ""):gsub("%.lua$", "")
	local m = req(path)
	if type(m[func]) ~= "function" then
		fail(path .. "." .. func .. " is not a function")
	end
	local args = {}
	if extra ~= nil and extra:lower() == "lobby" then
		args[1] = ensureLobby()
	end
	local before = workspaceSnapshot()
	local result = m[func](unpack(args))
	Mock.Advance(0.2)
	local root = rootOf(result)
	local label = path:match("([^/]+)$") .. "." .. func
	if root then
		return { { root = root, label = label, sub = "module", facing = lookOf(root) or { 0, 0, -1 } } }
	end
	local list = newChildren(before)
	if #list == 0 then
		fail(label .. " returned nothing and built nothing in the Workspace")
	end
	local out = {}
	for _, inst in ipairs(list) do
		out[#out + 1] = { root = inst, label = label .. " " .. inst.Name, sub = "module", facing = { 0, 0, -1 } }
	end
	return out
end
-- Homes (server/Services/HomeBuilder.lua):
--   home:<StationId>[:<level>|all[:<open>]]  one station model at the origin (front -Z); "all" = every level, one model
--                                    each; <open> = the Garden's open place count (default Prestige.GardenSlotsBase)
--   homerow:<StationId>[:<levels>[:<open>]]  levels side by side in one model (compare sizes at one scale), e.g. 1,4,7,10
--   homegardens[:<level>[:<opens>]]  the Garden at one level with several open counts side by side (default 3,7,12)
--   homeplot[:<tier>[:pads]]       spot 1 of the real lobby built up for house tier 1-4 / Cottage / Villa / Manor /
--                                    SkyCastle (every station at the cap of that tier; tier 4 = everything maxed and
--                                    Prestige 1), owned by a stand-in player, the Garden's open places from
--                                    TycoonCatalog.GardenSlots; ":pads" also places the buy pads AvailablePads shows
local function homeBuilder()
	local HB = req("server/Services/HomeBuilder", true)
	if not HB then
		fail("server/Services/HomeBuilder.lua does not exist yet")
	end
	return HB
end

BUILDERS.home = function(id, level, open)
	local HB = homeBuilder()
	local TC = req("shared/TycoonCatalog")
	local def = TC.Get(id or "")
	if not def or def.Kind == "Prestige" then
		local ids = {}
		for _, d in ipairs(TC.Stations) do
			ids[#ids + 1] = d.Id
		end
		fail("unknown station '" .. tostring(id) .. "'. Stations: " .. table.concat(ids, ", "))
	end
	local levels = {}
	if level == "all" then
		for l = 1, def.MaxLevel do
			levels[#levels + 1] = l
		end
	else
		levels[1] = tonumber(level) or def.MaxLevel
	end
	local out = {}
	for _, l in ipairs(levels) do
		local m = HB.BuildStationModel(id, l, nil, tonumber(open))
		if not m then
			fail("HomeBuilder.BuildStationModel(" .. id .. ", " .. l .. ") returned nothing")
		end
		m.Parent = Workspace
		local extra = (def.Kind == "Garden") and ("  " .. tostring(m:GetAttribute("Open")) .. " open places") or ""
		out[#out + 1] = { root = m, label = def.Name .. "  Lv " .. l .. extra, sub = id .. ":" .. l, facing = { 0, 0, -1 } }
	end
	return out
end

-- homerow:<StationId>[:<l1,l2,...>]  the given levels (default: every level) side by side, ONE model, one scale
BUILDERS.homerow = function(id, list, open)
	local HB = homeBuilder()
	local TC = req("shared/TycoonCatalog")
	local def = TC.Get(id or "")
	if not def or def.Kind == "Prestige" then
		fail("unknown station '" .. tostring(id) .. "'")
	end
	local levels = {}
	for v in tostring(list or ""):gmatch("[^,]+") do
		levels[#levels + 1] = tonumber(v)
	end
	if #levels == 0 then
		for l = 1, def.MaxLevel do
			levels[#levels + 1] = l
		end
	end
	local folder = Instance.new("Model")
	folder.Name = "Row_" .. id
	local step = math.min(def.Slot.Footprint.X, 40) + 4
	for i, l in ipairs(levels) do
		local m = HB.BuildStationModel(id, l, nil, tonumber(open))
		if m then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = CFrame.new((i - 1) * step, 0, 0) * d.CFrame
				end
			end
			m.Parent = folder
		end
	end
	folder.Parent = Workspace
	return { { root = folder, label = def.Name .. " levels " .. table.concat(levels, ","), sub = id, facing = { 0, 0, -1 } } }
end

-- homegardens[:<level>[:<opens>]]  the Garden at one level, one model per open count, side by side
BUILDERS.homegardens = function(level, list)
	local HB = homeBuilder()
	local TC = req("shared/TycoonCatalog")
	local def = TC.Get("Garden")
	level = math.max(1, math.min(def.MaxLevel, tonumber(level) or def.MaxLevel))
	local opens = {}
	for v in tostring(list or "3,7,12"):gmatch("[^,]+") do
		opens[#opens + 1] = tonumber(v)
	end
	local folder = Instance.new("Model")
	folder.Name = "Gardens"
	local step = def.Slot.Footprint.X + 4
	local total = 0
	for i, o in ipairs(opens) do
		local m = HB.BuildStationModel("Garden", level, nil, o)
		if m then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = CFrame.new((i - 1) * step, 0, 0) * d.CFrame
					total = total + 1
				end
			end
			m.Parent = folder
		end
	end
	folder.Parent = Workspace
	return { { root = folder, label = "Pet Garden Lv " .. level .. ", open places " .. table.concat(opens, " / "), sub = "Garden", facing = { 0, 0, -1 } } }
end

local TIER_NAMES = { cottage = 1, villa = 2, manor = 3, skycastle = 4, castle = 4 }

BUILDERS.homeplot = function(tier, extra)
	local HB = homeBuilder()
	local TC = req("shared/TycoonCatalog")
	local info = ensureLobby()
	tier = TIER_NAMES[tostring(tier or ""):lower()] or tier
	tier = math.max(1, math.min(4, tonumber(tier) or 4))
	HB.Init(info)
	local spot = info.Spots[1]
	local owner = nil
	pcall(function()
		owner = Mock.AddPlayer("HomeOwner", 777001)
	end)
	HB.SetOwner(spot, owner)
	local tierId = TC.HouseTiers[tier].Id
	local home = { Stations = {}, Prestige = (tier == 4) and 1 or 0 }
	for _, def in ipairs(TC.Stations) do
		local cap = def.TierCaps[tierId] or 0
		if def.Id == "House" then
			cap = tier
		end
		if def.ComingSoon and tier < 4 then
			cap = 0
		end
		if cap > 0 then
			home.Stations[def.Id] = math.min(cap, def.MaxLevel)
		end
	end
	local open = (type(TC.GardenSlots) == "function") and TC.GardenSlots(home) or 3
	if type(HB.SetGarden) == "function" then
		HB.SetGarden(spot, {}, open)
	end
	HB.BuildHome(spot, home)
	if extra == "pads" then
		HB.SetPads(spot, TC.AvailablePads(home))
	end
	Mock.Advance(0.2)
	local parts = HB.PartCount(spot)
	return { { root = spot.Folder, label = "Home plot: " .. TC.HouseTiers[tier].Name, sub = "Home folder: " .. parts .. " parts, " .. open .. " garden places", facing = { spot.PlotCFrame.LookVector.X, 0, spot.PlotCFrame.LookVector.Z } } }
end

-- homefree   spot 1 of the real lobby prepared by HomeBuilder.Init but not claimed: the gate's ClaimPrompt anchor and the
--            "FREE HOME" signpost (crop with --box to look at the gate)
BUILDERS.homefree = function()
	local HB = homeBuilder()
	local info = ensureLobby()
	HB.Init(info)
	local spot = info.Spots[1]
	Mock.Advance(0.2)
	return { { root = spot.Folder, label = "Free home plot", sub = "spot 1, unclaimed", facing = { spot.PlotCFrame.LookVector.X, 0, spot.PlotCFrame.LookVector.Z } } }
end

-- homegarden[:<open>[:<level>]] / hometrain[:<level>] (homegym)  (client world) the Pet Garden (default: 12 open
--            places, its top level) with a pet on every open place and a coin pile at each (CoinPiles), or the Training
--            Place (default: its top level) with a pet on every mat (TrainingPets): HomeBuilder builds the plot, the
--            plot attributes name the pets and the real HomeFx draws them (PetBuilder Low)
local function homePetsView(stationId, level, open)
	local HB = homeBuilder()
	local TC = req("shared/TycoonCatalog")
	local PC = req("shared/PetCatalog")
	local Fx = req("client/Controllers/HomeFx")
	local def = TC.Get(stationId)
	level = math.max(1, math.min(def.MaxLevel, tonumber(level) or def.MaxLevel))
	local folder = Instance.new("Folder")
	folder.Name = "Spot_99"
	folder.Parent = Workspace
	local cf = CFrame.new(0, 0, 0)
	local spot = { Index = 99, PlotCFrame = cf, PlotSize = TC.PlotSize, Center = cf.Position, Folder = folder }
	Fx.Init()
	HB.PreparePlot(spot)
	local ids = {}
	for _, d in ipairs(PC.Pets) do
		if #ids < 12 and not d.EventOnly then
			ids[#ids + 1] = d.Id
		end
	end
	local count = level
	if stationId == "Garden" then
		count = math.max(1, math.min(#def.Slot.Spots, tonumber(open) or #def.Slot.Spots))
	end
	local list, valid, piles = {}, {}, {}
	for i = 1, count do
		local key = ids[((i - 1) % #ids) + 1] .. ((i % 3 == 0) and "@Golden" or "")
		valid[i] = key
		if stationId == "Garden" then
			list[#list + 1] = i .. "=" .. key
			piles[#piles + 1] = i .. "=" .. tostring((i % 5) + 1) .. ((i % 4 == 0) and "F" or "") .. ((i % 6 == 0) and "*" or "")
		else
			list[#list + 1] = i .. "=" .. key .. ":" .. ({ "Speed", "Physique", "Ability", "Defense" })[((i - 1) % 4) + 1] .. ":" .. tostring(os.time() + 60 * i)
		end
	end
	if stationId == "Garden" then
		if type(HB.SetGarden) == "function" then
			HB.SetGarden(spot, valid, count)
		end
		folder:SetAttribute("GardenSlots", count)
		folder:SetAttribute("GardenPets", table.concat(list, ";"))
		folder:SetAttribute("CoinPiles", table.concat(piles, ";") .. ";W=5")
	else
		folder:SetAttribute("TrainingPets", table.concat(list, ";"))
		folder:SetAttribute("GymPets", table.concat(list, ";"))
	end
	HB.SetStation(spot, stationId, level)
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 30, -40), Vector3.new(0, 0, 0))
	end
	Mock.Advance(3)
	local view = Instance.new("Model")
	view.Name = stationId .. "View"
	local station = folder.Home:FindFirstChild("Station_" .. stationId)
	if station then
		station:Clone().Parent = view
	end
	local n = 0
	local fx = Workspace:FindFirstChild("ClientFx")
	if fx then
		for _, sub in ipairs(fx:GetChildren()) do
			for _, p in ipairs(sub:GetChildren()) do
				p:Clone().Parent = view
				n = n + 1
			end
		end
	end
	view.Parent = Workspace
	local look = (cf * def.Slot.CFrame).LookVector
	return { { root = view, label = def.Name .. " Lv " .. level .. " with " .. count .. " pets", sub = "HomeFx: " .. n .. " client pieces", facing = { look.X, 0, look.Z } } }
end

BUILDERS.homegarden = function(open, level)
	return homePetsView("Garden", level, open)
end

BUILDERS.hometrain = function(level)
	return homePetsView("Gym", level)
end
BUILDERS.homegym = BUILDERS.hometrain

-- portal:home  (client world) the home portal HomePortalFx (wave 3) draws from the local player's HomePortal attribute
--              ("x,y,z,yaw,closesAt"): everything new in the Workspace after a few frames
BUILDERS.portal = function()
	local Fx = req("client/Controllers/HomePortalFx", true)
	if not Fx or type(Fx.Init) ~= "function" then
		fail("client/Controllers/HomePortalFx.lua (Init) does not exist yet")
	end
	local before = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		before[c] = true
	end
	Fx.Init()
	local lp = game:GetService("Players").LocalPlayer
	if lp then
		local now = Workspace:GetServerTimeNow()
		lp:SetAttribute("HomePortal", string.format("%d,%d,%d,%d,%d", 0, 3, 0, 0, math.floor(now + 10)))
	end
	Mock.Advance(1.0)
	local view = Instance.new("Model")
	view.Name = "PortalView"
	for _, c in ipairs(Workspace:GetChildren()) do
		if not before[c] and c ~= view then
			c:Clone().Parent = view
		end
	end
	view.Parent = Workspace
	return { { root = view, label = "Home portal", sub = "HomePortalFx", facing = { 0, 0, -1 } } }
end

-- Phase 3 (server/Services/ArenaBuilder.lua):
--   arena                the Battle Arena (workspace.BattleArena: island, colosseum, duel rings, boards, the bridge and
--                        the Trial Portal on the plaza) built on the real lobby (+ the Storm Altar when it exists, like
--                        Main does); combine with lobby (lobby+arena) and crop with --box to see the plaza link
--   pocket[:<index>]     one private trial pocket (ArenaBuilder.BuildPocket(index), default 1) far out in the sky
local arenaInfo = nil
local function ensureArena()
	if arenaInfo then
		return arenaInfo
	end
	local info = ensureLobby()
	local StormAltar = req("server/Services/StormAltar", true)
	if StormAltar and type(StormAltar.Build) == "function" and not Workspace:FindFirstChild("StormAltar", true) then
		pcall(StormAltar.Build, info)
	end
	local AB = req("server/Services/ArenaBuilder", true)
	if not AB or type(AB.Build) ~= "function" then
		fail("server/Services/ArenaBuilder.lua (Build) does not exist yet")
	end
	local result = AB.Build(info)
	Mock.Advance(0.2)
	if type(result) ~= "table" or not isInstance(result.Model) then
		fail("ArenaBuilder.Build(lobbyInfo) returned no ArenaInfo with a Model")
	end
	arenaInfo = result
	return result
end

BUILDERS.arena = function()
	local info = ensureArena()
	local look = typeof(info.Center) == "CFrame" and info.Center.LookVector or Vector3.new(0, 0, -1)
	return { { root = info.Model, label = "Battle Arena", sub = "ArenaBuilder.Build(lobbyInfo) (" .. tostring(info.Link) .. " link)", facing = { look.X, 0, look.Z } } }
end

BUILDERS.pocket = function(index, kind)
	local AB = req("server/Services/ArenaBuilder", true)
	if not AB or type(AB.BuildPocket) ~= "function" then
		fail("server/Services/ArenaBuilder.lua (BuildPocket) does not exist yet")
	end
	-- pocket:ring = BuildPocket(1, "Ring"); pocket:<n>[:<kind>]
	if index and not tonumber(index) then
		kind, index = index, nil
	end
	local n = tonumber(index) or 1
	local mode = kind and (tostring(kind):sub(1, 1):upper() .. tostring(kind):sub(2):lower()) or nil
	local pocket = AB.BuildPocket(n, mode)
	Mock.Advance(0.2)
	if type(pocket) ~= "table" or not isInstance(pocket.Model) then
		fail("ArenaBuilder.BuildPocket(" .. n .. ", " .. tostring(mode) .. ") returned no pocket with a Model")
	end
	local title = (mode == "Ring") and "Champion Ring pocket " or "Trial pocket "
	return { { root = pocket.Model, label = title .. n, sub = "ArenaBuilder.BuildPocket(" .. n .. (mode and (", " .. mode) or "") .. ")", facing = { 0, 0, -1 } } }
end

-- Phase 3 bosses (shared/BossBuilder.lua, built from a BattleCatalog boss id):
--   boss:<bossId>[:<pose>[:<detail>]]   one boss, pose Idle (default) | Windup | Attack | Basic | Enrage | Hurt | Down
--                                       at the pose's strongest moment, detail High (default) | Low; pose may be
--                                       "<Pose>/<attackId>" (e.g. Windup/chain) and "<Pose>!" shows it enraged
--   bosses[:<pose>[:<detail>]]          the whole roster side by side
local function bossEntry(bossId, pose, detail)
	local BB = req("shared/BossBuilder", true)
	if not BB or type(BB.Build) ~= "function" then
		fail("shared/BossBuilder.lua (Build) does not exist yet")
	end
	local poseName, attack = tostring(pose or "Idle"), nil
	local enraged = poseName:sub(-1) == "!"
	if enraged then
		poseName = poseName:sub(1, -2)
	end
	local slash = poseName:find("/", 1, true)
	if slash then
		attack = poseName:sub(slash + 1)
		poseName = poseName:sub(1, slash - 1)
	end
	if poseName == "" then
		poseName = "Idle"
	end
	local progress = ({ Windup = 1, Attack = 0.4, Basic = 0.4, Enrage = 0.5, Hurt = 0, Down = 1 })[poseName]
	local d = (detail and detail:lower() == "low") and "Low" or "High"
	local model = BB.Build(bossId, { Detail = d, Pose = poseName, Progress = progress, Attack = attack, Enraged = enraged, PoseTime = 0.6 })
	if not model then
		fail("BossBuilder.Build('" .. tostring(bossId) .. "') returned nil")
	end
	model.Parent = Workspace
	Mock.Advance(0.05)
	return { root = model, label = tostring(bossId), sub = poseName .. (attack and ("/" .. attack) or "") .. (enraged and " enraged" or "") .. "  " .. d .. "  " .. BB.PartCount(model) .. " parts, " .. string.format("%.1f", BB.GetHeight(model)) .. " studs", facing = { 0, 0, -1 } }
end

BUILDERS.boss = function(id, pose, detail)
	if id == nil or id == "" then
		fail("usage: boss:<bossId>[:<pose>[:<detail>]]")
	end
	return { bossEntry(id, pose, detail) }
end

BUILDERS.bosses = function(pose, detail)
	local BB = req("shared/BossBuilder", true)
	if not BB then
		fail("shared/BossBuilder.lua does not exist yet")
	end
	local out = {}
	for i, id in ipairs(BB.Ids()) do
		local e = tryBuild(id, bossEntry, id, pose, detail)
		if e.root then
			e.root:PivotTo(CFrame.new((i - 2.5) * 44, 0, 0))
		end
		out[#out + 1] = e
	end
	return out
end

-- Phase 3 battles (client/Controllers/BattleController.lua, client world):
--   battle[:<trial|duel|raid>[:<seconds>[:specials]]]  a real BattleSim stepped at 10 Hz for <seconds> (default 6; raid
--                        9, when the boss's first telegraph fills) fed to the real BattleController the way BattleService
--                        sends it; the drawn workspace.ClientBattle (units, telegraphs, effects) is dumped. ":specials"
--                        fills the local team's meters and casts every special a moment before the dump (their VFX).
local function battleTeamOf(PC, count, skip)
	local out, kinds = {}, {}
	skip = skip or 0
	for _, def in ipairs(PC.Pets) do
		local sp = type(def.Special) == "table" and def.Special.Kind or nil
		if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
			if skip > 0 then
				skip = skip - 1
			else
				kinds[sp] = true
				out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = 10, Tier = "Normal", Slot = #out + 1 }
				if #out >= count then
					break
				end
			end
		end
	end
	return out
end

BUILDERS.battle = function(mode, seconds, extra)
	local BC = req("client/Controllers/BattleController", true)
	local Sim = req("shared/BattleSim", true)
	local PC = req("shared/PetCatalog")
	if not BC or not Sim then
		fail("client/Controllers/BattleController.lua or shared/BattleSim.lua does not exist yet (client world?)")
	end
	local Players = game:GetService("Players")
	local me = Players.LocalPlayer and Players.LocalPlayer.UserId or 4242
	mode = (mode and mode ~= "") and mode:lower() or "trial"
	local simMode = (mode == "raid") and "Raid" or ((mode == "duel") and "Duel" or "Trial")
	local setup = { Mode = simMode, Seed = 5, Id = "dump_battle" }
	if simMode == "Duel" then
		setup.Teams = { { Owner = me, Side = 1, Pets = battleTeamOf(PC, 4) }, { Owner = 78, Side = 2, Pets = battleTeamOf(PC, 3, 3) } }
	elseif simMode == "Raid" then
		setup.Teams = { { Owner = me, Side = 1, Pets = battleTeamOf(PC, 4) }, { Owner = 77, Side = 1, Pets = battleTeamOf(PC, 3, 2) } }
		setup.Boss = "storm_titan"
	else
		setup.Teams = { { Owner = me, Side = 1, Pets = battleTeamOf(PC, 4) } }
		setup.Trial = 10
	end
	local sim, why = Sim.new(setup)
	if not sim then
		fail("BattleSim.new: " .. tostring(why))
	end
	pcall(BC.Init)
	local id = "dump_battle"
	local d = sim:Describe()
	d.BattleId = id
	d.Zone = { CFrame = CFrame.new(0, 0, 0), Size = Vector3.new(d.Zone.X, 30, d.Zone.Z), X = d.Zone.X, Z = d.Zone.Z }
	d.Names = { [tostring(me)] = "Renderer", ["77"] = "Buddy", ["78"] = "Rival" }
	d.Side, d.Spectator, d.T = 1, false, sim:Time()
	BC.HandleState("Start", d, id)
	local function dense()
		local snap = sim:Snapshot()
		local units, top = {}, 0
		for k in pairs(snap.Units) do
			top = math.max(top, k)
		end
		for k = 1, top do
			units[k] = snap.Units[k] or { x = 0, z = 0, hp = 0, state = 5, meter = 0 }
		end
		snap.Units = units
		snap.BattleId = id
		return snap
	end
	local function step()
		local evs = sim:Step(0.1)
		if #evs > 0 then
			BC.HandleState("Events", evs, id)
		end
		BC.HandleState("Snapshot", dense(), id)
		Mock.Advance(0.1)
	end
	local total = tonumber(seconds) or ((simMode == "Raid") and 9 or 6)
	for _ = 1, math.floor(total / 0.1) do
		step()
	end
	if extra and extra:lower() == "specials" then
		for _, u in ipairs(sim.units or {}) do
			if u.owner == me and u.alive then
				u.meter = 100
			end
		end
		for slot = 1, 4 do
			pcall(sim.Command, sim, me, "Special", slot)
		end
		step()
		step()
		step()
	end
	local folder = Workspace:FindFirstChild("ClientBattle")
	if not folder then
		fail("BattleController drew nothing (no workspace.ClientBattle)")
	end
	local view = Instance.new("Model")
	view.Name = "BattleView"
	for _, c in ipairs(folder:GetChildren()) do
		c:Clone().Parent = view
	end
	view.Parent = Workspace
	local st = BC.GetStats()
	return { { root = view, label = "Battle: " .. simMode, sub = string.format("%d units, %d models, %d fx parts, %d telegraphs (t = %.1f s)", st.Units, st.Models, st.FxParts, st.Telegraphs, sim:Time()), facing = { 0, 0, -1 } } }
end

BUILDERS["storm_altar"] = BUILDERS["storm-altar"]
BUILDERS.stormaltar = BUILDERS["storm-altar"]
BUILDERS.npc = BUILDERS.npcs
BUILDERS.dragon = BUILDERS.skydragon

----------------------------------------------------------------------
-- Phase 5 per-owner target blocks (ARCHITECTURE_V3.md "Phase 5 build contract" 11, C18). Each owner adds its targets
-- to BUILDERS (BUILDERS.<kind> = function(a, b, c) ... return { { root, label, sub, facing } } end) from INSIDE its own
-- block only (own block only; re-read the file right before each edit; never touch another block or the dispatch
-- below). New helpers go into the owner's block too. The lead adds the python-side entries of tools/render_model.py
-- (--list, view presets such as `lobby --views top`) at the gate from the owners' reports.
----------------------------------------------------------------------

-- [owner: worldlobby] begin
-- (lobby with the Gate Court: `lobby` keeps its name; `gates` = the six gates + the court; `gate:<Home|Obby|Dungeon|Ring|Arena|Altar>`)
--   lobby                 LobbyBuilder.Build() + the Gate Court gates of ArenaBuilder (Ring, Arena) and, once it exists,
--                         DungeonBuilder (Dungeon): the whole lobby folder (crop with DUMP.box; render `--views top`)
--   gates                 the Gate Court alone: every gate of LobbyInfo.GatesFolder + the court tiles, terrace, rims and
--                         its dressing (cloned into one folder), facing the plaza
--   gate:<Id>             one gate (Home, Obby, Dungeon, Ring, Arena, Altar) and its pad, facing the plaza
local function worldlobbyLobby()
	local info = ensureLobby()
	if not info._p5GatesBuilt then
		info._p5GatesBuilt = true
		local okA, AB = pcall(req, "server/Services/ArenaBuilder")
		if okA and type(AB) == "table" and type(AB.Build) == "function" then
			pcall(AB.Build, info)
		end
		local okD, DB = pcall(req, "server/Services/DungeonBuilder")
		if okD and type(DB) == "table" and type(DB.Build) == "function" then
			pcall(DB.Build, info)
		end
		Mock.Advance(0.2)
	end
	return info
end

BUILDERS.lobby = function()
	local info = worldlobbyLobby()
	return { { root = info.Folder, label = "Lobby", sub = "LobbyBuilder.Build() + the Gate Court gates", facing = { 0, 0, -1 } } }
end

BUILDERS.gates = function()
	local info = worldlobbyLobby()
	local holder = Instance.new("Folder")
	holder.Name = "GateCourt"
	local plaza = info.Folder:FindFirstChild("Plaza")
	local pieces = { info.GatesFolder }
	if plaza then
		for _, name in ipairs({ "Courts", "GateCourtDecor" }) do
			pieces[#pieces + 1] = plaza:FindFirstChild(name)
		end
	end
	for _, piece in ipairs(pieces) do
		if piece then
			local copy = piece:Clone()
			-- the court only: the spawn court's rings stay out of the picture
			for _, d in ipairs(copy:GetChildren()) do
				if d.Name == "SpawnTile" or d.Name == "SpawnRing" then
					d:Destroy()
				end
			end
			copy.Parent = holder
		end
	end
	local look = info.GateSites and info.GateSites.Ring and info.GateSites.Ring.LookVector or Vector3.new(0, 0, -1)
	return { { root = holder, label = "Gate Court", sub = "the six gates + the court (LobbyInfo.GatesFolder)", facing = { look.X, 0, look.Z } } }
end

BUILDERS.gate = function(id)
	local info = worldlobbyLobby()
	id = tostring(id or "Obby")
	local model = info.GatesFolder and info.GatesFolder:FindFirstChild("Portal_" .. id)
	if not model then
		fail("no Portal_" .. id .. " in the Gate Court")
	end
	local site = info.GateSites and info.GateSites[id]
	local look = site and site.LookVector or Vector3.new(0, 0, -1)
	return { { root = model, label = "Portal_" .. id, sub = "WorldStyle.BuildGate (" .. id .. ")", facing = { look.X, 0, look.Z } } }
end
-- [owner: worldlobby] end

-- [owner: homeworld] begin
-- (home:Press1:<1..40> = the Berry Farm levels and home:<Id>:<level> every other station, through the generic `home`
--  target; homerow:House:1,2,3,4 / homerow:DecorFountain:1,2,3 / homerow:DecorFence:1,2,3 the tiers side by side;
--  homeplot:SkyCastle:pads the whole plot. homegarden[:<open>[:<level>]] = the Pet Garden with its 12 beds (default all
--  open) and the Food Bowl: HomeFx's roaming pets on top when the client HomeFx can draw them, else the HomeBuilder model
--  alone, so the target works before and after the W3 HomeFx rewrite)
do
	local petsView = BUILDERS.homegarden
	BUILDERS.homegarden = function(open, level)
		local HB = homeBuilder()
		local TC = req("shared/TycoonCatalog")
		local def = TC.Get("Garden")
		local beds = (def.Slot and (def.Slot.Beds or def.Slot.Spots)) or {}
		open = math.max(0, math.min(#beds, tonumber(open) or #beds))
		level = math.max(1, math.min(def.MaxLevel, tonumber(level) or def.MaxLevel))
		local ok, out = false, "no HomeFx view"
		if type(petsView) == "function" then
			ok, out = pcall(petsView, open, level)
		end
		if ok and type(out) == "table" then
			return out
		end
		local m = HB.BuildStationModel("Garden", level, nil, open)
		if not m then
			fail("HomeBuilder.BuildStationModel(Garden, " .. level .. ") returned nothing")
		end
		m.Parent = Workspace
		return { {
			root = m,
			label = def.Name .. " Lv " .. level .. "  " .. open .. " open beds + the Food Bowl",
			sub = "HomeBuilder (no HomeFx pets yet)",
			facing = { 0, 0, -1 },
		} }
	end
end
-- [owner: homeworld] end

-- [owner: dungeon] begin
-- (dungeon:portal, dungeon:room:<kind>, dungeon:boss, dungeon:run:<floor> = a built run of 4 rooms)
-- [owner: dungeon] end

-- [owner: arenaart] begin
-- (arena, arena:ring, pocket:ring after the 6.4 art pass; the trial pocket is gone)
-- [owner: arenaart] end

----------------------------------------------------------------------
-- main
----------------------------------------------------------------------
local target = tostring(ARGS.target or "")
if target == "" then
	fail("no target (DUMP.target)")
end
local box = nil
if type(ARGS.box) == "table" or (type(ARGS.box) == "userdata") then
	local b = {}
	for i = 1, 6 do
		b[i] = tonumber(ARGS.box[i])
	end
	if b[6] then
		box = b
	end
end

local entries = {}
for _, piece in ipairs(split(target, "+")) do
	local fields = split(piece, ":")
	local kind = (fields[1] or ""):lower()
	local builder = BUILDERS[kind]
	if not builder then
		local names = {}
		for k in pairs(BUILDERS) do
			names[#names + 1] = k
		end
		table.sort(names)
		fail("unknown target '" .. piece .. "'. Known: " .. table.concat(names, ", "))
	end
	local built = builder(fields[2], fields[3], fields[4])
	for _, e in ipairs(built) do
		entries[#entries + 1] = e
	end
end

local chunks = {}
local summary = {}
for i, e in ipairs(entries) do
	local parts, uncropped = {}, 0
	if e.root then
		parts, uncropped = collectParts(e.root, box)
	end
	local lines = {}
	for j, p in ipairs(parts) do
		lines[j] = partJson(p, e.root)
	end
	-- total = BaseParts in this dump (after the crop), all = BaseParts of the whole model
	chunks[i] = table.concat({
		"{\"label\":", str(e.label or (e.root and e.root.Name) or "?"),
		",\"sub\":", str(e.sub or ""),
		",\"root\":", str(e.root and e.root.Name or ""),
		",\"facing\":", arr(e.facing or { 0, 0, -1 }),
		",\"total\":", tostring(#parts),
		",\"all\":", tostring(uncropped),
		",\"parts\":[\n", table.concat(lines, ",\n"), "]}",
	})
	summary[#summary + 1] = tostring(e.label or (e.root and e.root.Name) or "?") .. ": " .. #parts .. " parts"
end

local json = "{\"target\":" .. str(target) .. ",\"box\":" .. (box and arr(box) or "null") .. ",\"models\":[\n" .. table.concat(chunks, ",\n") .. "\n]}\n"

if ARGS.out and ARGS.out ~= "" then
	local fh, err = io.open(tostring(ARGS.out), "w")
	if not fh then
		fail("cannot write " .. tostring(ARGS.out) .. ": " .. tostring(err))
	end
	fh:write(json)
	fh:close()
end

return json, table.concat(summary, "; ")
