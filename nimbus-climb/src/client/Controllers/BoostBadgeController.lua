-- BoostBadgeController (client, store 2026-11-04; spec 8 "Boost chips"): the small chips under the HUD's currency strips that
-- say which paid boost is running. No HudController edit: it reads the HUD's published attributes.
--
--   BoostBadgeController.Init()
--   BoostBadgeController.Chips() -> { Cash = bool, Xp = text | nil }   what the chips show now
--
-- Data: the replicated Player attributes OwnedPasses (csv of pass keys, e.g. "VIP,Cash2x") and XpBoostEnds (unix seconds
-- the XP potion bank ends; 0 = none). The server decides both; this only shows them.
-- Screen: ScreenGui "NimbusBoosts" (DisplayOrder 10 like the HUD, IgnoreGuiInset = false: gui px), Frame "BoostChips"
--   right-aligned at the strips' right edge (the HUD's side margin: 12 px, 20 on touch), y = NimbusHud.TopRightBottom + 4,
--   holding TextLabels "Chip_Cash" ("x2 Cash", while OwnedPasses has Cash2x) and "Chip_Xp" ("x2 XP · 58m", while
--   XpBoostEnds > now, the time left refreshed every second; "x2 XP" while OwnedPasses has PetXp2x: the pass and a potion
--   never stack, the pass wins). 46x24 at 1080p (text 18), 34x18 text 15 on a phone (the smaller screen side <= 500); a chip
--   grows with its text. Hidden with the strips (InMatch / InBattle, or no top-right strips). kit-b U8 review: each chip is
--   a kit B tag (CloudUI.SignBlock: Cash the cash green, XP the violet, a wood edge, square; no neon border).
-- Side hints (MenuController.Hint): "x2 Pet XP started!" only for a potion that starts during this view: XpBoostEnds rises
-- from a value that was no running potion (0, or an old end already in the past: the server leaves the last end on the
-- attribute) to an end whose time left is one whole potion (a Config.Store.Items Boost.XpPotion length, within
-- START_SLACK s); never for the first value seen (the attribute absent until then), an end in the past, an extension of a
-- running potion, or a potion bought earlier that arrives late (a provisional recovery, a slow profile load: part of it is
-- already used). "x2 Pet XP ends in 5 min" once per potion when its time left crosses Config.Store.Potion.WarnSeconds
-- downward. Neither while OwnedPasses has PetXp2x: the pass wins (Chips() shows its untimed "x2 XP"), so a potion on top
-- of it (a Starter pack's) neither starts nor ends anything (re-review 1).
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))

local BoostBadgeController = {}

local K = {
	DISPLAY_ORDER = 10,
	GAP = 4, -- under the strips
	CHIP_GAP = 6, -- between two chips
	EDGE = 12, -- the HUD's side margin (HudController K.EDGE) ...
	TOUCH_EDGE = 20, -- ... and on touch devices (K.TOUCH_EDGE)
	SMALL = 500, -- the smaller screen side at most this = a phone
	PC = { W = 46, H = 24, Text = 18, Pad = 8 },
	PHONE = { W = 34, H = 18, Text = 15, Pad = 5 },
	TICK = 1,
	START_SLACK = 15, -- seconds: a fresh potion's time left is its full length within this (os.time vs the server clock)
	-- (kit-b U8 review) the chips' kit B looks: Cash in the HUD's cash green (its strip's coin square) with the dark green
	-- ink, XP in the kit's violet with the brown ink (5.2:1); a 2 px wood edge suits a 18-24 px chip
	CASH_LOOK = { Face = Theme.Sign.Grass, Lip = Theme.Sign.GrassLip, Edge = Theme.Sign.Wood, Text = Theme.Sign.OnGrass },
	XP_LOOK = { Face = Theme.Sign.Violet, Lip = Theme.Sign.VioletLip, Edge = Theme.Sign.Wood, Text = Theme.Sign.Text },
	EDGE_PX = 2,
}
BoostBadgeController.K = K

local DOT = "\194\183"

local LocalPlayer = nil
local initialized = false
local U = {}
local S = { Ends = 0, Seen = false, WarnedFor = nil, Started = false }
local warned = {}

local function warnOnce(key, err)
	if not warned[key] then
		warned[key] = true
		warn("[BoostBadgeController] " .. key .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

local function now()
	return workspace:GetServerTimeNow()
end

local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and vp.X >= 2 and vp.Y >= 2 then
		return vp
	end
	return Vector2.new(1920, 1080)
end

local function hasPass(key)
	local csv = LocalPlayer and LocalPlayer:GetAttribute(Config.Attr.OwnedPasses or "OwnedPasses")
	if type(csv) ~= "string" then
		return false
	end
	for entry in csv:gmatch("[^,]+") do
		if entry:gsub("^%s+", ""):gsub("%s+$", "") == key then
			return true
		end
	end
	return false
end

local function boostAttr()
	return LocalPlayer and LocalPlayer:GetAttribute(Config.Attr.XpBoostEnds or "XpBoostEnds")
end

local function boostEnds()
	return tonumber(boostAttr()) or 0
end

-- the lengths of one XP potion (seconds): every Boost.XpPotion grant of Config.Store.Items
local function potionLengths()
	local out = {}
	local items = Config.Store and Config.Store.Items
	for _, item in ipairs(type(items) == "table" and items or {}) do
		local boost = type(item) == "table" and type(item.Grants) == "table" and item.Grants.Boost
		local secs = type(boost) == "table" and tonumber(boost.XpPotion)
		if secs and secs > 0 then
			out[#out + 1] = secs
		end
	end
	return out
end

-- a potion that has just started: its time left is one whole potion length
local function freshPotion(left)
	for _, secs in ipairs(potionLengths()) do
		if math.abs(left - secs) <= K.START_SLACK then
			return true
		end
	end
	return false
end

-- "58m" / "1h 5m"
local function leftText(seconds)
	local s = math.max(0, seconds)
	if s >= 3600 then
		return math.floor(s / 3600) .. "h " .. math.floor((s % 3600) / 60) .. "m"
	end
	return math.max(1, math.ceil(s / 60)) .. "m"
end

local function hint(text)
	local inst = script.Parent:FindFirstChild("MenuController")
	local ok, menu = pcall(function()
		return inst and require(inst)
	end)
	if ok and type(menu) == "table" and type(menu.Hint) == "function" then
		pcall(menu.Hint, text, "good")
	end
end

local function hiddenByPlay()
	local p = LocalPlayer
	return p == nil or p:GetAttribute(Config.Attr.InMatch) == true or p:GetAttribute(Config.Attr.InBattle or "InBattle") ~= nil
end

local H = {}

-- (kit-b U8 review) a chip is a kit B tag: a flat block in its colour in a wood edge (UIStroke "SignEdge"), square, its
-- text in the ink that reads on it; no lip (as the strips' coin squares: at 18-24 px a lip ran under the letters like an
-- underline)
function H.chip(name, look)
	local l = Theme.Label("", "Heading", { Size = K.PC.Text })
	l.Name = name
	l.AutomaticSize = Enum.AutomaticSize.X
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.Visible = false
	local pad = Instance.new("UIPadding")
	pad.Name = "Pad"
	pad.Parent = l
	CloudUI.SignBlock(l, look, { EdgePx = K.EDGE_PX, LipPx = 0, Pad = false })
	l.Parent = U.Holder
	return l
end

function BoostBadgeController.Chips()
	local out = { Cash = hasPass("Cash2x"), Xp = nil }
	local left = boostEnds() - now()
	if hasPass("PetXp2x") then
		out.Xp = "x2 XP"
	elseif left > 0 then
		out.Xp = "x2 XP " .. DOT .. " " .. leftText(left)
	end
	return out
end

function H.layout()
	if not U.Holder then
		return
	end
	local vp = viewport()
	local small = math.min(vp.X, vp.Y) <= K.SMALL
	local M = small and K.PHONE or K.PC
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("NimbusHud")
	local bottom = tonumber(hud and hud:GetAttribute("TopRightBottom")) or 0
	local chips = BoostBadgeController.Chips()
	local any = chips.Cash or chips.Xp ~= nil
	U.Holder.Visible = any and bottom > 0 and not hiddenByPlay()
	U.Holder.AnchorPoint = Vector2.new(1, 0)
	U.Holder.Position = UDim2.new(1, -(touch and K.TOUCH_EDGE or K.EDGE), 0, math.floor(bottom + K.GAP + 0.5))
	U.Holder.Size = UDim2.fromOffset(0, M.H)
	U.Layout.Padding = UDim.new(0, K.CHIP_GAP)
	for _, chip in ipairs({ U.Cash, U.Xp }) do
		chip.Size = UDim2.fromOffset(M.W, M.H)
		chip.TextSize = M.Text
		chip.Pad.PaddingLeft = UDim.new(0, M.Pad)
		chip.Pad.PaddingRight = UDim.new(0, M.Pad)
	end
	U.Cash.Text = "x2 Cash"
	U.Cash.Visible = chips.Cash
	U.Xp.Text = chips.Xp or ""
	U.Xp.Visible = chips.Xp ~= nil
end

-- the potion hints: started (see the header) and the WarnSeconds crossing (once per potion end)
function H.watchPotion()
	local ends = boostEnds()
	local was = S.Ends
	local seen = S.Seen
	S.Ends = ends
	S.Seen = boostAttr() ~= nil -- absent again: the next value is a first value (a baseline)
	local t = now()
	if S.Started and seen and was <= t and ends > t and freshPotion(ends - t) and not hasPass("PetXp2x") then
		hint("x2 Pet XP started!")
	end
	if ends ~= was then
		S.WarnedFor = nil
	end
end

function H.tick()
	local ends = boostEnds()
	local warnAt = (Config.Store and Config.Store.Potion and Config.Store.Potion.WarnSeconds) or 300
	local left = ends - now()
	if ends > 0 and left > 0 and left <= warnAt and S.WarnedFor ~= ends then
		if S.LastLeft and S.LastLeft > warnAt then
			S.WarnedFor = ends
			if not hasPass("PetXp2x") then -- the pass keeps x2: nothing ends
				hint("x2 Pet XP ends in " .. math.floor(warnAt / 60 + 0.5) .. " min")
			end
		end
	end
	S.LastLeft = left
	H.layout()
end

function BoostBadgeController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	local gui = CloudUI.NewScreenGui("NimbusBoosts", K.DISPLAY_ORDER)
	gui.IgnoreGuiInset = false
	U.Gui = gui
	local holder = Instance.new("Frame")
	holder.Name = "BoostChips"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.Visible = false
	holder.Parent = gui
	U.Holder = holder
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	U.Layout = layout
	U.Cash = H.chip("Chip_Cash", K.CASH_LOOK)
	U.Cash.LayoutOrder = 2
	U.Xp = H.chip("Chip_Xp", K.XP_LOOK)
	U.Xp.LayoutOrder = 1
	S.Ends = boostEnds()
	S.Seen = boostAttr() ~= nil
	S.LastLeft = S.Ends - now()
	S.Started = true
	local attr = Config.Attr
	for _, name in ipairs({ attr.OwnedPasses or "OwnedPasses", attr.InMatch, attr.InBattle or "InBattle" }) do
		LocalPlayer:GetAttributeChangedSignal(name):Connect(function()
			safe("layout", H.layout)
		end)
	end
	LocalPlayer:GetAttributeChangedSignal(attr.XpBoostEnds or "XpBoostEnds"):Connect(function()
		safe("potion", H.watchPotion)
		safe("layout", H.layout)
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		safe("layout", H.layout)
	end)
	safe("layout", H.layout)
	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui")
		local hud = pg:WaitForChild("NimbusHud", 30)
		if hud then
			hud:GetAttributeChangedSignal("TopRightBottom"):Connect(function()
				safe("layout", H.layout)
			end)
			safe("layout", H.layout)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(K.TICK)
			safe("tick", H.tick)
		end
	end)
end

return BoostBadgeController
