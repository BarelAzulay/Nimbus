-- smoke_p2_tycoon.lua: tycoon homes (ARCHITECTURE_V3.md "Phase 2: Tycoon homes" + "Phase 2 build contract", updated
-- for the "Phase 4 build contract": pets make the money, the home portal). server/Services/TycoonService.lua and the
-- claim-by-E SpotService. Loaded by tools/smoke.py in the SERVER world; every scenario runs on the booted game
-- (Main.server.lua), with or without HomeBuilder (when HomeBuilder's pads are missing, a stand-in BuyPrompt with the
-- contract attributes is triggered instead):
--   p2tycoon_claim      TycoonService API + signals; nobody gets a plot on join (no SpotIndex, GetSpot nil, a side
--                       toast "press E at its gate"); every plot has a ClaimPrompt; free nameplates read "Free home" /
--                       "Press E at the gate"; E claims (GetSpot / GetPlot / attribute / folder owner / Claimed fires /
--                       nameplate "Home Level 0" with the owner's name); double claim, someone else's plot, claiming in a
--                       match and prompt spam are refused; GoToSpot / GoHome open the home portal (walk in: home when
--                       claimed, else just outside the nearest free gate); leaving releases the plot (nameplate free
--                       again, attributes cleared)
--   p2tycoon_progress   a full simulated progression on one plot: the free Pet Garden (the only pad) then the Berry Bush
--                       from their pads (plants built with their Level), an Economy pet eating a meal every 8 s and
--                       popping coins into the bank (CollectorCash / CoinPiles replicated), the owner scooping by walking
--                       over the pile (HomeAction "Collect"), the pile cap (the pet naps), a stranger scooping nothing, a
--                       greedy buyer funded with AddCash who buys every cheapest unlocked pad (exact Cash per purchase,
--                       +1 Home Level each, the world build follows) until the Prestige pad unlocks; house tiers gated
--                       every 10 Home Levels ("Reach Home Level 10" refused even with the Cash), tier caps; Prestige:
--                       Cash, the bank, the piles and the stations reset, decor and garden kept, the Garden stays at
--                       level 1, +1 garden place, +1 star (nameplate), Gems reward, coins x1.25, prices x1.5, the Fusion
--                       Machine unlocks
--   p2tycoon_exploits   buying on someone else's plot (prompt + remote), buying without a plot, junk / negative / NaN /
--                       huge / wrong-type HomeAction arguments, GardenSet rules (any role: a Combat pet earns 1/1.6,
--                       unowned keys, a second slot for a single copy, a training pet, locked places, NaN slots), spam
--                       (one purchase per cooldown, one scoop payout of the Welcome-back pile, the burst budget),
--                       prestige before it is ready; Cash never goes negative
--   p2tycoon_offline    leave -> the plot is released; the saved LastSeen pays the Vault's offline coins INTO the bank on
--                       rejoin (the Cash balance untouched, a "Welcome back! Your pets made" toast, paid once); the saved
--                       build is restored on another plot and the offline coins wait in the Welcome-back pile
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor = math.abs, math.floor

local S = {}
if CONTEXT ~= "server" then
	return S
end

local advance, config, mod = K.advance, K.config, K.mod
local STAR = "\226\152\133"

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

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

local function TS()
	return requireAt("server/Services/TycoonService")
end
local function TC()
	return requireAt("shared/TycoonCatalog")
end
local function PK()
	return requireAt("shared/PetKeys")
end

local userSeq = 0
local function join(prefix)
	userSeq = userSeq + 1
	local p = Mock.AddPlayer(prefix .. userSeq, 962000 + userSeq)
	advance(1.0)
	return p
end

local function rejoin(name, userId)
	local p = Mock.AddPlayer(name, userId)
	advance(1.0)
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.6)
end

local function spots()
	return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
end

local function freeIndex(skip)
	local SS = mod("SpotService")
	for i = 1, config().Lobby.SpotCount do
		if spots()[i] and not SS.GetOwner(i) and i ~= skip then
			return i
		end
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

-- The BuyPrompt of a station's pad on a plot: HomeBuilder's, or a stand-in with the contract attributes.
local function buyPromptOf(index, stationId, ownerId)
	local info = spots()[index]
	for _, d in ipairs(info.Folder:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "BuyPrompt" then
			local node, id = d, nil
			for _ = 1, 6 do
				if not node then
					break
				end
				id = node:GetAttribute("StationId")
				if id ~= nil then
					break
				end
				node = node.Parent
			end
			if id == stationId then
				return d, false
			end
		end
	end
	local pad = Instance.new("Model")
	pad.Name = "Pad_" .. stationId
	pad:SetAttribute("StationId", stationId)
	pad:SetAttribute("OwnerUserId", ownerId)
	local part = Instance.new("Part")
	part.Name = "PadBase"
	part.Anchored = true
	part.Parent = pad
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy"
	prompt.HoldDuration = 0.25
	prompt:SetAttribute("StationId", stationId)
	prompt:SetAttribute("OwnerUserId", ownerId)
	prompt.Parent = part
	pad.Parent = info.Folder
	return prompt, true
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function homeAction(p, action, arg)
	Mock.FromClient(remote("HomeAction"), p, action, arg)
end

local function stationModels(index)
	local out = {}
	local info = spots()[index]
	for _, d in ipairs(info.Folder:GetDescendants()) do
		local id = d.Name:match("^Station_(.+)$")
		if id and (d:IsA("Model") or d:IsA("Folder") or d:IsA("BasePart")) then
			out[id] = d
		end
	end
	return out
end

local function hasHomeBuilder()
	return K.moduleInstance("server/Services/HomeBuilder") ~= nil
end

local function cashOf(p)
	return mod("DataService").GetCash(p)
end

local function stationsText(home)
	local parts = {}
	for id, lv in pairs((home and home.Stations) or {}) do
		parts[#parts + 1] = id .. "=" .. tostring(lv)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- an Economy and a Combat pet from the catalog (not Secret: plain roulette pets)
local function petsByRole()
	local PC = K.M["shared/PetCatalog"]
	local eco, combat = nil, nil
	for _, def in ipairs(PC.Pets) do
		if def.Rarity ~= "Secret" then
			if def.Role == "Economy" and not eco then
				eco = def
			elseif def.Role == "Combat" and not combat then
				combat = def
			end
		end
	end
	return eco, combat
end

local function givePet(p, key, n)
	local DataS = mod("DataService")
	local prof = DataS.GetProfile(p)
	local ok = PK().Add(prof, key, n or 1)
	DataS.MarkDirty(p)
	return ok
end

-- walks into the player's open home portal (the HomePortal attribute "x,y,z,yaw,closesAt"); true when one was open
local function portalInto(p)
	local text = p:GetAttribute(config().Attr.HomePortal)
	local x, y, z = tostring(text):match("^([^,]+),([^,]+),([^,]+)")
	if not x or not p.Character then
		return false
	end
	Mock.Teleport(p, CFrame.new(Vector3.new(tonumber(x), tonumber(y) + 3, tonumber(z))))
	advance(0.5) -- two passes of TycoonService's 0.2 s portal loop
	return true
end

-- far from every lawn (the plaza)
local function away(p)
	Mock.Teleport(p, config().Lobby.Origin + Vector3.new(0, 4, 0))
end

-- an Economy pet entry for TycoonCatalog.PetPower / IncomePerSecond
local function entryOf(def)
	return { Def = def, Level = 1, Tier = "Normal", Stage = 0 }
end

-- walks to the gate (just outside it, like a player) and presses E on its ClaimPrompt
local function claim(p, index)
	local prompt = claimPromptOf(index)
	local SS = mod("SpotService")
	local gate = SS.GateCFrame(spots()[index])
	if gate and p.Character then
		Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
	end
	if prompt then
		Mock.Trigger(prompt, p)
	end
	advance(0.6) -- past the claim cooldown
	return prompt ~= nil
end

----------------------------------------------------------------------------------------------------
-- p2tycoon_claim
----------------------------------------------------------------------------------------------------
S.p2tycoon_claim = guarded("p2tycoon_claim", function()
	if not K.needBoot() then
		return
	end
	local Config = config()
	local SS = mod("SpotService")
	local Ty = TS()
	if not T.check(Ty ~= nil, "tycoon: server/Services/TycoonService.lua loads") then
		return
	end
	for _, fn in ipairs({ "Init", "GetPlot", "GetHome", "Buy", "Collect", "Prestige", "IncomePerSecond", "Claim", "Release", "GardenSet" }) do
		T.check(type(Ty[fn]) == "function", "tycoon: TycoonService." .. fn .. " is a function")
	end
	for _, sig in ipairs({ "HomeChanged", "Claimed", "Prestiged" }) do
		T.check(type(Ty[sig]) == "table" and type(Ty[sig].Connect) == "function", "tycoon: signal TycoonService." .. sig)
	end
	for _, fn in ipairs({ "Claim", "Release", "GetOwner", "GetSpotByIndex", "FindFreeSpot", "SuggestSpot", "GateCFrame" }) do
		T.check(type(SS[fn]) == "function", "tycoon: SpotService." .. fn .. " is a function")
	end
	T.check(remote("HomeAction") ~= nil, "tycoon: the HomeAction remote exists")

	-- every plot has a ClaimPrompt and free plots read "Free home" / "Press E at the gate"
	local count = Config.Lobby.SpotCount
	local prompts = T.tally("tycoon: every plot's gate has a ClaimPrompt (SpotIndex attribute)")
	local labels = T.tally("tycoon: every free plot reads 'Free home' / 'Press E at the gate'")
	for i = 1, count do
		local info = spots()[i]
		if info then
			local prompt = claimPromptOf(i)
			prompts:case(prompt ~= nil and (prompt:GetAttribute("SpotIndex") == i or prompt:IsDescendantOf(info.Folder)), "plot " .. i)
			if not SS.GetOwner(i) then
				labels:case(info.NameLabel.Text == "Free home" and info.SubLabel.Text == "Press E at the gate",
					"plot " .. i .. ": " .. tostring(info.NameLabel.Text) .. " / " .. tostring(info.SubLabel.Text))
			end
		end
	end
	prompts:report()
	labels:report()

	-- join: no plot, a side toast tells them to press E
	local mark = K.logSize()
	local a = join("TyClaimA")
	T.check(SS.GetSpot(a) == nil and a:GetAttribute(Config.Attr.SpotIndex) == nil and Ty.GetPlot(a) == nil,
		"tycoon: joining does not hand out a plot (GetSpot nil, no SpotIndex attribute)")
	advance(5)
	T.check(K.notified(a, "press E at its gate", nil, mark), "tycoon: a new player gets the side toast 'Pick a free home: press E at its gate'")

	-- GoToSpot without a plot: the home portal opens toward the nearest free gate; walking in lands just outside it
	local root = K.root(a)
	local suggested = SS.SuggestSpot(a)
	local standing = root and root.Position
	Mock.FromClient(remote("GoToSpot"), a)
	advance(0.3)
	local portalText = a:GetAttribute(Config.Attr.HomePortal)
	T.check(type(portalText) == "string" and standing ~= nil and (K.root(a).Position - standing).Magnitude < 1 and SS.GetSpot(a) == nil,
		"tycoon: GoToSpot without a plot opens the home portal (the HomePortal attribute) and moves nobody by itself", tostring(portalText))
	local okWalk = portalInto(a)
	-- (the spawn is the plaza centre, equidistant from every plot: the nearest free gate is any free gate)
	local nearestGate = math.huge
	for i = 1, Config.Lobby.SpotCount do
		local gate = spots()[i] and not SS.GetOwner(i) and SS.GateCFrame(spots()[i])
		if gate then
			nearestGate = math.min(nearestGate, K.planar(K.root(a).Position, gate.Position))
		end
	end
	T.check(okWalk and suggested ~= nil and nearestGate <= 10 and SS.GetSpot(a) == nil,
		"tycoon: walking into the portal puts the player just outside a free gate (and claims nothing)",
		string.format("%.1f studs from the nearest free gate", nearestGate))
	advance(3.1) -- the portal cooldown

	-- E at the gate claims it
	local index = freeIndex()
	local claimedArgs = nil
	local conn = Ty.Claimed:Connect(function(p, info)
		claimedArgs = { p, info }
	end)
	mark = K.logSize()
	T.check(claim(a, index), "tycoon: (precondition) plot " .. tostring(index) .. " has a ClaimPrompt")
	conn:Disconnect()
	local info = spots()[index]
	T.check(SS.GetSpot(a) == info and Ty.GetPlot(a) == info and a:GetAttribute(Config.Attr.SpotIndex) == index,
		"tycoon: E at the gate claims the plot (GetSpot, GetPlot, SpotIndex attribute)")
	T.check(SS.GetOwner(index) == a and info.Folder:GetAttribute("OwnerUserId") == a.UserId, "tycoon: ...the plot folder carries OwnerUserId")
	T.check(claimedArgs ~= nil and claimedArgs[1] == a and claimedArgs[2] == info, "tycoon: TycoonService.Claimed fired (player, spotInfo)")
	T.check(mod("DataService").GetProfile(a).SpotIndex == index, "tycoon: the profile remembers the last plot (SpotIndex)")
	advance(1.2)
	T.eq(info.NameLabel.Text, a.DisplayName, "tycoon: the nameplate shows the owner")
	T.eq(info.SubLabel.Text, "Home Level 0", "tycoon: ...and 'Home Level 0' for a new home")
	T.check(K.notified(a, "Welcome home", "good", mark), "tycoon: a 'Welcome home' side toast")
	T.eq(claimPromptOf(index).Enabled, false, "tycoon: the gate's ClaimPrompt turns off once the plot is claimed")

	-- the podium: the owner's best pet copy (pet keys), built standing still and animated by the CLIENT (NC_Showcase)
	local Eco0 = petsByRole()
	if Eco0 then
		givePet(a, Eco0.Id, 1)
	end
	SS.Refresh(a)
	advance(0.2)
	local show = info.Folder:FindFirstChild("ShowcasePet", true)
	if T.check(show ~= nil, "tycoon podium: the owner's best pet stands on the podium (ShowcasePet)") then
		local anchored, parts = true, 0
		for _, d in ipairs(show:GetDescendants()) do
			if d:IsA("BasePart") then
				parts = parts + 1
				anchored = anchored and d.Anchored and not d.CanCollide
			end
		end
		local CS = game:GetService("CollectionService")
		T.check(CS:HasTag(show, "NC_Showcase") and show:GetAttribute("Ready") == true and show:GetAttribute("PetParts") == parts
			and type(show:GetAttribute("HoverAmp")) == "number",
			"tycoon podium: tagged NC_Showcase with Ready / PetParts / HoverAmp (ShowcaseController animates it on the client)")
		T.check(anchored and parts > 0, "tycoon podium: every part Anchored and non-colliding (the server never moves it)")
		local p0 = show:GetPivot()
		advance(1.5)
		T.check((show:GetPivot().Position - p0.Position).Magnitude < 1e-6 and (show:GetPivot().LookVector - p0.LookVector).Magnitude < 1e-6,
			"tycoon podium: the server does not animate the showcase (no CFrame writes)")
		local key = show:GetAttribute("PetId")
		local keys = PK()
		local parsed = keys and type(key) == "string" and keys.Parse(key)
		if parsed and parsed.PetId and parsed.Tier == "Normal" then
			givePet(a, keys.Make(parsed.PetId, "Golden"), 1)
			SS.Refresh(a)
			advance(0.2)
			local golden = info.Folder:FindFirstChild("ShowcasePet", true)
			local tag = info.Folder:FindFirstChild("ShowcaseTag", true)
			local nameLabel = tag and tag:FindFirstChild("PetName", true)
			local def = keys.DefOf(parsed.PetId .. "@Golden", mod("DataService").GetProfile(a))
			T.check(golden ~= nil and golden:GetAttribute("PetId") == parsed.PetId .. "@Golden",
				"tycoon podium: a Golden copy of the same pet takes the podium (pet keys, better tier wins the tie)",
				golden and tostring(golden:GetAttribute("PetId")) or "none")
			T.check(nameLabel ~= nil and def ~= nil and nameLabel.Text == tostring(def.DisplayName or def.Name),
				"tycoon podium: ...and its tag names the copy", nameLabel and nameLabel.Text or "no tag")
		else
			T.info("*podium tier check skipped: the podium shows " .. tostring(key))
		end
	end

	-- double claim, someone else's plot, claiming in a match, spam
	local other = freeIndex(index)
	mark = K.logSize()
	claim(a, other)
	T.check(SS.GetSpot(a) == info and SS.GetOwner(other) == nil, "tycoon: a second claim is refused (one plot per player)")
	T.check(K.notified(a, "already have a home", "bad", mark), "tycoon: ...with a toast")
	local b = join("TyClaimB")
	mark = K.logSize()
	claim(b, index)
	T.check(SS.GetOwner(index) == a and SS.GetSpot(b) == nil, "tycoon: nobody can claim a plot that is taken")
	T.check(K.notified(b, "belongs to", "bad", mark), "tycoon: ...the toast names the owner")
	b:SetAttribute(Config.Attr.InMatch, true)
	claim(b, other)
	T.check(SS.GetSpot(b) == nil and SS.GetOwner(other) == nil, "tycoon: claiming is refused during a match")
	advance(1.0) -- past the refusal toast throttle (the claim above was refused with the same text)
	mark = K.logSize()
	local inMatchAt = K.root(b) and K.root(b).Position
	homeAction(b, "GoHome")
	advance(0.6)
	T.check(K.notified(b, "Finish your match", "bad", mark) and inMatchAt ~= nil and (K.root(b).Position - inMatchAt).Magnitude < 1,
		"tycoon: HomeAction 'GoHome' is refused during a match (side toast, nobody moves)")
	b:SetAttribute(Config.Attr.InMatch, false)
	Mock.Teleport(b, config().Lobby.Origin + Vector3.new(0, 4, 0))
	Mock.Trigger(claimPromptOf(other), b)
	advance(0.6)
	T.check(SS.GetSpot(b) == nil and SS.GetOwner(other) == nil, "tycoon: a ClaimPrompt triggered from far away (the plaza) claims nothing")
	local gateOther = SS.GateCFrame(spots()[other])
	Mock.Teleport(b, gateOther * CFrame.new(0, 3, -5))
	local prompt = claimPromptOf(other)
	for _ = 1, 25 do
		Mock.Trigger(prompt, b)
	end
	local third = freeIndex(other)
	Mock.Teleport(b, SS.GateCFrame(spots()[third]) * CFrame.new(0, 3, -5))
	Mock.Trigger(claimPromptOf(third), b)
	advance(0.6)
	T.check(SS.GetSpot(b) == spots()[other] and SS.GetOwner(third) == nil, "tycoon: 25 claim presses in one frame claim exactly one plot")

	-- GoToSpot with a plot: the portal home (walk in, then within 6 studs of the plot's spawn)
	Mock.Teleport(a, config().Lobby.Origin + Vector3.new(10, 4, 0))
	advance(0.2)
	Mock.FromClient(remote("GoToSpot"), a)
	advance(0.2)
	T.check(type(a:GetAttribute(Config.Attr.HomePortal)) == "string" and K.planar(K.root(a).Position, info.SpawnCFrame.Position) > 20,
		"tycoon: GoToSpot with a plot opens the home portal where the player stands (no teleport yet)")
	portalInto(a)
	T.check(K.planar(K.root(a).Position, info.SpawnCFrame.Position) <= 6 and a:GetAttribute(Config.Attr.HomePortal) == nil,
		"tycoon: walking into it goes home (within 6 studs of the plot's spawn; the portal closes)")
	Mock.Teleport(b, config().Lobby.Origin + Vector3.new(-10, 4, 0))
	advance(0.2)
	homeAction(b, "GoHome")
	advance(0.2)
	T.check(type(b:GetAttribute(Config.Attr.HomePortal)) == "string", "tycoon: HomeAction 'GoHome' opens the portal too")
	portalInto(b)
	T.check(K.planar(K.root(b).Position, spots()[other].SpawnCFrame.Position) <= 6, "tycoon: ...and walking in goes home")

	-- leaving releases the plot
	leave(b)
	advance(1.2)
	local oi = spots()[other]
	T.check(SS.GetOwner(other) == nil and oi.NameLabel.Text == "Free home" and oi.SubLabel.Text == "Press E at the gate"
		and oi.Folder:GetAttribute("OwnerUserId") == nil and oi.Folder:GetAttribute("HomeLevel") == nil,
		"tycoon: leaving releases the plot ('Free home' / 'Press E at the gate', attributes cleared)")
	local stale = 0
	for _ in pairs(stationModels(other)) do
		stale = stale + 1
	end
	T.eq(stale, 0, "tycoon: ...and no station of the old build stays on it")
	T.eq(claimPromptOf(other).Enabled, true, "tycoon: ...and back on when the plot is released")
	local c = join("TyClaimC")
	claim(c, other)
	T.check(SS.GetSpot(c) == oi, "tycoon: a released plot can be claimed again")
	leave(c)
	leave(a)
	T.check(SS.GetOwner(index) == nil, "tycoon: (cleanup) plots free again")
	K.flushErrors("p2tycoon_claim")
	K.flushWarnings("p2tycoon_claim", { "HomeBuilder is missing" })
end)

----------------------------------------------------------------------------------------------------
-- p2tycoon_progress
----------------------------------------------------------------------------------------------------
S.p2tycoon_progress = guarded("p2tycoon_progress", function()
	if not K.needBoot() then
		return
	end
	local Config = config()
	local SS, DataS = mod("SpotService"), mod("DataService")
	local Ty, Cat = TS(), TC()
	if not Ty or not Cat then
		T.fail("tycoon: TycoonService and TycoonCatalog load")
		return
	end
	local p = join("TyProg")
	local index = freeIndex()
	claim(p, index)
	local info = spots()[index]
	if not T.check(SS.GetSpot(p) == info, "tycoon progress: (precondition) the plot is claimed") then
		leave(p)
		return
	end
	local withBuilder = hasHomeBuilder()
	T.info("*HomeBuilder " .. (withBuilder and "present: pads and stations are HomeBuilder's" or "absent: stand-in BuyPrompts"))

	-- the free Pet Garden from its pad (E on the BuyPrompt): the ONLY pad of a fresh home
	local cash0 = cashOf(p)
	local pads0 = Cat.AvailablePads(Ty.GetHome(p))
	T.check(#pads0 == 1 and pads0[1].StationId == "Garden" and pads0[1].Price == 0, "tycoon progress: a fresh home shows exactly one pad: the free Pet Garden")
	local prompt, fake = buyPromptOf(index, "Garden", p.UserId)
	if withBuilder then
		T.check(not fake and prompt:GetAttribute("OwnerUserId") == p.UserId, "tycoon progress: the claim put HomeBuilder's Pet Garden pad (BuyPrompt, OwnerUserId) on the plot")
	end
	Mock.Trigger(prompt, p)
	advance(0.3)
	local home = Ty.GetHome(p)
	T.check(home and home.Stations.Garden == 1 and cashOf(p) == cash0 and home.Level == 1, "tycoon progress: the Pet Garden is free from its pad (BuyPrompt): Home Level 1",
		stationsText(home))
	if fake then
		prompt.Parent.Parent:Destroy()
	end
	-- the Berry Bush ($15, the star price PriceAt) next: plants stand on the press slots with their Level
	local bushPrice = Cat.PriceAt("Press1", 1, home)
	T.eq(bushPrice, 15, "tycoon progress: the Berry Bush costs $15 at 0 stars (PriceAt = the base price)")
	DataS.AddCash(p, bushPrice)
	prompt, fake = buyPromptOf(index, "Press1", p.UserId)
	Mock.Trigger(prompt, p)
	advance(0.3)
	if fake then
		prompt.Parent.Parent:Destroy()
	end
	home = Ty.GetHome(p)
	T.check(home.Stations.Press1 == 1 and home.Level == 2 and cashOf(p) == cash0, "tycoon progress: the Berry Bush next (exactly $15): Home Level 2", stationsText(home))
	if withBuilder then
		local models = stationModels(index)
		T.check(models.Garden ~= nil and models.Press1 ~= nil and models.Press1:GetAttribute("Level") == 1,
			"tycoon progress: the stations stand on the plot (Station_Garden / Station_Press1 with its Level attribute)")
	end

	-- coins (Phase 5): no pet in the garden = no coins; a roaming Economy pet poops Cloud Cash worth 3 meals once per
	-- 24 s cycle (the first poop >= 24 s after the placement: Epoch = now + SettleSeconds)
	local Eco, Combat = petsByRole()
	local Roam = requireAt("shared/HomeRoam")
	local meal = Cat.Coins.MealSeconds
	local cycle = Roam.Cycle
	T.eq(Ty.IncomePerSecond(p), 0, "tycoon progress: no pet in the garden = no coins (IncomePerSecond 0)")
	givePet(p, Eco.Id, 1)
	homeAction(p, "GardenSet", { 1, Eco.Id })
	advance(0.3)
	home = Ty.GetHome(p)
	local coin = Cat.CoinValue(home, Cat.PetPower(entryOf(Eco)), 0)
	local poop = coin * Cat.Coins.PoopMeals
	local income = Ty.IncomePerSecond(p)
	T.check(home.Garden[1] == Eco.Id and near(income, Cat.IncomePerSecond(home, { [1] = entryOf(Eco) }, 0), 1e-6) and near(coin, (12 + 7) * Cat.PetPower(entryOf(Eco)), 1e-6),
		"tycoon progress: an Economy pet placed with HomeAction GardenSet earns Food (grass 12 + Berry Farm L1 7) / 8 x PetPower per second", tostring(income))
	T.eq(info.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id, "tycoon progress: the plot folder replicates GardenPets")
	T.check(tostring(info.Folder:GetAttribute("Roam")):match("^1=%d+%.%d$") ~= nil, "tycoon progress: ...and Roam ('1=<epoch>')", tostring(info.Folder:GetAttribute("Roam")))
	away(p)
	advance(Roam.SettleSeconds + 2 * cycle + 2)
	home = Ty.GetHome(p)
	T.check(home.CollectorCash >= 2 * poop - 1e-6 and home.CollectorCash <= 3 * poop + 1e-6, "tycoon progress: the 1 s tick lays one poop (3 coins) per cycle into the bank (CollectorCash)", tostring(home.CollectorCash))
	T.eq(info.Folder:GetAttribute("CollectorCash"), floor(home.CollectorCash), "tycoon progress: the plot folder replicates CollectorCash (whole)")
	T.check(near(info.Folder:GetAttribute("IncomePerSecond"), income, 0.051), "tycoon progress: ...and IncomePerSecond")
	T.check(tostring(info.Folder:GetAttribute("CoinDrops")):match("^1=%d+:%d") ~= nil, "tycoon progress: ...and CoinDrops ('1=<cycle>:<stage>')", tostring(info.Folder:GetAttribute("CoinDrops")))
	T.eq(info.Folder:GetAttribute("CoinPiles"), nil, "tycoon progress: ...no CoinPiles any more (Phase 5)")
	-- scoop: the owner walks over the pile (HomeAction 'Collect' = scoop in range, kept for old clients)
	local pile = Ty.Piles(p) and Ty.Piles(p)[1]
	local before = cashOf(p)
	local radius = Cat.ScoopRadius(home)
	local onLawn = 0
	for _, d in ipairs(Ty.Drops(p) or {}) do
		if K.planar(d.Position, pile.Pos) <= radius then
			onLawn = onLawn + d.Value
		end
	end
	onLawn = floor(onLawn + 1e-6)
	local bankBefore = home.CollectorCash
	local mark = K.logSize()
	Mock.Teleport(p, CFrame.new(pile.Pos + Vector3.new(0, 3, 0)))
	homeAction(p, "Collect")
	advance(0.1)
	home = Ty.GetHome(p)
	T.eq(cashOf(p) - before, onLawn, "tycoon progress: walking over the drops scoops the whole Cash within ScoopRadius (HomeAction 'Collect' = scoop in range)")
	T.check(home.CollectorCash >= bankBefore - onLawn - 1e-6 and home.CollectorCash <= bankBefore - onLawn + poop + 1e-6, "tycoon progress: ...the scooped drops are gone (the bank keeps the drops out of reach, the fraction and at most one new poop)", tostring(home.CollectorCash))
	T.check(K.notified(p, "scooped", "good", mark), "tycoon progress: ...with a 'scooped' side toast")

	-- the lawn cap: PileSeconds (Garden L1: 300 s) of the pet's coins, then the pet naps (Roam ':N<cycle>')
	local pileSeconds = Ty.PileSeconds(p)
	T.check(pileSeconds == Cat.PileSeconds(home) and pileSeconds == Cat.Get("Garden").Effects[1].PileSeconds, "tycoon progress: PileSeconds = the Garden's PileSeconds effect (300 s at L1)", tostring(pileSeconds))
	away(p)
	advance(pileSeconds + 3 * cycle)
	home = Ty.GetHome(p)
	local cap = pileSeconds * coin / meal
	T.check(home.CollectorCash >= cap - 1e-6 and home.CollectorCash <= cap + poop + 1e-6 and tostring(info.Folder:GetAttribute("Roam")):find(":N", 1, true) ~= nil,
		"tycoon progress: the lawn stops at PileSeconds of coins and the pet naps (':N')", tostring(home.CollectorCash) .. " of " .. tostring(cap) .. " roam " .. tostring(info.Folder:GetAttribute("Roam")))
	-- nobody else scoops
	local stranger = join("TyStranger")
	Mock.Teleport(stranger, CFrame.new(pile.Pos + Vector3.new(0, 3, 0)))
	homeAction(stranger, "Collect")
	advance(0.6)
	T.check(cashOf(stranger) == 0 and Ty.GetHome(p).CollectorCash >= cap - 1e-6, "tycoon progress: nobody else can scoop someone's coins")
	leave(stranger)
	Mock.Teleport(p, CFrame.new(pile.Pos + Vector3.new(0, 3, 0)))
	homeAction(p, "Collect")
	advance(0.6)
	away(p)

	-- greedy buyer: AddCash stands in for hours of income; always buys the cheapest unlocked pad
	local purchases, problems, deadEnd = 0, {}, nil
	local sawHouseGate, sawTierCap = false, false
	for _ = 1, 400 do
		home = Ty.GetHome(p)
		if Cat.CanPrestige(home) then
			break
		end
		local best = nil
		for _, pad in ipairs(Cat.AvailablePads(home)) do
			if not pad.Prestige then
				if pad.Locked == nil then
					if not best or pad.Price < best.Price then
						best = pad
					end
				elseif pad.StationId == "House" and pad.Locked:find("Reach Home Level", 1, true) and not sawHouseGate then
					-- the house tier gate: refused even with the Cash in hand
					sawHouseGate = true
					DataS.AddCash(p, pad.Price)
					local c = cashOf(p)
					local ok, reason = Ty.Buy(p, "House")
					local h2 = Ty.GetHome(p)
					if ok or cashOf(p) ~= c or h2.Stations.House ~= home.Stations.House or not tostring(reason):find("Reach Home Level", 1, true) then
						problems[#problems + 1] = "house gate bypassed at Home Level " .. Cat.HomeLevelOf(home) .. " (" .. tostring(reason) .. ")"
					end
					DataS.SpendCash(p, pad.Price)
				elseif pad.Locked:find("Needs the", 1, true) and pad.StationId:find("^Press") then
					sawTierCap = true
				end
			end
		end
		if not best then
			deadEnd = "Home Level " .. Cat.HomeLevelOf(home) .. ": " .. stationsText(home)
			break
		end
		if best.Price > 0 then
			DataS.AddCash(p, best.Price)
		end
		local c = cashOf(p)
		local level = Cat.StationLevel(home, best.StationId)
		local ok, result = Ty.Buy(p, best.StationId)
		local after = Ty.GetHome(p)
		purchases = purchases + 1
		if not ok then
			problems[#problems + 1] = best.StationId .. " refused: " .. tostring(result)
		elseif c - cashOf(p) ~= best.Price or Cat.StationLevel(after, best.StationId) ~= level + 1 or after.Level ~= Cat.HomeLevelOf(after)
			or Cat.HomeLevelOf(after) ~= Cat.HomeLevelOf(home) + 1 then
			problems[#problems + 1] = best.StationId .. ": paid " .. (c - cashOf(p)) .. " of " .. best.Price .. ", level " .. Cat.StationLevel(after, best.StationId)
		end
	end
	T.check(#problems == 0, "tycoon progress: every purchase takes exactly its price and adds one Home Level (" .. purchases .. " purchases)",
		table.concat(problems, " | "))
	T.check(deadEnd == nil, "tycoon progress: no dead end on the way to Prestige", deadEnd)
	T.check(sawHouseGate, "tycoon progress: the next house is refused below its Home Level ('Reach Home Level 10')")
	T.check(sawTierCap, "tycoon progress: station caps follow the house tier ('Needs the Villa')")
	home = Ty.GetHome(p)
	T.check(Cat.CanPrestige(home) and Cat.StationLevel(home, "House") == 4 and Cat.HomeLevelOf(home) >= 40,
		"tycoon progress: the Sky Castle and Home Level 40 reached (" .. Cat.HomeLevelOf(home) .. ")")
	local _, _, fusionReason = Cat.CheckPurchase(home, "FusionMachine")
	T.check(fusionReason == "Unlocks at Prestige 1", "tycoon progress: the Fusion Machine is locked before Prestige 1", tostring(fusionReason))
	if withBuilder then
		local models = stationModels(index)
		local miss = {}
		for id, lv in pairs(home.Stations) do
			if lv > 0 and (not models[id] or models[id]:GetAttribute("Level") ~= lv) then
				miss[#miss + 1] = id
			end
		end
		T.check(#miss == 0, "tycoon progress: every built station stands on the plot at its level", table.concat(miss, ","))
	end
	advance(1.2)
	T.eq(info.SubLabel.Text, "Home Level " .. Cat.HomeLevelOf(home), "tycoon progress: the nameplate follows the Home Level")

	-- Prestige
	DataS.AddCash(p, 12345)
	local gemsBefore = DataS.GetGems(p)
	if type(DataS.AddFood) == "function" then
		DataS.AddFood(p, "Snack", 3)
	end
	local foodBefore = type(DataS.GetFood) == "function" and DataS.GetFood(p, "Snack") or nil
	local petsBefore = Eco and PK().Count(DataS.GetProfile(p), Eco.Id) or nil
	local decor = {}
	for _, def in ipairs(Cat.Stations) do
		if def.KeepOnPrestige then
			decor[def.Id] = Cat.StationLevel(home, def.Id)
		end
	end
	local pres = nil
	local conn = Ty.Prestiged:Connect(function(pl, stars)
		pres = { pl, stars }
	end)
	mark = K.logSize()
	homeAction(p, "Prestige")
	advance(0.3)
	conn:Disconnect()
	local after = Ty.GetHome(p)
	T.check(after.Prestige == 1 and pres ~= nil and pres[1] == p and pres[2] == 1, "tycoon prestige: +1 star and Prestiged(player, 1)")
	T.eq(cashOf(p), 0, "tycoon prestige: Cash resets to 0")
	T.eq(DataS.GetGems(p) - gemsBefore, Cat.PrestigeGems(1), "tycoon prestige: the Gems reward")
	local wrong = {}
	for _, def in ipairs(Cat.Stations) do
		local want = decor[def.Id] or def.ResetLevel or 0
		if Cat.StationLevel(after, def.Id) ~= want then
			wrong[#wrong + 1] = def.Id .. "=" .. Cat.StationLevel(after, def.Id)
		end
	end
	T.check(#wrong == 0, "tycoon prestige: stations reset, decor kept, the Garden back at its ResetLevel 1", table.concat(wrong, ","))
	T.eq(after.Stations.Garden, 1, "tycoon prestige: the Pet Garden stays built at level 1 (the coins never stop)")
	T.check(after.CollectorCash == 0 and Ty.CoinsWaiting(p) == 0 and (info.Folder:GetAttribute("CoinDrops") or "") == "" and after.Level == Cat.HomeLevelOf(after),
		"tycoon prestige: the bank and the coins on the lawn are zero, Home Level = the decor + the Garden")
	T.check(Eco == nil or after.Garden[1] == Eco.Id, "tycoon prestige: garden choices are kept")
	T.check(Cat.GardenSlots(after) == 4 and info.Folder:GetAttribute("GardenSlots") == 4, "tycoon prestige: +1 garden place (4 = 3 + 1 star), replicated")
	T.check(K.notified(p, "Garden place 4 unlocked", "good", mark), "tycoon prestige: the 'Garden place 4 unlocked!' toast")
	T.check((petsBefore == nil or PK().Count(DataS.GetProfile(p), Eco.Id) == petsBefore)
		and (foodBefore == nil or DataS.GetFood(p, "Snack") == foodBefore),
		"tycoon prestige: pets and food are kept", tostring(petsBefore) .. " pets, " .. tostring(foodBefore) .. " snacks before")
	T.check(K.notified(p, "Prestige 1", "good", mark), "tycoon prestige: a side toast")
	advance(1.2)
	T.check(info.SubLabel.Text:find(STAR, 1, true) ~= nil, "tycoon prestige: the nameplate shows a prestige star", info.SubLabel.Text)
	if withBuilder then
		local models = stationModels(index)
		T.check(models.Press1 == nil and models.House == nil and models.Garden ~= nil, "tycoon prestige: the reset stations leave the plot, the Garden stays")
	end

	-- x1.25 coins per star, x1.5 prices per star, the Fusion Machine unlocks
	local h1 = Ty.GetHome(p)
	local starPrice = Cat.PriceAt("Press1", 1, h1)
	T.check(starPrice == floor(15 * 1.5) and starPrice > Cat.PriceFor("Press1", 1), "tycoon prestige: prices go up by half per star (Berry Bush $" .. tostring(starPrice) .. ")")
	DataS.AddCash(p, starPrice)
	local okBush = Ty.Buy(p, "Press1")
	T.check(okBush == true and cashOf(p) == 0, "tycoon prestige: a pad takes exactly its star price")
	h1 = Ty.GetHome(p)
	local inc = Ty.IncomePerSecond(p)
	local base = Cat.IncomePerSecond(h1, { [1] = entryOf(Eco) }, 0)
	T.check(near(inc, base * 1.25, 1e-6) and near(inc, Cat.IncomePerSecond(h1, { [1] = entryOf(Eco) }, 1), 1e-6), "tycoon prestige: coins x1.25 per star", tostring(inc))
	local probe = Ty.GetHome(p)
	probe.Stations.Kitchen = 1 -- a copy: the Fusion Machine's tree needs the Kitchen
	local okFusion, _, reason2 = Cat.CheckPurchase(probe, "FusionMachine")
	T.check(okFusion == true, "tycoon prestige: the Fusion Machine pad unlocks at Prestige 1 (with its Kitchen)", tostring(reason2))
	Ty.ClearCoins(p)
	away(p)
	advance(2 * cycle + 2)
	local coin25 = Cat.CoinValue(h1, Cat.PetPower(entryOf(Eco)), 1) * Cat.Coins.PoopMeals
	local cc = Ty.GetHome(p).CollectorCash
	T.check(near(coin25, Cat.FoodOf(h1) * Cat.PetPower(entryOf(Eco)) * 1.25 * Cat.Coins.PoopMeals, 1e-6) and cc >= coin25 - 1e-6 and cc <= 3 * coin25 + 1e-6,
		"tycoon prestige: the coins keep coming at the multiplied value", tostring(cc) .. " vs poop " .. tostring(coin25))
	leave(p)
	K.flushErrors("p2tycoon_progress")
	K.flushWarnings("p2tycoon_progress", { "HomeBuilder is missing" })
end)

----------------------------------------------------------------------------------------------------
-- p2tycoon_exploits
----------------------------------------------------------------------------------------------------
S.p2tycoon_exploits = guarded("p2tycoon_exploits", function()
	if not K.needBoot() then
		return
	end
	local SS, DataS = mod("SpotService"), mod("DataService")
	local Ty, Cat = TS(), TC()
	if not Ty or not Cat then
		T.fail("tycoon: TycoonService and TycoonCatalog load")
		return
	end
	local a = join("TyOwner")
	local b = join("TyThief")
	local ia = freeIndex()
	claim(a, ia)
	local ib = freeIndex(ia)
	claim(b, ib)
	Ty.Buy(a, "Garden")
	DataS.AddCash(a, Cat.PriceAt("Press1", 1, Ty.GetHome(a)))
	Ty.Buy(a, "Press1")
	advance(0.3)
	away(a)

	-- buying on someone else's plot
	DataS.AddCash(b, 5000)
	local homeA = Ty.GetHome(a)
	local cashB = cashOf(b)
	local prompt, fake = buyPromptOf(ia, "Press1", a.UserId)
	Mock.Trigger(prompt, b)
	advance(0.3)
	T.check(Ty.GetHome(a).Stations.Press1 == homeA.Stations.Press1 and cashOf(b) == cashB and (Ty.GetHome(b).Stations.Press1 or 0) == 0,
		"tycoon exploits: a BuyPrompt on someone else's plot buys nothing (for nobody)")
	if fake then
		-- a stand-in pad that claims to be the thief's, inside the owner's plot
		prompt:SetAttribute("OwnerUserId", b.UserId)
		prompt.Parent.Parent:SetAttribute("OwnerUserId", b.UserId)
		Mock.Trigger(prompt, b)
		advance(0.3)
		T.check(Ty.GetHome(a).Stations.Press1 == homeA.Stations.Press1 and cashOf(b) == cashB and (Ty.GetHome(b).Stations.Press1 or 0) == 0,
			"tycoon exploits: ...even when the pad's OwnerUserId names the thief (the plot decides)")
		prompt.Parent.Parent:Destroy()
	end
	T.check(SS.GetOwner(ia) == a, "tycoon exploits: the plot still belongs to its owner")

	-- no plot: no purchases
	local c = join("TyNoPlot")
	DataS.AddCash(c, 1000)
	homeAction(c, "Upgrade", "Press1")
	advance(0.3)
	local okNo, reasonNo = Ty.Buy(c, "Press1")
	T.check(not okNo and (Ty.GetHome(c).Stations.Press1 or 0) == 0 and cashOf(c) == 1000 and tostring(reasonNo):find("Claim a home", 1, true) ~= nil,
		"tycoon exploits: no purchases without a claimed plot", tostring(reasonNo))

	-- junk HomeAction arguments
	local junk = {
		{ 5, "Press1" }, { nil, nil }, { {}, "x" }, { string.rep("U", 500), "Press1" },
		{ "Upgrade", 0 / 0 }, { "Upgrade", -1 }, { "Upgrade", math.huge }, { "Upgrade", {} }, { "Upgrade", "Nope" },
		{ "Upgrade", string.rep("x", 1000) }, { "Upgrade", "Prestige" }, { "Upgrade", "ArenaGate" }, { "Upgrade", "FusionMachine" },
		{ "GardenSet", 0 / 0 }, { "GardenSet", { 0 / 0, "x" } }, { "GardenSet", { -1, "x" } }, { "GardenSet", { math.huge } },
		{ "GardenSet", { "1", "x" } }, { "GardenSet", { 1.5, "x" } }, { "GardenSet", "1" }, { "GardenSet", { Slot = {}, Key = {} } },
		{ "Prestige", {} }, { "GoHome", 0 / 0 }, { "Teleport", 1 }, { "AddCash", 1e9 },
	}
	local cashA, cashC = cashOf(a), cashOf(c)
	local before = stationsText(Ty.GetHome(a))
	for i, args in ipairs(junk) do
		homeAction(a, args[1], args[2])
		homeAction(c, args[1], args[2])
		if i % 4 == 0 then
			advance(0.6)
		end
	end
	advance(0.6)
	T.check(stationsText(Ty.GetHome(a)) == before and cashOf(a) == cashA and cashOf(c) == cashC and cashOf(a) >= 0,
		"tycoon exploits: junk / negative / NaN / huge / wrong-type HomeAction arguments change nothing",
		stationsText(Ty.GetHome(a)) .. " cash " .. cashOf(a))

	-- spam: one purchase per cooldown, the burst budget
	local price2 = Cat.PriceAt("Press1", 2, Ty.GetHome(a))
	DataS.AddCash(a, price2 * 3)
	local cash1 = cashOf(a)
	for _ = 1, 50 do
		homeAction(a, "Upgrade", "Press1")
	end
	advance(0.05)
	T.check(Ty.GetHome(a).Stations.Press1 == 2 and cash1 - cashOf(a) == price2, "tycoon exploits: 50 'Upgrade' requests in one frame buy exactly one level",
		"level " .. tostring(Ty.GetHome(a).Stations.Press1) .. ", paid " .. (cash1 - cashOf(a)))
	advance(1.0)
	-- Cash lying on the lawn (another server's coins, a merge): it waits in the Welcome-back pile, scooped once
	DataS.MutateHome(a, function(h)
		h.CollectorCash = 40.5
	end)
	advance(1.1) -- the tick reconciles the ledger with the bank
	local pw = Ty.Piles(a)
	T.check(pw and pw.W and near(pw.W.Value, 40.5, 1e-6), "tycoon exploits: Cash that appears in the bank waits in the Welcome-back pile (the ledger follows the bank)")
	Mock.Teleport(a, CFrame.new(pw.W.Pos + Vector3.new(0, 3, 0)))
	cash1 = cashOf(a)
	for _ = 1, 30 do
		homeAction(a, "Collect")
		Ty.Collect(a)
	end
	local left = Ty.GetHome(a).CollectorCash
	T.check(cashOf(a) - cash1 == 40 and near(left, 0.5, 1e-6), "tycoon exploits: 60 collects in one frame pay the lawn out once (whole Cash only, the fraction stays)",
		"paid " .. (cashOf(a) - cash1) .. ", left " .. tostring(left))
	advance(2.0)
	T.check(cashOf(a) - cash1 == 40 and near(Ty.GetHome(a).CollectorCash, 0.5, 1e-6), "tycoon exploits: ...and standing there pays nothing more")
	away(a)

	-- not enough cash: refused, nothing taken; never negative
	local need = Cat.PriceAt("Press1", 3, Ty.GetHome(a))
	local have = cashOf(a)
	if have >= need then
		DataS.SpendCash(a, have - need + 1)
	end
	have = cashOf(a)
	local okPoor, whyPoor = Ty.Buy(a, "Press1")
	T.check(not okPoor and cashOf(a) == have and Ty.GetHome(a).Stations.Press1 == 2 and tostring(whyPoor):find("Not enough Cash", 1, true) ~= nil,
		"tycoon exploits: a purchase without enough Cash is refused and takes nothing", tostring(whyPoor))

	-- prestige before it is ready
	local okP, whyP = Ty.Prestige(a)
	T.check(not okP and Ty.GetHome(a).Prestige == 0 and cashOf(a) == have, "tycoon exploits: Prestige before Home Level 40 + Sky Castle is refused", tostring(whyP))

	-- GardenSet rules (any role; the training lock; owned copies; open places)
	local Eco, Combat = petsByRole()
	local PC = K.M["shared/PetCatalog"]
	DataS.MutateHome(a, function(h)
		h.Stations.Press1 = 2
		h.Level = Cat.HomeLevelOf(h)
	end)
	advance(1.2)
	if Eco and Combat then
		givePet(a, Eco.Id, 1)
		givePet(a, Combat.Id, 1)
		local ok1 = Ty.GardenSet(a, 1, Combat.Id)
		local combatIncome = Ty.IncomePerSecond(a)
		local ok2, why2 = Ty.GardenSet(a, 1, "ghost_pet_404")
		local ok3, why3 = Ty.GardenSet(a, 4, Eco.Id)
		local ok4 = Ty.GardenSet(a, 1, Eco.Id)
		local ecoIncome = Ty.IncomePerSecond(a)
		local ok5, why5 = Ty.GardenSet(a, 1, Eco.Id .. "@Golden")
		local h = Ty.GetHome(a)
		T.check(ok1 == true and combatIncome > 0, "tycoon exploits: GardenSet accepts a Combat pet (any role works in the Garden)")
		T.check(near(combatIncome / ecoIncome, Cat.PetPower(entryOf(Combat)) / Cat.PetPower(entryOf(Eco)), 1e-6) and PC.RoleMultiplier(Combat) == 1 and PC.RoleMultiplier(Eco) == 1.6,
			"tycoon exploits: a Combat pet earns 1/1.6 of an Economy pet (RoleMult 1 vs 1.6 inside PetPower)", string.format("%.3f / %.3f", combatIncome, ecoIncome))
		T.check(not ok2 and h.Garden[1] == Eco.Id, "tycoon exploits: GardenSet refuses unknown keys", tostring(why2))
		T.check(not ok3 and tostring(why3):find("locked", 1, true) ~= nil, "tycoon exploits: GardenSet refuses a place above the open count (3 at 0 stars)", tostring(why3))
		T.check(ok4 and not ok5, "tycoon exploits: GardenSet refuses a tier copy the player does not own", tostring(why5))
		local ok6, why6 = Ty.GardenSet(a, 2, Eco.Id)
		T.check(not ok6 and tostring(why6):find("no free copy", 1, true) ~= nil and Ty.GetHome(a).Garden[2] == nil,
			"tycoon exploits: one copy cannot work in two garden slots", tostring(why6))
		givePet(a, Eco.Id, 1)
		Ty.GardenSet(a, 1, nil)
		DataS.MutateGrowth(a, function(g)
			g[Eco.Id] = g[Eco.Id] or {}
			g[Eco.Id].Job = { Stat = "Defense", Ends = os.time() + 90, Rank = 1, Slot = 1, Paid = 0 }
		end)
		local ok7, why7 = Ty.GardenSet(a, 1, Eco.Id)
		T.check(not ok7 and tostring(why7):find("is training", 1, true) ~= nil and tostring(why7):find("left", 1, true) ~= nil,
			"tycoon exploits: a training pet (DataService.TrainingKeys) cannot be placed in the Garden ('<name> is training (1:30 left)')", tostring(why7))
		DataS.MutateGrowth(a, function(g)
			g[Eco.Id].Job = nil
		end)
		local ok8 = Ty.GardenSet(a, 1, Eco.Id)
		local ok9 = Ty.GardenSet(a, 1, nil)
		T.check(ok8 and ok9 and Ty.GetHome(a).Garden[1] == nil, "tycoon exploits: GardenSet places and clears (nil) a slot")
		local okN = Ty.GardenSet(a, 0 / 0, Eco.Id)
		local okM = Ty.GardenSet(a, 999, Eco.Id)
		T.check(not okN and not okM, "tycoon exploits: NaN / out-of-range garden slots are refused")
		-- a garden pet that is no longer owned stops earning
		Ty.GardenSet(a, 1, Eco.Id)
		local with = Ty.IncomePerSecond(a)
		local prof = DataS.GetProfile(a)
		PK().Remove(prof, Eco.Id, PK().Count(prof, Eco.Id))
		local without = Ty.IncomePerSecond(a)
		T.check(without < with, "tycoon exploits: a garden pet that left the inventory stops earning", with .. " -> " .. without)
	else
		T.fail("tycoon exploits: (precondition) the catalog has an Economy and a Combat pet")
	end
	T.check(cashOf(a) >= 0 and cashOf(b) >= 0 and cashOf(c) >= 0, "tycoon exploits: Cash never goes negative")
	leave(a)
	leave(b)
	leave(c)
	K.flushErrors("p2tycoon_exploits")
	K.flushWarnings("p2tycoon_exploits", { "HomeBuilder is missing" })
end)

----------------------------------------------------------------------------------------------------
-- p2tycoon_offline
----------------------------------------------------------------------------------------------------
S.p2tycoon_offline = guarded("p2tycoon_offline", function()
	if not K.needBoot() then
		return
	end
	local SS, DataS = mod("SpotService"), mod("DataService")
	local Ty, Cat = TS(), TC()
	if not Ty or not Cat then
		T.fail("tycoon: TycoonService and TycoonCatalog load")
		return
	end
	local name, userId = "TyOffline", 963501
	local p = rejoin(name, userId)
	local first = freeIndex()
	claim(p, first)
	local Eco = petsByRole()
	DataS.MutateHome(p, function(h)
		h.Stations.Garden = 1
		h.Stations.Press1 = 6
		h.Stations.Vault = 1
		h.Level = Cat.HomeLevelOf(h)
	end)
	givePet(p, Eco.Id, 1)
	Ty.GardenSet(p, 1, Eco.Id)
	away(p)
	advance(1.2)
	local home = Ty.GetHome(p)
	local income = Ty.IncomePerSecond(p)
	T.check(income > 0 and Cat.StationLevel(home, "Vault") == 1, "tycoon offline: (precondition) a home with a Vault and a garden pet earns", tostring(income))
	advance(16) -- the periodic LastSeen refresh (every 15 s while online)
	local seen = Ty.GetHome(p).LastSeen or 0
	T.check(seen > 0 and os.time() - seen <= 16, "tycoon offline: LastSeen is refreshed while the player is online", tostring(seen))
	leave(p)
	advance(1.0)
	T.check(SS.GetOwner(first) == nil, "tycoon offline: leaving released the plot")
	local key = config().Tokens.DataStoreName .. "/u_" .. userId
	local rec = Mock.DataStore.Data[key]
	if not T.check(rec ~= nil and type(rec.Home) == "table" and (rec.Home.LastSeen or 0) > 0, "tycoon offline: the save holds Home.LastSeen") then
		return
	end
	local awayFor = 2 * 3600
	rec.Home.LastSeen = os.time() - awayFor
	local storedBank = rec.Home.CollectorCash or 0
	local storedCash = rec.Cash or 0
	local storedBerries = rec.Berries or 0
	local want = Cat.OfflineEarnings(home, awayFor, income)
	local mark = K.logSize()
	p = rejoin(name, userId)
	advance(4.0)
	T.check(want > 0 and cashOf(p) == storedCash, "tycoon offline: offline coins never go to the Cash balance (" .. want .. " owed)", "cash " .. cashOf(p) .. " stored " .. tostring(storedCash))
	local bank = Ty.GetHome(p).CollectorCash
	T.check(abs(bank - (storedBank + floor(want))) < 1, "tycoon offline: the Vault's offline coins go INTO the bank with LastSeen (the Welcome-back pile)",
		"bank " .. tostring(bank) .. " stored " .. tostring(storedBank) .. " + " .. tostring(want))
	T.eq(DataS.GetBerries(p) - storedBerries, floor(floor(want) * Cat.Berries.Share), "tycoon offline: ...and offline x Share berries land in the basket once")
	T.check(K.notified(p, "Welcome back! Your pets made", "good", mark), "tycoon offline: a 'Welcome back! Your pets made $X while you were away' side toast")
	advance(2)
	T.check(near(Ty.GetHome(p).CollectorCash, bank, 1e-6) and cashOf(p) == storedCash, "tycoon offline: paid once (LastSeen moved on)")
	T.check(K.notified(p, "Welcome back! Press E at your gate", "info", mark), "tycoon offline: a returning player whose last plot is free gets 'Welcome back! Press E at your gate'")
	T.check(SS.GetSpot(p) == nil and SS.SuggestSpot(p) == spots()[first], "tycoon offline: ...and GoToSpot / the guide lead to that gate (SuggestSpot), nothing is claimed yet")

	-- the saved build comes back on whichever plot is claimed; the offline coins wait in the Welcome-back pile
	local blocker = join("TyBlock")
	claim(blocker, first)
	local second = freeIndex(first)
	claim(p, second)
	local restored = Ty.GetHome(p)
	T.check(SS.GetSpot(p) == spots()[second] and restored.Stations.Press1 == 6 and restored.Stations.Vault == 1,
		"tycoon offline: the saved build is restored on another plot")
	local piles = Ty.Piles(p)
	T.check(piles and piles.W and near(piles.W.Value, bank, 1e-6) and tostring(spots()[second].Folder:GetAttribute("CoinDrops")):find("W=5", 1, true) ~= nil,
		"tycoon offline: the Welcome-back pile holds the offline coins (CoinDrops 'W=5')")
	local cashBefore = cashOf(p)
	Mock.Teleport(p, CFrame.new(piles.W.Pos + Vector3.new(0, 3, 0)))
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, floor(bank), "tycoon offline: scooping the Welcome-back pile pays the offline coins exactly once")
	advance(1.0)
	T.eq(cashOf(p) - cashBefore, floor(bank), "tycoon offline: ...and nothing more")
	away(p)
	if hasHomeBuilder() then
		local models = stationModels(second)
		T.check(models.Press1 and models.Press1:GetAttribute("Level") == 6 and models.Vault ~= nil, "tycoon offline: ...its stations stand on the new plot")
	end
	advance(1.2)
	T.eq(spots()[second].SubLabel.Text, "Home Level " .. Cat.HomeLevelOf(restored), "tycoon offline: ...and its nameplate shows the Home Level")
	leave(blocker)
	leave(p)
	K.flushErrors("p2tycoon_offline")
	K.flushWarnings("p2tycoon_offline", { "HomeBuilder is missing" })
end)

return S
