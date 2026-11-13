-- PixelIcon: the kit B icon set (U2 of .superpowers/slop-audit/round3/BUILD_PLAN.md, findings 5 and 7; decisions 2 and 3).
-- Every icon is a 9 x 9 one-colour bitmap kept as data: nine rows of nine cells, "#" drawn and "." empty, rows joined by
-- "/". The first 27 are the pitch's own (kit_pitch_mockups.html:523-550, the `I` table), ported as they are so the icons in
-- the game are the ones the owner saw; the rest are the ones the loading screen, menu, settings and credits need.
--   PixelIcon.Bitmaps[name]            the bitmap string
--   PixelIcon.Runs(name)               its merged rectangles { { x, y, w, h }, ... } in cells (nil for an unknown name)
--   PixelIcon.New(parent, name, px, colour)  a transparent px x px Frame (attribute PixelIcon = name) holding one Frame per
--                                      merged rectangle, snapped to whole pixels (cell = floor(px / 9), centred); nil for
--                                      an unknown name. px under 9 draws at 9; a px between multiples of 9 warns once
--                                      (PixelIcon.Warned)
-- Runs: each row's horizontal runs, then runs with the same columns in the rows below merged into one taller rectangle,
-- so an icon is a handful of Frames (smoke: at most 25). A generated sheet (one upload) can replace the Frames later in
-- dense grids; it would be drawn from this same data.
-- Requires nothing (Shared, usable from ReplicatedFirst). Plain Lua 5.1-compatible syntax only.

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

return PixelIcon
