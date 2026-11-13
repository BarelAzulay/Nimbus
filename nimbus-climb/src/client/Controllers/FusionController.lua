-- FusionController (client): the Fusion Machine window. Phase 2 (ARCHITECTURE_V3.md section 11 and the FusionService /
-- FusionController paragraph of the "Phase 2 build contract"); redrawn as card A of the window redo (gui-redo Task 11:
-- docs/superpowers/specs/2026-11-06-window-redo-design.md 5.1 and 5.6; plan docs/superpowers/plans/2026-11-06-window-redo.md).
--
--   FusionController.Init()
--   FusionController.Open(tab, args)   tab = "Upgrade" | "Mix" | nil (the last one); args (optional) =
--                                       { Key = key (the Upgrade pet / the Body), KeyB = key (the Style), Machine = the
--                                       Station_FusionMachine model it was opened at }
--   FusionController.Close()            closes our pet picker sheet and the window
--   FusionController.IsOpen() -> bool,  FusionController.Plan() -> the preview the window shows ({ Ok, Reason, Action, Inputs,
--       ResultKey, ResultName, Rarity, Tier, Elements, Cost = { Currency, Amount }, Notes; Mix: Moves, SpecialFrom,
--       SameElement, MovesText }),
--   FusionController.Select(keyA, keyB) picks pets like the sheet does (Upgrade: keyA; Mix: Body, Style; nil empties),
--   FusionController.Fuse() (the FUSE! button), FusionController.Layout() -> "PC" | "Phone" | "Portrait",
--   FusionController.SetMoves(attackKey, specialKey)   (Task 12) the Mix move choice: each argument must be the Body's or the
--                                       Style's key (anything else is ignored); attackKey picks the parent of the normal
--                                       attack (ignored when both parents share an element), specialKey the parent of the
--                                       special
--   FusionController.Moves() -> "BB" | "BS" | "SB" | "SS"   letter 1 = the normal attack's parent, letter 2 = the special's
--                                       (B = Body, S = Style); "BB" = today's hybrid (the Body gives both)
--   FusionController.MovesText(bodyKey, styleKey, moves) -> { Attack = { Element, Name }, Special = { Kind, Name } } | nil
--                                       (pure: stage 0's names from the catalogs; nil for a hybrid / unknown / missing pet;
--                                       junk or nil moves read as "BB")
--   FusionController.Opened (fires the tab) / Closed (Util.Signal)
--
-- How it opens: E at the player's own Fusion Machine (the FusionPrompt HomeBuilder puts on Station_FusionMachine; other
-- players' prompts are disabled locally by HomeFx and ignored here), or OpenPanel("Fusion", { Tab, Key, KeyB }) from the
-- server / other windows. One window at a time: opening it closes the menu windows, the Pet Index and the Gifts window
-- (CareController closes Feed / Garden / the Training Place on our Opened); a menu window or the Pet Index opening closes
-- it. Esc / gamepad B close our sheet first, then the window; the red X, walking away from the machine (when it was opened
-- there) and entering a match close it.
--
-- Card A (the owner's pick): a violet header (the crystal, "Fusion Machine", the UPGRADE / MIX tabs, the Cloud Token and
-- Gem chips, the red X) over a navy body:
--   UPGRADE  Stack: three fanned copies ("COPIES", the pet, "Uncommon . Flame"; a copy you do not have is an empty card),
--            CopiesText "x5 owned . uses 3", the Arrow, the big glowing Result (GOLDEN: gold + sparks; RAINBOW: a shimmering
--            edge) with its Pills ("Uncommon", "x1.5 power"), the Note (why it cannot fuse, the copies taken off the team /
--            Garden first, or what the fusion does). Tapping the Stack opens the shared pet picker (Upgrade context).
--   MIX      Slot_Body, the SwapButton, Slot_Style, the Arrow, the NEW HYBRID card (violet glow, the pet bobbing, the blended
--            name; Pills: rarity, "Flame + Storm" in the hybrid's element order, finish), the Note (a reason, when there is
--            one) and the Info line. Tapping a slot opens the picker (Mix context) with the other slot's species blocked
--            ("In Body" / "In Style", every finish).
--            The move choice (gui-redo Task 12, the owner's note): under each slot Chips_Body / Chips_Style hold an Attack
--            chip (the pet's element attack, "<sword> Flare"; PC adds the element: "... . Flame") over a Special chip ("<star>
--            Leaf Pounce"; PC adds the kind: "... . Pounce"), stage 0's names. In each pair exactly one chip is lit (attribute
--            Lit, a gold border and a check badge); a tap on the other parent's chip moves that move to it. The choice
--            follows the PET: the swap keeps each move with its pet (the letters flip), a new pet in either slot resets it to
--            "BB". Two parents of one element: both attack chips lit and inactive (one element, no choice). The outcome in
--            the owner's words, "Normal attack: Flame (Flare)" / "Special: Pounce (Leaf Pounce)": PC = OutcomeAttack and
--            OutcomeSpecial inside the NEW HYBRID card between its name and its pills; phone = ONE Outcome line under the
--            slot row (in the Info line's place; the kind words drop first when it is too wide, then it wraps inside its 40
--            px, never cut) with a reason note in the right column; portrait = the Outcome line above the Note / Info line.
--            The preview record is built by PetKeys.MixMoves like the server's (Elements order, SpecialFrom).
--   both     the CostBar (the token icon and the price; PC: "You have 12,480 Cloud Tokens", red when short) and FUSE!
--            (pulsing when it can fuse), a TipLine (PC on top; the phone's Upgrade at the bottom), the HintLine (3 s:
--            window-local hints such as why FUSE! is grey, and the server's refusal), the Locked card (no Prestige / no
--            machine yet).
-- No pet picked: opening the Upgrade tab opens the sheet by itself; Mix with an empty slot opens it for the first empty slot
-- (Body first) and, after a pick, once more for the other one while it is still empty; closing the sheet without a pick ends
-- that chain; nothing opens by itself when the context has no pet.
-- FUSE sends Remotes.Fusion("Upgrade", key) / ("Mix", body, style, moves); the server checks everything again and answers with
-- Fusion:FireClient("Result", { Ok, Key, Name, Reason... }). On success the inputs fly into the result, a flash and a confetti
-- burst, the new pet pops in with a NEW! tag, and glowing cubes burst out of the machine's output pod (client-only parts).
--
-- Screen: ScreenGui NimbusFusion (DisplayOrder 22, IgnoreGuiInset) > Window_Fusion (NeonKit.BigRect: 1440 x 880 at 1080p, the
-- PC layout computed in the design box with the 1080p mock as its largest form; 820 x 330 at scale 1 on an 844 x 390 phone;
-- one column on a portrait phone; UIScale "Fit") > Panel (UIScale "Pop": the 0.22 s Back-Out open) > Header (Icon, Title,
-- Tab_Upgrade, Tab_Mix, TokenChip, GemChip, CloseButton), Body (TipLine, Stack > Copy1..3, CopiesText, Slot_Body, Plus,
-- SwapButton, Slot_Style, Chips_Body / Chips_Style > Attack / Special (> Check), Arrow, Result (> ... OutcomeAttack,
-- OutcomeSpecial), Pills > Pill_*, Note, Info, Outcome, CostBar > CostLabel / CostIcon / Cost / Have, FuseButton, HintLine,
-- Locked, Flash, New). On a phone or a touch-only device the window hides Roblox's stick and jump
-- (MenuController.SetTouchHidden("Fusion")) and steps the menu column aside (SetColumnCovered); the cursor is free while it
-- is shown (client/MouseLock). Pet looks are CloudUI.PetViewport (cached by what they show). Every number comes from the
-- catalogs and the synced profile; the server decides. Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local UI = Client:WaitForChild("UI")
local CloudUI = require(UI:WaitForChild("CloudUI"))
local NeonKit = require(UI:WaitForChild("NeonKit"))
local GemIcon = require(UI:WaitForChild("GemIcon"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7a) the token chip's coin; (U7b) the window's icons
local PetPicker = require(UI:WaitForChild("PetPicker"))
local State = require(Client:WaitForChild("State"))

local function safeRequire(name)
	local ok, result = pcall(function()
		local module = Shared:FindFirstChild(name) or Shared:WaitForChild(name, 5)
		return module and require(module) or nil
	end)
	if ok and type(result) == "table" then
		return result
	end
	warn("[FusionController] " .. name .. " is unavailable: " .. tostring(result))
	return nil
end

local PetKeys = safeRequire("PetKeys")
local PetCatalog = safeRequire("PetCatalog")
local TycoonCatalog = safeRequire("TycoonCatalog")
local BattleCatalog = safeRequire("BattleCatalog") -- the move chips' names (ElementAttacks, Specials)

local FusionController = {}
FusionController.Opened = Util.Signal()
FusionController.Closed = Util.Signal()

----------------------------------------------------------------------
-- Tunables (design px; PC = the 1080p mock, Phone = screen px)
----------------------------------------------------------------------
local K = {
	CHIP_COIN = 18, -- (kit-b U7a) the Cloud Token coin before the header chip's balance (a PixelIcon, px)
	DISPLAY_ORDER = 22, -- above NimbusMenu (20) and the Pet Index (21); under the Training Place (23) and the sheet (24)
	RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1440, Y1 = 880 },
	MARGIN = 12,
	PHONE_W = 900,
	SHORT = 560,
	PC_MIN_H = 600,
	PC_MAX_W = 0.76,
	FUSE_TIMEOUT = 6, -- seconds the FUSE button waits for the server before it resets
	MACHINE_RANGE = 24, -- studs: the window closes when the player walks this far from the machine it opened at
	NEAR_RANGE = 30, -- studs: FUSE needs the player this close to their machine (the server allows a little more)
	BACK_ACTION = "NimbusFusionBack",
	PREVIEW_SEED = 4242, -- look seed of the Mix preview (the real hybrid draws its own)
	HINT_SECONDS = 3,
	SERVER_HINT_SECONDS = 4,
	TYPED_GAP = 0.1, -- seconds after a TextBox let go in which an Escape only ended the typing (H.typing)
	OPEN_FROM = 0.86,
	OPEN_TIME = 0.22,
	-- the text width a box must allow: TextService's, never less than this many em per character (the fonts' real widths)
	EM = { GothamBlack = 0.68, GothamBold = 0.66, BuilderSansBold = 0.58, BuilderSans = 0.56, FredokaOne = 0.62 },
	HEAD = {
		PC = {
			Header = 76, HeadPad = 24, Icon = 52, IconText = 36, TitleText = 34, TitleMin = 24, Close = 56, TabH = 56, TabText = 26,
			TabPad = 26, TabGap = 10, TabUpW = 220, TabMixW = 160, ChipH = 48, ChipText = 22, ChipPad = 16, ChipGap = 12, Gap = 16,
		},
		PHONE = {
			Header = 50, HeadPad = 10, Icon = 30, IconText = 22, TitleText = 20, TitleMin = 16, Close = 44, TabH = 44, TabText = 17,
			TabPad = 14, TabGap = 6, TabUpW = 130, TabMixW = 84, ChipH = 38, ChipText = 15, ChipPad = 10, ChipGap = 8, Gap = 8,
		},
	},
	-- PC (the 1080p mock's numbers: k = 1)
	PC = {
		Pad = 40, Text = 60, TipH = 36, TipText = 22, TipMinBody = 700, LineH = 34, LineText = 22, LineMin = 18, CostH = 150,
		CostHMin = 118, CostFull = 760, Bottom = 20, Gap = 14, FuseW = 320, FuseWNarrow = 280, FuseText = 44, HintH = 44, Hint = 20,
		ResultW = 480, ResultH = 470, StackW = 400, StackH = 340, CopiesH = 36, CopiesText = 26, SlotW = 310, SlotH = 400,
		Swap = 72, ArrowUp = 140, ArrowMix = 130, PillH = 38, PillText = 20, PillPad = 14, PillGap = 10,
		-- (Task 12) the move chips under the Mix slots (56 design px tall at every PC size: 44.8 px on screen at the 0.8
		-- factor), the shorter Mix slots above them, the two outcome lines in the NEW HYBRID card
		ChipH = 56, ChipGap = 8, ChipTop = 12, ChipPad = 14, ChipText = 22, ChipMin = 18, Badge = 28, BadgeText = 20,
		MixSlotH = 320, MixSlotMin = 120, OutH = 30, OutHMin = 26, OutText = 22,
	},
	PHONE = {
		Bottom = 48, LineH = 40, Text = 15, PillH = 30, PillPad = 8, PillGap = 6, CostH = 40, FuseH = 60, FuseHMin = 48, HintH = 36,
		ChipH = 44, ChipGap = 4, ChipTop = 4, ChipPad = 8, ChipText = 15, ChipMin = 15, Badge = 20, BadgeText = 15, OutMin = 14,
	},
}
-- the Mix move choice: letter 1 = the parent of the normal attack, letter 2 = the parent of the special (B Body, S Style)
local MOVES = { BB = true, BS = true, SB = true, SS = true }
local FLIP = { BB = "SS", SS = "BB", BS = "SB", SB = "BS" } -- the same moves after the swap (Body and Style trade places)

local Colors = Theme.Colors
local C = {
	White = Colors.White,
	Ink = Colors.TextStroke or Colors.Ink,
	Navy = Color3.fromRGB(11, 16, 48),
	Well = Color3.fromRGB(20, 26, 64),
	WellEdge = Color3.fromRGB(70, 84, 150),
	Muted = Color3.fromRGB(170, 180, 214),
	Gold = Color3.fromRGB(255, 211, 77),
	GoldLabel = Color3.fromRGB(255, 243, 176),
	Good = Colors.Good or Color3.fromRGB(120, 230, 120),
	Bad = Color3.fromRGB(255, 110, 110),
	Warn = Color3.fromRGB(255, 214, 110),
	Violet = Color3.fromRGB(155, 107, 255), -- the machine's violet (header, the NEW HYBRID card)
	Blue = Color3.fromRGB(74, 91, 184),
	Tier = {
		Normal = Color3.fromRGB(74, 80, 112),
		Golden = Color3.fromRGB(255, 196, 64),
		Rainbow = Color3.fromRGB(255, 112, 200),
	},
}
local TOKEN_INFO = Theme.Currency and Theme.Currency.Tokens or { Icon = "token", Color = C.Gold } -- (kit-b U7a) the coin
local GEM_INFO = Theme.Currency and Theme.Currency.Gems or { Color = Colors.Gem } -- (drawn: GemIcon, never a glyph)

-- typography as UTF-8 byte escapes (the source stays plain ASCII). kit-b U7b: the icons are PixelIcons (ICON), the emoji
-- went
local G = {
	Plus = "+",
	Dot = "\194\183",
	Question = "?",
}
local ICON = {
	Machine = "sparkle", -- the Fusion tile's icon (Config.Icons.Fusion): the header and the locked card
	Arrow = "play",
	Swap = "swap",
	Spark = "sparkle",
	Attack = "sword", -- the normal attack chip
	Special = "star", -- the special chip
	Check = "check", -- the lit chip's badge
}
local CHIP_ICON = 18 -- px: a move chip's icon, left of its text (inside ChipPad)
local NEXT_TIER = { Normal = "Golden", Golden = "Rainbow" }
local TIER_RANK = { Normal = 1, Golden = 2, Rainbow = 3 }
local TEXTS = {
	TipUpgrade = "Pick a pet with %d copies. Golden gives x1.5 power, Rainbow x2.5.",
	TipMix = "Tap a slot to pick a pet: Body first, then Style.",
	TipPhone = "Tap the copies to pick another pet. %d copies make 1 Golden; %d Golden make 1 Rainbow.",
	InfoPC = "Your hybrid gets its own random look. Hybrids are one of a kind and can't be fused again.",
	InfoPhone = "Body first, then Style. Your hybrid gets its own random look.",
	LockedSub = "Fuse 3 copies into a Golden or Rainbow pet, or mix two pets into a brand-new hybrid!",
	-- the HintLine when the picker would have nothing to show (review fix)
	EmptyNoPets = "No pets yet! Spin a roulette in the Shop to hatch one.",
	EmptyUpgrade = "Nothing to upgrade yet. Hybrids and Rainbow pets can't go higher.",
	EmptyMix = "You need regular pets to mix. Hybrids can't be mixed again.",
	-- the outcome of the move choice, in the owner's words
	OutAttack = "Normal attack: %s (%s)", -- element, attack name
	OutAttackShort = "Normal attack: %s",
	OutSpecial = "Special: %s (%s)", -- kind, special name
	OutSpecialShort = "Special: %s",
}

----------------------------------------------------------------------
-- Module state
----------------------------------------------------------------------
local initialized = false
local LocalPlayer = nil

local S = {
	Open = false,
	Built = false,
	Tab = "Upgrade",
	UpKey = nil, -- Upgrade input key
	MixA = nil, -- Mix: Body
	MixB = nil, -- Mix: Style
	Moves = "BB", -- Mix: the move choice (see MOVES); it belongs to the pair in MovesFor
	MovesFor = {}, -- { body key, style key } the choice was made for (H.syncMoves)
	Pending = nil, -- { Action, Token, At } while a request waits for the server
	Animating = false,
	Token = 0, -- bumps on every open / close (stale delayed callbacks check it)
	AtMachine = nil, -- the machine model the window was opened at (nil when opened from elsewhere)
	MachineNear = true,
	Plan = nil,
	FuseToken = 0,
	Mode = "PC",
	Portrait = false,
	Rect = nil,
	Sheet = false, -- our picker sheet is up
	SheetToken = 0,
	HintToken = 0,
	TouchOff = false,
	BackBound = false,
	RefreshPending = false,
	TypedAt = -1, -- os.clock() when a TextBox last let go of focus (H.typing)
	Fx = {},
	Warned = {},
	Geo = {}, -- the laid-out boxes paint needs (pills, the note's box, ...)
}
local U = { Views = {}, Copies = {}, Slots = {}, PillList = {}, Chips = {} }
local H = {} -- helpers (one table: the module stays far below Lua's local limit)

local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[FusionController] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok, err
end

local function place(inst, x, y, w, h)
	inst.AnchorPoint = Vector2.new(0, 0)
	inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
end

local function label(parent, name, role, size, props)
	local l = Theme.Label("", role, { Size = size })
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.TextTruncate = Enum.TextTruncate.AtEnd
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

----------------------------------------------------------------------
-- Pets, rules and costs (a mirror of FusionService: the server decides)
----------------------------------------------------------------------
function H.controller(name)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

function H.inMatch()
	return LocalPlayer ~= nil and LocalPlayer:GetAttribute(Config.Attr.InMatch) == true
end

function H.parse(key)
	if not PetKeys or type(key) ~= "string" then
		return nil
	end
	local ok, parsed = pcall(PetKeys.Parse, key)
	if ok and type(parsed) == "table" then
		return parsed
	end
	return nil
end

function H.def(key)
	local ok, def = pcall(State.DefOf, key)
	if ok and type(def) == "table" then
		return def
	end
	if PetKeys then
		local ok2, def2 = pcall(PetKeys.DefOf, key, State.Get())
		if ok2 and type(def2) == "table" then
			return def2
		end
	end
	return nil
end

function H.catalogDef(petId)
	if PetCatalog and type(PetCatalog.Get) == "function" and type(petId) == "string" then
		local ok, def = pcall(PetCatalog.Get, petId)
		if ok and type(def) == "table" then
			return def
		end
	end
	return nil
end

function H.nameOf(def, key)
	if type(def) == "table" then
		return tostring(def.DisplayName or def.Name or key)
	end
	return tostring(key)
end

function H.owned(key)
	local ok, n = pcall(State.OwnedCount, key)
	if ok and type(n) == "number" then
		return n
	end
	return 0
end

function H.equipped(key)
	local ok, n = pcall(State.EquippedCount, key)
	if ok and type(n) == "number" then
		return n
	end
	return 0
end

function H.stage(key)
	if type(key) ~= "string" or type(State.PetStage) ~= "function" then
		return 0
	end
	local ok, n = pcall(State.PetStage, key)
	return (ok and tonumber(n)) or 0
end

function H.home()
	local ok, home = pcall(State.Home)
	if ok and type(home) == "table" then
		return home
	end
	return { Level = 0, Prestige = 0, Stations = {}, Garden = {}, Gym = {} }
end

function H.balance(currency)
	if currency == "Gems" then
		local ok, n = pcall(State.Gems)
		return (ok and type(n) == "number") and n or 0
	end
	local ok, n = pcall(State.Tokens)
	return (ok and type(n) == "number") and n or 0
end

function H.copies()
	local f = TycoonCatalog and TycoonCatalog.Fusion
	local n = type(f) == "table" and tonumber(rawget(f, "Copies")) or nil
	if n and n >= 2 then
		return math.floor(n)
	end
	return 3
end

function H.unlockStars()
	local p = TycoonCatalog and TycoonCatalog.Prestige
	local n = type(p) == "table" and tonumber(p.FusionUnlock) or nil
	return n and math.floor(n) or 1
end

function H.machineLevel()
	local stations = H.home().Stations
	local lv = type(stations) == "table" and tonumber(stations.FusionMachine) or nil
	return lv and math.floor(lv) or 0
end

-- ok, reason
function H.unlocked()
	local stars = tonumber(H.home().Prestige) or 0
	if stars < H.unlockStars() then
		return false, "The Fusion Machine unlocks at Prestige " .. H.unlockStars()
	end
	if H.machineLevel() < 1 then
		return false, "Build the Fusion Machine at your home first"
	end
	return true
end

function H.costOf(action, rarity, tier)
	if not TycoonCatalog or type(TycoonCatalog.FusionCost) ~= "function" then
		return nil
	end
	local ok, cost = pcall(TycoonCatalog.FusionCost, action, rarity, tier, H.machineLevel())
	if not ok or type(cost) ~= "table" then
		return nil
	end
	if type(cost.Gems) == "number" and cost.Gems > 0 then
		return { Currency = "Gems", Amount = math.ceil(cost.Gems) }
	end
	if type(cost.Tokens) == "number" then
		return { Currency = "Tokens", Amount = math.ceil(cost.Tokens) }
	end
	return nil
end

function H.rarityOrder(rarityId)
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarityId then
			return r.Order or 0
		end
	end
	return 0
end

function H.rarityColor(rarityId)
	if rarityId == "Secret" then
		return Color3.fromRGB(150, 110, 232)
	end
	local ok, c = pcall(CloudUI.RarityColor, rarityId)
	return (ok and typeof(c) == "Color3") and c or C.WellEdge
end

function H.commas(n)
	return Util.Commas(math.max(0, math.floor(tonumber(n) or 0)))
end

-- What taking these copies frees: notes for the player (each with a Short form), and whether it would leave no team.
function H.usageNotes(inputs)
	local snap = State.Get()
	local equippedTotal = type(snap.Equipped) == "table" and #snap.Equipped or 0
	local home = H.home()
	local dropped, placedOff = 0, 0
	for _, input in ipairs(inputs) do
		local left = H.owned(input.Key) - input.Count
		dropped = dropped + math.max(0, H.equipped(input.Key) - left)
		local placed = 0
		for _, map in ipairs({ home.Garden, home.Gym }) do
			for _, k in pairs(type(map) == "table" and map or {}) do
				if k == input.Key then
					placed = placed + 1
				end
			end
		end
		placedOff = placedOff + math.max(0, placed - left)
	end
	local notes = {}
	if equippedTotal > 0 and dropped >= equippedTotal then
		return notes, "Those are your only team pets: put another pet in your team first", "Put another pet in your team first"
	end
	if dropped > 0 then
		notes[#notes + 1] = {
			Text = dropped .. " team cop" .. (dropped == 1 and "y is" or "ies are") .. " taken off first; the new pet takes the slot",
			Short = "Takes " .. dropped .. " cop" .. (dropped == 1 and "y" or "ies") .. " off your team",
			Color = C.Warn,
		}
	end
	if placedOff > 0 then
		notes[#notes + 1] = {
			Text = placedOff .. " cop" .. (placedOff == 1 and "y leaves" or "ies leave") .. " the Garden / Gym first; the new pet takes over",
			Short = placedOff .. " cop" .. (placedOff == 1 and "y leaves" or "ies leave") .. " the Garden / Gym first",
			Color = C.Warn,
		}
	end
	return notes, nil
end

----------------------------------------------------------------------
-- The Mix move choice (Task 12)
----------------------------------------------------------------------
-- the catalog defs of two regular pets (any finish), or nil (a hybrid, an unknown or a missing key)
function H.mixDefs(bodyKey, styleKey)
	local pa, pb = H.parse(bodyKey), H.parse(styleKey)
	if not (pa and pb) or pa.HybridId or pb.HybridId then
		return nil
	end
	local da, db = H.catalogDef(pa.PetId), H.catalogDef(pb.PetId)
	if not (da and db) then
		return nil
	end
	return da, db
end

-- The choice belongs to the two pets it was made for: the same pets the other way round (the swap) flip its letters, any
-- other change of pets (a pick, Select, a fusion, a pet that left) resets it to "BB". Returns the current moves.
function H.syncMoves()
	local a, b = S.MixA, S.MixB
	local was = S.MovesFor
	if a ~= was[1] or b ~= was[2] then
		if a ~= nil and b ~= nil and a == was[2] and b == was[1] then
			S.Moves = FLIP[S.Moves] or "BB"
		else
			S.Moves = "BB"
		end
		S.MovesFor = { a, b }
	end
	if not MOVES[S.Moves] then
		S.Moves = "BB"
	end
	return S.Moves
end

-- both parents share an element: the hybrid has one element, so the attack is no choice
function H.sameElement()
	local da, db = H.mixDefs(S.MixA, S.MixB)
	return da ~= nil and da.Element ~= nil and da.Element == db.Element
end

-- a special kind's word ("Pounce", "Storm", ...)
function H.kindWord(kind)
	local specials = BattleCatalog and BattleCatalog.Specials
	local s = type(specials) == "table" and kind ~= nil and specials[kind] or nil
	if type(s) == "table" and type(s.Name) == "string" then
		return s.Name
	end
	return tostring(kind or "")
end

-- The preview of the current selection (the same checks the server makes, in the same order).
function H.computePlan()
	local plan = { Ok = false, Action = S.Tab, Notes = {} }
	local okUnlock, why = H.unlocked()
	if not okUnlock then
		plan.Reason = why
		plan.Locked = true
		return plan
	end
	if not PetKeys then
		plan.Reason = "Fusion is not available right now"
		return plan
	end
	if S.Tab == "Upgrade" then
		local key = S.UpKey
		local parsed = key and H.parse(key)
		if not parsed then
			plan.Reason = "Pick a pet with " .. H.copies() .. " copies"
			plan.Empty = true
			return plan
		end
		local def = H.def(key)
		local base = H.catalogDef(parsed.PetId)
		local nextTier = NEXT_TIER[parsed.Tier]
		plan.Inputs = { { Key = key, Count = H.copies() } }
		plan.InputDef = def
		if parsed.HybridId or not base then
			plan.Reason = "Hybrids are one of a kind: they cannot be upgraded"
			return plan
		end
		if not nextTier then
			plan.Reason = "Rainbow is the best finish: this pet cannot go higher"
			return plan
		end
		plan.Tier = nextTier
		plan.Rarity = base.Rarity
		plan.ResultKey = PetKeys.Make(parsed.PetId, nextTier)
		plan.ResultDef = plan.ResultKey and PetKeys.DefOf(plan.ResultKey) or nil
		plan.ResultName = H.nameOf(plan.ResultDef, plan.ResultKey)
		plan.Cost = H.costOf("Upgrade", base.Rarity, nextTier)
		local have = H.owned(key)
		if have < H.copies() then
			plan.Reason = "You need " .. H.copies() .. " copies of " .. H.nameOf(def, key) .. " (you have " .. have .. ")"
			plan.ReasonShort = "You need " .. H.copies() .. " copies (you have " .. have .. ")"
			return plan
		end
	elseif S.Tab == "Mix" then
		local a, b = S.MixA, S.MixB
		H.syncMoves() -- (every change of pets is seen, also while a slot is empty)
		local pa, pb = a and H.parse(a), b and H.parse(b)
		plan.Inputs = {}
		if pa then
			plan.Inputs[#plan.Inputs + 1] = { Key = a, Count = 1 }
		end
		if pb then
			plan.Inputs[#plan.Inputs + 1] = { Key = b, Count = 1 }
		end
		if not pa or not pb then
			plan.Reason = "Pick two different pets to mix"
			plan.Empty = true
			return plan
		end
		if pa.HybridId or pb.HybridId then
			plan.Reason = "Hybrids cannot be mixed again: pick two regular pets"
			plan.ReasonShort = "Hybrids cannot be mixed again"
			return plan
		end
		if pa.PetId == pb.PetId then
			plan.Reason = "Pick two different pets to mix"
			return plan
		end
		local baseA, baseB = H.catalogDef(pa.PetId), H.catalogDef(pb.PetId)
		if not baseA or not baseB then
			plan.Reason = "Unknown pet"
			return plan
		end
		local rarity = (H.rarityOrder(baseB.Rarity) > H.rarityOrder(baseA.Rarity)) and baseB.Rarity or baseA.Rarity
		local tier = ((TIER_RANK[pb.Tier] or 1) < (TIER_RANK[pa.Tier] or 1)) and pb.Tier or pa.Tier
		local name = "Hybrid"
		if type(PetKeys.BlendName) == "function" then
			local okName, blended = pcall(PetKeys.BlendName, baseA.Name, baseB.Name)
			if okName and type(blended) == "string" then
				name = blended
			end
		end
		-- the move choice builds the record the way the server does (PetKeys.MixMoves): Elements in the attack parent's
		-- order, SpecialFrom = "Style" when the Style gives the special
		local moves = H.syncMoves()
		local elements, specialFrom
		if type(PetKeys.MixMoves) == "function" then
			local okMoves, e, from = pcall(PetKeys.MixMoves, baseA, baseB, moves)
			if okMoves and type(e) == "table" then
				elements, specialFrom = e, from
			end
		end
		if not elements then
			elements = {}
			for _, e in ipairs({ baseA.Element, baseB.Element }) do
				if type(e) == "string" and e ~= elements[1] then
					elements[#elements + 1] = e
				end
			end
		end
		local record = { Body = pa.PetId, Style = pb.PetId, Tier = tier, Rarity = rarity, Name = name, Elements = elements, Seed = K.PREVIEW_SEED, SpecialFrom = specialFrom }
		local previewKey = PetKeys.HybridKey("preview", tier)
		local okDef, def = pcall(PetKeys.DefOf, previewKey, { Hybrids = { preview = record } })
		plan.ResultDef = okDef and def or nil
		plan.ResultSig = "mix:" .. pa.PetId .. "+" .. pb.PetId .. "@" .. tostring(tier) .. "#" .. tostring(elements[1])
		plan.ResultName = (tier ~= "Normal" and (tier .. " ") or "") .. name
		plan.Rarity = rarity
		plan.Tier = tier
		plan.Elements = elements
		plan.Moves = moves
		plan.SpecialFrom = specialFrom
		plan.SameElement = baseA.Element ~= nil and baseA.Element == baseB.Element
		plan.MovesText = FusionController.MovesText(a, b, moves)
		plan.Cost = H.costOf("Mix", rarity, nil)
		if H.owned(a) < 1 or H.owned(b) < 1 then
			plan.Reason = "You do not own those pets"
			return plan
		end
	else
		plan.Reason = "Pick a tab"
		return plan
	end
	if not plan.Cost then
		plan.Reason = "These pets cannot be fused"
		return plan
	end
	local notes, rule, ruleShort = H.usageNotes(plan.Inputs)
	plan.Notes = notes
	if rule then
		plan.Reason = rule
		plan.ReasonShort = ruleShort
		return plan
	end
	local have = H.balance(plan.Cost.Currency)
	plan.CanAfford = have >= plan.Cost.Amount
	if not plan.CanAfford then
		plan.Reason = "Not enough " .. ((plan.Cost.Currency == "Gems") and "Gems" or "Cloud Tokens") .. " (you have " .. H.commas(have) .. ")"
		plan.ReasonShort = "Not enough " .. ((plan.Cost.Currency == "Gems") and "Gems" or "Cloud Tokens")
		return plan
	end
	if H.inMatch() then
		plan.Reason = "Fusion is closed during a match"
		return plan
	end
	plan.Ok = true
	return plan
end

----------------------------------------------------------------------
-- The machine in the world (the player's own Station_FusionMachine)
----------------------------------------------------------------------
function H.myMachine()
	local uid = LocalPlayer and LocalPlayer.UserId
	if not uid then
		return nil
	end
	for _, home in ipairs(CollectionService:GetTagged("NC_Home")) do
		if home:GetAttribute("OwnerUserId") == uid then
			local station = home:FindFirstChild("Station_FusionMachine")
			if station then
				return station
			end
		end
	end
	return nil
end

function H.distanceTo(model)
	local character = LocalPlayer and LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") or nil
	if not root or not model or not model.Parent then
		return math.huge
	end
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if not ok or typeof(pivot) ~= "CFrame" then
		return math.huge
	end
	return (root.Position - pivot.Position).Magnitude
end

-- the output pod (where the FusionPrompt rides), or the model's pivot
function H.outputPoint(model)
	if not model then
		return nil
	end
	local prompt = model:FindFirstChild("FusionPrompt", true)
	local holder = prompt and prompt.Parent
	if holder and holder:IsA("Attachment") then
		return holder.WorldPosition
	end
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok and typeof(pivot) == "CFrame" then
		return pivot.Position + Vector3.new(0, 3, 0)
	end
	return nil
end

----------------------------------------------------------------------
-- Text fit (TextService, never narrower than the font's real widths allow)
----------------------------------------------------------------------
function H.width(text, size, font)
	local ok, v = pcall(function()
		return Theme.Measure(text, font, size, 4096)
	end)
	if ok and typeof(v) == "Vector2" then
		return v.X
	end
	return #tostring(text) * size * 0.5
end

function H.boxW(text, size, font)
	local plain = tostring(text):gsub("<[^>]*>", "")
	local n = 0
	for _ in plain:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
	end
	local name = (typeof(font) == "EnumItem" and font.Name) or tostring(font)
	return math.max(H.width(plain, size, font), n * size * (K.EM[name] or 0.66))
end

-- the first text that fits `width` at a size from maxSize down to minSize; the last text at minSize when none does
function H.fit(lbl, texts, width, maxSize, minSize)
	for _, t in ipairs(texts) do
		local size = maxSize
		while size >= minSize do
			if H.boxW(t, size, Theme.FontOf(lbl)) <= width then
				lbl.Text, lbl.TextSize = t, size
				return t
			end
			size = size - 1
		end
	end
	lbl.Text, lbl.TextSize = texts[#texts], minSize
	return texts[#texts]
end

-- the rows `text` word-wraps into at `width` (math.huge when one word is wider)
function H.rows(text, size, font, width)
	local rows, cur = 0, 0
	local space = H.boxW(" ", size, font)
	for word in string.gmatch(tostring(text), "%S+") do
		local w = H.boxW(word, size, font)
		if w > width then
			return math.huge
		end
		if cur > 0 and cur + space + w <= width then
			cur = cur + space + w
		else
			rows = rows + 1
			cur = w
		end
	end
	return math.max(rows, 1)
end

-- the first text (and size) whose wrapped rows fit `width` x `height`; wraps only when one line is not enough
function H.fitLines(lbl, texts, width, height, maxSize, minSize)
	for _, t in ipairs(texts) do
		local size = maxSize
		while size >= minSize do
			local rows = H.rows(t, size, Theme.FontOf(lbl), width)
			if rows * size * 1.2 <= height + 0.5 then
				lbl.Text, lbl.TextSize, lbl.TextWrapped = t, size, rows > 1
				return t
			end
			size = size - 1
		end
	end
	lbl.Text, lbl.TextSize, lbl.TextWrapped = texts[#texts], minSize, true
	return texts[#texts]
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
function H.ensureGui()
	if U.Gui and U.Gui.Parent then
		return true
	end
	if not (LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")) then
		return false
	end
	U.Gui = CloudUI.NewScreenGui("NimbusFusion", K.DISPLAY_ORDER)
	U.Gui.IgnoreGuiInset = true
	S.Built = false
	U.Views, U.Copies, U.Slots, U.PillList, U.Chips = {}, {}, {}, {}, {}
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if S.Open then
			safe("relayout", H.layout)
		end
	end)
	return true
end

-- a tab: its fill is a sibling frame under the (transparent) button, so the fill's gradient never tints the text
function H.tabButton(name, text)
	local fill = Util.Create("Frame", { Name = name .. "Fill", BorderSizePixel = 0, BackgroundColor3 = C.White, ZIndex = 5, Parent = U.Header })
	Theme.Corner(fill, UDim.new(0, 12))
	Util.Create("UIStroke", { Name = "TabStroke", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2, Color = C.White, Parent = fill })
	Util.Create("UIGradient", { Name = "TabFill", Rotation = 90, Parent = fill })
	local b = Util.Create("TextButton", { Name = name, AutoButtonColor = false, BorderSizePixel = 0, BackgroundTransparency = 1, Text = text, ZIndex = 6, Parent = U.Header })
	Theme.Style(b, "Button", { Size = 26 })
	return b
end

-- a dark pill with a light edge (the balance chips)
function H.chip(name, color)
	local c = label(U.Header, name, "Display", 22, {
		TextColor3 = color, BackgroundTransparency = 0.35, BackgroundColor3 = C.Ink, ZIndex = 5, TextTruncate = Enum.TextTruncate.None,
	})
	Theme.Corner(c, UDim.new(0.5, 0))
	Theme.Stroke(c, C.White, 2, 0.75)
	return c
end

-- a pet card: the label on top, the look, the name, a sub line, a placeholder glyph and a dim cover
function H.petCard(parent, name, class, z)
	local card = NeonKit.Card({ Name = name, Class = class, Color = C.WellEdge, Corner = 18, Floor = true, ZIndex = z, Parent = parent })
	local body = card.Body
	local item = { Card = card, Root = card.Root }
	item.Label = label(body, "Label", "Heading", 26, { ZIndex = z + 3, TextTruncate = Enum.TextTruncate.None })
	item.Art = Util.Create("Frame", { Name = "Art", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z + 1, Parent = body })
	item.Bob = Util.Create("Frame", { Name = "Bob", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = item.Art })
	item.Placeholder = label(body, "Placeholder", "Title", 60, { ZIndex = z + 2, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.None })
	item.PetName = label(body, "PetName", "Heading", 28, { ZIndex = z + 3 })
	item.Sub = label(body, "Sub", "Body", 20, { ZIndex = z + 3, TextColor3 = C.Muted })
	item.Dim = Util.Create("Frame", {
		Name = "Dim", BackgroundColor3 = Color3.fromRGB(8, 10, 28), BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false,
		Size = UDim2.fromScale(1, 1), ZIndex = z + 4, Parent = body,
	})
	Theme.Corner(item.Dim, UDim.new(0, 18))
	item.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = card.Root })
	item.View = { Art = item.Bob, Z = z + 1 }
	return item
end

-- (Task 12) a move chip: its text on the button (inside ChipPad), a border (ChipStroke: gold when lit) and the Check badge
-- that straddles its top-right corner; side = "Body" | "Style", which = "Attack" | "Special"
function H.moveChip(parent, side, which)
	local b = Util.Create("TextButton", {
		Name = which, AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = C.Well, Text = "", ZIndex = 6, Parent = parent,
	})
	Theme.Style(b, "Body", { Size = 18 })
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Corner(b, UDim.new(0, 12))
	local stroke = Theme.Stroke(b, C.WellEdge, 2, 0)
	stroke.Name = "ChipStroke"
	local pad = Util.Create("UIPadding", { Name = "ChipPad", Parent = b })
	local check = label(b, "Check", "Heading", 15, {
		Text = "", BackgroundTransparency = 0, BackgroundColor3 = C.Gold, TextColor3 = C.Navy, ZIndex = 8, Visible = false,
		TextTruncate = Enum.TextTruncate.None, TextXAlignment = Enum.TextXAlignment.Center,
	})
	PixelIcon.Host(check, ICON.Check) -- (kit-b U7b) follows the badge's TextSize
	-- (kit-b U7b) the chip's move icon (sword / star) left of its text, in the padding (the layout widens PaddingLeft for it)
	local icon = PixelIcon.New(b, ICON[which], CHIP_ICON, b.TextColor3)
	icon.Name = "MoveIcon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, -(CHIP_ICON + 6), 0.5, 0)
	icon.ZIndex = 7
	Theme.Corner(check, UDim.new(0.5, 0))
	Theme.Stroke(check, C.Navy, 2, 0)
	pcall(NeonKit.AttachFx, b)
	b.Activated:Connect(function()
		safe("chip", H.onChip, side, which)
	end)
	return { Button = b, Stroke = stroke, Pad = pad, Check = check, Icon = icon }
end

function H.build()
	if S.Built then
		return
	end
	S.Built = true
	local holder = Util.Create("Frame", { Name = "Window_Fusion", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 2, Parent = U.Gui })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	local panel = Util.Create("Frame", {
		Name = "Panel", BackgroundColor3 = C.Navy, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = holder,
	})
	Theme.Corner(panel, UDim.new(0, 18))
	Theme.Stroke(panel, C.Violet, 3, 0)
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel })
	-- header: the violet strip, square at the bottom
	local header = Util.Create("Frame", { Name = "Header", BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
	Theme.Corner(header, UDim.new(0, 18))
	Theme.Gradient(header, Theme.Lighten(C.Violet, 0.12), Theme.Darken(C.Violet, 0.28), 90)
	U.Header = header
	U.HeaderFoot = Util.Create("Frame", { Name = "HeaderFoot", BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 3, Parent = header })
	Theme.Gradient(U.HeaderFoot, Theme.Lighten(C.Violet, 0.12):Lerp(Theme.Darken(C.Violet, 0.28), 0.76), Theme.Darken(C.Violet, 0.28), 90)
	U.Icon = label(header, "Icon", "Title", 36, { ZIndex = 4, Text = "", TextTruncate = Enum.TextTruncate.None })
	PixelIcon.Host(U.Icon, ICON.Machine) -- (kit-b U7b)
	U.Title = Theme.StyleTitle(label(header, "Title", "Title", 34, { ZIndex = 4, Text = "Fusion Machine", TextXAlignment = Enum.TextXAlignment.Left }))
	U.TabUp = H.tabButton("Tab_Upgrade", "UPGRADE")
	U.TabMix = H.tabButton("Tab_Mix", "MIX")
	U.TabUp.Activated:Connect(function()
		safe("tab", H.setTab, "Upgrade")
	end)
	U.TabMix.Activated:Connect(function()
		safe("tab", H.setTab, "Mix")
	end)
	U.TokenChip = H.chip("TokenChip", TOKEN_INFO.Color or C.Gold)
	PixelIcon.Lead(U.TokenChip, TOKEN_INFO.Icon or "token", { Px = K.CHIP_COIN }) -- (kit-b U7a) the coin before the balance
	U.GemChip = H.chip("GemChip", GEM_INFO.Color or Colors.Gem or C.White)
	-- lobby-shop Task 15 (spec 5.7): the gem balance is the drawn gem + the number (GemIcon.Amount), the chip sized to it
	U.GemAmount = GemIcon.Amount(U.GemChip, 0, { TextSize = 22, Color = GEM_INFO.Color or Colors.Gem, ZIndex = 6 })
	U.GemAmount.AnchorPoint = Vector2.new(0.5, 0.5)
	U.GemAmount.Position = UDim2.fromScale(0.5, 0.5)
	U.Close = CloudUI.Button({
		Name = "CloseButton", Text = "", Style = "Red", Size = UDim2.fromOffset(44, 44), TextSize = 22, ZIndex = 5,
		Callback = function()
			FusionController.Close()
		end,
		Parent = header,
	})
	NeonKit.CloseMark(U.Close) -- slop audit 2026-11-12: a drawn X (the U+2715 glyph showed a missing-glyph box)
	-- body
	local body = Util.Create("Frame", { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = panel })
	U.Body = body
	U.Tip = label(body, "TipLine", "Body", 22, { ZIndex = 3, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.None })
	-- Upgrade: the fanned stack of copies (one button) and its count
	U.Stack = Util.Create("TextButton", { Name = "Stack", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = body })
	pcall(NeonKit.AttachFx, U.Stack)
	U.Stack.Activated:Connect(function()
		safe("stack", H.tapSheet, "Upgrade")
	end)
	for i = 1, 3 do
		local item = H.petCard(U.Stack, "Copy" .. i, "Frame", 3 + i * 6)
		U.Copies[i] = item
	end
	U.CopiesText = label(body, "CopiesText", "Heading", 26, { ZIndex = 4 })
	-- Mix: the two slots, the plus and the swap button
	for _, slot in ipairs({ { "Body", "BODY" }, { "Style", "STYLE" } }) do
		local item = H.petCard(body, "Slot_" .. slot[1], "TextButton", 4)
		item.Label.Text = slot[2]
		pcall(NeonKit.AttachFx, item.Root)
		item.Root.Activated:Connect(function()
			safe("slot", H.tapSheet, slot[1])
		end)
		U.Slots[slot[1]] = item
	end
	U.Plus = label(body, "Plus", "Title", 40, { ZIndex = 4, Text = G.Plus, TextTruncate = Enum.TextTruncate.None })
	U.Swap = NeonKit.Button({ Name = "SwapButton", Text = "", Color = C.Blue, Size = UDim2.fromOffset(72, 72), TextSize = 34, ZIndex = 5, Parent = body })
	PixelIcon.Host(U.Swap, ICON.Swap) -- (kit-b U7b)
	local swapPad = U.Swap:FindFirstChildOfClass("UIPadding")
	if swapPad then
		swapPad.PaddingLeft, swapPad.PaddingRight = UDim.new(0, 0), UDim.new(0, 0)
	end
	U.Swap.Activated:Connect(function()
		safe("swap", H.onSwap)
	end)
	-- Mix: the move chips under each slot (above the slots' layer, so a lit chip's badge may overlap a slot's edge)
	for _, side in ipairs({ "Body", "Style" }) do
		local grp = Util.Create("Frame", { Name = "Chips_" .. side, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = body })
		U.Chips[side] = { Root = grp, Attack = H.moveChip(grp, side, "Attack"), Special = H.moveChip(grp, side, "Special"), Form = "pc" }
	end
	-- the outcome: the phone's one line (the PC's two lines live in the result card, below)
	U.Outcome = label(body, "Outcome", "Body", 15, {
		ZIndex = 4, Visible = false, TextColor3 = C.GoldLabel, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.None,
	})
	U.Arrow = label(body, "Arrow", "Title", 60, { ZIndex = 4, Text = "", TextColor3 = C.Gold, TextScaled = true, TextTruncate = Enum.TextTruncate.None })
	PixelIcon.Host(U.Arrow, ICON.Arrow, 45) -- (kit-b U7b)
	-- the result: big and glowing
	U.Result = H.petCard(body, "Result", "Frame", 4)
	U.Result.PetName.Name = "ResultName"
	U.Result.Sub.Visible = false
	for _, name in ipairs({ "OutcomeAttack", "OutcomeSpecial" }) do
		U[name] = label(U.Result.Card.Body, name, "Body", 22, { ZIndex = 7, Visible = false, TextColor3 = C.GoldLabel })
	end
	U.Sparks = {}
	for i = 1, 4 do
		U.Sparks[i] = label(U.Result.Card.Body, "Spark" .. i, "Title", 34, { ZIndex = 9, Text = "", TextColor3 = Color3.fromRGB(255, 248, 208), TextTruncate = Enum.TextTruncate.None, Visible = false })
		PixelIcon.Host(U.Sparks[i], ICON.Spark, 27) -- (kit-b U7b) follows the spark's fade
	end
	U.Shimmer = Util.Create("UIGradient", {
		Name = "Shimmer", Enabled = false, Rotation = 0, Parent = U.Result.Card.Stroke,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 92, 120)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 211, 77)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(72, 224, 120)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(64, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(176, 104, 255)),
		}),
	})
	U.Pills = Util.Create("Frame", { Name = "Pills", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10, Parent = body })
	U.Note = label(body, "Note", "Body", 22, { ZIndex = 4, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.None })
	U.Info = label(body, "Info", "Body", 22, { ZIndex = 4, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.None })
	-- the cost and FUSE!
	local cost = NeonKit.Card({ Name = "CostBar", Color = C.Blue, Corner = 18, Floor = false, Glow = false, ZIndex = 3, Parent = body })
	U.CostBar = cost
	U.CostLabel = label(cost.Body, "CostLabel", "Heading", 30, { ZIndex = 5, Text = "Cost", TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left })
	U.CostIcon = Util.Create("Frame", { Name = "CostIcon", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5, Parent = cost.Body })
	U.Cost = label(cost.Body, "Cost", "Display", 44, { ZIndex = 5, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left })
	U.Have = label(cost.Body, "Have", "Body", 22, { ZIndex = 5, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left })
	U.Fuse = NeonKit.Button({ Name = "FuseButton", Text = "FUSE!", Color = "Green", Size = UDim2.fromOffset(320, 92), TextSize = 44, ZIndex = 5, Parent = body })
	U.Fuse.Activated:Connect(function()
		safe("fuse", H.onFuseTap)
	end)
	U.Hint = label(body, "HintLine", "Heading", 20, {
		ZIndex = 30, Visible = false, BackgroundTransparency = 0.12, BackgroundColor3 = Color3.fromRGB(8, 10, 28), TextWrapped = true,
	})
	Theme.Corner(U.Hint, UDim.new(0, 10))
	-- the fusion animation's flash and NEW! tag
	U.Flash = Util.Create("Frame", { Name = "Flash", BackgroundTransparency = 1, BackgroundColor3 = C.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 25, Parent = body })
	Theme.Corner(U.Flash, UDim.new(0.5, 0))
	U.NewTag = label(body, "New", "Title", 26, {
		ZIndex = 26, Visible = false, Text = "NEW!", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(232, 84, 120), TextTruncate = Enum.TextTruncate.None,
	})
	Theme.Corner(U.NewTag, UDim.new(0, 10))
	Theme.Stroke(U.NewTag, C.Navy, 3, 0)
	-- the locked card (no Prestige / no machine yet): opaque, nothing of the window shows through
	U.Locked = Util.Create("Frame", { Name = "Locked", BackgroundTransparency = 0, BackgroundColor3 = C.White, BorderSizePixel = 0, Visible = false, ZIndex = 20, Parent = body })
	Theme.Corner(U.Locked, UDim.new(0, 18))
	Theme.Gradient(U.Locked, Color3.fromRGB(58, 46, 120), Color3.fromRGB(18, 22, 56), 90)
	U.LockedIcon = label(U.Locked, "Icon", "Title", 64, { ZIndex = 21, Text = "", TextTruncate = Enum.TextTruncate.None })
	PixelIcon.Host(U.LockedIcon, ICON.Machine, 54) -- (kit-b U7b)
	U.LockedText = label(U.Locked, "Text", "Heading", 24, { ZIndex = 21, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
	U.LockedSub = label(U.Locked, "Sub", "Body", 20, { ZIndex = 21, Text = TEXTS.LockedSub, TextWrapped = true, TextColor3 = Color3.fromRGB(196, 186, 240), TextTruncate = Enum.TextTruncate.None })
	-- the cursor is free while the window is shown (client/MouseLock, as the docked windows)
	local mouseLock = Client:FindFirstChild("MouseLock")
	local okLock, lock = pcall(function()
		return mouseLock and require(mouseLock)
	end)
	if okLock and type(lock) == "table" and type(lock.WatchVisible) == "function" then
		safe("mouse lock", lock.WatchVisible, "Dock:" .. holder.Name, holder)
	end
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
function H.layout()
	if not S.Built then
		return
	end
	local r = NeonKit.BigRect(K)
	S.Rect, S.Mode = r, r.mode
	S.Portrait = r.mode == "Phone" and r.portrait == true
	local W = math.floor(r.w / r.scale + 0.5)
	local Hh = math.floor(r.h / r.scale + 0.5)
	place(U.Holder, r.x, r.y, W, Hh)
	U.Fit.Scale = r.scale
	S.W, S.H = W, Hh
	local M = (S.Mode == "Phone") and K.HEAD.PHONE or K.HEAD.PC
	local B = Hh - M.Header
	place(U.Body, 0, M.Header, W, B)
	S.Geo = {}
	local mix = S.Tab == "Mix"
	for _, o in ipairs({ U.Stack, U.CopiesText }) do
		o.Visible = not mix
	end
	for _, o in ipairs({ U.Slots.Body.Root, U.Slots.Style.Root, U.Swap, U.Plus, U.Info }) do
		o.Visible = mix
	end
	if S.Mode ~= "Phone" then
		H.layoutPC(W, B)
	elseif S.Portrait then
		H.layoutPortrait(W, B)
	else
		H.layoutPhone(W, B)
	end
	place(U.Locked, 0, 0, W, B)
	H.layoutLocked(W, B)
	H.refresh()
	H.coverColumn()
end

function H.layoutHeader()
	local M = (S.Mode == "Phone") and K.HEAD.PHONE or K.HEAD.PC
	local W = S.W or 0
	place(U.Header, 0, 0, W, M.Header)
	place(U.HeaderFoot, 0, M.Header - 18, W, 18)
	place(U.Icon, M.HeadPad, (M.Header - M.Icon) / 2, M.Icon, M.Icon)
	U.Icon.TextSize = M.IconText
	place(U.Close, W - M.HeadPad - M.Close, (M.Header - M.Close) / 2, M.Close, M.Close) -- (its drawn X scales with it)
	local right = W - M.HeadPad - M.Close - M.Gap
	local font = Theme.FontOf(U.TabUp)
	local upW = math.max(M.TabUpW, H.boxW("UPGRADE", M.TabText, font) + 2 * M.TabPad)
	local mixW = math.max(M.TabMixW, H.boxW("MIX", M.TabText, font) + 2 * M.TabPad)
	local tokW = H.boxW(U.TokenChip.Text, M.ChipText, Theme.FontOf(U.TokenChip)) + 2 * M.ChipPad + K.CHIP_COIN + 4 -- + the coin
	GemIcon.SetAmount(U.GemAmount, nil, { TextSize = M.ChipText }) -- (re-measures: the gem + the number)
	local gemW = U.GemAmount.Size.X.Offset + 2 * M.ChipPad
	local titleX = M.HeadPad + M.Icon + 8
	local titles = (S.Mode == "Phone") and { "Fusion" } or { "Fusion Machine", "Fusion" }
	local showGem, showTok = S.Mode ~= "Phone", true
	local function chipsW()
		return (showTok and tokW or 0) + ((showTok and showGem) and (M.ChipGap + gemW) or 0)
	end
	local function titleRoom()
		return right - chipsW() - M.Gap - (upW + M.TabGap + mixW) - M.Gap - titleX
	end
	local minTitle = H.boxW(titles[#titles], M.TitleMin, Theme.FontOf(U.Title))
	if titleRoom() < minTitle and showGem then
		showGem = false
	end
	local tabsX = titleX
	U.Title.Visible = titleRoom() >= minTitle
	if U.Title.Visible then
		local room = titleRoom()
		local t = H.fit(U.Title, titles, room, M.TitleText, M.TitleMin)
		local tw = math.min(room, H.boxW(t, U.Title.TextSize, Theme.FontOf(U.Title)) + 4)
		place(U.Title, titleX, 0, tw, M.Header)
		tabsX = titleX + tw + M.Gap
	end
	if tabsX + upW + M.TabGap + mixW + M.Gap > right - chipsW() then
		showGem = false
	end
	if tabsX + upW + M.TabGap + mixW + M.Gap > right - chipsW() then
		showTok = false
	end
	if tabsX + upW + M.TabGap + mixW > right + M.Gap then
		upW = H.boxW("UPGRADE", M.TabText, font) + 2 * M.TabPad * 0.5
		mixW = H.boxW("MIX", M.TabText, font) + 2 * M.TabPad * 0.5
	end
	local ty = (M.Header - M.TabH) / 2
	for _, spec in ipairs({ { U.TabUp, tabsX, upW }, { U.TabMix, tabsX + upW + M.TabGap, mixW } }) do
		local b = spec[1]
		place(b, spec[2], ty, spec[3], M.TabH)
		b.TextSize = M.TabText
		local fill = U.Header:FindFirstChild(b.Name .. "Fill")
		if fill then
			place(fill, spec[2], ty, spec[3], M.TabH)
		end
	end
	U.TokenChip.Visible, U.GemChip.Visible = showTok, showTok and showGem
	local cy = (M.Header - M.ChipH) / 2
	local x = right
	if showTok and showGem then
		x = x - gemW
		place(U.GemChip, x, cy, gemW, M.ChipH)
		x = x - M.ChipGap
	end
	if showTok then
		place(U.TokenChip, x - tokW, cy, tokW, M.ChipH)
	end
	U.TokenChip.TextSize, U.GemChip.TextSize = M.ChipText, M.ChipText
end

-- the inside of a pet card (a copy, a slot or the result): pc = the PC proportions at factor k, else the phone's;
-- artMax (optional) caps the look's size (the shorter Mix slots keep their look clear of the name)
function H.layoutCard(item, w, h, pc, k, isResult, artMax)
	if pc then
		place(item.Label, 0, 12 * k, w, 32 * k)
		item.Label.TextSize = math.max(18, math.floor(26 * k + 0.5))
		local a = math.min(w * 0.74, h * 0.6, artMax or math.huge)
		place(item.Art, (w - a) / 2, 52 * k, a, a)
		place(item.Placeholder, (w - a) / 2, 52 * k, a, a)
		item.Placeholder.TextSize = math.min(100, math.max(40, math.floor(a * 0.42)))
		if isResult then
			place(item.PetName, 6, 346 / 470 * h, w - 12, 44 * k)
		else
			place(item.PetName, 6, h - 86 * k, w - 12, 44 * k)
		end
		place(item.Sub, 6, h - 44 * k, w - 12, 30 * k)
		item.NameMax = math.max(20, math.floor((isResult and 40 or 28) * k + 0.5))
		item.NameMin = 18
		item.Sub.TextSize = 18
		item.SubMax = math.max(18, math.floor(20 * k + 0.5))
	else
		place(item.Label, 0, 4, w, 20)
		item.Label.TextSize = 15
		local nameH = isResult and 26 or 22
		local subH = (item.Sub.Visible and not isResult) and 20 or 0
		local a = math.max(24, math.min(w * 0.74, h - 26 - nameH - subH - 6))
		place(item.Art, (w - a) / 2, 26, a, a)
		place(item.Placeholder, (w - a) / 2, 26, a, a)
		item.Placeholder.TextSize = math.min(100, math.max(30, math.floor(a * 0.42)))
		place(item.PetName, 4, h - nameH - subH - 4, w - 8, nameH)
		place(item.Sub, 4, h - subH - 2, w - 8, subH)
		item.NameMax = isResult and 20 or 15
		item.NameMin = 15
		item.Sub.TextSize = 15
		item.SubMax = 15
	end
	item.W, item.H, item.PC = w, h, pc
end

-- (Task 12) a slot's two move chips (Attack over Special) at x, y in the body, w wide; form = "pc" | "phone"
function H.layoutChips(side, x, y, w, form)
	local M = (form == "pc") and K.PC or K.PHONE
	local g = U.Chips[side]
	place(g.Root, x, y, w, 2 * M.ChipH + M.ChipGap)
	for i, which in ipairs({ "Attack", "Special" }) do
		local c = g[which]
		place(c.Button, 0, (i - 1) * (M.ChipH + M.ChipGap), w, M.ChipH)
		c.Pad.PaddingLeft, c.Pad.PaddingRight = UDim.new(0, M.ChipPad + CHIP_ICON + 6), UDim.new(0, M.ChipPad) -- (+ the move icon)
		-- the badge's centre near the chip's top-right corner (the position is inside the padding: the right edge is w - pad)
		local bs = M.Badge
		c.Check.AnchorPoint = Vector2.new(0, 0)
		c.Check.Position = UDim2.new(1, math.floor(M.ChipPad - bs * 0.75 + 0.5), 0, -math.floor(bs * 0.35 + 0.5))
		c.Check.Size = UDim2.fromOffset(bs, bs)
		c.Check.TextSize = M.BadgeText
	end
	g.Form, g.W, g.H = form, w, M.ChipH
end

-- (Task 12) the NEW HYBRID card on PC: the look, the name, the two outcome lines, then the pills; returns the pills' y
-- inside the card
function H.layoutResultMix(rw, rh, k)
	local P = K.PC
	local item = U.Result
	local pillH = math.max(30, P.PillH * k)
	local lineH = math.max(P.OutHMin, P.OutH * k)
	local pillsY = rh - 14 * k - pillH
	local specialY = pillsY - 4 * k - lineH
	local attackY = specialY - lineH
	local nameH = math.max(28, 44 * k)
	local nameY = attackY - 2 * k - nameH
	local a = math.max(40, math.min(rw * 0.74, nameY - 4 - 52 * k))
	place(item.Art, (rw - a) / 2, 52 * k, a, a)
	place(item.Placeholder, (rw - a) / 2, 52 * k, a, a)
	item.Placeholder.TextSize = math.min(100, math.max(40, math.floor(a * 0.42)))
	place(item.PetName, 6, nameY, rw - 12, nameH)
	place(U.OutcomeAttack, 10, attackY, rw - 20, lineH)
	place(U.OutcomeSpecial, 10, specialY, rw - 20, lineH)
	S.Geo.Outcome = { W = rw - 20, Max = math.max(18, math.floor(P.OutText * k + 0.5)), Min = 18 }
	return pillsY, pillH
end

function H.layoutPC(W, B)
	local P = K.PC
	local mix = S.Tab == "Mix"
	local tip = B >= P.TipMinBody
	U.Tip.Visible = tip
	place(U.Tip, P.Text, 14, W - 2 * P.Text, P.TipH)
	S.Geo.Tip = { W - 2 * P.Text, P.TipH, P.TipText, 18 }
	local cbh = (B >= P.CostFull) and P.CostH or P.CostHMin
	local costY = B - P.Bottom - cbh
	local fuseW = (W >= 1300) and P.FuseW or P.FuseWNarrow
	local fuseH = (cbh >= P.CostH) and 92 or 88
	place(U.Fuse, W - P.Pad - fuseW, costY + (cbh - fuseH) / 2, fuseW, fuseH)
	U.Fuse.TextSize = (cbh >= P.CostH) and P.FuseText or 40
	place(U.CostBar.Root, P.Pad, costY, W - 2 * P.Pad - fuseW - 24, cbh)
	H.layoutCost(W - 2 * P.Pad - fuseW - 24, cbh, "pc")
	local lineY = costY - P.Gap - P.LineH
	local rowBottom
	if mix then
		place(U.Info, P.Text, lineY, W - 2 * P.Text, P.LineH)
		place(U.Note, P.Text, lineY - P.LineH - 6, W - 2 * P.Text, P.LineH)
		rowBottom = lineY - P.LineH - 6 - 10
	else
		place(U.Note, P.Text, lineY, W - 2 * P.Text, P.LineH)
		rowBottom = lineY - 10
	end
	S.Geo.Note = { W - 2 * P.Text, P.LineH, P.LineText, P.LineMin }
	S.Geo.Info = { W - 2 * P.Text, P.LineH, P.LineText, P.LineMin }
	local rowTop = tip and P.Text or P.Gap
	local rowH = rowBottom - rowTop
	local cy = rowTop + rowH / 2
	local needW = mix and (P.SlotW + 22 + P.Swap + 22 + P.SlotW + 30 + P.ArrowMix + 30 + P.ResultW)
		or (P.StackW + 60 + P.ArrowUp + 60 + P.ResultW)
	local k = math.min(1, rowH / P.ResultH, (W - 2 * P.Pad) / needW)
	S.K = k
	local x0 = (W - needW * k) / 2
	local rw, rh = P.ResultW * k, P.ResultH * k
	local rx
	if mix then
		-- (Task 12) each slot over its two move chips (the chips keep their 56 px; the slot gives up the height), the column
		-- centred on the row like the result
		local sw = P.SlotW * k
		local chipsH = P.ChipTop + 2 * P.ChipH + P.ChipGap
		local sh = math.max(P.MixSlotMin, math.min(P.MixSlotH * k, rowH - chipsH))
		local top = cy - (sh + chipsH) / 2
		local sc = top + sh / 2 -- the slots' centre: the plus and the swap button sit on it
		place(U.Slots.Body.Root, x0, top, sw, sh)
		local swap = math.max(56, P.Swap * k)
		local sx = x0 + sw + 22 * k + (P.Swap * k - swap) / 2
		place(U.Plus, sx, sc - 50 * k - swap / 2, swap, swap)
		U.Plus.TextSize = math.max(28, math.floor(40 * k))
		place(U.Swap, sx, sc + 46 * k - swap / 2, swap, swap)
		U.Swap.TextSize = math.max(26, math.floor(34 * k))
		local styleX = x0 + (P.SlotW + 44 + P.Swap) * k
		place(U.Slots.Style.Root, styleX, top, sw, sh)
		for _, item in pairs(U.Slots) do
			item.Sub.Visible = true
			H.layoutCard(item, sw, sh, true, k, false, sh - 138 * k - 6)
		end
		H.layoutChips("Body", x0, top + sh + P.ChipTop, sw, "pc")
		H.layoutChips("Style", styleX, top + sh + P.ChipTop, sw, "pc")
		local ax = x0 + (2 * P.SlotW + 44 + P.Swap + 30) * k
		place(U.Arrow, ax, cy - P.ArrowMix * k / 2, P.ArrowMix * k, P.ArrowMix * k)
		rx = ax + (P.ArrowMix + 30) * k
	else
		local stW, stH = P.StackW * k, P.StackH * k
		local colH = stH + P.Gap * k + P.CopiesH * k
		local top = cy - colH / 2
		place(U.Stack, x0, top, stW, stH)
		H.layoutStack(stW, stH, true, k)
		place(U.CopiesText, x0, top + stH + P.Gap * k, stW, P.CopiesH * k)
		U.CopiesText.TextSize = math.max(20, math.floor(P.CopiesText * k + 0.5))
		local ax = x0 + (P.StackW + 60) * k
		place(U.Arrow, ax, cy - P.ArrowUp * k / 2, P.ArrowUp * k, P.ArrowUp * k)
		rx = ax + (P.ArrowUp + 60) * k
	end
	U.Arrow.Rotation = 0
	local ry = cy - rh / 2
	place(U.Result.Root, rx, ry, rw, rh)
	H.layoutCard(U.Result, rw, rh, true, k, true)
	H.layoutSparks(rw, rh, 34 * k)
	-- the pills inside the result card, under its name (Mix: under the two outcome lines)
	local pillsY = 404 / 470 * rh
	if mix then
		pillsY = H.layoutResultMix(rw, rh, k)
	end
	S.Geo.Pills = { X = rx + 8, Y = ry + pillsY, W = rw - 16, MaxH = math.max(30, P.PillH * k), H = math.max(30, P.PillH * k),
		Text = P.PillText, Min = 18, Pad = P.PillPad, Gap = P.PillGap, Center = true }
	place(U.Hint, P.Pad + 40, B - P.HintH - 10, W - 2 * P.Pad - 80, P.HintH)
	U.Hint.TextSize = P.Hint
end

-- the three fanned copies inside the Stack button
function H.layoutStack(w, h, pc, k)
	local cw, ch, offs
	if pc then
		cw, ch = 240 * k, 320 * k
		offs = { { 14 * k, 18 * k, -7 }, { 74 * k, 8 * k, -1 }, { 134 * k, 0, 5 } }
	else
		cw = math.min(116 * k, w * 0.6)
		ch = math.min(156, h - 8)
		local step = math.max(0, (w - cw - 6) / 2)
		offs = { { 2, 8, -7 }, { 2 + step, 4, -1 }, { 2 + 2 * step, 0, 5 } }
	end
	for i, item in ipairs(U.Copies) do
		local o = offs[i]
		local hh = (i == 3) and ch or (ch - (pc and 12 * k or 6))
		place(item.Root, o[1], o[2], cw, hh)
		item.Root.Rotation = o[3]
		item.Sub.Visible = pc and i == 3
		H.layoutCard(item, cw, hh, pc, k, false)
		item.Label.Visible = i == 3
		item.PetName.Visible = i == 3
	end
end

function H.layoutSparks(w, h, size)
	local spots = { { 0.12, 0.18 }, { 0.84, 0.14 }, { 0.78, 0.62 }, { 0.16, 0.58 } }
	for i, spark in ipairs(U.Sparks) do
		place(spark, w * spots[i][1] - size / 2, h * spots[i][2] - size / 2, size, size)
		spark.TextSize = math.max(16, math.floor(size))
	end
end

-- the cost bar's inside: pc (the 1080p bar, or its 118 tall form), phone (one 40 px row), portrait (two rows)
function H.layoutCost(w, h, form)
	local hasLabel = form == "pc"
	U.CostLabel.Visible = hasLabel
	U.Have.Visible = form ~= "phone"
	if form == "pc" then
		local full = h >= K.PC.CostH
		local pad = full and 40 or 24
		local rowY, rowH = full and 22 or 12, full and 56 or 48
		place(U.CostLabel, pad, rowY, full and 110 or 90, rowH)
		U.CostLabel.TextSize = full and 30 or 26
		local ix = pad + (full and 110 or 96)
		local icon = full and 56 or 48
		place(U.CostIcon, ix, rowY, icon, icon)
		S.Geo.IconPx = full and 44 or 38
		place(U.Cost, ix + icon + 10, rowY, math.max(40, w - ix - icon - 10 - pad), rowH)
		U.Cost.TextSize = full and 44 or 40
		place(U.Have, pad, full and 88 or 70, w - 2 * pad, full and 34 or 32)
		S.Geo.Have = { w - 2 * pad, full and 34 or 32, full and 22 or 20, 18 }
	elseif form == "portrait" then
		place(U.CostIcon, 8, 3, 28, 28)
		S.Geo.IconPx = 24
		place(U.Cost, 40, 0, w - 48, 32)
		U.Cost.TextSize = 22
		place(U.Have, 8, 32, w - 16, 22)
		S.Geo.Have = { w - 16, 22, 15, 14 }
	else
		place(U.CostIcon, 6, (h - 30) / 2, 30, 30)
		S.Geo.IconPx = 26
		place(U.Cost, 42, 0, w - 48, h)
		U.Cost.TextSize = 24
	end
end

function H.layoutLocked(W, B)
	local phone = S.Mode == "Phone"
	local icon = phone and 64 or 90
	place(U.LockedIcon, (W - icon) / 2, B * 0.42 - icon, icon, icon)
	U.LockedIcon.TextSize = phone and 46 or 64
	local tw = math.min(W - 60, 900)
	place(U.LockedText, (W - tw) / 2, B * 0.46, tw, phone and 44 or 64)
	U.LockedText.TextSize = phone and 18 or 24
	place(U.LockedSub, (W - tw) / 2, B * 0.46 + (phone and 52 or 76), tw, phone and 40 or 56)
	U.LockedSub.TextSize = phone and 15 or 20
end

function H.layoutPhone(W, B)
	local P = K.PHONE
	local mix = S.Tab == "Mix"
	local bottomY = B - P.Bottom
	local rowTop, rowBottom = 4, bottomY - 8
	local rowH = rowBottom - rowTop
	local kx = math.min(1, (W - 24) / 796)
	S.K = kx
	U.Tip.Visible = not mix
	place(U.Tip, 14, bottomY, W - 28, P.LineH)
	S.Geo.Tip = { W - 28, P.LineH, P.Text, 15 }
	local colX
	local resW, resH = math.max(136, (mix and 176 or 184) * kx), math.min(206, rowH)
	if mix then
		-- (Task 12) each slot over its two move chips; the slot gives up the height the chips need
		local sw = math.max(100, 130 * kx)
		local sh = math.min(172, rowH - (P.ChipTop + 2 * P.ChipH + P.ChipGap))
		local swap = 44
		local x = 14
		local styleX = x + sw + 16 + swap
		place(U.Slots.Body.Root, x, rowTop, sw, sh)
		place(U.Swap, x + sw + 8, rowTop + (sh - swap) / 2, swap, swap)
		U.Swap.TextSize = 24
		U.Plus.Visible = false
		place(U.Slots.Style.Root, styleX, rowTop, sw, sh)
		for _, item in pairs(U.Slots) do
			item.Sub.Visible = true
			H.layoutCard(item, sw, sh, false, kx, false)
		end
		H.layoutChips("Body", x, rowTop + sh + P.ChipTop, sw, "phone")
		H.layoutChips("Style", styleX, rowTop + sh + P.ChipTop, sw, "phone")
		local aw = math.max(34, 46 * kx)
		local ax = x + 2 * sw + 24 + swap
		local rx = ax + aw + 8
		place(U.Arrow, ax, rowTop + resH / 2 - aw / 2, aw, aw)
		place(U.Result.Root, rx, rowTop, resW, resH)
		colX = rx + resW + 12
		-- the bottom line: the Outcome when both pets are picked, else the Info (a reason note goes to the right column)
		place(U.Info, 14, bottomY, W - 28, P.LineH)
		place(U.Outcome, 14, bottomY, W - 28, P.LineH)
		S.Geo.Info = { W - 28, P.LineH, P.Text, 15 }
		S.Geo.Outcome = { W = W - 28, H = P.LineH, Max = P.Text, Min = P.OutMin }
	else
		local stW = 190 * kx
		local copiesH = 22
		local stH = rowH - copiesH - 8
		place(U.Stack, 14, rowTop + 2, stW, stH)
		H.layoutStack(stW, stH, false, kx)
		place(U.CopiesText, 14, rowTop + 2 + stH + 4, stW + 30, copiesH)
		U.CopiesText.TextSize = 15
		local aw = math.max(34, 50 * kx)
		local ax = 14 + stW + 8
		local rx = ax + aw + 8
		place(U.Arrow, ax, rowTop + resH / 2 - aw / 2, aw, aw)
		place(U.Result.Root, rx, rowTop, resW, resH)
		colX = rx + resW + 14
	end
	U.Arrow.Rotation = 0
	H.layoutCard(U.Result, resW, resH, false, kx, true)
	H.layoutSparks(resW, resH, 16)
	local colW = W - 12 - colX
	local fuseH = (rowH >= 200) and P.FuseH or P.FuseHMin
	local fuseY = rowBottom - fuseH
	place(U.Fuse, colX, fuseY, colW, fuseH)
	U.Fuse.TextSize = (fuseH >= P.FuseH) and 26 or 22
	local costY = fuseY - 8 - P.CostH
	place(U.CostBar.Root, colX, costY, colW, P.CostH)
	H.layoutCost(colW, P.CostH, "phone")
	local pillsTop = rowTop + 4
	if mix then
		S.Geo.Pills = { X = colX, Y = pillsTop, W = colW, MaxH = costY - 6 - pillsTop, H = P.PillH, Text = P.Text, Min = 15, Pad = P.PillPad, Gap = P.PillGap }
		-- (Task 12) a reason note sits under one row of pills (H.paint keeps the pills to that row while a note shows)
		local ny = pillsTop + P.PillH + 6
		place(U.Note, colX, ny, colW, costY - 6 - ny)
		S.Geo.Note = { colW, costY - 6 - ny, P.Text, 15 }
		S.Geo.MixCol = { PillsAll = costY - 6 - pillsTop, PillsNote = P.PillH }
	else
		S.Geo.Pills = { X = colX, Y = pillsTop, W = colW, MaxH = P.PillH, H = P.PillH, Text = P.Text, Min = 15, Pad = P.PillPad, Gap = P.PillGap }
		-- the note between the pills and the cost (it moves up when the pills take one row less)
		local ny = pillsTop + P.PillH + 6
		place(U.Note, colX, ny, colW, costY - 6 - ny)
		S.Geo.Note = { colW, costY - 6 - ny, P.Text, 15 }
	end
	place(U.Hint, 24, B - P.HintH - 6, W - 48, P.HintH)
	U.Hint.TextSize = 15
end

function H.layoutPortrait(W, B)
	local P = K.PHONE
	local mix = S.Tab == "Mix"
	local pad = 12
	U.Tip.Visible = false
	local fuseW, fuseH = 150, 56
	local fuseY = B - 8 - fuseH
	place(U.Fuse, W - pad - fuseW, fuseY, fuseW, fuseH)
	U.Fuse.TextSize = 24
	place(U.CostBar.Root, pad, fuseY, W - 2 * pad - fuseW - 8, fuseH)
	H.layoutCost(W - 2 * pad - fuseW - 8, fuseH, "portrait")
	local lineY = fuseY - 8 - P.LineH
	-- (Task 12) Mix: the Outcome line above the Note / Info line
	local outY = lineY - 4 - P.LineH
	local pillsY = (mix and outY or lineY) - 6 - P.PillH
	S.Geo.Pills = { X = pad, Y = pillsY, W = W - 2 * pad, MaxH = P.PillH, H = P.PillH, Text = P.Text, Min = 15, Pad = P.PillPad, Gap = P.PillGap, Center = true }
	place(U.Note, pad, lineY, W - 2 * pad, P.LineH)
	S.Geo.Note = { W - 2 * pad, P.LineH, P.Text, 15 }
	place(U.Info, pad, lineY, W - 2 * pad, P.LineH)
	S.Geo.Info = { W - 2 * pad, P.LineH, P.Text, 15 }
	place(U.Outcome, pad, outY, W - 2 * pad, P.LineH)
	S.Geo.Outcome = { W = W - 2 * pad, H = P.LineH, Max = P.Text, Min = P.OutMin }
	local regionTop, regionBottom = 6, pillsY - 8
	local arrowH = 32
	local resW = math.min(W - 2 * pad, 220)
	local y
	if mix then
		local swap = 44
		local sw = math.min(150, (W - 2 * pad - swap - 16) / 2)
		local chipsH = P.ChipTop + 2 * P.ChipH + P.ChipGap
		local flex = regionBottom - regionTop - (4 + arrowH + 4) - chipsH
		local kv = math.min(1, flex / (172 + 206))
		local sh, rh = 172 * kv, 206 * kv
		y = regionTop + math.max(0, (flex - sh - rh) / 2)
		local x0 = (W - (2 * sw + swap + 16)) / 2
		local styleX = x0 + sw + 16 + swap
		place(U.Slots.Body.Root, x0, y, sw, sh)
		place(U.Swap, x0 + sw + 8, y + (sh - swap) / 2, swap, swap)
		U.Swap.TextSize = 24
		U.Plus.Visible = false
		place(U.Slots.Style.Root, styleX, y, sw, sh)
		for _, item in pairs(U.Slots) do
			item.Sub.Visible = true
			H.layoutCard(item, sw, sh, false, 1, false)
		end
		H.layoutChips("Body", x0, y + sh + P.ChipTop, sw, "phone")
		H.layoutChips("Style", styleX, y + sh + P.ChipTop, sw, "phone")
		y = y + sh + chipsH + 4
		place(U.Arrow, (W - arrowH) / 2, y, arrowH, arrowH)
		y = y + arrowH + 4
		place(U.Result.Root, (W - resW) / 2, y, resW, rh)
		H.layoutCard(U.Result, resW, rh, false, 1, true)
		H.layoutSparks(resW, rh, 16)
	else
		local copiesH = 22
		local flex = regionBottom - regionTop - (4 + copiesH + 4 + arrowH + 4)
		local kv = math.min(1, flex / (160 + 206))
		local stH, rh = 160 * kv, 206 * kv
		local stW = 190 * math.max(0.7, kv)
		y = regionTop + math.max(0, (flex - stH - rh) / 2)
		place(U.Stack, (W - stW) / 2, y, stW, stH)
		H.layoutStack(stW, stH, false, math.max(0.7, kv))
		y = y + stH + 4
		place(U.CopiesText, pad, y, W - 2 * pad, copiesH)
		U.CopiesText.TextSize = 15
		y = y + copiesH + 4
		place(U.Arrow, (W - arrowH) / 2, y, arrowH, arrowH)
		y = y + arrowH + 4
		place(U.Result.Root, (W - resW) / 2, y, resW, rh)
		H.layoutCard(U.Result, resW, rh, false, 1, true)
		H.layoutSparks(resW, rh, 16)
	end
	U.Arrow.Rotation = 90
	place(U.Hint, pad + 6, B - 44, W - 2 * pad - 12, 38)
	U.Hint.TextSize = 15
end

----------------------------------------------------------------------
-- Paint
----------------------------------------------------------------------
function H.refresh()
	if not S.Built then
		return
	end
	-- drop selections the player no longer owns (fused away, traded...)
	if S.UpKey and H.owned(S.UpKey) < 1 then
		S.UpKey = nil
	end
	if S.MixA and H.owned(S.MixA) < 1 then
		S.MixA = nil
	end
	if S.MixB and H.owned(S.MixB) < 1 then
		S.MixB = nil
	end
	local machine = S.AtMachine or H.myMachine()
	S.MachineNear = machine == nil or H.distanceTo(machine) <= K.NEAR_RANGE
	local plan = H.computePlan()
	S.Plan = plan
	H.paintHeader()
	H.paint(plan)
end

function H.refreshSoon()
	if S.RefreshPending then
		return
	end
	S.RefreshPending = true
	task.defer(function()
		S.RefreshPending = false
		if S.Open and not S.Animating then
			safe("refresh", H.refresh)
		end
	end)
end

function H.short(n)
	n = math.max(0, math.floor(tonumber(n) or 0))
	if n < 1000000 then
		return H.commas(n)
	end
	return Theme.ShortNumber(n)
end

function H.paintHeader()
	U.TokenChip.Text = H.short(H.balance("Tokens"))
	GemIcon.SetAmount(U.GemAmount, H.short(H.balance("Gems")))
	for _, spec in ipairs({ { U.TabUp, "Upgrade" }, { U.TabMix, "Mix" } }) do
		local b, on = spec[1], S.Tab == spec[2]
		local selected = ColorSequence.new(Theme.Lighten(C.Violet, 0.55), Theme.Darken(C.Violet, 0.05))
		-- kit B (no outline): the selected tab's ink is the one that reads on its pale violet face (brown)
		b.TextColor3 = on and Theme.TextOn(selected) or Theme.Lighten(C.Muted, 0.4) -- (unselected: a pale muted ink, 4.5:1 on the header)
		b:SetAttribute("Selected", on)
		local fill = U.Header:FindFirstChild(b.Name .. "Fill")
		if fill then
			fill.BackgroundColor3 = on and C.White or C.Ink
			fill.BackgroundTransparency = on and 0 or 0.55
			local grad = fill:FindFirstChild("TabFill")
			if grad then
				grad.Color = on and selected or ColorSequence.new(C.White, C.White)
			end
			local st = fill:FindFirstChild("TabStroke")
			if st then
				st.Color = on and C.Ink or C.White
				st.Transparency = on and 0 or 0.8
			end
		end
	end
	H.layoutHeader()
end

-- one pet look (cached by what it shows)
function H.setView(rec, def, sig, stage, detail)
	stage = math.floor(tonumber(stage) or 0)
	local want = def and (tostring(sig) .. "#" .. stage .. "#" .. tostring(detail)) or nil
	if rec.Sig == want then
		return
	end
	rec.Sig = want
	if rec.Handle then
		pcall(rec.Handle.Destroy)
		rec.Handle = nil
	end
	if def then
		local ok, handle = pcall(CloudUI.PetViewport, rec.Art, def, UDim2.fromScale(1, 1), {
			Detail = stage >= 1 and "Low" or (detail or "High"),
			Evolved = stage >= 1 and stage or nil,
			Spin = "spin",
			ZIndex = rec.Z,
		})
		if ok then
			rec.Handle = handle
		end
	end
end

-- the name of a pet on a card: the whole name, else the last word
function H.cardName(item, text, color)
	item.PetName.TextColor3 = color or C.White
	local last = tostring(text):match("(%S+)%s*$") or tostring(text)
	H.fit(item.PetName, { text, last }, item.PetName.Size.X.Offset, item.NameMax or 28, item.NameMin or 15)
end

function H.subOf(def, pc)
	if type(def) ~= "table" then
		return ""
	end
	local element = def.Element or (type(def.Elements) == "table" and def.Elements[1]) or ""
	if pc then
		return tostring(def.Rarity or "") .. " " .. G.Dot .. " " .. tostring(element)
	end
	return tostring(element)
end

function H.paintCard(item, key, labelText)
	local def = key and H.def(key) or nil
	item.Label.Text = labelText or item.Label.Text
	item.Card.SetColor(def and H.rarityColor(def.Rarity) or C.WellEdge)
	item.Placeholder.Text = G.Plus
	item.Placeholder.Visible = def == nil
	if def then
		H.cardName(item, H.nameOf(def, key))
		H.fit(item.Sub, { H.subOf(def, item.PC), H.subOf(def, false) }, item.Sub.Size.X.Offset, item.SubMax or 18, item.PC and 18 or 15)
		item.Sub.TextColor3 = C.Muted
	else
		H.cardName(item, "Pick a pet", C.Muted)
		item.Sub.Text = ""
	end
	H.setView(item.View, def, key, key and H.stage(key) or 0, "High")
end

function H.paintStack(plan)
	local key = S.UpKey
	local def = key and H.def(key) or nil
	local have = key and H.owned(key) or 0
	for i, item in ipairs(U.Copies) do
		-- the front card always shows the pet; the back ones only the copies you have
		local shows = def ~= nil and (i == 3 or have >= 4 - i)
		item.Card.SetColor(def and H.rarityColor(def.Rarity) or C.WellEdge)
		item.Label.Text = "COPIES"
		item.Placeholder.Text = (i == 3) and G.Plus or G.Question
		item.Placeholder.Visible = not shows
		item.Dim.Visible = i ~= 3 and not shows
		if i == 3 then
			if def then
				H.cardName(item, H.nameOf(def, key))
				H.fit(item.Sub, { H.subOf(def, true) }, item.Sub.Size.X.Offset, item.SubMax or 18, 18)
			else
				H.cardName(item, "Pick a pet", C.Muted)
				item.Sub.Text = ""
			end
		end
		H.setView(item.View, shows and def or nil, key, H.stage(key), (i == 3) and "High" or "Low")
	end
	if def then
		U.CopiesText.Text = "x" .. have .. " owned " .. G.Dot .. " uses " .. H.copies()
		U.CopiesText.TextColor3 = (have >= H.copies()) and C.White or C.Warn
	else
		U.CopiesText.Text = "Tap to pick a pet"
		U.CopiesText.TextColor3 = C.Muted
	end
	H.fit(U.CopiesText, { U.CopiesText.Text }, U.CopiesText.Size.X.Offset, U.CopiesText.TextSize, S.Mode == "Phone" and 15 or 18)
end

function H.paintResult(plan)
	local item = U.Result
	local mix = S.Tab == "Mix"
	local tier = plan.Tier
	local color
	if mix then
		color = C.Violet
		H.fit(item.Label, { "NEW HYBRID", "NEW" }, item.Label.Size.X.Offset - 8, item.Label.TextSize, S.Mode == "Phone" and 15 or 18)
		item.Label.TextColor3 = C.Gold
	else
		color = (tier and C.Tier[tier]) or C.WellEdge
		item.Label.Text = tier and string.upper(tier) or "NEXT FINISH"
		item.Label.TextColor3 = (tier == "Golden") and C.GoldLabel or C.White
	end
	item.Card.SetColor(color)
	U.Shimmer.Enabled = (not mix) and tier == "Rainbow"
	for _, spark in ipairs(U.Sparks) do
		spark.Visible = (not mix) and plan.ResultDef ~= nil and (tier == "Golden" or tier == "Rainbow")
	end
	item.Placeholder.Text = G.Question
	item.Placeholder.Visible = plan.ResultDef == nil
	if plan.ResultDef then
		H.cardName(item, plan.ResultName or H.nameOf(plan.ResultDef), C.White)
	else
		H.cardName(item, mix and "Pick two pets" or "Pick a pet", C.Muted)
	end
	if not S.Animating then
		local keep = 0
		if not mix and plan.ResultKey then
			keep = math.max(H.stage(S.UpKey), H.stage(plan.ResultKey))
		end
		H.setView(item.View, plan.ResultDef, plan.ResultSig or plan.ResultKey, keep, "High")
	end
end

function H.tierWord(mult)
	if mult == math.floor(mult) then
		return "x" .. tostring(math.floor(mult)) .. " power"
	end
	return "x" .. string.format("%.1f", mult) .. " power"
end

-- the pills: { { Name, Text, Color } } laid in rows inside S.Geo.Pills (centred on PC); a pill that does not fit is left out
function H.paintPills(plan)
	local list = {}
	if plan.ResultDef then
		if plan.Rarity then
			list[#list + 1] = { "Pill_Rarity", tostring(plan.Rarity), Theme.Darken(H.rarityColor(plan.Rarity), 0.35) }
		end
		if S.Tab == "Upgrade" and plan.Tier then
			local mult = (PetKeys and PetKeys.TierMultiplier and PetKeys.TierMultiplier[plan.Tier]) or 1
			list[#list + 1] = { "Pill_Power", H.tierWord(mult), Theme.Darken(C.Tier.Golden, 0.45) }
		elseif S.Tab == "Mix" then
			local elements = plan.Elements or {}
			if #elements > 0 then
				local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[elements[1]]
				list[#list + 1] = { "Pill_Elements", table.concat(elements, " + "), Theme.Darken(info and info.Color or C.Warn, 0.4) }
			end
			list[#list + 1] = { "Pill_Tier", tostring(plan.Tier or "Normal"), Theme.Darken(C.Tier[plan.Tier or "Normal"] or C.Tier.Normal, 0.3) }
		end
	end
	local geo = S.Geo.Pills
	local used = {}
	if geo then
		local size = geo.Text
		local rows, row, rowW = {}, {}, 0
		local function widthOf(text, s)
			return math.ceil(H.boxW(text, s, Theme.Fonts.Heading) + 2 * geo.Pad)
		end
		-- PC: one row; the text steps down to its floor before a pill drops
		if geo.Center and geo.MaxH < 2 * geo.H then
			local total
			repeat
				total = 0
				for i, p in ipairs(list) do
					total = total + widthOf(p[2], size) + (i > 1 and geo.Gap or 0)
				end
				if total > geo.W and size > geo.Min then
					size = size - 1
				end
			until total <= geo.W or size <= geo.Min
		end
		for _, p in ipairs(list) do
			local w = math.min(widthOf(p[2], size), geo.W)
			if #row > 0 and rowW + geo.Gap + w > geo.W then
				rows[#rows + 1] = { Items = row, W = rowW }
				row, rowW = {}, 0
			end
			row[#row + 1] = { P = p, W = w }
			rowW = rowW + (#row > 1 and geo.Gap or 0) + w
		end
		if #row > 0 then
			rows[#rows + 1] = { Items = row, W = rowW }
		end
		local y = geo.Y
		for _, r in ipairs(rows) do
			if y - geo.Y + geo.H > geo.MaxH + 0.5 then
				break
			end
			local x = geo.Center and (geo.X + (geo.W - r.W) / 2) or geo.X
			for _, it in ipairs(r.Items) do
				local pill = U.PillList[it.P[1]]
				if not pill then
					pill = label(U.Pills, it.P[1], "Heading", 20, { ZIndex = 11, BackgroundTransparency = 0, TextTruncate = Enum.TextTruncate.None })
					Theme.Corner(pill, UDim.new(0.5, 0))
					Theme.Stroke(pill, C.Navy, 2, 0)
					U.PillList[it.P[1]] = pill
				end
				pill.Text = it.P[2]
				pill.TextSize = size
				pill.BackgroundColor3 = it.P[3]
				place(pill, x - geo.X, y - geo.Y, it.W, geo.H)
				used[it.P[1]] = true
				x = x + it.W + geo.Gap
			end
			y = y + geo.H + geo.Gap
		end
		place(U.Pills, geo.X, geo.Y, geo.W, math.max(geo.H, y - geo.Y - geo.Gap))
	end
	for name, pill in pairs(U.PillList) do
		pill.Visible = used[name] == true
	end
	return used
end

-- the note's lines, most important first: the reason, the copies taken off, the machine too far
function H.noteLines(plan)
	local lines = {}
	if plan.Reason and not plan.Empty and not plan.Locked then
		lines[#lines + 1] = { Text = plan.Reason, Short = plan.ReasonShort, Color = C.Bad }
	end
	for _, note in ipairs(plan.Notes or {}) do
		lines[#lines + 1] = note
	end
	if plan.Ok and not S.MachineNear then
		lines[#lines + 1] = { Text = "Walk up to your Fusion Machine to fuse", Short = "Walk up to your machine", Color = C.Warn }
	end
	return lines
end

function H.explain(plan)
	if plan.Tier == "Golden" then
		return { Text = H.copies() .. " copies become 1 Golden copy: x1.5 power and a gold shine.", Short = H.copies() .. " copies make 1 Golden: x1.5 power", Color = C.Muted }
	elseif plan.Tier == "Rainbow" then
		return { Text = H.copies() .. " Golden copies become 1 Rainbow copy: x2.5 power and a rainbow shimmer.", Short = H.copies() .. " Golden make 1 Rainbow: x2.5 power", Color = C.Muted }
	end
	return { Text = "Pick a pet with " .. H.copies() .. " copies to fuse it into its next finish.", Short = "Pick a pet with " .. H.copies() .. " copies", Color = C.Muted }
end

function H.paintLine(lbl, geo, line)
	if not (geo and line) then
		lbl.Text = ""
		return
	end
	lbl.TextColor3 = line.Color or C.Muted
	local texts = { line.Text }
	if line.Short and line.Short ~= line.Text then
		texts[2] = line.Short
	end
	H.fitLines(lbl, texts, geo[1], geo[2], geo[3], geo[4])
end

function H.paintNotes(plan)
	local mix = S.Tab == "Mix"
	local lines = H.noteLines(plan)
	local first = lines[1]
	if first and lines[2] and S.Mode ~= "Phone" then
		-- (PC: two notes share the line when they fit)
		first = { Text = first.Text .. "  " .. lines[2].Text, Short = first.Text, Color = first.Color }
	end
	if mix then
		U.Note.Visible = first ~= nil
		H.paintLine(U.Note, S.Geo.Note, first)
		local phoneLike = S.Mode == "Phone"
		-- PC: always; a landscape phone: the bottom line is the Outcome's once both pets are picked (the note has its own
		-- place in the right column); portrait: the Note takes the Info's line
		local info = true
		if phoneLike and not S.Portrait then
			info = plan.MovesText == nil
		elseif phoneLike then
			info = first == nil
		end
		U.Info.Visible = info
		H.paintLine(U.Info, S.Geo.Info, { Text = phoneLike and TEXTS.InfoPhone or TEXTS.InfoPC, Short = TEXTS.InfoPhone, Color = C.Muted })
	else
		U.Note.Visible = true
		H.paintLine(U.Note, S.Geo.Note, first or H.explain(plan))
	end
	if U.Tip.Visible then
		local tip
		if S.Mode ~= "Phone" then
			tip = mix and TEXTS.TipMix or string.format(TEXTS.TipUpgrade, H.copies())
		else
			tip = string.format(TEXTS.TipPhone, H.copies(), H.copies())
		end
		H.paintLine(U.Tip, S.Geo.Tip, { Text = tip, Color = C.Muted })
	end
end

function H.paintCost(plan)
	local cost = plan.Cost
	local currency = cost and cost.Currency or "Tokens"
	local info = (currency == "Gems") and GEM_INFO or TOKEN_INFO
	if U.IconCurrency ~= currency or U.IconPx ~= S.Geo.IconPx then
		U.IconCurrency, U.IconPx = currency, S.Geo.IconPx
		for _, c in ipairs(U.CostIcon:GetChildren()) do
			c:Destroy()
		end
		local ok, icon = pcall(NeonKit.Icon, U.CostIcon, currency, S.Geo.IconPx or 40)
		if ok and icon then
			icon.ZIndex = 6
		end
	end
	if cost then
		U.Cost.Text = H.commas(cost.Amount)
		U.Cost.TextColor3 = (plan.CanAfford == false) and C.Bad or (info.Color or C.Gold)
	else
		U.Cost.Text = "-"
		U.Cost.TextColor3 = C.Muted
	end
	local have = H.balance(currency)
	local word = (currency == "Gems") and "Gems" or "Cloud Tokens"
	local short = cost and have < cost.Amount
	U.Have.TextColor3 = short and C.Bad or C.Muted
	local geo = S.Geo.Have
	if geo and U.Have.Visible then
		H.fit(U.Have, { "You have " .. H.commas(have) .. " " .. word, "You have " .. H.short(have) }, geo[1], geo[3], geo[4])
	end
end

function H.canFuse(plan)
	return plan.Ok == true and S.MachineNear and not S.Pending and not S.Animating
end

function H.paintFuse(plan)
	local can = H.canFuse(plan)
	U.Fuse:SetAttribute("Disabled", not can)
	U.Fuse.Text = S.Pending and "Fusing..." or "FUSE!"
	U.Swap:SetAttribute("Disabled", not (S.MixA and S.MixB) or S.Pending ~= nil or S.Animating)
	local glow = U.Fuse:FindFirstChild("Glow")
	local gs = glow and glow:FindFirstChild("GlowStroke")
	if gs then
		if can and not S.Fx.Fuse then
			S.Fx.Fuse = TweenService:Create(gs, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.15 })
			S.Fx.Fuse:Play()
		elseif not can and S.Fx.Fuse then
			S.Fx.Fuse:Cancel()
			S.Fx.Fuse = nil
			gs.Transparency = NeonKit.Metrics.GlowTransparency
		end
	end
end

-- (Task 12) the first text (and size) that fits one line of `width`; else the texts word-wrapped inside `height`
function H.fitWrap(lbl, texts, width, height, maxSize, minSize)
	for _, t in ipairs(texts) do
		local size = maxSize
		while size >= minSize do
			if H.boxW(t, size, Theme.FontOf(lbl)) <= width then
				lbl.Text, lbl.TextSize, lbl.TextWrapped = t, size, false
				return t
			end
			size = size - 1
		end
	end
	return H.fitLines(lbl, texts, width, height, maxSize, minSize)
end

-- a move chip's look: lit = a gold border, a warm fill, white text and the check; off = lit but not tappable (equal elements)
function H.paintChip(g, c, texts, lit, off)
	local M = (g.Form == "pc") and K.PC or K.PHONE
	local b = c.Button
	b:SetAttribute("Lit", lit)
	b:SetAttribute("Disabled", off)
	b.Active = not off
	b.BackgroundColor3 = lit and Color3.fromRGB(86, 64, 20) or C.Well
	b.BackgroundTransparency = off and 0.3 or 0
	b.TextColor3 = lit and C.White or C.Muted
	PixelIcon.Tint(c.Icon, b.TextColor3)
	c.Stroke.Color = lit and C.Gold or C.WellEdge
	c.Stroke.Thickness = lit and 3 or 2
	c.Stroke.Transparency = off and 0.35 or 0
	c.Check.Visible = lit
	local w, h = (g.W or 0) - 2 * M.ChipPad - CHIP_ICON - 6, g.H or M.ChipH
	if g.Form == "pc" then
		-- PC: one line (the kind / element word drops before anything wraps)
		H.fitWrap(b, texts, w, h, M.ChipText, M.ChipMin)
		return
	end
	-- phone: the glyph stays; a long name wraps to a second line before the glyph is dropped
	for _, t in ipairs(texts) do
		if H.boxW(t, M.ChipText, Theme.FontOf(b)) <= w then
			b.Text, b.TextSize, b.TextWrapped = t, M.ChipText, false
			return
		end
		if H.rows(t, M.ChipText, Theme.FontOf(b), w) * M.ChipText * 1.2 <= h + 0.5 then
			b.Text, b.TextSize, b.TextWrapped = t, M.ChipText, true
			return
		end
	end
	H.fitLines(b, texts, w, h, M.ChipText, M.ChipMin)
end

-- the move chips and the outcome (Mix with two regular pets; hidden otherwise)
function H.paintMoves(plan)
	local mt = (S.Tab == "Mix") and plan.MovesText or nil
	local pc = S.Mode ~= "Phone"
	for _, side in ipairs({ "Body", "Style" }) do
		U.Chips[side].Root.Visible = mt ~= nil
	end
	U.OutcomeAttack.Visible = mt ~= nil and pc
	U.OutcomeSpecial.Visible = mt ~= nil and pc
	U.Outcome.Visible = mt ~= nil and not pc
	if not mt then
		return
	end
	local moves = plan.Moves or "BB"
	local same = plan.SameElement == true
	for _, side in ipairs({ "Body", "Style" }) do
		local letter = (side == "Body") and "B" or "S"
		local own = FusionController.MovesText(S.MixA, S.MixB, letter .. letter)
		local g = U.Chips[side]
		if own then
			local a, s = own.Attack, own.Special
			local attackTexts, specialTexts
			if g.Form == "pc" then
				attackTexts = { a.Name .. " " .. G.Dot .. " " .. a.Element, a.Name }
				specialTexts = { s.Name .. " " .. G.Dot .. " " .. H.kindWord(s.Kind), s.Name }
			else
				attackTexts = { a.Name }
				specialTexts = { s.Name }
			end
			H.paintChip(g, g.Attack, attackTexts, same or string.sub(moves, 1, 1) == letter, same)
			H.paintChip(g, g.Special, specialTexts, string.sub(moves, 2, 2) == letter, false)
		end
	end
	local a, s = mt.Attack, mt.Special
	local fullA = string.format(TEXTS.OutAttack, a.Element, a.Name)
	local shortA = string.format(TEXTS.OutAttackShort, a.Name)
	local fullS = string.format(TEXTS.OutSpecial, H.kindWord(s.Kind), s.Name)
	local shortS = string.format(TEXTS.OutSpecialShort, s.Name)
	local geo = S.Geo.Outcome
	if not geo then
		return
	end
	if pc then
		H.fit(U.OutcomeAttack, { fullA, shortA }, geo.W, geo.Max, geo.Min)
		H.fit(U.OutcomeSpecial, { fullS, shortS }, geo.W, geo.Max, geo.Min)
	else
		-- one line; when it is too wide the kind words drop first, then the short text wraps inside the line's height
		-- (never cut: the label does not truncate)
		local sep = " " .. G.Dot .. " "
		local short = shortA .. sep .. shortS
		local lbl = U.Outcome
		for _, t in ipairs({ fullA .. sep .. fullS, short }) do
			if H.boxW(t, geo.Max, Theme.FontOf(lbl)) <= geo.W then
				lbl.Text, lbl.TextSize, lbl.TextWrapped = t, geo.Max, false
				return
			end
		end
		H.fitLines(lbl, { short }, geo.W, geo.H, geo.Max, geo.Min)
	end
end

function H.paint(plan)
	local mix = S.Tab == "Mix"
	if mix then
		H.paintCard(U.Slots.Body, S.MixA, "BODY")
		H.paintCard(U.Slots.Style, S.MixB, "STYLE")
	else
		H.paintStack(plan)
	end
	-- (Task 12) a landscape phone's Mix: while a note shows, the pills keep to one row above it
	local col = S.Geo.MixCol
	if col and S.Geo.Pills then
		S.Geo.Pills.MaxH = (mix and H.noteLines(plan)[1] ~= nil) and col.PillsNote or col.PillsAll
	end
	H.paintMoves(plan)
	H.paintResult(plan)
	H.paintPills(plan)
	H.paintNotes(plan)
	H.paintCost(plan)
	H.paintFuse(plan)
	U.Locked.Visible = plan.Locked == true
	if plan.Locked then
		U.LockedText.Text = plan.Reason or ""
	end
end

-- the result's glow pulse and bob while the window is open (one tween each)
function H.startFx()
	H.stopFx()
	local gs = U.Result.Card.GlowStroke
	if gs then
		S.Fx.Glow = TweenService:Create(gs, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.2 })
		S.Fx.Glow:Play()
	end
	U.Result.Bob.Position = UDim2.fromOffset(0, -4)
	S.Fx.Bob = TweenService:Create(U.Result.Bob, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, 4) })
	S.Fx.Bob:Play()
	U.Shimmer.Rotation = 0
	S.Fx.Shimmer = TweenService:Create(U.Shimmer, TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	S.Fx.Shimmer:Play()
end

function H.stopFx()
	for key, tw in pairs(S.Fx) do
		pcall(function()
			tw:Cancel()
		end)
		S.Fx[key] = nil
	end
end

----------------------------------------------------------------------
-- The picker sheet (UI/PetPicker: Upgrade / Mix contexts)
----------------------------------------------------------------------
-- every owned key of `key`'s species (any finish) -> word
function H.speciesBlocked(key, word)
	local parsed = key and H.parse(key)
	if not parsed or not parsed.PetId then
		return nil
	end
	local ok, keys = pcall(State.Keys)
	local out = {}
	for _, k in ipairs((ok and type(keys) == "table") and keys or {}) do
		local p = H.parse(k)
		if p and p.PetId == parsed.PetId and not p.HybridId then
			out[k] = word
		end
	end
	return out
end

-- why the picker has nothing for this context ("Upgrade" | "Mix"): no pets at all, or only hybrids / Rainbow pets
function H.emptyText(ctx)
	local ok, keys = pcall(State.Keys)
	if not (ok and type(keys) == "table" and #keys > 0) then
		return TEXTS.EmptyNoPets
	end
	return ctx == "Upgrade" and TEXTS.EmptyUpgrade or TEXTS.EmptyMix
end

-- which = "Upgrade" | "Body" | "Style"; chain = after a pick, open the other Mix slot's sheet once when it is still empty
function H.openSheet(which, chain)
	if not S.Open or H.inMatch() or S.Pending or S.Animating or not H.unlocked() then
		return false
	end
	local ctx = (which == "Upgrade") and "Upgrade" or "Mix"
	local okEntries, entries = pcall(PetPicker.Entries, ctx)
	if not okEntries or type(entries) ~= "table" then
		return false
	end
	if #entries == 0 then
		-- nothing this tab can take: say why on the HintLine instead of doing nothing (review fix)
		H.hint(H.emptyText(ctx))
		return false
	end
	S.SheetToken = S.SheetToken + 1
	local mine = S.SheetToken
	local spec = { Context = ctx }
	if which == "Upgrade" then
		spec.Title, spec.Selected = "Pick a pet to upgrade", S.UpKey
	elseif which == "Body" then
		spec.Title, spec.Selected = "Pick the Body pet", S.MixA
		spec.Blocked = H.speciesBlocked(S.MixB, "In Style")
	else
		spec.Title, spec.Selected = "Pick the Style pet", S.MixB
		spec.Blocked = H.speciesBlocked(S.MixA, "In Body")
	end
	spec.OnPick = function(key)
		if S.Open then
			H.onPick(which, key, chain)
		end
	end
	spec.OnClose = function()
		if S.SheetToken == mine then
			S.Sheet = false
			H.syncBack()
		end
	end
	local ok = PetPicker.Open(spec)
	S.Sheet = ok == true
	H.syncBack()
	return S.Sheet
end

function H.closeSheet()
	if S.Sheet then
		S.Sheet = false
		S.SheetToken = S.SheetToken + 1
		safe("sheet close", PetPicker.Close)
	end
end

function H.onPick(which, key, chain)
	if which == "Upgrade" then
		S.UpKey = key
	elseif which == "Body" then
		S.MixA = key
	else
		S.MixB = key
	end
	safe("refresh", H.refresh)
	if chain and which ~= "Upgrade" then
		local other = (which == "Body") and "Style" or "Body"
		if (other == "Body" and not S.MixA) or (other == "Style" and not S.MixB) then
			H.openSheet(other, false)
		end
	end
end

-- a tap on the Stack (Upgrade) or a slot (Body / Style)
function H.tapSheet(which)
	if S.Pending or S.Animating then
		return
	end
	H.openSheet(which, which ~= "Upgrade")
end

-- no pet picked: the sheet opens by itself (Upgrade; Mix: the first empty slot, Body first)
function H.autoSheet()
	if not S.Open or S.Sheet or PetPicker.IsOpen() or S.Pending or S.Animating then
		return
	end
	if S.Tab == "Upgrade" then
		if not S.UpKey then
			H.openSheet("Upgrade", false)
		end
	elseif not S.MixA then
		H.openSheet("Body", true)
	elseif not S.MixB then
		H.openSheet("Style", true)
	end
end

----------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------
function H.hint(text, seconds)
	if not (U.Hint and S.Open) then
		return
	end
	S.HintToken = S.HintToken + 1
	local mine = S.HintToken
	U.Hint.Text = tostring(text)
	U.Hint.Visible = true
	task.delay(seconds or K.HINT_SECONDS, function()
		if S.HintToken == mine and U.Hint then
			U.Hint.Visible = false
		end
	end)
end

-- Escape that only ends typing (a focused TextBox: the sheet's search, the chat) goes back nowhere. Roblox lets go of the
-- box as it handles that Escape, so a box let go this very moment counts too. (Not InputBegan's gameProcessed: Roblox's
-- own menu binds Escape, so a plain Escape can arrive processed as well, and the window would stop closing on Esc.)
function H.typing()
	return UserInputService:GetFocusedTextBox() ~= nil or os.clock() - S.TypedAt < K.TYPED_GAP
end

function H.onFuseTap()
	if not S.Open or S.Pending or S.Animating then
		return
	end
	local plan = S.Plan or H.computePlan()
	if H.canFuse(plan) then
		FusionController.Fuse()
		return
	end
	local lines = H.noteLines(plan)
	if lines[1] then
		H.hint(lines[1].Text)
	elseif plan.Empty or plan.Reason then
		H.hint(plan.Reason or "Pick a pet first")
	end
end

function H.onSwap()
	if S.Pending or S.Animating or not S.Open then
		return
	end
	if not (S.MixA and S.MixB) then
		H.hint("Pick both pets first")
		return
	end
	S.MixA, S.MixB = S.MixB, S.MixA
	H.refresh()
end

-- (Task 12) a move chip tapped: that slot's pet gives that move (a lit chip, or an attack with one element, changes nothing)
function H.onChip(side, which)
	if not S.Open or S.Pending or S.Animating or S.Tab ~= "Mix" then
		return
	end
	local key = (side == "Body") and S.MixA or S.MixB
	if not key then
		return
	end
	if which == "Attack" then
		FusionController.SetMoves(key, nil)
	else
		FusionController.SetMoves(nil, key)
	end
end

function H.setTab(tab)
	if tab ~= "Upgrade" and tab ~= "Mix" then
		return
	end
	if S.Pending or S.Animating then
		return
	end
	local changed = S.Tab ~= tab
	S.Tab = tab
	if changed then
		H.closeSheet()
		H.layout()
	end
	H.autoSheet()
end

----------------------------------------------------------------------
-- Fusing + the fusion animation
----------------------------------------------------------------------
function H.burst(parent, color, amount, centre)
	local rng = Random.new()
	for i = 1, amount do
		local size = rng:NextInteger(9, 16)
		local pieceColor = color
		if i % 3 == 0 then
			pieceColor = C.Gold
		elseif i % 3 == 1 then
			pieceColor = Theme.Lighten(color, 0.5)
		end
		local piece = Util.Create("Frame", {
			Name = "Confetti", AnchorPoint = Vector2.new(0.5, 0.5), Position = centre, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 0,
			BackgroundColor3 = pieceColor, BorderSizePixel = 0, Rotation = rng:NextInteger(0, 90), ZIndex = 24, Parent = parent,
		})
		Theme.Corner(piece, UDim.new(0, 2))
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(70, 190)
		local target = UDim2.new(centre.X.Scale, centre.X.Offset + math.cos(angle) * distance, centre.Y.Scale, centre.Y.Offset + math.sin(angle) * distance * 0.7 - 20)
		local seconds = rng:NextNumber(0.6, 1.1)
		Util.Tween(piece, seconds, { Position = target, Rotation = piece.Rotation + rng:NextInteger(-200, 200) })
		Util.Tween(piece, seconds, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, seconds + 0.1)
	end
end

-- glowing cubes bursting out of the machine's output pod (client-only parts)
function H.machineBurst(color)
	local at = H.outputPoint(S.AtMachine or H.myMachine())
	if not at then
		return
	end
	local folder = workspace:FindFirstChild("ClientFx") or workspace
	local rng = Random.new()
	local function part(name, size, partColor)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = partColor
		p.Size = size
		p.CFrame = CFrame.new(at)
		p.Parent = folder
		return p
	end
	for i = 1, 10 do
		local p = part("FusionSpark", Vector3.new(0.4, 0.4, 0.4), (i % 3 == 0) and C.Gold or ((i % 3 == 1) and color or Theme.Lighten(color, 0.5)))
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.6, 1.6), rng:NextNumber(-1, 1)).Unit
		Util.Tween(p, 0.8, { CFrame = CFrame.new(at + dir * rng:NextNumber(3, 6)) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1) })
		Debris:AddItem(p, 0.9)
	end
	local flash = part("FusionFlash", Vector3.new(1, 1, 1), Theme.Lighten(color, 0.4))
	flash.Shape = Enum.PartType.Ball
	flash.Transparency = 0.2
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = flash
	Util.Tween(flash, 0.5, { Size = Vector3.new(5, 5, 5), Transparency = 1 })
	Util.Tween(light, 0.5, { Brightness = 0 })
	Debris:AddItem(flash, 0.6)
end

-- the flyers of the current tab (the stack's copies or the two slots), in body px
function H.flyers()
	local out = {}
	if S.Tab == "Mix" then
		for _, item in ipairs({ U.Slots.Body, U.Slots.Style }) do
			out[#out + 1] = { Item = item, Off = Vector2.new(0, 0) }
		end
	else
		local o = U.Stack.Position
		for i, item in ipairs(U.Copies) do
			if not item.Dim.Visible or i == 3 then
				out[#out + 1] = { Item = item, Off = Vector2.new(o.X.Offset, o.Y.Offset) }
			end
		end
	end
	return out
end

function H.playFusion(resultKey, rarity)
	S.Animating = true
	local mine = S.Token
	local color = rarity and H.rarityColor(rarity) or C.Violet
	local rp, rs = U.Result.Root.Position, U.Result.Root.Size
	local centre = Vector2.new(rp.X.Offset + rs.X.Offset / 2, rp.Y.Offset + rs.Y.Offset / 2)
	-- the move chips go with their pets (the next paint brings them back for the next pair)
	for _, g in pairs(U.Chips) do
		g.Root.Visible = false
	end
	-- 1) the inputs fly into the result, spinning and shrinking
	for _, f in ipairs(H.flyers()) do
		local root = f.Item.Root
		local size = root.Size
		local target = centre - f.Off - Vector2.new(size.X.Offset / 2, size.Y.Offset / 2)
		Util.Tween(root, 0.45, { Position = UDim2.fromOffset(target.X, target.Y), Rotation = root.Rotation + 180 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Util.Tween(f.Item.Pop, 0.45, { Scale = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	Util.Tween(U.Result.Pop, 0.45, { Scale = 0.7 })
	task.delay(0.45, function()
		if S.Token ~= mine then
			return
		end
		-- 2) a flash and a burst
		local at = UDim2.fromOffset(centre.X, centre.Y)
		U.Flash.Position = at
		U.Flash.Size = UDim2.fromOffset(40, 40)
		U.Flash.BackgroundTransparency = 0.1
		U.Flash.BackgroundColor3 = Theme.Lighten(color, 0.6)
		U.Flash.Visible = true
		Util.Tween(U.Flash, 0.35, { Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1 })
		H.burst(U.Body, color, 26, at)
		safe("machine fx", H.machineBurst, color)
		for _, f in ipairs(H.flyers()) do
			f.Item.Root.Visible = false
		end
		-- 3) the new pet pops in
		local def = H.def(resultKey)
		if def then
			H.setView(U.Result.View, def, resultKey, H.stage(resultKey), "High")
			H.cardName(U.Result, H.nameOf(def, resultKey), C.White)
			U.Result.Placeholder.Visible = false
		end
		U.Result.Pop.Scale = 0.4
		Util.Tween(U.Result.Pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		U.Result.Card.SetColor(color)
		U.NewTag.Visible = true
		U.NewTag.Rotation = -8
		local tagW, tagH = 92, 38
		place(U.NewTag, rp.X.Offset + rs.X.Offset - tagW + 10, rp.Y.Offset - 10, tagW, tagH)
		task.delay(1.6, function()
			if S.Token ~= mine then
				return
			end
			-- 4) back to picking
			H.resetAnimation()
			H.layout()
		end)
	end)
end

function H.resetAnimation()
	S.Animating = false
	if not S.Built then
		return
	end
	for _, item in ipairs(U.Copies) do
		item.Pop.Scale = 1
		item.Root.Visible = true
	end
	for _, item in pairs(U.Slots) do
		item.Pop.Scale = 1
		item.Root.Visible = true
	end
	U.Result.Pop.Scale = 1
	U.Flash.Visible = false
	U.NewTag.Visible = false
end

function H.remote()
	if S.Remote then
		return S.Remote
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("Fusion")
	if remote and remote:IsA("RemoteEvent") then
		S.Remote = remote
	end
	return S.Remote
end

function H.onResult(payload)
	if type(payload) ~= "table" then
		return
	end
	local pending = S.Pending
	S.Pending = nil
	if payload.Ok == true and type(payload.Key) == "string" then
		local key = payload.Key
		if not S.Built or not S.Open then
			return
		end
		-- the inputs are gone: start the next pick from the new pet when it can go on
		local parsed = H.parse(key)
		if S.Tab == "Upgrade" then
			S.UpKey = (parsed and NEXT_TIER[parsed.Tier]) and key or nil
		else
			S.MixA, S.MixB = nil, nil
		end
		local function play()
			if S.Open and S.Built then
				H.playFusion(key, payload.Rarity)
			end
		end
		if H.def(key) then
			play()
		else
			-- the profile snapshot with the new pet may land a moment after the answer
			local conn
			local done = false
			conn = State.Changed:Connect(function()
				if not done and H.def(key) then
					done = true
					conn:Disconnect()
					play()
				end
			end)
			task.delay(2, function()
				if not done then
					done = true
					conn:Disconnect()
					play()
				end
			end)
		end
	elseif pending and S.Built then
		if not payload.Quiet then
			H.hint(type(payload.Reason) == "string" and payload.Reason or "That fusion did not work", K.SERVER_HINT_SECONDS)
		end
		H.refresh()
	end
end

----------------------------------------------------------------------
-- One window at a time, the touch controls, the menu column, Esc / B
----------------------------------------------------------------------
function H.closeOthers()
	for _, name in ipairs({ "MenuController", "IndexController", "DailyController" }) do
		local mod = H.controller(name)
		if mod and type(mod.Close) == "function" then
			safe("close " .. name, mod.Close)
		end
	end
	if PetPicker.IsOpen() and not S.Sheet then
		safe("close sheet", PetPicker.Close) -- another window's sheet
	end
end

function H.syncTouch()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local want = S.Open and (S.Mode == "Phone" or touchOnly)
	if want == S.TouchOff then
		return
	end
	S.TouchOff = want
	local menu = H.controller("MenuController")
	if menu and type(menu.SetTouchHidden) == "function" then
		safe("touch", menu.SetTouchHidden, "Fusion", want)
	end
end

function H.coverColumn()
	local menu = H.controller("MenuController")
	if menu and type(menu.SetColumnCovered) == "function" then
		safe("cover", menu.SetColumnCovered, (S.Open and S.Rect) and S.Rect.x or nil, "Fusion")
	end
	H.syncTouch()
end

-- Esc / B: our sheet first, then the window
function H.back()
	if S.Sheet and PetPicker.IsOpen() then
		H.closeSheet()
	elseif S.Open then
		FusionController.Close()
	end
end

function H.syncBack()
	local want = S.Open
	if want and not S.BackBound then
		S.BackBound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					safe("back", H.back)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.ButtonB)
		end)
	elseif not want and S.BackBound then
		S.BackBound = false
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function FusionController.IsOpen()
	return S.Open
end

function FusionController.Plan()
	return S.Plan
end

function FusionController.Layout()
	local mode, portrait
	if S.Open and S.Rect then
		mode, portrait = S.Mode, S.Portrait
	else
		local r = NeonKit.BigRect(K)
		mode, portrait = r.mode, r.mode == "Phone" and r.portrait == true
	end
	if portrait then
		return "Portrait"
	end
	return mode
end

function FusionController.Select(keyA, keyB)
	if S.Tab == "Upgrade" then
		S.UpKey = keyA
	else
		S.MixA, S.MixB = keyA, keyB
	end
	if S.Built and S.Open then
		safe("refresh", H.refresh)
	end
end

-- (Task 12) the move choice
function FusionController.Moves()
	return H.syncMoves()
end

function FusionController.SetMoves(attackKey, specialKey)
	local moves = H.syncMoves()
	local a, b = S.MixA, S.MixB
	local function letter(key)
		if type(key) ~= "string" then
			return nil
		elseif key == a then
			return "B"
		elseif key == b then
			return "S"
		end
		return nil
	end
	local l1, l2 = letter(attackKey), letter(specialKey)
	if l1 and H.sameElement() then
		l1 = nil -- one element: the attack is no choice
	end
	local new = (l1 or string.sub(moves, 1, 1)) .. (l2 or string.sub(moves, 2, 2))
	if new ~= S.Moves and MOVES[new] then
		S.Moves = new
		if S.Built and S.Open and not S.Animating then
			safe("refresh", H.refresh)
		end
	end
end

function FusionController.MovesText(bodyKey, styleKey, moves)
	local body, style = H.mixDefs(bodyKey, styleKey)
	if not body then
		return nil
	end
	if not MOVES[moves] then
		moves = "BB"
	end
	local attackDef = (string.sub(moves, 1, 1) == "S") and style or body
	local specialDef = (string.sub(moves, 2, 2) == "S") and style or body
	local element = tostring(attackDef.Element or "")
	local attacks = BattleCatalog and BattleCatalog.ElementAttacks
	local attack = type(attacks) == "table" and attacks[element] or nil
	local special = type(specialDef.Special) == "table" and specialDef.Special or {}
	return {
		Attack = { Element = element, Name = (type(attack) == "table" and type(attack.Name) == "string") and attack.Name or element },
		Special = { Kind = special.Kind, Name = tostring(special.Name or "Special") },
	}
end

function FusionController.Fuse()
	if not S.Open or S.Pending or S.Animating then
		return false
	end
	local plan = H.computePlan()
	S.Plan = plan
	local machine = S.AtMachine or H.myMachine()
	S.MachineNear = machine == nil or H.distanceTo(machine) <= K.NEAR_RANGE
	if not plan.Ok or not S.MachineNear then
		H.refresh()
		return false
	end
	local remote = H.remote()
	if not remote then
		warnOnce("remote", "the Fusion remote is missing")
		return false
	end
	S.FuseToken = S.FuseToken + 1
	local token = S.FuseToken
	S.Pending = { Action = plan.Action, Token = token, At = os.clock(), Inputs = plan.Inputs }
	if plan.Action == "Upgrade" then
		remote:FireServer("Upgrade", S.UpKey)
	else
		remote:FireServer("Mix", S.MixA, S.MixB, FusionController.Moves())
	end
	-- the inputs glow while the machine works
	for _, f in ipairs(H.flyers()) do
		f.Item.Card.SetColor(C.Gold)
	end
	H.paintFuse(plan)
	task.delay(K.FUSE_TIMEOUT, function()
		if S.Pending and S.Pending.Token == token then
			S.Pending = nil
			if S.Open then
				H.refresh()
			end
		end
	end)
	return true
end

function FusionController.Open(tab, args)
	if not initialized then
		FusionController.Init()
	end
	if H.inMatch() or not H.ensureGui() then
		return
	end
	H.build()
	args = type(args) == "table" and args or {}
	if (tab == "Upgrade" or tab == "Mix") and tab ~= S.Tab then
		H.closeSheet()
		S.Tab = tab
	end
	if type(args.Key) == "string" then
		if S.Tab == "Upgrade" then
			S.UpKey = args.Key
		else
			S.MixA = args.Key
			S.MixB = type(args.KeyB) == "string" and args.KeyB or S.MixB
		end
	end
	if typeof(args.Machine) == "Instance" then
		S.AtMachine = args.Machine
	elseif not S.Open then
		S.AtMachine = nil
	end
	local wasOpen = S.Open
	if not wasOpen then
		H.closeOthers()
	end
	S.Open = true
	if not wasOpen then
		S.Token = S.Token + 1
	end
	U.Holder.Visible = true
	H.layout()
	H.syncBack()
	if not wasOpen then
		U.Pop.Scale = K.OPEN_FROM
		Util.Tween(U.Pop, K.OPEN_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		H.startFx()
		FusionController.Opened:Fire(S.Tab)
	end
	-- no pet picked: the sheet opens by itself (after Opened: the windows that close on it are gone)
	if S.Open then
		H.autoSheet()
	end
end

function FusionController.Close()
	H.closeSheet()
	if not S.Open then
		return
	end
	S.Open = false
	S.Token = S.Token + 1
	local mine = S.Token
	S.AtMachine = nil
	S.HintToken = S.HintToken + 1
	if U.Hint then
		U.Hint.Visible = false
	end
	H.resetAnimation()
	H.stopFx()
	H.syncBack()
	H.coverColumn()
	if U.Pop then
		Util.Tween(U.Pop, 0.12, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(0.13, function()
		if S.Token == mine and not S.Open and U.Holder then
			U.Holder.Visible = false
		end
	end)
	FusionController.Closed:Fire()
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function H.onPrompt(prompt)
	if typeof(prompt) ~= "Instance" or prompt.Name ~= "FusionPrompt" then
		return
	end
	local owner = prompt:GetAttribute("OwnerUserId")
	if owner ~= nil and LocalPlayer and owner ~= LocalPlayer.UserId then
		return -- someone else's machine (its prompt is disabled locally anyway)
	end
	FusionController.Open(nil, { Machine = prompt:FindFirstAncestor("Station_FusionMachine") })
end

function H.connectOthers()
	local function hook(name, signalName)
		local mod = H.controller(name)
		local signal = mod and mod[signalName]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function()
				FusionController.Close()
			end)
		end
	end
	hook("MenuController", "WindowOpened")
	hook("IndexController", "Opened")
end

-- 4 times a second while open: the walk-away close and the near check
function H.beat()
	if not S.Open then
		return
	end
	local now = os.clock()
	if now < (S.CheckAt or 0) then
		return
	end
	S.CheckAt = now + 0.25
	if S.AtMachine and H.distanceTo(S.AtMachine) > K.MACHINE_RANGE then
		FusionController.Close()
		return
	end
	if S.Pending == nil and not S.Animating then
		local machine = S.AtMachine or H.myMachine()
		local near = machine == nil or H.distanceTo(machine) <= K.NEAR_RANGE
		if near ~= S.MachineNear then
			safe("near", H.refresh)
		end
	end
end

function FusionController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	H.ensureGui()
	State.Changed:Connect(function()
		if S.Open and not S.Animating then
			H.refreshSoon()
		end
	end)
	for _, signalName in ipairs({ "TokensChanged", "GemsChanged" }) do
		local signal = State[signalName]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function()
				if S.Open and not S.Animating then
					H.refreshSoon()
				end
			end)
		end
	end
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if H.inMatch() then
				FusionController.Close()
			end
		end)
	end
	UserInputService.TextBoxFocusReleased:Connect(function()
		S.TypedAt = os.clock()
	end)
	UserInputService.InputBegan:Connect(function(input)
		if S.Open and input.KeyCode == Enum.KeyCode.Escape and not H.typing() then
			safe("back", H.back)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		safe("prompt", H.onPrompt, prompt)
	end)
	task.spawn(function()
		local okOpen, openRemote = pcall(Remotes.Get, "OpenPanel")
		if okOpen and openRemote then
			openRemote.OnClientEvent:Connect(function(panelId, args)
				if type(panelId) == "string" and panelId:lower() == "fusion" then
					local tab = type(args) == "table" and args.Tab or nil
					safe("OpenPanel", FusionController.Open, tab, args)
				end
			end)
		end
		local okFusion, remote = pcall(Remotes.Get, "Fusion")
		if okFusion and remote then
			S.Remote = remote
			remote.OnClientEvent:Connect(function(kind, payload)
				if kind == "Result" then
					safe("result", H.onResult, payload)
				end
			end)
		end
	end)
	task.defer(function()
		safe("hooks", H.connectOthers)
	end)
	RunService.Heartbeat:Connect(function()
		if S.Open then
			H.beat()
		end
	end)
end

return FusionController
