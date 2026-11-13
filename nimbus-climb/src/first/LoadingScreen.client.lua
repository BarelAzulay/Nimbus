pcall(function() game:GetService("ReplicatedFirst"):RemoveDefaultLoadingScreen() end)
-- LoadingScreen (ReplicatedFirst; ARCHITECTURE_V3.md "Phase 5 build contract" 7.1). Roblox runs it before every other
-- client script, so it may only use what is already there: ReplicatedStorage.Shared (Config, Theme, SignKit, PixelIcon,
-- TextureIds, UpdateNotes) and plain Roblox services. Never a PlayerScripts module (boot order, m13).
--
-- kit B (U3 of .superpowers/slop-audit/round3/BUILD_PLAN.md; finding 4, sky F11; the owner's approved pitch,
-- kit_pitch_mockups.html "B. Cloud Shop Signboard", loading thumbnail): ScreenGui "NimbusLoading" (DisplayOrder 100,
-- IgnoreGuiInset, ResetOnSpawn false) over a flat day sky (127,196,242) -> (207,234,252) with stepped cloud puffs (3-4
-- stacked Frames, each row 12 px narrower on each side, no corners). A Signboard hangs from the top of the screen on two
-- ropes: the flat pink awning, the navy header plank, the 6 px wood frame round the stone body; width min(0.5 W, 620
-- design px) and at least 480, the screen less a 16 px gutter on each side on a portrait phone (below 700 px wide). On a
-- short screen the header, padding and tag line shrink until the swinging board ends above the tip card. It swings
-- +-1.5 deg (Sine, 3.2 s); nothing else moves. (sign build) Once SignKit is there the board wears SignKit.Workshop's
-- trim like the title screen's (grain, nails, rope rings, the striped awning's notched lip, a chipped corner).
--   * Before Shared.Theme replicates: the sky, the clouds and the whole board (no text), drawn with this script's own copy
--     of the few Theme.Sign tokens and SignKit sizes it needs (smoke loading_tokens_match_theme pins them equal).
--   * Once Theme (and SignKit, PixelIcon) exist: "NIMBUS CLIMB" in LuckiestGuy gold on the navy plank (no outline), the
--     tag line (Config.Tagline, Nunito italic), 12 stone blocks that turn gold one by one with a 0.12 s pop, the caption
--     "Loading the sky... 64%" (FredokaOne; session lock, 2026-11-10: "Another server is still saving your progress..."
--     while the player attribute SaveWaiting is true), a tip from UpdateNotes.Tips in a SignKit.Notice with the pixel bulb
--     (a random first one, then the next every 5 s), and SKIP, a SignKit plank with the pixel arrow, after
--     Config.Loading.SkipAfter (6) seconds.
--   * The owner's picks (morning, uploads): the TextureIds keys named in Config.Loading.Images. A key with no id (tonight:
--     all three) leaves its fallback; with an id the logo image replaces the typed title, the lobby render replaces the
--     drawn sky and clouds, the mascot hops along the gold blocks.
-- Everything is laid out in design px of a 1080p screen under one UIScale (Theme.ScreenFactor's rule), again whenever the
-- viewport changes.
--
-- Progress = 5 weighted stages, each 0..1; the gui attribute Progress only moves forward and the blocks and caption
-- draw from it:
--   game loaded 0.30 (game:IsLoaded()) | shared modules 0.10 (Config, Theme, Util, Voxel present)
--   lobby replicated 0.30 (BaseParts under workspace.NimbusLobby vs its PartCount attribute; counted once, then by
--     DescendantAdded; after game:IsLoaded() a lobby / PartCount that is not there counts as done: the initial
--     replication is complete) | assets 0.15 (ContentProvider:PreloadAsync of the Sky and this gui)
--   profile 0.15 (the player attribute ProfileLoaded = true, written by DataService when the profile is loaded or
--     provisional)
-- Finish at 100%, at Config.Loading.MaxSeconds (25) or on SKIP: attribute Done = true on the gui. MainMenuController
-- fades it and destroys it; with the menu disabled (Config.MainMenu.Enabled ~= true) this script fades it (0.8 s) after
-- 2 s itself, and it also does so 12 s after Done if nobody took it (a menu that failed to load).
-- One 0.25 s poll loop that ends at Done; no per-frame work. Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	return
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local L = {
	POLL = 0.25,
	TIP_EVERY = 5,
	SELF_FADE = 2, -- seconds after Done when no main menu runs
	ORPHAN_FADE = 12, -- seconds after Done when the menu should take it but never does
	FADE = 0.8,
	BLOCKS = 12,
	POP = 0.12, -- one block turns gold every POP seconds, lifting 4 px and dropping back
	SWING = 1.5, -- degrees each way
	SWING_TIME = 3.2,
	SKY_TOP = rgb(127, 196, 242),
	SKY_BOTTOM = rgb(207, 234, 252),
	CLOUD = rgb(255, 255, 255),
	CLOUD_SHADE = rgb(207, 230, 248), -- the pitch's cloud underside (#CFE6F8)
	-- the kit B tokens the board needs before Shared.Theme exists: a copy of Theme.Sign (smoke loading_tokens_match_theme)
	SIGN = {
		Stone = rgb(255, 247, 230),
		StoneLip = rgb(220, 201, 160),
		Wood = rgb(140, 90, 46),
		Navy = rgb(35, 42, 110),
		Gold = rgb(255, 210, 74),
		GoldLip = rgb(201, 154, 30),
		Roof = rgb(238, 111, 166),
		RoofEdge = rgb(122, 42, 82),
		RoofLip = rgb(196, 74, 130),
		Post = rgb(196, 138, 78),
		Text = rgb(59, 36, 18),
		TextMuted = rgb(118, 84, 54),
	},
	-- ...and of the SignKit.Sizes it draws with (same pin)
	ROOF_H = 18,
	ROOF_EDGE = 4,
	ROOF_LIP = 5,
	RIM = 6,
	FRAME = 6,
	LIP = 8,
	ROPE_W = 6,
	BLOCK_EDGE = 2,
	BLOCK_LIP = 4,
	SKIP_W = 150,
	SKIP_H = 56,
	-- the cloud puffs: x, y (of the screen), bottom row width (design px), rows
	PUFFS = {
		{ 0.07, 0.17, 168, 3 }, { 0.9, 0.12, 192, 4 }, { 0.2, 0.42, 120, 3 }, { 0.83, 0.47, 144, 3 },
		{ 0.04, 0.74, 216, 4 }, { 0.95, 0.8, 168, 3 }, { 0.32, 0.93, 240, 4 }, { 0.66, 0.97, 192, 3 },
	},
	IMAGES = { Logo = "nimbus_logo", Backdrop = "ui_loading_lobby", Mascot = "ui_mascot_hop" },
	WEIGHTS = { Loaded = 0.30, Shared = 0.10, Lobby = 0.30, Assets = 0.15, Profile = 0.15 },
	STAGES = { "Loaded", "Shared", "Lobby", "Assets", "Profile" },
	SHARED = { "Config", "Theme", "Util", "Voxel" },
}
local SIGN = L.SIGN

-- live state (tests read it through the gui's attributes: Progress, Done, Tip)
local St = {
	Stage = { Loaded = 0, Shared = 0, Lobby = 0, Assets = 0, Profile = 0 },
	Shown = 0, -- the progress shown (never goes down)
	Blocks = 0, -- gold blocks drawn
	BlockTarget = 0,
	Stepping = false,
	Done = false,
	Elapsed = 0,
	TipIndex = 0,
	TipAt = 0,
	Lobby = nil, -- the NimbusLobby being counted
	LobbyParts = 0,
	LobbyConn = nil,
	Ui = {},
	Geo = {}, -- the last layout (design px)
	Images = {}, -- Logo / Backdrop / Mascot -> "rbxassetid://<id>" for the picks that have an id
	Theme = nil,
	Config = nil,
	Tips = {},
	Waiting = false, -- session lock: the player attribute SaveWaiting (another server still saves the progress)
}

----------------------------------------------------------------------
-- the gui: sky, clouds and the board at once (no text until Theme arrives)
----------------------------------------------------------------------

local function make(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function block(name, colour, props, parent)
	props.Name = name
	props.BackgroundColor3 = colour
	props.BorderSizePixel = 0
	return make("Frame", props, parent)
end

local function kit(obj, kind)
	obj:SetAttribute("SignKit", kind)
	return obj
end

local function viewport()
	local camera = Workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if size.X < 2 or size.Y < 2 then
		size = Vector2.new(1920, 1080)
	end
	return size
end

-- Theme.ScreenFactor's rule, here before Theme exists: clamp(H / 1080, 0.8, 1.25)
local function factor(height)
	return math.max(0.8, math.min(1.25, height / 1080))
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local gui = make("ScreenGui", {
	Name = "NimbusLoading",
	DisplayOrder = 100,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
gui:SetAttribute("Progress", 0)
gui:SetAttribute("Done", false)

local function buildSkeleton()
	local ui = St.Ui
	ui.Sky = make("Frame", {
		Name = "Sky",
		BackgroundColor3 = L.CLOUD,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = true, -- swallows clicks meant for the world behind
	}, gui)
	make("UIGradient", { Color = ColorSequence.new(L.SKY_TOP, L.SKY_BOTTOM), Rotation = 90 }, ui.Sky)

	-- the stepped puffs: each row a plain Frame 12 px narrower on each side than the one under it, a pale underside
	ui.Clouds = make("Frame", { Name = "Clouds", BackgroundTransparency = 1, ZIndex = 2 }, ui.Sky)
	ui.CloudScale = make("UIScale", { Name = "ReadScale" }, ui.Clouds)
	for i, p in ipairs(L.PUFFS) do
		local w, rows = p[3], p[4]
		local puff = make("Frame", {
			Name = "Puff" .. i,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(p[1], p[2]),
			Size = UDim2.fromOffset(w, rows * 14 + 6),
			ZIndex = 2,
		}, ui.Clouds)
		block("Shade", L.CLOUD_SHADE, { Position = UDim2.fromOffset(0, rows * 14), Size = UDim2.fromOffset(w, 6), ZIndex = 2 }, puff)
		for r = 1, rows do
			block("Row" .. r, L.CLOUD, {
				Position = UDim2.fromOffset(12 * (r - 1), (rows - r) * 14),
				Size = UDim2.fromOffset(w - 24 * (r - 1), 14),
				ZIndex = 2,
			}, puff)
		end
	end

	-- everything else: design px under one UIScale
	ui.Content = make("Frame", { Name = "Content", BackgroundTransparency = 1, ZIndex = 5 }, ui.Sky)
	ui.ReadScale = make("UIScale", { Name = "ReadScale" }, ui.Content)
	ui.Swing = make("Frame", {
		Name = "Swing",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Rotation = -L.SWING,
		ZIndex = 5,
	}, ui.Content)
	ui.Ropes = {}
	for i = 1, 2 do
		local rope = kit(block("Rope", SIGN.Post, { Size = UDim2.fromOffset(L.ROPE_W, 60), ZIndex = 1 }, ui.Swing), "Rope")
		block("Shade", SIGN.Wood, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, math.max(1, math.floor(L.ROPE_W / 3)), 1, 0),
			ZIndex = 1,
		}, rope)
		ui.Ropes[i] = rope
	end
	ui.Board = make("Frame", { Name = "Board", BackgroundTransparency = 1, ZIndex = 2 }, ui.Swing)

	-- the flat awning (SignKit.Roof): a fixed size, wider than the board
	ui.Roof = kit(block("Roof", SIGN.RoofEdge, { ZIndex = 3 }, ui.Board), "Roof")
	local face = block("Face", SIGN.Roof, {
		Position = UDim2.fromOffset(L.ROOF_EDGE, L.ROOF_EDGE),
		Size = UDim2.new(1, -2 * L.ROOF_EDGE, 1, -2 * L.ROOF_EDGE),
		ZIndex = 3,
	}, ui.Roof)
	block("Lip", SIGN.RoofLip, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, L.ROOF_LIP),
		ZIndex = 3,
	}, face)

	-- the navy header plank in its wood rim (SignKit.Header)
	ui.Head = kit(block("Head", SIGN.Wood, { ZIndex = 2 }, ui.Board), "Header")
	ui.Plate = block("Plate", SIGN.Navy, {
		Position = UDim2.fromOffset(L.RIM, L.RIM),
		Size = UDim2.new(1, -2 * L.RIM, 1, -L.RIM),
		ZIndex = 2,
	}, ui.Head)

	-- the wood frame and the stone body with its lip (SignKit.Frame / Body)
	ui.Wood = kit(block("Wood", SIGN.Wood, { ZIndex = 1 }, ui.Board), "Frame")
	ui.Body = kit(block("Body", SIGN.Stone, {
		Position = UDim2.fromOffset(L.FRAME, L.FRAME),
		Size = UDim2.new(1, -2 * L.FRAME, 1, -2 * L.FRAME),
		ZIndex = 1,
	}, ui.Wood), "Body")
	block("Lip", SIGN.StoneLip, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, L.LIP),
		ZIndex = 1,
	}, ui.Body)

	-- the progress: 12 stone blocks with a darker lip (SignKit.BlockRow)
	ui.Row = kit(make("Frame", { Name = "BlockRow", BackgroundTransparency = 1, ZIndex = 2 }, ui.Body), "BlockRow")
	ui.Row:SetAttribute("Count", L.BLOCKS)
	ui.Row:SetAttribute("Filled", 0)
	for i = 1, L.BLOCKS do
		local b = block("Block" .. i, SIGN.Wood, { ZIndex = 2 }, ui.Row)
		local bf = block("Face", SIGN.Stone, {
			Position = UDim2.fromOffset(L.BLOCK_EDGE, L.BLOCK_EDGE),
			Size = UDim2.new(1, -2 * L.BLOCK_EDGE, 1, -2 * L.BLOCK_EDGE),
			ZIndex = 2,
		}, b)
		block("Lip", SIGN.StoneLip, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, L.BLOCK_LIP),
			ZIndex = 2,
		}, bf)
	end

	ui.SwingTween = TweenService:Create(ui.Swing, TweenInfo.new(L.SWING_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Rotation = L.SWING,
	})
	ui.SwingTween:Play()
end

----------------------------------------------------------------------
-- layout (design px of a 1080p screen; again on a viewport change, when the tip card or the mascot arrives)
----------------------------------------------------------------------

local function layout()
	local ui, Theme = St.Ui, St.Theme
	local vp = viewport()
	local f = factor(vp.Y)
	local dw, dh = vp.X / f, vp.Y / f
	-- a portrait phone: the full-width board, SKIP above the tip card (a landscape phone keeps SKIP beside the card,
	-- unless that leaves the card too thin)
	local narrow = vp.X < 700 and (vp.X < vp.Y or dw - 2 * (L.SKIP_W + 48) < 360)
	for _, pair in ipairs({ { ui.Clouds, ui.CloudScale }, { ui.Content, ui.ReadScale } }) do
		pair[1].Size = UDim2.fromOffset(math.floor(dw + 0.5), math.floor(dh + 0.5))
		pair[2].Scale = f
	end

	-- the tip card and SKIP along the bottom (SKIP above the card on a narrow screen)
	local tipW = narrow and math.floor(dw - 40) or math.floor(math.min(760, dw - 2 * (L.SKIP_W + 48)))
	local tipSize = narrow and 18 or 19
	local tipH = narrow and 116 or 80
	if Theme and ui.Tip and #St.Tips > 0 then
		-- tall enough for the longest tip: its one-line width over the text box, plus a line for word breaks
		local lines = 1
		for _, tip in ipairs(St.Tips) do
			local ok, size = pcall(Theme.Measure, tip, "Body", tipSize)
			if ok and size then
				lines = math.max(lines, math.ceil(size.X / (tipW - 76) + 0.25)) -- the card less the bulb, its gap and the edges
			end
		end
		tipH = math.max(64, math.ceil(lines * tipSize * 1.25) + 28)
	end
	local tipTop = dh - 20 - tipH
	local bottom = narrow and (tipTop - 24 - L.SKIP_H) or (tipTop - 16)

	-- the board: min(0.5 W, 620 design px) but never under 480 (the title's room on a portrait tablet), within the 16 px
	-- gutter; the screen less the gutter on a narrow screen
	local boardW = math.floor(dw - 32 / f)
	if not narrow then
		boardW = math.floor(math.min(boardW, math.max(480, math.min(0.5 * vp.X, 620 * f) / f)))
	end
	local inner = boardW - 2 * L.FRAME
	local droop = math.ceil(0.5 * boardW * math.sin(math.rad(L.SWING))) -- a lower corner at the end of the swing
	local minTop = math.ceil(58 / f) + 12 -- below Roblox's top bar
	-- on a short screen (a 360 px landscape phone) step down until the swinging board ends above `bottom`: 1 a slimmer
	-- header and padding, 2 also no tag line; past that it may hang higher, into the top bar's height
	local headH, titleSize, pad, gap, bw, bh, rowW, compact, capH, tagY, tagH, rowY, capY, bodyH, woodH, boardH
	local headY = L.ROOF_H - 3
	for short = 0, 2 do
		local slim = narrow or short >= 1
		headH = slim and 64 or 84
		titleSize = slim and 44 or 64
		pad = slim and 12 or 18
		gap = slim and 4 or 6
		bw = math.min(40, math.floor((inner - 2 * pad - (L.BLOCKS - 1) * gap) / L.BLOCKS))
		bh = math.floor(bw * 0.8)
		rowW = L.BLOCKS * bw + (L.BLOCKS - 1) * gap
		compact = boardW < 600 -- the session-lock caption takes two lines there
		capH = compact and 52 or 30
		tagY, tagH = pad - 4, short >= 2 and 0 or 26
		rowY = (tagH > 0 and (tagY + tagH + 10) or pad) + (St.Images.Mascot and 36 or 0)
		capY = rowY + bh + 6
		bodyH = capY + capH + pad - 6 + L.LIP
		woodH = bodyH + 2 * L.FRAME
		boardH = headY + headH + woodH
		if minTop + boardH + droop <= bottom then
			break
		end
	end
	local topY = math.max(minTop, math.floor((bottom - boardH) * 0.45))
	if topY + boardH + droop > bottom then
		topY = math.max(8, bottom - boardH - droop)
	end
	St.Geo = { BoardW = boardW, BlockW = bw, Gap = gap, RowY = rowY, RowX = math.floor((inner - rowW) / 2) }

	local half = topY + boardH
	local sideX = 32
	ui.Swing.Size = UDim2.fromOffset(boardW + 2 * sideX, 2 * half)
	ui.Board.Position = UDim2.fromOffset(sideX, half + topY)
	ui.Board.Size = UDim2.fromOffset(boardW, boardH)
	for i, rope in ipairs(ui.Ropes) do
		local x = sideX + math.floor((i == 1 and 0.18 or 0.82) * boardW) - L.ROPE_W / 2
		rope.Position = UDim2.fromOffset(x, half - 12)
		rope.Size = UDim2.fromOffset(L.ROPE_W, topY + 20)
	end
	ui.Roof.Position = UDim2.fromOffset(-12, 0)
	ui.Roof.Size = UDim2.fromOffset(boardW + 24, L.ROOF_H)
	ui.Head.Position = UDim2.fromOffset(0, headY)
	ui.Head.Size = UDim2.fromOffset(boardW, headH)
	ui.Wood.Position = UDim2.fromOffset(0, headY + headH)
	ui.Wood.Size = UDim2.fromOffset(boardW, woodH)
	ui.Row.Position = UDim2.fromOffset(St.Geo.RowX, rowY)
	ui.Row.Size = UDim2.fromOffset(rowW, bh)
	for i = 1, L.BLOCKS do
		local b = ui.Row:FindFirstChild("Block" .. i)
		b.Position = UDim2.fromOffset((i - 1) * (bw + gap), 0)
		b.Size = UDim2.fromOffset(bw, bh)
	end
	if ui.Title then
		-- stepped down until it fits the plate with 12 px each side
		local room = boardW - 2 * L.RIM - 24
		while titleSize > 24 do
			local ok, size = pcall(Theme.Measure, ui.Title.Text, "Title", titleSize)
			if not ok or not size or size.X <= room then
				break
			end
			titleSize = titleSize - 2
		end
		ui.Title.TextSize = titleSize
	end
	if ui.Tagline then
		ui.Tagline.Visible = tagH > 0
		ui.Tagline.Position = UDim2.fromOffset(pad, tagY)
		ui.Tagline.Size = UDim2.fromOffset(inner - 2 * pad, math.max(tagH, 1))
	end
	if ui.Caption then
		ui.Caption.Position = UDim2.fromOffset(pad, capY)
		ui.Caption.Size = UDim2.fromOffset(inner - 2 * pad, capH)
		ui.Caption.TextSize = compact and 20 or 22
	end
	if ui.TipCard then
		ui.TipCard.Position = UDim2.fromOffset(math.floor(dw / 2), math.floor(dh - 20))
		ui.TipCard.Size = UDim2.fromOffset(tipW, tipH)
		ui.Tip.TextSize = tipSize
	end
	if ui.Skip then
		if narrow then
			ui.Skip.Position = UDim2.fromOffset(math.floor(dw - 20), math.floor(tipTop - 12))
		else
			ui.Skip.Position = UDim2.fromOffset(math.floor(dw - 24), math.floor(dh - 24))
		end
	end
	if ui.Mascot then
		ui.Mascot.Position = UDim2.fromOffset(St.Geo.RowX + math.max(0, St.Blocks - 0.5) * (bw + gap), rowY)
	end
	-- (sign build) the owner's "Workshop" trim (SignKit.Workshop, once SignKit is there), drawn again when the board's
	-- width changes (its awning's stripes and notched lip are cut to the width)
	if St.Kit and St.TrimW ~= boardW then
		St.TrimW = boardW
		St.Kit.Workshop({ Roof = ui.Roof, Head = ui.Head, Frame = ui.Wood, Ropes = ui.Ropes })
	end
end

----------------------------------------------------------------------
-- the picks' images (Config.Loading.Images keys in TextureIds; none has an id tonight)
----------------------------------------------------------------------

local function applyImages(ids)
	local names = (St.Config and type(St.Config.Loading) == "table" and type(St.Config.Loading.Images) == "table" and St.Config.Loading.Images) or L.IMAGES
	for role, key in pairs(names) do
		local id = type(ids) == "table" and tonumber(ids[key]) or nil
		if id and id > 0 then
			St.Images[role] = "rbxassetid://" .. tostring(id)
		end
	end
	local ui = St.Ui
	if St.Images.Backdrop and not ui.Backdrop then
		ui.Backdrop = make("ImageLabel", {
			Name = "Backdrop",
			BackgroundTransparency = 1,
			Image = St.Images.Backdrop,
			ScaleType = Enum.ScaleType.Crop,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}, ui.Sky)
		ui.Clouds.Visible = false
	end
	if St.Images.Logo and not ui.Logo then
		ui.Logo = make("ImageLabel", {
			Name = "Logo",
			BackgroundTransparency = 1,
			Image = St.Images.Logo,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -16, 1, -8),
			ZIndex = 3,
		}, ui.Plate)
		if ui.Title then
			ui.Title.Visible = false
		end
	end
	if St.Images.Mascot and not ui.Mascot then
		ui.Mascot = make("ImageLabel", {
			Name = "Mascot",
			BackgroundTransparency = 1,
			Image = St.Images.Mascot,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(34, 34),
			ZIndex = 4,
		}, ui.Body)
	end
	layout()
end

----------------------------------------------------------------------
-- the text, the tip card and SKIP (after Theme, on SignKit and PixelIcon)
----------------------------------------------------------------------

local function label(name, text, role, size, colour, props, parent)
	local obj = make("TextLabel", { Name = name, BackgroundTransparency = 1, Text = text }, parent)
	St.Theme.Style(obj, role, { Size = size, Color = colour })
	for key, value in pairs(props) do
		obj[key] = value
	end
	return obj
end

local function buildText(SignKit, PixelIcon)
	local ui, Sign = St.Ui, St.Theme.Sign
	ui.Title = label("Title", "NIMBUS CLIMB", "Title", 64, Sign.Gold, {
		Size = UDim2.fromScale(1, 1),
		Visible = St.Images.Logo == nil,
		ZIndex = 3,
	}, ui.Plate)
	-- the game's tag line (Config.Tagline; St.Config is nil when Config failed to load)
	local tagline = (St.Config and type(St.Config.Tagline) == "string" and St.Config.Tagline) or "Climb the storm. Together."
	ui.Tagline = label("Tagline", tagline, "Script", 20, Sign.TextMuted, { ZIndex = 2 }, ui.Body)
	ui.Caption = label("Caption", "Loading the sky... 0%", "Heading", 22, Sign.Text, { TextWrapped = true, ZIndex = 2 }, ui.Body)
	if not (SignKit and PixelIcon) then
		return
	end
	St.Kit = type(SignKit.Workshop) == "function" and SignKit or nil -- (sign build) layout() draws the workshop trim
	-- the tip: a small wood-framed stone card with the pixel bulb on a gold chip
	local card, face = SignKit.Notice(ui.Content, {
		Name = "TipCard",
		Text = "",
		IconSlot = true,
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 5,
	})
	ui.TipCard = card
	ui.Tip = face:FindFirstChild("Text")
	if ui.Tip then
		ui.Tip.Name = "Tip"
	end
	local slot = face:FindFirstChild("IconSlot")
	if slot then
		slot.BackgroundTransparency = 0
		slot.BackgroundColor3 = Sign.Gold
		local icon = PixelIcon.New(slot, "bulb", 27, Sign.Text)
		if icon then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	-- SKIP: a stone plank with the pixel arrow (bottom-right; above the tip card on a narrow screen)
	ui.Skip = SignKit.Plank(ui.Content, {
		Name = "Skip",
		Text = "SKIP",
		Style = "Stone",
		IconSlot = true,
		Width = L.SKIP_W,
		Height = L.SKIP_H,
		AnchorPoint = Vector2.new(1, 1),
		Visible = false,
		ZIndex = 8,
		Callback = function()
			St.Skipped = true
		end,
	})
	local iconSlot = ui.Skip:FindFirstChild("IconSlot", true)
	if iconSlot then
		local arrow = PixelIcon.New(iconSlot, "arrow", 27, Sign.Text)
		if arrow then
			arrow.AnchorPoint = Vector2.new(0.5, 0.5)
			arrow.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
end

----------------------------------------------------------------------
-- progress
----------------------------------------------------------------------

local function countLobby(lobby)
	if St.Lobby == lobby then
		return
	end
	if St.LobbyConn then
		St.LobbyConn:Disconnect()
	end
	St.Lobby = lobby
	local n = 0
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	St.LobbyParts = n
	St.LobbyConn = lobby.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			St.LobbyParts = St.LobbyParts + 1
		end
	end)
end

local function measure()
	local loaded = game:IsLoaded()
	St.Stage.Loaded = loaded and 1 or 0
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local have = 0
	for _, name in ipairs(L.SHARED) do
		if shared and shared:FindFirstChild(name) then
			have = have + 1
		end
	end
	St.Stage.Shared = have / #L.SHARED
	local lobby = Workspace:FindFirstChild("NimbusLobby")
	local total = lobby and lobby:GetAttribute("PartCount") or nil
	if lobby and type(total) == "number" and total > 0 then
		countLobby(lobby)
		St.Stage.Lobby = math.min(1, St.LobbyParts / total)
	elseif loaded then
		St.Stage.Lobby = 1
	end
	local attr = (St.Config and St.Config.Attr and St.Config.Attr.ProfileLoaded) or "ProfileLoaded"
	St.Stage.Profile = LocalPlayer:GetAttribute(attr) == true and 1 or 0
	local sum = 0
	for _, name in ipairs(L.STAGES) do
		sum = sum + L.WEIGHTS[name] * St.Stage[name]
	end
	return sum
end

local function paintBlock(i, on)
	local b = St.Ui.Row:FindFirstChild("Block" .. i)
	local face = b and b:FindFirstChild("Face")
	if face then
		face.BackgroundColor3 = on and SIGN.Gold or SIGN.Stone
		local lip = face:FindFirstChild("Lip")
		if lip then
			lip.BackgroundColor3 = on and SIGN.GoldLip or SIGN.StoneLip
		end
	end
end

local function blocksShown(k)
	St.Blocks = k
	St.Ui.Row:SetAttribute("Filled", k)
	local mascot = St.Ui.Mascot
	if mascot then
		local g = St.Geo
		local at = UDim2.fromOffset(g.RowX + math.max(0, k - 0.5) * (g.BlockW + g.Gap), g.RowY)
		mascot.Position = at
		TweenService:Create(mascot, TweenInfo.new(L.POP, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
			Position = at + UDim2.fromOffset(0, -10),
		}):Play()
	end
end

-- one block at a time towards the target, each lifting 4 px and dropping back (a jump down is drawn at once)
local function stepBlocks()
	if St.Stepping then
		return
	end
	St.Stepping = true
	task.spawn(function()
		while St.Blocks < St.BlockTarget and gui.Parent do
			local i = St.Blocks + 1
			paintBlock(i, true)
			blocksShown(i)
			local b = St.Ui.Row:FindFirstChild("Block" .. i)
			if b then
				local at = b.Position
				TweenService:Create(b, TweenInfo.new(L.POP / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
					Position = at + UDim2.fromOffset(0, -4),
				}):Play()
			end
			task.wait(L.POP)
		end
		St.Stepping = false
	end)
end

-- the blocks and the caption, from the gui attribute Progress
local function drawProgress()
	local p = tonumber(gui:GetAttribute("Progress")) or 0
	local k = math.max(0, math.min(L.BLOCKS, math.floor(p * L.BLOCKS + 1e-6)))
	St.BlockTarget = k
	if k < St.Blocks then
		for i = k + 1, St.Blocks do
			paintBlock(i, false)
		end
		blocksShown(k)
	elseif k > St.Blocks then
		stepBlocks()
	end
	local caption = St.Ui.Caption
	if caption then
		-- session lock (spec 18): while another server still saves this player's progress (the player attribute
		-- SaveWaiting, DataService's) the caption says so instead of the percentage
		if St.Waiting then
			caption.Text = "Another server is still saving your progress..."
		else
			caption.Text = "Loading the sky... " .. math.floor(p * 100 + 0.5) .. "%"
		end
	end
end

local function showProgress(value, force)
	if value <= St.Shown and not force then
		return
	end
	St.Shown = math.min(1, math.max(St.Shown, value))
	gui:SetAttribute("Progress", St.Shown)
	drawProgress()
end

-- true while the player attribute SaveWaiting is set; a change re-draws the caption even when the bar did not move
local function waitingChanged()
	local attr = (St.Config and St.Config.Attr and St.Config.Attr.SaveWaiting) or "SaveWaiting"
	local now = LocalPlayer:GetAttribute(attr) == true
	if now == St.Waiting then
		return false
	end
	St.Waiting = now
	return true
end

local function nextTip()
	local tips = St.Tips
	if #tips == 0 or not St.Ui.Tip then
		return
	end
	St.TipIndex = St.TipIndex % #tips + 1
	St.Ui.Tip.Text = tips[St.TipIndex]
	gui:SetAttribute("Tip", St.TipIndex)
end

----------------------------------------------------------------------
-- fade out (used when no main menu takes the screen)
----------------------------------------------------------------------

local function fadeAndDestroy()
	if not gui.Parent or gui:GetAttribute("Fading") then
		return
	end
	gui:SetAttribute("Fading", true)
	local info = TweenInfo.new(L.FADE)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiObject") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				TweenService:Create(d, info, { TextTransparency = 1 }):Play()
			elseif d:IsA("ImageLabel") then
				TweenService:Create(d, info, { ImageTransparency = 1 }):Play()
			end
		end
	end
	task.delay(L.FADE, function()
		gui:Destroy()
	end)
end

local function finish()
	if St.Done then
		return
	end
	St.Done = true
	showProgress(1)
	gui:SetAttribute("Done", true)
	if St.LobbyConn then
		St.LobbyConn:Disconnect()
		St.LobbyConn = nil
	end
	local menuOn = St.Config and type(St.Config.MainMenu) == "table" and St.Config.MainMenu.Enabled == true
	task.delay(menuOn and L.ORPHAN_FADE or L.SELF_FADE, fadeAndDestroy)
end

----------------------------------------------------------------------
-- boot
----------------------------------------------------------------------

buildSkeleton()
layout()
gui:GetAttributeChangedSignal("Progress"):Connect(drawProgress)
do
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if gui.Parent then
				pcall(layout)
			end
		end)
	end
end

task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local okConfig, Config = pcall(function()
		return require(shared:WaitForChild("Config"))
	end)
	St.Config = okConfig and Config or nil
	local okIds, ids = pcall(function()
		return require(shared:WaitForChild("TextureIds", 10))
	end)
	if okIds and type(ids) == "table" then
		local okImages, err = pcall(applyImages, ids)
		if not okImages then
			warn("[LoadingScreen] " .. tostring(err))
		end
	end
	local okTheme, Theme = pcall(function()
		return require(shared:WaitForChild("Theme"))
	end)
	if not okTheme or type(Theme) ~= "table" or not gui.Parent then
		return
	end
	St.Theme = Theme
	local okKit, SignKit = pcall(function()
		return require(shared:WaitForChild("SignKit", 10))
	end)
	local okIcon, PixelIcon = pcall(function()
		return require(shared:WaitForChild("PixelIcon", 10))
	end)
	local okNotes, notes = pcall(function()
		return require(shared:WaitForChild("UpdateNotes", 10))
	end)
	if okNotes and type(notes) == "table" and type(notes.Tips) == "table" then
		St.Tips = notes.Tips
	end
	if #St.Tips > 0 then
		-- a random first tip each load (UserId % #Tips showed a player the same tip every time); nextTip() moves to it
		St.TipIndex = math.random(1, #St.Tips) - 1
	end
	local okBuild, err = pcall(buildText, okKit and type(SignKit) == "table" and SignKit or nil, okIcon and type(PixelIcon) == "table" and PixelIcon or nil)
	if not okBuild then
		warn("[LoadingScreen] " .. tostring(err))
	end
	pcall(layout)
	nextTip()
	St.TipAt = St.Elapsed
	local okMeasure, value = pcall(measure)
	pcall(waitingChanged)
	showProgress(okMeasure and value or St.Shown, true)
	-- assets: the sky faces and this gui (the picks' images with it)
	task.spawn(function()
		local list = { gui }
		local skyInst = Lighting:FindFirstChildOfClass("Sky")
		if skyInst then
			list[#list + 1] = skyInst
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		St.Stage.Assets = 1
	end)
end)

task.spawn(function()
	local loading = (St.Config and St.Config.Loading) or {}
	while not St.Done and gui.Parent do
		local dt = task.wait(L.POLL)
		St.Elapsed = St.Elapsed + (tonumber(dt) or L.POLL)
		loading = (St.Config and St.Config.Loading) or loading
		local ok, value = pcall(measure)
		local okWait, changed = pcall(waitingChanged)
		if ok then
			showProgress(value, okWait and changed)
		elseif okWait and changed then
			showProgress(St.Shown, true)
		end
		if St.Ui.Skip and not St.Ui.Skip.Visible and St.Elapsed >= (tonumber(loading.SkipAfter) or 6) then
			St.Ui.Skip.Visible = true
		end
		if St.Elapsed - St.TipAt >= L.TIP_EVERY then
			St.TipAt = St.Elapsed
			nextTip()
		end
		if St.Skipped or St.Shown >= 0.999 or St.Elapsed >= (tonumber(loading.MaxSeconds) or 25) then
			finish()
		end
	end
end)
