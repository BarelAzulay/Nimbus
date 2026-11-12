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
-- docked right so the chest stays in view, touch
-- controls stay. Box: NeonKit.SideRect(520, 380, 352, 236) answers whether the 1080p design fits; when it does the PC
-- layout (520 x 380 design px at the rect's scale, 12 px x factor from the right, top = inset + 8 x factor), otherwise
-- the phone layout (352 x 236 at scale 1, 12 px from the right, top = inset + 8; a portrait screen puts it at the
-- bottom right so the character stays clear).
--   phone: title bar 44 ("SKY TROVE", Title 22, X 36x36); subtitle Body 16 "Help Nimbus grow and the Trove pays you!";
--          two rows 66 (orb 40, label Body 16, reward chips 15, button 100x44) and the footer 15
--   PC:    title bar 60 (Title 32, X 44), subtitle 20, rows 88 (orb 56, label 20, chips 18, button 150x52), footer 18
-- The Group row: "Join the Nimbus Climb group" + "$2,000" / "200 Tokens"; its button reads JOIN (Open), DONE (disabled,
-- Done), PREVIEW (disabled, Preview: GroupId 0 in the Studio preview); no button for Checked / Unavailable / Loading /
-- Soon (Soon's label reads "Coming soon"). The Like row has no button. The footer: "Community links are on our game
-- page. Prizes go straight to you. Once per player." JOIN -> pcall(GroupService.PromptJoinAsync, GroupId): Joined /
-- AlreadyMember -> TroveRequest("Joined"); JoinRequestPending -> the hint "Your request is waiting for the group. Come
-- back later!"; None / an error -> "Not joined yet. Join from the game page, then come back in a new server." (the hint
-- takes the footer's place).
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
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))

local TroveController = {}

local K = {
	DISPLAY_ORDER = 18,
	PREF_W = 520, PREF_H = 380, MIN_W = 352, MIN_H = 236,
	MARGIN = 12, TOP_GAP = 8,
	REST_DEG = 18, OPEN_DEG = 70, LID_TIME = 0.35,
	COINS = 18, COIN_TIME = 0.8, COIN_FLIGHT = 0.55,
}
local PHONE = { W = 352, H = 236, Pad = 10, Bar = 44, Title = 22, Close = 36, Sub = 16, SubY = 44, SubH = 20,
	Row = 66, Row1 = 64, Row2 = 132, Orb = 40, Label = 16, Chip = 15, BtnW = 100, BtnH = 44, BtnText = 18, Foot = 15, FootH = 34 }
local PC = { W = 520, H = 380, Pad = 16, Bar = 60, Title = 32, Close = 44, Sub = 20, SubY = 60, SubH = 28,
	Row = 88, Row1 = 92, Row2 = 188, Orb = 56, Label = 20, Chip = 18, BtnW = 150, BtnH = 52, BtnText = 22, Foot = 18, FootH = 48 }
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
	Button = { Open = "JOIN", Done = "DONE", Preview = "PREVIEW" },
}
local GLYPH = { Group = "\240\159\145\165", Like = "\240\159\145\141" } -- busts in silhouette, thumbs up

local S = {
	Inited = false,
	Open = false,
	State = nil, -- the last TroveState
	Mode = nil, -- "Phone" | "PC" (the built layout)
	Hint = nil,
	Joining = false,
	LidBase = setmetatable({}, { __mode = "k" }), -- [lid model] = the hinge CFrame at 0 degrees
	Pool = {}, -- the coin parts
	Anim = nil, -- the running claim animation (a Heartbeat connection)
}
local U = {} -- Gui, Panel (card), Scale, Rows, ...
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
	local l = Theme.Label(text, role, { Size = size, Stroke = 1, Outline = 2, Props = props })
	l.Name = name
	l.Parent = parent
	return l
end

----------------------------------------------------------------------
-- the panel
----------------------------------------------------------------------
local function chip(parent, name, text, M, x)
	local h = M.Chip + 6
	local f = Util.Create("Frame", {
		Name = name,
		BackgroundColor3 = Theme.Neon and Theme.Neon.Green or Color3.fromRGB(72, 224, 120),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = parent,
	})
	Util.Create("UICorner", { CornerRadius = UDim.new(0, math.floor(h / 2)), Parent = f })
	Util.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = f })
	label(f, "Text", text, "Body", M.Chip, {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	return f
end

local function makeRow(body, id, y, M, glyph, color)
	local row = Util.Create("Frame", {
		Name = "Row_" .. id,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(M.Pad, y),
		Size = UDim2.new(1, -2 * M.Pad, 0, M.Row),
		Parent = body,
	})
	Util.Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = row })
	local orbHolder = Util.Create("Frame", {
		Name = "OrbHolder",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 6, 0.5, -M.Orb / 2),
		Size = UDim2.fromOffset(M.Orb, M.Orb),
		Parent = row,
	})
	local orb = NeonKit.Orb(orbHolder, color, M.Orb)
	NeonKit.Icon(orb, glyph, math.floor(M.Orb * 0.5))
	return row
end

local function build(mode)
	local M = (mode == "PC") and PC or PHONE
	if U.Card then
		U.Card.Root:Destroy()
	end
	U.M = M
	S.Mode = mode
	local card = NeonKit.Card({ Name = "TrovePanel", Color = "Trove", Size = UDim2.fromOffset(M.W, M.H), Floor = false, Parent = U.Gui })
	card.Root.Visible = S.Open
	card.Root.Active = true
	U.Card = card
	U.Scale = Util.Create("UIScale", { Name = "TroveScale", Scale = 1, Parent = card.Root })
	local body = card.Body
	label(body, "TitleText", TEXT.Title, "Title", M.Title, {
		Position = UDim2.fromOffset(M.Pad + 2, 0),
		Size = UDim2.new(1, -(2 * M.Pad + M.Close + 8), 0, M.Bar),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	local close = NeonKit.Button({
		Name = "Close",
		Text = "",
		Color = "Red",
		Variant = "Outline",
		Size = UDim2.fromOffset(M.Close, M.Close),
		Position = UDim2.new(1, -(M.Pad - 2) - M.Close, 0, math.floor((M.Bar - M.Close) / 2)),
		Parent = body,
		Callback = function()
			TroveController.Close()
		end,
	})
	NeonKit.CloseMark(close) -- slop audit 2026-11-12: a drawn X (the U+2715 glyph showed a missing-glyph box)
	label(body, "Subtitle", TEXT.Sub, "Body", M.Sub, {
		Position = UDim2.fromOffset(M.Pad + 2, M.SubY),
		Size = UDim2.new(1, -2 * M.Pad, 0, M.SubH),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- the Group row
	local textX = 6 + M.Orb + 8
	local group = makeRow(body, "Group", M.Row1, M, GLYPH.Group, "Green")
	local labelH = M.Label * 2 + 4
	U.GroupLabel = label(group, "Label", TEXT.Group, "Body", M.Label, {
		Position = UDim2.fromOffset(textX, 3),
		Size = UDim2.new(1, -(textX + M.BtnW + 14), 0, labelH),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
	})
	local chips = Util.Create("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textX, 3 + labelH + 1),
		Size = UDim2.new(1, -(textX + M.BtnW + 14), 0, M.Chip + 6),
		Parent = group,
	})
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	U.CashChip = chip(chips, "CashChip", "$2,000", M, 0)
	U.TokenChip = chip(chips, "TokenChip", "200 Tokens", M, 0)
	U.TokenChip.LayoutOrder = 2
	U.Join = NeonKit.Button({
		Name = "JoinButton",
		Text = TEXT.Button.Open,
		Color = "Green",
		Size = UDim2.fromOffset(M.BtnW, M.BtnH),
		TextSize = M.BtnText,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Parent = group,
		Callback = function()
			TroveController._Join()
		end,
	})
	U.Status = label(group, "Status", "", "Body", M.Chip, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(M.BtnW, M.BtnH),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		Visible = false,
	})

	-- the Like row (no button)
	local like = makeRow(body, "Like", M.Row2, M, GLYPH.Like, "Gold")
	label(like, "Label", TEXT.Like, "Body", M.Label, {
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -(textX + 8), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
	})

	-- the footer and the hint that takes its place
	local footProps = {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, M.Pad, 1, -3),
		Size = UDim2.new(1, -2 * M.Pad, 0, M.FootH),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
	}
	U.Footer = label(body, "Footer", TEXT.Footer, "Body", M.Foot, footProps)
	U.Footer.TextColor3 = Theme.Colors.TextDim or U.Footer.TextColor3
	U.Hint = label(body, "Hint", "", "Body", M.Foot, footProps)
	U.Hint.TextColor3 = Theme.Neon and Theme.Neon.Gold or U.Hint.TextColor3
	U.Hint.Visible = false
end

local function render()
	if not U.Card then
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
		tokenText.Text = commas(reward.Tokens or 200) .. " Tokens"
	end
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
end

-- the window box: the PC layout when the 1080p design fits SideRect, else the phone layout at scale 1
local function layout()
	if not U.Gui then
		return
	end
	local vp = viewport()
	local W, H = vp.X, vp.Y
	local f = Theme.ScreenFactor(H)
	local rect = NeonKit.SideRect(K.PREF_W, K.PREF_H, K.MIN_W, K.MIN_H)
	local phone = rect.mode == "Sheet" or rect.designW < K.PREF_W - 0.5 or rect.designH < K.PREF_H - 0.5
	local mode = phone and "Phone" or "PC"
	if S.Mode ~= mode or not U.Card then
		build(mode)
		render()
	end
	-- (the gui starts below Roblox's top bar: y is in the gui's area, so "inset + 8" on screen is 8 here)
	local inset = U.Gui.IgnoreGuiInset and 0 or guiInset()
	local x, y, scale
	if phone then
		scale = 1
		x = math.max(K.MARGIN, W - K.MARGIN - PHONE.W)
		if rect.mode == "Sheet" then
			y = H - inset - K.MARGIN - PHONE.H
		else
			y = K.TOP_GAP
		end
	else
		scale = rect.scale
		x = W - K.MARGIN * f - PC.W * scale
		y = K.TOP_GAP * f
	end
	U.Scale.Scale = scale
	U.Card.Root.AnchorPoint = Vector2.new(0, 0)
	U.Card.Root.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	U.Card.Root:SetAttribute("TroveMode", mode)
end

----------------------------------------------------------------------
-- JOIN
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
	if U.Card then
		U.Card.Root.Visible = false
	end
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
	U.Card.Root.Visible = true
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
