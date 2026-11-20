-- ElementsWindow (client UI; Pitch 2 item 12_elements, the owner's pick A "Wheel"; spec
-- docs/superpowers/specs/2026-11-20-pitch2-build-design.md): the element chart as its own centred kit B window over the
-- Pet Index. Before it, Elements was a scrolling section inside the Index (3 of the 8 elements in view, 18 px arrows, no
-- title bar and no X: the owner's shot 12).
--
--   ElementsWindow.New(gui, opts) -> win      gui: the Index's ScreenGui; opts.OnClose() runs after the window hid;
--                                             opts.OnPlace(left) gets its left edge (gui px) while open, nil on close
--   win.Open() / win.Close() / win.IsOpen() / win.Relayout()   win.Holder (Frame "Window_Elements"), win.Mode
--
-- The window: CloudUI.Panel Skin "Signboard" ("ElementsPanel": navy header, the gold ribbon title ELEMENTS, the red X,
-- the awning on the frame on its two brackets), centred on the screen. Inside, "Chart": the Ring (the 6-loop of
-- Config.Elements.Strong from Order[1]: Water > Flame > Frost > Nature > Earth > Storm, each a kit B block in its
-- element's colour with its pixel glyph and name, "Block_<element>"; each link one pixel arrow at exactly 45 or 90
-- degrees, PixelIcon arrow* on even stairs, never a turned frame; the hub "x1.5 / to where it points") and the Side:
-- "How it works", worked examples (Water -> Flame x1.5 strong, Flame -> Water x0.75 weak; PC also Water vs Earth x1, no
-- arrow) and the rivals (the elements outside the loop, each strong against the other: Celestial <-> Shadow, x1.5 both
-- ways as PetCatalog's singleMultiplier).
-- Three layouts in design px, nothing scrolls in any:
--   PC        1060 x 760 at the screen factor (fitted to the screen): the tall hexagon left, the side column right
--   Short     a landscape phone, 800 x 320 at scale 1 (fitted): a wide hexagon left, a compact column right, no awning
--   Portrait  a phone held upright, 360 x 640 at scale 1 (fitted): the tall hexagon over the examples and the rivals; the
--             window starts low enough for its awning to clear the HUD's currency strips
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon"))
local SignKit = require(Shared:WaitForChild("SignKit"))

local CloudUI = require(script.Parent:WaitForChild("CloudUI"))

local SIGN = Theme.Sign
local INK = SIGN.Text

local ElementsWindow = {}

-- the layouts (design px). Ring: Block w x h, Glyph px, Name text, the arrows' px (Diag at 45 degrees, Straight at 90),
-- Cols (the left x of each block column) and Rows (each block row's top), Slots (the loop's 6 places as { col, row }
-- clockwise from the first element) and Links (the arrow from slot i to slot i + 1); Hub { x, y, w, h, big, small }.
-- Side: X (from the chart's left) and its own parts
local L = {
	PC = {
		-- (look review r0: at 720 the ring filled the body and Nature sat 2-3 px over its foot) 760, so the centred ring keeps
		-- about 20 px of stone over and under it, as the mock's
		W = 1060, H = 760, Roof = true,
		Ring = {
			W = 600, H = 632, Block = { 124, 104 }, Glyph = 36, Name = 22, Diag = 54, Straight = 54,
			Cols = { 68, 238, 408 }, Rows = { 8, 186, 360, 528 },
			Slots = { { 2, 1 }, { 3, 2 }, { 3, 3 }, { 2, 4 }, { 1, 3 }, { 1, 2 } },
			Links = { "arrowse", "arrowdown", "arrowsw", "arrownw", "arrowup", "arrowne" },
			Hub = { 200, 270, 200, 110, 48, 20 }, HubSub = "to where it points",
		},
		Side = {
			X = 636, W = 392, Head = 30, Body = 20, BodyLine = "Each arrow points at the one it beats.", Cards = true,
			Square = 64, SquareGlyph = 36, Arrow = 36, Tag = { 90, 44, 28 }, Caption = 18, RowH = 100, RowGap = 6,
			Examples = { "strong", "weak", "none" }, RivalBlock = { 130, 96, 36, 22 }, RivalArrow = 45, RivalCaption = 18,
			RivalText = "each hits the other x1.5",
		},
	},
	Short = {
		W = 800, H = 320, Roof = false,
		Ring = {
			W = 480, H = 236, Block = { 80, 56 }, Glyph = 18, Name = 15, Diag = 27, Straight = 36,
			Cols = { 0, 120, 280, 400 }, Rows = { 0, 90, 180 },
			Slots = { { 2, 1 }, { 3, 1 }, { 4, 2 }, { 3, 3 }, { 2, 3 }, { 1, 2 } },
			Links = { "arrow", "arrowse", "arrowsw", "left", "arrownw", "arrowne" },
			Hub = { 128, 90, 224, 56, 26, 15 }, HubSub = "to where it points",
		},
		Side = {
			X = 500, W = 276, Head = 20, Cards = false,
			Square = 36, SquareGlyph = 18, Arrow = 27, Tag = { 64, 32, 18 }, Caption = 15, RowH = 40, RowGap = 6,
			-- (look review r0: "rivals: / x1.5 / both" wrapped to 3 lines in 60 px) 78 px blocks leave the caption 72, two lines
			Examples = { "strong", "weak" }, RivalBlock = { 78, 50, 18, 15 }, RivalArrow = 18, RivalCaption = 15,
			RivalText = "rivals: x1.5 both",
		},
	},
	Portrait = {
		W = 360, H = 640, Roof = true,
		Ring = {
			W = 336, H = 312, Block = { 64, 54 }, Glyph = 18, Name = 15, Diag = 27, Straight = 27,
			Cols = { 20, 136, 252 }, Rows = { 0, 86, 172, 258 },
			Slots = { { 2, 1 }, { 3, 2 }, { 3, 3 }, { 2, 4 }, { 1, 3 }, { 1, 2 } },
			Links = { "arrowse", "arrowdown", "arrowsw", "arrownw", "arrowup", "arrowne" },
			Hub = { 106, 120, 124, 72, 26, 14 }, HubSub = "where it points",
		},
		Side = {
			X = 0, W = 336, Head = 0, Cards = false, Below = 18,
			Square = 40, SquareGlyph = 18, Arrow = 27, Tag = { 70, 32, 18 }, Caption = 15, RowH = 44, RowGap = 8,
			Examples = { "strong", "weak" }, RivalBlock = { 84, 54, 18, 15 }, RivalArrow = 18, RivalCaption = 15,
			RivalText = "rivals: x1.5 both",
		},
	},
}
ElementsWindow.Layouts = L
ElementsWindow.ROOF_CLEAR = 26 -- (the Gifts window's rule) design px of clear sky the awning needs over a phone window
ElementsWindow.MARGIN = 12

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function frame(parent, name, props)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function text(parent, name, str, role, size, color, props)
	local label = Theme.Label(str, role, { Size = size, Color = color })
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextWrapped = false
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = parent
	return label
end

local function info(element)
	return Config.Elements and Config.Elements.Info and Config.Elements.Info[element] or nil
end

-- the loop of Strong from Order[1] (6 elements) and the rest (the rivals), as the Index's old card read them
function ElementsWindow.Cycle()
	local elements = Config.Elements
	if type(elements) ~= "table" or type(elements.Order) ~= "table" or type(elements.Strong) ~= "table" then
		return {}, {}
	end
	local cycle, inCycle = {}, {}
	local current = elements.Order[1]
	while current and not inCycle[current] and #cycle < #elements.Order do
		inCycle[current] = true
		cycle[#cycle + 1] = current
		local nextList = elements.Strong[current]
		current = type(nextList) == "table" and nextList[1] or nil
	end
	if current ~= cycle[1] then
		cycle, inCycle = {}, {}
	end
	local rest = {}
	for _, e in ipairs(elements.Order) do
		if not inCycle[e] then
			rest[#rest + 1] = e
		end
	end
	return cycle, rest
end

-- a pixel icon centred on (cx, cy) of `parent`, its box on a whole design px
local function iconAt(parent, name, px, colour, cx, cy, z)
	local icon = PixelIcon.New(parent, name, px, colour)
	if icon then
		icon.Position = UDim2.fromOffset(math.floor(cx - px / 2 + 0.5), math.floor(cy - px / 2 + 0.5))
		icon.ZIndex = z
		for _, c in ipairs(icon:GetChildren()) do
			if c:IsA("GuiObject") then
				c.ZIndex = z
			end
		end
	end
	return icon
end

-- an element's block: its colour on the face, its darker lip, the wood edge; the glyph over its name in the ink that
-- reads on the colour. `name` false: a glyph-only square (the examples)
local function elementBlock(parent, element, x, y, w, h, glyph, nameSize, z, blockName)
	local data = info(element)
	if not data then
		return nil
	end
	local block = frame(parent, blockName or ("Block_" .. element), {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z,
	})
	block:SetAttribute("Element", element)
	local lipPx = h >= 50 and 5 or 3
	CloudUI.SignBlock(block, "Stone", { Face = data.Color, LipColor = Theme.Darken(data.Color, 0.28), EdgePx = h >= 50 and 3 or 2, LipPx = lipPx, Pad = false })
	local ink = Theme.TextOn(data.Color)
	local inner = h - lipPx
	if nameSize then
		local nameH = nameSize + 4
		local gap = math.max(2, math.floor((inner - glyph - nameH) / 3))
		iconAt(block, data.Icon or "sparkle", glyph, ink, w / 2, gap + glyph / 2, z + 1)
		text(block, "Name", element, "Heading", nameSize, ink, {
			Position = UDim2.fromOffset(2, gap * 2 + glyph),
			Size = UDim2.fromOffset(w - 4, nameH),
			ZIndex = z + 1,
		})
	else
		iconAt(block, data.Icon or "sparkle", glyph, ink, w / 2, inner / 2, z + 1)
	end
	return block
end

-- a multiplier tag: x1.5 on grass, x0.75 on the red, x1 on stone
local TAGS = {
	strong = { Text = "x1.5", Face = SIGN.Grass, Lip = SIGN.GrassLip, Caption = { "strong hit", "strong" } },
	weak = { Text = "x0.75", Face = SIGN.Red, Lip = SIGN.RedLip, Caption = { "weak hit", "weak" } },
	none = { Text = "x1", Face = SIGN.Tile, Lip = SIGN.StoneLip, Caption = { "no arrow", "no arrow" } },
}
local function tag(parent, kind, x, y, w, h, size, z)
	local t = TAGS[kind]
	local label = text(parent, "Tag_" .. kind, t.Text, "Display", size, Theme.TextOn(t.Face), {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z,
	})
	CloudUI.SignBlock(label, "Stone", { Face = t.Face, LipColor = t.Lip, EdgePx = 2, LipPx = 3 })
	label.TextColor3 = Theme.TextOn(t.Face)
	return label
end

----------------------------------------------------------------------
-- the chart
----------------------------------------------------------------------
local function buildRing(chart, spec, cycle, z)
	local R = spec.Ring
	local ring = frame(chart, "Ring", { Size = UDim2.fromOffset(R.W, R.H), ZIndex = z })
	local bw, bh = R.Block[1], R.Block[2]
	local centres = {}
	for i, element in ipairs(cycle) do
		local slot = R.Slots[i]
		if slot then
			local x, y = R.Cols[slot[1]], R.Rows[slot[2]]
			elementBlock(ring, element, x, y, bw, bh, R.Glyph, R.Name, z + 1)
			centres[i] = { x + bw / 2, y + bh / 2 }
		end
	end
	local n = #cycle
	for i = 1, n do
		local a, b = centres[i], centres[i % n + 1]
		local name = R.Links[i]
		if a and b and name then
			local diagonal = name:match("^arrow[ns][ew]$") ~= nil
			local px = diagonal and R.Diag or R.Straight
			local icon = iconAt(ring, name, px, SIGN.Wood, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, z + 2)
			if icon then
				icon.Name = "Link" .. i
			end
		end
	end
	local H = R.Hub
	local hub = frame(ring, "Hub", { Position = UDim2.fromOffset(H[1], H[2]), Size = UDim2.fromOffset(H[3], H[4]), ZIndex = z + 1 })
	CloudUI.SignBlock(hub, "Stone", { Face = SIGN.Tile, EdgePx = 2, LipPx = 4, Pad = false })
	local bigH = H[5] + 4
	local subH = H[6] + 4
	local top = math.floor((H[4] - 4 - bigH - subH) / 2)
	text(hub, "Mult", "x" .. tostring(Config.Elements.StrongMultiplier or 1.5), "Display", H[5], SIGN.GrassLip, {
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 0, bigH),
		ZIndex = z + 2,
	})
	text(hub, "Sub", R.HubSub, "Label", H[6], INK, {
		Position = UDim2.fromOffset(0, top + bigH),
		Size = UDim2.new(1, 0, 0, subH),
		ZIndex = z + 2,
	})
	return ring
end

-- one worked example at y (a card on PC): the attacker's square, the arrow (or "vs"), the defender's, the tag, its words
local function example(side, spec, kind, y, z)
	local S = spec.Side
	local strongMap = Config.Elements.Strong or {}
	local cycle = ElementsWindow.Cycle()
	local a = cycle[1] or "Water"
	local b = (strongMap[a] and strongMap[a][1]) or cycle[2] or "Flame"
	if kind == "weak" then
		a, b = b, a
	elseif kind == "none" then
		b = cycle[5] or "Earth" -- (two steps away on the loop: no arrow either way)
	end
	local row = frame(side, "Example_" .. kind, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(S.W, S.RowH), ZIndex = z })
	if S.Cards then
		CloudUI.SignBlock(row, "Stone", { Face = SIGN.Tile, EdgePx = 2, LipPx = 4, Pad = false })
	end
	local pad = S.Cards and 14 or 0
	local q = S.Square
	local qy = math.floor((S.RowH - (S.Cards and 4 or 0) - q) / 2)
	elementBlock(row, a, pad, qy, q, q, S.SquareGlyph, nil, z + 1, "From")
	local x = pad + q + 8
	if kind == "none" then
		text(row, "Vs", "vs", "Heading", S.Caption + 4, INK, {
			Position = UDim2.fromOffset(x, qy),
			Size = UDim2.fromOffset(S.Arrow, q),
			ZIndex = z + 1,
		})
	else
		iconAt(row, "arrow", S.Arrow, SIGN.Wood, x + S.Arrow / 2, qy + q / 2, z + 1)
	end
	x = x + S.Arrow + 8
	elementBlock(row, b, x, qy, q, q, S.SquareGlyph, nil, z + 1, "To")
	x = x + q + 12
	local tw, th, ts = S.Tag[1], S.Tag[2], S.Tag[3]
	local caption = TAGS[kind].Caption[S.Cards and 1 or 2]
	if S.Cards then
		-- the tag on top, its words under it, right-aligned with the card
		local tx = S.W - pad - tw - 40
		tag(row, kind, tx, qy - 4, tw, th, ts, z + 1)
		text(row, "Caption", caption, "Label", S.Caption, INK, {
			Position = UDim2.fromOffset(tx - 40, qy + th),
			Size = UDim2.fromOffset(tw + 80, S.Caption + 6),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = z + 1,
		})
	else
		tag(row, kind, x, math.floor((S.RowH - th) / 2), tw, th, ts, z + 1)
		text(row, "Caption", caption, "Label", S.Caption, INK, {
			Position = UDim2.fromOffset(x + tw + 8, 0),
			Size = UDim2.fromOffset(math.max(10, S.W - (x + tw + 8)), S.RowH),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = z + 1,
		})
	end
	return row
end

local function buildSide(chart, spec, rest, z)
	local S = spec.Side
	local side = frame(chart, "Side", { Size = UDim2.fromOffset(S.W, 10), ZIndex = z })
	local y = 0
	if S.Head > 0 then
		-- (a plain heading in the mock's own case: the ribbon is for the window's title only)
		text(side, "HowItWorks", "How it works", "Heading", S.Head, INK, {
			Size = UDim2.fromOffset(S.W, S.Head + 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = z + 1,
		})
		y = y + S.Head + 8
	end
	if S.Body and S.BodyLine then
		text(side, "Explain", S.BodyLine, "Body", S.Body, INK, {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.fromOffset(S.W, S.Body + 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = z + 1,
		})
		y = y + S.Body + 12
	end
	for _, kind in ipairs(S.Examples) do
		example(side, spec, kind, y, z + 1)
		y = y + S.RowH + S.RowGap
	end
	-- the rivals: the elements outside the loop, each strong against the other
	local a, b = rest[1], rest[2]
	if a and b then
		local rule = SignKit.Rule(side, { Name = "Rule", Width = S.W, ZIndex = z + 1 })
		rule.Position = UDim2.fromOffset(0, y + 4)
		y = y + 12
		if S.Head > 0 then
			text(side, "Rivals", "The rivals", "Heading", S.Head, INK, {
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.fromOffset(S.W, S.Head + 6),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = z + 1,
			})
			y = y + S.Head + 10
		end
		local RB = S.RivalBlock
		local row = frame(side, "RivalRow", { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(S.W, RB[2]), ZIndex = z + 1 })
		elementBlock(row, a, 0, 0, RB[1], RB[2], RB[3], RB[4], z + 2)
		local ax = RB[1] + 10
		local ap = S.RivalArrow
		local inner = RB[2] - 5
		iconAt(row, "arrow", ap, SIGN.Wood, ax + ap / 2, inner / 2 - ap / 2 - 2, z + 2)
		iconAt(row, "left", ap, SIGN.Wood, ax + ap / 2, inner / 2 + ap / 2 + 2, z + 2)
		local bx = ax + ap + 10
		elementBlock(row, b, bx, 0, RB[1], RB[2], RB[3], RB[4], z + 2)
		if S.Cards then
			text(side, "RivalCaption", S.RivalText, "Label", S.RivalCaption, INK, {
				Position = UDim2.fromOffset(0, y + RB[2] + 8),
				Size = UDim2.fromOffset(bx + RB[1], S.RivalCaption + 6),
				ZIndex = z + 1,
			})
			y = y + RB[2] + 8 + S.RivalCaption + 6
		else
			local cx = bx + RB[1] + 10
			text(row, "RivalCaption", S.RivalText, "Label", S.RivalCaption, INK, {
				Position = UDim2.fromOffset(cx, 0),
				Size = UDim2.fromOffset(math.max(10, S.W - cx), RB[2]),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = z + 2,
			})
			y = y + RB[2]
		end
	end
	side.Size = UDim2.fromOffset(S.W, y)
	return side, y
end

----------------------------------------------------------------------
-- the window
----------------------------------------------------------------------
local function viewportOf(gui)
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and vp.X > 2 and vp.Y > 2 then
		return vp
	end
	local s = gui and gui.AbsoluteSize
	return (s and s.X > 2) and s or Vector2.new(1920, 1080)
end

local function insetY()
	local inset = 58
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	return inset
end

-- the HUD's currency strips' (or the gift's) bottom in gui-area px (0: none), as the Gifts window reads it
local function stripsBottom(gui)
	local pg = gui and gui.Parent
	local hud = pg and pg:FindFirstChild("NimbusHud")
	if not hud then
		return 0
	end
	local gift = tonumber(hud:GetAttribute("GiftSize")) or 0
	if gift > 0 then
		return tonumber(hud:GetAttribute("GiftTop")) or 0
	end
	return tonumber(hud:GetAttribute("TopRightBottom")) or 0
end

-- the mode, the scale and the holder's place (gui-area px) for this screen
function ElementsWindow.Rect(gui)
	local vp = viewportOf(gui)
	local inset = (gui and gui.IgnoreGuiInset) and 0 or insetY()
	local areaW, areaH = vp.X, vp.Y - inset
	local factor = Theme.ScreenFactor(vp.Y)
	local mode
	if areaH > areaW then
		mode = "Portrait"
	elseif areaH / factor < 560 then
		mode = "Short"
	else
		mode = "PC"
	end
	local spec = L[mode]
	local m = ElementsWindow.MARGIN
	local roofRoom = spec.Roof and 22 or 0
	local cap = mode == "PC" and factor or 1
	local scale = math.min(cap, (areaW - 2 * m) / spec.W, (areaH - 2 * m - roofRoom) / spec.H)
	scale = math.max(0.4, scale)
	local w, h = spec.W * scale, spec.H * scale
	local x = math.floor((areaW - w) / 2 + 0.5)
	local y = math.floor((areaH - h + roofRoom * scale) / 2 + 0.5)
	if mode == "Portrait" then
		-- (the Gifts window's rule) the awning clears the currency strips by ROOF_CLEAR when the screen has the room
		local want = stripsBottom(gui) + ElementsWindow.ROOF_CLEAR * scale
		if y < want and want + h <= areaH - m then
			y = math.floor(want + 0.5)
		end
	end
	return { Mode = mode, Scale = scale, X = x, Y = y, W = w, H = h, Inset = inset }
end

function ElementsWindow.New(gui, opts)
	opts = opts or {}
	local win = { Mode = nil, Open_ = false }
	local holder = frame(gui, "Window_Elements", { Visible = false, ZIndex = 10, Active = true })
	local fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	win.Holder = holder
	local panel, chart = nil, nil

	local function build(mode)
		if panel then
			panel.Root:Destroy()
		end
		local spec = L[mode]
		panel = CloudUI.Panel({
			Name = "ElementsPanel",
			Title = "Elements",
			Closable = true,
			Skin = "Signboard",
			Icon = "sparkle",
			Size = UDim2.fromScale(1, 1),
			OnClose = function()
				win.Close()
			end,
			Parent = holder,
		})
		if panel.Roof then
			panel.Roof.Visible = spec.Roof == true -- (a landscape phone: no awning, as the Gifts window's)
		end
		win.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel.Root })
		local content = panel.Content
		chart = frame(content, "Chart", { Size = UDim2.fromScale(1, 1), ZIndex = 5 })
		local cycle, rest = ElementsWindow.Cycle()
		local contentTop = CloudUI.ContentInset(true)
		local cw, ch = spec.W - 24, spec.H - contentTop - 12
		local ring = buildRing(chart, spec, cycle, 5)
		local side, sideH = buildSide(chart, spec, rest, 5)
		local R = spec.Ring
		if mode == "Portrait" then
			local gap = spec.Side.Below or 16
			local total = R.H + gap + sideH
			local top = math.max(0, math.floor((ch - total) / 2))
			ring.Position = UDim2.fromOffset(math.floor((cw - R.W) / 2), top)
			side.Position = UDim2.fromOffset(math.floor((cw - spec.Side.W) / 2), top + R.H + gap)
		else
			ring.Position = UDim2.fromOffset(0, math.max(0, math.floor((ch - R.H) / 2)))
			side.Position = UDim2.fromOffset(spec.Side.X, math.max(0, math.floor((ch - sideH) / 2)))
		end
		win.Panel = panel
		win.Mode = mode
		holder:SetAttribute("Mode", mode)
	end

	-- (look review r0) the window's left edge to the caller while it is open (nil once it closed): the Index steps the menu
	-- tiles aside where the window reaches over them (844x390: slivers of the tiles showed at its left edge)
	local function place(left)
		if type(opts.OnPlace) == "function" then
			pcall(opts.OnPlace, left)
		end
	end

	function win.Relayout()
		local r = ElementsWindow.Rect(gui)
		local spec = L[r.Mode]
		-- (look review r0) the holder takes its size before the panel is built in it, and the title's ribbon is fitted again
		-- once its label has that box: fitted while the label had no box yet, the ribbon took the full pads its 220 px box
		-- on a 390 px phone has no room for, and its right tail ran under the X
		holder.Position = UDim2.fromOffset(r.X, r.Y)
		holder.Size = UDim2.fromOffset(spec.W, spec.H)
		fit.Scale = r.Scale
		if r.Mode ~= win.Mode or not panel then
			build(r.Mode)
		end
		if panel and panel.TitleLabel then
			Theme.StyleTitle(panel.TitleLabel)
		end
		win.Rect = r
		if win.Open_ then
			place(r.X)
		end
		return r
	end

	function win.IsOpen()
		return win.Open_ == true
	end

	function win.Open()
		win.Relayout()
		local was = win.Open_
		win.Open_ = true
		holder.Visible = true
		place(win.Rect and win.Rect.X or 0)
		if not was and panel then
			SignKit.Rise(panel.Root) -- (Pitch 2 F0) the kit's open: it rises 12 px in 3 hard steps
		end
	end

	function win.Close()
		if not win.Open_ then
			return
		end
		win.Open_ = false
		holder.Visible = false
		place(nil)
		if type(opts.OnClose) == "function" then
			pcall(opts.OnClose)
		end
	end

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if win.Open_ then
			pcall(win.Relayout)
		end
	end)
	-- the cursor is free while the window shows (client/MouseLock, as every window's)
	local okLock, lock = pcall(function()
		local module = script.Parent.Parent:FindFirstChild("MouseLock")
		return module and require(module)
	end)
	if okLock and type(lock) == "table" and type(lock.WatchVisible) == "function" then
		pcall(lock.WatchVisible, "Dock:" .. holder.Name, holder)
	end
	return win
end

return ElementsWindow
