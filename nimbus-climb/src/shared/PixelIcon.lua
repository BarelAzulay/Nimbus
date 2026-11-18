-- PixelIcon: the kit B icon set (U2 of .superpowers/slop-audit/round3/BUILD_PLAN.md, findings 5 and 7; decisions 2 and 3).
-- Every icon is a 9 x 9 one-colour bitmap kept as data: nine rows of nine cells, "#" drawn and "." empty, rows joined by
-- "/". The first 27 are the pitch's own (kit_pitch_mockups.html:523-550, the `I` table), ported as they are so the icons in
-- the game are the ones the owner saw; the rest are the ones the loading screen, menu, settings and credits need.
--   PixelIcon.Bitmaps[name]            the bitmap string
--   PixelIcon.Runs(name)               its merged rectangles { { x, y, w, h }, ... } in cells (nil for an unknown name)
--   PixelIcon.New(parent, name, px, colour)  a transparent px x px Frame (attribute PixelIcon = name) holding one Frame per
--                                      merged rectangle, snapped to whole pixels (cell = floor(px / 9), centred); nil for
--                                      an unknown name. px under 9 draws at 9; a px between multiples of 9 warns once
--                                      (PixelIcon.Warned). (U9-7 look) Under a UIScale the cells are whole screen px
--                                      (round(cell x scale), attribute CellPx), refitted when that scale changes
--   PixelIcon.Fit(icon)                (U9-7 look) fits an icon to the UIScales above it now (New and moves do it)
--   PixelIcon.Snap(px)                 the multiple of 9 nearest px (at least 9): the size an icon for a px glyph draws at
--   PixelIcon.Host(host, name, px[, colour])  (U7a) the icon centred in a text object, following its TextColor3 (unless
--                                      colour), TextTransparency and ZIndex (and with px nil its TextSize): an icon a
--                                      caller treats as a glyph
--   PixelIcon.Lead(label, name[, opts]) (U7a) the icon in front of a label's text ("<coin> 1,250"), the text inset past it;
--                                      opts.After / Count / Of: a rating after the text ("Easy" + 3 lit stars of 5); opts.Gap;
--                                      opts.Room (render gate): a left-aligned label keeps the trailing icons' room inside
--                                      its box (its text truncates first, the icons never leave the box).
--                                      Placed from TextBounds, or Theme.MeasureLabel when that reads 0 (a server: world signs)
--   PixelIcon.Clear(label[, opts])     (U7b) takes a Lead icon off again (a row whose mark comes and goes), insets back
--   PixelIcon.Mark(label, name|nil[, opts])  (U7b) Lead / Clear only when the mark changed: a status line set each refresh
--   PixelIcon.Set(host, name|nil[, px])      (U7b) Host only when the icon changed (the text emptied): a glyph label
-- Runs: each row's horizontal runs, then runs with the same columns in the rows below merged into one taller rectangle,
-- so an icon is a handful of Frames (smoke: at most 25). A generated sheet (one upload) can replace the Frames later in
-- dense grids; it would be drawn from this same data.
-- Requires nothing at load (Shared, usable from ReplicatedFirst); Lead requires Theme (its sibling) on the first text it
-- must measure itself (U7b review: a server's TextBounds read 0). Plain Lua 5.1-compatible syntax only.

local PixelIcon = {}

PixelIcon.Bitmaps = {
	-- the pitch's icons (kit_pitch_mockups.html, exactly as drawn there)
	paw = "..##.##../..##.##../##.....##/##.###.##/..#####../.#######./.#######./..##.##../.........",
	book = "........./###...###/####.####/####.####/####.####/####.####/####.####/.###.###./.........",
	house = "....#..../...###.../..#####../.#######./#########/.#######./.##...##./.##...##./.##...##.",
	stats = "........./......##./......##./...##.##./...##.##./##.##.##./##.##.##./##.##.##./.........",
	bag = "...###.../..#...#../.#######./#########/#########/#########/#########/#########/.#######.",
	arrow = "........./....#..../....##.../#######../########./#######../....##.../....#..../.........",
	gear = "...###.../.#.###.#./.#######./###...###/###...###/###...###/.#######./.#.###.#./...###...",
	heart = "........./.##...##./####.####/#########/#########/.#######./..#####../...###.../....#....",
	bolt = ".....###./....###../...###.../..######./....###../...###.../..###..../.##....../.........",
	note = "........./........./#########/#.......#/#..###..#/#..###..#/#.......#/#########/.........", -- a banknote (cash)
	coin = "..#####../.#######./####.####/####.####/####.####/####.####/####.####/.#######./..#####..",
	gem = "........./.#######./#########/#########/.#######./..#####../...###.../....#..../.........",
	gift = ".##...##./#..#.#..#/.#######./#########/#########/.###.###./.###.###./.###.###./.###.###.",
	check = "........./........#/.......##/#.....##./##...##../.##.##.../..###..../...#...../.........",
	x = "........./.##...##./.###.###./..#####../...###.../..#####../.###.###./.##...##./.........",
	sword = "......###/.....####/....####./...####../#.####.../.####..../..##...../.#.##..../#...#....",
	star = "....#..../....#..../...###.../#########/.#######./..#####../..#####../.##...##./.#.....#.",
	flame = "....#..../...##..../...###.../.#.####../.#######./#########/###...###/.##...##./..#####..",
	flake = "....#..../.#..#..#./..#.#.#../...###.../#########/...###.../..#.#.#../.#..#..#./....#....",
	moon = "...####../..###..../.###...../.###...../.###...../.###...../.####...#/..######./...####..",
	cloud = "........./...##..../..####.#./.#######./#########/#########/.#######./........./.........",
	apple = ".....##../....#..../.###.###./#########/#########/#########/#########/.#######./..##.##..",
	bell = "........./........./##.....##/##.....##/#########/##.....##/##.....##/........./.........",
	sprout = "........./###...###/####.####/.###.###./...###.../....#..../....#..../..#####../.#######.",
	plus = "...###.../...###.../...###.../#########/#########/#########/...###.../...###.../...###...",
	dash = "........./##..##.../.##..##../..##..##./...##..##/..##..##./.##..##../##..##.../.........",
	down = "........./........./##.....##/###...###/.###.###./..#####../...###.../....#..../.........",

	-- the screens' icons (U2): loading, menu, settings, credits
	play = ".#......./.###...../.#####.../.#######./.########/.#######./.#####.../.###...../.#.......",
	scroll = ".#######./#########/.#.....#./.#.###.#./.#.....#./.#.###.#./.#.....#./#########/.#######.",
	music = "...######/...######/...#....#/...#....#/...#....#/.###..###/####.####/####.####/.##...##.", -- a musical note
	speaker = "....#..../...##..#./..###...#/#####.#.#/#####.#.#/#####.#.#/..###...#/...##..#./....#....",
	monitor = "#########/#.......#/#.......#/#.......#/#.......#/#########/....#..../...###.../.#######.",
	shake = "#.#...#.#/...###.../#########/###...###/##..#..##/###...###/#########/........./#.#...#.#", -- camera shake
	mouse = "....#..../..#####../.##.#.##./.##.#.##./.#######./.#######./.#######./.#######./..#####..",
	bulb = "..#####../.#######./##..#####/##.######/.#######./..#####../........./..#####../...###...", -- a tip
	swap = "........./.....#.../########./.....#.../........./...#...../.########/...#...../.........",
	token = "..#####../.#######./####.####/###...###/##.....##/##.....##/#########/.#######./..#####..", -- the Cloud Token coin
	-- (U5) the settings scale's - (the pitch's plus without its upright)
	minus = "........./........./........./#########/#########/#########/........./........./.........",

	-- (U7a) the tiles' and the shop's icons the pitch did not draw (Config.Icons, NeonKit.Icon), in the pitch's style:
	-- solid shapes, a one-cell gap for every inner line
	pack = "..#####../.##...##./.#######./#########/##.....##/##.###.##/##.###.##/##.....##/.#######.", -- a backpack (Items)
	shield = ".#######./####.####/####.####/#.......#/####.####/.###.###./.###.###./..##.##../...###...", -- the Team
	trophy = "#########/#.#####.#/#.#####.#/.#######./..#####../...###.../....#..../..#####../.#######.", -- the Arena
	mountain = "...#...../..###..../..###.#../.#######./.########/#########/#########/#########/.........", -- the Obby (two peaks)
	key = "..####.../.##..##../.##..##../..####.../...##..../...####../...##..../...###.../...##....", -- the Dungeon
	crown = "........./#...#...#/##.###.##/#########/#########/#.#.#.#.#/#########/........./.........", -- the Ring, VIP
	sparkle = "....#..../....#..../...###.../..#####../#########/..#####../...###.../....#..../....#....", -- Fusion
	lock = "..#####../.##...##./.##...##./.##...##./#########/####.####/###...###/####.####/#########",
	box = "........./##.....##/###...###/#########/####.####/####.####/####.####/#########/.........", -- Packs
	ticket = "........./#########/##.######/.#######./.#.#####./.#######./##.######/#########/.........", -- Passes (notches, a torn line)
	potion = "...###.../....#..../....#..../..#####../.##...##./#########/#########/#########/.#######.", -- Boosts
	-- the Roulettes: the gumball globe (two off-centre balls so it never reads as a face), its neck and a solid base
	gumball = "..#####../.##.####./.#######./.####.##./..#####../...###.../..#####../.#######./#########",
	egg = "...###.../..#####../.#######./.#######./#########/#########/#########/.#######./..#####..",
	wrench = ".##..##../.##..##../.######../..####.../...##..../...##..../...##..../...##..../...##....", -- Repair
	chest = "........./.#######./#########/#########/........./###...###/####.####/#########/#########", -- the Sky Trove
	people = ".##...##./####.####/.##...##./........./.###.###./####.####/####.####/####.####/.........", -- the Trove's group
	clock = "..#####../.###.###./####.####/####.####/####...##/#########/#########/.#######./..#####..", -- a play-time tier

	-- (U7b) the battle HUD's elements and actions, the dungeon, the Training Place and the Home window's stations (the
	-- emoji they replace in brackets), same style
	drop = "....#..../....#..../...###.../..#####../.#######./.##.####./.#######./..#####../.........", -- Water
	leaf = ".....####/...######/..####.##/.####.###/.###.####/.##.####./..####.../.#......./#........", -- Nature
	target = "..#####../.#.....#./#..###..#/#.#...#.#/#.#.#.#.#/#.#...#.#/#..###..#/.#.....#./..#####..", -- the Target button
	skull = "..#####../.#######./#########/##..#..##/##..#..##/####.####/.#######./..#.#.#../..#####..", -- a dungeon boss room
	hourglass = "#########/.#######./..#####../...###.../....#..../...#.#.../..#...#../.#######./#########", -- a wait
	glass = ".####..../##..##.../#....#.../#....#.../##..##.../.####.#../......##./.......##/........#", -- search
	castle = "#.#.#.#.#/#########/#########/##.###.##/#########/####.####/###...###/###...###/###...###", -- the Sky Castle
	berry = "...#.#.../..#####../.#######./##.###.##/#########/.###.###./.#######./..#####../...###...", -- the Berry Farm
	pot = "..#.#.#../..#.#.#../........./#########/#########/.#######./.#######./..#####../.##...##.", -- the Food Machine
	weight = "..#####../.#.....#./.#.....#./..#####../.#######./#########/#########/#########/.#######.", -- training (a kettlebell: a dumbbell read as an H)
	vault = "#########/#.......#/#..###..#/#.#...#.#/#.#.#.#.#/#.#...#.#/#..###..#/#########/.#.....#.", -- the Vault
	fence = ".#..#..#./.#..#..#./#########/.#..#..#./.#..#..#./#########/.#..#..#./.#..#..#./.........", -- the Yard Fence
	fountain = "....#..../..#.#.#../.#..#..#./....#..../..#####../....#..../#########/#########/.#######.", -- the Fountain
	basket = "...###.../..#...#../.#.....#./#########/#.#.#.#.#/#########/.#.#.#.#./.#######./.........", -- the berry basket
	pip = "........./........./..#####../..#####../..#####../..#####../..#####../........./.........", -- a progress pip
	up = "........./....#..../...###.../..#####../.###.###./###...###/##.....##/........./.........", -- a bounce pad (down, turned)
	left = "........./....#..../...##..../..#######/.########/..#######/...##..../....#..../.........", -- the D-pad left (arrow, turned)
	shift = "....#..../...###.../..##.##../.##...##./####.####/..##.##../..##.##../..#####../.........", -- the Shift key (hollow up arrow)
}
-- tick is the pitch's check (one drawing, two names)
PixelIcon.Bitmaps.tick = PixelIcon.Bitmaps.check

local cache = {}

-- (U5) the sizes warned about: [px] = 1. A size between multiples of 9 draws whole cells off-centre in a padded box, so
-- New warns once per such size (pass 18, 27, 36, ...)
PixelIcon.Warned = {}

-- the merged rectangles of an icon, { x, y, w, h } in cells (0-based), nil for an unknown name
function PixelIcon.Runs(name)
	if cache[name] then
		return cache[name]
	end
	local bmp = PixelIcon.Bitmaps[name]
	if type(bmp) ~= "string" then
		return nil
	end
	local rows = {}
	for row in (bmp .. "/"):gmatch("([^/]*)/") do
		rows[#rows + 1] = row
	end
	local rects = {}
	local open = {} -- [x .. ":" .. w] = the rectangle still growing down from the row above
	for y = 0, #rows - 1 do
		local row = rows[y + 1]
		local nextOpen = {}
		local x = 1
		while x <= #row do
			if row:sub(x, x) == "#" then
				local s = x
				while x <= #row and row:sub(x, x) == "#" do
					x = x + 1
				end
				local key = (s - 1) .. ":" .. (x - s)
				local r = open[key]
				if r then
					r[4] = r[4] + 1
				else
					r = { s - 1, y, x - s, 1 }
					rects[#rects + 1] = r
				end
				nextOpen[key] = r
			else
				x = x + 1
			end
		end
		open = nextOpen
	end
	cache[name] = rects
	return rects
end

----------------------------------------------------------------------
-- (LOOK-ui, kitb-look1: the owner's look bar 2026-11-17, "pixel edges snapped to whole pixels at every screen size")
-- whole device px under a UIScale. A window or the HUD sits under a Fit / ViewportScale of 0.8 or 0.85 below 1080p, so a
-- 2 px design cell drew 1.6 screen px (lumpy 1-and-2 px cells in the game, soft in the renders). A part that must stay
-- on the pixel grid asks for its design px through PixelIcon.Px(n, s): the nearest whole number of screen px (at least
-- one), back in design px. PixelIcon.Whole re-runs a part's sizing whenever the rest scale above it changes.
----------------------------------------------------------------------
-- n design px under rest scale s: a whole number of screen px (at least one while n > 0), in design px
function PixelIcon.Px(n, s)
	n = tonumber(n) or 0
	s = tonumber(s) or 1
	if n <= 0 or s <= 0 then
		return n
	end
	return math.max(1, math.floor(n * s + 0.5)) / s
end

-- a UIScale that tweens and rests at 1 (a pop, a pulse, the HUD's unnamed ones) is left out of the rest scale: the
-- grid is the one the part rests on
local TRANSIENT = { Pop = true, Pulse = true, PopScale = true, FxScale = true, UIScale = true }

-- the product of the resting UIScales on `obj` and every GuiObject above it, up to its ScreenGui; `found` (optional) gets
-- each one
local function restScaleOf(obj, found)
	local s = 1
	local cur = obj
	while cur and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") then
			for _, ui in ipairs(cur:GetChildren()) do
				if ui:IsA("UIScale") and not TRANSIENT[ui.Name] then
					if ui.Scale > 0 then
						s = s * ui.Scale
					end
					if found then
						found[#found + 1] = ui
					end
				end
			end
		end
		cur = cur.Parent
	end
	return s
end
PixelIcon.RestScale = restScaleOf

local watched = setmetatable({}, { __mode = "k" }) -- [part] = { Fn = fn(s), S = the scale it was last sized for }
local hookedScales = setmetatable({}, { __mode = "k" }) -- [UIScale] = true once its Scale is watched
local passPending = false

local function applyWhole(part, entry, force)
	local found = {}
	local s = restScaleOf(part, found)
	for _, ui in ipairs(found) do
		if not hookedScales[ui] then
			hookedScales[ui] = true
			ui:GetPropertyChangedSignal("Scale"):Connect(function()
				if not passPending then
					passPending = true
					task.defer(function()
						passPending = false
						for p, e in pairs(watched) do
							if p.Parent then
								applyWhole(p, e, false)
							end
						end
					end)
				end
			end)
		end
	end
	if force or entry.S ~= s then
		entry.S = s
		entry.Fn(s)
	end
end

-- runs fn(s) now (s = the rest scale above `part`) and again whenever that scale changes: `part` moved under another
-- window, or a Fit / ViewportScale above it set to a new value. One watcher per part (a second call replaces fn)
function PixelIcon.Whole(part, fn)
	local entry = watched[part]
	if entry then
		entry.Fn = fn
		applyWhole(part, entry, true)
		return
	end
	entry = { Fn = fn, S = nil }
	watched[part] = entry
	applyWhole(part, entry, true)
	part.AncestryChanged:Connect(function()
		if part.Parent then
			applyWhole(part, entry, false)
		end
	end)
end

-- a stroke `n` design px thick (attribute DesignPx), drawn a whole number of screen px. Call again to change n; a
-- thickness its owner sets later (a selected card's thicker edge) is taken as the new design px and snapped too
local followed = setmetatable({}, { __mode = "k" }) -- [stroke or lip] = the value this module set last
function PixelIcon.WholeStroke(stroke, n)
	stroke:SetAttribute("DesignPx", tonumber(n) or stroke.Thickness)
	local first = followed[stroke] == nil
	followed[stroke] = -1
	PixelIcon.Whole(stroke, function(s)
		local px = PixelIcon.Px(stroke:GetAttribute("DesignPx") or 0, s)
		followed[stroke] = px
		stroke.Thickness = px
	end)
	if first then
		stroke:GetPropertyChangedSignal("Thickness"):Connect(function()
			if math.abs(stroke.Thickness - (followed[stroke] or -1)) > 1e-4 then
				PixelIcon.WholeStroke(stroke, stroke.Thickness)
			end
		end)
	end
	return stroke
end

-- a bar along an edge (a lip) `n` design px tall (attribute DesignPx; its width and position are the caller's), drawn a
-- whole number of screen px tall. Call again to change n; a height its owner sets later (a press thins the lip) is taken
-- as the new design px
function PixelIcon.WholeHeight(obj, n)
	obj:SetAttribute("DesignPx", tonumber(n) or obj.Size.Y.Offset)
	local first = followed[obj] == nil
	followed[obj] = -1
	PixelIcon.Whole(obj, function(s)
		local size = obj.Size
		local px = PixelIcon.Px(obj:GetAttribute("DesignPx") or 0, s)
		followed[obj] = px
		obj.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale, px)
	end)
	if first then
		obj:GetPropertyChangedSignal("Size"):Connect(function()
			local y = obj.Size.Y
			if y.Scale == 0 and math.abs(y.Offset - (followed[obj] or -1)) > 1e-4 then
				PixelIcon.WholeHeight(obj, y.Offset)
			end
		end)
	end
	return obj
end

-- (LOOK-ui) every kit edge (a Border UIStroke) and every kit lip (a Frame "Lip" of a fixed height) under `root`, now and
-- whenever one is added later, drawn on whole screen px (WholeStroke / WholeHeight). For a window's or the HUD's whole
-- gui, so a card built later (a list row, a pet card) stays on the grid without each builder asking. Once per root.
-- (LOOK-ui: border leaks) and no GuiObject there keeps Roblox's default 1 px dark border (BorderSizePixel 1 on a new
-- Frame / TextLabel: it showed round the Pets busy marks, the Shop's header icon, the BEST VALUE tag): kit B draws its
-- edges with strokes only
local treed = setmetatable({}, { __mode = "k" })
local function adopt(d)
	if d:IsA("GuiObject") and d.BorderSizePixel ~= 0 then
		d.BorderSizePixel = 0
	end
	if followed[d] ~= nil then
		return
	end
	if d:IsA("UIStroke") then
		if d.ApplyStrokeMode == Enum.ApplyStrokeMode.Border and d.Thickness > 0 then
			PixelIcon.WholeStroke(d, d.Thickness)
		end
	elseif d:IsA("Frame") and d.Name == "Lip" then
		local y = d.Size.Y
		if y.Scale == 0 and y.Offset > 0 then
			PixelIcon.WholeHeight(d, y.Offset)
		end
	end
end
function PixelIcon.WholeTree(root)
	if not root or treed[root] then
		return
	end
	treed[root] = true
	for _, d in ipairs(root:GetDescendants()) do
		adopt(d)
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("GuiObject") and d.BorderSizePixel ~= 0 then
			d.BorderSizePixel = 0
		end
		if d:IsA("UIStroke") or (d:IsA("Frame") and d.Name == "Lip") then
			-- its builder names and sizes it right after parenting it: look once that is done
			task.defer(function()
				if d.Parent then
					adopt(d)
				end
			end)
		end
	end)
end

-- a face inset `e` design px from every side of its parent (`extra` px more off its height: the lip it leaves showing
-- under it), both whole screen px (attributes InsetPx, InsetExtra). Call again to change them (a plank's press)
function PixelIcon.WholeInset(face, e, extra)
	face:SetAttribute("InsetPx", tonumber(e) or 0)
	face:SetAttribute("InsetExtra", tonumber(extra) or 0)
	PixelIcon.Whole(face, function(s)
		local px = PixelIcon.Px(face:GetAttribute("InsetPx") or 0, s)
		local more = PixelIcon.Px(face:GetAttribute("InsetExtra") or 0, s)
		face.Position = UDim2.fromOffset(px, px)
		face.Size = UDim2.new(1, -2 * px, 1, -(2 * px + more))
	end)
	return face
end

-- (U9-7 look) the cells on whole SCREEN pixels under a window's or a HUD's UIScale. A dock at 0.8 drew a 27 px icon's 3 px
-- cells 2.4 px wide (Roblox rounds each Frame's edges to the pixel, so the columns came out 2 and 3 px: uneven) and an
-- 18 px icon's 1.6 px wide. A cell is now round(cell x scale) screen px (a half rounds down, never under 2 for a 2+ px
-- cell; at 0.7 - 0.8 both sizes draw 2 px cells: one pixel size on a phone), centred in the icon's box, which keeps its
-- design size (the layout is unchanged; PixelIcon.Lead keeps its gap to the text past what draws outside the box).
-- The short tweens on top (a press, a pop, a pulse) are not counted. Fitted when the icon is parented under a ScreenGui
-- (here, or when it or an ancestor moves there) and again when one of the UIScales above it changes. At scale 1 the
-- cells are exactly the old ones. Attribute CellPx = the screen px of a cell
local TWEEN_SCALES = { Pop = true, PopScale = true, FxScale = true, Punch = true, Pulse = true, Swell = true, Bounce = true }
local scaleSets = setmetatable({}, { __mode = "k" }) -- [UIScale] = { [icon] = true } (weak both ways)
local scaleConns = setmetatable({}, { __mode = "k" })

-- the product of the layout UIScales on `obj` and above it, the list of them, and whether it reached a ScreenGui
local function layoutScale(obj)
	local s, scales = 1, {}
	local cur = obj
	while cur do
		if cur:IsA("LayerCollector") then
			return s, scales, true
		end
		if cur:IsA("GuiObject") then
			local ui = cur:FindFirstChildOfClass("UIScale")
			if ui and ui.Scale > 0 and not TWEEN_SCALES[ui.Name] then
				s = s * ui.Scale
				scales[#scales + 1] = ui
			end
		end
		cur = cur.Parent
	end
	return s, scales, false
end

-- the screen px of a cell of `cell` design px under scale s: the nearest whole px (a half rounds down), and never under
-- 2 for a cell of 2 or more, so an 18 px icon stays legible and every icon of a phone screen (0.7 - 0.8) draws 2 px cells
local function screenCellOf(cell, s)
	return math.max(1, math.min(cell, 2), math.ceil(cell * s - 0.5))
end

-- design px an icon of px draws past each side of its box under scale s (0 when it draws inside it)
local function overflowOf(px, s)
	local sc = screenCellOf(math.floor(px / 9), s)
	return math.max(0, (9 * sc / s - px) / 2)
end

local fitCells
local function watchScale(scale)
	if scaleConns[scale] then
		return scaleSets[scale]
	end
	local set = setmetatable({}, { __mode = "k" })
	scaleSets[scale] = set
	scaleConns[scale] = scale:GetPropertyChangedSignal("Scale"):Connect(function()
		for icon in pairs(set) do
			if icon.Parent then
				fitCells(icon)
			end
		end
	end)
	return set
end

fitCells = function(icon)
	local rects = PixelIcon.Runs(icon:GetAttribute("PixelIcon"))
	if not rects then
		return
	end
	local s, scales, rooted = layoutScale(icon.Parent)
	if not rooted then
		return
	end
	local px = icon.Size.X.Offset
	local cell = math.floor(px / 9)
	local screenCell = screenCellOf(cell, s)
	local dc = screenCell / s
	local pad = math.floor((px * s - 9 * screenCell) / 2) / s
	for i, r in ipairs(rects) do
		local f = icon:FindFirstChild("R" .. i)
		if f then
			f.Position = UDim2.fromOffset(pad + r[1] * dc, pad + r[2] * dc)
			f.Size = UDim2.fromOffset(r[3] * dc, r[4] * dc)
		end
	end
	icon:SetAttribute("CellPx", screenCell)
	for _, scale in ipairs(scales) do
		watchScale(scale)[icon] = true
	end
end

-- (U9-7 look) fits an icon made by PixelIcon.New to the UIScales above it now (New and a move do it by themselves)
function PixelIcon.Fit(icon)
	if icon and icon:GetAttribute("PixelIcon") then
		fitCells(icon)
	end
end

-- draws icon `name` at px x px in `colour` into `parent`; nil for an unknown name
function PixelIcon.New(parent, name, px, colour)
	local rects = PixelIcon.Runs(name)
	if not rects then
		return nil
	end
	px = math.max(9, math.floor(tonumber(px) or 18)) -- under 9 px a cell would be under a pixel: one px a cell
	if px % 9 ~= 0 and not PixelIcon.Warned[px] then
		PixelIcon.Warned[px] = 1
		warn("[PixelIcon] " .. px .. " px is not a multiple of 9: the cells draw at " .. (9 * math.floor(px / 9)) .. " px in a padded box")
	end
	local cell = math.floor(px / 9)
	local pad = math.floor((px - 9 * cell) / 2)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Size = UDim2.fromOffset(px, px)
	icon:SetAttribute("PixelIcon", name)
	for i, r in ipairs(rects) do
		local f = Instance.new("Frame")
		f.Name = "R" .. i
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 0
		f.BackgroundColor3 = colour or Color3.new(1, 1, 1)
		f.Position = UDim2.fromOffset(pad + r[1] * cell, pad + r[2] * cell)
		f.Size = UDim2.fromOffset(r[3] * cell, r[4] * cell)
		f.Parent = icon
	end
	icon.Parent = parent
	-- (U9-7 look) whole screen pixels under the UIScales above it, now and whenever it lands under a ScreenGui
	fitCells(icon)
	icon.AncestryChanged:Connect(function()
		fitCells(icon)
	end)
	return icon
end

-- recolours an icon made by PixelIcon.New
function PixelIcon.Tint(icon, colour)
	for _, f in ipairs(icon and icon:GetChildren() or {}) do
		if f:IsA("Frame") then
			f.BackgroundColor3 = colour
		end
	end
end

-- (U7a) the multiple of 9 nearest to px (at least 9): the size an icon standing in for a glyph of px draws at
function PixelIcon.Snap(px)
	return math.max(9, math.floor((tonumber(px) or 18) / 9 + 0.5) * 9)
end

-- (U7a) icon `name` of about px px centred in `host` (a text object): it takes the host's TextColor3 (unless `colour` is
-- given), TextTransparency and ZIndex and follows later changes to them, so a caller that tints, fades or layers the text
-- moves the icon with it. px nil: the icon is 0.9 x the host's TextSize and is redrawn when that changes (a glyph label
-- a layout resizes). Returns the icon Frame (attribute PixelIcon = name; a redraw replaces it); nil for an unknown name.
-- Hosting again on the same host drops the old icon and its connections first (a mark that changes, a coin resized).
local hosted = setmetatable({}, { __mode = "k" }) -- [host] = { icon = Frame, conns = { connections } }

function PixelIcon.Host(host, name, px, colour)
	local old = hosted[host]
	if old then
		hosted[host] = nil
		for _, c in ipairs(old.conns) do
			c:Disconnect()
		end
		if old.icon then
			old.icon:Destroy()
		end
	end
	if not PixelIcon.Bitmaps[name] then
		return nil
	end
	local entry = { icon = nil, conns = {} }
	hosted[host] = entry
	local icon = nil
	local function sync()
		if not icon then
			return
		end
		icon.ZIndex = host.ZIndex
		for _, f in ipairs(icon:GetChildren()) do
			if f:IsA("Frame") then
				f.BackgroundColor3 = colour or host.TextColor3
				f.BackgroundTransparency = host.TextTransparency
				f.ZIndex = host.ZIndex
			end
		end
	end
	local function draw()
		if icon then
			icon:Destroy()
		end
		icon = PixelIcon.New(host, name, PixelIcon.Snap(px or (tonumber(host.TextSize) or 18) * 0.9), colour or host.TextColor3)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		entry.icon = icon
		sync()
	end
	draw()
	local conns = entry.conns
	conns[#conns + 1] = host:GetPropertyChangedSignal("TextColor3"):Connect(sync)
	conns[#conns + 1] = host:GetPropertyChangedSignal("TextTransparency"):Connect(sync)
	conns[#conns + 1] = host:GetPropertyChangedSignal("ZIndex"):Connect(sync)
	if px == nil then
		conns[#conns + 1] = host:GetPropertyChangedSignal("TextSize"):Connect(function()
			if icon and icon.Size.X.Offset ~= PixelIcon.Snap((tonumber(host.TextSize) or 18) * 0.9) then
				draw()
			end
		end)
	end
	return icon
end

local leadConns = setmetatable({}, { __mode = "k" }) -- [label] = { [childName] = { connections } } (a re-call drops the old)

-- (U7a review) the product of the UIScales on `obj` and every GuiObject above it, up to its ScreenGui: Roblox's
-- TextBounds is screen px (after all of them), a Position offset is the object's own px. A HUD panel's ScreenFactor
-- (0.8 on a phone, up to 1.25) and a token pop (about 1.7) are among them
local function scaleOf(obj)
	local s = 1
	local cur = obj
	while cur and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") then
			local ui = cur:FindFirstChildOfClass("UIScale")
			if ui and ui.Scale > 0 then
				s = s * ui.Scale
			end
		end
		cur = cur.Parent
	end
	return s
end

-- (U7b review) the width of a label's text in its own px, for when TextBounds has none: Theme.MeasureLabel (TextService
-- with the label's font; a Nunito face, whose .Font reads Unknown, on its role's Enum font with the role's spare
-- widening, so it runs wide, never short). A Roblox server lays out no text (TextBounds reads 0 there), and the world
-- signs Lead on the server, where the icon's place is set once (no client places it again). Theme is required here, on
-- first use, not at load: PixelIcon loads without it (the loading screen draws icons before Theme arrives)
local function measuredWidth(label)
	local text = tostring(label.Text or "")
	if text == "" then
		return 0
	end
	local ok, v = pcall(function()
		local Theme = require(script.Parent.Theme)
		return Theme.MeasureLabel(label)
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return math.ceil(v.X)
	end
	return math.ceil(#text * (tonumber(label.TextSize) or 14) * 0.6)
end

function PixelIcon.Lead(label, name, opts)
	opts = opts or {}
	if not PixelIcon.Bitmaps[name] then
		return nil
	end
	local after = opts.After == true
	local childName = opts.Name or (after and "TrailIcon" or "LeadIcon")
	local old = label:FindFirstChild(childName)
	if old then
		old:Destroy()
	end
	leadConns[label] = leadConns[label] or {}
	for _, c in ipairs(leadConns[label][childName] or {}) do
		c:Disconnect()
	end
	local px = PixelIcon.Snap(opts.Px or (tonumber(label.TextSize) or 18) * 0.9)
	local cell = math.floor(px / 9)
	local count = math.max(0, math.floor(tonumber(opts.Count) or 1))
	local of = math.max(count, math.floor(tonumber(opts.Of) or count), 1)
	local w = of * px + (of - 1) * cell
	local gap = tonumber(opts.Gap) or math.max(3, math.floor(px / 4)) -- (U7b) opts.Gap: px between the text and the icons
	local pad = label:FindFirstChildOfClass("UIPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Parent = label
	end
	-- the label's own insets, read once (a second call measures from them, not from the first icon's)
	local baseL, baseR = label:GetAttribute("LeadInsetL"), label:GetAttribute("LeadInsetR")
	if baseL == nil then
		baseL, baseR = pad.PaddingLeft.Offset, pad.PaddingRight.Offset
		label:SetAttribute("LeadInsetL", baseL)
		label:SetAttribute("LeadInsetR", baseR)
	end
	local box = Instance.new("Frame")
	box.Name = childName
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(w, px)
	box:SetAttribute("PixelIcon", name)
	box:SetAttribute("IconCount", count)
	local icons = {}
	for i = 1, of do
		local icon = PixelIcon.New(box, name, px, opts.Colour or label.TextColor3)
		icon.Position = UDim2.fromOffset((i - 1) * (px + cell), 0)
		icons[i] = icon
	end
	local function sync()
		box.ZIndex = label.ZIndex
		for i, icon in ipairs(icons) do
			icon.ZIndex = label.ZIndex
			-- an unlit icon of a rating is the same colour at a third of its strength
			local t = label.TextTransparency
			if i > count then
				t = 1 - (1 - t) * 0.35
			end
			for _, f in ipairs(icon:GetChildren()) do
				if f:IsA("Frame") then
					f.BackgroundColor3 = opts.Colour or label.TextColor3
					f.BackgroundTransparency = t
					f.ZIndex = label.ZIndex
				end
			end
		end
	end
	local align = label.TextXAlignment
	-- (U9-7 look) the icon a whole design px from the label's padded box: its height from a fixed Size or, laid out, from
	-- AbsoluteSize (the label's own px), so the top is floor((h - px) / 2) and a centred text's icon floor(w / 2 ...) (half
	-- of an odd height or width put an icon on a half pixel); before the first layout the 0.5 scales
	local function padded()
		local s = scaleOf(label)
		local a = label.AbsoluteSize
		local pw, ph = nil, nil
		if a.X > 0 and a.Y > 0 and s > 0 then
			pw = math.floor(a.X / s + 0.5) - pad.PaddingLeft.Offset - pad.PaddingRight.Offset
			ph = math.floor(a.Y / s + 0.5) - pad.PaddingTop.Offset - pad.PaddingBottom.Offset
		end
		local sy = label.Size.Y
		local auto = label.AutomaticSize == Enum.AutomaticSize.Y or label.AutomaticSize == Enum.AutomaticSize.XY
		if sy.Scale == 0 and sy.Offset > 0 and not auto then
			ph = sy.Offset - pad.PaddingTop.Offset - pad.PaddingBottom.Offset
		end
		return pw, ph
	end
	local function vertical(ph)
		if ph then
			return 0, UDim.new(0, math.floor((ph - px) / 2))
		end
		return 0.5, UDim.new(0.5, 0)
	end
	-- a UIPadding insets the label's children as it insets the text, so the icon is placed in the same padded box as the
	-- letters: scale 0 / 0.5 / 1 are the text area's left edge, centre and right edge. TextBounds is screen px: back to
	-- the label's own px (a UIScale tween changes TextBounds, so a pop re-places it at the new scale). (U7b review) No
	-- bounds for a text that has letters (the server; a client before its first layout, which re-places on TextBounds):
	-- measured (measuredWidth)
	local function place()
		-- (U9-7 look) under a UIScale an icon's whole-px cells can draw past its box (18 px at 0.8: 2 px cells, 18 px on
		-- the screen in a 14.4 px box): the text's inset grows by what draws outside one side and the box steps out by the
		-- same, so the gap to the text still shows (the drawn icon's outer side takes that much of the label's own inset)
		local extra = math.ceil(overflowOf(px, (layoutScale(label))) - 0.01)
		local g = gap + extra
		-- (a rating's icons step apart by the same, so their drawn cells never touch)
		local step = px + cell + 2 * extra
		local w = (of - 1) * step + px
		box.Size = UDim2.fromOffset(w, px)
		for i, icon in ipairs(icons) do
			icon.Position = UDim2.fromOffset((i - 1) * step, 0)
		end
		if not after and align ~= Enum.TextXAlignment.Right then
			pad.PaddingLeft = UDim.new(pad.PaddingLeft.Scale, baseL + w + gap + extra)
		elseif after and (align ~= Enum.TextXAlignment.Left or opts.Room == true) then
			pad.PaddingRight = UDim.new(pad.PaddingRight.Scale, baseR + w + gap + extra)
		end
		local textW = label.TextBounds.X / scaleOf(label)
		if textW <= 0 and label.Text ~= "" then
			textW = measuredWidth(label)
		end
		if opts.Room == true and after and align == Enum.TextXAlignment.Left then
			-- (render gate) a truncated text's bounds can run past its text area: the icons start at that area's end at most
			local okA, boxW = pcall(function()
				return label.AbsoluteSize.X / scaleOf(label)
			end)
			if okA and type(boxW) == "number" and boxW > 0 then
				textW = math.min(textW, boxW - pad.PaddingLeft.Offset - pad.PaddingRight.Offset)
			end
		end
		textW = math.ceil(textW - 0.01) -- (U9-7 look) the icon a whole px from the text's measured end
		local pw, ph = padded()
		local ay, y = vertical(ph)
		box.AnchorPoint = Vector2.new(after and 0 or 1, ay)
		if align == Enum.TextXAlignment.Right then
			box.Position = after and UDim2.new(1, g, y.Scale, y.Offset) or UDim2.new(1, -(textW + g), y.Scale, y.Offset)
		elseif align == Enum.TextXAlignment.Center and label.Text == "" and not after then
			-- (U7b) icons alone on an empty centred label (a rating badge): centred in the label (the left inset moved the
			-- text area's centre right by half of w + gap)
			box.AnchorPoint = Vector2.new(0.5, ay)
			box.Position = UDim2.new(0.5, -math.floor((w + gap) / 2), y.Scale, y.Offset)
			if pw then
				box.AnchorPoint = Vector2.new(0, ay)
				box.Position = UDim2.new(0, math.floor(pw / 2 - (w + gap) / 2 - w / 2), y.Scale, y.Offset)
			end
		elseif align == Enum.TextXAlignment.Center then
			box.Position = UDim2.new(0.5, math.floor(after and (textW / 2 + g) or -(textW / 2 + g)), y.Scale, y.Offset)
			if pw then
				box.Position = UDim2.new(0, math.floor(pw / 2 + (after and (textW / 2 + g) or -(textW / 2 + g))), y.Scale, y.Offset)
			end
		else
			box.Position = after and UDim2.new(0, textW + g, y.Scale, y.Offset) or UDim2.new(0, -g, y.Scale, y.Offset)
		end
	end
	if not after and align ~= Enum.TextXAlignment.Right then
		pad.PaddingLeft = UDim.new(pad.PaddingLeft.Scale, baseL + w + gap)
	elseif after and (align ~= Enum.TextXAlignment.Left or opts.Room == true) then
		pad.PaddingRight = UDim.new(pad.PaddingRight.Scale, baseR + w + gap)
	end
	sync()
	place()
	box.Parent = label
	leadConns[label][childName] = {
		label:GetPropertyChangedSignal("TextColor3"):Connect(sync),
		label:GetPropertyChangedSignal("TextTransparency"):Connect(sync),
		label:GetPropertyChangedSignal("ZIndex"):Connect(sync),
		label:GetPropertyChangedSignal("TextBounds"):Connect(place),
		label:GetPropertyChangedSignal("Text"):Connect(place),
		label:GetPropertyChangedSignal("Size"):Connect(place), -- (U9-7 look) a new height moves the icon's whole-px top
	}
	-- (U9-7 look) a laid-out size places the icon on whole px (padded()): every lead follows its label's AbsoluteSize
	table.insert(leadConns[label][childName], label:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	return box
end

-- (U7b) a status line's mark set on every refresh: PixelIcon.Lead only when the mark (name, Count, Of) changed since the
-- last call (the label's attribute Mark_<child>), PixelIcon.Clear when name is nil. Cheap to call each frame
function PixelIcon.Mark(label, name, opts)
	opts = opts or {}
	local attr = "Mark_" .. (opts.Name or (opts.After == true and "TrailIcon" or "LeadIcon"))
	local key = name and (name .. ":" .. tostring(opts.Count or "") .. ":" .. tostring(opts.Of or "")) or ""
	if label:GetAttribute(attr) == key then
		return
	end
	label:SetAttribute(attr, key)
	if name then
		PixelIcon.Lead(label, name, opts)
	else
		PixelIcon.Clear(label, opts)
	end
end

-- (U7b) PixelIcon.Host only when the icon changed since the last call (the host's attribute HostMark); nil or an
-- unknown name drops the icon. For a glyph label a refresh rewrites (a ready tick, a lock badge that comes and goes)
function PixelIcon.Set(host, name, px, colour)
	local key = (name and PixelIcon.Bitmaps[name]) and (name .. ":" .. tostring(px or "")) or ""
	if host:GetAttribute("HostMark") == key then
		return
	end
	host:SetAttribute("HostMark", key)
	host.Text = ""
	PixelIcon.Host(host, key ~= "" and name or "", px, colour)
end

-- (U7b) takes the icon PixelIcon.Lead put on `label` off again (opts.After / opts.Name as given to Lead) and puts the
-- label's own insets back: a row whose mark comes and goes (a pet that stops training, a rating that drops to none)
function PixelIcon.Clear(label, opts)
	opts = opts or {}
	local after = opts.After == true
	local childName = opts.Name or (after and "TrailIcon" or "LeadIcon")
	local old = label:FindFirstChild(childName)
	if old then
		old:Destroy()
	end
	if leadConns[label] then
		for _, c in ipairs(leadConns[label][childName] or {}) do
			c:Disconnect()
		end
		leadConns[label][childName] = nil
	end
	local pad = label:FindFirstChildOfClass("UIPadding")
	local baseL, baseR = label:GetAttribute("LeadInsetL"), label:GetAttribute("LeadInsetR")
	if pad and baseL ~= nil then
		if after then
			pad.PaddingRight = UDim.new(pad.PaddingRight.Scale, baseR)
		else
			pad.PaddingLeft = UDim.new(pad.PaddingLeft.Scale, baseL)
		end
	end
end

return PixelIcon
