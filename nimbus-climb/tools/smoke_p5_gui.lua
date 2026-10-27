-- smoke_p5_gui.lua: the Phase 5 Neon kit and the window rule (ARCHITECTURE_V3.md "Phase 5 build contract" 6.6, 12.1).
-- Loaded by tools/smoke.py in the CLIENT world. Owner: neonkit (W2) writes the scenarios; every window owner adds its
-- scenes to the client_p5gui_cover lists from inside its own named block below (C18: own block only, re-read the file
-- right before each edit; never touch another block or the dispatch).
--   client_p5neon       Card stroke + Glow, Tile fonts + stroke, SideRect == the prototype at 4 sizes
--   client_p5stamina    150 stamina, runs ~10.7 s, refills <= 3.5 s, 4 dashes, 4 ticks
--   client_p5hud_pills  the HUD pills (Cash / Gems / Tokens / Berries) in the Neon style
--   client_p5gui_cover  for every scene of COVER (menu:*, feed, garden, train, ring, arena:*, dungeon, obby, settings) at
--                       1920x1080, 1280x720, 390x844 and 844x390: union <= 60% of the screen, landscape left edge
--                       >= 0.5 W, portrait top >= 0.44 H, no `Backdrop`, smallest text >= the floor (the coverage.py port)
-- Wave 2 (neonkit): the scenarios are live; the HUD and the reference docked panel are the kit's own cover scenes.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}

----------------------------------------------------------------------------------------------------
-- COVER: the scenes client_p5gui_cover opens, { Scene = "<dump_gui scene>", Open = function() ... end } entries.
-- Each window owner registers ITS windows inside its own block (append to COVER; a window gets its own controller).
----------------------------------------------------------------------------------------------------
local COVER = {}

-- [owner: neonkit] begin
-- COVER entry (every window owner): { Scene = "<name>", Open = function(size) ... end, Close = function() ... end,
--   Window = function() return <the window's root GuiObject> end, Sizes = { {W, H}, ... } (optional; default the 4) }
--   Open runs after the screen size is set (size = { W, H, touch }); Close must leave nothing open. Window (optional)
--   is checked against the window rule (landscape: left edge >= 0.5 W; portrait: top >= 0.44 H).
-- NK: the kit's helpers (shared by the scenarios below; other owners may call them read-only)
local NK = {}
NK.SIZES = { { 1920, 1080, false }, { 1280, 720, false }, { 390, 844, true }, { 844, 390, true } }
function NK.KC()
	return _G.KC
end
function NK.req(key)
	return require(Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", "")))
end
function NK.pg()
	return game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
end
function NK.advance(seconds)
	Mock.Advance(seconds)
end
-- the prototype's side_rect (p5design/design:world/gui/gui_proto.py), the reference SideRect must equal
function NK.protoRect(W, H, touch, prefW, prefH)
	local f = math.max(0.8, math.min(1.25, H / 1080))
	local m = 12 * f
	if W >= H then
		local maxW, maxH = W * 0.44, H - 58 - 2 * m
		local scale = f
		if prefW * scale > maxW then
			scale = touch and 0.8 or math.max(0.85, maxW / prefW)
		end
		local w = math.min(prefW, maxW / scale)
		local h = math.min(prefH, maxH / scale)
		return { x = W - m - w * scale, y = 58 + m + (maxH - h * scale) / 2, w = w * scale, h = h * scale, scale = scale }
	end
	-- (contract deviation, neonkit W2: the prototype let the sheet's bottom margin push its top to 0.44 H - m; the
	-- sheet is m shorter so the top 44% really stays clear, as the cover rule checks)
	local scale = 0.8
	local w = (W - 2 * m) / scale
	local h = math.min(prefH, (H * 0.56 - m) / scale)
	return { x = m, y = H - m - h * scale, w = w * scale, h = h * scale, scale = scale }
end
-- switch the simulated screen (and the touch flags); returns a restore function
function NK.screen(W, H, touch)
	local UIS = game:GetService("UserInputService")
	local old = { Mock.Viewport.X, Mock.Viewport.Y, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
	UIS.TouchEnabled = touch and true or false
	UIS.KeyboardEnabled = not touch
	UIS.MouseEnabled = not touch
	Mock.SetViewport(W, H)
	return function()
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[3], old[4], old[5]
		Mock.SetViewport(old[1], old[2])
	end
end
function NK.shown(obj)
	return obj ~= nil and NK.KC().isShown(obj)
end
function NK.scaleOf(inst)
	local scale = 1
	local cur = inst
	while cur and cur ~= game do
		if cur:IsA("GuiObject") then
			for _, c in ipairs(cur:GetChildren()) do
				if c:IsA("UIScale") and c.Name ~= "FxScale" and c.Name ~= "Pop" and c.Name ~= "Punch" then
					scale = scale * c.Scale
				end
			end
		end
		cur = cur.Parent
	end
	return scale
end
-- screen rect of a GuiObject (top bar included)
function NK.rect(obj)
	local gui = obj:FindFirstAncestorOfClass("ScreenGui")
	local dy = (gui and not gui.IgnoreGuiInset) and (Mock.TopInset or 0) or 0
	local p, sz = obj.AbsolutePosition, obj.AbsoluteSize
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + sz.X, y1 = p.Y + dy + sz.Y }
end
-- the coverage.py port: % of the screen under opaque GUI (BackgroundTransparency < 0.5, images, viewports) of every
-- enabled ScreenGui, on a 4 px grid; also the smallest on-screen text and any visible "Backdrop"
function NK.coverage()
	local W, H = Mock.Viewport.X, Mock.Viewport.Y
	local cols, rows = math.floor(W / 4) + 1, math.floor(H / 4) + 1
	local mask, covered = {}, 0
	local smallest, smallestName, backdrop = math.huge, "", nil
	for _, g in ipairs(NK.pg():GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("GuiObject") and NK.shown(d) and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
					if d.Name == "Backdrop" then
						backdrop = d:GetFullName()
					end
					local opaque = d.BackgroundTransparency < 0.5 or d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("ViewportFrame")
					if opaque then
						local r = NK.rect(d)
						local x0, y0 = math.max(0, math.floor(r.x0 / 4)), math.max(0, math.floor(r.y0 / 4))
						local x1, y1 = math.min(cols, math.floor(r.x1 / 4)), math.min(rows, math.floor(r.y1 / 4))
						for y = y0, y1 - 1 do
							local base = y * cols
							for x = x0, x1 - 1 do
								if not mask[base + x] then
									mask[base + x] = true
									covered = covered + 1
								end
							end
						end
					end
					if (d:IsA("TextLabel") or d:IsA("TextButton")) and tostring(d.Text):gsub("<[^>]*>", ""):gsub("%s", "") ~= "" then
						local px = d.TextScaled and d.AbsoluteSize.Y or d.TextSize * NK.scaleOf(d)
						if px < smallest then
							smallest, smallestName = px, d:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
						end
					end
				end
			end
		end
	end
	return 100 * covered / (cols * rows), smallest, smallestName, backdrop
end
-- the kit's own cover scenes: the bare HUD, and the reference side panel (a CloudUI.Panel 820 x 900 "Pets" window
-- docked by NeonKit.Dock, what menu:Pets becomes in W3) with the hotbar avoiding it
NK.Dock = {}
COVER[#COVER + 1] = { Scene = "hud", Open = function() end, Close = function() end }
COVER[#COVER + 1] = {
	Scene = "dock:Pets",
	Open = function()
		local CloudUI, NeonKit = NK.req("client/UI/CloudUI"), NK.req("client/UI/NeonKit")
		local g = CloudUI.NewScreenGui("SmokeDock", 22)
		local panel = CloudUI.Panel({ Name = "DockPanel", Title = "PETS", Category = "Pets", Closable = true, Size = UDim2.fromOffset(820, 900), Parent = g })
		local grid = CloudUI.Grid(panel.Content, 118, 12)
		for i = 1, 12 do
			CloudUI.Slot({ Size = UDim2.fromOffset(118, 118), LayoutOrder = i, Parent = grid }).SetContent({ Glyph = "P", Name = "Pet" })
		end
		NK.Dock.Gui, NK.Dock.Panel = g, panel
		NK.Dock.Handle = NeonKit.Dock(panel.Root, nil, 820, 900, 520, 420)
		local HB = NK.KC().M and NK.KC().M.HotbarController
		if HB and HB.SetAvoidRight and NK.Dock.Handle.Rect.mode == "Side" then
			HB.SetAvoidRight(NK.Dock.Handle.Rect.x)
		end
	end,
	Close = function()
		local HB = NK.KC().M and NK.KC().M.HotbarController
		if HB and HB.SetAvoidRight then
			HB.SetAvoidRight(nil)
		end
		if NK.Dock.Gui then
			NK.Dock.Gui:Destroy()
		end
		NK.Dock = {}
	end,
	Window = function()
		return NK.Dock.Panel and NK.Dock.Panel.Root
	end,
}
-- [owner: neonkit] end

-- [owner: careui] begin
-- careui (W3): every menu / care window docked by the window rule. A Phase 5 profile (a home, berries, evolved pets,
-- a team of 3) is synced once; each scene opens its window through the real controller and closes it again.
local CUI = {}
function CUI.profile()
	if CUI.Synced then
		return
	end
	CUI.Synced = true
	local PetCatalog = NK.req("shared/PetCatalog")
	local Config = NK.req("shared/Config")
	local ids = {}
	for _, def in ipairs(PetCatalog.Pets) do
		if not def.EventOnly and def.Rarity ~= "Secret" and #ids < 6 then
			ids[#ids + 1] = def.Id
		end
	end
	local pets, levels = {}, {}
	for i, id in ipairs(ids) do
		pets[id] = 1
		levels[id] = { Level = 10 + i * 5, Xp = 10 }
	end
	local LocalPlayer = game:GetService("Players").LocalPlayer
	local lobby = workspace:FindFirstChild("NimbusLobby") or Instance.new("Folder")
	lobby.Name = "NimbusLobby"
	lobby.Parent = workspace
	local plot = lobby:FindFirstChild("Spot_09") or Instance.new("Folder")
	plot.Name = "Spot_09"
	plot:SetAttribute("SpotIndex", 9)
	plot:SetAttribute("IncomePerSecond", 38.5)
	plot:SetAttribute("GardenSlots", 4)
	plot:SetAttribute("BerryCap", 3000)
	plot.Parent = lobby
	LocalPlayer:SetAttribute(Config.Attr.SpotIndex, 9)
	LocalPlayer:SetAttribute(Config.Attr.Berries or "Berries", 1240)
	NK.KC().toClient("ProfileSync", {
		Tokens = 900, Pets = pets, Equipped = { ids[1] }, Items = {}, Discovered = pets, IndexClaimed = {},
		Stats = { Matches = 3, Wins = 1, TokensEarned = 40, Spins = 2, BestTimes = {} },
		Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
		Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 12400, Gems = 85, Berries = 1240,
		Home = { Level = 21, Prestige = 1, Stations = { Garden = 3, Press1 = 13, Kitchen = 2, Gym = 2, Vault = 1, House = 2, FusionMachine = 1 },
			Garden = { ids[2], ids[3], "", "" }, Gym = {} },
		PetLevels = levels, PetGrowth = { [ids[4]] = { Evo = 1 }, [ids[5]] = { Evo = 2 } },
		Teams = { Presets = { { ids[5], ids[4], ids[1] }, {}, {} }, Active = 1, Slots = 3 },
	})
	NK.advance(0.5)
end
function CUI.menu()
	return NK.KC().M and NK.KC().M.MenuController
end
function CUI.menuWindow(id)
	local g = NK.pg():FindFirstChild("NimbusMenu")
	return g and g:FindFirstChild("Window_" .. id)
end
function CUI.closeAll()
	local KC = NK.KC()
	for _, name in ipairs({ "MenuController", "CareController", "IndexController", "FusionController" }) do
		local m = (KC.M and KC.M[name]) or NK.req("client/Controllers/" .. name)
		if m and type(m.Close) == "function" then
			pcall(m.Close)
		end
	end
end
for _, spec in ipairs({ { "menu:Pets", "Pets", "Inventory" }, { "menu:Home", "Home", "Home" }, { "menu:Team", "Team", "Team" },
	{ "menu:Shop", "Shop", "Shop" }, { "menu:Stats", "Stats", "Stats" } }) do
	COVER[#COVER + 1] = {
		Scene = spec[1],
		Open = function()
			CUI.profile()
			pcall(CUI.menu().Open, spec[2], {})
		end,
		Close = CUI.closeAll,
		Window = function()
			return CUI.menuWindow(spec[3])
		end,
	}
end
for _, spec in ipairs({ { "feed", "Feed" }, { "garden", "Garden" }, { "train", "Train" } }) do
	COVER[#COVER + 1] = {
		Scene = spec[1],
		Open = function()
			CUI.profile()
			local care = (NK.KC().M and NK.KC().M.CareController) or NK.req("client/Controllers/CareController")
			pcall(care.Open, spec[2], { Slot = 4 })
		end,
		Close = CUI.closeAll,
		Window = function()
			local g = NK.pg():FindFirstChild("NimbusCare")
			return g and g:FindFirstChild("Window_Care")
		end,
	}
end
COVER[#COVER + 1] = {
	Scene = "menu:Index",
	Open = function()
		CUI.profile()
		pcall(CUI.menu().Open, "Index", {})
	end,
	Close = CUI.closeAll,
	Window = function()
		local g = NK.pg():FindFirstChild("NimbusIndex")
		return g and g:FindFirstChild("Window_Index")
	end,
}
COVER[#COVER + 1] = {
	Scene = "fusion",
	Open = function()
		CUI.profile()
		local f = (NK.KC().M and NK.KC().M.FusionController) or NK.req("client/Controllers/FusionController")
		pcall(f.Open, "Upgrade", {})
	end,
	Close = CUI.closeAll,
	Window = function()
		local g = NK.pg():FindFirstChild("NimbusFusion")
		return g and g:FindFirstChild("Window_Fusion")
	end,
}
-- [owner: careui] end

-- [owner: menu] begin
-- the SETTINGS window after PLAY (opened by the menu gear: MainMenuController.OpenSettings), docked by the window rule
COVER[#COVER + 1] = {
	Scene = "settings",
	Open = function()
		local mm = NK.req("client/Controllers/MainMenuController")
		pcall(mm.OpenSettings)
	end,
	Close = function()
		local mm = NK.req("client/Controllers/MainMenuController")
		pcall(mm.CloseWindows)
	end,
	Window = function()
		local mm = NK.req("client/Controllers/MainMenuController")
		local holder = mm.Window()
		return holder
	end,
}
-- [owner: menu] end

-- [owner: battleclient] begin
-- (battle:fighter, battle:raid, battle:dungeon, result)
-- [owner: battleclient] end

-- [owner: dungeonclient] begin
-- dungeonclient (W4): the Ring / Arena windows (ArenaController), the Dungeon window with a Lobby payload (DungeonController)
-- and the obby picker (ObbyController), each through its real controller.
local DGC = {}
function DGC.mod(name)
	return (NK.KC().M and NK.KC().M[name]) or NK.req("client/Controllers/" .. name)
end
function DGC.closeAll()
	for _, name in ipairs({ "ArenaController", "DungeonController", "ObbyController", "MenuController" }) do
		local m = DGC.mod(name)
		if m and type(m.Close) == "function" then
			pcall(m.Close)
		end
	end
end
function DGC.arenaWindow(id)
	local g = NK.pg():FindFirstChild("NimbusArena")
	return g and g:FindFirstChild("Window_" .. id)
end
COVER[#COVER + 1] = {
	Scene = "ring",
	Open = function()
		pcall(DGC.mod("ArenaController").OpenRing)
	end,
	Close = DGC.closeAll,
	Window = function()
		return DGC.arenaWindow("Ring")
	end,
}
for _, tab in ipairs({ "Duels", "Raid", "Leaderboard" }) do
	COVER[#COVER + 1] = {
		Scene = "arena:" .. tab:lower(),
		Open = function()
			pcall(DGC.mod("ArenaController").OpenArena, tab)
		end,
		Close = DGC.closeAll,
		Window = function()
			return DGC.arenaWindow("Arena")
		end,
	}
end
COVER[#COVER + 1] = {
	Scene = "arena:dungeon",
	Open = function()
		local cleared = {}
		for f = 1, 12 do
			cleared[f] = f <= 4
		end
		NK.KC().toClient("DungeonState", "Lobby", {
			Parties = { { Leader = 501, LeaderName = "Ava", Floor = 3, Count = 2, Max = 4, Open = true, InRun = false },
				{ Leader = 502, LeaderName = "Sam", Floor = 5, Count = 3, Max = 4, Open = true, InRun = true, Room = 2 } },
			Record = { Best = 4, Cleared = cleared, Runs = 12, Clears = 7 },
		})
		pcall(DGC.mod("DungeonController").Open, 3)
	end,
	Close = DGC.closeAll,
	Window = function()
		local g = NK.pg():FindFirstChild("NimbusDungeon")
		return g and g:FindFirstChild("Window_Dungeon")
	end,
}
COVER[#COVER + 1] = {
	Scene = "obby",
	Open = function()
		pcall(DGC.mod("ObbyController").Open)
	end,
	Close = DGC.closeAll,
	Window = function()
		local g = NK.pg():FindFirstChild("NimbusObby")
		return g and g:FindFirstChild("Window_Obby")
	end,
}
-- [owner: dungeonclient] end

-- [owner: homefx+pets] begin
-- (follow windows, the home signs if a cover check is wanted)
-- [owner: homefx+pets] end

-- [owner: tutorial] begin
-- (tutorial panel + pointer)
-- [owner: tutorial] end

----------------------------------------------------------------------------------------------------
-- scenarios (neonkit W2 replaces the placeholder bodies)
----------------------------------------------------------------------------------------------------
S.client_p5neon = guarded("client_p5neon", function()
	local Theme = NK.req("shared/Theme")
	local Config = NK.req("shared/Config")
	local NeonKit, CloudUI = NK.req("client/UI/NeonKit"), NK.req("client/UI/CloudUI")
	-- Theme tokens (6.6)
	local want = { Orange = { 255, 150, 48 }, Blue = { 64, 170, 255 }, Purple = { 176, 104, 255 }, Red = { 255, 76, 100 }, Green = { 72, 224, 120 },
		Yellow = { 255, 210, 64 }, Cyan = { 64, 226, 236 }, Pink = { 255, 112, 200 }, Gold = { 255, 196, 64 }, Grey = { 150, 166, 204 } }
	local bad = {}
	for _, name in ipairs({ "Orange", "Blue", "Purple", "Red", "Green", "Yellow", "Cyan", "Pink", "Gold", "Grey" }) do
		local c, w = Theme.Neon[name], want[name]
		if not (c and c == Color3.fromRGB(w[1], w[2], w[3])) then
			bad[#bad + 1] = name
		end
	end
	T.check(#bad == 0, "p5neon: Theme.Neon has the 10 contract colours", table.concat(bad, ","))
	local cats = { Pets = "Orange", Items = "Blue", Team = "Red", Index = "Purple", Shop = "Green", Home = "Yellow", Stats = "Cyan", Settings = "Grey",
		Obby = "Blue", Dungeon = "Purple", Ring = "Gold", Arena = "Red", Altar = "Cyan", Care = "Green", Fusion = "Pink", Battle = "Red" }
	bad = {}
	for _, cat in ipairs({ "Pets", "Items", "Team", "Index", "Shop", "Home", "Stats", "Settings", "Obby", "Dungeon", "Ring", "Arena", "Altar", "Care", "Fusion", "Battle" }) do
		if Theme.Category[cat] ~= cats[cat] or Theme.NeonColor(cat) ~= Theme.Neon[cats[cat]] then
			bad[#bad + 1] = cat
		end
	end
	T.check(#bad == 0, "p5neon: Theme.Category (16 categories) + Theme.NeonColor(category)", table.concat(bad, ","))
	T.check(Theme.NeonColor("orange") == Theme.Neon.Orange and Theme.NeonColor(Theme.Neon.Pink) == Theme.Neon.Pink and Theme.NeonColor("nope") == Theme.Neon.Blue,
		"p5neon: NeonColor takes a neon name (any case) or a Color3; unknown -> Blue")
	local C = Theme.Colors
	T.check(C.PanelTop == Color3.fromRGB(26, 32, 72) and C.PanelBottom == Color3.fromRGB(12, 15, 38) and C.PanelInk == Color3.fromRGB(8, 10, 28) and C.Navy ~= nil and C.FrameTop ~= nil,
		"p5neon: Colors.PanelTop / PanelBottom / PanelInk (old keys kept)")
	local F = Theme.Fonts
	T.check(F.Title == Enum.Font.GothamBlack and F.Button == Enum.Font.GothamBlack and F.Toast == Enum.Font.GothamBlack and F.Display == Enum.Font.FredokaOne
		and F.Accent == Enum.Font.LuckiestGuy and F.Body == Enum.Font.BuilderSansBold and F.Label == Enum.Font.BuilderSansBold,
		"p5neon: fonts: Title / Button / Toast GothamBlack, Display FredokaOne, Accent LuckiestGuy, Body / Label BuilderSansBold")

	local g = CloudUI.NewScreenGui("SmokeNeon", 41)
	-- Card: 3 px neon stroke, glow ring (+3 px frame, 5 px stroke at 0.62), floor on a short card, sheen, Body
	local card = NeonKit.Card({ Name = "C1", Size = UDim2.fromOffset(240, 120), Color = "Purple", Parent = g })
	local stroke = card.Root:FindFirstChild("NeonStroke")
	T.check(stroke and stroke:IsA("UIStroke") and stroke.Thickness == 3 and stroke.Color == Theme.Neon.Purple and stroke.Transparency == 0,
		"p5neon: Card: a 3 px neon UIStroke in its colour")
	local glowStroke = card.Glow and card.Glow:FindFirstChildOfClass("UIStroke")
	T.check(card.Glow and card.Glow.Visible and glowStroke and glowStroke.Thickness == 5 and math.abs(glowStroke.Transparency - 0.62) < 1e-6 and glowStroke.Color == Theme.Neon.Purple
		and card.Glow.AbsoluteSize.X > card.Root.AbsoluteSize.X, "p5neon: Card: an outer glow frame with a 5 px stroke at 0.62")
	T.check(card.Floor and card.Floor.Visible and card.Floor.BackgroundColor3 == Theme.Neon.Purple and card.Root:FindFirstChildOfClass("UIGradient") ~= nil
		and card.Root:FindFirstChildOfClass("UIGradient").Color.Keypoints[1].Value == C.PanelTop, "p5neon: Card: the PanelTop -> PanelBottom fill + the neon floor (short card)")
	T.check(card.Sheen and card.Sheen.Visible and card.Body and card.Body:IsA("Frame") and #card.Body:GetChildren() == 0, "p5neon: Card: a sheen line; Body is empty for the caller")
	card.SetColor("Gold")
	card.SetGlow(false)
	T.check(stroke.Color == Theme.Neon.Gold and glowStroke.Color == Theme.Neon.Gold and card.Floor.BackgroundColor3 == Theme.Neon.Gold and not card.Glow.Visible, "p5neon: Card.SetColor / SetGlow")
	local tall = NeonKit.Card({ Size = UDim2.fromOffset(600, 700), Parent = g })
	T.check(not tall.Floor.Visible, "p5neon: a window-sized card has no floor by default")
	-- Tile: GothamBlack label 0.2 x size (>= 18) with a 2.5 px dark stroke, icon 0.46 x size on an orb
	local clicks = 0
	local tile = NeonKit.Tile({ Size = 84, Color = "Pets", Icon = "Pets", Label = "Pets", Callback = function()
		clicks = clicks + 1
	end, Parent = g })
	local outline = tile.Label and tile.Label:FindFirstChild("TextOutline")
	T.check(tile.Label and tile.Label.Font == Enum.Font.GothamBlack and tile.Label.TextSize == 18 and tile.Label.Text == "Pets" and outline and outline.Thickness == 2.5,
		"p5neon: Tile: the GothamBlack label (0.2 x 84 -> 18) with a 2.5 px dark stroke")
	T.check(tile.Icon and tile.Icon.TextSize and math.abs(tile.Icon.TextSize - 84 * 0.46) < 0.01 and tile.Orb and tile.Orb.Parent == tile.Card.Body, "p5neon: Tile: the icon (0.46 x size) on a glossy orb")
	T.check(tile.Root:FindFirstChild("NeonStroke").Color == Theme.Neon.Orange, "p5neon: Tile: Color 'Pets' -> the Orange neon border")
	Mock.Click(tile.Root)
	NK.advance(0.05)
	T.eq(clicks, 1, "p5neon: Tile: a click calls the Callback")
	tile.SetBadge(true)
	T.check(NK.shown(tile.Badge), "p5neon: Tile.SetBadge shows the red dot")
	-- Icon: an emoji glyph, or an ImageLabel once Config.Icons[id] holds an asset id
	local icon = NeonKit.Icon(g, "Shop", 40)
	T.check(icon:IsA("TextLabel") and icon.Text == NeonKit.Glyphs.Shop, "p5neon: Icon(id): the emoji glyph by default")
	Config.Icons = Config.Icons or {}
	Config.Icons.SmokeIcon = "rbxassetid://123"
	local img = NeonKit.Icon(g, "SmokeIcon", 40)
	Config.Icons.SmokeIcon = nil
	T.check(img:IsA("ImageLabel") and img.Image == "rbxassetid://123", "p5neon: Icon(id): Config.Icons[id] = 'rbxassetid://n' switches to an ImageLabel")
	local orb = NeonKit.Orb(g, "Cyan", 50)
	T.check(orb.AbsoluteSize.X == 50 and orb:FindFirstChildOfClass("UICorner").CornerRadius.Scale == 0.5, "p5neon: Orb(parent, color, size): a round disc")
	-- Pill + Button
	local pill = NeonKit.Pill({ Text = "12", Glyph = "$", Color = "Green", Size = 200, Parent = g })
	pill.SetText("99")
	T.check(pill.Text.Text == "99" and pill.Coin ~= nil and pill.Card.Root:FindFirstChild("NeonStroke").Color == Theme.Neon.Green, "p5neon: Pill: coin + neon card; SetText")
	local fired = 0
	local btn = NeonKit.Button({ Text = "PLAY", Color = "Green", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(400, 400), Callback = function()
		fired = fired + 1
	end, Parent = g })
	T.check(btn:IsA("TextButton") and btn.Text == "PLAY" and btn.Font == Enum.Font.GothamBlack and btn.TextColor3 == Color3.new(1, 1, 1), "p5neon: Button: a TextButton, white GothamBlack text")
	local fx = btn:FindFirstChild("FxScale")
	Mock.FireSignal(btn, "MouseEnter")
	NK.advance(0.4)
	local hover = fx and fx.Scale or 0
	Mock.FireSignal(btn, "MouseButton1Down")
	NK.advance(0.4)
	local press = fx and fx.Scale or 0
	Mock.FireSignal(btn, "MouseButton1Up")
	Mock.FireSignal(btn, "MouseLeave")
	NK.advance(0.4)
	T.check(math.abs(hover - 1.04) < 0.02 and math.abs(press - 0.95) < 0.02, "p5neon: Button: hover 1.04 / press 0.95", string.format("%.2f / %.2f", hover, press))
	btn:SetAttribute("Disabled", true)
	NK.advance(0.1)
	Mock.Click(btn)
	NK.advance(0.05)
	local greyed = btn:FindFirstChild("NeonStroke").Color == Theme.Neon.Grey and not btn:FindFirstChild("Glow").Visible
	btn:SetAttribute("Disabled", false)
	Mock.Click(btn)
	NK.advance(0.05)
	T.check(greyed and fired == 1, "p5neon: Button: Disabled greys it out (no glow) and ignores clicks", tostring(fired))
	local outlineBtn = NeonKit.Button({ Text = "SETTINGS", Variant = "Outline", Color = "Blue", Parent = g })
	T.check(outlineBtn:FindFirstChild("NeonStroke").Color == Theme.Neon.Blue and not outlineBtn:FindFirstChild("Glow").Visible, "p5neon: Button Outline: the navy face, a neon border, no glow")

	-- SideRect == the prototype at the 4 sizes (Pets 820 x 900), Dock places a window there and follows the screen
	for _, sz in ipairs(NK.SIZES) do
		local W, H, touch = sz[1], sz[2], sz[3]
		local r = NeonKit.SideRect(820, 900, nil, nil, { Width = W, Height = H, Touch = touch })
		local p = NK.protoRect(W, H, touch, 820, 900)
		local ok = math.abs(r.x - p.x) < 0.01 and math.abs(r.y - p.y) < 0.01 and math.abs(r.w - p.w) < 0.01 and math.abs(r.h - p.h) < 0.01 and math.abs(r.scale - p.scale) < 1e-6
		T.check(ok and r.mode == ((W >= H) and "Side" or "Sheet"), string.format("p5neon: SideRect(820, 900) at %dx%d == the prototype (%s)", W, H, r.mode),
			string.format("%.1f,%.1f %.1fx%.1f s%.3f vs %.1f,%.1f %.1fx%.1f s%.3f", r.x, r.y, r.w, r.h, r.scale, p.x, p.y, p.w, p.h, p.scale))
		if W >= H then
			T.check(r.x >= 0.56 * W - r.margin - 0.5 and r.w <= 0.44 * W + 0.5, string.format("p5neon: %dx%d: docked right, <= 44%% of the width", W, H))
		else
			T.check(r.y >= 0.44 * H - 0.5 and r.h <= 0.56 * H + 0.5, string.format("p5neon: %dx%d: a bottom sheet, the top 44%% clear", W, H))
		end
	end
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(820, 900)
	holder.Parent = g
	local dock = NeonKit.Dock(holder, nil, 820, 900)
	local function docked()
		local r = dock.Rect
		local a = NK.rect(holder)
		return r and math.abs(a.x0 - r.x) < 1.01 and math.abs(a.y0 - r.y) < 1.01 and math.abs((a.x1 - a.x0) - r.w) < 1.5 and math.abs((a.y1 - a.y0) - r.h) < 1.5,
			string.format("%.0f,%.0f %.0fx%.0f vs %.0f,%.0f %.0fx%.0f", a.x0, a.y0, a.x1 - a.x0, a.y1 - a.y0, r and r.x or -1, r and r.y or -1, r and r.w or -1, r and r.h or -1)
	end
	local ok, detail = docked()
	T.check(ok, "p5neon: Dock puts the window on its SideRect (1920x1080)", detail)
	local restore = NK.screen(390, 844, true)
	NK.advance(0.1)
	ok, detail = docked()
	T.check(ok and dock.Rect.mode == "Sheet" and holder:GetAttribute("DockMode") == "Sheet", "p5neon: ...and follows a screen change (390x844: a bottom sheet)", detail)
	restore()
	NK.advance(0.1)
	g:Destroy()
	NK.advance(0.2)
	NK.KC().flushErrors("client_p5neon")
	NK.KC().flushWarnings("client_p5neon")
end)

S.client_p5stamina = guarded("client_p5stamina", function()
	local Config = NK.req("shared/Config")
	local P = Config.Physics
	T.check(P.MaxStamina == 150 and P.StaminaRegen == 45 and P.RunStaminaDrain == 14 and P.DashStaminaCost == 35, "p5stamina: Config.Physics 150 / regen 45 / drain 14 / dash 35")
	local runFor, refill, dashes = P.MaxStamina / P.RunStaminaDrain, P.MaxStamina / P.StaminaRegen, math.floor(P.MaxStamina / P.DashStaminaCost)
	T.check(math.abs(runFor - 10.7) < 0.05, "p5stamina: a full bar runs ~10.7 s", string.format("%.2f s", runFor))
	T.check(refill <= 3.5, "p5stamina: it refills in <= 3.5 s", string.format("%.2f s", refill))
	T.eq(dashes, 4, "p5stamina: 4 dashes from full")
	local bar = NK.pg():FindFirstChild("NimbusHud") and NK.pg().NimbusHud:FindFirstChild("StaminaBar", true)
	local inner = bar and bar:FindFirstChild("Inner")
	local ticks = {}
	if inner then
		for i = 1, 8 do
			local t = inner:FindFirstChild("Tick" .. i)
			if t then
				ticks[#ticks + 1] = t
			end
		end
	end
	T.eq(#ticks, 4, "p5stamina: the HUD stamina tube shows 4 thin dark ticks")
	local placed = #ticks == 4
	for i, t in ipairs(ticks) do
		placed = placed and math.abs(t.Position.X.Scale - i * 35 / 150) < 1e-6 and t.Size.X.Offset <= 3
		local r, fr = NK.rect(t), NK.rect(inner)
		placed = placed and math.abs((r.x0 + r.x1) / 2 - (fr.x0 + (fr.x1 - fr.x0) * i * 35 / 150)) < 1.5
	end
	T.check(placed, "p5stamina: ...at 35 / 70 / 105 / 140 of 150 (one per dash)")
	local LocalPlayer = game:GetService("Players").LocalPlayer
	LocalPlayer:SetAttribute(Config.Attr.Stamina, 75)
	NK.advance(1)
	local fill = inner and inner:FindFirstChild("Fill")
	T.check(fill and math.abs(fill.Size.X.Scale - 0.5) < 0.03, "p5stamina: 75 of 150 fills half the tube", fill and string.format("%.2f", fill.Size.X.Scale) or "no fill")
	LocalPlayer:SetAttribute(Config.Attr.Stamina, 150)
	NK.advance(1)
	NK.KC().flushErrors("client_p5stamina")
end)

S.client_p5hud_pills = guarded("client_p5hud_pills", function()
	local Theme = NK.req("shared/Theme")
	local Config = NK.req("shared/Config")
	local LocalPlayer = game:GetService("Players").LocalPlayer
	local oldCash, oldGems = LocalPlayer:GetAttribute(Config.Attr.Cash), LocalPlayer:GetAttribute(Config.Attr.Gems)
	LocalPlayer:SetAttribute(Config.Attr.Cash, 12400)
	LocalPlayer:SetAttribute(Config.Attr.Gems, 85)
	NK.advance(1)
	local hud = NK.pg():FindFirstChild("NimbusHud")
	local function pill(id)
		return hud and hud:FindFirstChild("Currency_" .. id, true)
	end
	local want = { Cash = "Green", Gems = "Cyan", Tokens = "Gold" }
	for _, id in ipairs({ "Cash", "Gems", "Tokens" }) do
		local row = pill(id)
		local body = row and row:FindFirstChild("Body")
		local stroke = body and body:FindFirstChild("NeonStroke")
		local grad = body and body:FindFirstChildOfClass("UIGradient")
		T.check(NK.shown(row) and stroke and stroke.Color == Theme.Neon[want[id]] and grad and grad.Color.Keypoints[1].Value == Theme.Colors.PanelTop,
			"p5hud_pills: the " .. id .. " pill is a dark navy neon pill with a " .. want[id] .. " border")
	end
	local amount = pill("Cash") and pill("Cash"):FindFirstChild("Amount")
	T.check(amount and amount.Text == "12.4K", "p5hud_pills: Cash reads 12.4K", amount and amount.Text or "none")
	-- bug batch 2 #1 (option A): thin strips stacked top-right, right-aligned, under Roblox's top bar - on a desktop and
	-- on a landscape phone alike
	local function stackedTopRight(w, h, stripMax)
		local col, ok = {}, true
		for _, id in ipairs({ "Cash", "Gems", "Tokens" }) do
			local p = pill(id)
			if p and NK.shown(p) then
				col[#col + 1] = NK.rect(p)
			else
				ok = false
			end
		end
		ok = ok and #col == 3
		for i, r in ipairs(col) do
			ok = ok and r.y0 >= (Mock.TopInset or 58) - 0.5 and r.x1 <= w + 0.5 and r.x1 >= w - 40 and r.y1 < 0.45 * h
				and (r.x1 - r.x0) <= stripMax and (r.y1 - r.y0) <= 36
			if i > 1 then
				ok = ok and r.y0 >= col[i - 1].y1 and math.abs(r.x1 - col[i - 1].x1) < 1
			end
		end
		return ok, col[1] and string.format("%.0f,%.0f - %.0f,%.0f", col[1].x0, col[1].y0, col[1].x1, col[1].y1) or "none"
	end
	local okPc, firstPc = stackedTopRight(1920, 1080, 180)
	T.check(okPc and hud:GetAttribute("CurrencyMode") == "TopRight",
		"p5hud_pills: 1920x1080: thin strips (<= 180 x 36 px) stacked top-right, right-aligned, under the top bar", firstPc)
	local restore = NK.screen(844, 390, true)
	NK.advance(1.2)
	local okPhone, firstPhone = stackedTopRight(844, 390, 150)
	T.check(okPhone and hud:GetAttribute("CurrencyMode") == "TopRight",
		"p5hud_pills: 844x390: the same strips stacked top-right (clear of the jump button at the bottom)", firstPhone)
	restore()
	NK.advance(1)
	LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash)
	LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems)
	NK.advance(0.5)
	NK.KC().flushErrors("client_p5hud_pills")
end)

S.client_p5gui_cover = guarded("client_p5gui_cover", function()
	local measured = 0
	-- a clean lobby (no other scenario's leftovers): no match / party, no open window, the toasts gone
	local KC = NK.KC()
	local LocalPlayer = game:GetService("Players").LocalPlayer
	KC.toClient("MatchState", nil)
	KC.toClient("PartyState", nil)
	LocalPlayer:SetAttribute("InMatch", false)
	LocalPlayer:SetAttribute("Downed", false)
	-- the worst case of the HUD: all three currency pills (Cash / Gems / Tokens) are on screen
	local Config = NK.req("shared/Config")
	local oldCash, oldGems = LocalPlayer:GetAttribute(Config.Attr.Cash), LocalPlayer:GetAttribute(Config.Attr.Gems)
	LocalPlayer:SetAttribute(Config.Attr.Cash, 12400)
	LocalPlayer:SetAttribute(Config.Attr.Gems, 85)
	local MC = KC.M and KC.M.MenuController
	if MC and type(MC.Close) == "function" then
		pcall(MC.Close)
	end
	NK.advance(10)
	for _, scene in ipairs(COVER) do
		for _, sz in ipairs(scene.Sizes or NK.SIZES) do
			local W, H, touch = sz[1], sz[2], sz[3]
			if touch == nil then
				touch = math.min(W, H) <= 500
			end
			local restore = NK.screen(W, H, touch)
			NK.advance(0.6)
			local okOpen, err = pcall(scene.Open, { W, H, touch })
			NK.advance(1.2)
			local label = string.format("p5gui_cover %s %dx%d", scene.Scene, W, H)
			if not okOpen then
				T.fail(label .. ": Open failed", tostring(err))
			else
				local pct, smallest, smallName, backdrop = NK.coverage()
				measured = measured + 1
				T.info(string.format("%s: %.1f%% covered, smallest text %.1f px (%s)", label, pct, smallest, smallName))
				T.check(pct <= 60, label .. ": the GUI covers <= 60% of the screen", string.format("%.1f%%", pct))
				T.check(backdrop == nil, label .. ": no full-screen Backdrop", tostring(backdrop))
				local floorPx = (H >= 1000) and 15 or 14
				T.check(smallest >= floorPx - 0.01, label .. ": the smallest text is >= " .. floorPx .. " px", string.format("%.1f px %s", smallest, smallName))
				local win = scene.Window and scene.Window()
				if win and NK.shown(win) then
					local r = NK.rect(win)
					if W >= H then
						T.check(r.x0 >= 0.5 * W - 0.5, label .. ": the window stays right of the middle (left edge >= 0.5 W)", string.format("x %.0f", r.x0))
					else
						T.check(r.y0 >= 0.44 * H - 0.5, label .. ": the window is a bottom sheet (top >= 0.44 H)", string.format("y %.0f", r.y0))
					end
				end
			end
			if scene.Close then
				pcall(scene.Close)
			end
			NK.advance(0.4)
			restore()
			NK.advance(0.4)
		end
	end
	LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash)
	LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems)
	T.check(measured >= 2 * 4, "p5gui_cover: " .. #COVER .. " scenes registered, " .. measured .. " screens measured")
	NK.KC().flushErrors("client_p5gui_cover")
	NK.KC().flushWarnings("client_p5gui_cover")
end)

return S
