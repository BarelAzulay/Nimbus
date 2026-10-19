-- CloudUI: the game's UI kit. v5 (Phase 5, ARCHITECTURE_V3.md "Phase 5 build contract" 6.6): every widget is re-skinned
-- on the Neon kit (client/UI/NeonKit.lua, image 21.png): dark navy faces, a glowing neon border in the widget's own
-- colour, GothamBlack labels with a dark stroke. Panel = a Neon card (accent = props.Accent, props.Category or Blue)
-- with a GothamBlack 34 title, a neon underline and a red X; the cloud bumps, the sky-blue frame and the pixel glint
-- of v3 are gone ("less cute"). The API, the names and the attributes below are UNCHANGED.
-- (v3 text kept for the API:) the chunky "cloud" UI kit. Front-page-simulator style panels made cloudier: a thick dark
-- navy outline, glossy sky-blue frames with a bevelled rim, puffy cloud bumps along the top edge, a bold
-- title bar with big outlined title text and a red X, glossy buttons with a darker bottom lip, and a tiny
-- pixel glint (a nod to the voxel world). Everything is built from Frames / TextLabels / UICorner /
-- UIStroke / UIGradient / UIPadding / list+grid layouts. No images, no asset ids.
--
--   CloudUI.NewScreenGui(name, displayOrder) -> ScreenGui
--   CloudUI.Panel(props)      -> { Root, Body, Content, TitleBar, TitleLabel, CloseButton, Close, SetTitle, SetAccent, Destroy }
--   CloudUI.Button(props)     -> TextButton
--   CloudUI.IconButton(props) -> { Root, Button, Glyph, Caption, SetBadge, SetGlyph, SetLabel, SetColor }
--   CloudUI.Bar(props)        -> { Root, Fill, Label, SetFraction, SetText, SetColor, GetFraction }
--   CloudUI.Slot(props)       -> { Root, Button, SetContent, SetSelected, SetCount, SetHotkey, ... }
--   CloudUI.Tabs(props)       -> { Root, Content, Add, Select, GetSelected, GetPage, GetButton }
--   CloudUI.Grid(parent, cellSize, padding) -> ScrollingFrame (UIGridLayout, automatic canvas)
--   CloudUI.PetViewport(parent, petDef, size, opts) -> { Frame, Destroy, SetAnimated, SetExcited }   (opts.Evolved: Phase 4)
--   CloudUI.Pill(text, kind, parent) -> TextLabel
--   CloudUI.Tooltip(guiObject, textFn) -> disconnect function
--   CloudUI.RarityColor(rarityId) -> Color3
--   v3 readability helpers:
--   CloudUI.ScreenFactor()            -> Theme.ScreenFactor() (clamp(viewportY / 1080, 0.8, 1.25))
--   CloudUI.TextSize(basePx)          -> Theme.ScaledSize(basePx) for text that is not under a UIScale
--   CloudUI.AutoScale(guiObject, opts) -> UIScale kept at the screen factor (one shared camera listener)
--   CloudUI.Metrics / CloudUI.ContentInset(hasTitle, clouds) -> the panel geometry
--
-- Conventions
--   * Sizes are DESIGN pixels of a 1920x1080 screen and follow the v3 readability rule there (body text
--     >= 18, captions >= 15, buttons >= 20, titles 28-44). Put a widget tree under one UIScale of the screen
--     factor (CloudUI.AutoScale, or a window's own fit scale) and it reads well from phones to 1440p.
--   * Every constructor accepts Name / Parent / Position / AnchorPoint / Size in its props and names
--     its instances for debugging. Text uses Theme font roles only, with a stroke on every text.
--   * Buttons are plain TextButtons. Their state lives in attributes, so you can change it later:
--       button:SetAttribute("Disabled", true)   (or button.Active = false)   -> greyed out, callback ignored
--       button:SetAttribute("Style", "Gold")                                 -> re-skin
--     (CloudUI.SetDisabled / CloudUI.SetStyle do exactly that.) Setting button.Text just works.
--   * Hover / press feedback is a UIScale named "FxScale" (1.04 / 0.95). UIScale grows around the
--     AnchorPoint, so centre-anchored buttons look best.
--   * Panel.Content never gets decorative children, so callers may put a UIListLayout / UIGridLayout in it.
--   * ONE RenderStepped connection (CloudUI.Update) drives every pet viewport and the tooltip; it
--     disconnects itself when nothing needs it. Viewports of hidden or destroyed UI stop costing time.
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local NeonKit = require(script.Parent:WaitForChild("NeonKit"))

local CloudUI = {}

----------------------------------------------------------------------
-- Palette + tuning
----------------------------------------------------------------------
local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Colors.Gold or Colors.Token

local BUTTON_COLORS = Theme.Buttons or {}
local KIND_COLORS = Theme.Kinds or {}
-- v5 Neon kit colours
local NEON = Theme.Neon
local INK = Colors.PanelInk or Color3.fromRGB(8, 10, 28)
local PANEL_TOP = Colors.PanelTop or Color3.fromRGB(26, 32, 72)
local PANEL_BOTTOM = Colors.PanelBottom or Color3.fromRGB(12, 15, 38)
-- the neon colour of a button style name
local STYLE_NEON = { Green = "Green", Pink = "Pink", Red = "Red", Blue = "Blue", Gold = "Gold", Gray = "Grey" }

local HOVER_SCALE = 1.04
local PRESS_SCALE = 0.95
local FOV = 32 -- pet viewport camera
local TOOLTIP_DELAY = 0.35
local LONG_PRESS = 0.45

-- Panel geometry (design px)
local OUTLINE_THICKNESS = 3 -- v5: the neon border of every window
local PANEL_CORNER = 16
local PANEL_PAD = 12 -- frame border around the title bar and the content well
local TITLE_TOP = 10
local TITLE_H = 50
local TITLE_GAP = 10
local TITLE_TEXT = 34
local CLOSE_SIZE = 40
local UNTITLED_TOP_CLOUDS = 20 -- v5: no cloud bumps any more; an untitled panel keeps this room for its corner X

CloudUI.Metrics = {
	Outline = OUTLINE_THICKNESS,
	Corner = PANEL_CORNER,
	Pad = PANEL_PAD,
	TitleTop = TITLE_TOP,
	TitleHeight = TITLE_H,
	TitleGap = TITLE_GAP,
	TitleText = TITLE_TEXT,
	CloseSize = CLOSE_SIZE,
	ContentPad = 10, -- suggested padding for things laid out inside Panel.Content
	ButtonText = 22,
	ButtonHeight = 50,
	BodyText = 19,
	CaptionText = 16,
}

CloudUI.Palette = {
	Navy = NAVY,
	Gold = GOLD,
	Muted = MUTED,
	FrameTop = Colors.FrameTop,
	FrameBottom = Colors.FrameBottom,
	WellTop = Colors.WellTop,
	WellBottom = Colors.WellBottom,
	Mist = Colors.Mist,
	Buttons = BUTTON_COLORS,
}

-- Multiplier gradient for faces that carry TEXT. A UIGradient also tints the text of its TextLabel /
-- TextButton, so the gradient stays near white where the text sits and only darkens the "lip" band at
-- the bottom (hard step), which gives the glossy chunky 3-D look without recolouring the text.
local FACE_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(240, 242, 248)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 156, 184)),
})

----------------------------------------------------------------------
-- Small builders
----------------------------------------------------------------------
local function toUDim(value, default)
	if typeof(value) == "UDim" then
		return value
	end
	if type(value) == "number" then
		return UDim.new(0, value)
	end
	return default or UDim.new(0, 12)
end

local function toUDim2(value, default)
	if typeof(value) == "UDim2" then
		return value
	end
	if typeof(value) == "Vector2" then
		return UDim2.fromOffset(value.X, value.Y)
	end
	if type(value) == "number" then
		return UDim2.fromOffset(value, value)
	end
	return default
end

local function corner(parent, radius)
	return Util.Create("UICorner", { CornerRadius = toUDim(radius), Parent = parent })
end

local function round(parent)
	return Util.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return Util.Create("UIStroke", {
		Color = color or NAVY,
		Thickness = thickness or 3,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function padding(parent, left, top, right, bottom)
	return Util.Create("UIPadding", {
		PaddingLeft = toUDim(left or 0),
		PaddingTop = toUDim(top or 0),
		PaddingRight = toUDim(right or 0),
		PaddingBottom = toUDim(bottom or 0),
		Parent = parent,
	})
end

local function gradient(parent, sequence, rotation)
	return Util.Create("UIGradient", { Color = sequence, Rotation = rotation or 90, Parent = parent })
end

local function frame(name, props, parent)
	local p = props or {}
	p.Name = name
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	p.Parent = parent
	return Util.Create("Frame", p)
end

-- Soft translucent highlight strip near the top of a glossy face.
local function addShine(parent, heightScale, sideInset, transparency, zIndex)
	local shine = Util.Create("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = transparency or 0.82,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -2 * (sideInset or 10), heightScale or 0.32, 0),
		Active = false,
		ZIndex = zIndex or 1,
		Parent = parent,
	})
	round(shine)
	return shine
end

local function titleCase(text)
	text = tostring(text or "")
	return text:sub(1, 1):upper() .. text:sub(2):lower()
end

local function styleBase(style)
	return BUTTON_COLORS[titleCase(style)] or BUTTON_COLORS.Green or Color3.fromRGB(96, 196, 108)
end

local function isStyleName(style)
	return BUTTON_COLORS[titleCase(style)] ~= nil
end

local function isShown(gui)
	local node = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled ~= false
		end
		node = node.Parent
	end
	return false
end

----------------------------------------------------------------------
-- Readability helpers (v3)
----------------------------------------------------------------------
function CloudUI.ScreenFactor()
	return Theme.ScreenFactor()
end

-- Pixel size for text that is NOT under a UIScale (never below 14 px).
function CloudUI.TextSize(basePx, minPx)
	return Theme.ScaledSize(basePx, minPx)
end

-- Top / side / bottom insets of Panel.Content inside the panel (design px).
function CloudUI.ContentInset(hasTitle, clouds)
	local top = PANEL_PAD
	if hasTitle then
		top = TITLE_TOP + TITLE_H + TITLE_GAP
	elseif clouds ~= false then
		top = UNTITLED_TOP_CLOUDS -- v5: room for the corner X of an untitled panel
	end
	return top, PANEL_PAD, PANEL_PAD
end

local autoScales = {} -- { Scale = UIScale, Mult, Min, Max }
local autoCameraConn = nil
local autoWatchConn = nil

local function autoValue(entry)
	local value = Theme.ScreenFactor() * entry.Mult
	if entry.Min then
		value = math.max(entry.Min, value)
	end
	if entry.Max then
		value = math.min(entry.Max, value)
	end
	return value
end

local function refreshAutoScales()
	for i = #autoScales, 1, -1 do
		local entry = autoScales[i]
		if entry.Scale.Parent == nil then
			table.remove(autoScales, i)
		else
			entry.Scale.Scale = autoValue(entry)
		end
	end
end

local function bindAutoCamera()
	if autoCameraConn then
		autoCameraConn:Disconnect()
		autoCameraConn = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		autoCameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshAutoScales)
	end
	refreshAutoScales()
end

-- Adds (or reuses) a UIScale that keeps `guiObject` (designed in 1080p pixels) at the readability factor.
-- opts: Name (default "ReadScale"), Multiplier (default 1), Min, Max (clamp the final scale)
function CloudUI.AutoScale(guiObject, opts)
	if not guiObject then
		return nil
	end
	opts = opts or {}
	local name = opts.Name or "ReadScale"
	local scale = guiObject:FindFirstChild(name)
	if not (scale and scale:IsA("UIScale")) then
		scale = Util.Create("UIScale", { Name = name, Scale = 1, Parent = guiObject })
	end
	local entry = { Scale = scale, Mult = tonumber(opts.Multiplier) or 1, Min = opts.Min, Max = opts.Max }
	scale.Scale = autoValue(entry)
	table.insert(autoScales, entry)
	if not autoWatchConn then
		autoWatchConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindAutoCamera)
		bindAutoCamera()
	end
	return scale
end

----------------------------------------------------------------------
-- Shared update loop (ONE RenderStepped connection for viewports + tooltip)
----------------------------------------------------------------------
local tickers = {}
local loopConnection = nil
local clockTime = 0

function CloudUI.Update(dt)
	clockTime = clockTime + dt
	for i = #tickers, 1, -1 do
		local ticker = tickers[i]
		if ticker.dead then
			table.remove(tickers, i)
		else
			local ok, err = pcall(ticker.fn, dt, clockTime)
			if not ok then
				ticker.dead = true
				warn("[CloudUI] update error: " .. tostring(err))
			end
		end
	end
	if #tickers == 0 and loopConnection then
		loopConnection:Disconnect()
		loopConnection = nil
	end
end

local function addTicker(fn)
	local ticker = { fn = fn, dead = false }
	table.insert(tickers, ticker)
	if not loopConnection then
		loopConnection = RunService.RenderStepped:Connect(CloudUI.Update)
	end
	return ticker
end

----------------------------------------------------------------------
-- Hover / press feedback
----------------------------------------------------------------------
-- Adds a UIScale to `button` and tweens it on hover and press. opts.OnState(hovering, pressing) is
-- called on every change so the caller can repaint colours.
local function attachFx(button, opts)
	opts = opts or {}
	local hoverScale = opts.Hover or HOVER_SCALE
	local pressScale = opts.Press or PRESS_SCALE
	local scale = Util.Create("UIScale", { Name = "FxScale", Scale = 1, Parent = button })
	local fx = { Hovering = false, Pressing = false }
	local running = nil

	local function refresh(seconds)
		local target = 1
		if fx.Pressing then
			target = pressScale
		elseif fx.Hovering then
			target = hoverScale
		end
		if running then
			running:Cancel()
		end
		running = Util.Tween(scale, seconds, { Scale = target }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if opts.OnState then
			opts.OnState(fx.Hovering, fx.Pressing)
		end
	end

	button.MouseEnter:Connect(function()
		fx.Hovering = true
		refresh(0.12)
	end)
	button.MouseLeave:Connect(function()
		fx.Hovering = false
		fx.Pressing = false
		refresh(0.14)
	end)
	button.MouseButton1Down:Connect(function()
		fx.Pressing = true
		refresh(0.07)
	end)
	button.MouseButton1Up:Connect(function()
		fx.Pressing = false
		refresh(0.12)
	end)
	-- a finger that lifts never produces MouseLeave
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			fx.Hovering = false
			fx.Pressing = false
			refresh(0.12)
		end
	end)
	fx.Scale = scale
	return fx
end

----------------------------------------------------------------------
-- Screen gui
----------------------------------------------------------------------
function CloudUI.NewScreenGui(name, displayOrder)
	local player = Players.LocalPlayer
	local playerGui = player and player:WaitForChild("PlayerGui")
	local old = playerGui and playerGui:FindFirstChild(name)
	if old and old:IsA("ScreenGui") then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 1
	gui.Parent = playerGui
	return gui
end

----------------------------------------------------------------------
-- Rarity
----------------------------------------------------------------------
function CloudUI.RarityColor(rarityId)
	local wanted = tostring(rarityId or ""):lower()
	for _, rarity in ipairs(Config.Rarities) do
		if rarity.Id:lower() == wanted then
			return rarity.Color
		end
	end
	return Config.Rarities[1].Color
end

----------------------------------------------------------------------
-- Button
----------------------------------------------------------------------
-- props: Text, Style ("Green"|"Pink"|"Red"|"Blue"|"Gold"|"Gray"), Size (default 160x50), Position,
--        AnchorPoint, Callback (called as Callback(button)), Parent, TextSize (default 22), Name,
--        LayoutOrder, ZIndex
function CloudUI.Button(props)
	props = props or {}
	local state = { Style = isStyleName(props.Style) and titleCase(props.Style) or "Green" }

	local button = Util.Create("TextButton", {
		Name = props.Name or ("Button_" .. tostring(props.Text or "")),
		AutoButtonColor = false,
		Active = true, -- explicit: "Active == false" is how a button is switched off (see isDisabled)
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Darken(styleBase(state.Style), 0.4),
		Size = props.Size or UDim2.fromOffset(160, 50),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Text = props.Text or "",
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Theme.Style(button, "Button", { Size = props.TextSize or CloudUI.Metrics.ButtonText, Stroke = 1 })
	corner(button, 12)
	-- v5: the neon border in the style's own colour (Border mode) + a soft outer glow ring; dark text outline
	local outline = stroke(button, NAVY, 3, 0)
	local textOutline = Theme.TextOutline(button, 2, INK, 0) -- Contextual: the text
	gradient(button, FACE_SEQUENCE, 90)
	-- (no UIPadding: it would shift the glow ring; the text is centred and truncates at the edges)
	local glow = frame("Glow", {
		Position = UDim2.fromOffset(-4, -4),
		Size = UDim2.new(1, 8, 1, 8),
		ZIndex = button.ZIndex,
	}, button)
	corner(glow, 16)
	local glowStroke = stroke(glow, NAVY, 4, 0.68)
	addShine(button, 0.06, 12, 0.8, button.ZIndex)

	local fx
	local function isDisabled()
		return button:GetAttribute("Disabled") == true or button.Active == false
	end

	local function paint(seconds)
		local disabled = isDisabled()
		local neon = disabled and NEON.Grey or Theme.NeonColor(STYLE_NEON[state.Style] or "Green")
		local face = Theme.Darken(neon, disabled and 0.7 or 0.4)
		if not disabled and fx then
			if fx.Pressing then
				face = Theme.Darken(face, 0.15)
			elseif fx.Hovering then
				face = Theme.Lighten(face, 0.08)
			end
		end
		if seconds and seconds > 0 then
			Util.Tween(button, seconds, { BackgroundColor3 = face })
		else
			button.BackgroundColor3 = face
		end
		button.TextColor3 = disabled and Color3.fromRGB(176, 184, 206) or WHITE
		button.TextStrokeColor3 = INK
		if textOutline then
			textOutline.Color = INK
			textOutline.Transparency = disabled and 0.35 or 0
		end
		outline.Color = disabled and Theme.Darken(neon, 0.2) or neon
		glowStroke.Color = neon
		glow.Visible = not disabled
	end

	fx = attachFx(button, {
		OnState = function()
			paint(0.08)
		end,
	})
	paint(0)

	button:GetAttributeChangedSignal("Disabled"):Connect(function()
		paint(0.15)
	end)
	button:GetPropertyChangedSignal("Active"):Connect(function()
		paint(0.15)
	end)
	button:GetAttributeChangedSignal("Style"):Connect(function()
		local style = button:GetAttribute("Style")
		if type(style) == "string" and isStyleName(style) then
			state.Style = titleCase(style)
			paint(0.15)
		end
	end)

	if props.Callback then
		button.Activated:Connect(function()
			if isDisabled() then
				return
			end
			props.Callback(button)
		end)
	end

	button.Parent = props.Parent
	return button
end

function CloudUI.SetDisabled(button, disabled)
	if button then
		button:SetAttribute("Disabled", disabled and true or false)
	end
end

function CloudUI.SetStyle(button, style)
	if button then
		button:SetAttribute("Style", tostring(style))
	end
end

----------------------------------------------------------------------
-- Panel (window)
----------------------------------------------------------------------
-- props: Name, Size, Position, AnchorPoint, Title, Closable, OnClose, Parent, Accent (Color3: the neon border, glow,
--        title underline), Category (v5: a Theme.Category name, e.g. "Pets", when no Accent is given; default Blue),
--        Glow (v5, default true), Clouds (ignored since v5: no cloud bumps), LayoutOrder, TitleSize (default 34)
function CloudUI.Panel(props)
	props = props or {}
	local hasTitle = type(props.Title) == "string" and props.Title ~= ""
	local accent = props.Accent
	if typeof(accent) ~= "Color3" then
		accent = Theme.NeonColor(props.Category or "Blue")
	end
	local topInset = CloudUI.ContentInset(hasTitle, props.Clouds)

	local root = frame(props.Name or "CloudPanel", {
		Size = props.Size or UDim2.fromOffset(520, 380),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
	})

	-- soft drop shadow (keeps the dark card readable on a bright sky)
	local shadow = frame("Shadow", {
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.72,
		Position = UDim2.new(0, 0, 0, 6),
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 0,
	}, root)
	corner(shadow, PANEL_CORNER + 2)

	-- the Neon card: dark navy fill, a 3 px neon border, an outer glow ring, a sheen line under the top edge
	local card = NeonKit.Card({
		Name = "Body",
		Size = UDim2.new(1, 0, 1, 0),
		Color = accent,
		Corner = PANEL_CORNER,
		Stroke = OUTLINE_THICKNESS,
		Glow = props.Glow ~= false,
		Floor = false,
		ZIndex = 2,
		Active = true, -- sinks clicks so the world behind the window is not clicked
		Parent = root,
	})
	local body = card.Root

	-- the content well: a slightly darker inset (no decorative children: callers own its layout)
	local content = frame("Content", {
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.55,
		Position = UDim2.new(0, PANEL_PAD, 0, topInset),
		Size = UDim2.new(1, -2 * PANEL_PAD, 1, -(topInset + PANEL_PAD)),
		ZIndex = 4,
	}, root)
	corner(content, 12)
	stroke(content, WHITE, 1, 0.9)

	-- title: GothamBlack 34, white with a dark stroke, over a neon underline that fades out to the right
	local titleBar, titleLabel, underline = nil, nil, nil
	if hasTitle then
		titleBar = frame("TitleBar", {
			Position = UDim2.new(0, PANEL_PAD, 0, TITLE_TOP),
			Size = UDim2.new(1, -2 * PANEL_PAD, 0, TITLE_H),
			ZIndex = 5,
		}, root)
		local rightRoom = props.Closable and (CLOSE_SIZE + 18) or 16
		titleLabel = Theme.Label(props.Title, "Title", {
			Size = props.TitleSize or TITLE_TEXT,
			Stroke = 1,
			Outline = 3,
			OutlineColor = INK,
			Props = {
				Name = "Title",
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -(10 + rightRoom), 1, -4),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 6,
			},
		})
		titleLabel.Parent = titleBar
		underline = frame("Underline", {
			BackgroundColor3 = accent,
			BackgroundTransparency = 0,
			Position = UDim2.new(0, 8, 1, 1),
			Size = UDim2.new(1, -16, 0, 3),
			ZIndex = 6,
		}, titleBar)
		round(underline)
		Util.Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.6, 0.15),
				NumberSequenceKeypoint.new(1, 0.85),
			}),
			Parent = underline,
		})
	end

	local panel = {
		Root = root,
		Body = body,
		Content = content,
		TitleBar = titleBar,
		TitleLabel = titleLabel,
		Card = card,
	}

	function panel.Close()
		if props.OnClose then
			props.OnClose(panel)
		else
			root.Visible = false
		end
	end

	function panel.SetTitle(text)
		if titleLabel then
			titleLabel.Text = tostring(text)
		end
	end

	-- Re-colour the neon border, glow and title underline (e.g. by rarity or category).
	function panel.SetAccent(color)
		if type(color) == "string" then
			color = Theme.NeonColor(color)
		end
		if typeof(color) ~= "Color3" then
			return
		end
		card.SetColor(color)
		if underline then
			underline.BackgroundColor3 = color
		end
	end

	function panel.Destroy()
		root:Destroy()
	end

	if props.Closable then
		local closeSize = hasTitle and CLOSE_SIZE or (CLOSE_SIZE - 2)
		local position
		if hasTitle then
			-- at the right end of the title row
			position = UDim2.new(1, -(PANEL_PAD + 4 + CLOSE_SIZE / 2), 0, TITLE_TOP + math.floor(TITLE_H / 2) - 2)
		else
			-- on the top-right corner of the card
			position = UDim2.new(1, -12, 0, 8)
		end
		local closeButton = CloudUI.Button({
			Name = "Close",
			Text = "X",
			Style = "Red",
			TextSize = 24,
			Size = UDim2.fromOffset(closeSize, closeSize),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			ZIndex = 8,
			Callback = function()
				panel.Close()
			end,
			Parent = root,
		})
		panel.CloseButton = closeButton
	end

	root.Parent = props.Parent
	return panel
end

----------------------------------------------------------------------
-- Bar
----------------------------------------------------------------------
-- props: Size, Color, Label, Parent, Height, Position, AnchorPoint, Name, LayoutOrder, TextSize
function CloudUI.Bar(props)
	props = props or {}
	local height = props.Height or 24
	local color = props.Color or Colors.Health
	local fraction = 1

	local root = frame(props.Name or "CloudBar", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Size = props.Size or UDim2.new(1, 0, 0, height),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
	})
	round(root)
	-- v5: a dark ink track with a thin light rim (the fill carries the colour)
	local trackStroke = stroke(root, Theme.Lighten(PANEL_TOP, 0.12), 2.5, 0)
	gradient(root, ColorSequence.new(INK, PANEL_TOP), 90)

	local inner = frame("Inner", {
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(1, -6, 1, -6),
	}, root)

	local fill = frame("Fill", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 1, 0),
	}, inner)
	round(fill)
	local function fillSequence(c)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Lighten(c, 0.34)),
			ColorSequenceKeypoint.new(0.5, c),
			ColorSequenceKeypoint.new(1, Theme.Darken(c, 0.16)),
		})
	end
	local fillGradient = gradient(fill, fillSequence(color), 90)
	addShine(fill, 0.34, 6, 0.7)

	local textSize = props.TextSize or Util.Clamp(math.floor(height * 0.66 + 0.5), 15, 26)
	local label = Theme.Label(props.Label or "", "Heading", {
		Size = textSize,
		Stroke = 0.1,
		Outline = height >= 20 and 2 or 1.5,
		Props = {
			Name = "Text",
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 3,
			TextXAlignment = Enum.TextXAlignment.Center,
		},
	})
	label.Parent = root

	local bar = { Root = root, Fill = fill, Label = label }
	local running = nil

	function bar.SetFraction(value, animate)
		fraction = Util.Clamp(tonumber(value) or 0, 0, 1)
		local size = UDim2.new(fraction, 0, 1, 0)
		if running then
			running:Cancel()
			running = nil
		end
		if animate then
			running = Util.Tween(fill, 0.25, { Size = size }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		else
			fill.Size = size
		end
	end

	function bar.GetFraction()
		return fraction
	end

	function bar.SetText(text)
		label.Text = tostring(text or "")
	end

	function bar.SetColor(newColor)
		if typeof(newColor) ~= "Color3" then
			return
		end
		color = newColor
		fillGradient.Color = fillSequence(color)
	end
	bar.TrackStroke = trackStroke

	root.Parent = props.Parent
	return bar
end

----------------------------------------------------------------------
-- Pill
----------------------------------------------------------------------
local function kindColor(kind)
	if typeof(kind) == "Color3" then
		return kind
	end
	if type(kind) == "string" then
		local found = KIND_COLORS[kind:lower()]
		if found then
			return found
		end
		return CloudUI.RarityColor(kind)
	end
	return KIND_COLORS.info or Color3.fromRGB(90, 158, 234)
end

-- kind: "info" | "good" | "bad" | "token" | a rarity id ("Epic") | a Color3
function CloudUI.Pill(text, kind, parent)
	local color = kindColor(kind)
	-- v5: a dark face tinted by the kind colour, a neon border in that colour, white text with a dark stroke
	local pill = Theme.Label(tostring(text or ""), "Heading", {
		Size = 17,
		Stroke = 1,
		Outline = 2,
		OutlineColor = INK,
		Props = {
			Name = "Pill",
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Darken(color, 0.62),
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 28),
			TextXAlignment = Enum.TextXAlignment.Center,
		},
	})
	round(pill)
	stroke(pill, Theme.Lighten(color, 0.08), 2, 0)
	gradient(pill, FACE_SEQUENCE, 90)
	padding(pill, 12, 0, 12, 0)
	Util.Create("UISizeConstraint", { MinSize = Vector2.new(34, 28), Parent = pill })
	pill.Parent = parent
	return pill
end

----------------------------------------------------------------------
-- Icon button (round, with a caption below)
----------------------------------------------------------------------
-- props: Glyph (short text), Label (caption), Color (Color3 or style name), Callback, Parent, Size
--        (whole widget, default 72x96; the circle's diameter is the widget width, and with a caption the
--        widget is made at least width + 24 px tall so the caption never overlaps its neighbours),
--        Badge (bool), Position, AnchorPoint, Name, LayoutOrder
function CloudUI.IconButton(props)
	props = props or {}
	local hasLabel = type(props.Label) == "string" and props.Label ~= ""
	local labelHeight = 22
	local color = props.Color
	if type(color) == "string" then
		color = styleBase(color)
	elseif typeof(color) ~= "Color3" then
		color = BUTTON_COLORS.Blue or Color3.fromRGB(90, 158, 234)
	end

	local widgetSize = props.Size or UDim2.fromOffset(72, hasLabel and 96 or 72)
	if hasLabel and widgetSize.X.Scale == 0 and widgetSize.Y.Scale == 0 then
		local minHeight = widgetSize.X.Offset + labelHeight + 2
		if widgetSize.Y.Offset < minHeight then
			widgetSize = UDim2.fromOffset(widgetSize.X.Offset, minHeight)
		end
	end

	local root = frame(props.Name or ("IconButton_" .. tostring(props.Label or props.Glyph or "")), {
		Size = widgetSize,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
	})

	local holder = frame("CircleHolder", {
		Size = UDim2.new(1, 0, 1, hasLabel and -labelHeight or 0),
	}, root)

	local button = Util.Create("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -8, 1, -8),
		Parent = holder,
	})
	Util.Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = button })
	round(button)
	local outline = stroke(button, color, 3, 0)
	local faceGradient = gradient(button, ColorSequence.new(Theme.Lighten(color, 0.3), color), 90)

	-- v5: a dark disc tinted by the colour (light at the top), the neon ring around it
	local function faceSequence(c)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Darken(c, 0.25)),
			ColorSequenceKeypoint.new(0.55, Theme.Darken(c, 0.55)),
			ColorSequenceKeypoint.new(1, Theme.Darken(c, 0.78)),
		})
	end
	local function applyColor(c)
		color = c
		faceGradient.Color = faceSequence(c)
	end
	applyColor(color)

	local shine = Util.Create("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.76,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.1, 0),
		Size = UDim2.new(0.54, 0, 0.24, 0),
		Parent = button,
	})
	round(shine)

	local glyph = Theme.Label(tostring(props.Glyph or ""), "Title", {
		Scaled = true,
		Stroke = 1,
		Outline = 2,
		OutlineColor = INK,
		Props = {
			Name = "Glyph",
			Position = UDim2.new(0.5, 0, 0.44, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0.58, 0, 0.58, 0),
			ZIndex = 2,
		},
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 60, MinTextSize = 10, Parent = glyph })
	glyph.Parent = button

	local caption = nil
	if hasLabel then
		caption = Theme.Label(props.Label, "Heading", {
			Size = 16,
			Stroke = 0.2,
			Outline = 2,
			Props = {
				Name = "Caption",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.new(1.3, 0, 0, labelHeight),
				TextTruncate = Enum.TextTruncate.AtEnd,
			},
		})
		caption.Parent = root
	end

	-- little red "!" dot
	local badge = frame("Badge", {
		BackgroundColor3 = BUTTON_COLORS.Red or Color3.fromRGB(228, 90, 92),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.86, 0, 0.14, 0),
		Size = UDim2.fromOffset(24, 24),
		ZIndex = 4,
		Visible = props.Badge == true,
	}, button)
	round(badge)
	stroke(badge, INK, 2.5, 0)
	local badgeText = Theme.Label("!", "Button", {
		Size = 17,
		Stroke = 0.1,
		Props = { Name = "Mark", Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 },
	})
	badgeText.Parent = badge

	local function paint(hovering, pressing)
		local face = color
		if pressing then
			face = Theme.Darken(color, 0.08)
		elseif hovering then
			face = Theme.Lighten(color, 0.1)
		end
		faceGradient.Color = faceSequence(face)
		outline.Color = color
	end
	attachFx(button, {
		Hover = 1.07,
		Press = 0.93,
		OnState = paint,
	})

	if props.Callback then
		button.Activated:Connect(function()
			props.Callback(button)
		end)
	end

	local widget = { Root = root, Button = button, Glyph = glyph, Caption = caption }

	function widget.SetBadge(on)
		badge.Visible = on and true or false
	end

	function widget.SetGlyph(text)
		glyph.Text = tostring(text or "")
	end

	function widget.SetLabel(text)
		if caption then
			caption.Text = tostring(text or "")
		end
	end

	function widget.SetColor(newColor)
		if typeof(newColor) == "Color3" then
			applyColor(newColor)
			outline.Color = newColor
		end
	end

	root.Parent = props.Parent
	return widget
end

----------------------------------------------------------------------
-- Tooltip (one shared label, follows the mouse; long-press on touch)
----------------------------------------------------------------------
local tip = nil
local TIP_TEXT = 18 -- 1080p px; the tooltip gui has no UIScale, so the size is scaled when shown
local TIP_MAX_W = 300

local function ensureTip()
	if tip then
		return tip
	end
	local gui = CloudUI.NewScreenGui("CloudUITooltip", 60)
	gui.IgnoreGuiInset = true
	local label = Theme.Label("", "Body", {
		Size = Theme.ScaledSize(TIP_TEXT),
		Stroke = 0.35,
		Props = {
			Name = "Tip",
			Visible = false,
			BackgroundTransparency = 0.04,
			BackgroundColor3 = PANEL_BOTTOM,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 10,
		},
	})
	corner(label, 10)
	stroke(label, NEON.Blue, 2, 0.1)
	padding(label, 12, 8, 12, 8)
	local limit = Util.Create("UISizeConstraint", { MaxSize = Vector2.new(TIP_MAX_W, 480), Parent = label })
	label.Parent = gui
	tip = { Gui = gui, Label = label, Limit = limit, Owner = nil, Mode = "mouse", Ticker = nil }
	return tip
end

local function mouseLocation()
	local ok, pos = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if ok and pos then
		return pos
	end
	return Vector2.new(0, 0)
end

local function hideTip(owner)
	if not tip or not tip.Owner then
		return
	end
	if owner and tip.Owner ~= owner then
		return
	end
	tip.Owner = nil
	tip.Label.Visible = false
	if tip.Ticker then
		tip.Ticker.dead = true
		tip.Ticker = nil
	end
end

local function placeTip()
	if not tip or not tip.Owner then
		return
	end
	local owner = tip.Owner
	if not owner.Parent or not isShown(owner) then
		hideTip(owner)
		return
	end
	local label = tip.Label
	local screen = tip.Gui.AbsoluteSize
	local size = label.AbsoluteSize
	local x, y
	if tip.Mode == "mouse" then
		local m = mouseLocation()
		x = m.X + 16
		y = m.Y + 22
		if screen.Y > 0 and y + size.Y > screen.Y - 6 then
			y = m.Y - size.Y - 14
		end
	else
		local pos = owner.AbsolutePosition
		local osize = owner.AbsoluteSize
		x = pos.X + osize.X * 0.5 - size.X * 0.5
		y = pos.Y - size.Y - 8
		if y < 6 then
			y = pos.Y + osize.Y + 8
		end
	end
	if screen.X > 0 then
		x = Util.Clamp(x, 6, math.max(6, screen.X - size.X - 6))
	end
	label.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

local function showTip(owner, text, mode)
	local t = ensureTip()
	hideTip()
	t.Owner = owner
	t.Mode = mode or "mouse"
	t.Label.TextSize = Theme.ScaledSize(TIP_TEXT)
	t.Limit.MaxSize = Vector2.new(math.floor(TIP_MAX_W * Theme.ScreenFactor()), 480)
	t.Label.Text = text
	t.Label.Visible = true
	placeTip()
	t.Ticker = addTicker(placeTip)
end

-- textFn: function() -> string|nil (or a plain string). Returns a function that removes the tooltip.
function CloudUI.Tooltip(guiObject, textFn)
	if not guiObject then
		return function() end
	end
	local token = 0
	local hovering = false
	local pressing = false
	local connections = {}

	local function resolve()
		local text = textFn
		if type(textFn) == "function" then
			local ok, value = pcall(textFn)
			text = ok and value or nil
		end
		if type(text) == "string" and text ~= "" then
			return text
		end
		return nil
	end

	table.insert(
		connections,
		guiObject.MouseEnter:Connect(function()
			hovering = true
			token = token + 1
			local mine = token
			task.delay(TOOLTIP_DELAY, function()
				if hovering and token == mine then
					local text = resolve()
					if text then
						showTip(guiObject, text, "mouse")
					end
				end
			end)
		end)
	)
	table.insert(
		connections,
		guiObject.MouseLeave:Connect(function()
			hovering = false
			token = token + 1
			hideTip(guiObject)
		end)
	)
	table.insert(
		connections,
		guiObject.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				pressing = true
				token = token + 1
				local mine = token
				task.delay(LONG_PRESS, function()
					if pressing and token == mine then
						local text = resolve()
						if text then
							showTip(guiObject, text, "object")
							task.delay(2.4, function()
								hideTip(guiObject)
							end)
						end
					end
				end)
			end
		end)
	)
	table.insert(
		connections,
		guiObject.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				pressing = false
				token = token + 1
			end
		end)
	)
	if guiObject:IsA("TextButton") or guiObject:IsA("ImageButton") then
		table.insert(
			connections,
			guiObject.MouseButton1Down:Connect(function()
				token = token + 1
				hideTip(guiObject)
			end)
		)
	end

	return function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		connections = {}
		hideTip(guiObject)
	end
end

----------------------------------------------------------------------
-- Pet viewport
----------------------------------------------------------------------
local PetBuilderModule = nil
local PetCatalogModule = nil
local petBuilderTried = false
local petCatalogTried = false
local viewportCounter = 0

local function getPetBuilder()
	if not petBuilderTried then
		petBuilderTried = true
		local ok, result = pcall(function()
			return require(Shared:WaitForChild("PetBuilder", 5))
		end)
		if ok and type(result) == "table" then
			PetBuilderModule = result
		else
			warn("[CloudUI] PetBuilder is unavailable: " .. tostring(result))
		end
	end
	return PetBuilderModule
end

local function getPetCatalog()
	if not petCatalogTried then
		petCatalogTried = true
		local ok, result = pcall(function()
			return require(Shared:WaitForChild("PetCatalog", 5))
		end)
		if ok and type(result) == "table" then
			PetCatalogModule = result
		end
	end
	return PetCatalogModule
end

-- A ViewportFrame showing a PetBuilder model that spins slowly and flaps. All viewports share the one
-- CloudUI.Update loop; hidden viewports skip work and destroyed ones unregister themselves.
-- size: UDim2 | Vector2 | number (square pixels) | nil (fill the parent)
-- opts: Position, AnchorPoint, ZIndex, Animate (default true), Spin ("spin"|"sway"|"none", default "spin"),
--       Flap (speed multiplier), Excited (0..1), Detail ("High" default | "Low", passed to PetBuilder.Build),
--       Evolved (Phase 4: the stored evolution stage 1 | 2 (or true = 1), passed to PetBuilder.Build as opts.Evolved;
--       0 / nil / false = the normal form; the def itself is never changed)
function CloudUI.PetViewport(parent, petDef, size, opts)
	opts = opts or {}
	viewportCounter = viewportCounter + 1
	local phase = (viewportCounter * 0.83) % 6.28

	if type(petDef) == "string" then
		local catalog = getPetCatalog()
		petDef = catalog and catalog.Get and catalog.Get(petDef) or nil
	end

	local viewport = Util.Create("ViewportFrame", {
		Name = "PetViewport",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = toUDim2(size, UDim2.new(1, 0, 1, 0)),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.new(0, 0),
		ZIndex = opts.ZIndex or 1,
		Ambient = Color3.fromRGB(176, 182, 206),
		LightColor = Color3.fromRGB(255, 246, 232),
		LightDirection = Vector3.new(-0.4, -0.8, 1), -- shines towards +Z: onto a model's -Z "front" (see side)
	})
	local camera = Util.Create("Camera", { FieldOfView = FOV, Parent = viewport })
	viewport.CurrentCamera = camera

	local animOpts = { Flap = opts.Flap or 1, Excited = opts.Excited or 0 }
	local animated = opts.Animate ~= false
	local spinMode = opts.Spin or "spin"
	local angle = 0.55
	local dead = false
	local model = nil
	local builder = nil

	local center = Vector3.new(0, 1, 0)
	local halfH, halfW = 1.5, 1.8
	local lastAspect = 1
	local side = -1 -- which side of the model the camera sits on: -1 = the -Z side (Roblox models face -Z)

	if type(petDef) == "table" then
		builder = getPetBuilder()
		if builder and type(builder.Build) == "function" then
			local buildOpts = { Scale = 1 }
			if opts.Detail == "Low" or opts.Detail == "High" then
				buildOpts.Detail = opts.Detail
			end
			local evolved = opts.Evolved
			if evolved == true then
				evolved = 1
			end
			evolved = tonumber(evolved)
			if evolved and evolved >= 1 then
				buildOpts.Evolved = math.min(2, math.floor(evolved))
			end
			local ok, built = pcall(builder.Build, petDef, buildOpts)
			if ok and typeof(built) == "Instance" then
				model = built
			else
				warn("[CloudUI] PetBuilder.Build failed: " .. tostring(built))
			end
		end
	end

	local function fit()
		local abs = viewport.AbsoluteSize
		local aspect = 1
		if abs.X > 0 and abs.Y > 0 then
			aspect = abs.X / abs.Y
		end
		lastAspect = aspect
		local t = math.tan(math.rad(FOV) / 2)
		local dist = math.max(halfH * 1.2 / t, halfW * 1.08 / (t * aspect))
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, halfH * 0.12, dist * side), center)
	end

	-- Pets face -Z like every Roblox model (CFrame.lookAt convention). If a model's eyes turn out to sit
	-- on its +Z side instead, put the camera (and the light) there so the viewport shows the face.
	-- Expects the model to be posed at the origin with an identity pivot.
	local function detectSide(m, c)
		local sum, count = 0, 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:lower():find("eye", 1, true) then
				sum = sum + (d.Position.Z - c.Z)
				count = count + 1
			end
		end
		if count > 0 and sum / count > 0.05 then
			return 1
		end
		return -1
	end

	local function animate(t)
		if builder and type(builder.Animate) == "function" then
			pcall(builder.Animate, model, t, animOpts)
		end
	end

	local function pose(t, dt)
		if not model or not model.Parent then
			return
		end
		if spinMode == "spin" then
			angle = angle + dt * 0.8
		elseif spinMode == "sway" then
			angle = 0.5 + math.sin(t * 1.1 + phase) * 0.55
		end
		local bob = math.sin(t * 2.2 + phase) * halfH * 0.035
		model:PivotTo(CFrame.new(center + Vector3.new(0, bob, 0)) * CFrame.Angles(0, angle, 0) * CFrame.new(-center))
		animate(t + phase)
	end

	if model then
		model.Parent = viewport
		pcall(function()
			model:PivotTo(CFrame.new())
		end)
		animate(0.35)
		local ok, cf, bbox = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and cf and bbox then
			center = cf.Position
			halfH = math.max(0.5, bbox.Y * 0.5)
			halfW = math.max(0.5, math.max(bbox.X, bbox.Z) * 0.5)
			local okSide, found = pcall(detectSide, model, center)
			if okSide and found then
				side = found
				viewport.LightDirection = Vector3.new(-0.4, -0.8, -side)
			end
		end
		pose(0.35, 0)
	else
		-- no model available: a friendly placeholder instead of an empty frame
		local name = type(petDef) == "table" and petDef.Name or "?"
		local fallback = Theme.Label(tostring(name):sub(1, 1), "Title", {
			Scaled = true,
			Stroke = 0.2,
			Outline = 2,
			Props = { Name = "Fallback", Size = UDim2.new(1, 0, 1, 0) },
		})
		fallback.Parent = viewport
	end
	fit()

	local handle = { Frame = viewport, Model = model }
	local ticker = nil
	local visibilityTimer = 1
	local stepTimer = 0
	local orphanTime = 0
	local shown = false

	function handle.Destroy()
		if dead then
			return
		end
		dead = true
		if ticker then
			ticker.dead = true
		end
		if model then
			model:Destroy()
			model = nil
		end
		viewport:Destroy()
	end

	function handle.SetAnimated(on)
		animated = on and true or false
		if not animated and model then
			angle = 0.55
			pose(0.35, 0)
		end
	end

	function handle.SetExcited(amount)
		animOpts.Excited = Util.Clamp(tonumber(amount) or 0, 0, 1)
	end

	if model then
		ticker = addTicker(function(dt, t)
			if dead then
				return
			end
			visibilityTimer = visibilityTimer + dt
			if visibilityTimer >= 0.25 then
				local elapsed = visibilityTimer
				visibilityTimer = 0
				if viewport:IsDescendantOf(game) then
					orphanTime = 0
				else
					orphanTime = orphanTime + elapsed
				end
				if orphanTime > 1.5 then
					handle.Destroy()
					return
				end
				shown = isShown(viewport)
				if shown then
					local abs = viewport.AbsoluteSize
					if abs.X > 0 and abs.Y > 0 and math.abs(abs.X / abs.Y - lastAspect) > 0.02 then
						fit()
					end
				end
			end
			if not shown or not animated then
				return
			end
			stepTimer = stepTimer + dt
			if stepTimer < 1 / 40 then
				return
			end
			local step = stepTimer
			stepTimer = 0
			pose(t, step)
		end)
	end

	viewport.Parent = parent
	return handle
end

----------------------------------------------------------------------
-- Slot (inventory / hotbar cell with a rarity border)
----------------------------------------------------------------------
local function petKey(info)
	if type(info) ~= "table" then
		return nil
	end
	local pet = info.Pet
	if type(pet) == "table" then
		return pet.Id
	elseif type(pet) == "string" then
		return pet
	end
	return nil
end

-- props: Size (default 80x80), Position, AnchorPoint, Parent, Callback, Hotkey, Name, LayoutOrder
-- info = { Glyph, Color, Pet = PetDef, Detail = "High" | "Low" (PetBuilder detail, default High), RarityColor, Name, Blurb }
function CloudUI.Slot(props)
	props = props or {}
	local info = nil
	local selected = false
	local dimmed = false
	local hovering = false
	local viewportHandle = nil

	local root = frame(props.Name or "CloudSlot", {
		Size = props.Size or UDim2.fromOffset(80, 80),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
	})

	local button = Util.Create("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		Parent = root,
	})
	corner(button, 12)
	local outline = stroke(button, NAVY, 3, 0)
	local fill = gradient(button, ColorSequence.new(PANEL_TOP, PANEL_BOTTOM), 90)

	-- v5: a thin sheen line under the top edge + the rarity colour glowing up from the floor (behind the content)
	local gloss = frame("Gloss", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82,
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -20, 0, 2),
	}, button)
	corner(gloss, 1)
	local floorGlow = frame("Floor", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Position = UDim2.new(0, 3, 0.45, 0),
		Size = UDim2.new(1, -6, 0.55, -3),
		Visible = false,
	}, button)
	corner(floorGlow, 9)
	Util.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.74),
		}),
		Parent = floorGlow,
	})

	local content = frame("Content", { Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 }, button)

	local countLabel = Theme.Label("", "Heading", {
		Size = 17,
		Stroke = 0.1,
		Outline = 2,
		Props = {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -5, 1, -3),
			Size = UDim2.new(0.8, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			Visible = false,
			ZIndex = 5,
		},
	})
	countLabel.Parent = button

	local hotkeyChip = frame("Hotkey", {
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.05,
		Position = UDim2.new(0, 4, 0, 4),
		Size = UDim2.fromOffset(26, 26),
		ZIndex = 5,
		Visible = false,
	}, button)
	corner(hotkeyChip, 7)
	stroke(hotkeyChip, NEON.Grey, 1.5, 0.3)
	local hotkeyLabel = Theme.Label("", "Heading", {
		Size = 18,
		Stroke = 0.2,
		Props = { Name = "Key", Size = UDim2.new(1, 0, 1, 0), ZIndex = 6 },
	})
	hotkeyLabel.Parent = hotkeyChip

	local markerChip = frame("Marker", {
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(26, 26),
		ZIndex = 5,
		Visible = false,
	}, button)
	round(markerChip)
	stroke(markerChip, INK, 2, 0)
	local markerLabel = Theme.Label("", "Heading", {
		Size = 18,
		Stroke = 0.2,
		Props = { Name = "Mark", Size = UDim2.new(1, 0, 1, 0), ZIndex = 6 },
	})
	markerLabel.Parent = markerChip

	local dimOverlay = frame("Dim", {
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 6,
		Visible = false,
	}, button)
	corner(dimOverlay, 12)

	local flashOverlay = frame("Flash", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 7,
	}, button)
	corner(flashOverlay, 12)

	-- v5: a dark navy face; the border is the rarity (or the item) colour, gold when selected; the colour also
	-- glows up from the floor; an empty slot is a dim, darker well
	local function paint()
		local rarity = info and info.RarityColor
		local tint = rarity or (info and info.Color) or NEON.Grey
		if selected then
			outline.Color = NEON.Gold
			outline.Thickness = 4
		elseif info then
			outline.Color = tint
			outline.Thickness = 3
		else
			outline.Color = Theme.Darken(NEON.Grey, 0.45)
			outline.Thickness = 2.5
		end
		if not info then
			fill.Color = ColorSequence.new(Theme.Darken(PANEL_TOP, 0.2), INK)
			gloss.BackgroundTransparency = 0.92
			floorGlow.Visible = false
			return
		end
		gloss.BackgroundTransparency = 0.82
		floorGlow.Visible = true
		floorGlow.BackgroundColor3 = selected and NEON.Gold or tint
		local top = PANEL_TOP:Lerp(tint, 0.1)
		if selected then
			top = PANEL_TOP:Lerp(NEON.Gold, 0.18)
		end
		fill.Color = ColorSequence.new(top, PANEL_BOTTOM)
	end

	local function clearContent()
		if viewportHandle then
			viewportHandle.Destroy()
			viewportHandle = nil
		end
		for _, child in ipairs(content:GetChildren()) do
			child:Destroy()
		end
	end

	local fx = attachFx(button, {
		Hover = 1.06,
		Press = 0.94,
		OnState = function(isHover)
			hovering = isHover
			if viewportHandle then
				viewportHandle.SetAnimated(hovering or selected)
				viewportHandle.SetExcited(hovering and 0.8 or 0)
			end
		end,
	})

	local slot = { Root = root, Button = button, Fx = fx }

	function slot.SetContent(newInfo)
		-- Windows re-render on every State.Changed: keep the (expensive) pet model when the same pet is shown again.
		local keepKey = viewportHandle ~= nil and petKey(info) or nil
		if keepKey ~= nil and keepKey == petKey(newInfo) then
			info = newInfo
			paint()
			return
		end
		clearContent()
		info = newInfo
		if info then
			if info.Pet then
				viewportHandle = CloudUI.PetViewport(content, info.Pet, UDim2.new(1, -8, 1, -8), {
					Position = UDim2.new(0.5, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Animate = hovering or selected,
					Spin = "sway",
					Detail = info.Detail,
					ZIndex = 2,
				})
			elseif info.Glyph then
				local glyphColor = info.Color and Theme.Lighten(info.Color, 0.2) or WHITE
				local glyph = Theme.Label(tostring(info.Glyph), "Title", {
					Scaled = true,
					Stroke = 1,
					Color = glyphColor,
					Outline = 2,
					OutlineColor = INK,
					Props = {
						Name = "Glyph",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.46, 0),
						Size = UDim2.new(0.62, 0, 0.62, 0),
						ZIndex = 3,
					},
				})
				Util.Create("UITextSizeConstraint", { MaxTextSize = 48, MinTextSize = 10, Parent = glyph })
				glyph.Parent = content
			end
		end
		paint()
	end

	function slot.SetSelected(on)
		selected = on and true or false
		paint()
		if viewportHandle then
			viewportHandle.SetAnimated(hovering or selected)
		end
	end

	-- Pet slots hide counts of 1 ("x1" is noise); item slots always show their count.
	function slot.SetCount(n)
		if type(n) ~= "number" then
			countLabel.Visible = false
			return
		end
		local isPet = info ~= nil and info.Pet ~= nil
		countLabel.Text = "x" .. tostring(math.floor(n))
		countLabel.Visible = (not isPet) or n > 1
	end

	function slot.SetHotkey(text)
		local value = text and tostring(text) or ""
		hotkeyLabel.Text = value
		hotkeyChip.Visible = value ~= ""
	end

	-- small corner chip, e.g. "*" for an equipped pet; nil hides it
	function slot.SetMarker(text, color)
		local value = text and tostring(text) or ""
		markerLabel.Text = value
		markerChip.Visible = value ~= ""
		if typeof(color) == "Color3" then
			markerChip.BackgroundColor3 = color
		end
	end

	function slot.SetDimmed(on)
		dimmed = on and true or false
		dimOverlay.Visible = dimmed
	end

	-- quick white flash, e.g. after an item was used
	function slot.Flash()
		flashOverlay.BackgroundTransparency = 0.35
		Util.Tween(flashOverlay, 0.35, { BackgroundTransparency = 1 })
	end

	function slot.Destroy()
		clearContent()
		root:Destroy()
	end

	CloudUI.Tooltip(button, function()
		if not info or not info.Name then
			return nil
		end
		if info.Blurb then
			return tostring(info.Name) .. "\n" .. tostring(info.Blurb)
		end
		return tostring(info.Name)
	end)

	if props.Callback then
		button.Activated:Connect(function()
			props.Callback(slot)
		end)
	end

	slot.SetHotkey(props.Hotkey)
	slot.SetContent(nil)
	root.Parent = props.Parent
	return slot
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
-- props: Parent, Size, Position, AnchorPoint, Name, BarHeight (default 44), TextSize (default 21), OnSelect(name), Color (v5: the accent of the selected tab, a Color3 or neon / category name; default Blue)
-- Add(name, builderFn): creates the page frame, calls builderFn(page) immediately (errors are
-- warned, not thrown) and returns the page. The first tab added is selected.
function CloudUI.Tabs(props)
	props = props or {}
	local barHeight = props.BarHeight or 44
	local textSize = props.TextSize or 21

	local root = frame(props.Name or "CloudTabs", {
		Size = props.Size or UDim2.new(1, 0, 1, 0),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
	})
	local bar = frame("TabBar", { Size = UDim2.new(1, 0, 0, barHeight) }, root)
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = bar,
	})
	local content = frame("TabContent", {
		Position = UDim2.new(0, 0, 0, barHeight + 8),
		Size = UDim2.new(1, 0, 1, -(barHeight + 8)),
	}, root)

	local pages = {}
	local buttons = {}
	local outlines = {}
	local selected = nil
	local count = 0

	-- v5: neon pills; the selected tab is filled with its dark accent colour and glows, the others are navy with a
	-- dim border (props.Color: the accent, a Color3 or neon / category name; default Blue)
	local accent = Theme.NeonColor(props.Color or "Blue")
	local activeFace = Theme.Darken(accent, 0.42)
	local idleFace = PANEL_TOP
	local strokes = {}

	local function paintTab(name, animate)
		local button = buttons[name]
		if not button then
			return
		end
		local on = (name == selected)
		local face = on and activeFace or idleFace
		local textColor = on and WHITE or MUTED
		if animate then
			Util.Tween(button, 0.14, { BackgroundColor3 = face, TextColor3 = textColor })
		else
			button.BackgroundColor3 = face
			button.TextColor3 = textColor
		end
		button.TextStrokeColor3 = INK
		local border = strokes[name]
		if border then
			border.Color = on and accent or Theme.Darken(accent, 0.45)
			border.Thickness = on and 3 or 2
		end
		local textOutline = outlines[name]
		if textOutline then
			textOutline.Color = INK
			textOutline.Transparency = on and 0 or 0.25
		end
	end

	local tabs = { Root = root, Content = content, Bar = bar }

	function tabs.Select(name)
		if not pages[name] then
			return
		end
		local changed = selected ~= name
		selected = name
		for pageName, page in pairs(pages) do
			page.Visible = (pageName == name)
			paintTab(pageName, true)
		end
		if changed and props.OnSelect then
			props.OnSelect(name)
		end
	end

	function tabs.Add(name, builderFn)
		count = count + 1
		local page = frame("Page_" .. tostring(name), {
			Size = UDim2.new(1, 0, 1, 0),
			Visible = false,
		}, content)
		pages[name] = page

		local button = Util.Create("TextButton", {
			Name = "Tab_" .. tostring(name),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			BackgroundColor3 = idleFace,
			Text = tostring(name),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, barHeight - 4),
			LayoutOrder = count,
		})
		Theme.Style(button, "Button", { Size = textSize, Color = MUTED, Stroke = 1 })
		corner(button, math.floor((barHeight - 4) / 2))
		strokes[name] = stroke(button, accent, 2, 0)
		outlines[name] = Theme.TextOutline(button, 2, INK, 0.25)
		gradient(button, FACE_SEQUENCE, 90)
		padding(button, 20, 0, 20, 0)
		Util.Create("UISizeConstraint", { MinSize = Vector2.new(84, 0), Parent = button })
		button.Activated:Connect(function()
			tabs.Select(name)
		end)
		button.Parent = bar
		buttons[name] = button
		paintTab(name, false)

		if builderFn then
			local ok, err = pcall(builderFn, page)
			if not ok then
				warn("[CloudUI] tab '" .. tostring(name) .. "' builder failed: " .. tostring(err))
			end
		end
		if not selected then
			tabs.Select(name)
		end
		return page
	end

	function tabs.GetSelected()
		return selected
	end

	function tabs.GetPage(name)
		return pages[name]
	end

	function tabs.GetButton(name)
		return buttons[name]
	end

	root.Parent = props.Parent
	return tabs
end

----------------------------------------------------------------------
-- Grid
----------------------------------------------------------------------
-- cellSize: UDim2 | Vector2 | number; padding: number (px) | UDim2
function CloudUI.Grid(parent, cellSize, cellPadding)
	local cell = toUDim2(cellSize, UDim2.fromOffset(84, 84))
	local pad = toUDim2(cellPadding, UDim2.fromOffset(10, 10))

	local scroll = Util.Create("ScrollingFrame", {
		Name = "CloudGrid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = Theme.Lighten(NEON.Blue, 0.2),
		ScrollBarImageTransparency = 0.1,
	})
	padding(scroll, 10, 10, 10, 10)
	Util.Create("UIGridLayout", {
		Name = "Layout",
		CellSize = cell,
		CellPadding = pad,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = scroll,
	})
	scroll.Parent = parent
	return scroll
end

return CloudUI
