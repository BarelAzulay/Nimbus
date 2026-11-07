-- EggArt (client UI; lobby-shop Task 20, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.5 "Painted eggs" API and
-- 5.6 "How eggs look"): the seven eggs drawn from frames (no image ids, nothing to upload). One shape for all: an oval
-- body (UICorner 0.5, 0.8 x as wide as it is tall), a top-to-bottom tone gradient, a navy outline and a white highlight
-- on the upper left. The painted motifs, the rim light, the specular dot, the contact shadow, the sheen and the VFX come
-- with Task 26 (Paint returns {} until then), so the stage (Task 20) and the Shop can already use the API.
--
--   EggArt.New(parent, rarity, size, opts) -> Frame "Egg_<Rarity>" (size = the egg's height in design px; width
--     floor(0.8 x size + 0.5)); opts = { Form = "Auto" | "Simple" | "Medium" | "Full", Vfx = bool (Task 26), ZIndex, Name }
--     attributes Rarity and Form (Auto: Simple under 48 px, Medium 48-140, Full over 140)
--   EggArt.SetRarity(egg, rarity)  re-skins in place: the tones, the attribute, the default name; never a new instance
--   EggArt.Halves(parent, rarity, size) -> top, bottom   two CanvasGroups "HalfTop" / "HalfBottom" (the egg's width x half
--     its height, at y 0 and y size / 2 in the parent), each drawing the whole egg clipped to its half (a CanvasGroup clips
--     rotated paint correctly)
--   EggArt.Glow(rarity)  -> the glow strength behind the egg: 0 / 0 / 0.22 / 0.34 / 0.58 / 0.66 / 0.78 (Common .. Secret)
--   EggArt.Tones(rarity) -> top, bottom Color3: the rarity colour (Config.Rarities) 38% toward white / 28% toward black;
--     Secret rgb(74,68,104) / rgb(18,16,28) (its colour is near black)
--   EggArt.Paint(rarity) -> { { Kind, ... }, ... }   the motif list as data (tests); {} until Task 26
--
-- Instances (caps, spec 16.5: Simple <= 8, Medium <= 14, Full <= 28): the body Frame, its UICorner, the UIGradient
-- "Tone", the UIStroke "Outline" (rgb(11,16,48), size / 20 thick, at least 2 px, whole) and the "Highlight" Frame with
-- its UICorner: 6 in every form today.
-- Plain Lua 5.1-compatible syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local EggArt = {}

local K = {
	INK = Color3.fromRGB(11, 16, 48),
	WHITE = Color3.new(1, 1, 1),
	BLACK = Color3.new(0, 0, 0),
	TO_WHITE = 0.38, -- the top tone: the rarity colour this far toward white
	TO_BLACK = 0.28, -- the bottom tone: this far toward black
	SECRET_TOP = Color3.fromRGB(74, 68, 104),
	SECRET_BOTTOM = Color3.fromRGB(18, 16, 28),
	GLOW = { Common = 0, Uncommon = 0, Rare = 0.22, Epic = 0.34, Legendary = 0.58, Mythic = 0.66, Secret = 0.78 },
	SIMPLE_BELOW = 48, -- design px: Simple under this
	FULL_ABOVE = 140, -- design px: Full over this
	WIDTH = 0.8, -- the body is this much as wide as it is tall
	-- the highlight: an oval on the upper left (shares of the body)
	HL_POS = { 0.2, 0.12 },
	HL_SIZE = { 0.24, 0.2 },
	HL_ALPHA = 0.35,
}
EggArt.Metrics = K

local function rarityColor(rarity)
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarity then
			return r.Color
		end
	end
	return Color3.fromRGB(168, 178, 194)
end

local function known(rarity)
	return K.GLOW[rarity] ~= nil
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
	-- (Task 26: the motif list of spec 16.5's table, e.g. { Kind = "Spots", ... } for Common)
	local _ = rarity
	return {}
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

local function skin(egg, rarity)
	local top, bottom = EggArt.Tones(rarity)
	local tone = egg:FindFirstChild("Tone")
	if tone then
		tone.Color = ColorSequence.new(top, bottom)
	end
	egg.BackgroundColor3 = K.WHITE
	egg:SetAttribute("Rarity", rarity)
	if egg:GetAttribute("DefaultName") == true then
		egg.Name = "Egg_" .. rarity
	end
end

function EggArt.New(parent, rarity, size, opts)
	opts = opts or {}
	rarity = known(rarity) and rarity or "Common"
	size = math.max(8, math.floor((tonumber(size) or 64) + 0.5))
	local z = opts.ZIndex or 1
	local egg = Util.Create("Frame", {
		Name = opts.Name or ("Egg_" .. rarity),
		BackgroundColor3 = K.WHITE,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(math.floor(K.WIDTH * size + 0.5), size),
		ZIndex = z,
	})
	egg:SetAttribute("DefaultName", opts.Name == nil)
	egg:SetAttribute("Form", formOf(size, opts.Form))
	egg:SetAttribute("Size", size)
	Util.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = egg })
	Util.Create("UIGradient", { Name = "Tone", Rotation = 90, Parent = egg })
	Util.Create("UIStroke", {
		Name = "Outline",
		Color = K.INK,
		Thickness = math.max(2, math.floor(size / 20 + 0.5)),
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = egg,
	})
	local hl = Util.Create("Frame", {
		Name = "Highlight",
		BackgroundColor3 = K.WHITE,
		BackgroundTransparency = K.HL_ALPHA,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(K.HL_POS[1], K.HL_POS[2]),
		Size = UDim2.fromScale(K.HL_SIZE[1], K.HL_SIZE[2]),
		Rotation = -24,
		ZIndex = z + 1,
		Parent = egg,
	})
	Util.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = hl })
	skin(egg, rarity)
	egg.Parent = parent
	return egg
end

function EggArt.SetRarity(egg, rarity)
	if typeof(egg) ~= "Instance" or not known(rarity) or egg:GetAttribute("Rarity") == rarity then
		return
	end
	skin(egg, rarity)
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
		local egg = EggArt.New(group, rarity, size)
		egg.Position = UDim2.fromOffset(0, -(i - 1) * half)
		group.Parent = parent
		out[i] = group
	end
	return out[1], out[2]
end

return EggArt
