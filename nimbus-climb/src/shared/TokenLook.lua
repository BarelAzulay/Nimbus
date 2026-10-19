-- TokenLook: the look of the voxel cloud token, built by one function (ARCHITECTURE_V3.md "Phase 5 build contract"
-- 3.5). The obby's cloud tokens (TokenService.MakeTokenPart: palettes "Cloud" / "Golden", the output is the Phase 4
-- token part for part) and the Cloud Cash of the home (HomeFx: "Cash" / "GoldenCash", pooled, client only) share it.
-- Shared module: no services, no yields, no tags, no attributes, no animation (the callers own those).
-- Plain Lua 5.1-compatible syntax.
--
-- The voxel coin (v3 art direction): every piece is a block on one lattice (u studs per voxel, 11 voxels across). The
-- round silhouette is three overlapping centred blocks (the 9x9 root + 11x5 and 5x11 bands) in a lighter glowing rim,
-- the face sits half a voxel proud of the rim on both sides (a 7x7 plate; an octagon of two plates on golden coins),
-- and the cream cloud emblem (a 5x2 base under a centred 3x1 dome) stands half a voxel proud of the face. A soft
-- translucent halo (an anchored, unwelded ball: it never needs to spin) makes the coin read from far away.
--
-- API (the contract):
--   TokenLook.Build(opts) -> Part   the root (the 9x9 core block; Anchored, CanCollide false, CanTouch true, CanQuery
--     false) with the children RimWide, RimTall, Face (or FaceWide + FaceTall), CloudBase, CloudPuff (welded), Halo
--     (anchored, unwelded), TokenLight (PointLight) and Sparkles (ParticleEmitter). The coin stands on its edge facing
--     local X: spinning it about world Y shows both faces.
--     opts = { Position = Vector3 (centre; default 0,0,0), Parent = Instance | nil (set LAST), Palette = "Cloud" |
--       "Golden" | "Cash" | "GoldenCash" (default "Cloud"), Scale = number (default 1, x the palette's own scale),
--       Light = bool (default true), Sparkles = bool (default true), Phase = radians of yaw (default 0),
--       Halo = bool (extra; default true for Cloud / Golden, false for the cash palettes: 6 parts per Cash coin) }
--     Parts: Cloud 7, Golden 8 (halo included); Cash / GoldenCash 6 without the halo.
--   TokenLook.Palettes[name] = { Scale, Rim, Face, Cloud, Glow, Octagon, HaloScale, HaloTransparency, LightBrightness,
--     LightRange, SparkleRate, SparkleSize, SparkleLife, SparkleSpeed, SparkleAlpha, Spin, Bob, Name }   READ-ONLY
--   TokenLook.Motion = { Spin 2.0, GoldenSpin 2.6, Bob 0.45, GoldenBob 0.6, BobSpeed 2.2 }   (radians/s, studs)
--   TokenLook.Voxel = 0.32 (studs per voxel at Scale 1), TokenLook.HaloDiameter = 5.4

local Shared = script.Parent

local TokenLook = {}

-- Theme is only used for its in-world palette; a broken UI kit must never take the tokens down.
local themeModule = Shared:FindFirstChild("Theme")
local themeOk, Theme = false, nil
if themeModule then
	themeOk, Theme = pcall(require, themeModule)
end
if not themeOk or type(Theme) ~= "table" then
	Theme = {}
end

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

TokenLook.Voxel = 0.32 -- studs per coin voxel (a normal coin: 11 voxels = 3.5 studs across)
TokenLook.HaloDiameter = 5.4

TokenLook.Motion = {
	Spin = 2.0, -- radians per second around the vertical axis
	GoldenSpin = 2.6,
	Bob = 0.45, -- bob amplitude in studs
	GoldenBob = 0.6,
	BobSpeed = 2.2, -- radians per second of the up / down sine
}

local function colorOr(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end
	return fallback
end

local WORLD = type(Theme.World) == "table" and Theme.World or {}
local COLORS = type(Theme.Colors) == "table" and Theme.Colors or {}
local GOLD = colorOr(WORLD.Token, Color3.fromRGB(232, 168, 48))
local GLOW = GOLD:Lerp(Color3.fromRGB(255, 240, 190), 0.45)
local CASH = colorOr(COLORS.Cash, Color3.fromRGB(112, 204, 98))
local CASH_GLOW = colorOr(COLORS.CashGlow, Color3.fromRGB(196, 240, 150))
local M = TokenLook.Motion

-- Everything that differs between the looks (Cloud / Golden = the Phase 4 normal / golden token, unchanged).
TokenLook.Palettes = {
	Cloud = {
		Name = "CloudToken",
		Scale = 1,
		Rim = Color3.fromRGB(255, 206, 92), -- the glowing outer ring (Neon)
		Face = GOLD, -- the coin face
		Cloud = Color3.fromRGB(255, 244, 218), -- the cloud emblem in relief
		Glow = GLOW,
		Octagon = false,
		HaloScale = 1,
		HaloTransparency = 0.86,
		LightBrightness = 1.0,
		LightRange = 11,
		SparkleRate = 5,
		SparkleSize = 0.55,
		SparkleLife = NumberRange.new(0.9, 1.6),
		SparkleSpeed = NumberRange.new(0.4, 1.2),
		SparkleAlpha = 0.15,
		Spin = M.Spin,
		Bob = M.Bob,
	},
	Golden = {
		Name = "GoldenCloudToken",
		Scale = 1.5,
		Rim = Color3.fromRGB(255, 236, 156),
		Face = Color3.fromRGB(255, 212, 92),
		Cloud = Color3.fromRGB(255, 250, 238),
		Glow = Color3.fromRGB(255, 230, 150),
		Octagon = true,
		HaloScale = 1.2,
		HaloTransparency = 0.82,
		LightBrightness = 2.0,
		LightRange = 17,
		SparkleRate = 16,
		SparkleSize = 0.95,
		SparkleLife = NumberRange.new(1.1, 2.0),
		SparkleSpeed = NumberRange.new(0.4, 2.2),
		SparkleAlpha = 0.05,
		Spin = M.GoldenSpin,
		Bob = M.GoldenBob,
	},
	-- Cloud Cash (the home): a mint-green glowing rim (Theme Cash), a gold face, a white cloud
	Cash = {
		Name = "CashCoin",
		Scale = 1,
		Rim = CASH,
		Face = GOLD,
		Cloud = Color3.fromRGB(250, 252, 246),
		Glow = CASH_GLOW,
		Octagon = false,
		HaloScale = 1,
		HaloTransparency = 0.86,
		LightBrightness = 0.8,
		LightRange = 9,
		SparkleRate = 3,
		SparkleSize = 0.45,
		SparkleLife = NumberRange.new(0.8, 1.4),
		SparkleSpeed = NumberRange.new(0.3, 1.0),
		SparkleAlpha = 0.2,
		Spin = M.Spin,
		Bob = M.Bob,
	},
	-- a Lucky drop (x5): a bright gold rim around a mint-green face (still Cloud Cash, but golden), a brighter sparkle
	GoldenCash = {
		Name = "GoldenCashCoin",
		Scale = 1.15,
		Rim = Color3.fromRGB(255, 214, 72),
		Face = CASH,
		Cloud = Color3.fromRGB(255, 252, 240),
		Glow = Color3.fromRGB(255, 236, 150),
		Octagon = false,
		HaloScale = 1.2,
		HaloTransparency = 0.82,
		LightBrightness = 1.6,
		LightRange = 13,
		SparkleRate = 12,
		SparkleSize = 0.8,
		SparkleLife = NumberRange.new(1.0, 1.8),
		SparkleSpeed = NumberRange.new(0.4, 1.8),
		SparkleAlpha = 0.05,
		Spin = M.GoldenSpin,
		Bob = M.GoldenBob,
	},
}

-- A non-colliding block of the coin, positioned by `offset` (relative to the root). static = true: anchored and NOT
-- welded (the spherical halo, which the animating caller bobs along with the coin); otherwise welded to the root.
local function addPiece(token, name, shape, size, offset, color, material, transparency, static)
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Shape = shape
	piece.Size = size
	piece.Material = material
	piece.Color = color
	piece.Transparency = transparency or 0
	piece.Anchored = static == true
	piece.Massless = true
	piece.CanCollide = false
	piece.CanTouch = false
	piece.CanQuery = false
	piece.CastShadow = false
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.CFrame = token.CFrame * offset
	piece.Parent = token
	if not static then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = token
		weld.Part1 = piece
		weld.Parent = piece
	end
	return piece
end

-- One block of the coin lattice: centre (y, z) and size (thickness x height x width) in voxels.
local function addBlock(token, name, u, y, z, thick, height, width, color, material)
	return addPiece(token, name, Enum.PartType.Block, Vector3.new(thick * u, height * u, width * u),
		CFrame.new(0, y * u, z * u), color, material, 0)
end

local function finiteNumber(v, fallback)
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return fallback
end

function TokenLook.Build(opts)
	opts = type(opts) == "table" and opts or {}
	local paletteName = TokenLook.Palettes[opts.Palette] and opts.Palette or "Cloud"
	local look = TokenLook.Palettes[paletteName]
	local cash = paletteName == "Cash" or paletteName == "GoldenCash"
	local scale = look.Scale * math.max(0.05, finiteNumber(opts.Scale, 1))
	local u = TokenLook.Voxel * scale
	local phase = finiteNumber(opts.Phase, 0)
	local position = typeof(opts.Position) == "Vector3" and opts.Position or Vector3.new(0, 0, 0)
	local neon = Enum.Material.Neon
	local smooth = Enum.Material.SmoothPlastic

	-- the root: the 9x9 core of the rim silhouette (2 voxels thick)
	local token = Instance.new("Part")
	token.Name = look.Name
	token.Shape = Enum.PartType.Block
	token.Size = Vector3.new(2 * u, 9 * u, 9 * u)
	token.Material = neon
	token.Color = look.Rim
	token.Anchored = true
	token.CanCollide = false
	token.CanTouch = true
	token.CanQuery = false
	token.CastShadow = false
	token.TopSurface = Enum.SurfaceType.Smooth
	token.BottomSurface = Enum.SurfaceType.Smooth
	token.CFrame = CFrame.new(position) * CFrame.Angles(0, phase, 0)

	-- the rest of the stepped round silhouette: a wide and a tall band (11x5 and 5x11 voxels)
	addBlock(token, "RimWide", u, 0, 0, 2, 5, 11, look.Rim, neon)
	addBlock(token, "RimTall", u, 0, 0, 2, 11, 5, look.Rim, neon)

	-- the face, half a voxel proud of the rim on both sides: a 7x7 plate, or an octagon of two plates
	if look.Octagon then
		addBlock(token, "FaceWide", u, 0, 0, 3, 5, 7, look.Face, smooth)
		addBlock(token, "FaceTall", u, 0, 0, 3, 7, 5, look.Face, smooth)
	else
		addBlock(token, "Face", u, 0, 0, 3, 7, 7, look.Face, smooth)
	end

	-- the cloud emblem in relief (both sides): a 5x2 base under a centred 3x1 dome
	addBlock(token, "CloudBase", u, -0.5, 0, 4, 2, 5, look.Cloud, smooth)
	addBlock(token, "CloudPuff", u, 1, 0, 4, 1, 3, look.Cloud, smooth)

	-- the soft translucent halo (not welded: a ball looks the same however the coin turns)
	local wantHalo = opts.Halo
	if wantHalo == nil then
		wantHalo = not cash
	end
	if wantHalo then
		local haloSize = TokenLook.HaloDiameter * look.HaloScale * scale
		addPiece(token, "Halo", Enum.PartType.Ball, Vector3.new(haloSize, haloSize, haloSize),
			CFrame.new(0, 0, 0), look.Glow, neon, look.HaloTransparency, true)
	end

	if opts.Light ~= false then
		local light = Instance.new("PointLight")
		light.Name = "TokenLight"
		light.Color = look.Face
		light.Brightness = look.LightBrightness
		light.Range = look.LightRange
		light.Shadows = false
		light.Parent = token
	end

	if opts.Sparkles ~= false then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = SPARKLE_TEXTURE
		sparkles.Color = ColorSequence.new(look.Glow, look.Face)
		sparkles.LightEmission = 1
		sparkles.LightInfluence = 0
		sparkles.Rate = look.SparkleRate
		sparkles.Lifetime = look.SparkleLife
		sparkles.Speed = look.SparkleSpeed
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rotation = NumberRange.new(0, 360)
		sparkles.RotSpeed = NumberRange.new(-60, 60)
		sparkles.Acceleration = Vector3.new(0, 0.8, 0)
		sparkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, look.SparkleSize),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, look.SparkleAlpha),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparkles.Parent = token
	end

	if typeof(opts.Parent) == "Instance" then
		token.Parent = opts.Parent
	end
	return token
end

return TokenLook
