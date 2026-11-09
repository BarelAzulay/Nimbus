-- LobbyMachineBuilder (shop-area 2026-11-09, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.17.1): the shop's
-- roulette machine card A "Gumball Globe" (the mesh key prop_roulette_globe, blender/kit/props/lobby_machine.py) and the
-- real eggs piled inside its glass. LobbyBuilder's main chunk is near its local cap, so the machine's new pieces live
-- here (one local there); LobbyBuilder.buildMachine tags the globe key and calls GlobeEggs only when that tag dressed.
--
--   LobbyMachineBuilder.GLOBE = { Key = "prop_roulette_globe", Count = 18, Chase = 1, Scale = 0.5, ChaseScale = 0.54,
--                                 EggSize = Vector3.new(2.25, 3, 2.5) }   (polish 2026-11-09: was 12 at 0.42 / 0.44)
--   LobbyMachineBuilder.SECRET_EMBLEM = white-gold 255,240,200: the Celestial machine's star (its top rarity is Secret)
--   LobbyMachineBuilder.EggKey(rarity, pile) -> "egg_<rarity>" (the chase egg) | "egg_<rarity>_low" (pile) | nil
--   LobbyMachineBuilder.Rarities(roulette, count) -> { rarity id }
--     Pure (no Instances). [1] = the roulette's top rarity (the last of its odds > 0 in Config.Rarities order: the chase
--     egg), [2..count] = the pile of its lower rarities by weight: n_r = max(1, floor((count - 1) * w_r / sum + 0.5)),
--     then the largest n drops by one while the sum is over count - 1 and the most common rarity gains one while it is
--     under; interleaved by cycling the lower rarities in Config order, one of each while any is left. At 18: Cloud: Epic
--     + C U R C U R C U C U C U C C C C C; Storm: Legendary + U R E U R E U R E U R E U R U R R; Sky: Mythic + R E L R E L
--     R E L R E R E R E E E; Celestial: Secret + E L M E L M E L M E L E L E L E L. One rarity -> that egg everywhere;
--     none -> {}.
--   LobbyMachineBuilder.GlobeEggs(parent, cf, roulette, H) -> Model "GlobeEggs" | nil
--     cf = the machine's ground CFrame (the globe key's pivot, front -Z). Reads the globe manifest's Egg1..Egg18
--     attachments (pos = the egg's bottom centre in machine studs, rot = its turn) through MeshLibrary.Manifest and builds,
--     as a child of `parent` (the Roulette_<Id> model, beside its Machine: never inside the dressed body), one Model
--     GlobeEgg<i> per attachment holding one Part "Egg": the Part fallback (a block with a Sphere SpecialMesh, 2.25 x 3 x
--     2.5 x the scale, in the rarity colour, Secret dark with the shelf egg's violet tint, SmoothPlastic, anchored, no
--     collide / touch / query) standing on the pivot; the Model's WorldPivot = cf * the attachment, its attribute
--     ML_Scale = Scale (ChaseScale on GlobeEgg1: MeshLibrary.Dress assembles the mesh at that size about the pivot), then
--     H.Mesh.tag(model, EggKey(rarity, i ~= 1), pivot): the chase egg on the uploaded egg_<rarity>, the pile on
--     egg_<rarity>_low (polish 2026-11-09, review round 2's perf finding: the full keys would put 68 x ~3.4k tris in the
--     shop); ML_DressKey only where that key is not missing, so until the low eggs are uploaded the pile shows its Part
--     spheres. GlobeEgg2..18 are tagged H.Detail (NC_Detail: the Low graphics setting parks the pile; the chase egg always
--     shows); nothing is tagged Spin (a still pile). A manifest that is missing, or lacks an Egg<i> attachment, warns once
--     per manifest ("[LobbyMachineBuilder] prop_roulette_globe: no Egg<i> attachment" / "...: no manifest") and returns
--     nil: the machine stands without its eggs.
--     H = LobbyBuilder's L.H (box, Mesh, C, MAT, Detail).
--   LobbyMachineBuilder._Manifest  TESTS ONLY: a function(key) -> manifest used instead of MeshLibrary.Manifest (nil = real)
-- No light, no prompt, no animation (the server never animates). Plain Lua 5.1 syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LobbyMachineBuilder = {}

-- polish 2026-11-09: 18 eggs (the 12 read ~25 % full) at 0.5, the chase egg 0.54 (blender/kit/props/lobby_machine.py
-- EGG_SPOTS, poured by blender/pitches/shop_area_globe.py --settle onto the globe's cloud bed)
local GLOBE = {
	Key = "prop_roulette_globe", -- the mesh key, literal (tools/mesh_keys.py reads the keys from the source)
	Count = 18,
	Chase = 1,
	Scale = 0.5,
	ChaseScale = 0.54,
	EggSize = Vector3.new(2.25, 3, 2.5), -- the shelf egg's Part size (LobbyBoardBuilder EGG.Size)
}
LobbyMachineBuilder.GLOBE = GLOBE

-- the Celestial machine's emblem (polish: white-gold; the chat violet 180,150,255 was a near twin of Cloud's Epic lavender)
LobbyMachineBuilder.SECRET_EMBLEM = Color3.fromRGB(255, 240, 200)

-- the egg mesh keys, literal: the chase egg wears the full uploaded egg (LobbyBoardBuilder EGG_KEYS, ~3-3.7k tris); the
-- pile wears the low egg (polish: egg_<rarity>_low, a few hundred tris, one part; 68 full eggs would be ~230k tris).
-- With no id for a key its egg stays the rarity-tinted Part sphere (Mesh.tag leaves it undressed)
local EGG_KEYS = {
	Common = "egg_common",
	Uncommon = "egg_uncommon",
	Rare = "egg_rare",
	Epic = "egg_epic",
	Legendary = "egg_legendary",
	Mythic = "egg_mythic",
	Secret = "egg_secret",
}
local LOW_KEYS = {
	Common = "egg_common_low",
	Uncommon = "egg_uncommon_low",
	Rare = "egg_rare_low",
	Epic = "egg_epic_low",
	Legendary = "egg_legendary_low",
	Mythic = "egg_mythic_low",
	Secret = "egg_secret_low",
}

-- the dress key of an egg of `rarity`: the pile's low egg when `pile`, else the full egg (nil for an unknown rarity)
function LobbyMachineBuilder.EggKey(rarity, pile)
	return (pile and LOW_KEYS or EGG_KEYS)[rarity]
end
-- the Secret egg's Part colour: its near-black body with the violet glow (LobbyBoardBuilder SECRET, the shelf egg's)
local SECRET_EGG = Color3.fromRGB(40, 40, 52):Lerp(Color3.fromRGB(138, 92, 255), 0.18)
local DETAIL = "NC_Detail"

LobbyMachineBuilder._Manifest = nil

-- the rarities a roulette can pay, in Config.Rarities order
local function oddsList(roulette)
	local out = {}
	local odds = type(roulette) == "table" and type(roulette.Odds) == "table" and roulette.Odds or {}
	for _, r in ipairs(Config.Rarities) do
		local w = tonumber(odds[r.Id]) or 0
		if w > 0 then
			out[#out + 1] = { Id = r.Id, W = w, Color = r.Color }
		end
	end
	return out
end

function LobbyMachineBuilder.Rarities(roulette, count)
	count = math.max(0, math.floor(tonumber(count) or GLOBE.Count))
	local have = oddsList(roulette)
	local out = {}
	if #have == 0 or count == 0 then
		return out
	end
	local top = have[#have]
	out[1] = top.Id
	local lower = {}
	for i = 1, #have - 1 do
		lower[i] = have[i]
	end
	local m = count - 1
	if #lower == 0 then
		for i = 2, count do
			out[i] = top.Id
		end
		return out
	end
	local sum = 0
	for _, r in ipairs(lower) do
		sum = sum + r.W
	end
	local n, total = {}, 0
	for i, r in ipairs(lower) do
		n[i] = math.max(1, math.floor(m * r.W / sum + 0.5))
		total = total + n[i]
	end
	while total > m do
		local big = 1
		for i = 2, #n do
			if n[i] > n[big] then
				big = i
			end
		end
		n[big] = n[big] - 1
		total = total - 1
	end
	while total < m do
		n[1] = n[1] + 1
		total = total + 1
	end
	local left = total
	while left > 0 do
		for i, r in ipairs(lower) do
			if n[i] > 0 then
				out[#out + 1] = r.Id
				n[i] = n[i] - 1
				left = left - 1
			end
		end
	end
	return out
end

-- one warn per manifest (the four machines read the same one)
local warned = setmetatable({}, { __mode = "k" })
local NO_MANIFEST = {}
local function warnOnce(man, msg)
	local key = type(man) == "table" and man or NO_MANIFEST
	warned[key] = warned[key] or {}
	if warned[key][msg] then
		return
	end
	warned[key][msg] = true
	warn(msg)
end

-- a manifest attachment { Pos = {x, y, z}, Rot = {{...}, {...}, {...}} } -> its CFrame in machine space, nil if malformed
local function frameOf(a)
	local pos = type(a) == "table" and (a.Pos or a.pos)
	local rot = type(a) == "table" and (a.Rot or a.rot)
	if type(pos) ~= "table" or type(rot) ~= "table" or type(rot[1]) ~= "table" or type(rot[2]) ~= "table" or type(rot[3]) ~= "table" then
		return nil
	end
	local v = { pos[1], pos[2], pos[3], rot[1][1], rot[1][2], rot[1][3], rot[2][1], rot[2][2], rot[2][3], rot[3][1], rot[3][2], rot[3][3] }
	for i = 1, 12 do
		if type(v[i]) ~= "number" then
			return nil
		end
	end
	return CFrame.new(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
end

local function eggColour(id)
	if id == "Secret" then
		return SECRET_EGG
	end
	for _, r in ipairs(Config.Rarities) do
		if r.Id == id then
			return r.Color
		end
	end
	return Color3.fromRGB(200, 200, 210)
end

local function manifest(H)
	local get = LobbyMachineBuilder._Manifest
	if type(get) ~= "function" then
		local lib = type(H.Mesh) == "table" and type(H.Mesh.lib) == "function" and H.Mesh.lib() or nil
		get = lib and lib.Manifest
	end
	if type(get) ~= "function" then
		return nil
	end
	local ok, man = pcall(get, GLOBE.Key)
	return ok and type(man) == "table" and man or nil
end

function LobbyMachineBuilder.GlobeEggs(parent, cf, roulette, H)
	if typeof(parent) ~= "Instance" or typeof(cf) ~= "CFrame" or type(roulette) ~= "table" or type(H) ~= "table" or type(H.box) ~= "function" then
		return nil
	end
	local man = manifest(H)
	local att = man and (man.Attachments or man.attachments)
	if type(att) ~= "table" then
		warnOnce(man, "[LobbyMachineBuilder] " .. GLOBE.Key .. ": no manifest")
		return nil
	end
	local frames = {}
	for i = 1, GLOBE.Count do
		frames[i] = frameOf(att["Egg" .. i])
		if not frames[i] then
			warnOnce(man, "[LobbyMachineBuilder] " .. GLOBE.Key .. ": no Egg" .. i .. " attachment")
			return nil
		end
	end
	local seq = LobbyMachineBuilder.Rarities(roulette, GLOBE.Count)
	if #seq < GLOBE.Count then
		return nil -- a roulette without odds: nothing to show
	end
	local detail = type(H.Detail) == "string" and H.Detail or DETAIL
	local smooth = H.MAT and H.MAT.SmoothPlastic or Enum.Material.SmoothPlastic
	local model = Instance.new("Model")
	model.Name = "GlobeEggs"
	for i = 1, GLOBE.Count do
		local id = seq[i]
		local s = (i == GLOBE.Chase) and GLOBE.ChaseScale or GLOBE.Scale
		local pivot = cf * frames[i]
		local size = GLOBE.EggSize * s
		local egg = Instance.new("Model")
		egg.Name = "GlobeEgg" .. i
		local part = H.box(egg, "Egg", pivot * CFrame.new(0, size.Y / 2, 0), size, eggColour(id), { Material = smooth, Shadow = false })
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		local shape = Instance.new("SpecialMesh")
		shape.MeshType = Enum.MeshType.Sphere -- the ellipsoid of the block's size
		shape.Parent = part
		egg.WorldPivot = pivot
		-- the size first, then the tag: a client that sees the dress tag reads ML_Scale with it
		egg:SetAttribute("ML_Scale", s)
		local key = LobbyMachineBuilder.EggKey(id, i ~= GLOBE.Chase)
		if type(H.Mesh) == "table" and type(H.Mesh.tag) == "function" and key then
			H.Mesh.tag(egg, key, pivot)
		end
		if i ~= GLOBE.Chase then
			CollectionService:AddTag(egg, detail)
		end
		egg.Parent = model
	end
	model.WorldPivot = cf
	model.Parent = parent
	return model
end

return LobbyMachineBuilder
