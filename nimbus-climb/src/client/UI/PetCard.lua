-- PetCard (client UI): the small floating card above a pet (ARCHITECTURE_V3.md "Phase 4 build contract" 3.9).
-- One shared builder for every pet card of the game: PetController (followers), BattleController (battle units)
-- and HomeFx (garden / training pets at home) all draw their cards with it.
--
--   local card = PetCard.New(adornee, mode, heightStuds[, opts]) -> card
--       adornee      the BasePart the card floats over (a pet model's PrimaryPart); may be nil (set it later)
--       mode         one of PetCard.Modes (below); unknown -> "Follower"
--       heightStuds  studs above the adornee's centre (default 2.2), e.g. half the pet's height + 0.6
--       opts         optional { Parent = Instance (default: the local PlayerGui, so the EVOLVE pill can be tapped;
--                    without one the adornee), OnEvolve = function() (tap on the EVOLVE! pill), Name = string }
--   card:SetLevel(level, stage, ready)   "Lv 12", a gold star per evolution stage (0 / 1 / 2: none, a star, two
--                                        stars), ready = true shows the pulsing gold "EVOLVE!" pill (an Active button)
--   card:SetXp(frac)                     XP bar fill 0..1 (blue)
--   card:SetHp(frac)                     HP bar fill 0..1 (green on own / ally pets, red on enemies)
--   card:SetSpecial(frac, ready)         SPECIAL bar fill 0..1 (gold; brighter when ready)
--   card:SetTimer(frac, text)            training timer bar (purple) + its text, e.g. (0.4, "2:10")
--   card:SetLives(n, max)                Phase 5 (battle fighters): `max` small pips right of the level, `n` of them
--                                        lit (red hearts' colour), the rest dark; SetLives(nil) hides them
--   card:SetMode(mode)                   switches the rows / distance of the card (same instance, laid out again)
--   card:Destroy()                       removes the card (safe to call twice)
--   Extras (general helpers for the callers):
--   card:SetAdornee(adornee, heightStuds)  follow another part (a rebuilt model) without a new card
--   card:SetShown(shown)                 hide / show the card (BillboardGui.Enabled), e.g. while the owner battles
--   card:SetOnEvolve(fn)                 the EVOLVE! pill's tap handler
--   card.Gui                             the BillboardGui (named "PetCard" unless opts.Name)
--   PetCard.Count()                      cards alive right now (debug / tests)
--   PetCard.Modes                        the mode table below (read-only)
--
-- Modes (rows top to bottom; MaxDistance in studs). (Pitch 2 item 04 B) the Xp / Special flags still say which fractions
-- a mode feeds; only HP and the timer draw a row under the chip:
--   "Follower"  own follower:           the chip                           25 (2026-11-13 owner, was 15; first 90: the
--                                                                          card shows only with the camera close)
--   "Garden"    own garden pet at home: the chip                           90
--   "Training"  own training pet:       the chip + the purple timer "2:10" 90
--   "Unit"      own unit in a battle:   the chip + HP                      140 (BattleController's BAR_DISTANCE)
--   "Ally"      a teammate's unit:      the chip + HP (green)              140
--   "Enemy"     enemy / NPC unit:       the chip + HP (red)                140
--   "Other"     other players' pets:    the chip                           60
--
-- Looks (World text rule): a pixel-sized BillboardGui (offset UDim2, never studs-scaled text), LightInfluence 0.
-- (Pitch 2 item 04_world_ui, the owner's pick B "Stone tags"; owner shots 07 and 05: the navy plaque with a thin bar, its
-- stars plaque on top where the pet's body covered it) the tag is a compact wood chip (Plate: the Wood face, a 2 px
-- WoodDark edge, a 3 px lip, the lit top line), 30 px tall at 1080p and as wide as its row: the gold pixel stars INSIDE it
-- (StarBadge, no plaque of its own, left of the level so they never cover it), then "Lv 12" at 22 px in stone with a
-- dark wood stroke, then the lives pips. Under the chip ONE block row: HP (9 px, 8 blocks) in the modes that have it (the
-- training timer in Training); SPECIAL and XP keep their fractions (SetSpecial / SetXp) but show on the HUD helper cards,
-- not over the pet. The row is max(chip, 96) px wide with the chip centred over it. Every size is scaled with the
-- screen-height factor (Theme.ScaledSize, text never under 14 px). The EVOLVE! pill (20 px, gold) sits above the chip and
-- pulses with a reversing tween (the engine animates it; no Lua per frame).
-- Cost: nothing runs per frame. A bar fill is written only when it moved by more than 0.004 (BattleController's
-- rule); a text only when it changed. Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7b) the evolution stars
local SignKit = require(Shared:WaitForChild("SignKit")) -- (kit-b gate U9 round 3) the bars are the kit's block rows
local CloudUI = require(script.Parent:WaitForChild("CloudUI")) -- ... and the plate, the badge and EVOLVE! kit B blocks
local Sign = Theme.Sign

local PetCard = {}
PetCard.__index = PetCard

PetCard.Modes = {
	Follower = { MaxDistance = 25, Xp = true }, -- own follower only (2026-11-13 owner: 25, was 15; first 90)
	Garden = { MaxDistance = 90, Xp = true },
	Training = { MaxDistance = 90, Xp = true, Timer = true },
	Unit = { MaxDistance = 140, Hp = true, Special = true, Xp = true, OnTop = true },
	Ally = { MaxDistance = 140, Hp = true, OnTop = true },
	Enemy = { MaxDistance = 140, Hp = true, Enemy = true, OnTop = true },
	Other = { MaxDistance = 60 },
}

-- 1080p design pixels (scaled by the screen-height factor at layout time)
local K = {
	WIDTH = 96, -- the HP row's least width (the chip is centred over it)
	LEVEL_PX = 22, -- "Lv 12"
	STAR_PX = 18,
	STAR_GAP = 6, -- px between the stars and "Lv" (look review r0: 4 left 1-2 px of chip at 0.8; the mock's gap is ~7)
	CHIP_H = 26, -- (Pitch 2 item 04 B) the chip's face (30 px with its 2 px edge)
	CHIP_EDGE = 2,
	CHIP_LIP = 3,
	CHIP_PAD = 7, -- px from the face's side to the stars / the level (9 from the edge's outside)
	ROW_GAP = 4, -- px between the chip's edge and the HP row (y 36 of the mock-up)
	BAR = 8, -- the timer (kit-b gate U9 round 3: block rows, a 1 px wood edge and lip round a face)
	HP_BAR = 9,
	BLOCKS = { Hp = 8, Special = 8, Xp = 8, Timer = 4 }, -- one cell module: 8 across the plate (HP an eighth each), 4 in the timer's shorter row
	GAP = 3,
	TIMER_PX = 18,
	TIMER_TEXT_W = 40,
	PILL_H = 28,
	PILL_PX = 20,
	PILL_W = 108, -- (Pitch 2 item 04 B) the EVOLVE! plank's least width: the word in FredokaOne at PILL_PX (~89 px) + its room
	PILL_GAP = 4,
	FILL_EPS = 0.004,
	PULSE = 0.55, -- seconds per half pulse of the EVOLVE! pill
	PIP = 9, -- Phase 5: a lives pip (px at 1080p)
	PIP_GAP = 3,
}

-- (kit-b gate U9 round 3: the old neon card, rounded with smooth bars) the kit's navy sign plate and its role colours: each
-- bar's lit blocks in its role face and lip, EVOLVE! the gold plank, the pips square
local C = {
	Xp = Sign.Sky, XpLip = Sign.SkyLip,
	Special = Sign.Gold, SpecialLip = Sign.GoldLip,
	SpecialReady = Sign.GoldLight, SpecialReadyLip = Sign.GoldLip,
	HpOwn = Sign.Grass, HpOwnLip = Sign.GrassLip,
	HpEnemy = Sign.Red, HpEnemyLip = Sign.RedLip,
	Timer = Sign.Violet, TimerLip = Sign.VioletLip,
	Star = Sign.Gold,
	Pill = Sign.Gold,
	PillGlow = Sign.GoldLight, -- the pulse: the gold face to its light step and back (no glow ring)
	-- (Pitch 2 item 04 B) the wood chip: its face, edge and lip; "Lv" in stone with a dark wood stroke
	Chip = Sign.Wood,
	ChipEdge = Sign.WoodDark,
	ChipLip = Sign.WoodDark,
	Text = Sign.Stone,
	Stroke = Sign.WoodDark,
	Life = Sign.Red, -- a lit lives pip
	LifeLost = Sign.WoodDark,
	PipEdge = Sign.Text,
}

local STAR_ICON = "star" -- (kit-b U7b) the evolution stars are PixelIcons (they were U+2605)

local live = 0

----------------------------------------------------------------------
-- helpers
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

local function clamp01(x)
	x = tonumber(x) or 0
	if x ~= x then
		return 0
	end
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

-- a 1080p pixel size on this screen (bars / gaps: never below `minPx`)
local function px(base, minPx)
	local f = 1
	local ok, factor = pcall(Theme.ScreenFactor)
	if ok and type(factor) == "number" then
		f = factor
	end
	return math.max(minPx or 1, math.floor(base * f + 0.5))
end

local function defaultParent(adornee)
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if pg then
		return pg
	end
	return adornee
end

-- (kit-b gate U9 round 3) a bar is the kit's block row (SignKit.FitBlocks: whole-px blocks in a 1 px wood edge with
-- their lip, lit in the role's face and lip, the rest stone). The holder keeps the bar's name and the exact fraction in
-- its attribute Frac; Ceil lights a block for any part of it (health: a pet that lives shows one)
local function newBar(parent, name, color, lip, count, ceil)
	local back = make("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, parent)
	back:SetAttribute("Frac", 0)
	local row = SignKit.FitBlocks(back, { Count = count, Fill = color, FillLip = lip, Weight = "Micro", Size = UDim2.fromScale(1, 1) })
	return { Back = back, Row = row, Count = count, Ceil = ceil == true, Frac = 0 }
end

local function lightBar(bar)
	local n, f = bar.Count, bar.Frac
	local k = bar.Ceil and math.ceil(f * n - 1e-6) or math.floor(f * n + 1e-6)
	SignKit.FillBlocks(bar.Row, k)
end

local function writeFill(bar, frac)
	frac = clamp01(frac)
	if math.abs(frac - bar.Frac) > K.FILL_EPS or (frac == 0 and bar.Frac ~= 0) or (frac == 1 and bar.Frac ~= 1) then
		bar.Frac = frac
		bar.Back:SetAttribute("Frac", frac)
		lightBar(bar)
	end
end

-- a bar's lit colours (the enemy's red health, SPECIAL ready)
local function paintBar(bar, color, lip)
	SignKit.SetBlockCount(bar.Row, bar.Count, color, lip)
	lightBar(bar)
end

----------------------------------------------------------------------
-- construction + layout
----------------------------------------------------------------------
function PetCard.New(adornee, mode, heightStuds, opts)
	opts = type(opts) == "table" and opts or {}
	local self = setmetatable({}, PetCard)
	self.mode = PetCard.Modes[mode] and mode or "Follower"
	self.height = tonumber(heightStuds) or 2.2
	self.level, self.stage, self.ready = nil, 0, false
	self.timerText = nil
	self.lives, self.livesMax = nil, 0
	self.onEvolve = opts.OnEvolve
	self.destroyed = false

	local gui = make("BillboardGui", {
		Name = type(opts.Name) == "string" and opts.Name or "PetCard",
		Adornee = (typeof(adornee) == "Instance") and adornee or nil,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		Active = true,
		ClipsDescendants = false,
		StudsOffset = Vector3.new(0, self.height, 0),
	})
	self.Gui = gui
	-- (Pitch 2 item 04 B; it was the navy sign plate) the wood chip: square, a mitred 2 px dark wood edge, its 3 px lip,
	-- the lit top line only (Finish "Lean": a small world tag's instance budget)
	local plate = make("Frame", {
		Name = "Plate",
		BorderSizePixel = 0,
		ZIndex = 1,
	}, gui)
	CloudUI.SignBlock(plate, "Stone", {
		Face = C.Chip, Edge = C.ChipEdge, Lip = C.ChipLip, EdgePx = K.CHIP_EDGE, LipPx = K.CHIP_LIP, Pad = false, Finish = "Lean",
	})
	self.plate = plate

	local level = make("TextLabel", {
		Name = "Level",
		BackgroundTransparency = 1,
		Text = "Lv 1",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 2,
	}, plate)
	Theme.Style(level, "Display", { Color = C.Text, Outline = "World", OutlineThickness = 2, OutlineColor = C.Stroke }) -- over the world: ONE outline (kit-b U6)
	self.levelLabel = level
	-- Phase 5: the lives pips (frames, no text) right of the level; hidden until SetLives
	local pips = make("Frame", { Name = "Lives", BackgroundTransparency = 1, Visible = false }, plate)
	self.pipsFrame, self.pips = pips, {}

	-- the evolution stars: (Pitch 2 item 04 B; they were a navy plaque straddling the corner, covered by the pet's body)
	-- inside the chip, left of the level, with no plaque of their own
	local badge = make("Frame", {
		Name = "StarBadge",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, gui)
	local stars = make("TextLabel", {
		Name = "Stars",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 4,
	}, badge)
	Theme.Style(stars, "Heading", { Color = C.Star, Outline = "World", OutlineThickness = 1.5, OutlineColor = C.Stroke }) -- over the world: ONE outline (kit-b U6)
	self.starsLabel, self.badge = stars, badge

	self.bars = {
		Hp = newBar(plate, "Hp", C.HpOwn, C.HpOwnLip, K.BLOCKS.Hp, true),
		Special = newBar(plate, "Special", C.Special, C.SpecialLip, K.BLOCKS.Special),
		Xp = newBar(plate, "Xp", C.Xp, C.XpLip, K.BLOCKS.Xp),
		Timer = newBar(plate, "Timer", C.Timer, C.TimerLip, K.BLOCKS.Timer),
	}
	local timerText = make("TextLabel", {
		Name = "TimerText",
		BackgroundTransparency = 1,
		Text = "",
		Visible = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, plate)
	Theme.Style(timerText, "Heading", { Color = C.Text, Outline = "World", OutlineThickness = 2, OutlineColor = C.Stroke }) -- over the world: ONE outline (kit-b U6)
	self.timerLabel = timerText

	local pill = make("TextButton", {
		Name = "Evolve",
		Text = "EVOLVE!",
		BackgroundColor3 = C.Pill,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Active = true,
		Visible = false,
		Selectable = true,
	}, gui)
	Theme.Style(pill, "Button", { Color = Sign.Text }) -- (gate U9 round 3) brown ink on the gold plank, as the kit's planks
	CloudUI.SignBlock(pill, "Selected", { EdgePx = 2, LipPx = 3, Pad = false }) -- a square gold plank (no pill, no glow ring)
	self.pill = pill
	pill.Activated:Connect(function()
		if self.destroyed or not self.ready then
			return
		end
		local fn = self.onEvolve
		if type(fn) == "function" then
			local ok, err = pcall(fn)
			if not ok then
				warn("[PetCard] EVOLVE handler failed: " .. tostring(err))
			end
		end
	end)

	self:_layout()
	gui.Parent = (typeof(opts.Parent) == "Instance" and opts.Parent) or defaultParent(adornee)
	live = live + 1
	return self
end

-- lays the rows out for the current mode / ready state (called on SetMode / SetLevel changes, never per frame)
-- (Pitch 2 item 04 B) top to bottom: the EVOLVE! pill, the wood chip (stars, "Lv", lives pips in one row), the HP row /
-- the timer row under it. The chip is centred over the row; the billboard holds the chip's edge (it is drawn outside the
-- face) and grows upwards, the bottom row keeps the bottom.
function PetCard:_layout()
	local m = PetCard.Modes[self.mode]
	local gui = self.Gui
	gui.MaxDistance = m.MaxDistance
	gui.AlwaysOnTop = m.OnTop == true
	local gap = px(K.GAP, 2)
	local edge = K.CHIP_EDGE
	local chipH = px(K.CHIP_H, 18)
	local rowH = chipH - K.CHIP_LIP -- the chip's row sits above its lip
	local inset = px(K.CHIP_PAD, 4)
	local levelPx = Theme.ScaledSize(K.LEVEL_PX)
	local starPx = Theme.ScaledSize(K.STAR_PX)
	local hasStars = self.stage > 0
	self.levelLabel.TextSize = levelPx

	-- the chip's row, left to right (x in the face)
	local x = inset
	local badge = self.badge
	local bw, bh = 0, 0
	if hasStars then
		-- (look review r0: at 0.8 starPx 14 snapped to 9 px stars of 1 px cells beside an 18 px "Lv") the stars snap to the
		-- largest multiple of 9 within the chip's row and the level's px: 18 at 0.8 and 1080p, 27 at 1.25
		local snap = math.max(9, 9 * math.floor(math.min(rowH, math.max(starPx, levelPx)) / 9))
		local cell = math.floor(snap / 9)
		bw = self.stage * snap + (self.stage - 1) * cell
		bh = snap
		self.starsLabel.TextSize = starPx
		badge.Size = UDim2.fromOffset(bw, bh)
		-- (kit-b U7b) one PixelIcon star per stage, centred, at the multiple of 9 that fits starPx
		PixelIcon.Lead(self.starsLabel, STAR_ICON, { Count = self.stage, Of = self.stage, Px = snap })
		x = x + bw + px(K.STAR_GAP, 3)
	end
	badge.Visible = hasStars
	local ring = 2 -- the level's outline on both sides
	local levelW = math.ceil(Theme.MeasureLabel(self.levelLabel, self.levelLabel.Text, levelPx).X) + 2 * ring
	self.levelLabel.Position = UDim2.fromOffset(x, 0)
	self.levelLabel.Size = UDim2.fromOffset(levelW, rowH)
	x = x + levelW
	-- Phase 5 lives pips: right of the level, in the chip
	local nPips = self.lives ~= nil and self.livesMax or 0
	self.pipsFrame.Visible = nPips > 0
	if nPips > 0 then
		local pip, pgap = px(K.PIP, 5), px(K.PIP_GAP, 2)
		local pw = nPips * pip + (nPips - 1) * pgap
		x = x + gap
		self.pipsFrame.Position = UDim2.fromOffset(x, math.floor((rowH - pip) / 2))
		self.pipsFrame.Size = UDim2.fromOffset(pw, pip)
		x = x + pw
		for i = 1, math.max(nPips, #self.pips) do
			local p = self.pips[i]
			if i <= nPips then
				if not p then
					p = make("Frame", { Name = "Pip" .. i, BorderSizePixel = 0, BackgroundColor3 = C.Life, ZIndex = 2 }, self.pipsFrame)
					local edgeS = Theme.Stroke(p, C.PipEdge, 1, 0) -- (gate U9 round 3) a square pip in a 1 px edge
					edgeS.Name = "Edge"
					edgeS.LineJoinMode = Enum.LineJoinMode.Miter
					self.pips[i] = p
				end
				p.Visible = true
				p.Size = UDim2.fromOffset(pip, pip)
				p.Position = UDim2.fromOffset((i - 1) * (pip + pgap), 0)
				p.BackgroundColor3 = (i <= self.lives) and C.Life or C.LifeLost
			elseif p then
				p.Visible = false
			end
		end
	end
	local chipW = x + inset -- the face
	local outerW = chipW + 2 * edge

	-- the row under the chip: HP (the modes that have it), the training timer; SPECIAL and XP draw nothing here
	local bars = self.bars
	local hpOn, timerOn = m.Hp == true, m.Timer == true
	local w = outerW
	if hpOn or timerOn then
		w = math.max(outerW, px(K.WIDTH, 60))
	end
	-- (Pitch 2 item 04 B, the gate render) while EVOLVE! shows, the card is at least its word wide plus the plank's room
	-- (the chip stays centred): a lone "Lv 20" chip is narrower than the word, which ran out of its plank
	if self.ready then
		local word = Theme.Measure(self.pill.Text, "Button", Theme.ScaledSize(K.PILL_PX)).X
		w = math.max(w, math.ceil(word) + 2 * inset + 2 * edge, px(K.PILL_W, 80))
	end
	local chipX = math.floor((w - outerW) / 2) + edge -- the face's left in the billboard
	bars.Special.Back.Visible = false
	bars.Xp.Back.Visible = false
	if bars.Hp.Enemy ~= (m.Enemy == true) then
		bars.Hp.Enemy = m.Enemy == true
		paintBar(bars.Hp, m.Enemy and C.HpEnemy or C.HpOwn, m.Enemy and C.HpEnemyLip or C.HpOwnLip)
	end
	-- the rows are the chip's children, placed from the face's corner: under its edge, as wide as the billboard
	local rowY = chipH + edge + px(K.ROW_GAP, 2)
	local belowH = 0
	bars.Hp.Back.Visible = hpOn
	if hpOn then
		local hh = px(K.HP_BAR, 6)
		bars.Hp.Back.Position = UDim2.fromOffset(-chipX, rowY)
		bars.Hp.Back.Size = UDim2.fromOffset(w, hh)
		belowH = rowY + hh - chipH - edge
		rowY = rowY + hh + gap
	end
	bars.Timer.Back.Visible = timerOn
	self.timerLabel.Visible = timerOn
	if timerOn then
		local tpx = Theme.ScaledSize(K.TIMER_PX)
		local textW = px(K.TIMER_TEXT_W, 30)
		local th = tpx + 2
		local barH = px(K.BAR, 5)
		bars.Timer.Back.Position = UDim2.fromOffset(-chipX, rowY + math.floor((th - barH) / 2))
		bars.Timer.Back.Size = UDim2.fromOffset(w - textW - gap, barH)
		self.timerLabel.TextSize = tpx
		self.timerLabel.Position = UDim2.fromOffset(w - chipX - textW, rowY)
		self.timerLabel.Size = UDim2.fromOffset(textW, th)
		belowH = rowY + th - chipH - edge
	end

	-- the row above the chip: the EVOLVE! pill
	local top = 0
	local pill = self.pill
	if self.ready then
		local ph = px(K.PILL_H, 22)
		top = ph + px(K.PILL_GAP, 2)
		pill.TextSize = Theme.ScaledSize(K.PILL_PX)
		pill.Size = UDim2.fromOffset(w, ph)
		pill.Position = UDim2.fromOffset(0, 0)
	end
	pill.Visible = self.ready
	self.plate.Position = UDim2.fromOffset(chipX, top + edge)
	self.plate.Size = UDim2.fromOffset(chipW, chipH)
	if hasStars then
		badge.Position = UDim2.fromOffset(chipX + inset, top + edge + math.floor((rowH - bh) / 2))
	end
	gui.Size = UDim2.fromOffset(w, top + edge + chipH + edge + belowH)
	self:_pulse(self.ready)
end

function PetCard:_pulse(on)
	if on and not self.tween then
		local ok, tween = pcall(function()
			local info = TweenInfo.new(K.PULSE, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			return TweenService:Create(self.pill, info, { BackgroundColor3 = C.PillGlow })
		end)
		if ok and tween then
			self.tween = tween
			pcall(tween.Play, tween)
		end
	elseif not on and self.tween then
		pcall(self.tween.Cancel, self.tween)
		self.tween = nil
		self.pill.BackgroundColor3 = C.Pill
	end
end

----------------------------------------------------------------------
-- public setters (cheap: each writes only what changed)
----------------------------------------------------------------------
function PetCard:SetLevel(level, stage, ready)
	if self.destroyed then
		return
	end
	level = math.max(1, math.floor(tonumber(level) or 1))
	stage = math.floor(tonumber(stage) or 0)
	if stage < 0 then
		stage = 0
	elseif stage > 2 then
		stage = 2
	end
	ready = ready == true
	local relayout = false
	if level ~= self.level then
		-- (Pitch 2 item 04 B) the chip is as wide as its row: a level with more digits widens it
		relayout = #tostring(level) ~= #tostring(self.level or 1)
		self.level = level
		self.levelLabel.Text = "Lv " .. tostring(level)
	end
	if stage ~= self.stage then
		self.stage = stage
		self.starsLabel.Text = "" -- (kit-b U7b) the layout draws the stars (PixelIcon.Lead, Count = the stage)
		relayout = true
	end
	if ready ~= self.ready then
		self.ready = ready
		relayout = true
	end
	if relayout then
		self:_layout()
	end
end

function PetCard:SetXp(frac)
	if not self.destroyed then
		writeFill(self.bars.Xp, frac)
	end
end

function PetCard:SetHp(frac)
	if not self.destroyed then
		writeFill(self.bars.Hp, frac)
	end
end

function PetCard:SetSpecial(frac, ready)
	if self.destroyed then
		return
	end
	writeFill(self.bars.Special, frac)
	ready = ready == true
	if ready ~= self.specialReady then
		self.specialReady = ready
		paintBar(self.bars.Special, ready and C.SpecialReady or C.Special, ready and C.SpecialReadyLip or C.SpecialLip)
	end
end

function PetCard:SetTimer(frac, text)
	if self.destroyed then
		return
	end
	writeFill(self.bars.Timer, frac)
	text = text ~= nil and tostring(text) or ""
	if text ~= self.timerText then
		self.timerText = text
		self.timerLabel.Text = text
	end
end

-- Phase 5: a fighter's lives (pips right of the level); n = nil hides them. Re-lays out only when they change.
function PetCard:SetLives(n, maxN)
	if self.destroyed then
		return
	end
	n = tonumber(n)
	if n ~= nil then
		n = math.max(0, math.floor(n))
		maxN = math.max(n, math.min(5, math.floor(tonumber(maxN) or 3)))
	else
		maxN = 0
	end
	if n == self.lives and maxN == self.livesMax then
		return
	end
	local relayout = maxN ~= self.livesMax or (n == nil) ~= (self.lives == nil)
	self.lives, self.livesMax = n, maxN
	if relayout then
		self:_layout()
	elseif n ~= nil then
		for i, p in ipairs(self.pips) do
			p.BackgroundColor3 = (i <= n) and C.Life or C.LifeLost
		end
	end
end

function PetCard:SetMode(mode)
	if self.destroyed or not PetCard.Modes[mode] or mode == self.mode then
		return
	end
	self.mode = mode
	self:_layout()
end

function PetCard:SetAdornee(adornee, heightStuds)
	if self.destroyed then
		return
	end
	local gui = self.Gui
	local part = (typeof(adornee) == "Instance") and adornee or nil
	if gui.Adornee ~= part then
		gui.Adornee = part
	end
	local h = tonumber(heightStuds)
	if h and math.abs(h - self.height) > 0.01 then
		self.height = h
		gui.StudsOffset = Vector3.new(0, h, 0)
	end
end

function PetCard:SetShown(shown)
	if self.destroyed then
		return
	end
	shown = shown ~= false
	if self.Gui.Enabled ~= shown then
		self.Gui.Enabled = shown
	end
end

function PetCard:SetOnEvolve(fn)
	self.onEvolve = fn
end

function PetCard:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	live = live - 1
	if self.tween then
		pcall(self.tween.Cancel, self.tween)
		self.tween = nil
	end
	local gui = self.Gui
	self.Gui = nil
	if gui then
		pcall(gui.Destroy, gui)
	end
end

function PetCard.Count()
	return live
end

return PetCard
