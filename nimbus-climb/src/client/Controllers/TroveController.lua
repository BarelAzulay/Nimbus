-- TroveController (client, store 2026-11-04; docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.3 / 8 / 13b.5):
-- the Sky Trove panel and the chest's lid.
--
--   TroveController.Init()
--   TroveController.Open(state)   shows the panel (state = a TroveState table, optional: the last one is kept)
--   TroveController.Close()
--   TroveController.IsOpen() -> bool
--
-- How it opens: the server's OpenPanel("Trove") (TroveService, after the chest's prompt passed its checks) arrives here
-- (MenuController's onOpenPanel falls through for this id), TroveState(state) fills and refreshes the rows. The client
-- decides nothing: the server checks the group and pays.
--
-- The panel (ScreenGui NimbusTrove, DisplayOrder 18; IgnoreGuiInset false like every text-bearing gui, client_load):
-- docked right so the chest stays in view. Box: NeonKit.SideRect(520, 380, 420, 226) answers whether the 1080p design
-- fits; when it does the PC layout (520 x 380 design px at the rect's scale, 12 px x factor from the right, its top
-- 8 px x factor + the awning's 10 px under the HUD's currency strips and the gift's square: NimbusHud TopRightBottom, as
-- the Stats window docks; U9-4 look review: on top of them a sliver of the strips showed), otherwise (or where that dock
-- would run off a short desktop window) the phone layout at scale 1 (420 x 226, 12 px
-- from the right, top = inset + 8; on a touch screen where that box would end on the game's DASH button it reaches down
-- to THUMB_GAP px over Roblox's jump button instead, see phoneHeight); a portrait screen gets the bottom sheet (as wide
-- as the screen allows up to 400, 274 tall, 12 px over the bottom right) so the character stays clear.
-- (kit-b U9-4, finding 15) the Signboard kit: "TrovePanel" is the wood frame round "Stone" (the stone body with its
-- lip); (U9-4 look review) "Header" is SignKit.Header as the Stats / My Home side panels build theirs: the wood rim, the
-- navy "Plate" the title's band (look review 2: inside the rim with no tails at every size, the docked panel's rule)
-- holding "TroveIcon" (the gold icon square in its 2 px ink edge with the pixel chest), "TitleText" ("SKY TROVE" with its
-- stair), and "Close" (the red block on the plate, its X in brown ink; a phone: 36 px over its 44 px "CloseTap");
-- "Roof" the fixed-size awning (PC 360, the portrait sheet 240 under clear sky, never the landscape phone panel; never
-- stretched). Each ask is a stone block ("Row_Group",
-- "Row_Like") with a square icon chip ("Chip": the pixel people on sky, the heart on pink); the rewards are gold tags
-- ("CashChip" "$2,000", "TokenChip" the token coin + "200"); while the reward waits (Open) two pixel sparkles by the tags
-- take turns every second (the family's glint, as the Gifts window's today tile); "JoinButton" is the panel's one green
-- action. Nothing round or glossy, no neon.
--   PC:    header 60 (the 42 icon square, Title 32, X 40); subtitle Body 20 "Help Nimbus grow and the Trove pays you!"; rows 100 /
--          88 (chip 72 with its 54 px icon, label 20, tags 19 on 36, button 140 x 52); the footer 19 (>= 15 px at 1280x720's
--          0.8 scale)
--   phone: header 50 (a 36 square, Title 22, a 36 px X in its 44 px touch box); no subtitle (the panel keeps clear of the
--          jump button); rows 62 / 46 (chip 34, or 48 where both rows have room, label 15-16 on one line, tags 15,
--          button 96 x 44), the footer 15; (U9-4 review) the game's DASH
--          button sits 10 px over the jump button, so a 226 px panel ended on it on touch phones 390 to 460 px tall
--          (under the 58 px top bar: a sliver of DASH under its edge); there the panel stretches into that gap (228 at
--          844x390, 231 at 852x393, 268 at 932x430), covering DASH and its stroke whole and keeping the controls; a
--          quarter of the spare to each ask, the rest to the gaps round them; portrait: the lines wrap
-- The Group row: "Join the Nimbus Climb group" + the tags; its button reads Join (Open), Done (disabled, Done), Preview
-- (disabled, Preview: GroupId 0 in the Studio preview), sentence case (the kit's casing rule); no button for Checked /
-- Unavailable / Loading / Soon (Soon's label reads "Coming soon"). The Like row has no button. The footer: "Community
-- links are on our game page. Prizes go straight to you. Once per player." Join -> pcall(GroupService.PromptJoinAsync,
-- GroupId): Joined / AlreadyMember -> TroveRequest("Joined"); JoinRequestPending -> the hint "Your request is waiting
-- for the group. Come back later!"; None / an error -> "Not joined yet. Join from the game page, then come back in a new
-- server." (the hint takes the footer's place, in the kit's red ink).
-- Touch (the owner's rule: no control under Roblox's thumbstick or jump button): on a touch-only screen the panel keeps
-- Roblox's touch controls (the player can walk off) wherever its whole box clears the stick's zone and the jump button by
-- 6 px (HudController's rects); where it cannot (a short landscape phone, the portrait sheet) they go while it is open
-- (MenuController.SetTouchHidden("Trove")) and come back on Close. The HUD's vitals card steps aside while the panel lies
-- over it (HudController.SetVitalsHidden("Trove")).
-- The claim (a Done transition while the panel is open): the lid (CollectionService:GetTagged(Config.Tags.TroveLid)[1],
-- pivoted on its PrimaryPart hinge) swings 18 -> 70 degrees over 0.35 s (Back); on High 18 pooled client-only coins arc
-- from the chest into the character over 0.8 s; SoundFx "TroveOpen" ("Reward" until that key has an id); the toast is the
-- server's. Low: the lid and the sound only (the NC_Detail light and sparkles are already parked). No camera move.
-- One window at a time: opening fires MenuController.WindowOpened("Trove"); any other window id (and the other
-- controllers' Opened signals), entering a match and Esc close it.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local GroupService = game:GetService("GroupService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U9-4) the chest, the row icons, the token coin, the sparkles
local SignKit = require(Shared:WaitForChild("SignKit")) -- (kit-b U9-4) the awning over the panel
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))

local TroveController = {}

local SIGN = Theme.Sign
local K = {
	DISPLAY_ORDER = 18,
	PREF_W = 520, PREF_H = 380, MIN_W = 420, MIN_H = 226,
	MARGIN = 12, TOP_GAP = 8,
	FRAME = 6, -- the wood frame round the stone body
	ROOF_W = 360, ROOF_OVER = -SignKit.RoofSeat(), -- the awning: a fixed 360 px, its top 20 design px over the panel's (seated, F0 review)
	-- (U9-4 look review) the portrait sheet's awning (SignKit.Sizes.RoofPhoneW: look review 2, 240, its right end clear of
	-- the close block), wherever ROOF_CLEAR px of clear screen lie over the sheet's top (never on the landscape panel,
	-- which starts under Roblox's top bar)
	ROOF_PHONE_W = SignKit.Sizes.RoofPhoneW, ROOF_CLEAR = 26, -- (F0 review) the seated awning: its box 20 + bracket 2 over the top, 4 clear
	-- (U9-4 look review 2) a phone plate's close: a CloseBlock px red block centred on the plate, its 3 px stroke
	-- CLOSE_INSET - 3 px inside the plate's right end, over its Close px touch box ("CloseTap", under it): the Gifts window's
	CLOSE_INSET = 7,
	REST_DEG = 18, OPEN_DEG = 70, LID_TIME = 0.35,
	COINS = 18, COIN_TIME = 0.8, COIN_FLIGHT = 0.55,
	TWINKLE = 1, -- s each sparkle stays lit
	-- Roblox's own touch controls (gui px; HudController's K: small = the smaller screen side <= SMALL_PHONE): the stick's
	-- zone at the bottom left, the jump button J x J from 1.5 J + 10 to 0.5 J + 10 off the right edge, its bottom 20 px
	-- (small) or 0.75 J over the bottom edge; the panel keeps THUMB_GAP px clear of both or the controls go
	SMALL_PHONE = 500, STICK_W_SMALL = 110, STICK_H_SMALL = 96, STICK_H_PORTRAIT = 150, STICK_W_LARGE = 190, STICK_H_LARGE = 210,
	JUMP_SMALL = 70, JUMP_LARGE = 120, THUMB_GAP = 6,
	-- (U9-4 review) the game's DASH button (MovementController's layoutMobileControls; keep in sync): D x D centred over
	-- the jump button, its bottom DASH_GAP px over the jump button's top, a DASH_STROKE px stroke round it
	DASH_SMALL = 66, DASH_LARGE = 84, DASH_GAP = 10, DASH_STROKE = 3,
}
-- design px; Header = the SignKit header's height (its wood rim on top, the navy plate under it); rows from the panel's
-- top. (U9-4 look review) the header is SignKit.Header as the Stats / My Home side panels build it: Slot = the gold icon
-- square (SignKit.Sizes.IconSlot on PC; a phone's 44 px plate takes a 36 px square), SlotIcon the pixel chest in it,
-- Close the red block on the plate (40 on PC as the Stats window's, 44 on a phone: the touch floor; look review 2, a
-- phone draws a CloseBlock px block in that touch box).
-- (U9-4 look review 2: one pixel size per screen) every pixel icon at one of the kit's two sizes (SignKit.Sizes.Pixel,
-- as the Gifts window): PC the chest, the coin and the sparkles at the glyph size (27, 3 px cells), a row's icon at the
-- art size (54 on a 72 chip); a phone the glyph size (18, 2 px cells) and a row's icon the art size (36 on a 48 chip,
-- ChipBig) where both rows have room for it, else the glyph size on the 34 px chip
local PX = SignKit.Sizes.Pixel
local PC = { W = 520, H = 380, Header = 60, Slot = 42, SlotIcon = PX.PC.Glyph, TitleText = 32, Close = 40, Pad = 16,
	Sub = 20, SubY = 72, SubH = 26, Row1 = 108, Row1H = 100, Row2 = 216, Row2H = 88, Chip = 72, ChipIcon = PX.PC.Art, Label = 20,
	Lines = 2, Tag = 19, TagH = 36, Coin = PX.PC.Glyph, BtnW = 140, BtnH = 52, BtnText = 24, Foot = 19, FootY = 310, FootH = 50,
	Spark = PX.PC.Glyph }
local PHONE = { W = 420, H = 226, Header = 50, Slot = 36, SlotIcon = PX.Phone.Glyph, TitleText = 22, Close = 44, CloseBlock = 36, Pad = 12,
	Sub = 0, Row1 = 56, Row1H = 62, Row2 = 124, Row2H = 46, Chip = 34, ChipIcon = PX.Phone.Glyph, ChipBig = 48, ChipIconBig = PX.Phone.Art,
	Label = 16, Lines = 1, Tag = 15, TagH = 24, Coin = PX.Phone.Glyph, BtnW = 96, BtnH = 44, BtnText = 20, Foot = 15, FootY = 174, FootH = 38,
	Spark = PX.Phone.Glyph }
local PORTRAIT = { W = 400, H = 274, Header = 50, Slot = 36, SlotIcon = PX.Phone.Glyph, TitleText = 22, Close = 44, CloseBlock = 36, Pad = 12,
	Sub = 0, Row1 = 56, Row1H = 80, Row2 = 142, Row2H = 62, Chip = 34, ChipIcon = PX.Phone.Glyph, ChipBig = 48, ChipIconBig = PX.Phone.Art,
	Label = 16, Lines = 2, Tag = 15, TagH = 24, Coin = PX.Phone.Glyph, BtnW = 96, BtnH = 44, BtnText = 20, Foot = 15, FootY = 208, FootH = 52,
	Spark = PX.Phone.Glyph }
local MODES = { PC = PC, Phone = PHONE, Portrait = PORTRAIT }
local TEXT = {
	Title = "SKY TROVE",
	Sub = "Help Nimbus grow and the Trove pays you!",
	Group = "Join the Nimbus Climb group",
	Soon = "Coming soon",
	Like = "Enjoying it? A thumbs up on our game page helps a lot!",
	Footer = "Community links are on our game page. Prizes go straight to you. Once per player.",
	Pending = "Your request is waiting for the group. Come back later!",
	NotJoined = "Not joined yet. Join from the game page, then come back in a new server.",
	Status = { Checked = "Rejoin to check", Unavailable = "Try again soon", Loading = "Loading..." },
	Button = { Open = "Join", Done = "Done", Preview = "Preview" }, -- (kit-b U9-4) sentence case, the kit's casing rule
}
-- (kit-b U9-4) each ask's chip: its pixel icon (Config.Icons: the people, the heart) on the block colour of its role
local ASK = {
	Group = { Icon = "Group", Face = SIGN.Sky, Lip = SIGN.SkyLip },
	Like = { Icon = "Like", Face = SIGN.Roof, Lip = SIGN.RoofLip },
}

local S = {
	Inited = false,
	Open = false,
	State = nil, -- the last TroveState
	Mode = nil, -- "PC" | "Phone" | "Portrait" (the built layout)
	Hint = nil,
	Joining = false,
	LidBase = setmetatable({}, { __mode = "k" }), -- [lid model] = the hinge CFrame at 0 degrees
	Pool = {}, -- the coin parts
	Anim = nil, -- the running claim animation (a Heartbeat connection)
	Rect = nil, -- the panel's box in gui-area px { x, y, w, h } (layout)
	TouchOff = false, -- true while this panel asked Roblox's touch controls away
	VitalsOff = false, -- true while this panel asked the vitals card aside
	Twinkle = nil, -- the sparkles' Heartbeat connection while open
	Lit = false, -- which sparkle is lit (false = A)
}
local U = {} -- Gui, Panel, Scale, M, the parts
TroveController._S = S

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function safe(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[TroveController] " .. label .. " failed: " .. tostring(err))
	end
	return ok, err
end

local function controller(name)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

local function clientModule(name)
	local module = Client:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

local function localPlayer()
	return Players.LocalPlayer
end

local function inMatch()
	local p = localPlayer()
	return p ~= nil and p:GetAttribute(Config.Attr.InMatch) == true
end

local function groupAsk(state)
	local asks = type(state) == "table" and type(state.Asks) == "table" and state.Asks or {}
	for _, a in ipairs(asks) do
		if type(a) == "table" and a.Id == "Group" then
			return a
		end
	end
	return nil
end

local function groupStateOf(state)
	local a = groupAsk(state)
	return a and a.State or nil
end

local function commas(n)
	local out = tostring(math.floor(tonumber(n) or 0))
	while true do
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return out
end

local function viewport()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if vp.X < 2 or vp.Y < 2 then
		return Vector2.new(1920, 1080)
	end
	return vp
end

local function guiInset()
	local inset = NeonKit.Metrics.Inset
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	return inset
end

local function label(parent, name, text, role, size, props)
	local l = Theme.Label(text, role, { Size = size, Props = props })
	l.Name = name
	l.Parent = parent
	return l
end

local function place(inst, x, y, w, h)
	inst.AnchorPoint = Vector2.new(0, 0)
	inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
end

-- a flat Frame (the frame, the body, a lip)
local function block(name, colour, parent, z)
	return Util.Create("Frame", { Name = name, BackgroundColor3 = colour, BorderSizePixel = 0, ZIndex = z or 1, Parent = parent })
end

-- a lip along the bottom of `parent`, px tall
local function lip(parent, colour, px)
	return Util.Create("Frame", {
		Name = "Lip", BackgroundColor3 = colour, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, px), ZIndex = parent.ZIndex, Parent = parent,
	})
end

-- a pixel icon whose cells sit at `z` (PixelIcon draws them at the default ZIndex)
local function icon(parent, name, px, colour, z)
	local i = PixelIcon.New(parent, name, px, colour)
	if i then
		i.ZIndex = z
		for _, f in ipairs(i:GetChildren()) do
			f.ZIndex = z
		end
	end
	return i
end

----------------------------------------------------------------------
-- the panel
----------------------------------------------------------------------
-- (kit-b U9-4) a gold reward tag in its wood edge with brown words (and, for the tokens, the token coin before them)
local function tag(parent, name, coin, M)
	local f = block(name, SIGN.Gold, parent, 6)
	CloudUI.SignBlock(f, "Selected", { EdgePx = 2, LipPx = 3 })
	if coin then
		U.Coin = icon(f, "token", M.Coin, SIGN.Text, 7) -- (look review 2: the layout's glyph size, 27 on PC)
		if U.Coin then
			U.Coin.Name = "Coin"
		end
	end
	label(f, "Text", "", "Heading", 18, {
		TextColor3 = SIGN.Text, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false, ZIndex = 7,
	})
	return f
end

-- (kit-b U9-4) an ask: a stone block in its wood edge with its icon chip at the left
local function makeRow(id, M)
	local row = block("Row_" .. id, SIGN.Tile, U.Panel, 4)
	CloudUI.SignBlock(row, "Stone", { EdgePx = 2, LipPx = SignKit.Sizes.BlockLip })
	local ask = ASK[id]
	local chip = block("Chip", ask.Face, row, 5)
	CloudUI.SignBlock(chip, { Face = ask.Face, Lip = ask.Lip, Edge = SIGN.Wood, Text = SIGN.Text }, { EdgePx = 2, LipPx = 3 })
	local glyph = icon(chip, NeonKit.IconName(ask.Icon) or Config.Icons[ask.Icon], M.ChipIcon, SIGN.Text, 6)
	if glyph then
		glyph.Name = "Glyph"
	end
	return row, chip
end

-- the reward's glint: Frame "Sparkles" over the Group row with two pixel sparkles (SparkleA / SparkleB, PixelIcon
-- "sparkle") that take turns (two frames, no tween, no glow)
local function makeSparkles(row, M)
	local box = Util.Create("Frame", { Name = "Sparkles", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		Active = false, Visible = false, ZIndex = 8, Parent = row })
	for i, name in ipairs({ "SparkleA", "SparkleB" }) do
		local s = icon(box, "sparkle", M.Spark, SIGN.GoldDeep, 8)
		if s then
			s.Name = name
			s.Visible = i == 1
		end
	end
	return box
end

local function build(mode)
	local M = MODES[mode] or PHONE
	if U.Panel then
		U.Panel:Destroy()
	end
	U.M = M
	U.Width = nil
	U.Height = nil
	S.Mode = mode
	S.Lit = false
	local F = K.FRAME
	-- the wood frame round the stone body with its lip
	local panel = block("TrovePanel", SIGN.Wood, U.Gui, 2)
	panel.Visible = S.Open
	panel.Active = true
	panel:SetAttribute("SignKit", "Frame")
	U.Panel = panel
	U.Scale = Util.Create("UIScale", { Name = "TroveScale", Scale = 1, Parent = panel })
	local stone = block("Stone", SIGN.Stone, panel, 2)
	stone:SetAttribute("SignKit", "Body")
	lip(stone, SIGN.StoneLip, SignKit.Sizes.Lip)
	place(stone, F, F, M.W - 2 * F, M.H - 2 * F)
	SignKit.FinishFrame(panel, { Body = stone }) -- (Pitch 2 F0) the frame's light, the window's shadow, the carved body
	-- (U9-4 look review) the header as the Stats / My Home side panels build theirs (SignKit.Header, Ribbon): the wood rim,
	-- the navy plate as the title's band with its piping the whole header wide (inside the rim: the dock rule below), the
	-- pixel chest on the gold icon square in its 2 px ink edge, SKY TROVE with its stair, the red close on the plate
	local head, plate = SignKit.Header(panel, {
		Title = TEXT.Title, TitleSize = M.TitleText, Height = M.Header, Rim = F, IconSlot = true, Ribbon = true,
		Reserve = M.Close + 18, Name = "Header", ZIndex = 5,
	})
	U.Header, U.Plate = head, plate
	U.Title = plate:FindFirstChild("Title")
	if U.Title then
		U.Title.Name = "TitleText"
		U.Title.TextTruncate = Enum.TextTruncate.AtEnd
	end
	U.Icon = plate:FindFirstChild("IconSlot")
	if U.Icon then
		U.Icon.Name = "TroveIcon"
		U.Icon.Size = UDim2.fromOffset(M.Slot, M.Slot)
		local edge = U.Icon:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Name = "SignEdge"
		end
		local chest = icon(U.Icon, Config.Icons.Trove or "chest", M.SlotIcon, SIGN.Text, 3)
		if chest then
			chest.Name = "Chest"
			local at = math.floor((M.Slot - M.SlotIcon) / 2) -- whole px inside the square
			chest.Position = UDim2.fromOffset(at, at)
		end
		if M.Slot ~= SignKit.Sizes.IconSlot and U.Title then
			-- (a phone's smaller square: the title keeps the kit's 12 px gap after it)
			local d = SignKit.Sizes.IconSlot - M.Slot
			U.Title.Position = U.Title.Position - UDim2.fromOffset(d, 0)
			U.Title.Size = U.Title.Size + UDim2.fromOffset(d, 0)
		end
	end
	-- (U9-4 look review 2) docked 12 px from the screen's edge (or across a phone), the band's tails would leave the screen
	-- (its right tail and notches ran past x 1920): the band stays the header's width inside the rim, no tails, the render
	-- gate's dock rule (the Index; the Arena / Dungeon docks on kitb-ui2)
	SignKit.HeaderOverhang(head, false)
	local blockPx = M.CloseBlock or M.Close
	U.Close = CloudUI.Button({ Name = "Close", Text = "", Style = "Red", Skin = "Sign", Size = UDim2.fromOffset(blockPx, blockPx), TextSize = 22,
		ZIndex = 3, Parent = head, Callback = function()
			TroveController.Close()
		end })
	-- slop audit 2026-11-12: a drawn X (the U+2715 glyph showed a missing-glyph box); kit B: square bars in brown ink
	NeonKit.CloseMark(U.Close, { Square = true, Ink = SIGN.RedLip, Color = SIGN.Text })
	-- (merge kitb-look1 x U9-4) the pixel x at the screen's glyph size (one of the window's two pixel sizes), and on a phone
	-- the 36 px block keeps U9-4's 3 px edge and 5 px lip (the kit's 5 / 8 would hang out of the plate)
	NeonKit.CloseMarkPx(U.Close, (mode == "PC" and PX.PC or PX.Phone).Glyph)
	if M.CloseBlock then
		U.Close:SetAttribute("EdgePx", 3)
		U.Close:SetAttribute("LipPx", 5)
	end
	-- (U9-4 look review 2) a phone's 44 px touch box under the 36 px block (a tap on the ring round the block closes too)
	U.CloseTap = nil
	if M.CloseBlock then
		U.CloseTap = Util.Create("TextButton", {
			Name = "CloseTap", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Selectable = false,
			Active = true, ZIndex = 2, Parent = head,
		})
		U.CloseTap.Activated:Connect(function()
			TroveController.Close()
		end)
	end
	-- the awning: one fixed-size piece over the top rim (never stretched with the panel: the sign rule); PC 360, the
	-- portrait sheet ROOF_PHONE_W where the sky over it is clear (layout), never the landscape phone panel
	U.Roof = SignKit.Roof(panel, { Width = mode == "PC" and K.ROOF_W or K.ROOF_PHONE_W, Y = SignKit.RoofSeat(), ZIndex = 7 }) -- (F0 review) seated on the frame
	U.Roof.Visible = mode == "PC"
	U.Subtitle = label(panel, "Subtitle", TEXT.Sub, "Body", math.max(15, M.Sub), {
		TextColor3 = SIGN.Text, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4, Visible = M.Sub > 0,
	})

	-- the Group row: its line, the reward tags (and their glint), Join or a status line
	local group = makeRow("Group", M)
	U.Group = group
	U.GroupLabel = label(group, "Label", TEXT.Group, "Body", M.Label, {
		TextColor3 = SIGN.Text, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true, ZIndex = 6,
	})
	U.Chips = Util.Create("Frame", { Name = "Chips", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6, Parent = group })
	U.CashChip = tag(U.Chips, "CashChip", false, M)
	U.TokenChip = tag(U.Chips, "TokenChip", true, M)
	U.Sparkles = makeSparkles(group, M)
	U.Join = CloudUI.Button({ Name = "JoinButton", Text = TEXT.Button.Open, Style = "Green", Skin = "Sign", Size = UDim2.fromOffset(M.BtnW, M.BtnH),
		TextSize = M.BtnText, ZIndex = 6, Parent = group, Callback = function()
			TroveController._Join()
		end })
	U.Status = label(group, "Status", "", "Body", M.Tag, {
		TextColor3 = SIGN.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true, ZIndex = 6, Visible = false,
	})

	-- the Like row (no button)
	local like = makeRow("Like", M)
	U.Like = like
	U.LikeLabel = label(like, "Label", TEXT.Like, "Body", M.Label, {
		TextColor3 = SIGN.Text, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true, ZIndex = 6,
	})

	-- the footer and the hint that takes its place
	local footProps = {
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true, ZIndex = 4,
	}
	U.Footer = label(panel, "Footer", TEXT.Footer, "Body", M.Foot, footProps)
	U.Footer.TextColor3 = SIGN.TextMuted
	U.Hint = label(panel, "Hint", "", "Body", M.Foot, footProps)
	U.Hint.TextColor3 = SIGN.RedLip -- (kit-b U9-4) the notice in the kit's red ink
	U.Hint.Visible = false
end

-- the reward tags at (x, y) in the Group row, sized to their words; the sparkles round them
local function placeTags()
	local M = U.M
	if not (M and U.Chips) then
		return
	end
	local pad, gap = 8, 8
	local x = 0
	for _, chip in ipairs({ U.CashChip, U.TokenChip }) do
		local text = chip:FindFirstChild("Text")
		local coin = chip:FindFirstChild("Coin")
		text.TextSize = M.Tag
		-- (the words centred in a box with a little spare: a measure that runs short on the face's wide digits never
		-- spills them over the tag's edge)
		local tw = math.ceil(Theme.MeasureLabel(text).X * 1.15) + 2
		local cx = pad
		if coin then
			place(coin, pad, math.floor((M.TagH - 3 - M.Coin) / 2), M.Coin, M.Coin)
			cx = pad + M.Coin + 3
		end
		local w = cx + tw + pad - 2
		place(text, cx, 0, tw, M.TagH - 3)
		place(chip, x, 0, w, M.TagH)
		x = x + w + gap
	end
	-- the two sparkles on the stone just past the token tag (one up by its top corner, one lower and further out), where
	-- the gold reads; never over the words
	local right = U.Chips.Position.X.Offset + x - gap
	local top = U.Chips.Position.Y.Offset
	local px = M.Spark
	local a, b = U.Sparkles:FindFirstChild("SparkleA"), U.Sparkles:FindFirstChild("SparkleB")
	if a then
		a.Position = UDim2.fromOffset(math.floor(right + 2), math.floor(top - px * 0.6))
	end
	if b then
		b.Position = UDim2.fromOffset(math.floor(right + px * 0.9), math.floor(top + M.TagH - px * 0.9))
	end
end

-- the largest size from `size` down to 15 at which `l`'s text fits `w` px on one line
local function fitLine(l, size, w)
	for s = size, 15, -1 do
		l.TextSize = s
		if Theme.MeasureLabel(l).X <= w then
			return
		end
	end
end

-- every part's place for a panel W design px wide (the mode's metrics)
local function arrange(W)
	local M = U.M
	local F = K.FRAME
	local H = M.H
	place(U.Panel:FindFirstChild("Stone"), F, F, W - 2 * F, H - 2 * F)
	-- the header (SignKit.Header lays its plate out; the close sits on the plate, 10 px in from the frame's right edge as
	-- the Gifts window's, centred on the plate under the rim)
	place(U.Header, 0, 0, W, M.Header)
	if M.CloseBlock then
		-- (U9-4 look review 2) a phone: the 36 px block centred on the plate (4 px of plate over and under it, the icon
		-- square's height), its stroke 4 px inside the plate's right end; the 44 px touch box centred on it
		local b = M.CloseBlock
		local x, y = W - F - K.CLOSE_INSET - b, F + math.floor((M.Header - F - b) / 2)
		place(U.Close, x, y, b, b)
		local d = math.floor((M.Close - b) / 2)
		if U.CloseTap then
			place(U.CloseTap, x - d, y - d, M.Close, M.Close)
		end
	else
		place(U.Close, W - 10 - M.Close, F + math.floor((M.Header - F - M.Close) / 2), M.Close, M.Close)
	end
	if M.Sub > 0 then
		place(U.Subtitle, M.Pad + 2, M.SubY, W - 2 * M.Pad - 4, M.SubH)
	end
	-- the rows (row px; the lip under the face)
	local rowW = W - 2 * M.Pad
	local lipPx = SignKit.Sizes.BlockLip
	local inner = M.Pad == PC.Pad and 12 or 8
	-- (U9-4 look review 2) a phone's row icon at the art size on the bigger chip where both rows have room for it (4 px
	-- of face over and under the chip), else the glyph size on the small chip: both rows alike
	local chipPx, iconPx = M.Chip, M.ChipIcon
	if M.ChipBig and math.min(M.Row1H, M.Row2H) - lipPx >= M.ChipBig + 8 then
		chipPx, iconPx = M.ChipBig, M.ChipIconBig
	end
	U.ChipPx = chipPx
	local textX = inner + chipPx + (M.Pad == PC.Pad and 14 or 10)
	for _, r in ipairs({ { U.Group, M.Row1, M.Row1H, "Group" }, { U.Like, M.Row2, M.Row2H, "Like" } }) do
		local row, y, h = r[1], r[2], r[3]
		place(row, M.Pad, y, rowW, h)
		local chip = row:FindFirstChild("Chip")
		place(chip, inner, math.floor((h - lipPx - chipPx) / 2), chipPx, chipPx)
		local glyph = chip:FindFirstChild("Glyph")
		if glyph and glyph.Size.X.Offset ~= iconPx then
			glyph:Destroy()
			glyph = icon(chip, NeonKit.IconName(ASK[r[4]].Icon) or Config.Icons[ASK[r[4]].Icon], iconPx, SIGN.Text, 6)
			if glyph then
				glyph.Name = "Glyph"
			end
		end
		if glyph then
			place(glyph, math.floor((chipPx - iconPx) / 2), math.floor((chipPx - 3 - iconPx) / 2), iconPx, iconPx)
		end
	end
	local face1 = M.Row1H - lipPx
	local btnX = rowW - inner - M.BtnW
	place(U.Join, btnX, math.floor((face1 - M.BtnH) / 2), M.BtnW, M.BtnH)
	U.Join.TextSize = M.BtnText
	place(U.Status, btnX, math.floor((face1 - M.BtnH) / 2), M.BtnW, M.BtnH)
	U.Status.TextSize = M.Tag
	local labelW = btnX - (M.Pad == PC.Pad and 12 or 10) - textX
	local lineH = math.ceil(M.Label * 1.15)
	local labelH = M.Lines * lineH + 4
	local top = math.floor((face1 - labelH - 4 - M.TagH) / 2)
	place(U.GroupLabel, textX, top, labelW, labelH)
	U.GroupLabel.TextSize = M.Label
	if M.Lines == 1 then
		fitLine(U.GroupLabel, M.Label, labelW)
	end
	place(U.Chips, textX, top + labelH + 4, labelW, M.TagH)
	local face2 = M.Row2H - lipPx
	place(U.LikeLabel, textX, 2, rowW - textX - inner, face2 - 4)
	U.LikeLabel.TextSize = M.Label == PC.Label and M.Label or 15
	-- the footer and the hint
	for _, l in ipairs({ U.Footer, U.Hint }) do
		place(l, M.Pad, M.FootY, W - 2 * M.Pad, M.FootH)
		l.TextSize = M.Foot
	end
	placeTags()
end

-- the sparkles' turn: the lit one swaps every K.TWINKLE s while the panel is open and the reward waits
local function stopTwinkle()
	if S.Twinkle then
		S.Twinkle:Disconnect()
		S.Twinkle = nil
	end
end

local function startTwinkle()
	if S.Twinkle then
		return
	end
	local t = 0
	S.Twinkle = RunService.Heartbeat:Connect(function(dt)
		t = t + (tonumber(dt) or 0)
		if t < K.TWINKLE then
			return
		end
		t = t - K.TWINKLE
		S.Lit = not S.Lit
		local box = U.Sparkles
		local a, b = box and box:FindFirstChild("SparkleA"), box and box:FindFirstChild("SparkleB")
		if a and b then
			a.Visible, b.Visible = not S.Lit, S.Lit
		end
	end)
end

local function render()
	if not U.Panel then
		return
	end
	local state = S.State
	local a = groupAsk(state)
	local gs = a and a.State or "Loading"
	local reward = a and type(a.Reward) == "table" and a.Reward or {}
	U.GroupLabel.Text = (gs == "Soon") and TEXT.Soon or TEXT.Group
	local cashText = U.CashChip:FindFirstChild("Text")
	local tokenText = U.TokenChip:FindFirstChild("Text")
	if cashText then
		cashText.Text = "$" .. commas(reward.Cash or 2000)
	end
	if tokenText then
		tokenText.Text = commas(reward.Tokens or 200) -- (kit-b U9-4, the U7a rule) the token coin before the amount
	end
	placeTags()
	local buttonText = TEXT.Button[gs]
	U.Join.Visible = buttonText ~= nil
	if buttonText then
		U.Join.Text = buttonText
		U.Join:SetAttribute("Disabled", gs ~= "Open")
	end
	local status = TEXT.Status[gs]
	U.Status.Visible = buttonText == nil and status ~= nil
	U.Status.Text = status or ""
	if gs ~= "Open" and gs ~= "Checked" then
		S.Hint = nil
	end
	U.Hint.Text = S.Hint or ""
	U.Hint.Visible = S.Hint ~= nil
	U.Footer.Visible = S.Hint == nil
	-- the glint while the reward waits for the player
	local glint = gs == "Open"
	U.Sparkles.Visible = glint
	if glint and S.Open then
		startTwinkle()
	else
		stopTwinkle()
	end
end

-- Roblox's stick zone and jump button in the gui's area (HudController's robloxTouchRects), each { x0, y0, x1, y1 }
local function thumbZones()
	local vp = viewport()
	local area = U.Gui and U.Gui.AbsoluteSize
	if not area or area.X < 2 or area.Y < 2 then
		area = Vector2.new(vp.X, vp.Y - guiInset())
	end
	local small = math.min(vp.X, vp.Y) <= K.SMALL_PHONE
	local j = small and K.JUMP_SMALL or K.JUMP_LARGE
	local jumpBottom = small and 20 or j * 0.75
	local stickW = small and K.STICK_W_SMALL or K.STICK_W_LARGE
	local stickH = small and K.STICK_H_SMALL or K.STICK_H_LARGE
	if small and vp.Y > vp.X then
		stickH = K.STICK_H_PORTRAIT
	end
	return {
		{ 0, area.Y - stickH, stickW, area.Y },
		{ area.X - (1.5 * j + 10), area.Y - jumpBottom - j, area.X - (0.5 * j + 10), area.Y - jumpBottom },
	}
end

-- (U9-4 review) the landscape phone panel's height: PHONE.H, unless on a touch screen (where the game's DASH button
-- shows) that box would end on DASH; then as tall as reaches THUMB_GAP px over Roblox's jump button, which lands in the
-- DASH_GAP px between the two, so DASH and its stroke lie whole under the panel and the controls stay. A screen short
-- enough that PHONE.H already passes the jump button keeps PHONE.H (DASH lies whole under it; the controls go)
local function phoneHeight()
	if not UserInputService.TouchEnabled then
		return PHONE.H
	end
	local vp = viewport()
	local jumpTop = thumbZones()[2][2]
	local dash = math.min(vp.X, vp.Y) <= K.SMALL_PHONE and K.DASH_SMALL or K.DASH_LARGE
	if K.TOP_GAP + PHONE.H <= jumpTop - K.DASH_GAP - dash - K.DASH_STROKE then
		return PHONE.H -- DASH lies whole below the panel
	end
	return math.max(PHONE.H, math.floor(jumpTop - K.THUMB_GAP - K.TOP_GAP))
end

-- the phone layout's metrics for a panel h design px tall (h >= PHONE.H): a quarter of the spare height to each ask's
-- block, the rest in three even steps to the gaps under the header and each ask; the footer takes what is left
local function stretched(h)
	local spare = math.max(0, math.floor(h - PHONE.H))
	if spare == 0 then
		return PHONE
	end
	local M = {}
	for k, v in pairs(PHONE) do
		M[k] = v
	end
	local grow = math.floor(spare / 4)
	local step = math.floor((spare - 2 * grow) / 3)
	M.H = PHONE.H + spare
	M.Row1 = PHONE.Row1 + step
	M.Row1H = PHONE.Row1H + grow
	M.Row2 = PHONE.Row2 + 2 * step + grow
	M.Row2H = PHONE.Row2H + grow
	M.FootY = PHONE.FootY + 3 * step + 2 * grow
	M.FootH = PHONE.FootH + spare - 3 * step - 2 * grow
	return M
end

-- while open on a touch-only screen Roblox's touch controls go if the panel comes within THUMB_GAP px of them, and the
-- HUD's vitals card steps aside while the panel lies over it by more than a shared edge; both come back on Close
local function cover()
	local r = S.Open and S.Rect or nil
	local touchOff = false
	if r and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local g = K.THUMB_GAP
		for _, z in ipairs(thumbZones()) do
			if r.x < z[3] + g and r.x + r.w > z[1] - g and r.y < z[4] + g and r.y + r.h > z[2] - g then
				touchOff = true
			end
		end
	end
	if touchOff ~= S.TouchOff then
		S.TouchOff = touchOff
		local menu = controller("MenuController")
		if menu and type(menu.SetTouchHidden) == "function" then
			safe("touch", menu.SetTouchHidden, "Trove", touchOff)
		end
	end
	local vitalsOff = false
	local hud = r and controller("HudController") or nil
	if hud and type(hud.GetLayout) == "function" then
		local ok, layout = pcall(hud.GetLayout)
		local slot = ok and type(layout) == "table" and layout.VitalsSlot
		if slot then
			local w = math.min(r.x + r.w, slot.X + slot.W) - math.max(r.x, slot.X)
			local h = math.min(r.y + r.h, slot.Y + slot.H) - math.max(r.y, slot.Y)
			vitalsOff = w > 4 and h > 4
		end
	end
	if vitalsOff ~= S.VitalsOff then
		S.VitalsOff = vitalsOff
		hud = hud or controller("HudController")
		if hud and type(hud.SetVitalsHidden) == "function" then
			safe("vitals", hud.SetVitalsHidden, "Trove", vitalsOff)
		end
	end
end

local layout -- (forward: the HUD watcher re-lays the panel out)

-- (U9-4 look review) the HUD's top-right block (the currency strips and the gift's square under them) in gui-area px:
-- its bottom (NimbusHud TopRightBottom, 0 = none) and the strips' own bottom (over the gift's square, which hides while
-- this panel is open). A change re-lays an open panel out (watched once, when the HUD is first found)
local function hudTop()
	local p = localPlayer()
	local pg = p and p:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("NimbusHud")
	if not hud then
		return 0, 0
	end
	if not S.HudWatch then
		S.HudWatch = true
		hud:GetAttributeChangedSignal("TopRightBottom"):Connect(function()
			if S.Open then
				safe("layout", layout)
			end
		end)
	end
	local bottom = tonumber(hud:GetAttribute("TopRightBottom")) or 0
	local gift = tonumber(hud:GetAttribute("GiftSize")) or 0
	local strips = gift > 0 and (tonumber(hud:GetAttribute("GiftTop")) or bottom) or bottom
	return bottom, strips
end

-- the panel's box: the PC layout when the 1080p design fits SideRect and, docked under the HUD's strips, the screen, else
-- the phone layout at scale 1 (the bottom sheet on a portrait screen)
function layout()
	if not U.Gui then
		return
	end
	local vp = viewport()
	local W, H = vp.X, vp.Y
	local f = Theme.ScreenFactor(H)
	local rect = NeonKit.SideRect(K.PREF_W, K.PREF_H, K.MIN_W, K.MIN_H)
	local sheet = rect.mode == "Sheet"
	local inset = U.Gui.IgnoreGuiInset and 0 or guiInset()
	-- (U9-4 look review, the blocker) the PC panel docks UNDER the HUD's strips (and the gift's square: TopRightBottom),
	-- as the Stats window does: the old top dock, pushed 10 px down for the awning, left a sliver of the Cash strip over
	-- the frame's top and the strips' edges along its right. The $2,000 then lands in balances the player can see. Where
	-- that dock would run off the bottom (a short desktop window) the phone layout takes over (it covers the strips whole)
	local hudBottom, stripsBottom = hudTop()
	local dockY = hudBottom + K.TOP_GAP * f + K.ROOF_OVER * rect.scale
	local docks = dockY + K.PREF_H * rect.scale <= (H - inset) - K.MARGIN * f
	local phone = sheet or rect.designW < K.PREF_W - 0.5 or rect.designH < K.PREF_H - 0.5 or not docks
	local mode = sheet and "Portrait" or (phone and "Phone" or "PC")
	if S.Mode ~= mode or not U.Panel then
		build(mode)
	end
	local pw, ph = U.M.W, U.M.H
	if sheet then
		pw = math.min(PORTRAIT.W, W - 2 * K.MARGIN)
	elseif phone then
		ph = phoneHeight()
	end
	if U.Width ~= pw or U.Height ~= ph then
		U.Width, U.Height = pw, ph
		if mode == "Phone" then
			U.M = stretched(ph)
		end
		U.Panel.Size = UDim2.fromOffset(pw, ph)
		arrange(pw)
	end
	local M = U.M
	render()
	-- (the gui starts below Roblox's top bar: y is in the gui's area, so "inset + 8" on screen is 8 here)
	local x, y, scale
	if phone then
		scale = 1
		x = math.max(K.MARGIN, W - K.MARGIN - pw)
		if sheet then
			y = H - inset - K.MARGIN - M.H
		else
			y = K.TOP_GAP
		end
	else
		scale = rect.scale
		x = W - K.MARGIN * f - PC.W * scale
		y = dockY -- (the awning's top 8 px x factor under the HUD's block)
	end
	-- the awning: PC always; the portrait sheet where ROOF_CLEAR px of clear screen lie over its top (the strips' bottom,
	-- or the top of the gui's area)
	U.Roof.Visible = mode == "PC" or (sheet and y - K.ROOF_CLEAR >= stripsBottom)
	U.Scale.Scale = scale
	U.Panel.AnchorPoint = Vector2.new(0, 0)
	U.Panel.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	U.Panel:SetAttribute("TroveMode", mode)
	S.Rect = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), w = pw * scale, h = M.H * scale }
	cover()
end

----------------------------------------------------------------------
-- Join
----------------------------------------------------------------------
local function setHint(text)
	S.Hint = text
	render()
end

function TroveController._Join()
	local state = S.State
	if S.Joining or groupStateOf(state) ~= "Open" then
		return
	end
	local gid = tonumber(state.GroupId) or 0
	if gid <= 0 then
		return
	end
	S.Joining = true
	task.spawn(function()
		local ok, result = pcall(GroupService.PromptJoinAsync, GroupService, gid)
		S.Joining = false
		local status = Enum.GroupMembershipStatus
		if ok and (result == status.Joined or result == status.AlreadyMember) then
			setHint(nil)
			local okR, remote = pcall(Remotes.Get, "TroveRequest")
			if okR and remote then
				remote:FireServer("Joined")
			end
		elseif ok and result == status.JoinRequestPending then
			setHint(TEXT.Pending)
		else
			setHint(TEXT.NotJoined)
		end
	end)
end

----------------------------------------------------------------------
-- the claim: the lid and the coins
----------------------------------------------------------------------
local function backOut(t)
	local c1 = 1.70158
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

local function lidModel()
	for _, m in ipairs(CollectionService:GetTagged(Config.Tags.TroveLid)) do
		if m:IsA("Model") and m.PrimaryPart and m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

local function coinFolder()
	local f = workspace:FindFirstChild("TroveCoins")
	if not f then
		f = Instance.new("Folder")
		f.Name = "TroveCoins"
		f.Parent = workspace
	end
	return f
end

local function coin(i)
	local c = S.Pool[i]
	if not c then
		c = Instance.new("Part")
		c.Name = "TroveCoin"
		c.Size = Vector3.new(0.2, 0.8, 0.8) -- a square voxel coin (the world has no round primitives)
		c.Color = Theme.Neon and Theme.Neon.Gold or Color3.fromRGB(255, 204, 64)
		c.Material = Enum.Material.SmoothPlastic
		c.Anchored = true
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = false
		S.Pool[i] = c
	end
	return c
end

local function stopAnim()
	if S.Anim then
		S.Anim:Disconnect()
		S.Anim = nil
	end
	for _, c in ipairs(S.Pool) do
		c.Parent = nil
	end
end

local function playClaim()
	stopAnim()
	local lid = lidModel()
	local base
	if lid then
		base = S.LidBase[lid]
		if not base then
			base = lid.PrimaryPart.CFrame * CFrame.Angles(-math.rad(K.REST_DEG), 0, 0)
			S.LidBase[lid] = base
		end
	end
	local high = true
	local GQ = clientModule("GraphicsQuality")
	if GQ and type(GQ.Effective) == "function" then
		local ok, eff = pcall(GQ.Effective)
		high = not (ok and eff == "Low")
	end
	local flights = {}
	if high then
		local from = (lid and lid.PrimaryPart.Position or (base and base.Position)) or nil
		local char = localPlayer() and localPlayer().Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if from and root then
			local folder = coinFolder()
			local rng = Random.new()
			for i = 1, K.COINS do
				local c = coin(i)
				c.CFrame = CFrame.new(from)
				c.Parent = folder
				flights[i] = {
					Part = c,
					Delay = (i - 1) / (K.COINS - 1) * (K.COIN_TIME - K.COIN_FLIGHT),
					Side = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)),
					Lift = rng:NextNumber(3.5, 6),
					Spin = rng:NextNumber(6, 12),
				}
			end
			flights.From = from
			flights.Root = root
		end
	end
	local SoundFx = clientModule("SoundFx")
	if SoundFx and type(SoundFx.Play) == "function" then
		local id = type(SoundFx.Id) == "function" and SoundFx.Id("Sfx", "TroveOpen") or nil
		pcall(SoundFx.Play, id and "TroveOpen" or "Reward")
	end
	local t = 0
	S.Anim = RunService.Heartbeat:Connect(function(dt)
		t = t + (tonumber(dt) or 0)
		if lid and base and lid.Parent then
			local u = math.min(1, t / K.LID_TIME)
			local deg = K.REST_DEG + (K.OPEN_DEG - K.REST_DEG) * backOut(u)
			pcall(function()
				lid:PivotTo(base * CFrame.Angles(math.rad(deg), 0, 0))
			end)
		end
		local busy = false
		local target = flights.Root and flights.Root.Parent and flights.Root.Position or nil
		for i = 1, #flights do
			local fl = flights[i]
			if fl.Part.Parent then
				local u = (t - fl.Delay) / K.COIN_FLIGHT
				if u >= 1 or not target then
					fl.Part.Parent = nil
				else
					busy = true
					if u > 0 then
						local mid = math.sin(math.pi * u)
						local pos = flights.From:Lerp(target, u) + fl.Side * mid + Vector3.new(0, fl.Lift * mid, 0)
						fl.Part.CFrame = CFrame.new(pos) * CFrame.Angles(0, fl.Spin * t, math.rad(90))
					end
				end
			end
		end
		if not busy and t >= K.LID_TIME then
			stopAnim()
		end
	end)
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------
function TroveController.IsOpen()
	return S.Open == true
end

function TroveController.Close()
	S.Open = false
	S.Hint = nil
	stopTwinkle()
	if U.Panel then
		U.Panel.Visible = false
	end
	cover()
end

function TroveController.Open(state)
	if not S.Inited then
		TroveController.Init()
	end
	if inMatch() then
		return false
	end
	if type(state) == "table" then
		S.State = state
	end
	S.Open = true
	layout()
	render()
	U.Panel.Visible = true
	local menu = controller("MenuController")
	if menu and type(menu.WindowOpened) == "table" and type(menu.WindowOpened.Fire) == "function" then
		safe("WindowOpened", function()
			menu.WindowOpened:Fire("Trove")
		end)
	end
	return true
end

local function onState(state)
	if type(state) ~= "table" then
		return
	end
	local before = groupStateOf(S.State)
	S.State = state
	local now = groupStateOf(state)
	if now ~= "Open" and now ~= "Checked" then
		S.Hint = nil
	end
	render()
	if S.Open and before ~= nil and before ~= "Done" and now == "Done" then
		safe("claim", playClaim)
	end
end

local function connectOthers()
	local function hook(name, signalName, filter)
		local mod = controller(name)
		local signal = mod and mod[signalName]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function(id)
				if filter and id == "Trove" then
					return
				end
				if S.Open then
					TroveController.Close()
				end
			end)
		end
	end
	hook("MenuController", "WindowOpened", true)
	hook("IndexController", "Opened")
	hook("FusionController", "Opened")
	hook("CareController", "Opened")
	hook("ArenaController", "Opened")
	hook("DungeonController", "Opened")
	hook("ObbyController", "Opened")
end

function TroveController.Init()
	if S.Inited then
		return
	end
	S.Inited = true
	U.Gui = CloudUI.NewScreenGui("NimbusTrove", K.DISPLAY_ORDER)
	layout()
	local function bindCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				safe("layout", layout)
			end)
		end
	end
	bindCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera()
		safe("layout", layout)
	end)
	local p = localPlayer()
	if p then
		p:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if inMatch() then
				TroveController.Close()
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and S.Open then
			TroveController.Close()
		end
	end)
	task.spawn(function()
		local okOpen, openRemote = pcall(Remotes.Get, "OpenPanel")
		if okOpen and openRemote then
			openRemote.OnClientEvent:Connect(function(panelId)
				if type(panelId) == "string" and panelId:lower() == "trove" then
					safe("open", TroveController.Open)
				end
			end)
		end
	end)
	task.spawn(function()
		local okState, stateRemote = pcall(Remotes.Get, "TroveState")
		if okState and stateRemote then
			stateRemote.OnClientEvent:Connect(function(state)
				safe("state", onState, state)
			end)
		end
	end)
	task.defer(function()
		safe("connect", connectOthers)
	end)
end

return TroveController
