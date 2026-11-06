-- smoke_redo_train.lua: the Training Place window (docs/superpowers/specs/2026-11-06-window-redo-design.md 5.1, 5.5; plan
-- docs/superpowers/plans/2026-11-06-window-redo.md Task 7): client/Controllers/TrainController.lua, CareController's
-- forwarding and the one-window wiring. Client and phone worlds only (client_files, loaded after smoke_redo_geom.lua, whose
-- RedoGeom it uses):
--   client_train_ui        (1920x1080) OpenPanel("Train") with a pet in training: Window_Train in NimbusTrain, Key() = that pet,
--                          its skill card "Training" with STOP + the timer, the other three "Busy", the spots chip; Prev / Next walk
--                          the picker's default Train order and wrap without opening the sheet; "Change pet" opens the sheet
--                          on the current pet and a pick selects it; TRAIN asks first (today's texts) and Yes sends ONE
--                          PetCare("Train", key, stat), No sends nothing; STOP asks first (Cash back by Job.Paid) and sends
--                          PetCare("TrainStop", key); full spots, short Cash (red cost, disabled), rank 10 (MAX, no
--                          button); InMatch closes the window
--   client_train_wiring    CareController.Close() closes it; Care.Opened("Train") / Closed fire once; opening it closes the
--                          Pets window, the menu Shop window, the Store, the Index, the Fusion Machine and the Gifts window;
--                          the Pets window's Train button opens it on that pet and X goes back (ReturnTo); another window
--                          (WindowOpened "Store") drops the way back; Care.Mode() / IsOpen() while up; Care.Open("Feed")
--                          closes it; the confirm is a higher sibling of the window; Esc closes the confirm, then the sheet,
--                          then the window; CareController.Close() with the sheet up closes both
--   client_train_empty     no job: the sheet opens by itself; X on it leaves the empty window (Key() nil, "Pick a pet", every
--                          skill "NoPet" with an inactive "Pick a pet first" button, no cost or time); Step(1) / Step(-1)
--                          from empty pick the ends of the default order; a tapped disabled button says why on the
--                          HintLine; no pets: the empty text and no sheet; no Training Place: the chip, the build text and
--                          every skill "NoPlace"
--   client_train_layouts   844x390 (touch), 1280x720, 1366x768, 1920x1080 (+ 1280x640, 667x375 touch): RedoGeom.check
--                          (text >= 14 px, targets >= 44 px, on the screen under the top bar, the named controls never
--                          overlap); 844x390: an 820x330 box at
--                          y 59, Layout() "Phone", Roblox's touch controls gone while open and back after; a resize while
--                          open (1920x1080 -> 844x390 -> 1920x1080) passes each time; the empty state and the TRAIN confirm
--                          pass too
--   client_train_portrait  (phone world, 390x844 touch) one column: the pet above the skills, RedoGeom.check passes (the
--                          window, its TRAIN confirm and the empty state)
-- Fixture: six pets (a Rare in training on Physique, an evolved Epic, a stage-2 Legendary with Speed at rank 10, three
-- plain ones), the Training Place at Lv 3 (3 spots). Every scenario puts the profile and the attributes it found back.
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

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

	local MUSCLE = "\240\159\146\170"
	local SKILLS = { "Speed", "Physique", "Ability", "Defense" }
	-- key, level, stored evolution, skill ranks
	local FIX = {
		{ "storm_tabby", 22, 0, { Physique = 3 } }, -- Rare, training Physique (rank 4), team slot 3
		{ "aurora_fox", 34, 1, { Speed = 4 } }, -- Epic, evolved, team slot 1
		{ "ember_phoenix", 41, 2, { Speed = 10, Defense = 2 } }, -- Legendary, stage 2, Speed at the top
		{ "maple_fox", 12, 0, {} },
		{ "pebble_pup", 8, 0, {} },
		{ "honey_bunny", 20, 0, { Ability = 1 } },
	}
	local TRAINING = "storm_tabby"
	local JOB = { Stat = "Physique", In = 130, Rank = 4, Slot = 1, Paid = 2700 }
	local TEAM = { "aurora_fox", "ember_phoenix", "storm_tabby" }
	local NAMES = {
		"Mats", "PetCard", "PetName", "PetLevel", "PrevButton", "ChangeButton", "NextButton", "Skill_Speed", "Skill_Physique",
		"Skill_Ability", "Skill_Defense", "CloseButton", "SpotsChip",
	}

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
	function H.train()
		return H.mod("TrainController")
	end
	function H.care()
		return H.mod("CareController")
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
		return H.pg():FindFirstChild("NimbusTrain")
	end
	function H.win()
		local g = H.gui()
		return g and g:FindFirstChild("Window_Train")
	end
	function H.confirm()
		local g = H.gui()
		return g and g:FindFirstChild("Confirm")
	end
	function H.find(name, root)
		return RedoGeom.find(root or H.win(), name)
	end
	function H.skill(id)
		return H.find("Skill_" .. id)
	end
	function H.part(id, child)
		return RedoGeom.find(H.skill(id), child)
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
	-- a shown text under root that reads exactly `text`
	function H.shownText(root, text)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text == text and KC.isShown(d) then
				return d
			end
		end
		return nil
	end
	function H.states()
		local out = {}
		for i, id in ipairs(SKILLS) do
			local card = H.skill(id)
			out[i] = id .. "=" .. tostring(card and card:GetAttribute("State"))
		end
		return table.concat(out, " ")
	end
	function H.allStates(want)
		for _, id in ipairs(SKILLS) do
			local card = H.skill(id)
			if not (card and card:GetAttribute("State") == want) then
				return false
			end
		end
		return true
	end
	function H.order(PP)
		local out = {}
		for i, e in ipairs(PP.Sorted("Train", PP.Entries("Train"), "Default", "All", "")) do
			out[i] = e.Key
		end
		return out
	end

	-- a ProfileSync snapshot of the fixture. opts: Gym (Training Place level; 0 = not built), Job (false = nobody trains),
	-- Paid (the job's Paid), NoPets
	function H.snapshot(opts)
		opts = opts or {}
		local pets, levels, growth, discovered, busy = {}, {}, {}, {}, {}
		if not opts.NoPets then
			for _, f in ipairs(FIX) do
				pets[f[1]] = 1
				discovered[f[1]] = true
				levels[f[1]] = { Level = f[2], Xp = 5 }
				local g = { Evo = f[3] }
				for k, v in pairs(f[4]) do
					g[k] = v
				end
				growth[f[1]] = g
			end
			if opts.Job ~= false then
				growth[TRAINING].Job = { Stat = JOB.Stat, Ends = os.time() + JOB.In, Rank = JOB.Rank, Slot = JOB.Slot, From = "Follow", Paid = opts.Paid or JOB.Paid }
				busy[TRAINING] = "Training"
			end
		end
		local preset, equipped = {}, {}
		if not opts.NoPets then
			for _, key in ipairs(TEAM) do
				preset[#preset + 1] = key
				if not busy[key] then
					equipped[#equipped + 1] = key
				end
			end
		end
		local gym = opts.Gym
		if gym == nil then
			gym = 3
		end
		local stations = { Garden = 1 }
		if gym > 0 then
			stations.Gym = gym
		end
		return {
			Tokens = 900, Pets = pets, Equipped = equipped, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = discovered, IndexClaimed = {},
			Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 250000, Gems = 0,
			Home = { Level = 22, Prestige = 1, Stations = stations, Garden = {}, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = {}, Hybrids = {}, PetLevels = levels,
			Teams = { Presets = { preset, {}, {} }, Active = 1, Slots = 3, Busy = busy },
			Battle = { Trophies = 0, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			PetGrowth = growth,
			Ring = { Best = 0, Runs = 0 },
		}
	end
	function H.feed(opts)
		KC.toClient("ProfileSync", H.snapshot(opts))
		KC.advance(0.2)
	end
	function H.setCash(n)
		LocalPlayer:SetAttribute(H.config().Attr.Cash, n)
		KC.advance(0.2)
	end
	function H.closeAll()
		for _, name in ipairs({ "TrainController", "CareController", "MenuController", "StoreController", "IndexController", "FusionController", "DailyController" }) do
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
	-- runs fn(TC, PP, State) with the fixture synced; puts the profile and the attributes back after
	function H.with(label, opts, fn)
		local TC, PP = H.train(), H.picker()
		if not T.check(type(TC) == "table" and type(TC.Open) == "function" and type(TC.Close) == "function" and type(TC.IsOpen) == "function"
			and type(TC.Key) == "function" and type(TC.Select) == "function" and type(TC.Step) == "function" and type(TC.Layout) == "function"
			and type(TC.SkillState) == "function" and type(TC.DropReturn) == "function", label .. ": client/Controllers/TrainController.lua loads with its API") then
			return
		end
		if type(TC.Init) == "function" then
			pcall(TC.Init)
		end
		local State = H.state()
		local Config = H.config()
		local before = State and State.Get and State.Get() or nil
		local cashBefore = LocalPlayer:GetAttribute(Config.Attr.Cash)
		local matchBefore = LocalPlayer:GetAttribute(Config.Attr.InMatch)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.Cash, 250000)
		H.closeAll()
		H.feed(opts)
		local ok, err = pcall(fn, TC, PP, State)
		if not ok then
			T.fail(label .. ": error", tostring(err))
		end
		H.closeAll()
		LocalPlayer:SetAttribute(Config.Attr.Cash, cashBefore)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, matchBefore)
		if before then
			KC.toClient("ProfileSync", before)
		end
		KC.advance(0.3)
		KC.flushErrors(label)
	end

	------------------------------------------------------------------------------------------------
	S.client_train_ui = guarded("client_train_ui", function()
		RedoGeom.at(1920, 1080, false, "train ui", function()
			H.with("client_train_ui", nil, function(TC, PP, State)
				local TC_ = TC
				KC.toClient("OpenPanel", "Train", {})
				KC.advance(0.6)
				local win = H.win()
				T.check(H.gui() ~= nil and win ~= nil and H.shown(win) and TC_.IsOpen(), "train ui: OpenPanel('Train') opens Window_Train in NimbusTrain")
				T.eq(TC_.Key(), TRAINING, "train ui: without a key the pet in training is selected")
				T.check(not PP.IsOpen(), "train ui: ...and the sheet stays closed")
				local phys = H.skill("Physique")
				T.check(phys and phys:GetAttribute("State") == "Training" and H.text(H.part("Physique", "Action")) == "STOP",
					"train ui: its skill card is 'Training' with STOP", H.states() .. " / " .. H.text(H.part("Physique", "Action")))
				local timeText = H.text(H.part("Physique", "Time"))
				T.check(timeText:find("2:", 1, true) ~= nil and timeText:find("left", 1, true) ~= nil and timeText:find("Rank " .. JOB.Rank, 1, true) ~= nil,
					"train ui: ...and the timer ('Rank 4 - 2:10 left')", timeText)
				T.check(TC_.SkillState("Speed") == "Busy" and TC_.SkillState("Ability") == "Busy" and TC_.SkillState("Defense") == "Busy"
					and H.skill("Speed"):GetAttribute("State") == "Busy", "train ui: the other three skills are 'Busy'", H.states())
				T.check(H.text(H.part("Speed", "Action")) == "Busy training" and H.disabled(H.part("Speed", "Action")), "train ui: ...'Busy training', disabled")
				T.eq(H.text(H.find("SpotsChip")), "Training spots: 1 / 3 in use", "train ui: the spots chip")
				T.check(H.text(H.find("Name", H.skill("Speed"))) == "Attack Speed", "train ui: Speed reads 'Attack Speed'")
				-- the rank and the bar
				T.eq(H.text(H.part("Physique", "Rank")), "Rank 3 / 10", "train ui: 'Rank 3 / 10'")
				local bar = H.part("Physique", "Bar")
				local lit, segs = 0, 0
				for i = 1, 10 do
					local seg = bar and bar:FindFirstChild("Seg" .. i)
					if seg then
						segs = segs + 1
						if seg:GetAttribute("Lit") == true then
							lit = lit + 1
						end
					end
				end
				T.check(segs == 10 and lit == 3, "train ui: a 10-segment bar with 3 lit", segs .. " / " .. lit)
				-- Prev / Next walk the default Train order, wrapping, the sheet closed
				local order = H.order(PP)
				T.check(#order == #FIX and order[1] == TRAINING, "train ui: the default Train order starts with the pet in training", table.concat(order, ","))
				local walk = true
				for i = 2, #order do
					H.click(H.find("NextButton"))
					if TC_.Key() ~= order[i] then
						walk = false
					end
				end
				H.click(H.find("NextButton"))
				T.check(walk and TC_.Key() == order[1], "train ui: Next walks the order and wraps to the first", tostring(TC_.Key()))
				H.click(H.find("PrevButton"))
				T.eq(TC_.Key(), order[#order], "train ui: Prev from the first wraps to the last")
				H.click(H.find("PrevButton"))
				T.eq(TC_.Key(), order[#order - 1], "train ui: Prev steps back")
				T.check(not PP.IsOpen(), "train ui: Prev / Next never open the sheet")
				-- Change pet: the sheet on the current pet; a pick selects
				TC_.Select(TRAINING)
				KC.advance(0.2)
				H.click(H.find("ChangeButton"))
				T.check(PP.IsOpen(), "train ui: 'Change pet' opens the sheet")
				local card = RedoGeom.find(H.sheetWin(), "Card_" .. TRAINING)
				T.check(card ~= nil and card:GetAttribute("Selected") == true, "train ui: ...with the current pet selected")
				PP.Pick("maple_fox")
				KC.advance(0.3)
				T.check(TC_.Key() == "maple_fox" and not PP.IsOpen(), "train ui: a pick selects that pet and closes the sheet", tostring(TC_.Key()))
				-- TRAIN asks first (today's texts); Yes sends one PetCare("Train", key, stat)
				T.check(TC_.SkillState("Speed") == "Ready" and H.skill("Speed"):GetAttribute("State") == "Ready", "train ui: a free pet's skill is 'Ready'", H.states())
				local TCat = H.req("shared/TycoonCatalog")
				local def = State.DefOf("maple_fox")
				local name = tostring(def.DisplayName or def.Name)
				local cost, seconds = TCat.TrainCost(def, 1), TCat.TrainSeconds(1)
				local _, Util = KC.env()
				T.eq(H.text(H.part("Speed", "Cost")), "$" .. Util.Commas(cost), "train ui: the next rank's cost (TrainCost)")
				T.eq(H.text(H.part("Speed", "Time")), math.floor(seconds / 60 + 0.5) .. " min", "train ui: ...and its time (TrainSeconds)")
				local mark = #Mock.RemoteLog
				H.click(H.part("Speed", "Action"))
				local confirm = H.confirm()
				T.check(confirm ~= nil and H.shown(confirm), "train ui: TRAIN asks first")
				T.eq(H.text(H.find("Title", confirm)), MUSCLE .. " Train Attack Speed?", "train ui: today's confirm title")
				T.eq(H.text(H.find("Text", confirm)), name .. " goes to Rank 1 Attack Speed for " .. TCat.FormatCash(cost) .. ". It takes 1 min. " .. name
					.. " rests at home until it's done, then comes back by itself.", "train ui: today's confirm text")
				T.eq(H.text(H.find("Yes", confirm)), "Train " .. TCat.FormatCash(cost), "train ui: Yes reads 'Train $300'")
				T.eq(#KC.serverCalls("PetCare", mark), 0, "train ui: ...nothing sent yet")
				H.click(H.find("Yes", confirm))
				local pc = KC.serverCalls("PetCare", mark)
				T.check(#pc == 1 and pc[1].args[1] == "Train" and pc[1].args[2] == "maple_fox" and pc[1].args[3] == "Speed" and not H.shown(confirm),
					"train ui: Yes sends ONE PetCare('Train', key, 'Speed') and closes the confirm", tostring(#pc))
				mark = #Mock.RemoteLog
				H.click(H.part("Physique", "Action"))
				T.check(H.shown(confirm) and H.text(H.find("Title", confirm)):find("Physique", 1, true) ~= nil, "train ui: (No) the confirm again")
				H.click(H.find("No", confirm))
				T.check(#KC.serverCalls("PetCare", mark) == 0 and not H.shown(confirm), "train ui: No sends nothing and closes it")
				-- STOP asks first: the Cash-back wording follows Job.Paid
				TC_.Select(TRAINING)
				KC.advance(0.3)
				mark = #Mock.RemoteLog
				H.click(H.part("Physique", "Action"))
				T.check(H.shown(confirm) and H.text(H.find("Title", confirm)) == "Stop training?" and H.text(H.find("Text", confirm)):find("You get the Cash back, no rank.", 1, true) == 1,
					"train ui: STOP asks first ('You get the Cash back, no rank.')", H.text(H.find("Text", confirm)))
				H.click(H.find("Yes", confirm))
				pc = KC.serverCalls("PetCare", mark)
				T.check(#pc == 1 and pc[1].args[1] == "TrainStop" and pc[1].args[2] == TRAINING, "train ui: ...then sends PetCare('TrainStop', key)", tostring(#pc))
				H.feed({ Paid = 0 })
				KC.advance(0.6)
				H.click(H.part("Physique", "Action"))
				T.check(H.shown(confirm) and H.text(H.find("Text", confirm)):find("No rank and no Cash back", 1, true) == 1, "train ui: a job paid before a Prestige: 'No rank and no Cash back'", H.text(H.find("Text", confirm)))
				H.click(H.find("No", confirm))
				-- full spots
				H.feed({ Gym = 1 })
				TC_.Select("maple_fox")
				KC.advance(0.6)
				T.check(TC_.SkillState("Speed") == "Full" and H.text(H.part("Speed", "Action")) == "Spots full" and H.disabled(H.part("Speed", "Action")),
					"train ui: every spot in use: 'Spots full', disabled", H.states() .. " / " .. H.text(H.find("SpotsChip")))
				-- Cash short
				H.feed({})
				H.setCash(100)
				KC.advance(0.6)
				local costLabel = H.part("Speed", "Cost")
				local c = costLabel and costLabel.TextColor3
				T.check(TC_.SkillState("Speed") == "Short" and H.disabled(H.part("Speed", "Action")) and c and c.R > c.G + 0.2,
					"train ui: Cash short: 'Short', the cost in red, TRAIN disabled", H.states())
				H.setCash(250000)
				-- rank 10
				TC_.Select("ember_phoenix")
				KC.advance(0.6)
				T.check(TC_.SkillState("Speed") == "Max" and not H.shown(H.part("Speed", "Action")) and H.shown(H.part("Speed", "MaxTag")),
					"train ui: rank 10: 'Max', MAX and no button", H.states())
				T.check(TC_.SkillState("Defense") == "Ready", "train ui: ...its other skills train on")
				-- InMatch closes it
				LocalPlayer:SetAttribute(H.config().Attr.InMatch, true)
				KC.advance(0.4)
				T.check(not TC_.IsOpen() and not H.shown(H.win()), "train ui: entering a match closes the window")
				LocalPlayer:SetAttribute(H.config().Attr.InMatch, false)
				KC.advance(0.2)
			end)
		end)
	end)

	------------------------------------------------------------------------------------------------
	S.client_train_wiring = guarded("client_train_wiring", function()
		RedoGeom.at(1920, 1080, false, "train wiring", function()
			H.with("client_train_wiring", nil, function(TC, PP, State)
				local Care = H.care()
				if not T.check(Care and type(Care.NotifyTrain) == "function" and type(Care.CloseOwn) == "function", "train wiring: CareController.NotifyTrain / CloseOwn exist") then
					return
				end
				local opened, closed = {}, 0
				local c1 = Care.Opened:Connect(function(mode)
					opened[#opened + 1] = tostring(mode)
				end)
				local c2 = Care.Closed:Connect(function()
					closed = closed + 1
				end)
				T.check(Care.Open("Train", {}) == true, "train wiring: CareController.Open('Train') forwards (true)")
				KC.advance(0.4)
				T.check(TC.IsOpen() and Care.Mode() == "Train" and Care.IsOpen(), "train wiring: Care.Mode() == 'Train' and Care.IsOpen() while it is up")
				T.check(#opened == 1 and opened[1] == "Train", "train wiring: Care.Opened fired 'Train' once", table.concat(opened, ","))
				TC.Select("maple_fox")
				KC.advance(0.3)
				T.eq(#opened, 1, "train wiring: ...not again on a new pet")
				Care.Close()
				KC.advance(0.4)
				T.check(not TC.IsOpen() and not H.shown(H.win()) and Care.Mode() == nil and not Care.IsOpen(), "train wiring: CareController.Close() closes it")
				T.eq(closed, 1, "train wiring: Care.Closed fired once")
				c1:Disconnect()
				c2:Disconnect()
				-- the confirm is a higher sibling of the window
				TC.Open({ Key = "maple_fox" })
				KC.advance(0.4)
				local confirm, win = H.confirm(), H.win()
				T.check(confirm ~= nil and win ~= nil and confirm.Parent == win.Parent and confirm.ZIndex > win.ZIndex, "train wiring: the confirm lives in NimbusTrain above the window")
				-- opening it closes the other windows
				local others = {
					{ "the Pets window", function()
						H.mod("PetsController").Open({})
					end, function()
						return H.mod("PetsController").IsOpen()
					end },
					{ "the menu Shop window", function()
						H.mod("MenuController").Open("Shop", {})
					end, function()
						return H.mod("MenuController").IsOpen()
					end },
					{ "the Store", function()
						H.mod("StoreController").Open({})
					end, function()
						return H.mod("StoreController").IsOpen()
					end },
					{ "the Index", function()
						H.mod("IndexController").Open()
					end, function()
						return H.mod("IndexController").IsOpen()
					end },
					{ "the Fusion Machine", function()
						H.mod("FusionController").Open("Upgrade", {})
					end, function()
						return H.mod("FusionController").IsOpen()
					end },
					{ "the Gifts window", function()
						H.mod("DailyController").Open({})
					end, function()
						return H.mod("DailyController").IsOpen()
					end },
				}
				for _, o in ipairs(others) do
					H.closeAll()
					pcall(o[2])
					KC.advance(0.5)
					local wasOpen = o[3]() == true
					T.check(wasOpen, "train wiring: " .. o[1] .. " opens (setup)")
					TC.Open({ Key = "maple_fox" })
					KC.advance(0.5)
					T.check(TC.IsOpen() and not o[3](), "train wiring: opening the Training Place closes " .. o[1])
				end
				H.closeAll()
				-- the Pets window's Train button: there and back (ReturnTo)
				local Pets = H.mod("PetsController")
				Pets.Open({ Key = "maple_fox" })
				KC.advance(0.4)
				local petsWin = H.pg():FindFirstChild("NimbusPets"):FindFirstChild("Window_Pets")
				H.click(RedoGeom.find(petsWin, "ActTrain"))
				T.check(TC.IsOpen() and TC.Key() == "maple_fox" and not Pets.IsOpen(), "train wiring: the Pets window's Train opens the Training Place on that pet; the Pets window closes", tostring(TC.Key()))
				H.click(H.find("CloseButton"))
				T.check(not TC.IsOpen() and Pets.IsOpen(), "train wiring: X goes back to the Pets window")
				local detailName = RedoGeom.find(RedoGeom.find(petsWin, "Detail"), "Name")
				T.check(detailName and detailName.Text == State.DefOf("maple_fox").Name, "train wiring: ...on that pet", detailName and detailName.Text or "")
				-- another window drops the way back
				H.click(RedoGeom.find(petsWin, "ActTrain"))
				T.check(TC.IsOpen(), "train wiring: (again) open from the Pets window")
				H.mod("MenuController").WindowOpened:Fire("Store")
				KC.advance(0.5)
				T.check(not TC.IsOpen() and not Pets.IsOpen(), "train wiring: WindowOpened('Store') closes it and the Pets window does not come back")
				H.closeAll()
				-- Care.Open("Feed") while it is up
				TC.Open({ Key = "maple_fox" })
				KC.advance(0.4)
				Care.Open("Feed", {})
				KC.advance(0.4)
				T.check(not TC.IsOpen() and Care.Mode() == "Feed", "train wiring: Care.Open('Feed') closes it and opens the Food Machine", tostring(Care.Mode()))
				H.closeAll()
				-- Esc: the confirm, then the sheet, then the window
				TC.Open({ Key = "maple_fox" })
				KC.advance(0.4)
				H.click(H.part("Speed", "Action"))
				T.check(H.shown(H.confirm()), "train wiring: (Esc) the confirm is up")
				H.esc()
				T.check(not H.shown(H.confirm()) and TC.IsOpen(), "train wiring: Esc closes the confirm first")
				H.click(H.find("ChangeButton"))
				T.check(PP.IsOpen(), "train wiring: (Esc) the sheet is up")
				H.esc()
				T.check(not PP.IsOpen() and TC.IsOpen() and TC.Key() == "maple_fox", "train wiring: Esc closes the sheet next (the pet stays)")
				H.esc()
				T.check(not TC.IsOpen(), "train wiring: then the window")
				-- the gamepad B does the same
				TC.Open({ Key = "maple_fox" })
				KC.advance(0.4)
				Mock.TriggerAction("NimbusTrainBack", "Begin", Mock.NewInput("ButtonB", "Gamepad1", "Begin"))
				KC.advance(0.3)
				T.check(not TC.IsOpen(), "train wiring: gamepad B closes it")
				-- the sheet up, then CareController.Close()
				TC.Open({ Key = "maple_fox" })
				KC.advance(0.4)
				H.click(H.find("ChangeButton"))
				T.check(PP.IsOpen(), "train wiring: (Close) the sheet is up")
				Care.Close()
				KC.advance(0.4)
				T.check(not PP.IsOpen() and not TC.IsOpen(), "train wiring: CareController.Close() closes the sheet and the window")
			end)
		end)
	end)

	------------------------------------------------------------------------------------------------
	S.client_train_empty = guarded("client_train_empty", function()
		RedoGeom.at(1920, 1080, false, "train empty", function()
			H.with("client_train_empty", { Job = false }, function(TC, PP)
				TC.Open({})
				KC.advance(0.5)
				T.check(TC.IsOpen() and PP.IsOpen(), "train empty: no pet in training: the sheet opens by itself")
				H.click(RedoGeom.find(H.sheetWin(), "CloseButton"))
				T.check(not PP.IsOpen() and TC.IsOpen() and TC.Key() == nil, "train empty: X on the sheet leaves the window open with no pet", tostring(TC.Key()))
				T.check(H.shown(H.find("PickPrompt")) and H.text(H.find("PickPrompt")):find("Pick a pet", 1, true) ~= nil, "train empty: the pet card reads 'Pick a pet'")
				T.check(H.allStates("NoPet"), "train empty: every skill is 'NoPet'", H.states())
				local inactive, noNumbers = true, true
				for _, id in ipairs(SKILLS) do
					local b = H.part(id, "Action")
					if not (b and H.shown(b) and b.Text == "Pick a pet first" and H.disabled(b)) then
						inactive = false
					end
					for _, part in ipairs({ "Cost", "Time", "Rank" }) do
						local o = H.part(id, part)
						if o and H.shown(o) and o.Text ~= "" then
							noNumbers = false
						end
					end
				end
				T.check(inactive, "train empty: ...each with an inactive 'Pick a pet first' button")
				T.check(noNumbers, "train empty: ...and no rank, cost or time")
				T.eq(H.text(H.find("ChangeButton")), "Pick a pet", "train empty: 'Change pet' reads 'Pick a pet'")
				-- a tapped disabled button says why
				H.click(H.part("Speed", "Action"))
				local hint = H.find("HintLine")
				T.check(hint and H.shown(hint) and hint.Text == "Pick a pet first", "train empty: tapping it shows 'Pick a pet first' on the HintLine", H.text(hint))
				-- Prev / Next from empty: the ends of the default order
				local order = H.order(PP)
				TC.Step(1)
				KC.advance(0.2)
				T.eq(TC.Key(), order[1], "train empty: Step(1) from empty selects the first")
				TC.Close()
				KC.advance(0.3)
				TC.Open({})
				KC.advance(0.4)
				PP.Close()
				KC.advance(0.2)
				T.check(TC.Key() == nil, "train empty: (again) empty")
				TC.Step(-1)
				KC.advance(0.2)
				T.eq(TC.Key(), order[#order], "train empty: Step(-1) from empty selects the last")
				TC.Close()
				KC.advance(0.3)
				-- no pets at all
				H.feed({ NoPets = true })
				TC.Open({})
				KC.advance(0.5)
				T.check(TC.IsOpen() and not PP.IsOpen(), "train empty: no pets: the sheet does not open")
				T.check(H.shownText(H.win(), "No pets yet! Spin a roulette in the Shop to hatch one.") ~= nil, "train empty: ...and the body says how to get one")
				TC.Close()
				KC.advance(0.3)
				-- no Training Place
				H.feed({ Gym = 0 })
				TC.Open({ Key = "maple_fox" })
				KC.advance(0.5)
				T.eq(H.text(H.find("SpotsChip")), "No Training Place yet", "train empty: no Training Place: the chip")
				T.check(H.shownText(H.win(), "Build the Training Place at home first. Training makes pets tougher in battles!") ~= nil, "train empty: ...the build text")
				T.check(H.allStates("NoPlace") and TC.SkillState("Speed") == "NoPlace", "train empty: ...every skill 'NoPlace'", H.states())
				T.check(not PP.IsOpen(), "train empty: ...and no sheet")
			end)
		end)
	end)

	------------------------------------------------------------------------------------------------
	S.client_train_layouts = guarded("client_train_layouts", function()
		-- (+ 1280x640: the tight PC skill cards; 667x375: a small landscape phone, the slim phone cards)
		local sizes = { { 844, 390, true }, { 1280, 720, false }, { 1366, 768, false }, { 1920, 1080, false }, { 1280, 640, false }, { 667, 375, true } }
		for _, sz in ipairs(sizes) do
			local label = fmt("train layouts %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				H.with(label, nil, function(TC)
					local GuiService = game:GetService("GuiService")
					local touchBefore = GuiService.TouchControlsEnabled
					TC.Open({})
					KC.advance(0.6)
					local win = H.win()
					RedoGeom.check(win, label, { NoOverlap = NAMES })
					-- the TRAIN confirm fits and reads too
					TC.Select("maple_fox")
					KC.advance(0.2)
					H.click(H.part("Speed", "Action"))
					RedoGeom.check(H.confirm(), label .. " (confirm)", { NoOverlap = { "Title", "Text", "Yes", "No" } })
					H.click(H.find("No", H.confirm()))
					if sz[1] == 844 then
						local p, s = win.AbsolutePosition, win.AbsoluteSize
						T.check(math.abs(p.X - 12) <= 1 and math.abs(p.Y - 59) <= 1 and math.abs(s.X - 820) <= 1 and math.abs(s.Y - 330) <= 1,
							label .. ": an 820x330 box at y 59", RedoGeom.desc(win))
						T.eq(TC.Layout(), "Phone", label .. ": Layout() == 'Phone'")
						T.check(GuiService.TouchControlsEnabled == false, label .. ": Roblox's touch controls go while it is up")
						TC.Close()
						KC.advance(0.4)
						T.check(GuiService.TouchControlsEnabled == touchBefore, label .. ": ...and come back after")
					elseif sz[3] then
						T.eq(TC.Layout(), "Phone", label .. ": Layout() == 'Phone'")
					else
						T.eq(TC.Layout(), "PC", label .. ": Layout() == 'PC'")
					end
					-- the empty state
					H.feed({ Job = false })
					TC.Close()
					KC.advance(0.3)
					TC.Open({})
					KC.advance(0.5)
					H.picker().Close()
					KC.advance(0.3)
					RedoGeom.check(H.win(), label .. " (empty)", { NoOverlap = NAMES })
				end)
			end)
		end
		-- a resize while open
		RedoGeom.at(1920, 1080, false, "train resize", function()
			H.with("train resize", nil, function(TC)
				TC.Open({})
				KC.advance(0.6)
				RedoGeom.check(H.win(), "train resize 1920x1080", { NoOverlap = NAMES })
				Mock.SetViewport(844, 390)
				KC.advance(0.6)
				RedoGeom.check(H.win(), "train resize -> 844x390", { NoOverlap = NAMES })
				T.eq(TC.Layout(), "Phone", "train resize: Phone at 844x390")
				Mock.SetViewport(1920, 1080)
				KC.advance(0.6)
				RedoGeom.check(H.win(), "train resize -> 1920x1080", { NoOverlap = NAMES })
				T.eq(TC.Layout(), "PC", "train resize: PC again")
			end)
		end)
	end)

	------------------------------------------------------------------------------------------------
	S.client_train_portrait = guarded("client_train_portrait", function()
		local label = "train portrait 390x844"
		H.with(label, nil, function(TC)
			TC.Open({})
			KC.advance(0.6)
			local win = H.win()
			T.eq(TC.Layout(), "Portrait", label .. ": Layout() == 'Portrait'")
			RedoGeom.check(win, label, { NoOverlap = NAMES })
			local card, speed, phys = H.find("PetCard"), H.skill("Speed"), H.skill("Physique")
			T.check(card and speed and card.AbsolutePosition.Y + card.AbsoluteSize.Y <= speed.AbsolutePosition.Y + 0.5, label .. ": the pet sits above the skills",
				RedoGeom.desc(card) .. " / " .. RedoGeom.desc(speed))
			T.check(speed and phys and math.abs(speed.AbsolutePosition.X - phys.AbsolutePosition.X) < 1 and phys.AbsolutePosition.Y > speed.AbsolutePosition.Y,
				label .. ": the skills are one column", RedoGeom.desc(speed) .. " / " .. RedoGeom.desc(phys))
			TC.Select("maple_fox")
			KC.advance(0.2)
			H.click(H.part("Speed", "Action"))
			RedoGeom.check(H.confirm(), label .. " (confirm)", { NoOverlap = { "Title", "Text", "Yes", "No" } })
			H.click(H.find("No", H.confirm()))
			TC.Close()
			KC.advance(0.3)
			H.feed({ Job = false })
			TC.Open({})
			KC.advance(0.5)
			H.picker().Close()
			KC.advance(0.3)
			RedoGeom.check(H.win(), label .. " (empty)", { NoOverlap = NAMES })
		end)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
