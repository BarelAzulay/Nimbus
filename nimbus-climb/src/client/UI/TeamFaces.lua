-- TeamFaces (client UI, team balance, spec s.2): the row every battle panel shows, the three pets that will fight with Edit team
-- beside them. It replaces client/TeamPick's strip and its "Pick your battle team" popup: there is one flow and no silent auto-fill.
--
--   TeamFaces.New(parent, props) -> { Root, Refresh = fn, SetMode = fn(mode), Height = fn() -> design px, Destroy = fn }
--       props = { LayoutOrder, Compact = bool, Column = bool, ReturnTo = table | fn() -> table (what Edit team hands to the Pets window) };
--       SetMode("Card" | "Compact" | "Column") when the window's layout changes.
--       Frame "TeamFaces": Face1..Face3 (Picture, Tag "FIGHTER" | "HELPER", Level "L12", Power, Busy, StageBadge + attribute Stage; an open
--       slot shows Empty "Empty", a slot whose pet is busy shows Empty "Training" | "Gardening" and the Busy mark), TeamPower and
--       the TextButton EditTeam ("Edit team", 56 design px: >= 44 px under the 0.8 touch scale).
--         Card     the faces in a row, a line below with TeamPower and EditTeam (wide windows)
--         Compact  the faces in a row with EditTeam beside them, one line high (phones: the Dungeon's party box); no TeamPower
--         Column   the faces under each other, TeamPower and EditTeam below (the Ring's right column on a landscape phone)
--       Every row redraws on State.Changed (one shared connection; destroyed rows drop out).
--   TeamFaces.Entries() -> { { Key, Def, Level, Tier, Evo, Train, Power, Busy = false }... }  State.ActiveTeam(): the pets that fight, in
--       slot order (busy pets are not in it); an entry is what BattleCatalog reads
--   TeamFaces.Power() -> number   TeamPower of the entries, rounded; 0 when empty
--   TeamFaces.Ensure(continueFn, returnTo) -> bool   continueFn() at once when the team is not empty. With 0 owned pets the hint "You need
--       a pet: spin a roulette in the Cloud Shop." and nothing else. Otherwise the Pets window with slot 1 in pick mode and NO
--       automatic continue: the player presses the panel's button again after editing. A team whose pets are all busy says so.
-- The server decides again (BattleService.TEAM_REFUSALS). Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local UI = script.Parent
local Client = UI.Parent
local CloudUI = require(UI:WaitForChild("CloudUI"))
local Bits = require(UI:WaitForChild("PetBits"))
local State = require(Client:WaitForChild("State"))

local TeamFaces = {}

local K = {
	SLOTS = 3,
	PAD = 8,
	GAP = 6,
	EDIT_H = 56,
	EDIT_W = 150,
	EDIT_W_COMPACT = 100,
	CARD_H = 96, -- the height of a face per mode
	COMPACT_H = 64,
	COLUMN_H = 44,
	COLUMN_PAD = 4,
	NO_PET = "You need a pet: spin a roulette in the Cloud Shop.",
	ALL_BUSY = "Your whole team is busy: training or gardening",
}

local Colors = Theme.Colors
local WHITE = Colors.White
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Colors.Gold or Colors.Token
local ROW = Color3.fromRGB(34, 44, 92)
local ROW_DARK = Color3.fromRGB(20, 26, 60)
local POWER_GOLD = Color3.fromRGB(255, 214, 110)
local SWORDS = "\226\154\148"
local BUSY_GLYPH = { Training = "\240\159\146\170", Garden = "\240\159\140\177" }
local BUSY_WORD = { Training = "Training", Garden = "Gardening" }

local frame, text, corner, stroke = Bits.frame, Bits.text, Bits.corner, Bits.stroke

local S = {
	Rows = {}, -- live rows
	Conn = nil, -- the shared State.Changed connection
	Warned = {},
}

local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[TeamFaces] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function safe(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(label, err)
	end
	return ok
end

-- another controller, at call time: the windows load this module while they load themselves
local function controller(name)
	local folder = Client:FindFirstChild("Controllers")
	local module = folder and folder:FindFirstChild(name)
	local ok, mod = pcall(function()
		return module and require(module)
	end)
	return ok and type(mod) == "table" and mod or nil
end

local function hint(message, kind)
	local menu = controller("MenuController")
	if menu and type(menu.Hint) == "function" then
		safe("hint", menu.Hint, message, kind)
	end
end

local function commas(n)
	local out = tostring(math.floor(tonumber(n) or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- a Compact face's power: 2,144 -> 2.1K
local function shortPower(n)
	if n >= 1000 then
		return string.format("%.1fK", n / 1000)
	end
	return commas(n)
end

local function openPets(args)
	local pets = controller("PetsController")
	if pets and type(pets.Open) == "function" then
		safe("open pets", pets.Open, args)
	end
end

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
function TeamFaces.Entries()
	local out = {}
	local ok, keys = pcall(State.ActiveTeam)
	for _, key in ipairs(ok and type(keys) == "table" and keys or {}) do
		local def = Bits.defOfKey(key)
		if def then
			local level = Bits.petLevel(key)
			local entry = Bits.battleEntry(key, def, level)
			entry.Power = Bits.battlePower(key, def, level) or 0
			entry.Busy = false
			out[#out + 1] = entry
		end
	end
	return out
end

function TeamFaces.Power()
	local BC = Bits.battleCatalog()
	local entries = TeamFaces.Entries()
	if not BC or #entries == 0 then
		return 0
	end
	local ok, power = pcall(BC.TeamPower, entries)
	return ok and math.floor((tonumber(power) or 0) + 0.5) or 0
end

-- why the active team's busy pets are busy, in slot order: they keep their slot, the faces after the fielded ones say so
local function busyOfTeam()
	local out = {}
	local ok, teams = pcall(State.Teams)
	local active = ok and type(teams) == "table" and type(teams.Presets) == "table" and teams.Presets[teams.Active or 1]
	for _, key in ipairs(type(active) == "table" and active or {}) do
		local why = Bits.busyOf(key)
		if why then
			out[#out + 1] = why
		end
	end
	return out
end

function TeamFaces.Ensure(continueFn, returnTo)
	local ok, team = pcall(State.ActiveTeam)
	if ok and type(team) == "table" and #team > 0 then
		if continueFn then
			continueFn()
		end
		return true
	end
	if #Bits.ownedKeys() == 0 then
		hint(K.NO_PET, "info")
		return false
	end
	openPets({ Pick = 1, ReturnTo = returnTo })
	if #busyOfTeam() > 0 then
		hint(K.ALL_BUSY, "bad")
	end
	return false
end

----------------------------------------------------------------------
-- One face
----------------------------------------------------------------------
local function buildFace(root, i)
	local cell = frame(root, "Face" .. i, { BackgroundTransparency = 0, BackgroundColor3 = ROW })
	corner(cell, 10)
	local face = { Cell = cell, Rim = stroke(cell, Theme.Darken(Theme.Neon.Grey, 0.4), 2, 0.1), Key = nil, Stage = 0 }
	face.Picture = frame(cell, "Picture", { ZIndex = 2 })
	face.Tag = text(cell, "Tag", i == 1 and "FIGHTER" or "HELPER", "Tag", 18, WHITE, {
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Darken(i == 1 and Theme.Neon.Red or Theme.Neon.Blue, 0.2),
		ZIndex = 4,
	})
	corner(face.Tag, 6)
	face.Stage_ = text(cell, "StageBadge", "", "Button", 18, WHITE, {
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Darken(GOLD, 0.35),
		Visible = false,
		ZIndex = 4,
	})
	corner(face.Stage_, 6)
	face.Level = text(cell, "Level", "", "Heading", 18, Theme.Neon.Gold, { TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	face.Power = text(cell, "Power", "", "Heading", 18, POWER_GOLD, {
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	face.Empty = text(cell, "Empty", "Empty", "Heading", 18, MUTED, { ZIndex = 3 })
	face.Busy = text(cell, "Busy", "", "Heading", 18, WHITE, { Visible = false, ZIndex = 4 })
	return face
end

-- x and y in pixels; the width is a share of the parent (wScale) plus pixels
local function place(obj, x, y, wScale, w, h)
	obj.Position = UDim2.fromOffset(x, y)
	obj.Size = UDim2.new(wScale, w, 0, h)
end

-- where a face's parts sit: everything hangs off the cell's edges, so a cell can be any width
local function layoutFace(face, mode)
	if mode == "Column" then
		-- [picture] FIGHTER
		--           L12    sword 358
		local h = K.COLUMN_H
		local x = h + 2
		place(face.Picture, 2, 2, 0, h - 4, h - 4)
		place(face.Tag, x, 2, 0, 88, 20)
		place(face.Level, x, 22, 0, 44, 20)
		place(face.Power, x + 44, 22, 1, -(x + 48), 20)
		place(face.Empty, x, 22, 1, -(x + 4), 20)
		place(face.Busy, 2, 2, 0, h - 4, h - 4)
	elseif mode == "Compact" then
		-- FIGHTER (a line across)
		-- [picture] L12 / 358
		place(face.Tag, 2, 2, 1, -4, 20)
		place(face.Picture, 2, 22, 0, 34, 40)
		place(face.Level, 38, 22, 1, -40, 20)
		place(face.Power, 38, 42, 1, -40, 20)
		place(face.Busy, 2, 22, 1, -4, 20)
	else
		local h = K.CARD_H
		place(face.Picture, 4, 2, 1, -8, h - 30)
		place(face.Tag, 4, 4, 0, 88, 22)
		place(face.Stage_, 96, 4, 0, 62, 22)
		place(face.Level, 8, h - 26, 0, 46, 24)
		place(face.Power, 54, h - 26, 1, -60, 24)
		place(face.Empty, 4, 28, 1, -8, h - 32)
		place(face.Busy, 8, 28, 0, 26, h - 32)
	end
end

local function paintFace(face, entry, busy, mode, shown)
	local stage = entry and tonumber(entry.Evo) or 0
	local key = entry and entry.Key or nil
	if (shown or not key) and (face.Key ~= key or face.Stage ~= stage) then
		if face.Handle then
			pcall(face.Handle.Destroy)
			face.Handle = nil
		end
		face.Key, face.Stage = key, stage
		if entry then
			local ok, handle = pcall(CloudUI.PetViewport, face.Picture, entry.Def, UDim2.new(1, 0, 1, 0), {
				Spin = "sway",
				Detail = "Low",
				ZIndex = 2,
				Evolved = stage > 0 and stage or nil,
			})
			if ok then
				face.Handle = handle
			else
				warnOnce("viewport", handle)
			end
		end
	end
	face.Cell:SetAttribute("Stage", stage)
	face.Picture.Visible = entry ~= nil
	face.Level.Visible = entry ~= nil
	face.Power.Visible = entry ~= nil
	face.Empty.Visible = entry == nil
	face.Busy.Visible = entry == nil and busy ~= nil
	face.Cell.BackgroundColor3 = entry and ROW or ROW_DARK
	if entry then
		face.Level.Text = "L" .. tostring(entry.Level)
		face.Power.Text = mode == "Compact" and shortPower(entry.Power) or (SWORDS .. " " .. commas(entry.Power))
		face.Rim.Color = CloudUI.RarityColor(entry.Def.Rarity)
		face.Stage_.Text = stage >= 2 and "EVO II" or "EVO I"
		face.Stage_.Visible = stage > 0 and mode == "Card" -- (the picture shows the stage; the smaller faces have no room for the badge)
	else
		face.Stage_.Visible = false
		face.Empty.Text = busy and BUSY_WORD[busy] or "Empty"
		face.Busy.Text = busy and BUSY_GLYPH[busy] or ""
		if mode == "Compact" then
			-- the mark above the word when the slot's pet is busy
			place(face.Empty, 2, busy and 42 or 22, 1, -4, busy and 20 or 40)
		end
		face.Rim.Color = Theme.Darken(Theme.Neon.Grey, 0.4)
	end
end

----------------------------------------------------------------------
-- The row
----------------------------------------------------------------------
-- the row's window and page are on screen: a hidden row builds no pet viewports (its window refreshes it when it opens)
local function isShown(obj)
	while obj and obj:IsA("GuiObject") do
		if not obj.Visible then
			return false
		end
		obj = obj.Parent
	end
	return true
end

local function refreshRows()
	local alive = {}
	for _, row in ipairs(S.Rows) do
		if row.Root.Parent ~= nil then
			alive[#alive + 1] = row
			safe("row refresh", row.Refresh)
		else
			row.Release()
		end
	end
	S.Rows = alive
end

function TeamFaces.New(parent, props)
	props = props or {}
	local mode = (props.Column and "Column") or (props.Compact and "Compact") or "Card"
	local root = frame(parent, "TeamFaces", {
		BackgroundTransparency = 0.15,
		BackgroundColor3 = ROW_DARK,
		LayoutOrder = props.LayoutOrder or 0,
	})
	corner(root, 12)
	stroke(root, Theme.Darken(Theme.Neon.Red, 0.3), 2, 0.1)
	local faces = {}
	for i = 1, K.SLOTS do
		faces[i] = buildFace(root, i)
	end
	local power = text(root, "TeamPower", "", "Heading", 19, POWER_GOLD, {
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local edit = CloudUI.Button({
		Name = "EditTeam",
		Text = "Edit team",
		Style = "Blue",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(K.EDIT_W, K.EDIT_H),
		TextSize = 20,
		Parent = root,
		Callback = function()
			local back = props.ReturnTo
			if type(back) == "function" then
				back = back()
			end
			openPets({ ReturnTo = back })
		end,
	})

	local row = { Root = root }

	function row.Height()
		if mode == "Column" then
			return K.COLUMN_PAD * 2 + K.SLOTS * K.COLUMN_H + (K.SLOTS - 1) * K.COLUMN_PAD + K.GAP + K.EDIT_H
		elseif mode == "Compact" then
			return K.PAD * 2 + K.COMPACT_H
		end
		return K.PAD * 2 + K.CARD_H + K.GAP + K.EDIT_H
	end

	-- the cells of a row of faces: `taken` px of the row's width are not theirs
	local function faceRow(taken, h)
		local pad, n = K.PAD, K.SLOTS
		local share = (2 * pad + (n - 1) * K.GAP + taken) / n
		for i, face in ipairs(faces) do
			face.Cell.Position = UDim2.new((i - 1) / n, pad + (i - 1) * (K.GAP - share), 0, pad)
			face.Cell.Size = UDim2.new(1 / n, -share, 0, h)
		end
	end

	local function layout()
		root.Size = UDim2.new(1, 0, 0, row.Height())
		for _, face in ipairs(faces) do
			layoutFace(face, mode)
		end
		local pad = K.PAD
		if mode == "Column" then
			pad = K.COLUMN_PAD
			for i, face in ipairs(faces) do
				place(face.Cell, pad, pad + (i - 1) * (K.COLUMN_H + pad), 1, -2 * pad, K.COLUMN_H)
			end
			local y = pad + K.SLOTS * K.COLUMN_H + (K.SLOTS - 1) * pad + K.GAP
			edit.Position = UDim2.new(1, -pad, 0, y)
			edit.Size = UDim2.fromOffset(K.EDIT_W_COMPACT, K.EDIT_H)
			place(power, pad + 2, y, 1, -(2 * pad + K.EDIT_W_COMPACT + 6), K.EDIT_H)
		elseif mode == "Compact" then
			faceRow(K.EDIT_W_COMPACT + K.GAP, K.COMPACT_H)
			edit.Position = UDim2.new(1, -pad, 0, pad + (K.COMPACT_H - K.EDIT_H) / 2)
			edit.Size = UDim2.fromOffset(K.EDIT_W_COMPACT, K.EDIT_H)
		else
			faceRow(0, K.CARD_H)
			local y = pad + K.CARD_H + K.GAP
			edit.Position = UDim2.new(1, -pad, 0, y)
			edit.Size = UDim2.fromOffset(K.EDIT_W, K.EDIT_H)
			place(power, pad + 2, y, 1, -(2 * pad + K.EDIT_W + 6), K.EDIT_H)
		end
		power.Visible = mode ~= "Compact" -- (a Compact row sits in a panel that shows the team's power already)
	end

	function row.Refresh()
		local entries = TeamFaces.Entries()
		local busy = busyOfTeam()
		local shown = isShown(root)
		for i, face in ipairs(faces) do
			paintFace(face, entries[i], busy[i - #entries], mode, shown)
		end
		local total = commas(TeamFaces.Power())
		power.Text = mode == "Column" and (SWORDS .. " " .. total) or ("Team power " .. total)
	end

	function row.SetMode(newMode)
		if newMode ~= mode then
			mode = newMode
			layout()
			row.Refresh()
		end
	end

	function row.Release()
		for _, face in ipairs(faces) do
			if face.Handle then
				pcall(face.Handle.Destroy)
				face.Handle = nil
			end
		end
	end

	function row.Destroy()
		row.Release()
		root:Destroy()
	end

	layout()
	row.Refresh()
	S.Rows[#S.Rows + 1] = row
	if not S.Conn then
		S.Conn = State.Changed:Connect(refreshRows)
	end
	return row
end

return TeamFaces
