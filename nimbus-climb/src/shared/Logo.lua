-- Logo: the game's name lockup on the title screen's and the loading screen's header (the owner's picks 2026-11-13,
-- .superpowers/sign-logo-pitch/FINAL_OPTIONS.md "LOGO"). The final logo is L1, the voxel storm logo: a Blender picture
-- that needs ONE upload after the owner's OK. Its TextureIds key is Config.Loading.Images.Logo; until that key has an id
-- (id 0: not in TextureIds) the header shows L2, the "Storm plaque", built live here:
--   * a cloud plaque of stepped navy blocks (#2E3A7A, a 3 px #3B4A9A lit top, a 3 px #171C4F lip; three bumps rising
--     above the body; square blocks, no corner)
--   * NIMBUS CLIMB one FredokaOne letter at a time (Title role, 26 px), each at its fixed bounce (N 0, I -3, M +2, B -2,
--     U +3, S -1, C +2, L -2, I +3, M -3, B 0): a white face under a hard three-band gradient (NIMBUS cream, CLIMB gold),
--     ONE 3 px brown outline (U6's Title exception, Theme.OutlineOnPlate) and two offset copies behind it at +3 / +6 for
--     the block side
--   * a gold pixel lightning bolt (four squares, a darker right edge) hanging from the plaque's underside
-- Everything is in the pitch's px (the lockup is 216 x 48 from the bumps' top, the bolt hangs to 64) times `Scale`.
--   Logo.Key(Config)               -> the L1 picture's TextureIds key (Config.Loading.Images.Logo)
--   Logo.Fit(plateW, plateH)       -> the scale that fits a header plate (the pitch's 46 px header zone, 12 px each side)
--   Logo.Build(parent, opts)       -> the logo: opts.Image (an "rbxassetid://" string: the L1 picture) or nil (L2), Scale,
--                                     Position, AnchorPoint, ZIndex. Attribute Logo = "L1" | "L2"
-- Shared (the loading screen in ReplicatedFirst uses it once Shared is there); requires only Theme. Plain Lua 5.1 syntax.

local Theme = require(script.Parent:WaitForChild("Theme"))

local Logo = {}

Logo.KEY = "nimbus_logo" -- when Config has no Loading.Images.Logo
Logo.W, Logo.H, Logo.BOLT_B = 216, 48, 64 -- the lockup's box (from the bumps' top) and the bolt's lowest row
-- the L1 picture's footprint at the same scale: the pitch's 224 wide (the slab plus its overhanging puffs), the exported
-- PNG's shape (.superpowers/sign-logo-pitch/img/final/nimbus_logo_L1_1024.png, 1024 x 259)
Logo.L1 = { W = 224, H = 57 }
Logo.SIZE = 26 -- the letters' text size
Logo.WORDS = { "NIMBUS", "CLIMB" }
Logo.BOUNCE = { 0, -3, 2, -2, 3, -1, 2, -2, 3, -3, 0 }
-- each letter's advance in FredokaOne (em, read from its font file: tools/fixtures/fonts/FredokaOne-Regular.ttf), so the
-- lockup is spaced the same wherever it is measured
Logo.ADVANCE = { N = 0.72, I = 0.257, M = 0.87, B = 0.646, U = 0.726, S = 0.583, C = 0.679, L = 0.587 }
Logo.GAP, Logo.SPACE = 2, 9 -- between letters (their outlines meet, the faces do not), between the words

function Logo.Key(Config)
	local images = type(Config) == "table" and type(Config.Loading) == "table" and Config.Loading.Images
	return type(images) == "table" and type(images.Logo) == "string" and images.Logo or Logo.KEY
end

-- the scale for a header plate plateW x plateH (design px): the pitch's lockup sits in a 46 px header zone and keeps
-- 12 px clear each side
function Logo.Fit(plateW, plateH)
	return math.max(0.5, math.min((plateW - 24) / Logo.W, plateH / 46))
end

local function block(name, colour, x, y, w, h, s, z, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = colour
	f.Position = UDim2.fromOffset(math.floor(x * s + 0.5), math.floor(y * s + 0.5))
	f.Size = UDim2.fromOffset(math.max(1, math.floor(w * s + 0.5)), math.max(1, math.floor(h * s + 0.5)))
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- the plaque: the body with its lit top and lip, notched corners, three stepped bumps along its top
local function plaque(root, s, z)
	local Sign = Theme.Sign
	local parts = {}
	local function piece(name, colour, x, y, w, h)
		local f = block(name, colour, x, y, w, h, s, z, root)
		f:SetAttribute("LogoPart", "Plaque")
		parts[#parts + 1] = f
		return f
	end
	piece("PlaqueBody", Sign.NavyLight, 3, 8, 210, 40)
	piece("SideL", Sign.NavyLight, 0, 11, 3, 34)
	piece("SideR", Sign.NavyLight, 213, 11, 3, 34)
	piece("PlaqueTop", Sign.NavyTop, 3, 8, 210, 3)
	piece("PlaqueLip", Sign.NavyLip, 3, 45, 210, 3)
	for _, cx in ipairs({ 52, 108, 164 }) do
		piece("Bump", Sign.NavyLight, cx - 26, 3, 52, 8)
		piece("BumpLedge", Sign.NavyTop, cx - 26, 3, 52, 3)
		piece("BumpTop", Sign.NavyTop, cx - 18, 0, 36, 3)
	end
	return parts
end

-- one letter: its two block-side copies in the side layers (every side under every face, so a neighbour's side never
-- covers a face), then the banded face with its one brown outline in the face layer. Each copy carries LogoLetter =
-- its place and Bounce = its fixed bounce
local function letter(layers, ch, index, x, w, s, gold)
	local Sign = Theme.Sign
	local bounce = Logo.BOUNCE[index] or 0
	local size = math.max(8, math.floor(Logo.SIZE * s + 0.5))
	local stroke = math.max(1, math.floor(3 * s + 0.5))
	local function copy(name, colour, outline, dy, layer)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Text = ch
		Theme.Style(t, "Title", { Size = size, Color = colour })
		Theme.StyleTitle(t, "Logo")
		t.Position = UDim2.fromOffset(math.floor(x * s + 0.5), math.floor((10 + bounce + dy) * s + 0.5))
		t.Size = UDim2.fromOffset(math.max(1, math.floor(w * s + 0.5)), math.floor(34 * s + 0.5))
		t.ZIndex = layer.ZIndex
		t:SetAttribute("LogoLetter", index)
		t:SetAttribute("Bounce", bounce)
		local o = Instance.new("UIStroke")
		o.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		o.LineJoinMode = Enum.LineJoinMode.Round
		o.Color = outline
		o.Thickness = stroke
		o.Parent = t
		t.Parent = layer
		return t
	end
	copy("LetterSide2", Sign.NavyLip, Sign.NavyLip, 6, layers[1])
	copy("LetterSide1", gold and Sign.GoldLip or Sign.CloudSide, gold and Sign.GoldLip or Sign.CloudSide, 3, layers[2])
	local face = copy("LetterFace", Color3.new(1, 1, 1), Sign.Text, 0, layers[3])
	local bands = Instance.new("UIGradient")
	bands.Rotation = 90
	if gold then
		bands.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Sign.GoldLight),
			ColorSequenceKeypoint.new(0.45, Sign.GoldLight),
			ColorSequenceKeypoint.new(0.4501, Sign.Gold),
			ColorSequenceKeypoint.new(0.8, Sign.Gold),
			ColorSequenceKeypoint.new(0.8001, Sign.GoldDeep),
			ColorSequenceKeypoint.new(1, Sign.GoldDeep),
		})
	else
		bands.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Sign.Tile),
			ColorSequenceKeypoint.new(0.55, Sign.Tile),
			ColorSequenceKeypoint.new(0.5501, Sign.CloudShade),
			ColorSequenceKeypoint.new(1, Sign.CloudShade),
		})
	end
	bands.Parent = face
	return face
end

-- the bolt: four gold squares stepping down and left, each with a darker right edge
local function bolt(root, s, z)
	local Sign = Theme.Sign
	for _, b in ipairs({ { 177, 46 }, { 174, 50 }, { 176, 54 }, { 172, 59 } }) do
		local sq = block("Bolt", Sign.Gold, b[1], b[2], 5, 5, s, z, root)
		sq:SetAttribute("LogoPart", "Bolt")
		local edge = Instance.new("Frame")
		edge.Name = "Edge"
		edge.BorderSizePixel = 0
		edge.BackgroundColor3 = Sign.GoldLip
		edge.AnchorPoint = Vector2.new(1, 0)
		edge.Position = UDim2.fromScale(1, 0)
		edge.Size = UDim2.new(0, math.max(1, math.floor(2 * s + 0.5)), 1, 0)
		edge.ZIndex = z
		edge.Parent = sq
	end
end

function Logo.Build(parent, opts)
	opts = opts or {}
	local s = tonumber(opts.Scale) or 1
	local z = tonumber(opts.ZIndex) or 1
	local root
	if type(opts.Image) == "string" and opts.Image ~= "" then
		-- L1: the uploaded Blender picture (transparent PNG), its footprint at the same scale, never stretched
		root = Instance.new("ImageLabel")
		root.BackgroundTransparency = 1
		root.Image = opts.Image
		root.ScaleType = Enum.ScaleType.Fit
		root.Size = UDim2.fromOffset(math.floor(Logo.L1.W * s + 0.5), math.floor(Logo.L1.H * s + 0.5))
		root:SetAttribute("Logo", "L1")
	else
		root = Instance.new("Frame")
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromOffset(math.floor(Logo.W * s + 0.5), math.floor(Logo.BOLT_B * s + 0.5))
		root:SetAttribute("Logo", "L2")
		plaque(root, s, z)
		bolt(root, s, z)
		-- the letters, measured in the Title face and centred on the plaque
		local widths, total, n = {}, 0, 0
		for w, word in ipairs(Logo.WORDS) do
			for i = 1, #word do
				local ch = word:sub(i, i)
				local cw = Logo.ADVANCE[ch] and Logo.ADVANCE[ch] * Logo.SIZE
				if not cw then
					local ok, m = pcall(Theme.Measure, ch, "Title", Logo.SIZE)
					cw = ok and m and m.X or Logo.SIZE * 0.7
				end
				n = n + 1
				widths[n] = { ch, cw, w == 2 }
				total = total + cw + (i > 1 and Logo.GAP or 0)
			end
			if w < #Logo.WORDS then
				total = total + Logo.SPACE
			end
		end
		local x = (Logo.W - total) / 2
		local layers = {}
		for i, name in ipairs({ "Sides2", "Sides1", "Faces" }) do
			local layer = Instance.new("Frame")
			layer.Name = name
			layer.BackgroundTransparency = 1
			layer.Size = UDim2.fromScale(1, 1)
			layer.ZIndex = z + i
			layer.Parent = root
			layers[i] = layer
		end
		local index = 0
		for w, word in ipairs(Logo.WORDS) do
			for i = 1, #word do
				index = index + 1
				local info = widths[index]
				letter(layers, info[1], index, x, info[2], s, info[3])
				x = x + info[2] + Logo.GAP
			end
			x = x - Logo.GAP + Logo.SPACE
		end
	end
	root.Name = opts.Name or "Logo"
	root.ZIndex = z
	root.AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0)
	if opts.Position then
		root.Position = opts.Position
	end
	root.Parent = parent
	return root
end

return Logo
