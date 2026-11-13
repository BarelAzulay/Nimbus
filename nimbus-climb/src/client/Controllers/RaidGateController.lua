-- RaidGateController (client, boss raids; docs/superpowers/specs/2026-11-01-raid-boss-design.md): what a player sees of the raid boss
-- outside a fight. Nothing here decides anything: walking through the gate is the server's poll (BattleService), a dare is a
-- BattleRequest the server checks again.
--
--   RaidGateController.Init()
--   RaidGateController.OpenDare(prompt|nil) -> bool   the dare panel (the gate pillar's DarePrompt, OpenPanel = "Dare": ArenaController routes it)
--   RaidGateController.Close()
--   RaidGateController.IsOpen() -> bool
--   RaidGateController.Refresh()                      the idle boss and the tag, now
--   RaidGateController.Stop()                         tests: everything built here goes, the connections drop, Init starts it again
--   RaidGateController.Tier() -> tier                 my fight tier (BattleCatalog.RaidTiers row): the highest pet on the active team
--   RaidGateController.RewardLine() -> text           "Rewards ready" | "Rewards again in M:SS" (the saved Battle.RaidRewardAt)
--   RaidGateController.Opened / Closed (Util.Signal)
--
-- What the player sees
--   * The idle boss: workspace.ClientRaidGate.Boss_<id>, built here for this client alone at the centre of the colosseum floor (the
--     NC_BattleZone part with Mode "Raid" and ZoneId "Arena"), facing the lobby, in the colours and size of MY tier, while the
--     player is within K.RANGE studs and no fight has the floor (ArenaState.Raid: Active false, FloorHiddenIn 0). A floor fight's
--     "Start" takes it away at once, and it comes back only when BattleController has stopped drawing that fight (the end's linger: the
--     server says Active false at the end). Its head follows the player (at most 30 Hz, turning at K.TURN_SPEED rad/s). Graphics Low:
--     the Low model, no aura, it stands still.
--   * The gate tag: one pixel-sized BillboardGui RaidGateTag on the gate's crest (tag NC_RaidGateCrest, else the RaidGate part):
--     "<Boss> - your tier: <Tier> (L<n> boss)", the reward line, "<Tier> boss back in N s" while my tier's fight is closed, else "Walk
--     through to fight". Refreshed every second from the last ArenaState; hidden while the player fights.
--   * The dare panel: a NeonKit side panel (docked right on landscape screens, a bottom sheet on portrait phones) with one row per
--     tier above mine, "<Tier> - boss L<n>, hits x<h>, rewards x<r>" and a Dare button. One side panel at a time; Esc / gamepad B / the
--     red X / walking away from the pillar / my fight's Start close it. Dare with an empty team leads to the Pets window (TeamFaces.Ensure).
-- Remotes: ArenaState (in), BattleState ("Start" in); the dare goes out through ArenaController.Request. Plain Lua 5.1-compatible syntax only.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local UI = Client:WaitForChild("UI")
local CloudUI = require(UI:WaitForChild("CloudUI"))
local NeonKit = require(UI:WaitForChild("NeonKit"))
local TeamFaces = require(UI:WaitForChild("TeamFaces"))
local State = require(Client:WaitForChild("State"))

local RaidGateController = {}
RaidGateController.Opened = Util.Signal()
RaidGateController.Closed = Util.Signal()

local K = {
	DISPLAY_ORDER = 23,
	PREF_W = 560, -- design px of the dare panel
	PREF_H = 500,
	INTRO_H = 30,
	ROW_H = 72,
	GAP = 8,
	BUTTON_W = 120,
	BUTTON_H = 56, -- >= 44 px under the 0.8 touch scale
	TICK = 0.25, -- seconds between two looks at the state (the idle boss, the walk-away)
	TAG_EVERY = 1, -- seconds between two tag refreshes
	ANIM_GAP = 1 / 30, -- the idle boss moves at most at 30 Hz
	RANGE = 400, -- studs from the floor's centre within which the idle boss stands
	TURN_SPEED = 2, -- rad/s: how fast its head comes round
	YAW_MAX = 1, -- rad: BossBuilder's own limit
	LOOK_AHEAD = 100, -- studs: the point Animate's LookAt gets
	WALK_AWAY = 24, -- studs from the pillar that close a panel opened there (the server takes a dare within 20 of the gate)
	TAG_W = 380, -- px: fits a portrait phone; a long first line wraps
	TAG_H = 122,
	TAG_DISTANCE = 120,
	TAG_OFFSET = 5,
	BACK_ACTION = "NimbusRaidDareBack",
}

local Colors = Theme.Colors
local WHITE = Colors.White
local C = {
	Accent = Color3.fromRGB(214, 92, 96), -- the Arena panels' crimson
	Gold = (Theme.Neon and Theme.Neon.Gold) or Color3.fromRGB(255, 196, 64),
	Muted = Color3.fromRGB(176, 184, 214),
	Row = Color3.fromRGB(30, 36, 78),
	Plate = Color3.fromRGB(28, 36, 78),
}

local LocalPlayer = nil
local initialized = false
local U = {} -- gui references
local S = {
	Open = false,
	Token = 0,
	At = nil, -- the pillar when the panel was opened there
	BackBound = false,
	Arena = nil, -- last ArenaState
	ArenaAt = 0, -- os.clock() when it arrived
	Tier = nil, -- my tier (cached until the next ProfileSync)
	Model = nil, -- the idle boss
	ModelKey = nil, -- "<boss>|<tier>|<detail>": another key builds it again (the size follows the tier)
	ModelCF = nil,
	Yaw = 0, -- its head's yaw now
	AnimAt = 0,
	TickAt = 0,
	TagAt = 0,
	Conns = {},
	Failed = {}, -- [key] = true: a boss that would not build is not tried again every tick
	Warned = {},
}
local Mods = { Catalog = nil, Boss = nil, Gfx = nil } -- lazy modules (false = unavailable)
local H = {}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
function H.safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not S.Warned[key] then
		S.Warned[key] = true
		warn("[RaidGateController] " .. key .. ": " .. tostring(err))
	end
	return ok
end

function H.lazy(key, parent, name)
	if Mods[key] == nil then
		local module = parent:FindFirstChild(name)
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		Mods[key] = (ok and type(result) == "table") and result or false
	end
	return Mods[key] or nil
end

function H.catalog()
	return H.lazy("Catalog", Shared, "BattleCatalog")
end

function H.bossBuilder()
	return H.lazy("Boss", Shared, "BossBuilder")
end

function H.low()
	local gq = H.lazy("Gfx", Client, "GraphicsQuality")
	if gq and type(gq.Effective) == "function" then
		local ok, mode = pcall(gq.Effective)
		return ok and mode == "Low"
	end
	return false
end

function H.controller(name)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	return (ok and type(mod) == "table") and mod or nil
end

function H.clock(seconds)
	local s = math.max(0, math.ceil(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function H.text(parent, name, text, role, size, color, props)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = tostring(text or "")
	-- kit-b U6: the window is a plate, so the text reads by contrast (no outline)
	Theme.Style(label, role or "Body", { Size = size, Color = color or WHITE })
	label.TextYAlignment = Enum.TextYAlignment.Center
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = parent
	return label
end

function H.rootPosition()
	local char = LocalPlayer and LocalPlayer.Character
	local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))
	return root and root.Position or nil
end

function H.fighting()
	local id = LocalPlayer and LocalPlayer:GetAttribute(Config.Attr.InBattle)
	return type(id) == "string" and id ~= ""
end

-- ArenaState.Raid, as far as it can be read (the server's GetRaidStatus + the rotation)
function H.raid()
	local raid = type(S.Arena) == "table" and S.Arena.Raid or nil
	if type(raid) == "table" and type(raid.BossId) == "string" then
		return raid
	end
	return nil
end

-- seconds left of a countdown of the last ArenaState (they tick here between two states)
function H.left(value)
	local n = tonumber(value)
	if not n then
		return 0
	end
	return math.max(0, n - (os.clock() - S.ArenaAt))
end

function H.bossName(raid)
	local BC = H.catalog()
	local boss = BC and type(BC.Bosses) == "table" and BC.Bosses[raid.BossId]
	return tostring(raid.Name or (type(boss) == "table" and boss.Name) or "The boss")
end

----------------------------------------------------------------------
-- my tier, my reward clock
----------------------------------------------------------------------
function RaidGateController.Tier()
	if not S.Tier then
		local BC = H.catalog()
		if not BC or type(BC.RaidTierOfTeam) ~= "function" then
			return nil
		end
		S.Tier = BC.RaidTierOfTeam(TeamFaces.Entries())
	end
	return S.Tier
end

function RaidGateController.RewardLine()
	local BC = H.catalog()
	local ok, battle = pcall(State.Battle)
	local stamp = ok and type(battle) == "table" and tonumber(battle.RaidRewardAt) or 0
	local minutes = BC and type(BC.Raid) == "table" and tonumber(BC.Raid.RewardMinutes) or 20
	local left = stamp + minutes * 60 - os.time()
	if stamp <= 0 or left <= 0 then
		return "Rewards ready"
	end
	return "Rewards again in " .. H.clock(left)
end

----------------------------------------------------------------------
-- the world
----------------------------------------------------------------------
function H.floorZone()
	if U.Floor and U.Floor:IsDescendantOf(Workspace) then
		return U.Floor
	end
	U.Floor = nil
	for _, part in ipairs(CollectionService:GetTagged("NC_BattleZone")) do
		if part:GetAttribute("Mode") == "Raid" and part:GetAttribute("ZoneId") == "Arena" then
			U.Floor = part
			break
		end
	end
	return U.Floor
end

function H.tagAdornee()
	for _, tag in ipairs({ "NC_RaidGateCrest", "NC_RaidGate" }) do
		local part = CollectionService:GetTagged(tag)[1]
		if part then
			return part
		end
	end
	return nil
end

function H.folder()
	if not (U.Folder and U.Folder.Parent) then
		U.Folder = Instance.new("Folder")
		U.Folder.Name = "ClientRaidGate"
		U.Folder.Parent = Workspace
	end
	return U.Folder
end

----------------------------------------------------------------------
-- the idle boss
----------------------------------------------------------------------
function H.dropModel()
	if S.Model then
		pcall(S.Model.Destroy, S.Model)
	end
	S.Model, S.ModelKey, S.ModelCF = nil, nil, nil
end

-- the floor's surface under the zone part's centre (the zone stands on it: attribute FloorY), the zone's own turn: -Z faces the lobby
function H.floorFrame(zone)
	local y = tonumber(zone:GetAttribute("FloorY")) or zone.Position.Y
	return zone.CFrame * CFrame.new(0, y - zone.Position.Y, 0)
end

-- the fight's own boss still stands on the floor here (a lost fight: the end's linger, nothing on the server says so)
function H.fightOnFloor()
	local battle = H.controller("BattleController")
	return battle ~= nil and type(battle.DrawsRaidFloor) == "function" and battle.DrawsRaidFloor() == true
end

function H.syncBoss()
	local raid = H.raid()
	local zone = H.floorZone()
	local pos = H.rootPosition()
	local tier = RaidGateController.Tier()
	local want = raid ~= nil and raid.Active ~= true and H.left(raid.FloorHiddenIn) <= 0 and zone ~= nil and tier ~= nil and pos ~= nil
		and (pos - zone.Position).Magnitude <= K.RANGE and not H.fightOnFloor()
	if not want then
		H.dropModel()
		return
	end
	local low = H.low()
	local detail = low and "Low" or "High"
	local key = raid.BossId .. "|" .. tostring(tier.Id) .. "|" .. detail
	if S.ModelKey ~= key or not (S.Model and S.Model.Parent) then
		H.dropModel()
		local BB = H.bossBuilder()
		if not BB or S.Failed[key] then
			return
		end
		local cf = H.floorFrame(zone)
		local model = BB.Build(raid.BossId, { Tier = tier.Id, Detail = detail, NoAura = low, CFrame = cf, Parent = H.folder() })
		if not model then
			S.Failed[key] = true
			return
		end
		S.Model, S.ModelKey, S.ModelCF = model, key, cf
		S.Yaw = 0
	end
end

-- the head comes round at K.TURN_SPEED toward the player, the idle pose breathes under it (never on Low)
function H.animateBoss(now)
	local BB = H.bossBuilder()
	if not S.Model or not BB or now - S.AnimAt < K.ANIM_GAP or H.low() then
		return
	end
	local dt = math.min(now - S.AnimAt, K.TICK)
	S.AnimAt = now
	local pos = H.rootPosition()
	local target = 0
	if pos then
		local rel = S.ModelCF:PointToObjectSpace(pos)
		target = math.max(-K.YAW_MAX, math.min(K.YAW_MAX, math.atan2(-rel.X, -rel.Z)))
	end
	local step = K.TURN_SPEED * dt
	S.Yaw = S.Yaw + math.max(-step, math.min(step, target - S.Yaw))
	BB.Animate(S.Model, "Idle", now, { LookAt = (S.ModelCF * CFrame.Angles(0, S.Yaw, 0) * CFrame.new(0, 0, -K.LOOK_AHEAD)).Position })
end

----------------------------------------------------------------------
-- the gate tag
----------------------------------------------------------------------
function H.dropTag()
	if U.Tag then
		pcall(U.Tag.Destroy, U.Tag)
	end
	U.Tag, U.TagLines = nil, nil
end

function H.buildTag(adornee)
	local gui = Instance.new("BillboardGui")
	gui.Name = "RaidGateTag"
	gui.Size = UDim2.fromOffset(K.TAG_W, K.TAG_H)
	gui.StudsOffset = Vector3.new(0, K.TAG_OFFSET, 0)
	gui.MaxDistance = K.TAG_DISTANCE
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = adornee
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundColor3 = C.Plate
	plate.BackgroundTransparency = 0.1
	plate.BorderSizePixel = 0
	plate.Size = UDim2.new(1, 0, 1, 0)
	plate.Parent = gui
	Util.Create("UICorner", { CornerRadius = UDim.new(0, 12), Parent = plate })
	Util.Create("UIStroke", { Color = C.Gold, Thickness = 2, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = plate })
	local lines = {}
	for i, spec in ipairs({ { "Heading", 22, WHITE, 6, 56 }, { "Body", 18, C.Gold, 62, 26 }, { "Heading", 18, WHITE, 90, 26 } }) do
		lines[i] = H.text(plate, "Line" .. i, "", spec[1], spec[2], spec[3], {
			Position = UDim2.fromOffset(8, spec[4]),
			Size = UDim2.new(1, -16, 0, spec[5]),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end
	gui.Parent = H.folder()
	U.Tag, U.TagLines = gui, lines
end

function H.syncTag()
	local raid = H.raid()
	local tier = RaidGateController.Tier()
	local adornee = H.tagAdornee()
	if not raid or not tier or not adornee then
		H.dropTag()
		return
	end
	if not (U.Tag and U.Tag.Parent) then
		H.dropTag()
		H.buildTag(adornee)
	end
	U.Tag.Adornee = adornee
	U.Tag.Enabled = not H.fighting()
	U.TagLines[1].Text = H.bossName(raid) .. " - your tier: " .. tostring(tier.Id) .. " (L" .. tostring(tier.BossLevel) .. " boss)"
	U.TagLines[2].Text = RaidGateController.RewardLine()
	local closed = type(raid.Closed) == "table" and H.left(raid.Closed[tier.Id]) or 0
	if closed > 0 then
		U.TagLines[3].Text = tostring(tier.Id) .. " boss back in " .. tostring(math.ceil(closed)) .. " s"
	else
		U.TagLines[3].Text = "Walk through to fight"
	end
end

function RaidGateController.Refresh()
	H.safe("boss", H.syncBoss)
	H.safe("tag", H.syncTag)
end

----------------------------------------------------------------------
-- the dare panel
----------------------------------------------------------------------
function H.build()
	if U.Holder then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = "Dare"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(K.PREF_W, K.PREF_H)
	holder.Visible = false
	holder.ZIndex = 3
	holder.Parent = U.Gui
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	U.Dock = NeonKit.Dock(holder, U.Fit, K.PREF_W, K.PREF_H)
	local panel = CloudUI.Panel({
		Name = "DarePanel",
		Title = "Dare a higher tier",
		Closable = true,
		Category = "Arena",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		OnClose = function()
			RaidGateController.Close()
		end,
		Parent = holder,
	})
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel.Root })
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(14, 8)
	list.Size = UDim2.new(1, -28, 1, -16)
	list.Parent = panel.Content
	Util.Create("UIListLayout", { Padding = UDim.new(0, K.GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	U.List = list
end

function H.dare(tierId)
	RaidGateController.Close()
	TeamFaces.Ensure(function()
		local arena = H.controller("ArenaController")
		if arena and type(arena.Request) == "function" then
			arena.Request("RaidDare", tierId)
		end
	end)
end

function H.row(tier, order)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. tostring(tier.Id)
	row.BackgroundColor3 = C.Row
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, K.ROW_H)
	row.LayoutOrder = order
	row.Parent = U.List
	Util.Create("UICorner", { CornerRadius = UDim.new(0, 12), Parent = row })
	H.text(row, "Text", tostring(tier.Id) .. " - boss L" .. tostring(tier.BossLevel) .. ", hits x" .. tostring(tier.Hit) .. ", rewards x" .. tostring(tier.Reward), "Body", 19, WHITE, {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -(K.BUTTON_W + 32), 1, 0),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	CloudUI.Button({
		Name = "Dare_" .. tostring(tier.Id),
		Text = "Dare",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(K.BUTTON_W, K.BUTTON_H),
		Style = "Red",
		TextSize = 22,
		Parent = row,
		Callback = function()
			H.safe("dare", H.dare, tier.Id)
		end,
	})
	return row
end

function H.fillRows()
	for _, child in ipairs(U.List:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local BC = H.catalog()
	local mine = RaidGateController.Tier()
	local count = 0
	for _, id in ipairs(BC and BC.RaidTierOrder or {}) do
		if mine and BC.RaidCanDare(mine.Id, id) then
			count = count + 1
			H.row(BC.RaidTierById(id), count + 1)
		end
	end
	H.text(U.List, "Intro", count > 0 and "Winning a dare pays that tier's rewards." or "You are already at the top tier.", "Body", 18, C.Muted, {
		Size = UDim2.new(1, 0, 0, K.INTRO_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
end

function H.onBack(_name, inputState)
	if inputState == Enum.UserInputState.Begin and S.Open then
		RaidGateController.Close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function H.syncBack()
	local want = S.Open == true
	if want == S.BackBound then
		return
	end
	S.BackBound = want
	if want then
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, H.onBack, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
	else
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

function RaidGateController.OpenDare(prompt)
	if not initialized then
		RaidGateController.Init()
	end
	if not U.Gui or H.fighting() then
		return false
	end
	H.build()
	H.fillRows()
	-- a panel opened at the pillar closes when the player walks off
	S.At = nil
	local pillar = typeof(prompt) == "Instance" and prompt.Parent or nil
	local pos = H.rootPosition()
	if pillar and pillar:IsA("BasePart") and pos and (pos - pillar.Position).Magnitude <= K.WALK_AWAY then
		S.At = pillar
	end
	local was = S.Open
	if not was then
		for _, name in ipairs({ "MenuController", "IndexController", "FusionController", "CareController", "ArenaController", "DungeonController", "ObbyController" }) do
			local mod = H.controller(name)
			if mod and type(mod.Close) == "function" then
				pcall(mod.Close)
			end
		end
	end
	S.Open = true
	S.Token = S.Token + 1
	H.syncBack()
	if U.Dock and U.Dock.Refresh then
		U.Dock.Refresh()
	end
	U.Holder.Visible = true
	if not was then
		U.Pop.Scale = 0.9
		Util.Tween(U.Pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		RaidGateController.Opened:Fire("Dare")
	end
	return true
end

function RaidGateController.Close()
	if not S.Open then
		return
	end
	S.Open = false
	S.At = nil
	S.Token = S.Token + 1
	local mine = S.Token
	H.syncBack()
	if U.Pop then
		Util.Tween(U.Pop, 0.12, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(0.13, function()
		if S.Token == mine and not S.Open and U.Holder then
			U.Holder.Visible = false
			U.Pop.Scale = 1
		end
	end)
	RaidGateController.Closed:Fire("Dare")
end

function RaidGateController.IsOpen()
	return S.Open == true
end

----------------------------------------------------------------------
-- server messages + Init
----------------------------------------------------------------------
function H.onArenaState(state)
	if type(state) ~= "table" then
		return
	end
	S.Arena = state
	S.ArenaAt = os.clock()
	RaidGateController.Refresh()
end

function H.onBattleState(kind, payload)
	if kind ~= "Start" or type(payload) ~= "table" then
		return
	end
	if payload.Spectator ~= true and (payload.Side or 1) ~= 0 then
		RaidGateController.Close()
	end
	-- a fight on the real floor, seen before the next ArenaState: the fight's own boss stands there now
	local raid = H.raid()
	if raid and payload.Mode == "Raid" and type(payload.Raid) == "table" and payload.Raid.Pocket == false then
		raid.Active = true
		H.safe("boss", H.syncBoss)
	end
end

function H.heartbeat()
	local now = os.clock()
	H.safe("animate", H.animateBoss, now)
	if now < S.TickAt then
		return
	end
	S.TickAt = now + K.TICK
	H.safe("boss", H.syncBoss)
	if now >= S.TagAt then
		S.TagAt = now + K.TAG_EVERY
		H.safe("tag", H.syncTag)
	elseif U.Tag then
		U.Tag.Enabled = not H.fighting()
	end
	if S.Open and S.At then
		local pos = H.rootPosition()
		if pos and (pos - S.At.Position).Magnitude > K.WALK_AWAY then
			RaidGateController.Close()
		end
	end
end

function RaidGateController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	U.Gui = CloudUI.NewScreenGui("NimbusRaidGate", K.DISPLAY_ORDER)
	local conns = S.Conns
	conns[#conns + 1] = State.Changed:Connect(function()
		S.Tier = nil
		RaidGateController.Refresh()
	end)
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input)
		if S.Open and input.KeyCode == Enum.KeyCode.Escape then
			RaidGateController.Close()
		end
	end)
	conns[#conns + 1] = RunService.Heartbeat:Connect(H.heartbeat)
	task.spawn(function()
		local okArena, arenaRemote = pcall(Remotes.Get, "ArenaState")
		if okArena and arenaRemote and initialized then
			conns[#conns + 1] = arenaRemote.OnClientEvent:Connect(function(state)
				H.safe("ArenaState", H.onArenaState, state)
			end)
		end
		local okBattle, battleRemote = pcall(Remotes.Get, "BattleState")
		if okBattle and battleRemote and initialized then
			conns[#conns + 1] = battleRemote.OnClientEvent:Connect(function(kind, payload)
				H.safe("BattleState", H.onBattleState, kind, payload)
			end)
		end
	end)
	-- one side panel at a time
	task.defer(function()
		for _, spec in ipairs({ { "MenuController", "WindowOpened" }, { "IndexController", "Opened" }, { "FusionController", "Opened" }, { "CareController", "Opened" },
			{ "ArenaController", "Opened" }, { "DungeonController", "Opened" }, { "ObbyController", "Opened" } }) do
			local mod = H.controller(spec[1])
			local signal = mod and mod[spec[2]]
			if type(signal) == "table" and type(signal.Connect) == "function" then
				conns[#conns + 1] = signal:Connect(function(windowId)
					if windowId ~= "Dare" then
						RaidGateController.Close()
					end
				end)
			end
		end
	end)
end

function RaidGateController.Stop()
	RaidGateController.Close()
	for _, conn in ipairs(S.Conns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	S.Conns = {}
	H.dropModel()
	H.dropTag()
	if U.Folder then
		pcall(U.Folder.Destroy, U.Folder)
	end
	if U.Gui then
		pcall(U.Gui.Destroy, U.Gui)
	end
	U = {}
	S.Arena, S.Tier = nil, nil
	initialized = false
end

return RaidGateController
