-- smoke_redo_picker.lua: the shared full-screen pet picker sheet (docs/superpowers/specs/2026-11-06-window-redo-design.md 5.1,
-- 5.2; plan docs/superpowers/plans/2026-11-06-window-redo.md Task 6). Client and phone worlds only (client_files, loaded after
-- smoke_redo_geom.lua, whose RedoGeom it uses):
--   client_picker_pure       PetPicker.Entries per context (Train: every key with the hybrid; Upgrade: no hybrid, no Rainbow;
--                            Mix: no hybrid), the entry fields, the default orders (Train: training soonest first, the team in
--                            slot order, the rest by rarity then level; Upgrade: Ready first, copies, rarity, name; Mix: rarity
--                            then level), the other sorts, every filter, the case-insensitive plain search (Lua pattern
--                            characters never error or match everything), the training blocks (Upgrade: the key or its
--                            next-finish key training; Mix: the key training) and spec.Blocked on its card
--   client_picker_ui         (1920x1080) Open / title / Selected / Pick order (closed before OnPick, OnClose(true)) / blocked
--                            cards / Upgrade's dimmed but pickable 2-copy card and the green Ready badge / search + "No pets
--                            match." + Clear / the sort button's cycle kept per context / viewports only in the grid's visible
--                            window (and after scrolling) / the Training chip's live countdown / a key that leaves the
--                            collection while open (Review Focus 1) / the screen changing under the open sheet (Review Focus
--                            3) / X = OnClose(false)
--   client_picker_layouts    Train, Upgrade and Mix at 844x390 (touch), 1280x720 and 1920x1080: RedoGeom.check (text >= 14 px,
--                            targets >= 44 px, on the screen under the top bar, the top row never overlapping); the PC chips
--                            row rule (Train's five chips on row 2 at 1080p, Upgrade's three beside the search); 6 cards a row
--                            on the phone with Train's first three chips, 7 at 1080p
--   client_picker_portrait   (phone world, 390x844 touch) the sheet fits, RedoGeom.check passes, the cards wrap
-- Fixture: 30 keys (the mock's pets and more, so the 1080p grid scrolls): two training jobs with different ends (one on a Golden
-- copy whose Normal copy is then blocked in Upgrade), a 3-pet active team (one of them training), a hybrid, a Golden and a
-- Rainbow copy, copies 5 / 4 / 3 / 2 / 1. Every scenario puts the profile it found back and closes the sheet.
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

	-- key, level, copies, stored evolution
	local FIX = {
		{ "storm_tabby", 22, 1 }, -- Rare, training (ends first), team slot 3
		{ "sleepy_owl@Golden", 9, 1 }, -- Uncommon Golden, training (ends second)
		{ "sleepy_owl", 10, 1 }, -- Upgrade: blocked, its next finish (the Golden copy) is training
		{ "aurora_fox", 34, 1, 1 }, -- Epic, team slot 1, evolved
		{ "ember_phoenix", 41, 1, 1 }, -- Legendary, team slot 2, evolved
		{ "maple_fox", 12, 5 },
		{ "maple_fox@Rainbow", 3, 1 },
		{ "pebble_pup", 8, 4 },
		{ "honey_bunny", 20, 3 },
		{ "mochi_slime", 15, 2 },
		{ "bubble_axolotl", 6, 2 },
		{ "pip_penguin", 5, 2 },
		{ "stormfang", 11, 1 },
		{ "twilight_dragon", 33, 1 },
		{ "moonlit_owl", 27, 1 },
		{ "candy_unicorn", 25, 1 },
		{ "cherry_panda", 18, 1 },
		{ "biscuit_bear", 14, 1 },
		{ "hyb:h1", 13, 1 },
		{ "mallow_kitten", 7, 1 },
		{ "puddle_frog", 4, 1 },
		{ "bamboo_panda", 19, 1 },
		{ "waffle_corgi", 16, 1 },
		{ "blossom_bunny", 21, 1 },
		{ "shroomie_frog", 17, 1 },
		{ "frostling_penguin", 23, 1 },
		{ "nebula_axolotl", 24, 1 },
		{ "sunbeam_bear", 30, 1 },
		{ "cloudy_dragon", 28, 1 },
		{ "starlight_unicorn", 26, 1 },
	}
	local JOBS = {
		storm_tabby = { Stat = "Speed", In = 190, Slot = 1 },
		["sleepy_owl@Golden"] = { Stat = "Physique", In = 400, Slot = 2 },
	}
	local TEAM = { "aurora_fox", "ember_phoenix", "storm_tabby" }
	local LEVEL, COPIES = {}, {}
	for _, f in ipairs(FIX) do
		LEVEL[f[1]] = f[2]
		COPIES[f[1]] = f[3]
	end

	function H.req(path)
		local root, rest = path:match("^(%a+)/(.+)$")
		local inst = Mock.GetPath(ROOTS[root] .. "/" .. rest)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end
	function H.picker()
		return H.req("client/UI/PetPicker")
	end
	function H.state()
		return (KC.M and KC.M.State) or H.req("client/State")
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.win()
		local gui = H.pg():FindFirstChild("NimbusPetPicker")
		return gui and gui:FindFirstChild("Window_PetPicker", true)
	end
	function H.find(name)
		return RedoGeom.find(H.win(), name)
	end
	function H.card(key)
		return H.find("Card_" .. key)
	end
	function H.shown(o)
		return o ~= nil and KC.isShown(o)
	end
	function H.keysText(list)
		local out = {}
		for i, k in ipairs(list or {}) do
			out[i] = tostring(type(k) == "table" and k.Key or k)
		end
		return table.concat(out, ",")
	end
	function H.keysOf(entries)
		local out = {}
		for i, e in ipairs(entries) do
			out[i] = e.Key
		end
		return out
	end
	function H.same(a, b)
		if #a ~= #b then
			return false
		end
		for i = 1, #a do
			if a[i] ~= b[i] then
				return false
			end
		end
		return true
	end
	function H.setOf(list)
		local out = {}
		for _, k in ipairs(list) do
			out[k] = true
		end
		return out
	end
	function H.sameSet(list, wanted)
		local a = H.setOf(list)
		local n = 0
		for k in pairs(wanted) do
			n = n + 1
			if not a[k] then
				return false
			end
		end
		return n == #list
	end

	-- a ProfileSync snapshot of the fixture; drop = { [key] = true } leaves keys out (a pet that left the collection)
	function H.snapshot(drop)
		drop = drop or {}
		local pets, tiers, levels, discovered, growth, hybrids = {}, {}, {}, {}, {}, {}
		for _, f in ipairs(FIX) do
			local key, level, copies, evo = f[1], f[2], f[3], f[4]
			if not drop[key] then
				local base, tier = key:match("^(.-)@(%a+)$")
				if key:sub(1, 4) == "hyb:" then
					hybrids[key:sub(5)] = { Body = "maple_fox", Style = "storm_tabby", Elements = { "Flame", "Storm" }, Name = "Foxby", Rarity = "Rare", Tier = "Normal", Seed = 7 }
				elseif tier then
					tiers[base] = tiers[base] or {}
					tiers[base][tier] = copies
					discovered[base] = true
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
		local now = os.time()
		local busy = {}
		for key, job in pairs(JOBS) do
			if not drop[key] then
				growth[key] = growth[key] or {}
				growth[key].Job = { Stat = job.Stat, Ends = now + job.In, Rank = 1, Slot = job.Slot, From = "Free", Paid = 0 }
				busy[key] = "Training"
			end
		end
		local preset, equipped = {}, {}
		for _, key in ipairs(TEAM) do
			if not drop[key] then
				preset[#preset + 1] = key
				if not busy[key] then
					equipped[#equipped + 1] = key
				end
			end
		end
		return {
			Tokens = 900, Pets = pets, Equipped = equipped, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = discovered, IndexClaimed = {},
			Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 1000, Gems = 0,
			Home = { Level = 5, Prestige = 0, Stations = { Garden = 1 }, Garden = {}, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = tiers, Hybrids = hybrids, PetLevels = levels,
			Teams = { Presets = { preset, {}, {} }, Active = 1, Slots = 3, Busy = busy },
			Battle = { Trophies = 0, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			PetGrowth = growth,
			Ring = { Best = 0, Runs = 0 },
		}
	end
	function H.feed(drop)
		KC.toClient("ProfileSync", H.snapshot(drop))
		KC.advance(0.1)
	end
	-- runs fn with the fixture synced; puts the profile it found back and closes the sheet after
	function H.with(label, fn)
		local PP = H.picker()
		if not T.check(type(PP) == "table" and type(PP.Open) == "function", label .. ": client/UI/PetPicker loads") then
			return
		end
		local State = H.state()
		local before = State and State.Get and State.Get() or nil
		H.feed()
		local ok, err = pcall(fn, PP, State)
		if not ok then
			T.fail(label .. ": error", tostring(err))
		end
		pcall(PP.Close)
		if before then
			KC.toClient("ProfileSync", before)
		end
		KC.advance(0.2)
		KC.flushErrors(label)
	end

	-- the fixture's own numbers (independent of the module)
	function H.rarityOrder(State, key)
		local def = State.DefOf(key)
		local Config = KC.env()
		for _, r in ipairs(Config.Rarities) do
			if def and r.Id == def.Rarity then
				return r.Order
			end
		end
		return 1
	end
	function H.nameOf(State, key)
		local def = State.DefOf(key)
		return def and tostring(def.DisplayName or def.Name or key) or key
	end
	function H.isHybrid(key)
		return key:sub(1, 4) == "hyb:"
	end
	function H.tierOf(key)
		return key:match("@(%a+)$") or "Normal"
	end
	-- by rarity (high first), then level (high first), then name, then key
	function H.byRarity(State)
		return function(a, b)
			local ra, rb = H.rarityOrder(State, a), H.rarityOrder(State, b)
			if ra ~= rb then
				return ra > rb
			end
			if LEVEL[a] ~= LEVEL[b] then
				return LEVEL[a] > LEVEL[b]
			end
			return a < b
		end
	end
	function H.allKeys(filter)
		local out = {}
		for _, f in ipairs(FIX) do
			if not filter or filter(f[1]) then
				out[#out + 1] = f[1]
			end
		end
		return out
	end
	-- the cards in one row: the shown cards whose top equals the first shown card's top
	function H.perRow(PP)
		local first = H.card(PP.Shown()[1])
		local n = 0
		for _, key in ipairs(PP.Shown()) do
			local c = H.card(key)
			if c and first and math.abs(c.AbsolutePosition.Y - first.AbsolutePosition.Y) < 1 then
				n = n + 1
			end
		end
		return n
	end
	function H.clickName(name)
		local b = H.find(name)
		if T.check(b ~= nil, "picker: " .. name .. " exists") then
			Mock.Click(b)
		end
		KC.advance(0.1)
		return b
	end

	S.client_picker_pure = guarded("client_picker_pure", function()
		H.with("client_picker_pure", function(PP, State)
			-- who is listed
			local train = PP.Entries("Train")
			T.check(H.sameSet(H.keysOf(train), H.setOf(H.allKeys())), "picker pure: Entries('Train') = every owned key, the hybrid too", H.keysText(train))
			local up = PP.Entries("Upgrade")
			T.check(H.sameSet(H.keysOf(up), H.setOf(H.allKeys(function(k)
				return not H.isHybrid(k) and H.tierOf(k) ~= "Rainbow"
			end))), "picker pure: Entries('Upgrade') = no hybrid, no Rainbow", H.keysText(up))
			local mix = PP.Entries("Mix")
			T.check(H.sameSet(H.keysOf(mix), H.setOf(H.allKeys(function(k)
				return not H.isHybrid(k)
			end))), "picker pure: Entries('Mix') = no hybrid", H.keysText(mix))
			T.check(type(PP.Entries("Nope")) == "table" and #PP.Entries("Nope") == 0, "picker pure: an unknown context lists nothing")

			-- the entry fields
			local byKey = {}
			for _, e in ipairs(train) do
				byKey[e.Key] = e
			end
			local tabby, aurora, hyb = byKey.storm_tabby, byKey.aurora_fox, byKey["hyb:h1"]
			T.check(tabby and tabby.Job and tabby.Job.Stat == "Speed" and tabby.Job.Slot == 1 and type(tabby.Job.Ends) == "number" and tabby.Team == 3,
				"picker pure: a training team pet's entry has Job { Stat, Ends, Slot } and Team = its slot", tabby and fmt("%s %s", tostring(tabby.Team), tostring(tabby.Job and tabby.Job.Slot)) or "missing")
			T.check(aurora and aurora.Team == 1 and aurora.Job == nil and aurora.Level == 34 and aurora.Stage == State.PetStage("aurora_fox") and aurora.Rarity == "Epic"
				and aurora.RarityOrder == H.rarityOrder(State, "aurora_fox") and aurora.Copies == 1 and aurora.Name == "Aurora Fox" and aurora.Def ~= nil and aurora.Hybrid == false,
				"picker pure: Key, Def, Name, Level, Stage, Rarity, RarityOrder, Copies, Team, Hybrid", aurora and fmt("%s L%s s%s %s", tostring(aurora.Name), tostring(aurora.Level), tostring(aurora.Stage), tostring(aurora.Rarity)) or "missing")
			T.check(hyb and hyb.Hybrid == true and hyb.Name == H.nameOf(State, "hyb:h1") and hyb.Team == nil, "picker pure: the hybrid's entry", hyb and tostring(hyb.Name) or "missing")
			T.check(byKey.maple_fox and byKey.maple_fox.Copies == 5 and byKey.maple_fox.Blocked == nil, "picker pure: Copies = every copy (x5)")
			local trainBlocked = {}
			for _, e in ipairs(train) do
				if e.Blocked then
					trainBlocked[#trainBlocked + 1] = e.Key
				end
			end
			T.check(#trainBlocked == 0, "picker pure: nothing is blocked in Train", table.concat(trainBlocked, ","))

			-- Train's default order: training (soonest first), the team in slot order, the rest by rarity then level
			local want = { "storm_tabby", "sleepy_owl@Golden", "aurora_fox", "ember_phoenix" }
			local head = H.setOf(want)
			local rest = H.allKeys(function(k)
				return not head[k]
			end)
			table.sort(rest, H.byRarity(State))
			for _, k in ipairs(rest) do
				want[#want + 1] = k
			end
			local got = H.keysOf(PP.Sorted("Train", train, "Default", "All", ""))
			T.check(H.same(got, want), "picker pure: Train default = training (soonest first), team (slot order), rest (rarity, level)", H.keysText(got))
			got = H.keysOf(PP.Sorted("Train", train, nil, nil, nil))
			T.check(H.same(got, want), "picker pure: nil sort / filter / query = the default, all, no search")
			-- Level / Rarity / Name
			local lv = H.keysOf(PP.Sorted("Train", train, "Level", "All", ""))
			local okLevel = #lv == #train
			for i = 2, #lv do
				okLevel = okLevel and LEVEL[lv[i - 1]] >= LEVEL[lv[i]]
			end
			T.check(okLevel and lv[1] == "ember_phoenix", "picker pure: Train 'Level' = level high to low", H.keysText(lv))
			local ra = H.keysOf(PP.Sorted("Train", train, "Rarity", "All", ""))
			local okRarity = #ra == #train
			for i = 2, #ra do
				okRarity = okRarity and H.rarityOrder(State, ra[i - 1]) >= H.rarityOrder(State, ra[i])
			end
			T.check(okRarity, "picker pure: Train 'Rarity' = rarity high to low", H.keysText(ra))
			local nm = PP.Sorted("Train", train, "Name", "All", "")
			local okName = #nm == #train
			for i = 2, #nm do
				okName = okName and nm[i - 1].Name:lower() <= nm[i].Name:lower()
			end
			T.check(okName, "picker pure: Train 'Name' = A to Z", H.keysText(nm))

			-- Upgrade's default: Ready first, then copies, then rarity, then name
			local upSorted = PP.Sorted("Upgrade", up, "Default", "All", "")
			local okUp = #upSorted == #up
			for i = 2, #upSorted do
				local a, b = upSorted[i - 1], upSorted[i]
				local ka = { (a.Copies >= 3) and 1 or 0, a.Copies, H.rarityOrder(State, a.Key) }
				local kb = { (b.Copies >= 3) and 1 or 0, b.Copies, H.rarityOrder(State, b.Key) }
				if ka[1] ~= kb[1] then
					okUp = okUp and ka[1] > kb[1]
				elseif ka[2] ~= kb[2] then
					okUp = okUp and ka[2] > kb[2]
				elseif ka[3] ~= kb[3] then
					okUp = okUp and ka[3] > kb[3]
				else
					okUp = okUp and a.Name:lower() <= b.Name:lower()
				end
			end
			T.check(okUp and upSorted[1].Key == "maple_fox" and upSorted[2].Key == "pebble_pup" and upSorted[3].Key == "honey_bunny",
				"picker pure: Upgrade default = Ready first (x5, x4, x3), then copies, rarity, name", H.keysText(upSorted))
			local readyFlags = {}
			for _, e in ipairs(up) do
				if e.Ready ~= (COPIES[e.Key] >= 3) then
					readyFlags[#readyFlags + 1] = e.Key
				end
			end
			T.check(#readyFlags == 0, "picker pure: Ready = copies >= 3 (Upgrade)", table.concat(readyFlags, ","))
			-- Mix's default: rarity, then level
			local mixWant = H.keysOf(mix)
			table.sort(mixWant, H.byRarity(State))
			got = H.keysOf(PP.Sorted("Mix", mix, "Default", "All", ""))
			T.check(H.same(got, mixWant), "picker pure: Mix default = rarity, then level", H.keysText(got))
			got = H.keysOf(PP.Sorted("Mix", mix, "Team", "All", ""))
			T.check(got[1] == "aurora_fox" and got[2] == "ember_phoenix" and got[3] == "storm_tabby", "picker pure: Mix 'Team first' = the team in slot order first", H.keysText(got))

			-- the sorts and filters tables
			local function ids(list)
				local out = {}
				for i, it in ipairs(list or {}) do
					out[i] = tostring(it.Id) .. "=" .. tostring(it.Label)
				end
				return table.concat(out, ",")
			end
			T.eq(ids(PP.Sorts.Train), "Default=Training first,Level=Level,Rarity=Rarity,Name=Name", "picker pure: Sorts.Train")
			T.eq(ids(PP.Sorts.Upgrade), "Default=Ready first,Rarity=Rarity,Level=Level,Name=Name", "picker pure: Sorts.Upgrade")
			T.eq(ids(PP.Sorts.Mix), "Default=Rarity,Level=Level,Name=Name,Team=Team first", "picker pure: Sorts.Mix")
			T.eq(ids(PP.Filters.Train), "All=All,Team=Team,Training=Training,Rare=Rare and up,Epic=Epic and up", "picker pure: Filters.Train")
			T.eq(ids(PP.Filters.Upgrade), "All=All,Ready=Ready,Team=Team", "picker pure: Filters.Upgrade")
			T.eq(ids(PP.Filters.Mix), "All=All,Team=Team,Rare=Rare and up", "picker pure: Filters.Mix")

			-- filters
			got = H.keysOf(PP.Sorted("Train", train, "Default", "Team", ""))
			T.check(H.sameSet(got, H.setOf(TEAM)), "picker pure: Train 'Team' = the 3 team keys", H.keysText(got))
			got = H.keysOf(PP.Sorted("Train", train, "Default", "Training", ""))
			T.check(H.same(got, { "storm_tabby", "sleepy_owl@Golden" }), "picker pure: Train 'Training' = the 2 jobs (soonest first)", H.keysText(got))
			got = H.keysOf(PP.Sorted("Train", train, "Default", "Rare", ""))
			T.check(H.sameSet(got, H.setOf(H.allKeys(function(k)
				return H.rarityOrder(State, k) >= 3
			end))), "picker pure: Train 'Rare and up'", H.keysText(got))
			got = H.keysOf(PP.Sorted("Train", train, "Default", "Epic", ""))
			T.check(#got > 0 and H.sameSet(got, H.setOf(H.allKeys(function(k)
				return H.rarityOrder(State, k) >= 4
			end))), "picker pure: Train 'Epic and up'", H.keysText(got))
			got = H.keysOf(PP.Sorted("Upgrade", up, "Default", "Ready", ""))
			T.check(H.same(got, { "maple_fox", "pebble_pup", "honey_bunny" }), "picker pure: Upgrade 'Ready' = copies >= 3", H.keysText(got))
			got = H.keysOf(PP.Sorted("Upgrade", up, "Default", "Team", ""))
			T.check(H.sameSet(got, H.setOf(TEAM)), "picker pure: Upgrade 'Team'", H.keysText(got))
			got = H.keysOf(PP.Sorted("Mix", mix, "Default", "Rare", ""))
			T.check(H.sameSet(got, H.setOf(H.allKeys(function(k)
				return not H.isHybrid(k) and H.rarityOrder(State, k) >= 3
			end))), "picker pure: Mix 'Rare and up'", H.keysText(got))

			-- search: case-insensitive plain substring of the name
			local fox = {}
			for _, e in ipairs(train) do
				if e.Name:lower():find("fox", 1, true) then
					fox[e.Key] = true
				end
			end
			got = H.keysOf(PP.Sorted("Train", train, "Default", "All", "fox"))
			T.check(fox.aurora_fox and fox.maple_fox and H.sameSet(got, fox), "picker pure: 'fox' finds Aurora Fox and Maple Fox (and only names with fox)", H.keysText(got))
			got = H.keysOf(PP.Sorted("Train", train, "Default", "All", "  FoX "))
			T.check(H.sameSet(got, fox), "picker pure: the search ignores case and the spaces around it", H.keysText(got))
			-- Review Focus 2: pattern characters are plain text
			for _, q in ipairs({ "%", "%[", ".", "((", "[", "%a", ".*" }) do
				local okQ, res = pcall(PP.Sorted, "Train", train, "Default", "All", q)
				local hits = {}
				if okQ and type(res) == "table" then
					for _, e in ipairs(res) do
						if not e.Name:find(q, 1, true) then
							hits[#hits + 1] = e.Key
						end
					end
				end
				T.check(okQ and type(res) == "table" and #hits == 0 and #res == 0, "picker pure: the search text '" .. q .. "' never errors or matches everything", okQ and (#res .. " shown") or tostring(res))
			end

			-- training blocks
			local upBy, mixBy = {}, {}
			for _, e in ipairs(up) do
				upBy[e.Key] = e
			end
			for _, e in ipairs(mix) do
				mixBy[e.Key] = e
			end
			T.check(upBy.storm_tabby and upBy.storm_tabby.Blocked == "Training", "picker pure: Upgrade blocks a training key")
			T.check(upBy.sleepy_owl and upBy.sleepy_owl.Blocked == "Training", "picker pure: Upgrade blocks a key whose next finish is training")
			T.check(upBy["sleepy_owl@Golden"] and upBy["sleepy_owl@Golden"].Blocked == "Training", "picker pure: ...and the training Golden copy itself")
			T.check(upBy.maple_fox and upBy.maple_fox.Blocked == nil and upBy.cherry_panda and upBy.cherry_panda.Blocked == nil, "picker pure: Upgrade leaves the others pickable")
			T.check(mixBy.storm_tabby and mixBy.storm_tabby.Blocked == "Training" and mixBy.sleepy_owl and mixBy.sleepy_owl.Blocked == nil,
				"picker pure: Mix blocks a training key only")

			-- spec.Blocked shows on its card (merged over the training blocks)
			T.check(PP.Open({ Context = "Mix", Title = "Pick the Style pet", Blocked = { maple_fox = "In Body" } }) == true, "picker pure: Open(Mix) with Blocked")
			KC.advance(0.6)
			local maple = H.card("maple_fox")
			local word = maple and RedoGeom.find(maple, "BlockWord")
			T.check(maple ~= nil and maple:GetAttribute("Blocked") == "In Body" and word ~= nil and H.shown(word) and word.Text == "In Body",
				"picker pure: spec.Blocked = { maple_fox = 'In Body' } shows on that card", maple and tostring(maple:GetAttribute("Blocked")) or "no card")
			T.check(PP.Pick("maple_fox") == false and PP.IsOpen(), "picker pure: ...and it cannot be picked")
			local tabbyCard = H.card("storm_tabby")
			T.check(tabbyCard ~= nil and tabbyCard:GetAttribute("Blocked") == "Training", "picker pure: the training block shows too")
			PP.Close()
			T.check(PP.Open({ Context = "Nope" }) == false and not PP.IsOpen(), "picker pure: Open refuses a spec without a valid Context")
			T.check(PP.Open(nil) == false, "picker pure: ...and no spec")
		end)
	end)

	S.client_picker_ui = guarded("client_picker_ui", function()
		RedoGeom.at(1920, 1080, false, "client_picker_ui", function()
			H.with("client_picker_ui", function(PP, State)
				local picks, closes = {}, {}
				local openAtPick = nil
				local function onPick(key)
					openAtPick = PP.IsOpen()
					picks[#picks + 1] = key
				end
				local function onClose(picked)
					closes[#closes + 1] = picked
				end
				local k1, k2, k3 = "cherry_panda", "aurora_fox", "candy_unicorn"
				T.check(PP.Open({ Context = "Train", Title = "Pick a pet to train", Selected = k2, OnPick = onPick, OnClose = onClose }) == true, "picker ui: Open(Train) -> true")
				KC.advance(0.6)
				local gui = H.pg():FindFirstChild("NimbusPetPicker")
				local win = H.win()
				if not T.check(gui ~= nil and H.shown(win) and PP.IsOpen(), "picker ui: NimbusPetPicker > Window_PetPicker is shown") then
					return
				end
				T.check(gui.DisplayOrder == 24 and gui.IgnoreGuiInset == true, "picker ui: DisplayOrder 24, IgnoreGuiInset", fmt("%s %s", tostring(gui.DisplayOrder), tostring(gui.IgnoreGuiInset)))
				T.check(math.abs(win.AbsoluteSize.X - 1440) <= 2 and math.abs(win.AbsoluteSize.Y - 920) <= 2 and PP.Layout() == "PC", "picker ui: 1440x920 at 1080p, the PC layout",
					fmt("%.0fx%.0f %s", win.AbsoluteSize.X, win.AbsoluteSize.Y, tostring(PP.Layout())))
				T.eq(H.find("Title") and H.find("Title").Text, "PICK A PET TO TRAIN", "picker ui: the title") -- (kit-b U6: a Title-role text reads in capitals)
				T.eq(#PP.Shown(), #PP.Entries("Train"), "picker ui: one card per Train entry")
				T.check(H.card(k2) ~= nil and H.card(k2):GetAttribute("Selected") == true, "picker ui: the Selected pet's card is marked")
				T.check(H.card(k1) ~= nil and H.card(k1):GetAttribute("Selected") ~= true, "picker ui: ...no other")
				T.check(H.same(PP.Shown(), H.keysOf(PP.Sorted("Train", PP.Entries("Train"), "Default", "All", ""))), "picker ui: the cards come in the default Train order")
				-- card contents
				local auroraLv = H.card(k2) and RedoGeom.find(H.card(k2), "Level")
				local stars = string.rep("\226\152\133", State.PetStage(k2))
				T.check(auroraLv ~= nil and auroraLv.Text:find("Lv 34", 1, true) == 1 and (stars == "" or auroraLv.Text:find(stars, 1, true) ~= nil),
					"picker ui: 'Lv 34' with one star per stage", auroraLv and auroraLv.Text or "no Level")
				local badge = H.card(k2) and RedoGeom.find(H.card(k2), "Badge")
				T.check(badge ~= nil and H.shown(badge), "picker ui: a team pet shows the team star badge (Train)")
				local nonTeam = H.card(k1) and RedoGeom.find(H.card(k1), "Badge")
				T.check(nonTeam == nil or not H.shown(nonTeam), "picker ui: ...a pet out of the team has none")
				local rarityWord = H.card(k2) and RedoGeom.find(H.card(k2), "Rarity")
				T.check(rarityWord ~= nil and H.shown(rarityWord) and rarityWord.Text == "Epic", "picker ui: the rarity word under the name (PC)", rarityWord and rarityWord.Text or "none")
				-- the Training chip counts down
				local chip = H.card("storm_tabby") and RedoGeom.find(H.card("storm_tabby"), "TrainChip")
				local before = chip and chip.Text or ""
				KC.advance(1.3)
				local after = chip and chip.Text or ""
				T.check(chip ~= nil and H.shown(chip) and before:find("^Training %d+:%d%d$") ~= nil and before ~= after, "picker ui: the Training chip counts down live", before .. " -> " .. after)
				local noChip = H.card(k1) and RedoGeom.find(H.card(k1), "TrainChip")
				T.check(noChip == nil or not H.shown(noChip), "picker ui: ...only on a training pet")

				-- viewports: only the cards in the grid's visible window hold one (after 60 frames)
				KC.advance(2)
				local grid = H.find("Grid")
				local function viewCheck(label)
					local gb = { y = grid.AbsolutePosition.Y, h = grid.AbsoluteSize.Y }
					local wrong, inView, outView = {}, 0, 0
					for _, key in ipairs(PP.Shown()) do
						local c = H.card(key)
						local top, bottom = c.AbsolutePosition.Y, c.AbsolutePosition.Y + c.AbsoluteSize.Y
						local visible = bottom > gb.y + 0.5 and top < gb.y + gb.h - 0.5
						local has = c:FindFirstChild("PetViewport", true) ~= nil
						if visible then
							inView = inView + 1
						else
							outView = outView + 1
						end
						if has ~= visible then
							wrong[#wrong + 1] = key .. (visible and " (in view, none)" or " (out of view, has one)")
						end
					end
					T.check(#wrong == 0 and inView > 0 and outView > 0, "picker ui: only cards in the visible window hold a viewport (" .. label .. ")",
						fmt("%d in view, %d out; %s", inView, outView, table.concat(wrong, ", ", 1, math.min(#wrong, 5))))
				end
				if T.check(grid ~= nil and grid:IsA("ScrollingFrame"), "picker ui: Grid is a ScrollingFrame") then
					viewCheck("top")
					local scale = grid.AbsoluteSize.Y / math.max(1, grid.Size.Y.Offset)
					local maxY = grid.CanvasSize.Y.Offset * scale - grid.AbsoluteSize.Y
					grid.CanvasPosition = Vector2.new(0, math.max(0, maxY))
					KC.advance(1)
					viewCheck("scrolled to the end")
					local last = PP.Shown()[#PP.Shown()]
					T.check(H.card(last):FindFirstChild("PetViewport", true) ~= nil, "picker ui: the last row has its viewports after scrolling")
					grid.CanvasPosition = Vector2.new(0, 0)
					KC.advance(0.5)
				end

				-- search
				local search = H.find("Search")
				if T.check(search ~= nil and search:IsA("TextBox"), "picker ui: Search is a TextBox") then
					T.eq(search.PlaceholderText, "Search pets", "picker ui: the PC placeholder")
					search.Text = "fox"
					KC.advance(0.2)
					local okFox = #PP.Shown() > 0
					for _, key in ipairs(PP.Shown()) do
						okFox = okFox and H.nameOf(State, key):lower():find("fox", 1, true) ~= nil
					end
					T.check(okFox and H.shown(H.card("aurora_fox")) and not H.shown(H.card(k1)), "picker ui: typing 'fox' filters the cards", H.keysText(PP.Shown()))
					search.Text = "zzqq"
					KC.advance(0.2)
					local empty = H.find("Empty")
					local emptyText = empty and RedoGeom.find(empty, "EmptyText")
					local clear = H.find("ClearButton")
					T.check(#PP.Shown() == 0 and H.shown(empty) and emptyText and emptyText.Text == "No pets match." and H.shown(clear), "picker ui: no match -> 'No pets match.' + Clear",
						emptyText and emptyText.Text or "none")
					if clear then
						Mock.Click(clear)
						KC.advance(0.2)
					end
					T.check(search.Text == "" and #PP.Shown() == #PP.Entries("Train") and not H.shown(H.find("Empty")), "picker ui: Clear empties the search", tostring(search.Text))
				end

				-- sort: cycles, kept per context
				local sortButton = H.find("SortButton")
				T.check(sortButton ~= nil and sortButton.Text:find("Sort: Training first", 1, true) == 1, "picker ui: 'Sort: Training first'", sortButton and sortButton.Text or "none")
				H.clickName("SortButton")
				T.check(sortButton.Text:find("Sort: Level", 1, true) == 1 and H.card(PP.Shown()[1]) and PP.Shown()[1] == "ember_phoenix", "picker ui: a tap -> 'Sort: Level' (and the order)", sortButton.Text)
				H.clickName("SortButton")
				T.check(sortButton.Text:find("Sort: Rarity", 1, true) == 1, "picker ui: ...then 'Sort: Rarity'", sortButton.Text)
				H.clickName("SortButton")
				H.clickName("SortButton")
				T.check(sortButton.Text:find("Sort: Training first", 1, true) == 1, "picker ui: ...Name, then back to the first", sortButton.Text)
				H.clickName("SortButton")
				local filterTeam = H.find("Filter_Team")
				if filterTeam then
					Mock.Click(filterTeam)
					KC.advance(0.1)
				end
				T.check(filterTeam ~= nil and filterTeam:GetAttribute("Selected") == true and #PP.Shown() == 3, "picker ui: Filter_Team shows the team", H.keysText(PP.Shown()))
				PP.Close()
				KC.advance(0.1)
				closes = {}
				PP.Open({ Context = "Train", Title = "Pick a pet to train", OnPick = onPick, OnClose = onClose })
				KC.advance(0.6)
				T.check(H.find("SortButton").Text:find("Sort: Level", 1, true) == 1 and H.find("Filter_Team"):GetAttribute("Selected") == true and #PP.Shown() == 3,
					"picker ui: the sort and the filter are kept after Close + Open (same context)", H.find("SortButton").Text)
				PP.Close()
				PP.Open({ Context = "Upgrade", Title = "Pick a pet to upgrade" })
				KC.advance(0.6)
				T.check(H.find("SortButton").Text:find("Sort: Ready first", 1, true) == 1 and H.find("Filter_All"):GetAttribute("Selected") == true, "picker ui: Upgrade keeps its own sort and filter", H.find("SortButton").Text)
				-- Upgrade cards: the green Ready badge, a dimmed but pickable 2-copy card, a blocked card
				local maple = H.card("maple_fox")
				local mapleBadge = maple and RedoGeom.find(maple, "Badge")
				T.check(mapleBadge ~= nil and H.shown(mapleBadge) and mapleBadge.Text == "x5" and maple:GetAttribute("Ready") == true and maple:GetAttribute("Dim") ~= true,
					"picker ui: the 5-copy card's badge 'x5' in the Ready style", mapleBadge and mapleBadge.Text or "none")
				local slime = H.card("mochi_slime")
				local slimeBadge = slime and RedoGeom.find(slime, "Badge")
				T.check(slime ~= nil and slime:GetAttribute("Dim") == true and slime:GetAttribute("Ready") ~= true and slimeBadge and slimeBadge.Text == "x2",
					"picker ui: the 2-copy card is dimmed with 'x2'", slimeBadge and slimeBadge.Text or "none")
				T.check(mapleBadge and slimeBadge and mapleBadge.BackgroundColor3 ~= slimeBadge.BackgroundColor3, "picker ui: ...and the Ready badge has its own colour")
				for _, key in ipairs({ "sleepy_owl@Golden", "maple_fox" }) do
					local nm = H.card(key) and RedoGeom.find(H.card(key), "Name")
					local finish = key:match("@(%a+)$")
					T.check(nm ~= nil and nm.Text ~= "" and (finish == nil or nm.Text:find(finish, 1, true) ~= nil),
						"picker ui: a card's name keeps its finish word (" .. key .. ")", nm and nm.Text or "none")
				end
				T.check(PP.Pick("storm_tabby") == false and PP.IsOpen(), "picker ui: a blocked card cannot be picked, the sheet stays open")
				local tabbyWord = RedoGeom.find(H.card("storm_tabby"), "BlockWord")
				T.check(tabbyWord ~= nil and H.shown(tabbyWord) and tabbyWord.Text == "Training", "picker ui: ...it shows its word")
				local upPicks = {}
				PP.Close()
				PP.Open({ Context = "Upgrade", Title = "Pick a pet to upgrade", OnPick = function(key)
					upPicks[#upPicks + 1] = key
				end })
				KC.advance(0.3)
				T.check(PP.Pick("mochi_slime") == true and not PP.IsOpen() and upPicks[1] == "mochi_slime", "picker ui: a dimmed card can still be picked")
				T.check(PP.Pick("mochi_slime") == false and #upPicks == 1, "picker ui: Pick while closed does nothing")

				-- Review Focus 1: a key that leaves the collection while the sheet is open
				picks, closes = {}, {}
				PP.Open({ Context = "Train", Title = "Pick a pet to train", Selected = k3, OnPick = onPick, OnClose = onClose })
				PP.SetSort("Default")
				PP.SetFilter("All")
				KC.advance(0.4)
				T.check(H.card(k3) ~= nil and H.card(k3):GetAttribute("Selected") == true, "picker ui: (vanish) the card is there first")
				H.feed({ [k3] = true })
				KC.advance(0.3)
				T.check(H.card(k3) == nil and PP.Pick(k3) == false and #picks == 0, "picker ui: a key that left the collection loses its card and is never picked", tostring(H.card(k3)))
				T.check(PP.IsOpen() and #PP.Shown() == #PP.Entries("Train"), "picker ui: ...the sheet stays open with the rest")
				local selectedLeft = 0
				for _, key in ipairs(PP.Shown()) do
					if H.card(key):GetAttribute("Selected") == true then
						selectedLeft = selectedLeft + 1
					end
				end
				T.eq(selectedLeft, 0, "picker ui: ...and the Selected mark is gone")
				H.feed()
				KC.advance(0.3)
				T.check(H.card(k3) ~= nil and H.card(k3):GetAttribute("Selected") ~= true, "picker ui: it comes back as a plain card")

				-- Review Focus 3: the screen changes under the open sheet
				Mock.SetViewport(844, 390)
				KC.advance(0.6)
				T.check(PP.Layout() == "Phone", "picker ui: (resize) 844x390 -> the Phone layout", tostring(PP.Layout()))
				RedoGeom.check(H.win(), "picker ui: resized to 844x390", { NoOverlap = { "Search", "SortButton", "Filter_All", "Filter_Team", "Filter_Training", "CloseButton", "Grid" } })
				Mock.SetViewport(1920, 1080)
				KC.advance(0.6)
				T.check(PP.Layout() == "PC", "picker ui: (resize) back to 1920x1080 -> PC", tostring(PP.Layout()))
				RedoGeom.check(H.win(), "picker ui: back at 1920x1080", { NoOverlap = { "Search", "SortButton", "Filter_All", "Filter_Team", "Filter_Training", "Filter_Rare", "Filter_Epic", "CloseButton", "Grid" } })

				-- a pick: the sheet closes first, OnClose(true), OnPick once
				openAtPick = nil
				T.check(PP.Pick(k1) == true, "picker ui: Pick(k1) -> true")
				KC.advance(0.1)
				T.check(openAtPick == false and #picks == 1 and picks[1] == k1, "picker ui: closed before OnPick runs, OnPick once with the key", tostring(openAtPick) .. " " .. H.keysText(picks))
				T.check(#closes == 1 and closes[1] == true and not PP.IsOpen() and not H.shown(H.win()), "picker ui: OnClose(true), the sheet is gone", tostring(closes[1]))

				-- X closes without a pick
				picks, closes = {}, {}
				PP.Open({ Context = "Train", Title = "Pick a pet to train", OnPick = onPick, OnClose = onClose })
				KC.advance(0.4)
				H.clickName("CloseButton")
				T.check(not PP.IsOpen() and #closes == 1 and closes[1] == false and #picks == 0, "picker ui: X closes the sheet: OnClose(false), no pick", tostring(closes[1]))
				PP.Open({ Context = "Train", Title = "Pick a pet to train", OnClose = onClose })
				KC.advance(0.2)
				PP.Close()
				T.check(closes[#closes] == false and not PP.IsOpen(), "picker ui: Close() = OnClose(false)")
				-- an empty context still opens with its text
				H.feed(H.setOf(H.allKeys()))
				PP.Open({ Context = "Train", Title = "Pick a pet to train" })
				KC.advance(0.4)
				local emptyText = H.find("EmptyText")
				T.check(PP.IsOpen() and #PP.Shown() == 0 and emptyText and H.shown(emptyText) and emptyText.Text == "No pets yet! Spin a roulette in the Shop to hatch one." and not H.shown(H.find("ClearButton")),
					"picker ui: no pets at all -> it opens with 'No pets yet! ...'", emptyText and emptyText.Text or "none")
				PP.Close()
			end)
		end)
	end)

	-- the top-row controls of a context's sheet at this layout
	local function topRow(PP, ctx)
		local names = { "Title", "Search", "SortButton", "CloseButton", "Grid" }
		local phone = PP.Layout() == "Phone"
		for i, f in ipairs(PP.Filters[ctx] or {}) do
			if not (phone and i > 3) then
				names[#names + 1] = "Filter_" .. f.Id
			end
		end
		return names
	end

	S.client_picker_layouts = guarded("client_picker_layouts", function()
		local titles = { Train = "Pick a pet to train", Upgrade = "Pick a pet to upgrade", Mix = "Pick the Body pet" }
		for _, size in ipairs({ { 844, 390, true }, { 1280, 720, false }, { 1920, 1080, false } }) do
			for _, ctx in ipairs({ "Train", "Upgrade", "Mix" }) do
				local label = fmt("picker %s %dx%d", ctx, size[1], size[2])
				RedoGeom.at(size[1], size[2], size[3], label, function()
					H.with(label, function(PP)
						PP.Open({ Context = ctx, Title = titles[ctx] })
						KC.advance(0.6)
						local names = topRow(PP, ctx)
						RedoGeom.check(H.win(), label, { NoOverlap = names })
						local search, grid = H.find("Search"), H.find("Grid")
						local all = H.find("Filter_All")
						if size[1] == 844 then
							T.check(PP.Layout() == "Phone", label .. ": the Phone layout")
							local w = H.win()
							T.check(w and math.abs(w.AbsoluteSize.X - 820) <= 2 and math.abs(w.AbsoluteSize.Y - 330) <= 2 and math.abs(w.AbsolutePosition.Y - 59) <= 2,
								label .. ": 820x330 at y 59", w and fmt("%.0fx%.0f y %.0f", w.AbsoluteSize.X, w.AbsoluteSize.Y, w.AbsolutePosition.Y) or "none")
							T.eq(H.perRow(PP), 6, label .. ": 6 cards a row")
							T.check(search and math.abs(search.AbsoluteSize.X - 220) <= 2 and math.abs(search.AbsoluteSize.Y - 44) <= 2, label .. ": the search 220x44", RedoGeom.desc(search))
							T.eq(search and search.PlaceholderText, "Search", label .. ": the phone placeholder")
							local card = H.card(PP.Shown()[1])
							T.check(card and math.abs(card.AbsoluteSize.Y - 100) <= 2 and card.AbsoluteSize.X >= 122, label .. ": cards ~124 x 100", RedoGeom.desc(card))
							if ctx == "Train" then
								T.check(H.shown(H.find("Filter_Training")) and not H.shown(H.find("Filter_Rare")) and not H.shown(H.find("Filter_Epic")), label .. ": the phone shows Train's first three chips")
							end
							-- a long Golden / Rainbow name falls back to its finish + last word, never to a bare last word
							local golden = H.card("sleepy_owl@Golden")
							local nm = golden and RedoGeom.find(golden, "Name")
							T.check(nm ~= nil and nm.Text:find("Golden", 1, true) ~= nil, label .. ": the Golden copy's name keeps 'Golden'", nm and nm.Text or "none")
						else
							T.check(PP.Layout() == "PC", label .. ": the PC layout")
						end
						if size[1] == 1920 then
							T.eq(H.perRow(PP), 7, label .. ": 7 cards a row")
							T.check(search and math.abs(search.AbsoluteSize.X - 460) <= 2 and math.abs(search.AbsoluteSize.Y - 60) <= 2, label .. ": the search 460x60", RedoGeom.desc(search))
							local card = H.card(PP.Shown()[1])
							T.check(card and math.abs(card.AbsoluteSize.Y - 226) <= 2 and card.AbsoluteSize.X >= 178, label .. ": cards ~180 x 226", RedoGeom.desc(card))
							local chipsBottom = 0
							for _, f in ipairs(PP.Filters[ctx]) do
								local c = H.find("Filter_" .. f.Id)
								if c and H.shown(c) then
									chipsBottom = math.max(chipsBottom, c.AbsolutePosition.Y + c.AbsoluteSize.Y)
								end
							end
							T.check(grid and grid.AbsolutePosition.Y >= chipsBottom - 0.5, label .. ": the grid starts under the chips", fmt("grid %.0f, chips end %.0f", grid and grid.AbsolutePosition.Y or -1, chipsBottom))
							if ctx == "Train" then
								T.check(all and search and all.AbsolutePosition.Y >= search.AbsolutePosition.Y + search.AbsoluteSize.Y - 0.5, label .. ": Train's chips sit on row 2 (they do not fit beside the search at 1440)",
									RedoGeom.desc(all) .. " / " .. RedoGeom.desc(search))
							elseif ctx == "Upgrade" then
								local cy = all and (all.AbsolutePosition.Y + all.AbsoluteSize.Y / 2) or -1
								local sy = search and (search.AbsolutePosition.Y + search.AbsoluteSize.Y / 2) or -2
								T.check(math.abs(cy - sy) <= 1, label .. ": Upgrade's chips sit on the search row", RedoGeom.desc(all) .. " / " .. RedoGeom.desc(search))
							end
						end
						PP.Close()
					end)
				end)
			end
		end
	end)

	S.client_picker_portrait = guarded("client_picker_portrait", function()
		local label = "picker portrait 390x844"
		H.with(label, function(PP)
			PP.Open({ Context = "Train", Title = "Pick a pet to train" })
			KC.advance(0.6)
			local w = H.win()
			T.check(w ~= nil and H.shown(w) and PP.Layout() == "Phone", label .. ": the sheet opens in the Phone layout", tostring(PP.Layout()))
			RedoGeom.check(w, label, { NoOverlap = topRow(PP, "Train") })
			local n = H.perRow(PP)
			T.check(n >= 2 and n < #PP.Shown(), label .. ": the cards wrap", tostring(n) .. " a row")
			PP.Close()
		end)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
