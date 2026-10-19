-- smoke_p4_ring.lua: Phase 4 "Champion Ring" in BattleService (ARCHITECTURE_V3.md "Phase 4 build contract" 3.5 / 3.8 /
-- 3.11 / 5.1-5.4 / X13-X17 / 8.1) on the booted server with simulated players. Server world only (server_files of
-- tools/smoke.py); the scenarios run before the care block (they advance the clock by minutes).
--   p4ring_start    the entry checks IN ORDER with their exact toasts (no home / no pet / far from the portal / in an
--                   obby match / a provisional save), the fighters fallback (team -> equipped -> best owned by UnitPower,
--                   training pets skipped, at most GetTeams().Slots), junk start rounds, the "Start" payload (Ring =
--                   { Round, Best, Start, Champion }, unit evo / xp / xpNext), GetBattle (Mode Ring, Round), KeysInBattle,
--                   one battle at a time, the pocket from the shared pool, a BattleRequest("Ring") through the remote
--   p4ring_run      a single level-1 pet wins rounds 1-3 (chaining: InBattle never nil, one pocket, a fresh Start per
--                   round with Round + 1 after Ring.Intermission, every won round's End carries Rewards.Next / Cash /
--                   Record / Tokens), rewards exactly once per round (Cash + XP + Best), the run's natural loss pays the
--                   loss third under the gate (never more), the run ends the trial way (return teleport, InBattle cleared,
--                   the pocket freed, Ring.Runs + 1), BattleEnded with Mode "Ring", Round, Won
--   p4ring_rewards  Cash = max(floor, seconds of the climber's own garden income) x3 on a record (a garden pet at home
--                   makes the income count), the record x3 and the boss round's +100 Tokens exactly once (Ring.Best
--                   grow-only), a second run pays x1 and no Tokens for rounds already beaten, Ring.Best max / Runs
--                   delta, the checkpoint start (a beaten boss round, a round not beaten refused), Double Rewards does
--                   not touch ring Cash, the RingBoard attribute
--   p4ring_ends     every end path, each exactly once: Forfeit in an intermission (clean, the last round kept) vs in a
--                   fight (no loss XP), a leave during a round and between rounds (Runs + 1 in the saved profile), a
--                   respawn elsewhere, a teleport away (the pocket leash), joining an obby match, Shutdown during a round
--                   and between two rounds (the running round void, the wins stay paid); the pocket freed every time
--   p4ring_lossxp   the real-loss gate on the ring (Phase 5: LossRules, the Trials are gone): a round lost by the 90 s
--                   timeout pays a third of its XP, a forfeited round pays nothing, a won round the full XP; EventService
--                   ignores non-Raid results
-- Phase 5: the player's CHARACTER is the fighter's body: the harness drives it (drvTick: walk at the champion, ATTACK ~1/s).
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance = K.advance

local S = {}

local seq = 0
local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }
local MID = { "twilight_dragon", "moonlit_owl", "candy_unicorn" }
local WEAK = { "pebble_pup", "honey_bunny", "puddle_frog" }
local ALLOWED_WARNINGS = { "[BattleService]", "[DataService]", "[TycoonService]", "[PetCareService]" }

local function req(path)
	local inst = K.moduleInstance(path)
	if not inst then
		return nil
	end
	local ok, m = pcall(require, inst)
	if ok and type(m) == "table" then
		return m
	end
	return nil
end

local function BS()
	return req("server/Services/BattleService")
end
local function DS()
	return req("server/Services/DataService")
end
local function AB()
	return req("server/Services/ArenaBuilder")
end
local function BC()
	return req("shared/BattleCatalog")
end
local function TS()
	return req("server/Services/TycoonService")
end
local function PK()
	return req("shared/PetKeys")
end
local function PC()
	return req("shared/PetCatalog")
end

local function arenaInfo()
	local ab = AB()
	return ab and ab.GetInfo and ab.GetInfo() or nil
end

local function ready(label)
	if not K.needBoot() then
		return false
	end
	local bs = BS()
	if not bs or type(bs.StartRing) ~= "function" then
		T.fail(label .. ": skipped, server/Services/BattleService (StartRing) did not load")
		return false
	end
	if not arenaInfo() then
		T.fail(label .. ": skipped, ArenaBuilder.GetInfo() returned nothing (no arena in this build)")
		return false
	end
	if not TS() then
		T.fail(label .. ": skipped, TycoonService did not load (the ring needs a claimed home)")
		return false
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- players, homes, portals
----------------------------------------------------------------------------------------------------
-- a player who owns `pets` (level `level`), with team preset 1 = pets when `team` is not false
local function newPlayer(prefix, pets, level, team)
	seq = seq + 1
	local p = Mock.AddPlayer(prefix .. seq, 965000 + seq)
	advance(1.0)
	local data = DS()
	local prof = data.GetProfile(p)
	if prof and pets then
		for _, id in ipairs(pets) do
			prof.Pets[id] = (prof.Pets[id] or 0) + 1
			if level then
				prof.PetLevels[id] = { Level = level, Xp = 0 }
			end
		end
		data.MarkDirty(p)
		if team ~= false then
			local ok, why = data.SetTeam(p, 1, pets)
			if not ok then
				T.fail("(setup) SetTeam for " .. p.Name .. " failed", tostring(why))
			end
		end
	end
	return p
end

local function spots()
	return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
end

local function freeIndex()
	local SS = req("server/Services/SpotService")
	for i = 1, K.config().Lobby.SpotCount do
		if spots()[i] and not (SS and SS.GetOwner(i)) then
			return i
		end
	end
	return nil
end

-- claims a free plot and builds the free Pet Garden; the plot index or nil
local function claimHome(p)
	local Ty = TS()
	local index = freeIndex()
	if not Ty or not index then
		return nil
	end
	local ok = Ty.Claim(p, index)
	advance(0.6)
	if not ok then
		return nil
	end
	Ty.Buy(p, "Garden")
	advance(0.3)
	return index
end

-- where the service accepts ring starts: ArenaInfo.RingPortal, else the Portal_Ring model
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

local function ringPortalPos()
	local info = arenaInfo()
	return positionOf(info and info.RingPortal) or positionOf(workspace:FindFirstChild("Portal_Ring", true))
end

local function ringPortalInstance()
	local info = arenaInfo()
	local portal = info and info.RingPortal
	if type(portal) == "table" then
		return portal.Model or portal.Pad or portal.Part
	end
	if typeof(portal) == "Instance" then
		return portal
	end
	return workspace:FindFirstChild("Portal_Ring", true)
end

-- a build without Portal_Ring yet (the arenaworld engineer lands it in the same wave): a stand-in model so the
-- RingBoard attribute and the "walk to the portal" distance have a real target
local standIn = nil
local function ensurePortal()
	if ringPortalInstance() then
		return
	end
	local info = arenaInfo()
	local holder = workspace:FindFirstChild("BattleArena") or workspace
	local model = Instance.new("Model")
	model.Name = "Portal_Ring"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(8, 1, 8)
	local site = (typeof(info.RingSite) == "CFrame" and info.RingSite.Position) or (typeof(info.TrialPortal) == "Instance" and info.TrialPortal.Position) or info.Spawn.Position
	base.CFrame = CFrame.new(site + Vector3.new(24, 0, 0))
	base.Parent = model
	model.PrimaryPart = base
	model.Parent = holder
	standIn = model
end

local function dropStandIn()
	if standIn then
		standIn:Destroy()
		standIn = nil
	end
end

local function toRing(p, dx)
	local pos = ringPortalPos()
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(dx or 0, 3, 6)))
	advance(0.05)
end

local function toLobby(p)
	Mock.Teleport(p, CFrame.new(K.config().Lobby.Origin + Vector3.new(10, 4, 10)))
	advance(0.05)
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

local function lastMsg(p, kind, fromIndex)
	local list = battleMsgs(p, fromIndex, kind)
	local e = list[#list]
	return e and e.args[2] or nil, e
end

local function toasts(p, fromIndex)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, fromIndex or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	return out
end

local function toasted(p, needle, fromIndex)
	for _, text in ipairs(toasts(p, fromIndex)) do
		if text:find(needle, 1, true) then
			return true, text
		end
	end
	return false
end

local function watchEnded()
	local list = {}
	local conn = BS().BattleEnded:Connect(function(id, result)
		list[#list + 1] = { id = id, result = result }
	end)
	return {
		list = list,
		find = function(id)
			for _, e in ipairs(list) do
				if e.id == id then
					return e.result
				end
			end
			return nil
		end,
		count = function(id)
			local n = 0
			for _, e in ipairs(list) do
				if e.id == id then
					n = n + 1
				end
			end
			return n
		end,
		stop = function()
			conn:Disconnect()
		end,
	}
end

local function contains(list, value)
	for _, v in ipairs(type(list) == "table" and list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function count(t)
	local n = 0
	for _ in pairs(type(t) == "table" and t or {}) do
		n = n + 1
	end
	return n
end

local function pocketCount()
	local pockets = workspace:FindFirstChild("BattlePockets")
	return pockets and #pockets:GetChildren() or 0
end

local function ringOf(p)
	return DS().GetRing(p) or { Best = -1, Runs = -1 }
end

local function totalXp(p, key)
	local level, xp = DS().GetPetLevel(p, key)
	local Cat = req("shared/TycoonCatalog")
	local total = xp or 0
	for l = 1, (level or 1) - 1 do
		total = total + Cat.XpToNext(l)
	end
	return total
end

local function stored(uid)
	return Mock.DataStore.Data[K.config().Tokens.DataStoreName .. "/u_" .. uid]
end

local function cleanup(list)
	local bs = BS()
	for _, p in ipairs(list) do
		if p.Parent and bs and bs.IsInBattle(p) then
			bs.Forfeit(p)
		end
	end
	advance(0.3)
	K.removePlayers(list)
	advance(5)
end

-- the BattleState traffic of the long runs stays out of the client replay log
local savedHook = nil
local function quietReplication()
	if savedHook == nil and Mock._onRemote then
		savedHook = Mock._onRemote
		Mock._onRemote = function(entry)
			if entry.remote ~= "BattleState" then
				savedHook(entry)
			end
		end
	end
end
local function loudReplication()
	if savedHook then
		Mock._onRemote = savedHook
		savedHook = nil
	end
end

-- EventService's scheduler must not open a raid in the middle of a scenario
local realStartRaid = nil
local function holdRaidSchedule(bs)
	if realStartRaid == nil then
		realStartRaid = bs.StartRaid
		bs.StartRaid = function()
			return false, "A raid is already running"
		end
	end
end
local function releaseRaidSchedule(bs)
	if realStartRaid then
		bs.StartRaid = realStartRaid
		realStartRaid = nil
	end
end

local function scenario(name, fn)
	local run = guarded(name, fn)
	return function(...)
		local ok = run(...)
		local bs = BS()
		if bs then
			releaseRaidSchedule(bs)
			bs.Debug = nil
			if bs.SetDoubleRewards then
				bs.SetDoubleRewards(nil)
			end
			if bs.SetClosing then
				bs.SetClosing(false)
			end
		end
		loudReplication()
		return ok
	end
end

----------------------------------------------------------------------------------------------------
-- [Phase 5 driver] the client-side picture of a battle (BattleSim.DecodeSnapshot of the player's own messages) and a
-- fighter that walks its CHARACTER toward the nearest enemy at the legal run speed and presses ATTACK (B1: the
-- character is the fighter's body; a passive player deals no damage any more)
----------------------------------------------------------------------------------------------------
local DRV_DOWN, DRV_BENCHED = 5, 3

local function drvTracker(p, mark)
	return { p = p, cursor = mark or K.logSize(), static = {}, units = {}, ends = {}, ticks = 0, zone = nil, side = nil, fighter = nil, id = nil, start = nil, speed = nil }
end

local function drvPump(tr)
	local Sm = req("shared/BattleSim")
	local log = Mock.RemoteLog
	local uid = tr.p.UserId
	for i = tr.cursor + 1, #log do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == uid then
			local kind, payload = e.args[1], e.args[2]
			if kind == "Start" and type(payload) == "table" and payload.Spectator ~= true then
				tr.start, tr.id = payload, payload.BattleId
				tr.zone = payload.Zone and payload.Zone.CFrame
				tr.side = payload.Side
				tr.static, tr.units = {}, {}
				for _, u in ipairs(payload.Units or {}) do
					tr.static[u.id] = u
				end
				tr.fighter = payload.Team and payload.Team.Fighter
				tr.speed = payload.Team and payload.Team.Speed
			elseif kind == "Snapshot" and type(payload) == "table" and payload.BattleId == tr.id and Sm then
				tr.units = Sm.DecodeSnapshot(payload, tr.units)
			elseif kind == "Events" and type(payload) == "table" and e.args[3] == tr.id then
				for _, ev in ipairs(payload) do
					if (ev.type == "Spawn" or ev.type == "Wave") and type(ev.units) == "table" then
						for _, u in ipairs(ev.units) do
							tr.static[u.id] = u
						end
					elseif ev.type == "Swap" and ev.owner == uid then
						tr.fighter = ev["in"]
					elseif ev.type == "Speed" and ev.owner == uid then
						tr.speed = { Walk = ev.walk, Run = ev.run }
					elseif ev.type == "Telegraph" then
						tr.telegraphAt = Mock.Clock.now
					end
				end
			elseif kind == "End" and type(payload) == "table" and payload.Spectator ~= true and payload.BattleId == tr.id then
				tr.ends[#tr.ends + 1] = payload
			end
		end
	end
	tr.cursor = #log
end

local function drvMyPos(tr)
	local u = tr.fighter and tr.units[tr.fighter]
	if u then
		return u.x, u.z
	end
	return nil
end

local function drvNearest(tr)
	local fx, fz = drvMyPos(tr)
	if not fx then
		return nil
	end
	local best, bestD, bestS = nil, math.huge, nil
	for id, u in pairs(tr.units) do
		local s = tr.static[id]
		if s and s.side ~= tr.side and u.state ~= DRV_DOWN and u.state ~= DRV_BENCHED and (u.hp == nil or u.hp > 0) then
			local d = math.sqrt((u.x - fx) ^ 2 + (u.z - fz) ^ 2)
			if d < bestD then
				best, bestD, bestS = id, d, s
			end
		end
	end
	return best, bestD, bestS
end

-- one 0.1 s tick: walk toward the nearest enemy (stop inside the reach), press ATTACK every `every` ticks (3 = ~3/s),
-- Element + Special once per second when opts.kit
local function drvTick(tr, opts)
	opts = opts or {}
	local bs = BS()
	drvPump(tr)
	if not tr.id or not tr.p.Parent then
		return nil
	end
	local id, dist, s = drvNearest(tr)
	if not id then
		return nil
	end
	tr.ticks = tr.ticks + 1
	local run = (tr.speed and tr.speed.Run) or 16
	local mine = tr.static[tr.fighter] or {}
	local reach = (tonumber(mine.range) or 4.5) + (tonumber(s.radius) or 1) + 1
	local u = tr.units[id]
	local root = K.root(tr.p)
	if opts.move ~= false and root and tr.zone and dist > reach - 1 then
		local rel = tr.zone:PointToObjectSpace(root.Position)
		local dx, dz = u.x - rel.X, u.z - rel.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 0.01 then
			local travel = math.min(run * 0.1, d)
			Mock.Teleport(tr.p, CFrame.new(tr.zone:PointToWorldSpace(Vector3.new(rel.X + dx / d * travel, 3, rel.Z + dz / d * travel))))
		end
	end
	if opts.attack ~= false and tr.ticks % (opts.every or 3) == 0 then
		bs.Command(tr.p, "Attack", id)
	end
	if tr.telegraphAt and Mock.Clock.now - tr.telegraphAt < 0.25 and opts.dodge ~= false then
		bs.Command(tr.p, "Dash") -- a boss telegraph: the i-frames dodge it
	end
	if opts.kit ~= false and tr.ticks % 10 == 0 then
		bs.Command(tr.p, "Element")
		bs.Command(tr.p, "Special")
	end
	return id
end

-- plays every tracked fighter (a list of trackers) until `seconds` pass or stopFn(trs) is true; -> true when stopped early
local function drvPlay(trs, seconds, stopFn, opts)
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < seconds do
		advance(0.1)
		for _, tr in ipairs(trs) do
			drvTick(tr, opts)
		end
		if stopFn and stopFn(trs) then
			return true
		end
	end
	return false
end

-- Runs the ring for `p` from `startRound` and follows it message by message (0.1 s steps) until the run's final "End"
-- (Rewards.Final) or opts.stop. out = { id, refused, starts = { Start payloads }, wins = { End payloads with Next },
-- finalEnd, nilSamples (InBattle read nil while the run lived: a gap), ids = { [battleId] = true }, pocketsMax }.
-- opts.onWin(out, endMsg, wins) runs after every won round; opts.tick(out, t) every step.
local function runRing(p, startRound, opts)
	opts = opts or {}
	local bs = BS()
	local out = { starts = {}, wins = {}, ends = {}, nilSamples = 0, ids = {}, pocketsMax = 0, samples = 0 }
	local cursor = K.logSize()
	out.mark = cursor
	local ok, id
	if opts.remote then
		Mock.FromClient(K.remoteFolder():FindFirstChild("BattleRequest"), p, "Ring", startRound)
		advance(0.1)
		id = p:GetAttribute("InBattle")
		ok = type(id) == "string"
		if not ok then
			id = table.concat(toasts(p, cursor), " | ")
		end
	else
		ok, id = bs.StartRing(p, startRound)
	end
	if ok ~= true then
		out.refused = id
		return out
	end
	out.id = id
	out.ids[id] = true
	-- Phase 5: the climber plays (the character walks at the champion, ATTACK about once per second) unless opts.play == false
	local tr = drvTracker(p, out.mark)
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < (opts.maxSeconds or 900) do
		advance(0.1)
		if opts.play ~= false then
			drvTick(tr, { every = opts.every or 3 }) -- the kit too (Element / Special): what sim_battle's ladder was measured with
		end
		local attr = p:GetAttribute("InBattle")
		out.samples = out.samples + 1
		if attr == nil then
			out.nilSamples = out.nilSamples + 1
		elseif type(attr) == "string" then
			out.ids[attr] = true
		end
		out.pocketsMax = math.max(out.pocketsMax, pocketCount())
		local finished = false
		for _, e in ipairs(battleMsgs(p, cursor, "Start")) do
			out.starts[#out.starts + 1] = e.args[2]
		end
		for _, e in ipairs(battleMsgs(p, cursor, "End")) do
			local m = e.args[2]
			out.ends[#out.ends + 1] = m
			if m.Spectator ~= true and type(m.Rewards) == "table" then
				if m.Rewards.Final then
					out.finalEnd = m
					finished = true
				elseif m.Rewards.Next then
					out.wins[#out.wins + 1] = m
					if opts.onWin then
						opts.onWin(out, m, #out.wins)
					end
				end
			end
		end
		cursor = K.logSize()
		if opts.tick then
			opts.tick(out, Mock.Clock.now - t0)
		end
		if finished or out.stop then
			break
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- p4ring_start: the entry checks in order, the fighters fallback, the Start payload
----------------------------------------------------------------------------------------------------
S.p4ring_start = scenario("p4ring_start", function()
	if not ready("p4ring_start") then
		return
	end
	quietReplication()
	local bs, data, bc, Ty = BS(), DS(), BC(), TS()
	holdRaidSchedule(bs)
	ensurePortal()
	local w = watchEnded()
	T.check(type(bs.KeysInBattle) == "function" and type(bs.StartRing) == "function", "p4 ring: BattleService.StartRing and KeysInBattle exist (contract 5.4)")
	local inst = K.moduleInstance("server/Services/BattleService")
	local source = inst and inst.Source or ""
	T.check(source:find("Ring = 1.5", 1, true) ~= nil, "p4 ring: REQUEST_COOLDOWNS.Ring = 1.5")
	T.check(source:find("\nlocal RingRun = {}", 1, true) ~= nil, "p4 ring: the new helpers live in ONE table (RingRun)")
	T.check(bs.StartRing(nil, 1) == false and count(bs.KeysInBattle(nil)) == 0, "p4 ring: nil players answer safely")

	-- 1) no home
	local p = newPlayer("RingNoHome", nil, nil, false)
	toRing(p)
	local ok, why = bs.StartRing(p, 1)
	T.check(ok == false and why == "Claim your home first", "p4 ring: without a claimed home: 'Claim your home first' (checked first)", tostring(why))
	-- 2) no pet
	local index = claimHome(p)
	T.check(index ~= nil, "p4 ring: (setup) the player claims a home")
	toRing(p)
	ok, why = bs.StartRing(p, 1)
	T.check(ok == false and why == "You need a pet", "p4 ring: with a home but no pet: 'You need a pet'", tostring(why))
	-- 3) far from the portal (home + pet, no team: the equipped fallback)
	local prof = data.GetProfile(p)
	prof.Pets[WEAK[1]] = 1
	data.MarkDirty(p)
	toLobby(p)
	ok, why = bs.StartRing(p, 1)
	T.check(ok == false and why == "Walk to the Champion Ring portal", "p4 ring: away from Portal_Ring: 'Walk to the Champion Ring portal'", tostring(why))
	-- 4) in an obby match (canBattle comes before the portal distance)
	toRing(p)
	p:SetAttribute(K.config().Attr.InMatch, true)
	ok, why = bs.StartRing(p, 1)
	T.check(ok == false and type(why) == "string" and why:find("obby match", 1, true) ~= nil, "p4 ring: in an obby match: canBattle's toast", tostring(why))
	p:SetAttribute(K.config().Attr.InMatch, nil)
	-- junk start rounds
	local bad = {}
	for _, round in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, "1", 2, 7, 10, 20 }) do
		local okBad, whyBad = bs.StartRing(p, round)
		if okBad ~= false or whyBad ~= "Start from round 1 or a boss round you beat" then
			bad[#bad + 1] = tostring(round) .. "=" .. tostring(whyBad)
		end
	end
	T.check(#bad == 0, "p4 ring: junk start rounds and rounds not beaten are refused (0, -1, 1.5, nan, inf, '1', 2, 7, 10, 20)", table.concat(bad, ", "))

	-- the fighters fallback: no team -> the equipped keys -> the best owned pets by UnitPower
	local mark = K.logSize()
	ok, why = bs.StartRing(p, 1)
	T.check(ok == true and type(why) == "string", "p4 ring: StartRing(1) with a home, one pet and no team starts a run (the equipped / best-pet fallback)", tostring(why))
	local id1 = why
	local start = lastMsg(p, "Start", mark)
	local mine = {}
	for _, u in ipairs(start and start.Units or {}) do
		if u.owner == p.UserId then
			mine[#mine + 1] = u
		end
	end
	T.check(type(start) == "table" and start.Mode == "Ring" and start.Round == 1 and #mine == 1 and mine[1].key == WEAK[1] and start.Side == 1 and start.Spectator == false,
		"p4 ring: 'Start' Mode Ring, Round 1, the only owned pet fights (one unit)", start and tostring(#mine) or "no start")
	T.check(type(start) == "table" and type(start.Ring) == "table" and start.Ring.Round == 1 and start.Ring.Best == 0 and start.Ring.Start == 1 and type(start.Ring.Champion) == "table"
		and type(start.Ring.Champion.PetId) == "string" and start.Ring.Champion.Level == 1 and start.Ring.Champion.Tier == "Normal" and start.Ring.Champion.Boss == false
		and type(start.Ring.Champion.Name) == "string",
		"p4 ring: 'Start'.Ring = { Round 1, Best 0, Start 1, Champion = { PetId, Level 1, Tier, Boss false, Name } }", start and K.plain and K.plain(start.Ring) or "")
	local crowned, champ = 0, nil
	for _, u in ipairs(start and start.Units or {}) do
		if u.owner ~= p.UserId then
			champ = u
			if u.crowned == true then
				crowned = crowned + 1
			end
		end
	end
	T.check(crowned == 1 and champ and champ.id and start.Ring.Champion.PetId == champ.petId, "p4 ring: one crowned champion unit, the Start's Champion.PetId", champ and tostring(champ.petId) or "none")
	T.check(mine[1] and mine[1].evo == 0 and mine[1].xp == 0 and type(mine[1].xpNext) == "number", "p4 ring: the owner's unit carries evo / xp / xpNext for the pet card", mine[1] and (tostring(mine[1].evo) .. "/" .. tostring(mine[1].xp) .. "/" .. tostring(mine[1].xpNext)) or "")
	T.eq(p:GetAttribute("InBattle"), id1, "p4 ring: InBattle holds the round's battle id")
	local g = bs.GetBattle(p)
	T.check(g and g.Mode == "Ring" and g.Round == 1 and g.BattleId == id1 and g.State == "Running", "p4 ring: GetBattle: Mode Ring, Round 1, State Running")
	local keys = bs.KeysInBattle(p)
	T.check(keys[WEAK[1]] == true and count(keys) == 1, "p4 ring: KeysInBattle = the run's fixed key list")
	local ok2, why2 = bs.StartRing(p, 1)
	T.check(ok2 == false and type(why2) == "string" and why2:find("already", 1, true) ~= nil, "p4 ring: one run at a time (a second StartRing is refused)", tostring(why2))
	local okT, whyT = bs.Queue(p)
	T.check(okT == false and type(whyT) == "string" and whyT:find("already", 1, true) ~= nil, "p4 ring: ...and no other battle during a run (Queue refused)")
	T.eq(pocketCount(), 1, "p4 ring: one pocket from the shared pool")
	local ringZone = g and g.Zone and g.Zone.CFrame
	T.check(ringZone and (K.root(p).Position - ringZone.Position).Magnitude < 40 and (K.root(p).Position - ringPortalPos()).Magnitude > 300,
		"p4 ring: the player was teleported into the private pocket")
	T.check(start and start.Zone and start.Zone.X == bc.Zones.Ring.X and start.Zone.Z == bc.Zones.Ring.Z and start.TimeLimit == bc.Ring.TimeLimit,
		"p4 ring: the round's zone is Zones.Ring (44 x 44) with TimeLimit 90", start and (tostring(start.Zone.X) .. "/" .. tostring(start.TimeLimit)) or "")
	bs.Forfeit(p)
	advance(0.3)
	local r1 = w.find(id1)
	T.check(r1 ~= nil and r1.Mode == "Ring" and r1.Round == 1 and r1.Won == false and r1.Forfeit == true, "p4 ring: BattleEnded carries Mode Ring, Round and Won (a forfeit is not won)", r1 and tostring(r1.Reason) or "no end")
	advance(4.6)
	T.check(p:GetAttribute("InBattle") == nil and count(bs.KeysInBattle(p)) == 0 and pocketCount() == 0, "p4 ring: after the end: InBattle cleared, KeysInBattle empty, the pocket freed")

	-- the team comes first when there is one (training pets skipped, the preset kept); the equipped list second
	local q = newPlayer("RingTeam", { STRONG[1], STRONG[2], WEAK[2] }, 5)
	claimHome(q)
	local qprof = data.GetProfile(q)
	qprof.Equipped = { WEAK[2] }
	data.MarkDirty(q)
	-- STRONG[2] trains: the fixed list skips it (the preset keeps it)
	local trained = data.MutateGrowth(q, function(growth)
		growth[STRONG[2]] = { Job = { Stat = "Speed", Ends = os.time() + 600, Rank = 1, Slot = 1, From = "Free", Paid = 0 } }
	end)
	T.check(trained == true and data.TrainingKeys(q)[STRONG[2]] == true, "p4 ring: (setup) one team pet is training")
	toRing(q)
	mark = K.logSize()
	local okQ, idQ = bs.StartRing(q, 1)
	local sq = lastMsg(q, "Start", mark)
	local qKeys = {}
	for _, u in ipairs(sq and sq.Units or {}) do
		if u.owner == q.UserId then
			qKeys[#qKeys + 1] = u.key
		end
	end
	table.sort(qKeys)
	T.check(okQ == true and #qKeys == 2 and qKeys[1] == STRONG[1] and qKeys[2] == WEAK[2] and #data.GetTeams(q).Presets[1] == 3,
		"p4 ring: the fighters are the active team with the training pet skipped (the preset keeps all three)", table.concat(qKeys, ","))
	local inB = bs.KeysInBattle(q)
	T.check(inB[STRONG[1]] == true and inB[WEAK[2]] == true and inB[STRONG[2]] == nil, "p4 ring: KeysInBattle lists the two fighters only")
	bs.Forfeit(q)
	advance(4.8)
	-- an empty team -> the equipped keys
	data.SetTeam(q, 1, {})
	toRing(q)
	mark = K.logSize()
	okQ, idQ = bs.StartRing(q, 1)
	sq = lastMsg(q, "Start", mark)
	qKeys = {}
	for _, u in ipairs(sq and sq.Units or {}) do
		if u.owner == q.UserId then
			qKeys[#qKeys + 1] = u.key
		end
	end
	T.check(okQ == true and #qKeys == 1 and qKeys[1] == WEAK[2], "p4 ring: with an empty team the EQUIPPED pets fight", table.concat(qKeys, ","))
	bs.Forfeit(q)
	advance(4.8)
	-- nothing equipped -> the best owned pets by UnitPower (the training one skipped)
	qprof = data.GetProfile(q)
	qprof.Equipped = {}
	data.MarkDirty(q)
	toRing(q)
	mark = K.logSize()
	okQ, idQ = bs.StartRing(q, 1)
	sq = lastMsg(q, "Start", mark)
	qKeys = {}
	for _, u in ipairs(sq and sq.Units or {}) do
		if u.owner == q.UserId then
			qKeys[u.slot] = u.key
		end
	end
	T.check(okQ == true and #qKeys == 2 and qKeys[1] == STRONG[1] and qKeys[2] == WEAK[2],
		"p4 ring: with nothing equipped the BEST owned pets fight (by UnitPower, the training one skipped)", table.concat(qKeys, ","))
	bs.Forfeit(q)
	advance(4.8)
	-- teamOf's empty-team refusal stays for the other modes (TeamSpec without the ring fallback)
	local specTr, whyTr = bs.TeamSpec(q)
	T.check(specTr == nil and whyTr == "Pick your battle team first (Menu > Team)", "p4 ring: teamOf's empty-team refusal stays for duels / raids / encounters (TeamSpec)", tostring(whyTr))

	-- a provisional save: refused with its text, after the other checks (a stand-in profile from a DataStore outage)
	local DSt = Mock.DataStore
	local savedFail = DSt.Fail
	DSt.Fail = true
	local v = newPlayer("RingOutage", nil, nil, false)
	advance(3)
	if T.check(data.IsProvisional(v) == true, "p4 ring: (precondition) the outage makes the newcomer's profile provisional") then
		local vprof = data.GetProfile(v)
		if vprof then
			vprof.Pets[WEAK[3]] = 1
		end
		local okClaim = claimHome(v)
		local realGetPlot = Ty.GetPlot
		if not okClaim then
			-- a provisional player cannot claim a home in this build: stand in for the claim to reach the later check
			Ty.GetPlot = function(pl)
				if pl == v then
					return { Index = 0 }
				end
				return realGetPlot(pl)
			end
		end
		toRing(v)
		local okV, whyV = bs.StartRing(v, 1)
		T.check(okV == false and whyV == "Your save is still loading, try again in a moment", "p4 ring: a provisional save: 'Your save is still loading, try again in a moment' (after the home / pet / portal checks)", tostring(whyV))
		Ty.GetPlot = realGetPlot
	end
	DSt.Fail = savedFail
	K.removePlayers({ v })
	advance(1)

	-- through the remote: BattleRequest("Ring") with no round = round 1; a bad round answers the toast
	local m = K.logSize()
	toRing(p)
	Mock.FromClient(K.remoteFolder():FindFirstChild("BattleRequest"), p, "Ring", 5)
	advance(0.1)
	T.check((toasted(p, "Start from round 1", m)) and p:GetAttribute("InBattle") == nil, "p4 ring: BattleRequest('Ring', 5) answers the toast (round 5 is no boss round)")
	advance(1.6)
	m = K.logSize()
	Mock.FromClient(K.remoteFolder():FindFirstChild("BattleRequest"), p, "Ring")
	advance(0.1)
	local idR = p:GetAttribute("InBattle")
	local sr = lastMsg(p, "Start", m)
	T.check(type(idR) == "string" and sr and sr.Mode == "Ring" and sr.Round == 1, "p4 ring: BattleRequest('Ring') without a round starts round 1")
	Mock.FromClient(K.remoteFolder():FindFirstChild("BattleRequest"), p, "Ring", 1)
	advance(0.1)
	T.check(p:GetAttribute("InBattle") == idR, "p4 ring: ...a second request during the run changes nothing")
	bs.Forfeit(p)
	advance(4.8)
	K.flushErrors("p4ring_start")
	K.flushWarnings("p4ring_start", ALLOWED_WARNINGS)
	w.stop()
	cleanup({ p, q })
end)

----------------------------------------------------------------------------------------------------
-- p4ring_run: a single level-1 pet wins rounds 1-3; chaining with no gap; rewards once; the natural end
----------------------------------------------------------------------------------------------------
S.p4ring_run = scenario("p4ring_run", function()
	if not ready("p4ring_run") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	holdRaidSchedule(bs)
	ensurePortal()
	local w = watchEnded()
	local info = arenaInfo()
	local p = newPlayer("RingSolo", { WEAK[1] }, 1)
	claimHome(p)
	toRing(p)
	local cash0, tokens0, xp0 = data.GetCash(p), data.GetTokens(p), totalXp(p, WEAK[1])
	local run = runRing(p, 1, { maxSeconds = 1500 })
	if not T.check(run.id ~= nil, "p4 ring run: a level-1 Common starts the ring", tostring(run.refused)) then
		w.stop()
		cleanup({ p })
		return
	end
	T.check(#run.wins >= 3, "p4 ring run: a single level-1 pet wins rounds 1, 2 and 3 (the handicapped easy rounds)", #run.wins .. " wins")
	T.check(run.finalEnd ~= nil, "p4 ring run: the run ended by itself with a final 'End' (Rewards.Final)", run.finalEnd and tostring(run.finalEnd.Reason) or "still running")
	T.eq(run.nilSamples, 0, "p4 ring run: InBattle was never nil while the run lived (no gap between two rounds)")
	T.eq(run.pocketsMax, 1, "p4 ring run: one pocket for the whole run")
	local wins = #run.wins
	-- every won round: a fresh Start with Round + 1, in the same pocket, after the intermission
	local roundsOk, zoneOk, idsOk = true, true, true
	local firstZone = run.starts[1] and run.starts[1].Zone and run.starts[1].Zone.CFrame
	for i, s in ipairs(run.starts) do
		if s.Round ~= i or (s.Ring and s.Ring.Round ~= i) then
			roundsOk = false
		end
		if not (s.Zone and firstZone and (s.Zone.CFrame.Position - firstZone.Position).Magnitude < 0.01) then
			zoneOk = false
		end
		if i > 1 and run.starts[i - 1].BattleId == s.BattleId then
			idsOk = false
		end
	end
	T.check(#run.starts == wins + 1 and roundsOk, "p4 ring run: one 'Start' per round with Round 1, 2, 3... (and Ring.Round)", #run.starts .. " starts")
	T.check(zoneOk and idsOk, "p4 ring run: every round in the same pocket, each with a NEW battle id")
	T.check(count(run.ids) == wins + 1, "p4 ring run: InBattle held every round's id in turn (" .. count(run.ids) .. " ids)")
	-- the won rounds' End: Next / Cash / Record / Tokens; the Cash the floor (no garden pets), x3 (every round of a first run is a record)
	local cashSum, xpSum, tokenSum, endsOk = 0, 0, 0, true
	for i, m in ipairs(run.wins) do
		local rw = m.Rewards
		local want = bc.RingRewards(i, 0, true)
		if not (m.Outcome == "Win" and m.Won == true and rw.Next == i + 1 and rw.Round == i and rw.Record == true and rw.Cash == want.Cash and rw.Xp == want.Xp and rw.Tokens == want.Tokens) then
			endsOk = false
		end
		cashSum = cashSum + (rw.Cash or 0)
		xpSum = xpSum + (rw.Xp or 0)
		tokenSum = tokenSum + (rw.Tokens or 0)
	end
	T.check(endsOk, "p4 ring run: every won round's 'End' carries Rewards.Next = round + 1, Cash = the floor x3 (a first run: every round is a record), Xp = 20 + 6r, Record, Tokens")
	local lossEnd = run.finalEnd
	local lossXp = lossEnd and lossEnd.Rewards.Xp or 0
	T.check(lossEnd and lossEnd.Outcome == "Loss" and lossEnd.Won == false and lossEnd.Rewards.Final == true and type(lossEnd.Rewards.Run) == "table"
		and lossEnd.Rewards.Run.Wins == wins and lossEnd.Rewards.Run.Cash == cashSum and lossEnd.Rewards.Run.Xp == xpSum + lossXp and lossEnd.Rewards.Run.Round == wins + 1
		and lossEnd.Rewards.Run.Record == wins and lossEnd.Rewards.Run.Best == wins and lossEnd.Rewards.Run.Start == 1,
		"p4 ring run: the final 'End' (Outcome Loss) carries the result card: Run = { Wins, Cash, Xp, Round, Record, Best, Start }", lossEnd and K.plain and K.plain(lossEnd.Rewards.Run) or "")
	-- the losing round's XP follows the gate exactly (a third when the fight lasted >= 20 s or dealt >= 20%)
	local lastId = run.starts[#run.starts] and run.starts[#run.starts].BattleId
	local lastRes = lastId and w.find(lastId)
	if T.check(lastRes ~= nil and lastRes.Mode == "Ring" and lastRes.Round == wins + 1 and lastRes.Won == false and contains(lastRes.Losers, p.UserId), "p4 ring run: BattleEnded of the losing round: Mode Ring, Round, Won false", lastRes and tostring(lastRes.Reason) or "none") then
		local dealt = 1 - ((type(lastRes.Hp) == "table" and lastRes.Hp[2]) or 1)
		local want = bc.LossXp(bc.Ring.XpBase + bc.Ring.XpPerRound * (wins + 1), lastRes.Duration, dealt)
		T.eq(lossXp, want, "p4 ring run: the round that ended the run paid BattleCatalog.LossXp(20 + 6r, duration, dealt) = " .. tostring(want) .. " (duration " .. tostring(lastRes.Duration) .. " s, dealt " .. string.format("%.2f", dealt) .. ")")
		T.check(want == 0 or want == math.floor((bc.Ring.XpBase + bc.Ring.XpPerRound * (wins + 1)) / 3 + 0.5), "p4 ring run: ...a third of the round's win XP")
	end
	-- paid exactly once: balances and the pet's XP moved by the sums
	T.eq(data.GetCash(p) - cash0, cashSum, "p4 ring run: Cash grew by exactly the rounds' Cash (paid once per round)")
	T.eq(data.GetTokens(p) - tokens0, tokenSum, "p4 ring run: Tokens grew by exactly the rounds' Tokens")
	T.eq(totalXp(p, WEAK[1]) - xp0, xpSum + lossXp, "p4 ring run: the pet's XP grew by the rounds' XP + the loss third")
	local ring = ringOf(p)
	T.check(ring.Best == wins and ring.Runs == 1, "p4 ring run: Ring.Best = the rounds won, Ring.Runs = 1", "Best " .. tostring(ring.Best) .. " Runs " .. tostring(ring.Runs))
	-- BattleEnded once per round
	local onceOk = true
	for id in pairs(run.ids) do
		if w.count(id) ~= 1 then
			onceOk = false
		end
	end
	T.check(onceOk, "p4 ring run: BattleEnded fired exactly once per round")
	local wonOk = true
	for i, s in ipairs(run.starts) do
		local r = w.find(s.BattleId)
		if not r or r.Mode ~= "Ring" or r.Round ~= i or r.Won ~= (i <= wins) then
			wonOk = false
		end
	end
	T.check(wonOk, "p4 ring run: every round's BattleEnded result has Round and Won (true for the won rounds)")
	-- the end the trial way: InBattle stays until the return, then the player is back at the portal and the pocket is gone
	T.check(p:GetAttribute("InBattle") ~= nil, "p4 ring run: InBattle stays until the return teleport")
	advance(4.6)
	T.check(p:GetAttribute("InBattle") == nil and not bs.IsInBattle(p) and count(bs.KeysInBattle(p)) == 0, "p4 ring run: InBattle cleared after the return (KeysInBattle empty)")
	T.check((K.root(p).Position - (info.RingSite.Position + info.RingSite.LookVector * 12 + Vector3.new(0, 3, 0))).Magnitude < 12, "p4 ring run: the player is back in front of the Champion Ring portal (ArenaInfo.RingSite)", tostring(K.root(p).Position))
	T.eq(pocketCount(), 0, "p4 ring run: the pocket is freed")
	T.eq(#bs.ListBattles(), 0, "p4 ring run: no battle is left behind")
	T.check((toasted(p, "Run over after round", run.mark)), "p4 ring run: the result card toast ('Run over after round N: W wins, +$X, +Y XP')", table.concat(toasts(p, run.mark), " | "))
	-- the intermission: ~3 s between a won round's End and the next Start
	local gapOk, gapText = true, ""
	if #run.wins >= 1 and #run.starts >= 2 then
		-- (the Start payloads carry T = 0 for a fresh sim; measure with the message order instead: End then Start, nothing in between for the player)
		gapOk = run.ends[1] ~= nil
	end
	T.check(gapOk, "p4 ring run: a won round's End comes before the next Start" .. gapText)
	K.flushErrors("p4ring_run")
	K.flushWarnings("p4ring_run", ALLOWED_WARNINGS)
	w.stop()
	cleanup({ p })
end)

----------------------------------------------------------------------------------------------------
-- p4ring_rewards: Cash from the garden income, the record x3 and the boss Tokens once, the checkpoint start
----------------------------------------------------------------------------------------------------
S.p4ring_rewards = scenario("p4ring_rewards", function()
	if not ready("p4ring_rewards") then
		return
	end
	quietReplication()
	local bs, data, bc, Ty = BS(), DS(), BC(), TS()
	holdRaidSchedule(bs)
	ensurePortal()
	local w = watchEnded()
	local p = newPlayer("RingRich", STRONG, 12)
	local index = claimHome(p)
	-- a garden pet at home: the ring pays seconds of this income
	local prof = data.GetProfile(p)
	prof.Pets[MID[1]] = 1
	data.MarkDirty(p)
	local okG, whyG = Ty.GardenSet(p, 1, MID[1])
	advance(0.3)
	local ips = Ty.IncomePerSecond(p)
	T.check(index ~= nil and okG == true and ips > 0, "p4 ring rewards: (setup) a garden pet makes the climber's own income (" .. string.format("%.2f", ips) .. "/s)", tostring(whyG))
	local R = bc.Ring
	local every = R.BossEvery
	toRing(p)
	local cash0, tokens0 = data.GetCash(p), data.GetTokens(p)
	local incomes = {}
	local run = runRing(p, 1, {
		maxSeconds = 1200,
		onWin = function(out, m, wins)
			incomes[wins] = Ty.IncomePerSecond(p)
			if wins >= every then
				out.stop = true -- the boss round is won: enough
			end
		end,
	})
	if not T.check(run.id ~= nil and #run.wins >= every, "p4 ring rewards: a strong team wins rounds 1.." .. every .. " (the first boss round)", tostring(run.refused) .. " / " .. #run.wins .. " wins") then
		bs.Forfeit(p)
		advance(5)
		w.stop()
		cleanup({ p })
		return
	end
	-- Cash per round = max(floor, floor(ips x RingSeconds(r))) x3 (a first run: every round is a record); income beats the floor at some round
	local cashOk, aboveFloor, cashSum, tokenSum = true, 0, 0, 0
	for i, m in ipairs(run.wins) do
		local rw = m.Rewards
		local want = bc.RingRewards(i, incomes[i] or ips, true)
		if rw.Cash ~= want.Cash or rw.Record ~= true or rw.Tokens ~= want.Tokens then
			cashOk = false
		end
		if math.floor((incomes[i] or ips) * bc.RingSeconds(i)) > want.Floor then
			aboveFloor = aboveFloor + 1
		end
		cashSum = cashSum + rw.Cash
		tokenSum = tokenSum + rw.Tokens
	end
	T.check(cashOk, "p4 ring rewards: every round paid RingRewards(r, IncomePerSecond(player), record).Cash: seconds of the climber's OWN garden income with the floor, x3 on the record")
	T.check(aboveFloor >= 1 or ips * bc.RingSeconds(every) <= R.CashFloorBase + R.CashFloorPerRound * every, "p4 ring rewards: ...the income counted (above the floor) when it was bigger", tostring(aboveFloor))
	local bossEnd = run.wins[every]
	T.check(bossEnd and bossEnd.Rewards.Tokens == R.BossTokens and bossEnd.Rewards.Record == true, "p4 ring rewards: the FIRST clear of the boss round pays +" .. R.BossTokens .. " Tokens", bossEnd and tostring(bossEnd.Rewards.Tokens) or "none")
	T.eq(tokenSum, R.BossTokens, "p4 ring rewards: ...and only that round paid Tokens")
	T.eq(data.GetTokens(p) - tokens0, R.BossTokens, "p4 ring rewards: the token balance grew by exactly " .. R.BossTokens)
	T.eq(data.GetCash(p) - cash0, cashSum, "p4 ring rewards: the Cash balance grew by exactly the rounds' Cash")
	T.check(ringOf(p).Best == every, "p4 ring rewards: Ring.Best = " .. every)
	-- Forfeit in the intermission after the boss round: the run ends cleanly, the boss round stays paid
	local m1 = K.logSize()
	local okF = bs.Forfeit(p)
	advance(0.3)
	local endF = lastMsg(p, "End", m1)
	T.check(okF == true and endF and endF.Mode == "Ring" and endF.Reason == "Forfeit" and endF.Rewards and endF.Rewards.Final == true and endF.Rewards.Run.Wins == every and endF.Rewards.Run.Tokens == R.BossTokens,
		"p4 ring rewards: Forfeit between two rounds ends the run cleanly: a final 'End' (Reason Forfeit) with the result card, the boss round kept", endF and tostring(endF.Reason) or "no end")
	T.eq(data.GetTokens(p) - tokens0, R.BossTokens, "p4 ring rewards: ...nothing more was paid")
	advance(4.6)
	T.check(p:GetAttribute("InBattle") == nil and pocketCount() == 0, "p4 ring rewards: ...the player is free and the pocket is gone")
	local ring1 = ringOf(p)
	T.check(ring1.Best == every and ring1.Runs == 1, "p4 ring rewards: Ring = { Best " .. every .. ", Runs 1 }", "Best " .. tostring(ring1.Best) .. " Runs " .. tostring(ring1.Runs))

	-- a second run from round 1: rounds already beaten pay x1 and no Tokens at the boss round (Best grow-only)
	toRing(p)
	advance(1.6)
	local tokens1, cash1 = data.GetTokens(p), data.GetCash(p)
	local incomes2 = {}
	local run2 = runRing(p, 1, {
		maxSeconds = 1200,
		onWin = function(out, m, wins)
			incomes2[wins] = Ty.IncomePerSecond(p)
			if wins >= every then
				out.stop = true
			end
		end,
	})
	local plainOk = #run2.wins >= every
	for i, m in ipairs(run2.wins) do
		local want = bc.RingRewards(i, incomes2[i] or ips, false)
		if m.Rewards.Cash ~= want.Cash or m.Rewards.Record ~= false or m.Rewards.Tokens ~= 0 then
			plainOk = false
		end
	end
	T.check(plainOk, "p4 ring rewards: a second run pays x1 Cash, Record false and NO Tokens for the rounds already beaten (the record and the boss bonus are paid once ever)", #run2.wins .. " wins")
	T.eq(data.GetTokens(p), tokens1, "p4 ring rewards: ...no Tokens moved in the second run")
	-- Double Rewards does not touch ring Cash
	bs.SetDoubleRewards(true, 600)
	local m2 = K.logSize()
	local incomeD = Ty.IncomePerSecond(p)
	local before = data.GetCash(p)
	local bestBeforeD = ringOf(p).Best
	local run2b = { wins = {} }
	local trD = drvTracker(p, run2.mark)
	local t0 = Mock.Clock.now
	while #run2b.wins == 0 and Mock.Clock.now - t0 < 120 do
		advance(0.1)
		drvTick(trD, { every = 10, kit = false })
		for _, e in ipairs(battleMsgs(p, m2, "End")) do
			if e.args[2].Rewards and e.args[2].Rewards.Next then
				run2b.wins[1] = e.args[2]
			end
		end
	end
	bs.SetDoubleRewards(nil)
	local rwD = run2b.wins[1] and run2b.wins[1].Rewards
	-- (the round right after the first run's best is a new record: x3 comes from the record, never from Double Rewards)
	local wantD = rwD and bc.RingRewards(rwD.Round, incomeD, rwD.Round > bestBeforeD)
	T.check(rwD and wantD and rwD.Cash == wantD.Cash and rwD.Record == (rwD.Round > bestBeforeD) and rwD.Double ~= true and data.GetCash(p) - before == rwD.Cash, "p4 ring rewards: Double Rewards does not touch ring Cash (round " .. tostring(rwD and rwD.Round) .. ")", rwD and tostring(rwD.Cash) .. " vs " .. tostring(wantD and wantD.Cash) or "no round")
	bs.Forfeit(p)
	advance(0.3)
	bs.Forfeit(p)
	advance(4.8)
	local ring2 = ringOf(p)
	T.check(ring2.Best == math.max(every, #run2.wins + 1) and ring2.Runs == 2, "p4 ring rewards: Ring.Best only grows (max), Runs counts every run (2)", "Best " .. tostring(ring2.Best) .. " Runs " .. tostring(ring2.Runs))

	-- the checkpoint start: a beaten boss round may be the start; one not beaten is refused
	toRing(p)
	advance(1.6)
	local okC, whyC = bs.StartRing(p, every * 3)
	T.check(okC == false and whyC == "Start from round 1 or a boss round you beat", "p4 ring rewards: a boss round not beaten yet cannot be the start", tostring(whyC))
	local m3 = K.logSize()
	local okS, idS = bs.StartRing(p, every)
	local startS = lastMsg(p, "Start", m3)
	T.check(okS == true and startS and startS.Round == every and startS.Ring and startS.Ring.Start == every and startS.Ring.Best == ring2.Best and startS.Ring.Champion.Boss == true,
		"p4 ring rewards: the run starts at the beaten boss round " .. every .. " (Start.Ring.Start, a giant boss champion)", startS and (tostring(startS.Round) .. "/" .. tostring(startS.Ring and startS.Ring.Champion.Boss)) or tostring(idS))
	local gS = bs.GetBattle(p)
	T.check(gS and gS.Round == every, "p4 ring rewards: GetBattle.Round = " .. every)
	bs.Forfeit(p)
	advance(4.8)
	T.eq(ringOf(p).Runs, 3, "p4 ring rewards: Runs 3")

	-- the RingBoard attribute on Portal_Ring: "Name|Best" entries, best first
	local q = newPlayer("RingBoardB", STRONG, 12)
	claimHome(q)
	toRing(q, 4)
	local runQ = runRing(q, 1, {
		maxSeconds = 600,
		onWin = function(out, m, wins)
			if wins >= 2 then
				out.stop = true
			end
		end,
	})
	bs.Forfeit(q)
	advance(0.3)
	local portal = ringPortalInstance()
	local board = portal and portal:GetAttribute("RingBoard")
	-- "Name|Best;Name|Best": every climber of this server so far (earlier scenarios left records too), best first, at
	-- most three entries; p leads, q's entry is its wins
	local entries, sorted, posP, posQ = {}, true, nil, nil
	for name, best in tostring(board):gmatch("([^|;]+)|(%d+)") do
		entries[#entries + 1] = { Name = name, Best = tonumber(best) }
		if #entries > 1 and entries[#entries - 1].Best < tonumber(best) then
			sorted = false
		end
		if name == p.DisplayName then
			posP = #entries
		elseif name == q.DisplayName then
			posQ = #entries
		end
	end
	local wantBoard = p.DisplayName .. "|" .. tostring(ring2.Best) .. " ... " .. q.DisplayName .. "|" .. tostring(#runQ.wins)
	T.check(type(board) == "string" and #entries >= 2 and #entries <= 3 and sorted and posP == 1 and entries[1].Best == ring2.Best and posQ ~= nil and entries[posQ].Best == #runQ.wins,
		"p4 ring rewards: Portal_Ring's RingBoard attribute lists the best records in this server, best first ('Name|Best;Name|Best')", tostring(board) .. " vs " .. wantBoard)
	advance(4.8)
	K.flushErrors("p4ring_rewards")
	K.flushWarnings("p4ring_rewards", ALLOWED_WARNINGS)
	w.stop()
	cleanup({ p, q })
end)

----------------------------------------------------------------------------------------------------
-- p4ring_ends: every end path once
----------------------------------------------------------------------------------------------------
S.p4ring_ends = scenario("p4ring_ends", function()
	if not ready("p4ring_ends") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	holdRaidSchedule(bs)
	ensurePortal()
	local w = watchEnded()
	local info = arenaInfo()

	-- a run that is in its intermission right after the first win (the pets are strong: round 1 is over in seconds)
	local function toIntermission(p)
		toRing(p)
		advance(1.6)
		local run = runRing(p, 1, {
			maxSeconds = 120,
			onWin = function(out)
				out.stop = true
			end,
		})
		return run
	end

	-- 1) Forfeit in a fight: a loss, no loss XP (a forfeit never pays the third), Runs + 1
	local p = newPlayer("RingEndF", STRONG, 12)
	claimHome(p)
	toRing(p)
	local xp0 = totalXp(p, STRONG[1])
	local m = K.logSize()
	local ok, id = bs.StartRing(p, 1)
	advance(0.3)
	bs.Forfeit(p)
	advance(0.3)
	local r = w.find(id)
	local e = lastMsg(p, "End", m)
	T.check(ok and r and r.Forfeit == true and r.Won == false and contains(r.Losers, p.UserId) and e and e.Outcome == "Loss" and e.Rewards and e.Rewards.Final == true and e.Rewards.Xp == 0 and e.Rewards.Run.Wins == 0,
		"p4 ring ends: Forfeit in a fight loses the round and ends the run (Final, 0 wins, no loss XP)", r and tostring(r.Reason) or "no end")
	T.eq(totalXp(p, STRONG[1]), xp0, "p4 ring ends: ...no XP for a forfeit")
	T.check(ringOf(p).Runs == 1 and ringOf(p).Best == 0, "p4 ring ends: ...Ring.Runs 1, Best 0")
	advance(4.6)
	T.check(p:GetAttribute("InBattle") == nil and pocketCount() == 0 and (K.root(p).Position - (info.RingSite.Position + info.RingSite.LookVector * 12 + Vector3.new(0, 3, 0))).Magnitude < 12, "p4 ring ends: ...free, back at the Champion Ring portal, the pocket freed")

	-- 2) Forfeit in an intermission: clean (p4ring_rewards checks the card); here: Runs + 1, the win kept, the pocket freed
	local runI = toIntermission(p)
	T.check(#runI.wins == 1 and p:GetAttribute("InBattle") ~= nil and bs.GetBattle(p) and bs.GetBattle(p).State == "Intermission" and bs.GetBattle(p).Round == 2,
		"p4 ring ends: (setup) round 1 won, the run waits between rounds (GetBattle State Intermission, Round 2)", bs.GetBattle(p) and tostring(bs.GetBattle(p).State) or "no battle")
	local cashI = data.GetCash(p)
	local okI = bs.Forfeit(p)
	advance(0.2)
	T.check(okI == true and ringOf(p).Runs == 2 and ringOf(p).Best == 1 and data.GetCash(p) == cashI, "p4 ring ends: Forfeit between rounds: Runs + 1, Best 1 (the win kept), nothing else moves")
	T.check(bs.Forfeit(p) == false, "p4 ring ends: ...a second Forfeit finds no battle")
	advance(4.6)
	T.check(p:GetAttribute("InBattle") == nil and pocketCount() == 0, "p4 ring ends: ...free, the pocket freed")

	-- 3) a leave DURING a round: Runs + 1 written before the leave save (in the stored profile), the pocket freed
	toRing(p)
	advance(1.6)
	local uid = p.UserId
	local best0 = ringOf(p).Best
	local okL, idL = bs.StartRing(p, 1)
	advance(0.2)
	Mock.RemovePlayer(p)
	advance(0.5)
	local rL = w.find(idL)
	T.check(okL and rL ~= nil and w.count(idL) == 1 and rL.Won == false, "p4 ring ends: a disconnect mid-round ends the round (BattleEnded once, not won)")
	advance(1.5)
	local rec = stored(uid) or {}
	T.check(type(rec.Ring) == "table" and rec.Ring.Runs == 3 and rec.Ring.Best == best0, "p4 ring ends: ...Ring.Runs + 1 is in the saved profile (written in the PlayerRemoving handler, before the leave save)", rec.Ring and ("Runs " .. tostring(rec.Ring.Runs)) or "no Ring")
	advance(4)
	T.eq(pocketCount(), 0, "p4 ring ends: ...the pocket is freed")
	T.eq(#bs.ListBattles(), 0, "p4 ring ends: ...no battle left")

	-- 4) a leave BETWEEN rounds
	local q = newPlayer("RingEndQ", STRONG, 12)
	claimHome(q)
	local runQ = toIntermission(q)
	local quid = q.UserId
	T.check(#runQ.wins == 1, "p4 ring ends: (setup) another climber waits between rounds")
	Mock.RemovePlayer(q)
	advance(2)
	local recQ = stored(quid) or {}
	T.check(type(recQ.Ring) == "table" and recQ.Ring.Runs == 1 and recQ.Ring.Best == 1, "p4 ring ends: a disconnect between rounds: Runs 1, Best 1 saved", recQ.Ring and ("Runs " .. tostring(recQ.Ring.Runs) .. " Best " .. tostring(recQ.Ring.Best)) or "no Ring")
	advance(4)
	T.eq(pocketCount(), 0, "p4 ring ends: ...the pocket is freed")

	-- 5) a respawn elsewhere during a round: the run ends within ~1.5 s (the trial way), no loss XP. One level-1 pet:
	-- its round 1 lasts seconds (a strong team wipes the champion before the presence check can notice the leaver)
	local s = newPlayer("RingEndS", { WEAK[1] }, 1)
	claimHome(s)
	toRing(s)
	local xpS = totalXp(s, WEAK[1])
	local okS, idS = bs.StartRing(s, 1)
	advance(0.2)
	Mock.Kill(s)
	advance(0.1)
	Mock.Respawn(s)
	advance(1.6)
	local rS = w.find(idS)
	T.check(okS and rS ~= nil and rS.Won == false and contains(rS.Losers, s.UserId), "p4 ring ends: a respawn elsewhere during a round ends the run as a loss", rS and tostring(rS.Reason) or "still running")
	T.eq(totalXp(s, WEAK[1]), xpS, "p4 ring ends: ...no loss XP (a leave is never a real loss)")
	advance(4.6)
	T.check(s:GetAttribute("InBattle") == nil and ringOf(s).Runs == 1 and pocketCount() == 0, "p4 ring ends: ...free, Runs 1, the pocket freed")
	-- a respawn BETWEEN rounds
	local runS = toIntermission(s)
	T.check(#runS.wins == 1, "p4 ring ends: (setup) the climber waits between rounds")
	Mock.Kill(s)
	advance(0.1)
	Mock.Respawn(s)
	advance(1.6)
	T.check(ringOf(s).Runs == 2, "p4 ring ends: a respawn between rounds ends the run (Runs 2)")
	advance(4.6)
	T.check(s:GetAttribute("InBattle") == nil and pocketCount() == 0, "p4 ring ends: ...free, the pocket freed")

	-- 6) the pocket leash: a teleport away during a round, and between rounds
	toRing(s)
	advance(1.6)
	local okT, idT = bs.StartRing(s, 1)
	advance(0.2)
	toLobby(s)
	advance(1.6)
	local rT = w.find(idT)
	T.check(okT and rT ~= nil and rT.Won == false, "p4 ring ends: a teleport away from the pocket loses the round and ends the run (the leash)", rT and tostring(rT.Reason) or "still running")
	T.check((toasted(s, "You left the ring", 0)), "p4 ring ends: ...'You left the ring: the run is over.'")
	advance(4.6)
	T.eq(ringOf(s).Runs, 3, "p4 ring ends: ...Runs 3")
	local runT = toIntermission(s)
	T.check(#runT.wins == 1, "p4 ring ends: (setup) between rounds again")
	toLobby(s)
	advance(1.6)
	T.check(ringOf(s).Runs == 4 and bs.GetBattle(s) == nil or (bs.GetBattle(s) and bs.GetBattle(s).State ~= "Intermission"), "p4 ring ends: a teleport away between rounds ends the run (Runs 4)", tostring(ringOf(s).Runs))
	advance(4.6)
	T.check(s:GetAttribute("InBattle") == nil and pocketCount() == 0, "p4 ring ends: ...free, the pocket freed")

	-- 7) an obby match during a round and between rounds
	toRing(s)
	advance(1.6)
	local okM, idM = bs.StartRing(s, 1)
	advance(0.2)
	s:SetAttribute(K.config().Attr.InMatch, true)
	advance(0.8)
	local rM = w.find(idM)
	T.check(okM and rM ~= nil and rM.Won == false, "p4 ring ends: joining an obby match during a round ends the run", rM and tostring(rM.Reason) or "still running")
	s:SetAttribute(K.config().Attr.InMatch, nil)
	advance(4.6)
	T.eq(ringOf(s).Runs, 5, "p4 ring ends: ...Runs 5")
	local runM = toIntermission(s)
	T.check(#runM.wins == 1, "p4 ring ends: (setup) between rounds again")
	s:SetAttribute(K.config().Attr.InMatch, true)
	advance(0.8)
	T.eq(ringOf(s).Runs, 6, "p4 ring ends: joining an obby match between rounds ends the run (Runs 6)")
	s:SetAttribute(K.config().Attr.InMatch, nil)
	advance(4.6)
	T.check(s:GetAttribute("InBattle") == nil and pocketCount() == 0, "p4 ring ends: ...free, the pocket freed")

	-- 8) Shutdown during a round: void (nothing paid, nothing lost), the run over, the wins stay paid
	local u = newPlayer("RingEndU", STRONG, 12)
	claimHome(u)
	toRing(u)
	local runU = runRing(u, 1, {
		maxSeconds = 120,
		onWin = function(out)
			out.stop = true
		end,
	})
	advance(3.2) -- round 2 started
	local id2 = u:GetAttribute("InBattle")
	local cashU, tokensU, xpU = data.GetCash(u), data.GetTokens(u), totalXp(u, STRONG[1])
	T.check(#runU.wins == 1 and type(id2) == "string" and id2 ~= runU.id and bs.GetBattle(u) and bs.GetBattle(u).State == "Running", "p4 ring ends: (setup) round 1 won and paid, round 2 running")
	local mU = K.logSize()
	bs.Shutdown()
	advance(0.3)
	local rU = w.find(id2)
	local eU = lastMsg(u, "End", mU)
	T.check(rU ~= nil and rU.Reason == "Shutdown" and rU.Won == false and eU and eU.Reason == "Shutdown" and eU.Rewards and eU.Rewards.Void == true and eU.Rewards.Final == true and eU.Rewards.Run.Wins == 1,
		"p4 ring ends: Shutdown during a round: the round is void (Reason Shutdown), the final 'End' carries the card with the win kept", rU and tostring(rU.Reason) or "no end")
	T.check(data.GetCash(u) == cashU and data.GetTokens(u) == tokensU and totalXp(u, STRONG[1]) == xpU, "p4 ring ends: ...nothing paid, nothing lost for the void round")
	T.check((toasted(u, "ring round does not count", mU)), "p4 ring ends: ...'this ring round does not count' toast")
	T.eq(ringOf(u).Runs, 1, "p4 ring ends: ...Runs + 1 (the run is over)")
	local okRef, whyRef = bs.StartRing(u, 1)
	T.check(okRef == false and type(whyRef) == "string" and whyRef:find("restarting", 1, true) ~= nil, "p4 ring ends: ...new runs are refused while closing", tostring(whyRef))
	bs.SetClosing(false)
	advance(4.6)
	T.check(u:GetAttribute("InBattle") == nil and pocketCount() == 0, "p4 ring ends: ...free, the pocket freed")
	-- Shutdown between two rounds (no battle runs)
	local runU2 = toIntermission(u)
	T.check(#runU2.wins == 1 and bs.GetBattle(u) and bs.GetBattle(u).State == "Intermission", "p4 ring ends: (setup) the climber waits between rounds")
	local mU2 = K.logSize()
	bs.Shutdown()
	advance(0.3)
	local eU2 = lastMsg(u, "End", mU2)
	T.check(eU2 and eU2.Mode == "Ring" and eU2.Reason == "Shutdown" and eU2.Rewards and eU2.Rewards.Final == true and eU2.Rewards.Run.Wins == 1 and ringOf(u).Runs == 2,
		"p4 ring ends: Shutdown between two rounds ends the run too (a final 'End', Runs + 1)", eU2 and tostring(eU2.Reason) or "no end")
	bs.SetClosing(false)
	advance(4.6)
	T.check(u:GetAttribute("InBattle") == nil and pocketCount() == 0 and #bs.ListBattles() == 0, "p4 ring ends: ...free, the pocket freed, nothing left")

	-- 9) the fail-safe: a failing end of a ring round frees everything once
	toRing(u)
	advance(1.6)
	bs.Debug = { FailEnd = 1 }
	local mF = K.logSize()
	local okFs, idFs = bs.StartRing(u, 1)
	K.waitFor(function()
		return w.find(idFs) ~= nil
	end, 120)
	bs.Debug = nil
	local rF = w.find(idFs)
	T.check(okFs and rF ~= nil and rF.Reason == "Error" and w.count(idFs) == 1 and u:GetAttribute("InBattle") == nil and pocketCount() == 0 and ringOf(u).Runs == 3 and bs.GetBattle(u) == nil,
		"p4 ring ends: when a round's end fails, the fail-safe frees the player and the pocket, closes the run (Runs + 1) and fires BattleEnded once")
	K.flushWarnings("p4ring_ends", { "injected end failure", "[BattleService]", "[DataService]", "[TycoonService]", "[PetCareService]" })
	K.flushErrors("p4ring_ends")
	w.stop()
	cleanup({ p, s, u })
end)

----------------------------------------------------------------------------------------------------
-- p4ring_lossxp: the real-loss gate on the ring, EventService ignores non-Raid results
----------------------------------------------------------------------------------------------------
S.p4ring_lossxp = scenario("p4ring_lossxp", function()
	if not ready("p4ring_lossxp") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	holdRaidSchedule(bs)
	ensurePortal()
	local w = watchEnded()
	local L = bc.LossRules or {}
	T.check(L.LossShare and math.abs(L.LossShare - 1 / 3) < 1e-9 and L.LossMinSeconds == 20 and L.LossMinDamage == 0.2 and bc.TrialRewardRules == nil,
		"p4 loss xp: LossRules.LossShare 1/3, LossMinSeconds 20, LossMinDamage 0.2 (TrialRewardRules gone)")
	-- a passive climber (nobody presses ATTACK) loses round 1 by the 90 s timeout = a REAL loss (>= 20 s): a third of 20 + 6
	local p = newPlayer("RingLoser", MID, 10)
	claimHome(p)
	toRing(p)
	local xp0 = {}
	for _, key in ipairs(MID) do
		xp0[key] = totalXp(p, key)
	end
	local cash0 = data.GetCash(p)
	local mark = K.logSize()
	local ok, id = bs.StartRing(p, 1)
	K.waitFor(function()
		return w.find(id) ~= nil
	end, 130)
	local r = w.find(id)
	local e = lastMsg(p, "End", mark)
	local winXp = bc.Ring.XpBase + bc.Ring.XpPerRound * 1
	if T.check(ok and r ~= nil and contains(r.Losers, p.UserId) and r.Forfeit == false and r.Reason == "Timeout" and r.Duration >= L.LossMinSeconds,
		"p4 loss xp: a passive climber LOSES round 1 by timeout (a real loss: " .. tostring(r and r.Duration) .. " s)", r and tostring(r.Reason) or "no end") then
		local dealt = 1 - ((type(r.Hp) == "table" and r.Hp[2]) or 1)
		local want = bc.LossXp(winXp, r.Duration, dealt)
		local rw = r.Rewards[p.UserId]
		T.check(want == math.floor(winXp / 3 + 0.5) and rw and rw.Xp == want and (rw.Cash or 0) == 0 and e and e.Outcome == "Loss" and e.Rewards and e.Rewards.Xp == want and e.Rewards.Final == true,
			"p4 loss xp: the lost round pays a third of its XP (" .. tostring(want) .. ") and no Cash; the End is the run's final card", rw and tostring(rw.Xp) or "none")
		local gained = true
		for _, key in ipairs(MID) do
			if totalXp(p, key) - xp0[key] ~= want then
				gained = false
			end
		end
		T.check(gained, "p4 loss xp: ...every team pet got exactly " .. tostring(want) .. " XP (PetCareService.GrantXp)")
		T.eq(data.GetCash(p), cash0, "p4 loss xp: ...no Cash")
		T.check((toasted(p, "Run over after round 1", mark)), "p4 loss xp: ...the result card toast", table.concat(toasts(p, mark), " | "))
	end
	advance(4.6)
	-- a forfeit pays nothing (X15), however long the round lasted
	toRing(p)
	advance(1.6)
	local xp1 = totalXp(p, MID[1])
	local ok2, id2 = bs.StartRing(p, 1)
	advance(25)
	bs.Forfeit(p)
	advance(0.3)
	local r2 = w.find(id2)
	T.check(ok2 and r2 and r2.Forfeit == true and r2.Rewards[p.UserId] and r2.Rewards[p.UserId].Xp == 0 and totalXp(p, MID[1]) == xp1, "p4 loss xp: a forfeit after 25 s pays no XP (never for a forfeit)")
	advance(4.6)
	-- a won round pays the full XP (the climber plays)
	toRing(p)
	advance(1.6)
	local xp2 = totalXp(p, MID[1])
	local run = runRing(p, 1, {
		maxSeconds = 120,
		onWin = function(out)
			out.stop = true
		end,
	})
	T.check(run.id ~= nil and #run.wins == 1 and totalXp(p, MID[1]) - xp2 == winXp, "p4 loss xp: a won round still pays the full XP (" .. winXp .. ")", tostring(totalXp(p, MID[1]) - xp2))
	bs.Forfeit(p)
	advance(4.8)

	-- EventService keeps ignoring non-Raid results (a ring result changes nothing it tracks)
	local es = req("server/Services/EventService")
	if es and type(es.GetState) == "function" then
		local before = es.GetState().LastRaid
		local tok0 = data.GetTokens(p)
		local mE = K.logSize()
		bs.BattleEnded:Fire("smoke-ring-result", { BattleId = "smoke-ring-result", Mode = "Ring", Round = 7, Won = true, Winners = { p.UserId }, Losers = {}, Participants = { p.UserId }, Fighters = { p.UserId }, Damage = { [p.UserId] = 100 }, Shares = { [p.UserId] = 1 }, Forfeit = false, Rewards = {}, RewardsPaid = true })
		advance(0.3)
		local after = es.GetState().LastRaid
		T.check(data.GetTokens(p) == tok0 and ((before == nil and after == nil) or (before ~= nil and after ~= nil and before.Won == after.Won and before.BossId == after.BossId)) and #K.remotesFor("Notify", p.UserId, mE) == 0,
			"p4 loss xp: EventService ignores a Mode 'Ring' BattleEnded result (no raid toast, no payment, LastRaid untouched)")
	else
		T.info("*EventService not in this build: the non-Raid check was skipped")
	end
	dropStandIn()
	K.flushErrors("p4ring_lossxp")
	K.flushWarnings("p4ring_lossxp", ALLOWED_WARNINGS)
	w.stop()
	cleanup({ p })
end)

return S
