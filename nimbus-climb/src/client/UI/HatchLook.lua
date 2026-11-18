-- HatchLook (client UI; roll-look, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.15 "Roll look A+B", the
-- owner's pick A "Showcase" + B's colour tell): the dressed pieces of the egg stage as builders and small handles with no
-- stage state of their own. client/UI/EggStage keeps the phases and calls these from its builders, layout and phase runner.
-- Every rarity colour comes from Shade(RarityColor(r), t) (the pitch mock's `shade`).
--
--   HatchLook.Shade(c, t) -> Color3           t >= 0: c towards white by t; t < 0: towards black by -t
--   HatchLook.RarityColor(rarity) -> Color3   Config.Rarities' colour; Secret the readable violet 180,150,255; an unknown
--                                             rarity the neutral 168,178,194
--   HatchLook.Order(rarity) -> number         Config.Rarities' Order (1 when unknown)
--   (kit-b U9-2b, finding 15) the chrome is the Signboard kit's: square flat blocks (CloudUI.SignBlock: a face, a mitred
--   "SignEdge" and a darker "Lip"), cream / wood / navy, no gloss, shine, drop shadow or soft glow. The stage's art (the
--   plinth, the rays, the backlight, the FX, the eggs) keeps its roll-look softness and carries attribute Art = "Hatch".
--   HatchLook.Card(cell, geo) -> card         skins a strip cell (a Frame, its egg inside) as a stone block: the face
--                                             Theme.Sign.Tile, the cell's own UIStroke the mitred wood "SignEdge" (geo.Edge
--                                             px), no corner. geo = { W, H, Edge, Plate, Word, Lite, Phone, Z }. Not Lite: the
--                                             "Plate" band (geo.Plate px) along the bottom holding the upper-case "Word";
--                                             Lite (x3): a "Lip" band only. card = { Frame, Plate, PlateText, Rim }. Adds only
--                                             the Plate and its Word to the cell (Lite: the Lip; the edge is the cell's own
--                                             stroke, no shadow beside it): spec 16.15 "Budgets"
--   HatchLook.SetCard(card, rarity|false, state)   state "Idle" | "Landed" | "Dim": the face Tile / the Selected cream /
--                                             the sunk Well; the lip in RarityColor(r), the plate in Theme.ReadableFace(
--                                             RarityColor(r), 4.5) with its word in the ink it returns (StoneLip without a
--                                             rarity), 0.3 clear when Dim
--   HatchLook.ShowCard(card, cx, cy) / HideCard(card)   places a card by its centre (AnchorPoint 0.5: its pop grows round
--                                             the middle), or hides it
--   HatchLook.DropCard(card)                  destroys the cell
--   HatchLook.LandPop(card, fast, track) -> { tween }   the land: a UIScale "Pop" on the card 1 -> 1.15 (0.1 s Quad Out)
--                                             -> 1.09 (0.15 s Quad InOut; Fast 0.05 / 0.07) and one white "Sweep" (a hard-
--                                             edged flat band, Offset -1 -> 1 in 0.3 s, Fast 0.12; destroyed after). Every
--                                             tween it plays (the chained one too) goes into `track`
--   HatchLook.SetPop(card, scale)             the pop at rest (a resize cancelled its tweens)
--   HatchLook.Window(parent, pointer, opts) -> win   the gold winner window on the strip's existing "Pointer" frame (its
--                                             root): children Window (the square gold frame: a mitred stroke), NotchTop /
--                                             NotchBottom (stepped pixel pointers: a 5-unit row on the frame's edge, child
--                                             rows Row2 / Row3 of 3 and 1 units stepping in; a unit = Notch / 4 px), a
--                                             UIScale "Bounce"; beside it in `parent`, DimL / DimR darken the track outside
--                                             the window after the land. opts = { Phone, Gold, Stroke, Notch (0 = none),
--                                             Track (the tween set) }.
--                                             win:Place(x, y, w, h, trackW, trackH)  the window's box (the landed cell's + pad)
--                                             win:Style(opts)            a layout's stroke and notches (a resize)
--                                             win:Tell(color, seconds)   every gold part turns `color` (attribute Tell = true)
--                                             win:Reset()                gold again (Tell = nil)
--                                             win:Bounce(seconds) / win:Rest()   a 1.08 -> 1 Back Out pop / at rest
--                                             win:SetDim(k)              the dims at k (0 = clear .. 1 = dark), per frame
--                                             win:DropGlow()             nothing (no glow any more; kept for the rise's call)
--                                             win:DropDims()             the dims go (an x3 strip at the rise: the budget)
--                                             win:Destroy()
--   HatchLook.TrackFades(track, color) -> FadeL, FadeR   the strip's square ends: `color` fading to clear over the cards
--                                             (a UIGradient "Fade"; EggStage places them over the card band)
--   HatchLook.KEEP / HatchLook.ROBLOX         the ScreenGuis the stage never switches off: KEEP = spec 16.15's list (the
--                                             stage, toasts, the cursor hint, the tooltip, the Shop under the stage, the dev
--                                             tools, the main menu, the loading screen); ROBLOX = Roblox's own PlayerGui guis
--                                             (TouchGui: MenuController.SetTouchHidden owns the thumbstick; Freecam,
--                                             BubbleChat)
--   HatchLook.HideHud(playerGui, own) -> { ScreenGui }   switches off every Enabled ScreenGui in PlayerGui outside KEEP /
--                                             ROBLOX and not `own`, and remembers it
--   HatchLook.HideOne(gui)                    the same rule for one gui (PlayerGui.ChildAdded while the stage shows)
--   HatchLook.RestoreHud()                    switches each remembered gui back on when it is still in PlayerGui, still
--                                             off and not marked HudKeepOff, then forgets them. A remembered gui someone
--                                             switches on meanwhile is forgotten at once (theirs again: never fought, never
--                                             switched on by us later). (review round 1) An owner that switches its gui off
--                                             while the stage has it off writes the same value, which the stage cannot see:
--                                             it sets the attribute HudKeepOff (HatchLook.KEEP_OFF) = true for "keep it off"
--                                             (MovementController's MobileControls on a death), false when it shows it again
--   HatchLook.HiddenCount() -> number         how many guis are remembered (tests)
--   (Task 2: the opening)
--   HatchLook.Plinth(box, rarity, phone, opts) -> plinth   the flat lit disc the hero egg, its halves and the pet stand on,
--                                             drawn in the existing "Pedestal<j>" layout box (anchored at its top centre:
--                                             the egg's foot), every part an ellipse (review round 2: ImageLabels of the
--                                             built-in disc Metrics.DISC, tinted; a capsule frame read as a loading bar):
--                                             "Top" (0.85 of the box tall, centred ON the box's top edge so the egg stands
--                                             in its middle; navy gradient 52,72,154 -> 20,29,82), "Rim" (the Top's disc
--                                             3 px / phone 2 larger behind it, attribute Thickness), "Side" (the disc's
--                                             thickness: the Top's ellipse Metrics.PLINTH.Band = 0.15 of the box lower, a
--                                             vertical gradient 38,56,132 darkening to 10,17,52 over the band under the
--                                             Top's front edge, dark along its middle line), "Wall" (the band's straight
--                                             ends between the two centre lines at the box's ends, dark there), "Edge"
--                                             (the Side's disc 2 px / phone 1.5 larger behind it at 0.3: the lit lower
--                                             rim), "Ring" + "Cover" (an inner ring on the Top,
--                                             0.76 x 0.7 of it at 0.45: a disc under a Cover disc 2 / 1.5 px smaller in the
--                                             Top's colours over its span), "Glow1..2" (HatchLook.Glow: a soft halo round
--                                             the disc) and a UIScale "Pop" on the box. Top + Band = the box: no drum, no
--                                             puffs, no bars (a5a38ac). Neutral (Shade(Metrics.PLINTH.Neutral, .25) rim,
--                                             .4 ring, .2 edge and glow) until Tint. 17 instances (x3, one halo disc: 14)
--                                             opts = { Track (the tween set), Glows (1..2, default 2), Ring (false = none) }
--                                             plinth:SetAlpha(a)        0 = hidden .. 1 = shown (the rise's fade, per frame)
--                                             plinth:Tint(color, s)     rim Shade(c, .25), ring Shade(c, .4), edge and glow
--                                                                       Shade(c, .2) in s seconds (0: at once); remembered
--                                                                       for Rest
--                                             plinth:Reset()            neutral again;  plinth:Rest()  Pop 1, shown, colour
--                                                                       snapped (a resize cancelled the tweens)
--                                             plinth:FitGlow(share)     the halo at most share x the box wide (the screen's
--                                                                       edge: a portrait x3's outer columns)
--   HatchLook.PlinthLip(box, lip)             the Top's box (and its Rim round it): the disc centred on the box's top
--                                             edge, or (lip = true: a phone's reveal) the whole box, the 12 px lip
--                                             (EggStage's H.pedLook hides the other parts)
--   HatchLook.IMAGES                          the three optional images, TextureIds keys: Rays "hatch_rays" (EggStage passes
--                                             it to HatchFx.Rays: one ImageLabel fan), Glow "hatch_glow" (HatchLook.Glow: the
--                                             plinth's and the word's glows; EggStage's backlight), Sparkle "hatch_sparkle"
--                                             (HatchFx.Pool's sparks); none uploaded: their frame fallbacks draw (HatchFx's
--                                             ray wedges and spark squares, stacked round glows)
--   HatchLook.Image(key) -> "rbxassetid://<id>" | nil   the key's shared/TextureIds id when it is a number > 0
--                                             (HatchLook._Textures: a test table in place of the module; false = the module)
--   HatchLook.EGG_IMAGES[rarity] = "egg_card_<rarity>"   (egg-cards, spec 16.18) the strip cards' egg pictures (Cycles
--                                             renders of the real Blender eggs, blender/textures/build_egg_cards.py; not
--                                             uploaded yet); HatchLook.EggImage(rarity) -> "rbxassetid://<id>" | nil;
--                                             HatchLook.EggImages() -> how many of the seven have an id;
--                                             HatchLook.EggPictures() -> true only when all seven have one: the cards
--                                             draw the pictures all together or not at all (review round 1: never a mix
--                                             in a strip, and a cell never holds a painted egg and a picture);
--                                             HatchLook.PreloadEggImages() -> n: ContentProvider:PreloadAsync of the
--                                             seven urls not yet sent (a spawned thread, once per url; 0 when
--                                             EggPictures() is false); Metrics.EGG_PIC.Fill = 0.9, the egg's share of
--                                             its square picture
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
--                                             (kit-b U9-2b: the title look's face, white under a UIGradient "Bands" of three
--                                             hard bands Shade(c, .45) / c / Shade(c, -.2), one UIStroke Shade(c, -.68) of
--                                             clamp(round(size x 0.06), 2, 6) px, a UIScale "Pop") 0.04 x size apart, no
--                                             glow; no Letters: one such TextLabel (an x3 phone column, the crack word).
--                                             opts = { Letters, Name, ZIndex, Measure = function(text, size) -> px (the
--                                             stage's real text widths) }
--                                             word:Width() -> px            word:Place(cx, y)   (y = the top)
--                                             word:SetSize(size)            word:Destroy()
--                                             word:SetRarity(rarity)        the bands and the outline re-coloured
--                                             word:SetText(text)            a one-label word's text (+ attribute Text)
--                                             word:Pop(startAt, stagger, track)   letter i (from 0) 0 -> 1.3 (0.12 s Quad
--                                                 Out) -> 1 (0.14 s Quad In) at startAt + stagger x i (task.delay; the
--                                                 tweens go into `track`); one label: hidden until startAt
--                                             word:Settle()   every letter at 1, pending pops dropped (a resize mid-chain)
--   HatchLook.Pill(parent, opts) -> TextButton   a kit B plank named opts.Name (transparent tap box, Text ""): "Face" (a
--                                             CanvasGroup: the rise and fade) > "Body" (the block, CloudUI.SignBlock: Gold
--                                             the "Selected" look, Green the "Primary" grass; its wood "SignEdge" 3 px inside
--                                             the group and its "Lip" 5 px), "Label" (Theme "Button", the look's ink) and,
--                                             with opts.Price, "Chip" (the stone price tag, edge 2, lip 3, right-aligned 7 px
--                                             in) > "Coin" (the stage puts the icon in it), "Price" (Theme "Display",
--                                             brown). The attribute Disabled (CloudUI.SetDisabled) paints the sunk "Off"
--                                             well with muted words. A press sinks the face onto its lip (PillState).
--                                             opts = { Name, Kind = "Gold" | "Green", Text, TextSize, Price, Coin, Phone,
--                                             ZIndex }
--   HatchLook.PillParts(btn) -> { Face, Body, Lip, Edge, Label, Chip, Coin, Price }
--   HatchLook.PillState(btn, "Press" | "Rest")   the press: the lip 2 px, the words and the tag 3 px lower; Rest: back
--   HatchLook.SizePill(btn, textSize, phone, coin)   a layout's text and coin sizes (coin default 27, phone 18)
--   HatchLook.FitPill(btn, labelW, priceW, parts?) -> chipW, fits   the price tag's width (80 / phone 66 at the least,
--                                             its content's when the label needs the room) and whether the label fits
--   HatchLook.SetPillChip(btn, w, parts?)     the tag w px wide (0: hidden, the label takes the whole face). parts: the
--                                             button's PillParts already looked up (review round 2: no lookups per refresh)
--   HatchLook.PillIn(parts, k, rise)          the rise: the Face rise x (1 - k) px lower and 1 - k clear (k = 1: in place)
--   HatchLook.Chip(parent, opts) -> TextButton   a small chip: a transparent 44 px tap box drawing a "Pill" (36 px, phone
--                                             32): the navy SignBlock (its gold-lip edge 2 px, lip 3) with its cream
--                                             "Label". opts = { Name, Text, TextSize, Phone, ZIndex }
--   HatchLook.FastChip(parent, opts) -> TextButton   the Fast hatch chip: the navy chip with its square "Switch" (a slot
--                                             with a mitred "SlotEdge") and square stone "Knob", the "Label"
--   HatchLook.SetFast(chip, on)               the switch grass / the navy slot, the knob's side, attribute On
--   HatchLook.SizeChip(chip, textSize, phone) / HatchLook.SetChipText(chip, text)
--   HatchLook.ChipRoom(w, fast, phone) -> px  the label's width in a chip w px wide (its block's edge, the pad or the
--                                             switch taken out): the room a caller measures a chip's words against
--   HatchLook.Tag(parent, name, text, look, opts) -> tag, words   a flat reveal tag (NEW!, EVOLVED): a SignBlock in the
--                                             CloudUI.SignLooks `look` (edge 2, lip 3) with its "Text" (Theme "Tag") above
--                                             the lip; square, never tilted. opts = { ZIndex, Visible, TextSize }
--
-- Plain Lua 5.1-compatible syntax only. Text goes through Theme roles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Theme = require(Shared:WaitForChild("Theme"))
local CloudUI = require(script.Parent:WaitForChild("CloudUI")) -- (kit-b U9-2b) CloudUI.SignBlock / SignLooks: the kit's blocks

local HatchLook = {}

local rgb = Color3.fromRGB
local Sign = Theme.Sign
local K = {
	WHITE = Color3.new(1, 1, 1),
	BLACK = Color3.new(0, 0, 0),
	SECRET = rgb(180, 150, 255), -- Secret's own colour is near black: the readable violet (EggStage.Metrics.SECRET_TEXT)
	NEUTRAL = rgb(168, 178, 194),
	GOLD = rgb(242, 182, 68), -- the window's rest gold = EggStage.Metrics.GOLD
	NOTCH = rgb(255, 215, 106),
	DIM = rgb(4, 6, 22),
	DIM_A = 0.5, -- the dims' darkest (transparency 1 - DIM_A)
	POP = { Peak = 1.15, Rest = 1.09, Up = 0.1, Down = 0.15, UpFast = 0.05, DownFast = 0.07 },
	SWEEP = { Normal = 0.3, Fast = 0.12, Band = 0.45, Rotation = 18 },
	BOUNCE = 1.08,
	-- (review round 2) the plinth's ellipses are Roblox's built-in white disc (client content shipped with every client,
	-- not an upload: tools/check.mjs allows rbxasset://) stretched to each part's box and tinted: a true ellipse. A UICorner
	-- on a wide frame is a capsule with a long straight run, and the capsule plinth (with a capsule ring inside it) read
	-- as a loading bar under the pet
	DISC = "rbxasset://textures/whiteCircle.png",
	-- (Task 2) the plinth, in shares of its box (1.1 x / 0.24 x the egg, 16.4), the mock's platA: the Top ellipse Top of
	-- the box tall, centred on the box's top edge (the egg's foot), its Rim a disc Rim px larger behind it; the Side the
	-- Top's ellipse moved Band of the box down (the disc's thickness: a band under the Top's front edge, shaded darker
	-- downward) with the Wall (the band's straight ends between the two centre lines: a cylinder's edge, the mock's side)
	-- and the Edge behind it (Edge px larger, Shade(c, .2) at EdgeA: the mock's lit lower rim); the inner Ring (RingW x
	-- RingH of the Top, Shade(c, .4) at RingA) drawn as a disc under a Cover disc Ring px smaller that carries the Top's own
	-- gradient over its span (a stroke on an ellipse); the halo centred GlowY under the edge (the mock's 16 px under a 60 px
	-- disc), 1.6 x the box wide and 1.9 x the Top tall. Top + Band = 1: the disc stays inside its box (a flat disc, never
	-- the old drum); 1.1 / (0.24 x 0.85) = a 5.4 : 1 ellipse (the mock's 5 : 1 with a thicker side)
	PLINTH = {
		Top = 0.85, Band = 0.15, GlowY = 0.85 * 16 / 60, GlowW = 1.6, GlowH = 1.9 * 0.85, Rim = 3, RimPhone = 2,
		RingW = 0.76, RingH = 0.7, RingA = 0.45, Ring = 2, RingPhone = 1.5, Edge = 2, EdgePhone = 1.5, EdgeA = 0.3,
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
	-- (kit-b U9-2b) the letters wear the title look (Theme.StyleTitle's T1 face): white under HARD bands of the rarity's
	-- tones (Shade(c, Top) to BandA, c itself to BandB, Shade(c, Bottom) under it: no blend, the pixel kit's stepped
	-- shading) with ONE outline Shade(c, Outline); no glow halo (kit B: no glow)
	WORD = {
		Top = 0.45, Mid = 0, Bottom = -0.2, BandA = 0.45, BandB = 0.8, Outline = -0.68, OutlineK = 0.06, OutlineMin = 2, OutlineMax = 6, Spacing = 0.04, Pad = 0.2,
		Stagger = 0.05, Up = 0.12, Down = 0.14, Peak = 1.3,
	},
	-- (kit-b U9-2b) the bottom bar's planks: kit B blocks (CloudUI.SignBlock) in a CanvasGroup "Face" that rises and fades
	-- in; Kind -> its sign look (Gold: the gold block, brown words; Green: the grass block, the stage's one green action;
	-- disabled: the sunk Off well); Edge / Lip px (the kit's 3 / 5), the press leaves PressLip of the lip (the face sinks
	-- onto it); the price tag a stone block (TagEdge / TagLip) ChipIn px inside the face's right edge, ChipV px shorter than
	-- the face, its coin and price ChipPad / CoinGap apart; the label LabelL from the face's left, LabelGap before the tag
	PILL = {
		Look = { Gold = "Selected", Green = "Primary" }, Edge = 3, Lip = 5, PressLip = 2, TagEdge = 2, TagLip = 3,
		ChipIn = 7, ChipV = 14, ChipW = 80, ChipWPhone = 66, ChipPad = 9, CoinGap = 4, LabelL = 8, LabelGap = 4,
	},
	-- (kit-b U9-2b) the chips (Skip, Fast hatch): a navy block (the kit's navy sign: gold-lip edge, darker lip) H / HPhone
	-- tall in the 44 px tap box, cream words; Fast hatch's switch a square slot (navy lip, its lit edge) with a square
	-- stone knob, the slot grass when on
	CHIP = {
		H = 36, HPhone = 32, Pad = 12, Edge = 2, Lip = 3, Ink = Sign.Stone,
		SwitchW = 34, SwitchH = 18, SwitchWPhone = 30, SwitchHPhone = 16, SwitchX = 10, Slot = Sign.NavyLip, SlotEdge = Sign.NavyTop, On = Sign.Grass, OnEdge = Sign.GrassLip, Knob = Sign.Stone,
	},
	-- (kit-b U9-2b) the strip's cards: stone blocks (Sign.Tile; the landed card Sign.Selected, the dimmed ones the sunk
	-- Well) in a mitred wood edge Edge px thick, the rarity's colour on the plate along the bottom (a lite x3 card: a Lip
	-- px lip), the word in the ink that reads on it (the plate moved to reach Need:1, Theme.ReadableFace); the window's
	-- pixel notches: three rows Unit px tall stepping in
	CARD = { Edge = 3, EdgePhone = 2, Lip = 5, LipPhone = 4, DimText = 0.3, Need = 4.5 },
	-- (egg-cards, spec 16.18) the card eggs' pictures (blender/textures/build_egg_cards.py): the egg's projected box is Fill
	-- of the square picture's height, centred; a cell draws the picture (egg px) / Fill square on the painted egg's box
	EGG_PIC = { Fill = 0.9 },
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
-- the strip cards (kit-b U9-2b: stone blocks on the navy rail)
----------------------------------------------------------------------
function HatchLook.Card(cell, geo)
	local W, H = geo.W, geo.H
	local C = K.CARD
	local z = geo.Z or cell.ZIndex
	local card = { Frame = cell, Geo = geo, Lite = geo.Lite == true }
	cell.AnchorPoint = Vector2.new(0.5, 0.5)
	cell.BackgroundColor3 = Sign.Tile
	cell.BackgroundTransparency = 0
	for _, c in ipairs(cell:GetChildren()) do
		if c:IsA("UICorner") or c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	-- the cell's own stroke is the block's mitred wood edge
	local rim = cell:FindFirstChildOfClass("UIStroke") or stroke(cell, Sign.Wood, 3)
	rim.Name = "SignEdge"
	rim.Color = Sign.Wood
	rim.Transparency = 0
	rim.LineJoinMode = Enum.LineJoinMode.Miter
	rim.Thickness = geo.Edge or (geo.Phone and C.EdgePhone or C.Edge)
	card.Rim = rim
	if card.Lite then
		-- (an x3 card: the rarity's colour on its lip only, the x3 budget)
		local lip = geo.Phone and C.LipPhone or C.Lip
		card.Plate = frame(cell, "Lip", {
			Position = UDim2.fromOffset(0, H - lip), Size = UDim2.new(1, 0, 0, lip), BackgroundColor3 = Sign.StoneLip, BackgroundTransparency = 0, ZIndex = z + 1,
		})
	else
		-- the plate: the card's lip band in the rarity's colour, the rarity's word on it
		local ph = geo.Plate or 30
		card.Plate = frame(cell, "Plate", {
			Position = UDim2.fromOffset(0, H - ph), Size = UDim2.new(1, 0, 0, ph), BackgroundColor3 = Sign.StoneLip, BackgroundTransparency = 0, ZIndex = z + 1,
		})
		local word = Theme.Label("", geo.Phone and "Label" or "Heading", { Size = geo.Word or 18 })
		word.Name = "Word"
		word.Size = UDim2.fromScale(1, 1)
		word.TextColor3 = Sign.Text
		word.TextXAlignment = Enum.TextXAlignment.Center
		word.ZIndex = z + 2
		word.Parent = card.Plate
		card.PlateText = word
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
	-- the face: stone, the landed card the selected face, the others sunk once the strip has landed
	cell.BackgroundColor3 = (state == "Landed" and Sign.Selected) or (dim and Sign.Well) or Sign.Tile
	cell.BackgroundTransparency = 0
	card.Plate.BackgroundColor3 = c or Sign.StoneLip
	if card.PlateText then
		-- (U9-2b review) the word's plate is the rarity's colour moved the least it takes for its ink to read at 4.5:1 (a
		-- plate word is under 18 px on most screens): Epic's violet two steps lighter under the brown ink, the rest as is
		local face, ink = Sign.StoneLip, Sign.Text
		if c then
			face, ink = Theme.ReadableFace(c, K.CARD.Need)
		end
		card.Plate.BackgroundColor3 = face
		card.PlateText.Text = c and string.upper(rarity) or ""
		card.PlateText.TextColor3 = ink
		card.PlateText.TextTransparency = dim and K.CARD.DimText or 0
	end
end

function HatchLook.ShowCard(card, cx, cy)
	card.Frame.Position = UDim2.fromOffset(cx, cy)
	card.Frame.Visible = true
end

function HatchLook.HideCard(card)
	card.Frame.Visible = false
end

function HatchLook.DropCard(card)
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
	-- one shine sweep across the card (the clutter cap: one, at the land); (kit-b U9-2b) a flat band with hard edges, no
	-- soft falloff (the pixel look: no blur)
	local sw = K.SWEEP
	local sweep = frame(card.Frame, "Sweep", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ZIndex = card.Frame.ZIndex + 4 })
	local band = Util.Create("UIGradient", {
		Name = "Sweep", Rotation = sw.Rotation, Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.4201, sw.Band),
			NumberSequenceKeypoint.new(0.58, sw.Band), NumberSequenceKeypoint.new(0.5801, 1), NumberSequenceKeypoint.new(1, 1),
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

-- (kit-b U9-2b) a notch is a pixel pointer: its own frame the widest row (5 units wide) on the window's edge, two child
-- rows (3 units, 1 unit) stepping in towards the card; a unit is a quarter of the notch size, whole px
local function placeNotch(notch, n, i, edge)
	local u = math.max(1, math.floor(n / 4 + 0.5))
	local down = i == 1 -- the top notch points down into the window, the bottom one up
	notch.AnchorPoint = Vector2.new(0.5, down and 0 or 1)
	notch.Position = UDim2.new(0.5, 0, i - 1, down and -edge or edge)
	notch.Size = UDim2.fromOffset(5 * u, u)
	for r, row in ipairs({ notch:FindFirstChild("Row2"), notch:FindFirstChild("Row3") }) do
		row.Position = UDim2.fromOffset(r * u, (down and 1 or -1) * r * u)
		row.Size = UDim2.fromOffset((5 - 2 * r) * u, u)
	end
	notch.Visible = n > 0
end

function HatchLook.Window(parent, pointer, opts)
	opts = opts or {}
	local phone = opts.Phone == true
	local self = setmetatable({}, Win)
	self.Gold = opts.Gold or K.GOLD
	self.Track = opts.Track
	self.Root = pointer
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.BackgroundTransparency = 1
	for _, c in ipairs(pointer:GetChildren()) do
		c:Destroy() -- (the old 6 px bar's corner)
	end
	local z = pointer.ZIndex
	self.Scale = Util.Create("UIScale", { Name = "Bounce", Scale = 1, Parent = pointer })
	-- (kit-b U9-2b) a square gold frame, mitred, no soft glow round it
	self.Window = frame(pointer, "Window", { Size = UDim2.fromScale(1, 1), ZIndex = z + 1 })
	self.WinStroke = stroke(self.Window, self.Gold, opts.Stroke or (phone and 3 or 4), 0)
	self.WinStroke.LineJoinMode = Enum.LineJoinMode.Miter
	self.NotchN = opts.Notch or (phone and 10 or 16)
	self.Notches = {}
	for i, name in ipairs({ "NotchTop", "NotchBottom" }) do
		local notch = frame(pointer, name, { BackgroundColor3 = K.NOTCH, BackgroundTransparency = 0, ZIndex = z + 2 })
		for _, row in ipairs({ "Row2", "Row3" }) do
			frame(notch, row, { BackgroundColor3 = K.NOTCH, BackgroundTransparency = 0, ZIndex = z + 2 })
		end
		placeNotch(notch, self.NotchN, i, self.WinStroke.Thickness)
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

-- (kit-b U9-2b: the window has no soft glow any more) kept for the rise's call
function Win:DropGlow() end

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

-- the sizes of a layout (a resize): the frame's stroke, the notches (0 = none); (kit-b U9-2b) square: no corner, no glow
function Win:Style(opts)
	if opts.Stroke then
		self.WinStroke.Thickness = opts.Stroke
	end
	if opts.Notch then
		self.NotchN = opts.Notch
	end
	for i, notch in ipairs(self.Notches) do
		placeNotch(notch, self.NotchN, i, self.WinStroke.Thickness)
	end
end

function Win:paint(color, seconds)
	local out = {}
	local parts = { { self.WinStroke, "Color" } }
	for _, notch in ipairs(self.Notches) do
		parts[#parts + 1] = { notch, "BackgroundColor3" }
		for _, row in ipairs(notch:GetChildren()) do
			parts[#parts + 1] = { row, "BackgroundColor3" }
		end
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
	for _, notch in ipairs(self.Notches) do
		notch.BackgroundColor3 = K.NOTCH
		for _, row in ipairs(notch:GetChildren()) do
			row.BackgroundColor3 = K.NOTCH
		end
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

-- (kit-b U9-2b) square ends: the rail's own flat navy fading out over the cards ("Fade": a flat colour, no gloss)
function HatchLook.TrackFades(track, color)
	local out = {}
	for i, name in ipairs({ "FadeL", "FadeR" }) do
		local f = frame(track, name, { BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = 4 })
		Util.Create("UIGradient", { Name = "Fade", Transparency = i == 1 and NumberSequence.new(0, 1) or NumberSequence.new(1, 0), Parent = f })
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

-- (egg-cards, spec 16.18) the strip cards' egg pictures: one TextureIds key per rarity (none uploaded yet: the owner sees
-- the PNGs first); no id -> nil and the card draws its painted EggArt egg as before
HatchLook.EGG_IMAGES = {
	Common = "egg_card_common", Uncommon = "egg_card_uncommon", Rare = "egg_card_rare", Epic = "egg_card_epic",
	Legendary = "egg_card_legendary", Mythic = "egg_card_mythic", Secret = "egg_card_secret",
}

function HatchLook.EggImage(rarity)
	local key = HatchLook.EGG_IMAGES[rarity]
	return key and HatchLook.Image(key) or nil
end

local EGG_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

-- how many of the seven egg pictures have an id here
function HatchLook.EggImages()
	local n = 0
	for _, key in pairs(HatchLook.EGG_IMAGES) do
		if HatchLook.Image(key) then
			n = n + 1
		end
	end
	return n
end

-- (review round 1) the cards draw the pictures only when all seven have ids: one strip never mixes painted and rendered
-- eggs (as the hero eggs are 3D all together or not at all), and a cell never carries both (the x3's 750 cap: a cell with
-- a painted egg and a picture took a one-id x3 to 766 at the rise)
function HatchLook.EggPictures()
	return HatchLook.EggImages() >= #EGG_ORDER
end

-- (review round 1) the seven pictures fetched before a strip shows them (a 512 px image decodes a few frames after its
-- first use, and a picture card has no painted egg to show meanwhile): the urls not sent yet go to one
-- ContentProvider:PreloadAsync in a spawned thread, so nothing waits on it -> how many were sent now
local PRELOADED = {}
function HatchLook.PreloadEggImages()
	if not HatchLook.EggPictures() then
		return 0
	end
	local list = {}
	for _, rarity in ipairs(EGG_ORDER) do
		local url = HatchLook.EggImage(rarity)
		if url and not PRELOADED[url] then
			PRELOADED[url] = true
			list[#list + 1] = url
		end
	end
	if #list > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(list)
			end)
		end)
	end
	return #list
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
		-- opts.Ellipse (review round 2: the plinth's halo): each disc is the built-in disc image (an ellipse, the mock's
		-- elliptical halo; a round frame on a wide box is a capsule that read as a rounded box of light)
		local ellipse = opts.Ellipse == true
		self.Prop, self.ColorProp = ellipse and "ImageTransparency" or "BackgroundTransparency", ellipse and "ImageColor3" or "BackgroundColor3"
		local discs = opts.Discs or K.GLOW.Discs
		for i = 1, math.max(1, math.min(#discs, opts.Count or #discs)) do
			local d = discs[i]
			local f
			if ellipse then
				f = Util.Create("ImageLabel", {
					Name = name .. i, Image = K.DISC, ScaleType = Enum.ScaleType.Stretch, ImageColor3 = color, ImageTransparency = 0, BackgroundTransparency = 1, BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z, Parent = parent,
				})
			else
				f = frame(parent, name .. i, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = z })
				corner(f, 0.5)
			end
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

-- one ellipse of the plinth: the built-in white disc stretched to its box, tinted by ImageColor3 (and a UIGradient)
local function disc(parent, name, props)
	props = props or {}
	props.Name = name
	props.Image = K.DISC
	props.ScaleType = Enum.ScaleType.Stretch
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.Parent = parent
	return Util.Create("ImageLabel", props)
end

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
	-- the rim: the Top's disc its Thickness px larger every way, behind it (it stays with the lip too)
	local rim = box:FindFirstChild("Rim")
	if rim then
		local r = rim:GetAttribute("Thickness") or 0
		rim.Position = top.Position + UDim2.fromOffset(-r, -r)
		rim.Size = top.Size + UDim2.fromOffset(2 * r, 2 * r)
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
	self.Glow = HatchLook.Glow(box, HatchLook.Shade(P.Neutral, 0.2), { Name = "Glow", Count = opts.Glows, Z = z - 1, Ellipse = true })
	self.Glow:Place(UDim2.fromScale(0.5, P.GlowY), UDim2.fromScale(P.GlowW, P.GlowH))
	self.GlowW = P.GlowW
	-- the thickness: the Top's ellipse Band lower (a lit-to-dark band shows under the Top's front edge), its straight ends
	-- (the Wall, between the two centre lines) and the lit lower rim behind it (the Edge). Shaded like a cylinder (the
	-- mock's side): lit at the front under the Top's edge, darker downward and towards the two ends (the Side shows only
	-- its lower half: its middle line, where the ends meet the Wall, is dark; the Wall is dark at its ends)
	-- (the Wall's ends are the box's: the Top's widest points, the Rim overhanging them like the mock's stroke)
	local sideY = P.Band - P.Top / 2
	local edge = phone and P.EdgePhone or P.Edge
	self.Edge = disc(box, "Edge", {
		Position = UDim2.new(0, -edge, sideY, -edge), Size = UDim2.new(1, 2 * edge, P.Top, 2 * edge), ImageColor3 = HatchLook.Shade(P.Neutral, 0.2), ImageTransparency = P.EdgeA, ZIndex = z,
	})
	local lit = 1 - P.Band / P.Top
	self.Side = disc(box, "Side", { Position = UDim2.fromScale(0, sideY), Size = UDim2.fromScale(1, P.Top), ImageColor3 = K.WHITE, ZIndex = z + 1 })
	Util.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, P.SideA), ColorSequenceKeypoint.new(0.5, P.SideA), ColorSequenceKeypoint.new(lit, P.SideB), ColorSequenceKeypoint.new(1, P.SideA),
		}),
		Parent = self.Side,
	})
	self.Wall = frame(box, "Wall", { Size = UDim2.fromScale(1, P.Band), BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ZIndex = z + 1 })
	Util.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, P.SideA), ColorSequenceKeypoint.new(0.2, P.SideB), ColorSequenceKeypoint.new(0.8, P.SideB), ColorSequenceKeypoint.new(1, P.SideA),
		}),
		Parent = self.Wall,
	})
	local rim = phone and P.RimPhone or P.Rim
	self.Rim = disc(box, "Rim", { ImageColor3 = HatchLook.Shade(P.Neutral, 0.25), ZIndex = z + 2 })
	self.Rim:SetAttribute("Thickness", rim)
	self.Top = disc(box, "Top", { ImageColor3 = K.WHITE, ZIndex = z + 3 })
	Util.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(P.TopA, P.TopB), Parent = self.Top })
	if opts.Ring ~= false then
		-- the inner ring: a disc in the ring colour under a Cover disc `ring` px smaller in the Top's colours over its span
		local ring = phone and P.RingPhone or P.Ring
		local v0, v1 = 0.5 - P.RingH / 2, 0.5 + P.RingH / 2
		self.Ring = disc(box, "Ring", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(P.RingW, P.RingH * P.Top),
			ImageColor3 = HatchLook.Shade(P.Neutral, 0.4), ImageTransparency = P.RingA, ZIndex = z + 4,
		})
		self.Cover = disc(box, "Cover", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(P.RingW, -2 * ring, P.RingH * P.Top, -2 * ring), ImageColor3 = K.WHITE, ZIndex = z + 5,
		})
		Util.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(P.TopA:Lerp(P.TopB, v0), P.TopA:Lerp(P.TopB, v1)), Parent = self.Cover })
	end
	HatchLook.PlinthLip(box, false)
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
	local P = K.PLINTH
	a = math.max(0, math.min(1, a))
	self.Alpha = a
	self.Top.ImageTransparency = 1 - a
	self.Side.ImageTransparency = 1 - a
	self.Wall.BackgroundTransparency = 1 - a
	self.Rim.ImageTransparency = 1 - a
	self.Edge.ImageTransparency = 1 - a * (1 - P.EdgeA)
	if self.Ring then
		self.Ring.ImageTransparency = 1 - a * (1 - P.RingA)
		self.Cover.ImageTransparency = 1 - a
	end
	self.Glow:SetAlpha(a)
end

-- the rarity's (or the neutral) shades: rim Shade(c, .25), inner ring .4, the lit lower rim and the glow .2
function Plinth:paint(c, seconds)
	local out = {}
	for _, p in ipairs({ { self.Rim, HatchLook.Shade(c, 0.25) }, { self.Ring, HatchLook.Shade(c, 0.4) }, { self.Edge, HatchLook.Shade(c, 0.2) } }) do
		if p[1] then
			if seconds and seconds > 0 then
				out[#out + 1] = tween(p[1], seconds, { ImageColor3 = p[2] }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, self.Track)
			else
				p[1].ImageColor3 = p[2]
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

-- (kit-b U9-2b) the title look's hard bands in the rarity's tones (no blend between them)
local function wordColors(c)
	local W = K.WORD
	local top, mid, low = HatchLook.Shade(c, W.Top), HatchLook.Shade(c, W.Mid), HatchLook.Shade(c, W.Bottom)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(W.BandA, top),
		ColorSequenceKeypoint.new(W.BandA + 0.0001, mid), ColorSequenceKeypoint.new(W.BandB, mid),
		ColorSequenceKeypoint.new(W.BandB + 0.0001, low), ColorSequenceKeypoint.new(1, low),
	})
end

local function wordLabel(parent, name, text, size, c, z)
	local W = K.WORD
	local l = Theme.Label(text, "Title", { Size = size, Stroke = 1 })
	l.Name = name
	l.TextColor3 = K.WHITE -- (the bands tint it)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.ZIndex = z
	Util.Create("UIGradient", { Name = "Bands", Rotation = 90, Color = wordColors(c), Parent = l })
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
end

-- (cx, y) = the word's centre and top; room (the old glow's screen room) is no longer used: the word has no halo
function Word:Place(cx, y)
	local w = self:Width()
	if #self.Letters == 0 then
		w = w + K.WORD.Pad * self.Size
	end
	self.Frame.Position = UDim2.fromOffset(cx - w / 2, y)
	self.Frame.Size = UDim2.fromOffset(w, self.Size)
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
end

function Word:Settle()
	self:drop()
	for _, L in ipairs(self.Letters) do
		L.Pop.Scale = 1
	end
	if #self.Letters == 0 and self.Frame.Parent then
		self.Frame.Visible = true
	end
end

function Word:Destroy()
	self:drop()
	self.Frame:Destroy()
end

-- (review round 1) another rarity's colours on the same instances: the bands and the outline (the crack word moves on
-- to the next egg of an x3)
function Word:SetRarity(rarity)
	local c = HatchLook.RarityColor(rarity)
	local seq, edge = wordColors(c), HatchLook.Shade(c, K.WORD.Outline)
	local labels = { self.Frame }
	if #self.Letters > 0 then
		labels = {}
		for i, L in ipairs(self.Letters) do
			labels[i] = L.Label
		end
	end
	for _, l in ipairs(labels) do
		local g = l:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = seq
		end
		local s = l:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = edge
		end
	end
end

-- a one-label word's new text (the attribute Text follows); a letter word keeps its letters
function Word:SetText(text)
	self.Text = tostring(text)
	if #self.Letters == 0 then
		self.Frame.Text = self.Text
	end
	self.Frame:SetAttribute("Text", self.Text)
end

----------------------------------------------------------------------
-- (Task 3; kit-b U9-2b) the planks and the small chips of the bottom bar, the reveal's tags
----------------------------------------------------------------------
function HatchLook.PillParts(btn)
	local face = btn:FindFirstChild("Face")
	local body = face and face:FindFirstChild("Body")
	local chip = face and face:FindFirstChild("Chip")
	return {
		Face = face, Body = body, Lip = body and body:FindFirstChild("Lip"), Edge = body and body:FindFirstChild("SignEdge"), Label = face and face:FindFirstChild("Label"),
		Chip = chip, Coin = chip and chip:FindFirstChild("Coin"), Price = chip and chip:FindFirstChild("Price"),
	}
end

local function pressed(btn)
	return btn:GetAttribute("PillState") == "Press" and btn:GetAttribute("Disabled") ~= true
end

-- the words and the price tag on the face above the lip; a press moves them down with the face (the lip shrinks under it)
local function layoutPill(btn, p)
	local P = K.PILL
	local e = P.Edge
	local lip = pressed(btn) and P.PressLip or P.Lip
	local drop = P.Lip - lip
	local w = btn:GetAttribute("ChipW") or 0
	local right = (w > 0) and (P.LabelGap + w + P.ChipIn) or P.LabelL
	p.Label.Position = UDim2.fromOffset(e + P.LabelL, e + drop)
	p.Label.Size = UDim2.new(1, -(2 * e + P.LabelL + right), 1, -(2 * e + P.Lip))
	if p.Chip then
		p.Chip.Visible = w > 0
		p.Chip.Position = UDim2.new(1, -(e + P.ChipIn), 0.5, drop - P.Lip / 2)
		p.Chip.Size = UDim2.new(0, math.max(0, w), 1, -(2 * e + P.Lip + P.ChipV))
	end
end

local function paintPill(btn)
	local P = K.PILL
	local p = HatchLook.PillParts(btn)
	local off = btn:GetAttribute("Disabled") == true
	local role = off and "Off" or (P.Look[btn:GetAttribute("Kind")] or "Selected")
	CloudUI.SignBlock(p.Body, role, { EdgePx = P.Edge, LipPx = pressed(btn) and P.PressLip or P.Lip, Pad = false })
	p.Label.TextColor3 = CloudUI.SignLooks[role].Text
	if p.Price then
		p.Price.TextColor3 = off and Sign.TextMuted or Sign.Text
		-- the token coin (a PixelIcon hosted in a text label: it follows TextColor3) in the price's ink: never white on the
		-- cream tag (a GemIcon keeps its own colours)
		local icon = p.Coin and p.Coin:FindFirstChild("Icon")
		if icon and icon:IsA("TextLabel") then
			icon.TextColor3 = p.Price.TextColor3
		end
	end
	layoutPill(btn, p)
end

-- a plank's state: "Press" (the face sunk onto its lip, the lip PressLip px) or "Rest"; a disabled plank never sinks
function HatchLook.PillState(btn, state)
	if btn and btn.Parent then
		btn:SetAttribute("PillState", state == "Press" and "Press" or "Rest")
		paintPill(btn)
	end
end

-- (kit-b U9-2b) a kit B plank in the bottom bar: a transparent tap box holding the CanvasGroup "Face" (the rise and the
-- fade) > "Body" (the block: its face colour, the wood edge "SignEdge" inside the group, the darker "Lip"), "Label"
-- (Button role) and, with opts.Price, "Chip" (the stone price tag) > "Coin" (the stage draws the icon in it), "Price"
-- (Display role, brown). Attribute Disabled (CloudUI.SetDisabled) paints the sunk Off well; a press sinks the face
function HatchLook.Pill(parent, opts)
	opts = opts or {}
	local P = K.PILL
	local z = opts.ZIndex or 1
	local kind = P.Look[opts.Kind or "Gold"] and (opts.Kind or "Gold") or "Gold"
	local btn = Util.Create("TextButton", {
		Name = opts.Name or "Pill", Text = "", AutoButtonColor = false, Active = true, BorderSizePixel = 0, BackgroundTransparency = 1, ZIndex = z, Parent = parent,
	})
	btn:SetAttribute("Kind", kind)
	local face = Util.Create("CanvasGroup", { Name = "Face", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = btn })
	-- the block sits its edge's width inside the group (a Border stroke draws outside its frame: never clipped)
	frame(face, "Body", { Position = UDim2.fromOffset(P.Edge, P.Edge), Size = UDim2.new(1, -2 * P.Edge, 1, -2 * P.Edge), BackgroundTransparency = 0, ZIndex = z + 1 })
	local label = Theme.Label(opts.Text or "", "Button", { Size = opts.TextSize or 22, Stroke = 1 })
	label.Name = "Label"
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = z + 3
	label.Parent = face
	if opts.Price then
		local chip = frame(face, "Chip", { AnchorPoint = Vector2.new(1, 0.5), ZIndex = z + 2 })
		CloudUI.SignBlock(chip, "Stone", { EdgePx = P.TagEdge, LipPx = P.TagLip, Pad = false })
		frame(chip, "Coin", { AnchorPoint = Vector2.new(0, 0.5), ZIndex = z + 3 })
		local price = Theme.Label("", "Display", { Size = 20, Stroke = 1 })
		price.Name = "Price"
		price.TextXAlignment = Enum.TextXAlignment.Center
		price.ZIndex = z + 3
		price.Parent = chip
	end
	btn:SetAttribute("PillState", "Rest")
	btn:GetAttributeChangedSignal("Disabled"):Connect(function()
		paintPill(btn)
	end)
	btn.MouseButton1Down:Connect(function()
		HatchLook.PillState(btn, "Press")
	end)
	btn.MouseButton1Up:Connect(function()
		HatchLook.PillState(btn, "Rest")
	end)
	btn.MouseLeave:Connect(function()
		HatchLook.PillState(btn, "Rest")
	end)
	-- a finger that lifts never produces MouseLeave (nor MouseButton1Up once it slid off)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			HatchLook.PillState(btn, "Rest")
		end
	end)
	btn:SetAttribute("ChipW", opts.Price and (opts.Phone and P.ChipWPhone or P.ChipW) or 0)
	paintPill(btn)
	HatchLook.SizePill(btn, opts.TextSize or 22, opts.Phone, opts.Coin)
	return btn
end

-- a layout's text and coin sizes; the coin and the price sit on the price tag's face, above its lip
function HatchLook.SizePill(btn, textSize, phone, coin)
	local P = K.PILL
	local p = HatchLook.PillParts(btn)
	p.Label.TextSize = textSize
	btn:SetAttribute("Phone", phone == true)
	if p.Price then
		coin = coin or (phone and 18 or 27)
		p.Price.TextSize = math.max(15, textSize - 2)
		p.Coin.Size = UDim2.fromOffset(coin, coin)
		p.Coin.Position = UDim2.new(0, P.ChipPad, 0.5, -math.floor(P.TagLip / 2))
		p.Price.Position = UDim2.fromOffset(P.ChipPad + coin + P.CoinGap, 0)
		p.Price.Size = UDim2.new(1, -(2 * P.ChipPad + coin + P.CoinGap), 1, -P.TagLip)
	end
end

-- the price tag's width for a price priceW px wide: the mock's 80 / 66 at the least, only its content's when the label
-- needs the room; fits = the label (labelW px) fits beside it on the face (inside the block's edges)
function HatchLook.FitPill(btn, labelW, priceW, parts)
	local P = K.PILL
	local p = parts or HatchLook.PillParts(btn)
	local coin = p.Coin and p.Coin.Size.X.Offset or 0
	local content = 2 * P.ChipPad + coin + P.CoinGap + priceW
	local least = btn:GetAttribute("Phone") == true and P.ChipWPhone or P.ChipW
	local room = btn.Size.X.Offset - 2 * P.Edge - P.ChipIn - P.LabelL - P.LabelGap
	local w = math.max(content, least)
	if labelW > room - w then
		w = content
	end
	return math.ceil(w), labelW <= room - w
end

-- the price tag w px wide (0: hidden, the label takes the whole face). parts: the button's PillParts already looked up
-- (review round 2: no lookups per refresh)
function HatchLook.SetPillChip(btn, w, parts)
	btn:SetAttribute("ChipW", math.max(0, w))
	layoutPill(btn, parts or HatchLook.PillParts(btn))
end

function HatchLook.PillIn(parts, k, rise)
	k = math.max(0, math.min(1, k))
	parts.Face.Position = UDim2.fromOffset(0, (1 - k) * (rise or 0))
	parts.Face.GroupTransparency = 1 - k
end

-- (kit-b U9-2b) a small chip: a transparent 44 px tap box drawing the navy "Pill" block (the kit's navy sign: its gold-lip
-- edge, its darker lip) with its cream "Label"
function HatchLook.Chip(parent, opts)
	opts = opts or {}
	local C = K.CHIP
	local z = opts.ZIndex or 1
	local btn = Util.Create("TextButton", {
		Name = opts.Name or "Chip", Text = "", AutoButtonColor = false, Active = true, BorderSizePixel = 0, BackgroundTransparency = 1, ZIndex = z, Parent = parent,
	})
	local pill = frame(btn, "Pill", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 0, ZIndex = z })
	CloudUI.SignBlock(pill, "Navy", { EdgePx = C.Edge, LipPx = C.Lip, Pad = false })
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

-- the Fast hatch chip: the navy chip with its square "Switch" (a slot in its lit edge) and the square stone "Knob"
function HatchLook.FastChip(parent, opts)
	opts = opts or {}
	local C = K.CHIP
	local z = opts.ZIndex or 1
	local btn = HatchLook.Chip(parent, { Name = opts.Name or "FastHatch", Text = "Fast hatch", TextSize = opts.TextSize, Phone = opts.Phone, ZIndex = z })
	local pill = btn:FindFirstChild("Pill")
	local sw = frame(pill, "Switch", { AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.Slot, BackgroundTransparency = 0, ZIndex = z + 1 })
	local edge = stroke(sw, C.SlotEdge, 2, 0)
	edge.Name = "SlotEdge"
	edge.LineJoinMode = Enum.LineJoinMode.Miter
	frame(sw, "Knob", { AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.Knob, BackgroundTransparency = 0, ZIndex = z + 2 })
	HatchLook.SizeChip(btn, opts.TextSize or 18, opts.Phone)
	HatchLook.SetFast(btn, false)
	return btn
end

-- a chip label's left inset in its block and the block's width it leaves out: Skip Pad each side; Fast hatch the switch
-- and a 4 px gap on its left, the switch's inset on its right. (U9-2b review) the switch sits SwitchX px in from the tap
-- box (the block's edge inside it), so the label keeps the room it had before the block moved inside the tap box
local function chipInsets(fast, phone)
	local C = K.CHIP
	if not fast then
		return C.Pad, 2 * C.Pad
	end
	local x, w = C.SwitchX - C.Edge, phone and C.SwitchWPhone or C.SwitchW
	return x + w + 4, 2 * x + w + 4
end

-- a layout's chip: the block H / HPhone tall inside the tap box (its edge inside the box too), the words over the lip
function HatchLook.SizeChip(btn, textSize, phone)
	local C = K.CHIP
	local pill = btn:FindFirstChild("Pill")
	local label = pill:FindFirstChild("Label")
	pill.Size = UDim2.new(1, -2 * C.Edge, 0, (phone and C.HPhone or C.H) - 2 * C.Edge)
	label.TextSize = textSize
	local sw = pill:FindFirstChild("Switch")
	local left, out = chipInsets(sw ~= nil, phone)
	if sw then
		local w, h = phone and C.SwitchWPhone or C.SwitchW, phone and C.SwitchHPhone or C.SwitchH
		sw.Position = UDim2.new(0, C.SwitchX - C.Edge, 0.5, -math.floor(C.Lip / 2))
		sw.Size = UDim2.fromOffset(w, h)
		sw:FindFirstChild("Knob").Size = UDim2.fromOffset(h - 4, h - 4)
		HatchLook.SetFast(btn, btn:GetAttribute("On") == true)
	end
	-- (Fast hatch: the label centred in the room right of the switch)
	label.Position = UDim2.fromOffset(left, 0)
	label.Size = UDim2.new(1, -out, 1, -C.Lip)
end

-- (U9-2b review) the label's width in a chip w px wide (the tap box): what SizeChip leaves it, so a caller that picks the
-- words for a chip (EggStage's Skip forms) measures against the real label box
function HatchLook.ChipRoom(w, fast, phone)
	local _, out = chipInsets(fast == true, phone)
	return w - 2 * K.CHIP.Edge - out
end

-- (kit-b U9-2b) a flat tag of the reveal (NEW!, EVOLVED): a Frame named `name` painted as a kit B block in `look` (a
-- CloudUI.SignLooks name: its face, wood or gold-lip edge Edge px and darker lip) with its words "Text" (Tag role, in
-- capitals) on the face above the lip, the look's ink; square, never tilted
HatchLook.TAG = { Edge = 2, Lip = 3 }
function HatchLook.Tag(parent, name, text, look, opts)
	opts = opts or {}
	local T = HatchLook.TAG
	local z = opts.ZIndex or 6
	local tag = frame(parent, name, { BackgroundTransparency = 0, ZIndex = z, Visible = opts.Visible ~= false })
	CloudUI.SignBlock(tag, look, { EdgePx = T.Edge, LipPx = T.Lip, Pad = false })
	local words = Theme.Label(text, "Tag", { Size = opts.TextSize or 15 })
	words.Name = "Text"
	words.Size = UDim2.new(1, 0, 1, -T.Lip)
	words.ZIndex = z + 1
	words.TextColor3 = CloudUI.SignLooks[look].Text
	words.TextXAlignment = Enum.TextXAlignment.Center
	words.Parent = tag
	return tag, words
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
	local C = K.CHIP
	local knob = sw:FindFirstChild("Knob")
	sw.BackgroundColor3 = on and C.On or C.Slot
	local edge = sw:FindFirstChild("SlotEdge")
	if edge then
		edge.Color = on and C.OnEdge or C.SlotEdge
	end
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

-- (review round 1) an owner that switches its gui off while the stage already has it off writes the same value: no
-- signal reaches the stage, so the owner says so with the attribute HudKeepOff = true (MovementController's
-- MobileControls on a death) and the restore leaves that gui off
HatchLook.KEEP_OFF = "HudKeepOff"

function HatchLook.RestoreHud()
	local list = Hidden
	Hidden = {}
	for gui, conn in pairs(list) do
		pcall(function()
			conn:Disconnect()
		end)
		pcall(function()
			if gui.Parent ~= nil and gui.Enabled == false and gui:GetAttribute(HatchLook.KEEP_OFF) ~= true then
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
