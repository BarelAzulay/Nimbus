-- NpcController (client): brings the lobby NPC pets to life and shows their dialog (ARCHITECTURE_V3.md section 5).
--
--   NpcController.Init()
--   NpcController.Open(npcId)    opens the dialog of that NPC (what its ProximityPrompt does)
--   NpcController.Close()
--   NpcController.IsOpen() -> bool, npcId | nil
--
-- Idle (client only, the server never moves an NPC): every model tagged NpcDialog.Tag ("NC_Npc") gets a gentle
-- bob, a slow sway, a slow turn toward the nearest player (and toward you while you talk), low-frequency wing
-- flaps through PetBuilder.Animate and a little hop on every new line. To keep this cheap, the pet's static parts
-- are welded (locally) to its anchored PrimaryPart once it has fully replicated, so a pose is ONE CFrame write
-- plus the animated groups (wings, tail...); NPCs further than 140 studs from the camera are frozen, those past
-- 70 studs update every other frame. One RenderStepped connection drives everything.
--
-- Dialog (ScreenGui "NimbusNpcDialog", display order 13): a side card at the BOTTOM-LEFT, above the HUD's
-- bottom block (NimbusHud attribute BottomLeftTop: the bottom-centre vitals card) only when its x-span meets that
-- card (BottomCentreLeft / BottomCentreRight) or the hotbar under it, else near the bottom edge (desktops; touch
-- keeps the HUD's line above the thumbstick), and right of the menu column when they would overlap, never centred. It shows the NPC's name tab, a portrait viewport of the pet, its title, the line in a dark text
-- well with a typewriter reveal (numbers and key phrases highlighted), page dots, and Next / Close buttons.
-- kit B U9-9 (finding 15; it was v3's rounded cloud card with puffs and gradients): the card is a Signboard block, a 6 px
-- wood frame round the stone body with its stone lip, square, no shadow, glow or gradient. The name rides on a navy plank
-- (its gold-lip edge, its navy lip, two brass rivets) in gold, a plain Section title (a dialog's title, not a window's
-- ribbon); the portrait a sky well in a wood edge with the NPC's accent colour on its lip and a little pixel cloud; the title
-- under it a stone tag; the line brown on a pale well in a wood edge, a stepped pixel tail pointing at the portrait, its
-- highlights the accent / the numbers' gold moved until they read 4.5:1 there; the page dots square blocks (the line shown
-- gold, the rest the sunk well); Next the green plank (the dialog's one action), Close a stone plank. Pixel icons and wood
-- edges land on whole screen pixels at any card scale (client/UI/PixelCrisp).
-- Lines cycle (Next on the last line starts over). Triggering the prompt again (E) also advances; clicking the
-- text finishes the current line. The card closes when you walk away, die or enter a match.
-- Sounds (audio wave 2, client/SoundFx; a missing id is silent): "DialogOpen" when the card opens (not when switching
-- from another NPC mid-dialog), "DialogBlip" every 3rd letter the typewriter shows (never a space / punctuation;
-- Config MinGap), "DialogNext" when Next shows the next line (finishing a line early is silent). The NPC voices
-- (wordless, Config.Audio.Keys.Sfx Npc<Name><Kind>, <Name> = the NpcDialog Id in CamelCase: sparky_fox -> SparkyFox):
--   Greet    Config.Audio.Voice.GreetDelay (0.12 s) after the DialogOpen click, when this NPC's card opens (not when
--            switching mid-dialog), if the card is still open on it
--   Every Next that shows a new line (not a Next that only finishes the typewriter) gets one wordless reaction:
--   Pleased  the new line is the dialog's LAST line, or its text holds a "!"
--   Hmm      any other line (also line 1 again after "Again" on the last line, unless it holds a "!")
-- At most one voice per Voice.Gap (1.5 s) per NPC (a voice inside the gap is dropped), a new voice stops the NPC's
-- previous one, volume / pitch from Config.Audio.Volume / Pitch (0.6, 0.98-1.02). An NPC without voice keys is silent.
-- Designed in 1080p pixels under a UIScale of Theme.ScreenFactor() (body 20, captions 16, buttons 20, name 28),
-- shrunk to fit short screens but never below 14 px text. Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local function optionalShared(name)
	local module = Shared:FindFirstChild(name) or Shared:WaitForChild(name, 5)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	warn("[NpcController] failed to load " .. name .. ": " .. tostring(result))
	return nil
end

local NpcDialog = optionalShared("NpcDialog")
local PetBuilder = optionalShared("PetBuilder")
local PetCatalog = optionalShared("PetCatalog")

local Client = script.Parent.Parent
local CloudUI = nil
do
	local ok, result = pcall(function()
		return require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
	end)
	if ok and type(result) == "table" then
		CloudUI = result
	end
end
local PixelCrisp = nil -- (kit B U9-9) whole-pixel icons and edges under the card's scale
do
	local ok, result = pcall(function()
		return require(Client:WaitForChild("UI"):WaitForChild("PixelCrisp"))
	end)
	if ok and type(result) == "table" then
		PixelCrisp = result
	end
end

local LocalPlayer = Players.LocalPlayer

local NpcController = {}

----------------------------------------------------------------------
-- Tunables (studs / seconds; UI sizes are design pixels of a 1080p screen)
----------------------------------------------------------------------
local K = {
	CULL = 140, -- NPCs further than this from the camera are frozen
	NEAR = 70, -- beyond this they update every other frame
	LOOK_RANGE = 26, -- they turn toward the nearest player within this distance
	MAX_TURN = math.rad(115),
	TURN_RATE = 2.2,
	TURN_SPEED = math.rad(80), -- max degrees per second: a slow, deliberate turn
	BOB_AMP = 0.22,
	BOB_PERIOD = 3.4,
	ROLL = math.rad(2.2),
	NOD = math.rad(2.6),
	HOP_TIME = 0.42,
	HOP_H = 0.55,
	FLAP = 0.4, -- PetBuilder.Animate flap speed multiplier while idle (about 0.8 beats a second)
	FLAP_TALK = 0.8,
	EXCITE_TALK = 0.35,
	TARGET_REFRESH = 0.25,
	CHECK_EVERY = 0.2,
	LAYOUT_EVERY = 0.5,
	CPS = 50, -- typewriter characters per second
	PAUSE_END = 0.22,
	PAUSE_MID = 0.09,
	READY_TIMEOUT = 12,
	-- dialog card
	W = 540, -- full card
	-- (kit B U9-9) taller than the bubble's 216: the footer clears the stone lip and the line keeps its room. (U9-9 look 2)
	-- the card's lengths are multiples of 10 design px where they can be (whole px at 0.7, 0.8 and 1.0; PixelCrisp snaps
	-- the rest), and the line keeps its room over the page dots under the wider stone between the well and the footer
	H = 230,
	W_MIN = 420, -- compact card for narrow screens (taller, so long lines still fit)
	H_COMPACT = 270,
	TAB_ABOVE = 24, -- the name tab rides this far above the card
	PAD = 14,
	PORTRAIT = 130,
	WELL_X = 160,
	WELL_TOP = 30,
	FOOTER_H = 40,
	NEXT_W = 120,
	CLOSE_W = 110,
	BUTTON_GAP = 14, -- (U9-9 look 2) between Close and Next, the well and the footer, the title tag and Close: one rhythm
	TAB_INSET = 22, -- (U9-9 look 2) the name's room starts this far in from each end of its plank (12 px clear of a rivet)
	NAME_ROW = 20, -- (U9-9 look 2) a name too long for one row at the 20 px floor grows its plank by one row
	TEXT = 20,
	NAME = 28,
	CAPTION = 20, -- the title under the portrait (wraps to two rows when needed)
	BUTTON = 20,
	MIN_SCALE = 0.7, -- every text of the card is >= 20 design px, so 20 * 0.7 = 14 px: the readability floor
	EDGE = 12,
	TOUCH_EDGE = 20,
	GAP = 10,
	MAX_DOTS = 6,
	DISPLAY_ORDER = 13,
	MAX_WIDTH_FRACTION = 0.62, -- on wide screens the card never reaches into the middle of the screen
	SMALL_WIDTH_FRACTION = 0.8, -- small screens have no middle to spare
	SMALL_SCREEN = 1100,
}

local TAU = math.pi * 2
local TAG = (NpcDialog and NpcDialog.Tag) or "NC_Npc"
local SETTINGS = (NpcDialog and NpcDialog.Settings) or {}
local CLOSE_DISTANCE = tonumber(SETTINGS.CloseDistance) or 16
local TOKEN_WORD = (Theme.Currency and Theme.Currency.Tokens and Theme.Currency.Tokens.Word) or "Tokens" -- (kit-b U7a) "50 Tokens"

-- (kit B U9-9) the Signboard palette (Theme.Sign)
local SIGN = Theme.Sign
local C = {
	White = Theme.Colors.White,
	Gold = SIGN.Gold,
	Text = SIGN.Text,
	Well = SIGN.Tile, -- the line's pale well
	DotOff = SIGN.Well,
}
K.FRAME = 6 -- the card's wood frame
K.EDGE_PX = 2 -- a block's wood edge (the well, the title tag, the dots)
K.PORTRAIT_EDGE = 3 -- the portrait's wood edge
K.PORTRAIT_LIP = 6 -- its lip in the NPC's accent colour
K.TAG_LIP = 3
K.NAME_LIP = 5 -- the name plank's navy lip
-- (kit B U9-9) the card's rows (design px): Well = the well's room under it (the footer, its gaps and the stone lip),
-- FootUp = the footer's offset from the card's bottom (its height and the room under it), Lip = the stone lip, Tab = the
-- name plank's height and TabAbove how far it rides over the card (its edge included; it ends 24 px into the card).
-- (U9-9 review) Short: a phone too short for the card even at MIN_SCALE (360 px tall: the top bar's pill drew over the
-- name plank) takes the 12 px back from the footer's gaps and the lip (Cut: the old bubble's 216 / 250 again, the line
-- keeps its room) and a plank 8 px lower, so the plank clears the pill. (U9-9 look 2) Well - FootUp is the stone between
-- the well and the footer: BUTTON_GAP on the tall card (the one rhythm: 14 between the buttons, 14 over them), 12 on the
-- short one (the 94 px line room allows no more), so their whole-px wood edges never meet (4 px of stone or more at 0.7;
-- 10 drew 3 px)
K.ROWS = {
	Tall = { Cut = 0, Well = 36, FootUp = 22, Lip = 8, Tab = 46, TabAbove = K.TAB_ABOVE, TitleTag = 50 },
	Short = { Cut = 12, Well = 26, FootUp = 14, Lip = 4, Tab = 38, TabAbove = K.TAB_ABOVE - 8, TitleTag = 46 },
}
K.DOT = 10
K.DOT_GAP = 8
-- (U9-9 look) a portrait phone's compact card is this much taller (there is free sky above it): its six-line speech kept 6
-- px over the page dots at the 0.7 floor
K.PORTRAIT_EXTRA = 30
K.PILL_GAP = 4 -- the name plank stays this far under the top bar's pill (NimbusTopBar, display order 21: it draws over us)
K.ICON = 18 -- the pixel icons (the cloud, the "more" chevron): 18 screen px everywhere (PixelCrisp), their slot 18 / k

-- `color` moved towards the brown ink until it reads `need`:1 on the line's pale well (a highlight keeps its hue)
local function inkOnWell(color, need)
	need = need or 4.5
	local out = color
	for step = 1, 20 do
		if Theme.Contrast(out, C.Well) >= need then
			return out
		end
		out = color:Lerp(SIGN.Text, step * 0.05)
	end
	return SIGN.Text
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local recs = {} -- array of NPC records
local byModel = {} -- [model] = record
local pending = {} -- [model] = true while waiting for it to replicate
local talkedTo = {} -- [npcId] = true once the local player has talked to it (hides the "!" badge)
local promptServiceHooked = false
local lastTrigger = {} -- [prompt] = clock of the last accepted trigger (guards double events)

local clock = 0
local loopConn = nil
local targetTimer = 0
local checkTimer = 0
local layoutTimer = 0
local initialized = false

-- (audio wave 2) the sounds
local BLIP_EVERY = 3 -- a DialogBlip on every 3rd visible letter
local VOICE = (type(Config.Audio) == "table" and type(Config.Audio.Voice) == "table") and Config.Audio.Voice or {}
local VOICE_GAP = tonumber(VOICE.Gap) or 1.5
local GREET_DELAY = tonumber(VOICE.GreetDelay) or 0.12
local voices = {} -- [npcId] = { At = os.clock() of its last voice, Sound = the Sound it played }
local soundFxMod = nil
local function soundFx()
	if soundFxMod == nil then
		local module = Client:FindFirstChild("SoundFx")
		local ok, mod = false, nil
		if module then
			ok, mod = pcall(require, module)
		end
		soundFxMod = (ok and type(mod) == "table" and type(mod.Play) == "function") and mod or false
	end
	return soundFxMod or nil
end
local function playSfx(name)
	local SF = soundFx()
	if not SF then
		return nil
	end
	local ok, s = pcall(SF.Play, name)
	return ok and s or nil
end

-- "sparky_fox" -> "SparkyFox"
local function camelId(id)
	local out = string.gsub(tostring(id or ""), "(%w)(%w*)", function(a, b)
		return string.upper(a) .. b
	end)
	return (string.gsub(out, "[^%w]", ""))
end

-- the NPC's voice of `kind` ("Greet" | "Hmm" | "Pleased"); -> the Sound or nil (no key / id, inside the gap)
local function playVoice(rec, kind)
	if not rec or type(rec.Id) ~= "string" then
		return nil
	end
	local SF = soundFx()
	if not SF then
		return nil
	end
	local name = "Npc" .. camelId(rec.Id) .. kind
	if type(SF.Id) == "function" and SF.Id("Sfx", name) == nil then
		return nil -- (no voice for this NPC: silent, the gap untouched)
	end
	local now = os.clock()
	local v = voices[rec.Id]
	if v and v.At and now - v.At < VOICE_GAP and now >= v.At then
		return nil
	end
	if v and v.Sound then
		pcall(function()
			v.Sound:Stop() -- (never two voices of one NPC at once)
		end)
	end
	local ok, s = pcall(SF.Play, name)
	if not ok or typeof(s) ~= "Instance" then
		return nil
	end
	voices[rec.Id] = { At = now, Sound = s }
	return s
end

local UI = {}
local dialog = {
	Open = false,
	Rec = nil,
	Lines = nil,
	Index = 1,
	Chars = {},
	Total = 0,
	Shown = 0,
	Timer = 0,
	Typing = false,
	Viewport = nil,
	SlideTween = nil,
	PendingOpen = nil, -- an NPC model whose prompt was used before it finished replicating
	Width = nil,
	VitalsOff = false, -- (U9-9 look) the HUD's vitals card is stepped aside under the card (HudController.SetVitalsHidden)
}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- (kit B U9-9) a block's wood edge: a mitred border stroke named SignEdge, kept on whole screen pixels
local function edge(parent, color, px)
	local s = make("UIStroke", {
		Name = "SignEdge",
		Color = color or SIGN.Wood,
		Thickness = px,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, parent)
	if PixelCrisp then
		PixelCrisp.Edge(s, px)
	end
	return s
end

-- a flat lip along the bottom of `parent` (px tall), (U9-9 look) whole screen px at any card scale
local function lipOf(parent, color, px)
	local lip = make("Frame", {
		Name = "Lip",
		BorderSizePixel = 0,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, px),
		ZIndex = parent.ZIndex,
	}, parent)
	if PixelCrisp then
		PixelCrisp.Lip(lip, px)
	end
	return lip
end

-- (U9-9 look) a block's top-left on a whole screen px of the card (PixelCrisp.Box)
local function crispBox(obj)
	if PixelCrisp and obj then
		PixelCrisp.Box(obj)
	end
	return obj
end

local function box(name, props, parent)
	local f = make("Frame", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0 }, nil)
	for k, v in pairs(props) do
		f[k] = v
	end
	if parent then
		f.Parent = parent
	end
	return f
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function hex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function playerGui()
	return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function localRoot()
	local char = LocalPlayer and LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function topInset()
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(inset) == "Vector2" then
		return inset.Y
	end
	return 0
end

-- y offset that converts another gui's AbsolutePosition into our gui-area coordinates
local function insetShift(gui)
	if gui and gui:IsA("ScreenGui") and gui.IgnoreGuiInset then
		return -topInset()
	end
	return 0
end

local function shownIn(inst, root)
	local node = inst
	while node and node ~= root do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

local function rectOf(inst, dy)
	local p, s = inst.AbsolutePosition, inst.AbsoluteSize
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
end

----------------------------------------------------------------------
-- Rich text: numbers and key phrases of a line are highlighted
----------------------------------------------------------------------
local function escapeRich(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function isWordChar(ch)
	return ch ~= nil and ch ~= "" and string.find(ch, "^[%w]") ~= nil
end

-- returns richText, plainText
local function richLine(text, def, accent)
	text = tostring(text or "")
	local spans = {}
	local function free(s, e)
		for i = 1, #spans do
			local sp = spans[i]
			if s <= sp[2] and e >= sp[1] then
				return false
			end
		end
		return true
	end
	-- (kit B U9-9) on the pale well: the accent and the numbers' gold moved until they read (4.5:1)
	local keyColor = hex(inkOnWell(accent))
	local numColor = hex(inkOnWell(SIGN.GoldDeep))
	-- key phrases, longest first, whole words only
	local keys = {}
	if def and type(def.Keywords) == "table" then
		for _, k in ipairs(def.Keywords) do
			if type(k) == "string" and k ~= "" then
				keys[#keys + 1] = k
			end
		end
	end
	table.sort(keys, function(a, b)
		return #a > #b
	end)
	for _, k in ipairs(keys) do
		local init = 1
		while true do
			local s, e = string.find(text, k, init, true)
			if not s then
				break
			end
			local before = s > 1 and string.sub(text, s - 1, s - 1) or ""
			local after = string.sub(text, e + 1, e + 1)
			if not isWordChar(before) and not isWordChar(after) and free(s, e) then
				spans[#spans + 1] = { s, e, keyColor }
			end
			init = e + 1
		end
	end
	-- words painted in their own colour (element names), moved until they read on the pale well
	if def and type(def.ColorWords) == "table" then
		for word, color in pairs(def.ColorWords) do
			if type(word) == "string" and word ~= "" and typeof(color) == "Color3" then
				local wordColor = hex(inkOnWell(color))
				local from = 1
				while true do
					local s, e = string.find(text, word, from, true)
					if not s then
						break
					end
					local before = s > 1 and string.sub(text, s - 1, s - 1) or ""
					if not isWordChar(before) and not isWordChar(string.sub(text, e + 1, e + 1)) and free(s, e) then
						spans[#spans + 1] = { s, e, wordColor }
					end
					from = e + 1
				end
			end
		end
	end
	-- numbers: "+10", "x1.5", "1,000 Tokens", "40%", "1.6"
	local init = 1
	while true do
		local s, e = string.find(text, "[%+x]?%d[%d,%.]*%%?", init)
		if not s then
			break
		end
		if string.sub(text, s, s) == "x" and s > 1 and isWordChar(string.sub(text, s - 1, s - 1)) then
			s = s + 1 -- an "x" glued to a word is not a multiplier
		end
		while e > s and string.find(string.sub(text, e, e), "[,%.]") do
			e = e - 1
		end
		local glyph = " " .. TOKEN_WORD
		if string.sub(text, e + 1, e + #glyph) == glyph then
			e = e + #glyph
		end
		if free(s, e) then
			spans[#spans + 1] = { s, e, numColor }
		end
		init = e + 1
	end
	table.sort(spans, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local pos = 1
	for _, sp in ipairs(spans) do
		out[#out + 1] = escapeRich(string.sub(text, pos, sp[1] - 1))
		out[#out + 1] = '<font color="' .. sp[3] .. '">' .. escapeRich(string.sub(text, sp[1], sp[2])) .. "</font>"
		pos = sp[2] + 1
	end
	out[#out + 1] = escapeRich(string.sub(text, pos))
	return table.concat(out), text
end

-- UTF-8 characters of `text` into `into` (reused table); returns the count
local function splitChars(text, into)
	for i = #into, 1, -1 do
		into[i] = nil
	end
	local n = 0
	for ch in string.gmatch(text, "[\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		into[n] = ch
	end
	return n
end

local function charDelay(ch)
	local d = 1 / K.CPS
	if ch == "." or ch == "!" or ch == "?" then
		d = d + K.PAUSE_END
	elseif ch == "," or ch == ":" then
		d = d + K.PAUSE_MID
	end
	return d
end

----------------------------------------------------------------------
-- NPC records
----------------------------------------------------------------------
local function countParts(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

local function isComplete(model)
	if model:GetAttribute("Ready") ~= true then
		return false
	end
	local wanted = model:GetAttribute("PetParts")
	if type(wanted) ~= "number" then
		return true -- an NPC without a pet
	end
	local pet = model:FindFirstChild("Pet")
	if not pet then
		return false
	end
	local root = pet.PrimaryPart or pet:FindFirstChild("Body")
	return root ~= nil and countParts(pet) >= wanted
end

-- Parts that PetBuilder.Animate re-poses every call (wings, tail, halo...). Eyelids ("lid" groups) only change
-- transparency, so they stay welded to the body like everything else.
local function isAnimatedPart(part)
	local spec = part:GetAttribute("PB_G")
	if type(spec) ~= "string" then
		return false
	end
	local kind = string.match(spec, "^[^:]*:([^:]*)")
	return kind ~= "lid"
end

-- Welds every static part of the pet to its anchored root (local to this client): a pose is then one CFrame
-- write on the root. Returns true when the whole pet is welded.
local function weldStatic(pet, root)
	local ok, err = pcall(function()
		local inv = root.CFrame:Inverse()
		for _, part in ipairs(pet:GetDescendants()) do
			if part:IsA("BasePart") and part ~= root and not isAnimatedPart(part) then
				local weld = Instance.new("Weld")
				weld.Name = "NpcIdleWeld"
				weld.Part0 = root
				weld.Part1 = part
				weld.C0 = inv * part.CFrame
				weld.C1 = CFrame.new()
				weld.Parent = part
				part.Anchored = false
			end
		end
		root.Anchored = true
	end)
	if not ok then
		warn("[NpcController] could not weld an NPC pet, using PivotTo: " .. tostring(err))
	end
	return ok
end

local function scaleNameplate(rec)
	local gui = rec.Nameplate
	if not gui or not gui.Parent then
		return
	end
	local w = tonumber(gui:GetAttribute("BaseWidth"))
	local h = tonumber(gui:GetAttribute("BaseHeight"))
	local plate = gui:FindFirstChild("Plate")
	if not (w and h and plate and plate:IsA("GuiObject")) then
		return
	end
	local f = Theme.ScreenFactor()
	gui.Size = UDim2.fromOffset(math.floor(w * f + 0.5), math.floor(h * f + 0.5))
	local scale = plate:FindFirstChild("ReadScale")
	if not (scale and scale:IsA("UIScale")) then
		scale = make("UIScale", { Name = "ReadScale" }, plate)
	end
	scale.Scale = f
end

local function refreshBadge(rec)
	if rec.Badge then
		rec.Badge.Visible = not talkedTo[rec.Id]
	end
end

local onPrompt -- forward declaration (the dialog section defines it)
local ensureLoop

local function removeRec(rec)
	for i = #recs, 1, -1 do
		if recs[i] == rec then
			table.remove(recs, i)
		end
	end
	if rec.Model then
		byModel[rec.Model] = nil
	end
	if rec.PromptConn then
		rec.PromptConn:Disconnect()
		rec.PromptConn = nil
	end
	if dialog.Open and dialog.Rec == rec then
		NpcController.Close()
	end
end

local function setup(model)
	if byModel[model] or not model.Parent then
		return
	end
	local id = model:GetAttribute("NpcId")
	if type(id) ~= "string" then
		return
	end
	local rec = {
		Model = model,
		Id = id,
		Def = NpcDialog and NpcDialog.Get(id) or nil,
		Yaw = 0,
		Phase = (#recs * 1.37) % TAU,
		Skip = 0,
		Frame = 0,
		HopT = nil,
		Target = nil,
		AnimOpts = { Flap = K.FLAP, Excited = 0 },
		Accent = model:GetAttribute("Accent"),
	}
	if typeof(rec.Accent) ~= "Color3" then
		rec.Accent = (rec.Def and rec.Def.Accent) or Color3.fromRGB(120, 180, 236)
	end
	local pet = model:FindFirstChild("Pet")
	local root = pet and (pet.PrimaryPart or pet:FindFirstChild("Body"))
	if pet and root and root:IsA("BasePart") then
		rec.Pet = pet
		rec.Root = root
		rec.Base = root.CFrame
		rec.Welded = weldStatic(pet, root)
	end
	local promptPart = model:FindFirstChild("PromptPart")
	rec.Center = (promptPart and promptPart:IsA("BasePart") and promptPart.Position) or (rec.Base and rec.Base.Position)
		or model:GetPivot().Position
	rec.Prompt = model:FindFirstChild("TalkPrompt", true)
	rec.Nameplate = model:FindFirstChild("Nameplate", true)
	rec.Badge = rec.Nameplate and rec.Nameplate:FindFirstChild("Badge", true) or nil
	scaleNameplate(rec)
	refreshBadge(rec)
	if not promptServiceHooked and rec.Prompt and rec.Prompt:IsA("ProximityPrompt") then
		-- ProximityPromptService.PromptTriggered is unavailable: listen on the prompt itself
		local prompt = rec.Prompt
		rec.PromptConn = prompt.Triggered:Connect(function(player)
			onPrompt(prompt, player)
		end)
	end
	recs[#recs + 1] = rec
	byModel[model] = rec
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) and byModel[model] == rec then
			removeRec(rec)
		end
	end)
	ensureLoop()
	if dialog.PendingOpen == model then
		dialog.PendingOpen = nil
		task.defer(function()
			if byModel[model] == rec then
				NpcController.Open(rec.Id)
			end
		end)
	end
end

local function track(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	if byModel[model] or pending[model] then
		return
	end
	pending[model] = true
	task.spawn(function()
		local waited = 0
		while waited < K.READY_TIMEOUT and model.Parent and not isComplete(model) do
			task.wait(0.2)
			waited = waited + 0.2
		end
		pending[model] = nil
		if model.Parent then
			local ok, err = pcall(setup, model)
			if not ok then
				warn("[NpcController] NPC setup failed: " .. tostring(err))
			end
		end
	end)
end

local function recByPrompt(prompt)
	for _, rec in ipairs(recs) do
		if rec.Prompt == prompt then
			return rec
		end
	end
	-- a prompt we have not seen yet (the NPC is still replicating): find its NPC model
	local node = prompt
	while node and node ~= Workspace do
		local rec = byModel[node]
		if rec then
			return rec
		end
		node = node.Parent
	end
	return nil
end

----------------------------------------------------------------------
-- Idle animation
----------------------------------------------------------------------
local function refreshTargets()
	local roots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			roots[#roots + 1] = root
		end
	end
	local mine = localRoot()
	for _, rec in ipairs(recs) do
		local best, bestD = nil, K.LOOK_RANGE
		if dialog.Open and dialog.Rec == rec and mine then
			best = mine
		elseif rec.Center then
			for _, root in ipairs(roots) do
				local d = (root.Position - rec.Center).Magnitude
				if d < bestD then
					best, bestD = root, d
				end
			end
		end
		rec.Target = best
	end
end

local function poseNpc(rec, dt)
	local base = rec.Base
	-- slow turn toward the target (or back to the walkway)
	local desired = 0
	local target = rec.Target
	if target and target.Parent then
		local v = base:PointToObjectSpace(target.Position)
		if v.X * v.X + v.Z * v.Z > 0.25 then
			desired = clamp(math.atan2(-v.X, -v.Z), -K.MAX_TURN, K.MAX_TURN)
		end
	end
	local turn = (desired - rec.Yaw) * (1 - math.exp(-dt * K.TURN_RATE))
	local maxStep = K.TURN_SPEED * dt
	rec.Yaw = rec.Yaw + clamp(turn, -maxStep, maxStep)

	local talking = dialog.Open and dialog.Rec == rec
	local t = clock + rec.Phase
	local y = math.sin(t * TAU / K.BOB_PERIOD) * K.BOB_AMP
	if rec.HopT then
		rec.HopT = rec.HopT + dt
		local u = rec.HopT / K.HOP_TIME
		if u >= 1 then
			rec.HopT = nil
		else
			y = y + 4 * u * (1 - u) * K.HOP_H
		end
	end
	local pitch = 0
	if talking then
		local amount = 0.35
		if dialog.Typing then
			amount = 1
		end
		pitch = math.sin(t * 7.5) * K.NOD * amount
	end
	local roll = math.sin(t * 0.83) * K.ROLL
	local cf = base * CFrame.new(0, y, 0) * CFrame.Angles(0, rec.Yaw, 0) * CFrame.Angles(pitch, 0, roll)
	if rec.Welded then
		rec.Root.CFrame = cf
	else
		rec.Pet:PivotTo(cf)
	end

	local opts = rec.AnimOpts
	if talking then
		opts.Flap = K.FLAP_TALK
		opts.Excited = K.EXCITE_TALK
	else
		opts.Flap = K.FLAP
		opts.Excited = 0
	end
	if PetBuilder and PetBuilder.Animate then
		local ok = pcall(PetBuilder.Animate, rec.Pet, clock, opts)
		if not ok then
			rec.Pet = nil -- a broken rig: keep the NPC still from now on
		end
	end
end

-- distance from an NPC to the viewer: the camera or the local character, whichever is closer
local function viewDistance(pos, camPos, rootPos)
	local d = math.huge
	if camPos then
		d = (pos - camPos).Magnitude
	end
	if rootPos then
		d = math.min(d, (pos - rootPos).Magnitude)
	end
	if d == math.huge then
		return 0
	end
	return d
end

local function stepNpcs(dt, camPos, rootPos)
	for i = 1, #recs do
		local rec = recs[i]
		if rec.Pet and rec.Root and rec.Root.Parent then
			local d = viewDistance(rec.Base.Position, camPos, rootPos)
			if d <= K.CULL then
				rec.Frame = rec.Frame + 1
				rec.Skip = rec.Skip + dt
				if d <= K.NEAR or rec.Frame % 2 == 0 then
					local step = math.min(rec.Skip, 0.1)
					rec.Skip = 0
					poseNpc(rec, step)
				end
				if rec.Badge and rec.Badge.Visible and d <= K.NEAR then
					rec.Badge.Rotation = math.sin(clock * 4 + rec.Phase) * 12 -- a little "new tips" wiggle
				end
			else
				rec.Skip = 0
			end
		end
	end
end

----------------------------------------------------------------------
-- Dialog UI
----------------------------------------------------------------------
local function newButton(text, style, size, callback, parent)
	if CloudUI and CloudUI.Button then
		local ok, button = pcall(CloudUI.Button, {
			Name = "Button_" .. text,
			Text = text,
			Style = style,
			Skin = "Sign", -- (kit B U9-9) a plank with its lip: a press sinks it onto the lip
			Size = size,
			TextSize = K.BUTTON,
			Callback = callback,
			Parent = parent,
		})
		if ok and button then
			return button
		end
	end
	local button = make("TextButton", {
		Name = "Button_" .. text,
		Size = size,
		AutoButtonColor = true,
		BorderSizePixel = 0,
		BackgroundColor3 = style == "Green" and SIGN.Grass or SIGN.Tile,
		Text = text,
	}, nil)
	Theme.Style(button, "Button", { Size = K.BUTTON, Color = style == "Green" and SIGN.OnGrass or SIGN.Text })
	edge(button, SIGN.Wood, 3)
	button.Activated:Connect(function()
		callback(button)
	end)
	button.Parent = parent
	return button
end

-- (kit B U9-9) the speech tail: a stepped pixel wedge (rows of 4 px, 4 / 8 / 12 / 8 / 4 wide) in the wood colour, its
-- point at the portrait, its base on the well's left edge
local TAIL_ROWS = { 4, 8, 12, 8, 4 }

local function buildDialog()
	local gui
	if CloudUI and CloudUI.NewScreenGui then
		gui = CloudUI.NewScreenGui("NimbusNpcDialog", K.DISPLAY_ORDER)
	else
		local pg = playerGui()
		local old = pg and pg:FindFirstChild("NimbusNpcDialog")
		if old then
			old:Destroy()
		end
		gui = make("ScreenGui", {
			Name = "NimbusNpcDialog",
			ResetOnSpawn = false,
			IgnoreGuiInset = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = K.DISPLAY_ORDER,
		}, pg)
	end
	UI.Gui = gui

	local root = box("NpcDialog", {
		Position = UDim2.new(0, K.EDGE, 1, -220 - K.H), -- (U9-9 look) by its top-left corner (layoutDialog)
		Size = UDim2.fromOffset(K.W, K.H),
		Visible = false,
	}, gui)
	UI.Root = root
	UI.Scale = make("UIScale", { Name = "ReadScale", Scale = 1 }, root)

	local slide = box("Slide", { Size = UDim2.fromScale(1, 1) }, root)
	UI.Slide = slide
	if PixelCrisp then
		PixelCrisp.Root(slide) -- (U9-9 look) it slides in; the card's parts sit on whole px of it at rest
	end

	-- the card: the wood frame round the stone body, its stone lip along the bottom (the Signboard window's parts)
	local card = box("Card", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Wood,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Active = true, -- clicks on the card never fall through to the world
	}, slide)
	card:SetAttribute("SignKit", "Frame")
	local stone = box("Stone", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Stone,
		Position = UDim2.fromOffset(K.FRAME, K.FRAME),
		Size = UDim2.new(1, -2 * K.FRAME, 1, -2 * K.FRAME),
		ZIndex = 3,
	}, card)
	stone:SetAttribute("SignKit", "Body")
	UI.StoneLip = lipOf(stone, SIGN.StoneLip, K.ROWS.Tall.Lip)
	-- (U9-9 look 2) the card and the stone in it on whole px on all four sides: the wood frame round the stone is whole
	-- px wide on every side at any card scale (it drew 4.8 / 4.2 px, one side crisp and the other soft)
	UI.Card = crispBox(card)
	crispBox(stone)
	-- (Pitch 2 F0, finish pass A) the frame's light, the card's shadow, the stone sunk under the frame with its carved rim
	local SK = optionalShared("SignKit")
	if SK and SK.FinishFrame then
		SK.FinishFrame(card, { Body = stone })
	end

	-- portrait: a sky well in a wood edge, the NPC's accent colour on its lip, a little pixel cloud in its corner
	local portrait = box("Portrait", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Sky,
		Position = UDim2.fromOffset(K.PAD, 16),
		Size = UDim2.fromOffset(K.PORTRAIT, K.PORTRAIT),
		ZIndex = 5,
	}, card)
	edge(portrait, SIGN.Wood, K.PORTRAIT_EDGE)
	UI.PortraitLip = lipOf(portrait, SIGN.SkyLip, K.PORTRAIT_LIP)
	UI.PortraitLip.ZIndex = 8 -- over the pet's feet, like the ground it stands on
	UI.Portrait = crispBox(portrait)
	UI.PortraitHolder = box("Holder", { Size = UDim2.new(1, 0, 1, -K.PORTRAIT_LIP), ZIndex = 6 }, portrait)
	if PixelCrisp then
		-- (anchored at its top-left corner: at a 0.7 card its 18 screen px grow into the sky, away from the frame)
		PixelCrisp.Icon(portrait, "cloud", K.ICON, SIGN.Stone, {
			Name = "Cloud",
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(6, 4),
			ZIndex = 6,
		})
	end

	-- title caption under the portrait: a stone tag ((U9-9 look) 50 high on the tall card: its two rows of words clear
	-- of its edge and lip). (U9-9 look 2) PORTRAIT + 2 wide: its 2 px edge lines up with the portrait's 3 px edge; its
	-- bottom on the footer's bottom line (layoutDialog)
	local titlePill = box("TitlePill", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Tile,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(K.PAD + K.PORTRAIT / 2, 16 + K.PORTRAIT + 12),
		Size = UDim2.fromOffset(K.PORTRAIT + 2, K.ROWS.Tall.TitleTag),
		ZIndex = 6,
	}, card)
	UI.TitleStroke = edge(titlePill, SIGN.Wood, K.EDGE_PX)
	lipOf(titlePill, SIGN.StoneLip, K.TAG_LIP)
	UI.TitlePill = crispBox(titlePill)
	UI.Title = Theme.Label("", "Label", {
		Size = K.CAPTION,
		Color = SIGN.Text,
		Props = {
			Name = "Title",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -1),
			Size = UDim2.new(1, -10, 1, -(4 + K.TAG_LIP)),
			TextWrapped = true,
			LineHeight = 0.9,
			ZIndex = 7,
		},
	})
	UI.Title.Parent = titlePill

	-- the name on a navy plank riding on the top edge: gold, a plain Section title; a brass rivet at each end
	local nameTab = box("NameTab", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Navy,
		Position = UDim2.fromOffset(K.WELL_X, -22),
		Size = UDim2.fromOffset(250, 46),
		ZIndex = 8,
	}, slide)
	edge(nameTab, SIGN.GoldLip, 3)
	lipOf(nameTab, SIGN.NavyLip, K.NAME_LIP)
	for _, side in ipairs({ { "RivetL", 0, 6 }, { "RivetR", 1, -10 } }) do
		local rivet = box(side[1], {
			BackgroundTransparency = 0,
			BackgroundColor3 = SIGN.Brass,
			Position = UDim2.new(side[2], side[3], 0.5, -4),
			Size = UDim2.fromOffset(4, 4),
			ZIndex = 9,
		}, nameTab)
		if PixelCrisp then
			PixelCrisp.Adopt(rivet, 4) -- (U9-9 look) a whole-px square on a whole px
		end
	end
	UI.NameTab = crispBox(nameTab)
	UI.Name = Theme.Label("", "Title", {
		Scaled = true,
		Color = SIGN.Gold,
		Props = {
			Name = "Name",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -2),
			-- (U9-9 look 2) TAB_INSET in from each end: the letters 12 px clear of the brass rivets
			Size = UDim2.new(1, -2 * K.TAB_INSET, 1, -(10 + K.NAME_LIP)),
			ZIndex = 9,
		},
	})
	make("UITextSizeConstraint", { MaxTextSize = K.NAME, MinTextSize = 20 }, UI.Name)
	Theme.StyleTitle(UI.Name, "Section")
	UI.Name.Parent = nameTab

	-- the stepped pixel tail toward the portrait, then the text well (pale, high contrast)
	local tail = box("Tail", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(K.WELL_X - K.EDGE_PX, K.WELL_TOP + 24),
		Size = UDim2.fromOffset(12, 4 * #TAIL_ROWS),
		ZIndex = 5,
	}, card)
	for i, w in ipairs(TAIL_ROWS) do
		box("Step" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = SIGN.Wood,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, (i - 1) * 4),
			Size = UDim2.fromOffset(w, 4),
			ZIndex = 5,
		}, tail)
	end
	if PixelCrisp then
		PixelCrisp.Adopt(tail, 4) -- (U9-9 look) its steps whole px each (2.8 px drew uneven), from a whole px
	end
	local well = make("TextButton", {
		Name = "Well",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.Well,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(K.WELL_X, K.WELL_TOP),
		Size = UDim2.new(1, -(K.WELL_X + K.PAD), 1, -(K.WELL_TOP + K.FOOTER_H + K.ROWS.Tall.Well)),
		ZIndex = 6,
	}, card)
	edge(well, SIGN.Wood, K.EDGE_PX)
	UI.Well = crispBox(well)
	local line = Theme.Label("", "Body", {
		Size = K.TEXT,
		Color = SIGN.Text,
		Props = {
			Name = "Line",
			RichText = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(14, 10),
			-- the bottom row of the well holds the page dots, (U9-9 look) the speech ends 9 design px (6 px at 0.7) over them
			Size = UDim2.new(1, -28, 1, -37),
			LineHeight = 1.05,
			ZIndex = 7,
		},
	})
	line.Parent = well
	UI.Line = line
	-- the pixel down arrow: "there is more" (kit-b U7b; it was U+25BC), brown, on whole screen pixels
	local more = box("More", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -6),
		Size = UDim2.fromOffset(18, 18),
		Visible = false,
		ZIndex = 8,
	}, well)
	if PixelCrisp then
		-- (U9-9 look) from the slot's top-left, the slot itself on a whole px as it bobs (crispBox)
		PixelCrisp.Icon(more, "down", K.ICON, SIGN.Text, { ZIndex = 8, AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(0, 0) })
	end
	UI.More = crispBox(more)

	-- page dots in the bottom row of the well: square blocks in a wood edge (the line shown gold, the rest the sunk well)
	local dots = box("Dots", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -8),
		Size = UDim2.fromOffset(K.MAX_DOTS * (K.DOT + K.DOT_GAP), K.DOT),
		ZIndex = 8,
	}, well)
	UI.Dots = {}
	for i = 1, K.MAX_DOTS do
		local dot = box("Dot" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = C.DotOff,
			Position = UDim2.fromOffset((i - 1) * (K.DOT + K.DOT_GAP), 0),
			Size = UDim2.fromOffset(K.DOT, K.DOT),
			ZIndex = 9,
			Visible = false,
		}, dots)
		edge(dot, SIGN.Wood, K.EDGE_PX)
		if PixelCrisp then
			PixelCrisp.Adopt(dot, K.DOT) -- (U9-9 look) every dot the same whole px square, on a whole px
		end
		UI.Dots[i] = dot
	end

	-- footer: Close (a stone plank), Next (the green plank: the dialog's one action), right-aligned under the well
	local footer = box("Footer", {
		Position = UDim2.new(0, K.WELL_X, 1, -(K.FOOTER_H + K.ROWS.Tall.FootUp)),
		Size = UDim2.new(1, -(K.WELL_X + K.PAD), 0, K.FOOTER_H),
		ZIndex = 6,
	}, card)
	UI.Footer = footer

	UI.Next = newButton("Next", "Green", UDim2.fromOffset(K.NEXT_W, K.FOOTER_H), function()
		NpcController.Advance()
	end, footer)
	UI.Next.AnchorPoint = Vector2.new(1, 0.5)
	UI.Next.Position = UDim2.new(1, 0, 0.5, 0)
	UI.Next.ZIndex = 8
	-- (U9-9 look 2) on the full card Close stands BUTTON_GAP left of Next; the compact card moves it into the left column
	-- under the title tag and Next spans the well (placeButtons)
	UI.Close = newButton("Close", "Gray", UDim2.fromOffset(K.CLOSE_W, K.FOOTER_H), function()
		NpcController.Close()
	end, footer)
	UI.Close.AnchorPoint = Vector2.new(1, 0.5)
	UI.Close.Position = UDim2.new(1, -(K.NEXT_W + K.BUTTON_GAP), 0.5, 0)
	UI.Close.ZIndex = 8
	-- (U9-9 look) the planks' wood edges and lips on whole px at the card's scale (2.1 px drew uneven), from whole px
	if PixelCrisp then
		for _, b in ipairs({ UI.Next, UI.Close }) do
			for _, c in ipairs(b:GetChildren()) do
				if c:IsA("UIStroke") then
					PixelCrisp.Edge(c, c.Thickness)
				elseif c.Name == "Lip" and c:IsA("GuiObject") then
					PixelCrisp.Lip(c, c.Size.Y.Offset)
				end
			end
			PixelCrisp.Box(b)
		end
	end

	well.Activated:Connect(function()
		if dialog.Typing then
			NpcController.Advance()
		end
	end)
end

----------------------------------------------------------------------
-- Dialog layout (bottom-left, above the HUD, clear of the menu column)
----------------------------------------------------------------------
local function menuColumnRect()
	local pg = playerGui()
	local menu = pg and pg:FindFirstChild("NimbusMenu")
	if not (menu and menu:IsA("ScreenGui") and menu.Enabled) then
		return nil
	end
	local dy = insetShift(menu)
	local column = menu:FindFirstChild("MenuColumn", true)
	if column and column:IsA("GuiObject") and shownIn(column, menu) and column.AbsoluteSize.X > 0 then
		return rectOf(column, dy)
	end
	local rect = nil
	for _, d in ipairs(menu:GetDescendants()) do
		if d:IsA("GuiObject") and string.sub(d.Name, 1, 11) == "MenuButton_" and d.AbsoluteSize.X > 0 and shownIn(d, menu) then
			local r = rectOf(d, dy)
			if rect then
				rect.x0, rect.y0 = math.min(rect.x0, r.x0), math.min(rect.y0, r.y0)
				rect.x1, rect.y1 = math.max(rect.x1, r.x1), math.max(rect.y1, r.y1)
			else
				rect = r
			end
		end
	end
	return rect
end

local function tutorialRect()
	local pg = playerGui()
	local gui = pg and pg:FindFirstChild("NimbusTutorial")
	if not (gui and gui:IsA("ScreenGui") and gui.Enabled) then
		return nil
	end
	local panel = gui:FindFirstChild("TutorialPanel", true)
	if panel and panel:IsA("GuiObject") and shownIn(panel, gui) and panel.AbsoluteSize.X > 0 then
		return rectOf(panel, insetShift(gui))
	end
	return nil
end

-- The pet hotbar (NimbusHotbar.Hotbar, bottom centre) in gui-area pixels, nil while hidden or unmeasured.
local function hotbarRect()
	local pg = playerGui()
	local bar = pg and pg:FindFirstChild("NimbusHotbar")
	if not (bar and bar:IsA("ScreenGui") and bar.Enabled) then
		return nil
	end
	local holder = bar:FindFirstChild("Hotbar")
	if holder and holder:IsA("GuiObject") and shownIn(holder, bar) and holder.AbsoluteSize.X > 0 then
		return rectOf(holder, insetShift(bar))
	end
	return nil
end

-- (U9-9 look) the top bar's pill (NimbusTopBar, display order 21: it draws over the card) and its edge in our gui px,
-- nil while it is hidden or unmeasured
local function topBarPillRect()
	local pg = playerGui()
	local bar = pg and pg:FindFirstChild("NimbusTopBar")
	if not (bar and bar:IsA("ScreenGui") and bar.Enabled) then
		return nil
	end
	local pill = bar:FindFirstChild("Pill", true)
	if not (pill and pill:IsA("GuiObject") and shownIn(pill, bar) and pill.AbsoluteSize.X > 0) then
		return nil
	end
	local r = rectOf(pill, insetShift(bar))
	local stroke = pill:FindFirstChildOfClass("UIStroke")
	local e = stroke and stroke.Thickness or 0
	r.x0, r.y0, r.x1, r.y1 = r.x0 - e, r.y0 - e, r.x1 + e, r.y1 + e
	return r
end

-- (U9-9 look) the HUD's vitals card steps aside while the card lies over a part of it (the card stepped down under the
-- top bar's pill), as the result card and the Trove window do; back when it closes
local function setVitalsOff(off)
	if off == (dialog.VitalsOff == true) then
		return
	end
	local module = script.Parent:FindFirstChild("HudController")
	local okHud, hud = false, nil
	if module then
		okHud, hud = pcall(require, module)
	end
	if okHud and type(hud) == "table" and type(hud.SetVitalsHidden) == "function" then
		dialog.VitalsOff = off
		pcall(hud.SetVitalsHidden, "NpcDialog", off)
	end
end

local function syncVitals(card)
	local off = false
	local module = script.Parent:FindFirstChild("HudController")
	local okHud, hud = false, nil
	if module then
		okHud, hud = pcall(require, module)
	end
	if card and okHud and type(hud) == "table" and type(hud.GetLayout) == "function" then
		local okLayout, layout = pcall(hud.GetLayout)
		local slot = okLayout and type(layout) == "table" and layout.VitalsSlot
		if slot then -- (gui-area px of an IgnoreGuiInset = false gui, as ours)
			local w = math.min(card.x1, slot.X + slot.W) - math.max(card.x0, slot.X)
			local h = math.min(card.y1, slot.Y + slot.H) - math.max(card.y0, slot.Y)
			off = w > 4 and h > 4
		end
	end
	setVitalsOff(off)
end

-- Fits the card into the box left..rightLimit x topLimit..bottom (gui px): returns scale, design width, design
-- height and its bottom rows (K.ROWS). Narrow boxes get the compact card, (U9-9 review) a box too short for it even at
-- K.MIN_SCALE the short rows; the scale may come out below K.MIN_SCALE (= does not fit). (U9-9 look) On a portrait
-- screen (`tall`) the compact card is K.PORTRAIT_EXTRA taller: its speech kept clear of the page dots.
-- (U9-9 look 2) the name plank on a card of design width w: on the compact card it spans the well (flush with its right
-- edge), on the full card it is at most 250 wide; its name gets one row, or a second NAME_ROW when the name at the 20 px floor is wider than its room (TAB_INSET in from
-- each end): the plank grows up by that row instead of TextScaled wrapping two rows inside a one-row plank. -> width, extra
local function tabFor(w)
	local tabW = w - K.WELL_X - K.PAD
	if w >= K.W - 60 then
		tabW = math.min(250, tabW) -- (the full card's plank: the compact card's spans its whole well)
	end
	local text = UI.Name and UI.Name.Text or ""
	if text ~= "" then
		local ok, size = pcall(Theme.Measure, text, "Title", 20)
		if ok and typeof(size) == "Vector2" and size.X > tabW - 2 * K.TAB_INSET then
			return tabW, K.NAME_ROW
		end
	end
	return tabW, 0
end

local function fitCard(left, bottom, topLimit, rightLimit, f, tall)
	local availW, availH = rightLimit - left, bottom - topLimit
	if availW <= 0 or availH <= 0 then
		return 0, K.W_MIN, K.H_COMPACT - K.ROWS.Short.Cut, K.ROWS.Short
	end
	local scale = f
	local w = K.W
	if w * scale > availW then
		w = math.max(K.W_MIN, math.floor(availW / scale))
		if w * scale > availW then
			scale = availW / w
		end
	end
	local h = K.H
	if w < K.W - 60 then
		h = K.H_COMPACT + (tall and K.PORTRAIT_EXTRA or 0)
	end
	local _, extra = tabFor(w)
	local rows = K.ROWS.Tall
	if (h + rows.TabAbove + extra) * K.MIN_SCALE > availH then
		rows = K.ROWS.Short
		h = h - rows.Cut
	end
	if (h + rows.TabAbove + extra) * scale > availH then
		scale = availH / (h + rows.TabAbove + extra)
	end
	-- (U9-9 look 2) a fitted scale steps down to a tenth (0.724 -> 0.7): the card's lengths, multiples of 10, are whole px
	-- there (at 0.724 none could be); never under MIN_SCALE (a scale under it still says "does not fit")
	if scale < f and scale >= K.MIN_SCALE then
		scale = math.max(K.MIN_SCALE, math.floor(scale * 10 + 1e-6) / 10)
	end
	return scale, w, h, rows
end

local function layoutDialog()
	local gui, root = UI.Gui, UI.Root
	if not (gui and root) then
		return
	end
	local area = gui.AbsoluteSize
	if area.X < 2 or area.Y < 2 then
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		area = Vector2.new(vp.X, math.max(2, vp.Y - topInset()))
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local edge = touch and K.TOUCH_EDGE or K.EDGE
	local tall = area.Y > area.X -- (U9-9 look) a portrait screen: the compact card takes some of its free sky
	local f = Theme.ScreenFactor()
	local rightLimit = area.X * K.MAX_WIDTH_FRACTION
	if area.X < K.SMALL_SCREEN then
		rightLimit = math.max(rightLimit, area.X * K.SMALL_WIDTH_FRACTION)
	end
	rightLimit = math.min(rightLimit, area.X - edge)

	-- bottom: just above the HUD's bottom block (the vitals card, or an estimate of it); top: below the top-left panel
	local pg = playerGui()
	local hud = pg and pg:FindFirstChild("NimbusHud")
	local bottom = area.Y - edge - 190 * f
	local topLimit = edge
	local centre = nil -- the vitals card's x-span (bug batch 2 #1: it sits bottom-centre, not bottom-left)
	if hud and hud:IsA("ScreenGui") then
		local shift = insetShift(hud)
		local blt = hud:GetAttribute("BottomLeftTop")
		if type(blt) == "number" and blt > 0 then
			bottom = blt + shift - K.GAP
		end
		local tlb = hud:GetAttribute("TopLeftBottom")
		if type(tlb) == "number" and tlb > 0 then
			topLimit = tlb + shift + K.GAP
		end
		local bcl, bcr = hud:GetAttribute("BottomCentreLeft"), hud:GetAttribute("BottomCentreRight")
		if type(bcl) == "number" and type(bcr) == "number" and bcr > bcl then
			centre = { x0 = bcl, x1 = bcr }
		end
	end
	bottom = clamp(bottom, 60, area.Y - edge)

	-- 1) bottom-left above the HUD, stepping aside from the menu column / the tutorial card on our rows
	local column = menuColumnRect()
	local tut = tutorialRect()
	local function placeAt(b)
		local left = edge
		local probeTop = b - (K.H + K.TAB_ABOVE) * f
		local function sharesRows(r)
			return r ~= nil and r.y1 > probeTop and r.y0 < b
		end
		if sharesRows(column) then
			left = math.max(left, column.x1 + K.GAP)
		end
		if sharesRows(tut) and tut.x0 < left + K.W * f then
			local alt = tut.x1 + K.GAP
			if alt + K.W_MIN * K.MIN_SCALE <= rightLimit then
				left = math.max(left, alt)
			end
		end
		local s, cw, ch, rows = fitCard(left, b, topLimit, rightLimit, f, tall)
		return s, cw, ch, left, rows
	end
	local scale, w, h, left, rows = placeAt(bottom)
	-- desktops: the vitals card is bottom-CENTRE now, so the dialog only has to stand above it when its x-span
	-- actually meets the card (or the hotbar under it); otherwise it keeps its own default bottom near the edge.
	-- (Touch keeps the HUD's line: Roblox's thumbstick owns the bottom-left corner there.)
	if centre and not touch then
		local low = area.Y - edge
		local bar = hotbarRect()
		local function clear(b, l, s, cw)
			local x1 = l + cw * s
			if x1 + K.GAP > centre.x0 and l < centre.x1 + K.GAP then
				return false
			end
			return bar == nil or b <= bar.y0 - K.GAP or x1 + K.GAP <= bar.x0 or l >= bar.x1 + K.GAP
		end
		-- (U9-9 look 2) the corner dock is tried whenever there is room under the HUD's line, not only when the lifted card
		-- is already clear of the vitals: lifted, the menu rail pushed a 720p card right against the vitals card (it floated
		-- mid-left, 2 px from the vitals' corner); docked low it starts at the edge, clear of both (as at 1080p)
		if low > bottom + 1 then
			local s2, w2, h2, l2, r2 = placeAt(low)
			if clear(low, l2, s2, w2) then
				bottom, scale, w, h, left, rows = low, s2, w2, h2, l2, r2
			end
		end
	end
	local x, y = left, bottom
	if scale < K.MIN_SCALE and column and column.y0 > topLimit then
		-- 2) narrow screens: above the menu column, from the left edge
		local b2 = column.y0 - K.GAP
		local s2, w2, h2, r2 = fitCard(edge, b2, topLimit, area.X - edge, f, tall)
		if s2 >= K.MIN_SCALE then
			scale, w, h, x, y, rows = s2, w2, h2, edge, b2, r2
		end
	end
	scale = math.max(K.MIN_SCALE, scale) -- never below readable text, even if the card then overlaps a little
	-- (U9-9 look) the name plank never under the top bar's pill (it draws over the card: on a 640 x 360 window the pill
	-- hid the plank's words): the card steps down until the plank's gold edge is K.PILL_GAP under the pill, and the
	-- HUD's vitals card steps aside if the card then lies over it (syncVitals below)
	-- (U9-9 look 2) the plank spans the well (it was 104 px short of it: "CAPTAIN PENGUIN" wrapped to two rows on its lip)
	local tabW, extra = tabFor(w)
	local tabH = rows.Tab + extra
	local pill = topBarPillRect()
	if pill then
		local px0, px1 = x + (K.WELL_X - 3) * scale, x + (K.WELL_X + tabW + 3) * scale
		local ptop = y - h * scale + (24 - tabH - 3) * scale
		if px1 > pill.x0 and px0 < pill.x1 and ptop < pill.y1 + K.PILL_GAP then
			y = math.min(area.Y, y + (pill.y1 + K.PILL_GAP - ptop))
		end
	end
	root.Size = UDim2.fromOffset(w, h)
	-- (U9-9 review) the bottom rows of the tall or the short card: the well's room under it, the footer, the stone lip
	if UI.Well then
		UI.Well.Size = UDim2.new(1, -(K.WELL_X + K.PAD), 1, -(K.WELL_TOP + K.FOOTER_H + rows.Well))
	end
	if UI.Footer then
		UI.Footer.Position = UDim2.new(0, K.WELL_X, 1, -(K.FOOTER_H + rows.FootUp))
	end
	if UI.StoneLip then
		UI.StoneLip.Size = UDim2.new(1, 0, 0, rows.Lip)
	end
	UI.Root:SetAttribute("Rows", rows == K.ROWS.Short and "Short" or "Tall")
	-- (merge kitb-look1 x U9-9) the short card's 12 px of stone over the footer holds the kit's 5 px plank edge with
	-- 2 px to spare at 0.7: there the two planks keep U9-9's 3 px edge (CloudUI.Button's EdgePx attribute)
	for _, b in ipairs({ UI.Next, UI.Close }) do
		if b then
			b:SetAttribute("EdgePx", rows == K.ROWS.Short and 3 or nil)
		end
	end
	-- (U9-9 look 2) the left column ends on the footer's bottom line, as the right one does: the full card's title tag
	-- stands on that line under a square portrait; the compact card puts Close there (under the title tag, BUTTON_GAP
	-- apart) and lets Next span the well, its one wide action, and the portrait takes the column's height above them
	local compact = w < K.W - 60
	local footTop = h - (K.FOOTER_H + rows.FootUp)
	local tagTop = h - rows.FootUp - rows.TitleTag
	if compact then
		tagTop = footTop - K.BUTTON_GAP - rows.TitleTag
	end
	UI.Root:SetAttribute("Compact", compact)
	if UI.TitlePill then
		UI.TitlePill.Size = UDim2.fromOffset(K.PORTRAIT + 2, rows.TitleTag)
		UI.TitlePill.Position = UDim2.fromOffset(K.PAD + K.PORTRAIT / 2, tagTop)
	end
	if UI.Portrait then
		UI.Portrait.Size = UDim2.fromOffset(K.PORTRAIT, math.max(K.PORTRAIT - 30, tagTop - 12 - 16))
	end
	if UI.Close and UI.Next and UI.Footer and UI.Card then
		if compact then
			UI.Close.Parent = UI.Card
			UI.Close.AnchorPoint = Vector2.new(0, 0)
			UI.Close.Position = UDim2.fromOffset(K.PAD, footTop)
			UI.Close.Size = UDim2.fromOffset(K.PORTRAIT, K.FOOTER_H)
			UI.Next.Size = UDim2.new(1, 0, 0, K.FOOTER_H)
		else
			UI.Close.Parent = UI.Footer
			UI.Close.AnchorPoint = Vector2.new(1, 0.5)
			UI.Close.Position = UDim2.new(1, -(K.NEXT_W + K.BUTTON_GAP), 0.5, 0)
			UI.Close.Size = UDim2.fromOffset(K.CLOSE_W, K.FOOTER_H)
			UI.Next.Size = UDim2.fromOffset(K.NEXT_W, K.FOOTER_H)
		end
	end
	if UI.More then
		local slot = math.ceil(K.ICON / scale - 1e-6) -- (U9-9 look) the chevron's 18 screen px inside its slot
		UI.More.Size = UDim2.fromOffset(slot, slot)
	end
	-- (U9-9 look) placed by its top-left corner on a whole px (the UIScale grows it from there): every part of the card
	-- snaps to whole px of it; its bottom stays on the line it was fitted to
	local top = math.floor(y - h * scale + 0.5)
	root.Position = UDim2.fromOffset(math.floor(x + 0.5), top)
	UI.Scale.Scale = scale
	if UI.NameTab then
		UI.NameTab.Size = UDim2.fromOffset(tabW, tabH)
		UI.NameTab.Position = UDim2.fromOffset(K.WELL_X, 24 - tabH) -- it ends 24 px into the card
		UI.NameTab:SetAttribute("Rows", extra > 0 and 2 or 1)
	end
	syncVitals({ x0 = math.floor(x + 0.5), y0 = top, x1 = math.floor(x + 0.5) + w * scale, y1 = top + h * scale })
	if PixelCrisp then
		PixelCrisp.Refresh(root) -- (kit B U9-9) the icons and wood edges back on whole pixels at the new scale
	end
	dialog.Width = w
end

----------------------------------------------------------------------
-- Dialog flow
----------------------------------------------------------------------
-- (kit B U9-9) the line shown gold, the rest the sunk well; every dot the same square (no size jump)
local function setDots(count, index)
	for i, dot in ipairs(UI.Dots or {}) do
		dot.Visible = i <= count
		dot.BackgroundColor3 = i == index and C.Gold or C.DotOff
		dot:SetAttribute("Current", i == index)
	end
end

local function finishTyping()
	dialog.Typing = false
	dialog.Shown = dialog.Total
	if UI.Line then
		UI.Line.MaxVisibleGraphemes = -1
	end
	if UI.More then
		UI.More.Visible = true
	end
end

local function showLine(index)
	local lines = dialog.Lines
	if not lines or #lines == 0 then
		return
	end
	local n = #lines
	dialog.Index = ((index - 1) % n) + 1
	local rec = dialog.Rec
	local rich, plain = richLine(lines[dialog.Index], rec and rec.Def, (rec and rec.Accent) or C.Gold)
	UI.Line.Text = rich
	dialog.Plain = plain
	dialog.Total = splitChars(plain, dialog.Chars)
	dialog.Shown = 0
	dialog.Letters = 0
	dialog.Timer = 0
	dialog.Typing = dialog.Total > 0
	UI.Line.MaxVisibleGraphemes = 0
	UI.More.Visible = false
	setDots(math.min(n, K.MAX_DOTS), math.min(dialog.Index, K.MAX_DOTS))
	if UI.Next then
		if dialog.Index >= n then
			UI.Next.Text = "Again"
		else
			UI.Next.Text = "Next"
		end
	end
	if rec then
		rec.HopT = 0
	end
	if not dialog.Typing then
		finishTyping()
	end
end

local function stepTypewriter(dt)
	if not dialog.Typing then
		return
	end
	dialog.Timer = dialog.Timer + dt
	local changed = false
	while dialog.Typing do
		local nextChar = dialog.Chars[dialog.Shown + 1]
		local need = charDelay(nextChar)
		if dialog.Timer < need then
			break
		end
		dialog.Timer = dialog.Timer - need
		dialog.Shown = dialog.Shown + 1
		changed = true
		if isWordChar(nextChar) then
			dialog.Letters = (dialog.Letters or 0) + 1
			if dialog.Letters % BLIP_EVERY == 1 then
				playSfx("DialogBlip")
			end
		end
		if dialog.Shown >= dialog.Total then
			finishTyping()
		end
	end
	if changed and dialog.Typing then
		UI.Line.MaxVisibleGraphemes = dialog.Shown
	end
end

local function setPortrait(rec)
	if dialog.Viewport then
		pcall(dialog.Viewport.Destroy)
		dialog.Viewport = nil
	end
	local holder = UI.PortraitHolder
	if not holder then
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		child:Destroy()
	end
	local petId = rec.Model and rec.Model:GetAttribute("PetId")
	local petDef = nil
	if PetCatalog and type(PetCatalog.Get) == "function" and type(petId) == "string" then
		petDef = PetCatalog.Get(petId)
	end
	if petDef and CloudUI and CloudUI.PetViewport then
		local ok, handle = pcall(CloudUI.PetViewport, holder, petDef, UDim2.fromScale(1, 1), {
			Spin = "sway",
			Flap = 0.7,
			Detail = "High",
			ZIndex = 6,
		})
		if ok and handle then
			dialog.Viewport = handle
			return
		end
	end
	-- no viewport: the NPC's initial on the accent tile
	local name = (rec.Def and rec.Def.Name) or rec.Id
	local initial = Theme.Label(string.sub(tostring(name), 1, 1), "Title", {
		Size = 64,
		Color = SIGN.Text, -- brown on the sky well
		Props = { Name = "Initial", Size = UDim2.fromScale(1, 1), ZIndex = 7 },
	})
	initial.Parent = holder
end

local function setPromptText(rec, text)
	if rec and rec.Prompt and rec.Prompt.Parent then
		pcall(function()
			rec.Prompt.ActionText = text
		end)
	end
end

local function slideTo(visible)
	local slide = UI.Slide
	if not slide then
		return
	end
	if dialog.SlideTween then
		pcall(function()
			dialog.SlideTween:Cancel()
		end)
		dialog.SlideTween = nil
	end
	local hidden = UDim2.fromOffset(-((dialog.Width or K.W) + 80), 0)
	if visible then
		UI.Root.Visible = true
		slide.Position = hidden
		dialog.SlideTween = Util.Tween(slide, 0.32, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		local tween = Util.Tween(slide, 0.2, { Position = hidden }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		dialog.SlideTween = tween
		tween.Completed:Connect(function()
			if not dialog.Open and dialog.SlideTween == tween then
				UI.Root.Visible = false
			end
		end)
	end
end

local function openRec(rec)
	if not rec or not UI.Root then
		return
	end
	local lines = (rec.Def and rec.Def.Lines) or (NpcDialog and NpcDialog.GetLines(rec.Id)) or {}
	if #lines == 0 then
		lines = { "Hello there, climber!" }
	end
	local switching = dialog.Open and dialog.Rec ~= rec
	if dialog.Open and dialog.Rec == rec then
		return
	end
	if switching then
		setPromptText(dialog.Rec, "Talk")
	end
	dialog.Open = true
	dialog.Rec = rec
	dialog.Lines = lines
	talkedTo[rec.Id] = true
	refreshBadge(rec)
	setPromptText(rec, "Next")

	local def = rec.Def or {}
	local accent = rec.Accent or C.Gold
	UI.Name.Text = def.Name or rec.Model:GetAttribute("NpcName") or rec.Id
	UI.Title.Text = def.Title or rec.Model:GetAttribute("Title") or ""
	-- (kit B U9-9) the NPC's colour by role: on the portrait's lip (the ground it stands on), nothing glossy
	if UI.PortraitLip then
		UI.PortraitLip.BackgroundColor3 = accent
	end
	setPortrait(rec)
	layoutDialog()
	layoutTimer = 0
	checkTimer = 0
	refreshTargets()
	showLine(1)
	if not switching then
		slideTo(true)
		playSfx("DialogOpen")
		dialog.Greet = (dialog.Greet or 0) + 1
		local greet = dialog.Greet
		task.delay(GREET_DELAY, function()
			if dialog.Open and dialog.Rec == rec and dialog.Greet == greet then
				playVoice(rec, "Greet")
			end
		end)
	end
	ensureLoop()
end

function NpcController.Open(npcId)
	for _, rec in ipairs(recs) do
		if rec.Id == npcId then
			openRec(rec)
			return true
		end
	end
	return false
end

function NpcController.Close()
	if not dialog.Open then
		return
	end
	local rec = dialog.Rec
	dialog.Open = false
	dialog.Rec = nil
	dialog.Typing = false
	setPromptText(rec, "Talk")
	if dialog.Viewport then
		pcall(dialog.Viewport.Destroy)
		dialog.Viewport = nil
	end
	slideTo(false)
	setVitalsOff(false)
	refreshTargets()
end

-- Next: finish the current line, or go to the next one (wrapping to the first).
function NpcController.Advance()
	if not dialog.Open then
		return
	end
	if dialog.Typing then
		finishTyping()
	else
		showLine(dialog.Index + 1)
		playSfx("DialogNext")
		-- (the NPC's wordless reaction: Pleased on the last line or a "!" line, Hmm on any other line)
		local lines = dialog.Lines or {}
		if #lines > 0 then
			local last = dialog.Index == #lines
			local excited = string.find(tostring(dialog.Plain or lines[dialog.Index] or ""), "!", 1, true) ~= nil
			playVoice(dialog.Rec, (last or excited) and "Pleased" or "Hmm")
		end
	end
end

function NpcController.IsOpen()
	if dialog.Open and dialog.Rec then
		return true, dialog.Rec.Id
	end
	return false, nil
end

onPrompt = function(prompt, player)
	if player ~= nil and player ~= LocalPlayer then
		return
	end
	if typeof(prompt) ~= "Instance" then
		return
	end
	local rec = recByPrompt(prompt)
	if not rec then
		local id = prompt:GetAttribute("NpcId")
		if type(id) ~= "string" then
			return
		end
		local model = prompt:FindFirstAncestorOfClass("Model")
		while model and model:GetAttribute("NpcId") ~= id do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if not model then
			return
		end
		dialog.PendingOpen = model -- opens as soon as the NPC has fully replicated
		track(model)
		return
	end
	local now = clock
	if lastTrigger[prompt] and now - lastTrigger[prompt] < 0.15 then
		return
	end
	lastTrigger[prompt] = now
	if dialog.Open and dialog.Rec == rec then
		NpcController.Advance()
	else
		openRec(rec)
	end
end

-- Closes the dialog when the player walked away, died or left the lobby.
local function checkDialog()
	if not dialog.Open then
		return
	end
	local rec = dialog.Rec
	local root = localRoot()
	local char = LocalPlayer and LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not rec or not rec.Model.Parent or not root or (humanoid and humanoid.Health <= 0) then
		NpcController.Close()
		return
	end
	if LocalPlayer:GetAttribute(Config.Attr.InMatch) == true then
		NpcController.Close()
		return
	end
	local center = rec.Center
	if center then
		local d = root.Position - center
		if Vector3.new(d.X, 0, d.Z).Magnitude > CLOSE_DISTANCE or math.abs(d.Y) > CLOSE_DISTANCE then
			NpcController.Close()
		end
	end
end

----------------------------------------------------------------------
-- Frame loop
----------------------------------------------------------------------
local function onFrame(dt)
	dt = math.min(tonumber(dt) or 0, 0.25)
	clock = clock + dt
	targetTimer = targetTimer + dt
	if targetTimer >= K.TARGET_REFRESH then
		targetTimer = 0
		refreshTargets()
	end
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or nil
	local root = localRoot()
	stepNpcs(dt, camPos, root and root.Position or nil)

	if dialog.Open then
		stepTypewriter(dt)
		if UI.More and UI.More.Visible then
			UI.More.Position = UDim2.new(1, -10, 1, -6 - math.floor(math.abs(math.sin(clock * 5)) * 4 + 0.5)) -- (whole px steps)
		end
		checkTimer = checkTimer + dt
		if checkTimer >= K.CHECK_EVERY then
			checkTimer = 0
			checkDialog()
		end
		layoutTimer = layoutTimer + dt
		if layoutTimer >= K.LAYOUT_EVERY then
			layoutTimer = 0
			layoutDialog()
		end
	end
end

ensureLoop = function()
	if loopConn then
		return
	end
	loopConn = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(onFrame, dt)
		if not ok then
			warn("[NpcController] frame error: " .. tostring(err))
		end
	end)
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
local function onViewportChanged()
	for _, rec in ipairs(recs) do
		scaleNameplate(rec)
	end
	if dialog.Open then
		layoutDialog()
	end
end

function NpcController.Init()
	if initialized then
		return
	end
	initialized = true
	if not NpcDialog then
		warn("[NpcController] shared/NpcDialog is unavailable: NPC dialogs are disabled")
	end

	local okUi, errUi = pcall(buildDialog)
	if not okUi then
		warn("[NpcController] dialog UI failed: " .. tostring(errUi))
	end

	-- prompts: the service-wide signal (one connection for every NPC)
	local okHook = pcall(function()
		local signal = ProximityPromptService.PromptTriggered
		if signal then
			signal:Connect(function(prompt, player)
				onPrompt(prompt, player)
			end)
			promptServiceHooked = true
		end
	end)
	if not okHook then
		promptServiceHooked = false
	end

	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
		pending[model] = nil
		local rec = byModel[model]
		if rec then
			removeRec(rec)
		end
	end)
	for _, model in ipairs(CollectionService:GetTagged(TAG)) do
		track(model)
	end

	-- readable nameplates on every screen + dialog relayout
	local cameraConn = nil
	local function bindCamera()
		if cameraConn then
			cameraConn:Disconnect()
			cameraConn = nil
		end
		local cam = Workspace.CurrentCamera
		if cam then
			cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
		end
		onViewportChanged()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()

	if LocalPlayer then
		LocalPlayer.CharacterRemoving:Connect(function()
			NpcController.Close()
		end)
		LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if LocalPlayer:GetAttribute(Config.Attr.InMatch) == true then
				NpcController.Close()
			end
		end)
	end
end

return NpcController
