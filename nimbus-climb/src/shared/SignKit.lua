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
--   SignKit.Workshop(parts, opts) (sign build: the owner's pick "A Workshop") the hand-built trim on a hanging board's
--                                 parts: wood grain strips in the frame and the header rim, iron nails, a metal ring on
--                                 each rope, the awning striped with a notched lip, one chipped corner. Opt-in: only the
--                                 title screen's and the loading screen's boards call it (Credits stays as approved)
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
-- workshop trim (sign build; the owner's pick "A Workshop" on .superpowers/sign-pitch/sign_pitch.html)
----------------------------------------------------------------------

-- the trim's colours: the wood's own grain (Theme.Sign.Wood towards Text / Post) and the pitch's iron (#9AA3AD / #5D6670;
-- Theme.Sign has no grey, a later Iron / IronDark token there wins)
SignKit.WorkshopColors = {
	Grain = Sign.Wood:Lerp(Sign.Text, 0.45), -- a darker grain line
	GrainLight = Sign.Wood:Lerp(Sign.Post, 0.6), -- a lighter one, and the chipped corner's raw wood
	Iron = Sign.Iron or Color3.fromRGB(154, 163, 173),
	IronDark = Sign.IronDark or Color3.fromRGB(93, 102, 112),
	Stripe = Sign.RoofLip,
	Notch = Sign.RoofLip, -- the pitch's darker pink lip (--pinkdk)
}
local WC = SignKit.WorkshopColors
local NOTCH_H = 7 -- the awning's notched lip: a 4 px tooth and its 3 px point

-- one trim block: a flat Frame stamped SignKit = "Workshop", Workshop = its kind
local function bit(kind, colour, props, parent)
	local f = fill("Trim" .. kind, colour, props, parent)
	f:SetAttribute("SignKit", "Workshop")
	f:SetAttribute("Workshop", kind)
	return f
end

-- the trim of an earlier call, so a re-layout can draw it again at the new size
local function clearTrim(parent)
	for _, c in ipairs(parent:GetChildren()) do
		if c:GetAttribute("SignKit") == "Workshop" then
			c:Destroy()
		end
	end
end

-- a grain strip on a rail: x / y as { scale, offset }, w / h the same
local function grain(parent, light, x, y, w, h, z)
	return bit("Grain", light and WC.GrainLight or WC.Grain, {
		Position = UDim2.new(x[1], x[2], y[1], y[2]),
		Size = UDim2.new(w[1], w[2], h[1], h[2]),
		ZIndex = z,
	}, parent)
end

-- an iron nail head (s px): a square whose darker bottom-right (sh px) shows round a lighter cap (the pitch's inset shadow)
local function nail(parent, pos, s, sh, z)
	local n = bit("Nail", WC.IronDark, { Position = pos, Size = UDim2.fromOffset(s, s), ZIndex = z }, parent)
	fill("TrimCap", WC.Iron, { Size = UDim2.fromOffset(s - sh, s - sh), ZIndex = z }, n)
	return n
end

-- the lowest ZIndex among obj's own (non-trim) children, or 1
local function lowestChild(obj)
	local low = nil
	for _, c in ipairs(obj:GetChildren()) do
		if c:IsA("GuiObject") and c:GetAttribute("SignKit") ~= "Workshop" then
			low = math.min(low or c.ZIndex, c.ZIndex)
		end
	end
	return low or 1
end

-- cut a stepped bite out of a filled Frame's bottom-right corner, so what is behind the board shows through: the Frame
-- turns see-through and "Cut" patches (z, under its own children) fill it again less the bite. steps: { dx, dy } from
-- the corner, dx falling and dy rising; the bite is every x >= W - dx, y >= H - dy. maxH: the Frame's height when known
local function cut(obj, colour, steps, z, maxH)
	obj.BackgroundTransparency = 1
	local d = {}
	for _, s in ipairs(steps) do
		if s[1] > 0 and s[2] > 0 then
			d[#d + 1] = { s[1], maxH and math.min(s[2], maxH) or s[2] }
		end
	end
	local top = d[#d] and d[#d][2] or 0
	bit("Cut", colour, { Size = UDim2.new(1, 0, 1, -top), ZIndex = z }, obj)
	local above = 0
	for _, s in ipairs(d) do
		-- the band of rows between this step and the one before, as wide as the frame less this step's bite
		if s[2] > above then
			bit("Cut", colour, { Position = UDim2.new(0, 0, 1, -s[2]), Size = UDim2.new(1, -s[1], 0, s[2] - above), ZIndex = z }, obj)
		end
		above = s[2]
	end
end

-- parts: Roof (a flat SignKit.Roof: offset-sized, with its Face and Lip), Head (the header: rim + plate), Frame (the wood
-- frame round the body), Ropes (the board's ropes; their lower end runs RingAt px into the board). opts: Rail (the rim /
-- frame width, default Sizes.Frame), RingAt (8), Width (the board's design width; default the frame's or its board's),
-- Factor (the screen's UIScale, default Theme.ScreenFactor()). (review) The pitch drew the trim on a 250 px board, so
-- nails, rings and the chip grow with the board (Width / 250, 1 .. 2); a grain strip stays 2 screen px or wider (3 design
-- px under a 0.8 factor) so it never shimmers on the swinging board. Calling it again redraws the trim (a re-layout).
-- Returns the trim count
function SignKit.Workshop(parts, opts)
	opts = opts or {}
	local rail = tonumber(opts.Rail) or Z.Frame
	local n = 0
	local roof, head, wood = parts.Roof, parts.Head, parts.Frame
	local width = tonumber(opts.Width)
	if not width and wood then
		width = wood.Size.X.Offset > 0 and wood.Size.X.Offset or (wood.Parent and wood.Parent:IsA("GuiObject") and wood.Parent.Size.X.Offset)
	end
	local k = math.min(math.max((tonumber(width) or 440) / 250, 1), 2)
	local f = tonumber(opts.Factor) or Theme.ScreenFactor()
	local g = math.min(math.max(2, math.ceil(2 / f - 0.001)), rail - 2) -- a grain strip's width
	local gIn, gOut = 1, rail - g - 1 -- a strip's two places across a rail
	local nailS, nailSh, nailIn = math.floor(6 * k + 0.5), math.floor(2 * k + 0.5), math.floor(3 * k + 0.5)
	if roof then
		clearTrim(roof)
		local face = roof:FindFirstChild("Face")
		local w = roof.Size.X.Offset
		local z = roof.ZIndex
		if face then
			clearTrim(face)
			local lipObj = face:FindFirstChild("Lip")
			local lip = lipObj and lipObj.Size.Y.Offset or Z.RoofLip
			-- stripes: a 2 px darker line every 16 px across the face, above its lip
			local faceW = w - 2 * Z.RoofEdge
			for x = 14, faceW - 4, 16 do
				bit("Stripe", WC.Stripe, { Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, 2, 1, -lip), ZIndex = face.ZIndex }, face)
				n = n + 1
			end
		end
		-- the notched lip under the awning: stepped pixel teeth (10 px, then 6 px), one every 14 px
		local notch = frame("TrimNotch", { Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, NOTCH_H), ZIndex = z }, roof)
		notch:SetAttribute("SignKit", "Workshop")
		notch:SetAttribute("Workshop", "Notch")
		for x = 2, w - 12, 14 do
			local tooth = bit("Tooth", WC.Notch, { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(10, 4), ZIndex = z }, notch)
			fill("TrimPoint", WC.Notch, { Position = UDim2.fromOffset(2, 4), Size = UDim2.fromOffset(6, 3), ZIndex = z }, tooth)
			n = n + 1
		end
	end
	if head then
		clearTrim(head)
		local z = head.ZIndex
		-- grain along the side rails of the rim (its top hides under the awning)
		grain(head, false, { 0, gIn }, { 0.32, 0 }, { 0, g }, { 0.5, 0 }, z)
		grain(head, true, { 1, -rail + gOut }, { 0.22, 0 }, { 0, g }, { 0.55, 0 }, z)
		-- a nail in each top corner of the navy plate, as in the pitch, below the awning's notched teeth
		local plate = head:FindFirstChild("Plate")
		local nz = (plate and plate.ZIndex or z) + 1
		local y = rail + nailIn
		if roof and roof.Parent == head.Parent then
			y = math.max(y, roof.Position.Y.Offset + roof.Size.Y.Offset + NOTCH_H - head.Position.Y.Offset + 2)
		end
		nail(head, UDim2.fromOffset(rail + nailIn, y), nailS, nailSh, nz)
		nail(head, UDim2.new(1, -(rail + nailIn + nailS), 0, y), nailS, nailSh, nz)
		n = n + 4
	end
	if wood then
		clearTrim(wood)
		local z = wood.ZIndex
		-- grain on the left, right and bottom rails (a dark and a light run each, never the same length twice)
		grain(wood, false, { 0, gIn }, { 0.12, 0 }, { 0, g }, { 0.38, 0 }, z)
		grain(wood, true, { 0, gOut }, { 0.6, 0 }, { 0, g }, { 0.22, 0 }, z)
		grain(wood, true, { 1, -rail + gOut }, { 0.08, 0 }, { 0, g }, { 0.3, 0 }, z)
		grain(wood, false, { 1, -rail + gIn }, { 0.52, 0 }, { 0, g }, { 0.26, 0 }, z)
		grain(wood, false, { 0.1, 0 }, { 1, -rail + gOut }, { 0.32, 0 }, { 0, g }, z)
		grain(wood, true, { 0.55, 0 }, { 1, -rail + gIn }, { 0.28, 0 }, { 0, g }, z)
		local body = wood:FindFirstChild("Body")
		local bz = body and body.ZIndex or z
		local inset = body and body.Position.X.Offset or rail
		local lip = body and body:FindFirstChild("Lip")
		local lipH = lip and lip.Size.Y.Offset or Z.Lip
		-- a nail in each bottom corner of the body, as in the pitch, just above its lip (over the body: a higher ZIndex)
		local ny = -(inset + lipH + nailIn + nailS)
		nail(wood, UDim2.new(0, inset + nailIn, 1, ny), nailS, nailSh, bz + 1)
		nail(wood, UDim2.new(1, -(inset + nailIn + nailS), 1, ny), nailS, nailSh, bz + 1)
		-- one chipped corner (bottom-right): a stepped bite out of the frame and the body that shows what is behind the
		-- board (the pitch's 8 px bite in the sky colour), a dark crack running left along the lip from its inner step (clear of the nail)
		local c = math.floor(8 * k + 0.5)
		local s = math.floor(c / 4.5)
		local steps = { { c, c - 2 * s }, { c - s, c - s }, { c - 2 * s, c } }
		cut(wood, wood.BackgroundColor3, steps, bz - 1)
		if body then
			clearTrim(body)
			local inner = {}
			for i, st in ipairs(steps) do
				inner[i] = { st[1] - inset, st[2] - inset }
			end
			cut(body, body.BackgroundColor3, inner, lowestChild(body) - 1)
			if lip then
				clearTrim(lip)
				cut(lip, lip.BackgroundColor3, inner, lip.ZIndex, lipH)
			end
		end
		local chip = bit("Chip", WC.Grain, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Size = UDim2.fromOffset(c, c),
			ZIndex = bz + 1,
		}, wood)
		chip.BackgroundTransparency = 1 -- a marker over the bite: only its crack shows
		local p = math.floor(2 * k + 0.5)
		fill("TrimCrack", WC.Grain, { Position = UDim2.fromOffset(s - p, s - g), Size = UDim2.fromOffset(p, g), ZIndex = bz + 1 }, chip)
		fill("TrimCrack", WC.Grain, { Position = UDim2.fromOffset(s - 2 * p + 1, s), Size = UDim2.fromOffset(p - 1, g), ZIndex = bz + 1 }, chip)
		n = n + 9
	end
	-- a metal ring where each rope ties on: an arch round the rope, sitting on the awning (the pitch's 18 x 13 knot with
	-- its 3 px bars, grown with the board)
	local ringW, ringH, bar = math.floor(18 * k + 0.5), math.floor(13 * k + 0.5), math.floor(3 * k + 0.5)
	for _, rope in ipairs(parts.Ropes or {}) do
		clearTrim(rope)
		local z = rope.ZIndex
		local ring = frame("TrimRing", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(tonumber(opts.RingAt) or 8)),
			Size = UDim2.fromOffset(ringW, ringH),
			ZIndex = z,
		}, rope)
		ring:SetAttribute("SignKit", "Workshop")
		ring:SetAttribute("Workshop", "Ring")
		fill("TrimTop", WC.Iron, { Size = UDim2.fromOffset(ringW, bar), ZIndex = z }, ring)
		fill("TrimLeft", WC.Iron, { Size = UDim2.fromOffset(bar, ringH), ZIndex = z }, ring)
		fill("TrimRight", WC.IronDark, { Position = UDim2.fromOffset(ringW - bar, 0), Size = UDim2.fromOffset(bar, ringH), ZIndex = z }, ring)
		n = n + 1
	end
	return n
end

return SignKit
