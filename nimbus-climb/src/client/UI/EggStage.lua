-- EggStage (client UI; lobby-shop Tasks 20 / 27, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.4 "The
-- egg-opening cutscene" and 5.5 "The egg stage"): the stage every roulette spin plays through. The one BuyRoulette request
-- path, the RouletteResult listener and its queue, and the seven phases dressed as storyboard A "Pedestal" (the owner's
-- pick, .superpowers/lobby-shop/pitch/CUTSCENE_PICK.md, with Gemini's cloud ring): the world dims (a navy Dim, four
-- vignette edges, HatchFx.Dim's blur and "Hatch" tint on High), the machine's name slides down, the server's strip
-- scrolls with speed streaks, the landed egg rises out of it onto a cloud-stone pedestal in a spot light with its rarity
-- backlight and a turning cloud ring, cracks glow and light leaks as it shakes (the push-in: its UIScale to 1.06), then
-- bursts (halves, the shock ring, the rays, the sparks, the ring's swell in the rarity colour, a white or gold flash) and
-- the pet pops on the pedestal under its banner (Legendary and up keep slow gold rays, Mythic / Secret confetti, Secret
-- a starry backdrop and a violet aura). The effects are client/UI/HatchFx; ShopController calls Init (Task 22).
-- Sounds: the owner's egg keys (Config.Audio Egg*), each playing Config.Audio.Fallback (today's roulette sounds, or
-- nothing) while its id is 0.
-- (egg-3d, spec 16.14) an x1 roll's hero egg is the real Blender egg (client/UI/Egg3D: a ViewportFrame "Egg3D" in the
-- Egg1 frame, attribute Egg3D = its key) when its key is usable here on High graphics: it turns slowly over the rise,
-- settles as it cracks, rocks in 3D with the shakes and, when its two halves' keys are usable too, splits into them at
-- the burst (the frame moves into Halves1, attribute Split3D) and they fly apart; else today's 2D halves. No id, Low
-- graphics, a phone with a 3D egg already showing or a failed Assemble: today's 2D egg exactly. x3 keeps 2D eggs.
-- (roll-look, spec 16.15 "Roll look A+B") the dressed roll and opening (client/UI/HatchLook builds the pieces): the HUD
-- hides, glossy strip cards under a gold window with B's colour tell, an overshoot and a land pop (Task 1); the opening
-- (Task 2): every egg rises onto a flat lit plinth in its Pedestal box (HatchLook.Plinth: neutral, popping 0.6 -> 1 and
-- fading in over the rise), Gemini's tweak from Rare up at the first shake (the plinth, the cloud ring and faint turning
-- rays take the rarity colour; x3: the rays for the best pull only), the burst's punch (Stage's UIScale "Punch", High
-- only), the sparks capped at 16 on phones; below Rare the plinth takes its colour at the burst. The reveal (Task 3): the
-- rarity word as letters popping in turn (HatchLook.Word: gradient, outline, glow; an x3 phone column one label), B's
-- silhouette from Legendary (the best pull's pets black for 0.3 s, the chain waiting for them), the name / NEW! / note
-- rising in, the glossy pills (HatchLook.Pill) rising in and the small chips (HatchLook.Chip / FastChip), a landscape
-- phone's x1 reveal side by side (the pet left, the word, name, note and pills right: L.reveal1Side), the rays dimmed to
-- 0.55 while the text shows.
--
--   EggStage.Init()                        connects the RouletteResult listener (once)
--   EggStage.Show(result) -> bool          plays a RouletteResult (new shape with Pulls, or the old top-level shape); a
--                                          result that comes while a roll plays waits in the queue (DONE plays it)
--   EggStage.Request(rouletteId, currency, spins) -> bool   the only BuyRoulette sender: FIRE_GAP 0.3 s, the pending
--                                          flag, WAIT_TIMEOUT 7 s (then a toast); a failure answer is one toast
--   EggStage.IsPending() / IsShowing() / Phase() -> "Intro" | "Strip" | "Land" | "Rise" | "Crack" | "Burst" | "Reveal" | nil
--   EggStage.Skip()                        before the reveal: the reveal starts on the next frame (sounds stop)
--   EggStage.Back()                        Esc's one path (ShopController's Esc handler, Task 22): skip before the
--                                          reveal, DONE on it. EggStage has NO UserInputService handler of its own.
--   EggStage.Done()                        DONE on the reveal (the next queued result plays in place); a skip before it
--   EggStage.Close()                       closes from anyone else (MenuController.Close, Task 22); toasts the pulls not
--                                          shown yet
--   (review round 2) taps = the Dim, the Skip chip, SPIN AGAIN, DONE. Before the reveal a tap skips at once; on it, SPIN
--   AGAIN, DONE and a tap's close act only once armed: ARM_AFTER 0.8 s after the reveal appeared and ARM_QUIET 0.5 s after
--   the last tap (each tap restarts the wait, so a mash never buys a spin); the two buttons show disabled until then. The
--   roll's Skip chip and Fast hatch sit on the reveal's chip row (L.rollBar), never under SPIN AGAIN or DONE. Esc / B
--   (Back) stay DONE at once on the reveal (keys never land on a paid button); Done() and Skip() are the API (no wait).
--   EggStage.Timings(fast, spins) -> { Intro, Strip, Land, Rise, Crack, Burst, Stagger, LandGap, RevealAt }
--   EggStage.NoteText(pull, rarity, brief) -> the reveal's note (brief: an x3 column's, without the pet's name);
--   EggStage.Layout() -> "PC" | "Phone" | "Portrait"
--   EggStage.IsPrewarmed(petId) -> true once that pet's model was built for the reveal (warmed during the strip)
--   EggStage.Stats() -> { Instances, Tweens, Sparks, Effects, Heartbeats }  this module's GUI instances (a ViewportFrame
--                                          counts as one), playing tweens (its own and its HatchFx handles'), live sparks,
--                                          Lighting effects (the blur and the "Hatch" preset) and Heartbeats (one: the
--                                          phase runner also steps the spark pool)
--   signals Pending(rouletteId, currency, spins), Answered(result), Opened(), Closed(reason)
--   EggStage._Answer(result)               the RouletteResult listener's body (tests call it while MenuController's old
--                                          stage still listens to the remote, until Task 22)
--   EggStage._InjectPhaseError = "<Phase>" a test-only hook (nil by default): the phase runner raises an error when the
--                                          roll reaches that phase ("Reveal": inside the reveal's build, after its
--                                          columns); every teardown resets it. An exit before the reveal was fully built
--                                          (roll.RevealBuilt, set last) toasts the roll's pulls
--
-- Instances: NimbusHatch (DisplayOrder 25, IgnoreGuiInset, ResetOnSpawn false) > Stage (UIScale "Punch") > Dim (the
-- tap-anywhere button), Vignette, (Stars: the Secret backdrop), Content (the area under the top bar, UIScale "Fit") > Title,
-- Strips > Strip1..3 > Track (a non-scrolling ScrollingFrame: it clips) > Cell1..12, Streaks (High), Pointer; Hero > Spot,
-- Rays, CloudRing1..3, Backlight1..3, Pedestal1..3 (> Top, Side, Ring, Glow1..2 or Glow: the plinth), Egg1..3 (> Cracks,
-- Leaks), Halves1..3, CrackWord; Burst > Shock, Sparks (the pool of 64);
-- Reveal > TextIn (the rise's NumberValue), Col1..3 > Banner (Word: L1..Ln + Glow1..2, attribute Text; an x3 phone
-- column: one TextLabel), Aura (Secret), Shell, Pet, Name, New (beside the name; an x3 phone / portrait column
-- puts it on the pet frame's top-left corner, under an EvolvedRibbon when there is one), Note, EvolvedRibbon; BottomBar > Skip,
-- FastHatch (the chips), SpinAgain, Done (the pills), PillsIn; then Stage > Flash. (The Rays live in Hero, not Burst: a GUI frame's children cannot sit
-- between another frame's, and the rays belong behind the egg, the pedestal and the pet.) Strip cells are recycled (at
-- most 12 per strip): a cell re-skins its egg with EggArt.SetRarity when it wraps (Task 26: lean Medium eggs, Rim = false
-- and Budget = 9; Rare and up wear a rarity ring on the cell's stroke; only the landed cell's egg gets its VFX).
-- Attributes for tests: Strip<j>.Landed, Egg<j>.State (Rise / Crack / Burst / Open), Burst.Sparks (the last burst's count).
--
-- Never breaks the player (16.4): it writes nothing to the Camera or the Humanoid and plays on through a death or a
-- respawn; one teardown(reason) ends every exit ("Done" | "Error" | "Match" | "Close") and fires Closed(reason) last.
-- Gamepad B: "NimbusHatchBack" at ContextActionPriority High + 1, bound only while the stage shows, always Sink.
-- Plain Lua 5.1-compatible syntax only. Text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Theme = require(Shared:WaitForChild("Theme"))
local PetCatalog = require(Shared:WaitForChild("PetCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UIFolder = script.Parent
local ClientFolder = UIFolder.Parent
local EggArt = require(UIFolder:WaitForChild("EggArt"))
local Egg3D = require(UIFolder:WaitForChild("Egg3D"))
local HatchFx = require(UIFolder:WaitForChild("HatchFx"))
local HatchLook = require(UIFolder:WaitForChild("HatchLook"))
local GemIcon = require(UIFolder:WaitForChild("GemIcon"))
local CloudUI = require(UIFolder:WaitForChild("CloudUI"))
local NeonKit = require(UIFolder:WaitForChild("NeonKit"))
local PetBits = require(UIFolder:WaitForChild("PetBits"))
local State = require(ClientFolder:WaitForChild("State"))
local ClientSettings = require(ClientFolder:WaitForChild("ClientSettings"))

local LocalPlayer = Players.LocalPlayer
local DOT = "\194\183"

local EggStage = {}
EggStage.Pending = Util.Signal()
EggStage.Answered = Util.Signal()
EggStage.Opened = Util.Signal()
EggStage.Closed = Util.Signal()

local K = {
	GUI = "NimbusHatch",
	ORDER = 25,
	BACK_ACTION = "NimbusHatchBack",
	FIRE_GAP = 0.3, -- seconds between two BuyRoulette sends
	WAIT_TIMEOUT = 7, -- seconds to wait for a RouletteResult
	-- (review round 2) SPIN AGAIN, DONE and a tap's close arm ARM_AFTER after the reveal appeared AND ARM_QUIET after the
	-- last tap on the stage (each tap restarts the wait): a double tap or a mash on the Skip chip never spends a spin
	ARM_AFTER = 0.8,
	ARM_QUIET = 0.5,
	-- (review round 3) SPIN AGAIN's row (label + coin + price + its two 6 px gaps) keeps this much of the button free (8 px a
	-- side, clear of the rounded gold border), else the price takes its short form from 1,000 up ("3K")
	AGAIN_SLACK = 16,
	NEXT_GAP = 0.15,
	STRIP_LEN = 40,
	WIN = 34,
	START_CELL = 4.5, -- the pointer starts over cell 5's centre (cell i spans i-1 .. i)
	CURVE = 2.8, -- the strip's ease (1 - (1 - t) ^ CURVE), today's
	TICKS_PER_S = 12,
	MAX_CELLS = 12,
	DIM = 0.45, -- the navy dim's final transparency (0.55 strong)
	VIGNETTE = 0.25, -- the vignette edges' final transparency
	NAVY = Color3.fromRGB(8, 12, 32),
	INK = Color3.fromRGB(11, 16, 48),
	GOLD = Color3.fromRGB(242, 182, 68),
	WHITE = Color3.new(1, 1, 1),
	TRACK = Color3.fromRGB(14, 22, 58),
	CELL = Color3.fromRGB(44, 70, 132),
	SECRET_TEXT = Color3.fromRGB(180, 150, 255), -- Secret's own colour is near black: the readable violet on navy
	SECRET_ID = (Config.Gems and Config.Gems.SecretRoulette and Config.Gems.SecretRoulette.Id) or "Secret",
	RESTRICTED_ATTR = "PaidRandomItemsRestricted",
	-- the owner's egg sounds (Config.Audio: each plays Config.Audio.Fallback while its id is 0)
	SOUND = { Tick = "EggStripTick", Land = "EggStripLand", Rise = "EggRise", Shake = "EggShake", Crack = "EggCrack", Burst = "EggBurst", Ring = "EggCloudRing" },
	-- the owner's picks page: EggRevealCommon is "Common to Rare", EggRevealLegend Legendary / Mythic
	REVEAL_SOUND = { Common = "EggRevealCommon", Uncommon = "EggRevealCommon", Rare = "EggRevealCommon", Epic = "EggRevealEpic", Legendary = "EggRevealLegend", Mythic = "EggRevealLegend", Secret = "EggRevealSecret" },
	LOUD_FROM = 5, -- Config.Rarities Order: Legendary and up play at Scale 1, the rest at 0.6
	QUIET = 0.6,
	-- (Task 27) the dressed cutscene (spec 16.4 "VFX and budget")
	SPARKS = { Common = 12, Uncommon = 16, Rare = 20, Epic = 28, Legendary = 40, Mythic = 48, Secret = 48 },
	CONFETTI = 24,
	STARS = 14,
	POOL = 64,
	PUSH = 1.06, -- the push-in: the hero egg's UIScale over the shakes (it grows on its foot, so it never meets the pedestal)
	SQUASH = 0.05, -- a shake squashes the egg this much (wider and lower, never taller)
	SHOCK = 900 / 380, -- the shock ring's last diameter, in egg heights (900 px over the 380 px PC egg)
	RAYS = 2.4, -- the rays' diameter, in egg heights (on the reveal 2.2 pet sizes)
	RING = 1.6, -- the cloud ring's diameter, in egg heights (roll-look: its puffs on a circle round the egg, the mock's ring)
	SPOT = 520 / 380, -- the spot cone's width, in egg heights
	SHAKE_SPARKS = 4,
	SHAKE_SPARK = { Life = { 0.25, 0.4 }, Speed = { 90, 170 }, Px = { 4, 7 } },
	GOLD_IN = 0.25, -- the gold flash: from 0.8 (a kick on the burst frame) to 0.5 in 0.25 s, out to clear in 0.6 s (half
	GOLD_FROM = 0.8, -- strong at most: the reveal's banner and name read through it)
	GOLD_PEAK = 0.5,
	GOLD_OUT = 0.6,
	WHITE_FLASH = { 0.4, 0.12 }, -- the micro-flash: transparency 0.4 (0.6 strong) for 0.12 s
	TAIL = 0.25, -- Skip's burst tail over the reveal's start
	PED = {
		StoneTop = Color3.fromRGB(214, 222, 240), StoneFoot = Color3.fromRGB(112, 124, 160), Top = Color3.fromRGB(241, 245, 255),
		Gold = Color3.fromRGB(242, 193, 78), Puff = Color3.fromRGB(227, 236, 251),
	},
	SPOT_COLOR = Color3.fromRGB(255, 246, 222),
	AURA = Color3.fromRGB(150, 110, 255),
	-- the shop's window rule (spec 5.4) decides Phone vs PC
	RECT = { RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1660, Y1 = 900 }, MARGIN = 12, PHONE_W = 900, SHORT = 560, PC_MIN_H = 600, PC_MAX_W = 0.87 },
	TEXT = {
		Match = "The shop is closed during a match.",
		-- (review round 1) a BuyRoulette that left the client is almost always charged: never ask for a retry
		NoAnswer = "Still waiting for the roulette. Your spin will hatch as soon as it arrives.",
		Failed = "The spin failed.",
		Fallback = "A new pet joined your collection!",
		Policy = "Gem roulettes are not available on this account right now.",
		Hatched = "You hatched: ",
	},
}
-- design px per layout (spec 5.5 / 16.4); the middle (strip cells, crack eggs, reveal pets) shrinks to 0.6, text never
K.PC = {
	TitleY = 34, TitleH = 60, TitleSize = 52, Side = 40,
	Strip1 = { H = 296, CellW = 230, CellH = 250, Step = 246, Egg = 160, Word = 18 },
	Strip3 = { H = 230, Gap = 30, CellW = 190, CellH = 210, Step = 206, Egg = 130, Word = 20 },
	Crack1 = { Egg = 380, Word = 80 }, Crack3 = { Egg = 220, Word = 80 }, Col3 = 520,
	R1 = { BannerY = 20, BannerH = 104, Word = 84, BannerMin = 320, BannerPad = 80, Gap = 8, Pet = 420, PetMin = 252, Ped = 90 / 420, NameGap = 16, NameH = 60, Name = 54, NoteGap = 4, NoteH = 32, Note = 24, NewW = 120, NewH = 44, New = 26 },
	R3 = { BannerH = 70, Word = 56, BannerMin = 200, BannerPad = 60, Gap = 12, Pet = 300, PetMin = 180, PedW = 0.8, PedH = 0.18, NameGap = 12, NameH = 44, Name = 36, NoteGap = 4, NoteH = 52, Note = 20, NewW = 96, NewH = 36, New = 22 },
	-- (roll-look, spec 16.15 "Sizes") the glossy pills 56 tall (44.8 real px at the PC factor's floor of 0.8, 1280x720 /
	-- 1366x768); the chips draw 36 px pills in tap boxes 56 tall for the same reason (the readability rule's 44 real px:
	-- a 44 design px box is 35 px at the floor); { pref, min, height } in design px
	Bar = { Gap = 16, Text = 22, ChipText = 18, Skip = { 260, 200, 56 }, SkipReveal = { 260, 200, 56 }, Fast = { 200, 170, 56 }, Again = { 380, 300, 56 }, Done = { 220, 180, 56 }, Coin = 30, FastText = 18 },
}
K.PHONE = {
	TitleY = 6, TitleH = 28, TitleSize = 28, Side = 10,
	Strip1 = { H = 170, CellW = 130, CellH = 160, Step = 138, Egg = 104, Word = 15 },
	Strip3 = { H = 74, Gap = 6, CellW = 76, CellH = 66, Step = 80, Egg = 48 },
	Crack1 = { Egg = 200, Word = 40 }, Crack3 = { Egg = 96, Word = 40 }, Col3 = 260,
	R1 = { BannerY = 2, BannerH = 44, Word = 40, BannerMin = 160, BannerPad = 40, Gap = 2, Pet = 170, PetMin = 110, Lip = true, NameGap = 2, NameH = 30, Name = 26, NoteGap = 2, NoteH = 20, NoteH2 = 36, Note = 15, NewW = 70, NewH = 26, New = 15 },
	R3 = { BannerH = 28, Word = 22, BannerMin = 120, BannerPad = 24, Gap = 2, Pet = 130, PetMin = 78, Lip = true, NameGap = 2, NameH = 22, Name = 18, NoteGap = 2, NoteH = 36, Note = 15, NewW = 56, NewH = 22, New = 15, RowPet = 110, RowMax = 150 },
	-- (roll-look) pills 46 tall, chips 44 px boxes drawing 32 px pills; Again3 = SPIN AGAIN x3 (its longer label beside the
	-- price chip, measured with the real fonts)
	Bar = { Gap = 8, Text = 16, ChipText = 15, Skip = { 150, 120, 44 }, SkipReveal = { 150, 120, 44 }, Fast = { 150, 135, 44 }, Again = { 208, 180, 46 }, Again3 = { 250, 226, 46 }, Done = { 118, 100, 46 }, Coin = 20, FastText = 15 },
	-- (roll-look, spec 16.15 "Phone x1 landscape reveal", the pitch's phoneA) side by side: the pet in the left PetCol of
	-- the width, the right column from the top: the word row (the 44 px band, letters at Word, Min WordMin), the name row
	-- (+ NEW!), the note (two lines), the two pills; the chips stay on the bottom row
	R1Side = { PetCol = 0.46, Pet = 170, PetMin = 110, WordRow = 48, BannerH = 44, BannerPad = 24, Word = 44, WordMin = 40, Gap = 8, NameH = 30, Name = 26, NoteGap = 4, NoteH = 36, Note = 15, PillGap = 12, NewW = 70, NewH = 26, New = 15 },
}
K.LIP = { W = 0.7, H = 12, Up = 8 }
-- the crack's shakes as { from, to (shares of Crack), degrees }: two, one on Fast hatch
K.SHAKE = { { 0.12, 0.4, 6 }, { 0.55, 0.88, 10 } }
K.SHAKE_FAST = { { 0.25, 0.75, 10 } }
-- (egg-3d, spec 16.14) the 3D hero egg: its start angle (degrees: a three-quarter look that turns towards the front), a
-- slow turn (seconds a turn) over the rise, settling over this share of the crack; a shake's dip (studs at full squash);
-- the egg layers that turn with its rock on screen
K.EGG3D = { Turn = -28, Spin = 9, Settle = 0.3, Dip = 0.06, Turns = { "Cracks", "Leaks" } }
-- (roll-look, spec 16.15 "Roll look A+B") the dressed strip (client/UI/HatchLook builds the pieces): B's colour tell (Rare
-- and up: the window turns the coming colour Before s ahead of the land, in Tween s; Fast hatch in brackets), the
-- overshoot (Px x the strip's scale past the winner at the end of the ease, then the Back Out spring over Land), the
-- track's colours, the card and window sizes per layout (design px at the 1080p strip; x3 and a shrunk strip scale them)
K.LOOK = {
	TELL = { Before = 0.7, Fast = 0.25, Tween = 0.25, TweenFast = 0.1 },
	OVERSHOOT = { Px = 18, Fast = 8 },
	TRACK = {
		Top = Color3.fromRGB(20, 31, 82), Bottom = Color3.fromRGB(8, 13, 40), Outer = Color3.fromRGB(3, 5, 15), OuterA = 0.15, Rim = 4,
		Edge = Color3.fromRGB(44, 63, 136), Fade = Color3.fromRGB(14, 22, 61), FadeW = 0.12,
	},
	PC = { Card = { Corner = 18, Shadow = 8, Shine = 3, Plate = 30, Notch = 16, Win = 4, WinGlow = 10, Pad = 8 } },
	PHONE = { Card = { Corner = 12, Shadow = 5, Shine = 2, Plate = 22, Notch = 10, Win = 3, WinGlow = 6, Pad = 6 } },
	-- (Task 2) Gemini's shake tweak (Rare and up, at the first shake: the plinth, the cloud ring and the rays to the rarity
	-- colour in Tween s, Fast hatch in Fast s; the rays rest at GroupTransparency Rays); the burst's punch (Stage's UIScale
	-- to Scale in Up s, back in Down s; squeezed into a Fast hatch's shorter burst); the plinth's pop over the rise (From ->
	-- 1, Back Out); below Rare the plinth takes its colour at the burst in BurstTint s; the sparks a phone's burst keeps
	TWEAK = { Tween = 0.25, Fast = 0.1, Rays = 0.75 },
	PUNCH = { Scale = 1.05, Up = 0.08, Down = 0.25 },
	PLINTH_IN = { From = 0.6 },
	BURST_TINT = 0.15,
	PHONE_SPARKS = 16,
	-- (Task 3) B's silhouette (the best pull from Config.Rarities Order From: its pet black until Hold, white in Fill; the
	-- reveal's chain waits for it); the chain (seconds from the silhouette's end: the letters Letter apart, the name / NEW! /
	-- note rising TextRise px from Text in TextIn, NEW!'s pop to NewPeak at New in NewIn then NewOut, the pills rising
	-- PillsRise px (less where the screen's edge is nearer) from Pills in PillsIn); the rays' rest while the text shows
	SIL = { Hold = 0.3, Fill = 0.15, From = 5 },
	CHAIN = { Letter = 0.05, Text = 0.2, TextRise = 16, TextIn = 0.25, New = 0.4, NewPeak = 1.3, NewIn = 0.15, NewOut = 0.12, Pills = 0.4, PillsRise = 20, PillsIn = 0.3 },
	RAYS_TEXT = 0.55,
	CHEVRONS = "\226\128\186\226\128\186",
	NEW = { Edge = Color3.fromRGB(107, 66, 0), Ink = Color3.fromRGB(58, 34, 0), Tilt = -6 },
}
EggStage.Metrics = K

-- S: the stage. Roll = the roll playing (or nil); Queue = results waiting for DONE; Lay = the layout of this screen
local S = {
	Gui = nil, Stage = nil, Content = nil, Fit = nil, Dim = nil, Flash = nil, Vignette = nil, Punch = nil,
	Roll = nil, Queue = {}, Lay = nil, Conns = {}, Beat = nil, Bound = false, Inited = false,
	Pending = false, PendToken = 0, PendFrom = nil, LastFire = -10, LastTap = -10,
	Warm = {}, Warned = {}, Menu = nil, Sfx = nil, Builder = nil, GQ = nil, Stars = nil, Dimmed = false,
}
-- the tweens of the phases (cancelled at the reveal) and of the overlay (the flash, the shock, the rays: they play on
-- over the reveal's start); both weak-keyed, both counted by Stats and cancelled by every teardown
S.Tweens = setmetatable({}, { __mode = "k" })
S.Overlay = setmetatable({}, { __mode = "k" })
EggStage._S = S
EggStage._InjectPhaseError = nil

local H = {} -- helpers
local L = {} -- layout
local B = {} -- builders
local R = {} -- the phase runner

----------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------
function H.warnOnce(key, err)
	local k = tostring(key) .. tostring(err)
	if not S.Warned[k] then
		S.Warned[k] = true
		warn("[EggStage] " .. tostring(key) .. ": " .. tostring(err))
	end
end

function H.safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		H.warnOnce(key, err)
	end
	return ok
end

function H.lazy(field, folder, name)
	if S[field] == nil then
		S[field] = false
		local module = folder and folder:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				S[field] = mod
			end
		end
	end
	return S[field] or nil
end

function H.menu()
	return H.lazy("Menu", ClientFolder:FindFirstChild("Controllers"), "MenuController")
end

function H.toast(text)
	local mc = H.menu()
	if mc and type(mc.Hint) == "function" then
		pcall(mc.Hint, text, "info")
	end
end

-- one sound of the roll: an egg key without an id yet plays Config.Audio.Fallback[key] in its place (or nothing); the
-- Sound is remembered so a skip (and an exit before the reveal) can stop it
function H.sfx(name, scale)
	local sf = H.lazy("Sfx", ClientFolder, "SoundFx")
	if not sf or type(sf.Play) ~= "function" then
		return nil
	end
	local fallback = type(Config.Audio) == "table" and type(Config.Audio.Fallback) == "table" and Config.Audio.Fallback or {}
	if fallback[name] ~= nil then
		local okId, id = pcall(sf.Id, "Sfx", name)
		if not (okId and id) then
			name = fallback[name]
			if not name then
				return nil
			end
		end
	end
	local ok, snd = pcall(sf.Play, name, { Scale = scale })
	if ok and typeof(snd) == "Instance" then
		if S.Roll then
			S.Roll.Sounds[snd] = true
		end
		return snd
	end
	return nil
end

function H.stopSounds(roll)
	for snd in pairs(roll and roll.Sounds or {}) do
		pcall(function()
			snd:Stop()
		end)
	end
	if roll then
		roll.Sounds = {}
	end
end

-- High graphics (GraphicsQuality has Low and High): the blur, the tint, the turning rays and ring, the speed streaks
function H.high()
	local gq = H.lazy("GQ", ClientFolder, "GraphicsQuality")
	if not gq or type(gq.Effective) ~= "function" then
		return true
	end
	local ok, mode = pcall(gq.Effective)
	return not ok or mode ~= "Low"
end

function H.order(rarity)
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarity then
			return r.Order or 1
		end
	end
	return 1
end

function H.scaleFor(rarity)
	return H.order(rarity) >= K.LOUD_FROM and 1 or K.QUIET
end

function H.color(rarity)
	if rarity == "Secret" then
		return K.SECRET_TEXT
	end
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarity then
			return r.Color
		end
	end
	return K.WHITE
end

function H.inMatch()
	return LocalPlayer ~= nil and LocalPlayer:GetAttribute(Config.Attr.InMatch) == true
end

function H.roulette(id)
	if type(id) ~= "string" then
		return nil
	end
	for _, r in ipairs(Config.Roulettes or {}) do
		if r.Id == id then
			return r
		end
	end
	local s = Config.Gems and Config.Gems.SecretRoulette
	if s and s.Id == id then
		return s
	end
	return nil
end

-- the price of one spin in that currency (Config; the server checks it again)
function H.price(roulette, currency)
	if not roulette then
		return 0
	end
	if currency == "Gems" then
		local prices = Config.Gems and Config.Gems.RouletteGemPrices or {}
		return math.floor(tonumber(prices[roulette.Id]) or tonumber(roulette.GemPrice) or 0)
	end
	return math.floor(tonumber(roulette.Price) or 0)
end

function H.balance(currency)
	local fn = currency == "Gems" and State.Gems or State.Tokens
	local ok, n = pcall(fn)
	return (ok and type(n) == "number") and n or 0
end

function H.gemsOpen()
	return LocalPlayer ~= nil and LocalPlayer:GetAttribute(K.RESTRICTED_ATTR) == false
end

function H.remote(name)
	local ok, remote = pcall(Remotes.Get, name)
	return ok and remote or nil
end

-- the text's width (TextService: the real font). K.MEASURE(text, size, font) replaces it when set: tools/dump_gui.lua's
-- renders pass the renderer's font metrics (the mock's GetTextSize is a flat 0.5 em per character)
function H.textW(text, size, role)
	local font = Theme.Fonts[role] or Theme.Fonts.Body
	local ok, v = pcall(function()
		if type(K.MEASURE) == "function" then
			return Vector2.new(K.MEASURE(text, size, font), size)
		end
		return TextService:GetTextSize(text, size, font, Vector2.new(100000, 1000))
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return v.X
	end
	return #tostring(text) * size * 0.6
end

function H.tween(inst, seconds, goals, style, direction, overlay)
	if not inst or not inst.Parent then
		return nil
	end
	local info = TweenInfo.new(math.max(0.01, seconds), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tw = TweenService:Create(inst, info, goals)
	if overlay then
		S.Overlay[tw] = true
	else
		S.Tweens[tw] = true
	end
	tw:Play()
	return tw
end

-- the phases' tweens; with all = true the overlay's too (a resize, an exit)
function H.cancelTweens(all)
	for _, set in ipairs(all and { S.Tweens, S.Overlay } or { S.Tweens }) do
		for tw in pairs(set) do
			pcall(function()
				tw:Cancel()
			end)
			set[tw] = nil
		end
	end
end

function H.frame(parent, name, props)
	props = props or {}
	props.Name = name
	props.BorderSizePixel = 0
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	props.Parent = parent
	return Util.Create("Frame", props)
end

function H.label(parent, name, text, role, size, props)
	local l = Theme.Label(text, role, { Size = size, Stroke = 0.2, Outline = 2 })
	l.Name = name
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function H.corner(parent, r)
	return Util.Create("UICorner", { CornerRadius = (r and r < 1) and UDim.new(r, 0) or UDim.new(0, r or 12), Parent = parent })
end

function H.stroke(parent, color, thickness)
	return Util.Create("UIStroke", { Color = color, Thickness = thickness or 3, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

function H.place(o, x, y, w, h)
	if o then
		o.Position = UDim2.fromOffset(x, y)
		if w then
			o.Size = UDim2.fromOffset(math.max(0, w), math.max(0, h))
		end
	end
end

-- (Task 26) EggArt.Resize: the size, the outline and every painted stroke (ring dots, swirls, the VFX rings) follow
function H.sizeEgg(egg, size)
	EggArt.Resize(egg, size)
end

function H.insets()
	local top, bottom = 58, 0
	pcall(function()
		local tl, br = GuiService:GetGuiInset()
		top, bottom = tl.Y, br.Y
	end)
	return top, bottom
end

function H.viewport()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize
	if v and v.X > 2 and v.Y > 2 then
		return v.X, v.Y
	end
	return 1280, 720
end

----------------------------------------------------------------------
-- public pure parts
----------------------------------------------------------------------
function EggStage.Timings(fast, spins)
	local t
	if fast then
		t = { Intro = 0.15, Strip = 0.8, Land = 0.12, Rise = 0.2, Crack = 0.4, Burst = 0.25 }
	else
		t = { Intro = 0.35, Strip = 3.0, Land = 0.35, Rise = 0.5, Crack = 1.2, Burst = 0.35 }
	end
	t.Stagger, t.LandGap = 0, 0
	local n = 1
	if (tonumber(spins) or 1) > 1 then
		n = 3
		t.Crack = fast and 0.4 or 0.9
		t.Stagger = fast and 0.25 or 0.6
		t.LandGap = fast and 0.12 or 0.25
	end
	t.RevealAt = t.Intro + t.Strip + (n - 1) * t.LandGap + t.Land + t.Rise + (n - 1) * t.Stagger + t.Crack + t.Burst
	return t
end

-- brief (an x3 column, review round 3): a duplicate's note leaves the pet's name out ("you have 12 now"); the name sits right
-- above it, and on a phone the long form wrapped to three lines in the column's 36 px box
function EggStage.NoteText(pull, rarity, brief)
	pull = type(pull) == "table" and pull or {}
	local def = type(pull.PetId) == "string" and PetCatalog.Get(pull.PetId) or nil
	rarity = rarity or (def and def.Rarity) or "?"
	local text
	local sub = type(pull.Substitute) == "table" and tonumber(pull.Substitute.Tokens) or nil
	if sub then
		text = "Stack full: +" .. Util.Commas(sub) .. " Tokens instead"
	else
		local tail
		if pull.IsNew == true then
			tail = "added to your pets"
		else
			local count = tonumber(pull.Count)
			if not count then
				local ok, n = pcall(State.OwnedCount, pull.Key or pull.PetId)
				count = (ok and type(n) == "number") and n or 1
			end
			local what = brief and "" or (" " .. (def and def.Name or "of them"))
			tail = "you have " .. math.floor(count) .. what .. " now"
		end
		local n = tonumber(pull.PoolSize)
		if n and n >= 1 then
			text = "1 of " .. math.floor(n) .. " " .. rarity .. (n == 1 and " pet " or " pets ") .. DOT .. " " .. tail
		else
			text = tail:sub(1, 1):upper() .. tail:sub(2)
		end
	end
	if pull.Pity == true then
		text = text .. " " .. DOT .. " guaranteed"
	end
	return text
end

function EggStage.Layout()
	local w, h = H.viewport()
	local top = H.insets()
	local ok, rect = pcall(NeonKit.BigRect, K.RECT, { Width = w, Height = h, Inset = top })
	if h > w then
		return "Portrait"
	end
	if ok and type(rect) == "table" and rect.mode == "Phone" then
		return "Phone"
	end
	return "PC"
end

----------------------------------------------------------------------
-- the roll (a normalized result)
----------------------------------------------------------------------
function H.stripRarities(strip, rarity)
	if type(strip) ~= "table" or #strip < K.WIN then
		return nil
	end
	local out = {}
	for i = 1, K.STRIP_LEN do
		local def = type(strip[i]) == "string" and PetCatalog.Get(strip[i]) or nil
		out[i] = (def and EggArt.Glow(def.Rarity) ~= nil and def.Rarity) or false
	end
	out[K.WIN] = rarity
	return out
end

function R.schedule(roll)
	local T = roll.T
	local n = roll.N
	local s = { IntroEnd = T.Intro, Land = {} }
	local t = T.Intro
	if roll.HasStrip then
		for j = 1, n do
			s.Land[j] = T.Intro + T.Strip + (j - 1) * T.LandGap
		end
		s.StripEnd = s.Land[n]
		s.LandEnd = s.StripEnd + T.Land
		t = s.LandEnd
	else
		s.StripEnd, s.LandEnd = t, t
	end
	s.RiseEnd = t + T.Rise
	s.CrackAt, s.BurstAt, s.OpenAt = {}, {}, {}
	for j = 1, n do
		s.CrackAt[j] = s.RiseEnd + (j - 1) * T.Stagger
		s.BurstAt[j] = s.CrackAt[j] + T.Crack
		s.OpenAt[j] = s.BurstAt[j] + T.Burst
	end
	s.RevealAt = s.OpenAt[n]
	return s
end

function H.makeRoll(result)
	if type(result) ~= "table" or result.Ok == false then
		return nil
	end
	local src = (type(result.Pulls) == "table" and #result.Pulls > 0) and result.Pulls or { result }
	local roulette = H.roulette(result.RouletteId)
	local pulls = {}
	for i = 1, math.min(3, #src) do
		local p = src[i]
		local def = type(p) == "table" and type(p.PetId) == "string" and PetCatalog.Get(p.PetId) or nil
		if def then
			local rarity = EggArt.Metrics.GLOW[def.Rarity] and def.Rarity or "Common"
			local pull = {
				Def = def, PetId = def.Id, Key = (type(p.Key) == "string" and p.Key ~= "") and p.Key or def.Id, Rarity = rarity,
				IsNew = p.IsNew == true, Count = tonumber(p.Count), PoolSize = tonumber(p.PoolSize),
				Pity = (p.Pity == true) or nil, Substitute = type(p.Substitute) == "table" and p.Substitute or nil,
			}
			if not pull.PoolSize and roulette then
				local n = #PetCatalog.RarityPool(roulette.Id, rarity)
				pull.PoolSize = n > 0 and n or nil
			end
			pull.Rarities = H.stripRarities(p.Strip, rarity)
			pulls[#pulls + 1] = pull
		end
	end
	if #pulls == 0 then
		return nil
	end
	local hasStrip = true
	local best = 1
	for j, p in ipairs(pulls) do
		if not p.Rarities then
			hasStrip = false
		end
		if H.order(p.Rarity) > H.order(pulls[best].Rarity) then
			best = j
		end
	end
	local currency = (result.Currency == "Gems") and "Gems" or "Tokens"
	if roulette and roulette.Id == K.SECRET_ID then
		currency = "Gems"
	end
	local fast = ClientSettings.Get("FastHatch") == true
	local roll = {
		Result = result, Pulls = pulls, N = #pulls, Roulette = roulette, Currency = currency, HasStrip = hasStrip, Fast = fast, Best = best,
		T = EggStage.Timings(fast, #pulls > 1 and 3 or 1), Strips = {}, Eggs = {}, Cols = {}, Views = {}, UI = {}, Phase = "Intro",
		Sounds = {}, Hi = H.high(), Tweaked = {},
	}
	roll.Sched = R.schedule(roll)
	return roll
end

----------------------------------------------------------------------
-- layout (design px in Content's own space; Content = the screen under the top bar at the UIScale "Fit")
----------------------------------------------------------------------
-- the bottom bar: { H, Items = { [name] = { x, y, w, h } } } for the roll (Skip, Fast hatch) or the reveal
function L.bar(cw, P, portrait, reveal, hasAgain, x3)
	local spec = P.Bar
	local gap = spec.Gap
	local avail = cw - 24
	local again = (x3 and spec.Again3) or spec.Again
	local items
	if reveal then
		items = { { "Skip", spec.SkipReveal } }
		if hasAgain then
			items[#items + 1] = { "SpinAgain", again }
		end
		items[#items + 1] = { "Done", spec.Done }
		items[#items + 1] = { "FastHatch", spec.Fast }
	else
		items = { { "Skip", spec.Skip }, { "FastHatch", spec.Fast } }
	end
	local out = { Items = {} }
	local function sum(list, k)
		local s = 0
		for _, it in ipairs(list) do
			s = s + it[2][k]
		end
		return s + gap * (#list - 1)
	end
	local function rowH(list)
		local h = 0
		for _, it in ipairs(list) do
			h = math.max(h, it[2][3])
		end
		return h
	end
	-- one row: widths between min and pref, packed and centred from x0
	local function packRow(list, y, h)
		local pref, least = sum(list, 1), sum(list, 2)
		local k = 1
		if pref > avail then
			k = (pref == least) and 0 or math.max(0, (avail - least) / (pref - least))
		end
		local total = 0
		local widths = {}
		for i, it in ipairs(list) do
			widths[i] = it[2][2] + (it[2][1] - it[2][2]) * k
			total = total + widths[i]
		end
		total = total + gap * (#list - 1)
		local x = (cw - total) / 2
		for i, it in ipairs(list) do
			out.Items[it[1]] = { x = x, y = y + (h - it[2][3]) / 2, w = widths[i], h = it[2][3] }
			x = x + widths[i] + gap
		end
	end
	local h = rowH(items)
	if sum(items, 1) <= avail then
		-- the anchored row: the roll's Skip centred, the reveal's SPIN AGAIN + DONE centred; Skip left, Fast hatch right
		local fast = spec.Fast[1]
		local fastX = cw - 12 - fast
		local okAnchored
		if reveal then
			local mainW = (hasAgain and (again[1] + gap) or 0) + spec.Done[1]
			local mainX = (cw - mainW) / 2
			okAnchored = 12 + spec.SkipReveal[1] + gap <= mainX and mainX + mainW + gap <= fastX
			if okAnchored then
				out.Items.Skip = { x = 12, y = (h - spec.SkipReveal[3]) / 2, w = spec.SkipReveal[1], h = spec.SkipReveal[3] }
				local x = mainX
				if hasAgain then
					out.Items.SpinAgain = { x = x, y = (h - again[3]) / 2, w = again[1], h = again[3] }
					x = x + again[1] + gap
				end
				out.Items.Done = { x = x, y = (h - spec.Done[3]) / 2, w = spec.Done[1], h = spec.Done[3] }
			end
		else
			local skipX = (cw - spec.Skip[1]) / 2
			okAnchored = skipX + spec.Skip[1] + gap <= fastX
			if okAnchored then
				out.Items.Skip = { x = skipX, y = (h - spec.Skip[3]) / 2, w = spec.Skip[1], h = spec.Skip[3] }
			end
		end
		if okAnchored then
			out.Items.FastHatch = { x = fastX, y = (h - spec.Fast[3]) / 2, w = fast, h = spec.Fast[3] }
		else
			packRow(items, 0, h)
		end
		out.H = h
	elseif sum(items, 2) <= avail and not portrait then
		packRow(items, 0, h)
		out.H = h
	else
		-- two rows: the main controls on top
		local top, low
		if reveal then
			top = {}
			if hasAgain then
				top[1] = items[2]
			end
			top[#top + 1] = { "Done", spec.Done }
			low = { { "Skip", spec.SkipReveal }, { "FastHatch", spec.Fast } }
		else
			top, low = { items[1] }, { items[2] }
		end
		local h1, h2 = rowH(top), rowH(low)
		packRow(top, 0, h1)
		packRow(low, h1 + 8, h2)
		out.H = h1 + 8 + h2
	end
	return out
end

-- (roll-look) a landscape phone's x1 reveal (side by side, its pills in the right column, L.reveal1Side): the bottom row
-- holds the two chips only, Skip at the left, Fast hatch at the right
function L.chipBar(cw, P)
	local spec = P.Bar
	local s, f = spec.SkipReveal, spec.Fast
	local h = math.max(s[3], f[3])
	return {
		H = h,
		Items = {
			Skip = { x = 12, y = (h - s[3]) / 2, w = s[1], h = s[3] },
			FastHatch = { x = cw - 12 - f[1], y = (h - f[3]) / 2, w = f[1], h = f[3] },
		},
	}
end

-- (review round 2) the roll's bar is the reveal's chip row: the Skip chip and the Fast hatch toggle sit exactly where the
-- reveal puts "Tap to close" and its Fast hatch (one row, bottom-anchored like the reveal's), so the finger that skipped
-- rests on the close chip or the Dim as the reveal appears, never on SPIN AGAIN or DONE (which also arm late: H.armed).
-- The owner's pitch drew the roll's SKIP in a bottom corner, clear of the centred SPIN AGAIN + DONE.
function L.rollBar(rev)
	local s, f = rev.Items.Skip, rev.Items.FastHatch
	if not (s and f) then
		return nil
	end
	local h = math.max(s.h, f.h)
	return {
		H = h,
		Items = {
			Skip = { x = s.x, y = (h - s.h) / 2, w = s.w, h = s.h },
			FastHatch = { x = f.x, y = (h - f.h) / 2, w = f.w, h = f.h },
		},
	}
end

function L.compute(n, roll)
	local w, h = H.viewport()
	local top, bottom = H.insets()
	local mode = EggStage.Layout()
	local pc = mode == "PC"
	local P = pc and K.PC or K.PHONE
	local scale = pc and Theme.ScreenFactor(h) or 1
	local cw, ch = w / scale, math.max(1, (h - top) / scale)
	local x3 = n > 1
	local lay = { Mode = mode, PC = pc, P = P, Scale = scale, W = cw, H = ch, Top = top, N = n, X3 = x3, Portrait = mode == "Portrait" }
	local bm = (12 + bottom) / scale -- 12 screen px above the bottom inset at every scale
	local hasAgain = roll ~= nil and roll.Roulette ~= nil
	lay.HasAgain = hasAgain
	-- (roll-look) a landscape phone's x1 reveal stands side by side: its pills go to the right column, the bottom row
	-- keeps the two chips (L.reveal1Side places the pills)
	lay.Side = mode == "Phone" and not x3
	lay.BarReveal = lay.Side and L.chipBar(cw, P) or L.bar(cw, P, lay.Portrait, true, hasAgain, x3)
	lay.BarRoll = L.rollBar(lay.BarReveal) or L.bar(cw, P, lay.Portrait, false, hasAgain, x3)
	lay.BarRoll.Y = ch - bm - lay.BarRoll.H
	lay.BarReveal.Y = ch - bm - lay.BarReveal.H
	lay.Title = { Y = P.TitleY, H = P.TitleH, Size = P.TitleSize }
	local midTop, midBot = P.TitleY + P.TitleH, lay.BarRoll.Y
	local avail = midBot - midTop
	-- strips
	local spec = x3 and P.Strip3 or P.Strip1
	local total = x3 and (3 * spec.H + 2 * spec.Gap) or spec.H
	local s = Util.Clamp(avail / total, 0.6, 1)
	local step = spec.Step * s
	local trackW = math.min(cw - 2 * P.Side, 10 * step)
	local y0 = midTop + (avail - total * s) / 2
	lay.Strip = { S = s, Step = step, CellW = spec.CellW * s, CellH = spec.CellH * s, Egg = math.floor(spec.Egg * s + 0.5), Word = spec.Word, H = spec.H * s, W = trackW, X = (cw - trackW) / 2, Y = {} }
	for j = 1, (x3 and 3 or 1) do
		lay.Strip.Y[j] = y0 + (j - 1) * (spec.H + (spec.Gap or 0)) * s
	end
	-- the crack: the word, the egg, its pedestal (1.1 x / 0.24 x the egg), centred in the middle. The gap above the egg
	-- keeps the room of its outline (a Border stroke, size / 20 outside its box) and of the push-in (Task 27: the egg grows
	-- to K.PUSH on its foot during the shakes), so the word stays clear at the push-in's peak
	local crack = x3 and P.Crack3 or P.Crack1
	local colW = x3 and math.min(P.Col3, (cw - 24) / 3) or cw
	local sE = Util.Clamp((avail - crack.Word - 6) / ((1.24 + (K.PUSH - 1) + 0.05) * crack.Egg), 0.6, 1)
	local E = crack.Egg * sE
	if x3 then
		E = math.min(E, (colW - 8) / 1.1)
	end
	E = math.floor(E)
	local gap = math.max(2, math.floor(E / 20 + 0.5)) + 4 + math.ceil((K.PUSH - 1) * E)
	local stackH = crack.Word + gap + E * 1.24
	local cTop = midTop + (avail - stackH) / 2
	lay.Crack = { E = E, WordY = cTop, WordH = crack.Word, EggY = cTop + crack.Word + gap, PedW = 1.1 * E, PedH = 0.24 * E, Cx = {} }
	for j = 1, (x3 and 3 or 1) do
		lay.Crack.Cx[j] = x3 and (cw / 2 + (j - 2) * colW) or cw / 2
	end
	-- the reveal
	if x3 then
		L.reveal3(lay, P, colW)
	elseif lay.Side then
		L.reveal1Side(lay, P)
	else
		L.reveal1(lay, P)
	end
	return lay
end

-- (roll-look, spec 16.15, the pitch's phoneA) a landscape phone's x1 reveal side by side: the pet (and its lip) centred in
-- the left PetCol of the screen; the right column's stack (the word band, the name row, the note, the two pills) centred
-- beside it; the pills are BottomBar's items placed up here (y relative to the bar), the chips stay on the bottom row
function L.reveal1Side(lay, P)
	local r = P.R1Side
	local bar = P.Bar
	local cw = lay.W
	local col = { X = 0, Y = 0, W = cw, H = lay.H }
	local leftW = math.floor(r.PetCol * cw)
	local midTop, midBot = 2, lay.BarReveal.Y - 2
	local avail = midBot - midTop
	local pet = math.floor(Util.Clamp(math.min(r.Pet, leftW - 24, avail - 20), r.PetMin, r.Pet))
	local petY = midTop + math.max(0, (avail - pet) / 2)
	col.Pet = { X = (leftW - pet) / 2, Y = petY, S = pet }
	col.Ped = { X = col.Pet.X + (pet - K.LIP.W * pet) / 2, Y = petY + pet - K.LIP.Up - K.LIP.H, W = K.LIP.W * pet, H = K.LIP.H }
	col.Shell = L.shell(col.Pet, true)
	local rx = leftW + r.Gap
	local rw = cw - rx - 12
	local items = {}
	if lay.HasAgain then
		items[1] = { "SpinAgain", bar.Again }
	end
	items[#items + 1] = { "Done", bar.Done }
	local pillH = 0
	for _, it in ipairs(items) do
		pillH = math.max(pillH, it[2][3])
	end
	local stack = r.WordRow + r.Gap + r.NameH + r.NoteGap + r.NoteH + r.PillGap + pillH
	local top = midTop + math.max(0, (avail - stack) / 2)
	col.Banner = { CX = rx + rw / 2, Y = top + (r.WordRow - r.BannerH) / 2, H = r.BannerH, Word = r.Word, WordMin = r.WordMin, Min = 0, Pad = r.BannerPad, MaxW = rw }
	col.NameX, col.NameW = rx, rw
	col.NameY, col.NameH, col.NameSize = top + r.WordRow + r.Gap, r.NameH, r.Name
	col.NoteY, col.NoteH, col.NoteSize = col.NameY + r.NameH + r.NoteGap, r.NoteH, r.Note
	col.New = { W = r.NewW, H = r.NewH, Size = r.New }
	-- the pills: preferred widths, down to their least when the column is narrow, centred under the note
	local pref, least = bar.Gap * (#items - 1), bar.Gap * (#items - 1)
	for _, it in ipairs(items) do
		pref, least = pref + it[2][1], least + it[2][2]
	end
	local k = (pref <= rw or pref == least) and 1 or math.max(0, (rw - least) / (pref - least))
	local x = rx + (rw - (least + (pref - least) * k)) / 2
	local py = col.NoteY + r.NoteH + r.PillGap
	for _, it in ipairs(items) do
		local w = it[2][2] + (it[2][1] - it[2][2]) * k
		lay.BarReveal.Items[it[1]] = { x = x, y = py + (pillH - it[2][3]) / 2 - lay.BarReveal.Y, w = w, h = it[2][3] }
		x = x + w + bar.Gap
	end
	lay.Cols = { col }
end

-- x1 reveal: the Banner as the title band, then pet (+ pedestal or lip), name, note centred above the bottom bar
function L.reveal1(lay, P)
	local r = P.R1
	local cw = lay.W
	local col = { X = 0, Y = 0, W = cw, H = lay.H }
	local midTop = r.BannerY + r.BannerH + r.Gap
	local midBot = lay.BarReveal.Y - r.Gap
	local noteH = (lay.Portrait and r.NoteH2) or r.NoteH
	local fixed = r.NameGap + r.NameH + r.NoteGap + noteH
	local pedK = r.Lip and 0 or r.Ped
	local pet = math.floor(Util.Clamp((midBot - midTop - fixed) / (1 + pedK), r.PetMin, r.Pet))
	local stack = pet * (1 + pedK) + fixed
	local top = midTop + math.max(0, (midBot - midTop - stack) / 2)
	col.Banner = { Y = r.BannerY, H = r.BannerH, Word = r.Word, Min = r.BannerMin, Pad = r.BannerPad }
	col.Pet = { X = (cw - pet) / 2, Y = top, S = pet }
	col.NameY = top + pet * (1 + pedK) + r.NameGap
	col.NameH, col.NameSize = r.NameH, r.Name
	col.NoteY, col.NoteH, col.NoteSize = col.NameY + r.NameH + r.NoteGap, noteH, r.Note
	col.New = { W = r.NewW, H = r.NewH, Size = r.New }
	if r.Lip then
		col.Ped = { X = (cw - K.LIP.W * pet) / 2, Y = top + pet - K.LIP.Up - K.LIP.H, W = K.LIP.W * pet, H = K.LIP.H }
	else
		col.Ped = { X = (cw - pet) / 2, Y = top + pet, W = pet, H = pet * r.Ped }
	end
	col.Shell = L.shell(col.Pet, r.Lip)
	lay.Cols = { col }
end

-- the shell (the egg's bottom half) at the pet's feet
function L.shell(pet, lip)
	local eggSize = math.floor(pet.S * 0.52)
	local w = math.floor(EggArt.Metrics.WIDTH * eggSize + 0.5)
	local bottom = pet.Y + pet.S - (lip and (K.LIP.Up + 4) or 2)
	return { X = pet.X + (pet.S - w) / 2, Y = bottom - eggSize / 2, W = w, H = eggSize / 2, Egg = eggSize }
end

-- x3 reveal: three columns (PC / phone landscape) or three rows (portrait)
function L.reveal3(lay, P, colW)
	local r = P.R3
	local cw = lay.W
	local cols = {}
	if lay.Portrait then
		local barY = lay.BarReveal.Y
		local rowH = math.min(r.RowMax, (barY - 2 - 2 * 8 - 2) / 3)
		local rowW = cw - 24
		for j = 1, 3 do
			local pet = math.min(r.RowPet, rowH - 8)
			local col = { X = 12, Y = 2 + (j - 1) * (rowH + 8), W = rowW, H = rowH, Row = true }
			col.Pet = { X = 0, Y = (rowH - pet) / 2, S = pet }
			local rx = pet + 12
			local stack = r.BannerH + 4 + r.NameH + 4 + r.NoteH
			local ty = math.max(0, (rowH - stack) / 2)
			col.Banner = { X = rx, Y = ty, H = r.BannerH, Word = r.Word, Min = r.BannerMin, Pad = r.BannerPad, MaxW = rowW - rx, Left = true }
			col.NameX, col.NameW = rx, rowW - rx
			col.NameY, col.NameH, col.NameSize = ty + r.BannerH + 4, r.NameH, r.Name
			col.NoteY, col.NoteH, col.NoteSize = col.NameY + r.NameH + 4, r.NoteH, r.Note
			col.New = { W = r.NewW, H = r.NewH, Size = r.New, Corner = true }
			col.Ped = { X = col.X + (pet - K.LIP.W * pet) / 2, Y = col.Y + col.Pet.Y + pet - K.LIP.Up - K.LIP.H, W = K.LIP.W * pet, H = K.LIP.H }
			col.Shell = L.shell(col.Pet, true)
			cols[j] = col
		end
		lay.Cols = cols
		return
	end
	local colY = lay.PC and 20 or 2
	local colH = lay.BarReveal.Y - (lay.PC and 8 or 2) - colY
	for j = 1, 3 do
		local col = { X = cw / 2 - 1.5 * colW + (j - 1) * colW, Y = colY, W = colW, H = colH }
		local midTop = r.BannerH + r.Gap
		local fixed = r.NameGap + r.NameH + r.NoteGap + r.NoteH
		local pedK = r.Lip and 0 or r.PedH
		local pet = math.floor(Util.Clamp((colH - midTop - fixed) / (1 + pedK), r.PetMin, math.min(r.Pet, colW - 8)))
		local stack = pet * (1 + pedK) + fixed
		local top = midTop + math.max(0, (colH - midTop - stack) / 2)
		col.Banner = { Y = 0, H = r.BannerH, Word = r.Word, Min = r.BannerMin, Pad = r.BannerPad, MaxW = colW - 8 }
		col.Pet = { X = (colW - pet) / 2, Y = top, S = pet }
		col.NameY, col.NameH, col.NameSize = top + pet * (1 + pedK) + r.NameGap, r.NameH, r.Name
		col.NoteY, col.NoteH, col.NoteSize = col.NameY + r.NameH + r.NoteGap, r.NoteH, r.Note
		-- (review round 3) on a phone NEW! leaves the 18 px name's row for the pet frame's corner: beside it the name had
		-- column - 24 - 64 px (117 at 640x360, 172 at 844x390) and Legendary to Secret names were cut. PC keeps the pitch's row
		col.New = { W = r.NewW, H = r.NewH, Size = r.New, Corner = not lay.PC }
		if r.Lip then
			col.Ped = { X = col.X + (colW - K.LIP.W * pet) / 2, Y = colY + top + pet - K.LIP.Up - K.LIP.H, W = K.LIP.W * pet, H = K.LIP.H }
		else
			col.Ped = { X = col.X + (colW - r.PedW * pet) / 2, Y = colY + top + pet, W = r.PedW * pet, H = r.PedH * pet }
		end
		col.Shell = L.shell(col.Pet, r.Lip)
		cols[j] = col
	end
	lay.Cols = cols
end

----------------------------------------------------------------------
-- building
----------------------------------------------------------------------
function B.gui()
	if S.Gui and S.Gui.Parent then
		return true
	end
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return false
	end
	local old = pg:FindFirstChild(K.GUI)
	if old then
		old:Destroy()
	end
	local gui = Util.Create("ScreenGui", { Name = K.GUI, DisplayOrder = K.ORDER, IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	-- (roll-look) anchored at its centre: the burst's punch (the UIScale "Punch") grows the whole stage round the middle
	local stage = H.frame(gui, "Stage", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) })
	S.Punch = Util.Create("UIScale", { Name = "Punch", Scale = 1, Parent = stage })
	S.Dim = Util.Create("TextButton", {
		Name = "Dim", Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = K.NAVY, BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = stage,
	})
	S.Dim.Activated:Connect(function()
		H.safe("tap", H.tap)
	end)
	local vig = H.frame(stage, "Vignette", { Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	for _, e in ipairs({ { "Top", 0, 0, 1, 0.14, 90 }, { "Bottom", 0, 0.86, 1, 0.14, 270 }, { "Left", 0, 0, 0.1, 1, 0 }, { "Right", 0.9, 0, 0.1, 1, 180 } }) do
		local edge = H.frame(vig, e[1], { Position = UDim2.fromScale(e[2], e[3]), Size = UDim2.fromScale(e[4], e[5]), BackgroundColor3 = K.NAVY, BackgroundTransparency = 1, ZIndex = 2 })
		Util.Create("UIGradient", { Rotation = e[6], Transparency = NumberSequence.new(0, 1), Parent = edge })
	end
	S.Content = H.frame(stage, "Content", { ZIndex = 3 })
	S.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = S.Content })
	S.Flash = H.frame(stage, "Flash", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.WHITE, BackgroundTransparency = 1, ZIndex = 4 })
	S.Gui, S.Stage, S.Vignette = gui, stage, vig
	gui.Parent = pg
	return true
end

-- the roll's own content (rebuilt per roll): Title, Strips, Hero, Burst, Reveal, BottomBar
function B.roll(roll)
	local c = S.Content
	local P = S.Lay.P
	local title = (roll.Roulette and roll.Roulette.DisplayName) or "Hatching"
	if roll.N > 1 then
		title = title .. " x3"
	end
	roll.UI.Title = H.label(c, "Title", title, "Title", P.TitleSize, { ZIndex = 5, TextXAlignment = Enum.TextXAlignment.Center })
	roll.UI.Strips = H.frame(c, "Strips", { Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	roll.UI.Hero = H.frame(c, "Hero", { Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	local burst = H.frame(c, "Burst", { Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	roll.UI.Burst = burst
	-- (Task 27) the effects: the shock ring and the spark pool over the hero, the rays behind it (in Hero); the overlay
	-- tweens play on over the reveal's start. The pool is stepped by the phase runner (one Heartbeat in all)
	local best = roll.Pulls[roll.Best].Rarity
	roll.Shock = HatchFx.Shock(burst, best, { ZIndex = 3, Track = S.Overlay })
	roll.Rays = HatchFx.Rays(roll.UI.Hero, best, { ZIndex = 2, Track = S.Overlay })
	roll.Pool = HatchFx.Pool(burst, K.POOL, 4)
	roll.Pool:Drive()
	roll.UI.Reveal = H.frame(c, "Reveal", { Size = UDim2.fromScale(1, 1), ZIndex = 4, Visible = false })
	roll.UI.Crack = H.label(roll.UI.Hero, "CrackWord", "", "Title", S.Lay.Crack.WordH, { ZIndex = 8, Visible = false, TextXAlignment = Enum.TextXAlignment.Center })
	if roll.HasStrip then
		for j = 1, roll.N do
			B.strip(roll, j)
		end
	end
	B.bar(roll)
end

function B.strip(roll, j)
	local st = { Cells = {}, Landed = false, Tick = nil }
	local tk = K.LOOK.TRACK
	local geo = H.cardGeo(S.Lay)
	st.Frame = H.frame(roll.UI.Strips, "Strip" .. j, { ZIndex = 1 })
	-- (roll-look) the track: navy glass (a vertical gradient) in a dark rim, a thin blue edge, its ends fading out
	st.Outer = H.frame(st.Frame, "Outer", { BackgroundColor3 = tk.Outer, BackgroundTransparency = tk.OuterA, ZIndex = 0 })
	st.OuterCorner = H.corner(st.Outer, geo.TrackCorner + tk.Rim)
	st.Track = Util.Create("ScrollingFrame", {
		Name = "Track", BorderSizePixel = 0, BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ClipsDescendants = true, Active = false,
		ScrollingEnabled = false, ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = st.Frame,
	})
	Util.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(tk.Top, tk.Bottom), Parent = st.Track })
	st.TrackCorner = H.corner(st.Track, geo.TrackCorner)
	H.stroke(st.Track, tk.Edge, 2)
	st.FadeL, st.FadeR = HatchLook.TrackFades(st.Track, tk.Fade, geo.Corner)
	-- the gold winner window (its root keeps the name Pointer) and the dims beside it
	st.Pointer = H.frame(st.Frame, "Pointer", { ZIndex = 3 })
	st.Win = HatchLook.Window(st.Frame, st.Pointer, {
		Phone = not S.Lay.PC, Gold = K.GOLD, Stroke = geo.Win, Glow = geo.WinGlow, Notch = geo.Notch, Corner = geo.WinCorner, Track = S.Tweens,
		NotchEdge = roll.N == 1, -- (x3: plain notches, the budget)
	})
	if roll.Hi then
		-- (Task 27) soft speed streaks over the glass at full speed (High only; placed each frame inside the track)
		st.Streaks = H.frame(st.Frame, "Streaks", { Size = UDim2.fromScale(1, 1), ZIndex = 2 })
		st.StreakBars = {}
		local fade = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1) })
		for i = 1, 4 do
			local bar = H.frame(st.Streaks, "Streak" .. i, { BackgroundColor3 = K.WHITE, BackgroundTransparency = 1, ZIndex = 2 })
			Util.Create("UIGradient", { Transparency = fade, Parent = bar })
			st.StreakBars[i] = bar
		end
	end
	roll.Strips[j] = st
end

-- (re)builds the 12 recycled cells of a strip at the layout's cell size
function B.cells(roll, j)
	local st = roll.Strips[j]
	local g = S.Lay.Strip
	for _, cell in pairs(st.Cells) do
		HatchLook.DropCard(cell.Card)
	end
	st.Cells = {}
	st.Geo = g
	local geo = H.cardGeo(S.Lay)
	-- (roll-look) as many recycled cells as can intersect the track at once (floor(W / Step) + 2, at most 12): the dressed
	-- cards cost more, and an x3 strip of 12 went past 750 instances
	st.Slots = math.min(K.MAX_CELLS, math.floor(g.W / g.Step) + 2)
	for slot = 1, st.Slots do
		local f = H.frame(st.Track, "Cell" .. slot, { Size = UDim2.fromOffset(g.CellW, g.CellH), BackgroundColor3 = K.CELL, BackgroundTransparency = 0.15, Visible = false, ZIndex = 2 })
		H.corner(f, 12)
		local stroke = H.stroke(f, Theme.Colors.WellEdge, 3)
		-- (roll-look, spec 16.15) the glossy card: a navy face with the rarity tint, the rim, a shine line; x1 adds the
		-- rarity plate holding the word and a shadow beside the cell (x3: lite, <= 16 instances a cell)
		local card = HatchLook.Card(f, {
			W = g.CellW, H = g.CellH, Corner = geo.Corner, Shadow = geo.Shadow, Shine = geo.Shine, Plate = geo.Plate, Word = g.Word,
			Lite = roll.N > 1, Phone = not S.Lay.PC,
		})
		-- (Task 26) a lean egg: no rim light and <= 9 instances (spec 16.15: <= 20 per x1 cell, the card included)
		local egg = EggArt.New(f, "Common", g.Egg, { Form = g.Egg < 48 and "Simple" or "Medium", ZIndex = 3, Rim = false, Budget = 9 })
		egg.AnchorPoint = Vector2.new(0.5, 0)
		local word = card.PlateText
		if word then
			-- the egg stands in the room above the plate, a little low (its top keeps clear of the shine line)
			local plateY = card.Plate.Position.Y.Offset
			egg.Position = UDim2.fromOffset(g.CellW / 2, math.max(g.CellH * 0.06, (plateY - g.Egg) * 0.55))
		elseif g.Word then
			-- (an x3 card's word: the text stroke only, no outline instance: the x3 budget)
			egg.Position = UDim2.fromOffset(g.CellW / 2, g.CellH * 0.08)
			word = Theme.Label("", "Heading", { Size = g.Word, Stroke = 0.2 })
			word.Name = "Word"
			word.ZIndex = 3
			word.Position = UDim2.fromOffset(0, g.CellH * 0.08 + g.Egg + 2)
			word.Size = UDim2.fromOffset(g.CellW, g.Word + 4)
			word.Parent = f
		else
			egg.Position = UDim2.fromOffset(g.CellW / 2, (g.CellH - g.Egg) / 2)
		end
		st.Cells[slot] = { Frame = f, Stroke = stroke, Egg = egg, Word = word, Index = nil, Card = card, OnPlate = word ~= nil and word == card.PlateText }
	end
end

-- (roll-look) the card and window sizes of this layout: the PC / phone table at the 1080p x1 strip, scaled with the cells
-- when they are smaller (x3, a shrunk strip); the plate never gets shorter than its word; an x3 phone's strips sit 6 px
-- apart, so their windows go without notches
function H.cardGeo(lay)
	local base = lay.PC and K.LOOK.PC.Card or K.LOOK.PHONE.Card
	local g = lay.Strip
	local k = math.min(1, g.CellH / lay.P.Strip1.CellH)
	local function px(v)
		return math.max(1, math.floor(v * k + 0.5))
	end
	local geo = {
		Corner = px(base.Corner), Shadow = px(base.Shadow), Shine = px(base.Shine), Plate = math.max(px(base.Plate), (g.Word or 0) + 6), Pad = px(base.Pad),
		Win = math.max(2, math.floor(base.Win * math.max(k, 0.6) + 0.5)), WinGlow = math.max(3, math.floor(base.WinGlow * math.max(k, 0.6) + 0.5)),
		Notch = (lay.X3 and not lay.PC) and 0 or px(base.Notch),
	}
	geo.WinCorner = geo.Corner + math.floor(geo.Pad / 2 + 0.5)
	geo.TrackCorner = math.min(geo.Corner + geo.Pad, math.floor(g.H / 2))
	return geo
end

-- the cell showing the winner (strip index K.WIN) once the strip has landed
function H.landedCell(st)
	for _, cell in pairs(st.Cells) do
		if cell.Index == K.WIN then
			return cell
		end
	end
	return nil
end

function B.bar(roll)
	local P = S.Lay.P
	local phone = not S.Lay.PC
	local bar = H.frame(S.Content, "BottomBar", { ZIndex = 6 })
	roll.UI.Bar = bar
	-- (roll-look, spec 16.15) the small chips (a 44 px tap box drawing a 36 / 32 px pill) and the glossy pills (HatchLook)
	roll.UI.Skip = HatchLook.Chip(bar, { Name = "Skip", Text = "", TextSize = P.Bar.ChipText, Phone = phone, ZIndex = 6 })
	roll.UI.Skip.Activated:Connect(function()
		H.safe("tap", H.tap)
	end)
	-- (review round 2) DONE and SPIN AGAIN read Activated themselves: a tap on them while they are not armed still counts
	-- as a tap and restarts the wait (H.press)
	roll.UI.Done = HatchLook.Pill(bar, { Name = "Done", Kind = "Green", Text = "DONE", TextSize = P.Bar.Text, Phone = phone, ZIndex = 6 })
	roll.UI.Done.Activated:Connect(function()
		H.safe("done", H.doneTap)
	end)
	local again = HatchLook.Pill(bar, { Name = "SpinAgain", Kind = "Gold", Text = "SPIN AGAIN", TextSize = P.Bar.Text, Price = true, Coin = P.Bar.Coin, Phone = phone, ZIndex = 6 })
	again.Activated:Connect(function()
		H.safe("again", H.againTap)
	end)
	local parts = HatchLook.PillParts(again)
	local z = parts.Coin.ZIndex
	if roll.Currency == "Gems" then
		local gem = GemIcon.New(parts.Coin, P.Bar.Coin, { ZIndex = z })
		gem.Position = UDim2.fromOffset(0, 0)
	else
		NeonKit.Icon(parts.Coin, "Tokens", P.Bar.Coin).ZIndex = z
	end
	roll.UI.Again, roll.UI.AgainLabel, roll.UI.AgainCoin, roll.UI.AgainPrice = again, parts.Label, parts.Coin, parts.Price
	-- the pills' rise (spec 16.15 "Pills"): one NumberValue tweened 0 -> 1 drives both (H.pillsIn)
	roll.UI.Pills = { again, roll.UI.Done }
	roll.UI.PillParts = { parts, HatchLook.PillParts(roll.UI.Done) }
	roll.UI.Rise = {}
	local pillsIn = Util.Create("NumberValue", { Name = "PillsIn", Value = 1, Parent = bar })
	roll.PillsIn = pillsIn
	pillsIn:GetPropertyChangedSignal("Value"):Connect(function()
		H.pillsIn(roll, pillsIn.Value)
	end)
	-- the Fast hatch chip (ClientSettings FastHatch: the profile, every device)
	local fast = HatchLook.FastChip(bar, { Name = "FastHatch", TextSize = P.Bar.FastText, Phone = phone, ZIndex = 6 })
	fast.Activated:Connect(function()
		H.safe("fast", function()
			ClientSettings.Set("FastHatch", ClientSettings.Get("FastHatch") ~= true)
		end)
	end)
	roll.UI.Fast = fast
	H.paintFast(roll)
end

function H.paintFast(roll)
	local fast = roll and roll.UI.Fast
	if fast and fast.Parent then
		HatchLook.SetFast(fast, ClientSettings.Get("FastHatch") == true)
	end
end

-- (roll-look) the pills' rise at k (0 = low and clear .. 1 = in place); H.applyBar keeps each pill's rise on the screen
function H.pillsIn(roll, k)
	roll.PillK = k
	for i, btn in ipairs(roll.UI.Pills or {}) do
		if btn.Parent then
			HatchLook.PillIn(roll.UI.PillParts[i], k, roll.UI.Rise[btn.Name] or 0)
		end
	end
end

-- the reveal columns (one per pull, in the server's order)
function B.cols(roll)
	local reveal = roll.UI.Reveal
	local lay = S.Lay
	local brief = #roll.Pulls > 1 -- (review round 3) an x3 column's note leaves the name out: it sits right above
	for j, pull in ipairs(roll.Pulls) do
		local col = H.frame(reveal, "Col" .. j, { ZIndex = 4 })
		-- (roll-look, spec 16.15 "Reveal word") the Banner is the word's box (no plate, no border): the rarity word as
		-- letters (gradient, outline, glow) popping in turn; an x3 phone column keeps one label
		local banner = H.frame(col, "Banner", { ZIndex = 5 })
		local g = lay.Cols[j]
		local word = HatchLook.Word(banner, string.upper(pull.Rarity) .. "!", pull.Rarity, g and g.Banner.Word or 22, {
			Letters = lay.PC or roll.N == 1, ZIndex = 6, Measure = H.titleW,
		})
		if pull.Rarity == "Secret" then
			-- (Task 27) Secret's violet aura: a soft ring behind the pet, inside its frame
			local aura = H.frame(col, "Aura", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = K.AURA, BackgroundTransparency = 0.8, ZIndex = 4 })
			H.corner(aura, 0.5)
			Util.Create("UIStroke", { Color = K.AURA, Thickness = 3, Transparency = 0.6, Parent = aura })
			Util.Create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.9), NumberSequenceKeypoint.new(1, 0.2) }), Rotation = 90, Parent = aura })
		end
		local shell = H.frame(col, "Shell", { ZIndex = 4 })
		local pet = H.frame(col, "Pet", { ZIndex = 5 })
		local pop = Util.Create("UIScale", { Name = "Pop", Scale = 0, Parent = pet })
		local stage = 0
		local okStage, st = pcall(PetBits.stage, pull.Key)
		if okStage and type(st) == "number" then
			stage = st
		end
		local view = CloudUI.PetViewport(pet, pull.Def, UDim2.fromScale(1, 1), {
			Spin = "spin", Excited = 1, Flap = 1.5, ZIndex = 5, Evolved = stage >= 1 and stage or nil, Detail = stage >= 1 and "Low" or nil,
		})
		roll.Views[#roll.Views + 1] = view
		local vf = view and view.Frame
		if vf and not vf:IsA("ViewportFrame") then
			vf = vf:FindFirstChildWhichIsA("ViewportFrame", true)
		end
		-- (roll-look, the mock's sceneA) the name white in the round display face with the ink outline under the coloured word
		local name = H.label(col, "Name", pull.Def.Name, "Display", 18, { ZIndex = 5, TextColor3 = K.WHITE, TextTruncate = Enum.TextTruncate.AtEnd })
		-- (ZIndex 6 / 7 like the EvolvedRibbon: on a phone's x3 it sits on the pet frame's corner, over the pet's view)
		-- (roll-look) NEW! is a small gold pill with ink text (the mock's newPill), popping in at the chain's SIL + 0.4
		local new = H.frame(col, "New", { BackgroundColor3 = K.WHITE, BackgroundTransparency = 0, ZIndex = 6, Visible = pull.IsNew })
		H.corner(new, 0.5)
		Util.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 224, 138), Color3.fromRGB(240, 166, 52)), Parent = new })
		H.stroke(new, K.LOOK.NEW.Edge, 2)
		local newText = Theme.Label("NEW!", "Button", { Size = 15, Stroke = 1 })
		newText.Name, newText.Size, newText.ZIndex, newText.TextColor3, newText.Parent = "Text", UDim2.fromScale(1, 1), 7, K.LOOK.NEW.Ink, new
		local newPop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = new })
		local note = H.label(col, "Note", EggStage.NoteText(pull, pull.Rarity, brief), "Body", 15, { ZIndex = 5, TextWrapped = true, TextColor3 = Theme.Colors.Muted })
		if stage >= 1 then
			local ribbon = H.frame(col, "EvolvedRibbon", { BackgroundColor3 = K.GOLD, BackgroundTransparency = 0, Rotation = 8, ZIndex = 6 })
			H.corner(ribbon, 10)
			H.stroke(ribbon, K.INK, 2)
			H.label(ribbon, "Text", stage >= 2 and "Evolved II" or "Evolved", "Button", 15, { Size = UDim2.fromScale(1, 1), ZIndex = 7 })
		end
		-- the chain's fades: { object, property, its shown value } (the name and note: their text, classic stroke, outline)
		local fade = {}
		for _, l in ipairs({ name, note }) do
			fade[#fade + 1] = { l, "TextTransparency", 0 }
			fade[#fade + 1] = { l, "TextStrokeTransparency", l.TextStrokeTransparency }
			local outline = l:FindFirstChild("TextOutline")
			if outline then
				fade[#fade + 1] = { outline, "Transparency", outline.Transparency }
			end
		end
		roll.Cols[j] = {
			Root = col, Shell = shell, Pet = pet, Pop = pop, Banner = banner, Word = word, Name = name, New = new, NewPop = newPop, Note = note, View = vf, Fade = fade, Rest = {},
			Sil = H.order(pull.Rarity) >= K.LOOK.SIL.From,
		}
	end
	-- the name / NEW! / note rise (spec 16.15): one NumberValue tweened 0 -> 1 drives every column (H.textIn)
	local textIn = Util.Create("NumberValue", { Name = "TextIn", Value = 1, Parent = reveal })
	roll.TextIn = textIn
	textIn:GetPropertyChangedSignal("Value"):Connect(function()
		H.textIn(roll, textIn.Value)
	end)
end

-- the stage's text widths in the Title face (the reveal word's letters)
function H.titleW(text, size)
	return H.textW(text, size, "Title")
end

-- (roll-look) the name / NEW! / note at k (0 = 16 px low and clear .. 1 = at their layout places, shown)
function H.textIn(roll, k)
	roll.TextK = k
	local rise = (1 - k) * K.LOOK.CHAIN.TextRise
	for _, c in pairs(roll.Cols) do
		for key, at in pairs(c.Rest or {}) do
			c[key].Position = at + UDim2.fromOffset(0, rise)
		end
		for _, f in ipairs(c.Fade or {}) do
			f[1][f[2]] = 1 - k * (1 - f[3])
		end
	end
end

----------------------------------------------------------------------
-- applying the layout (snaps: called on build, on the reveal and after a resize)
----------------------------------------------------------------------
function H.apply()
	local roll, lay = S.Roll, S.Lay
	if not roll or not lay or not S.Content then
		return
	end
	S.Content.Position = UDim2.fromOffset(0, lay.Top)
	S.Content.Size = UDim2.fromOffset(lay.W, lay.H)
	S.Fit.Scale = lay.Scale
	local title = roll.UI.Title
	if title then
		H.place(title, 12, lay.Title.Y, lay.W - 24, lay.Title.H)
		title.TextSize = lay.Title.Size
		title.Visible = not roll.Revealed
	end
	H.applyStrips(roll, lay)
	H.applyHero(roll, lay)
	H.applyReveal(roll, lay)
	H.applyBar(roll, lay)
end

function H.applyStrips(roll, lay)
	local g = lay.Strip
	local geo = H.cardGeo(lay)
	local rim = K.LOOK.TRACK.Rim
	local band = (g.H - g.CellH) / 2
	local fw = math.floor(K.LOOK.TRACK.FadeW * g.W + 0.5)
	for j, st in pairs(roll.Strips) do
		H.place(st.Frame, g.X, g.Y[j], g.W, g.H)
		if st.Outer then
			H.place(st.Outer, -rim, -rim, g.W + 2 * rim, g.H + 2 * rim)
			st.OuterCorner.CornerRadius = UDim.new(0, geo.TrackCorner + rim)
		end
		st.TrackCorner.CornerRadius = UDim.new(0, geo.TrackCorner)
		-- the ends fade over the card band (the track's own gradient shows above and below it)
		H.place(st.FadeL, 0, band, fw, g.CellH)
		H.place(st.FadeR, g.W - fw, band, fw, g.CellH)
		for _, fade in ipairs({ st.FadeL, st.FadeR }) do
			fade:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, geo.Corner)
		end
		if st.Geo ~= g then
			B.cells(roll, j)
		end
		-- the gold window round the landed cell's box + Pad a side, the dims beside it over the track
		st.Win:Style({ Stroke = geo.Win, Glow = geo.WinGlow, Notch = geo.Notch, Corner = geo.WinCorner })
		st.Win:Place(g.W / 2 - g.CellW / 2 - geo.Pad, band - geo.Pad, g.CellW + 2 * geo.Pad, g.CellH + 2 * geo.Pad, g.W, g.H)
		R.cells(roll, j, st.C or K.START_CELL)
	end
end

function H.applyHero(roll, lay)
	local cr = lay.Crack
	if roll.Spot then
		-- one light cone from above the word onto the pedestal(s)
		local w = K.SPOT * cr.E + (roll.N > 1 and (cr.Cx[3] - cr.Cx[1]) or 0)
		w = math.min(w, lay.W - 8)
		local y = math.max(0, cr.WordY - 0.2 * cr.E)
		H.place(roll.Spot, lay.W / 2 - w / 2, y, w, cr.EggY + cr.E + 0.6 * cr.PedH - y)
		roll.Spot.Visible = not roll.Revealed
	end
	for j, e in pairs(roll.Eggs) do
		local cx = cr.Cx[j]
		local eggY = cr.EggY
		if e.Egg and e.Egg.Parent then
			-- the egg stands on its foot (AnchorPoint 0.5, 1): the push-in grows it upward, never into the pedestal
			H.sizeEgg(e.Egg, cr.E)
			e.Egg.Position = UDim2.fromOffset(cx, eggY + cr.E)
			e.Pop.Scale = 1
			e.Egg.Rotation = 0
			e.Egg.Visible = e.State == "Rise" or e.State == "Crack"
		end
		if e.Ring then
			-- (roll-look) never past the screen's edge (a portrait x3's outer columns)
			e.Ring:Place(cx, eggY + cr.E / 2, math.min(K.RING * cr.E, 2 * math.min(cx, lay.W - cx)))
		end
		if e.Back then
			local d = 0.96 * cr.E
			H.place(e.Back, cx - d / 2, eggY + (cr.E - d) / 2, d, d)
		end
		if e.Holder and e.Holder.Parent then
			if e.State == "Crack" and e.HolderSize ~= cr.E then
				e.Holder:Destroy()
				e.Holder = nil
				B.halves(roll, j)
			elseif e.State ~= "Crack" and e.HolderSize ~= cr.E then
				e.Holder.Visible = false
			end
		end
		if e.Ped then
			-- (roll-look) the box is anchored at its top centre (the plinth pops round the egg's foot)
			local pcx, pw
			if roll.Revealed and lay.Cols[j] then
				local p = lay.Cols[j].Ped -- (in Content's space: Hero fills Content)
				pcx, pw = p.X + p.W / 2, p.W
				H.place(e.Ped, pcx, p.Y, p.W, p.H)
				H.pedLook(e.Ped, p.H < 20)
			else
				pcx, pw = cx, cr.PedW
				H.place(e.Ped, cx, eggY + cr.E, cr.PedW, cr.PedH)
				H.pedLook(e.Ped, false)
			end
			if e.Plinth then
				-- the halo never past the screen's edge (a portrait x3's outer columns)
				e.Plinth:FitGlow(2 * math.min(pcx, lay.W - pcx) / math.max(1, pw))
			end
		end
	end
	H.placeWord(roll, lay)
	-- the rays: round the last egg that burst (or the egg of Gemini's tweak), or behind the best pet on the reveal
	if roll.Rays then
		local at = roll.RaysAt or roll.TweakRays
		if roll.Revealed then
			local g = lay.Cols[roll.Best]
			if g then
				roll.Rays:Place(g.X + g.Pet.X + g.Pet.S / 2, g.Y + g.Pet.Y + g.Pet.S / 2, 2.2 * g.Pet.S)
			end
		elseif at then
			roll.Rays:Place(cr.Cx[at], cr.EggY + cr.E / 2, K.RAYS * cr.E)
		end
	end
end

-- the crack word, centred over the hero, as wide as its text
function H.placeWord(roll, lay)
	local word = roll.UI.Crack
	if word and lay then
		local cr = lay.Crack
		word.TextSize = cr.WordH
		local w = math.min(lay.W - 24, H.textW(word.Text, cr.WordH, "Title") + 40)
		H.place(word, (lay.W - w) / 2, cr.WordY, w, cr.WordH)
	end
end

-- the pedestal's look: the flat lit plinth (roll-look: Top, Side, Ring, the glow), or only its Top as the thin lip a
-- phone's reveal pet stands on
function H.pedLook(ped, lip)
	if ped:GetAttribute("Lip") == lip then
		return
	end
	ped:SetAttribute("Lip", lip)
	for _, c in ipairs(ped:GetChildren()) do
		if c:IsA("GuiObject") and c.Name ~= "Top" then
			c.Visible = not lip
		end
	end
	HatchLook.PlinthLip(ped, lip)
end

function H.applyReveal(roll, lay)
	if not roll.Revealed then
		return
	end
	for j, c in pairs(roll.Cols) do
		local g = lay.Cols[j]
		if g then
			H.place(c.Root, g.X, g.Y, g.W, g.H)
			local banner, word = c.Banner, c.Word
			if word then
				-- (roll-look) the word at its layout size (a landscape phone's right column: down to WordMin when it is long)
				local maxW = g.Banner.MaxW or (g.W - 24)
				local size = g.Banner.Word
				word:SetSize(size)
				if g.Banner.WordMin and word:Width() > maxW - 8 then
					size = math.max(g.Banner.WordMin, math.floor(size * (maxW - 8) / word:Width()))
					word:SetSize(size)
				end
				local bw = math.min(math.max(g.Banner.Min, word:Width() + g.Banner.Pad), maxW)
				local bx = g.Banner.Left and g.Banner.X or (g.Banner.CX and (g.Banner.CX - bw / 2)) or (g.W - bw) / 2
				H.place(banner, bx, g.Banner.Y, bw, g.Banner.H)
				-- (its glow stays on the screen: the room above the word's top and to the nearer side, in Content's px)
				local top, cx = g.Y + g.Banner.Y + (g.Banner.H - size) / 2, g.X + bx + bw / 2
				word:Place(bw / 2, (g.Banner.H - size) / 2, { Up = math.max(0, top - 1), Half = math.max(0, math.min(cx, lay.W - cx) - 1) })
			end
			H.place(c.Pet, g.Pet.X + g.Pet.S / 2, g.Pet.Y + g.Pet.S / 2, g.Pet.S, g.Pet.S)
			c.Pet.AnchorPoint = Vector2.new(0.5, 0.5)
			local aura = c.Root:FindFirstChild("Aura")
			if aura then
				-- a soft halo just inside the pet's frame (clear of the shell and the pedestal under it)
				H.place(aura, g.Pet.X + g.Pet.S / 2, g.Pet.Y + g.Pet.S * 0.47, g.Pet.S * 0.86, g.Pet.S * 0.86)
			end
			local sh = g.Shell
			local shellX, shellY = sh.X, sh.Y
			H.place(c.Shell, shellX, shellY, sh.W, sh.H)
			if c.ShellEgg ~= sh.Egg then
				c.Shell:ClearAllChildren()
				local top, bottom = EggArt.Halves(c.Shell, roll.Pulls[j].Rarity, sh.Egg)
				top:Destroy()
				bottom.Position = UDim2.fromOffset(0, 0)
				c.ShellEgg = sh.Egg
			end
			-- the name (+ NEW!) row, then the note
			local name, new, note = c.Root:FindFirstChild("Name"), c.Root:FindFirstChild("New"), c.Root:FindFirstChild("Note")
			local ribbon = c.Root:FindFirstChild("EvolvedRibbon")
			local rw = math.min(g.Pet.S, lay.PC and 150 or 96)
			local rh = lay.PC and 36 or 24
			local nx, nw = g.NameX or 12, g.NameW or (g.W - 24)
			local corner = g.New.Corner == true
			local newW = (new and new.Visible and not corner) and (g.New.W + 8) or 0
			local textW = math.min(nw - newW, H.textW(name.Text, g.NameSize, "Display") + 8)
			local rowX = g.Row and nx or (nx + (nw - textW - newW) / 2)
			name.TextSize = g.NameSize
			H.place(name, rowX, g.NameY, textW, g.NameH)
			if new then
				if corner then
					-- (review round 3) the pet frame's top-left corner, the EvolvedRibbon's mirror (tilted the other way), under the
					-- ribbon when both show (a narrow pet's ribbon spans the whole frame; 10 px apart so the two tilts stay clear);
					-- the name keeps its whole row
					local ny = g.Pet.Y + 0.12 * g.Pet.S + (ribbon and (rh + 10) or 0)
					H.place(new, g.Pet.X, ny, g.New.W, g.New.H)
					new.Rotation = -8
				else
					H.place(new, rowX + textW + 8, g.NameY + (g.NameH - g.New.H) / 2, g.New.W, g.New.H)
					new.Rotation = K.LOOK.NEW.Tilt
				end
				local t = new:FindFirstChild("Text")
				if t then
					t.TextSize = g.New.Size
				end
			end
			note.TextSize = g.NoteSize
			note.TextXAlignment = g.Row and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
			H.place(note, nx, g.NoteY, nw, g.NoteH)
			if ribbon then
				H.place(ribbon, g.Pet.X + g.Pet.S - rw, g.Pet.Y + 0.12 * g.Pet.S, rw, rh) -- inside the pet frame, clear of the banner
				local t = ribbon:FindFirstChild("Text")
				if t then
					t.TextSize = lay.PC and 20 or 15
				end
			end
			c.Pop.Scale = roll.PopDone and 1 or c.Pop.Scale
			-- (roll-look) the rest places the chain's rise ends at (H.textIn)
			c.Rest.Name, c.Rest.New, c.Rest.Note = name.Position, new and new.Position or nil, note.Position
		end
	end
	if roll.TextK and roll.TextK < 1 then
		H.textIn(roll, roll.TextK)
	end
end

function H.applyBar(roll, lay)
	local bar = roll.Revealed and lay.BarReveal or lay.BarRoll
	H.place(roll.UI.Bar, 0, bar.Y, lay.W, bar.H)
	local P = lay.P
	local phone = not lay.PC
	-- (roll-look) the chips' text with the chevrons, the chips' and pills' sizes of this layout
	local verb = roll.Revealed and "close" or "skip"
	HatchLook.SetChipText(roll.UI.Skip, (lay.PC and "Tap anywhere to " or "Tap to ") .. verb .. " " .. K.LOOK.CHEVRONS)
	HatchLook.SizeChip(roll.UI.Skip, P.Bar.ChipText, phone)
	HatchLook.SizeChip(roll.UI.Fast, P.Bar.FastText, phone)
	for _, btn in ipairs(roll.UI.Pills) do
		HatchLook.SizePill(btn, P.Bar.Text, phone, P.Bar.Coin)
	end
	for _, name in ipairs({ "Skip", "FastHatch", "SpinAgain", "Done" }) do
		local o = roll.UI.Bar:FindFirstChild(name)
		local it = bar.Items[name]
		if o then
			o.Visible = it ~= nil
			if it then
				H.place(o, it.x, it.y, it.w, it.h)
				-- the pills rise PillsRise px into place, less where the screen's bottom edge is nearer (never off it)
				roll.UI.Rise[name] = math.max(0, math.min(K.LOOK.CHAIN.PillsRise, lay.H - (bar.Y + it.y + it.h) - 1))
			end
		end
	end
	H.paintFast(roll)
	H.refreshAgain()
	if roll.PillK then
		H.pillsIn(roll, roll.PillK)
	end
end

-- SPIN AGAIN: the same roulette, currency and spins; disabled with the reason when it cannot be paid or is locked, and
-- (review round 2) SPIN AGAIN and DONE both disabled until the reveal is armed (H.armed: the label and price stay)
function H.refreshAgain()
	local roll = S.Roll
	if not roll then
		return
	end
	local armed = H.armed()
	roll.Armed = armed
	local done = roll.UI.Done
	if done and done.Parent then
		CloudUI.SetDisabled(done, not armed)
	end
	local btn = roll.UI.Again
	if not btn or not btn.Parent then
		return
	end
	local roulette = roll.Roulette
	if not roulette then
		btn.Visible = false
		return
	end
	local price = H.price(roulette, roll.Currency) * roll.N
	local reason = nil
	if H.inMatch() then
		reason = "Shop closed"
	elseif roll.Currency == "Gems" and not H.gemsOpen() then
		reason = "Locked"
	elseif H.balance(roll.Currency) < price then
		reason = roll.Currency == "Gems" and "Not enough Gems" or "Not enough Tokens"
	end
	local lbl = roll.UI.AgainLabel
	lbl.Text = reason or ((roll.N > 1) and "SPIN AGAIN x3" or "SPIN AGAIN")
	local priceText = (S.Lay and S.Lay.PC) and Util.Commas(price) or Theme.ShortNumber(price)
	local chipW = 0
	if reason == nil then
		-- (review round 3) measured with the real fonts (TextService): a label that would not fit beside the price chip (its
		-- content's width at the least) takes the short price ("3K"); (roll-look) the chip holds the coin and the price
		local labelW = H.textW(lbl.Text, lbl.TextSize, "Button")
		local fits
		chipW, fits = HatchLook.FitPill(btn, labelW, H.textW(priceText, roll.UI.AgainPrice.TextSize, "Display"))
		if not fits then
			priceText = Theme.ShortNumber(price, 1000)
			chipW = HatchLook.FitPill(btn, labelW, H.textW(priceText, roll.UI.AgainPrice.TextSize, "Display"))
		end
	end
	roll.UI.AgainPrice.Text = priceText
	HatchLook.SetPillChip(btn, chipW) -- (a reason: no chip, the label takes the whole pill)
	CloudUI.SetDisabled(btn, reason ~= nil or S.Pending or not armed)
end

----------------------------------------------------------------------
-- the phase runner (one Heartbeat while the stage shows)
----------------------------------------------------------------------
function R.phaseAt(roll, t)
	local s = roll.Sched
	if t < s.IntroEnd then
		return "Intro"
	elseif roll.HasStrip and t < s.StripEnd then
		return "Strip"
	elseif roll.HasStrip and t < s.LandEnd then
		return "Land"
	elseif t < s.RiseEnd then
		return "Rise"
	elseif t < s.BurstAt[roll.N] then
		return "Crack"
	elseif t < s.RevealAt then
		return "Burst"
	end
	return "Reveal"
end

-- lays the strip's cells out with the pointer over position c (cell i spans i-1 .. i); at most 12 cells intersect
function R.cells(roll, j, c)
	local st = roll.Strips[j]
	local g = st and st.Geo
	if not g then
		return
	end
	st.C = c
	local half = g.W / 2
	local rarities = roll.Pulls[j].Rarities or {}
	local used = st.Used or {} -- (one table per strip, cleared each frame: no per-frame garbage)
	st.Used = used
	for slot in pairs(used) do
		used[slot] = nil
	end
	local first = math.max(1, math.floor(c - half / g.Step) - 1)
	local last = math.min(K.STRIP_LEN, math.ceil(c + half / g.Step) + 1)
	for i = first, last do
		local x = half + (i - 1 - c) * g.Step + (g.Step - g.CellW) / 2
		if x + g.CellW > 0 and x < g.W then
			local slot = ((i - 1) % (st.Slots or K.MAX_CELLS)) + 1
			local cell = st.Cells[slot]
			if cell and not used[slot] then
				used[slot] = true
				if cell.Index ~= i then
					cell.Index = i
					cell.Frame:SetAttribute("Index", i)
					local rarity = rarities[i]
					local landed = st.Landed and i == K.WIN
					local egg = cell.Egg -- (nil once the winner's egg has lifted out at the rise: the hero egg left its card)
					if egg then
						egg.Visible = rarity ~= false and rarity ~= nil and not (landed and st.Lifted)
						if rarity then
							EggArt.SetRarity(egg, rarity)
						end
					end
					-- (roll-look, spec 16.15) the card by rarity: the face tint, the rim (Rare and up opaque in Shade(c, .05),
					-- below Shade(c, -.1) at 0.25), the plate's word; the landed card's rim is 5 thick and its egg gets its
					-- VFX, the others dim to 0.6 once the strip has landed
					HatchLook.SetCard(cell.Card, rarity or false, landed and "Landed" or (st.Landed and "Dim") or "Idle")
					if cell.Word and not cell.OnPlate then
						cell.Word.Text = rarity or ""
						cell.Word.TextColor3 = H.color(rarity)
					end
					if egg and (cell.Vfx == true) ~= (landed and rarity ~= nil and rarity ~= false) then
						cell.Vfx = landed and rarity ~= nil and rarity ~= false
						EggArt.SetVfx(egg, cell.Vfx)
					end
				end
				-- (placed by its centre: the land pop grows round the middle; its shadow follows)
				HatchLook.ShowCard(cell.Card, x + g.CellW / 2, g.H / 2)
			end
		end
	end
	for slot, cell in pairs(st.Cells) do
		if not used[slot] then
			HatchLook.HideCard(cell.Card)
		end
	end
end

function R.land(roll, j)
	local st = roll.Strips[j]
	st.Landed = true
	st.Frame:SetAttribute("Landed", true)
	local rarity = roll.Pulls[j].Rarity
	H.sfx(K.SOUND.Land, H.scaleFor(rarity))
	for _, cell in pairs(st.Cells) do
		cell.Index = nil -- re-skin with the landed look on the next layout
	end
	R.cells(roll, j, st.C or K.START_CELL)
	-- (roll-look) the winner has passed the window by the overshoot: the Back Out spring (R.landStep, from the next frame)
	-- brings it back over Land; the window bounces, the landed card pops once with one shine sweep
	local g = st.Geo
	st.Over = g and (roll.Fast and K.LOOK.OVERSHOOT.Fast or K.LOOK.OVERSHOOT.Px) * g.S or 0
	st.Fresh, st.Settled = true, false
	if st.Win then
		st.Win:Bounce(roll.T.Land)
	end
	local cell = H.landedCell(st)
	if cell then
		HatchLook.LandPop(cell.Card, roll.Fast, S.Tweens)
	end
end

-- (roll-look) one frame of the land: the landed strips spring back from the overshoot (Back Out, the rise's curve) and
-- the track darkens round the window; a strip rests once its Land is over
function R.landStep(roll, t)
	for j, st in pairs(roll.Strips) do
		if st.Landed and not st.Settled and st.Geo then
			if st.Fresh then
				st.Fresh = nil -- (the land's own frame shows the whole overshoot)
			else
				local k = Util.Clamp((t - roll.Sched.Land[j]) / math.max(0.01, roll.T.Land), 0, 1)
				local back = 1 + 2.70158 * (k - 1) ^ 3 + 1.70158 * (k - 1) ^ 2
				R.cells(roll, j, K.WIN - 0.5 + (st.Over or 0) * (1 - back) / st.Geo.Step)
				if st.Win then
					st.Win:SetDim(k)
				end
				st.Settled = k >= 1
			end
		end
	end
end

-- (roll-look) B's colour tell: from Rare up the window, its glow and its notches turn the coming rarity's colour a moment
-- before the strip stops (Common / Uncommon keep the gold: no fake tease); x3: each strip its own pull's colour
function R.tell(roll, j, t)
	local st = roll.Strips[j]
	local rarity = roll.Pulls[j].Rarity
	if st.Told or not st.Win or H.order(rarity) < 3 then
		return
	end
	local tl = K.LOOK.TELL
	if t >= roll.Sched.Land[j] - (roll.Fast and tl.Fast or tl.Before) then
		st.Told = true
		st.Win:Tell(H.color(rarity), roll.Fast and tl.TweenFast or tl.Tween)
	end
end

-- the speed streaks: as bright as the strip is fast (the ease's slope), sliding left, always inside the track
function R.streaks(st, t, p)
	local g = st.Geo
	if not st.StreakBars or not g then
		return
	end
	local a = Util.Clamp(((1 - p) ^ (K.CURVE - 1) - 0.3) / 0.7, 0, 1)
	local bw = g.W * 0.32
	for i, bar in ipairs(st.StreakBars) do
		local u = (i * 0.29 + t * 2.4) % 1
		bar.Position = UDim2.fromOffset((g.W - bw) * (1 - u), g.H * (0.14 + 0.18 * i))
		bar.Size = UDim2.fromOffset(bw, math.max(2, math.floor(3 * g.S + 0.5)))
		bar.BackgroundTransparency = 1 - 0.55 * a
	end
end

function R.strips(roll, t)
	local s = roll.Sched
	for j, st in pairs(roll.Strips) do
		-- (a landed strip belongs to R.landStep)
		if not st.Landed then
			local dur = math.max(0.01, s.Land[j] - s.IntroEnd)
			local p = Util.Clamp((t - s.IntroEnd) / dur, 0, 1)
			-- (roll-look, spec 16.15) today's ease plus the overshoot past the winner over its last stretch (p ^ 8)
			local g = st.Geo
			local over = g and (roll.Fast and K.LOOK.OVERSHOOT.Fast or K.LOOK.OVERSHOOT.Px) * g.S / g.Step or 0
			local c = K.START_CELL + (K.WIN - 0.5 - K.START_CELL) * (1 - (1 - p) ^ K.CURVE) + over * p ^ 8
			R.tell(roll, j, t)
			R.cells(roll, j, c)
			R.streaks(st, t, p)
			local cell = math.floor(c)
			if st.Tick ~= cell then
				if st.Tick ~= nil and j == 1 and p < 1 and os.clock() - (roll.LastTick or -1) >= 1 / K.TICKS_PER_S then
					roll.LastTick = os.clock()
					H.sfx(K.SOUND.Tick, K.QUIET)
				end
				st.Tick = cell
			end
			if p >= 1 then
				R.land(roll, j)
			end
		end
	end
end

-- the pedestal's box (spec 16.4 "Spot, Backlight, Pedestal"): the layout anchor the egg, the halves and the pet stand on,
-- from 420 x 90 down to a phone's 12 px lip. The owner (2026-11-08) had the cloud-stone drum removed ("the useless bars
-- below the pet"); roll-look (spec 16.15) draws a flat lit plinth in it instead (HatchLook.Plinth: a disc centred on
-- the egg's foot, its thin side, an inner ring and a soft halo; nothing stacked under it). It starts neutral.
function B.pedestal(hero, j, rarity, e)
	local box = H.frame(hero, "Pedestal" .. j, { ZIndex = 5 })
	-- (x3: one halo disc under the smaller plinths, the 750-instance budget)
	e.Plinth = HatchLook.Plinth(box, rarity, not S.Lay.PC, { Track = S.Tweens, Glows = S.Roll and S.Roll.N > 1 and 1 or 2 })
	return box
end

-- the rarity backlight: four stacked round glows, as strong as the egg's glow (none for Common / Uncommon)
function B.backlight(hero, j, rarity)
	local glow = EggArt.Glow(rarity)
	local back = H.frame(hero, "Backlight" .. j, { Visible = glow > 0, ZIndex = 4 })
	local discs = {}
	for i, s in ipairs({ 1, 0.78, 0.58, 0.4 }) do
		local disc = H.frame(back, "Glow" .. i, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(s, s), BackgroundColor3 = H.color(rarity), BackgroundTransparency = 1, ZIndex = 4 })
		disc:SetAttribute("Alpha", 1 - glow * ({ 0.22, 0.32, 0.45, 0.62 })[i])
		H.corner(disc, 0.5)
		discs[i] = disc
	end
	return back, discs
end

-- the backdrop of the rise at rest (after a resize cancelled its tweens): the spot, the glows, the rings
function H.settleHero(roll)
	if roll.Spot and not roll.Revealed then
		roll.Spot.BackgroundTransparency = 0
	end
	for _, e in pairs(roll.Eggs) do
		for _, disc in ipairs(e.Back and e.Back:GetChildren() or {}) do
			if disc:IsA("Frame") then
				disc.BackgroundTransparency = disc:GetAttribute("Alpha") or 1
			end
		end
		if e.Ring and (e.State == "Rise" or e.State == "Crack") then
			e.Ring:Show(0.01)
			e.Ring:Spin(true)
			if e.Tint then
				e.Ring:Tint(e.Tint, 0) -- (Gemini's tweak already played: kept)
			end
		end
		-- (roll-look) the plinth at rest: popped, shown, its colour snapped (the tweak's or the burst's, else neutral)
		if e.Plinth then
			e.Plinth:Rest()
		end
	end
end

-- the eggs lift out of the strip and grow onto their pedestals in a spot light, their backlight and cloud ring fading in
-- behind them. quick (a skip before the rise): only the pedestals the reveal stands on
function R.rise(roll, quick)
	roll.HeroBuilt = true
	local cr = S.Lay.Crack
	local hero = roll.UI.Hero
	if not quick then
		roll.Spot = H.frame(hero, "Spot", { BackgroundColor3 = K.SPOT_COLOR, BackgroundTransparency = 1, ZIndex = 1 })
		H.corner(roll.Spot, 0.5)
		-- (roll-look) fainter than 16.4's 0.84 / 0.6: its straight sides read as a pale box behind the plinth's halo
		Util.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.92), NumberSequenceKeypoint.new(1, 0.76) }), Parent = roll.Spot })
	end
	for j, pull in ipairs(roll.Pulls) do
		local e = { State = "Rise" }
		e.Back, e.Glows = B.backlight(hero, j, pull.Rarity)
		e.Ped = B.pedestal(hero, j, pull.Rarity, e)
		if not quick then
			-- (roll-look) the plinth comes in with the rise: from K.LOOK.PLINTH_IN.From and clear (R.riseStep)
			e.Plinth.Pop.Scale = K.LOOK.PLINTH_IN.From
			e.Plinth:SetAlpha(0)
			e.Ring = HatchFx.CloudRing(hero, H.color(pull.Rarity), { ZIndex = 3, Track = S.Tweens })
			e.Ring.Frame.Name = "CloudRing" .. j
			-- the hero egg: Full with its rarity VFX (spec 16.5 "Where the VFX show"); its drifting sparkles come from the pool
			e.Egg = EggArt.New(hero, pull.Rarity, cr.E, { Name = "Egg" .. j, ZIndex = 6, Vfx = true })
			e.Egg.AnchorPoint = Vector2.new(0.5, 1)
			e.Egg:SetAttribute("State", "Rise")
			e.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = e.Egg })
			roll.Pool:Ambient(e.Egg, pull.Rarity)
			B.egg3d(roll, e, pull.Rarity)
		end
		roll.Eggs[j] = e
	end
	H.applyHero(roll, S.Lay)
	if quick then
		return
	end
	-- the grow: from the landed cell (or the middle) to the pedestal; the backdrop fades in. Driven a frame at a time by
	-- R.riseStep from the one Heartbeat (x3 would need ~25 tweens for it; the budget is 24 in all)
	local g = S.Lay.Strip
	for j, e in pairs(roll.Eggs) do
		local st = roll.Strips[j]
		e.RiseTo, e.PedTo = e.Egg.Position, e.Ped.Position
		if st and st.Geo then
			e.RiseFrom = UDim2.fromOffset(g.X + g.W / 2, g.Y[j] + g.H / 2 + g.Egg / 2)
			e.PopFrom = math.max(0.1, g.Egg / math.max(1, cr.E))
		else
			e.RiseFrom, e.PopFrom = e.RiseTo, 0.4
		end
		e.PedFrom = e.PedTo + UDim2.fromOffset(0, 0.12 * cr.E)
		e.Ring:Show(roll.T.Rise)
		e.Ring:Spin(true)
	end
	-- the landed strips only need the cells on show while they slide away (the rest go: x3 stays inside 750 instances)
	for _, st in pairs(roll.Strips) do
		for slot, cell in pairs(st.Cells) do
			if not cell.Frame.Visible then
				HatchLook.DropCard(cell.Card)
				st.Cells[slot] = nil
			end
		end
		-- (roll-look) the winner lifts OUT of its card (the hero egg grows from its place: no second egg left behind), and
		-- the window lets its soft glow go; an x3 strip drops its dark rim too (x3 stays inside 750 instances while the
		-- strips slide away under the three rising eggs)
		local lc = H.landedCell(st)
		if lc and lc.Egg then
			lc.Egg:Destroy()
			lc.Egg = nil
		end
		st.Lifted = true
		if st.Win then
			st.Win:DropGlow()
		end
		if roll.N > 1 and st.Outer then
			st.Outer:Destroy()
			st.Outer = nil
		end
		-- (Task 2) ...and its end fades and dims (the three plinths come in now: x3 stays inside 750 at the rise's start)
		if roll.N > 1 then
			for _, key in ipairs({ "FadeL", "FadeR" }) do
				if st[key] then
					st[key]:Destroy()
					st[key] = nil
				end
			end
			if st.Win then
				st.Win:DropDims()
			end
		end
		if st.Streaks then
			st.Streaks:Destroy()
			st.Streaks, st.StreakBars = nil, nil
		end
	end
	roll.Rising = true -- (R.advance steps it from this frame)
	H.sfx(K.SOUND.Rise, H.scaleFor(roll.Pulls[roll.Best].Rarity))
end

-- one frame of the rise (u: 0 -> 1 over the Rise phase): the eggs ease up and grow (Back), the pedestals settle, the
-- spot and the glows fade in, the strips slide away down off the screen
function R.riseStep(roll, t)
	if not roll.Rising then
		return
	end
	local s = roll.Sched
	local u = Util.Clamp((t - s.LandEnd) / math.max(0.01, s.RiseEnd - s.LandEnd), 0, 1)
	local quad = 1 - (1 - u) * (1 - u)
	local back = 1 + 2.70158 * (u - 1) ^ 3 + 1.70158 * (u - 1) ^ 2
	if roll.Spot then
		roll.Spot.BackgroundTransparency = 1 - u
	end
	for _, e in pairs(roll.Eggs) do
		if e.Egg and e.RiseTo then
			e.Egg.Position = e.RiseFrom:Lerp(e.RiseTo, quad)
			e.Pop.Scale = e.PopFrom + (1 - e.PopFrom) * back
			e.Ped.Position = e.PedFrom:Lerp(e.PedTo, back)
		end
		if e.Plinth and e.PedTo then
			-- (roll-look) the plinth pops in (Back Out, past 1 and back) and fades in over the whole rise
			local from = K.LOOK.PLINTH_IN.From
			e.Plinth.Pop.Scale = from + (1 - from) * back
			e.Plinth:SetAlpha(u)
		end
		if e.Glows and e.Back.Visible then
			for _, disc in ipairs(e.Glows) do
				disc.BackgroundTransparency = 1 + (disc:GetAttribute("Alpha") - 1) * u
			end
		end
	end
	if roll.UI.Strips and S.Lay then
		-- the strips slide away: down and off the screen, slow then fast (the egg has left them by then)
		local top = S.Lay.Strip and S.Lay.Strip.Y and S.Lay.Strip.Y[1] or 0
		roll.UI.Strips.Position = UDim2.fromOffset(0, (S.Lay.H - top) * u * u)
	end
	if u >= 1 then
		roll.Rising = false
	end
end

function R.dropStrips(roll)
	for _, st in pairs(roll.Strips) do
		st.Frame:Destroy()
	end
	roll.Strips = {}
	if roll.UI.Strips then
		roll.UI.Strips.Visible = false
	end
end

-- (egg-3d, spec 16.14) the real Blender egg in a ViewportFrame inside the hero egg's frame (x1 only: the x3 roll and the
-- strip cells keep their 2D eggs; at most one ViewportFrame egg on a phone). It takes the frame's place, size, rise and
-- push-in; the 2D paint hides, the backlight, ring, cracks, leaks, sparks and Rays / Aura stay round it. No id for the
-- key, Low graphics, the phone limit or a failed Assemble: nothing changes (today's 2D egg).
function B.egg3d(roll, e, rarity)
	if roll.N ~= 1 or not e.Egg then
		return
	end
	local view = Egg3D.New(e.Egg, rarity, { Phone = EggStage.Layout() ~= "PC", ZIndex = e.Egg.ZIndex + 2, Turn = K.EGG3D.Turn, Spin = K.EGG3D.Spin })
	if view then
		EggArt.SetPaintShown(e.Egg, false)
		e.Egg:SetAttribute("Egg3D", view.Key)
		e.V3 = view
	end
end

function B.halves(roll, j)
	local e = roll.Eggs[j]
	local cr = S.Lay.Crack
	local w = math.floor(EggArt.Metrics.WIDTH * cr.E + 0.5)
	local holder = H.frame(roll.UI.Hero, "Halves" .. j, { Visible = false, ZIndex = 6 })
	H.place(holder, cr.Cx[j] - w / 2, cr.EggY, w, cr.E)
	e.Holder, e.HolderSize = holder, cr.E
	-- (egg-3d) a 3D egg whose two Blender halves are usable here splits into them at the burst (the ViewportFrame moves
	-- into this holder); otherwise today's 2D halves, under the same flash
	e.Split3D = e.V3 ~= nil and e.V3:CanSplit() or false
	holder:SetAttribute("Split3D", e.Split3D)
	if not e.Split3D then
		e.Top, e.Bottom = EggArt.Halves(holder, roll.Pulls[j].Rarity, cr.E)
	end
end

function R.crack(roll, j)
	local e = roll.Eggs[j]
	e.State = "Crack"
	e.Egg:SetAttribute("State", "Crack")
	local rarity = roll.Pulls[j].Rarity
	R.word(roll)
	B.halves(roll, j)
	-- the first crack and its light; the push-in over the shakes (the egg grows on its foot to K.PUSH)
	e.Step, e.Shook = 1, 0
	HatchFx.Cracks(e.Egg, rarity, 1)
	HatchFx.Leaks(e.Egg, rarity, 1)
	H.tween(e.Pop, roll.T.Crack * 0.9, { Scale = K.PUSH }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	if e.V3 then
		-- the turn eases to a stop as the first crack glows (the cracks are drawn on the screen: the egg holds under them)
		e.V3:Settle(roll.T.Crack * K.EGG3D.Settle)
	end
	H.sfx(K.SOUND.Crack, H.scaleFor(rarity))
end

-- the crack word names the egg that bursts next: x3's eggs crack 0.6 s apart and overlap, so it is the earliest one
-- still cracking (after the last burst it keeps the last word until the reveal hides it)
function R.word(roll)
	local word = roll.UI.Crack
	for j = 1, roll.N do
		local e = roll.Eggs[j]
		if word and e and e.State == "Crack" then
			local rarity = roll.Pulls[j].Rarity
			local text = string.upper(rarity) .. " EGG!"
			if word.Text ~= text or not word.Visible then
				word.Text = text
				word.TextColor3 = H.color(rarity)
				word.Visible = true
				H.placeWord(roll, S.Lay)
			end
			return
		end
	end
end

-- the shakes: two (one on Fast hatch), +-6 then +-10 degrees with a squash (wider and lower: never taller, so the
-- push-in's room above the egg holds); at each the cracks grow (1 -> 3 -> 5), the light leaks lengthen, small sparks pop
function R.shake(roll, j, u)
	local e = roll.Eggs[j]
	local C = roll.T.Crack
	local rot, squash = 0, 0
	local windows = roll.Fast and K.SHAKE_FAST or K.SHAKE
	for k, w in ipairs(windows) do
		local a, b = w[1] * C, w[2] * C
		if u >= a and u <= b then
			local s = (u - a) / (b - a)
			rot = w[3] * math.sin(s * math.pi * 6)
			squash = math.sin(s * math.pi)
		end
		if u >= a and e.Shook < k then
			e.Shook = k
			R.shakeStart(roll, j, (k == #windows) and 5 or 3)
		end
	end
	local E = S.Lay.Crack.E
	local w0 = math.floor(EggArt.Metrics.WIDTH * E + 0.5)
	if e.V3 then
		-- (egg-3d) the 3D egg rocks about its middle in 3D and dips; the cracks and leaks turn with it on screen (the frame
		-- itself stays square to the screen and unsquashed: the ViewportFrame's camera keeps its framing)
		e.Egg.Rotation = 0
		e.V3:Pose(rot, -K.EGG3D.Dip * squash)
		for _, name in ipairs(K.EGG3D.Turns) do
			local layer = e.Egg:FindFirstChild(name)
			if layer then
				layer.Rotation = rot
			end
		end
		e.Egg.Size = UDim2.fromOffset(w0, E)
		return
	end
	e.Egg.Rotation = rot
	e.Egg.Size = UDim2.fromOffset(w0 * (1 + K.SQUASH * squash), E * (1 - K.SQUASH * squash))
end

function R.shakeStart(roll, j, step)
	local e = roll.Eggs[j]
	local rarity = roll.Pulls[j].Rarity
	local cr = S.Lay.Crack
	e.Step = step
	HatchFx.Cracks(e.Egg, rarity, step)
	HatchFx.Leaks(e.Egg, rarity, step)
	roll.Pool:Burst(Vector2.new(cr.Cx[j], cr.EggY + 0.6 * cr.E), rarity, K.SHAKE_SPARKS, K.SHAKE_SPARK)
	H.sfx(K.SOUND.Shake, H.scaleFor(rarity))
	if e.Shook == 1 then
		R.tweak(roll, j) -- (the first shake: step 3, or a Fast hatch's one shake)
	end
end

-- (roll-look, spec 16.15) Gemini's shake tweak, Rare and up only (Common / Uncommon: nothing until the burst, no fake
-- tease): the plinth's rim, ring and glow and the cloud ring turn the rarity colour; the rays come up faint and start
-- turning behind the egg (x3: only for the best pull, the rays' one owner; the bursts move them on)
function R.tweak(roll, j)
	local e = roll.Eggs[j]
	local rarity = roll.Pulls[j].Rarity
	if not e or roll.Tweaked[j] or H.order(rarity) < 3 then
		return
	end
	roll.Tweaked[j] = true
	local tw = roll.Fast and K.LOOK.TWEAK.Fast or K.LOOK.TWEAK.Tween
	local color = H.color(rarity)
	e.Tint = color
	if e.Plinth then
		e.Plinth:Tint(color, tw)
	end
	if e.Ring then
		e.Ring:Tint(color, tw)
	end
	if j == roll.Best and roll.Rays and not roll.RaysAt then
		local cr = S.Lay.Crack
		roll.TweakRays = j
		roll.Rays:Recolor(rarity)
		roll.Rays:Place(cr.Cx[j], cr.EggY + cr.E / 2, K.RAYS * cr.E)
		roll.Rays:Flash(K.LOOK.TWEAK.Rays, tw)
		roll.Rays:Spin(true)
	end
end

-- (roll-look) the burst's punch: the whole stage 1 -> 1.05 -> 1 round its middle (High only; a Fast hatch's shorter
-- burst squeezes it so it is over before the reveal). Phase tweens: the reveal and a resize put it back to 1
function R.punch(roll)
	local pu = S.Punch
	if not (pu and pu.Parent) or not H.high() then
		return
	end
	local P = K.LOOK.PUNCH
	local k = math.min(1, (roll.T.Burst - 0.01) / (P.Up + P.Down))
	pu.Scale = 1
	local up = H.tween(pu, P.Up * k, { Scale = P.Scale }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if up then
		up.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and S.Punch == pu and pu.Parent then
				H.tween(pu, P.Down * k, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			end
		end)
	end
end

-- (roll-look) a burst's sparks: the rarity's count, capped on phones
function H.sparks(rarity)
	local n = K.SPARKS[rarity] or 12
	if S.Lay and not S.Lay.PC then
		n = math.min(n, K.LOOK.PHONE_SPARKS)
	end
	return n
end

function R.burst(roll, j)
	local e = roll.Eggs[j]
	e.State = "Burst"
	e.Egg:SetAttribute("State", "Burst")
	e.Egg.Visible = false
	e.Egg.Rotation = 0
	roll.Pool:StopAmbient(e.Egg)
	EggArt.SetVfx(e.Egg, false) -- (hidden from here: its sheen and VFX stop)
	local pull = roll.Pulls[j]
	local rarity = pull.Rarity
	local color = H.color(rarity)
	local cr = S.Lay.Crack
	local T = roll.T
	local cx, cy = cr.Cx[j], cr.EggY + cr.E / 2
	-- (egg-3d) the 3D egg splits into its two Blender halves at the exact pose it cracked in and they fly apart (the
	-- ViewportFrame moves into the halves' holder, the hidden hero frame's box); a split that fails falls back to the 2D
	-- halves under the same flash
	if e.Split3D and e.V3 and e.Holder then
		e.V3.Frame.Parent = e.Holder
		e.Holder.Visible = true
		if not (e.V3:Split() and e.V3:Fly(T.Burst)) then
			e.V3:Destroy()
			e.V3 = nil
			e.Split3D = false
			e.Holder:SetAttribute("Split3D", false)
			e.Top, e.Bottom = EggArt.Halves(e.Holder, rarity, e.HolderSize or cr.E)
		end
	elseif e.V3 then
		e.V3:Destroy() -- (its halves have no ids: today's 2D halves take over under the flash)
		e.V3 = nil
	end
	-- the halves fly apart: the top spins up-left and fades, the bottom settles as the shell on the pedestal
	if e.Holder and e.Top and e.Bottom then
		e.Holder.Visible = true
		H.tween(e.Top, T.Burst, { Position = UDim2.fromOffset(-0.25 * cr.E, -0.45 * cr.E), Rotation = -35, GroupTransparency = 1 })
		H.tween(e.Bottom, T.Burst, { Position = UDim2.fromOffset(0, cr.E / 2 + 0.04 * cr.E) })
	end
	-- the shock ring, the rays flashing in and turning, the cloud ring's swell in the rarity colour, the sparks
	roll.Shock:Play(cx, cy, K.SHOCK * cr.E, T.Burst, color:Lerp(K.WHITE, 0.2))
	roll.RaysAt = j
	roll.Rays:Recolor(rarity)
	roll.Rays:Place(cx, cy, K.RAYS * cr.E)
	roll.Rays:Flash(0.3, 0.12)
	roll.Rays:Spin(true)
	if e.Ring then
		e.Ring:Spin(false)
		e.Ring:Pulse(color, T.Burst)
	end
	-- (roll-look) below Rare the plinth takes its colour now (the tweak gave it to Rare and up at the first shake); the punch
	if e.Plinth and not e.Tint then
		e.Tint = color
		e.Plinth:Tint(color, math.min(K.LOOK.BURST_TINT, T.Burst))
	end
	R.punch(roll)
	local n = roll.Pool:Burst(Vector2.new(cx, cy), rarity, H.sparks(rarity))
	roll.UI.Burst:SetAttribute("Sparks", n)
	H.sfx(K.SOUND.Burst, H.scaleFor(rarity))
	H.sfx(K.SOUND.Ring, H.scaleFor(rarity))
	R.word(roll) -- (x3: the word moves on to the next egg still cracking)
	if j == roll.Best then
		-- x3: the loudest reveal sound and the gold flash follow the best pull, on its burst (spec 16.4 "x3")
		if roll.N > 1 then
			R.revealSound(roll)
		end
		R.flash(roll, H.order(rarity) >= K.LOUD_FROM)
	else
		R.flash(roll, false)
	end
end

-- the reveal sound of the best pull, once per roll
function R.revealSound(roll)
	if roll.RevealSoundDone then
		return
	end
	roll.RevealSoundDone = true
	local best = roll.Pulls[roll.Best]
	H.sfx(K.REVEAL_SOUND[best.Rarity] or K.REVEAL_SOUND.Common, H.scaleFor(best.Rarity))
end

-- the flash: white (0.12 s at 0.6 strong) or, once per roll for the best pull from Legendary, gold (a kick at 0.2
-- strong, up to 0.5 in 0.25 s, 0.6 s out); white = false skips the white one (Skip's burst tail). Overlay tweens: they play on over the reveal's start
function R.flash(roll, gold, white)
	if gold and roll.GoldDone then
		gold = false
	end
	local f = S.Flash
	if not f or (not gold and white == false) then
		return
	end
	-- one flash at a time: a new one ends the one before (its tween and its pending fade-out)
	if S.FlashTw then
		pcall(function()
			S.FlashTw:Cancel()
		end)
	end
	S.FlashToken = (S.FlashToken or 0) + 1
	local token = S.FlashToken
	if gold then
		roll.GoldDone = true
		f.BackgroundColor3 = K.GOLD
		f.BackgroundTransparency = K.GOLD_FROM
		S.FlashTw = H.tween(f, K.GOLD_IN, { BackgroundTransparency = K.GOLD_PEAK }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, true)
		task.delay(K.GOLD_IN, function()
			if S.FlashToken == token and S.Flash == f and f.Parent then
				S.FlashTw = H.tween(f, K.GOLD_OUT, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, true)
			end
		end)
	else
		f.BackgroundColor3 = K.WHITE
		f.BackgroundTransparency = K.WHITE_FLASH[1]
		S.FlashTw = H.tween(f, K.WHITE_FLASH[2], { BackgroundTransparency = 1 }, nil, nil, true)
	end
end

function R.reveal(roll, skipped)
	roll.Revealed = true
	roll.RevealedAt = os.clock()
	roll.Phase = "Reveal"
	if skipped then
		H.stopSounds(roll) -- (Skip: every sound of the roll so far stops)
	end
	R.dropStrips(roll)
	if not roll.HeroBuilt then
		R.rise(roll, true)
	end
	for _, e in pairs(roll.Eggs) do
		if e.V3 then
			e.V3:Destroy()
			e.V3 = nil
		end
		if e.Egg then
			roll.Pool:StopAmbient(e.Egg)
			e.Egg:Destroy()
			e.Egg = nil
		end
		if e.Holder then
			e.Holder:Destroy()
			e.Holder = nil
		end
		if e.Back then
			e.Back.Visible = false
		end
		if e.Ring then
			e.Ring:Destroy()
			e.Ring = nil
		end
		e.State = "Open"
	end
	if roll.Spot then
		roll.Spot.Visible = false
	end
	roll.UI.Crack.Visible = false
	H.cancelTweens()
	H.settleBackdrop(true)
	-- (roll-look) the punch over (a Skip may cut it), every plinth shown in its rarity colour under its pet
	if S.Punch then
		S.Punch.Scale = 1
	end
	for j, e in pairs(roll.Eggs) do
		if e.Plinth then
			e.Tint = e.Tint or H.color(roll.Pulls[j].Rarity)
			e.Plinth.Color = e.Tint
			e.Plinth:Rest()
		end
	end
	B.cols(roll)
	if EggStage._InjectPhaseError == "Reveal" then
		error("injected phase error (Reveal)") -- the test hook: an error inside the reveal's own build
	end
	roll.UI.Reveal.Visible = true
	H.apply()
	local best = roll.Pulls[roll.Best]
	local loud = H.order(best.Rarity) >= K.LOUD_FROM
	local g = S.Lay.Cols[roll.Best]
	local px, py, ps = 0, 0, 0
	if g then
		px, py, ps = g.X + g.Pet.X + g.Pet.S / 2, g.Y + g.Pet.Y + g.Pet.S / 2, g.Pet.S
	end
	if skipped then
		-- the burst's last 0.25 s over the reveal's start (spec 16.4 "Skip"): the shock ring, the rays, the sparks and,
		-- from Legendary, the gold Flash once; no white micro-flash
		roll.Shock:Play(px, py, 1.6 * ps, K.TAIL, H.color(best.Rarity):Lerp(K.WHITE, 0.2))
		roll.Rays:Recolor(best.Rarity)
		if roll.Rays.Frame then
			roll.Rays.Frame.Visible = true
			roll.Rays.Frame.GroupTransparency = 0.3
		end
		roll.Pool:Burst(Vector2.new(px, py), best.Rarity, H.sparks(best.Rarity))
		R.flash(roll, loud, false)
	end
	-- Legendary and up keep slow gold rays behind the best pet (roll-look: dimmed to RAYS_TEXT while the text shows, the
	-- clutter cap); the others' rays fade with the burst's tail
	if loud then
		roll.Rays:Recolor(best.Rarity) -- (x3: the last burst may have been a lesser egg's)
		roll.Rays:Flash(K.LOOK.RAYS_TEXT, 0.2)
		roll.Rays:Spin(true)
	elseif roll.Rays.Frame and roll.Rays.Frame.Visible then
		roll.Rays:Flash(1, K.TAIL)
		local rays, mine = roll.Rays, roll
		task.delay(K.TAIL + 0.02, function()
			if S.Roll == mine then
				rays:Hide()
			end
		end)
	end
	-- the pets pop (0 -> past 1 -> 1, Back); (roll-look, spec 16.15) from Legendary the best pull's pets stand black (B's
	-- silhouette) and the chain (the letters, the name / NEW! / note, the pills) waits SIL for them
	for _, c in pairs(roll.Cols) do
		H.tween(c.Pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	local sil = H.order(best.Rarity) >= K.LOOK.SIL.From and K.LOOK.SIL.Hold or 0
	R.chain(roll, sil)
	local mine = roll
	task.delay(0.36, function()
		if S.Roll == mine then
			mine.PopDone = true
		end
	end)
	-- Mythic and Secret: confetti for 1.5 s (as soon as the pool has room for all of it); Secret: the starry backdrop
	if best.Rarity == "Mythic" or best.Rarity == "Secret" then
		roll.ConfettiWanted = best.Rarity
		R.confetti(roll)
	end
	if best.Rarity == "Secret" and S.Stage and not S.Stars then
		S.Stars = HatchFx.Stars(S.Stage, K.STARS)
		S.Stars.Frame.ZIndex = 2
	end
	R.revealSound(roll)
	-- (review round 1) set last: an error anywhere above leaves it nil, and teardown("Error") toasts the pulls then
	roll.RevealBuilt = true
end

-- (roll-look, spec 16.15 "Easing and timings") the reveal's chain from sil (0, or the silhouette's hold): the silhouettes
-- fill at sil, the letters pop 0.05 s apart from sil, the name / NEW! / note rise at sil + 0.2, NEW! pops at sil + 0.4,
-- the pills rise at sil + 0.4 (they still arm by the arming rule: H.armed). Every beat is a task.delay checked against
-- roll.ChainToken (a resize settles the chain and drops the rest: H.settleChain) and the roll still showing
function R.chain(roll, sil)
	local C = K.LOOK.CHAIN
	roll.ChainToken = (roll.ChainToken or 0) + 1
	local token = roll.ChainToken
	local function later(at, fn)
		task.delay(math.max(0, at), function()
			if S.Roll == roll and roll.ChainToken == token and not roll.Dead then
				H.safe("chain", fn)
			end
		end)
	end
	for _, c in pairs(roll.Cols) do
		c.Word:Pop(sil, C.Letter, S.Tweens)
		c.NewPop.Scale = 0
		if c.Sil and sil > 0 and c.View then
			c.View.ImageColor3 = Color3.new(0, 0, 0)
		end
	end
	H.textIn(roll, 0)
	H.pillsIn(roll, 0)
	if sil > 0 then
		later(sil, function()
			for _, c in pairs(roll.Cols) do
				if c.Sil and c.View then
					H.tween(c.View, K.LOOK.SIL.Fill, { ImageColor3 = K.WHITE })
				end
			end
		end)
	end
	later(sil + C.Text, function()
		roll.TextIn.Value = 0
		H.tween(roll.TextIn, C.TextIn, { Value = 1 })
	end)
	later(sil + C.New, function()
		for _, c in pairs(roll.Cols) do
			if c.New.Visible then
				local pop = c.NewPop
				local up = H.tween(pop, C.NewIn, { Scale = C.NewPeak })
				if up then
					up.Completed:Connect(function(state)
						if state == Enum.PlaybackState.Completed and pop.Parent then
							H.tween(pop, C.NewOut, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
						end
					end)
				end
			end
		end
	end)
	later(sil + C.Pills, function()
		roll.PillsIn.Value = 0
		H.tween(roll.PillsIn, C.PillsIn, { Value = 1 })
	end)
end

-- the chain at its end at once (a resize mid-chain: its tweens were cancelled), the beats still pending dropped
function H.settleChain(roll)
	roll.ChainToken = (roll.ChainToken or 0) + 1
	for _, c in pairs(roll.Cols) do
		c.Word:Settle()
		c.NewPop.Scale = 1
		if c.View and c.View.Parent then
			c.View.ImageColor3 = K.WHITE
		end
	end
	H.textIn(roll, 1)
	H.pillsIn(roll, 1)
end

-- the confetti falls once the pool can hold all of it (the burst's sparks go back first)
function R.confetti(roll)
	local want = roll.ConfettiWanted
	if not want or not roll.Pool then
		return
	end
	local n = H.high() and K.CONFETTI or math.floor(K.CONFETTI / 2)
	if roll.Pool:Live() + n <= K.POOL then
		roll.ConfettiWanted = nil
		roll.Pool:Confetti(K.CONFETTI, want)
	end
end

function R.advance(roll)
	local t = os.clock() - roll.Start
	if roll.Revealed then
		roll.AgainClock = (roll.AgainClock or 0) + 1
		-- (every 8 heartbeats for the balance and the policy; on the frame the reveal arms or a tap disarms it)
		if roll.AgainClock % 8 == 0 or H.armed() ~= roll.Armed then
			H.refreshAgain()
		end
		R.confetti(roll)
		return
	end
	if roll.SkipWanted then
		R.reveal(roll, true)
		return
	end
	local s = roll.Sched
	if roll.HasStrip and next(roll.Strips) ~= nil then
		if not roll.StartPlayed and t >= s.IntroEnd then
			roll.StartPlayed = true
			H.sfx("SpinStart", K.QUIET)
		end
		R.strips(roll, t)
		R.landStep(roll, t)
	end
	R.warmOne(roll)
	if t >= s.LandEnd and not roll.HeroBuilt then
		R.rise(roll)
	end
	R.riseStep(roll, t)
	if t >= s.RiseEnd and next(roll.Strips) ~= nil then
		R.dropStrips(roll)
	end
	for j = 1, roll.N do
		local e = roll.Eggs[j]
		if e then
			if e.State == "Rise" and t >= s.CrackAt[j] then
				R.crack(roll, j)
			end
			if e.State == "Crack" then
				if t >= s.BurstAt[j] then
					R.burst(roll, j)
				else
					R.shake(roll, j, t - s.CrackAt[j])
				end
			end
			if e.State == "Burst" and t >= s.OpenAt[j] then
				e.State = "Open"
				if e.Egg then
					e.Egg:SetAttribute("State", "Open")
				end
			end
		end
	end
	if t >= s.RevealAt then
		R.reveal(roll, false)
		return
	end
	roll.Phase = R.phaseAt(roll, t)
	if EggStage._InjectPhaseError ~= nil and roll.Phase == EggStage._InjectPhaseError then
		error("injected phase error (" .. tostring(roll.Phase) .. ")")
	end
end

-- builds one pulled pet's model ahead of the reveal (one build a frame, while the strip runs). S.Warm[petId]: true =
-- built, false = its build failed (never tried again this session: review round 1, a failing build ran every frame and
-- kept the later pulls cold), nil = not tried yet
function R.warmOne(roll)
	local builder = nil
	for _, pull in ipairs(roll.Pulls) do
		if S.Warm[pull.PetId] == nil then
			builder = builder or H.lazy("Builder", Shared, "PetBuilder")
			if not (builder and type(builder.Build) == "function") then
				return -- no builder (yet): nothing is marked, the next frame asks again
			end
			local ok, model = pcall(builder.Build, pull.Def, { Scale = 1 })
			if ok and typeof(model) == "Instance" then
				model:Destroy()
				S.Warm[pull.PetId] = true
			else
				S.Warm[pull.PetId] = false
			end
			return
		end
	end
end

-- the one Heartbeat: the phases, then the spark pool (driven from here: no Heartbeat of its own)
function R.step(dt)
	local roll = S.Roll
	if not roll then
		return
	end
	local ok, err = pcall(R.advance, roll)
	if not ok and S.Roll == roll then
		H.warnOnce("phase", err)
		H.teardown("Error")
		return
	end
	if S.Roll == roll and roll.Pool then
		pcall(roll.Pool.Step, roll.Pool, tonumber(dt) or (1 / 60))
	end
end

----------------------------------------------------------------------
-- open, rolls, exits
----------------------------------------------------------------------
function H.open()
	if not B.gui() then
		return false
	end
	-- (roll-look, spec 16.15 "The HUD hides") every other Enabled ScreenGui goes off while the stage shows (HatchLook.KEEP
	-- and Roblox's own stay), and one added meanwhile too; every teardown switches them back on (HatchLook.RestoreHud)
	local pg = S.Gui.Parent
	HatchLook.HideHud(pg, S.Gui)
	S.Conns[#S.Conns + 1] = pg.ChildAdded:Connect(function(child)
		H.safe("hud", HatchLook.HideOne, child)
	end)
	if not S.Beat then
		S.Beat = RunService.Heartbeat:Connect(R.step)
	end
	S.Conns[#S.Conns + 1] = S.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		H.safe("resize", H.relayout)
	end)
	S.Conns[#S.Conns + 1] = LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
		if H.inMatch() and (S.Roll or S.Gui) then
			H.teardown("Match")
		end
	end)
	S.Conns[#S.Conns + 1] = ClientSettings.Changed:Connect(function(key)
		if key == "FastHatch" then
			H.paintFast(S.Roll)
		end
	end)
	if not S.Bound then
		S.Bound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					H.safe("back", EggStage.Back)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.ButtonB)
		end)
	end
	local mc = H.menu()
	if mc and type(mc.SetTouchHidden) == "function" then
		pcall(mc.SetTouchHidden, "Hatch", true)
	end
	return true
end

function H.startRoll(roll)
	S.Roll = roll
	roll.Start = os.clock()
	roll.Phase = "Intro"
	S.Lay = L.compute(roll.N, roll)
	B.roll(roll)
	H.apply()
	-- the intro: the dim, the vignette, the title sliding down
	if S.Dim and S.Dim.BackgroundTransparency > K.DIM then
		H.tween(S.Dim, roll.T.Intro, { BackgroundTransparency = K.DIM })
	end
	for _, edge in ipairs(S.Vignette:GetChildren()) do
		if edge:IsA("Frame") and edge.BackgroundTransparency > K.VIGNETTE then
			H.tween(edge, roll.T.Intro, { BackgroundTransparency = K.VIGNETTE })
		end
	end
	local title = roll.UI.Title
	local final = title.Position
	title.Position = final + UDim2.fromOffset(0, -20)
	H.tween(title, roll.T.Intro, { Position = final })
	-- the world behind: the blur and the cool tint (High only; one effect + the "Hatch" preset, ours)
	S.Dimmed = true
	pcall(HatchFx.Dim, true, roll.T.Intro)
end

function H.finishRoll()
	local roll = S.Roll
	S.Roll = nil
	if roll then
		roll.Dead = true
		for _, v in ipairs(roll.Views) do
			pcall(v.Destroy)
		end
		roll.Views = {}
		for _, key in ipairs({ "Rays", "Shock", "Pool" }) do
			local fx = roll[key]
			if fx then
				pcall(fx.Destroy, fx)
			end
		end
		for _, e in pairs(roll.Eggs) do
			if e.Ring then
				pcall(e.Ring.Destroy, e.Ring)
			end
			if e.V3 then
				pcall(e.V3.Destroy, e.V3)
				e.V3 = nil
			end
		end
		roll.Sounds = {}
	end
	if S.Stars then
		pcall(S.Stars.Destroy)
		S.Stars = nil
	end
	H.cancelTweens(true)
	S.FlashTw = nil
	S.FlashToken = (S.FlashToken or 0) + 1
	if S.Content then
		for _, child in ipairs(S.Content:GetChildren()) do
			if child ~= S.Fit then
				child:Destroy()
			end
		end
	end
	if S.Flash then
		S.Flash.BackgroundTransparency = 1
	end
end

function H.namesOf(roll, out)
	for _, p in ipairs(roll.Pulls) do
		out[#out + 1] = p.Def.Name
	end
	return out
end

-- every exit ends here: the pulls not shown yet are toasted, then everything this module made goes, then Closed(reason)
function H.teardown(reason)
	local roll = S.Roll
	if not roll and not S.Gui then
		return
	end
	if reason ~= "Done" then
		local names = {}
		-- the roll's pulls unless its reveal was fully built (an error inside R.reveal leaves RevealBuilt nil)
		if roll and (not roll.Revealed or not roll.RevealBuilt) then
			H.namesOf(roll, names)
		end
		for _, result in ipairs(S.Queue) do
			local queued = H.makeRoll(result)
			if queued then
				H.namesOf(queued, names)
			end
		end
		S.Queue = {}
		if #names > 0 then
			H.toast(K.TEXT.Hatched .. table.concat(names, ", "))
		end
		H.stopSounds(roll) -- (DONE lets the reveal's sound ring out; every other exit stops the roll's sounds)
	end
	EggStage._InjectPhaseError = nil
	H.finishRoll()
	if S.Dimmed then
		S.Dimmed = false
		pcall(HatchFx.Dim, false, 0.35)
	end
	if S.Beat then
		S.Beat:Disconnect()
		S.Beat = nil
	end
	for _, conn in ipairs(S.Conns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	S.Conns = {}
	if S.Bound then
		S.Bound = false
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
	local mc = H.menu()
	if mc and type(mc.SetTouchHidden) == "function" then
		pcall(mc.SetTouchHidden, "Hatch", false)
	end
	H.safe("hud", HatchLook.RestoreHud)
	if S.Gui then
		S.Gui:Destroy()
	end
	S.Gui, S.Stage, S.Content, S.Fit, S.Dim, S.Flash, S.Vignette, S.Lay, S.Punch = nil, nil, nil, nil, nil, nil, nil, nil, nil
	pcall(EggStage.Closed.Fire, EggStage.Closed, reason)
end

-- the backdrop at rest (after its tweens were cancelled): the dim, the vignette edges, no flash (keepFlash: the
-- reveal's start, where the burst's flash plays on)
function H.settleBackdrop(keepFlash)
	if S.Dim then
		S.Dim.BackgroundTransparency = K.DIM
	end
	if S.Vignette then
		for _, edge in ipairs(S.Vignette:GetChildren()) do
			if edge:IsA("Frame") then
				edge.BackgroundTransparency = K.VIGNETTE
			end
		end
	end
	if S.Flash and not keepFlash then
		S.Flash.BackgroundTransparency = 1
	end
end

function H.relayout()
	local roll = S.Roll
	if not roll or not S.Content then
		return
	end
	H.cancelTweens(true)
	S.FlashToken = (S.FlashToken or 0) + 1
	S.Lay = L.compute(roll.N, roll)
	H.settleBackdrop()
	if S.Punch then
		S.Punch.Scale = 1 -- (roll-look: a punch cut short by the resize)
	end
	if roll.UI.Strips then
		roll.UI.Strips.Position = UDim2.fromOffset(0, 0)
	end
	for _, c in pairs(roll.Cols) do
		c.Pop.Scale = 1
	end
	roll.PopDone = roll.Revealed
	-- a resize mid-rise ends the rise where it was going (H.apply puts the eggs and pedestals at their new places)
	roll.Rising = false
	for _, e in pairs(roll.Eggs) do
		if e.Pop and e.State == "Rise" then
			e.Pop.Scale = 1
		end
	end
	H.apply()
	H.settleHero(roll)
	if roll.Revealed then
		H.settleChain(roll) -- (roll-look) every letter at 1, the silhouette filled, the text and the pills in place
	end
	-- (roll-look) the strips at rest: the window's bounce done and its tell colour snapped, a landed card's pop at 1.09
	for _, st in pairs(roll.Strips) do
		if st.Win then
			st.Win:Rest()
		end
		local cell = st.Landed and H.landedCell(st)
		if cell then
			HatchLook.SetPop(cell.Card, HatchLook.Metrics.POP.Rest)
		end
	end
	-- the overlay at rest: the shock gone, the rays shown only where they stay (Legendary and up on the reveal) or while a
	-- burst's tail would still play (they go with the next burst or the reveal)
	if roll.Shock then
		roll.Shock:Hide()
	end
	if roll.Rays and roll.Rays.Frame then
		if roll.Revealed and H.order(roll.Pulls[roll.Best].Rarity) >= K.LOUD_FROM then
			roll.Rays.Frame.Visible = true
			roll.Rays.Frame.GroupTransparency = K.LOOK.RAYS_TEXT
			roll.Rays:Spin(true)
		elseif not roll.Revealed and roll.TweakRays and not roll.RaysAt then
			-- (roll-look) Gemini's tweak played and no burst yet: the faint turning rays stay
			roll.Rays.Frame.Visible = true
			roll.Rays.Frame.GroupTransparency = K.LOOK.TWEAK.Rays
			roll.Rays:Spin(true)
		else
			roll.Rays:Hide()
		end
	end
end

-- (review round 2) the reveal is armed ARM_AFTER after it appeared and ARM_QUIET after the last tap on the stage
function H.armed()
	local roll = S.Roll
	if not (roll and roll.Revealed and roll.RevealedAt) then
		return false
	end
	local now = os.clock()
	return now - roll.RevealedAt >= K.ARM_AFTER and now - S.LastTap >= K.ARM_QUIET
end

-- one tap on the stage (the Dim, the Skip chip, SPIN AGAIN or DONE; Esc and B are keys, not taps): returns whether the
-- reveal was armed before it, then restarts the wait, so a mash never arms SPIN AGAIN
function H.press()
	local armed = H.armed()
	S.LastTap = os.clock()
	return armed
end

-- a tap anywhere outside the buttons, or the Skip chip: skip before the reveal (at once, spec 16.4), close it once armed
function H.tap()
	local roll = S.Roll
	if not roll then
		return
	end
	local armed = H.press()
	if roll.Revealed then
		if armed then
			EggStage.Done()
		end
	else
		EggStage.Skip()
	end
end

-- DONE: closes the reveal (or plays the next queued result) once armed
function H.doneTap()
	if H.press() then
		EggStage.Done()
	end
end

-- SPIN AGAIN: a new paid request once armed, and only while it shows enabled (no reason, not pending)
function H.againTap()
	local roll = S.Roll
	local btn = roll and roll.UI.Again
	if H.press() and btn and btn:GetAttribute("Disabled") ~= true then
		H.again()
	end
end

function H.again()
	local roll = S.Roll
	if not roll or not roll.Revealed or not roll.Roulette then
		return
	end
	if EggStage.Request(roll.Roulette.Id, roll.Currency, roll.N > 1 and 3 or 1) then
		S.PendFrom = "Again"
	end
end

----------------------------------------------------------------------
-- public API
----------------------------------------------------------------------
function EggStage.Init()
	if S.Inited then
		return
	end
	S.Inited = true
	local remote = H.remote("RouletteResult")
	if remote then
		remote.OnClientEvent:Connect(function(result)
			H.safe("RouletteResult", EggStage._Answer, result)
		end)
	else
		H.warnOnce("Init", "the RouletteResult remote is unavailable")
	end
end

function EggStage.Show(result)
	local roll = H.makeRoll(result)
	if not roll then
		if type(result) == "table" and result.Ok ~= false then
			H.toast(K.TEXT.Fallback)
		end
		return false
	end
	if S.Roll then
		S.Queue[#S.Queue + 1] = result
		return true
	end
	if not H.open() then
		H.toast(K.TEXT.Hatched .. table.concat(H.namesOf(roll, {}), ", "))
		return false
	end
	H.startRoll(roll)
	pcall(EggStage.Opened.Fire, EggStage.Opened)
	return true
end

function EggStage._Answer(result)
	local fromAgain = S.PendFrom == "Again"
	S.Pending = false
	S.PendToken = S.PendToken + 1
	S.PendFrom = nil
	pcall(EggStage.Answered.Fire, EggStage.Answered, result)
	if type(result) ~= "table" then
		H.refreshAgain()
		return
	end
	if result.Ok == false then
		local reason = (type(result.Reason) == "string" and result.Reason ~= "") and result.Reason or K.TEXT.Failed
		H.toast(reason)
		H.refreshAgain()
		return
	end
	local roll = S.Roll
	if roll and roll.Revealed and fromAgain and #S.Queue == 0 then
		local nextRoll = H.makeRoll(result)
		if nextRoll then
			H.finishRoll()
			H.startRoll(nextRoll)
			return
		end
	end
	EggStage.Show(result)
end

function EggStage.Request(rouletteId, currency, spins)
	if S.Pending then
		return false
	end
	local now = os.clock()
	if now - S.LastFire < K.FIRE_GAP then
		return false
	end
	local roulette = H.roulette(rouletteId)
	if not roulette then
		return false
	end
	spins = (spins == 3) and 3 or 1
	currency = (currency == "Gems" or roulette.Id == K.SECRET_ID) and "Gems" or "Tokens"
	if roulette.Id == K.SECRET_ID then
		spins = 1 -- the Secret Roulette is x1 only (spec 13 call 2)
	end
	if H.inMatch() then
		H.toast(K.TEXT.Match)
		return false
	end
	local price = H.price(roulette, currency) * spins
	if currency == "Gems" and not H.gemsOpen() then
		H.toast(K.TEXT.Policy)
		return false
	end
	if H.balance(currency) < price then
		H.toast("You need " .. Util.Commas(price) .. (currency == "Gems" and " Gems" or " Cloud Tokens") .. " for that.")
		return false
	end
	local remote = H.remote("BuyRoulette")
	if not remote then
		return false
	end
	local ok = pcall(function()
		remote:FireServer(roulette.Id, currency, spins)
	end)
	if not ok then
		return false
	end
	S.LastFire = now
	S.Pending = true
	S.PendFrom = nil
	S.PendToken = S.PendToken + 1
	local mine = S.PendToken
	pcall(EggStage.Pending.Fire, EggStage.Pending, roulette.Id, currency, spins)
	H.refreshAgain()
	task.delay(K.WAIT_TIMEOUT, function()
		if S.Pending and S.PendToken == mine then
			S.Pending = false
			S.PendFrom = nil
			H.toast(K.TEXT.NoAnswer)
			H.refreshAgain()
		end
	end)
	return true
end

function EggStage.IsPending()
	return S.Pending == true
end

function EggStage.IsShowing()
	return S.Roll ~= nil
end

function EggStage.Phase()
	return S.Roll and S.Roll.Phase or nil
end

function EggStage.Skip()
	local roll = S.Roll
	if roll and not roll.Revealed then
		roll.SkipWanted = true
	end
end

function EggStage.Back()
	local roll = S.Roll
	if not roll then
		return
	end
	if roll.Revealed then
		EggStage.Done()
	else
		EggStage.Skip()
	end
end

function EggStage.Done()
	local roll = S.Roll
	if not roll then
		return
	end
	if not roll.Revealed then
		EggStage.Skip()
		return
	end
	while #S.Queue > 0 do
		local nextRoll = H.makeRoll(table.remove(S.Queue, 1))
		if nextRoll then
			H.finishRoll()
			H.startRoll(nextRoll)
			return
		end
	end
	H.teardown("Done")
end

function EggStage.Close()
	if S.Roll or S.Gui then
		H.teardown("Close")
	elseif #S.Queue > 0 then
		local names = {}
		for _, result in ipairs(S.Queue) do
			local queued = H.makeRoll(result)
			if queued then
				H.namesOf(queued, names)
			end
		end
		S.Queue = {}
		if #names > 0 then
			H.toast(K.TEXT.Hatched .. table.concat(names, ", "))
		end
	end
end

function EggStage.IsPrewarmed(petId)
	return S.Warm[petId] == true
end

function EggStage.Stats()
	local n = 0
	if S.Gui and S.Gui.Parent then
		n = 1
		local skip = {}
		for _, d in ipairs(S.Gui:GetDescendants()) do
			local cur = d.Parent
			local inside = false
			while cur and cur ~= S.Gui do
				if skip[cur] or cur:IsA("ViewportFrame") then
					inside = true
					break
				end
				cur = cur.Parent
			end
			if inside then
				skip[d] = true
			else
				n = n + 1
			end
		end
	end
	local tweens = 0
	for _, set in ipairs({ S.Tweens, S.Overlay }) do
		for tw in pairs(set) do
			local ok, playing = pcall(function()
				return tw.PlaybackState == Enum.PlaybackState.Playing
			end)
			if ok and playing then
				tweens = tweens + 1
			end
		end
	end
	local sparks = 0
	if S.Roll and S.Roll.Pool then
		local ok, live = pcall(S.Roll.Pool.Live, S.Roll.Pool)
		sparks = ok and tonumber(live) or 0
	end
	local effects = 0
	if S.Gui and S.Gui.Parent then
		local ok, fx = pcall(HatchFx.Stats)
		effects = ok and type(fx) == "table" and tonumber(fx.Effects) or 0
	end
	return { Instances = n, Tweens = tweens, Sparks = sparks, Effects = effects, Heartbeats = S.Beat and 1 or 0 }
end

return EggStage
