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
--   rays, the FX, the eggs) carries attribute Art = "Hatch"; (U9-2b look review 2) the plinth is a kit block now.
--   HatchLook.Card(cell, geo) -> card         skins a strip cell (a Frame, its egg inside) as a stone block: the face
--                                             Theme.Sign.Tile, the cell's own UIStroke the mitred wood "SignEdge" (geo.Edge
--                                             px), no corner. geo = { W, H, Edge, Plate, Word, Lite, Phone, Z }. Not Lite: the
--                                             "Plate" band (geo.Plate px) along the bottom holding the upper-case "Word";
--                                             Lite (a phone's x3): a "Lip" band only (look review: a PC x3 card holds the
--                                             plate too). card = { Frame, Plate, PlateText, Rim }. Adds only the Plate and its
--                                             Word to the cell (Lite: the Lip; the edge is the cell's own stroke, no shadow
--                                             beside it): spec 16.15 "Budgets"
--   HatchLook.SetCard(card, rarity|false, state)   state "Idle" | "Landed" | "Dim": the face Tile / the Selected cream /
--                                             the sunk Well (look review: the landed card's edge the ink, Sign.Text: the
--                                             kit's selected mark); the lip in RarityColor(r), the plate in
--                                             Theme.ReadableFace(RarityColor(r), 4.5) with its word in the ink it returns
--                                             (StoneLip without a rarity), 0.3 clear when Dim
--   HatchLook.ShowCard(card, cx, cy) / HideCard(card)   places a card by its centre (AnchorPoint 0.5), its hop
--                                             above it, or hides it
--   HatchLook.DropCard(card)                  destroys the cell
--   HatchLook.LandPop(card, fast, track, room) -> { tween }   the land (look review: never a scale): the card hops
--                                             min(POP.Hop, room) px up (0.1 s Quad Out) and back (0.1 s; Fast 0.05 / 0.05)
--                                             on whole px (a NumberValue "Hop" on the cell), and one white "Sweep" (a hard-
--                                             edged flat band, Offset -1 -> 1 in 0.3 s, Fast 0.12; destroyed after). Every
--                                             tween it plays (the chained one too) goes into `track`
--   HatchLook.SetPop(card)                    the card at rest, no hop (a resize cancelled its tweens)
--   HatchLook.Window(parent, pointer, opts) -> win   the gold winner window on the strip's existing "Pointer" frame (its
--                                             root): children Window (the square gold frame: a mitred stroke), NotchTop /
--                                             NotchBottom (stepped pixel pointers: a 6-unit row on the frame's edge, child
--                                             rows Row2 / Row3 of 4 and 2 units stepping in; look review: Notch is the unit,
--                                             the screen's pixel: 3 px on PC, 2 on a phone; every row on whole px), a
--                                             UIScale "Bounce"; beside it in `parent`, DimL / DimR darken the track outside
--                                             the window after the land. opts = { Phone, Gold, Stroke, Notch (0 = none),
--                                             Track (the tween set) }.
--                                             win:Place(x, y, w, h, trackW, trackH)  the window's box (the landed cell's + pad;
--                                                                        its centre on a whole px, its sides even)
--                                             win:Style(opts)            a layout's stroke and notches (a resize)
--                                             win:Tell(color, seconds)   every gold part turns `color` (attribute Tell = true)
--                                             win:Reset()                gold again (Tell = nil)
--                                             win:Bounce(seconds) / win:Rest()   a 1.08 -> 1 Back Out pop / at rest
--                                             win:SetDim(k)              the dims at k (0 = clear .. 1 = dark), per frame
--                                             win:DropGlow()             nothing (no glow any more; kept for the rise's call)
--                                             win:DropDims()             the dims go (an x3 strip at the rise: the budget)
--                                             win:Destroy()
--   HatchLook.TrackEnds(track) -> EndL, EndR   (look review) the rail's square ends: a flat TRACK_END.Px line of
--                                             Sign.NavyLip each, over the cards (no fade); EggStage places them
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
--   HatchLook.Plinth(box, rarity, phone, opts) -> plinth   (U9-2b look review 2: a kit block, no ellipse, gradient or
--                                             halo) the slab the hero egg, its halves and the pet stand on, drawn in the
--                                             existing "Pedestal<j>" layout box (anchored at its top centre: the egg's foot,
--                                             the slab's top): "Slab" (CloudUI.SignBlock "Navy": the navy face, the mitred
--                                             GoldLip "SignEdge", its "Lip" in the rarity's colour) on "Foot" (a narrower
--                                             NavyLip block), every size whole units of the box's attribute Unit
--                                             (opts.Unit, else 2 on a phone, 3); a UIScale "Pop" kept at 1. Neutral
--                                             (Sign.NavyLip on the lip) until Tint. 7 instances.
--                                             opts = { Track (the tween set), Unit }
--                                             plinth:SetAlpha(a)        0 = hidden .. 1 = shown (the rise's fade, per frame)
--                                             plinth:Tint(color, s)     the lip `color` in s seconds (0: at once); remembered
--                                                                       for Rest
--                                             plinth:Reset()            neutral again;  plinth:Rest()  shown, colour snapped
--                                                                       (a resize cancelled the tweens)
--   HatchLook.PlinthLip(box, lip)             lays the slab and the foot out in the box's Size (call it after a resize);
--                                             lip = true (a phone's reveal): the slab fills the box (the 12 px lip), no
--                                             foot. Attributes SlabH / FootH (px)
--   HatchLook.IMAGES                          the three optional images, TextureIds keys: Rays "hatch_rays" (EggStage passes
--                                             it to HatchFx.Rays: one ImageLabel fan), Glow "hatch_glow" (no longer drawn: U9-2b
--                                             look review 2, kit B has no glow; the key stays for the TextureIds table),
--                                             Sparkle "hatch_sparkle" (HatchFx.Pool's sparks); none uploaded: their frame
--                                             fallbacks draw (HatchFx's ray wedges and spark squares)
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
--                                             CanvasGroup: the rise and fade) > "Body" (the block, CloudUI.SignBlock: Stone
--                                             the stone plank, Green the "Primary" grass, Gold the "Selected" look; its wood
--                                             "SignEdge" 3 px inside the group and its "Lip" 5 px), "Label" (Theme "Button",
--                                             the look's ink) and, with opts.Price, "Chip" (look review: the Shop's Spin row,
--                                             no tag box: a transparent holder after the label) > "Coin" (the stage puts the
--                                             icon in it; a pixel coin in Sign.GoldLip), "Price" (Theme "Button" at the
--                                             label's size, the look's ink). The attribute Disabled (CloudUI.SetDisabled)
--                                             paints the sunk "Off" well with muted words and coin. A press sinks the face
--                                             onto its lip (PillState). opts = { Name, Kind = "Stone" | "Green" | "Gold",
--                                             Text, TextSize, Price, Coin, Phone, ZIndex }
--   HatchLook.PillParts(btn) -> { Face, Body, Lip, Edge, Label, Chip, Coin, Price }
--   HatchLook.PillState(btn, "Press" | "Rest")   the press: the lip 2 px, the words and the price 3 px lower; Rest: back
--   HatchLook.SizePill(btn, textSize, phone, coin)   a layout's text and coin sizes (coin default 30, phone 20: its
--                                             pixel icon 27 / 18, the kit's Glyph size)
--   HatchLook.FitPill(btn, labelW, priceW, parts?) -> chipW, fits   the inline price's width (the coin, the row gap,
--                                             the price) and whether the label fits beside it
--   HatchLook.SetPillChip(btn, w, parts?, labelW)   the price row w px wide after a label labelW px wide, the row centred
--                                             on the face on whole px (0: hidden, the label takes the whole face). parts:
--                                             the button's PillParts already looked up (review round 2: no lookups per
--                                             refresh)
--   HatchLook.PillIn(parts, k, rise)          the rise: the Face rise x (1 - k) px lower and 1 - k clear (k = 1: in place)
--   HatchLook.Chip(parent, opts) -> TextButton   a small chip: a transparent 44 px tap box drawing a "Pill" (36 px, phone
--                                             32): the navy SignBlock (its gold-lip edge 2 px, lip 3) with its cream
--                                             "Label". opts = { Name, Text, TextSize, Phone, ZIndex }
--   HatchLook.FastChip(parent, opts) -> TextButton   the Fast hatch chip: the navy chip with the kit's one switch
--                                             (CloudUI.SignSwitch, the Shop's: the "Switch" well slot and its stone "Knob"),
--                                             the "Label"
--   HatchLook.SetFast(chip, on)               the switch gold / the well slot, the knob's side, attribute On
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
	-- (look review) the land is the kit's hover lift, never a scale (a part takes no scale bounce: its pixel edges stay whole
	-- and the rail never clips it): the landed card hops Hop px up (at most its room) in Up s and back in Down s, whole px
	POP = { Hop = 4, Up = 0.1, Down = 0.1, UpFast = 0.05, DownFast = 0.05 },
	SWEEP = { Normal = 0.3, Fast = 0.12, Band = 0.45, Rotation = 18 },
	BOUNCE = 1.08,
	-- (U9-2b look review 2, the owner's look bar of 2026-11-17: no smooth round shapes, no glow) the plinth is a kit
	-- block: the navy sign slab (Sign.Navy, the GoldLip edge one unit, the rarity on its lip: the pitch's "rarity on the
	-- lip") on a narrower NavyLip foot, in the screen's pixel unit (3 px PC, 2 px a phone / a 720p PC): the slab SlabK x
	-- its box wide tall (at least SlabMin units, its lip 2 units from LipFrom), the foot FootK x the slab tall (at least
	-- FootMin units), FootIn x the box in on each side. Neutral (the navy sign's own lip) until the rarity shows
	PLINTH = {
		SlabK = 0.1, SlabMin = 5, LipFrom = 8, FootK = 0.5, FootMin = 3, FootIn = 0.1,
		-- (kit-b gate U9 round 3: two navy slabs read as empty nameplates) a shop's display stand: a wood top in its dark wood
		-- edge with one light top row (Shine) and the rarity on its lip (Neutral, the wood's own dark lip, before it), on a
		-- stone base in the same edge
		Face = Sign.Wood, Edge = Sign.WoodDark, Shine = Sign.WoodLight,
		Neutral = Sign.WoodDark, FootFace = Sign.Stone, FootLip = Sign.StoneLip,
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
	-- in; Kind -> its sign look (Stone: the stone plank, brown words; Green: the grass block, the stage's one green action;
	-- Gold: the selected look, kept for callers; disabled: the sunk Off well); Edge / Lip px (the kit's 3 / 5), the press
	-- leaves PressLip of the lip (the face sinks onto it). (look review) a price sits inline like the Shop's Spin: the
	-- label, the coin (Sign.GoldLip, whole px) and the price (the Button role, the label's size) one centred row, Gap(size)
	-- = max(3, floor(size x 0.3)) px apart (the Shop's row gap); LabelL px of face kept free each side
	PILL = {
		Look = { Gold = "Selected", Green = "Primary", Stone = "Stone" }, Edge = 3, Lip = 5, PressLip = 2, LabelL = 8, Coin = Sign.GoldLip,
	},
	-- (kit-b U9-2b) the chips (Skip, Fast hatch): a navy block (the kit's navy sign: gold-lip edge, darker lip) H / HPhone
	-- tall in the 44 px tap box, cream words; (look review) Fast hatch's switch is the kit's one switch, the Shop's
	-- (CloudUI.SignSwitch: the sunk well slot, the stone knob in its wood edge, gold while on: never a second green beside Done)
	CHIP = {
		H = 36, HPhone = 32, Pad = 12, Edge = 2, Lip = 3, Ink = Sign.Stone,
		SwitchW = 34, SwitchH = 18, SwitchWPhone = 30, SwitchHPhone = 16, SwitchX = 10,
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
	-- the face: stone, the landed card the selected face, the others sunk once the strip has landed; (look review) the
	-- landed card wears the kit's selected mark, its edge in the ink (the Pets grid's pick, the Gifts TODAY tile)
	cell.BackgroundColor3 = (state == "Landed" and Sign.Selected) or (dim and Sign.Well) or Sign.Tile
	cell.BackgroundTransparency = 0
	if card.Rim then
		card.Rim.Color = state == "Landed" and Sign.Text or Sign.Wood
	end
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
	card.X, card.Y = cx, cy
	card.Frame.Position = UDim2.fromOffset(cx, cy - (card.HopY or 0))
	card.Frame.Visible = true
end

function HatchLook.HideCard(card)
	card.Frame.Visible = false
end

function HatchLook.DropCard(card)
	card.Frame:Destroy()
end

-- (look review) the hop's driver: a NumberValue "Hop" on the cell (px up); the card follows it in whole px
local function hopOf(card)
	local f = card.Frame
	local hop = f:FindFirstChild("Hop")
	if not (hop and hop:IsA("NumberValue")) then
		hop = Util.Create("NumberValue", { Name = "Hop", Value = 0, Parent = f })
		hop:GetPropertyChangedSignal("Value"):Connect(function()
			card.HopY = math.floor((tonumber(hop.Value) or 0) + 0.5)
			if card.X and f.Parent then
				f.Position = UDim2.fromOffset(card.X, card.Y - card.HopY)
			end
		end)
	end
	return hop
end

-- the card at rest: no hop (a resize cancelled its tweens); `scale` is ignored (kept for old callers: never a scale)
function HatchLook.SetPop(card, scale)
	if card and card.Frame and card.Frame.Parent then
		hopOf(card).Value = 0
		card.HopY = 0
		if card.X then
			card.Frame.Position = UDim2.fromOffset(card.X, card.Y)
		end
	end
end

-- (look review) the land: the card hops min(Hop, room) px up and back (room: the caller's free px above it inside the
-- rail and the window's navy pad), whole px, plus one hard-edged shine sweep; nothing scales, nothing is clipped
function HatchLook.LandPop(card, fast, track, room)
	local out = {}
	if not (card and card.Frame and card.Frame.Parent) then
		return out
	end
	local P = K.POP
	local hop = hopOf(card)
	hop.Value = 0
	local h = math.max(0, math.floor(math.min(P.Hop, tonumber(room) or P.Hop)))
	local up = h > 0 and tween(hop, fast and P.UpFast or P.Up, { Value = h }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, track) or nil
	if up then
		out[#out + 1] = up
		up.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and hop.Parent then
				tween(hop, fast and P.DownFast or P.Down, { Value = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, track)
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

-- (kit-b U9-2b) a notch is a pixel pointer: its own frame the widest row on the window's edge, two child rows stepping in
-- towards the card. (look review) u is the screen's pixel unit (the kit's pixel pair: 3 px on PC, 2 on a phone; 0 =
-- none), the rows 6u / 4u / 2u wide (even: they centre on a whole px), the widest at floor(w / 2) - 3u of the window's
-- w px, AnchorPoint 0: every row on whole px
local function placeNotch(notch, u, i, edge, w)
	u = math.max(0, math.floor(tonumber(u) or 0))
	local down = i == 1 -- the top notch points down into the window, the bottom one up
	notch.AnchorPoint = Vector2.new(0, down and 0 or 1)
	notch.Position = UDim2.new(0, math.floor((w or 0) / 2) - 3 * u, i - 1, down and -edge or edge)
	notch.Size = UDim2.fromOffset(6 * u, u)
	for r, row in ipairs({ notch:FindFirstChild("Row2"), notch:FindFirstChild("Row3") }) do
		row.Position = UDim2.fromOffset(r * u, (down and 1 or -1) * r * u)
		row.Size = UDim2.fromOffset((6 - 2 * r) * u, u)
	end
	notch.Visible = u > 0
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
	self.NotchN = opts.Notch or (phone and 2 or 3) -- (look review) the notch's pixel unit, px
	self.Notches = {}
	for i, name in ipairs({ "NotchTop", "NotchBottom" }) do
		local notch = frame(pointer, name, { BackgroundColor3 = K.NOTCH, BackgroundTransparency = 0, ZIndex = z + 2 })
		for _, row in ipairs({ "Row2", "Row3" }) do
			frame(notch, row, { BackgroundColor3 = K.NOTCH, BackgroundTransparency = 0, ZIndex = z + 2 })
		end
		placeNotch(notch, self.NotchN, i, self.WinStroke.Thickness, 0)
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

-- (look review: whole px) the box's centre on a whole px and its sides even, so every edge lands on a whole px (the
-- bounce still grows round the middle: AnchorPoint 0.5)
function Win:Place(x, y, w, h, trackW, trackH)
	local root = self.Root
	local W, Hh = 2 * math.floor(math.max(0, w) / 2 + 0.5), 2 * math.floor(math.max(0, h) / 2 + 0.5)
	local cx, cy = math.floor(x + w / 2 + 0.5), math.floor(y + h / 2 + 0.5)
	root.Position = UDim2.fromOffset(cx, cy)
	root.Size = UDim2.fromOffset(W, Hh)
	self.W = W
	for i, notch in ipairs(self.Notches) do
		placeNotch(notch, self.NotchN, i, self.WinStroke.Thickness, W)
	end
	if trackW and self.Dims[2] then
		local left, right = self.Dims[1], self.Dims[2]
		local x0, x1 = cx - W / 2, cx + W / 2
		left.Position = UDim2.fromOffset(0, 0)
		left.Size = UDim2.fromOffset(math.max(0, x0), trackH or h)
		right.Position = UDim2.fromOffset(x1, 0)
		right.Size = UDim2.fromOffset(math.max(0, trackW - x1), trackH or h)
	end
end

-- the sizes of a layout (a resize): the frame's stroke, the notches' pixel unit (0 = none); (kit-b U9-2b) square: no
-- corner, no glow
function Win:Style(opts)
	if opts.Stroke then
		self.WinStroke.Thickness = opts.Stroke
	end
	if opts.Notch then
		self.NotchN = opts.Notch
	end
	for i, notch in ipairs(self.Notches) do
		placeNotch(notch, self.NotchN, i, self.WinStroke.Thickness, self.W or 0)
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

-- (look review) the rail's square ends: no airbrushed fade (the kit has no soft gradient on its chrome), a flat End px
-- line of the rail's lip (Sign.NavyLip) inside the wood frame at each end, over the cards: the cards slide into a slot.
-- EggStage places them (EndL / EndR, the track's full height)
HatchLook.TRACK_END = { Px = 2, Color = Sign.NavyLip }
function HatchLook.TrackEnds(track)
	local out = {}
	for i, name in ipairs({ "EndL", "EndR" }) do
		out[i] = frame(track, name, { BackgroundColor3 = HatchLook.TRACK_END.Color, BackgroundTransparency = 0, ZIndex = 4 })
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
-- the plinth (the Pedestal<j> box's look; U9-2b look review 2: a kit block slab on a narrower foot, never a soft disc)
----------------------------------------------------------------------
local Plinth = {}
Plinth.__index = Plinth

-- the slab and its foot laid out in the box (its Size in px, attribute Unit = the screen's pixel u): the slab one block
-- (face, mitred GoldLip edge u px, lip) from the box's top (the egg's / the pet's foot) SlabK x the box wide tall (at
-- least SlabMin units), its lip 2 units (1 under LipFrom units), the foot FootK x the slab tall (at least FootMin units)
-- and FootIn x the box in on each side; every size whole units. lip = true (a phone's reveal): the slab fills the box (the
-- 12 px lip), no foot. A block's edge is a stroke outside its frame: each frame sits one edge inside its outline, and
-- the foot's top edge lies on the slab's bottom one (one line, not two)
function HatchLook.PlinthLip(box, lip)
	local slab, foot = box and box:FindFirstChild("Slab"), box and box:FindFirstChild("Foot")
	if not (slab and foot) then
		return
	end
	local P = K.PLINTH
	local u = math.max(1, box:GetAttribute("Unit") or 3)
	local w = math.floor(box.Size.X.Offset + 0.5)
	local function units(v)
		return math.floor(v / u + 0.5) * u
	end
	local slabH, lipH, footH, footIn
	if lip then
		slabH, lipH, footH, footIn = math.max(3 * u, math.floor(box.Size.Y.Offset + 0.5)), u, 0, 0
	else
		slabH = math.max(P.SlabMin * u, units(P.SlabK * w))
		lipH = slabH >= P.LipFrom * u and 2 * u or u
		footH = math.max(P.FootMin * u, units(P.FootK * slabH))
		footIn = math.max(2 * u, units(P.FootIn * w))
	end
	box:SetAttribute("SlabH", slabH)
	box:SetAttribute("FootH", footH)
	slab.Position = UDim2.fromOffset(u, u)
	slab.Size = UDim2.fromOffset(math.max(0, w - 2 * u), math.max(0, slabH - 2 * u))
	slab.SignEdge.Thickness = u
	slab.Lip.Size = UDim2.new(1, 0, 0, lipH)
	local shine = slab:FindFirstChild("Shine")
	if shine then
		shine.Size = UDim2.new(1, 0, 0, u) -- one pixel unit of light wood along the top
	end
	foot.Visible = footH > 0
	foot.Position = UDim2.fromOffset(footIn + u, slabH)
	foot.Size = UDim2.fromOffset(math.max(0, w - 2 * footIn - 2 * u), math.max(0, footH - 2 * u))
	foot.SignEdge.Thickness = u
	foot.Lip.Size = UDim2.new(1, 0, 0, u)
end

function HatchLook.Plinth(box, rarity, phone, opts)
	opts = opts or {}
	local P = K.PLINTH
	local self = setmetatable({ Box = box, Rarity = rarity, Track = opts.Track, Alpha = 1, Color = nil }, Plinth)
	local z = box.ZIndex
	box.AnchorPoint = Vector2.new(0.5, 0) -- (the egg's foot: the slab's top)
	box.BackgroundTransparency = 1
	box:SetAttribute("Unit", opts.Unit or (phone and 2 or 3))
	-- (kept at 1: the plinth rises and fades in with the egg, never a scale: its pixel edges stay whole)
	self.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = box })
	self.Foot = frame(box, "Foot", { BackgroundTransparency = 0, ZIndex = z })
	-- (Pitch 2 F0) the hatch stage keeps its approved roll look and its instance budget (smoke_roll_look: the plinth is 8
	-- instances, x3 <= 750 a frame): every kit block of the stage is painted with Finish = false (no finish pass parts)
	CloudUI.SignBlock(self.Foot, "Stone", { Face = P.FootFace, LipColor = P.FootLip, Edge = P.Edge, EdgePx = 2, LipPx = 2, Pad = false, Finish = false })
	self.Slab = frame(box, "Slab", { BackgroundTransparency = 0, ZIndex = z + 1 })
	CloudUI.SignBlock(self.Slab, "Stone", { Face = P.Face, LipColor = P.Neutral, Edge = P.Edge, EdgePx = 2, LipPx = 2, Pad = false, Finish = false })
	self.Slab.Lip.ZIndex = z + 2
	local shine = frame(self.Slab, "Shine", { BackgroundTransparency = 0, BackgroundColor3 = P.Shine, ZIndex = z + 2 })
	self.Parts = {
		{ self.Slab, "BackgroundTransparency" }, { self.Slab.SignEdge, "Transparency" }, { self.Slab.Lip, "BackgroundTransparency" },
		{ shine, "BackgroundTransparency" },
		{ self.Foot, "BackgroundTransparency" }, { self.Foot.SignEdge, "Transparency" }, { self.Foot.Lip, "BackgroundTransparency" },
	}
	HatchLook.PlinthLip(box, false)
	return self
end

-- (kept for callers: the plinth has no halo any more)
function Plinth:FitGlow() end

function Plinth:SetAlpha(a)
	a = math.max(0, math.min(1, a))
	self.Alpha = a
	for _, p in ipairs(self.Parts) do
		p[1][p[2]] = 1 - a
	end
end

-- the rarity on the slab's lip (the pitch's "rarity on the lip"); Neutral (the navy sign's own lip) before it
function Plinth:paint(c, seconds)
	local out = {}
	local lip = self.Slab and self.Slab:FindFirstChild("Lip")
	if lip then
		if seconds and seconds > 0 then
			out[#out + 1] = tween(lip, seconds, { BackgroundColor3 = c }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, self.Track)
		else
			lip.BackgroundColor3 = c
		end
	end
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

-- (look review) the gap between an inline price row's parts: the Shop's Spin row gap, max(3, floor(size x 0.3)) px
local function rowGap(size)
	return math.max(3, math.floor((tonumber(size) or 22) * 0.3))
end

-- the words and the price on the face above the lip; a press moves them down with the face (the lip shrinks under it).
-- (look review) with a price (attribute ChipW > 0: the coin, its gap and the price, px) the label (attribute LabelW px)
-- and the price are one row centred on the face at whole px, like the Shop's Spin (no tag box); no price: the label
-- fills the face
local function layoutPill(btn, p)
	local P = K.PILL
	local e = P.Edge
	local lip = pressed(btn) and P.PressLip or P.Lip
	local drop = P.Lip - lip
	local w = math.max(0, math.ceil(btn:GetAttribute("ChipW") or 0))
	if w > 0 and p.Chip then
		local labelW = math.ceil(btn:GetAttribute("LabelW") or 0)
		local gap = rowGap(p.Label.TextSize)
		local x0 = e + math.max(P.LabelL, math.floor((btn.Size.X.Offset - 2 * e - (labelW + gap + w)) / 2))
		p.Label.Position = UDim2.fromOffset(x0 - 1, e + drop)
		p.Label.Size = UDim2.new(0, labelW + 2, 1, -(2 * e + P.Lip))
		p.Chip.Visible = true
		p.Chip.Position = UDim2.fromOffset(x0 + labelW + gap, e + drop)
		p.Chip.Size = UDim2.new(0, w, 1, -(2 * e + P.Lip))
		if p.Coin then
			local rowH = btn.Size.Y.Offset - 2 * e - P.Lip
			p.Coin.Position = UDim2.fromOffset(0, math.max(0, math.floor((rowH - p.Coin.Size.Y.Offset) / 2)))
		end
	else
		p.Label.Position = UDim2.fromOffset(e + P.LabelL, e + drop)
		p.Label.Size = UDim2.new(1, -2 * (e + P.LabelL), 1, -(2 * e + P.Lip))
		if p.Chip then
			p.Chip.Visible = false
		end
	end
end

local function paintPill(btn)
	local P = K.PILL
	local p = HatchLook.PillParts(btn)
	local off = btn:GetAttribute("Disabled") == true
	local role = off and "Off" or (P.Look[btn:GetAttribute("Kind")] or "Stone")
	CloudUI.SignBlock(p.Body, role, { EdgePx = P.Edge, LipPx = pressed(btn) and P.PressLip or P.Lip, Pad = false, Finish = false })
	p.Label.TextColor3 = CloudUI.SignLooks[role].Text
	if p.Price then
		p.Price.TextColor3 = CloudUI.SignLooks[role].Text
		-- (look review) the token coin (a PixelIcon hosted in a text label: it follows TextColor3) in the deep gold the Shop's
		-- Spin draws it in, muted with the words when disabled (a GemIcon keeps its own colours)
		local icon = p.Coin and p.Coin:FindFirstChild("Icon")
		if icon and icon:IsA("TextLabel") then
			icon.TextColor3 = off and Sign.TextMuted or P.Coin
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
-- (Button role) and, with opts.Price, "Chip" (look review: the inline price row, no box) > "Coin" (the stage draws the
-- icon in it), "Price" (the Button role, the look's ink). Attribute Disabled (CloudUI.SetDisabled) paints the sunk Off
-- well; a press sinks the face
function HatchLook.Pill(parent, opts)
	opts = opts or {}
	local P = K.PILL
	local z = opts.ZIndex or 1
	local kind = P.Look[opts.Kind or "Stone"] and (opts.Kind or "Stone") or "Stone"
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
		-- (look review) the price row: a transparent holder (no tag box), the coin and the price at whole px
		local chip = frame(face, "Chip", { ZIndex = z + 2 })
		frame(chip, "Coin", { ZIndex = z + 3 })
		local price = Theme.Label("", "Button", { Size = opts.TextSize or 22, Stroke = 1 })
		price.Name = "Price"
		price.TextXAlignment = Enum.TextXAlignment.Left
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
	btn:SetAttribute("ChipW", 0)
	paintPill(btn)
	HatchLook.SizePill(btn, opts.TextSize or 22, opts.Phone, opts.Coin)
	return btn
end

-- a layout's text and coin sizes; (look review) the price in the label's size and role, the coin a whole-px box (its
-- pixel icon centred in it by PixelIcon.Host's whole-px offset), the price the row gap after it
function HatchLook.SizePill(btn, textSize, phone, coin)
	local p = HatchLook.PillParts(btn)
	p.Label.TextSize = textSize
	btn:SetAttribute("Phone", phone == true)
	if p.Price then
		coin = math.floor(coin or (phone and 20 or 30))
		local gap = rowGap(textSize)
		p.Price.TextSize = textSize
		p.Coin.Size = UDim2.fromOffset(coin, coin)
		-- a hosted pixel coin (a text label: NeonKit.Icon) is the coin's own box at 0, 0, its glyph size the coin's (the
		-- icon redraws at 0.9 x it, centred on whole px)
		local icon = p.Coin:FindFirstChild("Icon")
		if icon and icon:IsA("TextLabel") then
			icon.AnchorPoint = Vector2.new(0, 0)
			icon.Position = UDim2.fromOffset(0, 0)
			icon.Size = UDim2.fromOffset(coin, coin)
			icon.TextSize = coin
		end
		p.Price.Position = UDim2.fromOffset(coin + gap, 0)
		p.Price.Size = UDim2.new(1, 2 - (coin + gap), 1, 0)
	end
	layoutPill(btn, p)
end

-- (look review) the inline price's width for a price priceW px wide (the coin, the row gap, the price: whole px) and
-- whether the label (labelW px) fits beside it on the face, LabelL px kept free each side
function HatchLook.FitPill(btn, labelW, priceW, parts)
	local P = K.PILL
	local p = parts or HatchLook.PillParts(btn)
	local coin = p.Coin and p.Coin.Size.X.Offset or 0
	local gap = rowGap(p.Label.TextSize)
	local content = math.ceil(coin + gap + priceW)
	local room = btn.Size.X.Offset - 2 * (P.Edge + P.LabelL)
	return content, labelW + gap + content <= room
end

-- the price row w px wide (0: hidden, the label takes the whole face) beside a label labelW px wide. parts: the button's
-- PillParts already looked up (review round 2: no lookups per refresh)
function HatchLook.SetPillChip(btn, w, parts, labelW)
	btn:SetAttribute("ChipW", math.max(0, w))
	btn:SetAttribute("LabelW", math.max(0, tonumber(labelW) or 0))
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
	CloudUI.SignBlock(pill, "Navy", { EdgePx = C.Edge, LipPx = C.Lip, Pad = false, Finish = false })
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

-- the Fast hatch chip: the navy chip with the kit's switch (CloudUI.SignSwitch: the "Switch" slot and its "Knob", the
-- Shop's part) and its "Label"
function HatchLook.FastChip(parent, opts)
	opts = opts or {}
	local z = opts.ZIndex or 1
	local btn = HatchLook.Chip(parent, { Name = opts.Name or "FastHatch", Text = "Fast hatch", TextSize = opts.TextSize, Phone = opts.Phone, ZIndex = z })
	local pill = btn:FindFirstChild("Pill")
	CloudUI.SignSwitch(pill, { ZIndex = z + 1, Finish = false })
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
		-- (look review: whole px) the slot's top a whole px, centred on the face above the lip
		local w, h = phone and C.SwitchWPhone or C.SwitchW, phone and C.SwitchHPhone or C.SwitchH
		local pillH = (phone and C.HPhone or C.H) - 2 * C.Edge
		sw.AnchorPoint = Vector2.new(0, 0)
		sw.Position = UDim2.fromOffset(C.SwitchX - C.Edge, math.floor((pillH - h) / 2) - math.floor(C.Lip / 2))
		sw.Size = UDim2.fromOffset(w, h)
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
	CloudUI.SignBlock(tag, look, { EdgePx = T.Edge, LipPx = T.Lip, Pad = false, Finish = false })
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
	CloudUI.SetSignSwitch(sw, on) -- (look review) the Shop's switch: gold while on, the knob slid across
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
