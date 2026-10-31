-- smoke_p5_flow.lua: the END-TO-END Phase 5 flows (ARCHITECTURE_V3.md "Phase 5 build contract" 12.1, row "flow" of 11.1):
-- 2-4 simulated players on the whole booted Phase 5 game, through the doors a client uses (the MenuPlay / TutorialEvent /
-- ObbyPick / HomeAction / PetCare / BattleRequest / BattleCommand / DungeonRequest / EquipPet / BuyRoulette remotes,
-- ProximityPrompts, walking over Cloud Cash, the developer chat commands) while PlayerService, PortalService, MatchService,
-- TycoonService, PetCareService, BattleService, DungeonService, TutorialService, DevService and DataService run at once.
-- Cash and berries for big purchases come from DataService.AddCash / AddBerries (stand-ins for hours of garden income,
-- like tools/sim_tycoon.py). Every scenario sets up and cleans up its own players.
-- Loaded by tools/smoke.py in BOTH worlds (ARGS.context picks the half). Server scenarios (booted, before "shutdown"):
--   p5flow_new      Nia (new; the game's owner for /petlevel) and Rex (a visitor): held by the main menu until MenuPlay ->
--                   tutorial chapter 1 (claim, gift spin, equip, index, the ONE obby portal: a real Easy climb) -> Medium
--                   unlocked (ObbyPick Medium yes, Hard "Beat Medium to unlock Hard") -> chapter 2: the free Pet Garden, a
--                   roaming pet poops Cloud Cash (Rex scoops nothing, Nia's walk scoops it ONCE) -> the Berry Farm (the
--                   garden's poops grow berries) -> the Food Machine -> Feed spends berries, never Cash (+$1,000 chapter
--                   reward once) -> /petlevel 20 + EVOLVE (stage 1, LevelFactor x1.5 bonus, PetGrowth.Evo in ProfileSync)
--                   -> chapter 3: the Arena gate, a team of 3 (a 4th key refused), Dungeon floor 1 solo (loot once per
--                   room, the first clear once, DungeonWon) -> Champion Ring rounds 1-3 with ATTACK / ELEMENT / SPECIAL /
--                   DASH / BUFF / SWAP (paid once per round) -> Prestige keeps the berries, the Garden and its pet.
--   p5flow_migrate  Vic, a Phase 4 save (4 plants + Collector + 6 decor + a 4-key team + TrialBest 15 + 2 Feasts + BestTimes
--                   Easy / Medium) and Wes, a Phase 3 save (P4 + P5 in ONE load): Home Level unchanged or up, the Farm
--                   level, DecorCredit / LegacyMagnet, a 3-key team with the 4th pet still owned, floors 1-5 cleared, Hard
--                   unlocked, the Feasts as berries fed ("Ready to evolve!"), the welcome toast once; nothing lost.
--   p5flow_dungeon  Ada, Bea, Cal: a party of 3 clears floors 1-2 (loot once per member per room, the first clear once per
--                   member, the chest once), Double Rewards on floor 2 with a late joiner paid only from his room on, Bea
--                   wipes solo on floor 4 (the loss third, no first clear), a rejoin keeps Dungeon, the developer /reset.
--   p5flow_rejoin   Eve + Fin: Fin disconnects mid-run (the run goes on, his save counts the run, nothing twice after his
--                   rejoin), Eve disconnects mid-ring-run (Runs + 1, the pocket freed, no battle after the rejoin), berries
--                   and the 3-key team survive the rejoin.
--   p5flow_merge    Gus on two servers (a second DataService copy, same store): berries add up, Dungeon Cleared union +
--                   a first clear made on both servers lands once in Cleared, two migrations of one Phase 4 save do not
--                   double Clears, Settings of the live session win, Teams stay 3 keys; then the frozen Phase 4
--                   DataService (tools/fixtures/DataService_phase4.lua) saves his Phase 5 profile mid-session: nothing lost.
--   client_p5flow   (client) Nia's real messages replayed: State.Berries / Dungeon / Teams (Slots 3) / PetStage, the Ring
--                   'Start' drawn as the fighter + two helper portraits (Root.Team.Fighter, Root.Team.Helpers.Helper1/2).
-- A shared driver (the character walks at the fighter's legal run toward the nearest enemy and presses ATTACK; dungeon run
-- helpers) is exported as _G.FlowKit5 for the older flows (smoke_p3_flow.lua, smoke_p4_flow.lua).
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local IDS = { Nia = 989501, Rex = 989502, Vic = 989601, Wes = 989602, Ada = 989701, Bea = 989702, Cal = 989703, Eve = 989801, Fin = 989802, Gus = 989901 }

local S = {}
if CONTEXT ~= "server" then
	------------------------------------------------------------------------------------------------
	-- client world: Nia's real messages from the server run
	------------------------------------------------------------------------------------------------
	S.client_p5flow = guarded("client_p5flow", function()
		local KC = _G.KC
		if not T.check(type(KC) == "table" and type(KC.toClient) == "function", "client p5 flow: (precondition) the client kit is loaded") then
			return
		end
		if REPLICATION == nil then
			T.warn("client p5 flow: no server replication log (the server flow did not run)")
			return
		end
		local advance = KC.advance
		local LocalPlayer = game:GetService("Players").LocalPlayer
		local function moduleAt(top, rest)
			local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
			if not inst then
				return nil
			end
			local ok, result = pcall(require, inst)
			return ok and type(result) == "table" and result or nil
		end
		local State = moduleAt("client", "State")
		local BCtl = moduleAt("client", "Controllers/BattleController")
		if not T.check(State ~= nil and BCtl ~= nil and type(BCtl.GetBattle) == "function", "client p5 flow: (precondition) State and BattleController load") then
			return
		end
		local syncs, ringStart, ringSnaps, ringEnd, dungeon, ringRest = {}, nil, {}, nil, {}, {}
		-- her messages as this client's own (her UserId -> the local player's, like smoke_p3_flow's replay)
		local pattern = "%f[%d]" .. IDS.Nia .. "%f[%D]"
		local me = tostring(LocalPlayer.UserId)
		for i = 1, #REPLICATION do
			local e = REPLICATION[i]
			if e.kind == "remote" and e.userId == IDS.Nia then
				local raw = e.args
				if type(raw) == "string" then
					raw = (raw:gsub(pattern, me))
				end
				local args = Mock.Deserialize(raw)
				if type(args) == "table" then
					if e.remote == "ProfileSync" and type(args[1]) == "table" then
						syncs[#syncs + 1] = args[1]
					elseif e.remote == "BattleState" and type(args[2]) == "table" then
						if args[1] == "Start" and args[2].Mode == "Ring" and not ringStart then
							ringStart = args
						elseif ringStart and args[1] == "Snapshot" and args[2].BattleId == ringStart[2].BattleId and #ringSnaps < 6 then
							ringSnaps[#ringSnaps + 1] = args
						elseif ringStart and not ringEnd and (args[1] == "Start" or args[1] == "End") then
							ringRest[#ringRest + 1] = args -- every later round's Start / End, up to the run's final End
							if args[1] == "End" and type(args[2].Rewards) == "table" and args[2].Rewards.Final then
								ringEnd = args
							end
						end
					elseif e.remote == "DungeonState" then
						dungeon[#dungeon + 1] = args
					end
				end
			end
		end
		if not T.check(#syncs > 0, "client p5 flow: (precondition) Nia's ProfileSync messages are in the replication log (p5flow_new ran)") then
			return
		end
		local errors0 = #Mock.Errors
		Mock.SetViewport(1920, 1080)
		LocalPlayer:SetAttribute("InBattle", nil)
		-- the last snapshot before her Prestige carries the Phase 5 fields
		local best = nil
		for _, snap in ipairs(syncs) do
			if type(snap.Dungeon) == "table" and type(snap.PetGrowth) == "table" then
				best = snap
			end
		end
		if T.check(best ~= nil, "client p5 flow: a real ProfileSync carries Dungeon + PetGrowth") then
			KC.toClient("ProfileSync", best)
			advance(0.4)
			local d = State.Dungeon and State.Dungeon()
			T.check(type(d) == "table" and d.Best == 1 and d.Cleared and d.Cleared[1] == true, "client p5 flow: State.Dungeon() mirrors her floor-1 clear", d and tostring(d.Best) or "nil")
			local teams = State.Teams and State.Teams()
			T.check(teams and teams.Slots == 3 and teams.Presets and #teams.Presets[1] == 3, "client p5 flow: State.Teams() = her team of 3 (Slots 3)")
			local key = teams and teams.Presets and teams.Presets[1] and nil
			for k, g in pairs(best.PetGrowth or {}) do
				if type(g) == "table" and g.Evo == 1 then
					key = k
				end
			end
			T.check(key ~= nil and State.PetStage and State.PetStage(key) == 1, "client p5 flow: State.PetStage(key) = 1 for her evolved pet (the grid draws it evolved)", tostring(key))
			T.check(type(best.Berries) == "number", "client p5 flow: ProfileSync carries Berries", tostring(best.Berries))
		end
		if T.check(ringStart ~= nil, "client p5 flow: (precondition) Nia's Ring 'Start' is in the log") then
			KC.toClient("BattleState", ringStart[1], ringStart[2], ringStart[3])
			for _, snap in ipairs(ringSnaps) do
				advance(0.1)
				KC.toClient("BattleState", snap[1], snap[2], snap[3])
			end
			advance(0.6)
			local b = BCtl.GetBattle()
			local gui = LocalPlayer.PlayerGui:FindFirstChild("NimbusBattle")
			local function shownAt(path)
				local node = gui
				for part in path:gmatch("[^%.]+") do
					node = node and node:FindFirstChild(part)
				end
				if not node then
					return false
				end
				local cur = node
				while cur and cur ~= gui do
					if cur:IsA("GuiObject") and cur.Visible == false then
						return false
					end
					cur = cur.Parent
				end
				return true
			end
			T.check(b ~= nil and b.Mode == "Ring" and b.Fighter == true, "client p5 flow: her real Ring 'Start': BattleController runs a Ring battle as her fighter", b and tostring(b.Mode) or "no battle")
			T.check(gui ~= nil and shownAt("Root.Team.Fighter") and shownAt("Root.Team.Helpers.Helper1") and shownAt("Root.Team.Helpers.Helper2"),
				"client p5 flow: ...the HUD shows her fighter card and two helper portraits (4.7)",
				"gui " .. tostring(gui ~= nil) .. " enabled " .. tostring(gui and gui.Enabled) .. " team " .. tostring(shownAt("Root.Team")) .. " fighter " .. tostring(shownAt("Root.Team.Fighter"))
					.. " h1 " .. tostring(shownAt("Root.Team.Helpers.Helper1")) .. " h2 " .. tostring(shownAt("Root.Team.Helpers.Helper2")) .. " snaps " .. #ringSnaps .. " hud " .. tostring(BCtl.IsHudVisible and BCtl.IsHudVisible()))
			for _, msg in ipairs(ringRest) do
				KC.toClient("BattleState", msg[1], msg[2], msg[3])
				advance(msg[1] == "End" and 1.5 or 0.3)
			end
			advance(12)
			T.check(ringEnd ~= nil and BCtl.GetBattle() == nil, "client p5 flow: ...and after the run's rounds and its final End no battle is left (" .. #ringRest .. " later messages)")
		end
		T.info("client p5 flow: " .. #dungeon .. " DungeonState messages of Nia's run in the log")
		T.eq(#Mock.Errors - errors0, 0, "client p5 flow: no client script errors")
		if KC.flushErrors then
			KC.flushErrors("client_p5flow")
		end
	end)
	return S
end

local abs, floor, min, max = math.abs, math.floor, math.min, math.max
local advance, config, mod = K.advance, K.config, K.mod
local ALLOWED_WARNINGS = { "[DataService]", "[GemService]", "HomeBuilder is missing", "[BattleService]", "[DungeonService]", "[TycoonService]", "[PetCareService]" }
local WEAK = { "pebble_pup", "honey_bunny", "puddle_frog" }
local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }
local F = {} -- facts shared by the chapters of one run (filled as they go)

----------------------------------------------------------------------------------------------------
-- Kit: the shared driver + run helpers (exported as _G.FlowKit5)
----------------------------------------------------------------------------------------------------
local Kit = {}
local DOWN, BENCHED = 5, 3

function Kit.req(path)
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
function Kit.BS() return Kit.req("server/Services/BattleService") end
function Kit.Sim() return Kit.req("shared/BattleSim") end
function Kit.BC() return Kit.req("shared/BattleCatalog") end
function Kit.DGS() return Kit.req("server/Services/DungeonService") end
function Kit.DGB() return Kit.req("server/Services/DungeonBuilder") end
function Kit.remote(name)
	local folder = K.remoteFolder()
	return folder and folder:FindFirstChild(name) or nil
end

-- the client-side picture of the player's battles (from the BattleState messages), across rounds / rooms
function Kit.tracker(p, mark)
	return { p = p, cursor = mark or K.logSize(), static = {}, units = {}, ends = {}, events = {}, starts = {}, ticks = 0 }
end

function Kit.pump(tr)
	local log = Mock.RemoteLog
	local uid = tr.p.UserId
	local Sim = Kit.Sim()
	for i = tr.cursor + 1, #log do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == uid then
			local kind, payload = e.args[1], e.args[2]
			if kind == "Start" and type(payload) == "table" and payload.Spectator ~= true then
				tr.start = payload
				tr.starts[#tr.starts + 1] = payload
				tr.id = payload.BattleId
				tr.zone = payload.Zone and payload.Zone.CFrame
				tr.side = payload.Side
				tr.static = {}
				for _, u in ipairs(payload.Units or {}) do
					tr.static[u.id] = u
				end
				tr.units = {}
				tr.fighter = payload.Team and payload.Team.Fighter
				tr.speed = payload.Team and payload.Team.Speed
			elseif kind == "Snapshot" and type(payload) == "table" and payload.BattleId == tr.id then
				tr.units = Sim.DecodeSnapshot(payload, tr.units)
			elseif kind == "Events" and type(payload) == "table" and e.args[3] == tr.id then
				for _, ev in ipairs(payload) do
					tr.events[#tr.events + 1] = ev
					if (ev.type == "Spawn" or ev.type == "Wave") and type(ev.units) == "table" then
						for _, u in ipairs(ev.units) do
							tr.static[u.id] = u
						end
					elseif ev.type == "Swap" and ev.owner == uid then
						tr.fighter = ev["in"]
					elseif ev.type == "Speed" and ev.owner == uid then
						tr.speed = { Walk = ev.walk, Run = ev.run }
					end
				end
			elseif kind == "End" and type(payload) == "table" and payload.Spectator ~= true then
				tr.ends[#tr.ends + 1] = payload
			end
		end
	end
	tr.cursor = #log
end

function Kit.myPos(tr)
	local u = tr.fighter and tr.units[tr.fighter]
	if u then
		return u.x, u.z
	end
	return nil
end

function Kit.nearestEnemy(tr)
	local fx, fz = Kit.myPos(tr)
	if not fx then
		return nil
	end
	local best, bestD, bestS = nil, math.huge, nil
	for id, u in pairs(tr.units) do
		local s = tr.static[id]
		if s and s.side ~= tr.side and u.state ~= DOWN and u.state ~= BENCHED and (u.hp == nil or u.hp > 0) then
			local d = math.sqrt((u.x - fx) ^ 2 + (u.z - fz) ^ 2)
			if d < bestD or (d == bestD and best and id < best) then
				best, bestD, bestS = id, d, s
			end
		end
	end
	return best, bestD, bestS
end

local function charLocal(tr)
	local root = K.root(tr.p)
	if not root or not tr.zone then
		return nil
	end
	local rel = tr.zone:PointToObjectSpace(root.Position)
	return rel.X, rel.Z
end

local function moveChar(tr, tx, tz, step)
	local cx, cz = charLocal(tr)
	if not cx then
		return
	end
	local dx, dz = tx - cx, tz - cz
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= 0.01 then
		return
	end
	local travel = min(step, d)
	Mock.Teleport(tr.p, CFrame.new(tr.zone:PointToWorldSpace(Vector3.new(cx + dx / d * travel, 3, cz + dz / d * travel))))
end

-- one 0.1 s step of a player who walks at the legal run toward the nearest enemy and presses ATTACK (every
-- `opts.every` ticks; `opts.kit` adds ELEMENT + SPECIAL every 10 ticks); `opts.remote` sends through BattleCommand
function Kit.tick(tr, opts)
	opts = opts or {}
	Kit.pump(tr)
	local id, dist, s = Kit.nearestEnemy(tr)
	if not id then
		return nil
	end
	local run = (tr.speed and tr.speed.Run) or 16
	local mine = tr.static[tr.fighter] or {}
	local reach = (tonumber(mine.range) or 4.5) + (tonumber(s.radius) or 1) + 1
	local u = tr.units[id]
	if opts.move ~= false and dist > reach - 1 then
		moveChar(tr, u.x, u.z, run * 0.1)
	end
	tr.ticks = tr.ticks + 1
	local function send(action, arg)
		if opts.remote then
			Mock.FromClient(Kit.remote("BattleCommand"), tr.p, action, arg)
		else
			Kit.BS().Command(tr.p, action, arg)
		end
	end
	if opts.attack ~= false and tr.ticks % (opts.every or 3) == 0 then
		send("Attack", id)
	end
	if opts.kit and tr.ticks % 10 == 0 then
		send("Element", id)
		send("Special")
	end
	return id
end

-- plays (0.1 s steps) until the tracked battle ends or `seconds` pass; -> the End payload | nil
function Kit.playUntilEnd(tr, seconds, opts)
	local t0 = Mock.Clock.now
	Kit.pump(tr)
	local startId = tr.id
	local seen = #tr.ends
	while Mock.Clock.now - t0 < seconds do
		advance(0.1)
		Kit.tick(tr, opts)
		for i = seen + 1, #tr.ends do
			if tr.ends[i].BattleId == (startId or tr.id) then
				return tr.ends[i]
			end
		end
	end
	return nil
end

-- the Champion Ring through the BattleRequest remote, played by the driver: out = { id, refused, starts, wins,
-- finalEnd, nilSamples, tracker }; opts.stopAfterWins / maxSeconds / tick (an extra per-tick hook: fn(tr))
function Kit.runRing(p, startRound, opts)
	opts = opts or {}
	local out = { starts = {}, wins = {}, nilSamples = 0 }
	local mark = K.logSize()
	local tr = Kit.tracker(p, mark)
	out.tracker = tr
	Mock.FromClient(Kit.remote("BattleRequest"), p, "Ring", startRound)
	advance(0.1)
	local id = p:GetAttribute("InBattle")
	if type(id) ~= "string" or id:sub(1, 1) == "D" then
		local why = {}
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark)) do
			why[#why + 1] = tostring(e.args[1])
		end
		out.refused = table.concat(why, " | ")
		return out
	end
	out.id = id
	local seenEnds = 0
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < (opts.maxSeconds or 900) do
		advance(0.1)
		if p:GetAttribute("InBattle") == nil then
			out.nilSamples = out.nilSamples + 1
		end
		Kit.tick(tr, opts)
		if opts.tick then
			opts.tick(tr)
		end
		local finished = false
		for i = seenEnds + 1, #tr.ends do
			local m = tr.ends[i]
			seenEnds = i
			if type(m.Rewards) == "table" then
				if m.Rewards.Final then
					out.finalEnd = m
					finished = true
				elseif m.Rewards.Next then
					out.wins[#out.wins + 1] = m
				end
			end
		end
		if finished or (opts.stopAfterWins and #out.wins >= opts.stopAfterWins) then
			break
		end
	end
	out.starts = tr.starts
	return out
end

-- dungeon helpers ------------------------------------------------------------------------------
function Kit.dinfo()
	local db = Kit.DGB()
	return db and db.GetInfo and db.GetInfo() or nil
end
function Kit.toPad(p, dx, dz)
	local i = Kit.dinfo()
	local pad = i and (i.Pad or i.PromptPart)
	if pad then
		Mock.Teleport(p, CFrame.new(pad.Position + Vector3.new(dx or 0, 3.5, dz or 0)))
	end
	advance(0.05)
end
function Kit.dreq(p, action, a, b)
	Mock.FromClient(Kit.remote("DungeonRequest"), p, action, a, b)
	advance(0.05)
end
-- bug batch 2 #14: `p` walks to chest `slot` of the treasure alcove and presses its E prompt (the engine's path)
function Kit.pickChest(p, run, slot)
	local ri = run and run.Pocket and run.Pocket.Rooms[5] or nil
	local part = ri and ri.Chests and ri.Chests[slot] or nil
	local prompt = part and part:FindFirstChild("ChestPrompt")
	if not prompt then
		return false
	end
	Mock.Teleport(p, CFrame.new(part.CFrame:PointToWorldSpace(Vector3.new(0, 2, 3))))
	advance(0.6)
	if prompt.Enabled then
		Mock.Trigger(prompt, p)
	end
	advance(0.05)
	return true
end
function Kit.runOf(p)
	local dgs = Kit.DGS()
	return dgs and dgs.St.runOf[p] or nil
end
function Kit.waitState(run, state, seconds)
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < seconds do
		if run.State == state then
			return true
		end
		advance(0.25)
	end
	return run.State == state
end
function Kit.crossThreshold(run, p)
	local ri = run and run.Pocket and run.Pocket.Rooms[run.Room]
	if ri and ri.Threshold then
		Mock.Teleport(p, CFrame.new(ri.Threshold.Position))
	end
	advance(0.6)
end
-- dungeon-fixes decision 2: no timer moves the group; every member still in presses E at the open door's
-- EnterPrompt (ProximityPromptService), then the fade's Out passes and the server enters the next room
function Kit.pressDoor(run)
	local dg = Kit.DGS().Dg
	local t0 = Mock.Clock.now
	local prompt = dg.nextDoor(run)
	while not prompt and run.State ~= "Ending" and Mock.Clock.now - t0 < Kit.BC().Dungeon.Intermission + 2 do
		advance(0.25)
		prompt = dg.nextDoor(run)
	end
	if not prompt then
		return false
	end
	for _, uid in ipairs(run.Order) do
		local m = run.Members[uid]
		if m and not m.Left and m.Player.Parent then
			Mock.Teleport(m.Player, CFrame.new(prompt.Parent.Position))
			Mock.Trigger(prompt, m.Player)
		end
	end
	advance(0.6)
	return true
end
-- DungeonState messages of a kind since a log mark
function Kit.dstates(p, mark, kind)
	local out = {}
	for _, e in ipairs(K.remotesFor("DungeonState", p.UserId, mark or 0)) do
		if kind == nil or e.args[1] == kind then
			out[#out + 1] = e.args[2]
		end
	end
	return out
end

-- plays the run from its Hall / Corridor through `toRoom` (default 4) with every member in `members` driving;
-- opts.onRoom(room) runs once when each room's fight started; -> rooms cleared, the last room tried
function Kit.clearRooms(run, members, opts)
	opts = opts or {}
	local D = Kit.BC().Dungeon
	local trs = {}
	for i, m in ipairs(members) do
		trs[i] = Kit.tracker(m)
		trs[i].ticks = i - 1 -- (party members press ATTACK on different ticks)
	end
	if run.State == "Hall" then
		Kit.pressDoor(run)
	end
	local cleared, room = 0, run.Room
	while room <= (opts.toRoom or 4) do
		if run.State ~= "Corridor" then
			break
		end
		local lead = nil
		for _, m in ipairs(members) do
			if m.Parent and Kit.runOf(m) == run then
				lead = lead or m
			end
		end
		if not lead then
			break
		end
		Kit.crossThreshold(run, lead)
		if run.State ~= "Fight" then
			break
		end
		if opts.onRoom then
			opts.onRoom(room)
		end
		local t0 = Mock.Clock.now
		while run.State == "Fight" and Mock.Clock.now - t0 < (opts.roomSeconds or 200) do
			advance(0.1)
			for i, m in ipairs(members) do
				if m.Parent and Kit.runOf(m) == run and not opts.passive then
					Kit.tick(trs[i], opts)
				end
			end
		end
		if run.State ~= "Corridor" and run.State ~= "Treasure" then
			break
		end
		cleared = cleared + 1
		Kit.pressDoor(run)
		if room == 4 then
			Kit.waitState(run, "Treasure", 2)
			break
		end
		local t1 = Mock.Clock.now
		while not (run.Room == room + 1 and run.Phase == "Threshold" and run.State == "Corridor") and Mock.Clock.now - t1 < 2 do
			advance(0.25)
		end
		room = room + 1
		if opts.onCorridor then
			opts.onCorridor(room)
		end
	end
	return cleared, room
end

_G.FlowKit5 = Kit

----------------------------------------------------------------------------------------------------
-- helpers (server)
----------------------------------------------------------------------------------------------------
local function svc()
	return {
		Ty = Kit.req("server/Services/TycoonService"),
		Care = Kit.req("server/Services/PetCareService"),
		BS = Kit.BS(),
		AB = Kit.req("server/Services/ArenaBuilder"),
		DGS = Kit.DGS(),
		DGB = Kit.DGB(),
		PS = Kit.req("server/Services/PlayerService"),
		Portal = mod("PortalService"),
		TSv = mod("TutorialService"),
		DataS = mod("DataService"),
		SS = mod("SpotService"),
		TC = Kit.req("shared/TycoonCatalog"),
		BC = Kit.BC(),
		PK = Kit.req("shared/PetKeys"),
		PC = K.M["shared/PetCatalog"],
		OL = K.M["shared/ObbyLevels"] or Kit.req("shared/ObbyLevels"),
		Steps = Kit.req("shared/TutorialSteps"),
		HR = Kit.req("shared/HomeRoam"),
	}
end

local function ready(label)
	if not K.needBoot() then
		return nil
	end
	local X = svc()
	local ok = X.Ty and X.Care and X.BS and X.AB and X.DGS and X.DGB and X.PS and X.TSv and X.TC and X.BC and X.PK and X.PC and X.OL and X.Steps
	if not T.check(ok and X.DGB.GetInfo and X.DGB.GetInfo() ~= nil and Kit.remote("DungeonRequest") ~= nil and Kit.remote("MenuPlay") ~= nil,
		label .. ": (precondition) the Phase 5 services, catalogs, DungeonInfo and the new remotes are loaded") then
		return nil
	end
	return X
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
local function listText(list)
	local out = {}
	for _, v in ipairs(type(list) == "table" and list or {}) do
		out[#out + 1] = tostring(v)
	end
	return table.concat(out, ",")
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
local function DS() return mod("DataService") end
local function cash(p) return DS().GetCash(p) end
local function gems(p) return DS().GetGems(p) end
local function tokens(p) return DS().GetTokens(p) end
local function berries(p) return DS().GetBerries(p) end
local function home(p) return DS().GetHome(p) end
local function level(p, id)
	local h = home(p)
	return (h and h.Stations and h.Stations[id]) or 0
end
local function fund(p, amount)
	local have = cash(p)
	if amount and amount > have then
		DS().AddCash(p, amount - have)
	end
end
local function totalXp(p, key)
	local lv, xp = DS().GetPetLevel(p, key)
	local Cat = Kit.req("shared/TycoonCatalog")
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
	local prof = DS().GetProfile(p)
	Kit.req("shared/PetKeys").Add(prof, key, n or 1)
	if lv then
		prof.PetLevels[key] = { Level = lv, Xp = 0 }
	end
	DS().MarkDirty(p)
end
local function equipped(p)
	return DS().GetProfile(p).Equipped or {}
end
local function away(p)
	Mock.Teleport(p, CFrame.new(config().Lobby.Origin + Vector3.new(0, 4, 0)))
end
local function standAt(p, pos)
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 0)))
end
local function tutEvent(p, name)
	advance(0.3)
	Mock.FromClient(Kit.remote("TutorialEvent"), p, name)
	advance(0.3)
end
local function tut(p)
	return mod("TutorialService").GetState(p)
end
local function stepOf(p)
	local st = tut(p)
	if not st then
		return nil
	end
	return st.Done and "done!" or st.Id
end
local function waitStep(p, id, seconds)
	K.waitFor(function()
		return stepOf(p) == id
	end, seconds or 3)
	return stepOf(p)
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
	for _, d in ipairs(info and info.Folder and info.Folder:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
			return d
		end
	end
	return nil
end
-- walks to a free gate and presses E on its ClaimPrompt; the plot index or nil
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
local function attrUp(inst, name, depth)
	local cur = inst
	for _ = 1, depth or 6 do
		if not cur then
			return nil
		end
		local v = cur:GetAttribute(name)
		if v ~= nil then
			return v
		end
		cur = cur.Parent
	end
	return nil
end
local function buyPrompt(info, id)
	for _, d in ipairs(info.Folder:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "BuyPrompt" and attrUp(d, "StationId") == id then
			return d
		end
	end
	return nil
end
local function promptPosition(prompt)
	local parent = prompt and prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end
local function pressPad(p, info, id)
	local prompt = buyPrompt(info, id)
	local at = promptPosition(prompt)
	if at then
		Mock.Teleport(p, CFrame.new(at + Vector3.new(0, 3, 0)))
	end
	if prompt then
		Mock.Trigger(prompt, p)
	end
	advance(0.6)
end
local function stationModel(info, id)
	for _, d in ipairs(info.Folder:GetDescendants()) do
		if d.Name == "Station_" .. id then
			return d
		end
	end
	return nil
end
local function carePrompt(info, stationId, name)
	local m = stationModel(info, stationId)
	for _, d in ipairs(m and m:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") and d.Name == name then
			return d
		end
	end
	return nil
end
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
local function scoopLedger(Ty)
	local totals, calls = {}, {}
	local conn = Ty.CoinsScooped and Ty.CoinsScooped:Connect(function(player, amount)
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
			end
		end,
	}
end
-- waits (1 s steps) for a player's first Cloud Cash drop with a poop; -> the drop | nil
local function firstDrop(Ty, p, seconds)
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < (seconds or 60) do
		for _, d in ipairs(Ty.Drops(p) or {}) do
			if (d.Poops or 0) >= 1 then
				return d
			end
		end
		advance(1)
	end
	return nil
end
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
local function toRing(X, p)
	local info = X.AB.GetInfo and X.AB.GetInfo() or nil
	local pos = positionOf(info and info.RingPortal) or positionOf(workspace:FindFirstChild("Portal_Ring", true))
	if pos then
		Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 6)))
	end
	advance(0.1)
	return pos
end
-- the game's owner may run the developer chat commands (DevService): `userId` owns this game for the scenario
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
local function chat(p, text)
	advance(0.6)
	Mock.FireSignal(p, "Chatted", text)
	advance(0.8)
end
local function lastSync(p, mark)
	local list = K.remotesFor("ProfileSync", p.UserId, mark or 0)
	local e = list[#list]
	return e and e.args[1] or nil
end
local function dungeonText(d)
	if type(d) ~= "table" then
		return tostring(d)
	end
	local floors = {}
	for f, v in pairs(d.Cleared or {}) do
		if v then
			floors[#floors + 1] = tonumber(f) or f
		end
	end
	table.sort(floors, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, f in ipairs(floors) do
		parts[#parts + 1] = tostring(f)
	end
	return "{Best " .. tostring(d.Best) .. " Runs " .. tostring(d.Runs) .. " Clears " .. tostring(d.Clears) .. " Cleared " .. table.concat(parts, ",") .. "}"
end
local function floorsExactly(d, n)
	local set = {}
	for f, v in pairs(d and d.Cleared or {}) do
		if v == true then
			set[tonumber(f) or f] = true
		end
	end
	if count(set) ~= n then
		return false
	end
	for f = 1, n do
		if not set[f] then
			return false
		end
	end
	return true
end
local function sumLoot(list, field)
	local s = 0
	for _, l in ipairs(list) do
		s = s + (tonumber(l[field]) or 0)
	end
	return s
end
-- ends every dungeon run and party left over (a failed check must not leak a run into the next scenario)
local function endDungeons()
	local dgs = Kit.DGS()
	if not dgs then
		return
	end
	local order = {}
	for _, id in ipairs(dgs.St.runOrder or {}) do
		order[#order + 1] = id
	end
	for _, id in ipairs(order) do
		local run = dgs.St.runs[id]
		if run then
			pcall(dgs.Dg.endRun, run, false, "Abandoned", true)
		end
	end
	for _, party in pairs(dgs.St.parties or {}) do
		if party and party.Leader then
			pcall(dgs.LeaveParty, party.Leader)
		end
	end
	if dgs.SetClosing then
		dgs.SetClosing(false)
	end
	advance(0.2)
end

-- the scenario wrapper: no scheduled raid, the battle snapshots stay out of the client replay (except Nia's first ring
-- seconds: F.record), every player removed and every run ended afterwards
local function scenario(name, fn)
	return guarded(name, function()
		local bs = Kit.BS()
		local realStartRaid = bs and bs.StartRaid
		if bs then
			bs.StartRaid = function()
				return false, "A raid is already running"
			end
		end
		local savedHook = Mock._onRemote
		if savedHook then
			Mock._onRemote = function(entry)
				if entry.remote == "BattleState" then
					local kind = entry.args and entry.args[1]
					local keep = entry.userId == IDS.Nia and (kind == "Start" or kind == "End" or (F.record == true and (F.recordUntil == nil or Mock.Clock.now <= F.recordUntil)))
					if not keep then
						return
					end
				end
				savedHook(entry)
			end
		end
		local players = {}
		local ok, err = pcall(fn, players)
		F.record, F.recordUntil = nil, nil
		if savedHook then
			Mock._onRemote = savedHook
		end
		endDungeons()
		if bs then
			for _, p in ipairs(players) do
				if p and p.Parent and bs.IsInBattle and bs.IsInBattle(p) then
					pcall(bs.Forfeit, p)
				end
			end
			if bs.SetDoubleRewards then
				pcall(bs.SetDoubleRewards, false)
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
end

-- a real climb of the level the obby party picked: the ONE obby pad -> the party countdown -> checkpoints -> the finish;
-- -> ok, match | why
local function climbObby(p)
	local MS = K.MS()
	local zone = K.W.lobbyInfo.Portals.Obby.Zone
	Mock.Teleport(p, CFrame.new(zone.Position))
	local started = K.waitFor(function()
		return MS.GetMatchOf(p) ~= nil
	end, config().Match.PartyCountdown + 8)
	if not started then
		return false, "no match started from the obby pad"
	end
	local m = MS.GetMatchOf(p)
	if not K.toPlaying(m) then
		return false, "the match never reached Playing"
	end
	advance(0.5)
	for i = 1, #m.Course.Checkpoints do
		local cp = m.Course.Checkpoints[i]
		Mock.Teleport(p, cp.Part.Position + Vector3.new(0, 3.5, 0))
		advance(0.6)
	end
	local fin = m.Course.Finish
	Mock.Teleport(p, fin.Position + Vector3.new(0, fin.Size.Y / 2 + 3.5, 0))
	K.waitFor(function()
		return p:GetAttribute(config().Attr.InMatch) ~= true
	end, 20)
	advance(1)
	return true, m
end

----------------------------------------------------------------------------------------------------
-- p5flow_new: a brand-new player through the whole Phase 5 game
----------------------------------------------------------------------------------------------------
-- 1. the main menu holds the character until PLAY; tutorial chapter 1 with a real Easy climb; the obby level picker
local function newArrive(X, players)
	local Config = config()
	local cfg = Config.MainMenu
	local was = cfg.Enabled
	cfg.Enabled = true
	local nia, rex
	local okHold, errHold = pcall(function()
		nia = Mock.AddPlayer("Nia", IDS.Nia)
		players[#players + 1] = nia
		rex = Mock.AddPlayer("Rex", IDS.Rex)
		players[#players + 1] = rex
		advance(1.2)
		T.check(nia.Character == nil and X.PS.HasSpawned(nia) == false, "p5 flow new: the main menu holds Nia's character (no spawn before PLAY)")
		T.eq(nia:GetAttribute(Config.Attr.ProfileLoaded or "ProfileLoaded"), true, "p5 flow new: ...while her profile loads behind it (ProfileLoaded)")
		Mock.FromClient(Kit.remote("MenuPlay"), nia)
		Mock.FromClient(Kit.remote("MenuPlay"), rex)
		advance(0.8)
		T.check(nia.Character ~= nil and X.PS.HasSpawned(nia) and rex.Character ~= nil, "p5 flow new: PLAY (MenuPlay) spawns her character (and Rex's)")
	end)
	cfg.Enabled = was
	if not okHold then
		error(errHold, 0)
	end
	advance(1.5)
	-- chapter 1: welcome -> home (claim) -> shop -> spin -> equip -> index -> the obby portal -> finish -> done
	local DataS, SS = X.DataS, X.SS
	T.eq(stepOf(nia), "welcome", "p5 flow new: her tutorial starts at 'welcome'")
	tutEvent(nia, "Next")
	T.eq(stepOf(nia), "home", "p5 flow new: Next -> 'home'")
	local st = tut(nia)
	local index = st and st.Target and st.Target.SpotIndex or freeIndex()
	local got = claim(nia, index)
	F.niaPlot = got
	waitStep(nia, "shop", 3)
	T.check(got ~= nil and stepOf(nia) == "shop", "p5 flow new: E at the free gate the arrow shows claims her home -> 'shop'", tostring(stepOf(nia)))
	tutEvent(nia, "ShopOpened")
	T.eq(stepOf(nia), "spin", "p5 flow new: the Shop opened -> 'spin' (gift tokens)")
	withRoll(WEAK[1], function()
		Mock.FromClient(Kit.remote("BuyRoulette"), nia, "Cloud")
	end)
	advance(0.6)
	T.check(X.PK.Count(DataS.GetProfile(nia), WEAK[1]) == 1 and listHas(equipped(nia), WEAK[1]), "p5 flow new: the gift pays her first Cloud Roulette spin (" .. WEAK[1] .. ", equipped)")
	T.eq(stepOf(nia), "equip", "p5 flow new: the spin -> 'equip'")
	tutEvent(nia, "PetsOpened")
	T.eq(stepOf(nia), "index", "p5 flow new: Pets opened with the pet equipped -> 'index'")
	tutEvent(nia, "IndexOpened")
	T.eq(stepOf(nia), "portal", "p5 flow new: the Index opened -> 'portal'")
	st = tut(nia)
	local obbyPos = K.W.lobbyInfo.Portals.Obby.Center or (K.W.lobbyInfo.Portals.Obby.Zone and K.W.lobbyInfo.Portals.Obby.Zone.Position)
	T.check(st and st.Target and typeof(st.Target.Position) == "Vector3" and obbyPos and K.planar(st.Target.Position, obbyPos) < 12,
		"p5 flow new: 'portal' points at the ONE obby portal (lobby.Portals.Obby)")
	-- the obby: a new player climbs Easy (no win yet); the climb completes 'portal' and 'finish'
	local OL = X.OL
	T.eq(OL.HighestUnlocked(DataS.GetProfile(nia).Stats.BestTimes), 1, "p5 flow new: a new player has only Easy open (ObbyLevels)")
	local okClimb, m = climbObby(nia)
	T.check(okClimb and type(m) == "table" and m.DifficultyId == "Easy", "p5 flow new: stepping onto the obby pad alone starts an Easy party -> a real climb to the finish", tostring(type(m) == "table" and m.DifficultyId or m))
	local bt = DataS.GetProfile(nia).Stats.BestTimes
	T.check(type(bt.Easy) == "number" and bt.Easy > 0, "p5 flow new: ...the win records her Easy time (Stats.BestTimes)")
	waitStep(nia, "done", 5)
	T.eq(stepOf(nia), "done", "p5 flow new: the climb finishes 'portal' + 'finish' -> 'done'")
	-- finishing Easy unlocks Medium: ObbyPick Medium yes, Hard no
	local mark = K.logSize()
	advance(1.2)
	Mock.FromClient(Kit.remote("ObbyPick"), nia, "Hard")
	advance(0.4)
	T.check(nia:GetAttribute(Config.Attr.ObbyLevel) ~= "Hard" and toasted(nia, "Beat Medium to unlock Hard", mark), "p5 flow new: ObbyPick('Hard') is refused: 'Beat Medium to unlock Hard'")
	advance(0.6)
	Mock.FromClient(Kit.remote("ObbyPick"), nia, "Medium")
	advance(0.4)
	T.check(OL.HighestUnlocked(bt) == 2 and nia:GetAttribute(Config.Attr.ObbyLevel) == "Medium", "p5 flow new: finishing Easy unlocked Medium: ObbyPick('Medium') sets ObbyLevel = Medium")
	local t0 = tokens(nia)
	tutEvent(nia, "Next")
	waitStep(nia, "garden", 3)
	T.check(stepOf(nia) == "garden" and tokens(nia) == t0 + Config.Tutorial.FinishReward.Tokens, "p5 flow new: 'done' pays the basics reward and the home chapter starts at 'garden' (her home is claimed)",
		tostring(stepOf(nia)))
	T.check(SS.GetSpot(nia) ~= nil, "p5 flow new: her plot is hers")
	return nia, rex
end

-- 2. the home chapter: the free Pet Garden, Cloud Cash scooped once, the Berry Farm grows berries, the Food Machine, Feed
local function newHome(X, nia, rex, ledger)
	local DataS, Ty, TC, PC = X.DataS, X.Ty, X.TC, X.PC
	local info = F.niaPlot and spots()[F.niaPlot]
	if not T.check(info ~= nil and Ty.GetPlot(nia) == info, "p5 flow new: (precondition) Nia has her plot") then
		return false
	end
	local petId = WEAK[1]
	local pads = TC.AvailablePads(home(nia))
	T.check(#pads == 1 and pads[1].StationId == "Garden" and pads[1].Price == 0, "p5 flow new: her fresh home shows one pad: the free Pet Garden")
	pressPad(nia, info, "Garden")
	away(nia)
	T.check(level(nia, "Garden") == 1, "p5 flow new: E on it builds the Pet Garden for free")
	Mock.FromClient(Kit.remote("HomeAction"), nia, "GardenSet", { 1, petId })
	advance(0.5)
	T.check(home(nia).Garden[1] == petId and info.Folder:GetAttribute("GardenPets") == "1=" .. petId, "p5 flow new: her pet goes to work on bed 1 (GardenPets)")
	waitStep(nia, "coins", 3)
	T.eq(stepOf(nia), "coins", "p5 flow new: a pet on a bed completes 'garden' -> 'coins'")
	T.check(info.Folder:GetAttribute("RoamSeed") ~= nil and tostring(info.Folder:GetAttribute("Roam")):match("^1=") ~= nil, "p5 flow new: the pet roams (RoamSeed + Roam '1=<epoch>')")
	-- it eats at the Food Bowl and poops Cloud Cash (the shared HomeRoam plan the server and every client follow)
	local seed = info.Folder:GetAttribute("RoamSeed")
	local epoch = tonumber(tostring(info.Folder:GetAttribute("Roam")):match("^1=([%d%.]+)"))
	local states = {}
	if X.HR and seed and epoch then
		for t = 0, X.HR.Cycle, 0.5 do
			local _, _, state = X.HR.At(seed, 1, epoch, epoch + t)
			states[tostring(state)] = true
		end
	end
	T.check(states.Eat and states.Poop, "p5 flow new: its first roam cycle (HomeRoam.At) has it eat at the bowl and poop", (function()
		local list = {}
		for k in pairs(states) do
			list[#list + 1] = k
		end
		table.sort(list)
		return table.concat(list, ",")
	end)())
	-- only the owner scoops it, exactly once
	away(rex)
	local drop = firstDrop(Ty, nia, 60)
	if T.check(drop ~= nil and typeof(drop.Position) == "Vector3" and drop.Value > 0, "p5 flow new: within one roam cycle the pet poops a Cloud Cash coin (TycoonService.Drops)") then
		advance(1.2)
		local stC = tut(nia)
		T.check(stC and stC.Id == "coins" and stC.Target and typeof(stC.Target.Position) == "Vector3" and K.planar(stC.Target.Position, drop.Position) < 1, "p5 flow new: 'coins' points at the drop")
		local bank0, rexCash = home(nia).CollectorCash, cash(rex)
		standAt(rex, drop.Position)
		advance(0.6)
		away(rex)
		T.check(cash(rex) == rexCash and ledger.of(rex) == 0 and home(nia).CollectorCash >= bank0 - 1e-6, "p5 flow new: Rex walking over Nia's Cloud Cash scoops nothing")
		local c0, total0 = cash(nia), cash(nia) + home(nia).CollectorCash
		standAt(nia, drop.Position)
		advance(0.4)
		away(nia)
		local gained = cash(nia) - c0
		T.check(gained >= 1 and gained == ledger.of(nia), "p5 flow new: Nia walking over it scoops it (+$" .. gained .. ", CoinsScooped)")
		local total1 = cash(nia) + home(nia).CollectorCash
		T.check(total1 >= total0 - 1e-6 and total1 <= total0 + drop.Value * 2 + 1e-6, "p5 flow new: ...paid once: Cash + the lawn stay the same (only a new poop may add)", total0 .. " -> " .. total1)
		local c1, l1 = cash(nia), ledger.of(nia)
		standAt(nia, drop.Position)
		advance(0.4)
		away(nia)
		T.check(cash(nia) - c1 == ledger.of(nia) - l1 and cash(nia) - c1 < max(1, floor(drop.Value)), "p5 flow new: ...a second walk over the same spot pays that coin no second time")
		waitStep(nia, "machine", 3)
		T.eq(stepOf(nia), "machine", "p5 flow new: scooping completes 'coins' -> 'machine'")
	end
	-- 'machine': the Farm pad until built, then the Food Machine pad
	local stM = tut(nia)
	local farmPad = buyPrompt(info, "Press1")
	local farmAt = farmPad and promptPosition(farmPad)
	T.check(stM and stM.Target and typeof(stM.Target.Position) == "Vector3" and farmAt and K.planar(stM.Target.Position, farmAt) < 4, "p5 flow new: 'machine' points at the Berry Farm pad first")
	local inc0 = Ty.IncomePerSecond(nia)
	fund(nia, TC.PriceFor("Press1", 1))
	pressPad(nia, info, "Press1")
	away(nia)
	T.check(level(nia, "Press1") == 1 and stationModel(info, "Press1") ~= nil and TC.Get("Press1").Name == "Berry Farm", "p5 flow new: the Berry Farm stands (Press1 Lv 1)")
	advance(1.2)
	T.check(Ty.IncomePerSecond(nia) > inc0, "p5 flow new: ...its berries make every Cloud Cash coin bigger (IncomePerSecond up)", inc0 .. " -> " .. Ty.IncomePerSecond(nia))
	-- the garden's poops grow berries now (V x Berries.Share each, the fraction kept server-side)
	local b0 = berries(nia)
	local t0 = Mock.Clock.now
	while berries(nia) <= b0 and Mock.Clock.now - t0 < 6 * (X.HR and X.HR.Cycle or 24) do
		advance(2)
	end
	T.check(berries(nia) > b0, "p5 flow new: the Berry Farm + her pet's poops grow berries into her basket (" .. b0 .. " -> " .. berries(nia) .. ")")
	T.eq(nia:GetAttribute(config().Attr.Berries or "Berries"), berries(nia), "p5 flow new: ...the Berries attribute follows")
	fund(nia, TC.PriceFor("Kitchen", 1))
	pressPad(nia, info, "Kitchen")
	away(nia)
	T.check(level(nia, "Kitchen") == 1, "p5 flow new: then the Food Machine")
	waitStep(nia, "feed", 3)
	T.eq(stepOf(nia), "feed", "p5 flow new: the Food Machine completes 'machine' -> 'feed'")
	-- Feed: berries, never Cash; a feed without enough berries is refused
	advance(1.2)
	local feedPrompt = carePrompt(info, "Kitchen", "FeedPrompt")
	if T.check(feedPrompt ~= nil and feedPrompt:GetAttribute("OwnerUserId") == nia.UserId, "p5 flow new: the Food Machine has her FeedPrompt") then
		local mark = K.logSize()
		local at = promptPosition(feedPrompt)
		if at then
			Mock.Teleport(nia, CFrame.new(at + Vector3.new(0, 0, -3)))
		end
		Mock.Trigger(feedPrompt, nia)
		advance(0.3)
		away(nia)
		local op = K.lastRemote("OpenPanel", nia.UserId, mark)
		T.check(op ~= nil and op.args[1] == "Pets" and type(op.args[2]) == "table" and op.args[2].Action == "Feed", "p5 flow new: E opens her Pets panel on Feed")
	end
	local def = PC.Get(petId)
	local cost, xpGain = TC.FeedBerries(def, 1), TC.FeedXp(1, 1)
	DataS.SpendBerries(nia, berries(nia))
	advance(0.6)
	local mark = K.logSize()
	local cashF, xpF = cash(nia), totalXp(nia, petId)
	Mock.FromClient(Kit.remote("PetCare"), nia, "Feed", petId)
	advance(0.5)
	T.check(totalXp(nia, petId) == xpF and cash(nia) == cashF and toasted(nia, "berries", mark), "p5 flow new: Feed with an empty basket is refused (no Cash is taken instead)",
		table.concat(toasts(nia, nil, mark), " | "))
	DataS.AddBerries(nia, cost) -- (a stand-in for the berries her garden grows meanwhile)
	advance(0.6)
	local fed = nil
	local conn = X.Care.Fed:Connect(function(player, key, food)
		if player == nia then
			fed = { key, food }
		end
	end)
	local c2, chapter0 = cash(nia), tut(nia)
	mark = K.logSize()
	Mock.FromClient(Kit.remote("PetCare"), nia, "Feed", petId)
	advance(0.6)
	conn:Disconnect()
	T.check(berries(nia) == 0 and totalXp(nia, petId) - xpF == xpGain, "p5 flow new: ONE Feed: " .. cost .. " berries -> +" .. xpGain .. " XP", berries(nia) .. " berries left, +" .. (totalXp(nia, petId) - xpF) .. " XP")
	T.check(fed ~= nil and fed[1] == petId and fed[2] == "Berries", "p5 flow new: ...PetCareService.Fed fires with 'Berries'")
	local st = tut(nia)
	T.check(chapter0 and chapter0.Id == "feed" and st and st.Chapter == 3 and st.Id == "arena", "p5 flow new: the feed ends the home chapter -> chapter 3 'arena'", st and tostring(st.Id) or "nil")
	T.eq(cash(nia), c2 + 1000, "p5 flow new: ...no Cash for food; the chapter pays its $1,000 once")
	advance(1.2)
	Mock.FromClient(Kit.remote("PetCare"), nia, "Feed", petId)
	advance(0.6)
	T.eq(cash(nia), c2 + 1000, "p5 flow new: a refused second feed (no berries) pays no second chapter reward")
	return true
end

-- the newest event of a type (and owner / unit) since an index of the tracker's event list
local function eventSince(tr, from, evType, test)
	for i = from + 1, #tr.events do
		local ev = tr.events[i]
		if ev.type == evType and (test == nil or test(ev)) then
			return ev
		end
	end
	return nil
end

-- the six controls through the BattleCommand remote, during ring rounds (each retried while no enemy is alive, e.g.
-- between two rounds): -> { Attack, Element, Special, Dash, Buff, Swap } = true when its event came back
local function tryControls(X, p, tr)
	local uid = p.UserId
	local seen = {}
	local function cmd(action, arg)
		Mock.FromClient(Kit.remote("BattleCommand"), p, action, arg)
	end
	local function liveEnemy(seconds)
		local t0 = Mock.Clock.now
		while Mock.Clock.now - t0 < (seconds or 12) do
			Kit.pump(tr)
			local id = Kit.nearestEnemy(tr)
			if id and X.BS.IsInBattle(p) then
				return id
			end
			advance(0.1)
		end
		return nil
	end
	local function walkIn()
		local t1 = Mock.Clock.now
		while Mock.Clock.now - t1 < 6 do
			advance(0.1)
			Kit.tick(tr, { attack = false })
			local _, dist, s = Kit.nearestEnemy(tr)
			local mine = tr.static[tr.fighter] or {}
			if dist and dist <= (tonumber(mine.range) or 4.5) + (tonumber(s and s.radius) or 1) then
				return true
			end
		end
		return false
	end
	-- sends `action` while an enemy lives and waits for its event; up to 4 tries; `prep` runs before each send
	local function try(action, argFn, evType, test, prep)
		for _ = 1, 4 do
			local enemy = liveEnemy()
			if not enemy then
				return false
			end
			if prep then
				prep()
			end
			local from = #tr.events
			cmd(action, argFn and argFn(Kit.nearestEnemy(tr) or enemy) or nil)
			local t0 = Mock.Clock.now
			while Mock.Clock.now - t0 < 1.5 do
				advance(0.1)
				Kit.tick(tr, { attack = false })
				if eventSince(tr, from, evType, test) then
					return true
				end
			end
		end
		return false
	end
	local function mine(ev)
		return ev.unit == tr.fighter or ev.from == tr.fighter
	end
	local function owned(ev)
		return ev.owner == uid
	end
	local function target(id)
		return id
	end
	seen.Element = try("Element", target, "Element", mine, walkIn)
	seen.Dash = try("Dash", nil, "Dash", mine)
	seen.Buff = try("Buff", function()
		return 2
	end, "Buff", owned)
	local fighter0 = tr.fighter
	seen.Swap = try("Swap", function()
		return 2
	end, "Swap", owned) and tr.fighter ~= fighter0
	-- SPECIAL the moment the fighter's energy is full (hits charge it; a round won meanwhile starts a fresh meter)
	local full = (X.BC.Fighter and X.BC.Fighter.SpecialMeterMax) or 100
	local t2 = Mock.Clock.now
	seen.Special = false
	while Mock.Clock.now - t2 < 90 and not seen.Special do
		advance(0.1)
		Kit.tick(tr, { attack = false }) -- (energy fills with time and the hits she takes; a won round would reset it)
		local u = tr.fighter and tr.units[tr.fighter]
		-- (the snapshot meter is rounded: press again every 0.5 s while it reads full)
		if u and (u.meter or 0) >= full and Kit.nearestEnemy(tr) and tr.ticks % 5 == 0 then
			local from = #tr.events
			cmd("Special")
			for _ = 1, 3 do
				advance(0.1)
				Kit.pump(tr)
				if eventSince(tr, from, "Special", mine) then
					seen.Special = true
					break
				end
			end
		end
	end
	seen.Attack = try("Attack", target, "Hit", function(ev)
		return ev.from == tr.fighter
	end, walkIn)
	return seen
end

-- 3. evolve, chapter 3 (arena, team of 3, the dungeon), the Champion Ring with the new controls, Prestige
local function newBattle(X, nia)
	local Config = config()
	local DataS, Ty, TC, BC, PC = X.DataS, X.Ty, X.TC, X.BC, X.PC
	local petId = WEAK[1]
	-- /petlevel 20 (the owner's developer command) + EVOLVE: stage 1 multiplies the LEVEL bonus by 1.5 (3.1). Bug batch 2
	-- #18: her pet works on bed 1 (busy gardening, not following): the "Remote recall" takes it out and equips it in one
	-- request, and after the level it goes back to its bed (and stops following)
	Mock.FromClient(Kit.remote("HomeAction"), nia, "GardenRecall", { Key = petId, To = "Equip" })
	advance(0.6)
	T.check(home(nia).Garden[1] == nil and listHas(DataS.GetProfile(nia).Equipped, petId), "p5 flow new: GardenRecall takes her pet off bed 1 and equips it in one request (bug batch 2 #18)")
	chat(nia, "/petlevel 20")
	local lv20 = DataS.GetPetLevel(nia, petId)
	T.eq(lv20, 20, "p5 flow new: '/petlevel 20' sets her equipped pet to level 20")
	Mock.FromClient(Kit.remote("HomeAction"), nia, "GardenSet", { 1, petId })
	advance(0.5)
	T.check(home(nia).Garden[1] == petId and not listHas(DataS.GetProfile(nia).Equipped, petId), "p5 flow new: ...back on bed 1 it stops following (one job at a time)")
	advance(1.2)
	local inc0 = Ty.IncomePerSecond(nia)
	local mark = K.logSize()
	Mock.FromClient(Kit.remote("PetCare"), nia, "Evolve", petId)
	advance(0.8)
	T.eq(DataS.GetEvolution(nia, petId), 1, "p5 flow new: EVOLVE at level 20: stage 1")
	T.check(toasted(nia, "Level bonus x1.5", mark), "p5 flow new: ...'<pet> evolved! Level bonus x1.5!'", table.concat(toasts(nia, nil, mark), " | "))
	advance(1.2)
	local want = PC.LevelFactor(20, 1) / PC.LevelFactor(20, 0)
	T.check(abs(Ty.IncomePerSecond(nia) / inc0 - want) < 1e-6, "p5 flow new: ...its Cloud Cash grows x" .. string.format("%.3f", want) .. " (LevelFactor(20, 1) / LevelFactor(20, 0))",
		inc0 .. " -> " .. Ty.IncomePerSecond(nia))
	local snap = lastSync(nia, mark)
	T.check(snap and type(snap.PetGrowth) == "table" and type(snap.PetGrowth[petId]) == "table" and snap.PetGrowth[petId].Evo == 1,
		"p5 flow new: ...ProfileSync carries PetGrowth Evo 1 (State.PetStage -> every grid draws it evolved, 3.7)")
	-- chapter 3: the Arena gate of the Gate Court
	local arena = X.AB.GetInfo()
	local gatePart = arena and arena.ArenaPortal
	local gatePrompt = gatePart and gatePart:FindFirstChild("ArenaPortalPrompt", true)
	if T.check(gatePrompt ~= nil, "p5 flow new: Portal_Arena stands in the Gate Court with its ArenaPortalPrompt") then
		Mock.Teleport(nia, CFrame.new(gatePart.Position + Vector3.new(0, 3, 3)))
		advance(0.2)
		Mock.Trigger(gatePrompt, nia)
		advance(1.0)
		waitStep(nia, "team", 4)
	end
	T.eq(stepOf(nia), "team", "p5 flow new: the Arena gate takes her to the Battle Arena: 'arena' -> 'team'")
	-- a team of 3: a fighter and two helpers (a 4th key is refused, 4.8)
	givePet(nia, STRONG[1], 1, 20)
	givePet(nia, WEAK[2], 1, 15)
	givePet(nia, WEAK[3], 1, 15)
	mark = K.logSize()
	Mock.FromClient(Kit.remote("BattleRequest"), nia, "TeamSet", 1, { STRONG[1], petId, WEAK[2], WEAK[3] })
	advance(0.6)
	T.check(#DataS.GetTeams(nia).Presets[1] ~= 4 and toasted(nia, "Teams have 3 pets", mark), "p5 flow new: a 4-pet team is refused ('Teams have 3 pets: a fighter and two helpers')",
		table.concat(toasts(nia, nil, mark), " | "))
	advance(1.2)
	-- bug batch 2 #18: her garden pet is busy gardening: a team with it is refused ("gardening")
	mark = K.logSize()
	Mock.FromClient(Kit.remote("BattleRequest"), nia, "TeamSet", 1, { STRONG[1], petId, WEAK[2] })
	advance(0.6)
	T.check(#DataS.GetTeams(nia).Presets[1] == 0 and toasted(nia, "gardening", mark), "p5 flow new: her garden pet cannot join the team ('gardening', bug batch 2 #18)",
		table.concat(toasts(nia, nil, mark), " | "))
	advance(1.2)
	Mock.FromClient(Kit.remote("BattleRequest"), nia, "TeamSet", 1, { STRONG[1], WEAK[2], WEAK[3] })
	advance(0.6)
	local team = DataS.GetTeams(nia)
	T.check(team.Slots == 3 and listText(team.Presets[1]) == listText({ STRONG[1], WEAK[2], WEAK[3] }), "p5 flow new: she saves her team of 3 (fighter " .. STRONG[1] .. " + two helpers)", listText(team.Presets[1]))
	waitStep(nia, "dungeon", 3)
	T.eq(stepOf(nia), "dungeon", "p5 flow new: the team completes 'team' -> 'dungeon'")
	local dinfo = Kit.dinfo()
	local st = tut(nia)
	T.check(st and st.Target and typeof(st.Target.Position) == "Vector3" and dinfo and K.planar(st.Target.Position, (dinfo.Pad or dinfo.PromptPart).Position) < 12,
		"p5 flow new: 'dungeon' points at the Dungeon portal (DungeonInfo.Pad)")
	-- Dungeon floor 1, solo, through the remote
	local tok0, gem0, cash0, xp0 = tokens(nia), gems(nia), cash(nia), totalXp(nia, STRONG[1])
	local dm = K.logSize()
	Kit.toPad(nia)
	Kit.dreq(nia, "Solo", 1)
	local run = Kit.runOf(nia)
	if T.check(run ~= nil and nia:GetAttribute("InBattle") == run.Id, "p5 flow new: DungeonRequest Solo 1 at the portal starts her run (InBattle = the run id)") then
		local rooms = Kit.clearRooms(run, { nia }, { remote = true, kit = true })
		T.check(rooms == 4 and run.State == "Treasure", "p5 flow new: her team of 3 clears all four rooms of floor 1 (" .. rooms .. ")", tostring(run.State))
		Kit.pickChest(nia, run, 2)
		Kit.pickChest(nia, run, 3)
		advance(BC.Dungeon.TreasureSeconds + 6)
		local loots = Kit.dstates(nia, dm, "Loot")
		local chests = Kit.dstates(nia, dm, "Chest")
		local ends = Kit.dstates(nia, dm, "End")
		local fc = BC.DungeonFirstClear(1)
		local chestTok = (chests[1] and chests[1].Kind == "Tokens") and chests[1].Amount or 0
		local chestCash = (chests[1] and chests[1].Kind == "Cash") and chests[1].Amount or 0
		T.check(#loots == 4 and #chests == 1, "p5 flow new: one Loot card per room and ONE chest (E at a second chest pays nothing)", #loots .. " loots, " .. #chests .. " chests")
		T.eq(tokens(nia) - tok0, sumLoot(loots, "Tokens") + fc.Tokens + chestTok, "p5 flow new: Tokens = the rooms' loot + the first clear (" .. fc.Tokens .. ") + the chest, each paid once")
		T.eq(gems(nia) - gem0, fc.Gems, "p5 flow new: ...the first clear's Gems (" .. fc.Gems .. ") once")
		T.eq(cash(nia) - cash0, sumLoot(loots, "Cash") + chestCash, "p5 flow new: ...Cash = the rooms' loot + the chest")
		T.check(totalXp(nia, STRONG[1]) > xp0, "p5 flow new: ...and her team pets got the rooms' XP")
		local e = ends[#ends]
		T.check(e and e.Cleared == true and e.FirstClear ~= nil and e.Unlocked == 2, "p5 flow new: the End card: Cleared, FirstClear, floor 2 unlocked")
		local d = DataS.GetDungeon(nia)
		T.check(d and d.Best == 1 and floorsExactly(d, 1) and d.Clears == 1 and d.Runs == 1, "p5 flow new: Dungeon { Best 1, Cleared {1}, Clears 1, Runs 1 }", dungeonText(d))
		T.check(nia:GetAttribute("InBattle") == nil and Kit.runOf(nia) == nil, "p5 flow new: ...she is back at the portal, out of the run")
		waitStep(nia, "raid", 3)
		T.eq(stepOf(nia), "raid", "p5 flow new: the floor-1 clear completes 'dungeon' (DungeonWon) -> 'raid'")
	end
	-- the Champion Ring: rounds 1-3 with the six controls
	local ring0 = DataS.GetRing(nia)
	local cashR, tokR = cash(nia), tokens(nia)
	toRing(X, nia)
	F.record = true
	local controls = nil
	local run2 = Kit.runRing(nia, 1, {
		stopAfterWins = 3,
		maxSeconds = 900,
		remote = true,
		tick = function(tr)
			if not controls and tr.fighter then
				F.recordUntil = Mock.Clock.now + 2
				controls = tryControls(X, nia, tr)
			end
		end,
	})
	F.record, F.recordUntil = nil, nil
	if T.check(run2.id ~= nil, "p5 flow new: at the Champion Ring portal BattleRequest 'Ring' starts round 1", tostring(run2.refused)) then
		local start = run2.starts[1]
		T.check(start and start.Mode == "Ring" and type(start.Team) == "table" and #start.Team.Bench == 2 and start.Team.Lives == 3,
			"p5 flow new: 'Start' carries Team { Fighter, Bench (2 helpers), Lives 3 }")
		controls = controls or {}
		for _, name in ipairs({ "Attack", "Element", "Dash", "Buff", "Swap", "Special" }) do
			T.check(controls[name] == true, "p5 flow new: the " .. name:upper() .. " control works in the ring (its event came back)")
		end
		T.check(#run2.wins >= 3, "p5 flow new: her team wins rounds 1, 2 and 3", #run2.wins .. " wins")
		local cashSum, tokSum, okEnds = 0, 0, true
		for i, m in ipairs(run2.wins) do
			local rw = m.Rewards
			if rw.Round ~= i or rw.Next ~= i + 1 then
				okEnds = false
			end
			cashSum, tokSum = cashSum + (rw.Cash or 0), tokSum + (rw.Tokens or 0)
		end
		T.check(okEnds and run2.nilSamples == 0, "p5 flow new: ...each won round's End carries Round / Next; no InBattle gap between rounds")
		T.eq(cash(nia) - cashR, cashSum, "p5 flow new: ...Cash paid exactly once per round")
		T.eq(tokens(nia) - tokR, tokSum, "p5 flow new: ...Tokens likewise")
		if X.BS.IsInBattle(nia) then
			Mock.FromClient(Kit.remote("BattleCommand"), nia, "Forfeit")
			advance(0.2)
			if X.BS.IsInBattle(nia) then
				X.BS.Forfeit(nia)
			end
		end
		advance(6)
		local ring = DataS.GetRing(nia)
		T.check(ring.Best >= 3 and ring.Runs == (ring0 and ring0.Runs or 0) + 1 and nia:GetAttribute("InBattle") == nil, "p5 flow new: Ring.Best >= 3, Runs + 1, she is out of the battle",
			"Best " .. tostring(ring.Best) .. " Runs " .. tostring(ring.Runs))
	end
	return true
end

-- 4. Prestige keeps the berries, the Garden and its pet
local function newPrestige(X, nia)
	local DataS, Ty, TC = X.DataS, X.Ty, X.TC
	local info = F.niaPlot and spots()[F.niaPlot]
	away(nia)
	DataS.AddBerries(nia, 777)
	advance(0.6)
	local b0 = berries(nia)
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
	T.check(TC.CanPrestige(home(nia)) == true, "p5 flow new: (stand-in for hours of play) her home is prestige-ready")
	local mark = K.logSize()
	Mock.FromClient(Kit.remote("HomeAction"), nia, "Prestige")
	advance(0.8)
	local h = home(nia)
	T.check(h.Prestige == 1 and (h.Stations.Garden or 0) == 1 and (h.Stations.Press1 or 0) == 0 and TC.GardenSlots(h) == 4 and toasted(nia, "Prestige 1!", mark),
		"p5 flow new: Prestige 1: the stations reset, the Pet Garden stays (Lv 1, 4 beds)")
	T.check(berries(nia) >= b0, "p5 flow new: ...her berries are kept (" .. b0 .. " before, the garden keeps adding)", tostring(berries(nia)))
	T.check(h.Garden[1] == WEAK[1] and Ty.IncomePerSecond(nia) > 0 and DataS.GetEvolution(nia, WEAK[1]) == 1, "p5 flow new: ...her evolved pet keeps its bed and keeps pooping Cloud Cash")
	advance(1.2)
	T.check(info and stationModel(info, "Garden") ~= nil and stationModel(info, "Kitchen") == nil, "p5 flow new: ...the Garden stands on the plot, the Food Machine is gone")
end

S.p5flow_new = scenario("p5flow_new", function(players)
	local X = ready("p5 flow new")
	if not X then
		return
	end
	Mock.DataStore.Data[storeKey(IDS.Nia)] = nil
	Mock.DataStore.Data[storeKey(IDS.Rex)] = nil
	local restoreOwner = becomeOwner(IDS.Nia)
	local ledger = scoopLedger(X.Ty)
	local okRun, errRun = pcall(function()
		local nia, rex = newArrive(X, players)
		if not (nia and nia.Parent and nia.Character) then
			return
		end
		if newHome(X, nia, rex, ledger) then
			newBattle(X, nia)
			newPrestige(X, nia)
		end
		X.DataS.Save(nia)
		advance(0.5)
		local rec = stored(IDS.Nia) or {}
		T.check(type(rec.Dungeon) == "table" and rec.Dungeon.Best == 1 and (rec.Berries or 0) > 0 and type(rec.Teams) == "table" and #rec.Teams.Presets[1] == 3,
			"p5 flow new: her save holds Dungeon, Berries and the 3-key team")
	end)
	ledger.stop()
	restoreOwner()
	if not okRun then
		error(errRun, 0)
	end
end)

----------------------------------------------------------------------------------------------------
-- p5flow_migrate: a Phase 4 save (Vic) and a Phase 3 save (Wes) on their first Phase 5 load
----------------------------------------------------------------------------------------------------
local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepCopy(x)
	end
	return out
end

local function sumLevels(stations)
	local n = 0
	for _, lv in pairs(stations) do
		n = n + (tonumber(lv) or 0)
	end
	return n
end

local function rosterOf(X)
	local ecos, combats = {}, {}
	for _, def in ipairs(X.PC.Pets) do
		if not def.EventOnly and def.Rarity ~= "Secret" and def.Rarity ~= "Mythic" then
			if def.Role == "Economy" and #ecos < 6 then
				ecos[#ecos + 1] = def.Id
			elseif def.Role == "Combat" and #combats < 4 then
				combats[#combats + 1] = def.Id
			end
		end
	end
	return ecos, combats
end

-- the Phase 4 save of 12.1: 4 plants + Collector + 6 decor + a 4-key team + TrialBest 15 + 2 Feasts + Easy / Medium wins
local function phase4Save(X, index, ecos, combats)
	local stations = { Garden = 6, Press1 = 8, Press2 = 5, Press3 = 3, Press4 = 2, Collector = 3, Kitchen = 2, Gym = 2, House = 3, Vault = 1,
		DecorLamps = 2, DecorFlowers = 3, DecorBanners = 1, DecorFence = 1, DecorFountain = 1, DecorPodium = 1 }
	local pets, discovered, levels = {}, {}, {}
	for _, id in ipairs(ecos) do
		pets[id], discovered[id] = 1, true
	end
	for _, id in ipairs(combats) do
		pets[id], discovered[id] = 1, true
	end
	levels[ecos[1]] = { Level = 22, Xp = 0 } -- ready to evolve
	levels[combats[1]] = { Level = 15, Xp = 0 }
	levels[combats[2]] = { Level = 19, Xp = X.TC.XpToNext(19) - 50 } -- 50 XP short of level 20
	levels[combats[4]] = { Level = 12, Xp = 7 } -- the 4th team key
	local garden = {}
	for i = 1, 6 do
		garden[i] = ecos[i]
	end
	local cleared = {}
	for i = 1, 15 do
		cleared[i] = true
	end
	local now = os.time()
	return {
		Version = 2, Tokens = 800, Cash = 2000, Gems = 50,
		Pets = pets, Equipped = { combats[1] }, Items = {},
		Stats = { Matches = 12, Wins = 9, TokensEarned = 4000, Spins = 20, BestTimes = { Easy = 95, Medium = 160 } },
		Discovered = discovered, IndexClaimed = {},
		Tutorial = { Step = #X.Steps.Steps + 1, Done = true, Gifted = true },
		SpotIndex = index,
		Home = { Level = sumLevels(stations), Prestige = 1, Stations = stations, Garden = garden, Gym = {}, CollectorCash = 500, LastSeen = now - 30, LegacySlots = 6, LegacyPrices = true },
		Food = { Feast = 2 },
		PetLevels = levels,
		PetGrowth = { [combats[4]] = { Physique = 2 } },
		Teams = { Presets = { { combats[1], combats[2], combats[3], combats[4] }, {}, {} }, Active = 1 },
		Battle = { Trophies = 40, TrialBest = 15, TrialCleared = cleared, Raids = 2, RaidBestDamage = 900, PvPWins = 3, PvPLosses = 1, EventPets = {} },
		Ring = { Best = 7, Runs = 3 },
		Migrations = { P4 = true },
		UpdatedAt = now - 3600,
	}
end

-- a Phase 3 save (no Migrations at all): P4 + P5 run in ONE load
local function phase3Save(X, ecos, combats)
	local now = os.time()
	return {
		Version = 2, Tokens = 333, Cash = 4444, Gems = 22,
		Pets = { [ecos[2]] = 2, [combats[3]] = 1 }, Equipped = { combats[3] }, Items = {},
		Stats = { Matches = 3, Wins = 2, TokensEarned = 900, Spins = 4, BestTimes = { Easy = 120 } },
		Discovered = { [ecos[2]] = true, [combats[3]] = true }, IndexClaimed = {},
		Tutorial = { Step = X.Steps.ChapterStart[3], Done = false, Gifted = true },
		Home = { Level = 9, Prestige = 0, Stations = { Garden = 3, Press1 = 4, Press2 = 2, Collector = 1, Kitchen = 1 }, Garden = { ecos[2] }, Gym = {}, CollectorCash = 0, LastSeen = now - 30 },
		Food = { Snack = 3 },
		PetLevels = { [ecos[2]] = { Level = 9, Xp = 3 }, [combats[3]] = { Level = 6, Xp = 0 } },
		Teams = { Presets = { { combats[3], ecos[2] } }, Active = 1 },
		Battle = { Trophies = 5, TrialBest = 7, TrialCleared = { true, true, true, true, true, true, true }, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
		UpdatedAt = now - 3600,
	}
end

local function migrateVic(X, players, ledger, ecos, combats)
	local DataS, Ty, TC = X.DataS, X.Ty, X.TC
	local index = freeIndex()
	local save = phase4Save(X, index, ecos, combats)
	local oldHome = deepCopy(save.Home)
	local expect = deepCopy(save.Home)
	TC.FoldLegacy(expect, true)
	Mock.DataStore.Data[storeKey(IDS.Vic)] = save
	local mark0 = K.logSize()
	local vic = join("Vic")
	players[#players + 1] = vic
	local rex = join("Rex")
	players[#players + 1] = rex
	advance(4)
	local h = home(vic)
	local nowHome = DataS.MigratedNow(vic, "P5Home")
	T.check(DataS.IsMigrated(vic, "P5Home") and DataS.IsMigrated(vic, "P5Dungeon") and type(nowHome) == "table" and nowHome.FirstTime == true,
		"p5 flow migrate: Vic's first Phase 5 load runs the one-time P5Home + P5Dungeon steps")
	-- the home: Home Level never down, one Berry Farm, the legacy magnet, decor credit
	T.check(h.Level >= oldHome.Level and TC.HomeLevelOf(h) >= oldHome.Level, "p5 flow migrate: Home Level " .. oldHome.Level .. " -> " .. tostring(h.Level) .. " (unchanged or up)")
	T.check(h.Stations.Press1 == expect.Stations.Press1 and h.Stations.Press1 >= 18 and h.Stations.Press2 == nil and h.Stations.Press3 == nil and h.Stations.Press4 == nil,
		"p5 flow migrate: the 4 plants (8 + 5 + 3 + 2) grew into ONE Berry Farm at Lv " .. tostring(h.Stations.Press1), tostring(h.Stations.Press1))
	T.check(h.Stations.Collector == nil and h.LegacyMagnet == 3 and h.LegacyMagnetStar == 1, "p5 flow migrate: the Coin Magnet Lv 3 folds into the Garden as LegacyMagnet 3 (this star)")
	T.check(h.Stations.DecorFence == 3 and h.Stations.DecorFountain == 2 and h.Stations.DecorPodium == 1 and h.DecorCredit == 3 and h.Stations.DecorLamps == nil and h.Stations.DecorFlowers == nil and h.Stations.DecorBanners == nil,
		"p5 flow migrate: 6 decor -> 3: Fence = max(Fence, Flowers, Banners), Fountain = max(Fountain, Lamps), DecorCredit 3 for the levels that did not fit",
		"Fence " .. tostring(h.Stations.DecorFence) .. " Fountain " .. tostring(h.Stations.DecorFountain) .. " credit " .. tostring(h.DecorCredit))
	T.check(h.Stations.Garden == 6 and h.Stations.Kitchen == 2 and h.Stations.Gym == 2 and h.Stations.House == 3 and h.Stations.Vault == 1 and h.LegacySlots == 6 and h.Prestige == 1,
		"p5 flow migrate: every other station, the 6 legacy beds and the star are untouched")
	-- the team: 3 keys, the 4th pet still owned with its level and growth
	local team = DataS.GetTeams(vic)
	T.check(team.Slots == 3 and listText(team.Presets[1]) == listText({ combats[1], combats[2], combats[3] }), "p5 flow migrate: his 4-key team keeps its first 3 keys", listText(team.Presets[1]))
	local lv4, xp4 = DataS.GetPetLevel(vic, combats[4])
	T.check(DataS.GetProfile(vic).Pets[combats[4]] == 1 and lv4 == 12 and xp4 == 7 and DataS.GetGrowth(vic, combats[4]).Physique == 2, "p5 flow migrate: ...the 4th pet stays owned (level 12, its rank)")
	-- the dungeon: TrialBest 15 -> floors 1-5
	local d = DataS.GetDungeon(vic)
	T.check(d and d.Best == 5 and floorsExactly(d, 5) and d.Clears == 5 and d.Runs == 0, "p5 flow migrate: TrialBest 15 -> Dungeon floors 1-5 cleared (Best 5, Clears 5, Runs 0)", dungeonText(d))
	-- the obby: his Easy + Medium wins open Hard
	local OL = X.OL
	T.eq(OL.HighestUnlocked(DataS.GetProfile(vic).Stats.BestTimes), 3, "p5 flow migrate: his Easy + Medium wins open Hard (no migration: ObbyLevels reads BestTimes)")
	local mark = K.logSize()
	Mock.FromClient(Kit.remote("ObbyPick"), vic, "Extreme")
	advance(0.4)
	T.check(vic:GetAttribute(config().Attr.ObbyLevel) ~= "Extreme" and toasted(vic, "Beat Hard to unlock Extreme", mark), "p5 flow migrate: ObbyPick('Extreme') is refused ('Beat Hard to unlock Extreme')")
	advance(0.6)
	Mock.FromClient(Kit.remote("ObbyPick"), vic, "Hard")
	advance(0.4)
	T.eq(vic:GetAttribute(config().Attr.ObbyLevel), "Hard", "p5 flow migrate: ObbyPick('Hard') is accepted")
	-- the food: 2 Feasts -> 12,800 berries, Food zeroed
	T.check(berries(vic) == 2 * TC.Berries.LegacyFood.Feast and DataS.GetFood(vic, "Feast") == 0, "p5 flow migrate: his 2 leftover Feasts became " .. (2 * TC.Berries.LegacyFood.Feast) .. " berries (Food zeroed)",
		tostring(berries(vic)))
	-- nothing else lost
	local prof = DataS.GetProfile(vic)
	T.check(DataS.GetCash(vic) == 2000 and DataS.GetGems(vic) == 50 and DataS.GetTokens(vic) == 800 and count(prof.Pets) == 10 and (DataS.GetPetLevel(vic, ecos[1])) == 22
		and DataS.GetRing(vic).Best == 7 and DataS.GetBattle(vic).Trophies == 40, "p5 flow migrate: Cash, Gems, Tokens, all 10 pets, levels, the Ring record and trophies are kept")
	-- the claim: the welcome toast once; the stations stand; the Welcome-back pile is scooped once
	mark = K.logSize()
	local got = claim(vic, index)
	local info = got and spots()[got]
	if not T.check(info ~= nil, "p5 flow migrate: Vic claims his home") then
		return nil
	end
	away(vic)
	advance(1.5)
	T.eq(#toasts(vic, "Your home got simpler!", mark), 1, "p5 flow migrate: one 'Your home got simpler!' toast on the claim")
	local wrong = {}
	for id, lv in pairs(h.Stations) do
		local m = stationModel(info, id)
		if not m or m:GetAttribute("Level") ~= lv then
			wrong[#wrong + 1] = id
		end
	end
	T.check(#wrong == 0 and stationModel(info, "Collector") == nil and stationModel(info, "Press2") == nil, "p5 flow migrate: every Phase 5 station stands at its level on the plot, no old one", table.concat(wrong, ","))
	T.check(tostring(info.Folder:GetAttribute("CoinDrops")):find("W=", 1, true) ~= nil, "p5 flow migrate: his $500 of old Collector Cash waits as the Welcome-back heap (CoinDrops 'W=')",
		tostring(info.Folder:GetAttribute("CoinDrops")))
	local piles = Ty.Piles(vic)
	local w = piles and piles.W
	if w and typeof(w.Pos) == "Vector3" then
		local rc = cash(rex)
		standAt(rex, w.Pos)
		advance(0.6)
		away(rex)
		T.check(cash(rex) == rc and ledger.of(rex) == 0, "p5 flow migrate: Rex walking over Vic's heap scoops nothing")
		local c0, l0 = cash(vic), ledger.of(vic)
		standAt(vic, w.Pos)
		advance(0.4)
		away(vic)
		local gained = cash(vic) - c0
		T.check(gained >= 500 and gained == ledger.of(vic) - l0, "p5 flow migrate: walking over it scoops it once (+$" .. gained .. ")")
		local c2, l2 = cash(vic), ledger.of(vic)
		standAt(vic, w.Pos)
		advance(0.4)
		away(vic)
		T.check(cash(vic) - c2 == ledger.of(vic) - l2 and cash(vic) - c2 < 500, "p5 flow migrate: ...a second walk finds no old Cash again")
	end
	-- the Feasts, now berries, feed his old 19: "Ready to evolve!"; no Cash
	local b0, c1 = berries(vic), cash(vic)
	mark = K.logSize()
	for _ = 1, 4 do
		if (DataS.GetPetLevel(vic, combats[2])) >= 20 then
			break
		end
		Mock.FromClient(Kit.remote("PetCare"), vic, "Feed", combats[2])
		advance(0.5)
	end
	T.check((DataS.GetPetLevel(vic, combats[2])) >= 20 and berries(vic) < b0 and cash(vic) == c1, "p5 flow migrate: Feed spends the berries (not Cash) and his level-19 pet reaches Lv 20",
		tostring((DataS.GetPetLevel(vic, combats[2]))) .. " / " .. b0 .. " -> " .. berries(vic))
	T.check(toasted(vic, "Ready to evolve!", mark), "p5 flow migrate: ...'Ready to evolve!'", table.concat(toasts(vic, nil, mark), " | "))
	local inc0 = Ty.IncomePerSecond(vic)
	Mock.FromClient(Kit.remote("PetCare"), vic, "Evolve", ecos[1])
	advance(1.2)
	T.check(DataS.GetEvolution(vic, ecos[1]) == 1 and Ty.IncomePerSecond(vic) > inc0, "p5 flow migrate: his level-22 garden pet evolves (stage 1, more Cloud Cash)")
	-- the dungeon at the portal: floor 7 locked, floor 6 open for a party
	Kit.toPad(vic)
	mark = K.logSize()
	Kit.dreq(vic, "Solo", 7)
	T.check(Kit.runOf(vic) == nil and toasted(vic, "Clear floor 6 first", mark), "p5 flow migrate: floor 7 is locked ('Clear floor 6 first')")
	advance(1.2)
	Kit.dreq(vic, "Create", 6)
	local party = X.DGS.GetParty(vic)
	T.check(party ~= nil and party.Floor == 6, "p5 flow migrate: a party on floor 6 is open to him (his migrated floors)")
	Kit.dreq(vic, "Leave")
	away(vic)
	return vic
end

local function migrateWes(X, players, ecos, combats)
	local DataS, TC = X.DataS, X.TC
	local save = phase3Save(X, ecos, combats)
	Mock.DataStore.Data[storeKey(IDS.Wes)] = save
	local wes = join("Wes")
	players[#players + 1] = wes
	advance(3)
	T.check(DataS.IsMigrated(wes, "P4") and DataS.IsMigrated(wes, "P5Home") and DataS.IsMigrated(wes, "P5Dungeon"), "p5 flow migrate: Wes's Phase 3 save runs P4 + P5Home + P5Dungeon in one load")
	local h = home(wes)
	T.check(h.Level >= 9 and h.Stations.Press1 >= 6 and h.Stations.Press2 == nil and h.Stations.Collector == nil and h.LegacyMagnet == 1, "p5 flow migrate: ...his plants fold into the Farm (Lv " .. tostring(h.Stations.Press1) .. "), the Collector into LegacyMagnet 1, Home Level not down",
		tostring(h.Level))
	local d = DataS.GetDungeon(wes)
	T.check(d and d.Best == 2 and floorsExactly(d, 2), "p5 flow migrate: ...TrialBest 7 -> floors 1-2", dungeonText(d))
	T.check(berries(wes) == 3 * TC.Berries.LegacyFood.Snack and DataS.GetFood(wes, "Snack") == 0, "p5 flow migrate: ...3 Snacks -> " .. (3 * TC.Berries.LegacyFood.Snack) .. " berries", tostring(berries(wes)))
	local prof = DataS.GetProfile(wes)
	T.check(DataS.GetCash(wes) == 4444 and DataS.GetGems(wes) == 22 and DataS.GetTokens(wes) == 333 and prof.Pets[ecos[2]] == 2 and prof.Pets[combats[3]] == 1
		and (DataS.GetPetLevel(wes, ecos[2])) == 9 and DataS.GetTeams(wes).Slots == 3 and listText(DataS.GetTeams(wes).Presets[1]) == listText({ combats[3], ecos[2] }),
		"p5 flow migrate: ...nothing lost: Cash, Gems, Tokens, both pets (2 copies), levels, his 2-pet team")
	leave(wes)
	advance(1)
	local rec = stored(IDS.Wes) or {}
	T.check(type(rec.Migrations) == "table" and rec.Migrations.P4 and rec.Migrations.P5Home and rec.Migrations.P5Dungeon and type(rec.Dungeon) == "table" and rec.Dungeon.Best == 2 and rec.Berries == 600
		and (rec.Food == nil or (rec.Food.Snack or 0) == 0), "p5 flow migrate: ...his save is a Phase 5 save (markers, Dungeon, Berries, no Snacks)")
end

S.p5flow_migrate = scenario("p5flow_migrate", function(players)
	local X = ready("p5 flow migrate")
	if not X then
		return
	end
	local ecos, combats = rosterOf(X)
	if not T.check(#ecos == 6 and #combats == 4, "p5 flow migrate: (precondition) six Economy and four Combat pets in the catalog") then
		return
	end
	local ledger = scoopLedger(X.Ty)
	local okRun, errRun = pcall(function()
		migrateVic(X, players, ledger, ecos, combats)
		migrateWes(X, players, ecos, combats)
	end)
	ledger.stop()
	if not okRun then
		error(errRun, 0)
	end
end)
----------------------------------------------------------------------------------------------------
-- p5flow_dungeon: three players in the Dungeon
----------------------------------------------------------------------------------------------------
-- a fresh player with a team of 3 (`pets` at `lv`) set through the BattleRequest remote
local function fighterJoin(name, pets, lv)
	Mock.DataStore.Data[storeKey(IDS[name])] = nil
	local p = join(name)
	for _, id in ipairs(pets) do
		givePet(p, id, 1, lv)
	end
	advance(0.3)
	Mock.FromClient(Kit.remote("BattleRequest"), p, "TeamSet", 1, pets)
	advance(0.6)
	return p
end

local function wallet(p)
	return { cash = cash(p), tokens = tokens(p), gems = gems(p), mark = K.logSize() }
end

-- what one member got from one run: Loot cards, the chest, the End card, and the wallet deltas
local function runTake(p, w)
	local loots, lossXp = {}, 0
	for _, l in ipairs(Kit.dstates(p, w.mark, "Loot")) do
		if l.Loss then
			lossXp = lossXp + (l.Xp or 0)
		else
			loots[#loots + 1] = l
		end
	end
	local chests = Kit.dstates(p, w.mark, "Chest")
	local ends = Kit.dstates(p, w.mark, "End")
	local chestTok, chestCash, chestGems = 0, 0, 0
	for _, c in ipairs(chests) do
		if c.Kind == "Tokens" then
			chestTok = chestTok + c.Amount
		elseif c.Kind == "Cash" then
			chestCash = chestCash + c.Amount
		elseif c.Kind == "Gems" then
			chestGems = chestGems + c.Amount
		end
	end
	return {
		loots = loots, lossXp = lossXp, chests = chests, endMsg = ends[#ends], ends = #ends,
		dTok = tokens(p) - w.tokens, dCash = cash(p) - w.cash, dGems = gems(p) - w.gems,
		chestTok = chestTok, chestCash = chestCash, chestGems = chestGems,
	}
end

-- every member's wallet change = their loot + (first clear) + their chest, each paid once
local function checkPaidOnce(label, p, take, fc)
	local fcTok = fc and fc.Tokens or 0
	local fcGems = fc and fc.Gems or 0
	T.eq(take.dTok, sumLoot(take.loots, "Tokens") + fcTok + take.chestTok, label .. ": " .. p.Name .. "'s Tokens = loot + first clear + chest (once each)")
	T.eq(take.dCash, sumLoot(take.loots, "Cash") + take.chestCash, label .. ": " .. p.Name .. "'s Cash = loot + chest (once each)")
	T.eq(take.dGems, fcGems + take.chestGems, label .. ": " .. p.Name .. "'s Gems = the first clear's (once)")
	T.check(#take.chests == 1 and take.ends == 1, label .. ": " .. p.Name .. " opened ONE chest and got ONE End card", #take.chests .. " chests, " .. take.ends .. " ends")
end

local function partyRun(leader, members, floorIndex)
	Kit.toPad(leader)
	Kit.dreq(leader, "Create", floorIndex)
	for _, m in ipairs(members) do
		if m ~= leader then
			Kit.toPad(m, 2, 0)
			Kit.dreq(m, "Join", leader.UserId)
			Kit.dreq(m, "Ready", true)
			advance(0.4)
		end
	end
	Kit.dreq(leader, "Start")
	advance(6)
	return Kit.runOf(leader)
end

-- (bug batch 2 #14) every member picks ONE chest (member i the chest i), then tries the next one too
local function finishTreasure(run, members, D)
	for i, m in ipairs(members) do
		if Kit.runOf(m) == run then
			Kit.pickChest(m, run, i)
			Kit.pickChest(m, run, i % 4 + 1)
		end
	end
	advance(D.TreasureSeconds + 6)
end

local function dungeonParty(X, ada, bea, cal)
	local DataS, BC = X.DataS, X.BC
	local D = BC.Dungeon
	local cleared = {}
	local conn = X.DGS.FloorCleared:Connect(function(player, f)
		cleared[#cleared + 1] = tostring(player.Name) .. ":" .. tostring(f)
	end)
	-- floor 1: a party of 3
	local w = { [ada] = wallet(ada), [bea] = wallet(bea), [cal] = wallet(cal) }
	local run = partyRun(ada, { ada, bea, cal }, 1)
	if T.check(run ~= nil and count(run.Members) == 3 and Kit.runOf(bea) == run and Kit.runOf(cal) == run, "p5 flow dungeon: Ada's party of 3 starts floor 1 (Create / Join / Ready / Start)") then
		local rooms = Kit.clearRooms(run, { ada, bea, cal }, { remote = true })
		T.check(rooms == 4 and run.State == "Treasure", "p5 flow dungeon: the party clears floor 1 (" .. rooms .. " rooms)", tostring(run.State))
		finishTreasure(run, { ada, bea, cal }, D)
		for _, p in ipairs({ ada, bea, cal }) do
			local take = runTake(p, w[p])
			T.check(#take.loots == 4, "p5 flow dungeon: floor 1: " .. p.Name .. " got one Loot card per room (4)", tostring(#take.loots))
			checkPaidOnce("p5 flow dungeon: floor 1", p, take, BC.DungeonFirstClear(1))
			local d = DataS.GetDungeon(p)
			T.check(d and d.Best == 1 and floorsExactly(d, 1) and d.Clears == 1 and d.Runs == 1 and p:GetAttribute("InBattle") == nil, "p5 flow dungeon: " .. p.Name .. "'s record { Best 1, Cleared {1}, Clears 1, Runs 1 }", dungeonText(d))
		end
		table.sort(cleared)
		T.eq(table.concat(cleared, ","), "Ada:1,Bea:1,Cal:1", "p5 flow dungeon: FloorCleared fired once per member")
	end
	-- floor 2 under Double Rewards; Cal joins late (after room 1)
	X.BS.SetDoubleRewards(true, 900)
	advance(1.2)
	w = { [ada] = wallet(ada), [bea] = wallet(bea), [cal] = wallet(cal) }
	cleared = {}
	local run2 = partyRun(ada, { ada, bea }, 2)
	if T.check(run2 ~= nil and count(run2.Members) == 2, "p5 flow dungeon: Ada + Bea start floor 2 (Double Rewards on)") then
		local joined = false
		local rooms = Kit.clearRooms(run2, { ada, bea, cal }, {
			remote = true,
			onCorridor = function(room)
				if room == 2 and not joined then
					Kit.toPad(cal)
					local mk = K.logSize()
					Kit.dreq(cal, "Join", ada.UserId)
					advance(0.6)
					joined = Kit.runOf(cal) == run2
					T.check(joined, "p5 flow dungeon: Cal joins Ada's run late, in the corridor to room 2", table.concat(toasts(cal, nil, mk), " | "))
				end
			end,
		})
		T.check(rooms == 4 and run2.State == "Treasure", "p5 flow dungeon: floor 2 cleared (" .. rooms .. " rooms)", tostring(run2.State))
		finishTreasure(run2, { ada, bea, cal }, D)
		local fc2 = BC.DungeonFirstClear(2)
		for _, p in ipairs({ ada, bea, cal }) do
			local take = runTake(p, w[p])
			local want = p == cal and 3 or 4
			T.check(#take.loots == want, "p5 flow dungeon: floor 2: " .. p.Name .. " got " .. want .. " Loot cards" .. (p == cal and " (the rooms after his late join only)" or ""), tostring(#take.loots))
			checkPaidOnce("p5 flow dungeon: floor 2", p, take, fc2)
			local boss = nil
			for _, l in ipairs(take.loots) do
				if l.Room == 4 then
					boss = l
				end
			end
			local normal = BC.DungeonRewards(2, 4, 4, 0, false)
			local double = BC.DungeonRewards(2, 4, 4, 0, true)
			T.check(boss ~= nil and boss.Tokens == double.Tokens and double.Tokens == 2 * normal.Tokens and boss.Xp == normal.Xp,
				"p5 flow dungeon: " .. p.Name .. "'s boss-room loot under Double Rewards: Tokens x2 (" .. tostring(double.Tokens) .. "), XP not doubled", boss and (tostring(boss.Tokens) .. " / " .. tostring(boss.Xp)) or "no boss loot")
			local d = DataS.GetDungeon(p)
			T.check(d and d.Best == 2 and floorsExactly(d, 2) and d.Clears == 2 and d.Runs == 2, "p5 flow dungeon: " .. p.Name .. "'s record { Best 2, Cleared {1, 2}, Clears 2, Runs 2 }", dungeonText(d))
		end
	end
	X.BS.SetDoubleRewards(false)
	conn:Disconnect()
end

-- Bea, solo on floor 4 with one level-1 pet, standing still: the wipe pays the loss third only
local function dungeonWipe(X, bea)
	local DataS, BC = X.DataS, X.BC
	local okM = DataS.MutateDungeon(bea, function(d)
		d.Cleared[3] = true
		d.Best = math.max(d.Best, 3)
	end)
	T.check(okM == true, "p5 flow dungeon: (stand-in for floor 3) MutateDungeon marks Bea's floor 3 cleared")
	givePet(bea, WEAK[3], 1, 1)
	advance(0.3)
	Mock.FromClient(Kit.remote("BattleRequest"), bea, "TeamSet", 1, { WEAK[3] })
	advance(0.6)
	local before = DataS.GetDungeon(bea)
	local w = wallet(bea)
	local xp0 = totalXp(bea, WEAK[3])
	Kit.toPad(bea)
	Kit.dreq(bea, "Solo", 4)
	local run = Kit.runOf(bea)
	if not T.check(run ~= nil and run.Floor == 4, "p5 flow dungeon: Bea starts floor 4 solo (floor 3 cleared)") then
		return
	end
	local rooms = Kit.clearRooms(run, { bea }, { passive = true, roomSeconds = 220 })
	advance(6)
	local take = runTake(bea, w)
	local e = take.endMsg
	T.check(rooms == 0 and e and e.Cleared == false and (e.Reason == "Wipe" or e.Reason == "Timeout") and e.Room == 1, "p5 flow dungeon: her level-1 pet, standing still, is wiped in room 1 (End Reason Wipe / Timeout)",
		e and tostring(e.Reason) or "no End")
	T.check(#take.loots == 0 and take.dTok == 0 and take.dCash == 0 and take.dGems == 0, "p5 flow dungeon: ...no loot, Tokens, Cash or Gems for a lost room")
	T.check(totalXp(bea, WEAK[3]) - xp0 == take.lossXp, "p5 flow dungeon: ...at most the loss third of the room's XP (only for a real loss >= 20 s), paid once as its card says", tostring(take.lossXp))
	local d = DataS.GetDungeon(bea)
	T.check(d and d.Best == 3 and d.Cleared[4] == nil and d.Clears == before.Clears and d.Runs == before.Runs + 1 and bea:GetAttribute("InBattle") == nil and Kit.runOf(bea) == nil,
		"p5 flow dungeon: ...no first clear, Runs + 1, she is back out of the run", dungeonText(d))
end

S.p5flow_dungeon = scenario("p5flow_dungeon", function(players)
	local X = ready("p5 flow dungeon")
	if not X then
		return
	end
	local restoreOwner = becomeOwner(IDS.Ada)
	local okRun, errRun = pcall(function()
		-- (level-25 Commons, floors 1-2 are real fights since the team balance: every member must deal >= 5% of the party's
		-- damage in a room to be paid for it, 5.2)
		local ada = fighterJoin("Ada", WEAK, 25)
		local bea = fighterJoin("Bea", WEAK, 25)
		local cal = fighterJoin("Cal", WEAK, 25)
		players[#players + 1] = ada
		players[#players + 1] = bea
		players[#players + 1] = cal
		dungeonParty(X, ada, bea, cal)
		dungeonWipe(X, bea)
		-- a rejoin keeps Dungeon
		local d0 = X.DataS.GetDungeon(ada)
		leave(ada)
		advance(1)
		local rec = stored(IDS.Ada) or {}
		T.check(type(rec.Dungeon) == "table" and rec.Dungeon.Best == d0.Best and rec.Dungeon.Runs == d0.Runs and rec.Dungeon.Clears == d0.Clears, "p5 flow dungeon: Ada's leave save holds her Dungeon record")
		ada = join("Ada")
		players[#players + 1] = ada
		advance(1)
		local d1 = X.DataS.GetDungeon(ada)
		T.check(d1 and dungeonText(d1) == dungeonText(d0), "p5 flow dungeon: ...and her rejoin reads it back unchanged", dungeonText(d1))
		-- the developer /reset wipes Dungeon and berries, keeps Settings
		X.DataS.AddBerries(ada, 250)
		X.DataS.SetSetting(ada, "Music", 3)
		advance(0.6)
		chat(ada, "/reset")
		advance(1)
		local d2 = X.DataS.GetDungeon(ada)
		T.check(d2 and (d2.Best or 0) == 0 and floorsExactly(d2, 0) and (d2.Runs or 0) == 0 and berries(ada) == 0, "p5 flow dungeon: the developer /reset wipes Dungeon and berries", dungeonText(d2))
		T.eq(X.DataS.GetSettings(ada).Music, 3, "p5 flow dungeon: ...and keeps the settings")
		givePet(ada, WEAK[1], 1, 5)
		Mock.FromClient(Kit.remote("BattleRequest"), ada, "TeamSet", 1, { WEAK[1] })
		advance(1.2)
		Kit.toPad(ada)
		local mk = K.logSize()
		Kit.dreq(ada, "Solo", 2)
		T.check(Kit.runOf(ada) == nil and toasted(ada, "Clear floor 1 first", mk), "p5 flow dungeon: ...floor 2 is locked again after the reset")
	end)
	restoreOwner()
	if not okRun then
		error(errRun, 0)
	end
end)
----------------------------------------------------------------------------------------------------
-- p5flow_rejoin: a disconnect mid-run and mid-ring-run, then rejoins
----------------------------------------------------------------------------------------------------
local function pocketCount()
	local pockets = workspace:FindFirstChild("BattlePockets")
	return pockets and #pockets:GetChildren() or 0
end

local function rejoinDungeon(X, eve, fin, players)
	local DataS, BC = X.DataS, X.BC
	local D = BC.Dungeon
	local we, wf = wallet(eve), wallet(fin)
	local run = partyRun(eve, { eve, fin }, 1)
	if not T.check(run ~= nil and count(run.Members) == 2, "p5 flow rejoin: Eve + Fin start floor 1") then
		return fin
	end
	local dropped = false
	local rooms = Kit.clearRooms(run, { eve, fin }, {
		remote = true,
		onRoom = function(room)
			if room == 2 and not dropped then
				-- Fin's connection drops in the middle of room 2's fight
				advance(1.0)
				dropped = true
				Mock.RemovePlayer(fin)
				advance(1.5)
			end
		end,
	})
	T.check(dropped and rooms == 4 and run.State == "Treasure" and run.Members[fin.UserId] and run.Members[fin.UserId].Left == true,
		"p5 flow rejoin: Fin disconnects in room 2: the run goes on and Eve clears floor 1 alone", rooms .. " rooms, " .. tostring(run.State))
	finishTreasure(run, { eve }, D)
	local take = runTake(eve, we)
	T.check(#take.loots == 4, "p5 flow rejoin: Eve got her 4 Loot cards", tostring(#take.loots))
	checkPaidOnce("p5 flow rejoin", eve, take, BC.DungeonFirstClear(1))
	-- Fin's leave save: room 1's loot (paid before he dropped), the run counted, no clear
	local finLoots = Kit.dstates(fin, wf.mark, "Loot")
	local rec = stored(IDS.Fin) or {}
	local rd = type(rec.Dungeon) == "table" and rec.Dungeon or {}
	T.check(#finLoots == 1 and rec.Tokens == wf.tokens + sumLoot(finLoots, "Tokens") and (rd.Runs or 0) == 1 and (rd.Clears or 0) == 0 and not (rd.Cleared and rd.Cleared[1]),
		"p5 flow rejoin: Fin's leave save holds room 1's loot (once), Runs 1, no clear", "loots " .. #finLoots .. " tokens " .. tostring(rec.Tokens) .. " " .. dungeonText(rd))
	-- he rejoins: no run, nothing paid twice
	fin = join("Fin")
	players[#players + 1] = fin
	advance(1)
	local d = DataS.GetDungeon(fin)
	T.check(Kit.runOf(fin) == nil and X.DGS.GetRun(fin) == nil and fin:GetAttribute("InBattle") == nil, "p5 flow rejoin: Fin rejoins outside any run (no InBattle)")
	T.check(tokens(fin) == rec.Tokens and d and d.Runs == 1 and d.Clears == 0, "p5 flow rejoin: ...his tokens and Dungeon record are the leave save's (nothing paid twice)", dungeonText(d))
	return fin
end

local function rejoinRing(X, eve, players)
	local DataS = X.DataS
	DataS.AddBerries(eve, 321)
	advance(0.8)
	local keepBerries = berries(eve)
	local keepTeam = listText(DataS.GetTeams(eve).Presets[1])
	local runs0 = DataS.GetRing(eve).Runs or 0
	local pockets0 = pocketCount()
	T.check(claim(eve) ~= nil, "p5 flow rejoin: (setup) Eve claims a home (the Ring pays seconds of her garden)")
	toRing(X, eve)
	local out = Kit.runRing(eve, 1, { stopAfterWins = 1, maxSeconds = 300, remote = true })
	T.check(out.id ~= nil and #out.wins >= 1, "p5 flow rejoin: Eve wins ring round 1", tostring(out.refused))
	local live = K.waitFor(function()
		return X.BS.IsInBattle(eve) and type(eve:GetAttribute("InBattle")) == "string"
	end, 15)
	T.check(live and pocketCount() >= pockets0 + 1, "p5 flow rejoin: ...round 2 runs in its pocket")
	Mock.RemovePlayer(eve)
	advance(2)
	local rec = stored(IDS.Eve) or {}
	local rr = type(rec.Ring) == "table" and rec.Ring or {}
	T.check((rr.Runs or 0) == runs0 + 1 and (rr.Best or 0) >= 1, "p5 flow rejoin: Eve disconnects mid-round 2: Ring.Runs + 1 and Best >= 1 in her leave save", tostring(rr.Runs))
	K.waitFor(function()
		return pocketCount() == pockets0
	end, 10)
	T.eq(pocketCount(), pockets0, "p5 flow rejoin: ...her pocket is freed")
	eve = join("Eve")
	players[#players + 1] = eve
	advance(1)
	T.check(not X.BS.IsInBattle(eve) and eve:GetAttribute("InBattle") == nil and (DataS.GetRing(eve).Runs or 0) == runs0 + 1, "p5 flow rejoin: she rejoins out of any battle; Runs counted once")
	T.check(berries(eve) == keepBerries and listText(DataS.GetTeams(eve).Presets[1]) == keepTeam and DataS.GetTeams(eve).Slots == 3, "p5 flow rejoin: ...her berries (" .. keepBerries .. ") and her team of 3 come back",
		tostring(berries(eve)))
end

S.p5flow_rejoin = scenario("p5flow_rejoin", function(players)
	local X = ready("p5 flow rejoin")
	if not X then
		return
	end
	local eve = fighterJoin("Eve", WEAK, 25)
	local fin = fighterJoin("Fin", WEAK, 25)
	players[#players + 1] = eve
	players[#players + 1] = fin
	rejoinDungeon(X, eve, fin, players)
	rejoinRing(X, eve, players)
end)

----------------------------------------------------------------------------------------------------
-- p5flow_merge: two servers, then the Phase 4 fixture as an old server
----------------------------------------------------------------------------------------------------
local function hookedSignals()
	local out = { game:GetService("Players").PlayerRemoving }
	local folder = K.remoteFolder and K.remoteFolder()
	for _, name in ipairs({ "RequestProfile", "SettingsSet" }) do
		local remote = folder and folder:FindFirstChild(name)
		if remote then
			out[#out + 1] = remote.OnServerEvent
		end
	end
	return out
end
local function connectionMarks()
	local marks = {}
	for _, sig in ipairs(hookedSignals()) do
		local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
		marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
	end
	return marks
end
local function dropHooks(marks)
	local clean = true
	for _, m in ipairs(marks) do
		if m.conns then
			for i = #m.conns, m.n + 1, -1 do
				local conn = m.conns[i]
				if type(conn) == "table" and conn.Disconnect then
					conn:Disconnect()
				end
			end
			clean = clean and #m.conns == m.n
		else
			clean = false
		end
	end
	return clean
end
-- a module as "another server" on the same mock store: a clone of the live DataService, or the frozen Phase 4 one
local function otherServer(name, source)
	local inst = K.moduleInstance("server/Services/DataService")
	if not inst then
		return nil, "no DataService"
	end
	local marks = connectionMarks()
	local mod2
	if source then
		mod2 = Instance.new("ModuleScript")
		-- HUD cleanup: a frozen release read Config.Items.MaxCarry (5), which this build's Config no longer has (that
		-- server shipped its own Config): the copy loaded here reads the old value instead (the file stays untouched)
		mod2.Source = (string.gsub(source, "Config%.Items%.MaxCarry", "5"))
	else
		mod2 = inst:Clone()
	end
	mod2.Name = name
	mod2.Parent = inst.Parent
	local ok, module = pcall(require, mod2)
	if not ok or type(module) ~= "table" then
		mod2:Destroy()
		dropHooks(marks)
		return nil, tostring(module)
	end
	return module, function()
		mod2:Destroy()
		return dropHooks(marks)
	end
end
local function readFixture(fileName)
	for _, candidate in ipairs({ "tools/fixtures/" .. fileName, "fixtures/" .. fileName, "../tools/fixtures/" .. fileName, "nimbus-climb/tools/fixtures/" .. fileName }) do
		local fh = io.open(candidate, "r")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
		end
	end
	return nil
end

local function mergeTwoServers(X, gus, ecos, combats)
	local DataS = X.DataS
	local B, releaseB = otherServer("DataServiceFlowMergeB")
	if not T.check(B ~= nil, "p5 flow merge: a second DataService copy loads as 'server B'", tostring(releaseB)) then
		return
	end
	local okRun, errRun = pcall(function()
		B.Load(gus)
		local dA, dB = DataS.GetDungeon(gus), B.GetDungeon(gus)
		T.check(dA and dB and dA.Clears == 3 and dB.Clears == 3 and dA.Best == 3 and dB.Best == 3, "p5 flow merge: both servers migrated his unmigrated save (TrialBest 9 -> Best 3, Clears 3 each)",
			dungeonText(dA) .. " / " .. dungeonText(dB))
		local base = DataS.GetBerries(gus)
		T.check(base == B.GetBerries(gus), "p5 flow merge: both converted his Snack into the same berries (" .. tostring(base) .. ")")
		-- B: +100 berries, the first clear of floor 4, Music 2, a team; it saves first
		B.AddBerries(gus, 100)
		local okB, firstB = B.MutateDungeon(gus, function(d)
			d.Cleared[4] = true
			d.Clears = d.Clears + 1
			d.Runs = d.Runs + 1
		end)
		B.SetSetting(gus, "Music", 2)
		-- (bug batch 2 #18: his eco pets all work in the Garden, so the team is three Combat pets)
		local okT = B.SetTeam(gus, 1, { combats[1], combats[2], combats[3] })
		T.check(okB and firstB and okT and B.Save(gus) == true, "p5 flow merge: server B clears floor 4 first, adds 100 berries, sets Music 2 and a team, and saves")
		-- A (this server, live): +50 berries, the SAME first clear before it read B's save, Music 9
		DataS.AddBerries(gus, 50)
		local okA, firstA = DataS.MutateDungeon(gus, function(d)
			d.Cleared[4] = true
			d.Clears = d.Clears + 1
			d.Runs = d.Runs + 1
		end)
		DataS.SetSetting(gus, "Music", 9)
		T.check(okA and firstA and DataS.Save(gus) == true, "p5 flow merge: server A clears floor 4 too (first there as well) and saves")
		local rec = stored(IDS.Gus) or {}
		local sd = type(rec.Dungeon) == "table" and rec.Dungeon or {}
		T.check(floorsExactly(sd, 4) and sd.Best == 4, "p5 flow merge: Cleared is the union {1..4}: the first clear made on both servers lands ONCE in Cleared", dungeonText(sd))
		T.check(sd.Clears == 5 and sd.Runs == 2, "p5 flow merge: Clears = 3 migrated (not 6: two migrations do not double it) + the two real clears; Runs 2", dungeonText(sd))
		T.eq(rec.Berries, base + 150, "p5 flow merge: berries add up as deltas (" .. tostring(base) .. " + 100 + 50), the converted Snack counted once")
		T.check(type(rec.Settings) == "table" and rec.Settings.Music == 9, "p5 flow merge: Settings: the last saving session wins (Music 9)")
		local preset = type(rec.Teams) == "table" and type(rec.Teams.Presets) == "table" and rec.Teams.Presets[1] or {}
		local owned = true
		for _, key in ipairs(preset) do
			if not (rec.Pets and rec.Pets[key]) then
				owned = false
			end
		end
		T.check(#preset >= 1 and #preset <= 3 and owned, "p5 flow merge: the stored team has at most 3 keys, every one owned", listText(preset))
		advance(0.3)
		local live = DataS.GetDungeon(gus)
		T.check(live and live.Clears == 5 and live.Best == 4 and floorsExactly(live, 4), "p5 flow merge: the live session adopts the merged Dungeon record", dungeonText(live))
		T.eq(DataS.GetBerries(gus), rec.Berries, "p5 flow merge: ...and the stored berries")
	end)
	T.check(releaseB() == true, "p5 flow merge: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
end

local function mergeRollout(X, gus, combats, ecos)
	local DataS = X.DataS
	local src = readFixture("DataService_phase4.lua")
	if not T.check(src ~= nil and #src > 1000, "p5 flow merge: (precondition) tools/fixtures/DataService_phase4.lua is readable") then
		return
	end
	local P4DS, release = otherServer("DataServiceFlowPhase4", src)
	if not T.check(P4DS ~= nil and type(P4DS.Load) == "function", "p5 flow merge: the frozen Phase 4 DataService loads as an old server", tostring(release)) then
		return
	end
	local okRun, errRun = pcall(function()
		local keep = { Berries = DataS.GetBerries(gus), Dungeon = dungeonText(DataS.GetDungeon(gus)), Music = DataS.GetSettings(gus).Music, Tokens = DataS.GetTokens(gus) }
		P4DS.Load(gus)
		P4DS.AddTokens(gus, 5)
		P4DS.SetTeam(gus, 1, { combats[1], combats[2], combats[3], ecos[1] })
		P4DS.AddFood(gus, "Snack", 1)
		T.eq(P4DS.Save(gus), true, "p5 flow merge: the Phase 4 server plays (tokens, a 4-key team, a Snack) and saves his Phase 5 profile")
		local rec = stored(IDS.Gus) or {}
		T.check(rec.Berries == keep.Berries and type(rec.Dungeon) == "table" and type(rec.Settings) == "table" and rec.Settings.Music == keep.Music and rec.Migrations.P5Home and rec.Migrations.P5Dungeon,
			"p5 flow merge: ...Berries, Dungeon, Settings and the P5 markers come back untouched (keepForeign)")
		DataS.AddTokens(gus, 1)
		T.eq(DataS.Save(gus), true, "p5 flow merge: this server saves and adopts the store")
		advance(0.3)
		T.check(DataS.GetBerries(gus) == keep.Berries and dungeonText(DataS.GetDungeon(gus)) == keep.Dungeon and DataS.GetSettings(gus).Music == keep.Music and DataS.GetTokens(gus) == keep.Tokens + 6,
			"p5 flow merge: nothing lost: berries, Dungeon, Settings kept; the tokens of both servers land once")
		T.check(#DataS.GetTeams(gus).Presets[1] == 3 and DataS.GetProfile(gus).Pets[ecos[1]] ~= nil, "p5 flow merge: the old server's 4-key team reads as 3 keys; the 4th pet stays owned")
		-- bug batch 2 #18 rollout: the Phase 4 server put a GARDEN pet (ecos[1]) in the team; this server never lets it
		-- fight (the garden placement wins the merge, the pet keeps working in the Garden)
		local teamA = DataS.GetTeams(gus).Presets[1]
		local inTeam = false
		for _, k in ipairs(teamA) do
			inTeam = inTeam or k == ecos[1]
		end
		local gHome = DataS.GetHome(gus) or {}
		local inGarden = false
		for _, k in pairs(gHome.Garden or {}) do
			inGarden = inGarden or k == ecos[1]
		end
		T.check(not inTeam and inGarden, "p5 flow merge: (bug batch 2 #18) the garden pet the old server teamed up stays in the Garden and out of the team", listText(teamA))
		T.check(DataS.GetFood(gus, "Snack") == 1 and DataS.GetBerries(gus) == keep.Berries, "p5 flow merge: the old server's Snack stays Food (no second conversion, no free berries)")
	end)
	T.check(release() == true, "p5 flow merge: the Phase 4 module's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
end

S.p5flow_merge = scenario("p5flow_merge", function(players)
	local X = ready("p5 flow merge")
	if not X then
		return
	end
	local ecos, combats = rosterOf(X)
	local save = phase4Save(X, nil, ecos, combats)
	save.Battle.TrialBest = 9
	save.Battle.TrialCleared = { true, true, true, true, true, true, true, true, true }
	save.Food = { Snack = 1 }
	save.SpotIndex = nil
	Mock.DataStore.Data[storeKey(IDS.Gus)] = save
	local gus = join("Gus")
	players[#players + 1] = gus
	advance(1)
	mergeTwoServers(X, gus, ecos, combats)
	mergeRollout(X, gus, combats, ecos)
	leave(gus)
	advance(1)
	local rec = stored(IDS.Gus) or {}
	T.check(type(rec.Dungeon) == "table" and rec.Dungeon.Best == 4 and type(rec.Teams) == "table" and #rec.Teams.Presets[1] == 3, "p5 flow merge: his leave save: Dungeon Best 4, a 3-key team")
end)

return S
