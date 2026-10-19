-- smoke_p5_menu.lua: Phase 5 loading screen, main menu before spawning, settings (ARCHITECTURE_V3.md "Phase 5 build
-- contract" 7.1-7.3; menu W3). Loaded by tools/smoke.py in the server world and the client world:
--   p5menu_spawn       (server) with Config.MainMenu.Enabled a joining player has no Character until MenuPlay; a second
--                      MenuPlay (and junk arguments) does nothing; no remote -> the character appears after the 90 s
--                      fallback on the mock clock; death -> a new character after Players.RespawnTime; a player leaving
--                      before PLAY leaves nothing behind; Enabled false -> the character spawns at once; CharacterAutoLoads
--                      stays false
--   client_p5loading   the ReplicatedFirst screen: RemoveDefaultLoadingScreen called, no text before Shared.Theme, the bar
--                      never goes back, 85% while the profile is not loaded, SKIP only after 6 s, tips rotate every 5 s,
--                      Done at 100% (ProfileLoaded), at MaxSeconds and on SKIP, gone after the fade
--   client_p5menu      with the menu enabled: every ScreenGui except NimbusLoading / NimbusMainMenu / NimbusNotify is off until
--                      PLAY (incl. one created later and NimbusDash / NimbusRun / NimbusIndex / NimbusNpcDialog /
--                      NimbusTutorialPointer by name), Shift / Q do nothing before PLAY, no character before PLAY, MenuPlay
--                      fired once, camera Scriptable then Custom, Played once, the tutorial gui off before / on after, the
--                      loading screen faded by the menu, the UPDATES badge, /menu reopens it without a second MenuPlay
--   client_p5menu_mobile (phone 390x844) PLAY >= 56 px and on screen, no menu text under 14 px or off screen, SETTINGS is
--                      a bottom sheet below 0.44 H, a tap sends MenuPlay once
--   client_p5settings  sliders -> ONE SettingsSet after the 0.4 s debounce with clamped whole numbers; Graphics Low hides
--                      NC_Detail decor (emitters off) and pushes GfxLow, High restores; Shake OFF; SeenNotes on UPDATES
--
-- Every OTHER scenario runs with the menu DISABLED (contract 7.2: "what every existing smoke scenario and the mock get
-- unless a test sets Enabled"): this file sets Config.MainMenu.Enabled = false when it loads (both worlds), and on the
-- client it plays DataService's part for the loading screen (the player attribute ProfileLoaded = true) and gives the
-- mock ReplicatedFirst:RemoveDefaultLoadingScreen. Deterministic: no RNG, mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local function sharedModule(name)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local inst = shared and shared:FindFirstChild(name)
	return inst and require(inst) or nil
end

-- the default for every scenario: the menu off (today's instant spawn, nothing gated)
do
	local Config = sharedModule("Config")
	if Config and type(Config.MainMenu) == "table" then
		Config.MainMenu.Enabled = false
	end
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local Players = game:GetService("Players")

	S.p5menu_spawn = guarded("p5menu_spawn", function()
		local advance, mod = K.advance, K.mod
		local Config = K.config()
		local PS = mod("PlayerService")
		if not T.check(PS and type(PS.SpawnPlayer) == "function" and type(PS.HasSpawned) == "function",
			"p5menu: PlayerService.SpawnPlayer / HasSpawned exist") then
			return
		end
		T.eq(Players.CharacterAutoLoads, false, "p5menu: Players.CharacterAutoLoads stays false (PlayerService spawns every character)")
		local folder = K.remoteFolder and K.remoteFolder() or game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		local menuPlay = folder and folder:FindFirstChild("MenuPlay")
		if not T.check(menuPlay ~= nil, "p5menu: the MenuPlay remote exists") then
			return
		end
		local St = PS._St
		local cfg = Config.MainMenu
		local was = cfg.Enabled
		local made = {}
		local ok, err = pcall(function()
			cfg.Enabled = true
			-- 1. held until MenuPlay
			local a = Mock.AddPlayer("MenuAva", 870001)
			made[#made + 1] = a
			advance(0.6)
			T.check(a.Character == nil, "p5menu: a joining player has no character before PLAY")
			T.eq(PS.HasSpawned(a), false, "p5menu: HasSpawned is false before PLAY")
			T.check(St and St.waiting[a] == true, "p5menu: the player is recorded as waiting")
			T.eq(a:GetAttribute((Config.Attr and Config.Attr.ProfileLoaded) or "ProfileLoaded"), true,
				"p5menu: the ProfileLoaded attribute is set once the profile loaded (the loading screen's last stage)")
			Mock.FromClient(menuPlay, a)
			advance(0.5)
			local char = a.Character
			T.check(char ~= nil and char.Parent ~= nil, "p5menu: MenuPlay spawns the character")
			T.eq(PS.HasSpawned(a), true, "p5menu: HasSpawned after MenuPlay")
			T.check(St.waiting[a] == nil and St.timers[a] == nil, "p5menu: no waiting mark / fallback timer left after the spawn")
			-- 2. a second MenuPlay (also with junk) does nothing
			advance(1.5)
			Mock.FromClient(menuPlay, a)
			Mock.FromClient(menuPlay, a, "junk", 1e300, {})
			advance(0.5)
			T.check(a.Character == char, "p5menu: a second MenuPlay (or junk arguments) loads no new character")
			-- 3. death -> respawn after RespawnTime
			local hum = char:FindFirstChildOfClass("Humanoid")
			local respawn = Players.RespawnTime
			if T.check(hum ~= nil, "p5menu: the character has a Humanoid") then
				hum.Health = 0
				advance(math.max(0.2, respawn - 1))
				T.check(a.Character == char, "p5menu: no instant respawn (waits RespawnTime)")
				advance(1.6)
				local fresh = a.Character
				T.check(fresh ~= nil and fresh ~= char and fresh.Parent ~= nil, "p5menu: a dead player gets a new character after RespawnTime (" .. tostring(respawn) .. " s)")
			end
			-- 4. no MenuPlay -> the 90 s fallback
			local b = Mock.AddPlayer("MenuBen", 870002)
			made[#made + 1] = b
			advance(0.6)
			T.check(b.Character == nil, "p5menu: a player who never presses PLAY waits...")
			advance((tonumber(cfg.FallbackSeconds) or 90) - 2)
			T.check(b.Character == nil, "p5menu: ...still no character 2 s before the fallback")
			advance(2.5)
			T.check(b.Character ~= nil, "p5menu: the server spawns the character after FallbackSeconds without MenuPlay (Y13)")
			T.eq(PS.HasSpawned(b), true, "p5menu: HasSpawned after the fallback")
			Mock.FromClient(menuPlay, b)
			advance(0.4)
			-- 5. leaving before PLAY leaves nothing behind
			local c = Mock.AddPlayer("MenuCy", 870003)
			advance(0.6)
			Mock.RemovePlayer(c)
			advance(0.2)
			local left = {}
			for name, map in pairs(St) do
				if map[c] ~= nil then
					left[#left + 1] = name
				end
			end
			table.sort(left)
			T.check(#left == 0, "p5menu: a player who leaves before PLAY leaves nothing in the spawn state", table.concat(left, ", "))
			Mock.FromClient(menuPlay, c)
			advance(0.2)
			T.check(c.Character == nil, "p5menu: a MenuPlay from a player who left spawns nothing")
			-- 6. menu disabled: the character at once
			cfg.Enabled = false
			local d = Mock.AddPlayer("MenuDee", 870004)
			made[#made + 1] = d
			T.check(d.Character ~= nil, "p5menu: with Config.MainMenu.Enabled = false the character spawns at once on join")
			T.eq(PS.HasSpawned(d), true, "p5menu: HasSpawned at once with the menu disabled")
		end)
		cfg.Enabled = was
		if not ok then
			T.fail("p5menu: the spawn scenario crashed", tostring(err))
		end
		K.removePlayers(made)
		advance(0.5)
		K.flushErrors("p5menu_spawn")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CollectionService = game:GetService("CollectionService")
	local LocalPlayer = Players.LocalPlayer
	local Config = sharedModule("Config")
	local ATTR = (Config and Config.Attr and Config.Attr.ProfileLoaded) or "ProfileLoaded"
	local H = { RemoveCalls = 0 }

	-- the mock has no ReplicatedFirst:RemoveDefaultLoadingScreen: count the calls (the script pcalls it anyway)
	do
		local rf = Mock.Classes and Mock.Classes.ReplicatedFirst
		local function shim()
			H.RemoveCalls = H.RemoveCalls + 1
		end
		if rf then
			if type(rf.methods) == "table" then
				rf.methods.RemoveDefaultLoadingScreen = shim
			end
			if type(rf.own) == "table" then
				rf.own.methods = rf.own.methods or {}
				rf.own.methods.RemoveDefaultLoadingScreen = shim
			end
		end
		-- DataService's part: the profile is loaded (the loading screen finishes in the client boot)
		if LocalPlayer then
			LocalPlayer:SetAttribute(ATTR, true)
		end
	end

	function H.advance(seconds)
		if KC and KC.advance then
			KC.advance(seconds)
		else
			Mock.Advance(seconds)
		end
	end
	function H.client(name)
		return require(Mock.GetPath(ROOTS["client"] .. "/" .. name))
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.loadingScript()
		local folder = ROOTS["first"] and Mock.GetPath(ROOTS["first"]) or nil
		return folder and folder:FindFirstChild("LoadingScreen") or nil
	end
	function H.calls(name, from)
		local n = {}
		for i = (from or 0) + 1, #Mock.RemoteLog do
			local e = Mock.RemoteLog[i]
			if e.kind == "server" and e.remote == name then
				n[#n + 1] = e
			end
		end
		return n
	end
	function H.texts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
				out[#out + 1] = d
			end
		end
		return out
	end
	function H.find(root, name)
		return root and root:FindFirstChild(name, true) or nil
	end

	------------------------------------------------------------------------------------------------
	S.client_p5loading = guarded("client_p5loading", function()
		local pg = H.pg()
		local script = H.loadingScript()
		if not T.check(script ~= nil and script:IsA("LocalScript"), "p5loading: src/first/LoadingScreen.client.lua is mounted in ReplicatedFirst") then
			return
		end
		T.check(H.RemoveCalls >= 1, "p5loading: the boot called ReplicatedFirst:RemoveDefaultLoadingScreen()", tostring(H.RemoveCalls))
		T.check(pg:FindFirstChild("NimbusLoading") == nil, "p5loading: the boot's loading screen is gone (Done, faded, destroyed)")

		-- a fresh run: Theme missing at first, profile not loaded
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local theme = shared:FindFirstChild("Theme")
		LocalPlayer:SetAttribute(ATTR, nil)
		theme.Parent = nil
		local calls0 = H.RemoveCalls
		Mock.RunScript(script)
		H.advance(0.6)
		local gui = pg:FindFirstChild("NimbusLoading")
		if not T.check(gui ~= nil, "p5loading: ScreenGui NimbusLoading is built") then
			theme.Parent = shared
			LocalPlayer:SetAttribute(ATTR, true)
			return
		end
		T.check(H.RemoveCalls == calls0 + 1, "p5loading: RemoveDefaultLoadingScreen is called first thing")
		T.check(gui.DisplayOrder == 100 and gui.IgnoreGuiInset == true and gui.ResetOnSpawn == false,
			"p5loading: DisplayOrder 100, IgnoreGuiInset, ResetOnSpawn false")
		T.eq(#H.texts(gui), 0, "p5loading: no text before Shared.Theme exists (fonts only through Theme roles)")
		theme.Parent = shared
		H.advance(0.6)
		T.check(#H.texts(gui) >= 4, "p5loading: the logo, tag line, caption and tip appear once Theme arrives", tostring(#H.texts(gui)))
		local caption = H.find(gui, "Caption")
		local skip = H.find(gui, "Skip")
		local tip = H.find(gui, "Tip")
		T.check(caption ~= nil and caption.Text:find("Loading the sky", 1, true) ~= nil, "p5loading: the caption reads 'Loading the sky... n%'", caption and caption.Text or "missing")
		T.check(skip ~= nil and skip.Visible == false, "p5loading: no SKIP at first")

		-- the bar: forward only, 85% while the profile is not loaded (the clock is ~1.2 s into the run here)
		local backwards, last = false, -1
		local tip0 = tip and tip.Text or ""
		for _ = 1, 16 do -- to ~5.2 s
			H.advance(0.25)
			local p = gui:GetAttribute("Progress") or 0
			if p < last - 1e-9 then
				backwards = true
			end
			last = p
		end
		T.check(not backwards, "p5loading: the bar never goes backwards")
		T.near(last, 0.85, 0.011, "p5loading: 85% while the profile is not loaded (the other four stages done)")
		T.check(gui:GetAttribute("Done") ~= true, "p5loading: not Done without the profile")
		T.check(skip and skip.Visible == false, "p5loading: still no SKIP at ~5 s")
		H.advance(1.2)
		T.check(skip and skip.Visible == true, "p5loading: SKIP shows after Config.Loading.SkipAfter (6 s)")
		T.check(tip and tip.Text ~= "" and tip.Text ~= tip0, "p5loading: the tip changes every 5 s", tip0)
		local fill = H.find(gui, "Fill")
		local w1 = fill and fill.AbsoluteSize.X or 0
		-- the profile arrives -> 100% -> Done -> (menu disabled) faded and destroyed 2 s later
		LocalPlayer:SetAttribute(ATTR, true)
		H.advance(0.5)
		T.eq(gui:GetAttribute("Done"), true, "p5loading: Done = true at 100% (ProfileLoaded)")
		T.near(gui:GetAttribute("Progress") or 0, 1, 1e-6, "p5loading: the bar reaches 100%")
		T.check(fill and fill.AbsoluteSize.X >= w1, "p5loading: the fill only grows")
		T.check(caption and caption.Text:find("100%", 1, true) ~= nil, "p5loading: the caption says 100%", caption and caption.Text or "")
		T.check(gui.Parent ~= nil, "p5loading: still there right after Done")
		H.advance(2.8)
		T.check(gui.Parent == nil, "p5loading: with the menu disabled the screen fades and is destroyed ~2.4 s after Done")

		-- MaxSeconds without a profile
		LocalPlayer:SetAttribute(ATTR, nil)
		Mock.RunScript(script)
		H.advance(0.5)
		local g2 = pg:FindFirstChild("NimbusLoading")
		H.advance((tonumber(Config.Loading and Config.Loading.MaxSeconds) or 25) - 1.5)
		T.check(g2 and g2:GetAttribute("Done") ~= true, "p5loading: not Done before MaxSeconds")
		H.advance(1.5)
		T.check(g2 and g2:GetAttribute("Done") == true, "p5loading: Done at Config.Loading.MaxSeconds (25 s) even without the profile")
		H.advance(3)
		T.check(g2 == nil or g2.Parent == nil, "p5loading: ...and gone after the fade")

		-- SKIP
		Mock.RunScript(script)
		H.advance(6.6)
		local g3 = pg:FindFirstChild("NimbusLoading")
		local skip3 = g3 and H.find(g3, "Skip")
		if T.check(skip3 ~= nil and skip3.Visible, "p5loading: SKIP visible on the third run") then
			Mock.Click(skip3)
			H.advance(0.3)
			T.eq(g3:GetAttribute("Done"), true, "p5loading: SKIP finishes the loading screen")
		end
		LocalPlayer:SetAttribute(ATTR, true)
		H.advance(3)
		T.check(pg:FindFirstChild("NimbusLoading") == nil, "p5loading: no loading screen left behind")
		KC.flushErrors("client_p5loading")
	end)

	------------------------------------------------------------------------------------------------
	S.client_p5menu = guarded("client_p5menu", function()
		local pg = H.pg()
		local UiGate = H.client("UiGate")
		local MMC = H.client("Controllers/MainMenuController")
		local CS = H.client("ClientSettings")
		if not T.check(type(MMC.Open) == "function" and type(MMC.Play) == "function" and type(UiGate.MarkPlayed) == "function",
			"p5menu: MainMenuController.Open / Play and UiGate load") then
			return
		end
		T.eq(UiGate.HasPlayed(), true, "p5menu: with the menu disabled the boot marks PLAY at once")
		local same = true
		for i, name in ipairs({ "NimbusLoading", "NimbusMainMenu", "NimbusNotify" }) do
			same = same and UiGate.ALLOW[i] == name
		end
		T.check(same and #UiGate.ALLOW == 3, "p5menu: UiGate.ALLOW = { NimbusLoading, NimbusMainMenu, NimbusNotify }")

		-- fake guis the gate must catch by name (whatever their controllers do), enabled
		local fakes = {}
		for _, name in ipairs({ "NimbusDash", "NimbusRun", "NimbusIndex", "NimbusNpcDialog", "NimbusTutorialPointer", "NimbusTutorial" }) do
			local g = pg:FindFirstChild(name)
			if not g then
				g = Instance.new("ScreenGui")
				g.Name = name
				g.Parent = pg
				fakes[#fakes + 1] = g
			end
			g.Enabled = true
		end
		local wasOn = {}
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") then
				wasOn[g] = g.Enabled
			end
		end
		-- a loading screen for the menu to take away
		local loading = Instance.new("ScreenGui")
		loading.Name = "NimbusLoading"
		loading:SetAttribute("Done", false)
		local plate = Instance.new("Frame")
		plate.Size = UDim2.fromScale(1, 1)
		plate.Parent = loading
		loading.Parent = pg

		-- no character yet: the server holds it until MenuPlay
		local oldChar = LocalPlayer.Character
		if oldChar then
			oldChar.Parent = nil
			LocalPlayer.Character = nil
		end
		local played = 0
		local conn = UiGate.Played:Connect(function()
			played = played + 1
		end)
		local log0 = #Mock.RemoteLog
		Config.MainMenu.Enabled = true
		UiGate._ResetForTests()
		MMC._M.SentPlay = false
		MMC.Open()
		H.advance(0.2)
		local later = Instance.new("ScreenGui")
		later.Name = "NimbusLater"
		later.Parent = pg
		H.advance(0.2)
		local wrong = {}
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and not UiGate.IsAllowed(g.Name) then
				wrong[#wrong + 1] = g.Name
			end
		end
		table.sort(wrong)
		T.check(#wrong == 0, "p5menu: before PLAY every ScreenGui outside UiGate.ALLOW is off", table.concat(wrong, ", "))
		for _, name in ipairs({ "NimbusDash", "NimbusRun", "NimbusIndex", "NimbusNpcDialog", "NimbusTutorialPointer", "NimbusTutorial", "NimbusLater" }) do
			local g = pg:FindFirstChild(name)
			T.check(g ~= nil and g.Enabled == false, "p5menu: " .. name .. " is off before PLAY")
		end
		local tut = pg:FindFirstChild("NimbusTutorial")
		if tut then
			tut.Enabled = true -- its owner tries to show the tutorial panel
			H.advance(0.1)
			T.eq(tut.Enabled, false, "p5menu: the tutorial gui stays off before PLAY even when its owner switches it on")
		end
		local menuGui = pg:FindFirstChild("NimbusMainMenu")
		T.check(menuGui ~= nil and menuGui.Enabled and H.find(menuGui, "PlayButton") ~= nil, "p5menu: the main menu (NimbusMainMenu) shows a PLAY button")
		local camera = workspace.CurrentCamera
		T.eq(camera.CameraType, Enum.CameraType.Scriptable, "p5menu: the camera is Scriptable (the orbit) before PLAY")
		local cf1 = camera.CFrame.Position
		H.advance(2)
		local cf2 = camera.CFrame.Position
		T.check((cf1 - cf2).Magnitude > 1, "p5menu: the camera orbits")
		local centre = MMC._M.Orbit.Centre
		if centre then
			local flat = Vector3.new(cf2.X - centre.X, 0, cf2.Z - centre.Z).Magnitude
			T.near(flat, Config.MainMenu.OrbitRadius, 0.5, "p5menu: orbit radius = Config.MainMenu.OrbitRadius")
			T.near(cf2.Y - centre.Y, Config.MainMenu.OrbitHeight, 0.5, "p5menu: orbit height = Config.MainMenu.OrbitHeight")
		end
		-- the loading hand-off
		loading:SetAttribute("Done", true)
		H.advance(0.6)
		T.check(loading.Parent == nil, "p5menu: the menu fades the loading screen (0.4 s) and destroys it once Done")
		-- the UPDATES badge
		local badge = H.find(menuGui, "NewBadge")
		local notes = sharedModule("UpdateNotes")
		local wantBadge = (notes and notes.Latest or 0) > (CS.Get("SeenNotes") or 0)
		T.check(badge ~= nil and badge.Visible == wantBadge, "p5menu: the NEW badge on UPDATES follows Latest > SeenNotes", tostring(wantBadge))
		-- Shift / Q do nothing before PLAY
		local MC = H.client("Controllers/MovementController")
		local _ = MC
		local stamina0 = LocalPlayer:GetAttribute("Stamina")
		Mock.KeysDown.LeftShift = true
		pcall(Mock.TriggerAction, "NimbusRun", "Begin", Mock.NewInput("LeftShift", "Keyboard", "Begin"))
		pcall(Mock.TriggerAction, "NimbusDash", "Begin", Mock.NewInput("Q", "Keyboard", "Begin"))
		H.advance(0.8)
		Mock.KeysDown.LeftShift = false
		pcall(Mock.TriggerAction, "NimbusRun", "End", Mock.NewInput("LeftShift", "Keyboard", "End"))
		T.eq(#H.calls("Dash", log0), 0, "p5menu: Q (dash) does nothing before PLAY")
		local stamina1 = LocalPlayer:GetAttribute("Stamina")
		T.check(stamina0 == nil or stamina1 == nil or stamina1 >= stamina0 - 0.01, "p5menu: Shift (run) drains no stamina before PLAY")
		T.check(LocalPlayer.Character == nil, "p5menu: no character before PLAY")
		T.eq(#H.calls("MenuPlay", log0), 0, "p5menu: no MenuPlay before PLAY")
		T.eq(played, 0, "p5menu: UiGate.Played has not fired before PLAY")

		-- PLAY (Enter + a click: one MenuPlay)
		pcall(Mock.TriggerAction, "NimbusMenuPlay", "Begin", Mock.NewInput("Return", "Keyboard", "Begin"))
		Mock.Click(H.find(menuGui, "PlayButton"))
		H.advance(0.3)
		T.eq(#H.calls("MenuPlay", log0), 1, "p5menu: PLAY fires MenuPlay exactly once (Enter + click)")
		local args = H.calls("MenuPlay", log0)[1]
		T.check(args ~= nil and (args.args == nil or (args.args.n or #args.args) == 0), "p5menu: MenuPlay carries no arguments")
		T.eq(UiGate.HasPlayed(), false, "p5menu: not played until the character arrives (or 5 s)")
		-- the server spawns the character
		if oldChar then
			oldChar.Parent = workspace
			LocalPlayer.Character = oldChar
		else
			Mock.LoadCharacter(LocalPlayer)
		end
		H.advance(0.8)
		T.eq(UiGate.HasPlayed(), true, "p5menu: PLAY marks UiGate played after the character and the 0.35 s fade")
		T.eq(played, 1, "p5menu: UiGate.Played fires once")
		T.eq(camera.CameraType, Enum.CameraType.Custom, "p5menu: the camera is Custom again after PLAY")
		T.check(H.find(menuGui, "Menu") == nil, "p5menu: the menu screen is gone after PLAY")
		local back = {}
		for g, on in pairs(wasOn) do
			if g.Parent and g.Enabled ~= on then
				back[#back + 1] = g.Name
			end
		end
		table.sort(back)
		T.check(#back == 0, "p5menu: every gated gui is back as it was after PLAY", table.concat(back, ", "))
		T.check(tut == nil or tut.Enabled == true, "p5menu: the tutorial gui shows after PLAY (its owner switched it on meanwhile)")
		T.eq(later.Enabled, true, "p5menu: a gui created during the menu comes on after PLAY")

		-- /menu reopens it client-side (no second MenuPlay), PLAY closes it again
		local Dev = H.client("Controllers/DevController")
		local devFlag = pg:GetAttribute("NC_Dev")
		pg:SetAttribute("NC_Dev", true)
		H.advance(0.2)
		T.check(type(Dev.OnChat) == "function" and Dev.OnChat("/menu") == true, "p5menu: the owner's /menu opens the main menu")
		H.advance(0.3)
		T.eq(MMC.IsOpen(), true, "p5menu: the menu is open again")
		T.eq(pg:FindFirstChild("NimbusHud") and pg.NimbusHud.Enabled, false, "p5menu: /menu hides the HUD again")
		MMC.Play()
		H.advance(0.8)
		T.eq(#H.calls("MenuPlay", log0), 1, "p5menu: PLAY after /menu sends no second MenuPlay")
		T.eq(MMC.IsOpen(), false, "p5menu: ...and closes the menu")
		T.eq(played, 1, "p5menu: Played does not fire twice")
		pg:SetAttribute("NC_Dev", devFlag)
		T.eq(Dev.OnChat("/menu"), devFlag == true, "p5menu: /menu does nothing without NC_Dev")
		if MMC.IsOpen() then
			MMC.Play()
			H.advance(0.8)
		end

		conn:Disconnect()
		Config.MainMenu.Enabled = false
		for _, g in ipairs(fakes) do
			g:Destroy()
		end
		later:Destroy()
		KC.flushErrors("client_p5menu")
	end)

	------------------------------------------------------------------------------------------------
	S.client_p5settings = guarded("client_p5settings", function()
		local pg = H.pg()
		local MMC = H.client("Controllers/MainMenuController")
		local CS = H.client("ClientSettings")
		local GQ = H.client("GraphicsQuality")
		local LS = H.client("LightingStack")
		if not T.check(type(MMC.OpenSettings) == "function" and type(CS.Set) == "function" and type(GQ.Apply) == "function",
			"p5settings: MainMenuController.OpenSettings, ClientSettings and GraphicsQuality load") then
			return
		end
		-- pure rules
		T.eq(CS.Clean("Music", 7.6), 8, "p5settings: Clean rounds Music to a whole number")
		T.eq(CS.Clean("Sfx", 99), 10, "p5settings: Clean clamps Sfx to 10")
		T.eq(CS.Clean("Music", 0 / 0), nil, "p5settings: NaN refused")
		T.eq(CS.Clean("Gfx", "Ultra"), nil, "p5settings: unknown Gfx refused")
		T.eq(CS.Clean("Shake", "yes"), nil, "p5settings: Shake must be a boolean")
		T.eq(GQ.Resolve("Auto", 2), "Low", "p5settings: Auto + Roblox graphics level 1..3 = Low")
		T.eq(GQ.Resolve("Auto", 0), "High", "p5settings: Auto + Automatic = High")
		T.eq(GQ.Resolve("Low", 10), "Low", "p5settings: Low stays Low")

		MMC.OpenSettings()
		H.advance(0.3)
		local holder = MMC.Window()
		if not T.check(holder ~= nil and holder.Parent ~= nil, "p5settings: the settings window opens (MainMenuController.OpenSettings)") then
			return
		end
		T.check(holder:GetAttribute("DockMode") ~= nil, "p5settings: the window is docked by NeonKit.Dock (window rule)")
		local music = H.find(holder, "Row_Music")
		local plus, minus = music and H.find(music, "Plus"), music and H.find(music, "Minus")
		if not T.check(plus ~= nil and minus ~= nil, "p5settings: Music has - / + buttons") then
			return
		end
		local start = CS.Get("Music")
		local log0 = #Mock.RemoteLog
		for _ = 1, 3 do
			Mock.Click(plus)
			H.advance(0.1)
		end
		T.eq(CS.Get("Music"), math.min(10, start + 3), "p5settings: the slider applies locally at once")
		T.eq(#H.calls("SettingsSet", log0), 0, "p5settings: nothing sent inside the 0.4 s debounce")
		H.advance(0.5)
		local sent = H.calls("SettingsSet", log0)
		T.eq(#sent, 1, "p5settings: ONE SettingsSet after the debounce")
		local a = sent[1] and sent[1].args or {}
		T.check(a[1] == "Music" and a[2] == math.min(10, start + 3) and a[2] == math.floor(a[2]), "p5settings: SettingsSet('Music', whole number)",
			tostring(a[1]) .. " " .. tostring(a[2]))
		local log1 = #Mock.RemoteLog
		for _ = 1, 14 do
			Mock.Click(minus)
		end
		H.advance(0.6)
		sent = H.calls("SettingsSet", log1)
		T.check(#sent == 1 and sent[1].args[2] == 0, "p5settings: pressing - past 0 clamps to 0, one send", #sent .. " sends")
		local value = H.find(music, "Value")
		T.check(value and value.Text == "OFF", "p5settings: Music 0 reads OFF", value and value.Text or "")

		-- Graphics Low / High
		local decor = Instance.new("Model")
		decor.Name = "P5MenuDecor"
		local part = Instance.new("Part")
		part.Parent = decor
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = true
		emitter.Parent = part
		decor.Parent = workspace
		CollectionService:AddTag(decor, "NC_Detail")
		local low = H.find(holder, "Chip_LOW")
		if T.check(low ~= nil, "p5settings: Graphics has a LOW chip") then
			Mock.Click(low)
			H.advance(0.3)
		end
		T.eq(CS.Get("Gfx"), "Low", "p5settings: Gfx = Low")
		T.eq(GQ.Effective(), "Low", "p5settings: GraphicsQuality goes Low")
		T.check(not decor:IsDescendantOf(workspace), "p5settings: Low hides NC_Detail decor (out of the workspace)")
		T.eq(emitter.Enabled, false, "p5settings: Low turns the decor's particle emitters off")
		T.eq(LS.Top(), "GfxLow", "p5settings: Low pushes the GfxLow lighting preset")
		local late = Instance.new("Model")
		late.Name = "P5MenuLateDecor"
		late.Parent = workspace
		CollectionService:AddTag(late, "NC_Detail")
		H.advance(0.2)
		T.check(not late:IsDescendantOf(workspace), "p5settings: decor that appears while Low is hidden too")
		local high = H.find(holder, "Chip_HIGH")
		if high then
			Mock.Click(high)
			H.advance(0.3)
		end
		T.eq(GQ.Effective(), "High", "p5settings: High restores")
		T.check(decor.Parent == workspace and late.Parent == workspace, "p5settings: High puts the decor back where it was")
		T.eq(emitter.Enabled, true, "p5settings: High turns the emitters back on")
		T.check(LS.Top() ~= "GfxLow", "p5settings: High pops GfxLow")
		local auto = H.find(holder, "Chip_AUTO")
		if auto then
			Mock.Click(auto)
			H.advance(0.6)
		end
		decor:Destroy()
		late:Destroy()

		-- Shake
		local off = H.find(holder, "Chip_OFF")
		if T.check(off ~= nil, "p5settings: Camera shake has an OFF chip") then
			Mock.Click(off)
			H.advance(0.6)
		end
		T.eq(CS.Get("Shake"), false, "p5settings: Shake OFF (BattleController's shake amplitude x 0)")
		local on = H.find(holder, "Chip_ON")
		if on then
			Mock.Click(on)
			H.advance(0.6)
		end
		T.eq(CS.Get("Shake"), true, "p5settings: Shake ON again")

		-- SeenNotes on UPDATES
		local log2 = #Mock.RemoteLog
		MMC.OpenUpdates()
		H.advance(0.6)
		local notes = sharedModule("UpdateNotes")
		local seen = H.calls("SettingsSet", log2)
		local found = false
		for _, e in ipairs(seen) do
			if e.args[1] == "SeenNotes" and e.args[2] == notes.Latest then
				found = true
			end
		end
		T.check(found or (CS.Get("SeenNotes") == notes.Latest and #seen == 0), "p5settings: opening UPDATES sends SettingsSet('SeenNotes', Latest)")
		T.eq(CS.Get("SeenNotes"), notes.Latest, "p5settings: SeenNotes = UpdateNotes.Latest")
		MMC.CloseWindows()
		H.advance(0.2)
		T.check(MMC.Window() == nil, "p5settings: CloseWindows leaves nothing open")
		local _ = pg
		KC.flushErrors("client_p5settings")
	end)

	------------------------------------------------------------------------------------------------
	-- phone (390x844 touch): the menu column fits, PLAY is a big thumb target, the settings sheet keeps the top clear
	S.client_p5menu_mobile = guarded("client_p5menu_mobile", function()
		local pg = H.pg()
		local UiGate = H.client("UiGate")
		local MMC = H.client("Controllers/MainMenuController")
		local vp = Mock.Viewport
		local W, Hh = vp.X, vp.Y
		local log0 = #Mock.RemoteLog
		Config.MainMenu.Enabled = true
		UiGate._ResetForTests()
		MMC._M.SentPlay = false
		MMC.Open()
		H.advance(0.4)
		local menuGui = pg:FindFirstChild("NimbusMainMenu")
		local play = H.find(menuGui, "PlayButton")
		if T.check(play ~= nil, "p5menu phone: the PLAY button exists") then
			local p, sz = play.AbsolutePosition, play.AbsoluteSize
			T.check(sz.Y >= 56, "p5menu phone: PLAY is a big thumb target (>= 56 px tall)", tostring(sz.Y))
			T.check(p.X >= 0 and p.X + sz.X <= W and p.Y >= 0 and p.Y + sz.Y <= Hh, "p5menu phone: PLAY is fully on screen")
		end
		local small, offscreen = {}, {}
		for _, d in ipairs(menuGui:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and KC.isShown(d) then
				local scale = 1
				local cur = d
				while cur and cur ~= menuGui do
					local us = cur:FindFirstChildOfClass("UIScale")
					if us then
						scale = scale * us.Scale
					end
					cur = cur.Parent
				end
				if d.TextSize * scale < 14 - 1e-6 then
					small[#small + 1] = d.Name .. " " .. string.format("%.1f", d.TextSize * scale)
				end
				local p, sz = d.AbsolutePosition, d.AbsoluteSize
				if p.X < -1 or p.X + sz.X > W + 1 then
					offscreen[#offscreen + 1] = d.Name
				end
			end
		end
		T.check(#small == 0, "p5menu phone: no menu text under 14 px", table.concat(small, ", "))
		T.check(#offscreen == 0, "p5menu phone: no menu text runs off the screen", table.concat(offscreen, ", "))
		MMC.OpenSettings()
		H.advance(0.4)
		local holder = MMC.Window()
		if T.check(holder ~= nil, "p5menu phone: SETTINGS opens over the menu") then
			T.eq(holder:GetAttribute("DockMode"), "Sheet", "p5menu phone: the settings window is a bottom sheet")
			T.check(holder.AbsolutePosition.Y >= 0.44 * Hh - 2, "p5menu phone: the sheet keeps the top 44% clear")
		end
		MMC.CloseWindows()
		Mock.Click(play)
		H.advance(1)
		T.eq(#H.calls("MenuPlay", log0), 1, "p5menu phone: a tap on PLAY sends MenuPlay once")
		T.eq(UiGate.HasPlayed(), true, "p5menu phone: played after the tap")
		Config.MainMenu.Enabled = false
		KC.flushErrors("client_p5menu_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
