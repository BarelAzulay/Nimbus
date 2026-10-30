-- TeamPick (client, HUD cleanup Task 2; the owner's pick "C" on the HUD cleanup pitch + the note "add an autofill best
-- pets button"): the battle team at the portal. The Team tile is gone; every team portal panel (the Dungeon panel, the
-- Battle Arena's Duels / Raid pages) shows a strip of the active preset with Edit and Auto-fill best, and a press on a
-- team portal with an empty team opens the "Pick your battle team" popup first and goes on into the portal after Save.
--
--   TeamPick.ActiveKeys() -> {key...}        the active preset minus the keys that cannot fight now (in training, the
--                                            only copy working in the Garden): what the server fields
--   TeamPick.Fieldable() -> { { Key, Def, Level, Tier, Power }... }   every owned key with a free copy, not in training,
--                                            strongest first (BattleCatalog.UnitPower with the stored evolution + ranks)
--   TeamPick.Best(n) -> {key...}             the n strongest fieldable keys
--   TeamPick.Save(keys, onDone)              BattleRequest("TeamSet", active preset, keys) ONCE (no TeamSelect); onDone(true)
--                                            when State.Teams() shows those keys in that preset (any order), onDone(false)
--                                            + the hint "Your team could not save. Try again!" after 2.5 s. A newer Save or
--                                            Close() drops an older pending one silently.
--   TeamPick.Ensure(continueFn) -> bool      continueFn() at once when ActiveKeys() is not empty; else the popup, and
--                                            continueFn() after a save the server confirmed; with no fieldable pet the hint
--                                            "You need a pet: spin a roulette in the Cloud Shop." and no popup
--   TeamPick.Strip(parent, props) -> { Root, Refresh }   props { LayoutOrder, Compact }: Frame "TeamStrip" with
--                                            StripSlot1..3 (PetName, Level "L<n>", Element pill; an empty slot shows
--                                            Empty "Empty"), TextButtons StripEdit "Edit" (MenuController.OpenTeam) and
--                                            StripAuto "Auto-fill best" (Save(Best(3))). Strips re-render on State.Changed
--                                            (one shared connection; destroyed strips drop out).
--   TeamPick.Popup(props)                    props { OnSave = fn(keys), OnCancel = fn }: ScreenGui "NimbusTeamPick"
--                                            (DisplayOrder 26, above the windows 20-23 and the dungeon fade 25, below
--                                            Notify 30) with a dimmed Backdrop and Frame "TeamPickPopup": a CloudUI.Panel
--                                            "Pick your battle team", PopSlot1..3 (CloudUI.Slot + name / level / element;
--                                            a tap swaps in the next strongest pet not in the team), TextButtons PopAuto
--                                            "Auto-fill best", PopCancel "Cancel" (and the red X), PopSave "Save and enter".
--                                            Prefilled with the active team, else Best(3). One UIScale fits it inside the
--                                            screen (16 px side gutters, 8 px top / bottom) at the readability factor.
--   TeamPick.IsOpen() -> bool, TeamPick.Close()
--
-- The server validates every TeamSet (DataService.CheckTeam: owned, a free copy, unique, at most 3) and refuses a battle
-- without a team ("Pick your battle team first (at a battle portal, or Pets > Team)").
-- Plain Lua 5.1-compatible syntax only. All fonts come from Theme roles; no asset ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local State = require(Client:WaitForChild("State"))

local TeamPick = {}

local K = {
	SLOTS = 3,
	SAVE_TIMEOUT = 2.5, -- seconds a Save waits for the synced preset
	DISPLAY_ORDER = 26,
	POP_W = 600, -- the popup (design px of a 1080p screen)
	POP_H = 372,
	GUTTER_X = 16, -- screen px kept free around the popup
	GUTTER_Y = 8,
	SLOT_VIEW = 112,
	BUTTON_H = 56,
	STRIP_SLOT_H = 56, -- the portal strip
	STRIP_SLOT_H_COMPACT = 44,
	STRIP_BUTTON_H = 44,
	STRIP_PAD = 8,
}

local Colors = Theme.Colors
local WHITE = Colors.White
local MUTED = Colors.Muted or Colors.CloudShade
local INK = Colors.TextStroke or Colors.Ink
local ROW = Color3.fromRGB(34, 44, 92)
local ROW_DARK = Color3.fromRGB(20, 26, 60)

local S = {
	Strips = {}, -- live strips { Root, Refresh }
	Conn = nil, -- the shared State.Changed connection
	SaveId = 0, -- the newest Save (older pending ones finish silently)
	Pop = nil, -- the popup's widgets
	Open = false,
	PopId = 0, -- one per popup opening
	Mods = {},
	Warned = {},
}

local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[TeamPick] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function safe(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(label, err)
	end
	return ok
end

local function shared(name)
	if S.Mods[name] == nil then
		S.Mods[name] = false
		local module = Shared:FindFirstChild(name)
		local ok, result = pcall(function()
			return module and require(module)
		end)
		if ok and type(result) == "table" then
			S.Mods[name] = result
		end
	end
	return S.Mods[name] or nil
end

local function menu()
	if S.Mods.MenuController == nil then
		S.Mods.MenuController = false
		local folder = Client:FindFirstChild("Controllers")
		local module = folder and folder:FindFirstChild("MenuController")
		local ok, result = pcall(function()
			return module and require(module)
		end)
		if ok and type(result) == "table" then
			S.Mods.MenuController = result
		end
	end
	return S.Mods.MenuController or nil
end

local function hint(text, kind)
	local mc = menu()
	if mc and type(mc.Hint) == "function" then
		safe("hint", mc.Hint, text, kind)
	end
end

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
local function teams()
	local ok, t = pcall(State.Teams)
	if ok and type(t) == "table" and type(t.Presets) == "table" then
		return t
	end
	return { Presets = { {}, {}, {} }, Active = 1, Slots = K.SLOTS }
end

local function activePreset()
	local a = math.floor(tonumber(teams().Active) or 1)
	if a < 1 or a > 3 then
		a = 1
	end
	return a
end

local function copyList(list)
	local out = {}
	for i, v in ipairs(type(list) == "table" and list or {}) do
		out[i] = v
	end
	return out
end

-- same keys, any order
local function sameSet(a, b)
	if #a ~= #b then
		return false
	end
	local seen = {}
	for _, k in ipairs(a) do
		seen[k] = (seen[k] or 0) + 1
	end
	for _, k in ipairs(b) do
		if not seen[k] or seen[k] < 1 then
			return false
		end
		seen[k] = seen[k] - 1
	end
	return true
end

-- copies of a key working in the Garden (bug batch 2 #18: a gardening copy cannot fight)
local function gardenCopies(key)
	local ok, home = pcall(State.Home)
	local garden = ok and type(home) == "table" and type(home.Garden) == "table" and home.Garden or {}
	local n = 0
	for _, k in pairs(garden) do
		if k == key then
			n = n + 1
		end
	end
	return n
end

local function canField(key)
	if type(key) ~= "string" then
		return false
	end
	local okT, training = pcall(State.IsTraining, key)
	if okT and training then
		return false
	end
	local okC, owned = pcall(State.OwnedCount, key)
	return okC and (tonumber(owned) or 0) - gardenCopies(key) >= 1
end

local function entryOf(key)
	local okD, def = pcall(State.DefOf, key)
	if not okD or type(def) ~= "table" then
		return nil
	end
	local okL, level = pcall(State.PetLevel, key)
	level = okL and tonumber(level) or 1
	local PetKeys = shared("PetKeys")
	local parsed = PetKeys and PetKeys.Parse and PetKeys.Parse(key)
	local tier = type(parsed) == "table" and parsed.Tier or "Normal"
	local okG, growth = pcall(State.PetGrowth, key)
	growth = okG and type(growth) == "table" and growth or {}
	local power = 0
	local BC = shared("BattleCatalog")
	if BC and type(BC.UnitPower) == "function" then
		local okP, p = pcall(BC.UnitPower, def, level, tier, { Evo = growth.Evo, Train = growth })
		power = okP and tonumber(p) or 0
	end
	return { Key = key, Def = def, Level = level, Tier = tier, Power = power }
end

function TeamPick.ActiveKeys()
	local out = {}
	for _, key in ipairs(teams().Presets[activePreset()] or {}) do
		if canField(key) then
			out[#out + 1] = key
		end
	end
	return out
end

function TeamPick.Fieldable()
	local out = {}
	local ok, keys = pcall(State.Keys)
	for _, key in ipairs(ok and type(keys) == "table" and keys or {}) do
		if canField(key) then
			local e = entryOf(key)
			if e then
				out[#out + 1] = e
			end
		end
	end
	table.sort(out, function(a, b)
		if a.Power ~= b.Power then
			return a.Power > b.Power
		end
		return tostring(a.Key) < tostring(b.Key)
	end)
	return out
end

function TeamPick.Best(n)
	local out = {}
	for i, e in ipairs(TeamPick.Fieldable()) do
		if i > (n or K.SLOTS) then
			break
		end
		out[#out + 1] = e.Key
	end
	return out
end

local function fire(...)
	local ok, remote = pcall(Remotes.Get, "BattleRequest")
	if not ok or not remote then
		warnOnce("BattleRequest", remote)
		return false
	end
	local args = { ... }
	return safe("TeamSet", function()
		remote:FireServer(unpack(args))
	end)
end

function TeamPick.Save(keys, onDone)
	local list = copyList(keys)
	local preset = activePreset()
	S.SaveId = S.SaveId + 1
	local mine = S.SaveId
	local done = false
	local conn = nil
	local function finish(ok)
		if done then
			return
		end
		done = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if mine ~= S.SaveId then
			return -- a newer save (or Close) took over
		end
		if not ok then
			hint("Your team could not save. Try again!", "bad")
		end
		if onDone then
			safe("save done", onDone, ok)
		end
	end
	if #list == 0 or not fire("TeamSet", preset, copyList(list)) then
		finish(false)
		return
	end
	conn = State.Changed:Connect(function()
		if sameSet(copyList(teams().Presets[preset]), list) then
			finish(true)
		end
	end)
	task.delay(K.SAVE_TIMEOUT, function()
		finish(false)
	end)
end

----------------------------------------------------------------------
-- Small builders
----------------------------------------------------------------------
local function frame(parent, name, props)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function text(parent, name, value, role, size, color, props)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = tostring(value or "")
	Theme.Style(label, role or "Body", { Size = size, Color = color or WHITE, Stroke = 1 })
	Theme.TextOutline(label, 1.5, INK, 0.1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = parent
	return label
end

local function corner(parent, px)
	return Util.Create("UICorner", { CornerRadius = UDim.new(0, px or 10), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return Util.Create("UIStroke", {
		Color = color or INK,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function elementOf(def)
	local PC = shared("PetCatalog")
	local elems = nil
	if PC and type(PC.ElementsOf) == "function" then
		local ok, result = pcall(PC.ElementsOf, def)
		elems = ok and result or nil
	end
	local e = type(elems) == "table" and elems[1] or (type(def) == "table" and def.Element)
	if type(e) ~= "string" then
		return nil, nil
	end
	local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[e]
	return (info and info.Name) or e, info and info.Color or Theme.Neon.Grey
end

local function nameOf(def)
	return type(def) == "table" and tostring(def.Name or def.Id or "?") or "?"
end

-- the element pill: Frame "Element" (its colour) with the label "Text"
local function elementPill(parent, props)
	local pill = frame(parent, "Element", props)
	pill.BackgroundTransparency = 0
	pill.BackgroundColor3 = Theme.Neon.Grey
	pill.AutomaticSize = Enum.AutomaticSize.X
	corner(pill, 8)
	Util.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = pill })
	text(pill, "Text", "", "Heading", 18, WHITE, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X })
	return pill
end

local function paintPill(pill, def)
	local name, color = elementOf(def)
	pill.Visible = name ~= nil
	if name then
		pill.BackgroundColor3 = Theme.Darken(color, 0.25)
		pill:FindFirstChild("Text").Text = name
	end
end

----------------------------------------------------------------------
-- The strip
----------------------------------------------------------------------
local function refreshStrips()
	local alive = {}
	for _, strip in ipairs(S.Strips) do
		if strip.Root.Parent ~= nil then
			alive[#alive + 1] = strip
			safe("strip refresh", strip.Refresh)
		end
	end
	S.Strips = alive
end

local function ensureConn()
	if not S.Conn then
		S.Conn = State.Changed:Connect(function()
			refreshStrips()
			if S.Open and S.Pop then
				safe("popup refresh", S.Pop.Prune)
			end
		end)
	end
end

local function autoFill()
	local best = TeamPick.Best(K.SLOTS)
	if #best == 0 then
		hint("You need a pet: spin a roulette in the Cloud Shop.", "info")
		return
	end
	local current = copyList(teams().Presets[activePreset()])
	if sameSet(current, best) then
		hint("Your best pets are already in your team!", "info")
		return
	end
	TeamPick.Save(best, function(ok)
		if ok then
			hint("Team saved: your " .. #best .. " strongest pets!", "good")
		end
	end)
end

function TeamPick.Strip(parent, props)
	props = props or {}
	local compact = props.Compact == true
	local slotH = compact and K.STRIP_SLOT_H_COMPACT or K.STRIP_SLOT_H
	local pad = K.STRIP_PAD
	local height = pad * 2 + slotH + 6 + K.STRIP_BUTTON_H
	local root = frame(parent, "TeamStrip", {
		BackgroundTransparency = 0.15,
		BackgroundColor3 = ROW_DARK,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = props.LayoutOrder or 0,
	})
	corner(root, 12)
	stroke(root, Theme.Darken(Theme.Neon.Red, 0.3), 2, 0.1)
	-- buttons: a right-aligned row under the slots (a compact strip too: beside them, a landscape phone's ~414 px
	-- Dungeon party box left the slots ~30 px each)
	local buttonsW = 96 + 8 + 176
	local buttons = frame(root, "Buttons", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -pad, 1, -pad),
		Size = UDim2.fromOffset(buttonsW, K.STRIP_BUTTON_H),
	})
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = buttons,
	})
	CloudUI.Button({
		Name = "StripEdit",
		Text = "Edit",
		Style = "Blue",
		Size = UDim2.fromOffset(96, K.STRIP_BUTTON_H),
		TextSize = 20,
		LayoutOrder = 1,
		Parent = buttons,
		Callback = function()
			local mc = menu()
			if mc and type(mc.OpenTeam) == "function" then
				safe("strip edit", mc.OpenTeam, activePreset())
			end
		end,
	})
	CloudUI.Button({
		Name = "StripAuto",
		Text = "Auto-fill best",
		Style = "Green",
		Size = UDim2.fromOffset(176, K.STRIP_BUTTON_H),
		TextSize = 20,
		LayoutOrder = 2,
		Parent = buttons,
		Callback = function()
			safe("strip auto", autoFill)
		end,
	})
	if not compact then
		text(root, "Caption", "Your battle team", "Heading", 19, MUTED, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, pad + 2, 1, -pad),
			Size = UDim2.new(1, -(buttonsW + 3 * pad), 0, K.STRIP_BUTTON_H),
		})
	end
	local row = frame(root, "Slots", {
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.new(1, -2 * pad, 0, slotH),
	})
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = row,
	})
	local slots = {}
	for i = 1, K.SLOTS do
		local cell = frame(row, "StripSlot" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = ROW,
			Size = UDim2.new(1 / K.SLOTS, -4, 1, 0),
			LayoutOrder = i,
		})
		corner(cell, 10)
		local rim = stroke(cell, Theme.Darken(Theme.Neon.Grey, 0.4), 2, 0.1)
		local name = text(cell, "PetName", "", "Heading", 19, WHITE, {
			Position = UDim2.fromOffset(10, compact and 0 or 4),
			Size = compact and UDim2.new(1, -62, 1, 0) or UDim2.new(1, -16, 0, 24),
		})
		local level = text(cell, "Level", "", "Heading", 18, Theme.Neon.Gold, compact and {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.new(0, 48, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
		} or {
			Position = UDim2.fromOffset(10, 30),
			Size = UDim2.fromOffset(48, 22),
		})
		local pill = elementPill(cell, {
			Position = UDim2.fromOffset(60, 30),
			Size = UDim2.fromOffset(0, 22),
		})
		local empty = text(cell, "Empty", "Empty", "Heading", 18, MUTED, {
			Size = UDim2.new(1, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		slots[i] = { Cell = cell, Rim = rim, Name = name, Level = level, Pill = pill, Empty = empty }
	end
	local strip = { Root = root }
	function strip.Refresh()
		local keys = TeamPick.ActiveKeys()
		for i, s in ipairs(slots) do
			local key = keys[i]
			local e = key and entryOf(key) or nil
			s.Empty.Visible = e == nil
			s.Name.Visible = e ~= nil
			s.Level.Visible = e ~= nil
			if e then
				s.Name.Text = nameOf(e.Def)
				s.Level.Text = "L" .. tostring(e.Level)
				paintPill(s.Pill, e.Def)
				s.Pill.Visible = s.Pill.Visible and not compact
				local _, color = elementOf(e.Def)
				s.Rim.Color = color or Theme.Neon.Grey
				s.Cell.BackgroundColor3 = ROW
			else
				s.Pill.Visible = false
				s.Rim.Color = Theme.Darken(Theme.Neon.Grey, 0.4)
				s.Cell.BackgroundColor3 = ROW_DARK
			end
		end
	end
	strip.Refresh()
	S.Strips[#S.Strips + 1] = strip
	ensureConn()
	return strip
end

----------------------------------------------------------------------
-- The popup
----------------------------------------------------------------------
local function buildPopup()
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local gui = CloudUI.NewScreenGui("NimbusTeamPick", K.DISPLAY_ORDER)
	gui.Enabled = false
	local P = { Gui = gui, Slots = {}, Keys = {} }
	P.Backdrop = frame(gui, "Backdrop", {
		BackgroundTransparency = 0.45,
		BackgroundColor3 = Color3.fromRGB(4, 6, 18),
		Size = UDim2.new(1, 0, 1, 0),
		Active = true, -- the world behind is not clicked while the popup asks
	})
	P.Holder = frame(gui, "TeamPickPopup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(K.POP_W, K.POP_H),
		Visible = false,
		ZIndex = 2,
	})
	P.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = P.Holder })
	local panel = CloudUI.Panel({
		Name = "TeamPickPanel",
		Title = "Pick your battle team",
		Closable = true,
		Category = "Team",
		Size = UDim2.new(1, 0, 1, 0),
		OnClose = function()
			safe("popup cancel", P.Cancel)
		end,
		Parent = P.Holder,
	})
	local content = panel.Content
	text(content, "Help", "Slot 1 is your FIGHTER. Tap a slot to swap in another pet.", "Body", 18, MUTED, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 26),
	})
	local row = frame(content, "Slots", { Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 170) })
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
		Parent = row,
	})
	for i = 1, K.SLOTS do
		local col = frame(row, "Col" .. i, { Size = UDim2.new(1 / K.SLOTS, -8, 1, 0), LayoutOrder = i })
		local slot = CloudUI.Slot({
			Name = "PopSlot" .. i,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(K.SLOT_VIEW, K.SLOT_VIEW),
			Parent = col,
			Callback = function()
				safe("popup slot", P.Cycle, i)
			end,
		})
		local name = text(slot.Root, "PetName", "", "Heading", 19, WHITE, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 4),
			Size = UDim2.fromOffset(176, 24),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local info = frame(slot.Root, "Info", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 30),
			Size = UDim2.fromOffset(176, 24),
		})
		Util.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
			Parent = info,
		})
		local level = text(info, "Level", "", "Heading", 18, Theme.Neon.Gold, {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
		})
		local pill = elementPill(info, { Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2 })
		local role = text(slot.Root, "Role", i == 1 and "FIGHTER" or "HELPER", "Button", 18, WHITE, {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(i == 1 and 86 or 76, 24),
			BackgroundTransparency = 0,
			BackgroundColor3 = i == 1 and Theme.Darken(Theme.Neon.Red, 0.2) or Theme.Darken(Theme.Neon.Blue, 0.2),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 8,
		})
		corner(role, 8)
		P.Slots[i] = { Slot = slot, Name = name, Level = level, Pill = pill, Key = nil }
	end
	local buttons = frame(content, "Buttons", { Position = UDim2.fromOffset(12, 218), Size = UDim2.new(1, -24, 0, K.BUTTON_H) })
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = buttons,
	})
	P.Auto = CloudUI.Button({
		Name = "PopAuto",
		Text = "Auto-fill best",
		Style = "Blue",
		Size = UDim2.fromOffset(190, K.BUTTON_H),
		TextSize = 21,
		LayoutOrder = 1,
		Parent = buttons,
		Callback = function()
			safe("popup auto", P.AutoFill)
		end,
	})
	P.CancelButton = CloudUI.Button({
		Name = "PopCancel",
		Text = "Cancel",
		Style = "Gray",
		Size = UDim2.fromOffset(130, K.BUTTON_H),
		TextSize = 21,
		LayoutOrder = 2,
		Parent = buttons,
		Callback = function()
			safe("popup cancel", P.Cancel)
		end,
	})
	P.Save = CloudUI.Button({
		Name = "PopSave",
		Text = "Save and enter",
		Style = "Green",
		Size = UDim2.fromOffset(210, K.BUTTON_H),
		TextSize = 21,
		LayoutOrder = 3,
		Parent = buttons,
		Callback = function()
			safe("popup save", P.Submit)
		end,
	})

	function P.Paint()
		local n = 0
		for i, s in ipairs(P.Slots) do
			local key = P.Keys[i]
			local e = key and entryOf(key) or nil
			s.Key = e and key or nil
			if e then
				n = n + 1
				local stage = 0
				local okS, st = pcall(State.PetStage, key)
				stage = okS and tonumber(st) or 0
				s.Slot.SetContent({ Pet = e.Def, Detail = "Low", Evolved = stage >= 1 and stage or nil, Name = nameOf(e.Def), RarityColor = CloudUI.RarityColor(e.Def.Rarity) })
				s.Name.Text = nameOf(e.Def)
				s.Name.TextColor3 = WHITE
				s.Level.Text = "L" .. tostring(e.Level)
				s.Level.Visible = true
				paintPill(s.Pill, e.Def)
			else
				s.Slot.SetContent({ Glyph = "+", Name = "Tap to add a pet" })
				s.Name.Text = "Empty"
				s.Name.TextColor3 = MUTED
				s.Level.Visible = false
				s.Pill.Visible = false
			end
		end
		CloudUI.SetDisabled(P.Save, n == 0 or P.Saving == true)
		CloudUI.SetDisabled(P.Auto, P.Saving == true)
		P.Save.Text = P.Saving and "Saving..." or "Save and enter"
	end

	-- a slot tap: the next strongest fieldable pet that is not in another slot (wraps around)
	function P.Cycle(i)
		if P.Saving then
			return
		end
		local list = TeamPick.Fieldable()
		local taken = {}
		for j, key in pairs(P.Keys) do
			if j ~= i and key then
				taken[key] = true
			end
		end
		local start = 0
		for idx, e in ipairs(list) do
			if e.Key == P.Keys[i] then
				start = idx
			end
		end
		for step = 1, #list do
			local e = list[((start + step - 1) % #list) + 1]
			if not taken[e.Key] and e.Key ~= P.Keys[i] then
				P.Keys[i] = e.Key
				P.Compact()
				P.Paint()
				return
			end
		end
		hint("No other pet to swap in.", "info")
	end

	-- the keys stay dense (slot 1 = the fighter)
	function P.Compact()
		local out = {}
		for i = 1, K.SLOTS do
			if P.Keys[i] then
				out[#out + 1] = P.Keys[i]
			end
		end
		P.Keys = out
	end

	-- a sync while the popup is open: drop keys that cannot fight any more
	function P.Prune()
		if P.Saving then
			return
		end
		local out = {}
		for _, key in ipairs(P.Keys) do
			if canField(key) then
				out[#out + 1] = key
			end
		end
		P.Keys = out
		P.Paint()
	end

	function P.AutoFill()
		if P.Saving then
			return
		end
		P.Keys = TeamPick.Best(K.SLOTS)
		P.Paint()
	end

	function P.Cancel()
		local cb = P.OnCancel
		TeamPick.Close()
		if cb then
			safe("popup on cancel", cb)
		end
	end

	function P.Submit()
		if P.Saving then
			return
		end
		P.Compact()
		if #P.Keys == 0 then
			hint("Pick at least one pet for your team.", "info")
			return
		end
		P.Saving = true
		P.Paint()
		if P.OnSave then
			safe("popup on save", P.OnSave, copyList(P.Keys))
		end
	end

	function P.Layout()
		local size = gui.AbsoluteSize
		local w, h = size.X, size.Y
		if w < 2 or h < 2 then
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
			w, h = vp.X, vp.Y
		end
		local factor = 1
		local ok, f = pcall(CloudUI.ScreenFactor)
		if ok and tonumber(f) then
			factor = f
		end
		local fit = math.min((w - 2 * K.GUTTER_X) / K.POP_W, (h - 2 * K.GUTTER_Y) / K.POP_H)
		P.Fit.Scale = math.max(0.3, math.min(factor, fit))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if S.Open then
			safe("popup layout", P.Layout)
		end
	end)
	return P
end

function TeamPick.Popup(props)
	props = props or {}
	if not S.Pop or not S.Pop.Gui.Parent then
		S.Pop = buildPopup()
	end
	local P = S.Pop
	if not P then
		return nil
	end
	ensureConn()
	S.SaveId = S.SaveId + 1 -- a save of an earlier opening finishes silently
	S.PopId = S.PopId + 1
	P.OnSave, P.OnCancel = props.OnSave, props.OnCancel
	P.Saving = false
	local keys = TeamPick.ActiveKeys()
	if #keys == 0 then
		keys = TeamPick.Best(K.SLOTS)
	end
	P.Keys = keys
	S.Open = true
	P.Gui.Enabled = true
	P.Holder.Visible = true
	P.Backdrop.Visible = true
	P.Layout()
	P.Paint()
	return P
end

function TeamPick.IsOpen()
	return S.Open == true
end

function TeamPick.Close()
	S.SaveId = S.SaveId + 1
	S.PopId = S.PopId + 1
	S.Open = false
	local P = S.Pop
	if P then
		P.Saving = false
		P.OnSave, P.OnCancel = nil, nil
		P.Holder.Visible = false
		P.Backdrop.Visible = false
		P.Gui.Enabled = false
	end
end

function TeamPick.Ensure(continueFn)
	if #TeamPick.ActiveKeys() > 0 then
		if continueFn then
			continueFn()
		end
		return true
	end
	if #TeamPick.Fieldable() == 0 then
		TeamPick.Close()
		hint("You need a pet: spin a roulette in the Cloud Shop.", "info")
		return false
	end
	local opening = nil
	TeamPick.Popup({
		OnSave = function(keys)
			TeamPick.Save(keys, function(ok)
				if opening ~= S.PopId then
					return -- this popup was closed (Cancel, another portal) while it saved
				end
				TeamPick.Close() -- (a failed save already showed its hint)
				if ok and continueFn then
					continueFn()
				end
			end)
		end,
	})
	opening = S.PopId
	return false
end

return TeamPick
