-- smoke_p2_flow.lua: the END-TO-END home flow (ARCHITECTURE_V3.md "Phase 2: Tycoon homes" + "Phase 2 build contract",
-- rewritten for the "Phase 4 build contract": presses -> food plants, Collector -> Coin Magnet, Kitchen -> Food
-- Machine, Gym -> Training Place, rainbow coins): three simulated players play the homes together on the booted game,
-- through the same doors a client uses (ProximityPrompts, the HomeAction / PetCare / Fusion / BuyRoulette /
-- TutorialEvent / EquipPet / GoToSpot remotes, walking over coins, the home portal, MarketplaceService.ProcessReceipt)
-- while TycoonService, PetCareService, FusionService, GemService, TutorialService, SpotService, HomeBuilder, PetService
-- and DataService all run at once. Cash for the big purchases comes from DataService.AddCash (a stand-in for hours of
-- garden income, like tools/sim_tycoon.py). Payments are checked against Cash + the coins scooped meanwhile
-- (TycoonService.CoinsScooped): a player walking past their garden scoops it.
-- Loaded by tools/smoke.py in BOTH worlds (ARGS.context picks the half). In the server world the scenarios are chapters
-- of ONE story and run in order:
--   p2flow_arrive        Ann (new), Ben (new, an account where paid random items are restricted) and Cid (a v3 /
--                        Phase 1 save: Home.Rooms reserve, finished basics, an old SpotIndex) join: nobody gets a
--                        plot, Cash / Gems attributes, the policy state, the join toasts, Cid's migrated profile +
--                        ProfileSync and his tutorial resuming at the home chapter; Cid claims his old plot ('claim' ->
--                        'garden', the arrow on his free Pet Garden pad). Ann plays the basics chapter: the Home
--                        button opens her home portal toward a free gate (walk in, no claim), E at the gate, a lobby
--                        respawn at her home, the gift spin, a real Easy match, 'done' -> 'garden'. Ben skips the
--                        tutorial, claims a plot and can neither claim Ann's plot nor use her pads.
--   p2flow_build         Ann's home chapter: the free Pet Garden pad (the only pad of a fresh home), a pet in garden
--                        place 1 (HomeAction GardenSet, what the GardenSpotPrompt's picker sends) -> 'coins'; Ben's
--                        own Garden with a Combat pet (1/1.6 of the coins); a coin after one meal, Ben walking over
--                        Ann's pile scoops nothing, Ann's walk scoops it -> 'machine'; the arrow pad by pad (the
--                        Berry Bush makes bigger coins) to the Food Machine -> 'feed'; the locked Fusion Machine pad;
--                        the owner-only FeedPrompt opens the feed list, a 'Level up' batch levels the pet (one toast,
--                        the chapter's Cash reward once); the Training Place: TrainPrompt, a Combat pet in the Garden,
--                        Train (PetCare) with the lock (no equip, no garden place) and the automatic return to its
--                        place with rank 1. Ben levels his Berry Bush to the Cottage cap. Cid builds his Garden from
--                        the Home window, places a pet and leaves: his save is a Phase 4 home.
--   p2flow_prestige      Ann builds the home up pad by pad: the next house is refused below its Home Level, Villa /
--                        Manor / Sky Castle, until the Prestige pad unlocks; E on it only opens the confirmation;
--                        confirming: +1 star, Gems, Cash 0, stations reset but decor kept and the Pet Garden at Lv 1,
--                        garden place 4, the garden keeps making coins, a training job runs through the prestige.
--                        DataStore merge after the prestige: a stale prestige-0 write (station level, +Cash, +Gems,
--                        +Snacks) lands before this server saves: the prestiged Home and Cash win, Gems and Snacks add up.
--   p2flow_fusion_gems   After the prestige: the star prices, the Fusion Machine pad unlocks; three copies (one in the
--                        Garden, one equipped) fuse only next to the machine: the Golden copy takes over the garden
--                        place and the equipped place and makes x1.5 coins; gem packs through ProcessReceipt; the Storm
--                        Altar opens the Secret roulette; a gem spin; mixing that pet with the trained Combat pet makes a
--                        hybrid that takes its garden place and keeps its training ranks; the podium tag.
--   p2flow_rejoin        Ann leaves with coins on her lawn (kept as the bank) and her plot is cleared; Cid rejoins and
--                        claims Ann's old plot (his Garden comes back there, 'coins'); Ann rejoins ("Pick a free home"),
--                        every saved number is back, she claims another plot and the whole build is restored there
--                        (stations, the star, GardenPets, the FeedPrompt, income), an old gem receipt is still known.
--                        DataStore merge the other way: Ben's previous server lands a late Prestige-1 Home while he
--                        plays at Prestige 0 here: his live Home and the plot in the world follow it.
--   client_p2flow        (client) the flow's players end with a finished tutorial: the card shows the finale and
--                        leaves; a tutorial restarted afterwards in the same session shows its card and its world guide
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	------------------------------------------------------------------------------------------------
	-- client world: the tutorial card after the whole tutorial was finished (the flow's players end there)
	------------------------------------------------------------------------------------------------
	S.client_p2flow = guarded("client_p2flow", function()
		local KC = _G.KC
		if not T.check(type(KC) == "table" and type(KC.toClient) == "function", "client flow: (precondition) the client kit is loaded") then
			return
		end
		local advance, toClient = KC.advance, KC.toClient
		local Config = KC.env()
		local LocalPlayer = game:GetService("Players").LocalPlayer
		local function moduleAt(top, rest)
			local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
			if not inst then
				return nil
			end
			local ok, result = pcall(require, inst)
			return ok and type(result) == "table" and result or nil
		end
		local Steps = moduleAt("shared", "TutorialSteps")
		local TC = moduleAt("client", "Controllers/TutorialController")
		if not T.check(Steps ~= nil and TC ~= nil and type(TC.GetState) == "function", "client flow: (precondition) TutorialSteps and TutorialController load") then
			return
		end
		local function payload(index, over)
			local step = Steps.Steps[index]
			local text = tostring(step.Text):gsub("{GiftTokens}", tostring(Config.Tutorial.GiftTokens))
			text = text:gsub("{FinishTokens}", tostring(Config.Tutorial.FinishReward.Tokens))
			local st = {
				Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = text, Target = step.Target, Chapter = step.Chapter,
				CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, Gift = step.Gift == true,
				Done = false, Completed = false, Skipped = false, Reward = 0,
			}
			for k, v in pairs(over or {}) do
				st[k] = v
			end
			return st
		end
		local function panel()
			local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
			local g = pg and pg:FindFirstChild("NimbusTutorial")
			return g and g:FindFirstChild("TutorialPanel")
		end
		local function guideSign()
			local fx = workspace:FindFirstChild("ClientFx")
			return fx and fx:FindFirstChild("GuideSign", true)
		end
		Mock.SetViewport(1920, 1080)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		local errors0 = #Mock.Errors
		-- the home chapter's last step, then the whole tutorial completes: the finale, then the card leaves
		local last = #Steps.Steps
		toClient("TutorialState", payload(last))
		advance(3)
		T.check(panel() ~= nil and panel().Visible, "client flow: the card shows the home chapter's last step ('" .. Steps.Steps[last].Id .. "')")
		toClient("TutorialState", payload(last, { Done = true, Completed = true }))
		advance(1)
		T.check(panel() ~= nil and panel().Visible, "client flow: finishing the tutorial shows the finale on the card")
		advance(6)
		T.check(panel() ~= nil and not panel().Visible, "client flow: ...then the card leaves")
		-- the developer tools restart the tutorial in the same session: the card and the world guide come back
		local portal = (Steps.IndexOf and Steps.IndexOf.portal) or 7
		local target = { Kind = "Portal", Id = "Easy", Label = "Easy Portal", Position = Config.Lobby.Origin + Vector3.new(60, 0, 40) }
		toClient("TutorialState", payload(portal, { Target = target }))
		advance(2.5)
		local st = TC.GetState()
		T.check(panel() ~= nil and panel().Visible and st ~= nil and st.Id == "portal", "client flow: a tutorial restarted after the finale shows its card again")
		T.check(guideSign() ~= nil, "client flow: ...and its world guide (the floating sign over the target)")
		-- finished again (no Completed: no second finale)
		toClient("TutorialState", payload(last, { Done = true }))
		advance(1.5)
		T.check(panel() ~= nil and not panel().Visible, "client flow: a Done state without Completed just hides the card")
		T.eq(#Mock.Errors - errors0, 0, "client flow: no client script errors")
		if KC.flushErrors then
			KC.flushErrors("client_p2flow")
		end
	end)
	return S
end

local abs, floor, max, min = math.abs, math.floor, math.max, math.min
local advance, config, mod = K.advance, K.config, K.mod
local STAR = "\226\152\133"
local SECRET = "Secret"
local ALLOWED_WARNINGS = { "[DataService]", "[GemService]", "HomeBuilder is missing" }

-- the story's shared state (the scenarios are chapters of one flow)
local F = {
	ids = { Ann = 988001, Ben = 988002, Cid = 988003 },
	p = {}, -- name -> Player
	plot = {}, -- name -> plot index
	policy = {}, -- userId -> "allow" | "restrict"
}

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
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

local function svc()
	return {
		Ty = requireAt("server/Services/TycoonService"),
		Care = requireAt("server/Services/PetCareService"),
		Fuse = requireAt("server/Services/FusionService"),
		Gems = requireAt("server/Services/GemService"),
		HB = requireAt("server/Services/HomeBuilder"),
		TSv = mod("TutorialService"),
		DataS = mod("DataService"),
		PetS = mod("PetService"),
		SS = mod("SpotService"),
		MS = mod("MatchService"),
		TC = requireAt("shared/TycoonCatalog"),
		PK = requireAt("shared/PetKeys"),
		PC = K.M["shared/PetCatalog"],
		Steps = requireAt("shared/TutorialSteps"),
	}
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function storeKey(userId)
	return config().Tokens.DataStoreName .. "/u_" .. userId
end

local function stored(userId)
	return Mock.DataStore.Data[storeKey(userId)]
end

local function spots()
	return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
end

local function countKeys(map)
	local n = 0
	for _ in pairs(type(map) == "table" and map or {}) do
		n = n + 1
	end
	return n
end

local function mapText(map)
	local parts = {}
	for k, v in pairs(type(map) == "table" and map or {}) do
		parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function sameMap(a, b)
	return mapText(a) == mapText(b)
end

-- side toasts (Notify) to a player since `mark` whose text contains `needle` (plain text)
local function toasts(p, needle, mark, kind)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		local text = tostring(e.args[1])
		if text:find(needle, 1, true) and (kind == nil or e.args[2] == kind) then
			out[#out + 1] = text
		end
	end
	return out
end

local function toasted(p, needle, mark, kind)
	return #toasts(p, needle, mark, kind) > 0
end

local function lastSnapshot(p, mark)
	local list = K.remotesFor("ProfileSync", p.UserId, mark or 0)
	local e = list[#list]
	return e and e.args[1] or nil
end

local function cash(p)
	return mod("DataService").GetCash(p)
end

local function gems(p)
	return mod("DataService").GetGems(p)
end

local function tokens(p)
	return mod("DataService").GetTokens(p)
end

local function home(p)
	local Ty = requireAt("server/Services/TycoonService")
	return Ty and Ty.GetHome(p) or nil
end

local function level(p, id)
	local h = home(p)
	return (h and h.Stations and h.Stations[id]) or 0
end

-- tops the balance up to `amount` (a stand-in for the Collector income of the time it takes)
local function fund(p, amount)
	local have = cash(p)
	if amount > have then
		mod("DataService").AddCash(p, amount - have)
	end
end

local function join(name, wait)
	local p = Mock.AddPlayer(name, F.ids[name])
	advance(wait or 1.0)
	F.p[name] = p
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.8)
end

-- runs fn() while PetCatalog.RollPet always answers `petId` (the roulettes read the field at call time; remote
-- handlers run right away in the mock, so a remote call inside fn rolls the forced pet)
local function withRoll(petId, fn)
	local PC = K.M["shared/PetCatalog"]
	local original = PC.RollPet
	PC.RollPet = function()
		return petId
	end
	local ok, err = pcall(fn)
	PC.RollPet = original
	if not ok then
		error(err, 0)
	end
end

-- a Common Economy and a Common Combat pet of the Cloud Roulette's pool
local function petsByRole(PC)
	local eco, combat = nil, nil
	for _, def in ipairs(PC.ListByRarity("Common")) do
		if def.Role == "Economy" and not eco then
			eco = def
		elseif def.Role == "Combat" and not combat then
			combat = def
		end
	end
	return eco, combat
end

-- PolicyService double (the mock has no GetPolicyInfoForPlayerAsync): installed only while the players join
local PolS = game:GetService("PolicyService")
local MPS = game:GetService("MarketplaceService")
local function installPolicy()
	PolS.GetPolicyInfoForPlayerAsync = function(_, player)
		local mode = F.policy[player.UserId] or "allow"
		return { ArePaidRandomItemsRestricted = mode == "restrict", IsPaidItemTradingAllowed = true }
	end
end
local function removePolicy()
	PolS.GetPolicyInfoForPlayerAsync = nil
end

-- runs fn(...) in its own thread (it may yield): box.done / box.ok / box.result
local function spawnCall(fn, ...)
	local box = { done = false }
	local args = { n = select("#", ...), ... }
	task.spawn(function()
		local ok, result = pcall(fn, unpack(args, 1, args.n))
		box.ok, box.result, box.done = ok, result, true
	end)
	return box
end

----------------------------------------------------------------------------------------------------
-- plots, prompts, pads
----------------------------------------------------------------------------------------------------
local function attrUp(inst, name, depth)
	local node = inst
	for _ = 1, depth or 6 do
		if typeof(node) ~= "Instance" or node == workspace then
			return nil
		end
		local v = node:GetAttribute(name)
		if v ~= nil then
			return v
		end
		node = node.Parent
	end
	return nil
end

local function promptPosition(prompt)
	local parent = prompt and prompt.Parent
	if typeof(parent) ~= "Instance" then
		return nil
	end
	if parent:IsA("BasePart") then
		return parent.Position
	end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function claimPromptOf(index)
	local info = spots()[index]
	if info and info.Folder then
		for _, d in ipairs(info.Folder:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
				return d
			end
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" and d:GetAttribute("SpotIndex") == index then
			return d
		end
	end
	return nil
end

-- walks to the gate (just outside it) and presses E on its ClaimPrompt
local function claim(p, index)
	local SS = mod("SpotService")
	local gate = SS.GateCFrame(spots()[index])
	if gate and p.Character then
		Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
	end
	local prompt = claimPromptOf(index)
	if prompt then
		Mock.Trigger(prompt, p)
	end
	advance(0.6)
	return prompt ~= nil
end

local function freePlots(skip)
	local SS = mod("SpotService")
	local out = {}
	for i = 1, config().Lobby.SpotCount do
		if spots()[i] and not SS.GetOwner(i) and not (skip and skip[i]) then
			out[#out + 1] = i
		end
	end
	return out
end

-- the BuyPrompt of a station's pad on a plot (HomeBuilder's pads: the StationId attribute up the chain)
local function buyPrompt(info, id)
	if not info or not info.Folder then
		return nil
	end
	for _, d in ipairs(info.Folder:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "BuyPrompt" and attrUp(d, "StationId") == id then
			return d
		end
	end
	return nil
end

-- walks onto the pad and presses E (the prompt's cooldown is 0.2 s; one press per call)
local function pressPad(p, info, id)
	local prompt = buyPrompt(info, id)
	if not prompt then
		return false
	end
	local at = promptPosition(prompt)
	if at then
		Mock.Teleport(p, CFrame.new(at + Vector3.new(0, 3, 0)))
	end
	Mock.Trigger(prompt, p)
	advance(0.3)
	return true
end

local function stationModel(info, id)
	if not info or not info.Folder then
		return nil
	end
	for _, d in ipairs(info.Folder:GetDescendants()) do
		if d.Name == "Station_" .. id then
			return d
		end
	end
	return nil
end

local function stationIds(info)
	local out = {}
	if info and info.Folder then
		for _, d in ipairs(info.Folder:GetDescendants()) do
			local id = d.Name:match("^Station_(.+)$")
			if id then
				out[#out + 1] = id
			end
		end
	end
	table.sort(out)
	return out
end

local function pivotOf(model)
	if not model then
		return nil
	end
	if model:IsA("BasePart") then
		return model.CFrame
	end
	local ok, cf = pcall(function()
		return model:GetPivot()
	end)
	if ok then
		return cf
	end
	return nil
end

local function padPosition(info, id)
	local HB = requireAt("server/Services/HomeBuilder")
	local model = HB and HB.GetPad and HB.GetPad(info, id) or nil
	local cf = pivotOf(model)
	if cf then
		return cf.Position
	end
	local TC = requireAt("shared/TycoonCatalog")
	local def = TC and TC.Get(id)
	if def and def.Slot and def.Slot.Pad and info.PlotCFrame then
		return (info.PlotCFrame * def.Slot.Pad).Position
	end
	return nil
end

-- Phase 4: a care prompt (FeedPrompt on the Food Machine's Hopper, TrainPrompt on the Training Place) of a plot
local function carePrompt(info, stationId, name)
	local st = stationModel(info, stationId)
	if not st then
		return nil
	end
	for _, d in ipairs(st:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == name then
			return d
		end
	end
	return nil
end

-- the GardenSpotPrompt ("Put a pet here") of a garden place
local function gardenPrompt(info, slot)
	local st = stationModel(info, "Garden")
	if not st then
		return nil
	end
	for _, d in ipairs(st:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "GardenSpotPrompt" and d:GetAttribute("Slot") == slot then
			return d
		end
	end
	return nil
end

-- where garden place `slot` is (its Spot<slot> attachment, the point the tutorial arrow uses)
local function gardenSpotPos(info, slot)
	local st = stationModel(info, "Garden")
	local a = st and st:FindFirstChild("Spot" .. tostring(slot), true)
	if a and a:IsA("Attachment") then
		return a.WorldPosition
	end
	return nil
end

-- the plaza, far from every garden (nobody scoops coins there)
local function away(p)
	Mock.Teleport(p, CFrame.new(config().Lobby.Origin + Vector3.new(0, 4, 0)))
end

local function standAt(p, pos)
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 0)))
end

-- "x,y,z,yaw,closesAt" of the HomePortal attribute -> the portal's ground point
local function parsePortal(text)
	if type(text) ~= "string" then
		return nil
	end
	local parts = {}
	for n in text:gmatch("[^,]+") do
		parts[#parts + 1] = tonumber(n)
	end
	if #parts ~= 5 then
		return nil
	end
	return Vector3.new(parts[1], parts[2], parts[3])
end

-- every whole Cash amount a player scooped from the lawn (TycoonService.CoinsScooped) since the ledger started:
-- purchases are checked against Cash + scooped, because a player standing near the garden scoops by walking past
local function scoopLedger()
	local Ty = requireAt("server/Services/TycoonService")
	local totals = {}
	local conn = nil
	if Ty and Ty.CoinsScooped and Ty.CoinsScooped.Connect then
		conn = Ty.CoinsScooped:Connect(function(player, amount)
			if player then
				totals[player.UserId] = (totals[player.UserId] or 0) + (tonumber(amount) or 0)
			end
		end)
	end
	return {
		of = function(p)
			return totals[p.UserId] or 0
		end,
		stop = function()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end,
	}
end

local function givePet(p, key, n)
	local DataS = mod("DataService")
	local PK = requireAt("shared/PetKeys")
	local ok = PK.Add(DataS.GetProfile(p), key, n or 1)
	DataS.MarkDirty(p)
	return ok
end

-- the GardenPets text a home's Garden map should show ('1=a;2=b', slot order)
local function gardenText(garden)
	local slots = {}
	for slot in pairs(type(garden) == "table" and garden or {}) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	local parts = {}
	for _, slot in ipairs(slots) do
		parts[#parts + 1] = tostring(slot) .. "=" .. tostring(garden[slot])
	end
	return table.concat(parts, ";")
end

-- the cheapest unlocked, affordable-with-funding pad of a home (not the Prestige pad)
local function cheapestPad(TC, h)
	local best = nil
	for _, pad in ipairs(TC.AvailablePads(h)) do
		if not pad.Prestige and pad.Locked == nil and (not best or pad.Price < best.Price) then
			best = pad
		end
	end
	return best
end

----------------------------------------------------------------------------------------------------
-- tutorial
----------------------------------------------------------------------------------------------------
local function tut(p)
	local TSv = mod("TutorialService")
	return TSv and TSv.GetState(p) or nil
end

-- the current step id; "done!" once everything is finished (the basics' last step is called "done")
local function stepOf(p)
	local st = tut(p)
	if not st then
		return nil
	end
	if st.Done then
		return "done!"
	end
	return st.Id
end

local function tutEvent(p, eventName)
	advance(0.3) -- the remote is rate limited (0.25 s per player)
	Mock.FromClient(remote("TutorialEvent"), p, eventName)
	advance(0.3)
end

local function waitStep(p, id, seconds)
	K.waitFor(function()
		return stepOf(p) == id
	end, seconds or 3)
	return stepOf(p)
end

local function v3Profile(spotIndex, eco, combat)
	local now = os.time()
	return {
		Version = 2,
		Tokens = 340,
		Pets = { [eco] = 2, [combat] = 1 },
		Equipped = { eco },
		Items = { heal_cloud = 1 },
		Stats = { Matches = 6, Wins = 4, TokensEarned = 900, Spins = 3, BestTimes = { Easy = 95.5 } },
		SpotIndex = spotIndex,
		Discovered = { [eco] = true, [combat] = true },
		IndexClaimed = {},
		Tutorial = { Step = 10, Done = true, Gifted = true },
		-- the v3 reserve: Phase 1 saved these defaults (ARCHITECTURE_V3.md section 1)
		Cash = 0,
		Gems = 0,
		Home = { Level = 0, Rooms = {}, Prestige = 0 },
		PetLevels = {},
		UpdatedAt = now - 86400,
	}
end

----------------------------------------------------------------------------------------------------
-- p2flow_arrive
----------------------------------------------------------------------------------------------------
S.p2flow_arrive = guarded("p2flow_arrive", function()
	if not K.needBoot() then
		return
	end
	local X = svc()
	if not T.check(X.Ty and X.Care and X.Fuse and X.Gems and X.TC and X.PK and X.TSv and X.Steps and X.SS and X.MS and X.PetS,
		"flow: (precondition) TycoonService, PetCareService, FusionService, GemService, TutorialService and the Phase 2 catalogs load") then
		return
	end
	local Config = config()
	local DataS, SS, TSv, Ty, Gs = X.DataS, X.SS, X.TSv, X.Ty, X.Gems
	local ecoDef, combatDef = petsByRole(X.PC)
	if not T.check(ecoDef ~= nil and combatDef ~= nil, "flow: (precondition) the Cloud Roulette has a Common Economy and a Common Combat pet") then
		return
	end
	F.eco, F.combat = ecoDef.Id, combatDef.Id
	local errors0 = #Mock.Errors

	-- Cid played Phase 1: his save is a v3 profile (Home.Rooms reserve, finished basics, an auto-assigned plot)
	local free = freePlots()
	if not T.check(#free >= 3, "flow: (precondition) at least 3 plots are free", #free .. " free") then
		return
	end
	F.plot.Cid = free[#free]
	Mock.DataStore.Data[storeKey(F.ids.Cid)] = v3Profile(F.plot.Cid, F.eco, F.combat)
	F.policy[F.ids.Ben] = "restrict"

	installPolicy()
	local mark = K.logSize()
	local okJoin, errJoin = pcall(function()
		join("Ann")
		join("Ben")
		join("Cid")
	end)
	removePolicy() -- every account was looked up on join; the answers stay
	if not T.check(okJoin, "flow: three players join", tostring(errJoin)) then
		return
	end
	local ann, ben, cid = F.p.Ann, F.p.Ben, F.p.Cid
	advance(5) -- the join toasts come 4 s after the profile loaded

	-- nobody gets a plot on join
	for _, p in ipairs({ ann, ben, cid }) do
		T.check(SS.GetSpot(p) == nil and Ty.GetPlot(p) == nil and p:GetAttribute(Config.Attr.SpotIndex) == nil,
			"flow join: " .. p.Name .. " has no plot until pressing E at a gate")
	end
	T.check(ann:GetAttribute(Config.Attr.Cash) == 0 and ann:GetAttribute(Config.Attr.Gems) == 0 and ben:GetAttribute(Config.Attr.Cash) == 0,
		"flow join: new players show Cash 0 / Gems 0 on the HUD attributes")
	T.check(toasted(ann, "Pick a free home: press E at its gate", mark, "info") and toasted(ben, "Pick a free home", mark),
		"flow join: new players get the side toast 'Pick a free home: press E at its gate!'")
	T.check(not toasted(ann, "Welcome back", mark), "flow join: ...not 'Welcome back' (they never had a plot)")
	T.eq(Gs.PolicyState(ann), "Allowed", "flow join: Ann's account may buy random items (PolicyService)")
	T.eq(Gs.PolicyState(ben), "Restricted", "flow join: Ben's account may not (paid random items restricted)")
	T.check(ann:GetAttribute("PaidRandomItemsRestricted") == false and ben:GetAttribute("PaidRandomItemsRestricted") == true,
		"flow join: ...mirrored on the PaidRandomItemsRestricted attribute (the Shop hides gem roulettes for Ben)")
	local steps = X.Steps.Steps
	local stA = tut(ann)
	T.check(stA and stA.Id == "welcome" and stA.Step == 1 and stA.Total == #steps and stA.Done == false,
		"flow join: a new player's tutorial starts at 'welcome' (1/" .. #steps .. ")", stA and (tostring(stA.Id) .. " " .. tostring(stA.Step)) or "no state")

	-- Cid: the v3 profile migrated on load
	local cp = DataS.GetProfile(cid)
	if T.check(cp ~= nil, "flow migrate: (precondition) Cid's v3 profile loads") then
		local h = cp.Home
		T.check(type(h) == "table" and type(h.Stations) == "table" and h.Rooms == h.Stations and next(h.Stations) == nil
			and h.Prestige == 0 and h.Level == 0 and type(h.Garden) == "table" and type(h.Gym) == "table" and h.CollectorCash == 0,
			"flow migrate: Home.Rooms became the Phase 2 Home (Stations = Rooms, Garden, Gym, CollectorCash)")
		T.check(cp.Tokens == 340 and cp.Pets[F.eco] == 2 and cp.Pets[F.combat] == 1 and cp.Equipped[1] == F.eco and cp.Items.heal_cloud == 1
			and cp.Stats.Wins == 4 and cp.Stats.BestTimes.Easy == 95.5, "flow migrate: tokens, pets, equipped, items and stats are kept")
		T.check(type(cp.Food) == "table" and type(cp.Tiers) == "table" and type(cp.Hybrids) == "table" and type(cp.GemReceipts) == "table"
			and type(cp.PetLevels) == "table", "flow migrate: the new Phase 2 maps exist (Food, Tiers, Hybrids, GemReceipts, PetLevels)")
		T.check(cid:GetAttribute(Config.Attr.Cash) == 0 and cid:GetAttribute(Config.Attr.Gems) == 0 and cid:GetAttribute(Config.Attr.Tokens) == 340,
			"flow migrate: Cash / Gems / CloudTokens attributes")
		local snap = lastSnapshot(cid, mark)
		T.check(snap ~= nil and type(snap.Home) == "table" and snap.Home.Level == 0 and snap.Home.Prestige == 0 and type(snap.Home.Stations) == "table"
			and snap.Cash == 0 and type(snap.Food) == "table" and snap.Pets[F.eco] == 2,
			"flow migrate: Cid's ProfileSync carries the Phase 2 fields")
	end
	local stC = tut(cid)
	T.check(stC and stC.Id == "claim" and stC.Chapter == 2 and stC.Step == X.Steps.ChapterStart[2] and stC.Done == false,
		"flow migrate: a finished Phase 1 tutorial resumes at the home chapter ('claim')", stC and tostring(stC.Id) or "no state")
	T.check(toasted(cid, "Welcome back! Press E at your gate (#" .. F.plot.Cid .. ")", mark, "info"),
		"flow migrate: Cid's last plot (#" .. F.plot.Cid .. ") is free: 'Welcome back! Press E at your gate'")
	local sugg = SS.SuggestSpot(cid)
	T.check(sugg == spots()[F.plot.Cid], "flow migrate: ...and the guide / GoToSpot lead to that gate (SuggestSpot)")

	-- Cid claims his old plot: 'claim' -> 'garden' (Phase 4: the free Pet Garden comes first)
	claim(cid, F.plot.Cid)
	waitStep(cid, "garden", 3)
	local cidInfo = spots()[F.plot.Cid]
	T.check(SS.GetSpot(cid) == cidInfo and cidInfo.Folder:GetAttribute("OwnerUserId") == cid.UserId, "flow migrate: E at his gate gives Cid his old plot")
	T.eq(stepOf(cid), "garden", "flow migrate: ...and completes the tutorial's 'claim'")
	local stCp = tut(cid)
	local cidPad = padPosition(cidInfo, "Garden")
	T.check(stCp and stCp.Target and typeof(stCp.Target.Position) == "Vector3" and cidPad ~= nil and (stCp.Target.Position - cidPad).Magnitude < 1,
		"flow migrate: ...'garden' points at the free Pet Garden pad of his plot (he owns pets already)")

	-- Ann: the basics chapter, start to end
	T.eq(TSv.HandleEvent(ann, "ShopOpened"), false, "flow tutorial: an event of another step is refused")
	tutEvent(ann, "Next")
	T.eq(stepOf(ann), "home", "flow tutorial: Next -> 'home'")
	local st = tut(ann)
	local target = st and st.Target
	F.plot.Ann = target and target.SpotIndex
	local gate = F.plot.Ann and SS.GateCFrame(spots()[F.plot.Ann])
	if not T.check(type(target) == "table" and target.Kind == "Spot" and gate ~= nil and SS.GetOwner(F.plot.Ann) == nil
		and typeof(target.Position) == "Vector3" and (target.Position - gate.Position).Magnitude < 1,
		"flow tutorial: 'home' points at the gate of a free plot", target and tostring(target.SpotIndex) or "no target") then
		return
	end
	-- Phase 4: the Home button (GoToSpot) opens Ann's home portal; without a home it leads to a free gate
	mark = K.logSize()
	Mock.Teleport(ann, CFrame.new(Config.Lobby.Origin + Vector3.new(14, 4, 9))) -- (off the plaza centre: every gate is as near from there)
	advance(0.2)
	Mock.FromClient(remote("GoToSpot"), ann)
	advance(0.4)
	local portalAt = parsePortal(ann:GetAttribute(Config.Attr.HomePortal or "HomePortal"))
	T.check(portalAt ~= nil and SS.GetSpot(ann) == nil, "flow tutorial: the Home button (GoToSpot) opens Ann's home portal (HomePortal), no plot claimed",
		tostring(ann:GetAttribute(Config.Attr.HomePortal or "HomePortal")))
	if portalAt then
		standAt(ann, portalAt)
		advance(0.6)
	end
	local nearGate = math.huge
	for _, i in ipairs(freePlots()) do
		local g = SS.GateCFrame(spots()[i])
		if g and K.root(ann) then
			nearGate = min(nearGate, K.planar(K.root(ann).Position, g.Position))
		end
	end
	T.check(nearGate <= 12 and SS.GetSpot(ann) == nil and ann:GetAttribute(Config.Attr.HomePortal or "HomePortal") == nil,
		"flow tutorial: walking into it lands Ann at a free gate without claiming it (the portal closes)", string.format("%.1f studs", nearGate))
	T.check(toasted(ann, "Press E at the gate to claim this home", mark, "info"), "flow tutorial: ...'Press E at the gate to claim this home!'")
	mark = K.logSize()
	claim(ann, F.plot.Ann)
	waitStep(ann, "shop", 3)
	local annInfo = spots()[F.plot.Ann]
	T.check(SS.GetSpot(ann) == annInfo and Ty.GetPlot(ann) == annInfo and ann:GetAttribute(Config.Attr.SpotIndex) == F.plot.Ann,
		"flow tutorial: E at the gate claims the plot")
	T.eq(stepOf(ann), "shop", "flow tutorial: ...and completes 'home'")
	T.check(toasted(ann, "Welcome home", mark, "good"), "flow tutorial: ...with the 'Welcome home' toast")
	advance(1.2)
	T.check(annInfo.NameLabel.Text == ann.DisplayName and annInfo.SubLabel.Text == "Home Level 0", "flow tutorial: the nameplate shows Ann / 'Home Level 0'",
		tostring(annInfo.NameLabel.Text) .. " / " .. tostring(annInfo.SubLabel.Text))
	-- a lobby respawn now lands at her home
	Mock.Kill(ann)
	local back = K.waitFor(function()
		return ann.Character ~= nil and K.hum(ann) ~= nil and K.hum(ann).Health > 0
	end, 12)
	advance(0.8)
	T.check(back and K.root(ann) ~= nil and K.planar(K.root(ann).Position, annInfo.SpawnCFrame.Position) <= 10,
		"flow tutorial: a lobby respawn lands at the claimed home", K.root(ann) and string.format("%.1f studs", K.planar(K.root(ann).Position, annInfo.SpawnCFrame.Position)) or "no character")

	tutEvent(ann, "ShopOpened")
	T.eq(stepOf(ann), "spin", "flow tutorial: the Shop opened -> 'spin'")
	T.eq(tokens(ann), Config.Tutorial.GiftTokens, "flow tutorial: ...Nimbus gifts " .. Config.Tutorial.GiftTokens .. " Cloud Tokens")
	mark = K.logSize()
	withRoll(F.eco, function()
		Mock.FromClient(remote("BuyRoulette"), ann, "Cloud")
	end)
	advance(0.5)
	local ap = DataS.GetProfile(ann)
	local rolled = K.lastRemote("RouletteResult", ann.UserId, mark)
	T.check(rolled and rolled.args[1] and rolled.args[1].Ok == true and rolled.args[1].PetId == F.eco and ap.Pets[F.eco] == 1 and tokens(ann) == 0,
		"flow tutorial: the gift pays a Cloud Roulette spin (BuyRoulette remote): " .. F.eco)
	T.eq(ann:GetAttribute(Config.Attr.EquippedPets), F.eco, "flow tutorial: ...the very first pet is equipped")
	T.eq(stepOf(ann), "equip", "flow tutorial: the spin completes 'spin'")
	tutEvent(ann, "PetsOpened")
	T.eq(stepOf(ann), "index", "flow tutorial: opening Pets with the pet equipped completes 'equip'")
	tutEvent(ann, "IndexOpened")
	T.eq(stepOf(ann), "portal", "flow tutorial: the Index opened -> 'portal'")
	local match = K.startMatch("Easy", { ann })
	K.waitFor(function()
		return ann:GetAttribute(Config.Attr.InMatch) == true and stepOf(ann) ~= "portal"
	end, 10)
	T.eq(stepOf(ann), "finish", "flow tutorial: a real Easy match starts -> 'finish'")
	-- while Ann climbs, her plot stays hers
	mark = K.logSize()
	claim(ben, F.plot.Ann)
	T.check(SS.GetOwner(F.plot.Ann) == ann and SS.GetSpot(ben) == nil, "flow tutorial: Ben cannot claim Ann's plot while she is away in a match")
	T.check(toasted(ben, "belongs to " .. ann.DisplayName, mark, "bad"), "flow tutorial: ...the toast names the owner")
	if match then
		X.MS.LeaveMatch(ann)
	end
	K.waitFor(function()
		return stepOf(ann) ~= "finish"
	end, 10)
	T.eq(stepOf(ann), "done", "flow tutorial: back from the match -> 'done'")
	advance(2)
	local t0 = tokens(ann)
	mark = K.logSize()
	tutEvent(ann, "Next")
	waitStep(ann, "garden", 3)
	T.eq(tokens(ann), t0 + Config.Tutorial.FinishReward.Tokens, "flow tutorial: 'done' pays the basics reward (" .. Config.Tutorial.FinishReward.Tokens .. " tokens)")
	T.eq(stepOf(ann), "garden", "flow tutorial: the home chapter's 'claim' completes at once (Ann already has a home) -> 'garden'")
	local stP = tut(ann)
	local annPad = padPosition(annInfo, "Garden")
	T.check(stP and stP.Chapter == 2 and stP.Target and stP.Target.SpotIndex == F.plot.Ann and annPad ~= nil and typeof(stP.Target.Position) == "Vector3"
		and (stP.Target.Position - annPad).Magnitude < 1, "flow tutorial: ...the arrow points at the free Pet Garden pad of her plot")
	local stored1 = DataS.GetTutorial(ann)
	T.check(stored1 and stored1.Done == true and stored1.Step == X.Steps.IndexOf.garden, "flow tutorial: the stored progress: basics done, Step = 'garden'",
		stored1 and (tostring(stored1.Done) .. " / " .. tostring(stored1.Step)) or "nil")

	-- Ben: skips the tutorial, claims a plot, cannot touch Ann's
	local tb = tokens(ben)
	tutEvent(ben, "Skip")
	T.check(tut(ben) and tut(ben).Done == true and tokens(ben) == tb, "flow: Ben skips the tutorial (no rewards)")
	free = freePlots()
	F.plot.Ben = free[1]
	claim(ben, F.plot.Ben)
	local benInfo = spots()[F.plot.Ben]
	T.check(SS.GetSpot(ben) == benInfo and F.plot.Ben ~= F.plot.Ann and F.plot.Ben ~= F.plot.Cid, "flow: Ben claims a plot of his own (#" .. tostring(F.plot.Ben) .. ")")
	mark = K.logSize()
	claim(ben, F.plot.Cid)
	T.check(SS.GetSpot(ben) == benInfo and SS.GetOwner(F.plot.Cid) == cid and toasted(ben, "already have a home", mark, "bad"),
		"flow: a second claim is refused (one plot per player)")
	local annPad1 = buyPrompt(annInfo, "Garden")
	if T.check(annPad1 ~= nil and annPad1:GetAttribute("OwnerUserId") == ann.UserId, "flow: Ann's Pet Garden pad carries her OwnerUserId (HomeFx hides it for others)") then
		Mock.Trigger(annPad1, ben)
		advance(0.3)
		T.check(level(ann, "Garden") == 0 and level(ben, "Garden") == 0, "flow: Ben's E on Ann's pad builds nothing (for nobody)")
	end
	T.check(SS.GetOwner(F.plot.Ann) == ann and SS.GetOwner(F.plot.Ben) == ben and SS.GetOwner(F.plot.Cid) == cid,
		"flow: three plots, three owners")
	local mine = 0
	for i = errors0 + 1, #Mock.Errors do
		mine = mine + 1
	end
	T.eq(mine, 0, "flow arrive: no script errors")
	K.flushErrors("p2flow_arrive")
	K.flushWarnings("p2flow_arrive", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p2flow_build
----------------------------------------------------------------------------------------------------
S.p2flow_build = guarded("p2flow_build", function()
	if not K.needBoot() then
		return
	end
	local X = svc()
	local ann, ben, cid = F.p.Ann, F.p.Ben, F.p.Cid
	if not T.check(ann and ann.Parent and ben and ben.Parent and F.plot.Ann and F.plot.Ben and X.Ty and X.TC,
		"flow build: (precondition) Ann and Ben are in the game with their plots (p2flow_arrive)") then
		return
	end
	local ledger = scoopLedger()
	local okRun, errRun = pcall(function()
		local Config = config()
		local DataS, Ty, TC, PK = X.DataS, X.Ty, X.TC, X.PK
		local annInfo, benInfo = spots()[F.plot.Ann], spots()[F.plot.Ben]
		local meal = TC.Coins.MealSeconds

		-- the free Pet Garden (the only pad of a fresh home), then a pet in it: 'garden'
		local pads0 = TC.AvailablePads(home(ann))
		T.check(#pads0 == 1 and pads0[1].StationId == "Garden" and pads0[1].Price == 0, "flow build: Ann's fresh home shows one pad: the free Pet Garden", tostring(#pads0))
		local mark = K.logSize()
		pressPad(ann, annInfo, "Garden")
		T.check(level(ann, "Garden") == 1 and cash(ann) == 0, "flow build: E on the Pet Garden pad builds it for free")
		T.check(toasted(ann, "Built Pet Garden", mark, "good"), "flow build: ...'Built Pet Garden!' toast")
		advance(0.6)
		T.check(stationModel(annInfo, "Garden") ~= nil and annInfo.Folder:GetAttribute("GardenSlots") == 3,
			"flow build: ...the Garden stands on Ann's plot with 3 open places (GardenSlots)", tostring(annInfo.Folder:GetAttribute("GardenSlots")))
		T.eq(stepOf(ann), "garden", "flow build: the Garden alone does not finish 'garden' (a pet must sit in it)")
		local stG = tut(ann)
		local spot1 = gardenSpotPos(annInfo, 1)
		T.check(stG and stG.Target and typeof(stG.Target.Position) == "Vector3" and spot1 ~= nil and (stG.Target.Position - spot1).Magnitude < 1,
			"flow build: ...its arrow moves to garden place 1")
		local gp = gardenPrompt(annInfo, 1)
		T.check(gp ~= nil and gp.Enabled == true and gp:GetAttribute("OwnerUserId") == ann.UserId,
			"flow build: the empty place has Ann's 'Put a pet here' prompt (GardenSpotPrompt; the client's picker answers it)")
		mark = K.logSize()
		Mock.FromClient(remote("HomeAction"), ann, "GardenSet", { 1, F.eco })
		advance(0.4)
		T.check(home(ann).Garden[1] == F.eco and annInfo.Folder:GetAttribute("GardenPets") == "1=" .. F.eco,
			"flow build: the picker's HomeAction GardenSet puts the pet in place 1 (GardenPets on the plot)", tostring(annInfo.Folder:GetAttribute("GardenPets")))
		T.check(toasted(ann, "is working in your Garden", mark), "flow build: ...'<pet> is working in your Garden!'")
		waitStep(ann, "coins", 3)
		T.eq(stepOf(ann), "coins", "flow build: a pet in the Garden completes 'garden'")
		local gpTaken = gardenPrompt(annInfo, 1)
		T.check(gpTaken ~= nil and gpTaken.Enabled == false, "flow build: ...and the taken place's prompt turns off")

		-- Ben next door: his own free Garden with a Combat pet (any role works there; Combat earns 1/1.6)
		givePet(ben, F.combat, 1)
		pressPad(ben, benInfo, "Garden")
		Mock.FromClient(remote("HomeAction"), ben, "GardenSet", { 1, F.combat })
		advance(0.4)
		T.check(level(ben, "Garden") == 1 and home(ben).Garden[1] == F.combat, "flow build: Ben builds his own free Garden and puts a Combat pet in it (any role may work there)")
		local incA, incB = Ty.IncomePerSecond(ann), Ty.IncomePerSecond(ben)
		T.check(incA > 0 and incB > 0 and abs(incA / incB - 1.6) < 1e-6, "flow build: ...a Combat pet makes 1/1.6 of the coins of an Economy pet of the same rarity and level",
			incA .. " / " .. incB)

		-- rainbow coins: one per meal, only the owner scoops them: 'coins'
		away(ann)
		away(ben)
		advance(meal + 1.5)
		local piles = Ty.Piles(ann)
		local pile = piles and piles[1]
		T.check(pile ~= nil and pile.Coins >= 1 and typeof(pile.Pos) == "Vector3", "flow build: after one meal (" .. meal .. " s) Ann's pet popped a coin into its pile",
			pile and tostring(pile.Coins) or "no pile")
		T.check(tostring(annInfo.Folder:GetAttribute("CoinPiles")):match("^1=%d") ~= nil, "flow build: ...shown on the plot (CoinPiles)", tostring(annInfo.Folder:GetAttribute("CoinPiles")))
		if pile then
			advance(1.2)
			local stC = tut(ann)
			T.check(stC and stC.Target and typeof(stC.Target.Position) == "Vector3" and (stC.Target.Position - pile.Pos).Magnitude < 1, "flow build: 'coins' points at the pile")
			local bank0, cb0, lb0 = home(ann).CollectorCash, cash(ben), ledger.of(ben)
			standAt(ben, pile.Pos)
			advance(0.6)
			away(ben)
			T.check(cash(ben) == cb0 and ledger.of(ben) == lb0 and home(ann).CollectorCash >= bank0 - 1e-6, "flow build: Ben walking over Ann's coins scoops nothing")
			local c0, la0 = cash(ann), ledger.of(ann)
			local onLawn = floor(home(ann).CollectorCash)
			standAt(ann, pile.Pos)
			advance(0.4)
			away(ann)
			local gained = cash(ann) - c0
			T.check(onLawn > 0 and gained >= onLawn and gained == ledger.of(ann) - la0, "flow build: Ann walking over her pile scoops it (+$" .. gained .. ", CoinsScooped)",
				gained .. " of " .. onLawn)
			waitStep(ann, "machine", 3)
			T.eq(stepOf(ann), "machine", "flow build: scooping completes 'coins'")
		end

		-- the 'machine' arrow, pad by pad: the Berry Bush on the way (plants make bigger coins), then the Food Machine
		local path, lost, foodUp = {}, nil, nil
		for _ = 1, 30 do
			if stepOf(ann) ~= "machine" then
				break
			end
			local stK = tut(ann)
			local nextPad = nil
			for _, padDef in ipairs(TC.AvailablePads(home(ann))) do
				local pos = padPosition(annInfo, padDef.StationId)
				if padDef.Locked == nil and pos and stK.Target and typeof(stK.Target.Position) == "Vector3" and (pos - stK.Target.Position).Magnitude < 0.5 then
					nextPad = padDef
				end
			end
			if not nextPad then
				lost = tostring(stK and stK.Hint)
				break
			end
			fund(ann, nextPad.Price)
			local before = level(ann, nextPad.StationId)
			local inc0 = Ty.IncomePerSecond(ann)
			pressPad(ann, annInfo, nextPad.StationId)
			path[#path + 1] = nextPad.StationId
			if level(ann, nextPad.StationId) ~= before + 1 then
				lost = nextPad.StationId .. " was not built"
				break
			end
			if nextPad.StationId == "Press1" then
				foodUp = Ty.IncomePerSecond(ann) > inc0
			end
		end
		away(ann)
		T.check(lost == nil and path[#path] == "Kitchen", "flow build: following the 'machine' arrow pad by pad builds the Food Machine", table.concat(path, " > ") .. (lost and (" (lost: " .. lost .. ")") or ""))
		T.check(foodUp == true, "flow build: ...with the Berry Bush on the way (every coin bigger: IncomePerSecond up)")
		waitStep(ann, "feed", 3)
		T.eq(stepOf(ann), "feed", "flow build: the Food Machine completes 'machine'")

		-- the player's rule: the Fusion Machine pad is a locked silhouette until Prestige 1
		local fusionPrompt = buyPrompt(annInfo, "FusionMachine")
		local fusionPad = X.HB and X.HB.GetPad and X.HB.GetPad(annInfo, "FusionMachine") or nil
		if T.check(fusionPrompt ~= nil, "flow build: with the Food Machine built, the Fusion Machine pad appears") then
			T.check(fusionPrompt.Enabled == false and fusionPad ~= nil and fusionPad:GetAttribute("Locked") == "Unlocks at Prestige 1",
				"flow build: ...locked: 'Unlocks at Prestige 1' (its prompt is off)", fusionPad and tostring(fusionPad:GetAttribute("Locked")) or "no pad model")
			T.check(annInfo.Folder:FindFirstChild("Ghost_FusionMachine", true) ~= nil, "flow build: ...with the machine's silhouette on the yard")
			fund(ann, TC.PriceFor("FusionMachine", 1))
			local c = cash(ann)
			mark = K.logSize()
			Mock.Trigger(fusionPrompt, ann) -- (a forged press: the engine does not fire a disabled prompt)
			advance(0.3)
			away(ann)
			T.check(level(ann, "FusionMachine") == 0 and cash(ann) == c and toasted(ann, "Unlocks at Prestige 1", mark, "bad"),
				"flow build: a forced press on it builds nothing, takes nothing and says why")
		end

		-- E at the Food Machine (owner only) opens the feed list; the list's Feed button is the PetCare remote
		advance(1.2) -- PetCareService dresses the machine's prompts on its next tick
		local feedPrompt = carePrompt(annInfo, "Kitchen", "FeedPrompt")
		if T.check(feedPrompt ~= nil and feedPrompt:GetAttribute("OwnerUserId") == ann.UserId and feedPrompt.Parent and feedPrompt.Parent.Name == "Hopper",
			"flow build: the Food Machine has Ann's 'Feed pets' prompt on its Hopper", feedPrompt and feedPrompt.Parent and feedPrompt.Parent.Name or "no prompt") then
			local at = promptPosition(feedPrompt)
			mark = K.logSize()
			if at then
				Mock.Teleport(ben, CFrame.new(at + Vector3.new(0, 0, -3)))
			end
			Mock.Trigger(feedPrompt, ben)
			advance(0.3)
			away(ben)
			T.eq(#K.remotesFor("OpenPanel", ben.UserId, mark), 0, "flow build: Ben's E on Ann's Food Machine opens nothing")
			if at then
				Mock.Teleport(ann, CFrame.new(at + Vector3.new(0, 0, -3)))
			end
			Mock.Trigger(feedPrompt, ann)
			advance(0.3)
			away(ann)
			local op = K.lastRemote("OpenPanel", ann.UserId, mark)
			T.check(op ~= nil and op.args[1] == "Pets" and type(op.args[2]) == "table" and op.args[2].Action == "Feed", "flow build: Ann's E opens her Pets panel on Feed (OpenPanel)")
			local stF = tut(ann)
			local machineAt = pivotOf(stationModel(annInfo, "Kitchen"))
			T.check(stF and stF.Target and typeof(stF.Target.Position) == "Vector3" and machineAt ~= nil and K.planar(stF.Target.Position, machineAt.Position) <= 16,
				"flow build: 'feed' points at the Food Machine (its front)", stF and stF.Target and machineAt and string.format("%.1f studs", K.planar(stF.Target.Position, machineAt.Position)) or "")
		end
		-- a 'Level up' batch: machine feeds until Lv 2, each priced at the level it is eaten at (no leftovers yet)
		local ecoDef = X.PC.Get(F.eco)
		local lv0, xp0 = DataS.GetPetLevel(ann, F.eco)
		local machineLevel = level(ann, "Kitchen")
		local feeds, price, xp = 0, 0, xp0 or 0
		while feeds < 10 and xp < TC.XpToNext(lv0) do
			xp = xp + TC.FeedXp(lv0, machineLevel)
			price = price + TC.FeedPrice(ecoDef, lv0)
			feeds = feeds + 1
		end
		fund(ann, price)
		local c1 = cash(ann)
		local income1 = Ty.IncomePerSecond(ann)
		mark = K.logSize()
		Mock.FromClient(remote("PetCare"), ann, "Feed", F.eco, { Count = feeds })
		advance(0.6)
		local lv = DataS.GetPetLevel(ann, F.eco)
		T.check(lv0 == 1 and lv == 2, "flow build: a 'Level up' batch of " .. feeds .. " machine feeds levels the pet to 2", tostring(lv0) .. " -> " .. tostring(lv))
		T.eq(#toasts(ann, "reached Lv 2", mark), 1, "flow build: ...with one level-up toast")
		local stDone = tut(ann)
		-- (Phase 3 appends the pet-battle chapter: the home chapter's end moves on to it instead of finishing everything)
		T.check(stDone and ((stDone.Done == true and stDone.Completed == true) or (stDone.Chapter or 0) >= 3),
			"flow build: feeding a pet ends the home chapter (the tutorial is done, or on to the battle chapter)")
		T.eq(cash(ann), c1 - price + 1000, "flow build: ...the feeds cost $" .. price .. " and the home chapter pays its Cash reward (once)")
		advance(1.2)
		T.check(Ty.IncomePerSecond(ann) > income1, "flow build: the garden coins follow the pet's level", income1 .. " -> " .. Ty.IncomePerSecond(ann))

		-- the Training Place: a Combat pet from the roulette trains there (Phase 4: no more Gym slots)
		DataS.AddTokens(ann, 50)
		withRoll(F.combat, function()
			advance(0.3)
			Mock.FromClient(remote("BuyRoulette"), ann, "Cloud")
		end)
		advance(0.5)
		T.eq(PK.Count(DataS.GetProfile(ann), F.combat), 1, "flow train: a Combat pet from the Cloud Roulette (" .. F.combat .. ")")
		fund(ann, TC.PriceFor("Gym", 1))
		pressPad(ann, annInfo, "Gym")
		away(ann)
		T.check(level(ann, "Gym") == 1 and stationModel(annInfo, "Gym") ~= nil, "flow train: the Training Place pad builds it")
		local arenaPrompt = buyPrompt(annInfo, "ArenaGate")
		local arenaPad = X.HB and X.HB.GetPad and X.HB.GetPad(annInfo, "ArenaGate") or nil
		T.check(arenaPrompt ~= nil and arenaPrompt.Enabled == true and arenaPad ~= nil and (arenaPad:GetAttribute("Locked") or "") == "",
			"flow train: ...and the Arena Gate pad shows up, buyable (Phase 3)", arenaPad and tostring(arenaPad:GetAttribute("Locked")) or "no pad")
		advance(1.2)
		local trainPrompt = carePrompt(annInfo, "Gym", "TrainPrompt")
		if T.check(trainPrompt ~= nil and trainPrompt:GetAttribute("OwnerUserId") == ann.UserId, "flow train: the Training Place has Ann's 'Train pets' prompt") then
			local at = promptPosition(trainPrompt)
			if at then
				Mock.Teleport(ann, CFrame.new(at + Vector3.new(0, 0, -3)))
			end
			mark = K.logSize()
			Mock.Trigger(trainPrompt, ann)
			advance(0.3)
			away(ann)
			local op = K.lastRemote("OpenPanel", ann.UserId, mark)
			T.check(op ~= nil and op.args[1] == "Train", "flow train: ...E opens the training window (OpenPanel 'Train')")
		end
		-- any role works in the Garden now: the Combat pet takes place 2
		Mock.FromClient(remote("HomeAction"), ann, "GardenSet", { 2, F.combat })
		advance(0.4)
		T.check(home(ann).Garden[2] == F.combat and annInfo.Folder:GetAttribute("GardenPets") == "1=" .. F.eco .. ";2=" .. F.combat,
			"flow train: the Combat pet works in garden place 2 (GardenPets)", tostring(annInfo.Folder:GetAttribute("GardenPets")))
		local combatDef = X.PC.Get(F.combat)
		local cost = TC.TrainCost(combatDef, 1)
		fund(ann, cost)
		local c2 = cash(ann)
		mark = K.logSize()
		Mock.FromClient(remote("PetCare"), ann, "Train", F.combat, "Physique")
		advance(0.4)
		local g = DataS.GetGrowth(ann, F.combat)
		local job = g and g.Job
		T.check(type(job) == "table" and job.Stat == "Physique" and job.Rank == 1 and c2 - cash(ann) == cost,
			"flow train: Train (PetCare) starts Physique rank 1 for $" .. tostring(cost), job and (tostring(job.Stat) .. " " .. tostring(job.Rank)) or "no job")
		T.check(toasted(ann, "started Physique training", mark), "flow train: ...'started Physique training' toast")
		T.check(home(ann).Garden[2] == nil and type(job) == "table" and job.From == "Garden:2", "flow train: ...the trainee leaves its garden place and remembers it (From 'Garden:2')",
			job and tostring(job.From) or "")
		T.check(tostring(annInfo.Folder:GetAttribute("TrainingPets")):find(F.combat .. ":Physique:", 1, true) ~= nil, "flow train: ...shown on the plot (TrainingPets)",
			tostring(annInfo.Folder:GetAttribute("TrainingPets")))
		-- the training lock: neither equipped nor in the Garden while it trains
		mark = K.logSize()
		advance(1.6)
		Mock.FromClient(remote("EquipPet"), ann, F.combat)
		advance(0.4)
		Mock.FromClient(remote("HomeAction"), ann, "GardenSet", { 2, F.combat })
		advance(0.4)
		local eq = DataS.GetProfile(ann).Equipped
		local isEq = false
		for _, k in ipairs(eq) do
			isEq = isEq or k == F.combat
		end
		T.check(not isEq and home(ann).Garden[2] == nil and toasted(ann, "is training", mark), "flow train: a training pet can be neither equipped nor put in the Garden ('is training')")
		-- done after its time: rank 1, back in its place by itself
		mark = K.logSize()
		advance(TC.TrainSeconds(1) + 2)
		g = DataS.GetGrowth(ann, F.combat)
		T.check(g and g.Physique == 1 and g.Job == nil, "flow train: after " .. TC.TrainSeconds(1) .. " s the pet has Physique rank 1", g and tostring(g.Physique) or "")
		T.check(home(ann).Garden[2] == F.combat and toasted(ann, "finished Physique training", mark), "flow train: ...and is back in garden place 2 by itself (with a toast)")

		-- Ben's home ran on its own the whole time
		T.check(home(ben).CollectorCash > 0 and ledger.of(ben) == 0 and level(ben, "Kitchen") == 0, "flow build: Ben's garden made his own coins meanwhile (nothing of Ann's)",
			tostring(home(ben).CollectorCash))
		-- the house tier caps the plants: Ben's Cottage takes the Berry Bush to Lv 6, the 7th level needs the Villa
		local cap = TC.MaxLevelAt("Press1", home(ben))
		local upTo = {}
		for _ = level(ben, "Press1") + 1, cap do
			local nextLv = level(ben, "Press1") + 1
			fund(ben, TC.PriceFor("Press1", nextLv))
			pressPad(ben, benInfo, "Press1")
			upTo[#upTo + 1] = level(ben, "Press1")
		end
		T.check(cap == 6 and level(ben, "Press1") == cap, "flow build: Ben levels his Berry Bush to the Cottage's cap (Lv " .. tostring(cap) .. ") with E", table.concat(upTo, ","))
		local benPadModel = X.HB and X.HB.GetPad and X.HB.GetPad(benInfo, "Press1") or nil
		T.check(benPadModel ~= nil and benPadModel:GetAttribute("Locked") == "Needs the Villa" and buyPrompt(benInfo, "Press1").Enabled == false,
			"flow build: ...then its pad reads 'Needs the Villa' (prompt off)", benPadModel and tostring(benPadModel:GetAttribute("Locked")) or "no pad")
		fund(ben, TC.PriceFor("Press1", cap + 1))
		local cBen2, lBen2 = cash(ben), ledger.of(ben)
		mark = K.logSize()
		advance(1.6)
		pressPad(ben, benInfo, "Press1")
		T.check(level(ben, "Press1") == cap and cash(ben) - (ledger.of(ben) - lBen2) == cBen2 and toasted(ben, "Needs the Villa", mark, "bad"),
			"flow build: ...and a forced press is refused with that reason (nothing paid)")
		away(ben)
		DataS.SpendCash(ben, cash(ben)) -- (back to an empty wallet)

		-- Cid: his free Garden from the Home window (HomeAction Upgrade), a pet in it, then he leaves
		if cid and cid.Parent and F.plot.Cid then
			Mock.FromClient(remote("HomeAction"), cid, "Upgrade", "Garden")
			advance(0.6)
			T.eq(level(cid, "Garden"), 1, "flow migrate: Cid builds his Pet Garden from the Home window (HomeAction Upgrade)")
			Mock.FromClient(remote("HomeAction"), cid, "GardenSet", { 1, F.eco })
			advance(0.4)
			waitStep(cid, "coins", 3)
			T.eq(stepOf(cid), "coins", "flow migrate: ...puts a pet in it and his tutorial moves on ('coins')")
			leave(cid)
			advance(1.5)
			local rec = stored(F.ids.Cid) or {}
			local rh = type(rec.Home) == "table" and rec.Home or {}
			T.check(rec.Version == 2 and type(rh.Stations) == "table" and rh.Stations.Garden == 1 and type(rh.Garden) == "table" and rh.Garden[1] == F.eco
				and rh.Rooms == nil and rh.Prestige == 0 and rh.Level == 1, "flow migrate: Cid's save is a Phase 4 home now (Home.Stations with the Garden, its pet, no Rooms)", mapText(rh.Stations))
			T.check(type(rec.Migrations) == "table" and rec.Migrations.P4 == true, "flow migrate: ...marked migrated (Migrations.P4)")
			T.check(rec.SpotIndex == F.plot.Cid and type(rec.Tutorial) == "table" and rec.Tutorial.Step == X.Steps.IndexOf.coins and rec.Tokens == 340,
				"flow migrate: ...with his plot, tutorial progress and tokens")
			T.eq(spots()[F.plot.Cid].NameLabel.Text, "Free home", "flow migrate: his plot is free again")
		end
	end)
	ledger.stop()
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p2flow_build")
	K.flushWarnings("p2flow_build", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p2flow_prestige
----------------------------------------------------------------------------------------------------
S.p2flow_prestige = guarded("p2flow_prestige", function()
	if not K.needBoot() then
		return
	end
	local X = svc()
	local ann = F.p.Ann
	if not T.check(ann and ann.Parent and F.plot.Ann and level(ann, "Kitchen") >= 1, "flow prestige: (precondition) Ann has her plot with a Food Machine (p2flow_build)") then
		return
	end
	-- (Ann scoops her coins whenever she walks past them: every payment below is checked against Cash + scooped)
	local ledger = scoopLedger()
	local okRun, errRun = pcall(function()
		local DataS, Ty, TC = X.DataS, X.Ty, X.TC
		local annInfo = spots()[F.plot.Ann]
		local mark = K.logSize()

		-- pad by pad up to the Prestige pad (the next house first whenever it is open, then the cheapest pad)
		local problems, gateRefused = {}, {}
		local purchases = 0
		for _ = 1, 300 do
			local h = home(ann)
			if TC.CanPrestige(h) then
				break
			end
			local housePad = nil
			for _, padDef in ipairs(TC.AvailablePads(h)) do
				if padDef.StationId == "House" then
					housePad = padDef
				end
				if padDef.StationId == "House" and padDef.Locked and padDef.Locked:find("Reach Home Level", 1, true) and not gateRefused[padDef.NextLevel] then
					-- the next house below its Home Level: refused even with the Cash in hand
					gateRefused[padDef.NextLevel] = true
					fund(ann, padDef.Price)
					local c, l0 = cash(ann), ledger.of(ann)
					local m = K.logSize()
					advance(1.6) -- (the same refusal text is not repeated within 1.5 s)
					pressPad(ann, annInfo, "House")
					if level(ann, "House") ~= padDef.Level or cash(ann) - (ledger.of(ann) - l0) ~= c or not toasted(ann, padDef.Locked, m, "bad") then
						problems[#problems + 1] = "the " .. tostring(padDef.Title) .. " was not refused below " .. padDef.Locked
					end
				end
			end
			local best = (housePad and housePad.Locked == nil) and housePad or cheapestPad(TC, h)
			if not best then
				problems[#problems + 1] = "dead end at Home Level " .. TC.HomeLevelOf(h)
				break
			end
			fund(ann, best.Price)
			local c, l0 = cash(ann), ledger.of(ann)
			local before = level(ann, best.StationId)
			if not pressPad(ann, annInfo, best.StationId) then
				problems[#problems + 1] = "no pad for " .. best.StationId
				break
			end
			purchases = purchases + 1
			local paid = c + (ledger.of(ann) - l0) - cash(ann)
			if level(ann, best.StationId) ~= before + 1 or paid ~= best.Price then
				problems[#problems + 1] = best.StationId .. " Lv " .. (before + 1) .. ": paid " .. paid .. " of " .. tostring(best.Price)
				break
			end
		end
		away(ann)
		local h = home(ann)
		T.check(#problems == 0, "flow prestige: " .. purchases .. " purchases with E on the pads, each for exactly its price", table.concat(problems, " | "))
		T.check(gateRefused[2] and gateRefused[3] and gateRefused[4], "flow prestige: the Villa, Manor and Sky Castle pads refuse below Home Level 10 / 20 / 30 (toast, nothing paid)",
			"refused: " .. mapText(gateRefused))
		for _, name in ipairs({ "Villa", "Manor", "Sky Castle" }) do
			T.check(toasted(ann, name .. " built!", mark, "good"), "flow prestige: '" .. name .. " built!' toast")
		end
		T.check(toasted(ann, "Prestige is ready", mark, "good"), "flow prestige: 'Prestige is ready at your home!' toast")
		T.check(TC.CanPrestige(h) and TC.HomeLevelOf(h) >= 40 and level(ann, "House") == 4, "flow prestige: the Sky Castle at Home Level " .. TC.HomeLevelOf(h))
		local prestigePad = buyPrompt(annInfo, "Prestige")
		if not T.check(prestigePad ~= nil, "flow prestige: the Prestige pad appears on the plot") then
			return
		end
		T.eq(TC.GardenSlots(h), 3, "flow prestige: 3 garden places before the first Prestige")

		-- a training job running through the prestige (Phase 4: Prestige keeps every training job)
		local combatDef = X.PC.Get(F.combat)
		fund(ann, TC.TrainCost(combatDef, 1) or 0)
		local mTrain = K.logSize()
		advance(0.3)
		Mock.FromClient(remote("PetCare"), ann, "Train", F.combat, "Speed")
		advance(0.4)
		local jobBefore = DataS.GetGrowth(ann, F.combat).Job
		T.check(type(jobBefore) == "table" and jobBefore.Stat == "Speed" and jobBefore.From == "Garden:2", "flow prestige: (here) the Combat pet starts Speed training from garden place 2",
			table.concat(toasts(ann, "", mTrain), " | "))

		-- E on the Prestige pad only asks: a reset of the whole build is never one key press
		DataS.AddCash(ann, 12345)
		DataS.Save(ann) -- the store holds the build of Home Level 40
		local before = {
			Cash = cash(ann), Gems = gems(ann), Stations = home(ann).Stations, Garden = home(ann).Garden,
			Snack = DataS.GetFood(ann, "Snack"), Eco = X.PK.Count(DataS.GetProfile(ann), F.eco), Level = TC.HomeLevelOf(home(ann)),
			EcoLevel = DataS.GetPetLevel(ann, F.eco), Physique = DataS.GetGrowth(ann, F.combat).Physique,
		}
		T.check(prestigePad.ActionText == "Prestige" and prestigePad.HoldDuration >= 1, "flow prestige: the Prestige pad's prompt says 'Prestige' and needs a long hold",
			tostring(prestigePad.ActionText) .. " / " .. tostring(prestigePad.HoldDuration))
		mark = K.logSize()
		local l1 = ledger.of(ann)
		pressPad(ann, annInfo, "Prestige")
		away(ann)
		local asked = K.remotesFor("OpenPanel", ann.UserId, mark)
		local ask = asked[#asked]
		T.check(home(ann).Prestige == 0 and cash(ann) - (ledger.of(ann) - l1) == before.Cash and ask ~= nil and ask.args[1] == "Home" and type(ask.args[2]) == "table" and ask.args[2].Action == "Prestige",
			"flow prestige: E on the Prestige pad resets nothing: it opens the Home window on the prestige confirmation", tostring(home(ann).Prestige) .. " / " .. cash(ann) .. " / " .. #asked .. " OpenPanel")
		-- the Home window's confirm button
		advance(1.1)
		Mock.FromClient(remote("HomeAction"), ann, "Prestige")
		advance(0.3)
		local after = home(ann)
		T.check(after.Prestige == 1 and cash(ann) == 0 and after.CollectorCash == 0 and gems(ann) == before.Gems + TC.PrestigeGems(1),
			"flow prestige: confirming in the Home window (HomeAction 'Prestige'): +1 star, Cash 0, no coins left, +" .. TC.PrestigeGems(1) .. " Gems",
			tostring(after.Prestige) .. " / " .. cash(ann) .. " / " .. gems(ann))
		local want = TC.StationsAfterPrestige(before.Stations)
		local wrong = {}
		for _, def in ipairs(TC.Stations) do
			if (after.Stations[def.Id] or 0) ~= (want[def.Id] or 0) then
				wrong[#wrong + 1] = def.Id .. "=" .. tostring(after.Stations[def.Id])
			end
		end
		T.check(#wrong == 0 and (after.Stations.Garden or 0) == 1, "flow prestige: stations reset, decor kept, the Pet Garden stays built at Lv 1", table.concat(wrong, ","))
		T.check(sameMap(after.Garden, before.Garden) and DataS.GetFood(ann, "Snack") == before.Snack and X.PK.Count(DataS.GetProfile(ann), F.eco) == before.Eco
			and DataS.GetPetLevel(ann, F.eco) == before.EcoLevel, "flow prestige: the garden places, food, pets and pet levels are kept")
		T.check(toasted(ann, "Prestige 1!", mark, "good") and toasted(ann, "Fusion Machine unlocked", mark, "good"), "flow prestige: 'Prestige 1!' and 'Fusion Machine unlocked' toasts")
		T.check(TC.GardenSlots(after) == 4 and toasted(ann, "Garden place 4 unlocked", mark), "flow prestige: ...and garden place 4 opens ('Garden place 4 unlocked!')")
		local jobAfter = DataS.GetGrowth(ann, F.combat).Job
		T.check(type(jobAfter) == "table" and jobAfter.Stat == "Speed" and jobAfter.Ends == jobBefore.Ends and DataS.GetGrowth(ann, F.combat).Physique == before.Physique,
			"flow prestige: the training job and the earned ranks survive the prestige")
		advance(1.2)
		T.check(annInfo.SubLabel.Text:find(STAR, 1, true) ~= nil and annInfo.Folder:GetAttribute("Prestige") == 1 and annInfo.Folder:GetAttribute("GardenSlots") == 4,
			"flow prestige: the nameplate shows the star (Prestige 1, GardenSlots 4 on the plot)", annInfo.SubLabel.Text)
		T.check(stationModel(annInfo, "Press1") == nil and stationModel(annInfo, "House") == nil and stationModel(annInfo, "Garden") ~= nil,
			"flow prestige: the reset stations leave the plot, the Pet Garden stays")
		T.check(Ty.IncomePerSecond(ann) > 0, "flow prestige: the garden pets keep making coins right away (the coins never stop)", tostring(Ty.IncomePerSecond(ann)))
		-- the job ends after the prestige: the pet comes back to its place
		advance(TC.TrainSeconds(1) + 2)
		away(ann)
		local gDone = DataS.GetGrowth(ann, F.combat)
		T.check(gDone.Speed == 1 and gDone.Job == nil and home(ann).Garden[2] == F.combat, "flow prestige: the job finishes after the prestige (Speed rank 1) and the pet is back in place 2")
		local cashNow = cash(ann)

		-- DataStore merge after the prestige: a stale server's late write lands (Ann's previous session, at prestige 0:
		-- an extra Vault level, +5000 Cash, +7 Gems, +2 Snacks). Its Home edits and its Cash belong to the run this prestige
		-- reset, so neither survives (the prestige rule); Gems and Food always travel as deltas. While the store is still at
		-- prestige 0 this server's merge decides that; when an autosave of this server already stored the prestige, the
		-- stale server's own merge does (it keeps only its Gems / Food deltas), so the record gets just those. Either way
		-- the outcome below is the same.
		local rec = stored(ann.UserId)
		if T.check(type(rec) == "table" and type(rec.Home) == "table", "flow merge: (precondition) Ann has a save") then
			local storeAtZero = (rec.Home.Prestige or 0) == 0
			T.info("flow merge: the stale write lands " .. (storeAtZero and "before this server saved the prestige" or "after an autosave stored the prestige"))
			if storeAtZero then
				rec.Home.Stations = type(rec.Home.Stations) == "table" and rec.Home.Stations or {}
				rec.Home.Stations.Vault = min(5, (rec.Home.Stations.Vault or 0) + 1)
				rec.Home.Level = (rec.Home.Level or 0) + 1
				rec.Cash = (rec.Cash or 0) + 5000
			end
			rec.Gems = (rec.Gems or 0) + 7
			rec.Food = type(rec.Food) == "table" and rec.Food or {}
			rec.Food.Snack = (rec.Food.Snack or 0) + 2
			DataS.Save(ann)
			local s = stored(ann.UserId) or {}
			local sh = type(s.Home) == "table" and s.Home or {}
			T.check(sh.Prestige == 1 and sameMap(sh.Stations, home(ann).Stations) and (sh.Stations.Vault or 0) == (home(ann).Stations.Vault or 0),
				"flow merge: the prestiged Home wins whole (the stale write's station levels do not come back)", mapText(sh.Stations))
			T.eq(s.Cash, cashNow, "flow merge: Cash follows the prestige: the stale server's +5000 belonged to the reset run (only this run's balance is stored)")
			T.eq(s.Gems, before.Gems + 7 + TC.PrestigeGems(1), "flow merge: Gems: the stale +7 plus the prestige reward (paid once)")
			T.check(type(s.Food) == "table" and s.Food.Snack == (before.Snack or 0) + 2, "flow merge: Food merges as a delta (+2 Snacks)")
			advance(0.6)
			T.check(cash(ann) == s.Cash and ann:GetAttribute(config().Attr.Cash) == s.Cash and gems(ann) == s.Gems and ann:GetAttribute(config().Attr.Gems) == s.Gems,
				"flow merge: the live profile adopts the merged balances (HUD attributes too)")
			T.check(home(ann).Prestige == 1 and stationModel(annInfo, "Vault") == nil and stationModel(annInfo, "Press1") == nil,
				"flow merge: ...and the plot keeps showing the prestiged home")
			T.check(tut(ann) and (tut(ann).Done == true or (tut(ann).Chapter or 0) >= 3) and DataS.GetTutorial(ann).Done == true,
				"flow merge: ...and the finished tutorial stays finished (or on the battle chapter)")
		end
	end)
	ledger.stop()
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("p2flow_prestige")
	K.flushWarnings("p2flow_prestige", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p2flow_fusion_gems
----------------------------------------------------------------------------------------------------
S.p2flow_fusion_gems = guarded("p2flow_fusion_gems", function()
	if not K.needBoot() then
		return
	end
	local X = svc()
	local ann, ben = F.p.Ann, F.p.Ben
	if not T.check(ann and ann.Parent and home(ann) and home(ann).Prestige >= 1, "flow fusion: (precondition) Ann prestiged (p2flow_prestige)") then
		return
	end
	local Config = config()
	local DataS, Ty, TC, PK, Gs, FS = X.DataS, X.Ty, X.TC, X.PK, X.Gems, X.Fuse
	local annInfo = spots()[F.plot.Ann]
	local prof = DataS.GetProfile(ann)

	-- rebuild the way to the Fusion Machine
	-- (the Garden was kept; star prices x1.5 now)
	local route = { "Press1", "Kitchen" }
	local missed = {}
	for _, id in ipairs(route) do
		local lvBefore = level(ann, id)
		local okBuy, price = TC.CheckPurchase(home(ann), id)
		T.check(okBuy == true and price == TC.PriceAt(id, lvBefore + 1, home(ann)) and price > (TC.PriceFor(id, lvBefore + 1) or 0),
			"flow fusion: " .. id .. " costs the star price after the prestige ($" .. tostring(price) .. " = PriceAt, above the base price)")
		fund(ann, price or 0)
		pressPad(ann, annInfo, id)
		if level(ann, id) ~= lvBefore + 1 then
			missed[#missed + 1] = id
		end
	end
	away(ann)
	T.check(#missed == 0, "flow fusion: Ann rebuilds the Berry Bush and the Food Machine", table.concat(missed, ","))
	advance(1.2)
	local base = Ty.IncomePerSecond(ann)
	local _, parts = Ty.IncomePerSecond(ann)
	T.check(type(parts) == "table" and abs((parts.Multiplier or 0) - TC.PrestigeMultiplier(1)) < 1e-6 and base > 0,
		"flow fusion: the garden pets earn, every coin x" .. TC.PrestigeMultiplier(1), tostring(base))
	local okPad, priceFusion, lockFusion = TC.CheckPurchase(home(ann), "FusionMachine")
	T.check(okPad == true and buyPrompt(annInfo, "FusionMachine") ~= nil, "flow fusion: the Fusion Machine pad is unlocked (Prestige 1 + Food Machine)", tostring(lockFusion))
	fund(ann, priceFusion or 0)
	pressPad(ann, annInfo, "FusionMachine")
	away(ann)
	local machine = stationModel(annInfo, "FusionMachine")
	if not T.check(level(ann, "FusionMachine") == 1 and machine ~= nil, "flow fusion: E on its pad builds the Fusion Machine") then
		return
	end

	-- three copies: one works in the Garden, one is equipped (with the Combat pet, so a pet stays equipped)
	DataS.AddTokens(ann, 100)
	for _ = 1, 2 do
		withRoll(F.eco, function()
			advance(0.3)
			Mock.FromClient(remote("BuyRoulette"), ann, "Cloud")
		end)
	end
	advance(0.4)
	Mock.FromClient(remote("EquipPet"), ann, F.combat)
	advance(0.4)
	T.check(PK.Count(prof, F.eco) == 3 and home(ann).Garden[1] == F.eco and prof.Equipped[1] == F.eco and prof.Equipped[2] == F.combat,
		"flow fusion: (precondition) 3 copies, one in the Garden; equipped: the pet + the Combat pet", PK.Count(prof, F.eco) .. " / {" .. table.concat(prof.Equipped, ",") .. "}")
	local level0 = DataS.GetPetLevel(ann, F.eco)
	local cost = TC.FusionCost("Upgrade", X.PC.Get(F.eco).Rarity, "Golden", 1)
	DataS.AddTokens(ann, (cost and cost.Tokens) or 0)
	local t0 = tokens(ann)

	-- the window works only at the machine (E at the machine opens it)
	Mock.Teleport(ann, K.W.lobbyInfo.SpawnCFrame)
	advance(0.3)
	local mark = K.logSize()
	Mock.FromClient(remote("Fusion"), ann, "Upgrade", F.eco)
	advance(0.3)
	T.check(PK.Count(prof, F.eco) == 3 and tokens(ann) == t0 and toasted(ann, "Walk up to your Fusion Machine", mark, "bad"),
		"flow fusion: a fusion request from the plaza is refused (walk up to the machine), nothing used")
	advance(1.0)
	local at = pivotOf(machine)
	Mock.Teleport(ann, at * CFrame.new(0, 3, -8))
	mark = K.logSize()
	Mock.FromClient(remote("Fusion"), ann, "Upgrade", F.eco)
	advance(0.6)
	local golden = PK.Make(F.eco, "Golden")
	T.check(PK.Count(prof, F.eco) == 0 and PK.Count(prof, golden) == 1, "flow fusion: Upgrade at the machine: 3 copies -> 1 " .. golden)
	T.eq(tokens(ann), t0 - ((cost and cost.Tokens) or 0), "flow fusion: ...for the TycoonCatalog cost in Cloud Tokens")
	T.eq(home(ann).Garden[1], golden, "flow fusion: ...the Golden copy took over the garden slot")
	T.check(prof.Equipped[1] == golden and prof.Equipped[2] == F.combat and ann:GetAttribute(Config.Attr.EquippedPets) == golden .. "," .. F.combat,
		"flow fusion: ...and the equipped place", table.concat(prof.Equipped, ","))
	T.eq(DataS.GetPetLevel(ann, golden), level0, "flow fusion: ...and keeps the level of its inputs")
	local results = K.remotesFor("Fusion", ann.UserId, mark)
	local res = results[#results]
	T.check(res and res.args[1] == "Result" and type(res.args[2]) == "table" and res.args[2].Ok == true and res.args[2].Key == golden,
		"flow fusion: the window gets Fusion('Result', {Ok, Key}) for its animation")
	advance(1.2)
	T.eq(annInfo.Folder:GetAttribute("GardenPets"), "1=" .. golden .. ";2=" .. F.combat, "flow fusion: the plot shows the Golden pet in the Garden")
	local ecoDef, combatDef = X.PC.Get(F.eco), X.PC.Get(F.combat)
	local goldenEntry = { Def = ecoDef, Level = level0, Tier = "Golden", Stage = DataS.GetEvolution(ann, golden), Key = golden }
	local normalEntry = { Def = ecoDef, Level = level0, Tier = "Normal", Stage = 0, Key = F.eco }
	local combatEntry = { Def = combatDef, Level = (DataS.GetPetLevel(ann, F.combat)), Tier = "Normal", Stage = DataS.GetEvolution(ann, F.combat), Key = F.combat }
	local wantIncome = TC.IncomePerSecond(home(ann), { [1] = goldenEntry, [2] = combatEntry }, 1)
	T.check(abs(TC.PetPower(goldenEntry) / TC.PetPower(normalEntry) - 1.5) < 1e-6 and abs(Ty.IncomePerSecond(ann) - wantIncome) < 1e-6,
		"flow fusion: the Golden garden pet makes x1.5 coins (and the prestige x" .. TC.PrestigeMultiplier(1) .. ")", tostring(Ty.IncomePerSecond(ann)) .. " vs " .. tostring(wantIncome))

	-- gem packs (the owner pasted two product ids; restored below)
	local G = Config.Gems.Products
	local savedIds = {}
	for i, p in ipairs(G) do
		savedIds[i] = p.Id
	end
	local cb = MPS.ProcessReceipt
	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local okGems, errGems = pcall(function()
		T.check(type(cb) == "function", "flow gems: GemService set MarketplaceService.ProcessReceipt")
		G[2].Id, G[3].Id = 4398802, 4398803
		local function run(info)
			local box = spawnCall(cb, info)
			K.waitFor(function()
				return box.done
			end, 30)
			return box.done and box.ok and box.result or "error"
		end
		local g0 = gems(ann)
		local r1 = { PlayerId = ann.UserId, ProductId = G[2].Id, PurchaseId = "flow-ann-1", CurrencySpent = 99 }
		local r2 = { PlayerId = ann.UserId, ProductId = G[3].Id, PurchaseId = "flow-ann-2", CurrencySpent = 199 }
		T.eq(run(r1), GRANTED, "flow gems: Ann buys a " .. G[2].Name .. ": PurchaseGranted")
		T.eq(gems(ann), g0 + G[2].Gems, "flow gems: ...+" .. G[2].Gems .. " Gems")
		local rec = stored(ann.UserId) or {}
		T.check(rec.Gems == gems(ann) and type(rec.GemReceipts) == "table" and rec.GemReceipts[r1.PurchaseId] ~= nil and type(rec.Home) == "table" and rec.Home.Prestige == 1,
			"flow gems: ...saved with its receipt before PurchaseGranted (the prestiged home in the same record)")
		T.eq(run(r1), GRANTED, "flow gems: Roblox retries the same receipt: PurchaseGranted...")
		T.eq(gems(ann), g0 + G[2].Gems, "flow gems: ...and nothing is granted twice")
		T.eq(run(r2), GRANTED, "flow gems: a " .. G[3].Name .. " too")
		T.eq(gems(ann), g0 + G[2].Gems + G[3].Gems, "flow gems: ...+" .. G[3].Gems)
		T.eq(run({ PlayerId = ann.UserId, ProductId = 4398801, PurchaseId = "flow-ann-x" }), NOT_YET, "flow gems: a pack that is not created (id 0) stays pending")
		local gb = gems(ben)
		T.eq(run({ PlayerId = ben.UserId, ProductId = G[2].Id, PurchaseId = "flow-ben-1" }), GRANTED, "flow gems: Ben (random items restricted) can still buy Gems")
		T.check(gems(ben) == gb + G[2].Gems and gems(ann) == g0 + G[2].Gems + G[3].Gems, "flow gems: ...his Gems are his (Ann's untouched)")
		F.receipt = r1
	end)
	for i, p in ipairs(G) do
		p.Id = savedIds[i]
	end
	T.check(okGems, "flow gems: the purchase steps ran", tostring(errGems))

	-- the Storm Altar opens the Shop on the Secret roulette (Ann); Ben gets a side toast
	local altarPrompt = nil
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "StormAltarPrompt" then
			altarPrompt = d
		end
	end
	local secretId = Config.Gems.SecretRoulette.Id
	if T.check(altarPrompt ~= nil, "flow secret: the Storm Altar has its Summon prompt") then
		local where = promptPosition(altarPrompt)
		if where then
			Mock.Teleport(ann, CFrame.new(where + Vector3.new(0, 0, -6)))
			Mock.Teleport(ben, CFrame.new(where + Vector3.new(4, 0, -6)))
		end
		mark = K.logSize()
		Mock.Trigger(altarPrompt, ann)
		Mock.Trigger(altarPrompt, ben)
		advance(0.3)
		local opened = 0
		for _, e in ipairs(K.remotesFor("OpenPanel", ann.UserId, mark)) do
			if e.args[1] == "Shop" and type(e.args[2]) == "table" and e.args[2].RouletteId == secretId then
				opened = opened + 1
			end
		end
		T.eq(opened, 1, "flow secret: Ann's Summon opens the Shop on the Secret roulette")
		T.check(#K.remotesFor("OpenPanel", ben.UserId, mark) == 0 and toasted(ben, "not available", mark), "flow secret: Ben's account gets a side toast instead (no Shop)")
	end
	-- a gem spin of the Secret roulette (the Shop's Gems tab: BuyRoulette(id, "Gems")). The roll is pinned to the pool
	-- pet whose hybrid with the training Combat pet gets the shortest blended name (the podium check after the Mix
	-- wants the narrowest tag, the same in every run); the quote, the charge and the grant stay the real ones.
	local price = Config.Gems.SecretRoulette.GemPrice
	local gA, gB, pB = gems(ann), gems(ben), countKeys(DataS.GetProfile(ben).Pets)
	local pinned = nil
	do
		local combatDef = X.PC.Get(F.combat)
		local pool = (Gs and type(Gs.PossiblePets) == "function") and Gs.PossiblePets(secretId) or {}
		local shortest = math.huge
		for _, def in ipairs(pool) do
			local okName, blended = pcall(PK.BlendName, def.Name, combatDef and combatDef.Name)
			local n = (okName and type(blended) == "string") and #blended or math.huge
			if n < shortest or (n == shortest and pinned and def.Id < pinned) then
				pinned, shortest = def.Id, n
			end
		end
	end
	local realRoll = Gs and Gs.RollPet
	if pinned and realRoll then
		Gs.RollPet = function()
			return pinned
		end
	end
	mark = K.logSize()
	local okSpin, errSpin = pcall(function()
		Mock.FromClient(remote("BuyRoulette"), ann, secretId, "Gems")
		Mock.FromClient(remote("BuyRoulette"), ben, secretId, "Gems")
		advance(0.6)
	end)
	if realRoll then
		Gs.RollPet = realRoll
	end
	T.check(okSpin, "flow secret: the spins ran", tostring(errSpin))
	local spun = K.lastRemote("RouletteResult", ann.UserId, mark)
	local result = spun and spun.args[1]
	local won = type(result) == "table" and result.Ok == true and result.PetId or nil
	local wonDef = won and X.PC.Get(won)
	T.check(wonDef ~= nil and (wonDef.Rarity == "Mythic" or wonDef.Rarity == SECRET) and gems(ann) == gA - price and result.Currency == "Gems",
		"flow secret: Ann's Secret spin: a " .. tostring(wonDef and wonDef.Rarity) .. " pet for " .. price .. " Gems", tostring(won))
	T.check(won ~= nil and PK.Count(prof, won) >= 1 and prof.Discovered[won] == true, "flow secret: ...owned and discovered in the Pet Index")
	T.check(gems(ben) == gB and countKeys(DataS.GetProfile(ben).Pets) == pB, "flow secret: Ben's spin is refused, nothing charged")
	F.secretPet = won

	-- mixing the Secret-roulette pet with the trained Combat pet (Mythic / Secret inputs cost Gems)
	if won then
		local mixCost = TC.FusionCost("Mix", wonDef.Rarity, nil, 1) or {}
		local gemsBefore, tokensBefore = gems(ann), tokens(ann)
		T.check(mixCost.Gems ~= nil, "flow fusion: a Mix with a " .. wonDef.Rarity .. " pet costs Gems", mapText(mixCost))
		advance(1.0)
		Mock.Teleport(ann, at * CFrame.new(0, 3, -8))
		mark = K.logSize()
		Mock.FromClient(remote("Fusion"), ann, "Mix", won, F.combat)
		advance(0.6)
		local hybridKey, record = nil, nil
		for uid, r in pairs(prof.Hybrids or {}) do
			if r.Body == won and r.Style == F.combat then
				hybridKey, record = "hyb:" .. uid, r
			end
		end
		T.check(hybridKey ~= nil and PK.Count(prof, hybridKey) == 1 and PK.Count(prof, F.combat) == 0 and PK.Count(prof, won) == 0,
			"flow fusion: Mix(" .. won .. ", " .. F.combat .. ") makes a hybrid record (both inputs used)", tostring(hybridKey))
		T.eq(gems(ann), gemsBefore - (mixCost.Gems or 0), "flow fusion: ...for " .. tostring(mixCost.Gems) .. " Gems (no tokens)")
		T.eq(tokens(ann), tokensBefore, "flow fusion: ...no Cloud Tokens taken")
		if record then
			T.check(record.Rarity == wonDef.Rarity and type(record.Elements) == "table" and #record.Elements >= 1 and type(record.Name) == "string",
				"flow fusion: ...the hybrid has the higher rarity, both elements and a blended name (" .. tostring(record.Name) .. ")")
			local def = PK.DefOf(hybridKey, prof)
			T.eq(home(ann).Garden[2], hybridKey, "flow fusion: ...the hybrid took over the garden place of its input (any role works there)")
			local gh = DataS.GetGrowth(ann, hybridKey)
			T.check(gh and gh.Physique >= 1 and gh.Speed >= 1 and gh.Evo == 0, "flow fusion: ...and keeps the best training ranks of its parents (Physique 1, Speed 1), unevolved",
				gh and (tostring(gh.Physique) .. "/" .. tostring(gh.Speed) .. "/" .. tostring(gh.Evo)) or "")
			T.check(prof.Equipped[2] == hybridKey, "flow fusion: ...and the equipped place of the Combat pet", table.concat(prof.Equipped, ","))
			F.hybrid = hybridKey

			-- the hybrid is Ann's best pet now: it takes her podium, on a tag plate that hugs its short blended name
			-- (World text rule: compact plates; the plate's minimum width once left ~75 px of it empty)
			if X.SS and type(X.SS.Refresh) == "function" then
				pcall(X.SS.Refresh, ann)
			end
			advance(0.3)
			local tag = annInfo and annInfo.Folder and annInfo.Folder:FindFirstChild("ShowcaseTag", true)
			local card = tag and tag:FindFirstChild("Card", true)
			local nameLabel = tag and tag:FindFirstChild("PetName", true)
			local shownName = def and tostring(def.DisplayName or def.Name) or "?"
			if T.check(tag ~= nil and tag.Enabled and card ~= nil and nameLabel ~= nil and nameLabel.Text == shownName,
				"flow fusion: ...and takes Ann's podium (her best pet): the tag names '" .. shownName .. "'", nameLabel and nameLabel.Text or "no tag") then
				local minX, maxX = math.huge, -math.huge
				for _, c in ipairs(card:GetDescendants()) do
					if c:IsA("GuiObject") and c.Visible and c.AbsoluteSize.X > 0 then
						minX = math.min(minX, c.AbsolutePosition.X)
						maxX = math.max(maxX, c.AbsolutePosition.X + c.AbsoluteSize.X)
					end
				end
				T.check(maxX > minX and card.AbsoluteSize.X - (maxX - minX) <= 64,
					"flow fusion: ...on a plate that hugs the short name (World text rule: compact plates)",
					string.format("%d px plate for %d px of text", card.AbsoluteSize.X, maxX - minX))
			end
		end
	end
	K.flushErrors("p2flow_fusion_gems")
	K.flushWarnings("p2flow_fusion_gems", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p2flow_rejoin
----------------------------------------------------------------------------------------------------
S.p2flow_rejoin = guarded("p2flow_rejoin", function()
	if not K.needBoot() then
		return
	end
	local X = svc()
	local ann, ben = F.p.Ann, F.p.Ben
	if not T.check(ann and ann.Parent and F.plot.Ann and home(ann) and home(ann).Prestige >= 1, "flow rejoin: (precondition) Ann prestiged and has her plot") then
		return
	end
	local Config = config()
	local DataS, Ty, TC, PK, SS = X.DataS, X.Ty, X.TC, X.PK, X.SS
	local DSt = Mock.DataStore
	local annOld = F.plot.Ann
	local annInfo = spots()[annOld]

	-- Ann leaves with coins on her lawn: the leave save keeps them (the bank, whole Cash) for the Welcome-back pile
	away(ann)
	advance(2 * TC.Coins.MealSeconds + 1)
	T.check(home(ann).CollectorCash >= 1, "flow rejoin: (precondition) coins wait on Ann's lawn", tostring(home(ann).CollectorCash))
	local keep = {
		Cash = cash(ann), Bank = home(ann).CollectorCash, Gems = gems(ann), Tokens = tokens(ann), Home = home(ann), Food = DataS.GetFood(ann),
		Level = TC.HomeLevelOf(home(ann)), Golden = DataS.GetPetLevel(ann, PK.Make(F.eco, "Golden")),
		Hybrids = countKeys(DataS.GetProfile(ann).Hybrids), Tiers = mapText((DataS.GetProfile(ann).Tiers or {})[F.eco]),
		Income = Ty.IncomePerSecond(ann),
	}
	DSt.Latency = 0.2 -- a real DataStore call takes a moment: the refund lands while the leave save runs
	local okLeave = pcall(function()
		leave(ann)
		advance(4)
	end)
	DSt.Latency = 0
	local rec = stored(F.ids.Ann) or {}
	local recBank = type(rec.Home) == "table" and rec.Home.CollectorCash or nil
	T.check(okLeave and rec.Cash == keep.Cash and type(recBank) == "number" and recBank >= floor(keep.Bank) and recBank == floor(recBank),
		"flow rejoin: the leave save keeps her Cash and the coins on her lawn (the bank as whole Cash)", tostring(rec.Cash) .. " vs " .. keep.Cash .. ", bank " .. tostring(recBank) .. " vs " .. keep.Bank)
	T.check(SS.GetOwner(annOld) == nil and annInfo.NameLabel.Text == "Free home" and annInfo.SubLabel.Text == "Press E at the gate" and #stationIds(annInfo) == 0
		and claimPromptOf(annOld) and claimPromptOf(annOld).Enabled == true, "flow rejoin: Ann's plot is released and cleared (Free home, no stations, the ClaimPrompt is back)",
		table.concat(stationIds(annInfo), ","))

	-- Cid comes back and takes Ann's old plot (his own last plot is free: "Welcome back")
	local mark = K.logSize()
	local cid = join("Cid")
	advance(5)
	T.check(toasted(cid, "Welcome back! Press E at your gate (#" .. tostring(F.plot.Cid) .. ")", mark), "flow rejoin: Cid gets 'Welcome back! Press E at your gate'")
	claim(cid, annOld)
	advance(1.2)
	T.check(SS.GetSpot(cid) == annInfo and level(cid, "Garden") == 1 and stationModel(annInfo, "Garden") ~= nil
		and annInfo.NameLabel.Text == cid.DisplayName and annInfo.SubLabel.Text == "Home Level 1",
		"flow rejoin: Cid claims Ann's old plot and his Phase 4 build comes back there (the Pet Garden)", annInfo.SubLabel.Text)
	T.eq(annInfo.Folder:GetAttribute("GardenPets"), "1=" .. F.eco, "flow rejoin: ...with his garden pet (GardenPets)")
	T.eq(stepOf(cid), "coins", "flow rejoin: ...his tutorial resumes where he left it")
	local stCid = tut(cid)
	T.check(stCid and stCid.Target and stCid.Target.SpotIndex == annOld and typeof(stCid.Target.Position) == "Vector3"
		and stationModel(annInfo, "Garden") ~= nil and K.planar(stCid.Target.Position, pivotOf(stationModel(annInfo, "Garden")).Position) < 20,
		"flow rejoin: ...and its arrow points at his coins in the garden of his new plot", stCid and stCid.Target and tostring(stCid.Target.SpotIndex) or "no target")

	-- Ann rejoins: her last plot is taken now
	mark = K.logSize()
	ann = join("Ann")
	advance(5)
	T.check(toasted(ann, "Pick a free home", mark, "info") and not toasted(ann, "Welcome back", mark), "flow rejoin: Ann's last plot is taken: 'Pick a free home'")
	local prof = DataS.GetProfile(ann)
	T.check(cash(ann) == keep.Cash and gems(ann) == keep.Gems and tokens(ann) == keep.Tokens and ann:GetAttribute(Config.Attr.Cash) == keep.Cash,
		"flow rejoin: Cash (with the refund), Gems and tokens are back")
	T.check(sameMap(DataS.GetFood(ann), keep.Food) and DataS.GetPetLevel(ann, PK.Make(F.eco, "Golden")) == keep.Golden
		and countKeys(prof.Hybrids) == keep.Hybrids and mapText((prof.Tiers or {})[F.eco]) == keep.Tiers,
		"flow rejoin: food, pet levels, the Golden copy and the hybrid are back")
	T.check(tut(ann) and (tut(ann).Done == true or (tut(ann).Chapter or 0) >= 3), "flow rejoin: the finished tutorial stays finished (or on the battle chapter)")
	local h = home(ann)
	T.check(h and h.Prestige == 1 and sameMap(h.Stations, keep.Home.Stations) and sameMap(h.Garden, keep.Home.Garden) and next(h.Gym or {}) == nil,
		"flow rejoin: the saved home is intact (prestige, stations, garden places; no Gym slots)")
	T.check(h and h.CollectorCash == recBank, "flow rejoin: ...and her coins are back in the bank (no offline pay for a short absence)", h and tostring(h.CollectorCash) or "")
	local sugg = SS.SuggestSpot(ann)
	local newIndex = nil
	for i, info in pairs(spots()) do
		if info == sugg then
			newIndex = i
		end
	end
	if not T.check(newIndex ~= nil and newIndex ~= annOld and SS.GetOwner(newIndex) == nil, "flow rejoin: the guide suggests another free plot") then
		return
	end
	mark = K.logSize()
	claim(ann, newIndex)
	F.plot.Ann = newIndex
	local newInfo = spots()[newIndex]
	advance(1.5)
	T.check(SS.GetSpot(ann) == newInfo and toasted(ann, "Rebuilt at Home Level " .. keep.Level, mark, "good"), "flow rejoin: E at that gate: 'Welcome home! Rebuilt at Home Level " .. keep.Level .. "'")
	local miss = {}
	for id, lv in pairs(keep.Home.Stations) do
		local m = stationModel(newInfo, id)
		if lv > 0 and (not m or m:GetAttribute("Level") ~= lv) then
			miss[#miss + 1] = id
		end
	end
	T.check(#miss == 0, "flow rejoin: every saved station stands on the new plot at its level", table.concat(miss, ","))
	T.check(newInfo.Folder:GetAttribute("Prestige") == 1 and newInfo.Folder:GetAttribute("HomeLevel") == keep.Level and newInfo.SubLabel.Text:find(STAR, 1, true) ~= nil,
		"flow rejoin: the nameplate and plot attributes show Home Level " .. keep.Level .. " and the star", newInfo.SubLabel.Text)
	T.eq(newInfo.Folder:GetAttribute("GardenPets"), gardenText(keep.Home.Garden), "flow rejoin: the Golden pet and the hybrid work in the Garden again (GardenPets)")
	advance(1.2)
	local feedP = carePrompt(newInfo, "Kitchen", "FeedPrompt")
	T.check(feedP ~= nil and feedP:GetAttribute("OwnerUserId") == ann.UserId, "flow rejoin: the rebuilt Food Machine has Ann's 'Feed pets' prompt again")
	T.check(abs(Ty.IncomePerSecond(ann) - keep.Income) < 1e-6, "flow rejoin: the same income as before leaving", Ty.IncomePerSecond(ann) .. " vs " .. keep.Income)
	if F.receipt then
		local G = Config.Gems.Products
		local saved2 = G[2].Id
		G[2].Id = 4398802
		local box = spawnCall(MPS.ProcessReceipt, F.receipt)
		K.waitFor(function()
			return box.done
		end, 30)
		G[2].Id = saved2
		T.check(box.done and box.ok and box.result == Enum.ProductPurchaseDecision.PurchaseGranted and gems(ann) == keep.Gems,
			"flow rejoin: an old purchase retried after the rejoin is known (PurchaseGranted, nothing added)")
	end

	-- DataStore merge the other way: Ben's previous server lands a late Prestige-1 Home while he plays at Prestige 0
	if ben and ben.Parent and F.plot.Ben then
		local benInfo = spots()[F.plot.Ben]
		DataS.Save(ben)
		local brec = stored(ben.UserId)
		if T.check(type(brec) == "table" and type(brec.Home) == "table" and brec.Home.Prestige == 0, "flow merge 2: (precondition) Ben's save is at Prestige 0") then
			local b0 = brec.Cash or 0
			brec.Home = { Level = 6, Prestige = 1, Stations = { Garden = 1, Press1 = 3, Collector = 1, DecorLamps = 1 }, Garden = {}, Gym = {}, CollectorCash = 0, LastSeen = os.time() }
			brec.Cash = b0 + 777
			fund(ben, TC.PriceFor("Collector", 1))
			pressPad(ben, benInfo, "Collector")
			fund(ben, TC.PriceFor("House", 1))
			pressPad(ben, benInfo, "House")
			away(ben)
			T.eq(level(ben, "House"), 1, "flow merge 2: (here) Ben builds his Coin Magnet and his Cottage at Prestige 0")
			local cashNow = cash(ben) -- the session's Cash change since the save is b0 -> cashNow
			local mk = K.logSize()
			DataS.Save(ben)
			local s = stored(ben.UserId) or {}
			local sh = type(s.Home) == "table" and s.Home or {}
			T.check(sh.Prestige == 1 and type(sh.Stations) == "table" and sh.Stations.Press1 == 3 and sh.Stations.DecorLamps == 1 and sh.Stations.House == nil and sh.Stations.Garden == 1,
				"flow merge 2: the stored higher prestige wins the whole Home (this server's Cottage is void)", mapText(sh.Stations))
			T.eq(s.Cash, (b0 + 777) + (cashNow - b0), "flow merge 2: Cash still merges as a delta (+777 from the other server, this server's change on top)")
			advance(2.5)
			T.eq(cash(ben), s.Cash, "flow merge 2: ...and the live balance adopts it")
			local bh = home(ben)
			T.check(bh and bh.Prestige == 1 and bh.Stations.Press1 == 3 and bh.Stations.DecorLamps == 1 and bh.Stations.House == nil, "flow merge 2: Ben's live Home adopts it")
			local p1 = stationModel(benInfo, "Press1")
			T.check(p1 ~= nil and p1:GetAttribute("Level") == 3 and stationModel(benInfo, "DecorLamps") ~= nil and stationModel(benInfo, "House") == nil,
				"flow merge 2: ...the plot in the world follows (the Berry Bush at Lv 3, the lanterns, no Cottage)")
			T.check(benInfo.Folder:GetAttribute("Prestige") == 1 and benInfo.SubLabel.Text:find(STAR, 1, true) ~= nil, "flow merge 2: ...the star on his nameplate", benInfo.SubLabel.Text)
			T.check(#K.remotesFor("ProfileSync", ben.UserId, mk) >= 1, "flow merge 2: ...and his client gets the new snapshot")
			T.check(tut(ben) and tut(ben).Done == true, "flow merge 2: ...his skipped tutorial stays skipped")
			local okU, whyU = X.Fuse.Unlocked(ben)
			T.check(okU == false and tostring(whyU):find("Build the Fusion Machine", 1, true) ~= nil, "flow merge 2: the Fusion Machine now only needs to be built (Prestige 1 reached)", tostring(whyU))
		end
	end

	-- everyone leaves; the plots are free again
	leave(ann)
	leave(ben)
	leave(cid)
	advance(2)
	local still = {}
	for _, name in ipairs({ "Ann", "Ben", "Cid" }) do
		local idx = F.plot[name]
		if idx and SS.GetOwner(idx) ~= nil then
			still[#still + 1] = name .. "#" .. idx
		end
	end
	T.check(#still == 0 and SS.GetOwner(newIndex) == nil and SS.GetOwner(annOld) == nil, "flow end: every plot of the flow is free again", table.concat(still, ","))
	K.endAllMatches()
	K.flushErrors("p2flow_rejoin")
	K.flushWarnings("p2flow_rejoin", ALLOWED_WARNINGS)
end)

return S
