-- GemIcon (client UI; lobby-shop Task 15, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.7 "How gems look",
-- pitch gemlook A): every gem in the GUI drawn as a cut gem out of frames (no image ids, so nothing to upload).
--
--   GemIcon.New(parent, size, opts) -> Frame "GemIcon" (size x size design px; opts = { Shine = true, ZIndex, Name })
--     attributes Simple (true under 28 px) and Shine (true when the icon is registered with the shine driver)
--   GemIcon.Pile(parent, size, count) -> Frame "GemPile" (count 1, 2, 3, 4 or 6 GemIcons at the pitch's PILE offsets; any
--     other count takes the nearest smaller pile)
--   GemIcon.Amount(parent, n, opts) -> Frame "GemAmount" > GemIcon + TextLabel "Value" (n: a number -> "1,250", or a ready
--     string such as "12.3M"; opts = { Size (the gem, default TextSize x 1.1), TextSize (22), Color (white), ZIndex })
--     sized to the gem + the measured number (attribute Width)
--   GemIcon.SetAmount(frame, n, opts) writes the number (n nil keeps it) and re-measures; opts restyles (TextSize / Size /
--     Color; the gem is rebuilt when its size changes)
--   GemIcon.Driver() -> { Count = n, Running = bool }   the live icons the one shine Heartbeat drives (dead ones dropped)
--
-- The look (spec 5.7): one 45-degree diamond ("Body", a square turned 45 degrees) inside an unrotated clipping frame
-- ("Clip") that cuts its top tip flat: the table, the crown and the pavilion of a cut gem. Three cyan-blue tones (light
-- Theme.Currency.Gems.Glow rgb(186,236,255), mid Theme.Currency.Gems.Color rgb(84,196,246), dark rgb(40,120,200)) through
-- the Body's UIGradient "Tone" and an inner facet diamond ("Facet"), a navy outline (UIStroke "Outline" rgb(11,16,48),
-- size / 16 thick) with a navy bar on the cut ("Cut"), and a small white four-point star on the upper left ("Glint";
-- review round 1: not "Star", a palette key the Blender kit bakes into evolved pets, which a lookup by name would unbake).
-- Under 28 px the simple form: the silhouette, two tones (light crown, mid pavilion), a navy outline of at least 2 px
-- snapped to whole pixels, no facet and no star (at 19-24 px those blur into each other).
-- Shine (Review Focus 5): a thin white bar ("ShineBar", a second diamond with a moving UIGradient band) sweeps across the
-- gem every 3.5 s for 0.6 s, only for icons of at least 20 px made while the graphics setting is High, and only while it
-- stays High. Every icon shares ONE Heartbeat driver: a weak-keyed registry; an icon out of the tree (destroyed, or its
-- window rebuilt) drops out on the next step, and the Heartbeat disconnects when nothing is left to shine.
-- Plain Lua 5.1-compatible syntax only. Text goes through Theme roles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local GemIcon = {}

local GEMS = (Theme.Currency and Theme.Currency.Gems) or {}
local K = {
	LIGHT = GEMS.Glow or Color3.fromRGB(186, 236, 255),
	MID = GEMS.Color or Color3.fromRGB(84, 196, 246),
	DARK = Color3.fromRGB(40, 120, 200),
	INK = Color3.fromRGB(11, 16, 48),
	WHITE = Color3.new(1, 1, 1),
	SIMPLE_BELOW = 28, -- design px: the simple form below this
	SHINE_MIN = 20, -- design px: the shine from this size up
	PERIOD = 3.5, -- seconds between two sweeps of one icon
	SWEEP = 0.6, -- seconds one sweep takes
	PHASE_STEP = 0.83, -- the next icon's sweep starts this much later (icons side by side do not flash together)
	HALF = 0.45, -- the diamond's half diagonal, at most this x size
	CUT = 0.5, -- the cut takes this share of the half diagonal off the top tip (the table is half the girdle)
	AMOUNT_GAP = 0.22, -- the gap between the gem and the number, x the gem size
	-- the pitch's PILE (page.html): { x, y, size } as shares of the pile box, back to front
	PILE = {
		[1] = { { 0.5, 0.55, 0.8 } },
		[2] = { { 0.36, 0.6, 0.62 }, { 0.64, 0.5, 0.7 } },
		[3] = { { 0.3, 0.64, 0.6 }, { 0.7, 0.64, 0.6 }, { 0.5, 0.4, 0.7 } },
		[4] = { { 0.25, 0.66, 0.52 }, { 0.75, 0.66, 0.52 }, { 0.5, 0.64, 0.58 }, { 0.5, 0.36, 0.62 } },
		[6] = { { 0.2, 0.72, 0.46 }, { 0.5, 0.74, 0.5 }, { 0.8, 0.72, 0.46 }, { 0.34, 0.5, 0.5 }, { 0.66, 0.5, 0.5 }, { 0.5, 0.27, 0.56 } },
	},
}
GemIcon.Metrics = K

-- the shine driver's state: Icons[icon] = { Bar, Sweep, Phase, On } (weak keys); GQ = client/GraphicsQuality or false
local D = { T = 0, NextPhase = 0, Conn = nil, GQ = nil }
D.Icons = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
-- the graphics setting (client/GraphicsQuality's Effective(), asked on every call: the settings window changes it);
-- High when the module is not there (the offline renderer's gallery)
local function gfxHigh()
	if D.GQ == nil then
		D.GQ = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("GraphicsQuality")
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				D.GQ = mod
			end
		end
	end
	if not D.GQ then
		return true
	end
	local ok, mode = pcall(D.GQ.Effective)
	return not ok or mode ~= "Low"
end

local function box(name, props, parent)
	props.Name = name
	props.BorderSizePixel = 0
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	props.Parent = parent
	return Util.Create("Frame", props)
end

local function textWidth(text, size, font)
	local ok, v = pcall(function()
		return Theme.Measure(text, font, size, 100000)
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return v.X
	end
	return #text * size * 0.6
end

----------------------------------------------------------------------
-- the shine driver
----------------------------------------------------------------------
local function prune()
	local n = 0
	for icon in pairs(D.Icons) do
		if icon.Parent == nil or not icon:IsDescendantOf(game) then
			D.Icons[icon] = nil
		else
			n = n + 1
		end
	end
	return n
end

local function step(dt)
	D.T = D.T + (tonumber(dt) or 0)
	local high = gfxHigh()
	local alive = 0
	for icon, s in pairs(D.Icons) do
		if icon.Parent == nil or not icon:IsDescendantOf(game) then
			D.Icons[icon] = nil
		else
			alive = alive + 1
			local p = (D.T + s.Phase) % K.PERIOD
			local on = high and p < K.SWEEP
			if on then
				s.Sweep.Offset = Vector2.new(-1 + 2 * p / K.SWEEP, 0)
			end
			if on ~= s.On then
				s.On = on
				s.Bar.Visible = on
			end
		end
	end
	if alive == 0 and D.Conn then
		D.Conn:Disconnect()
		D.Conn = nil
	end
end

local function register(icon, bar, sweep)
	D.Icons[icon] = { Bar = bar, Sweep = sweep, Phase = D.NextPhase, On = false }
	D.NextPhase = (D.NextPhase + K.PHASE_STEP) % K.PERIOD
	if not D.Conn then
		D.Conn = RunService.Heartbeat:Connect(step)
	end
end

function GemIcon.Driver()
	local n = prune()
	if n == 0 and D.Conn then
		D.Conn:Disconnect()
		D.Conn = nil
	end
	return { Count = n, Running = D.Conn ~= nil }
end

----------------------------------------------------------------------
-- New
----------------------------------------------------------------------
-- a square turned 45 degrees: half diagonal d, centred at (x, y) of its parent
local function diamond(name, parent, x, y, d, z, color)
	local side = d * math.sqrt(2)
	return box(name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(side, side),
		Rotation = 45,
		BackgroundTransparency = 0,
		BackgroundColor3 = color or K.WHITE,
		ZIndex = z,
	}, parent)
end

-- a gradient along the SCREEN's vertical on a frame turned 45 degrees (the gradient turns with its frame)
local function screenGradient(name, parent, keys, transparency)
	return Util.Create("UIGradient", {
		Name = name,
		Rotation = 45,
		Color = ColorSequence.new(keys),
		Transparency = transparency,
		Parent = parent,
	})
end

function GemIcon.New(parent, size, opts)
	opts = opts or {}
	local s = math.max(8, tonumber(size) or 32)
	local simple = s < K.SIMPLE_BELOW
	local z = tonumber(opts.ZIndex) or 1
	-- the outline: size / 16; the simple form at least 2 px and whole
	local th = s / 16
	if simple then
		th = math.max(2, math.floor(th + 0.5))
	end
	-- the diamond fits the box with its outline (a mitred tip reaches th x sqrt 2 past the edge)
	local d = math.min(K.HALF * s, s / 2 - 1.42 * th - 0.5)
	local c = K.CUT * d
	local cx = s / 2
	local cy = s / 2 - (c + 0.414 * th) / 2 -- the visible gem (cut bar to tip) centred in the box
	local cutY = cy - d + c

	local root = box(opts.Name or "GemIcon", { Size = UDim2.fromOffset(s, s), ZIndex = z }, nil)
	root:SetAttribute("Simple", simple)
	local clip = box("Clip", {
		Position = UDim2.fromOffset(0, cutY),
		Size = UDim2.fromOffset(s, s - cutY + 2 * th),
		ClipsDescendants = true,
		ZIndex = z,
	}, root)
	local body = diamond("Body", clip, cx, cy - cutY, d, z)
	if simple then
		screenGradient("Tone", body, {
			ColorSequenceKeypoint.new(0, K.LIGHT),
			ColorSequenceKeypoint.new(0.499, K.LIGHT),
			ColorSequenceKeypoint.new(0.501, K.MID),
			ColorSequenceKeypoint.new(1, K.MID),
		})
	else
		screenGradient("Tone", body, {
			ColorSequenceKeypoint.new(0, K.LIGHT),
			ColorSequenceKeypoint.new(0.499, K.LIGHT:Lerp(K.MID, 0.45)),
			ColorSequenceKeypoint.new(0.501, K.MID),
			ColorSequenceKeypoint.new(1, K.DARK),
		})
	end
	Util.Create("UIStroke", {
		Name = "Outline",
		Color = K.INK,
		Thickness = th,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
		Parent = body,
	})
	if not simple then
		-- the inner facet: a diamond of half the size on the girdle, its top tip on the table's edge
		local facet = diamond("Facet", clip, cx, cy - cutY, d * 0.5, z + 1, K.WHITE)
		facet.BackgroundTransparency = 0.25
		Util.Create("UIGradient", {
			Name = "FacetTone",
			Rotation = 0,
			Color = ColorSequence.new(K.LIGHT, K.MID:Lerp(K.DARK, 0.35)),
			Parent = facet,
		})
	end
	-- the navy bar on the cut (above the clip: the outline's own top edge was cut away with the tip)
	local barW = 2 * (c + 1.2 * th)
	box("Cut", {
		Position = UDim2.fromOffset(cx - barW / 2, cutY - th),
		Size = UDim2.fromOffset(barW, th),
		BackgroundTransparency = 0,
		BackgroundColor3 = K.INK,
		ZIndex = z + 3,
	}, root)
	if not simple then
		-- the white four-point star on the upper left (in the crown)
		local star = box("Glint", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx - 0.4 * d, cutY + 0.28 * d),
			Size = UDim2.fromOffset(0.22 * s, 0.22 * s),
			ZIndex = z + 4,
		}, root)
		for i, dims in ipairs({ { 0.2, 1 }, { 1, 0.2 } }) do
			local arm = box("Arm" .. i, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(dims[1], dims[2]),
				BackgroundTransparency = 0,
				BackgroundColor3 = K.WHITE,
				ZIndex = z + 4,
			}, star)
			Util.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = arm })
		end
	end
	local shine = opts.Shine ~= false and s >= K.SHINE_MIN and gfxHigh()
	if shine then
		local bar = diamond("ShineBar", clip, cx, cy - cutY, d, z + 2, K.WHITE)
		bar.Visible = false
		local sweep = Util.Create("UIGradient", {
			Name = "Sweep",
			Rotation = 0,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(0.58, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Offset = Vector2.new(-1, 0),
			Parent = bar,
		})
		register(root, bar, sweep)
	end
	root:SetAttribute("Shine", shine == true)
	root.Parent = parent
	return root
end

----------------------------------------------------------------------
-- Pile
----------------------------------------------------------------------
function GemIcon.Pile(parent, size, count)
	local s = math.max(8, tonumber(size) or 96)
	local n = math.max(1, math.floor(tonumber(count) or 1))
	while not K.PILE[n] do
		n = n - 1
	end
	local pile = box("GemPile", { Size = UDim2.fromOffset(s, s) }, nil)
	pile:SetAttribute("Count", n)
	for i, p in ipairs(K.PILE[n]) do
		local g = p[3] * s
		local icon = GemIcon.New(pile, g, { ZIndex = 1 + i })
		icon.Position = UDim2.fromOffset(p[1] * s - g / 2, p[2] * s - g / 2)
	end
	pile.Parent = parent
	return pile
end

----------------------------------------------------------------------
-- Amount
----------------------------------------------------------------------
local function amountText(n)
	if type(n) == "string" then
		return n
	end
	return Util.Commas(math.max(0, math.floor(tonumber(n) or 0)))
end

-- lays the gem and the number out side by side and sizes the frame to them
local function measure(frame)
	local icon = frame:FindFirstChild("GemIcon")
	local value = frame:FindFirstChild("Value")
	if not (icon and value) then
		return
	end
	local g = icon.Size.X.Offset
	local ts = value.TextSize
	local gap = math.floor(g * K.AMOUNT_GAP + 0.5)
	local w = math.ceil(textWidth(value.Text, ts, Theme.FontOf(value))) + 2
	local h = math.max(g, ts + 4)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 0, 0.5, 0)
	value.Position = UDim2.new(0, g + gap, 0, 0)
	value.Size = UDim2.new(0, w, 1, 0)
	frame.Size = UDim2.fromOffset(g + gap + w, h)
	frame:SetAttribute("Width", g + gap + w)
end

function GemIcon.Amount(parent, n, opts)
	opts = opts or {}
	local ts = tonumber(opts.TextSize) or 22
	local g = math.floor((tonumber(opts.Size) or ts * 1.1) + 0.5)
	local z = tonumber(opts.ZIndex) or 1
	local frame = box("GemAmount", { Size = UDim2.fromOffset(g, g), ZIndex = z }, nil)
	GemIcon.New(frame, g, { ZIndex = z + 1 })
	local value = Theme.Label(amountText(n), "Display", {
		Size = ts,
		Color = opts.Color or K.WHITE,
		Props = {
			Name = "Value",
			ZIndex = z + 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
		},
	})
	value.Parent = frame
	measure(frame)
	frame.Parent = parent
	return frame
end

function GemIcon.SetAmount(frame, n, opts)
	if typeof(frame) ~= "Instance" then
		return
	end
	local value = frame:FindFirstChild("Value")
	local icon = frame:FindFirstChild("GemIcon")
	if not value then
		return
	end
	if n ~= nil then
		value.Text = amountText(n)
	end
	if type(opts) == "table" then
		if tonumber(opts.TextSize) then
			value.TextSize = tonumber(opts.TextSize)
		end
		if opts.Color then
			value.TextColor3 = opts.Color
		end
		local g = math.floor((tonumber(opts.Size) or value.TextSize * 1.1) + 0.5)
		if not icon or icon.Size.X.Offset ~= g then
			local z = icon and icon.ZIndex or value.ZIndex
			if icon then
				icon:Destroy()
			end
			GemIcon.New(frame, g, { ZIndex = z })
		end
	end
	measure(frame)
end

return GemIcon
