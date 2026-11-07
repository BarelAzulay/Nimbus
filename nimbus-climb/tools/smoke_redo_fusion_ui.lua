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
--                           window; Close() closes the sheet too; NimbusFusion ignores the gui inset
--   client_fusion_layouts   Upgrade and Mix at 844x390 (touch), 1280x720, 1366x768, 1920x1080 (+ 1280x640, 667x375 touch):
--                           RedoGeom.check (text >= 14 px, targets >= 44 px, on the screen under the top bar, the named
--                           controls never overlap) and the main texts fit their boxes with the real font widths;
--                           844x390: an 820x330 box at y 59, Layout() "Phone", Roblox's touch controls gone while open and
--                           back after; PC sizes: Layout() "PC", every text >= 18 design px; the empty Upgrade state passes
--                           too; a resize while open (1920x1080 -> 844x390 -> 1920x1080, the sheet up) passes each time
--   client_fusion_portrait  (phone world, 390x844 touch) Layout() "Portrait": the Stack and the slots above the Result, the
--                           two slots side by side, RedoGeom.check passes on both tabs
-- Fixture: Maple Fox x5 (three in the team) + a Golden copy, Storm Tabby, Pebble Pup x4, Honey Bunny x2, an evolved Aurora
-- Fox and a hybrid; Prestige 1 with the Fusion Machine; 50,000 Cloud Tokens. Every scenario puts the profile and the
-- attributes it found back. Deterministic: mock clock only. Plain Lua 5.1 syntax only.

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
	local MIX_NAMES = { "Slot_Body", "SwapButton", "Slot_Style", "Arrow", "Result", "CostBar", "FuseButton", "Info", "Tab_Upgrade", "Tab_Mix", "CloseButton" }

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

	-- a ProfileSync snapshot of the fixture. opts: NoPets, Locked (Prestige 0), Team (the active preset; default TEAM)
	function H.snapshot(opts)
		opts = opts or {}
		local pets, tiers, levels, growth, discovered = {}, {}, {}, {}, {}
		if not opts.NoPets then
			for _, f in ipairs(FIX) do
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
		local names = { "CopiesText", "Note", "ResultName", "Cost", "Have", "FuseButton", "Tab_Upgrade", "Tab_Mix", "TipLine", "Info", "Label" }
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
				T.check(PP.IsOpen() and H.sheetTitle() == "Pick a pet to upgrade", "fusion ui: tapping the Stack opens the sheet titled 'Pick a pet to upgrade'", H.sheetTitle())
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
				T.check(FC.IsOpen() and PP.IsOpen() and H.sheetTitle() == "Pick a pet to upgrade", "fusion ui: Upgrade with no pet: the sheet opens by itself", H.sheetTitle())
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
				T.check(PP.IsOpen() and H.sheetTitle() == "Pick the Body pet", "fusion ui: Mix with empty slots: the Body sheet opens by itself", H.sheetTitle())
				H.sheetDefaults(PP)
				shown = table.concat(PP.Shown(), ",")
				T.check(shown:find("hyb:", 1, true) == nil, "fusion ui: ...no hybrid in it", shown)
				T.check(PP.Pick("maple_fox"), "fusion ui: (pick Maple Fox as the Body)")
				KC.advance(0.4)
				T.check(PP.IsOpen() and H.sheetTitle() == "Pick the Style pet", "fusion ui: a pick: the Style sheet opens next", H.sheetTitle())
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
				T.check(PP.IsOpen() and H.sheetTitle() == "Pick the Style pet" and H.card("storm_tabby") and H.card("storm_tabby"):GetAttribute("Blocked") == "In Body",
					"fusion ui: tapping Slot_Style opens its sheet with the Body's species blocked", H.sheetTitle())
				T.check(H.card("maple_fox") and H.card("maple_fox"):GetAttribute("Selected") == true, "fusion ui: ...the slot's pet selected")
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
				T.check(PP.IsOpen() and H.sheetTitle() == "Pick the Body pet", "fusion ui: (chain) the Body sheet")
				PP.Pick("pebble_pup")
				KC.advance(0.4)
				T.check(PP.IsOpen() and H.sheetTitle() == "Pick the Style pet", "fusion ui: (chain) ...then the Style sheet")
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
						RedoGeom.check(win, l, { NoOverlap = (tab == "Mix") and MIX_NAMES or UP_NAMES })
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
				RedoGeom.check(H.win(), "fusion resize -> 844x390", { NoOverlap = MIX_NAMES })
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
			RedoGeom.check(H.win(), label .. " Mix", { NoOverlap = MIX_NAMES })
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

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
