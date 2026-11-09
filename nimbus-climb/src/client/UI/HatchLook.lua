-- HatchLook (client UI; roll-look, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.15 "Roll look A+B", the
-- owner's pick A "Showcase" + B's colour tell): the dressed pieces of the egg stage as builders and small handles with no
-- stage state of their own. client/UI/EggStage keeps the phases and calls these from its builders, layout and phase runner.
-- Every rarity colour comes from Shade(RarityColor(r), t) (the pitch mock's `shade`).
--
--   HatchLook.Shade(c, t) -> Color3           t >= 0: c towards white by t; t < 0: towards black by -t
--   HatchLook.RarityColor(rarity) -> Color3   Config.Rarities' colour; Secret the readable violet 180,150,255; an unknown
--                                             rarity the neutral 168,178,194
--   HatchLook.Order(rarity) -> number         Config.Rarities' Order (1 when unknown)
--   HatchLook.Card(cell, geo) -> card         skins a strip cell (a Frame with a UICorner and a UIStroke, its egg inside):
--                                             geo = { W, H, Corner, Shadow, Shine, Plate, Word, Lite, Phone, Z }. The face is
--                                             the cell's own UIGradient "Face" (navy 37,51,122 -> 17,25,68; from Rare up the
--                                             rarity tint rides in its top: c at 0.5 fading out by 0.75 of the height), the
--                                             rim is the cell's UIStroke, a white "Shine" line under the top edge; not Lite:
--                                             the rarity "Plate" pill holding the upper-case white "Word", and a
--                                             "Shadow<slot>" frame BESIDE the cell in its track (+Shadow px below it: a child
--                                             would draw over the card). card = { Frame, Face, Tint (= Face), Shine, Plate,
--                                             PlateText, Shadow, Rim }. Adds 5 instances to the cell (Lite: 2), +2 beside it
--   HatchLook.SetCard(card, rarity|false, state)   state "Idle" | "Landed" | "Dim": the face tint, the rim (Rare and up
--                                             Shade(c, .05) opaque, below Shade(c, -.1) at 0.25; 5 px Landed, else 3), the
--                                             plate (Shade(c, -.45), its stroke Shade(c, .1)) and its word; Dim: the face at
--                                             0.6 (as before the redo), the plate, word, rim and shine faded with it
--   HatchLook.ShowCard(card, cx, cy) / HideCard(card)   places a card by its centre (AnchorPoint 0.5: its pop grows round
--                                             the middle) with its shadow, or hides both
--   HatchLook.DropCard(card)                  destroys the cell and its shadow
--   HatchLook.LandPop(card, fast, track) -> { tween }   the land: a UIScale "Pop" on the card 1 -> 1.15 (0.1 s Quad Out)
--                                             -> 1.09 (0.15 s Quad InOut; Fast 0.05 / 0.07) and one white "Sweep" (a
--                                             gradient band, Offset -1 -> 1 in 0.3 s, Fast 0.12; destroyed after). Every
--                                             tween it plays (the chained one too) goes into `track`
--   HatchLook.SetPop(card, scale)             the pop at rest (a resize cancelled its tweens)
--   HatchLook.Window(parent, pointer, opts) -> win   the gold winner window on the strip's existing "Pointer" frame (its
--                                             root): children Glow (a wide soft stroke), Window (the gold stroke), NotchTop /
--                                             NotchBottom (45-degree squares centred on its top and bottom edges), a UIScale
--                                             "Bounce"; beside it in `parent`, DimL / DimR darken the track outside the window
--                                             after the land. opts = { Gold, Stroke, Glow, Notch (0 = none), NotchEdge (false
--                                             = no dark edge on the notches), Corner, Track (the tween set) }.
--                                             win:Place(x, y, w, h, trackW, trackH)  the window's box (the landed cell's + pad)
--                                             win:Style(opts)            a layout's strokes, corners and notches (a resize)
--                                             win:Tell(color, seconds)   every gold part turns `color` (attribute Tell = true)
--                                             win:Reset()                gold again (Tell = nil)
--                                             win:Bounce(seconds) / win:Rest()   a 1.08 -> 1 Back Out pop / at rest
--                                             win:SetDim(k)              the dims at k (0 = clear .. 1 = dark), per frame
--                                             win:DropGlow()             the soft glow goes (the rise: the winner lifted out)
--                                             win:DropDims()             the dims go (an x3 strip at the rise: the budget)
--                                             win:Destroy()
--   HatchLook.TrackFades(track, color, corner) -> FadeL, FadeR   the strip's ends fading from `color` to clear over the
--                                             cards (EggStage places them over the card band)
--   HatchLook.KEEP / HatchLook.ROBLOX         the ScreenGuis the stage never switches off: KEEP = spec 16.15's list (the
--                                             stage, toasts, the cursor hint, the tooltip, the Shop under the stage, the dev
--                                             tools, the main menu, the loading screen); ROBLOX = Roblox's own PlayerGui guis
--                                             (TouchGui: MenuController.SetTouchHidden owns the thumbstick; Freecam,
--                                             BubbleChat)
--   HatchLook.HideHud(playerGui, own) -> { ScreenGui }   switches off every Enabled ScreenGui in PlayerGui outside KEEP /
--                                             ROBLOX and not `own`, and remembers it
--   HatchLook.HideOne(gui)                    the same rule for one gui (PlayerGui.ChildAdded while the stage shows)
--   HatchLook.RestoreHud()                    switches each remembered gui back on when it is still in PlayerGui and still
--                                             off, then forgets them. A remembered gui someone switches on meanwhile is
--                                             forgotten at once (theirs again: never fought, never switched on by us later)
--   HatchLook.HiddenCount() -> number         how many guis are remembered (tests)
--   (Task 2: the opening)
--   HatchLook.Plinth(box, rarity, phone, opts) -> plinth   the flat lit disc the hero egg, its halves and the pet stand on,
--                                             drawn in the existing "Pedestal<j>" layout box (anchored at its top centre:
--                                             the egg's foot): "Top" (a disc 0.667 of the box tall, centred ON the box's
--                                             top edge so the egg stands in its middle; navy gradient 52,72,154 ->
--                                             20,29,82, its UIStroke "Rim" 3 px / phone 2), "Side" (the rim's thickness
--                                             under it: the lower third shows, a horizontal gradient 10,17,52 / 38,56,132
--                                             / 10,17,52), "Ring" (an inner ring on the Top, 0.76 x 0.7 of it, its stroke
--                                             at 0.45), "Glow1..2" (HatchLook.Glow: a soft halo round the disc) and a
--                                             UIScale "Pop" on the box. No drum, no puffs, no bars (a5a38ac). Neutral
--                                             (Shade(Metrics.PLINTH.Neutral, .25) rim, .4 ring, .2 glow) until Tint.
--                                             opts = { Track (the tween set), Glows (1..2, default 2), Ring (false = none) }
--                                             plinth:SetAlpha(a)        0 = hidden .. 1 = shown (the rise's fade, per frame)
--                                             plinth:Tint(color, s)     rim Shade(c, .25), ring Shade(c, .4), glow Shade(c, .2)
--                                                                       in s seconds (0: at once); remembered for Rest
--                                             plinth:Reset()            neutral again;  plinth:Rest()  Pop 1, shown, colour
--                                                                       snapped (a resize cancelled the tweens)
--                                             plinth:FitGlow(share)     the halo at most share x the box wide (the screen's
--                                                                       edge: a portrait x3's outer columns)
--   HatchLook.PlinthLip(box, lip)             the Top's box: the disc centred on the box's top edge, or (lip = true: a
--                                             phone's reveal) the whole box, the 12 px lip (EggStage's H.pedLook hides
--                                             the other parts)
--   HatchLook.IMAGES                          the three optional images, TextureIds keys: Rays "hatch_rays", Glow
--                                             "hatch_glow", Sparkle "hatch_sparkle" (none uploaded: their frame
--                                             fallbacks draw: HatchFx's ray wedges and spark squares, stacked round glows)
--   HatchLook.Image(key) -> "rbxassetid://<id>" | nil   the key's shared/TextureIds id when it is a number > 0
--                                             (HatchLook._Textures: a test table in place of the module; false = the module)
--   HatchLook.Glow(parent, color, opts) -> glow   a soft glow: with a hatch_glow id one ImageLabel named opts.Name
--                                             ("Glow") tinted `color`; without, opts.Count (2) crossed round Frames
--                                             "<Name>1..n", each with a UIGradient fading it out (a wide one to its sides,
--                                             a tall one to its top and bottom: no hard edge). opts = { Name, Count, Z }
--                                             glow:Place(pos, size)     the glow's centre and box (UDim2: scale or offset)
--                                             glow:SetAlpha(a)          0 = hidden .. 1 = shown
--                                             glow:SetColor(c, s, track, out)   in s seconds (0: at once)
--
-- Plain Lua 5.1-compatible syntax only. Text goes through Theme roles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Theme = require(Shared:WaitForChild("Theme"))

local HatchLook = {}

local rgb = Color3.fromRGB
local K = {
	WHITE = Color3.new(1, 1, 1),
	BLACK = Color3.new(0, 0, 0),
	SECRET = rgb(180, 150, 255), -- Secret's own colour is near black: the readable violet (EggStage.Metrics.SECRET_TEXT)
	NEUTRAL = rgb(168, 178, 194),
	GOLD = rgb(242, 182, 68), -- the window's rest gold = EggStage.Metrics.GOLD
	WIN_GLOW = rgb(244, 196, 78),
	NOTCH = rgb(255, 215, 106),
	NOTCH_EDGE = rgb(90, 54, 0),
	FACE_TOP = rgb(37, 51, 122),
	FACE_BOT = rgb(17, 25, 68),
	EDGE = rgb(44, 63, 136), -- a rarity-less cell's rim, the track's stroke
	SHADOW = rgb(2, 4, 14),
	SHADOW_A = 0.45,
	SHINE_A = 0.65,
	TINT_A = 0.5, -- the rarity tint over the face's top, gone by TINT_TO of the height
	TINT_TO = 0.75,
	DIM = rgb(4, 6, 22),
	DIM_A = 0.5, -- the dims' darkest (transparency 1 - DIM_A)
	POP = { Peak = 1.15, Rest = 1.09, Up = 0.1, Down = 0.15, UpFast = 0.05, DownFast = 0.07 },
	SWEEP = { Normal = 0.3, Fast = 0.12, Band = 0.45, Rotation = 18 },
	BOUNCE = 1.08,
	-- (Task 2) the plinth, in shares of its box (1.1 x / 0.24 x the egg, 16.4): the Top disc 0.667 of the box tall,
	-- centred on the box's top edge (the egg's foot); the Side the same height from that edge down (its lower third
	-- shows under the Top); the halo centred 16 / 90 of the box under the edge, 1.6 x the box wide and 1.9 x the Top
	-- tall; the inner ring 0.76 x 0.7 of the Top
	PLINTH = {
		Top = 2 / 3, GlowY = 16 / 90, GlowW = 1.6, GlowH = 1.9 * 2 / 3, RingW = 0.76, RingH = 0.7, RingA = 0.45, Rim = 3, RimPhone = 2,
		Ring = 2, RingPhone = 1.5,
		TopA = rgb(52, 72, 154), TopB = rgb(20, 29, 82), SideA = rgb(10, 17, 52), SideB = rgb(38, 56, 132),
		-- the colour the plinth's rim / ring / glow are shaded from before the rarity is shown on it (a soft periwinkle
		-- of the stage's navy: no rarity, no tease; Common's own grey reads as a white outline here)
		Neutral = rgb(110, 132, 200),
	},
	-- the glow's frame fallback (no hatch_glow id): crossed soft discs, a wide one fading to its sides and a tall one
	-- fading to its top and bottom, so the halo round the plinth falls off every way (the mock's radial gradient) with no
	-- hard edge; shares of the glow's box, transparency keypoints across each disc. The image's own transparency
	GLOW = {
		Discs = {
			{ W = 1, H = 0.79, Rotation = 0, Fade = { { 0, 1 }, { 0.18, 0.9 }, { 0.5, 0.5 }, { 0.82, 0.9 }, { 1, 1 } } },
			{ W = 0.72, H = 1, Rotation = 90, Fade = { { 0, 1 }, { 0.25, 0.84 }, { 0.5, 0.55 }, { 0.75, 0.84 }, { 1, 1 } } },
		},
		ImageA = 0.2,
	},
}
HatchLook.Metrics = K

----------------------------------------------------------------------
-- colours
----------------------------------------------------------------------
function HatchLook.Shade(c, t)
	t = tonumber(t) or 0
	if t >= 0 then
		return c:Lerp(K.WHITE, math.min(1, t))
	end
	return c:Lerp(K.BLACK, math.min(1, -t))
end

function HatchLook.RarityColor(rarity)
	if rarity == "Secret" then
		return K.SECRET
	end
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarity then
			return r.Color
		end
	end
	return K.NEUTRAL
end

function HatchLook.Order(rarity)
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarity then
			return r.Order or 1
		end
	end
	return 1
end

local function tween(inst, seconds, goals, style, direction, track)
	if not inst or not inst.Parent then
		return nil
	end
	local info = TweenInfo.new(math.max(0.01, seconds), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tw = TweenService:Create(inst, info, goals)
	if track then
		track[tw] = true
	end
	tw:Play()
	return tw
end

local function frame(parent, name, props)
	props = props or {}
	props.Name = name
	props.BorderSizePixel = 0
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	props.Parent = parent
	return Util.Create("Frame", props)
end

local function corner(parent, r)
	return Util.Create("UICorner", { CornerRadius = (r and r < 1) and UDim.new(r, 0) or UDim.new(0, r or 12), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return Util.Create("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

----------------------------------------------------------------------
-- the strip cards
----------------------------------------------------------------------
-- the face: navy top to bottom; with a tint colour, that colour at TINT_A over the top fading out by TINT_TO (the two
-- layers of the mock folded into one gradient: same colours, one instance less per card)
local function faceColors(tint)
	local function at(y)
		local base = K.FACE_TOP:Lerp(K.FACE_BOT, y)
		if not tint or y >= K.TINT_TO then
			return base
		end
		return base:Lerp(tint, K.TINT_A * (1 - y / K.TINT_TO))
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, at(0)),
		ColorSequenceKeypoint.new(K.TINT_TO / 2, at(K.TINT_TO / 2)),
		ColorSequenceKeypoint.new(K.TINT_TO, at(K.TINT_TO)),
		ColorSequenceKeypoint.new(1, at(1)),
	})
end

function HatchLook.Card(cell, geo)
	local W, H = geo.W, geo.H
	local cr = geo.Corner or 12
	local z = geo.Z or cell.ZIndex
	local card = { Frame = cell, Geo = geo, Lite = geo.Lite == true }
	cell.AnchorPoint = Vector2.new(0.5, 0.5)
	cell.BackgroundColor3 = K.WHITE
	cell.BackgroundTransparency = 0
	local uc = cell:FindFirstChildOfClass("UICorner") or corner(cell, cr)
	uc.CornerRadius = UDim.new(0, cr)
	card.Rim = cell:FindFirstChildOfClass("UIStroke") or stroke(cell, K.EDGE, 3)
	card.Face = Util.Create("UIGradient", { Name = "Face", Rotation = 90, Color = faceColors(nil), Parent = cell })
	card.Tint = card.Face
	local inset = math.floor(cr * 0.67 + 0.5)
	card.Shine = frame(cell, "Shine", {
		Position = UDim2.fromOffset(inset, math.max(2, math.floor(cr / 3 + 0.5))), Size = UDim2.fromOffset(math.max(0, W - 2 * inset), geo.Shine or 3),
		BackgroundColor3 = K.WHITE, BackgroundTransparency = K.SHINE_A, ZIndex = z + 1,
	})
	if not card.Lite then
		local ph = geo.Plate or 30
		card.Plate = frame(cell, "Plate", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2, H - ph - math.floor(ph * 0.4 + 0.5)), Size = UDim2.fromOffset(math.floor(W * 0.8 + 0.5), ph),
			BackgroundColor3 = K.FACE_BOT, BackgroundTransparency = 0, ZIndex = z + 1, Visible = false,
		})
		corner(card.Plate, 0.5)
		card.PlateEdge = stroke(card.Plate, K.EDGE, geo.Phone and 1.5 or 2)
		local word = Theme.Label("", geo.Phone and "Label" or "Heading", { Size = geo.Word or 18, Stroke = 0.75 })
		word.Name = "Word"
		word.Size = UDim2.fromScale(1, 1)
		word.TextColor3 = K.WHITE
		word.TextXAlignment = Enum.TextXAlignment.Center
		word.ZIndex = z + 2
		word.Parent = card.Plate
		card.PlateText = word
		-- the shadow sits beside the cell in its track, under it (ZIndex: a child would always draw over the card)
		local slot = cell.Name:match("%d+") or ""
		card.Shadow = frame(cell.Parent, "Shadow" .. slot, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(W, H), BackgroundColor3 = K.SHADOW, BackgroundTransparency = K.SHADOW_A,
			ZIndex = math.max(1, z - 1), Visible = false,
		})
		corner(card.Shadow, cr)
	end
	return card
end

function HatchLook.SetCard(card, rarity, state)
	if not card then
		return
	end
	local key = tostring(rarity) .. "/" .. tostring(state)
	if card.Key == key then
		return
	end
	card.Key = key
	local cell = card.Frame
	local dim = state == "Dim"
	local c = rarity and HatchLook.RarityColor(rarity) or nil
	local strong = rarity and HatchLook.Order(rarity) >= 3
	card.Face.Color = faceColors((c and not card.Lite) and c or nil)
	cell.BackgroundTransparency = dim and 0.6 or 0
	local rim = card.Rim
	if c then
		rim.Color = strong and HatchLook.Shade(c, 0.05) or HatchLook.Shade(c, -0.1)
		rim.Transparency = strong and 0 or 0.25
	else
		rim.Color = K.EDGE
		rim.Transparency = 0.25
	end
	if dim then
		rim.Transparency = math.max(rim.Transparency, 0.5)
	end
	rim.Thickness = state == "Landed" and 5 or 3
	card.Shine.BackgroundTransparency = dim and 0.88 or K.SHINE_A
	if card.Plate then
		card.Plate.Visible = c ~= nil
		if c then
			card.Plate.BackgroundColor3 = HatchLook.Shade(c, -0.45)
			card.Plate.BackgroundTransparency = dim and 0.45 or 0
			card.PlateEdge.Color = HatchLook.Shade(c, 0.1)
			card.PlateEdge.Transparency = dim and 0.5 or 0
			card.PlateText.Text = string.upper(rarity)
			card.PlateText.TextTransparency = dim and 0.35 or 0
		end
	end
end

function HatchLook.ShowCard(card, cx, cy)
	card.Frame.Position = UDim2.fromOffset(cx, cy)
	card.Frame.Visible = true
	local sh = card.Shadow
	if sh then
		sh.Position = UDim2.fromOffset(cx, cy + (card.Geo.Shadow or 8))
		sh.Visible = true
	end
end

function HatchLook.HideCard(card)
	card.Frame.Visible = false
	if card.Shadow then
		card.Shadow.Visible = false
	end
end

function HatchLook.DropCard(card)
	if card.Shadow then
		card.Shadow:Destroy()
		card.Shadow = nil
	end
	card.Frame:Destroy()
end

local function popOf(card)
	local f = card.Frame
	local pop = f:FindFirstChild("Pop")
	if not (pop and pop:IsA("UIScale")) then
		pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = f })
	end
	return pop
end

function HatchLook.SetPop(card, scale)
	if card and card.Frame and card.Frame.Parent then
		popOf(card).Scale = scale
	end
end

function HatchLook.LandPop(card, fast, track)
	local out = {}
	if not (card and card.Frame and card.Frame.Parent) then
		return out
	end
	local P = K.POP
	local pop = popOf(card)
	pop.Scale = 1
	local up = tween(pop, fast and P.UpFast or P.Up, { Scale = P.Peak }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, track)
	if up then
		out[#out + 1] = up
		up.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and pop.Parent then
				tween(pop, fast and P.DownFast or P.Down, { Scale = P.Rest }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, track)
			end
		end)
	end
	-- one shine sweep across the card (the clutter cap: one, at the land)
	local sw = K.SWEEP
	local sweep = frame(card.Frame, "Sweep", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ZIndex = card.Frame.ZIndex + 4 })
	corner(sweep, card.Geo.Corner or 12)
	local band = Util.Create("UIGradient", {
		Rotation = sw.Rotation, Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, sw.Band),
			NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = sweep,
	})
	local tw = tween(band, fast and sw.Fast or sw.Normal, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, track)
	if tw then
		out[#out + 1] = tw
		tw.Completed:Connect(function()
			sweep:Destroy() -- (done or cancelled: never left half way)
		end)
	else
		sweep:Destroy()
	end
	return out
end

----------------------------------------------------------------------
-- the gold window and the track's ends
----------------------------------------------------------------------
local Win = {}
Win.__index = Win

function HatchLook.Window(parent, pointer, opts)
	opts = opts or {}
	local phone = opts.Phone == true
	local self = setmetatable({}, Win)
	self.Gold = opts.Gold or K.GOLD
	self.Track = opts.Track
	self.Root = pointer
	self.Corner = opts.Corner or (phone and 15 or 22)
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.BackgroundTransparency = 1
	for _, c in ipairs(pointer:GetChildren()) do
		c:Destroy() -- (the old 6 px bar's corner)
	end
	local z = pointer.ZIndex
	self.Scale = Util.Create("UIScale", { Name = "Bounce", Scale = 1, Parent = pointer })
	self.Glow = frame(pointer, "Glow", { Size = UDim2.fromScale(1, 1), ZIndex = z })
	corner(self.Glow, self.Corner)
	self.GlowStroke = stroke(self.Glow, K.WIN_GLOW, opts.Glow or (phone and 6 or 10), 0.65)
	self.Window = frame(pointer, "Window", { Size = UDim2.fromScale(1, 1), ZIndex = z + 1 })
	corner(self.Window, self.Corner)
	self.WinStroke = stroke(self.Window, self.Gold, opts.Stroke or (phone and 3 or 4), 0)
	local n = opts.Notch or (phone and 10 or 16)
	self.Notches = {}
	for i, name in ipairs({ "NotchTop", "NotchBottom" }) do
		local notch = frame(pointer, name, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, i - 1), Size = UDim2.fromOffset(n, n), Rotation = 45,
			BackgroundColor3 = K.NOTCH, BackgroundTransparency = 0, ZIndex = z + 2, Visible = n > 0,
		})
		if opts.NotchEdge ~= false then
			self.Edges = self.Edges or {}
			self.Edges[i] = stroke(notch, K.NOTCH_EDGE, phone and 1.5 or 2, 0)
		end
		self.Notches[i] = notch
	end
	-- the dims beside the window (the mock's landDim: the track darkens round the winner). Square: past the track's
	-- rounded ends they only cover its near-black rim, where the dim cannot be told apart
	self.Dims = {}
	for i, name in ipairs({ "DimL", "DimR" }) do
		self.Dims[i] = frame(parent, name, { BackgroundColor3 = K.DIM, BackgroundTransparency = 1, ZIndex = math.max(1, z - 1) })
	end
	return self
end

-- the soft glow goes (the rise: the winner has lifted out of the window)
function Win:DropGlow()
	if self.Glow then
		self.Glow:Destroy()
		self.Glow, self.GlowStroke = nil, nil
	end
end

-- (Task 2) the dims go (an x3 strip sliding away at the rise: the budget)
function Win:DropDims()
	for _, d in ipairs(self.Dims) do
		d:Destroy()
	end
	self.Dims = {}
end

function Win:Place(x, y, w, h, trackW, trackH)
	local root = self.Root
	root.Position = UDim2.fromOffset(x + w / 2, y + h / 2)
	root.Size = UDim2.fromOffset(math.max(0, w), math.max(0, h))
	if trackW and self.Dims[2] then
		local left, right = self.Dims[1], self.Dims[2]
		left.Position = UDim2.fromOffset(0, 0)
		left.Size = UDim2.fromOffset(math.max(0, x), trackH or h)
		right.Position = UDim2.fromOffset(x + w, 0)
		right.Size = UDim2.fromOffset(math.max(0, trackW - x - w), trackH or h)
	end
end

-- the sizes of a layout (a resize): strokes, corners, notches (0 = none)
function Win:Style(opts)
	if opts.Stroke then
		self.WinStroke.Thickness = opts.Stroke
	end
	if opts.Glow and self.GlowStroke then
		self.GlowStroke.Thickness = opts.Glow
	end
	if opts.Corner then
		self.Corner = opts.Corner
		if self.Glow then
			self.Glow:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, opts.Corner)
		end
		self.Window:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, opts.Corner)
	end
	if opts.Notch then
		for _, notch in ipairs(self.Notches) do
			notch.Size = UDim2.fromOffset(opts.Notch, opts.Notch)
			notch.Visible = opts.Notch > 0
		end
	end
end

function Win:paint(color, seconds)
	local out = {}
	local parts = { { self.WinStroke, "Color" }, { self.Notches[1], "BackgroundColor3" }, { self.Notches[2], "BackgroundColor3" } }
	if self.GlowStroke then
		parts[#parts + 1] = { self.GlowStroke, "Color" }
	end
	-- (the notches' dark edge follows, a deep shade of the same colour)
	for _, edge in pairs(self.Edges or {}) do
		parts[#parts + 1] = { edge, "Color", HatchLook.Shade(color, -0.6) }
	end
	for _, p in ipairs(parts) do
		local inst, prop, goal = p[1], p[2], p[3] or color
		if seconds and seconds > 0 then
			out[#out + 1] = tween(inst, seconds, { [prop] = goal }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, self.Track)
		else
			inst[prop] = goal
		end
	end
	return out
end

function Win:Tell(color, seconds)
	self.Root:SetAttribute("Tell", true)
	self.TellColor = color
	return self:paint(color, seconds)
end

function Win:Reset()
	self.Root:SetAttribute("Tell", nil)
	self.TellColor = nil
	self.WinStroke.Color = self.Gold
	if self.GlowStroke then
		self.GlowStroke.Color = K.WIN_GLOW
	end
	for _, notch in ipairs(self.Notches) do
		notch.BackgroundColor3 = K.NOTCH
	end
	for _, edge in pairs(self.Edges or {}) do
		edge.Color = K.NOTCH_EDGE
	end
end

function Win:Bounce(seconds)
	self.Scale.Scale = K.BOUNCE
	return tween(self.Scale, seconds, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, self.Track)
end

function Win:Rest()
	self.Scale.Scale = 1
	if self.TellColor then
		self:paint(self.TellColor, 0)
	end
end

function Win:SetDim(k)
	local a = 1 - K.DIM_A * math.max(0, math.min(1, k))
	for _, d in ipairs(self.Dims) do
		d.BackgroundTransparency = a
	end
end

function Win:Destroy()
	for _, d in ipairs(self.Dims) do
		d:Destroy()
	end
	self.Root:Destroy()
end

function HatchLook.TrackFades(track, color, cr)
	local out = {}
	for i, name in ipairs({ "FadeL", "FadeR" }) do
		local f = frame(track, name, { BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = 4 })
		corner(f, cr or 12)
		Util.Create("UIGradient", { Transparency = i == 1 and NumberSequence.new(0, 1) or NumberSequence.new(1, 0), Parent = f })
		out[i] = f
	end
	return out[1], out[2]
end

----------------------------------------------------------------------
-- the optional images (spec 16.15 "Fallbacks": no id today, the frames draw)
----------------------------------------------------------------------
HatchLook.IMAGES = { Rays = "hatch_rays", Glow = "hatch_glow", Sparkle = "hatch_sparkle" }
HatchLook._Textures = false -- (tests: a table of key -> id in place of shared/TextureIds; false = the module)

local TextureIds = nil
local function textures()
	if type(HatchLook._Textures) == "table" then
		return HatchLook._Textures
	end
	if TextureIds == nil then
		TextureIds = false
		local module = Shared:FindFirstChild("TextureIds")
		if module and module:IsA("ModuleScript") then
			local ok, ids = pcall(require, module)
			if ok and type(ids) == "table" then
				TextureIds = ids
			end
		end
	end
	return TextureIds or {}
end

function HatchLook.Image(key)
	local id = textures()[key]
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	return nil
end

----------------------------------------------------------------------
-- a soft glow: one ImageLabel with an id, else stacked round frames
----------------------------------------------------------------------
local Glow = {}
Glow.__index = Glow

function HatchLook.Glow(parent, color, opts)
	opts = opts or {}
	local self = setmetatable({ Parts = {}, Alphas = {}, Shares = {}, Alpha = 1 }, Glow)
	local name = opts.Name or "Glow"
	local z = opts.Z or parent.ZIndex
	local image = HatchLook.Image(HatchLook.IMAGES.Glow)
	if image then
		self.Prop, self.ColorProp = "ImageTransparency", "ImageColor3"
		self.Parts[1] = Util.Create("ImageLabel", {
			Name = name, Image = image, ImageColor3 = color, ImageTransparency = K.GLOW.ImageA, BackgroundTransparency = 1, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z, Parent = parent,
		})
		self.Alphas[1], self.Shares[1] = K.GLOW.ImageA, { W = 1, H = 1 }
	else
		self.Prop, self.ColorProp = "BackgroundTransparency", "BackgroundColor3"
		local discs = K.GLOW.Discs
		for i = 1, math.max(1, math.min(#discs, opts.Count or #discs)) do
			local d = discs[i]
			local f = frame(parent, name .. i, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = z })
			corner(f, 0.5)
			local keys = {}
			for k, kp in ipairs(d.Fade) do
				keys[k] = NumberSequenceKeypoint.new(kp[1], kp[2])
			end
			Util.Create("UIGradient", { Rotation = d.Rotation, Transparency = NumberSequence.new(keys), Parent = f })
			self.Parts[i], self.Alphas[i], self.Shares[i] = f, 0, d
		end
	end
	return self
end

function Glow:Place(pos, size)
	for i, p in ipairs(self.Parts) do
		local w, h = self.Shares[i].W, self.Shares[i].H
		p.Position = pos
		p.Size = UDim2.new(size.X.Scale * w, size.X.Offset * w, size.Y.Scale * h, size.Y.Offset * h)
	end
end

function Glow:SetAlpha(a)
	self.Alpha = a
	for i, p in ipairs(self.Parts) do
		p[self.Prop] = 1 - a * (1 - self.Alphas[i])
	end
end

function Glow:SetColor(c, seconds, track, out)
	for _, p in ipairs(self.Parts) do
		if seconds and seconds > 0 then
			local tw = tween(p, seconds, { [self.ColorProp] = c }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, track)
			if tw and out then
				out[#out + 1] = tw
			end
		else
			p[self.ColorProp] = c
		end
	end
end

----------------------------------------------------------------------
-- the plinth (the Pedestal<j> box's look: a flat lit disc, never the old drum)
----------------------------------------------------------------------
local Plinth = {}
Plinth.__index = Plinth

function HatchLook.PlinthLip(box, lip)
	local top = box and box:FindFirstChild("Top")
	if not top then
		return
	end
	if lip then
		top.Position = UDim2.fromScale(0, 0)
		top.Size = UDim2.fromScale(1, 1)
	else
		top.Position = UDim2.fromScale(0, -K.PLINTH.Top / 2)
		top.Size = UDim2.fromScale(1, K.PLINTH.Top)
	end
end

function HatchLook.Plinth(box, rarity, phone, opts)
	opts = opts or {}
	local P = K.PLINTH
	local self = setmetatable({ Box = box, Rarity = rarity, Track = opts.Track, Alpha = 1, Color = nil }, Plinth)
	local z = box.ZIndex
	box.AnchorPoint = Vector2.new(0.5, 0) -- (the egg's foot: the pop grows round the disc's middle)
	box.BackgroundTransparency = 1
	self.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = box })
	self.Glow = HatchLook.Glow(box, HatchLook.Shade(P.Neutral, 0.2), { Name = "Glow", Count = opts.Glows, Z = z - 1 })
	self.Glow:Place(UDim2.fromScale(0.5, P.GlowY), UDim2.fromScale(P.GlowW, P.GlowH))
	self.GlowW = P.GlowW
	self.Side = frame(box, "Side", { Size = UDim2.fromScale(1, P.Top), BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ZIndex = z })
	corner(self.Side, 0.5)
	Util.Create("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, P.SideA), ColorSequenceKeypoint.new(0.5, P.SideB), ColorSequenceKeypoint.new(1, P.SideA) }), Parent = self.Side,
	})
	self.Top = frame(box, "Top", { BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ZIndex = z + 1 })
	corner(self.Top, 0.5)
	Util.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(P.TopA, P.TopB), Parent = self.Top })
	self.Rim = stroke(self.Top, HatchLook.Shade(P.Neutral, 0.25), phone and P.RimPhone or P.Rim, 0)
	self.Rim.Name = "Rim"
	HatchLook.PlinthLip(box, false)
	if opts.Ring ~= false then
		self.Ring = frame(box, "Ring", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(P.RingW, P.RingH * P.Top), ZIndex = z + 2 })
		corner(self.Ring, 0.5)
		self.RingStroke = stroke(self.Ring, HatchLook.Shade(P.Neutral, 0.4), phone and P.RingPhone or P.Ring, P.RingA)
	end
	return self
end

-- the halo at most `share` x the box wide (the room to the screen's nearer edge, both sides)
function Plinth:FitGlow(share)
	local P = K.PLINTH
	local w = math.min(P.GlowW, math.max(1, share or P.GlowW))
	if self.GlowW ~= w then
		self.GlowW = w
		self.Glow:Place(UDim2.fromScale(0.5, P.GlowY), UDim2.fromScale(w, P.GlowH))
	end
end

function Plinth:SetAlpha(a)
	a = math.max(0, math.min(1, a))
	self.Alpha = a
	self.Top.BackgroundTransparency = 1 - a
	self.Side.BackgroundTransparency = 1 - a
	self.Rim.Transparency = 1 - a
	if self.RingStroke then
		self.RingStroke.Transparency = 1 - a * (1 - K.PLINTH.RingA)
	end
	self.Glow:SetAlpha(a)
end

function Plinth:paint(c, seconds)
	local out = {}
	for _, p in ipairs({ { self.Rim, HatchLook.Shade(c, 0.25) }, { self.RingStroke, HatchLook.Shade(c, 0.4) } }) do
		if p[1] then
			if seconds and seconds > 0 then
				out[#out + 1] = tween(p[1], seconds, { Color = p[2] }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, self.Track)
			else
				p[1].Color = p[2]
			end
		end
	end
	self.Glow:SetColor(HatchLook.Shade(c, 0.2), seconds, self.Track, out)
	return out
end

function Plinth:Tint(color, seconds)
	self.Color = color or HatchLook.RarityColor(self.Rarity)
	return self:paint(self.Color, seconds)
end

function Plinth:Reset()
	self.Color = nil
	self:paint(K.PLINTH.Neutral, 0)
end

function Plinth:Rest()
	self.Pop.Scale = 1
	self:SetAlpha(1)
	self:paint(self.Color or K.PLINTH.Neutral, 0)
end

----------------------------------------------------------------------
-- the HUD hides while the stage shows (spec 16.15 "The HUD hides")
----------------------------------------------------------------------
HatchLook.KEEP = {
	NimbusHatch = true, NimbusNotify = true, NimbusMouseLockHint = true, CloudUITooltip = true, NimbusShop = true, NimbusDev = true,
	NimbusMainMenu = true, NimbusLoading = true,
}
HatchLook.ROBLOX = { TouchGui = true, Freecam = true, BubbleChat = true }

local Hidden = {} -- [ScreenGui] = its Enabled watch (a connection)

local function hideOne(gui, own)
	if typeof(gui) ~= "Instance" or not gui:IsA("ScreenGui") or gui == own or Hidden[gui] ~= nil then
		return false
	end
	if HatchLook.KEEP[gui.Name] or HatchLook.ROBLOX[gui.Name] or not gui.Enabled then
		return false
	end
	gui.Enabled = false
	-- someone switches it on while the stage shows: it is theirs again (left on now, never switched on by us later)
	Hidden[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		local conn = Hidden[gui]
		if conn and gui.Enabled then
			Hidden[gui] = nil
			conn:Disconnect()
		end
	end)
	return true
end

function HatchLook.HideHud(pg, own)
	local out = {}
	for _, gui in ipairs(pg and pg:GetChildren() or {}) do
		if hideOne(gui, own) then
			out[#out + 1] = gui
		end
	end
	return out
end

function HatchLook.HideOne(gui)
	return hideOne(gui, nil)
end

function HatchLook.RestoreHud()
	local list = Hidden
	Hidden = {}
	for gui, conn in pairs(list) do
		pcall(function()
			conn:Disconnect()
		end)
		pcall(function()
			if gui.Parent ~= nil and gui.Enabled == false then
				gui.Enabled = true
			end
		end)
	end
end

function HatchLook.HiddenCount()
	local n = 0
	for _ in pairs(Hidden) do
		n = n + 1
	end
	return n
end

return HatchLook
