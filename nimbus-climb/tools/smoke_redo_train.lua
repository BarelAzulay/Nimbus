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
--                          then the window; CareController.Close() with the sheet up closes both; review fix: an Escape that
--                          only ends typing in a TextBox (focused, or let go just before) closes nothing
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
--                          pass too; review fix: on the touch sizes a short-Cash TRAIN keeps its price in red inside the
--                          greyed button
--   client_train_portrait  (phone world, 390x844 touch) one column: the pet above the skills, RedoGeom.check passes (the
--                          window, its TRAIN confirm and the empty state); Task 8: the five mats in their band, apart
--   client_train_mats      (Task 8; 1920x1080, then 844x390 touch) the mats row: the pure TrainController.Mats(home,
--                          growthMap, selectedKey) (a job on its Slot, the pending pet on the first free open mat, "+ Add a
--                          pet", locked mats with their unlock level; a job with no Slot / a second job on a taken slot on
--                          the next free mat; a job on a closed mat keeps it with a lock badge; a full place has no pending
--                          mat; review fix: only slots - jobs empty open mats are free, the rest 'InUse' ("Spot in use",
--                          a HintLine reason, no sheet); no Training Place: five locked mats); the window: Mat1..Mat5 with State / Key / LockBadge,
--                          their texts, a job mat's live timer, tapping a job mat selects that pet (its skill turns
--                          "Training"), "+ Add a pet" opens the sheet, a locked mat only says how to open it on the HintLine
--                          (with the house that allows that level when the house caps it); a job ending, a Training Place
--                          upgrade and a Prestige-like snapshot re-render the mats while open; RedoGeom.check with the mats
--                          apart and clear of the pet card and the skills, each inside the band
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
	-- Paid (the job's Paid), NoPets, JobSlot (the training pet's Slot), Extra ({ { key, stat, slot, seconds }... }: more
	-- pets in training), House (the House station level = the house tier)
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
				growth[TRAINING].Job = { Stat = JOB.Stat, Ends = os.time() + JOB.In, Rank = JOB.Rank, Slot = opts.JobSlot or JOB.Slot, From = "Follow", Paid = opts.Paid or JOB.Paid }
				busy[TRAINING] = "Training"
			end
			for _, x in ipairs(opts.Extra or {}) do
				local g = growth[x[1]]
				g.Job = { Stat = x[2], Ends = os.time() + x[4], Rank = (g[x[2]] or 0) + 1, Slot = x[3], From = "Follow", Paid = 100 }
				busy[x[1]] = "Training"
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
		if opts.House then
			stations.House = opts.House
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
				-- (review fix) Escape that only ends typing in a TextBox closes nothing (the search stays, so does the sheet)
				TC.Open({ Key = "maple_fox" })
				KC.advance(0.4)
				H.click(H.find("ChangeButton"))
				local search = RedoGeom.find(H.sheetWin(), "Search")
				T.check(PP.IsOpen() and search ~= nil, "train wiring: (typing) the sheet and its Search box are up")
				H.escTyping(search, "release")
				T.check(PP.IsOpen() and TC.IsOpen(), "train wiring: Escape that lets go of the Search box (released just before) closes nothing")
				H.escTyping(search, "focused")
				T.check(PP.IsOpen() and TC.IsOpen(), "train wiring: ...nor while a TextBox still has focus")
				H.esc()
				T.check(not PP.IsOpen() and TC.IsOpen(), "train wiring: ...the next Escape closes the sheet as before")
				H.click(H.part("Speed", "Action"))
				T.check(H.shown(H.confirm()), "train wiring: (typing) the confirm is up")
				H.escTyping(search, "focused")
				T.check(H.shown(H.confirm()) and TC.IsOpen(), "train wiring: ...Escape while typing in the chat keeps the confirm")
				H.esc()
				T.check(not H.shown(H.confirm()) and TC.IsOpen(), "train wiring: ...a plain Escape closes it")
				H.closeAll()
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
					if sz[3] then
						-- (review fix, spec 5.5) cash short on the small cards: TRAIN greyed with the price in red INSIDE it
						H.setCash(100)
						KC.advance(0.6)
						local b = H.part("Speed", "Action")
						local txt = H.text(b)
						local red = '<font color="#ff6e6e">$'
						T.check(TC.SkillState("Speed") == "Short" and H.disabled(b) and b.RichText == true and txt:find("TRAIN", 1, true) == 1,
							label .. ": (phone) cash short: TRAIN greyed out", txt)
						T.check(txt:find("$", 1, true) == nil or txt:find(red, 1, true) ~= nil, label .. ": ...its price in red (C.Bad)", txt)
						if sz[1] == 844 then
							T.check(txt:find(red, 1, true) ~= nil, label .. ": ...the price fits in the button at 844x390", txt)
						end
						RedoGeom.check(win, label .. " (cash short)", { NoOverlap = NAMES })
						H.setCash(250000)
						KC.advance(0.6)
						txt = H.text(H.part("Speed", "Action"))
						T.check(txt:find("<font", 1, true) == nil and txt:find("TRAIN", 1, true) == 1, label .. ": ...affordable again: no red price", txt)
					end
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
			-- (Task 8) the five mats sit in their band, apart and clear of the pet card and the skills
			H.matsApart(label .. " (mats)")
		end)
	end)

	------------------------------------------------------------------------------------------------
	-- Task 8: the mats row
	local DOT = "\194\183"
	local MATS = { "Mat1", "Mat2", "Mat3", "Mat4", "Mat5" }
	local MAT_NAMES = {
		"Mat1", "Mat2", "Mat3", "Mat4", "Mat5", "PetCard", "PetName", "PetLevel", "PrevButton", "ChangeButton", "NextButton",
		"Skill_Speed", "Skill_Physique", "Skill_Ability", "Skill_Defense", "CloseButton", "SpotsChip",
	}
	function H.mat(i)
		return H.find("Mat" .. i)
	end
	-- "Job,Pending,Job,Locked,Locked" of the window's mats
	function H.matStates()
		local out = {}
		for i = 1, 5 do
			local m = H.mat(i)
			out[i] = tostring(m and m:GetAttribute("State"))
		end
		return table.concat(out, ",")
	end
	-- every shown text under mat i, joined with "|"
	function H.matText(i)
		local m = H.mat(i)
		local out = {}
		for _, d in ipairs(m and m:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and KC.isShown(d) then
				out[#out + 1] = d.Text
			end
		end
		return table.concat(out, "|")
	end
	function H.has(text, part)
		return tostring(text):find(part, 1, true) ~= nil
	end
	-- the five mats inside the band, apart from each other and from the pet card and the skills
	function H.matsApart(label)
		local win = H.win()
		RedoGeom.check(win, label, { NoOverlap = MAT_NAMES })
		local band = H.find("Mats")
		local bp, bs = band.AbsolutePosition, band.AbsoluteSize
		local out = {}
		for i = 1, 5 do
			local m = H.mat(i)
			local p, s = m.AbsolutePosition, m.AbsoluteSize
			if p.X < bp.X - 0.5 or p.Y < bp.Y - 0.5 or p.X + s.X > bp.X + bs.X + 0.5 or p.Y + s.Y > bp.Y + bs.Y + 0.5 then
				out[#out + 1] = RedoGeom.desc(m)
			end
		end
		T.check(#out == 0, label .. ": every mat lies inside the Mats band", RedoGeom.desc(band) .. " / " .. table.concat(out, "; "))
	end
	-- the home tier that first allows Training Place level lv (the Home window's "Needs the ..." house)
	function H.houseFor(lv)
		local TCat = H.req("shared/TycoonCatalog")
		local caps = TCat.Get("Gym").TierCaps
		for _, tier in ipairs(TCat.HouseTiers) do
			if (caps[tier.Id] or 0) >= lv then
				return tier.Name
			end
		end
		return nil
	end

	S.client_train_mats = guarded("client_train_mats", function()
		-- the pure function
		RedoGeom.at(1920, 1080, false, "train mats pure", function()
			H.with("client_train_mats (pure)", nil, function(TC)
				if not T.check(type(TC.Mats) == "function", "train mats: TrainController.Mats(home, growthMap, selectedKey) exists") then
					return
				end
				local now = os.time()
				local function job(slot, inSec, stat)
					return { Evo = 0, Speed = 0, Physique = 0, Ability = 0, Defense = 0, Job = { Stat = stat or "Speed", Ends = now + (inSec or 100), Rank = 1, Slot = slot } }
				end
				local function home(gym, house)
					return { Stations = { Gym = gym, House = house } }
				end
				local function states(m)
					local out = {}
					for i = 1, 5 do
						out[i] = tostring(m[i] and m[i].State)
					end
					return table.concat(out, ",")
				end
				local function keys(m)
					local out = {}
					for i = 1, 5 do
						out[i] = tostring(m[i] and m[i].Key)
					end
					return table.concat(out, ",")
				end
				local map = { a = job(1), b = job(3) }
				local m = TC.Mats(home(3), map, nil)
				T.check(type(m) == "table" and #m == 5, "train mats pure: five mats always", type(m) == "table" and tostring(#m) or type(m))
				T.eq(states(m), "Job,Add,Job,Locked,Locked", "train mats pure: slots 3, jobs on Slot 1 and 3 -> Job, Add, Job, Locked, Locked")
				T.check(m[1].Key == "a" and m[3].Key == "b" and m[1].Job == map.a.Job and m[3].Job == map.b.Job and m[2].Key == nil,
					"train mats pure: ...each job on its own mat, with its Job", keys(m))
				T.check(m[4].Unlock == 4 and m[5].Unlock == 5 and m[1].Unlock == nil, "train mats pure: ...the locked mats say the level that opens them",
					tostring(m[4].Unlock) .. " / " .. tostring(m[5].Unlock))
				local badge = false
				for i = 1, 5 do
					badge = badge or m[i].LockBadge == true
				end
				T.check(not badge, "train mats pure: ...no lock badge")
				map.c = { Evo = 0, Speed = 2 }
				m = TC.Mats(home(3), map, "c")
				T.check(states(m) == "Job,Pending,Job,Locked,Locked" and m[2].Key == "c" and m[2].Job == nil,
					"train mats pure: a selected free pet -> mat 2 'Pending' with that pet", states(m) .. " " .. keys(m))
				m = TC.Mats(home(3), { a = job(1) }, "fresh_pet")
				T.check(states(m) == "Job,Pending,Add,Locked,Locked" and m[2].Key == "fresh_pet",
					"train mats pure: a selected pet with no growth entry yet is pending too", states(m) .. " " .. keys(m))
				m = TC.Mats(home(3), { a = job(1) }, "a")
				T.eq(states(m), "Job,Add,Add,Locked,Locked", "train mats pure: the selected pet in training: no pending mat")
				for _, slot in ipairs({ 0, false, 2.5, -1, 6, 99 }) do
					local j = job(2)
					local free = job(0)
					free.Job.Slot = slot or nil
					m = TC.Mats(home(3), { a = j, b = free }, nil)
					T.check(states(m) == "Job,Job,Add,Locked,Locked" and m[1].Key == "b" and m[2].Key == "a" and not m[1].LockBadge,
						"train mats pure: a job with no Slot (" .. tostring(slot) .. ") -> the first free mat", states(m) .. " " .. keys(m))
				end
				m = TC.Mats(home(3), { a = job(2, 50), b = job(2, 100) }, nil)
				T.check(states(m) == "Add,Job,Job,Locked,Locked" and m[2].Key == "a" and m[3].Key == "b",
					"train mats pure: two jobs on Slot 2 -> the sooner keeps it, the second on the next free mat", states(m) .. " " .. keys(m))
				m = TC.Mats(home(3), { b = job(2, 100), a = job(2, 50), c = job(3) }, nil)
				T.check(states(m) == "Job,Job,Job,Locked,Locked" and m[1].Key == "b" and m[2].Key == "a" and not m[1].LockBadge,
					"train mats pure: ...the next free OPEN mat, wrapping round (no lock badge)", states(m) .. " " .. keys(m))
				m = TC.Mats(home(3), { a = job(5) }, nil)
				T.check(states(m) == "Add,Add,InUse,Locked,Job" and m[5].Key == "a" and m[5].LockBadge == true and m[5].Unlock == 5,
					"train mats pure: a job on Slot 5 with slots 3 -> mat 5 'Job' with LockBadge; it uses one of the 3 spots, so mat 3 is 'InUse'", states(m) .. " " .. keys(m))
				T.check(m[3].Key == nil and m[3].Job == nil and m[3].LockBadge == false, "train mats pure: ...an 'InUse' mat holds no pet and no badge", keys(m))
				m = TC.Mats(home(3), { a = job(1), b = job(2), c = job(3) }, "d")
				T.eq(states(m), "Job,Job,Job,Locked,Locked", "train mats pure: every spot in use: no pending mat")
				m = TC.Mats(home(2), { a = job(1), b = job(3) }, "d")
				T.check(states(m) == "Job,InUse,Job,Locked,Locked" and m[3].LockBadge == true and m[2].Key == nil,
					"train mats pure: slots 2, a job on closed mat 3: two jobs fill the place, so mat 2 is 'InUse' (no '+ Add a pet', no pending)", states(m))
				-- (review fix) the free spots are slots - jobs, never the empty open mats: the row never offers more than the chip
				m = TC.Mats(home(3), { a = job(1), z = job(5) }, "c")
				T.check(states(m) == "Job,Pending,InUse,Locked,Job" and m[2].Key == "c",
					"train mats pure: slots 3, jobs on mat 1 and closed mat 5, a pet picked: one free spot -> mat 2 'Pending', mat 3 'InUse'", states(m) .. " " .. keys(m))
				m = TC.Mats(home(3), { a = job(1), z = job(5) }, nil)
				T.eq(states(m), "Job,Add,InUse,Locked,Job", "train mats pure: ...no pet picked: mat 2 '+ Add a pet', mat 3 'InUse'")
				m = TC.Mats(home(2), { a = job(3), b = job(4), c = job(5) }, "d")
				T.check(states(m) == "InUse,InUse,Job,Job,Job" and m[3].LockBadge and m[4].LockBadge and m[5].LockBadge,
					"train mats pure: slots 2 (a Prestige), three jobs on closed mats 3-5: both open mats 'InUse', no pending", states(m) .. " " .. keys(m))
				m = TC.Mats(home(5), { a = job(2) }, nil)
				T.eq(states(m), "Add,Job,Add,Add,Add", "train mats pure: no job on a closed mat: every empty open mat stays '+ Add a pet'")
				m = TC.Mats({ Stations = {} }, {}, "d")
				T.check(states(m) == "Locked,Locked,Locked,Locked,Locked" and m[1].Unlock == 1 and m[5].Unlock == 5,
					"train mats pure: no Training Place: five locked mats (Lv 1..5)", states(m))
				local ok, res = pcall(TC.Mats, nil, nil, nil)
				T.check(ok and type(res) == "table" and states(res) == "Locked,Locked,Locked,Locked,Locked", "train mats pure: junk arguments do not error",
					ok and states(res) or tostring(res))
				ok, res = pcall(TC.Mats, home(5), { x = "junk", y = { Job = "junk" }, z = { Job = { Slot = 2 } } }, nil)
				T.check(ok and type(res) == "table" and res[2].State == "Job" and res[2].Key == "z" and res[1].State == "Add",
					"train mats pure: junk growth entries are skipped", ok and states(res) or tostring(res))
				m = TC.Mats(home(5), {}, nil)
				T.eq(states(m), "Add,Add,Add,Add,Add", "train mats pure: Lv 5: five open mats")
			end)
		end)

		-- the window at 1920x1080 and on a landscape phone
		local sizes = { { 1920, 1080, false }, { 844, 390, true } }
		for _, sz in ipairs(sizes) do
			local pc = sz[1] == 1920
			local label = fmt("train mats %dx%d", sz[1], sz[2])
			local fixture = { Extra = { { "honey_bunny", "Defense", 3, 200 } }, House = 3 }
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				H.with(label, fixture, function(TC, PP)
					TC.Open({ Key = "maple_fox" })
					KC.advance(0.6)
					local band = H.find("Mats")
					T.check(band ~= nil and H.shown(band), label .. ": the Mats band is shown")
					local all = true
					for i = 1, 5 do
						local m = H.mat(i)
						if not (m and H.shown(m) and m.Parent == band) then
							all = false
						end
					end
					if not T.check(all, label .. ": Mat1..Mat5 shown in the band") then
						return
					end
					T.eq(H.matStates(), "Job,Pending,Job,Locked,Locked", label .. ": two jobs + the pending pet")
					T.check(H.mat(1):GetAttribute("Key") == TRAINING and H.mat(2):GetAttribute("Key") == "maple_fox" and H.mat(3):GetAttribute("Key") == "honey_bunny"
						and H.mat(4):GetAttribute("Key") == nil, label .. ": ...each mat's Key")
					T.check(H.mat(5):GetAttribute("LockBadge") == false and H.mat(1):GetAttribute("LockBadge") == false, label .. ": ...no lock badge")
					T.eq(H.text(H.find("SpotsChip")), pc and "Training spots: 2 / 3 in use" or "2 / 3 spots", label .. ": the chip counts both jobs")
					-- the mats' texts
					local t1, t2, t4 = H.matText(1), H.matText(2), H.matText(4)
					T.check(H.has(t1, "Tabby") and H.has(t1, " left"), label .. ": a job mat shows the pet and its time left", t1)
					if pc then
						T.check(H.has(t1, "Storm Tabby") and H.has(t1, "Physique " .. DOT .. " Rank " .. JOB.Rank), label .. ": (PC) ...and 'Physique " .. DOT .. " Rank 4'", t1)
						T.check(H.has(t2, "Maple Fox") and H.has(t2, "Pick a skill below"), label .. ": (PC) the pending mat: 'Pick a skill below'", t2)
						T.check(H.has(t4, "Training Place Lv 4"), label .. ": (PC) a locked mat: 'Training Place Lv 4'", t4)
					else
						T.check(H.has(t2, "Pick a skill") and not H.has(t2, "below"), label .. ": (phone) the pending mat: 'Pick a skill'", t2)
						T.check(H.has(t4, "Lv 4") and not H.has(t4, "Training Place"), label .. ": (phone) a locked mat: 'Lv 4'", t4)
					end
					-- sizes (spec 5.5)
					local s1 = H.mat(1).AbsoluteSize
					if pc then
						T.check(s1.X >= 250 and s1.X <= 290 and math.abs(s1.Y - band.AbsoluteSize.Y) <= 1 and math.abs(band.AbsoluteSize.Y - 132) <= 1,
							label .. ": (PC) mats about 268 wide in a 132 band", RedoGeom.desc(H.mat(1)) .. " / " .. RedoGeom.desc(band))
					else
						local gap = H.mat(2).AbsolutePosition.X - (H.mat(1).AbsolutePosition.X + s1.X)
						T.check(math.abs(s1.X - 152) <= 1 and math.abs(s1.Y - 52) <= 1 and math.abs(gap - 8) <= 1,
							label .. ": (phone) mats 152 x 52, 8 px apart", RedoGeom.desc(H.mat(1)) .. " gap " .. tostring(gap))
					end
					-- the timer counts down while open
					local before = t1
					KC.advance(2.1)
					T.check(H.matText(1) ~= before, label .. ": a job mat's timer counts down", before .. " -> " .. H.matText(1))
					-- the geometry
					H.matsApart(label)
					-- a job mat selects its pet
					H.click(H.mat(3))
					T.check(TC.Key() == "honey_bunny" and H.skill("Defense"):GetAttribute("State") == "Training" and not PP.IsOpen(),
						label .. ": tapping a job mat selects that pet; its skill card turns 'Training'", tostring(TC.Key()) .. " " .. H.states())
					T.check(H.mat(3):GetAttribute("Selected") == true and H.mat(1):GetAttribute("Selected") ~= true, label .. ": ...that mat is marked selected")
					T.eq(H.matStates(), "Job,Add,Job,Locked,Locked", label .. ": ...a pet in training is not pending: mat 2 reads '+ Add a pet'")
					T.check(H.has(H.matText(2), "Add a pet") or H.has(H.matText(2), "Add"), label .. ": ...'+ Add a pet'", H.matText(2))
					-- "+ Add a pet" opens the sheet
					H.click(H.mat(2))
					T.check(PP.IsOpen(), label .. ": tapping '+ Add a pet' opens the sheet")
					PP.Close()
					KC.advance(0.3)
					-- a locked mat only says how to open it
					local mark = #Mock.RemoteLog
					H.click(H.mat(5))
					local hint = H.find("HintLine")
					local house = H.houseFor(5)
					T.check(house ~= nil and H.houseFor(4) ~= house, label .. ": (setup) the Manor allows Lv 4, not Lv 5")
					T.check(hint and H.shown(hint) and hint.Text == "Upgrade your Training Place to Lv 5 to open this spot. Needs the " .. tostring(house) .. ".",
						label .. ": a locked mat over the house's cap: the HintLine says the level and the house", H.text(hint))
					T.check(TC.Key() == "honey_bunny" and not PP.IsOpen() and #KC.serverCalls("PetCare", mark) == 0 and not H.shown(H.confirm()),
						label .. ": ...and nothing else happens")
					H.click(H.mat(4))
					T.eq(H.text(hint), "Upgrade your Training Place to Lv 4 to open this spot.", label .. ": a locked mat the house allows: the level only")
					-- a job ending: its mat goes back to '+ Add a pet' (or pending), the chip drops
					TC.Select("maple_fox")
					KC.advance(0.3)
					H.feed({ Job = false, Extra = fixture.Extra, House = 3 })
					KC.advance(0.3)
					T.eq(H.matStates(), "Pending,Add,Job,Locked,Locked", label .. ": a job ends: its mat frees up (the pending pet moves there)")
					T.eq(H.text(H.find("SpotsChip")), pc and "Training spots: 1 / 3 in use" or "1 / 3 spots", label .. ": ...the chip count drops")
					-- the slots change while open (Review Focus 5)
					H.feed({ Gym = 4, Extra = fixture.Extra, House = 3 })
					KC.advance(0.3)
					T.eq(H.matStates(), "Job,Pending,Job,Add,Locked", label .. ": the Training Place reaches Lv 4: Mat4 opens at once")
					H.feed({ Gym = 2, Extra = fixture.Extra, House = 3 })
					KC.advance(0.3)
					T.check(H.mat(3):GetAttribute("State") == "Job" and H.mat(3):GetAttribute("LockBadge") == true and H.mat(3):GetAttribute("Key") == "honey_bunny",
						label .. ": a Prestige-like snapshot (2 spots, a job on Slot 3): Mat3 keeps its job with a lock badge", H.matStates())
					local badgeShown = false
					for _, d in ipairs(H.mat(3):GetDescendants()) do
						if d.Name == "LockBadge" and KC.isShown(d) then
							badgeShown = true
						end
					end
					T.check(badgeShown, label .. ": ...the lock badge is drawn")
					T.eq(H.matStates(), "Job,InUse,Job,Locked,Locked", label .. ": ...two jobs fill 2 spots: no pending mat, mat 2 'InUse' (no '+ Add a pet')")
					T.eq(H.text(H.find("SpotsChip")), pc and "Training spots: 2 / 2 in use" or "2 / 2 spots", label .. ": ...the chip reads 2 / 2")
					local t2u = H.matText(2)
					T.check(H.has(t2u:lower(), "in use") and not H.has(t2u, "Add"), label .. ": ...the 'InUse' mat reads 'In use', never 'Add a pet'", t2u)
					if pc then
						T.check(H.has(t2u, "Spot in use"), label .. ": (PC) ...'Spot in use'", t2u)
					end
					mark = #Mock.RemoteLog
					H.click(H.mat(2))
					T.check(not PP.IsOpen() and #KC.serverCalls("PetCare", mark) == 0 and not H.shown(H.confirm()),
						label .. ": tapping the 'InUse' mat opens no sheet (every spot is taken)")
					T.eq(H.text(H.find("HintLine")), "In use by a pet on a closed spot. Free again when that pet is done.",
						label .. ": ...the HintLine says why")
					H.matsApart(label .. " (lock badge)")
					-- no Training Place: five locked mats, the build text in the body
					H.feed({ Gym = 0, Job = false })
					KC.advance(0.3)
					T.eq(H.matStates(), "Locked,Locked,Locked,Locked,Locked", label .. ": no Training Place: five locked mats")
					T.check(H.shownText(H.win(), "Build the Training Place at home first. Training makes pets tougher in battles!") ~= nil,
						label .. ": ...the body says how to build it")
					H.click(H.mat(1))
					T.eq(H.text(H.find("HintLine")), "Build the Training Place at home to open this spot.", label .. ": ...the first mat says to build it")
					-- (the build text takes the skills' place: it reads, stays on the screen and clear of the mats and the pet)
					RedoGeom.check(H.win(), label .. " (no Training Place)", {
						NoOverlap = { "Mat1", "Mat2", "Mat3", "Mat4", "Mat5", "PetCard", "PetName", "PrevButton", "ChangeButton", "NextButton", "Empty", "CloseButton" },
					})
				end)
			end)
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
