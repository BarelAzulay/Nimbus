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
--   LobbyBoardBuilder.Leaderboard(parent, L, H) -> Model | nil   (Task 11: the leaderboard board on the south lawn)
--
--   H = { noticeBoard, surfaceGui, signPanel, signText, box, Mesh, C, MAT, LAWN }
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

return LobbyBoardBuilder
