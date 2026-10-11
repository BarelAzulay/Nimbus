-- ArenaController (client, Phase 3, ui): the battle windows and side cards of the Battle Arena (ARCHITECTURE_V3.md
-- "Phase 3: Pet battles", the "Phase 3 build contract" and its "Interfaces between the Phase 3 modules").
--
--   ArenaController.Init()
--   ArenaController.OpenTrials(level|nil)     the Trial window (the Trial Portal's prompt, OpenPanel("Trials", {Level}))
--   ArenaController.OpenArena(tab|nil)        the Arena panel: tab "Duels" | "Raid" | "Leaderboard" (OpenPanel("Arena",
--                                             {Tab}), the duel pads, the event board, the trophy board, the main gate)
--   ArenaController.Close()
--   Extras: ArenaController.IsOpen() -> bool, ArenaController.GetState() -> { Arena = last ArenaState, Lobby = last
--           BattleState "Lobby", Window = "Trials" | "Arena" | nil, Tab, Level }, ArenaController.SelectLevel(n),
--           ArenaController.Opened / Closed (Util.Signal), ArenaController.Request(action, a, b) (sends BattleRequest
--           like the buttons do: client-side spacing, the server validates everything)
--
-- What the player sees
--   * Trial window (Portal_Trials, prompt attribute OpenPanel = "Trials"): the 30 levels of BattleCatalog.Trials in
--     their chapters (locked levels greyed with a lock, cleared ones with a green first-clear check, mini-boss levels
--     with a BOSS tag, the next level to beat highlighted); the selected level's enemy team (pet viewports, levels,
--     element badges), its recommended power against the power of the player's active team (a bar and a verdict),
--     the rewards (per win and the first-clear bonus, or "Cleared"), Edit team (the Team window) and START, which
--     sends BattleRequest("Trial", level). Start is refused here when the level is locked, the team is empty, the
--     player is in a battle or away from the portal (the server checks all of it again).
--   * Arena panel (OpenPanel = "Arena", OpenPanelTab = "Events" | "Leaderboard" | "Raid"; the duel pads carry
--     RingIndex / PadIndex): DUELS (the quick queue: Queue / Unqueue + the wait; challenge a player in the server:
--     Challenge(userId); incoming invites with Accept / Decline; the player's trophies and duel record), BOSS RAID
--     (the running raid: boss, element, HP, fighters, time left, JOIN / LEAVE; the next event with its countdown;
--     Double Rewards; which elements beat the boss; the reward tiers) and LEADERS (ArenaState.Leaderboard, top 10,
--     the player's own row highlighted).
--   * Side cards (right edge, above the hotbar, never in the screen centre; ScreenGui "NimbusArenaSide"): a duel
--     invite (BattleState "Lobby".Invites) with Accept / Decline and a draining timer, the invite the player sent,
--     the quick-queue status with Leave, the raid join card while a raid can be joined (JOIN inside the arena, a
--     "head to the arena" line elsewhere) and the event countdown chip ("Boss Raid in 1:45", "2x Rewards 29:12")
--     while an event is announced or running. Countdowns tick locally between two ArenaState messages. All of it
--     hides in an obby match and while the player fights (attribute InBattle).
-- Remotes: BattleState ("Lobby" in), ArenaState (in), OpenPanel (in), BattleRequest (out: Trial, Challenge,
-- ChallengeReply, Queue, Unqueue, JoinRaid, LeaveRaid). Every request is spaced on the client too (K.FIRE_GAP).
-- One window at a time: opening one closes the menu windows, the Pet Index and the Fusion window, and their opening
-- closes this one. Esc / gamepad B / the red X / a click outside close it; walking away from the Trial Portal
-- closes the Trial window. Readability rule: everything is designed in 1080p pixels (body 19, captions >= 18,
-- buttons 22, titles 26-34) under ONE UIScale (the screen factor, or less to fit), so phones keep >= 14 px.
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
	PREF_W = 1120,
	PREF_H = 720,
	MIN_W = 800,
	MIN_H = 380, -- (a landscape phone's 332 px gui area keeps the 0.8 scale)
	TALL_MIN_W = 420, -- portrait phones: a single column that keeps the 0.8 scale
	TALL_MAX_H = 1100,
	TALL = 760, -- windows narrower than this use the single-column layout
	NARROW = 1000,
	SHORT = 560,
	MARGIN = 12, -- screen px kept free around the window
	BUMPS = 28, -- room for the panel's cloud bumps
	INSET_X = 24, -- the panel frame around Panel.Content (CloudUI.ContentInset)
	INSET_Y = 82,
	FIRE_GAP = 0.5, -- seconds between two sends of the same request
	TRIAL_RANGE = 28, -- studs from the Trial Portal where START works (the server allows 30)
	WALK_AWAY = 70, -- studs from the portal that close a Trial window opened there
	ARENA_SLACK = 12, -- studs around the arena's bounding box that still count as "in the arena"
	LEVEL_TILE = 92,
	LEVEL_TILE_NARROW = 80,
	LEVEL_GAP = 8,
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
	Arena = Color3.fromRGB(214, 92, 96), -- the panels' accent (crimson, like the Trial Portal)
	Trial = Color3.fromRGB(196, 74, 92),
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
	Open = nil, -- "Trials" | "Arena" | nil
	Token = 0,
	Tab = "Duels",
	Level = nil, -- the selected trial level
	Arena = nil, -- last ArenaState
	ArenaAt = 0, -- os.clock() when it arrived
	Lobby = nil, -- last BattleState "Lobby"
	LobbyAt = 0,
	AtPortal = nil, -- the portal part when the Trial window was opened there
	BackBound = false,
	LastFire = {},
	Built = {},
	Tall = false,
	Narrow = false,
	Short = false,
	Warned = {},
	ArenaBox = nil, -- { CFrame, Size } of workspace.BattleArena (static, measured once)
}
local Win = {} -- per-window widget tables: Win.Trials, Win.Arena

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
	return { Trophies = 0, TrialBest = 0, TrialCleared = {}, PvPWins = 0, PvPLosses = 0, Raids = 0 }
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

local function trials()
	local BC = catalog()
	return BC and type(BC.Trials) == "table" and BC.Trials or {}
end

local function trialCount()
	local BC = catalog()
	return (BC and tonumber(BC.TrialCount)) or #trials()
end

local function cleared(level)
	local b = battleData()
	return type(b.TrialCleared) == "table" and b.TrialCleared[level] == true
end

local function bestLevel()
	local b = battleData()
	local best = math.floor(tonumber(b.TrialBest) or 0)
	if type(b.TrialCleared) == "table" then
		for level in pairs(b.TrialCleared) do
			if type(level) == "number" and level > best then
				best = level
			end
		end
	end
	return best
end

-- level 1 is always open; level N needs N-1 cleared
local function unlocked(level)
	return level <= 1 or cleared(level - 1) or level <= bestLevel() + 1
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

local function trialPortal()
	local arena = arenaModel()
	local portal = arena and arena:FindFirstChild("Portal_Trials", true)
	if not portal then
		local lobby = Workspace:FindFirstChild("NimbusLobby")
		portal = lobby and lobby:FindFirstChild("Portal_Trials", true)
	end
	return portal
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

-- studs from the Trial Portal (nil when unknown: no portal or no character)
local function portalDistance()
	local pos = rootPosition()
	local portal = S.AtPortal or trialPortal()
	local at = positionOf(portal)
	if not pos or not at then
		return nil
	end
	local d = pos - at
	return Vector3.new(d.X, 0, d.Z).Magnitude
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

-- w, h (design px), scale, x, y (centre, gui px), tall
local function fitWindow()
	local area = guiArea()
	local factor = screenFactor()
	local tall = area.X < area.Y
	local minW = tall and K.TALL_MIN_W or K.MIN_W
	local prefH = tall and K.TALL_MAX_H or K.PREF_H
	local freeW = area.X - 2 * K.MARGIN
	local freeH = area.Y - 2 * K.MARGIN
	local w = Util.Clamp(math.floor(freeW / factor), minW, K.PREF_W)
	local h = Util.Clamp(math.floor((freeH - K.BUMPS * factor) / factor), K.MIN_H, prefH)
	local scale = Util.Clamp(math.min(factor, freeW / w, freeH / h), 0.3, 1.25)
	local y = math.min(area.Y / 2 + K.BUMPS * scale / 2, area.Y - K.MARGIN / 2 - h * scale / 2)
	return w, h, scale, area.X / 2, math.max(y, h * scale / 2), tall or w < K.TALL
end

local function newWindow(id, title)
	local win = { Id = id }
	win.Holder = makeFrame(U.Gui, "Window_" .. id, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(K.PREF_W, K.PREF_H),
		Visible = false,
		ZIndex = 3,
	})
	win.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = win.Holder })
	win.Panel = CloudUI.Panel({
		Name = id .. "Panel",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Title = title,
		Closable = true,
		Accent = C.Arena,
		OnClose = function()
			ArenaController.Close()
		end,
		Parent = win.Holder,
	})
	win.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = win.Panel.Root })
	Win[id] = win
	return win
end

local function layoutWindow(win)
	local w, h, scale, x, y, tall = fitWindow()
	win.Holder.Size = UDim2.fromOffset(w, h)
	win.Holder.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	win.Fit.Scale = scale
	S.Tall = tall
	S.Narrow = w < K.NARROW
	S.Short = h < K.SHORT and not tall
	if win.OnLayout and (win.W ~= w or win.H ~= h) then
		win.W, win.H = w, h
		safe("layout " .. win.Id, win.OnLayout, w, h, S.Narrow, S.Short, tall)
	end
end

----------------------------------------------------------------------
-- Trial window
----------------------------------------------------------------------
local function buildTrials()
	local win = newWindow("Trials", "Trial Portal")
	local content = win.Panel.Content
	local ui = { Tiles = {}, Chapters = {}, Enemy = {} }
	win.Ui = ui

	-- level list (left), grouped by chapter
	ui.List = scroller(content, "Levels", {})
	pad(ui.List, 4, 4, 14, 8)
	listLayout(ui.List, Enum.FillDirection.Vertical, 10)
	local BC = catalog()
	local chapters = (BC and BC.TrialChapters) or { { Name = "Trials", From = 1, To = trialCount() } }
	for index, chapter in ipairs(chapters) do
		local block = makeFrame(ui.List, "Chapter" .. index, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
		})
		listLayout(block, Enum.FillDirection.Vertical, 6)
		local head = makeFrame(block, "Head", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 })
		makeText(head, "Name", tostring(chapter.Name), "Title", 24, WHITE, {
			Size = UDim2.new(0.62, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local progress = makeText(head, "Progress", "", "Heading", 19, MUTED, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 0),
			Size = UDim2.new(0.38, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local grid = makeFrame(block, "Grid", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
		})
		local layout = Util.Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(K.LEVEL_TILE, K.LEVEL_TILE),
			CellPadding = UDim2.fromOffset(K.LEVEL_GAP, K.LEVEL_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		ui.Chapters[index] = { Chapter = chapter, Progress = progress, Layout = layout }
		for level = chapter.From, chapter.To do
			local tile = {}
			tile.Button = Util.Create("TextButton", {
				Name = "Level" .. level,
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Text = "",
				BackgroundColor3 = WHITE,
				LayoutOrder = level,
				Parent = grid,
			})
			corner(tile.Button, 14)
			tile.Stroke = stroke(tile.Button, NAVY, 3, 0)
			tile.Gradient = Util.Create("UIGradient", { Rotation = 90, Parent = tile.Button })
			tile.Number = makeText(tile.Button, "Number", tostring(level), "Display", 36, WHITE, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 2),
				Size = UDim2.new(1, 0, 0, 40),
				ZIndex = 3,
			})
			tile.Tag = colorPill(tile.Button, "Boss", "BOSS", C.Boss, 18, 0)
			tile.Tag.AnchorPoint = Vector2.new(0.5, 0)
			tile.Tag.Position = UDim2.new(0.5, 0, 0, -10)
			tile.Tag.ZIndex = 5
			tile.Tag.Visible = false
			tile.Check = makeFrame(tile.Button, "Cleared", {
				BackgroundTransparency = 0,
				BackgroundColor3 = C.Cleared,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -4, 1, -4),
				Size = UDim2.fromOffset(30, 30),
				Visible = false,
				ZIndex = 5,
			})
			round(tile.Check)
			stroke(tile.Check, NAVY, 2.5, 0)
			makeText(tile.Check, "Mark", G.Check, "Heading", 20, WHITE, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 6 })
			tile.Lock = makeText(tile.Button, "Lock", G.Lock, "Title", 22, WHITE, {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -2, 1, -2),
				Size = UDim2.fromOffset(32, 30),
				Visible = false,
				ZIndex = 5,
			})
			tile.Button.Activated:Connect(function()
				S.Level = level
				refreshOpen()
			end)
			CloudUI.Tooltip(tile.Button, function()
				local t = trials()[level]
				if not t then
					return nil
				end
				local text = "Level " .. level .. ": " .. tostring(t.Name)
				if not unlocked(level) then
					text = text .. "\nBeat level " .. (level - 1) .. " to unlock it"
				elseif cleared(level) then
					text = text .. "\nCleared " .. G.Check
				end
				return text
			end)
			ui.Tiles[level] = tile
		end
	end

	-- detail (right)
	ui.Detail = inset(content, "Detail", {})
	ui.DetailScroll = scroller(ui.Detail, "Scroll", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) })
	pad(ui.DetailScroll, 14, 10, 16, 12)
	listLayout(ui.DetailScroll, Enum.FillDirection.Vertical, 10)
	local d = ui.DetailScroll

	local head = makeFrame(d, "Head", { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
	ui.Head = head
	ui.HeadLayout = listLayout(head, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	ui.LevelLabel = autoText(head, "Level", "LEVEL 1", "Title", 32, GOLD, 1)
	ui.NameLabel = autoText(head, "Name", "", "Title", 28, WHITE, 2)
	local tags = makeFrame(d, "Tags", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2 })
	listLayout(tags, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	ui.Tags = tags

	ui.EnemyTitle = makeText(d, "EnemyTitle", "Enemy team", "Heading", 20, MUTED, {
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
	})
	ui.EnemyRow = makeFrame(d, "Enemies", { Size = UDim2.new(1, 0, 0, 150), LayoutOrder = 4 })
	ui.EnemyLayout = Util.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(118, 150),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ui.EnemyRow,
	})

	-- power: recommended vs. the active team
	local power = inset(d, "Power", { Size = UDim2.new(1, 0, 0, 120), LayoutOrder = 5 })
	ui.Power = power
	makeText(power, "RecCaption", "Recommended", "Heading", 19, MUTED, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(0.5, -14, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	ui.RecValue = makeText(power, "RecValue", "", "Display", 32, C.Power, {
		Position = UDim2.fromOffset(14, 32),
		Size = UDim2.new(0.5, -14, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	makeText(power, "TeamCaption", "Your team", "Heading", 19, MUTED, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.new(0.5, -14, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	ui.TeamValue = makeText(power, "TeamValue", "", "Display", 32, WHITE, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 32),
		Size = UDim2.new(0.5, -14, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local track = makeFrame(power, "Bar", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(14, 20, 48),
		Position = UDim2.fromOffset(14, 74),
		Size = UDim2.new(1, -28, 0, 12),
	})
	round(track)
	ui.BarFill = makeFrame(track, "Fill", {
		BackgroundTransparency = 0,
		BackgroundColor3 = GOOD,
		Size = UDim2.new(0.5, 0, 1, 0),
	})
	round(ui.BarFill)
	ui.BarMark = makeFrame(track, "Recommended", {
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(4, 20),
		ZIndex = 3,
	})
	ui.Verdict = makeText(power, "Verdict", "", "Body", 19, C.GoodText, {
		Position = UDim2.fromOffset(14, 90),
		Size = UDim2.new(1, -28, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- rewards
	local rewards = inset(d, "Rewards", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6 })
	ui.Rewards = rewards
	pad(rewards, 14, 8, 14, 10)
	listLayout(rewards, Enum.FillDirection.Vertical, 4)
	makeText(rewards, "Title", "Rewards", "Heading", 20, WHITE, {
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	ui.WinLine = wrapText(rewards, "Win", "", "Body", 19, WHITE, 2)
	local firstRow = makeFrame(rewards, "First", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
	})
	listLayout(firstRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	ui.FirstBadge = colorPill(firstRow, "Badge", "FIRST CLEAR", Color3.fromRGB(226, 160, 54), 18, 1)
	ui.FirstLine = makeText(firstRow, "Text", "", "Body", 19, C.Power, {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
	})

	-- footer (always in view, under the scrolling detail): why START is off, Edit team, START
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
		Size = UDim2.fromOffset(200, 54),
		Style = "Green",
		TextSize = 26,
		Parent = actions,
		Callback = function()
			safe("start trial", ArenaController.StartSelected)
		end,
	})
	ui.Why = makeText(ui.Footer, "Why", "", "Body", 19, C.WarnText, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 44),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	})

	win.OnLayout = function(w, h, narrow, short, tall)
		local cw = w - K.INSET_X
		local tile = narrow and K.LEVEL_TILE_NARROW or K.LEVEL_TILE
		local cols = 5
		local listW = cols * tile + (cols - 1) * K.LEVEL_GAP + 4 + 14 + 12
		for _, ch in ipairs(ui.Chapters) do
			ch.Layout.CellSize = UDim2.fromOffset(tile, tile)
		end
		local detailW
		if tall then
			-- one column: the detail first, the levels below it
			local detailH = 600
			ui.Detail.Position = UDim2.fromOffset(12, 10)
			ui.Detail.Size = UDim2.new(1, -24, 0, math.min(detailH, h - K.INSET_Y - 260))
			ui.List.Position = UDim2.new(0, 12, 0, 10 + math.min(detailH, h - K.INSET_Y - 260) + 10)
			ui.List.Size = UDim2.new(1, -24, 1, -(30 + math.min(detailH, h - K.INSET_Y - 260)))
			detailW = cw - 24
			local fit = math.floor((cw - 24 - 30 - 4 * K.LEVEL_GAP) / 5)
			for _, ch in ipairs(ui.Chapters) do
				ch.Layout.CellSize = UDim2.fromOffset(math.min(tile, fit), math.min(tile, fit))
			end
		else
			ui.List.Position = UDim2.fromOffset(12, 10)
			ui.List.Size = UDim2.new(0, listW, 1, -20)
			ui.Detail.Position = UDim2.fromOffset(12 + listW + 12, 10)
			ui.Detail.Size = UDim2.new(1, -(listW + 36), 1, -20)
			detailW = cw - listW - 36
		end
		local inner = detailW - 8 - 30
		local enemyCols = inner >= 4 * 112 + 3 * 8 and 4 or 2
		local cardW = math.min(130, math.floor((inner - (enemyCols - 1) * 8) / enemyCols))
		ui.EnemyLayout.CellSize = UDim2.fromOffset(cardW, 150)
		ui.EnemyCols = enemyCols
		ui.StartButton.Size = UDim2.fromOffset(inner < 420 and 170 or 200, 54)
		-- narrow details stack the level number over its name
		local stack = inner < 440
		ui.HeadLayout.FillDirection = stack and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
		ui.HeadLayout.Padding = UDim.new(0, stack and 0 or 10)
		ui.Head.Size = UDim2.new(1, 0, 0, stack and 76 or 40)
		ui.Why.Size = UDim2.new(1, 0, 0, short and 26 or 44)
		-- short windows (landscape phones): the power check and the rewards come before the enemy team
		ui.Power.LayoutOrder = short and 3 or 5
		ui.Rewards.LayoutOrder = short and 4 or 6
		ui.EnemyTitle.LayoutOrder = short and 5 or 3
		ui.EnemyRow.LayoutOrder = short and 6 or 4
		ui.WhyH = short and 26 or 44
	end

	local function verdictOf(mine, rec)
		if rec <= 0 then
			return "", C.GoodText
		end
		local ratio = mine / rec
		if mine <= 0 then
			return "Pick your battle team first!", C.WarnText
		elseif ratio >= 1.15 then
			return "Your team looks ready for this one!", C.GoodText
		elseif ratio >= 0.9 then
			return "A close fight: use your specials well.", C.WarnText
		elseif ratio >= 0.7 then
			return "Tough fight! Level up or add synergy.", C.WarnText
		end
		return "Too strong for now: train your pets first.", C.BadText
	end

	local function enemyCard(entry, order)
		local def = petDef(entry.PetId, entry.Tier)
		local card = makeFrame(ui.EnemyRow, "Enemy" .. order, {
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			LayoutOrder = order,
		})
		corner(card, 12)
		stroke(card, entry.Boss and C.Boss or NAVY, entry.Boss and 4 or 3, 0)
		local tint = rarityColor(def)
		Theme.Gradient(card, Theme.Lighten(INSET, 0.3):Lerp(tint, 0.4), Theme.Darken(INSET, 0.05):Lerp(tint, 0.2), 90)
		local view = makeFrame(card, "ViewHolder", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.new(1, -10, 0, 70),
			ZIndex = 2,
		})
		if def then
			pcall(function()
				local handle = CloudUI.PetViewport(view, def, UDim2.new(1, 0, 1, 0), {
					Spin = "sway",
					Animate = entry.Boss == true,
					Detail = "Low",
					ZIndex = 2,
				})
				table.insert(ui.Enemy, handle)
			end)
		end
		if entry.Boss then
			local crown = colorPill(card, "BossTag", G.Crown .. " BOSS", C.Boss, 18, 0)
			crown.AnchorPoint = Vector2.new(0.5, 0)
			crown.Position = UDim2.new(0.5, 0, 0, 2)
			crown.ZIndex = 5
		end
		makeText(card, "PetName", def and tostring(def.Name) or tostring(entry.PetId), "Body", 18, rarityText(def), {
			Position = UDim2.fromOffset(4, 74),
			Size = UDim2.new(1, -8, 0, 40),
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		})
		local row = makeFrame(card, "Row", { Position = UDim2.fromOffset(4, 116), Size = UDim2.new(1, -8, 0, 28), ZIndex = 3 })
		listLayout(row, Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		autoText(row, "Level", "Lv " .. tostring(entry.Level or 1), "Heading", 18, WHITE, 0)
		local elements = elementsOf(def)
		if elements[1] then
			elementPill(row, elements[1], 18, 1)
		end
		return card
	end

	win.Refresh = function()
		local count = math.max(1, trialCount())
		local list = trials()
		if not S.Level or not list[S.Level] then
			S.Level = math.min(count, bestLevel() + 1)
		end
		local level = S.Level
		local nextLevel = math.min(count, bestLevel() + 1)
		-- tiles
		for n, tile in pairs(ui.Tiles) do
			local open = unlocked(n)
			local done = cleared(n)
			local t = list[n]
			local selected = n == level
			local base = done and Color3.fromRGB(70, 140, 96) or (open and C.Next or Color3.fromRGB(70, 78, 104))
			if t and t.MiniBoss and open and not done then
				base = C.Trial
			end
			tile.Gradient.Color = ColorSequence.new(Theme.Lighten(base, 0.22), Theme.Darken(base, 0.18))
			tile.Stroke.Color = selected and GOLD or NAVY
			tile.Stroke.Thickness = selected and 4.5 or 3
			tile.Number.TextColor3 = open and WHITE or Color3.fromRGB(176, 184, 206)
			tile.Tag.Visible = t ~= nil and t.MiniBoss == true
			tile.Check.Visible = done
			tile.Lock.Visible = not open
			if n == nextLevel and open and not done then
				tile.Stroke.Color = selected and GOLD or Theme.Lighten(C.Next, 0.5)
			end
		end
		for _, ch in ipairs(ui.Chapters) do
			local n, total = 0, 0
			for lv = ch.Chapter.From, ch.Chapter.To do
				total = total + 1
				if cleared(lv) then
					n = n + 1
				end
			end
			ch.Progress.Text = (n >= total and (G.Check .. " ") or "") .. n .. " / " .. total
			ch.Progress.TextColor3 = n >= total and C.GoodText or MUTED
		end
		-- detail
		local t = list[level]
		ui.LevelLabel.Text = "LEVEL " .. level
		ui.NameLabel.Text = t and tostring(t.Name) or "?"
		clearChildren(ui.Tags)
		if t then
			colorPill(ui.Tags, "Chapter", tostring(t.Chapter or ""), Color3.fromRGB(90, 120, 190), 18, 1)
			if t.MiniBoss then
				colorPill(ui.Tags, "MiniBoss", G.Crown .. " Mini-boss", C.Boss, 18, 2)
			end
			if cleared(level) then
				colorPill(ui.Tags, "Cleared", G.Check .. " Cleared", C.Cleared, 18, 3)
			elseif not unlocked(level) then
				colorPill(ui.Tags, "Locked", G.Lock .. " Locked", Color3.fromRGB(110, 118, 146), 18, 3)
			end
		end
		-- enemy team (rebuilt only when the level changes)
		if ui.EnemyLevel ~= level then
			ui.EnemyLevel = level
			for _, handle in ipairs(ui.Enemy) do
				pcall(handle.Destroy)
			end
			ui.Enemy = {}
			clearChildren(ui.EnemyRow)
			for i, entry in ipairs((t and t.Team) or {}) do
				enemyCard(entry, i)
			end
		end
		local enemies = t and t.Team and #t.Team or 0
		local rows = math.max(1, math.ceil(enemies / math.max(1, ui.EnemyCols or 4)))
		ui.EnemyRow.Size = UDim2.new(1, 0, 0, rows * 150 + (rows - 1) * 8)
		-- power
		local rec = t and tonumber(t.RecommendedPower) or 0
		local team = activeTeam()
		local mine = teamPower(team)
		ui.RecValue.Text = G.Swords .. " " .. commas(rec)
		ui.TeamValue.Text = G.Swords .. " " .. commas(mine)
		local ratio = rec > 0 and mine / rec or 1
		ui.TeamValue.TextColor3 = ratio >= 1 and C.GoodText or (ratio >= 0.8 and C.WarnText or C.BadText)
		local top = math.max(rec, mine) * 1.15
		local fill = top > 0 and mine / top or 0
		ui.BarFill.Size = UDim2.new(Util.Clamp(fill, 0.02, 1), 0, 1, 0)
		ui.BarFill.BackgroundColor3 = ratio >= 1 and GOOD or (ratio >= 0.8 and Color3.fromRGB(240, 186, 70) or BAD)
		ui.BarMark.Position = UDim2.new(top > 0 and rec / top or 0.5, 0, 0.5, 0)
		local verdict, verdictColor = verdictOf(mine, rec)
		ui.Verdict.Text = verdict
		ui.Verdict.TextColor3 = verdictColor
		-- rewards
		local r = t and t.Rewards or {}
		local double = S.Arena and type(S.Arena.Double) == "table" and S.Arena.Double.Active == true
		local mult = double and 2 or 1
		ui.WinLine.Text = "Each win: " .. G.Cloud .. " " .. commas((tonumber(r.Tokens) or 0) * mult) .. " Cloud Tokens + "
			.. commas(r.Xp or 0) .. " XP per pet" .. (double and "  (2x now!)" or "")
		local first = type(r.FirstClear) == "table" and r.FirstClear or {}
		if cleared(level) then
			ui.FirstBadge.Text = G.Check .. " CLAIMED"
			ui.FirstBadge.BackgroundColor3 = C.Cleared
			ui.FirstLine.Text = "First-clear bonus collected"
			ui.FirstLine.TextColor3 = MUTED
		else
			ui.FirstBadge.Text = "FIRST CLEAR"
			ui.FirstBadge.BackgroundColor3 = Color3.fromRGB(226, 160, 54)
			local text = "+" .. G.Cloud .. " " .. commas((tonumber(first.Tokens) or 0) * mult)
			if (tonumber(first.Gems) or 0) > 0 then
				text = text .. "   +" .. G.Gem .. " " .. commas(first.Gems) .. " Gems"
			end
			ui.FirstLine.Text = text
			ui.FirstLine.TextColor3 = C.Power
		end
		-- start
		local why = nil
		if not unlocked(level) then
			why = "Beat level " .. (level - 1) .. " to unlock this one."
		elseif #team == 0 then
			why = "Pick your battle team first (Edit team)."
		elseif battleId() then
			why = "Finish your current battle first."
		elseif inMatch() then
			why = "Finish your climb first."
		else
			local d2 = portalDistance()
			if d2 and d2 > K.TRIAL_RANGE then
				why = "Walk to the Trial Portal to start."
			end
		end
		CloudUI.SetDisabled(ui.StartButton, why ~= nil)
		ui.StartButton.Text = "START"
		ui.Why.Text = why or ""
		ui.Why.Visible = why ~= nil
		local footerH = why and (60 + (ui.WhyH or 44)) or 56
		ui.Footer.Size = UDim2.new(1, -28, 0, footerH)
		ui.DetailScroll.Size = UDim2.new(1, -8, 1, -(footerH + 22))
	end
	return win
end

function ArenaController.StartSelected()
	local level = S.Level
	if type(level) ~= "number" or not unlocked(level) then
		return false
	end
	if #activeTeam() == 0 then
		toast("Pick your battle team first!", "info")
		return false
	end
	if request("Trial", level) then
		local win = Win.Trials
		if win and win.Ui and win.Ui.StartButton then
			win.Ui.StartButton.Text = "Starting..."
			CloudUI.SetDisabled(win.Ui.StartButton, true)
		end
		return true
	end
	return false
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
		stroke(row, C.Arena, 3, 0)
		makeText(row, "Name", G.Swords .. " " .. tostring(invite.FromName or "Someone") .. " challenges you!", "Heading", 20, WHITE, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
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
			wrapText(ui.ChallengeList, "Empty", "Nobody else is in this server yet. Invite a friend, or beat the Trial Portal's levels meanwhile!", "Body", 19, MUTED, 1)
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
	for _, name in ipairs({ "MenuController", "IndexController", "FusionController" }) do
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
				local card = sideCard("Invite" .. i, C.Arena, 10 + i)
				makeText(card, "Title", G.Swords .. " Duel challenge!", "Heading", 21, Theme.Lighten(C.Arena, 0.4), {
					Size = UDim2.new(1, 0, 0, 28),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 1,
				})
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

local function setBackdrop(on)
	local backdrop = U.Backdrop
	if not backdrop then
		return
	end
	if on then
		backdrop.Visible = true
		tween(backdrop, 0.18, { BackgroundTransparency = 0.55 })
	else
		tween(backdrop, 0.15, { BackgroundTransparency = 1 })
		local mine = S.Token
		task.delay(0.17, function()
			if S.Token == mine and not S.Open and backdrop.Parent then
				backdrop.Visible = false
			end
		end)
	end
end

local function closeOthers()
	for _, name in ipairs({ "MenuController", "IndexController", "FusionController" }) do
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
	if id == "Trials" then
		ok, result = pcall(buildTrials)
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
	if not was then
		setBackdrop(true)
	end
	refreshOpen()
	if was ~= id then
		ArenaController.Opened:Fire(id)
	end
	return true
end

function ArenaController.OpenTrials(level, portal)
	local n = tonumber(level)
	if n and catalog() and trials()[math.floor(n)] then
		S.Level = math.floor(n)
	elseif S.Open ~= "Trials" then
		S.Level = nil -- the next level to beat
	end
	S.AtPortal = (typeof(portal) == "Instance") and portal or nil
	return open("Trials")
end

function ArenaController.OpenArena(tab)
	S.Tab = normalizeTab(tab) or S.Tab or "Duels"
	S.AtPortal = nil
	return open("Arena")
end

function ArenaController.SelectLevel(level)
	local n = tonumber(level)
	if n and trials()[math.floor(n)] then
		S.Level = math.floor(n)
		if S.Open == "Trials" then
			refreshOpen()
		end
	end
end

function ArenaController.Close()
	if not S.Open then
		return
	end
	local id = S.Open
	local win = Win[id]
	S.Open = nil
	S.AtPortal = nil
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
	setBackdrop(false)
	refreshSide()
	ArenaController.Closed:Fire(id)
end

function ArenaController.IsOpen()
	return S.Open ~= nil
end

function ArenaController.GetState()
	return { Arena = S.Arena, Lobby = S.Lobby, Window = S.Open, Tab = S.Tab, Level = S.Level }
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
	if panel == "Trials" then
		ArenaController.OpenTrials(nil, prompt.Parent)
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
				if windowId ~= nil and (windowId == "Trials" or windowId == "Arena") then
					return
				end
				ArenaController.Close()
			end)
		end
	end
	hook("MenuController", "WindowOpened")
	hook("IndexController", "Opened")
	hook("FusionController", "Opened")
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
	U.Backdrop = Util.Create("TextButton", {
		Name = "Backdrop",
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(8, 12, 32),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 1,
		Parent = gui,
	})
	U.Backdrop.Activated:Connect(function()
		ArenaController.Close()
	end)
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
				if key == "trials" or key == "trial" then
					safe("OpenPanel", ArenaController.OpenTrials, args.Level)
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
		if S.Open == "Trials" and S.AtPortal then
			local d = portalDistance()
			if d and d > K.WALK_AWAY then
				ArenaController.Close()
				return
			end
		end
		if S.Open == "Arena" and Win.Arena and Win.Arena.Live then
			safe("live", Win.Arena.Live)
		end
		safe("side", refreshSide)
	end)
end

return ArenaController
