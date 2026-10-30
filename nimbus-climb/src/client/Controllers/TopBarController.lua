-- TopBarController (client, HUD cleanup): the top-left pill in Roblox's top bar (the owner's pick "B" on the HUD
-- cleanup pitch) with Shop, Travel and Settings, and the Quick Travel drop-down (pick "A").
--
--   TopBarController.Init()
--   TopBarController.GetRect() -> { X0, X1, Y0, Y1 } | nil   the pill (screen px; nil while hidden)
--   TopBarController.TravelAllowed() -> boolean             the Travel button shows (lobby only)
--   TopBarController.Refresh()                              relayout now (tests; a changed top-bar inset)
--
-- Screen: ScreenGui "NimbusTopBar" (display order 21, IgnoreGuiInset = true, so its px are screen px).
--   * Frame "Pill": one rounded navy pill inside Roblox's top-bar band (y 0 .. GuiService:GetGuiInset().Y), right of
--     Roblox's own buttons: GuiService.TopbarInset.Min.X + 8 (read under pcall; K.FALLBACK_LEFT 212 while it is not
--     available) and left of TopbarInset.Max.X (else K.RIGHT_RESERVE px off the right edge: the "..." button).
--     TextButtons PillButton_Shop (MenuController.Open("Shop"); in a match the side hint "The shop is closed during a
--     match."; a second tap closes the open shop), PillButton_Travel (lobby only) and PillButton_Settings
--     (MenuController.OpenSettings: MainMenuController's settings panel). Icon + label; icons only on phones (the
--     smaller screen side <= K.SMALL_PHONE) or when the labels do not fit; squeezed to K.MIN_BTN_W when even that
--     does not fit (a tooltip names an icon-only button).
--   * The ScreenGui carries the attributes PillRight / PillBottom (screen px of the pill's right / bottom edge, 0
--     while the gui is disabled): HudController starts a phone battle's TopBand currency row right of PillRight.
--   * Frame "TravelMenu": the Travel drop-down under the button (top at the band's bottom), TextButtons
--     TravelPortals ("Portals": the Gate Court) and TravelLobby ("Lobby": the spawn plaza). A row fires
--     Remotes.QuickTravel("Court" | "Plaza") (the server checks everything: GateService.Travel), closes the menu and
--     shows Frame "TravelFade" (a short black dip: 0.45 at once -> 0.15, back to clear and hidden by 0.6 s).
--   * Travel is lobby only (TravelAllowed, polled every K.POLL s and on the InMatch / InBattle attributes): hidden in
--     a match (InMatch), a battle / dungeon run / the Ring (InBattle), and while the character stands in the bounding
--     box (+ 40 studs Y) of workspace.BattleArena (the Arena island) or of the Storm Altar island's model.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))

local TopBarController = {}

-- screen px (the top bar is not scaled by the screen factor: it is Roblox's own band)
local K = {
	PILL_H = 40, -- the pill's height in the 58 px band ...
	PILL_MIN_H = 32, -- ... never below this (a thumb)
	BTN_W = 44, -- one button's icon area
	LABEL_W = 70, -- a label's width when it cannot be measured
	LABEL_TEXT = 17,
	ICON = 22,
	GAP = 6, -- between the pill's bottom and the drop-down
	PAD = 4, -- inside the pill, around the buttons
	BTN_GAP = 2,
	MIN_BTN_W = 30, -- icon-only buttons are squeezed this far at most
	EDGE_PAD = 8, -- right of TopbarInset.Min.X
	FALLBACK_LEFT = 212, -- the first free x on a PC when TopbarInset is not available
	BAND_INSET = 58, -- the top bar's height when the gui inset reads 0
	RIGHT_RESERVE = 72, -- Roblox's right-side buttons when TopbarInset is not available
	SMALL_PHONE = 500, -- icons only when the smaller screen side is at most this
	FADE = 0.25, -- the fade back to clear (the dip itself takes FADE_IN)
	FADE_IN = 0.12,
	FADE_START = 0.45, -- the dip starts here at once (the teleport is instant: the cue must be too) ...
	FADE_DARK = 0.15, -- ... and darkens to this
	FADE_DONE = 0.6, -- seconds after the tap the fade is gone
	POLL = 0.5,
	MENU_W = 180,
	ROW_H = 44,
	MENU_PAD = 8,
	ISLAND_Y_SLACK = 40, -- like ArenaController.inArena
	BOX_TTL = 10, -- seconds an island's bounding box is reused (streaming may change it)
	ALTAR_SEARCH = 5, -- seconds between two deep searches for the altar model
	TRAVEL_GAP = 0.4, -- seconds between two QuickTravel sends (the server's cooldown is 2 s)
}
TopBarController.K = K

local BUTTONS = {
	{ Id = "Shop", Label = "Shop", Icon = "Shop" },
	{ Id = "Travel", Label = "Travel", Icon = "Travel" },
	{ Id = "Settings", Label = "Settings", Icon = "Settings" },
}

local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.PanelBottom or Color3.fromRGB(12, 15, 38)

local LocalPlayer = nil
local initialized = false
local gui = nil
local U = { Buttons = {}, Pill = nil, Menu = nil, Fade = nil }
local S = {
	TravelShown = true,
	MenuOpen = false,
	FadeSerial = 0,
	LastSend = 0,
	Boxes = setmetatable({}, { __mode = "k" }), -- island model -> { CFrame, Size, At }
	Altar = nil,
	AltarSearch = -math.huge,
	Layout = nil, -- { X, Y, W, H, Travel = { X, W } }
}
local warned = {}

local function warnOnce(key, err)
	if not warned[key] then
		warned[key] = true
		warn("[TopBarController] " .. key .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

local function menu()
	local inst = script.Parent:FindFirstChild("MenuController")
	local ok, mod = pcall(function()
		return inst and require(inst)
	end)
	return ok and type(mod) == "table" and mod or nil
end

----------------------------------------------------------------------
-- Geometry (screen px)
----------------------------------------------------------------------
local function viewport()
	local cam = workspace.CurrentCamera
	local size = cam and cam.ViewportSize
	if size and size.X >= 2 and size.Y >= 2 then
		return size
	end
	return Vector2.new(1920, 1080)
end

local function topbarInset()
	local ok, rect = pcall(function()
		return GuiService.TopbarInset
	end)
	if ok and typeof(rect) == "Rect" and rect.Min.X > 0 and rect.Max.X > rect.Min.X then
		return rect
	end
	return nil
end

local function leftEdge()
	local rect = topbarInset()
	if rect then
		return rect.Min.X + K.EDGE_PAD
	end
	return K.FALLBACK_LEFT
end

local function rightLimit(vp)
	local rect = topbarInset()
	if rect then
		return rect.Max.X
	end
	return vp.X - K.RIGHT_RESERVE
end

local function inset()
	local y = 0
	pcall(function()
		y = GuiService:GetGuiInset().Y
	end)
	if not y or y <= 0 then
		return K.BAND_INSET
	end
	return y
end

local function labelWidth(text)
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, K.LABEL_TEXT, Theme.Fonts.Button, Vector2.new(1000, 100))
	end)
	if ok and typeof(bounds) == "Vector2" and bounds.X > 0 then
		return math.ceil(bounds.X) + 10
	end
	return K.LABEL_W
end

----------------------------------------------------------------------
-- Travel: lobby only
----------------------------------------------------------------------
local function rootPosition()
	local char = LocalPlayer and LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function altarModel()
	if S.Altar and S.Altar.Parent then
		return S.Altar
	end
	S.Altar = nil
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local altar = lobby and lobby:FindFirstChild("StormAltar")
	if not altar and os.clock() - S.AltarSearch >= K.ALTAR_SEARCH then
		S.AltarSearch = os.clock()
		altar = workspace:FindFirstChild("StormAltar", true)
	end
	if altar and altar:IsA("Model") then
		S.Altar = altar
	end
	return S.Altar
end

local function insideIsland(model, pos)
	if not (model and model:IsA("Model") and model.Parent) then
		return false
	end
	local box = S.Boxes[model]
	if not box or os.clock() - box.At > K.BOX_TTL then
		local ok, cf, size = pcall(function()
			return model:GetBoundingBox()
		end)
		if not ok or typeof(cf) ~= "CFrame" then
			return false
		end
		box = { CFrame = cf, Size = size, At = os.clock() }
		S.Boxes[model] = box
	end
	local rel = box.CFrame:PointToObjectSpace(pos)
	local half = box.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and math.abs(rel.Y) <= half.Y + K.ISLAND_Y_SLACK
end

function TopBarController.TravelAllowed()
	if not LocalPlayer then
		return false
	end
	if LocalPlayer:GetAttribute(Config.Attr.InMatch) == true then
		return false
	end
	if LocalPlayer:GetAttribute(Config.Attr.InBattle or "InBattle") ~= nil then
		return false
	end
	local pos = rootPosition()
	if pos then
		if insideIsland(workspace:FindFirstChild("BattleArena"), pos) or insideIsland(altarModel(), pos) then
			return false
		end
	end
	return true
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
local function setMenuOpen(on)
	S.MenuOpen = on == true
	if U.Menu then
		U.Menu.Visible = S.MenuOpen
	end
	local travel = U.Buttons.Travel
	if travel then
		travel.Root.BackgroundTransparency = S.MenuOpen and 0.72 or 1
	end
end

local function placeMenu()
	local lay = S.Layout
	if not (U.Menu and lay and lay.Travel) then
		return
	end
	local vp = viewport()
	local h = 2 * K.ROW_H + 3 * K.MENU_PAD
	local x = math.max(lay.X, math.min(lay.X + lay.Travel.X, vp.X - K.MENU_W - K.MENU_PAD))
	U.Menu.Size = UDim2.fromOffset(K.MENU_W, h)
	U.Menu.Position = UDim2.fromOffset(x, math.max(lay.Y + lay.H + K.GAP, inset()))
end

local function writeAttributes()
	if not gui then
		return
	end
	local lay = S.Layout
	local on = gui.Enabled and lay ~= nil
	local right = on and (lay.X + lay.W) or 0
	local bottom = on and (lay.Y + lay.H) or 0
	if gui:GetAttribute("PillRight") ~= right then
		gui:SetAttribute("PillRight", right)
	end
	if gui:GetAttribute("PillBottom") ~= bottom then
		gui:SetAttribute("PillBottom", bottom)
	end
end

local function relayout()
	if not (gui and U.Pill) then
		return
	end
	local vp = viewport()
	local band = inset()
	local h = math.floor(Util.Clamp(band - 10, K.PILL_MIN_H, K.PILL_H))
	local y = math.max(0, math.floor((band - h) / 2))
	local left = leftEdge()
	local right = rightLimit(vp)
	local shown = {}
	for _, spec in ipairs(BUTTONS) do
		if spec.Id ~= "Travel" or S.TravelShown then
			shown[#shown + 1] = spec
		end
	end
	local n = #shown
	local function total(widths)
		local sum = 2 * K.PAD + (n - 1) * K.BTN_GAP
		for _, w in ipairs(widths) do
			sum = sum + w
		end
		return sum
	end
	local labels = math.min(vp.X, vp.Y) > K.SMALL_PHONE
	local widths = {}
	if labels then
		for i, spec in ipairs(shown) do
			widths[i] = K.BTN_W + labelWidth(spec.Label) - 8
		end
		if left + total(widths) > right then
			labels = false
		end
	end
	if not labels then
		local w = K.BTN_W
		if left + 2 * K.PAD + n * w + (n - 1) * K.BTN_GAP > right then
			w = math.max(K.MIN_BTN_W, math.floor((right - left - 2 * K.PAD - (n - 1) * K.BTN_GAP) / n))
		end
		for i = 1, n do
			widths[i] = w
		end
	end
	local x = K.PAD
	local travelAt = nil
	for _, spec in ipairs(BUTTONS) do
		local b = U.Buttons[spec.Id]
		if b then
			b.Root.Visible = spec.Id ~= "Travel" or S.TravelShown
		end
	end
	for i, spec in ipairs(shown) do
		local b = U.Buttons[spec.Id]
		local w = widths[i]
		b.Root.Position = UDim2.fromOffset(x, 2)
		b.Root.Size = UDim2.fromOffset(w, h - 4)
		b.Label.Visible = labels
		if labels then
			b.Icon.Position = UDim2.fromOffset(K.BTN_W / 2, (h - 4) / 2)
			b.Label.Position = UDim2.fromOffset(K.BTN_W - 6, 0)
			b.Label.Size = UDim2.new(1, -(K.BTN_W - 6), 1, 0)
		else
			b.Icon.Position = UDim2.fromOffset(w / 2, (h - 4) / 2)
		end
		if spec.Id == "Travel" then
			travelAt = { X = x, W = w }
		end
		x = x + w + K.BTN_GAP
	end
	local width = total(widths)
	U.Pill.Position = UDim2.fromOffset(left, y)
	U.Pill.Size = UDim2.fromOffset(width, h)
	S.Layout = { X = left, Y = y, W = width, H = h, Labels = labels, Travel = travelAt }
	placeMenu()
	writeAttributes()
end

-- the Travel button follows TravelAllowed (its drop-down closes when it hides)
local function applyTravel()
	local allowed = TopBarController.TravelAllowed()
	if allowed ~= S.TravelShown then
		S.TravelShown = allowed
		if not allowed then
			setMenuOpen(false)
		end
		relayout()
	end
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------
local function shopShown()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local menuGui = pg and pg:FindFirstChild("NimbusMenu")
	local win = menuGui and menuGui:FindFirstChild("Window_Shop")
	return win ~= nil and win:IsA("GuiObject") and win.Visible
end

local function onShop()
	setMenuOpen(false)
	local mc = menu()
	if not mc then
		return
	end
	if LocalPlayer:GetAttribute(Config.Attr.InMatch) == true then
		if type(mc.Hint) == "function" then
			mc.Hint("The shop is closed during a match.", "info")
		end
		return
	end
	if shopShown() and type(mc.Close) == "function" then
		mc.Close()
		return
	end
	mc.Open("Shop")
end

local function onSettings()
	setMenuOpen(false)
	local mc = menu()
	if mc and type(mc.OpenSettings) == "function" then
		mc.OpenSettings()
	end
end

local function onTravel()
	if not S.TravelShown then
		return
	end
	setMenuOpen(not S.MenuOpen)
	placeMenu()
end

local function showFade()
	local fade = U.Fade
	if not fade then
		return
	end
	S.FadeSerial = S.FadeSerial + 1
	local serial = S.FadeSerial
	fade.BackgroundTransparency = K.FADE_START
	fade.Visible = true
	Util.Tween(fade, K.FADE_IN, { BackgroundTransparency = K.FADE_DARK }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(K.FADE_DONE - K.FADE, function()
		if S.FadeSerial == serial and fade.Parent then
			Util.Tween(fade, K.FADE, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
	task.delay(K.FADE_DONE, function()
		if S.FadeSerial == serial and fade.Parent then
			fade.BackgroundTransparency = 1
			fade.Visible = false
		end
	end)
end

local function travelTo(dest)
	setMenuOpen(false)
	if not S.TravelShown or os.clock() - S.LastSend < K.TRAVEL_GAP then
		return
	end
	S.LastSend = os.clock()
	local ok, remote = pcall(Remotes.Get, "QuickTravel")
	if ok and remote then
		remote:FireServer(dest)
		showFade()
	end
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
local function buildButton(parent, spec, order, callback)
	local root = Util.Create("TextButton", {
		Name = "PillButton_" .. spec.Id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 3,
		Parent = parent,
	})
	Util.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = root })
	local icon = NeonKit.Icon(root, spec.Icon, K.ICON)
	icon.ZIndex = 4
	local label = Theme.Label(spec.Label, "Button", {
		Size = K.LABEL_TEXT,
		Stroke = 0.5,
		Props = {
			Name = "Label",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 4,
		},
	})
	label.Parent = root
	local fx = nil
	fx = NeonKit.AttachFx(root, function(hover, press)
		if spec.Id ~= "Travel" or not S.MenuOpen then
			root.BackgroundTransparency = (hover or press) and 0.85 or 1
		end
	end)
	root.Activated:Connect(function()
		safe("pill " .. spec.Id, callback)
	end)
	CloudUI.Tooltip(root, function()
		return (S.Layout and S.Layout.Labels) and nil or spec.Label
	end)
	return { Root = root, Icon = icon, Label = label, Fx = fx }
end

local function buildMenu()
	local card = NeonKit.Card({
		Name = "TravelMenu",
		Size = UDim2.fromOffset(K.MENU_W, 2 * K.ROW_H + 3 * K.MENU_PAD),
		Color = "Blue",
		Glow = false,
		Floor = false,
		ZIndex = 5,
		Parent = gui,
	})
	U.Menu = card.Root
	U.Menu.Visible = false
	local rows = {
		{ Name = "TravelPortals", Text = "Portals", Dest = "Court", Color = "Blue" },
		{ Name = "TravelLobby", Text = "Lobby", Dest = "Plaza", Color = "Green" },
	}
	for i, row in ipairs(rows) do
		NeonKit.Button({
			Name = row.Name,
			Text = row.Text,
			TextSize = 20,
			Color = row.Color,
			Size = UDim2.fromOffset(K.MENU_W - 2 * K.MENU_PAD, K.ROW_H),
			Position = UDim2.fromOffset(K.MENU_PAD, K.MENU_PAD + (i - 1) * (K.ROW_H + K.MENU_PAD)),
			ZIndex = 6,
			Parent = card.Body,
			Callback = function()
				safe("travel " .. row.Dest, travelTo, row.Dest)
			end,
		})
	end
end

local function build()
	local pill = Util.Create("Frame", {
		Name = "Pill",
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = gui,
	})
	Util.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = pill })
	Util.Create("UIStroke", {
		Color = Theme.Lighten(Colors.PanelTop or NAVY, 0.35),
		Thickness = 1.5,
		Transparency = 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = pill,
	})
	U.Pill = pill
	local actions = { Shop = onShop, Travel = onTravel, Settings = onSettings }
	for i, spec in ipairs(BUTTONS) do
		U.Buttons[spec.Id] = buildButton(pill, spec, i, actions[spec.Id])
	end
	buildMenu()
	U.Fade = Util.Create("Frame", {
		Name = "TravelFade",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Active = false,
		ZIndex = 20,
		Parent = gui,
	})
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function TopBarController.GetRect()
	if not (gui and gui.Enabled and U.Pill and U.Pill.Visible) then
		return nil
	end
	local p, s = U.Pill.AbsolutePosition, U.Pill.AbsoluteSize
	return { X0 = p.X, X1 = p.X + s.X, Y0 = p.Y, Y1 = p.Y + s.Y }
end

function TopBarController.Refresh()
	if not initialized then
		return
	end
	S.TravelShown = TopBarController.TravelAllowed()
	if not S.TravelShown then
		setMenuOpen(false)
	end
	relayout()
end

function TopBarController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	gui = CloudUI.NewScreenGui("NimbusTopBar", 21)
	gui.IgnoreGuiInset = true
	build()
	S.TravelShown = TopBarController.TravelAllowed()
	relayout()

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		safe("relayout", relayout)
	end)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		safe("enabled", writeAttributes)
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
			safe("inset", relayout)
		end)
	end)
	for _, attr in ipairs({ Config.Attr.InMatch, Config.Attr.InBattle or "InBattle" }) do
		LocalPlayer:GetAttributeChangedSignal(attr):Connect(function()
			safe("travel", applyTravel)
		end)
	end
	-- a click into the world closes the drop-down
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not S.MenuOpen then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			setMenuOpen(false)
		end
	end)
	task.spawn(function()
		while gui and gui.Parent do
			safe("poll", applyTravel)
			task.wait(K.POLL)
		end
	end)
end

return TopBarController
