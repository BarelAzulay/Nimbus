-- TutorialController (client): Nimbus the Cloudy Dragon guides a new player (ARCHITECTURE_V3.md section 4).
--
--   TutorialController.Init()
--   TutorialController.GetState() -> the last TutorialState payload (nil until one arrived)
--
-- What it shows (all client-side, nothing system-announced in the screen centre):
--   * Side panel (ScreenGui "NimbusTutorial", display order 12): a compact cloud card on the LEFT, below the HUD's
--     top-left panel area and right of the menu column (both MEASURED: NimbusHud attribute TopLeftBottom /
--     BottomLeftTop and NimbusMenu.MenuColumn / MenuButton_*). It holds a round portrait of Nimbus (PetBuilder
--     Cloudy Dragon in a ViewportFrame, gently flapping, livelier while talking), the step title, "Step 3/9",
--     progress pips, the typewriter text, a hint line with the live distance, a Next button (CompleteOn = "Next",
--     or AlsoNext) and a small "Skip tutorial" link that asks to confirm. Tapping the portrait folds the card into a
--     bubble (the portrait keeps flapping in it, at half the frame rate; Pitch 2 item 03_tutorial_dock B: the "bubble"
--     is the quest strip, QuestStrip: the portrait chip, the step's title, "3/21", the steps in chapter blocks and a
--     "+" block that opens the card; PC / a landscape phone top-left under the top bar, a portrait phone on the HUD
--     stack over the vitals card; too narrow or meeting the arena's side stack: the portrait chip alone);
--     screens too small for the card get the bubble automatically. The HUD's bottom-left block (HP / stamina card)
--     is a hard limit: a bubble that has no room under the top-left panel (party / match panel on a landscape
--     phone) sits beside that panel instead. A card the player opens in the plain lobby may cover the idle vitals
--     card (and, as a last resort, the idle hotbar) but never the thumbstick, the touch buttons or the screen edge;
--     with a party panel up (a match is about to start) the vitals card, the currency pills and the hotbar are hard
--     limits wherever the card goes (beside the panel too; no room: the bubble); in a match it never covers the
--     vitals (the bubble), and a card opened in the lobby is folded back when the match starts. During
--     a battle on a phone (BattleController's compact team cards at the top / left edge) the panel hides until the
--     battle ends. While a menu window / the Pet Index / the roulette is open the card folds into the bubble
--     and the menu pointer hides. Designed in 1080p pixels under a UIScale of
--     Theme.ScreenFactor() (readability rule: body 20, captions 18, buttons 22, title 30 -> >= 14.4 px on phones).
--     Step completion: a voxel confetti burst from the portrait; the end of the tutorial: a bigger one.
--   * Guide arrow for world targets (Spot / Shop / Roulette / Portal, found by name under workspace.NimbusLobby,
--     the server's Target.Position as a fallback): a golden voxel arrow sculpted with shared/Voxel.lua that hops in two
--     hard steps (Pitch 2 item 13 A: no spin, no tween, no light), a stone name + distance tag beside its shaft and a
--     trail of flat gold dot blocks on the ground from just ahead of the feet toward the target (it was a Beam of a
--     sparkle strip and a ring of Neon sparkles) (workspace.ClientFx.TutorialGuide).
--   * TutorialController.Guide (Pitch 2 item 13 A): the travel guide the Shop's "Show the way" starts (see the section
--     "Travel guide" below): the same world guide to the Storm Altar gate, a "Guiding to Storm Altar" chip with its X.
--   * Menu targets: a pulsing gold ring around MenuButton_<Id> and a small pixel-art arrow pointing at it ("Home" rings
--     the Home tile, MenuButton_Spot)
--     (ScreenGui "NimbusTutorialPointer", display order 21, above the menu), on the first side of the button
--     (right, above, below, left) that is clear of the other tiles and of the tutorial card; none free (the
--     middle of the phone's 2 x 3 grid): the ring alone. The card / bubble keeps the arrow's spot free.
--   * Hidden in a match except the "finish" step text; the guides only show in the lobby.
-- Events sent through TutorialEvent (the server validates them against the current step): "Next", "Skip",
-- "ShopOpened" / "IndexOpened" / "PetsOpened" (MenuController.WindowOpened / IndexController.WindowOpened, the
-- OpenPanel remote and clicks on the matching menu button) and "Sync" (asks for the state again).
-- Per-frame work runs in ONE RenderStepped connection, only while something is shown.
-- Phase 5: nothing shows before the player pressed PLAY on the main menu (UiGate.WaitForPlay(600) before the first panel);
-- the portal step's world target is Portal_Obby (the ONE Obby portal of the Gate Court).
-- (kit B U9-9) The card and the pointer wear the Signboard kit, the layout and behaviour unchanged: the card is the wood
-- frame round a stone body with its lip (no shadow, puffs, gloss or gradient), the portrait a square sky well in a wood
-- frame (a little pixel cloud in its corner, the ground lip over Nimbus' feet), the name a plain Section title in brown,
-- the counter a stone tag, the fold a stone block with the pixel minus, the pips kit B blocks (a done step grass, the
-- current one gold, the rest the sunk well, each in a wood edge), the text well a pale tile in a wood edge, the hint line
-- in navy ink, Next the one green plank (gold on the last step), the skip confirm a red and a stone plank (Pitch 2 03 B:
-- the folded bubble's "!" badge and "Tap me!" plank gave way to the quest strip). Confetti in the kit's gold and pink, flat squares that flip (no rotation) on
-- whole pixels. The menu pointer's ring is a square gold frame in wood lines that breathes in whole pixels (no glow, no
-- fade); the pixel arrow is gold with a brown outline, its scale snapped so each 4 px cell is twice the screen's icon pixel. Icons and
-- edges under the card's scale stay on whole screen px (client/UI/PixelCrisp). The world guide sign is the world-text
-- wave's.
-- Plain Lua 5.1-compatible syntax only. All fonts come from Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))

local Client = script.Parent.Parent
local LocalPlayer = Players.LocalPlayer

local TutorialController = {}
-- (look:fix6b2 N3) Metrics.MEASURE(text, size, role) -> Vector2: a one-line text's size (design px) when a hook is set, else
-- Theme.Measure (TextService). tools/dump_gui.lua's tutorial scenes hand it the renderer's font metrics: the mock's
-- TextService answers a flat 0.5 em a letter, so the titles' fit (fitTextSize) kept 'The Champion Ring' (FredokaOne draws it
-- 0.545 em a letter) at its full size and the gate's render cut it to 'The Champion Ri...'; Roblox measures the face
TutorialController.Metrics = { MEASURE = nil }

----------------------------------------------------------------------
-- Tunables (design pixels of a 1080p screen unless noted)
----------------------------------------------------------------------
-- (U9-9 look 2) the card's lengths on the 0.8 grid (multiples of 5: whole px at 0.8 and 1.0; PixelCrisp snaps the rest,
-- at 0.7 or a fitted scale, on all four sides)
local K = {
	PANEL_W = 440,
	PANEL_MIN_W = 260,
	PAD = 15,
	PORTRAIT = 95,
	-- the portrait pops above the card, (U9-9 look 2) its top level with the name plank's gold edge (TAB_Y): the guide's
	-- name rides the card's top edge on a navy plank, as an NPC's does
	PORTRAIT_Y = -30,
	TAB_Y = -27, -- the name plank's top (its 3 px gold edge reaches PORTRAIT_Y) ...
	TAB_H = 35, -- ... and height: it ends 8 px into the card, clear above the counter tag and the fold (TAG_Y)
	TAB_INSET = 22, -- the name starts this far in from each end of its plank (12 px clear of a brass rivet; the NPC's)
	TAB_TEXT = 24, -- the name's largest size on the plank
	-- (2026-11-28 playtest C42: "NIMB..." on a 667x375 card, the engine drawing the name wider than TextService measured it
	-- at its floor) the name's box reaches this far into each inset past its plank's fit, 4 px clear of the rivets
	NAME_SLACK = 8,
	POP_EDGE = 6, -- at the screen's top edge the portrait and the plank may ride up to this far from the top (layout)
	TAG_Y = 16, -- the counter tag and the fold block (30 high), under the name plank's row
	TAG_H = 30,
	COUNTER_W = 105,
	FOLD_W = 35,
	HEADER_H = 95, -- card height above the text well
	WELL_PAD = 12,
	HINT_H = 26,
	FOOTER_H = 48,
	NAME_SIZE = 30,
	TITLE_SIZE = 22,
	-- (kit-b backlog items 10 / 16) a step title that does not fit one line at TITLE_FLOOR (its 14 screen px floor on the
	-- smallest card, 0.7) takes two lines at that size, the header TITLE_LINE taller (it was cut at 14.4 px: 'Pick Your Te...')
	TITLE_FLOOR = 20,
	TITLE_LINE = 24,
	BODY_SIZE = 20,
	CAPTION_SIZE = 18,
	BUTTON_SIZE = 22,
	NEXT_W = 150,
	BUTTON_H = 45,
	-- (U9-9 look) the step progress, one SignKit block row in whole SCREEN px (layoutProgress): its blocks PROG_H tall,
	-- PROG_GAP apart, a block per step while each gets PROG_MIN px (at most PROG_MAX), else a block per chapter of
	-- PROG_CHAPTER steps; the kit's 2 px wood edge and a PROG_LIP lip
	PROG_H = 12,
	PROG_GAP = 2,
	PROG_MIN = 10,
	PROG_MAX = 14,
	PROG_CHAPTER = 3,
	PROG_BLOCKS = 8, -- (kit-b gate U9 r4) the most single-step blocks; more steps show as chapters
	PROG_LIP = 2,
	NAME_MIN = 20, -- narrow cards shrink the name (and the step title down to CAPTION_SIZE) before truncating
	OUTLINE_ROOM = 6, -- the labels' glyph outline + stroke draw this much wider than TextService measures
	SKIP_W = 132,
	SKIP_SHORT_W = 56,
	CONFIRM_W = 92,
	CONFIRM_SHORT_W = 76,
	CONFIRM_TIGHT_W = 64,
	QUESTION_MIN = 90, -- the confirm question wraps to two lines down to this width, then shortens to "Skip?"
	QUESTION_SHORT_MIN = 60, -- "Skip?" needs this much on one line, else the confirm buttons narrow again
	EDGE = 12,
	TOUCH_EDGE = 20,
	GAP = 10,
	-- (kit-b backlog items 6 / 7 / 8) a window's hard shadow (Theme.Finish.Window), design px past its box to the right and
	-- down: the card's own, and the HUD's top-left panel's. GAP is kept off the ink, past it (box to box it left 0 - 2.4 px)
	SHADOW = 8,
	MIDDLE = 0.15, -- the screen middle the panel keeps out of: |dx| < 15% width and |dy| < 15% height
	TYPE_CPS = 52, -- typewriter characters per second
	TYPE_DELAY = 0.2,
	FIRST_SHOW_DELAY = 1.2,
	PANEL_ORDER = 12, -- HUD 10, hotbar 11, windows 20, toasts 30
	POINTER_ORDER = 21, -- above the menu column
	POINTER_ROOM = 92, -- room right of a Menu target for the arrow (68 px long, bouncing up to 15 px out)
	EVENT_COOLDOWN = 0.35,
	NEXT_LOCK = 2.5,
	SKIP_LOCK = 3,
	LAYOUT_EVERY = 0.5,
	COVER_EVERY = 0.15, -- (C17 review) seconds between two reads of a covering window's ink over the guide (Cover.underWindow)
	PORTRAIT_STEP = 1 / 30,
	PORTRAIT_FOLDED_STEP = 1 / 15, -- the folded bubble keeps flapping at half the rate (bug batch 2 #23; phone battery)
	FINALE_SECONDS = 4.5,
	-- world guide (studs)
	VOXEL = 0.36,
	ARROW_LIFT = 5, -- arrow centre above the target top (the arrow is ~7.6 studs tall: its tip clears the top)
	-- (Pitch 2 item 13 A) the arrow hops BOB studs every BOB_STEP s, two hard steps (it bobbed on a sine and spun)
	BOB = 0.6,
	BOB_STEP = 0.45,
	TRAIL_MAX = 90,
	TRAIL_HIDE = 10,
	-- (Pitch 2 item 13 A) the dot trail: DOT_SIZE-stud flat gold blocks every DOT_STEP studs from DOT_START studs ahead
	-- of the feet (at most DOT_MAX, out to TRAIL_MAX), laid again every DOT_EVERY s
	DOT_START = 2.5,
	DOT_STEP = 3,
	DOT_SIZE = 0.8,
	DOT_MAX = 30,
	DOT_EVERY = 0.25,
	-- floating guide sign (1080p design px, scaled by the screen factor): a stone tag (SIGN_EDGE wood edge, SIGN_LIP gold
	-- lip, SIGN_PAD in) SIGN_STUDS right of the arrow's axis (beside the shaft), SIGN_LIFT studs over the arrow's centre
	SIGN_W = 340,
	SIGN_H = 96,
	SIGN_NAME = 24,
	SIGN_INFO = 19,
	SIGN_EDGE = 3,
	SIGN_LIP = 4,
	SIGN_PAD = 14,
	SIGN_STUDS = 1.6,
	SIGN_GAP = 0.5, -- (look review fin0) studs between the arrow's widest part and the sign (its offset: W.signStuds)
	SIGN_LIFT = 1.5,
	RESOLVE_RETRY = 2,
	-- (Pitch 2 item 13 A; the owner's pick B of 2026-11-23, "Top-bar plank", the X on the right) the travel guide's chip,
	-- the top bar pill's twin: a cream stone plank (its wood edge outside the face, its lip inside) in Roblox's top band,
	-- its face GUIDE_DOCK screen px left of TopbarInset's right end (else GUIDE_RIGHT_RESERVE px off the screen's right:
	-- the '...' room), at the pill's height and row (TopBarController's rule: GUIDE_PILL / GUIDE_PILL_TOUCH px in a
	-- GUIDE_BAND px band, never under GUIDE_PILL_MIN), GUIDE_PILL_GAP px or more clear of the pill. A touch screen: the
	-- two-line ticket ([needle] place / 'NN studs away' [X]) in 1080p design px under the screen factor, each on whole
	-- screen px: GUIDE_PAD in, the GUIDE_MARK block, GUIDE_GAP to the lines (GUIDE_NAME over GUIDE_INFO, the muted ink),
	-- GUIDE_GAP to the red X block, a GUIDE_LIP lip; a portrait phone (no room in the band) the same ticket
	-- GUIDE_TICKET_H tall on the vitals stack, its ink GUIDE_STACK px over the name plank. A PC: one line at the pill's
	-- height ([needle] place [the 'NN studs' tag] [X]) in GUIDE_BAR_* screen px. Its X: a GUIDE_CLOSE px target. It
	-- arrives within GUIDE_ARRIVE studs of the gate, says so for GUIDE_HERE s and slides out in two steps over the last
	-- GUIDE_SLIDE s; the stud count is read every GUIDE_READ_EVERY s
	GUIDE_ORDER = 13,
	GUIDE_DOCK = 8,
	GUIDE_BAND = 58,
	GUIDE_RIGHT_RESERVE = 72,
	GUIDE_PILL = 40,
	GUIDE_PILL_TOUCH = 48,
	GUIDE_PILL_MIN = 32,
	GUIDE_PILL_GAP = 4,
	GUIDE_PAD = 8,
	GUIDE_MARK = 34,
	GUIDE_ICON = 18,
	GUIDE_GAP = 10,
	GUIDE_NAME = 22,
	GUIDE_INFO = 18,
	GUIDE_LIP = 5,
	GUIDE_TICKET_H = 55,
	GUIDE_STACK = 8,
	GUIDE_BAR_EDGE = 3,
	GUIDE_BAR_LIP = 4,
	GUIDE_BAR_PAD = 5,
	GUIDE_BAR_GAP = 10,
	GUIDE_BAR_NAME = 20,
	GUIDE_BAR_INFO = 18,
	GUIDE_BAR_TAG_H = 24,
	GUIDE_BAR_TAG_PAD = 7,
	GUIDE_BAR_TAG_GAP = 10,
	GUIDE_BAR_X_GAP = 12,
	GUIDE_BAR_LANE = 0.6, -- (look:chipB) a PC's one-line bar starts at 60 % of the width or further right, else the ticket
	GUIDE_CLOSE = 44,
	GUIDE_ARRIVE = 8,
	GUIDE_HERE = 3,
	GUIDE_SLIDE = 0.4,
	GUIDE_READ_EVERY = 0.25,
	-- (the pick) the needle: 'ahead' while the gate is on the screen; off it, behind from GUIDE_BEHIND degrees of bearing,
	-- a new sector only GUIDE_HOLD_DEG degrees past its edge; a change in two hard sprite steps, GUIDE_NEEDLE_STEP s apart
	GUIDE_BEHIND = 130,
	GUIDE_HOLD_DEG = 10,
	GUIDE_NEEDLE_STEP = 1 / 15,
	-- (the owner's portrait pick of 2026-11-24, "steps aside for signs": asideWanted) a portrait chip hides while a shown
	-- prompt plank stands within GUIDE_SIGN_KEEP px of its spot, back only once its spot has been clear of every sign
	-- for GUIDE_SIGN_DWELL s on end (the owner's pick of 2026-11-25: was 0.5 s from when it hid). 1.0 s covers the jumps
	-- at the gate (Config.Physics: 6.9 studs, 0.53 s in the air; where the plank meets the spot only near the top, the
	-- spot is clear for up to 0.93 s between two jumps 0.5 - 0.6 s apart) and tilts of 0.5 s each way: the smallest hold
	-- with no blink in travel_guide_plank at 30 and 60 fps (0.9 s blinked there)
	GUIDE_SIGN_KEEP = 6,
	GUIDE_SIGN_DWELL = 1.0,
	-- confetti (gui px at factor 1)
	CONFETTI_SMALL = 26,
	CONFETTI_BIG = 64,
	GRAVITY = 820,
	-- (kit B U9-9) the Signboard card
	FRAME = 6, -- the wood frame round the stone body
	CARD_LIP = 6, -- the stone body's lip
	FOOT_PAD = 18, -- the card's room under the text well (the frame, the lip and 4 px of stone)
	EDGE_PX = 2, -- a block's wood edge (the well, the tags, the pips)
	TAG_LIP = 3, -- a tag's lip (the counter, the fold, the badge, Tap me!)
	PORTRAIT_FRAME = 3, -- the portrait's wood frame
	PORTRAIT_LIP = 6, -- its ground lip
	NAME_LIP = 5, -- (U9-9 look 2) the name plank's navy lip (the NPC's)
	-- (Pitch 2 item 03_tutorial_dock, option B "Quest strip"; the owner's shot 03: folded, the guide was a lone sky tile with
	-- a "!" and a navy "Tap me!" tag, no step, no title) folded, the guide is one stone strip (STRIP_W x STRIP_H, a
	-- STRIP_EDGE wood edge, its STRIP_LIP lip): Nimbus' portrait chip (STRIP_CHIP square, STRIP_PAD in), the step's title
	-- (STRIP_TITLE: 23 px on PC, 18 on a phone's 0.8) with "3/21" right of it, under them the steps (STRIP_CELL_H tall: a
	-- chapter block of PROG_CHAPTER cells each, STRIP_CHAPTER_GAP screen px apart, 1 px of wood between two cells), and the
	-- STRIP_OPEN px "+" block that opens the card (>= 44 screen px at 0.8). PC and a landscape phone: top-left under the top
	-- bar (right of the menu column); a portrait phone: on the HUD stack, from the vitals card's left edge to the RUN / DASH
	-- column's right edge, STRIP_DOCK_GAP screen px over the vitals card. Narrower than STRIP_MIN_W, or meeting the arena's
	-- side stack: the portrait chip alone (its tap opens the card)
	STRIP_W = 440,
	STRIP_MIN_W = 300,
	STRIP_H = 76,
	STRIP_PAD = 8,
	STRIP_EDGE = 3,
	STRIP_LIP = 4,
	STRIP_CHIP = 56,
	STRIP_TITLE = 23,
	STRIP_TITLE_MIN = 18,
	STRIP_COUNT = 20,
	STRIP_OPEN = 56,
	STRIP_PLUS = 27,
	STRIP_COL_GAP = 10,
	STRIP_CELL_H = 14,
	STRIP_CHAPTER_GAP = 3,
	STRIP_DOCK_GAP = 10,
	-- (kit-b backlog items 7 / 8) a landscape chip's air off a HUD piece's box where STRIP_DOCK_GAP finds no spot (568 x 320
	-- in a match: 59 px between the thumbstick and the panel), screen px: 4 px of ink past a touch key's 3 px edge
	MIN_AIR = 7,
}

local BULLET = "\194\187 " -- >>
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7a) the portrait's fallback cloud

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local TC = Theme.Colors
local SIGN = Theme.Sign -- (kit B U9-9) the Signboard palette
-- (Pitch 2 item 13 A) the world guide's arrow wears the kit's gold: the face, its light and its lip (no own yellows)
local C = {
	Navy = TC.Navy or TC.Ink,
	Stroke = TC.TextStroke or TC.Ink,
	White = TC.White,
	Gold = TC.Gold or TC.Token,
	ArrowLight = SIGN.GoldLight or SIGN.Gold,
	Arrow = SIGN.Gold,
	ArrowDark = SIGN.GoldLip,
	ArrowShine = SIGN.Stone,
	-- (kit B U9-9) the kit's confetti: the reward's gold and the gift's pink, each with its lip (no rainbow)
	Confetti = { SIGN.Gold, SIGN.Roof, SIGN.GoldLip, SIGN.RoofLip },
}
TutorialController.Confetti = C.Confetti

-- client event -> the CompleteOn it completes (mirrors TutorialService)
local EVENT_NEEDS = { Next = "Next", ShopOpened = "ShopOpened", IndexOpened = "IndexOpened", PetsOpened = "Equipped" }
-- window / panel ids (WindowOpened, OpenPanel, menu buttons) -> event
local WINDOW_EVENTS = { Shop = "ShopOpened", Index = "IndexOpened", Pets = "PetsOpened", Inventory = "PetsOpened" }
-- the menu button that leads to what the current step waits for (store W1: the pill's Shop button opens the Robux
-- Store now, so ShopOpened has no button: the roulette machines open the Cloud Shop)
local HOOK_FOR = { IndexOpened = "Index", Equipped = "Pets" }
local WORLD_KINDS = { Spot = true, Shop = true, Roulette = true, Portal = true }
local DEFAULT_HINTS = {
	NearSpot = "Walk to your plot",
	ShopOpened = "Open the shop",
	Rolled = "Spin a roulette",
	Equipped = "Tap the Pets button", -- (U9-9 look) the kit B ring is a gold frame: nothing glows
	IndexOpened = "Tap the Index button",
	MatchStarted = "Step into the portal",
	MatchEnded = "Reach the finish",
}

-- Runtime tables (kept in a few tables so the module stays far below Lua's 200-locals limit)
local UI = {} -- panel + pointer instances
local S = { clock = 0, layoutTimer = 0, hintTimer = 0, typing = false } -- panel state
local P = { yaw = 0.38, side = -1, dist = 6, height = 3, accum = 0, excitedUntil = 0 } -- portrait
local M = { findTimer = 0 } -- menu pointer
local W = { built = false, active = false, resolveTimer = 0, labelTimer = 0 } -- world guide
local G = { active = false } -- (Pitch 2 item 13 A) the travel guide (TutorialController.Guide)
local R = { last = {}, hooked = {} } -- remotes + hooks
local Fx = { pool = {}, live = 0 } -- confetti
local Mods = {} -- optional modules: name -> table | false
local warned = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function warnOnce(key, message)
	if not warned[key] then
		warned[key] = true
		warn("[TutorialController] " .. tostring(message))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, key .. " failed: " .. tostring(err))
	end
	return ok
end

local function loadModule(container, name, timeout)
	if not container then
		return nil
	end
	local inst = container:FindFirstChild(name)
	if not inst and timeout then
		local okWait, found = pcall(function()
			return container:WaitForChild(name, timeout)
		end)
		if okWait then
			inst = found
		end
	end
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	warnOnce("load" .. name, "could not load " .. name .. ": " .. tostring(result))
	return nil
end

-- (2026-11-28 playtest C17 review) the windows over the guide: which fold the card and where they draw (one table: the
-- chunk is near Lua's 200 locals)
local Cover = {}
-- (at 667 x 375 the Ring, Dungeon and Arena windows, the Food Machine and the garden picker the steps send the player to
-- lay over the open card and the strip, 'The Champion Rin'; the Sky Trove and Fusion too, Fusion over the card on a PC)
-- every window family that answers IsOpen, after MenuController's (its windows, Pets, the Shop, the egg stage): one open
-- folds the card as a menu window does (windowCovering)
Cover.WINDOWS = { "IndexController", "DailyController", "NpcController", "ArenaController", "DungeonController",
	"CareController", "TrainController", "FusionController", "TroveController", "RaidGateController", "ObbyController",
	"LossScreen", "PetPicker" }
Cover.CONTROLLERS = {}
for _, name in ipairs(Cover.WINDOWS) do
	Cover.CONTROLLERS[name] = name ~= "PetPicker" -- (a UI module)
end

-- Optional collaborators, loaded on first use (missing ones simply switch a feature off).
local function mod(name)
	local cached = Mods[name]
	if cached == nil then
		local loaded
		if name == "CloudUI" or name == "PixelCrisp" then
			loaded = loadModule(Client:FindFirstChild("UI"), name, 5)
		elseif name == "PetPicker" then -- (2026-11-28 playtest C17 review: windowCovering, the garden picker)
			loaded = loadModule(Client:FindFirstChild("UI"), name)
		elseif name == "MenuController" or name == "IndexController" or name == "HudController" or name == "PromptController"
			or Cover.CONTROLLERS[name] then -- (2026-11-28 playtest C17: windowCovering)
			loaded = loadModule(script.Parent, name)
		else
			loaded = loadModule(Shared, name, 5)
		end
		cached = loaded or false
		Mods[name] = cached
	end
	return cached or nil
end

local function make(className, name, props, parent)
	local inst = Instance.new(className)
	inst.Name = name
	if props then
		for key, value in pairs(props) do
			inst[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- A transparent, borderless Frame unless props say otherwise.
local function box(name, props, parent)
	props = props or {}
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	props.BorderSizePixel = 0
	return make("Frame", name, props, parent)
end

local function corner(parent, px)
	return make("UICorner", "Corner", { CornerRadius = UDim.new(0, px) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return make("UIStroke", "Stroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- (kit B U9-9) a block's wood edge: a mitred border stroke named SignEdge, kept on whole screen px under the card's scale
local function edge(parent, color, px)
	local s = make("UIStroke", "SignEdge", {
		Color = color or SIGN.Wood,
		Thickness = px,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, parent)
	local crisp = mod("PixelCrisp")
	if crisp then
		crisp.Edge(s, px)
	end
	return s
end

-- a flat lip along the bottom of `parent` (px tall), (U9-9 look) whole screen px at any card scale
local function lipOf(parent, color, px)
	local lip = box("Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, px),
		ZIndex = parent.ZIndex,
	}, parent)
	local crisp = mod("PixelCrisp")
	if crisp then
		crisp.Lip(lip, px)
	end
	return lip
end

-- a pixel icon on whole screen px (PixelCrisp.Icon; a hosted glyph label when PixelCrisp is missing)
local function crispIcon(parent, name, px, colour, opts)
	local crisp = mod("PixelCrisp")
	if crisp then
		return crisp.Icon(parent, name, px, colour, opts)
	end
	opts = opts or {}
	local glyph = make("TextLabel", opts.Name or "Crisp", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = colour,
		AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = opts.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(px, px),
		ZIndex = opts.ZIndex or 1,
	}, parent)
	PixelIcon.Host(glyph, name, px)
	return glyph, glyph
end

-- (U9-9 look 2) a block on whole screen px of the card on all four sides (PixelCrisp.Box: its top-left and its size)
local function crispBox(obj)
	local crisp = mod("PixelCrisp")
	if crisp and obj then
		crisp.Box(obj)
	end
	return obj
end

-- A Theme-styled label. kit-b U6: the tutorial panel is a plate, so no outline (the guide sign over the world keeps its
-- own, below, until the world sign wave moves world text to kit B).
local function label(parent, name, text, role, size, color, props)
	local obj = Theme.Label(text, role, {
		Size = size,
		Color = color or C.White,
	})
	obj.Name = name
	if props then
		for key, value in pairs(props) do
			obj[key] = value
		end
	end
	obj.Parent = parent
	return obj
end

-- (kit B U9-9) a Signboard plank (CloudUI.Button Skin "Sign" when available, a flat kit B fallback otherwise).
local FALLBACK_FACE = { Green = "Grass", Gold = "Gold", Red = "Red" }
local function button(props)
	props.Skin = "Sign"
	local CloudUI = mod("CloudUI")
	if CloudUI and type(CloudUI.Button) == "function" then
		local ok, made = pcall(CloudUI.Button, props)
		if ok and made then
			return made
		end
	end
	local base = SIGN[FALLBACK_FACE[props.Style or "Green"] or "Tile"]
	local obj = make("TextButton", props.Name or "Button", {
		AutoButtonColor = true,
		BorderSizePixel = 0,
		BackgroundColor3 = base,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		Text = props.Text or "",
	})
	Theme.Style(obj, "Button", { Size = props.TextSize or K.BUTTON_SIZE, Color = props.Style == "Green" and SIGN.OnGrass or SIGN.Text })
	edge(obj, SIGN.Wood, 3)
	if props.Callback then
		obj.Activated:Connect(function()
			if obj:GetAttribute("Disabled") ~= true then
				props.Callback(obj)
			end
		end)
	end
	obj.Parent = props.Parent
	return obj
end

local function setDisabled(obj, disabled)
	if not obj then
		return
	end
	local CloudUI = mod("CloudUI")
	if CloudUI and type(CloudUI.SetDisabled) == "function" then
		pcall(CloudUI.SetDisabled, obj, disabled)
	else
		obj:SetAttribute("Disabled", disabled and true or false)
		obj.AutoButtonColor = not disabled
	end
end

local function setStyle(obj, style)
	local CloudUI = mod("CloudUI")
	if obj and CloudUI and type(CloudUI.SetStyle) == "function" then
		pcall(CloudUI.SetStyle, obj, style)
	elseif obj and Theme.Buttons and Theme.Buttons[style] then
		obj.BackgroundColor3 = Theme.Buttons[style]
	end
end

local function tween(inst, seconds, goal, style, direction)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

local function inMatch()
	return LocalPlayer:GetAttribute(Config.Attr.InMatch) == true
end

local function playerGui()
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function topInset()
	local inset = 0
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	return inset
end

-- y shift that converts another ScreenGui's AbsolutePosition into ours (ours does not ignore the inset).
local function insetShift(gui)
	if gui and gui:IsA("ScreenGui") and gui.IgnoreGuiInset then
		return -topInset()
	end
	return 0
end

local function shownIn(inst, rootGui)
	local node = inst
	while node and node ~= rootGui do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	if rootGui and rootGui:IsA("ScreenGui") and not rootGui.Enabled then
		return false
	end
	return node == rootGui
end

local function rectOf(inst, dy)
	local p, s = inst.AbsolutePosition, inst.AbsoluteSize
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
end

local function guiArea()
	local size = UI.Gui and UI.Gui.AbsoluteSize
	if size and size.X > 1 and size.Y > 1 then
		return size
	end
	local camera = Workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 1 then
		return Vector2.new(camera.ViewportSize.X, camera.ViewportSize.Y - topInset())
	end
	return Vector2.new(1280, 660)
end

local function rootPart()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function firstRouletteId()
	local list = Config.Roulettes
	if type(list) == "table" and type(list[1]) == "table" and type(list[1].Id) == "string" then
		return list[1].Id
	end
	return "Cloud"
end

local function graphemeCount(text)
	if utf8 and type(utf8.len) == "function" then
		local ok, n = pcall(utf8.len, text)
		if ok and type(n) == "number" then
			return n
		end
	end
	return #text
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
local function getRemote(name)
	local folder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 15)
	if not folder then
		return nil
	end
	local remote = folder:FindFirstChild(name) or folder:WaitForChild(name, 10)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

-- true when the current step shows the Next button: a "Next" step, or one with AlsoNext (bug batch 2 #24: the raid
-- step completes on its floor OR on Next)
local function nextShown(st)
	return st ~= nil and not st.Done and (st.CompleteOn == "Next" or st.AlsoNext == true)
end

-- Sends a tutorial event. Window / Next events go out only when the current step waits for them.
local function fireEvent(name)
	if not R.event then
		return false
	end
	if name ~= "Sync" and name ~= "Skip" then
		local st = S.state
		if not st or st.Done or (EVENT_NEEDS[name] ~= st.CompleteOn and not (name == "Next" and nextShown(st))) then
			return false
		end
	end
	local now = os.clock()
	local last = R.last[name]
	if last and now - last < K.EVENT_COOLDOWN then
		return false
	end
	R.last[name] = now
	local ok = pcall(function()
		R.event:FireServer(name)
	end)
	return ok
end

local function onWindowOpened(windowId)
	local event = WINDOW_EVENTS[tostring(windowId)]
	if event then
		fireEvent(event)
	end
end

----------------------------------------------------------------------
-- Panel: measuring + layout
----------------------------------------------------------------------
-- Height of the wrapped body text (design px). TextService wraps at the frame width; a result wider than the
-- frame means it did not wrap, so a per-line estimate is used instead.
local function bodyHeight(text, width)
	local perLine = math.max(8, math.floor(width / (K.BODY_SIZE * 0.52)))
	local estimate = math.max(1, math.ceil(#text / perLine)) * math.ceil(K.BODY_SIZE * 1.2) + 6
	local ok, size = pcall(function()
		return Theme.Measure(text, "Body", K.BODY_SIZE, width)
	end)
	if ok and size and size.Y > 0 and size.X <= width + 1 then
		return math.ceil(size.Y) + 6
	end
	return estimate
end

-- Single-line text width (design px) in a Theme role, as the label shows it ((U9-9 look) a caps role in capitals, a
-- FontFace role widened: the Title role's Enum font in lower case measured "NIMBUS" 10 % short, and the name came out
-- "NIMB..."); a rough per-character estimate when TextService cannot measure.
local function textWidth(text, size, role)
	local hook = TutorialController.Metrics.MEASURE
	local ok, measured = pcall(function()
		if hook then
			return hook(text, size, role)
		end
		return Theme.Measure(text, role, size, 10000)
	end)
	if ok and measured and measured.X > 0 then
		return measured.X
	end
	return #text * size * 0.62
end

-- The largest text size from `size` down to `minSize` (steps of 2, the last step to minSize itself) whose text fits
-- `room` design px.
local function fitTextSize(text, size, minSize, role, room)
	while size > minSize and textWidth(text, size, role) + K.OUTLINE_ROOM > room do
		size = math.max(minSize, size - 2)
	end
	return size
end

-- (kit-b backlog item 10) the lines `text` wraps to at `size` in `width` design px, word by word as the engine wraps it,
-- each line measured as it shows (textWidth: the titles' measure) with its glyph outline's room
local function wrapLines(text, size, role, width)
	local lines, line = 0, nil
	for sep, word in string.gmatch(text, "(%s*)(%S+)") do
		local try = line and (line .. sep .. word) or word
		if line and textWidth(try, size, role) + K.OUTLINE_ROOM > width then
			lines, line = lines + 1, word
		else
			line = try
		end
	end
	return lines + (line and 1 or 0)
end

-- (U9-9 look) the objective line wraps to a second line rather than cut its words (it was "Tap the glowing Pet..." on a
-- portrait phone): measured at the size it takes on the smallest card (14 screen px at 0.7) with the room the distance
-- suffix needs, so the card never jumps in height as the player walks. Returns its row's design height and its lines.
-- (kit-b backlog item 10: 13 objective lines ran past a one-line row - 960 x 540 '...then Food' / 'Machine' - where
-- TextService's wrapped height was read as one line; and a third line was never counted) its lines counted word by word
-- (wrapLines), as many as it takes
local HINT_MEASURE = math.max(K.CAPTION_SIZE, math.ceil(14 / 0.7 - 1e-6))
local function hintHeight(width)
	local st = S.state
	local text = st and (st.Hint or DEFAULT_HINTS[st.CompleteOn]) or ""
	if st and type(st.Target) == "table" and WORLD_KINDS[st.Target.Kind] then
		text = text .. "  \194\183  you're here!" -- (kit-b backlog item 10: the middle dot, as the live line has it; it was the bytes 1, "94", 1, "83")
	end
	local lines = math.max(1, wrapLines(BULLET .. text, HINT_MEASURE, "Label", width))
	return K.HINT_H + (lines - 1) * math.ceil(HINT_MEASURE * 1.2), lines
end

-- (kit-b backlog items 10 / 16: 'Pick Your Te...', 'Your Pet Gar...' on a narrow card at the 14.4 px floor) the lines the
-- step's title takes in a card `width` design px wide: 1 where it fits one line of the header at K.TITLE_FLOOR - its floor
-- on the smallest card (14 screen px at 0.7) -, else the lines it wraps to at that size (applyGeometry, panelHeight)
local function titleLines(width)
	local title = UI.StepTitle and UI.StepTitle.Text or ""
	local room = width - (K.PAD + K.PORTRAIT + 12) - K.PAD
	if title == "" or textWidth(title, K.TITLE_FLOOR, "Heading") + K.OUTLINE_ROOM <= room then
		return 1
	end
	return math.max(2, wrapLines(title, K.TITLE_FLOOR, "Heading", room))
end

-- the header's extra design px for the title's lines: each line past the first is K.TITLE_LINE, but on a narrow card (no
-- counter tag) the progress row moves up beside the fold block and the first two lines fit the header (applyGeometry)
local function titleExtraOf(width, lines)
	local headRoom = width - (K.PAD + K.PORTRAIT + 12) - K.PAD
	local counterShown = headRoom >= K.COUNTER_W + 6 + K.FOLD_W
	return math.max(0, lines - (counterShown and 1 or 2)) * K.TITLE_LINE
end

local function hintShown()
	local st = S.state
	-- (S.compactCard: a short screen's opened card drops the objective line; the text above says the same)
	return st ~= nil and not st.Done and st.CompleteOn ~= "Next" and not S.finale and not S.compactCard
end

local function footerShown()
	return not S.finale
end

-- Design-pixel height of the expanded panel at `width` (cached per width + text), its body's and its hint's, and the
-- header's extra for a title on more lines (titleLines, titleExtraOf).
local function panelHeight(width)
	local text = S.fullText or ""
	local st = S.state
	local title = UI.StepTitle and UI.StepTitle.Text or ""
	local key = tostring(width) .. "|" .. text .. "|" .. tostring(hintShown()) .. "|" .. tostring(footerShown()) .. "|" .. tostring(st and st.Step) .. "|" .. title
	if S.heightKey == key then
		return S.heightValue, S.bodyValue, S.hintValue, S.titleExtraValue
	end
	local wellW = width - 2 * K.PAD - 2 * K.WELL_PAD
	local bodyH = bodyHeight(text, wellW)
	local titleExtra = titleExtraOf(width, titleLines(width))
	local h = K.HEADER_H + titleExtra + 10 + bodyH + 8 + K.FOOT_PAD -- (kit B U9-9) the well ends above the stone lip
	local hintH = K.HINT_H
	if hintShown() then
		hintH = hintHeight(wellW)
		h = h + hintH + 4
	end
	if footerShown() then
		h = h + K.FOOTER_H
	end
	S.heightKey, S.heightValue, S.bodyValue, S.hintValue, S.titleExtraValue = key, h, bodyH, hintH, titleExtra
	return h, bodyH, hintH, titleExtra
end

-- MenuController's column (or the union of its MenuButton_* tiles) in our gui coordinates.
local function menuRect()
	local pg = playerGui()
	local menuGui = pg and pg:FindFirstChild("NimbusMenu")
	if not (menuGui and menuGui:IsA("ScreenGui") and menuGui.Enabled) then
		return nil
	end
	local dy = insetShift(menuGui)
	local column = menuGui:FindFirstChild("MenuColumn", true)
	if column and column:IsA("GuiObject") and column.AbsoluteSize.X > 0 and shownIn(column, menuGui) then
		return rectOf(column, dy)
	end
	local found = nil
	for _, d in ipairs(menuGui:GetDescendants()) do
		if d:IsA("GuiObject") and string.sub(d.Name, 1, 11) == "MenuButton_" and d.AbsoluteSize.X > 0 and shownIn(d, menuGui) then
			local r = rectOf(d, dy)
			if found then
				found.x0, found.y0 = math.min(found.x0, r.x0), math.min(found.y0, r.y0)
				found.x1, found.y1 = math.max(found.x1, r.x1), math.max(found.y1, r.y1)
			else
				found = r
			end
		end
	end
	return found
end

-- (look:fix6b2 N1) the menu column as far as it reaches: menuRect with every shown button in the column - its tiles, its
-- fold tab and the tab's tap pad (MenuController's ToggleHit, reaching right into the free sky); nil without a column
local function columnReach()
	local r = menuRect()
	local pg = playerGui()
	local menuGui = pg and pg:FindFirstChild("NimbusMenu")
	local column = r and menuGui and menuGui:FindFirstChild("MenuColumn", true)
	if not column then
		return r
	end
	local dy = insetShift(menuGui)
	for _, d in ipairs(column:GetDescendants()) do
		if d:IsA("GuiButton") and d.AbsoluteSize.X > 0 and shownIn(d, menuGui) then
			local b = rectOf(d, dy)
			r = { x0 = math.min(r.x0, b.x0), y0 = math.min(r.y0, b.y0), x1 = math.max(r.x1, b.x1), y1 = math.max(r.y1, b.y1) }
		end
	end
	return r
end

-- HUD neighbours (published by HudController, gui px): bottom of the top-left panel area and top of the
-- bottom-left block (vitals / currency), plus the top-left panel's right edge and the top-right stack (0 when absent).
local function hudBounds(area)
	local pg = playerGui()
	local hud = pg and pg:FindFirstChild("NimbusHud")
	local out = { TopLeftBottom = 0, TopLeftRight = 0, BottomLeftTop = area.Y, TopRightLeft = 0, TopRightBottom = 0 }
	if hud and hud:IsA("ScreenGui") and hud.Enabled then
		local dy = insetShift(hud)
		local a = tonumber(hud:GetAttribute("TopLeftBottom"))
		if a and a > 0 then
			out.TopLeftBottom = a + dy
		end
		local b = tonumber(hud:GetAttribute("BottomLeftTop"))
		if b and b > 0 then
			out.BottomLeftTop = b + dy
		end
		local r = tonumber(hud:GetAttribute("TopLeftRight"))
		if r and r > 0 and out.TopLeftBottom > 0 then
			out.TopLeftRight = r
		end
		local trl = tonumber(hud:GetAttribute("TopRightLeft"))
		local trb = tonumber(hud:GetAttribute("TopRightBottom"))
		if trl and trl > 0 and trb and trb > 0 then
			out.TopRightLeft, out.TopRightBottom = trl, trb + dy
		end
	end
	return out
end

-- The hotbar in our gui coordinates (nil when there is none on screen).
local function hotbarRect()
	local pg = playerGui()
	local bar = pg and pg:FindFirstChild("NimbusHotbar")
	local frame = bar and bar:FindFirstChild("Hotbar")
	if frame and frame:IsA("GuiObject") and frame.AbsoluteSize.X > 0 and shownIn(frame, bar) then
		return rectOf(frame, insetShift(bar))
	end
	return nil
end

-- The HUD's bottom-left block (vitals card, currency pills) as rects in our gui coordinates. ((kitb-matchhud) `noVitals`:
-- without the vitals card)
local function bottomLeftRects(noVitals)
	local out = {}
	local pg = playerGui()
	local hud = pg and pg:FindFirstChild("NimbusHud")
	local block = hud and hud:FindFirstChild("BottomLeft")
	if not (block and hud:IsA("ScreenGui") and hud.Enabled) then
		return out
	end
	local dy = insetShift(hud)
	for _, child in ipairs(block:GetChildren()) do
		if child:IsA("GuiObject") and child.AbsoluteSize.X > 0 and shownIn(child, hud) and not (noVitals and child.Name == "Vitals") then
			out[#out + 1] = rectOf(child, dy)
		end
	end
	return out
end

-- (kitb-matchhud) the vitals card's slot, shown or stepped aside (HudController.GetLayout().VitalsSlot: gui-area px of an
-- IgnoreGuiInset = false gui, as ours), nil when there is none
local function vitalsSlot()
	local hud = mod("HudController")
	if not (hud and type(hud.GetLayout) == "function") then
		return nil
	end
	local ok, lay = pcall(hud.GetLayout)
	local s = ok and type(lay) == "table" and lay.VitalsSlot
	if not s then
		return nil
	end
	return { x0 = s.X, y0 = s.Y, x1 = s.X + s.W, y1 = s.Y + s.H }
end

-- Phase 3: the compact battle team cards (BattleController on phones and small windows: a row under the battle's
-- top card, or a grid at the left edge of a landscape phone where the menu tiles were) while the player fights;
-- nil otherwise (no battle, or the wide layout's team card at the bottom right).
local function battleTeamRect(area)
	local pg = playerGui()
	local battle = pg and pg:FindFirstChild("NimbusBattle")
	local root = battle and battle:FindFirstChild("Root")
	local team = root and root:FindFirstChild("Team")
	if team and team:IsA("GuiObject") and team.AbsoluteSize.X > 0 and shownIn(team, battle) then
		local r = rectOf(team, insetShift(battle))
		if r.y0 < area.Y * 0.4 then
			return r
		end
	end
	return nil
end

-- Roblox's touch thumbstick (bottom-left; the classic stick or the dynamic stick's idle ring, whichever is
-- bigger) in gui px, nil without touch.
local function thumbstickRect(area)
	if not UserInputService.TouchEnabled then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or area
	if math.min(vp.X, vp.Y) <= 500 then
		return { x0 = 25, y0 = area.Y - 96, x1 = 104, y1 = area.Y - 20 }
	end
	return { x0 = 58, y0 = area.Y - 210, x1 = 206, y1 = area.Y - 90 }
end

-- The touch RUN / DASH buttons (MovementController's MobileControls) in our gui coordinates.
local function touchButtonRects()
	local out = {}
	local pg = playerGui()
	local mobile = pg and pg:FindFirstChild("MobileControls")
	if not (mobile and mobile:IsA("ScreenGui") and mobile.Enabled) then
		return out
	end
	local dy = insetShift(mobile)
	for _, d in ipairs(mobile:GetDescendants()) do
		if d:IsA("GuiButton") and d.AbsoluteSize.X > 0 and shownIn(d, mobile) then
			out[#out + 1] = rectOf(d, dy)
		end
	end
	return out
end

-- A menu window, the odds popup, the roulette stage or the Pet Index is open (they cover the menu and the card).
local function windowCovering()
	local menu = mod("MenuController")
	if menu and type(menu.IsOpen) == "function" then
		local ok, open = pcall(menu.IsOpen)
		if ok and open == true then
			return true
		end
	end
	-- (2026-11-28 playtest C17) the Gifts window and an NPC's dialog stacked on the open card: they cover it too, as every
	-- other window family does (Cover.WINDOWS, C17 review)
	for _, name in ipairs(Cover.WINDOWS) do
		local m = mod(name)
		if m and type(m.IsOpen) == "function" then
			local ok, open = pcall(m.IsOpen)
			if ok and open == true then
				return true
			end
		end
	end
	-- (C17) and a phone's dungeon chip in the top band (DungeonController's RunChip: the party countdown, the run) lay
	-- under the strip, 'Door: tap Enter' read 'Enter'
	local pg = playerGui()
	local run = pg and pg:FindFirstChild("NimbusDungeonRun")
	local chip = run and run:FindFirstChild("RunChip", true)
	if chip and chip:IsA("GuiObject") and run:IsA("ScreenGui") and chip.AbsoluteSize.X > 0 and shownIn(chip, run) then
		return true
	end
	return false
end

-- Folded into the bubble? A window on top (S.windowOpen) or a card that cannot fit on this screen right now
-- (S.forcedBubble) always folds it; otherwise the player's choice, else automatic (the card does not fit).
local function collapsed()
	if S.windowOpen or S.forcedBubble then
		return true
	end
	if S.finale then
		return false
	end
	if S.manual == "collapsed" then
		return true
	end
	return S.manual ~= "expanded" and S.autoCollapse == true
end

-- (U9-9 look) the step progress: ONE SignKit.BlockRow (the kit's block-bar language: a wood edge, the face, its darker
-- lip) in a holder that undoes the card's scale, so its blocks, gaps, edges and lips are whole screen px at every card
-- size. A block per step while each gets K.PROG_MIN px, else a block per chapter of K.PROG_CHAPTER steps: done grass,
-- the current gold, the rest the sunk well with no lip. (The pips, their tight variant and the thin bar it replaces
-- were four looks for one thing.)
local PROG_LOOK = {
	Done = { Face = SIGN.Grass, Lip = SIGN.GrassLip },
	Current = { Face = SIGN.Gold, Lip = SIGN.GoldLip },
	Open = { Face = SIGN.Well },
}

-- (Pitch 2 03 B) the quest strip's steps for S.progStep / S.progDone: a done step's cell grass, the current one gold,
-- the rest the sunk well (the card's row looks, one cell a step)
local function paintStripSteps()
	local row = UI.StripRow
	if not row then
		return
	end
	local step, done = S.progStep or 0, S.progDone == true
	for _, cell in ipairs(row:GetDescendants()) do
		local s = cell:GetAttribute("Step")
		if s then
			local state = (done or s < step) and "Done" or (s == step and "Current" or "Open")
			cell.BackgroundColor3 = PROG_LOOK[state].Face
			cell:SetAttribute("State", state)
		end
	end
	row:SetAttribute("Current", done and 0 or step)
end

-- paints the row for `current` (the step shown; 0 with allDone for the finale); no arguments: the last ones again
local function paintProgress(current, allDone)
	if current ~= nil then
		S.progStep, S.progDone = current, allDone == true
	end
	paintStripSteps()
	local row = UI.ProgressRow
	if not row then
		return
	end
	local per = row:GetAttribute("PerBlock") or 1
	local n = row:GetAttribute("Count") or 0
	local step = S.progStep or 0
	local now = step >= 1 and math.ceil(step / per) or 0
	for i = 1, n do
		local state = "Open"
		if S.progDone or i < now then
			state = "Done"
		elseif i == now then
			state = "Current"
		end
		local block = row:FindFirstChild("Block" .. i)
		local face = block and block:FindFirstChild("Face")
		if face then
			local look = PROG_LOOK[state]
			block:SetAttribute("State", state)
			face.BackgroundColor3 = look.Face
			face.BackgroundTransparency = 0
			local lip = face:FindFirstChild("Lip")
			if lip then
				lip.Visible = look.Lip ~= nil
				lip.BackgroundColor3 = look.Lip or look.Face
			end
		end
	end
	row:SetAttribute("Current", (S.progDone and 0) or now)
end

-- the face of the block the current step is in (it breathes), nil when there is none
local function currentProgressFace()
	local row = UI.ProgressRow
	local now = row and row:GetAttribute("Current")
	local block = row and now and now > 0 and row:FindFirstChild("Block" .. now)
	return block and block:FindFirstChild("Face") or nil
end

-- sizes the row to `room` design px of the header at the card's scale, rebuilding it when its blocks change
local function layoutProgress(room)
	local holder = UI.Progress
	if not holder then
		return
	end
	local crisp = mod("PixelCrisp")
	local k = math.max(0.1, crisp and crisp.ScaleAbove(holder) or UI.Scale.Scale)
	local total = S.progTotal or 0
	local roomPx = math.max(0, math.floor(room * k))
	local per, n = 1, total
	local bw = n > 0 and math.floor((roomPx + K.PROG_GAP) / n) - K.PROG_GAP or 0
	-- (kit-b gate U9 r4: 21 thin blocks beside "Step 1/21" said the same thing twice, as noise) more than PROG_BLOCKS steps
	-- show as chapters of PROG_CHAPTER (21 steps: 7 blocks); the counter keeps the exact step
	if bw < K.PROG_MIN or n > K.PROG_BLOCKS then
		per = K.PROG_CHAPTER
		n = math.ceil(total / per)
		bw = n > 0 and math.floor((roomPx + K.PROG_GAP) / n) - K.PROG_GAP or 0
	else
		bw = math.min(bw, K.PROG_MAX)
	end
	local unscale = holder:FindFirstChild("Unscale")
	if unscale and unscale.Scale ~= 1 / k then
		unscale.Scale = 1 / k
	end
	holder.Size = UDim2.fromOffset(roomPx, K.PROG_H)
	local key = n .. "|" .. bw .. "|" .. per .. "|" .. total
	if S.progKey ~= key or not (UI.ProgressRow and UI.ProgressRow.Parent) then
		S.progKey = key
		if UI.ProgressRow then
			UI.ProgressRow:Destroy()
			UI.ProgressRow = nil
		end
		local SignKit = mod("SignKit")
		if SignKit and n > 0 and bw > 0 then
			local row = SignKit.BlockRow(holder, { Count = n, BlockW = bw, BlockH = K.PROG_H, Gap = K.PROG_GAP })
			row:SetAttribute("PerBlock", per)
			row:SetAttribute("Steps", total)
			for i = 1, n do
				local block = row:FindFirstChild("Block" .. i)
				local face = block and block:FindFirstChild("Face")
				local lip = face and face:FindFirstChild("Lip")
				if lip then
					lip.Size = UDim2.new(1, 0, 0, K.PROG_LIP)
				end
			end
			UI.ProgressRow = row
		end
	end
	paintProgress()
end

-- (Pitch 2 03 B) sizes the quest strip's steps to `room` design px at the strip's scale: one chapter block of
-- K.PROG_CHAPTER cells per chapter (21 steps: 7 blocks of 3, so the row and "3/21" agree), each block a wood frame
-- (2 screen px) round its cells with 1 px of wood between two; rebuilt only when the blocks change
local function layoutStripSteps(room)
	local holder = UI.StripSteps
	if not holder then
		return
	end
	local crisp = mod("PixelCrisp")
	local k = math.max(0.1, crisp and crisp.ScaleAbove(holder) or UI.Scale.Scale)
	local total = S.progTotal or 0
	local per = K.PROG_CHAPTER
	local n = math.ceil(total / per)
	local roomPx = math.max(0, math.floor(room * k))
	local hPx = math.max(8, math.floor(K.STRIP_CELL_H * k + 0.5))
	local gap, e = K.STRIP_CHAPTER_GAP, 2
	local bw = n > 0 and math.floor((roomPx + gap) / n) - gap or 0
	local unscale = holder:FindFirstChild("Unscale")
	if unscale and unscale.Scale ~= 1 / k then
		unscale.Scale = 1 / k
	end
	holder.Size = UDim2.fromOffset(roomPx, hPx)
	local key = n .. "|" .. bw .. "|" .. hPx .. "|" .. total
	if S.stripKey ~= key or not (UI.StripRow and UI.StripRow.Parent) then
		S.stripKey = key
		if UI.StripRow then
			UI.StripRow:Destroy()
			UI.StripRow = nil
		end
		if n > 0 and bw > 2 * e + per then
			local row = box("Row", { Size = UDim2.fromOffset(n * (bw + gap) - gap, hPx), ZIndex = 2 }, holder)
			row:SetAttribute("Steps", total)
			row:SetAttribute("PerBlock", per)
			for i = 1, n do
				local block = box("Chapter" .. i, {
					BackgroundTransparency = 0,
					BackgroundColor3 = SIGN.Wood,
					Position = UDim2.fromOffset((i - 1) * (bw + gap), 0),
					Size = UDim2.fromOffset(bw, hPx),
					ZIndex = 2,
				}, row)
				local c = math.min(per, total - (i - 1) * per)
				local inner = bw - 2 * e
				local cw = math.floor((inner - (c - 1)) / c)
				local x = e
				for j = 1, c do
					local w = (j == c) and (bw - e - x) or cw
					local cell = box("Cell" .. j, {
						BackgroundTransparency = 0,
						BackgroundColor3 = SIGN.Well,
						Position = UDim2.fromOffset(x, e),
						Size = UDim2.fromOffset(w, hPx - 2 * e),
						ZIndex = 2,
					}, block)
					cell:SetAttribute("Step", (i - 1) * per + j)
					x = x + cw + 1
				end
			end
			UI.StripRow = row
		end
	end
	paintStripSteps()
end

-- (Pitch 2 03 B) the HUD's vitals card (NimbusHud.BottomLeft.Vitals) in our gui px, nil when it is not shown
local function vitalsRect()
	local pg = playerGui()
	local hud = pg and pg:FindFirstChild("NimbusHud")
	local block = hud and hud:FindFirstChild("BottomLeft")
	local vitals = block and block:FindFirstChild("Vitals")
	if vitals and vitals:IsA("GuiObject") and vitals.AbsoluteSize.X > 0 and shownIn(vitals, hud) then
		return rectOf(vitals, insetShift(hud))
	end
	return nil
end

-- (Pitch 2 03 B, the spec's caveat) the arena's side stack (ArenaController: NimbusArenaSide.SideStack, anchored at the
-- bottom right and growing upward) in our gui px while it holds a shown card, nil otherwise
local function arenaSideRect()
	local pg = playerGui()
	local gui = pg and pg:FindFirstChild("NimbusArenaSide")
	local side = gui and gui:FindFirstChild("SideStack")
	if not (side and side:IsA("GuiObject") and side.AbsoluteSize.X > 0 and shownIn(side, gui)) then
		return nil
	end
	for _, c in ipairs(side:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible and c.AbsoluteSize.Y > 0 then
			return rectOf(side, insetShift(gui))
		end
	end
	return nil
end

-- (Pitch 2 03 B) lays the folded guide out as the quest strip at `x, y` (gui px), `w` design px wide, or as the portrait
-- chip alone (`chip`): the strip's parts, the portrait on its left end, the "+" only while the card can open
local function placeStrip(w, chip)
	local pad, c = K.STRIP_PAD, K.STRIP_CHIP
	UI.Strip.Visible = not chip
	if chip then
		UI.Portrait.Position = UDim2.fromOffset(0, 0)
		UI.Portrait.Size = UDim2.fromOffset(c, c)
		return
	end
	UI.Strip.Position = UDim2.fromOffset(0, 0)
	UI.Strip.Size = UDim2.fromOffset(w, K.STRIP_H)
	UI.Portrait.Position = UDim2.fromOffset(pad, pad)
	UI.Portrait.Size = UDim2.fromOffset(c, c)
	local canOpen = S.canOpen ~= false and not S.windowOpen
	UI.StripOpen.Visible = canOpen
	local openX = w - pad - K.STRIP_OPEN
	UI.StripOpen.Position = UDim2.fromOffset(openX, pad)
	UI.StripOpen.Size = UDim2.fromOffset(K.STRIP_OPEN, c)
	local x0 = pad + c + K.STRIP_COL_GAP
	local x1 = canOpen and (openX - K.STRIP_COL_GAP) or (w - pad - K.STRIP_COL_GAP)
	local colW = math.max(20, x1 - x0)
	local titleH = K.STRIP_TITLE + 6
	local count = UI.StripCount.Text
	local countW = math.ceil(textWidth(count, K.STRIP_COUNT, "Heading")) + K.OUTLINE_ROOM
	UI.StripCount.Position = UDim2.fromOffset(x1 - countW, pad)
	UI.StripCount.Size = UDim2.fromOffset(countW, titleH)
	local titleW = math.max(20, colW - countW - 8)
	local title = UI.StripTitle.Text
	local size = fitTextSize(title, K.STRIP_TITLE, K.STRIP_TITLE_MIN, "Heading", titleW)
	-- (kit-b backlog items 10 / 16: 'The Pet Ind...' at 640 x 360) a title that does not fit beside its count even at its
	-- floor takes the count's room too: the strip drops "6/21" (its step cells still show the progress), as a narrow card
	-- drops its counter tag
	local showCount = textWidth(title, size, "Heading") + K.OUTLINE_ROOM <= titleW
	UI.StripCount.Visible = showCount
	if not showCount then
		titleW = colW
		size = fitTextSize(title, K.STRIP_TITLE, K.STRIP_TITLE_MIN, "Heading", titleW)
	end
	UI.StripTitle.TextSize = size
	UI.StripTitle.Position = UDim2.fromOffset(x0, pad)
	UI.StripTitle.Size = UDim2.fromOffset(titleW, titleH)
	local stepsY = pad + titleH + 4
	UI.StripSteps.Position = UDim2.fromOffset(x0, stepsY)
	layoutStripSteps(colW)
end

-- (U9-9 look) the HUD's vitals card steps aside while the opened card lies over a part of it (the plain lobby's card
-- the player opened on a short screen), as the result card and the NPC dialog do; back when the card folds or goes.
-- `rect`: the opened card in gui px, nil when it is folded or hidden. ((kitb-matchhud) `aside`: the folded chip's spot
-- holds them aside - layout's landscape chip)
local function syncVitals(rect, aside)
	local off = aside == true
	local hud = mod("HudController")
	if not off and rect and hud and type(hud.GetLayout) == "function" then
		local okLayout, lay = pcall(hud.GetLayout)
		local slot = okLayout and type(lay) == "table" and lay.VitalsSlot
		if slot then -- (gui-area px of an IgnoreGuiInset = false gui, as ours)
			local w = math.min(rect.x1, slot.X + slot.W) - math.max(rect.x0, slot.X)
			local h = math.min(rect.y1, slot.Y + slot.H) - math.max(rect.y0, slot.Y)
			off = w > 4 and h > 4
		end
	end
	if off ~= (S.vitalsOff == true) and hud and type(hud.SetVitalsHidden) == "function" then
		S.vitalsOff = off
		pcall(hud.SetVitalsHidden, "Tutorial", off)
	end
end

-- Applies the inner geometry of the panel for a design width / height (`titleExtra`: the header's second title line).
local function applyGeometry(width, height, bodyH, hintH, titleExtra)
	titleExtra = titleExtra or 0
	UI.Root.Size = UDim2.fromOffset(width, height)
	-- (kit-b backlog items 10 / 16) a title on two lines or more (titleLines): on a narrow card, with no counter tag, the
	-- progress row takes the tag's place left of the fold block and the title the progress row's, so two lines keep the
	-- header's height (a short phone's card has no px to spare); the progress row and the text well titleExtra lower.
	-- (written only when they move: PixelCrisp keeps its whole-px nudge in their Scale)
	local x0 = K.PAD + K.PORTRAIT + 12
	local headRoom = width - x0 - K.PAD
	local counterShown = headRoom >= K.COUNTER_W + 6 + K.FOLD_W
	local wraps = titleLines(width) > 1
	local progUp = wraps and not counterShown
	local function at(obj, x, y)
		if obj.Position.X.Offset ~= x or obj.Position.Y.Offset ~= y then
			obj.Position = UDim2.fromOffset(x, y)
		end
	end
	at(UI.Progress, x0, progUp and (K.TAG_Y + math.floor((K.TAG_H - K.PROG_H) / 2)) or (76 + titleExtra))
	at(UI.Well, K.PAD, K.HEADER_H + titleExtra)
	if UI.Well.Size.Y.Offset ~= -(K.HEADER_H + titleExtra + K.FOOT_PAD) then
		UI.Well.Size = UDim2.new(1, -2 * K.PAD, 1, -(K.HEADER_H + titleExtra + K.FOOT_PAD))
	end
	UI.Body.Size = UDim2.new(1, -2 * K.WELL_PAD, 0, bodyH)
	UI.TypeSkip.Size = UI.Body.Size
	UI.Hint.Position = UDim2.fromOffset(K.WELL_PAD, 10 + bodyH + 4)
	UI.Hint.Size = UDim2.new(1, -2 * K.WELL_PAD, 0, hintH or K.HINT_H) -- (U9-9 look) one or two lines
	UI.Hint.Visible = hintShown()
	UI.Footer.Visible = footerShown()
	-- (kit B U9-9) a card shrunk to fit a short phone (down to 0.7) keeps its small words at 14 screen px or more: the
	-- caption size grows to 14 / scale (18 -> 20 at 0.7)
	local cap = math.max(K.CAPTION_SIZE, math.ceil(14 / math.max(0.1, UI.Scale.Scale) - 1e-6))
	-- narrow cards drop the counter tag (the progress row still shows the progress): the counter and the fold share the
	-- row under the name plank (U9-9 look 2), the fold always shown
	UI.CounterPill.Visible = counterShown
	-- (U9-9 look 2) the name on its navy plank: as wide as the name at its size (measured as it shows, the Title role in
	-- capitals) and its insets, never wider than the header; the name down to the caption size before it would cut, the
	-- label TextScaled under that size (as the NPC's name), so the engine's own fit has the last word
	local nameRoom = headRoom - 2 * K.TAB_INSET
	local nameMin = math.min(K.NAME_MIN, cap)
	local nameSize = fitTextSize(UI.Name.Text, K.TAB_TEXT, nameMin, "Title", nameRoom)
	UI.Name.TextSize = nameSize
	if UI.NameFit then
		UI.NameFit.MinTextSize = nameMin
		UI.NameFit.MaxTextSize = nameSize
	end
	if UI.NameTab then
		local plankW = math.ceil(textWidth(UI.Name.Text, nameSize, "Title")) + K.OUTLINE_ROOM + 2 * K.TAB_INSET
		UI.NameTab.Size = UDim2.fromOffset(math.min(headRoom, plankW), K.TAB_H)
	end
	UI.Counter.TextSize = cap
	UI.Hint.TextSize = cap
	UI.SkipLink.TextSize = cap
	UI.ConfirmQuestion.TextSize = math.max(19, cap)
	-- (kit-b backlog items 10 / 16) one line from TITLE_SIZE down to TITLE_FLOOR, else its lines at TITLE_FLOOR
	-- (titleLines); it was cut at the 14.4 px floor on a narrow card. Its box: from the title row's top to 4 px over the
	-- well with the progress row moved up, or the row's 26 px; each line past those TITLE_LINE taller (titleExtra)
	UI.StepTitle.TextWrapped = wraps
	UI.StepTitle.TextYAlignment = wraps and Enum.TextYAlignment.Bottom or Enum.TextYAlignment.Center
	-- (2026-11-28 playtest C49: its descender touched the well's frame, 0.8 px, on phones) the moved-up box ends 4 px over
	-- the well
	UI.StepTitle.Size = UDim2.new(1, -(x0 + K.PAD), 0, (progUp and (K.HEADER_H - 4 - 46) or 26) + titleExtra)
	UI.StepTitle.TextSize = wraps and K.TITLE_FLOOR or fitTextSize(UI.StepTitle.Text, K.TITLE_SIZE, math.min(K.TITLE_FLOOR, cap), "Heading", headRoom)
	layoutProgress(progUp and (headRoom - K.FOLD_W - 6) or headRoom)
	-- narrow footers: "Skip tutorial" shortens to "Skip" and the Next button narrows, so they never overlap
	local footerW = width - 2 * K.PAD - 2 * K.WELL_PAD
	local shortSkip = footerW < K.SKIP_W + K.GAP + K.NEXT_W
	local skipW = shortSkip and K.SKIP_SHORT_W or K.SKIP_W
	UI.SkipLink.Text = shortSkip and "Skip" or "Skip tutorial"
	UI.SkipLink.Size = UDim2.fromOffset(skipW, 34)
	UI.SkipUnderline.Size = UDim2.fromOffset(math.ceil(textWidth(UI.SkipLink.Text, cap, "Label")), 2) -- (a crisp lip: 2 px)
	UI.Next.Size = UDim2.fromOffset(math.min(K.NEXT_W, footerW - skipW - K.GAP), K.BUTTON_H)
	-- and the skip confirmation: smaller buttons first, then the short question
	local confirmW = K.CONFIRM_W
	if footerW - (2 * confirmW + 12) < K.QUESTION_MIN then
		confirmW = K.CONFIRM_SHORT_W
	end
	if footerW - (2 * confirmW + 12) < K.QUESTION_SHORT_MIN then
		confirmW = K.CONFIRM_TIGHT_W
	end
	local questionW = footerW - (2 * confirmW + 12)
	UI.ConfirmYes.Size = UDim2.fromOffset(confirmW, 40)
	UI.ConfirmYes.Position = UDim2.new(1, -(confirmW + 8), 0.5, 0)
	UI.ConfirmStay.Size = UDim2.fromOffset(confirmW, 40)
	UI.ConfirmQuestion.Size = UDim2.new(0, questionW, 1, 0)
	UI.ConfirmQuestion.Text = questionW >= K.QUESTION_MIN and "Skip the tutorial?" or "Skip?"
end

local function layout()
	if not UI.Root then
		return
	end
	local area = guiArea()
	local k = Theme.ScreenFactor()
	S.compactCard = false -- measured with the objective line first (a short screen's opened card may drop it below)
	-- (kit B U9-9) the pixel arrow's cells are whole screen px. (U9-9 look 2) Its 2 px cells are the screen's icon pixel (a
	-- 2 px icon cell drawn at k lands on round(2k) whole screen px, never under 2; PixelCrisp.Px): its scale is that / 2
	-- (the arrow drew on 4 px cells, twice as coarse as the paw beside it)
	local ps = math.max(2, math.floor(2 * k + 0.5)) / 2
	if UI.PointerScale and UI.PointerScale.Scale ~= ps then
		UI.PointerScale.Scale = ps
	end
	local edge = UserInputService.TouchEnabled and K.TOUCH_EDGE or K.EDGE
	local inset = topInset()
	local screenH = area.Y + inset
	local midX0 = area.X * (0.5 - K.MIDDLE)
	local midY0 = screenH * (0.5 - K.MIDDLE) - inset
	local midY1 = screenH * (0.5 + K.MIDDLE) - inset
	local hud = hudBounds(area)
	local column = menuRect()
	-- the portrait pokes PORTRAIT_Y above the card: the card starts that much lower. (U9-9 look 2) At the screen's top
	-- edge the portrait and the name plank that ride the card's top edge may use the edge margin (down to POP_EDGE from
	-- the top): the card's body stays as high as it was before the plank (a landscape phone's opened card kept clear of
	-- the thumbstick's zone); under a top-left panel they keep the whole gap
	local cardTop0 = math.max(edge, K.POP_EDGE - K.PORTRAIT_Y * k)
	local top = cardTop0
	-- (kit-b backlog item 8) the top-left panel (a match / party panel) casts its hard shadow right and down: GAP of air
	-- past it (GAP off its box left 1.6 - 2.4 px of ink, 0 px at 932 x 430 / 960 x 540)
	local panelGap = (K.GAP + K.SHADOW) * k
	if hud.TopLeftBottom > 0 then
		top = math.max(edge, hud.TopLeftBottom + panelGap) - K.PORTRAIT_Y * k
	end
	-- the HUD's bottom-left block (vitals card / currency stack) is a hard limit for the bubble and the card
	local bottomLimit = math.min(area.Y - edge, hud.BottomLeftTop - K.GAP * k)

	-- on a Menu step the card / bubble also keeps clear of the pointer arrow's spot right of the target tile
	-- (otherwise the arrow would have to sit on Nimbus, or on a neighbouring tile of the phone grid)
	local target = nil
	local st = S.state
	if st and not st.Done and st.Target and st.Target.Kind == "Menu" and not inMatch() and M.button and M.button.Parent then
		local owner = M.button:FindFirstAncestorOfClass("ScreenGui")
		if owner and shownIn(M.button, owner) and M.button.AbsoluteSize.X > 0 then
			target = rectOf(M.button, insetShift(owner))
		end
	end

	local function leftFor(t, h)
		local l = edge
		if column and t < column.y1 + K.GAP * k and t + h > column.y0 - K.GAP * k then
			l = math.max(edge, column.x1 + K.GAP * k)
		end
		if target and t < target.y1 + K.GAP * k and t + h > target.y0 - K.GAP * k then
			l = math.max(l, target.x1 + K.POINTER_ROOM * math.max(k, ps))
		end
		return l
	end

	-- expanded card: as wide as allowed, never into the screen middle, never under the bottom-left HUD
	local width = K.PANEL_W
	local h = panelHeight(width) * k
	local left = leftFor(top, h)
	local maxW = math.floor((area.X - left - edge) / k)
	if width > maxW then
		width = maxW
		h = panelHeight(width) * k
		left = leftFor(top, h)
	end
	if left + width * k > midX0 and top + h > midY0 and top < midY1 then
		width = math.floor((midX0 - left) / k)
		h = panelHeight(math.max(width, K.PANEL_MIN_W)) * k
		left = leftFor(top, h)
	end
	local fits = width >= K.PANEL_MIN_W and top + h <= bottomLimit
	width = math.max(width, K.PANEL_MIN_W)
	S.autoCollapse = not fits

	-- A card the player opened (or the finale) that does not fit there. In the plain lobby nothing can hurt the
	-- player and the hotbar is idle, so the card the player asked for may cover the vitals card (and, as a last
	-- resort, the idle hotbar) and reach towards the middle like any window the player opens. With a party panel up
	-- (a match is about to start) the vitals card / currency pills and the hotbar are hard limits wherever the card
	-- goes (beside the panel too). It never covers Roblox's thumbstick, the touch buttons, the menu or the token pill
	-- and never leaves the screen, so its text, Next button and Skip link are always reachable. In a match: the bubble.
	local relaxed = nil
	if not fits and not inMatch() then
		local inputs = touchButtonRects()
		inputs[#inputs + 1] = thumbstickRect(area)
		local bar = hotbarRect()
		local hard = {} -- the vitals block + the hotbar while a party panel is up
		if hud.TopLeftBottom > 0 then
			for _, r in ipairs(bottomLeftRects()) do
				hard[#hard + 1] = r
			end
			hard[#hard + 1] = bar
		end
		local positions = { { Top = top, Left = nil } }
		if hud.TopLeftRight > 0 then
			-- beside the top-left panel (party panel) at the top edge
			positions[#positions + 1] = { Top = cardTop0, Left = hud.TopLeftRight + panelGap }
		end
		if hud.TopRightBottom > 0 then
			-- below the HUD's top-right block (the currency strips) when they leave the top too narrow
			positions[#positions + 1] = { Top = hud.TopRightBottom + K.GAP * k - K.PORTRAIT_Y * k, Left = nil }
		end
		-- (kit-b backlog item 6: on 360 x 640 / 384 x 640 the card could not open at any step, 375 x 667 at 18 of 21, so a
		-- tap did nothing and the tutorial could not pass step 1: beside the wallet strip and the Gift tile the top row is
		-- under PANEL_MIN_W, and under them the card has 160 - 180 px above RUN) a portrait phone's spot under the menu
		-- column, its right edge GAP of air left of the touch keys past its shadow: down to Roblox's thumbstick (it may lie
		-- over the vitals card, which steps aside - syncVitals - as for any card the player opens in the lobby)
		local reach = area.Y > area.X and columnReach() or nil
		if reach then
			local keysX = nil
			for _, r in ipairs(touchButtonRects()) do
				keysX = math.min(keysX or r.x0, r.x0)
			end
			positions[#positions + 1] = {
				Top = reach.y1 + (K.GAP + K.SHADOW) * k - K.PORTRAIT_Y * k,
				Left = nil,
				Right = keysX and (keysX - (K.GAP + K.SHADOW) * k) or nil,
			}
		end
		local function try(pos, avoidBar, compact, lastResort)
			S.compactCard = compact
			local t = pos.Top
			local l = pos.Left or leftFor(t, area.Y)
			local rightLimit = area.X - edge
			if hud.TopRightLeft > 0 and t < hud.TopRightBottom + K.GAP * k then
				rightLimit = math.min(rightLimit, hud.TopRightLeft - K.GAP * k)
			end
			if pos.Right then
				rightLimit = math.min(rightLimit, pos.Right)
			end
			local w2 = math.min(K.PANEL_W, math.floor((rightLimit - l) / k))
			-- (an in-place last resort may still be PANEL_MIN_W wide at 0.7: its search below)
			if w2 < K.PANEL_MIN_W and not (lastResort == "inPlace" and (rightLimit - l) / 0.7 >= K.PANEL_MIN_W) then
				return nil
			end
			local designH2 = panelHeight(w2)
			local h2 = designH2 * k
			if not pos.Left then
				l = leftFor(t, h2)
			end
			local x1 = l + w2 * k
			local floorY = area.Y - edge
			-- (kit-b backlog item 6) the touch keys and the thumbstick: GAP of air off the card's ink, its shadow included
			-- (box to box, the shadow lay 1 px into RUN at 375 x 667 steps 7 / 11 / 14)
			local s = K.SHADOW * k
			for _, r in pairs(inputs) do
				if l < r.x1 and x1 + s + K.GAP * k > r.x0 then
					floorY = math.min(floorY, r.y0 - K.GAP * k - s)
				end
			end
			for _, r in pairs(hard) do
				if l < r.x1 and x1 > r.x0 then
					floorY = math.min(floorY, r.y0 - K.GAP * k)
				end
			end
			if avoidBar and bar and l < bar.x1 and x1 > bar.x0 then
				floorY = math.min(floorY, bar.y0 - K.GAP * k)
			end
			if not lastResort and t + h2 <= floorY then
				return { Width = w2, Left = l, Top = t, H = h2, Scale = k, Compact = compact }
			elseif lastResort == "inPlace" then
				-- (kit-b backlog item 6) shrunk just enough (never below 0.7) to fit where it stands, or not here: a card
				-- shrunk to s may be (rightLimit - l) / s design px wide, its words on fewer lines, so a few widths are
				-- tried and the largest scale that fits both ways wins
				local best = nil
				for _, sTry in ipairs({ k, (k + 0.7) / 2, 0.7 }) do
					local w3 = math.min(K.PANEL_W, math.floor((rightLimit - l) / sTry))
					if w3 >= K.PANEL_MIN_W then
						local designH3 = panelHeight(w3)
						local fit = math.min(k, (floorY - t) / designH3, (rightLimit - l) / w3)
						if fit >= 0.7 and (best == nil or fit > best.Scale) then
							best = { Width = w3, Left = l, Top = t, H = designH3 * fit, Scale = fit, Compact = compact }
						end
					end
				end
				return best
			elseif lastResort then
				-- shrink just enough (never below 0.7: body text 14 px) to keep the card on screen
				local fit = math.max(0.7, math.min(k, (floorY - t) / designH2))
				local t2 = math.max(edge, K.POP_EDGE - K.PORTRAIT_Y * fit, math.min(t, floorY - designH2 * fit))
				return { Width = w2, Left = l, Top = t2, H = designH2 * fit, Scale = fit, Compact = compact }
			end
			return nil
		end
		for _, avoidBar in ipairs({ true, false }) do
			for _, pos in ipairs(positions) do
				for _, compact in ipairs({ false, true }) do
					relaxed = relaxed or try(pos, avoidBar, compact, nil)
				end
			end
		end
		if not relaxed and hud.TopLeftBottom <= 0 then
			-- nothing else fits in the plain lobby: the compact card, shrunk just enough (the Next button and the
			-- Skip link must stay reachable). With a party panel up (a short countdown) the bubble waits instead.
			relaxed = try(positions[1], false, true, true)
			-- (kit-b backlog item 6) where the top row is too narrow even for that (a short portrait phone), the first
			-- other spot where the compact card fits shrunk in its place
			for i = 2, #positions do
				relaxed = relaxed or try(positions[i], false, true, "inPlace")
			end
		end
		-- the variant that won decides whether the objective line is shown
		S.compactCard = relaxed ~= nil and relaxed.Compact == true
	end
	S.canOpen = fits or relaxed ~= nil
	S.forcedBubble = not S.canOpen and (S.manual == "expanded" or S.finale == true)
	local folded = collapsed()
	local cardScale = k
	if not fits and relaxed and not folded then
		width, left, top, h, cardScale = relaxed.Width, relaxed.Left, relaxed.Top, relaxed.H, relaxed.Scale
	else
		S.compactCard = false
	end
	if UI.Scale.Scale ~= cardScale then
		UI.Scale.Scale = cardScale
	end

	local designH, bodyH, hintH, titleExtra = panelHeight(width)
	-- (Pitch 2 item 03_tutorial_dock B) folded, the guide is the quest strip (K.STRIP_*): on a portrait phone on the HUD
	-- stack over the vitals card (from its left edge to the RUN / DASH column's right edge, STRIP_DOCK_GAP over it); on
	-- PC and a landscape phone top-left under the top bar (under a top-left panel, else beside it at the top edge), right
	-- of the menu column and short of the top-right stack. Too narrow, with no room, or meeting the arena's side stack: the
	-- portrait chip alone. (look:fix6b major 1) On a portrait phone the strip docks over the whole stack it spans: where
	-- RUN stands higher than the vitals card (360 x 640, 375 x 667, 384 x 640 since O3's 2947a7a moved the card left of
	-- RUN / DASH and below RUN's top) it sits STRIP_DOCK_GAP over RUN (it ran 58 x 22 px over RUN); a strip that would
	-- then meet a key, the menu column, the top-right stack or the top edge folds to the portrait chip
	local stripW, stripChip = K.STRIP_W, false
	local chipAside = false -- ((kitb-matchhud) the landscape chip's spot holds the vitals aside: below)
	if folded then
		local h2 = K.STRIP_H * k
		local chipH = K.STRIP_CHIP * k
		local v = area.Y > area.X and vitalsRect() or nil
		local reach = v and columnReach() or nil -- (look:fix6b2 N1) the menu column with its fold tab's tap pad
		local dockBlocked = false
		-- a touch key round `x0`..`x1` x `t0`..`t1` (STRIP_DOCK_GAP of air, half a px spare), nil when none
		local function keyIn(x0, x1, t0, t1)
			local d = K.STRIP_DOCK_GAP - 0.5
			for _, r in ipairs(touchButtonRects()) do
				if r.x1 > x0 - d and r.x0 < x1 + d and r.y1 > t0 - d and r.y0 < t1 + d then
					return r
				end
			end
			return nil
		end
		if v then
			local right = v.x1
			for _, r in ipairs(touchButtonRects()) do
				if r.x0 >= v.x1 - 4 and r.y0 < v.y1 and r.y1 > v.y0 - K.STRIP_DOCK_GAP - h2 then
					right = math.max(right, r.x1)
				end
			end
			left = v.x0
			stripW = math.min(K.STRIP_W, math.floor((math.min(right, area.X - edge) - left) / k))
			-- the stack's top across the strip's width: the vitals card's, or a key's beside it that stands higher
			local stackTop = v.y0
			for _, r in ipairs(touchButtonRects()) do
				if r.x1 > left and r.x0 < left + stripW * k and r.y0 < v.y1 and r.y1 > v.y0 - K.STRIP_DOCK_GAP - h2 then
					stackTop = math.min(stackTop, r.y0)
				end
			end
			top = stackTop - K.STRIP_DOCK_GAP - h2
			local x1 = left + stripW * k
			local g = K.GAP * k
			-- (look:fix6b2 N1) the column with STRIP_DOCK_GAP of air beyond the strip's own wood edge: GAP's 8 px off its box
			-- left 3.5 px of ink between the strip's edge and the tiles' shadow at 384 x 720 in a 3 player match (0.9 px at
			-- 400 x 720)
			local d = K.STRIP_DOCK_GAP + K.STRIP_EDGE * k - 0.5
			dockBlocked = top < edge or keyIn(left, x1, top, top + h2) ~= nil
				or (reach ~= nil and left < reach.x1 + d and x1 > reach.x0 - d and top < reach.y1 + d and top + h2 > reach.y0 - d)
				or (hud.TopRightLeft > 0 and x1 > hud.TopRightLeft - g and top < hud.TopRightBottom + g)
		else
			-- (kit-b backlog items 7 / 8) STRIP_DOCK_GAP of air past the top-left panel's hard shadow (GAP off its box left
			-- 0 - 2.4 px of ink: 0 at 844 x 390 on the party pad), and past the strip's own wood edge short of the top-right
			-- stack (3.6 px off the wallet strip there); a strip that would meet a touch key folds to the chip
			local dockPanel = K.STRIP_DOCK_GAP + K.SHADOW * k
			top = hud.TopLeftBottom > 0 and (hud.TopLeftBottom + dockPanel) or edge
			left = leftFor(top, h2)
			if top + h2 > bottomLimit and hud.TopLeftRight > 0 then
				top = edge
				left = math.max(hud.TopLeftRight + dockPanel, leftFor(top, h2))
			end
			local rightLimit = area.X - edge
			if hud.TopRightLeft > 0 and top < hud.TopRightBottom + K.GAP * k then
				rightLimit = math.min(rightLimit, hud.TopRightLeft - K.STRIP_DOCK_GAP - K.STRIP_EDGE * k)
			end
			stripW = math.min(K.STRIP_W, math.floor((rightLimit - left) / k))
			dockBlocked = keyIn(left, left + stripW * k, top, top + h2) ~= nil
		end
		local side = arenaSideRect()
		local x1, y1 = left + stripW * k, top + h2
		local g = K.GAP * k
		local meets = side ~= nil and left < side.x1 + g and x1 > side.x0 - g and top < side.y1 + g and y1 > side.y0 - g
		stripChip = stripW < K.STRIP_MIN_W or meets or dockBlocked or (v == nil and y1 > bottomLimit)
		if stripChip then
			-- (look:fix6b2 N1) the chip's spot keeps STRIP_DOCK_GAP of air off every HUD piece round it (the column, the keys,
			-- the vitals block, the top-left panel, each piece of the top-right stack - the wallet strips, the Gift tile, the
			-- boost chips -, the arena's side stack, the screen's edges). (kit-b backlog items 7 / 8) A landscape chip (`wide`)
			-- also keeps it off Roblox's thumbstick and the screen's left and bottom edges, and off the top-left panel as it
			-- stands, past its hard shadow (`gap`: the air, STRIP_DOCK_GAP unless given)
			local d = K.STRIP_DOCK_GAP - 0.5
			local pieces = {}
			local pg = playerGui()
			for _, spec in ipairs({ { "NimbusHud", "TopRight" }, { "NimbusDaily" }, { "NimbusBoosts" } }) do
				local g = pg and pg:FindFirstChild(spec[1])
				local holder = g and g:IsA("ScreenGui") and g.Enabled and (spec[2] and g:FindFirstChild(spec[2]) or g)
				for _, c in ipairs(holder and holder:GetChildren() or {}) do
					local s = c:IsA("GuiObject") and c.AbsoluteSize
					if s and s.X > 0 and s.X < area.X * 0.6 and s.Y < area.Y * 0.6 and shownIn(c, g) then
						pieces[#pieces + 1] = rectOf(c, insetShift(g))
					end
				end
			end
			local wide = {}
			if not v then
				local hudGui = pg and pg:FindFirstChild("NimbusHud")
				local block = hudGui and hudGui:IsA("ScreenGui") and hudGui.Enabled and hudGui:FindFirstChild("TopLeft")
				local s = K.SHADOW * k
				for _, c in ipairs(block and block:GetChildren() or {}) do
					if c:IsA("GuiObject") and c.AbsoluteSize.X > 0 and shownIn(c, hudGui) then
						local r = rectOf(c, insetShift(hudGui))
						wide[#wide + 1] = { x0 = r.x0, y0 = r.y0, x1 = r.x1 + s, y1 = r.y1 + s }
					end
				end
				wide[#wide + 1] = thumbstickRect(area)
			end
			local blocks = bottomLeftRects()
			local function clear(l, t, col, gap)
				local m = gap and (gap - 0.5) or d
				local function meets(r)
					return r ~= nil and r.x1 > l - m and r.x0 < l + chipH + m and r.y1 > t - m and r.y0 < t + chipH + m
				end
				if t < edge or l + chipH > area.X - edge or meets(col) or meets(arenaSideRect()) then
					return false
				end
				if not v and (l < edge or t + chipH > area.Y - edge) then
					return false
				end
				for _, list in ipairs({ touchButtonRects(), blocks, pieces, wide }) do
					for _, r in pairs(list) do
						if meets(r) then
							return false
						end
					end
				end
				return not v or not (hud.TopLeftBottom > 0 and t < hud.TopLeftBottom + d and (hud.TopLeftRight <= 0 or l < hud.TopLeftRight + d))
			end
			if v then
				-- on the stack still, STRIP_DOCK_GAP over the vitals card; (look:fix6b major 1) and over a key in its own
				-- column, should one stand there
				local function spot(l)
					local t = v.y0 - K.STRIP_DOCK_GAP - chipH
					local r = keyIn(l, l + chipH, t, t + chipH)
					return r and (r.y0 - K.STRIP_DOCK_GAP - chipH) or t
				end
				-- (look:fix6b2 N1) at the card's left edge, else right of the menu column and its fold tab's tap pad
				-- (columnReach), else right of its tiles (menuRect; the tap pad, over the chip, takes a tap there): the
				-- first clear spot. In a 3 or 4 player match and on a full party pad the panel pushes the column down to the
				-- card: the chip, checked against the keys only, lay under its Home tile (20 - 26.5 px). Where no spot is
				-- clear it keeps the first
				local tiles = menuRect()
				top = spot(left)
				for _, s in ipairs({ { left, reach }, { reach and reach.x1 + K.STRIP_DOCK_GAP, reach }, { tiles and tiles.x1 + K.STRIP_DOCK_GAP, tiles } }) do
					local l = s[1] and math.max(left, s[1])
					local t = l and spot(l)
					if l and clear(l, t, s[2]) then
						left, top = l, t
						break
					end
				end
			else
				if top + chipH > bottomLimit then
					top = math.max(edge, bottomLimit - chipH)
					left = leftFor(top, chipH)
				end
				-- (kit-b backlog items 7 / 8: beside a party / match panel the chip lay on the wallet strip - 640 x 360
				-- 19.6 px - and, at 568 x 320, where RUN stands at the top right beside the panel, 40 px over RUN: nothing
				-- checked it against the top-right stack or the keys) its spot, else under the top-left panel, else under the
				-- menu column, each right of Roblox's thumbstick where it meets it: the first clear spot, with STRIP_DOCK_GAP
				-- of air, else (the smallest phones: 568 x 320 has 59 px between the stick and the panel) with MIN_AIR.
				-- Where none is clear it keeps the first
				local dockPanel = K.STRIP_DOCK_GAP + K.SHADOW * k
				local col = columnReach()
				local stick = thumbstickRect(area)
				local spots = { { left, top } }
				if hud.TopLeftBottom > 0 then
					local t = hud.TopLeftBottom + dockPanel
					spots[#spots + 1] = { leftFor(t, chipH), t }
				end
				if col then
					local t = col.y1 + dockPanel
					spots[#spots + 1] = { leftFor(t, chipH), t }
				end
				local function search()
					for _, gap in ipairs({ K.STRIP_DOCK_GAP, K.MIN_AIR }) do
						for _, s in ipairs(spots) do
							local l, t = s[1], s[2]
							if stick and stick.x1 > l - gap and stick.x0 < l + chipH + gap and stick.y1 > t - gap and stick.y0 < t + chipH + gap then
								l = stick.x1 + gap
							end
							if clear(l, t, col, gap) then
								left, top = l, t
								return true
							end
						end
					end
					return false
				end
				-- (kitb-matchhud, the owner's pick A "Slim bar") at 568 x 320 in a solo / duo match the slim bar takes the row
				-- under the menu column the chip had, and no other spot is clear (the chip lay 40 px over RUN): where one is
				-- clear but for the vitals, the chip takes it and the vitals step aside while it shows there (the panel's gold
				-- 'you' chip shows the HP), as for the card the player opens (syncVitals). While it holds them aside their slot
				-- counts as if they showed, so the chip's spot never flips with them
				local slot = S.chipAside and vitalsSlot() or nil
				if slot then
					blocks[#blocks + 1] = slot
				end
				local found = search()
				if not found and (slot or vitalsRect()) then
					blocks = bottomLeftRects(true)
					found = search()
					chipAside = found
				end
			end
		end
	end
	S.stripChip = folded and stripChip
	S.chipAside = folded and stripChip and chipAside
	applyGeometry(width, designH, bodyH, hintH, titleExtra)
	if folded then
		placeStrip(stripW, stripChip)
		UI.Root.Size = stripChip and UDim2.fromOffset(K.STRIP_CHIP, K.STRIP_CHIP) or UDim2.fromOffset(stripW, K.STRIP_H)
	else
		UI.Strip.Visible = false
		UI.Portrait.Position = UDim2.fromOffset(K.PAD, K.PORTRAIT_Y)
		UI.Portrait.Size = UDim2.fromOffset(K.PORTRAIT, K.PORTRAIT)
	end
	S.portraitBase = UI.Portrait.Position
	local crisp = mod("PixelCrisp")
	if crisp then
		crisp.Refresh(UI.Root) -- (kit B U9-9) icons and edges back on whole screen px at the card's scale
	end
	UI.Main.Visible = not folded

	local goal = UDim2.fromOffset(math.floor(left + 0.5), math.floor(top + 0.5))
	if folded or not S.shown then
		syncVitals(nil, S.shown and S.chipAside)
	else
		local gx, gy = goal.X.Offset, goal.Y.Offset
		syncVitals({ x0 = gx, y0 = gy, x1 = gx + width * cardScale, y1 = gy + designH * cardScale })
	end
	if S.placed ~= goal then
		S.placed = goal
		if UI.Root.Visible and S.hasPlaced then
			tween(UI.Root, 0.25, { Position = goal })
		else
			UI.Root.Position = goal
		end
		S.hasPlaced = true
	end

	M.side = nil -- the menu pointer re-chooses its side around the new layout

	-- floating sign above the world arrow follows the readability rule too
	if W.labelGui then
		W.labelGui.Size = UDim2.fromOffset(math.floor(K.SIGN_W * k), math.floor(K.SIGN_H * k))
		if W.signScale then
			W.signScale.Scale = k
		end
	end
end

----------------------------------------------------------------------
-- Panel: building
----------------------------------------------------------------------
local function buildPortrait(parent)
	-- (kit B U9-9) a square sky well in a wood frame (the NPC dialog's portrait): a little pixel cloud in its corner,
	-- Nimbus in front of it, the ground lip over Nimbus' feet
	local holder = box("Portrait", {
		Size = UDim2.fromOffset(K.PORTRAIT, K.PORTRAIT),
		Position = UDim2.fromOffset(K.PAD, K.PORTRAIT_Y),
		ZIndex = 2,
	}, parent)
	local f = K.PORTRAIT_FRAME
	local frame = box("Frame", { BackgroundTransparency = 0, BackgroundColor3 = SIGN.Wood, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, holder)
	frame:SetAttribute("SignKit", "Frame")
	local sky = box("Sky", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Sky,
		Position = UDim2.fromOffset(f, f),
		Size = UDim2.new(1, -2 * f, 1, -2 * f),
		ZIndex = 2,
	}, frame)
	-- (U9-9 look 2) the portrait, its frame and the sky in it on whole px on all four sides (crispBox): the wood frame a
	-- whole px wide on every side at any card scale (2.4 px drew soft)
	crispBox(holder)
	crispBox(frame)
	crispBox(sky)
	crispIcon(sky, "cloud", 18, SIGN.Stone, {
		Name = "Cloud",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(5, 4),
		ZIndex = 2,
	})
	local view = make("ViewportFrame", "Nimbus", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(f, f),
		Size = UDim2.new(1, -2 * f, 1, -2 * f),
		Ambient = rgb(186, 192, 218),
		LightColor = rgb(255, 246, 232),
		LightDirection = Vector3.new(-0.4, -0.8, 1),
		ZIndex = 2,
	}, holder)
	crispBox(box("Ground", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.SkyLip,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, f, 1, -f),
		Size = UDim2.new(1, -2 * f, 0, K.PORTRAIT_LIP),
		ZIndex = 2,
	}, holder))
	local toggle = make("TextButton", "Toggle", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, holder)
	-- (Pitch 2 item 03_tutorial_dock B: the folded guide is the quest strip, buildStrip; the "!" badge and the "Tap me!"
	-- tag of the lone bubble are gone)
	UI.Portrait, UI.View, UI.Toggle = holder, view, toggle
end

-- (Pitch 2 item 03_tutorial_dock B) the folded guide: the quest strip (K.STRIP_*), a stone strip in its wood edge and lip
-- holding the step's title, "3/21", the steps row (layoutStripSteps) and the "+" block; Nimbus' portrait sits on its left
-- end as the chip (layout moves it there while the card is folded)
local function buildStrip(parent)
	local strip = box("QuestStrip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Stone,
		Size = UDim2.fromOffset(K.STRIP_W, K.STRIP_H),
		Visible = false,
		Active = true, -- (a tap on the strip never falls through to the world)
		ZIndex = 1,
	}, parent)
	edge(strip, SIGN.Wood, K.STRIP_EDGE)
	lipOf(strip, SIGN.StoneLip, K.STRIP_LIP)
	crispBox(strip)
	UI.Strip = strip
	UI.StripTitle = label(strip, "QuestTitle", "", "Heading", K.STRIP_TITLE, SIGN.Text, {
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		ZIndex = 2,
	})
	UI.StripCount = label(strip, "QuestCount", "", "Heading", K.STRIP_COUNT, SIGN.Text, {
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		ZIndex = 2,
	})
	-- the steps: a holder undoing the strip's scale (Unscale), so its chapter blocks and cells are whole screen px
	UI.StripSteps = box("QuestSteps", { Size = UDim2.fromOffset(200, K.STRIP_CELL_H), ZIndex = 2 }, strip)
	make("UIScale", "Unscale", { Scale = 1 }, UI.StripSteps)
	crispBox(UI.StripSteps)
	-- the "+" block: a stone tag in its wood edge with the pixel plus; it opens the card
	local open = make("TextButton", "QuestOpen", {
		BackgroundColor3 = SIGN.Tile,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(K.STRIP_OPEN, K.STRIP_OPEN),
		ZIndex = 2,
	}, strip)
	edge(open, SIGN.Wood, K.EDGE_PX)
	lipOf(open, SIGN.StoneLip, K.TAG_LIP)
	crispIcon(open, "plus", K.STRIP_PLUS, SIGN.Text, { Name = "Plus", Position = UDim2.new(0.5, 0, 0.5, -1), ZIndex = 2 })
	crispBox(open)
	UI.StripOpen = open
end

local function buildPixelArrow(parent)
	-- a chunky left-pointing pixel arrow: (kit B U9-9) a brown outline, the gold's three bands and a stone glint. (U9-9 look
	-- 2) Drawn on the icons' 2 px cell (34 x 22 cells, the same 68 x 44 silhouette): one pixel size on the screen, its
	-- head's steps as fine as the paw's beside it (on 4 px cells they were twice as coarse)
	local cols, rows, cell = 34, 22, 2
	local function inside(r, c)
		if r < 0 or r >= rows or c < 0 or c >= cols then
			return false
		end
		local head = c <= 15 and c >= math.abs(r - 10.5) - 0.5
		local shaft = r >= 6 and r <= 15 and c >= 12
		return head or shaft
	end
	local glint = { ["8_7"] = true, ["9_6"] = true } -- two stone cells along the head's upper edge
	local palette = { o = SIGN.Text, L = SIGN.GoldLight, G = SIGN.Gold, D = SIGN.GoldLip, W = SIGN.Stone }
	for r = 0, rows - 1 do
		local runKey, runStart = nil, 0
		for c = 0, cols do
			local key = nil
			if c < cols and inside(r, c) then
				local edgeCell = not (inside(r - 1, c) and inside(r + 1, c) and inside(r, c - 1) and inside(r, c + 1))
				if edgeCell then
					key = "o"
				elseif glint[r .. "_" .. c] then
					key = "W"
				elseif r <= 9 then
					key = "L"
				elseif r <= 11 then
					key = "G"
				else
					key = "D"
				end
			end
			if key ~= runKey then
				if runKey then
					box("Px" .. r .. "_" .. runStart, {
						BackgroundTransparency = 0,
						BackgroundColor3 = palette[runKey],
						Position = UDim2.fromOffset(runStart * cell, r * cell),
						Size = UDim2.fromOffset((c - runStart) * cell, cell),
					}, parent)
				end
				runKey, runStart = key, c
			end
		end
	end
	parent.Size = UDim2.fromOffset(cols * cell, rows * cell)
end

local function buildPointer()
	local pg = playerGui()
	local gui = make("ScreenGui", "NimbusTutorialPointer", {
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = K.POINTER_ORDER,
	}, nil)
	-- (U9-9 look 2) no ring: the pointed tile wears the kit's Selected look itself (MenuController.SetPointed: the gold face
	-- and its lip, the pitch's .sb.on), as the rail's tiles lie edge to edge and a ring round one covered the next ("ndex");
	-- the pixel arrow points at it
	local arrow = box("Arrow", { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, Active = false }, gui)
	buildPixelArrow(arrow)
	UI.PointerScale = make("UIScale", "ReadScale", { Scale = 1 }, arrow)
	UI.PointerGui, UI.Arrow = gui, arrow
	gui.Parent = pg
end

local function onNextPressed()
	if S.typing then
		S.typeShown = S.typeTotal -- first press reveals the whole line
		return
	end
	if os.clock() < (S.nextLockUntil or 0) then
		return
	end
	if fireEvent("Next") then
		S.nextLockUntil = os.clock() + K.NEXT_LOCK
		setDisabled(UI.Next, true)
	end
end

local function setConfirming(on)
	S.confirming = on and true or false
	UI.Confirm.Visible = S.confirming
	UI.SkipLink.Visible = not S.confirming
	UI.Next.Visible = not S.confirming and nextShown(S.state)
end

local function buildPanel()
	local pg = playerGui()
	local gui = make("ScreenGui", "NimbusTutorial", {
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = K.PANEL_ORDER,
	}, nil)
	UI.Gui = gui
	local root = box("TutorialPanel", { Size = UDim2.fromOffset(K.PANEL_W, 260), Visible = false }, gui)
	UI.Root = root
	UI.Scale = make("UIScale", "ReadScale", { Scale = 1 }, root)
	local slide = box("Slide", { Size = UDim2.fromScale(1, 1) }, root)
	UI.Slide = slide
	local crisp = mod("PixelCrisp")
	if crisp then
		crisp.Root(slide) -- (U9-9 look) it slides in; the card's blocks sit on whole px of it at rest
	end

	local main = box("Main", { Size = UDim2.fromScale(1, 1), ZIndex = 1 }, slide)
	UI.Main = main
	-- (kit B U9-9) the card: the wood frame round the stone body, its lip along the bottom (the NPC dialog's card)
	local card = box("Card", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Wood,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Active = true, -- clicks on the card never fall through to the world
	}, main)
	card:SetAttribute("SignKit", "Frame")
	local stone = box("Stone", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Stone,
		Position = UDim2.fromOffset(K.FRAME, K.FRAME),
		Size = UDim2.new(1, -2 * K.FRAME, 1, -2 * K.FRAME),
		ZIndex = 3,
	}, card)
	stone:SetAttribute("SignKit", "Body")
	lipOf(stone, SIGN.StoneLip, K.CARD_LIP)
	-- (U9-9 look 2) the card and the stone in it on whole px on all four sides: the wood frame a whole px wide everywhere
	crispBox(card)
	crispBox(stone)
	-- (Pitch 2 F0, finish pass A) the frame's light, the card's shadow, the stone sunk under the frame with its carved rim
	local SK = mod("SignKit")
	if SK and SK.FinishFrame then
		SK.FinishFrame(card, { Body = stone })
	end

	-- header: the name plank, step title, block row, counter tag, fold block (kit B U9-9: brown on the stone body)
	local header = box("Header", { Size = UDim2.new(1, 0, 0, K.HEADER_H), ZIndex = 5 }, main)
	local x0 = K.PAD + K.PORTRAIT + 12
	-- (U9-9 look 2) the speaker's name on the NPC dialog's plank (one header language for the two speaker cards): a navy
	-- plank in a gold-lip edge with its navy lip and two brass rivets, riding the card's top edge from the header's x0, the
	-- name a plain Section title in gold (it was brown words on the stone, the plain one of the family)
	local nameTab = box("NameTab", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Navy,
		Position = UDim2.fromOffset(x0, K.TAB_Y),
		Size = UDim2.fromOffset(160, K.TAB_H),
		ZIndex = 6,
	}, main)
	edge(nameTab, SIGN.GoldLip, 3)
	lipOf(nameTab, SIGN.NavyLip, K.NAME_LIP)
	local crispMod = mod("PixelCrisp")
	for _, side in ipairs({ { "RivetL", 0, 6 }, { "RivetR", 1, -10 } }) do
		local rivet = box(side[1], {
			BackgroundTransparency = 0,
			BackgroundColor3 = SIGN.Brass,
			Position = UDim2.new(side[2], side[3], 0.5, -4),
			Size = UDim2.fromOffset(4, 4),
			ZIndex = 7,
		}, nameTab)
		if crispMod then
			crispMod.Adopt(rivet, 4) -- a whole-px square on a whole px
		end
	end
	UI.NameTab = crispBox(nameTab)
	UI.Name = label(nameTab, "GuideName", "Nimbus", "Title", K.TAB_TEXT, SIGN.Gold, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -2),
		Size = UDim2.new(1, -2 * (K.TAB_INSET - K.NAME_SLACK), 1, -(6 + K.NAME_LIP)),
		TextXAlignment = Enum.TextXAlignment.Center,
		-- (2026-11-28 playtest C42 review: the offline fit cannot see the engine's own measure, which drew the name about
		-- 3 px wider than its box) never cut: the plank is sized to the name, so a name the engine draws a little wider
		-- stays on the plank's insets instead of reading "NIMB..."
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 7,
	})
	UI.Name.TextScaled = true -- (U9-9 look) under UI.NameFit (applyGeometry): never cut to "NIMB..."
	UI.NameFit = make("UITextSizeConstraint", "Fit", { MinTextSize = K.NAME_MIN, MaxTextSize = K.TAB_TEXT }, UI.Name)
	Theme.StyleTitle(UI.Name, "Section")
	UI.StepTitle = label(header, "StepTitle", "", "Heading", K.TITLE_SIZE, SIGN.Text, {
		Position = UDim2.fromOffset(x0, 46),
		Size = UDim2.new(1, -(x0 + K.PAD), 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- (U9-9 look) the step progress: one SignKit block row in whole screen px (layoutProgress), its holder undoing the
	-- card's scale (Unscale) and its top-left on a whole px
	UI.Progress = box("Progress", { Position = UDim2.fromOffset(x0, 76), Size = UDim2.fromOffset(200, K.PROG_H) }, header)
	make("UIScale", "Unscale", { Scale = 1 }, UI.Progress)
	if crisp then
		crisp.Box(UI.Progress)
	end
	-- the counter: a stone tag in its wood edge, brown words; (U9-9 look 2) under the name plank's row, left of the fold
	local pill = box("Counter", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Tile,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(K.PAD + K.FOLD_W + 6), 0, K.TAG_Y),
		Size = UDim2.fromOffset(K.COUNTER_W, K.TAG_H),
	}, header)
	edge(pill, SIGN.Wood, K.EDGE_PX)
	lipOf(pill, SIGN.StoneLip, K.TAG_LIP)
	UI.Counter = label(pill, "Text", "Step 1/1", "Heading", K.CAPTION_SIZE, SIGN.Text, { Size = UDim2.new(1, 0, 1, -K.TAG_LIP) })
	UI.CounterPill = pill
	-- the fold: a stone block with the pixel minus
	local fold = make("TextButton", "Fold", {
		BackgroundColor3 = SIGN.Tile,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -K.PAD, 0, K.TAG_Y),
		Size = UDim2.fromOffset(K.FOLD_W, K.TAG_H),
	}, header)
	edge(fold, SIGN.Wood, K.EDGE_PX)
	lipOf(fold, SIGN.StoneLip, K.TAG_LIP)
	crispIcon(fold, "minus", 18, SIGN.Text, { Name = "Bar", Position = UDim2.new(0.5, 0, 0.5, -1) })
	UI.Fold = fold

	-- text well: a pale tile in a wood edge
	local well = box("Well", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Tile,
		Position = UDim2.fromOffset(K.PAD, K.HEADER_H),
		Size = UDim2.new(1, -2 * K.PAD, 1, -(K.HEADER_H + K.FOOT_PAD)),
		ZIndex = 6,
	}, main)
	edge(well, SIGN.Wood, K.EDGE_PX)
	UI.Well = well
	UI.Body = label(well, "Body", "", "Body", K.BODY_SIZE, SIGN.Text, {
		Position = UDim2.fromOffset(K.WELL_PAD, 10),
		Size = UDim2.new(1, -2 * K.WELL_PAD, 0, 60),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	UI.TypeSkip = make("TextButton", "TypeSkip", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UI.Body.Position,
		Size = UI.Body.Size,
	}, well)
	UI.Hint = label(well, "Hint", "", "Label", K.CAPTION_SIZE, SIGN.Navy, { -- (kit B U9-9) the objective in navy ink
		Position = UDim2.fromOffset(K.WELL_PAD, 70),
		Size = UDim2.new(1, -2 * K.WELL_PAD, 0, K.HINT_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true, -- (U9-9 look) a second line (hintHeight), never cut
	})

	local footer = box("Footer", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, K.WELL_PAD, 1, -6),
		Size = UDim2.new(1, -2 * K.WELL_PAD, 0, K.FOOTER_H),
		ZIndex = 2,
	}, well)
	UI.Footer = footer
	local skip = make("TextButton", "SkipLink", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(132, 34),
		Text = "Skip tutorial",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, footer)
	Theme.Style(skip, "Label", { Size = K.CAPTION_SIZE, Color = SIGN.TextMuted })
	-- (U9-9 look 2) a 2 px line on whole px at any card scale (it drew 1.6 px): a crisp lip on a crisp origin
	UI.SkipUnderline = box("Underline", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.TextMuted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -3),
		Size = UDim2.new(0, 104, 0, 2),
	}, skip)
	if crispMod then
		UI.SkipUnderline:SetAttribute("CrispLipWhole", true) -- (its width a whole px as well)
		crispMod.Lip(UI.SkipUnderline, 2)
		crispMod.Box(UI.SkipUnderline)
	end
	UI.SkipLink = skip
	UI.Next = button({
		Name = "Next",
		Text = "Next",
		Style = "Green",
		TextSize = K.BUTTON_SIZE,
		Size = UDim2.fromOffset(K.NEXT_W, K.BUTTON_H),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Callback = onNextPressed,
		Parent = footer,
	})

	local confirm = box("Confirm", { Size = UDim2.fromScale(1, 1), Visible = false }, footer)
	UI.Confirm = confirm
	UI.ConfirmQuestion = label(confirm, "Question", "Skip the tutorial?", "Body", 19, SIGN.Text, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, -196, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	UI.ConfirmYes = button({
		Name = "ConfirmSkip",
		Text = "Skip",
		Style = "Red",
		TextSize = 20,
		Size = UDim2.fromOffset(92, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -100, 0.5, 0),
		Callback = function()
			if fireEvent("Skip") then
				S.skipLockUntil = os.clock() + K.SKIP_LOCK
				setDisabled(UI.ConfirmYes, true)
			end
		end,
		Parent = confirm,
	})
	UI.ConfirmStay = button({
		Name = "ConfirmStay",
		Text = "Stay",
		Style = "Blue",
		TextSize = 20,
		Size = UDim2.fromOffset(92, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Callback = function()
			setConfirming(false)
		end,
		Parent = confirm,
	})

	-- (U9-9 look) the tags, the well and the planks on whole screen px of the card at any scale: their top-left (Box), and
	-- a CloudUI plank's wood edge and lip (2.1 / 2.4 px drew uneven)
	if crisp then
		for _, block in ipairs({ UI.CounterPill, UI.Fold, UI.Well, UI.Next, UI.ConfirmYes, UI.ConfirmStay }) do
			if block ~= UI.CounterPill and block ~= UI.Fold and block ~= UI.Well then
				for _, c in ipairs(block:GetChildren()) do
					if c:IsA("UIStroke") and c:GetAttribute("CrispEdge") == nil then
						crisp.Edge(c, c.Thickness)
					elseif c.Name == "Lip" and c:IsA("GuiObject") and c:GetAttribute("CrispLip") == nil then
						crisp.Lip(c, c.Size.Y.Offset)
					end
				end
			end
			crisp.Box(block)
		end
	end

	buildPortrait(slide)
	buildStrip(slide)

	-- confetti layer (gui pixels, no UIScale)
	UI.Fx = box("Confetti", { Size = UDim2.fromScale(1, 1), ZIndex = 50, Active = false }, gui)

	-- input
	skip.Activated:Connect(function()
		setConfirming(true)
	end)
	UI.TypeSkip.Activated:Connect(function()
		if S.typing then
			S.typeShown = S.typeTotal
		end
	end)
	UI.Toggle.Activated:Connect(function()
		if collapsed() then
			if S.canOpen == false or S.windowOpen then
				return -- the card has no room right now (a match on a short screen) or a window covers it
			end
			S.manual = "expanded"
		else
			S.manual = "collapsed"
		end
		safe("layout", layout)
	end)
	fold.Activated:Connect(function()
		S.manual = "collapsed"
		safe("layout", layout)
	end)
	-- (Pitch 2 03 B) the quest strip's "+" opens the card, as a tap on the portrait chip does
	UI.StripOpen.Activated:Connect(function()
		if not collapsed() or S.canOpen == false or S.windowOpen then
			return
		end
		S.manual = "expanded"
		safe("layout", layout)
	end)

	gui.Parent = pg
end

----------------------------------------------------------------------
-- Portrait: PetBuilder Cloudy Dragon in the viewport
----------------------------------------------------------------------
local function setupPortraitModel()
	local view = UI.View
	if not view or P.model then
		return
	end
	local Steps = mod("TutorialSteps")
	local guide = Steps and type(Steps.Guide) == "table" and Steps.Guide or {}
	local petId = type(guide.PetId) == "string" and guide.PetId or "cloudy_dragon"
	local PetBuilder = mod("PetBuilder")
	local PetCatalog = mod("PetCatalog")
	local def = nil
	if PetCatalog and type(PetCatalog.Get) == "function" then
		local okDef, found = pcall(PetCatalog.Get, petId)
		if okDef and type(found) == "table" then
			def = found
		end
	end
	local model = nil
	if def and PetBuilder and type(PetBuilder.Build) == "function" then
		local okBuild, built = pcall(PetBuilder.Build, def, { Detail = "High", Scale = 1 })
		if okBuild and typeof(built) == "Instance" then
			model = built
		else
			warnOnce("portrait", "PetBuilder.Build failed: " .. tostring(built))
		end
	end
	if not model then
		-- no pet art available: a friendly cloud glyph instead of an empty bubble
		-- (kit-b U7a) the pitch's pixel cloud; (kit B U9-9) on whole screen px, stone on the sky
		crispIcon(view.Parent, "cloud", 45, SIGN.Stone, { Name = "Fallback", ZIndex = 2 })
		return
	end
	model.Parent = view
	pcall(function()
		model:PivotTo(CFrame.new())
	end)
	P.builder = PetBuilder
	if type(PetBuilder.Animate) == "function" then
		pcall(PetBuilder.Animate, model, 0.3, { Flap = 0.8 })
	end
	local center, height = Vector3.new(0, 1.2, 0), 2.6
	local okBox, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if okBox and cf and size then
		center, height = cf.Position, math.max(0.5, size.Y)
	end
	-- pets face -Z; if this model's eyes sit on +Z, film that side instead
	local sum, count = 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "eye", 1, true) then
			sum = sum + (d.Position.Z - center.Z)
			count = count + 1
		end
	end
	if count > 0 and sum / count > 0.05 then
		P.side = 1
		view.LightDirection = Vector3.new(-0.4, -0.8, -1)
	end
	P.model = model
	P.height = height
	P.focus = center + Vector3.new(0, height * 0.1, 0)
	P.dist = (height * 0.62) / math.tan(math.rad(15)) -- the whole head, horns included, and a hint of wings
	P.camera = make("Camera", "PortraitCamera", { FieldOfView = 30 }, view)
	view.CurrentCamera = P.camera
end

local function updatePortrait(dt, t)
	if not P.model or not P.camera then
		return
	end
	P.accum = P.accum + dt
	if P.accum < (collapsed() and K.PORTRAIT_FOLDED_STEP or K.PORTRAIT_STEP) then
		return
	end
	P.accum = 0
	local excited = 0
	if t < P.excitedUntil then
		excited = 1
	elseif S.typing then
		excited = 0.35
	end
	local a = P.yaw + math.sin(t * 0.55) * 0.12
	local bob = math.sin(t * 1.7) * P.height * 0.03
	local focus = P.focus + Vector3.new(0, bob, 0)
	local offset = Vector3.new(math.sin(a) * P.dist, P.dist * 0.1, math.cos(a) * P.dist * P.side)
	P.camera.CFrame = CFrame.lookAt(focus + offset, focus)
	if P.builder and type(P.builder.Animate) == "function" then
		local ok = pcall(P.builder.Animate, P.model, t, { Flap = 0.7 + excited * 1.1, Excited = excited })
		if not ok then
			P.builder = nil
		end
	end
end

----------------------------------------------------------------------
-- Confetti (voxel squares), pooled
----------------------------------------------------------------------
local function burst(big)
	if not UI.Fx or not UI.Portrait then
		return
	end
	local k = Theme.ScreenFactor()
	local origin = UI.Portrait.AbsolutePosition + UI.Portrait.AbsoluteSize * 0.5 - UI.Fx.AbsolutePosition
	local count = big and K.CONFETTI_BIG or K.CONFETTI_SMALL
	for i = 1, count do
		local piece = nil
		for _, p in ipairs(Fx.pool) do
			if not p.alive then
				piece = p
				break
			end
		end
		if not piece then
			if #Fx.pool >= K.CONFETTI_BIG * 2 then
				break
			end
			local frameObj = box("Bit", { BackgroundTransparency = 0, Visible = false }, UI.Fx)
			piece = { frame = frameObj, alive = false }
			table.insert(Fx.pool, piece)
		end
		local angle = -0.25 - math.random() * 2.2 -- up and to the right, away from the screen edge
		local speed = (big and 300 or 230) + math.random() * (big and 340 or 220)
		local px = math.floor((5 + math.random() * 6) * k + 0.5)
		piece.alive = true
		piece.x, piece.y = origin.X, origin.Y
		piece.vx = math.cos(angle) * speed * k + 40 * k
		piece.vy = math.sin(angle) * speed * k
		piece.rot = math.random() * 90
		piece.vr = (math.random() - 0.5) * 720
		piece.age = 0
		piece.life = 1.1 + math.random() * (big and 0.9 or 0.5)
		piece.px = px
		local f = piece.frame
		f.BackgroundColor3 = C.Confetti[(i % #C.Confetti) + 1]
		f.Size = UDim2.fromOffset(px, px)
		f.BackgroundTransparency = 0
		f.Rotation = 0
		f.Position = UDim2.fromOffset(math.floor(piece.x - px / 2 + 0.5), math.floor(piece.y - px / 2 + 0.5))
		f.Visible = true
	end
	Fx.live = 0
	for _, p in ipairs(Fx.pool) do
		if p.alive then
			Fx.live = Fx.live + 1
		end
	end
end

local function updateConfetti(dt)
	if Fx.live <= 0 then
		return
	end
	local k = Theme.ScreenFactor()
	local live = 0
	for _, p in ipairs(Fx.pool) do
		if p.alive then
			p.age = p.age + dt
			if p.age >= p.life then
				p.alive = false
				p.frame.Visible = false
			else
				p.vy = p.vy + K.GRAVITY * k * dt
				p.vx = p.vx * (1 - math.min(0.9, 1.4 * dt))
				p.x = p.x + p.vx * dt
				p.y = p.y + p.vy * dt
				p.rot = p.rot + p.vr * dt
				-- (kit B U9-9) a flat bit that flips (its width follows the turn) on whole screen px, never a rotated square
				local f = p.frame
				local w = math.max(1, math.floor(p.px * math.abs(math.cos(math.rad(p.rot))) + 0.5))
				f.Size = UDim2.fromOffset(w, p.px)
				f.Position = UDim2.fromOffset(math.floor(p.x - w / 2 + 0.5), math.floor(p.y - p.px / 2 + 0.5))
				local fade = (p.age - p.life * 0.65) / (p.life * 0.35)
				if fade > 0 then
					f.BackgroundTransparency = math.min(1, fade)
				end
				live = live + 1
			end
		end
	end
	Fx.live = live
end

-- (audio wave 2) client/SoundFx, lazy; false = unavailable
local soundFxMod = nil
local function playSfx(name)
	if soundFxMod == nil then
		local module = Client:FindFirstChild("SoundFx")
		local ok, mod = false, nil
		if module then
			ok, mod = pcall(require, module)
		end
		soundFxMod = (ok and type(mod) == "table" and type(mod.Play) == "function") and mod or false
	end
	if soundFxMod then
		pcall(soundFxMod.Play, name)
	end
end

local function celebrate(big)
	P.excitedUntil = S.clock + (big and 2.6 or 1.4)
	-- a finished step: TutorialStep; the finale: Reward (its own TutorialChapter take was skipped this wave)
	playSfx(big and "Reward" or "TutorialStep")
	if S.shown then
		safe("burst", burst, big)
	end
	if UI.Portrait then
		-- a happy hop of the portrait (from where layout put it: over the card, or on the quest strip's end)
		local base = S.portraitBase or UDim2.fromOffset(K.PAD, K.PORTRAIT_Y)
		UI.Portrait.Position = base
		local up = tween(UI.Portrait, 0.14, { Position = base + UDim2.fromOffset(0, -10) })
		up.Completed:Connect(function()
			tween(UI.Portrait, 0.32, { Position = base }, Enum.EasingStyle.Bounce)
		end)
	end
end

----------------------------------------------------------------------
-- Panel: content + visibility
----------------------------------------------------------------------
local function setVisibleGraphemes(n)
	if S.noGraphemes then
		if n < 0 then
			UI.Body.Text = S.fullText or ""
		else
			UI.Body.Text = string.sub(S.fullText or "", 1, n)
		end
		return
	end
	local ok = pcall(function()
		UI.Body.MaxVisibleGraphemes = n
	end)
	if not ok then
		S.noGraphemes = true
		setVisibleGraphemes(n)
	end
end

local function startTyping(text)
	S.fullText = text
	UI.Body.Text = text
	S.typeTotal = graphemeCount(text)
	S.typeShown = 0
	S.typeDelay = K.TYPE_DELAY
	S.typing = true
	setVisibleGraphemes(0)
end

local function updateTypewriter(dt)
	if not S.typing then
		return
	end
	if S.typeDelay > 0 then
		S.typeDelay = S.typeDelay - dt
		return
	end
	S.typeShown = S.typeShown + dt * K.TYPE_CPS
	if S.typeShown >= S.typeTotal then
		S.typing = false
		setVisibleGraphemes(-1)
	else
		setVisibleGraphemes(math.floor(S.typeShown))
	end
end

local function hintText()
	local st = S.state
	if not st then
		return ""
	end
	local text = st.Hint or DEFAULT_HINTS[st.CompleteOn] or ""
	if W.active and W.distance then
		if W.distance <= K.TRAIL_HIDE then
			text = text .. "  \194\183  you're here!"
		else
			text = text .. "  \194\183  " .. math.floor(W.distance + 0.5) .. " studs"
		end
	end
	return BULLET .. text
end

-- Fills the panel with the current step (called when the step changes).
local function renderStep()
	local st = S.state
	if not st or not UI.Root then
		return
	end
	UI.StepTitle.Text = st.Title ~= "" and st.Title or "Nimbus says"
	UI.Counter.Text = "Step " .. st.Step .. "/" .. st.Total
	UI.StripTitle.Text = UI.StepTitle.Text -- (Pitch 2 03 B) the folded quest strip's title and count
	UI.StripCount.Text = st.Step .. "/" .. st.Total
	S.progTotal = st.Total -- (layout builds the row for it)
	paintProgress(st.Step, false)
	UI.Hint.Text = hintText()
	local isNext = nextShown(st)
	UI.Next.Text = st.Button or "Next"
	setStyle(UI.Next, st.Step >= st.Total and "Gold" or "Green")
	setDisabled(UI.Next, false)
	setDisabled(UI.ConfirmYes, false)
	S.nextLockUntil = 0
	setConfirming(false)
	UI.Next.Visible = isNext
	S.heightKey = nil
	startTyping(st.Text)
	safe("layout", layout)
end

local function renderFinale(reward)
	S.finale = true
	S.typing = false
	UI.StepTitle.Text = "All done!"
	UI.Counter.Text = "Complete!"
	UI.StripTitle.Text = "All done!"
	UI.StripCount.Text = "Done!"
	paintProgress(0, true)
	local text = "You know the basics now. Happy climbing, see you in the clouds!"
	if type(reward) == "number" and reward > 0 then
		text = "+" .. reward .. " Cloud Tokens are yours! You know the basics now. Happy climbing!"
	end
	S.heightKey = nil
	startTyping(text)
	S.typeShown = 0
	safe("layout", layout)
end

local function panelWanted()
	if S.finale then
		return S.clock < (S.finaleUntil or 0)
	end
	local st = S.state
	if not st or st.Done then
		return false
	end
	if S.clock < (S.showAfter or 0) then
		return false
	end
	if inMatch() and st.CompleteOn ~= "MatchEnded" then
		return false
	end
	-- a battle on a phone: the battle HUD's top card and team cards hold the top / left of the screen and the rest is
	-- the fight (the HUD cues ATTACK / RETREAT / SPECIAL itself); Nimbus comes back when the battle ends
	if UI.Gui and battleTeamRect(guiArea()) then
		return false
	end
	return true
end

local function setPanelShown(on)
	if not UI.Root then
		return
	end
	if on == S.shown then
		return
	end
	S.shown = on
	local k = math.max(0.1, UI.Scale.Scale)
	local hiddenX = -math.floor((UI.Root.AbsolutePosition.X / k) + UI.Root.Size.X.Offset + 40)
	if on then
		S.coverRead = 0 -- (C17 review) a window it comes back under is read at once (Step)
		safe("layout", layout)
		UI.Root.Visible = true
		UI.Slide.Position = UDim2.fromOffset(hiddenX, 0)
		tween(UI.Slide, 0.45, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
		if S.typing then
			S.typeDelay = math.max(S.typeDelay or 0, 0.35) -- let the card arrive before talking
		end
	else
		syncVitals(nil)
		local out = tween(UI.Slide, 0.3, { Position = UDim2.fromOffset(hiddenX, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		out.Completed:Connect(function()
			if not S.shown and UI.Root then
				UI.Root.Visible = false
				-- (C17 review) a guide that slid out unseen under a window is whole again for its next show
				UI.Slide.Visible = true
			end
		end)
	end
end

----------------------------------------------------------------------
-- Menu pointer: pulsing ring + pixel arrow at MenuButton_<Id>
----------------------------------------------------------------------
local function findMenuButton(id)
	local pg = playerGui()
	if not pg or type(id) ~= "string" then
		return nil
	end
	local names = { "MenuButton_" .. id, "Menu_" .. id }
	if id == "Home" then
		-- the Home tile keeps its v3 id "Spot" (MenuController): Phase 4's "Portal Home" step rings it as "Home"
		table.insert(names, 1, "MenuButton_Spot")
	end
	for _, name in ipairs(names) do
		for _, d in ipairs(pg:GetDescendants()) do
			if d.Name == name and d:IsA("GuiObject") and d.AbsoluteSize.X > 0 then
				local owner = d:FindFirstAncestorOfClass("ScreenGui")
				if owner and owner ~= UI.Gui and owner ~= UI.PointerGui and shownIn(d, owner) then
					return d
				end
			end
		end
	end
	return nil
end

local function isButton(obj)
	return obj:IsA("TextButton") or obj:IsA("ImageButton")
end

-- The button itself, or the first button inside a tile frame.
local function clickable(obj)
	if isButton(obj) then
		return obj
	end
	for _, d in ipairs(obj:GetDescendants()) do
		if isButton(d) then
			return d
		end
	end
	return nil
end

-- Hooks clicks on the menu button that leads to what the current step waits for.
local function refreshClickHook()
	local st = S.state
	local id = st and not st.Done and HOOK_FOR[st.CompleteOn] or nil
	if id ~= M.hookId or (M.hookConn and not (M.hookButton and M.hookButton.Parent)) then
		if M.hookConn then
			M.hookConn:Disconnect()
			M.hookConn = nil
		end
		M.hookId = id
		M.hookButton = nil
	end
	if id and not M.hookConn then
		local found = findMenuButton(id)
		local target = found and clickable(found)
		if target then
			M.hookButton = target
			M.hookConn = target.Activated:Connect(function()
				task.delay(0.35, onWindowOpened, id)
			end)
		end
	end
end

-- (U9-9 look 2) the menu tile the pointer marks (MenuController.SetPointed: the kit's Selected gold face); nil = none
local function setPointed(id)
	if M.pointed == id then
		return
	end
	local menu = mod("MenuController")
	if menu and type(menu.SetPointed) == "function" then
		if M.pointed then
			pcall(menu.SetPointed, M.pointed, false)
		end
		if id then
			pcall(menu.SetPointed, id, true)
		end
	end
	M.pointed = id
end

local function hidePointer()
	setPointed(nil)
	if UI.Arrow and UI.Arrow.Visible then
		UI.Arrow.Visible = false
	end
end

-- Shown MenuButton_* tiles (other than `except`) in our gui coordinates.
local function menuButtonRects(except)
	local out = {}
	local pg = playerGui()
	local menuGui = pg and pg:FindFirstChild("NimbusMenu")
	if not (menuGui and menuGui:IsA("ScreenGui") and menuGui.Enabled) then
		return out
	end
	local dy = insetShift(menuGui)
	for _, d in ipairs(menuGui:GetDescendants()) do
		if d ~= except and d:IsA("GuiObject") and string.sub(d.Name, 1, 11) == "MenuButton_" and d.AbsoluteSize.X > 0 and shownIn(d, menuGui) then
			out[#out + 1] = rectOf(d, dy)
		end
	end
	return out
end

-- What the pointer arrow must not cover: the other menu tiles and the tutorial card / bubble; (2026-11-28 playtest C51:
-- at 640x360 the step-21 arrow pointed up at Home from inside the thumbstick's zone) on touch, Roblox's thumbstick and
-- the RUN / DASH buttons too, as for the guide chip
local function pointerObstacles(button, area)
	local list = menuButtonRects(button)
	for _, r in ipairs(touchButtonRects()) do
		list[#list + 1] = r
	end
	list[#list + 1] = area and thumbstickRect(area) or nil
	if UI.Root and UI.Root.Visible then
		local part = (collapsed() and S.stripChip) and UI.Portrait or UI.Root -- (Pitch 2 03 B: folded, the root is the strip)
		if part and part.AbsoluteSize.X > 0 then
			list[#list + 1] = rectOf(part, 0)
		end
	end
	return list
end

local function rectsOverlap(a, b)
	return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

-- Where the arrow goes around target rect `r`: right of it pointing left (the default), else above it pointing
-- down, below it pointing up or left of it pointing right, whichever first stays on screen and clear of the
-- neighbouring tiles and the tutorial card / bubble (the 2 x 3 phone grid has a tile right of Index). Returns
-- side, rotation; side "none" when every side is taken: then only the gold tile marks the button (an arrow on a
-- neighbouring tile would point the new player at the wrong button).
local POINTER_SIDES = { { "right", 0 }, { "above", -90 }, { "below", 90 }, { "left", 180 } }
local function pointerCentre(side, r, len, thick, push)
	local cx, cy = (r.x0 + r.x1) * 0.5, (r.y0 + r.y1) * 0.5
	if side == "right" then
		return r.x1 + push + len / 2, cy, len, thick
	elseif side == "above" then
		return cx, r.y0 - push - len / 2, thick, len
	elseif side == "below" then
		return cx, r.y1 + push + len / 2, thick, len
	end
	return r.x0 - push - len / 2, cy, len, thick
end

local function choosePointerSide(r, k, area, button)
	local len, thick = 68 * k, 44 * k
	local push = 15 * k -- the farthest point of the bounce
	local obstacles = pointerObstacles(button, area)
	for _, spec in ipairs(POINTER_SIDES) do
		local cx, cy, w, h = pointerCentre(spec[1], r, len, thick, push)
		local box = { x0 = cx - w / 2, y0 = cy - h / 2, x1 = cx + w / 2, y1 = cy + h / 2 }
		local clear = box.x0 >= 0 and box.y0 >= 0 and box.x1 <= area.X and box.y1 <= area.Y
		if clear then
			for _, o in ipairs(obstacles) do
				if rectsOverlap(box, o) then
					clear = false
					break
				end
			end
		end
		if clear then
			return spec[1], spec[2]
		end
	end
	return "none", 0
end

local function updateMenuPointer(dt, t)
	local st = S.state
	-- hidden while a window / the Index / the roulette covers the menu (S.windowOpen): it would draw on top of it
	local want = st and not st.Done and not S.finale and st.Target and st.Target.Kind == "Menu" and S.shown and not inMatch()
		and not S.windowOpen
	local targetId = want and st.Target.Id or nil
	-- (Pitch 2 item 13 A) the travel guide away from the lobby points at the Home tile (its Go home opens the home portal)
	if G.active and G.phase == "Home" and not S.windowOpen and not inMatch() then
		want, targetId = true, "Home"
	end
	M.findTimer = M.findTimer - dt
	if M.findTimer <= 0 then
		M.findTimer = 1
		safe("menu hook", refreshClickHook)
		if want then
			local valid = M.button and M.button.Parent and M.buttonId == targetId
			if valid then
				local owner = M.button:FindFirstAncestorOfClass("ScreenGui")
				valid = owner ~= nil and shownIn(M.button, owner)
			end
			if not valid then
				M.button = findMenuButton(targetId)
				M.buttonId = targetId
				M.side = nil
			end
		end
	end
	if not want or not M.button or not M.button.Parent then
		hidePointer()
		return
	end
	local owner = M.button:FindFirstAncestorOfClass("ScreenGui")
	local r = rectOf(M.button, insetShift(owner))
	local w, h = r.x1 - r.x0, r.y1 - r.y0
	if w <= 0 or h <= 0 then
		hidePointer()
		return
	end
	local k = Theme.ScreenFactor()
	local pk = UI.PointerScale and UI.PointerScale.Scale or k -- the arrow's snapped scale (layout)
	-- (U9-9 look 2) the tile itself turns gold (the kit's Selected look); no ring over its neighbours
	setPointed(targetId)
	-- the side is re-chosen after every layout pass (M.side = nil there, twice a second at most)
	if not M.side then
		local okSide, side, rotation = pcall(choosePointerSide, r, pk, guiArea(), M.button)
		if okSide then
			M.side, M.rotation = side, rotation
		else
			M.side, M.rotation = "right", 0
		end
	end
	if M.side == "none" then
		if UI.Arrow.Visible then
			UI.Arrow.Visible = false
		end
		return
	end
	local bounce = (8 + 7 * (math.sin(t * 5) + 1) * 0.5) * pk
	local len, thick = 68 * pk, 44 * pk
	local cx, cy = pointerCentre(M.side, r, len, thick, bounce)
	local rotation = M.rotation or 0
	-- (kit B U9-9) the arrow's box (after its quarter turn) starts on a whole screen px, so every cell is whole
	local bw, bh = len, thick
	if rotation % 180 ~= 0 then
		bw, bh = thick, len
	end
	cx = math.floor(cx - bw / 2 + 0.5) + bw / 2
	cy = math.floor(cy - bh / 2 + 0.5) + bh / 2
	UI.Arrow.Rotation = rotation
	UI.Arrow.Position = UDim2.fromOffset(cx, cy)
	UI.Arrow.Visible = true
end

----------------------------------------------------------------------
-- World guide: voxel arrow, sparkle ring, sign and dotted beam
----------------------------------------------------------------------
local function clientFx()
	local folder = Workspace:FindFirstChild("ClientFx")
	if not folder then
		folder = make("Folder", "ClientFx", nil, Workspace)
	end
	return folder
end

local function finishArrowPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
end

-- The golden guide arrow, sculpted with the voxel kit (a stepped-block arrow when the kit is missing).
local function buildArrowModel()
	local Voxel = mod("Voxel")
	local model = nil
	if Voxel and type(Voxel.NewGrid) == "function" and type(Voxel.Build) == "function" then
		local ok, built = pcall(function()
			local g = Voxel.NewGrid(24)
			-- head: a round cone pointing down with a lighter lip at its base
			Voxel.Shape(g, { Kind = "Cone", A = { 0, 9, 0 }, B = { 0, -0.5, 0 }, Radius = 6.4, Key = "Gold" })
			Voxel.Shape(g, { Kind = "Torus", Center = { 0, 9.2, 0 }, Radius = 5.8, Thickness = 0.8, Key = "Rim" })
			-- shaft: a rounded column with a soft dome on top
			Voxel.Shape(g, { Kind = "RoundBox", Center = { 0, 14.5, 0 }, Size = { 5, 11, 5 }, Round = 1.6, Key = "Gold" })
			Voxel.Shape(g, { Kind = "Ellipsoid", Center = { 0, 19.5, 0 }, Radius = { 2.4, 1.2, 2.4 }, Key = "Rim" })
			-- glints on the front-left edge
			Voxel.Shape(g, { Kind = "Box", Center = { -1, 14, -2 }, Size = { 1, 8, 1 }, Key = "Shine", Op = "Paint" })
			Voxel.Shape(g, { Kind = "Box", Center = { -2, 6.5, -4 }, Size = { 1, 3, 3 }, Key = "Shine", Op = "Paint" })
			Voxel.Shade(g, { Skip = { Shine = true }, DarkAt = -0.7, LightAt = 0.5, Noise = 0.03, Seed = 11 })
			return Voxel.Build(g, {
				VoxelSize = K.VOXEL,
				Palette = {
					Gold = C.Arrow,
					Gold_Light = C.ArrowLight,
					Gold_Dark = C.ArrowDark,
					Rim = C.ArrowLight,
					Rim_Light = C.ArrowShine,
					Rim_Dark = C.Arrow,
					Shine = C.ArrowShine,
				},
				Center = true,
				Name = "GuideArrow",
				MaxParts = 110,
				CastShadow = false,
			})
		end)
		if ok and typeof(built) == "Instance" then
			model = built
		else
			warnOnce("arrow", "voxel arrow failed: " .. tostring(built))
		end
	end
	if not model then
		model = make("Model", "GuideArrow", nil, nil)
		-- a stepped head (tip at the bottom) under a block shaft
		local widths = { 0.8, 1.8, 3.0, 4.2 }
		for i, w in ipairs(widths) do
			make("Part", "Head" .. i, {
				Size = Vector3.new(w, 1, w),
				Color = (i % 2 == 0) and C.ArrowDark or C.Arrow,
				Material = Enum.Material.SmoothPlastic,
				CFrame = CFrame.new(0, i - 4.5, 0),
			}, model)
		end
		make("Part", "Shaft", {
			Size = Vector3.new(1.8, 4, 1.8),
			Color = C.ArrowLight,
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(0, 2.5, 0),
		}, model)
	end
	local parts, offsets = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			finishArrowPart(d)
			table.insert(parts, d)
			table.insert(offsets, d.CFrame)
		end
	end
	-- (Pitch 2 item 13 A, kit B: nothing glows) the PointLight "Glow" on the first part went
	return model, parts, offsets
end

local function buildWorldGuide()
	W.built = true
	local folder = make("Folder", "TutorialGuide", nil, nil)
	W.folder = folder
	local model, parts, offsets = buildArrowModel()
	model.Parent = folder
	W.arrowParts, W.arrowOffsets = parts, offsets
	W.arrowTop = nil
	-- (look review fin0, MJ1) the arrow's outline for its box on the screen: the corners of its parts that are the
	-- farthest out along one of the 124 directions of a 5x5x5 grid (the points its silhouette can end at, a few dozen of
	-- the ~800 corners), round its centre. One box round the whole arrow (r1) drew it a head's width wide at its narrow
	-- tip: seen from below, that box's far bottom corners projected ~40 px under the real arrow and the chip dodged an
	-- arrow that ended above it
	local corners, wide = {}, 0
	for i, p in ipairs(parts) do
		local o, s = offsets[i].Position, p.Size / 2
		wide = math.max(wide, math.abs(o.X) + s.X, math.abs(o.Z) + s.Z)
		for _, dx in ipairs({ -1, 1 }) do
			for _, dy in ipairs({ -1, 1 }) do
				for _, dz in ipairs({ -1, 1 }) do
					corners[#corners + 1] = o + Vector3.new(dx * s.X, dy * s.Y, dz * s.Z)
				end
			end
		end
	end
	local hull, taken = {}, {}
	for x = -2, 2 do
		for y = -2, 2 do
			for z = -2, 2 do
				if x ~= 0 or y ~= 0 or z ~= 0 then
					local best, at = -math.huge, nil
					for i, c in ipairs(corners) do
						local v = c.X * x + c.Y * y + c.Z * z
						if v > best then
							best, at = v, i
						end
					end
					if at and not taken[at] then
						taken[at] = true
						hull[#hull + 1] = corners[at]
					end
				end
			end
		end
	end
	W.arrowHull = hull
	-- (look review fin0, minor) the GuideSign's edge stands K.SIGN_GAP studs past the arrow's widest part (SIGN_STUDS
	-- 1.6 sat inside its ~2.4-stud head: the card hid the arrow's side, 3 px at 844x390, 12 at 1920)
	W.signStuds = math.max(K.SIGN_STUDS, wide + K.SIGN_GAP)

	-- (Pitch 2 item 13_travel_guide A, the owner's pick "Gold arrow + dot trail"; it was a glowing Beam of a sparkle strip
	-- from the hip and a ring of Neon sparkles) the trail is flat gold dot blocks on the ground (Dots: a pool of
	-- SmoothPlastic squares, laid every K.DOT_EVERY s from K.DOT_START studs ahead of the feet toward the target, every
	-- K.DOT_STEP studs, at most K.TRAIL_MAX studs out); no Neon, no light
	W.dotFolder = make("Folder", "Dots", nil, folder)
	W.dots = {}
	W.dotTimer = 0

	-- floating sign beside the arrow's shaft (World text rule: pixel-sized, the name 24 px and the distance 19 px at 1080p
	-- on a compact plate sized to its text; a UIScale follows the screen-height factor). (Pitch 2 item 04 / 13: the navy
	-- rounded card with the gold stroke went) a stone tag: the Stone face, a 3 px wood edge, the gold lip, brown ink.
	-- AlwaysOnTop with a long MaxDistance on purpose: it is the way-finder, seen from anywhere in the lobby.
	local anchor = make("Part", "SignAnchor", { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }, folder)
	finishArrowPart(anchor)
	W.labelAnchor = anchor
	local k = Theme.ScreenFactor()
	-- beside the shaft, not over the arrow's head: the billboard's left edge on the axis (SizeOffset 0.5), moved
	-- W.signStuds right of it on the screen (StudsOffset: past the arrow's widest part), the card on its left edge
	local signGui = make("BillboardGui", "GuideSign", {
		Size = UDim2.fromOffset(math.floor(K.SIGN_W * k), math.floor(K.SIGN_H * k)),
		SizeOffset = Vector2.new(0.5, 0),
		StudsOffset = Vector3.new(W.signStuds or K.SIGN_STUDS, 0, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 4000,
		ClipsDescendants = false,
	}, anchor)
	W.labelGui = signGui
	local card = box("Card", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Stone,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, K.SIGN_EDGE, 0.5, 0),
		Size = UDim2.fromOffset(150, K.SIGN_NAME + K.SIGN_INFO + 22),
	}, signGui)
	-- (the UIScale grows the card round its anchor, the left edge: it stays beside the shaft at any screen size)
	edge(card, SIGN.Wood, K.SIGN_EDGE)
	lipOf(card, SIGN.GoldLip, K.SIGN_LIP)
	W.signCard = card
	W.signScale = make("UIScale", "ReadScale", { Scale = k }, card)
	W.signName = label(card, "Name", "", "Heading", K.SIGN_NAME, SIGN.Text, {
		Position = UDim2.fromOffset(K.SIGN_PAD, 5),
		Size = UDim2.fromOffset(100, K.SIGN_NAME + 4),
		TextScaled = false,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	W.signDistance = label(card, "Distance", "", "Label", K.SIGN_INFO, SIGN.TextMuted, {
		Position = UDim2.fromOffset(K.SIGN_PAD, 5 + K.SIGN_NAME + 5),
		Size = UDim2.fromOffset(100, K.SIGN_INFO + 4),
		TextScaled = false,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
end

-- the sign's card hugs its two lines (measured; no AutomaticSize: the lip is a child outside any list). (look review
-- fin1, MJ-B) W.signShort: the name alone, the distance line off (where the two lines do not fit beside the arrow)
local function layoutSign()
	local card = W.signCard
	if not card then
		return
	end
	local short = W.signShort == true
	W.signDistance.Visible = not short
	local nameW = Theme.Measure(W.signName.Text, "Heading", K.SIGN_NAME).X
	local infoW = short and 0 or Theme.Measure(W.signDistance.Text, "Label", K.SIGN_INFO).X
	local inner = math.ceil(math.max(nameW, infoW, 60)) + 4
	W.signName.Size = UDim2.fromOffset(inner, K.SIGN_NAME + 4)
	W.signDistance.Size = UDim2.fromOffset(inner, K.SIGN_INFO + 4)
	local lines = short and (5 + K.SIGN_NAME + 4) or (5 + K.SIGN_NAME + 5 + K.SIGN_INFO + 4)
	card.Size = UDim2.fromOffset(inner + 2 * K.SIGN_PAD, lines + 4 + K.SIGN_LIP)
end

-- (look review fin0, MJ2) the board of the gate the world guide stands over is off while the guide shows: the arrow
-- (ARROW_LIFT over the gate's top) and the GuideSign hang exactly where the board hangs (27 studs up, growing upwards, a
-- pixel billboard, so no studs lift clears it at every distance), and the GuideSign already names the place (the
-- approved mock 13 A shows the target gate with the sign alone). Its own Enabled comes back when the guide moves on or
-- ends; a board switched on by someone else meanwhile is switched off again on the next frame. holdBoard(nil) lets go.
local function holdBoard(board)
	local held = W.board
	if held and held ~= board then
		if held.Parent then
			held.Enabled = W.boardWas ~= false
		end
		W.board, W.boardWas = nil, nil
	end
	if board and board.Parent then
		if W.board ~= board then
			W.board, W.boardWas = board, board.Enabled
		end
		if board.Enabled then
			board.Enabled = false
		end
	end
end

local function setWorldActive(on)
	if not W.built then
		return
	end
	if not on then
		holdBoard(nil)
	end
	if on == W.active then
		return
	end
	W.active = on
	if on then
		W.folder.Parent = clientFx()
		W.dotTimer = 0 -- the trail is laid again from where the player stands now
	else
		W.folder.Parent = nil
		W.distance = nil
	end
end

-- Bounding box of a Model / BasePart / Folder (cf, size) or nil.
local function boundsOf(inst)
	if inst:IsA("Model") then
		local ok, cf, size = pcall(function()
			return inst:GetBoundingBox()
		end)
		if ok and cf and size then
			return cf, size
		end
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	end
	local lo, hi = nil, nil
	local n = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
			if n > 4000 then
				break
			end
			local p, s = d.Position, d.Size * 0.5
			local a, b = p - s, p + s
			if lo then
				lo = Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z))
				hi = Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z))
			else
				lo, hi = a, b
			end
		end
	end
	if not lo then
		return nil
	end
	return CFrame.new((lo + hi) * 0.5), hi - lo
end

local function findSpotFolder(lobby, index)
	if not lobby or type(index) ~= "number" then
		return nil
	end
	local named = lobby:FindFirstChild(string.format("Spot_%02d", index), true)
	if named and named:GetAttribute("SpotIndex") == index then
		return named
	end
	for _, d in ipairs(lobby:GetDescendants()) do
		if (d:IsA("Folder") or d:IsA("Model")) and d:GetAttribute("SpotIndex") == index then
			return d
		end
	end
	return nil
end

-- Where the guide points: { Ground = Vector3, ArrowAt = Vector3, Radius, Name } or nil.
local function resolveTarget(target)
	local lobby = Workspace:FindFirstChild("NimbusLobby")
	local kind = target.Kind
	local name = target.Label
	local server = typeof(target.Position) == "Vector3" and target.Position or nil
	local ground, arrowAt, radius = nil, nil, 6
	local model = nil
	if kind == "Spot" then
		radius = 9
		name = name or "Your Home"
		local index = target.SpotIndex
		if type(index) ~= "number" then
			index = LocalPlayer:GetAttribute(Config.Attr.SpotIndex)
		end
		ground = server
		if not ground then
			local folder = findSpotFolder(lobby, index)
			local plot = folder and folder:FindFirstChild("Plot")
			if plot and plot:IsA("Model") then
				local okPivot, pivot = pcall(function()
					return plot:GetPivot()
				end)
				if okPivot and pivot then
					ground = pivot.Position
				end
			elseif folder then
				local cf, size = boundsOf(folder)
				if cf then
					ground = cf.Position - Vector3.new(0, size.Y * 0.5, 0)
				end
			end
		end
		if ground then
			arrowAt = ground + Vector3.new(0, 6, 0)
		end
	elseif kind == "Gate" then
		-- (Pitch 2 item 13 A, the travel guide) a lobby gate by its ProximityPrompt (target.Prompt, e.g. AltarGatePrompt):
		-- the ground under its prompt part, the arrow over its gate model (the part itself when it has none)
		radius = 6
		name = name or "Gate"
		local prompt = lobby and type(target.Prompt) == "string" and lobby:FindFirstChild(target.Prompt, true)
		local part = prompt and prompt.Parent
		if part and part:IsA("BasePart") then
			local p, half = part.Position, part.Size.Y * 0.5
			ground = Vector3.new(p.X, p.Y - half, p.Z)
			arrowAt = Vector3.new(p.X, p.Y + half + 3, p.Z)
			local gate = part:FindFirstAncestorOfClass("Model")
			if gate and gate ~= lobby then
				local cf, size = boundsOf(gate)
				if cf and size.Y < 60 then
					arrowAt = Vector3.new(p.X, cf.Position.Y + size.Y * 0.5, p.Z)
				end
				model = gate
			end
		end
	else
		local id = target.Id
		if kind == "Portal" then
			radius = 7
			id = id or "Obby" -- Phase 5: the ONE Obby portal (Portal_Obby in the Gate Court)
			model = lobby and lobby:FindFirstChild("Portal_" .. tostring(id), true)
			if not name then
				local diff = Config.GetDifficulty and Config.GetDifficulty(id)
				name = (diff and diff.DisplayName or tostring(id)) .. " Portal"
			end
		else
			radius = 5
			id = id or firstRouletteId()
			model = lobby and lobby:FindFirstChild("Roulette_" .. tostring(id), true)
			if not name then
				name = kind == "Shop" and "Cloud Shop" or (tostring(id) .. " Roulette")
			end
		end
		if model then
			local cf, size = boundsOf(model)
			if cf then
				local c = cf.Position
				arrowAt = Vector3.new(c.X, c.Y + size.Y * 0.5, c.Z)
				ground = server or Vector3.new(c.X, c.Y - size.Y * 0.5, c.Z)
			end
		end
		if not ground and server then
			ground = server
			arrowAt = server + Vector3.new(0, 8, 0)
		end
	end
	if not ground or not arrowAt then
		return nil
	end
	-- (look review fin0, MJ2) a gate's hanging board (WorldStyle.BuildTag "GateTag", or a builder's stand-in of that name)
	local board = nil
	if model and (kind == "Gate" or kind == "Portal") then
		local b = model:FindFirstChild("GateTag", true)
		board = (b and b:IsA("BillboardGui")) and b or nil
	end
	return { Ground = ground, ArrowAt = arrowAt, Radius = radius, Name = name or "", Board = board }
end

local function targetKey(target)
	local p = typeof(target.Position) == "Vector3" and target.Position or Vector3.new()
	return table.concat({
		tostring(target.Kind),
		tostring(target.Id),
		tostring(target.SpotIndex),
		string.format("%.0f,%.0f,%.0f", p.X, p.Y, p.Z),
	}, "|")
end

-- (Pitch 2 item 13 A) the ground under a trail point: a ray down from a little over the straight line from the feet to
-- the target (the character and the guide are skipped; every guide part is CanQuery off), else that line
local function groundY(x, z, line)
	local hit = nil
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { LocalPlayer.Character, W.folder }
		local result = Workspace:Raycast(Vector3.new(x, line + 4, z), Vector3.new(0, -12, 0), params)
		if result then
			hit = result.Position.Y
		end
	end)
	return hit or line
end

-- the trail's i-th dot block (a pool: made once, hidden by Transparency 1 when not laid)
local function dotAt(i)
	local d = W.dots[i]
	if not d then
		d = make("Part", "Dot" .. i, {
			Size = Vector3.new(K.DOT_SIZE, 0.16, K.DOT_SIZE),
			Color = SIGN.Gold,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 1,
		}, W.dotFolder)
		finishArrowPart(d)
		W.dots[i] = d
	end
	return d
end

-- lays the dot trail from K.DOT_START studs ahead of `from` (the root) toward `goal` (the target's ground), every
-- K.DOT_STEP studs, out to K.TRAIL_MAX; none within K.TRAIL_HIDE of the goal. -> the flat distance to the goal
local function layDots(from, goal)
	local flat = Vector3.new(goal.X - from.X, 0, goal.Z - from.Z)
	local dist = flat.Magnitude
	local n = 0
	if dist > K.TRAIL_HIDE then
		local dir = flat.Unit
		local yaw = math.atan2(-dir.X, -dir.Z)
		local reach = math.min(dist - 2, K.TRAIL_MAX)
		local footY = from.Y - 3
		local s = K.DOT_START
		while s <= reach and n < K.DOT_MAX do
			n = n + 1
			local x, z = from.X + dir.X * s, from.Z + dir.Z * s
			local line = footY + (goal.Y - footY) * (s / dist)
			local part = dotAt(n)
			part.CFrame = CFrame.new(x, groundY(x, z, line) + 0.1, z) * CFrame.Angles(0, yaw, 0)
			if part.Transparency ~= 0 then
				part.Transparency = 0
			end
			s = s + K.DOT_STEP
		end
	end
	for i = n + 1, #W.dots do
		if W.dots[i].Transparency ~= 1 then
			W.dots[i].Transparency = 1
		end
	end
	return dist
end

local function updateWorldGuide(dt, t)
	local st = S.state
	local target = st and st.Target
	local want = st and not st.Done and not S.finale and S.shown and target and WORLD_KINDS[target.Kind] and not inMatch()
	-- (Pitch 2 item 13 A) the travel guide the player asked for takes the world guide while it walks the lobby (one guide
	-- at a time; the tutorial's comes back when it ends)
	if G.active and G.target and (G.phase == "Walk" or G.phase == "Here") then
		target, want = G.target, true
	end
	if not want then
		setWorldActive(false)
		return
	end
	if not W.built then
		local ok = safe("world guide", buildWorldGuide)
		if not ok then
			return
		end
	end
	local key = targetKey(target)
	W.resolveTimer = W.resolveTimer - dt
	if key ~= W.key or (not W.resolved and W.resolveTimer <= 0) then
		W.key = key
		W.resolveTimer = K.RESOLVE_RETRY
		local ok, resolved = pcall(resolveTarget, target)
		W.resolved = ok and resolved or nil
		if W.resolved then
			W.signName.Text = W.resolved.Name
			W.arrowTop = nil
			W.labelTimer = 0
			W.dotTimer = 0
		end
	end
	local goal = W.resolved
	if not goal then
		setWorldActive(false)
		return
	end
	setWorldActive(true)
	holdBoard(goal.Board)

	-- (Pitch 2 item 13 A) the arrow hops between two heights in hard steps (it bobbed on a sine and spun), its parts
	-- written only when it hops
	local hop = (math.floor(t / K.BOB_STEP) % 2 == 0) and 0 or K.BOB
	W.arrowHome = goal.ArrowAt + Vector3.new(0, K.ARROW_LIFT, 0)
	W.arrowBase = W.arrowHome
	local top = W.arrowBase + Vector3.new(0, hop, 0)
	if W.arrowTop ~= top then
		W.arrowTop = top
		local cf = CFrame.new(top)
		local parts, offsets = W.arrowParts, W.arrowOffsets
		for i = 1, #parts do
			parts[i].CFrame = cf * offsets[i]
		end
		W.labelAnchor.CFrame = CFrame.new(W.arrowBase + Vector3.new(0, K.SIGN_LIFT, 0))
	end

	-- the dot trail from just ahead of the feet toward the target (capped), the distance on the sign
	local root = rootPart()
	W.labelTimer = W.labelTimer - dt
	W.dotTimer = W.dotTimer - dt
	if root then
		local from = root.Position
		if W.dotTimer <= 0 then
			W.dotTimer = K.DOT_EVERY
			W.distance = layDots(from, goal.Ground)
		end
		local dist = W.distance or Vector3.new(goal.Ground.X - from.X, 0, goal.Ground.Z - from.Z).Magnitude
		if W.labelTimer <= 0 then
			W.labelTimer = 0.25
			local text = (dist <= K.TRAIL_HIDE) and "You're here!" or (math.floor(dist + 0.5) .. " studs away")
			if W.signDistance.Text ~= text or W.signLaid ~= W.signName.Text then
				W.signDistance.Text = text
				W.signLaid = W.signName.Text
				layoutSign()
			end
		end
	else
		W.distance = nil
	end
end

----------------------------------------------------------------------
-- State handling
----------------------------------------------------------------------
local function sanitize(payload)
	local st = {
		Step = math.max(1, math.floor(tonumber(payload.Step) or 1)),
		Total = math.max(1, math.floor(tonumber(payload.Total) or 1)),
		Id = type(payload.Id) == "string" and payload.Id or "",
		Title = type(payload.Title) == "string" and payload.Title or "",
		Text = type(payload.Text) == "string" and payload.Text or "",
		CompleteOn = type(payload.CompleteOn) == "string" and payload.CompleteOn or nil,
		Hint = type(payload.Hint) == "string" and payload.Hint or nil,
		Button = type(payload.Button) == "string" and payload.Button or nil,
		AlsoNext = payload.AlsoNext == true,
		Done = payload.Done == true,
		Completed = payload.Completed == true,
		Skipped = payload.Skipped == true,
		Reward = tonumber(payload.Reward) or 0,
		Target = nil,
	}
	if st.Step > st.Total then
		st.Total = st.Step
	end
	if type(payload.Target) == "table" and type(payload.Target.Kind) == "string" then
		local t = payload.Target
		st.Target = {
			Kind = t.Kind,
			Id = (type(t.Id) == "string") and t.Id or nil,
			Label = (type(t.Label) == "string") and t.Label or nil,
			Position = (typeof(t.Position) == "Vector3") and t.Position or nil,
			SpotIndex = (type(t.SpotIndex) == "number") and t.SpotIndex or nil,
		}
	end
	-- older servers: fill in what the shared step list knows
	local Steps = mod("TutorialSteps")
	-- the step at the payload's index first (Phase 4: chapter 4's "portal" shares its id with chapter 1's), else by id
	local def = nil
	if Steps and type(Steps.Steps) == "table" then
		local atIndex = Steps.Steps[st.Step]
		if type(atIndex) == "table" and atIndex.Id == st.Id then
			def = atIndex
		elseif type(Steps.IndexOf) == "table" and Steps.IndexOf[st.Id] then
			def = Steps.Steps[Steps.IndexOf[st.Id]]
		end
	end
	if type(def) == "table" then
		st.CompleteOn = st.CompleteOn or def.CompleteOn
		st.Hint = st.Hint or def.Hint
		st.Button = st.Button or def.Button
		if payload.AlsoNext == nil and def.AlsoNext == true and st.CompleteOn == def.CompleteOn then
			st.AlsoNext = true -- an older server: the shared step list knows
		end
		if st.Title == "" and type(def.Title) == "string" then
			st.Title = def.Title
		end
	end
	st.CompleteOn = st.CompleteOn or "Next"
	return st
end

local function ensureLoop()
	if R.loop then
		return
	end
	R.loop = RunService.RenderStepped:Connect(function(dt)
		TutorialController.Step(dt)
	end)
end

----------------------------------------------------------------------
-- Travel guide (Pitch 2 item 13_travel_guide A, the owner's pick "Gold arrow + dot trail"; its chip the owner's pick B of
-- 2026-11-23, "Top-bar plank"): the Shop's "Show the way" (it teleported) starts it. In the lobby world it is the world
-- guide above, pointed at the target's gate (the dot trail from the feet, the arrow over the gate; its GuideSign is
-- retired while the travel guide runs), and a chip, the top bar pill's twin: a cream stone plank docked in Roblox's top
-- band at its right end beside '...' (a portrait phone: on the vitals stack), the needle (PixelIcon's arrows, the way to
-- the gate), "Storm Altar" over "NN studs away" (a PC: one line, the stud count in its tag) and the red X (a 44 px target)
-- that ends it. Away from the lobby world (an arena, a dungeon) it routes home first: the house mark, "Home first" /
-- "then follow the arrow", the menu pointer on the Home tile (its Go home opens the home portal) and no trail; back in
-- the lobby the trail picks up by itself. Within K.GUIDE_ARRIVE studs of the gate the chip turns grass ("You're here" /
-- CloudUI.PromptWords) for K.GUIDE_HERE s, slides up in two hard steps and the guide ends. A match or a battle / run /
-- the Ring (a portal walked into), standing at the altar, the X or Stop end it at once; a second Start replaces the
-- first. Nothing is left behind: the chip's ScreenGui goes, the world guide hides (or goes back to the tutorial's target,
-- its sign back on), the pointer clears.
--   TutorialController.Guide.Start(id) -> boolean   id: a key of GUIDE_TARGETS ("StormAltar"); false in a match / battle
--   TutorialController.Guide.Stop()
--   TutorialController.Guide.Active() -> id | nil
--   TutorialController.Guide.Phase() -> "Walk" | "Home" | "Here" | nil
----------------------------------------------------------------------
local GUIDE_TARGETS = {
	StormAltar = { Kind = "Gate", Id = "Altar", Prompt = "AltarGatePrompt", Label = "Storm Altar" },
}
local Guide = {}
TutorialController.Guide = Guide

local function guideBlocked()
	return inMatch() or LocalPlayer:GetAttribute(Config.Attr.InBattle or "InBattle") ~= nil
end

-- the lobby world the trail can walk: the plaza, its islands, the ring street and the home plots on it, at lobby height
local function inLobbyWorld(pos)
	local L = Config.Lobby
	if typeof(pos) ~= "Vector3" or type(L) ~= "table" or typeof(L.Origin) ~= "Vector3" then
		return false
	end
	local dx, dz = pos.X - L.Origin.X, pos.Z - L.Origin.Z
	local reach = (L.SpotRingRadius or 340) + (L.PlotSize or 72)
	return dx * dx + dz * dz <= reach * reach and math.abs(pos.Y - L.Origin.Y) <= (L.ZoneBand or 80)
end

-- the target's prompt part in the lobby (looked up again while missing: the lobby may stream in)
local function guidePart()
	if G.part and G.part.Parent then
		return G.part
	end
	local lobby = Workspace:FindFirstChild("NimbusLobby")
	local prompt = lobby and G.spec and lobby:FindFirstChild(G.spec.Prompt, true)
	local part = prompt and prompt.Parent
	G.part = (part and part:IsA("BasePart")) and part or nil
	return G.part
end

-- (the owner's pick B of 2026-11-23 on the guide chip pitch, "Top-bar plank", the X on the RIGHT; Gemini's left X was not
-- taken) the chip is the top bar pill's twin and stands at ONE home: Roblox's top band at its right end, its face
-- K.GUIDE_DOCK px left of TopbarInset's right end (the '...' room; read as the pill reads it) at the pill's own height and
-- row; a portrait phone (no room in the band) on the vitals stack, flush with the card's left edge, its ink K.GUIDE_STACK
-- px over the name plank (over the tutorial's quest strip when that docks there, over a touch key in its columns: clear
-- of RUN). It never moves, hides or changes its line on a camera move (but on a portrait phone it steps aside, hidden in
-- its place, while a world sign the camera brings stands on its spot: asideWanted): its home is read again only every K.LAYOUT_EVERY s
-- (the HUD, a turned phone) and on a new phase, and its width is fixed per phase (a three-digit stud count kept room
-- for). The travel guide's GuideSign is retired (its name and stud count are the chip's lines; the tutorial's own guide
-- keeps its sign); the gold arrow over the gate and the dot trail stay. The needle (guideNeedle) is PixelIcon's own
-- arrows, never a turned frame. Screen px throughout: the chip's ScreenGui ignores the gui inset, as the top bar's does.

-- the product of the UIScales on `inst` and its ancestors (what its stroke's Thickness is drawn at)
local function drawnScale(inst)
	local k, node = 1, inst
	while node and not node:IsA("ScreenGui") do
		for _, c in ipairs(node:GetChildren()) do
			if c:IsA("UIScale") then
				k = k * c.Scale
			end
		end
		node = node.Parent
	end
	return k
end

-- what `inst` draws, in screen px: its box and its border edge (a UIStroke outside the box) -> { x0, y0, x1, y1 }
local function inkRect(inst)
	local gui = inst:FindFirstAncestorOfClass("ScreenGui")
	local r = rectOf(inst, (gui and not gui.IgnoreGuiInset) and topInset() or 0)
	local s = inst:FindFirstChildOfClass("UIStroke")
	if s and s.Enabled and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
		local e = s.Thickness * drawnScale(inst)
		r = { x0 = r.x0 - e, y0 = r.y0 - e, x1 = r.x1 + e, y1 = r.y1 + e }
	end
	return r
end

-- the GuideSign on (both lines, or `short`: the name alone) or off; W.signGen counts its jumps
local function setSignShown(on, short)
	local gui = W.labelGui
	if not gui then
		return
	end
	if gui.Enabled ~= on then
		gui.Enabled = on
		W.signGen = (W.signGen or 0) + 1
	end
	short = on and short == true
	if (W.signShort == true) ~= short then
		W.signShort = short
		W.signGen = (W.signGen or 0) + 1
		layoutSign()
	end
end

-- the whole screen px of `v` design px at the screen factor (the pitch's px(): never under 1)
local function chipPx(v)
	return math.max(1, math.floor(v * (G.k or 1) + 0.5))
end

-- Roblox's top band: its height (K.GUIDE_BAND when the gui inset reads 0) and the free band's right end (TopbarInset,
-- else K.GUIDE_RIGHT_RESERVE px off the right edge: the '...' button), as TopBarController reads them
local function bandOf(vpX)
	local band = topInset()
	if band <= 0 then
		band = K.GUIDE_BAND
	end
	local right = vpX - K.GUIDE_RIGHT_RESERVE
	local ok, tb = pcall(function()
		return GuiService.TopbarInset
	end)
	if ok and typeof(tb) == "Rect" and tb.Min.X > 0 and tb.Max.X > tb.Min.X then
		right = tb.Max.X
	end
	return band, right
end

-- the pill's height and row in the band (TopBarController.relayout's own rule) -> h, y
local function pillRow(band)
	local touch = UserInputService.TouchEnabled == true
	local h = math.floor(math.clamp(band - (touch and 6 or 10), K.GUIDE_PILL_MIN, touch and K.GUIDE_PILL_TOUCH or K.GUIDE_PILL))
	return h, math.max(0, math.floor((band - h) / 2))
end

-- where the chip's face stands: its top-left in screen px, for a face `w` x `h` with a wood edge `e`
local function chipHome(w, h, e)
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	if not G.portrait then
		-- (the pill's row: its own height's middle of the band; a PC's ticket, a touch pill tall, the same rule)
		local band, right = bandOf(vp.X)
		return right - K.GUIDE_DOCK - w, math.max(0, math.floor((band - h) / 2))
	end
	-- the vitals stack: the card's left edge, the name plank's ink top (the quest strip's when it docks over it)
	local pg = playerGui()
	local hud = pg and pg:FindFirstChild("NimbusHud")
	local vit = hud and hud:FindFirstChild("BottomLeft") and hud.BottomLeft:FindFirstChild("Vitals")
	local body = vit and vit:FindFirstChild("Body")
	local card = body and body:FindFirstChild("Card")
	local tab = body and body:FindFirstChild("NameTab")
	local x, foot = K.EDGE, vp.Y - K.EDGE
	if card and vit:IsA("GuiObject") and vit.AbsoluteSize.X > 0 and shownIn(vit, hud) then
		x = card.AbsolutePosition.X
		foot = inkRect(tab and tab.AbsoluteSize.X > 0 and tab or card).y0
	end
	-- (look:chipB major 3) never past the screen's K.EDGE gutter: paintChip shortens a ticket that would run past it
	-- (its 'NN studs'); this holds a chip whose short line still would not fit
	if w > 0 then
		x = math.max(K.EDGE + e, math.min(x, vp.X - K.EDGE - e - w))
	end
	local strip, over = UI.Strip, nil
	if strip and strip.Visible and strip.AbsoluteSize.Y > 0 and UI.Gui and shownIn(strip, UI.Gui) then
		local s = inkRect(strip)
		if s.y1 <= foot + 0.5 and s.y0 < foot and s.y0 > foot - 200 then
			over = s
		end
	end
	-- (clear of RUN) a touch key in the chip's columns that its spot meets: the chip stands over the key instead, by the
	-- key's ink (look:chipB: its block's 3 px wood edge is drawn outside the button's box; by the box the chip's foot
	-- stood 5 px over RUN's ink at 320 x 568, not GUIDE_STACK)
	local keys = {}
	local pgK = playerGui()
	local mobile = pgK and pgK:FindFirstChild("MobileControls")
	if mobile and mobile:IsA("ScreenGui") and mobile.Enabled then
		for _, d in ipairs(mobile:GetDescendants()) do
			if d:IsA("GuiButton") and d.AbsoluteSize.X > 0 and shownIn(d, mobile) then
				local r = inkRect(d)
				for _, c in ipairs(d:GetDescendants()) do
					if c:IsA("GuiObject") and c.AbsoluteSize.X > 0 and shownIn(c, mobile) then
						local q = inkRect(c)
						r = { x0 = math.min(r.x0, q.x0), y0 = math.min(r.y0, q.y0), x1 = math.max(r.x1, q.x1), y1 = math.max(r.y1, q.y1) }
					end
				end
				keys[#keys + 1] = r
			end
		end
	end
	local function settle(f)
		local moved = true
		while moved do
			moved = false
			local y1 = f - K.GUIDE_STACK
			local y0 = y1 - h - 2 * e
			for _, r in ipairs(keys) do
				local ky0, ky1 = r.y0, r.y1
				if r.x0 < x + w + e + K.GUIDE_STACK and r.x1 > x - e - K.GUIDE_STACK and ky0 < y1 + K.GUIDE_STACK and ky1 > y0 - K.GUIDE_STACK and ky0 < f then
					f, moved = ky0, true
					break
				end
			end
		end
		return f
	end
	local under = foot
	foot = settle(over and over.y0 or foot)
	-- (look:chipB, 320 x 568 with the strip docked) no room over the strip under the menu column: the chip stood on its
	-- tiles and yielded its spot to them for the whole guide (spotClaimed). There it stands under the strip, at its own
	-- home over the name plank, when that is GUIDE_STACK clear of the strip; else over it as before
	if over then
		local pgM = playerGui()
		local menu = pgM and pgM:FindFirstChild("NimbusMenu")
		local col = menu and menu:FindFirstChild("MenuColumn", true)
		if col and col:IsA("GuiObject") and menu:IsA("ScreenGui") and col.AbsoluteSize.X > 1 and shownIn(col, menu) then
			local c, m = inkRect(col), K.GUIDE_PILL_GAP
			local y1 = foot - K.GUIDE_STACK
			local y0 = y1 - h - 2 * e
			if c.x0 < x + w + e + m and c.x1 > x - e - m and c.y0 < y1 + m and c.y1 > y0 - m then
				local f = settle(under)
				if f - K.GUIDE_STACK - h - 2 * e >= over.y1 + K.GUIDE_STACK then
					foot = f
				end
			end
		end
	end
	return x, foot - K.GUIDE_STACK - e - h
end

-- (Pitch 2 item 13 A; the pick's lines) the chip per phase: its mark's face and icon (the needle's arrows: guideNeedle),
-- the chip's lip, its two lines (`Info` with its widest reserve: the stud count's three digits), whether the X shows
local GUIDE_LOOK = {
	Walk = { Face = "Gold", Icon = "arrowup", Lip = "StoneLip", Close = true, Name = function(spec)
		return spec.Label
	end, Info = function(d, bar, short) -- (short: a ticket with no room for 'away', look:chipB major 3)
		return math.clamp(math.floor((d or 0) + 0.5), 0, 999) .. ((bar or short) and " studs" or " studs away")
	end, Reserve = function(bar, short)
		return (bar or short) and "888 studs" or "888 studs away"
	end },
	Home = { Face = "Gold", Icon = "house", Lip = "StoneLip", Close = true, Name = function()
		return "Home first"
	end, Info = function()
		return "then follow the arrow"
	end, Short = function() -- (a line that would run past the pill or the screen's gutters)
		return "then the arrow"
	end },
	Here = { Face = "Grass", Icon = "check", Lip = "GrassLip", Close = false, Name = function()
		return "You're here"
	end, Info = function()
		local CloudUI = mod("CloudUI")
		local ok, words = false, nil
		if CloudUI and type(CloudUI.PromptWords) == "function" then
			ok, words = pcall(CloudUI.PromptWords, false)
		end
		return (ok and type(words) == "string") and words or "press E"
	end },
}

-- the needle's sprite per sector (PixelIcon's own arrows) and the 45 degree sprite of a step between two of them
local NEEDLE_ICON = { ahead = "arrowup", right = "arrow", left = "left", behind = "arrowdown" }
local NEEDLE_STEP = {
	["ahead:right"] = "arrowne", ["ahead:left"] = "arrownw", ["right:behind"] = "arrowse", ["left:behind"] = "arrowsw",
}

-- a block's wood edge at `px` (whole screen px) and its lip at `lip` px
local function setBlockEdge(block, px, lip)
	local s = block:FindFirstChild("SignEdge")
	if s and s.Thickness ~= px then
		s.Thickness = px
		local crisp = mod("PixelCrisp")
		if crisp then
			crisp.Edge(s, px)
		end
	end
	local l = block:FindFirstChild("Lip")
	if l and lip and l.Size.Y.Offset ~= lip then
		l.Size = UDim2.new(1, 0, 0, lip)
	end
end

-- the mark's icon: re-hosted on its glyph (the attribute PixelIcon names it)
local function setMarkIcon(name)
	local glyph = G.glyph
	if glyph and G.sprite ~= name then
		G.sprite = name
		glyph:SetAttribute("PixelIcon", name)
		PixelIcon.Host(glyph, name, K.GUIDE_ICON)
	end
end

-- paints the chip for `phase` and lays it out in its form: the two-line ticket on a touch screen (the pill's height in
-- the band) and on a portrait phone (K.GUIDE_TICKET_H), the one-line bar (the 'NN studs' tag) on a PC; the place
-- (placeChip) is taken after it
local function paintChip(phase)
	local chip, look = G.chip, GUIDE_LOOK[phase]
	if not chip or not look then
		return
	end
	local ok, k = pcall(Theme.ScreenFactor)
	G.k = (ok and type(k) == "number" and k > 0) and k or 1
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	G.vp = vp
	G.portrait = vp.Y > vp.X
	local bar = not G.portrait and UserInputService.TouchEnabled ~= true
	local close = look.Close
	local name = look.Name(G.spec)
	local band = bandOf(vp.X)
	local pillH = pillRow(band)
	-- the sizes (screen px): the ticket's from the kit's design px at the screen factor, the bar's at the pill's own
	local e, h, lip, mk, pad, gap, ts, ss, tagged
	local function sizes()
		if bar then
			e, h, lip = K.GUIDE_BAR_EDGE, pillH, K.GUIDE_BAR_LIP
			mk, pad, gap = h - lip - 4, K.GUIDE_BAR_PAD, K.GUIDE_BAR_GAP
			ts, ss = K.GUIDE_BAR_NAME, K.GUIDE_BAR_INFO
		else
			e = (G.k < 1) and 2 or 3
			-- (a PC's ticket: a touch pill's height, as tall as the band allows: two lines want it)
			h = G.portrait and chipPx(K.GUIDE_TICKET_H) or math.max(pillH, math.min(K.GUIDE_PILL_TOUCH, band - 6))
			lip, mk, pad, gap = chipPx(K.GUIDE_LIP), chipPx(K.GUIDE_MARK), chipPx(K.GUIDE_PAD), chipPx(K.GUIDE_GAP)
			ts, ss = math.ceil(K.GUIDE_NAME * G.k - 1e-6), math.ceil(K.GUIDE_INFO * G.k - 1e-6)
		end
		-- (look:chipB minor 4) a PC's tag is the stud count's number cell: only the walk (a distance) wears it; Home /
		-- Here say their second line ('then follow the arrow', 'press E') as plain muted words after the name, as the
		-- ticket does
		tagged = bar and look.Reserve ~= nil
	end
	sizes()
	local function widthOf(info)
		local nw = math.ceil(textWidth(name, ts, "Heading"))
		local iw = math.ceil(textWidth(info, ss, "Heading"))
		if bar then
			local tagW = tagged and (iw + 2 * K.GUIDE_BAR_TAG_PAD) or iw
			return pad + mk + gap + nw + K.GUIDE_BAR_TAG_GAP + tagW + (close and (K.GUIDE_BAR_X_GAP + mk + pad) or K.GUIDE_BAR_X_GAP), nw, tagW
		end
		local tw = math.max(nw, iw)
		return pad + mk + gap + tw + (close and (gap + mk + pad) or gap), tw, 0
	end
	if look.Reserve and not G.distance then
		local root, part = rootPart(), guidePart()
		if root and part then
			G.distance = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z).Magnitude
		end
	end
	local info = look.Info(G.distance, bar, false)
	local reserve = look.Reserve and look.Reserve(bar, false) or info
	local w, tw, tagW = widthOf(reserve)
	if bar then
		-- (look:chipB, travel_guide_clear's walk at 844 x 390 with no touch, red from 816badd: the one-line bar reached in
		-- to x 450, over the gold arrow at x 487 - 516; B's case is the arrow's lane kept free) a PC screen whose bar would
		-- start left of K.GUIDE_BAR_LANE of its width (a small window) wears the phones' two-line ticket instead
		local _, right = bandOf(vp.X)
		if right - K.GUIDE_DOCK - w - K.GUIDE_BAR_EDGE < vp.X * K.GUIDE_BAR_LANE then
			bar = false
			sizes()
			info = look.Info(G.distance, bar, false)
			reserve = look.Reserve and look.Reserve(bar, false) or info
			w, tw, tagW = widthOf(reserve)
		end
	end
	local face = h - lip
	local short = false
	if look.Short or (look.Reserve and not bar) then
		-- (a line that runs past the pill, or past the screen's right gutter on a portrait phone) the short one: Home's
		-- 'then the arrow'; (look:chipB major 3: at 320 x 568 the ticket stood flush with a vitals card standing right of
		-- the menu, its ink 3 px from the screen's right edge, 7 px past the card) the walk's 'NN studs' (minor 3: the walk
		-- now reads the pill's room in the band too; the band holds it at every screen of the pick, 568 x 320 too)
		local pg = playerGui()
		local pillGui = pg and pg:FindFirstChild("NimbusTopBar")
		local pillRight = pillGui and tonumber(pillGui:GetAttribute("PillRight")) or 0
		local _, right = bandOf(vp.X)
		local room = right - K.GUIDE_DOCK - pillRight - 2 * e - K.GUIDE_PILL_GAP
		if G.portrait then
			room = vp.X - K.EDGE - chipHome(0, h, e)
		end
		if w + 2 * e > room then
			short = true
			info = look.Short and look.Short(G.spec) or look.Info(G.distance, bar, true)
			reserve = look.Reserve and look.Reserve(bar, true) or info
			w, tw, tagW = widthOf(reserve)
		end
	end
	G.look, G.bar, G.e, G.h, G.w, G.short = look, bar, e, h, w, short
	chip.Size = UDim2.fromOffset(w, h)
	setBlockEdge(chip, e, lip)
	local chipLip = chip:FindFirstChild("Lip")
	if chipLip then
		chipLip.BackgroundColor3 = SIGN[look.Lip] or SIGN.StoneLip
	end
	-- the mark (the needle, the house, the check) and its brass pin (Gemini's touch: the needle's pivot cell in gold)
	local my = math.floor((face - mk) / 2)
	local markFace = SIGN[look.Face] or SIGN.Gold
	G.mark.BackgroundColor3 = markFace
	G.mark.Position = UDim2.fromOffset(pad, my)
	G.mark.Size = UDim2.fromOffset(mk, mk)
	setBlockEdge(G.mark, 2, bar and 3 or chipPx(3))
	local markLip = G.mark:FindFirstChild("Lip")
	if markLip then
		markLip.BackgroundColor3 = Theme.SignLipOf(markFace)
	end
	local ix, iy = math.floor(mk / 2) - math.floor(K.GUIDE_ICON / 2), math.floor(mk / 2) - 1 - math.floor(K.GUIDE_ICON / 2)
	G.iconHolder.Position = UDim2.fromOffset(ix, iy)
	G.glyph.TextColor3 = (look.Face == "Grass") and SIGN.OnGrass or SIGN.Text
	G.pin.Position = UDim2.fromOffset(ix + 4 * K.GUIDE_ICON / 9, iy + 4 * K.GUIDE_ICON / 9)
	G.pin.Size = UDim2.fromOffset(K.GUIDE_ICON / 9, K.GUIDE_ICON / 9)
	if phase == "Walk" then
		G.needle = G.needle or "ahead"
		chip:SetAttribute("Needle", G.needle)
		setMarkIcon(G.stepIcon or NEEDLE_ICON[G.needle])
		G.pin.Visible = true
	else
		G.needle, G.stepIcon, G.stepTo, G.stepLeft = nil, nil, nil, nil
		chip:SetAttribute("Needle", nil)
		setMarkIcon(look.Icon)
		G.pin.Visible = false
	end
	-- the lines: the place over its distance (the ticket), or the place and its tag (the bar)
	local tx = pad + mk + gap
	G.place.TextSize = ts
	G.place.Text = name
	G.info.TextSize = ss
	G.info.Text = info
	G.info.TextColor3 = tagged and SIGN.Text or SIGN.TextMuted
	local lh, ih = ts + 4, ss + 4
	if bar and not tagged then
		-- (minor 4) Home / Here on a PC: the name, then its second line in plain muted words, no number cell
		G.place.Position = UDim2.fromOffset(tx, math.floor((face - lh) / 2))
		G.place.Size = UDim2.fromOffset(tw + 2, lh)
		G.tag.Visible = false
		G.info.Parent = chip
		G.info.TextXAlignment = Enum.TextXAlignment.Left
		G.info.Position = UDim2.fromOffset(tx + tw + K.GUIDE_BAR_TAG_GAP, math.floor((face - ih) / 2))
		G.info.Size = UDim2.fromOffset(tagW + 2, ih)
	elseif bar then
		G.place.Position = UDim2.fromOffset(tx, math.floor((face - lh) / 2))
		G.place.Size = UDim2.fromOffset(tw + 2, lh)
		local tagH = K.GUIDE_BAR_TAG_H
		G.tag.Visible = true
		G.tag.Position = UDim2.fromOffset(tx + tw + K.GUIDE_BAR_TAG_GAP, math.floor((face - tagH) / 2))
		G.tag.Size = UDim2.fromOffset(tagW, tagH)
		G.info.Parent = G.tag
		G.info.TextXAlignment = Enum.TextXAlignment.Center
		G.info.Position = UDim2.fromOffset(0, math.floor((tagH - ih) / 2))
		G.info.Size = UDim2.fromOffset(tagW, ih)
	else
		G.place.Position = UDim2.fromOffset(tx, math.floor(face * 0.30 - lh / 2 + 0.5))
		G.place.Size = UDim2.fromOffset(tw + 2, lh)
		G.tag.Visible = false
		G.info.Parent = chip
		G.info.TextXAlignment = Enum.TextXAlignment.Left
		G.info.Position = UDim2.fromOffset(tx, math.floor(face * 0.75 - ih / 2 + 0.5))
		G.info.Size = UDim2.fromOffset(tw + 2, ih)
	end
	-- the X: the red block (as big as the mark) in a transparent K.GUIDE_CLOSE px button round it
	local hit = K.GUIDE_CLOSE
	local inset = math.floor((hit - mk) / 2)
	local xx = w - pad - mk
	G.close.Visible = close
	G.close.Size = UDim2.fromOffset(hit, hit)
	G.close.Position = UDim2.fromOffset(xx - inset, my - inset)
	G.closeFace.Position = UDim2.fromOffset(inset, inset)
	G.closeFace.Size = UDim2.fromOffset(mk, mk)
	G.xIcon.Position = UDim2.fromOffset(ix, iy)
	setBlockEdge(G.closeFace, 2, bar and 3 or chipPx(3))
	local crisp = mod("PixelCrisp")
	if crisp and type(crisp.Refresh) == "function" then
		pcall(crisp.Refresh, chip)
	end
	G.home = nil
	G.placeTimer = 0
end

-- (look:chipB major 2, and the states the B pins had not met) the cards that take the chip's spot for a while, each
-- its ScreenGui and its part (its shown children counted: an invite card, a menu tile): a dungeon party's chip
-- (DungeonController's RunChip, a phone's party countdown with its window closed: "Starting in 24 - press READY" /
-- "Dungeon in 5...", from the pill to '...' in the band), an NPC's dialog (it reaches the band on a landscape phone, the
-- vitals stack on a portrait one), the arena's side card (a duel invite, the queue), and on a portrait phone a portal
-- party's panel with the menu column and the wallet strips it pushes down onto the vitals stack
local SPOT_CLAIMS = {
	{ "NimbusDungeonRun", "RunChip" },
	{ "NimbusNpcDialog", "NpcDialog" },
	{ "NimbusArenaSide", "SideStack" },
	{ "NimbusMenu", "MenuColumn" },
	{ "NimbusHud", "PartyPanel" },
	{ "NimbusHud", "Currency" },
	-- (an open Shop: at 960 x 540 its awning, seated over the window's top, reaches into the band 1 px under the chip)
	{ "NimbusShop", "ShopWindow" },
}
local SPOT_HOLD = 12 -- (no flicker) a yielded chip comes back only this far clear: the party chip is fitted to its words

-- where one of SPOT_CLAIMS would meet the chip's home (ink K.GUIDE_PILL_GAP px round: battle_hud_no_overlap's MIN_GAP)
-- the chip yields its spot - hidden, the guide still running (the arrow and the trail stay), back once the card goes. A
-- HUD state, never a camera move; each of these is the moment's word (a party about to start, a talk, an invite).
-- Was: drawn over the dungeon party's chip (13 over 12) until the run began, over the NPC's dialog, the invite card,
-- under the menu tiles a full portal party pushes down at 360 x 640
local function spotClaimed()
	local home = G.home
	if not (home and G.w and G.h and G.e) then
		return false
	end
	local pg = playerGui()
	if not pg then
		return false
	end
	local m = K.GUIDE_PILL_GAP + (G.yielded and SPOT_HOLD or 0)
	local x0, y0 = home.x - G.e - m, home.y - G.e - m
	local x1, y1 = home.x + G.w + G.e + m, home.y + G.h + G.e + m
	-- what a part draws, not its box (the arena's empty side stack is an 8 px transparent list across the vitals stack)
	local function draws(o)
		if o.BackgroundTransparency < 0.99 or o:FindFirstChildOfClass("UIStroke") then
			return true
		end
		if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.Image ~= "" and o.ImageTransparency < 0.99 then
			return true
		end
		return (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= "" and o.TextTransparency < 0.99
	end
	local function meets(obj)
		if not (obj:IsA("GuiObject") and obj.Visible) then
			return false
		end
		local r = inkRect(obj)
		local hit = r.x0 < x1 and x0 < r.x1 and r.y0 < y1 and y0 < r.y1
		if hit and obj.AbsoluteSize.X > 1 and obj.AbsoluteSize.Y > 1 and draws(obj) then
			return true
		end
		if obj.ClipsDescendants and not hit then
			return false -- (its children are cut to its box: a window's scrolling page is not walked)
		end
		for _, c in ipairs(obj:GetChildren()) do
			if meets(c) then
				return true
			end
		end
		return false
	end
	G.claimRefs = G.claimRefs or {}
	for i, claim in ipairs(SPOT_CLAIMS) do
		local gui = pg:FindFirstChild(claim[1])
		local obj = G.claimRefs[i]
		if not (obj and gui and obj:IsDescendantOf(gui)) then
			obj = gui and gui:FindFirstChild(claim[2], true)
			G.claimRefs[i] = obj
		end
		if obj and obj:IsA("GuiObject") and gui:IsA("ScreenGui") and shownIn(obj, gui) and meets(obj) then
			return true
		end
	end
	return false
end

-- (the owner's pick of 2026-11-24 for PORTRAIT phones, "steps aside for signs"; look:chipB: with the tutorial's strip
-- docked the chip stood under the gate's 'TAP Enter' plank, its X on the plank, and a camera tilt or an NPC's 'Talk'
-- brought a plank onto it) a world sign - the kit's prompt planks, PromptController's PromptCard billboards in the
-- PlayerGui: the gate's 'TAP Enter', an NPC's 'Talk', any that shows - standing within GUIDE_SIGN_KEEP px of the chip's spot
-- (its ink and its X's GUIDE_CLOSE px target, where it is drawn) takes the spot, as a card does (spotClaimed): the chip
-- hides, its X with it (a tap on the sign never cancels the guide), the guide still running. Read every
-- GUIDE_NEEDLE_STEP s; back only once its spot has been SPOT_HOLD px clear of every sign for GUIDE_SIGN_DWELL s on end
-- (no flicker: the owner's pick of 2026-11-25, was no sooner than that after it stepped aside), in the same place: it
-- never moves to dodge. A sign the camera carries is kept off by twice its move since the last read more (where it is by the next read: it never reaches the chip between two reads). Landscape screens and
-- a PC keep the band as they are: never aside there

-- a shown prompt plank's rect on the screen (viewport px: the chip's ScreenGui ignores the inset) as the engine draws a
-- pixel billboard: its adornee's point, StudsOffsetWorldSpace and StudsOffset (the camera's axes), Size px round it
local function signRect(cam, card)
	local ad = card.Adornee
	if not (card.Enabled and ad) then
		return nil
	end
	local p = nil
	if ad:IsA("BasePart") then
		p = ad.Position
	elseif ad:IsA("Attachment") then
		p = ad.WorldPosition
	else
		return nil
	end
	local cf = cam.CFrame
	local so = card.StudsOffset
	p = p + card.StudsOffsetWorldSpace + cf.RightVector * so.X + cf.UpVector * so.Y - cf.LookVector * so.Z
	if card.MaxDistance > 0 and (p - cf.Position).Magnitude > card.MaxDistance then
		return nil
	end
	local v = cam:WorldToViewportPoint(p)
	if v.Z <= 0 then
		return nil
	end
	local w, h = card.Size.X.Offset, card.Size.Y.Offset
	local x0 = v.X - w / 2 + card.SizeOffset.X * w
	local y0 = v.Y - h / 2 - card.SizeOffset.Y * h
	return { x0 = x0, y0 = y0, x1 = x0 + w, y1 = y0 + h }
end

-- each shown plank on the screen now -> { [card] = rect }
local function signsNow()
	local out = {}
	local pg, cam = playerGui(), Workspace.CurrentCamera
	if not (pg and cam) then
		return out
	end
	for _, c in ipairs(pg:GetChildren()) do
		if c.Name == "PromptCard" and c:IsA("BillboardGui") then
			local ok, r = pcall(signRect, cam, c)
			if ok and r then
				out[c] = r
			end
		end
	end
	return out
end

-- (at the timed read) each plank's move since the last read: the margin a sign the camera carries is kept off by
local function trackSigns()
	if not G.portrait then
		G.signSeen = nil
		return
	end
	local seen = signsNow()
	for c, r in pairs(seen) do
		local last = G.signSeen and G.signSeen[c]
		r.move = last and math.max(math.abs(r.x0 - last.x0), math.abs(r.y0 - last.y0)) or 0
	end
	G.signSeen = seen
end

-- whether the chip stands aside for a sign now (a portrait screen): one within the keep of its spot where it is drawn,
-- or, once aside, its spot clear of every sign for less than GUIDE_SIGN_DWELL s
local function asideWanted()
	if not (G.portrait and G.home and G.w and G.h and G.e) then
		return false
	end
	local lift = math.floor((G.slide or 0) * (G.h + 2 * G.e) + 0.5)
	local x, y = G.home.x, G.home.y - lift
	local s = { x0 = x - G.e, y0 = y - G.e, x1 = x + G.w + G.e, y1 = y + G.h + G.e }
	local close = G.close
	if close and close.Visible then
		local p, z = close.Position, close.Size
		s.x0, s.y0 = math.min(s.x0, x + p.X.Offset), math.min(s.y0, y + p.Y.Offset)
		s.x1, s.y1 = math.max(s.x1, x + p.X.Offset + z.X.Offset), math.max(s.y1, y + p.Y.Offset + z.Y.Offset)
	end
	local keep = K.GUIDE_SIGN_KEEP + (G.aside and SPOT_HOLD or 0)
	for c, r in pairs(signsNow()) do
		local last = G.signSeen and G.signSeen[c]
		local m = keep + 2 * (last and last.move or 0)
		if r.x0 < s.x1 + m and s.x0 - m < r.x1 and r.y0 < s.y1 + m and s.y0 - m < r.y1 then
			G.signAt = S.clock -- (the owner's pick of 2026-11-25) the spot's last read with a sign on it
			return true
		end
	end
	-- (the owner's pick of 2026-11-25; look:portrait: counted from when it hid, a sign that left for a moment - a jump,
	-- a quick tilt - let it back for 0.07 - 0.2 s) back only once the spot has been clear for the hold on end
	return G.aside == true and S.clock - (G.signAt or 0) < K.GUIDE_SIGN_DWELL - 1e-6
end

-- the chip at its home (read again every K.LAYOUT_EVERY s, never on a camera move); the "You're here" slide lifts it
local function placeChip()
	local chip = G.chip
	if not (chip and G.w) then
		return
	end
	local x, y = chipHome(G.w, G.h, G.e)
	G.home = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
	G.yielded = spotClaimed()
	local aside = asideWanted()
	if aside ~= (G.aside == true) then
		G.aside = aside
	end
	local lift = math.floor((G.slide or 0) * (G.h + 2 * G.e) + 0.5)
	chip.Position = UDim2.fromOffset(G.home.x, G.home.y - lift)
	chip.Visible = (G.slide or 0) < 1 and not G.yielded and not G.aside
end

local function buildChip()
	local pg = playerGui()
	if not pg then
		return false
	end
	local gui = make("ScreenGui", "NimbusGuide", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = K.GUIDE_ORDER,
	}, nil)
	local chip = box("Chip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Stone,
		Size = UDim2.fromOffset(200, 48),
		ZIndex = 2,
	}, gui)
	edge(chip, SIGN.Wood, 2)
	lipOf(chip, SIGN.StoneLip, 4)
	local mark = box("Mark", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Gold,
		Size = UDim2.fromOffset(27, 27),
		ZIndex = 3,
	}, chip)
	edge(mark, SIGN.Wood, 2)
	lipOf(mark, SIGN.GoldLip, 2)
	local holder, glyph = crispIcon(mark, "arrowup", K.GUIDE_ICON, SIGN.Text, {
		Name = "Icon",
		ZIndex = 5,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(4, 3),
	})
	G.iconHolder, G.glyph, G.sprite = holder, glyph, "arrowup"
	G.pin = box("Pin", { BackgroundTransparency = 0, BackgroundColor3 = SIGN.Gold, ZIndex = 6 }, mark)
	local function line(nm)
		return label(chip, nm, "", "Heading", 18, SIGN.Text, {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextScaled = false,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.None,
			ZIndex = 4,
		})
	end
	G.place = line("Place")
	G.info = line("Info")
	-- (the bar) the stud count's tag: the vitals card's own number cell, a Well face in its WellEdge line
	local tag = box("Tag", { BackgroundTransparency = 0, BackgroundColor3 = SIGN.WellEdge, ZIndex = 3, Visible = false }, chip)
	box("Face", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Well,
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		ZIndex = 3,
	}, tag)
	G.tag = tag
	local close = make("TextButton", "Close", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, chip)
	local closeFace = box("Face", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Red,
		ZIndex = 4,
		Active = false,
	}, close)
	edge(closeFace, SIGN.Wood, 2)
	lipOf(closeFace, SIGN.RedLip, 2)
	G.xIcon = crispIcon(closeFace, "x", K.GUIDE_ICON, SIGN.Text, {
		Name = "Icon",
		ZIndex = 5,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(4, 3),
	})
	close.Activated:Connect(function()
		Guide.Stop()
	end)
	G.gui, G.chip, G.mark, G.close, G.closeFace = gui, chip, mark, close, closeFace
	gui.Parent = pg
	return true
end

function Guide.Stop()
	local was = G.active
	G.active = false
	G.phase, G.id, G.spec, G.target, G.part = nil, nil, nil, nil, nil
	G.slide, G.hereUntil, G.placeTimer, G.home, G.distance, G.distTimer, G.yielded = nil, nil, nil, nil, nil, nil, nil
	G.claimTimer, G.claimRefs, G.aside, G.signSeen, G.signAt = nil, nil, nil, nil, nil
	G.needle, G.stepIcon, G.stepTo, G.stepLeft, G.sprite = nil, nil, nil, nil, nil
	G.look, G.bar, G.e, G.h, G.w, G.k, G.vp, G.portrait, G.short = nil, nil, nil, nil, nil, nil, nil, nil, nil
	if G.gui then
		G.gui:Destroy()
	end
	G.gui, G.chip, G.mark, G.close, G.closeFace, G.place, G.info, G.tag = nil, nil, nil, nil, nil, nil, nil, nil
	G.iconHolder, G.glyph, G.pin, G.xIcon = nil, nil, nil, nil
	-- (the tutorial's own guide keeps its two-line sign)
	setSignShown(true, false)
	if was then
		-- the world guide and the pointer go with it (the tutorial's own target, if any, comes back on its next frame)
		setWorldActive(false)
		W.key = nil
		hidePointer()
		M.findTimer = 0
	end
end

local function setPhase(phase)
	if G.phase == phase then
		return
	end
	G.phase = phase
	W.key = nil
	M.findTimer = 0
	safe("guide chip", paintChip, phase)
	safe("guide chip", placeChip)
end

-- the distance the chip shows (straight to the gate, on the ground: one measure from the first frame, so standing still
-- it never changes), read every K.GUIDE_READ_EVERY s; the chip's width already holds three digits, so a new number never
-- moves it
local function readDistance(dt)
	G.distTimer = (G.distTimer or 0) - dt
	if G.distTimer > 0 then
		return
	end
	G.distTimer = K.GUIDE_READ_EVERY
	local root = rootPart()
	local part = guidePart()
	local d = nil
	if root and part then
		d = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z).Magnitude
	end
	G.distance = d
	if G.phase == "Walk" and G.info and G.look then
		local text = G.look.Info(d, G.bar, G.short)
		if G.info.Text ~= text then
			G.info.Text = text
		end
	end
end

-- one frame of the travel guide (TutorialController.Step, before the pointer and the world guide)
local function updateTravel(dt)
	if not G.active then
		return
	end
	if guideBlocked() then
		Guide.Stop()
		return
	end
	-- (the pick) the GuideSign is retired while the travel guide runs: its words are the chip's (a world guide built
	-- again after the start is hidden too)
	if W.labelGui and W.labelGui.Enabled then
		setSignShown(false)
	end
	-- (major 2) a card coming to or going from the chip's spot (spotClaimed), and (the owner's portrait pick of 2026-11-24)
	-- a sign: read at the kit's step, 1/15 s
	G.claimTimer = (G.claimTimer or 0) - dt
	if G.home and G.claimTimer <= 0 then
		G.claimTimer = K.GUIDE_NEEDLE_STEP
		safe("guide signs", trackSigns)
		local okB, claimed = pcall(spotClaimed)
		local okS, aside = pcall(asideWanted)
		if (okB and (claimed == true) ~= (G.yielded == true)) or (okS and (aside == true) ~= (G.aside == true)) then
			safe("guide chip", placeChip)
		end
	end
	if G.phase == "Here" then
		local left = (G.hereUntil or 0) - S.clock
		local slide = 0
		if left <= K.GUIDE_SLIDE / 2 then
			slide = 1
		elseif left <= K.GUIDE_SLIDE then
			slide = 0.5
		end
		if slide ~= (G.slide or 0) then
			G.slide = slide
			safe("guide chip", placeChip)
		end
		if left <= 0 then
			Guide.Stop()
		end
		return
	end
	local root = rootPart()
	local pos = root and root.Position
	if pos and G.id == "StormAltar" and type(Config.AtAltar) == "function" and Config.AtAltar(pos) == true then
		Guide.Stop() -- already through the gate: the altar's own prompts take over
		return
	end
	if pos and inLobbyWorld(pos) then
		local part = guidePart()
		local d = part and Vector3.new(part.Position.X - pos.X, 0, part.Position.Z - pos.Z).Magnitude
		if d and d <= K.GUIDE_ARRIVE then
			G.hereUntil = S.clock + K.GUIDE_HERE
			G.slide = 0
			setPhase("Here")
			return
		end
		setPhase("Walk")
	elseif pos then
		setPhase("Home")
	end
	safe("guide distance", readDistance, dt)
	G.placeTimer = (G.placeTimer or 0) - dt
	if G.placeTimer <= 0 then
		G.placeTimer = K.LAYOUT_EVERY
		-- a new screen size (a turned phone) repaints the chip in its form; else its home follows the HUD
		local okK, k = pcall(Theme.ScreenFactor)
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize
		if (okK and k ~= G.k) or (vp and G.vp and vp ~= G.vp) then
			safe("guide chip", paintChip, G.phase)
		end
		safe("guide chip", placeChip)
	end
end

-- (the pick, the needle) where the gate is, read every frame after the world guide (its arrow's hop this frame): the
-- needle rests on 'ahead' while the gate or its arrow is on the screen (8 px in); off it, the sector of the gate's
-- bearing from the camera (ahead within the screen's half width, right / left, behind from K.GUIDE_BEHIND degrees), a
-- new sector taken only K.GUIDE_HOLD_DEG degrees past its edge (no chatter there). A change shows the 45 degree sprite
-- between for K.GUIDE_NEEDLE_STEP s, then the new one: two hard steps, no tween, never a turned frame
local function guideNeedle(dt)
	if not (G.active and G.phase == "Walk" and G.chip and G.needle) then
		return
	end
	if G.stepTo then
		G.stepLeft = (G.stepLeft or 0) - dt
		if G.stepLeft <= 1e-6 then
			G.stepIcon, G.stepTo = nil, nil
			setMarkIcon(NEEDLE_ICON[G.needle])
		end
	end
	local cam = Workspace.CurrentCamera
	local part = guidePart()
	if not (cam and part) then
		return
	end
	local vp = cam.ViewportSize
	local function onScreen(p)
		local ok, v = pcall(cam.WorldToViewportPoint, cam, p)
		return ok and typeof(v) == "Vector3" and v.Z > 0 and v.X >= 8 and v.X <= vp.X - 8 and v.Y >= 8 and v.Y <= vp.Y - 8
	end
	local want = nil
	local on = onScreen(part.Position)
	if not on and W.active and W.arrowParts and #W.arrowParts > 0 then
		local mid = Vector3.new()
		for _, p in ipairs(W.arrowParts) do
			mid = mid + p.Position
		end
		on = onScreen(mid / #W.arrowParts)
	end
	local prev = G.needle
	-- (look:chipB minor 6) the gate's bearing on the ground: the camera's heading, its pitch left out (in camera space a
	-- steep look up or down swelled a small turn: 9 degrees off read 48 at a 72 degree look up, the needle 'right' with the
	-- gate ahead, and a gate under the view could read 'behind'). A camera looking straight up or down takes its heading
	-- from the screen's up (down: ahead; up: behind)
	local function flat()
		local cf = cam.CFrame
		local look = cf.LookVector
		local fwd = Vector3.new(look.X, 0, look.Z)
		if fwd.Magnitude < 0.05 then
			local up = cf.UpVector
			fwd = Vector3.new(up.X, 0, up.Z) * ((look.Y < 0) and 1 or -1)
		end
		if fwd.Magnitude < 1e-6 then
			return 0, -1
		end
		fwd = fwd.Unit
		local to = part.Position - cf.Position
		-- (x: right of the heading, z: -ahead, as in camera space)
		return to.X * -fwd.Z + to.Z * fwd.X, -(to.X * fwd.X + to.Z * fwd.Z)
	end
	if on then
		want = "ahead"
	else
		local vx, vz = flat()
		local v = { X = vx, Z = vz }
		local b = math.deg(math.atan2(v.X, -v.Z))
		local ab = math.abs(b)
		local half = math.deg(math.atan(math.tan(math.rad(cam.FieldOfView / 2)) * vp.X / math.max(1, vp.Y)))
		local hold = K.GUIDE_HOLD_DEG
		local side = (b > 0) and "right" or "left"
		local function sector(aheadTo, behindFrom)
			if ab >= behindFrom then
				return "behind"
			elseif ab > aheadTo then
				return side
			end
			return "ahead"
		end
		want = sector(half, K.GUIDE_BEHIND)
		if want ~= prev then
			-- (the hold) the sector it holds keeps it until the bearing is K.GUIDE_HOLD_DEG past that sector's edge
			local held = sector(prev == "ahead" and half + hold or half - hold, prev == "behind" and K.GUIDE_BEHIND - hold or K.GUIDE_BEHIND + hold)
			if held == prev then
				want = prev
			end
		end
	end
	if want and want ~= prev then
		G.needle = want
		G.chip:SetAttribute("Needle", want)
		local step = NEEDLE_STEP[prev .. ":" .. want] or NEEDLE_STEP[want .. ":" .. prev]
		if not step then
			-- (a half turn: the side the gate went round; right <-> left: over the way it went, ahead or behind)
			local vx, vz = flat()
			if (prev == "ahead" and want == "behind") or (prev == "behind" and want == "ahead") then
				step = NEEDLE_ICON[(vx > 0) and "right" or "left"]
			else
				step = NEEDLE_ICON[(vz < 0) and "ahead" or "behind"]
			end
		end
		G.stepIcon, G.stepTo, G.stepLeft = step, want, K.GUIDE_NEEDLE_STEP
		setMarkIcon(step)
	end
end

function Guide.Start(id)
	local spec = GUIDE_TARGETS[id]
	if not spec or guideBlocked() then
		return false
	end
	-- a second start replaces the first: the running guide's chip is kept (repainted, no second chip) and its state reset
	local keep = G.active and G.gui ~= nil and G.gui.Parent ~= nil
	if not keep then
		Guide.Stop()
	end
	G.active, G.id, G.spec = true, id, spec
	G.target = { Kind = spec.Kind, Id = spec.Id, Label = spec.Label, Prompt = spec.Prompt }
	G.phase, G.part, G.slide, G.hereUntil = nil, nil, nil, nil
	W.key = nil
	G.needle, G.stepIcon, G.stepTo, G.stepLeft, G.distance, G.distTimer = nil, nil, nil, nil, nil, nil
	if not keep then
		local ok, built = pcall(buildChip)
		if not (ok and built) then
			Guide.Stop()
			return false
		end
	end
	local root = rootPart()
	setPhase((root and inLobbyWorld(root.Position)) and "Walk" or "Home")
	updateTravel(0)
	ensureLoop()
	return G.active == true
end

function Guide.Active()
	return G.active and G.id or nil
end

function Guide.Phase()
	return G.active and G.phase or nil
end

local function applyState(payload)
	if type(payload) ~= "table" or not UI.Root then
		return
	end
	local prev = S.state
	local st = sanitize(payload)
	S.state = st
	if st.Done then
		if st.Completed and prev and not prev.Done and not S.finale then
			-- just finished: a last word from Nimbus, a big burst, then the card leaves
			S.finaleUntil = S.clock + K.FINALE_SECONDS
			renderFinale(st.Reward)
			if not S.shown then
				setPanelShown(true)
			end
			celebrate(true)
		elseif not S.finale then
			setPanelShown(false)
		end
		ensureLoop()
		return
	end
	if S.finale then
		-- a tutorial running again after the finale (the developer tools' restart): the card and the guide come back
		S.finale = false
		S.finaleUntil = nil
	end
	local changed = not prev or prev.Done or prev.Id ~= st.Id or prev.Step ~= st.Step or prev.Text ~= st.Text
	if changed then
		local advanced = prev ~= nil and not prev.Done and st.Step > prev.Step
		if S.manual == "collapsed" then
			S.manual = nil -- new words from Nimbus unfold the card again (an expanded card stays expanded)
		end
		renderStep()
		if advanced then
			celebrate(false)
		end
		if R.checkOpenWindows then
			task.defer(R.checkOpenWindows)
		end
	else
		UI.Hint.Text = hintText()
	end
	if not prev then
		S.showAfter = S.clock + K.FIRST_SHOW_DELAY
	end
	W.key = nil -- re-resolve the world target (the position may have arrived)
	M.findTimer = 0
	ensureLoop()
end

-- where each covering window (Cover.WINDOWS) draws: its ScreenGui; of NimbusMenu (it holds the menu column too) only the
-- Window_ frames, of NimbusDungeonRun (its run card) only the party's chip
Cover.GUIS = {
	{ "NimbusMenu", Prefix = "Window_" }, { "NimbusPets" }, { "NimbusShop" }, { "NimbusHatch" }, { "NimbusIndex" },
	{ "NimbusDaily" }, { "NimbusNpcDialog" }, { "NimbusDungeonRun", Part = "RunChip" }, { "NimbusArena" }, { "NimbusDungeon" },
	{ "NimbusCare" }, { "NimbusTrain" }, { "NimbusFusion" }, { "NimbusTrove" }, { "NimbusRaidGate" }, { "NimbusObby" },
	{ "NimbusLoss" }, { "NimbusPetPicker" },
}

-- what a part draws, not its box (as spotClaimed reads it: a window's holder is a transparent frame over the screen)
function Cover.drawn(o)
	if o.BackgroundTransparency < 0.99 or o:FindFirstChildOfClass("UIStroke") then
		return true
	end
	if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.Image ~= "" and o.ImageTransparency < 0.99 then
		return true
	end
	return (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= "" and o.TextTransparency < 0.99
end

-- true when `obj` (shown) or a shown part under it draws ink meeting `box` (screen px; a clipping part's children are cut
-- to its box, so one clear of `box` is not walked)
function Cover.meets(obj, box)
	if not (obj:IsA("GuiObject") and obj.Visible) then
		return false
	end
	local r = inkRect(obj)
	local hit = r.x0 < box.x1 and box.x0 < r.x1 and r.y0 < box.y1 and box.y0 < r.y1
	if hit and obj.AbsoluteSize.X > 1 and obj.AbsoluteSize.Y > 1 and Cover.drawn(obj) then
		return true
	end
	if obj.ClipsDescendants and not hit then
		return false
	end
	for _, c in ipairs(obj:GetChildren()) do
		if Cover.meets(c, box) then
			return true
		end
	end
	return false
end

-- the guide's ink where it rests (the card with its name plank and portrait, or the strip; the slide's offset taken off,
-- so its slide-in reads as its place), screen px; nil while it is not up
function Cover.guideInk()
	local slide, root = UI.Slide, UI.Root
	if not (slide and root and root.Visible) then
		return nil
	end
	local box = nil
	local function walk(o)
		for _, c in ipairs(o:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible then
				if c.AbsoluteSize.X > 1 and c.AbsoluteSize.Y > 1 and Cover.drawn(c) then
					local r = inkRect(c)
					box = box and { x0 = math.min(box.x0, r.x0), y0 = math.min(box.y0, r.y0), x1 = math.max(box.x1, r.x1), y1 = math.max(box.y1, r.y1) } or r
				end
				walk(c)
			end
		end
	end
	walk(slide)
	if not box then
		return nil
	end
	local dx = slide.Position.X.Offset * math.max(0.01, UI.Scale.Scale)
	return { x0 = box.x0 - dx, y0 = box.y0, x1 = box.x1 - dx, y1 = box.y1 }
end

-- a covering window's ink meets the guide's (the strip beside the docked Ring window at 1920 x 1080 stays; the Ring window
-- over the strip at 667 x 375, or the Pets window over its right end at 1920 x 1080, does not)
function Cover.underWindow()
	local pg = playerGui()
	local box = pg and Cover.guideInk()
	if not box then
		return false
	end
	for _, spec in ipairs(Cover.GUIS) do
		local gui = pg:FindFirstChild(spec[1])
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			if spec.Part then
				local part = gui:FindFirstChild(spec.Part, true)
				if part and part:IsA("GuiObject") and shownIn(part, gui) and Cover.meets(part, box) then
					return true
				end
			else
				for _, c in ipairs(gui:GetChildren()) do
					if (not spec.Prefix or c.Name:sub(1, #spec.Prefix) == spec.Prefix) and Cover.meets(c, box) then
						return true
					end
				end
			end
		end
	end
	return false
end

-- One frame of every tutorial visual (RenderStepped). Public so tests can drive it.
function TutorialController.Step(dt)
	dt = math.min(tonumber(dt) or 0, 0.25)
	S.clock = S.clock + dt
	local t = S.clock

	S.layoutTimer = S.layoutTimer + dt
	if S.layoutTimer >= K.LAYOUT_EVERY then
		S.layoutTimer = 0
		safe("layout", layout)
	end
	if S.finale and S.clock >= (S.finaleUntil or 0) and S.shown then
		setPanelShown(false)
	end
	local wanted = panelWanted()
	if wanted ~= (S.shown == true) then
		setPanelShown(wanted)
	end
	-- a window on top (menu window, odds, roulette stage, Pet Index): fold the card into the bubble and hide the
	-- menu pointer until it closes
	local covered = false
	if S.shown then
		local ok, open = pcall(windowCovering)
		covered = ok and open == true
	end
	if covered ~= (S.windowOpen == true) then
		S.windowOpen = covered
		S.coverRead = 0
		safe("layout", layout)
	end
	-- (2026-11-28 playtest C17: the Shop left 'Pick a B' of the folded strip showing, its '5/21' under the window) the
	-- folded guide steps out of sight while a covering window's ink meets its own (Cover.underWindow; C17 review: hidden
	-- under every window, it also went where nothing lay over it, as the Gifts window and an NPC's dialog at 1920 x 1080), read
	-- every COVER_EVERY s and at once when a window comes or goes. Written only while the panel shows (C17 review: a guide
	-- sent away under a window popped back in for its slide-out); the slide-out's end makes it whole again
	if S.shown and UI.Slide then
		S.coverRead = (S.coverRead or 0) - dt
		if S.coverRead <= 0 then
			S.coverRead = K.COVER_EVERY
			local ok, under = true, false
			if covered then
				ok, under = pcall(Cover.underWindow)
			end
			local hide = ok and under == true
			if UI.Slide.Visible == hide then
				UI.Slide.Visible = not hide
			end
		end
	end
	if S.shown then
		safe("typewriter", updateTypewriter, dt)
		-- the portrait animates whenever the panel shows: the folded bubble IS UI.Portrait, so it keeps flapping there
		-- too (at PORTRAIT_FOLDED_STEP; bug batch 2 #23: it froze while folded)
		safe("portrait", updatePortrait, dt, t)
		S.hintTimer = S.hintTimer - dt
		if S.hintTimer <= 0 then
			S.hintTimer = 0.25
			if UI.Hint.Visible then
				UI.Hint.Text = hintText()
			end
			if (S.nextLockUntil or 0) > 0 and os.clock() >= S.nextLockUntil then
				S.nextLockUntil = 0
				setDisabled(UI.Next, false)
			end
			if (S.skipLockUntil or 0) > 0 and os.clock() >= S.skipLockUntil then
				S.skipLockUntil = 0
				setDisabled(UI.ConfirmYes, false)
			end
			-- the current step's block breathes
			local st = S.state
			local face = st and not S.finale and currentProgressFace()
			if face then
				face.BackgroundTransparency = (math.sin(t * 6) + 1) * 0.2
			end
		end
	end
	safe("travel guide", updateTravel, dt)
	safe("menu pointer", updateMenuPointer, dt, t)
	safe("world guide", updateWorldGuide, dt, t)
	safe("guide needle", guideNeedle, dt)
	safe("confetti", updateConfetti, dt)

	-- nothing left to show: stop the loop until the next state (or the next travel guide)
	local st = S.state
	if st and st.Done and not S.shown and Fx.live <= 0 and not W.active and not G.active and R.loop then
		R.loop:Disconnect()
		R.loop = nil
		hidePointer()
	end
end

function TutorialController.GetState()
	return S.state
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
-- { module, signal, fixed window id (nil: the signal passes the window id) }
local WINDOW_SIGNALS = {
	{ "MenuController", "WindowOpened", nil },
	{ "IndexController", "WindowOpened", nil },
	{ "IndexController", "Opened", "Index" },
}

local function hookWindowSignals()
	for _, spec in ipairs(WINDOW_SIGNALS) do
		local key = spec[1] .. "." .. spec[2]
		if not R.hooked[key] then
			local m = mod(spec[1])
			local signal = m and m[spec[2]]
			if type(signal) == "table" and type(signal.Connect) == "function" then
				R.hooked[key] = true
				local fixed = spec[3]
				signal:Connect(function(windowId)
					onWindowOpened(fixed or windowId)
				end)
			end
		end
	end
	local indexHooked = R.hooked["IndexController.Opened"] or R.hooked["IndexController.WindowOpened"] or not mod("IndexController")
	return R.hooked["MenuController.WindowOpened"] == true and indexHooked == true
end

-- A window the step asks for may already be open when the step begins.
local function checkOpenWindows()
	local st = S.state
	if st and not st.Done and st.CompleteOn == "IndexOpened" then
		local IndexController = mod("IndexController")
		if IndexController and type(IndexController.IsOpen) == "function" then
			local ok, open = pcall(IndexController.IsOpen)
			if ok and open == true then
				onWindowOpened("Index")
			end
		end
	end
end

function TutorialController.Init()
	if R.initialized then
		return
	end
	R.initialized = true
	R.checkOpenWindows = function()
		safe("open windows", checkOpenWindows)
	end
	if not LocalPlayer then
		return
	end
	local okBuild, err = pcall(function()
		buildPanel()
		buildPointer()
	end)
	if not okBuild then
		warn("[TutorialController] could not build the panel: " .. tostring(err))
		return
	end
	safe("layout", layout)

	-- screen changes re-flow the panel right away
	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				safe("layout", layout)
			end)
		end
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
		M.findTimer = 0
		W.key = nil
		if inMatch() then
			-- a card opened in the lobby must not follow the player into the climb (it would cover the HP card):
			-- every match starts with Nimbus' automatic choice
			S.manual = nil
		end
		safe("layout", layout)
	end)

	task.spawn(function()
		-- Phase 5 (7.2): the main menu comes first. No panel, arrow or menu pointer before PLAY (or 600 s); the state
		-- the server pushed meanwhile is asked for again with "Sync" below
		local gate = loadModule(Client, "UiGate")
		if gate and type(gate.WaitForPlay) == "function" then
			pcall(gate.WaitForPlay, 600)
		end
		R.event = getRemote("TutorialEvent")
		local stateRemote = getRemote("TutorialState")
		if stateRemote then
			stateRemote.OnClientEvent:Connect(function(payload)
				safe("state", applyState, payload)
			end)
		else
			warnOnce("remote", "TutorialState remote missing: tutorial panel disabled")
			return
		end
		local openPanel = getRemote("OpenPanel")
		if openPanel then
			openPanel.OnClientEvent:Connect(function(panelId)
				onWindowOpened(panelId)
			end)
		end
		-- ask for the state (the join-time push may have arrived before we listened)
		fireEvent("Sync")
		for _, pause in ipairs({ 2, 4, 8, 15 }) do
			task.wait(pause)
			if S.state then
				break
			end
			R.last.Sync = nil
			fireEvent("Sync")
		end
	end)

	-- the portrait model (first sculpt can take a moment) and the window signals of the menu
	task.defer(function()
		safe("portrait", setupPortraitModel)
	end)
	task.spawn(function()
		for _ = 1, 30 do
			local ok, done = pcall(hookWindowSignals)
			if ok and done then
				break
			end
			task.wait(2)
		end
	end)
end

return TutorialController
