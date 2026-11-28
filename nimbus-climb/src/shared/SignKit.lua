-- SignKit: the Signboard parts of kit B (U2 of .superpowers/slop-audit/round3/BUILD_PLAN.md, findings 5 and 7; the owner's
-- approved pitch, kit_pitch_mockups.html "B. Cloud Shop Signboard"). One shared set of parts that the loading screen
-- (ReplicatedFirst: Shared only) and every window build from. Square blocks, no slice image: a part is Frames in the
-- Theme.Sign colours, an edge, a darker bottom lip and a face, never a glow, a gradient or a scale bounce.
--   SignKit.Roof(parent, opts)    the flat pink awning with its dark edge and darker lip: ONE fixed-size piece (offset
--                                 only, never stretched with the window; Gemini's rule), centred on the window's top.
--                                 opts.Shape = "Gable": the Credits window's gable (two slopes, fascia, vent)
--   SignKit.Header(parent, opts)  the navy sign plank in a wood rim, its title in FredokaOne gold (Title role, through
--                                 Theme.StyleTitle); returns head, plate (the caller adds a close X to the plate).
--                                 opts.Ribbon: the untabbed window's header (Pitch 2 F0 A: its plate inside the
--                                 rim, no tails; the title wears the gold V-notched ribbon on it).
--                                 (U9-4 look review, the one header rule) every untabbed window and side panel
--                                 (Pets, Index, Stats, My Home, Settings, What's New, the Sky Trove) uses this
--                                 header with Ribbon. A TABBED window (the Shop, the Gifts window) keeps its navy
--                                 band inside the frame instead: its tabs sit on the band, where the ribbon's piping
--                                 and tails would run under them. Both share the icon square (Sizes.IconSlot, a 2 px
--                                 ink edge), the gold ribbon title and the red close block
--   SignKit.Frame(parent, opts)   the wood frame under the header
--   SignKit.Body(frame, opts)     the stone body inside it, with the stone lip along its bottom
--   SignKit.Plank(parent, opts)   a button with a real bottom lip: hover lifts the block 2 px, press sinks it 4 px and the
--                                 lip shrinks to 2 px (U5: the pitch's .dn); the label shrinks to fit, then truncates;
--                                 Style Off is disabled; SignKit.PlankState(plank, "Rest" | "Hover" | "Press") sets one
--   SignKit.Rope(parent, opts)    a rope / post the board hangs from
--   SignKit.BlockRow(parent, opts) n stone blocks with a darker lip; SignKit.FillBlocks(row, k) turns the first k gold
--   SignKit.FitBlocks(parent, opts) (LOOK-ui) a BlockRow filling its own box (a bar's place): n blocks of one whole width
--   SignKit.ScrollBar(scroll, opts) (U9-7 look) a list's bar: the kit's thickness, the wood, square ends
--   SignKit.FitBlocks(parent, opts) (LOOK-ui) a BlockRow filling its own box (a bar's place): n blocks of one whole width
--   SignKit.Notice(parent, opts)  a small wood-framed stone card (a tip, a notice); returns notice, face
--   SignKit.Nails(board, opts)    (U9-7) two nail heads on a hanging board's top corners (the handmade touch)
--   SignKit.Scroll(sf, thickness) (LOOK-ui) the kit's one scroll bar on a ScrollingFrame: wood, opaque, square ends
--   SignKit.Rig(parts, opts)      (sign/logo build: the owner's pick B2 "Sky-climber's rig", 2026-11-13; it replaced the
--                                 Workshop trim) a hanging board's canopy (canvas under navy stripes, a scalloped
--                                 valance with brass piping, a stitched patch), the frame's bevel, rope lashings on its
--                                 corners, the canvas body's hem, twisted ropes ending in carabiners on eye-bolts, two
--                                 propellers, the brass version plate. Opt-in: only the title screen's and the loading
--                                 screen's boards call it (Credits stays as approved). SignKit.Spin(root, on) flips the
--                                 propellers (2 frames, never a rotation); SignKit.PropFrame(root, n) sets one
-- Every part stamps attribute SignKit = its kind. Sizes are design px of a 1080p screen (the pitch's 0.8-scale px / 0.8);
-- opts override any colour or size, so a look the owner already approved (Credits) builds from these parts unchanged.
-- (LOOK-ui, kitb-look1) every edge, inset and lip is a whole number of screen px under the window's scale (PixelIcon.Px /
-- PixelIcon.Whole): at a 0.8 Fit a 2 px edge draws 2 screen px, not 1.6.
-- Requires only Theme and PixelIcon (Shared; PixelIcon requires nothing at load). Plain Lua 5.1-compatible syntax only.

local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))

local SignKit = {}

local Sign = Theme.Sign

SignKit.Sizes = {
	RoofW = 320, -- the awning's default width (a window passes its own, still a fixed offset)
	RoofH = 18,
	RoofEdge = 4, -- the dark border round the awning
	RoofLip = 5, -- its darker bottom lip
	-- (U9-4 look review 2) a phone window's awning (the portrait Gifts window, the portrait Trove sheet): 240, so its right
	-- end keeps clear of the close block on a 390 px screen (the 288 of the 0.8 windows lay over it)
	RoofPhoneW = 240,
	HeadH = 64,
	Rim = 6, -- the header's wood rim (top, left, right; the frame below closes it): the frame's width, so the edge runs straight
	TitleX = 18,
	IconSlot = 42, -- the gold icon square in a header
	-- (U9-4 look review 2: one pixel size per screen) a window's pixel icons draw at one of two sizes, one double the other:
	-- Glyph (a header icon, a sparkle, a clock, a reward's coin) and Art (a reward's art on its chip, a tick, a row's
	-- icon): 3 / 6 px cells on PC (27 / 54 at 1080p), 2 / 4 px on a phone (18 / 36). The Gifts window and the Trove read it
	Pixel = { PC = { Glyph = 27, Art = 54 }, Phone = { Glyph = 18, Art = 36 } },
	Frame = 6, -- the wood frame round a body
	Edge = 5, -- a block's edge (planks, notices)
	Lip = 8, -- a block's darker bottom lip
	PlankH = 50,
	Hover = 2, -- hover lifts a plank this far
	Sink = 4, -- press sinks the whole plank this far (the pitch's .dn translateY 4px) ...
	PressLip = 2, -- ... and its lip shrinks to this (.dn lip 2px)
	LabelPad = 6, -- a plank label's room inside the face, each side
	NoticeGap = 18, -- a notice's icon square to its text
	RopeW = 6,
	ScrollBar = 8, -- (U9-7 look) a scrolling list's bar on kit B: this thick, in the wood, opaque (every window's lists)
	ScrollBarPhone = 6, -- (LOOK-ui) the same bar in a phone layout's list
	BlockW = 28,
	BlockH = 22,
	BlockGap = 4,
	BlockEdge = 2,
	BlockLip = 4,
	-- (kit-b gate U9 r4: one bar language, the owner's look bar "every bar in the same block-bar language") the only two
	-- weights a bar (SignKit.FitBlocks, opts.Weight) may take: Bar for every bar on a screen (HP, XP, stamina, cooldown,
	-- progress, timers) and Micro only for a world billboard (a pet's floating card) or a tiny team pip. Edge / Lip / Gap
	-- design px (a Bar's gap 2 or 3: GapMax); MinEdge / MinLip SCREEN px, so a phone window's 0.5 Fit keeps a 2 px wood
	-- edge like its planks (the Food Machine's rows drew 1 px hairline boxes)
	Bar = { Edge = 2, Lip = 3, Gap = 2, GapMax = 3, MinEdge = 2, MinLip = 2 },
	Micro = { Edge = 1, Lip = 1, Gap = 1, GapMax = 1, MinEdge = 1, MinLip = 1 },
	NoticeEdge = 4,
	NoticeLip = 4,
	-- (LOOK-ui, kitb-look1: the Pets, Index, Home, Stats and Shop closes drew 35 to 47 screen px with 2 or 3 px cells, by
	-- their window's Fit) one close block: never under CloseMin screen px square, its x in CloseCell screen px cells
	-- (NeonKit.CloseBlock)
	CloseMin = 44,
	CloseCell = 3,
}
local Z = SignKit.Sizes

-- plank looks: face, lip, edge, text (the pitch's .bt, .bt.pri, .bt.sel, .bt.dng, .bt.off and the navy sign)
SignKit.Styles = {
	Stone = { Face = Sign.Tile, Lip = Sign.StoneLip, Edge = Sign.Wood, Text = Sign.Text },
	Grass = { Face = Sign.Grass, Lip = Sign.GrassLip, Edge = Sign.Wood, Text = Sign.OnGrass },
	Gold = { Face = Sign.Gold, Lip = Sign.GoldLip, Edge = Sign.Wood, Text = Sign.Text },
	Red = { Face = Sign.Red, Lip = Sign.RedLip, Edge = Sign.Wood, Text = Color3.new(1, 1, 1) },
	Navy = { Face = Sign.Navy, Lip = Sign.NavyLip, Edge = Sign.GoldLip, Text = Sign.Gold }, -- the pitch's sign edge (--signEdge)
	Off = { Face = Sign.Well, Lip = Sign.Well, Edge = Sign.WellEdge, Text = Sign.TextMuted, Off = true },
	-- (U9-8 look) a small secondary action in a row (the Sky Obby picker's PICK): the sky face on its SkyLip lip
	Sky = { Face = Sign.Sky, Lip = Sign.SkyLip, Edge = Sign.Wood, Text = Sign.Text },
}

local function frame(name, props, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for key, value in pairs(props or {}) do
		f[key] = value
	end
	f.Parent = parent
	return f
end

local function fill(name, colour, props, parent)
	props = props or {}
	props.BackgroundTransparency = 0
	props.BackgroundColor3 = colour
	return frame(name, props, parent)
end

local function round(parent)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = parent
	return c
end

local function line(parent, colour, thickness)
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Parent = parent
	-- (U9-8 look; LOOK-ui) a whole number of screen px under the scale above it (SignKit.Whole, below: it counts every
	-- layout UIScale, so the Credits board under its own scale keeps the approved tree)
	SignKit.Whole(s, function(sc)
		s.Thickness = SignKit.Px(thickness, sc)
	end)
	return s
end

-- (LOOK-ui) a lip `n` design px tall along its parent's bottom, and a face inset `e` px from its parent's sides (`extra`
-- px more off its height: the lip it leaves showing), both whole screen px under the window's scale
local function lipOf(lip, n)
	return PixelIcon.WholeHeight(lip, n)
end
local function inset(face, e, extra)
	return PixelIcon.WholeInset(face, e, extra)
end
SignKit.Inset = inset

-- the caller's placement (Position, AnchorPoint, ZIndex, LayoutOrder, Name, Active, Visible), then the kind stamp
local PLACE = { "Position", "AnchorPoint", "ZIndex", "LayoutOrder", "Name", "Active", "Visible" }
local function place(obj, opts, kind)
	for _, key in ipairs(PLACE) do
		if opts[key] ~= nil then
			obj[key] = opts[key]
		end
	end
	obj:SetAttribute("SignKit", kind)
	return obj
end

local function text(name, value, role, size, colour, props, parent)
	local l = Theme.Label(tostring(value or ""), role, { Size = size, Color = colour, Stroke = 1 })
	l.Name = name
	for key, v in pairs(props) do
		l[key] = v
	end
	l.Parent = parent
	return l
end

----------------------------------------------------------------------
-- whole screen pixels (U9-8 look)
----------------------------------------------------------------------

-- (U9-8 look; the owner's look bar: pixel edges on whole pixels at every screen size) a window or a HUD card lives under a
-- layout UIScale (0.8 on phones and on a 1280x720 window), so a part sized in design px landed between pixels: a 2 px edge
-- drew 1.6 px, a 4 px lip 3.2, a 6 px frame 4.8 (soft in a render, 1 or 2 px in Roblox by where it fell). The kit's sizes
-- (an edge, a lip, the frame, the roof, a nail) now resolve to whole SCREEN px under the scale above them, PixelIcon's
-- rule for its cells: round(px x scale), never under 1 px. A part whose two edges are a whole number of px apart draws
-- that many px wherever it sits (Roblox rounds both edges the same way). The tweens on top (a press, a pop, a pulse) are
-- not counted. SignKit.Px(px, s): the design px of round(px x s) screen px (0 stays 0). SignKit.LayoutScale(obj): the
-- product of the layout UIScales on obj and above it. SignKit.Whole(obj, fit): calls fit(s) now and again whenever obj
-- moves (it lands under a ScreenGui) or one of the layout UIScales above it changes (the latest fit given wins)
local TWEEN_SCALES = { Pop = true, PopScale = true, FxScale = true, Punch = true, Pulse = true, Swell = true, Bounce = true }
local wholeFits = setmetatable({}, { __mode = "k" }) -- [obj] = fit
local wholeSets = setmetatable({}, { __mode = "k" }) -- [UIScale] = { [obj] = true }
local wholeConns = setmetatable({}, { __mode = "k" })

local function layoutScale(obj)
	local s, scales = 1, {}
	local cur = obj
	while cur do
		if cur:IsA("LayerCollector") then
			break
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
	return s, scales
end

function SignKit.LayoutScale(obj)
	return (layoutScale(obj))
end

function SignKit.Px(px, s)
	px = tonumber(px) or 0
	if px <= 0 then
		return 0
	end
	s = (s and s > 0) and s or 1
	return math.max(1, math.floor(px * s + 0.5)) / s
end

-- (Pitch 2 F0) a finish part also refits when a UIScale is ADDED above it after it was fitted (the match result card is
-- built, then scaled to the viewport: NotifyController's ViewportScale): SignKit.Whole only hears the scales that were
-- there at its fit. scaleWatch[obj] = true opts a part in; scaleAdds[ancestor] = { [obj] = true }
local scaleWatch = setmetatable({}, { __mode = "k" })
local scaleAdds = setmetatable({}, { __mode = "k" })
local refitWhole
local function hookScaleAdds(obj)
	local cur = obj.Parent
	while cur and not cur:IsA("LayerCollector") do
		local set = scaleAdds[cur]
		if not set then
			set = setmetatable({}, { __mode = "k" })
			scaleAdds[cur] = set
			cur.ChildAdded:Connect(function(c)
				if c:IsA("UIScale") then
					for o in pairs(set) do
						refitWhole(o)
					end
				end
			end)
		end
		set[obj] = true
		cur = cur.Parent
	end
end

refitWhole = function(obj)
	local fit = wholeFits[obj]
	if not fit then
		return
	end
	if scaleWatch[obj] then
		hookScaleAdds(obj)
	end
	local s, scales = layoutScale(obj)
	fit(s)
	for _, scale in ipairs(scales) do
		local set = wholeSets[scale]
		if not set then
			set = setmetatable({}, { __mode = "k" })
			wholeSets[scale] = set
			wholeConns[scale] = scale:GetPropertyChangedSignal("Scale"):Connect(function()
				for o in pairs(set) do
					refitWhole(o)
				end
			end)
		end
		set[obj] = true
	end
end

function SignKit.Whole(obj, fit)
	local first = wholeFits[obj] == nil
	wholeFits[obj] = fit
	if first then
		obj.AncestryChanged:Connect(function()
			refitWhole(obj)
		end)
	end
	refitWhole(obj)
end

----------------------------------------------------------------------
-- the finish (Pitch 2 item F0, the owner's pick A "Carved signboard", 2026-11-20)
----------------------------------------------------------------------

-- ONE light from the top left on every part (Theme.Finish; the mock-ups .superpowers/slop-audit/round3/build/PITCH2/
-- F_overall_finish/F0_*_optA.png): a wood edge lit WoodLight on its top and left and shaded WoodDark on its bottom and
-- right, the stone body sunk under its frame with a carved rim, a slot a sunk well, a raised card's two-step diagonal hard
-- shadow (no blur). Every finish part is a holder Frame named Finish<Kind> (attribute Finish = <Kind>) of plain square
-- Frames, ZIndex 0 (under its part's own children, over the part's face), laid over the part's box (or `out` px round it:
-- a block whose wood edge is a UIStroke outside its box) in whole screen px (SignKit.Whole on the holder, so the part's
-- own fit stays). It never moves or resizes the part, so no window's layout or fit changes. A UIPadding on the part (a
-- text block's LipPad) would move its children: the holders reach back out by it, now and whenever it changes. Calling a
-- finish again updates its one holder. A part built with opts.Finish = false (the approved Credits window) gets none.
-- (playtest 2026-11-28 C2 / C3) nor does a part whose children a layout (list, grid, page, table) places, or whose size
-- AutomaticSize takes from its children, now or when that comes later (most callers add the layout after SignBlock):
-- a layout laid the holders out as rows (the Ring champion and rewards cards and the Raid tier card came out empty,
-- the trophy chip blank, a stray shadow line beside the x2 countdown) and an AutomaticSize part grew round holders that
-- reach `out` px past it, which grew with it (the arena "pets can battle here" notice became a 568x157 board)
local FIN = Theme.Finish
local WHITE = Color3.new(1, 1, 1)
local FIN_PARTS = setmetatable({}, { __mode = "k" }) -- [part] = { [holder] = true }: refit when its padding or size changes

local function padOf(obj)
	local pad = obj:FindFirstChildOfClass("UIPadding")
	if not pad then
		return 0, 0, 0, 0
	end
	return pad.PaddingLeft.Offset, pad.PaddingTop.Offset, pad.PaddingRight.Offset, pad.PaddingBottom.Offset
end

-- the holder over obj's box, `out` px round it, whatever obj's padding
local function cover(obj, h, out)
	local l, t, r, b = padOf(obj)
	h.Position = UDim2.fromOffset(-l - out, -t - out)
	h.Size = UDim2.new(1, l + r + 2 * out, 1, t + b + 2 * out)
end

-- the finish parts of a part that has them (holders, its shine / top line; not an awning's trim)
local function finishParts(obj)
	local out = {}
	for _, c in ipairs(obj:GetChildren()) do
		local k = c:GetAttribute("Finish")
		if k ~= nil and k ~= "Awning" then
			out[#out + 1] = c
		end
	end
	return out
end

-- (C2 review) every layout class that places a part's children (Roblox's UIGridStyleLayout family, named one by one:
-- the test mock has no UIGridStyleLayout base class)
local LAYOUTS = { "UIListLayout", "UIGridLayout", "UIPageLayout", "UITableLayout" }
local function isLayout(c)
	for _, class in ipairs(LAYOUTS) do
		if c:IsA(class) then
			return true
		end
	end
	return false
end

-- (C2 / C3) true when a layout places obj's children or AutomaticSize sizes obj: it takes no finish parts
local function finishless(obj)
	if obj:IsA("GuiObject") and obj.AutomaticSize ~= Enum.AutomaticSize.None then
		return true
	end
	for _, c in ipairs(obj:GetChildren()) do
		if isLayout(c) then
			return true
		end
	end
	return false
end
SignKit.Finishless = finishless

local function shed(obj)
	for _, c in ipairs(finishParts(obj)) do
		c:SetAttribute("FinishOff", true)
		c.Visible = false
	end
end

local function track(obj, h)
	local set = FIN_PARTS[obj]
	if not set then
		set = setmetatable({}, { __mode = "k" })
		FIN_PARTS[obj] = set
		local function again()
			for x in pairs(set) do
				refitWhole(x)
			end
		end
		local function hook(c)
			if c:IsA("UIPadding") then
				c.Changed:Connect(again)
			end
		end
		for _, c in ipairs(obj:GetChildren()) do
			hook(c)
		end
		obj.ChildAdded:Connect(function(c)
			hook(c)
			if c:IsA("UIPadding") or c.Name == "CloseMark" then
				again()
			end
			if isLayout(c) then
				shed(obj) -- (C2) a layout came after the finish: its parts leave the layout
			end
		end)
		obj:GetPropertyChangedSignal("Size"):Connect(again)
		if obj:IsA("GuiObject") then
			obj:GetPropertyChangedSignal("AutomaticSize"):Connect(function()
				if finishless(obj) then
					shed(obj) -- (C3)
				end
			end)
		end
	end
	set[h] = true
end

local function holderOf(obj, name, kind)
	local h = obj:FindFirstChild(name)
	if not h then
		h = frame(name, { ZIndex = 0 }, obj)
		h:SetAttribute("Finish", kind)
	end
	scaleWatch[h] = true
	h:SetAttribute("FinishOff", nil)
	h.Visible = true
	track(obj, h)
	if finishless(obj) then
		shed(obj) -- (C2 / C3) built, so a repaint keeps one holder, but never shown
	end
	return h
end

local function strip(h, name, colour, transparency)
	local s = h:FindFirstChild(name)
	if not s then
		s = fill(name, colour, { ZIndex = 0 }, h)
	end
	s.BackgroundColor3 = colour
	s.BackgroundTransparency = transparency or 0
	return s
end

local function same(a, b)
	return typeof(a) == "Color3" and typeof(b) == "Color3" and math.abs(a.R - b.R) < 0.004 and math.abs(a.G - b.G) < 0.004 and math.abs(a.B - b.B) < 0.004
end

-- hide a finish holder (it stays hidden until its finish is called again)
local function hide(obj, name)
	local h = obj and obj:FindFirstChild(name)
	if h then
		h:SetAttribute("FinishOff", true)
		h.Visible = false
	end
end
SignKit.HideFinish = hide

-- the light on a wood edge. opts: Px (thick: Finish.Bevel on a window frame, Finish.Line on a block), Out (design px of
-- the part's edge stroke outside its box, 0 = the edge is the part's own border), Sides ("TLBR"; a header's rim "TLR"),
-- Light / Dark (WoodLight / WoodDark). Children LitT, LitL, DarkB, DarkR (the shaded ones drawn last: they win the corners)
function SignKit.Bevel(obj, opts)
	opts = opts or {}
	local h = holderOf(obj, "FinishBevel", "Bevel")
	local px, out = tonumber(opts.Px) or FIN.Line, tonumber(opts.Out) or 0
	local sides = opts.Sides or "TLBR"
	local parts = {}
	for _, d in ipairs({ { "T", "LitT", opts.Light or Sign.WoodLight }, { "L", "LitL", opts.Light or Sign.WoodLight },
		{ "B", "DarkB", opts.Dark or Sign.WoodDark }, { "R", "DarkR", opts.Dark or Sign.WoodDark } }) do
		if sides:find(d[1], 1, true) then
			parts[d[1]] = strip(h, d[2], d[3])
		elseif h:FindFirstChild(d[2]) then
			h[d[2]]:Destroy()
		end
	end
	SignKit.Whole(h, function(sc)
		local t = SignKit.Px(px, sc)
		cover(obj, h, SignKit.Px(out, sc))
		if parts.T then
			parts.T.Position = UDim2.new(0, 0, 0, 0)
			parts.T.Size = UDim2.new(1, 0, 0, t)
		end
		if parts.L then
			parts.L.Position = UDim2.new(0, 0, 0, 0)
			parts.L.Size = UDim2.new(0, t, 1, 0)
		end
		if parts.B then
			parts.B.Position = UDim2.new(0, 0, 1, -t)
			parts.B.Size = UDim2.new(1, 0, 0, t)
		end
		if parts.R then
			parts.R.Position = UDim2.new(1, -t, 0, 0)
			parts.R.Size = UDim2.new(0, t, 1, 0)
		end
	end)
	return h
end

-- a block under Finish.SmallBlock design px tall (a chip, a key cap) casts no shadow; nor a close block or a part with
-- attribute NoShadow
local function noShadow(obj, sc)
	if obj:GetAttribute("NoShadow") == true or obj:FindFirstChild("CloseMark") then
		return true
	end
	local s = obj.Size
	local tall = s.Y.Scale == 0 and s.Y.Offset or ((obj.AbsoluteSize.Y > 0 and sc > 0) and obj.AbsoluteSize.Y / sc or math.huge)
	return tall < FIN.SmallBlock
end

-- the two-step diagonal hard shadow down and right of the part (no blur: a darker near band Px - Step wide, a lighter
-- outer step to Px). opts: Px (Finish.Card, Finish.Window), Out (as Bevel's), Block (a block: none when it is small).
-- Children FarR, FarB (drawn first), NearR, NearB, in the ink at Finish.Far / Finish.Near transparency
function SignKit.Shadow(obj, opts)
	opts = opts or {}
	local h = holderOf(obj, "FinishShadow", "Shadow")
	local off, out = tonumber(opts.Px) or FIN.Card, tonumber(opts.Out) or 0
	local farR, farB = strip(h, "FarR", Sign.Text, FIN.Far), strip(h, "FarB", Sign.Text, FIN.Far)
	local nearR, nearB = strip(h, "NearR", Sign.Text, FIN.Near), strip(h, "NearB", Sign.Text, FIN.Near)
	local block = opts.Block == true
	SignKit.Whole(h, function(sc)
		local f = SignKit.Px(off, sc)
		local n = SignKit.Px(math.max(1, off - FIN.Step), sc)
		cover(obj, h, SignKit.Px(out, sc))
		farR.Position, farR.Size = UDim2.new(1, 0, 0, f), UDim2.new(0, f, 1, 0)
		farB.Position, farB.Size = UDim2.new(0, f, 1, 0), UDim2.new(1, -f, 0, f)
		nearR.Position, nearR.Size = UDim2.new(1, 0, 0, n), UDim2.new(0, n, 1, 0)
		nearB.Position, nearB.Size = UDim2.new(0, n, 1, 0), UDim2.new(1, -n, 0, n)
		h.Visible = h:GetAttribute("FinishOff") ~= true and not (block and noShadow(obj, sc))
	end)
	return h
end

-- the stone body sunk under its frame: a StoneLip band Finish.Sink px along its top and left (SinkT, SinkL), the WellEdge
-- hairline at its top (RimT, RimL), a lit Tile line Finish.RimLit px down its right edge (LitR), and the carved line where
-- frame and body meet, Finish.Line px just outside it (LineT / LineL WoodDark, LineB / LineR WoodLight)
function SignKit.Carve(body)
	local h = holderOf(body, "FinishCarve", "Carve")
	local p = {}
	for _, d in ipairs({ { "LineT", Sign.WoodDark }, { "LineL", Sign.WoodDark }, { "LineB", Sign.WoodLight }, { "LineR", Sign.WoodLight },
		{ "SinkT", Sign.StoneLip }, { "SinkL", Sign.StoneLip }, { "RimT", Sign.WellEdge }, { "RimL", Sign.WellEdge }, { "LitR", Sign.Tile } }) do
		p[d[1]] = strip(h, d[1], d[2])
	end
	SignKit.Whole(h, function(sc)
		local l, k, r = SignKit.Px(FIN.Line, sc), SignKit.Px(FIN.Sink, sc), SignKit.Px(FIN.RimLit, sc)
		cover(body, h, l)
		p.LineT.Position, p.LineT.Size = UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, l)
		p.LineL.Position, p.LineL.Size = UDim2.new(0, 0, 0, 0), UDim2.new(0, l, 1, 0)
		p.LineB.Position, p.LineB.Size = UDim2.new(0, 0, 1, -l), UDim2.new(1, 0, 0, l)
		p.LineR.Position, p.LineR.Size = UDim2.new(1, -l, 0, 0), UDim2.new(0, l, 1, 0)
		p.SinkT.Position, p.SinkT.Size = UDim2.fromOffset(l, l), UDim2.new(1, -2 * l, 0, k)
		p.SinkL.Position, p.SinkL.Size = UDim2.fromOffset(l, l), UDim2.new(0, k, 1, -2 * l)
		p.RimT.Position, p.RimT.Size = UDim2.fromOffset(l, l), UDim2.new(1, -2 * l, 0, l)
		p.RimL.Position, p.RimL.Size = UDim2.fromOffset(l, l), UDim2.new(0, l, 1, -2 * l)
		p.LitR.Position, p.LitR.Size = UDim2.new(1, -l - r, 0, l), UDim2.new(0, r, 1, -2 * l)
	end)
	return h
end

-- a raised face's lit top band: Finish.Shine px of the face (opts.Color; without it the face's own colour, followed as it
-- changes) toward white by Finish.ShineMix; opts.Px, opts.Mix, opts.Name / opts.Kind (a navy plate's NavyTop line:
-- SignKit.BandTop)
local FOLLOW = setmetatable({}, { __mode = "k" }) -- [face] = true: its shine follows its colour
function SignKit.Shine(face, opts)
	opts = opts or {}
	local name = opts.Name or "FinishShine"
	local s = face:FindFirstChild(name)
	if not s then
		s = fill(name, WHITE, { ZIndex = 0 }, face)
		s:SetAttribute("Finish", opts.Kind or "Shine")
	end
	local mix = tonumber(opts.Mix) or FIN.ShineMix
	local follow = typeof(opts.Color) ~= "Color3"
	s:SetAttribute("Follow", follow and mix or nil)
	if follow and not FOLLOW[face] then
		FOLLOW[face] = true
		face:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
			local x = face:FindFirstChild("FinishShine")
			local k = x and x:GetAttribute("Follow")
			if k then
				x.BackgroundColor3 = Theme.Mix(face.BackgroundColor3, WHITE, k)
			end
		end)
	end
	local base = follow and face.BackgroundColor3 or opts.Color
	s.BackgroundColor3 = Theme.Mix(base, WHITE, mix)
	s:SetAttribute("FinishOff", nil)
	s.Visible = true
	track(face, s)
	if finishless(face) then
		shed(face) -- (C2 / C3)
	end
	scaleWatch[s] = true
	local px = tonumber(opts.Px) or FIN.Shine
	SignKit.Whole(s, function(sc)
		local l, t, r = padOf(face)
		s.Position = UDim2.fromOffset(-l, -t)
		s.Size = UDim2.new(1, l + r, 0, SignKit.Px(px, sc))
	end)
	return s
end

-- a navy plate's / band's lit top line (FinishTop: NavyTop, Finish.Shine px)
function SignKit.BandTop(band)
	return SignKit.Shine(band, { Name = "FinishTop", Kind = "Top", Color = Sign.NavyTop, Mix = 0 })
end

-- a sunk well (a slot, an Off block): the shaded top and left band (ShadeT, ShadeL: Finish.WellShade px, the face toward
-- its edge by Finish.WellMix) and the lit bottom line (LitB: Finish.Line px). opts.Face / opts.Edge: the colours (default
-- the part's own colour / WellEdge)
function SignKit.Sunk(obj, opts)
	opts = opts or {}
	local h = holderOf(obj, "FinishSunk", "Sunk")
	local face = typeof(opts.Face) == "Color3" and opts.Face or obj.BackgroundColor3
	local edge = typeof(opts.Edge) == "Color3" and opts.Edge or Sign.WellEdge
	local shade = Theme.Mix(face, edge, FIN.WellMix)
	local t, l = strip(h, "ShadeT", shade), strip(h, "ShadeL", shade)
	local b = strip(h, "LitB", Theme.Mix(face, WHITE, FIN.WellLitMix))
	SignKit.Whole(h, function(sc)
		local k, one = SignKit.Px(FIN.WellShade, sc), SignKit.Px(FIN.Line, sc)
		cover(obj, h, 0)
		t.Position, t.Size = UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, k)
		l.Position, l.Size = UDim2.new(0, 0, 0, 0), UDim2.new(0, k, 1, 0)
		b.Position, b.Size = UDim2.new(0, 0, 1, -one), UDim2.new(1, 0, 0, one)
	end)
	return h
end

-- a raised kit block's whole finish in one call (CloudUI.SignBlock, SignKit.Plank, SignKit.Notice). opts: Face (the
-- object whose top shines, default obj), FaceColor, Out (its edge stroke's design px outside the box), Wood (false: an
-- ink / gold edge takes no wood light), Well (a sunk well instead: no light, no shine, no shadow), Shadow (false: none)
function SignKit.FinishBlock(obj, opts)
	opts = opts or {}
	local face = opts.Face or obj
	if opts.Well then
		hide(obj, "FinishBevel")
		hide(obj, "FinishShadow")
		hide(face, "FinishShine")
		SignKit.Sunk(face, { Face = opts.FaceColor, Edge = opts.EdgeColor })
		return
	end
	hide(face, "FinishSunk")
	if opts.Wood == false then
		hide(obj, "FinishBevel")
	else
		SignKit.Bevel(obj, { Px = FIN.Line, Out = opts.Out })
	end
	SignKit.Shine(face, { Color = opts.FaceColor })
	if opts.Shadow == false then
		hide(obj, "FinishShadow")
	else
		SignKit.Shadow(obj, { Px = FIN.Card, Out = opts.Out, Block = true })
	end
end

-- a window frame's whole finish (SignKit.Frame, CloudUI's Signboard panel and the windows that lay their own frame: the
-- Shop, the Gifts window, ...): the Finish.Bevel light on the wood, the window's shadow, the carved rim of its body (the
-- child stamped SignKit = "Body", or opts.Body)
function SignKit.FinishFrame(wood, opts)
	opts = opts or {}
	SignKit.Bevel(wood, { Px = FIN.Bevel })
	if opts.Shadow ~= false then
		SignKit.Shadow(wood, { Px = FIN.Window })
	end
	local body = opts.Body
	if not body then
		for _, c in ipairs(wood:GetChildren()) do
			if c:GetAttribute("SignKit") == "Body" then
				body = c
				break
			end
		end
	end
	if body then
		SignKit.Carve(body)
	end
end

-- (the open) the window rises Finish.Rise px to where it is now in Finish.RiseSteps hard steps, Finish.RiseStep s apart:
-- no easing, no scale bounce. Called again mid-rise it starts over from the same rest; a layout that moves the window
-- mid-rise wins (the rise stops where the layout put it)
local RISE = setmetatable({}, { __mode = "k" })
local function samePos(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
function SignKit.Rise(obj)
	if not (obj and obj:IsA("GuiObject")) then
		return
	end
	local run = RISE[obj]
	local rest = (run and run.at and samePos(obj.Position, run.at)) and run.rest or obj.Position
	local steps = math.max(1, math.floor(FIN.RiseSteps))
	run = { rest = rest }
	RISE[obj] = run
	local function at(k)
		local sc = SignKit.LayoutScale(obj)
		local p = UDim2.new(rest.X.Scale, rest.X.Offset, rest.Y.Scale, rest.Y.Offset + SignKit.Px(FIN.Rise * k / steps, sc))
		obj.Position = p
		run.at = p
	end
	local function step(k)
		if RISE[obj] ~= run then
			return
		end
		if not samePos(obj.Position, run.at) then
			RISE[obj] = nil
			return
		end
		if k <= 0 then
			obj.Position = rest
			RISE[obj] = nil
			return
		end
		at(k)
		task.delay(FIN.RiseStep, step, k - 1)
	end
	at(steps)
	task.delay(FIN.RiseStep, step, steps - 1)
end

-- the press's one darker frame: the face (Frame) shows Finish.PressDark darker for Finish.PressFrame s, then its colour
-- again (unless something repainted it meanwhile)
function SignKit.PressFrame(face)
	if not (face and face:IsA("GuiObject")) then
		return
	end
	local rest = face.BackgroundColor3
	local dark = Theme.Darken(rest, FIN.PressDark)
	face.BackgroundColor3 = dark
	task.delay(FIN.PressFrame, function()
		if same(face.BackgroundColor3, dark) then
			face.BackgroundColor3 = rest
		end
	end)
end

----------------------------------------------------------------------
-- scroll bar
----------------------------------------------------------------------

-- (U9-7 look) every kit B list's bar: Sizes.ScrollBar thick, opaque, in the wood, and square at both ends. Roblox's own
-- top / bottom images are round caps (a smooth capsule beside the square planks, a brown pill when the thumb is short):
-- all three parts take the built-in middle piece, so the bar is a plain block (no upload). opts: Thickness, Color.
-- Returns the ScrollingFrame.
SignKit.ScrollImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
function SignKit.ScrollBar(scroll, opts)
	opts = opts or {}
	scroll.ScrollBarThickness = tonumber(opts.Thickness) or Z.ScrollBar
	scroll.ScrollBarImageColor3 = opts.Color or Sign.Wood
	scroll.ScrollBarImageTransparency = 0
	scroll.TopImage = SignKit.ScrollImage
	scroll.MidImage = SignKit.ScrollImage
	scroll.BottomImage = SignKit.ScrollImage
	scroll:SetAttribute("SignBar", true)
	return scroll
end

----------------------------------------------------------------------
-- roof
----------------------------------------------------------------------

-- the Credits gable: two tilted slopes (their lower parts hide behind the header), a darker fascia board and a round vent
local function gable(roof, opts, w, h)
	local slopeT = opts.Slope or 52
	local halfW = w / 2
	local theta = math.atan2(h, halfW)
	local len = math.sqrt(halfW * halfW + h * h)
	-- the slope's top edge runs eave -> ridge; its centre sits half a thickness below that edge's middle
	local nx, ny = math.sin(theta), math.cos(theta)
	local cx, cy = halfW / 2 + nx * slopeT / 2, h / 2 + ny * slopeT / 2
	for _, side in ipairs({ { "SlopeL", cx, -1 }, { "SlopeR", w - cx, 1 } }) do
		fill(side[1], opts.Color or Sign.Roof, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(side[2], cy),
			Size = UDim2.fromOffset(len + 1, slopeT),
			Rotation = side[3] * math.deg(theta),
			ZIndex = 1,
		}, roof)
	end
	fill("Fascia", opts.Shade or Sign.RoofLip, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(w + 16, opts.Fascia or 9),
		ZIndex = 2,
	}, roof)
	local vent = fill("Vent", opts.Vent or Sign.Stone, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(halfW, math.floor(h * 0.52)),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = 3,
	}, roof)
	round(vent)
	vent:SetAttribute("Art", "gable vent") -- (kit-b gate U9 round 3) the Credits gable's round vent: the drawn roof's own detail
	line(vent, opts.VentEdge or Sign.Wood, 2)
end

-- opts: Width, Height (fixed design px), Y, Shape ("Flat" | "Gable"), Color, Edge (border colour), Lip (lip colour),
-- EdgePx, LipPx; gable: Slope, Fascia, Shade, Vent, VentEdge
-- (LOOK-ui2: the Training Place, Fusion and the pet picker drew a bare gold icon on their hand-laid navy plank, Pets, My
-- Home, Battle Arena and the Food Machine put it in the gold square) SignKit.Header's IconSlot on a label a window lays out
-- itself: the gold square in a 2 px ink line, the pixel icon `name` in the ink at `px` (27 on a PC header, 18 on a phone's:
-- the kit's two icon sizes). Call again for a new icon or size; a nil name keeps the one it shows
function SignKit.IconSlot(host, name, px)
	host.BackgroundTransparency = 0
	host.BackgroundColor3 = Sign.Gold
	host.BorderSizePixel = 0
	host.Text = ""
	if not host:FindFirstChild("SlotLine") then
		line(host, Sign.Text, 2).Name = "SlotLine"
	end
	name = name or host:GetAttribute("SlotIcon")
	px = px or host:GetAttribute("SlotPx") or 27
	if name and (host:GetAttribute("SlotIcon") ~= name or host:GetAttribute("SlotPx") ~= px) then
		host:SetAttribute("SlotIcon", name)
		host:SetAttribute("SlotPx", px)
		PixelIcon.Host(host, name, px, Sign.Text)
	end
	return host
end

function SignKit.Roof(parent, opts)
	opts = opts or {}
	local w = tonumber(opts.Width) or Z.RoofW
	local h = tonumber(opts.Height) or Z.RoofH
	local roof = frame("Roof", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, tonumber(opts.Y) or 0),
		Size = UDim2.fromOffset(w, h),
	}, parent)
	if opts.Shape == "Gable" then
		gable(roof, opts, w, h)
	else
		local e = tonumber(opts.EdgePx) or Z.RoofEdge
		local lipPx = tonumber(opts.LipPx) or Z.RoofLip
		roof.BackgroundTransparency = 0
		roof.BackgroundColor3 = opts.Edge or Sign.RoofEdge
		local face = fill("Face", opts.Color or Sign.Roof, {
			Position = UDim2.fromOffset(e, e),
			Size = UDim2.new(1, -2 * e, 1, -2 * e),
		}, roof)
		inset(face, e)
		lipOf(fill("Lip", opts.Lip or Sign.RoofLip, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, lipPx),
		}, face), lipPx)
		-- (U9-8 look) the sprite itself whole screen px under the window's scale (was 14.4 px high at 0.8); its border
		-- and its lip snap through inset / lipOf (LOOK-ui)
		SignKit.Whole(roof, function(sc)
			roof.Size = UDim2.fromOffset(SignKit.Px(w, sc), SignKit.Px(h, sc))
		end)
		if opts.Finish ~= false then
			SignKit.Awning(roof, w, h, opts)
		end
	end
	return place(roof, opts, "Roof")
end

-- (Pitch 2 F0, the owner's pick A: "a striped scalloped awning seated on the frame on two wood end brackets"; the flat
-- awning floated half over the frame like a stray bar) the flat roof's trim, in its holder FinishTrim (attribute Finish =
-- "Awning") over the roof's face: cream stripes every other AwningSizes.Band px, the pink's lit top line, a scalloped
-- valance (one tab per band, its edge, face, shade and rounded tip) hanging AwningSizes.Hang px under the roof's box over
-- the frame's top rim, and a wood bracket at each end holding it to the frame. The roof's box (its size, its place) is
-- unchanged
SignKit.AwningSizes = { Band = 24, Hang = 8, Bracket = 8 }

-- (look review of finish pass A, major 1: the awning hung into the header band, its scallops over the Gifts window's Play
-- time tab, the Index's title and the phone's GIFTS) where a window's awning goes: the Y (design px) that puts its box
-- over the window's top edge `frameTop` (default 0) so that only its valance hangs over the frame, ending on the wood
-- rim (Sizes.Rim): the awning sits ON the frame (the mock: F0_*_optA.png), never over the header's tabs, title or close
function SignKit.RoofSeat(frameTop)
	return (tonumber(frameTop) or 0) - (Z.RoofH + SignKit.AwningSizes.Hang - Z.Rim)
end
local AWNING = setmetatable({}, { __mode = "k" }) -- [roof] = the "w x h" its trim was built for
function SignKit.Awning(roof, w, h)
	local A = SignKit.AwningSizes
	-- a window that resizes its roof (the Gifts window's phone awning) gets the trim again at the new width (design px:
	-- the size it set, or the whole-px size SignKit.Whole gave it)
	if AWNING[roof] == nil then
		roof:GetPropertyChangedSignal("Size"):Connect(function()
			local sc = SignKit.LayoutScale(roof)
			local nw = math.floor(roof.Size.X.Offset + 0.5)
			local built = AWNING[roof]
			if built and roof:FindFirstChild("FinishTrim") and math.abs(nw - built[1]) > math.max(1, 1 / sc) then
				SignKit.Awning(roof, nw, built[2])
			end
		end)
	end
	AWNING[roof] = { w, h }
	local t = roof:FindFirstChild("FinishTrim")
	if t then
		t:Destroy()
	end
	t = frame("FinishTrim", { ZIndex = 2, Size = UDim2.fromScale(1, 1) }, roof)
	t:SetAttribute("Finish", "Awning")
	local e = Z.RoofEdge
	local bands = {}
	local x = e
	local n = 0
	while x < w - e do
		n = n + 1
		bands[n] = { x, math.min(A.Band, w - e - x) }
		x = x + A.Band
	end
	local function box(name, colour, x0, y0, bw, bh)
		local f = fill(name, colour, { ZIndex = 2 }, t)
		f:SetAttribute("At", Vector2.new(x0, y0))
		f:SetAttribute("Box", Vector2.new(bw, bh))
		return f
	end
	for i, b in ipairs(bands) do
		if i % 2 == 0 then
			box("Stripe" .. i, Sign.Stone, b[1], e, b[2], h - 2 * e)
		end
	end
	box("TopLight", Theme.Mix(Sign.Roof, WHITE, 0.45), e, e, w - 2 * e, 2)
	for i, b in ipairs(bands) do
		local cream = i % 2 == 0
		local faceC = cream and Sign.Stone or Sign.Roof
		local shade = cream and Sign.StoneLip or Sign.RoofLip
		local bx, bw = b[1], b[2]
		box("Tab" .. i, Sign.RoofEdge, bx, h - 4, bw, 10)
		box("TabFace" .. i, faceC, bx + 2, h - 4, math.max(1, bw - 4), 8)
		box("TabShade" .. i, shade, bx + 2, h + 2, math.max(1, bw - 4), 2)
		if bw > 8 then
			box("TabTip" .. i, Sign.RoofEdge, bx + 4, h + 6, bw - 8, 2)
		end
		if bw > 12 then
			box("TabTipShade" .. i, shade, bx + 6, h + 4, bw - 12, 2)
		end
	end
	for _, side in ipairs({ { "BracketL", -A.Bracket }, { "BracketR", w } }) do
		box(side[1], Sign.WoodDark, side[2], -2, A.Bracket, h + 2 + A.Hang)
		box(side[1] .. "Wood", Sign.Wood, side[2] + 1, -1, A.Bracket - 2, h + A.Hang)
		box(side[1] .. "Lit", Sign.WoodLight, side[2] + 1, -1, A.Bracket - 2, 2)
	end
	-- every piece on whole screen px under the window's scale: its two edges each snapped
	scaleWatch[t] = true
	SignKit.Whole(t, function(sc)
		for _, f in ipairs(t:GetChildren()) do
			local at, sz = f:GetAttribute("At"), f:GetAttribute("Box")
			if at and sz then
				local x0, y0 = SignKit.Px(math.abs(at.X), sc) * (at.X < 0 and -1 or 1), SignKit.Px(math.abs(at.Y), sc) * (at.Y < 0 and -1 or 1)
				local x1, y1 = SignKit.Px(math.abs(at.X + sz.X), sc) * ((at.X + sz.X) < 0 and -1 or 1), SignKit.Px(at.Y + sz.Y, sc)
				f.Position = UDim2.fromOffset(x0, y0)
				f.Size = UDim2.fromOffset(math.max(SignKit.Px(1, sc), x1 - x0), math.max(SignKit.Px(1, sc), y1 - y0))
			end
		end
	end)
	return t
end

----------------------------------------------------------------------
-- header, frame, body
----------------------------------------------------------------------

-- (render gate, GATE_KITB; Pitch 2 F0 A, look review of finish pass A major 3) how far a Ribbon header's plate reaches
-- past the frame: 0. The finish's shared rule is "header bands inside the frame" (the mock keeps the plate at
-- x+6 .. x+w-6); the T1 band out over the frame with its dark notched tails is gone
SignKit.HeaderBand = { Over = 0 }

-- the plate inside the rim (every header: the F0 rule); SignKit.HeaderOverhang
local function placePlate(head, on)
	local plate = head:FindFirstChild("Plate")
	local rim = head:GetAttribute("Rim") or Z.Rim
	on = false -- (F0 A) never out over the frame
	local over = 0
	if not plate then
		return
	end
	-- the plate's own parts (the icon square, the title) keep their place on the screen when the plate moves
	local delta = (on and -over or rim) - plate.Position.X.Offset
	if delta ~= 0 then
		for _, c in ipairs(plate:GetChildren()) do
			if c:IsA("GuiObject") and c:GetAttribute("Ribbon") == nil then
				local p, s = c.Position, c.Size
				c.Position = UDim2.new(p.X.Scale, p.X.Offset - delta, p.Y.Scale, p.Y.Offset)
				if s.X.Scale == 1 then
					c.Size = UDim2.new(1, s.X.Offset + delta, s.Y.Scale, s.Y.Offset)
				end
			end
		end
	end
	plate.Position = UDim2.fromOffset(on and -over or rim, rim)
	plate.Size = UDim2.new(1, on and 2 * over or -2 * rim, 1, -rim)
	for _, side in ipairs({ "TailL", "TailR" }) do
		local tail = head:FindFirstChild(side)
		if tail then
			tail.Visible = on
		end
	end
	head:SetAttribute("Overhang", on)
end

-- (render gate) a Ribbon header's band out over the frame (on) or inside the rim (off). (Pitch 2 F0 A) both keep it inside
-- the rim with no tails now ("header bands inside the frame"); the callers keep calling it. The title does not move
function SignKit.HeaderOverhang(head, on)
	if head and head:GetAttribute("Ribbon") then
		placePlate(head, on == true)
	end
end

-- opts: Title, TitleRole ("Title"), TitleSize, TitleColor (gold), Drop (a Color3: a drop line 3 px under the title),
-- TitleX, Reserve (px kept free on the right, e.g. for a close X), Y, Height, Rim, RimColor (wood), Color (navy),
-- IconSlot (a gold square left of the title for a PixelIcon), Ribbon (the untabbed window's header: the plate stays
-- inside the rim, Pitch 2 F0 A; the title wears its own gold V-notched ribbon, RibbonBand = "Header")
function SignKit.Header(parent, opts)
	opts = opts or {}
	local rim = tonumber(opts.Rim) or Z.Rim
	local role = opts.TitleRole or "Title"
	local ribbon = opts.Ribbon == true and role == "Title"
	local shift = 0 -- (F0 A) the plate starts at the rim: nothing moves in
	local head = fill("Head", opts.RimColor or Sign.Wood, {
		Position = UDim2.fromOffset(0, tonumber(opts.Y) or 0),
		Size = UDim2.new(1, 0, 0, tonumber(opts.Height) or Z.HeadH),
		Active = true,
	}, parent)
	head:SetAttribute("Rim", rim)
	local plate = fill("Plate", opts.Color or Sign.Navy, {
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 1, -rim),
	}, head)
	local size = tonumber(opts.TitleSize) or Theme.RoleSize(role)
	if ribbon then
		-- (Pitch 2 F0 A) no tails on the head: the plate stays inside the rim, the title's own ribbon carries the V tails
		head:SetAttribute("Ribbon", true)
		placePlate(head, false)
	end
	local x = (tonumber(opts.TitleX) or Z.TitleX) + shift
	if opts.IconSlot then
		local slot = fill("IconSlot", Sign.Gold, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12 + shift, 0.5, 0),
			Size = UDim2.fromOffset(Z.IconSlot, Z.IconSlot),
			ZIndex = 2, -- over the band's pipings
		}, plate)
		line(slot, Sign.Text, 2)
		x = 12 + Z.IconSlot + 12 + shift
	end
	local box = UDim2.new(1, -(x + (tonumber(opts.Reserve) or 0) + shift), 1, 0)
	if opts.Drop then
		text("TitleDrop", opts.Title, role, size, opts.Drop, {
			Position = UDim2.fromOffset(x, 3),
			Size = box,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 1,
		}, plate)
	end
	local title = text("Title", opts.Title, role, size, opts.TitleColor or Sign.Gold, {
		Position = UDim2.fromOffset(x, 0),
		Size = box,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	}, plate)
	if role == "Title" then
		if ribbon then
			title:SetAttribute("RibbonBand", "Header") -- the plate is its band
		end
		Theme.StyleTitle(title) -- (T0) the one title treatment; the Credits' Sign role keeps its approved look
	end
	place(head, opts, "Header")
	-- (U9-8 look) the rim whole screen px under the window's scale (the same rule as the frame's, so the two still match)
	SignKit.Whole(head, function(sc)
		head:SetAttribute("Rim", SignKit.Px(rim, sc))
		placePlate(head, head:GetAttribute("Overhang") == true)
	end)
	if opts.Finish ~= false then
		-- (Pitch 2 F0) the rim carries the frame's light (lit top and left, shaded right: the frame below closes it), the
		-- navy plate its lit top line
		SignKit.Bevel(head, { Px = FIN.Bevel, Sides = "TLR" })
		SignKit.BandTop(plate)
	end
	return head, plate
end

-- opts: Y, Height (nil = down to the parent's bottom), Color (wood), Finish (false: no finish, the approved Credits)
function SignKit.Frame(parent, opts)
	opts = opts or {}
	local y = tonumber(opts.Y) or 0
	local h = tonumber(opts.Height)
	local wood = fill("Wood", opts.Color or Sign.Wood, {
		Position = UDim2.fromOffset(0, y),
		Size = h and UDim2.new(1, 0, 0, h) or UDim2.new(1, 0, 1, -y),
		Active = true,
	}, parent)
	place(wood, opts, "Frame")
	if opts.Finish ~= false then
		-- (Pitch 2 F0) the frame's light and the window's shadow (its body, added next, carves itself)
		SignKit.Bevel(wood, { Px = FIN.Bevel })
		SignKit.Shadow(wood, { Px = FIN.Window })
	end
	return wood
end

-- opts: Inset (the frame's width), Color (stone), Lip (px; 0 = none), LipColor, Line = { Inset, Thickness, Color } (an
-- inner line drawn as a Border stroke)
function SignKit.Body(parentFrame, opts)
	opts = opts or {}
	local inset = tonumber(opts.Inset) or Z.Frame
	local body = fill("Body", opts.Color or Sign.Stone, {
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
	}, parentFrame)
	local lip = tonumber(opts.Lip) or Z.Lip
	local lipFrame = nil
	if lip > 0 then
		lipFrame = lipOf(fill("Lip", opts.LipColor or Sign.StoneLip, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, lip),
		}, body), lip)
	end
	-- (U9-8 look) the wood frame round it and its lip whole screen px under the window's scale
	SignKit.Whole(body, function(sc)
		local i = SignKit.Px(inset, sc)
		body.Position = UDim2.fromOffset(i, i)
		body.Size = UDim2.new(1, -2 * i, 1, -2 * i)
		if lipFrame then
			lipFrame.Size = UDim2.new(1, 0, 0, SignKit.Px(lip, sc))
		end
	end)
	if type(opts.Line) == "table" then
		local li = tonumber(opts.Line.Inset) or 5
		local ln = frame("Line", {
			Position = UDim2.fromOffset(li, li),
			Size = UDim2.new(1, -2 * li, 1, -2 * li),
			ZIndex = 1,
		}, body)
		line(ln, opts.Line.Color or Sign.StoneLip, tonumber(opts.Line.Thickness) or 3)
	end
	place(body, opts, "Body")
	if opts.Finish ~= false then
		SignKit.Carve(body) -- (Pitch 2 F0) sunk under the frame, the carved rim
	end
	return body
end

----------------------------------------------------------------------
-- plank (button)
----------------------------------------------------------------------

-- the block offset and the lip a state shows (the plank and the block keep their size): hover lifts the block Hover px;
-- press sinks it Sink px and the face grows down over the lip until PressLip px of it shows (the pitch's .dn)
function SignKit.PlankState(plank, state)
	local block = plank and plank:FindFirstChild("Block")
	local face = block and block:FindFirstChild("Face")
	if not face then
		return
	end
	-- (U9-8 look) every size whole screen px under the window's scale
	local sc = SignKit.LayoutScale(plank)
	local e = SignKit.Px(plank:GetAttribute("EdgePx") or Z.Edge, sc)
	local lip = SignKit.Px(plank:GetAttribute("LipPx") or Z.Lip, sc)
	if plank:GetAttribute("Off") then
		state = "Rest"
	end
	if state ~= "Hover" and state ~= "Press" then
		state = "Rest"
	end
	if state == "Press" and plank:GetAttribute("PlankState") ~= "Press" then
		SignKit.PressFrame(face) -- (Pitch 2 F0) the press: one darker frame, then the sink
	end
	local shown = state == "Press" and math.min(lip, SignKit.Px(Z.PressLip, sc)) or lip
	block.Position = UDim2.fromOffset(0, (state == "Hover" and -SignKit.Px(Z.Hover, sc)) or (state == "Press" and SignKit.Px(Z.Sink, sc)) or 0)
	face.Position = UDim2.fromOffset(e, e)
	face.Size = UDim2.new(1, -2 * e, 1, -(2 * e + shown))
	local under = block:FindFirstChild("Lip")
	if under then
		under.Position = UDim2.fromOffset(e, e)
		under.Size = UDim2.new(1, -2 * e, 1, -2 * e)
	end
	plank:SetAttribute("PlankState", state)
end

-- the label's size: `size` stepped down until the text fits `room` px (Theme.Measure, Button role), never under 14
local function fitSize(textValue, size, room)
	while size > 14 do
		local ok, m = pcall(Theme.Measure, textValue, "Button", size)
		if not ok or not m or m.X <= room then
			break
		end
		size = size - 1
	end
	return size
end
SignKit.FitSize = fitSize -- (U5 review) for a caller that lays its own icon beside the label (MainMenuController)

-- opts: Text, Style (SignKit.Styles name, default Stone), Width, Height, TextSize (stepped down to fit the face, then the
-- label truncates), Face / Lip / Edge / TextColor overrides, LipPx (the lip's height, default Sizes.Lip), IconSlot (a
-- square left of the label for a PixelIcon), Callback (on Activated). Style Off is disabled: not Active, not Selectable,
-- no callback, it never moves
function SignKit.Plank(parent, opts)
	opts = opts or {}
	local look = SignKit.Styles[opts.Style or "Stone"] or SignKit.Styles.Stone
	local w = tonumber(opts.Width) or 160
	local h = tonumber(opts.Height) or Z.PlankH
	local e, lip = Z.Edge, tonumber(opts.LipPx) or Z.Lip
	local plank = Instance.new("TextButton")
	plank.Name = "Plank"
	plank.Text = ""
	plank.AutoButtonColor = false
	plank.BackgroundTransparency = 1
	plank.BorderSizePixel = 0
	plank.Size = UDim2.fromOffset(w, h)
	plank.Active = not look.Off
	plank.Selectable = not look.Off
	plank:SetAttribute("EdgePx", e)
	plank:SetAttribute("LipPx", lip)
	if look.Off then
		plank:SetAttribute("Off", true)
	end
	local block = fill("Block", opts.Edge or look.Edge, { Size = UDim2.fromScale(1, 1) }, plank)
	fill("Lip", opts.Lip or look.Lip, {
		Position = UDim2.fromOffset(e, e),
		Size = UDim2.new(1, -2 * e, 1, -2 * e),
	}, block)
	local face = fill("Face", opts.Face or look.Face, {
		Position = UDim2.fromOffset(e, e),
		Size = UDim2.new(1, -2 * e, 1, -(2 * e + lip)),
		ZIndex = 2,
	}, block)
	local x = 0
	if opts.IconSlot then
		local px = h - 2 * e - lip - 8
		frame("IconSlot", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(px, px),
			ZIndex = 3,
		}, face)
		x = 10 + px
	end
	local room = w - 2 * e - x - 2 * Z.LabelPad
	text("Label", opts.Text, "Button", fitSize(tostring(opts.Text or ""), tonumber(opts.TextSize) or 22, room), opts.TextColor or look.Text, {
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(1, -x, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	}, face)
	plank.MouseEnter:Connect(function()
		SignKit.PlankState(plank, "Hover")
	end)
	plank.MouseLeave:Connect(function()
		SignKit.PlankState(plank, "Rest")
	end)
	plank.MouseButton1Down:Connect(function()
		SignKit.PlankState(plank, "Press")
	end)
	plank.MouseButton1Up:Connect(function()
		SignKit.PlankState(plank, plank:GetAttribute("PlankState") == "Press" and "Hover" or "Rest")
	end)
	-- a finger that lifts never produces MouseLeave (nor MouseButton1Up once it slid off)
	plank.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			SignKit.PlankState(plank, "Rest")
		end
	end)
	if type(opts.Callback) == "function" and not look.Off then
		plank.Activated:Connect(opts.Callback)
	end
	if opts.Finish ~= false then
		-- (Pitch 2 F0) an Off plank is a sunk well; a raised one has the light on its wood edge, the face's lit top band and
		-- the card shadow (none under an ink-edged close block)
		local edge = opts.Edge or look.Edge
		if look.Off then
			SignKit.Sunk(face, { Face = opts.Face or look.Face, Edge = edge })
		else
			if same(edge, Sign.Wood) then
				SignKit.Bevel(block, { Px = FIN.Line })
			end
			SignKit.Shine(face)
			if not same(edge, Sign.Text) then
				SignKit.Shadow(plank, { Px = FIN.Card, Block = true })
			end
		end
	end
	plank.Parent = parent
	-- (U9-8 look) drawn again in whole screen px whenever it moves or the window's scale changes
	SignKit.Whole(plank, function()
		SignKit.PlankState(plank, plank:GetAttribute("PlankState") or "Rest")
	end)
	return place(plank, opts, "Plank")
end

----------------------------------------------------------------------
-- rope, block row, notice
----------------------------------------------------------------------

-- opts: Length, Width, Color (post), Shade (wood: its shaded side)
function SignKit.Rope(parent, opts)
	opts = opts or {}
	local w = tonumber(opts.Width) or Z.RopeW
	local rope = fill("Rope", opts.Color or Sign.Post, { Size = UDim2.fromOffset(w, tonumber(opts.Length) or 60) }, parent)
	fill("Shade", opts.Shade or Sign.Wood, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, math.max(1, math.floor(w / 3)), 1, 0),
	}, rope)
	return place(rope, opts, "Rope")
end

-- opts: Count, BlockW, BlockH, Gap, (U9-7 look) LipPx (the lip under each face: Sizes.BlockLip; a small block keeps its
-- face about three quarters of its height, as the loading bar's), EdgePx (Sizes.BlockEdge), Fill / FillLip (the lit
-- blocks' face and lip: gold by default; a role colour, e.g. a boss's health in red)
local BLOCK_FILL = setmetatable({}, { __mode = "k" }) -- [row] = { face, lip }
function SignKit.BlockRow(parent, opts)
	opts = opts or {}
	local n = math.max(1, math.floor(tonumber(opts.Count) or 12))
	local bw, bh = tonumber(opts.BlockW) or Z.BlockW, tonumber(opts.BlockH) or Z.BlockH
	local gap = tonumber(opts.Gap) or Z.BlockGap
	local e = tonumber(opts.EdgePx) or Z.BlockEdge
	local lipPx = tonumber(opts.LipPx) or Z.BlockLip
	local row = frame("BlockRow", { Size = UDim2.fromOffset(n * bw + (n - 1) * gap, bh) }, parent)
	row:SetAttribute("Count", n)
	row:SetAttribute("LipPx", lipPx)
	BLOCK_FILL[row] = { typeof(opts.Fill) == "Color3" and opts.Fill or Sign.Gold, typeof(opts.FillLip) == "Color3" and opts.FillLip or Sign.GoldLip }
	for i = 1, n do
		local b = fill("Block" .. i, Sign.Wood, {
			Position = UDim2.fromOffset((i - 1) * (bw + gap), 0),
			Size = UDim2.fromOffset(bw, bh),
		}, row)
		local face = fill("Face", Sign.Stone, {
			Position = UDim2.fromOffset(e, e),
			Size = UDim2.new(1, -2 * e, 1, -2 * e),
		}, b)
		inset(face, e)
		lipOf(fill("Lip", Sign.StoneLip, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, lipPx),
		}, face), lipPx)
	end
	-- (U9-8 look) each block's wood edge and lip whole screen px under the scale above the row (the blocks keep their
	-- design widths, so no window's layout moves)
	SignKit.Whole(row, function(sc)
		local ew, lw = SignKit.Px(e, sc), SignKit.Px(lipPx, sc)
		for i = 1, n do
			local b = row:FindFirstChild("Block" .. i)
			local face = b and b:FindFirstChild("Face")
			if face then
				face.Position = UDim2.fromOffset(ew, ew)
				face.Size = UDim2.new(1, -2 * ew, 1, -2 * ew)
				local lip = face:FindFirstChild("Lip")
				if lip then
					lip.Size = UDim2.new(1, 0, 0, lw)
				end
			end
		end
	end)
	place(row, opts, "BlockRow")
	SignKit.FillBlocks(row, 0)
	return row
end

-- (LOOK-ui, kitb-look1: the owner's look bar 2026-11-17, "every bar in the block-bar language") a BlockRow that fills its
-- own box, for a bar laid out by the screen (opts Size / Position / AnchorPoint, Scale allowed): Count blocks sharing its
-- width (each 1/Count of it less its share of the gaps: it fits whatever the box becomes, a block's edge and lip stay on
-- whole screen px). opts: Count, Gap (2), EdgePx (2), LipPx (3), Fill / FillLip, Size, Position, AnchorPoint, ZIndex,
-- Name. SignKit.FillBlocks lights it; SignKit.SetBlockCount changes Count
local function fitBlock(row, i, e, lipPx)
	local b = fill("Block" .. i, Sign.Wood, { Size = UDim2.new(0, 0, 1, 0) }, row)
	local face = fill("Face", Sign.Stone, {
		Position = UDim2.fromOffset(e, e),
		Size = UDim2.new(1, -2 * e, 1, -2 * e),
	}, b)
	inset(face, e)
	lipOf(fill("Lip", Sign.StoneLip, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, lipPx),
	}, face), lipPx)
	return b
end

-- (LOOK-ui, kitb-look1: blocks laid as shares of the row were fractional at every size, 11.67 px with a 7.67 px face at
-- 1080p, a 2 px smudge on a phone) laid out in whole screen px from the row's AbsoluteSize: every block w = floor((rowW -
-- (n - 1) x gap) / n) wide, block i at i x (w + gap), the spare px left at the row's end, the height whole; again when
-- the row's size or scale changes. A block whose face would be under 4 px drops its edge (an edgeless pip on its 2 px
-- lip). Before the first layout (no size yet) the shares stand in
local MIN_FACE = 4
local function layFit(row)
	local n = row:GetAttribute("Count") or 0
	if n < 1 then
		return
	end
	local gap = row:GetAttribute("Gap") or 2
	local abs = row.AbsoluteSize
	local s = PixelIcon.RestScale(row)
	if abs.X < 1 or abs.Y < 1 or s <= 0 then
		for i = 1, n do
			local b = row:FindFirstChild("Block" .. i)
			if b then
				b.Position = UDim2.new((i - 1) / n, (i - 1) * gap / n, 0, 0)
				b.Size = UDim2.new(1 / n, -(n - 1) * gap / n, 1, 0)
			end
		end
		return
	end
	local g = math.max(1, math.floor(gap * s + 0.5))
	local w = math.max(1, math.floor((math.floor(abs.X + 1e-6) - (n - 1) * g) / n))
	local h = math.max(1, math.floor(abs.Y + 1e-6))
	-- (kit-b gate U9 r4) the weight's edge and lip in whole screen px, never under its MinEdge / MinLip screen px; handed
	-- to WholeInset / WholeHeight as the design px that draw exactly that many
	local e = math.max(row:GetAttribute("MinEdge") or 1, math.max(1, math.floor((row:GetAttribute("EdgePx") or 2) * s + 0.5)))
	local lipScreen = math.max(row:GetAttribute("MinLip") or 1, math.max(1, math.floor((row:GetAttribute("LipPx") or 3) * s + 0.5)))
	local pip = w - 2 * e < MIN_FACE
	row:SetAttribute("Pips", pip)
	row:SetAttribute("BlockPx", w)
	-- each block is its share of the row plus the whole-px correction measured now: exact while the row keeps this size,
	-- and still inside the row if it changes before the next layout (the share follows it; a resize may not be signalled)
	local W, Hh = abs.X / s, abs.Y / s
	for i = 1, n do
		local b = row:FindFirstChild("Block" .. i)
		if b then
			b.Position = UDim2.new((i - 1) / n, (i - 1) * (w + g) / s - (i - 1) / n * W, 0, 0)
			b.Size = UDim2.new(1 / n, w / s - W / n, 1, h / s - Hh)
			b.BackgroundTransparency = pip and 1 or 0
			local face = b:FindFirstChild("Face")
			if face then
				PixelIcon.WholeInset(face, pip and 0 or e / s)
				local lip = face:FindFirstChild("Lip")
				if lip and pip then
					PixelIcon.WholeHeight(lip, 2)
				elseif lip then
					PixelIcon.WholeHeight(lip, lipScreen / s)
				end
			end
		end
	end
end

-- (kit-b gate U9 r4) opts.Weight "Bar" (default) or "Micro" (Sizes.Bar / Sizes.Micro): the row's edge, lip and min screen
-- px come from its weight only, its Gap is clamped into the weight's range (a caller's EdgePx / LipPx are not read)
function SignKit.FitBlocks(parent, opts)
	opts = opts or {}
	local weight = opts.Weight == "Micro" and "Micro" or "Bar"
	local wt = Z[weight]
	local row = frame("BlockRow", { Size = opts.Size or UDim2.new(1, 0, 0, Z.BlockH) }, parent)
	row:SetAttribute("Weight", weight)
	row:SetAttribute("Gap", math.max(wt.Gap, math.min(wt.GapMax, tonumber(opts.Gap) or wt.Gap)))
	row:SetAttribute("EdgePx", wt.Edge)
	row:SetAttribute("LipPx", wt.Lip)
	row:SetAttribute("MinEdge", wt.MinEdge)
	row:SetAttribute("MinLip", wt.MinLip)
	row:SetAttribute("Fit", true)
	BLOCK_FILL[row] = { typeof(opts.Fill) == "Color3" and opts.Fill or Sign.Gold, typeof(opts.FillLip) == "Color3" and opts.FillLip or Sign.GoldLip }
	place(row, opts, "BlockRow")
	SignKit.SetBlockCount(row, opts.Count)
	-- (LOOK-ui) whole screen px again whenever the row is laid out anew (a window resized, a Fit changed)
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layFit(row)
	end)
	return row
end

-- a FitBlocks row with `n` blocks (rebuilt; none lit); Fill / FillLip (optional) the lit colours from now on
function SignKit.SetBlockCount(row, n, fillColor, fillLip)
	n = math.max(1, math.floor(tonumber(n) or 10))
	if typeof(fillColor) == "Color3" then
		BLOCK_FILL[row] = { fillColor, typeof(fillLip) == "Color3" and fillLip or fillColor }
	end
	if row:GetAttribute("Count") ~= n or not row:FindFirstChild("Block1") then
		for _, c in ipairs(row:GetChildren()) do
			if c.Name:match("^Block%d+$") then
				c:Destroy()
			end
		end
		row:SetAttribute("Count", n)
		for i = 1, n do
			fitBlock(row, i, row:GetAttribute("EdgePx") or 2, row:GetAttribute("LipPx") or 3)
		end
	end
	layFit(row)
	SignKit.FillBlocks(row, 0)
	return row
end

-- the first k blocks lit (gold, or the row's Fill: face and lip), the rest stone; k is floored and clamped to 0..Count.
-- Returns k
function SignKit.FillBlocks(row, k)
	local n = row:GetAttribute("Count") or 0
	local lit = BLOCK_FILL[row] or { Sign.Gold, Sign.GoldLip }
	k = math.max(0, math.min(n, math.floor(tonumber(k) or 0)))
	for i = 1, n do
		local b = row:FindFirstChild("Block" .. i)
		local face = b and b:FindFirstChild("Face")
		if face then
			local on = i <= k
			face.BackgroundColor3 = on and lit[1] or Sign.Stone
			local lip = face:FindFirstChild("Lip")
			if lip then
				lip.BackgroundColor3 = on and lit[2] or Sign.StoneLip
			end
		end
	end
	row:SetAttribute("Filled", k)
	return k
end

-- (LOOK-ui, kitb-look1: the owner's look bar, one style across screens) the kit's one scroll bar: in the wood, opaque,
-- square ends (Roblox's round end caps swapped for its straight middle piece), Sizes.ScrollBar thick (`thickness`:
-- Sizes.ScrollBarPhone in a phone layout's list, 0 for none). Call again to change the thickness
-- (merge kitb-look1 x kitb-ui2: the two builds of the kit's one bar are one) SignKit.ScrollBar draws it, thickness in px
function SignKit.Scroll(sf, thickness)
	return SignKit.ScrollBar(sf, { Thickness = math.floor(tonumber(thickness) or Z.ScrollBar) })
end

-- opts: Width, Height, Text, TextSize, IconSlot (a square at the left for a PixelIcon)
function SignKit.Notice(parent, opts)
	opts = opts or {}
	local e = Z.NoticeEdge
	local notice = fill("Notice", Sign.Wood, {
		Size = UDim2.fromOffset(tonumber(opts.Width) or 360, tonumber(opts.Height) or 64),
	}, parent)
	local face = fill("Face", Sign.Stone, {
		Position = UDim2.fromOffset(e, e),
		Size = UDim2.new(1, -2 * e, 1, -2 * e),
	}, notice)
	inset(face, e)
	lipOf(fill("Lip", Sign.StoneLip, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, Z.NoticeLip),
	}, face), Z.NoticeLip)
	local x = 12
	if opts.IconSlot then
		local px = 30
		frame("IconSlot", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, -Z.NoticeLip / 2),
			Size = UDim2.fromOffset(px, px),
			ZIndex = 2,
		}, face)
		x = 10 + px + Z.NoticeGap -- (U5) the text keeps clear of the icon at the phones' 0.8 scale too
	end
	if opts.Text then
		text("Text", opts.Text, "Body", tonumber(opts.TextSize) or 18, Theme.TextOn("Stone"), {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -(x + 10), 1, -Z.NoticeLip),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
		}, face)
	end
	-- (U9-8 look) its wood edge and lip whole screen px under the scale above it
	local noticeLip = face:FindFirstChild("Lip")
	SignKit.Whole(notice, function(sc)
		local ew = SignKit.Px(e, sc)
		face.Position = UDim2.fromOffset(ew, ew)
		face.Size = UDim2.new(1, -2 * ew, 1, -2 * ew)
		if noticeLip then
			noticeLip.Size = UDim2.new(1, 0, 0, SignKit.Px(Z.NoticeLip, sc))
		end
	end)
	place(notice, opts, "Notice")
	if opts.Finish ~= false then
		-- (Pitch 2 F0) a floating card: the light on its wood edge, its face's lit top band, the card shadow
		SignKit.Bevel(notice, { Px = FIN.Line })
		SignKit.Shine(face)
		SignKit.Shadow(notice, { Px = FIN.Card, Block = true })
	end
	return notice, face
end

-- (Pitch 2 F0 A: "dotted pixel rules", "'ROBUX ITEMS' as a captioned rule"; the mock's sep "dots") a dotted rule: Dot x Dot
-- px dots every Pitch px in `opts.Color` (WellEdge) in a holder `opts.Width` design px wide and Dot tall (attribute SignKit
-- = "Rule", each dot Rule = "Dot"). SignKit.SetRule(rule, w) lays it again at a new width (dots reused)
SignKit.RuleSizes = { Dot = 2, Pitch = 6 }
function SignKit.SetRule(rule, w)
	local R = SignKit.RuleSizes
	w = math.max(0, math.floor((tonumber(w) or 0) + 0.5))
	local n = w >= R.Dot and math.floor((w - R.Dot) / R.Pitch) + 1 or 0
	local dots = {}
	for _, c in ipairs(rule:GetChildren()) do
		if c:GetAttribute("Rule") == "Dot" then
			dots[#dots + 1] = c
		end
	end
	local colour = rule:GetAttribute("RuleColor") or Sign.WellEdge
	for i = 1, math.max(n, #dots) do
		local d = dots[i]
		if i <= n then
			if not d then
				d = fill("Dot", colour, { ZIndex = rule.ZIndex }, rule)
				d:SetAttribute("Rule", "Dot")
			end
			d.Position = UDim2.fromOffset((i - 1) * R.Pitch, 0)
			d.Size = UDim2.fromOffset(R.Dot, R.Dot)
		elseif d then
			d:Destroy()
		end
	end
	rule.Size = UDim2.fromOffset(w, R.Dot)
	return rule
end

-- opts: Width, Color, Position, ZIndex, Name, Visible (the caller's placement, as every part's)
function SignKit.Rule(parent, opts)
	opts = opts or {}
	local rule = frame(opts.Name or "Rule", { ZIndex = tonumber(opts.ZIndex) or 1 }, parent)
	rule:SetAttribute("RuleColor", opts.Color or Sign.WellEdge)
	place(rule, opts, "Rule")
	return SignKit.SetRule(rule, opts.Width)
end

-- (kit-b U9-7, the owner's look bar 2026-11-17: small handmade touches that read as this game) two nail heads on a
-- hanging board's top corners, so a card that hangs on the screen is nailed up, not floating: plain WoodDark squares
-- (opts.Size design px, default 4) opts.Inset px in from the corner (default 6), above the board's face (opts.ZIndex,
-- default one over the board). Returns the two Frames (NailL, NailR; attribute SignKit = "Nail")
function SignKit.Nails(board, opts)
	opts = opts or {}
	local s = math.max(2, math.floor(tonumber(opts.Size) or 4))
	local inset = math.floor(tonumber(opts.Inset) or 6)
	local z = tonumber(opts.ZIndex) or (board.ZIndex + 1)
	local out = {}
	for i, side in ipairs({ 0, 1 }) do
		local nail = fill(i == 1 and "NailL" or "NailR", opts.Color or Sign.WoodDark, {
			AnchorPoint = Vector2.new(side, 0),
			Position = UDim2.new(side, (side == 0) and inset or -inset, 0, inset),
			Size = UDim2.fromOffset(s, s),
			ZIndex = z,
		}, board)
		nail:SetAttribute("SignKit", "Nail")
		-- (U9-8 look) the nail head and its inset whole screen px under the scale above the board (3.2 px at 0.8 before)
		SignKit.Whole(nail, function(sc)
			local at = SignKit.Px(inset, sc)
			nail.Position = UDim2.new(side, (side == 0) and at or -at, 0, at)
			nail.Size = UDim2.fromOffset(SignKit.Px(s, sc), SignKit.Px(s, sc))
		end)
		out[i] = nail
	end
	return out[1], out[2]
end

----------------------------------------------------------------------
-- the sky-climber's rig (sign/logo build: the owner's pick B2, .superpowers/sign-logo-pitch/FINAL_OPTIONS.md "BOARD")
----------------------------------------------------------------------

-- The pitch drew B2 on a 250 px board; every size here is its px times k = the board's width / 250, clamped 1 .. 2 (as the
-- Workshop trim before it). Positions along the board follow its real width.
SignKit.RigSizes = {
	Stripe = 26, -- the canopy's navy stripes ...
	Gap = 14, -- ... and the canvas between them
	Scallop = 20, -- the valance's scallops: 20 wide, dropping 8 in three steps, brass piping under each step
	Drop = 8,
	Pipe = 2,
	PatchW = 16, -- the stitched patch at x 176 of 250
	PatchH = 12,
	PatchAt = 176,
	Stitch = 3,
	Lash = 14, -- a corner lashing's square
	Twist = 6, -- the ropes' twist blocks
	CaraW = 12, -- the carabiner and its open gate
	CaraH = 18,
	Gate = 8,
	Eye = 10, -- the eye-bolt on the canopy's top edge
	Bar = 3, -- the iron's bar
	Prop = 22, -- a propeller's blade, hub and bracket, centred 6 in from each end of the board, 4 above it
	PropW = 6,
	Hub = 6,
	BracketW = 8,
	BracketH = 10,
	PropIn = 6,
	PropUp = 4,
	PlateW = 40, -- the brass version plate on the bottom rail: 13 above the board's foot to 3 below it
	PlateH = 16,
	PlateUp = 13,
	PlateText = 11,
	Hem = 3, -- the canvas body's hem and its 2 px lit top / left
	HemLit = 2,
	Bevel = 2, -- the frame's lit top / left edge, 3 for its shaded bottom / right
	Shade = 3,
	Flip = 0.5, -- the propellers' 2-frame flip
}
local RZ = SignKit.RigSizes

-- one rig piece: a flat Frame stamped SignKit = "Rig", Rig = its kind (Trim = the B2 trim it belongs to)
local function piece(kind, colour, props, parent, trim)
	local f = fill("Rig" .. kind, colour, props, parent)
	f:SetAttribute("SignKit", "Rig")
	f:SetAttribute("Rig", kind)
	if trim then
		f:SetAttribute("Trim", trim)
	end
	return f
end

local function clearRig(parent)
	for _, c in ipairs(parent:GetChildren()) do
		if c:GetAttribute("SignKit") == "Rig" then
			c:Destroy()
		end
	end
end

-- a ring of four iron bars (w x h, bar thick): the eye-bolt, and the carabiner with its open gate on the right
local function ironRing(kind, w, h, bar, colour, dark, gate, z, parent, trim)
	local ring = frame("Rig" .. kind, { Size = UDim2.fromOffset(w, h), ZIndex = z }, parent)
	ring:SetAttribute("SignKit", "Rig")
	ring:SetAttribute("Rig", kind)
	ring:SetAttribute("Trim", trim)
	fill("Top", colour, { Size = UDim2.fromOffset(w, bar), ZIndex = z }, ring)
	fill("Bottom", colour, { Position = UDim2.fromOffset(0, h - bar), Size = UDim2.fromOffset(w, bar), ZIndex = z }, ring)
	fill("Left", colour, { Size = UDim2.fromOffset(bar, h), ZIndex = z }, ring)
	if gate and gate > 0 then
		local top = math.floor((h - gate) / 2)
		fill("Right", dark, { Position = UDim2.fromOffset(w - bar, 0), Size = UDim2.fromOffset(bar, top), ZIndex = z }, ring)
		fill("Right", dark, { Position = UDim2.fromOffset(w - bar, top + gate), Size = UDim2.fromOffset(bar, h - top - gate), ZIndex = z }, ring)
	else
		fill("Right", dark, { Position = UDim2.fromOffset(w - bar, 0), Size = UDim2.fromOffset(bar, h), ZIndex = z }, ring)
	end
	return ring
end

-- the blades of every propeller under root: frame 1 level (wider than tall), 2 upright. A flip swaps the blade's size,
-- never a Rotation (a turned Frame goes soft)
function SignKit.PropFrame(root, n)
	for _, d in ipairs(root:GetDescendants()) do
		if d:GetAttribute("Rig") == "Blade" then
			local long, short = d:GetAttribute("Long"), d:GetAttribute("Short")
			if long and short then
				d.Size = n == 2 and UDim2.fromOffset(short, long) or UDim2.fromOffset(long, short)
			end
		end
	end
	root:SetAttribute("PropFrame", n == 2 and 2 or 1)
end

-- the propellers under root turn (flip every RigSizes.Flip s) while `on`, else rest level. Called again it restarts;
-- the loop ends when root leaves the game
function SignKit.Spin(root, on)
	local gen = (root:GetAttribute("RigSpin") or 0) + 1
	root:SetAttribute("RigSpin", gen)
	SignKit.PropFrame(root, 1)
	if not on then
		return
	end
	task.spawn(function()
		local n = 1
		while true do
			task.wait(RZ.Flip)
			if not root.Parent or root:GetAttribute("RigSpin") ~= gen then
				return
			end
			n = 3 - n
			SignKit.PropFrame(root, n)
		end
	end)
end

-- parts: Board (the board Frame: the ropes, roof, header and frame are laid out in it), Roof (a flat SignKit.Roof),
-- Head (the header), Frame (the wood frame round the body), Ropes (the board's ropes, siblings of the board in its
-- Swing). opts: Width (the board's design width; default the board's), Version ("V6": the brass plate's text; none = no
-- plate). B2 on those parts: the canopy (the roof's face weathered canvas under navy stripes, a navy edge, a scalloped
-- valance with brass piping), a stitched patch on it, the frame's bevel (a lit top / left edge, a shaded bottom / right),
-- rope lashings on its four corners, the canvas body's hem (no seams), the twisted ropes ending in carabiners clipped to
-- eye-bolts on the canopy's top edge, two propellers at the canopy's top corners, the brass version plate on the bottom
-- rail. The five trims (lashings, hang rig, propellers, plate, patch) are B2's limit. Flat Frames in Theme.Sign colours,
-- offset sizes (nothing on the top is stretched or sliced), no glow. Calling it again redraws the rig (a re-layout).
-- Returns the number of pieces
function SignKit.Rig(parts, opts)
	opts = opts or {}
	local board, roof, head, wood = parts.Board, parts.Roof, parts.Head, parts.Frame
	-- (Pitch 2 F0) the rig draws its own approved bevel, canopy and hem (the B2 pick): the kit's finish steps aside on the
	-- parts it rigs
	local function unfinish(obj, names)
		for _, name in ipairs(names) do
			local h = obj and obj:FindFirstChild(name)
			if h then
				h:Destroy()
			end
		end
	end
	unfinish(wood, { "FinishBevel", "FinishShadow" })
	unfinish(wood and wood:FindFirstChild("Body"), { "FinishCarve" })
	unfinish(head, { "FinishBevel" })
	unfinish(head and head:FindFirstChild("Plate"), { "FinishTop" })
	unfinish(roof, { "FinishTrim" })
	local bw = tonumber(opts.Width) or (board and board.Size.X.Offset) or 440
	local bh = board and board.Size.Y.Offset or 0
	local k = math.min(math.max(bw / 250, 1), 2)
	local at = bw / 250 -- a position on the pitch's 250 px board
	local function px(v, least)
		return math.max(least or 1, math.floor(v * k + 0.5))
	end
	local n = 0
	if board then
		clearRig(board)
	end
	-- the canopy: the roof's face canvas, navy stripes across it, its edge and lip navy; the scalloped valance under it
	local roofW, roofH, roofX = 0, 0, 0
	if roof then
		clearRig(roof)
		roofW, roofH = roof.Size.X.Offset, roof.Size.Y.Offset
		roofX = roof.Position.X.Scale * bw + roof.Position.X.Offset - roof.AnchorPoint.X * roofW
		roof.BackgroundColor3 = Sign.NavyLip
		local face = roof:FindFirstChild("Face")
		if face then
			clearRig(face)
			face.BackgroundColor3 = Sign.Canvas
			local lip = face:FindFirstChild("Lip")
			if lip then
				lip.BackgroundColor3 = Sign.NavyLip
			end
			local faceW = roofW - 2 * Z.RoofEdge
			local x = 0
			while x < faceW do
				piece("Stripe", Sign.NavyLight, {
					Position = UDim2.fromOffset(x, 0),
					Size = UDim2.new(0, math.min(px(RZ.Stripe), faceW - x), 1, 0),
					ZIndex = face.ZIndex,
				}, face)
				n = n + 1
				x = x + px(RZ.Stripe) + px(RZ.Gap)
			end
		end
		-- the valance: scallops in the stripe colour above them, each three steps narrower to its foot, brass under each
		-- step's open edge
		local sw, rows, pipe = px(RZ.Scallop, 6), math.max(1, math.floor(px(RZ.Drop) / 3)), px(RZ.Pipe)
		local inset = math.max(1, math.floor(sw / 6))
		local period = px(RZ.Stripe) + px(RZ.Gap)
		local count = math.floor(roofW / sw)
		local x0 = math.floor((roofW - count * sw) / 2)
		for i = 0, count - 1 do
			local x = x0 + i * sw
			local mid = (x + sw / 2 - Z.RoofEdge) % period
			local colour = mid < px(RZ.Stripe) and Sign.NavyLight or Sign.Canvas
			local sc = frame("RigScallop", { Position = UDim2.new(0, x, 1, 0), Size = UDim2.fromOffset(sw, 3 * rows + pipe), ZIndex = roof.ZIndex }, roof)
			sc:SetAttribute("SignKit", "Rig")
			sc:SetAttribute("Rig", "Scallop")
			for r = 0, 2 do
				local cut = r * inset
				fill("Step", colour, { Position = UDim2.fromOffset(cut, r * rows), Size = UDim2.fromOffset(sw - 2 * cut, rows), ZIndex = roof.ZIndex }, sc)
				-- the brass piping under this step's open edge (the whole foot on the last step)
				if r == 2 then
					piece("Piping", Sign.Brass, { Position = UDim2.fromOffset(cut, 3 * rows), Size = UDim2.fromOffset(sw - 2 * cut, pipe), ZIndex = roof.ZIndex }, sc)
				else
					piece("Piping", Sign.Brass, { Position = UDim2.fromOffset(cut, (r + 1) * rows), Size = UDim2.fromOffset(inset, pipe), ZIndex = roof.ZIndex }, sc)
					piece("Piping", Sign.Brass, { Position = UDim2.fromOffset(sw - cut - inset, (r + 1) * rows), Size = UDim2.fromOffset(inset, pipe), ZIndex = roof.ZIndex }, sc)
				end
			end
			n = n + 1
		end
		-- the patch: canvas, four stitches along each long side, at x 176 of 250
		local pw, ph, st = px(RZ.PatchW), px(RZ.PatchH), px(RZ.Stitch, 2)
		local patch = piece("Patch", Sign.Stone, {
			Position = UDim2.fromOffset(math.floor(-roofX + RZ.PatchAt * at - pw / 2), math.floor((roofH - ph) / 2)),
			Size = UDim2.fromOffset(pw, ph),
			ZIndex = roof.ZIndex,
		}, roof, "Patch")
		for i = 0, 3 do
			local sx = math.floor((i + 0.5) * pw / 4 - st / 2)
			fill("Stitch", Sign.Wood, { Position = UDim2.fromOffset(sx, 0), Size = UDim2.fromOffset(st, math.max(1, math.floor(st / 2))), ZIndex = roof.ZIndex }, patch)
			fill("Stitch", Sign.Wood, { Position = UDim2.fromOffset(sx, ph - math.max(1, math.floor(st / 2))), Size = UDim2.fromOffset(st, math.max(1, math.floor(st / 2))), ZIndex = roof.ZIndex }, patch)
		end
		n = n + 1
	end
	-- the frame's bevel: a lit top / left edge, a shaded bottom / right (B1's skeleton under B2)
	for _, part in ipairs({ head, wood }) do
		if part then
			clearRig(part)
			local z = part.ZIndex
			piece("Bevel", Sign.WoodLight, { Size = UDim2.new(0, RZ.Bevel, 1, 0), ZIndex = z }, part)
			piece("Bevel", Sign.WoodDark, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, RZ.Shade, 1, 0), ZIndex = z }, part)
			if part == head then
				piece("Bevel", Sign.WoodLight, { Size = UDim2.new(1, 0, 0, RZ.Bevel), ZIndex = z }, part)
			else
				piece("Bevel", Sign.WoodDark, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, RZ.Shade), ZIndex = z }, part)
			end
			n = n + 4
		end
	end
	-- the canvas body: one sheet, a hem on its top, left and right (its lip is the foot), lit inside the hem; no seams
	local body = wood and wood:FindFirstChild("Body")
	if body then
		clearRig(body)
		local hem, lit = px(RZ.Hem), px(RZ.HemLit)
		piece("Hem", Sign.StoneLip, { Size = UDim2.new(1, 0, 0, hem), ZIndex = 1 }, body)
		piece("Hem", Sign.StoneLip, { Size = UDim2.new(0, hem, 1, 0), ZIndex = 1 }, body)
		piece("Hem", Sign.StoneLip, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, hem, 1, 0), ZIndex = 1 }, body)
		piece("HemLit", Sign.Tile, { Position = UDim2.fromOffset(hem, hem), Size = UDim2.new(1, -2 * hem, 0, lit), ZIndex = 1 }, body)
		piece("HemLit", Sign.Tile, { Position = UDim2.fromOffset(hem, hem), Size = UDim2.new(0, lit, 1, -hem), ZIndex = 1 }, body)
		n = n + 5
	end
	if not board then
		return n
	end
	local z = 5 -- over the roof (3), the header (2) and the logo (4)
	-- the corner lashings: rope wound round each corner of the frame (below the valance at the top), diagonal strands of
	-- rope and its shade over the dark wood
	local ls = px(RZ.Lash, 6)
	local cell = math.max(2, math.floor(ls / 5))
	ls = cell * 5
	local topY = roof and (roof.Position.Y.Offset + roofH + px(RZ.Drop) + px(RZ.Pipe)) or (head and head.Position.Y.Offset or 0)
	for _, c in ipairs({ { 0, topY }, { bw - ls, topY }, { 0, bh - ls }, { bw - ls, bh - ls } }) do
		local lash = piece("Lashing", Sign.WoodDark, { Position = UDim2.fromOffset(c[1], c[2]), Size = UDim2.fromOffset(ls, ls), ZIndex = z }, board, "Lashing")
		for r = 0, 4 do
			for col = 0, 4 do
				local d = (col - r) % 3
				if d < 2 then
					fill("Strand", d == 0 and Sign.Post or Sign.Wood, { Position = UDim2.fromOffset(col * cell, r * cell), Size = UDim2.fromOffset(cell, cell), ZIndex = z }, lash)
				end
			end
		end
		n = n + 1
	end
	-- the hang rig: each rope twisted (wood blocks down its length, its flat shade off), ending in a carabiner clipped to
	-- an eye-bolt on the canopy's top edge
	local bar = px(RZ.Bar, 2)
	local roofTop = roof and roof.Position.Y.Offset or 0
	for _, rope in ipairs(parts.Ropes or {}) do
		clearRig(rope)
		local shade = rope:FindFirstChild("Shade")
		if shade then
			shade.Visible = false
		end
		local tb = px(RZ.Twist, 3)
		local len = rope.Size.Y.Offset
		local y = 0
		while y < len do
			piece("Twist", Sign.Wood, { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, math.min(tb, len - y)), ZIndex = rope.ZIndex }, rope, "HangRig")
			y = y + 2 * tb
			n = n + 1
		end
		local cx = rope.Position.X.Offset + rope.Size.X.Offset / 2 - board.Position.X.Offset
		local ew, cw, ch = px(RZ.Eye), px(RZ.CaraW), px(RZ.CaraH)
		local eyeY = roofTop - math.floor(ew / 2)
		ironRing("EyeBolt", ew, ew, bar, Sign.IronDark, Sign.IronDark, 0, z, board, "HangRig").Position = UDim2.fromOffset(math.floor(cx - ew / 2), eyeY)
		ironRing("Carabiner", cw, ch, bar, Sign.Iron, Sign.IronDark, px(RZ.Gate), z, board, "HangRig").Position = UDim2.fromOffset(math.floor(cx - cw / 2), eyeY - ch + bar)
		n = n + 2
	end
	-- the propellers: at the canopy's top corners, wooden blades (a darker lower edge) on a brass hub on a bracket
	local long, short, hub = px(RZ.Prop), px(RZ.PropW, 3), px(RZ.Hub, 3)
	local brW, brH = px(RZ.BracketW), px(RZ.BracketH)
	for _, x in ipairs({ RZ.PropIn * at, bw - RZ.PropIn * at }) do
		local cy = roofTop - RZ.PropUp * at
		local prop = frame("RigPropeller", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(cy + 0.5)),
			Size = UDim2.fromOffset(long, long),
			ZIndex = z,
		}, board)
		prop:SetAttribute("SignKit", "Rig")
		prop:SetAttribute("Rig", "Propeller")
		prop:SetAttribute("Trim", "Propeller")
		piece("Bracket", Sign.GoldLip, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(brW, brH), ZIndex = z }, prop)
		local blade = piece("Blade", Sign.Post, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(long, short), ZIndex = z }, prop)
		blade:SetAttribute("Long", long)
		blade:SetAttribute("Short", short)
		fill("Edge", Sign.Wood, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, math.max(1, math.floor(short / 3))), ZIndex = z }, blade)
		piece("Hub", Sign.Brass, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(hub, hub), ZIndex = z }, prop)
		n = n + 1
	end
	-- the version plate: brass on the bottom rail, centred, its rivets at the ends, "V6" in brown
	if opts.Version then
		local w, h = px(RZ.PlateW), px(RZ.PlateH)
		local plate = piece("Plate", Sign.GoldLip, {
			Position = UDim2.fromOffset(math.floor((bw - w) / 2), bh - px(RZ.PlateUp)),
			Size = UDim2.fromOffset(w, h),
			ZIndex = z,
		}, board, "Plate")
		local e = math.max(1, math.floor(k + 0.5))
		local face = fill("Face", Sign.Gold, { Position = UDim2.fromOffset(e, 0), Size = UDim2.new(1, -2 * e, 1, -e), ZIndex = z }, plate)
		fill("Shine", Sign.GoldLight, { Size = UDim2.new(1, 0, 0, math.max(1, math.floor(2 * k / 1.5))), ZIndex = z }, face)
		local rv = px(RZ.Bar, 2)
		for _, rx in ipairs({ e + 1, w - 2 * e - rv - 1 }) do
			fill("Rivet", Sign.GoldLip, { Position = UDim2.fromOffset(rx, math.floor((h - rv) / 2)), Size = UDim2.fromOffset(rv, rv), ZIndex = z }, face)
		end
		local l = text("PlateText", opts.Version, "Tag", math.max(18, px(RZ.PlateText)), Sign.Text, {
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
		}, face)
		l.TextYAlignment = Enum.TextYAlignment.Center
		n = n + 1
	end
	return n
end

return SignKit
