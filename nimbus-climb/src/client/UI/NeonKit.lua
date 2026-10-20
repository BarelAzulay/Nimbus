-- NeonKit: the Phase 5 "Neon" GUI kit (ARCHITECTURE_V3.md "Phase 5 build contract" 6.6, image 21.png): dark navy
-- cards with a glowing neon border in their own colour, a soft coloured floor glow, big glossy icons on orbs and bold
-- white GothamBlack labels with a dark stroke. Premium, game-y, and never in the way: the window rule (SideRect /
-- Dock) keeps every window docked at the right edge (landscape) or as a bottom sheet (portrait).
--
--   NeonKit.Card(props)   -> { Root, Body, Stroke, Glow, Floor, SetColor(color), SetGlow(on) }
--   NeonKit.Tile(props)   -> { Root, Card, Orb, Icon, Label, SetBadge(on), SetColor(color), SetLabel(text), SetIcon(id) }
--   NeonKit.Orb(parent, color, size)  -> Frame (a glossy disc; centred in its parent unless moved)
--   NeonKit.Icon(parent, id, size)    -> TextLabel (emoji glyph) | ImageLabel (when Config.Icons[id] = "rbxassetid://n")
--   NeonKit.Pill(props)   -> { Root, Card, Coin, Glyph, Text, SetText(text), SetColor(color) }
--   NeonKit.Button(props) -> TextButton (Variant "Primary" | "Outline"; hover 1.04 / press 0.95; Disabled attribute)
--   NeonKit.SideRect(prefW, prefH, minW, minH) -> { x, y, w, h, scale, mode = "Side" | "Sheet", designW, designH }
--   NeonKit.Dock(holder, uiScale, prefW, prefH, minW, minH) -> { Rect, Refresh(), Disconnect() }
--     (also a MouseLock hold while the holder is shown: client/MouseLock.WatchVisible; dungeon-fixes decision 6)
--
-- Conventions (the same as CloudUI): sizes are DESIGN pixels of a 1920x1080 screen; put the tree under one UIScale
-- (CloudUI.AutoScale, or the scale NeonKit.Dock writes) and it follows the readability rule everywhere. Colours are a
-- Color3, a Theme.Neon name ("Orange") or a Theme.Category name ("Pets"); see Theme.NeonColor. Every text uses a
-- Theme font role. Every constructor takes Name / Parent / Position / AnchorPoint / Size / LayoutOrder / ZIndex.
-- Card children go into card.Body (it never gets decorative children, so a UIListLayout there is fine).
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local NeonKit = {}

local Colors = Theme.Colors
local WHITE = Colors.White
local INK = Colors.PanelInk or Color3.fromRGB(8, 10, 28)
local TOP = Colors.PanelTop or Color3.fromRGB(26, 32, 72)
local BOTTOM = Colors.PanelBottom or Color3.fromRGB(12, 15, 38)

-- the kit's numbers (design px); tests and window owners read them
NeonKit.Metrics = {
	Corner = 14, -- card corner radius
	Stroke = 3, -- the neon border
	GlowPad = 3, -- the glow ring frame sits this far outside the card (its stroke hugs the neon border)
	GlowStroke = 5, -- ... this thick
	GlowTransparency = 0.62,
	FloorFrom = 0.45, -- the coloured floor glow starts this far down the card (scale)
	FloorTransparency = 0.72, -- ... and is this transparent at the very bottom
	FloorMaxHeight = 260, -- cards taller than this get no floor by default (windows)
	SheenTransparency = 0.8,
	TileIcon = 0.46, -- icon glyph size x tile size
	TileOrb = 0.62, -- orb diameter x tile size
	TileLabel = 0.2, -- label text size x tile size
	TileLabelMin = 18, -- ... never below this (14.4 px on a phone at the 0.8 scale)
	LabelStroke = 2.5, -- the dark stroke of a tile label
	Margin = 12, -- window rule: screen margin x the screen factor
	Inset = 58, -- window rule: Roblox's top bar
	SideMaxW = 0.44, -- landscape: a docked window is at most this much of the width
	SheetMaxH = 0.56, -- portrait: a bottom sheet is at most this much of the height
	SheetScale = 0.8,
	MinScaleDesktop = 0.85,
	MinScaleTouch = 0.8,
}
local MX = NeonKit.Metrics

-- Default glyphs of the icon ids (Config.Icons[id] = "rbxassetid://n" swaps in a real image later, no code change).
NeonKit.Glyphs = {
	Pets = "\240\159\144\190", -- paw prints
	Items = "\240\159\142\146", -- backpack
	Inventory = "\240\159\142\146",
	Team = "\226\154\148\239\184\143", -- crossed swords
	Index = "\240\159\147\150", -- open book
	Shop = "\240\159\155\146", -- cart
	Home = "\240\159\143\160", -- house
	Spot = "\240\159\143\160",
	Stats = "\240\159\143\134", -- trophy
	Settings = "\226\154\153\239\184\143", -- gear
	Obby = "\226\155\176\239\184\143", -- mountain
	Dungeon = "\240\159\151\157\239\184\143", -- key
	Ring = "\240\159\145\145", -- crown
	Arena = "\240\159\143\159\239\184\143", -- stadium
	Altar = "\226\154\161", -- lightning
	Care = "\240\159\141\147", -- berry
	Berries = "\240\159\141\147",
	Fusion = "\226\156\168", -- sparkles
	Battle = "\226\154\148\239\184\143",
	Cash = "$",
	Tokens = "\226\152\129", -- cloud
	Gems = "\226\151\134", -- diamond
	Close = "\226\156\149", -- multiplication x
	Lock = "\240\159\148\146",
	Play = "\226\150\182",
}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function colorOf(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" and value ~= "" then
		return Theme.NeonColor(value)
	end
	return fallback or Theme.Neon.Blue
end
NeonKit.ColorOf = colorOf

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

local function corner(parent, px)
	return Util.Create("UICorner", { CornerRadius = UDim.new(0, px), Parent = parent })
end

local function round(parent)
	return Util.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = parent })
end

local function stroke(parent, color, thickness, transparency, name)
	return Util.Create("UIStroke", {
		Name = name or "UIStroke",
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
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

local function floorTransparency()
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 0.93),
		NumberSequenceKeypoint.new(1, MX.FloorTransparency),
	})
end

-- the dark navy fill, a breath of the neon colour mixed into the top
local function fillSequence(top, bottom)
	return ColorSequence.new(top, bottom)
end

-- Hover 1.04 / press 0.95 on a UIScale named FxScale (CloudUI's convention). onState(hover, press) repaints.
local function attachFx(button, onState, hoverScale, pressScale)
	local scale = button:FindFirstChild("FxScale")
	if not (scale and scale:IsA("UIScale")) then
		scale = Util.Create("UIScale", { Name = "FxScale", Scale = 1, Parent = button })
	end
	local st = { Hover = false, Press = false, Running = nil }
	local function refresh(seconds)
		local target = 1
		if st.Press then
			target = pressScale or 0.95
		elseif st.Hover then
			target = hoverScale or 1.04
		end
		if st.Running then
			st.Running:Cancel()
		end
		st.Running = Util.Tween(scale, seconds, { Scale = target }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if onState then
			onState(st.Hover, st.Press)
		end
	end
	button.MouseEnter:Connect(function()
		st.Hover = true
		refresh(0.12)
	end)
	button.MouseLeave:Connect(function()
		st.Hover = false
		st.Press = false
		refresh(0.14)
	end)
	button.MouseButton1Down:Connect(function()
		st.Press = true
		refresh(0.07)
	end)
	button.MouseButton1Up:Connect(function()
		st.Press = false
		refresh(0.12)
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			st.Hover = false
			st.Press = false
			refresh(0.12)
		end
	end)
	st.Scale = scale
	return st
end
NeonKit.AttachFx = attachFx

local function isDisabled(button)
	return button:GetAttribute("Disabled") == true or button.Active == false
end

----------------------------------------------------------------------
-- Card
----------------------------------------------------------------------
-- props: Name, Size (UDim2 | number | Vector2; default 200x120), Position, AnchorPoint, LayoutOrder, ZIndex, Parent,
--        Color (Color3 | neon / category name; default Blue), Corner (14), Stroke (3), Glow (bool, default true),
--        Floor (bool; default: the card is at most 260 design px tall), Fill ({ top, bottom } Color3s; default
--        PanelTop -> PanelBottom), Sheen (bool, default true), Class ("Frame" default | "TextButton": a clickable
--        card, Text = "" and AutoButtonColor off), Transparency (the fill, default 0), Active, ClipsDescendants
function NeonKit.Card(props)
	props = props or {}
	local color = colorOf(props.Color)
	local size = toUDim2(props.Size, UDim2.fromOffset(200, 120))
	local radius = tonumber(props.Corner) or MX.Corner
	local thickness = tonumber(props.Stroke) or MX.Stroke
	local z = props.ZIndex or 1
	local class = (props.Class == "TextButton") and "TextButton" or "Frame"

	local root = Instance.new(class)
	root.Name = props.Name or "NeonCard"
	root.BorderSizePixel = 0
	root.BackgroundColor3 = WHITE
	root.BackgroundTransparency = tonumber(props.Transparency) or 0
	root.Size = size
	root.Position = props.Position or UDim2.new()
	root.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	root.LayoutOrder = props.LayoutOrder or 0
	root.ZIndex = z
	if props.Active ~= nil then
		root.Active = props.Active
	end
	if class == "TextButton" then
		root.Text = ""
		root.AutoButtonColor = false
		if props.Active == nil then
			root.Active = true
		end
	end
	corner(root, radius)
	-- A UIGradient also tints the TEXT of its TextButton (and a child frame would cover that text), so a clickable
	-- card carries its fill as BackgroundColor3 plus a multiplier gradient that stays white where the text sits
	-- and only darkens the bottom; a plain card carries the real two-colour gradient.
	local fill = props.Fill
	local fillTop = (type(fill) == "table" and typeof(fill[1]) == "Color3") and fill[1] or TOP
	local fillBottom = (type(fill) == "table" and typeof(fill[2]) == "Color3") and fill[2] or BOTTOM
	local textSafe = class == "TextButton"
	local fillGradient = Util.Create("UIGradient", { Name = "Fill", Rotation = 90, Parent = root })
	local function applyFill(top, bottom)
		if textSafe then
			root.BackgroundColor3 = top:Lerp(bottom, 0.3)
			fillGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.6, Color3.fromRGB(236, 238, 246)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 154, 176)),
			})
		else
			fillGradient.Color = fillSequence(top, bottom)
		end
	end
	applyFill(fillTop, fillBottom)
	local neon = stroke(root, color, thickness, 0, "NeonStroke")

	-- the outer glow ring (behind nothing: a transparent frame with only a wide, soft stroke)
	local glow = frame("Glow", {
		Position = UDim2.fromOffset(-MX.GlowPad, -MX.GlowPad),
		Size = UDim2.new(1, 2 * MX.GlowPad, 1, 2 * MX.GlowPad),
		ZIndex = z,
		Visible = props.Glow ~= false,
	}, root)
	corner(glow, radius + MX.GlowPad)
	local glowStroke = stroke(glow, color, MX.GlowStroke, MX.GlowTransparency, "GlowStroke")

	-- the coloured floor: the neon colour fading up from the bottom of the card
	local wantFloor = props.Floor
	if wantFloor == nil then
		wantFloor = size.Y.Scale == 0 and size.Y.Offset > 0 and size.Y.Offset <= MX.FloorMaxHeight
	end
	local floorFrame = frame("Floor", {
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Position = UDim2.new(0, thickness, MX.FloorFrom, 0),
		Size = UDim2.new(1, -2 * thickness, 1 - MX.FloorFrom, -thickness),
		ZIndex = z,
		Visible = wantFloor == true,
	}, root)
	corner(floorFrame, math.max(2, radius - thickness))
	Util.Create("UIGradient", { Rotation = 90, Transparency = floorTransparency(), Parent = floorFrame })

	-- the sheen: a thin light line under the top edge
	local sheen = frame("Sheen", {
		BackgroundTransparency = MX.SheenTransparency,
		BackgroundColor3 = WHITE,
		Position = UDim2.new(0, radius, 0, 4),
		Size = UDim2.new(1, -2 * radius, 0, 2),
		ZIndex = z,
		Visible = props.Sheen ~= false,
	}, root)
	round(sheen)

	local body = frame("Body", {
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		ClipsDescendants = props.ClipsDescendants == true,
	}, root)

	local card = {
		Root = root, Body = body, Stroke = neon, Glow = glow, GlowStroke = glowStroke, Floor = floorFrame,
		Sheen = sheen, FillGradient = fillGradient, Color = color,
	}
	function card.SetColor(newColor)
		local c = colorOf(newColor, card.Color)
		card.Color = c
		neon.Color = c
		glowStroke.Color = c
		floorFrame.BackgroundColor3 = c
	end
	function card.SetGlow(on)
		glow.Visible = on and true or false
	end
	function card.SetFill(top, bottom)
		applyFill(top or TOP, bottom or BOTTOM)
	end
	root.Parent = props.Parent
	return card
end

----------------------------------------------------------------------
-- Orb + Icon
----------------------------------------------------------------------
-- A glossy disc behind an icon: light top, the colour, a darker bottom; a soft highlight ellipse in the top third.
function NeonKit.Orb(parent, color, size)
	local c = colorOf(color)
	local px = tonumber(size) or 48
	local orb = frame("Orb", {
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(px, px),
	}, parent)
	round(orb)
	Util.Create("UIGradient", {
		Name = "Gloss",
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Lighten(c, 0.45)),
			ColorSequenceKeypoint.new(0.5, c),
			ColorSequenceKeypoint.new(1, Theme.Darken(c, 0.3)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.6, 0.5),
			NumberSequenceKeypoint.new(1, 0.72),
		}),
		Parent = orb,
	})
	stroke(orb, Theme.Lighten(c, 0.2), math.max(1.5, px * 0.035), 0.55, "Rim")
	local hi = frame("Highlight", {
		BackgroundTransparency = 0.75,
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.58, 0.26),
	}, orb)
	round(hi)
	return orb
end

-- The image id for an icon (Config.Icons[id] = "rbxassetid://n"), or nil.
local function iconImage(id)
	local icons = Config.Icons
	if type(icons) == "table" and type(id) == "string" then
		local value = icons[id]
		if type(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

-- An icon: the emoji glyph of `id` (NeonKit.Glyphs[id], or `id` itself when it is not a known id) as a TextLabel of
-- `size` px, or an ImageLabel once Config.Icons[id] holds an asset id. Centred in its parent unless moved.
function NeonKit.Icon(parent, id, size)
	local px = tonumber(size) or 32
	local image = iconImage(id)
	local icon
	if image then
		icon = Util.Create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(px * 1.1, px * 1.1),
		})
	else
		local glyph = NeonKit.Glyphs[id] or tostring(id or "")
		icon = Theme.Label(glyph, "Display", {
			Size = px,
			Stroke = 1,
			Props = {
				Name = "Icon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(px * 1.25, px * 1.25),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
			},
		})
	end
	icon:SetAttribute("IconId", tostring(id or ""))
	icon.Parent = parent
	return icon
end

----------------------------------------------------------------------
-- Tile (image 21.png)
----------------------------------------------------------------------
-- props: Size (number, design px; default 84), Color (default "Blue"), Icon (an icon id or a glyph), Label (text),
--        Callback(tile), Badge (bool), Name, Position, AnchorPoint, LayoutOrder, ZIndex, Parent, Glow (default true)
function NeonKit.Tile(props)
	props = props or {}
	local s = tonumber(props.Size) or 84
	if typeof(props.Size) == "UDim2" then
		s = props.Size.X.Offset
	end
	local color = colorOf(props.Color)
	local hasLabel = type(props.Label) == "string" and props.Label ~= ""
	local card = NeonKit.Card({
		Name = props.Name or ("Tile_" .. tostring(props.Label or props.Icon or "")),
		Class = "TextButton",
		Size = UDim2.fromOffset(s, s),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Color = color,
		Corner = math.max(10, math.floor(s * 0.16 + 0.5)),
		Glow = props.Glow,
		Floor = true,
	})
	local root = card.Root
	local iconY = hasLabel and 0.4 or 0.5
	local orb = NeonKit.Orb(card.Body, color, s * MX.TileOrb)
	orb.Position = UDim2.fromScale(0.5, iconY)
	local iconPx = s * (hasLabel and MX.TileIcon or 0.56)
	local icon = NeonKit.Icon(card.Body, props.Icon or props.Label or "", iconPx)
	icon.Position = UDim2.fromScale(0.5, iconY)

	local label = nil
	if hasLabel then
		label = Theme.Label(props.Label, "Button", {
			Size = math.max(MX.TileLabelMin, math.floor(s * MX.TileLabel + 0.5)),
			Stroke = 1,
			Outline = MX.LabelStroke,
			OutlineColor = INK,
			Props = {
				Name = "Label",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.83, 0),
				Size = UDim2.new(1, 12, 0, math.floor(s * 0.3 + 0.5)),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
			},
		})
		label.Parent = card.Body
	end

	local badge = frame("Badge", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Neon.Red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(math.max(22, s * 0.28), math.max(22, s * 0.28)),
		Visible = props.Badge == true,
	}, card.Body)
	round(badge)
	stroke(badge, INK, 2, 0)
	local mark = Theme.Label("!", "Button", {
		Size = math.max(MX.TileLabelMin, math.floor(s * 0.2 + 0.5)),
		Stroke = 1,
		Outline = 1.5,
		OutlineColor = INK,
		Props = { Name = "Mark", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center },
	})
	mark.Parent = badge

	local tile = { Root = root, Card = card, Orb = orb, Icon = icon, Label = label, Badge = badge, Color = color }
	tile.Fx = attachFx(root, function(hover, press)
		card.GlowStroke.Transparency = (hover or press) and 0.45 or MX.GlowTransparency
	end)
	function tile.SetBadge(on)
		badge.Visible = on and true or false
	end
	function tile.SetColor(newColor)
		local c = colorOf(newColor, tile.Color)
		tile.Color = c
		card.SetColor(c)
		local gloss = orb:FindFirstChild("Gloss")
		if gloss then
			gloss.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Lighten(c, 0.45)),
				ColorSequenceKeypoint.new(0.5, c),
				ColorSequenceKeypoint.new(1, Theme.Darken(c, 0.3)),
			})
		end
	end
	function tile.SetLabel(text)
		if label then
			label.Text = tostring(text or "")
		end
	end
	function tile.SetIcon(id)
		local pos = icon.Position
		icon:Destroy()
		icon = NeonKit.Icon(card.Body, id, iconPx)
		icon.Position = pos
		tile.Icon = icon
	end
	if props.Callback then
		root.Activated:Connect(function()
			if not isDisabled(root) then
				props.Callback(tile)
			end
		end)
	end
	root.Parent = props.Parent
	return tile
end

----------------------------------------------------------------------
-- Pill (currency / status)
----------------------------------------------------------------------
-- props: Text, Glyph (coin glyph; default none), Color (default Blue), Size (UDim2 | number width; default 200x40),
--        Height (when Size is a number; default 40), TextSize (default 0.62 x height), Font role (default "Display"),
--        Name, Position, AnchorPoint, LayoutOrder, ZIndex, Parent, Glow (default false)
function NeonKit.Pill(props)
	props = props or {}
	local color = colorOf(props.Color)
	local h = tonumber(props.Height) or 40
	local size = props.Size
	if type(size) == "number" then
		size = UDim2.fromOffset(size, h)
	elseif typeof(size) == "UDim2" then
		h = size.Y.Offset > 0 and size.Y.Offset or h
	else
		size = UDim2.fromOffset(200, h)
	end
	local hasCoin = type(props.Glyph) == "string" and props.Glyph ~= ""
	local root = frame(props.Name or "NeonPill", {
		Size = size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	local coinD = math.floor(h * 1.12 + 0.5)
	local left = hasCoin and math.floor(coinD * 0.42) or 0
	local card = NeonKit.Card({
		Name = "Card",
		Position = UDim2.fromOffset(left, 0),
		Size = UDim2.new(1, -left, 1, 0),
		Color = color,
		Corner = math.floor(h / 2),
		Glow = props.Glow == true,
		Floor = true,
		Sheen = true,
		ZIndex = props.ZIndex,
		Parent = root,
	})
	local coin, glyph = nil, nil
	if hasCoin then
		coin = frame("Coin", {
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(coinD, coinD),
			ZIndex = props.ZIndex or 1,
		}, root)
		round(coin)
		Util.Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Lighten(color, 0.5)),
				ColorSequenceKeypoint.new(0.55, color),
				ColorSequenceKeypoint.new(1, Theme.Darken(color, 0.35)),
			}),
			Parent = coin,
		})
		stroke(coin, INK, 2.5, 0)
		local shine = frame("Shine", {
			BackgroundTransparency = 0.6,
			BackgroundColor3 = WHITE,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.1),
			Size = UDim2.fromScale(0.56, 0.24),
		}, coin)
		round(shine)
		glyph = Theme.Label(props.Glyph, "Display", {
			Size = math.floor(coinD * 0.56 + 0.5),
			Stroke = 1,
			Outline = 2,
			OutlineColor = Theme.Darken(color, 0.65),
			Props = { Name = "Glyph", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center },
		})
		glyph.Parent = coin
	end
	local textLeft = hasCoin and (coinD - left + 6) or math.floor(h * 0.45)
	local text = Theme.Label(tostring(props.Text or ""), props.Font or "Display", {
		Size = tonumber(props.TextSize) or math.floor(h * 0.62 + 0.5),
		Stroke = 1,
		Outline = 2.5,
		OutlineColor = INK,
		Props = {
			Name = "Text",
			Position = UDim2.fromOffset(textLeft, 0),
			Size = UDim2.new(1, -(textLeft + math.floor(h * 0.35)), 1, -2),
			TextXAlignment = hasCoin and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
		},
	})
	text.Parent = card.Body

	local pill = { Root = root, Card = card, Coin = coin, Glyph = glyph, Text = text, Color = color }
	function pill.SetText(value)
		text.Text = tostring(value or "")
	end
	function pill.SetColor(newColor)
		local c = colorOf(newColor, pill.Color)
		pill.Color = c
		card.SetColor(c)
	end
	root.Parent = props.Parent
	return pill
end

----------------------------------------------------------------------
-- Button
----------------------------------------------------------------------
-- props: Text, Color (default Green), Variant ("Primary" default: a filled dark-colour face + glow | "Outline": the
--        navy card face with a neon border), Size (default 180x52), TextSize (default 22), Callback(button), Name,
--        Position, AnchorPoint, LayoutOrder, ZIndex, Parent
-- State: button:SetAttribute("Disabled", true) (or Active = false) greys it out and ignores clicks;
--        button:SetAttribute("Color", "Red") re-colours it.
function NeonKit.Button(props)
	props = props or {}
	local st = { Color = colorOf(props.Color, Theme.Neon.Green), Variant = (props.Variant == "Outline") and "Outline" or "Primary" }
	local size = toUDim2(props.Size, UDim2.fromOffset(180, 52))
	local h = size.Y.Scale == 0 and size.Y.Offset or 52
	local card = NeonKit.Card({
		Name = props.Name or ("NeonButton_" .. tostring(props.Text or "")),
		Class = "TextButton",
		Size = size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Color = st.Color,
		Corner = math.min(16, math.floor(h * 0.32 + 0.5)),
		Glow = st.Variant == "Primary",
		Floor = st.Variant == "Outline",
	})
	local button = card.Root
	button.Active = true
	button.Text = tostring(props.Text or "")
	button.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Style(button, "Button", { Size = props.TextSize or 22, Stroke = 1, Outline = 2, OutlineColor = INK })
	Util.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = button })
	local outline = button:FindFirstChild("TextOutline")
	local fx

	local function paint()
		local disabled = isDisabled(button)
		local c = disabled and Theme.Neon.Grey or st.Color
		local hot = fx and (fx.Hover or fx.Press)
		card.SetColor(c)
		card.SetGlow(st.Variant == "Primary" and not disabled)
		if st.Variant == "Primary" then
			local top = Theme.Darken(c, disabled and 0.72 or (hot and 0.42 or 0.5))
			card.SetFill(top, Theme.Darken(c, 0.82))
		else
			card.SetFill(hot and Theme.Lighten(TOP, 0.08) or TOP, BOTTOM)
		end
		button.TextColor3 = disabled and Color3.fromRGB(176, 184, 206) or WHITE
		if outline then
			outline.Transparency = disabled and 0.4 or 0
		end
	end
	fx = attachFx(button, paint)
	paint()
	button:GetAttributeChangedSignal("Disabled"):Connect(paint)
	button:GetPropertyChangedSignal("Active"):Connect(paint)
	button:GetAttributeChangedSignal("Color"):Connect(function()
		local value = button:GetAttribute("Color")
		if type(value) == "string" then
			st.Color = colorOf(value, st.Color)
			paint()
		end
	end)
	if props.Callback then
		button.Activated:Connect(function()
			if not isDisabled(button) then
				props.Callback(button)
			end
		end)
	end
	button.Parent = props.Parent
	return button
end

----------------------------------------------------------------------
-- The window rule: SideRect + Dock
----------------------------------------------------------------------
local function isTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function viewport()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if vp.X < 2 or vp.Y < 2 then
		return Vector2.new(1920, 1080)
	end
	return vp
end

-- The window rule (contract 6.6, the prototype's side_rect). Returns screen pixels (top bar included):
--   x, y, w, h   the window's box on screen;  scale  the UIScale to put on a window designed at designW x designH;
--   mode         "Side" (landscape: docked right, <= 44% of the width, never left of 0.56 W - margin, vertically
--                centred below the top bar) | "Sheet" (portrait: a bottom sheet, scale 0.8, full width minus the
--                margins, <= 56% of the height: the top 44% where the character stands stays clear)
-- prefW / prefH: the preferred window size in design px; minW / minH (optional): the smallest design size the
-- content accepts (the scale shrinks instead, down to the phone scale).
-- opts (optional, tests): { Width, Height, Touch } override the screen.
function NeonKit.SideRect(prefW, prefH, minW, minH, opts)
	opts = opts or {}
	local vp = viewport()
	local W = tonumber(opts.Width) or vp.X
	local H = tonumber(opts.Height) or vp.Y
	local touch = opts.Touch
	if touch == nil then
		touch = isTouch()
	end
	prefW = tonumber(prefW) or 640
	prefH = tonumber(prefH) or 800
	local f = Theme.ScreenFactor(H)
	local m = MX.Margin * f
	local inset = MX.Inset
	local rect
	if W >= H then
		local maxW, maxH = W * MX.SideMaxW, H - inset - 2 * m
		local scale = f
		if prefW * scale > maxW then
			if touch then
				scale = MX.MinScaleTouch
			else
				scale = math.max(MX.MinScaleDesktop, maxW / prefW)
			end
		end
		local w = math.min(prefW, maxW / scale)
		local h = math.min(prefH, maxH / scale)
		if minW and w < minW then
			w = minW
		end
		if minH and h < minH then
			h = minH
			scale = math.min(scale, maxH / minH)
		end
		rect = {
			x = W - m - w * scale,
			y = inset + m + (maxH - h * scale) / 2,
			w = w * scale,
			h = h * scale,
			scale = scale,
			mode = "Side",
		}
	else
		-- the sheet (with its bottom margin) stays inside the lower 56%: its top edge is never above 0.44 H
		local scale = MX.SheetScale
		local room = H * MX.SheetMaxH - m
		local w = (W - 2 * m) / scale
		local h = math.min(prefH, room / scale)
		if minH and h < minH then
			h = minH
			scale = math.min(scale, room / minH)
			w = (W - 2 * m) / scale
		end
		rect = {
			x = m,
			y = H - m - h * scale,
			w = w * scale,
			h = h * scale,
			scale = scale,
			mode = "Sheet",
		}
	end
	rect.designW = rect.w / rect.scale
	rect.designH = rect.h / rect.scale
	rect.margin = m
	return rect
end

local function guiInsetOf(holder)
	local gui = holder and holder:FindFirstAncestorOfClass("ScreenGui")
	if gui and gui.IgnoreGuiInset then
		return 0
	end
	local inset = MX.Inset
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	return inset
end

-- The optional client/MouseLock module (nil on the server or when missing): a docked window frees the cursor
local mouseLock = nil
local mouseLockWatched = setmetatable({}, { __mode = "k" }) -- [holder] = true (one watcher per holder)
local function getMouseLock()
	if mouseLock == nil then
		mouseLock = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("MouseLock")
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" and type(mod.WatchVisible) == "function" then
				mouseLock = mod
			end
		end
	end
	return mouseLock or nil
end

-- Docks `holder` (a window root designed in px, AnchorPoint set to 0,0) by the window rule and keeps it docked when
-- the screen changes size. While the holder is shown (Visible in an Enabled ScreenGui) it is a MouseLock hold: the
-- cursor is free; hiding / removing / destroying the holder releases it (independent of Disconnect). `uiScale` (optional) is the UIScale to drive; without one a UIScale "DockScale" is added
-- (or reused) on the holder. Returns { Rect, Refresh(), Disconnect() }; Rect is the last SideRect.
-- The holder's Position is in ITS gui's area: a ScreenGui with IgnoreGuiInset = false starts below the top bar.
function NeonKit.Dock(holder, uiScale, prefW, prefH, minW, minH)
	local dock = { Rect = nil }
	if not holder then
		return dock
	end
	if not (uiScale and uiScale:IsA("UIScale")) then
		uiScale = holder:FindFirstChild("DockScale")
		if not (uiScale and uiScale:IsA("UIScale")) then
			uiScale = Util.Create("UIScale", { Name = "DockScale", Scale = 1, Parent = holder })
		end
	end
	local conns = {}
	function dock.Refresh()
		if not holder.Parent then
			return
		end
		local r = NeonKit.SideRect(prefW, prefH, minW, minH)
		dock.Rect = r
		holder.AnchorPoint = Vector2.new(0, 0)
		holder.Position = UDim2.fromOffset(math.floor(r.x + 0.5), math.floor(r.y - guiInsetOf(holder) + 0.5))
		holder.Size = UDim2.fromOffset(math.floor(r.designW + 0.5), math.floor(r.designH + 0.5))
		uiScale.Scale = r.scale
		holder:SetAttribute("DockMode", r.mode)
		holder:SetAttribute("DockLeft", math.floor(r.x + 0.5))
	end
	local function bindCamera()
		if conns.Camera then
			conns.Camera:Disconnect()
			conns.Camera = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			conns.Camera = camera:GetPropertyChangedSignal("ViewportSize"):Connect(dock.Refresh)
		end
		dock.Refresh()
	end
	conns.Watch = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	conns.Gone = holder.Destroying:Connect(function()
		dock.Disconnect()
	end)
	function dock.Disconnect()
		for _, key in ipairs({ "Camera", "Watch", "Gone" }) do
			if conns[key] then
				conns[key]:Disconnect()
				conns[key] = nil
			end
		end
	end
	bindCamera()
	local ml = getMouseLock()
	if ml and not mouseLockWatched[holder] then
		mouseLockWatched[holder] = true
		pcall(ml.WatchVisible, "Dock:" .. holder.Name, holder)
	end
	return dock
end

-- The local player's PlayerGui (nil on the server); a convenience for window owners.
function NeonKit.PlayerGui()
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui") or nil
end

return NeonKit
