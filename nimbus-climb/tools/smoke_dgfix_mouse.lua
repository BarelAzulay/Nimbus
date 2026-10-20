-- smoke_dgfix_mouse.lua: the mouse lock option (docs/dungeon-fixes/plan.md decision 6; owner: mouse-lock). Loaded by
-- tools/smoke.py in the server world and the client world:
--   dgfixmouse_data    (server) Settings.MouseLock defaults to false (left out of the store while default); SettingsSet
--                      ("MouseLock", true) lands, is saved and survives a rejoin (GetSettings + the ProfileSync
--                      snapshot); non-boolean values (1, "true", a table, nil, NaN) are refused by SetSetting and dropped
--                      by the remote
--   client_dgfix_mouse (client) default off: no RenderStep binding, MouseBehavior untouched; a ProfileSync carrying
--                      Settings.MouseLock = true turns it on (rejoin data); LockCenter only while enabled with no hold, ONE
--                      binding "NimbusMouseLock" at RenderPriority.Camera + 1, nothing written per frame while unlocked;
--                      Hold / Release are counted per reason, releasing an unknown reason is harmless; every NeonKit.Dock
--                      window (menu Pets / Index, Care, Fusion, Arena, Dungeon, Obby, Settings) frees the cursor while open
--                      and closing it locks again; the main menu (Open .. PLAY), the loading screen, the result card, the
--                      tutorial card and a focused TextBox hold; the Settings window toggles it live (the lock engages when
--                      the window closes); the L key toggles the setting (not while typing); a touch-only device is a no-op
-- Deterministic: mock clock only, no RNG; the setting, the device flags and MouseBehavior are restored at the end.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	S.dgfixmouse_data = guarded("dgfixmouse_data", function()
		if not K.needBoot() then
			return
		end
		local advance, mod, config = K.advance, K.mod, K.config
		local DataS = mod("DataService")
		local function storeKey(userId)
			return config().Tokens.DataStoreName .. "/u_" .. userId
		end
		local function stored(userId)
			return Mock.DataStore.Data[storeKey(userId)]
		end
		local function join(name, userId)
			local p = Mock.AddPlayer(name, userId)
			advance(1.0)
			return p
		end
		local function leave(players)
			K.removePlayers(players)
			advance(3)
		end
		local UID = 966101
		local p = join("DgMouse", UID)
		local s = DataS.GetSettings(p)
		T.eq(s.MouseLock, false, "dgfix mouse data: MouseLock defaults to false")
		T.eq(DataS.Save(p), true, "dgfix mouse data: (a save)")
		T.eq((stored(UID) or {}).Settings, nil, "dgfix mouse data: default settings stay out of the store")
		local bad = {}
		for _, v in ipairs({ 1, 0, "true", "false", {}, 0 / 0 }) do
			if DataS.SetSetting(p, "MouseLock", v) ~= false then
				bad[#bad + 1] = tostring(v)
			end
		end
		if DataS.SetSetting(p, "MouseLock", nil) ~= false then
			bad[#bad + 1] = "nil"
		end
		T.check(#bad == 0 and DataS.GetSettings(p).MouseLock == false, "dgfix mouse data: SetSetting refuses non-boolean MouseLock values", table.concat(bad, ", "))
		local folder = K.remoteFolder and K.remoteFolder()
		local remote = folder and folder:FindFirstChild("SettingsSet")
		if not T.check(remote ~= nil, "dgfix mouse data: the SettingsSet remote exists") then
			leave({ p })
			return
		end
		Mock.FromClient(remote, p, "MouseLock", "yes")
		Mock.FromClient(remote, p, "MouseLock", 1)
		T.eq(DataS.GetSettings(p).MouseLock, false, "dgfix mouse data: junk MouseLock through SettingsSet is dropped")
		advance(1.2) -- the bucket refills
		Mock.FromClient(remote, p, "MouseLock", true)
		T.eq(DataS.GetSettings(p).MouseLock, true, "dgfix mouse data: SettingsSet('MouseLock', true) lands")
		T.eq(DataS.Save(p), true, "dgfix mouse data: saves")
		local st = (stored(UID) or {}).Settings
		T.check(type(st) == "table" and st.MouseLock == true, "dgfix mouse data: the store holds MouseLock = true")
		leave({ p })
		-- rejoin
		local mark = K.logSize()
		local p2 = join("DgMouse", UID)
		T.eq(DataS.GetSettings(p2).MouseLock, true, "dgfix mouse data: MouseLock = true survives a rejoin")
		DataS.Sync(p2)
		local list = K.remotesFor("ProfileSync", p2.UserId, mark)
		local snap = list[#list] and list[#list].args[1] or nil
		T.check(type(snap) == "table" and type(snap.Settings) == "table" and snap.Settings.MouseLock == true, "dgfix mouse data: the rejoin's ProfileSync carries Settings.MouseLock = true")
		-- and back off
		Mock.FromClient(remote, p2, "MouseLock", false)
		T.eq(DataS.GetSettings(p2).MouseLock, false, "dgfix mouse data: SettingsSet('MouseLock', false) lands")
		leave({ p2 })
		local st2 = (stored(UID) or {}).Settings
		T.check(st2 == nil or st2.MouseLock == false, "dgfix mouse data: OFF again saves as the default")
		K.flushErrors("dgfixmouse_data")
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
	local UIS = game:GetService("UserInputService")
	local LocalPlayer = Players.LocalPlayer
	local H = {}

	function H.client(name)
		return require(Mock.GetPath(ROOTS["client"] .. "/" .. name))
	end
	function H.mod(name)
		return (KC.M and KC.M[name]) or H.client("Controllers/" .. name)
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.advance(seconds)
		KC.advance(seconds)
	end
	function H.bindings()
		local n, names = 0, {}
		for name in pairs(Mock.RenderSteps) do
			n = n + 1
			names[#names + 1] = tostring(name)
		end
		table.sort(names)
		return n, table.concat(names, ",")
	end
	function H.holdText(ML)
		local out = {}
		for k, v in pairs(ML.Holds()) do
			out[#out + 1] = k .. "=" .. v
		end
		table.sort(out)
		return table.concat(out, ", ")
	end
	function H.press(keyName, processed)
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput(keyName, "Keyboard", "Begin"), processed or false)
	end
	-- a small profile (tutorial done: the card is put away) with the given settings
	function H.profile(settings)
		KC.toClient("ProfileSync", {
			Tokens = 900, Pets = { cloudy_dragon = 1, pebble_pup = 1 }, Equipped = { "cloudy_dragon" }, Items = {},
			Discovered = { cloudy_dragon = true, pebble_pup = true }, IndexClaimed = {},
			Stats = { Matches = 3, Wins = 1, TokensEarned = 40, Spins = 2, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 12400, Gems = 85, Berries = 1240,
			Teams = { Presets = { { "cloudy_dragon" }, {}, {} }, Active = 1, Slots = 3 },
			Settings = settings,
		})
		H.advance(0.8)
	end

	S.client_dgfix_mouse = guarded("client_dgfix_mouse", function()
		local ML = H.client("MouseLock")
		local CS = H.client("ClientSettings")
		if not T.check(type(ML) == "table" and type(ML.Start) == "function" and type(ML.Hold) == "function" and type(ML.Release) == "function"
			and type(ML.SetEnabled) == "function" and type(ML.IsEnabled) == "function" and type(ML.IsLocked) == "function",
			"dgfix mouse: client/MouseLock loads with Start / SetEnabled / IsEnabled / IsLocked / Hold / Release") then
			return
		end
		local LC, DEF = Enum.MouseBehavior.LockCenter, Enum.MouseBehavior.Default
		local saved = { UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = false, true, true
		UIS.MouseBehavior = DEF
		local ok, err = pcall(function()
			ML.Start()
			ML.Start() -- idempotent
			T.eq(ML._St.Started, true, "dgfix mouse: started (MainMenuController.Init starts it; Start twice is fine)")
			H.profile({ Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0 })
			H.advance(0.6)
			if next(ML.Holds()) ~= nil then
				T.info("dgfix mouse: holds at the start: " .. H.holdText(ML))
			end

			-- default off: no binding, nothing written
			T.eq(CS.Get("MouseLock"), false, "dgfix mouse: the setting defaults to off")
			T.eq(ML.IsEnabled(), false, "dgfix mouse: MouseLock is disabled by default")
			T.eq(ML.IsLocked(), false, "dgfix mouse: ...and not locked")
			T.eq(Mock.RenderSteps[ML.BIND], nil, "dgfix mouse: no RenderStep binding while off")
			UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition -- e.g. the camera's right-button pan
			H.advance(0.2)
			T.eq(UIS.MouseBehavior, Enum.MouseBehavior.LockCurrentPosition, "dgfix mouse: while off MouseBehavior is never written per frame")
			UIS.MouseBehavior = DEF

			-- rejoin data: a ProfileSync with Settings.MouseLock = true turns it on
			H.profile({ Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0, MouseLock = true })
			T.eq(CS.Get("MouseLock"), true, "dgfix mouse: a ProfileSync with Settings.MouseLock = true is adopted (rejoin)")
			T.eq(ML.IsEnabled(), true, "dgfix mouse: ...and MouseLock follows it")
			local preHolds = H.holdText(ML)
			T.check(preHolds == "", "dgfix mouse: no hold in the plain lobby (no window, menu, card)", preHolds)
			T.eq(ML.IsLocked(), true, "dgfix mouse: enabled + no hold = locked")
			local bind = Mock.RenderSteps[ML.BIND]
			T.check(bind ~= nil and bind.priority == Enum.RenderPriority.Camera.Value + 1, "dgfix mouse: ONE RenderStep binding at RenderPriority.Camera + 1 (after the camera)",
				bind and tostring(bind.priority) or "none")
			H.advance(0.1)
			T.eq(UIS.MouseBehavior, LC, "dgfix mouse: the binding sets MouseBehavior = LockCenter")
			UIS.MouseBehavior = DEF -- the camera scripts write Default each frame...
			H.advance(0.05)
			T.eq(UIS.MouseBehavior, LC, "dgfix mouse: ...and the binding (after the camera) puts LockCenter back each frame")
			local n0, names0 = H.bindings()

			-- holds: counted per reason; unknown reasons are harmless
			UIS.MouseIconEnabled = false
			ML.Hold("battle")
			T.eq(ML.IsLocked(), false, "dgfix mouse: Hold frees the cursor")
			T.eq(UIS.MouseBehavior, DEF, "dgfix mouse: ...MouseBehavior Default at once")
			T.eq(UIS.MouseIconEnabled, true, "dgfix mouse: ...MouseIconEnabled true")
			T.eq(Mock.RenderSteps[ML.BIND], nil, "dgfix mouse: ...and the binding is gone (nothing per frame while free)")
			UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			H.advance(0.2)
			T.eq(UIS.MouseBehavior, Enum.MouseBehavior.LockCurrentPosition, "dgfix mouse: while held MouseBehavior is not written per frame")
			UIS.MouseBehavior = DEF
			ML.Hold("battle")
			T.eq(ML.Release("battle"), true, "dgfix mouse: Release of a held reason -> true")
			T.eq(ML.IsLocked(), false, "dgfix mouse: two Holds of one reason need two Releases")
			ML.Hold("other")
			T.eq(ML.Release("battle"), true, "dgfix mouse: (second Release)")
			T.eq(ML.IsLocked(), false, "dgfix mouse: another reason still holds")
			T.eq(ML.Release("other"), true, "dgfix mouse: (Release other)")
			T.eq(ML.IsLocked(), true, "dgfix mouse: every hold released -> locked again")
			T.eq(ML.Release("battle"), false, "dgfix mouse: a third Release of 'battle' -> false")
			T.eq(ML.Release("never-held"), false, "dgfix mouse: Release of an unknown reason -> false")
			T.eq(ML.Release(nil), false, "dgfix mouse: Release(nil) -> false")
			T.eq(ML.IsLocked(), true, "dgfix mouse: ...and the lock is unchanged")
			T.eq(next(ML.Holds()), nil, "dgfix mouse: no hold left")
			H.advance(0.1)
			T.eq(UIS.MouseBehavior, LC, "dgfix mouse: LockCenter again")
			local n1, names1 = H.bindings()
			T.check(n1 == n0 and Mock.RenderSteps[ML.BIND] ~= nil, "dgfix mouse: re-locking re-binds the same single binding", names0 .. " / " .. names1)

			-- SetEnabled(false) / (true)
			ML.SetEnabled(false)
			T.check(not ML.IsLocked() and UIS.MouseBehavior == DEF and Mock.RenderSteps[ML.BIND] == nil, "dgfix mouse: SetEnabled(false) frees and unbinds")
			ML.SetEnabled(true)
			T.check(ML.IsLocked() and Mock.RenderSteps[ML.BIND] ~= nil, "dgfix mouse: SetEnabled(true) locks again")

			-- every docked window
			local function menuWin(id)
				local g = H.pg():FindFirstChild("NimbusMenu")
				return g and g:FindFirstChild("Window_" .. id)
			end
			local function inGui(guiName, holderName)
				return function()
					local g = H.pg():FindFirstChild(guiName)
					return g and g:FindFirstChild(holderName)
				end
			end
			local function closeAll()
				for _, name in ipairs({ "MenuController", "CareController", "IndexController", "FusionController", "ArenaController", "DungeonController", "ObbyController" }) do
					local m = H.mod(name)
					if m and type(m.Close) == "function" then
						pcall(m.Close)
					end
				end
				pcall(H.mod("MainMenuController").CloseWindows)
			end
			local cleared = {}
			for f = 1, 12 do
				cleared[f] = f <= 4
			end
			local WINDOWS = {
				{ "menu:Pets", function() H.mod("MenuController").Open("Pets", {}) end, function() return menuWin("Inventory") end },
				{ "menu:Index", function() H.mod("MenuController").Open("Index", {}) end, inGui("NimbusIndex", "Window_Index") },
				{ "care:Feed", function() H.mod("CareController").Open("Feed", { Slot = 4 }) end, inGui("NimbusCare", "Window_Care") },
				{ "fusion", function() H.mod("FusionController").Open("Upgrade", {}) end, inGui("NimbusFusion", "Window_Fusion") },
				{ "arena", function() H.mod("ArenaController").OpenArena("Duels") end, inGui("NimbusArena", "Window_Arena") },
				{ "dungeon", function()
					KC.toClient("DungeonState", "Lobby", { Parties = {}, Record = { Best = 4, Cleared = cleared, Runs = 12, Clears = 7 } })
					H.mod("DungeonController").Open(3)
				end, inGui("NimbusDungeon", "Window_Dungeon") },
				{ "obby", function() H.mod("ObbyController").Open() end, inGui("NimbusObby", "Window_Obby") },
				{ "settings", function() H.mod("MainMenuController").OpenSettings() end, function() return (H.mod("MainMenuController").Window()) end },
			}
			for _, w in ipairs(WINDOWS) do
				closeAll()
				H.advance(0.6)
				local okOpen, errOpen = pcall(w[2])
				H.advance(0.6)
				local holder = w[3]()
				if T.check(okOpen and holder ~= nil and holder.Visible, "dgfix mouse " .. w[1] .. ": the window opens", tostring(errOpen)) then
					T.check(not ML.IsLocked() and UIS.MouseBehavior == DEF and Mock.RenderSteps[ML.BIND] == nil, "dgfix mouse " .. w[1] .. ": the open docked window frees the cursor", H.holdText(ML))
					local found = false
					for key in pairs(ML.Holds()) do
						if key:find("Dock:" .. holder.Name, 1, true) == 1 then
							found = true
						end
					end
					T.check(found, "dgfix mouse " .. w[1] .. ": the hold is the window's NeonKit.Dock hold", H.holdText(ML))
				end
				closeAll()
				H.advance(0.6)
				T.check(ML.IsLocked(), "dgfix mouse " .. w[1] .. ": closing the window locks again", H.holdText(ML))
				H.advance(0.05)
				T.eq(UIS.MouseBehavior, LC, "dgfix mouse " .. w[1] .. ": ...LockCenter")
			end
			-- a destroyed holder releases too
			local NeonKit = H.client("UI/NeonKit")
			local g = Instance.new("ScreenGui")
			g.Name = "DgMouseDock"
			g.Parent = H.pg()
			local f = Instance.new("Frame")
			f.Name = "Window_DgMouse"
			f.Parent = g
			NeonKit.Dock(f, nil, 600, 600)
			T.eq(ML.IsLocked(), false, "dgfix mouse: a new docked window (Visible) holds")
			g.Enabled = false
			T.eq(ML.IsLocked(), true, "dgfix mouse: ...its ScreenGui disabled releases")
			g.Enabled = true
			T.eq(ML.IsLocked(), false, "dgfix mouse: ...enabled again holds")
			f:Destroy()
			T.eq(ML.IsLocked(), true, "dgfix mouse: ...destroying the holder releases")
			g:Destroy()

			-- the Settings window: live toggle, the lock engages when the window closes
			local MMC = H.mod("MainMenuController")
			MMC.OpenSettings()
			H.advance(0.4)
			local holder = MMC.Window()
			local row = holder and holder:FindFirstChild("Row_MouseLock", true)
			if T.check(row ~= nil, "dgfix mouse: the Settings window has the Mouse lock row") then
				local offChip = row:FindFirstChild("Chip_OFF", true)
				Mock.Click(offChip)
				H.advance(0.6)
				T.check(CS.Get("MouseLock") == false and ML.IsEnabled() == false, "dgfix mouse: OFF in the window applies at once")
				local onChip = row:FindFirstChild("Chip_ON", true)
				local log0 = #Mock.RemoteLog
				Mock.Click(onChip)
				T.eq(ML.IsEnabled(), true, "dgfix mouse: ON in the window applies at once")
				T.eq(ML.IsLocked(), false, "dgfix mouse: ...but the open window keeps the cursor free")
				H.advance(0.6)
				local sent = KC.serverCalls("SettingsSet", log0)
				T.check(#sent == 1 and sent[1].args[1] == "MouseLock" and sent[1].args[2] == true, "dgfix mouse: ...one SettingsSet('MouseLock', true) persists it", #sent .. " sends")
			end
			MMC.CloseWindows()
			H.advance(0.2)
			T.eq(ML.IsLocked(), true, "dgfix mouse: closing the Settings window engages the lock")

			-- the main menu (Open .. PLAY)
			MMC.Open()
			H.advance(0.5)
			T.check(not ML.IsLocked() and (ML.Holds().MainMenu or 0) == 1, "dgfix mouse: the main menu frees the cursor", H.holdText(ML))
			MMC.Play()
			H.advance(1.5)
			T.check(ML.IsLocked() and ML.Holds().MainMenu == nil, "dgfix mouse: after PLAY the lock is back", H.holdText(ML))

			-- the loading screen
			local loading = Instance.new("ScreenGui")
			loading.Name = "NimbusLoading"
			loading.Parent = H.pg()
			H.advance(0.05)
			T.eq(ML.IsLocked(), false, "dgfix mouse: the loading screen frees the cursor")
			loading:Destroy()
			H.advance(0.05)
			T.eq(ML.IsLocked(), true, "dgfix mouse: ...gone -> locked")

			-- the result card (NotifyController publishes ResultCardLeft while it is open)
			local notify = H.pg():FindFirstChild("NimbusNotify")
			if T.check(notify ~= nil, "dgfix mouse: NimbusNotify exists") then
				local old = notify:GetAttribute("ResultCardLeft")
				notify:SetAttribute("ResultCardLeft", 1200)
				T.eq(ML.IsLocked(), false, "dgfix mouse: the open result card frees the cursor")
				notify:SetAttribute("ResultCardLeft", 0)
				T.eq(ML.IsLocked(), true, "dgfix mouse: ...closed -> locked")
				notify:SetAttribute("ResultCardLeft", old)
			end

			-- the tutorial card (the folded bubble does not hold)
			local tut = H.pg():FindFirstChild("NimbusTutorial")
			local fake = nil
			if not tut then
				fake = Instance.new("ScreenGui")
				fake.Name = "NimbusTutorial"
				local r = Instance.new("Frame")
				r.Name = "TutorialPanel"
				r.Visible = false
				r.Parent = fake
				local sl = Instance.new("Frame")
				sl.Name = "Slide"
				sl.Parent = r
				local mn = Instance.new("Frame")
				mn.Name = "Main"
				mn.Parent = sl
				fake.Parent = H.pg()
				tut = fake
			end
			local root = tut:FindFirstChild("TutorialPanel")
			local main = root and root:FindFirstChild("Slide") and root.Slide:FindFirstChild("Main")
			if T.check(root ~= nil and main ~= nil, "dgfix mouse: the tutorial card tree TutorialPanel > Slide > Main") then
				local rv, mv = root.Visible, main.Visible
				root.Visible, main.Visible = false, true
				T.eq(ML.IsLocked(), true, "dgfix mouse: tutorial card away -> no hold")
				root.Visible = true
				T.eq(ML.IsLocked(), false, "dgfix mouse: the tutorial card shown frees the cursor")
				main.Visible = false
				T.eq(ML.IsLocked(), true, "dgfix mouse: ...folded into the bubble -> locked")
				root.Visible, main.Visible = rv, mv
			end
			if fake then
				fake:Destroy()
			end
			H.advance(0.05)

			-- a focused TextBox (chat)
			Mock.FireSignal(UIS, "TextBoxFocused", Instance.new("TextBox"))
			T.eq(ML.IsLocked(), false, "dgfix mouse: a focused TextBox frees the cursor")
			Mock.FireSignal(UIS, "TextBoxFocusReleased", Instance.new("TextBox"))
			T.eq(ML.IsLocked(), true, "dgfix mouse: ...focus released -> locked")

			-- the L key
			T.eq(ML.KEY_NAME, "L", "dgfix mouse: the quick toggle key is L")
			H.press("L", true)
			T.eq(ML.IsEnabled(), true, "dgfix mouse: L while typing (gameProcessed) does nothing")
			local log1 = #Mock.RemoteLog
			H.press("L", false)
			T.check(ML.IsEnabled() == false and CS.Get("MouseLock") == false and not ML.IsLocked(), "dgfix mouse: L toggles the setting off")
			H.advance(0.6)
			local sentL = KC.serverCalls("SettingsSet", log1)
			T.check(#sentL == 1 and sentL[1].args[2] == false, "dgfix mouse: ...and saves it (SettingsSet)", #sentL .. " sends")
			H.press("L", false)
			H.advance(0.6)
			T.check(ML.IsEnabled() and ML.IsLocked(), "dgfix mouse: L again turns it back on")

			-- a touch-only device: no effect
			UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = true, false, false
			H.advance(0.05)
			T.check(not ML.IsLocked() and Mock.RenderSteps[ML.BIND] == nil, "dgfix mouse: touch-only device -> no lock, no binding (enabled or not)")
			UIS.MouseBehavior = DEF
			H.advance(0.2)
			T.eq(UIS.MouseBehavior, DEF, "dgfix mouse: ...MouseBehavior untouched on touch")
			H.press("L", false)
			T.eq(ML.IsEnabled(), true, "dgfix mouse: ...and the L key does nothing there")
			UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = false, true, true
			H.advance(0.05)
			T.eq(ML.IsLocked(), true, "dgfix mouse: back on keyboard + mouse -> locked")

			-- one binding in total
			local n2, names2 = H.bindings()
			T.check(n2 == n0, "dgfix mouse: still only the one RenderStep binding of MouseLock", names2)
		end)
		T.check(ok, "client_dgfix_mouse ran to the end", tostring(err))
		-- restore: setting off, no binding, device flags, cursor
		pcall(CS.Set, "MouseLock", false)
		H.advance(0.6)
		pcall(ML.SetEnabled, false)
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = saved[1], saved[2], saved[3]
		UIS.MouseBehavior = Enum.MouseBehavior.Default
		UIS.MouseIconEnabled = true
		T.check(Mock.RenderSteps[ML.BIND] == nil, "dgfix mouse: restored (off, no binding)")
		KC.flushErrors("client_dgfix_mouse")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
