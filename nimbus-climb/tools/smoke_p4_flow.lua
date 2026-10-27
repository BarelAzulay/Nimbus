-- smoke_p4_flow.lua: the END-TO-END Phase 4 flow (ARCHITECTURE_V3.md "Phase 4: pets make the money" + "Phase 4 build
-- contract" 8.1): several simulated players on the booted game, through the same doors a client uses (ProximityPrompts,
-- walking over coins, the HomeAction / PetCare / EquipPet / BuyRoulette / BattleRequest / TutorialEvent remotes, the
-- home portal, the developer chat command) while TycoonService, PetCareService, BattleService, TutorialService,
-- SpotService, HomeBuilder, PetService, DevService and DataService all run at once. Cash for big purchases comes from
-- DataService.AddCash (a stand-in for hours of garden income). Every scenario sets up and cleans up its own players.
-- Loaded by tools/smoke.py in BOTH worlds (ARGS.context picks the half). Server scenarios (booted):
--   p4flow_new       Nia, a brand-new player (who is also the game's owner, for /petlevel), and Rex, a visitor: claim ->
--                    the free Pet Garden (the only pad) -> a pet in place 1 -> (Phase 5) it roams and poops a Cloud Cash
--                    coin, Rex walking over it scoops nothing, Nia's walk scoops it once -> the Berry Farm + the Food
--                    Machine -> the owner-only FeedPrompt and one machine feed paid in berries -> Champion Ring rounds
--                    1-3 with her one level-1 pet, driven by the shared Phase 5 driver (no InBattle gap, paid once,
--                    Ring.Best / Runs) -> /petlevel 20 + EVOLVE (stage 1, the LevelFactor x1.5 bonus, a Common never
--                    stage 2) -> the Training Place: Train with the lock (no equip, no garden place) and the automatic
--                    return to place 1 with the rank -> Prestige: garden place 4 opens, the Garden stays built at Lv 1,
--                    the pet keeps its level / stage / rank; a skipped tutorial never shows chapter 4.
--   p4flow_migrate   Vic, a Phase 3 save (Prestige 1, presses, Collector Cash, leftover Feasts, two Gym pets, a 6-pet
--                    Garden L6, the Phase 3 tutorial finished): the P4 + P5 migrations in ONE load (Home Level never
--                    down, the Manor kept, the presses folded into one Berry Farm, the Collector into LegacyMagnet,
--                    LegacySlots 6, LegacyPrices, the Gym emptied with its toast, the Feasts converted into berries), the
--                    claim (stations built, the welcome toast once, the Welcome-back heap scooped exactly once), old
--                    prices this run, a berry feed ("Ready to evolve!"), an EVOLVE, then tutorial chapter 4: train ->
--                    ring -> portal (+300 Tokens once).
--   p4flow_rejoin    Moe leaves mid-training (the job is saved, still locked after a quick rejoin, finished while he is
--                    away: the toast, the rank, the pet back with him) and mid-ring-run (Runs + 1 in the leave save,
--                    the pocket freed, no battle after the rejoin, nothing counted twice).
--   p4flow_merge     Kai: the two-server merge of the Phase 4 data: a stale server's late write (a better ring record,
--                    two more runs, a rank it finished, the same rank this server finished, Cash) lands before this
--                    server saves: Ring.Best max, Runs delta, ranks max (one rank stays one rank), a running job kept,
--                    Cash delta; the live profile adopts it and a rejoin reads the same numbers.
--   client_p4flow    (client) Vic's real chapter-4 TutorialState messages from the server run: the card walks
--                    train > ring > portal with the server's targets, then the finale.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local IDS = { Nia = 989101, Rex = 989102, Vic = 989201, Moe = 989301, Kai = 989401 }

local S = {}
if CONTEXT ~= "server" then
	------------------------------------------------------------------------------------------------
	-- client world: Vic's real chapter-4 tutorial states (recorded by the server half) on the tutorial card
	------------------------------------------------------------------------------------------------
	S.client_p4flow = guarded("client_p4flow", function()
		local KC = _G.KC
		if not T.check(type(KC) == "table" and type(KC.toClient) == "function", "client p4 flow: (precondition) the client kit is loaded") then
			return
		end
		if REPLICATION == nil then
			T.warn("client p4 flow: no server replication log (the server flow did not run)")
			return
		end
		local advance = KC.advance
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
		local TCtl = moduleAt("client", "Controllers/TutorialController")
		if not T.check(TCtl ~= nil and type(TCtl.GetState) == "function", "client p4 flow: (precondition) TutorialController loads") then
			return
		end
		local function panel()
			local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
			local g = pg and pg:FindFirstChild("NimbusTutorial")
			return g and g:FindFirstChild("TutorialPanel")
		end
		local states = {}
		for i = 1, #REPLICATION do
			local e = REPLICATION[i]
			if e.kind == "remote" and e.remote == "TutorialState" and e.userId == IDS.Vic then
				local args = Mock.Deserialize(e.args)
				if type(args) == "table" and type(args[1]) == "table" then
					states[#states + 1] = args[1]
				end
			end
		end
		if not T.check(#states > 0, "client p4 flow: (precondition) Vic's TutorialState messages are in the replication log (p4flow_migrate ran)") then
			return
		end
		Mock.SetViewport(1920, 1080)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute("InBattle", nil)
		local errors0 = #Mock.Errors
		local order, chapters, ringTarget, finale = {}, {}, nil, false
		for _, st in ipairs(states) do
			KC.toClient("TutorialState", st)
			advance(0.8)
			local now = TCtl.GetState()
			local id = st.Done and "done" or (now and now.Id)
			if id and order[#order] ~= id then
				order[#order + 1] = id
			end
			if not st.Done then
				chapters[#chapters + 1] = tostring(st.Chapter)
				if st.Id == "ring" and type(st.Target) == "table" then
					ringTarget = st.Target
				end
			end
			if st.Done and st.Completed then
				finale = panel() ~= nil and panel().Visible
			end
		end
		local text = table.concat(order, ">")
		T.check(text:find("train>ring>portal", 1, true) ~= nil, "client p4 flow: Vic's real messages walk the card through chapter 4: train > ring > portal", text)
		T.check(not table.concat(chapters, ","):find("[^4,]"), "client p4 flow: ...every state of his is a chapter-4 state (a finished Phase 3 tutorial resumes there)", table.concat(chapters, ","))
		local rt = {}
		for k, v in pairs(type(ringTarget) == "table" and ringTarget or {}) do
			rt[#rt + 1] = tostring(k) .. "=" .. typeof(v) .. ":" .. tostring(v)
		end
		table.sort(rt)
		T.check(type(ringTarget) == "table" and (ringTarget.Kind == "Arena" or ringTarget.Arena == "Ring") and typeof(ringTarget.Position) == "Vector3",
			"client p4 flow: ...the 'ring' card carries the server's Champion Ring target (resolved to a world position)", table.concat(rt, " "))
		T.check(finale, "client p4 flow: ...and the finished tutorial shows the finale on the card")
		advance(7)
		T.check(panel() == nil or not panel().Visible, "client p4 flow: ...then the card leaves")
		-- leave the card hidden for the scenarios after this one (a Done state without the finale)
		local last = states[#states]
		last.Done, last.Completed = true, false
		KC.toClient("TutorialState", last)
		advance(1)
		T.eq(#Mock.Errors - errors0, 0, "client p4 flow: no client script errors")
		if KC.flushErrors then
			KC.flushErrors("client_p4flow")
		end
	end)
	return S
end

local abs, floor = math.abs, math.floor
local advance, config, mod = K.advance, K.config, K.mod
local ALLOWED_WARNINGS = { "[DataService]", "[GemService]", "HomeBuilder is missing" }
local WEAK = { "pebble_pup", "honey_bunny", "puddle_frog" } -- Commons (pebble_pup: Economy) that win the easy ring rounds

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
		BS = requireAt("server/Services/BattleService"),
		AB = requireAt("server/Services/ArenaBuilder"),
		HB = requireAt("server/Services/HomeBuilder"),
		TSv = mod("TutorialService"),
		DataS = mod("DataService"),
		SS = mod("SpotService"),
		TC = requireAt("shared/TycoonCatalog"),
		BC = requireAt("shared/BattleCatalog"),
		PK = requireAt("shared/PetKeys"),
		PC = K.M["shared/PetCatalog"],
		Steps = requireAt("shared/TutorialSteps"),
	}
end

local function ready(label)
	if not K.needBoot() then
		return nil
	end
	local X = svc()
	if not T.check(X.Ty and X.Care and X.BS and X.AB and X.TSv and X.TC and X.BC and X.PK and X.PC and X.Steps and X.SS,
		label .. ": (precondition) TycoonService, PetCareService, BattleService, ArenaBuilder, TutorialService and the catalogs load") then
		return nil
	end
	return X
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

local function count(map)
	local n = 0
	for _ in pairs(type(map) == "table" and map or {}) do
		n = n + 1
	end
	return n
end

local function listHas(list, v)
	for _, x in ipairs(type(list) == "table" and list or {}) do
		if x == v then
			return true
		end
	end
	return false
end

local function toasts(p, needle, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		local text = tostring(e.args[1])
		if needle == nil or text:find(needle, 1, true) then
			out[#out + 1] = text
		end
	end
	return out
end

local function toasted(p, needle, mark)
	return #toasts(p, needle, mark) > 0
end

local function cash(p)
	return mod("DataService").GetCash(p)
end

local function tokens(p)
	return mod("DataService").GetTokens(p)
end

local function home(p)
	return mod("DataService").GetHome(p)
end

local function level(p, id)
	local h = home(p)
	return (h and h.Stations and h.Stations[id]) or 0
end

local function fund(p, amount)
	local have = cash(p)
	if amount > have then
		mod("DataService").AddCash(p, amount - have)
	end
end

local function totalXp(p, key)
	local lv, xp = mod("DataService").GetPetLevel(p, key)
	local Cat = requireAt("shared/TycoonCatalog")
	local total = xp or 0
	for l = 1, (lv or 1) - 1 do
		total = total + Cat.XpToNext(l)
	end
	return total
end

local function join(name, wait)
	local p = Mock.AddPlayer(name, IDS[name])
	advance(wait or 1.2)
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.8)
end

local function givePet(p, key, n, lv)
	local DataS = mod("DataService")
	local PK = requireAt("shared/PetKeys")
	local prof = DataS.GetProfile(p)
	PK.Add(prof, key, n or 1)
	if lv then
		prof.PetLevels[key] = { Level = lv, Xp = 0 }
	end
	DataS.MarkDirty(p)
end

local function equipped(p)
	return mod("DataService").GetProfile(p).Equipped or {}
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
	return nil
end

-- walks to the gate (just outside it) and presses E on its ClaimPrompt; the plot index or nil
local function claim(p, index)
	index = index or freeIndex()
	if not index then
		return nil
	end
	local gate = mod("SpotService").GateCFrame(spots()[index])
	if gate and p.Character then
		Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
	end
	local prompt = claimPromptOf(index)
	if prompt then
		Mock.Trigger(prompt, p)
	end
	advance(0.6)
	return mod("SpotService").GetSpot(p) == spots()[index] and index or nil
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

local function carePrompt(info, stationId, name)
	local st = stationModel(info, stationId)
	for _, d in ipairs(st and st:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") and d.Name == name then
			return d
		end
	end
	return nil
end

local function away(p)
	Mock.Teleport(p, CFrame.new(config().Lobby.Origin + Vector3.new(0, 4, 0)))
end

local function standAt(p, pos)
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 0)))
end

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

-- every whole Cash amount a player scooped (TycoonService.CoinsScooped) since the ledger started
local function scoopLedger(Ty)
	local totals, calls = {}, {}
	local conn = Ty.CoinsScooped:Connect(function(player, amount)
		if player then
			totals[player.UserId] = (totals[player.UserId] or 0) + (tonumber(amount) or 0)
			calls[player.UserId] = (calls[player.UserId] or 0) + 1
		end
	end)
	return {
		of = function(p)
			return totals[p.UserId] or 0
		end,
		calls = function(p)
			return calls[p.UserId] or 0
		end,
		stop = function()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end,
	}
end

-- runs fn() while PetCatalog.RollPet always answers `petId`
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

-- the scenario frame: EventService's scheduler opens no raid meanwhile (the flows run late, when the game clock is
-- large: the next event may be anything), the BattleState traffic of the ring rounds stays out of the client replay,
-- and every player of the scenario leaves at the end (whatever happened)
local function scenario(name, fn)
	local run = guarded(name, function()
		local bs = requireAt("server/Services/BattleService")
		local realStartRaid = bs and bs.StartRaid
		if bs then
			bs.StartRaid = function()
				return false, "A raid is already running"
			end
		end
		local savedHook = Mock._onRemote
		if savedHook then
			Mock._onRemote = function(entry)
				if entry.remote ~= "BattleState" then
					savedHook(entry)
				end
			end
		end
		local players = {}
		local ok, err = pcall(fn, players)
		if savedHook then
			Mock._onRemote = savedHook
		end
		for _, p in ipairs(players) do
			if p and p.Parent then
				if bs and bs.IsInBattle and bs.IsInBattle(p) and bs.Forfeit then
					pcall(bs.Forfeit, p)
				end
			end
		end
		advance(0.5)
		for _, p in ipairs(players) do
			if p and p.Parent then
				Mock.RemovePlayer(p)
			end
		end
		advance(5)
		if bs then
			bs.StartRaid = realStartRaid
		end
		if not ok then
			error(err, 0)
		end
		K.flushErrors(name)
		K.flushWarnings(name, ALLOWED_WARNINGS)
	end)
	return run
end

----------------------------------------------------------------------------------------------------
-- the Champion Ring
----------------------------------------------------------------------------------------------------
local function positionOf(thing)
	if type(thing) == "table" then
		if typeof(thing.Position) == "Vector3" then
			return thing.Position
		end
		if typeof(thing.CFrame) == "CFrame" then
			return thing.CFrame.Position
		end
		return positionOf(thing.Pad or thing.Part or thing.Model)
	end
	if typeof(thing) ~= "Instance" or not thing:IsDescendantOf(workspace) then
		return nil
	end
	if thing:IsA("BasePart") then
		return thing.Position
	end
	local ok, cf = pcall(function()
		return thing:GetPivot()
	end)
	return ok and typeof(cf) == "CFrame" and cf.Position or nil
end

local function ringPortalPos(X)
	local info = X.AB.GetInfo and X.AB.GetInfo() or nil
	return positionOf(info and info.RingPortal) or positionOf(workspace:FindFirstChild("Portal_Ring", true))
end

local function toRing(X, p)
	local pos = ringPortalPos(X)
	if pos then
		Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 6)))
	end
	advance(0.1)
end

local function pocketCount()
	local pockets = workspace:FindFirstChild("BattlePockets")
	return pockets and #pockets:GetChildren() or 0
end

local function battleMsgs(p, fromIndex, kind)
	local out = {}
	local log = Mock.RemoteLog
	for i = (fromIndex or 0) + 1, #log do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and (kind == nil or e.args[1] == kind) then
			out[#out + 1] = e
		end
	end
	return out
end

-- starts the ring through the BattleRequest remote and follows it in 0.1 s steps until the run's final "End"
-- (Rewards.Final), opts.stopAfterWins won rounds, or opts.maxSeconds. out = { id, refused, starts, wins, finalEnd,
-- nilSamples (InBattle read nil while the run lived), ids }. Phase 5: a passive fighter deals no damage, so the
-- player is driven (the shared driver of smoke_p5_flow.lua: walk at the legal run toward the champion, ATTACK)
local function runRing(p, startRound, opts)
	opts = opts or {}
	local out = { starts = {}, wins = {}, nilSamples = 0, ids = {} }
	local cursor = K.logSize()
	local FK = _G.FlowKit5
	local drv = FK and FK.tracker(p, cursor) or nil
	Mock.FromClient(remote("BattleRequest"), p, "Ring", startRound)
	advance(0.1)
	local id = p:GetAttribute("InBattle")
	if type(id) ~= "string" then
		out.refused = table.concat(toasts(p, nil, cursor), " | ")
		return out
	end
	out.id = id
	out.ids[id] = true
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < (opts.maxSeconds or 900) do
		advance(0.1)
		if drv and opts.passive ~= true then
			FK.tick(drv, { remote = true })
		end
		local attr = p:GetAttribute("InBattle")
		if attr == nil then
			out.nilSamples = out.nilSamples + 1
		elseif type(attr) == "string" then
			out.ids[attr] = true
		end
		local finished = false
		for _, e in ipairs(battleMsgs(p, cursor, "Start")) do
			out.starts[#out.starts + 1] = e.args[2]
		end
		for _, e in ipairs(battleMsgs(p, cursor, "End")) do
			local m = e.args[2]
			if type(m) == "table" and m.Spectator ~= true and type(m.Rewards) == "table" then
				if m.Rewards.Final then
					out.finalEnd = m
					finished = true
				elseif m.Rewards.Next then
					out.wins[#out.wins + 1] = m
				end
			end
		end
		cursor = K.logSize()
		if finished or (opts.stopAfterWins and #out.wins >= opts.stopAfterWins) then
			break
		end
	end
	return out
end

-- the game's owner may run the developer chat commands (DevService): Nia owns this game for the scenario
local function becomeOwner(userId)
	local Config = config()
	local saved = { Studio = Mock.Options.Studio, CreatorId = game.CreatorId, CreatorType = game.CreatorType, Enabled = Config.Dev.Enabled }
	Mock.Options.Studio = false
	game.CreatorType = Enum.CreatorType.User
	game.CreatorId = userId
	Config.Dev.Enabled = true
	return function()
		Mock.Options.Studio = saved.Studio
		game.CreatorId = saved.CreatorId
		game.CreatorType = saved.CreatorType
		Config.Dev.Enabled = saved.Enabled
	end
end

----------------------------------------------------------------------------------------------------
-- p4flow_new: a brand-new player, from the claim to the first Prestige
----------------------------------------------------------------------------------------------------
S.p4flow_new = scenario("p4flow_new", function(players)
	local X = ready("p4 flow new")
	if not X then
		return
	end
	local Config = config()
	local DataS, Ty, TC, BC, PK, PC = X.DataS, X.Ty, X.TC, X.BC, X.PK, X.PC
	local petId = WEAK[1]
	local petDef = PC.Get(petId)
	if not T.check(petDef ~= nil and petDef.Role == "Economy" and petDef.Rarity == "Common", "p4 flow new: (precondition) " .. petId .. " is a Common Economy pet") then
		return
	end
	Mock.DataStore.Data[storeKey(IDS.Nia)] = nil
	Mock.DataStore.Data[storeKey(IDS.Rex)] = nil
	local restoreOwner = becomeOwner(IDS.Nia)
	local ledger = scoopLedger(Ty)
	local okRun, errRun = pcall(function()
		local nia = join("Nia")
		local rex = join("Rex")
		players[#players + 1] = nia
		players[#players + 1] = rex
		advance(4)
		Mock.FromClient(remote("TutorialEvent"), nia, "Skip")
		advance(0.4)
		T.check(DataS.GetTutorial(nia).Done == true, "p4 flow new: Nia skips the tutorial")

		-- claim -> the free Pet Garden, the only pad of a fresh home
		local index = claim(nia)
		local info = index and spots()[index]
		if not T.check(info ~= nil and Ty.GetPlot(nia) == info, "p4 flow new: Nia claims a home (E at a free gate)") then
			return
		end
		local pads = TC.AvailablePads(home(nia))
		T.check(#pads == 1 and pads[1].StationId == "Garden" and pads[1].Price == 0, "p4 flow new: her fresh home shows exactly one pad: the free Pet Garden")
		pressPad(nia, info, "Garden")
		away(nia)
		T.check(level(nia, "Garden") == 1 and cash(nia) == 0 and stationModel(info, "Garden") ~= nil, "p4 flow new: E on it builds the Pet Garden for free")
		-- a pet (the Cloud Roulette, with tokens) in garden place 1
		DataS.AddTokens(nia, 100)
		withRoll(petId, function()
			advance(0.3)
			Mock.FromClient(remote("BuyRoulette"), nia, "Cloud")
		end)
		advance(0.5)
		T.check(PK.Count(DataS.GetProfile(nia), petId) == 1 and listHas(equipped(nia), petId), "p4 flow new: her first pet from the Cloud Roulette is equipped (" .. petId .. ")")
		Mock.FromClient(remote("HomeAction"), nia, "GardenSet", { 1, petId })
		advance(0.4)
		T.check(home(nia).Garden[1] == petId and info.Folder:GetAttribute("GardenPets") == "1=" .. petId, "p4 flow new: ...and goes to work in garden place 1 (GardenPets)")
		local mark = K.logSize()
		advance(1.6)
		Mock.FromClient(remote("HomeAction"), nia, "GardenSet", { 4, petId })
		advance(0.4)
		T.check(home(nia).Garden[4] == nil and toasted(nia, "Garden place locked: Prestige to open it", mark), "p4 flow new: place 4 is locked before the first Prestige (3 places)")

		-- coins (Phase 5: the pet roams and poops Cloud Cash, the first poop one roam cycle after it was placed); only the
		-- owner scoops them, exactly once
		local pile = nil
		local tw = Mock.Clock.now
		while not pile and Mock.Clock.now - tw < 60 do
			for _, d in ipairs(Ty.Drops(nia) or {}) do
				if (d.Poops or 0) >= 1 and not pile then
					pile = { Coins = d.Poops, Pos = d.Position }
				end
			end
			advance(1)
		end
		if T.check(pile ~= nil and pile.Coins >= 1, "p4 flow new: within one roam cycle her pet poops a Cloud Cash coin (TycoonService.Drops)", pile and tostring(pile.Coins) or "no drop") then
			local bank0, rexCash = home(nia).CollectorCash, cash(rex)
			standAt(rex, pile.Pos)
			advance(0.6)
			away(rex)
			T.check(cash(rex) == rexCash and ledger.of(rex) == 0 and home(nia).CollectorCash >= bank0 - 1e-6, "p4 flow new: Rex walking over Nia's coins scoops nothing")
			local c0, total0 = cash(nia), cash(nia) + home(nia).CollectorCash
			standAt(nia, pile.Pos)
			advance(0.3)
			away(nia)
			local gained = cash(nia) - c0
			T.check(gained >= 1 and gained == ledger.of(nia) and ledger.calls(nia) >= 1, "p4 flow new: Nia walking over her pile scoops it (+$" .. gained .. ", CoinsScooped)")
			local total1 = cash(nia) + home(nia).CollectorCash
			local oneCoin = (TC.Coins.LuckyMult + 1) * Ty.IncomePerSecond(nia) * TC.Coins.MealSeconds * TC.Coins.PoopMeals
			T.check(total1 >= total0 - 1e-6 and total1 <= total0 + oneCoin + 1e-6 and home(nia).CollectorCash < bank0,
				"p4 flow new: ...paid once: Cash + the coins on the lawn stay the same (only a new coin may add)", total0 .. " -> " .. total1)
		end

		-- the Berry Farm and the Food Machine (pads with E), the owner-only FeedPrompt, one machine feed (Phase 5: berries)
		fund(nia, TC.PriceFor("Press1", 1))
		pressPad(nia, info, "Press1")
		fund(nia, TC.PriceFor("Kitchen", 1))
		pressPad(nia, info, "Kitchen")
		away(nia)
		T.check(level(nia, "Press1") == 1 and level(nia, "Kitchen") == 1 and stationModel(info, "Kitchen") ~= nil, "p4 flow new: the Berry Farm, then the Food Machine")
		advance(1.2)
		local feedPrompt = carePrompt(info, "Kitchen", "FeedPrompt")
		if T.check(feedPrompt ~= nil and feedPrompt:GetAttribute("OwnerUserId") == nia.UserId, "p4 flow new: the Food Machine has Nia's FeedPrompt") then
			local at = promptPosition(feedPrompt)
			mark = K.logSize()
			if at then
				Mock.Teleport(rex, CFrame.new(at + Vector3.new(0, 0, -3)))
				Mock.Teleport(nia, CFrame.new(at + Vector3.new(2, 0, -3)))
			end
			Mock.Trigger(feedPrompt, rex)
			Mock.Trigger(feedPrompt, nia)
			advance(0.3)
			away(rex)
			away(nia)
			local op = K.lastRemote("OpenPanel", nia.UserId, mark)
			T.check(#K.remotesFor("OpenPanel", rex.UserId, mark) == 0 and op ~= nil and op.args[1] == "Pets" and type(op.args[2]) == "table" and op.args[2].Action == "Feed",
				"p4 flow new: E opens the feed list for Nia only (OpenPanel 'Pets' / Feed)")
		end
		local price, xpGain = TC.FeedBerries(petDef, 1), TC.FeedXp(1, 1)
		DataS.SpendBerries(nia, DataS.GetBerries(nia))
		DataS.AddBerries(nia, price) -- (a stand-in for the berries her garden grows)
		advance(0.6)
		local c1, xp1 = cash(nia), totalXp(nia, petId)
		local fed = nil
		local fedConn = X.Care.Fed:Connect(function(player, key, foodId)
			if player == nia then
				fed = { key, foodId }
			end
		end)
		Mock.FromClient(remote("PetCare"), nia, "Feed", petId)
		advance(0.4)
		fedConn:Disconnect()
		T.check(cash(nia) == c1 and DataS.GetBerries(nia) == 0 and totalXp(nia, petId) - xp1 == xpGain and (DataS.GetPetLevel(nia, petId)) == 1,
			"p4 flow new: one machine feed: " .. price .. " berries (no Cash) for +" .. xpGain .. " XP (still level 1)", (c1 - cash(nia)) .. " / " .. (totalXp(nia, petId) - xp1))
		T.check(fed ~= nil and fed[1] == petId and fed[2] == "Berries", "p4 flow new: ...PetCareService.Fed fires (a berry feed)")

		-- the Champion Ring: rounds 1-3 with one level-1 pet. Bug batch 2 #18: a garden pet is busy gardening (the ring's
		-- fallback skips it), so she takes it out of the Garden and equips it in ONE request (the "Remote recall")
		mark = K.logSize()
		Mock.FromClient(remote("HomeAction"), nia, "GardenRecall", { Key = petId, To = "Equip" })
		advance(0.6)
		T.check(home(nia).Garden[1] == nil and listHas(equipped(nia), petId) and toasted(nia, "left the garden and follows you now", mark),
			"p4 flow new: GardenRecall takes her pet out of the Garden and equips it in one request (bug batch 2 #18)")
		local runs0 = DataS.GetRing(nia)
		local cash2, tok2, xp2 = cash(nia), tokens(nia), totalXp(nia, petId)
		toRing(X, nia)
		local run = runRing(nia, 1, { maxSeconds = 1500 })
		if T.check(run.id ~= nil, "p4 flow new: at the Champion Ring portal BattleRequest 'Ring' starts round 1", tostring(run.refused)) then
			T.check(#run.wins >= 3, "p4 flow new: her one level-1 pet wins rounds 1, 2 and 3", #run.wins .. " wins")
			T.check(run.finalEnd ~= nil and run.nilSamples == 0, "p4 flow new: ...the run ends by itself, with no InBattle gap between the rounds",
				run.finalEnd and tostring(run.finalEnd.Outcome) or "still running")
			local cashSum, xpSum, tokSum, okEnds = 0, 0, 0, true
			for i, m in ipairs(run.wins) do
				local rw = m.Rewards
				local floorCash = BC.RingRewards(i, 0, true).Cash
				if not (rw.Round == i and rw.Next == i + 1 and rw.Record == true and type(rw.Cash) == "number" and rw.Cash >= floorCash and rw.Xp == BC.Ring.XpBase + BC.Ring.XpPerRound * i) then
					okEnds = false
				end
				cashSum, xpSum, tokSum = cashSum + (rw.Cash or 0), xpSum + (rw.Xp or 0), tokSum + (rw.Tokens or 0)
			end
			local lossXp = run.finalEnd and run.finalEnd.Rewards.Xp or 0
			T.check(okEnds, "p4 flow new: every won round pays its Cash (at least the floor x3: a first run's rounds are records) and 20 + 6r XP")
			T.eq(cash(nia) - cash2, cashSum, "p4 flow new: ...Cash paid exactly once per round")
			T.eq(tokens(nia) - tok2, tokSum, "p4 flow new: ...Tokens likewise")
			T.eq(totalXp(nia, petId) - xp2, xpSum + lossXp, "p4 flow new: ...and the pet's XP grew by the rounds' XP (+ the loss third)")
			local ring = DataS.GetRing(nia)
			T.check(ring.Best == #run.wins and ring.Runs == (runs0 and runs0.Runs or 0) + 1, "p4 flow new: Ring.Best = the rounds won, Runs + 1",
				"Best " .. tostring(ring.Best) .. " Runs " .. tostring(ring.Runs))
		end
		advance(5) -- the return teleport comes 4 s after the end
		T.check(nia:GetAttribute("InBattle") == nil and not X.BS.IsInBattle(nia), "p4 flow new: after the run she is out of the battle")
		away(nia)

		-- /petlevel 20 (the owner's developer command) + EVOLVE
		mark = K.logSize()
		advance(0.6)
		Mock.FireSignal(nia, "Chatted", "/petlevel 20")
		advance(0.8)
		local lv20, xp20 = DataS.GetPetLevel(nia, petId)
		T.check(lv20 == 20 and xp20 == 0, "p4 flow new: '/petlevel 20' sets her equipped pet to level 20", tostring(lv20) .. " / " .. tostring(xp20))
		T.eq(nia:GetAttribute(Config.Attr.EquippedInfo), "20:0", "p4 flow new: ...EquippedInfo '20:0' (the card above the follower)")
		-- back to work in garden place 1 (bug batch 2 #18: it leaves her side for it)
		Mock.FromClient(remote("HomeAction"), nia, "GardenSet", { 1, petId })
		advance(0.4)
		T.check(home(nia).Garden[1] == petId and not listHas(equipped(nia), petId), "p4 flow new: back in garden place 1 it stops following (one job at a time)")
		advance(1.2) -- (one garden tick with the new level)
		local income0 = Ty.IncomePerSecond(nia)
		mark = K.logSize()
		Mock.FromClient(remote("PetCare"), nia, "Evolve", petId)
		advance(0.6)
		T.eq(DataS.GetEvolution(nia, petId), 1, "p4 flow new: EVOLVE at level 20: stage 1")
		T.check(toasted(nia, "evolved!", mark), "p4 flow new: ...'<pet> evolved! Level bonus x1.5!' toast")
		local evo = nil
		for _, e in ipairs(K.remotesFor("OpenPanel", nia.UserId, mark)) do
			if e.args[1] == "Evolve" then
				evo = e.args[2]
			end
		end
		T.check(type(evo) == "table" and evo.Key == petId and evo.Stage == 1, "p4 flow new: ...OpenPanel('Evolve', {Key, Stage = 1}) for her EVOLVE moment")
		advance(1.2)
		-- (bug batch 2 #18: the evolved pet works in garden place 1, so it does not follow: no follower card)
		T.eq(nia:GetAttribute(Config.Attr.EquippedInfo) or "", "", "p4 flow new: ...EquippedInfo stays empty (the pet gardens, it does not follow)")
		local evoGain = PC.LevelFactor(20, 1) / PC.LevelFactor(20, 0)
		T.check(abs(Ty.IncomePerSecond(nia) / income0 - evoGain) < 1e-6, "p4 flow new: ...its coins grow x" .. string.format("%.3f", evoGain) .. " (Phase 5: the level bonus x1.5)", income0 .. " -> " .. Ty.IncomePerSecond(nia))
		mark = K.logSize()
		advance(1.2)
		Mock.FromClient(remote("PetCare"), nia, "Evolve", petId)
		advance(0.6)
		T.check(DataS.GetEvolution(nia, petId) == 1 and #toasts(nia, nil, mark) >= 1, "p4 flow new: a Common never evolves a second time (refused with a toast)",
			table.concat(toasts(nia, nil, mark), " | "))

		-- the Training Place: Train with the lock, then the automatic return to garden place 1
		fund(nia, TC.PriceFor("Gym", 1))
		pressPad(nia, info, "Gym")
		away(nia)
		T.eq(level(nia, "Gym"), 1, "p4 flow new: the Training Place pad builds it")
		local cost = TC.TrainCost(petDef, 1)
		fund(nia, cost)
		local c3 = cash(nia)
		mark = K.logSize()
		Mock.FromClient(remote("PetCare"), nia, "Train", petId, "Physique")
		advance(0.4)
		local job = DataS.GetGrowth(nia, petId).Job
		T.check(type(job) == "table" and job.Stat == "Physique" and job.Rank == 1 and job.From == "Garden:1" and c3 - cash(nia) == cost,
			"p4 flow new: Train: Physique rank 1 for $" .. tostring(cost) .. ", remembering garden place 1", job and tostring(job.From) or "no job")
		T.check(DataS.TrainingKeys(nia)[petId] == true and home(nia).Garden[1] == nil and not listHas(equipped(nia), petId),
			"p4 flow new: ...the pet leaves its garden place and her side (the training lock)")
		advance(1.6)
		mark = K.logSize()
		Mock.FromClient(remote("EquipPet"), nia, petId)
		advance(0.4)
		T.check(not listHas(equipped(nia), petId) and toasted(nia, "is training", mark), "p4 flow new: a training pet cannot be equipped ('is training')")
		advance(1.6)
		mark = K.logSize()
		Mock.FromClient(remote("HomeAction"), nia, "GardenSet", { 1, petId })
		advance(0.4)
		T.check(home(nia).Garden[1] == nil and toasted(nia, "is training", mark), "p4 flow new: ...nor put in the Garden")
		mark = K.logSize()
		advance(TC.TrainSeconds(1) + 2)
		local g = DataS.GetGrowth(nia, petId)
		T.check(g.Physique == 1 and g.Job == nil and home(nia).Garden[1] == petId and toasted(nia, "finished Physique training", mark),
			"p4 flow new: after its time: Physique rank 1, back in garden place 1 by itself (with a toast)")

		-- Prestige: garden place 4, the Garden still built, the pet keeps its growth
		DataS.MutateHome(nia, function(h)
			for _, def in ipairs(TC.Stations) do
				if not def.KeepOnPrestige then
					h.Stations[def.Id] = def.MaxLevel
				end
			end
			h.Stations.FusionMachine = 0
			h.Stations.ArenaGate = 0
			h.Level = TC.HomeLevelOf(h)
		end)
		advance(1.2)
		T.check(TC.CanPrestige(home(nia)) == true, "p4 flow new: (stand-in for hours of play) her home is prestige-ready")
		mark = K.logSize()
		Mock.FromClient(remote("HomeAction"), nia, "Prestige")
		advance(0.6)
		local h = home(nia)
		T.check(h.Prestige == 1 and (h.Stations.Garden or 0) == 1 and TC.GardenSlots(h) == 4, "p4 flow new: Prestige 1: the Pet Garden stays built (Lv 1) and opens place 4")
		T.check(toasted(nia, "Prestige 1!", mark) and toasted(nia, "Garden place 4 unlocked!", mark), "p4 flow new: ...'Prestige 1!' and 'Garden place 4 unlocked!'")
		advance(1.2)
		T.check(stationModel(info, "Garden") ~= nil and stationModel(info, "Kitchen") == nil and info.Folder:GetAttribute("GardenSlots") == 4,
			"p4 flow new: ...the Garden stands on the plot, the Food Machine is gone (GardenSlots 4)")
		T.check(h.Garden[1] == petId and (DataS.GetPetLevel(nia, petId)) == 20 and DataS.GetEvolution(nia, petId) == 1 and DataS.GetGrowth(nia, petId).Physique == 1
			and Ty.IncomePerSecond(nia) > 0, "p4 flow new: ...her pet keeps its place, level 20, stage 1 and its rank, and keeps making coins")
		givePet(nia, WEAK[2], 1)
		Mock.FromClient(remote("HomeAction"), nia, "GardenSet", { 4, WEAK[2] })
		advance(0.4)
		T.eq(home(nia).Garden[4], WEAK[2], "p4 flow new: a second pet now works in place 4")
		T.check(DataS.GetTutorial(nia).Done == true and not toasted(nia, "Pets tutorial complete", 0), "p4 flow new: her skipped tutorial never shows chapter 4")
	end)
	ledger.stop()
	restoreOwner()
	if not okRun then
		error(errRun, 0)
	end
end)

----------------------------------------------------------------------------------------------------
-- p4flow_migrate: a Phase 3 veteran's first Phase 4 session, then tutorial chapter 4
----------------------------------------------------------------------------------------------------
local function phase3Save(X, index)
	local ecos, combats = {}, {}
	for _, def in ipairs(X.PC.Pets) do
		if not def.EventOnly and def.Rarity ~= "Secret" and def.Rarity ~= "Mythic" then
			if def.Role == "Economy" and #ecos < 6 then
				ecos[#ecos + 1] = def.Id
			elseif def.Role == "Combat" and #combats < 3 then
				combats[#combats + 1] = def.Id
			end
		end
	end
	local pets, discovered, levels = {}, {}, {}
	for _, id in ipairs(ecos) do
		pets[id], discovered[id] = 1, true
	end
	for _, id in ipairs(combats) do
		pets[id], discovered[id] = 1, true
	end
	levels[ecos[1]] = { Level = 22, Xp = 0 } -- ready to evolve
	levels[combats[1]] = { Level = 15, Xp = 0 } -- the fighter
	levels[combats[2]] = { Level = 19, Xp = X.TC.XpToNext(19) - 100 } -- a Gym pet 100 XP short of level 20
	levels[combats[3]] = { Level = 6, Xp = 0 } -- the other Gym pet
	local stations = { Garden = 6, Press1 = 8, Press2 = 5, Press3 = 3, Collector = 3, Kitchen = 2, Gym = 2, House = 3, Vault = 1 }
	local garden = {}
	for i = 1, 6 do
		garden[i] = ecos[i]
	end
	local now = os.time()
	return {
		Version = 2, Tokens = 800, Cash = 2000, Gems = 50,
		Pets = pets, Equipped = { combats[1] }, Items = {},
		Stats = { Matches = 12, Wins = 9, TokensEarned = 4000, Spins = 20, BestTimes = {} },
		Discovered = discovered, IndexClaimed = {},
		Tutorial = { Step = X.Steps.ChapterStart[4], Done = true, Gifted = true }, -- a finished Phase 3 tutorial (step 19, done)
		SpotIndex = index,
		Home = {
			Level = X.TC.HomeLevelOf({ Stations = stations }), Prestige = 1, Stations = stations,
			Garden = garden, Gym = { combats[2], combats[3] }, CollectorCash = 1234, LastSeen = now - 30,
		},
		Food = { Feast = 2 },
		PetLevels = levels,
		UpdatedAt = now - 3600,
	}, ecos, combats
end

S.p4flow_migrate = scenario("p4flow_migrate", function(players)
	local X = ready("p4 flow migrate")
	if not X then
		return
	end
	local DataS, Ty, TC, PC = X.DataS, X.Ty, X.TC, X.PC
	local index = freeIndex()
	if not T.check(index ~= nil, "p4 flow migrate: (precondition) a free plot") then
		return
	end
	local save, ecos, combats = phase3Save(X, index)
	if not T.check(#ecos == 6 and #combats == 3, "p4 flow migrate: (precondition) six Economy and three Combat pets in the catalog") then
		return
	end
	local savedStations = {}
	for k, v in pairs(save.Home.Stations) do
		savedStations[k] = v
	end
	local homeLevel = save.Home.Level
	Mock.DataStore.Data[storeKey(IDS.Vic)] = save
	local ledger = scoopLedger(Ty)
	local okRun, errRun = pcall(function()
		local mark0 = K.logSize()
		local vic = join("Vic")
		players[#players + 1] = vic
		local rex = join("Rex") -- a visitor (his save from p4flow_new, if any, does not matter)
		players[#players + 1] = rex
		advance(5)
		-- the one-time migration
		local h = home(vic)
		local info0 = DataS.MigratedNow(vic, "P4")
		T.check(DataS.IsMigrated(vic, "P4") == true and type(info0) == "table" and info0.Veteran == true and info0.GymPets == 2,
			"p4 flow migrate: his first Phase 4 load runs the one-time migration (Migrations.P4, a veteran, 2 Gym pets freed)")
		-- (Phase 5: the same load also runs P5Home: the three presses fold into one Berry Farm, the Collector into the
		-- Garden's LegacyMagnet; the Home Level never drops)
		T.check(TC.HomeLevelOf(h) >= homeLevel and TC.HouseTierOf(h) == 3 and (h.Stations.Press1 or 0) >= 8 + 5 + 3 and h.Stations.Press2 == nil
			and h.Stations.Collector == nil and h.LegacyMagnet == 3, "p4 flow migrate: Home Level " .. homeLevel .. " or more and the Manor kept; the presses fold into a Berry Farm (Lv "
			.. tostring(h.Stations.Press1) .. "), the Collector into LegacyMagnet 3", tostring(h.Level) .. " HL " .. tostring(TC.HomeLevelOf(h)) .. " tier " .. tostring(TC.HouseTierOf(h)) .. " magnet " .. tostring(h.LegacyMagnet))
		T.check(h.LegacySlots == 6 and h.LegacyPrices == true and TC.GardenSlots(h) == 6, "p4 flow migrate: his 6-place Garden keeps 6 places this run (LegacySlots) and the old prices (LegacyPrices)")
		T.check(next(h.Gym or {}) == nil and toasted(vic, "The Gym is now the Training Place", mark0), "p4 flow migrate: the old Gym is emptied with its toast (the pets are back with him)")
		T.check(h.CollectorCash == 1234 and DataS.GetFood(vic, "Feast") == 0 and DataS.GetBerries(vic) == 2 * TC.Berries.LegacyFood.Feast and (DataS.GetPetLevel(vic, ecos[1])) == 22,
			"p4 flow migrate: Collector Cash and pet levels are kept; the 2 leftover Feasts became " .. (2 * TC.Berries.LegacyFood.Feast) .. " berries", tostring(DataS.GetBerries(vic)))
		local st = X.TSv.GetState(vic)
		T.check(st and st.Done == false and st.Chapter == 4 and st.Id == "train" and st.Step == X.Steps.ChapterStart[4],
			"p4 flow migrate: his finished Phase 3 tutorial resumes at chapter 4 ('train')", st and (tostring(st.Chapter) .. ":" .. tostring(st.Id)) or "no state")

		-- the claim: plants built, the welcome toast once, the Welcome-back pile
		local mark = K.logSize()
		local got = claim(vic, index)
		local info = got and spots()[got]
		if not T.check(info ~= nil, "p4 flow migrate: Vic claims his home") then
			return
		end
		away(vic)
		advance(1.5)
		T.eq(#toasts(vic, "Welcome to the new home!", mark), 1, "p4 flow migrate: one welcome toast ('Your presses grew into food plants...')")
		T.check(home(vic).Level == TC.HomeLevelOf(home(vic)) and home(vic).Level >= homeLevel, "p4 flow migrate: after the claim the stored Home Level mirrors the folded stations (never lower)",
			tostring(home(vic).Level))
		local wrong = {}
		for id, lv in pairs(home(vic).Stations) do
			local m = stationModel(info, id)
			if not m or m:GetAttribute("Level") ~= lv then
				wrong[#wrong + 1] = id
			end
		end
		T.check(#wrong == 0 and stationModel(info, "Press2") == nil and stationModel(info, "Collector") == nil, "p4 flow migrate: every (folded) station stands at its level, no old one", table.concat(wrong, ","))
		T.eq(info.Folder:GetAttribute("GardenSlots"), 6, "p4 flow migrate: GardenSlots 6 on the plot")
		local gp = tostring(info.Folder:GetAttribute("GardenPets"))
		local placed = 0
		for _ in gp:gmatch("[^;]+") do
			placed = placed + 1
		end
		T.eq(placed, 6, "p4 flow migrate: all six garden pets work (GardenPets)")
		local piles = Ty.Piles(vic)
		local w = piles and piles.W
		if T.check(w ~= nil and abs(w.Value - 1234) < 1e-6 and tostring(info.Folder:GetAttribute("CoinDrops")):find("W=", 1, true) ~= nil,
			"p4 flow migrate: his old Collector Cash waits in the Welcome-back heap ($1,234, CoinDrops 'W=')", w and tostring(w.Value) or "no pile") then
			local rexCash = cash(rex)
			standAt(rex, w.Pos)
			advance(0.6)
			away(rex)
			T.check(cash(rex) == rexCash and ledger.of(rex) == 0 and Ty.Piles(vic).W ~= nil and abs(Ty.Piles(vic).W.Value - 1234) < 1e-6,
				"p4 flow migrate: Rex, visiting, walks over Vic's Welcome-back pile: it stays Vic's")
			local c0, l0 = cash(vic), ledger.of(vic)
			standAt(vic, w.Pos)
			advance(0.3)
			away(vic)
			local gained = cash(vic) - c0
			local after = Ty.Piles(vic)
			T.check(gained >= 1234 and gained == ledger.of(vic) - l0 and (after == nil or after.W == nil or after.W.Value < 1),
				"p4 flow migrate: walking over it scoops it once (+$" .. gained .. ")")
			advance(0.6)
			local c2, l2 = cash(vic), ledger.of(vic)
			standAt(vic, w.Pos)
			advance(0.3)
			away(vic)
			local again = cash(vic) - c2
			T.check(again == ledger.of(vic) - l2 and again < 1234, "p4 flow migrate: ...a second walk finds no old Cash again (only new coins)", again .. " / " .. (ledger.of(vic) - l2))
		end
		-- old prices this run: no star multiplier until his next Prestige
		local farmLv = level(vic, "Press1")
		local okBuy, price = TC.CheckPurchase(home(vic), "Press1")
		T.check(okBuy == true and price == TC.PriceFor("Press1", farmLv + 1), "p4 flow migrate: the Berry Farm's next level costs the old (no-star) price this run ($" .. tostring(price) .. ")")

		-- the Feasts' berries feed a Gym pet to 'Ready to evolve!' (Phase 5: Feed spends berries, never Cash)
		local gymPet = combats[2]
		local c1, b1 = cash(vic), DataS.GetBerries(vic)
		mark = K.logSize()
		Mock.FromClient(remote("PetCare"), vic, "Feed", gymPet)
		advance(0.6)
		local lv = DataS.GetPetLevel(vic, gymPet)
		T.check(DataS.GetBerries(vic) < b1 and cash(vic) == c1 and lv >= 20, "p4 flow migrate: one Feed of the Feasts' berries (no Cash) takes the old Gym pet to Lv " .. tostring(lv))
		T.check(toasted(vic, "Ready to evolve!", mark), "p4 flow migrate: ...'Ready to evolve!'", table.concat(toasts(vic, nil, mark), " | "))
		-- the level-22 garden pet evolves
		local inc0 = Ty.IncomePerSecond(vic)
		Mock.FromClient(remote("PetCare"), vic, "Evolve", ecos[1])
		advance(1.2)
		T.check(DataS.GetEvolution(vic, ecos[1]) == 1 and Ty.IncomePerSecond(vic) > inc0, "p4 flow migrate: his level-22 garden pet evolves (stage 1, more coins)")

		-- chapter 4: train -> ring -> portal
		st = X.TSv.GetState(vic)
		local gym = stationModel(info, "Gym")
		T.check(st and st.Id == "train" and st.Target and typeof(st.Target.Position) == "Vector3" and gym ~= nil and K.planar(st.Target.Position, gym:GetPivot().Position) < 16,
			"p4 flow migrate: 'train' points at his Training Place")
		local trainee = combats[3]
		fund(vic, TC.TrainCost(PC.Get(trainee), 1))
		Mock.FromClient(remote("PetCare"), vic, "Train", trainee, "Defense")
		advance(0.6)
		T.check(type(DataS.GetGrowth(vic, trainee).Job) == "table", "p4 flow migrate: he starts Defense training for his other old Gym pet")
		K.waitFor(function()
			local s2 = X.TSv.GetState(vic)
			return s2 and s2.Id == "ring"
		end, 3)
		st = X.TSv.GetState(vic)
		local portalPos = ringPortalPos(X)
		T.check(st and st.Id == "ring" and st.Target and typeof(st.Target.Position) == "Vector3" and portalPos ~= nil and K.planar(st.Target.Position, portalPos) < 20,
			"p4 flow migrate: training completes 'train' -> 'ring' (the arrow on the Champion Ring portal)")
		local tok0 = tokens(vic)
		toRing(X, vic)
		local run = runRing(vic, 1, { stopAfterWins = 1, maxSeconds = 300 })
		T.check(run.id ~= nil and #run.wins >= 1, "p4 flow migrate: his level-15 fighter wins round 1", tostring(run.refused))
		advance(0.5)
		st = X.TSv.GetState(vic)
		T.check(st and st.Id == "portal" and st.Chapter == 4, "p4 flow migrate: a won ring round completes 'ring' -> 'portal'", st and tostring(st.Id) or "no state")
		local tokRing = tokens(vic) - tok0
		if X.BS.IsInBattle(vic) then
			X.BS.Forfeit(vic) -- leaves the ring in the intermission: the run ends cleanly
		end
		advance(5.5)
		T.check(not X.BS.IsInBattle(vic) and vic:GetAttribute("InBattle") == nil, "p4 flow migrate: he leaves the ring in the intermission")
		-- Home -> Go home: the portal; walking in finishes the tutorial (+300 Tokens once)
		local tok1 = tokens(vic)
		mark = K.logSize()
		Mock.Teleport(vic, CFrame.new(config().Lobby.Origin + Vector3.new(14, 4, 9)))
		advance(0.3)
		Mock.FromClient(remote("HomeAction"), vic, "GoHome")
		advance(0.4)
		local at = parsePortal(vic:GetAttribute(config().Attr.HomePortal or "HomePortal"))
		if T.check(at ~= nil, "p4 flow migrate: Home -> Go home opens his portal (HomePortal)") then
			standAt(rex, at)
			advance(0.6)
			local rr = K.root(rex)
			T.check(rr ~= nil and K.planar(rr.Position, at) < 4 and vic:GetAttribute(config().Attr.HomePortal or "HomePortal") ~= nil,
				"p4 flow migrate: Rex stepping into Vic's portal goes nowhere (it stays open for Vic)")
			away(rex)
			standAt(vic, at)
			advance(0.8)
			local root = K.root(vic)
			T.check(root ~= nil and K.planar(root.Position, info.SpawnCFrame.Position) <= 6, "p4 flow migrate: walking in takes him home (within 6 studs of his spawn)")
		end
		advance(1)
		st = X.TSv.GetState(vic)
		local reward = tokens(vic) - tok1
		T.check(st and st.Done == true and reward == 300 and toasted(vic, "Pets tutorial complete! +300 Tokens", mark), "p4 flow migrate: the portal finishes chapter 4: +300 Tokens and the toast",
			tostring(reward) .. " / " .. (st and tostring(st.Id) or "no state"))
		T.check(DataS.GetTutorial(vic).Done == true and DataS.GetTutorial(vic).Step == #X.Steps.Steps + 1, "p4 flow migrate: ...stored as finished (Step " .. (#X.Steps.Steps + 1) .. ")")
		T.info("p4 flow migrate: ring round tokens " .. tokRing)
		-- once: a second trip through the portal pays nothing
		advance(3.5)
		local tok2 = tokens(vic)
		away(vic)
		advance(0.2)
		Mock.FromClient(remote("HomeAction"), vic, "GoHome")
		advance(0.4)
		local at2 = parsePortal(vic:GetAttribute(config().Attr.HomePortal or "HomePortal"))
		if at2 then
			standAt(vic, at2)
			advance(0.8)
		end
		T.eq(tokens(vic), tok2, "p4 flow migrate: the chapter's reward is paid once")
	end)
	ledger.stop()
	if not okRun then
		error(errRun, 0)
	end
end)

----------------------------------------------------------------------------------------------------
-- p4flow_rejoin: leave + rejoin mid-training and mid-ring-run
----------------------------------------------------------------------------------------------------
S.p4flow_rejoin = scenario("p4flow_rejoin", function(players)
	local X = ready("p4 flow rejoin")
	if not X then
		return
	end
	local DataS, TC, PC = X.DataS, X.TC, X.PC
	Mock.DataStore.Data[storeKey(IDS.Moe)] = nil
	local fighter, trainee = WEAK[1], WEAK[2]
	local moe = join("Moe")
	players[1] = moe
	advance(4)
	Mock.FromClient(remote("TutorialEvent"), moe, "Skip")
	advance(0.3)
	givePet(moe, fighter, 1, 1)
	givePet(moe, trainee, 1, 1)
	local index = claim(moe)
	if not T.check(index ~= nil, "p4 flow rejoin: (setup) Moe claims a home") then
		return
	end
	DataS.MutateHome(moe, function(h)
		h.Stations.Garden, h.Stations.Press1, h.Stations.Kitchen, h.Stations.Gym = 1, 1, 1, 1
		h.Level = TC.HomeLevelOf(h)
	end)
	advance(2.1)
	away(moe)
	Mock.FromClient(remote("EquipPet"), moe, fighter)
	advance(0.4)
	Mock.FromClient(remote("EquipPet"), moe, trainee)
	advance(0.4)
	T.check(listHas(equipped(moe), fighter) and listHas(equipped(moe), trainee), "p4 flow rejoin: (setup) both pets follow him")

	-- mid-training: the job is saved and keeps its lock
	fund(moe, TC.TrainCost(PC.Get(trainee), 1))
	Mock.FromClient(remote("PetCare"), moe, "Train", trainee, "Ability")
	advance(0.4)
	local job = DataS.GetGrowth(moe, trainee).Job
	T.check(type(job) == "table" and job.Stat == "Ability" and job.From == "Follow", "p4 flow rejoin: Moe starts Ability training for a following pet (From 'Follow')", job and tostring(job.From) or "no job")
	leave(moe)
	advance(1.5)
	local rec = stored(IDS.Moe) or {}
	local rg = type(rec.PetGrowth) == "table" and rec.PetGrowth[trainee] or nil
	T.check(type(rg) == "table" and type(rg.Job) == "table" and rg.Job.Stat == "Ability" and rg.Job.Ends == job.Ends and not listHas(rec.Equipped, trainee),
		"p4 flow rejoin: leaving mid-training saves the job (and the pet is not equipped)")
	advance(5)
	moe = join("Moe")
	players[1] = moe
	advance(1)
	local mark = K.logSize()
	advance(1.6)
	Mock.FromClient(remote("EquipPet"), moe, trainee)
	advance(0.4)
	T.check(DataS.TrainingKeys(moe)[trainee] == true and not listHas(equipped(moe), trainee) and toasted(moe, "is training", mark),
		"p4 flow rejoin: a quick rejoin: still training, still locked")
	-- finished while he is away
	leave(moe)
	advance(TC.TrainSeconds(1) + 5)
	mark = K.logSize()
	moe = join("Moe")
	players[1] = moe
	advance(5)
	local g = DataS.GetGrowth(moe, trainee)
	T.check(g.Ability == 1 and g.Job == nil and toasted(moe, "Training done while you were away!", mark),
		"p4 flow rejoin: a job that ended while he was away completes on load ('Training done while you were away!', Ability rank 1)")
	T.check(listHas(equipped(moe), trainee), "p4 flow rejoin: ...and the pet follows him again (From 'Follow')", table.concat(equipped(moe), ","))
	T.eq(DataS.GetGrowth(moe, trainee).Ability, 1, "p4 flow rejoin: ...one rank, once")

	-- mid-ring-run: Runs + 1 in the leave save, the pocket freed, no battle after the rejoin
	index = claim(moe)
	T.check(index ~= nil, "p4 flow rejoin: (setup) he claims a home again (the ring needs one)")
	Mock.FromClient(remote("UnequipPet"), moe, trainee) -- (one level-1 fighter keeps the round running)
	advance(0.4)
	local runs0 = DataS.GetRing(moe).Runs
	local pockets0 = pocketCount()
	local ended = {}
	local conn = X.BS.BattleEnded:Connect(function(id)
		ended[id] = (ended[id] or 0) + 1
	end)
	toRing(X, moe)
	Mock.FromClient(remote("BattleRequest"), moe, "Ring", 1)
	advance(0.6)
	local battleId = moe:GetAttribute("InBattle")
	if T.check(type(battleId) == "string" and pocketCount() == pockets0 + 1, "p4 flow rejoin: Moe starts a ring run (one pocket)", tostring(battleId)) then
		leave(moe)
		advance(6)
		local rec2 = stored(IDS.Moe) or {}
		local rr = type(rec2.Ring) == "table" and rec2.Ring or { Runs = 0 }
		T.check((rr.Runs or 0) == runs0 + 1, "p4 flow rejoin: leaving mid-round: Ring.Runs + 1 in his save", tostring(rr.Runs) .. " vs " .. tostring(runs0 + 1))
		T.check(pocketCount() == pockets0 and ended[battleId] == 1, "p4 flow rejoin: ...the round ends once (BattleEnded) and its pocket is freed")
		moe = join("Moe")
		players[1] = moe
		advance(2)
		T.check(moe:GetAttribute("InBattle") == nil and not X.BS.IsInBattle(moe) and DataS.GetRing(moe).Runs == runs0 + 1,
			"p4 flow rejoin: after the rejoin: no battle, the run counted once")
	end
	conn:Disconnect()
end)

----------------------------------------------------------------------------------------------------
-- p4flow_merge: two servers write the same Phase 4 profile
----------------------------------------------------------------------------------------------------
S.p4flow_merge = scenario("p4flow_merge", function(players)
	local X = ready("p4 flow merge")
	if not X then
		return
	end
	local DataS, TC, PC = X.DataS, X.TC, X.PC
	local a, b = WEAK[1], WEAK[3]
	local now = os.time()
	Mock.DataStore.Data[storeKey(IDS.Kai)] = {
		Version = 2, Tokens = 100, Cash = 500, Gems = 10, Pets = { [a] = 1, [b] = 1 }, Equipped = { a }, Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 1, BestTimes = {} }, Discovered = { [a] = true, [b] = true }, IndexClaimed = {},
		Tutorial = { Step = #X.Steps.Steps + 1, Done = true, Gifted = true },
		Home = { Level = 4, Prestige = 0, Stations = { Garden = 1, Press1 = 1, Kitchen = 1, Gym = 1 }, Garden = { b }, Gym = {}, CollectorCash = 0, LastSeen = now },
		PetLevels = { [a] = { Level = 10, Xp = 0 } },
		PetGrowth = { [a] = { Speed = 2 } }, Ring = { Best = 4, Runs = 3 }, Migrations = { P4 = true },
		UpdatedAt = now - 60,
	}
	local kai = join("Kai")
	players[1] = kai
	advance(3)
	T.check(DataS.GetRing(kai).Best == 4 and DataS.GetGrowth(kai, a).Speed == 2, "p4 flow merge: (precondition) Kai's Phase 4 save loads (ring record 4, Speed rank 2)")
	-- this server: a run with a new record, a Defense rank finished here, a running job, +$50
	DataS.MutateRing(kai, function(r)
		r.Best = 5
		r.Runs = r.Runs + 1
	end)
	DataS.MutateGrowth(kai, function(g)
		g[a] = g[a] or {}
		g[a].Defense = 1
	end)
	local index = claim(kai)
	away(kai)
	fund(kai, cash(kai) + TC.TrainCost(PC.Get(b), 1))
	local c0 = cash(kai)
	Mock.FromClient(remote("PetCare"), kai, "Train", b, "Ability")
	advance(0.4)
	local job = DataS.GetGrowth(kai, b).Job
	T.check(index ~= nil and type(job) == "table", "p4 flow merge: (here) Kai starts Ability training")
	DataS.AddCash(kai, 50)
	local cashHere = cash(kai) -- this session's balance (its delta since the load travels into the merge)
	-- the other server's late write: a better record, two more runs, a Speed rank, the SAME Defense rank, Cash
	local rec = stored(IDS.Kai)
	rec.Ring = { Best = 9, Runs = rec.Ring.Runs + 2 }
	rec.PetGrowth = { [a] = { Speed = 3, Defense = 1 } }
	rec.Cash = rec.Cash + 70
	rec.Migrations.P4Welcome = true
	DataS.Save(kai)
	local s = stored(IDS.Kai) or {}
	local sg = type(s.PetGrowth) == "table" and s.PetGrowth[a] or {}
	T.check(type(s.Ring) == "table" and s.Ring.Best == 9 and s.Ring.Runs == 3 + 2 + 1, "p4 flow merge: Ring.Best is the max (9), Runs add up (3 + 2 there + 1 here)",
		type(s.Ring) == "table" and (tostring(s.Ring.Best) .. " / " .. tostring(s.Ring.Runs)) or "no ring")
	T.check(sg.Speed == 3 and sg.Defense == 1, "p4 flow merge: ranks are the max: Speed 3 from there, and the Defense rank both servers finished stays ONE rank",
		tostring(sg.Speed) .. " / " .. tostring(sg.Defense))
	local sj = type(s.PetGrowth) == "table" and type(s.PetGrowth[b]) == "table" and s.PetGrowth[b].Job or nil
	T.check(type(sj) == "table" and sj.Stat == "Ability" and sj.Ends == job.Ends, "p4 flow merge: ...this server's running job survives the other server's write")
	T.eq(s.Cash, cashHere + 70, "p4 flow merge: Cash merges as a delta (+70 there on top of this session's balance)")
	T.check(type(s.Migrations) == "table" and s.Migrations.P4 == true and s.Migrations.P4Welcome == true, "p4 flow merge: Migrations are a union")
	advance(1)
	T.check(DataS.GetRing(kai).Best == 9 and DataS.GetRing(kai).Runs == 6 and DataS.GetGrowth(kai, a).Speed == 3 and DataS.GetGrowth(kai, a).Defense == 1
		and DataS.TrainingKeys(kai)[b] == true and cash(kai) == s.Cash, "p4 flow merge: the live profile adopts the merged numbers")
	T.check(c0 > 0, "p4 flow merge: (setup) funded")
	-- a rejoin reads the same numbers, nothing counted twice
	leave(kai)
	advance(2)
	kai = join("Kai")
	players[1] = kai
	advance(2)
	T.check(DataS.GetRing(kai).Best == 9 and DataS.GetRing(kai).Runs == 6 and DataS.GetGrowth(kai, a).Speed == 3 and DataS.GetGrowth(kai, a).Defense == 1
		and DataS.TrainingKeys(kai)[b] == true, "p4 flow merge: after a rejoin: the same record, runs, ranks and job")
end)

return S
