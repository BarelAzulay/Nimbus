-- LobbyBoardBuilder (lobby shop 2026-11-07, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.9 / 5.6 / 5.10): the
-- lobby's newer boards, drawn with LobbyBuilder's own helpers (passed in as H), so they look exactly like the other notice
-- boards and add only one local to LobbyBuilder's near-full main chunk.
--
--   LobbyBoardBuilder.EggGuide(parent, cf, H) -> Model "EggGuide"
--     cf = the board's ground CFrame (front -Z, towards the reader; WorldPivot = cf). Built at the Sky Trove's old spot on
--     the shop island (the trove moved to the plaza lawn):
--       * EggGuideBoard: an 11 x 8 notice board (H.noticeBoard tags it prop_board_s, its Face stays) whose SurfaceGui
--         reads "Every egg hatches a random pet of its rarity" under its header, then names the seven eggs
--         (Config.Eggs.Names) in their rarity colours, left to right and row by row in Config.Eggs.Order (two columns:
--         seven names at the 0.6-stud floor do not fit one row). The Secret egg's name is a light violet (its rarity
--         colour is near-black).
--       * EggShelf: a low stone shelf (17.6 x 0.8 x 2.6) 3 studs in front of the board.
--       * Egg_<Rarity>: the seven 3D eggs standing on the shelf 2.5 studs apart in the same order, left to right as the
--         reader sees them (the reader's left is the board's +X), each Mesh.tag'ged with its egg_<rarity> key at the egg's
--         bottom centre (the Blender pivot). Until a key has an id the egg is its Part fallback: a 2.25 x 3 x 2.5
--         ellipsoid (a block with a Sphere SpecialMesh, CourseBuilder's way: a Roblox Ball part is always round) in the
--         rarity colour, SmoothPlastic, not colliding; the Secret egg dark with its violet tint.
--   LobbyBoardBuilder.Leaderboard(parent, L, H) -> Model "LobbyLeaderboard" | nil
--     The global leaderboard's board on the south lawn (spec 5.10 "World"): placed with H.plazaSpot at polar 295 degrees,
--     r 48, clearance 9 (nil when the spot is not free: plazaSpot has warned "plaza decor skipped"), on the lawn layer,
--     facing the plaza centre (H.faceCentre). The layout Task 23's prop_board_lb mesh shares (pivot = the ground centre,
--     front -Z towards the centre):
--       * Face: 16 x 13 x 0.4, centred 9.5 up, navy SmoothPlastic, not colliding but queryable: the client's PlayerGui
--         SurfaceGui (LeaderboardController, 50 px per stud = 800 x 650 px, ten rows at the 0.6-stud floor) adorns it
--         and its tabs take taps. It stays a Part under the mesh (Mesh.tag keeps "Face").
--       * two 1 x 17 x 1 timber posts at local x +-8.9 on stone feet, a 0.6-stud frame around the face (four bars) with
--         a plank back, an 18.6 x 0.6 x 2.4 roof at y 16.9 with a ridge on it.
--     Mesh.tag(model, "prop_board_lb", cf, nil, { "Face" }); the Part build shows until that key has an id.
--
--   H = { noticeBoard, surfaceGui, signPanel, signText, box, Mesh, C, MAT, LAWN, plazaSpot, faceCentre } (LobbyBuilder's
--   layout field L.H, built once per Build)
-- No light, no prompt, no animation (the server never animates). Plain Lua 5.1 syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LobbyBoardBuilder = {}

-- the egg mesh keys, literal (tools/mesh_keys.py reads the keys from the source)
local EGG_KEYS = {
	Common = "egg_common",
	Uncommon = "egg_uncommon",
	Rare = "egg_rare",
	Epic = "egg_epic",
	Legendary = "egg_legendary",
	Mythic = "egg_mythic",
	Secret = "egg_secret",
}
local EGG = { Size = Vector3.new(2.25, 3, 2.5), Step = 2.5 } -- the Blender egg's size (studs), the gap between centres
-- the stone shelf and its centre's distance in front of the board: 3 studs (not 4) and 17.6 wide (the eggs need 17.25), so
-- at the trove's old spot its end keeps 0.8 stud from the Celestial machine's base (at 4 / 18 it touched it)
local SHELF = { Size = Vector3.new(17.6, 0.8, 2.6), Z = -3 }
local SECRET = {
	Body = Color3.fromRGB(40, 40, 52), -- Config.Rarities Secret
	Tint = Color3.fromRGB(138, 92, 255), -- the Secret egg's violet glow (spec 5.6)
	Text = Color3.fromRGB(178, 150, 255), -- its name on the navy board
}
local PX = { Title = 52, Info = 30 } -- px at 50 px per stud: 1.04 stud / 0.6 stud (the World text rule)
-- the leaderboard board: where it stands (polar degrees, radius, plazaSpot clearance; spec 5.10 checked the clearance
-- against the fountain, the NPC spots, the benches, the flower beds and the spawn) and its layout (shared with Task 23)
local BOARD = {
	Angle = 295, R = 48, Clear = 9,
	Face = Vector3.new(16, 13, 0.4), FaceY = 9.5,
	PostX = 8.9, PostH = 17,
	Rim = 0.6, -- the frame's width around the face
	Roof = Vector3.new(18.6, 0.6, 2.4), RoofY = 16.9,
}

local function rarityColor(id)
	for _, r in ipairs(Config.Rarities) do
		if r.Id == id then
			return r.Color
		end
	end
	return Color3.fromRGB(200, 200, 210)
end

-- the egg rarities in Config.Eggs.Order (only those with a mesh key)
local function eggOrder()
	local out = {}
	local eggs = type(Config.Eggs) == "table" and Config.Eggs or {}
	for _, id in ipairs(type(eggs.Order) == "table" and eggs.Order or {}) do
		if EGG_KEYS[id] then
			out[#out + 1] = id
		end
	end
	return out
end

local function eggName(id)
	local names = type(Config.Eggs) == "table" and type(Config.Eggs.Names) == "table" and Config.Eggs.Names or {}
	return names[id] or (id .. " Egg")
end

-- 550 x 400 px canvas (11 x 8 studs): a 1.04-stud header, the 0.6-stud line (wrapped), then the names in two columns
-- (0.6 stud). The bottom fifth stays empty: the eggs on the shelf (3.8 studs tall) stand in front of it, and every
-- letter starts above 3.9 studs, so it shows over the eggs from a standing player's eye.
local function guideSign(face, order, H)
	local gui = H.surfaceGui(face, Enum.NormalId.Front)
	local panel = H.signPanel(gui)
	H.signText(panel, "EGG GUIDE", "Title", PX.Title, H.C.TextGold, "Header", 0.04, 0.025, 0.92, 0.14)
	H.signText(panel, "Every egg hatches a random pet of its rarity", "Body", PX.Info, H.C.Text, "Sub", 0.05, 0.175, 0.9, 0.2, nil, true)
	for i, id in ipairs(order) do
		local row, col = math.floor((i - 1) / 2), (i - 1) % 2
		local x = (col == 0) and 0.05 or 0.5
		if i == #order and col == 0 then
			x = 0.275 -- an odd last name sits in the middle of its row
		end
		local color = (id == "Secret") and SECRET.Text or rarityColor(id)
		H.signText(panel, eggName(id), "Heading", PX.Info, color, "EggName_" .. id, x, 0.39 + row * 0.105, 0.45, 0.1)
	end
	gui.Parent = face
	return gui
end

function LobbyBoardBuilder.EggGuide(parent, cf, H)
	local model = Instance.new("Model")
	model.Name = "EggGuide"
	model.Parent = parent
	local order = eggOrder()
	local face = H.noticeBoard(model, cf, 11, 8, "EggGuideBoard")
	guideSign(face, order, H)
	-- the shelf: its bottom on the board's ground (the lawn), the part over the court's stone just sinks into it
	local shelfCF = cf * CFrame.new(0, SHELF.Size.Y / 2, SHELF.Z)
	H.box(model, "EggShelf", shelfCF, SHELF.Size, H.C.StoneLight, { Collide = true, Material = H.MAT.SmoothPlastic })
	for i, id in ipairs(order) do
		-- the reader faces the board's front (-Z): their left is +X, so the first egg stands at +X
		local eggCF = cf * CFrame.new((#order + 1 - 2 * i) * EGG.Step / 2, SHELF.Size.Y, SHELF.Z)
		local color = rarityColor(id)
		if id == "Secret" then
			color = SECRET.Body:Lerp(SECRET.Tint, 0.18)
		end
		local egg = H.box(model, "Egg_" .. id, eggCF * CFrame.new(0, EGG.Size.Y / 2, 0), EGG.Size, color, { Material = H.MAT.SmoothPlastic })
		local shape = Instance.new("SpecialMesh")
		shape.MeshType = Enum.MeshType.Sphere -- the ellipsoid of the block's size
		shape.Parent = egg
		H.Mesh.tag(egg, EGG_KEYS[id], eggCF)
	end
	model.WorldPivot = cf
	return model
end

function LobbyBoardBuilder.Leaderboard(parent, L, H)
	local pos = H.plazaSpot(BOARD.Angle, BOARD.R, BOARD.Clear, L)
	if not pos then
		return nil -- not free: plazaSpot has warned "plaza decor skipped"
	end
	local cf = H.faceCentre(pos - Vector3.new(0, H.LAWN, 0)) -- on the lawn layer, the front (-Z) towards the centre
	local C, solid = H.C, { Collide = true }
	local model = Instance.new("Model")
	model.Name = "LobbyLeaderboard"
	model.Parent = parent
	local fw, fh, rim = BOARD.Face.X, BOARD.Face.Y, BOARD.Rim
	H.box(model, "Face", cf * CFrame.new(0, BOARD.FaceY, 0), BOARD.Face, C.Navy, { Material = H.MAT.SmoothPlastic, Query = true })
	H.box(model, "Back", cf * CFrame.new(0, BOARD.FaceY, BOARD.Face.Z / 2 + 0.15), Vector3.new(fw + 2 * rim, fh + 2 * rim, 0.3), C.Plank, solid)
	for _, s in ipairs({ -1, 1 }) do
		H.box(model, "Frame", cf * CFrame.new(0, BOARD.FaceY + s * (fh + rim) / 2, 0), Vector3.new(fw + 2 * rim, rim, rim), C.Plank, solid)
		H.box(model, "Frame", cf * CFrame.new(s * (fw + rim) / 2, BOARD.FaceY, 0), Vector3.new(rim, fh, rim), C.Plank, solid)
		H.box(model, "Post", cf * CFrame.new(s * BOARD.PostX, BOARD.PostH / 2, 0), Vector3.new(1, BOARD.PostH, 1), C.PlankDark, solid)
		H.box(model, "PostFoot", cf * CFrame.new(s * BOARD.PostX, 0.4, 0), Vector3.new(1.6, 0.8, 1.6), C.StoneDark, solid)
	end
	H.box(model, "Roof", cf * CFrame.new(0, BOARD.RoofY, 0), BOARD.Roof, C.PlankDark)
	H.box(model, "Ridge", cf * CFrame.new(0, BOARD.RoofY + BOARD.Roof.Y / 2 + 0.25, 0), Vector3.new(BOARD.Roof.X - 1.4, 0.5, 1.4), C.Rose)
	model.WorldPivot = cf -- before the tag: the mesh's offset is measured from the model's pivot
	H.Mesh.tag(model, "prop_board_lb", cf, nil, { "Face" })
	return model
end

return LobbyBoardBuilder
