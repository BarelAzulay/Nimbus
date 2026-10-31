-- DevController (client): the owner-only DEV button and its "Developer tools" side panel (Config.Dev; the server
-- half is server/Services/DevService.lua).
--
--   DevController.Init()
--   Extras (tests): DevController.Open(), DevController.Close(), DevController.IsOpen(), DevController.Relayout()
--   Phase 5 (7.2): chat "/menu" (owner only) -> DevController.OpenMainMenu(); DevController.OnChat(message) (tests)
--
-- Everything here only exists while the LocalPlayer's PlayerGui has the attribute NC_Dev = true (DevService sets it
-- for the game's owner, the Config.Dev.Admins and everyone testing in Studio; a PlayerGui only replicates to its own
-- player, so nobody else learns who the developers are). The attribute is watched; it is only a hint: the server
-- checks every command again. NC_DevTutorial = true (same place) shows "Restart tutorial": the server only sets it
-- when its TutorialService can restart a tutorial.
--
-- ScreenGui "NimbusDev" (display order 15, IgnoreGuiInset = false), built the first time NC_Dev turns true:
--   * DevTile: a chunky cloud tile in the menu tiles' style (glossy face, thick navy outline, big "DEV") with the
--     TextButton "DevButton", docked to the RIGHT edge. Its spot is MEASURED, never guessed: the lowest free place
--     on the right edge that touches none of the menu column, the HUD blocks (NimbusHud panels + its published
--     TopRight geometry), the battle HUD's visible blocks (NimbusBattle.Root: the action cluster, the team card, the
--     enemy list, the top card, LEAVE; bug #16), the hotbar, the tutorial panel, the touch RUN / DASH buttons and Roblox's jump button,
--     and stays out of the middle of the screen. On a PC that is the bottom-right corner; on phones and tablets it
--     sits just above the thumb buttons. The top of the side-toast column (NimbusNotify's ToastStack, measured;
--     room for its two newest toasts) is kept free too whenever the screen has room for that. Re-checked twice a
--     second and on every screen size change.
--   * DevPanel: a compact CloudUI panel docked to the right edge, never centred, titled "Developer tools":
--     "Give all pets", "+1M tokens" (Config.Dev.GrantTokens through Theme.ShortNumber), "Restart tutorial",
--     "Skip tutorial", "Start Boss Raid" (Phase 3: DevCommand "raid"), the pet showcase ("Evolve every pet" =
--     DevCommand("evolve", "all"), "Show all pets" / "Show evolved pets" / "Show Evolved II pets" =
--     DevCommand("pets", "0" | "1" | "2"), "Clear pet show" = DevCommand("clearpets"); client/Controllers/DevPetShow.lua
--     builds them), the tools on all my pets ("Evolve my pets" = DevCommand("evolvepets"); a number box and "Level all pets" =
--     DevCommand("levelall", n), junk in the box goes to the server, whose toast answers; "Max stats pets" =
--     DevCommand("maxpets"); "2x speed: off / on" = DevCommand("speed"), following the hint NC_DevSpeed), the list of everyone
--     in the server (a row "DevPlayer_<UserId>" per player, kept up to date; other players' rows have "Dev_kick_<UserId>" =
--     DevCommand("kick", name) and "Dev_ban_<UserId>" = DevCommand("ban", name), which asks "Are you sure?" like Reset), "Reset
--     my data" (the first tap turns it into "Are you sure?"; only a second, separate tap
--     0.6 to 4 s later sends it, so a double click never resets) and the note "Only you can see this". For the
--     first 0.4 s after it opens its buttons ignore taps (the rest of a double click on the tile lands there).
--     It takes a free stretch of the right edge below the toasts' room, so the toasts that answer its buttons
--     never cover it, preferring a stretch where it fits whole (see placePanel): while open it may lie over the
--     thumb buttons or HUD pieces (one tap closes it), never in the middle. Only a very short screen (a landscape
--     phone) has no such stretch: there the newest toasts may cover its top. When the stretch is short the
--     buttons scroll instead of shrinking the text. The tile hides while it is open.
--     Built on the first open, so a developer who never opens it only carries the small tile.
-- Input: mouse, touch and gamepad. Both are Selectable TextButtons (Activated covers click, tap and gamepad A);
-- opening the panel with a gamepad selects its first button; B (ContextActionService, only while open), Esc, the
-- red X and the tile close it.
-- Readability rule: designed in 1080p pixels under one UIScale of the screen factor clamp(viewportY / 1080,
-- 0.8, 1.25): buttons 22 px, title 28 px, note 18 px -> never below 14 px on a phone.
-- Remote out: DevCommand(command, arg). Plain Lua 5.1-compatible syntax only. Fonts only via Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))

local DevController = {}

----------------------------------------------------------------------
-- Tunables (design pixels of a 1080p screen unless noted)
----------------------------------------------------------------------
local K = {
	ATTR = "NC_Dev", -- PlayerGui attributes set by DevService
	ATTR_TUTORIAL = "NC_DevTutorial",
	ATTR_SPEED = "NC_DevSpeed",
	GUI_NAME = "NimbusDev",
	ORDER = 15, -- above the HUD (10), hotbar (11) and tutorial (12); below the menu windows (20) and toasts (30)
	EDGE = 12, -- KEEP IN SYNC with HudController.lua: EDGE and TOUCH_EDGE (screen px)
	TOUCH_EDGE = 20,
	GAP = 8, -- screen px kept free around every neighbour
	CENTRE_TOL = 0.145, -- the middle of the screen: |dx| < 14.5% of the width and |dy| < 14.5% of the height
	SCAN_STEP = 4, -- screen px between two candidate spots of the tile
	TILE = 84, -- same size as a menu tile
	TILE_MIN_SHRINK = 0.75, -- bug #16: the tile may shrink this far to fit a short screen's gap (text 30 x 0.75 = 22 design px)
	TILE_TEXT = 30,
	PANEL_W = 340,
	TITLE_TEXT = 28,
	BUTTON_H = 50,
	BUTTON_TEXT = 22,
	NOTE_TEXT = 18,
	NOTE_H = 26,
	ROW_TEXT = 18, -- the player rows and the box (x 0.8 on a phone: 14.4 px)
	ROW_NAME_H = 26, -- a player row's name line, above its two buttons
	ROW_GAP = 8, -- between Kick and Ban, and between the box and its button
	BOX_W = 84,
	DEFAULT_LEVEL = "100",
	BOX_MAX_TEXT = 16, -- characters of a junk box sent to the server
	LIST_PAD = 10,
	LIST_GAP = 8,
	BUMPS = 30, -- room the panel's cloud bumps (and their outline) need above its top edge
	MIN_PANEL_H = 230, -- the shortest (scrolling) panel worth showing
	MIN_SCALE = 0.5, -- only for absurdly small windows
	POLL = 0.5, -- seconds between two layout checks
	CONFIRM_SECONDS = 4, -- an armed "Are you sure?" disarms itself after this many seconds
	CONFIRM_DELAY = 0.6, -- seconds the confirming tap must come after the first one (a double click never resets)
	OPEN_GUARD = 0.4, -- seconds after opening during which the panel's buttons ignore taps
	SEND_GAP = 0.35, -- seconds between two commands sent from this panel
	-- design px kept free at the top of the side-toast column: its two newest toasts (the answer to a DEV button
	-- of up to 3 lines and one more of up to 4). KEEP IN SYNC with NotifyController.lua's toast: 18 px text,
	-- 8 px padding above and below, TOAST_GAP 8
	TOAST_ROOM = 200,
	BACK_ACTION = "NimbusDevBack",
}

local BUTTONS = Theme.Buttons or {}
local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local INK = Colors.TextStroke or Colors.Ink
local DEV_COLOR = Theme.Mix(Colors.Storm, BUTTONS.Blue or Color3.fromRGB(90, 158, 234), 0.3) -- slate blue

local LocalPlayer = nil
local initialized = false
local enabled = false
local panelOpen = false
local pollSerial = 0
local lastSend = -math.huge
local openedAt = -math.huge -- os.clock() of the last Open()
local warned = {}

local UI = {} -- Gui, Tile, TileScale, TileButton, TileFx, Panel, PanelRoot, PanelScale, List, Buttons = {}, PlayerList, Rows = {}
local Hint = { Gui = nil } -- the LocalPlayer's PlayerGui: DevService's NC_Dev / NC_DevTutorial live there
local Reset = { Until = 0, Serial = 0, ChangedAt = -math.huge, Text = "Reset my data" } -- ChangedAt: when it was last armed or sent
local Back = { Bound = false }
local applied = {} -- last values written by relayout (only changes are written)

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function warnOnce(key, err)
	if not warned[key] then
		warned[key] = true
		warn("[DevController] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function guard(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

local function devConfig()
	if type(Config.Dev) == "table" then
		return Config.Dev
	end
	return {}
end

local function isTouchDevice()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if vp.X < 2 or vp.Y < 2 then
		return Vector2.new(1920, 1080)
	end
	return vp
end

local function topInset()
	local inset = 0
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	return inset
end

-- The area GUIs with IgnoreGuiInset = false are laid out in (below the top bar).
local function guiAreaSize()
	local size = UI.Gui and UI.Gui.AbsoluteSize
	if size and size.X >= 2 and size.Y >= 2 then
		return size
	end
	local vp = viewportSize()
	return Vector2.new(vp.X, math.max(2, vp.Y - topInset()))
end

local function usingGamepad()
	local ok, kind = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	return ok and kind ~= nil and string.find(tostring(kind), "Gamepad", 1, true) ~= nil
end

local refreshTutorialButton -- defined with the panel (Building)

local function corner(parent, radius)
	return Util.Create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent, color, thickness)
	return Util.Create("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function plainFrame(parent, name, props)
	local frame = Util.Create("Frame", { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0 })
	for key, value in pairs(props or {}) do
		frame[key] = value
	end
	frame.Parent = parent
	return frame
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
local function devRemote()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("DevCommand")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

-- Fires DevCommand(command, arg). Returns true when it was sent (a quick double tap is dropped).
local function send(command, arg)
	local now = os.clock()
	if now - lastSend < K.SEND_GAP then
		return false
	end
	local remote = devRemote()
	if not remote then
		warnOnce("remote", "the DevCommand remote is missing")
		return false
	end
	lastSend = now
	remote:FireServer(command, arg)
	return true
end

local function grantTokens()
	local amount = tonumber(devConfig().GrantTokens)
	if not amount or amount ~= amount or amount < 1 then
		amount = 1000000
	end
	return math.floor(amount)
end

local function tokensLabel()
	local amount = grantTokens()
	local text = nil
	if type(Theme.ShortNumber) == "function" then
		local ok, short = pcall(Theme.ShortNumber, amount)
		if ok and type(short) == "string" then
			text = short
		end
	end
	return "+" .. (text or Util.Commas(amount)) .. " tokens"
end

-- Phase 2: test amounts of Cash and Gems (Config.Dev.GrantCash / GrantGems).
local function grantAmount(key, fallback)
	local amount = tonumber(devConfig()[key])
	if not amount or amount ~= amount or amount < 1 then
		amount = fallback
	end
	return math.floor(amount)
end

local function amountLabel(amount, word)
	local text = nil
	if type(Theme.ShortNumber) == "function" then
		local ok, short = pcall(Theme.ShortNumber, amount)
		if ok and type(short) == "string" then
			text = short
		end
	end
	return "+" .. (text or Util.Commas(amount)) .. " " .. word
end

local function disarm(confirm)
	confirm.Until = 0
	confirm.Serial = confirm.Serial + 1
	if confirm.Button then
		confirm.Button.Text = confirm.Text
	end
end

-- First tap arms the button ("Are you sure?"); a second tap sends the command when it comes CONFIRM_DELAY to
-- CONFIRM_SECONDS later. A tap sooner than CONFIRM_DELAY after arming (or after sending) is ignored and the button
-- stays as it is: a double click, however fast, can never wipe the data or ban anyone. fire() -> true when it was sent.
local function confirmPress(confirm, fire)
	local now = os.clock()
	if now - confirm.ChangedAt < K.CONFIRM_DELAY then
		return
	end
	if confirm.Until > now then
		if fire() then
			disarm(confirm)
			confirm.ChangedAt = now
		end
		return
	end
	confirm.Until = now + K.CONFIRM_SECONDS
	confirm.ChangedAt = now
	confirm.Serial = confirm.Serial + 1
	local serial = confirm.Serial
	confirm.Button.Text = "Are you sure?"
	task.delay(K.CONFIRM_SECONDS, function()
		if confirm.Serial == serial then
			disarm(confirm)
		end
	end)
end

local function speedLabel()
	return (Hint.Gui ~= nil and Hint.Gui:GetAttribute(K.ATTR_SPEED) == true) and "2x speed: on" or "2x speed: off"
end

local function refreshSpeedButton()
	local button = UI.Buttons and UI.Buttons.speed
	if button then
		button.Text = speedLabel()
	end
end

-- The level box: a whole number, or its text as it is (the server refuses that with a toast).
local function levelFromBox()
	local text = string.match(UI.LevelBox.Text, "^%s*(.-)%s*$") or ""
	return tonumber(text) or string.sub(text, 1, K.BOX_MAX_TEXT)
end

-- A panel button's press, ignored for OPEN_GUARD seconds after the panel opened: the panel opens where the DEV
-- tile was, so the second click of a double click on the tile would otherwise land on one of its buttons.
local function panelPress(action)
	return function()
		if os.clock() - openedAt < K.OPEN_GUARD then
			return
		end
		action()
	end
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------
-- Glossy chunky face (same recipe as the menu tiles): light top, the colour, then a darker lip at the bottom.
local function tileSequence(c)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Lighten(c, 0.34)),
		ColorSequenceKeypoint.new(0.5, Theme.Lighten(c, 0.05)),
		ColorSequenceKeypoint.new(0.78, Theme.Darken(c, 0.08)),
		ColorSequenceKeypoint.new(0.8, Theme.Darken(c, 0.32)),
		ColorSequenceKeypoint.new(1, Theme.Darken(c, 0.4)),
	})
end

local function buildTile(gui)
	local tile = plainFrame(gui, "DevTile", {
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(K.TILE, K.TILE),
		Position = UDim2.new(1, -K.EDGE, 1, -K.EDGE),
		ZIndex = 2,
	})
	UI.Tile = tile
	UI.TileScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = tile })

	local button = Util.Create("TextButton", {
		Name = "DevButton",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Selectable = true,
		ZIndex = 3,
		Parent = tile,
	})
	UI.TileButton = button
	corner(button, 18)
	local outline = stroke(button, NAVY, 4)
	local face = Util.Create("UIGradient", { Rotation = 90, Color = tileSequence(DEV_COLOR), Parent = button })
	local gloss = plainFrame(button, "Gloss", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.new(1, -16, 0.3, 0),
		ZIndex = 3,
	})
	corner(gloss, 10)
	-- two tiny pixel glints, like the menu tiles (a nod to the voxel world)
	for i, glint in ipairs({ { 10, 9, 6 }, { 18, 9, 4 } }) do
		plainFrame(button, "Glint" .. i, {
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.15,
			Position = UDim2.fromOffset(glint[1], glint[2]),
			Size = UDim2.fromOffset(glint[3], glint[3]),
			ZIndex = 4,
		})
	end
	local label = Theme.Label("DEV", "Title", {
		Size = K.TILE_TEXT,
		Stroke = 0.1,
		StrokeColor = INK,
		Outline = 2.5,
		OutlineColor = INK,
		Props = {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.new(1, -8, 0, 36),
			ZIndex = 5,
		},
	})
	label.Parent = button

	-- hover / press feedback (same feel as the menu tiles)
	local fx = Util.Create("UIScale", { Name = "FxScale", Scale = 1, Parent = button })
	local state = { Hovering = false, Pressing = false }
	local function paint()
		local color = DEV_COLOR
		local scale = 1
		if state.Pressing then
			color = Theme.Darken(DEV_COLOR, 0.08)
			scale = 0.93
		elseif state.Hovering then
			color = Theme.Lighten(DEV_COLOR, 0.1)
			scale = 1.07
		end
		face.Color = tileSequence(color)
		outline.Color = NAVY
		Util.Tween(fx, 0.1, { Scale = scale })
	end
	button.MouseEnter:Connect(function()
		state.Hovering = true
		paint()
	end)
	button.MouseLeave:Connect(function()
		state.Hovering, state.Pressing = false, false
		paint()
	end)
	button.MouseButton1Down:Connect(function()
		state.Pressing = true
		paint()
	end)
	button.MouseButton1Up:Connect(function()
		state.Pressing = false
		paint()
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			state.Hovering, state.Pressing = false, false
			paint()
		end
	end)
	button.Activated:Connect(function()
		guard("open", DevController.Open)
	end)
	CloudUI.Tooltip(button, function()
		return "Developer tools (only you)"
	end)
end

-- Design height of the whole panel when nothing is cut off (count buttons + the player list).
local function fullPanelHeight(count)
	local top, _, bottom = CloudUI.ContentInset(true)
	local list = 2 * K.LIST_PAD + count * (K.BUTTON_H + K.LIST_GAP) + K.NOTE_H
	if UI.PlayerList then
		list = list + UI.PlayerList.Size.Y.Offset + K.LIST_GAP
	end
	return top + list + bottom
end

-- True when the server says "Restart tutorial" works in this build (NC_DevTutorial on our PlayerGui).
local function tutorialAvailable()
	return Hint.Gui ~= nil and Hint.Gui:GetAttribute(K.ATTR_TUTORIAL) == true
end

-- Shows "Restart tutorial" only when it works, and sizes the panel for the buttons that are shown.
function refreshTutorialButton()
	local button = UI.Buttons and UI.Buttons.tutorial
	if not button then
		return -- the panel is not built yet: it asks again when it is
	end
	button.Visible = tutorialAvailable()
	local shown = 0
	for _, b in ipairs(UI.Buttons) do
		if b.Visible then
			shown = shown + 1
		end
	end
	UI.FullHeight = fullPanelHeight(shown)
	DevController.Relayout()
end

-- One row of the player list: the name, and for other players Kick and Ban (Ban asks "Are you sure?" first).
local function buildPlayerRow(player)
	local id = player.UserId
	local mine = player == LocalPlayer
	local row = plainFrame(UI.PlayerList, "DevPlayer_" .. id, {
		Size = UDim2.new(1, 0, 0, mine and K.ROW_NAME_H or (K.ROW_NAME_H + K.BUTTON_H)),
	})
	local label = Theme.Label(mine and (player.DisplayName .. " (you)") or (player.DisplayName .. " (@" .. player.Name .. ")"), "Label", {
		Size = K.ROW_TEXT,
		Stroke = 0.3,
		Outline = 1.5,
		Props = {
			Name = "PlayerName",
			Size = UDim2.new(1, 0, 0, K.ROW_NAME_H),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 6,
		},
	})
	label.Parent = row
	local entry = { Row = row, Confirm = nil }
	if not mine then
		local target = tostring(player.UserId) -- the server finds exactly this player, or nobody once they left
		local half = UDim2.new(0.5, -K.ROW_GAP / 2, 0, K.BUTTON_H)
		local kick = CloudUI.Button({
			Name = "Dev_kick_" .. id,
			Text = "Kick",
			Style = "Gold",
			Size = half,
			Position = UDim2.fromOffset(0, K.ROW_NAME_H),
			TextSize = K.ROW_TEXT,
			ZIndex = 6,
			Callback = panelPress(function()
				send("kick", target)
			end),
			Parent = row,
		})
		kick.Selectable = true
		local confirm = { Until = 0, Serial = 0, ChangedAt = -math.huge, Text = "Ban" }
		local ban = CloudUI.Button({
			Name = "Dev_ban_" .. id,
			Text = confirm.Text,
			Style = "Red",
			Size = half,
			Position = UDim2.new(0.5, K.ROW_GAP / 2, 0, K.ROW_NAME_H),
			TextSize = K.ROW_TEXT,
			ZIndex = 6,
			Callback = panelPress(function()
				guard("ban", confirmPress, confirm, function()
					return send("ban", target)
				end)
			end),
			Parent = row,
		})
		ban.Selectable = true
		confirm.Button = ban
		entry.Confirm = confirm
	end
	return entry
end

-- The list follows the server: a row per player, sorted by name; the panel's height follows the list.
local function refreshPlayerList(leaving)
	local holder = UI.PlayerList
	if not holder then
		return
	end
	local present = {}
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= leaving then
			present[player.UserId] = true
			list[#list + 1] = player
		end
	end
	for id, entry in pairs(UI.Rows) do
		if not present[id] then
			entry.Row:Destroy()
			UI.Rows[id] = nil
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	local height = K.NOTE_H
	for index, player in ipairs(list) do
		local entry = UI.Rows[player.UserId]
		if not entry then
			entry = buildPlayerRow(player)
			UI.Rows[player.UserId] = entry
		end
		entry.Row.LayoutOrder = index + 1
		height = height + K.LIST_GAP + entry.Row.Size.Y.Offset
	end
	holder.Size = UDim2.new(1, 0, 0, height)
	refreshTutorialButton()
end

local function buildPlayerSection(parent, order)
	local holder = plainFrame(parent, "DevPlayers", { Size = UDim2.new(1, 0, 0, K.NOTE_H), LayoutOrder = order })
	UI.PlayerList = holder
	UI.Rows = {}
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, K.LIST_GAP),
		Parent = holder,
	})
	local title = Theme.Label("Players in this server", "Label", {
		Size = K.ROW_TEXT,
		Stroke = 0.3,
		Outline = 1.5,
		Props = {
			Name = "PlayersTitle",
			Size = UDim2.new(1, 0, 0, K.NOTE_H),
			LayoutOrder = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
		},
	})
	title.Parent = holder
	if not UI.PlayersHooked then
		UI.PlayersHooked = true
		Players.PlayerAdded:Connect(function()
			guard("players", refreshPlayerList)
		end)
		Players.PlayerRemoving:Connect(function(player)
			guard("players", refreshPlayerList, player)
		end)
	end
end

-- The number box and "Level all pets" side by side, one button's height.
local function buildLevelRow(parent, order, callback)
	local row = plainFrame(parent, "Dev_levelrow", { Size = UDim2.new(1, 0, 0, K.BUTTON_H), LayoutOrder = order })
	local box = Util.Create("TextBox", {
		Name = "Dev_levelbox",
		Text = K.DEFAULT_LEVEL,
		PlaceholderText = "1-100",
		ClearTextOnFocus = false,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		TextColor3 = NAVY,
		Size = UDim2.new(0, K.BOX_W, 1, 0),
		Selectable = true,
		ZIndex = 6,
		Parent = row,
	})
	Theme.Style(box, "Button", { Size = K.BUTTON_TEXT })
	box.TextColor3 = NAVY
	corner(box, 10)
	stroke(box, NAVY, 2)
	UI.LevelBox = box
	return CloudUI.Button({
		Name = "Dev_levelall",
		Text = "Level all pets",
		Style = "Green",
		Size = UDim2.new(1, -(K.BOX_W + K.ROW_GAP), 1, 0),
		Position = UDim2.fromOffset(K.BOX_W + K.ROW_GAP, 0),
		TextSize = K.ROW_TEXT,
		ZIndex = 6,
		Callback = callback,
		Parent = row,
	})
end

local function buildPanel(gui)
	local specs = {
		{ Id = "allpets", Text = "Give all pets", Style = "Green" },
		{ Id = "tokens", Text = tokensLabel(), Style = "Gold" },
		{ Id = "cash", Text = amountLabel(grantAmount("GrantCash", 1000000), "Cash"), Style = "Green" },
		{ Id = "gems", Text = amountLabel(grantAmount("GrantGems", 1000), "Gems"), Style = "Blue" },
		{ Id = "tutorial", Text = "Restart tutorial", Style = "Blue" },
		{ Id = "skiptutorial", Text = "Skip tutorial", Style = "Pink" },
		{ Id = "raid", Text = "Start Boss Raid", Style = "Gold" }, -- Phase 3 (events): DevCommand("raid")
		-- the pet showcase (DevService: evolve / pets / clearpets)
		{ Id = "evolveall", Text = "Evolve every pet", Style = "Gold", Command = "evolve", Arg = "all" },
		{ Id = "pets0", Text = "Show all pets", Style = "Blue", Command = "pets", Arg = "0" },
		{ Id = "pets1", Text = "Show evolved pets", Style = "Blue", Command = "pets", Arg = "1" },
		{ Id = "pets2", Text = "Show Evolved II pets", Style = "Blue", Command = "pets", Arg = "2" },
		{ Id = "clearpets", Text = "Clear pet show", Style = "Gray", Command = "clearpets" },
		-- the tools on all my pets, saved (DevService: evolvepets / levelall / maxpets), and 2x speed
		{ Id = "evolvepets", Text = "Evolve my pets", Style = "Green" },
		{ Id = "levelall", Text = "Level all pets", Style = "Green" },
		{ Id = "maxpets", Text = "Max stats pets", Style = "Gold" },
		{ Id = "speed", Text = speedLabel(), Style = "Blue" },
		{ Id = "players" },
		{ Id = "reset", Text = "Reset my data", Style = "Red" },
	}
	UI.FullHeight = fullPanelHeight(#specs)
	local panel = CloudUI.Panel({
		Name = "DevPanel",
		Title = "Developer tools",
		TitleSize = K.TITLE_TEXT,
		Closable = true,
		OnClose = function()
			DevController.Close()
		end,
		Accent = DEV_COLOR,
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(K.PANEL_W, UI.FullHeight),
		Position = UDim2.new(1, -K.EDGE, 1, -K.EDGE),
		Parent = gui,
	})
	UI.Panel = panel
	UI.PanelRoot = panel.Root
	UI.PanelRoot.Visible = false
	UI.PanelScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = panel.Root })

	local list = Util.Create("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = WHITE,
		ZIndex = 5,
		Parent = panel.Content,
	})
	UI.List = list
	Util.Create("UIPadding", {
		PaddingTop = UDim.new(0, K.LIST_PAD),
		PaddingBottom = UDim.new(0, K.LIST_PAD),
		PaddingLeft = UDim.new(0, K.LIST_PAD),
		PaddingRight = UDim.new(0, K.LIST_PAD + 4),
		Parent = list,
	})
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, K.LIST_GAP),
		Parent = list,
	})

	UI.Buttons = {}
	local buttonCount = 0
	local function makeButton(index, spec, callback)
		local id = spec.Id
		local button
		if id == "levelall" then
			button = buildLevelRow(list, index, callback)
		else
			button = CloudUI.Button({
				Name = "Dev_" .. id,
				Text = spec.Text,
				Style = spec.Style,
				Size = UDim2.new(1, 0, 0, K.BUTTON_H),
				TextSize = K.BUTTON_TEXT,
				LayoutOrder = index,
				ZIndex = 6,
				Callback = callback,
				Parent = list,
			})
		end
		button.Selectable = true
		buttonCount = buttonCount + 1
		UI.Buttons[id] = button
		UI.Buttons[buttonCount] = button
		if id == "reset" then
			Reset.Button = button
		end
	end
	for index, spec in ipairs(specs) do
		local id = spec.Id
		local callback
		if id == "reset" then
			callback = panelPress(function()
				guard("reset", confirmPress, Reset, function()
					return send("reset")
				end)
			end)
		elseif id == "levelall" then
			callback = panelPress(function()
				send("levelall", levelFromBox())
			end)
		elseif id == "tokens" then
			callback = panelPress(function()
				send("tokens", grantTokens())
			end)
		elseif id == "cash" then
			callback = panelPress(function()
				send("cash", grantAmount("GrantCash", 1000000))
			end)
		elseif id == "gems" then
			callback = panelPress(function()
				send("gems", grantAmount("GrantGems", 1000))
			end)
		elseif spec.Command then
			callback = panelPress(function()
				send(spec.Command, spec.Arg)
			end)
		else
			callback = panelPress(function()
				send(id)
			end)
		end
		if id == "players" then
			buildPlayerSection(list, index)
		else
			makeButton(index, spec, callback)
		end
	end
	local note = Theme.Label("Only you can see this", "Label", {
		Size = K.NOTE_TEXT,
		Color = Colors.Muted or WHITE,
		Stroke = 0.3,
		Outline = 1.5,
		Props = {
			Name = "Note",
			Size = UDim2.new(1, 0, 0, K.NOTE_H),
			LayoutOrder = #specs + 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
		},
	})
	note.Parent = list
	refreshPlayerList()
end

local function build()
	if UI.Gui and UI.Gui.Parent then
		return
	end
	local gui = CloudUI.NewScreenGui(K.GUI_NAME, K.ORDER)
	gui.Enabled = false
	UI.Gui = gui
	applied = {}
	UI.PanelRoot = nil -- the panel is built on first open (a developer who never opens it only pays for the tile)
	buildTile(gui)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		guard("relayout", DevController.Relayout)
	end)
end

----------------------------------------------------------------------
-- Layout: measured neighbours (all rectangles in our gui-area pixels)
----------------------------------------------------------------------
local function playerGui()
	return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

-- y offset that converts a gui's AbsolutePosition into our gui-area coordinates
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

local function addRect(list, inst, root, dy)
	if not (inst and inst:IsA("GuiObject")) then
		return
	end
	local p, s = inst.AbsolutePosition, inst.AbsoluteSize
	if s.X <= 0 or s.Y <= 0 or not shownIn(inst, root) then
		return
	end
	list[#list + 1] = { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
end

local function enabledGui(pg, name)
	local gui = pg:FindFirstChild(name)
	if gui and gui:IsA("ScreenGui") and gui.Enabled then
		return gui
	end
	return nil
end

-- The side toasts (NimbusNotify, drawn above us): the measured left / right edges and top of the toast column,
-- reserved TOAST_ROOM design px down, so its newest toasts (the answers to the panel's buttons) stay readable.
-- nil when there is no toast column.
local function toastRoom(pg, factor)
	local notify = enabledGui(pg, "NimbusNotify")
	local stack = notify and notify:FindFirstChild("ToastStack", true)
	if not (stack and stack:IsA("GuiObject")) or stack.AbsoluteSize.X <= 0 then
		return nil
	end
	local p, s = stack.AbsolutePosition, stack.AbsoluteSize
	local top = p.Y + insetShift(notify)
	return { x0 = p.X, y0 = top, x1 = p.X + s.X, y1 = top + K.TOAST_ROOM * factor }
end

-- What the DEV tile and panel keep clear of (gui-area rectangles):
--   Others          the menu column, HUD blocks, hotbar, tutorial panel, touch buttons (the tile never touches them)
--   Toasts          the toast column's room, or nil
--   TopRightBottom  the bottom of the HUD's top-right block (0 if none), TopRightLeft its left edge
local function neighbours(area, factor)
	local out = {}
	local layout = { Others = out, Toasts = nil, TopRightBottom = 0, TopRightLeft = area.X }
	local pg = playerGui()
	if not pg then
		return layout
	end
	layout.Toasts = toastRoom(pg, factor)
	local menu = enabledGui(pg, "NimbusMenu")
	if menu then
		addRect(out, menu:FindFirstChild("MenuColumn"), menu, insetShift(menu))
	end
	local hud = enabledGui(pg, "NimbusHud")
	if hud then
		local dy = insetShift(hud)
		for _, holder in ipairs(hud:GetChildren()) do
			if holder:IsA("GuiObject") and holder.Visible then
				for _, panel in ipairs(holder:GetChildren()) do
					addRect(out, panel, hud, dy)
				end
			end
		end
		local trb = tonumber(hud:GetAttribute("TopRightBottom")) or 0
		if trb > 0 then
			layout.TopRightBottom = trb
			layout.TopRightLeft = tonumber(hud:GetAttribute("TopRightLeft")) or 0
			out[#out + 1] = { x0 = layout.TopRightLeft, y0 = 0, x1 = area.X, y1 = trb }
		end
	end
	-- bug #16: the battle HUD (BattleController's NimbusBattle): every visible top-level block of its Root (the action
	-- cluster Commands, Team, Enemies, TopCard, LEAVE, ...), so the tile never sits on the ATTACK button; plus the
	-- cluster's own buttons (on a phone the Commands frame is a small anchor and its buttons sit outside it)
	local battle = enabledGui(pg, "NimbusBattle")
	if battle then
		local root = battle:FindFirstChild("Root")
		local dy = insetShift(battle)
		for _, block in ipairs(root and root:GetChildren() or {}) do
			if block:IsA("GuiObject") and block.Visible then
				addRect(out, block, battle, dy)
				if block.Name == "Commands" then
					for _, b in ipairs(block:GetChildren()) do
						if b:IsA("GuiObject") then
							addRect(out, b, battle, dy)
						end
					end
				end
			end
		end
	end
	local hotbar = enabledGui(pg, "NimbusHotbar")
	if hotbar then
		addRect(out, hotbar:FindFirstChild("Hotbar"), hotbar, insetShift(hotbar))
	end
	local tutorial = enabledGui(pg, "NimbusTutorial")
	if tutorial then
		addRect(out, tutorial:FindFirstChild("TutorialPanel"), tutorial, insetShift(tutorial))
	end
	-- touch RUN / DASH (MovementController)
	local mobile = enabledGui(pg, "MobileControls")
	if mobile then
		local dy = insetShift(mobile)
		for _, d in ipairs(mobile:GetDescendants()) do
			if d:IsA("TextButton") or d:IsA("ImageButton") then
				addRect(out, d, mobile, dy)
			end
		end
	end
	-- Roblox's own jump button; when it cannot be measured, the footprint MovementController assumes
	-- (KEEP IN SYNC with MovementController.lua layoutMobileControls)
	local measured = false
	local touchGui = enabledGui(pg, "TouchGui")
	if touchGui then
		local jump = touchGui:FindFirstChild("JumpButton", true)
		if jump then
			local before = #out
			addRect(out, jump, touchGui, insetShift(touchGui))
			measured = #out > before
		end
	end
	if not measured and isTouchDevice() then
		local vp = viewportSize()
		local small = math.min(vp.X, vp.Y) <= 500
		local size = small and 70 or 120
		local bottom = small and 20 or size * 0.75
		local dy = area.Y - vp.Y -- screen -> gui area (minus the top bar)
		out[#out + 1] = {
			x0 = vp.X - (size * 1.5 + 10),
			y0 = vp.Y - bottom - size + dy,
			x1 = vp.X - (size * 0.5 + 10),
			y1 = vp.Y - bottom + dy,
		}
	end
	return layout
end

-- A new list with the rectangles of `a` and `b` (either may be a list, one rectangle or nil).
local function joined(a, b)
	local out = {}
	for _, part in ipairs({ a or {}, b or {} }) do
		if part.x0 then
			out[#out + 1] = part
		else
			for _, r in ipairs(part) do
				out[#out + 1] = r
			end
		end
	end
	return out
end

-- The middle of the screen the game never writes into (same band as the HUD), in gui-area pixels.
local function centreBand(area)
	local vp = viewportSize()
	local inset = math.max(0, vp.Y - area.Y)
	local tol = K.CENTRE_TOL
	return {
		x0 = vp.X * (0.5 - tol),
		x1 = vp.X * (0.5 + tol),
		y0 = vp.Y * (0.5 - tol) - inset,
		y1 = vp.Y * (0.5 + tol) - inset,
	}
end

local function touches(a, b, gap)
	return a.x0 < b.x1 + gap and a.x1 > b.x0 - gap and a.y0 < b.y1 + gap and a.y1 > b.y0 - gap
end

-- Bottom edge (gui px) of the lowest spot for a size x size tile at the right edge `right` that touches no
-- blocker and stays out of the band; nil when there is none. `precise`: a blocked candidate jumps to just above
-- the blocker it touches (no SCAN_STEP grid), so a narrow gap that just fits the tile is found.
local function lowestFreeSpot(area, side, right, size, blockers, band, precise)
	local y1 = area.Y - side
	while y1 - size >= side do
		local rect = { x0 = right - size, y0 = y1 - size, x1 = right, y1 = y1 }
		local free = not touches(rect, band, 0)
		local nextY = y1 - K.SCAN_STEP
		if free then
			for _, r in ipairs(blockers) do
				if touches(rect, r, K.GAP) then
					free = false
					if precise then
						nextY = math.min(y1 - 0.5, r.y0 - K.GAP - 0.01)
					end
					break
				end
			end
		elseif precise then
			nextY = y1 - 1
		end
		if free then
			return y1
		end
		y1 = nextY
	end
	return nil
end

-- Bottom-right corner (gui px) of the tile and its size share: the lowest free spot on the right edge, clear of
-- the toasts' room too when the screen has space for that (a short phone screen has not: then only toasts may
-- touch it). Bug #16: a short landscape phone in a battle (the enemy list above, the thumb buttons below) may have
-- no full-size stretch left on the right edge: the tile then shrinks (down to TILE_MIN_SHRINK, its text stays
-- readable) into the biggest gap rather than covering the battle HUD.
local function placeTile(area, side, size, layout, band)
	local right = area.X - side
	for _, blockers in ipairs({ joined(layout.Others, layout.Toasts), layout.Others }) do
		local y1 = lowestFreeSpot(area, side, right, size, blockers, band)
		if y1 then
			return right, y1, 1
		end
	end
	local shrink = 1
	while shrink > K.TILE_MIN_SHRINK + 1e-9 do
		shrink = math.max(K.TILE_MIN_SHRINK, shrink - 0.05)
		for _, blockers in ipairs({ joined(layout.Others, layout.Toasts), layout.Others }) do
			local y1 = lowestFreeSpot(area, side, right, size * shrink, blockers, band, true)
			if y1 then
				return right, y1, shrink
			end
		end
	end
	-- no free spot at all (a tiny window): the top-right corner
	return right, math.min(area.Y - side, side + size), 1
end

-- Free vertical stretches [y0, y1] of the column [x0, x1] between top and bottom. `headroom` is kept free below
-- every blocker as well (the panel's cloud bumps stick out above its top edge).
local function freeStretches(x0, x1, top, bottom, blockers, headroom)
	local spans = {}
	for _, r in ipairs(blockers) do
		if r.x0 < x1 + K.GAP and r.x1 > x0 - K.GAP and r.y1 + K.GAP > top and r.y0 - K.GAP < bottom then
			spans[#spans + 1] = { r.y0 - K.GAP, r.y1 + K.GAP + headroom }
		end
	end
	table.sort(spans, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local cursor = top
	for _, span in ipairs(spans) do
		if span[1] > cursor then
			out[#out + 1] = { cursor, math.min(span[1], bottom) }
		end
		cursor = math.max(cursor, span[2])
	end
	if cursor < bottom then
		out[#out + 1] = { cursor, bottom }
	end
	return out
end

-- The tallest free stretch (the lower one on a tie); nil when none is at least minH tall.
local function bestStretch(stretches, minH)
	local best = nil
	for _, s in ipairs(stretches) do
		local h = s[2] - s[1]
		if h >= minH and (best == nil or h >= best[2] - best[1]) then
			best = s
		end
	end
	return best
end

-- Bottom-right corner, design height and scale of the open panel. While it is open the panel is what the
-- developer uses, so it should be whole and uncovered: it may then lie over the thumb buttons or HUD pieces (one
-- tap closes it), but never over the toasts' room or in the middle of the screen. Tried in this order:
--   1. clear of everything, full height        2. clear of the toasts' room and the middle, full height
--   3. clear of everything, scrolling           4. clear of the toasts' room and the middle, scrolling
--   5. out of the middle only (a very short screen: the newest toasts may cover its top)
local function placePanel(area, side, factor, layout, band)
	local scale = math.max(K.MIN_SCALE, math.min(factor, (area.X - 2 * side) / K.PANEL_W))
	local right = area.X - side
	local left = right - K.PANEL_W * scale
	local bumps = K.BUMPS * scale
	local top = side
	if layout.TopRightBottom > 0 and layout.TopRightLeft < right then
		top = math.max(top, layout.TopRightBottom + K.GAP) -- the HUD's top-right block always stays visible
	end
	top = top + bumps
	local bottom = area.Y - side
	local fullH = (UI.FullHeight or 400) * scale
	local minH = math.min(K.MIN_PANEL_H * scale, bottom - top)
	local bandBlock = nil
	if left < band.x1 and right > band.x0 then
		bandBlock = { x0 = left, x1 = right, y0 = band.y0 + K.GAP, y1 = band.y1 - K.GAP }
	end
	local everything = joined(joined(layout.Others, layout.Toasts), bandBlock)
	local toastsAndMiddle = joined(layout.Toasts, bandBlock)
	local tries = {
		{ everything, fullH },
		{ toastsAndMiddle, fullH },
		{ everything, minH },
		{ toastsAndMiddle, minH },
		{ joined(bandBlock, nil), minH },
	}
	local stretch = nil
	for _, try in ipairs(tries) do
		stretch = bestStretch(freeStretches(left, right, top, bottom, try[1], bumps), try[2])
		if stretch then
			break
		end
	end
	stretch = stretch or { top, bottom }
	local height = math.min(UI.FullHeight or 400, (stretch[2] - stretch[1]) / scale)
	return right, stretch[2], height, scale
end

local function setIfChanged(key, inst, prop, value)
	if applied[key] ~= value then
		applied[key] = value
		inst[prop] = value
	end
end

function DevController.Relayout()
	if not UI.Gui or not enabled then
		return
	end
	local area = guiAreaSize()
	local factor = Theme.ScreenFactor(viewportSize().Y)
	local side = isTouchDevice() and K.TOUCH_EDGE or K.EDGE
	local layout = neighbours(area, factor)
	local band = centreBand(area)
	local tx, ty, shrink = placeTile(area, side, K.TILE * factor, layout, band)
	setIfChanged("tileScale", UI.TileScale, "Scale", factor * shrink)
	setIfChanged("tilePos", UI.Tile, "Position", UDim2.fromOffset(math.floor(tx + 0.5), math.floor(ty + 0.5)))
	if panelOpen then
		local px, py, height, scale = placePanel(area, side, factor, layout, band)
		setIfChanged("panelScale", UI.PanelScale, "Scale", scale)
		setIfChanged("panelSize", UI.PanelRoot, "Size", UDim2.fromOffset(K.PANEL_W, math.floor(height)))
		setIfChanged("panelPos", UI.PanelRoot, "Position", UDim2.fromOffset(math.floor(px + 0.5), math.floor(py + 0.5)))
	end
end

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------
local function onBackAction(_name, inputState)
	if inputState == Enum.UserInputState.Begin and panelOpen then
		DevController.Close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function bindBack(on)
	if on == Back.Bound then
		return
	end
	Back.Bound = on
	if on then
		guard("bind back", function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, onBackAction, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.ButtonB)
		end)
	else
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

local function selectionInside(root)
	local selected = GuiService.SelectedObject
	return selected ~= nil and root ~= nil and selected:IsDescendantOf(root)
end

function DevController.IsOpen()
	return panelOpen
end

function DevController.Open()
	if not enabled or not UI.Gui then
		return false
	end
	if panelOpen then
		DevController.Close()
		return false
	end
	if not (UI.PanelRoot and UI.PanelRoot.Parent) then
		if not guard("build panel", buildPanel, UI.Gui) then
			return false
		end
	end
	panelOpen = true
	openedAt = os.clock()
	disarm(Reset)
	UI.PanelRoot.Visible = true
	UI.Tile.Visible = false
	DevController.Relayout()
	bindBack(true)
	if usingGamepad() and UI.Buttons[1] then
		pcall(function()
			GuiService.SelectedObject = UI.Buttons[1]
		end)
	end
	return true
end

function DevController.Close()
	if not panelOpen then
		return
	end
	panelOpen = false
	disarm(Reset)
	for _, entry in pairs(UI.Rows or {}) do
		if entry.Confirm then
			disarm(entry.Confirm)
		end
	end
	local hadSelection = selectionInside(UI.PanelRoot)
	if UI.PanelRoot then
		UI.PanelRoot.Visible = false
	end
	if UI.Tile then
		UI.Tile.Visible = enabled
	end
	bindBack(false)
	if hadSelection then
		pcall(function()
			GuiService.SelectedObject = (enabled and usingGamepad()) and UI.TileButton or nil
		end)
	end
	DevController.Relayout()
end

----------------------------------------------------------------------
-- NC_Dev on / off
----------------------------------------------------------------------
local function startPolling()
	pollSerial = pollSerial + 1
	local serial = pollSerial
	task.spawn(function()
		while enabled and serial == pollSerial do
			guard("relayout", DevController.Relayout)
			task.wait(K.POLL)
		end
	end)
end

local function setEnabled(on)
	if on == enabled then
		return
	end
	if on then
		if not guard("build", build) then
			return
		end
		enabled = true
		UI.Gui.Enabled = true
		UI.Tile.Visible = not panelOpen
		applied = {}
		startPolling()
	else
		DevController.Close()
		enabled = false
		pollSerial = pollSerial + 1
		if UI.Gui then
			UI.Gui.Enabled = false
		end
	end
end

local function refreshFlag()
	setEnabled(Hint.Gui ~= nil and Hint.Gui:GetAttribute(K.ATTR) == true)
end

-- Follows DevService's hints on our PlayerGui (never on the Player: that one every client can read).
local function watchHints()
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 60)
	if not pg then
		return
	end
	Hint.Gui = pg
	pg:GetAttributeChangedSignal(K.ATTR):Connect(function()
		guard("NC_Dev", refreshFlag)
	end)
	pg:GetAttributeChangedSignal(K.ATTR_TUTORIAL):Connect(function()
		guard("NC_DevTutorial", refreshTutorialButton)
	end)
	pg:GetAttributeChangedSignal(K.ATTR_SPEED):Connect(function()
		guard("NC_DevSpeed", refreshSpeedButton)
	end)
	guard("NC_Dev", refreshFlag)
end

-- Phase 5 (7.2): the owner shortcut /menu reopens the main menu (MainMenuController.Open: client-side only, the
-- character stays and MenuPlay is never sent again). Only while NC_Dev is set; DevService ignores the word.
function DevController.OpenMainMenu()
	local module = script.Parent:FindFirstChild("MainMenuController")
	local ok, menu = pcall(function()
		return module and require(module)
	end)
	if ok and type(menu) == "table" and type(menu.Open) == "function" then
		guard("menu", menu.Open)
		return true
	end
	return false
end

function DevController.OnChat(message)
	if type(message) ~= "string" or #message > 40 or not string.match(string.lower(message), "^%s*/menu%s*$") then
		return false
	end
	if not (Hint.Gui and Hint.Gui:GetAttribute(K.ATTR) == true) then
		return false
	end
	return DevController.OpenMainMenu()
end

local function watchChat()
	LocalPlayer.Chatted:Connect(DevController.OnChat)
	pcall(function()
		local chat = game:GetService("TextChatService")
		chat.SendingMessage:Connect(function(msg)
			DevController.OnChat(msg and msg.Text)
		end)
	end)
end

function DevController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then
		return
	end
	UserInputService.InputBegan:Connect(function(input)
		if panelOpen and input.KeyCode == Enum.KeyCode.Escape then
			DevController.Close()
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			guard("relayout", DevController.Relayout)
		end)
	end
	task.spawn(watchHints)
	pcall(watchChat)
end

return DevController
