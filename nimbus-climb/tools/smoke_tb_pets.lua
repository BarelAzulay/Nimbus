-- smoke_tb_pets.lua: team balance, Task 4: the Pets window (spec s.3, one big window with the slots pinned on top; the Pets
-- and Team tabs of MenuController are gone). Client worlds only (loaded by tools/smoke.py):
--   client_tb_pets_pc       (1920x1080) ScreenGui NimbusPets: 1260x900 centred, no Window_Inventory, WindowOpened("Pets") once per
--                           opening, Slot1..3 with FIGHTER / HELPER, the grid is the only scroller, one sort control, busy
--                           marks + number badges + the tier chip + evolved stars on the cards, team power without busy pets
--                           and its breakdown, no "Equip" word, PresetB sends TeamSelect(2), MenuController routes
--   client_tb_pets_pick     pick mode: the banner + glow, one tap = TeamSet at once with the pop and the heavy sound, a swap,
--                           the holes that keep a busy pet's slot (the server's kept rule), X cancels, a gardening pet asks
--                           for the recall and keeps pick mode armed (Review Focus 3), a refused TeamSet reverts AT ONCE with
--                           the toast and re-arms, a save that never syncs says so, Auto-fill best + Undo, Clear's second tap
--   client_tb_pets_actions  the detail's rows (Task 1's numbers), Put in team, Make fighter (a swap with slot 1), Remove, Feed and
--                           Train come back to the window (and keep Open's ReturnTo), Evolve keeps its confirm, Garden stays a
--                           HomeAction, Closed hands ReturnTo back, an Evolve pill opens the confirm, the Esc order
--   client_tb_pets_phone    (844x390 touch) 820x330 under the top bar, the slots in a column on the left, 104 x 130 cards, every
--                           target >= 44 px, the sheet over the grid (not the slots) with its actions at the bottom edge; the
--                           menu tiles step aside; 667x375 and 640x360: the top row ends before the close button, labels fit;
--                           a 1024x768 touch tablet: PC layout, touch controls off while open, targets >= 44 px
-- Deterministic: mock clock only. The viewport, the attributes and the profile are restored at the end.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

local function serverScenarios()
	return {}
end

local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local H = {}

	-- the fixture: three team pets, two more free pets, one training, one fully gardening, a Golden copy, one that can
	-- evolve, one evolved. Levels make the power order the level order among same-rarity pets only, so the tests read it.
	local K1, K2, K3, K4, K5 = "ember_phoenix", "biscuit_bear", "sunbeam_bear", "pebble_pup", "maple_fox"
	local TRAINING, GARDEN, GOLDEN, READY, EVOLVED = "sleepy_owl", "bubble_axolotl", "honey_bunny@Golden", "mallow_kitten", "pip_penguin"
	local LEVELS = { [K1] = 14, [K2] = 10, [K3] = 6, [K4] = 2, [K5] = 8, [TRAINING] = 12, [GARDEN] = 9, [GOLDEN] = 5, [READY] = 22, [EVOLVED] = 25 }

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
	function H.win()
		local gui = H.pg():FindFirstChild("NimbusPets")
		return gui and gui:FindFirstChild("PetsWindow", true)
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
	function H.card(key)
		return H.find(H.win(), "Card_" .. key)
	end
	function H.slot(i)
		return H.find(H.win(), "Slot" .. i)
	end
	function H.slotPart(i, name)
		return H.slot(i):FindFirstChild(name) or H.find(H.slot(i), name)
	end
	function H.cardOrder()
		local out = {}
		for _, c in ipairs(H.find(H.win(), "Grid"):GetChildren()) do
			if c.Name:sub(1, 5) == "Card_" then
				out[#out + 1] = c
			end
		end
		table.sort(out, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i, c in ipairs(out) do
			out[i] = c.Name:sub(6)
		end
		return out
	end
	function H.clickName(name)
		local b = H.find(H.win(), name)
		if T.check(b ~= nil, "tb pets: " .. name .. " exists") then
			Mock.Click(b)
		end
		return b
	end
	function H.teamSets(mark)
		local out = {}
		for _, c in ipairs(KC.serverCalls("BattleRequest", mark)) do
			if c.args[1] == "TeamSet" then
				out[#out + 1] = c
			end
		end
		return out
	end
	function H.list(args)
		local out = {}
		for i = 1, 4 do
			if args[3][i] ~= nil then
				out[#out + 1] = tostring(args[3][i])
			end
		end
		return table.concat(out, ",")
	end
	function H.lastSet(mark)
		local sets = H.teamSets(mark)
		return sets[#sets]
	end
	function H.anyText(root, needle)
		local found = {}
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and tostring(d.Text):lower():find(needle, 1, true) then
				found[#found + 1] = d.Name .. "=" .. tostring(d.Text)
			end
		end
		return found
	end
	function H.scrollers(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("ScrollingFrame") then
				out[#out + 1] = d
			end
		end
		return out
	end
	-- every button a thumb can reach right now
	function H.targets(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("TextButton") or d:IsA("ImageButton")) and H.shown(d) then
				out[#out + 1] = d
			end
		end
		return out
	end
	-- a ProfileSync snapshot: the fixture with a team list for preset 1, { Preset = n, Teams = table, Pets = table, Growth = table }
	function H.snapshot(opts)
		opts = opts or {}
		local pets, levels, discovered, tiers = {}, {}, {}, {}
		for key, level in pairs(LEVELS) do
			local base, tier = key:match("^(.-)@(%a+)$")
			if tier then
				tiers[base] = { [tier] = 1 }
			else
				pets[key] = 1
			end
			levels[key] = { Level = level, Xp = 10 }
			discovered[base or key] = true
		end
		local growth = {
			[TRAINING] = { Job = { Stat = "Physique", Ends = os.time() + 130, Rank = 1, Slot = 1, From = "Free", Paid = 0 } },
			[EVOLVED] = { Evo = 1 },
		}
		local teams = opts.Teams or { Presets = { { K1, K2, K3 }, { K4 }, {} }, Active = 1, Slots = 3 }
		teams.Busy = { [TRAINING] = "Training", [GARDEN] = "Garden" }
		local equipped = {}
		for _, key in ipairs(teams.Presets[teams.Active]) do
			if not teams.Busy[key] then
				equipped[#equipped + 1] = key
			end
		end
		return {
			Tokens = 900, Pets = pets, Equipped = equipped, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = discovered, IndexClaimed = {},
			Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 1000, Gems = 0,
			Home = { Level = 5, Prestige = 0, Stations = { Garden = 1 }, Garden = { GARDEN }, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = tiers, Hybrids = {},
			PetLevels = levels,
			Teams = teams,
			Battle = { Trophies = 120, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			PetGrowth = growth,
			Ring = { Best = 0, Runs = 0 },
		}
	end
	function H.feed(team, active)
		local teams = team and { Presets = { team, { K4 }, {} }, Active = active or 1, Slots = 3 } or nil
		KC.toClient("ProfileSync", H.snapshot({ Teams = teams }))
		KC.advance(0.1)
	end
	function H.reset()
		local Config = KC.env()
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		KC.toClient("MatchState", nil)
		KC.toClient("PartyState", nil)
		KC.advance(0.2)
	end
	function H.closeAll()
		for _, name in ipairs({ "CareController", "PetsController", "MenuController", "ArenaController", "DungeonController", "ObbyController" }) do
			local m = H.mod(name)
			if m and type(m.Close) == "function" then
				pcall(m.Close, true)
			end
		end
		KC.advance(0.5)
	end
	function H.power(key)
		local BC, PKeys = H.req("shared/BattleCatalog"), H.req("shared/PetKeys")
		local State = H.req("client/State")
		local parsed = PKeys.Parse(key)
		return math.floor(BC.UnitPower({ Def = State.DefOf(key), Key = key, Level = LEVELS[key], Tier = parsed and parsed.Tier or "Normal",
			Evo = State.PetStage(key), Train = {} }) + 0.5)
	end
	function H.teamPower(keys)
		local BC = H.req("shared/BattleCatalog")
		local State = H.req("client/State")
		local entries = {}
		for i, key in ipairs(keys) do
			entries[i] = { Def = State.DefOf(key), Key = key, Level = LEVELS[key], Tier = "Normal", Evo = State.PetStage(key), Train = {} }
		end
		return BC.TeamPower(entries)
	end
	-- runs fn at a screen size with a clean profile and everything closed; restores the screen after
	function H.at(w, h, touch, label, fn)
		local PC = H.mod("PetsController")
		if not T.check(type(PC) == "table" and type(PC.Open) == "function", label .. ": client/Controllers/PetsController loads") then
			return
		end
		local UIS = game:GetService("UserInputService")
		local old = { Mock.Viewport.X, Mock.Viewport.Y, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = touch, not touch, not touch
		Mock.SetViewport(w, h)
		KC.advance(0.6)
		H.reset()
		H.closeAll()
		H.feed()
		local ok, err = pcall(fn, PC)
		if not ok then
			T.fail(label .. ": error", tostring(err))
		end
		H.closeAll()
		H.feed()
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[3], old[4], old[5]
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.6)
		KC.flushErrors(label)
	end

	S.client_tb_pets_pc = guarded("client_tb_pets_pc", function()
		H.at(1920, 1080, false, "client_tb_pets_pc", function(PC)
			local MC = H.mod("MenuController")
			local opened = {}
			local conn = MC.WindowOpened:Connect(function(id)
				opened[#opened + 1] = tostring(id)
			end)
			PC.Open({})
			KC.advance(0.5)
			local win = H.win()
			if not T.check(H.shown(win), "tb pets: NimbusPets > PetsWindow opens") then
				conn:Disconnect()
				return
			end
			local gui = H.pg():FindFirstChild("NimbusPets")
			T.check(gui.IgnoreGuiInset == true, "tb pets: the window's ScreenGui measures from the screen's top")
			T.check(PC.IsOpen() == true and PC.Layout() == "PC", "tb pets: IsOpen + the PC layout")
			T.check(math.abs(win.AbsoluteSize.X - 1260) <= 2 and math.abs(win.AbsoluteSize.Y - 900) <= 2 and math.abs(win.AbsolutePosition.X + win.AbsoluteSize.X / 2 - 960) <= 2,
				"tb pets: 1260x900 centred at 1080p", fmt("%.0fx%.0f at %.0f", win.AbsoluteSize.X, win.AbsoluteSize.Y, win.AbsolutePosition.X))
			T.check(win.AbsolutePosition.Y >= 58 - 0.5 and win.AbsolutePosition.Y + win.AbsoluteSize.Y <= 1080, "tb pets: ...under the top bar, on the screen", fmt("y %.0f", win.AbsolutePosition.Y))
			T.check(H.menu():FindFirstChild("Window_Inventory") == nil, "tb pets: no Window_Inventory any more")
			T.check(#opened == 1 and opened[1] == "Pets", "tb pets: WindowOpened('Pets') fired once", table.concat(opened, ","))
			T.check(MC.IsOpen() == true, "tb pets: MenuController.IsOpen() knows the window is up")
			PC.Open({})
			KC.advance(0.1)
			T.check(#opened == 1, "tb pets: ...a second Open of the open window does not fire it again")
			for i = 1, 3 do
				T.check(H.slot(i) ~= nil and H.shown(H.slot(i)), "tb pets: Slot" .. i)
			end
			T.check(H.slotPart(1, "Tag").Text == "FIGHTER" and H.slotPart(2, "Tag").Text == "HELPER" and H.slotPart(3, "Tag").Text == "HELPER", "tb pets: FIGHTER / HELPER tags")
			T.check(H.slotPart(1, "Level").Text == "L14" and H.slotPart(1, "Power").Text:find(tostring(H.power(K1)), 1, true) ~= nil and H.slotPart(1, "Face") ~= nil, "tb pets: a slot shows the face, the level and the power", H.slotPart(1, "Power").Text)
			local sc = H.scrollers(win)
			T.check(#sc == 1 and sc[1].Name == "Grid", "tb pets: the grid is the only scroller (no nested scrolling)", tostring(#sc))
			-- the sort control
			local rows = {}
			for key in pairs(LEVELS) do
				rows[#rows + 1] = key
			end
			table.sort(rows, function(a, b)
				return H.power(a) > H.power(b)
			end)
			T.check(H.cardOrder()[1] == rows[1] and PC.Sort() == "Strongest" and H.find(win, "SortButton").Text == "Strongest", "tb pets: sorted Strongest by default", H.cardOrder()[1])
			T.eq(#H.cardOrder(), 10, "tb pets: one card per owned copy")
			H.clickName("SortButton")
			KC.advance(0.1)
			T.check(PC.Sort() == "Rarest" and H.find(win, "SortButton").Text == "Rarest", "tb pets: one sort control; a tap goes to Rarest")
			local PCat = H.req("shared/PetCatalog")
			local RANK = {}
			for i, r in ipairs(H.req("shared/Config").Rarities or {}) do
				RANK[type(r) == "table" and r.Id or r] = i
			end
			local first, second = H.req("client/State").DefOf(H.cardOrder()[1]), H.req("client/State").DefOf(H.cardOrder()[#H.cardOrder()])
			T.check(PCat and first and second and (RANK[first.Rarity] or 0) >= (RANK[second.Rarity] or 0), "tb pets: ...rarest first", tostring(first and first.Rarity))
			H.clickName("SortButton")
			KC.advance(0.1)
			T.check(PC.Sort() == "Level" and H.cardOrder()[1] == EVOLVED and H.cardOrder()[2] == READY, "tb pets: ...then Level", H.cardOrder()[1])
			H.clickName("SortButton")
			KC.advance(0.1)
			T.check(PC.Sort() == "Strongest", "tb pets: ...and back to Strongest")
			PC.SetSort("Level")
			T.check(PC.Sort() == "Level" and H.cardOrder()[1] == EVOLVED, "tb pets: SetSort works")
			PC.SetSort("junk")
			T.check(PC.Sort() == "Level", "tb pets: SetSort ignores junk")
			PC.SetSort("Strongest")
			-- the cards
			local function shownPart(card, name)
				local part = H.find(card, name)
				return part ~= nil and part.Visible == true
			end
			T.check(shownPart(H.card(TRAINING), "Busy") and shownPart(H.card(GARDEN), "Busy") and not shownPart(H.card(K4), "Busy"), "tb pets: busy marks on the training and the gardening pet only")
			T.check(H.find(H.card(K1), "Number").Text == "1" and H.find(H.card(K2), "Number").Text == "2" and shownPart(H.card(K3), "Number") and not shownPart(H.card(K4), "Number"), "tb pets: the team number badge")
			T.check(H.find(H.card(K4), "Level").Text == "L2" and H.find(H.card(K4), "Power").Text:find(tostring(H.power(K4)), 1, true) ~= nil, "tb pets: a card shows the level and the power")
			T.check(shownPart(H.card(K4), "Picture") and H.find(H.card(K4), "Rarity") and H.find(H.card(K4), "Rarity"):IsA("UIStroke"), "tb pets: the picture and the rarity border")
			local Config = H.req("shared/Config")
			local elementOf = PCat.ElementsOf(PCat.Get(K1))[1]
			T.check(H.find(H.card(K1), "Element").BackgroundColor3 == Config.Elements.Info[elementOf].Color, "tb pets: the element icon wears the element's colour", elementOf)
			T.check(shownPart(H.card(GOLDEN), "Tier") and H.find(H.card(GOLDEN), "Tier"):FindFirstChild("Mark").Text == "G" and not shownPart(H.card(K4), "Tier"), "tb pets: the Golden copy keeps its tier chip")
			T.check(shownPart(H.card(EVOLVED), "Stars") and not shownPart(H.card(K4), "Stars"), "tb pets: the evolved pet keeps its star")
			T.check(H.find(H.card(K4), "Name").Text == H.req("client/State").DefOf(K4).Name and shownPart(H.card(K4), "Name"), "tb pets: the name shows on PC cards")
			-- the team's numbers: busy pets out
			local want = H.teamPower({ K1, K2, K3 })
			T.check(H.find(win, "TeamPower").Text == "Team power " .. want, "tb pets: Team power", H.find(win, "TeamPower").Text)
			T.check(H.find(win, "TeamBreakdown").Text:find("^Fighter " .. H.power(K1) .. " %+ helpers " .. H.power(K2) .. ", " .. H.power(K3)) ~= nil, "tb pets: the one-line breakdown", H.find(win, "TeamBreakdown").Text)
			H.feed({ TRAINING, K2 })
			KC.advance(0.1)
			want = H.teamPower({ K2 })
			T.check(H.find(win, "TeamPower").Text == "Team power " .. want, "tb pets: ...a busy pet is left out of the power", H.find(win, "TeamPower").Text)
			T.check(H.slotPart(1, "Busy").Visible and H.slotPart(1, "Level").Text == "L12" and H.slotPart(2, "Tag").Text == "FIGHTER", "tb pets: a busy pet keeps its slot, greyed; the next free pet is the fighter")
			H.feed()
			-- the words
			local equip = H.anyText(win, "equip")
			T.check(#equip == 0, "tb pets: the Equip words are gone", table.concat(equip, " | "))
			-- A / B / C
			T.check(H.find(win, "PresetA").Text == "A" and H.find(win, "PresetB").Text == "B" and H.find(win, "PresetC").Text == "C", "tb pets: the A / B / C group")
			T.check(H.find(win, "PresetA"):GetAttribute("Selected") == true and H.find(win, "PresetB"):GetAttribute("Selected") ~= true, "tb pets: the active team is lit")
			local mark = #Mock.RemoteLog
			H.clickName("PresetB")
			local calls = KC.serverCalls("BattleRequest", mark)
			T.check(#calls == 1 and calls[1].args[1] == "TeamSelect" and calls[1].args[2] == 2, "tb pets: B sends TeamSelect(2)")
			T.check(H.find(win, "PresetB"):GetAttribute("Selected") == true and H.slotPart(1, "Level").Text == "L2" and H.slotPart(2, "Empty").Visible, "tb pets: ...and shows team B at once")
			H.feed({ K1, K2, K3 }, 2)
			KC.advance(0.1)
			T.check(H.find(win, "PresetB"):GetAttribute("Selected") == true and H.slotPart(1, "Level").Text == "L2", "tb pets: ...the sync confirms it")
			KC.advance(0.5)
			mark = #Mock.RemoteLog
			H.clickName("PresetA")
			KC.toClient("Notify", "You cannot do that during a match", "bad", 3)
			KC.advance(0.1)
			T.check(H.find(win, "PresetB"):GetAttribute("Selected") == true and H.hintText():find("during a match", 1, true) ~= nil, "tb pets: a refused team change goes back at once and says why", H.hintText())
			H.feed()
			-- the routes of MenuController
			PC.Close(true)
			KC.advance(0.3)
			T.check(PC.IsOpen() == false and MC.IsOpen() == false and not H.shown(win), "tb pets: Close")
			for _, route in ipairs({ { "Pets", {} }, { "Team", {} }, { "Inventory", {} } }) do
				MC.Open(route[1], route[2])
				KC.advance(0.2)
				T.check(PC.IsOpen() == true, "tb pets: MenuController.Open('" .. route[1] .. "') opens the window")
				MC.Close()
				KC.advance(0.3)
				T.check(PC.IsOpen() == false, "tb pets: MenuController.Close() closes it")
			end
			MC.OpenTeam(2)
			KC.advance(0.2)
			T.check(PC.IsOpen() == true and H.find(win, "PresetB"):GetAttribute("Shown") == true and H.slotPart(1, "Level").Text == "L2", "tb pets: OpenTeam(2) shows team B", H.slotPart(1, "Level").Text)
			MC.Close()
			KC.advance(0.3)
			Mock.Click(MC.GetButton("Pets"))
			KC.advance(0.2)
			T.check(PC.IsOpen() == true, "tb pets: the Pets tile opens it")
			T.check(MC.GetButton("Pets"):GetAttribute("Disabled") ~= true, "tb pets: the tile is enabled")
			Mock.Click(MC.GetButton("Pets"))
			KC.advance(0.3)
			T.check(PC.IsOpen() == false, "tb pets: ...and closes it")
			-- one window at a time
			PC.Open({})
			KC.advance(0.2)
			MC.Open("Stats", {})
			KC.advance(0.3)
			T.check(PC.IsOpen() == false and H.menu():FindFirstChild("Window_Stats").Visible, "tb pets: another window closes it")
			opened = {}
			PC.Open({})
			KC.advance(0.3)
			T.check(not H.menu():FindFirstChild("Window_Stats").Visible and opened[1] == "Pets", "tb pets: ...and it closes the other windows")
			PC.Close(true)
			KC.advance(0.3)
			-- entering a match closes it
			local Cfg = KC.env()
			PC.Open({})
			KC.advance(0.2)
			LocalPlayer:SetAttribute(Cfg.Attr.InMatch, true)
			KC.advance(0.3)
			T.check(PC.IsOpen() == false, "tb pets: a match closes it")
			LocalPlayer:SetAttribute(Cfg.Attr.InMatch, false)
			conn:Disconnect()
		end)
	end)

	S.client_tb_pets_pick = guarded("client_tb_pets_pick", function()
		H.at(1920, 1080, false, "client_tb_pets_pick", function(PC)
			local SF = H.req("client/SoundFx")
			local played = {}
			local realPlay = SF.Play
			SF.Play = function(name, opts)
				played[#played + 1] = name
				return realPlay(name, opts)
			end
			PC.Open({})
			KC.advance(0.5)
			local win = H.win()
			local function banner()
				return H.find(win, "PickBanner")
			end
			T.check(not banner().Visible, "tb pets: no banner before a slot is tapped")
			Mock.Click(H.slot(2))
			KC.advance(0.05)
			T.check(banner().Visible and banner().Text == "Pick a helper for slot 2" and H.slotPart(2, "Glow").Visible and not H.slotPart(1, "Glow").Visible, "tb pets: pick mode on slot 2", banner().Text)
			Mock.Click(H.slot(2))
			KC.advance(0.05)
			T.check(not banner().Visible and not H.slotPart(2, "Glow").Visible, "tb pets: tapping the slot again cancels")
			Mock.Click(H.slot(1))
			KC.advance(0.05)
			T.check(banner().Text == "Pick your fighter", "tb pets: slot 1 asks for the fighter", banner().Text)
			H.clickName("PickCancel")
			KC.advance(0.05)
			T.check(not banner().Visible, "tb pets: X cancels")
			-- one tap drops it in, at once
			Mock.Click(H.slot(2))
			local mark = #Mock.RemoteLog
			played = {}
			Mock.Click(H.card(K5))
			local set = H.lastSet(mark)
			T.check(set and H.list(set.args) == table.concat({ K1, K5, K3 }, ",") and set.args[2] == 1, "tb pets: one tap sends TeamSet at once", set and H.list(set.args))
			T.check(H.slotPart(2, "Level").Text == "L" .. LEVELS[K5], "tb pets: ...the slot shows the pet at once", H.slotPart(2, "Level").Text)
			T.check(not banner().Visible, "tb pets: ...pick mode ends")
			T.check(played[#played] == "SpinLand", "tb pets: ...with the heavy sound (an approved id)", tostring(played[#played]))
			local pop = H.slot(2):FindFirstChild("Pop")
			T.check(pop and pop.Scale ~= nil and pop.Scale >= 1, "tb pets: ...and the pop")
			H.feed({ K1, K5, K3 })
			KC.advance(0.5)
			T.check(H.slotPart(2, "Level").Text == "L" .. LEVELS[K5], "tb pets: the sync agrees: it stays")
			-- a pet in another slot swaps
			Mock.Click(H.slot(3))
			mark = #Mock.RemoteLog
			Mock.Click(H.card(K1))
			set = H.lastSet(mark)
			T.check(set and H.list(set.args) == table.concat({ K3, K5, K1 }, ","), "tb pets: a pet already in another slot swaps positions", set and H.list(set.args))
			H.feed({ K3, K5, K1 })
			KC.advance(0.5)
			-- the slot's own pet offers Remove: pick mode ends on its details
			Mock.Click(H.slot(3))
			mark = #Mock.RemoteLog
			Mock.Click(H.card(K1))
			KC.advance(0.05)
			T.check(#H.teamSets(mark) == 0 and not banner().Visible and H.find(win, "ActRemove").Visible and H.find(H.find(win, "Detail"), "Name").Text == H.req("client/State").DefOf(K1).Name,
				"tb pets: tapping the slot's own pet offers Remove and sends nothing")
			-- an empty slot past the first empty one picks the first empty one (the server compacts)
			H.feed({ K1 })
			KC.advance(0.5)
			Mock.Click(H.slot(3))
			KC.advance(0.05)
			T.check(H.slotPart(2, "Glow").Visible and banner().Text == "Pick a helper for slot 2", "tb pets: a later empty slot picks the first empty one", banner().Text)
			H.clickName("PickCancel")
			H.feed()
			KC.advance(0.5)
			-- Review Focus 3: a gardening pet
			Mock.Click(H.slot(1))
			mark = #Mock.RemoteLog
			Mock.Click(H.card(GARDEN))
			KC.advance(0.1)
			local gui = H.pg():FindFirstChild("NimbusPets")
			local recall = gui:FindFirstChild("GardenRecall")
			T.check(recall and H.shown(recall) and H.slotPart(1, "Level").Text == "L" .. LEVELS[K1] and #H.teamSets(mark) == 0, "tb pets: a gardening pet asks for the recall, the slot stays")
			T.check(banner().Visible and H.slotPart(1, "Glow").Visible, "tb pets: ...pick mode stays armed under the question")
			T.check(#H.anyText(recall, "equip") == 0 and #H.anyText(recall, "put it in your team") == 1, "tb pets: ...in team words")
			Mock.Click(H.find(recall, "RecallNo"))
			KC.advance(0.1)
			T.check(gui:FindFirstChild("GardenRecall") == nil and banner().Visible and H.slotPart(1, "Glow").Visible and H.slotPart(1, "Level").Text == "L" .. LEVELS[K1], "tb pets: No: pick mode stays armed on the same slot")
			Mock.Click(H.card(GARDEN))
			KC.advance(0.1)
			recall = gui:FindFirstChild("GardenRecall")
			mark = #Mock.RemoteLog
			Mock.Click(H.find(recall, "RecallYes"))
			local home = KC.serverCalls("HomeAction", mark)
			T.check(#home == 1 and home[1].args[1] == "GardenRecall" and home[1].args[2].Key == GARDEN and home[1].args[2].To == "Team" and home[1].args[2].Preset == 1 and home[1].args[2].Keys[1] == GARDEN,
				"tb pets: Yes: one GardenRecall with the team")
			T.check(H.slotPart(1, "Level").Text == "L" .. LEVELS[GARDEN] and not banner().Visible, "tb pets: ...the slot shows it at once")
			-- ...the server refuses: the toast at once, the slot back, pick mode armed
			KC.toClient("Notify", "Your Garden is locked right now", "bad", 3)
			KC.advance(0.05)
			T.check(H.hintText():find("Garden is locked", 1, true) ~= nil and H.slotPart(1, "Level").Text == "L" .. LEVELS[K1] and banner().Visible and H.slotPart(1, "Glow").Visible,
				"tb pets: a refusal shows at once, the slot goes back, pick mode is armed again", H.hintText())
			H.clickName("PickCancel")
			KC.advance(0.5)
			-- a training pet: refused on the spot, armed
			Mock.Click(H.slot(2))
			mark = #Mock.RemoteLog
			Mock.Click(H.card(TRAINING))
			KC.advance(0.05)
			T.check(#H.teamSets(mark) == 0 and H.hintText():find("is training", 1, true) ~= nil and banner().Visible and H.slotPart(2, "Level").Text == "L" .. LEVELS[K2], "tb pets: a training pet says why at once and stays armed", H.hintText())
			-- a refused TeamSet (Notify "bad" within 2.5 s)
			mark = #Mock.RemoteLog
			Mock.Click(H.card(K5))
			T.check(H.slotPart(2, "Level").Text == "L" .. LEVELS[K5], "tb pets: the slot shows the new pet")
			KC.toClient("Notify", "That pet is training (2:10 left)", "bad", 3)
			KC.advance(0.05)
			T.check(H.hintText():find("training (2:10", 1, true) ~= nil and H.slotPart(2, "Level").Text == "L" .. LEVELS[K2] and banner().Visible and H.slotPart(2, "Glow").Visible, "tb pets: a refused TeamSet goes back at once with the toast and re-arms", H.hintText())
			-- a "bad" Notify with nothing pending is none of the window's business
			H.clickName("PickCancel")
			KC.advance(3.2)
			T.check(H.hintText() == "", "tb pets: (the toast is gone)", H.hintText())
			KC.toClient("Notify", "Something else went wrong", "bad", 3)
			KC.advance(0.05)
			T.check(H.hintText() == "", "tb pets: a bad Notify with nothing pending stays out of the window", H.hintText())
			-- a sync that does not show the keys does not revert early; no answer at all says so after 2.5 s
			Mock.Click(H.slot(2))
			KC.advance(0.5)
			Mock.Click(H.card(K5))
			H.feed()
			T.check(H.slotPart(2, "Level").Text == "L" .. LEVELS[K5], "tb pets: an unrelated sync does not undo a pending pick")
			KC.advance(2.6)
			T.check(H.slotPart(2, "Level").Text == "L" .. LEVELS[K2] and H.hintText():find("could not save", 1, true) ~= nil and banner().Visible, "tb pets: no answer: the slot goes back and it says so", H.hintText())
			H.clickName("PickCancel")
			KC.advance(3)
			-- a busy pet keeps its slot through an edit: holes, not a shift (the server's kept rule)
			H.feed({ K1, K2, TRAINING })
			KC.advance(0.5)
			mark = #Mock.RemoteLog
			Mock.Click(H.card(K2))
			KC.advance(0.05)
			H.clickName("ActRemove")
			set = H.lastSet(mark)
			T.check(set and set.args[3][1] == K1 and (set.args[3][2] == "" or set.args[3][2] == false) and set.args[3][3] == TRAINING, "tb pets: Remove in the middle sends a hole, so the busy pet keeps its slot", set and H.list(set.args))
			T.check(H.slotPart(1, "Level").Text == "L" .. LEVELS[K1] and H.slotPart(2, "Level").Text == "L" .. LEVELS[TRAINING], "tb pets: ...the slots show the compacted team")
			H.feed({ K1, TRAINING })
			KC.advance(0.5)
			H.feed()
			KC.advance(0.5)
			-- quick edits are spaced for the server's cooldown: the last one always arrives
			mark = #Mock.RemoteLog
			Mock.Click(H.slot(2))
			Mock.Click(H.card(K5))
			Mock.Click(H.slot(3))
			Mock.Click(H.card(K4))
			T.check(#H.teamSets(mark) == 1, "tb pets: a second edit inside the cooldown waits", tostring(#H.teamSets(mark)))
			KC.advance(0.6)
			set = H.lastSet(mark)
			T.check(#H.teamSets(mark) == 2 and set and H.list(set.args) == table.concat({ K1, K5, K4 }, ","), "tb pets: ...and then goes out with both", set and H.list(set.args))
			H.feed({ K1, K5, K4 })
			KC.advance(0.5)
			-- the server's shared BattleRequest bucket (burst 4, refill 1/s; a miss gets no answer at all): a quick string of
			-- edits waits for it instead of reading as a failed save. The server's bucket is modelled here on the mock clock
			H.feed()
			KC.advance(6)
			mark = #Mock.RemoteLog
			local tokens, tokensAt, counted, dropped = 4, os.clock(), 0, 0
			local function pump(seconds)
				local stop = os.clock() + seconds
				while os.clock() < stop do
					KC.advance(0.05)
					local sets = H.teamSets(mark)
					while counted < #sets do
						counted = counted + 1
						tokens = math.min(4, tokens + (os.clock() - tokensAt))
						tokensAt = os.clock()
						if tokens < 1 then
							dropped = dropped + 1
						else
							tokens = tokens - 1
							local args = sets[counted].args
							H.feed({ args[3][1], args[3][2], args[3][3] })
						end
					end
				end
			end
			for i = 1, 8 do
				Mock.Click(H.slot(3))
				Mock.Click(H.card(i % 2 == 1 and K5 or K4))
				pump(0.46)
			end
			pump(4)
			set = H.lastSet(mark)
			T.check(dropped == 0, "tb pets: eight quick edits stay inside the server's request bucket", fmt("%d of %d dropped", dropped, counted))
			T.check(set and H.list(set.args) == table.concat({ K1, K2, K4 }, ","), "tb pets: ...the last edit arrives", set and H.list(set.args))
			T.check(H.hintText():find("could not save", 1, true) == nil, "tb pets: ...and nothing reads as a failed save", H.hintText())
			H.feed({ K1, K5, K4 })
			KC.advance(0.5)
			-- Auto-fill best
			local rows = {}
			for key in pairs(LEVELS) do
				if key ~= TRAINING and key ~= GARDEN then
					rows[#rows + 1] = key
				end
			end
			table.sort(rows, function(a, b)
				return H.power(a) > H.power(b)
			end)
			local best = table.concat({ rows[1], rows[2], rows[3] }, ",")
			mark = #Mock.RemoteLog
			local undo = H.find(win, "Undo")
			T.check(undo and not undo.Visible, "tb pets: no Undo before Auto-fill best")
			T.check(H.clickName("AutoFill").Text == "Auto-fill best", "tb pets: the button says Auto-fill best")
			set = H.lastSet(mark)
			T.check(set and set.args[2] == 1 and H.list(set.args) == best, "tb pets: Auto-fill best writes the 3 strongest free pets to the active team (busy pets out)", set and H.list(set.args))
			T.check(H.hintText():find("Team filled", 1, true) ~= nil and H.shown(undo), "tb pets: ...with a toast and Undo", H.hintText())
			H.feed({ rows[1], rows[2], rows[3] })
			KC.advance(0.5)
			mark = #Mock.RemoteLog
			Mock.Click(undo)
			set = H.lastSet(mark)
			T.check(set and H.list(set.args) == table.concat({ K1, K5, K4 }, ","), "tb pets: Undo sends the previous keys", set and H.list(set.args))
			T.check(not undo.Visible, "tb pets: ...once")
			H.feed({ K1, K5, K4 })
			KC.advance(0.5)
			H.clickName("AutoFill")
			KC.advance(6.2)
			T.check(not undo.Visible, "tb pets: Undo goes after 6 s")
			H.feed({ K1, K5, K4 })
			KC.advance(0.5)
			-- Clear asks for a second tap
			local clear = H.find(win, "ClearTeam")
			mark = #Mock.RemoteLog
			T.check(clear.Text == "Clear", "tb pets: Clear")
			Mock.Click(clear)
			KC.advance(0.05)
			T.check(#H.teamSets(mark) == 0 and clear.Text == "Tap again to clear", "tb pets: Clear asks for a second tap", clear.Text)
			KC.advance(3.1)
			T.check(clear.Text == "Clear", "tb pets: ...for 3 s")
			Mock.Click(clear)
			KC.advance(0.05)
			Mock.Click(clear)
			set = H.lastSet(mark)
			T.check(set and set.args[3][1] == nil and H.slotPart(1, "Empty").Visible and clear.Text == "Clear", "tb pets: ...the second tap clears the team")
			SF.Play = realPlay
		end)
	end)

	S.client_tb_pets_actions = guarded("client_tb_pets_actions", function()
		H.at(1920, 1080, false, "client_tb_pets_actions", function(PC)
			local Care = H.mod("CareController")
			local BC, PCat = H.req("shared/BattleCatalog"), H.req("shared/PetCatalog")
			local State = H.req("client/State")
			H.feed({})
			PC.Open({})
			KC.advance(0.5)
			local win = H.win()
			Mock.Click(H.card(K2))
			KC.advance(0.05)
			local detail = H.find(win, "Detail")
			T.check(H.find(detail, "Name").Text == State.DefOf(K2).Name, "tb pets: selecting a pet shows its details", H.find(detail, "Name").Text)
			local function row(name)
				local r = H.find(detail, "Row_" .. name)
				return r and H.find(r, "Label").Text, r and H.find(r, "Value").Text
			end
			local label, value = row("Power")
			T.check(label == "Battle power" and value == tostring(H.power(K2)), "tb pets: the Battle power row is UnitPower", tostring(label) .. " " .. tostring(value))
			label, value = row("Health")
			T.check(label == "Health" and value == tostring(math.floor(BC.BattleStatsOf(K2, 10).Health + 0.5)), "tb pets: the Health row shows the battle number", tostring(value))
			label, value = row("Speed")
			T.check(label == "Speed" and value == tostring(math.floor(PCat.GetStats(K2, 10).Speed + 0.5)), "tb pets: the Speed row keeps the garden number", tostring(value))
			label, value = row("Income")
			T.check(label == "Coins" and value:find("/s", 1, true) ~= nil, "tb pets: the Coins row", tostring(value))
			T.check(H.find(detail, "Perks") ~= nil and H.find(detail, "XpBar") ~= nil, "tb pets: the perks and the XP bar")
			-- Put in team
			local mark = #Mock.RemoteLog
			T.check(H.find(win, "ActPut").Visible and not H.find(win, "ActRemove").Visible and not H.find(win, "ActFighter").Visible, "tb pets: a free pet offers Put in team")
			H.clickName("ActPut")
			local set = H.lastSet(mark)
			T.check(set and H.list(set.args) == K2, "tb pets: Put in team fills the first empty slot", set and H.list(set.args))
			H.feed({ K2 })
			KC.advance(0.5)
			T.check(not H.find(win, "ActPut").Visible and H.find(win, "ActRemove").Visible and not H.find(win, "ActFighter").Visible, "tb pets: the fighter offers Remove only")
			Mock.Click(H.card(K4))
			KC.advance(0.05)
			mark = #Mock.RemoteLog
			H.clickName("ActPut")
			set = H.lastSet(mark)
			T.check(set and H.list(set.args) == table.concat({ K2, K4 }, ","), "tb pets: ...then the next one", set and H.list(set.args))
			H.feed({ K2, K4 })
			KC.advance(0.5)
			-- Make fighter
			T.check(H.find(win, "ActFighter").Visible and H.find(win, "ActRemove").Visible, "tb pets: a helper offers Make fighter and Remove")
			mark = #Mock.RemoteLog
			H.clickName("ActFighter")
			set = H.lastSet(mark)
			T.check(set and H.list(set.args) == table.concat({ K4, K2 }, ","), "tb pets: Make fighter swaps with slot 1", set and H.list(set.args))
			H.feed({ K4, K2, K1 })
			KC.advance(0.5)
			Mock.Click(H.card(K1))
			KC.advance(0.05)
			mark = #Mock.RemoteLog
			H.clickName("ActFighter")
			set = H.lastSet(mark)
			T.check(set and H.list(set.args) == table.concat({ K1, K2, K4 }, ","), "tb pets: ...a swap, not a rotation", set and H.list(set.args))
			H.feed({ K1, K2, K4 })
			KC.advance(0.5)
			-- Put in team with a full team: pick mode on slot 1
			Mock.Click(H.card(K5))
			KC.advance(0.05)
			mark = #Mock.RemoteLog
			H.clickName("ActPut")
			KC.advance(0.05)
			T.check(#H.teamSets(mark) == 0 and H.find(win, "PickBanner").Visible and H.slotPart(1, "Glow").Visible, "tb pets: Put in team on a full team enters pick mode")
			H.clickName("PickCancel")
			-- a gardening pet: the recall
			Mock.Click(H.card(GARDEN))
			KC.advance(0.05)
			T.check(H.find(win, "ActGarden").Text == "Leave Garden", "tb pets: a gardening pet offers Leave Garden")
			H.feed({ K1 })
			KC.advance(0.5)
			H.clickName("ActPut")
			KC.advance(0.05)
			local gui = H.pg():FindFirstChild("NimbusPets")
			T.check(gui:FindFirstChild("GardenRecall") ~= nil, "tb pets: Put in team on a gardening pet asks for the recall")
			Mock.Click(H.find(gui:FindFirstChild("GardenRecall"), "RecallNo"))
			KC.advance(0.05)
			-- a training pet: says why at once
			Mock.Click(H.card(TRAINING))
			KC.advance(0.05)
			mark = #Mock.RemoteLog
			H.clickName("ActPut")
			KC.advance(0.05)
			T.check(#H.teamSets(mark) == 0 and H.hintText():find("is training", 1, true) ~= nil, "tb pets: Put in team on a training pet says why", H.hintText())
			T.check(H.find(win, "ActTrain").Text == "Training" and H.find(detail, "Work").Text:find("Training Physique", 1, true) ~= nil, "tb pets: the detail says where it trains", H.find(detail, "Work").Text)
			-- Garden stays a HomeAction
			Mock.Click(H.card(K4))
			KC.advance(0.05)
			mark = #Mock.RemoteLog
			H.clickName("ActGarden")
			local home = KC.serverCalls("HomeAction", mark)
			T.check(#home == 1 and home[1].args[1] == "GardenSet" and home[1].args[2].Key == K4, "tb pets: Garden sends HomeAction GardenSet", tostring(#home))
			KC.advance(0.5)
			-- Feed and Train come back, with what the window was given
			local ret = { Window = "Ring", Start = 20 }
			local closedWith = {}
			local conn = PC.Closed:Connect(function(r)
				closedWith[#closedWith + 1] = r or false
			end)
			PC.Close(true)
			KC.advance(0.3)
			T.check(closedWith[1] == false, "tb pets: a silent Close hands nothing back")
			PC.Open({ Key = K2, ReturnTo = ret })
			KC.advance(0.3)
			T.check(H.find(H.find(win, "Detail"), "Name").Text == State.DefOf(K2).Name, "tb pets: Open({ Key }) selects the pet")
			closedWith = {}
			H.clickName("ActFeed")
			KC.advance(0.2)
			T.check(Care.IsOpen() and Care.Mode() == "Feed" and not PC.IsOpen(), "tb pets: Feed opens the Food Machine list in its place")
			T.check(#closedWith == 1 and closedWith[1] == false, "tb pets: ...without handing ReturnTo back yet")
			Care.Close()
			KC.advance(0.2)
			T.check(PC.IsOpen(), "tb pets: ...and closing it comes back to the window")
			T.check(H.find(H.find(win, "Detail"), "Name").Text == State.DefOf(K2).Name, "tb pets: ...on the same pet")
			H.clickName("ActTrain")
			KC.advance(0.2)
			T.check(Care.IsOpen() and Care.Mode() == "Train" and not PC.IsOpen(), "tb pets: Train opens the Training Place")
			Care.Close()
			KC.advance(0.2)
			T.check(PC.IsOpen(), "tb pets: ...and comes back")
			-- another window while a care list came from the Pets window: no way back on top of it
			H.clickName("ActFeed")
			KC.advance(0.2)
			H.mod("MenuController").Open("Stats", {})
			KC.advance(0.3)
			T.check(not PC.IsOpen() and not Care.IsOpen() and H.menu():FindFirstChild("Window_Stats").Visible, "tb pets: another window drops the way back")
			H.mod("MenuController").Close()
			KC.advance(0.3)
			closedWith = {}
			PC.Open({ ReturnTo = ret })
			KC.advance(0.2)
			PC.Close()
			KC.advance(0.3)
			T.check(#closedWith == 1 and closedWith[1] == ret, "tb pets: Close hands ReturnTo back", tostring(closedWith[1]))
			conn:Disconnect()
			-- Evolve keeps its confirm
			PC.Open({ Key = K2 })
			KC.advance(0.2)
			T.check(not H.find(win, "ActEvolve").Visible, "tb pets: no Evolve before the level")
			PC.Open({ Key = READY })
			KC.advance(0.2)
			T.check(H.find(win, "ActEvolve").Visible, "tb pets: Evolve on a pet that can")
			H.clickName("ActEvolve")
			KC.advance(0.2)
			T.check(Care.IsOpen() and Care.Mode() == nil and PC.IsOpen(), "tb pets: Evolve opens its confirm over the window")
			Care.Close()
			KC.advance(0.3)
			-- an Evolve from a window with a ReturnTo: the cinematic plays, then the window is back, and its Close follows the chain
			local fromRing = { Window = "Ring", Start = 10 }
			PC.Open({ Key = READY, ReturnTo = fromRing })
			KC.advance(0.2)
			local closedAfter = {}
			local evoConn = PC.Closed:Connect(function(back)
				closedAfter[#closedAfter + 1] = back or false
			end)
			KC.toClient("OpenPanel", "Evolve", { Key = READY, Stage = 1 })
			KC.advance(0.2)
			T.check(not PC.IsOpen(), "tb pets: the Evolve cinematic takes the screen")
			KC.advance(15)
			T.check(PC.IsOpen(), "tb pets: ...the window comes back after it (it came from a panel)")
			T.check(PC.IsOpen() and H.find(H.find(win, "Detail"), "Name").Text == State.DefOf(READY).Name, "tb pets: ...on the same pet")
			closedAfter = {}
			local arenaBack = {}
			local Arena = H.mod("ArenaController")
			local realOpenRing = Arena.OpenRing
			Arena.OpenRing = function(start, portal)
				arenaBack[#arenaBack + 1] = start
			end
			PC.Close()
			KC.advance(0.3)
			Arena.OpenRing = realOpenRing
			T.check(closedAfter[#closedAfter] == fromRing and arenaBack[1] == 10, "tb pets: ...and its Close still goes back to the Ring panel, same start round", tostring(arenaBack[1]))
			-- another window opened during the cinematic takes over
			PC.Open({ Key = READY, ReturnTo = fromRing })
			KC.advance(0.2)
			KC.toClient("OpenPanel", "Evolve", { Key = READY, Stage = 1 })
			KC.advance(0.2)
			H.mod("MenuController").WindowOpened:Fire("Shop")
			KC.advance(15)
			T.check(not PC.IsOpen(), "tb pets: another window opened during the cinematic: no window comes back")
			H.closeAll()
			-- a match started during the cinematic: nothing comes back either
			PC.Open({ Key = READY, ReturnTo = fromRing })
			KC.advance(0.2)
			KC.toClient("OpenPanel", "Evolve", { Key = READY, Stage = 1 })
			KC.advance(0.2)
			local EvoConfig = KC.env()
			LocalPlayer:SetAttribute(EvoConfig.Attr.InBattle, true)
			KC.advance(15)
			T.check(not PC.IsOpen(), "tb pets: a battle started during the cinematic: no window comes back")
			LocalPlayer:SetAttribute(EvoConfig.Attr.InBattle, nil)
			KC.advance(0.2)
			H.closeAll()
			-- a plain Evolve (no panel behind the window) keeps today's end: the player stands with the evolved pet
			PC.Open({ Key = READY })
			KC.advance(0.2)
			KC.toClient("OpenPanel", "Evolve", { Key = READY, Stage = 1 })
			KC.advance(15)
			T.check(not PC.IsOpen(), "tb pets: an Evolve with no panel behind it does not reopen the window")
			evoConn:Disconnect()
			H.closeAll()
			-- the floating card's EVOLVE! pill
			PC.Close(true)
			KC.advance(0.2)
			H.mod("MenuController").Open("Pets", { Tab = "Pets", Key = READY, Action = "Evolve" })
			KC.advance(0.3)
			T.check(PC.IsOpen() and Care.IsOpen() and H.find(H.find(win, "Detail"), "Name").Text == State.DefOf(READY).Name, "tb pets: the EVOLVE! pill: the window on that pet + the confirm")
			Care.Close()
			KC.advance(0.3)
			-- Esc: the question, then pick mode, then the window
			local UIS = game:GetService("UserInputService")
			local function esc()
				Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), false)
				KC.advance(0.1)
			end
			H.feed({ K1 })
			KC.advance(0.5)
			Mock.Click(H.slot(2))
			Mock.Click(H.card(GARDEN))
			KC.advance(0.05)
			local gui2 = H.pg():FindFirstChild("NimbusPets")
			esc()
			T.check(gui2:FindFirstChild("GardenRecall") == nil and H.find(win, "PickBanner").Visible and PC.IsOpen(), "tb pets: Esc answers the question No")
			esc()
			T.check(not H.find(win, "PickBanner").Visible and PC.IsOpen(), "tb pets: Esc ends pick mode")
			esc()
			T.check(not PC.IsOpen(), "tb pets: Esc closes the window")
			-- the empty state
			KC.toClient("ProfileSync", { Tokens = 0, Pets = {}, Equipped = {}, Teams = { Presets = { {}, {}, {} }, Active = 1, Slots = 3 }, Tutorial = { Step = 1000, Done = true, Gifted = true } })
			KC.advance(0.1)
			PC.Open({})
			KC.advance(0.3)
			local empty = H.find(H.find(win, "GridWell"), "Empty")
			T.check(empty and H.shown(empty) and H.find(empty, "OpenShop") and H.shown(H.find(empty, "OpenShop")), "tb pets: no pets: the empty state with Open Shop")
			H.feed()
		end)
	end)

	S.client_tb_pets_phone = guarded("client_tb_pets_phone", function()
		H.at(844, 390, true, "client_tb_pets_phone", function(PC)
			local State = H.req("client/State")
			local MC = H.mod("MenuController")
			PC.Open({})
			KC.advance(0.5)
			local win = H.win()
			if not T.check(H.shown(win), "tb pets phone: the window opens") then
				return
			end
			T.check(PC.Layout() == "Phone", "tb pets phone: the phone layout", PC.Layout())
			local GuiService = game:GetService("GuiService")
			local inset = GuiService:GetGuiInset().Y
			local p, sz = win.AbsolutePosition, win.AbsoluteSize
			T.check(math.abs(sz.X - 820) <= 2 and math.abs(sz.Y - 330) <= 2 and p.Y >= inset - 0.5 and p.Y + sz.Y <= 390 + 0.5, "tb pets phone: 820x330 under the top bar", fmt("%.0fx%.0f at y %.0f", sz.X, sz.Y, p.Y))
			T.check(math.abs(p.X + sz.X / 2 - 422) <= 2, "tb pets phone: ...centred")
			local grid = H.find(win, "Grid")
			T.check(H.slot(1).AbsolutePosition.X + H.slot(1).AbsoluteSize.X <= grid.AbsolutePosition.X + 0.5 and H.shown(H.slot(3)), "tb pets phone: the slots in a column on the left, always visible")
			T.check(H.slot(1).AbsolutePosition.Y < H.slot(2).AbsolutePosition.Y and H.slot(3).AbsolutePosition.Y + H.slot(3).AbsoluteSize.Y <= p.Y + sz.Y + 0.5, "tb pets phone: ...one under the other, inside the window")
			T.check(math.abs(H.card(K1).AbsoluteSize.X - 104) <= 2 and math.abs(H.card(K1).AbsoluteSize.Y - 130) <= 2, "tb pets phone: 104 x 130 cards", fmt("%.0f x %.0f", H.card(K1).AbsoluteSize.X, H.card(K1).AbsoluteSize.Y))
			T.check(not H.find(H.card(K1), "Name").Visible, "tb pets phone: no name on the phone cards")
			local function allTargets(label)
				for _, b in ipairs(H.targets(win)) do
					T.check(b.AbsoluteSize.Y >= 44, "tb pets phone: " .. label .. ": " .. b.Name .. " >= 44 px", fmt("%.1f", b.AbsoluteSize.Y))
				end
			end
			allTargets("the window")
			T.check(game:GetService("GuiService").TouchControlsEnabled == false, "tb pets phone: Roblox's stick and jump button go while the window is up (they would sit over slot 3 and the cards)")
			T.check(H.shown(H.find(win, "PresetA")) and H.shown(H.find(win, "SortButton")), "tb pets phone: A / B / C and sort on the top row")
			T.check(MC.GetButton("Pets").Parent.Visible == false or MC.GetButton("Pets").Visible == false, "tb pets phone: the menu tiles step aside (the window covers them)")
			-- pick mode
			Mock.Click(H.slot(2))
			KC.advance(0.1)
			local banner = H.find(win, "PickBanner")
			T.check(H.shown(banner) and banner.Text == "Pick a helper for slot 2", "tb pets phone: the banner")
			T.check(banner.AbsolutePosition.X >= H.slot(2).AbsolutePosition.X + H.slot(2).AbsoluteSize.X - 0.5, "tb pets phone: ...on the top row, not over the slots")
			allTargets("pick mode")
			H.clickName("PickCancel")
			KC.advance(0.1)
			-- the sheet
			Mock.Click(H.card(K2))
			KC.advance(0.1)
			local sheet = H.find(win, "Sheet")
			if T.check(sheet and H.shown(sheet), "tb pets phone: tapping a pet opens the sheet") then
				T.check(H.find(win, "Detail") == nil, "tb pets phone: one detail: the sheet")
				T.check(sheet.AbsolutePosition.X >= H.slot(1).AbsolutePosition.X + H.slot(1).AbsoluteSize.X - 0.5, "tb pets phone: the sheet opens over the grid, not the slots", fmt("%.0f", sheet.AbsolutePosition.X))
				local put = H.find(sheet, "ActPut")
				local fighter = H.find(sheet, "ActFighter")
				local act = (put.Visible and put) or fighter
				T.check(act.AbsolutePosition.Y + act.AbsoluteSize.Y >= p.Y + sz.Y - 60, "tb pets phone: big actions at the bottom edge", fmt("%.0f", act.AbsolutePosition.Y + act.AbsoluteSize.Y))
				T.check(H.find(sheet, "Name").Text == State.DefOf(K2).Name and H.shown(H.find(sheet, "Name")), "tb pets phone: the name shows in the sheet")
				T.check(sheet.AbsolutePosition.X + sheet.AbsoluteSize.X <= p.X + sz.X + 0.5 and sheet.AbsolutePosition.Y + sheet.AbsoluteSize.Y <= p.Y + sz.Y + 0.5, "tb pets phone: ...inside the window")
				for _, name in ipairs({ "ActFeed", "ActTrain", "ActGarden" }) do
					local b = H.find(sheet, name)
					T.check(b and H.shown(b), "tb pets phone: " .. name .. " in the sheet")
				end
				allTargets("the sheet")
				H.clickName("SheetClose")
				KC.advance(0.1)
				T.check(not H.shown(sheet), "tb pets phone: SheetClose")
			end
			-- a text floor on a phone
			local small = {}
			for _, d in ipairs(win:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and H.shown(d) and d.Text ~= "" and d.TextSize < 14 then
					small[#small + 1] = d.Name .. "=" .. tostring(d.TextSize)
				end
			end
			T.check(#small == 0, "tb pets phone: every text >= 14 px", table.concat(small, ", "))
			PC.Close(true)
			KC.advance(0.3)
			T.check(MC.GetButton("Pets").Parent.Visible ~= false and MC.GetButton("Pets").Visible ~= false, "tb pets phone: the tiles come back")
			T.check(GuiService.TouchControlsEnabled == true, "tb pets phone: ...and Roblox's touch controls")
			-- a portrait phone: the slots keep the top, the sheet the rest
			Mock.SetViewport(390, 844)
			KC.advance(0.5)
			PC.Open({})
			KC.advance(0.5)
			T.check(PC.Layout() == "Phone", "tb pets phone: portrait is a phone layout too")
			T.check(win.AbsolutePosition.Y >= inset - 0.5 and win.AbsolutePosition.X >= 0 and win.AbsolutePosition.X + win.AbsoluteSize.X <= 390, "tb pets phone: portrait: on the screen, under the top bar")
			T.check(H.slot(3).AbsolutePosition.Y + H.slot(3).AbsoluteSize.Y <= H.find(win, "Grid").AbsolutePosition.Y + 0.5, "tb pets phone: portrait: the slots above the grid")
			allTargets("portrait")
			Mock.Click(H.card(K2))
			KC.advance(0.1)
			sheet = H.find(win, "Sheet")
			T.check(sheet and H.shown(sheet) and sheet.AbsolutePosition.Y >= H.slot(1).AbsolutePosition.Y + H.slot(1).AbsoluteSize.Y - 0.5, "tb pets phone: portrait: the sheet leaves the slots alone")
			allTargets("the portrait sheet")
		end)
		-- 16:9 phones under 660 design px: the top row fits between the slots and the close button, every chip keeps its label
		for _, size in ipairs({ { 667, 375 }, { 640, 360 } }) do
			local w, h = size[1], size[2]
			local tag = fmt("tb pets phone %dx%d", w, h)
			H.at(w, h, true, "client_tb_pets_phone", function(PC)
				PC.Open({})
				KC.advance(0.5)
				local win = H.win()
				if not T.check(H.shown(win) and PC.Layout() == "Phone", tag .. ": the phone layout", PC.Layout()) then
					return
				end
				local close = H.find(win, "Close")
				local closeX = close.AbsolutePosition.X
				local function clearRow(label)
					for _, name in ipairs({ "PresetA", "PresetB", "PresetC", "SortButton", "AutoFill", "ClearTeam", "Undo", "PickCancel", "PickBanner" }) do
						local b = H.find(win, name)
						if b and H.shown(b) then
							T.check(b.AbsolutePosition.X + b.AbsoluteSize.X <= closeX - 0.5, tag .. ": " .. label .. ": " .. name .. " ends before the close button", fmt("%.0f against %.0f", b.AbsolutePosition.X + b.AbsoluteSize.X, closeX))
							T.check(b.AbsoluteSize.Y >= 44, tag .. ": " .. label .. ": " .. name .. " >= 44 px", fmt("%.1f", b.AbsoluteSize.Y))
							if b.Text ~= "" and name ~= "PickBanner" then
								T.check(b.TextBounds.X <= b.AbsoluteSize.X - 2, tag .. ": " .. label .. ": " .. name .. " '" .. b.Text .. "' fits", fmt("%.0f in %.0f", b.TextBounds.X, b.AbsoluteSize.X))
							end
						end
					end
				end
				clearRow("the row")
				H.clickName("AutoFill")
				KC.advance(0.1)
				T.check(H.shown(H.find(win, "Undo")), tag .. ": Undo shows after Auto-fill best")
				clearRow("Undo")
				H.feed()
				KC.advance(6.5)
				Mock.Click(H.find(win, "ClearTeam"))
				KC.advance(0.05)
				clearRow("Clear armed")
				KC.advance(3.1)
				Mock.Click(H.slot(2))
				KC.advance(0.1)
				clearRow("pick mode")
			end)
		end
		-- a touch tablet gets the PC layout at the 0.8 factor: Roblox's stick and jump button still go, the small targets stay >= 44 px
		H.at(1024, 768, true, "client_tb_pets_phone", function(PC)
			local GuiService = game:GetService("GuiService")
			PC.Open({ Key = K2 })
			KC.advance(0.5)
			local win = H.win()
			T.check(PC.Layout() == "PC", "tb pets tablet: the PC layout", PC.Layout())
			T.check(GuiService.TouchControlsEnabled == false, "tb pets tablet: Roblox's stick and jump button go while the window is up (they would sit over the Detail's buttons)")
			local function allTargets(label)
				for _, b in ipairs(H.targets(win)) do
					T.check(b.AbsoluteSize.Y >= 44, "tb pets tablet: " .. label .. ": " .. b.Name .. " >= 44 px", fmt("%.1f", b.AbsoluteSize.Y))
				end
			end
			allTargets("the window")
			Mock.Click(H.slot(2))
			KC.advance(0.1)
			allTargets("pick mode")
			local cancel = H.find(win, "PickCancel")
			T.check(cancel.AbsoluteSize.X >= 44, "tb pets tablet: PickCancel >= 44 px wide", fmt("%.1f", cancel.AbsoluteSize.X))
			local grid, sort = H.find(win, "Grid"), H.find(win, "SortButton")
			T.check(sort.AbsolutePosition.Y + sort.AbsoluteSize.Y <= grid.AbsolutePosition.Y + 0.5, "tb pets tablet: the grid stays under the taller Sort", fmt("%.0f against %.0f", sort.AbsolutePosition.Y + sort.AbsoluteSize.Y, grid.AbsolutePosition.Y))
			PC.Close(true)
			KC.advance(0.3)
			T.check(GuiService.TouchControlsEnabled == true, "tb pets tablet: ...and they come back")
		end)
		-- the same screen with a mouse and a keyboard keeps them
		H.at(1024, 768, false, "client_tb_pets_phone", function(PC)
			local GuiService = game:GetService("GuiService")
			PC.Open({})
			KC.advance(0.5)
			T.check(GuiService.TouchControlsEnabled == true, "tb pets tablet: a mouse and keyboard screen of that size leaves the touch controls alone")
			PC.Close(true)
			KC.advance(0.3)
		end)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
