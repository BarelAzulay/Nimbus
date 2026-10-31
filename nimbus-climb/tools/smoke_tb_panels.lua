-- smoke_tb_panels.lua: team balance, Task 5: the battle panels (spec s.2): the three faces + Edit team on the Ring, the Dungeon,
-- the Duels and the Raid page; TeamPick and its "Pick your battle team" popup are gone. Loaded by tools/smoke.py in the server
-- world (pure) and the client worlds:
--   tb_panels_text         the "team" tutorial step and Coach Corgi point at the new controls (97-125 bytes, <= 125 bytes), the
--                          "equip" step and the Fusion window no longer say Equip; client/TeamPick is gone
--   client_tb_faces_ring   (1920x1080, 1280x720, a portrait phone) a 3-pet team with one pet training: FIGHTER / HELPER, the training
--                          pet's face says so, the row sits above the buttons and outside the scroller, no fallback titles, CONTINUE
--                          goes straight in at Start 20
--   client_tb_faces_return Edit team opens the Pets window and comes back: the Ring at Start 20 (Review Focus 4), the Dungeon on the
--                          same floor, the Arena on the same tab, through Care too; a silent close comes back nowhere
--   client_tb_faces_empty  an empty team opens the Pets window in pick mode on slot 1 and sends nothing, at every entry button; a
--                          team of busy pets says why; closing it never enters; 0 pets get the hint and no window
--   client_tb_faces_phone  (844x390 and 390x844 touch) the Ring row in the right column of a landscape phone, clear of the jump button;
--                          every Edit team and entry button >= 44 px, texts >= 14 px, rows inside their windows
-- Deterministic: mock clock only. The viewport, the attributes and the profile are restored at the end.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function req(path)
		local inst = K.moduleInstance(path)
		local ok, m = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(m) == "table" and m or nil
	end

	S.tb_panels_text = guarded("tb_panels_text", function()
		local Steps, Npc = req("shared/TutorialSteps"), req("shared/NpcDialog")
		if not T.check(Steps and Npc, "tb panels: TutorialSteps and NpcDialog load") then
			return
		end
		local function step(id)
			for _, s in ipairs(Steps.Steps) do
				if s.Id == id then
					return s
				end
			end
			return {}
		end
		local team = step("team")
		T.check(#team.Text >= 97 and #team.Text <= 125 and team.Text:find("Auto%-fill best") ~= nil and team.Text:find("tap a slot", 1, true) ~= nil
			and not team.Text:find("Team tab", 1, true) and not team.Text:find("[<>&]"), "tb panels: the team step names the new controls, 97-125 bytes of plain text", tostring(#team.Text))
		T.check(team.Hint == "Open Pets: put 3 pets in your team" and team.Target and team.Target.Id == "Pets" and team.CompleteOn == "TeamSet",
			"tb panels: ...its hint says so, it still rings Pets and completes on TeamSet", tostring(team.Hint))
		local buddy = step("equip")
		T.check(#buddy.Text >= 97 and #buddy.Text <= 125 and not buddy.Text:lower():find("equip", 1, true) and buddy.Text:find("team", 1, true) ~= nil,
			"tb panels: the first pet's step says team, not equip (97-125 bytes)", tostring(buddy.Text))
		local corgi = nil
		for _, npc in ipairs(Npc.Npcs or Npc.List or Npc) do
			if type(npc) == "table" and npc.Id == "coach_corgi" then
				corgi = npc
			end
		end
		if T.check(corgi ~= nil, "tb panels: Coach Corgi exists") then
			local open = false
			for _, line in ipairs(corgi.Lines) do
				T.check(#line <= 125 and not line:find("Tap Team", 1, true), "tb panels: Coach Corgi never says Tap Team, <= 125 bytes", line)
				open = open or line:find("Open Pets", 1, true) ~= nil
			end
			T.check(open, "tb panels: Coach Corgi points at Pets")
		end
		T.check(K.moduleInstance("client/TeamPick") == nil, "tb panels: client/TeamPick is gone")
		T.check(K.moduleInstance("client/UI/TeamFaces") ~= nil, "tb panels: client/UI/TeamFaces exists")
		K.flushErrors("tb_panels_text")
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
	local LocalPlayer = Players.LocalPlayer
	local H = {}

	local K1, K2, K3, K4 = "ember_phoenix", "biscuit_bear", "sunbeam_bear", "pebble_pup"
	local LEVELS = { [K1] = 14, [K2] = 10, [K3] = 6, [K4] = 2 }

	function H.req(path)
		local root, rest = path:match("^(%a+)/(.+)$")
		local inst = Mock.GetPath(ROOTS[root] .. "/" .. rest)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end
	function H.mod(name)
		if KC.M and KC.M[name] then
			return KC.M[name]
		end
		return H.req("client/Controllers/" .. name)
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	function H.shown(obj)
		return obj ~= nil and KC.isShown(obj)
	end
	function H.hintText()
		local menu = H.pg():FindFirstChild("NimbusMenu")
		local hint = menu and menu:FindFirstChild("MenuHint")
		local label = hint and hint:FindFirstChild("Text")
		return (hint and hint.Visible and label) and tostring(label.Text) or ""
	end
	function H.ringWin()
		local gui = H.pg():FindFirstChild("NimbusArena")
		return gui and gui:FindFirstChild("Window_Ring")
	end
	function H.arenaWin()
		local gui = H.pg():FindFirstChild("NimbusArena")
		return gui and gui:FindFirstChild("Window_Arena")
	end
	function H.dungeonWin()
		local gui = H.pg():FindFirstChild("NimbusDungeon")
		return gui and gui:FindFirstChild("Window_Dungeon")
	end
	function H.petsWin()
		local gui = H.pg():FindFirstChild("NimbusPets")
		return gui and gui:FindFirstChild("Window_Pets")
	end
	-- the row shown in a window (the Arena's hidden page keeps its own)
	function H.row(win)
		for _, d in ipairs(win and win:GetDescendants() or {}) do
			if d.Name == "TeamFaces" and H.shown(d) then
				return d
			end
		end
		return nil
	end
	function H.anyText(root, needle)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				if tostring(d.Text):lower():find(needle:lower(), 1, true) then
					return d.Name .. ": " .. tostring(d.Text)
				end
			end
		end
		return nil
	end
	function H.inside(o, outer)
		local p, s, cp, cs = o.AbsolutePosition, o.AbsoluteSize, outer.AbsolutePosition, outer.AbsoluteSize
		return p.X >= cp.X - 0.5 and p.X + s.X <= cp.X + cs.X + 0.5 and p.Y >= cp.Y - 0.5 and p.Y + s.Y <= cp.Y + cs.Y + 0.5
	end
	function H.requests(remote, mark, action)
		local out = {}
		for _, c in ipairs(KC.serverCalls(remote, mark)) do
			if action == nil or c.args[1] == action then
				out[#out + 1] = c
			end
		end
		return out
	end
	-- a ProfileSync snapshot: `team` = the active preset, `busy` = { key = "Training" | "Garden" }; Equipped follows them like the server's
	function H.snapshot(pets, team, busy, over)
		local owned, levels, discovered = {}, {}, {}
		for id, level in pairs(pets) do
			owned[id] = 1
			levels[id] = { Level = level, Xp = 0 }
			discovered[id] = true
		end
		local equipped, growth = {}, {}
		for _, key in ipairs(team) do
			if not (busy and busy[key]) then
				equipped[#equipped + 1] = key
			end
		end
		for key, why in pairs(busy or {}) do
			if why == "Training" then
				growth[key] = { Job = { Stat = "Physique", Ends = os.time() + 3600, Rank = 1, Slot = 1, From = "Free", Paid = 0 } }
			end
		end
		local snap = {
			Tokens = 900,
			Pets = owned,
			Equipped = equipped,
			Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = discovered,
			IndexClaimed = {},
			Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 0, Gems = 0,
			Home = { Level = 5, Prestige = 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = {}, Hybrids = {},
			PetLevels = levels,
			Teams = { Presets = { team, {}, {} }, Active = 1, Slots = 3, Busy = busy or {} },
			Battle = { Trophies = 120, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			PetGrowth = growth,
			Ring = { Best = 24, Runs = 9 },
		}
		for k, v in pairs(over or {}) do
			snap[k] = v
		end
		return snap
	end
	function H.feed(pets, team, busy, over)
		KC.toClient("ProfileSync", H.snapshot(pets, team, busy, over))
		KC.advance(0.3)
	end
	function H.closeAll()
		for _, name in ipairs({ "MenuController", "ArenaController", "DungeonController", "CareController", "ObbyController" }) do
			local m = H.mod(name)
			if m and type(m.Close) == "function" then
				pcall(m.Close)
			end
		end
		local PC = H.mod("PetsController")
		if PC then
			pcall(PC.Close, true)
		end
		KC.advance(0.5)
	end
	function H.reset()
		local Config = KC.env()
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, 3)
		KC.toClient("MatchState", nil)
		KC.toClient("PartyState", nil)
		KC.toClient("DungeonState", "Lobby", { Parties = {}, Mine = nil, Record = { Best = 4, Cleared = {}, Runs = 0, Clears = 0 } })
		KC.advance(0.3)
	end
	-- runs fn at a screen size with the three controllers ready, puts everything back
	function H.at(w, h, touch, label, fn)
		local AC, DC, PC = H.mod("ArenaController"), H.mod("DungeonController"), H.mod("PetsController")
		if not T.check(AC and DC and PC, label .. ": ArenaController, DungeonController and PetsController load") then
			return
		end
		pcall(AC.Init)
		pcall(DC.Init)
		local UIS = game:GetService("UserInputService")
		local Config = KC.env()
		local old = { Mock.Viewport.X, Mock.Viewport.Y, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled, LocalPlayer:GetAttribute(Config.Attr.SpotIndex) }
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = touch, not touch, not touch
		Mock.SetViewport(w, h)
		KC.advance(0.6)
		H.reset()
		H.closeAll()
		local ok, err = pcall(fn, AC, DC, PC)
		if not ok then
			T.fail(label .. ": error", tostring(err))
		end
		H.closeAll()
		H.reset()
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, old[6])
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[3], old[4], old[5]
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.6)
		KC.flushErrors(label)
	end
	function H.commas(n)
		local text = tostring(math.floor(n))
		local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (out:gsub("^,", ""))
	end

	-- three pets on the team, the third in training; Ring best 24 (starts 1, 10, 20)
	local function ringChecks(AC, label)
		local TF = H.req("client/UI/TeamFaces")
		H.feed(LEVELS, { K1, K2, K3 }, { [K3] = "Training" })
		AC.OpenRing(20)
		KC.advance(0.6)
		local win = H.ringWin()
		local row = H.row(win)
		if not T.check(row ~= nil, label .. ": the Ring window shows the TeamFaces row") then
			return
		end
		local f1, f2, f3 = row:FindFirstChild("Face1"), row:FindFirstChild("Face2"), row:FindFirstChild("Face3")
		T.check(f1 and f1.Tag.Text == "FIGHTER" and f2 and f2.Tag.Text == "HELPER" and f2.Level.Text == "L" .. LEVELS[K2], label .. ": three faces: FIGHTER / HELPER, the level", f2 and f2.Level.Text)
		T.check(f3 and H.shown(f3.Empty) and f3.Empty.Text == "Training" and H.shown(f3.Busy), label .. ": the training pet is not fielded: its face says Training", f3 and f3.Empty.Text)
		T.check(not H.shown(f1:FindFirstChild("Empty")) and H.shown(f1.Picture), label .. ": a fielded pet shows its picture")
		local power = TF and TF.Power() or -1
		local tp = row:FindFirstChild("TeamPower", true)
		T.check(power > 0 and tp and (not H.shown(tp) or tp.Text:find(H.commas(power), 1, true) ~= nil), label .. ": TeamPower = TeamFaces.Power()", tp and tp.Text)
		local footer, start, edit = H.find(win, "Footer"), H.find(win, "Start"), H.find(row, "EditTeam")
		T.check(edit and H.shown(edit) and edit.Text == "Edit team", label .. ": Edit team is on the row")
		T.check(H.find(footer, "EditTeam") == nil, label .. ": ...and no longer in the footer")
		T.check(row.AbsolutePosition.Y + row.AbsoluteSize.Y <= footer.AbsolutePosition.Y + footer.AbsoluteSize.Y - start.AbsoluteSize.Y + 0.5 and H.inside(row, win),
			label .. ": the row sits above the buttons, inside the window", fmt("row bottom %.0f, footer top %.0f", row.AbsolutePosition.Y + row.AbsoluteSize.Y, footer.AbsolutePosition.Y))
		local scroll = H.find(win, "Scroll")
		T.check(not row:IsDescendantOf(scroll), label .. ": the row is outside the scroller (never cut off)")
		T.check(H.find(win, "FightersTitle") == nil and H.find(win, "Fighter1") == nil, label .. ": no fighter title, no old cards")
		T.check(not H.anyText(win, "your strongest pets") and not H.anyText(win, "equipped") and not H.anyText(win, "Your fighters"), label .. ": no fallback words", tostring(H.anyText(win, "Your fighters")))
		T.check(H.find(win, "TeamValue") and H.find(win, "TeamValue").Text:find(H.commas(power), 1, true) ~= nil and H.find(win, "TeamCaption").Text == "Your team", label .. ": the champion box compares with Your team")
		T.eq(start.Text, "CONTINUE", label .. ": a boss start reads CONTINUE")
		T.check(not start:GetAttribute("Disabled"), label .. ": ...and is on")
		local mark = #Mock.RemoteLog
		Mock.Click(start)
		KC.advance(0.1)
		local sent = H.requests("BattleRequest", mark, "Ring")
		T.check(#sent == 1 and sent[1].args[2] == 20 and #H.requests("BattleRequest", mark) == 1, label .. ": CONTINUE goes straight in: BattleRequest('Ring', 20), nothing else", tostring(#sent))
		T.check(not H.mod("PetsController").IsOpen(), label .. ": ...with no extra screen")
		-- the entries: the ones that fight, in slot order
		local entries = TF and TF.Entries() or {}
		T.check(#entries == 2 and entries[1].Key == K1 and entries[2].Key == K2 and entries[1].Level == LEVELS[K1] and entries[1].Def ~= nil and entries[1].Tier == "Normal" and entries[1].Power > 0,
			label .. ": TeamFaces.Entries = the team minus the busy pet", tostring(#entries))
		T.eq(table.concat((function()
			local keys = {}
			for _, e in ipairs(AC.RingInfo().Fighters or {}) do
				keys[#keys + 1] = e.Key
			end
			return keys
		end)(), ","), K1 .. "," .. K2, label .. ": RingInfo's fighters are those entries")
		AC.Close()
		KC.advance(0.4)
	end

	S.client_tb_faces_ring = guarded("client_tb_faces_ring", function()
		T.check(H.req("client/TeamPick") == nil, "tb panels: client/TeamPick is gone")
		local TF = H.req("client/UI/TeamFaces")
		if not T.check(type(TF) == "table" and type(TF.New) == "function" and type(TF.Entries) == "function" and type(TF.Power) == "function" and type(TF.Ensure) == "function",
			"tb panels: client/UI/TeamFaces loads (New, Entries, Power, Ensure)") then
			return
		end
		H.at(1920, 1080, false, "tb panels 1080p", function(AC)
			ringChecks(AC, "tb panels 1080p")
			-- slot 1 trains: the next free pet is the FIGHTER; the row follows a sync while the window is open
			H.feed(LEVELS, { K1, K2, K3 }, { [K1] = "Training" })
			AC.OpenRing(1)
			KC.advance(0.5)
			local row = H.row(H.ringWin())
			T.check(row.Face1.Level.Text == "L" .. LEVELS[K2] and row.Face1.Tag.Text == "FIGHTER", "tb panels: slot 1 trains: the next free pet fights", row.Face1.Level.Text)
			H.feed(LEVELS, { K4 }, {})
			KC.advance(0.1)
			T.check(row.Face1.Level.Text == "L" .. LEVELS[K4] and H.shown(row.Face2.Empty) and row.Face2.Empty.Text == "Empty", "tb panels: a sync redraws the faces; an open slot says Empty", row.Face2.Empty.Text)
			-- an evolved fighter keeps its stage on the face
			H.feed(LEVELS, { K1 }, {}, { PetGrowth = { [K1] = { Evo = 2 } } })
			KC.advance(0.1)
			T.check(row.Face1:GetAttribute("Stage") == 2 and row.Face1:FindFirstChild("StageBadge") and row.Face1.StageBadge.Text == "EVO II" and row.Face1.StageBadge.Visible,
				"tb panels: an evolved fighter's face carries its stored stage and an EVO badge", tostring(row.Face1:GetAttribute("Stage")))
			AC.Close()
		end)
		H.at(1280, 720, false, "tb panels 720p", function(AC)
			ringChecks(AC, "tb panels 720p")
		end)
		H.at(390, 844, true, "tb panels portrait", function(AC)
			ringChecks(AC, "tb panels portrait")
		end)
	end)

	S.client_tb_faces_return = guarded("client_tb_faces_return", function()
		H.at(1920, 1080, false, "tb panels return", function(AC, DC, PC)
			H.feed(LEVELS, { K1, K2, K3 }, {})
			AC.OpenRing(20)
			KC.advance(0.5)
			Mock.Click(H.find(H.row(H.ringWin()), "EditTeam"))
			KC.advance(0.3)
			T.check(PC.IsOpen() and not AC.IsOpen(), "tb panels: Edit team opens the Pets window, the Ring window steps aside")
			PC.Close()
			KC.advance(0.3)
			local st = AC.GetState()
			T.check(not PC.IsOpen() and st.Window == "Ring" and st.RingStart == 20, "tb panels: ...and closing it returns to the Ring window at Start 20 (Review Focus 4)", tostring(st.Window) .. " " .. tostring(st.RingStart))
			-- the picked round, not the window's default
			Mock.Click(H.find(H.ringWin(), "Start10"))
			KC.advance(0.3)
			Mock.Click(H.find(H.row(H.ringWin()), "EditTeam"))
			KC.advance(0.3)
			PC.Close()
			KC.advance(0.3)
			T.eq(AC.GetState().RingStart, 10, "tb panels: ...the tile picked last, not the latest boss")
			-- back through Care: the Food Machine comes back to the window, the window back to the Ring
			Mock.Click(H.find(H.row(H.ringWin()), "EditTeam"))
			KC.advance(0.3)
			local Care = H.mod("CareController")
			PC.Open({ Key = K1 })
			KC.advance(0.3)
			Mock.Click(H.find(H.petsWin(), "ActFeed"))
			KC.advance(0.3)
			T.check(Care.IsOpen() and not PC.IsOpen(), "tb panels: Feed opens the Food Machine")
			Care.Close()
			KC.advance(0.3)
			T.check(PC.IsOpen(), "tb panels: ...it comes back to the Pets window")
			PC.Close()
			KC.advance(0.3)
			T.check(AC.GetState().Window == "Ring" and AC.GetState().RingStart == 10, "tb panels: ...and that one back to the Ring", tostring(AC.GetState().Window))
			-- a silent close (something else took over) returns nowhere
			Mock.Click(H.find(H.row(H.ringWin()), "EditTeam"))
			KC.advance(0.3)
			H.mod("MenuController").Close()
			KC.advance(0.3)
			T.check(not PC.IsOpen() and not AC.IsOpen(), "tb panels: a silent close returns nowhere")
			-- the Dungeon, on the same floor
			DC.Open(3)
			KC.advance(0.5)
			Mock.Click(H.find(H.row(H.dungeonWin()), "EditTeam"))
			KC.advance(0.3)
			T.check(PC.IsOpen() and not DC.IsOpen(), "tb panels: the Dungeon's Edit team opens the Pets window")
			PC.Close()
			KC.advance(0.3)
			T.check(DC.IsOpen() and DC.GetState().Floor == 3, "tb panels: ...the Dungeon window returns on floor 3", tostring(DC.GetState().Floor))
			DC.Close()
			KC.advance(0.3)
			-- the Arena, on the same tab
			for _, tab in ipairs({ "Raid", "Duels" }) do
				AC.OpenArena(tab)
				KC.advance(0.5)
				Mock.Click(H.find(H.row(H.arenaWin()), "EditTeam"))
				KC.advance(0.3)
				T.check(PC.IsOpen() and not AC.IsOpen(), "tb panels: the Arena's Edit team opens the Pets window (" .. tab .. ")")
				PC.Close()
				KC.advance(0.3)
				T.check(AC.GetState().Window == "Arena" and AC.GetState().Tab == tab, "tb panels: ...the Arena returns on the same tab (" .. tab .. ")", tostring(AC.GetState().Tab))
				AC.Close()
				KC.advance(0.3)
			end
			-- no ReturnTo: nothing opens
			PC.Open({})
			KC.advance(0.3)
			PC.Close()
			KC.advance(0.3)
			T.check(not AC.IsOpen() and not DC.IsOpen(), "tb panels: the Pets tile's window returns nowhere")
		end)
	end)

	S.client_tb_faces_empty = guarded("client_tb_faces_empty", function()
		H.at(1920, 1080, false, "tb panels empty", function(AC, DC, PC)
			local TF = H.req("client/UI/TeamFaces")
			local function petsPick(label, mark)
				local win = H.petsWin()
				local banner = win and H.find(win, "PickBanner")
				local slot1 = win and H.find(win, "Slot1")
				T.check(PC.IsOpen() and banner and H.shown(banner) and slot1 and H.shown(H.find(slot1, "Glow")), label .. ": opens the Pets window in pick mode on slot 1")
				T.check(#KC.serverCalls("BattleRequest", mark) == 0 and #KC.serverCalls("DungeonRequest", mark) == 0, label .. ": ...and sends nothing")
				T.check(H.pg():FindFirstChild("NimbusTeamPick") == nil, label .. ": ...no popup")
			end
			H.feed(LEVELS, {}, {})
			T.check(#TF.Entries() == 0 and TF.Power() == 0, "tb panels: an empty team: no entries, power 0")
			-- the Dungeon: SOLO
			DC.Open(1)
			KC.advance(0.5)
			local row = H.row(H.dungeonWin())
			T.check(row and H.shown(row.Face1.Empty) and row.Face1.Empty.Text == "Empty", "tb panels: the Dungeon row shows the empty team")
			local mark = #Mock.RemoteLog
			Mock.Click(H.find(H.dungeonWin(), "SoloButton"))
			KC.advance(0.2)
			petsPick("tb panels: SOLO with an empty team", mark)
			PC.Close()
			KC.advance(0.3)
			T.check(DC.IsOpen() and #H.requests("DungeonRequest", mark, "Solo") == 0, "tb panels: closing without a team does not enter (no silent auto-fill), back on the Dungeon window")
			-- PARTY too
			mark = #Mock.RemoteLog
			Mock.Click(H.find(H.dungeonWin(), "PartyButton"))
			KC.advance(0.2)
			petsPick("tb panels: PARTY with an empty team", mark)
			PC.Close()
			KC.advance(0.3)
			-- a team picked while the window was open: nothing enters by itself, the button then goes straight in
			H.feed(LEVELS, { K1 }, {})
			mark = #Mock.RemoteLog
			KC.advance(0.6)
			T.check(#H.requests("DungeonRequest", mark, "Solo") == 0, "tb panels: a team saved later does not enter by itself")
			Mock.Click(H.find(H.dungeonWin(), "SoloButton"))
			KC.advance(0.2)
			T.check(#H.requests("DungeonRequest", mark, "Solo") == 1 and not PC.IsOpen(), "tb panels: ...the player presses SOLO again: straight in")
			DC.Close()
			KC.advance(0.3)
			-- a party member's READY goes through it too; NOT READY never asks
			H.feed(LEVELS, {}, {})
			DC.Open(1)
			KC.advance(0.5)
			local me = LocalPlayer.UserId
			KC.toClient("DungeonState", "Lobby", { Parties = {}, Record = { Best = 4, Cleared = {}, Runs = 0, Clears = 0 },
				Mine = { Leader = 501, Floor = 1, Members = { { UserId = 501, Name = "Ava", Ready = true, Power = 40 }, { UserId = me, Name = LocalPlayer.Name, Ready = false, Power = 0 } } } })
			KC.advance(0.6)
			T.check(H.row(H.dungeonWin()) ~= nil, "tb panels: a party member's box carries the row too")
			mark = #Mock.RemoteLog
			Mock.Click(H.find(H.dungeonWin(), "ReadyButton"))
			KC.advance(0.2)
			petsPick("tb panels: READY with an empty team", mark)
			PC.Close(true)
			KC.advance(0.3)
			H.reset()
			H.closeAll()
			-- the Ring: START is on, it opens the window
			H.feed(LEVELS, {}, {})
			AC.OpenRing(1)
			KC.advance(0.5)
			local win = H.ringWin()
			local start = H.find(win, "Start")
			T.check(not start:GetAttribute("Disabled") and not H.shown(H.find(win, "Why")), "tb panels: an empty team does not switch START off: it leads to the Pets window", H.find(win, "Why").Text)
			mark = #Mock.RemoteLog
			Mock.Click(start)
			KC.advance(0.2)
			petsPick("tb panels: START with an empty team", mark)
			PC.Close()
			KC.advance(0.3)
			T.check(AC.GetState().Window == "Ring" and #H.requests("BattleRequest", mark) == 0, "tb panels: ...back on the Ring window, nothing sent")
			AC.Close()
			KC.advance(0.3)
			-- Raid + Duels: JOIN RAID stays on; Find a match
			AC.OpenArena("Raid")
			KC.advance(0.4)
			KC.toClient("ArenaState", {
				Next = { Kind = "BossRaid", BossId = "storm_titan", Name = "Storm Titan", StartsIn = 90, Announced = true },
				Raid = { Active = true, BossId = "lava_golem", Name = "Lava Golem", Hp = 500, MaxHp = 1000, Players = 2, EndsIn = 200, Joinable = true, JoinEndsIn = 40, Waiting = false, BattleId = "raid-1" },
				Double = { Active = false },
				Leaderboard = {},
			})
			KC.advance(0.4)
			local page = H.find(H.arenaWin(), "Page_Raid")
			local join = H.find(page, "JoinRaid")
			T.check(join and join:GetAttribute("Disabled") ~= true, "tb panels: JOIN RAID is on with an empty team")
			mark = #Mock.RemoteLog
			Mock.Click(join)
			KC.advance(0.2)
			petsPick("tb panels: JOIN RAID with an empty team", mark)
			PC.Close()
			KC.advance(0.3)
			T.check(AC.GetState().Window == "Arena" and AC.GetState().Tab == "Raid", "tb panels: ...back on the Raid page")
			AC.OpenArena("Duels")
			KC.advance(0.4)
			mark = #Mock.RemoteLog
			Mock.Click(H.find(H.find(H.arenaWin(), "Page_Duels"), "Queue"))
			KC.advance(0.2)
			petsPick("tb panels: Find a match with an empty team", mark)
			PC.Close()
			KC.advance(0.3)
			-- a team: Find a match sends at once
			H.feed(LEVELS, { K1, K2 }, {})
			mark = #Mock.RemoteLog
			KC.advance(0.6)
			Mock.Click(H.find(H.find(H.arenaWin(), "Page_Duels"), "Queue"))
			KC.advance(0.2)
			T.check(#H.requests("BattleRequest", mark, "Queue") == 1 and not PC.IsOpen(), "tb panels: with a team Find a match sends Queue at once")
			AC.Close()
			KC.advance(0.3)
			-- every pet of the team is busy: the same flow, and it says why
			H.feed(LEVELS, { K1 }, { [K1] = "Training" })
			DC.Open(1)
			KC.advance(0.5)
			mark = #Mock.RemoteLog
			Mock.Click(H.find(H.dungeonWin(), "SoloButton"))
			KC.advance(0.2)
			T.check(PC.IsOpen() and #H.requests("DungeonRequest", mark, "Solo") == 0, "tb panels: a team of busy pets counts as empty: the Pets window")
			T.check(H.hintText():find("busy", 1, true) ~= nil, "tb panels: ...and it says why", H.hintText())
			PC.Close(true)
			KC.advance(0.3)
			-- 0 pets: the hint, no window, a disabled START that says so
			H.feed({}, {}, {})
			DC.Open(1)
			KC.advance(0.5)
			mark = #Mock.RemoteLog
			Mock.Click(H.find(H.dungeonWin(), "SoloButton"))
			KC.advance(0.2)
			T.check(H.hintText():find("You need a pet", 1, true) ~= nil and not PC.IsOpen() and #H.requests("DungeonRequest", mark) == 0, "tb panels: 0 pets = the hint, no window", H.hintText())
			DC.Close()
			KC.advance(0.3)
			AC.OpenRing(1)
			KC.advance(0.5)
			win = H.ringWin()
			T.check(H.find(win, "Start"):GetAttribute("Disabled") == true and H.find(win, "Why").Text:find("You need a pet", 1, true) ~= nil, "tb panels: 0 pets: START says You need a pet", H.find(win, "Why").Text)
			AC.Close()
			H.feed(LEVELS, {}, {})
		end)
	end)

	S.client_tb_faces_phone = guarded("client_tb_faces_phone", function()
		local function small(root)
			local out = {}
			for _, d in ipairs(root:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and H.shown(d) and d.Text ~= "" then
					local box = Mock.GuiBox(d)
					local px = d.TextSize * ((box and box.scale) or 1)
					if px < 14 - 0.05 then
						out[#out + 1] = d.Name .. " " .. fmt("%.1f", px)
					end
				end
			end
			return out
		end
		for _, size in ipairs({ { 844, 390 }, { 390, 844 } }) do
			local w, h = size[1], size[2]
			local label = fmt("tb panels phone %dx%d", w, h)
			H.at(w, h, true, label, function(AC, DC)
				H.feed(LEVELS, { K1, K2, K3 }, {})
				AC.OpenRing(1)
				KC.advance(0.8)
				local win = H.ringWin()
				local row = H.row(win)
				if T.check(row ~= nil, label .. ": the Ring row is shown") then
					local panel = H.find(win, "RingPanel")
					local edit = H.find(row, "EditTeam")
					local start = H.find(win, "Start")
					T.check(H.inside(row, panel), label .. ": ...inside the window")
					T.check(edit.AbsoluteSize.Y >= 44 and H.shown(edit), label .. ": ...Edit team >= 44 px", fmt("%.1f", edit.AbsoluteSize.Y))
					T.check(start.AbsoluteSize.Y >= 44 and H.shown(start), label .. ": ...START >= 44 px", fmt("%.1f", start.AbsoluteSize.Y))
					for i = 1, 3 do
						T.check(H.inside(row:FindFirstChild("Face" .. i), row), label .. ": ...Face" .. i .. " inside the row")
						T.check(H.shown(row:FindFirstChild("Face" .. i).Tag) and H.inside(row:FindFirstChild("Face" .. i).Tag, row:FindFirstChild("Face" .. i)), label .. ": ...Face" .. i .. "'s tag fits it")
					end
					T.eq(table.concat(small(row), ", "), "", label .. ": every text of the row >= 14 px")
					if w > h then
						T.check(row.AbsolutePosition.X >= win.AbsolutePosition.X + win.AbsoluteSize.X / 2 - 0.5, label .. ": the row sits in the right column", fmt("x %.0f, window %.0f + %.0f", row.AbsolutePosition.X, win.AbsolutePosition.X, win.AbsoluteSize.X))
						T.check(row.AbsolutePosition.Y + row.AbsoluteSize.Y <= h - 90, label .. ": ...above Roblox's jump button", fmt("bottom %.0f", row.AbsolutePosition.Y + row.AbsoluteSize.Y))
						T.check(start.AbsolutePosition.X + start.AbsoluteSize.X <= row.AbsolutePosition.X + 0.5, label .. ": ...CONTINUE stays in the left column, clear of the jump button")
						T.check(H.find(row:FindFirstChild("Face2"), "Power").Text ~= "", label .. ": ...every face shows its power")
					else
						T.check(row.AbsolutePosition.Y + row.AbsoluteSize.Y <= start.AbsolutePosition.Y + 0.5, label .. ": the row sits above START")
						T.check(start.AbsolutePosition.Y + start.AbsoluteSize.Y <= h - 90, label .. ": ...START stays above the thumbstick and the jump button", fmt("bottom %.0f", start.AbsolutePosition.Y + start.AbsoluteSize.Y))
					end
				end
				AC.Close()
				KC.advance(0.3)
				-- the Why text on a landscape phone stays in the left column, inside the window
				LocalPlayer:SetAttribute(KC.env().Attr.SpotIndex, nil)
				AC.OpenRing(1)
				KC.advance(0.8)
				win = H.ringWin()
				local why = H.find(win, "Why")
				T.check(H.shown(why) and H.inside(why, H.find(win, "RingPanel")) and (w < h or why.AbsolutePosition.X + why.AbsoluteSize.X <= H.row(win).AbsolutePosition.X + 0.5), label .. ": the reason START is off stays beside the row")
				LocalPlayer:SetAttribute(KC.env().Attr.SpotIndex, 3)
				AC.Close()
				KC.advance(0.3)
				-- the Dungeon
				DC.Open(1)
				KC.advance(0.8)
				local dw = H.dungeonWin()
				local dr = H.row(dw)
				if T.check(dr ~= nil, label .. ": the Dungeon row is shown") then
					local panel = H.find(dw, "DungeonPanel")
					local edit = H.find(dr, "EditTeam")
					T.check(H.inside(dr, panel), label .. ": ...inside the window", fmt("%.0f..%.0f", dr.AbsolutePosition.X, dr.AbsolutePosition.X + dr.AbsoluteSize.X))
					T.check(edit.AbsoluteSize.Y >= 44, label .. ": ...Edit team >= 44 px", fmt("%.1f", edit.AbsoluteSize.Y))
					T.eq(table.concat(small(dr), ", "), "", label .. ": every text of the row >= 14 px")
					for i = 1, 3 do
						local face = dr:FindFirstChild("Face" .. i)
						T.check(H.inside(face, dr) and H.inside(face.Tag, face) and H.inside(face.Level, face) and H.inside(face.Power, face), label .. ": ...Face" .. i .. " keeps its parts inside")
					end
				end
				local solo, party = H.find(dw, "SoloButton"), H.find(dw, "PartyButton")
				local box = H.find(dw, "Party")
				T.check(solo and H.shown(solo) and solo.AbsoluteSize.Y >= 44 and party.AbsoluteSize.Y >= 44, label .. ": SOLO and PARTY stay >= 44 px", solo and fmt("%.1f", solo.AbsoluteSize.Y))
				T.check(solo.AbsolutePosition.Y + solo.AbsoluteSize.Y <= box.AbsolutePosition.Y + box.AbsoluteSize.Y + 0.5, label .. ": ...in view without scrolling", fmt("%.0f <= %.0f", solo.AbsolutePosition.Y + solo.AbsoluteSize.Y, box.AbsolutePosition.Y + box.AbsoluteSize.Y))
				if w > h and dr then
					T.check(party.AbsolutePosition.X + party.AbsoluteSize.X <= w - 110, label .. ": ...PARTY stops short of the jump button", fmt("right %.0f", party.AbsolutePosition.X + party.AbsoluteSize.X))
					T.check(dr.AbsolutePosition.Y + dr.AbsoluteSize.Y <= h - 86, label .. ": ...the row (Edit team) sits above the jump button", fmt("bottom %.0f", dr.AbsolutePosition.Y + dr.AbsoluteSize.Y))
				end
				DC.Close()
				KC.advance(0.3)
				-- the Raid page
				AC.OpenArena("Raid")
				KC.advance(0.8)
				local ar = H.row(H.arenaWin())
				if T.check(ar ~= nil, label .. ": the Raid page's row is shown") then
					T.check(H.find(ar, "EditTeam").AbsoluteSize.Y >= 44, label .. ": ...Edit team >= 44 px")
					T.check(H.inside(ar, H.find(H.arenaWin(), "ArenaPanel")), label .. ": ...inside the window")
					T.check(H.find(H.arenaWin(), "JoinRaid").AbsoluteSize.Y >= 44, label .. ": ...JOIN RAID >= 44 px")
				end
				AC.OpenArena("Duels")
				KC.advance(0.8)
				local queue = H.find(H.find(H.arenaWin(), "Page_Duels"), "Queue")
				T.check(queue and H.shown(queue) and queue.AbsoluteSize.Y >= 44, label .. ": Find a match >= 44 px", queue and fmt("%.1f", queue.AbsoluteSize.Y))
				local dfaces, left = H.row(H.arenaWin()), H.find(H.find(H.arenaWin(), "Page_Duels"), "Left")
				T.check(dfaces and left and dfaces.AbsolutePosition.Y + dfaces.AbsoluteSize.Y <= left.AbsolutePosition.Y + left.AbsoluteSize.Y + 0.5, label .. ": the Duels row is whole in its scroller", dfaces and fmt("bottom %.0f, scroller %.0f", dfaces.AbsolutePosition.Y + dfaces.AbsoluteSize.Y, left.AbsolutePosition.Y + left.AbsoluteSize.Y))
				AC.Close()
			end)
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
