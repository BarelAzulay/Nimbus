-- TeamFaces (client UI, team balance, spec s.2): the row every battle panel shows, the three pets that will fight with Edit team
-- beside them. It replaces client/TeamPick's strip and its "Pick your battle team" popup: there is one flow and no silent auto-fill.
--
--   TeamFaces.New(parent, props) -> { Root, Refresh = fn, SetMode = fn(mode), Height = fn() -> design px, Destroy = fn }
--       props = { LayoutOrder, Compact = bool, Column = bool, ReturnTo = table | fn() -> table (what Edit team hands to the Pets window),
--         SlotH = { Compact = h, Column = h } };
--       SetMode("Card" | "Compact" | "Column") when the window's layout changes.
--       (U9-7 look) props.SlotH: row.Slot, an empty frame "Slot" the window fills, takes the power line's place (TeamPower stays
--       hidden): beside Edit team in a Card row, a line of SlotH.Compact px under the faces in a Compact row, a line of
--       SlotH.Column px under a full-width Edit team in a Column (no height: no line). The Ring pins its champion there.
--       Frame "TeamFaces": Face1..Face3 (Picture, Tag "FIGHTER" | "HELPER", Level "L12", Power, Busy, StageBadge + attribute Stage; an open
--       slot shows Empty "Empty", a slot whose pet is busy shows Empty "Training" | "Gardening" and the Busy mark; a Compact
--       face the word alone, "Training" | "Garden"), TeamPower and
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
-- (kit-b U9-7) On the Signboard kit, as the Pets window's team slots: the row a sunk stone well, the faces stone tiles with the
-- rarity on their lip, FIGHTER / HELPER red / sky tags, Edit team a stone block (the panel's own action is its one green).
-- The server decides again (BattleService.TEAM_REFUSALS). Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7b) the power sword and the busy marks

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
	EDIT_W_TWO_LINES = 76, -- (kit-b U9-7) the Compact row's Edit team block, its words on two lines
	CARD_H = 96, -- the height of a face per mode
	COMPACT_H = 64,
	COLUMN_H = 46, -- (U9-7 look) the tag's line and the level's line no longer share 2 px
	COLUMN_PAD = 4,
	NO_PET = "You need a pet: spin a roulette in the Cloud Shop.",
	ALL_BUSY = "Your whole team is busy: training or gardening",
}

-- (kit-b U9-7) the Signboard palette (the Pets window's team slots, U8): the row is a sunk stone well, each face a raised
-- stone tile with the pet's rarity on its lip and the pet standing in a light well, FIGHTER a red tag and HELPER a sky
-- tag in brown ink, EVO a gold tag; brown ink on stone, the muted brown for the level and an empty slot
local SIGN = Theme.Sign
local INK = SIGN.Text
local MUTED = SIGN.TextMuted
local LIP = 4 -- design px of a face's lip
local ROLE_COLOR = { FIGHTER = SIGN.Red, HELPER = SIGN.Sky }
-- (kit-b U7b) PixelIcons, not emoji: the sword before a power, a busy slot's mark (training: the weight, garden: the sprout)
local POWER_ICON = "sword"
local BUSY_ICON = { Training = "weight", Garden = "sprout" }
local BUSY_WORD = { Training = "Training", Garden = "Gardening" }
-- (U9-7 look) a Compact face's busy slot: the word alone, centred under the tag (as an open slot's "Empty"); the 18 px mark
-- had a 20 px row between the tag and the word (it ran into both), and "Gardening" filled the tile edge to edge
local BUSY_SHORT = { Training = "Training", Garden = "Garden" }

local frame, text, stroke = Bits.frame, Bits.text, Bits.stroke

-- (kit-b U9-7) a square edge with mitred corners (kit B has no rounded blocks)
local function edge(parent, color, thickness)
	local s = stroke(parent, color, thickness, 0)
	s.Name = "SignEdge"
	s.LineJoinMode = Enum.LineJoinMode.Miter
	return s
end

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

-- a Compact face's power: 2,144 -> 2.14K (Theme.Short, the game's one short-number style; Pitch 2 F0)
local function shortPower(n)
	return Theme.Short(n)
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
	-- (kit-b U9-7) a raised stone tile in a wood edge; its lip takes the pet's rarity (paintFace)
	local cell = frame(root, "Face" .. i, { BackgroundTransparency = 0, BackgroundColor3 = SIGN.Tile })
	local face = { Cell = cell, Rim = edge(cell, SIGN.Wood, 2), Key = nil, Stage = 0 }
	face.Lip = frame(cell, "Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.StoneLip,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, LIP),
		ZIndex = 2,
	})
	face.Picture = frame(cell, "Picture", { BackgroundTransparency = 0, BackgroundColor3 = SIGN.PetWell, ZIndex = 2 })
	local role = i == 1 and "FIGHTER" or "HELPER"
	face.Tag = text(cell, "Tag", role, "Tag", 18, INK, {
		BackgroundTransparency = 0,
		BackgroundColor3 = ROLE_COLOR[role],
		ZIndex = 4,
	})
	face.Stage_ = text(cell, "StageBadge", "", "Button", 18, INK, {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Gold,
		Visible = false,
		ZIndex = 4,
	})
	edge(face.Stage_, SIGN.Wood, 2)
	face.Level = text(cell, "Level", "", "Heading", 18, MUTED, { TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	face.Power = text(cell, "Power", "", "Heading", 18, INK, {
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	face.Empty = text(cell, "Empty", "Empty", "Heading", 18, MUTED, { ZIndex = 3 })
	face.Busy = text(cell, "Busy", "", "Heading", 18, INK, { Visible = false, ZIndex = 4 })
	return face
end

-- x and y in pixels; the width is a share of the parent (wScale) plus pixels
local function place(obj, x, y, wScale, w, h)
	obj.Position = UDim2.fromOffset(x, y)
	obj.Size = UDim2.new(wScale, w, 0, h)
end

-- where a face's parts sit: everything hangs off the cell's edges, so a cell can be any width
local function layoutFace(face, mode)
	-- (kit-b U9-7) everything stays above the face's LIP px rarity lip
	if mode == "Column" then
		-- [picture] FIGHTER
		--           L12    sword 358
		-- (U9-7 look) the tag 2..20, the line under it 22..40: 2 px clear of each other and of the lip (the tag sat on the
		-- tops of "L57" and the sword, "Gardening" ran into the lip)
		local h = K.COLUMN_H
		local p = h - 2 - LIP
		local x = p + 6
		place(face.Picture, 2, 2, 0, p, p)
		place(face.Tag, x, 2, 0, 88, 18)
		place(face.Level, x, 22, 0, 44, 18)
		place(face.Power, x + 44, 22, 1, -(x + 48), 18)
		place(face.Empty, x, 22, 1, -(x + 4), 18)
		place(face.Busy, 2, 2, 0, p, p)
	elseif mode == "Compact" then
		-- FIGHTER (a line across)
		-- [picture] L12 / 358
		place(face.Tag, 2, 2, 1, -4, 20)
		place(face.Picture, 2, 22, 0, 34, 38 - LIP)
		place(face.Level, 38, 22, 1, -40, 20)
		place(face.Power, 38, 40, 1, -40, 20)
		place(face.Busy, 2, 22, 1, -4, 20)
	else
		local h = K.CARD_H
		place(face.Picture, 4, 4, 1, -8, h - 34)
		place(face.Tag, 4, 4, 0, 88, 22)
		place(face.Stage_, 96, 4, 0, 62, 22)
		place(face.Level, 8, h - 28, 0, 46, 24)
		place(face.Power, 54, h - 28, 1, -60, 24)
		place(face.Empty, 4, 28, 1, -8, h - 32 - LIP)
		place(face.Busy, 8, 28, 0, 26, h - 32 - LIP)
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
	face.Busy.Visible = entry == nil and busy ~= nil and mode ~= "Compact"
	-- (kit-b U9-7) an open slot is a sunk stone well, a filled one a raised tile
	face.Cell.BackgroundColor3 = entry and SIGN.Tile or SIGN.Well
	face.Rim.Color = entry and SIGN.Wood or SIGN.WellEdge
	if entry then
		face.Level.Text = "L" .. tostring(entry.Level)
		-- (kit-b U7b) the sword before a full power (a Compact face has room for the short number only); drawn on a change
		local sword = mode ~= "Compact"
		if face.PowerIcon ~= sword then
			face.PowerIcon = sword
			if sword then
				PixelIcon.Lead(face.Power, POWER_ICON)
			else
				PixelIcon.Clear(face.Power)
			end
		end
		face.Power.Text = sword and commas(entry.Power) or shortPower(entry.Power)
		face.Lip.BackgroundColor3 = CloudUI.RarityColor(entry.Def.Rarity) -- (kit-b U9-7) the rarity on the lip
		face.Stage_.Text = stage >= 2 and "EVO II" or "EVO I"
		face.Stage_.Visible = stage > 0 and mode == "Card" -- (the picture shows the stage; the smaller faces have no room for the badge)
	else
		face.Stage_.Visible = false
		face.Empty.Text = busy and ((mode == "Compact") and BUSY_SHORT[busy] or BUSY_WORD[busy]) or "Empty"
		local mark = busy and BUSY_ICON[busy] or nil
		if face.BusyIcon ~= mark then
			face.BusyIcon = mark
			PixelIcon.Host(face.Busy, mark or "") -- an unknown name drops the old mark
		end
		if mode == "Compact" then
			place(face.Empty, 2, 22, 1, -4, 38 - LIP)
		end
		face.Lip.BackgroundColor3 = SIGN.WellEdge
	end
end

----------------------------------------------------------------------
-- The row
----------------------------------------------------------------------
-- (U9-7 look) an object's width in its own design px: AbsoluteSize over the UIScales above it; 0 before the first layout
local function designWidth(obj)
	local s, cur = 1, obj
	while cur and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") then
			local ui = cur:FindFirstChildOfClass("UIScale")
			if ui and ui.Scale > 0 then
				s = s * ui.Scale
			end
		end
		cur = cur.Parent
	end
	local w = obj.AbsoluteSize.X
	return (w > 0) and (w / s + 0.001) or 0
end
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
	-- (kit-b U9-7) the row: a sunk stone well in its own darker edge (the pitch's .wl), square
	local root = frame(parent, "TeamFaces", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Well,
		LayoutOrder = props.LayoutOrder or 0,
	})
	edge(root, SIGN.WellEdge, 2)
	local faces = {}
	for i = 1, K.SLOTS do
		faces[i] = buildFace(root, i)
	end
	local power = text(root, "TeamPower", "", "Heading", 19, INK, {
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local edit = CloudUI.Button({
		Name = "EditTeam",
		Text = "Edit team",
		Style = "Gray",
		Skin = "Sign", -- (kit-b U9-7) a stone block: the panel's own action keeps the green
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

	local slotH = type(props.SlotH) == "table" and props.SlotH or nil
	local slot = slotH and frame(root, "Slot", {}) or nil
	local row = { Root = root, Slot = slot }

	-- (U9-7 look) the slot's own line in a Compact or Column row (a Card row has it beside Edit team)
	local function slotLine()
		local h = slotH and tonumber(slotH[mode]) or 0
		return (mode ~= "Card" and h > 0) and h or 0
	end

	function row.Height()
		local extra = slotLine() > 0 and (K.GAP + slotLine()) or 0
		if mode == "Column" then
			return K.COLUMN_PAD * 2 + K.SLOTS * K.COLUMN_H + (K.SLOTS - 1) * K.COLUMN_PAD + K.GAP + K.EDIT_H + extra
		elseif mode == "Compact" then
			return K.PAD * 2 + K.COMPACT_H + extra
		end
		return K.PAD * 2 + K.CARD_H + K.GAP + K.EDIT_H
	end

	function row.Mode()
		return mode
	end

	-- the cells of a row of faces: `taken` px of the row's width are not theirs. (U9-7 look) Whole design px once the row's
	-- width is known (thirds of it put the slot edges and rarity lips between pixels: 172.67 / 181.33 px), the remainder
	-- to the last face; a share of the width before the first layout
	local rowTaken, rowH = 0, 0
	local function faceRow(taken, h)
		rowTaken, rowH = taken, h
		local pad, n = K.PAD, K.SLOTS
		local width = designWidth(root)
		if width > 0 then
			local avail = math.floor(width) - 2 * pad - (n - 1) * K.GAP - taken
			local each = math.floor(avail / n)
			local x = pad
			for i, face in ipairs(faces) do
				local cw = (i == n) and (avail - each * (n - 1)) or each
				face.Cell.Position = UDim2.fromOffset(x, pad)
				face.Cell.Size = UDim2.fromOffset(cw, h)
				x = x + cw + K.GAP
			end
			return
		end
		local share = (2 * pad + (n - 1) * K.GAP + taken) / n
		for i, face in ipairs(faces) do
			face.Cell.Position = UDim2.new((i - 1) / n, pad + (i - 1) * (K.GAP - share), 0, pad)
			face.Cell.Size = UDim2.new(1 / n, -share, 0, h)
		end
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if mode ~= "Column" and rowH > 0 then
			faceRow(rowTaken, rowH)
		end
	end)

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
			edit.Size = slot and UDim2.new(1, -2 * pad, 0, K.EDIT_H) or UDim2.fromOffset(K.EDIT_W_COMPACT, K.EDIT_H)
			place(power, pad + 2, y, 1, -(2 * pad + K.EDIT_W_COMPACT + 6), K.EDIT_H)
			if slot then
				place(slot, pad, y + K.EDIT_H + K.GAP, 1, -2 * pad, slotLine())
			end
		elseif mode == "Compact" then
			-- (kit-b U9-7) "Edit team" on two lines in a narrower block: the faces get the room for a whole FIGHTER tag
			faceRow(K.EDIT_W_TWO_LINES + K.GAP, K.COMPACT_H)
			edit.Position = UDim2.new(1, -pad, 0, pad + (K.COMPACT_H - K.EDIT_H) / 2)
			edit.Size = UDim2.fromOffset(K.EDIT_W_TWO_LINES, K.EDIT_H)
			if slot then
				place(slot, pad + 2, pad + K.COMPACT_H + K.GAP, 1, -(2 * pad + 4), slotLine())
			end
		else
			faceRow(0, K.CARD_H)
			local y = pad + K.CARD_H + K.GAP
			edit.Position = UDim2.new(1, -pad, 0, y)
			edit.Size = UDim2.fromOffset(K.EDIT_W, K.EDIT_H)
			place(power, pad + 2, y, 1, -(2 * pad + K.EDIT_W + 6), K.EDIT_H)
			if slot then
				place(slot, pad + 2, y, 1, -(2 * pad + K.EDIT_W + 6), K.EDIT_H)
			end
		end
		power.Visible = mode ~= "Compact" and not slot -- (a Compact row sits in a panel that shows the team's power already)
		if slot then
			slot.Visible = mode == "Card" or slotLine() > 0
		end
		edit.TextWrapped = mode == "Compact"
		edit.TextTruncate = (mode == "Compact") and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
		edit.LineHeight = (mode == "Compact") and 0.9 or 1
		edit.TextSize = (mode == "Compact") and 19 or 20
	end

	function row.Refresh()
		if mode ~= "Column" and rowH > 0 and designWidth(root) > 0 then
			faceRow(rowTaken, rowH) -- (U9-7 look) whole px once the row is laid out
		end
		local entries = TeamFaces.Entries()
		local busy = busyOfTeam()
		local shown = isShown(root)
		for i, face in ipairs(faces) do
			paintFace(face, entries[i], busy[i - #entries], mode, shown)
		end
		local total = commas(TeamFaces.Power())
		local sword = mode == "Column" -- (kit-b U7b) a Column row says the power with the sword in front
		if row.PowerIcon ~= sword then
			row.PowerIcon = sword
			if sword then
				PixelIcon.Lead(power, POWER_ICON)
			else
				PixelIcon.Clear(power)
			end
		end
		power.Text = sword and total or ("Team power " .. total)
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
