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
-- Modes (rows top to bottom; MaxDistance in studs):
--   "Follower"  own follower:           level + XP                         90
--   "Garden"    own garden pet at home: level + XP                         90
--   "Training"  own training pet:       level + XP + the purple timer "2:10" 90
--   "Unit"      own unit in a battle:   level + HP + SPECIAL + XP          140 (BattleController's BAR_DISTANCE)
--   "Ally"      a teammate's unit:      level + HP (green)                 140
--   "Enemy"     enemy / NPC unit:       level + HP (red)                   140
--   "Other"     other players' pets:    level only                         60
--
-- Looks (World text rule): a pixel-sized BillboardGui (offset UDim2, never studs-scaled text), LightInfluence 0, a
-- compact dark plate 96 px wide at 1080p; "Lv 12" at 22 px bold with a dark stroke; the stars (U+2605) in gold at
-- 18 px; bars 6 px (XP blue, SPECIAL gold, timer purple) and 9 px (HP); every size is scaled with Theme.ScaledSize
-- (screen-height factor, text never under 14 px). The EVOLVE! pill (20 px, gold) sits above the plate and pulses
-- with a reversing tween (the engine animates it; no Lua per frame).
-- Cost: nothing runs per frame. A bar fill is written only when it moved by more than 0.004 (BattleController's
-- rule); a text only when it changed. Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local PetCard = {}
PetCard.__index = PetCard

PetCard.Modes = {
	Follower = { MaxDistance = 90, Xp = true },
	Garden = { MaxDistance = 90, Xp = true },
	Training = { MaxDistance = 90, Xp = true, Timer = true },
	Unit = { MaxDistance = 140, Hp = true, Special = true, Xp = true, OnTop = true },
	Ally = { MaxDistance = 140, Hp = true, OnTop = true },
	Enemy = { MaxDistance = 140, Hp = true, Enemy = true, OnTop = true },
	Other = { MaxDistance = 60 },
}

-- 1080p design pixels (scaled by the screen-height factor at layout time)
local K = {
	WIDTH = 96,
	PAD = 4,
	LEVEL_PX = 22, -- "Lv 12"
	STAR_PX = 18,
	ROW_LEVEL = 24,
	BAR = 6, -- XP / SPECIAL / timer
	HP_BAR = 9,
	GAP = 3,
	TIMER_PX = 18,
	TIMER_TEXT_W = 40,
	PILL_H = 28,
	PILL_PX = 20,
	PILL_GAP = 4,
	FILL_EPS = 0.004,
	PULSE = 0.55, -- seconds per half pulse of the EVOLVE! pill
	PIP = 9, -- Phase 5: a lives pip (px at 1080p)
	PIP_GAP = 3,
}

local C = {
	Plate = Color3.fromRGB(24, 32, 70),
	PlateEdge = Color3.fromRGB(12, 16, 40),
	Track = Color3.fromRGB(10, 14, 34),
	Xp = Color3.fromRGB(98, 172, 246),
	Special = Color3.fromRGB(244, 196, 78),
	SpecialReady = Color3.fromRGB(255, 226, 120),
	HpOwn = Theme.Colors.Health or Color3.fromRGB(92, 206, 128),
	HpEnemy = Color3.fromRGB(236, 88, 100),
	Timer = Color3.fromRGB(176, 120, 240),
	Star = Theme.Colors.Gold or Color3.fromRGB(244, 196, 78),
	Pill = Theme.Buttons.Gold or Color3.fromRGB(244, 190, 70),
	PillGlow = Color3.fromRGB(255, 232, 150),
	Text = Theme.Colors.White,
	Stroke = Theme.Colors.TextStroke or Color3.fromRGB(16, 22, 50),
	Life = Color3.fromRGB(255, 86, 112), -- a lit lives pip
	LifeLost = Color3.fromRGB(58, 64, 96),
}

local STAR = "\226\152\133" -- U+2605 BLACK STAR

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

local function newBar(parent, name, color)
	local back = make("Frame", {
		Name = name,
		BackgroundColor3 = C.Track,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Visible = false,
	}, parent)
	Theme.Corner(back, UDim.new(0, 3))
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
	}, back)
	Theme.Corner(fill, UDim.new(0, 3))
	return { Back = back, Fill = fill, Frac = 0 }
end

local function writeFill(bar, frac)
	frac = clamp01(frac)
	if math.abs(frac - bar.Frac) > K.FILL_EPS or (frac == 0 and bar.Frac ~= 0) or (frac == 1 and bar.Frac ~= 1) then
		bar.Frac = frac
		bar.Fill.Size = UDim2.new(frac, 0, 1, 0)
	end
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
	local plate = make("Frame", {
		Name = "Plate",
		BackgroundColor3 = C.Plate,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, gui)
	Theme.Corner(plate, UDim.new(0, 8))
	local edge = Theme.Stroke(plate, C.PlateEdge, 2, 0.1)
	edge.Name = "Edge"
	self.plate = plate

	local level = make("TextLabel", {
		Name = "Level",
		BackgroundTransparency = 1,
		Text = "Lv 1",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, plate)
	Theme.Style(level, "Display", { Color = C.Text, Stroke = 0.2, StrokeColor = C.Stroke })
	Theme.TextOutline(level, 2, C.Stroke, 0)
	self.levelLabel = level
	-- Phase 5: the lives pips (frames, no text) right of the level; hidden until SetLives
	local pips = make("Frame", { Name = "Lives", BackgroundTransparency = 1, Visible = false }, plate)
	self.pipsFrame, self.pips = pips, {}

	-- the evolution stars: a small badge straddling the plate's top-right corner (the level keeps the full width)
	local badge = make("Frame", {
		Name = "StarBadge",
		BackgroundColor3 = C.Plate,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, gui)
	Theme.Corner(badge, UDim.new(0.5, 0))
	local badgeEdge = Theme.Stroke(badge, C.Star, 1.5, 0)
	badgeEdge.Name = "Edge"
	local stars = make("TextLabel", {
		Name = "Stars",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 4,
	}, badge)
	Theme.Style(stars, "Heading", { Color = C.Star, Stroke = 0.2, StrokeColor = C.Stroke })
	Theme.TextOutline(stars, 1.5, C.Stroke, 0)
	self.starsLabel, self.badge = stars, badge

	self.bars = {
		Hp = newBar(plate, "Hp", C.HpOwn),
		Special = newBar(plate, "Special", C.Special),
		Xp = newBar(plate, "Xp", C.Xp),
		Timer = newBar(plate, "Timer", C.Timer),
	}
	local timerText = make("TextLabel", {
		Name = "TimerText",
		BackgroundTransparency = 1,
		Text = "",
		Visible = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, plate)
	Theme.Style(timerText, "Heading", { Color = C.Text, Stroke = 0.2, StrokeColor = C.Stroke })
	Theme.TextOutline(timerText, 2, C.Stroke, 0)
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
	Theme.Style(pill, "Button", { Color = C.Text, Stroke = 0.2, StrokeColor = C.Stroke })
	Theme.TextOutline(pill, 2, C.Stroke, 0)
	Theme.Corner(pill, UDim.new(0.5, 0))
	local glow = Theme.Stroke(pill, C.PillGlow, 3, 0.05)
	glow.Name = "Glow"
	self.pill, self.pillGlow = pill, glow
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
function PetCard:_layout()
	local m = PetCard.Modes[self.mode]
	local gui = self.Gui
	gui.MaxDistance = m.MaxDistance
	gui.AlwaysOnTop = m.OnTop == true
	local pad, gap = px(K.PAD, 2), px(K.GAP, 2)
	local w = px(K.WIDTH, 60)
	local inner = w - 2 * pad
	local y = pad
	local rowH = px(K.ROW_LEVEL, 16)
	local levelPx = Theme.ScaledSize(K.LEVEL_PX)
	local starPx = Theme.ScaledSize(K.STAR_PX)
	local hasStars = self.stage > 0
	self.levelLabel.TextSize = levelPx
	self.levelLabel.Position = UDim2.fromOffset(pad, y)
	self.levelLabel.Size = UDim2.fromOffset(inner, rowH)
	-- Phase 5 lives pips: the level takes the left part of the row, the pips the right
	local nPips = self.lives ~= nil and self.livesMax or 0
	self.pipsFrame.Visible = nPips > 0
	if nPips > 0 then
		local pip, pgap = px(K.PIP, 5), px(K.PIP_GAP, 2)
		local pw = nPips * pip + (nPips - 1) * pgap
		self.levelLabel.Size = UDim2.fromOffset(inner - pw - gap, rowH)
		self.pipsFrame.Position = UDim2.fromOffset(pad + inner - pw, y + math.floor((rowH - pip) / 2))
		self.pipsFrame.Size = UDim2.fromOffset(pw, pip)
		for i = 1, math.max(nPips, #self.pips) do
			local p = self.pips[i]
			if i <= nPips then
				if not p then
					p = make("Frame", { Name = "Pip" .. i, BorderSizePixel = 0, BackgroundColor3 = C.Life }, self.pipsFrame)
					Theme.Corner(p, UDim.new(0.5, 0))
					local edge = Theme.Stroke(p, C.Stroke, 1.5, 0)
					edge.Name = "Edge"
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
	y = y + rowH + gap

	local bars = self.bars
	local function place(bar, on, h)
		bar.Back.Visible = on
		if on then
			bar.Back.Position = UDim2.fromOffset(pad, y)
			bar.Back.Size = UDim2.fromOffset(inner, h)
			y = y + h + gap
		end
	end
	place(bars.Hp, m.Hp == true, px(K.HP_BAR, 4))
	bars.Hp.Fill.BackgroundColor3 = m.Enemy and C.HpEnemy or C.HpOwn
	place(bars.Special, m.Special == true, px(K.BAR, 3))
	place(bars.Xp, m.Xp == true, px(K.BAR, 3))
	-- training timer: the bar on the left, "2:10" on the right of the same row
	local timerOn = m.Timer == true
	bars.Timer.Back.Visible = timerOn
	self.timerLabel.Visible = timerOn
	if timerOn then
		local tpx = Theme.ScaledSize(K.TIMER_PX)
		local textW = px(K.TIMER_TEXT_W, 30)
		local th = tpx + 2
		local barH = px(K.BAR, 3)
		bars.Timer.Back.Position = UDim2.fromOffset(pad, y + math.floor((th - barH) / 2))
		bars.Timer.Back.Size = UDim2.fromOffset(inner - textW - gap, barH)
		self.timerLabel.TextSize = tpx
		self.timerLabel.Position = UDim2.fromOffset(w - pad - textW, y)
		self.timerLabel.Size = UDim2.fromOffset(textW, th)
		y = y + th + gap
	end
	local plateH = y - gap + pad

	-- the row above the plate: the EVOLVE! pill (left) and the star badge (right); the billboard grows upwards and
	-- the plate keeps the bottom. A badge alone dips 3 px into the plate's top edge, like a tab.
	local top = 0
	local pill = self.pill
	local badge = self.badge
	local bw, bh = 0, 0
	if hasStars then
		bh = starPx + 4
		bw = starPx * self.stage + px(10, 6)
		self.starsLabel.TextSize = starPx
		badge.Size = UDim2.fromOffset(bw, bh)
	end
	badge.Visible = hasStars
	if self.ready then
		local ph = px(K.PILL_H, 22)
		top = ph + px(K.PILL_GAP, 2)
		pill.TextSize = Theme.ScaledSize(K.PILL_PX)
		pill.Size = UDim2.fromOffset(w, ph)
		pill.Position = UDim2.fromOffset(0, 0)
	end
	if hasStars then
		local dip = math.min(3, bh - 2)
		badge.Position = UDim2.fromOffset(w - bw - px(6, 3), top)
		top = top + bh - dip
	end
	pill.Visible = self.ready
	self.plate.Position = UDim2.fromOffset(0, top)
	self.plate.Size = UDim2.fromOffset(w, plateH)
	gui.Size = UDim2.fromOffset(w, top + plateH)
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
	if level ~= self.level then
		self.level = level
		self.levelLabel.Text = "Lv " .. tostring(level)
	end
	local relayout = false
	if stage ~= self.stage then
		self.stage = stage
		self.starsLabel.Text = stage >= 2 and (STAR .. STAR) or (stage == 1 and STAR or "")
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
		self.bars.Special.Fill.BackgroundColor3 = ready and C.SpecialReady or C.Special
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
