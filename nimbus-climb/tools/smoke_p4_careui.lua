-- smoke_p4_careui.lua: the Phase 4 pet-care UI (ARCHITECTURE_V3.md "Phase 4 build contract" 3.4-3.7, 3.9 and 8.1, careui
-- engineer): client/Controllers/CareController.lua, MenuController's Home window and Pets panel, EvolutionFx's confetti.
-- Loaded by tools/smoke.py in the client worlds (desktop and the 390x844 touch phone):
--   client_p4careui_feed     the Food Machine list (OpenPanel("Pets", {Action = "Feed"})): garden pets first (by place),
--                            then the followers, then the rest; "Lv 12 / 100" and the XP bar; "Feed $340 (+90 XP)" and
--                            "Level up $1.2K" from TycoonCatalog.FeedPrice / FeedXp along the XP curve (Feed sends
--                            PetCare("Feed", key), Level up PetCare("Feed", key, {Count = n}) with the feeds the next level
--                            needs); leftovers first and free ("Feed (free Feast, 3 left)" + the leftovers line); EVOLVE!
--                            only where PetCatalog.CanEvolve says so (a confirm, then PetCare("Evolve", key)); a level-100
--                            pet shows MAX LEVEL; the footer "Food Machine Lv 2: each feed fills 30% of the bar" + Upgrade
--                            (HomeAction "Upgrade" "Kitchen"); a menu window opening closes it
--   client_p4careui_garden   the garden picker (OpenPanel("Pets", {Action = "Garden", Slot})): every pet, any role, with its
--                            Coins $/s; Put here -> HomeAction GardenSet {Slot, Key}; a training pet and a pet whose only
--                            copy is placed are disabled; Take out on a filled place -> GardenSet {Slot}; E on an own
--                            GardenSpotPrompt opens it for that Slot, someone else's prompt does nothing
--   client_p4careui_train    the Training Place window (OpenPanel("Train")): four skills with rank bars, the next rank's
--                            cost / time (TrainCost / TrainSeconds), Train asks first then sends PetCare("Train", key, stat);
--                            the training pet shows its timer, its skills are disabled and Stop asks first ("You get the
--                            Cash back, no rank") then sends PetCare("TrainStop", key); full spots disable Train; rank 10
--                            shows MAX
--   client_p4careui_evolve   the EVOLVE moment (OpenPanel("Evolve", {Key, Stage})): every window closes, the follower is
--                            parked (PetController.PlayEvolution), EvolutionFx plays on two clones 5-6.5 studs in front of
--                            the player with voxel confetti, nothing in the screen centre, then the clones go and the
--                            follower comes back; a second Evolve waits for the first
--   client_p4careui_panels   the Pets panel (Lv n / 100, evolution pill, Coins pill, Garden for any role, Equip disabled while
--                            training, Train / EVOLVE open CareController) and the Home window (the Pet Garden card: coins
--                            waiting, coins / min, places N/12, the legacy lines, no Collect; the new station names and
--                            effects; the prestige texts; Go home sends HomeAction "GoHome" and closes)
--   client_p4careui_sizes    every care window, the confirm, the Pets panel and the Home window at 1920x1080 and 1280x720:
--                            every text >= 18 design px; at 844x390 every text >= 14 px on screen
--   client_p4careui_mobile   (phone world, 390x844) the same windows keep every text >= 14 px on screen
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local KC = _G.KC

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local function advance(seconds)
	if KC and KC.advance then
		KC.advance(seconds)
	else
		Mock.Advance(seconds)
	end
end

local function moduleAt(top, rest)
	local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
end

local function pg()
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function find(root, name)
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function shown(obj)
	local cur = obj
	while cur and cur ~= game do
		if cur:IsA("LayerCollector") then
			if cur.Enabled == false then
				return false
			end
		elseif cur:IsA("GuiObject") and cur.Visible == false then
			return false
		end
		cur = cur.Parent
	end
	return true
end

local function toClient(name, ...)
	Mock.ToClient(ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild(name), ...)
end

local function calls(name, mark)
	local out = {}
	for i = (mark or 0) + 1, #Mock.RemoteLog do
		local e = Mock.RemoteLog[i]
		if e.kind == "server" and e.remote == name then
			out[#out + 1] = e
		end
	end
	return out
end

local function disabled(button)
	return button == nil or button:GetAttribute("Disabled") == true or button.Active == false
end

local function flat(text)
	return (tostring(text or ""):gsub("\n", " "))
end

local PetCatalog = moduleAt("shared", "PetCatalog")
local TC = moduleAt("shared", "TycoonCatalog")
local Config = moduleAt("shared", "Config")
local Util = moduleAt("shared", "Util")

local function petOf(rarity, skip)
	for _, def in ipairs(PetCatalog.Pets) do
		if def.Rarity == rarity and not def.EventOnly and def.Id ~= skip and def.Role ~= nil then
			return def.Id
		end
	end
	return nil
end

local function petOfRole(role, skip)
	for _, def in ipairs(PetCatalog.Pets) do
		if def.Role == role and not def.EventOnly and def.Rarity ~= "Secret" and def.Id ~= skip then
			return def.Id
		end
	end
	return nil
end

-- the cast: two garden pets, a follower, a pet ready to EVOLVE, a pet in training, a level-100 pet, a Combat pet
local P = {}
P.G1 = petOf("Common")
P.G2 = petOf("Uncommon")
P.READY = petOf("Rare")
P.FOLLOW = petOf("Epic")
P.TRAIN = petOf("Common", P.G1)
P.MAX = petOf("Legendary")
P.COMBAT = petOfRole("Combat", P.TRAIN)
if P.COMBAT == P.G1 or P.COMBAT == P.G2 or P.COMBAT == P.READY or P.COMBAT == P.FOLLOW or P.COMBAT == P.MAX then
	P.COMBAT = petOfRole("Combat", P.COMBAT)
end

local function care()
	return (KC and KC.M and KC.M.CareController) or moduleAt("client", "Controllers/CareController")
end

local function menu()
	return (KC and KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
end

local plot = nil
local function setPlot(attrs)
	local lobby = workspace:FindFirstChild("NimbusLobby")
	if not lobby then
		lobby = Instance.new("Folder")
		lobby.Name = "NimbusLobby"
		lobby.Parent = workspace
	end
	if not plot or not plot.Parent then
		plot = Instance.new("Folder")
		plot.Name = "Spot_05"
		plot:SetAttribute("SpotIndex", 5)
		plot.Parent = lobby
	end
	for k, v in pairs(attrs or {}) do
		plot:SetAttribute(k, v)
	end
	LocalPlayer:SetAttribute(Config.Attr.SpotIndex, 5)
end

-- a profile in the middle of Phase 4 (opts: Food, Gym, Speed10, House, Legacy, Cash)
local function profile(opts)
	opts = opts or {}
	local pets = {}
	for _, id in pairs(P) do
		pets[id] = 1
	end
	local home = {
		Level = 22,
		Prestige = 1,
		Stations = { Garden = 2, Press1 = 5, Kitchen = 2, Gym = opts.Gym or 2, Vault = 1, House = opts.House or 3 },
		Garden = { P.G1, P.G2, "", "" },
		Gym = {},
		CollectorCash = 1840,
		LegacySlots = opts.Legacy and 6 or nil,
		LegacyPrices = opts.Legacy or nil,
	}
	local growth = {
		[P.FOLLOW] = { Evo = 1, Physique = 3 },
		[P.TRAIN] = { Physique = 1, Job = { Stat = "Physique", Ends = os.time() + 130, Rank = 2, Slot = 1, From = "Follow", Paid = 1200 } },
		[P.MAX] = { Evo = 2, Speed = opts.Speed10 and 10 or 4 },
	}
	return {
		Tokens = 900,
		Pets = pets,
		Equipped = { P.FOLLOW },
		Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
		Discovered = pets,
		IndexClaimed = {},
		Tutorial = { Step = 99, Done = true, Gifted = true },
		Cash = opts.Cash or 250000,
		Gems = 50,
		Home = home,
		Food = {},
		Berries = opts.Berries or 1240,
		PetLevels = {
			[P.G1] = { Level = 12, Xp = 300 },
			[P.G2] = { Level = 9, Xp = 40 },
			[P.READY] = { Level = 20, Xp = 10 },
			[P.FOLLOW] = { Level = 57, Xp = 900 },
			[P.TRAIN] = { Level = 7, Xp = 0 },
			[P.MAX] = { Level = 100, Xp = 0 },
		},
		PetGrowth = growth,
		Ring = { Best = 0, Runs = 0 },
	}
end

local function sync(opts)
	local snap = profile(opts)
	setPlot({ CollectorCash = snap.Home.CollectorCash, IncomePerSecond = 38.5, GardenSlots = opts and opts.Legacy and 6 or 4, HomeLevel = 22, Prestige = 1, BerryCap = 3000 })
	LocalPlayer:SetAttribute(Config.Attr.Berries or "Berries", snap.Berries)
	LocalPlayer:SetAttribute(Config.Attr.Cash, snap.Cash)
	LocalPlayer:SetAttribute(Config.Attr.Gems, snap.Gems)
	LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
	toClient("ProfileSync", snap)
	advance(0.4)
	return snap
end

local function careGui()
	return pg():FindFirstChild("NimbusCare")
end

local function careWin()
	local g = careGui()
	return g and g:FindFirstChild("Window_Care")
end

local function closeAll()
	local C = care()
	if C then
		C.Close()
	end
	local M = menu()
	if M then
		M.Close()
	end
	advance(0.3)
end

-- texts under `root` smaller than `floorPx` design px (TextScaled ones by their UITextSizeConstraint minimum)
local function smallTexts(root, floorPx)
	local out = {}
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) then
			local size = d.TextSize
			if d.TextScaled then
				local c = d:FindFirstChildOfClass("UITextSizeConstraint")
				if c then
					size = c.MinTextSize
				else
					local box = Mock.GuiBox(d)
					size = (box and box.scale and box.scale > 0) and (box.h / box.scale) or 0
				end
			end
			if size < floorPx - 0.01 then
				out[#out + 1] = d.Name .. "=" .. tostring(size)
			end
		end
	end
	return out
end

-- texts under `root` smaller than `floorPx` ON SCREEN (design size x the cumulative UIScale)
local function smallOnScreen(root, floorPx)
	local out = {}
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) then
			local box = Mock.GuiBox(d)
			local scale = (box and box.scale) or 1
			local size = d.TextSize
			if d.TextScaled then
				local c = d:FindFirstChildOfClass("UITextSizeConstraint")
				size = c and c.MinTextSize or ((box and scale > 0) and box.h / scale or 0)
			end
			if size * scale < floorPx - 0.05 then
				out[#out + 1] = string.format("%s=%.1f", d.Name, size * scale)
			end
		end
	end
	return out
end

-- shown texts whose centre sits in the middle of the screen (tol = share of the screen)
local function centred(tol)
	local vp = Mock.Viewport
	local out = {}
	for _, d in ipairs(pg():GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) and d.AbsoluteSize.X > 0 then
			local cx = d.AbsolutePosition.X + d.AbsoluteSize.X / 2
			local cy = d.AbsolutePosition.Y + d.AbsoluteSize.Y / 2
			if abs(cx - vp.X / 2) < tol * vp.X and abs(cy - vp.Y / 2) < tol * vp.Y then
				out[#out + 1] = d:GetFullName():sub(-60) .. " '" .. tostring(d.Text):sub(1, 24) .. "'"
			end
		end
	end
	return out
end

local function errorsSince(mark, needles)
	local out = {}
	for i = mark + 1, #Mock.Errors do
		local msg = tostring(Mock.Errors[i].msg)
		for _, n in ipairs(needles) do
			if msg:find(n, 1, true) then
				out[#out + 1] = msg:sub(1, 160)
				break
			end
		end
	end
	return out
end

-- the feeds the next level needs (at most 10) and their Cash, walked along the XP curve like the server does
local function levelUpPlan(id, level, xp, machine)
	local def = PetCatalog.Get(id)
	local count, price, lv = 0, 0, level
	local cap = PetCatalog.LevelCap(def)
	while count < 10 and lv == level and lv < cap do
		price = price + TC.FeedPrice(def, lv)
		xp = xp + TC.FeedXp(lv, machine)
		count = count + 1
		while lv < cap and xp >= TC.XpToNext(lv) do
			xp = xp - TC.XpToNext(lv)
			lv = lv + 1
		end
	end
	return count, price
end

local function bootIfNeeded()
	if not ReplicatedStorage:FindFirstChild("Remotes") then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, n in ipairs(Config.Remotes) do
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
	if not (pg() and pg():FindFirstChild("NimbusMenu")) then
		Mock.RunScript(Mock.GetPath(ROOTS["client"] .. "/Main"))
		advance(3)
	end
end

local function ready()
	bootIfNeeded()
	local C = care()
	if not T.check(type(C) == "table" and type(C.Open) == "function" and type(C.Close) == "function" and type(C.IsOpen) == "function"
		and type(C.Init) == "function", "careui: client/Controllers/CareController.lua loads with Init / Open / Close / IsOpen") then
		return nil
	end
	C.Init()
	local M = menu()
	if M and M.Init then
		M.Init()
	end
	return C, M
end

----------------------------------------------------------------------------------------------------
-- the Food Machine list
----------------------------------------------------------------------------------------------------
S.client_p4careui_feed = guarded("client_p4careui_feed", function()
	local C, M = ready()
	if not C then
		return
	end
	local errors0 = #Mock.Errors
	sync()
	toClient("OpenPanel", "Pets", { Tab = "Pets", Action = "Feed" })
	advance(0.6)
	local win = careWin()
	T.check(C.Mode() == "Feed" and C.IsOpen() and win and win.Visible, "careui feed: OpenPanel('Pets', {Action = 'Feed'}) (the FeedPrompt) opens the Food Machine list")
	T.check(not (M and M.IsOpen()), "careui feed: ...and no menu window under it")
	local function row(id)
		return win and find(win, "Feed_" .. id)
	end
	T.check(row(P.G1) and row(P.G2) and row(P.FOLLOW) and row(P.G1).LayoutOrder == 1 and row(P.G2).LayoutOrder == 2 and row(P.FOLLOW).LayoutOrder == 3,
		"careui feed: garden pets first (by place), then the followers, then the rest",
		row(P.G1) and (row(P.G1).LayoutOrder .. "," .. row(P.G2).LayoutOrder .. "," .. row(P.FOLLOW).LayoutOrder) or "rows missing")
	local r1 = row(P.G1)
	local def1 = PetCatalog.Get(P.G1)
	T.check(r1 and find(r1, "Level").Text == "Lv 12 / 100", "careui feed: a row shows 'Lv 12 / 100' (the cap from PetCatalog)", r1 and find(r1, "Level").Text or "")
	local barText = r1 and find(find(r1, "XpBar"), "Text")
	T.check(barText and barText.Text == Util.Commas(300) .. " / " .. Util.Commas(TC.XpToNext(12)) .. " XP", "careui feed: ...and the XP bar (300 / XpToNext(12))", barText and barText.Text or "")
	-- Phase 5 (3.4): ONE Feed button with the berry price; no "Level up"
	local cost1 = TC.FeedBerries(def1, 12)
	local wantFeed = "Feed  " .. Util.Commas(cost1) .. " berries  (+" .. Util.Commas(TC.FeedXp(12, 2)) .. " XP)"
	local feedBtn = r1 and find(r1, "Feed")
	T.eq(feedBtn and feedBtn.Text, wantFeed, "careui feed: ONE Feed button 'Feed  N berries  (+xp XP)' from TycoonCatalog.FeedBerries / FeedXp")
	local upBtn = nil
	for _, d in ipairs(win and win:GetDescendants() or {}) do
		if (d:IsA("TextButton") and (d.Name == "LevelUp" or d.Text:find("Level up", 1, true))) then
			upBtn = d
		end
	end
	T.check(upBtn == nil, "careui feed: no 'Level up' button (one feed per press)", upBtn and upBtn:GetFullName() or "")
	local bar = win and find(win, "BerryBasket")
	local barText = bar and find(bar, "Text")
	T.check(barText and barText.Text == "Berry Basket 1,240 / 3,000" and shown(bar), "careui feed: the header is the Berry Basket bar (Berries / BerryCap)", barText and barText.Text or "none")
	local rate = win and find(win, "BasketRate")
	T.check(rate and rate.Text == "+" .. Util.Commas(math.floor(38.5 * TC.Berries.Share * 60 + 0.5)) .. " a minute", "careui feed: ...and the berries a minute (income x Share x 60)", rate and rate.Text or "")
	local how = win and find(win, "Leftovers")
	T.check(how and how.Text:find("Each Feed turns berries into XP", 1, true), "careui feed: the footer says how it works", how and how.Text or "")
	-- a short basket: nothing is sent, the hint says why
	local mark = #Mock.RemoteLog
	Mock.Click(feedBtn)
	advance(0.4)
	T.eq(#calls("PetCare", mark), cost1 > 1240 and 0 or 1, "careui feed: Feed with too few berries sends nothing (the hint says how many it needs)")
	LocalPlayer:SetAttribute(Config.Attr.Berries or "Berries", cost1 + 500)
	advance(0.6)
	mark = #Mock.RemoteLog
	Mock.Click(feedBtn)
	advance(0.4)
	local pc = calls("PetCare", mark)
	T.check(#pc == 1 and pc[1].args[1] == "Feed" and pc[1].args[2] == P.G1 and pc[1].args[3] == nil,
		"careui feed: with enough berries Feed sends PetCare('Feed', key) (one feed, no second argument)")
	-- EVOLVE only where CanEvolve
	local evoReady = row(P.READY) and find(row(P.READY), "Evolve")
	local evoNot = r1 and find(r1, "Evolve")
	T.check(evoReady and evoReady.Visible and evoNot and not evoNot.Visible, "careui feed: EVOLVE! shows only on the pet that can evolve (level 20, stage 0)")
	mark = #Mock.RemoteLog
	Mock.Click(evoReady)
	advance(0.4)
	local confirm = careGui() and careGui():FindFirstChild("CareConfirm")
	T.check(confirm and confirm.Visible and #calls("PetCare", mark) == 0 and find(confirm, "Title").Text:find("Evolve", 1, true),
		"careui feed: EVOLVE asks first (nothing is sent yet)")
	Mock.Click(find(confirm, "ConfirmYes"))
	advance(0.3)
	pc = calls("PetCare", mark)
	T.check(#pc == 1 and pc[1].args[1] == "Evolve" and pc[1].args[2] == P.READY and not confirm.Visible, "careui feed: ...then sends PetCare('Evolve', key)")
	-- the level-100 pet
	local rMax = row(P.MAX)
	T.check(rMax and flat(find(rMax, "Feed").Text) == "Max level" and disabled(find(rMax, "Feed"))
		and find(find(rMax, "XpBar"), "Text").Text == "MAX LEVEL" and find(rMax, "Level").Text == "Lv 100 / 100",
		"careui feed: a level-100 pet shows MAX LEVEL and cannot eat")
	-- the footer
	local machine = win and find(win, "Machine")
	T.check(machine and machine.Text:find("Food Machine Lv 2: each feed fills 30% of the bar.", 1, true), "careui feed: the footer names the machine's level and share",
		machine and machine.Text or "")
	local home = profile().Home
	local pad = nil
	for _, p in ipairs(TC.AvailablePads(home)) do
		if p.StationId == "Kitchen" then
			pad = p
		end
	end
	local upgrade = win and find(win, "UpgradeMachine")
	if pad and not pad.Locked then
		LocalPlayer:SetAttribute(Config.Attr.Cash, pad.Price + 1000) -- (State.Cash reads the attribute)
		advance(0.4)
		T.check(machine.Text:find("Upgrade to Lv 3 (35%): " .. TC.FormatCash(pad.Price), 1, true) and upgrade and upgrade.Visible,
			"careui feed: ...and the next level with its price + Upgrade", machine.Text)
		mark = #Mock.RemoteLog
		Mock.Click(upgrade)
		advance(0.3)
		local hc = calls("HomeAction", mark)
		T.check(#hc == 1 and hc[1].args[1] == "Upgrade" and hc[1].args[2] == "Kitchen", "careui feed: Upgrade sends HomeAction('Upgrade', 'Kitchen') (the pad's purchase)")
	else
		T.check(pad and machine.Text:find(tostring(pad.Locked), 1, true) and not (upgrade and upgrade.Visible),
			"careui feed: a locked next level says why (no Upgrade)", machine.Text)
	end
	-- a menu window opening closes it
	if M then
		M.Open("Stats")
		advance(0.4)
		T.check(not C.IsOpen(), "careui feed: a menu window opening closes the Food Machine list")
	end
	closeAll()
	local mine = errorsSince(errors0, { "CareController", "MenuController" })
	T.check(#mine == 0, "careui feed: no script errors", table.concat(mine, " | "))
end)

----------------------------------------------------------------------------------------------------
-- the garden picker
----------------------------------------------------------------------------------------------------
S.client_p4careui_garden = guarded("client_p4careui_garden", function()
	local C = ready()
	if not C then
		return
	end
	local errors0 = #Mock.Errors
	local snap = sync()
	toClient("OpenPanel", "Pets", { Action = "Garden", Slot = 3 })
	advance(0.6)
	local win = careWin()
	local place = win and find(win, "Place")
	T.check(C.Mode() == "Garden" and win.Visible and place and place.Text:find("Garden place 3", 1, true), "careui garden: OpenPanel('Pets', {Action = 'Garden', Slot = 3}) opens the picker for place 3")
	local function pick(id)
		return win and find(win, "Pick_" .. id)
	end
	local combat = pick(P.COMBAT)
	local put = combat and find(combat, "PutHere")
	T.check(put and put.Visible and not disabled(put), "careui garden: a Combat pet can be put in the Garden (any role)")
	local mark = #Mock.RemoteLog
	Mock.Click(put)
	advance(0.3)
	local hc = calls("HomeAction", mark)
	T.check(#hc == 1 and hc[1].args[1] == "GardenSet" and hc[1].args[2].Slot == 3 and hc[1].args[2].Key == P.COMBAT,
		"careui garden: Put here sends HomeAction('GardenSet', {Slot = 3, Key})")
	T.check(disabled(find(pick(P.TRAIN), "PutHere")) and disabled(find(pick(P.G1), "PutHere")),
		"careui garden: a pet in training and a pet whose only copy already works there are disabled")
	-- coins per second (PetPower x food x stars / meal x Lucky)
	local defC = PetCatalog.Get(P.COMBAT)
	local home = snap.Home
	local food = TC.FoodOf(home)
	local rate = TC.PetPower({ Def = defC, Level = 1, Stage = 0 }) * food * TC.PrestigeMultiplier(1) * TC.LuckyEV(home) / TC.Coins.MealSeconds
	local coins = combat and find(combat, "Coins")
	local want = rate < 100 and ("$" .. ((string.format("%.1f", floor(rate * 10 + 0.5) / 10)):gsub("%.0$", ""))) or TC.FormatCash(rate)
	T.check(coins and coins.Text == "Coins " .. want .. "/s", "careui garden: every pet shows the coins it makes in this Garden", (coins and coins.Text or "?") .. " want " .. want)
	local role = combat and find(combat, "Role")
	T.check(role and role.Text:find("Combat", 1, true), "careui garden: ...and its role")
	-- a filled place: Take out
	toClient("OpenPanel", "Pets", { Action = "Garden", Slot = 1 })
	advance(0.4)
	local take = win and find(win, "TakeOut")
	T.check(take and take.Visible and find(win, "Now").Text:find(PetCatalog.Get(P.G1).Name, 1, true), "careui garden: a filled place names its pet and offers Take out")
	mark = #Mock.RemoteLog
	Mock.Click(take)
	advance(0.3)
	hc = calls("HomeAction", mark)
	T.check(#hc == 1 and hc[1].args[1] == "GardenSet" and hc[1].args[2].Slot == 1 and hc[1].args[2].Key == nil, "careui garden: Take out sends GardenSet {Slot = 1}")
	closeAll()
	-- E on the own GardenSpotPrompt (server-made: attributes Slot, OwnerUserId) opens the picker for that place
	local part = Instance.new("Part")
	part.Name = "CareUiPromptPart"
	part.Anchored = true
	part.Parent = workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GardenSpotPrompt"
	prompt:SetAttribute("Slot", 4)
	prompt:SetAttribute("OwnerUserId", 999001)
	prompt.Parent = part
	Mock.Trigger(prompt, LocalPlayer)
	advance(0.3)
	T.check(not C.IsOpen(), "careui garden: someone else's GardenSpotPrompt opens nothing")
	prompt:SetAttribute("OwnerUserId", LocalPlayer.UserId)
	Mock.Trigger(prompt, LocalPlayer)
	advance(0.4)
	place = win and find(win, "Place")
	T.check(C.Mode() == "Garden" and place and place.Text:find("Garden place 4", 1, true), "careui garden: E on an own GardenSpotPrompt opens the picker for its Slot")
	part:Destroy()
	closeAll()
	local mine = errorsSince(errors0, { "CareController" })
	T.check(#mine == 0, "careui garden: no script errors", table.concat(mine, " | "))
end)

----------------------------------------------------------------------------------------------------
-- the Training Place window
----------------------------------------------------------------------------------------------------
S.client_p4careui_train = guarded("client_p4careui_train", function()
	local C = ready()
	if not C then
		return
	end
	local errors0 = #Mock.Errors
	sync({ Gym = 2 })
	toClient("OpenPanel", "Train", {})
	advance(0.6)
	local win = careWin()
	T.check(C.Mode() == "Train" and win and win.Visible, "careui train: OpenPanel('Train') (the TrainPrompt) opens the Training Place window")
	local skills = {}
	for _, id in ipairs({ "Speed", "Physique", "Ability", "Defense" }) do
		skills[#skills + 1] = win and find(win, "Skill_" .. id) and id or nil
	end
	T.eq(table.concat(skills, ","), "Speed,Physique,Ability,Defense", "careui train: the four skills (Attack Speed, Physique, Ability, Defense)")
	T.check(find(find(win, "Skill_Speed"), "Name").Text == "Attack Speed", "careui train: Speed is labelled 'Attack Speed'")
	-- the pet in training is selected first: its timer, Stop
	local timer = find(win, "TrainTimer")
	local timerText = timer and find(timer, "Text")
	T.check(timer and shown(timer) and timerText and timerText.Text:find("Rank 2: 2:", 1, true) and timerText.Text:find("left", 1, true),
		"careui train: the pet in training shows its timer ('Physique Rank 2: 2:10 left')", timerText and timerText.Text or "")
	T.check(disabled(find(find(win, "Skill_Speed"), "Train")) and find(find(win, "Skill_Physique"), "Train").Text == "Training",
		"careui train: a training pet cannot start another skill")
	local mark = #Mock.RemoteLog
	Mock.Click(find(win, "StopTraining"))
	advance(0.4)
	local confirm = careGui():FindFirstChild("CareConfirm")
	T.check(confirm.Visible and find(confirm, "Text").Text:find("You get the Cash back, no rank", 1, true) and #calls("PetCare", mark) == 0,
		"careui train: Stop asks first ('You get the Cash back, no rank')")
	Mock.Click(find(confirm, "ConfirmYes"))
	advance(0.3)
	local pc = calls("PetCare", mark)
	T.check(#pc == 1 and pc[1].args[1] == "TrainStop" and pc[1].args[2] == P.TRAIN, "careui train: ...then sends PetCare('TrainStop', key)")
	-- another pet: costs and times from the catalog, Train asks first
	local rowF = find(win, "Train_" .. P.FOLLOW)
	Mock.Click(rowF)
	advance(0.4)
	local defF = PetCatalog.Get(P.FOLLOW)
	local phys = find(win, "Skill_Physique")
	local want = "Rank 4: " .. TC.FormatCash(TC.TrainCost(defF, 4)) .. ", " .. floor(TC.TrainSeconds(4) / 60) .. " min"
	T.eq(find(phys, "Cost").Text, want, "careui train: the next rank's cost and time (TrainCost / TrainSeconds; Rank 4 takes 4 minutes)")
	T.check(find(phys, "Rank").Text == "Rank 3/10", "careui train: the rank bar shows the pet's rank")
	local lit = 0
	for i = 1, 10 do
		local pip = find(find(phys, "RankBar"), "Pip" .. i)
		if pip and pip.BackgroundColor3 ~= Color3.fromRGB(14, 20, 52) then
			lit = lit + 1
		end
	end
	T.eq(lit, 3, "careui train: three of the ten pips are lit")
	mark = #Mock.RemoteLog
	Mock.Click(find(phys, "Train"))
	advance(0.4)
	T.check(confirm.Visible and find(confirm, "Title").Text:find("Physique", 1, true) and #calls("PetCare", mark) == 0, "careui train: Train asks first")
	Mock.Click(find(confirm, "ConfirmYes"))
	advance(0.3)
	pc = calls("PetCare", mark)
	T.check(#pc == 1 and pc[1].args[1] == "Train" and pc[1].args[2] == P.FOLLOW and pc[1].args[3] == "Physique", "careui train: ...then sends PetCare('Train', key, 'Physique')")
	-- full spots (one Training Place spot, one job running)
	sync({ Gym = 1 })
	toClient("OpenPanel", "Train", { Key = P.FOLLOW })
	advance(0.5)
	phys = find(win, "Skill_Physique")
	T.check(disabled(find(phys, "Train")) and find(win, "Spots").Text:find("1 / 1", 1, true), "careui train: full spots disable Train", find(win, "Spots").Text)
	-- rank 10
	sync({ Speed10 = true })
	toClient("OpenPanel", "Train", { Key = P.MAX })
	advance(0.5)
	local speed = find(win, "Skill_Speed")
	T.check(find(speed, "Max").Visible and not find(speed, "Train").Visible, "careui train: rank 10 shows MAX")
	closeAll()
	local mine = errorsSince(errors0, { "CareController" })
	T.check(#mine == 0, "careui train: no script errors", table.concat(mine, " | "))
end)

----------------------------------------------------------------------------------------------------
-- the EVOLVE moment
----------------------------------------------------------------------------------------------------
S.client_p4careui_evolve = guarded("client_p4careui_evolve", function()
	local C, M = ready()
	if not C then
		return
	end
	local errors0 = #Mock.Errors
	local Fx = moduleAt("client", "Controllers/EvolutionFx")
	local PC = (KC and KC.M and KC.M.PetController) or moduleAt("client", "Controllers/PetController")
	sync()
	LocalPlayer:SetAttribute("EquippedPets", P.FOLLOW)
	advance(1.5)
	local function follower()
		local info = PC and PC.GetFollowerInfo and PC.GetFollowerInfo(LocalPlayer) or {}
		return info[1]
	end
	T.check(follower() ~= nil and follower().Key == P.FOLLOW, "careui evolve: the follower is out")
	if M then
		M.Open("Pets", { Key = P.FOLLOW })
		advance(0.4)
	end
	toClient("OpenPanel", "Evolve", { Key = P.FOLLOW, Stage = 2 })
	advance(0.4)
	T.check(not (M and M.IsOpen()) and not C.IsOpen(), "careui evolve: every window slides away")
	T.eq(C.Evolving(), 1, "careui evolve: the evolution plays")
	T.check(follower() and follower().Parked == true, "careui evolve: the follower is parked (PetController.PlayEvolution)")
	local folder = workspace:FindFirstChild("CareEvolution")
	local model = nil
	for _, d in ipairs(folder and folder:GetChildren() or {}) do
		if d:IsA("Model") then
			model = d
		end
	end
	local root = Mock.GetRoot(LocalPlayer)
	local dist = nil
	if model and root then
		local p = model:GetPivot().Position
		dist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	end
	T.check(dist and dist >= 4.5 and dist <= 7, "careui evolve: EvolutionFx plays on a clone 5-6 studs in front of the player (in the world, not a viewport)", tostring(dist))
	T.check(Fx and Fx.Count() >= 1, "careui evolve: EvolutionFx is playing")
	local centre = centred(0.12)
	T.check(#centre == 0, "careui evolve: nothing in the screen centre", table.concat(centre, "; "))
	-- a second Evolve waits for the first
	toClient("OpenPanel", "Evolve", { Key = P.READY, Stage = 1 })
	advance(0.2)
	T.eq(C.Evolving(), 1, "careui evolve: a second Evolve waits for the first")
	advance(2.6 + 0.38 + 0.35)
	local confetti = 0
	for _, d in ipairs(folder and folder:GetDescendants() or {}) do
		if d:IsA("BasePart") and d.Name == "EvolveConfetti" then
			confetti = confetti + 1
		end
	end
	T.check(confetti >= 20, "careui evolve: voxel confetti at the reveal", tostring(confetti))
	local dur = Fx and Fx.Duration(2) or 5
	advance(dur + 1.6)
	local f = follower()
	T.check(f and not f.Parked and (f.Stage or 0) >= 1, "careui evolve: the follower comes back (rebuilt evolved)")
	-- the second one plays next, then everything is gone
	advance((Fx and Fx.Duration(1) or 5) + 2)
	T.eq(C.Evolving(), 0, "careui evolve: both evolutions finished")
	local left = 0
	for _, d in ipairs(folder and folder:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			left = left + 1
		end
	end
	T.eq(left, 0, "careui evolve: no clone or effect part is left")
	LocalPlayer:SetAttribute("EquippedPets", "")
	advance(0.4)
	local mine = errorsSince(errors0, { "CareController", "EvolutionFx" })
	T.check(#mine == 0, "careui evolve: no script errors", table.concat(mine, " | "))
end)

----------------------------------------------------------------------------------------------------
-- the Pets panel + the Home window
----------------------------------------------------------------------------------------------------
S.client_p4careui_panels = guarded("client_p4careui_panels", function()
	local C, M = ready()
	if not (C and M) then
		return
	end
	local errors0 = #Mock.Errors
	sync({ Legacy = true })
	local menuGui = pg():FindFirstChild("NimbusMenu")
	M.Open("Pets", { Key = P.FOLLOW })
	advance(0.6)
	local inv = menuGui:FindFirstChild("Window_Inventory")
	local detail = find(inv, "Detail")
	T.check(find(detail, "Level").Text == "Lv 57 / 100", "careui pets: 'Lv 57 / 100'", find(detail, "Level").Text)
	local evo = find(inv, "Evolution")
	T.check(evo and evo.Visible and evo.Text:find("Evolved", 1, true), "careui pets: the evolution pill")
	local coins = find(inv, "Stat_Income")
	T.check(coins and coins.Text:find("^Coins %$"), "careui pets: the 'Coins $/s' pill", coins and coins.Text or "")
	local slot, tag = nil, nil
	for _, d in ipairs(inv:GetDescendants()) do
		if d.Name == "Pet_" .. P.FOLLOW and find(d, "LevelTag") then
			slot, tag = d, find(d, "LevelTag")
		end
	end
	local evoTag = slot and find(slot, "EvoTag")
	T.check(tag and tag.Text:find("Lv 57", 1, true) and evoTag and evoTag.Visible and evoTag.Text:find("\226\152\133", 1, true),
		"careui pets: the grid slot shows the level (LevelTag) and the evolution star (EvoTag, Phase 5)",
		tag and (tag.Text .. " visible=" .. tostring(tag.Visible) .. " evo=" .. tostring(evoTag and evoTag.Text)) or (slot and "no LevelTag" or "no slot"))
	M.Open("Pets", { Key = P.COMBAT })
	advance(0.3)
	T.check(find(inv, "WorkPet").Text == "Garden" and not disabled(find(inv, "WorkPet")), "careui pets: Garden for a Combat pet (any role)")
	M.Open("Pets", { Key = P.TRAIN })
	advance(0.3)
	T.check(disabled(find(inv, "Equip")) and find(find(inv, "Detail"), "Work").Text:find("Training", 1, true), "careui pets: Equip is disabled while training")
	local trainChip = find(find(inv, "Pet_" .. P.TRAIN), "WorkBadge")
	T.check(trainChip and trainChip.Visible, "careui pets: the training pet's slot has a chip")
	M.Open("Pets", { Key = P.READY })
	advance(0.3)
	T.check(find(inv, "EvolvePet").Visible, "careui pets: EVOLVE! on a pet that can evolve")
	-- the floating card's pill: MenuController.Open("Pets", {Key, Action = "Evolve"}) -> the Pets panel + the confirm
	M.Close()
	advance(0.3)
	M.Open("Pets", { Tab = "Pets", Key = P.READY, Action = "Evolve" })
	advance(0.6)
	local confirm = pg():FindFirstChild("NimbusCare"):FindFirstChild("CareConfirm")
	T.check(inv.Visible and confirm.Visible, "careui pets: the card's EVOLVE! pill opens the Pets panel with the EVOLVE confirm")
	C.Close()
	M.Close()
	advance(0.3)
	-- the Home window
	M.Open("Home")
	advance(0.6)
	local win = menuGui:FindFirstChild("Window_Home")
	T.check(win and win.Visible, "careui home: the Home window opens")
	-- Phase 5 (3.4): the flow strip: Berry Farm -> pets eat & poop -> Berry Basket -> Food Machine
	local strip = find(win, "FlowStrip")
	local function tileText(id)
		local t = strip and find(strip, "Flow_" .. id)
		return t and (find(t, "Title").Text .. " | " .. find(t, "Value").Text) or "?"
	end
	T.check(strip and shown(strip), "careui home: the flow strip is on top of the Home window")
	T.eq(tileText("Farm"), "Berry Farm | Lv 5", "careui home: strip 1 = the Berry Farm and its level")
	T.eq(tileText("Poop"), "Pets eat & poop | " .. TC.FormatCash(floor(38.5 * 60 + 0.5)) .. " a minute", "careui home: strip 2 = Cloud Cash a minute (IncomePerSecond x 60)")
	T.eq(tileText("Basket"), "Berry Basket | 1,240 / 3,000", "careui home: strip 3 = the Berry Basket (Berries / BerryCap)")
	T.eq(tileText("Machine"), "Food Machine | Feed = XP", "careui home: strip 4 = the Food Machine")
	local gardenCard = find(win, "GardenCard")
	T.check(gardenCard == nil or not shown(gardenCard), "careui home: no old 'coins waiting' card (fewer things on screen)")
	T.check(find(win, "Collect") == nil, "careui home: no Collect button")
	local rows = 0
	for _, d in ipairs(win:GetDescendants()) do
		if d.Name:find("^Station_") then
			rows = rows + 1
		end
	end
	T.eq(rows, #TC.Stations, "careui home: one row per station of TycoonCatalog (11)")
	local names = {}
	for _, id in ipairs({ "Press1", "Kitchen", "Gym", "Garden", "DecorFence", "DecorFountain", "DecorPodium" }) do
		local row = find(win, "Station_" .. id)
		names[#names + 1] = row and find(row, "Name").Text or "?"
	end
	T.eq(table.concat(names, ","), "Berry Farm,Food Machine,Training Place,Pet Garden,Yard Fence,Fountain,Pet Podium", "careui home: the Phase 5 station names (3 decor)")
	local infoOf = function(id)
		local row = find(win, "Station_" .. id)
		return row and find(row, "Info").Text or ""
	end
	T.check(infoOf("Press1"):find("food", 1, true) and infoOf("Kitchen"):find("Feeds fill", 1, true) and infoOf("Gym"):find("train at once", 1, true),
		"careui home: what each station does (food, feeds fill, pets train at once)",
		infoOf("Press1") .. " | " .. infoOf("Kitchen") .. " | " .. infoOf("Gym"))
	local signed = TC.SignedPads(TC.AvailablePads(profile().Home), 250000)
	local tags, ok = 0, true
	for _, d in ipairs(win:GetDescendants()) do
		if d.Name == "NextTag" and shown(d) then
			tags = tags + 1
			local id = d.Parent.Name:gsub("^Station_", "")
			ok = ok and signed[id] == true
		end
	end
	T.check(ok and tags >= 1 and tags <= 4, "careui home: the pads SignedPads picks carry a 'Next' tag (at most 3 + Prestige)", tags .. " tags")
	T.check(find(win, "Reward").Text:find("+1 garden place", 1, true), "careui home: the prestige reward names the garden place", find(win, "Reward").Text)
	local mark = #Mock.RemoteLog
	Mock.Click(find(win, "GoHome"))
	advance(0.4)
	local hc = calls("HomeAction", mark)
	T.check(#hc == 1 and hc[1].args[1] == "GoHome" and not M.IsOpen(), "careui home: Go home sends HomeAction('GoHome') (the portal) and closes")
	closeAll()
	local mine = errorsSince(errors0, { "CareController", "MenuController" })
	T.check(#mine == 0, "careui panels: no script errors", table.concat(mine, " | "))
end)

----------------------------------------------------------------------------------------------------
-- sizes: every window at 1920x1080 / 1280x720 (>= 18 design px) and 844x390 (>= 14 px on screen)
----------------------------------------------------------------------------------------------------
local function eachWindow(fn)
	local C, M = care(), menu()
	local menuGui = pg():FindFirstChild("NimbusMenu")
	local views = {
		{ "the Food Machine list", function()
			toClient("OpenPanel", "Pets", { Action = "Feed" })
		end, function()
			return careWin()
		end },
		{ "the garden picker", function()
			toClient("OpenPanel", "Pets", { Action = "Garden", Slot = 1 })
		end, function()
			return careWin()
		end },
		{ "the Training Place", function()
			toClient("OpenPanel", "Train", {})
		end, function()
			return careWin()
		end },
		{ "the EVOLVE confirm", function()
			C.ConfirmEvolve(P.READY)
		end, function()
			return careGui():FindFirstChild("CareConfirm")
		end },
		{ "the Pets panel", function()
			M.Open("Pets", { Key = P.TRAIN })
		end, function()
			return menuGui:FindFirstChild("Window_Inventory")
		end },
		{ "the Home window", function()
			M.Open("Home")
		end, function()
			return menuGui:FindFirstChild("Window_Home")
		end },
	}
	for _, v in ipairs(views) do
		closeAll()
		v[2]()
		advance(0.8)
		fn(v[1], v[3]())
	end
	closeAll()
end

S.client_p4careui_sizes = guarded("client_p4careui_sizes", function()
	local C = ready()
	if not C then
		return
	end
	sync({ Food = { Feast = 2 }, Legacy = true })
	local before = Mock.Viewport
	for _, size in ipairs({ { 1920, 1080 }, { 1280, 720 } }) do
		Mock.SetViewport(size[1], size[2])
		advance(0.4)
		eachWindow(function(label, root)
			local small = smallTexts(root, 18)
			T.check(root ~= nil and #small == 0, string.format("careui %dx%d: every text of %s is >= 18 design px", size[1], size[2], label), table.concat(small, ", "))
		end)
	end
	Mock.SetViewport(844, 390)
	advance(0.4)
	eachWindow(function(label, root)
		local small = smallOnScreen(root, 14)
		T.check(root ~= nil and #small == 0, "careui 844x390: every text of " .. label .. " is >= 14 px on screen", table.concat(small, ", "))
	end)
	Mock.SetViewport(before.X, before.Y)
	advance(0.4)
end)

S.client_p4careui_mobile = guarded("client_p4careui_mobile", function()
	local C = ready()
	if not C then
		return
	end
	sync({ Food = { Feast = 2 }, Legacy = true })
	eachWindow(function(label, root)
		local small = smallOnScreen(root, 14)
		T.check(root ~= nil and #small == 0, "careui phone 390x844: every text of " .. label .. " is >= 14 px on screen", table.concat(small, ", "))
	end)
	LocalPlayer:SetAttribute(Config.Attr.SpotIndex, nil)
	if plot then
		plot:Destroy()
		plot = nil
	end
	advance(0.3)
end)

return S
