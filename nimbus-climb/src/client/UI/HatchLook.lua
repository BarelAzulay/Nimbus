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
--                                             a tall one to its top and bottom: no hard edge). opts = { Name, Count, Z,
--                                             Discs (another disc list: the word's nested capsules) }
--                                             glow:Place(pos, size)     the glow's centre and box (UDim2: scale or offset)
--                                             glow:SetAlpha(a)          0 = hidden .. 1 = shown
--                                             glow:Fade(a, s, track)    the same in s seconds (Quad Out)
--                                             glow:SetColor(c, s, track, out)   in s seconds (0: at once)
--   (Task 3: the reveal)
--   HatchLook.Word(parent, text, rarity, size, opts) -> word   the rarity word: a Frame opts.Name ("Word") with the
--                                             attribute Text; opts.Letters: one Theme "Title" TextLabel per glyph "L1..Ln"
--                                             (white under a vertical UIGradient Shade(c, .78) / .22 / -.18, a round
--                                             UIStroke Shade(c, -.68) of clamp(round(size x 0.12), 2, 10) px, a UIScale
--                                             "Pop") 0.04 x size apart, over a soft Glow (c, peak about 0.55, the word +
--                                             0.6 x size wide, 1.1 x size tall); no Letters: one such TextLabel (an x3
--                                             phone column). opts = { Letters, Name, ZIndex, Measure = function(text, size)
--                                             -> px (the stage's real text widths) }
--                                             word:Width() -> px            word:Place(cx, y)   (y = the top)
--                                             word:SetSize(size)            word:Destroy()
--                                             word:Pop(startAt, stagger, track)   letter i (from 0) 0 -> 1.3 (0.12 s Quad
--                                                 Out) -> 1 (0.14 s Quad In) at startAt + stagger x i, the glow in over
--                                                 0.2 s from startAt + 0.05 (task.delay; the tweens go into `track`); one
--                                                 label: hidden until startAt
--                                             word:Settle()   every letter at 1, the glow shown, pending pops dropped (a
--                                                 resize mid-chain)
--   HatchLook.Pill(parent, opts) -> TextButton   a glossy pill button named opts.Name (transparent tap box, Text ""):
--                                             "Shadow" (2,4,14 at 0.5, 7 px down, 4 px in), "Face" (a CanvasGroup: the
--                                             rise and fade) > "Body" (the capsule: UIGradient "Fill" of the Kind, UIStroke
--                                             "Edge" 3 px), "Shine" (white at 0.7 over the top third), "Label" (Theme
--                                             "Button"; Gold: ink 58,34,0; Green: white with the ink outline) and, with
--                                             opts.Price, "Chip" (black at 0.8, right-aligned 7 px in) > "Coin" (the stage
--                                             puts the icon in it), "Price" (Theme "Display"). The attribute Disabled
--                                             (CloudUI.SetDisabled) repaints it grey (stroke 60,64,76, text 176,184,206).
--                                             opts = { Name, Kind = "Gold" | "Green", Text, TextSize, Price, Coin, Phone,
--                                             ZIndex }
--   HatchLook.PillParts(btn) -> { Shadow, Face, Body, Fill, Edge, Shine, Label, Chip, Coin, Price }
--   HatchLook.SizePill(btn, textSize, phone, coin)   a layout's text and coin sizes
--   HatchLook.FitPill(btn, labelW, priceW) -> chipW, fits   the price chip's width (80 / phone 66 at the least, its
--                                             content's when the label needs the room) and whether the label fits
--   HatchLook.SetPillChip(btn, w)             the chip w px wide (0: hidden, the label takes the whole pill)
--   HatchLook.PillIn(parts, k, rise)          the rise: the Face rise x (1 - k) px lower and 1 - k clear, the shadow
--                                             with it (k = 1: in place)
--   HatchLook.Chip(parent, opts) -> TextButton   a small chip: a transparent 44 px tap box drawing a "Pill" (36 px, phone
--                                             32; black at 0.55) with its "Label" (227,233,255). opts = { Name, Text,
--                                             TextSize, Phone, ZIndex }
--   HatchLook.FastChip(parent, opts) -> TextButton   the Fast hatch chip: the Pill navy 11,18,51 at 0.15 with a 44,63,136
--                                             edge, its "Switch" (34 x 18, phone 30 x 16) and "Knob", the "Label"
--   HatchLook.SetFast(chip, on)               the switch Theme.Colors.Good / 44,63,136, the knob's side, attribute On
--   HatchLook.SizeChip(chip, textSize, phone) / HatchLook.SetChipText(chip, text)
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
	INK = rgb(11, 16, 48),
	-- (Task 3) the rarity word (spec 16.15: the gradient / outline shades of c, the letters' pop, the glow behind). The
	-- outline: the mock's SVG stroke (0.12 x size) is centred on the glyph's edge, so 0.06 x size of it shows outside the
	-- glyph; a UIStroke's Thickness is all outside, so 0.06 x size draws the mock's outline (0.12 drew it twice as heavy).
	-- The glow: a halo taller and wider than the word (GlowW x size more, GlowH x size tall, less where the screen's edge
	-- is nearer), its fallback discs' centre about 0.68 clear (GlowA): the mock's blurred 0.5 stroke, never a slab
	WORD = {
		Top = 0.78, Mid = 0.22, Bottom = -0.18, Outline = -0.68, OutlineK = 0.06, OutlineMin = 2, OutlineMax = 6, Spacing = 0.04, Pad = 0.2,
		Stagger = 0.05, Up = 0.12, Down = 0.14, Peak = 1.3, GlowAt = 0.05, GlowIn = 0.2, GlowA = 0.65, GlowW = 1.0, GlowH = 1.8,
		-- the word glow's fallback: three nested capsules, each fading out to its sides (no hard side edge), stacked so
		-- the halo also falls off up and down; at GlowA their centre is about 0.55 clear
		Discs = {
			{ W = 1, H = 1, Rotation = 0, Fade = { { 0, 1 }, { 0.2, 0.93 }, { 0.5, 0.8 }, { 0.8, 0.93 }, { 1, 1 } } },
			{ W = 0.88, H = 0.66, Rotation = 0, Fade = { { 0, 1 }, { 0.2, 0.9 }, { 0.5, 0.72 }, { 0.8, 0.9 }, { 1, 1 } } },
			{ W = 0.74, H = 0.38, Rotation = 0, Fade = { { 0, 1 }, { 0.25, 0.88 }, { 0.5, 0.65 }, { 0.75, 0.88 }, { 1, 1 } } },
		},
	},
	-- the glossy pills (the mock's pillBtn): the face gradients top / middle (at Mid) / bottom, the stroke and text ink
	PILL = {
		Gold = { Top = rgb(255, 224, 138), Mid = rgb(246, 178, 60), Bottom = rgb(223, 143, 38), Edge = rgb(107, 66, 0), Ink = rgb(58, 34, 0) },
		Green = { Top = rgb(124, 240, 162), Mid = rgb(47, 184, 102), Bottom = rgb(29, 138, 74), Edge = rgb(13, 77, 42), Ink = rgb(255, 255, 255), Outline = true },
		Off = { Top = rgb(120, 126, 140), Mid = rgb(102, 108, 122), Bottom = rgb(84, 90, 104), Edge = rgb(60, 64, 76), Ink = rgb(176, 184, 206) },
		MidAt = 0.55, Shadow = rgb(2, 4, 14), ShadowA = 0.5, ShadowY = 7, ShadowIn = 4, Edge = 3, ShineA = 0.7, ShineOffA = 0.88, ShineX = 12, ShineY = 4,
		ShineH = 0.34, ChipA = 0.8, ChipIn = 7, ChipV = 16, ChipW = 80, ChipWPhone = 66, ChipPad = 9, CoinGap = 4, LabelL = 8, LabelGap = 4,
	},
	-- the chips (the mock's chip / fastChip): the pill heights in the 44 px tap box, colours, the switch
	CHIP = {
		H = 36, HPhone = 32, A = 0.55, Ink = rgb(227, 233, 255), Pad = 12, FastBg = rgb(11, 18, 51), FastA = 0.15, FastEdge = rgb(44, 63, 136),
		Edge = 2, EdgePhone = 1.5, SwitchW = 34, SwitchH = 18, SwitchWPhone = 30, SwitchHPhone = 16, SwitchX = 10, Off = rgb(44, 63, 136),
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
		local discs = opts.Discs or K.GLOW.Discs
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

function Glow:Fade(a, seconds, track)
	self.Alpha = a
	local out = {}
	for i, p in ipairs(self.Parts) do
		local goal = 1 - a * (1 - self.Alphas[i])
		if seconds and seconds > 0 then
			out[#out + 1] = tween(p, seconds, { [self.Prop] = goal }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, track)
		else
			p[self.Prop] = goal
		end
	end
	return out
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
-- (Task 3) the rarity word: a TextLabel a glyph popping in turn (or one label), its gradient, outline and glow
----------------------------------------------------------------------
local Word = {}
Word.__index = Word

local function wordLabel(parent, name, text, size, c, z)
	local W = K.WORD
	local l = Theme.Label(text, "Title", { Size = size, Stroke = 1 })
	l.Name = name
	l.TextColor3 = K.WHITE -- (the gradient tints it)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.ZIndex = z
	Util.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, HatchLook.Shade(c, W.Top)), ColorSequenceKeypoint.new(0.5, HatchLook.Shade(c, W.Mid)), ColorSequenceKeypoint.new(1, HatchLook.Shade(c, W.Bottom)),
		}),
		Parent = l,
	})
	Util.Create("UIStroke", { Color = HatchLook.Shade(c, W.Outline), Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = l })
	l.Parent = parent
	return l
end

local function outlineOf(size)
	local W = K.WORD
	return math.max(W.OutlineMin, math.min(W.OutlineMax, math.floor(size * W.OutlineK + 0.5)))
end

function HatchLook.Word(parent, text, rarity, size, opts)
	opts = opts or {}
	local c = HatchLook.RarityColor(rarity)
	local z = opts.ZIndex or parent.ZIndex
	local self = setmetatable({ Text = tostring(text), Size = size, Letters = {}, Measure = opts.Measure, Token = 0, Tw = {} }, Word)
	if opts.Letters then
		self.Frame = frame(parent, opts.Name or "Word", { ZIndex = z })
		self.Glow = HatchLook.Glow(self.Frame, c, { Name = "Glow", Z = z, Discs = K.WORD.Discs })
		self.Glow:SetAlpha(K.WORD.GlowA)
		local i = 0
		for ch in self.Text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			i = i + 1
			local l = wordLabel(self.Frame, "L" .. i, ch, size, c, z + 1)
			l.AnchorPoint = Vector2.new(0.5, 0.5) -- (its pop grows round its middle)
			self.Letters[i] = { Label = l, Char = ch, Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = l }), W = 0 }
		end
	else
		self.Frame = wordLabel(parent, opts.Name or "Word", self.Text, size, c, z)
	end
	self.Frame:SetAttribute("Text", self.Text)
	self:SetSize(size)
	return self
end

function Word:charW(text, size)
	local w = self.Measure and self.Measure(text, size) or nil
	return (type(w) == "number" and w > 0) and w or #text * size * 0.6
end

function Word:Width()
	if #self.Letters == 0 then
		return self:charW(self.Text, self.Size)
	end
	local w = 0
	for _, L in ipairs(self.Letters) do
		w = w + L.W
	end
	return w + K.WORD.Spacing * self.Size * (#self.Letters - 1)
end

function Word:SetSize(size)
	self.Size = size
	local th = outlineOf(size)
	if #self.Letters == 0 then
		self.Frame.TextSize = size
		self.Frame:FindFirstChildOfClass("UIStroke").Thickness = th
		return
	end
	local x, gap, pad = 0, K.WORD.Spacing * size, K.WORD.Pad * size
	for _, L in ipairs(self.Letters) do
		L.W = self:charW(L.Char, size)
		L.Label.TextSize = size
		L.Label:FindFirstChildOfClass("UIStroke").Thickness = th
		-- the glyph's box: its advance + a little room for the outline (never clipped), centred on the advance
		L.Label.Position = UDim2.fromOffset(x + L.W / 2, size / 2)
		L.Label.Size = UDim2.fromOffset(L.W + pad, size)
		x = x + L.W + gap
	end
	self:placeGlow()
end

-- the halo round the word: GlowW x size wider and GlowH x size tall, at most room.Up above / below it and room.Half to
-- either side of its centre (the screen's edges: never off the screen)
function Word:placeGlow()
	if not self.Glow then
		return
	end
	local size, w, room = self.Size, self:Width(), self.Room
	local gw, gh = w + K.WORD.GlowW * size, K.WORD.GlowH * size
	if room then
		gw = math.min(gw, math.max(w, 2 * room.Half))
		gh = math.min(gh, math.max(size, size + 2 * room.Up))
	end
	self.Glow:Place(UDim2.fromOffset(w / 2, size / 2), UDim2.fromOffset(gw, gh))
end

-- room (optional) = { Up = px free above the word's top, Half = px free from its centre to the nearer side }
function Word:Place(cx, y, room)
	local w = self:Width()
	if #self.Letters == 0 then
		w = w + K.WORD.Pad * self.Size
	end
	self.Frame.Position = UDim2.fromOffset(cx - w / 2, y)
	self.Frame.Size = UDim2.fromOffset(w, self.Size)
	if room then
		self.Room = room
		self:placeGlow()
	end
end

function Word:drop()
	self.Token = self.Token + 1
	for tw in pairs(self.Tw) do
		pcall(function()
			tw:Cancel()
		end)
	end
	self.Tw = {}
end

function Word:Pop(startAt, stagger, track)
	self:drop()
	local mine = self.Token
	local W = K.WORD
	startAt = math.max(0, tonumber(startAt) or 0)
	if #self.Letters == 0 then
		self.Frame.Visible = false
		task.delay(startAt, function()
			if self.Token == mine and self.Frame.Parent then
				self.Frame.Visible = true
			end
		end)
		return
	end
	local function play(inst, seconds, goals, direction)
		local tw = tween(inst, seconds, goals, Enum.EasingStyle.Quad, direction, track)
		if tw then
			self.Tw[tw] = true
		end
		return tw
	end
	self.Glow:SetAlpha(0)
	for i, L in ipairs(self.Letters) do
		L.Pop.Scale = 0
		task.delay(startAt + (stagger or W.Stagger) * (i - 1), function()
			if self.Token ~= mine or not L.Pop.Parent then
				return
			end
			local up = play(L.Pop, W.Up, { Scale = W.Peak }, Enum.EasingDirection.Out)
			if up then
				up.Completed:Connect(function(state)
					if state == Enum.PlaybackState.Completed and self.Token == mine and L.Pop.Parent then
						play(L.Pop, W.Down, { Scale = 1 }, Enum.EasingDirection.In)
					end
				end)
			end
		end)
	end
	task.delay(startAt + W.GlowAt, function()
		if self.Token == mine and self.Frame.Parent then
			for _, tw in ipairs(self.Glow:Fade(W.GlowA, W.GlowIn, track)) do
				self.Tw[tw] = true
			end
		end
	end)
end

function Word:Settle()
	self:drop()
	for _, L in ipairs(self.Letters) do
		L.Pop.Scale = 1
	end
	if self.Glow then
		self.Glow:SetAlpha(K.WORD.GlowA)
	end
	if #self.Letters == 0 and self.Frame.Parent then
		self.Frame.Visible = true
	end
end

function Word:Destroy()
	self:drop()
	self.Frame:Destroy()
end

----------------------------------------------------------------------
-- (Task 3) the glossy pills and the small chips of the bottom bar
----------------------------------------------------------------------
local function pillFill(look)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, look.Top), ColorSequenceKeypoint.new(K.PILL.MidAt, look.Mid), ColorSequenceKeypoint.new(1, look.Bottom),
	})
end

function HatchLook.PillParts(btn)
	local face = btn:FindFirstChild("Face")
	local body = face and face:FindFirstChild("Body")
	local chip = face and face:FindFirstChild("Chip")
	return {
		Shadow = btn:FindFirstChild("Shadow"), Face = face, Body = body, Fill = body and body:FindFirstChild("Fill"), Edge = body and body:FindFirstChild("Edge"),
		Shine = face and face:FindFirstChild("Shine"), Label = face and face:FindFirstChild("Label"), Chip = chip, Coin = chip and chip:FindFirstChild("Coin"),
		Price = chip and chip:FindFirstChild("Price"),
	}
end

local function paintPill(btn)
	local p = HatchLook.PillParts(btn)
	local off = btn:GetAttribute("Disabled") == true
	local look = off and K.PILL.Off or (K.PILL[btn:GetAttribute("Kind")] or K.PILL.Gold)
	p.Fill.Color = pillFill(look)
	p.Edge.Color = look.Edge
	p.Label.TextColor3 = look.Ink
	p.Shine.BackgroundTransparency = off and K.PILL.ShineOffA or K.PILL.ShineA
	if p.Price then
		p.Price.TextColor3 = look.Ink
	end
end

function HatchLook.Pill(parent, opts)
	opts = opts or {}
	local P = K.PILL
	local z = opts.ZIndex or 1
	local kind = P[opts.Kind or "Gold"] and (opts.Kind or "Gold") or "Gold"
	local btn = Util.Create("TextButton", {
		Name = opts.Name or "Pill", Text = "", AutoButtonColor = false, Active = true, BorderSizePixel = 0, BackgroundTransparency = 1, ZIndex = z, Parent = parent,
	})
	btn:SetAttribute("Kind", kind)
	local shadow = frame(btn, "Shadow", {
		Position = UDim2.fromOffset(P.ShadowIn, P.ShadowY), Size = UDim2.new(1, -2 * P.ShadowIn, 1, 0), BackgroundColor3 = P.Shadow, BackgroundTransparency = P.ShadowA, ZIndex = z,
	})
	corner(shadow, 0.5)
	local face = Util.Create("CanvasGroup", { Name = "Face", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = btn })
	-- the capsule sits its stroke's width inside the group (a Border stroke draws outside its frame: never clipped)
	local body = frame(face, "Body", { Position = UDim2.fromOffset(P.Edge, P.Edge), Size = UDim2.new(1, -2 * P.Edge, 1, -2 * P.Edge), BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ZIndex = z + 1 })
	corner(body, 0.5)
	Util.Create("UIGradient", { Name = "Fill", Rotation = 90, Color = pillFill(P[kind]), Parent = body })
	stroke(body, P[kind].Edge, P.Edge, 0).Name = "Edge"
	local shine = frame(face, "Shine", { Position = UDim2.fromOffset(P.ShineX, P.ShineY), Size = UDim2.new(1, -2 * P.ShineX, P.ShineH, 0), BackgroundColor3 = K.WHITE, BackgroundTransparency = P.ShineA, ZIndex = z + 2 })
	corner(shine, 0.5)
	local label = Theme.Label(opts.Text or "", "Button", { Size = opts.TextSize or 22, Stroke = 1 })
	label.Name = "Label"
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = z + 3
	label.Parent = face
	if P[kind].Outline then
		Theme.TextOutline(label, 2, K.INK, 0)
	end
	if opts.Price then
		local chip = frame(face, "Chip", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -P.ChipIn, 0.5, 0), BackgroundColor3 = K.BLACK, BackgroundTransparency = P.ChipA, ZIndex = z + 2 })
		corner(chip, 0.5)
		frame(chip, "Coin", { AnchorPoint = Vector2.new(0, 0.5), ZIndex = z + 3 })
		local price = Theme.Label("", "Display", { Size = 20, Stroke = 1 })
		price.Name = "Price"
		price.TextXAlignment = Enum.TextXAlignment.Center
		price.ZIndex = z + 3
		price.Parent = chip
	end
	btn:GetAttributeChangedSignal("Disabled"):Connect(function()
		paintPill(btn)
	end)
	paintPill(btn)
	HatchLook.SizePill(btn, opts.TextSize or 22, opts.Phone, opts.Coin)
	HatchLook.SetPillChip(btn, opts.Price and (opts.Phone and P.ChipWPhone or P.ChipW) or 0)
	return btn
end

function HatchLook.SizePill(btn, textSize, phone, coin)
	local P = K.PILL
	local p = HatchLook.PillParts(btn)
	p.Label.TextSize = textSize
	btn:SetAttribute("Phone", phone == true)
	if p.Price then
		coin = coin or (phone and 20 or 30)
		p.Price.TextSize = math.max(15, textSize - 2)
		p.Coin.Size = UDim2.fromOffset(coin, coin)
		p.Coin.Position = UDim2.new(0, P.ChipPad, 0.5, 0)
		p.Price.Position = UDim2.fromOffset(P.ChipPad + coin + P.CoinGap, 0)
		p.Price.Size = UDim2.new(1, -(2 * P.ChipPad + coin + P.CoinGap), 1, 0)
	end
end

-- the chip's width for a price priceW px wide: the mock's 80 / 66 at the least, only its content's when the label needs
-- the room; fits = the label (labelW px) fits beside it
function HatchLook.FitPill(btn, labelW, priceW)
	local P = K.PILL
	local p = HatchLook.PillParts(btn)
	local coin = p.Coin and p.Coin.Size.X.Offset or 0
	local content = 2 * P.ChipPad + coin + P.CoinGap + priceW
	local least = btn:GetAttribute("Phone") == true and P.ChipWPhone or P.ChipW
	local room = btn.Size.X.Offset - P.ChipIn - P.LabelL - P.LabelGap
	local w = math.max(content, least)
	if labelW > room - w then
		w = content
	end
	return math.ceil(w), labelW <= room - w
end

function HatchLook.SetPillChip(btn, w)
	local P = K.PILL
	local p = HatchLook.PillParts(btn)
	if p.Chip then
		p.Chip.Visible = w > 0
		p.Chip.Size = UDim2.new(0, math.max(0, w), 1, -P.ChipV)
	end
	if w > 0 then
		p.Label.Position = UDim2.fromOffset(P.LabelL, 0)
		p.Label.Size = UDim2.new(1, -(P.LabelL + P.LabelGap + w + P.ChipIn), 1, 0)
	else
		p.Label.Position = UDim2.fromOffset(P.LabelL, 0)
		p.Label.Size = UDim2.new(1, -2 * P.LabelL, 1, 0)
	end
end

function HatchLook.PillIn(parts, k, rise)
	k = math.max(0, math.min(1, k))
	parts.Face.Position = UDim2.fromOffset(0, (1 - k) * (rise or 0))
	parts.Face.GroupTransparency = 1 - k
	parts.Shadow.BackgroundTransparency = 1 - k * (1 - K.PILL.ShadowA)
end

function HatchLook.Chip(parent, opts)
	opts = opts or {}
	local C = K.CHIP
	local z = opts.ZIndex or 1
	local btn = Util.Create("TextButton", {
		Name = opts.Name or "Chip", Text = "", AutoButtonColor = false, Active = true, BorderSizePixel = 0, BackgroundTransparency = 1, ZIndex = z, Parent = parent,
	})
	local pill = frame(btn, "Pill", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = K.BLACK, BackgroundTransparency = C.A, ZIndex = z })
	corner(pill, 0.5)
	local label = Theme.Label(opts.Text or "", "Label", { Size = opts.TextSize or 18, Stroke = 1 })
	label.Name = "Label"
	label.TextColor3 = C.Ink
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = z + 1
	label.Parent = pill
	HatchLook.SizeChip(btn, opts.TextSize or 18, opts.Phone)
	return btn
end

function HatchLook.FastChip(parent, opts)
	opts = opts or {}
	local C = K.CHIP
	local z = opts.ZIndex or 1
	local btn = HatchLook.Chip(parent, { Name = opts.Name or "FastHatch", Text = "Fast hatch", TextSize = opts.TextSize, Phone = opts.Phone, ZIndex = z })
	local pill = btn:FindFirstChild("Pill")
	pill.BackgroundColor3 = C.FastBg
	pill.BackgroundTransparency = C.FastA
	stroke(pill, C.FastEdge, opts.Phone and C.EdgePhone or C.Edge, 0).Name = "Edge"
	local sw = frame(pill, "Switch", { AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.Off, BackgroundTransparency = 0, ZIndex = z + 1 })
	corner(sw, 0.5)
	corner(frame(sw, "Knob", { AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ZIndex = z + 2 }), 0.5)
	HatchLook.SizeChip(btn, opts.TextSize or 18, opts.Phone)
	HatchLook.SetFast(btn, false)
	return btn
end

function HatchLook.SizeChip(btn, textSize, phone)
	local C = K.CHIP
	local pill = btn:FindFirstChild("Pill")
	local label = pill:FindFirstChild("Label")
	pill.Size = UDim2.new(1, 0, 0, phone and C.HPhone or C.H)
	label.TextSize = textSize
	local sw = pill:FindFirstChild("Switch")
	if sw then
		local w, h = phone and C.SwitchWPhone or C.SwitchW, phone and C.SwitchHPhone or C.SwitchH
		sw.Position = UDim2.new(0, C.SwitchX, 0.5, 0)
		sw.Size = UDim2.fromOffset(w, h)
		sw:FindFirstChild("Knob").Size = UDim2.fromOffset(h - 4, h - 4)
		local edge = pill:FindFirstChild("Edge")
		if edge then
			edge.Thickness = phone and C.EdgePhone or C.Edge
		end
		-- the label centred in the room right of the switch
		label.Position = UDim2.fromOffset(C.SwitchX + w + 4, 0)
		label.Size = UDim2.new(1, -(C.SwitchX + w + 4 + C.SwitchX), 1, 0)
		HatchLook.SetFast(btn, btn:GetAttribute("On") == true)
	else
		label.Position = UDim2.fromOffset(C.Pad, 0)
		label.Size = UDim2.new(1, -2 * C.Pad, 1, 0)
	end
end

function HatchLook.SetChipText(btn, text)
	local pill = btn and btn:FindFirstChild("Pill")
	local label = pill and pill:FindFirstChild("Label")
	if label then
		label.Text = text
	end
end

function HatchLook.SetFast(btn, on)
	local pill = btn and btn:FindFirstChild("Pill")
	local sw = pill and pill:FindFirstChild("Switch")
	if not sw then
		return
	end
	local knob = sw:FindFirstChild("Knob")
	sw.BackgroundColor3 = on and Theme.Colors.Good or K.CHIP.Off
	if knob then
		knob.Position = on and UDim2.new(1, -knob.Size.X.Offset - 2, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	end
	btn:SetAttribute("On", on == true)
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
