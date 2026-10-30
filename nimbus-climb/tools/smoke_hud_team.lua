-- smoke_hud_team.lua: HUD cleanup, Task 2 (the owner's pick on the HUD cleanup pitch: slot 2 "C" the battle team at the
-- portal, plus the pitch note "add an autofill best pets button"). Loaded by tools/smoke.py in the server world and the
-- client worlds:
--   hudteam_refusal       (server, booted) BattleService.TeamSpec's empty-team refusal names the portal and Pets > Team,
--                         DungeonService.StartSolo refuses with the same text; tutorial step 16 ("team") rings the Pets
--                         tile, completes on TeamSet and says "Open Pets, then the Team tab" + "Auto-fill best" in 97-125
--                         bytes of plain text
--   client_hudteam_tab    (client, 1920x1080) Open("Team") opens the Pets window (Window_Inventory, no Window_Team) on its
--                         Team tab with the P3 editor (slot cards, presets, Use this team), titled "Battle Team", and fires
--                         WindowOpened("Team"); Open("Pets") goes back to the Pets tab; OpenPanel("Team", { Preset = 2 })
--                         selects preset 2
--   client_hudteam_portal (client) TeamPick: ActiveKeys / Fieldable (sorted by UnitPower, no training pet) / Best; the
--                         Dungeon panel's team strip (StripSlot1..3, Edit, Auto-fill best -> BattleRequest("TeamSet",
--                         active, the 3 best)); SOLO with an empty team opens the "Pick your battle team" popup (PopSlot1..3
--                         cycle, Auto-fill best, Save and enter, Cancel), Save fires TeamSet, waits for the sync, then
--                         DungeonRequest("Solo"); 2 pets save a 2-pet team; 0 pets get the hint and no popup; no sync in
--                         2.5 s closes the popup with a hint; the Arena's Duels + Raid pages carry the strip, JOIN RAID stays
--                         enabled with an empty team and goes through the popup, Find a match too
--   client_hudteam_mobile (phone world, 844x390 touch) the popup fits the screen with 16 px gutters, its buttons >= 44 px;
--                         the Dungeon panel's strip sits inside the window
-- Deterministic: mock clock only. The viewport, the attributes and the profile are restored at the end.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format
local REFUSAL = "Pick your battle team first (at a battle portal, or Pets > Team)"

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

	S.hudteam_refusal = guarded("hudteam_refusal", function()
		if not K.needBoot() then
			return
		end
		local BS = req("server/Services/BattleService")
		local DS = req("server/Services/DataService")
		local DGS = req("server/Services/DungeonService")
		local Steps = req("shared/TutorialSteps")
		if not T.check(BS and DS and DGS and Steps and type(BS.TeamSpec) == "function", "hudteam: BattleService / DataService / DungeonService / TutorialSteps load") then
			return
		end
		local players = K.freshPlayers(1, "TeamRef")
		local a = players[1]
		K.advance(0.5)
		local prof = DS.GetProfile(a)
		if prof then
			prof.Pets.pebble_pup = (prof.Pets.pebble_pup or 0) + 1
			prof.Pets.biscuit_bear = (prof.Pets.biscuit_bear or 0) + 1
			DS.MarkDirty(a)
		end
		for i = 1, 3 do
			DS.SetTeam(a, i, {})
		end
		local spec, why = BS.TeamSpec(a)
		T.check(spec == nil and why == REFUSAL, "hudteam: TeamSpec's empty-team refusal names the portal and Pets > Team", tostring(why))
		local ok, why2 = DGS.StartSolo(a, 1)
		T.check(ok == false and why2 == why, "hudteam: the Dungeon refuses with the same text", tostring(why2))

		local step = Steps.Steps[16]
		if T.check(type(step) == "table" and step.Id == "team", "hudteam: tutorial step 16 is the 'team' step") then
			T.check(step.Target and step.Target.Kind == "Menu" and step.Target.Id == "Pets" and step.CompleteOn == "TeamSet",
				"hudteam: ...it rings the Pets tile and completes on TeamSet", step.Target and tostring(step.Target.Id))
			-- (plain text: no "<>&", so "Pets, then the Team tab" instead of the plan's "Pets > Team")
			T.check(#step.Text >= 97 and #step.Text <= 125 and step.Text:find("Open Pets, then the Team tab", 1, true) ~= nil and step.Text:find("Auto%-fill best") ~= nil
				and not step.Text:find("[<>&]"), "hudteam: ...its text names Pets, the Team tab and Auto-fill best in 97-125 bytes of plain text", tostring(#step.Text))
			T.check(not step.Text:find("Tap Team", 1, true) and not tostring(step.Hint):find("Tap Team", 1, true) and tostring(step.Hint):find("Open Pets, then Team", 1, true) ~= nil,
				"hudteam: ...no stale 'Tap Team' (the hint says Open Pets, then Team)", tostring(step.Hint))
		end
		K.removePlayers(players)
		K.flushErrors("hudteam_refusal")
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

	-- four pets at different levels (the power order is the level order), an empty team
	local FOUR = { ember_phoenix = 14, biscuit_bear = 10, sunbeam_bear = 6, pebble_pup = 2 }
	local TWO = { biscuit_bear = 10, pebble_pup = 2 }
	local EMPTY_TEAMS = { Presets = { {}, {}, {} }, Active = 1, Slots = 3 }

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
	function H.menu()
		return H.pg():FindFirstChild("NimbusMenu")
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
		local hint = H.menu() and H.menu():FindFirstChild("MenuHint")
		local label = hint and hint:FindFirstChild("Text")
		return (hint and hint.Visible and label) and tostring(label.Text) or ""
	end
	function H.calls(name, mark)
		return KC.serverCalls(name, mark)
	end
	function H.titleOf(win)
		local bar = H.find(win, "TitleBar")
		local label = bar and bar:FindFirstChild("Title")
		return label and label.Text or "?"
	end
	function H.dungeonPanel()
		local gui = H.pg():FindFirstChild("NimbusDungeon")
		return gui and gui:FindFirstChild("Window_Dungeon")
	end
	function H.arenaPanel()
		local gui = H.pg():FindFirstChild("NimbusArena")
		return gui and gui:FindFirstChild("Window_Arena")
	end
	function H.popup()
		local gui = H.pg():FindFirstChild("NimbusTeamPick")
		return gui and gui:FindFirstChild("TeamPickPopup")
	end
	-- a ProfileSync snapshot (the shape of smoke_p3_ui's): pets = { id = level }, teams, extra fields
	function H.snapshot(pets, teams, over)
		local owned, levels, discovered = {}, {}, {}
		for id, level in pairs(pets) do
			owned[id] = 1
			levels[id] = { Level = level, Xp = 0 }
			discovered[id] = true
		end
		local snap = {
			Tokens = 900,
			Pets = owned,
			Equipped = {},
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
			Teams = teams or EMPTY_TEAMS,
			Battle = { Trophies = 120, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			PetGrowth = {},
			Ring = { Best = 0, Runs = 0 },
		}
		for k, v in pairs(over or {}) do
			snap[k] = v
		end
		return snap
	end
	function H.feed(pets, teams, over)
		KC.toClient("ProfileSync", H.snapshot(pets, teams, over))
		KC.advance(0.3)
	end
	function H.teamOf(keys)
		return { Presets = { keys, {}, {} }, Active = 1, Slots = 3 }
	end
	function H.closeAll()
		for _, name in ipairs({ "MenuController", "ArenaController", "DungeonController", "CareController", "ObbyController" }) do
			local m = H.mod(name)
			if m and type(m.Close) == "function" then
				pcall(m.Close)
			end
		end
		local TP = H.req("client/TeamPick")
		if TP and type(TP.Close) == "function" then
			pcall(TP.Close)
		end
		KC.advance(0.5)
	end
	function H.reset()
		local Config = KC.env()
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		KC.toClient("MatchState", nil)
		KC.toClient("PartyState", nil)
		KC.toClient("DungeonState", "Lobby", { Parties = {}, Mine = nil, Record = { Best = 0, Cleared = {}, Runs = 0, Clears = 0 } })
		KC.advance(0.3)
	end

	S.client_hudteam_tab = guarded("client_hudteam_tab", function()
		local MC = H.mod("MenuController")
		if not T.check(type(MC) == "table" and type(MC.Open) == "function" and type(MC.OpenTeam) == "function", "hudteam tab: MenuController.Open / OpenTeam exist") then
			return
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		H.reset()
		H.closeAll()
		H.feed(FOUR, EMPTY_TEAMS)
		local opened = {}
		local conn = MC.WindowOpened:Connect(function(id)
			opened[#opened + 1] = tostring(id)
		end)
		MC.Open("Team", {})
		KC.advance(0.6)
		local inv = H.menu():FindFirstChild("Window_Inventory")
		T.check(H.shown(inv) and H.menu():FindFirstChild("Window_Team") == nil, "hudteam tab: Open('Team') opens the Pets window; there is no Window_Team any more")
		local page = H.find(inv, "Page_Team")
		T.check(H.find(inv, "Tab_Team") and H.find(inv, "Tab_Pets") and page and page.Visible and not H.find(inv, "Page_Pets").Visible,
			"hudteam tab: ...on its Team tab (next to Pets)")
		T.check(H.find(page, "Slot1") and H.find(page, "Slot3") and H.find(page, "UseTeam") and H.find(page, "Preset1") and H.find(page, "PickerGrid"),
			"hudteam tab: ...holding the P3 editor (slot cards, presets, Use this team, the picker)")
		T.check(H.titleOf(inv) == "Battle Team", "hudteam tab: ...titled Battle Team", H.titleOf(inv))
		local fired = false
		for _, id in ipairs(opened) do
			fired = fired or id == "Team"
		end
		T.check(fired, "hudteam tab: ...and WindowOpened('Team') fired (the tutorial and the Ring line listen)", table.concat(opened, ","))
		local grid = H.find(page, "PickerGrid")
		local tiles = 0
		for _, c in ipairs(grid and grid:GetChildren() or {}) do
			if c:IsA("TextButton") then
				tiles = tiles + 1
			end
		end
		T.eq(tiles, 4, "hudteam tab: the picker lists the 4 pets")
		-- the editor still edits: a tap adds the pet (TeamSet on the shown preset)
		local mark = #Mock.RemoteLog
		Mock.Click(H.find(page, "Pick_biscuit_bear"))
		KC.advance(0.8)
		local sets = {}
		for _, c in ipairs(H.calls("BattleRequest", mark)) do
			if c.args[1] == "TeamSet" then
				sets[#sets + 1] = c
			end
		end
		T.check(#sets == 1 and sets[1].args[2] == 1 and sets[1].args[3][1] == "biscuit_bear", "hudteam tab: tapping a pet in the Team tab sends TeamSet (1, { biscuit_bear })", tostring(#sets))
		H.feed(FOUR, H.teamOf({ "biscuit_bear" }))
		KC.advance(4.5)
		MC.Open("Pets", {})
		KC.advance(0.3)
		T.check(H.find(inv, "Page_Pets").Visible and not page.Visible and H.titleOf(inv) == "Pets", "hudteam tab: Open('Pets') switches back to the Pets tab", H.titleOf(inv))
		KC.toClient("OpenPanel", "Team", { Preset = 2 })
		KC.advance(0.3)
		local p2 = H.find(page, "Preset2")
		T.check(page.Visible and p2 and p2:GetAttribute("Selected") == true and H.find(page, "Preset1"):GetAttribute("Selected") ~= true,
			"hudteam tab: OpenPanel('Team', { Preset = 2 }) selects preset 2")
		-- the Team tab keeps the Pets tile lit (it lives in the Pets window)
		local tile = MC.GetButton and MC.GetButton("Pets")
		T.check(tile ~= nil, "hudteam tab: the Pets tile exists")
		MC.Close()
		KC.advance(0.4)
		opened = {}
		MC.OpenTeam(1)
		KC.advance(0.4)
		local again = false
		for _, id in ipairs(opened) do
			again = again or id == "Team"
		end
		T.check(page.Visible and H.find(page, "Preset1"):GetAttribute("Selected") == true and again,
			"hudteam tab: OpenTeam(1) opens Pets > Team on preset 1 and fires WindowOpened('Team') again for the new opening")
		conn:Disconnect()
		H.closeAll()
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.5)
		KC.flushErrors("client_hudteam_tab")
	end)

	S.client_hudteam_portal = guarded("client_hudteam_portal", function()
		local TP = H.req("client/TeamPick")
		local MC = H.mod("MenuController")
		local DC = H.mod("DungeonController")
		local AC = H.mod("ArenaController")
		local PC = H.req("shared/PetCatalog")
		local PetKeys = H.req("shared/PetKeys")
		if not T.check(type(TP) == "table" and type(TP.Ensure) == "function" and type(TP.Strip) == "function" and type(TP.Popup) == "function",
			"hudteam portal: client/TeamPick loads (ActiveKeys, Fieldable, Best, Save, Ensure, Strip, Popup, IsOpen, Close)") then
			return
		end
		if not T.check(DC and AC and MC, "hudteam portal: DungeonController, ArenaController and MenuController load") then
			return
		end
		pcall(DC.Init)
		pcall(AC.Init)
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		H.reset()
		H.closeAll()
		H.feed(FOUR, EMPTY_TEAMS)

		------------------------------------------------------------ TeamPick's data
		local f = TP.Fieldable()
		T.check(#TP.ActiveKeys() == 0 and #f == 4 and #TP.Best(3) == 3, "hudteam portal: TeamPick: an empty active team, 4 fieldable pets, Best(3) picks 3",
			fmt("%d / %d / %d", #TP.ActiveKeys(), #f, #TP.Best(3)))
		T.check(f[1] and f[4] and f[1].Power >= f[2].Power and f[2].Power >= f[3].Power and f[3].Power >= f[4].Power and f[1].Key == "ember_phoenix",
			"hudteam portal: ...sorted by UnitPower (the level 14 phoenix first)", f[1] and f[1].Key)
		T.check(f[1] and f[1].Def and f[1].Level == 14 and f[1].Tier == "Normal", "hudteam portal: ...each with Key, Def, Level, Tier, Power")
		local best = TP.Best(3)
		H.feed(FOUR, EMPTY_TEAMS, { PetGrowth = { ember_phoenix = { Job = { Stat = "Physique", Ends = os.time() + 3600, Rank = 1, Slot = 1, From = "Free", Paid = 0 } } } })
		T.check(#TP.Fieldable() == 3 and TP.Best(1)[1] ~= "ember_phoenix", "hudteam portal: a training pet is not fieldable")
		H.feed(FOUR, H.teamOf({ "ember_phoenix", "pebble_pup" }), { PetGrowth = { ember_phoenix = { Job = { Stat = "Physique", Ends = os.time() + 3600, Rank = 1, Slot = 1, From = "Free", Paid = 0 } } } })
		local ak = TP.ActiveKeys()
		T.check(#ak == 1 and ak[1] == "pebble_pup", "hudteam portal: ActiveKeys skips a training pet of the active preset", table.concat(ak, ","))
		H.feed(FOUR, EMPTY_TEAMS, { Home = { Level = 5, Prestige = 0, Stations = {}, Garden = { "sunbeam_bear" }, Gym = {}, CollectorCash = 0 } })
		local gardenFree = true
		for _, e in ipairs(TP.Fieldable()) do
			gardenFree = gardenFree and e.Key ~= "sunbeam_bear"
		end
		T.check(gardenFree and #TP.Fieldable() == 3, "hudteam portal: a gardening pet (its only copy in the Garden) is not fieldable")
		H.feed(FOUR, EMPTY_TEAMS)

		------------------------------------------------------------ the Dungeon panel's strip
		DC.Open(1)
		KC.advance(0.6)
		local strip = H.find(H.dungeonPanel(), "TeamStrip")
		local s1 = strip and H.find(strip, "StripSlot1")
		T.check(strip and H.shown(strip) and s1 and s1:FindFirstChild("Empty") and s1.Empty.Text == "Empty" and H.find(strip, "StripEdit") and H.find(strip, "StripAuto"),
			"hudteam portal: the Dungeon panel shows the team strip (empty slots) with Edit and Auto-fill best")
		if not strip then
			H.closeAll()
			Mock.SetViewport(old[1], old[2])
			return
		end
		T.check(H.find(strip, "StripEdit").Text == "Edit" and H.find(strip, "StripAuto").Text == "Auto-fill best", "hudteam portal: ...labelled Edit / Auto-fill best")
		local n0 = #Mock.RemoteLog
		Mock.Click(H.find(strip, "StripAuto"))
		KC.advance(0.1)
		local c = H.calls("BattleRequest", n0)
		T.check(#c == 1 and c[1].args[1] == "TeamSet" and c[1].args[2] == 1 and type(c[1].args[3]) == "table" and #c[1].args[3] == 3 and c[1].args[3][1] == best[1]
			and c[1].args[3][2] == best[2] and c[1].args[3][3] == best[3], "hudteam portal: Auto-fill best fires BattleRequest('TeamSet', active preset, the 3 best keys)", tostring(#c))
		H.feed(FOUR, H.teamOf(best))
		KC.advance(0.3)
		strip = H.find(H.dungeonPanel(), "TeamStrip")
		local name1 = strip and H.find(strip, "StripSlot1") and H.find(strip, "StripSlot1"):FindFirstChild("PetName")
		local want = PC and PetKeys and PC.Get(PetKeys.Parse(best[1]).PetId)
		T.check(name1 and want and name1.Text == want.Name and H.shown(name1), "hudteam portal: ...the strip shows the saved team", name1 and name1.Text)
		local lv = strip and H.find(strip, "StripSlot1"):FindFirstChild("Level")
		T.check(lv and lv.Text == "L14", "hudteam portal: ...with the level (L14)", lv and lv.Text)
		local el = strip and H.find(strip, "StripSlot1"):FindFirstChild("Element")
		T.check(el and el:FindFirstChild("Text") and el.Text.Text ~= "", "hudteam portal: ...and the element pill", el and el:FindFirstChild("Text") and el.Text.Text)
		Mock.Click(H.find(strip, "StripEdit"))
		KC.advance(0.5)
		local inv = H.menu():FindFirstChild("Window_Inventory")
		T.check(H.shown(inv) and H.find(inv, "Page_Team") and H.find(inv, "Page_Team").Visible, "hudteam portal: Edit opens Pets > Team")

		------------------------------------------------------------ the empty-team popup continues into the portal
		H.feed(FOUR, EMPTY_TEAMS)
		DC.Open(1)
		KC.advance(0.5)
		local d0 = #Mock.RemoteLog
		Mock.Click(H.find(H.dungeonPanel(), "SoloButton"))
		KC.advance(0.1)
		local pop = H.popup()
		local function dsends(mark, action)
			local out = {}
			for _, e in ipairs(H.calls("DungeonRequest", mark)) do
				if e.args[1] == action then
					out[#out + 1] = e
				end
			end
			return out
		end
		T.check(pop and pop.Visible and H.shown(pop) and #dsends(d0, "Solo") == 0, "hudteam portal: SOLO with an empty team opens the popup and sends nothing yet")
		if not pop then
			H.closeAll()
			Mock.SetViewport(old[1], old[2])
			return
		end
		local gui = pop.Parent
		T.check(gui:IsA("ScreenGui") and gui.DisplayOrder == 26 and TP.IsOpen() == true, "hudteam portal: ...in ScreenGui NimbusTeamPick (order 26); IsOpen() is true")
		local title = H.find(pop, "Title")
		T.check(H.find(pop, "PopSlot1") and H.find(pop, "PopSlot3") and H.find(pop, "PopAuto") and H.find(pop, "PopSave") and H.find(pop, "PopCancel")
			and title and title.Text == "Pick your battle team", "hudteam portal: ...3 slots, Auto-fill best, Save and enter, Cancel under 'Pick your battle team'")
		T.check(H.find(pop, "PopAuto").Text == "Auto-fill best" and H.find(pop, "PopSave").Text == "Save and enter" and H.find(pop, "PopCancel").Text == "Cancel",
			"hudteam portal: ...with those labels")
		local pn = H.find(H.find(pop, "PopSlot1"), "PetName")
		T.check(pn and want and pn.Text == want.Name, "hudteam portal: ...prefilled with the best pets (slot 1 = the strongest)", pn and pn.Text)
		-- a tap on a slot swaps in the next pet that is not in the team yet
		local slot3 = H.find(pop, "PopSlot3")
		local before = H.find(slot3, "PetName").Text
		Mock.Click(H.find(slot3, "Button"))
		KC.advance(0.1)
		local after = H.find(slot3, "PetName").Text
		local ok4 = PC and PC.Get("pebble_pup")
		T.check(after ~= before and ok4 and after == ok4.Name, "hudteam portal: tapping slot 3 swaps in the 4th pet", before .. " -> " .. after)
		local n1 = #Mock.RemoteLog
		Mock.Click(H.find(pop, "PopCancel"))
		KC.advance(0.1)
		T.check(not pop.Visible and #dsends(d0, "Solo") == 0 and #H.calls("BattleRequest", n1) == 0 and TP.IsOpen() == false, "hudteam portal: Cancel closes it and sends nothing")
		n1 = #Mock.RemoteLog
		Mock.Click(H.find(H.dungeonPanel(), "SoloButton"))
		KC.advance(0.1)
		Mock.Click(H.find(pop, "PopAuto"))
		KC.advance(0.1)
		Mock.Click(H.find(pop, "PopSave"))
		KC.advance(0.1)
		local bq = H.calls("BattleRequest", n1)
		T.check(#bq == 1 and bq[1].args[1] == "TeamSet" and bq[1].args[2] == 1 and #bq[1].args[3] == 3 and bq[1].args[3][1] == best[1] and #dsends(d0, "Solo") == 0,
			"hudteam portal: Save and enter fires TeamSet (Auto-fill best: the 3 best) and waits for the sync", tostring(#bq))
		T.check(pop.Visible, "hudteam portal: ...the popup stays while it saves")
		H.feed(FOUR, H.teamOf(best))
		KC.advance(0.3)
		local dq = dsends(d0, "Solo")
		T.check(#dq == 1 and dq[1].args[2] == 1 and not pop.Visible, "hudteam portal: ...then continues into the portal: DungeonRequest('Solo', 1)", tostring(#dq))
		-- a team: SOLO goes straight in
		local d1 = #Mock.RemoteLog
		KC.advance(0.5)
		Mock.Click(H.find(H.dungeonPanel(), "SoloButton"))
		KC.advance(0.1)
		T.check(not pop.Visible and #dsends(d1, "Solo") == 1, "hudteam portal: with a team SOLO sends at once (no popup)")

		-- a 2-pet player saves a 2-pet team; a 0-pet player gets the hint
		H.feed(TWO, EMPTY_TEAMS)
		local n2 = #Mock.RemoteLog
		KC.advance(0.5)
		Mock.Click(H.find(H.dungeonPanel(), "SoloButton"))
		KC.advance(0.1)
		Mock.Click(H.find(pop, "PopAuto"))
		KC.advance(0.1)
		Mock.Click(H.find(pop, "PopSave"))
		KC.advance(0.1)
		local two = H.calls("BattleRequest", n2)
		T.check(#two == 1 and #two[1].args[3] == 2, "hudteam portal: two pets: Save sends a 2-key team", two[1] and tostring(#two[1].args[3]))
		H.feed({}, EMPTY_TEAMS)
		Mock.Click(H.find(H.dungeonPanel(), "SoloButton"))
		KC.advance(0.1)
		T.check(not pop.Visible and H.hintText():find("You need a pet", 1, true) ~= nil, "hudteam portal: no pets: the hint, no popup", H.hintText())
		-- a save that never syncs
		H.feed(FOUR, EMPTY_TEAMS)
		local d2 = #Mock.RemoteLog
		KC.advance(0.5)
		Mock.Click(H.find(H.dungeonPanel(), "SoloButton"))
		KC.advance(0.1)
		Mock.Click(H.find(pop, "PopSave"))
		KC.advance(2.6)
		T.check(not pop.Visible and #dsends(d2, "Solo") == 0 and H.hintText():find("could not save", 1, true) ~= nil,
			"hudteam portal: no sync within 2.5 s: the popup closes with a hint and does not enter", H.hintText())
		-- a member's READY goes through the popup too
		local me = LocalPlayer.UserId
		KC.toClient("DungeonState", "Lobby", { Parties = {}, Record = { Best = 0, Cleared = {}, Runs = 0, Clears = 0 },
			Mine = { Leader = 501, Floor = 1, Members = { { UserId = 501, Name = "Ava", Ready = true, Power = 40 }, { UserId = me, Name = LocalPlayer.Name, Ready = false, Power = 0 } } } })
		KC.advance(0.6)
		local mstrip = H.find(H.dungeonPanel(), "TeamStrip")
		T.check(mstrip and H.shown(mstrip), "hudteam portal: a party member's box carries the strip too")
		local r0 = #Mock.RemoteLog
		Mock.Click(H.find(H.dungeonPanel(), "ReadyButton"))
		KC.advance(0.1)
		T.check(pop.Visible and #dsends(r0, "Ready") == 0, "hudteam portal: READY with an empty team opens the popup first")
		Mock.Click(H.find(pop, "PopCancel"))
		KC.advance(0.1)
		H.reset()
		H.closeAll()

		------------------------------------------------------------ the Arena panel
		local arena = workspace:FindFirstChild("BattleArena")
		if arena and arena:IsA("Model") and KC.root() then
			local ok, cf = pcall(function()
				return arena:GetBoundingBox()
			end)
			if ok and typeof(cf) == "CFrame" then
				Mock.Teleport(LocalPlayer, cf * CFrame.new(0, 4, 0))
				KC.advance(0.3)
			end
		end
		AC.OpenArena("Duels")
		KC.advance(0.5)
		local duels = H.find(H.arenaPanel(), "Page_Duels")
		T.check(duels and H.find(duels, "TeamStrip") and H.shown(H.find(duels, "TeamStrip")), "hudteam portal: the Arena Duels page carries the team strip")
		AC.OpenArena("Raid")
		KC.advance(0.3)
		local raid = H.find(H.arenaPanel(), "Page_Raid")
		T.check(raid and H.find(raid, "TeamStrip") and H.shown(H.find(raid, "TeamStrip")), "hudteam portal: ...and the Raid page")
		KC.toClient("ArenaState", {
			Next = { Kind = "BossRaid", BossId = "storm_titan", Name = "Storm Titan", StartsIn = 90, Announced = true },
			Raid = { Active = true, BossId = "lava_golem", Name = "Lava Golem", Hp = 500, MaxHp = 1000, Players = 2, EndsIn = 200, Joinable = true, JoinEndsIn = 40, Waiting = false, BattleId = "raid-1" },
			Double = { Active = false },
			Leaderboard = {},
		})
		KC.advance(0.4)
		local join = raid and H.find(raid, "JoinRaid")
		local why = join and join.Parent:FindFirstChild("Why")
		T.check(join and join:GetAttribute("Disabled") ~= true and why and why.Text == "", "hudteam portal: JOIN RAID is enabled with an empty team (the popup handles it)",
			why and why.Text)
		local n3 = #Mock.RemoteLog
		Mock.Click(join)
		KC.advance(0.1)
		T.check(pop.Visible and #H.calls("BattleRequest", n3) == 0, "hudteam portal: ...it opens the popup instead of sending JoinRaid")
		Mock.Click(H.find(pop, "PopAuto"))
		KC.advance(0.1)
		Mock.Click(H.find(pop, "PopSave"))
		KC.advance(0.1)
		H.feed(FOUR, H.teamOf(best))
		KC.advance(0.3)
		local after3 = H.calls("BattleRequest", n3)
		T.check(#after3 == 2 and after3[1].args[1] == "TeamSet" and after3[2].args[1] == "JoinRaid" and not pop.Visible, "hudteam portal: ...and continues with JoinRaid after the save",
			tostring(#after3))
		AC.OpenArena("Duels")
		KC.advance(0.3)
		H.feed(FOUR, EMPTY_TEAMS)
		local n4 = #Mock.RemoteLog
		Mock.Click(H.find(H.find(H.arenaPanel(), "Page_Duels"), "Queue"))
		KC.advance(0.1)
		T.check(pop.Visible and #H.calls("BattleRequest", n4) == 0, "hudteam portal: Find a match with an empty team opens the popup too")
		Mock.Click(H.find(pop, "PopCancel"))
		KC.advance(0.1)
		-- a team: Find a match sends at once
		H.feed(FOUR, H.teamOf(best))
		local n5 = #Mock.RemoteLog
		Mock.Click(H.find(H.find(H.arenaPanel(), "Page_Duels"), "Queue"))
		KC.advance(0.1)
		local q = H.calls("BattleRequest", n5)
		T.check(not pop.Visible and #q == 1 and q[1].args[1] == "Queue", "hudteam portal: with a team Find a match sends Queue at once")
		H.closeAll()
		H.reset()
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.5)
		KC.flushErrors("client_hudteam_portal")
	end)

	S.client_hudteam_mobile = guarded("client_hudteam_mobile", function()
		local TP = H.req("client/TeamPick")
		local DC = H.mod("DungeonController")
		if not T.check(type(TP) == "table" and type(TP.Ensure) == "function", "hudteam phone: client/TeamPick loads") then
			return
		end
		local UIS = game:GetService("UserInputService")
		local old = { Mock.Viewport.X, Mock.Viewport.Y, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = true, false, false
		Mock.SetViewport(844, 390)
		KC.advance(0.6)
		H.reset()
		H.closeAll()
		H.feed(FOUR, EMPTY_TEAMS)
		local entered = 0
		TP.Ensure(function()
			entered = entered + 1
		end)
		KC.advance(0.5)
		local pop = H.popup()
		if T.check(pop and H.shown(pop) and entered == 0, "hudteam phone: Ensure with an empty team opens the popup") then
			local p, s = pop.AbsolutePosition, pop.AbsoluteSize
			T.check(s.X <= 844 - 32 and s.Y <= 390 - 16, "hudteam phone: the popup fits a landscape phone with 16 px gutters", fmt("%.0f x %.0f", s.X, s.Y))
			T.check(p.X >= 16 - 0.5 and p.X + s.X <= 844 - 16 + 0.5 and p.Y >= 0 and p.Y + s.Y <= 390, "hudteam phone: ...inside the screen", fmt("%.0f,%.0f", p.X, p.Y))
			for _, name in ipairs({ "PopSave", "PopAuto", "PopCancel" }) do
				local b = H.find(pop, name)
				T.check(b and b.AbsoluteSize.Y >= 44, "hudteam phone: ..." .. name .. " stays >= 44 px", b and fmt("%.1f", b.AbsoluteSize.Y))
			end
			local small = KC.smallTexts and KC.smallTexts(14) or {}
			local mine = {}
			for _, item in ipairs(type(small) == "table" and small or {}) do
				if tostring(item):find("Pop", 1, true) or tostring(item):find("TeamPick", 1, true) then
					mine[#mine + 1] = tostring(item)
				end
			end
			T.check(#mine == 0, "hudteam phone: every popup text >= 14 px", table.concat(mine, ", "))
		end
		TP.Close()
		KC.advance(0.3)
		if DC then
			pcall(DC.Init)
			DC.Open(1)
			KC.advance(1)
			local win = H.dungeonPanel()
			local strip = win and H.find(win, "TeamStrip")
			if T.check(strip and H.shown(strip), "hudteam phone: the Dungeon panel shows the strip on a landscape phone") then
				local wr, sr = win.AbsolutePosition.X + win.AbsoluteSize.X, strip.AbsolutePosition.X + strip.AbsoluteSize.X
				T.check(strip.AbsolutePosition.X >= win.AbsolutePosition.X - 0.5 and sr <= wr + 0.5, "hudteam phone: ...inside the window", fmt("%.0f <= %.0f", sr, wr))
			end
		end
		H.closeAll()
		H.reset()
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[3], old[4], old[5]
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.6)
		KC.flushErrors("client_hudteam_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
