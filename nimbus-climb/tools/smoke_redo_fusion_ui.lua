-- smoke_redo_fusion_ui.lua: the Fusion Machine window, card A (docs/superpowers/specs/2026-11-06-window-redo-design.md 5.1, 5.6;
-- plan docs/superpowers/plans/2026-11-06-window-redo.md Task 11): client/Controllers/FusionController.lua rebuilt on
-- NeonKit.BigRect with the shared pet picker sheet (UI/PetPicker) in place of its old left-hand grid. Client and phone worlds
-- only (client_files, loaded after smoke_redo_geom.lua, whose RedoGeom it uses):
--   client_fusion_ui_a      (1920x1080) Upgrade on a 5-copy pet with a team copy taken: the Stack (three fanned cards: COPIES,
--                           the pet, "Uncommon . Flame"), "x5 owned . uses 3", the big Result "Golden Maple Fox" with its
--                           pills "Uncommon" / "x1.5 power", the Note "1 team copy is taken off first; the new pet takes the
--                           slot", FUSE! active; tapping the Stack opens the sheet in its Upgrade context and a pick selects
--                           that pet; FUSE sends ONE Fusion("Upgrade", key); a pet short of copies: the Note says why, FUSE
--                           is greyed and a tap says it on the HintLine; Upgrade with no pet opens the sheet by itself (and
--                           nothing opens without pets); Mix with both slots empty: the Body sheet opens, a pick opens the
--                           Style sheet with the Body's species blocked ("In Body", every finish), a pick fills both slots
--                           and the NEW HYBRID card shows the blended name, "Flame + Storm", the rarity and the finish;
--                           closing a chained sheet without a pick ends the chain; a slot tap opens its sheet; the swap
--                           button swaps the pets; the tabs switch; Esc with the sheet up closes only the sheet, then the
--                           window; Close() closes the sheet too; NimbusFusion ignores the gui inset; review fixes: an Escape
--                           that only ends typing in the Search box closes nothing; an empty pick list (no pets, only a
--                           Rainbow pet + a hybrid, only a hybrid) says why on the HintLine from the auto-open and the taps
--   client_fusion_layouts   Upgrade and Mix at 844x390 (touch), 1280x720, 1366x768, 1920x1080 (+ 1280x640, 667x375 touch):
--                           RedoGeom.check (text >= 14 px, targets >= 44 px, on the screen under the top bar, the named
--                           controls never overlap) and the main texts fit their boxes with the real font widths;
--                           844x390: an 820x330 box at y 59, Layout() "Phone", Roblox's touch controls gone while open and
--                           back after; PC sizes: Layout() "PC", every text >= 18 design px; the empty Upgrade state passes
--                           too; a resize while open (1920x1080 -> 844x390 -> 1920x1080, the sheet up) passes each time
--   client_fusion_portrait  (phone world, 390x844 touch) Layout() "Portrait": the Stack and the slots above the Result, the
--                           two slots side by side, RedoGeom.check passes on both tabs
--   client_fusion_moves     (Task 12; 1920x1080, then 844x390 touch) the Mix move chips: under each slot an Attack chip
--                           ("<sword> Flare", PC "... . Flame") and a Special chip ("<star> Leaf Pounce", PC "... . Pounce"),
--                           exactly one lit (attribute Lit, the check badge) in each pair; the default "BB" (the Body gives
--                           both = today's hybrid); a tap on the other parent's chip moves that move ("BS", "SS"); the
--                           preview record follows (SpecialFrom, the Elements order in the pills); FUSE sends
--                           Fusion("Mix", body, style, moves); the swap keeps each move with its pet (the letters flip);
--                           a new pet (the sheet or Select) resets to "BB"; SetMoves ignores keys that are not in a slot;
--                           equal elements: both attack chips lit and inactive, the special still choosable; the pure
--                           MovesText(body, style, moves) (stage 0's names); the outcome: PC OutcomeAttack "Normal attack:
--                           Flame (Flare)" + OutcomeSpecial "Special: Pounce (Leaf Pounce)" inside the NEW HYBRID card
--                           between its name and its pills; phone ONE Outcome line under the slot row ("... . Special:
--                           ..."), the kind words dropping first and then a wrap when it is too wide, never cut (a long
--                           special such as "Wish Upon the Stars", 844x390 and 667x375); the Info line when a slot is
--                           empty; a reason note in the phone's right column; RedoGeom at both sizes
-- Fixture: Maple Fox x5 (three in the team) + a Golden copy, Storm Tabby, Pebble Pup x4, Honey Bunny x2, an evolved Aurora
-- Fox and a hybrid (client_fusion_moves adds an Ember Phoenix: a second Flame pet); Prestige 1 with the Fusion Machine;
-- 50,000 Cloud Tokens. Every scenario puts the profile and the attributes it found back. Deterministic: mock clock only.
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

	local DOT = "\194\183"
	-- key, level, copies, stored evolution
	local FIX = {
		{ "maple_fox", 12, 5 },
		{ "maple_fox@Golden", 14, 1 },
		{ "storm_tabby", 22, 1 },
		{ "pebble_pup", 8, 4 },
		{ "honey_bunny", 20, 2 },
		{ "aurora_fox", 34, 1, 1 },
	}
	local TEAM = { "maple_fox", "maple_fox", "maple_fox" }
	local UP_NAMES = { "Stack", "CopiesText", "Arrow", "Result", "CostBar", "FuseButton", "Note", "Tab_Upgrade", "Tab_Mix", "CloseButton" }
	-- (Task 12) the move chips sit under the slots; on a landscape phone the outcome line takes the Info line's place
	local MIX_NAMES = { "Slot_Body", "Chips_Body", "SwapButton", "Slot_Style", "Chips_Style", "Arrow", "Result", "CostBar", "FuseButton", "Info", "Tab_Upgrade", "Tab_Mix", "CloseButton" }
	local MIX_PHONE = { "Slot_Body", "Chips_Body", "SwapButton", "Slot_Style", "Chips_Style", "Arrow", "Result", "CostBar", "FuseButton", "Outcome", "Tab_Upgrade", "Tab_Mix", "CloseButton" }
	local MIX_PORTRAIT = { "Slot_Body", "Chips_Body", "SwapButton", "Slot_Style", "Chips_Style", "Arrow", "Result", "CostBar", "FuseButton", "Outcome", "Info", "Tab_Upgrade", "Tab_Mix", "CloseButton" }
	local SWORD, STAR = "\226\154\148", "\226\152\133"

	function H.req(path)
		local root, rest = path:match("^(%a+)/(.+)$")
		local inst = Mock.GetPath(ROOTS[root] .. "/" .. rest)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end
	function H.mod(name)
		return (KC.M and KC.M[name]) or H.req("client/Controllers/" .. name)
	end
	function H.fc()
		return H.mod("FusionController")
	end
	function H.picker()
		return H.req("client/UI/PetPicker")
	end
	function H.state()
		return (KC.M and KC.M.State) or H.req("client/State")
	end
	function H.config()
		return H.req("shared/Config")
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.gui()
		return H.pg():FindFirstChild("NimbusFusion")
	end
	function H.win()
		local g = H.gui()
		return g and g:FindFirstChild("Window_Fusion")
	end
	function H.find(name, root)
		return RedoGeom.find(root or H.win(), name)
	end
	function H.shown(o)
		return o ~= nil and KC.isShown(o)
	end
	function H.text(o)
		return o and tostring(o.Text) or "<nil>"
	end
	function H.click(o)
		if o then
			Mock.Click(o)
		end
		KC.advance(0.4)
	end
	function H.esc()
		Mock.FireSignal(game:GetService("UserInputService"), "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), false)
		KC.advance(0.3)
	end
	-- (review fix) Escape while a TextBox has focus (the sheet's search, the chat): Roblox lets go of the box and InputBegan
	-- arrives processed. how = "release" (the box let go just before InputBegan) | "focused" (GetFocusedTextBox() still
	-- returns the box while InputBegan runs)
	function H.escTyping(box, how)
		local UIS = game:GetService("UserInputService")
		local methods = Mock.Classes.UserInputService.methods
		local old = methods.GetFocusedTextBox
		if how == "focused" then
			methods.GetFocusedTextBox = function()
				return box
			end
		else
			Mock.FireSignal(UIS, "TextBoxFocused", box)
			Mock.FireSignal(UIS, "TextBoxFocusReleased", box)
		end
		local ok, err = pcall(Mock.FireSignal, UIS, "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), true)
		methods.GetFocusedTextBox = old
		KC.advance(0.3)
		if not ok then
			error(err, 0)
		end
	end
	function H.disabled(b)
		return b ~= nil and b:GetAttribute("Disabled") == true
	end
	function H.sheetWin()
		local g = H.pg():FindFirstChild("NimbusPetPicker")
		return g and g:FindFirstChild("Window_PetPicker")
	end
	function H.sheetTitle()
		local w = H.sheetWin()
		local header = w and RedoGeom.find(w, "Header")
		return header and H.text(RedoGeom.find(header, "Title")) or "<no sheet>"
	end
	function H.card(key)
		return RedoGeom.find(H.sheetWin(), "Card_" .. key)
	end
	-- the text of a named label under `root` (the window by default)
	function H.t(name, root)
		return H.text(H.find(name, root))
	end
	-- the shown pill texts under Pills, sorted by name
	function H.pills()
		local pills = H.find("Pills")
		local out = {}
		for _, c in ipairs(pills and pills:GetChildren() or {}) do
			if c:IsA("TextLabel") and c.Visible and c.Text ~= "" then
				out[c.Name] = c.Text
			end
		end
		return out
	end
	function H.calls(mark)
		return KC.serverCalls("Fusion", mark)
	end

	-- (Task 12) the move chips: H.chip("Body" | "Style", "Attack" | "Special")
	function H.chip(side, which)
		local grp = H.find("Chips_" .. side)
		return grp and RedoGeom.find(grp, which)
	end
	function H.lit(c)
		return c ~= nil and c:GetAttribute("Lit") == true
	end
	-- the four chips' lit flags as "BA BS SA SS" letters: e.g. "1100" = the Body's two lit
	function H.lits()
		local out = ""
		for _, side in ipairs({ "Body", "Style" }) do
			for _, which in ipairs({ "Attack", "Special" }) do
				out = out .. (H.lit(H.chip(side, which)) and "1" or "0")
			end
		end
		return out
	end
	-- every lit chip shows its check badge, no unlit one does
	function H.checksMatch()
		for _, side in ipairs({ "Body", "Style" }) do
			for _, which in ipairs({ "Attack", "Special" }) do
				local c = H.chip(side, which)
				local badge = c and RedoGeom.find(c, "Check")
				if not c or H.shown(badge) ~= H.lit(c) then
					return false
				end
			end
		end
		return true
	end
	function H.boxIn(a, b)
		local ap, as, bp, bs = a.AbsolutePosition, a.AbsoluteSize, b.AbsolutePosition, b.AbsoluteSize
		return ap.X >= bp.X - 0.5 and ap.Y >= bp.Y - 0.5 and ap.X + as.X <= bp.X + bs.X + 0.5 and ap.Y + as.Y <= bp.Y + bs.Y + 0.5
	end
	function H.bottom(o)
		return o.AbsolutePosition.Y + o.AbsoluteSize.Y
	end
	-- the fixture plus opts.Extra ({ key, level, copies, evo }); opts.Only replaces the fixture's pets (the hybrid stays)
	function H.fixture(opts)
		local list = {}
		for _, f in ipairs(opts.Only or FIX) do
			list[#list + 1] = f
		end
		for _, f in ipairs(opts.Extra or {}) do
			list[#list + 1] = f
		end
		return list
	end

	-- a ProfileSync snapshot of the fixture. opts: NoPets, Locked (Prestige 0), Team (the active preset; default TEAM),
	-- Extra (more pets: { key, level, copies, evo })
	function H.snapshot(opts)
		opts = opts or {}
		local pets, tiers, levels, growth, discovered = {}, {}, {}, {}, {}
		if not opts.NoPets then
			for _, f in ipairs(H.fixture(opts)) do
				local key, level, copies, evo = f[1], f[2], f[3], f[4]
				local base, tier = key:match("^(.-)@(%a+)$")
				if tier then
					tiers[base] = tiers[base] or {}
					tiers[base][tier] = copies
				else
					pets[key] = copies
					discovered[key] = true
				end
				levels[key] = { Level = level, Xp = 5 }
				if evo then
					growth[key] = { Evo = evo }
				end
			end
		end
		local team = opts.NoPets and {} or (opts.Team or TEAM)
		local equipped = {}
		for i, k in ipairs(team) do
			equipped[i] = k
		end
		return {
			Tokens = 50000, Pets = pets, Equipped = equipped, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = discovered, IndexClaimed = {},
			Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 250000, Gems = 40,
			Home = { Level = 22, Prestige = opts.Locked and 0 or 1, Stations = { Garden = 1, FusionMachine = opts.Locked and 0 or 1 }, Garden = {}, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = tiers, PetLevels = levels, PetGrowth = growth,
			Hybrids = opts.NoPets and {} or { hc1 = { Body = "pip_penguin", Style = "ember_phoenix", Elements = { "Frost", "Flame" }, Name = "Pengnix", Rarity = "Legendary", Tier = "Normal", Seed = 3 } },
			Teams = { Presets = { team, {}, {} }, Active = 1, Slots = 3, Busy = {} },
			Battle = { Trophies = 0, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			Ring = { Best = 0, Runs = 0 },
		}
	end
	function H.feed(opts)
		KC.toClient("ProfileSync", H.snapshot(opts))
		KC.advance(0.2)
	end
	function H.closeAll()
		for _, name in ipairs({ "FusionController", "TrainController", "CareController", "MenuController", "StoreController", "IndexController", "DailyController" }) do
			local m = H.mod(name)
			if m and type(m.Close) == "function" then
				pcall(m.Close)
			end
		end
		local PP = H.picker()
		if PP then
			pcall(PP.Close)
		end
		KC.advance(0.4)
	end
	-- the pet keys the sheet may show: every filter and sort back to its default for this context
	function H.sheetDefaults(PP)
		pcall(PP.SetFilter, "All")
		pcall(PP.SetSort, "Default")
		KC.advance(0.1)
	end
	-- runs fn(FC, PP, State) with the fixture synced; puts the profile and the attributes back after
	function H.with(label, opts, fn)
		local FC, PP = H.fc(), H.picker()
		if not T.check(type(FC) == "table" and type(FC.Open) == "function" and type(FC.Close) == "function" and type(FC.IsOpen) == "function"
			and type(FC.Plan) == "function" and type(FC.Select) == "function" and type(FC.Layout) == "function" and type(PP) == "table",
			label .. ": client/Controllers/FusionController.lua loads with its API (Open, Close, IsOpen, Plan, Select, Layout)") then
			return
		end
		if type(FC.Init) == "function" then
			pcall(FC.Init)
		end
		local State = H.state()
		local Config = H.config()
		local before = State and State.Get and State.Get() or nil
		local tokensBefore = LocalPlayer:GetAttribute(Config.Attr.Tokens)
		local gemsBefore = LocalPlayer:GetAttribute(Config.Attr.Gems)
		local matchBefore = LocalPlayer:GetAttribute(Config.Attr.InMatch)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.Tokens, 50000)
		LocalPlayer:SetAttribute(Config.Attr.Gems, 40)
		H.closeAll()
		H.feed(opts)
		local ok, err = pcall(fn, FC, PP, State)
		if not ok then
			T.fail(label .. ": error", tostring(err))
		end
		-- (a FUSE left waiting: the server's quiet no)
		KC.toClient("Fusion", "Result", { Ok = false, Reason = "x", Quiet = true })
		H.closeAll()
		LocalPlayer:SetAttribute(Config.Attr.Tokens, tokensBefore)
		LocalPlayer:SetAttribute(Config.Attr.Gems, gemsBefore)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, matchBefore)
		if before then
			KC.toClient("ProfileSync", before)
		end
		KC.advance(0.3)
		KC.flushErrors(label)
	end
	-- opens a tab with its pets picked (Upgrade: maple_fox; Mix: maple_fox + storm_tabby) and no sheet
	function H.openTab(FC, PP, tab)
		if tab == "Mix" then
			FC.Open("Mix", { Key = "maple_fox", KeyB = "storm_tabby" })
		else
			FC.Open("Upgrade", { Key = "maple_fox" })
		end
		KC.advance(0.6)
		if PP.IsOpen() then
			PP.Close()
			KC.advance(0.3)
		end
	end
	-- the texts every layout must fit with Roblox's real font widths
	function H.fitsAll(label, tab)
		local names = { "CopiesText", "Note", "ResultName", "Cost", "Have", "FuseButton", "Tab_Upgrade", "Tab_Mix", "TipLine", "Info", "Label", "Outcome", "OutcomeAttack", "OutcomeSpecial" }
		local bad = {}
		for _, name in ipairs(names) do
			local o = H.find(name)
			if o and H.shown(o) and o.Text ~= "" then
				local ok, detail = RedoGeom.fits(o)
				if not ok then
					bad[#bad + 1] = detail
				end
			end
		end
		for _, side in ipairs({ "Body", "Style" }) do
			for _, which in ipairs({ "Attack", "Special" }) do
				local c = H.chip(side, which)
				if c and H.shown(c) and c.Text ~= "" then
					local ok, detail = RedoGeom.fits(c)
					if not ok then
						bad[#bad + 1] = detail
					end
				end
			end
		end
		for _, root in ipairs({ H.find(tab == "Mix" and "Slot_Body" or "Stack"), H.find("Slot_Style"), H.find("Pills") }) do
			if root and H.shown(root) then
				for _, d in ipairs(root:GetDescendants()) do
					if d:IsA("TextLabel") and H.shown(d) and d.Text ~= "" and not d.TextScaled then
						local ok, detail = RedoGeom.fits(d)
						if not ok then
							bad[#bad + 1] = detail
						end
					end
				end
			end
		end
		T.check(#bad == 0, label .. ": the main texts fit their boxes (real font widths)", table.concat(bad, "; ", 1, math.min(#bad, 5)))
	end
	-- PC: every shown text of the window is at least 18 design px (the readability rule under one UIScale)
	function H.pcText(label)
		local small = {}
		for _, d in ipairs(H.win():GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and not d.TextScaled and H.shown(d) and d.TextSize < 18 then
				small[#small + 1] = d.Name .. "=" .. d.TextSize
			end
		end
		T.check(#small == 0, label .. ": every text is >= 18 design px on PC", table.concat(small, ", ", 1, math.min(#small, 6)))
	end

	------------------------------------------------------------------------------------------------
	S.client_fusion_ui_a = guarded("client_fusion_ui_a", function()
		RedoGeom.at(1920, 1080, false, "fusion ui a", function()
			H.with("client_fusion_ui_a", nil, function(FC, PP, State)
				local Keys = H.req("shared/PetKeys")
				-- Upgrade on the 5-copy Maple Fox (three in the team: one team copy goes)
				FC.Open("Upgrade", { Key = "maple_fox" })
				KC.advance(0.6)
				local win = H.win()
				T.check(H.gui() ~= nil and win ~= nil and H.shown(win) and FC.IsOpen(), "fusion ui: Open('Upgrade', { Key }) shows Window_Fusion in NimbusFusion")
				T.check(H.gui() and H.gui().IgnoreGuiInset == true, "fusion ui: NimbusFusion ignores the gui inset (the BigRect box is in screen px)")
				T.check(not PP.IsOpen(), "fusion ui: a pet given: the sheet stays closed")
				local tabUp, tabMix = H.find("Tab_Upgrade"), H.find("Tab_Mix")
				T.check(tabUp and tabMix and H.text(tabUp) == "UPGRADE" and H.text(tabMix) == "MIX" and tabUp:GetAttribute("Selected") == true and tabMix:GetAttribute("Selected") ~= true,
					"fusion ui: the header tabs UPGRADE (selected) and MIX", H.text(tabUp) .. " / " .. H.text(tabMix))
				local stack = H.find("Stack")
				T.check(H.shown(stack) and stack:IsA("GuiButton"), "fusion ui: the Stack (a button) is shown")
				local cards = 0
				for i = 1, 3 do
					if H.shown(RedoGeom.find(stack, "Copy" .. i)) then
						cards = cards + 1
					end
				end
				T.eq(cards, 3, "fusion ui: ...three fanned copies")
				local front = RedoGeom.find(stack, "Copy3")
				T.check(front and front.Rotation ~= 0 and RedoGeom.find(stack, "Copy1").Rotation ~= front.Rotation, "fusion ui: ...fanned (each card turned its own way)")
				T.eq(H.t("Label", front), "COPIES", "fusion ui: the front copy says COPIES")
				T.eq(H.t("PetName", front), "Maple Fox", "fusion ui: ...the pet's name")
				T.eq(H.t("Sub", front), "Uncommon " .. DOT .. " Flame", "fusion ui: ...'Uncommon . Flame'")
				T.eq(H.t("CopiesText"), "x5 owned " .. DOT .. " uses 3", "fusion ui: 'x5 owned . uses 3'")
				local result = H.find("Result")
				T.check(H.shown(result) and H.shown(H.find("Arrow")), "fusion ui: the Arrow and the Result card")
				T.eq(H.t("ResultName", result), "Golden Maple Fox", "fusion ui: the Result reads 'Golden Maple Fox'")
				T.eq(H.t("Label", result), "GOLDEN", "fusion ui: ...under 'GOLDEN'")
				local pills = H.pills()
				T.check(pills.Pill_Rarity == "Uncommon" and pills.Pill_Power == "x1.5 power", "fusion ui: the pills 'Uncommon' and 'x1.5 power'",
					tostring(pills.Pill_Rarity) .. " / " .. tostring(pills.Pill_Power))
				T.eq(H.t("Note"), "1 team copy is taken off first; the new pet takes the slot", "fusion ui: the Note says a team copy goes first")
				local fuse = H.find("FuseButton")
				T.check(H.shown(fuse) and not H.disabled(fuse) and H.text(fuse) == "FUSE!", "fusion ui: FUSE! is active", H.text(fuse))
				local cost = H.find("CostBar")
				T.check(H.shown(cost) and H.text(RedoGeom.find(cost, "Cost")) ~= "" and H.text(RedoGeom.find(cost, "Have")):find("You have 50,000 Cloud Tokens", 1, true) ~= nil,
					"fusion ui: the CostBar shows the price and 'You have 50,000 Cloud Tokens'", H.text(RedoGeom.find(cost, "Have")))
				local want = H.req("shared/TycoonCatalog").FusionCost("Upgrade", "Uncommon", "Golden", 1).Tokens
				local plan = FC.Plan()
				T.check(plan and plan.Ok and plan.Cost and plan.Cost.Amount == want and H.text(RedoGeom.find(cost, "Cost")):find(tostring(want), 1, true) ~= nil,
					"fusion ui: ...the server's price (TycoonCatalog.FusionCost with the machine)", H.text(RedoGeom.find(cost, "Cost")) .. " / " .. tostring(want))

				-- the Stack opens the sheet (Upgrade), a pick selects that pet
				H.click(stack)
				T.check(PP.IsOpen() and H.sheetTitle() == "PICK A PET TO UPGRADE", "fusion ui: tapping the Stack opens the sheet titled 'Pick a pet to upgrade'", H.sheetTitle())
				T.check(H.shown(RedoGeom.find(H.sheetWin(), "Filter_Ready")), "fusion ui: ...in its Upgrade context (the Ready filter)")
				H.sheetDefaults(PP)
				local shown = table.concat(PP.Shown(), ",")
				T.check(shown:find("hyb:", 1, true) == nil and shown:find("pebble_pup", 1, true) ~= nil, "fusion ui: ...regular pets only (no hybrid)", shown)
				T.check(H.card("maple_fox") and H.card("maple_fox"):GetAttribute("Selected") == true, "fusion ui: ...the current pet is the selected card")
				T.check(PP.Pick("pebble_pup"), "fusion ui: (pick Pebble Pup)")
				KC.advance(0.4)
				plan = FC.Plan()
				T.check(not PP.IsOpen() and plan and plan.Inputs and plan.Inputs[1] and plan.Inputs[1].Key == "pebble_pup", "fusion ui: a pick closes the sheet and selects that pet")
				T.eq(H.t("CopiesText"), "x4 owned " .. DOT .. " uses 3", "fusion ui: ...'x4 owned . uses 3'")

				-- FUSE sends one request
				FC.Select("maple_fox")
				KC.advance(0.3)
				local mark = #Mock.RemoteLog
				H.click(H.find("FuseButton"))
				local calls = H.calls(mark)
				T.check(#calls == 1 and calls[1].args[1] == "Upgrade" and calls[1].args[2] == "maple_fox", "fusion ui: FUSE! sends ONE Fusion('Upgrade', key)", #calls .. " calls")
				H.click(H.find("FuseButton"))
				T.eq(#H.calls(mark), 1, "fusion ui: ...a second tap while it waits sends nothing")
				KC.toClient("Fusion", "Result", { Ok = false, Reason = "x", Quiet = true })
				KC.advance(0.3)

				-- a pet short of copies: the Note says why, FUSE is grey, a tap says why on the HintLine
				FC.Select("honey_bunny")
				KC.advance(0.3)
				T.eq(H.t("Note"), "You need 3 copies of Honey Bunny (you have 2)", "fusion ui: 2 copies: the Note says what is missing")
				T.check(H.disabled(H.find("FuseButton")), "fusion ui: ...FUSE! is greyed out")
				mark = #Mock.RemoteLog
				H.click(H.find("FuseButton"))
				local hint = H.find("HintLine")
				T.check(hint and H.shown(hint) and hint.Text == "You need 3 copies of Honey Bunny (you have 2)", "fusion ui: ...a tap says it on the HintLine", H.text(hint))
				T.eq(#H.calls(mark), 0, "fusion ui: ...and sends nothing")

				-- Upgrade with no pet: the sheet opens by itself
				FC.Select(nil)
				FC.Close()
				KC.advance(0.3)
				FC.Open("Upgrade", {})
				KC.advance(0.5)
				T.check(FC.IsOpen() and PP.IsOpen() and H.sheetTitle() == "PICK A PET TO UPGRADE", "fusion ui: Upgrade with no pet: the sheet opens by itself", H.sheetTitle())
				PP.Close()
				KC.advance(0.3)
				T.check(FC.IsOpen() and not PP.IsOpen(), "fusion ui: ...X on it leaves the window open")
				T.check(H.t("PetName", RedoGeom.find(H.find("Stack"), "Copy3")) == "Pick a pet" and H.disabled(H.find("FuseButton")), "fusion ui: ...the Stack says 'Pick a pet', FUSE! greyed",
					H.t("PetName", RedoGeom.find(H.find("Stack"), "Copy3")))

				-- the tabs: Mix with both slots empty -> Body sheet, a pick -> Style sheet (Body's species blocked), a pick -> both
				H.click(H.find("Tab_Mix"))
				T.check(H.find("Tab_Mix"):GetAttribute("Selected") == true and FC.Plan() and FC.Plan().Action == "Mix", "fusion ui: the MIX tab switches the window")
				if PP.IsOpen() then
					PP.Close()
					KC.advance(0.3)
				end
				FC.Select(nil, nil)
				FC.Close()
				KC.advance(0.3)
				FC.Open("Mix", {})
				KC.advance(0.5)
				T.check(PP.IsOpen() and H.sheetTitle() == "PICK THE BODY PET", "fusion ui: Mix with empty slots: the Body sheet opens by itself", H.sheetTitle())
				H.sheetDefaults(PP)
				shown = table.concat(PP.Shown(), ",")
				T.check(shown:find("hyb:", 1, true) == nil, "fusion ui: ...no hybrid in it", shown)
				T.check(PP.Pick("maple_fox"), "fusion ui: (pick Maple Fox as the Body)")
				KC.advance(0.4)
				T.check(PP.IsOpen() and H.sheetTitle() == "PICK THE STYLE PET", "fusion ui: a pick: the Style sheet opens next", H.sheetTitle())
				T.check(H.card("maple_fox") and H.card("maple_fox"):GetAttribute("Blocked") == "In Body" and H.card("maple_fox@Golden") and H.card("maple_fox@Golden"):GetAttribute("Blocked") == "In Body",
					"fusion ui: ...the Body's species is blocked 'In Body' (every finish)")
				T.check(PP.Pick("maple_fox@Golden") == false and PP.IsOpen(), "fusion ui: ...and cannot be picked")
				T.check(PP.Pick("storm_tabby"), "fusion ui: (pick Storm Tabby as the Style)")
				KC.advance(0.4)
				T.check(not PP.IsOpen(), "fusion ui: both slots filled: nothing more opens")
				T.eq(H.t("PetName", H.find("Slot_Body")), "Maple Fox", "fusion ui: Slot_Body holds Maple Fox")
				T.eq(H.t("PetName", H.find("Slot_Style")), "Storm Tabby", "fusion ui: Slot_Style holds Storm Tabby")
				T.eq(H.t("Label", H.find("Slot_Body")), "BODY", "fusion ui: ...under 'BODY'")
				T.eq(H.t("Label", H.find("Slot_Style")), "STYLE", "fusion ui: ...and 'STYLE'")
				result = H.find("Result")
				T.eq(H.t("Label", result), "NEW HYBRID", "fusion ui: the Result is the NEW HYBRID card")
				T.eq(H.t("ResultName", result), Keys.BlendName("Maple Fox", "Storm Tabby"), "fusion ui: ...with the blended name")
				pills = H.pills()
				T.check(pills.Pill_Rarity == "Rare" and pills.Pill_Elements == "Flame + Storm" and pills.Pill_Tier == "Normal", "fusion ui: ...pills 'Rare', 'Flame + Storm', 'Normal'",
					tostring(pills.Pill_Rarity) .. " / " .. tostring(pills.Pill_Elements) .. " / " .. tostring(pills.Pill_Tier))
				T.check(H.shown(H.find("Info")) and H.t("Info"):find("one of a kind", 1, true) ~= nil, "fusion ui: ...and the Info line", H.t("Info"))
				-- the swap button
				H.click(H.find("SwapButton"))
				plan = FC.Plan()
				T.check(plan and plan.Inputs and plan.Inputs[1].Key == "storm_tabby" and plan.Inputs[2].Key == "maple_fox" and H.t("PetName", H.find("Slot_Body")) == "Storm Tabby",
					"fusion ui: the swap button swaps the two pets")
				T.eq(H.t("ResultName", H.find("Result")), Keys.BlendName("Storm Tabby", "Maple Fox"), "fusion ui: ...and the hybrid's name")
				-- a slot tap opens its sheet (the other species blocked by its word)
				H.click(H.find("Slot_Style"))
				T.check(PP.IsOpen() and H.sheetTitle() == "PICK THE STYLE PET" and H.card("storm_tabby") and H.card("storm_tabby"):GetAttribute("Blocked") == "In Body",
					"fusion ui: tapping Slot_Style opens its sheet with the Body's species blocked", H.sheetTitle())
				T.check(H.card("maple_fox") and H.card("maple_fox"):GetAttribute("Selected") == true, "fusion ui: ...the slot's pet selected")
				-- (review fix) Escape that only ends typing in the Search box (or the chat) closes nothing
				local search = RedoGeom.find(H.sheetWin(), "Search")
				T.check(search ~= nil, "fusion ui: (typing) the sheet's Search box")
				H.escTyping(search, "release")
				T.check(PP.IsOpen() and FC.IsOpen(), "fusion ui: Escape that lets go of the Search box (released just before) closes nothing")
				H.escTyping(search, "focused")
				T.check(PP.IsOpen() and FC.IsOpen(), "fusion ui: ...nor while a TextBox still has focus")
				-- Esc: the sheet first, then the window
				H.esc()
				T.check(not PP.IsOpen() and FC.IsOpen(), "fusion ui: Esc with the sheet up closes only the sheet")
				plan = FC.Plan()
				T.check(plan and plan.Inputs and #plan.Inputs == 2, "fusion ui: ...the slots stay")
				-- FUSE (Mix)
				mark = #Mock.RemoteLog
				H.click(H.find("FuseButton"))
				calls = H.calls(mark)
				T.check(#calls == 1 and calls[1].args[1] == "Mix" and calls[1].args[2] == "storm_tabby" and calls[1].args[3] == "maple_fox", "fusion ui: FUSE! sends Fusion('Mix', body, style)", #calls .. " calls")
				KC.toClient("Fusion", "Result", { Ok = false, Reason = "x", Quiet = true })
				KC.advance(0.3)
				H.esc()
				T.check(not FC.IsOpen() and not H.shown(H.win()), "fusion ui: ...then Esc closes the window")
				-- a chained sheet closed without a pick ends the chain
				FC.Open("Mix", {})
				KC.advance(0.3)
				FC.Select(nil, nil)
				KC.advance(0.2)
				H.click(H.find("Slot_Body"))
				T.check(PP.IsOpen() and H.sheetTitle() == "PICK THE BODY PET", "fusion ui: (chain) the Body sheet")
				PP.Pick("pebble_pup")
				KC.advance(0.4)
				T.check(PP.IsOpen() and H.sheetTitle() == "PICK THE STYLE PET", "fusion ui: (chain) ...then the Style sheet")
				PP.Close()
				KC.advance(0.6)
				plan = FC.Plan()
				T.check(not PP.IsOpen() and plan and plan.Inputs and #plan.Inputs == 1 and plan.Inputs[1].Key == "pebble_pup", "fusion ui: closing the Style sheet without a pick leaves Style empty and opens nothing more")
				T.check(H.t("PetName", H.find("Slot_Style")) == "Pick a pet" and H.disabled(H.find("SwapButton")), "fusion ui: ...the empty slot says 'Pick a pet', the swap is greyed")
				FC.Select(nil, nil)
				FC.Close()
				KC.advance(0.3)
				FC.Open("Mix", {})
				KC.advance(0.4)
				PP.Close()
				KC.advance(0.6)
				T.check(not PP.IsOpen() and FC.IsOpen(), "fusion ui: closing the first (Body) sheet ends the chain too")
				-- Close() closes the sheet with the window
				FC.Open("Upgrade", { Key = "maple_fox" })
				KC.advance(0.3)
				H.click(H.find("Stack"))
				T.check(PP.IsOpen(), "fusion ui: (Close) the sheet is up")
				FC.Close()
				KC.advance(0.3)
				T.check(not PP.IsOpen() and not FC.IsOpen(), "fusion ui: Close() closes the sheet and the window")
				-- no pets at all: nothing opens by itself
				H.feed({ NoPets = true })
				FC.Select(nil)
				FC.Open("Upgrade", {})
				KC.advance(0.4)
				T.check(FC.IsOpen() and not PP.IsOpen(), "fusion ui: no pets: the sheet does not open by itself")
				-- (review fix) an empty pick list says why on the HintLine instead of doing nothing
				local NO_PETS = "No pets yet! Spin a roulette in the Shop to hatch one."
				local NO_UPGRADE = "Nothing to upgrade yet. Hybrids and Rainbow pets can't go higher."
				local NO_MIX = "You need regular pets to mix. Hybrids can't be mixed again."
				local hint = H.find("HintLine")
				T.check(hint and H.shown(hint) and hint.Text == NO_PETS, "fusion ui: no pets: the HintLine says how to get one", H.text(hint))
				FC.Close()
				KC.advance(4)
				-- only a Rainbow pet and a hybrid: nothing can go up a finish
				H.feed({ Only = { { "maple_fox@Rainbow", 20, 1 } }, Team = {} })
				FC.Select(nil, nil)
				FC.Open("Upgrade", {})
				KC.advance(0.4)
				hint = H.find("HintLine")
				T.check(FC.IsOpen() and not PP.IsOpen() and hint and H.shown(hint) and hint.Text == NO_UPGRADE,
					"fusion ui: only a Rainbow pet and a hybrid: Upgrade's sheet does not open; the HintLine says why", H.text(hint))
				KC.advance(4)
				T.check(not H.shown(hint), "fusion ui: ...(the hint goes after a few seconds)")
				H.click(H.find("Stack"))
				T.check(not PP.IsOpen() and H.shown(hint) and hint.Text == NO_UPGRADE, "fusion ui: ...tapping the Stack says it again", H.text(hint))
				H.click(H.find("Tab_Mix"))
				T.check(PP.IsOpen() and H.sheetTitle() == "PICK THE BODY PET", "fusion ui: ...Mix still has the Rainbow pet to pick", H.sheetTitle())
				PP.Close()
				KC.advance(0.3)
				FC.Close()
				KC.advance(4)
				-- only the hybrid: nothing to mix either
				H.feed({ Only = {}, Team = {} })
				FC.Select(nil, nil)
				FC.Open("Mix", {})
				KC.advance(0.4)
				hint = H.find("HintLine")
				T.check(FC.IsOpen() and not PP.IsOpen() and hint and H.shown(hint) and hint.Text == NO_MIX,
					"fusion ui: only a hybrid: Mix's sheet does not open; the HintLine says why", H.text(hint))
				KC.advance(4)
				H.click(H.find("Slot_Style"))
				T.check(not PP.IsOpen() and H.shown(hint) and hint.Text == NO_MIX, "fusion ui: ...tapping a slot says it again", H.text(hint))
			end)
		end)
	end)

	------------------------------------------------------------------------------------------------
	S.client_fusion_layouts = guarded("client_fusion_layouts", function()
		local sizes = { { 844, 390, true }, { 1280, 720, false }, { 1366, 768, false }, { 1920, 1080, false }, { 1280, 640, false }, { 667, 375, true } }
		for _, sz in ipairs(sizes) do
			local label = fmt("fusion layouts %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				H.with(label, nil, function(FC, PP)
					local GuiService = game:GetService("GuiService")
					local touchBefore = GuiService.TouchControlsEnabled
					for _, tab in ipairs({ "Upgrade", "Mix" }) do
						local l = label .. " " .. tab
						H.openTab(FC, PP, tab)
						local win = H.win()
						RedoGeom.check(win, l, { NoOverlap = (tab == "Mix") and (sz[3] and MIX_PHONE or MIX_NAMES) or UP_NAMES })
						H.fitsAll(l, tab)
						if sz[3] then
							T.eq(FC.Layout(), "Phone", l .. ": Layout() == 'Phone'")
						else
							T.eq(FC.Layout(), "PC", l .. ": Layout() == 'PC'")
							H.pcText(l)
						end
						if sz[1] == 844 then
							local p, s = win.AbsolutePosition, win.AbsoluteSize
							T.check(math.abs(p.X - 12) <= 1 and math.abs(p.Y - 59) <= 1 and math.abs(s.X - 820) <= 1 and math.abs(s.Y - 330) <= 1,
								l .. ": an 820x330 box at y 59", RedoGeom.desc(win))
							T.check(GuiService.TouchControlsEnabled == false, l .. ": Roblox's touch controls go while it is up")
						end
					end
					FC.Close()
					KC.advance(0.4)
					if sz[1] == 844 then
						T.check(GuiService.TouchControlsEnabled == touchBefore, label .. ": ...and come back after")
					end
					-- the empty Upgrade state (the sheet closed without a pick)
					FC.Open("Upgrade", { Key = "maple_fox" })
					KC.advance(0.3)
					FC.Select(nil)
					KC.advance(0.3)
					RedoGeom.check(H.win(), label .. " (empty Upgrade)", { NoOverlap = UP_NAMES })
				end)
			end)
		end
		-- a resize while open, the sheet up
		RedoGeom.at(1920, 1080, false, "fusion resize", function()
			H.with("fusion resize", nil, function(FC, PP)
				H.openTab(FC, PP, "Mix")
				H.click(H.find("Slot_Style"))
				T.check(PP.IsOpen(), "fusion resize: (the sheet is up)")
				RedoGeom.check(H.win(), "fusion resize 1920x1080", { NoOverlap = MIX_NAMES })
				Mock.SetViewport(844, 390)
				KC.advance(0.6)
				RedoGeom.check(H.win(), "fusion resize -> 844x390", { NoOverlap = MIX_PHONE })
				RedoGeom.check(H.sheetWin(), "fusion resize -> 844x390 (sheet)", {})
				T.eq(FC.Layout(), "Phone", "fusion resize: Phone at 844x390")
				Mock.SetViewport(1920, 1080)
				KC.advance(0.6)
				RedoGeom.check(H.win(), "fusion resize -> 1920x1080", { NoOverlap = MIX_NAMES })
				T.eq(FC.Layout(), "PC", "fusion resize: PC again")
			end)
		end)
	end)

	------------------------------------------------------------------------------------------------
	S.client_fusion_portrait = guarded("client_fusion_portrait", function()
		local label = "fusion portrait 390x844"
		H.with(label, nil, function(FC, PP)
			H.openTab(FC, PP, "Upgrade")
			T.eq(FC.Layout(), "Portrait", label .. ": Layout() == 'Portrait'")
			-- (the header's token chip has no room on a portrait phone: the CostBar says the balance)
			RedoGeom.check(H.win(), label .. " Upgrade", { NoOverlap = UP_NAMES })
			H.fitsAll(label .. " Upgrade", "Upgrade")
			local stack, result = H.find("Stack"), H.find("Result")
			T.check(stack and result and stack.AbsolutePosition.Y + stack.AbsoluteSize.Y <= result.AbsolutePosition.Y + 0.5, label .. ": the Stack sits above the Result",
				RedoGeom.desc(stack) .. " / " .. RedoGeom.desc(result))
			H.openTab(FC, PP, "Mix")
			RedoGeom.check(H.win(), label .. " Mix", { NoOverlap = MIX_PORTRAIT })
			H.fitsAll(label .. " Mix", "Mix")
			local body, style = H.find("Slot_Body"), H.find("Slot_Style")
			result = H.find("Result")
			T.check(body and style and result and body.AbsolutePosition.Y + body.AbsoluteSize.Y <= result.AbsolutePosition.Y + 0.5
				and style.AbsolutePosition.Y + style.AbsoluteSize.Y <= result.AbsolutePosition.Y + 0.5, label .. ": the slots sit above the Result",
				RedoGeom.desc(body) .. " / " .. RedoGeom.desc(result))
			T.check(body and style and math.abs(body.AbsolutePosition.Y - style.AbsolutePosition.Y) < 1 and style.AbsolutePosition.X > body.AbsolutePosition.X,
				label .. ": ...side by side", RedoGeom.desc(body) .. " / " .. RedoGeom.desc(style))
			-- the empty Upgrade state
			FC.Open("Upgrade", { Key = "maple_fox" })
			KC.advance(0.3)
			FC.Select(nil)
			KC.advance(0.3)
			RedoGeom.check(H.win(), label .. " (empty Upgrade)", { NoOverlap = UP_NAMES })
		end)
	end)

	------------------------------------------------------------------------------------------------
	-- (Task 12) the Mix move chips and the outcome lines
	S.client_fusion_moves = guarded("client_fusion_moves", function()
		local function mtText(mt)
			if type(mt) ~= "table" then
				return tostring(mt)
			end
			local a, s = mt.Attack or {}, mt.Special or {}
			return fmt("%s/%s + %s/%s", tostring(a.Element), tostring(a.Name), tostring(s.Kind), tostring(s.Name))
		end
		local function lastMix(mark)
			local calls = H.calls(mark)
			return #calls, calls[1] and calls[1].args or {}
		end
		RedoGeom.at(1920, 1080, false, "fusion moves pc", function()
			H.with("client_fusion_moves", { Extra = { { "ember_phoenix", 30, 1 } } }, function(FC, PP)
				if not T.check(type(FC.SetMoves) == "function" and type(FC.Moves) == "function" and type(FC.MovesText) == "function",
					"fusion moves: FusionController.SetMoves / Moves / MovesText exist") then
					return
				end
				-- MovesText (pure): letter 1 = the attack's parent, letter 2 = the special's; stage 0's names
				T.eq(mtText(FC.MovesText("maple_fox", "storm_tabby", "SB")), "Storm/Bolt + Pounce/Leaf Pounce", "fusion moves: MovesText(maple, tabby, 'SB')")
				T.eq(mtText(FC.MovesText("maple_fox", "storm_tabby", "BS")), "Flame/Flare + Storm/Static Storm", "fusion moves: MovesText(maple, tabby, 'BS')")
				T.eq(mtText(FC.MovesText("maple_fox", "storm_tabby", "XX")), "Flame/Flare + Pounce/Leaf Pounce", "fusion moves: MovesText: junk moves read as 'BB'")
				T.eq(mtText(FC.MovesText("maple_fox", "storm_tabby")), "Flame/Flare + Pounce/Leaf Pounce", "fusion moves: MovesText: nil moves read as 'BB'")
				T.eq(mtText(FC.MovesText("maple_fox@Golden", "storm_tabby", "SS")), "Storm/Bolt + Storm/Static Storm", "fusion moves: MovesText reads a finish key's species")
				T.check(FC.MovesText("hyb:hc1", "storm_tabby", "BB") == nil and FC.MovesText(nil, "storm_tabby", "BB") == nil and FC.MovesText("maple_fox", "no_such_pet", "BB") == nil,
					"fusion moves: MovesText is nil for a hybrid, a missing or an unknown pet")

				-- Body Maple Fox + Style Storm Tabby: the default, both from the Body
				H.openTab(FC, PP, "Mix")
				T.eq(FC.Moves(), "BB", "fusion moves: the default is 'BB' (the Body gives both = today's hybrid)")
				local cb, cs = H.find("Chips_Body"), H.find("Chips_Style")
				T.check(H.shown(cb) and H.shown(cs), "fusion moves: Chips_Body and Chips_Style are shown")
				for _, side in ipairs({ "Body", "Style" }) do
					local slot, chips = H.find("Slot_" .. side), H.find("Chips_" .. side)
					T.check(slot and chips and chips.AbsolutePosition.Y >= H.bottom(slot) - 0.5 and math.abs(chips.AbsolutePosition.X - slot.AbsolutePosition.X) <= 1
						and math.abs(chips.AbsoluteSize.X - slot.AbsoluteSize.X) <= 1, "fusion moves: Chips_" .. side .. " sit under their slot, as wide as it",
						RedoGeom.desc(slot) .. " / " .. RedoGeom.desc(chips))
					local a, s = H.chip(side, "Attack"), H.chip(side, "Special")
					T.check(a and s and a:IsA("GuiButton") and s:IsA("GuiButton") and s.AbsolutePosition.Y >= H.bottom(a) - 0.5, "fusion moves: ...an Attack chip over a Special chip (" .. side .. ")")
				end
				T.eq(H.lits(), "1100", "fusion moves: 'BB': the Body's two chips are lit, the Style's are not")
				T.check(H.checksMatch(), "fusion moves: ...every lit chip (and only those) shows its check")
				T.eq(H.text(H.chip("Body", "Attack")), SWORD .. " Flare " .. DOT .. " Flame", "fusion moves: PC Body attack chip '<sword> Flare . Flame'")
				T.eq(H.text(H.chip("Body", "Special")), STAR .. " Leaf Pounce " .. DOT .. " Pounce", "fusion moves: PC Body special chip '<star> Leaf Pounce . Pounce'")
				T.eq(H.text(H.chip("Style", "Attack")), SWORD .. " Bolt " .. DOT .. " Storm", "fusion moves: PC Style attack chip '<sword> Bolt . Storm'")
				T.eq(H.text(H.chip("Style", "Special")), STAR .. " Static Storm " .. DOT .. " Storm", "fusion moves: PC Style special chip '<star> Static Storm . Storm'")
				local result = H.find("Result")
				local oa, os2 = RedoGeom.find(result, "OutcomeAttack"), RedoGeom.find(result, "OutcomeSpecial")
				T.check(H.shown(oa) and H.shown(os2), "fusion moves: PC: OutcomeAttack and OutcomeSpecial inside the NEW HYBRID card")
				T.eq(H.text(oa), "Normal attack: Flame (Flare)", "fusion moves: PC OutcomeAttack")
				T.eq(H.text(os2), "Special: Pounce (Leaf Pounce)", "fusion moves: PC OutcomeSpecial")
				T.check(not H.shown(H.find("Outcome")), "fusion moves: PC: no phone Outcome line")

				-- a tap on the Style's special chip moves the special
				H.click(H.chip("Style", "Special"))
				T.eq(FC.Moves(), "BS", "fusion moves: tapping the Style's special chip -> 'BS'")
				T.eq(H.lits(), "1001", "fusion moves: ...the Body's attack and the Style's special are lit")
				T.check(H.checksMatch(), "fusion moves: ...the checks follow")
				T.eq(H.text(os2), "Special: Storm (Static Storm)", "fusion moves: ...the special line reads Static Storm")
				T.eq(H.text(oa), "Normal attack: Flame (Flare)", "fusion moves: ...the attack line stays")
				local plan = FC.Plan()
				T.check(plan and plan.SpecialFrom == "Style" and plan.ResultDef and plan.ResultDef.Special and plan.ResultDef.Special.Name == "Static Storm",
					"fusion moves: ...the preview record takes the Style's special (SpecialFrom 'Style')", plan and tostring(plan.SpecialFrom))
				-- and the attack
				H.click(H.chip("Style", "Attack"))
				T.eq(FC.Moves(), "SS", "fusion moves: tapping the Style's attack chip -> 'SS'")
				T.eq(H.lits(), "0011", "fusion moves: ...the Style's two chips are lit")
				T.eq(H.text(oa), "Normal attack: Storm (Bolt)", "fusion moves: ...the attack line reads Storm (Bolt)")
				T.eq(H.pills().Pill_Elements, "Storm + Flame", "fusion moves: ...the pills show the record's element order 'Storm + Flame'")
				plan = FC.Plan()
				T.check(plan and plan.Elements and plan.Elements[1] == "Storm" and plan.Elements[2] == "Flame" and plan.ResultDef and plan.ResultDef.Element == "Storm",
					"fusion moves: ...the preview hybrid's first element is Storm")
				H.click(H.chip("Style", "Attack"))
				T.eq(FC.Moves(), "SS", "fusion moves: tapping a lit chip changes nothing")

				-- FUSE sends the moves
				local mark = #Mock.RemoteLog
				H.click(H.find("FuseButton"))
				local n, args = lastMix(mark)
				T.check(n == 1 and args[1] == "Mix" and args[2] == "maple_fox" and args[3] == "storm_tabby" and args[4] == "SS",
					"fusion moves: FUSE! sends exactly one Fusion('Mix', maple, tabby, 'SS')", n .. " calls, moves " .. tostring(args[4]))
				KC.toClient("Fusion", "Result", { Ok = false, Reason = "x", Quiet = true })
				KC.advance(0.3)

				-- the swap keeps each move with its pet
				H.click(H.find("SwapButton"))
				T.eq(H.t("PetName", H.find("Slot_Body")), "Storm Tabby", "fusion moves: (swap) Storm Tabby is the Body now")
				T.eq(FC.Moves(), "BB", "fusion moves: swap: 'SS' -> 'BB' (both moves stay with Storm Tabby, now the Body)")
				T.eq(H.lits(), "1100", "fusion moves: ...the chips lit under the new Body")
				T.eq(H.text(H.chip("Body", "Attack")), SWORD .. " Bolt " .. DOT .. " Storm", "fusion moves: ...the Body's chips are Storm Tabby's")
				T.eq(H.text(oa), "Normal attack: Storm (Bolt)", "fusion moves: ...the attack line is unchanged")
				T.eq(H.text(os2), "Special: Storm (Static Storm)", "fusion moves: ...the special line is unchanged")
				FC.SetMoves("aurora_fox", "pebble_pup")
				FC.SetMoves(5, {})
				KC.advance(0.2)
				T.eq(FC.Moves(), "BB", "fusion moves: SetMoves with owned keys that are in no slot (or non-keys) changes nothing")
				FC.SetMoves(nil, "maple_fox")
				KC.advance(0.2)
				T.eq(FC.Moves(), "BS", "fusion moves: SetMoves(nil, the Style key) -> 'BS'")
				H.click(H.find("SwapButton"))
				T.eq(FC.Moves(), "SB", "fusion moves: swap flips 'BS' -> 'SB' (Storm Tabby's attack, Maple Fox's special)")
				T.eq(H.lits(), "0110", "fusion moves: ...lit: the Body's special, the Style's attack")
				T.eq(H.text(oa), "Normal attack: Storm (Bolt)", "fusion moves: ...attack Storm (Bolt)")
				T.eq(H.text(os2), "Special: Pounce (Leaf Pounce)", "fusion moves: ...special Pounce (Leaf Pounce)")
				FC.SetMoves("aurora_fox", 5)
				KC.advance(0.2)
				T.eq(FC.Moves(), "SB", "fusion moves: SetMoves ignores a key that is in no slot and a non-key")
				FC.SetMoves("maple_fox", "storm_tabby")
				KC.advance(0.2)
				T.eq(FC.Moves(), "BS", "fusion moves: SetMoves(body key, style key) -> 'BS'")
				FC.SetMoves("storm_tabby", "maple_fox")
				KC.advance(0.2)
				mark = #Mock.RemoteLog
				H.click(H.find("FuseButton"))
				n, args = lastMix(mark)
				T.check(n == 1 and args[4] == "SB", "fusion moves: FUSE! sends 'SB'", n .. " calls, moves " .. tostring(args[4]))
				KC.toClient("Fusion", "Result", { Ok = false, Reason = "x", Quiet = true })
				KC.advance(0.3)

				-- a new pet in either slot resets the choice
				H.click(H.find("Slot_Style"))
				T.check(PP.IsOpen() and PP.Pick("pebble_pup"), "fusion moves: (pick Pebble Pup as the Style)")
				KC.advance(0.4)
				T.eq(FC.Moves(), "BB", "fusion moves: a new Style pet resets to 'BB'")
				T.eq(H.text(H.chip("Style", "Attack")), SWORD .. " Quake " .. DOT .. " Earth", "fusion moves: ...the Style's chips are Pebble Pup's")
				FC.SetMoves("pebble_pup", "pebble_pup")
				KC.advance(0.2)
				T.eq(FC.Moves(), "SS", "fusion moves: (SS)")
				FC.Select("maple_fox", "storm_tabby")
				KC.advance(0.3)
				T.eq(FC.Moves(), "BB", "fusion moves: new pets through Select reset to 'BB'")

				-- equal elements: one element, the attack is no choice
				FC.Select("maple_fox", "ember_phoenix")
				KC.advance(0.3)
				local ab, as2 = H.chip("Body", "Attack"), H.chip("Style", "Attack")
				T.check(H.lit(ab) and H.lit(as2) and ab.Active == false and as2.Active == false and H.disabled(ab) and H.disabled(as2),
					"fusion moves: two Flame pets: both attack chips lit and inactive")
				H.click(as2)
				FC.SetMoves("ember_phoenix", nil)
				KC.advance(0.2)
				T.eq(FC.Moves(), "BB", "fusion moves: ...tapping one (or SetMoves) changes nothing")
				T.eq(H.pills().Pill_Elements, "Flame", "fusion moves: ...the pills show the one element")
				T.eq(H.text(oa), "Normal attack: Flame (Flare)", "fusion moves: ...attack Flame (Flare)")
				local ss = H.chip("Style", "Special")
				T.check(ss and ss.Active ~= false and not H.disabled(ss), "fusion moves: ...the special chips stay tappable")
				H.click(ss)
				T.eq(FC.Moves(), "BS", "fusion moves: ...and the special still moves ('BS')")
				T.eq(H.text(os2), "Special: Blast (Phoenix Flare)", "fusion moves: ...special Blast (Phoenix Flare)")

				-- the geometry at 1920x1080
				FC.Select("maple_fox", "storm_tabby")
				KC.advance(0.3)
				RedoGeom.check(H.win(), "fusion moves 1920x1080", { NoOverlap = MIX_NAMES })
				H.fitsAll("fusion moves 1920x1080", "Mix")
				local rname, pills = H.find("ResultName"), H.find("Pills")
				T.check(H.boxIn(oa, result) and H.boxIn(os2, result), "fusion moves: PC: the outcome lines lie inside the NEW HYBRID card", RedoGeom.desc(oa) .. " / " .. RedoGeom.desc(result))
				T.check(rname and pills and oa.AbsolutePosition.Y >= H.bottom(rname) - 0.5 and os2.AbsolutePosition.Y >= H.bottom(oa) - 0.5 and H.bottom(os2) <= pills.AbsolutePosition.Y + 0.5,
					"fusion moves: PC: name, then the two lines, then the pills (top to bottom, no overlap)",
					RedoGeom.desc(rname) .. " / " .. RedoGeom.desc(oa) .. " / " .. RedoGeom.desc(os2) .. " / " .. RedoGeom.desc(pills))
				T.check(oa.TextSize >= 18 and os2.TextSize >= 18, "fusion moves: PC: the lines are >= 18 design px")
			end)
		end)

		RedoGeom.at(844, 390, true, "fusion moves phone", function()
			H.with("client_fusion_moves phone", nil, function(FC, PP)
				if type(FC.Moves) ~= "function" then
					T.fail("fusion moves phone: no FusionController.Moves")
					return
				end
				H.openTab(FC, PP, "Mix")
				local win = H.win()
				local out = H.find("Outcome")
				T.check(H.shown(out), "fusion moves phone: the one Outcome line is shown")
				T.eq(H.text(out), "Normal attack: Flame (Flare) " .. DOT .. " Special: Pounce (Leaf Pounce)", "fusion moves phone: the Outcome line reads both moves")
				T.check(not H.shown(H.find("OutcomeAttack")) and not H.shown(H.find("OutcomeSpecial")), "fusion moves phone: no outcome lines in the 176 px card")
				T.check(not H.shown(H.find("Info")), "fusion moves phone: the Outcome takes the Info line's place")
				if out and win then
					local p, s = out.AbsolutePosition, out.AbsoluteSize
					local wp = win.AbsolutePosition
					local slot = H.find("Chips_Body")
					T.check(math.abs(p.X - (wp.X + 14)) <= 1 and math.abs(s.X - 792) <= 1 and math.abs(s.Y - 40) <= 1 and slot and p.Y >= H.bottom(slot) - 0.5,
						"fusion moves phone: the line is 792 x 40 at x 14, under the slot row", RedoGeom.desc(out))
					T.check(out.TextSize >= 15, "fusion moves phone: ...at >= 15 px", tostring(out.TextSize))
				end
				for _, side in ipairs({ "Body", "Style" }) do
					for _, which in ipairs({ "Attack", "Special" }) do
						local c = H.chip(side, which)
						local sz = c and c.AbsoluteSize
						T.check(sz and math.abs(sz.X - 130) <= 1 and math.abs(sz.Y - 44) <= 1, "fusion moves phone: " .. side .. " " .. which .. " chip is 130 x 44", c and RedoGeom.desc(c) or "nil")
					end
				end
				T.eq(H.text(H.chip("Body", "Attack")), SWORD .. " Flare", "fusion moves phone: the attack chip '<sword> Flare'")
				T.eq(H.text(H.chip("Body", "Special")), STAR .. " Leaf Pounce", "fusion moves phone: the special chip '<star> Leaf Pounce'")
				local styleSpecial = H.chip("Style", "Special")
				T.eq(H.text(styleSpecial), STAR .. " Static Storm", "fusion moves phone: every chip keeps its glyph ('<star> Static Storm', wrapped when it must)")
				local okFit, fitDetail = RedoGeom.fits(styleSpecial)
				T.check(okFit, "fusion moves phone: ...and fits its 130 x 44", fitDetail)
				RedoGeom.check(win, "fusion moves 844x390", { NoOverlap = { "Slot_Body", "Chips_Body", "SwapButton", "Slot_Style", "Chips_Style", "Arrow", "Result", "Outcome", "CostBar", "FuseButton" } })
				H.fitsAll("fusion moves 844x390", "Mix")
				-- a tap on a phone
				H.click(H.chip("Style", "Special"))
				T.eq(FC.Moves(), "BS", "fusion moves phone: tapping the Style's special chip -> 'BS'")
				T.eq(H.text(out), "Normal attack: Flame (Flare) " .. DOT .. " Special: Storm (Static Storm)", "fusion moves phone: ...the line follows")
				local mark = #Mock.RemoteLog
				H.click(H.find("FuseButton"))
				local n, args = lastMix(mark)
				T.check(n == 1 and args[4] == "BS", "fusion moves phone: FUSE! sends 'BS'", n .. " calls")
				KC.toClient("Fusion", "Result", { Ok = false, Reason = "x", Quiet = true })
				KC.advance(0.3)

				-- long specials: the line never cuts (the kind words drop first, then it wraps)
				local Cat = H.req("shared/PetCatalog")
				local special = Cat and Cat.Get("storm_tabby") and Cat.Get("storm_tabby").Special
				local oldName = special and special.Name
				local okLong, errLong = pcall(function()
					special.Name = "Wish Upon the Stars"
					FC.Select("maple_fox", "storm_tabby")
					KC.advance(0.3)
					T.eq(FC.Moves(), "BS", "fusion moves phone: (same pets: the choice stays)")
					T.eq(H.text(out), "Normal attack: Flame (Flare) " .. DOT .. " Special: Storm (Wish Upon the Stars)", "fusion moves phone: 'Wish Upon the Stars' still fits whole")
					local ok, detail = RedoGeom.fits(out)
					T.check(ok and out.TextFits ~= false, "fusion moves phone: ...and fits its box", detail)
					local c = H.chip("Style", "Special")
					ok, detail = RedoGeom.fits(c)
					T.check(ok and c.Text:find("Wish", 1, true) ~= nil, "fusion moves phone: ...its chip fits too (wrapped inside 130 x 44)", detail)
					special.Name = "Wish Upon the Stars of the Far Northern Winter Sky"
					FC.Select("maple_fox", "storm_tabby")
					KC.advance(0.3)
					local short = "Normal attack: Flare " .. DOT .. " Special: Wish Upon the Stars of the Far Northern Winter Sky"
					T.eq(H.text(out), short, "fusion moves phone: too wide: the kind words drop first")
					ok, detail = RedoGeom.fits(out)
					T.check(ok and out.TextWrapped == false, "fusion moves phone: ...one line that fits (no wrap while the short text fits)", detail)
					Mock.SetViewport(667, 375)
					KC.advance(0.6)
					T.eq(H.text(out), short, "fusion moves 667x375: the short text")
					ok, detail = RedoGeom.fits(out)
					T.check(ok and out.TextWrapped == true and out.TextTruncate == Enum.TextTruncate.None, "fusion moves 667x375: ...wraps to two lines inside the 40 px, never cut", detail)
					Mock.SetViewport(844, 390)
					KC.advance(0.6)
				end)
				if special then
					special.Name = oldName
				end
				if not okLong then
					T.fail("fusion moves phone: long names: error", tostring(errLong))
				end
				FC.Select("maple_fox", "storm_tabby")
				KC.advance(0.3)

				-- a reason goes to the right column; the outcome keeps its line
				LocalPlayer:SetAttribute(H.config().Attr.Tokens, 10)
				FC.Select("maple_fox", "storm_tabby")
				KC.advance(0.3)
				local note = H.find("Note")
				T.check(H.shown(note) and H.text(note):find("Not enough", 1, true) ~= nil and H.shown(out), "fusion moves phone: short of tokens: the Note says so and the Outcome stays", H.text(note))
				RedoGeom.check(win, "fusion moves 844x390 (note)", { NoOverlap = { "Slot_Body", "Chips_Body", "SwapButton", "Slot_Style", "Chips_Style", "Arrow", "Result", "Pills", "Note", "Outcome", "CostBar", "FuseButton" } })
				H.fitsAll("fusion moves 844x390 (note)", "Mix")
				LocalPlayer:SetAttribute(H.config().Attr.Tokens, 50000)
				-- an empty slot: no chips, no outcome, the Info line back
				FC.Select("maple_fox", nil)
				KC.advance(0.3)
				T.check(not H.shown(H.find("Chips_Body")) and not H.shown(H.find("Chips_Style")) and not H.shown(out) and H.shown(H.find("Info")),
					"fusion moves phone: one slot empty: no chips, no Outcome, the Info line")
			end)
		end)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
