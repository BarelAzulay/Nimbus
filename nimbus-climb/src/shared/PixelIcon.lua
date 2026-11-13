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
--   PixelIcon.Snap(px)                 the multiple of 9 nearest px (at least 9): the size an icon for a px glyph draws at
--   PixelIcon.Host(host, name, px[, colour])  (U7a) the icon centred in a text object, following its TextColor3 (unless
--                                      colour), TextTransparency and ZIndex (and with px nil its TextSize): an icon a
--                                      caller treats as a glyph
--   PixelIcon.Lead(label, name[, opts]) (U7a) the icon in front of a label's text ("<coin> 1,250"), the text inset past it;
--                                      opts.After / Count / Of: a rating after the text ("Easy" + 3 lit stars of 5); opts.Gap
--   PixelIcon.Clear(label[, opts])     (U7b) takes a Lead icon off again (a row whose mark comes and goes), insets back
--   PixelIcon.Mark(label, name|nil[, opts])  (U7b) Lead / Clear only when the mark changed: a status line set each refresh
--   PixelIcon.Set(host, name|nil[, px])      (U7b) Host only when the icon changed (the text emptied): a glyph label
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
	-- a UIPadding insets the label's children as it insets the text, so the icon is placed in the same padded box as the
	-- letters: scale 0 / 0.5 / 1 are the text area's left edge, centre and right edge. TextBounds is screen px: back to
	-- the label's own px (a UIScale tween changes TextBounds, so a pop re-places it at the new scale)
	local function place()
		local textW = label.TextBounds.X / scaleOf(label)
		box.AnchorPoint = Vector2.new(after and 0 or 1, 0.5)
		if align == Enum.TextXAlignment.Right then
			box.Position = after and UDim2.new(1, gap, 0.5, 0) or UDim2.new(1, -(textW + gap), 0.5, 0)
		elseif align == Enum.TextXAlignment.Center and label.Text == "" and not after then
			-- (U7b) icons alone on an empty centred label (a rating badge): centred in the label (the left inset moved the
			-- text area's centre right by half of w + gap)
			box.AnchorPoint = Vector2.new(0.5, 0.5)
			box.Position = UDim2.new(0.5, -math.floor((w + gap) / 2), 0.5, 0)
		elseif align == Enum.TextXAlignment.Center then
			box.Position = UDim2.new(0.5, math.floor(after and (textW / 2 + gap) or -(textW / 2 + gap)), 0.5, 0)
		else
			box.Position = after and UDim2.new(0, textW + gap, 0.5, 0) or UDim2.new(0, -gap, 0.5, 0)
		end
	end
	if not after and align ~= Enum.TextXAlignment.Right then
		pad.PaddingLeft = UDim.new(pad.PaddingLeft.Scale, baseL + w + gap)
	elseif after and align ~= Enum.TextXAlignment.Left then
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
	}
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
