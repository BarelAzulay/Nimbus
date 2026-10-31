-- TopBarController (client, HUD cleanup): the top-left pill in Roblox's top bar (the owner's pick "B" on the HUD
-- cleanup pitch) with Shop, Travel and Settings.
--
--   TopBarController.Init()
--   TopBarController.GetRect() -> { X0, X1, Y0, Y1 } | nil   the pill (screen px; nil while hidden)
--   TopBarController.TravelAllowed() -> boolean             the Travel button shows (not in a match or a battle)
--   TopBarController.Refresh()                              relayout now (tests; a changed top-bar inset)
--
-- Screen: ScreenGui "NimbusTopBar" (display order 21, IgnoreGuiInset = true, so its px are screen px).
--   * Frame "Pill": one rounded navy pill inside Roblox's top-bar band (y 0 .. GuiService:GetGuiInset().Y), right of
--     Roblox's own buttons: GuiService.TopbarInset.Min.X + 8 (read under pcall; K.FALLBACK_LEFT 212 while it is not
--     available) and left of TopbarInset.Max.X (else K.RIGHT_RESERVE px off the right edge: the "..." button).
--     TextButtons PillButton_Shop (MenuController.Open("Shop"); in a match the side hint "The shop is closed during a
--     match."; a second tap closes the open shop), PillButton_Travel and PillButton_Settings
--     (MenuController.OpenSettings: MainMenuController's settings panel). Icon + label; icons only on phones (the
--     smaller screen side <= K.SMALL_PHONE) or when the labels do not fit; squeezed to K.MIN_BTN_W when even that
--     does not fit (a tooltip names an icon-only button).
--   * The ScreenGui carries the attributes PillRight / PillBottom (screen px of the pill's right / bottom edge, 0
--     while the gui is disabled): HudController starts a phone battle's TopBand currency row right of PillRight.
--   * A tap on Travel fires Remotes.QuickTravel("Plaza"): the server opens the same portal as Go home, leading to the lobby
--     spawn (GateService.Travel; every refusal, its toast and the cooldown are the server's). No menu: one destination.
--   * Travel shows everywhere Go home works, also at home and on the Arena and Altar islands (getting back to the lobby
--     from there is the point): hidden only in a match (InMatch) and in a battle / dungeon run / the Ring (InBattle),
--     followed through those attributes.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	PAD = 4, -- inside the pill, around the buttons
	BTN_GAP = 2,
	MIN_BTN_W = 30, -- icon-only buttons are squeezed this far at most
	EDGE_PAD = 8, -- right of TopbarInset.Min.X
	FALLBACK_LEFT = 212, -- the first free x on a PC when TopbarInset is not available
	BAND_INSET = 58, -- the top bar's height when the gui inset reads 0
	RIGHT_RESERVE = 72, -- Roblox's right-side buttons when TopbarInset is not available
	SMALL_PHONE = 500, -- icons only when the smaller screen side is at most this
	TRAVEL_GAP = 0.4, -- seconds between two QuickTravel sends (the portal's cooldown is 3 s)
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
local U = { Buttons = {}, Pill = nil }
local S = {
	TravelShown = true,
	LastSend = 0,
	Layout = nil, -- { X, Y, W, H, Labels }
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
-- Travel: everywhere but a match or a battle
----------------------------------------------------------------------
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
	return true
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
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
		x = x + w + K.BTN_GAP
	end
	local width = total(widths)
	U.Pill.Position = UDim2.fromOffset(left, y)
	U.Pill.Size = UDim2.fromOffset(width, h)
	S.Layout = { X = left, Y = y, W = width, H = h, Labels = labels }
	writeAttributes()
end

-- the Travel button follows TravelAllowed
local function applyTravel()
	local allowed = TopBarController.TravelAllowed()
	if allowed ~= S.TravelShown then
		S.TravelShown = allowed
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
	local mc = menu()
	if mc and type(mc.OpenSettings) == "function" then
		mc.OpenSettings()
	end
end

-- one destination: the tap asks the server for the portal
local function onTravel()
	if not S.TravelShown or os.clock() - S.LastSend < K.TRAVEL_GAP then
		return
	end
	S.LastSend = os.clock()
	local ok, remote = pcall(Remotes.Get, "QuickTravel")
	if ok and remote then
		remote:FireServer("Plaza")
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
		root.BackgroundTransparency = (hover or press) and 0.85 or 1
	end)
	root.Activated:Connect(function()
		safe("pill " .. spec.Id, callback)
	end)
	CloudUI.Tooltip(root, function()
		return (S.Layout and S.Layout.Labels) and nil or spec.Label
	end)
	return { Root = root, Icon = icon, Label = label, Fx = fx }
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
end

return TopBarController
