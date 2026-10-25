-- smoke_bug2_tutset.lua: bug batch 2, lane tutorial-settings (player reports #23, #24, #21). Loaded by tools/smoke.py in
-- the server world and the client world:
--   bug2tut_raidstep      (server, #24 "the tutorial tells a new player to wait 20 min for the boss raid") the raid step
--                         (index 18) is informational: its payload has AlsoNext + "Got it!" and a hint without a raid
--                         countdown; standing at the forum with no raid it waits; stepping onto the Boss Raid floor
--                         completes it (chapter 3 reward paid once, no bonus toast without a raid); "Next" completes it
--                         for a player anywhere; "Next" is still refused on a step without AlsoNext ("team"); a stored
--                         mid-step profile (Step 18, Done) whose player already stands on the floor finishes on load (not
--                         stuck); a live raid seen in the arena completes it with the "Bonus!" toast
--   bug2tut_mousedata     (server, #21 "mouse lock on gameplay") Settings.MouseLock: a new profile is true (kept out of the
--                         store while default); a stored Settings table WITHOUT MouseLock (saved before the option) loads
--                         as true; a stored false WITHOUT the P5MouseLock marker (the old default written along with
--                         another setting) loads as true ONCE and the store gets true + the marker; a false the player
--                         sets (SetSetting marks it) or a stored false WITH the marker loads as false and stays false
--                         through a save and a rejoin
--   client_bug2tut_portrait (client, #23 "the tutorial helper animation stops when you close the windows") the folded
--                         bubble's portrait camera keeps moving (about 15 updates a second, PORTRAIT_FOLDED_STEP) and the
--                         open card's at about 30 (PORTRAIT_STEP)
--   client_bug2tut_raidnext (client, #24) the raid step shows the hint line AND a "Got it!" Next button; clicking it sends
--                         TutorialEvent("Next")
--   client_bug2tut_mouse  (client, #21) a profile without Settings.MouseLock enables the lock; the Settings row reads
--                         "Mouse lock (recommended)" with ON selected; overlays that are not docked windows hold the
--                         cursor while shown: MenuController's RouletteStage / OddsPopup (NimbusMenu) and the NPC dialog
--                         card (NimbusNpcDialog.NpcDialog); the first lock of a session that lasts 0.5 s shows a
--                         "press L to free the cursor" pill (NimbusMouseLockHint) for 6 s, once, gone at once on a hold
-- Deterministic: mock clock only, no RNG; the setting, the device flags and the cursor are restored at the end.
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
	local userSeq = 0

	local function requireAt(key)
		local inst = K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end

	local function join(prefix)
		userSeq = userSeq + 1
		local p = Mock.AddPlayer(prefix .. userSeq, 982000 + userSeq)
		K.advance(1.0)
		return p
	end

	local function leave(p)
		if p and p.Parent then
			K.removePlayers({ p })
		end
		K.advance(1.0)
	end

	S.bug2tut_raidstep = guarded("bug2tut_raidstep", function()
		if not K.needBoot() then
			return
		end
		local advance, mod, waitFor = K.advance, K.mod, K.waitFor
		local TSv = mod("TutorialService")
		local DataS = mod("DataService")
		local BS = requireAt("server/Services/BattleService")
		local AB = requireAt("server/Services/ArenaBuilder")
		local Steps = requireAt("shared/TutorialSteps")
		local info = AB and AB.GetInfo and AB.GetInfo() or nil
		if not T.check(TSv and DataS and BS and Steps and type(info) == "table" and type(info.Floor) == "table" and typeof(info.Floor.CFrame) == "CFrame",
			"bug2 raid step: TutorialService, DataService, BattleService, TutorialSteps and ArenaInfo.Floor are there") then
			return
		end
		local errors0 = #Mock.Errors
		local RAID = Steps.IndexOf.raid
		local NEXT = Steps.ChapterStart[4]
		T.eq(RAID, 18, "bug2 raid step: the raid step keeps index 18 (saved progress lands on it)")
		local function stepId(p)
			local st = TSv.GetState(p)
			return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
		end
		local function onStep(p, index)
			DataS.SetTeam(p, 1, {})
			DataS.SetTutorial(p, { Step = index, Done = true, Gifted = true })
			TSv.Reload(p)
			advance(0.6)
		end
		local forum = info.Spawn * CFrame.new(0, 3, 0)
		local onFloor = info.Floor.CFrame * CFrame.new(12, 3, -10)
		local src = K.moduleInstance("server/Services/TutorialService")
		local reward = 500
		do
			local okSrc, text = pcall(function()
				return src and src.Source
			end)
			reward = (okSrc and type(text) == "string" and tonumber(text:match("local ARENA_FINISH_TOKENS = (%d+)"))) or reward
		end

		-- 1. the payload: AlsoNext, "Got it!", no countdown; at the forum with no raid it waits
		local p = join("RaidStep")
		Mock.Teleport(p, forum)
		onStep(p, RAID)
		T.eq(stepId(p), "raid", "bug2 raid step: (setup) a player on 'raid', at the arena forum")
		local st = TSv.GetState(p)
		T.check(st and st.AlsoNext == true and st.Button == "Got it!" and st.CompleteOn == "RaidFloor",
			"bug2 raid step: the payload has AlsoNext + a 'Got it!' button (CompleteOn RaidFloor)", st and (tostring(st.CompleteOn) .. " / " .. tostring(st.AlsoNext)))
		T.check(st and type(st.Hint) == "string" and not st.Hint:find("min", 1, true) and not st.Hint:find("Next Boss Raid", 1, true),
			"bug2 raid step: the hint has no raid countdown", st and tostring(st.Hint))
		T.check(st and tostring(st.Text):find("the board shows the timer", 1, true) ~= nil, "bug2 raid step: the text says the board shows the raid timer", st and tostring(st.Text))
		advance(2.5)
		T.eq(stepId(p), "raid", "bug2 raid step: no raid, not on the floor: it waits")

		-- 2. stepping onto the raid floor completes it (the reward once, no bonus without a raid)
		local tokens0 = DataS.GetTokens(p)
		local mark = K.logSize()
		Mock.Teleport(p, onFloor)
		waitFor(function()
			return stepId(p) ~= "raid"
		end, 3)
		st = TSv.GetState(p)
		T.check(st and st.Step == NEXT and st.Chapter == 4, "bug2 raid step: standing on the Boss Raid floor completes 'raid' (on to chapter 4)", st and tostring(st.Id))
		T.eq(DataS.GetTokens(p) - tokens0, reward, "bug2 raid step: ...and pays the battle chapter's reward (" .. reward .. ") once")
		T.check(not K.notified(p, "Bonus", nil, mark), "bug2 raid step: ...no bonus toast without a live raid")
		leave(p)

		-- 3. Next completes it anywhere; Next on a step without AlsoNext is still refused
		local q = join("RaidNext")
		Mock.Teleport(q, CFrame.new(K.config().Lobby.Origin + Vector3.new(12, 4, 12)))
		onStep(q, RAID)
		T.eq(stepId(q), "raid", "bug2 raid step: (setup) a second player on 'raid' in the lobby")
		local okNext = TSv.HandleEvent(q, "Next")
		advance(0.4)
		T.check(okNext == true and stepId(q) == Steps.Steps[NEXT].Id, "bug2 raid step: 'Next' completes 'raid' (no 20 minute wait)", tostring(stepId(q)))
		onStep(q, Steps.IndexOf.team)
		T.eq(stepId(q), "team", "bug2 raid step: (setup) the same player back on 'team'")
		local okTeam, why = TSv.HandleEvent(q, "Next")
		advance(0.4)
		T.check(okTeam == false and stepId(q) == "team", "bug2 raid step: 'Next' is still refused on a step without AlsoNext", tostring(why))
		leave(q)

		-- 4. an existing profile stored mid-step (Step 18, Done) whose player stands on the floor finishes on load
		local r = join("RaidStored")
		Mock.Teleport(r, onFloor)
		DataS.SetTeam(r, 1, {})
		DataS.SetTutorial(r, { Step = RAID, Done = true, Gifted = true })
		TSv.Reload(r)
		waitFor(function()
			return stepId(r) ~= "raid"
		end, 2)
		T.eq(stepId(r), Steps.Steps[NEXT].Id, "bug2 raid step: a profile saved on 'raid' (Step 18) is not stuck: on the floor it finishes on load")
		leave(r)

		-- 5. a live raid seen in the arena: completes, with the bonus toast
		local w = join("RaidBonus")
		Mock.Teleport(w, forum)
		onStep(w, RAID)
		T.eq(stepId(w), "raid", "bug2 raid step: (setup) a player on 'raid' at the forum")
		mark = K.logSize()
		local okRaid = BS.StartRaid(nil)
		waitFor(function()
			return stepId(w) ~= "raid"
		end, 3)
		T.check(okRaid == true, "bug2 raid step: (setup) a raid opens")
		T.eq(stepId(w), Steps.Steps[NEXT].Id, "bug2 raid step: a live raid seen in the arena completes 'raid' too")
		T.check(K.notified(w, "Bonus", nil, mark), "bug2 raid step: ...with the 'Bonus!' toast")
		pcall(BS.EndRaid)
		waitFor(function()
			return BS.GetRaidStatus() == nil
		end, 20)
		leave(w)

		local mine = 0
		for i = errors0 + 1, #Mock.Errors do
			if tostring(Mock.Errors[i].msg):find("Tutorial", 1, true) then
				mine = mine + 1
			end
		end
		T.eq(mine, 0, "bug2 raid step: no script errors from TutorialService")
		K.flushErrors("bug2tut_raidstep")
	end)

	S.bug2tut_mousedata = guarded("bug2tut_mousedata", function()
		if not K.needBoot() then
			return
		end
		local advance = K.advance
		local DataS = K.mod("DataService")
		local function storeKey(userId)
			return K.config().Tokens.DataStoreName .. "/u_" .. userId
		end
		local function stored(userId)
			return Mock.DataStore.Data[storeKey(userId)]
		end
		local function joinAs(name, userId)
			local p = Mock.AddPlayer(name, userId)
			advance(1.0)
			return p
		end
		local function leaveAll(p)
			K.removePlayers({ p })
			advance(3)
		end
		local UID = 982901
		local p = joinAs("MouseNew", UID)
		T.eq(DataS.GetSettings(p).MouseLock, true, "bug2 mouse data: a new profile has MouseLock = true")
		T.eq(DataS.Save(p), true, "bug2 mouse data: (a save)")
		T.eq((stored(UID) or {}).Settings, nil, "bug2 mouse data: ...and the default stays out of the store")
		-- another setting changed: the stored table then carries every key
		T.eq(DataS.SetSetting(p, "Music", 3), true, "bug2 mouse data: (Music 3)")
		leaveAll(p)
		local rec = stored(UID)
		if not T.check(type(rec) == "table" and type(rec.Settings) == "table" and rec.Settings.MouseLock == true,
			"bug2 mouse data: a non-default Settings table is stored whole (MouseLock true)") then
			return
		end
		-- a save from before the option: Settings without MouseLock -> ON, once and for good
		rec.Settings.MouseLock = nil
		p = joinAs("MouseNew", UID)
		T.eq(DataS.GetSettings(p).MouseLock, true, "bug2 mouse data: a stored Settings table without MouseLock loads as true")
		T.eq(DataS.GetSettings(p).Music, 3, "bug2 mouse data: ...and keeps its other keys (Music 3)")
		leaveAll(p)
		-- a save from the last days before this release: the whole Settings table with MouseLock = false (the old
		-- default, written because Music was set) and no P5MouseLock marker -> ON once, written back with the marker
		rec = stored(UID)
		if not T.check(type(rec) == "table", "bug2 mouse data: (the record is stored)") then
			return
		end
		rec.Settings = { Music = 3, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 2, MouseLock = false }
		if type(rec.Migrations) == "table" then
			rec.Migrations.P5MouseLock = nil
		end
		p = joinAs("MouseNew", UID)
		T.eq(DataS.GetSettings(p).MouseLock, true, "bug2 mouse data: a stored false WITHOUT the P5MouseLock marker loads as true (once)")
		T.eq(DataS.GetSettings(p).SeenNotes, 2, "bug2 mouse data: ...and keeps its other keys (SeenNotes 2)")
		T.eq(DataS.IsMigrated(p, "P5MouseLock"), true, "bug2 mouse data: ...and marks P5MouseLock")
		T.eq(DataS.Save(p), true, "bug2 mouse data: (a save)")
		rec = stored(UID) or {}
		T.check(type(rec.Settings) == "table" and rec.Settings.MouseLock == true and type(rec.Migrations) == "table" and rec.Migrations.P5MouseLock == true,
			"bug2 mouse data: ...the store holds MouseLock = true and the marker")
		-- a saved false stays false: the player's own choice marks the step done
		T.eq(DataS.SetSetting(p, "MouseLock", false), true, "bug2 mouse data: (the player turns it off)")
		leaveAll(p)
		rec = stored(UID) or {}
		T.eq((rec.Settings or {}).MouseLock, false, "bug2 mouse data: the store holds MouseLock = false")
		T.eq((rec.Migrations or {}).P5MouseLock, true, "bug2 mouse data: ...with the P5MouseLock marker")
		p = joinAs("MouseNew", UID)
		T.eq(DataS.GetSettings(p).MouseLock, false, "bug2 mouse data: a stored false WITH the marker loads as false (never flipped)")
		T.eq(DataS.Save(p), true, "bug2 mouse data: (a save)")
		T.eq(((stored(UID) or {}).Settings or {}).MouseLock, false, "bug2 mouse data: ...and stays false through a save")
		leaveAll(p)
		K.flushErrors("bug2tut_mousedata")
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
	function H.shared(name)
		return require(Mock.GetPath(ROOTS["shared"] .. "/" .. name))
	end
	function H.mod(name)
		return (KC.M and KC.M[name]) or H.client("Controllers/" .. name)
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.find(root, name)
		return root and root:FindFirstChild(name, true) or nil
	end
	-- a TutorialState payload built like TutorialService.buildPayload (AlsoNext included)
	function H.payload(index, over)
		local Steps = H.shared("TutorialSteps")
		local Config = KC.env()
		local step = Steps.Steps[index]
		local text = step.Text:gsub("{GiftTokens}", tostring(Config.Tutorial.GiftTokens))
		text = text:gsub("{FinishTokens}", tostring(Config.Tutorial.FinishReward.Tokens))
		local st = {
			Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = text, Target = nil,
			CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, AlsoNext = step.AlsoNext == true,
			Gift = step.Gift == true, Chapter = step.Chapter, Done = false, Completed = false, Skipped = false, Reward = 0,
		}
		for k, v in pairs(over or {}) do
			st[k] = v
		end
		return st
	end
	function H.restoreTutorial(saved)
		if saved then
			KC.toClient("TutorialState", saved)
		else
			KC.toClient("TutorialState", H.payload(1, { Done = true }))
		end
		KC.advance(1.5)
	end

	S.client_bug2tut_portrait = guarded("client_bug2tut_portrait", function()
		local TC = H.mod("TutorialController")
		local tut = H.pg() and H.pg():FindFirstChild("NimbusTutorial")
		if not T.check(type(TC) == "table" and type(TC.Step) == "function" and tut ~= nil, "bug2 portrait: TutorialController.Step and NimbusTutorial are there") then
			return
		end
		local saved = TC.GetState()
		KC.toClient("TutorialState", H.payload(1))
		KC.advance(3)
		local main = H.find(tut, "Main")
		if main and not main.Visible then
			local toggle = H.find(tut, "Toggle")
			if toggle then
				Mock.Click(toggle) -- open the card first (auto-folded on this screen)
				KC.advance(1)
			end
		end
		local cam = H.find(tut, "PortraitCamera")
		if not T.check(cam ~= nil and cam:IsA("Camera"), "bug2 portrait: the portrait has its camera (PortraitCamera)") then
			H.restoreTutorial(saved)
			return
		end
		-- counts the frames (of 60 at 60 fps, driven straight through TutorialController.Step) that moved the camera
		local function moves()
			local n, last = 0, cam.CFrame.Position
			for _ = 1, 60 do
				TC.Step(1 / 60)
				local now = cam.CFrame.Position
				if (now - last).Magnitude > 1e-5 then
					n = n + 1
				end
				last = now
			end
			return n
		end
		local open = moves()
		T.check(main and main.Visible, "bug2 portrait: (setup) the card is open")
		T.check(open >= 20 and open <= 32, "bug2 portrait: the open card's portrait moves about 30 times a second (PORTRAIT_STEP)", open .. " moves")
		local fold = H.find(tut, "Fold")
		if fold then
			Mock.Click(fold)
		end
		KC.advance(1)
		T.check(main and not main.Visible, "bug2 portrait: (setup) folded into the bubble")
		local folded = moves()
		T.check(folded >= 10 and folded <= 17, "bug2 portrait: the folded bubble keeps animating, about 15 times a second (PORTRAIT_FOLDED_STEP)", folded .. " moves")
		-- a window on top also folds the card: the bubble still flaps
		local toggle = H.find(tut, "Toggle")
		if toggle then
			Mock.Click(toggle) -- unfold again
			KC.advance(1)
		end
		local MC = H.mod("MenuController")
		if MC and type(MC.Open) == "function" then
			MC.Open("Pets", {})
			KC.advance(1)
			local covered = moves()
			T.check(main and not main.Visible and covered >= 10, "bug2 portrait: with a menu window open the folded bubble still animates", covered .. " moves")
			pcall(MC.Close)
			KC.advance(1)
		end
		H.restoreTutorial(saved)
		KC.flushErrors("client_bug2tut_portrait")
	end)

	S.client_bug2tut_raidnext = guarded("client_bug2tut_raidnext", function()
		local TC = H.mod("TutorialController")
		local Steps = H.shared("TutorialSteps")
		local tut = H.pg() and H.pg():FindFirstChild("NimbusTutorial")
		if not T.check(type(TC) == "table" and tut ~= nil and Steps.IndexOf.raid ~= nil, "bug2 raid next: TutorialController, NimbusTutorial and the raid step are there") then
			return
		end
		local saved = TC.GetState()
		KC.toClient("TutorialState", H.payload(Steps.IndexOf.raid))
		KC.advance(3)
		local main = H.find(tut, "Main")
		if main and not main.Visible then
			local toggle = H.find(tut, "Toggle")
			if toggle then
				Mock.Click(toggle)
				KC.advance(1)
			end
		end
		local nextButton, hint = nil, H.find(tut, "Hint")
		for _, d in ipairs(tut:GetDescendants()) do
			if d:IsA("TextButton") and d.Name == "Next" then
				nextButton = d
			end
		end
		T.check(nextButton ~= nil and nextButton.Visible and nextButton.Text == "Got it!", "bug2 raid next: the raid step shows a 'Got it!' Next button",
			nextButton and (tostring(nextButton.Visible) .. " '" .. tostring(nextButton.Text) .. "'") or "none")
		T.check(hint ~= nil and hint.Visible and tostring(hint.Text):find("raid floor", 1, true) ~= nil, "bug2 raid next: ...next to the hint line", hint and hint.Text or "none")
		if nextButton and nextButton.Visible then
			local mark = #Mock.RemoteLog
			local function sent()
				for _, e in ipairs(KC.serverCalls("TutorialEvent", mark)) do
					if e.args[1] == "Next" then
						return true
					end
				end
				return false
			end
			Mock.Click(nextButton) -- the first press may only finish the typewriter
			KC.advance(0.4)
			if not sent() then
				Mock.Click(nextButton)
				KC.advance(0.4)
			end
			T.check(sent(), "bug2 raid next: clicking it sends TutorialEvent('Next')")
		end
		H.restoreTutorial(saved)
		KC.flushErrors("client_bug2tut_raidnext")
	end)

	S.client_bug2tut_mouse = guarded("client_bug2tut_mouse", function()
		local ML = H.client("MouseLock")
		local CS = H.client("ClientSettings")
		if not T.check(type(ML) == "table" and type(ML.Holds) == "function" and type(CS) == "table", "bug2 mouse: client/MouseLock and ClientSettings load") then
			return
		end
		local saved = { UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = false, true, true
		local function profile(settings)
			KC.toClient("ProfileSync", {
				Tokens = 900, Pets = { cloudy_dragon = 1 }, Equipped = { "cloudy_dragon" }, Items = {},
				Discovered = { cloudy_dragon = true }, IndexClaimed = {},
				Stats = { Matches = 3, Wins = 1, TokensEarned = 40, Spins = 2, BestTimes = {} },
				Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
				Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 12400, Gems = 85, Berries = 1240,
				Teams = { Presets = { { "cloudy_dragon" }, {}, {} }, Active = 1, Slots = 3 },
				Settings = settings,
			})
			KC.advance(0.8)
		end
		local ok, err = pcall(function()
			ML.Start()
			-- a saved OFF first (so a leftover local change from an earlier scenario is dropped), then a profile that never
			-- had the key (a new player / a save from before the option): ON
			profile({ Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0, MouseLock = false })
			T.eq(ML.IsEnabled(), false, "bug2 mouse: (setup) a saved OFF is off")
			profile({ Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 3 })
			T.eq(CS.Get("MouseLock"), true, "bug2 mouse: a profile without Settings.MouseLock reads ON")
			T.eq(ML.IsEnabled(), true, "bug2 mouse: ...and the lock is enabled")

			-- the Settings row
			local MMC = H.mod("MainMenuController")
			MMC.OpenSettings()
			KC.advance(0.6)
			local holder = MMC.Window and MMC.Window()
			local row = holder and holder:FindFirstChild("Row_MouseLock", true)
			local title = row and row:FindFirstChild("Title")
			T.check(title ~= nil and tostring(title.Text):find("Mouse lock (recommended)", 1, true) ~= nil, "bug2 mouse: the Settings row reads 'Mouse lock (recommended)'", title and title.Text or "no row")
			local onChip = row and row:FindFirstChild("Chip_ON", true)
			T.check(onChip ~= nil and onChip:GetAttribute("Selected") == true, "bug2 mouse: ...with ON selected")
			MMC.CloseWindows()
			KC.advance(0.6)

			-- overlays that are not docked windows hold the cursor while shown
			local function holds(key)
				return ML.Holds()[key] or 0
			end
			local menu = H.pg():FindFirstChild("NimbusMenu")
			if T.check(menu ~= nil, "bug2 mouse: NimbusMenu exists") then
				for _, name in ipairs({ "RouletteStage", "OddsPopup" }) do
					local f = Instance.new("Frame")
					f.Name = name
					f.Size = UDim2.fromScale(1, 1)
					f.BackgroundTransparency = 1
					f.Parent = menu
					T.eq(holds("auto:NimbusMenu"), 1, "bug2 mouse: MenuController's " .. name .. " holds the cursor while shown")
					f.Visible = false
					T.eq(holds("auto:NimbusMenu"), 0, "bug2 mouse: ..." .. name .. " hidden: released")
					f.Visible = true
					T.eq(holds("auto:NimbusMenu"), 1, "bug2 mouse: ...shown again: held")
					f:Destroy()
					T.eq(holds("auto:NimbusMenu"), 0, "bug2 mouse: ..." .. name .. " destroyed: released")
				end
			end
			local npcGui = H.pg():FindFirstChild("NimbusNpcDialog")
			local fake = nil
			if not npcGui then
				fake = Instance.new("ScreenGui")
				fake.Name = "NimbusNpcDialog"
				local card = Instance.new("Frame")
				card.Name = "NpcDialog"
				card.Visible = false
				card.Parent = fake
				fake.Parent = H.pg()
				npcGui = fake
			end
			local card = npcGui:FindFirstChild("NpcDialog")
			if T.check(card ~= nil, "bug2 mouse: the NPC dialog card NimbusNpcDialog.NpcDialog") then
				local was = card.Visible
				card.Visible = false
				T.eq(holds("auto:NimbusNpcDialog"), 0, "bug2 mouse: NPC dialog closed: no hold")
				card.Visible = true
				T.eq(holds("auto:NimbusNpcDialog"), 1, "bug2 mouse: NPC dialog open: the cursor is free for its Next / Close buttons")
				card.Visible = false
				T.eq(holds("auto:NimbusNpcDialog"), 0, "bug2 mouse: ...closed again: released")
				card.Visible = was
			end
			if fake then
				fake:Destroy()
			end

			-- the once-per-session "press L" hint (the lock is on by default: a new player must learn how to free the
			-- cursor for the HUD buttons)
			local St = ML._St
			if T.check(type(St) == "table" and type(ML.HINT_GUI) == "string", "bug2 mouse: MouseLock exposes its hint (HINT_GUI)") then
				local function hint()
					return H.pg():FindFirstChild(ML.HINT_GUI)
				end
				St.Hinted = false
				ML.Hold("bug2:hint")
				ML.Release("bug2:hint")
				if T.check(ML.IsLocked(), "bug2 mouse: (setup) the cursor is locked, no hold left", H.holdText and H.holdText(ML) or "") then
					KC.advance(0.1)
					ML.Hold("bug2:hint")
					ML.Release("bug2:hint")
					KC.advance(0.6)
					local gui = hint()
					local label = gui and gui:FindFirstChild("Hint")
					T.check(label ~= nil and tostring(label.Text):find("press L", 1, true) ~= nil and label.TextSize >= 14,
						"bug2 mouse: the first lock of the session shows 'press L to free the cursor'", label and label.Text or "no hint")
					KC.advance(6.5)
					T.check(hint() == nil, "bug2 mouse: ...gone after a few seconds")
					ML.Hold("bug2:hint")
					ML.Release("bug2:hint")
					KC.advance(0.8)
					T.check(hint() == nil, "bug2 mouse: ...and only once a session")
					-- a window opening while it shows hides it at once
					St.Hinted = false
					ML.Hold("bug2:hint")
					ML.Release("bug2:hint")
					KC.advance(0.6)
					T.check(hint() ~= nil, "bug2 mouse: (setup) the hint shows again after a reset")
					ML.Hold("bug2:hint")
					T.check(hint() == nil, "bug2 mouse: a hold (a window opens) removes the hint at once")
					ML.Release("bug2:hint")
					KC.advance(0.8)
				end
			end
		end)
		T.check(ok, "client_bug2tut_mouse ran to the end", tostring(err))
		-- restore: off (like the scenarios before the default changed), device flags, cursor
		pcall(CS.Set, "MouseLock", false)
		KC.advance(0.6)
		pcall(ML.SetEnabled, false)
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = saved[1], saved[2], saved[3]
		UIS.MouseBehavior = Enum.MouseBehavior.Default
		UIS.MouseIconEnabled = true
		KC.flushErrors("client_bug2tut_mouse")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
