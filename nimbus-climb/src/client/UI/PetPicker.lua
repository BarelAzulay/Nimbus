-- PetPicker (client UI, gui-redo Task 6; docs/superpowers/specs/2026-11-06-window-redo-design.md 5.1 / 5.2): the ONE
-- full-screen pet picker sheet. The Training Place (TrainController) and the Fusion Machine (FusionController) open it over
-- their own window; it reads State / PetBits / PetKeys and never sends a remote.
--
--   PetPicker.Open(spec) -> boolean   spec = { Context = "Train" | "Upgrade" | "Mix", Title = string, Selected = key | nil
--                                     (outlined gold), Blocked = { [key] = word } | nil (dimmed with that word, not pickable),
--                                     OnPick = function(key) | nil (called once; the sheet closes first), OnClose =
--                                     function(picked) | nil }. false only without a gui or a valid Context (an empty list
--                                     still opens and says so). Opening over an open sheet closes that one first (OnClose(false)).
--   PetPicker.Close()                 closes without a pick: OnClose(false). The opener's Close calls it too.
--   PetPicker.IsOpen() -> boolean     PetPicker.Layout() -> "PC" | "Phone"
--   PetPicker.Entries(context) -> { entry... }   pure over State. entry = { Key, Def, Name, Level, Stage, Rarity, RarityOrder,
--                                     Copies, Team (the slot in the active preset) | nil, Job = { Stat, Ends, Slot } | nil, Ready
--                                     (Upgrade: Copies >= TycoonCatalog.Fusion.Copies), Hybrid, Blocked = "Training" | nil }.
--                                     Train lists every owned key; Upgrade the regular keys that can still go up a finish (no
--                                     hybrid, no Rainbow); Mix the regular keys. Blocked: Upgrade a key in training or whose
--                                     next-finish key is in training, Mix a key in training (the server refuses both).
--   PetPicker.Sorted(context, entries, sortId, filterId, query) -> entries   pure (the Training window's arrows use it): the
--                                     filter, the case-insensitive plain search of the name (string.find plain), the sort
--   PetPicker.Sorts[context], PetPicker.Filters[context]   { { Id, Label }... } (the first is the default)
--   Tests: PetPicker.Shown() -> { key... } (the cards in display order), SetQuery(text), SetSort(id), SetFilter(id),
--          Pick(key) -> boolean (the tap path: false when closed, blocked, gone or not shown)
-- The sheet binds no Esc / gamepad B: the opener's back handler calls Close() while IsOpen(), else closes itself. It does not
-- fire MenuController.WindowOpened (it is part of the window that opened it); entering a match closes it.
--
-- Screen: ScreenGui "NimbusPetPicker" (DisplayOrder 24, IgnoreGuiInset = true): Shade (dims the screen under the top bar,
-- swallows taps) and Window_PetPicker (NeonKit.BigRect: 1440x920 at 1080p, 820x330 at scale 1 on an 844x390 phone; UIScale
-- "Fit") > Panel (UIScale "Pop": the open tween) > Header (Icon, Title, CloseButton), Body > Search (TextBox), SortButton
-- ("Sort: Ready first" + a down arrow; it cycles the context's sorts), Filter_<Id> chips (attribute Selected), Grid (the only
-- ScrollingFrame) > Card_<key> (attributes Selected, Blocked, Dim, Ready; Art, Level "Lv 34" + a gold star per stage, Badge
-- (Train: a gold star in the team; Upgrade "x5", green when Ready; Mix "x2"), Name (TextService-measured: the whole name,
-- else a Golden / Rainbow copy's "Golden Owl", else the last word), Rarity (PC), TrainChip "Training 3:10" (Train, live),
-- Shade + BlockWord), Empty (EmptyText, ClearButton), HintLine (3 s: why a blocked card cannot be picked). ViewCache
-- (hidden) parks cached viewports. The window is a MouseLock hold while shown (the cursor is free).
--   Phone (scale 1): header 50, X 44; search 220 x 44, sort 170 x 44, chips 44 tall (Train shows its first three), the row
--     wrapping where the box is narrower (portrait: the search takes the whole first row); the grid 10 px under the last row
--     (y 58 on one row), cards >= 124 x 100 (art 56), 6 a row at 820.
--   PC: header 76, X 56; search 460 x 60, sort 280 x 60, chips 50 tall on the first row when they end at least 24 px before
--     the body's right edge, else on a row at y 92 with the grid from y 166 (else y 100); cards >= 180 x 226 (7 a row at 1080p).
--   Both: the cards fill the grid's width (as many as fit at the smallest size, then widened to fill).
-- Viewports: only the cards that intersect the grid's visible window hold one (CloudUI.PetViewport, Low, still); a card that
-- scrolls out parks its viewport in ViewCache (clones cached per key, rebuilt on a new stage, at most CACHE_MAX kept), new
-- ones are built under BUILD_BUDGET seconds a frame (at least one, at most BUILD_MAX) on one Heartbeat connection that lives
-- while the sheet is open. State.Changed re-lists the open sheet: a key that left the collection loses its card, can never be
-- handed to OnPick, and drops the Selected mark. Sort and filter are kept per context for the session; the search starts
-- empty on every Open.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles; glyphs are UTF-8 byte escapes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7b) the picker's icons

local UI = script.Parent
local Client = UI.Parent
local CloudUI = require(UI:WaitForChild("CloudUI"))
local NeonKit = require(UI:WaitForChild("NeonKit"))
local Bits = require(UI:WaitForChild("PetBits"))
local State = require(Client:WaitForChild("State"))

local PetPicker = {}

local K = {
	DISPLAY_ORDER = 24,
	RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1440, Y1 = 920 },
	MARGIN = 12,
	PHONE_W = 900,
	SHORT = 560,
	PC_MIN_H = 600,
	PC_MAX_W = 0.76,
	BUILD_BUDGET = 0.004, -- seconds of viewport building a frame (the first one always)
	BUILD_MAX = 4,
	CACHE_MAX = 48, -- cached viewports kept (shown + parked)
	TICK = 0.25, -- seconds between two Training chip refreshes
	HINT_SECONDS = 3,
	OPEN_TIME = 0.22,
	OPEN_FROM = 0.92,
	SHADE = 0.55,
	PHONE_FILTERS = 3,
	PHONE = {
		Header = 50, Close = 44, CloseY = 3, HeadPad = 10, Icon = 36, IconText = 24, TitleText = 20, TitleMin = 16,
		Pad = 10, RowY = 4, Row = 44, RowGap = 8, Gap = 8, ChipH = 44, ChipGap = 6, ChipText = 15, SearchW = 220, SortW = 170,
		SortText = 15, SortMin = 15, SearchText = 15, GridGap = 10, Scroll = 6, CardW = 124, CardH = 100, CardGap = 8,
		Art = 56, ArtY = 6, Text = 15, ChipRowH = 22, NameH = 20, Corner = 12, Hint = 15, Empty = 18, ClearW = 160,
		ClearH = 44, Block = 15,
	},
	PC = {
		Header = 76, Close = 56, CloseY = 10, HeadPad = 24, Icon = 52, IconText = 36, TitleText = 34, TitleMin = 24,
		Pad = 30, RowY = 18, Row = 60, RowGap = 14, Gap = 16, ChipH = 50, ChipGap = 10, ChipText = 20, SearchW = 460,
		SortW = 280, SortText = 22, SortMin = 18, SearchText = 22, Row2Y = 92, GridY1 = 100, GridY2 = 166, ChipEnd = 24,
		Scroll = 10, CardW = 180, CardH = 226, CardGap = 14, Art = 120, ArtY = 12, Text = 18, NameText = 20, ChipRowH = 30,
		NameH = 28, RarityH = 24, Corner = 14, Hint = 20, Empty = 24, ClearW = 200, ClearH = 56, Block = 22,
	},
	-- the chips' design widths (the mock's), widened when the measured label needs more
	CHIP_W = {
		PC = { All = 90, Team = 110, Training = 150, Ready = 110, Rare = 190, Epic = 180 },
		Phone = { All = 64, Team = 74, Training = 104, Ready = 84, Rare = 124, Epic = 124 },
	},
}

PetPicker.Sorts = {
	Train = { { Id = "Default", Label = "Training first" }, { Id = "Level", Label = "Level" }, { Id = "Rarity", Label = "Rarity" }, { Id = "Name", Label = "Name" } },
	Upgrade = { { Id = "Default", Label = "Ready first" }, { Id = "Rarity", Label = "Rarity" }, { Id = "Level", Label = "Level" }, { Id = "Name", Label = "Name" } },
	Mix = { { Id = "Default", Label = "Rarity" }, { Id = "Level", Label = "Level" }, { Id = "Name", Label = "Name" }, { Id = "Team", Label = "Team first" } },
}
PetPicker.Filters = {
	Train = { { Id = "All", Label = "All" }, { Id = "Team", Label = "Team" }, { Id = "Training", Label = "Training" }, { Id = "Rare", Label = "Rare and up" }, { Id = "Epic", Label = "Epic and up" } },
	Upgrade = { { Id = "All", Label = "All" }, { Id = "Ready", Label = "Ready" }, { Id = "Team", Label = "Team" } },
	Mix = { { Id = "All", Label = "All" }, { Id = "Team", Label = "Team" }, { Id = "Rare", Label = "Rare and up" } },
}
-- the short sort words a narrow sort button falls back to
local SHORT = { ["Training first"] = "Training", ["Ready first"] = "Ready", ["Team first"] = "Team" }
local FILTER_IDS = { "All", "Team", "Training", "Ready", "Rare", "Epic" }
local FILTER_LABELS = { All = "All", Team = "Team", Training = "Training", Ready = "Ready", Rare = "Rare and up", Epic = "Epic and up" }

local Colors = Theme.Colors
local C = {
	White = Colors.White,
	Ink = Colors.TextStroke or Colors.Ink,
	Navy = Color3.fromRGB(11, 16, 48),
	Well = Color3.fromRGB(20, 26, 64),
	Muted = Color3.fromRGB(154, 165, 204),
	Gold = Color3.fromRGB(255, 211, 77),
	Purple = Color3.fromRGB(106, 63, 184),
	Ready = Color3.fromRGB(31, 138, 60),
	Count = Color3.fromRGB(8, 12, 40),
	Accent = { Train = Color3.fromRGB(228, 104, 96), Upgrade = Color3.fromRGB(155, 107, 255), Mix = Color3.fromRGB(155, 107, 255) },
}
-- (kit-b U7b) PixelIcons, not emoji: the team star, the sort arrow, the search glass, the header's icon per context
local ICON = { Star = "star", Down = "down", Glass = "glass", Context = { Train = "weight", Upgrade = "sparkle", Mix = "sparkle" } }
local LEVEL_STAR = 20 -- px a level line's evolution star takes (18 + its cell gap)

local H = {}
local U = { Cards = {}, Chips = {}, Views = {} } -- widgets; Views[key] = { Handle, Stage } (cached viewports)
local S = {
	Open = false,
	Built = false,
	Spec = nil,
	Context = nil,
	Selected = nil,
	Query = "",
	Sort = { Train = "Default", Upgrade = "Default", Mix = "Default" },
	Filter = { Train = "All", Upgrade = "All", Mix = "All" },
	Order = {}, -- the shown keys in display order
	Shown = {}, -- [key] = true
	ByKey = {}, -- [key] = entry of the open context
	Mode = "PC",
	Scale = 1,
	ViewDirty = false,
	TickAcc = 0,
	HintToken = 0,
	Silent = false,
	Warned = {},
}

local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[PetPicker] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
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
-- Data (pure over State)
----------------------------------------------------------------------
function H.optional(name)
	local module = Shared:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	return (ok and type(mod) == "table") and mod or nil
end

function H.copiesNeeded()
	local tycoon = H.optional("TycoonCatalog")
	local n = tycoon and type(tycoon.Fusion) == "table" and tonumber(tycoon.Fusion.Copies) or nil
	return n or 3
end

-- { [key] = slot } of the active preset
function H.teamSlots()
	local out = {}
	local ok, teams = pcall(State.Teams)
	if ok and type(teams) == "table" and type(teams.Presets) == "table" then
		local preset = teams.Presets[tonumber(teams.Active) or 1]
		for i, key in ipairs(type(preset) == "table" and preset or {}) do
			if type(key) == "string" and key ~= "" and out[key] == nil then
				out[key] = i
			end
		end
	end
	return out
end

local NEXT_TIER = { Normal = "Golden", Golden = "Rainbow" }

function PetPicker.Entries(context)
	local out = {}
	if not PetPicker.Sorts[context] then
		return out
	end
	local okKeys, keys = pcall(State.Keys)
	if not okKeys or type(keys) ~= "table" then
		return out
	end
	local okMap, growth = pcall(State.PetGrowthMap)
	growth = (okMap and type(growth) == "table") and growth or {}
	local slots = H.teamSlots()
	local need = H.copiesNeeded()
	local seen = {}
	for _, key in ipairs(keys) do
		local copies = type(key) == "string" and not seen[key] and State.OwnedCount(key) or 0
		local parsed = copies > 0 and Bits.parseKey(key) or nil
		if parsed then
			seen[key] = true
			local hybrid = parsed.HybridId ~= nil
			local nextTier = NEXT_TIER[parsed.Tier or "Normal"]
			local listed = context == "Train" or (context == "Mix" and not hybrid) or (context == "Upgrade" and not hybrid and nextTier ~= nil)
			local def = listed and Bits.defOfKey(key) or nil
			if def then
				local g = growth[key]
				local job = type(g) == "table" and type(g.Job) == "table" and g.Job or nil
				local blocked = nil
				if context ~= "Train" and job then
					blocked = "Training"
				elseif context == "Upgrade" and parsed.PetId then
					local nextG = growth[parsed.PetId .. "@" .. nextTier]
					if type(nextG) == "table" and type(nextG.Job) == "table" then
						blocked = "Training"
					end
				end
				out[#out + 1] = {
					Key = key,
					Def = def,
					Name = Bits.displayName(key, def),
					Level = (Bits.petLevel(key)),
					Stage = Bits.stage(key),
					Rarity = def.Rarity,
					RarityOrder = Bits.rarityOrder(def.Rarity),
					Copies = copies,
					Team = slots[key],
					Job = job and { Stat = job.Stat, Ends = tonumber(job.Ends) or 0, Slot = job.Slot } or nil,
					Ready = context == "Upgrade" and copies >= need,
					Hybrid = hybrid,
					Blocked = blocked,
				}
			end
		end
	end
	return out
end

function H.valid(list, id)
	for _, it in ipairs(list or {}) do
		if it.Id == id then
			return true
		end
	end
	return false
end

function H.passes(e, filterId)
	if filterId == "Team" then
		return e.Team ~= nil
	elseif filterId == "Training" then
		return e.Job ~= nil
	elseif filterId == "Ready" then
		return e.Ready == true
	elseif filterId == "Rare" then
		return e.RarityOrder >= Bits.rarityOrder("Rare")
	elseif filterId == "Epic" then
		return e.RarityOrder >= Bits.rarityOrder("Epic")
	end
	return true
end

-- comparers answer true / false, or nil on a tie (the next rule decides; the key is the last)
local CMP = {}
function CMP.rarity(a, b)
	if a.RarityOrder ~= b.RarityOrder then
		return a.RarityOrder > b.RarityOrder
	end
	return nil
end
function CMP.level(a, b)
	if a.Level ~= b.Level then
		return a.Level > b.Level
	end
	return nil
end
function CMP.name(a, b)
	local x, y = tostring(a.Name):lower(), tostring(b.Name):lower()
	if x ~= y then
		return x < y
	end
	return nil
end
function CMP.team(a, b)
	local x, y = a.Team or math.huge, b.Team or math.huge
	if x ~= y then
		return x < y
	end
	return nil
end
-- Train's default: in training (soonest done first), then the team (slot order), then the rest
function CMP.training(a, b)
	local ga = a.Job and 1 or (a.Team and 2 or 3)
	local gb = b.Job and 1 or (b.Team and 2 or 3)
	if ga ~= gb then
		return ga < gb
	end
	if ga == 1 and a.Job.Ends ~= b.Job.Ends then
		return a.Job.Ends < b.Job.Ends
	elseif ga == 2 then
		return CMP.team(a, b)
	end
	return nil
end
function CMP.ready(a, b)
	if (a.Ready == true) ~= (b.Ready == true) then
		return a.Ready == true
	end
	if a.Copies ~= b.Copies then
		return a.Copies > b.Copies
	end
	return nil
end

local CHAINS = {
	Train = { Default = { CMP.training, CMP.rarity, CMP.level, CMP.name }, Level = { CMP.level, CMP.rarity, CMP.name }, Rarity = { CMP.rarity, CMP.level, CMP.name }, Name = { CMP.name } },
	Upgrade = { Default = { CMP.ready, CMP.rarity, CMP.name }, Rarity = { CMP.rarity, CMP.level, CMP.name }, Level = { CMP.level, CMP.rarity, CMP.name }, Name = { CMP.name } },
	Mix = { Default = { CMP.rarity, CMP.level, CMP.name }, Level = { CMP.level, CMP.rarity, CMP.name }, Name = { CMP.name }, Team = { CMP.team, CMP.rarity, CMP.level, CMP.name } },
}

function PetPicker.Sorted(context, entries, sortId, filterId, query)
	local out = {}
	local chains = CHAINS[context]
	if not chains or type(entries) ~= "table" then
		return out
	end
	if not H.valid(PetPicker.Filters[context], filterId) then
		filterId = "All"
	end
	local chain = chains[sortId] or chains.Default
	local q = type(query) == "string" and string.lower(query):match("^%s*(.-)%s*$") or ""
	for _, e in ipairs(entries) do
		if type(e) == "table" and H.passes(e, filterId) and (q == "" or string.find(tostring(e.Name):lower(), q, 1, true) ~= nil) then
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		for _, fn in ipairs(chain) do
			local r = fn(a, b)
			if r ~= nil then
				return r
			end
		end
		return tostring(a.Key) < tostring(b.Key)
	end)
	return out
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
function H.ensureGui()
	if U.Gui and U.Gui.Parent then
		return true
	end
	local player = Players.LocalPlayer
	if not (player and player:FindFirstChildOfClass("PlayerGui")) then
		return false
	end
	U.Gui = CloudUI.NewScreenGui("NimbusPetPicker", K.DISPLAY_ORDER)
	U.Gui.IgnoreGuiInset = true
	S.Built = false
	U.Cards, U.Chips, U.Views = {}, {}, {}
	if not S.Hooked then
		S.Hooked = true
		State.Changed:Connect(function()
			if S.Open then
				safe("relist", H.relist)
			end
		end)
		player:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if player:GetAttribute(Config.Attr.InMatch) == true then
				PetPicker.Close()
			end
		end)
	end
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if S.Open then
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
	local gui = U.Gui
	U.Shade = Util.Create("TextButton", {
		Name = "Shade", Text = "", AutoButtonColor = false, BorderSizePixel = 0, Active = true, Selectable = false,
		BackgroundColor3 = Color3.fromRGB(4, 6, 20), BackgroundTransparency = K.SHADE, Visible = false, Parent = gui,
	})
	local holder = Util.Create("Frame", { Name = "Window_PetPicker", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 2, Parent = gui })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	local panel = Util.Create("Frame", {
		Name = "Panel", BackgroundColor3 = C.Navy, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = holder,
	})
	Theme.Corner(panel, UDim.new(0, 18))
	U.PanelStroke = Theme.Stroke(panel, C.Accent.Train, 3, 0)
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel })
	U.Panel = panel
	-- header: the accent strip, square at the bottom
	local header = Util.Create("Frame", { Name = "Header", BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
	Theme.Corner(header, UDim.new(0, 18))
	U.HeaderGradient = Theme.Gradient(header, C.Accent.Train, C.Accent.Train, 90)
	U.HeaderFoot = Util.Create("Frame", { Name = "HeaderFoot", BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 3, Parent = header })
	U.FootGradient = Theme.Gradient(U.HeaderFoot, C.Accent.Train, C.Accent.Train, 90)
	U.Header = header
	U.Icon = label(header, "Icon", "Title", 36, { ZIndex = 4, TextTruncate = Enum.TextTruncate.None })
	U.Title = Theme.StyleTitle(label(header, "Title", "Title", 34, { ZIndex = 4, TextXAlignment = Enum.TextXAlignment.Left }))
	U.Close = CloudUI.Button({
		Name = "CloseButton", Text = "", Style = "Red", Size = UDim2.fromOffset(44, 44), TextSize = 22, ZIndex = 5,
		Callback = function()
			PetPicker.Close()
		end,
		Parent = header,
	})
	NeonKit.CloseMark(U.Close) -- slop audit 2026-11-12: a drawn X (the U+2715 glyph showed a missing-glyph box)
	-- body
	local body = Util.Create("Frame", { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = panel })
	U.Body = body
	local search = Util.Create("TextBox", {
		Name = "Search", Text = "", PlaceholderText = "Search pets", ClearTextOnFocus = false, BorderSizePixel = 0,
		BackgroundColor3 = C.Well, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3, Parent = body,
	})
	Theme.Style(search, "Body", { Size = 22 })
	search.PlaceholderColor3 = C.Muted
	Theme.Corner(search, UDim.new(0, 12))
	Theme.Stroke(search, Color3.fromRGB(70, 84, 150), 2, 0)
	U.SearchPad = Util.Create("UIPadding", { PaddingLeft = UDim.new(0, 44), PaddingRight = UDim.new(0, 10), Parent = search })
	U.Glass = label(search, "Glass", "Body", 20, { ZIndex = 4, TextTruncate = Enum.TextTruncate.None })
	PixelIcon.Host(U.Glass, ICON.Glass, 18)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		if not S.Silent and S.Open then
			S.Query = search.Text
			safe("search", H.relist, true)
		end
	end)
	U.Search = search
	U.Sort = NeonKit.Button({
		Name = "SortButton", Text = "Sort", Color = Color3.fromRGB(74, 91, 184), Size = UDim2.fromOffset(170, 44), TextSize = 22, ZIndex = 3,
		Callback = function()
			H.cycleSort()
		end,
		Parent = body,
	})
	for _, id in ipairs(FILTER_IDS) do
		local chip = Util.Create("TextButton", {
			Name = "Filter_" .. id, Text = FILTER_LABELS[id], AutoButtonColor = false, BorderSizePixel = 0,
			BackgroundColor3 = C.Well, Visible = false, ZIndex = 3, Parent = body,
		})
		Theme.Style(chip, "Button", { Size = 20 })
		Theme.Corner(chip, UDim.new(0.5, 0))
		local outline = Theme.Stroke(chip, Color3.fromRGB(70, 84, 150), 2, 0)
		chip.Activated:Connect(function()
			PetPicker.SetFilter(id)
		end)
		U.Chips[id] = { Button = chip, Stroke = outline, Glyphs = chip:FindFirstChild("TextOutline") }
	end
	local grid = Util.Create("ScrollingFrame", {
		Name = "Grid", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8, ScrollBarImageColor3 = Color3.fromRGB(200, 210, 240), CanvasSize = UDim2.fromOffset(0, 0),
		ZIndex = 3, Parent = body,
	})
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		S.ViewDirty = true
	end)
	U.Grid = grid
	local empty = Util.Create("Frame", { Name = "Empty", BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 4, Parent = body })
	U.Empty = empty
	U.EmptyText = label(empty, "EmptyText", "Heading", 24, { ZIndex = 5, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
	U.Clear = CloudUI.Button({
		Name = "ClearButton", Text = "Clear", Style = "Blue", Size = UDim2.fromOffset(160, 44), TextSize = 20, ZIndex = 5,
		Callback = function()
			H.clear()
		end,
		Parent = empty,
	})
	U.Hint = label(body, "HintLine", "Heading", 20, {
		Visible = false, ZIndex = 8, BackgroundTransparency = 0.15, BackgroundColor3 = Color3.fromRGB(8, 10, 28), TextWrapped = true,
	})
	Theme.Corner(U.Hint, UDim.new(0, 10))
	U.Cache = Util.Create("Frame", { Name = "ViewCache", BackgroundTransparency = 1, Visible = false, Size = UDim2.fromOffset(10, 10), Parent = holder })
	-- the cursor is free while the sheet is shown (client/MouseLock, as the Pets window)
	local mouseLock = Client:FindFirstChild("MouseLock")
	local okLock, lock = pcall(function()
		return mouseLock and require(mouseLock)
	end)
	if okLock and type(lock) == "table" and type(lock.WatchVisible) == "function" then
		safe("mouse lock", lock.WatchVisible, "Dock:" .. holder.Name, holder)
	end
end

function H.newCard(key)
	local item = { Key = key }
	local b = Util.Create("TextButton", {
		Name = "Card_" .. key, Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = C.White, ZIndex = 3, Parent = U.Grid,
	})
	item.Button = b
	item.Corner = Theme.Corner(b, UDim.new(0, 12))
	item.Stroke = Theme.Stroke(b, C.White, 3, 0)
	item.Stroke.Name = "RarityStroke"
	item.Fill = Theme.Gradient(b, C.Navy, C.Navy, 90)
	item.Art = Util.Create("Frame", { Name = "Art", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = b })
	item.Level = label(b, "Level", "Heading", 18, {
		ZIndex = 5, RichText = true, BackgroundTransparency = 0.35, BackgroundColor3 = C.Count, TextTruncate = Enum.TextTruncate.None,
	})
	Theme.Corner(item.Level, UDim.new(0.5, 0))
	item.Badge = label(b, "Badge", "Heading", 18, { ZIndex = 5, BackgroundTransparency = 1, TextTruncate = Enum.TextTruncate.None })
	Theme.Corner(item.Badge, UDim.new(0.5, 0))
	item.Name = label(b, "Name", "Button", 18, { ZIndex = 5 })
	item.Rarity = label(b, "Rarity", "Label", 18, { ZIndex = 5 })
	item.Chip = label(b, "TrainChip", "Heading", 18, {
		ZIndex = 6, Visible = false, BackgroundTransparency = 0, BackgroundColor3 = C.Purple, TextTruncate = Enum.TextTruncate.None,
	})
	Theme.Corner(item.Chip, UDim.new(0.5, 0))
	item.Shade = Util.Create("Frame", {
		Name = "Shade", BackgroundColor3 = Color3.fromRGB(8, 10, 28), BackgroundTransparency = 0.45, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 7, Parent = b,
	})
	Theme.Corner(item.Shade, UDim.new(0, 12))
	item.Word = label(item.Shade, "BlockWord", "Heading", 18, { ZIndex = 8, Visible = false, Size = UDim2.fromScale(1, 1) })
	b.Activated:Connect(function()
		PetPicker.Pick(key)
	end)
	U.Cards[key] = item
	return item
end

function H.dropView(key)
	local v = U.Views[key]
	if v then
		U.Views[key] = nil
		pcall(v.Handle.Destroy)
	end
end

----------------------------------------------------------------------
-- Text fit (TextService: the real font)
----------------------------------------------------------------------
function H.width(text, size, font)
	local plain = tostring(text):gsub("<[^>]*>", "")
	local ok, v = pcall(function()
		return Theme.Measure(plain, font, size, 4096)
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
			if H.width(t, size, Theme.FontOf(lbl)) <= width then
				lbl.Text, lbl.TextSize = t, size
				return
			end
			size = size - 1
		end
	end
	lbl.Text, lbl.TextSize = texts[#texts], minSize
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
function H.metrics()
	return S.Mode == "Phone" and K.PHONE or K.PC
end

function H.inset()
	local inset = 58
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	return inset
end

-- the filter chips this layout shows for the context
function H.chipIds()
	local out = {}
	for i, f in ipairs(PetPicker.Filters[S.Context] or {}) do
		if not (S.Mode == "Phone" and i > K.PHONE_FILTERS) then
			out[#out + 1] = f.Id
		end
	end
	return out
end

function H.chipWidth(id, M)
	local base = K.CHIP_W[S.Mode == "Phone" and "Phone" or "PC"][id] or 90
	return math.max(base, math.ceil(H.width(FILTER_LABELS[id], M.ChipText, Theme.Fonts.Button)) + 24)
end

function H.layout()
	if not S.Built then
		return
	end
	local r = NeonKit.BigRect(K)
	S.Mode, S.Scale = r.mode, r.scale
	local phone = r.mode == "Phone"
	local M = H.metrics()
	local W = math.floor(r.w / r.scale + 0.5)
	local Hh = math.floor(r.h / r.scale + 0.5)
	place(U.Holder, r.x, r.y, W, Hh)
	U.Fit.Scale = r.scale
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local inset = H.inset()
	place(U.Shade, 0, inset, vp.X, math.max(0, vp.Y - inset))
	-- header
	place(U.Header, 0, 0, W, M.Header)
	place(U.HeaderFoot, 0, M.Header - 18, W, 18)
	place(U.Icon, M.HeadPad, (M.Header - M.Icon) / 2, M.Icon, M.Icon)
	U.Icon.TextSize = M.IconText
	place(U.Close, W - M.HeadPad - M.Close, M.CloseY, M.Close, M.Close) -- (its drawn X scales with it)
	local titleX = M.HeadPad + M.Icon + 8
	local titleW = W - titleX - M.Close - 2 * M.HeadPad
	place(U.Title, titleX, 0, titleW, M.Header)
	H.fit(U.Title, { U.Title.Text }, titleW, M.TitleText, M.TitleMin)
	-- body
	local bodyH = Hh - M.Header
	place(U.Body, 0, M.Header, W, bodyH)
	local chips = H.chipIds()
	local shownChip = {}
	for _, id in ipairs(chips) do
		shownChip[id] = true
	end
	for _, id in ipairs(FILTER_IDS) do
		U.Chips[id].Button.Visible = shownChip[id] == true
	end
	local refilter = false
	if not shownChip[S.Filter[S.Context]] then
		S.Filter[S.Context] = "All" -- the phone hides that chip: show everything rather than an unseen filter
		refilter = true
	end
	U.Search.TextSize = M.SearchText
	U.Search.PlaceholderText = phone and "Search" or "Search pets"
	U.SearchPad.PaddingLeft = UDim.new(0, phone and 34 or 50)
	place(U.Glass, phone and -28 or -42, 0, phone and 24 or 34, M.Row)
	U.Glass.TextSize = phone and 16 or 24
	local gridY
	if phone then
		-- one flowing row (it wraps where the box is narrower; portrait: the search alone on the first row)
		local items = { { U.Search, r.portrait and (W - 2 * M.Pad) or M.SearchW, M.Gap }, { U.Sort, M.SortW, M.Gap } }
		for _, id in ipairs(chips) do
			items[#items + 1] = { U.Chips[id].Button, H.chipWidth(id, M), M.ChipGap }
		end
		local x, y = M.Pad, M.RowY
		for _, it in ipairs(items) do
			if x > M.Pad and x + it[2] > W - M.Pad then
				x, y = M.Pad, y + M.Row + M.RowGap
			end
			place(it[1], x, y, it[2], M.Row)
			x = x + it[2] + it[3]
		end
		gridY = y + M.Row + M.GridGap
	else
		place(U.Search, M.Pad, M.RowY, M.SearchW, M.Row)
		local sortX = M.Pad + M.SearchW + M.Gap
		place(U.Sort, sortX, M.RowY, M.SortW, M.Row)
		local total = 0
		for i, id in ipairs(chips) do
			total = total + H.chipWidth(id, M) + (i > 1 and M.ChipGap or 0)
		end
		local x = sortX + M.SortW + M.Gap
		local y = M.RowY + (M.Row - M.ChipH) / 2
		gridY = M.GridY1
		if x + total > W - M.ChipEnd then
			x, y, gridY = M.Pad, M.Row2Y, M.GridY2
		end
		for _, id in ipairs(chips) do
			local w = H.chipWidth(id, M)
			if x > M.Pad and x + w > W - M.Pad then
				x, y = M.Pad, y + M.ChipH + 10
				gridY = y + M.ChipH + 24
			end
			place(U.Chips[id].Button, x, y, w, M.ChipH)
			x = x + w + M.ChipGap
		end
	end
	for _, id in ipairs(FILTER_IDS) do
		U.Chips[id].Button.TextSize = M.ChipText
	end
	local gridH = math.max(M.CardH, bodyH - gridY - M.Pad)
	place(U.Grid, M.Pad, gridY, W - 2 * M.Pad, gridH)
	U.Grid.ScrollBarThickness = M.Scroll
	place(U.Empty, M.Pad, gridY, W - 2 * M.Pad, gridH)
	place(U.EmptyText, 10, math.max(0, gridH / 2 - M.Empty * 2 - 10), W - 2 * M.Pad - 20, M.Empty * 3)
	U.EmptyText.TextSize = M.Empty
	place(U.Clear, (W - 2 * M.Pad - M.ClearW) / 2, math.max(0, gridH / 2 + M.Empty), M.ClearW, M.ClearH)
	U.Clear.TextSize = phone and 18 or 22
	local hintH = phone and 30 or 40
	place(U.Hint, M.Pad + 20, bodyH - hintH - 8, W - 2 * M.Pad - 40, hintH)
	U.Hint.TextSize = M.Hint
	H.paintSort()
	if refilter then
		H.relist(true)
	else
		H.layoutCards()
	end
end

-- the inside of one card at its size
function H.layoutCard(item, w, h, M)
	local phone = S.Mode == "Phone"
	local art = math.min(M.Art, w - 8)
	place(item.Art, (w - art) / 2, M.ArtY, art, art)
	local pad = phone and 4 or 8
	local text = M.Text
	item.Level.TextSize = text
	local stars = tonumber(item.Level:GetAttribute("Stars")) or 0 -- (kit-b U7b) the stars drawn after the text
	local lw = math.min(w - 2 * pad, H.width(item.Level.Text, text, Theme.FontOf(item.Level)) + (phone and 12 or 16) + (stars > 0 and (stars * LEVEL_STAR + 4) or 0))
	place(item.Level, pad, pad, lw, M.ChipRowH)
	local bw = M.ChipRowH
	local starBadge = item.Badge:GetAttribute("HostMark") ~= nil and item.Badge:GetAttribute("HostMark") ~= ""
	if not starBadge then
		bw = H.width(item.Badge.Text, text, Theme.FontOf(item.Badge)) + (phone and 12 or 16)
	end
	place(item.Badge, w - pad - bw, pad, bw, M.ChipRowH)
	item.Badge.TextSize = starBadge and (phone and 18 or 24) or text
	local nameY, nameSize = h - M.NameH - (phone and 4 or 40), M.NameText or text
	place(item.Name, pad, nameY, w - 2 * pad, M.NameH)
	H.fit(item.Name, item.Names or { "" }, w - 2 * pad - 4, nameSize, nameSize)
	item.Rarity.Visible = not phone
	place(item.Rarity, pad, h - (M.RarityH or 0) - 12, w - 2 * pad, M.RarityH or 0)
	item.Rarity.TextSize = text
	place(item.Chip, phone and 4 or 10, nameY - M.ChipRowH - (phone and 0 or 4), w - (phone and 8 or 20), M.ChipRowH)
	item.Chip.TextSize = text
	item.Word.TextSize = M.Block
	item.Corner.CornerRadius = UDim.new(0, M.Corner)
end

-- positions the shown cards in rows filling the grid's width; the canvas follows
function H.layoutCards()
	local M = H.metrics()
	local gw = U.Grid.Size.X.Offset - M.Scroll - 2
	local gap = M.CardGap
	local n = math.max(1, math.floor((gw + gap) / (M.CardW + gap)))
	local cw = math.floor((gw - (n - 1) * gap) / n)
	local ch = M.CardH
	S.PerRow, S.CardW = n, cw
	for i, key in ipairs(S.Order) do
		local item = U.Cards[key]
		if item then
			local row, col = math.floor((i - 1) / n), (i - 1) % n
			place(item.Button, col * (cw + gap), row * (ch + gap), cw, ch)
			H.layoutCard(item, cw, ch, M)
		end
	end
	local rows = math.ceil(#S.Order / n)
	U.Grid.CanvasSize = UDim2.fromOffset(0, math.max(0, rows * (ch + gap) - gap + 4))
	S.ViewDirty = true
end

----------------------------------------------------------------------
-- Cards
----------------------------------------------------------------------
-- "Lv 34" and its evolution stars (0-2), drawn after it as gold PixelIcons (kit-b U7b)
function H.levelText(e)
	return "Lv " .. tostring(e.Level), math.min(2, math.max(0, tonumber(e.Stage) or 0))
end

function H.jobText(job)
	return "Training " .. Bits.jobLeft(job)
end

function H.paintCard(item, e)
	local ctx = S.Context
	local tint = CloudUI.RarityColor(e.Rarity)
	item.Fill.Color = ColorSequence.new(Theme.Darken(tint, 0.45), Theme.Darken(tint, 0.72))
	local selected = S.Selected == e.Key
	item.Stroke.Color = selected and C.Gold or Theme.Lighten(tint, 0.15)
	item.Stroke.Thickness = selected and 5 or 3
	item.Button:SetAttribute("Selected", selected)
	-- the name, then (a Golden / Rainbow copy) its finish + last word, then the last word
	local last = string.match(e.Name, "(%S+)%s*$") or e.Name
	local tier = not e.Hybrid and Bits.tierOf(e.Key, e.Def) or "Normal"
	item.Names = { e.Name, last }
	if tier ~= "Normal" then
		item.Names = { e.Name, tier .. " " .. last, last }
	end
	local levelText, stars = H.levelText(e)
	item.Level.Text = levelText
	item.Level:SetAttribute("Stars", stars)
	PixelIcon.Mark(item.Level, stars > 0 and ICON.Star or nil, { After = true, Count = stars, Of = stars, Colour = C.Gold, Px = 18 })
	item.Rarity.Text = tostring(e.Rarity or "")
	item.Rarity.TextColor3 = Theme.Lighten(tint, 0.35)
	-- the corner badge
	local badge = item.Badge
	if ctx == "Train" then
		badge.Visible = e.Team ~= nil
		badge.TextColor3 = C.Gold
		PixelIcon.Set(badge, ICON.Star) -- (kit-b U7b) a team member
		badge.BackgroundTransparency = 1
	else
		badge.Visible = true
		PixelIcon.Set(badge, nil)
		badge.Text = "x" .. tostring(e.Copies)
		badge.TextColor3 = C.White
		badge.BackgroundTransparency = e.Ready and 0 or 0.35
		badge.BackgroundColor3 = e.Ready and C.Ready or C.Count
	end
	item.Button:SetAttribute("Ready", e.Ready == true)
	-- the Training chip (Train)
	item.Job = (ctx == "Train") and e.Job or nil
	item.Chip.Visible = item.Job ~= nil
	if item.Job then
		item.Chip.Text = H.jobText(item.Job)
	end
	-- dimmed (Upgrade: fewer copies than a fusion takes) / blocked (with its word)
	local blocked = e.Blocked
	local dim = ctx == "Upgrade" and not e.Ready
	item.Button:SetAttribute("Blocked", blocked)
	item.Button:SetAttribute("Dim", dim)
	item.Shade.Visible = dim or blocked ~= nil
	item.Shade.BackgroundTransparency = blocked and 0.3 or 0.5
	item.Word.Visible = blocked ~= nil
	item.Word.Text = blocked or ""
	item.Stage = e.Stage
	item.Def = e.Def
end

-- re-reads the entries, the order and the cards (resetScroll: back to the top)
function H.relist(resetScroll)
	if not S.Built or not S.Context then
		return
	end
	local ctx = S.Context
	local entries = PetPicker.Entries(ctx)
	local spec = S.Spec or {}
	local owned = {}
	S.ByKey = {}
	for _, e in ipairs(entries) do
		if type(spec.Blocked) == "table" and type(spec.Blocked[e.Key]) == "string" then
			e.Blocked = spec.Blocked[e.Key]
		end
		S.ByKey[e.Key] = e
		owned[e.Key] = true
	end
	if S.Selected and not owned[S.Selected] then
		S.Selected = nil
	end
	-- a key that left the collection (or this context) loses its card; its viewport stays cached while the pet is owned
	for key, item in pairs(U.Cards) do
		if not owned[key] then
			local v = U.Views[key]
			if v and State.OwnedCount(key) > 0 then
				v.Handle.Frame.Parent = U.Cache
			elseif v then
				H.dropView(key)
			end
			U.Cards[key] = nil
			item.Button:Destroy()
		end
	end
	local order = PetPicker.Sorted(ctx, entries, S.Sort[ctx], S.Filter[ctx], S.Query)
	S.Order, S.Shown = {}, {}
	for i, e in ipairs(order) do
		S.Order[i] = e.Key
		S.Shown[e.Key] = true
		H.paintCard(U.Cards[e.Key] or H.newCard(e.Key), e)
	end
	for key, item in pairs(U.Cards) do
		item.Button.Visible = S.Shown[key] == true
	end
	for key, v in pairs(U.Views) do
		if not S.Shown[key] and v.Handle.Frame.Parent ~= U.Cache then
			v.Handle.Frame.Parent = U.Cache
		end
	end
	U.Empty.Visible = #order == 0
	U.Clear.Visible = #entries > 0
	U.EmptyText.Text = #entries > 0 and "No pets match." or "No pets yet! Spin a roulette in the Shop to hatch one."
	H.paintChips()
	H.layoutCards()
	if resetScroll then
		U.Grid.CanvasPosition = Vector2.new(0, 0)
	end
end

function H.paintChips()
	local active = S.Filter[S.Context]
	for id, chip in pairs(U.Chips) do
		local on = id == active
		chip.Button:SetAttribute("Selected", on)
		chip.Button.BackgroundColor3 = on and Theme.Darken(C.Gold, 0.15) or C.Well
		chip.Button.TextColor3 = on and C.Navy or C.White
		if chip.Glyphs then
			chip.Glyphs.Transparency = on and 1 or 0 -- dark text on gold reads without its outline
		end
		chip.Stroke.Color = on and C.Gold or Color3.fromRGB(70, 84, 150)
	end
end

function H.sortLabel()
	for _, s in ipairs(PetPicker.Sorts[S.Context] or {}) do
		if s.Id == S.Sort[S.Context] then
			return s.Label
		end
	end
	return ""
end

function H.paintSort()
	if not S.Context then
		return
	end
	local M = H.metrics()
	local name = H.sortLabel()
	local short = SHORT[name] or name
	-- (kit-b U7b) the arrow is a PixelIcon after the text (18 px + its gap)
	H.fit(U.Sort, { "Sort: " .. name, "Sort: " .. short, short }, M.SortW - 22 - 22, M.SortText, M.SortMin)
	PixelIcon.Mark(U.Sort, ICON.Down, { After = true, Px = 18 })
end

function H.cycleSort()
	local list = PetPicker.Sorts[S.Context]
	if not list then
		return
	end
	local at = 1
	for i, s in ipairs(list) do
		if s.Id == S.Sort[S.Context] then
			at = i
		end
	end
	PetPicker.SetSort(list[at % #list + 1].Id)
end

function H.clear()
	S.Filter[S.Context] = "All"
	S.Silent = true
	U.Search.Text = ""
	S.Silent = false
	S.Query = ""
	H.relist(true)
end

function H.hint(message)
	S.HintToken = S.HintToken + 1
	local mine = S.HintToken
	U.Hint.Text = message
	U.Hint.Visible = true
	task.delay(K.HINT_SECONDS, function()
		if S.HintToken == mine and U.Hint then
			U.Hint.Visible = false
		end
	end)
end

function H.blockedHint(e)
	if e.Blocked == "Training" then
		return e.Name .. " is training: wait for it to finish"
	elseif e.Blocked == "In Body" or e.Blocked == "In Style" then
		return e.Name .. " is already in the other slot"
	end
	return e.Name .. " can't be picked here"
end

-- the selected card's row comes into view
function H.scrollToSelected()
	local M = H.metrics()
	for i, key in ipairs(S.Order) do
		if key == S.Selected then
			local top = math.floor((i - 1) / math.max(1, S.PerRow or 1)) * (M.CardH + M.CardGap)
			if top + M.CardH > U.Grid.Size.Y.Offset then
				U.Grid.CanvasPosition = Vector2.new(0, top * S.Scale)
			end
			return
		end
	end
end

----------------------------------------------------------------------
-- Viewports (one Heartbeat while open)
----------------------------------------------------------------------
function H.trimCache()
	local n = 0
	for _ in pairs(U.Views) do
		n = n + 1
	end
	if n <= K.CACHE_MAX then
		return
	end
	for key, v in pairs(U.Views) do
		if n <= K.CACHE_MAX then
			break
		end
		if v.Handle.Frame.Parent == U.Cache then
			H.dropView(key)
			n = n - 1
		end
	end
end

function H.fill()
	local gp, gs = U.Grid.AbsolutePosition, U.Grid.AbsoluteSize
	local top, bottom = gp.Y, gp.Y + gs.Y
	local started = os.clock()
	local built, pending = 0, false
	for _, key in ipairs(S.Order) do
		local item = U.Cards[key]
		if item then
			local p, s = item.Button.AbsolutePosition, item.Button.AbsoluteSize
			local inView = gs.Y > 0 and p.Y + s.Y > top + 0.5 and p.Y < bottom - 0.5
			local v = U.Views[key]
			if inView then
				if v and v.Stage == item.Stage then
					if v.Handle.Frame.Parent ~= item.Art then
						v.Handle.Frame.Parent = item.Art
					end
				elseif built >= K.BUILD_MAX or (built > 0 and os.clock() - started >= K.BUILD_BUDGET) then
					pending = true
				else
					H.dropView(key)
					built = built + 1
					local stage = item.Stage or 0
					local ok, handle = pcall(CloudUI.PetViewport, item.Art, item.Def, UDim2.fromScale(1, 1), {
						Detail = "Low", Spin = "sway", Animate = false, Evolved = stage >= 1 and stage or nil, ZIndex = 4,
					})
					if ok and handle then
						U.Views[key] = { Handle = handle, Stage = stage }
					else
						warnOnce("viewport", handle)
					end
				end
			elseif v and v.Handle.Frame.Parent == item.Art then
				v.Handle.Frame.Parent = U.Cache
			end
		end
	end
	S.ViewDirty = pending
	H.trimCache()
end

function H.step(dt)
	if not S.Open then
		return
	end
	if S.ViewDirty then
		safe("viewports", H.fill)
	end
	S.TickAcc = S.TickAcc + (tonumber(dt) or 0)
	if S.TickAcc >= K.TICK then
		S.TickAcc = 0
		for _, key in ipairs(S.Order) do
			local item = U.Cards[key]
			if item and item.Job then
				item.Chip.Text = H.jobText(item.Job)
			end
		end
	end
end

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------
function H.hide()
	S.Open = false
	S.HintToken = S.HintToken + 1
	if U.Holder then
		U.Holder.Visible = false
		U.Shade.Visible = false
		U.Hint.Visible = false
	end
	if S.Beat then
		S.Beat:Disconnect()
		S.Beat = nil
	end
	if S.Tween then
		S.Tween:Cancel()
		S.Tween = nil
	end
end

function PetPicker.Open(spec)
	if type(spec) ~= "table" or not PetPicker.Sorts[spec.Context] then
		return false
	end
	if not H.ensureGui() then
		return false
	end
	if S.Open then
		PetPicker.Close()
	end
	H.build()
	S.Spec = spec
	S.Context = spec.Context
	S.Selected = type(spec.Selected) == "string" and spec.Selected or nil
	S.Query = ""
	S.Silent = true
	U.Search.Text = ""
	S.Silent = false
	local accent = C.Accent[S.Context]
	U.HeaderGradient.Color = ColorSequence.new(Theme.Lighten(accent, 0.12), Theme.Darken(accent, 0.28))
	U.FootGradient.Color = ColorSequence.new(Theme.Lighten(accent, 0.12):Lerp(Theme.Darken(accent, 0.28), 0.76), Theme.Darken(accent, 0.28))
	U.PanelStroke.Color = accent
	PixelIcon.Set(U.Icon, ICON.Context[S.Context])
	U.Title.Text = tostring(spec.Title or "Pick a pet")
	S.Open = true
	U.Holder.Visible = true
	U.Shade.Visible = true
	U.Hint.Visible = false
	H.layout()
	H.relist(true)
	H.scrollToSelected()
	S.TickAcc = 0
	if S.Tween then
		S.Tween:Cancel()
	end
	U.Pop.Scale = K.OPEN_FROM
	S.Tween = Util.Tween(U.Pop, K.OPEN_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if not S.Beat then
		S.Beat = RunService.Heartbeat:Connect(H.step)
	end
	return true
end

function PetPicker.Close()
	if not S.Open then
		return
	end
	local spec = S.Spec
	H.hide()
	if spec and type(spec.OnClose) == "function" then
		safe("OnClose", spec.OnClose, false)
	end
end

function PetPicker.IsOpen()
	return S.Open
end

function PetPicker.Layout()
	if S.Open then
		return S.Mode
	end
	return NeonKit.BigRect(K).mode
end

function PetPicker.Pick(key)
	if not S.Open or type(key) ~= "string" or not S.Shown[key] then
		return false
	end
	local e = S.ByKey[key]
	if not e or State.OwnedCount(key) < 1 then
		return false
	end
	if e.Blocked then
		H.hint(H.blockedHint(e))
		return false
	end
	local spec = S.Spec
	H.hide()
	if type(spec.OnClose) == "function" then
		safe("OnClose", spec.OnClose, true)
	end
	if type(spec.OnPick) == "function" then
		safe("OnPick", spec.OnPick, key)
	end
	return true
end

function PetPicker.Shown()
	local out = {}
	for i, key in ipairs(S.Order) do
		out[i] = key
	end
	return out
end

function PetPicker.SetQuery(text)
	if not S.Open then
		return
	end
	U.Search.Text = tostring(text or "")
end

function PetPicker.SetSort(id)
	local ctx = S.Context
	if ctx and H.valid(PetPicker.Sorts[ctx], id) then
		S.Sort[ctx] = id
		if S.Open then
			H.paintSort()
			H.relist(true)
		end
	end
end

function PetPicker.SetFilter(id)
	local ctx = S.Context
	if ctx and H.valid(PetPicker.Filters[ctx], id) then
		S.Filter[ctx] = id
		if S.Open then
			H.relist(true)
		end
	end
end

return PetPicker
