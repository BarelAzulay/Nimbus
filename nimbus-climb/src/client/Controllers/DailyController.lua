-- DailyController (client, store 2026-11-04; spec 5.2 / 8 "Gifts" / 13b.3-4): the Gifts button, its pip and ring, and the
-- daily-gifts window (the 7-day streak strip and the play-time rows).
--
--   DailyController.Init()
--   DailyController.Open(args)    args = { Tab = "Daily" | "Play" } (nil: Daily, or Play when only a play tier is ready)
--   DailyController.Close()
--   DailyController.IsOpen() -> bool
--   DailyController.State() -> the last DailyState payload | nil
--   DailyController.PipShown() -> bool
--
-- Data: DailyState (server -> client) is the only source (DailyService builds it; nothing here decides a reward):
--   { Loading = bool (provisional: no CLAIM), Streak, Paid, Weeks, Pet, ReadyAt (unix), KeepUntil (unix), Cell (1..7: the NEXT
--     cell), Vip = bool, StepBack = n (the last claim's step-back), Days = { { Kind = "Cash" | "Tokens" | "Gems" | "Pet",
--     Amount = n | nil, PetId = "week_wisp" | nil, Claimed, Today } x7 }, Play = { Seconds, DayEnds (unix), Active = bool,
--     Tiers = { { Min, Kind, Amount, PetId, Claimed, Ready } x7 } }, ServerNow (unix) }
--   Amounts are the server's resolved numbers (13b.3). Countdowns use ReadyAt / DayEnds - workspace:GetServerTimeNow().
--   A claim fires DailyRequest("Claim") / DailyRequest("ClaimPlay", tier) (1 s client gap per action); the toast is the
--   server's. The tutorial gate reads TutorialState (Done, or Step >= the index of the "spin" step).
--
-- Screen: ScreenGui "NimbusDaily" (DisplayOrder 19 like the Store and the Pets window: they never overlap, each Open fires
-- MenuController.WindowOpened(id) and each closes on any other id; IgnoreGuiInset = false: the HUD attributes are gui px).
--   * TextButton "GiftsButton": round, x = NimbusHud.TopRightLeft - 8 - size, y = 6 (gui px); 56 px at 1080p (x the screen
--     factor), 44 px on a phone; hidden with the strips (InMatch / InBattle, or no top-right strips); re-laid out on the HUD's
--     TopRightLeft / TopRightBottom signals. Children: the Gifts glyph, Frame "Pip" (a 10 px Neon.Red dot: a claim or a play
--     tier is ready, >= Config.Daily.PipDelaySeconds after the last CharacterAdded, the tutorial at its spin step or later),
--     a 0.4 s shake when a play tier becomes Ready in a payload that is not the first after a join / Loading one.
--     Frame "Ring" (around the button, attribute Fill = Play.Seconds / the next tier's seconds): two half arcs (RingRight /
--     RingLeft, each a clipped circle whose UIStroke carries a stepped UIGradient), Neon.Gold, 40 % transparent while
--     Play.Active == false.
--   * Frame "DailyHolder" (UIScale "Scale") > NeonKit.Card "DailyWindow": PC 760x420 design px at the screen factor, phone
--     560x300 at scale 1; under the button with the right edges aligned (moved up only as far as the screen needs). Title
--     row: Tab_Daily ("Daily"), Tab_Play ("Play time"), CloseButton. DailyPage: Header "Day 3 of 7 · Week 2", VipChip
--     "VIP x2", Cells > Cell1..7 (Day, Art (glyph or the pet's PetViewport), Amount, Dim, Check; attributes Claimed / Today /
--     Pulsing: today's card is Neon.Gold and its border pulses), Footer (ClaimButton "CLAIM!" | Countdown "Next gift in 4h
--     12m" + Keep "Come back tomorrow to keep your streak!"), WeekBanner. PlayPage: Header "47 min played today · Resets in
--     5h" or "Paused: move around to keep counting!" (Body 15, Neon.Gold), Rows > Row1..7 (Label "10 min · +$200", Claim
--     "CLAIM", ToGo "13 min to go", Check). Fx: the week's Rainbow Sweep and 24 Confetti frames (both skipped on Low).
--   * A grown claimed set pops the cell / row (1.15 -> 1, 0.25 s) with SoundFx "Reward"; a Streak that grew onto a multiple of
--     7: the sweep, the confetti, "WEEK DONE! Week Wisp is yours!", SoundFx "DailyWeek"; StepBack > 0: the side hint
--     "Welcome back! You stepped back n day(s). Keep going!" once per claim (MenuController.Hint).
--   * Closes on X, Esc, gamepad B (bound only while open), InMatch / InBattle, and any other WindowOpened id.
-- Art: glyph fallbacks (NeonKit.Icon: "Gifts", "Cash", "Tokens", "Gems"); Config.Icons swaps in the uploaded images later.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TutorialSteps = require(Shared:WaitForChild("TutorialSteps"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))
local SoundFx = require(Client:WaitForChild("SoundFx"))
local GraphicsQuality = require(Client:WaitForChild("GraphicsQuality"))

local DailyController = {}

local K = {
	DISPLAY_ORDER = 19,
	GAP = 8, -- the button's gap to the strips, the window's gap under the button
	TOP = 6, -- the button's y (gui px)
	BTN = 56, -- the button at 1080p (x the screen factor) ...
	BTN_MIN = 44, -- ... never below this
	SMALL = 500, -- the smaller screen side at most this = a phone
	PIP = 10,
	RING_PAD = 4, -- the ring sits this far outside the button
	RING_STROKE = 3,
	RING_DIM = 0.4, -- the ring's transparency while the play clock is paused
	SHAKE = { 4, -4, 3, -3, 2, -2, 1, 0 }, -- px offsets, one per SHAKE_STEP (0.4 s)
	SHAKE_STEP = 0.05,
	CLAIM_GAP = 1, -- seconds between two sends of one action
	POP = 1.15,
	POP_TIME = 0.25,
	WEEK_SECONDS = 4.5, -- the week banner stays this long
	CONFETTI = 24,
	CONFETTI_TIME = 1.6,
	PULSE = 0.55, -- today's border fades to this and back, once a second
	EDGE = 4, -- the window keeps this far from the screen edges
	BACK_ACTION = "NimbusDailyBack",
	-- the window in design px: PC at the screen factor, Phone at scale 1 (texts >= 15)
	PC = {
		W = 760, H = 420, Pad = 20, TitleY = 14, TitleH = 44, TabW = { 150, 170 }, TabText = 22, Close = 44,
		HeaderY = 70, HeaderH = 34, HeaderText = 26, ChipW = 120, ChipText = 20,
		CellsY = 112, CellW = 92, CellH = 132, DayText = 17, IconPx = 44, PetPx = 70, AmountText = 20, CheckText = 24,
		FooterY = 258, FooterH = 76, ClaimW = 260, ClaimH = 56, ClaimText = 28, CountText = 22, KeepText = 18,
		BannerY = 344, BannerH = 40, BannerText = 26,
		RowsY = 112, RowH = 38, RowGap = 4, Columns = 1, RowText = 19, RowBtnW = 120, RowBtnH = 34, RowBtnText = 18, ToGoW = 160,
		PausedText = 15,
	},
	PHONE = {
		W = 560, H = 300, Pad = 10, TitleY = 8, TitleH = 40, TabW = { 110, 130 }, TabText = 17, Close = 40,
		HeaderY = 54, HeaderH = 24, HeaderText = 18, ChipW = 84, ChipText = 15,
		CellsY = 82, CellW = 64, CellH = 92, DayText = 15, IconPx = 28, PetPx = 44, AmountText = 15, CheckText = 18,
		FooterY = 180, FooterH = 56, ClaimW = 200, ClaimH = 48, ClaimText = 22, CountText = 17, KeepText = 15,
		BannerY = 250, BannerH = 32, BannerText = 20,
		RowsY = 86, RowH = 46, RowGap = 6, Columns = 2, RowText = 15, RowBtnW = 92, RowBtnH = 40, RowBtnText = 15, ToGoW = 104,
		PausedText = 15,
	},
}
DailyController.K = K

local DOT = "\194\183"
local CHECK = "\226\156\148"
local WHITE = Theme.Colors.White
local GOLD = Theme.Neon.Gold
local INK = Theme.Colors.PanelInk or Color3.fromRGB(8, 10, 28)
local MUTED = Theme.Colors.Muted or Color3.fromRGB(212, 224, 246)

local LocalPlayer = nil
local initialized = false
local U = { Cells = {}, Rows = {} } -- the instances
local S = {
	Open = false,
	Tab = "Daily",
	State = nil, -- the last payload
	Last = nil, -- the last non-Loading payload since the last Loading one (the baseline of pops / shakes / the week)
	Tutorial = nil, -- the last TutorialState payload
	SpawnAt = 0, -- time() of the last CharacterAdded
	LastFire = {},
	Mode = nil, -- "PC" | "Phone" of the built window
	ShakeX = 0,
	ShakeToken = 0,
	StepBackKey = nil,
	BannerUntil = 0,
	Pulse = false,
	BackBound = false,
	Hidden = true,
}
local warned = {}

local function warnOnce(key, err)
	if not warned[key] then
		warned[key] = true
		warn("[DailyController] " .. key .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

local function controller(name)
	local inst = script.Parent:FindFirstChild(name)
	local ok, mod = pcall(function()
		return inst and require(inst)
	end)
	return ok and type(mod) == "table" and mod or nil
end

local function now()
	return workspace:GetServerTimeNow()
end

local function commas(n)
	return Util.Commas(math.floor(tonumber(n) or 0))
end

local function label(name, text, role, size, parent, props)
	local l = Theme.Label(text or "", role, { Size = size, Stroke = 0.5, Outline = 1.5 })
	l.Name = name
	l.TextWrapped = true
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function place(inst, x, y, w, h)
	inst.AnchorPoint = Vector2.new(0, 0)
	inst.Position = UDim2.fromOffset(x, y)
	inst.Size = UDim2.fromOffset(w, h)
end

local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and vp.X >= 2 and vp.Y >= 2 then
		return vp
	end
	return Vector2.new(1920, 1080)
end

-- "4h 12m" / "12m 5s"
local function leftText(seconds)
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	if h > 0 then
		return h .. "h " .. m .. "m"
	end
	return m .. "m " .. (s % 60) .. "s"
end

-- "5h" / "40m"
local function resetText(seconds)
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	if s >= 3600 then
		return math.floor(s / 3600) .. "h"
	end
	return math.max(1, math.ceil(s / 60)) .. "m"
end

local function petName(petId)
	local ok, catalog = pcall(function()
		return require(Shared:WaitForChild("PetCatalog", 5))
	end)
	local def = ok and type(catalog) == "table" and catalog.Get and catalog.Get(petId) or nil
	return (def and def.Name) or "a pet"
end

-- the short amount of a cell ("$1,450", "50", "Week Wisp")
local function cellAmount(entry)
	local kind = entry.Kind
	if kind == "Cash" then
		return "$" .. commas(entry.Amount)
	elseif kind == "Pet" then
		return petName(entry.PetId)
	elseif kind == "Berries" then
		return "Berries"
	end
	return commas(entry.Amount)
end

-- the words of a play tier's reward ("+$200", "+40 Tokens")
local function tierReward(tier)
	local kind = tier.Kind
	if kind == "Cash" then
		return "+$" .. commas(tier.Amount)
	elseif kind == "Tokens" then
		return "+" .. commas(tier.Amount) .. " Tokens"
	elseif kind == "Gems" then
		return "+" .. commas(tier.Amount) .. " Gems"
	elseif kind == "Berries" then
		return "Full Berry Basket"
	elseif kind == "Pet" then
		return petName(tier.PetId)
	end
	return "+" .. commas(tier.Amount)
end

local function days(st)
	return (type(st) == "table" and type(st.Days) == "table") and st.Days or {}
end

local function play(st)
	return (type(st) == "table" and type(st.Play) == "table") and st.Play or {}
end

local function tiers(st)
	local p = play(st)
	return type(p.Tiers) == "table" and p.Tiers or {}
end

local function entryAt(list, i)
	local e = list[i]
	return type(e) == "table" and e or {}
end

local function claimReady(st)
	return type(st) == "table" and st.Loading ~= true and tonumber(st.ReadyAt) ~= nil and now() >= tonumber(st.ReadyAt)
end

local function tierReady(st)
	if type(st) ~= "table" or st.Loading == true then
		return false
	end
	for _, t in ipairs(tiers(st)) do
		if type(t) == "table" and t.Ready == true and t.Claimed ~= true then
			return true
		end
	end
	return false
end

-- the ring's fill: Play.Seconds / the next tier's seconds (1 once every tier is behind)
local function ringFill(st)
	local seconds = tonumber(play(st).Seconds) or 0
	for _, t in ipairs(tiers(st)) do
		local goal = (tonumber(type(t) == "table" and t.Min) or 0) * 60
		if goal > seconds then
			return math.max(0, math.min(1, seconds / goal))
		end
	end
	return #tiers(st) > 0 and 1 or 0
end

local function tutorialOk()
	local t = S.Tutorial
	if type(t) ~= "table" then
		local tc = controller("TutorialController")
		if tc and type(tc.GetState) == "function" then
			local ok, state = pcall(tc.GetState)
			t = ok and state or nil
		end
	end
	if type(t) ~= "table" then
		return false
	end
	if t.Done == true then
		return true
	end
	local spin = TutorialSteps.IndexOf and TutorialSteps.IndexOf.spin or 1
	local step = tonumber(t.Step) or (type(t.Id) == "string" and TutorialSteps.IndexOf[t.Id]) or 0
	return step >= spin
end

local function hiddenByPlay()
	local p = LocalPlayer
	if not p then
		return true
	end
	return p:GetAttribute(Config.Attr.InMatch) == true or p:GetAttribute(Config.Attr.InBattle or "InBattle") ~= nil
end

local H = {}

----------------------------------------------------------------------
-- The button, its pip and ring
----------------------------------------------------------------------
function H.hud()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	return pg and pg:FindFirstChild("NimbusHud")
end

function H.small()
	local vp = viewport()
	return math.min(vp.X, vp.Y) <= K.SMALL
end

function H.buttonSize()
	if H.small() then
		return K.BTN_MIN
	end
	return math.max(K.BTN_MIN, math.floor(K.BTN * Theme.ScreenFactor(viewport().Y)))
end

function H.buildButton()
	local size = H.buttonSize()
	local card = NeonKit.Card({
		Name = "GiftsButton", Class = "TextButton", Color = "Gold", Size = size, Corner = math.floor(size / 2),
		Floor = false, Sheen = false, ZIndex = 2, Parent = U.Gui,
	})
	U.Button = card.Root
	U.ButtonCard = card
	U.Icon = NeonKit.Icon(card.Body, "Gifts", math.floor(size * 0.5))
	U.Icon.Size = UDim2.fromScale(0.9, 0.9)
	U.Icon.TextScaled = true
	U.Icon.ZIndex = 3
	-- the ring: two clipped halves of one circle, each stroke under a stepped gradient (spec 8: "fills toward the next tier")
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 3
	ring.Parent = U.Gui
	U.Ring = ring
	U.Arcs = {}
	for i, side in ipairs({ "RingRight", "RingLeft" }) do
		local half = Instance.new("Frame")
		half.Name = side
		half.BackgroundTransparency = 1
		half.BorderSizePixel = 0
		half.ClipsDescendants = true
		half.Size = UDim2.fromScale(0.5, 1)
		half.Position = UDim2.fromScale(i == 1 and 0.5 or 0, 0)
		half.ZIndex = 3
		half.Parent = ring
		local arc = Instance.new("Frame")
		arc.Name = "Arc"
		arc.BackgroundTransparency = 1
		arc.BorderSizePixel = 0
		arc.Size = UDim2.fromScale(2, 1)
		arc.Position = UDim2.fromScale(i == 1 and -1 or 0, 0)
		arc.ZIndex = 3
		arc.Parent = half
		Theme.Corner(arc, UDim.new(0.5, 0))
		local stroke = Instance.new("UIStroke")
		stroke.Name = "RingStroke"
		stroke.Color = GOLD
		stroke.Thickness = K.RING_STROKE
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = arc
		local grad = Instance.new("UIGradient")
		grad.Name = "Step"
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = stroke
		U.Arcs[i] = { Stroke = stroke, Gradient = grad }
	end
	local pip = Instance.new("Frame")
	pip.Name = "Pip"
	pip.BackgroundColor3 = Theme.Neon.Red
	pip.BorderSizePixel = 0
	pip.AnchorPoint = Vector2.new(0.5, 0.5)
	pip.Position = UDim2.new(1, -4, 0, 4)
	pip.Size = UDim2.fromOffset(K.PIP, K.PIP)
	pip.ZIndex = 5
	pip.Visible = false
	Theme.Corner(pip, UDim.new(0.5, 0))
	pip.Parent = U.Button
	U.Pip = pip
	U.Button.Activated:Connect(function()
		if S.Open then
			DailyController.Close()
		else
			DailyController.Open()
		end
	end)
end

function H.paintRing()
	if not U.Ring then
		return
	end
	local st = S.State
	local fill = ringFill(st)
	U.Ring:SetAttribute("Fill", fill)
	local right = math.min(fill, 0.5) * 360
	local left = 180 + math.max(0, math.min(fill - 0.5, 0.5)) * 360
	local paused = type(st) == "table" and st.Loading ~= true and play(st).Active == false
	for i, arc in ipairs(U.Arcs) do
		arc.Gradient.Rotation = i == 1 and right or left
		arc.Stroke.Transparency = paused and K.RING_DIM or 0
	end
	U.Ring.Visible = not S.Hidden and type(st) == "table" and st.Loading ~= true and #tiers(st) > 0
end

function H.layoutButton()
	if not U.Button then
		return
	end
	local size = H.buttonSize()
	local hud = H.hud()
	local left = tonumber(hud and hud:GetAttribute("TopRightLeft")) or 0
	S.Hidden = left <= 0 or hiddenByPlay()
	local x = math.floor(left - K.GAP - size + 0.5)
	U.Button.Size = UDim2.fromOffset(size, size)
	U.Button.Position = UDim2.fromOffset(x + S.ShakeX, K.TOP)
	U.ButtonCard.Root:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, math.floor(size / 2))
	U.Button.Visible = not S.Hidden
	local r = size + 2 * K.RING_PAD
	U.Ring.Size = UDim2.fromOffset(r, r)
	U.Ring.Position = UDim2.fromOffset(x + S.ShakeX - K.RING_PAD, K.TOP - K.RING_PAD)
	H.paintRing()
	if S.Hidden then
		U.Ring.Visible = false
	end
	S.ButtonRect = { x = x, y = K.TOP, size = size }
	H.refreshPip()
end

function H.refreshPip()
	if U.Pip then
		U.Pip.Visible = DailyController.PipShown()
	end
end

function H.shake()
	S.ShakeToken = S.ShakeToken + 1
	local mine = S.ShakeToken
	task.spawn(function()
		for _, dx in ipairs(K.SHAKE) do
			if S.ShakeToken ~= mine then
				return
			end
			S.ShakeX = dx
			safe("shake", H.layoutButton)
			task.wait(K.SHAKE_STEP)
		end
		if S.ShakeToken == mine then
			S.ShakeX = 0
			safe("shake", H.layoutButton)
		end
	end)
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
function H.mode()
	if H.small() then
		return "Phone"
	end
	local f = Theme.ScreenFactor(viewport().Y)
	local area = U.Gui.AbsoluteSize
	local top = K.TOP + H.buttonSize() + K.GAP
	if area.Y > 2 and (top + K.PC.H * f > area.Y - K.EDGE or K.PC.W * f > area.X - 2 * K.EDGE) then
		return "Phone"
	end
	return "PC"
end

function H.tabButton(name, text, x, M, width)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = text
	Theme.Style(b, "Button", { Size = M.TabText, Stroke = 0.6, Outline = 1.5 })
	place(b, x, M.TitleY, width, M.TitleH)
	Theme.Corner(b, UDim.new(0, 10))
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TabStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = GOLD
	stroke.Parent = b
	b.Parent = U.Body
	return b
end

function H.build()
	local mode = H.mode()
	if U.Holder and S.Mode == mode then
		return
	end
	if U.Holder then
		U.Holder:Destroy()
	end
	S.Mode = mode
	local M = mode == "PC" and K.PC or K.PHONE
	U.M = M
	U.Cells, U.Rows = {}, {}
	local holder = Instance.new("Frame")
	holder.Name = "DailyHolder"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(M.W, M.H)
	holder.Visible = false
	holder.ZIndex = 4
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = holder
	U.Scale = scale
	U.Holder = holder
	local card = NeonKit.Card({ Name = "DailyWindow", Color = "Gold", Size = UDim2.fromScale(1, 1), Floor = false, ZIndex = 4, Parent = holder })
	U.Window = card.Root
	U.Body = card.Body
	U.Body.ClipsDescendants = true
	U.TabDaily = H.tabButton("Tab_Daily", "Daily", M.Pad, M, M.TabW[1])
	U.TabPlay = H.tabButton("Tab_Play", "Play time", M.Pad + M.TabW[1] + 8, M, M.TabW[2])
	U.TabDaily.Activated:Connect(function()
		H.setTab("Daily")
	end)
	U.TabPlay.Activated:Connect(function()
		H.setTab("Play")
	end)
	local close = NeonKit.Button({ Name = "CloseButton", Text = NeonKit.Glyphs.Close, Color = "Red", Size = M.Close, TextSize = M.TabText,
		Position = UDim2.fromOffset(M.W - M.Pad - M.Close, M.TitleY), Parent = U.Body, Callback = function()
			DailyController.Close()
		end })
	close.ZIndex = 5

	-- the Daily page
	local inner = M.W - 2 * M.Pad
	local daily = Instance.new("Frame")
	daily.Name = "DailyPage"
	daily.BackgroundTransparency = 1
	daily.Size = UDim2.fromScale(1, 1)
	daily.Parent = U.Body
	U.DailyPage = daily
	U.DailyHeader = label("Header", "", "Title", M.HeaderText, daily, { TextXAlignment = Enum.TextXAlignment.Left })
	place(U.DailyHeader, M.Pad, M.HeaderY, inner - M.ChipW - 8, M.HeaderH)
	U.VipChip = label("VipChip", "VIP x2", "Heading", M.ChipText, daily, { BackgroundTransparency = 0.15, BackgroundColor3 = Theme.Darken(GOLD, 0.55), TextColor3 = GOLD })
	place(U.VipChip, M.W - M.Pad - M.ChipW, M.HeaderY + 2, M.ChipW, M.HeaderH - 4)
	Theme.Corner(U.VipChip, UDim.new(0.5, 0))
	local cells = Instance.new("Frame")
	cells.Name = "Cells"
	cells.BackgroundTransparency = 1
	place(cells, M.Pad, M.CellsY, inner, M.CellH)
	cells.Parent = daily
	local gap = math.floor((inner - 7 * M.CellW) / 6)
	local x0 = math.floor((inner - (7 * M.CellW + 6 * gap)) / 2)
	for i = 1, 7 do
		local c = NeonKit.Card({ Name = "Cell" .. i, Color = "Blue", Size = UDim2.fromOffset(M.CellW, M.CellH), Floor = false, Corner = 10,
			Position = UDim2.fromOffset(x0 + (i - 1) * (M.CellW + gap), 0), Parent = cells })
		local pop = Instance.new("UIScale")
		pop.Name = "Pop"
		pop.Parent = c.Root
		local day = label("Day", "Day " .. i, "Label", M.DayText, c.Body)
		place(day, 2, 4, M.CellW - 4, M.DayText + 4)
		local art = Instance.new("Frame")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		place(art, 0, M.DayText + 8, M.CellW, M.CellH - 2 * M.DayText - 20)
		art.Parent = c.Body
		local amount = label("Amount", "", "Display", M.AmountText, c.Body, { TextWrapped = false, TextScaled = false })
		place(amount, 2, M.CellH - M.AmountText - 10, M.CellW - 4, M.AmountText + 6)
		amount.TextTruncate = Enum.TextTruncate.AtEnd
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.BackgroundColor3 = INK
		dim.BackgroundTransparency = 0.45
		dim.BorderSizePixel = 0
		dim.Size = UDim2.fromScale(1, 1)
		dim.ZIndex = 3
		dim.Visible = false
		Theme.Corner(dim, UDim.new(0, 10))
		dim.Parent = c.Body
		local check = label("Check", CHECK, "Title", M.CheckText, c.Body, { TextColor3 = Theme.Neon.Green, ZIndex = 4, Visible = false })
		place(check, M.CellW - M.CheckText - 6, 2, M.CheckText + 4, M.CheckText + 4)
		U.Cells[i] = { Card = c, Root = c.Root, Pop = pop, Art = art, Amount = amount, Dim = dim, Check = check, ArtKey = nil }
	end
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	place(footer, M.Pad, M.FooterY, inner, M.FooterH)
	footer.Parent = daily
	U.Claim = NeonKit.Button({ Name = "ClaimButton", Text = "CLAIM!", Color = "Green", Size = UDim2.fromOffset(M.ClaimW, M.ClaimH), TextSize = M.ClaimText,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, math.floor((M.FooterH - M.ClaimH) / 2)), Parent = footer,
		Callback = function()
			H.send("Claim")
		end })
	U.Countdown = label("Countdown", "", "Heading", M.CountText, footer)
	place(U.Countdown, 0, 2, inner, M.CountText + 8)
	U.Keep = label("Keep", "Come back tomorrow to keep your streak!", "Body", M.KeepText, footer, { TextColor3 = MUTED })
	place(U.Keep, 0, M.CountText + 12, inner, M.KeepText + 8)
	U.Banner = label("WeekBanner", "WEEK DONE! Week Wisp is yours!", "Title", M.BannerText, daily, { TextColor3 = GOLD, Visible = false })
	place(U.Banner, M.Pad, M.BannerY, inner, M.BannerH)

	-- the Play page
	local playPage = Instance.new("Frame")
	playPage.Name = "PlayPage"
	playPage.BackgroundTransparency = 1
	playPage.Size = UDim2.fromScale(1, 1)
	playPage.Visible = false
	playPage.Parent = U.Body
	U.PlayPage = playPage
	U.PlayHeader = label("Header", "", "Heading", M.HeaderText, playPage, { TextXAlignment = Enum.TextXAlignment.Left })
	place(U.PlayHeader, M.Pad, M.HeaderY, inner, M.HeaderH)
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	place(rows, M.Pad, M.RowsY, inner, M.H - M.RowsY - M.Pad)
	rows.Parent = playPage
	local perColumn = math.ceil(7 / M.Columns)
	local colW = math.floor((inner - (M.Columns - 1) * 10) / M.Columns)
	for i = 1, 7 do
		local col = math.floor((i - 1) / perColumn)
		local rowIndex = (i - 1) % perColumn
		local r = Instance.new("Frame")
		r.Name = "Row" .. i
		r.BackgroundColor3 = Theme.Colors.PanelTop or Color3.fromRGB(26, 32, 72)
		r.BackgroundTransparency = 0.25
		r.BorderSizePixel = 0
		place(r, col * (colW + 10), rowIndex * (M.RowH + M.RowGap), colW, M.RowH)
		Theme.Corner(r, UDim.new(0, 8))
		r.Parent = rows
		local pop = Instance.new("UIScale")
		pop.Name = "Pop"
		pop.Parent = r
		local right = M.ToGoW
		local text = label("Label", "", "Body", M.RowText, r, { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false })
		text.TextTruncate = Enum.TextTruncate.AtEnd
		place(text, 10, 0, colW - right - 16, M.RowH)
		local togo = label("ToGo", "", "Body", M.RowText, r, { TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		place(togo, colW - right - 6, 0, right, M.RowH)
		local check = label("Check", CHECK, "Title", M.RowText + 4, r, { TextColor3 = Theme.Neon.Green, TextXAlignment = Enum.TextXAlignment.Right })
		place(check, colW - right - 6, 0, right, M.RowH)
		local tier = i
		local claim = NeonKit.Button({ Name = "Claim", Text = "CLAIM", Color = "Green", Size = UDim2.fromOffset(M.RowBtnW, M.RowBtnH), TextSize = M.RowBtnText,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Parent = r, Callback = function()
				H.send("ClaimPlay", tier)
			end })
		U.Rows[i] = { Root = r, Pop = pop, Label = text, ToGo = togo, Check = check, Claim = claim }
	end

	-- the week's sweep + confetti layer (inside the window only)
	local fx = Instance.new("Frame")
	fx.Name = "Fx"
	fx.BackgroundTransparency = 1
	fx.ClipsDescendants = true
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = 8
	fx.Parent = U.Body
	U.Fx = fx
	holder.Parent = U.Gui
	S.Pulse = false
end

function H.layoutWindow()
	if not U.Holder or not S.ButtonRect then
		return
	end
	local M = U.M
	local scale = S.Mode == "PC" and Theme.ScreenFactor(viewport().Y) or 1
	local area = U.Gui.AbsoluteSize
	local w, h = M.W * scale, M.H * scale
	local b = S.ButtonRect
	local right = b.x + b.size
	local x = right - w
	if x < K.EDGE then
		x = K.EDGE
	end
	local y = b.y + b.size + K.GAP
	if area.Y > 2 and y + h > area.Y - K.EDGE then
		y = math.max(K.EDGE, area.Y - K.EDGE - h)
	end
	U.Holder.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	U.Scale.Scale = scale
	S.Scale = scale
end

function H.setTab(tab)
	S.Tab = tab == "Play" and "Play" or "Daily"
	H.render()
end

function H.paintTab(button, selected)
	button.BackgroundColor3 = selected and Theme.Darken(GOLD, 0.45) or (Theme.Colors.PanelBottom or INK)
	button.BackgroundTransparency = selected and 0 or 0.2
	button.TextColor3 = selected and WHITE or MUTED
	button:SetAttribute("Selected", selected)
	local stroke = button:FindFirstChild("TabStroke")
	if stroke then
		stroke.Transparency = selected and 0 or 0.6
	end
end

function H.paintArt(cell, entry, M)
	local key = tostring(entry.Kind) .. ":" .. tostring(entry.PetId)
	if cell.ArtKey == key then
		return
	end
	cell.ArtKey = key
	for _, child in ipairs(cell.Art:GetChildren()) do
		child:Destroy()
	end
	if entry.Kind == "Pet" and type(entry.PetId) == "string" then
		local ok = pcall(function()
			local vp = CloudUI.PetViewport(cell.Art, entry.PetId, M.PetPx, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Spin = "sway" })
			vp.Name = "PetViewport"
		end)
		if ok then
			return
		end
	end
	local icon = NeonKit.Icon(cell.Art, (entry.Kind == "Pet" and "Gifts") or (entry.Kind == "Berries" and "Berries") or tostring(entry.Kind or "Gifts"), M.IconPx)
	icon.ZIndex = 2
end

function H.renderDaily(st, M)
	local loading = type(st) ~= "table" or st.Loading == true
	if loading then
		U.DailyHeader.Text = "Daily gifts"
	else
		U.DailyHeader.Text = "Day " .. tostring(tonumber(st.Cell) or 1) .. " of 7 " .. DOT .. " Week " .. tostring((tonumber(st.Weeks) or 0) + 1)
	end
	U.VipChip.Visible = not loading and st.Vip == true
	local list = days(st)
	for i, cell in ipairs(U.Cells) do
		local e = entryAt(list, i)
		local claimed = e.Claimed == true
		local today = e.Today == true and not claimed and not loading
		cell.Root:SetAttribute("Claimed", claimed)
		cell.Root:SetAttribute("Today", today)
		cell.Root:SetAttribute("Pulsing", today)
		cell.Dim.Visible = claimed
		cell.Check.Visible = claimed
		cell.Card.SetColor(today and "Gold" or "Blue")
		if not today then
			cell.Card.Stroke.Transparency = 0
		end
		if e.Kind ~= nil then
			cell.Amount.Text = cellAmount(e)
			H.paintArt(cell, e, M)
		else
			cell.Amount.Text = ""
		end
	end
	local ready = claimReady(st)
	U.Claim.Visible = ready
	U.Countdown.Visible = not ready
	U.Keep.Visible = not ready and not loading
	if loading then
		U.Countdown.Text = "Getting your gifts ready..."
	elseif not ready then
		U.Countdown.Text = "Next gift in " .. leftText((tonumber(st.ReadyAt) or 0) - now())
	end
	U.Banner.Visible = time() < S.BannerUntil
end

function H.renderPlay(st, M)
	local p = play(st)
	local loading = type(st) ~= "table" or st.Loading == true
	local seconds = tonumber(p.Seconds) or 0
	if loading then
		U.PlayHeader.Text = "Play time gifts"
		U.PlayHeader.Font = Theme.Fonts.Heading
		U.PlayHeader.TextColor3 = WHITE
		U.PlayHeader.TextSize = M.HeaderText
	elseif p.Active == false then
		U.PlayHeader.Text = "Paused: move around to keep counting!"
		U.PlayHeader.Font = Theme.Fonts.Body
		U.PlayHeader.TextColor3 = GOLD
		U.PlayHeader.TextSize = M.PausedText
	else
		U.PlayHeader.Text = math.floor(seconds / 60) .. " min played today " .. DOT .. " Resets in " .. resetText((tonumber(p.DayEnds) or 0) - now())
		U.PlayHeader.Font = Theme.Fonts.Heading
		U.PlayHeader.TextColor3 = WHITE
		U.PlayHeader.TextSize = M.HeaderText
	end
	local list = tiers(st)
	for i, row in ipairs(U.Rows) do
		local t = list[i]
		row.Root.Visible = type(t) == "table"
		if type(t) == "table" then
			local goal = (tonumber(t.Min) or 0) * 60
			row.Label.Text = tostring(tonumber(t.Min) or 0) .. " min " .. DOT .. " " .. tierReward(t)
			local claimed = t.Claimed == true
			local ready = not claimed and t.Ready == true and not loading
			row.Check.Visible = claimed
			row.Claim.Visible = ready
			row.ToGo.Visible = not claimed and not ready
			if goal > seconds then
				row.ToGo.Text = math.ceil((goal - seconds) / 60) .. " min to go"
			else
				row.ToGo.Text = loading and "" or "Almost!"
			end
			row.Root.BackgroundTransparency = claimed and 0.55 or 0.25
		end
	end
end

function H.render()
	if not U.Holder then
		return
	end
	local M = U.M
	local st = S.State
	H.paintTab(U.TabDaily, S.Tab == "Daily")
	H.paintTab(U.TabPlay, S.Tab == "Play")
	U.DailyPage.Visible = S.Tab == "Daily"
	U.PlayPage.Visible = S.Tab == "Play"
	H.renderDaily(st, M)
	H.renderPlay(st, M)
end

-- 1 s: countdowns, today's pulse, the pip
function H.tick()
	H.refreshPip()
	if not S.Open or not U.Holder then
		return
	end
	H.render()
	S.Pulse = not S.Pulse
	for _, cell in ipairs(U.Cells) do
		if cell.Root:GetAttribute("Pulsing") == true then
			Util.Tween(cell.Card.Stroke, 0.9, { Transparency = S.Pulse and K.PULSE or 0 })
		end
	end
end

----------------------------------------------------------------------
-- Moments
----------------------------------------------------------------------
function H.pop(scaleObj)
	if scaleObj then
		scaleObj.Scale = K.POP
		Util.Tween(scaleObj, K.POP_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
end

function H.week()
	S.BannerUntil = time() + K.WEEK_SECONDS
	pcall(SoundFx.Play, "DailyWeek")
	if not (S.Open and U.Fx) or GraphicsQuality.Effective() == "Low" then
		return -- the sweep and the confetti are High only (the banner and the sound stay)
	end
	local fx = U.Fx
	local sweep = Instance.new("Frame")
	sweep.Name = "Sweep"
	sweep.BorderSizePixel = 0
	sweep.BackgroundColor3 = WHITE
	sweep.BackgroundTransparency = 0.45
	sweep.Size = UDim2.fromScale(0.35, 1)
	sweep.Position = UDim2.fromScale(-0.4, 0)
	sweep.ZIndex = 8
	local rainbow = Theme.Colors.Rainbow
	local keys = {}
	for i, c in ipairs(rainbow) do
		keys[#keys + 1] = ColorSequenceKeypoint.new((i - 1) / math.max(1, #rainbow - 1), c)
	end
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(keys)
	grad.Parent = sweep
	sweep.Parent = fx
	Util.Tween(sweep, 0.8, { Position = UDim2.fromScale(1.05, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(0.9, function()
		sweep:Destroy()
	end)
	for i = 1, K.CONFETTI do
		local bit = Instance.new("Frame")
		bit.Name = "Confetti"
		bit.BorderSizePixel = 0
		bit.BackgroundColor3 = rainbow[(i - 1) % #rainbow + 1]
		bit.Size = UDim2.fromOffset(8, 12)
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		local x = (i - 0.5) / K.CONFETTI + (math.random() - 0.5) * 0.03
		bit.Position = UDim2.new(x, 0, 0, -8)
		bit.ZIndex = 9
		bit.Parent = fx
		local fall = K.CONFETTI_TIME * (0.7 + 0.3 * math.random())
		Util.Tween(bit, fall, { Position = UDim2.new(x + (math.random() - 0.5) * 0.08, 0, 1, 12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(fall + 0.05, function()
			bit:Destroy()
		end)
	end
end

function H.onState(payload)
	if type(payload) ~= "table" then
		return
	end
	S.State = payload
	if payload.Loading == true then
		S.Last = nil -- a (re)load: the next real payload is a join, it never pops, shakes or celebrates
		H.paintRing()
		H.refreshPip()
		H.render()
		return
	end
	local prev = S.Last
	if prev then
		local popped = false
		local before, after = days(prev), days(payload)
		for i = 1, 7 do
			if entryAt(after, i).Claimed == true and entryAt(before, i).Claimed ~= true then
				popped = true
				if U.Cells[i] then
					H.pop(U.Cells[i].Pop)
				end
			end
		end
		local tb, ta = tiers(prev), tiers(payload)
		local newlyReady = false
		for i = 1, #ta do
			local a, b = entryAt(ta, i), entryAt(tb, i)
			if a.Claimed == true and b.Claimed ~= true then
				popped = true
				if U.Rows[i] then
					H.pop(U.Rows[i].Pop)
				end
			end
			if a.Ready == true and a.Claimed ~= true and b.Ready ~= true then
				newlyReady = true
			end
		end
		if popped then
			pcall(SoundFx.Play, "Reward")
		end
		local streak, was = tonumber(payload.Streak) or 0, tonumber(prev.Streak) or 0
		if streak > was and streak > 0 and streak % 7 == 0 then
			H.week()
		end
		if newlyReady then
			H.shake()
		end
	end
	local back = tonumber(payload.StepBack) or 0
	if back > 0 then
		local key = tostring(back) .. "|" .. tostring(payload.Streak) .. "|" .. tostring(payload.ReadyAt)
		if key ~= S.StepBackKey then
			S.StepBackKey = key
			local menu = controller("MenuController")
			if menu and type(menu.Hint) == "function" then
				local n = math.floor(back)
				pcall(menu.Hint, "Welcome back! You stepped back " .. n .. (n == 1 and " day" or " days") .. ". Keep going!", "info")
			end
		end
	end
	S.Last = payload
	H.paintRing()
	H.refreshPip()
	H.render()
end

function H.send(action, tier)
	local key = action .. tostring(tier or "")
	local t = os.clock()
	if S.LastFire[key] and t - S.LastFire[key] < K.CLAIM_GAP then
		return false
	end
	local ok, remote = pcall(Remotes.Get, "DailyRequest")
	if not ok or not remote then
		return false
	end
	S.LastFire[key] = t
	if tier ~= nil then
		remote:FireServer(action, tier)
	else
		remote:FireServer(action)
	end
	return true
end

function H.syncBack()
	if S.Open and not S.BackBound then
		S.BackBound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					DailyController.Close()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
	elseif not S.Open and S.BackBound then
		S.BackBound = false
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

function H.relayout()
	H.layoutButton()
	if S.Open then
		local mode = S.Mode
		H.build()
		if S.Mode ~= mode then
			U.Holder.Visible = true
		end
		H.layoutWindow()
		H.render()
	end
end

function H.onPlayState()
	if S.Open and hiddenByPlay() then
		DailyController.Close()
	end
	H.layoutButton()
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function DailyController.State()
	return S.State
end

function DailyController.IsOpen()
	return S.Open
end

function DailyController.PipShown()
	local st = S.State
	if type(st) ~= "table" or st.Loading == true or S.Hidden then
		return false
	end
	if not (claimReady(st) or tierReady(st)) then
		return false
	end
	if time() - S.SpawnAt < (Config.Daily and Config.Daily.PipDelaySeconds or 20) then
		return false
	end
	return tutorialOk()
end

function DailyController.Open(args)
	if not initialized then
		DailyController.Init()
	end
	if not U.Gui or hiddenByPlay() then
		return false
	end
	args = type(args) == "table" and args or {}
	local wasOpen = S.Open
	if args.Tab == "Play" or args.Tab == "Daily" then
		S.Tab = args.Tab
	elseif not wasOpen then
		S.Tab = (not claimReady(S.State) and tierReady(S.State)) and "Play" or "Daily"
	end
	S.Open = true
	H.layoutButton()
	H.build()
	H.layoutWindow()
	U.Holder.Visible = true
	H.render()
	H.syncBack()
	if not wasOpen then
		U.Scale.Scale = (S.Scale or 1) * 0.92
		Util.Tween(U.Scale, 0.18, { Scale = S.Scale or 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local menu = controller("MenuController")
		if menu and menu.WindowOpened then
			menu.WindowOpened:Fire("Daily")
		end
	end
	return true
end

function DailyController.Close()
	if not S.Open then
		return
	end
	S.Open = false
	if U.Holder then
		U.Holder.Visible = false
	end
	H.syncBack()
end

function DailyController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	U.Gui = CloudUI.NewScreenGui("NimbusDaily", K.DISPLAY_ORDER)
	U.Gui.IgnoreGuiInset = false
	H.buildButton()
	S.SpawnAt = time()
	LocalPlayer.CharacterAdded:Connect(function()
		S.SpawnAt = time()
		H.refreshPip()
	end)
	local attr = Config.Attr
	LocalPlayer:GetAttributeChangedSignal(attr.InMatch):Connect(function()
		safe("match", H.onPlayState)
	end)
	LocalPlayer:GetAttributeChangedSignal(attr.InBattle or "InBattle"):Connect(function()
		safe("battle", H.onPlayState)
	end)
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		safe("relayout", H.relayout)
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and S.Open then
			DailyController.Close()
		end
	end)
	local menu = controller("MenuController")
	if menu and menu.WindowOpened then
		menu.WindowOpened:Connect(function(id)
			if id ~= "Daily" and S.Open then
				DailyController.Close()
			end
		end)
	end
	safe("layout", H.layoutButton)
	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui")
		local hud = pg:WaitForChild("NimbusHud", 30)
		if hud then
			for _, name in ipairs({ "TopRightLeft", "TopRightBottom" }) do
				hud:GetAttributeChangedSignal(name):Connect(function()
					safe("relayout", H.relayout)
				end)
			end
			safe("relayout", H.relayout)
		end
	end)
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, "DailyState")
		if ok and remote then
			remote.OnClientEvent:Connect(function(payload)
				safe("state", H.onState, payload)
			end)
		end
	end)
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, "TutorialState")
		if ok and remote then
			remote.OnClientEvent:Connect(function(payload)
				if type(payload) == "table" then
					S.Tutorial = payload
					H.refreshPip()
				end
			end)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			safe("tick", H.tick)
		end
	end)
end

return DailyController
