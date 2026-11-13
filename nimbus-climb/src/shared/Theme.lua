-- Theme: fonts, colours, text sizes and tiny UI builders so every label in the game looks consistent.
-- v2: calmer, darker, clearer palette (late-afternoon cloud world), the in-world palette `Theme.World`
-- (LobbyBuilder / CourseBuilder / TokenService / HazardService) and the palette tokens of the chunky
-- "cloud" UI kit (client/UI/CloudUI.lua).
-- v3: the READABILITY RULE (ARCHITECTURE_V3.md): at 1920x1080 body text >= 18 px, small captions >= 15 px,
-- buttons >= 20 px, titles 28-44 px; everything scales with the screen height
-- (factor clamp(viewportY / 1080, 0.8, 1.25)) and nothing ever drops below 14 px. Every text gets a stroke
-- or sits on a solid panel (kit B: stroke OR panel, never both; see below).
--   * Theme.Sizes[role]          default size per font role at 1080p (applied by Theme.Style / Theme.Label)
--   * Theme.ScreenFactor()       the screen-height factor (1 on the server)
--   * Theme.ScaledSize(basePx)   basePx (a 1080p size) for the current screen, never below 14
--   * Theme.TextOutline(label)   a thick UIStroke around the glyphs (reads on light and busy backgrounds)
--   * Theme.Currency / Theme.ShortNumber(n)   currency glyphs + colours and "12.3K" style numbers
-- Two ways to follow the rule: put widgets designed in 1080p pixels under a UIScale of Theme.ScreenFactor()
-- (CloudUI.AutoScale does that), or give a loose label TextSize = Theme.ScaledSize(base). Never both.
-- v5 (Phase 5, the Neon kit of client/UI/NeonKit.lua, ARCHITECTURE_V3.md "Phase 5 build contract" 6.6): the neon accent
-- colours `Theme.Neon`, the colour of every menu / window category `Theme.Category`, `Theme.NeonColor(name)`, the dark
-- navy card fill `Colors.PanelTop / PanelBottom / PanelInk`, and the "less cute" faces: Title / Button / Toast are
-- GothamBlack now (Display stays FredokaOne for the big friendly numbers, Accent LuckiestGuy for damage numbers).
-- kit B (U1 of .superpowers/slop-audit/round3/BUILD_PLAN.md, the owner's approved kit pitch): the pitch's faces by role
-- (LuckiestGuy titles and signs, FredokaOne headings / buttons / tags / nameplates, Nunito ExtraBold reading text through
-- `Theme.Faces`, Nunito Bold Italic for flavour lines; GothamBlack and Fondamento are gone) and the readability rule
-- "contrast by surface, outline only with no plate": Theme.Style adds no stroke by default, `Outline = "World"` gives text
-- over the 3D world one outline and no stroke, `Theme.TextOn(surface)` picks the text colour for a fill. Also
-- `Theme.SetRole` (a role's face without restyling), `Theme.Measure` (text size for a role), `Theme.Sign` (the kit B
-- palette) and `Theme.Radius` (the corner tokens).
-- U1 review: a Nunito label reads .Font = Enum.Font.Unknown in Roblox (no Enum twin) and TextService:GetTextSize throws on
-- it, so never measure with lbl.Font: `Theme.FontOf(lbl)` (the Enum font to measure with) and `Theme.MeasureLabel(lbl)`.
-- U6 (the outline and font sweep): one outline at most. Theme.Style never sets a classic text stroke (an old caller's Stroke
-- is ignored), so a label is either plain (on a panel, plank, chip or button) or carries ONE outline: Outline = "World"
-- for text over the 3D world with no plate. Theme.Measure also takes an Enum font (the old GetTextSize helpers), and
-- Theme.Corner takes "Round" (a pill or a disc) beside the Theme.Radius tokens. World signs (BillboardGui / SurfaceGui) keep
-- their one outline on their plate (the World text rule of ARCHITECTURE_V3). Casing: the Title, Sign, Accent and Tag roles
-- read in capitals (`Theme.CapsRoles`, kept by Theme.SetRole; LuckiestGuy's lower case reads oddly: "PeTS").
-- T0 (the owner's title pick B): the Title role is FredokaOne; LuckiestGuy stays on Accent (damage numbers, world hint
-- words) and Sign (the approved Credits header). Every window title goes through `Theme.StyleTitle(label)`, the one place a
-- designed title treatment will go (today it adds nothing). T0 review: so do the Title-role headings that are not a
-- window's name, with a `Theme.TitleExempt` kind (a section head, a headline with its own gradient) that keeps them plain.
-- Plain Lua 5.1-compatible syntax only. Safe to require on the server and on the client.

local Theme = {}

local function font(name, fallback)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	if ok and value then
		return value
	end
	local okFallback, fallbackValue = pcall(function()
		return Enum.Font[fallback or "GothamBold"]
	end)
	if okFallback and fallbackValue then
		return fallbackValue
	end
	return Enum.Font.GothamBold
end

-- Font roles. Use roles, never raw Enum.Font, anywhere in the game.
-- v3: Body and Label moved to the heavier Builder Sans cuts (far easier to read at small sizes on busy
-- backgrounds); the chunky display faces stay.
-- kit B: the pitch's three faces. LuckiestGuy is loud, so it is for the Credits sign and damage numbers only (T0: titles
-- moved to FredokaOne); FredokaOne carries titles, headings, buttons, tags and nameplates; reading text is Nunito ExtraBold
-- (Theme.Faces below: the Enum font of a FontFace role is only its fallback for an engine without Font.new).
Theme.Fonts = {
	-- THE one line for the title face (T0: the owner's title pick B, FredokaOne; was LuckiestGuy). Window titles also go
	-- through Theme.StyleTitle
	Title = font("FredokaOne"), -- logo fallback, banners, portal names, window titles
	Display = font("FredokaOne"), -- big numbers: timer, countdown, currency counts
	Heading = font("FredokaOne"), -- panel headers, section heads, card / pet names
	Body = font("BuilderSansBold", "GothamBold"), -- descriptions, dialog text (face: Nunito ExtraBold)
	Label = font("BuilderSansBold", "GothamMedium"), -- small captions (face: Nunito ExtraBold)
	Accent = font("LuckiestGuy", "FredokaOne"), -- damage numbers, "GO!"
	Script = font("Nunito", "BuilderSansBold"), -- flavour text / taglines (face: Nunito Bold Italic; Fondamento retired)
	-- v2 additions
	Toast = font("BuilderSansBold", "GothamBold"), -- side-of-screen system messages (face: Nunito ExtraBold)
	Button = font("FredokaOne"), -- text on buttons, tabs and tiles
	-- kit B additions
	Tag = font("FredokaOne"), -- small capital tags: FIGHTER, NEW, rarity, L30, key caps
	Nameplate = font("FredokaOne"), -- names over heads (over the world: Outline = "World")
	-- (credits look B) the Signboard window kit: its header title, and the maker's hand-written signature + polaroid caption.
	-- Signature is THE one place to swap that face (the owner's pick PermanentMarker; Gemini's phone pick was "Kalam").
	-- Sign stays its own entry so the approved Credits look does not move when the Title line flips (T0: it did; Sign kept).
	Sign = font("LuckiestGuy", "FredokaOne"),
	Signature = font("PermanentMarker", "FredokaOne"),
}

-- FontFace roles (a weight or style an Enum.Font has not got). Theme.Style / Theme.Label / Theme.SetRole put a role's
-- face on after its Enum font (setting .Font afterwards would undo it, so use Theme.SetRole, not .Font =); Theme.Face(label,
-- role) puts one on by itself. Nil when the engine has no Font.new (then the label keeps its role font).
local function face(family, weight, style)
	local ok, value = pcall(function()
		return Font.new("rbxasset://fonts/families/" .. family .. ".json", Enum.FontWeight[weight], Enum.FontStyle[style])
	end)
	return ok and value or nil
end
local READING = face("Nunito", "ExtraBold", "Normal")
Theme.Faces = {
	Caps = face("Nunito", "Heavy", "Normal"), -- (credits look B) small spaced capitals ("CREATED BY")
	Thanks = face("Nunito", "Bold", "Italic"), -- (credits look B) the gold thank-you line
	-- kit B reading text and flavour lines
	Body = READING,
	Label = READING,
	Toast = READING,
	Script = face("Nunito", "Bold", "Italic"),
}

-- Theme.Measure's widening per FontFace role: TextService:GetTextSize only knows the Enum fallback (Builder Sans Bold),
-- and Nunito ExtraBold runs a few per cent wider (Nunito Regular is 0.94-1.0 x Builder Sans Bold, ExtraBold about 1.07 x
-- Regular), so these round up to never cut a word. Roles not listed measure 1:1 (their Enum font is the face).
Theme.MeasureSpare = {
	Body = 1.06,
	Label = 1.06,
	Toast = 1.06,
	Script = 1.06,
}

----------------------------------------------------------------------
-- Readability rule (v3)
----------------------------------------------------------------------
Theme.Readability = {
	RefHeight = 1080, -- sizes below are pixels on a 1920x1080 screen
	MinFactor = 0.8, -- phones / small windows
	MaxFactor = 1.25, -- 1440p and up
	MinPx = 14, -- nothing is ever rendered smaller
	Caption = 15,
	Body = 18,
	Button = 20,
	TitleMin = 28,
	TitleMax = 44,
}

-- Default TextSize per font role at 1080p (design pixels). Theme.Style uses them whenever the caller gives
-- no Size; widgets under a UIScale of Theme.ScreenFactor() then follow the rule automatically.
Theme.Sizes = {
	Title = 34,
	Display = 32,
	Heading = 22,
	Body = 19,
	Label = 16,
	Accent = 30,
	Script = 19,
	Toast = 18,
	Button = 22,
	Tag = 16,
	Nameplate = 20,
	Sign = 34,
	Signature = 56,
}

local function clamp(n, lo, hi)
	if n < lo then
		return lo
	elseif n > hi then
		return hi
	end
	return n
end

local function viewportHeight()
	local ok, height = pcall(function()
		local camera = workspace.CurrentCamera
		return camera and camera.ViewportSize.Y or 0
	end)
	if ok and type(height) == "number" then
		return height
	end
	return 0
end

local function isClient()
	local ok, result = pcall(function()
		return game:GetService("RunService"):IsClient()
	end)
	return ok and result == true
end

-- The screen-height factor of the readability rule: clamp(viewportY / 1080, 0.8, 1.25).
-- `height` (optional) overrides the measured viewport height. On the server (no screen) it is 1.
function Theme.ScreenFactor(height)
	local r = Theme.Readability
	local h = tonumber(height)
	if not h then
		if not isClient() then
			return 1
		end
		h = viewportHeight()
	end
	if not h or h < 2 then
		return 1
	end
	return clamp(h / r.RefHeight, r.MinFactor, r.MaxFactor)
end

-- A 1080p pixel size scaled for the current screen, rounded, never below `minPx` (default 14).
-- Use it for text that is NOT under a UIScale (tooltips, billboards, loose labels).
function Theme.ScaledSize(basePx, minPx)
	local base = tonumber(basePx) or Theme.Readability.Body
	local floorPx = tonumber(minPx) or Theme.Readability.MinPx
	return math.max(floorPx, math.floor(base * Theme.ScreenFactor() + 0.5))
end

-- Default size of a role (1080p design pixels).
function Theme.RoleSize(role)
	return Theme.Sizes[role] or Theme.Sizes.Body
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Theme.Colors = {
	-- Existing keys (other modules depend on every one of them) with the calmer v2 values.
	SkyTop = rgb(66, 116, 192),
	SkyBottom = rgb(212, 164, 184),
	Cloud = rgb(214, 224, 240),
	CloudShade = rgb(150, 168, 200),
	Storm = rgb(54, 60, 88),
	Ink = rgb(26, 32, 64), -- text outlines
	Panel = rgb(30, 40, 80), -- dark HUD cards
	PanelLight = rgb(64, 84, 142),
	Token = rgb(238, 190, 62),
	TokenGlow = rgb(250, 224, 132),
	Health = rgb(92, 206, 128),
	HealthMid = rgb(238, 190, 72),
	HealthLow = rgb(236, 88, 100),
	Stamina = rgb(98, 172, 232),
	Good = rgb(108, 208, 144),
	Bad = rgb(240, 102, 112),
	White = rgb(255, 255, 255), -- text only
	Rainbow = {
		rgb(232, 104, 120),
		rgb(240, 160, 88),
		rgb(240, 208, 98),
		rgb(104, 200, 142),
		rgb(98, 168, 232),
		rgb(160, 130, 232),
	},

	-- v2 UI-kit tokens (CloudUI)
	Navy = rgb(24, 34, 78), -- thick outlines around panels, buttons, slots
	Outline = rgb(24, 34, 78), -- alias of Navy
	FrameTop = rgb(176, 212, 244), -- outer window frame, top colour
	FrameBottom = rgb(112, 158, 216), -- outer window frame, bottom colour
	WellTop = rgb(60, 96, 164), -- inner content well, top colour
	WellBottom = rgb(40, 68, 128), -- inner content well, bottom colour
	WellEdge = rgb(22, 34, 82),
	Mist = rgb(226, 234, 246), -- pale cloud used for slot fills (never pure white)
	MistDeep = rgb(176, 196, 228),
	Gold = rgb(244, 196, 78),
	-- Secondary text on dark wells. 4.6:1 on WellTop, 7.1:1 on WellBottom, 5.5:1 on PanelLight
	-- (the old (176,192,222) gave only 3.4:1 on WellTop); still clearly dimmer than White.
	Muted = rgb(212, 224, 246),

	-- v3 additions
	TextStroke = rgb(16, 22, 50), -- the thick glyph outline (Theme.TextOutline), a touch darker than Ink
	TextDark = rgb(30, 40, 82), -- text that sits directly on a pale fill (Mist slots, light pills)
	TitleBar = rgb(98, 160, 236), -- default window title bar (CloudUI.Panel without an Accent)
	Cash = rgb(112, 204, 98),
	CashGlow = rgb(196, 240, 150),
	Gem = rgb(84, 196, 246),
	GemGlow = rgb(186, 236, 255),

	-- v5 Neon kit (NeonKit.Card / CloudUI.Panel): the dark navy card fill (top -> bottom) and the darkest ink
	PanelTop = rgb(26, 32, 72),
	PanelBottom = rgb(12, 15, 38),
	PanelInk = rgb(8, 10, 28),
}

-- v5 Neon kit: the glowing border / accent colours (image 21.png). One colour per category below.
Theme.Neon = {
	Orange = rgb(255, 150, 48),
	Blue = rgb(64, 170, 255),
	Purple = rgb(176, 104, 255),
	Red = rgb(255, 76, 100),
	Green = rgb(72, 224, 120),
	Yellow = rgb(255, 210, 64),
	Cyan = rgb(64, 226, 236),
	Pink = rgb(255, 112, 200),
	Gold = rgb(255, 196, 64),
	Grey = rgb(150, 166, 204),
}

-- v5: the neon colour NAME of every menu tile / window / mode (Theme.NeonColor turns it into a Color3).
Theme.Category = {
	Pets = "Orange",
	Items = "Blue",
	Team = "Red",
	Index = "Purple",
	Shop = "Green",
	Home = "Yellow",
	Stats = "Cyan",
	Settings = "Grey",
	Obby = "Blue",
	Dungeon = "Purple",
	Ring = "Gold",
	Arena = "Red",
	Altar = "Cyan",
	Care = "Green",
	Fusion = "Pink",
	Battle = "Red",
	-- store (2026-11-04): the Robux Store and the Gifts window share the gold; the Sky Trove is a prize chest
	Store = "Gold",
	Daily = "Gold",
	Trove = "Green",
}

-- Base colours of the glossy button styles (CloudUI.Button / IconButton).
Theme.Buttons = {
	Green = rgb(96, 196, 108),
	Pink = rgb(238, 126, 176),
	Red = rgb(228, 90, 92),
	Blue = rgb(90, 158, 234),
	Gold = rgb(244, 190, 70),
	Gray = rgb(144, 156, 180),
}

-- Pill / toast colours by kind (v5: the neon Blue / Green / Red / Gold of the Neon kit).
Theme.Kinds = {
	info = rgb(64, 170, 255),
	good = rgb(72, 224, 120),
	bad = rgb(255, 76, 100),
	token = rgb(255, 196, 64),
}

-- Currencies (v3): glyph, attribute name (Config.Attr values) and the coin colours used by the HUD stack,
-- the shop and price tags. Cash and Gems arrive with the tycoon phase.
Theme.Currency = {
	Tokens = {
		Id = "Tokens",
		Name = "Cloud Tokens",
		Attr = "CloudTokens",
		Glyph = "\226\152\129", -- cloud
		Color = rgb(238, 190, 62),
		Glow = rgb(250, 224, 132),
	},
	Cash = {
		Id = "Cash",
		Name = "Cash",
		Attr = "Cash",
		Glyph = "$",
		Color = rgb(112, 204, 98),
		Glow = rgb(196, 240, 150),
	},
	Gems = {
		Id = "Gems",
		Name = "Gems",
		Attr = "Gems",
		Glyph = "\226\151\134", -- black diamond
		Color = rgb(84, 196, 246),
		Glow = rgb(186, 236, 255),
	},
}

-- kit B: the Signboard palette of the approved pitch (kit_pitch_mockups.html, BUILD_PLAN decision 5): stone body and its
-- darker lip, wood frame, navy header plank, gold sign titles, the pink awning, green for the one main action, red, and
-- the brown text that sits on stone (13.6:1).
Theme.Sign = {
	Stone = rgb(255, 247, 230), -- #FFF7E6
	StoneLip = rgb(220, 201, 160), -- #DCC9A0
	Wood = rgb(140, 90, 46), -- #8C5A2E
	Navy = rgb(35, 42, 110), -- #232A6E
	Gold = rgb(255, 210, 74), -- #FFD24A
	Roof = rgb(238, 111, 166), -- #EE6FA6
	Grass = rgb(111, 207, 106), -- #6FCF6A
	Red = rgb(238, 106, 127), -- #EE6A7F
	Text = rgb(59, 36, 18), -- #3B2412
	TextMuted = rgb(118, 84, 54), -- #765436 (small captions on stone)
	-- U2 (SignKit): the pitch's edges and darker bottom lips (kB --*Lip tokens, the .roof border, the .posts colour)
	RoofEdge = rgb(122, 42, 82), -- #7A2A52
	RoofLip = rgb(196, 74, 130), -- #C44A82
	GoldLip = rgb(201, 154, 30), -- #C99A1E
	NavyLip = rgb(23, 28, 79), -- #171C4F
	GrassLip = rgb(63, 154, 69), -- #3F9A45
	OnGrass = rgb(22, 50, 26), -- #16321A (U5: text and icons on a grass plank, the pitch's --onPri)
	RedLip = rgb(184, 54, 79), -- #B8364F
	Tile = rgb(255, 253, 246), -- #FFFDF6 (a raised stone button)
	Well = rgb(243, 230, 200), -- #F3E6C8 (a sunk / disabled stone)
	WellEdge = rgb(201, 168, 119), -- #C9A877
	Post = rgb(196, 138, 78), -- #C48A4E (sign posts and ropes; their shaded side is Wood)
}

-- kit B corner radius tokens in px (Theme.Corner(obj, "M")); the windows of the pitch are square-cornered blocks, so the
-- largest token is small. U6 moved the literal radii of the files it swept to these (tools/check.mjs RADIUS_SWEPT,
-- rule radius-literal); Theme.Corner(obj, "Round") is the pill / disc (half the short side).
Theme.Radius = {
	None = 0,
	S = 4,
	M = 8,
}

-- In-world palette for Parts (lobby, courses, tokens, hazards). Calm, never pure white; platform
-- tops are clearly lighter than their sides, hazards are a distinct dark red/purple, checkpoints
-- teal. Trim colours are per difficulty id (Config.Difficulties order) and also by index.
Theme.World = {
	-- Peaks are 214 / 184 / 150 on purpose: the same ceiling LobbyBuilder clamps to, so the lobby
	-- and every course platform (and the Start/Finish pads) share one calm palette and the blue
	-- channel does not clip towards white-cyan under the late-afternoon sun.
	CloudTop = rgb(183, 194, 214),
	CloudSide = rgb(135, 152, 184),
	CloudShadow = rgb(96, 113, 150),
	Hazard = rgb(160, 62, 94),
	HazardGlow = rgb(222, 100, 124),
	Checkpoint = rgb(62, 172, 152),
	Token = rgb(238, 194, 86),
	Storm = rgb(58, 64, 94),
	Wind = rgb(150, 198, 226),
	Water = rgb(96, 156, 214),
	Trim = {
		Easy = rgb(96, 190, 140),
		Medium = rgb(96, 160, 224),
		Hard = rgb(226, 150, 74),
		Extreme = rgb(214, 92, 104),
		Saint = rgb(150, 110, 220), -- violet, mirrors Config.Difficulties Saint (gold is reserved for stars/tokens)
		rgb(96, 190, 140),
		rgb(96, 160, 224),
		rgb(226, 150, 74),
		rgb(214, 92, 104),
		rgb(150, 110, 220),
	},
	Rainbow = {
		rgb(206, 96, 112),
		rgb(214, 148, 84),
		rgb(214, 190, 96),
		rgb(100, 174, 128),
		rgb(92, 150, 206),
		rgb(142, 118, 206),
	},
}

-- v5: a neon colour by category ("Pets"), by neon name ("Orange", any case) or a Color3 passed through; anything
-- else (nil, unknown) is the Blue neon.
function Theme.NeonColor(categoryOrColorName)
	if typeof(categoryOrColorName) == "Color3" then
		return categoryOrColorName
	end
	if type(categoryOrColorName) ~= "string" or categoryOrColorName == "" then
		return Theme.Neon.Blue
	end
	local name = categoryOrColorName
	local category = Theme.Category[name]
	if category then
		return Theme.Neon[category]
	end
	if Theme.Neon[name] then
		return Theme.Neon[name]
	end
	local lower = name:lower()
	for key, value in pairs(Theme.Category) do
		if key:lower() == lower then
			return Theme.Neon[value]
		end
	end
	for key, value in pairs(Theme.Neon) do
		if key:lower() == lower then
			return value
		end
	end
	if lower == "gray" then
		return Theme.Neon.Grey
	end
	return Theme.Neon.Blue
end

-- Colour for a health fraction 0..1 (green -> amber -> red).
function Theme.HealthColor(fraction)
	if fraction > 0.6 then
		return Theme.Colors.Health
	elseif fraction > 0.3 then
		return Theme.Colors.HealthMid
	end
	return Theme.Colors.HealthLow
end

-- kit B: the text colour for a surface. A name of Theme.Sign ("Stone", "Navy", "Wood", ...), one of today's dark fills
-- ("Panel", "Dark", "Well"), any Color3 or a ColorSequence (a gradient fill: judged at its worst stop); the brown #3B2412
-- or white, whichever has the higher contrast on it (brown on stone and gold, white on navy, wood and the dark panels).
-- Nil / unknown = white, the dark panels' colour today.
local function channel(v)
	if v <= 0.04045 then
		return v / 12.92
	end
	return ((v + 0.055) / 1.055) ^ 2.4
end

local function luminance(c)
	return 0.2126 * channel(c.R) + 0.7152 * channel(c.G) + 0.0722 * channel(c.B)
end

local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

local DARK_SURFACES = { Panel = "Panel", Dark = "PanelTop", Well = "WellTop" }

function Theme.TextOn(surface)
	local fill = nil
	if typeof(surface) == "ColorSequence" then
		-- (U6 review) a gradient fill: the ink whose worst contrast over the colour stops is higher
		local brown, white = math.huge, math.huge
		for _, kp in ipairs(surface.Keypoints) do
			brown = math.min(brown, contrast(Theme.Sign.Text, kp.Value))
			white = math.min(white, contrast(Theme.Colors.White, kp.Value))
		end
		return (brown > white) and Theme.Sign.Text or Theme.Colors.White
	end
	if typeof(surface) == "Color3" then
		fill = surface
	elseif type(surface) == "string" then
		fill = Theme.Sign[surface] or (DARK_SURFACES[surface] and Theme.Colors[DARK_SURFACES[surface]])
	end
	if not fill then
		return Theme.Colors.White
	end
	if contrast(Theme.Sign.Text, fill) > contrast(Theme.Colors.White, fill) then
		return Theme.Sign.Text
	end
	return Theme.Colors.White
end

-- (U6 review) the WCAG contrast ratio of two colours (1 .. 21)
function Theme.Contrast(a, b)
	return contrast(a, b)
end

-- (U6 review) a small face (a pill, a badge, a tab, a bar) and its ink for text that must reach `need`:1 (default 4.5,
-- small text): the colour itself with Theme.TextOn's ink when that reads; a mid tone where neither ink reads is moved the
-- least it takes, in steps of 0.04: lightened towards the pale cloud for the brown ink or darkened towards the navy shade
-- for white. whiteOnly: the ink must be white (a bar whose text also crosses its dark track), so it is only darkened.
-- -> face, ink
function Theme.ReadableFace(color, need, whiteOnly)
	need = tonumber(need) or 4.5
	local white, brown = Theme.Colors.White, Theme.Sign.Text
	local ink = whiteOnly and white or Theme.TextOn(color)
	if contrast(ink, color) >= need then
		return color, ink
	end
	for step = 1, 25 do
		local k = step * 0.04
		local dark = Theme.Darken(color, k)
		if contrast(white, dark) >= need then
			return dark, white
		end
		if not whiteOnly then
			local light = Theme.Lighten(color, k)
			if contrast(brown, light) >= need then
				return light, brown
			end
		end
	end
	return Theme.Darken(color, 1), white
end

----------------------------------------------------------------------
-- Colour helpers (shading stays navy-tinted so shadows feel cool, not muddy)
----------------------------------------------------------------------
local SHADE_TARGET = Color3.fromRGB(14, 20, 52)
local LIGHT_TARGET = Color3.fromRGB(238, 244, 255)

function Theme.Mix(a, b, t)
	return a:Lerp(b, t)
end

-- k in 0..1: how far towards the dark navy shade.
function Theme.Darken(color, k)
	return color:Lerp(SHADE_TARGET, k)
end

-- k in 0..1: how far towards soft pale cloud (never pure white).
function Theme.Lighten(color, k)
	return color:Lerp(LIGHT_TARGET, k)
end

----------------------------------------------------------------------
-- Numbers
----------------------------------------------------------------------
local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

local function trimDecimals(text)
	if text:find("%.") then
		text = text:gsub("0+$", "")
		text = text:gsub("%.$", "")
	end
	return text
end

-- Big-number display: below `fullBelow` (default 10000) with thousands separators ("9,999"), above it
-- three significant digits plus a suffix ("12.3K", "456K", "1.23M", "7B"). Digits are truncated, never
-- rounded up, so the display never claims more than the player has.
function Theme.ShortNumber(n, fullBelow)
	n = tonumber(n) or 0
	if n ~= n then -- NaN
		n = 0
	end
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end
	n = math.floor(n)
	if n < (tonumber(fullBelow) or 10000) then
		return sign .. commas(n)
	end
	local value = n
	local index = 0
	while value >= 1000 and index < #SUFFIXES do
		value = value / 1000
		index = index + 1
	end
	if index == 0 then
		return sign .. commas(n)
	end
	local text
	if value >= 100 then
		text = tostring(math.floor(value))
	elseif value >= 10 then
		text = trimDecimals(string.format("%.1f", math.floor(value * 10) / 10))
	else
		text = trimDecimals(string.format("%.2f", math.floor(value * 100) / 100))
	end
	return sign .. text .. SUFFIXES[index]
end

----------------------------------------------------------------------
-- Text + small GUI builders
----------------------------------------------------------------------

-- Thick outline around the GLYPHS of a text object (a UIStroke in Contextual mode). Reuses an existing
-- outline made by this function. Use it on labels without a border stroke (a UIStroke in Border mode
-- outlines the box instead; CloudUI puts both on its buttons).
function Theme.TextOutline(obj, thickness, color, transparency)
	if not obj then
		return nil
	end
	local outline = obj:FindFirstChild("TextOutline")
	if not (outline and outline:IsA("UIStroke")) then
		outline = Instance.new("UIStroke")
		outline.Name = "TextOutline"
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		outline.LineJoinMode = Enum.LineJoinMode.Round
		outline.Parent = obj
	end
	outline.Color = color or Theme.Colors.TextStroke
	outline.Thickness = thickness or 2
	outline.Transparency = transparency or 0
	return outline
end

-- The outline thickness of Outline = "World" per role (damage numbers read from further away than a nameplate).
local WORLD_OUTLINE = { Accent = 3, Title = 3, Sign = 3, Display = 2.5 }

-- kit B casing (U6; the owner saw LuckiestGuy's odd lower-case "e" in "PeTS"): titles, signs, accents and tags read in
-- capitals. Theme.SetRole keeps a label of these roles in capitals whatever text is set on it later; a label moved to
-- another role keeps the case of the texts set after. Buttons read in sentence case (written so by the callers).
Theme.CapsRoles = { Title = true, Sign = true, Accent = true, Tag = true }

-- `text` in capitals outside rich text tags ("<font ...>") and entities ("&amp;"); ASCII letters only, every other byte
-- (UTF-8 symbols) stays.
function Theme.Caps(text)
	text = tostring(text or "")
	local out, pos = {}, 1
	while true do
		local s = text:find("[<&]", pos)
		if not s then
			break
		end
		local e
		if text:sub(s, s) == "<" then
			e = text:find(">", s, true)
		else
			local _, last = text:find("^&#?%w+;", s)
			e = last
		end
		if e then
			out[#out + 1] = text:sub(pos, s - 1):upper()
			out[#out + 1] = text:sub(s, e)
			pos = e + 1
		else
			out[#out + 1] = text:sub(pos, s):upper() -- a lone "<" or "&"
			pos = s + 1
		end
	end
	out[#out + 1] = text:sub(pos):upper()
	return table.concat(out)
end

-- labels already listening for their text (weak keys: the label owns its connection)
local capsHooked = setmetatable({}, { __mode = "k" })

local function keepCaps(obj)
	if obj:IsA("TextBox") then
		return -- what a player types stays as typed
	end
	local now = Theme.Caps(obj.Text)
	if obj.Text ~= now then
		obj.Text = now
	end
	if capsHooked[obj] then
		return
	end
	capsHooked[obj] = true
	obj:GetPropertyChangedSignal("Text"):Connect(function()
		if Theme.CapsRoles[obj:GetAttribute("FontRole")] then
			local caps = Theme.Caps(obj.Text)
			if obj.Text ~= caps then
				obj.Text = caps
			end
		end
	end)
end

-- Puts a role's font on a text object and nothing else (colour, size and stroke stay): the Enum font (which also resets
-- FontFace, so a label leaving a face role loses its Nunito face), then the role's FontFace when it has one, and stamps
-- the role on it (attribute FontRole, read by Theme.FontOf). Use it instead of `obj.Font = Theme.Fonts.X`, which would
-- drop a FontFace. A Theme.CapsRoles role keeps the text in capitals. An unknown role is Body. Returns obj.
function Theme.SetRole(obj, role)
	if not obj then
		return nil
	end
	if not Theme.Fonts[role] then
		role = "Body"
	end
	obj.Font = Theme.Fonts[role]
	Theme.Face(obj, role)
	obj:SetAttribute("FontRole", role)
	if Theme.CapsRoles[role] then
		keepCaps(obj)
	end
	return obj
end

-- the role Theme.SetRole stamped on obj; Body when there is none
local function stampedRole(obj)
	local ok, role = pcall(function()
		return obj:GetAttribute("FontRole")
	end)
	if ok and Theme.Fonts[role] then
		return role
	end
	return "Body"
end

-- The Enum font to measure a text object with (TextService:GetTextSize takes only an Enum.Font). A label whose FontFace
-- has no Enum twin (Nunito ExtraBold, Nunito Bold Italic) reads .Font = Enum.Font.Unknown in Roblox, and GetTextSize
-- throws on Unknown; then its stamped role's Enum fallback (Body's when it has none). Any other label answers its own
-- .Font. Use it wherever a fit helper would read lbl.Font.
function Theme.FontOf(obj)
	local f = obj and obj.Font
	if f and f ~= Enum.Font.Unknown then
		return f
	end
	return Theme.Fonts[stampedRole(obj)]
end

-- The size of a text object's text (or `text`) at its TextSize (or `size`), wrapped at `width` when given: Theme.Measure
-- with its role when it draws a face (.Font reads Unknown; the role's spare widening), else GetTextSize with its own
-- Enum font. Returns a Vector2.
function Theme.MeasureLabel(obj, text, size, width)
	if text == nil then
		text = obj and obj.Text or ""
	end
	if obj and Theme.CapsRoles[stampedRole(obj)] then
		text = Theme.Caps(text) -- (U6) what the label will show
	end
	size = tonumber(size) or (obj and obj.TextSize) or nil
	local f = obj and obj.Font
	if f and f ~= Enum.Font.Unknown then
		local frame = Vector2.new(tonumber(width) or 100000, 100000)
		return game:GetService("TextService"):GetTextSize(tostring(text), size or 14, f, frame)
	end
	return Theme.Measure(text, stampedRole(obj), size, width)
end

-- Apply a font role (and an outline when asked) to any TextLabel/TextButton/TextBox.
-- kit B rule: text reads by the contrast of its surface (Theme.TextOn), so there is no stroke unless the caller asks.
-- opts: Size (design px; default Theme.Sizes[role]), Color, Scaled (bool), Outline (a thickness: adds Theme.TextOutline;
--       "World": text over the 3D world with no plate, one outline of the role's world thickness), OutlineThickness (with
--       "World"), OutlineColor (StrokeColor is read as the outline colour when OutlineColor is not given).
--       Stroke and OnLight are kept for old callers and do nothing (U6: kit B has no classic text stroke; the label's own
--       stroke is cleared, so a restyled label never ends with a stroke under its outline).
function Theme.Style(obj, role, opts)
	opts = opts or {}
	Theme.SetRole(obj, role)
	obj.TextColor3 = opts.Color or Theme.Colors.White
	obj.TextStrokeColor3 = opts.StrokeColor or Theme.Colors.Ink
	local world = opts.Outline == "World"
	obj.TextStrokeTransparency = 1
	if opts.Scaled then
		obj.TextScaled = true
	elseif opts.Size then
		obj.TextSize = opts.Size
	else
		obj.TextSize = Theme.RoleSize(role)
	end
	if opts.Outline then
		local thickness
		if world then
			thickness = tonumber(opts.OutlineThickness) or WORLD_OUTLINE[role] or 2
		else
			thickness = tonumber(opts.Outline) or 2
		end
		Theme.TextOutline(obj, thickness, opts.OutlineColor or opts.StrokeColor or Theme.Colors.TextStroke, 0)
	end
	return obj
end

-- The size of `text` in a role's font at `size` px (wrapped at `width` when given): TextService:GetTextSize with the role's
-- Enum font, X widened by Theme.MeasureSpare for a FontFace role and rounded up (TextService does not know FontFace;
-- GetTextBoundsAsync does, but it yields). A wrap width is narrowed by the same factor, so the rows counted are the wider
-- face's. An unknown role measures as Body; a Theme.CapsRoles role measures the text in capitals. `role` may also be an Enum.Font (U6: the old GetTextSize helpers pass the
-- font they read): measured 1:1 with that font, and Enum.Font.Unknown (a Nunito face read back) as Body. Returns a Vector2.
function Theme.Measure(text, role, size, width)
	if typeof(role) == "EnumItem" and role ~= Enum.Font.Unknown then
		local frame = Vector2.new(tonumber(width) or 100000, 100000)
		return game:GetService("TextService"):GetTextSize(tostring(text or ""), tonumber(size) or 14, role, frame)
	end
	if not Theme.Fonts[role] then
		role = "Body"
	end
	text = tostring(text or "")
	if Theme.CapsRoles[role] then
		text = Theme.Caps(text) -- (U6) a caps role shows its text in capitals
	end
	size = tonumber(size) or Theme.RoleSize(role)
	local spare = Theme.MeasureSpare[role] or 1
	local frame = Vector2.new(tonumber(width) and (tonumber(width) / spare) or 100000, 100000)
	local raw = game:GetService("TextService"):GetTextSize(text, size, Theme.Fonts[role], frame)
	return Vector2.new(math.ceil(raw.X * spare), raw.Y)
end

-- T0: the one title treatment. Every window title (CloudUI.Panel, SignKit.Header with the Title role, the windows that
-- draw their own header title, the loading board) is passed here after it is styled, so a designed title look (gradient,
-- border, shadow) is added in this one place. Today it adds nothing: it stamps attribute TitleLook = "Plain" (the look in
-- use) and leaves the label as it was. Safe to call twice. Returns the label.
-- T0 review: a Title-role heading that is NOT a window's name passes a kind from Theme.TitleExempt (each with its reason):
-- StyleTitle(label, kind) stamps TitleLook = kind and never gives it the window title look, so a run-time walk
-- (smoke_kitb_ui kitb_titles_stamped) tells a heading skipped on purpose from a window title someone forgot.
Theme.TitleExempt = {
	Section = "a section head or an empty-state line inside a window (Best times, Quick match, Elements, a Home section): "
		.. "the window's own title carries the title look, its sections stay plain under it",
	OwnGradient = "a headline that paints its own gradient over white text (the race result's VICTORY! / DEFEAT, the HUD's "
		.. "game-name card); a second title treatment would fight that gradient",
}
function Theme.StyleTitle(label, kind)
	if not label then
		return nil
	end
	label:SetAttribute("TitleLook", kind or "Plain")
	return label
end

-- Build a styled TextLabel. props are applied after styling so you can override anything.
-- Theme.Label("Hello", "Title", {Size = 36, Outline = 2, Props = {Position = UDim2.new(0, 0, 0, 0)}})
function Theme.Label(text, role, opts)
	opts = opts or {}
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	Theme.Style(label, role, opts)
	if opts.Props then
		for key, value in pairs(opts.Props) do
			label[key] = value
		end
	end
	return label
end

-- Puts the FontFace role `role` (Theme.Faces) on a text object; false when that face is not available.
function Theme.Face(obj, role)
	local f = Theme.Faces[role]
	if not (obj and f) then
		return false
	end
	return (pcall(function()
		obj.FontFace = f
	end))
end

-- radius: a UDim, a number of px, a Theme.Radius token name ("None", "S", "M") or "Round" (a pill / disc); default 12 px
-- (the swept files always name a token).
function Theme.Corner(parent, radius)
	if radius == "Round" then
		radius = UDim.new(0.5, 0)
	elseif type(radius) == "string" then
		radius = Theme.Radius[radius] or 0
	end
	if type(radius) == "number" then
		radius = UDim.new(0, radius)
	end
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
	return c
end

function Theme.Stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.Colors.Ink
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0.2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Vertical two-colour gradient on a GuiObject.
function Theme.Gradient(parent, top, bottom, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- Rounded dark card used for compact HUD elements (windows use CloudUI.Panel). v3: a solid card (text on
-- it always reads), a thick navy outline and a soft top-to-bottom gradient.
function Theme.Panel(props)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Colors.White
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	Theme.Corner(frame, UDim.new(0, 14))
	Theme.Stroke(frame, Theme.Colors.Navy, 3, 0)
	Theme.Gradient(frame, Theme.Colors.PanelLight, Theme.Colors.Panel, 90)
	if props then
		for key, value in pairs(props) do
			frame[key] = value
		end
	end
	return frame
end

return Theme
