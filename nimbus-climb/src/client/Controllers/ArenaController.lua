-- ArenaController (client, Phase 3, ui; Phase 5 dungeonclient W4): the battle windows and side cards of the Battle Arena
-- (ARCHITECTURE_V3.md "Phase 3: Pet battles", the "Phase 3 build contract", Phase 4 3.8 and the "Phase 5 build contract"
-- 3.7, 4.2, 5.3, 6.6, 10.5).
--
--   ArenaController.Init()
--   ArenaController.OpenArena(tab|nil)        the Arena panel: tab "Duels" | "Raid" | "Leaderboard" (OpenPanel("Arena",
--                                             {Tab}), the duel pads, the event board, the trophy board, the main gate)
--   ArenaController.OpenRing(start|nil, portal|nil)  Phase 4: the Champion Ring window (Portal_Ring's RingPrompt,
--                                             OpenPanel("Ring", {Start}))
--   ArenaController.Close()
--   Extras: ArenaController.IsOpen() -> bool, ArenaController.GetState() -> { Arena = last ArenaState, Lobby = last
--           BattleState "Lobby", Window = "Arena" | "Ring" | nil, Tab, RingStart }, ArenaController.Opened / Closed
--           (Util.Signal), ArenaController.Request(action, a, b) (sends BattleRequest like the buttons do: client-side
--           spacing, the server validates everything), ArenaController.StartRing() (the ring window's START),
--           ArenaController.RingInfo() -> { Best, Runs, Start, Starts, Board, Fighters, Source, Preview, Why }
--
-- Phase 5: the Trial window is gone (the Dungeon replaced it). Portal_Dungeon's DungeonPrompt (OpenPanel = "Dungeon") is
-- handed over to DungeonController.Open here, next to "Ring". Both windows are NeonKit side panels (640 x 860 design px,
-- NeonKit.Dock: docked right on landscape screens, a bottom sheet on portrait phones, no full-screen dimming; the hotbar
-- re-centres with HotbarController.SetAvoidRight). A challenge more than Duel.PracticeInvite apart carries
-- Practice = true: the invite says "Practice duel - no trophies or rewards". The Ring's fighter cards draw each pet's
-- stored evolution stage (State.PetStage -> CloudUI.PetViewport { Evolved }, a STAGE badge).
--
-- What the player sees
--   * Arena panel (OpenPanel = "Arena", OpenPanelTab = "Events" | "Leaderboard" | "Raid"; the duel pads carry
--     RingIndex / PadIndex): DUELS (the quick queue: Queue / Unqueue + the wait; challenge a player in the server:
--     Challenge(userId); incoming invites with Accept / Decline (the practice flag); the player's trophies and duel
--     record), BOSS RAID (the running raid: boss, element, HP, fighters, time left, JOIN / LEAVE; the next event with its
--     countdown; Double Rewards; which elements beat the boss; the reward tiers) and LEADERS (ArenaState.Leaderboard,
--     top 10, the player's own row highlighted).
--   * Champion Ring window (Portal_Ring's prompt, OpenPanel = "Ring"): the record "Best: Round N" and the runs, the best
--     of this server (Portal_Ring's RingBoard attribute, top 3), the start picker (round 1 or a boss round 10, 20 ...
--     already beaten), the start round's champion, "Next win: +$X +Y XP", the fighters the server will field (the battle
--     team, else the equipped pets, else the strongest pets; training pets skipped; evolved looks) and START / CONTINUE
--     -> BattleRequest("Ring", start). The server's refusal toasts also show in the footer. The Team screen gets a
--     "Champion Ring best: Round N" line from here. A side toast when the player crosses the arena's edge: "Battle
--     Arena: pets can battle here" / "Safe zone: no pet battles here".
--   * Side cards (right edge, above the hotbar, never in the screen centre; ScreenGui "NimbusArenaSide"): a duel
--     invite (BattleState "Lobby".Invites) with Accept / Decline and a draining timer, the invite the player sent,
--     the quick-queue status with Leave, the raid join card while a raid can be joined and the event countdown chip
--     ("Boss Raid in 1:45", "2x Rewards 29:12"). Countdowns tick locally between two ArenaState messages. All of it
--     hides in an obby match and while the player fights (attribute InBattle).
-- Remotes: BattleState ("Lobby" in), ArenaState (in), OpenPanel (in), Notify (in: ring refusals), BattleRequest (out:
-- Ring, Challenge, ChallengeReply, Queue, Unqueue, JoinRaid, LeaveRaid). Every request is spaced on the client too (K.FIRE_GAP).
-- One side panel at a time: opening one closes the menu windows, the Pet Index, the Fusion / Care windows, the Dungeon
-- window and the obby picker, and their opening closes this one. Esc / gamepad B / the red X close it; walking away from
-- the Ring portal closes the Ring window. Readability rule: everything is designed in 1080p pixels (body 19, captions
-- >= 18, buttons 22, titles 26-34) under ONE UIScale, so phones keep >= 14 px.
-- Plain Lua 5.1-compatible syntax only. All fonts come from Theme roles; no asset ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))
local State = require(Client:WaitForChild("State"))

-- other engineers' shared modules: optional, every use is guarded
local function optionalShared(name)
	local module = Shared:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	warn("[ArenaController] " .. name .. " is unavailable: " .. tostring(result))
	return nil
end

local PetCatalog = optionalShared("PetCatalog")
local PetKeys = optionalShared("PetKeys")
local BattleCatalog = nil -- resolved on first use (see catalog())

local ArenaController = {}
ArenaController.Opened = Util.Signal()
ArenaController.Closed = Util.Signal()

----------------------------------------------------------------------
-- Tunables (design pixels of a 1080p screen unless noted)
----------------------------------------------------------------------
local K = {
	DISPLAY_ORDER = 23, -- above NimbusMenu (20), the Pet Index (21) and the Fusion window (22)
	SIDE_ORDER = 12, -- side cards: above the HUD (10) and the hotbar (11), below the windows
	PREF_W = 640, -- Phase 5 (6.6): the Arena / Ring windows are NeonKit side panels of 640 x 860 design px
	PREF_H = 860,
	TALL = 760, -- windows narrower than this use the single-column layout (every docked window)
	NARROW = 1000,
	SHORT = 560, -- docked lower than this (landscape phones): the compact rows
	INSET_X = 24, -- the panel frame around Panel.Content (CloudUI.ContentInset)
	INSET_Y = 82,
	FIRE_GAP = 0.5, -- seconds between two sends of the same request
	RING_RANGE = 28, -- studs from the Champion Ring portal where START works (the server allows 30)
	WALK_AWAY = 70, -- studs from the portal that close a Ring window opened there
	ARENA_SLACK = 12, -- studs around the arena's bounding box that still count as "in the arena"
	SIDE_W = 340, -- side cards
	SIDE_BOTTOM = 112, -- design px above the bottom edge (clear of the hotbar's corner and the HUD)
	SIDE_BOTTOM_TOUCH = 210, -- touch screens: above Roblox's jump button
	SIDE_BOTTOM_PORTRAIT = 340, -- portrait phones: above the HUD's raised bottom-left block (vitals + currency)
	SIDE_MAX_CARDS = 3,
	SIDE_MAX_CARDS_SHORT = 1,
	ANNOUNCE = 120, -- seconds before an event when the countdown chip appears (BattleCatalog.Events.AnnounceSeconds)
	BACK_ACTION = "NimbusArenaBack",
	TICK = 0.25, -- seconds between two refreshes of the live numbers
	ATTR_IN_BATTLE = "InBattle", -- BattleService's attribute (the battle id while the player fights)
}

local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Colors.Gold or Colors.Token
local INK = Colors.TextStroke or Colors.Ink
local GOOD = Colors.Good
local BAD = Colors.Bad
local BUTTONS = Theme.Buttons or {}
local INSET = Color3.fromRGB(20, 30, 70)
local C = {
	Arena = Color3.fromRGB(214, 92, 96), -- the panels' accent (crimson)
	Practice = Color3.fromRGB(120, 196, 255), -- a practice duel (no trophies, no rewards)
	Power = Color3.fromRGB(255, 214, 110),
	GoodText = Color3.fromRGB(150, 236, 170),
	WarnText = Color3.fromRGB(255, 206, 120),
	BadText = Color3.fromRGB(255, 150, 150),
	Lock = Color3.fromRGB(255, 206, 120),
	Boss = Color3.fromRGB(226, 90, 92),
	Cleared = Color3.fromRGB(96, 196, 108),
	Next = Color3.fromRGB(90, 158, 234),
	Token = Colors.Token or GOLD,
	Gem = Colors.Gem or Color3.fromRGB(84, 196, 246),
	Double = Color3.fromRGB(150, 110, 232),
	Me = Color3.fromRGB(70, 110, 190),
	Medal = { Color3.fromRGB(246, 200, 70), Color3.fromRGB(200, 210, 226), Color3.fromRGB(214, 146, 92) },
}

-- glyphs as UTF-8 escapes (the source stays ASCII)
local G = {
	Swords = "\226\154\148",
	Trophy = "\240\159\143\134",
	Cloud = "\226\152\129",
	Gem = (Theme.Currency and Theme.Currency.Gems and Theme.Currency.Gems.Glyph) or "\226\151\134",
	Lock = "\240\159\148\146",
	Check = "\226\156\147",
	Crown = "\240\159\145\145",
	Clock = "\226\143\177",
	Star = "\226\152\133",
	Bullet = "\194\183",
	Heart = "\226\157\164",
	Skull = "\240\159\146\128",
	Double = "\226\156\150", -- heavy multiplication x
	Up = "\226\150\178",
}

----------------------------------------------------------------------
-- Module state
----------------------------------------------------------------------
local LocalPlayer = nil
local initialized = false
local U = {} -- gui references
local S = {
	Open = nil, -- "Arena" | "Ring" | nil
	Token = 0,
	Tab = "Duels",
	Arena = nil, -- last ArenaState
	ArenaAt = 0, -- os.clock() when it arrived
	Lobby = nil, -- last BattleState "Lobby"
	LobbyAt = 0,
	RingAt = nil, -- the portal part when the Champion Ring window was opened there
	BackBound = false,
	LastFire = {},
	Built = {},
	Tall = false,
	Narrow = false,
	Short = false,
	Warned = {},
	ArenaBox = nil, -- { CFrame, Size } of workspace.BattleArena (static, measured once)
}
local Win = {} -- per-window widget tables: Win.Arena, Win.Ring

local refreshOpen, refreshSide, screenFactor -- forward declarations

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[ArenaController] " .. key .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

local function catalog()
	if not BattleCatalog then
		BattleCatalog = optionalShared("BattleCatalog")
	end
	return BattleCatalog
end

local function makeFrame(parent, name, props)
	local p = props or {}
	p.Name = name
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	p.Parent = parent
	return Util.Create("Frame", p)
end

local function makeText(parent, name, text, role, size, color, props)
	local p = { Name = name }
	if props then
		for key, value in pairs(props) do
			p[key] = value
		end
	end
	local label = Theme.Label(tostring(text), role, {
		Size = size,
		Color = color or WHITE,
		Stroke = 0.25,
		StrokeColor = INK,
		Outline = 1.5,
		OutlineColor = INK,
		Props = p,
	})
	label.Parent = parent
	return label
end

local function corner(parent, radius)
	return Theme.Corner(parent, UDim.new(0, radius or 12))
end

local function round(parent)
	return Theme.Corner(parent, UDim.new(0.5, 0))
end

local function stroke(parent, color, thickness, transparency)
	return Theme.Stroke(parent, color or NAVY, thickness or 3, transparency or 0)
end

local function pad(parent, left, top, right, bottom)
	return Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		Parent = parent,
	})
end

local function listLayout(parent, direction, gap, hAlign, vAlign)
	return Util.Create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 0),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

local function scroller(parent, name, props)
	local p = props or {}
	p.Name = name
	p.BackgroundTransparency = 1
	p.BorderSizePixel = 0
	p.CanvasSize = UDim2.new(0, 0, 0, 0)
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	p.ScrollingDirection = Enum.ScrollingDirection.Y
	p.ScrollBarThickness = 10
	p.ScrollBarImageColor3 = Colors.FrameTop or Colors.Cloud
	p.ScrollBarImageTransparency = 0.1
	p.Parent = parent
	return Util.Create("ScrollingFrame", p)
end

local function inset(parent, name, props)
	local p = props or {}
	p.BackgroundColor3 = INSET
	p.BackgroundTransparency = 0.42
	local frame = makeFrame(parent, name, p)
	corner(frame, 12)
	stroke(frame, Colors.WellEdge or NAVY, 3, 0.15)
	return frame
end

local function autoText(parent, name, text, role, size, color, order)
	return makeText(parent, name, text, role, size, color, {
		Size = UDim2.fromOffset(0, size + 8),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order or 0,
	})
end

local function wrapText(parent, name, text, role, size, color, order)
	return makeText(parent, name, text, role, size, color, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order or 0,
	})
end

local function clearChildren(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function colorPill(parent, name, text, color, size, order)
	local dark = Theme.Darken(color, 0.62)
	local textSize = size or 18
	local pill = Theme.Label(text, "Heading", {
		Size = textSize,
		Color = WHITE,
		Stroke = 0.1,
		StrokeColor = dark,
		Outline = 1.5,
		OutlineColor = dark,
		Props = {
			Name = name,
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, textSize + 9),
			LayoutOrder = order or 0,
		},
	})
	round(pill)
	stroke(pill, NAVY, 2, 0)
	Theme.Gradient(pill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 206, 226), 90)
	pad(pill, 9, 0, 9, 1)
	pill.Parent = parent
	return pill
end

local function elementColor(element)
	local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[element]
	return info and info.Color or Colors.PanelLight
end

local function elementPill(parent, element, size, order)
	return colorPill(parent, "Element_" .. tostring(element), tostring(element), elementColor(element), size, order)
end

local function commas(n)
	return Util.Commas(math.floor(tonumber(n) or 0))
end

local function clock(seconds)
	seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

local function tween(inst, seconds, goal, style, direction)
	return Util.Tween(inst, seconds, goal, style, direction)
end

local function rarityColor(def)
	return CloudUI.RarityColor(def and def.Rarity)
end

local function rarityText(def)
	if def and def.Rarity == "Secret" then
		return Color3.fromRGB(196, 168, 255)
	end
	return Theme.Lighten(rarityColor(def), 0.3)
end

local function elementsOf(def)
	if type(def) ~= "table" then
		return {}
	end
	if PetCatalog and type(PetCatalog.ElementsOf) == "function" then
		local ok, list = pcall(PetCatalog.ElementsOf, def)
		if ok and type(list) == "table" then
			return list
		end
	end
	if type(def.Element) == "string" then
		return { def.Element }
	end
	return {}
end

----------------------------------------------------------------------
-- Game state readers
----------------------------------------------------------------------
local function attr(name)
	return LocalPlayer and LocalPlayer:GetAttribute(name) or nil
end

local function inMatch()
	return attr(Config.Attr.InMatch) == true
end

local function battleId()
	local id = attr((Config.Attr and Config.Attr.InBattle) or K.ATTR_IN_BATTLE)
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

local function battleData()
	if type(State.Battle) == "function" then
		local ok, b = pcall(State.Battle)
		if ok and type(b) == "table" then
			return b
		end
	end
	return { Trophies = 0, PvPWins = 0, PvPLosses = 0, Raids = 0 }
end

local function teamsData()
	if type(State.Teams) == "function" then
		local ok, t = pcall(State.Teams)
		if ok and type(t) == "table" and type(t.Presets) == "table" then
			return t
		end
	end
	return { Presets = { {}, {}, {} }, Active = 1, Slots = 3 }
end

-- the active preset as BattleCatalog entries { Def, Level, Key }
local function activeTeam()
	local teams = teamsData()
	local list = teams.Presets[teams.Active] or {}
	local out = {}
	for _, key in ipairs(list) do
		local def = nil
		if type(State.DefOf) == "function" then
			local ok, result = pcall(State.DefOf, key)
			if ok and type(result) == "table" then
				def = result
			end
		end
		if not def and PetCatalog and type(PetCatalog.Get) == "function" then
			def = PetCatalog.Get(key)
		end
		if def then
			local level = 1
			if type(State.PetLevel) == "function" then
				local ok, lv = pcall(State.PetLevel, key)
				if ok and type(lv) == "number" then
					level = lv
				end
			end
			out[#out + 1] = { Def = def, Level = level, Key = key }
		end
	end
	return out
end

local function teamPower(entries)
	local BC = catalog()
	if not BC or type(BC.TeamPower) ~= "function" then
		return 0
	end
	local ok, p = pcall(BC.TeamPower, entries)
	return ok and tonumber(p) or 0
end

local function petDef(petId, tier)
	if PetKeys and type(PetKeys.DefOf) == "function" and type(PetKeys.Make) == "function" and tier and tier ~= "Normal" then
		local ok, def = pcall(function()
			return PetKeys.DefOf(PetKeys.Make(petId, tier), nil)
		end)
		if ok and type(def) == "table" then
			return def
		end
	end
	if PetCatalog and type(PetCatalog.Get) == "function" then
		return PetCatalog.Get(petId)
	end
	return nil
end

-- seconds left of a countdown field of the last ArenaState, ticking locally
local function arenaSeconds(value)
	local n = tonumber(value)
	if not n then
		return nil
	end
	return math.max(0, n - (os.clock() - S.ArenaAt))
end

local function lobbySeconds(value)
	local n = tonumber(value)
	if not n then
		return nil
	end
	return math.max(0, n - (os.clock() - S.LobbyAt))
end

local function rootPosition()
	local character = LocalPlayer and LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function arenaModel()
	return Workspace:FindFirstChild("BattleArena")
end

local function positionOf(inst)
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		local ok, cf = pcall(function()
			return inst:GetBoundingBox()
		end)
		if ok and cf then
			return cf.Position
		end
	end
	local part = inst:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

-- true / false when the arena is known, nil when it cannot be told (the server decides then)
local function inArena()
	local pos = rootPosition()
	local arena = arenaModel()
	if not pos or not arena or not arena:IsA("Model") then
		return nil
	end
	if not S.ArenaBox then
		local ok, cf, size = pcall(function()
			return arena:GetBoundingBox()
		end)
		if not ok or not cf then
			return nil
		end
		S.ArenaBox = { CFrame = cf, Size = size }
	end
	local rel = S.ArenaBox.CFrame:PointToObjectSpace(pos)
	local half = S.ArenaBox.Size / 2
	local m = K.ARENA_SLACK
	return math.abs(rel.X) <= half.X + m and math.abs(rel.Z) <= half.Z + m and rel.Y <= half.Y + 40 and rel.Y >= -half.Y - 40
end

----------------------------------------------------------------------
-- Requests (BattleRequest; spaced here, validated on the server)
----------------------------------------------------------------------
local requestRemote = nil

local function request(action, a, b)
	local now = os.clock()
	local key = action .. "|" .. tostring(a)
	if S.LastFire[key] and now - S.LastFire[key] < K.FIRE_GAP then
		return false
	end
	if not requestRemote then
		local ok, remote = pcall(Remotes.Get, "BattleRequest")
		if ok and remote then
			requestRemote = remote
		end
	end
	if not requestRemote then
		return false
	end
	S.LastFire[key] = now
	local ok, err = pcall(function()
		requestRemote:FireServer(action, a, b)
	end)
	if not ok then
		warnOnce("BattleRequest " .. action, err)
	end
	return ok
end

-- a short hint at the right edge (never in the screen centre), e.g. "Walk into the Battle Arena to duel!"
local function toast(text, kind)
	if not U.HintGui then
		return
	end
	S.HintToken = (S.HintToken or 0) + 1
	local mine = S.HintToken
	U.HintLabel.Text = tostring(text)
	U.HintFrame.BackgroundColor3 = (kind == "bad") and Color3.fromRGB(120, 40, 56) or Color3.fromRGB(28, 36, 78)
	U.HintFrame.Visible = true
	U.HintScale.Scale = screenFactor and screenFactor() or 1
	task.delay(2.8, function()
		if S.HintToken == mine and U.HintFrame then
			U.HintFrame.Visible = false
		end
	end)
end

local function otherController(name)
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

local function openTeamWindow()
	local menu = otherController("MenuController")
	ArenaController.Close()
	if menu and type(menu.Open) == "function" then
		pcall(menu.Open, "Team", {})
	end
end

----------------------------------------------------------------------
-- Window frame (one CloudUI panel per window, both in the ScreenGui NimbusArena)
----------------------------------------------------------------------
local function guiArea()
	local size = U.Gui and U.Gui.AbsoluteSize or Vector2.new(1280, 720)
	if size.X < 2 or size.Y < 2 then
		return Vector2.new(1280, 720)
	end
	return size
end

function screenFactor()
	local camera = Workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	if vp and vp.Y > 2 then
		return Theme.ScreenFactor(vp.Y)
	end
	return Theme.ScreenFactor(guiArea().Y)
end

local function newWindow(id, title)
	local win = { Id = id }
	win.Holder = makeFrame(U.Gui, "Window_" .. id, {
		Size = UDim2.fromOffset(K.PREF_W, K.PREF_H),
		Visible = false,
		ZIndex = 3,
	})
	win.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = win.Holder })
	-- Phase 5 (6.6): docked right on landscape screens, a bottom sheet on portrait phones (NeonKit.Dock), no dimming
	win.Dock = NeonKit.Dock(win.Holder, win.Fit, K.PREF_W, K.PREF_H)
	win.Panel = CloudUI.Panel({
		Name = id .. "Panel",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Title = title,
		Closable = true,
		Category = (id == "Ring") and "Ring" or "Arena",
		OnClose = function()
			ArenaController.Close()
		end,
		Parent = win.Holder,
	})
	win.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = win.Panel.Root })
	Win[id] = win
	return win
end

-- the hotbar re-centres left of a docked window (HotbarController.SetAvoidRight; nil = no window)
local function avoidRight(x)
	local hb = otherController("HotbarController")
	if hb and type(hb.SetAvoidRight) == "function" then
		pcall(hb.SetAvoidRight, x)
	end
end

-- the docked size (design px) -> the window's own layout: every docked window is narrow ("tall" = one column);
-- "short" = a landscape phone (the window is lower than K.SHORT)
local function layoutWindow(win)
	if win.Dock and win.Dock.Refresh then
		win.Dock.Refresh()
	end
	local rect = win.Dock and win.Dock.Rect
	local w = rect and math.floor(rect.designW + 0.5) or K.PREF_W
	local h = rect and math.floor(rect.designH + 0.5) or K.PREF_H
	local tall = w < K.TALL
	S.Tall = tall
	S.Narrow = w < K.NARROW
	S.Short = h < K.SHORT
	if S.Open == win.Id then
		avoidRight(rect and rect.mode == "Side" and rect.x or nil)
	end
	if win.OnLayout and (win.W ~= w or win.H ~= h) then
		win.W, win.H = w, h
		safe("layout " .. win.Id, win.OnLayout, w, h, S.Narrow, S.Short, tall)
	end
end

----------------------------------------------------------------------
-- Champion Ring window (Phase 4, "Phase 4 build contract" 3.8): the record ("Best: Round N"), the best of this server
-- (Portal_Ring's RingBoard attribute), the start picker (round 1 or a boss round already beaten), the next round's
-- champion, the fighters with their power, "Next win: +$X +Y XP" and START -> BattleRequest("Ring", start). The
-- server decides everything again (StartRing); its refusal toasts also show in the window's footer. Every helper of
-- the ring lives in this one table (the file stays far under the 200-locals limit).
----------------------------------------------------------------------
local Ring = {
	Start = 1, -- the picked start round
	Pending = false, -- START was sent, no Start / refusal yet
	PendingAt = 0,
	Refusal = nil, -- the last ring refusal toast of the server (shown in the footer for a few seconds)
	RefusalAt = 0,
	LastZone = nil, -- safe-zone toast: true in the Battle Arena, false outside, nil unknown
	BattleAt = -100, -- os.clock() when the player last fought (no zone toast right after a battle's return teleport)
	CARD_H = 112, -- design px of a fighter card
	TILE_H = 66, -- design px of a start picker tile
}

-- the server's entry refusals (BattleService.StartRing; prefixes of its Notify texts)
Ring.REFUSALS = {
	"Claim your home first", "You need a pet", "Your pets are all training", "Walk to the Champion Ring portal",
	"Your save is still loading", "Start from round 1 or a boss round", "Every ring is busy", "Finish your obby match",
	"Leave the portal party", "You are already in a battle", "Wait until you respawn", "The server is restarting",
}

function Ring.cfg()
	local BC = catalog()
	return BC and type(BC.Ring) == "table" and BC.Ring or {}
end

function Ring.bossEvery()
	return math.max(1, math.floor(tonumber(Ring.cfg().BossEvery) or 10))
end

-- the record { Best, Runs } (State.Ring, synced by ProfileSync)
function Ring.record()
	local ok, r = pcall(function()
		return State.Ring()
	end)
	r = (ok and type(r) == "table") and r or {}
	return math.max(0, math.floor(tonumber(r.Best) or 0)), math.max(0, math.floor(tonumber(r.Runs) or 0))
end

function Ring.portal()
	local arena = arenaModel()
	local model = arena and arena:FindFirstChild("Portal_Ring", true) or nil
	if not model then
		model = Workspace:FindFirstChild("Portal_Ring", true)
	end
	return model
end

-- where the distance is measured to: the part the prompt sat on, else Portal_Ring's PortalPad (or the model)
function Ring.anchor()
	if S.RingAt and S.RingAt.Parent then
		return S.RingAt
	end
	local model = Ring.portal()
	return model and (model:FindFirstChild("PortalPad", true) or model) or nil
end

function Ring.distance()
	local pos = rootPosition()
	local at = positionOf(Ring.anchor())
	if not pos or not at then
		return nil
	end
	local d = pos - at
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- "Alex|31;Sam|24;Kim|20" (written by BattleService on Portal_Ring and its pad) -> { { Name, Round }... } best first
function Ring.board()
	local model = Ring.portal()
	local text = model and model:GetAttribute("RingBoard") or nil
	if type(text) ~= "string" or text == "" then
		local pad = model and model:FindFirstChild("PortalPad", true)
		text = pad and pad:GetAttribute("RingBoard") or nil
	end
	local list = {}
	if type(text) == "string" then
		for entry in text:gmatch("[^;]+") do
			local name, round = entry:match("^(.-)|(%d+)$")
			round = tonumber(round)
			if name and name ~= "" and round and round > 0 then
				list[#list + 1] = { Name = name:gsub("[%c<>&]", ""), Round = math.floor(round) }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.Round ~= b.Round then
			return a.Round > b.Round
		end
		return a.Name < b.Name
	end)
	while #list > 3 do
		table.remove(list)
	end
	return list
end

-- the start rounds the server accepts: 1 and every boss round already beaten (the latest seven of them)
function Ring.starts(best)
	local every = Ring.bossEvery()
	local out = { 1 }
	local top = math.floor(best / every)
	for k = math.max(1, top - 6), top do
		out[#out + 1] = k * every
	end
	return out
end

function Ring.training(key)
	if type(State.IsTraining) ~= "function" then
		return false
	end
	local ok, busy = pcall(State.IsTraining, key)
	return ok and busy == true
end

-- a pet key as a BattleCatalog entry { Def, Level, Key, Evo, Train, Power }, or nil
function Ring.entryOf(key)
	local def = nil
	if type(State.DefOf) == "function" then
		local ok, result = pcall(State.DefOf, key)
		if ok and type(result) == "table" then
			def = result
		end
	end
	if not def and PetCatalog and type(PetCatalog.Get) == "function" then
		def = PetCatalog.Get(key)
	end
	if not def then
		return nil
	end
	local level = 1
	if type(State.PetLevel) == "function" then
		local ok, lv = pcall(State.PetLevel, key)
		if ok and type(lv) == "number" then
			level = lv
		end
	end
	local okG, g = pcall(function()
		return State.PetGrowth(key)
	end)
	g = (okG and type(g) == "table") and g or {}
	local entry = {
		Def = def,
		Level = level,
		Key = key,
		Evo = tonumber(g.Evo) or 0,
		Train = { Speed = g.Speed or 0, Physique = g.Physique or 0, Ability = g.Ability or 0, Defense = g.Defense or 0 },
		Power = 0,
	}
	local BC = catalog()
	if BC and type(BC.UnitPower) == "function" then
		local ok, p = pcall(BC.UnitPower, entry)
		entry.Power = ok and tonumber(p) or 0
	end
	return entry
end

function Ring.collect(keys)
	local out = {}
	for _, key in ipairs(type(keys) == "table" and keys or {}) do
		if type(key) == "string" and not Ring.training(key) then
			local entry = Ring.entryOf(key)
			if entry then
				out[#out + 1] = entry
			end
		end
	end
	return out
end

function Ring.ownedKeys()
	local ok, keys = pcall(State.Keys)
	return (ok and type(keys) == "table") and keys or {}
end

-- the fighters the server will pick (contract 3.8): the active team (training pets skipped), else the equipped pets,
-- else the best owned pets by power (up to the team slots); and where they came from ("team" | "equipped" | "best")
function Ring.fighters()
	local teams = teamsData()
	local list = Ring.collect(teams.Presets[teams.Active])
	if #list > 0 then
		return list, "team"
	end
	local okEq, equipped = pcall(function()
		return State.EquippedList()
	end)
	list = Ring.collect(okEq and equipped or nil)
	if #list > 0 then
		return list, "equipped"
	end
	list = Ring.collect(Ring.ownedKeys())
	table.sort(list, function(a, b)
		if a.Power ~= b.Power then
			return a.Power > b.Power
		end
		return tostring(a.Key) < tostring(b.Key)
	end)
	local slots = math.max(1, math.floor(tonumber(teams.Slots) or 3))
	while #list > slots do
		table.remove(list)
	end
	return list, "best"
end

-- the garden's coins per second (the plot attribute IncomePerSecond): ring Cash is a few seconds of it
function Ring.income()
	local index = attr(Config.Attr.SpotIndex)
	if type(index) ~= "number" then
		return 0
	end
	local folder = Ring.Folder
	if not (folder and folder.Parent and folder:GetAttribute("SpotIndex") == index) then
		local lobby = Workspace:FindFirstChild("NimbusLobby")
		folder = lobby and lobby:FindFirstChild(string.format("Spot_%02d", index), true) or nil
		Ring.Folder = folder
	end
	local value = folder and folder:GetAttribute("IncomePerSecond")
	return type(value) == "number" and value or 0
end

-- "Common", "Uncommon or Rare"
function Ring.bandText(round)
	local cfg = Ring.cfg()
	if round <= #(cfg.EasyRounds or {}) then
		return "Common"
	end
	for _, band in ipairs(cfg.Bands or {}) do
		if round >= (tonumber(band.From) or 0) and (band.To == nil or round <= band.To) then
			local names = band.Rarities or {}
			if #names <= 1 then
				return tostring(names[1] or "")
			end
			return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
		end
	end
	return ""
end

-- the round `round`: { Boss, Power (about: the run's seed picks the species), Band, Cash, Xp, Tokens, Record }
function Ring.preview(round, best)
	local BC = catalog()
	local out = { Round = round, Boss = round % Ring.bossEvery() == 0, Power = 0, Band = Ring.bandText(round), Cash = 0, Xp = 0,
		Tokens = 0, Record = round > best }
	if BC and type(BC.RingPower) == "function" then
		local ok, p = pcall(BC.RingPower, round, 1)
		out.Power = ok and tonumber(p) or 0
	end
	if BC and type(BC.RingRewards) == "function" then
		local ok, r = pcall(BC.RingRewards, round, Ring.income(), out.Record)
		if ok and type(r) == "table" then
			out.Cash, out.Xp, out.Tokens = tonumber(r.Cash) or 0, tonumber(r.Xp) or 0, tonumber(r.Tokens) or 0
		end
	end
	return out
end

-- why START cannot work right now (the server's checks, in its order), or nil
function Ring.why(fighters)
	if type(attr(Config.Attr.SpotIndex)) ~= "number" then
		return "Claim your home first: press E at a free gate."
	end
	if #Ring.ownedKeys() == 0 then
		return "You need a pet: spin a roulette in the Cloud Shop."
	end
	if #(fighters or {}) == 0 then
		return "Your pets are all training right now."
	end
	if inMatch() then
		return "Finish your obby match first."
	end
	if battleId() then
		return "You are already in a battle."
	end
	local d = Ring.distance()
	if d and d > K.RING_RANGE then
		return "Walk to the Champion Ring portal."
	end
	if Ring.Refusal and os.clock() - Ring.RefusalAt < 6 then
		return Ring.Refusal
	end
	return nil
end

function Ring.money(n)
	return "$" .. commas(n)
end

-- one fighter card (viewport, name, level, power)
function Ring.fighterCard(parent, entry, order, handles)
	local def = entry.Def
	local card = makeFrame(parent, "Fighter" .. order, { BackgroundTransparency = 0, BackgroundColor3 = WHITE, LayoutOrder = order })
	corner(card, 12)
	stroke(card, NAVY, 3, 0)
	local tint = rarityColor(def)
	Theme.Gradient(card, Theme.Lighten(INSET, 0.3):Lerp(tint, 0.4), Theme.Darken(INSET, 0.05):Lerp(tint, 0.2), 90)
	local view = makeFrame(card, "ViewHolder", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(1, -10, 0, 54),
		ZIndex = 2,
	})
	-- Phase 5 (3.7): the stored evolution stage (an evolved model is always built Low)
	local stage = 0
	if type(State.PetStage) == "function" and entry.Key then
		local okStage, n = pcall(State.PetStage, entry.Key)
		stage = okStage and tonumber(n) or 0
	end
	card:SetAttribute("Stage", stage)
	pcall(function()
		local handle = CloudUI.PetViewport(view, def, UDim2.new(1, 0, 1, 0), { Spin = "sway", Detail = "Low", ZIndex = 2, Evolved = stage > 0 and stage or nil })
		table.insert(handles, handle)
	end)
	if stage > 0 then
		local badge = makeText(card, "StageBadge", (stage >= 2) and "EVO II" or "EVO I", "Button", 18, WHITE, {
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Darken(GOLD, 0.35),
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(62, 22),
			ZIndex = 4,
		})
		corner(badge, 8)
	end
	makeText(card, "PetName", tostring(def.DisplayName or def.Name or entry.Key), "Body", 18, WHITE, {
		Position = UDim2.fromOffset(4, 58),
		Size = UDim2.new(1, -8, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	local row = makeFrame(card, "Row", { Position = UDim2.fromOffset(4, 82), Size = UDim2.new(1, -8, 0, 26), ZIndex = 3 })
	listLayout(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	autoText(row, "Level", "Lv " .. tostring(entry.Level or 1), "Heading", 18, WHITE, 1)
	autoText(row, "Power", G.Swords .. " " .. commas(entry.Power), "Heading", 18, C.Power, 2)
	return card
end

-- the start picker tile of `round`
function Ring.startTile(ui, round, order)
	local boss = round > 1
	local tile = {}
	tile.Button = Util.Create("TextButton", {
		Name = "Start" .. round,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		BackgroundColor3 = WHITE,
		LayoutOrder = order,
		Parent = ui.Picker,
	})
	corner(tile.Button, 14)
	tile.Stroke = stroke(tile.Button, NAVY, 3, 0)
	local base = boss and C.Boss or C.Next
	Util.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Theme.Lighten(base, 0.22), Theme.Darken(base, 0.18)),
		Parent = tile.Button,
	})
	makeText(tile.Button, "Caption", boss and (G.Crown .. " BOSS") or "ROUND", "Heading", 18, WHITE, {
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 22),
		ZIndex = 3,
	})
	makeText(tile.Button, "Number", tostring(round), "Display", 30, WHITE, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 3,
	})
	tile.Button.Activated:Connect(function()
		Ring.Start = round
		Ring.Picked = true
		Ring.Refusal = nil
		refreshOpen()
	end)
	CloudUI.Tooltip(tile.Button, function()
		if round <= 1 then
			return "Start a new run at round 1"
		end
		return "Continue from boss round " .. round .. " (you beat it)"
	end)
	ui.Tiles[round] = tile
	return tile
end

function Ring.build()
	local win = newWindow("Ring", "Champion Ring")
	local content = win.Panel.Content
	local ui = { Tiles = {}, Handles = {}, Board = {} }
	win.Ui = ui

	-- side column: the record, the best of this server, how it works
	ui.Side = scroller(content, "Side", {})
	pad(ui.Side, 4, 4, 14, 8)
	listLayout(ui.Side, Enum.FillDirection.Vertical, 10)
	local rec = inset(ui.Side, "Record", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	pad(rec, 14, 8, 14, 10)
	listLayout(rec, Enum.FillDirection.Vertical, 2)
	makeText(rec, "Caption", "Your record", "Heading", 19, MUTED, {
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	ui.BestLabel = makeText(rec, "Best", "", "Display", 34, C.Power, {
		Size = UDim2.new(1, 0, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
	})
	ui.RunsLabel = wrapText(rec, "Runs", "", "Body", 19, WHITE, 3)

	local board = inset(ui.Side, "ServerBest", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	pad(board, 14, 8, 14, 10)
	listLayout(board, Enum.FillDirection.Vertical, 4)
	makeText(board, "Caption", G.Trophy .. " Best in this server", "Heading", 20, WHITE, {
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
	})
	for i = 1, 3 do
		local row = makeFrame(board, "Row" .. i, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1 + i })
		local name = makeText(row, "Name", "", "Body", 19, WHITE, {
			Size = UDim2.new(1, -96, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local round = makeText(row, "Round", "", "Heading", 19, C.Medal[i], {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(96, 28),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		ui.Board[i] = { Row = row, Name = name, Round = round }
	end
	ui.BoardEmpty = wrapText(board, "Empty", "No record yet: be the first!", "Body", 19, MUTED, 9)

	local how = inset(ui.Side, "How", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	pad(how, 14, 8, 14, 10)
	listLayout(how, Enum.FillDirection.Vertical, 4)
	local every = Ring.bossEvery()
	local tokens = math.floor(tonumber(Ring.cfg().BossTokens) or 100)
	wrapText(how, "Text", "Beat the champion, meet a stronger one! Every " .. every .. "th round is a BOSS round (first win: +"
		.. tokens .. " Tokens). A loss ends the run, but every win pays at once."
		.. " Your pets keep their HP from round to round, and a fainted pet sits out the rest of the run.", "Body", 19, WHITE, 1)
	ui.CashNote = wrapText(how, "CashNote", "", "Body", 18, MUTED, 2)

	-- detail: the start picker, the champion, the rewards, the fighters
	ui.Detail = inset(content, "Detail", {})
	ui.DetailScroll = scroller(ui.Detail, "Scroll", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) })
	pad(ui.DetailScroll, 14, 10, 16, 12)
	listLayout(ui.DetailScroll, Enum.FillDirection.Vertical, 10)
	local d = ui.DetailScroll
	makeText(d, "PickTitle", "Start from", "Heading", 20, MUTED, {
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	ui.Picker = makeFrame(d, "Picker", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	ui.PickerLayout = Util.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(104, Ring.TILE_H),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.Picker,
	})

	local champ = inset(d, "Champion", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	pad(champ, 14, 8, 14, 10)
	ui.Champ = champ
	listLayout(champ, Enum.FillDirection.Vertical, 6)
	-- the title row (wide windows also carry the tags in it; narrow ones show them on their own row)
	ui.ChampHead = makeFrame(champ, "Head", { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1 })
	listLayout(ui.ChampHead, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	ui.ChampTitle = autoText(ui.ChampHead, "Title", "", "Title", 26, WHITE, 0)
	ui.ChampTitle.TextXAlignment = Enum.TextXAlignment.Left
	ui.ChampTags = makeFrame(champ, "Tags", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2 })
	listLayout(ui.ChampTags, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local powers = makeFrame(champ, "Powers", { Size = UDim2.new(1, 0, 0, 62), LayoutOrder = 3 })
	makeText(powers, "ChampCaption", "Champion (about)", "Heading", 19, MUTED, {
		Size = UDim2.new(0.5, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	ui.ChampPower = makeText(powers, "ChampValue", "", "Display", 30, C.Power, {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(0.5, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	makeText(powers, "TeamCaption", "Your fighters", "Heading", 19, MUTED, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.5, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	ui.TeamPower = makeText(powers, "TeamValue", "", "Display", 30, WHITE, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 24),
		Size = UDim2.new(0.5, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	ui.Verdict = wrapText(champ, "Verdict", "", "Body", 19, C.GoodText, 4)

	local rewards = inset(d, "Rewards", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
	pad(rewards, 14, 8, 14, 10)
	ui.Rewards = rewards
	listLayout(rewards, Enum.FillDirection.Vertical, 4)
	ui.NextWin = wrapText(rewards, "NextWin", "", "Heading", 22, WHITE, 1)
	ui.RecordLine = wrapText(rewards, "Record", "", "Body", 19, C.Power, 2)

	ui.FightersTitle = makeText(d, "FightersTitle", "Your fighters", "Heading", 20, MUTED, {
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 5,
	})
	ui.Fighters = makeFrame(d, "Fighters", { Size = UDim2.new(1, 0, 0, Ring.CARD_H), LayoutOrder = 6 })
	ui.FighterLayout = Util.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, Ring.CARD_H),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.Fighters,
	})

	-- footer (always in view): why START is off, Edit team, START
	ui.Footer = makeFrame(ui.Detail, "Footer", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -10),
		Size = UDim2.new(1, -28, 0, 56),
	})
	local actions = makeFrame(ui.Footer, "Actions", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 56),
	})
	ui.EditButton = CloudUI.Button({
		Name = "EditTeam",
		Text = "Edit team",
		Size = UDim2.fromOffset(170, 54),
		Style = "Blue",
		TextSize = 22,
		Parent = actions,
		Callback = function()
			openTeamWindow()
		end,
	})
	ui.StartButton = CloudUI.Button({
		Name = "Start",
		Text = "START",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(240, 54),
		Style = "Green",
		TextSize = 24,
		Parent = actions,
		Callback = function()
			safe("start ring", ArenaController.StartRing)
		end,
	})
	ui.Why = makeText(ui.Footer, "Why", "", "Body", 19, C.WarnText, {
		Size = UDim2.new(1, 0, 0, 44),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	})

	win.OnLayout = function(w, h, narrow, short, tall)
		local cw = w - K.INSET_X
		local sideW = narrow and 300 or 340
		local detailW
		if tall then
			-- one column (every docked window): the detail first, the record and the board below it; a landscape
			-- phone's short window shows the detail only (the record is on the Team screen too)
			local sideH = short and 0 or math.min(230, math.floor((h - K.INSET_Y) * 0.3))
			local detailH = h - K.INSET_Y - 20 - (short and 0 or (sideH + 10))
			ui.Side.Visible = not short
			ui.Detail.Position = UDim2.fromOffset(12, 10)
			ui.Detail.Size = UDim2.new(1, -24, 0, detailH)
			ui.Side.Position = UDim2.fromOffset(12, 10 + detailH + 10)
			ui.Side.Size = UDim2.new(1, -24, 0, sideH)
			detailW = cw - 24
		else
			ui.Side.Visible = true
			ui.Side.Position = UDim2.fromOffset(12, 10)
			ui.Side.Size = UDim2.new(0, sideW, 1, -20)
			ui.Detail.Position = UDim2.fromOffset(12 + sideW + 12, 10)
			ui.Detail.Size = UDim2.new(1, -(sideW + 36), 1, -20)
			detailW = cw - sideW - 36
		end
		local inner = detailW - 8 - 30
		local cols = math.max(1, math.min(4, math.floor((inner + 8) / (138 + 8))))
		local cardW = math.min(170, math.floor((inner - (cols - 1) * 8) / cols))
		ui.FighterLayout.CellSize = UDim2.fromOffset(cardW, Ring.CARD_H)
		ui.TagsInline = inner >= 640
		ui.FighterCols = cols
		local tileCols = math.max(3, math.min(8, math.floor((inner + 8) / (96 + 8))))
		local tileW = math.min(112, math.floor((inner - (tileCols - 1) * 8) / tileCols))
		ui.PickerLayout.CellSize = UDim2.fromOffset(tileW, Ring.TILE_H)
		-- a landscape phone's footer keeps 120 px clear of Roblox's jump button: smaller buttons there
		ui.StartButton.Size = UDim2.fromOffset(short and 160 or (inner < 420 and 190 or 240), 54)
		ui.EditButton.Size = UDim2.fromOffset(short and 124 or (inner < 420 and 150 or 170), 54)
		ui.Why.Size = UDim2.new(1, 0, 0, short and 26 or 44)
		ui.WhyH = short and 26 or 44
		-- landscape phones: "Next win" comes right under the picker, and the footer keeps clear of Roblox's jump
		-- button (bottom right corner of the screen)
		ui.Rewards.LayoutOrder = short and 3 or 4
		ui.Champ.LayoutOrder = short and 4 or 3
		ui.FooterInset = short and 120 or 28
	end

	win.Refresh = function()
		Ring.refresh(win, ui)
	end
	win.Live = function()
		Ring.live(win, ui)
	end
	return win
end

function Ring.verdict(mine, champ)
	if champ <= 0 then
		return "", C.GoodText
	end
	if mine <= 0 then
		return "Put pets in your team first!", C.WarnText
	end
	local ratio = mine / champ
	if ratio >= 1.15 then
		return "Your pets look ready: go for it!", C.GoodText
	elseif ratio >= 0.9 then
		return "A close fight: tap SPECIAL when it is ready.", C.WarnText
	end
	return "A strong champion! Feed, train or EVOLVE your pets.", C.BadText
end

function Ring.refresh(win, ui)
	local best, runs = Ring.record()
	local starts = Ring.starts(best)
	local valid = false
	for _, r in ipairs(starts) do
		valid = valid or r == Ring.Start
	end
	if not valid then
		Ring.Start = 1
	end
	local start = Ring.Start
	-- record + the server's best
	ui.BestLabel.Text = best > 0 and ("Best: Round " .. best) or "Best: none yet"
	ui.RunsLabel.Text = best > 0 and (commas(runs) .. (runs == 1 and " run so far" or " runs so far")) or "Win round 1 to set your first record!"
	local board = Ring.board()
	for i, row in ipairs(ui.Board) do
		local entry = board[i]
		row.Row.Visible = entry ~= nil
		if entry then
			local mine = LocalPlayer and entry.Name == LocalPlayer.Name
			row.Name.Text = i .. ". " .. entry.Name .. (mine and " (you)" or "")
			row.Name.TextColor3 = mine and C.GoodText or WHITE
			row.Round.Text = "Round " .. entry.Round
		end
	end
	ui.BoardEmpty.Visible = #board == 0
	-- the start picker (rebuilt when the beaten boss rounds change)
	local sig = table.concat(starts, ",")
	if ui.PickerSig ~= sig then
		ui.PickerSig = sig
		clearChildren(ui.Picker)
		ui.Tiles = {}
		for i, round in ipairs(starts) do
			Ring.startTile(ui, round, i)
		end
	end
	for round, tile in pairs(ui.Tiles) do
		local selected = round == start
		tile.Stroke.Color = selected and GOLD or NAVY
		tile.Stroke.Thickness = selected and 4.5 or 3
	end
	-- the champion of the start round
	local p = Ring.preview(start, best)
	ui.ChampTitle.Text = "Round " .. start .. " champion"
	clearChildren(ui.ChampTags)
	for _, child in ipairs(ui.ChampHead:GetChildren()) do
		if child:IsA("GuiObject") and child ~= ui.ChampTitle then
			child:Destroy()
		end
	end
	local tagParent = ui.TagsInline and ui.ChampHead or ui.ChampTags
	ui.ChampTags.Visible = not ui.TagsInline
	if p.Boss then
		colorPill(tagParent, "Boss", G.Crown .. " BOSS", C.Boss, 18, 1)
	end
	if p.Band ~= "" then
		colorPill(tagParent, "Band", p.Band, Color3.fromRGB(90, 120, 190), 18, 2)
	end
	-- the fighters (cards rebuilt only when they change)
	local fighters, source = Ring.fighters()
	local fsig = source
	for _, e in ipairs(fighters) do
		fsig = fsig .. "|" .. tostring(e.Key) .. ":" .. tostring(e.Level) .. ":" .. tostring(e.Power)
	end
	if ui.FighterSig ~= fsig then
		ui.FighterSig = fsig
		for _, handle in ipairs(ui.Handles) do
			pcall(handle.Destroy)
		end
		ui.Handles = {}
		clearChildren(ui.Fighters)
		for i, e in ipairs(fighters) do
			Ring.fighterCard(ui.Fighters, e, i, ui.Handles)
		end
	end
	local rows = math.max(1, math.ceil(#fighters / math.max(1, ui.FighterCols or 4)))
	ui.Fighters.Size = UDim2.new(1, 0, 0, #fighters > 0 and (rows * Ring.CARD_H + (rows - 1) * 8) or 0)
	local titles = { team = "Your fighters (your battle team)", equipped = "Your fighters (your equipped pets)", best = "Your fighters (your strongest pets)" }
	ui.FightersTitle.Text = #fighters > 0 and titles[source] or "Your fighters: none ready"
	local mine = teamPower(fighters)
	ui.ChampPower.Text = G.Swords .. " " .. commas(p.Power)
	ui.TeamPower.Text = G.Swords .. " " .. commas(mine)
	local ratio = p.Power > 0 and mine / p.Power or 1
	ui.TeamPower.TextColor3 = ratio >= 1 and C.GoodText or (ratio >= 0.9 and C.WarnText or C.BadText)
	local verdict, color = Ring.verdict(mine, p.Power)
	ui.Verdict.Text = verdict
	ui.Verdict.TextColor3 = color
	-- rewards of the next win
	ui.NextWin.Text = "Next win: +" .. Ring.money(p.Cash) .. "  +" .. commas(p.Xp) .. " XP"
	local recordText
	if p.Record then
		recordText = G.Star .. " New record: x" .. tostring(Ring.cfg().RecordMult or 3) .. " Cash!"
		if p.Boss and p.Tokens > 0 then
			recordText = recordText .. "  +" .. commas(p.Tokens) .. " Tokens for the boss"
		end
	else
		recordText = "Beat round " .. (best + 1) .. " for a new record: x" .. tostring(Ring.cfg().RecordMult or 3) .. " Cash!"
	end
	ui.RecordLine.Text = recordText
	ui.CashNote.Text = Ring.income() > 0 and "Each win pays a few seconds of your garden's coins (more every round) and XP to every fighter."
		or "Put pets in your Pet Garden: ring wins pay more when your garden makes coins!"
	Ring.live(win, ui)
end

-- the footer only (4 times a second while the window is open: the walk to the portal, the server's answer)
function Ring.live(_win, ui)
	if Ring.Pending and os.clock() - Ring.PendingAt > 4 then
		Ring.Pending = false
	end
	local fighters = Ring.fighters()
	local why = Ring.why(fighters)
	local start = Ring.Start
	CloudUI.SetDisabled(ui.StartButton, why ~= nil or Ring.Pending)
	if Ring.Pending then
		ui.StartButton.Text = "Starting..."
	else
		ui.StartButton.Text = start > 1 and "CONTINUE" or "START"
	end
	ui.Why.Text = why or ""
	ui.Why.Visible = why ~= nil
	local footerH = why and (60 + (ui.WhyH or 44)) or 56
	ui.Footer.Size = UDim2.new(1, -(ui.FooterInset or 28), 0, footerH)
	ui.DetailScroll.Size = UDim2.new(1, -8, 1, -(footerH + 22))
end

function ArenaController.StartRing()
	local fighters = Ring.fighters()
	local why = Ring.why(fighters)
	if why then
		toast(why, "info")
		return false
	end
	if request("Ring", Ring.Start) then
		Ring.Pending = true
		Ring.PendingAt = os.clock()
		Ring.Refusal = nil
		local win = Win.Ring
		if win and win.Ui then
			Ring.live(win, win.Ui)
		end
		return true
	end
	return false
end

-- a server toast: a ring refusal answers the START just sent (shown in the footer, START works again)
function Ring.onNotify(text)
	if type(text) ~= "string" or S.Open ~= "Ring" then
		return
	end
	for _, prefix in ipairs(Ring.REFUSALS) do
		if text:sub(1, #prefix) == prefix then
			Ring.Pending = false
			Ring.Refusal = text
			Ring.RefusalAt = os.clock()
			local win = Win.Ring
			if win and win.Ui then
				Ring.live(win, win.Ui)
			end
			return
		end
	end
end

-- the safe-zone side toast (contract 3.11): crossing the Battle Arena's edge, never right after a battle's teleport
function Ring.zoneTick()
	if battleId() or inMatch() then
		Ring.BattleAt = os.clock()
	end
	local inside = inArena()
	if inside == nil then
		return
	end
	local was = Ring.LastZone
	Ring.LastZone = inside
	if was == nil or was == inside or os.clock() - Ring.BattleAt < 6 then
		return
	end
	if inside then
		toast(G.Swords .. " Battle Arena: pets can battle here", "info")
	else
		toast(G.Heart .. " Safe zone: no pet battles here", "good")
	end
end

-- the Champion Ring line on the Team screen (MenuController's window "Team"; added from here, it stays below the
-- team sections): "Champion Ring best: Round 12 (9 runs)"
function Ring.teamLine()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local menu = pg and pg:FindFirstChild("NimbusMenu")
	local holder = menu and menu:FindFirstChild("Window_Team", true)
	local top = holder and holder:FindFirstChild("TopBar", true)
	local left = top and top.Parent and top.Parent:FindFirstChild("Left")
	if not left then
		return nil
	end
	local label = left:FindFirstChild("RingRecord")
	if not label then
		label = makeText(left, "RingRecord", "", "Heading", 19, C.Power, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 999,
		})
	end
	local best, runs = Ring.record()
	label.Text = best > 0 and (G.Crown .. " Champion Ring best: Round " .. best .. " (" .. commas(runs) .. (runs == 1 and " run)" or " runs)"))
		or (G.Crown .. " Champion Ring: no record yet (the portal is on the plaza)")
	return label
end

-- the Champion Ring board in the Arena panel's Leaders tab: the best of this server (Portal_Ring's RingBoard) + the
-- player's own record
function Ring.leaderSection(parent, order)
	local box = inset(parent, "RingBoard", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order })
	pad(box, 14, 10, 14, 12)
	listLayout(box, Enum.FillDirection.Vertical, 4)
	wrapText(box, "Title", G.Crown .. " Champion Ring: best in this server", "Heading", 21, WHITE, 1)
	local board = Ring.board()
	for i, entry in ipairs(board) do
		local mine = LocalPlayer and entry.Name == LocalPlayer.Name
		wrapText(box, "Row" .. i, i .. ". " .. entry.Name .. (mine and " (you)" or "") .. ": Round " .. entry.Round,
			"Body", 19, mine and C.GoodText or WHITE, 1 + i)
	end
	if #board == 0 then
		wrapText(box, "Empty", "No ring record in this server yet: be the first!", "Body", 19, MUTED, 2)
	end
	local best = Ring.record()
	wrapText(box, "Mine", best > 0 and ("Your best: Round " .. best .. ". Beat it for triple Cash!")
		or "Press E at the Champion Ring portal on the plaza to set your record.", "Body", 19, C.Power, 9)
	return box
end

-- the Champion Ring numbers the window shows (tests / other controllers)
function ArenaController.RingInfo()
	local best, runs = Ring.record()
	local fighters, source = Ring.fighters()
	return {
		Best = best,
		Runs = runs,
		Start = Ring.Start,
		Starts = Ring.starts(best),
		Board = Ring.board(),
		Fighters = fighters,
		Source = source,
		Preview = Ring.preview(Ring.Start, best),
		Why = Ring.why(fighters),
	}
end

----------------------------------------------------------------------
-- Arena panel: Duels | Boss Raid | Leaders
----------------------------------------------------------------------
local TABS = {
	{ Id = "Duels", Label = G.Swords .. " Duels", Short = "Duels" },
	{ Id = "Raid", Label = G.Skull .. " Boss Raid", Short = "Raid" },
	{ Id = "Leaderboard", Label = G.Trophy .. " Leaders", Short = "Leaders" },
}

local function normalizeTab(tab)
	if type(tab) ~= "string" then
		return nil
	end
	local t = tab:lower()
	if t:find("duel", 1, true) or t:find("pvp", 1, true) or t:find("queue", 1, true) then
		return "Duels"
	elseif t:find("raid", 1, true) or t:find("event", 1, true) or t:find("boss", 1, true) then
		return "Raid"
	elseif t:find("leader", 1, true) or t:find("troph", 1, true) or t:find("rank", 1, true) then
		return "Leaderboard"
	end
	return nil
end

local function leaderboard()
	local list = S.Arena and S.Arena.Leaderboard
	return type(list) == "table" and list or {}
end

local function trophiesOf(userId)
	for _, row in ipairs(leaderboard()) do
		if type(row) == "table" and row.UserId == userId then
			return tonumber(row.Trophies)
		end
	end
	return nil
end

local function bossInfo(bossId)
	local BC = catalog()
	local boss = BC and type(BC.Bosses) == "table" and BC.Bosses[bossId]
	return type(boss) == "table" and boss or nil
end

-- the elements that hit `element` hard (Config.Elements.Strong)
local function countersOf(element)
	local out = {}
	local strong = (Config.Elements and Config.Elements.Strong) or {}
	for _, attacker in ipairs((Config.Elements and Config.Elements.Order) or {}) do
		for _, target in ipairs(strong[attacker] or {}) do
			if target == element then
				out[#out + 1] = attacker
			end
		end
	end
	return out
end

local function raidStatus()
	local raid = S.Arena and S.Arena.Raid
	if type(raid) == "table" and raid.Active ~= false then
		return raid
	end
	return nil
end

local function inRaid()
	local raid = raidStatus()
	local id = battleId()
	return raid ~= nil and id ~= nil and raid.BattleId ~= nil and tostring(raid.BattleId) == id
end

local function buildArena()
	local win = newWindow("Arena", "Battle Arena")
	local content = win.Panel.Content
	local ui = { Pages = {}, TabButtons = {}, Rows = {} }
	win.Ui = ui

	-- tab bar + trophies
	ui.Bar = makeFrame(content, "TabBar", { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 50) })
	local tabRow = makeFrame(ui.Bar, "Tabs", { Size = UDim2.new(1, -180, 1, 0) })
	listLayout(tabRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for i, tab in ipairs(TABS) do
		ui.TabButtons[tab.Id] = CloudUI.Button({
			Name = "Tab_" .. tab.Id,
			Text = tab.Label,
			Size = UDim2.fromOffset(200, 46),
			Style = "Gray",
			TextSize = 22,
			LayoutOrder = i,
			Parent = tabRow,
			Callback = function()
				S.Tab = tab.Id
				refreshOpen()
			end,
		})
	end
	ui.TabRow = tabRow
	local chip = makeFrame(ui.Bar, "Trophies", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INSET,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(0, 48),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	corner(chip, 12)
	stroke(chip, NAVY, 3, 0)
	pad(chip, 12, 0, 14, 0)
	listLayout(chip, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	ui.Trophies = autoText(chip, "Value", G.Trophy .. " 0", "Display", 28, WHITE, 1)
	ui.Chip = chip

	local function page(id)
		local frame = makeFrame(content, "Page_" .. id, { Visible = false })
		ui.Pages[id] = frame
		return frame
	end

	------------------------------------------------------------ Duels
	local duels = page("Duels")
	ui.DuelLeft = scroller(duels, "Left", {})
	pad(ui.DuelLeft, 2, 2, 12, 6)
	listLayout(ui.DuelLeft, Enum.FillDirection.Vertical, 10)
	local quick = inset(ui.DuelLeft, "Quick", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	pad(quick, 14, 10, 14, 14)
	listLayout(quick, Enum.FillDirection.Vertical, 8)
	makeText(quick, "Title", "Quick match", "Title", 26, WHITE, {
		Size = UDim2.new(1, 0, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	wrapText(quick, "Text", "Get paired with a player near your trophies. Both of you stay in the arena: the duel runs on a free ring.", "Body", 19, MUTED, 2)
	ui.QueueStatus = wrapText(quick, "Status", "", "Heading", 20, C.Power, 3)
	local queueRow = makeFrame(quick, "Buttons", { Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 4 })
	ui.QueueButton = CloudUI.Button({
		Name = "Queue",
		Text = "Find a match",
		Size = UDim2.fromOffset(240, 54),
		Style = "Green",
		TextSize = 24,
		Parent = queueRow,
		Callback = function()
			local lobby = S.Lobby
			local queued = lobby and type(lobby.Queue) == "table" and lobby.Queue.Queued == true
			if queued then
				request("Unqueue")
			else
				if inArena() == false then
					toast("Walk into the Battle Arena to duel!", "info")
					return
				end
				request("Queue")
			end
		end,
	})
	local record = inset(ui.DuelLeft, "Record", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	pad(record, 14, 10, 14, 12)
	listLayout(record, Enum.FillDirection.Vertical, 4)
	makeText(record, "Title", "Your record", "Heading", 22, WHITE, {
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	ui.RecordText = wrapText(record, "Lines", "", "Body", 19, WHITE, 2)
	wrapText(record, "Rules", "Win: +" .. "20 " .. G.Trophy .. "   Loss: -10 " .. G.Trophy .. "   Nobody ever loses a pet!", "Body", 18, MUTED, 3)
	ui.RecordRules = record:FindFirstChild("Rules")
	ui.InviteBox = inset(ui.DuelLeft, "Invites", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	pad(ui.InviteBox, 14, 10, 14, 12)
	listLayout(ui.InviteBox, Enum.FillDirection.Vertical, 8)

	ui.Challenge = inset(duels, "Challenge", {})
	ui.ChallengeList = scroller(ui.Challenge, "List", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) })
	pad(ui.ChallengeList, 12, 8, 14, 10)
	listLayout(ui.ChallengeList, Enum.FillDirection.Vertical, 8)

	------------------------------------------------------------ Boss Raid
	local raid = page("Raid")
	ui.RaidScroll = scroller(raid, "Scroll", {})
	pad(ui.RaidScroll, 2, 2, 12, 6)
	listLayout(ui.RaidScroll, Enum.FillDirection.Vertical, 10)
	ui.BossCard = inset(ui.RaidScroll, "Boss", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	pad(ui.BossCard, 16, 10, 16, 14)
	listLayout(ui.BossCard, Enum.FillDirection.Vertical, 8)
	local bossHead = makeFrame(ui.BossCard, "Head", { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
	listLayout(bossHead, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	ui.BossState = colorPill(bossHead, "State", "LIVE", C.Boss, 18, 1)
	ui.BossName = autoText(bossHead, "Name", "", "Title", 30, WHITE, 2)
	ui.BossElement = makeFrame(bossHead, "Element", { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3 })
	listLayout(ui.BossElement, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	ui.BossBlurb = wrapText(ui.BossCard, "Blurb", "", "Body", 19, MUTED, 2)
	local hpTrack = makeFrame(ui.BossCard, "Hp", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(14, 20, 48),
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 3,
	})
	corner(hpTrack, 10)
	stroke(hpTrack, NAVY, 3, 0)
	ui.BossHpFill = makeFrame(hpTrack, "Fill", {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Boss,
		Size = UDim2.new(1, 0, 1, 0),
	})
	corner(ui.BossHpFill, 10)
	Theme.Gradient(ui.BossHpFill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 170, 180), 90)
	ui.BossHpText = makeText(hpTrack, "Text", "", "Heading", 19, WHITE, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 })
	ui.BossLine = wrapText(ui.BossCard, "Line", "", "Heading", 20, WHITE, 4)
	local raidButtons = makeFrame(ui.BossCard, "Buttons", { Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 5 })
	ui.JoinButton = CloudUI.Button({
		Name = "JoinRaid",
		Text = "JOIN RAID",
		Size = UDim2.fromOffset(240, 56),
		Style = "Red",
		TextSize = 26,
		Parent = raidButtons,
		Callback = function()
			if inRaid() then
				request("LeaveRaid")
			else
				if inArena() == false then
					toast("Walk into the Battle Arena to join the raid!", "info")
					return
				end
				request("JoinRaid")
			end
		end,
	})
	ui.JoinWhy = makeText(raidButtons, "Why", "", "Body", 19, C.WarnText, {
		Position = UDim2.fromOffset(256, 0),
		Size = UDim2.new(1, -256, 1, 0),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	ui.NextCard = inset(ui.RaidScroll, "Next", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	pad(ui.NextCard, 16, 10, 16, 12)
	listLayout(ui.NextCard, Enum.FillDirection.Vertical, 4)
	makeText(ui.NextCard, "Title", "Next event", "Heading", 20, MUTED, {
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	ui.NextName = wrapText(ui.NextCard, "Name", "", "Title", 24, WHITE, 2)
	ui.NextClock = makeText(ui.NextCard, "Clock", "--:--", "Display", 36, C.Power, {
		Size = UDim2.new(1, 0, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
	})
	ui.DoubleLine = wrapText(ui.NextCard, "Double", "", "Heading", 20, Theme.Lighten(C.Double, 0.35), 4)

	ui.Tips = inset(ui.RaidScroll, "Tips", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	pad(ui.Tips, 16, 10, 16, 12)
	listLayout(ui.Tips, Enum.FillDirection.Vertical, 6)

	------------------------------------------------------------ Leaders
	local leaders = page("Leaderboard")
	ui.LeaderScroll = scroller(leaders, "Scroll", {})
	pad(ui.LeaderScroll, 2, 2, 12, 6)
	listLayout(ui.LeaderScroll, Enum.FillDirection.Vertical, 8)

	win.OnLayout = function(w, h, narrow, short, tall)
		local cw = w - K.INSET_X
		local barH = tall and 108 or 50
		ui.Bar.Size = UDim2.new(1, -28, 0, barH)
		local tabW = tall and math.floor((cw - 28 - 16) / 3) or (narrow and 180 or 200)
		for _, tab in ipairs(TABS) do
			local button = ui.TabButtons[tab.Id]
			button.Size = UDim2.fromOffset(tabW, 46)
			button.TextSize = tall and 20 or 22
			button.Text = tall and (tab.Short or tab.Label) or tab.Label
		end
		if tall then
			ui.TabRow.Size = UDim2.new(1, 0, 0, 48)
			ui.Chip.AnchorPoint = Vector2.new(0, 0)
			ui.Chip.Position = UDim2.fromOffset(0, 58)
		else
			ui.TabRow.Size = UDim2.new(1, -180, 1, 0)
			ui.Chip.AnchorPoint = Vector2.new(1, 0.5)
			ui.Chip.Position = UDim2.new(1, 0, 0.5, 0)
		end
		local top = 10 + barH + 12
		for _, frame in pairs(ui.Pages) do
			frame.Position = UDim2.fromOffset(14, top)
			frame.Size = UDim2.new(1, -28, 1, -(top + 10))
		end
		ui.RaidScroll.Size = UDim2.new(1, 0, 1, 0)
		ui.LeaderScroll.Size = UDim2.new(1, 0, 1, 0)
		if tall then
			ui.DuelLeft.Position = UDim2.fromOffset(0, 0)
			ui.DuelLeft.Size = UDim2.new(1, 0, 0.58, -6)
			ui.Challenge.Position = UDim2.new(0, 0, 0.58, 6)
			ui.Challenge.Size = UDim2.new(1, 0, 0.42, -6)
		else
			local leftW = math.floor((cw - 28) * 0.48)
			ui.DuelLeft.Position = UDim2.fromOffset(0, 0)
			ui.DuelLeft.Size = UDim2.new(0, leftW, 1, 0)
			ui.Challenge.Position = UDim2.fromOffset(leftW + 12, 0)
			ui.Challenge.Size = UDim2.new(1, -(leftW + 12), 1, 0)
		end
		ui.JoinWhy.Visible = not tall
		ui.BossName.TextSize = tall and 24 or 30
	end

	local function inviteRow(parent, invite, order)
		local row = makeFrame(parent, "Invite" .. order, {
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(60, 40, 90),
			Size = UDim2.new(1, 0, 0, 104),
			LayoutOrder = order,
		})
		corner(row, 12)
		local practice = invite.Practice == true
		stroke(row, practice and C.Practice or C.Arena, 3, 0)
		row:SetAttribute("Practice", practice)
		makeText(row, "Name", G.Swords .. " " .. tostring(invite.FromName or "Someone") .. (practice and " wants a practice duel" or " challenges you!"), "Heading", 20, WHITE, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		if practice then
			-- Phase 5 (4.2): the two teams are far apart in power: the duel is practice (no trophies, no rewards)
			row.Size = UDim2.new(1, 0, 0, 130)
			makeText(row, "PracticeFlag", "Practice duel - no trophies or rewards", "Heading", 18, C.Practice, {
				Position = UDim2.fromOffset(12, 100),
				Size = UDim2.new(1, -24, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
		end
		makeText(row, "Info", G.Trophy .. " " .. commas(invite.Trophies or 0) .. "    " .. G.Swords .. " " .. commas(invite.Power or 0)
			.. "    " .. clock(lobbySeconds(invite.ExpiresIn) or 0), "Body", 19, MUTED, {
			Position = UDim2.fromOffset(12, 34),
			Size = UDim2.new(1, -24, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		CloudUI.Button({
			Name = "Accept",
			Text = "Accept",
			Position = UDim2.fromOffset(12, 60),
			Size = UDim2.fromOffset(140, 40),
			Style = "Green",
			TextSize = 20,
			Parent = row,
			Callback = function()
				request("ChallengeReply", invite.FromUserId, true)
			end,
		})
		CloudUI.Button({
			Name = "Decline",
			Text = "Decline",
			Position = UDim2.fromOffset(160, 60),
			Size = UDim2.fromOffset(140, 40),
			Style = "Gray",
			TextSize = 20,
			Parent = row,
			Callback = function()
				request("ChallengeReply", invite.FromUserId, false)
			end,
		})
		return row
	end

	local function playerRow(player, order, sent)
		local row = makeFrame(ui.ChallengeList, "Player_" .. player.UserId, {
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(34, 50, 100),
			Size = UDim2.new(1, 0, 0, 62),
			LayoutOrder = order,
		})
		corner(row, 12)
		stroke(row, NAVY, 3, 0)
		makeText(row, "Name", player.DisplayName ~= "" and player.DisplayName or player.Name, "Title", 22, WHITE, {
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -190, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local trophies = trophiesOf(player.UserId)
		makeText(row, "Trophies", G.Trophy .. " " .. (trophies and commas(trophies) or "?"), "Heading", 18, C.Power, {
			Position = UDim2.fromOffset(12, 34),
			Size = UDim2.new(1, -190, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		if sent then
			local pill = colorPill(row, "Sent", "Sent " .. clock(lobbySeconds(sent.ExpiresIn) or 0), Color3.fromRGB(110, 118, 146), 18, 0)
			pill.AnchorPoint = Vector2.new(1, 0.5)
			pill.Position = UDim2.new(1, -12, 0.5, 0)
		else
			local button = CloudUI.Button({
				Name = "Challenge",
				Text = "Challenge",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(160, 46),
				Style = "Red",
				TextSize = 21,
				Parent = row,
				Callback = function()
					if inArena() == false then
						toast("Walk into the Battle Arena to duel!", "info")
						return
					end
					request("Challenge", player.UserId)
				end,
			})
			CloudUI.SetDisabled(button, S.Lobby ~= nil and S.Lobby.Sent ~= nil)
		end
		return row
	end

	local function refreshDuels()
		local lobby = S.Lobby or {}
		local queue = type(lobby.Queue) == "table" and lobby.Queue or {}
		if queue.Queued then
			local seconds = (tonumber(queue.Seconds) or 0) + (os.clock() - S.LobbyAt)
			ui.QueueStatus.Text = "Searching... " .. clock(seconds) .. "   (" .. commas(queue.Waiting or 1) .. " in the queue)"
			ui.QueueButton.Text = "Leave queue"
			CloudUI.SetStyle(ui.QueueButton, "Gray")
		else
			local waiting = tonumber(queue.Waiting) or 0
			ui.QueueStatus.Text = waiting > 0 and (commas(waiting) .. " waiting for a match right now") or "Nobody is queued yet: be the first!"
			ui.QueueButton.Text = "Find a match"
			CloudUI.SetStyle(ui.QueueButton, "Green")
		end
		CloudUI.SetDisabled(ui.QueueButton, battleId() ~= nil)
		local b = battleData()
		ui.RecordText.Text = G.Trophy .. " " .. commas(b.Trophies or 0) .. " trophies     " .. commas(b.PvPWins or 0) .. " won " .. G.Bullet .. " "
			.. commas(b.PvPLosses or 0) .. " lost"
		local BC = catalog()
		local rules = BC and type(BC.Trophies) == "table" and BC.Trophies or nil
		if rules and ui.RecordRules then
			ui.RecordRules.Text = "Win: +" .. commas(rules.Win or 0) .. " " .. G.Trophy .. "   Loss: " .. tostring(rules.Loss or 0) .. " "
				.. G.Trophy .. "   Nobody ever loses a pet!"
		end
		-- incoming invites
		clearChildren(ui.InviteBox)
		local invites = type(lobby.Invites) == "table" and lobby.Invites or {}
		ui.InviteBox.Visible = #invites > 0
		if #invites > 0 then
			makeText(ui.InviteBox, "Title", "Challenges for you", "Heading", 22, WHITE, {
				Size = UDim2.new(1, 0, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 0,
			})
			for i, invite in ipairs(invites) do
				if type(invite) == "table" then
					inviteRow(ui.InviteBox, invite, i)
				end
			end
		end
		-- players to challenge
		clearChildren(ui.ChallengeList)
		makeText(ui.ChallengeList, "Title", "Challenge a player", "Title", 26, WHITE, {
			Size = UDim2.new(1, 0, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 0,
		})
		local others = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then
				others[#others + 1] = p
			end
		end
		table.sort(others, function(x, y)
			return (trophiesOf(x.UserId) or 0) > (trophiesOf(y.UserId) or 0)
		end)
		local sent = type(lobby.Sent) == "table" and lobby.Sent or nil
		for i, p in ipairs(others) do
			playerRow(p, i, sent and sent.ToUserId == p.UserId and sent or nil)
		end
		if #others == 0 then
			wrapText(ui.ChallengeList, "Empty", "Nobody else is in this server yet. Invite a friend, or try the Dungeon meanwhile!", "Body", 19, MUTED, 1)
		end
	end

	local function tierLine(parent, tier, order)
		local row = makeFrame(parent, "Tier_" .. tostring(tier.Id), {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
		})
		listLayout(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
		local colors = { Gold = C.Medal[1], Silver = Color3.fromRGB(150, 164, 190), Bronze = C.Medal[3], Helper = Color3.fromRGB(90, 120, 190) }
		colorPill(row, "Name", tostring(tier.Id), colors[tier.Id] or Color3.fromRGB(90, 120, 190), 18, 1)
		local share = math.floor((tonumber(tier.MinShare) or 0) * 100 + 0.5)
		local text = (share > 0 and (share .. "%+ damage: ") or "Any damage: ") .. G.Cloud .. " " .. commas(tier.Tokens or 0)
		if (tonumber(tier.Gems) or 0) > 0 then
			text = text .. ", " .. math.floor((tonumber(tier.GemChance) or 0) * 100 + 0.5) .. "% for " .. G.Gem .. " " .. commas(tier.Gems)
		end
		makeText(row, "Text", text, "Body", 19, WHITE, {
			Size = UDim2.new(1, -96, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		})
	end

	local function refreshRaid()
		local raid = raidStatus()
		local nextEvent = S.Arena and type(S.Arena.Next) == "table" and S.Arena.Next or nil
		local bossId = raid and raid.BossId or (nextEvent and nextEvent.BossId)
		local boss = bossInfo(bossId)
		local element = boss and boss.Element
		if ui.BossElementSig ~= tostring(element) then
			ui.BossElementSig = tostring(element)
			clearChildren(ui.BossElement)
			if element then
				elementPill(ui.BossElement, element, 18, 1)
			end
		end
		ui.BossName.Text = (raid and raid.Name) or (boss and boss.Name) or (nextEvent and nextEvent.Name) or "Boss Raid"
		ui.BossBlurb.Text = boss and tostring(boss.Blurb or "") or "A giant boss appears on the colosseum floor. Everyone in the arena can fight it together!"
		local hpVisible = false
		if raid then
			local maxHp = tonumber(raid.MaxHp) or 0
			local hp = tonumber(raid.Hp) or 0
			if raid.Waiting or maxHp <= 0 then
				ui.BossState.Text = "OPEN"
				ui.BossState.BackgroundColor3 = Color3.fromRGB(226, 160, 54)
				ui.BossLine.Text = "Waiting for the first fighter! Join closes in " .. clock(arenaSeconds(raid.JoinEndsIn) or 0)
			else
				hpVisible = true
				ui.BossState.Text = raid.Enraged and "ENRAGED" or "LIVE"
				ui.BossState.BackgroundColor3 = C.Boss
				ui.BossHpFill.Size = UDim2.new(Util.Clamp(hp / maxHp, 0, 1), 0, 1, 0)
				ui.BossHpText.Text = commas(hp) .. " / " .. commas(maxHp)
				local line = commas(raid.Players or 0) .. " fighting " .. G.Bullet .. " " .. clock(arenaSeconds(raid.EndsIn) or 0) .. " left"
				if raid.Joinable then
					line = line .. " " .. G.Bullet .. " join closes in " .. clock(arenaSeconds(raid.JoinEndsIn) or 0)
				end
				ui.BossLine.Text = line
			end
		else
			ui.BossState.Text = "SOON"
			ui.BossState.BackgroundColor3 = Color3.fromRGB(90, 120, 190)
			local starts = nextEvent and nextEvent.Kind == "BossRaid" and arenaSeconds(nextEvent.StartsIn) or nil
			ui.BossLine.Text = starts and ("Starts in " .. clock(starts) .. ". Be in the arena with your team!") or "No raid running right now."
		end
		ui.BossHpFill.Parent.Visible = hpVisible
		-- join / leave
		local why = nil
		local canJoin = raid ~= nil and (raid.Joinable == true or raid.Waiting == true)
		if inRaid() then
			ui.JoinButton.Text = "LEAVE RAID"
			CloudUI.SetStyle(ui.JoinButton, "Gray")
		else
			ui.JoinButton.Text = "JOIN RAID"
			CloudUI.SetStyle(ui.JoinButton, "Red")
			if not raid then
				why = "Raids start every " .. ((catalog() and catalog().Events and catalog().Events.Schedule and catalog().Events.Schedule[1]
					and catalog().Events.Schedule[1].EveryMinutes) or 20) .. " minutes."
			elseif not canJoin then
				why = "The join window has closed. Watch from the stands!"
			elseif battleId() then
				why = "Finish your current battle first."
			elseif #activeTeam() == 0 then
				why = "Pick your battle team first."
			elseif inArena() == false then
				why = "Walk into the Battle Arena to join."
			end
		end
		CloudUI.SetDisabled(ui.JoinButton, why ~= nil and not inRaid())
		ui.JoinWhy.Text = why or ""
		-- next event + double rewards
		if nextEvent then
			ui.NextClock.Text = clock(arenaSeconds(nextEvent.StartsIn) or 0)
			local kind = nextEvent.Kind == "DoubleRewards" and "Double Rewards hour" or "Boss Raid"
			ui.NextName.Text = kind .. ((nextEvent.Name and nextEvent.Kind ~= "DoubleRewards") and (": " .. tostring(nextEvent.Name)) or "")
		else
			ui.NextClock.Text = "--:--"
			ui.NextName.Text = "Nothing scheduled"
		end
		local double = S.Arena and type(S.Arena.Double) == "table" and S.Arena.Double or nil
		if double and double.Active then
			ui.DoubleLine.Text = G.Double .. "2 Double Rewards for " .. clock(arenaSeconds(double.EndsIn) or 0) .. ": every battle pays twice the tokens!"
			ui.DoubleLine.Visible = true
		else
			ui.DoubleLine.Visible = false
		end
		-- tips: elements that beat the boss + the reward tiers
		local sig = tostring(bossId)
		if ui.TipsSig ~= sig then
			ui.TipsSig = sig
			clearChildren(ui.Tips)
			makeText(ui.Tips, "Title", "How to win", "Heading", 22, WHITE, {
				Size = UDim2.new(1, 0, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			})
			if element then
				local counters = countersOf(element)
				if #counters > 0 then
					wrapText(ui.Tips, "CountersText", "Bring these pets: they hit " .. tostring(element) .. " hard.", "Body", 19, WHITE, 2)
					local row = makeFrame(ui.Tips, "Counters", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2 })
					row.LayoutOrder = 3
					listLayout(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
					for i, e in ipairs(counters) do
						elementPill(row, e, 18, i)
					end
				end
			end
			wrapText(ui.Tips, "Retreat", "Glowing circles and lines on the floor mean a big hit is coming: press RETREAT to get your pets out!", "Body", 19, MUTED, 4)
			local BC = catalog()
			local tiers = BC and BC.Raid and BC.Raid.Tiers
			if type(tiers) == "table" then
				makeText(ui.Tips, "TiersTitle", "Rewards by damage dealt", "Heading", 20, WHITE, {
					Size = UDim2.new(1, 0, 0, 26),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 5,
				})
				for i, tier in ipairs(tiers) do
					tierLine(ui.Tips, tier, 5 + i)
				end
			end
		end
	end

	local function refreshLeaders()
		clearChildren(ui.LeaderScroll)
		makeText(ui.LeaderScroll, "Title", "Trophy leaders in this server", "Title", 26, WHITE, {
			Size = UDim2.new(1, 0, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 0,
		})
		local list = leaderboard()
		local meShown = false
		for i, row in ipairs(list) do
			if i > 10 then
				break
			end
			if type(row) == "table" then
				local me = LocalPlayer and row.UserId == LocalPlayer.UserId
				meShown = meShown or me
				local frame = makeFrame(ui.LeaderScroll, "Rank" .. i, {
					BackgroundTransparency = 0,
					BackgroundColor3 = me and C.Me or Color3.fromRGB(34, 50, 100),
					Size = UDim2.new(1, 0, 0, 54),
					LayoutOrder = i,
				})
				corner(frame, 12)
				stroke(frame, me and GOLD or NAVY, me and 3.5 or 3, 0)
				local medal = makeFrame(frame, "Medal", {
					BackgroundTransparency = 0,
					BackgroundColor3 = C.Medal[i] or Color3.fromRGB(70, 90, 150),
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 10, 0.5, 0),
					Size = UDim2.fromOffset(40, 40),
				})
				round(medal)
				stroke(medal, NAVY, 2.5, 0)
				makeText(medal, "Rank", tostring(i), "Display", 24, WHITE, { Size = UDim2.new(1, 0, 1, 0) })
				makeText(frame, "Name", tostring(row.Name or "?") .. (me and "  (you)" or ""), "Title", 23, me and Theme.Lighten(GOLD, 0.35) or WHITE, {
					Position = UDim2.fromOffset(62, 0),
					Size = UDim2.new(1, -220, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				})
				makeText(frame, "Trophies", G.Trophy .. " " .. commas(row.Trophies or 0), "Display", 26, C.Power, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -14, 0, 0),
					Size = UDim2.new(0, 160, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Right,
				})
			end
		end
		if #list == 0 then
			wrapText(ui.LeaderScroll, "Empty", "The leaderboard fills up as soon as the arena reports in.", "Body", 19, MUTED, 1)
		end
		if not meShown and LocalPlayer then
			wrapText(ui.LeaderScroll, "Mine", "You: " .. G.Trophy .. " " .. commas(battleData().Trophies or 0) .. " trophies. Win duels to climb the board!", "Heading", 20, C.Power, 20)
		end
		Ring.leaderSection(ui.LeaderScroll, 25)
		local BC = catalog()
		local rules = BC and type(BC.Trophies) == "table" and BC.Trophies or { Win = 20, Loss = -10 }
		local note = inset(ui.LeaderScroll, "HowTo", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 30 })
		pad(note, 14, 10, 14, 12)
		listLayout(note, Enum.FillDirection.Vertical, 4)
		wrapText(note, "Title", "How trophies work", "Heading", 20, WHITE, 1)
		wrapText(note, "Text", "Win a duel: +" .. commas(rules.Win or 20) .. " " .. G.Trophy .. "   Lose one: " .. tostring(rules.Loss or -10) .. " "
			.. G.Trophy .. " (never below 0). Duel on the rings in front of the colosseum, or join the quick queue!", "Body", 19, MUTED, 2)
	end

	win.Refresh = function()
		local tab = S.Tab
		if not ui.Pages[tab] then
			tab = "Duels"
			S.Tab = tab
		end
		for id, frame in pairs(ui.Pages) do
			frame.Visible = id == tab
		end
		for id, button in pairs(ui.TabButtons) do
			CloudUI.SetStyle(button, id == tab and "Red" or "Gray")
		end
		ui.Trophies.Text = G.Trophy .. " " .. commas(battleData().Trophies or 0)
		if tab == "Duels" then
			refreshDuels()
		elseif tab == "Raid" then
			refreshRaid()
		else
			refreshLeaders()
		end
	end
	-- the live numbers (countdowns) without rebuilding the lists
	win.Live = function()
		if S.Tab == "Raid" then
			refreshRaid()
		elseif S.Tab == "Duels" then
			local lobby = S.Lobby or {}
			local queue = type(lobby.Queue) == "table" and lobby.Queue or {}
			if queue.Queued then
				local seconds = (tonumber(queue.Seconds) or 0) + (os.clock() - S.LobbyAt)
				ui.QueueStatus.Text = "Searching... " .. clock(seconds) .. "   (" .. commas(queue.Waiting or 1) .. " in the queue)"
			end
		end
	end
	return win
end

----------------------------------------------------------------------
-- Side cards (right edge): duel invites, the sent invite, the queue, the raid join card, the event countdown
----------------------------------------------------------------------
local function sideCard(name, accent, order)
	local card = makeFrame(U.Side, name, {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(28, 36, 78),
		Size = UDim2.fromOffset(K.SIDE_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
	})
	corner(card, 14)
	stroke(card, NAVY, 3.5, 0)
	pad(card, 22, 8, 12, 10)
	-- the accent stripe sits in the left padding (the body below holds the card's list)
	local bar = makeFrame(card, "Accent", {
		BackgroundTransparency = 0,
		BackgroundColor3 = accent,
		Position = UDim2.new(0, -14, 0, 0),
		Size = UDim2.new(0, 6, 1, 0),
	})
	round(bar)
	local body = makeFrame(card, "Body", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	listLayout(body, Enum.FillDirection.Vertical, 4)
	return body
end

local function buildSide()
	local gui = CloudUI.NewScreenGui("NimbusArenaSide", K.SIDE_ORDER)
	U.SideGui = gui
	U.Side = makeFrame(gui, "SideStack", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -K.SIDE_BOTTOM),
		Size = UDim2.fromOffset(K.SIDE_W, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	U.SideScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = U.Side })
	listLayout(U.Side, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	U.SideCards = {}
end

local function relayoutSide()
	if not U.Side then
		return
	end
	local factor = screenFactor()
	U.SideScale.Scale = factor
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local area = guiArea()
	local bottom = (touch and K.SIDE_BOTTOM_TOUCH or K.SIDE_BOTTOM) * factor
	if area.X < area.Y then
		bottom = K.SIDE_BOTTOM_PORTRAIT * factor
	end
	U.Side.Position = UDim2.new(1, -12, 1, -math.floor(bottom + 0.5))
end

-- true while a menu window, the Pet Index or the Fusion window covers the screen (the side cards step back)
local function otherWindowOpen()
	for _, name in ipairs({ "MenuController", "IndexController", "FusionController", "CareController", "DungeonController", "ObbyController" }) do
		local mod = otherController(name)
		if mod and type(mod.IsOpen) == "function" then
			local ok, open = pcall(mod.IsOpen)
			if ok and open == true then
				return true
			end
		end
	end
	return false
end

-- rebuilds the side cards (cheap: a handful of frames, only when something changed; the clocks tick in place)
local function sideSignature()
	local parts = {}
	local lobby = S.Lobby or {}
	for _, inv in ipairs(type(lobby.Invites) == "table" and lobby.Invites or {}) do
		if type(inv) == "table" then
			parts[#parts + 1] = "i" .. tostring(inv.FromUserId)
		end
	end
	if type(lobby.Sent) == "table" then
		parts[#parts + 1] = "s" .. tostring(lobby.Sent.ToUserId)
	end
	if type(lobby.Queue) == "table" and lobby.Queue.Queued then
		parts[#parts + 1] = "q"
	end
	local raid = raidStatus()
	if raid and (raid.Joinable or raid.Waiting) and not inRaid() then
		parts[#parts + 1] = "r" .. tostring(raid.BossId) .. tostring(inArena())
	end
	local nextEvent = S.Arena and type(S.Arena.Next) == "table" and S.Arena.Next or nil
	local starts = nextEvent and arenaSeconds(nextEvent.StartsIn)
	if starts and starts <= K.ANNOUNCE and starts > 0 then
		parts[#parts + 1] = "n" .. tostring(nextEvent.Kind)
	end
	local double = S.Arena and type(S.Arena.Double) == "table" and S.Arena.Double
	if double and double.Active then
		parts[#parts + 1] = "d"
	end
	local area = guiArea()
	parts[#parts + 1] = tostring(area.Y < 500 or area.X < area.Y)
	return table.concat(parts, ",")
end

function refreshSide()
	if not U.Side then
		return
	end
	local hidden = inMatch() or battleId() ~= nil or S.Open ~= nil or otherWindowOpen()
	U.Side.Visible = not hidden
	if hidden then
		return
	end
	local sig = sideSignature()
	if sig ~= S.SideSig then
		S.SideSig = sig
		clearChildren(U.Side)
		U.SideCards = {}
		local area = guiArea()
		local maxCards = (area.Y < 500 or area.X < area.Y) and K.SIDE_MAX_CARDS_SHORT or K.SIDE_MAX_CARDS
		local count = 0
		local lobby = S.Lobby or {}
		-- 1. duel invites (most urgent first)
		for i, invite in ipairs(type(lobby.Invites) == "table" and lobby.Invites or {}) do
			if type(invite) == "table" and count < maxCards then
				count = count + 1
				local practice = invite.Practice == true
				local card = sideCard("Invite" .. i, practice and C.Practice or C.Arena, 10 + i)
				card.Parent:SetAttribute("Practice", practice)
				makeText(card, "Title", G.Swords .. (practice and " Practice duel" or " Duel challenge!"), "Heading", 21, practice and C.Practice or Theme.Lighten(C.Arena, 0.4), {
					Size = UDim2.new(1, 0, 0, 28),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 1,
				})
				if practice then
					-- Phase 5 (4.2): a challenge more than Duel.PracticeInvite apart in TeamPower
					makeText(card, "PracticeFlag", "No trophies or rewards", "Body", 18, C.Practice, {
						Size = UDim2.new(1, 0, 0, 22),
						TextXAlignment = Enum.TextXAlignment.Left,
						LayoutOrder = 2,
					})
				end
				makeText(card, "Name", tostring(invite.FromName or "Someone") .. " wants to battle", "Body", 19, WHITE, {
					Size = UDim2.new(1, 0, 0, 24),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = 2,
				})
				local info = makeText(card, "Info", "", "Heading", 18, C.Power, {
					Size = UDim2.new(1, 0, 0, 24),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 3,
				})
				local buttons = makeFrame(card, "Buttons", { Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 4 })
				CloudUI.Button({
					Name = "Accept",
					Text = "Accept",
					Size = UDim2.new(0.5, -4, 0, 44),
					Style = "Green",
					TextSize = 21,
					Parent = buttons,
					Callback = function()
						request("ChallengeReply", invite.FromUserId, true)
					end,
				})
				CloudUI.Button({
					Name = "Decline",
					Text = "Decline",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.new(0.5, -4, 0, 44),
					Style = "Gray",
					TextSize = 21,
					Parent = buttons,
					Callback = function()
						request("ChallengeReply", invite.FromUserId, false)
					end,
				})
				local track = makeFrame(card, "Timer", {
					BackgroundTransparency = 0,
					BackgroundColor3 = Color3.fromRGB(14, 20, 48),
					Size = UDim2.new(1, 0, 0, 6),
					LayoutOrder = 5,
				})
				round(track)
				local fill = makeFrame(track, "Fill", { BackgroundTransparency = 0, BackgroundColor3 = C.Arena, Size = UDim2.new(1, 0, 1, 0) })
				round(fill)
				local total = math.max(1, tonumber(invite.ExpiresIn) or 30)
				table.insert(U.SideCards, function()
					local left = lobbySeconds(invite.ExpiresIn) or 0
					info.Text = G.Trophy .. " " .. commas(invite.Trophies or 0) .. "   " .. G.Swords .. " " .. commas(invite.Power or 0) .. "   " .. G.Clock .. " " .. clock(left)
					fill.Size = UDim2.new(Util.Clamp(left / total, 0, 1), 0, 1, 0)
				end)
			end
		end
		-- 2. the invite I sent
		if type(lobby.Sent) == "table" and count < maxCards then
			count = count + 1
			local sent = lobby.Sent
			local card = sideCard("Sent", Color3.fromRGB(110, 118, 146), 20)
			local text = makeText(card, "Text", "", "Body", 19, WHITE, {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			})
			table.insert(U.SideCards, function()
				text.Text = G.Swords .. " Waiting for " .. tostring(sent.ToName or "them") .. " to accept... " .. clock(lobbySeconds(sent.ExpiresIn) or 0)
			end)
		end
		-- 3. the quick queue
		if type(lobby.Queue) == "table" and lobby.Queue.Queued and count < maxCards then
			count = count + 1
			local queue = lobby.Queue
			local card = sideCard("Queue", C.Next, 30)
			local row = makeFrame(card, "Row", { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1 })
			local text = makeText(row, "Text", "", "Body", 20, WHITE, {
				Size = UDim2.new(1, -112, 1, 0),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			CloudUI.Button({
				Name = "Leave",
				Text = "Leave",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.fromOffset(104, 42),
				Style = "Gray",
				TextSize = 20,
				Parent = row,
				Callback = function()
					request("Unqueue")
				end,
			})
			table.insert(U.SideCards, function()
				local seconds = (tonumber(queue.Seconds) or 0) + (os.clock() - S.LobbyAt)
				text.Text = "Finding a duel... " .. clock(seconds)
			end)
		end
		-- 4. the raid join card
		local raid = raidStatus()
		if raid and (raid.Joinable or raid.Waiting) and not inRaid() and count < maxCards then
			count = count + 1
			local card = sideCard("Raid", C.Boss, 40)
			makeText(card, "Title", G.Skull .. " BOSS RAID: " .. tostring(raid.Name or (bossInfo(raid.BossId) or {}).Name or "Boss"), "Heading", 21, Theme.Lighten(C.Boss, 0.45), {
				Size = UDim2.new(1, 0, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			})
			local line = makeText(card, "Line", "", "Body", 19, WHITE, {
				Size = UDim2.new(1, 0, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
			})
			local here = inArena()
			if here == false then
				makeText(card, "Where", "Head to the Battle Arena to join!", "Body", 19, C.WarnText, {
					Size = UDim2.new(1, 0, 0, 24),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 3,
				})
			else
				local buttons = makeFrame(card, "Buttons", { Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 3 })
				CloudUI.Button({
					Name = "Join",
					Text = "JOIN RAID",
					Size = UDim2.new(0.62, -4, 0, 44),
					Style = "Red",
					TextSize = 21,
					Parent = buttons,
					Callback = function()
						request("JoinRaid")
					end,
				})
				CloudUI.Button({
					Name = "Info",
					Text = "Info",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.new(0.38, -4, 0, 44),
					Style = "Blue",
					TextSize = 21,
					Parent = buttons,
					Callback = function()
						ArenaController.OpenArena("Raid")
					end,
				})
			end
			table.insert(U.SideCards, function()
				local r = raidStatus() or raid
				line.Text = commas(r.Players or 0) .. " fighting " .. G.Bullet .. " join closes in " .. clock(arenaSeconds(r.JoinEndsIn) or 0)
			end)
		end
		-- 5. the event countdown chip (always last: closest to the hotbar corner)
		local nextEvent = S.Arena and type(S.Arena.Next) == "table" and S.Arena.Next or nil
		local starts = nextEvent and arenaSeconds(nextEvent.StartsIn)
		local double = S.Arena and type(S.Arena.Double) == "table" and S.Arena.Double
		local showNext = starts and starts <= K.ANNOUNCE and starts > 0
		if showNext or (double and double.Active) then
			local chip = makeFrame(U.Side, "Countdown", {
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(28, 36, 78),
				Size = UDim2.fromOffset(0, 46),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = 90,
			})
			corner(chip, 23)
			stroke(chip, GOLD, 3, 0)
			pad(chip, 14, 0, 16, 0)
			listLayout(chip, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
			local label = autoText(chip, "Text", "", "Heading", 20, WHITE, 1)
			local clockLabel = autoText(chip, "Clock", "", "Display", 26, C.Power, 2)
			table.insert(U.SideCards, function()
				local s2 = nextEvent and arenaSeconds(nextEvent.StartsIn)
				if s2 and s2 <= K.ANNOUNCE and s2 > 0 then
					label.Text = (nextEvent.Kind == "DoubleRewards" and (G.Double .. "2 Rewards in") or (G.Skull .. " Boss Raid in"))
					clockLabel.Text = clock(s2)
				elseif double and double.Active then
					label.Text = G.Double .. "2 Rewards"
					clockLabel.Text = clock(arenaSeconds(double.EndsIn) or 0)
				end
			end)
		end
	end
	for _, tick in ipairs(U.SideCards) do
		pcall(tick)
	end
end

----------------------------------------------------------------------
-- Opening / closing
----------------------------------------------------------------------
local function onBackAction(_name, inputState)
	if inputState == Enum.UserInputState.Begin and S.Open then
		ArenaController.Close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function syncBackBinding()
	local want = S.Open ~= nil
	if want == S.BackBound then
		return
	end
	S.BackBound = want
	if want then
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, onBackAction, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
	else
		task.defer(function()
			if not S.BackBound then
				pcall(function()
					ContextActionService:UnbindAction(K.BACK_ACTION)
				end)
			end
		end)
	end
end

local function closeOthers()
	for _, name in ipairs({ "MenuController", "IndexController", "FusionController", "CareController", "DungeonController", "ObbyController" }) do
		local mod = otherController(name)
		if mod and type(mod.Close) == "function" then
			pcall(mod.Close)
		end
	end
end

function refreshOpen()
	local win = S.Open and Win[S.Open]
	if win and win.Refresh then
		safe("refresh " .. S.Open, win.Refresh)
	end
	refreshSide()
end

local function ensureWindow(id)
	if S.Built[id] then
		return Win[id]
	end
	S.Built[id] = true
	local ok, result
	if id == "Ring" then
		ok, result = pcall(Ring.build)
	else
		ok, result = pcall(buildArena)
	end
	if not ok then
		warnOnce("build " .. id, result)
		return nil
	end
	return result
end

local function open(id)
	if not initialized then
		ArenaController.Init()
	end
	if not U.Gui or inMatch() then
		return false
	end
	local win = ensureWindow(id)
	if not win then
		return false
	end
	local was = S.Open
	if was and was ~= id and Win[was] then
		Win[was].Holder.Visible = false
	end
	if not was then
		closeOthers()
	end
	S.Open = id
	S.Token = S.Token + 1
	syncBackBinding()
	win.W = nil -- re-run the layout for the current screen
	layoutWindow(win)
	win.Holder.Visible = true
	if was ~= id then
		win.Pop.Scale = 0.86
		tween(win.Pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	refreshOpen()
	if was ~= id then
		ArenaController.Opened:Fire(id)
	end
	return true
end

function ArenaController.OpenArena(tab)
	S.Tab = normalizeTab(tab) or S.Tab or "Duels"
	return open("Arena")
end

function ArenaController.OpenRing(start, portal)
	local n = tonumber(start)
	if n then
		Ring.Start = math.floor(n)
	elseif S.Open ~= "Ring" then
		local best = Ring.record()
		local starts = Ring.starts(best)
		local keep = false
		for _, r in ipairs(starts) do
			keep = keep or (Ring.Picked and r == Ring.Start)
		end
		if not keep then
			Ring.Start = starts[#starts] -- the latest beaten boss round, else round 1 (a round the kid picked stays)
		end
	end
	Ring.Refusal = nil
	Ring.Pending = false
	S.RingAt = (typeof(portal) == "Instance") and portal or nil
	return open("Ring")
end

function ArenaController.Close()
	if not S.Open then
		return
	end
	local id = S.Open
	local win = Win[id]
	S.Open = nil
	S.RingAt = nil
	Ring.Pending = false
	S.Token = S.Token + 1
	local mine = S.Token
	syncBackBinding()
	if win then
		tween(win.Pop, 0.12, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.13, function()
			if S.Token == mine and S.Open ~= id and win.Holder then
				win.Holder.Visible = false
			end
		end)
	end
	avoidRight(nil)
	refreshSide()
	ArenaController.Closed:Fire(id)
end

function ArenaController.IsOpen()
	return S.Open ~= nil
end

function ArenaController.GetState()
	return { Arena = S.Arena, Lobby = S.Lobby, Window = S.Open, Tab = S.Tab, RingStart = Ring.Start }
end

function ArenaController.Request(action, a, b)
	return request(action, a, b)
end

----------------------------------------------------------------------
-- Server messages
----------------------------------------------------------------------
local function onArenaState(state)
	if type(state) ~= "table" then
		return
	end
	S.Arena = state
	S.ArenaAt = os.clock()
	if S.Open == "Arena" then
		refreshOpen()
	else
		refreshSide()
	end
end

local function onBattleState(kind, payload)
	if kind == "Lobby" and type(payload) == "table" then
		S.Lobby = payload
		S.LobbyAt = os.clock()
		if S.Open == "Arena" and S.Tab == "Duels" then
			refreshOpen()
		else
			refreshSide()
		end
	elseif kind == "Start" and type(payload) == "table" and payload.Spectator ~= true and (payload.Side or 1) ~= 0 then
		-- my battle began: the windows step aside
		Ring.Pending = false
		ArenaController.Close()
	elseif kind == "End" and type(payload) == "table" and payload.Spectator ~= true then
		task.delay(0.5, refreshSide)
	end
end

local function onPromptTriggered(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then
		return
	end
	local panel = prompt:GetAttribute("OpenPanel")
	if panel == "Ring" or prompt:GetAttribute("OpenPanelTab") == "Ring" then
		-- Portal_Ring's RingPrompt
		ArenaController.OpenRing(nil, prompt.Parent)
	elseif panel == "Dungeon" then
		-- Phase 5 (5.3): Portal_Dungeon's DungeonPrompt is handed to DungeonController (the Dungeon side panel)
		local dungeon = otherController("DungeonController")
		if dungeon and type(dungeon.Open) == "function" then
			ArenaController.Close()
			dungeon.Open(nil, prompt.Parent)
		end
	elseif panel == "Arena" then
		local tab = prompt:GetAttribute("OpenPanelTab")
		if tab == nil and prompt:GetAttribute("RingIndex") ~= nil then
			tab = "Duels"
		end
		ArenaController.OpenArena(tab)
	end
end

local function connectOthers()
	local function hook(name, signalName)
		local mod = otherController(name)
		local signal = mod and mod[signalName]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function(windowId)
				if windowId ~= nil and (windowId == "Arena" or windowId == "Ring") then
					return
				end
				ArenaController.Close()
				if name == "MenuController" and windowId == "Team" then
					-- the Champion Ring record line on the Team screen (after its first layout)
					task.defer(function()
						safe("team line", Ring.teamLine)
					end)
				end
			end)
		end
	end
	hook("MenuController", "WindowOpened")
	hook("IndexController", "Opened")
	hook("FusionController", "Opened")
	hook("CareController", "Opened")
	hook("DungeonController", "Opened")
	hook("ObbyController", "Opened")
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function ArenaController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)

	local gui = CloudUI.NewScreenGui("NimbusArena", K.DISPLAY_ORDER)
	U.Gui = gui
	buildSide()
	relayoutSide()
	-- the hint (right edge, a third down: clear of the toasts at the top and the side cards at the bottom)
	U.HintGui = gui
	U.HintFrame = makeFrame(gui, "Hint", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(28, 36, 78),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.36, 0),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		ZIndex = 20,
	})
	corner(U.HintFrame, 12)
	stroke(U.HintFrame, GOLD, 3, 0)
	pad(U.HintFrame, 14, 8, 14, 8)
	U.HintScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = U.HintFrame })
	U.HintLabel = makeText(U.HintFrame, "Text", "", "Heading", 20, WHITE, {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 21,
	})

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		safe("relayout", function()
			relayoutSide()
			S.SideSig = nil
			if S.Open and Win[S.Open] then
				layoutWindow(Win[S.Open])
				refreshOpen()
			else
				refreshSide()
			end
		end)
	end)
	State.Changed:Connect(function()
		safe("State.Changed", refreshOpen)
		safe("team line", Ring.teamLine)
	end)
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if inMatch() then
				ArenaController.Close()
			end
			safe("InMatch", refreshSide)
		end)
		LocalPlayer:GetAttributeChangedSignal((Config.Attr and Config.Attr.InBattle) or K.ATTR_IN_BATTLE):Connect(function()
			S.SideSig = nil
			safe("InBattle", refreshOpen)
		end)
	end
	Players.PlayerAdded:Connect(function()
		if S.Open == "Arena" and S.Tab == "Duels" then
			safe("players", refreshOpen)
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if S.Open == "Arena" and S.Tab == "Duels" then
			task.defer(function()
				safe("players", refreshOpen)
			end)
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if S.Open and input.KeyCode == Enum.KeyCode.Escape then
			ArenaController.Close()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		safe("prompt", onPromptTriggered, prompt)
	end)

	task.spawn(function()
		local okOpen, openRemote = pcall(Remotes.Get, "OpenPanel")
		if okOpen and openRemote then
			openRemote.OnClientEvent:Connect(function(panelId, args)
				if type(panelId) ~= "string" then
					return
				end
				args = type(args) == "table" and args or {}
				local key = panelId:lower()
				if key == "ring" then
					safe("OpenPanel", ArenaController.OpenRing, args.Start)
				elseif key == "arena" or key == "duels" or key == "raid" or key == "leaderboard" then
					local tab = args.Tab or ((key ~= "arena") and panelId or nil)
					safe("OpenPanel", ArenaController.OpenArena, tab)
				end
			end)
		end
		local okArena, arenaRemote = pcall(Remotes.Get, "ArenaState")
		if okArena and arenaRemote then
			arenaRemote.OnClientEvent:Connect(function(state)
				safe("ArenaState", onArenaState, state)
			end)
		end
		local okNotify, notifyRemote = pcall(Remotes.Get, "Notify")
		if okNotify and notifyRemote then
			notifyRemote.OnClientEvent:Connect(function(text)
				safe("Notify", Ring.onNotify, text)
			end)
		end
		local okBattle, battleRemote = pcall(Remotes.Get, "BattleState")
		if okBattle and battleRemote then
			battleRemote.OnClientEvent:Connect(function(kind, payload)
				safe("BattleState", onBattleState, kind, payload)
			end)
		end
	end)
	task.defer(function()
		safe("hooks", connectOthers)
	end)

	-- one light loop: countdowns, walk-away, the side cards' clocks (4 times a second)
	local nextTick = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextTick then
			return
		end
		nextTick = now + K.TICK
		if S.Open == "Ring" and S.RingAt then
			local d = Ring.distance()
			if d and d > K.WALK_AWAY then
				ArenaController.Close()
				return
			end
		end
		if S.Open == "Arena" and Win.Arena and Win.Arena.Live then
			safe("live", Win.Arena.Live)
		elseif S.Open == "Ring" and Win.Ring and Win.Ring.Live then
			safe("ring live", Win.Ring.Live)
		end
		safe("zone", Ring.zoneTick)
		safe("side", refreshSide)
	end)
end

return ArenaController
