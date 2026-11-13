-- SignKit: the Signboard parts of kit B (U2 of .superpowers/slop-audit/round3/BUILD_PLAN.md, findings 5 and 7; the owner's
-- approved pitch, kit_pitch_mockups.html "B. Cloud Shop Signboard"). One shared set of parts that the loading screen
-- (ReplicatedFirst: Shared only) and every window build from. Square blocks, no slice image: a part is Frames in the
-- Theme.Sign colours, an edge, a darker bottom lip and a face, never a glow, a gradient or a scale bounce.
--   SignKit.Roof(parent, opts)    the flat pink awning with its dark edge and darker lip: ONE fixed-size piece (offset
--                                 only, never stretched with the window; Gemini's rule), centred on the window's top.
--                                 opts.Shape = "Gable": the Credits window's gable (two slopes, fascia, vent)
--   SignKit.Header(parent, opts)  the navy sign plank in a wood rim, its title in FredokaOne gold (Title role, through
--                                 Theme.StyleTitle); returns head, plate (the caller adds a close X to the plate).
--                                 opts.Ribbon: the plate is the T1 band out over the frame with its tails
--                                 (SignKit.HeaderOverhang(head, on) pulls it in and drops the tails)
--   SignKit.Frame(parent, opts)   the wood frame under the header
--   SignKit.Body(frame, opts)     the stone body inside it, with the stone lip along its bottom
--   SignKit.Plank(parent, opts)   a button with a real bottom lip: hover lifts the block 2 px, press sinks it 4 px and the
--                                 lip shrinks to 2 px (U5: the pitch's .dn); the label shrinks to fit, then truncates;
--                                 Style Off is disabled; SignKit.PlankState(plank, "Rest" | "Hover" | "Press") sets one
--   SignKit.Rope(parent, opts)    a rope / post the board hangs from
--   SignKit.BlockRow(parent, opts) n stone blocks with a darker lip; SignKit.FillBlocks(row, k) turns the first k gold
--   SignKit.Notice(parent, opts)  a small wood-framed stone card (a tip, a notice); returns notice, face
--   SignKit.Rig(parts, opts)      (sign/logo build: the owner's pick B2 "Sky-climber's rig", 2026-11-13; it replaced the
--                                 Workshop trim) a hanging board's canopy (canvas under navy stripes, a scalloped
--                                 valance with brass piping, a stitched patch), the frame's bevel, rope lashings on its
--                                 corners, the canvas body's hem, twisted ropes ending in carabiners on eye-bolts, two
--                                 propellers, the brass version plate. Opt-in: only the title screen's and the loading
--                                 screen's boards call it (Credits stays as approved). SignKit.Spin(root, on) flips the
--                                 propellers (2 frames, never a rotation); SignKit.PropFrame(root, n) sets one
-- Every part stamps attribute SignKit = its kind. Sizes are design px of a 1080p screen (the pitch's 0.8-scale px / 0.8);
-- opts override any colour or size, so a look the owner already approved (Credits) builds from these parts unchanged.
-- Requires only Theme (Shared). Plain Lua 5.1-compatible syntax only.

local Theme = require(script.Parent:WaitForChild("Theme"))

local SignKit = {}

local Sign = Theme.Sign

SignKit.Sizes = {
	RoofW = 320, -- the awning's default width (a window passes its own, still a fixed offset)
	RoofH = 18,
	RoofEdge = 4, -- the dark border round the awning
	RoofLip = 5, -- its darker bottom lip
	HeadH = 64,
	Rim = 6, -- the header's wood rim (top, left, right; the frame below closes it): the frame's width, so the edge runs straight
	TitleX = 18,
	IconSlot = 42, -- the gold icon square in a header
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
	BlockW = 28,
	BlockH = 22,
	BlockGap = 4,
	BlockEdge = 2,
	BlockLip = 4,
	NoticeEdge = 4,
	NoticeLip = 4,
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
	return s
end

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
	line(vent, opts.VentEdge or Sign.Wood, 2)
end

-- opts: Width, Height (fixed design px), Y, Shape ("Flat" | "Gable"), Color, Edge (border colour), Lip (lip colour),
-- EdgePx, LipPx; gable: Slope, Fascia, Shade, Vent, VentEdge
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
		roof.BackgroundTransparency = 0
		roof.BackgroundColor3 = opts.Edge or Sign.RoofEdge
		local face = fill("Face", opts.Color or Sign.Roof, {
			Position = UDim2.fromOffset(e, e),
			Size = UDim2.new(1, -2 * e, 1, -2 * e),
		}, roof)
		fill("Lip", opts.Lip or Sign.RoofLip, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, tonumber(opts.LipPx) or Z.RoofLip),
		}, face)
	end
	return place(roof, opts, "Roof")
end

----------------------------------------------------------------------
-- header, frame, body
----------------------------------------------------------------------

-- (render gate, GATE_KITB; the pitch title_T1: "The band sizes to the header; the tails are fixed") the band over a
-- Ribbon header: the plate reaches this far past the frame on each side, a swallowtail tail hangs off each end
SignKit.HeaderBand = { Over = 10 }

-- the plate inside the rim, or (a Ribbon header) the band out over the frame with its tails; SignKit.HeaderOverhang
local function placePlate(head, on)
	local plate = head:FindFirstChild("Plate")
	local rim = head:GetAttribute("Rim") or Z.Rim
	local over = on and SignKit.HeaderBand.Over or 0
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

-- (render gate) a Ribbon header's band out over the frame with its tails (on), or kept inside the rim with no tails (off:
-- a phone's short title sign, whose tails would land on the controls beside it). The title does not move
function SignKit.HeaderOverhang(head, on)
	if head and head:GetAttribute("Ribbon") then
		placePlate(head, on == true)
	end
end

-- opts: Title, TitleRole ("Title"), TitleSize, TitleColor (gold), Drop (a Color3: a drop line 3 px under the title),
-- TitleX, Reserve (px kept free on the right, e.g. for a close X), Y, Height, Rim, RimColor (wood), Color (navy),
-- IconSlot (a gold square left of the title for a PixelIcon), Ribbon (render gate: the plate is the T1 band the whole
-- header wide, out over the frame by HeaderBand.Over with a tail at each end; the title's ribbon keeps only its
-- letters, underline and stair, Theme's RibbonBand = "Header")
function SignKit.Header(parent, opts)
	opts = opts or {}
	local rim = tonumber(opts.Rim) or Z.Rim
	local role = opts.TitleRole or "Title"
	local ribbon = opts.Ribbon == true and role == "Title"
	local shift = ribbon and SignKit.HeaderBand.Over or 0 -- the plate starts this far left of the head: its children move in
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
		-- the tails behind the band's ends (ZIndex under the plate), their bottoms a little under the band's (the pitch)
		local R = Theme.TitleRibbon
		local k = size / R.Base
		local function px(v, least)
			return math.max(least or 1, math.floor(v * k + 0.5))
		end
		local tw, th, over, notch = px(R.TailW), px(R.TailH), px(R.TailOver), px(R.Notch, 2)
		for _, side in ipairs({ { "TailL", -1 }, { "TailR", 1 } }) do
			local tail = fill(side[1], Sign.NavyLip, { ZIndex = 0 }, head)
			tail:SetAttribute("Ribbon", "Tail")
			Theme.RibbonTail(tail, tw, th, notch, side[2])
			tail.Position = side[2] < 0 and UDim2.new(0, -shift - (tw - notch) + over, 1, -th + px(R.TailOver))
				or UDim2.new(1, shift - over, 1, -th + px(R.TailOver))
		end
		head:SetAttribute("Ribbon", true)
		placePlate(head, true)
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
	return head, plate
end

-- opts: Y, Height (nil = down to the parent's bottom), Color (wood)
function SignKit.Frame(parent, opts)
	opts = opts or {}
	local y = tonumber(opts.Y) or 0
	local h = tonumber(opts.Height)
	local wood = fill("Wood", opts.Color or Sign.Wood, {
		Position = UDim2.fromOffset(0, y),
		Size = h and UDim2.new(1, 0, 0, h) or UDim2.new(1, 0, 1, -y),
		Active = true,
	}, parent)
	return place(wood, opts, "Frame")
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
	if lip > 0 then
		fill("Lip", opts.LipColor or Sign.StoneLip, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, lip),
		}, body)
	end
	if type(opts.Line) == "table" then
		local li = tonumber(opts.Line.Inset) or 5
		local ln = frame("Line", {
			Position = UDim2.fromOffset(li, li),
			Size = UDim2.new(1, -2 * li, 1, -2 * li),
			ZIndex = 1,
		}, body)
		line(ln, opts.Line.Color or Sign.StoneLip, tonumber(opts.Line.Thickness) or 3)
	end
	return place(body, opts, "Body")
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
	local e = plank:GetAttribute("EdgePx") or Z.Edge
	local lip = plank:GetAttribute("LipPx") or Z.Lip
	if plank:GetAttribute("Off") then
		state = "Rest"
	end
	if state ~= "Hover" and state ~= "Press" then
		state = "Rest"
	end
	local shown = state == "Press" and math.min(lip, Z.PressLip) or lip
	block.Position = UDim2.fromOffset(0, (state == "Hover" and -Z.Hover) or (state == "Press" and Z.Sink) or 0)
	face.Position = UDim2.fromOffset(e, e)
	face.Size = UDim2.new(1, -2 * e, 1, -(2 * e + shown))
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
	plank.Parent = parent
	SignKit.PlankState(plank, "Rest")
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

-- opts: Count, BlockW, BlockH, Gap
function SignKit.BlockRow(parent, opts)
	opts = opts or {}
	local n = math.max(1, math.floor(tonumber(opts.Count) or 12))
	local bw, bh = tonumber(opts.BlockW) or Z.BlockW, tonumber(opts.BlockH) or Z.BlockH
	local gap = tonumber(opts.Gap) or Z.BlockGap
	local e = Z.BlockEdge
	local row = frame("BlockRow", { Size = UDim2.fromOffset(n * bw + (n - 1) * gap, bh) }, parent)
	row:SetAttribute("Count", n)
	for i = 1, n do
		local b = fill("Block" .. i, Sign.Wood, {
			Position = UDim2.fromOffset((i - 1) * (bw + gap), 0),
			Size = UDim2.fromOffset(bw, bh),
		}, row)
		local face = fill("Face", Sign.Stone, {
			Position = UDim2.fromOffset(e, e),
			Size = UDim2.new(1, -2 * e, 1, -2 * e),
		}, b)
		fill("Lip", Sign.StoneLip, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, Z.BlockLip),
		}, face)
	end
	place(row, opts, "BlockRow")
	SignKit.FillBlocks(row, 0)
	return row
end

-- the first k blocks gold (face and lip), the rest stone; k is floored and clamped to 0..Count. Returns k
function SignKit.FillBlocks(row, k)
	local n = row:GetAttribute("Count") or 0
	k = math.max(0, math.min(n, math.floor(tonumber(k) or 0)))
	for i = 1, n do
		local b = row:FindFirstChild("Block" .. i)
		local face = b and b:FindFirstChild("Face")
		if face then
			local on = i <= k
			face.BackgroundColor3 = on and Sign.Gold or Sign.Stone
			local lip = face:FindFirstChild("Lip")
			if lip then
				lip.BackgroundColor3 = on and Sign.GoldLip or Sign.StoneLip
			end
		end
	end
	row:SetAttribute("Filled", k)
	return k
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
	fill("Lip", Sign.StoneLip, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, Z.NoticeLip),
	}, face)
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
	place(notice, opts, "Notice")
	return notice, face
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
