-- SignKit: the Signboard parts of kit B (U2 of .superpowers/slop-audit/round3/BUILD_PLAN.md, findings 5 and 7; the owner's
-- approved pitch, kit_pitch_mockups.html "B. Cloud Shop Signboard"). One shared set of parts that the loading screen
-- (ReplicatedFirst: Shared only) and every window build from. Square blocks, no slice image: a part is Frames in the
-- Theme.Sign colours, an edge, a darker bottom lip and a face, never a glow, a gradient or a scale bounce.
--   SignKit.Roof(parent, opts)    the flat pink awning with its dark edge and darker lip: ONE fixed-size piece (offset
--                                 only, never stretched with the window; Gemini's rule), centred on the window's top.
--                                 opts.Shape = "Gable": the Credits window's gable (two slopes, fascia, vent)
--   SignKit.Header(parent, opts)  the navy sign plank in a wood rim, its title in LuckiestGuy gold (Title role); returns
--                                 head, plate (the caller adds a close X to the plate)
--   SignKit.Frame(parent, opts)   the wood frame under the header
--   SignKit.Body(frame, opts)     the stone body inside it, with the stone lip along its bottom
--   SignKit.Plank(parent, opts)   a button with a real bottom lip: hover lifts the block 2 px, press sinks it 4 px and the
--                                 lip shrinks to 2 px (U5: the pitch's .dn); the label shrinks to fit, then truncates;
--                                 Style Off is disabled; SignKit.PlankState(plank, "Rest" | "Hover" | "Press") sets one
--   SignKit.Rope(parent, opts)    a rope / post the board hangs from
--   SignKit.BlockRow(parent, opts) n stone blocks with a darker lip; SignKit.FillBlocks(row, k) turns the first k gold
--   SignKit.Notice(parent, opts)  a small wood-framed stone card (a tip, a notice); returns notice, face
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

-- opts: Title, TitleRole ("Title"), TitleSize, TitleColor (gold), Drop (a Color3: a drop line 3 px under the title),
-- TitleX, Reserve (px kept free on the right, e.g. for a close X), Y, Height, Rim, RimColor (wood), Color (navy),
-- IconSlot (a gold square left of the title for a PixelIcon)
function SignKit.Header(parent, opts)
	opts = opts or {}
	local rim = tonumber(opts.Rim) or Z.Rim
	local head = fill("Head", opts.RimColor or Sign.Wood, {
		Position = UDim2.fromOffset(0, tonumber(opts.Y) or 0),
		Size = UDim2.new(1, 0, 0, tonumber(opts.Height) or Z.HeadH),
		Active = true,
	}, parent)
	local plate = fill("Plate", opts.Color or Sign.Navy, {
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 1, -rim),
	}, head)
	local x = tonumber(opts.TitleX) or Z.TitleX
	if opts.IconSlot then
		local slot = fill("IconSlot", Sign.Gold, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(Z.IconSlot, Z.IconSlot),
		}, plate)
		line(slot, Sign.Text, 2)
		x = 12 + Z.IconSlot + 12
	end
	local role = opts.TitleRole or "Title"
	local size = tonumber(opts.TitleSize) or Theme.RoleSize(role)
	local box = UDim2.new(1, -(x + (tonumber(opts.Reserve) or 0)), 1, 0)
	if opts.Drop then
		text("TitleDrop", opts.Title, role, size, opts.Drop, {
			Position = UDim2.fromOffset(x, 3),
			Size = box,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 1,
		}, plate)
	end
	text("Title", opts.Title, role, size, opts.TitleColor or Sign.Gold, {
		Position = UDim2.fromOffset(x, 0),
		Size = box,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	}, plate)
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

return SignKit
