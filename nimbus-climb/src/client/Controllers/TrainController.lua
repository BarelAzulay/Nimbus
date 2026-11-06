-- TrainController (client, gui-redo Task 7): the Training Place window (docs/superpowers/specs/2026-11-06-window-redo-design.md
-- 5.1 and 5.5; plan docs/superpowers/plans/2026-11-06-window-redo.md Task 7). It took the Train page out of CareController,
-- which keeps Feed, Garden and Evolve and forwards Open("Train", args) here.
--
--   TrainController.Init()
--   TrainController.Open(args) -> boolean   args = { Key?, ReturnTo? }. Key: that pet; without one the first pet in training
--       (soonest done); none training (a Training Place and a pet exist): the pet picker sheet opens by itself. ReturnTo:
--       the Pets window's own Open args; closing this window (X, Esc, B) goes back to it unless DropReturn ran.
--   TrainController.Close()        closes the confirm, our sheet and the window
--   TrainController.IsOpen()       -> true while the window or its confirm is up
--   TrainController.Key()          -> the selected pet key or nil (the empty state)
--   TrainController.Select(key)    selects an owned pet
--   TrainController.Step(dir)      -1 = the previous, 1 = the next pet in the picker's default Train order (wraps; from no pet:
--                                  1 = the first, -1 = the last); never opens the sheet
--   TrainController.DropReturn()   another window, a match or a battle took over: closing does not go back to the Pets window
--   TrainController.Layout()       -> "PC" | "Phone" | "Portrait"
--   TrainController.SkillState(stat) -> "Ready" | "Training" | "Busy" | "Full" | "Short" | "Max" | "Match" | "NoPet" | "NoPlace"
--
-- One window at a time, through CareController (so no other controller changes): on open this closes the menu windows (the
-- Pets window, the Store, the Index with them), the Pet Index, the Fusion Machine, the Gifts window and Care's own Feed /
-- Garden window (CareController.CloseOwn), and tells CareController (NotifyTrain) so Care.Opened fires "Train" and
-- Care.Closed fires on close; CareController.Close() / its DropReturn close this one too. It never fires
-- MenuController.WindowOpened.
-- Instances: ScreenGui NimbusTrain (23, IgnoreGuiInset) > Window_Train (UIScale Fit) > Panel > Header (Icon, Title,
-- SpotsChip, CloseButton) and Body (Mats [the band Task 8 fills], PetCard [PickPrompt], PetName, PetLevel, PrevButton,
-- ChangeButton, NextButton, RestNote, Skills > Skill_<Id> [attribute State; Name, Rank, Bar, Now, Next, Cost, Time, Action,
-- MaxTag], Empty, HintLine); ConfirmShade + Confirm (Title, Text, Yes, No): siblings of Window_Train above it.
-- Sends PetCare("Train", key, stat) / PetCare("TrainStop", key), each asked first, at most every 0.3 s; the server checks
-- everything again (it picks the mat, the price and the time). Every number shown comes from the catalogs and the synced
-- profile. The layout is computed in the design box of NeonKit.BigRect (PC: the 1080p mock as its largest form; Phone: 820 x
-- 330 screen px; Portrait: one column). Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local UI = Client:WaitForChild("UI")
local CloudUI = require(UI:WaitForChild("CloudUI"))
local NeonKit = require(UI:WaitForChild("NeonKit"))
local PetPicker = require(UI:WaitForChild("PetPicker"))
local Bits = require(UI:WaitForChild("PetBits"))
local State = require(Client:WaitForChild("State"))

local function optionalShared(name)
	local module = Shared:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	return (ok and type(mod) == "table") and mod or nil
end

local BattleCatalog = optionalShared("BattleCatalog")

local TrainController = {}

----------------------------------------------------------------------
-- Tunables (design px; PC = the 1080p mock, Phone = screen px)
----------------------------------------------------------------------
local K = {
	DISPLAY_ORDER = 23, -- Care's order: above NimbusMenu (20), the Pet Index (21) and the Fusion Machine (22)
	RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1440, Y1 = 840 },
	MARGIN = 12,
	PHONE_W = 900,
	SHORT = 560,
	PC_MIN_H = 600,
	PC_MAX_W = 0.76,
	TICK = 0.5, -- seconds between two refreshes while open (the timers)
	FIRE_GAP = 0.3, -- client-side spacing between two sends of the same action
	HINT_SECONDS = 3,
	OPEN_FROM = 0.86,
	OPEN_TIME = 0.22,
	VIEW_CACHE = 6, -- pet viewports kept (the shown one + parked ones)
	CONFIRM_W = 560,
	BACK_ACTION = "NimbusTrainBack",
	PC = {
		Header = 76, HeadPad = 24, Icon = 52, IconText = 36, TitleText = 34, TitleMin = 24, Close = 56, ChipText = 20,
		ChipH = 44, ChipPad = 18, Gap = 16, Pad = 24, MatsY = 12, MatsH = 132, Top = 158, Bottom = 14, LeftMax = 420,
		LeftShare = 0.292, ColGap = 24, NameH = 46, NameText = 42, NameMin = 28, LevelH = 30, LevelText = 26, Arrow = 76,
		ArrowText = 40, ChangeText = 24, NoteH = 50, NoteText = 19, CardGap = 16, PromptText = 30, ChipText2 = 18,
		Empty = 26, Hint = 20, HintH = 44,
	},
	PHONE = {
		Header = 50, HeadPad = 10, Icon = 36, IconText = 24, TitleText = 20, TitleMin = 16, Close = 44, ChipText = 15,
		ChipH = 30, ChipPad = 10, Gap = 8, Pad = 14, MatsY = 4, MatsH = 52, Top = 64, Bottom = 4, Left = 200,
		CardH = 112, NameH = 22, NameText = 18, NameMin = 15, LevelH = 20, LevelText = 15, Arrow = 44, ArrowText = 24,
		ChangeText = 16, ColGap = 12, CardGapX = 8, CardGapY = 6, PromptText = 18, ChipText2 = 15, Empty = 18, Hint = 15,
		HintH = 32,
	},
	-- the skill cards' insides
	CARD = {
		full = {
			Pad = 16, Icon = 64, IconText = 34, Name = 30, NameMin = 22, NameY = 14, NameH = 36, Rank = 22, RankH = 28, BarY = 92,
			BarH = 24, Line = 20, LineH = 28, NowY = 128, NextY = 158, BtnW = 200, BtnH = 64, BtnText = 24, BtnMin = 18, Cost = 26,
			CostH = 34, Time = 20, TimeH = 26, MaxText = 30,
		},
		compact = {
			Pad = 12, Icon = 48, IconText = 26, Name = 26, NameMin = 20, NameY = 10, NameH = 30, Rank = 20, RankH = 24, BarY = 72,
			BarH = 20, Line = 19, LineH = 24, NowY = 100, NextY = 126, BtnW = 180, BtnH = 56, BtnText = 22, BtnMin = 18, Cost = 24,
			CostH = 30, Time = 19, TimeH = 24, MaxText = 26,
		},
		-- (PC buttons stay >= 56 design px: 44+ screen px at the smallest PC scale, 0.8)
		tight = { Pad = 10, Top = 6, TopH = 26, Name = 20, NameMin = 18, Rank = 18, BarH = 12, Line = 18, LineH = 24, BtnH = 56, BtnText = 20, BtnMin = 18, Bottom = 6, MaxText = 22 },
		phone = { Pad = 8, Top = 2, TopH = 20, Name = 16, NameMin = 15, Rank = 15, BarH = 10, Line = 15, LineH = 18, BtnH = 44, BtnText = 16, BtnMin = 15, Bottom = 3, MaxText = 18 },
		row = { Pad = 10, Name = 16, NameMin = 15, Rank = 15, BtnW = 140, BtnH = 44, BtnText = 16, BtnMin = 15, Line = 15, MaxText = 18 },
	},
}

local Colors = Theme.Colors
local C = {
	White = Colors.White,
	Ink = Colors.TextStroke or Colors.Ink,
	Navy = Color3.fromRGB(11, 16, 48),
	Well = Color3.fromRGB(20, 26, 64),
	WellEdge = Color3.fromRGB(70, 84, 150),
	Muted = Color3.fromRGB(170, 180, 214),
	Gold = Color3.fromRGB(255, 211, 77),
	Good = Color3.fromRGB(120, 230, 120),
	Bad = Color3.fromRGB(255, 110, 110),
	Purple = Theme.Neon.Purple,
	Grey = Theme.Neon.Grey,
	SegOff = Color3.fromRGB(30, 38, 86),
	Accent = Color3.fromRGB(228, 104, 96),
	Skill = {
		Speed = Color3.fromRGB(63, 200, 255),
		Physique = Color3.fromRGB(255, 107, 129),
		Ability = Color3.fromRGB(180, 124, 255),
		Defense = Color3.fromRGB(255, 179, 71),
	},
}

-- glyphs as UTF-8 byte escapes (the source stays plain ASCII)
local G = {
	Muscle = "\240\159\146\170", -- the Training Place's station icon (TycoonCatalog Gym) and the picker's Train icon
	Star = "\226\152\133",
	Close = "\226\156\149",
	Prev = "\226\128\185",
	Next = "\226\128\186",
	Arrow = "\226\134\146",
	Dot = "\194\183",
	Plus = "+",
	Icons = {
		Speed = "\226\154\161",
		Physique = "\226\157\164\239\184\143",
		Ability = "\226\156\168",
		Defense = "\240\159\155\161\239\184\143",
	},
}

local SKILLS = (BattleCatalog and type(BattleCatalog.TrainingSkills) == "table" and #BattleCatalog.TrainingSkills == 4) and BattleCatalog.TrainingSkills
	or {
		{ Id = "Speed", Name = "Attack Speed" },
		{ Id = "Physique", Name = "Physique" },
		{ Id = "Ability", Name = "Ability" },
		{ Id = "Defense", Name = "Defense" },
	}
-- what one rank adds (BattleCatalog.Training) and the words after the number
local EFFECT = {
	Speed = { Per = 0.04, Words = "attack speed", Sign = "+" },
	Physique = { Per = 0.05, Words = "max health", Sign = "+" },
	Ability = { Per = 0.04, Words = "special power and charge", Short = "special power", Sign = "+" },
	Defense = { Per = 0.03, Words = "damage taken", Sign = "-" },
}
local HINTS = {
	NoPet = "Pick a pet first",
	NoPlace = "Build the Training Place at home first.",
	Busy = "This pet is already training. Stop it first to train another skill.",
	Full = "Every training spot is in use. Upgrade the Training Place for more!",
	Short = "Not enough Cash for this rank yet.",
	Match = "Pets train at home, after the match.",
}
local TEXTS = {
	NoPets = "No pets yet! Spin a roulette in the Shop to hatch one.",
	NoPlace = "Build the Training Place at home first. Training makes pets tougher in battles!",
	Rest = "Training pets rest at home until they're done.",
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local LocalPlayer = nil
local initialized = false
local S = {
	Open = false,
	Built = false,
	Token = 0,
	Key = nil, -- the selected pet (nil = the empty state)
	ReturnTo = nil, -- the Pets window's Open args to go back to
	BackTo = nil,
	Sheet = false, -- the picker sheet is up and ours
	SheetToken = 0,
	Confirm = nil, -- { Yes = fn } while the confirm is up
	Mode = "PC",
	Portrait = false,
	Scale = 1,
	Rect = nil,
	Card = "full", -- the skill cards' inside layout
	ViewId = nil, -- the shown viewport ("key#stage")
	States = {},
	Last = {},
	HintToken = 0,
	TouchOff = false,
	BackBound = false,
	RefreshPending = false,
	Warned = {},
}
local U = { Skills = {}, Views = {} }
local H = {} -- helpers (one table: the module stays far below Lua's local limit)

local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[TrainController] " .. tostring(key) .. ": " .. tostring(err))
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
	local l = Theme.Label("", role, { Size = size, Stroke = 0.25, StrokeColor = C.Ink, Outline = 1.5, OutlineColor = C.Ink })
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
-- Data (display only: the synced profile + the catalogs)
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

function H.now()
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

function H.clock(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- today's confirm wording ("1 min", "45 s")
function H.minutes(seconds)
	local m = math.floor((tonumber(seconds) or 0) / 60 + 0.5)
	if m < 1 then
		return math.max(1, math.floor(tonumber(seconds) or 0)) .. " s"
	end
	return m .. " min"
end

function H.money(n)
	return Bits.formatCash(n)
end

-- the card's exact cost ("$26,250")
function H.commas(n)
	return "$" .. Util.Commas(math.max(0, math.floor(tonumber(n) or 0)))
end

function H.def(key)
	return type(key) == "string" and Bits.defOfKey(key) or nil
end

function H.owned(key)
	if type(key) ~= "string" then
		return false
	end
	local ok, n = pcall(State.OwnedCount, key)
	return ok and (tonumber(n) or 0) > 0
end

function H.valid(key)
	return H.owned(key) and H.def(key) ~= nil
end

function H.cash()
	local ok, v = pcall(State.Cash)
	return (ok and type(v) == "number") and v or 0
end

function H.maxRank()
	local tr = BattleCatalog and BattleCatalog.Training
	return (type(tr) == "table" and tonumber(tr.MaxRank)) or 10
end

function H.rank(key, stat)
	local g = Bits.growth(key)
	local r = math.floor(tonumber(g[stat]) or 0)
	return math.max(0, math.min(H.maxRank(), r))
end

function H.per(stat)
	local tr = BattleCatalog and BattleCatalog.Training
	local v = type(tr) == "table" and tonumber(tr[stat]) or nil
	return v or EFFECT[stat].Per
end

function H.pct(stat, rank)
	return math.floor(H.per(stat) * 100 * rank + 0.5)
end

function H.placeLevel(home)
	local st = type(home) == "table" and home.Stations or nil
	local v = type(st) == "table" and tonumber(st.Gym) or nil
	if v and v == v then
		return math.max(0, math.floor(v))
	end
	return 0
end

function H.slots(home)
	return tonumber(Bits.catalogCall("TrainingSlots", home)) or 0
end

-- the jobs running (the growth map: a job can belong to a copy no longer listed)
function H.used()
	local okMap, map = pcall(State.PetGrowthMap)
	local n = 0
	if okMap and type(map) == "table" then
		for _, e in pairs(map) do
			if type(e) == "table" and type(e.Job) == "table" then
				n = n + 1
			end
		end
	end
	return n
end

function H.skillName(stat)
	for _, s in ipairs(SKILLS) do
		if s.Id == stat then
			return s.Name
		end
	end
	return tostring(stat)
end

-- the picker's default Train order (training soonest first, the team, the rest by rarity then level)
function H.order()
	local ok, sorted = pcall(function()
		return PetPicker.Sorted("Train", PetPicker.Entries("Train"), "Default", "All", "")
	end)
	local out = {}
	if ok and type(sorted) == "table" then
		for i, e in ipairs(sorted) do
			out[i] = e.Key
		end
	end
	return out
end

function H.firstTraining()
	for _, key in ipairs(H.order()) do
		if Bits.job(key) then
			return key
		end
	end
	return nil
end

function H.skillState(stat)
	if H.placeLevel(Bits.homeData()) < 1 then
		return "NoPlace"
	end
	local key = S.Key
	local def = H.valid(key) and H.def(key) or nil
	if not def then
		return "NoPet"
	end
	if H.inMatch() then
		return "Match"
	end
	local job = Bits.job(key)
	if job and job.Stat == stat then
		return "Training"
	end
	local rank = H.rank(key, stat)
	if rank >= H.maxRank() then
		return "Max"
	end
	if job then
		return "Busy"
	end
	if H.used() >= H.slots(Bits.homeData()) then
		return "Full"
	end
	local cost = tonumber(Bits.catalogCall("TrainCost", def, rank + 1)) or 0
	if H.cash() < cost then
		return "Short"
	end
	return "Ready"
end

----------------------------------------------------------------------
-- Text fit (TextService: the real font)
----------------------------------------------------------------------
function H.width(text, size, font)
	local plain = tostring(text):gsub("<[^>]*>", "")
	local ok, v = pcall(function()
		return TextService:GetTextSize(plain, size, font, Vector2.new(4096, 1024))
	end)
	if ok and typeof(v) == "Vector2" then
		return v.X
	end
	return #plain * size * 0.55
end

-- the first text that fits `width` at a size from maxSize down to minSize; the last text at minSize when none does
function H.fit(lbl, texts, width, maxSize, minSize)
	for _, t in ipairs(texts) do
		local size = maxSize
		while size >= minSize do
			if H.width(t, size, lbl.Font) <= width then
				lbl.Text, lbl.TextSize = t, size
				return
			end
			size = size - 1
		end
	end
	lbl.Text, lbl.TextSize = texts[#texts], minSize
end

-- the height of a wrapped text in `width` (TextService, never less than the lines its single-line width needs)
function H.wrappedHeight(text, size, font, width)
	local lineH = math.ceil(size * 1.25)
	local lines = math.max(1, math.ceil(H.width(text, size, font) / math.max(1, width * 0.9)))
	local h = lines * lineH
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(width, 4096))
	end)
	if ok and typeof(v) == "Vector2" and v.Y > h then
		h = v.Y
	end
	return h
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
	U.Gui = CloudUI.NewScreenGui("NimbusTrain", K.DISPLAY_ORDER)
	U.Gui.IgnoreGuiInset = true
	S.Built = false
	U.Skills, U.Views, S.ViewId = {}, {}, nil
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if S.Open or S.Confirm then
			safe("relayout", H.layout)
		end
	end)
	return true
end

function H.build()
	if S.Built then
		return
	end
	S.Built = true
	local holder = Util.Create("Frame", { Name = "Window_Train", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 2, Parent = U.Gui })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	local panel = Util.Create("Frame", {
		Name = "Panel", BackgroundColor3 = C.Navy, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = holder,
	})
	Theme.Corner(panel, UDim.new(0, 18))
	Theme.Stroke(panel, C.Accent, 3, 0)
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel })
	-- header: the accent strip, square at the bottom
	local header = Util.Create("Frame", { Name = "Header", BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
	Theme.Corner(header, UDim.new(0, 18))
	Theme.Gradient(header, Theme.Lighten(C.Accent, 0.12), Theme.Darken(C.Accent, 0.28), 90)
	U.Header = header
	U.HeaderFoot = Util.Create("Frame", { Name = "HeaderFoot", BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 3, Parent = header })
	Theme.Gradient(U.HeaderFoot, Theme.Lighten(C.Accent, 0.12):Lerp(Theme.Darken(C.Accent, 0.28), 0.76), Theme.Darken(C.Accent, 0.28), 90)
	U.Icon = label(header, "Icon", "Title", 36, { ZIndex = 4, Text = G.Muscle, TextTruncate = Enum.TextTruncate.None })
	U.Title = label(header, "Title", "Title", 34, { ZIndex = 4, Text = "Training Place", TextXAlignment = Enum.TextXAlignment.Left })
	U.Chip = label(header, "SpotsChip", "Heading", 20, {
		ZIndex = 4, BackgroundTransparency = 0.2, BackgroundColor3 = Color3.fromRGB(40, 12, 22), TextTruncate = Enum.TextTruncate.None,
	})
	Theme.Corner(U.Chip, UDim.new(0.5, 0))
	Theme.Stroke(U.Chip, Theme.Lighten(C.Accent, 0.35), 2, 0.2)
	U.Close = CloudUI.Button({
		Name = "CloseButton", Text = G.Close, Style = "Red", Size = UDim2.fromOffset(44, 44), TextSize = 22, ZIndex = 5,
		Callback = function()
			TrainController.Close()
		end,
		Parent = header,
	})
	-- body
	local body = Util.Create("Frame", { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = panel })
	U.Body = body
	U.Mats = Util.Create("Frame", { Name = "Mats", BackgroundColor3 = C.Well, BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 3, Parent = body })
	Theme.Corner(U.Mats, UDim.new(0, 14))
	Theme.Stroke(U.Mats, C.WellEdge, 2, 0.3)
	-- the big pet card (tap: the sheet)
	U.Card = NeonKit.Card({ Name = "PetCard", Class = "TextButton", Color = C.Grey, Corner = 18, Floor = true, ZIndex = 3, Parent = body })
	U.Card.Root.Activated:Connect(function()
		H.openSheet()
	end)
	U.Art = Util.Create("Frame", { Name = "Art", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = U.Card.Body })
	U.Rarity = label(U.Card.Body, "RarityChip", "Heading", 18, {
		ZIndex = 6, BackgroundTransparency = 0, BackgroundColor3 = C.Grey, TextTruncate = Enum.TextTruncate.None,
	})
	Theme.Corner(U.Rarity, UDim.new(0.5, 0))
	U.Element = label(U.Card.Body, "ElementChip", "Heading", 18, {
		ZIndex = 6, BackgroundTransparency = 0.1, BackgroundColor3 = C.Well, TextTruncate = Enum.TextTruncate.None,
	})
	Theme.Corner(U.Element, UDim.new(0.5, 0))
	U.ElementStroke = Theme.Stroke(U.Element, C.White, 2, 0)
	U.Prompt = label(U.Card.Body, "PickPrompt", "Heading", 30, {
		ZIndex = 6, Visible = false, RichText = true, TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
	})
	U.Name = label(body, "PetName", "Title", 42, { ZIndex = 3 })
	U.Level = label(body, "PetLevel", "Heading", 26, { ZIndex = 3, RichText = true, TextColor3 = C.Muted })
	U.Prev = NeonKit.Button({
		Name = "PrevButton", Text = G.Prev, Color = "Blue", Size = UDim2.fromOffset(76, 76), TextSize = 40, ZIndex = 3,
		Callback = function()
			TrainController.Step(-1)
		end,
		Parent = body,
	})
	U.Change = NeonKit.Button({
		Name = "ChangeButton", Text = "Change pet", Color = "Blue", Size = UDim2.fromOffset(220, 76), TextSize = 24, ZIndex = 3,
		Callback = function()
			H.openSheet()
		end,
		Parent = body,
	})
	U.Next = NeonKit.Button({
		Name = "NextButton", Text = G.Next, Color = "Blue", Size = UDim2.fromOffset(76, 76), TextSize = 40, ZIndex = 3,
		Callback = function()
			TrainController.Step(1)
		end,
		Parent = body,
	})
	U.Note = label(body, "RestNote", "Body", 19, { ZIndex = 3, Text = TEXTS.Rest, TextWrapped = true, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.None })
	U.SkillsFrame = Util.Create("Frame", { Name = "Skills", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = body })
	for _, skill in ipairs(SKILLS) do
		H.newSkill(skill)
	end
	U.Empty = label(body, "Empty", "Heading", 24, { ZIndex = 5, Visible = false, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
	U.Hint = label(body, "HintLine", "Heading", 20, {
		ZIndex = 9, Visible = false, BackgroundTransparency = 0.12, BackgroundColor3 = Color3.fromRGB(8, 10, 28), TextWrapped = true,
	})
	Theme.Corner(U.Hint, UDim.new(0, 10))
	U.Cache = Util.Create("Frame", { Name = "ViewCache", BackgroundTransparency = 1, Visible = false, Size = UDim2.fromOffset(10, 10), Parent = holder })
	H.buildConfirm()
	-- the cursor is free while the window is shown (client/MouseLock, as the Pets window)
	local mouseLock = Client:FindFirstChild("MouseLock")
	local okLock, lock = pcall(function()
		return mouseLock and require(mouseLock)
	end)
	if okLock and type(lock) == "table" and type(lock.WatchVisible) == "function" then
		safe("mouse lock", lock.WatchVisible, "Dock:" .. holder.Name, holder)
	end
end

function H.newSkill(skill)
	local id = skill.Id
	local color = C.Skill[id] or C.Accent
	local card = NeonKit.Card({ Name = "Skill_" .. id, Color = color, Corner = 16, Floor = true, ZIndex = 3, Parent = U.SkillsFrame })
	local body = card.Body
	local item = { Id = id, Color = color, Card = card, Root = card.Root, Segs = {} }
	item.IconHolder = Util.Create("Frame", { Name = "IconHolder", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = body })
	item.Orb = NeonKit.Orb(item.IconHolder, color, 64)
	item.Orb.ZIndex = 4
	item.Icon = label(item.IconHolder, "Icon", "Display", 34, {
		ZIndex = 5, Text = G.Icons[id] or G.Muscle, Size = UDim2.fromScale(1, 1), TextTruncate = Enum.TextTruncate.None,
	})
	item.NameL = label(body, "Name", "Title", 30, { ZIndex = 5, Text = skill.Name or H.skillName(id), TextXAlignment = Enum.TextXAlignment.Left })
	item.RankL = label(body, "Rank", "Heading", 22, { ZIndex = 5, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left })
	item.Bar = Util.Create("Frame", { Name = "Bar", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5, Parent = body })
	for i = 1, 10 do
		local seg = Util.Create("Frame", { Name = "Seg" .. i, BackgroundColor3 = C.SegOff, BorderSizePixel = 0, ZIndex = 6, Parent = item.Bar })
		Theme.Corner(seg, UDim.new(0, 4))
		seg:SetAttribute("Lit", false)
		item.Segs[i] = seg
	end
	item.Now = label(body, "Now", "Body", 20, { ZIndex = 5, TextXAlignment = Enum.TextXAlignment.Left })
	item.Next = label(body, "Next", "Body", 20, { ZIndex = 5, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Left })
	item.Cost = label(body, "Cost", "Display", 26, { ZIndex = 5, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Left })
	item.Time = label(body, "Time", "Body", 20, { ZIndex = 5, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left })
	item.Action = NeonKit.Button({ Name = "Action", Text = "TRAIN", Color = "Green", Size = UDim2.fromOffset(200, 64), TextSize = 24, ZIndex = 6, Parent = body })
	-- (not the Button's Callback: a disabled button still says why, on the HintLine)
	item.Action.Activated:Connect(function()
		H.onAction(id)
	end)
	item.MaxTag = label(body, "MaxTag", "Display", 30, {
		ZIndex = 6, Visible = false, Text = "MAX", TextColor3 = C.Gold, BackgroundTransparency = 0.2, BackgroundColor3 = Color3.fromRGB(60, 44, 8),
		TextTruncate = Enum.TextTruncate.None,
	})
	Theme.Corner(item.MaxTag, UDim.new(0, 14))
	Theme.Stroke(item.MaxTag, C.Gold, 2, 0.1)
	U.Skills[id] = item
end

function H.buildConfirm()
	U.Shade = Util.Create("TextButton", {
		Name = "ConfirmShade", Text = "", AutoButtonColor = false, BorderSizePixel = 0, Active = true, Selectable = false, Visible = false,
		BackgroundColor3 = Color3.fromRGB(4, 6, 20), BackgroundTransparency = 0.5, Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = U.Gui,
	})
	U.Shade.Activated:Connect(function()
		H.closeConfirm()
	end)
	local holder = Util.Create("Frame", { Name = "Confirm", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 41, Parent = U.Gui })
	U.Confirm = holder
	U.ConfirmFit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	local box = Util.Create("Frame", { Name = "Box", BackgroundColor3 = C.Navy, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 42, Parent = holder })
	Theme.Corner(box, UDim.new(0, 18))
	U.ConfirmStroke = Theme.Stroke(box, C.Good, 4, 0)
	U.ConfirmPop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = box })
	U.ConfirmTitle = label(box, "Title", "Title", 30, { ZIndex = 43 })
	U.ConfirmText = label(box, "Text", "Body", 20, {
		ZIndex = 43, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top,
	})
	U.ConfirmYes = CloudUI.Button({
		Name = "Yes", Text = "Yes", Style = "Green", Size = UDim2.fromOffset(250, 56), TextSize = 23, ZIndex = 44,
		Callback = function()
			local c = S.Confirm
			H.closeConfirm()
			if c and type(c.Yes) == "function" then
				safe("confirm", c.Yes)
			end
		end,
		Parent = box,
	})
	U.ConfirmNo = CloudUI.Button({
		Name = "No", Text = "Not now", Style = "Blue", Size = UDim2.fromOffset(190, 56), TextSize = 22, ZIndex = 44,
		Callback = function()
			H.closeConfirm()
		end,
		Parent = box,
	})
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
function H.layout()
	if not S.Built then
		return
	end
	local r = NeonKit.BigRect(K)
	S.Rect, S.Scale, S.Mode = r, r.scale, r.mode
	S.Portrait = r.mode == "Phone" and r.portrait == true
	local W = math.floor(r.w / r.scale + 0.5)
	local Hh = math.floor(r.h / r.scale + 0.5)
	place(U.Holder, r.x, r.y, W, Hh)
	U.Fit.Scale = r.scale
	S.W, S.H = W, Hh
	if S.Mode ~= "Phone" then
		H.layoutPC(W, Hh)
	elseif S.Portrait then
		H.layoutPortrait(W, Hh)
	else
		H.layoutPhone(W, Hh)
	end
	H.layoutConfirm()
	H.paint()
	H.coverColumn()
end

function H.metrics()
	return S.Mode == "Phone" and K.PHONE or K.PC
end

function H.layoutHeader()
	local M = H.metrics()
	local W = S.W or 0
	place(U.Header, 0, 0, W, M.Header)
	place(U.HeaderFoot, 0, M.Header - 18, W, 18)
	place(U.Icon, M.HeadPad, (M.Header - M.Icon) / 2, M.Icon, M.Icon)
	U.Icon.TextSize = M.IconText
	place(U.Close, W - M.HeadPad - M.Close, (M.Header - M.Close) / 2, M.Close, M.Close)
	U.Close.TextSize = math.floor(M.Close * 0.5)
	U.Chip.TextSize = M.ChipText
	local chipW = math.ceil(H.width(U.Chip.Text, M.ChipText, U.Chip.Font)) + 2 * M.ChipPad
	local chipX = W - M.HeadPad - M.Close - M.Gap - chipW
	place(U.Chip, chipX, (M.Header - M.ChipH) / 2, chipW, M.ChipH)
	local titleX = M.HeadPad + M.Icon + 8
	local titleW = math.max(40, chipX - M.Gap - titleX)
	place(U.Title, titleX, 0, titleW, M.Header)
	H.fit(U.Title, { "Training Place", "Training" }, titleW, M.TitleText, M.TitleMin)
end

function H.layoutPC(W, Hh)
	local M = K.PC
	local bodyH = Hh - M.Header
	place(U.Body, 0, M.Header, W, bodyH)
	place(U.Mats, M.Pad, M.MatsY, W - 2 * M.Pad, M.MatsH)
	local y0 = M.Top
	local A = bodyH - y0 - M.Bottom
	local leftW = math.min(M.LeftMax, math.floor(W * M.LeftShare))
	local below = 4 + M.NameH + M.LevelH + 10 + M.Arrow + 10 + M.NoteH
	local cardH = A - below
	local note = true
	if cardH < 160 then
		note = false
		below = below - 10 - M.NoteH
		cardH = A - below
	end
	cardH = math.max(100, cardH)
	place(U.Card.Root, M.Pad, y0, leftW, cardH)
	H.layoutCardInside(leftW, cardH, false)
	local y = y0 + cardH + 4
	place(U.Name, M.Pad, y, leftW, M.NameH)
	U.Name.TextXAlignment = Enum.TextXAlignment.Center
	y = y + M.NameH
	place(U.Level, M.Pad, y, leftW, M.LevelH)
	U.Level.TextSize = M.LevelText
	U.Level.TextXAlignment = Enum.TextXAlignment.Center
	y = y + M.LevelH + 10
	place(U.Prev, M.Pad, y, M.Arrow, M.Arrow)
	place(U.Next, M.Pad + leftW - M.Arrow, y, M.Arrow, M.Arrow)
	place(U.Change, M.Pad + M.Arrow + 10, y, leftW - 2 * M.Arrow - 20, M.Arrow)
	U.Prev.TextSize, U.Next.TextSize = M.ArrowText, M.ArrowText
	y = y + M.Arrow + 10
	S.NoteOn = note
	place(U.Note, M.Pad, y, leftW, M.NoteH)
	U.Note.TextSize = M.NoteText
	-- the skill cards, 2 x 2
	local sx = M.Pad + leftW + M.ColGap
	local sw = W - sx - M.Pad
	place(U.SkillsFrame, sx, y0, sw, A)
	local cw = math.floor((sw - M.CardGap) / 2)
	local ch = math.floor((A - M.CardGap) / 2)
	S.Card = (ch >= 272 and "full") or (ch >= 222 and "compact") or "tight"
	for i, skill in ipairs(SKILLS) do
		local item = U.Skills[skill.Id]
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		place(item.Root, col * (cw + M.CardGap), row * (ch + M.CardGap), cw, ch)
		if S.Card == "tight" then
			H.layoutSkillSmall(item, cw, ch, K.CARD.tight)
		else
			H.layoutSkillBig(item, cw, ch, K.CARD[S.Card])
		end
	end
	S.EmptyBody = { M.Pad, y0, W - 2 * M.Pad, A, M.Empty }
	S.EmptyBand = { M.Pad + 20, M.MatsY, W - 2 * M.Pad - 40, M.MatsH, 24 }
	place(U.Hint, M.Pad + 40, bodyH - M.HintH - 10, W - 2 * M.Pad - 80, M.HintH)
	U.Hint.TextSize = M.Hint
end

function H.layoutPhone(W, Hh)
	local M = K.PHONE
	local bodyH = Hh - M.Header
	place(U.Body, 0, M.Header, W, bodyH)
	place(U.Mats, M.Pad, M.MatsY, W - 2 * M.Pad, M.MatsH)
	local y0 = M.Top
	local leftW = M.Left
	-- the card gives way on a lower phone so the buttons stay on the screen
	local cardH = math.max(80, math.min(M.CardH, bodyH - y0 - (2 + M.NameH + M.LevelH + 4 + M.Arrow) - M.Bottom))
	place(U.Card.Root, M.Pad, y0, leftW, cardH)
	H.layoutCardInside(leftW, cardH, true)
	local y = y0 + cardH + 2
	place(U.Name, M.Pad, y, leftW, M.NameH)
	U.Name.TextXAlignment = Enum.TextXAlignment.Center
	y = y + M.NameH
	place(U.Level, M.Pad, y, leftW, M.LevelH)
	U.Level.TextSize = M.LevelText
	U.Level.TextXAlignment = Enum.TextXAlignment.Center
	y = y + M.LevelH + 4
	place(U.Prev, M.Pad, y, M.Arrow, M.Arrow)
	place(U.Next, M.Pad + leftW - M.Arrow, y, M.Arrow, M.Arrow)
	place(U.Change, M.Pad + M.Arrow + 6, y, leftW - 2 * M.Arrow - 12, M.Arrow)
	U.Prev.TextSize, U.Next.TextSize = M.ArrowText, M.ArrowText
	S.NoteOn = false -- (no room on a landscape phone)
	local sx = M.Pad + leftW + M.ColGap
	local sw = W - sx - M.Pad
	local A = bodyH - y0 - M.Bottom
	place(U.SkillsFrame, sx, y0, sw, A)
	local cw = math.floor((sw - M.CardGapX) / 2)
	local ch = math.floor((A - M.CardGapY) / 2)
	S.Card = "phone"
	for i, skill in ipairs(SKILLS) do
		local item = U.Skills[skill.Id]
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		place(item.Root, col * (cw + M.CardGapX), row * (ch + M.CardGapY), cw, ch)
		H.layoutSkillSmall(item, cw, ch, K.CARD.phone)
	end
	S.EmptyBody = { M.Pad, y0, W - 2 * M.Pad, A, M.Empty }
	S.EmptyBand = { M.Pad + 8, M.MatsY, W - 2 * M.Pad - 16, M.MatsH, 15 }
	place(U.Hint, M.Pad + 10, bodyH - M.HintH - 6, W - 2 * M.Pad - 20, M.HintH)
	U.Hint.TextSize = M.Hint
end

function H.layoutPortrait(W, Hh)
	local M = K.PHONE
	local bodyH = Hh - M.Header
	place(U.Body, 0, M.Header, W, bodyH)
	local pad = 12
	place(U.Mats, pad, M.MatsY, W - 2 * pad, 60)
	local y0 = 72
	local cardW, cardH = 150, 140
	place(U.Card.Root, pad, y0, cardW, cardH)
	H.layoutCardInside(cardW, cardH, true)
	local rx = pad + cardW + 10
	local rw = W - rx - pad
	place(U.Name, rx, y0 + 4, rw, 24)
	U.Name.TextXAlignment = Enum.TextXAlignment.Left
	place(U.Level, rx, y0 + 28, rw, 22)
	U.Level.TextSize = M.LevelText
	U.Level.TextXAlignment = Enum.TextXAlignment.Left
	local by = y0 + 56
	place(U.Prev, rx, by, M.Arrow, M.Arrow)
	place(U.Next, rx + rw - M.Arrow, by, M.Arrow, M.Arrow)
	place(U.Change, rx + M.Arrow + 6, by, rw - 2 * M.Arrow - 12, M.Arrow)
	U.Prev.TextSize, U.Next.TextSize = M.ArrowText, M.ArrowText
	place(U.Note, rx, by + M.Arrow + 6, rw, cardH - (by - y0) - M.Arrow - 6)
	U.Note.TextSize = 15
	S.NoteOn = U.Note.Size.Y.Offset >= 30
	local sy = y0 + cardH + 10
	local gap = 8
	local A = bodyH - sy - 6
	place(U.SkillsFrame, pad, sy, W - 2 * pad, A)
	local ch = math.floor((A - 3 * gap) / 4)
	S.Card = "row"
	for i, skill in ipairs(SKILLS) do
		local item = U.Skills[skill.Id]
		place(item.Root, 0, (i - 1) * (ch + gap), W - 2 * pad, ch)
		H.layoutSkillRow(item, W - 2 * pad, ch, K.CARD.row)
	end
	S.EmptyBody = { pad, y0, W - 2 * pad, bodyH - y0 - 6, M.Empty }
	S.EmptyBand = { pad + 6, M.MatsY, W - 2 * pad - 12, 60, 15 }
	place(U.Hint, pad + 6, bodyH - 44, W - 2 * pad - 12, 38)
	U.Hint.TextSize = M.Hint
end

-- the big pet card's inside: the viewport, the rarity chip, the element chip (PC), the "Pick a pet" prompt
function H.layoutCardInside(w, h, small)
	local chipH = small and 22 or 32
	place(U.Art, 6, small and 4 or 10, w - 12, h - (small and 8 or 20))
	place(U.Rarity, 8, 8, 10, chipH)
	U.Rarity.TextSize = small and 15 or 18
	place(U.Element, w - 8 - 10, 8, 10, chipH)
	U.Element.TextSize = 18
	U.Prompt.TextSize = small and K.PHONE.PromptText or K.PC.PromptText
	place(U.Prompt, 4, 0, w - 8, h)
	S.CardW, S.CardSmall = w, small
end

function H.layoutBar(item, x, y, w, h)
	place(item.Bar, x, y, w, h)
	local gap = h >= 16 and 6 or 3
	local segW = (w - 9 * gap) / 10
	for i, seg in ipairs(item.Segs) do
		place(seg, (i - 1) * (segW + gap), 0, segW, h)
	end
end

-- PC full / compact: icon + name + rank, the bar, Now, Next, and the cost / time beside the button
function H.layoutSkillBig(item, w, h, m)
	item.IconHolder.Visible = true
	place(item.IconHolder, m.Pad, m.Pad, m.Icon, m.Icon)
	item.Orb.Size = UDim2.fromOffset(m.Icon, m.Icon)
	item.Icon.TextSize = m.IconText
	local tx = m.Pad + m.Icon + 12
	local tw = w - tx - m.Pad
	place(item.NameL, tx, m.NameY, tw, m.NameH)
	H.fit(item.NameL, { item.NameL.Text }, tw, m.Name, m.NameMin)
	place(item.RankL, tx, m.NameY + m.NameH, tw, m.RankH)
	item.RankL.TextSize = m.Rank
	item.RankL.TextXAlignment = Enum.TextXAlignment.Left
	H.layoutBar(item, m.Pad, m.BarY, w - 2 * m.Pad, m.BarH)
	item.Now.Visible, item.Next.Visible, item.Cost.Visible, item.Time.Visible = true, true, true, true
	place(item.Now, m.Pad, m.NowY, w - 2 * m.Pad, m.LineH)
	place(item.Next, m.Pad, m.NextY, w - 2 * m.Pad, m.LineH)
	item.Now.TextSize, item.Next.TextSize = m.Line, m.Line
	local by = h - m.Pad - m.BtnH
	place(item.Action, w - m.Pad - m.BtnW, by, m.BtnW, m.BtnH)
	place(item.MaxTag, w - m.Pad - m.BtnW, by, m.BtnW, m.BtnH)
	item.MaxTag.TextSize = m.MaxText
	local cw = w - 2 * m.Pad - m.BtnW - 10
	place(item.Cost, m.Pad, by, cw, m.CostH)
	place(item.Time, m.Pad, by + m.CostH, cw, m.TimeH)
	item.Cost.TextSize, item.Time.TextSize = m.Cost, m.Time
	item.Lay = m
end

-- phone (and the tight PC card): the name and "4/10" on top, the bar, one line, the button across the bottom
function H.layoutSkillSmall(item, w, h, m)
	item.IconHolder.Visible = false
	local pad = m.Pad
	local topH, barH, gap = m.TopH, m.BarH, 3
	local by = h - m.BtnH - m.Bottom
	local lineY = m.Top + topH + gap + barH + gap
	if lineY + m.LineH > by then
		-- a short card: a slimmer bar and gaps
		barH, gap = 6, 2
		topH = math.max(m.Name + 2, by - m.LineH - m.Top - 2 * gap - barH)
		lineY = m.Top + topH + gap + barH + gap
	end
	local rankW = math.ceil(H.width("10/10", m.Rank, item.RankL.Font)) + 6
	place(item.NameL, pad, m.Top, w - 2 * pad - rankW - 4, topH)
	H.fit(item.NameL, { item.NameL.Text }, w - 2 * pad - rankW - 4, m.Name, m.NameMin)
	place(item.RankL, w - pad - rankW, m.Top, rankW, topH)
	item.RankL.TextSize = m.Rank
	item.RankL.TextXAlignment = Enum.TextXAlignment.Right
	H.layoutBar(item, pad, m.Top + topH + gap, w - 2 * pad, barH)
	item.Next.Visible, item.Cost.Visible, item.Time.Visible = false, false, false
	item.Now.Visible = true
	place(item.Now, pad, lineY, w - 2 * pad, m.LineH)
	item.Now.TextSize = m.Line
	place(item.Action, pad, by, w - 2 * pad, m.BtnH)
	place(item.MaxTag, pad, by, w - 2 * pad, m.BtnH)
	item.MaxTag.TextSize = m.MaxText
	item.Lay = m
end

-- portrait: the name, "4/10", the bar and one line on the left, the button on the right
function H.layoutSkillRow(item, w, h, m)
	item.IconHolder.Visible = false
	local pad = m.Pad
	local bx = w - 8 - m.BtnW
	local lw = bx - pad - 8
	local rankW = math.ceil(H.width("10/10", m.Rank, item.RankL.Font)) + 6
	local top = math.max(4, math.floor((h - 64) / 2))
	place(item.NameL, pad, top, lw - rankW - 4, 20)
	H.fit(item.NameL, { item.NameL.Text }, lw - rankW - 4, m.Name, m.NameMin)
	place(item.RankL, pad + lw - rankW, top, rankW, 20)
	item.RankL.TextSize = m.Rank
	item.RankL.TextXAlignment = Enum.TextXAlignment.Right
	H.layoutBar(item, pad, top + 24, lw, 10)
	item.Next.Visible, item.Cost.Visible, item.Time.Visible = false, false, false
	item.Now.Visible = true
	place(item.Now, pad, top + 40, lw, 20)
	item.Now.TextSize = m.Line
	place(item.Action, bx, (h - m.BtnH) / 2, m.BtnW, m.BtnH)
	place(item.MaxTag, bx, (h - m.BtnH) / 2, m.BtnW, m.BtnH)
	item.MaxTag.TextSize = m.MaxText
	item.Lay = m
end

function H.layoutConfirm()
	if not U.Confirm then
		return
	end
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local inset = 58
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	place(U.Shade, 0, 0, vp.X, vp.Y)
	local scale = Theme.ScreenFactor(vp.Y)
	local freeW, freeH = vp.X - 24, vp.Y - inset - 16
	local w = math.min(K.CONFIRM_W, math.floor(freeW / scale))
	local pad = 24
	local textW = w - 2 * pad
	local textH = H.wrappedHeight(U.ConfirmText.Text, 20, U.ConfirmText.Font, textW)
	local titleH = 40
	local btnY = pad + titleH + 12 + textH + 16
	local h = btnY + 56 + pad
	if h * scale > freeH then
		scale = math.max(0.5, freeH / h)
	end
	U.ConfirmFit.Scale = scale
	place(U.Confirm, (vp.X - w * scale) / 2, inset + (vp.Y - inset - h * scale) / 2, w, h)
	place(U.ConfirmTitle, pad, pad - 4, textW, titleH)
	H.fit(U.ConfirmTitle, { U.ConfirmTitle.Text }, textW, 30, 22)
	place(U.ConfirmText, pad, pad + titleH + 12, textW, textH)
	U.ConfirmText.TextSize = 20
	local noW = 190
	local yesW = math.min(260, textW - noW - 14)
	local bx = (w - yesW - noW - 14) / 2
	place(U.ConfirmYes, bx, btnY, yesW, 56)
	place(U.ConfirmNo, bx + yesW + 14, btnY, noW, 56)
	H.fit(U.ConfirmYes, { U.ConfirmYes.Text }, yesW - 16, 23, 18)
	H.fit(U.ConfirmNo, { U.ConfirmNo.Text }, noW - 16, 22, 18)
end

----------------------------------------------------------------------
-- Paint
----------------------------------------------------------------------
function H.chipText(level, used, slots)
	if level < 1 then
		return S.Portrait and "Not built yet" or "No Training Place yet"
	end
	if S.Mode == "Phone" then
		return used .. " / " .. slots .. " spots"
	end
	return "Training spots: " .. used .. " / " .. slots .. " in use"
end

function H.levelText(key, def)
	local lv = Bits.petLevel(key)
	local text = "Lv " .. lv .. " / " .. Bits.levelCap(key, def)
	local stage = Bits.stage(key)
	if stage > 0 then
		text = text .. ' <font color="#FFD34D">' .. string.rep(G.Star, math.min(2, stage)) .. "</font>"
	end
	return text
end

function H.paint()
	if not S.Built then
		return
	end
	if S.Key and not H.valid(S.Key) then
		S.Key = nil -- the selected pet left the collection: the empty state
	end
	local home = Bits.homeData()
	local level = H.placeLevel(home)
	local used, slots = H.used(), H.slots(home)
	local hasPets = #H.order() > 0
	U.Chip.Text = H.chipText(level, used, slots)
	U.Chip.TextColor3 = (level >= 1 and slots > 0 and used >= slots) and C.Gold or C.White
	H.layoutHeader()
	-- the pet column
	for _, o in ipairs({ U.Card.Root, U.Name, U.Level, U.Prev, U.Change, U.Next, U.SkillsFrame }) do
		o.Visible = hasPets
	end
	U.Note.Visible = hasPets and S.NoteOn == true
	H.paintPet()
	for _, skill in ipairs(SKILLS) do
		safe("skill " .. skill.Id, H.paintSkill, U.Skills[skill.Id])
	end
	-- the empty texts: no pets (the body), no Training Place (the mats band)
	local spec, text = nil, nil
	if not hasPets then
		spec, text = S.EmptyBody, TEXTS.NoPets
	elseif level < 1 then
		spec, text = S.EmptyBand, TEXTS.NoPlace
	end
	U.Empty.Visible = spec ~= nil
	if spec then
		place(U.Empty, spec[1], spec[2], spec[3], spec[4])
		U.Empty.TextSize = spec[5]
		U.Empty.Text = text
	end
end

function H.paintPet()
	local key = S.Key
	local def = key and H.def(key) or nil
	local phone = S.Mode == "Phone"
	if not def then
		U.Card.SetColor(C.Grey)
		U.Prompt.Visible = true
		U.Prompt.Text = '<font size="' .. (phone and 34 or 64) .. '">' .. G.Plus .. "</font>\nPick a pet"
		U.Rarity.Visible, U.Element.Visible = false, false
		U.Name.Text, U.Level.Text = "", ""
		U.Change.Text = "Pick a pet"
		H.showView(nil)
	else
		local rarityColor = CloudUI.RarityColor(def.Rarity)
		U.Card.SetColor(rarityColor)
		U.Prompt.Visible = false
		-- the rarity chip
		U.Rarity.Visible = true
		U.Rarity.Text = string.upper(tostring(def.Rarity or ""))
		U.Rarity.BackgroundColor3 = Theme.Darken(rarityColor, 0.25)
		local rw = math.ceil(H.width(U.Rarity.Text, U.Rarity.TextSize, U.Rarity.Font)) + (phone and 14 or 22)
		U.Rarity.Size = UDim2.fromOffset(rw, U.Rarity.Size.Y.Offset)
		-- the element chip (PC: there is room)
		local elements = Bits.elementsOf(def)
		local el = elements[1]
		local info = el and Config.Elements and Config.Elements.Info and Config.Elements.Info[el]
		U.Element.Visible = (not S.CardSmall) and info ~= nil
		if U.Element.Visible then
			U.Element.Text = el
			U.ElementStroke.Color = info.Color or C.White
			U.Element.TextColor3 = Theme.Lighten(info.Color or C.White, 0.3)
			local ew = math.ceil(H.width(el, U.Element.TextSize, U.Element.Font)) + 22
			place(U.Element, (S.CardW or 200) - 8 - ew, 8, ew, U.Element.Size.Y.Offset)
		end
		-- the name and the level
		local M = H.metrics()
		local name = Bits.displayName(key, def)
		local nameMax = S.Portrait and 18 or M.NameText
		local nameMin = S.Portrait and 15 or M.NameMin
		local last = name:match("(%S+)$") or name
		H.fit(U.Name, { name, last }, U.Name.Size.X.Offset - 4, nameMax, nameMin)
		U.Name.TextColor3 = Theme.Lighten(rarityColor, 0.3)
		U.Level.Text = H.levelText(key, def)
		U.Change.Text = (phone and "Change") or "Change pet"
		H.showView(key, def, Bits.stage(key))
	end
	H.fit(U.Change, { U.Change.Text, "Pick" }, U.Change.Size.X.Offset - 22, phone and K.PHONE.ChangeText or K.PC.ChangeText, phone and 15 or 18)
end

-- the pet viewport of key at its stage (cached per key and stage; parked ones are hidden and skip work)
function H.showView(key, def, stage)
	local id = key and (key .. "#" .. tostring(stage or 0)) or nil
	if S.ViewId == id and (not id or (U.Views[id] and U.Views[id].Handle.Frame.Parent == U.Art)) then
		return
	end
	if S.ViewId and U.Views[S.ViewId] then
		U.Views[S.ViewId].Handle.Frame.Parent = U.Cache
	end
	S.ViewId = nil
	if not id then
		return
	end
	local v = U.Views[id]
	if not v then
		local ok, handle = pcall(CloudUI.PetViewport, U.Art, def, UDim2.fromScale(1, 1), {
			Detail = "Low", Spin = "sway", Evolved = (stage or 0) >= 1 and stage or nil, ZIndex = 5,
		})
		if not (ok and type(handle) == "table" and handle.Frame) then
			warnOnce("viewport", handle)
			return
		end
		v = { Handle = handle }
		U.Views[id] = v
	end
	v.Handle.Frame.Parent = U.Art
	v.Used = os.clock()
	S.ViewId = id
	H.trimViews()
end

function H.trimViews()
	local list = {}
	for id, v in pairs(U.Views) do
		if id ~= S.ViewId then
			list[#list + 1] = { Id = id, Used = v.Used or 0 }
		end
	end
	table.sort(list, function(a, b)
		return a.Used < b.Used
	end)
	local extra = #list + 1 - K.VIEW_CACHE
	for i = 1, extra do
		local v = U.Views[list[i].Id]
		U.Views[list[i].Id] = nil
		if v then
			pcall(v.Handle.Destroy)
		end
	end
end

function H.paintSkill(item)
	local id = item.Id
	local st = H.skillState(id)
	S.States[id] = st
	item.Root:SetAttribute("State", st)
	local key = S.Key
	local def = key and H.valid(key) and H.def(key) or nil
	local small = S.Card == "phone" or S.Card == "row" or S.Card == "tight"
	local m = item.Lay or K.CARD.full
	local maxRank = H.maxRank()
	local rank = def and H.rank(key, id) or 0
	local job = def and Bits.job(key) or nil
	local eff = EFFECT[id]
	local nowPct, nextPct = H.pct(id, rank), H.pct(id, rank + 1)
	local cost = def and (tonumber(Bits.catalogCall("TrainCost", def, rank + 1)) or 0) or 0
	local seconds = tonumber(Bits.catalogCall("TrainSeconds", rank + 1)) or 60
	local noPet = def == nil
	-- the card's colour
	local color = item.Color
	if st == "Training" then
		color = C.Purple
	elseif noPet or st == "NoPlace" or st == "Match" then
		color = C.Grey
	end
	item.Card.SetColor(color)
	-- the rank and the bar
	if noPet then
		item.RankL.Text = ""
	elseif small then
		item.RankL.Text = rank .. "/" .. maxRank
	else
		item.RankL.Text = "Rank " .. rank .. " / " .. maxRank
	end
	local trainingSeg = (st == "Training" and job) and math.floor(tonumber(job.Rank) or (rank + 1)) or nil
	for i, seg in ipairs(item.Segs) do
		local lit = (not noPet) and i <= rank
		seg:SetAttribute("Lit", lit)
		if lit then
			seg.BackgroundColor3 = Theme.Lighten(item.Color, 0.1)
		elseif trainingSeg == i then
			seg.BackgroundColor3 = C.Purple
		else
			seg.BackgroundColor3 = C.SegOff
		end
	end
	-- the texts
	local nowText, nextText, costText, timeText = "", "", "", ""
	local nextColor, timeColor = C.Good, C.Muted
	local left = job and math.max(0, (tonumber(job.Ends) or 0) - H.now()) or 0
	local jobRank = job and math.floor(tonumber(job.Rank) or (rank + 1)) or (rank + 1)
	-- rank 0 has no bonus yet ("-0% damage taken" would read oddly)
	local nowShort = rank > 0 and (eff.Sign .. nowPct .. "%") or "0%"
	local words = rank > 0 and (eff.Sign .. nowPct .. "% " .. eff.Words) or "no bonus yet"
	if noPet then
		nowText = ""
	elseif st == "Training" then
		nowText = "Now: " .. words
		nextText = "Rank " .. jobRank .. ": " .. eff.Sign .. H.pct(id, jobRank) .. "%"
		timeText = "Rank " .. jobRank .. " " .. G.Dot .. " " .. H.clock(left) .. " left"
		timeColor = Theme.Lighten(C.Purple, 0.45)
	elseif st == "Max" then
		nowText = "Now: " .. words
		nextText, nextColor = "Top rank!", C.Gold
	else
		nowText = "Now: " .. words
		nextText = "Rank " .. (rank + 1) .. ": " .. eff.Sign .. nextPct .. "%"
		costText = H.commas(cost)
		timeText = H.minutes(seconds)
	end
	if small then
		-- one line: "+16% -> +20% - 5 min" / "Rank 4 - 2:10 left" / "+40% - top rank"
		local line = ""
		if st == "Training" then
			line = timeText
		elseif st == "Max" then
			line = nowShort .. " " .. G.Dot .. " top rank"
		elseif not noPet then
			line = nowShort .. " " .. G.Arrow .. " " .. eff.Sign .. nextPct .. "% " .. G.Dot .. " " .. timeText
		end
		H.fit(item.Now, { line, (line:gsub(" " .. G.Dot .. " .*$", "")) }, item.Now.Size.X.Offset - 2, m.Line, m.Line)
		item.Now.TextColor3 = st == "Training" and timeColor or C.White
	else
		local fits = { nowText }
		if not noPet and rank > 0 then
			if eff.Short then
				fits[#fits + 1] = "Now: " .. eff.Sign .. nowPct .. "% " .. eff.Short
			end
			fits[#fits + 1] = "Now: " .. nowShort
		end
		H.fit(item.Now, fits, item.Now.Size.X.Offset - 2, m.Line, math.max(18, m.Line - 2))
		item.Now.TextColor3 = C.White
		item.Next.Text, item.Next.TextColor3 = nextText, nextColor
		item.Cost.Text = costText
		item.Cost.TextColor3 = st == "Short" and C.Bad or C.Good
		item.Time.Text, item.Time.TextColor3 = timeText, timeColor
	end
	-- the button
	local maxed = st == "Max"
	item.Action.Visible = not maxed
	item.MaxTag.Visible = maxed
	if not maxed then
		local text, colorName, disabled = "TRAIN", "Green", false
		if st == "Ready" or st == "Short" then
			text = small and ("TRAIN " .. H.commas(cost)) or "TRAIN"
			disabled = st == "Short"
		elseif st == "Training" then
			text, colorName = "STOP", "Pink"
		elseif st == "Busy" then
			text, disabled = "Busy training", true
		elseif st == "Full" then
			text, disabled = "Spots full", true
		elseif st == "Match" then
			text, disabled = "In a match", true
		elseif st == "NoPet" then
			text, disabled = "Pick a pet first", true
		elseif st == "NoPlace" then
			text, disabled = "No Training Place", true
		end
		if item.Action:GetAttribute("Color") ~= colorName then
			item.Action:SetAttribute("Color", colorName)
		end
		if item.Action:GetAttribute("Disabled") ~= disabled then
			item.Action:SetAttribute("Disabled", disabled)
		end
		H.fit(item.Action, { text, (text:gsub(" %$.*$", "")) }, item.Action.Size.X.Offset - 22, m.BtnText or 22, m.BtnMin or 18)
	end
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------
function H.fire(gapKey, name, ...)
	local now = os.clock()
	if S.Last[gapKey] and now - S.Last[gapKey] < K.FIRE_GAP then
		return false
	end
	local ok, remote = pcall(Remotes.Get, name)
	if not ok or not remote then
		warnOnce("remote " .. name, remote)
		return false
	end
	S.Last[gapKey] = now
	local args = { ... }
	local n = select("#", ...)
	return (pcall(function()
		remote:FireServer(unpack(args, 1, n))
	end))
end

function H.hint(text)
	if not (U.Hint and S.Open) then
		return
	end
	S.HintToken = S.HintToken + 1
	local mine = S.HintToken
	U.Hint.Text = tostring(text)
	U.Hint.Visible = true
	task.delay(K.HINT_SECONDS, function()
		if S.HintToken == mine and U.Hint then
			U.Hint.Visible = false
		end
	end)
end

function H.onAction(stat)
	if not S.Open then
		return
	end
	local st = H.skillState(stat)
	if st == "Ready" then
		H.askTrain(S.Key, stat)
	elseif st == "Training" then
		H.askStop(S.Key)
	elseif HINTS[st] then
		H.hint(HINTS[st])
	end
end

function H.showConfirm(spec)
	if not U.Confirm then
		return
	end
	if S.Sheet then
		H.closeSheet() -- the sheet and the confirm are never up together
	end
	S.Confirm = spec
	U.ConfirmTitle.Text = spec.Title or ""
	U.ConfirmTitle.TextColor3 = spec.Color or C.Good
	U.ConfirmStroke.Color = spec.Color or C.Good
	U.ConfirmText.Text = spec.Text or ""
	U.ConfirmYes.Text = spec.YesText or "Yes"
	CloudUI.SetStyle(U.ConfirmYes, spec.Style or "Green")
	U.ConfirmNo.Text = spec.NoText or "Not now"
	H.layoutConfirm()
	U.Shade.Visible = true
	U.Confirm.Visible = true
	U.ConfirmPop.Scale = 0.9
	Util.Tween(U.ConfirmPop, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	H.syncBack()
end

function H.closeConfirm()
	S.Confirm = nil
	if U.Confirm then
		U.Confirm.Visible = false
		U.Shade.Visible = false
	end
	H.syncBack()
end

-- TRAIN asks first (CareController's texts of today)
function H.askTrain(key, stat)
	local def = H.valid(key) and H.def(key) or nil
	if not def or H.inMatch() then
		return
	end
	local rank = H.rank(key, stat) + 1
	local cost = tonumber(Bits.catalogCall("TrainCost", def, rank)) or 0
	local seconds = tonumber(Bits.catalogCall("TrainSeconds", rank)) or 60
	local name = Bits.displayName(key, def)
	H.showConfirm({
		Title = G.Muscle .. " Train " .. H.skillName(stat) .. "?",
		Text = name .. " goes to Rank " .. rank .. " " .. H.skillName(stat) .. " for " .. H.money(cost) .. ". It takes "
			.. H.minutes(seconds) .. ". " .. name .. " rests at home until it's done, then comes back by itself.",
		YesText = "Train " .. H.money(cost),
		Style = "Green",
		Color = Theme.Lighten(C.Good, 0.1),
		Yes = function()
			H.fire("train", "PetCare", "Train", key, stat)
		end,
	})
end

-- STOP asks first: the Cash comes back when the job was paid this Prestige (Job.Paid > 0)
function H.askStop(key)
	local def = H.valid(key) and H.def(key) or nil
	local job = def and Bits.job(key) or nil
	if not job then
		return
	end
	local paid = tonumber(job.Paid) or 0
	H.showConfirm({
		Title = "Stop training?",
		Text = (paid > 0 and "You get the Cash back, no rank. " or "No rank and no Cash back (it was paid before your Prestige). ")
			.. Bits.displayName(key, def) .. " comes back to you right away.",
		YesText = "Stop training",
		NoText = "Keep training",
		Style = "Pink",
		Color = Color3.fromRGB(255, 160, 200),
		Yes = function()
			H.fire("trainstop", "PetCare", "TrainStop", key)
		end,
	})
end

----------------------------------------------------------------------
-- The picker sheet (UI/PetPicker, Train context)
----------------------------------------------------------------------
function H.openSheet()
	if not S.Open or H.inMatch() then
		return
	end
	if #H.order() == 0 then
		return
	end
	H.closeConfirm()
	S.SheetToken = S.SheetToken + 1
	local mine = S.SheetToken
	local ok = PetPicker.Open({
		Context = "Train",
		Title = "Pick a pet to train",
		Selected = S.Key,
		OnPick = function(key)
			if S.Open then
				TrainController.Select(key)
			end
		end,
		OnClose = function()
			if S.SheetToken == mine then
				S.Sheet = false
			end
		end,
	})
	S.Sheet = ok == true
	H.syncBack()
end

function H.closeSheet()
	if S.Sheet then
		S.Sheet = false
		S.SheetToken = S.SheetToken + 1
		safe("sheet close", PetPicker.Close)
	end
end

----------------------------------------------------------------------
-- One window at a time, the touch controls, the menu column, Esc / B
----------------------------------------------------------------------
function H.closeOthers()
	for _, name in ipairs({ "MenuController", "IndexController", "FusionController", "DailyController" }) do
		local mod = H.controller(name)
		if mod and type(mod.Close) == "function" then
			safe("close " .. name, mod.Close)
		end
	end
	local care = H.controller("CareController")
	if care and type(care.CloseOwn) == "function" then
		safe("close care", care.CloseOwn)
	end
	if PetPicker.IsOpen() and not S.Sheet then
		safe("close sheet", PetPicker.Close) -- another window's sheet
	end
end

function H.notifyCare(open)
	local care = H.controller("CareController")
	if care and type(care.NotifyTrain) == "function" then
		safe("notify care", care.NotifyTrain, open)
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
		safe("touch", menu.SetTouchHidden, "Train", want)
	end
end

function H.coverColumn()
	local menu = H.controller("MenuController")
	if menu and type(menu.SetColumnCovered) == "function" then
		safe("cover", menu.SetColumnCovered, (S.Open and S.Rect) and S.Rect.x or nil, "Train")
	end
	H.syncTouch()
end

-- Esc / B: the confirm first, then our sheet, then the window
function H.back()
	if S.Confirm then
		H.closeConfirm()
	elseif S.Sheet and PetPicker.IsOpen() then
		H.closeSheet()
	elseif S.Open then
		TrainController.Close()
	end
end

function H.syncBack()
	local want = S.Open or S.Confirm ~= nil
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

function H.refreshSoon()
	if S.RefreshPending then
		return
	end
	S.RefreshPending = true
	task.defer(function()
		S.RefreshPending = false
		if S.Open then
			safe("refresh", H.paint)
		end
	end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function TrainController.IsOpen()
	return S.Open or S.Confirm ~= nil
end

function TrainController.Key()
	return S.Key
end

function TrainController.Layout()
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

function TrainController.SkillState(stat)
	if not EFFECT[stat] then
		return nil
	end
	return H.skillState(stat)
end

function TrainController.Select(key)
	if not H.valid(key) then
		return false
	end
	S.Key = key
	if S.Open then
		safe("paint", H.paint)
	end
	return true
end

function TrainController.Step(dir)
	local order = H.order()
	local n = #order
	if n == 0 then
		return false
	end
	local back = (tonumber(dir) or 1) < 0
	local index = nil
	for i, key in ipairs(order) do
		if key == S.Key then
			index = i
			break
		end
	end
	local key
	if not index then
		key = back and order[n] or order[1]
	else
		key = order[((index - 1 + (back and -1 or 1)) % n) + 1]
	end
	return TrainController.Select(key)
end

function TrainController.DropReturn()
	S.ReturnTo = nil
	S.BackTo = nil
end

function TrainController.Open(args)
	if not initialized then
		TrainController.Init()
	end
	args = type(args) == "table" and args or {}
	if H.inMatch() or not H.ensureGui() then
		return false
	end
	H.build()
	local wasOpen = S.Open
	if not wasOpen then
		H.closeOthers()
		S.BackTo = nil
		S.ReturnTo = type(args.ReturnTo) == "table" and args.ReturnTo or nil
	end
	if H.valid(args.Key) then
		S.Key = args.Key
	elseif not wasOpen or not H.valid(S.Key) then
		S.Key = H.firstTraining()
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
		local mine = S.Token
		task.spawn(function()
			while S.Open and S.Token == mine do
				task.wait(K.TICK)
				if S.Open and S.Token == mine then
					safe("tick", H.paint)
				end
			end
		end)
		H.notifyCare(true)
	end
	-- no pet chosen: the sheet opens by itself (a Training Place and a pet exist)
	if not S.Key and not S.Sheet and H.placeLevel(Bits.homeData()) >= 1 and #H.order() > 0 then
		H.openSheet()
	end
	return true
end

function TrainController.Close()
	H.closeConfirm()
	H.closeSheet()
	if not S.Open then
		return
	end
	S.Open = false
	S.Token = S.Token + 1
	local mine = S.Token
	local back = S.ReturnTo
	S.ReturnTo = nil
	S.HintToken = S.HintToken + 1
	if U.Hint then
		U.Hint.Visible = false
	end
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
	H.notifyCare(false)
	if back then
		-- came from the Pets window: back to it next, unless what closed this one takes over (DropReturn)
		S.BackTo = back
		task.defer(function()
			if S.BackTo == back then
				S.BackTo = nil
				local pets = H.controller("PetsController")
				if pets and type(pets.Open) == "function" and not H.inMatch() then
					safe("back to pets", pets.Open, back)
				end
			end
		end)
	end
end

function TrainController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	H.ensureGui()
	State.Changed:Connect(function()
		if S.Open then
			H.refreshSoon()
		end
	end)
	for _, name in ipairs({ "CashChanged", "BerriesChanged" }) do
		local signal = State[name]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function()
				if S.Open then
					H.refreshSoon()
				end
			end)
		end
	end
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if H.inMatch() then
				TrainController.DropReturn()
				TrainController.Close()
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and (S.Open or S.Confirm) then
			safe("back", H.back)
		end
	end)
end

return TrainController
