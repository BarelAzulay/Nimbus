-- smoke_lobby_shop_world.lua: the lobby-shop world (docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.9 / 5.6 / 5.11 /
-- 16.3 / 16.5; plan docs/superpowers/plans/2026-11-07-lobby-shop.md Tasks 10 / 12 / 13 / 14 / 17 / 23 / 25). Server world only (booted):
--   lobby_trove_plaza  the Sky Trove on the plaza lawn at spot C (spec 16.2, Task 17): its centre at polar 165 degrees r 50
--                      from Config.Lobby.Origin (+-0.5), facing the plaza centre, <= 60 parts, the sign post at local x
--                      -6.2 (the walk side), the PromptPart in front, LobbyInfo.Shop.ItemShop = { PromptPart, Center,
--                      Model, Lid }; its neighbours (spec 16.2's table): the Guide board >= 12.5 studs, both west benches
--                      >= 10 and within 0.5 of each other (it stands between them), every other bench >= 10, every NPC spot
--                      >= 11.5, every lawn flower bed >= 10.5, the west cross walk's centre line >= 11.5, the spawn court's
--                      centre >= 42.5; the sign's Footing >= 0.5 stud outside the west walk (half width 5) and off every
--                      Paths / PathBorders cell; the Join sign (JoinAnchor 10.5
--                      studs up, JoinBillboard): "Group rewards coming soon!" at GroupId 0, "Join the group!" over "2,000
--                      Cash + 200 Tokens" when rebuilt with GroupId 123, tagged NC_Bob (BobStuds 0.5, BobSeconds 2.4); the
--                      forced fallback shop (LobbyBuilder._ForceShopFallback) puts its trove on the same plaza spot, facing
--                      the centre; one
--                      SkyTrove in a lobby either way; the TroveGroupDone attribute (a stored claim after the load and after
--                      a provisional load's recovery, at the claim, never for a player without the claim); the egg row
--                      (checkEggRow, shop-area 16.17.2) in front of the WINGED PETS board; the dress requests name
--                      egg_common .. egg_secret on the Egg_<Rarity> parts at the egg's bottom centre; ML_DressKey only
--                      where MeshLibrary.Status(key) ~= "missing" (in --mesh the scenario gives the egg keys fixture
--                      holders, so the check runs there); the rarity board's subtitle; no "plaza decor skipped" warn in
--                      any build; every lobby light within the light rule
--   altar_gate         the Storm Altar gate on the plaza (5.11 (a)): LobbyInfo.Gates.Altar.Pad is a walkable 14 x 0.6 x 14
--                      Pad 14 studs in front with the Obby pad's inlay / rim / lantern parts (same names and counts); the
--                      tag reads "Storm Altar" / "Secret pets" with the Pill "Secret Roulette"; VortexBoost 1.4 on the
--                      model (none on the Obby gate); ReturnCFrame 14..21 studs along the LookVector, 3 +- 0.1 over the pad
--                      top (its highest part), looking out; nothing else solid on the pad; standing on it for 3 s
--                      teleports nobody; Portal_Altar keeps ML_DressKey gate_altar; a rebuild with WorldStyle.BuildGate
--                      failing takes Gates.Fallback, whose Altar gate has the pad, the Pill text, the attribute and the
--                      same ReturnCFrame rule
--   altar_portal_glow  the altar portals (5.11 (b) (c)): Model PortalGlow beside an untouched Portal (its children as
--                      before, its prop_altar_portal LayoutSig matches, ML_DressKey wherever that key is not missing:
--                      the default run): a Neon GlowDisc (crystal cyan, union radius <= 6.0, top 0.06
--                      over the old disc top) with a lighter GlowHeart, GlowRing (16 cyan Neon segments on r 6.0, 0.35 over
--                      the disc top, pivot = the disc centre on the disc top, NC_Spin with SpinSeconds 6), a sky Beam
--                      (0.5 -> 160 studs up, FaceCamera, no texture, cyan -> white, transparency 0.2 -> 1, width 3 -> 1),
--                      sparkles, one PointLight 1.5 / 24; the standing return ring: GetReturnPad() = ReturnPrompt with one
--                      PointLight 1.3 / 14 (no ReturnGlow), the two collidable Pad octagons the only colliders, Ring = 13
--                      green Neon segments on one ring 4.5 up over the pad facing the walk from the dais (the bridge's
--                      centre line 14 studs out: the plan's "facing the altar" does not fit between the island's rim
--                      clouds, the stone ring and the edge) + two stone feet outside the 4x6x4 box over the pad, every
--                      ReturnPortal part (rotated bounds) and the portal_ring mesh's bounds >= 4.25 studs off the bridge's
--                      centre line, within the deck and outside the landing box, the mesh's bounds clear of the rim clouds
--                      and the stone ring, nothing collidable but the pads over the pad, the PlazaGatePrompt E / 8, the
--                      sign "To the Plaza" (a pixel
--                      BillboardGui on the Part fallback; shop-area polish: the dressed mesh's 4 x 1 board reads
--                      "Plaza" at 0.96 stud, the World text rule's ~1-stud title); the altar <= 500 parts, its lights within the lobby rule; the
--                      portal_altar_ring manifest (Task 29) against the built altar: seated (its foot reaches into the old
--                      disc), inside the Portal rim's nearest stone face as it turns (a 16-gon: half extent / cos 11.25),
--                      no taller than the Part ring, one Fixed SmoothPlastic part + Neon Glow* parts, GlowBar the ring's
--                      cyan; a rebuild with StormAltar._Kit (and, in the default run, the portal_ring tag forced to
--                      "dressed"; in --mesh fixture holders for portal_ring and portal_altar_ring): the portal_altar_ring
--                      request on GlowRing at the disc centre on the disc
--                      top, the portal_ring request on ReturnPortal.Ring (origin Y = the octagons' top - 1.05, the ring's
--                      facing, Look.Primary the Return green), the mesh-side sign (a SurfaceGui at 50 px per stud on a
--                      SignFace part at the manifest's SignFace), ML_DressKey only where the key is not missing
--   altar_world_gem    the world gem (5.7): Model WorldGem whose one Part fallback Gem is a 4x4x4 Glass block in
--                      rgb(84,196,246) turned 45 degrees on X and Z (anchored, no collide / touch), the model's pivot upright
--                      at its centre, NC_Spin with SpinSeconds 8 / BobStuds 0.6 / BobSeconds 3; shop-area 16.17.4 (spot 2
--                      "Side crystal"): the centre 15.0 studs over the deck straight above the medium crystal (ring index
--                      HEAD +- 3 at r 12.2) on the side away from the return ring, the cube's lowest corner >= 2 over the
--                      crystal's tip (>= 1.4 at the bob's bottom, the gem_world mesh's bounds >= 2), the stone ring / the
--                      crystal straight below (never open deck), outside the
--                      8-stud bridge lane (rotated, turning, and the gem_world mesh's bounds), >= 12 studs from every prompt
--                      part, clear of every other altar part while it turns and bobs; one cyan PointLight 1.0 / 12; the altar
--                      <= 500 parts with its lights in the rule; a rebuild with StormAltar._Kit: one gem_world request on
--                      WorldGem at the gem CFrame, ML_DressKey only where the key is not missing (--mesh: a fixture holder)
--   shop_prompt        the walk-up Shop prompt (spec 16.3, Task 23; shop-area 16.17.2): the egg row's PromptPart (invisible,
--                      not colliding, 5 x 4 x 3) at the WINGED PETS board's cf * (0, 2, -5.6) (+-0.1); LobbyInfo.Shop.Counter
--                      = { PromptPart, Center = the board's Face, Model = the EggRow } (Roulettes / ItemShop unchanged); one
--                      ShopPrompt on it ("Open" / "Shop",
--                      HoldDuration 0, range 10, no line of sight), the only one in the workspace; a trigger fires one
--                      OpenPanel("Shop", { Tab = "Eggs" }) to that player, a second within PROMPT_COOLDOWN none, InMatch
--                      none, junk triggers nothing; no Counter -> no prompt and one warn; the lobby rebuilt -> exactly one
--                      ShopPrompt, on the new part (PetService.Init with the new LobbyInfo, as a rebuild does); the forced
--                      fallback shop's own Counter carries it; the arch sign reads "eggs & gems"; the four machine prompts
--                      unchanged; the booted lobby's prompts are put back at the end
--   egg_shelf_fx       the shelf's VFX (spec 16.5 "The world eggs", Task 26): Rare .. Secret eggs each hold one sparkle
--                      ParticleEmitter (Rate 1 / 2 / 3 / 4 / 5, the rarity colour, Secret the egg's violet; LightEmission
--                      0.5, Lifetime 1.2-2, Speed 0.3-0.8; tagged NC_Detail; on an Attachment Center at the egg's
--                      middle, so the Part fallback and a dressed mesh share it), Common and Uncommon none; one PointLight
--                      EggShelfGlow 1.0 / 10 at the shelf's centre; every lobby light within the light rule; no part
--                      added to the egg row (shelf + seven eggs + PromptPart); the trove <= 60 parts; the same on a
--                      rebuilt lobby
--   shop_globe         the Gumball Globe (shop-area T1, spec 16.17.1): LobbyMachineBuilder.GLOBE / Rarities (the four
--                      sequences, top first) / GlobeEggs / EggKey / SECRET_EMBLEM; the prop_roulette_globe manifest
--                      (Egg1..Egg18, Meta.eggScale 0.5 / chaseScale 0.54, inside 9 x 14.5 x 7, <= 4000 tris, the eight
--                      parts, glass 0.80, every egg's middle inside the glass, pivots >= 0.9 apart, the chase egg in
--                      front; shop-area polish: 18 eggs, the pile on the low-poly egg_<rarity>_pile keys, the chase egg on
--                      the full key); the default run (no globe id) = today's machine,
--                      the uploaded prop_roulette cabinet (review round 1: ML_DressKey prop_roulette in the roulette colour
--                      with f17dc0d's look; --mesh, whose fixture has no prop_roulette id: the Part build), no GlobeEggs, no
--                      warn; one prop_roulette_globe request per Machine (origin, Look.Primary = the roulette colour,
--                      Look.Secondary = its top rarity's) and after it one prop_roulette request, the price card / DomeGlow /
--                      PromptPart unchanged; dressed (--mesh: fixture holders; default: the tag forced) -> no prop_roulette
--                      request, GlobeEggs of eighteen egg Models
--                      at the attachments (ML_Scale, NC_Detail on 2..18, Egg1 egg_<rarity>, the pile egg_<rarity>_pile, in
--                      order); a manifest
--                      without Egg7 -> one warn, no GlobeEggs, the machines stand
--   shop_egg_row       the egg row under WINGED PETS (shop-area T2, spec 16.17.2): no EggGuide anywhere, one Model EggRow
--                      at the board's frame (at(23, -10) on the lawn since shop-area polish (was at(21, -8)), facing the
--                      shop centre, every egg >= 2 studs from the Cloud machine's 9 x 7 footprint): EggShelf (the shelf numbers
--                      of EGGROW below) with the seven Egg_<Rarity> eggs at Step 2.7 (Common at the reader's left), the
--                      turntable tags, the sparkles, the egg_<rarity> requests; the RarityStrip SurfaceGui on the shelf's
--                      front (50 px per stud, LightInfluence 0, a Navy Band at 0.2, seven Label_<Rarity> 135 x 40 px under
--                      their eggs, 30 px Body text in the rarity colour (Secret 178,150,255) with the INK outline, no
--                      TextScaled; measured with Roblox's BuilderSans-Bold no two labels meet and each stays on the
--                      canvas); one EggShelfGlow; the PromptPart at cf * (0, 2, -5.6); LobbyInfo.Shop.Counter = { that
--                      part, Center = the board's Face, Model = EggRow } with its one ShopPrompt; the WINGED PETS board's
--                      letters and pills end above y 3.9 (<= 375 of 450 px), the subtitle right-aligned in the header row;
--                      the eggs >= 3 studs from every roulette prompt, the row clear of every other shop prop; the right
--                      lawn (at(-21, -8)) empty but for lamps / flower beds (unchanged by the polish move); the same on a rebuilt lobby and the forced
--                      fallback shop keeps its ShopCounter
-- Rebuilds follow smoke_p6_lobby.lua: the booted lobby is set aside (renamed) and put back, the hooks (_Kit,
-- _ForceShopFallback), Config.Trove.GroupId, the Meadow stats and the fixture holders restored in every path.
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local K = _G.K
local fmt = string.format
local CS = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local MESH_MODE = (os and os.getenv and os.getenv("NC_MESH_FIXTURES") == "1") or false
local ALLOWED_WARNINGS = { "[DataService]", "[MeshLibrary]", "[LobbyBuilder] shop failed: forced" }
local EGG_KEYS = {
	Common = "egg_common", Uncommon = "egg_uncommon", Rare = "egg_rare", Epic = "egg_epic",
	Legendary = "egg_legendary", Mythic = "egg_mythic", Secret = "egg_secret",
}
local LAWN = 0.4
-- spot C (spec 16.2): polar 165 degrees, r 50 (plaza-local x -48.30, z 12.94); the plazaSpot clearances it must keep
local TROVE_DEG, TROVE_R = 165, 50
local TROVE_NEED = { Guide = 12.5, Bench = 10, BenchPair = 0.5, Npc = 11.5, Bed = 10.5, Walk = 11.5, Court = 42.5, Footing = 0.5 }
local WALK_HALF = 5 -- G.PathHalf: the cross walks' half width, border included
local SOON_TEXT = "Group rewards coming soon!"
local RARITY_SUB = "Every egg hatches a pet of its rarity"
-- the egg row under the WINGED PETS board (shop-area spec 16.17.2): the shelf, the egg step, the label strip, the prompt
-- part's offset and the board's 450 px canvas with its 375 px line (the eggs in front stand 3.8 studs tall: every letter
-- ends above y 3.9 = (11.4 - 3.9) x 50 px from the face's top). TextW: the labels' widths at 30 px measured with Roblox's
-- own BuilderSans-Bold (content/fonts; Theme's Body face), the gap rule's input; Outline = signText's INK stroke at 30 px.
local EGGROW = {
	Shelf = Vector3.new(19.3, 0.8, 2.6), ShelfZ = -3, ShelfX = 1.35, EggsX = 1.0, Step = 2.7, EggSize = Vector3.new(2.25, 3, 2.5),
	PPS = 50, StripH = 40, Cell = 135, Text = 30, BandAlpha = 0.2, Navy = Color3.fromRGB(34, 42, 76),
	SecretText = Color3.fromRGB(178, 150, 255), MinGap = 6, Outline = 2, UnderEgg = 30,
	TextW = { Common = 126, Uncommon = 161, Rare = 65, Epic = 59, Legendary = 151, Mythic = 98, Secret = 91 },
	Prompt = Vector3.new(0, 2, -5.6), PromptSize = Vector3.new(5, 4, 3),
	CanvasH = 450, MaxBottom = 375, HeaderTop = 60, RowTop = 68,
	Glow = { Brightness = 1.0, Range = 10, Lift = 1.5 },
	MachineGap = 3, PropGap = 0.3, RightLawn = 6,
	MachineClear = 2.0, MachineFoot = Vector3.new(9, 1, 7), -- polish: the row's clear gap to every machine
	Board = Vector2.new(23, -10), -- polish: the WINGED PETS board's spot at(x, z) (was at(21, -8): the row's Secret end 0.44 stud off the Cloud machine)
}

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local function req(path)
	local inst = K.moduleInstance(path)
	if not inst then
		return nil
	end
	local ok, m = pcall(require, inst)
	return (ok and type(m) == "table") and m or nil
end

local function hdist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function near(a, b, tol)
	return (a - b).Magnitude <= (tol or 0.05)
end

-- --mesh: fixture holders (a Folder named after the key: Status -> "loading") for `keys` (a list or a map's values),
-- put into EVERY P6PetsMeshLibrary folder, each removal pushed on `undo`. P6.Install never destroys the folder before it,
-- so after a scenario that re-installs (p6lobby_server) the first one found is stale while the library reads the newest
-- (shop-area review round 1: such a run order left the globe and the egg row undressed). -> the number of folders
local function fixtureHolders(keys, undo)
	local list = {}
	for _, k in pairs(keys) do
		list[#list + 1] = k
	end
	table.sort(list)
	local n = 0
	for _, root in ipairs(RS:GetChildren()) do
		if root.Name == "P6PetsMeshLibrary" then
			n = n + 1
			for _, key in ipairs(list) do
				if not root:FindFirstChild(key) then
					local h = Instance.new("Folder")
					h.Name = key
					h.Parent = root
					undo[#undo + 1] = function()
						h:Destroy()
					end
				end
			end
		end
	end
	return n
end

-- no fixture holder for `key` left in any P6PetsMeshLibrary folder
local function holdersGone(key)
	for _, root in ipairs(RS:GetChildren()) do
		if root.Name == "P6PetsMeshLibrary" and root:FindFirstChild(key) then
			return false
		end
	end
	return true
end

local function sameColor(a, b)
	return math.abs(a.R - b.R) < 0.006 and math.abs(a.G - b.G) < 0.006 and math.abs(a.B - b.B) < 0.006
end

local function countParts(root)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

local function polar(deg, r)
	local o = K.config().Lobby.Origin
	return Vector3.new(o.X + math.cos(math.rad(deg)) * r, o.Y, o.Z + math.sin(math.rad(deg)) * r)
end

-- LobbyBuilder's shop frame: centre = Origin + ShopOffset on the walking height, -Z towards the plaza centre
local function shopFrame()
	local L = K.config().Lobby
	local o = L.Origin
	local S0 = Vector3.new(o.X + L.ShopOffset.X, o.Y, o.Z + L.ShopOffset.Z)
	return CFrame.lookAt(S0, S0 + flat(o - S0).Unit), S0
end

-- the WINGED PETS board's ground frame (shop-area 16.17.2: the egg row stands in front of it): at(EGGROW.Board) on the lawn,
-- its front (-Z) towards the shop centre
local function boardFrame()
	local shopCF, S0 = shopFrame()
	local pos = (shopCF * CFrame.new(EGGROW.Board.X, 0, EGGROW.Board.Y)).Position - Vector3.new(0, LAWN, 0)
	local target = S0 - Vector3.new(0, LAWN, 0)
	return CFrame.lookAt(pos, pos + flat(target - pos).Unit)
end

-- the right lawn's spot at(-21, -8) (shop-area 16.17.2: empty but for its lamp and flower bed)
local function rightLawn()
	local shopCF = shopFrame()
	return (shopCF * CFrame.new(-21, 0, -8)).Position
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

-- the four XZ corners of a part's footprint (parts here turn about Y only)
local function corners(p)
	local out = {}
	local hx, hz = p.Size.X / 2, p.Size.Z / 2
	for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		out[#out + 1] = (p.CFrame * CFrame.new(c[1] * hx, 0, c[2] * hz)).Position
	end
	return out
end

-- horizontal distance from a point to a part's footprint rectangle
local function pointToRect(pt, p)
	local l = p.CFrame:PointToObjectSpace(Vector3.new(pt.X, p.Position.Y, pt.Z))
	local dx = math.max(math.abs(l.X) - p.Size.X / 2, 0)
	local dz = math.max(math.abs(l.Z) - p.Size.Z / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- horizontal gap between two parts' footprints (convex: the nearest point is a corner of one of them)
local function rectGap(a, b)
	local best = math.huge
	for _, c in ipairs(corners(a)) do
		best = math.min(best, pointToRect(c, b))
	end
	for _, c in ipairs(corners(b)) do
		best = math.min(best, pointToRect(c, a))
	end
	return best
end

local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") then
			out[#out + 1] = d
		end
	end
	return out
end

local function skippedWarns(from)
	local out = {}
	for i = (from or 0) + 1, #Mock.Output do
		local o = Mock.Output[i]
		if string.find(tostring(o.text), "plaza decor skipped", 1, true) then
			out[#out + 1] = o.text
		end
	end
	return out
end

local function troveOf(root)
	local found = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") and d.Name == "SkyTrove" then
			found[#found + 1] = d
		end
	end
	return found
end

-- a second LobbyBuilder.Build() next to the booted lobby (set aside, put back): setup(undo) may push restore functions
local function rebuild(label, setup, inspect)
	local LB = req("server/Services/LobbyBuilder")
	local live = workspace:FindFirstChild("NimbusLobby")
	if not T.check(LB ~= nil and live ~= nil, label .. ": (precondition) LobbyBuilder and the booted lobby") then
		return
	end
	local MK = LB._Meadow and LB._Meadow.K
	local savedStats, savedLast = MK and MK.Stats, MK and MK.Last
	local undo = {}
	live.Name = "NimbusLobby_LobbyShopKeep"
	local cursor = #Mock.Output
	local okSetup, errSetup = pcall(setup, undo, LB)
	local okBuild, info = false, "setup failed"
	if okSetup then
		okBuild, info = pcall(LB.Build)
	end
	local okInspect, errInspect = true, nil
	if okBuild and type(info) == "table" and typeof(info.Folder) == "Instance" then
		okInspect, errInspect = pcall(inspect, info, cursor)
	end
	if type(info) == "table" and typeof(info.Folder) == "Instance" then
		info.Folder:Destroy()
	end
	for i = #undo, 1, -1 do
		pcall(undo[i])
	end
	LB._Kit = nil
	LB._ForceShopFallback = nil
	if MK then
		MK.Stats, MK.Last = savedStats, savedLast
	end
	live.Name = "NimbusLobby"
	T.check(okSetup and okBuild and type(info) == "table" and info.Folder ~= nil, label .. ": LobbyBuilder.Build() ran", tostring(errSetup or info))
	T.check(okInspect, label .. ": the checks ran", tostring(errInspect))
end

----------------------------------------------------------------------------------------------------
-- the checks of one built trove / egg row
----------------------------------------------------------------------------------------------------
local function checkTrovePlace(label, stall)
	local model = stall and stall.Model
	if not T.check(model ~= nil and model.Name == "SkyTrove" and model.PrimaryPart ~= nil, label .. ": ItemShop.Model is the SkyTrove with a PrimaryPart") then
		return nil
	end
	local o = K.config().Lobby.Origin
	local spot = polar(TROVE_DEG, TROVE_R)
	T.check(typeof(stall.Center) == "Vector3" and hdist(stall.Center, spot) <= 0.5,
		label .. fmt(": the trove's centre stands at spot C, polar %d degrees, r %d from the origin (+-0.5)", TROVE_DEG, TROVE_R),
		stall.Center and fmt("%.2f off", hdist(stall.Center, spot)) or "no Center")
	local cf = model.PrimaryPart.CFrame
	local toC = flat(o - cf.Position).Unit
	T.check(cf.LookVector:Dot(toC) > 0.99, label .. ": the trove faces the plaza centre", fmt("dot %.4f", cf.LookVector:Dot(toC)))
	T.check(math.abs(cf.Position.Y - 2.6 - (o.Y - LAWN)) <= 0.05, label .. ": the trove stands on the plaza lawn (Origin.Y - 0.4)", fmt("%.2f", cf.Position.Y - 2.6))
	return cf
end

-- spot C's neighbours (spec 16.2's table, measured on the built lobby): centre-to-centre distances in plaza-local studs
local function checkTroveNeighbours(label, root, info, stall, Config)
	local o = Config.Lobby.Origin
	local c = stall.Center
	local guide = root:FindFirstChild("GuideBoard", true)
	local gface = guide and guide:FindFirstChild("Face")
	local dGuide = gface and hdist(c, gface.Position) or -1
	T.check(gface ~= nil and dGuide >= TROVE_NEED.Guide, label .. fmt(": the Guide board stands >= %.1f studs off", TROVE_NEED.Guide), fmt("%.2f", dGuide))
	local benches, beds = {}, {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") and d.Parent and d.Parent.Name == "LawnDecor" then
			if d.Name == "Bench" then
				benches[#benches + 1] = hdist(c, d:GetPivot().Position)
			elseif d.Name == "FlowerBed" then
				beds[#beds + 1] = hdist(c, d:GetPivot().Position)
			end
		end
	end
	table.sort(benches)
	table.sort(beds)
	local b1, b2 = benches[1] or -1, benches[2] or -1
	T.check(#benches >= 4 and b1 >= TROVE_NEED.Bench and math.abs(b2 - b1) <= TROVE_NEED.BenchPair,
		label .. fmt(": both west benches stand >= %d studs off and within %.1f of each other (the chest between them); every bench >= %d", TROVE_NEED.Bench, TROVE_NEED.BenchPair, TROVE_NEED.Bench),
		fmt("%d benches, nearest %.2f / %.2f", #benches, b1, b2))
	T.check(#beds >= 1 and beds[1] >= TROVE_NEED.Bed, label .. fmt(": every lawn flower bed stands >= %.1f studs off", TROVE_NEED.Bed), fmt("%d beds, nearest %.2f", #beds, beds[1] or -1))
	local npc = math.huge
	for _, s in ipairs(info.NpcSpots or {}) do
		npc = math.min(npc, hdist(c, s.Position))
	end
	T.check(#(info.NpcSpots or {}) >= 6 and npc >= TROVE_NEED.Npc, label .. fmt(": every NPC spot stands >= %.1f studs off", TROVE_NEED.Npc), fmt("%d spots, nearest %.2f", #(info.NpcSpots or {}), npc))
	-- the west cross walk: L.CrossAngles = MidAngle +- 90 (MidAngle = Config.Lobby.GateFacing), the west one at 180
	local wa = math.rad(((Config.Lobby.GateFacing or 90) + 90) % 360)
	local ux, uz = math.cos(wa), math.sin(wa)
	local function lateral(p)
		local px, pz = p.X - o.X, p.Z - o.Z
		return math.abs(-px * uz + pz * ux), px * ux + pz * uz
	end
	local dWalk, along = lateral(c)
	T.check(dWalk >= TROVE_NEED.Walk and along > 34 and along < 100, label .. fmt(": the west cross walk's centre line runs >= %.1f studs off (beside its stretch)", TROVE_NEED.Walk), fmt("%.2f off, %.1f along", dWalk, along))
	local dCourt = hdist(c, o)
	T.check(dCourt >= TROVE_NEED.Court, label .. fmt(": the spawn court's centre is >= %.1f studs off", TROVE_NEED.Court), fmt("%.2f", dCourt))
	-- the sign's footing: outside the walk band and off every path / border voxel cell
	local sign = stall.Model:FindFirstChild("Sign")
	local foot = sign and sign:FindFirstChild("Footing")
	if not T.check(foot ~= nil and foot:IsA("BasePart"), label .. ": the sign has its Footing") then
		return
	end
	local band = math.huge
	for _, q in ipairs(corners(foot)) do
		band = math.min(band, lateral(q) - WALK_HALF)
	end
	T.check(band >= TROVE_NEED.Footing, label .. fmt(": the sign's footing ends >= %.1f stud outside the west walk (half width %d)", TROVE_NEED.Footing, WALK_HALF), fmt("%.2f", band))
	local cell, cells, cellName = math.huge, 0, "-"
	for _, m in ipairs(root:GetDescendants()) do
		if m:IsA("Model") and (m.Name == "Paths" or m.Name == "PathBorders") then
			for _, p in ipairs(m:GetDescendants()) do
				local g = p:IsA("BasePart") and rectGap(foot, p) or math.huge
				if g < 40 then
					cells = cells + 1
					if g < cell then
						cell, cellName = g, m.Name
					end
				end
			end
		end
	end
	T.check(cells > 0 and cell >= TROVE_NEED.Footing, label .. fmt(": the sign's footing stands >= %.1f stud off every path / border cell", TROVE_NEED.Footing), fmt("%d cells near, nearest (%s) %.2f", cells, cellName, cell))
	T.info(fmt("*%s: Guide board %.2f, west benches %.2f / %.2f, NPC spot %.2f, flower bed %.2f, west walk %.2f, spawn court %.2f studs; the footing %.2f outside the walk band, %.2f off the nearest path cell",
		label, dGuide, b1, b2, npc, beds[1] or -1, dWalk, dCourt, band, cell))
end

-- a GuiObject's box in px (x, y, w, h) inside a SurfaceGui canvas of w x h px, from the Size / Position / AnchorPoint
-- chain under the gui; nil when an AutomaticSize decides it or the object is not under the gui
local function guiBox(obj, gui, w, h)
	local chain = {}
	local cur = obj
	while cur and cur ~= gui do
		chain[#chain + 1] = cur
		cur = cur.Parent
	end
	if cur ~= gui then
		return nil
	end
	local x, y = 0, 0
	for i = #chain, 1, -1 do
		local o = chain[i]
		if o:IsA("GuiObject") then
			if o.AutomaticSize ~= Enum.AutomaticSize.None then
				return nil
			end
			local ow = w * o.Size.X.Scale + o.Size.X.Offset
			local oh = h * o.Size.Y.Scale + o.Size.Y.Offset
			x = x + w * o.Position.X.Scale + o.Position.X.Offset - o.AnchorPoint.X * ow
			y = y + h * o.Position.Y.Scale + o.Position.Y.Offset - o.AnchorPoint.Y * oh
			w, h = ow, oh
		end
	end
	return x, y, w, h
end

local function rarityDef(Config, id)
	for _, rd in ipairs(Config.Rarities) do
		if rd.Id == id then
			return rd
		end
	end
	return nil
end

-- the WINGED PETS board (shop-area 16.17.2): every letter and pill ends above y 3.9 (<= 375 of its 450 px), the header row
-- holds the title (left) and the subtitle (right, two lines), the measured text widths keep them apart
local function checkRarityBoard(label, shop)
	local rb = shop and shop:FindFirstChild("RarityBoard")
	local face = rb and rb:FindFirstChild("Face")
	local gui = face and face:FindFirstChildOfClass("SurfaceGui")
	local panel = gui and gui:FindFirstChild("Panel")
	if not T.check(rb ~= nil and face ~= nil and gui ~= nil and panel ~= nil, label .. ": the RarityBoard with its SurfaceGui panel on its Face") then
		return nil
	end
	local W, H = face.Size.X * gui.PixelsPerStud, face.Size.Y * gui.PixelsPerStud
	T.check(math.abs(W - 700) < 0.5 and math.abs(H - EGGROW.CanvasH) < 0.5, label .. ": the board's canvas is 700 x 450 px (14 x 9 studs at 50 px per stud)", fmt("%.0f x %.0f", W, H))
	local low, frames = {}, 0
	for _, ch in ipairs(panel:GetChildren()) do
		local isRow = ch:IsA("Frame") and string.match(ch.Name, "^Rarities%d+$") ~= nil
		if ch:IsA("TextLabel") or isRow then
			local _, y, _, h = guiBox(ch, gui, W, H)
			if not y or y + h > EGGROW.MaxBottom + 1e-3 * H then
				low[#low + 1] = ch.Name .. (y and fmt(" ends %.1f px", y + h) or " (no box)")
			end
			if isRow then
				frames = frames + 1
				for _, pill in ipairs(ch:GetChildren()) do
					if pill:IsA("GuiObject") and pill.Size.Y.Scale == 0 and pill.Size.Y.Offset > h + 1e-3 then
						low[#low + 1] = ch.Name .. "." .. pill.Name .. fmt(" %d px tall in a %.0f px row", pill.Size.Y.Offset, h)
					end
				end
			end
		end
	end
	T.check(#low == 0 and frames >= 4, label .. fmt(": every WINGED PETS letter and pill row ends above y 3.9 (<= %d of %d px; the eggs stand in front)", EGGROW.MaxBottom, EGGROW.CanvasH),
		frames .. " pill rows; " .. table.concat(low, ", "))
	local title, sub = panel:FindFirstChild("Header"), panel:FindFirstChild("Sub")
	if T.check(title ~= nil and title:IsA("TextLabel") and title.Text == "WINGED PETS" and title.TextSize == 50, label .. ": the title 'WINGED PETS' at 50 px") then
		local tx = guiBox(title, gui, W, H)
		T.check(title.TextXAlignment == Enum.TextXAlignment.Left and tx ~= nil, label .. ": ...left-aligned in the header row")
	end
	if T.check(sub ~= nil and sub:IsA("TextLabel") and sub.Text == RARITY_SUB, label .. ": the subtitle reads '" .. RARITY_SUB .. "'", sub and sub.Text) then
		local sx, sy, sw, sh = guiBox(sub, gui, W, H)
		T.check(sx ~= nil and sub.TextXAlignment == Enum.TextXAlignment.Right and sy <= EGGROW.HeaderTop and sy + sh <= EGGROW.RowTop + 1e-3 and sub.TextSize == 30,
			label .. ": ...30 px, right-aligned in the header row (starts <= 60 px, ends above the first roulette row at 68 px)", sx and fmt("y %.1f .. %.1f", sy, sy + sh))
		-- measured (Roblox's fonts): the title 383 px (GothamBlack = Montserrat Black at 50 px), the subtitle wrapped into
		-- "Every egg hatches" (261 px) / "a pet of its rarity" (238 px) by a box 261 .. 285 px wide ("Every egg hatches a" is
		-- 286); two 30 px lines fit its height; the title's right end and the subtitle's left end >= 6 px apart (outlines in)
		local tx = guiBox(title, gui, W, H)
		if sx and tx then
			local titleRight = tx + 383 + 3
			local subLeft = sx + sw - 261 - 2
			T.check(sub.TextWrapped == true and sw >= 261 and sw < 286 and sh >= 2 * 30, label .. ": ...wrapped into two lines (its box 261 .. 285 px wide, 60+ px tall)", fmt("%.1f x %.1f px", sw, sh))
			T.check(subLeft - titleRight >= EGGROW.MinGap, label .. ": ...the title's letters and the subtitle's keep >= 6 px apart", fmt("%.1f px", subLeft - titleRight))
		end
	end
	return face
end

-- the seven egg_<rarity> dress requests (LobbyBuilder._Kit) on the row's eggs at their bottom centres; ML_DressKey where the
-- key is not missing (--mesh: fixture holders make every one count)
local function checkEggRequests(label, LB, row, Config, ML)
	local recs = {}
	for _, rec in ipairs(LB and LB._Kit and LB._Kit.Targets or {}) do
		for r, key in pairs(EGG_KEYS) do
			if rec.Key == key then
				recs[r] = recs[r] or {}
				table.insert(recs[r], rec)
			end
		end
	end
	local bad = {}
	for _, r in ipairs(Config.Eggs.Order) do
		local list = recs[r] or {}
		local egg = row and row:FindFirstChild("Egg_" .. r)
		local rec = list[1]
		if #list ~= 1 or not egg or rec.Target ~= egg then
			bad[#bad + 1] = r .. fmt(" (%d records)", #list)
		elseif not (typeof(rec.Origin) == "CFrame" and near(rec.Origin.Position, egg.Position - Vector3.new(0, 1.5, 0)) and rec.Origin.UpVector.Y > 0.999) then
			bad[#bad + 1] = r .. " (origin not the egg's bottom centre)"
		end
	end
	T.check(#bad == 0, label .. ": seven dress requests egg_common .. egg_secret on the Egg_<Rarity> parts at the egg's bottom centre", table.concat(bad, ", "))
	local checked, wrong = 0, {}
	for _, r in ipairs(Config.Eggs.Order) do
		local key = EGG_KEYS[r]
		local okSt, st = pcall(ML.Status, key)
		local egg = row and row:FindFirstChild("Egg_" .. r)
		if okSt and st ~= "missing" and egg then
			checked = checked + 1
			local off = cfFromString(egg:GetAttribute("ML_Offset"))
			if egg:GetAttribute("ML_DressKey") ~= key or not off or not near((egg:GetPivot() * off).Position, egg.Position - Vector3.new(0, 1.5, 0)) then
				wrong[#wrong + 1] = r
			end
		end
	end
	if MESH_MODE then
		T.check(checked == 7 and #wrong == 0, label .. " (--mesh): every egg is tagged with its egg_<rarity> key, the mesh pivot on the egg's bottom centre",
			checked .. " checked; wrong: " .. table.concat(wrong, ", "))
	else
		T.check(#wrong == 0, label .. ": ML_DressKey on the eggs whose key is not missing (" .. checked .. " here; --mesh checks all seven)", table.concat(wrong, ", "))
	end
end

-- the egg row (shop-area 16.17.2) of one built lobby: the shelf, the seven eggs, the strip, the glow, the PromptPart, the
-- WINGED PETS board above it, the clearances, the empty right lawn; info = its LobbyInfo (the Counter) -> the row | nil
local function checkEggRow(label, lobby, Config, info)
	local shop = lobby:FindFirstChild("Shop")
	T.check(shop ~= nil and shop:FindFirstChild("EggGuide", true) == nil and shop:FindFirstChild("EggGuideBoard", true) == nil,
		label .. ": no Egg Guide (board, shelf or model) anywhere in the Shop folder")
	local rows = {}
	for _, ch in ipairs(shop and shop:GetChildren() or {}) do
		if ch.Name == "EggRow" then
			rows[#rows + 1] = ch
		end
	end
	local row = rows[1]
	if not T.check(#rows == 1 and row:IsA("Model"), label .. ": the Shop folder holds one Model EggRow", #rows .. " EggRow") then
		return nil
	end
	local bcf = boardFrame()
	T.check(near(row:GetPivot().Position, bcf.Position) and row:GetPivot().LookVector:Dot(bcf.LookVector) > 0.999,
		label .. ": the EggRow's pivot is the WINGED PETS board's ground frame (at(23, -10) on the lawn, facing the shop centre)",
		fmt("%.2f off", (row:GetPivot().Position - bcf.Position).Magnitude))
	local kids, wantKids = {}, { "EggShelf", "PromptPart" }
	for _, r in ipairs(Config.Eggs.Order) do
		wantKids[#wantKids + 1] = "Egg_" .. r
	end
	for _, ch in ipairs(row:GetChildren()) do
		kids[#kids + 1] = ch.Name
	end
	table.sort(kids)
	table.sort(wantKids)
	T.eq(table.concat(kids, ","), table.concat(wantKids, ","), label .. ": the EggRow holds the shelf, the seven eggs and the PromptPart (nothing else)")

	------------------------------------------------------------------ the shelf
	local shelf = row:FindFirstChild("EggShelf")
	if not T.check(shelf ~= nil and shelf:IsA("BasePart"), label .. ": a stone shelf EggShelf") then
		return row
	end
	local shelfCF = bcf * CFrame.new(EGGROW.ShelfX, EGGROW.Shelf.Y / 2, EGGROW.ShelfZ)
	T.check(near(shelf.Size, EGGROW.Shelf, 0.01) and near(shelf.Position, shelfCF.Position, 0.05) and shelf.CFrame.LookVector:Dot(bcf.LookVector) > 0.999,
		label .. fmt(": the shelf is %g x %g x %g at the board's cf * (%g, %g, %g) (the eggs' centre at x %g: the row slid towards the reader's left, off the Cloud machine), turned with the board",
			EGGROW.Shelf.X, EGGROW.Shelf.Y, EGGROW.Shelf.Z, EGGROW.ShelfX, EGGROW.Shelf.Y / 2, EGGROW.ShelfZ, EGGROW.EggsX),
		fmt("size %s, %.3f off", tostring(shelf.Size), (shelf.Position - shelfCF.Position).Magnitude))
	T.check(shelf.Material == Enum.Material.SmoothPlastic and shelf.CanCollide == true and shelf.Anchored == true, label .. ": ...SmoothPlastic, colliding, anchored")
	local top = shelf.Position.Y + shelf.Size.Y / 2

	------------------------------------------------------------------ the seven eggs
	local right = -bcf.RightVector -- the reader faces the board's front: their right is the board's -X
	local eggs, bad = {}, {}
	for i, r in ipairs(Config.Eggs.Order) do
		local egg = row:FindFirstChild("Egg_" .. r)
		local def = rarityDef(Config, r)
		local mesh = egg and egg:FindFirstChildOfClass("SpecialMesh")
		local want = (bcf * CFrame.new(EGGROW.EggsX + (8 - 2 * i) * EGGROW.Step / 2, EGGROW.Shelf.Y + EGGROW.EggSize.Y / 2, EGGROW.ShelfZ)).Position
		if not (egg and egg:IsA("BasePart")) then
			bad[#bad + 1] = r .. " missing"
		else
			eggs[#eggs + 1] = { Id = r, D = egg.Position:Dot(right) }
			if not near(egg.Size, EGGROW.EggSize, 0.01) then
				bad[#bad + 1] = r .. " size " .. tostring(egg.Size)
			end
			if not (mesh and mesh.MeshType == Enum.MeshType.Sphere and mesh.MeshId == "") then
				bad[#bad + 1] = r .. " not an ellipsoid (Sphere SpecialMesh)"
			end
			if egg.Material ~= Enum.Material.SmoothPlastic then
				bad[#bad + 1] = r .. " material " .. tostring(egg.Material)
			end
			if r == "Secret" then
				local c = egg.Color
				if not (c.B > c.R and c.B > c.G and math.max(c.R, c.G, c.B) * 255 <= 110) then
					bad[#bad + 1] = "Secret not dark violet " .. tostring(c)
				end
			elseif not (def and sameColor(egg.Color, def.Color)) then
				bad[#bad + 1] = r .. " colour " .. tostring(egg.Color)
			end
			if not near(egg.Position, want, 0.05) then
				bad[#bad + 1] = r .. fmt(" %.2f off its place", (egg.Position - want).Magnitude)
			end
			if math.abs(egg.Position.Y - EGGROW.EggSize.Y / 2 - top) > 0.05 then
				bad[#bad + 1] = r .. " not standing on the shelf"
			end
		end
	end
	T.check(#bad == 0 and #eggs == 7, label .. fmt(": seven Egg_<Rarity> eggs, 2.25 x 3 x 2.5 ellipsoids in SmoothPlastic and the rarity colour (Secret dark violet), standing on the shelf %g studs apart at cf * (%g + (8 - 2 i) * %g, %g, %g)",
		EGGROW.Step, EGGROW.EggsX, EGGROW.Step / 2, EGGROW.Shelf.Y, EGGROW.ShelfZ), table.concat(bad, "; "))
	local still = {}
	for _, r in ipairs(Config.Eggs.Order) do
		local egg = row:FindFirstChild("Egg_" .. r)
		if not (egg and CS:HasTag(egg, Config.Tags.Spin) and egg:GetAttribute("SpinSeconds") == 14 and egg:GetAttribute("BobStuds") == 0.12
			and egg:GetAttribute("BobSeconds") == 3.2) then
			still[#still + 1] = r
		end
	end
	T.check(#still == 0, label .. ": every egg is tagged NC_Spin with SpinSeconds 14, BobStuds 0.12, BobSeconds 3.2 (the shelf turntable)", table.concat(still, ", "))
	table.sort(eggs, function(a, b)
		return a.D < b.D
	end)
	local order = {}
	for _, e in ipairs(eggs) do
		order[#order + 1] = e.Id
	end
	T.eq(table.concat(order, ","), table.concat(Config.Eggs.Order, ","), label .. ": ...left to right (as the reader sees them) in Config.Eggs.Order, Common at the reader's left")

	------------------------------------------------------------------ the rarity label strip on the shelf's front
	local strip = shelf:FindFirstChild("RarityStrip")
	if T.check(strip ~= nil and strip:IsA("SurfaceGui"), label .. ": a SurfaceGui RarityStrip on the shelf") then
		T.check(strip.Face == Enum.NormalId.Front and strip.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud and strip.PixelsPerStud == EGGROW.PPS
			and strip.LightInfluence == 0 and (strip.Adornee == nil or strip.Adornee == shelf),
			label .. ": ...on the shelf's Front face at 50 px per stud, LightInfluence 0")
		local W, H = shelf.Size.X * strip.PixelsPerStud, shelf.Size.Y * strip.PixelsPerStud
		local band = strip:FindFirstChild("Band")
		T.check(band ~= nil and band:IsA("Frame") and band.Size.X.Scale == 1 and band.Size.Y.Scale == 1 and band.Size.X.Offset == 0 and band.Size.Y.Offset == 0
			and math.abs(band.BackgroundTransparency - EGGROW.BandAlpha) < 1e-6 and sameColor(band.BackgroundColor3, EGGROW.Navy),
			label .. ": ...a Navy Band over the whole canvas at BackgroundTransparency 0.2")
		local Theme = req("shared/Theme")
		local badL, spans = {}, {}
		for i, id in ipairs(Config.Eggs.Order) do
			local l = strip:FindFirstChild("Label_" .. id, true)
			local def = rarityDef(Config, id)
			local colour = (id == "Secret") and EGGROW.SecretText or (def and def.Color)
			local x, _, w, h = nil, nil, nil, nil
			if l and l:IsA("TextLabel") then
				x, _, w, h = guiBox(l, strip, W, H)
			end
			local eggC = W / 2 - (EGGROW.EggsX - EGGROW.ShelfX + (8 - 2 * i) * EGGROW.Step / 2) * strip.PixelsPerStud -- the canvas's left = the shelf's +X end
			if not (l and l:IsA("TextLabel") and x) then
				badL[#badL + 1] = id .. " missing"
			else
				local c = x + w / 2
				spans[i] = { Id = id, C = c, Half = ((EGGROW.TextW[id] or 0) + 2 * EGGROW.Outline) / 2 }
				local stroke = l:FindFirstChildOfClass("UIStroke")
				if not (math.abs(w - EGGROW.Cell) <= 0.5 and math.abs(h - EGGROW.StripH) <= 0.5) then
					badL[#badL + 1] = id .. fmt(" box %.1f x %.1f px", w, h)
				end
				if math.abs(c - eggC) > EGGROW.UnderEgg then
					badL[#badL + 1] = id .. fmt(" centre %.1f px, its egg at %.1f px", c, eggC)
				end
				if l.Text ~= id or l.TextSize ~= EGGROW.Text or l.TextScaled ~= false or l.TextWrapped ~= false then
					badL[#badL + 1] = id .. fmt(" text '%s' %s px scaled %s", tostring(l.Text), tostring(l.TextSize), tostring(l.TextScaled))
				end
				if not (colour and sameColor(l.TextColor3, colour)) then
					badL[#badL + 1] = id .. " colour " .. tostring(l.TextColor3)
				end
				if not (stroke and stroke.Thickness >= EGGROW.Outline and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual) then
					badL[#badL + 1] = id .. " no INK outline"
				end
				if Theme and l.Font ~= Theme.Fonts.Body then
					badL[#badL + 1] = id .. " font " .. tostring(l.Font) .. " (want Theme.Fonts.Body: the measured BuilderSans-Bold)"
				end
			end
		end
		T.check(#badL == 0, label .. ": seven Label_<Rarity> in Config.Eggs.Order, 135 x 40 px boxes standing under their eggs, the rarity id in 30 px Body (no TextScaled, no wrap) in the rarity colour (Secret 178,150,255) with the INK outline",
			table.concat(badL, "; "))
		-- the measured widths: neighbours >= MinGap apart, the end labels on the canvas
		local gaps, worst = {}, math.huge
		for i = 1, #Config.Eggs.Order do
			local a, b = spans[i], spans[i + 1]
			if a and i == 1 then
				worst = math.min(worst, a.C - a.Half)
				gaps[#gaps + 1] = fmt("left edge %.1f", a.C - a.Half)
			end
			if a and b then
				local g = (b.C - b.Half) - (a.C + a.Half)
				worst = math.min(worst, g)
				gaps[#gaps + 1] = fmt("%s/%s %.1f", a.Id, b.Id, g)
			elseif a and i == #Config.Eggs.Order then
				worst = math.min(worst, W - (a.C + a.Half))
				gaps[#gaps + 1] = fmt("right edge %.1f", W - (a.C + a.Half))
			end
		end
		T.check(#spans == 7 and worst >= EGGROW.MinGap, label .. fmt(": no two labels meet (measured widths: every gap >= %d px) and the end labels stay on the %.0f px canvas", EGGROW.MinGap, W),
			table.concat(gaps, ", "))
	end

	------------------------------------------------------------------ the shelf's one glow
	local lights = {}
	for _, d in ipairs(row:GetDescendants()) do
		if d:IsA("Light") then
			lights[#lights + 1] = d
		end
	end
	local g = lights[1]
	local at = g and g.Parent and g.Parent:IsA("Attachment") and g.Parent.WorldPosition or nil
	T.check(#lights == 1 and g:IsA("PointLight") and g.Name == "EggShelfGlow" and math.abs(g.Brightness - EGGROW.Glow.Brightness) < 1e-6 and g.Range == EGGROW.Glow.Range
		and not g.Shadows and at ~= nil and g.Parent.Parent == shelf and near(at, shelf.Position + Vector3.new(0, shelf.Size.Y / 2 + EGGROW.Glow.Lift, 0), 0.05),
		label .. ": one PointLight EggShelfGlow 1.0 / 10 (no shadows) on an Attachment 1.5 over the shelf's top centre, no other light in the row",
		#lights .. " lights" .. (g and (" " .. g:GetFullName()) or ""))

	------------------------------------------------------------------ the walk-up PromptPart, LobbyInfo.Shop.Counter
	local pp = row:FindFirstChild("PromptPart")
	local wantPP = bcf * CFrame.new(EGGROW.Prompt)
	T.check(pp ~= nil and pp:IsA("BasePart") and pp.Transparency >= 0.99 and pp.CanCollide == false and near(pp.Size, EGGROW.PromptSize, 0.01)
		and near(pp.Position, wantPP.Position, 0.1), label .. ": the PromptPart is an invisible, non-colliding 5 x 4 x 3 part at the board's cf * (0, 2, -5.6)",
		pp and fmt("%.3f off", (pp.Position - wantPP.Position).Magnitude) or "none")
	local face = checkRarityBoard(label, shop)
	if info then
		local counter = type(info.Shop) == "table" and info.Shop.Counter
		T.check(type(counter) == "table" and counter.PromptPart == pp and counter.Model == row and typeof(counter.Center) == "Vector3" and face ~= nil
			and near(counter.Center, face.Position, 0.05), label .. ": LobbyInfo.Shop.Counter = { PromptPart = the row's part, Center = the WINGED PETS Face, Model = EggRow }")
	end

	------------------------------------------------------------------ clearances: the machines' prompts, the other props, the right lawn
	local minGap = math.huge
	for _, rl in ipairs(Config.Roulettes) do
		local m = shop:FindFirstChild("Roulette_" .. rl.Id)
		local mp = m and m:FindFirstChild("PromptPart")
		for _, r in ipairs(Config.Eggs.Order) do
			local egg = row:FindFirstChild("Egg_" .. r)
			if mp and egg then
				minGap = math.min(minGap, rectGap(egg, mp))
			elseif not mp then
				minGap = -1
			end
		end
	end
	T.check(minGap >= EGGROW.MachineGap, label .. ": every egg stands >= 3 studs from every roulette machine's prompt part", fmt("nearest %.2f", minGap))
	local hits, nearest, nearestName = {}, math.huge, "-"
	for _, d in ipairs(shop:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 and not d:IsDescendantOf(row) and d.Name ~= "ShopNeck" and not string.find(d:GetFullName(), "Ground", 1, true)
			and not string.find(d:GetFullName(), "ShopCloud", 1, true) and d.Position.Y > top - 2 then
			for _, mine in ipairs(row:GetChildren()) do
				if mine:IsA("BasePart") and mine.Transparency < 0.99 then
					local gp = rectGap(mine, d)
					if gp < nearest then
						nearest, nearestName = gp, d:GetFullName():gsub("^.-Shop%.", "") .. " / " .. mine.Name
					end
					if gp < EGGROW.PropGap then
						hits[#hits + 1] = d:GetFullName():gsub("^.-Shop%.", "") .. " (" .. mine.Name .. fmt(" %.2f)", gp)
					end
				end
			end
		end
	end
	T.check(#hits == 0, label .. ": the shelf and the eggs keep >= 0.3 stud clear of every other shop prop", table.concat(hits, ", "))
	T.info(fmt("*%s: the egg row's nearest shop prop %.2f studs (%s), nearest machine prompt %.2f", label, nearest, nearestName, minGap))
	-- polish 2026-11-09: the Secret end stood 0.44 stud from the Cloud machine (its eggs read as that machine's eggs): the
	-- whole row keeps EGGROW.MachineClear from every machine, measured to each visible machine part (the Part build the
	-- uploaded cabinet dresses) and to the Gumball Globe's 9 x 7 footprint round the machine's ground centre
	local machineNear, machineName = math.huge, "-"
	for _, rl in ipairs(Config.Roulettes) do
		local m = shop:FindFirstChild("Roulette_" .. rl.Id)
		local mp = m and m:FindFirstChild("PromptPart")
		local foot = nil
		if mp then
			local cf0 = mp.CFrame * CFrame.new(0, -2, 5.4) -- buildMachine: PromptPart at cf * (0, 2, -5.4)
			foot = { CFrame = cf0, Position = cf0.Position, Size = EGGROW.MachineFoot }
		end
		for _, mine in ipairs(row:GetChildren()) do
			if mine:IsA("BasePart") and mine.Transparency < 0.99 then
				if foot then
					local g = rectGap(mine, foot)
					if g < machineNear then
						machineNear, machineName = g, rl.Id .. " footprint / " .. mine.Name
					end
				end
				for _, d in ipairs(m and m:GetDescendants() or {}) do
					if d:IsA("BasePart") and d.Transparency < 0.99 and d.Position.Y > top - 2 then
						local g = rectGap(mine, d)
						if g < machineNear then
							machineNear, machineName = g, rl.Id .. " " .. d.Name .. " / " .. mine.Name
						end
					end
				end
			end
		end
	end
	T.check(machineNear >= EGGROW.MachineClear, label .. fmt(": the egg row keeps >= %.1f studs from every roulette machine (its parts and the globe's 9 x 7 footprint): its eggs never read as a machine's", EGGROW.MachineClear),
		fmt("nearest %.2f (%s)", machineNear, machineName))
	T.info(fmt("*%s: the egg row's nearest roulette machine %.2f studs (%s)", label, machineNear, machineName))
	local spot, stray = rightLawn(), {}
	for _, d in ipairs(shop:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 and not string.find(d:GetFullName(), "Ground", 1, true) and not string.find(d:GetFullName(), "ShopCloud", 1, true)
			and pointToRect(spot, d) < EGGROW.RightLawn and d.Position.Y > spot.Y - 2 then
			local ok = false
			local cur = d
			while cur and cur ~= shop do
				if cur.Name == "ShopLamp" or cur.Name == "FlowerBed" then
					ok = true
				end
				cur = cur.Parent
			end
			if not ok then
				stray[#stray + 1] = d:GetFullName():gsub("^.-Shop%.", "")
			end
		end
	end
	T.check(#stray == 0, label .. ": the right lawn (at(-21, -8), emptied by 16.17.2) holds nothing within 6 studs but lamps and flower beds", table.concat(stray, ", "))
	return row
end

----------------------------------------------------------------------------------------------------
-- lobby_trove_plaza
----------------------------------------------------------------------------------------------------
S.lobby_trove_plaza = guarded("lobby_trove_plaza", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local info = K.W.lobbyInfo
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local ML = req("shared/MeshLibrary")
	T.check(Config.Tags.Bob == "NC_Bob" and Config.Tags.Spin == "NC_Spin" and Config.Attr.TroveGroupDone == "TroveGroupDone",
		"Config: Tags.Bob = NC_Bob, Tags.Spin = NC_Spin, Attr.TroveGroupDone = TroveGroupDone")

	------------------------------------------------------------------ the booted trove
	local stall = info and info.Shop and info.Shop.ItemShop
	T.check(type(stall) == "table" and stall.PromptPart and typeof(stall.Center) == "Vector3" and stall.Model and stall.Lid,
		"trove plaza: LobbyInfo.Shop.ItemShop keeps { PromptPart, Center, Model, Lid }")
	local cf = checkTrovePlace("trove plaza", stall)
	if cf then
		local model = stall.Model
		T.check(countParts(model) <= 60, "trove plaza: the trove stays <= 60 parts (the Join sign's anchor included)", tostring(countParts(model)))
		local post = model:FindFirstChild("Sign") and model.Sign:FindFirstChild("Post")
		local lx = post and cf:PointToObjectSpace(post.Position).X
		T.check(lx ~= nil and math.abs(lx + 6.2) <= 0.05, "trove plaza: the sign post stands at local x -6.2 (the west walk side, open lawn; +6.2 is the Guide board's side)", tostring(lx))
		T.check((stall.PromptPart.Position - stall.Center).Magnitude < 10, "trove plaza: the PromptPart stands within 10 studs of the centre")
		checkTroveNeighbours("trove plaza", lobby, info, stall, Config)
		T.check(#troveOf(lobby) == 1, "trove plaza: exactly one SkyTrove in the booted lobby", tostring(#troveOf(lobby)))
		local anchor = model:FindFirstChild("JoinAnchor")
		local bb = anchor and anchor:FindFirstChild("JoinBillboard")
		if T.check(anchor ~= nil and anchor:IsA("BasePart") and bb ~= nil and bb:IsA("BillboardGui"), "trove plaza: the JoinAnchor part carries the JoinBillboard") then
			local lift = anchor.Position.Y - (Config.Lobby.Origin.Y - LAWN)
			T.check(anchor.Transparency >= 0.99 and math.abs(lift - 10.5) <= 0.05 and hdist(anchor.Position, stall.Center) <= 0.05,
				"trove plaza: ...an invisible anchor 10.5 studs over the chest's centre", fmt("lift %.2f", lift))
			local list = texts(bb)
			T.check(#list == 1 and list[1].Text == SOON_TEXT, "trove plaza: at GroupId 0 the Join sign reads one line, '" .. SOON_TEXT .. "'",
				#list .. " lines: " .. tostring(list[1] and list[1].Text))
			T.check(CS:HasTag(bb, "NC_Bob") and bb:GetAttribute("BobStuds") == 0.5 and bb:GetAttribute("BobSeconds") == 2.4,
				"trove plaza: the Join sign is tagged NC_Bob with BobStuds 0.5 and BobSeconds 2.4")
			T.check(bb.Size.X.Scale == 0 and bb.Size.Y.Scale == 0 and bb.LightInfluence == 0 and bb.MaxDistance >= 50 and bb.MaxDistance <= 150,
				"trove plaza: ...a pixel-sized tag (the World text rule)")
		end
	end

	------------------------------------------------------------------ the booted egg row (shop-area 16.17.2), the rarity board
	checkEggRow("egg row", lobby, Config, info)
	local rb = lobby:FindFirstChild("RarityBoard", true)
	local sub = rb and rb:FindFirstChild("Sub", true)
	T.check(sub ~= nil and sub.Text == RARITY_SUB, "rarity board: the subtitle reads '" .. RARITY_SUB .. "'", sub and sub.Text)

	------------------------------------------------------------------ the build log, the light rule
	local skipped = skippedWarns(0)
	T.check(#skipped == 0, "trove plaza: no 'plaza decor skipped' warn in the build log", table.concat(skipped, " | "))
	local Lamps = Config.Sky.Lamps
	local bright, spots = {}, 0
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			spots = spots + 1
		elseif d:IsA("PointLight") then
			local lamp = d.Parent and Lamps.Names[d.Parent.Name]
			local ok = lamp and (d.Brightness <= 1.2 + 1e-6 and d.Range <= 16 and not d.Shadows) or (not lamp and d.Brightness <= 1.5 + 1e-6 and d.Range <= 28)
			if not ok then
				bright[#bright + 1] = d:GetFullName()
			end
		end
	end
	T.check(#bright == 0 and spots == 0, "trove plaza: every lobby light within the light rule (lamps <= 1.2 / 16, others <= 1.5 / 28, no spot / surface lights)", table.concat(bright, ", "))

	------------------------------------------------------------------ rebuild: GroupId 123 + the dress requests
	rebuild("trove plaza rebuild", function(undo, LB)
		local oldGid = Config.Trove.GroupId
		Config.Trove.GroupId = 123
		undo[#undo + 1] = function()
			Config.Trove.GroupId = oldGid
		end
		LB._Kit = { Targets = {}, Clouds = {} }
		if MESH_MODE then
			-- --mesh: fixture holders for the egg keys in the fixture MeshLibrary's root (Status -> "loading"), removed after
			T.check(fixtureHolders(EGG_KEYS, undo) > 0, "egg row (--mesh): the fixture MeshLibrary root exists")
		end
	end, function(built, cursor)
		local LB = req("server/Services/LobbyBuilder")
		local stall2 = built.Shop and built.Shop.ItemShop
		checkTrovePlace("trove plaza rebuild", stall2)
		local bb = stall2 and stall2.Model and stall2.Model:FindFirstChild("JoinBillboard", true)
		local got = {}
		for _, l in ipairs(bb and texts(bb) or {}) do
			got[#got + 1] = l.Text
		end
		table.sort(got)
		T.eq(table.concat(got, " / "), "2,000 Cash + 200 Tokens / Join the group!", "trove plaza: with GroupId 123 the Join sign reads 'Join the group!' over '2,000 Cash + 200 Tokens'")
		T.eq(#troveOf(built.Folder), 1, "trove plaza rebuild: exactly one SkyTrove in the lobby")
		local shop2 = built.Folder:FindFirstChild("Shop")
		checkEggRequests("egg row", LB, shop2 and shop2:FindFirstChild("EggRow"), Config, ML)
		local sk = skippedWarns(cursor)
		T.check(#sk == 0, "trove plaza rebuild: no 'plaza decor skipped' warn", table.concat(sk, " | "))
	end)

	------------------------------------------------------------------ rebuild: the forced fallback shop
	rebuild("trove plaza fallback", function(_, LB)
		LB._ForceShopFallback = true
	end, function(built, cursor)
		local folder = built.Folder
		T.check(folder:FindFirstChild("ShopFallback") ~= nil and folder:FindFirstChild("Shop") == nil, "trove plaza fallback: _ForceShopFallback takes the fallbackShop path")
		local stall2 = built.Shop and built.Shop.ItemShop
		T.check(type(stall2) == "table" and stall2.PromptPart and typeof(stall2.Center) == "Vector3" and stall2.Model and stall2.Lid,
			"trove plaza fallback: ItemShop keeps { PromptPart, Center, Model, Lid }")
		local spot = polar(TROVE_DEG, TROVE_R)
		T.check(stall2 and stall2.Model and stall2.Model.Parent == folder.ShopFallback and typeof(stall2.Center) == "Vector3" and hdist(stall2.Center, spot) <= 0.5,
			fmt("trove plaza fallback: the fallback trove stands on the same plaza spot (spot C, polar %d, r %d)", TROVE_DEG, TROVE_R),
			stall2 and stall2.Center and fmt("%.2f off", hdist(stall2.Center, spot)) or "")
		local pp = stall2 and stall2.Model and stall2.Model.PrimaryPart
		local o = K.config().Lobby.Origin
		T.check(pp ~= nil and pp.CFrame.LookVector:Dot(flat(o - pp.Position).Unit) > 0.99, "trove plaza fallback: ...facing the plaza centre",
			pp and fmt("dot %.4f", pp.CFrame.LookVector:Dot(flat(o - pp.Position).Unit)) or "no PrimaryPart")
		T.eq(#troveOf(folder), 1, "trove plaza fallback: exactly one SkyTrove in the lobby")
		local sk = skippedWarns(cursor)
		T.check(#sk == 0, "trove plaza fallback: no 'plaza decor skipped' warn on that build either", table.concat(sk, " | "))
	end)
	local LB = req("server/Services/LobbyBuilder")
	T.check(LB and LB._ForceShopFallback == nil and LB._Kit == nil, "trove plaza: the hooks are back to nil")
	T.check(workspace:FindFirstChild("NimbusLobby") == lobby and #CS:GetTagged(Config.Tags.TroveLid) == 1, "trove plaza: the booted lobby is back (one tagged lid)")

	------------------------------------------------------------------ TroveGroupDone
	local DS = K.mod("DataService")
	local attr = Config.Attr.TroveGroupDone
	local key = Config.Tokens.DataStoreName .. "/u_"
	local savedFail, savedGid = Mock.DataStore.Fail, Config.Trove.GroupId
	local players = {}
	local function join(name, uid)
		local p = Mock.AddPlayer(name, uid)
		players[#players + 1] = p
		K.advance(1.2)
		return p
	end
	local function loaded(p)
		return K.waitFor(function()
			return DS.GetProfile(p) ~= nil and not DS.IsProvisional(p)
		end, 10)
	end
	local okRun, errRun = pcall(function()
		Mock.DataStore.Data[key .. 986101] = { Version = 2, Tokens = 0, Pets = {}, Equipped = {}, Trove = { Group = true } }
		local a = join("TroveDoneA", 986101)
		T.check(loaded(a), "trove done: (precondition) the stored profile loads")
		K.advance(0.3)
		T.eq(a:GetAttribute(attr), true, "trove done: a stored claim (Trove.Group) sets TroveGroupDone after the load")

		Mock.DataStore.Data[key .. 986102] = { Version = 2, Tokens = 0, Pets = {}, Equipped = {}, Trove = { Group = true } }
		Mock.DataStore.Fail = true
		local b = join("TroveDoneB", 986102)
		local prov = K.waitFor(function()
			return DS.IsProvisional(b) == true
		end, 10)
		T.check(prov and b:GetAttribute(attr) == nil, "trove done: a provisional (outage) load sets nothing")
		Mock.DataStore.Fail = savedFail
		local back = K.waitFor(function()
			return DS.IsProvisional(b) ~= true
		end, 60)
		K.advance(0.3)
		T.check(back and b:GetAttribute(attr) == true, "trove done: ...its recovery (ProfileRebased) sets TroveGroupDone")

		local c = join("TroveDoneC", 986103)
		T.check(loaded(c) and c:GetAttribute(attr) == nil, "trove done: a fresh player has no TroveGroupDone")
		Config.Trove.GroupId = 777
		c.IsInGroupAsync = function(_, gid)
			return gid == 777
		end
		Mock.FromClient(K.remoteFolder().TroveRequest, c, "Joined")
		K.advance(0.5)
		local trove = DS.GetTrove(c)
		T.check(type(trove) == "table" and trove.Group == true and c:GetAttribute(attr) == true, "trove done: the claim sets TroveGroupDone")
		c.IsInGroupAsync = nil
		Config.Trove.GroupId = savedGid

		local d = join("TroveDoneD", 986104)
		T.check(loaded(d), "trove done: (precondition) a second player loads")
		K.advance(0.3)
		T.eq(d:GetAttribute(attr), nil, "trove done: a second player without the claim has no attribute")
	end)
	Mock.DataStore.Fail = savedFail
	Config.Trove.GroupId = savedGid
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(1)
	T.check(okRun, "trove done: the scenario body ran", tostring(errRun))
	K.flushErrors("lobby_trove_plaza")
	K.flushWarnings("lobby_trove_plaza", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- altar_gate (Task 12, spec 5.11 (a)): the Storm Altar gate on the plaza
----------------------------------------------------------------------------------------------------
local ALTAR = { Title = "Storm Altar", Info = "Secret pets", Pill = "Secret Roulette", Boost = 1.4 }
local GATE_FALLBACK_MARK = "forced gate fallback (altar_gate)"

-- the highest top of a gate's pad: the Pad part and every PadTile* part of the gate model
local function padTopOf(model, pad)
	local top = pad.Position.Y + pad.Size.Y / 2
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 7) == "PadTile" then
			top = math.max(top, d.Position.Y + d.Size.Y / 2)
		end
	end
	return top
end

-- "Name xN" of a gate's pad kit (its PadTile* inlay / rim tiles and Lantern* parts), sorted
local function padKit(model)
	local n = {}
	for _, d in ipairs(model:GetChildren()) do
		local head = string.sub(d.Name, 1, 7)
		if d:IsA("BasePart") and (head == "PadTile" or head == "Lantern") then
			n[d.Name] = (n[d.Name] or 0) + 1
		end
	end
	local out = {}
	for name, c in pairs(n) do
		out[#out + 1] = name .. " x" .. c
	end
	table.sort(out)
	return table.concat(out, ", ")
end

local function gateTag(model)
	local tag = model:FindFirstChild("GateTag", true)
	local plate = tag and tag:FindFirstChild("Plate")
	local pill = plate and plate:FindFirstChild("Pill")
	local pillLabel = pill and (pill:FindFirstChild("Label") or pill:FindFirstChild("PillLabel"))
	return plate and plate:FindFirstChild("Title"), plate and plate:FindFirstChild("Info"), pill, pillLabel
end

-- the checks of one built Altar gate (the booted WorldStyle gate or the forced Gates.Fallback one)
local function checkAltarGate(label, gate, site)
	local model, pad = gate and gate.Model, gate and gate.Pad
	if not T.check(model ~= nil and typeof(site) == "CFrame", label .. ": LobbyInfo.Gates.Altar.Model and GateSites.Altar") then
		return nil
	end
	-- the tag (checked before the pad, so a missing pad still shows every other miss)
	local title, infoL, pill, pillLabel = gateTag(model)
	T.check(title ~= nil and title.Text == ALTAR.Title and infoL ~= nil and infoL.Text == ALTAR.Info and infoL.Visible ~= false,
		label .. ": the tag reads '" .. ALTAR.Title .. "' / '" .. ALTAR.Info .. "'", tostring(title and title.Text) .. " / " .. tostring(infoL and infoL.Text))
	T.check(pill ~= nil and pill.Visible == true and pillLabel ~= nil and pillLabel.Text == ALTAR.Pill,
		label .. ": ...and shows the Pill '" .. ALTAR.Pill .. "'", pillLabel and (pillLabel.Text .. (pill.Visible and "" or " (hidden)")) or "no pill")
	T.eq(model:GetAttribute("VortexBoost"), ALTAR.Boost, label .. ": the gate model carries VortexBoost 1.4")
	-- the pad
	local okPad = pad ~= nil and pad:IsA("BasePart") and pad.Name == "Pad" and pad:IsDescendantOf(model)
	if not T.check(okPad and near(pad.Size, Vector3.new(14, 0.6, 14), 0.01) and pad.CanCollide,
		label .. ": LobbyInfo.Gates.Altar.Pad is the gate's walkable 14 x 0.6 x 14 Pad", pad and (pad.Name .. " " .. tostring(pad.Size)) or "no pad") then
		return nil
	end
	local l = site:PointToObjectSpace(pad.Position)
	T.check(math.abs(l.X) < 0.05 and math.abs(l.Z + 14) < 0.05 and math.abs(l.Y - 0.3) < 0.05,
		label .. ": ...lying 14 studs in front of the gate (toward the plaza), on the ground", tostring(l))
	-- the way back lands on the pad's front half, 3 studs over the pad top, looking out along the gate's LookVector
	local ret = gate.ReturnCFrame
	local top = padTopOf(model, pad)
	if T.check(typeof(ret) == "CFrame", label .. ": LobbyInfo.Gates.Altar.ReturnCFrame") then
		local rel = ret.Position - site.Position
		local along, side = rel:Dot(site.LookVector), math.abs(rel:Dot(site.RightVector))
		T.check(along >= 14 and along <= 21 and side <= 0.5, label .. ": ...14..21 studs along the gate's LookVector (the pad's front half)", fmt("along %.2f, side %.2f", along, side))
		T.check(math.abs(ret.Position.Y - top - 3) <= 0.1, label .. ": ...3 studs (+-0.1) over the pad top (its highest part)", fmt("%.3f over", ret.Position.Y - top))
		T.check(ret.LookVector:Dot(site.LookVector) > 0.99, label .. ": ...looking out along the gate's LookVector (at the plaza)")
	end
	return model, pad, top
end

S.altar_gate = guarded("altar_gate", function()
	if not K.needBoot() then
		return
	end
	local info = K.W.lobbyInfo
	local gates = type(info) == "table" and info.Gates or {}
	local site = info and info.GateSites and info.GateSites.Altar
	local model, pad, top = checkAltarGate("altar gate", gates.Altar, site)
	local obby = gates.Obby and gates.Obby.Model
	T.check(obby ~= nil and obby:GetAttribute("VortexBoost") == nil, "altar gate: the Obby gate has no VortexBoost (only the Altar's vortex is boosted)")
	if model and obby then
		local kit = padKit(model)
		T.check(kit ~= "" and kit == padKit(obby) and string.find(kit, "PadTileGlow", 1, true) ~= nil and string.find(kit, "LanternGlow x2", 1, true) ~= nil,
			"altar gate: the pad has the Obby pad's Neon inlay, rim tiles and two lanterns (same names and counts)", kit .. " vs " .. padKit(obby))
		T.eq(model:GetAttribute("ML_DressKey"), "gate_altar", "altar gate: the gate_altar mesh target keeps its ML_DressKey")
	end
	if model and pad then
		-- nothing else solid stands on the pad (6 studs up)
		local box = site * CFrame.new(0, top - site.Position.Y + 3.05, -14)
		local solid = {}
		for _, p in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(14, 6, 14))) do
			if p.CanCollide and not p:IsDescendantOf(model) then
				local char = false
				for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
					if pl.Character and p:IsDescendantOf(pl.Character) then
						char = true
					end
				end
				if not char then
					solid[#solid + 1] = p:GetFullName()
				end
			end
		end
		T.check(#solid == 0, "altar gate: nothing else solid stands on the pad (6 studs up)", table.concat(solid, ", "))
		-- the pad is a landing spot, not a trigger: GateService's Travel prompt stays the only way in
		local GS = K.mod("GateService")
		local fired = {}
		local conn = GS and GS.Teleported and GS.Teleported:Connect(function(_, id)
			fired[#fired + 1] = tostring(id)
		end)
		local players = K.freshPlayers(1, "AltarPad")
		local p = players[1]
		local spot = (site * CFrame.new(0, 0, -14)).Position
		Mock.Teleport(p, CFrame.new(spot.X, top + 3, spot.Z))
		K.advance(3)
		local root = K.root(p)
		T.check(conn ~= nil and #fired == 0 and root ~= nil and hdist(root.Position, spot) < 1,
			"altar gate: standing on the pad for 3 s teleports nobody", table.concat(fired, ", ") .. (root and fmt(" (%.2f studs off)", hdist(root.Position, spot)) or ""))
		if conn then
			conn:Disconnect()
		end
		K.removePlayers(players)
	end

	------------------------------------------------------------------ the forced Gates.Fallback gate
	local WS = req("shared/WorldStyle")
	local realBuildGate = WS and WS.BuildGate
	rebuild("altar gate fallback", function(undo)
		WS.BuildGate = function()
			error(GATE_FALLBACK_MARK)
		end
		undo[#undo + 1] = function()
			WS.BuildGate = realBuildGate
		end
	end, function(built)
		local g = built.Gates and built.Gates.Altar
		local m = g and g.Model
		T.check(m ~= nil and m:FindFirstChild("Column") ~= nil and m:FindFirstChild("GlowCore") == nil,
			"altar gate fallback: WorldStyle.BuildGate failing builds the Altar gate with Gates.Fallback (columns, no voxel core)")
		checkAltarGate("altar gate fallback", g, built.GateSites and built.GateSites.Altar)
	end)
	T.check(WS ~= nil and WS.BuildGate == realBuildGate, "altar gate: WorldStyle.BuildGate is back after the forced fallback")
	K.flushErrors("altar_gate")
	K.flushWarnings("altar_gate", { "[DataService]", "[MeshLibrary]", GATE_FALLBACK_MARK })
end)

----------------------------------------------------------------------------------------------------
-- altar_portal_glow (Task 13, spec 5.11 (b) (c)): the summon portal's glow and the standing return ring
----------------------------------------------------------------------------------------------------
local GLOW = {
	-- the Portal model's children as StormAltar built them before Task 13 (what the prop_altar_portal LayoutSig covers)
	PortalKids = "Disc x4, DiscHeart x4, Rim x14, RimTop x14, Rune x9",
	Cyan = Color3.fromRGB(63, 200, 255),
	Heart = Color3.fromRGB(186, 236, 255),
	Green = Color3.fromRGB(96, 190, 140),
	White = Color3.fromRGB(255, 255, 255),
	RingR = 6.0, -- the summon ring's centre radius (its Part build; the portal_altar_ring mesh of Task 29 dresses it)
	RingUp = 0.35, -- ...its height over the disc top
	Seg = Vector3.new(2 * 6.0 * math.tan(math.rad(11.25)) + 0.08, 0.5, 0.3),
	Lane = 4.25, -- every ReturnPortal part (rotated bounds) off the bridge's centre line (the mesh's nearest corner ~4.32)
	RTop = 23, -- the island's walkable top radius (StormAltar R_TOP)
	Land = 1.25 * math.sqrt(2) + 0.01, -- outside the landing box (2.5 x 5 x 2.5 on the centre line): past its corners
	-- the ring faces the walk from the dais: the bridge's centre line this far out from the altar centre (the plan said
	-- "the altar"; in the real island only a lane-facing ring fits between the rim clouds, the stone ring and the edge)
	FaceAt = 14,
	MeshPadY = 1.0, -- the portal_ring manifest's Pad attachment Y (the plinth top)
	SignFace = Vector3.new(0, 8.25, -1.25), -- ...its SignFace attachment
	SignText = "To the Plaza", -- the Part fallback's pixel tag
	-- (shop-area polish) the dressed ring's 4 x 1 navy board: "To the Plaza" fit it only at 0.6 stud, under the World
	-- text rule's ~1-stud title; the board now reads the destination alone at 48 px = 0.96 stud
	BoardText = "Plaza",
	BoardStuds = 0.95,
	Allowed = { "[DataService]", "[MeshLibrary]" },
}

-- "Name xN" of a model's direct children, sorted
local function childKit(model)
	local n = {}
	for _, d in ipairs(model:GetChildren()) do
		n[d.Name] = (n[d.Name] or 0) + 1
	end
	local out = {}
	for name, c in pairs(n) do
		out[#out + 1] = name .. " x" .. c
	end
	table.sort(out)
	return table.concat(out, ", ")
end

local function partsUnder(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			out[#out + 1] = d
		end
	end
	return out
end

-- the eight world corners of a box (any rotation)
local function boxCorners(cf, size)
	local out, h = {}, size / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				out[#out + 1] = (cf * CFrame.new(sx * h.X, sy * h.Y, sz * h.Z)).Position
			end
		end
	end
	return out
end

-- top of a part turned about Y only
local function topOf(p)
	return p.Position.Y + p.Size.Y / 2
end

local function isCharacterPart(p)
	for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
		if pl.Character and p:IsDescendantOf(pl.Character) then
			return true
		end
	end
	return false
end

-- world points against the bridge frame: the smallest distance off the centre line (altar centre -> landing), the
-- largest reach from the altar centre, the smallest distance to the landing spot
local function laneCheck(label, points, A, landing)
	local axis = flat(landing - A.Position).Unit
	local lat, reach, toLand = math.huge, 0, math.huge
	for _, p in ipairs(points) do
		local rel = flat(p - A.Position)
		lat = math.min(lat, math.abs(rel.X * -axis.Z + rel.Z * axis.X))
		reach = math.max(reach, hdist(p, A.Position))
		toLand = math.min(toLand, hdist(p, landing))
	end
	T.check(#points > 0 and lat >= GLOW.Lane and reach <= GLOW.RTop and toLand >= GLOW.Land,
		label .. " >= " .. GLOW.Lane .. " studs off the bridge's centre line, within the deck (r " .. GLOW.RTop .. ") and outside the landing box",
		fmt("%d points: %.2f off the line, reach %.2f, %.2f from the landing", #points, lat, reach, toLand))
end

-- the eight corners of a manifest's bounds placed at `origin`
local function meshCorners(ML, key, origin)
	local man = ML and ML.Manifest(key)
	local b = man and man.Bounds
	local lo, hi = b and (b.Min or b.min), b and (b.Max or b.max)
	if type(lo) ~= "table" or type(hi) ~= "table" then
		return {}
	end
	local vlo, vhi = Vector3.new(lo[1], lo[2], lo[3]), Vector3.new(hi[1], hi[2], hi[3])
	return boxCorners(origin * CFrame.new((vlo + vhi) / 2), vhi - vlo)
end

-- where the return ring faces from `centre`: the bridge's centre line GLOW.FaceAt studs out from the altar centre
local function ringFacing(A, landing, centre)
	local at = A.Position + flat(landing - A.Position).Unit * GLOW.FaceAt
	return flat(at - centre).Unit
end

-- the portal_ring mesh's bounds above its plinth top (local y 1.0 .. 9.5) hold no island part rising over the deck (rim
-- clouds) and no stone-ring part: the ring stands in the clear, never buried in a billow
local function checkRingClear(label, altar, A, origin)
	local island, stones = altar:FindFirstChild("Island"), altar:FindFirstChild("Ring")
	local hits = {}
	for _, p in ipairs(workspace:GetPartBoundsInBox(origin * CFrame.new(0, 5.25, 0), Vector3.new(9, 8.5, 3))) do
		if (island and p:IsDescendantOf(island) and topOf(p) > A.Position.Y + 0.1) or (stones and p:IsDescendantOf(stones)) then
			hits[#hits + 1] = p.Name .. fmt(" (top %.2f over the deck)", topOf(p) - A.Position.Y)
		end
	end
	T.check(#hits == 0, label .. ": the portal_ring mesh's bounds stand clear of the island's rim clouds and the stone ring", table.concat(hits, ", ", 1, math.min(#hits, 4)))
end

local function signGuis(portal)
	local found = {}
	for _, d in ipairs(portal:GetDescendants()) do
		if (d:IsA("BillboardGui") or d:IsA("SurfaceGui")) and d.Name == "PlazaSign" then
			found[#found + 1] = d
		end
	end
	return found
end

local function joinedText(gui)
	local t = {}
	for _, l in ipairs(texts(gui)) do
		t[#t + 1] = l.Text
	end
	return table.concat(t, " / ")
end

-- the old disc's top and the glow disc's top (studs over A) of a built altar
local function discTops(altar, A)
	local oldTop, glowTop = -math.huge, -math.huge
	local portal, glow = altar:FindFirstChild("Portal"), altar:FindFirstChild("PortalGlow")
	for _, d in ipairs(portal and portal:GetChildren() or {}) do
		if d:IsA("BasePart") and (d.Name == "Disc" or d.Name == "DiscHeart") then
			oldTop = math.max(oldTop, topOf(d) - A.Position.Y)
		end
	end
	for _, d in ipairs(glow and glow:GetChildren() or {}) do
		if d:IsA("BasePart") and d.Name == "GlowDisc" then
			glowTop = math.max(glowTop, topOf(d) - A.Position.Y)
		end
	end
	return oldTop, glowTop
end

-- the summon glow of one built altar (spec 5.11 b)
local function checkGlow(label, altar, A, Config, SA, ML)
	local portal, glow = altar:FindFirstChild("Portal"), altar:FindFirstChild("PortalGlow")
	T.check(portal ~= nil and childKit(portal) == GLOW.PortalKids, label .. ": the Portal model is untouched (its children as before Task 13: " .. GLOW.PortalKids .. ")",
		portal and childKit(portal) or "no Portal")
	-- the LayoutSig itself (any mode), and the tag wherever the key is not missing (the default run: it has an id)
	local man = ML and ML.Manifest("prop_altar_portal")
	local sig = man and man.Attachments and man.Attachments.LayoutSig
	local pos = sig and (sig.Pos or sig.pos)
	if T.check(portal ~= nil and type(pos) == "table" and SA._Mesh ~= nil, label .. ": (setup) the prop_altar_portal manifest's LayoutSig") then
		local n, a, b = SA._Mesh.Signature(portal, A)
		local tol = 0.05 + n * 1e-4
		T.check(n == pos[1] and math.abs(a - pos[2]) <= tol and math.abs(b - pos[3]) <= tol, label .. ": the Portal still matches its prop_altar_portal LayoutSig",
			fmt("%d / %.3f / %.3f vs %s / %s / %s", n, a, b, tostring(pos[1]), tostring(pos[2]), tostring(pos[3])))
	end
	local okSt, st = pcall(ML.Status, "prop_altar_portal")
	if okSt and st ~= "missing" then
		T.eq(portal and portal:GetAttribute("ML_DressKey"), "prop_altar_portal", label .. ": ...so it keeps ML_DressKey prop_altar_portal (the key is " .. tostring(st) .. ")")
	end
	if not T.check(glow ~= nil and glow:IsA("Model") and glow.Parent == altar, label .. ": Model PortalGlow stands beside the Portal") then
		return
	end
	local oldTop, discTop = discTops(altar, A)
	local heartTop, reach, discs, hearts, discOk, heartOk, solid = -math.huge, 0, 0, 0, true, true, {}
	for _, d in ipairs(partsUnder(glow)) do
		if d.CanCollide or d.CanTouch then
			solid[#solid + 1] = d.Name
		end
		if d.Parent == glow and (d.Name == "GlowDisc" or d.Name == "GlowHeart") then
			for _, c in ipairs(boxCorners(d.CFrame, d.Size)) do
				reach = math.max(reach, hdist(c, A.Position))
			end
			if d.Name == "GlowDisc" then
				discs = discs + 1
				discOk = discOk and d.Material == Enum.Material.Neon and sameColor(d.Color, GLOW.Cyan)
			else
				hearts = hearts + 1
				heartTop = math.max(heartTop, topOf(d) - A.Position.Y)
				heartOk = heartOk and d.Material == Enum.Material.Neon and sameColor(d.Color, GLOW.Heart)
			end
		end
	end
	T.check(discs >= 4 and discOk and reach <= GLOW.RingR + 0.001, label .. ": GlowDisc is a Neon 16-gon in the crystal cyan rgb(63,200,255) inside the rim (union radius <= 6.0)",
		fmt("%d parts, radius %.3f", discs, reach))
	T.check(math.abs(discTop - oldTop - 0.06) <= 0.01, label .. ": ...its top 0.06 above the old disc top", fmt("old %.3f, glow %.3f", oldTop, discTop))
	T.check(hearts >= 1 and heartOk and heartTop > discTop and heartTop - discTop <= 0.05, label .. ": GlowHeart, the lighter heart rgb(186,236,255), just over the glow disc",
		fmt("%d parts, %.3f over the disc", hearts, heartTop - discTop))
	T.check(#solid == 0, label .. ": no PortalGlow part collides or touches", table.concat(solid, ", "))
	-- the spinning ring (its Part build; the portal_altar_ring mesh dresses it once it has an id: checkAltarRingMesh)
	local centre = (A * CFrame.new(0, discTop, 0)).Position
	local ring = glow:FindFirstChild("GlowRing")
	if T.check(ring ~= nil and ring:IsA("Model"), label .. ": GlowRing is a Model") then
		T.check(CS:HasTag(ring, Config.Tags.Spin) and ring:GetAttribute("SpinSeconds") == 6, label .. ": GlowRing is tagged NC_Spin with SpinSeconds 6 (the client turns it)",
			tostring(ring:GetAttribute("SpinSeconds")))
		T.check(near(ring:GetPivot().Position, centre, 0.01) and ring:GetPivot().UpVector.Y > 0.9999, label .. ": ...its pivot is the disc centre on the disc top")
		local segs, bad = 0, {}
		for _, d in ipairs(partsUnder(ring)) do
			segs = segs + 1
			local r, up = hdist(d.Position, A.Position), d.Position.Y - centre.Y
			if d.Material ~= Enum.Material.Neon or not sameColor(d.Color, GLOW.Cyan) or not near(d.Size, GLOW.Seg, 0.01) or math.abs(r - GLOW.RingR) > 0.01 or math.abs(up - GLOW.RingUp) > 0.01 then
				bad[#bad + 1] = d.Name .. fmt(" r %.2f up %.2f %s", r, up, tostring(d.Size))
			end
		end
		T.check(segs == 16 and #bad == 0, label .. fmt(": ...16 cyan Neon segments (%.2f x 0.5 x 0.3) on the ring r 6.0, 0.35 above the disc top", GLOW.Seg.X),
			segs .. " segments; " .. table.concat(bad, ", ", 1, math.min(#bad, 3)))
	end
	-- the sky beam
	local beam = glow:FindFirstChildWhichIsA("Beam", true)
	if T.check(beam ~= nil and beam.Attachment0 ~= nil and beam.Attachment1 ~= nil, label .. ": a sky Beam between two attachments") then
		local a0, a1 = beam.Attachment0.WorldPosition, beam.Attachment1.WorldPosition
		T.check(hdist(a0, centre) <= 0.01 and hdist(a1, centre) <= 0.01 and math.abs(a0.Y - centre.Y - 0.5) <= 0.01 and math.abs(a1.Y - centre.Y - 160) <= 0.01,
			label .. ": ...from 0.5 to 160 studs over the disc centre (about 160 apart)", fmt("%.2f / %.2f up", a0.Y - centre.Y, a1.Y - centre.Y))
		local anchor = beam.Attachment0.Parent
		T.check(anchor ~= nil and anchor:IsA("BasePart") and anchor.Transparency >= 1 and anchor == beam.Attachment1.Parent, label .. ": ...both on one invisible anchor")
		local ck, tk = beam.Color.Keypoints, beam.Transparency.Keypoints
		T.check(beam.FaceCamera == true and beam.Texture == "" and beam.Width0 == 3 and beam.Width1 == 1, label .. ": ...FaceCamera, no texture, width 3 -> 1",
			fmt("FaceCamera %s, texture '%s', %s -> %s", tostring(beam.FaceCamera), tostring(beam.Texture), tostring(beam.Width0), tostring(beam.Width1)))
		T.check(sameColor(ck[1].Value, GLOW.Cyan) and sameColor(ck[#ck].Value, GLOW.White) and math.abs(tk[1].Value - 0.2) < 1e-6 and math.abs(tk[#tk].Value - 1) < 1e-6,
			label .. ": ...cyan to white, transparency 0.2 rising to 1 with height")
	end
	T.check(glow:FindFirstChildWhichIsA("ParticleEmitter", true) ~= nil, label .. ": rising sparkles")
	local lights = {}
	for _, d in ipairs(glow:GetDescendants()) do
		if d:IsA("Light") then
			lights[#lights + 1] = d
		end
	end
	local l = lights[1]
	T.check(#lights == 1 and l:IsA("PointLight") and math.abs(l.Brightness - 1.5) < 1e-6 and l.Range == 24 and l.Shadows == false, label .. ": one PointLight 1.5 / 24 (no shadows)",
		#lights .. " lights" .. (l and fmt(", %s / %s", tostring(l.Brightness), tostring(l.Range)) or ""))
end

-- the standing return ring of one built altar (spec 5.11 c). Returns the portal, the pad centre (deck height), the pad top.
local function checkReturn(label, SA, altar, A, landing)
	local pad = SA.GetReturnPad()
	local portal = pad and pad.Parent
	if not T.check(pad ~= nil and pad.Name == "ReturnPrompt" and portal ~= nil and portal.Name == "ReturnPortal" and portal.Parent == altar,
		label .. ": GetReturnPad() is the ReturnPrompt anchor of Model ReturnPortal") then
		return nil
	end
	local lights = {}
	for _, d in ipairs(pad:GetChildren()) do
		if d:IsA("Light") then
			lights[#lights + 1] = d
		end
	end
	local l = lights[1]
	T.check(#lights == 1 and l:IsA("PointLight") and math.abs(l.Brightness - 1.3) < 1e-6 and l.Range == 14 and l.Shadows == false and portal:FindFirstChild("ReturnGlow", true) == nil,
		label .. ": ReturnPrompt carries exactly one PointLight (1.3 / 14) and ReturnGlow is gone", #lights .. " lights" .. (l and fmt(", %s / %s", tostring(l.Brightness), tostring(l.Range)) or ""))
	local pads, padTop, others, pts = {}, -math.huge, {}, {}
	for _, d in ipairs(partsUnder(portal)) do
		if d.Name == "Pad" and d.Parent == portal then
			pads[#pads + 1] = d
			padTop = math.max(padTop, topOf(d))
		elseif d.CanCollide or d.CanTouch then
			others[#others + 1] = d:GetFullName()
		end
		for _, c in ipairs(boxCorners(d.CFrame, d.Size)) do
			pts[#pts + 1] = c
		end
	end
	local padsOk = #pads == 2
	for _, p in ipairs(pads) do
		padsOk = padsOk and p.CanCollide and math.abs(p.Size.Y - 0.2) < 1e-6
	end
	T.check(padsOk and math.abs(padTop - A.Position.Y - 0.2) <= 0.01, label .. ": the two flat Pad octagons (0.2 tall, collidable, top 0.2 over the deck) stay the floor",
		#pads .. fmt(" pads, top %.3f over the deck", padTop - A.Position.Y))
	T.check(#others == 0, label .. ": every other ReturnPortal part has CanCollide and CanTouch false", table.concat(others, ", ", 1, math.min(#others, 4)))
	local centre = Vector3.new(pad.Position.X, A.Position.Y, pad.Position.Z)
	local face = ringFacing(A, landing, centre)
	-- the standing ring: its Part fallback (the portal_ring mesh dresses it once the key has an id)
	local ring = portal:FindFirstChild("Ring")
	if T.check(ring ~= nil and ring:IsA("Model"), label .. ": the standing ring is Model ReturnPortal.Ring") then
		local segs, feet, stray = {}, {}, {}
		for _, d in ipairs(partsUnder(ring)) do
			if d.Name == "RingSegment" then
				segs[#segs + 1] = d
			elseif d.Name == "PortalFoot" then
				feet[#feet + 1] = d
			else
				stray[#stray + 1] = d.Name
			end
		end
		local ringC = centre + Vector3.new(0, 4.5, 0)
		local r0, segOk = nil, true
		for _, s in ipairs(segs) do
			local rel = s.Position - ringC
			r0 = r0 or rel.Magnitude
			segOk = segOk and s.Material == Enum.Material.Neon and sameColor(s.Color, GLOW.Green) and math.abs(rel.Magnitude - r0) <= 0.01 and math.abs(rel:Dot(face)) <= 0.01
		end
		T.check(#segs == 13 and segOk and r0 >= 3.6 and r0 <= 4.2, label .. ": ...its Part fallback: 13 green Neon segments (rgb(96,190,140)) on one ring 4.5 up over the pad (r ~3.9), facing the walk from the dais",
			#segs .. fmt(" segments, r %.2f", r0 or 0))
		local feetOk = #feet == 2
		for _, f in ipairs(feet) do
			feetOk = feetOk and pointToRect(centre, f) > 2 * math.sqrt(2) and f.Material ~= Enum.Material.Neon
		end
		T.check(feetOk and #stray == 0, label .. ": ...and two stone feet outside the 4x6x4 box over the pad (nothing else)", #feet .. " feet; " .. table.concat(stray, ", "))
	end
	laneCheck(label .. ": every ReturnPortal part (rotated bounds) is", pts, A, landing)
	-- nothing collidable but the pads in the 4x6x4 box over the pad
	local solid = {}
	for _, p in ipairs(workspace:GetPartBoundsInBox(CFrame.new(centre.X, A.Position.Y + 3.05, centre.Z), Vector3.new(4, 6, 4))) do
		if p.CanCollide and not (p.Name == "Pad" and p.Parent == portal) and not isCharacterPart(p) then
			solid[#solid + 1] = p:GetFullName() .. fmt(" (top %.2f over the deck, %.2f from the pad centre, size %s)", topOf(p) - A.Position.Y, hdist(p.Position, centre), tostring(p.Size))
		end
	end
	T.check(#solid == 0, label .. ": nothing collidable but the pads in the 4x6x4 box over the pad", table.concat(solid, ", ", 1, math.min(#solid, 4)))
	local prompt = pad:FindFirstChild("PlazaGatePrompt")
	T.check(prompt ~= nil and prompt.KeyboardKeyCode == Enum.KeyCode.E and prompt.MaxActivationDistance == 8, label .. ": the PlazaGatePrompt keeps E and range 8")
	-- spec 16.16 (owner 2026-11-08: no vortex in the ring): ReturnPortal is a PortalFx gate (GateId "Plaza") with no
	-- Swirl parts; the client's Fixed vortex reads the VortexCenter part and the Vortex* attributes
	T.eq(portal:GetAttribute("GateId"), "Plaza", label .. ": ReturnPortal carries GateId 'Plaza' (PortalFxController tracks it)")
	local vc = portal:FindFirstChild("VortexCenter")
	local ringC = centre + Vector3.new(0, 4.5, 0)
	T.check(vc ~= nil and vc:IsA("BasePart") and vc.Parent == portal and vc.Anchored and vc.Transparency == 1 and not vc.CanCollide and not vc.CanQuery and not vc.CanTouch
		and near(vc.Position, ringC, 0.1) and face ~= nil and vc.CFrame.LookVector:Dot(face) > 0.9999,
		label .. ": ...an invisible anchored VortexCenter (no collide / query / touch) in the Part ring's opening (4.5 over the pad, +-0.1), its front facing the walk",
		vc and fmt("%.3f off", (vc.Position - ringC).Magnitude) or "no VortexCenter")
	local radius, meshR, offset, color = portal:GetAttribute("VortexRadius"), portal:GetAttribute("VortexMeshRadius"), portal:GetAttribute("VortexMeshOffset"), portal:GetAttribute("VortexColor")
	-- the Part ring: 13 segments 0.7 thick on r = 3.8 (inner faces 3.45 out); the mesh: the Neon rim's inner edge 2.5
	-- out (blender/kit/props/lobby_shop.py RING_RIM)
	T.check(type(radius) == "number" and radius > 1 and radius < 3.45 and type(meshR) == "number" and meshR > 1 and meshR < 2.5,
		label .. ": ...VortexRadius inside the Part ring (< 3.45), VortexMeshRadius inside the mesh's Neon rim (< 2.5)", fmt("%s / %s", tostring(radius), tostring(meshR)))
	T.check(typeof(color) == "Color3" and sameColor(color, GLOW.Green), label .. ": ...VortexColor = the ring's green rgb(96,190,140)", tostring(color))
	-- review minor 1: the client probes only the named child for the mesh dress (an ML_Mesh under the Pad never counts)
	local meshChild = portal:GetAttribute("VortexMeshChild")
	T.check(meshChild == "Ring" and portal:FindFirstChild("Ring") ~= nil, label .. ": ...VortexMeshChild = 'Ring' (the child the portal_ring mesh dresses)", tostring(meshChild))
	local ML = req("shared/MeshLibrary")
	local man = ML and ML.Manifest("portal_ring")
	local att = man and man.Attachments and man.Attachments.PortalCenter
	local pc = att and (att.Pos or att.pos)
	if T.check(typeof(offset) == "CFrame" and type(pc) == "table" and vc ~= nil and face ~= nil, label .. ": ...VortexMeshOffset (a CFrame) and the portal_ring manifest's PortalCenter") then
		local y = padTop - 0.05 - GLOW.MeshPadY
		local origin = CFrame.lookAt(Vector3.new(centre.X, y, centre.Z), Vector3.new(centre.X, y, centre.Z) + face)
		local want = origin * CFrame.new(pc[1], pc[2], pc[3])
		local got = vc.CFrame * offset
		T.check(near(got.Position, want.Position, 0.1) and got.LookVector:Dot(face) > 0.9999,
			label .. ": ...VortexCenter x VortexMeshOffset = the dressed mesh's PortalCenter (+-0.1), facing the walk", fmt("%.3f off", (got.Position - want.Position).Magnitude))
	end
	return portal, centre, padTop, face
end

-- every light of the altar within the lobby rule; the altar's part budget
local function checkAltarBudget(label, altar)
	local showcase = altar:FindFirstChild("StormfangShowcase", true)
	local parts, bright, spots = 0, {}, 0
	for _, d in ipairs(altar:GetDescendants()) do
		if d:IsA("BasePart") and not (showcase and d:IsDescendantOf(showcase)) then
			parts = parts + 1
		elseif d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			spots = spots + 1
		elseif d:IsA("PointLight") and not (d.Brightness <= 1.5 + 1e-6 and d.Range <= 28 and not d.Shadows) then
			bright[#bright + 1] = d:GetFullName()
		end
	end
	T.check(#bright == 0 and spots == 0, label .. ": every altar light within the lobby rule (<= 1.5 / 28, no shadows, no spot / surface lights)", table.concat(bright, ", "))
	T.check(parts <= 500, label .. ": the altar stays <= 500 parts (the showcase pet excluded)", parts .. " parts")
	T.info("*" .. label .. ": " .. parts .. " parts")
end

-- the sign as the Part fallback shows it: a pixel-sized BillboardGui
local function checkBillboardSign(label, portal)
	local list = signGuis(portal)
	local gui = list[1]
	if not T.check(#list == 1 and gui:IsA("BillboardGui"), label .. ": the Part fallback's 'To the Plaza' sign is one BillboardGui PlazaSign", #list .. " signs") then
		return
	end
	local small = {}
	for _, l in ipairs(texts(gui)) do
		if l.TextSize < 22 or l.TextScaled then
			small[#small + 1] = l.Text
		end
	end
	T.eq(joinedText(gui), GLOW.SignText, label .. ": ...it reads 'To the Plaza'")
	T.check(gui.Size.X.Scale == 0 and gui.Size.Y.Scale == 0 and gui.Size.X.Offset > 0 and #small == 0 and gui.LightInfluence == 0 and gui.MaxDistance >= 50 and gui.MaxDistance <= 150,
		label .. ": ...pixel-sized, text >= 22 px (no TextScaled), LightInfluence 0, MaxDistance 50-150", tostring(gui.Size) .. ", MaxDistance " .. tostring(gui.MaxDistance) .. "; small: " .. table.concat(small, ", "))
end

-- the sign as the dressed mesh shows it: a SurfaceGui at 50 px per stud on a SignFace part at the mesh's SignFace
local function checkSurfaceSign(label, portal, origin)
	local list = signGuis(portal)
	local gui = list[1]
	if not T.check(#list == 1 and gui:IsA("SurfaceGui"), label .. ": the mesh's 'Plaza' sign is one SurfaceGui PlazaSign", #list .. " signs") then
		return
	end
	local face = gui.Adornee or gui.Parent
	local want = origin * CFrame.new(GLOW.SignFace)
	local front = face and face:IsA("BasePart") and (face.CFrame * CFrame.new(0, 0, -face.Size.Z / 2)).Position
	T.check(face ~= nil and face.Name == "SignFace" and face.Parent == portal and front ~= nil and (front - want.Position).Magnitude <= 0.05 and face.CFrame.LookVector:Dot(want.LookVector) > 0.9999,
		label .. ": ...on part SignFace (in ReturnPortal, beside the Ring), its front face on the mesh's SignFace attachment", front and fmt("%.3f off", (front - want.Position).Magnitude) or "no SignFace part")
	local small = {}
	for _, l in ipairs(texts(gui)) do
		if l.TextSize / 50 < GLOW.BoardStuds or l.TextScaled then
			small[#small + 1] = l.Text .. " " .. fmt("%.2f stud", l.TextSize / 50)
		end
	end
	T.eq(joinedText(gui), GLOW.BoardText, label .. ": ...it reads 'Plaza' (the destination, title-sized on the 4 x 1 board)")
	T.check(gui.Face == Enum.NormalId.Front and gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud and gui.PixelsPerStud == 50 and gui.LightInfluence == 0 and #small == 0,
		label .. ": ...Face Front, 50 px per stud, the title >= 0.95 stud (World text rule ~1 stud; no TextScaled), LightInfluence 0", tostring(gui.PixelsPerStud) .. " px/stud; small: " .. table.concat(small, ", "))
end

-- the portal_altar_ring manifest (Task 29) against a built altar: the mesh the client dresses GlowRing with
local function checkAltarRingMesh(label, altar, A, ML)
	local man = ML and ML.Manifest("portal_altar_ring")
	local b = man and man.Bounds
	local lo, hi = b and (b.Min or b.min), b and (b.Max or b.max)
	if not T.check(type(lo) == "table" and type(hi) == "table", label .. ": the portal_altar_ring manifest exists (Task 29) with its bounds") then
		return
	end
	local att = man.Attachments and man.Attachments.Center
	local cp = att and (att.Pos or att.pos)
	T.check(type(cp) == "table" and math.abs(cp[1]) + math.abs(cp[2]) + math.abs(cp[3]) < 1e-6, label .. ": ...attachment Center at its pivot (the disc centre on the glow disc's top)")
	-- the old Disc's top (under the glow disc, studs from the ring's pivot) and the Portal rim's nearest stone face
	local portal = altar:FindFirstChild("Portal")
	local _, glowTop = discTops(altar, A)
	local discTop, rimIn = -math.huge, math.huge
	for _, d in ipairs(portal and portal:GetChildren() or {}) do
		if d:IsA("BasePart") and d.Name == "Disc" then
			discTop = math.max(discTop, topOf(d) - A.Position.Y - glowTop)
		elseif d:IsA("BasePart") and d.Name == "Rim" then
			rimIn = math.min(rimIn, hdist(d.Position, A.Position) - d.Size.Z / 2)
		end
	end
	T.check(lo[2] < discTop and lo[2] > discTop - 0.2, label .. ": ...seated: its foot reaches into the old disc (no gap under it), not through it",
		fmt("foot %.3f, the old disc's top %.3f", lo[2], discTop))
	-- it turns, so its farthest point sweeps a circle: a 16-gon's corners are its half extent / cos 11.25 out
	local half = math.max(math.abs(lo[1]), math.abs(hi[1]), math.abs(lo[3]), math.abs(hi[3]))
	local reach = half / math.cos(math.rad(11.25))
	T.check(reach < rimIn - 0.05, label .. ": ...inside the Portal rim's nearest stone face as it turns (16-gon corners < the face - 0.05)",
		fmt("reach %.3f, the rim's face %.3f", reach, rimIn))
	T.check(hi[2] <= GLOW.RingUp + GLOW.Seg.Y / 2 + 0.1, label .. ": ...no taller than the Part ring (+0.1)", fmt("top %.3f", hi[2]))
	-- one Fixed SmoothPlastic part (the baked stone) and Neon parts named Glow*, GlowBar in the ring's crystal cyan
	-- (MeshLibrary.Manifest hands the parts over with lower-case fields; the raw manifest has them capitalised)
	local fixed, bad, bar = 0, {}, false
	for _, p in ipairs(man.Parts or {}) do
		local name, mat, c = tostring(p.name or p.Name), p.material or p.Material, p.color or p.Color
		if mat == "Neon" then
			if string.sub(name, 1, 4) ~= "Glow" then
				bad[#bad + 1] = name
			end
			if name == "GlowBar" and type(c) == "table" and c[1] == "rgb" then
				bar = sameColor(Color3.fromRGB(c[2], c[3], c[4]), GLOW.Cyan)
			end
		elseif name == "Fixed" and mat == "SmoothPlastic" then
			fixed = fixed + 1
		else
			bad[#bad + 1] = name .. " " .. tostring(mat)
		end
	end
	T.check(fixed == 1 and #bad == 0 and bar, label .. ": ...one Fixed SmoothPlastic part and Neon Glow* parts, GlowBar in the crystal cyan rgb(63,200,255)",
		fixed .. " Fixed; " .. table.concat(bad, ", ") .. (bar and "" or "; GlowBar not cyan"))
end

S.altar_portal_glow = guarded("altar_portal_glow", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local SA, ML, WS = req("server/Services/StormAltar"), req("shared/MeshLibrary"), req("shared/WorldStyle")
	local info = K.W.lobbyInfo
	local altar = SA and SA.GetModel()
	if not T.check(altar ~= nil and ML ~= nil and type(info) == "table" and typeof(SA.GetLanding()) == "CFrame", "altar portal glow: StormAltar (built at boot), MeshLibrary and LobbyInfo") then
		return
	end
	T.check(WS ~= nil and sameColor(WS.Palette.Accent.Green, GLOW.Green), "altar portal glow: WorldStyle's Accent.Green is the Return-gate green rgb(96,190,140)")

	------------------------------------------------------------------ the booted altar
	local A, landing = SA.GetCFrame(), SA.GetLanding().Position
	checkGlow("altar glow", altar, A, Config, SA, ML)
	checkAltarRingMesh("summon ring mesh", altar, A, ML)
	local portal, centre, padTop, face = checkReturn("return ring", SA, altar, A, landing)
	if portal then
		local okSt, st = pcall(ML.Status, "portal_ring")
		if okSt and st == "missing" then
			local ring = portal:FindFirstChild("Ring")
			T.check(ring ~= nil and ring:GetAttribute("ML_DressKey") == nil, "return ring: no ML_DressKey while portal_ring is missing (the Part fallback shows)")
			checkBillboardSign("return ring", portal)
		end
		local y = padTop - 0.05 - GLOW.MeshPadY
		local origin = CFrame.lookAt(Vector3.new(centre.X, y, centre.Z), Vector3.new(centre.X, y, centre.Z) + face)
		laneCheck("return ring: the portal_ring mesh's bounds (9 x 9.5 x 3, rotated) at its spot are", meshCorners(ML, "portal_ring", origin), A, landing)
		checkRingClear("return ring", altar, A, origin)
	end
	checkAltarBudget("altar glow", altar)

	------------------------------------------------------------------ rebuild: the dress requests (and the mesh-side sign)
	local M = SA._Mesh
	local realTag = M and M.tag
	local undo = {}
	local okRun, errRun = pcall(function()
		SA._Kit = { Targets = {} }
		if MESH_MODE then
			-- --mesh: fixture holders for portal_ring and portal_altar_ring (its manifest since Task 29) in the fixture
			-- MeshLibrary's root (Status -> "loading"), removed after
			T.check(fixtureHolders({ "portal_ring", "portal_altar_ring" }, undo) > 0, "altar portal glow (--mesh): the fixture MeshLibrary root exists")
		else
			-- the default run has no portal_ring id: the tag's answer is forced to "dressed" (after the real call records the
			-- request) so the mesh-side sign is built and checked here too
			M.tag = function(target, key, ...)
				local r = realTag(target, key, ...)
				if key == "portal_ring" then
					return true
				end
				return r
			end
			undo[#undo + 1] = function()
				M.tag = realTag
			end
		end
		local okB, A2 = pcall(SA.Build, info)
		K.advance(0.3)
		local altar2 = SA.GetModel()
		if not T.check(okB and typeof(A2) == "CFrame" and altar2 ~= nil and altar2 ~= altar, "altar portal glow rebuild: StormAltar.Build ran with the kit hook", tostring(A2)) then
			return
		end
		local landing2 = SA.GetLanding().Position
		checkGlow("altar glow (rebuilt)", altar2, A2, Config, SA, ML)
		local portal2, centre2, padTop2, face2 = checkReturn("return ring (rebuilt)", SA, altar2, A2, landing2)
		checkAltarBudget("altar glow (rebuilt)", altar2)
		local recs = {}
		for _, rec in ipairs(SA._Kit and SA._Kit.Targets or {}) do
			recs[rec.Key] = recs[rec.Key] or {}
			table.insert(recs[rec.Key], rec)
		end
		local glow2 = altar2:FindFirstChild("PortalGlow")
		local gring = glow2 and glow2:FindFirstChild("GlowRing")
		local _, discTop2 = discTops(altar2, A2)
		local ra = recs.portal_altar_ring or {}
		T.check(#ra == 1 and gring ~= nil and ra[1].Target == gring and typeof(ra[1].Origin) == "CFrame" and near(ra[1].Origin.Position, (A2 * CFrame.new(0, discTop2, 0)).Position, 0.01)
			and ra[1].Origin.UpVector.Y > 0.9999, "altar glow: one portal_altar_ring dress request on GlowRing, its origin the disc centre on the disc top (+-0.01)", #ra .. " records")
		local ring2 = portal2 and portal2:FindFirstChild("Ring")
		local rp = recs.portal_ring or {}
		local rec = rp[1]
		if T.check(#rp == 1 and ring2 ~= nil and rec.Target == ring2 and typeof(rec.Origin) == "CFrame", "return ring: one portal_ring dress request on ReturnPortal.Ring", #rp .. " records") then
			T.check(math.abs(rec.Origin.Position.Y - (padTop2 - 0.05 - GLOW.MeshPadY)) <= 0.01, "return ring: ...its origin Y = the octagons' top - 0.05 - 1.0 (the plinth top 0.05 under the octagons)",
				fmt("%.3f vs %.3f", rec.Origin.Position.Y, padTop2 - 1.05))
			T.check(hdist(rec.Origin.Position, centre2) <= 0.01 and face2 ~= nil and rec.Origin.LookVector:Dot(face2) > 0.9999 and rec.Origin.UpVector.Y > 0.9999,
				"return ring: ...centred on the pad, upright, facing the walk from the dais (the bridge's centre line " .. GLOW.FaceAt .. " studs out)")
			checkRingClear("return ring (dressed)", altar2, A2, rec.Origin)
			T.check(type(rec.Look) == "table" and typeof(rec.Look.Primary) == "Color3" and sameColor(rec.Look.Primary, GLOW.Green), "return ring: ...Look.Primary = WorldStyle.Accent.Green rgb(96,190,140)")
			laneCheck("return ring: the portal_ring mesh's bounds (9 x 9.5 x 3, rotated) at the dress origin are", meshCorners(ML, "portal_ring", rec.Origin), A2, landing2)
			checkSurfaceSign("return ring (dressed)", portal2, rec.Origin)
		end
		-- ML_DressKey only where the key is not missing (the default run has no ids; --mesh has the two holders)
		for _, kv in ipairs({ { "portal_altar_ring", gring }, { "portal_ring", ring2 } }) do
			local key, target = kv[1], kv[2]
			local okSt, st = pcall(ML.Status, key)
			if okSt and st ~= "missing" then
				local off = target and cfFromString(target:GetAttribute("ML_Offset"))
				local want = (key == "portal_ring") and rec and rec.Origin or (ra[1] and ra[1].Origin)
				T.check(target ~= nil and target:GetAttribute("ML_DressKey") == key and off ~= nil and want ~= nil and near((target:GetPivot() * off).Position, want.Position, 0.01),
					"altar portal glow: ML_DressKey = " .. key .. " (the key is " .. tostring(st) .. "), the mesh placed at the dress origin")
			elseif MESH_MODE then
				T.fail("altar portal glow (--mesh): the fixture holder should make " .. key .. "'s status not 'missing'", tostring(st))
			else
				T.check(target ~= nil and target:GetAttribute("ML_DressKey") == nil, "altar portal glow: no ML_DressKey = " .. key .. " while the key is missing (the Part build shows)")
			end
		end
	end)
	for i = #undo, 1, -1 do
		pcall(undo[i])
	end
	SA._Kit = nil
	-- the normal altar back (no hook, no holder): the return prompt binds to its new pad
	local okBack = pcall(SA.Build, info)
	K.advance(0.3)
	local pad = SA.GetReturnPad()
	T.check(okRun, "altar portal glow: the rebuild checks ran", tostring(errRun))
	T.check(okBack and SA._Kit == nil and (M == nil or M.tag == realTag) and pad ~= nil and pad:FindFirstChild("PlazaGatePrompt") ~= nil,
		"altar portal glow: the hooks are back and the altar is rebuilt as normal (the return prompt re-bound)")
	K.flushErrors("altar_portal_glow")
	K.flushWarnings("altar_portal_glow", GLOW.Allowed)
end)

----------------------------------------------------------------------------------------------------
-- altar_world_gem (Task 14, spec 5.7 "World gem"): the spinning world gem on the altar deck
----------------------------------------------------------------------------------------------------
local WGEM = {
	Color = Color3.fromRGB(84, 196, 246), -- the GUI gem's mid tone (Theme.Currency.Gems)
	Size = Vector3.new(4, 4, 4),
	Turn = CFrame.Angles(math.rad(45), 0, math.rad(45)), -- the Part fallback turned 45 degrees on X and Z
	-- shop-area 16.17.4 (spot 2 "Side crystal"; the owner: "move it ... not where the players might stand"): the gem's
	-- centre 15 studs over the deck straight above the medium crystal (ring index HEAD +- CrystalStep on the stone ring's
	-- centre radius RingC) on the side away from the return ring. Was: 15 out / 7.5 side, 3 studs over open deck.
	Up = 15,
	RingC = 12.2,
	RingN = 22,
	Head = 11,
	CrystalStep = 3,
	TipClear = 2, -- the turned cube's lowest corner over the crystal's tip
	BobClear = 1.4, -- ...at the bob's bottom
	Near = 3, -- "under the gem": a Crystals / Ring part whose box comes within this many studs horizontally
	Lane = 4, -- the 8-stud bridge lane's half width
	Sphere = 2 * math.sqrt(3), -- the 4-stud cube's half diagonal: covers the cube (and the 6-stud mesh) at any turn
	Bob = 0.6, -- BobStuds: the client moves it +-0.6 from its built pivot
	Margin = 0.25, -- the least gap from the gem's sweep to any other altar part
	PromptMin = 12, -- (16.17.4: >= 12 studs from both prompt parts; was 6)
	Allowed = { "[DataService]", "[MeshLibrary]" },
}

-- the horizontal distance from a point to a part's world bounds (its eight corners' footprint)
local function flatToBounds(pt, part)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local top = -math.huge
	for _, c in ipairs(boxCorners(part.CFrame, part.Size)) do
		minX, maxX = math.min(minX, c.X), math.max(maxX, c.X)
		minZ, maxZ = math.min(minZ, c.Z), math.max(maxZ, c.Z)
		top = math.max(top, c.Y)
	end
	local dx = math.max(minX - pt.X, 0, pt.X - maxX)
	local dz = math.max(minZ - pt.Z, 0, pt.Z - maxZ)
	return math.sqrt(dx * dx + dz * dz), top
end

-- point to oriented box distance
local function pointToBox(p, part)
	local l = part.CFrame:PointToObjectSpace(p)
	local h = part.Size / 2
	local dx = math.max(math.abs(l.X) - h.X, 0)
	local dy = math.max(math.abs(l.Y) - h.Y, 0)
	local dz = math.max(math.abs(l.Z) - h.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- the checks of one built world gem; returns the WorldGem model and its Gem part
local function checkWorldGem(label, SA, altar, A, landing, Config, ML)
	local model = altar:FindFirstChild("WorldGem")
	if not T.check(model ~= nil and model:IsA("Model") and model.Parent == altar, label .. ": Model WorldGem stands on the altar") then
		return nil
	end
	local parts = partsUnder(model)
	local gem = model:FindFirstChild("Gem")
	if not T.check(#parts == 1 and gem ~= nil and gem:IsA("BasePart"), label .. ": its Part fallback is one part, Gem", #parts .. " parts") then
		return model
	end
	T.check(near(gem.Size, WGEM.Size, 0.001) and gem.Material == Enum.Material.Glass and sameColor(gem.Color, WGEM.Color),
		label .. ": Gem is a 4x4x4 Glass block in the gem colour rgb(84,196,246)", tostring(gem.Size) .. " " .. tostring(gem.Material))
	T.check(gem.Anchored and not gem.CanCollide and not gem.CanTouch, label .. ": ...anchored, CanCollide and CanTouch false",
		fmt("Anchored %s, CanCollide %s, CanTouch %s", tostring(gem.Anchored), tostring(gem.CanCollide), tostring(gem.CanTouch)))
	-- the pivot: upright at the gem's centre (what the client spins and bobs it about, and where the mesh goes)
	local pivot = model:GetPivot()
	T.check(near(pivot.Position, gem.Position, 0.01) and pivot.UpVector.Y > 0.9999, label .. ": ...the model's pivot is upright at the gem's centre")
	local rel = pivot:ToObjectSpace(gem.CFrame)
	local turnOk = true
	for _, pair in ipairs({ { rel.RightVector, WGEM.Turn.RightVector }, { rel.UpVector, WGEM.Turn.UpVector }, { rel.LookVector, WGEM.Turn.LookVector } }) do
		turnOk = turnOk and (pair[1] - pair[2]).Magnitude <= 0.001
	end
	T.check(turnOk, label .. ": ...turned 45 degrees on X and Z (so it reads as a gem)")
	-- the spin tag and its three attributes
	T.check(CS:HasTag(model, Config.Tags.Spin) and model:GetAttribute("SpinSeconds") == 8 and model:GetAttribute("BobStuds") == WGEM.Bob and model:GetAttribute("BobSeconds") == 3,
		label .. ": WorldGem is tagged NC_Spin with SpinSeconds 8, BobStuds 0.6, BobSeconds 3 (the client turns and bobs it)",
		fmt("%s / %s / %s", tostring(model:GetAttribute("SpinSeconds")), tostring(model:GetAttribute("BobStuds")), tostring(model:GetAttribute("BobSeconds"))))
	-- shop-area 16.17.4 (rewritten): spot 2 "Side crystal". The old checks "3 studs over the deck right below" and "15 out /
	-- 7.5 to the side" are gone: the gem now stands over the medium crystal on the side away from the return ring
	local corners8 = boxCorners(gem.CFrame, gem.Size)
	local low, sweep = math.huge, 0
	for _, c in ipairs(corners8) do
		low = math.min(low, c.Y)
		sweep = math.max(sweep, hdist(c, gem.Position))
	end
	local axis = flat(landing - A.Position).Unit
	local bf = CFrame.lookAt(A.Position, A.Position + axis)
	local g = bf:PointToObjectSpace(gem.Position)
	local pad = SA.GetReturnPad()
	local padX = pad and bf:PointToObjectSpace(pad.Position).X or 1
	local side = padX >= 0 and -1 or 1
	local step = 360 / WGEM.RingN
	local want, wantK = nil, nil
	for _, k in ipairs({ WGEM.Head - WGEM.CrystalStep, WGEM.Head + WGEM.CrystalStep }) do
		local p = (A * CFrame.Angles(0, -math.rad(k * step), 0) * CFrame.new(0, WGEM.Up, -WGEM.RingC)).Position
		if bf:PointToObjectSpace(p).X * side > 0 then
			want, wantK = p, k
		end
	end
	T.check(want ~= nil and (gem.Position - want).Magnitude <= 0.05,
		label .. ": the gem's centre stands 15 over the deck straight above the medium crystal (ring index " .. tostring(wantK) .. ") on the side away from the return ring",
		fmt("off by %.3f; bridge frame ahead %.2f / side %.2f / up %.2f (return ring side %.2f)", want and (gem.Position - want).Magnitude or -1, -g.Z, g.X, gem.Position.Y - A.Position.Y, padX))
	T.check(math.abs(gem.Position.Y - A.Position.Y - WGEM.Up) <= 0.05, label .. ": ...its centre 15.0 studs over the deck (+-0.05)", fmt("%.3f", gem.Position.Y - A.Position.Y))
	-- clear air over the crystal's tip: the highest Crystals / Ring part under the gem (its box within 3 studs horizontally)
	local tip, tipName = -math.huge, "-"
	for _, groupName in ipairs({ "Crystals", "Ring" }) do
		local group = altar:FindFirstChild(groupName)
		for _, d in ipairs(group and partsUnder(group) or {}) do
			local dist, top = flatToBounds(gem.Position, d)
			if dist <= WGEM.Near and top > tip then
				tip, tipName = top, d:GetFullName()
			end
		end
	end
	T.check(tip > A.Position.Y and low - tip >= WGEM.TipClear and low - WGEM.Bob - tip >= WGEM.BobClear,
		label .. ": ...the turned cube's lowest corner clears the crystal's tip by >= 2 (>= 1.4 at the bob's bottom)",
		fmt("tip %.2f over the deck (%s), lowest corner %.2f: %.2f / %.2f of air", tip - A.Position.Y, tipName, low - A.Position.Y, low - tip, low - WGEM.Bob - tip))
	local meshLow = math.huge
	for _, c in ipairs(meshCorners(ML, "gem_world", model:GetPivot())) do
		meshLow = math.min(meshLow, c.Y)
	end
	T.check(meshLow < math.huge and meshLow - tip >= WGEM.TipClear, label .. ": ...the gem_world mesh's bounds clear the tip by >= 2 too",
		fmt("%.2f of air", meshLow - tip))
	-- nobody stands under it: straight below is the stone ring / the crystal, never open deck
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(gem.Position, Vector3.new(0, -40, 0), params)
	local ringM, crystalsM = altar:FindFirstChild("Ring"), altar:FindFirstChild("Crystals")
	T.check(hit ~= nil and ((ringM and hit.Instance:IsDescendantOf(ringM)) or (crystalsM and hit.Instance:IsDescendantOf(crystalsM))),
		label .. ": ...straight below the gem is the stone ring / the crystal (never open deck where players stand)", hit and hit.Instance:GetFullName() or "no hit")
	-- outside the 8-stud bridge lane: the cube's rotated bounds, the cube turning, and the gem_world mesh's bounds
	local lat = math.huge
	for _, c in ipairs(corners8) do
		lat = math.min(lat, math.abs(bf:PointToObjectSpace(c).X))
	end
	T.check(lat >= WGEM.Lane and math.abs(g.X) - sweep >= WGEM.Lane, label .. ": ...outside the 8-stud bridge lane (the rotated cube, and the cube while it turns)",
		fmt("corners %.2f off the line, turning %.2f", lat, math.abs(g.X) - sweep))
	laneCheck(label .. ": the gem_world mesh's bounds (6 x 4.5 x 6) at the gem are", meshCorners(ML, "gem_world", pivot), A, landing)
	-- at least 6 studs from every ProximityPrompt part (the AltarPrompt, the ReturnPrompt that carries the plaza-gate prompt)
	local prompts, closest, names = 0, math.huge, {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			local host = d.Parent
			if host and host:IsA("Attachment") then
				host = host.Parent
			end
			if host and host:IsA("BasePart") and hdist(host.Position, A.Position) <= 60 then
				prompts = prompts + 1
				names[#names + 1] = host.Name
				closest = math.min(closest, hdist(host.Position, gem.Position))
			end
		end
	end
	T.check(prompts >= 2 and closest >= WGEM.PromptMin, label .. ": ...at least 12 studs from every ProximityPrompt part (horizontally)",
		fmt("%d prompt parts (%s), nearest %.2f studs", prompts, table.concat(names, ", "), closest))
	-- clear of every other altar part while it turns and bobs (a sphere of the cube's half diagonal, +-0.6)
	local worst, who = math.huge, "-"
	for _, d in ipairs(partsUnder(altar)) do
		if not d:IsDescendantOf(model) and d.Transparency < 0.99 then
			for k = -3, 3 do
				local dd = pointToBox(gem.Position + Vector3.new(0, k * WGEM.Bob / 3, 0), d)
				if dd < worst then
					worst, who = dd, d:GetFullName()
				end
			end
		end
	end
	T.check(worst - WGEM.Sphere >= WGEM.Margin, label .. ": ...clear of every other altar part while it turns and bobs (crystals, stones, rim clouds, the return ring)",
		fmt("%.2f studs of air (nearest %s)", worst - WGEM.Sphere, who))
	T.info(fmt("*%s: centre %.2f over the deck, lane %.2f (turning %.2f), nearest prompt %.2f, %.2f studs of air to %s", label, gem.Position.Y - A.Position.Y,
		lat, math.abs(g.X) - sweep, closest, worst - WGEM.Sphere, who))
	-- one cyan PointLight 1.0 / 12
	local lights = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") then
			lights[#lights + 1] = d
		end
	end
	local l = lights[1]
	T.check(#lights == 1 and l:IsA("PointLight") and math.abs(l.Brightness - 1) < 1e-6 and l.Range == 12 and l.Shadows == false and sameColor(l.Color, WGEM.Color),
		label .. ": one cyan PointLight 1.0 / 12 (no shadows)", #lights .. " lights" .. (l and fmt(", %s / %s", tostring(l.Brightness), tostring(l.Range)) or ""))
	return model, gem
end

S.altar_world_gem = guarded("altar_world_gem", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local SA, ML = req("server/Services/StormAltar"), req("shared/MeshLibrary")
	local info = K.W.lobbyInfo
	local altar = SA and SA.GetModel()
	if not T.check(altar ~= nil and ML ~= nil and type(info) == "table" and typeof(SA.GetLanding()) == "CFrame" and type(Config.Tags) == "table" and type(Config.Tags.Spin) == "string",
		"world gem: StormAltar (built at boot), MeshLibrary, LobbyInfo and Config.Tags.Spin") then
		return
	end

	------------------------------------------------------------------ the booted altar
	checkWorldGem("world gem", SA, altar, SA.GetCFrame(), SA.GetLanding().Position, Config, ML)
	checkAltarBudget("world gem", altar)

	------------------------------------------------------------------ rebuild: the dress request
	local undo = {}
	local okRun, errRun = pcall(function()
		SA._Kit = { Targets = {} }
		if MESH_MODE then
			-- --mesh: a fixture holder for gem_world in the fixture MeshLibrary's root (Status -> "loading"), removed after
			T.check(fixtureHolders({ "gem_world" }, undo) > 0, "world gem (--mesh): the fixture MeshLibrary root exists")
		end
		local okB, A2 = pcall(SA.Build, info)
		K.advance(0.3)
		local altar2 = SA.GetModel()
		if not T.check(okB and typeof(A2) == "CFrame" and altar2 ~= nil and altar2 ~= altar, "world gem rebuild: StormAltar.Build ran with the kit hook", tostring(A2)) then
			return
		end
		local model2, gem2 = checkWorldGem("world gem (rebuilt)", SA, altar2, A2, SA.GetLanding().Position, Config, ML)
		checkAltarBudget("world gem (rebuilt)", altar2)
		local recs = {}
		for _, rec in ipairs(SA._Kit and SA._Kit.Targets or {}) do
			if rec.Key == "gem_world" then
				recs[#recs + 1] = rec
			end
		end
		local rec = recs[1]
		T.check(#recs == 1 and model2 ~= nil and gem2 ~= nil and rec.Target == model2 and typeof(rec.Origin) == "CFrame" and near(rec.Origin.Position, gem2.Position, 0.01)
			and rec.Origin.UpVector.Y > 0.9999 and near(rec.Origin.Position, model2:GetPivot().Position, 0.01),
			"world gem: one gem_world dress request on WorldGem, its origin the gem CFrame (upright at the gem's centre, the model's pivot)", #recs .. " records")
		local okSt, st = pcall(ML.Status, "gem_world")
		if okSt and st ~= "missing" then
			local off = model2 and cfFromString(model2:GetAttribute("ML_Offset"))
			T.check(model2 ~= nil and model2:GetAttribute("ML_DressKey") == "gem_world" and off ~= nil and rec ~= nil and near((model2:GetPivot() * off).Position, rec.Origin.Position, 0.01),
				"world gem: ML_DressKey = gem_world (the key is " .. tostring(st) .. "), the mesh placed at the gem")
		elseif MESH_MODE then
			T.fail("world gem (--mesh): the fixture holder should make gem_world's status not 'missing'", tostring(st))
		else
			T.check(model2 ~= nil and model2:GetAttribute("ML_DressKey") == nil, "world gem: no ML_DressKey while gem_world is missing (the Part fallback shows)")
		end
	end)
	for i = #undo, 1, -1 do
		pcall(undo[i])
	end
	SA._Kit = nil
	-- the normal altar back (no hook, no holder): the return prompt binds to its new pad
	local okBack = pcall(SA.Build, info)
	K.advance(0.3)
	local pad = SA.GetReturnPad()
	local holderGone = holdersGone("gem_world")
	T.check(okRun, "world gem: the rebuild checks ran", tostring(errRun))
	T.check(okBack and SA._Kit == nil and holderGone and pad ~= nil and pad:FindFirstChild("PlazaGatePrompt") ~= nil,
		"world gem: the hook and the holder are gone and the altar is rebuilt as normal (the return prompt re-bound)")
	K.flushErrors("altar_world_gem")
	K.flushWarnings("altar_world_gem", WGEM.Allowed)
end)

----------------------------------------------------------------------------------------------------
-- shop_prompt (Task 23, spec 16.3 "The walk-up prompt"; shop-area 16.17.2: on the egg row): the row's PromptPart and
-- PetService's ShopPrompt
----------------------------------------------------------------------------------------------------
local SHOP = {
	Name = "ShopPrompt", Range = 10, Offset = Vector3.new(0, 2, -5.6), Size = Vector3.new(5, 4, 3), Caption = "eggs & gems",
	Missing = "[PetService] no Shop.Counter.PromptPart",
}

-- every ProximityPrompt called `name` under root
local function promptsNamed(root, name)
	local out = {}
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") and d.Name == name then
			out[#out + 1] = d
		end
	end
	return out
end

-- the one ShopPrompt on `part` with the spec's properties -> the prompt | nil
local function checkShopPrompt(label, part)
	local list = promptsNamed(part, SHOP.Name)
	local pr = list[1]
	T.check(#list == 1 and pr.Parent == part and pr.ActionText == "Open" and pr.ObjectText == "Shop" and pr.HoldDuration == 0
		and pr.MaxActivationDistance == SHOP.Range and pr.RequiresLineOfSight == false,
		label .. ": one ShopPrompt on the PromptPart ('Open' / 'Shop', HoldDuration 0, MaxActivationDistance 10, RequiresLineOfSight false)",
		pr and fmt("%d prompts: '%s' / '%s', hold %s, range %s, los %s", #list, tostring(pr.ActionText), tostring(pr.ObjectText), tostring(pr.HoldDuration),
			tostring(pr.MaxActivationDistance), tostring(pr.RequiresLineOfSight)) or (#list .. " prompts"))
	return pr
end

-- the walk-up part itself: invisible, not colliding, 5 x 4 x 3
local function checkCounterPart(label, part)
	return T.check(part ~= nil and typeof(part) == "Instance" and part:IsA("BasePart") and part.Transparency >= 0.99 and part.CanCollide == false
		and near(part.Size, SHOP.Size, 0.01), label .. ": the Counter's PromptPart is an invisible, non-colliding 5 x 4 x 3 part",
		part and typeof(part) == "Instance" and part:IsA("BasePart") and fmt("transparency %.2f, collide %s, size %s", part.Transparency, tostring(part.CanCollide), tostring(part.Size)) or "none")
end

-- the four machine prompts as before: one RoulettePrompt each, 'Open' / the machine's name, range 12, instant
local function checkMachinePrompts(label, shopInfo, Config)
	local bad = {}
	for _, rl in ipairs(Config.Roulettes) do
		local m = type(shopInfo) == "table" and type(shopInfo.Roulettes) == "table" and shopInfo.Roulettes[rl.Id]
		local list = promptsNamed(m and m.PromptPart, "RoulettePrompt")
		local pr = list[1]
		if not (#list == 1 and pr.ActionText == "Open" and pr.ObjectText == rl.DisplayName and pr.MaxActivationDistance == 12 and pr.HoldDuration == 0 and pr.RequiresLineOfSight == false) then
			bad[#bad + 1] = rl.Id .. " (" .. #list .. ")"
		end
	end
	T.check(#bad == 0, label .. ": the four machine prompts are unchanged (one RoulettePrompt each: 'Open' / the machine's name, range 12)", table.concat(bad, ", "))
end

S.shop_prompt = guarded("shop_prompt", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local info = K.W.lobbyInfo
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local PS = K.mod("PetService")
	local shopFolder = lobby and lobby:FindFirstChild("Shop")
	local row = shopFolder and shopFolder:FindFirstChild("EggRow")
	local part = row and row:FindFirstChild("PromptPart")
	if not T.check(type(info) == "table" and type(info.Shop) == "table" and PS ~= nil and type(PS.Init) == "function" and part ~= nil,
		"shop prompt: (precondition) LobbyInfo.Shop, PetService and the egg row's PromptPart") then
		K.flushErrors("shop_prompt")
		K.flushWarnings("shop_prompt", ALLOWED_WARNINGS)
		return
	end

	------------------------------------------------------------------ the part, LobbyInfo.Shop.Counter, the prompt
	checkCounterPart("shop prompt", part)
	local want = boardFrame() * CFrame.new(SHOP.Offset)
	T.check(near(part.Position, want.Position, 0.1) and part.CFrame.LookVector:Dot(want.LookVector) > 0.999,
		"shop prompt: the PromptPart stands at the WINGED PETS board's cf * (0, 2, -5.6), in front of the egg row (+-0.1)", fmt("%.3f off", (part.Position - want.Position).Magnitude))
	local counter = info.Shop.Counter
	local rbFace = shopFolder:FindFirstChild("RarityBoard") and shopFolder.RarityBoard:FindFirstChild("Face")
	T.check(type(counter) == "table" and counter.PromptPart == part and counter.Model == row and typeof(counter.Center) == "Vector3" and rbFace ~= nil
		and near(counter.Center, rbFace.Position, 0.05),
		"shop prompt: LobbyInfo.Shop.Counter = { PromptPart = the egg row's part, Center = the WINGED PETS board's Face, Model = the EggRow }")
	local stall = info.Shop.ItemShop
	T.check(type(info.Shop.Roulettes) == "table" and type(stall) == "table" and stall.PromptPart ~= nil and stall.Model ~= nil and stall.Lid ~= nil,
		"shop prompt: LobbyInfo.Shop.Roulettes and .ItemShop keep their shapes")
	local prompt = checkShopPrompt("shop prompt", part)
	T.eq(#promptsNamed(workspace, SHOP.Name), 1, "shop prompt: exactly one ShopPrompt in the workspace")
	checkMachinePrompts("shop prompt", info.Shop, Config)
	local arch = shopFolder:FindFirstChild("ShopArch")
	local sign = arch and arch:FindFirstChild("ShopSign")
	local subs = {}
	for _, d in ipairs(sign and sign:GetDescendants() or {}) do
		if d:IsA("TextLabel") and d.Name == "Sub" then
			subs[#subs + 1] = tostring(d.Text)
		end
	end
	T.check(#subs == 2 and subs[1] == SHOP.Caption and subs[2] == SHOP.Caption, "shop prompt: the arch sign's caption reads '" .. SHOP.Caption .. "' on both faces", table.concat(subs, " / "))

	------------------------------------------------------------------ triggers, the cooldown, InMatch, junk
	local players = {}
	local function opens(p, mark)
		return K.remotesFor("OpenPanel", p.UserId, mark)
	end
	local okRun, errRun = pcall(function()
		local a = Mock.AddPlayer("ShopPromptA", 987301)
		local b = Mock.AddPlayer("ShopPromptB", 987302)
		players = { a, b }
		K.advance(1)
		if not prompt then
			return
		end
		local mark = K.logSize()
		Mock.Trigger(prompt, a)
		K.advance(0.1)
		local first = opens(a, mark)
		local args = first[1] and first[1].args
		local keys = 0
		for _ in pairs(type(args) == "table" and type(args[2]) == "table" and args[2] or {}) do
			keys = keys + 1
		end
		T.check(#first == 1 and first[1].kind ~= "all" and args[1] == "Shop" and type(args[2]) == "table" and args[2].Tab == "Eggs" and keys == 1,
			"shop prompt: a trigger fires one OpenPanel('Shop', { Tab = 'Eggs' }) to that player only", #first .. " OpenPanel")
		T.eq(#opens(b, mark), 0, "shop prompt: ...nobody else's Shop opens")
		Mock.Trigger(prompt, a)
		K.advance(0.1)
		T.eq(#opens(a, mark), 1, "shop prompt: a second trigger within PROMPT_COOLDOWN (0.5 s) fires none")
		K.advance(0.6)
		Mock.Trigger(prompt, a)
		K.advance(0.1)
		T.eq(#opens(a, mark), 2, "shop prompt: ...and one again after the cooldown")
		b:SetAttribute(Config.Attr.InMatch, true)
		Mock.Trigger(prompt, b)
		K.advance(0.1)
		T.eq(#opens(b, mark), 0, "shop prompt: InMatch -> none")
		b:SetAttribute(Config.Attr.InMatch, nil)
		K.advance(0.6)
		local mark2, errs = K.logSize(), #Mock.Errors
		Mock.FireSignal(prompt, "Triggered", nil)
		Mock.FireSignal(prompt, "Triggered", a.Name)
		Mock.FireSignal(prompt, "Triggered", workspace)
		K.advance(0.2)
		T.check(#K.remotesFor("OpenPanel", nil, mark2) == 0 and #Mock.Errors == errs, "shop prompt: a trigger without a live player opens nothing and raises nothing")

		-------------------------------------------------------------- a missing part warns once
		local cursor = #Mock.Output
		PS.Init({ Shop = { Roulettes = info.Shop.Roulettes, ItemShop = info.Shop.ItemShop } })
		local warned = 0
		for i = cursor + 1, #Mock.Output do
			if Mock.Output[i].kind == "warn" and string.find(tostring(Mock.Output[i].text), SHOP.Missing, 1, true) then
				warned = warned + 1
			end
		end
		T.check(warned == 1 and #promptsNamed(workspace, SHOP.Name) == 0, "shop prompt: no Shop.Counter -> no ShopPrompt and one warn", warned .. " warns")

		-------------------------------------------------------------- lobby rebuilt (Review Focus 4)
		rebuild("shop prompt rebuild", function() end, function(built)
			local c2 = built.Shop and built.Shop.Counter
			local p2 = type(c2) == "table" and c2.PromptPart or nil
			T.check(p2 ~= nil and p2 ~= part and p2:IsDescendantOf(built.Folder) and c2.Model ~= nil and c2.Model.Name == "EggRow" and typeof(c2.Center) == "Vector3",
				"shop prompt rebuild: the new lobby's Counter has its own PromptPart on its own EggRow")
			PS.Init(built)
			local all = promptsNamed(workspace, SHOP.Name)
			T.check(#all == 1 and all[1].Parent == p2, "shop prompt rebuild: lobby rebuilt -> exactly one ShopPrompt, on the new part", #all .. " ShopPrompts")
			local pr2 = checkShopPrompt("shop prompt rebuild", p2)
			checkMachinePrompts("shop prompt rebuild", built.Shop, Config)
			if pr2 then
				K.advance(0.6)
				local mk = K.logSize()
				Mock.Trigger(pr2, a)
				K.advance(0.1)
				T.eq(#opens(a, mk), 1, "shop prompt rebuild: the new prompt opens the Shop")
			end
		end)

		-------------------------------------------------------------- the forced fallback shop
		rebuild("shop prompt fallback", function(_, LB)
			LB._ForceShopFallback = true
		end, function(built)
			local c2 = built.Shop and built.Shop.Counter
			local p2 = type(c2) == "table" and c2.PromptPart or nil
			local fb = built.Folder:FindFirstChild("ShopFallback")
			T.check(fb ~= nil and p2 ~= nil and p2:IsDescendantOf(fb) and c2.Model ~= nil and c2.Model:IsDescendantOf(fb) and typeof(c2.Center) == "Vector3",
				"shop prompt fallback: the fallback shop gives its own Counter { PromptPart, Center, Model }")
			checkCounterPart("shop prompt fallback", p2)
			PS.Init(built)
			local all = promptsNamed(workspace, SHOP.Name)
			T.check(#all == 1 and all[1].Parent == p2, "shop prompt fallback: exactly one ShopPrompt, on the fallback counter", #all .. " ShopPrompts")
			checkShopPrompt("shop prompt fallback", p2)
			checkMachinePrompts("shop prompt fallback", built.Shop, Config)
		end)
	end)
	-- the booted lobby's prompts back
	pcall(PS.Init, info)
	local back = promptsNamed(workspace, SHOP.Name)
	T.check(#back == 1 and back[1].Parent == part, "shop prompt: the booted egg row has its one ShopPrompt back", #back .. " ShopPrompts")
	checkMachinePrompts("shop prompt (back)", info.Shop, Config)
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(1)
	T.check(okRun, "shop prompt: the scenario body ran", tostring(errRun))
	K.flushErrors("shop_prompt")
	local allowed = { SHOP.Missing }
	for _, w in ipairs(ALLOWED_WARNINGS) do
		allowed[#allowed + 1] = w
	end
	K.flushWarnings("shop_prompt", allowed)
end)

----------------------------------------------------------------------------------------------------
-- egg_shelf_fx (Task 26, spec 16.5 "The world eggs"): the shelf's sparkles and its one glow
----------------------------------------------------------------------------------------------------
local SHELF_FX = {
	Rate = { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4, Secret = 5 },
	SecretColor = Color3.fromRGB(138, 92, 255), -- Secret's own colour is near black: its egg's violet glow (spec 5.6)
	Detail = "NC_Detail",
}

local function checkShelfFx(label, row, Config)
	local bad, emitters = {}, 0
	for _, r in ipairs(Config.Eggs.Order) do
		local egg = row:FindFirstChild("Egg_" .. r)
		local list = {}
		for _, d in ipairs(egg and egg:GetDescendants() or {}) do
			if d:IsA("ParticleEmitter") then
				list[#list + 1] = d
			end
		end
		emitters = emitters + #list
		local rate = SHELF_FX.Rate[r]
		if not egg then
			bad[#bad + 1] = r .. " missing"
		elseif not rate then
			if #list ~= 0 then
				bad[#bad + 1] = r .. fmt(" has %d emitters (none below Rare)", #list)
			end
		elseif #list ~= 1 then
			bad[#bad + 1] = r .. fmt(" has %d emitters (want 1)", #list)
		else
			local pe = list[1]
			local want = SHELF_FX.SecretColor
			for _, rd in ipairs(Config.Rarities) do
				if rd.Id == r and r ~= "Secret" then
					want = rd.Color
				end
			end
			local kp = pe.Color.Keypoints
			local att = pe.Parent
			if pe.Rate ~= rate then
				bad[#bad + 1] = r .. " Rate " .. tostring(pe.Rate)
			end
			if not (sameColor(kp[1].Value, want) and sameColor(kp[#kp].Value, want)) then
				bad[#bad + 1] = r .. " colour " .. tostring(kp[1].Value)
			end
			if math.abs(pe.LightEmission - 0.5) > 1e-6 or math.abs(pe.Lifetime.Min - 1.2) > 1e-6 or math.abs(pe.Lifetime.Max - 2) > 1e-6
				or math.abs(pe.Speed.Min - 0.3) > 1e-6 or math.abs(pe.Speed.Max - 0.8) > 1e-6 then
				bad[#bad + 1] = r .. " LightEmission / Lifetime / Speed"
			end
			if not CS:HasTag(pe, SHELF_FX.Detail) then
				bad[#bad + 1] = r .. " not tagged NC_Detail (Low graphics would not park it)"
			end
			if not (att and att:IsA("Attachment") and att.Name == "Center" and att.Parent == egg and near(att.WorldPosition, egg.Position, 0.05)) then
				bad[#bad + 1] = r .. " not on an Attachment Center at the egg's middle"
			end
			if (pe.Texture or "") ~= "" and string.find(pe.Texture, "rbxassetid", 1, true) then
				bad[#bad + 1] = r .. " has an uploaded texture"
			end
		end
	end
	T.check(#bad == 0 and emitters == 5, label .. ": Rare .. Secret eggs each hold one sparkle ParticleEmitter (Rate 1 / 2 / 3 / 4 / 5, the rarity colour (Secret violet), LightEmission 0.5, Lifetime 1.2-2, Speed 0.3-0.8, tagged NC_Detail) on an Attachment Center at the egg's middle; Common and Uncommon none",
		table.concat(bad, "; "))
	local lights = {}
	for _, d in ipairs(row:GetDescendants()) do
		if d:IsA("Light") then
			lights[#lights + 1] = d
		end
	end
	local shelf = row:FindFirstChild("EggShelf")
	local g = lights[1]
	local at = g and g.Parent and (g.Parent:IsA("Attachment") and g.Parent.WorldPosition or (g.Parent:IsA("BasePart") and g.Parent.Position)) or nil
	T.check(#lights == 1 and g:IsA("PointLight") and g.Name == "EggShelfGlow" and math.abs(g.Brightness - 1.0) < 1e-6 and g.Range == 10 and not g.Shadows
		and shelf ~= nil and at ~= nil and hdist(at, shelf.Position) <= 0.05 and at.Y >= shelf.Position.Y,
		label .. ": one PointLight EggShelfGlow 1.0 / 10 (no shadows) at the shelf's centre, on or over it", #lights .. " lights" .. (g and (" " .. g:GetFullName()) or ""))
	-- no part added: the sparkles and the glow ride on Attachments (shop-area 16.17.2: the row is the shelf, the seven eggs
	-- and the PromptPart; no board of its own)
	local want = 1 + #Config.Eggs.Order + 1
	T.eq(countParts(row), want, label .. ": the egg row adds no part (shelf + seven eggs + PromptPart)")
end

S.egg_shelf_fx = guarded("egg_shelf_fx", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local info = K.W.lobbyInfo
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local shopFolder = lobby and lobby:FindFirstChild("Shop")
	local row = shopFolder and shopFolder:FindFirstChild("EggRow")
	if not T.check(row ~= nil and type(info) == "table", "egg shelf fx: (precondition) the booted lobby's EggRow") then
		return
	end
	checkShelfFx("egg shelf fx", row, Config)
	-- every lobby light within the light rule (lamps <= 1.2 / 16, others <= 1.5 / 28, no spot / surface lights)
	local Lamps = Config.Sky.Lamps
	local bright, spots = {}, 0
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			spots = spots + 1
		elseif d:IsA("PointLight") then
			local lamp = d.Parent and Lamps.Names[d.Parent.Name]
			local ok = lamp and (d.Brightness <= 1.2 + 1e-6 and d.Range <= 16 and not d.Shadows) or (not lamp and d.Brightness <= 1.5 + 1e-6 and d.Range <= 28)
			if not ok then
				bright[#bright + 1] = d:GetFullName()
			end
		end
	end
	T.check(#bright == 0 and spots == 0, "egg shelf fx: every lobby light within the light rule", table.concat(bright, ", "))
	local stall = info.Shop and info.Shop.ItemShop
	T.check(stall ~= nil and stall.Model ~= nil and countParts(stall.Model) <= 60, "egg shelf fx: the trove stays <= 60 parts", stall and stall.Model and tostring(countParts(stall.Model)) or "no trove")
	-- the same set on a rebuilt lobby (a dev reset), and on the eggs' dressed meshes (the emitters stay on the Part)
	rebuild("egg shelf fx rebuild", function() end, function(built)
		local g2 = built.Folder:FindFirstChild("EggRow", true)
		if T.check(g2 ~= nil, "egg shelf fx rebuild: the rebuilt lobby has its EggRow") then
			checkShelfFx("egg shelf fx rebuild", g2, Config)
		end
	end)
	K.flushErrors("egg_shelf_fx")
	K.flushWarnings("egg_shelf_fx", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- shop_globe (shop-area T1, spec 16.17.1): the Gumball Globe key prop_roulette_globe and its in-globe eggs
----------------------------------------------------------------------------------------------------
-- polish 2026-11-09: 18 eggs (the 12 read ~25 % full) at 0.5 / the chase egg 0.54; the pile on the low keys
-- egg_<rarity>_pile (a few hundred tris each), only the chase egg on the full egg_<rarity>; Secret's star white-gold
local GLOBE = {
	Key = "prop_roulette_globe", Count = 18, Scale = 0.5, ChaseScale = 0.54, EggSize = Vector3.new(2.25, 3, 2.5),
	OldKey = "prop_roulette", -- review round 1: the uploaded cabinet every Machine wears while the globe has no id
	Parts = { "Body", "BodyDark", "BodyLight", "Bulb", "Emblem", "Fixed", "Glass", "Glow" },
	Centre = Vector3.new(0, 9.75, 0), Inner = 2.8, Margin = 0.1, Gap = 0.9, MaxTris = 4000, GlassT = 0.8,
	Footprint = Vector3.new(9, 14.5, 7),
	Seq = {
		Cloud = "Epic Common Uncommon Rare Common Uncommon Rare Common Uncommon Common Uncommon Common Uncommon Common Common Common Common Common",
		Storm = "Legendary Uncommon Rare Epic Uncommon Rare Epic Uncommon Rare Epic Uncommon Rare Epic Uncommon Rare Uncommon Rare Rare",
		Sky = "Mythic Rare Epic Legendary Rare Epic Legendary Rare Epic Legendary Rare Epic Rare Epic Rare Epic Epic Epic",
		Celestial = "Secret Epic Legendary Mythic Epic Legendary Mythic Epic Legendary Mythic Epic Legendary Epic Legendary Epic Legendary Epic Legendary",
	},
	-- the pile's dress key suffix (Egg2..Egg18); Egg1 (the chase egg) keeps the full key. Review round 2: "_pile", never
	-- "_low": MeshLibrary.LowKey("egg_<rarity>") reads "egg_<rarity>_low" as the full egg's LOD twin (SetLod "Low")
	PileKey = "_pile",
	SecretEmblem = Color3.fromRGB(255, 240, 200), -- polish: white-gold (the chat violet 180,150,255 twinned Cloud's Epic)
	SecretEgg = Color3.fromRGB(40, 40, 52):Lerp(Color3.fromRGB(138, 92, 255), 0.18), -- the shelf egg's Part colour
	NoEgg7 = "[LobbyMachineBuilder] prop_roulette_globe: no Egg7 attachment",
	CardH = 7.6,
}
GLOBE.Allowed = { "[DataService]", "[MeshLibrary]", GLOBE.NoEgg7 }

local function rarityColour(Config, id)
	for _, r in ipairs(Config.Rarities) do
		if r.Id == id then
			return r.Color
		end
	end
	return nil
end

-- the emblem colour of a roulette: its top rarity's colour (Secret -> the readable violet)
local function emblemColour(Config, roulette)
	local top = nil
	for _, r in ipairs(Config.Rarities) do
		if roulette.Odds and (roulette.Odds[r.Id] or 0) > 0 then
			top = r
		end
	end
	if top and top.Id == "Secret" then
		return GLOBE.SecretEmblem
	end
	return top and top.Color
end

-- the prop_roulette look f17dc0d passed: Secondary = the top rarity's Config colour (Secret: its own dark Config colour)
local function oldSecondary(Config, roulette)
	local top = nil
	for _, r in ipairs(Config.Rarities) do
		if roulette.Odds and (roulette.Odds[r.Id] or 0) > 0 then
			top = r
		end
	end
	return top and top.Color or Color3.fromRGB(255, 205, 80)
end

local function v3of(t)
	return type(t) == "table" and Vector3.new(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) or nil
end

-- an attachment { Pos, Rot } of a manifest -> its CFrame in model space (nil when malformed)
local function attCF(a)
	local pos = type(a) == "table" and (a.Pos or a.pos)
	local rot = type(a) == "table" and (a.Rot or a.rot)
	if type(pos) ~= "table" or type(rot) ~= "table" or type(rot[1]) ~= "table" or type(rot[2]) ~= "table" or type(rot[3]) ~= "table" then
		return nil
	end
	return CFrame.new(pos[1], pos[2], pos[3], rot[1][1], rot[1][2], rot[1][3], rot[2][1], rot[2][2], rot[2][3], rot[3][1], rot[3][2], rot[3][3])
end

local function cfNear(a, b, tol)
	tol = tol or 0.01
	return near(a.Position, b.Position, tol) and near(a.RightVector, b.RightVector, tol) and near(a.UpVector, b.UpVector, tol)
		and near(a.LookVector, b.LookVector, tol)
end

local function warnsSince(cursor, needle)
	local n = 0
	for i = (cursor or 0) + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and string.find(tostring(o.text), needle, 1, true) then
			n = n + 1
		end
	end
	return n
end

-- the manifest of the globe: Egg1..Egg18, the scales, the bounds, the budget, the eight parts, the egg spots in the glass
local function checkGlobeManifest(ML)
	local man = ML and ML.Manifest(GLOBE.Key)
	if not T.check(type(man) == "table" and type(man.Raw) == "table", "globe manifest: MeshLibrary.Manifest('" .. GLOBE.Key .. "') loads (src/shared/MeshManifests)") then
		return nil
	end
	local att, eggs, others = man.Attachments or {}, 0, {}
	for name in pairs(att) do
		if string.match(name, "^Egg%d+$") then
			eggs = eggs + 1
		else
			others[#others + 1] = name
		end
	end
	local missing = {}
	for i = 1, GLOBE.Count do
		if not attCF(att["Egg" .. i]) then
			missing[#missing + 1] = "Egg" .. i
		end
	end
	T.check(eggs == GLOBE.Count and #missing == 0 and #others == 0, "globe manifest: exactly eighteen attachments Egg1..Egg18, each a Pos + 3 x 3 Rot",
		fmt("%d Egg attachments, missing %s, others %s", eggs, table.concat(missing, ","), table.concat(others, ",")))
	local meta = man.Raw.Meta or {}
	T.check(meta.eggScale == GLOBE.Scale and meta.chaseScale == GLOBE.ChaseScale, "globe manifest: Meta.eggScale 0.5, Meta.chaseScale 0.54",
		tostring(meta.eggScale) .. " / " .. tostring(meta.chaseScale))
	local b = man.Bounds or {}
	local lo, hi, size = v3of(b.Min), v3of(b.Max), v3of(b.Size)
	T.check(lo ~= nil and hi ~= nil and size ~= nil and size.X <= GLOBE.Footprint.X + 1e-6 and size.Z <= GLOBE.Footprint.Z + 1e-6
		and hi.Y <= GLOBE.Footprint.Y + 1e-6 and lo.Y >= -1e-6 and math.abs(lo.X + hi.X) <= 0.6 and math.abs(lo.Z + hi.Z) <= 0.6,
		"globe manifest: inside the 9 x 7 footprint round the pivot, from the ground to y <= 14.5", size and fmt("size %.2f x %.2f x %.2f, min y %.2f, max y %.2f", size.X, size.Y, size.Z, lo.Y, hi.Y) or "no bounds")
	T.check(type(man.Raw.Tris) == "number" and man.Raw.Tris <= GLOBE.MaxTris, "globe manifest: <= 4000 triangles (propBig)", tostring(man.Raw.Tris))
	local names, byName = {}, {}
	for _, p in ipairs(man.Parts) do
		names[#names + 1] = p.name
		byName[p.name] = p
	end
	table.sort(names)
	T.eq(table.concat(names, " "), table.concat(GLOBE.Parts, " "), "globe manifest: eight parts Body / BodyDark / BodyLight / Bulb / Emblem / Fixed / Glass / Glow")
	local em, gl, body = byName.Emblem, byName.Glass, byName.Body
	T.check(em ~= nil and em.material == "Neon" and type(em.color) == "table" and em.color[1] == "Secondary"
		and body ~= nil and type(body.color) == "table" and body.color[1] == "Primary"
		and gl ~= nil and gl.material == "Glass" and math.abs((tonumber(gl.transparency) or 0) - GLOBE.GlassT) < 1e-6,
		"globe manifest: Body = Primary, Emblem = Neon Secondary, Glass = Glass at Transparency 0.80 (polish: clearer, was 0.70)")
	-- the egg spots: each scaled egg's middle inside the glass (centre (0, 9.75, 0), r 2.8 - 0.1), pivots >= 0.9 apart
	local bad, spots = {}, {}
	for i = 1, GLOBE.Count do
		local cf = attCF(att["Egg" .. i])
		if cf then
			local s = (i == 1) and GLOBE.ChaseScale or GLOBE.Scale
			local mid = (cf * CFrame.new(0, GLOBE.EggSize.Y * s / 2, 0)).Position
			if (mid - GLOBE.Centre).Magnitude > GLOBE.Inner - GLOBE.Margin then
				bad[#bad + 1] = fmt("Egg%d middle %.2f from the centre", i, (mid - GLOBE.Centre).Magnitude)
			end
			if cf.UpVector.Y < 0.7 then
				bad[#bad + 1] = fmt("Egg%d lies over (up %.2f)", i, cf.UpVector.Y)
			end
			spots[i] = cf.Position
		end
	end
	for i = 1, GLOBE.Count do
		for j = i + 1, GLOBE.Count do
			if spots[i] and spots[j] and (spots[i] - spots[j]).Magnitude < GLOBE.Gap then
				bad[#bad + 1] = fmt("Egg%d - Egg%d %.2f apart", i, j, (spots[i] - spots[j]).Magnitude)
			end
		end
	end
	local chase = spots[1]
	T.check(#bad == 0, "globe manifest: every egg's middle inside the glass by >= 0.1 stud, standing (up > 0.7), the pivots >= 0.9 apart", table.concat(bad, "; "))
	-- (polish: the pile climbs to the back; an egg in front of the chase egg may stand lower than the chase egg's middle,
	-- shop_area_globe.py --check ray-casts its face >= 85 % clear)
	local front = true
	local chaseMid = chase and chase.Y + GLOBE.EggSize.Y * GLOBE.ChaseScale / 2
	for i = 2, GLOBE.Count do
		if chase and spots[i] and spots[i].Z < chase.Z - 0.05 and math.abs(spots[i].X - chase.X) < 0.9 and spots[i].Y + GLOBE.EggSize.Y * GLOBE.Scale > chaseMid then
			front = false
		end
	end
	T.check(chase ~= nil and chase.Z < 0 and front, "globe manifest: the chase egg Egg1 stands in the front half, no egg in front of it reaching over its middle", chase and tostring(chase) or "no Egg1")
	return man
end

S.shop_globe = guarded("shop_globe", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local ML = req("shared/MeshLibrary")
	local LMB = req("server/Services/LobbyMachineBuilder")
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local G = LMB and LMB.GLOBE
	if not T.check(LMB ~= nil and type(G) == "table" and type(LMB.Rarities) == "function" and type(LMB.GlobeEggs) == "function" and ML ~= nil and lobby ~= nil,
		"globe: (precondition) the booted lobby, MeshLibrary and server/Services/LobbyMachineBuilder with GLOBE / Rarities / GlobeEggs") then
		return
	end
	T.check(G.Key == GLOBE.Key and G.Count == GLOBE.Count and G.Chase == 1 and G.Scale == GLOBE.Scale and G.ChaseScale == GLOBE.ChaseScale
		and typeof(G.EggSize) == "Vector3" and near(G.EggSize, GLOBE.EggSize, 1e-6),
		"globe: GLOBE = { Key prop_roulette_globe, Count 18, Chase 1, Scale 0.5, ChaseScale 0.54, EggSize 2.25 x 3 x 2.5 }")
	-- polish: the pile's dress keys are the low eggs, the chase egg's the full key; Secret's star white-gold
	local lowKeys, badLow = 0, {}
	for _, r in ipairs(Config.Rarities) do
		local id = r.Id
		local want = "egg_" .. string.lower(id)
		local okK, full, low = pcall(function()
			return LMB.EggKey(id, false), LMB.EggKey(id, true)
		end)
		if okK and full == want and low == want .. GLOBE.PileKey and low ~= full .. "_low" then
			lowKeys = lowKeys + 1
		else
			badLow[#badLow + 1] = id .. " " .. tostring(full) .. " / " .. tostring(low)
		end
	end
	T.check(type(LMB.EggKey) == "function" and lowKeys == #Config.Rarities,
		"globe: LobbyMachineBuilder.EggKey(rarity, pile) = egg_<rarity> for the chase egg, egg_<rarity>_pile for the pile (never egg_<rarity>_low: MeshLibrary.LowKey's LOD-twin name)",
		table.concat(badLow, "; "))
	T.check(typeof(LMB.SECRET_EMBLEM) == "Color3" and sameColor(LMB.SECRET_EMBLEM, GLOBE.SecretEmblem), "globe: LobbyMachineBuilder.SECRET_EMBLEM is white-gold 255,240,200",
		tostring(LMB.SECRET_EMBLEM))

	------------------------------------------------------------------ Rarities (pure): the four sequences of 16.17.1
	local byId = {}
	for _, r in ipairs(Config.Roulettes) do
		byId[r.Id] = r
		local want = GLOBE.Seq[r.Id]
		if want then
			local okR, seq = pcall(LMB.Rarities, r, GLOBE.Count)
			T.eq(okR and type(seq) == "table" and table.concat(seq, " ") or tostring(seq), want, "globe: " .. r.Id .. "'s chase egg + pile (Rarities, top first, the pile by weight, interleaved)")
		end
	end
	T.check(byId.Cloud and byId.Storm and byId.Sky and byId.Celestial, "globe: (precondition) the four roulettes Cloud / Storm / Sky / Celestial")
	local okDuo, duo = pcall(LMB.Rarities, { Id = "Duo", Odds = { Mythic = 60, Secret = 40 } }, GLOBE.Count)
	T.eq(okDuo and type(duo) == "table" and table.concat(duo, " ") or tostring(duo), "Secret" .. string.rep(" Mythic", GLOBE.Count - 1), "globe: a roulette with two rarities fills the pile with the lower one")
	local okSolo, solo = pcall(LMB.Rarities, { Id = "Solo", Odds = { Rare = 1 } }, 4)
	T.eq(okSolo and type(solo) == "table" and table.concat(solo, " ") or tostring(solo), "Rare Rare Rare Rare", "globe: a one-rarity roulette shows that egg everywhere")

	------------------------------------------------------------------ the manifest
	local man = checkGlobeManifest(ML)

	------------------------------------------------------------------ the default run: no globe id -> today's machine,
	-- the UPLOADED prop_roulette cabinet (review round 1: prop_roulette has a shipped id, so the live game dresses every
	-- Machine with it; the voxel Part build is only what a place without that asset shows)
	local okSt, st = pcall(ML.Status, GLOBE.Key)
	T.check(okSt and st == "missing", "globe: MeshLibrary.Status('prop_roulette_globe') is 'missing' (no id in this build)", tostring(st))
	-- (--mesh reconfigures MeshLibrary with the fixture's pet ids only: there prop_roulette is missing too and the Machine
	-- stays on the Part build; the shipped MeshIds of the default run carry its uploaded id)
	local okOld, stOld = pcall(ML.Status, GLOBE.OldKey)
	local oldShipped = okOld and stOld ~= "missing"
	if not MESH_MODE then
		T.check(oldShipped, "globe: (precondition) MeshLibrary.Status('prop_roulette') is not 'missing' (its uploaded id ships in MeshIds)", tostring(stOld))
	end
	local wantKey = oldShipped and GLOBE.OldKey or nil
	local shop = lobby:FindFirstChild("Shop")
	local bootBad = {}
	for _, r in ipairs(Config.Roulettes) do
		local m = shop and shop:FindFirstChild("Roulette_" .. r.Id)
		local body = m and m:FindFirstChild("Machine")
		if not (m and body) then
			bootBad[#bootBad + 1] = r.Id .. " (no Machine)"
		end
		local wantS = oldSecondary(Config, r)
		local dressOk = (wantKey == nil and body and body:GetAttribute("ML_DressKey") == nil)
			or (body and body:GetAttribute("ML_DressKey") == wantKey and typeof(body:GetAttribute("ML_Primary")) == "Color3" and sameColor(body:GetAttribute("ML_Primary"), r.Color)
				and typeof(body:GetAttribute("ML_Secondary")) == "Color3" and sameColor(body:GetAttribute("ML_Secondary"), wantS))
		if body and not dressOk then
			bootBad[#bootBad + 1] = r.Id .. " Machine ML_DressKey " .. tostring(body:GetAttribute("ML_DressKey")) .. " / " .. tostring(body:GetAttribute("ML_Primary")) .. " / " .. tostring(body:GetAttribute("ML_Secondary"))
		end
		if m and m:FindFirstChild("GlobeEggs") then
			bootBad[#bootBad + 1] = r.Id .. " has GlobeEggs"
		end
		if m and not (m:FindFirstChild("PromptPart") and m:FindFirstChild("PriceAnchor") and m:FindFirstChild("DomeGlow")) then
			bootBad[#bootBad + 1] = r.Id .. " lost PromptPart / PriceAnchor / DomeGlow"
		end
	end
	T.check(#bootBad == 0, "globe (default run): every Roulette_<Id>'s Machine wears today's uploaded cabinet (ML_DressKey prop_roulette, ML_Primary = the roulette colour, ML_Secondary = its top rarity's Config colour, as f17dc0d), no GlobeEggs, PromptPart / PriceAnchor / DomeGlow", table.concat(bootBad, "; "))
	T.eq(warnsSince(0, "[LobbyMachineBuilder]"), 0, "globe (default run): no [LobbyMachineBuilder] warn in the boot log")

	------------------------------------------------------------------ the dress request (default run: the globe asked first, then prop_roulette)
	local _, S0 = shopFrame()
	local origins = {}
	rebuild("globe request", function(_, LB)
		LB._Kit = { Targets = {}, Clouds = {} }
	end, function(built)
		local LB = req("server/Services/LobbyBuilder")
		local recs, olds, order = {}, {}, {}
		for i, rec in ipairs(LB._Kit and LB._Kit.Targets or {}) do
			if rec.Key == GLOBE.Key then
				recs[#recs + 1] = rec
				order[rec] = i
			elseif rec.Key == GLOBE.OldKey then
				olds[#olds + 1] = rec
				order[rec] = i
			end
		end
		local oldBad = {}
		local f0 = built.Folder:FindFirstChild("Shop")
		for _, r in ipairs(Config.Roulettes) do
			local m = f0 and f0:FindFirstChild("Roulette_" .. r.Id)
			local body = m and m:FindFirstChild("Machine")
			local mine, globe = {}, nil
			for _, rec in ipairs(olds) do
				if body and rec.Target == body then
					mine[#mine + 1] = rec
				end
			end
			for _, rec in ipairs(recs) do
				if body and rec.Target == body then
					globe = rec
				end
			end
			local rec = mine[1]
			local look = rec and rec.Look or {}
			if #mine ~= 1 then
				oldBad[#oldBad + 1] = r.Id .. fmt(" (%d prop_roulette requests)", #mine)
			elseif not (globe and order[globe] < order[rec] and typeof(rec.Origin) == "CFrame" and cfNear(rec.Origin, globe.Origin, 1e-4)
				and typeof(look.Primary) == "Color3" and sameColor(look.Primary, r.Color) and typeof(look.Secondary) == "Color3" and sameColor(look.Secondary, oldSecondary(Config, r))) then
				oldBad[#oldBad + 1] = r.Id .. " prop_roulette request not after the globe's at its origin with f17dc0d's look (" .. tostring(look.Primary) .. " / " .. tostring(look.Secondary) .. ")"
			end
		end
		T.check(#oldBad == 0 and #olds == #Config.Roulettes, "globe: while prop_roulette_globe is missing each Machine asks for exactly one 'prop_roulette' dress after the globe's (same origin, Primary = the roulette colour, Secondary = its top rarity's Config colour)",
			#olds .. " requests; " .. table.concat(oldBad, "; "))
		local bad = {}
		local f = built.Folder:FindFirstChild("Shop")
		for _, r in ipairs(Config.Roulettes) do
			local m = f and f:FindFirstChild("Roulette_" .. r.Id)
			local body = m and m:FindFirstChild("Machine")
			local hit = {}
			for _, rec in ipairs(recs) do
				if body and rec.Target == body then
					hit[#hit + 1] = rec
				end
			end
			local rec = hit[1]
			if #hit ~= 1 then
				bad[#bad + 1] = r.Id .. fmt(" (%d requests)", #hit)
			else
				local o = rec.Origin
				local toCentre = flat(S0 - o.Position).Unit
				if not (typeof(o) == "CFrame" and math.abs(o.Position.Y - Config.Lobby.Origin.Y) <= 0.01 and o.UpVector.Y > 0.9999 and o.LookVector:Dot(toCentre) > 0.9999) then
					bad[#bad + 1] = r.Id .. " origin not the ground centre facing the shop centre"
				end
				local look = rec.Look or {}
				local wantE = emblemColour(Config, r)
				if not (typeof(look.Primary) == "Color3" and sameColor(look.Primary, r.Color) and typeof(look.Secondary) == "Color3" and wantE and sameColor(look.Secondary, wantE)) then
					bad[#bad + 1] = r.Id .. " look " .. tostring(look.Primary) .. " / " .. tostring(look.Secondary)
				end
				origins[r.Id] = o
				local anchor, glow, pp = m:FindFirstChild("PriceAnchor"), m:FindFirstChild("DomeGlow"), m:FindFirstChild("PromptPart")
				if not (anchor and near(anchor.Position, (o * CFrame.new(0, 14.2 + GLOBE.CardH / 2, 0)).Position, 0.01)
					and glow and near(glow.Position, (o * CFrame.new(0, 9.5, 0)).Position, 0.01)
					and pp and cfNear(pp.CFrame, o * CFrame.new(0, 2, -5.4), 0.01) and near(pp.Size, Vector3.new(5, 4, 3), 0.01)) then
					bad[#bad + 1] = r.Id .. " price card / DomeGlow / PromptPart moved"
				end
				if body:GetAttribute("ML_DressKey") ~= wantKey or m:FindFirstChild("GlobeEggs") then
					bad[#bad + 1] = r.Id .. " not on prop_roulette or has GlobeEggs while the globe key is missing"
				end
			end
		end
		T.check(#bad == 0 and #recs == #Config.Roulettes, "globe: one prop_roulette_globe request per machine on its Machine, origin = the ground centre facing the shop centre, Look.Primary = the roulette colour, Look.Secondary = its top rarity's colour (Celestial: the Secret violet 180,150,255); the price card at 14.2 + 3.8, DomeGlow at 9.5, PromptPart (0, 2, -5.4) unchanged; the Machine on prop_roulette, no GlobeEggs",
			#recs .. " requests; " .. table.concat(bad, "; "))
	end)

	------------------------------------------------------------------ dressed: GlobeEggs from the manifest's Egg<i> attachments
	local LB = req("server/Services/LobbyBuilder")
	local M = LB and LB._Mesh
	local realTag = M and M.tag
	local function forceGlobe(undo)
		if MESH_MODE then
			-- --mesh: fixture holders (Status -> "loading") for the globe and the seven egg keys, removed after
			local keys = { GLOBE.Key }
			for _, k in pairs(EGG_KEYS) do
				keys[#keys + 1] = k
				keys[#keys + 1] = k .. GLOBE.PileKey -- polish: the pile eggs
			end
			T.check(fixtureHolders(keys, undo) > 0, "globe (--mesh): the fixture MeshLibrary root exists")
		elseif M and realTag then
			-- the default run has no globe id: the tag's answer is forced to "dressed" (after the real call records the request)
			M.tag = function(target, key, ...)
				local r = realTag(target, key, ...)
				if key == GLOBE.Key then
					return true
				end
				return r
			end
			undo[#undo + 1] = function()
				M.tag = realTag
			end
		end
	end
	rebuild("globe dressed", function(undo, LB2)
		LB2._Kit = { Targets = {}, Clouds = {} }
		forceGlobe(undo)
	end, function(built, cursor)
		local LB2 = req("server/Services/LobbyBuilder")
		local eggRecs, oldN = {}, 0
		for _, rec in ipairs(LB2._Kit and LB2._Kit.Targets or {}) do
			if typeof(rec.Target) == "Instance" and rec.Target.Name:match("^GlobeEgg%d+$") then
				eggRecs[rec.Target] = eggRecs[rec.Target] or {}
				table.insert(eggRecs[rec.Target], rec)
			end
			if rec.Key == GLOBE.OldKey then
				oldN = oldN + 1
			end
		end
		T.eq(oldN, 0, "globe dressed: a dressed globe asks for no 'prop_roulette' dress (the fallback only follows a refused globe tag)")
		local f = built.Folder:FindFirstChild("Shop")
		local bad, dressBad = {}, {}
		local pileFallback = 0
		for _, r in ipairs(Config.Roulettes) do
			local m = f and f:FindFirstChild("Roulette_" .. r.Id)
			local body = m and m:FindFirstChild("Machine")
			local ge = m and m:FindFirstChild("GlobeEggs")
			local o = origins[r.Id]
			local seq = {}
			for w in string.gmatch(GLOBE.Seq[r.Id] or "", "%S+") do
				seq[#seq + 1] = w
			end
			if not (ge and ge:IsA("Model") and ge.Parent == m and body and o and man) then
				bad[#bad + 1] = r.Id .. " (no GlobeEggs Model beside Machine)"
			else
				if body:FindFirstChild("GlobeEggs", true) then
					bad[#bad + 1] = r.Id .. " GlobeEggs inside the dressed Machine"
				end
				local kids = ge:GetChildren()
				if #kids ~= GLOBE.Count then
					bad[#bad + 1] = r.Id .. fmt(" %d GlobeEgg models", #kids)
				end
				for i = 1, GLOBE.Count do
					local em = ge:FindFirstChild("GlobeEgg" .. i)
					local s = (i == 1) and GLOBE.ChaseScale or GLOBE.Scale
					local want = o * attCF(man.Attachments["Egg" .. i])
					local part = em and em:FindFirstChild("Egg")
					local mesh = part and part:FindFirstChildOfClass("SpecialMesh")
					local rarity = seq[i]
					-- (polish) the chase egg on the full key, the pile on the pile eggs
					local key = rarity and ("egg_" .. string.lower(rarity) .. ((i == 1) and "" or GLOBE.PileKey))
					local colour = (rarity == "Secret") and GLOBE.SecretEgg or rarityColour(Config, rarity)
					if not (em and em:IsA("Model") and part and part:IsA("BasePart")) then
						bad[#bad + 1] = fmt("%s GlobeEgg%d missing", r.Id, i)
					else
						local nParts = 0
						for _, d in ipairs(em:GetDescendants()) do
							if d:IsA("BasePart") then
								nParts = nParts + 1
							end
						end
						if nParts ~= 1 then
							bad[#bad + 1] = fmt("%s GlobeEgg%d has %d parts", r.Id, i, nParts)
						end
						if not cfNear(em:GetPivot(), want, 0.01) then
							bad[#bad + 1] = fmt("%s GlobeEgg%d pivot off the Egg%d attachment", r.Id, i, i)
						end
						if not (near(part.Size, GLOBE.EggSize * s, 0.005) and mesh and mesh.MeshType == Enum.MeshType.Sphere
							and near(part.Position, (want * CFrame.new(0, GLOBE.EggSize.Y * s / 2, 0)).Position, 0.01)) then
							bad[#bad + 1] = fmt("%s GlobeEgg%d Part not the %.2f-scaled Sphere egg standing on its pivot", r.Id, i, s)
						end
						if not (part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery) then
							bad[#bad + 1] = fmt("%s GlobeEgg%d Part not anchored / ghost", r.Id, i)
						end
						if not (colour and sameColor(part.Color, colour)) then
							bad[#bad + 1] = fmt("%s GlobeEgg%d colour %s (want %s's)", r.Id, i, tostring(part.Color), tostring(rarity))
						end
						if em:GetAttribute("ML_Scale") ~= s then
							bad[#bad + 1] = fmt("%s GlobeEgg%d ML_Scale %s", r.Id, i, tostring(em:GetAttribute("ML_Scale")))
						end
						if CS:HasTag(em, "NC_Detail") ~= (i ~= 1) then
							bad[#bad + 1] = fmt("%s GlobeEgg%d NC_Detail %s", r.Id, i, tostring(CS:HasTag(em, "NC_Detail")))
						end
						if CS:HasTag(em, Config.Tags.Spin) or CS:HasTag(part, Config.Tags.Spin) then
							bad[#bad + 1] = fmt("%s GlobeEgg%d tagged Spin", r.Id, i)
						end
						local recs = eggRecs[em] or {}
						if #recs ~= 1 or recs[1].Key ~= key or typeof(recs[1].Origin) ~= "CFrame" or not cfNear(recs[1].Origin, want, 0.01) then
							bad[#bad + 1] = fmt("%s GlobeEgg%d dress request %s (want one %s at the pivot)", r.Id, i, recs[1] and tostring(recs[1].Key) or "none", tostring(key))
						end
						local okE, stE = pcall(ML.Status, key)
						if okE and stE ~= "missing" then
							if em:GetAttribute("ML_DressKey") ~= key then
								dressBad[#dressBad + 1] = fmt("%s GlobeEgg%d ML_DressKey %s", r.Id, i, tostring(em:GetAttribute("ML_DressKey")))
							end
						elseif MESH_MODE then
							dressBad[#dressBad + 1] = fmt("%s GlobeEgg%d: %s still missing under --mesh", r.Id, i, tostring(key))
						elseif em:GetAttribute("ML_DressKey") ~= nil then
							-- (polish) a key with no id (the low eggs before their upload): the rarity-tinted Part sphere stays
							dressBad[#dressBad + 1] = fmt("%s GlobeEgg%d dressed %s though %s is missing", r.Id, i, tostring(em:GetAttribute("ML_DressKey")), tostring(key))
						else
							pileFallback = pileFallback + 1
						end
					end
				end
				if MESH_MODE then
					local wantE = emblemColour(Config, r)
					if not (body:GetAttribute("ML_DressKey") == GLOBE.Key and typeof(body:GetAttribute("ML_Primary")) == "Color3" and sameColor(body:GetAttribute("ML_Primary"), r.Color)
						and typeof(body:GetAttribute("ML_Secondary")) == "Color3" and wantE and sameColor(body:GetAttribute("ML_Secondary"), wantE)) then
						dressBad[#dressBad + 1] = r.Id .. " Machine not tagged prop_roulette_globe with ML_Primary / ML_Secondary"
					end
				end
			end
		end
		T.check(#bad == 0, "globe dressed: each Roulette_<Id> holds a GlobeEggs Model (beside Machine) of GlobeEgg1..18 at the manifest's Egg<i> attachments, one Sphere Part 'Egg' each (2.25 x 3 x 2.5 x 0.5, Egg1 x 0.54, standing on its pivot, anchored, no collide / touch / query, the rarity colour, Secret dark violet), ML_Scale, NC_Detail on 2..18 only, no Spin, one request at the pivot in the Rarities order: Egg1 egg_<rarity>, the pile egg_<rarity>_pile",
			table.concat(bad, "; "))
		if MESH_MODE then
			T.check(#dressBad == 0, "globe dressed (--mesh): Machine tagged prop_roulette_globe (ML_Primary / ML_Secondary), every GlobeEgg ML_DressKey egg_<rarity> (Egg1) / egg_<rarity>_pile (the pile)", table.concat(dressBad, "; "))
		else
			T.check(#dressBad == 0, "globe dressed: ML_DressKey on the eggs whose key is not missing (the chase egg's uploaded egg_<rarity>), none where it is missing (--mesh checks every one)", table.concat(dressBad, "; "))
			-- (polish) the low keys have no id in this build: every pile egg is its rarity-tinted Part sphere
			T.eq(pileFallback, #Config.Roulettes * (GLOBE.Count - 1), "globe dressed: until egg_<rarity>_pile is uploaded every pile egg (4 x 17) stays the rarity-tinted Part sphere, undressed")
		end
		T.eq(warnsSince(cursor, "[LobbyMachineBuilder]"), 0, "globe dressed: no [LobbyMachineBuilder] warn")
	end)

	------------------------------------------------------------------ a manifest without Egg7: one warn, no GlobeEggs, the machine stands
	local copy = nil
	if man then
		copy = {}
		for k, v in pairs(man) do
			copy[k] = v
		end
		copy.Attachments = {}
		for k, v in pairs(man.Attachments or {}) do
			if k ~= "Egg7" then
				copy.Attachments[k] = v
			end
		end
	end
	rebuild("globe without Egg7", function(undo, LB2)
		LB2._Kit = { Targets = {}, Clouds = {} }
		forceGlobe(undo)
		LMB._Manifest = function()
			return copy
		end
		undo[#undo + 1] = function()
			LMB._Manifest = nil
		end
	end, function(built, cursor)
		local f = built.Folder:FindFirstChild("Shop")
		local bad = {}
		for _, r in ipairs(Config.Roulettes) do
			local m = f and f:FindFirstChild("Roulette_" .. r.Id)
			if not (m and m:FindFirstChild("Machine") and m:FindFirstChild("PromptPart") and m:FindFirstChild("PriceAnchor")) then
				bad[#bad + 1] = r.Id .. " lost Machine / PromptPart / PriceAnchor"
			elseif m:FindFirstChild("GlobeEggs") then
				bad[#bad + 1] = r.Id .. " built GlobeEggs"
			end
		end
		T.check(copy ~= nil and #bad == 0, "globe without Egg7: no GlobeEggs anywhere, every machine keeps Machine / PromptPart / PriceAnchor", table.concat(bad, "; "))
		T.eq(warnsSince(cursor, GLOBE.NoEgg7), 1, "globe without Egg7: exactly one warn '" .. GLOBE.NoEgg7 .. "'")
		T.check(built.Shop and built.Shop.Roulettes and built.Shop.Roulettes.Cloud and built.Shop.Roulettes.Cloud.PromptPart ~= nil, "globe without Egg7: LobbyInfo.Shop.Roulettes still carry their PromptParts")
	end)

	T.check(LMB._Manifest == nil and LB and LB._Kit == nil and (M == nil or M.tag == realTag) and holdersGone(GLOBE.Key),
		"globe: the hooks (_Manifest, _Kit, Mesh.tag) and the fixture holders are back")
	K.flushErrors("shop_globe")
	K.flushWarnings("shop_globe", GLOBE.Allowed)
end)

----------------------------------------------------------------------------------------------------
-- shop_egg_row (shop-area T2, spec 16.17.2): the Egg Guide removed, the seven-egg row with its rarity labels under the
-- WINGED PETS board, the walk-up E prompt there, no orphan
----------------------------------------------------------------------------------------------------
S.shop_egg_row = guarded("shop_egg_row", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local info = K.W.lobbyInfo
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local ML = req("shared/MeshLibrary")
	local LBD = req("server/Services/LobbyBoardBuilder")
	if not T.check(lobby ~= nil and type(info) == "table" and type(info.Shop) == "table" and ML ~= nil and LBD ~= nil,
		"egg row: (precondition) the booted lobby, its LobbyInfo.Shop, MeshLibrary and server/Services/LobbyBoardBuilder") then
		return
	end
	T.check(type(LBD.EggRow) == "function" and LBD.EggGuide == nil, "egg row: LobbyBoardBuilder.EggRow exists, LobbyBoardBuilder.EggGuide is gone")
	T.check(info.Shop.EggGuide == nil and (type(info.Shop.Counter) ~= "table" or info.Shop.Counter.Model == nil or info.Shop.Counter.Model.Name == "EggRow"),
		"egg row: nothing named EggGuide in LobbyInfo (Counter.Model is the EggRow)")

	------------------------------------------------------------------ the booted lobby
	local row = checkEggRow("egg row", lobby, Config, info)
	local part = row and row:FindFirstChild("PromptPart")
	if part then
		checkShopPrompt("egg row", part)
	end
	T.eq(#promptsNamed(workspace, SHOP.Name), 1, "egg row: exactly one ShopPrompt in the workspace, on the row's PromptPart")
	checkMachinePrompts("egg row", info.Shop, Config)

	------------------------------------------------------------------ a rebuilt lobby (the dress requests; --mesh: fixture holders)
	rebuild("egg row rebuild", function(undo, LB)
		LB._Kit = { Targets = {}, Clouds = {} }
		if MESH_MODE then
			T.check(fixtureHolders(EGG_KEYS, undo) > 0, "egg row (--mesh): the fixture MeshLibrary root exists")
		end
	end, function(built, cursor)
		local LB = req("server/Services/LobbyBuilder")
		local row2 = checkEggRow("egg row rebuild", built.Folder, Config, built)
		T.check(row2 ~= nil and row2 ~= row, "egg row rebuild: the new lobby has its own EggRow")
		checkEggRequests("egg row rebuild", LB, row2, Config, ML)
		local failed = 0
		for i = (cursor or 0) + 1, #Mock.Output do
			local t = tostring(Mock.Output[i].text)
			if string.find(t, "egg row failed", 1, true) or string.find(t, "rarity board failed", 1, true) then
				failed = failed + 1
			end
		end
		T.eq(failed, 0, "egg row rebuild: no 'egg row failed' / 'rarity board failed' warn")
	end)

	------------------------------------------------------------------ the forced fallback shop keeps its own counter
	rebuild("egg row fallback", function(_, LB)
		LB._ForceShopFallback = true
	end, function(built)
		local fb = built.Folder:FindFirstChild("ShopFallback")
		local c2 = built.Shop and built.Shop.Counter
		T.check(fb ~= nil and type(c2) == "table" and c2.Model ~= nil and c2.Model.Name == "ShopCounter" and c2.Model:IsDescendantOf(fb) and c2.PromptPart ~= nil,
			"egg row fallback: the forced fallback shop keeps its own ShopCounter as the Counter")
		T.check(built.Folder:FindFirstChild("EggRow", true) == nil and built.Folder:FindFirstChild("EggGuide", true) == nil,
			"egg row fallback: no egg row (and no Egg Guide) in the fallback shop")
	end)
	local LB = req("server/Services/LobbyBuilder")
	T.check(LB and LB._ForceShopFallback == nil and LB._Kit == nil and workspace:FindFirstChild("NimbusLobby") == lobby, "egg row: the hooks are back to nil, the booted lobby is back")
	K.flushErrors("shop_egg_row")
	K.flushWarnings("shop_egg_row", ALLOWED_WARNINGS)
end)

return S
