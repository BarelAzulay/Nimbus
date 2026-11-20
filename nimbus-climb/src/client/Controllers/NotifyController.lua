-- NotifyController (client, v3): the game's side-of-screen voice. Nothing here is ever centred.
--
--   NotifyController.Init()
--   NotifyController.Toast(text, kind, duration) -> bool   (roll-look review round 1) a local toast exactly as the Notify
--                                    remote shows one (MenuController.Hint routes here while its NimbusMenu gui is off:
--                                    the egg stage's HUD hide)
--   NotifyController.SetHeld(who, on) (quick wins 2026-11-12, win 1) owner-keyed hold, like HudController.SetVitalsHidden:
--                                    while any owner holds (the main menu: "MainMenu", from Open until the PLAY fade
--                                    ends) every gameplay toast waits instead of showing (Notify remote and Toast alike).
--                                    Not held: "bad" (an error / a refusal), a Notify sent with opts.System (the
--                                    save-wait toasts) and "pull" (a chat line, posted at once). Identical held toasts
--                                    merge; up to HELD_MAX (16) distinct ones are kept, the oldest token / good one
--                                    dropped first and an opts.Keep one (the join welcome) last. When the last owner lets
--                                    go, the ones older than HELD_SECONDS (60) are dropped unless Keep, and the rest are
--                                    shown in the order sent, one every HELD_PACE (0.35 s) while the column has room.
--   NotifyController.IsHeld() -> bool  true while any owner holds
--
-- Remotes handled
--   Notify(text, kind, duration[, opts])  opts (optional table): System / Keep, see SetHeld above.
--                                 -> compact toast stack on the RIGHT edge, from the top (below the HUD currency
--                                    stack when that sits top-right on a short screen, and below the top-left
--                                    panel on a narrow one). Max 4, 250 design px wide, newest on top, slide in
--                                    from the right, `Toast` role font at the readable 18 px, a coloured accent
--                                    bar + icon by kind (info|good|bad|token). Identical toasts that are still
--                                    showing are merged into "text x2". A toast the column has no room for
--                                    (a short landscape phone fits one) waits and shows once room frees up.
--                                    Kind "pull" (lobby-shop spec 5.5, the server's Legendary+ hatch line
--                                    "<Name> hatched a <Rarity> <Pet>!") is a system chat line instead:
--                                    TextChatService.TextChannels.RBXSystem:DisplaySystemMessage, rich text
--                                    escaped, the rarity word in its Config.Rarities colour (Config.Eggs.ChatColors
--                                    overrides one: Secret's near-black is #B496FF on the dark chat, spec 16.5);
--                                    no channel (the legacy chat, not replicated yet) or an error -> a "good" toast.
--   MatchResult(result)           -> compact result card on the right edge (about 45% down): VICTORY!/DEFEAT in
--                                    the Title font with a gradient, difficulty + stars, time, tokens, bonus,
--                                    a small member list and a "Back to lobby in Ns" line. It closes when the
--                                    server clears MatchState (the player is back in the lobby), when the
--                                    player presses its X, or a few seconds after the countdown ends.
--                                    (U9-9 review) On a touch screen it stays clear of Roblox's jump button, the
--                                    touch RUN and the currency strip; the touch DASH lies wholly under it or wholly
--                                    clear (its taps pass through the card); where even the compact rows do not fit
--                                    (a 360 to 390 px tall landscape phone, a portrait phone above the centre band)
--                                    it is the mini card (no team, no difficulty line, 250 wide); the HUD's vitals
--                                    card steps aside under it.
--   MatchState(nil)               -> closes the result card.
--   DashFx(userId)                -> a cheap puff + trail on that player's character (own dashes are ignored,
--                                    MovementController already shows those).
--
-- kit B U9-9 (finding 15, the pitch's .toast; it was v5's neon pill): a toast is a kit B block like the HUD's currency
-- strips above it: the stone tile face, a 2 px wood edge, the darker stone lip along its bottom, square, no glow or
-- gradient; the kind's colour by role on a square chip in its left end (info sky + the bulb, good grass + the tick, bad red
-- + the x, token gold + the coin, with a pixel sparkle: a reward), the pixel icon on whole screen pixels at any scale
-- (client/UI/PixelCrisp), the text brown. A merged repeat flashes the face pale gold. The result card is a Signboard
-- CloudUI.Panel (wood frame, stone body, an awning as wide as the card): VICTORY! a gold banner block and DEFEAT a stone
-- one (plain Section titles: a pop-up's title, not a window's ribbon), the stats stone rows with brown values, the
-- member list brown with a tick / x chip, the footer brown; its confetti the kit's gold and pink bits (no rainbow).
-- The GUI is "NimbusNotify" (display order 30, IgnoreGuiInset = false). Sizes follow the v3 readability rule:
-- panels are designed in 1080p pixels and carry a UIScale of Theme.ScreenFactor() (same as the HUD), inside
-- full-screen holder frames whose UIPadding is the screen margin, so scaling never detaches them from the edge.
-- Where the HUD sits is read from the attributes HudController publishes on the NimbusHud gui.
-- Plain Lua 5.1-compatible syntax only. All fonts come from Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7a) the toast and result card icons

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local PixelCrisp = require(Client:WaitForChild("UI"):WaitForChild("PixelCrisp")) -- (kit B U9-9) whole-pixel icons

local NotifyController = {}

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- Tuning (design px of a 1080p screen)
----------------------------------------------------------------------
-- toasts
local MAX_TOASTS = 4
local TOAST_W = 250
-- (U9-9 look) the column's rows in multiples of 5 design px, whole screen px at the phones' 0.8 and at 1080p (a UDim's
-- Offset is whole in Roblox, so 8 px of padding would draw 6.4): the gap, the padding, the lip
local TOAST_GAP = 10
local TOAST_PAD = 10
local TOAST_TEXT_SIZE = 18
local TOAST_TEXT_MIN = 25 -- a one-line toast's text row (the card is then 50 design px: 40 px at 0.8)
local TOAST_ICON = 30
local TOAST_BG = 0 -- (kit B U9-9) an opaque stone block
local TOAST_EDGE = 2 -- the wood edge (as the HUD's currency strips)
local TOAST_LIP = 5 -- the darker stone lip along the bottom (4 px at 0.8)
local TOAST_CHIP_LIP = 3 -- the chip's own lip
local TOAST_GLYPH = 18 -- the chip's pixel icon (2 px cells at 1080p)
local DEFAULT_DURATION = 3
local MIN_DURATION = 1.5
local MAX_DURATION = 8
local MAX_TOAST_CHARS = 90
local MIN_TOAST_H = 52 -- a one-line toast (design px)
-- a toast the screen had no room for (a short landscape phone fits one) waits and comes back when room frees up,
-- so two toasts sent together (/devhelp) are both read: up to WAIT_MAX wait, each for at most WAIT_SECONDS
local WAIT_MAX = 3
local WAIT_SECONDS = 20
local WAIT_MIN_SHOWN = 1.5 -- seconds a toast must have been readable before it may be pushed out for good
-- (quick wins, win 1; review round 1) toasts held by SetHeld (the title screen): parked, then shown one by one once the
-- hold ends, so nothing is cut. Identical held toasts merge ("x2"). Over HELD_MAX distinct ones the oldest low-value
-- one (HELD_LOW: token / good) goes first, then the oldest plain one; a Keep one (opts.Keep: the join welcome) last.
-- At release a held toast older than HELD_SECONDS is dropped as stale (a "Double Rewards in 2 minutes" line), unless Keep.
local HELD_MAX = 16
local HELD_SECONDS = 60
local HELD_LOW = { token = true, good = true }
local HELD_PACE = 0.35 -- seconds between two released toasts (and between two room checks while the column is full)

-- KEEP IN SYNC with HudController.lua: EDGE and TOUCH_EDGE.
local EDGE = 12
local TOUCH_EDGE = 20
local HUD_GAP = 10 -- kept below the HUD pieces the stack has to clear
local GIFT_GAP = 8 -- (kit-b) design px beside the gift's square on a portrait screen (HudController K.GIFT_GAP)

-- result card
local RESULT_W = 290
local RESULT_ROOF_OVER = 10 -- (kit B U9-9) the awning reaches this far past each side of the card ...
-- ... and this far above its top: the card is placed so the awning clears the HUD too. (P2 fix A) Read from the kit: since
-- the F0 finish pass seats the awning on the frame (SignKit.RoofSeat, 20 design px over the card) the old 10 put the awning
-- of a card placed under the strip 8 px up into the token strip on a 360 px tall phone
local RESULT_ROOF_UP = -require(Shared:WaitForChild("SignKit")).RoofSeat()
-- (kit B U9-9) the card's rows (design px): the full card, and the compact one for a screen whose room for the card
-- (resultRoom: under the HUD's top-right block and the awning, above the touch buttons, the lower quarter or the centre
-- band) is less than the full card's height (a landscape phone): the stat blocks thinner, the banner and the gaps
-- tighter and the card's top room under the awning used (Trim; Slack the room under the footer), no "Win bonus" row
-- when there is no bonus (a loss: it read "-") and a team of three or four in two columns of names with their ticks /
-- crosses (the player's own tokens are the Tokens row). Every text stays >= 18 design px (14.4 px at the phones' 0.8).
-- A member line stays 26 high: at 0.8 its 18 px icons (2 px cells, PixelCrisp) need that room to sit apart line to line.
-- (U9-9 review) Mini: where even the compact card is taller than its room (a 360 to 390 px tall landscape phone, between
-- the currency strip and the jump button; a portrait phone, above the centre band): the compact rows with no team and no
-- difficulty line (the result, the reason in its short words, the stats and the countdown), W 250 (the toast column's
-- width, so it clears the centre band on a 640 px phone)
-- (U9-9 look) every row a multiple of 5 design px, so its edges land on whole screen px at the phones' 0.8 and at 1080p,
-- and a stat block tall enough for its 18 px coin: Row - RowGap is the block (30 -> 24 px at 0.8: its value row 20 px, a
-- pixel clear of the coin above and of its lip below), RowGap the stone between two blocks (their 2 px edges and 4 px of
-- stone between them at 0.8); Close the red close block
-- (inside the banner's face above its lip); Diff the difficulty's role chip (30 high, 4 px under the banner's edge). The
-- mini card's win bonus rides in the Tokens row ("11 +10", MergeBonus)
local RESULT_ROWS = {
	Full = { Title = 45, Headline = 34, Diff = 45, Reason = 25, Gap = 5, Row = 45, RowGap = 10, Member = 30, Foot = 30, Value = 20, Trim = 0,
		Slack = 10, Close = 35, W = RESULT_W },
	Compact = { Title = 40, Headline = 30, Diff = 45, Reason = 25, Gap = 5, Row = 40, RowGap = 10, Member = 30, Foot = 25, Value = 18, Trim = 10,
		Slack = 5, Close = 30, SkipZeroBonus = true, Columns = 2, W = RESULT_W },
	-- (U9-9 look 2) Mini: Slack 5 under the countdown (it stood on the outcome lip, its "y" in it), taken from the Gap
	Mini = { Title = 40, Headline = 30, Diff = 0, Reason = 25, Gap = 5, Row = 40, RowGap = 10, Member = 30, Foot = 20, Value = 18, Trim = 10,
		Slack = 5, Close = 30, SkipZeroBonus = true, MergeBonus = true, NoTeam = true, NoDiff = true, ShortReason = true, W = 250 },
	-- (P2 fix A) Micro: where even the mini card is taller than its room (a lost match's mini card, its reason line 25 more,
	-- on a 360 px tall landscape phone: 200 of 177.5 between the strip, the awning and the jump button): the mini card with
	-- no Time row, so the result, the reason, the tokens and the countdown all show and the awning clears the strip
	Micro = { Title = 40, Headline = 30, Diff = 0, Reason = 25, Gap = 5, Row = 40, RowGap = 10, Member = 30, Foot = 20, Value = 18, Trim = 10,
		Slack = 5, Close = 30, SkipZeroBonus = true, MergeBonus = true, NoTeam = true, NoDiff = true, ShortReason = true, NoTime = true, W = 250 },
}
local RESULT_ROW_LIP = 5 -- a stat block's lip (4 px at 0.8)
local RESULT_BANNER_LIP = 5
local RESULT_ICON_GAP = 5 -- the room between a value and its coin / tick (4 px at 0.8)
local RESULT_NAIL = 4 -- (U9-9 look) the stone body's two nails at its top corners (the dungeon End card's, U9-7) ...
local RESULT_NAIL_IN = 5 -- ... this far in from the corner
local RESULT_CHIP_H = 20 -- (U9-9 look 2) the mini card's win bonus chip (the HUD's gold run chip): its height and lip
local RESULT_CHIP_LIP = 3
local RESULT_TIERS = { "Full", "Compact", "Mini", "Micro" } -- the first whose card fits its room (the last when none does)
NotifyController.ResultRows = RESULT_ROWS
local RESULT_Y = 0.47 -- vertical position (fraction of the screen), right edge
-- On narrow (portrait) screens the scaled card reaches into the middle of the screen. The game must never say
-- anything there, so the card moves up until it sits above this central band (fractions of the screen size).
local CENTRE_BAND = 0.15
local CENTRE_MARGIN = 6
local CONFETTI_PIECES = 22

-- dash puffs of other players
local FX_MAX_DISTANCE = 140
local FX_MIN_INTERVAL = 0.2
local FxSprites = require(Shared:WaitForChild("FxSprites")) -- the game's own particle sprites (kit B X1)

local Colors = Theme.Colors

local FALLBACK_KINDS = {
	info = Color3.fromRGB(90, 158, 234),
	good = Color3.fromRGB(96, 196, 108),
	bad = Color3.fromRGB(228, 90, 92),
	token = Color3.fromRGB(240, 188, 66),
}
-- (kit B U9-9) each kind's chip: its colour by role (the pitch's .ti, the HUD's coin squares), the lip under it and the
-- pixel icon in the ink that reads on it. Every kind is a PixelIcon now (the "i" / "!" letters went)
local SIGN = Theme.Sign
-- (U9-9 look 2) the result card's inline coins in the Shop's deep gold ("x3 [coin] 150", ShopEggs), not the brown ink:
-- one currency, one colour
local RESULT_COIN = SIGN.GoldLip
local KIND_CHIP = {
	info = { Face = SIGN.Sky, Lip = SIGN.SkyLip, Icon = "bulb", Ink = SIGN.Text },
	good = { Face = SIGN.Grass, Lip = SIGN.GrassLip, Icon = "check", Ink = SIGN.OnGrass },
	bad = { Face = SIGN.Red, Lip = SIGN.RedLip, Icon = "x", Ink = SIGN.Text },
	token = { Face = SIGN.Gold, Lip = SIGN.GoldLip, Icon = "token", Ink = SIGN.Text, Sparkle = true },
}
NotifyController.KindChip = KIND_CHIP
-- (U9-9 look) the result card's difficulty stars are drawn in the ink of the difficulty's chip (buildResults)

local REASON_TEXT = {
	defeat = "The whole team went down",
	timeout = "Out of time",
	abandoned = "Match abandoned",
}
-- (U9-9 review) the mini card's 250 px row cut "The whole team went down" short
local REASON_SHORT = {
	defeat = "The team went down",
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local initialized = false
local rng = Random.new()
local UI = {} -- Gui, Stack, StackScale, ToastPad, ResultPad, ResultHolder
local scalers = {}
local toasts = {} -- live toasts, oldest first
local waiting = {} -- toasts pushed out for room: { Text, Kind, Duration, Until }, oldest first
local holders = {} -- SetHeld owners: { [who] = true }; any owner holds the non-"bad" toasts
local held = {} -- toasts waiting for the hold to end: { Text, Kind, Duration, Keep, Count, At }, oldest first (<= HELD_MAX)
local released = {} -- held toasts let go and not shown yet (the drain), oldest first
local drainArmed = false -- a drain step is scheduled
local toastSerial = 0
local result = { Panel = nil, Serial = 0, Height = 0, Width = RESULT_W } -- the open result card (Height, Width: design px)
local lastDashFx = {}
local hud = { Gui = nil, Conn = nil } -- the NimbusHud gui whose layout attributes we follow

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local tween = Util.Tween

local function isTouchDevice()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if vp.X < 2 or vp.Y < 2 then
		return Vector2.new(1920, 1080)
	end
	return vp
end

-- The readability factor: clamp(viewportY / 1080, 0.8, 1.25) (the HUD uses the same).
local function currentScale()
	return Theme.ScreenFactor(viewportSize().Y)
end

local function topInset()
	local okInset, inset = pcall(GuiService.GetGuiInset, GuiService)
	return (okInset and inset and inset.Y) or 0
end

local function hex(color)
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local function newFrame(parent, name, props)
	local p = { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0 }
	if props then
		for key, value in pairs(props) do
			p[key] = value
		end
	end
	p.Parent = parent
	return Util.Create("Frame", p)
end

-- Themed TextLabel with any label property in props. kit-b U6: the toasts, the result card and the hints are all
-- plates, so their texts read by contrast with no outline and no classic stroke.
local function newText(parent, name, text, role, size, color, props)
	local extra = {
		Name = name,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	if props then
		for key, value in pairs(props) do
			extra[key] = value
		end
	end
	local label = Theme.Label(text, role, {
		Size = size,
		Color = color,
		Props = extra,
	})
	label.Parent = parent
	return label
end

local function addViewportScale(root)
	local s = Instance.new("UIScale")
	s.Name = "ViewportScale"
	s.Scale = currentScale()
	s.Parent = root
	table.insert(scalers, s)
	return s
end

local function kindColor(kind)
	local name = "info"
	if type(kind) == "string" and FALLBACK_KINDS[string.lower(kind)] then
		name = string.lower(kind)
	end
	local fromTheme = Theme.Kinds and Theme.Kinds[name]
	return fromTheme or FALLBACK_KINDS[name], name
end

-- Cut a string to `maxChars` characters (UTF-8 aware) and add "..." when it was longer.
local function truncateText(text, maxChars)
	text = tostring(text or "")
	local okLen, len = pcall(utf8.len, text)
	if okLen and len then
		if len <= maxChars then
			return text
		end
		local okOff, offset = pcall(utf8.offset, text, maxChars + 1)
		if okOff and offset then
			return string.sub(text, 1, offset - 1) .. "..."
		end
	end
	if #text <= maxChars then
		return text
	end
	return string.sub(text, 1, maxChars) .. "..."
end

-- A transparent full-screen frame whose UIPadding is the screen margin.
local function newHolder(name)
	local holder = newFrame(UI.Gui, name, { Size = UDim2.fromScale(1, 1) })
	local pad = Instance.new("UIPadding")
	pad.Parent = holder
	return holder, pad
end

-- One layout attribute HudController publishes on NimbusHud (gui-area pixels, 0 = nothing there).
local function hudValue(name)
	local gui = hud.Gui
	if not gui or not gui.Parent then
		return 0
	end
	local value = gui:GetAttribute(name)
	if type(value) == "number" then
		return value
	end
	return 0
end

-- (kit B U9-9) Roblox's own jump button on a touch screen (its TouchGui is not the game's to read), as the kit's fit tests
-- place it: J = 70 px on a small screen (shorter side <= 500), from 1.5 J + 10 to 0.5 J + 10 in from the right and 20 + J
-- up from the bottom; a big screen's 120 px button sits higher (210 up). -> x0, x1, y0 in gui px; nil without touch
local function jumpButton()
	if not isTouchDevice() then
		return nil
	end
	local vp = viewportSize()
	local areaY = vp.Y - topInset()
	if math.min(vp.X, vp.Y) <= 500 then
		return vp.X - 115, vp.X - 45, areaY - 90
	end
	return vp.X - 190, vp.X - 50, areaY - 210
end

-- Lowest gui y a toast column whose left edge is at `toastLeft` (right edge `toastRight`) may reach: above the
-- centre band when the column reaches into it sideways (portrait phones), above the touch RUN / DASH buttons
-- under the column, (kit B U9-9) 6 px above Roblox's jump button, and never into the lower quarter of the screen.
-- (U9-9 review) card: the result card's limit. The touch DASH under it is left out and returned as its rows with its
-- stroke ({ Top, Bottom }, gui px): the card lies wholly over it or wholly clear of it (resultSpan), its taps pass through
-- the card. On a touch screen the touch buttons are the card's floor, not the lower quarter (the big phones' DASH reaches
-- into that quarter: a card over it ends at the jump button)
local function bottomLimitFor(toastLeft, toastRight, card)
	local vp = viewportSize()
	local inset = topInset()
	local limit = (card and isTouchDevice()) and (vp.Y - inset) or (vp.Y - inset) * 0.72
	if toastLeft < vp.X * (0.5 + CENTRE_BAND) and toastRight > vp.X * (0.5 - CENTRE_BAND) then
		limit = math.min(limit, vp.Y * (0.5 - CENTRE_BAND) - CENTRE_MARGIN - inset)
	end
	local jx0, jx1, jy0 = jumpButton()
	if jx0 and toastRight > jx0 - 6 and toastLeft < jx1 + 6 then
		limit = math.min(limit, jy0 - 6)
	end
	local dash = nil
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local mobile = playerGui and playerGui:FindFirstChild("MobileControls")
	if mobile and mobile:IsA("ScreenGui") and mobile.Enabled then
		local dy = mobile.IgnoreGuiInset and -inset or 0
		for _, d in ipairs(mobile:GetDescendants()) do
			if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible and d.AbsoluteSize.X > 0 then
				local x0 = d.AbsolutePosition.X
				local x1 = x0 + d.AbsoluteSize.X
				if x1 > toastLeft and x0 < toastRight then
					local y0 = d.AbsolutePosition.Y + dy
					if card and d.Name == "DashButton" then
						local stroke = d:FindFirstChildOfClass("UIStroke")
						local s = (stroke and stroke.Enabled ~= false) and stroke.Thickness or 0
						dash = { Top = y0 - s, Bottom = y0 + d.AbsoluteSize.Y + s, Clear = y0 - TOAST_GAP }
					else
						limit = math.min(limit, y0 - TOAST_GAP)
					end
				end
			end
		end
	end
	return limit, dash
end

-- Where the toast column goes: { Top, Right (padding from the right edge), Bottom (lowest y) } in gui px.
-- Normally the top-right corner (below the HUD's currency stack when that sits there). On a short screen
-- where not even one toast fits between that stack and the touch buttons, the column moves to the left of
-- the stack instead; on a narrow screen it also stays below the top-left panel when the two would overlap.
local function toastPlacement()
	local side = isTouchDevice() and TOUCH_EDGE or EDGE
	local k = currentScale()
	local vp = viewportSize()
	local width = TOAST_W * k
	local right = side
	local top = EDGE
	local rightBottom = hudValue("TopRightBottom")
	if rightBottom > 0 then
		top = rightBottom + HUD_GAP
		-- (kit-b) on a portrait screen the gift's square under the strips (GiftLeft / GiftTop / GiftSize) would eat the
		-- column's room as a stack of strips would (HudController lines those up in one row there): the column starts
		-- level with the square, left of it, the square's own gap (HudController K.GIFT_GAP) away, so the cards' text
		-- stays in the screen's right part
		if vp.Y > vp.X and hudValue("GiftSize") > 0 and hudValue("GiftLeft") > 0 then
			right = math.max(side, vp.X - hudValue("GiftLeft") + GIFT_GAP * k)
			top = hudValue("GiftTop")
		end
		local left = vp.X - right - width
		local room = (bottomLimitFor(left, vp.X - right) - top) / math.max(0.01, k)
		local stackLeft = hudValue("TopRightLeft")
		if room < MIN_TOAST_H and stackLeft > 0 then
			right = math.max(side, vp.X - stackLeft + HUD_GAP)
			top = EDGE
		end
	end
	local toastLeft = vp.X - right - width
	local leftRight = hudValue("TopLeftRight")
	if leftRight > 0 and leftRight > toastLeft - 4 then
		top = math.max(top, hudValue("TopLeftBottom") + HUD_GAP)
	end
	return {
		Top = math.floor(top),
		Right = math.floor(right),
		Bottom = bottomLimitFor(toastLeft, vp.X - right),
	}
end

-- Conservative height of a toast in design px (wide glyphs, word wrap slack).
local function estimateToastHeight(text)
	local width = TOAST_W - 24 - (TOAST_ICON + 10)
	local perLine = math.max(1, math.floor(width / (TOAST_TEXT_SIZE * 0.62)))
	local okLen, len = pcall(utf8.len, tostring(text or ""))
	if not okLen or type(len) ~= "number" then
		len = #tostring(text or "")
	end
	local lines = math.max(1, math.ceil(len / perLine))
	-- (kit B U9-9) the stone tag's padding (over it, and with its lip under it) and its wood edge outside it
	return math.max(TOAST_TEXT_MIN, lines * math.ceil(TOAST_TEXT_SIZE * 1.15)) + 2 * TOAST_PAD + TOAST_LIP + 2 * TOAST_EDGE
end

-- (U9-9 look) a toast's text row: the height its wrapped text takes (TextBounds, in the label's own px; a measure until the
-- text is laid out), picked so the card's edges land on whole screen px (PixelCrisp.Len), at least one line's
-- TOAST_TEXT_MIN; the card is its padding, this row and its lip, each whole px, so its height is set, not automatic
local function sizeToastText(toast)
	local label, card = toast.Label, toast.Card
	if not (label and label.Parent and card) then
		return
	end
	local k = PixelCrisp.ScaleAbove(label)
	local h = label.TextBounds.Y / math.max(0.01, k)
	if h <= 0 then
		local room = TOAST_W - 2 * TOAST_PAD - (TOAST_ICON + 10)
		local okM, m = pcall(Theme.Measure, label.Text, "Toast", TOAST_TEXT_SIZE, room)
		h = (okM and typeof(m) == "Vector2") and m.Y or TOAST_TEXT_MIN
	end
	h = PixelCrisp.Len(math.max(TOAST_TEXT_MIN, math.ceil(h - 0.01)), k)
	local want = UDim2.new(1, -(TOAST_ICON + 10), 0, h)
	if label.Size ~= want then
		label.Size = want
	end
	local cardH = UDim2.new(1, 0, 0, 2 * TOAST_PAD + TOAST_LIP + h)
	if card.Size ~= cardH then
		card.Size = cardH
	end
end

-- (kit-b) a live toast's height in design px: its card as sizeToastText set it (padding, text row, lip: a set height
-- since U9-9) and its wood edge outside it; the estimate only while the card has no height yet
local function liveToastHeight(toast)
	local card = toast.Card
	local h = card and card.Size.Y.Scale == 0 and card.Size.Y.Offset or 0
	if h > 0 then
		return h + 2 * TOAST_EDGE
	end
	return estimateToastHeight(toast.Label.Text)
end

local dismissToast -- defined below

-- Keeps the newest toasts that fit above the column's lowest allowed y (always at least the newest one).
local function trimToasts()
	if #toasts == 0 then
		return
	end
	local k = currentScale()
	local place = toastPlacement()
	local budget = (place.Bottom - place.Top) / math.max(0.01, k)
	local used = 0
	local kept = 0
	local drop = {}
	for i = #toasts, 1, -1 do -- newest first
		local toast = toasts[i]
		local h = liveToastHeight(toast)
		if kept > 0 then
			h = h + TOAST_GAP
		end
		if kept >= 1 and used + h > budget then
			for j = i, 1, -1 do
				table.insert(drop, toasts[j])
			end
			break
		end
		used = used + h
		kept = kept + 1
	end
	local now = os.clock()
	for _, toast in ipairs(drop) do
		-- pushed out before it could be read: it waits for room (see flushWaiting)
		local shownFor = now - (toast.Born or now)
		local left = (toast.Expiry or now) - now
		if shownFor < WAIT_MIN_SHOWN and left > MIN_DURATION and #waiting < WAIT_MAX then
			table.insert(waiting, 1, { Text = toast.Text, Kind = toast.Kind, Duration = left, Until = now + WAIT_SECONDS })
		end
		dismissToast(toast)
	end
end

local function applyMargins()
	local side = isTouchDevice() and TOUCH_EDGE or EDGE
	if UI.ToastPad then
		local place = toastPlacement()
		UI.ToastPad.PaddingRight = UDim.new(0, place.Right)
		UI.ToastPad.PaddingTop = UDim.new(0, place.Top)
	end
	if UI.ResultPad then
		UI.ResultPad.PaddingRight = UDim.new(0, side)
	end
end

-- Where a result card `width` design px wide goes: true = at the right edge, from its left x to its right x (gui px).
-- (U9-9 review) Every landscape screen keeps it there (a phone under 720 px wide took the centre-band rule below, which
-- never asked bottomLimitFor about the touch buttons); a portrait one only when the scaled card stays right of the
-- centre band
local function resultOnEdge(width)
	local vp = viewportSize()
	local side = isTouchDevice() and TOUCH_EDGE or EDGE
	local cardLeft = vp.X - side - width * currentScale()
	return vp.X > vp.Y or cardLeft >= vp.X * (0.5 + CENTRE_BAND), cardLeft, vp.X - side
end

-- (kit B U9-9; review) The rows the right-edge card may use (gui px): Top = under the HUD's top-right block and the awning,
-- Clear = the lowest y that keeps the touch DASH wholly clear, Cover = the lowest y bottomLimitFor allows (jump button, RUN,
-- the centre band) when the card may lie wholly over DASH (it reaches past DASH's stroke), else Clear; Dash = DASH's rows
-- with its stroke (nil without one under the card). Never a sliver of DASH under the card's edge (the U9-4 rule)
local function resultSpan(width)
	local k = currentScale()
	local _, cardLeft, cardRight = resultOnEdge(width)
	local top = math.max(EDGE, hudValue("TopRightBottom") + HUD_GAP) + RESULT_ROOF_UP * k
	local cover, dash = bottomLimitFor(cardLeft, cardRight, true)
	local clear = cover
	if dash and dash.Clear < cover then
		clear = dash.Clear
		if cover < dash.Bottom then
			cover = clear
		end
	end
	return top, clear, cover, dash
end

-- a whole gui px for the card's centre y, kept inside lo .. hi when those leave one (the DASH window is 1 px)
local function snapInside(y, lo, hi)
	local a, b = math.ceil(lo), math.floor(hi)
	if a <= b then
		return math.min(math.max(math.floor(y + 0.5), a), b)
	end
	return math.floor(y)
end

-- Position of the (right-edge) result card: `xScale` 1 = on screen, > 1 = parked off screen. The card sits at
-- RESULT_Y of the screen height; when the screen is so narrow that the scaled card reaches into the centre band
-- it is lifted above that band instead (never below it: the thumb controls live there).
local function resultPosition(xScale, panelHeight, panelWidth)
	local vp = viewportSize()
	local k = currentScale()
	local width = panelWidth or result.Width
	local half = (panelHeight or result.Height) * k / 2
	local roof = RESULT_ROOF_UP * k -- (kit B U9-9) the awning over the card's top
	if resultOnEdge(width) then
		-- keep clear of a top-right currency stack on short screens
		local top, clear, cover, dash = resultSpan(width)
		local y = (vp.Y - topInset()) * RESULT_Y
		local lo, hi = top + half, clear - half
		if hi < lo and cover > clear then
			-- (U9-9 review) too tall to end above the touch DASH: the card lies wholly over it (a short landscape phone),
			-- or on a screen with no room either way it ends at the cover limit, never over the top edge
			lo, hi = math.max(lo, dash.Bottom - half), cover - half
			if lo <= hi then
				return UDim2.new(xScale, 0, 0, snapInside(y, lo, hi))
			end
			return UDim2.new(xScale, 0, 0, math.floor(math.max(hi, EDGE + roof + half)))
		end
		if hi < lo then
			-- no room at all (a tiny screen): as low as the limit lets it, never over the top edge
			return UDim2.new(xScale, 0, 0, math.floor(math.max(hi, EDGE + roof + half)))
		end
		-- v5: a short screen lifts the card under the HUD so it never covers the touch RUN / DASH / jump buttons below it
		if y > hi or y < lo then
			y = lo
		end
		return UDim2.new(xScale, 0, 0, snapInside(y, lo, hi))
	end
	-- the ScreenGui area starts below the top bar (IgnoreGuiInset = false), so gui y = screen y - inset
	local ceiling = vp.Y * (0.5 - CENTRE_BAND) - CENTRE_MARGIN - half - topInset()
	local floorY = math.max(EDGE, hudValue("TopRightBottom") + HUD_GAP) + roof + half
	return UDim2.new(xScale, 0, 0, math.floor(math.max(ceiling, floorY)))
end

-- (kit B U9-9) the design px of height a card `width` design px wide has where resultPosition puts it: from under the HUD's
-- top-right block and the awning down to the lowest y it may reach (the right edge: resultSpan's Cover), or to the centre
-- band (a narrow portrait screen)
local function resultRoom(width)
	local vp = viewportSize()
	local k = math.max(0.01, currentScale())
	if resultOnEdge(width) then
		local top, _, cover = resultSpan(width)
		return (cover - top) / k
	end
	local top = math.max(EDGE, hudValue("TopRightBottom") + HUD_GAP) + RESULT_ROOF_UP * k
	return (vp.Y * (0.5 - CENTRE_BAND) - CENTRE_MARGIN - topInset() - top) / k
end

-- (U9-9 review, look) the HUD's vitals card steps aside while the open card lies over a part of it (a short landscape
-- phone: the mini card's corner over the card's right end), as the Trove and Gifts windows do; back when the card goes
local function syncVitals()
	local off = false
	local panel = result.Panel
	local module = script.Parent:FindFirstChild("HudController")
	local okHud, hud = false, nil
	if module then
		okHud, hud = pcall(require, module)
	end
	if not (okHud and type(hud) == "table") then
		return
	end
	if panel and panel.Root and panel.Root.Parent and type(hud.GetLayout) == "function" then
		local okLayout, layout = pcall(hud.GetLayout)
		local slot = okLayout and type(layout) == "table" and layout.VitalsSlot
		if slot then
			local vp, k = viewportSize(), currentScale()
			local x1 = vp.X - (isTouchDevice() and TOUCH_EDGE or EDGE)
			local x0 = x1 - result.Width * k
			local pos = resultPosition(1)
			local cy = pos.Y.Scale * (vp.Y - topInset()) + pos.Y.Offset
			local y0, y1 = cy - result.Height * k / 2, cy + result.Height * k / 2
			local w = math.min(x1, slot.X + slot.W) - math.max(x0, slot.X)
			local h = math.min(y1, slot.Y + slot.H) - math.max(y0, slot.Y)
			off = w > 4 and h > 4
		end
	end
	if off ~= (result.VitalsOff == true) and type(hud.SetVitalsHidden) == "function" then
		result.VitalsOff = off
		pcall(hud.SetVitalsHidden, "ResultCard", off)
	end
end

-- Tells the HUD where the open result card starts (gui x of its left edge; 0 = no card), so on a narrow
-- screen it can tuck the match panel away instead of drawing both on top of each other.
local function publishResultCard()
	if not UI.Gui then
		return
	end
	local value = 0
	if result.Panel and result.Panel.Root and result.Panel.Root.Parent then
		local side = isTouchDevice() and TOUCH_EDGE or EDGE
		value = math.floor(viewportSize().X - side - result.Width * currentScale())
	end
	if UI.Gui:GetAttribute("ResultCardLeft") ~= value then
		UI.Gui:SetAttribute("ResultCardLeft", value)
	end
	syncVitals()
end

local function relayout()
	local k = currentScale()
	for i = #scalers, 1, -1 do
		local s = scalers[i]
		if s.Parent then
			s.Scale = k
		else
			table.remove(scalers, i)
		end
	end
	-- (U9-9 look) the column's scale rounded so its 250 px width is whole screen px (its cards' edges on whole px)
	if UI.StackScale then
		UI.StackScale.Scale = math.max(1, math.floor(TOAST_W * k + 0.5)) / TOAST_W
	end
	applyMargins()
	trimToasts()
	for _, toast in ipairs(toasts) do
		sizeToastText(toast)
	end
	PixelCrisp.Refresh(UI.Stack) -- (kit B U9-9) the icons and edges back on whole pixels at the new scale
	local panel = result.Panel
	if panel and panel.Root and panel.Root.Parent then
		panel.Root.Position = resultPosition(1)
		PixelCrisp.Refresh(panel.Root)
	end
	publishResultCard()
end

-- Follow the HUD's layout attributes (the HUD may be built before or after us, and rebuilt).
local function bindHud(gui)
	if hud.Gui == gui then
		return
	end
	if hud.Conn then
		hud.Conn:Disconnect()
		hud.Conn = nil
	end
	hud.Gui = gui
	if gui then
		hud.Conn = gui.AttributeChanged:Connect(function()
			pcall(relayout)
		end)
	end
	pcall(relayout)
end

local function watchHud()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		return
	end
	local existing = playerGui:FindFirstChild("NimbusHud")
	if existing and existing:IsA("ScreenGui") then
		bindHud(existing)
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "NimbusHud" and child:IsA("ScreenGui") then
			bindHud(child)
		end
	end)
end

----------------------------------------------------------------------
-- Toasts
----------------------------------------------------------------------
-- a = 0 fully visible .. 1 fully faded
local function setToastAlpha(toast, a, seconds)
	local goals = {
		{ toast.Card, { BackgroundTransparency = TOAST_BG + (1 - TOAST_BG) * a } },
		{ toast.Stroke, { Transparency = a } },
		{ toast.Lip, { BackgroundTransparency = a } },
		{ toast.Label, { TextTransparency = a } },
		{ toast.Icon, { BackgroundTransparency = a } },
		{ toast.IconStroke, { Transparency = a } },
		{ toast.IconLip, { BackgroundTransparency = a } },
		{ toast.IconGlyph, { TextTransparency = a } },
		{ toast.Sparkle, { TextTransparency = a } },
	}
	for _, entry in ipairs(goals) do
		if entry[1] then
			if seconds and seconds > 0 then
				tween(entry[1], seconds, entry[2], Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			else
				for key, value in pairs(entry[2]) do
					entry[1][key] = value
				end
			end
		end
	end
end

function dismissToast(toast)
	if toast.Dead then
		return
	end
	toast.Dead = true
	for i, live in ipairs(toasts) do
		if live == toast then
			table.remove(toasts, i)
			break
		end
	end
	tween(toast.Card, 0.22, { Position = UDim2.new(0, TOAST_W + 40, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	setToastAlpha(toast, 1, 0.22)
	task.delay(0.25, function()
		local slot = toast.Slot
		if not slot or not slot.Parent then
			return
		end
		-- collapse the gap smoothly instead of popping the stack
		local scale = UI.StackScale and UI.StackScale.Scale or 1
		local height = slot.AbsoluteSize.Y / math.max(0.01, scale)
		slot.AutomaticSize = Enum.AutomaticSize.None
		slot.Size = UDim2.new(1, 0, 0, height)
		tween(slot, 0.15, { Size = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.18, function()
			if slot.Parent then
				slot:Destroy()
			end
		end)
	end)
end

local flushWaiting -- defined after addToast

local function scheduleExpiry(toast, duration)
	toast.Expiry = os.clock() + duration
	task.delay(duration + 0.02, function()
		if not toast.Dead and os.clock() >= toast.Expiry then
			dismissToast(toast)
			if flushWaiting and #waiting > 0 then
				task.delay(0.3, flushWaiting)
			end
		end
	end)
end

local function refreshToastText(toast)
	local text = toast.Text
	if toast.Count > 1 then
		text = text .. "  x" .. tostring(toast.Count)
	end
	toast.Label.Text = text
	sizeToastText(toast) -- (U9-9 look) "x2" may take a second line
	PixelCrisp.Refresh(toast.Card)
end

-- (kit B U9-9) brown on the stone tile, whatever the kind (the chip carries the kind's colour)
local function toastTextColor()
	return SIGN.Text
end

local function buildToast(text, kind)
	local color, kindName = kindColor(kind)
	local chip = KIND_CHIP[kindName] or KIND_CHIP.info
	toastSerial = toastSerial + 1

	-- the slot is the list item (it keeps its place while the card slides); the card is what moves
	local slot = newFrame(UI.Stack, "ToastSlot", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = -toastSerial, -- newest on top
	})
	-- (kit B U9-9) the stone block: tile face, wood edge, the stone lip along its bottom (CloudUI.SignBlock keeps the lip
	-- flush with the block's edges under the padding)
	local card = newFrame(slot, "Toast", {
		Position = UDim2.new(0, TOAST_W + 40, 0, 0),
		Size = UDim2.new(1, 0, 0, 2 * TOAST_PAD + TOAST_LIP + TOAST_TEXT_MIN), -- sizeToastText
	})
	-- (U9-9 look) the card is a crisp root: it slides in, and its chip and icons sit on whole px of it at rest (its
	-- padding, text row and lip are whole px, so the column's cards rest on whole px too)
	PixelCrisp.Root(card)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, TOAST_PAD)
	pad.PaddingBottom = UDim.new(0, TOAST_PAD + TOAST_LIP)
	pad.PaddingLeft = UDim.new(0, TOAST_PAD)
	pad.PaddingRight = UDim.new(0, TOAST_PAD)
	pad.Parent = card
	local stroke, lip = CloudUI.SignBlock(card, { Face = SIGN.Tile, Lip = SIGN.StoneLip, Edge = SIGN.Wood, Text = SIGN.Text }, {
		EdgePx = TOAST_EDGE,
		LipPx = TOAST_LIP,
	})
	PixelCrisp.Edge(stroke, TOAST_EDGE)
	PixelCrisp.Lip(lip, TOAST_LIP)
	card.BackgroundTransparency = 1 -- faded in by setToastAlpha
	stroke.Transparency = 1
	lip.BackgroundTransparency = 1

	-- the kind's chip: its colour by role, a wood edge, its own darker lip; the pixel icon on whole screen pixels
	local icon = newFrame(card, "Icon", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(TOAST_ICON, TOAST_ICON),
		BackgroundTransparency = 1,
		BackgroundColor3 = chip.Face,
	})
	local iconStroke = Theme.Stroke(icon, SIGN.Wood, TOAST_EDGE, 1)
	iconStroke.Name = "SignEdge"
	iconStroke.LineJoinMode = Enum.LineJoinMode.Miter
	PixelCrisp.Edge(iconStroke, TOAST_EDGE)
	local iconLip = newFrame(icon, "Lip", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, TOAST_CHIP_LIP),
		BackgroundTransparency = 1,
		BackgroundColor3 = chip.Lip,
	})
	PixelCrisp.Lip(iconLip, TOAST_CHIP_LIP)
	local holder, glyph = PixelCrisp.Icon(icon, chip.Icon, TOAST_GLYPH, chip.Ink, {
		Position = UDim2.new(0.5, 0, 0.5, -1), -- centred on the face above the lip
	})
	glyph.TextTransparency = 1 -- the icon fades in and out with the glyph's TextTransparency
	icon:SetAttribute("Kind", kindName)
	-- a reward gets one pixel sparkle on the chip's top-right corner (the Sky Trove's reward tags have two), in the deep
	-- gold that shows on the tile and at the icon's own pixel size (one pixel size per screen)
	local sparkle = nil
	if chip.Sparkle then
		local _, s = PixelCrisp.Icon(icon, "sparkle", TOAST_GLYPH, SIGN.GoldDeep, {
			Name = "Sparkle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 2, 0, 2),
			ZIndex = 3,
		})
		sparkle = s
		sparkle.TextTransparency = 1
	end

	local label = newText(card, "Text", text, "Toast", TOAST_TEXT_SIZE, toastTextColor(), {
		Position = UDim2.new(0, TOAST_ICON + 10, 0, 0),
		Size = UDim2.new(1, -(TOAST_ICON + 10), 0, TOAST_TEXT_MIN),
		TextWrapped = true,
		TextTransparency = 1,
	})

	local toast = {
		Slot = slot, Card = card, Stroke = stroke, Lip = lip, Icon = icon, IconStroke = iconStroke, IconLip = iconLip,
		IconGlyph = glyph, IconHolder = holder, Sparkle = sparkle, Label = label, Text = text, Kind = kindName, Count = 1,
		Dead = false, Expiry = 0, Color = color,
	}
	-- (U9-9 look) the text row sized to whole px (again once the text is laid out), then the chip and its icons on whole
	-- px of the card
	sizeToastText(toast)
	label:GetPropertyChangedSignal("TextBounds"):Connect(function()
		if not toast.Dead then
			sizeToastText(toast)
			PixelCrisp.Refresh(card)
		end
	end)
	PixelCrisp.Box(icon)
	PixelCrisp.Refresh(card)
	return toast
end

-- (audio wave 2 fix) client/SoundFx, lazy; false = unavailable
local soundFxMod = nil
local function playSfx(name)
	if soundFxMod == nil then
		local module = Client:FindFirstChild("SoundFx")
		local ok, mod = false, nil
		if module then
			ok, mod = pcall(require, module)
		end
		soundFxMod = (ok and type(mod) == "table" and type(mod.Play) == "function") and mod or false
	end
	if soundFxMod then
		pcall(soundFxMod.Play, name)
	end
end

local function addToast(text, kind, duration)
	if not UI.Stack then
		return
	end
	text = truncateText(text, MAX_TOAST_CHARS)
	if text == "" then
		return
	end
	duration = Util.Clamp(tonumber(duration) or DEFAULT_DURATION, MIN_DURATION, MAX_DURATION)

	-- merge an identical toast that is still showing
	local _, kindName = kindColor(kind)
	for _, live in ipairs(toasts) do
		if not live.Dead and live.Text == text and live.Kind == kindName then
			live.Count = live.Count + 1
			refreshToastText(live)
			-- (kit B U9-9) the repeat flashes the stone face pale gold (the text stays brown and readable)
			live.Card.BackgroundColor3 = SIGN.Selected
			tween(live.Card, 0.35, { BackgroundColor3 = SIGN.Tile }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			scheduleExpiry(live, duration)
			return
		end
	end

	local toast = buildToast(text, kind)
	toast.Born = os.clock()
	if kindName == "bad" then
		playSfx("Error") -- a refused action (a NEW "bad" toast; its merged repeats stay silent; Config MinGap 1 s)
	end
	table.insert(toasts, toast)
	-- never more than MAX_TOASTS (and never further down than the screen allows): the oldest leave first
	while #toasts > MAX_TOASTS do
		dismissToast(toasts[1])
	end
	-- (U9-9 review) the column where trimToasts measures it: the touch RUN / DASH may have come or gone since the last
	-- relayout (MovementController shows them on a spawn), and nothing on the HUD moved to tell us
	applyMargins()
	trimToasts()

	toast.Card.Position = UDim2.new(0, TOAST_W + 40, 0, 0)
	tween(toast.Card, 0.38, { Position = UDim2.new(0, 0, 0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	setToastAlpha(toast, 0, 0.2)
	scheduleExpiry(toast, duration)
end

-- true when the toast column fits one more toast with this text under the live ones (height only)
local function columnFits(text)
	local k = currentScale()
	local place = toastPlacement()
	local used = 0
	for _, live in ipairs(toasts) do
		used = used + liveToastHeight(live) + TOAST_GAP
	end
	return used + estimateToastHeight(text) <= (place.Bottom - place.Top) / math.max(0.01, k)
end

-- Shows the oldest waiting toast when the column has room for it again (one at a time; stale ones are dropped).
function flushWaiting()
	local now = os.clock()
	while #waiting > 0 and waiting[1].Until < now do
		table.remove(waiting, 1)
	end
	local entry = waiting[1]
	if not entry or not UI.Stack then
		return
	end
	-- (kit-b) an empty column always takes it, as the held toasts' drain does (drainStep) and as a new toast is always
	-- shown (trimToasts keeps the newest): a text taller than a short column (the strips stacked down a landscape phone)
	-- waited for room it could never get and was never read
	if #toasts > 0 and not columnFits(entry.Text) then
		return -- still no room: tried again when the next toast leaves
	end
	table.remove(waiting, 1)
	addToast(entry.Text, entry.Kind, entry.Duration)
end

-- (quick wins, review round 1) the drain of the released held toasts: one every HELD_PACE seconds while the column has
-- room (fewer than MAX_TOASTS live and it fits; an empty column always takes one), so a long list is read one by one
-- instead of the newest pushing the first out. Paused while held again (the /menu reopen); resumed at that release.
-- A failing step drops the rest with a warning (drainReleased), so the chain can never stick armed.
local drainStep
local function drainReleased()
	local ok, err = pcall(drainStep)
	if not ok then
		drainArmed = false
		released = {}
		warn("[NotifyController] the held toasts failed: " .. tostring(err))
	end
end

function drainStep()
	drainArmed = false
	if next(holders) ~= nil or #released == 0 then
		return
	end
	local entry = released[1]
	if not UI.Stack then
		released = {} -- no toast column to show them on
		return
	end
	local live = #toasts
	if live == 0 or (live < MAX_TOASTS and columnFits(tostring(entry.Text))) then
		table.remove(released, 1)
		for _ = 1, math.max(1, entry.Count or 1) do
			addToast(entry.Text, entry.Kind, entry.Duration) -- repeats merge into "text x2"
		end
	end
	if #released > 0 then
		drainArmed = true
		task.delay(HELD_PACE, drainReleased)
	end
end

local function buildToastStack()
	local holder, pad = newHolder("ToastHolder")
	UI.ToastPad = pad
	local stack = newFrame(holder, "ToastStack", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(TOAST_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.Padding = UDim.new(0, TOAST_GAP)
	list.Parent = stack
	UI.Stack = stack
	UI.StackScale = addViewportScale(stack)
	UI.StackScale.Scale = math.max(1, math.floor(TOAST_W * currentScale() + 0.5)) / TOAST_W -- (U9-9 look) as relayout
end

----------------------------------------------------------------------
-- Result card
----------------------------------------------------------------------
local function closeResults(immediate)
	local panel = result.Panel
	result.Serial = result.Serial + 1
	result.Panel = nil
	publishResultCard()
	if not panel or not panel.Root or not panel.Root.Parent then
		return
	end
	if immediate then
		panel.Destroy()
		return
	end
	tween(panel.Root, 0.3, { Position = resultPosition(1.8) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.35, function()
		if panel.Root.Parent then
			panel.Destroy()
		end
	end)
end

-- Count a label up from 0 to `target`. The serial stops it if the card closed meanwhile.
local function countUp(label, target, delay, seconds, format, serial)
	task.spawn(function()
		task.wait(delay)
		local started = os.clock()
		while true do
			if result.Serial ~= serial or not label.Parent then
				return
			end
			local a = (os.clock() - started) / seconds
			if a >= 1 then
				label.Text = format(target)
				return
			end
			local eased = 1 - (1 - a) * (1 - a) * (1 - a)
			label.Text = format(math.floor(target * eased + 0.5))
			task.wait(0.03)
		end
	end)
end

-- Square "pixel" confetti (the voxel world's little sparkle) falling over the card. (kit B U9-9) In the kit's gold and pink
-- with their lips (the Gifts window's week confetti), no rainbow.
local KIT_CONFETTI = { SIGN.Gold, SIGN.Roof, SIGN.GoldLip, SIGN.RoofLip }
NotifyController.Confetti = KIT_CONFETTI
local function burstConfetti(root, serial)
	local palette = KIT_CONFETTI
	for i = 1, CONFETTI_PIECES do
		local x = rng:NextNumber(0.06, 0.94)
		local startY = rng:NextNumber(-6, 18)
		local px = rng:NextInteger(6, 10)
		local piece = newFrame(root, "Confetti", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(x, 0, 0, startY),
			Size = UDim2.fromOffset(px, px),
			BackgroundTransparency = 1,
			BackgroundColor3 = palette[(i % #palette) + 1],
			Rotation = rng:NextInteger(0, 3) * 90,
			ZIndex = 12,
		})
		task.delay(rng:NextNumber(0.2, 0.7), function()
			if result.Serial ~= serial or not piece.Parent then
				return
			end
			piece.BackgroundTransparency = 0
			local fall = rng:NextNumber(130, 220)
			tween(piece, rng:NextNumber(0.9, 1.4), {
				Position = UDim2.new(Util.Clamp(x + rng:NextNumber(-0.12, 0.12), 0.02, 0.98), 0, 0, startY + fall),
				Rotation = piece.Rotation + rng:NextInteger(-2, 2) * 90,
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(1.5, function()
				if piece.Parent then
					piece:Destroy()
				end
			end)
		end)
	end
end

local function normaliseMembers(list)
	local out = {}
	if type(list) == "table" then
		for _, m in ipairs(list) do
			if type(m) == "table" then
				table.insert(out, {
					Name = tostring(m.Name or "?"),
					Tokens = math.max(0, math.floor(tonumber(m.MatchTokens) or 0)),
					Finished = m.Finished == true,
					Downed = m.Downed == true,
				})
			end
			if #out >= 4 then
				break
			end
		end
	end
	return out
end

local function isLocalName(name)
	return name == LocalPlayer.Name or name == LocalPlayer.DisplayName
end

local function buildResults(data)
	local won = data.Won == true
	local diff = Config.GetDifficulty and Config.GetDifficulty(data.DifficultyId) or nil
	local diffColor = (diff and diff.Color) or Colors.Stamina
	local starCount = tonumber(data.Stars) or (diff and diff.Stars) or 0
	local members = normaliseMembers(data.Members)
	local reason = (not won) and REASON_TEXT[tostring(data.Reason or "defeat")] or nil

	-- fixed vertical layout (inner coordinates); (kit B U9-9) the stat rows are stone blocks 6 px apart; the compact rows
	-- when the full card is taller than the screen's room for it, the mini card when the compact one is too (RESULT_ROWS)
	local insetTop, _, insetBottom = CloudUI.ContentInset(false, true)
	local hasBonus = (tonumber(data.Bonus) or 0) >= 1
	local function layoutWith(rows)
		local out = { Rows = rows }
		out.Stats = (rows.MergeBonus or (rows.SkipZeroBonus and not hasBonus)) and 2 or 3
		if rows.NoTime then
			out.Stats = out.Stats - 1 -- (P2 fix A) the micro card: no Time row
		end
		out.Cols = (rows.Columns and #members > 2) and rows.Columns or 1
		out.Members = #members > 1 and not rows.NoTeam
		local y = 0
		out.TitleY = y
		y = y + rows.Title
		out.DiffY = y
		y = y + rows.Diff
		out.ReasonY = y
		if reason then
			y = y + rows.Reason
		end
		y = y + rows.Gap
		out.StatsY = y
		y = y + rows.Row * out.Stats -- (U9-9 look) each row ends in its RowGap of stone
		out.MembersY = y
		if out.Members then
			y = y + math.ceil(#members / out.Cols) * rows.Member + 5
		end
		out.FootY = y
		y = y + rows.Foot
		out.PanelH = insetTop + insetBottom + rows.Slack + y - rows.Trim
		-- (U9-9 look) the card's height an even number of screen px where one is near: its centre sits on a whole px
		-- (resultPosition), so its top and bottom do too
		local k = currentScale()
		for add = 0, 20 do
			local v = (out.PanelH + add) * k
			if math.abs(v - math.floor(v + 0.5)) < 1e-4 and math.floor(v + 0.5) % 2 == 0 then
				out.PanelH = out.PanelH + add
				break
			end
		end
		return out
	end
	local L, tier = nil, nil
	for _, name in ipairs(RESULT_TIERS) do
		L, tier = layoutWith(RESULT_ROWS[name]), name
		local okRoom, room = pcall(resultRoom, L.Rows.W)
		if not okRoom or type(room) ~= "number" or L.PanelH <= room then
			break
		end
	end
	local R = L.Rows
	local TITLE_H, REASON_H, ROW_H, MEMBER_H, FOOT_H = R.Title, R.Reason, R.Row, R.Member, R.Foot
	local titleY, diffY, reasonY, statsY, membersY, footY = L.TitleY, L.DiffY, L.ReasonY, L.StatsY, L.MembersY, L.FootY
	local showMembers = L.Members
	local panelH, panelW = L.PanelH, R.W
	result.Height, result.Width = panelH, panelW

	-- (kit B U9-9) the Signboard skin: wood frame, stone body and its lip, the red close block; the awning as wide as the
	-- card (the pitch's roof reaches 10 px past each side; a fixed size, never stretched)
	local panel = CloudUI.Panel({
		Name = "ResultCard",
		Skin = "Signboard",
		Size = UDim2.fromOffset(panelW, panelH),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = resultPosition(1.8, panelH, panelW),
		Closable = true,
		CloseBlock = false, -- (merge U9-9 x kitb-look1) the close sits in the banner's face, sized and drawn below
		OnClose = function()
			closeResults(false)
		end,
		Parent = UI.ResultHolder,
	})
	panel.Body.Active = false
	if panel.Roof then
		panel.Roof.Size = UDim2.fromOffset(panelW + 2 * RESULT_ROOF_OVER, panel.Roof.Size.Y.Offset)
	end
	addViewportScale(panel.Root)
	local inner = newFrame(panel.Content, "Inner", {
		Position = UDim2.new(0, 4, 0, 2 - R.Trim),
		Size = UDim2.new(1, -8, 1, -4 + R.Trim),
	})
	panel.Root:SetAttribute("Compact", R ~= RESULT_ROWS.Full)
	panel.Root:SetAttribute("Rows", tier) -- (U9-9 review) Full / Compact / Mini, (P2 fix A) Micro
	-- (U9-9 look) the card is a crisp root: it slides in, and its blocks and icons sit on whole px of it at rest
	PixelCrisp.Root(panel.Root)

	-- (U9-9 look) one grammar with the run's other end cards (U9-6 RUN OVER, U9-7 FLOOR CLEARED): the outcome on the stone
	-- body's lip (green for a win, red for a loss) and two dark nails at the body's top corners (U9-7's SignKit.Nails look:
	-- WoodDark, 4 px, 5 in); the awning and the banner stay this card's own
	local stone = panel.Body and panel.Body:FindFirstChild("Stone")
	local stoneLip = stone and stone:FindFirstChild("Lip")
	if stoneLip then
		stoneLip.BackgroundColor3 = won and SIGN.GrassLip or SIGN.RedLip
		stoneLip:SetAttribute("Outcome", won and "Win" or "Loss")
		PixelCrisp.Lip(stoneLip, stoneLip.Size.Y.Offset)
	end
	if stone then
		-- on the root over the content: the compact cards' banner rides up under the awning (Trim), and the nails hold it
		local inX, inY = stone.Position.X.Offset + RESULT_NAIL_IN, stone.Position.Y.Offset + RESULT_NAIL_IN
		for _, side in ipairs({ 0, 1 }) do
			local nail = newFrame(panel.Root, side == 0 and "NailL" or "NailR", {
				AnchorPoint = Vector2.new(side, 0),
				Position = UDim2.new(side, side == 0 and inX or -inX, 0, inY),
				Size = UDim2.fromOffset(RESULT_NAIL, RESULT_NAIL),
				BackgroundTransparency = 0,
				BackgroundColor3 = SIGN.WoodDark,
				ZIndex = 9,
			})
			nail:SetAttribute("SignKit", "Nail")
			PixelCrisp.Adopt(nail, RESULT_NAIL) -- a whole-px square on a whole px
		end
	end

	-- the headline: a banner block across the card's top (VICTORY! gold, DEFEAT stone with the loss's red lip) with brown
	-- words, a plain Section title (a pop-up's title: the window ribbon is for window names); the red close block sits on
	-- its right end, inside the banner's face above its lip
	local banner = newFrame(inner, "Banner", {
		Position = UDim2.fromOffset(0, titleY),
		Size = UDim2.new(1, 0, 0, TITLE_H),
	})
	local bannerEdge, bannerLip = CloudUI.SignBlock(banner, won and "Selected" or "Stone", {
		EdgePx = 3,
		LipPx = RESULT_BANNER_LIP,
		Lip = (not won) and SIGN.RedLip or nil,
	})
	PixelCrisp.Edge(bannerEdge, 3)
	PixelCrisp.Lip(bannerLip, RESULT_BANNER_LIP)
	PixelCrisp.Box(banner)
	Theme.StyleTitle(newText(banner, "Headline", won and "VICTORY!" or "DEFEAT", "Title", R.Headline, SIGN.Text, {
		Size = UDim2.new(1, -(R.Close + 10), 1, -RESULT_BANNER_LIP),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	}), "Section")
	if panel.CloseButton then
		local close = panel.CloseButton
		close.Size = UDim2.fromOffset(R.Close, R.Close)
		close.AnchorPoint = Vector2.new(1, 0.5)
		-- root px: the card's Content sits at (12, the untitled inset), Inner 4 / 2 inside it
		local insetTop2 = CloudUI.ContentInset(false, true)
		close.Position = UDim2.new(1, -(12 + 4 + 6), 0, insetTop2 + 2 - R.Trim + titleY + math.floor((TITLE_H - RESULT_BANNER_LIP) / 2))
		-- (U9-9 look) its wood edge and lip on whole px (2.4 px drew uneven)
		local lipPx = 0
		for _, c in ipairs(close:GetChildren()) do
			if c:IsA("UIStroke") then
				PixelCrisp.Edge(c, c:GetAttribute("CrispEdge") or c.Thickness)
			elseif c.Name == "Lip" and c:IsA("GuiObject") then
				lipPx = c:GetAttribute("CrispLip") or c.Size.Y.Offset
				PixelCrisp.Lip(c, lipPx)
			end
		end
		PixelCrisp.Box(close)
		-- (U9-9 look 2) the X is the pitch's pixel icon (ic("x")) on the card's 2 px cell, brown on the red block, centred in
		-- the face above the lip: NeonKit.CloseMark's four bars turned 45 degrees drew a smooth anti-aliased X beside the
		-- toasts' crisp pixel x. (The same change for every kit B window's close block belongs in NeonKit.CloseMark, a
		-- shared file: raised at the gate)
		local old = close:FindFirstChild("CloseMark")
		local z = old and old.ZIndex or (close.ZIndex + 2)
		if old then
			old:Destroy()
		end
		PixelCrisp.Icon(close, "x", 18, SIGN.Text, {
			Name = "CloseMark",
			Position = UDim2.new(0.5, 0, 0.5, -math.floor(lipPx / 2)),
			ZIndex = z + 1,
		})
	end
	-- (U9-9 look 2) the frame's parts on whole px on all four sides: the stone inside the wood (4.8 px), the awning and
	-- its face (14.4 px high, a 3.2 px border)
	PixelCrisp.Box(panel.Body)
	if stone then
		PixelCrisp.Box(stone)
	end
	if panel.Roof then
		PixelCrisp.Box(panel.Roof)
		local face = panel.Roof:FindFirstChild("Face")
		if face then
			PixelCrisp.Box(face)
		end
	end

	-- (U9-9 look) the difficulty is a role chip in the kit's tag language (as FIGHTER / HELPER and the rarity tags): its
	-- colour on the face, its darker lip, a 2 px wood edge, the word and its stars inside in the ink that reads on it, the
	-- whole chip centred 4 px under the banner (the short bar under the words read as a slip). The mini card has none
	if not R.NoDiff then
		local diffText = tostring(data.DifficultyName or data.DifficultyId or "")
		local k = currentScale()
		-- (kit-b U9 merge check) the chip's word is 18 px under the screen's scale: the face moves the least it takes to read
		-- 4.5:1 (Extreme's red read 3.86:1 with the brown ink); the lip keeps the difficulty's own colour
		local face, ink = Theme.ReadableFace(diffColor, 4.5)
		local stars = math.min(5, math.max(0, math.floor(starCount)))
		local starsW = stars > 0 and (stars * 18 + (stars - 1) * 2 + RESULT_ICON_GAP) or 0
		local chip = newFrame(inner, "DiffChip", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, diffY + 10),
			Size = UDim2.fromOffset(200, 30),
		})
		local chipEdge, chipLip = CloudUI.SignBlock(chip, { Face = face, Lip = Theme.Darken(diffColor, 0.35), Edge = SIGN.Wood, Text = ink }, {
			EdgePx = 2,
			LipPx = RESULT_BANNER_LIP,
		})
		PixelCrisp.Edge(chipEdge, 2)
		PixelCrisp.Lip(chipLip, RESULT_BANNER_LIP)
		chip:SetAttribute("Difficulty", tostring(data.DifficultyId or ""))
		local diffLabel = newText(chip, "Difficulty", diffText, "Heading", 18, ink, {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, -RESULT_BANNER_LIP),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
		})
		if stars > 0 then -- (kit-b U7a) the stars are PixelIcons after the name, (U9-9 look) in the chip's ink
			PixelCrisp.Adopt(PixelIcon.Lead(diffLabel, "star", { After = true, Count = stars, Px = 18, Colour = ink, Gap = RESULT_ICON_GAP }))
		end
		-- the chip as wide as its word (as laid out; a measure until then) and its stars, whole px wide
		local function fitChip()
			local textW = diffLabel.TextBounds.X / math.max(0.01, PixelCrisp.ScaleAbove(diffLabel))
			if textW <= 0 then
				local okW, measured = pcall(Theme.Measure, diffText, "Heading", 18)
				textW = (okW and typeof(measured) == "Vector2") and measured.X or #diffText * 11
			end
			chip.Size = UDim2.fromOffset(PixelCrisp.Len(math.ceil(textW) + starsW + 20, k), 30)
			PixelCrisp.Refresh(chip)
		end
		fitChip()
		diffLabel:GetPropertyChangedSignal("TextBounds"):Connect(fitChip)
		PixelCrisp.Box(chip)
	end
	if reason then
		if R.ShortReason then
			reason = REASON_SHORT[tostring(data.Reason or "defeat")] or reason
		end
		newText(inner, "Reason", reason, "Body", 18, SIGN.TextMuted, {
			Position = UDim2.fromOffset(0, reasonY),
			Size = UDim2.new(1, 0, 0, REASON_H),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end

	-- stats
	local serial = result.Serial
	-- (kit B U9-9) a stat row: a stone block (tile face, 2 px wood edge, its lip), the caption and the value brown. (U9-9
	-- look) The block is Row - RowGap high (whole px at 0.8 and 1080p) and its value row ends on the lip, so an 18 px coin
	-- sits inside the face with a pixel clear above it and above the lip
	local function statRow(index, caption, valueText, valueColor)
		local rowY = statsY + (index - 1) * ROW_H
		local bar = newFrame(inner, "Row" .. caption, {
			Position = UDim2.fromOffset(2, rowY + 2),
			Size = UDim2.new(1, -4, 0, ROW_H - R.RowGap),
		})
		local barEdge, barLip = CloudUI.SignBlock(bar, "Stone", { EdgePx = 2, LipPx = RESULT_ROW_LIP })
		PixelCrisp.Edge(barEdge, 2)
		PixelCrisp.Lip(barLip, RESULT_ROW_LIP)
		PixelCrisp.Box(bar)
		newText(bar, "Caption", caption, "Body", 18, SIGN.Text, {
			Position = UDim2.new(0, 10, 0, 0),
			Size = UDim2.new(0.45, 0, 1, -RESULT_ROW_LIP),
		})
		return newText(bar, "Value", valueText, "Heading", R.Value, valueColor, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0.55, 0, 1, -RESULT_ROW_LIP),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	local coinOpts = { After = true, Gap = RESULT_ICON_GAP, Colour = RESULT_COIN }

	-- MatchTokens is what was PAID OUT to this player (pet TokenBonus and rounding carry included), while
	-- TotalTokens is the course's raw token value, so the two must not be shown as "own / total" ("48 / 24"
	-- with a +100% pet). The row shows the personal payout on its own, like the member list below.
	local ownTokens = math.max(0, math.floor(tonumber(data.MatchTokens) or 0))
	local bonus = math.max(0, math.floor(tonumber(data.Bonus) or 0))
	local seconds = tonumber(data.Seconds) or 0

	-- (P2 fix A) the micro card leaves the Time row out: the Tokens row is its first
	local tokenIndex = 1
	if not R.NoTime then
		statRow(1, "Time", Util.FormatTime(seconds), SIGN.Text)
		tokenIndex = 2
	end
	-- (kit-b U7a) the amounts end in the Cloud Token coin (a PixelIcon after the number)
	local tokenValue = statRow(tokenIndex, "Tokens", "0", SIGN.Text)
	PixelCrisp.Adopt(PixelIcon.Lead(tokenValue, Theme.Currency.Tokens.Icon, coinOpts))
	-- (kit B U9-9) the compact card leaves a missing bonus out (L.Stats 2); (U9-9 look) the mini card shows it in the
	-- Tokens row. (U9-9 look 2) On a gold chip (the kit's Selected face and its lip, the HUD's run chip) left of the total,
	-- so the "+10" reads as the win bonus (plain "11  +10" said nothing)
	local merged = R.MergeBonus and bonus > 0
	local bonusValue = L.Stats >= 3 and statRow(3, "Win bonus", bonus > 0 and "+0" or "-", bonus > 0 and SIGN.Text or SIGN.TextMuted) or nil
	countUp(tokenValue, ownTokens, 0.45, 0.8, function(n)
		return tostring(n)
	end, serial)
	if merged then
		local row = tokenValue.Parent
		local text = "+" .. tostring(bonus)
		local okW, measured = pcall(Theme.Measure, text, "Heading", 18)
		local textW = (okW and typeof(measured) == "Vector2") and measured.X or #text * 11
		local chip = newFrame(row, "BonusChip", {
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(math.ceil(textW) + 12, RESULT_CHIP_H), -- (PixelCrisp.Box below: on whole px)
			ZIndex = 2,
		})
		-- (no wood edge of its own: in the row's 20 px face the chip's edge doubled the row's wood line; the gold face and
		-- its lip set inside the stone with a clear pixel above and below)
		local chipEdge, chipLip = CloudUI.SignBlock(chip, "Selected", { EdgePx = 2, LipPx = RESULT_CHIP_LIP })
		chipEdge:Destroy()
		PixelCrisp.Lip(chipLip, RESULT_CHIP_LIP)
		chip:SetAttribute("Bonus", bonus)
		newText(chip, "Bonus", text, "Heading", 18, SIGN.Text, {
			Size = UDim2.new(1, 0, 1, -RESULT_CHIP_LIP),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
		})
		-- 6 px left of the count's first digit (the digits end RESULT_ICON_GAP before the coin, PixelIcon.Lead),
		-- re-placed as the count runs up; in the face above the row's lip
		local function placeChip()
			local k = math.max(0.01, PixelCrisp.ScaleAbove(tokenValue))
			local digits = tokenValue.TextBounds.X
			if digits <= 0 then
				local okV, v = pcall(Theme.Measure, tokenValue.Text, "Heading", R.Value)
				digits = ((okV and typeof(v) == "Vector2") and v.X or 0) * k
			end
			local coin = tokenValue:FindFirstChild("TrailIcon")
			local textR = coin and coin.AbsolutePosition.X - RESULT_ICON_GAP * k or (tokenValue.AbsolutePosition.X + tokenValue.AbsoluteSize.X)
			local fromRight = (row.AbsolutePosition.X + row.AbsoluteSize.X - (textR - digits)) / k
			chip.Position = UDim2.new(1, -math.ceil(fromRight + 6), 0.5, -math.floor(RESULT_ROW_LIP / 2))
		end
		placeChip()
		tokenValue:GetPropertyChangedSignal("TextBounds"):Connect(placeChip)
		tokenValue:GetPropertyChangedSignal("Text"):Connect(placeChip)
		PixelCrisp.Box(chip)
	end
	if bonus > 0 and bonusValue then
		PixelCrisp.Adopt(PixelIcon.Lead(bonusValue, Theme.Currency.Tokens.Icon, coinOpts))
		countUp(bonusValue, bonus, 0.9, 0.7, function(n)
			return "+" .. tostring(n)
		end, serial)
	end

	-- members
	if showMembers then
		-- (kit B U9-9) the compact card lays a team of three or four in two columns: each a name and its tick / cross
		local cols = L.Cols
		for i, m in ipairs(members) do
			local col = (i - 1) % cols
			local line = math.floor((i - 1) / cols)
			local row = newFrame(inner, "Member" .. i, {
				Position = UDim2.new(col / cols, col > 0 and 3 or 0, 0, membersY + line * MEMBER_H),
				Size = UDim2.new(1 / cols, cols > 1 and -3 or 0, 0, MEMBER_H),
			})
			PixelCrisp.Box(row) -- (U9-9 look) on a whole px of the card
			local mine = isLocalName(m.Name)
			-- (kit B U9-9) the player's own line on a pale gold strip (the selected face); every name brown
			if mine then
				row.BackgroundTransparency = 0
				row.BackgroundColor3 = SIGN.Selected
				row:SetAttribute("Mine", true)
			end
			-- (U9-9 look) the amount ends 5 design px (4 px at 0.8) before the tick's 18 px icon, the coin as far before it
			newText(row, "Name", m.Name, "Body", 18, SIGN.Text, {
				Position = UDim2.new(0, 6, 0, 0),
				Size = UDim2.new(1, cols > 1 and -36 or -110, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			if cols == 1 then
				local tokens = newText(row, "Tokens", tostring(m.Tokens), "Heading", 18, SIGN.Text, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -35, 0, 0),
					Size = UDim2.fromOffset(70, MEMBER_H),
					TextXAlignment = Enum.TextXAlignment.Right,
				})
				-- (kit-b U7a) the coin before the amount
				PixelCrisp.Adopt(PixelIcon.Lead(tokens, Theme.Currency.Tokens.Icon, { Gap = RESULT_ICON_GAP, Colour = RESULT_COIN }))
			end
			-- (kit-b U7a) the state is a PixelIcon: a tick when finished, an x when downed (kit B: the grass / red lips'
			-- deep tones that read on stone)
			local mark, stateColor = nil, SIGN.Text
			if m.Finished then
				mark, stateColor = "check", SIGN.GrassLip
			elseif m.Downed then
				mark, stateColor = "x", SIGN.RedLip
			end
			local state = newText(row, "State", "", "Heading", 18, stateColor, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -5, 0, 0),
				Size = UDim2.fromOffset(25, MEMBER_H),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			if mark then
				state:SetAttribute("PixelIcon", mark)
				PixelCrisp.Adopt(PixelIcon.Host(state, mark, 18))
			end
		end
	end

	-- footer: countdown to the lobby
	local footer = newText(inner, "Footer", "", "Toast", 19, SIGN.TextMuted, {
		Position = UDim2.fromOffset(0, footY),
		Size = UDim2.new(1, 0, 0, FOOT_H),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	PixelCrisp.Refresh(panel.Root) -- (U9-9 look) every block, lip, edge and icon on whole px of the card
	return panel, footer, serial
end

local function showResults(data)
	if type(data) ~= "table" or not UI.ResultHolder then
		return
	end
	closeResults(true)
	result.Serial = result.Serial + 1
	local ok, panel, footer, serial = pcall(buildResults, data)
	if not ok then
		warn("[NotifyController] result card failed: " .. tostring(panel))
		return
	end
	result.Panel = panel
	publishResultCard()

	tween(panel.Root, 0.5, { Position = resultPosition(1) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if data.Won == true then
		burstConfetti(panel.Root, serial)
	end

	-- "Back to lobby in Ns"
	task.spawn(function()
		local deadline = os.clock() + (Config.Match.EndScreenSeconds or 10)
		while result.Serial == serial and footer.Parent do
			local left = math.ceil(deadline - os.clock())
			if left <= 0 then
				footer.Text = "Going back to the lobby..."
				break
			end
			footer.Text = "Back to lobby in " .. tostring(left) .. "s"
			task.wait(0.2)
		end
		-- safety net: the server normally clears MatchState (which closes the card) right about now
		task.wait(5)
		if result.Serial == serial then
			closeResults(false)
		end
	end)
end

local function buildResultHolder()
	local holder, pad = newHolder("ResultHolder")
	UI.ResultHolder = holder
	UI.ResultPad = pad
end

----------------------------------------------------------------------
-- Other players' dash puffs
----------------------------------------------------------------------
local function newEmitter(parent, props)
	local emitter = Instance.new("ParticleEmitter")
	FxSprites.Apply(emitter, props.Sprite) -- props.Sprite: an FxSprites role (texture + flipbook)
	for key, value in pairs(props) do
		if key ~= "Sprite" then
			emitter[key] = value
		end
	end
	emitter.Parent = parent
	return emitter
end

local function dashPuff(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - root.Position).Magnitude > FX_MAX_DISTANCE then
		return
	end

	local feetOffset = 3
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		feetOffset = humanoid.HipHeight + root.Size.Y * 0.5
	end
	feetOffset = Util.Clamp(feetOffset, 2, 5)

	local instances = {}
	local soft = Theme.Lighten(Colors.Stamina, 0.55)

	local feet = Instance.new("Attachment")
	feet.Name = "NC_DashFeet"
	feet.Position = Vector3.new(0, -feetOffset + 0.2, 0)
	feet.Parent = root
	table.insert(instances, feet)

	local puff = newEmitter(feet, {
		Name = "NC_DashPuff",
		Sprite = "Puff",
		Color = ColorSequence.new(Colors.Cloud, Colors.CloudShade),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 3.2),
		}),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(5, 10),
		SpreadAngle = Vector2.new(70, 70),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Drag = 3,
		LightEmission = 0.05,
		LockedToPart = false,
		Rate = 0,
		Enabled = false,
	})
	puff:Emit(7)

	local sparks = newEmitter(root, {
		Name = "NC_DashSparks",
		Sprite = "Sparkle",
		Color = ColorSequence.new(soft, Colors.Stamina),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.25, 0.45),
		Speed = NumberRange.new(8, 18),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		LightEmission = 0.8,
		LockedToPart = false,
		Rate = 0,
		Enabled = false,
	})
	sparks:Emit(6)
	table.insert(instances, sparks)

	-- a short ribbon through the torso while the dash lasts
	local top = Instance.new("Attachment")
	top.Name = "NC_DashTrailTop"
	top.Position = Vector3.new(0, 1.2, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "NC_DashTrailBottom"
	bottom.Position = Vector3.new(0, -1.4, 0)
	bottom.Parent = root
	table.insert(instances, top)
	table.insert(instances, bottom)

	local trail = Instance.new("Trail")
	trail.Name = "NC_DashTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.3
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 0.5
	trail.Color = ColorSequence.new(soft, Colors.Stamina)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	trail.Parent = root
	table.insert(instances, trail)

	task.delay(Config.Physics.DashDuration + 0.08, function()
		pcall(function()
			trail.Enabled = false
		end)
	end)
	task.delay(1.2, function()
		for _, inst in ipairs(instances) do
			pcall(function()
				inst:Destroy()
			end)
		end
	end)
end

local function onDashFx(userId)
	if type(userId) ~= "number" or userId == LocalPlayer.UserId then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	local now = os.clock()
	local last = lastDashFx[userId]
	if last and now - last < FX_MIN_INTERVAL then
		return
	end
	lastDashFx[userId] = now
	dashPuff(player)
end

----------------------------------------------------------------------
-- Remote handlers + wiring
----------------------------------------------------------------------
-- Kind "pull": the line into the system chat (RBXSystem), the rarity word after the last " hatched a " coloured by
-- Config.Rarities. Answers true when it went to the chat; never yields (FindFirstChild, no WaitForChild).
local function pullToChat(text)
	local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
	local channel = channels and channels:FindFirstChild("RBXSystem")
	if not (channel and channel:IsA("TextChannel")) then
		return false
	end
	local line = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	local at, from = nil, 1
	while true do -- the last " hatched a " (a display name could hold the words too)
		local s, e = string.find(line, " hatched a ", from, true)
		if not s then
			break
		end
		at, from = e, e + 1
	end
	local word = at and string.match(line, "^(%a+)", at + 1)
	-- Config.Eggs.ChatColors overrides a rarity colour that reads badly on the dark chat (Secret's near-black; Task 26)
	local chat = type(Config.Eggs) == "table" and type(Config.Eggs.ChatColors) == "table" and Config.Eggs.ChatColors or {}
	for _, rarity in ipairs(Config.Rarities) do
		local color = word and rarity.Id == word and (typeof(chat[word]) == "Color3" and chat[word] or rarity.Color)
		if typeof(color) == "Color3" then
			line = string.sub(line, 1, at) .. '<font color="' .. hex(color) .. '">' .. word .. "</font>" .. string.sub(line, at + 1 + #word)
			break
		end
	end
	channel:DisplaySystemMessage(line)
	return true
end

-- which held toast leaves when the list is full: the oldest low-value one (HELD_LOW), else the oldest that is not
-- Keep, else the oldest
local function heldVictim()
	local plain = nil
	for i, entry in ipairs(held) do
		if not entry.Keep then
			local _, name = kindColor(entry.Kind)
			if HELD_LOW[name] then
				return i
			end
			plain = plain or i
		end
	end
	return plain or 1
end

-- parks a toast while held (the title screen); an identical one already parked only counts up
local function holdToast(text, kind, duration, keep)
	local now = os.clock()
	for _, entry in ipairs(held) do
		if entry.Text == text and entry.Kind == kind then
			entry.Count = entry.Count + 1
			entry.At = now
			entry.Duration = duration
			entry.Keep = entry.Keep or keep
			return
		end
	end
	table.insert(held, { Text = text, Kind = kind, Duration = duration, Keep = keep, Count = 1, At = now })
	while #held > HELD_MAX do
		table.remove(held, heldVictim())
	end
end

-- opts (4th argument, optional table): System = true shows it even while held (the save-wait toasts: they describe the
-- moment, so they must not arrive late); Keep = true keeps it through the hold's age limit and its cap (the join welcome)
local function onNotify(text, kind, duration, opts)
	opts = type(opts) == "table" and opts or nil
	if kind == "pull" then
		-- a chat line, not a toast: never held (the chat is not the title screen's toast column)
		local ok, shown = pcall(pullToChat, tostring(text))
		if ok and shown then
			return
		end
		kind = "good" -- no chat channel (or it failed): today's toast
	end
	if next(holders) ~= nil and kind ~= "bad" and not (opts and opts.System == true) then
		holdToast(tostring(text), kind, duration, opts ~= nil and opts.Keep == true)
		return
	end
	addToast(text, kind, duration)
end

local function onMatchResult(data)
	showResults(data)
end

local function onMatchState(state)
	-- the server clears MatchState when it sends the player back to the lobby
	if state == nil then
		closeResults(false)
	end
end

-- Remotes.Get yields until the folder replicates, so every hook runs in its own thread.
local function hook(name, handler)
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, name)
		if not ok or not remote then
			warn("[NotifyController] remote " .. name .. " unavailable: " .. tostring(remote))
			return
		end
		remote.OnClientEvent:Connect(function(...)
			local okCall, err = pcall(handler, ...)
			if not okCall then
				warn("[NotifyController] " .. name .. " handler failed: " .. tostring(err))
			end
		end)
	end)
end

local function hookCamera()
	local cameraConn = nil
	local function bind()
		if cameraConn then
			cameraConn:Disconnect()
			cameraConn = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				pcall(relayout)
			end)
		end
		pcall(relayout)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind)
	bind()
	task.delay(0.5, function()
		pcall(relayout)
	end)
	task.delay(2, function()
		pcall(relayout)
	end)
end

-- (roll-look review round 1) a local toast, as the Notify remote would show it: for the menu's side hint while its gui
-- (NimbusMenu) is off (the egg stage hides the HUD; NimbusNotify stays). -> true when shown (or queued for room, or held)
function NotifyController.Toast(text, kind, duration)
	if not initialized or not UI.Stack or type(text) ~= "string" then
		return false
	end
	local ok = pcall(onNotify, text, kind or "info", duration)
	return ok
end

-- (quick wins, win 1) owner-keyed hold of the gameplay toasts (see the header). Letting go as the last owner drops the
-- stale ones (older than HELD_SECONDS, unless Keep) and shows the rest one by one in the order sent (drainReleased);
-- an owner that never held changes nothing.
function NotifyController.SetHeld(who, on)
	if type(who) ~= "string" or who == "" then
		return
	end
	if on == true then
		holders[who] = true
		return
	end
	if holders[who] == nil then
		return
	end
	holders[who] = nil
	if next(holders) ~= nil then
		return
	end
	local now = os.clock()
	for _, entry in ipairs(held) do
		if entry.Keep or now - entry.At <= HELD_SECONDS then
			table.insert(released, entry)
		end
	end
	held = {}
	if not drainArmed then
		drainReleased()
	end
end

function NotifyController.IsHeld()
	return next(holders) ~= nil
end

function NotifyController.Init()
	if initialized then
		return
	end
	initialized = true
	if not LocalPlayer then
		return
	end

	-- hook the remotes first so nothing sent while the GUI builds is lost to a yield
	hook("Notify", onNotify)
	hook("MatchResult", onMatchResult)
	hook("MatchState", onMatchState)
	hook("DashFx", onDashFx)

	local ok, err = pcall(function()
		UI.Gui = CloudUI.NewScreenGui("NimbusNotify", 30)
		buildResultHolder() -- first: toasts are created afterwards, so they draw on top of the card
		buildToastStack()
		applyMargins()
		hookCamera()
	end)
	if not ok then
		warn("[NotifyController] GUI setup failed: " .. tostring(err))
	end
	task.spawn(function()
		local okHud, hudErr = pcall(watchHud)
		if not okHud then
			warn("[NotifyController] could not follow the HUD layout: " .. tostring(hudErr))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastDashFx[player.UserId] = nil
	end)
end

return NotifyController
