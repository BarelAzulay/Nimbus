-- EggArt (client UI; lobby-shop Tasks 20 / 26, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.5 "Painted eggs"
-- and 5.6 "How eggs look"): the seven eggs drawn from frames (no image ids, nothing to upload), painted with the same
-- motifs as the Blender shelf eggs (blender/kit/props/lobby_shop.py prop lobby_egg), so the shelf, the Shop and the
-- cutscene show one egg per rarity. One shape for all: an oval body (UICorner 0.5, 0.8 x as wide as it is tall), a
-- top-to-bottom tone gradient, a navy outline and a white highlight on the upper left.
--
--   EggArt.New(parent, rarity, size, opts) -> Frame "Egg_<Rarity>" (size = the egg's height in design px; width
--     floor(0.8 x size + 0.5)); opts = { Form = "Auto" | "Simple" | "Medium" | "Full", Vfx = bool, ZIndex, Name,
--     Rim = false (no rim light), Budget = n (a lower instance cap: the strip's cells pass 9, spec 16.4's 14 per cell),
--     Still = true (a Full egg whose sheen waits for SetVfx(egg, true): the Shop's hero egg) }
--     attributes Rarity, Form (Auto: Simple under 48 px, Medium 48-140, Full over 140), Size, Motifs (the paint kinds
--     drawn, comma-separated) and Vfx
--   EggArt.SetRarity(egg, rarity)  re-paints in place (tone, paint, light layer, VFX); the name follows a default name
--   EggArt.SetVfx(egg, on)  on (High graphics only): a Full egg's sheen plays and, from Rare up, the rarity VFX are added;
--     off (or Low): the VFX removed and the sheen parked, so the egg is still (nothing plays)
--   EggArt.Resize(egg, size)  the size, the outline and every stroke inside (each stroke keeps its share of the size)
--   EggArt.Halves(parent, rarity, size) -> top, bottom   two CanvasGroups "HalfTop" / "HalfBottom" (the egg's width x half
--     its height, at y 0 and y size / 2 in the parent), each drawing the whole painted egg (no sheen, no shadow, no
--     tween: they fly apart in 0.35 s) clipped to its half
--   EggArt.Glow(rarity)  -> the glow strength behind the egg: 0 / 0 / 0.22 / 0.34 / 0.58 / 0.66 / 0.78 (Common .. Secret)
--   EggArt.Tones(rarity) -> top, bottom Color3: the rarity colour (Config.Rarities) 38% toward white / 28% toward black;
--     Secret rgb(74,68,104) / rgb(18,16,28) (its colour is near black)
--   EggArt.Paint(rarity) -> { { Kind, Count }, ... }   spec 16.5's motif list in order (Secret lists its stars first:
--     the Simple rule keeps them; its two rune lines ride in the shell's tone in every form)
--
-- The layers (instance caps, spec 16.5: Simple <= 8, Medium <= 14, Full <= 28): every form has the body Frame, its
-- UICorner, the UIGradient "Tone" (the paint's bands are hard-edged keypoints in it: no instance, <= 20 keypoints), the
-- UIStroke "Outline" (rgb(11,16,48), size / 20, at least 2 px, whole) and the "Highlight" with its UICorner (6). Medium
-- adds the "Rim" light (an inset capsule with a transparency gradient: 3); Full the Rim, the "Specular" dot (2), the
-- contact "Shadow" under the egg (2), the "Sheen" (a capsule whose UIGradient sweeps every ~4 s on High: 3) and, from
-- Epic up, the "Light" layer (soft glow rows behind the Neon details: 3). The paint fills what is left, in priority
-- order: Simple the first motif, Medium the first two as they fit, Full every motif (no frame pokes out of the outline).
-- VFX (Rare and up, High only; <= 8 instances, <= 3 tweens): a "Halo" ring in the glow colour round every one; Epic
-- the Light layer flickers every ~3 s and the star row twinkles; Legendary's soft "Rays" turn behind it and the gems
-- glint; Mythic's ribbon drifts; Secret pulses, its two stars twinkle and a dark violet "Aura" ring stands round it.
-- The drifting sparkles are not the egg's: they come from a HatchFx pool (client/UI/HatchFx). Every tween stops when the
-- egg is destroyed. Plain Lua 5.1-compatible syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local EggArt = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local K = {
	INK = rgb(11, 16, 48),
	WHITE = Color3.new(1, 1, 1),
	BLACK = Color3.new(0, 0, 0),
	TO_WHITE = 0.38, -- the top tone: the rarity colour this far toward white
	TO_BLACK = 0.28, -- the bottom tone: this far toward black
	SECRET_TOP = rgb(74, 68, 104),
	SECRET_BOTTOM = rgb(18, 16, 28),
	GLOW = { Common = 0, Uncommon = 0, Rare = 0.22, Epic = 0.34, Legendary = 0.58, Mythic = 0.66, Secret = 0.78 },
	SIMPLE_BELOW = 48, -- design px: Simple under this
	FULL_ABOVE = 140, -- design px: Full over this
	WIDTH = 0.8, -- the body is this much as wide as it is tall
	-- the highlight: an oval on the upper left (shares of the body)
	HL_POS = { 0.2, 0.12 },
	HL_SIZE = { 0.24, 0.2 },
	HL_ALPHA = 0.35,
	CAP = { Simple = 8, Medium = 14, Full = 28 },
	FORM_CHAR = { Simple = "S", Medium = "M", Full = "F" },
	EPS = 0.002, -- a hard band edge in the tone gradient
	BAND_SHADE = 0.22, -- a band's colour this far toward black at the egg's foot (shaded by height)
	SHEEN = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 2.8), -- 4.0 s a sweep
	HALO_K = 0.085, -- the halo ring's thickness, a share of the egg's height
	SECRET_GLOW = rgb(138, 92, 255), -- Secret's glow is violet (its colour is near black)
	AURA = rgb(52, 24, 110),
	SHADOW = rgb(11, 16, 48),
}
EggArt.Metrics = K

-- the instance cost of each paint shape (a ringed dot adds its UIStroke)
local COST = { dot = 2, dia = 1, bar = 1, row = 2, band = 2, ring = 3, ticks = 2, plus = 2 }

----------------------------------------------------------------------------------------------------
-- the designs (spec 16.5's table): Kinds = { Kind, Count } in order; Bands[kind] = tone bands { y0, y1, colour } (hard)
-- or { t, colour } (a soft point), Bands.Base in every form; Els = { kind, forms, shape, ... } in priority order (x a
-- share of the egg's width, y of its height, sizes in egg heights); Light = the glow rows from Epic up
----------------------------------------------------------------------------------------------------
local SPOT, CREAM, LIME, NAVY, GOLD = rgb(116, 124, 138), rgb(250, 240, 200), rgb(186, 240, 100), rgb(20, 36, 92), rgb(255, 206, 72)
local D = {}
D.Common = {
	Kinds = { { "Spots", 4 }, { "Dots", 2 }, { "Shine", 1 } },
	Bands = {},
	Els = {
		{ "Spots", "S", "dot", 0.60, 0.56, 0.30, SPOT },
		{ "Spots", "MF", "dot", 0.64, 0.40, 0.26, SPOT },
		{ "Dots", "MF", "dot", 0.52, 0.565, 0.075, K.WHITE, 0.05 },
		{ "Spots", "F", "dot", 0.33, 0.66, 0.19, SPOT },
		{ "Spots", "F", "dot", 0.74, 0.76, 0.15, SPOT },
		{ "Spots", "F", "dot", 0.50, 0.90, 0.11, SPOT },
		{ "Dots", "F", "dot", 0.24, 0.45, 0.06, K.WHITE, 0.05 },
	},
}
D.Uncommon = {
	Kinds = { { "ZigzagBand", 1 }, { "Spots", 3 }, { "Dots", 1 } },
	Bands = { ZigzagBand = { { 0.395, 0.625, rgb(40, 110, 62) } } }, -- the deep green belt the zigzag runs on
	Els = {
		{ "ZigzagBand", "SM", "bar", 0.035, 0.445, 0.5, 0.575, 0.075, CREAM, 0, 1 },
		{ "ZigzagBand", "SM", "bar", 0.5, 0.575, 0.965, 0.445, 0.075, CREAM, 1, 0 },
		{ "ZigzagBand", "F", "bar", 0.035, 0.575, 0.25, 0.445, 0.075, CREAM, 0, 1 },
		{ "ZigzagBand", "F", "bar", 0.25, 0.445, 0.5, 0.575, 0.075, CREAM, 1, 1 },
		{ "ZigzagBand", "F", "bar", 0.5, 0.575, 0.75, 0.445, 0.075, CREAM, 1, 1 },
		{ "ZigzagBand", "F", "bar", 0.75, 0.445, 0.965, 0.575, 0.075, CREAM, 1, 0 },
		{ "Spots", "MF", "dot", 0.5, 0.468, 0.075, LIME },
		{ "Spots", "F", "dot", 0.25, 0.555, 0.075, LIME },
		{ "Spots", "F", "dot", 0.75, 0.555, 0.075, LIME },
		{ "Dots", "F", "dot", 0.64, 0.24, 0.065, K.WHITE, 0.05 },
	},
}
D.Rare = {
	Kinds = { { "Bands", 2 }, { "Dots", 4 } },
	Bands = {
		Bands = {
			{ 0.306, 0.318, NAVY }, { 0.318, 0.402, rgb(246, 250, 255) }, { 0.402, 0.414, NAVY },
			{ 0.618, 0.630, NAVY }, { 0.630, 0.714, rgb(246, 250, 255) }, { 0.714, 0.726, NAVY },
		},
	},
	Els = {
		{ "Dots", "MF", "dot", 0.5, 0.516, 0.10, K.WHITE, 0, NAVY, 0.012 },
		{ "Dots", "F", "dot", 0.2, 0.516, 0.10, K.WHITE, 0, NAVY, 0.012 },
		{ "Dots", "F", "dot", 0.8, 0.516, 0.10, K.WHITE, 0, NAVY, 0.012 },
		{ "Dots", "F", "dot", 0.62, 0.20, 0.06, K.WHITE, 0.45 },
	},
}
D.Epic = {
	Kinds = { { "StarBand", 1 }, { "Trim", 2 }, { "Stars", 3 }, { "Dots", 2 } },
	Bands = {
		StarBand = { { 0.333, 0.600, rgb(70, 32, 128) } },
		Trim = { { 0.267, 0.333, GOLD }, { 0.600, 0.667, GOLD } },
	},
	Els = {
		-- the star row: a white line brightest at the three stars, and the stars' upright arms
		{ "Stars", "F", "row", 0.06, 0.94, 0.4665, 0.024, rgb(255, 248, 220), { 0, 1, 0.06, 0.7, 0.182, 0, 0.34, 0.7, 0.5, 0, 0.66, 0.7, 0.818, 0, 0.94, 0.7, 1, 1 } },
		{ "Stars", "F", "bar", 0.22, 0.4115, 0.22, 0.5215, 0.024, rgb(255, 248, 220) },
		{ "Stars", "F", "bar", 0.5, 0.3765, 0.5, 0.5565, 0.024, rgb(255, 248, 220) },
		{ "Stars", "F", "bar", 0.78, 0.4115, 0.78, 0.5215, 0.024, rgb(255, 248, 220) },
		{ "Dots", "F", "dot", 0.62, 0.17, 0.06, K.WHITE, 0.05 },
		{ "Dots", "F", "dot", 0.5, 0.80, 0.06, GOLD },
	},
	Light = { Color = rgb(255, 230, 150), Peaks = { { 0.30, 0.66, 0.06 }, { 0.4665, 0.74, 0.04 }, { 0.633, 0.66, 0.06 } } },
}
D.Legendary = {
	Kinds = { { "Crown", 1 }, { "Trim", 1 }, { "Gems", 2 }, { "Swags", 1 } },
	Bands = {
		Crown = { { 0.300, 0.509, rgb(150, 24, 52) }, { 0.509, 0.517, rgb(176, 106, 18) }, { 0.517, 0.667, rgb(255, 244, 206) } },
		Trim = { { 0.667, 0.733, GOLD } },
		Swags = { { 0.158, 0.172, rgb(255, 240, 205) } },
	},
	Els = {
		{ "Crown", "SMF", "dia", 0.5, 0.517, 0.30, rgb(255, 244, 206) },
		{ "Crown", "MF", "dia", 0.2, 0.517, 0.26, rgb(255, 244, 206) },
		{ "Crown", "MF", "dia", 0.8, 0.517, 0.26, rgb(255, 244, 206) },
		{ "Gems", "F", "dia", 0.335, 0.592, 0.09, rgb(255, 52, 96) },
		{ "Gems", "F", "dia", 0.665, 0.592, 0.09, rgb(52, 150, 255) },
		{ "Swags", "F", "dot", 0.5, 0.165, 0.05, rgb(255, 250, 240) },
		{ "Swags", "F", "dot", 0.76, 0.165, 0.05, rgb(255, 250, 240) },
	},
	Light = { Color = rgb(255, 236, 170), Peaks = { { 0.40, 0.7, 0.05 }, { 0.592, 0.62, 0.05 }, { 0.70, 0.62, 0.05 } } },
}
D.Mythic = {
	Kinds = { { "WaveBands", 4 }, { "Ribbon", 1 }, { "Swirls", 2 }, { "Stars", 1 } },
	Bands = {
		WaveBands = {
			{ 0.08, rgb(255, 232, 240) }, { 0.24, rgb(252, 176, 204) }, { 0.42, rgb(236, 130, 180) },
			{ 0.62, rgb(150, 56, 120) }, { 0.80, rgb(120, 52, 150) }, { 0.94, rgb(98, 54, 170) },
		},
	},
	Els = {
		{ "Ribbon", "MF", "band", 0.517, 0.577, { rgb(156, 92, 255), rgb(214, 176, 255) } },
		{ "Swirls", "F", "ring", 0.27, 0.445, 0.10, rgb(60, 236, 212), 0.018 },
		{ "Swirls", "F", "ring", 0.73, 0.65, 0.10, rgb(60, 236, 212), 0.018 },
		{ "Stars", "F", "dia", 0.66, 0.20, 0.07, rgb(255, 246, 252) },
	},
	Light = { Color = rgb(236, 210, 255), Peaks = { { 0.445, 0.72, 0.05 }, { 0.547, 0.6, 0.05 }, { 0.65, 0.72, 0.05 } } },
}
D.Secret = {
	Kinds = { { "Stars", 2 }, { "Runes", 1 }, { "Cracks", 1 }, { "Dots", 1 } },
	Bands = {
		-- the two magenta rune lines and the violet dusk at the foot: every form
		Base = {
			{ 0.333, 0.352, rgb(226, 82, 255) }, { 0.667, 0.686, rgb(226, 82, 255) },
			{ 0.80, rgb(40, 30, 72) }, { 0.94, rgb(70, 40, 124) },
		},
	},
	Els = {
		{ "Stars", "SMF", "plus", 0.62, 0.20, 0.13, 0.16, 0.02, rgb(255, 248, 220) },
		-- six rune marks, uneven in spacing, width and glow (an even row read as a barcode)
		{ "Runes", "MF", "ticks", 0.415, 0.585, rgb(226, 82, 255), { { 0.09, 0.025, 0.1 }, { 0.24, 0.04, 0.4 }, { 0.41, 0.022, 0.05 }, { 0.57, 0.045, 0.35 }, { 0.75, 0.025, 0.12 }, { 0.9, 0.035, 0.3 } } },
		{ "Stars", "F", "plus", 0.30, 0.84, 0.07, 0.08, 0.016, rgb(255, 248, 220) },
		{ "Cracks", "F", "bar", 0.53, 0.03, 0.46, 0.15, 0.022, rgb(150, 70, 255), 0, 1 },
		{ "Cracks", "F", "bar", 0.46, 0.15, 0.52, 0.335, 0.022, rgb(150, 70, 255), 1, 0 },
		{ "Dots", "F", "dia", 0.80, 0.30, 0.035, K.WHITE },
	},
	Light = { Color = rgb(226, 140, 255), Peaks = { { 0.18, 0.78, 0.07 }, { 0.343, 0.6, 0.04 }, { 0.50, 0.7, 0.06 }, { 0.676, 0.6, 0.04 } } },
}

-- per-egg state (weak keys): { Rarity, Form, Size, Z, Budget, Half, Paint = {}, Light, Sheen = tween, VfxOn, Fx = {} }
local ST = setmetatable({}, { __mode = "k" })
-- the graphics setting (client/GraphicsQuality's Effective(), asked on every call); High when the module is not there
local Q = { GQ = nil }

local function rarityColor(rarity)
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarity then
			return r.Color
		end
	end
	return rgb(168, 178, 194)
end

local function known(rarity)
	return K.GLOW[rarity] ~= nil
end

local function high()
	if Q.GQ == nil then
		Q.GQ = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("GraphicsQuality")
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				Q.GQ = mod
			end
		end
	end
	if not Q.GQ then
		return true
	end
	local ok, mode = pcall(Q.GQ.Effective)
	return not ok or mode ~= "Low"
end

function EggArt.Tones(rarity)
	if rarity == "Secret" then
		return K.SECRET_TOP, K.SECRET_BOTTOM
	end
	local c = rarityColor(rarity)
	return c:Lerp(K.WHITE, K.TO_WHITE), c:Lerp(K.BLACK, K.TO_BLACK)
end

function EggArt.Glow(rarity)
	return K.GLOW[rarity] or 0
end

function EggArt.Paint(rarity)
	local d = D[rarity]
	local out = {}
	for i, k in ipairs(d and d.Kinds or {}) do
		out[i] = { Kind = k[1], Count = k[2] }
	end
	return out
end

local function formOf(size, wanted)
	if wanted == "Simple" or wanted == "Medium" or wanted == "Full" then
		return wanted
	end
	if size < K.SIMPLE_BELOW then
		return "Simple"
	elseif size <= K.FULL_ABOVE then
		return "Medium"
	end
	return "Full"
end

local function outlineOf(size)
	return math.max(2, math.floor(size / 20 + 0.5))
end

-- the frame / corner / stroke / gradient makers (one helper table keeps the main chunk's locals few)
local M = {}
function M.frame(parent, name, z, color, alpha)
	return Util.Create("Frame", {
		Name = name,
		BackgroundColor3 = color or K.WHITE,
		BackgroundTransparency = alpha or 0,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = parent,
	})
end
function M.corner(f)
	return Util.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
end
-- a stroke whose thickness keeps its share k of the egg's height (Resize reads the attribute K)
function M.stroke(f, color, k, size, alpha)
	local s = Util.Create("UIStroke", {
		Color = color,
		Thickness = math.max(1, math.floor(k * size + 0.5)),
		Transparency = alpha or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = f,
	})
	s:SetAttribute("K", k)
	return s
end
function M.alphas(list)
	local kps = {}
	for i = 1, #list, 2 do
		kps[#kps + 1] = NumberSequenceKeypoint.new(list[i], list[i + 1])
	end
	return NumberSequence.new(kps)
end
function M.gradient(f, name, rotation, alphas, colors)
	return Util.Create("UIGradient", { Name = name, Rotation = rotation or 0, Transparency = alphas, Color = colors, Parent = f })
end
-- a centred frame at (x, y) (shares of the egg), w x h in egg heights
function M.at(f, x, y, w, h)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w / K.WIDTH, h)
	return f
end

-- the paint shapes: SHAPE[kind](egg, z, e, size) -> the frame (e = the element row; its arguments from e[4])
local SHAPE = {}
function SHAPE.dot(egg, z, e, size)
	local f = M.at(M.frame(egg, "Dot", z, e[7], e[8]), e[4], e[5], e[6], e[6])
	M.corner(f)
	if e[9] then
		M.stroke(f, e[9], e[10], size)
	end
	return f
end
function SHAPE.dia(egg, z, e)
	local side = e[6] / math.sqrt(2) -- d is the diamond's diagonal
	local f = M.at(M.frame(egg, "Dia", z, e[7]), e[4], e[5], side, side)
	f.Rotation = 45
	return f
end
-- a bar from (x1, y1) to (x2, y2), t thick; e[10] / e[11] = 1 mitres that end (a zigzag joint: (t / 2) tan of its slope)
function SHAPE.bar(egg, z, e)
	local x1, y1, x2, y2, t = e[4] * K.WIDTH, e[5], e[6] * K.WIDTH, e[7], e[8]
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	local ux, uy = dx / len, dy / len
	local m = (t / 2) * math.abs(dy / math.max(math.abs(dx), 1e-6))
	m = math.min(m, t)
	local a, b = (e[10] or 0) * m, (e[11] or 0) * m
	local cx, cy = (x1 + x2) / 2 + ux * (b - a) / 2, (y1 + y2) / 2 + uy * (b - a) / 2
	local f = M.at(M.frame(egg, "Bar", z, e[9]), cx / K.WIDTH, cy, len + a + b, t)
	f.Rotation = math.deg(math.atan2(dy, dx))
	return f
end
-- a horizontal line x1 .. x2 at y, its transparency along it from the list (pairs of time, alpha)
function SHAPE.row(egg, z, e)
	local f = M.frame(egg, "Row", z, e[8])
	f.AnchorPoint = Vector2.new(0, 0.5)
	f.Position = UDim2.fromScale(e[4], e[6])
	f.Size = UDim2.fromScale(e[5] - e[4], e[7])
	M.gradient(f, "Taper", 0, M.alphas(e[9]))
	return f
end
-- a ribbon across the egg's straight middle (y0 .. y1), striped along it
function SHAPE.band(egg, z, e)
	local f = M.frame(egg, "Band", z, K.WHITE)
	f.Position = UDim2.fromScale(0, e[4])
	f.Size = UDim2.fromScale(1, e[5] - e[4])
	local kps, cs = {}, e[6]
	for i = 0, 6 do
		kps[#kps + 1] = ColorSequenceKeypoint.new(i / 6, cs[(i % 2) + 1])
	end
	M.gradient(f, "Stripes", 0, nil, ColorSequence.new(kps))
	f:FindFirstChild("Stripes").Offset = Vector2.new(-0.15, 0)
	return f
end
function SHAPE.ring(egg, z, e, size)
	local f = M.at(M.frame(egg, "Ring", z, e[7], 1), e[4], e[5], e[6], e[6])
	M.corner(f)
	M.stroke(f, e[7], e[8], size)
	return f
end
-- soft rune marks along the egg's straight middle (y0 .. y1): e[7] = { { centre, half width, alpha }, ... } (<= 6: the
-- gradient's 20 keypoints)
function SHAPE.ticks(egg, z, e)
	local f = M.frame(egg, "Ticks", z, e[6])
	f.Position = UDim2.fromScale(0, e[4])
	f.Size = UDim2.fromScale(1, e[5] - e[4])
	local list = { 0, 1 }
	for _, m in ipairs(e[7]) do
		list[#list + 1], list[#list + 2] = m[1] - m[2], 1
		list[#list + 1], list[#list + 2] = m[1], m[3]
		list[#list + 1], list[#list + 2] = m[1] + m[2], 1
	end
	list[#list + 1], list[#list + 2] = 1, 1
	M.gradient(f, "Ticks", 0, M.alphas(list))
	return f
end
-- a 4-point star: a crossbar (w wide, t thick) holding its upright arm (h tall) as a child, so one Size tween twinkles both
function SHAPE.plus(egg, z, e)
	local x, y, w, h, t = e[4], e[5], e[6], e[7], e[8]
	local f = M.at(M.frame(egg, "Plus", z, e[9]), x, y, w, t)
	local arm = M.frame(f, "Arm", z, e[9])
	arm.AnchorPoint = Vector2.new(0.5, 0.5)
	arm.Position = UDim2.fromScale(0.5, 0.5)
	arm.Size = UDim2.fromScale(t / w, h / t)
	return f
end

-- the tone: the shell's top-to-bottom colours with the bands of the kinds drawn (hard bands: keypoints EPS apart)
function M.tone(rarity, kinds)
	local top, bottom = EggArt.Tones(rarity)
	local d = D[rarity]
	local soft, hard = { { 0, top } }, {}
	local function take(list)
		for _, b in ipairs(list or {}) do
			if #b == 2 then
				soft[#soft + 1] = { b[1], b[2] }
			else
				hard[#hard + 1] = b
			end
		end
	end
	take(d.Bands.Base)
	for _, k in ipairs(d.Kinds) do
		if kinds[k[1]] then
			take(d.Bands[k[1]])
		end
	end
	soft[#soft + 1] = { 1, bottom }
	table.sort(soft, function(a, b)
		return a[1] < b[1]
	end)
	table.sort(hard, function(a, b)
		return a[1] < b[1]
	end)
	local function base(y)
		for i = 2, #soft do
			if y <= soft[i][1] then
				local a, b = soft[i - 1], soft[i]
				return a[2]:Lerp(b[2], (y - a[1]) / math.max(b[1] - a[1], 1e-6))
			end
		end
		return bottom
	end
	local function shade(c, y)
		return c:Lerp(K.BLACK, K.BAND_SHADE * y)
	end
	local pts, spans, last = {}, {}, nil
	for _, b in ipairs(hard) do
		local y0, y1, c = b[1], b[2], b[3]
		if last and math.abs(last - y0) < 1e-6 then
			pts[#pts + 1] = { y0 + K.EPS, shade(c, y0) }
		else
			if last then
				pts[#pts + 1] = { last + K.EPS, base(last) }
			end
			pts[#pts + 1] = { y0 - K.EPS, base(y0) }
			pts[#pts + 1] = { y0, shade(c, y0) }
		end
		pts[#pts + 1] = { y1, shade(c, y1) }
		spans[#spans + 1] = { y0 - K.EPS, y1 + K.EPS }
		last = y1
	end
	if last then
		pts[#pts + 1] = { last + K.EPS, base(last) }
	end
	for i = 2, #soft - 1 do
		local inside = false
		for _, s in ipairs(spans) do
			inside = inside or (soft[i][1] >= s[1] and soft[i][1] <= s[2])
		end
		if not inside then
			pts[#pts + 1] = soft[i]
		end
	end
	table.sort(pts, function(a, b)
		return a[1] < b[1]
	end)
	local kps = { ColorSequenceKeypoint.new(0, top) }
	for _, p in ipairs(pts) do
		if p[1] > kps[#kps].Time and p[1] < 1 then
			kps[#kps + 1] = ColorSequenceKeypoint.new(p[1], p[2])
		end
	end
	kps[#kps + 1] = ColorSequenceKeypoint.new(1, bottom)
	return ColorSequence.new(kps)
end

-- the Light layer (Full, Epic and up): a capsule over the body, its glow rows soft peaks of a transparency gradient
function M.light(egg, d, z)
	local f = M.frame(egg, "Light", z, K.WHITE)
	f.Size = UDim2.fromScale(1, 1)
	M.corner(f)
	local list = { 0, 1 }
	for _, p in ipairs(d.Light.Peaks) do
		list[#list + 1], list[#list + 2] = p[1] - p[3], 1
		list[#list + 1], list[#list + 2] = p[1], p[2]
		list[#list + 1], list[#list + 2] = p[1] + p[3], 1
	end
	list[#list + 1], list[#list + 2] = 1, 1
	M.gradient(f, "Glow", 90, M.alphas(list), ColorSequence.new(d.Light.Color))
	return f
end

-- the rarity-dependent layers: the Light layer, the paint (greedy within the cap) and the tone; attribute Motifs
function M.paint(egg, st)
	local d, form, z = D[st.Rarity], st.Form, st.Z
	local nk = (form == "Simple") and 1 or ((form == "Medium") and 2 or #d.Kinds)
	local allowed, hasEl, drew, count = {}, {}, {}, {}
	for i = 1, nk do
		allowed[d.Kinds[i][1]] = true
	end
	if form == "Full" and d.Light then
		st.Light = M.light(egg, d, z + 1)
	end
	local cap = math.min(st.Budget or K.CAP[form], K.CAP[form])
	local used = #egg:GetDescendants() + 1
	local fc = K.FORM_CHAR[form]
	st.Paint = {}
	for _, e in ipairs(d.Els) do
		local kind = e[1]
		if allowed[kind] and string.find(e[2], fc, 1, true) then
			hasEl[kind] = true
			local cost = COST[e[3]] + ((e[3] == "dot" and e[9]) and 1 or 0)
			if used + cost <= cap then
				count[kind] = (count[kind] or 0) + 1
				local f = SHAPE[e[3]](egg, z + 2, e, st.Size)
				f.Name = kind .. count[kind]
				st.Paint[#st.Paint + 1] = f
				used = used + cost
				drew[kind] = true
			end
		end
	end
	local motifs, kinds = {}, {}
	for i = 1, nk do
		local kind = d.Kinds[i][1]
		if drew[kind] or not hasEl[kind] then
			motifs[#motifs + 1] = kind
			kinds[kind] = true
		end
	end
	local tone = egg:FindFirstChild("Tone")
	if tone then
		tone.Color = M.tone(st.Rarity, kinds)
	end
	egg.BackgroundColor3 = K.WHITE
	egg:SetAttribute("Motifs", table.concat(motifs, ","))
end

function M.unpaint(st)
	for _, f in ipairs(st.Paint or {}) do
		f:Destroy()
	end
	st.Paint = {}
	if st.Light then
		st.Light:Destroy()
		st.Light = nil
	end
end

----------------------------------------------------------------------------------------------------
-- the sheen and the VFX
----------------------------------------------------------------------------------------------------
function M.startSheen(egg, st)
	local sheen = egg:FindFirstChild("Sheen")
	local grad = sheen and sheen:FindFirstChild("Sweep")
	if st.Sheen or not grad or not high() then
		return
	end
	grad.Offset = Vector2.new(-1, 0)
	st.Sheen = TweenService:Create(grad, K.SHEEN, { Offset = Vector2.new(1, 0) })
	st.Sheen:Play()
end

function M.stopSheen(egg, st)
	if st.Sheen then
		st.Sheen:Cancel()
		st.Sheen = nil
	end
	local sheen = egg:FindFirstChild("Sheen")
	local grad = sheen and sheen:FindFirstChild("Sweep")
	if grad then
		grad.Offset = Vector2.new(-1, 0)
	end
end

-- one endless VFX tween; the property's resting value is kept so clearing puts it back
function M.loop(st, inst, info, goal)
	if not inst then
		return
	end
	local rest = {}
	for prop in pairs(goal) do
		rest[prop] = inst[prop]
	end
	local tw = TweenService:Create(inst, info, goal)
	st.Fx[#st.Fx + 1] = { Tween = tw, Inst = inst, Rest = rest }
	tw:Play()
end

local function glowColor(rarity)
	if rarity == "Secret" then
		return K.SECRET_GLOW
	end
	return rarityColor(rarity):Lerp(K.WHITE, 0.25)
end

function M.addVfx(egg, st)
	local r, z, size = st.Rarity, st.Z, st.Size
	local glow = K.GLOW[r] or 0
	if glow <= 0 then
		return
	end
	local o = outlineOf(size)
	local made = {}
	-- the halo: a ring in the glow colour just outside the outline
	local halo = M.frame(egg, "Halo", z, K.WHITE, 1)
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.Size = UDim2.new(1, 2 * o, 1, 2 * o)
	halo:SetAttribute("PadOutline", true)
	M.corner(halo)
	M.stroke(halo, glowColor(r), K.HALO_K, size, 1 - 0.85 * glow)
	made[#made + 1] = halo
	local sine = Enum.EasingStyle.Sine
	local io = Enum.EasingDirection.InOut
	if r == "Epic" then
		M.loop(st, st.Light, TweenInfo.new(0.18, Enum.EasingStyle.Linear, io, -1, true, 2.8), { BackgroundTransparency = 0.55 })
		M.loop(st, egg:FindFirstChild("Stars1"), TweenInfo.new(0.9, sine, io, -1, true, 0.5), { BackgroundTransparency = 0.6 })
	elseif r == "Legendary" then
		-- the soft rays: two bars turning behind the egg, invisible over it (a child draws over its parent)
		local rays = M.frame(egg, "Rays", z, K.WHITE, 1)
		M.at(rays, 0.5, 0.5, 2.2, 2.2)
		for i, rot in ipairs({ 45, 135 }) do
			local bar = M.frame(rays, "Ray" .. i, z, glowColor(r), 0)
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.fromScale(1, 0.1)
			bar.Rotation = rot
			M.gradient(bar, "Fade", 0, M.alphas({ 0, 1, 0.14, 0.62, 0.26, 1, 0.74, 1, 0.86, 0.62, 1, 1 }))
		end
		made[#made + 1] = rays
		M.loop(st, rays, TweenInfo.new(30, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 })
		M.loop(st, st.Light, TweenInfo.new(0.3, sine, io, -1, true, 2.4), { BackgroundTransparency = 0.6 })
	elseif r == "Mythic" then
		local ribbon = egg:FindFirstChild("Ribbon1")
		M.loop(st, ribbon and ribbon:FindFirstChild("Stripes"), TweenInfo.new(3.2, sine, io, -1, true), { Offset = Vector2.new(0.15, 0) })
	elseif r == "Secret" then
		local aura = M.frame(egg, "Aura", z, K.WHITE, 1)
		M.at(aura, 0.5, 0.5, 1.3, 1.3)
		M.corner(aura)
		M.stroke(aura, K.AURA, 0.03, size, 0.3)
		made[#made + 1] = aura
		M.loop(st, st.Light, TweenInfo.new(1.6, sine, io, -1, true), { BackgroundTransparency = 0.6 })
		for i, info in ipairs({ TweenInfo.new(0.9, sine, io, -1, true, 0.3), TweenInfo.new(1.3, sine, io, -1, true, 0.7) }) do
			local star = egg:FindFirstChild("Stars" .. i)
			if star then
				local s = star.Size
				M.loop(st, star, info, { Size = UDim2.fromScale(s.X.Scale * 0.55, s.Y.Scale * 0.55) })
			end
		end
	end
	st.FxInst = made
	st.VfxOn = true
	egg:SetAttribute("Vfx", true)
end

function M.clearVfx(egg, st)
	for _, fx in ipairs(st.Fx) do
		fx.Tween:Cancel()
		if fx.Inst.Parent then
			for prop, v in pairs(fx.Rest) do
				fx.Inst[prop] = v
			end
		end
	end
	st.Fx = {}
	for _, inst in ipairs(st.FxInst or {}) do
		inst:Destroy()
	end
	st.FxInst = {}
	st.VfxOn = false
	egg:SetAttribute("Vfx", false)
end

----------------------------------------------------------------------------------------------------
-- the API
----------------------------------------------------------------------------------------------------
function EggArt.New(parent, rarity, size, opts)
	opts = opts or {}
	rarity = known(rarity) and rarity or "Common"
	size = math.max(8, math.floor((tonumber(size) or 64) + 0.5))
	local z = opts.ZIndex or 1
	local form = formOf(size, opts.Form)
	local egg = Util.Create("Frame", {
		Name = opts.Name or ("Egg_" .. rarity),
		BackgroundColor3 = K.WHITE,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(math.floor(K.WIDTH * size + 0.5), size),
		ZIndex = z,
	})
	egg:SetAttribute("DefaultName", opts.Name == nil)
	egg:SetAttribute("Form", form)
	egg:SetAttribute("Size", size)
	egg:SetAttribute("Rarity", rarity)
	M.corner(egg)
	Util.Create("UIGradient", { Name = "Tone", Rotation = 90, Parent = egg })
	Util.Create("UIStroke", {
		Name = "Outline",
		Color = K.INK,
		Thickness = outlineOf(size),
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = egg,
	})
	local hl = M.frame(egg, "Highlight", z + 5, K.WHITE, K.HL_ALPHA)
	hl.Position = UDim2.fromScale(K.HL_POS[1], K.HL_POS[2])
	hl.Size = UDim2.fromScale(K.HL_SIZE[1], K.HL_SIZE[2])
	hl.Rotation = -24
	M.corner(hl)
	local st = { Rarity = rarity, Form = form, Size = size, Z = z, Budget = opts.Budget, Paint = {}, Fx = {}, FxInst = {} }
	ST[egg] = st
	if form ~= "Simple" and opts.Rim ~= false then
		-- the rim light: an inset capsule, lit along its lower right edge (the light bouncing back off the ground)
		local rim = M.at(M.frame(egg, "Rim", z + 3, K.WHITE), 0.5, 0.5, 0.92 * K.WIDTH, 0.94)
		M.corner(rim)
		M.gradient(rim, "RimFade", 45, M.alphas({ 0, 1, 0.6, 1, 0.86, 0.74, 1, 0.62 }))
	end
	if form == "Full" then
		M.corner(M.at(M.frame(egg, "Specular", z + 6, K.WHITE, 0.1), 0.255, 0.355, 0.05, 0.05))
		if not opts._Half then
			-- the contact shadow: a flat ellipse just under the egg (its top under the outline)
			M.corner(M.at(M.frame(egg, "Shadow", z, K.SHADOW, 0.7), 0.5, 1.04, 0.76, 0.07))
			local sheen = M.frame(egg, "Sheen", z + 4, K.WHITE)
			sheen.Size = UDim2.fromScale(1, 1)
			M.corner(sheen)
			local sweep = M.gradient(sheen, "Sweep", 25, M.alphas({ 0, 1, 0.4, 1, 0.5, 0.55, 0.6, 1, 1, 1 }))
			sweep.Offset = Vector2.new(-1, 0)
		end
	end
	M.paint(egg, st)
	egg.Destroying:Connect(function()
		if st.Sheen then
			st.Sheen:Cancel()
			st.Sheen = nil
		end
		for _, fx in ipairs(st.Fx) do
			fx.Tween:Cancel()
		end
		st.Fx = {}
	end)
	egg.Parent = parent
	if form == "Full" and not opts.Still and not opts._Half then
		M.startSheen(egg, st)
	end
	if opts.Vfx then
		EggArt.SetVfx(egg, true)
	end
	return egg
end

function EggArt.SetRarity(egg, rarity)
	if typeof(egg) ~= "Instance" or not known(rarity) or egg:GetAttribute("Rarity") == rarity then
		return
	end
	local st = ST[egg]
	egg:SetAttribute("Rarity", rarity)
	if egg:GetAttribute("DefaultName") == true then
		egg.Name = "Egg_" .. rarity
	end
	if not st then
		local tone = egg:FindFirstChild("Tone")
		if tone then
			tone.Color = ColorSequence.new(EggArt.Tones(rarity))
		end
		return
	end
	local fx = st.VfxOn
	if fx then
		M.clearVfx(egg, st)
	end
	M.unpaint(st)
	st.Rarity = rarity
	M.paint(egg, st)
	if fx then
		M.addVfx(egg, st)
	end
end

function EggArt.SetVfx(egg, on)
	local st = typeof(egg) == "Instance" and ST[egg] or nil
	if not st then
		return
	end
	if on and high() then
		M.startSheen(egg, st)
		if not st.VfxOn then
			M.addVfx(egg, st)
		end
	else
		if st.VfxOn then
			M.clearVfx(egg, st)
		end
		M.stopSheen(egg, st)
	end
end

function EggArt.Resize(egg, size)
	if typeof(egg) ~= "Instance" then
		return
	end
	size = math.max(8, math.floor((tonumber(size) or 64) + 0.5))
	egg.Size = UDim2.fromOffset(math.floor(K.WIDTH * size + 0.5), size)
	egg:SetAttribute("Size", size)
	local st = ST[egg]
	if st then
		st.Size = size
	end
	local o = outlineOf(size)
	local outline = egg:FindFirstChild("Outline")
	if outline then
		outline.Thickness = o
	end
	for _, d in ipairs(egg:GetDescendants()) do
		local k = d:GetAttribute("K")
		if d:IsA("UIStroke") and type(k) == "number" then
			d.Thickness = math.max(1, math.floor(k * size + 0.5))
		elseif d:GetAttribute("PadOutline") == true then
			d.Size = UDim2.new(1, 2 * o, 1, 2 * o)
		end
	end
end

function EggArt.Halves(parent, rarity, size)
	size = math.max(8, math.floor((tonumber(size) or 64) + 0.5))
	local w = math.floor(K.WIDTH * size + 0.5)
	local half = size / 2
	local out = {}
	for i, name in ipairs({ "HalfTop", "HalfBottom" }) do
		local group = Util.Create("CanvasGroup", {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, (i - 1) * half),
			Size = UDim2.fromOffset(w, half),
		})
		local egg = EggArt.New(group, rarity, size, { _Half = true })
		egg.Position = UDim2.fromOffset(0, -(i - 1) * half)
		group.Parent = parent
		out[i] = group
	end
	return out[1], out[2]
end

return EggArt
