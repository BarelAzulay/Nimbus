-- smoke_p3_fix_server.lua: regression checks for the Phase 3 review fixes on the SERVER side (fix:server). Both
-- worlds (ARGS.context picks the half): the server scenarios run booted, before the care block (they advance the
-- clock by minutes); the client scenario checks BattleController's decoding of the new snapshot wire form.
--   p3fixsrv_retreat   (pure BattleSim) a timely RETREAT escapes Lines and Circles alike (>= 85% of threatened pets for
--                      a perfect dodger, every boss), Line telegraphs end just past their target, a parked team steps
--                      out of a telegraph aimed at it, a PLAYER team that only RETREATs returns to ATTACK by itself
--                      after Damage.RetreatLock + RetreatAutoResume (Order event with auto = true) while an Auto team
--                      keeps hiding, every boss telegraph lasts >= 2.2 s
--   p3fixsrv_trial1    Trial 1 is one handicapped pet that EVERY single level-1 Common / Uncommon beats without a
--                      command; levels 2+ keep their curve; the tutorial's "team" step passes a one-pet player with
--                      that pet and makes a player with more pets field three (DataService.FieldableKeys)
--   p3fixsrv_duel      a duel between teams far apart in power is a practice duel (toast, nothing paid, no PvP
--                      counters); an honest duel between comparable teams is still paid in full (the early-forfeit
--                      gate is checked by p3bs_duel)
--   p3fixsrv_raid      a raider under BattleCatalog.Raid.MinShare gets nothing (Tier "None", no Raids + 1, a toast) and
--                      barely grows the boss (weighted head count); the result's Fighters leave out leavers and
--                      EventService's toast / LastRaid.Players count them
--   p3fixsrv_leave     both duellists leaving in one frame: the duel is void (no penalty, no PvP loss for either);
--                      BattleService.Shutdown() (game:BindToClose) ends a duel void and a raid with the tier of the
--                      share so far, refuses new battles until SetClosing(false)
--   p3fixsrv_net16     a full 16-raider Shadow Hydra raid: under ~20 KB/s per fighter on average, fighters at ~10 Hz,
--                      a spectator at ~5 Hz, U a flat number array, and the spectator's decoded picture equals the
--                      fighter's at the same T (BattleSim.DecodeSnapshot round trip)
--   client_p3fixsrv_wire (client world) BattleController.HandleState("Snapshot") decodes the wire form: units follow
--                      the sim's positions, HP, meters and Down state; junk payloads change nothing
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, max, min, sqrt = math.abs, math.floor, math.max, math.min, math.sqrt
local fmt = string.format

local function moduleAt(top, rest)
	local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
end

----------------------------------------------------------------------------------------------------
-- shared: the geometry of a telegraph event (the sim's own test, kept here so the check is independent)
----------------------------------------------------------------------------------------------------
local function inShape(ev, x, z, radius)
	if ev.shape == "Line" then
		local dx, dz = x - ev.x, z - ev.z
		local dirX, dirZ = math.cos(ev.angle), math.sin(ev.angle)
		local along = dx * dirX + dz * dirZ
		if along < -radius or along > ev.length + radius then
			return false
		end
		return abs(dx * dirZ - dz * dirX) <= ev.width / 2 + radius
	end
	local dx, dz = x - ev.x, z - ev.z
	return dx * dx + dz * dz <= (ev.r + radius) * (ev.r + radius)
end

local function pet(key, level, tier)
	return { Key = key, Level = level or 1, Tier = tier }
end

local function team(owner, side, pets, flags)
	local list = {}
	for i, p in ipairs(pets) do
		list[i] = { Key = p.Key, PetId = p.PetId, Def = p.Def, Level = p.Level, Tier = p.Tier, Slot = i }
	end
	local spec = { Owner = owner, Side = side, Pets = list }
	for k, v in pairs(flags or {}) do
		spec[k] = v
	end
	return spec
end

local M5 = { pet("aurora_fox", 12), pet("storm_tabby", 14), pet("bamboo_panda", 14) }

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer

	S.client_p3fixsrv_wire = guarded("client_p3fixsrv_wire", function()
		local BC = moduleAt("client", "Controllers/BattleController")
		local Sim = moduleAt("shared", "BattleSim")
		if not T.check(BC ~= nil and Sim ~= nil and type(Sim.DecodeSnapshot) == "function", "wire: BattleController and BattleSim.DecodeSnapshot load") then
			return
		end
		local me = LocalPlayer.UserId
		local id = "smoke_wire_" .. tostring(math.random(100000, 999999))
		local sim = Sim.new({ Mode = "Trial", Trial = 3, Seed = 5, Id = id, Teams = { { Owner = me, Side = 1, Pets = { pet("aurora_fox", 10), pet("storm_tabby", 10), pet("bamboo_panda", 10) } } }, Specials = false })
		if not T.check(sim ~= nil, "wire: a BattleSim trial for the client") then
			return
		end
		local d = sim:Describe()
		d.BattleId = id
		d.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(d.Zone.X, 30, d.Zone.Z), X = d.Zone.X, Z = d.Zone.Z }
		d.Names = { [tostring(me)] = LocalPlayer.Name }
		d.Side, d.Spectator, d.T = 1, false, sim:Time()
		LocalPlayer:SetAttribute("InBattle", id)
		local errs0 = #Mock.Errors
		BC.HandleState("Start", d, id)
		local last = {}
		local function feed()
			local evs = sim:Step(0.1)
			if #evs > 0 then
				BC.HandleState("Events", evs, id)
			end
			local snap = sim:SnapshotDelta(last)
			snap.BattleId = id
			BC.HandleState("Snapshot", snap, id)
			KC.advance(0.1)
			return snap
		end
		local first = nil
		for i = 1, 60 do
			local snap = feed()
			if i == 1 then
				first = snap
			end
		end
		KC.advance(0.3) -- the render clock catches up with the last snapshot
		T.check(first and type(first.U) == "table" and #first.U >= 6 * #sim.units, "wire: the first snapshot after Start is the full picture (every unit with every field)", first and tostring(#first.U) or "nil")
		local picture = sim:Snapshot().Units
		local tally = T.tally("wire: every unit the client draws matches the sim's picture after 6 s (position within 0.3 studs, HP, state)")
		local checked = 0
		for uid, s in pairs(picture) do
			local u = BC.GetUnit(uid)
			checked = checked + 1
			local okU = u ~= nil and abs(u.X - s.x) <= 0.3 and abs(u.Z - s.z) <= 0.3 and u.Hp == s.hp and u.State == s.state and (s.hp > 0 or u.Parked or u.Hp == 0)
			tally:case(okU, uid .. ": " .. (u and fmt("x %.1f/%.1f z %.1f/%.1f hp %s/%s st %s/%s", u.X, s.x, u.Z, s.z, tostring(u.Hp), tostring(s.hp), tostring(u.State), tostring(s.state)) or "no unit"))
		end
		tally:report(checked .. " units")
		-- a unit left out of the snapshot (unchanged) keeps its picture; meters follow
		local meterOk = true
		for uid, s in pairs(picture) do
			local u = BC.GetUnit(uid)
			if u and abs((u.Meter or 0) - s.meter) > 1 then
				meterOk = false
			end
		end
		T.check(meterOk, "wire: special meters are carried across snapshots that leave them out")
		-- junk: nothing changes, no errors
		local before = BC.GetUnit(1)
		BC.HandleState("Snapshot", { BattleId = id, T = sim:Time() + 1, U = { "x", 5, 3 } }, id)
		BC.HandleState("Snapshot", { BattleId = id, T = sim:Time() + 2, U = { 1, 2 } }, id) -- code 1 < 128: junk
		BC.HandleState("Snapshot", { BattleId = id, T = sim:Time() + 3, U = "nope" }, id)
		BC.HandleState("Snapshot", { BattleId = id, T = sim:Time() + 4 }, id)
		KC.advance(0.3)
		local after = BC.GetUnit(1)
		T.check(before and after and after.Hp == before.Hp and abs(after.X - before.X) < 0.01, "wire: junk snapshot payloads change nothing")
		T.eq(#Mock.Errors, errs0, "wire: no script errors")
		-- an out-of-range "End" cleans the battle up at once (no result card is left for the next scenarios)
		LocalPlayer:SetAttribute("InBattle", nil)
		BC.HandleState("End", { BattleId = id, Mode = "Trial", Spectator = true, Reason = "OutOfRange" }, id)
		KC.advance(1)
		T.check(BC.GetBattle() == nil and not BC.IsHudVisible(), "wire: the battle is cleaned up afterwards")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance = K.advance

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
	local function ES()
		return req("server/Services/EventService")
	end
	local function BC()
		return req("shared/BattleCatalog")
	end
	local function Sim()
		return req("shared/BattleSim")
	end
	local function PC()
		return req("shared/PetCatalog")
	end
	local function arenaInfo()
		local ab = req("server/Services/ArenaBuilder")
		return ab and ab.GetInfo and ab.GetInfo() or nil
	end

	local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }
	local MID = { "twilight_dragon", "moonlit_owl", "candy_unicorn" }
	local ALT = { "starlight_unicorn", "sunbeam_bear", "nebula_axolotl" }
	local WEAK = { "pebble_pup", "honey_bunny", "puddle_frog" }

	local seq = 0
	local function newPlayer(prefix, pets, level)
		seq = seq + 1
		local p = Mock.AddPlayer(prefix .. seq, 963000 + seq)
		advance(1.0)
		local data = DS()
		local prof = data.GetProfile(p)
		if prof and pets then
			for _, petId in ipairs(pets) do
				prof.Pets[petId] = (prof.Pets[petId] or 0) + 1
				if level then
					prof.PetLevels[petId] = { Level = level, Xp = 0 }
				end
			end
			data.MarkDirty(p)
			local ok, why = data.SetTeam(p, 1, pets)
			if not ok then
				T.fail("(setup) SetTeam for " .. p.Name .. " failed", tostring(why))
			end
		end
		return p
	end

	local function toArena(p, dx, dz)
		local info = arenaInfo()
		Mock.Teleport(p, info.Spawn * CFrame.new(dx or 0, 0, dz or 0))
		advance(0.05)
	end
	local function toPortal(p)
		local info = arenaInfo()
		Mock.Teleport(p, CFrame.new(info.TrialPortal.Position + Vector3.new(0, 3, 6)))
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
		return e and e.args[2] or nil
	end
	local function toasts(p, fromIndex)
		local out = {}
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, fromIndex or 0)) do
			out[#out + 1] = tostring(e.args[1])
		end
		return out
	end
	local function toasted(p, pattern, fromIndex)
		for _, text in ipairs(toasts(p, fromIndex)) do
			if text:find(pattern, 1, true) then
				return true, text
			end
		end
		return false, table.concat(toasts(p, fromIndex), " | ")
	end
	local function contains(list, value)
		for _, v in ipairs(type(list) == "table" and list or {}) do
			if v == value then
				return true
			end
		end
		return false
	end
	local function tokens(p)
		return DS().GetTokens(p)
	end
	local function record(p)
		return DS().GetBattle(p) or {}
	end

	local function watchEnded()
		local list = {}
		local conn = BS().BattleEnded:Connect(function(id, result)
			list[#list + 1] = { id = id, result = result }
		end)
		return {
			find = function(id)
				for _, e in ipairs(list) do
					if e.id == id then
						return e.result
					end
				end
				return nil
			end,
			stop = function()
				conn:Disconnect()
			end,
		}
	end
	local function waitEnded(w, id, seconds)
		return K.waitFor(function()
			return w.find(id) ~= nil
		end, seconds or 130)
	end

	-- EventService's scheduler must not open a raid in the middle of a scenario: StartRaid refuses while held
	local realStartRaid = nil
	local function holdRaidSchedule(bs)
		if realStartRaid == nil then
			realStartRaid = bs.StartRaid
			bs.StartRaid = function()
				return false, "A raid is already running"
			end
		end
		return realStartRaid
	end
	local function releaseRaidSchedule(bs)
		if realStartRaid then
			bs.StartRaid = realStartRaid
			realStartRaid = nil
		end
	end
	local function endAnyRaid(bs)
		if bs.GetRaidStatus() ~= nil then
			bs.EndRaid()
			advance(0.2)
		end
	end

	-- the heavy BattleState traffic stays out of the client replay log
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

	-- keeps these players' teams RETREATing for `seconds` (a player team resumes by itself, so the order is repeated)
	local function holdBack(bs, list, seconds)
		local left = seconds
		while left > 0 do
			for _, p in ipairs(list) do
				bs.Command(p, "Retreat")
			end
			local step = min(2, left)
			advance(step)
			left = left - step
		end
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

	local function ready(label)
		if not K.needBoot() then
			return false
		end
		if not BS() or not arenaInfo() then
			T.fail(label .. ": skipped, BattleService or the arena is missing")
			return false
		end
		return true
	end

	-- every scenario: guarded, then the shared switches are always put back
	local function scenario(name, fn)
		local run = guarded(name, fn)
		return function(...)
			local ok = run(...)
			local bs = BS()
			if bs then
				releaseRaidSchedule(bs)
				bs.Debug = nil
				if bs.SetClosing then
					bs.SetClosing(false)
				end
				if bs.SetDoubleRewards then
					bs.SetDoubleRewards(nil)
				end
			end
			loudReplication()
			return ok
		end
	end

	------------------------------------------------------------------------------------------------
	-- p3fixsrv_retreat (pure sim)
	------------------------------------------------------------------------------------------------
	S.p3fixsrv_retreat = guarded("p3fixsrv_retreat", function()
		local Sm, Cat = Sim(), BC()
		if not T.check(Sm and Cat, "retreat: BattleSim + BattleCatalog load") then
			return
		end
		local D = Cat.Damage
		T.check(type(D.RetreatAutoResume) == "number" and D.RetreatAutoResume >= 2 and D.RetreatAutoResume <= 5 and type(D.TelegraphMargin) == "number" and D.TelegraphMargin > 0,
			"retreat: BattleCatalog.Damage.RetreatAutoResume (~3 s) and TelegraphMargin exist", tostring(D.RetreatAutoResume))
		T.check(type(Sm.LineOvershoot) == "number" and Sm.LineOvershoot >= 3 and Sm.LineOvershoot <= 10, "retreat: BattleSim.LineOvershoot (a Line ends just past its target)")
		local shortest = math.huge
		for _, bossId in ipairs(Cat.BossOrder) do
			for _, a in ipairs(Cat.Bosses[bossId].Attacks) do
				shortest = min(shortest, a.Telegraph)
			end
		end
		T.check(shortest >= 2.2, "retreat: every boss telegraph lasts at least 2.2 s (#7: the client fills toward the dodge deadline)", tostring(shortest))

		-- a perfect dodger against every boss: threatened pets vs pets still hit, per shape; line lengths; parked escapes
		local total = { Line = { threatened = 0, hit = 0 }, Circle = { threatened = 0, hit = 0 } }
		local linesOk, parkedThreatened, parkedHit = true, 0, 0
		for _, bossId in ipairs(Cat.BossOrder) do
			for seed = 1, 2 do
				local b = Sm.new({ Mode = "Raid", Boss = bossId, Seed = seed, Teams = { team(101, 1, M5) } })
				local radius, mine, pending = {}, {}, {}
				for _, info in ipairs(b:StaticUnits()) do
					radius[info.id] = info.radius
					if info.owner == 101 then
						mine[info.id] = true
					end
				end
				local bossUnit = b.boss
				local retreatAt, attackAt = nil, nil
				local steps = 0
				while not b:IsFinished() and steps < 3400 do
					local events = b:Step(0.1)
					steps = steps + 1
					local t = b:Time()
					local snap = b:Snapshot()
					local parked = b:TeamOf(101).Order == "Retreat"
					for _, ev in ipairs(events) do
						if ev.type == "Telegraph" then
							if ev.shape == "Line" then
								-- the line ends a little past the pet it is aimed at (never a whole-floor ray): no longer than the
								-- farthest living pet plus the overshoot (a fan's side lines share the aimed pet's length; pets
								-- moved up to ~2 studs since it was aimed)
								local farthest = 0
								for id in pairs(mine) do
									local u = snap.Units[id]
									if u and u.hp > 0 then
										farthest = max(farthest, sqrt((u.x - bossUnit.x) ^ 2 + (u.z - bossUnit.z) ^ 2))
									end
								end
								if farthest > 0 and ev.length > farthest + Sm.LineOvershoot + 3 then
									linesOk = false
								end
							end
							local threatened, any = {}, false
							for id in pairs(mine) do
								local u = snap.Units[id]
								if u and u.hp > 0 and inShape(ev, u.x, u.z, radius[id] or 2) then
									threatened[id] = true
									any = true
								end
							end
							if any then
								pending[ev.id] = { shape = ev.shape, threatened = threatened, hit = {}, parked = parked }
								local at = t + 1e-6
								if not retreatAt or at < retreatAt then
									retreatAt = at
								end
								if not attackAt or ev.at + 0.1 > attackAt then
									attackAt = ev.at + 0.1
								end
							end
						elseif ev.type == "Hit" and ev.tele and pending[ev.tele] and mine[ev.to] then
							pending[ev.tele].hit[ev.to] = true
						end
					end
					if retreatAt and t >= retreatAt then
						retreatAt = nil
						b:Command(101, "Retreat")
					end
					if attackAt and t >= attackAt and not retreatAt and b:Command(101, "Attack") then
						attackAt = nil
					end
				end
				for _, p in pairs(pending) do
					for id in pairs(p.threatened) do
						total[p.shape].threatened = total[p.shape].threatened + 1
						if p.parked then
							parkedThreatened = parkedThreatened + 1
						end
						if p.hit[id] then
							total[p.shape].hit = total[p.shape].hit + 1
							if p.parked then
								parkedHit = parkedHit + 1
							end
						end
					end
				end
			end
		end
		local function escaped(row)
			return row.threatened > 0 and (row.threatened - row.hit) / row.threatened or 1
		end
		T.check(total.Line.threatened >= 20 and escaped(total.Line) >= 0.85, "retreat: a RETREAT on the warning escapes >= 85% of Line hits (#2 / #6)",
			fmt("%d threatened, %d hit", total.Line.threatened, total.Line.hit))
		T.check(total.Circle.threatened >= 20 and escaped(total.Circle) >= 0.85, "retreat: ...and >= 85% of Circle hits",
			fmt("%d threatened, %d hit", total.Circle.threatened, total.Circle.hit))
		T.check(linesOk, "retreat: every Line telegraph ends within LineOvershoot of the pet it is aimed at")
		T.check(parkedThreatened == 0 or parkedHit <= parkedThreatened * 0.2, "retreat: a team already parked at its anchor steps out of a telegraph aimed at it",
			fmt("%d threatened while parked, %d hit", parkedThreatened, parkedHit))

		-- a retreating team parks beside its anchor within the lock + resume window, then goes back by itself
		local b = Sm.new({ Mode = "Raid", Boss = "frost_wyrm", Seed = 3, Teams = { team(102, 1, M5) } })
		b:Command(102, "Retreat")
		for _ = 1, 40 do
			b:Step(0.1)
		end
		local anchor = b:TeamOf(102).Anchor
		local parkedAll = true
		for _, u in ipairs(b:TeamOf(102).Units) do
			local su = b:Snapshot().Units[u.id]
			if su and sqrt((su.x - anchor.x) ^ 2 + (su.z - anchor.z) ^ 2) > 6 then
				parkedAll = false
			end
		end
		T.check(parkedAll and b:TeamOf(102).Order == "Retreat", "retreat: a retreating team is parked beside its anchor after 4 s (still RETREAT)")
		for _ = 1, 12 do
			b:Step(0.1)
		end
		T.eq(b:TeamOf(102).Order, "Attack", "retreat: ...and is back to ATTACK by itself a second later (RetreatLock + RetreatAutoResume)")

		-- auto resume: a player team that only RETREATs returns to ATTACK by itself; an Auto team does not
		local wait = D.RetreatLock + D.RetreatAutoResume
		local duel = Sm.new({ Mode = "Trial", Trial = 4, Seed = 7, Teams = { team(1, 1, { pet("mallow_kitten", 4), pet("biscuit_bear", 3), pet("maple_fox", 3) }) } })
		for _ = 1, 100 do
			duel:Step(0.1)
		end
		duel:Command(1, "Retreat")
		local resumedAt, orderEv = nil, nil
		local steps = 0
		while not duel:IsFinished() and steps < 1200 do
			for _, ev in ipairs(duel:Step(0.1)) do
				if ev.type == "Order" and ev.owner == 1 and ev.order == "Attack" and ev.auto and not resumedAt then
					resumedAt, orderEv = duel:Time() - 10, ev
				end
			end
			steps = steps + 1
		end
		local r = duel:Result()
		T.check(resumedAt ~= nil and resumedAt >= wait - 0.01 and resumedAt <= wait + 3, "retreat: a player team that RETREATs returns to ATTACK by itself ~" .. wait .. " s later (Order event, auto = true) (#8)", tostring(resumedAt))
		T.check(orderEv and orderEv.target == nil and r and r.WinnerSide == 1 and r.Reason ~= "Timeout", "retreat: ...and goes on to win the trial it was winning (no 120 s timeout)", r and r.Reason or "unfinished")
		local okCmd, why = duel:Command(1, "Attack")
		T.check(okCmd == true or why == "Finished", "retreat: ATTACK is still accepted at once after a RETREAT (the lock aside)", tostring(why))
		local hide = Sm.new({ Mode = "Duel", Seed = 4, Teams = { team(1, 1, M5, { Auto = true }), team(2, 2, M5, { Auto = true }) } })
		hide:Command(1, "Retreat")
		local autoResumed = false
		for _ = 1, 150 do
			for _, ev in ipairs(hide:Step(0.1)) do
				if ev.type == "Order" and ev.auto then
					autoResumed = true
				end
			end
		end
		T.check(not autoResumed and hide:TeamOf(1).Order == "Retreat", "retreat: an Npc / Auto team keeps its RETREAT order (no auto resume)")
	end)

	------------------------------------------------------------------------------------------------
	-- p3fixsrv_trial1
	------------------------------------------------------------------------------------------------
	S.p3fixsrv_trial1 = guarded("p3fixsrv_trial1", function()
		local Cat, Sm, Pets = BC(), Sim(), PC()
		if not T.check(Cat and Sm and Pets, "trial 1: BattleCatalog, BattleSim, PetCatalog load") then
			return
		end
		local t1 = Cat.Trials[1]
		T.check(t1 and #t1.Team == 1 and type(t1.Team[1].Handicap) == "number" and t1.Team[1].Handicap > 0 and t1.Team[1].Handicap < 1 and t1.Team[1].Level == 1
			and t1.RecommendedPower <= 4, "trial 1: one handicapped level-1 NPC pet, RecommendedPower <= 4 (#5)", t1 and fmt("%d pets, power %d, handicap %s", #t1.Team, t1.RecommendedPower, tostring(t1.Team[1].Handicap)) or "nil")
		local spec = Cat.TrialTeam(1)
		T.check(spec and #spec.Pets == 1 and spec.Pets[1].Handicap == t1.Team[1].Handicap, "trial 1: TrialTeam(1) carries the handicap to BattleSim")
		local ok, problems = Cat.Validate()
		T.check(ok, "trial 1: BattleCatalog.Validate() still passes", table.concat(problems or {}, "; "))
		T.check(Cat.Trials[2].RecommendedPower >= 15 and Cat.Trials[2].RecommendedPower <= 22 and #Cat.Trials[2].Team == 3 and Cat.Trials[5].MiniBoss == true,
			"trial 1: levels 2+ keep their curve (level 2 ~17-18, three pets, a mini-boss at 5)", tostring(Cat.Trials[2].RecommendedPower))
		-- every single level-1 Common / Uncommon, no command at all (the tutorial's player who never presses SPECIAL)
		local tally = T.tally("trial 1: every single level-1 Common / Uncommon wins Trial 1 without a single command (6 seeds each)")
		local singles = 0
		for _, def in ipairs(Pets.Pets) do
			if def.Rarity == "Common" or def.Rarity == "Uncommon" then
				singles = singles + 1
				local wins, dur = 0, 0
				for seed = 1, 6 do
					local b = Sm.new({ Mode = "Trial", Trial = 1, Seed = seed, Teams = { team(1, 1, { pet(def.Id, 1) }) } })
					local steps = 0
					while b and not b:IsFinished() and steps < 1300 do
						b:Step(0.1)
						steps = steps + 1
					end
					local r = b and b:Result()
					if r and r.WinnerSide == 1 then
						wins = wins + 1
						dur = dur + r.Duration
					end
				end
				tally:case(wins == 6 and dur / max(1, wins) <= 60, def.Id .. ": " .. wins .. "/6 wins, " .. fmt("%.0f", dur / max(1, wins)) .. " s")
			end
		end
		tally:report(singles .. " pets")
		-- a day-1 trio still clears trial 1 fast, and trial 2 is a real (winnable) fight for it
		local b2 = Sm.new({ Mode = "Trial", Trial = 2, Seed = 2, Teams = { team(1, 1, { pet("mallow_kitten", 1), pet("puddle_frog", 1), pet("pebble_pup", 1) }, { Auto = true }) } })
		local steps = 0
		while not b2:IsFinished() and steps < 1300 do
			b2:Step(0.1)
			steps = steps + 1
		end
		T.check(b2:Result() and b2:Result().WinnerSide == 1, "trial 1: a brand-new trio of Commons (auto) still beats trial 2", b2:Result() and b2:Result().Reason or "unfinished")

		-- the tutorial's "team" step on the booted game
		if not K.needBoot() then
			return
		end
		local TSv, DataS, Steps = K.mod("TutorialService"), K.mod("DataService"), req("shared/TutorialSteps")
		local info = arenaInfo()
		if not T.check(TSv and DataS and Steps and info and type(TSv.Reload) == "function" and type(DataS.FieldableKeys) == "function",
			"trial 1 tutorial: TutorialService, DataService.FieldableKeys, TutorialSteps and the arena are there") then
			return
		end
		local teamStep = Steps.Steps[Steps.IndexOf.team]
		T.check(teamStep and teamStep.Text:find("put your pets in your team", 1, true) ~= nil and teamStep.Text:find("up to 3", 1, true) ~= nil and teamStep.Text:find("Prestige 1", 1, true) ~= nil
			and not teamStep.Text:find("pick 3 pets", 1, true), "trial 1 tutorial: the 'team' text says what the step checks (put your pets in your team, up to 3, a 4th after Prestige 1)", teamStep and teamStep.Text)
		local start = Steps.ChapterStart[3]
		local function stepId(p)
			local st = TSv.GetState(p)
			return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
		end
		local function tutorialPlayer(prefix, pets)
			local p = newPlayer(prefix, nil)
			local prof = DataS.GetProfile(p)
			for _, petId in ipairs(pets) do
				prof.Pets[petId] = (prof.Pets[petId] or 0) + 1
			end
			DataS.MarkDirty(p)
			DataS.SetTeam(p, 1, {})
			DataS.SetTutorial(p, { Step = start, Done = true, Gifted = true })
			Mock.Teleport(p, CFrame.new(K.config().Lobby.Origin + Vector3.new(12, 4, 12)))
			TSv.Reload(p)
			advance(0.6)
			Mock.Teleport(p, info.Spawn * CFrame.new(0, 3, 0))
			K.waitFor(function()
				return stepId(p) ~= "arena"
			end, 3)
			return p
		end
		local one = tutorialPlayer("TutOne", { "pebble_pup" })
		T.eq(stepId(one), "team", "trial 1 tutorial: a player with ONE pet reaches 'team'")
		T.eq(#DataS.FieldableKeys(one), 1, "trial 1 tutorial: DataService.FieldableKeys counts that one pet")
		DataS.SetTeam(one, 1, { "pebble_pup" })
		advance(0.6)
		T.eq(stepId(one), "trial", "trial 1 tutorial: ...and completes 'team' with that one pet in the team")
		local many = tutorialPlayer("TutMany", { "pebble_pup", "honey_bunny", "puddle_frog", "mallow_kitten" })
		T.eq(stepId(many), "team", "trial 1 tutorial: a player with four pets reaches 'team'")
		DataS.SetTeam(many, 1, { "pebble_pup" })
		advance(1.2)
		T.eq(stepId(many), "team", "trial 1 tutorial: ...one pet in the team is not enough for them ('team' waits)")
		DataS.SetTeam(many, 1, { "pebble_pup", "honey_bunny", "puddle_frog" })
		advance(0.6)
		T.eq(stepId(many), "trial", "trial 1 tutorial: ...three pets complete 'team' (the 4th slot waits for Prestige 1)")
		K.flushErrors("trial 1 tutorial")
		cleanup({ one, many })
	end)

	------------------------------------------------------------------------------------------------
	-- p3fixsrv_duel
	------------------------------------------------------------------------------------------------
	S.p3fixsrv_duel = scenario("p3fixsrv_duel", function()
		if not ready("p3fixsrv_duel") then
			return
		end
		quietReplication()
		local bs, data, cat = BS(), DS(), BC()
		local TR = cat.Trophies
		local w = watchEnded()
		-- a practice duel: STRONG level 20 vs a single level-1 pebble pup
		local strong = newPlayer("GapStrong", STRONG, 20)
		local weak = newPlayer("GapWeak", { "pebble_pup" }, 1)
		data.AddTrophies(strong, 50)
		data.AddTrophies(weak, 50)
		toArena(strong, 3, 0)
		toArena(weak, -3, 0)
		local recS0, recW0 = record(strong), record(weak)
		local tS0, tW0 = tokens(strong), tokens(weak)
		local mark = K.logSize()
		local ok, id = bs.StartDuel(strong, weak)
		T.check(ok == true, "practice: (setup) the duel starts", tostring(id))
		T.check(toasted(strong, "Practice duel", mark) and toasted(weak, "Practice duel", mark), "practice: both get a clear 'Practice duel' side toast at the start (#0 power gap)", select(2, toasted(weak, "Practice duel", mark)))
		waitEnded(w, id, 60)
		local r = w.find(id)
		T.check(r ~= nil and contains(r.Winners, strong.UserId), "practice: the strong team wins", r and r.Reason or "no end")
		local rwS, rwW = r and r.Rewards[strong.UserId], r and r.Rewards[weak.UserId]
		T.check(rwS and rwS.Practice == true and rwS.Tokens == 0 and rwS.Xp == 0 and rwS.Trophies == 0 and tokens(strong) == tS0 and record(strong).Trophies == recS0.Trophies and (record(strong).PvPWins or 0) == (recS0.PvPWins or 0),
			"practice: the winner gets no tokens, XP or trophies and no PvPWin", rwS and fmt("tokens %s xp %s trophies %s", tostring(rwS.Tokens), tostring(rwS.Xp), tostring(rwS.Trophies)) or "none")
		T.check(rwW and rwW.Tokens == 0 and rwW.Trophies == 0 and tokens(weak) == tW0 and record(weak).Trophies == recW0.Trophies and (record(weak).PvPLosses or 0) == (recW0.PvPLosses or 0),
			"practice: the loser loses no trophies, gets no tokens and no PvPLoss")
		T.check(toasted(strong, "No rewards for practice", mark), "practice: the result toast says so")
		advance(4.5)
		-- the same two with real teams: honest, so the pair limit was not spent on the practice duel
		local other = newPlayer("GapOther", MID, 20)
		toArena(other, 0, 4)
		local m2 = K.logSize()
		ok, id = bs.StartDuel(strong, other)
		T.check(ok == true and not toasted(strong, "Practice", m2), "stomp: a duel between comparable teams is not practice", tostring(id))
		-- an honest duel between comparable teams, fought to the end, is still rewarded in full
		local tS1, trS1, winsS1 = tokens(strong), record(strong).Trophies, record(strong).PvPWins or 0
		waitEnded(w, id, 130)
		r = w.find(id)
		local winner = r and r.Winners[1] == strong.UserId and strong or other
		local rwWin = r and r.Rewards[winner.UserId]
		T.check(r ~= nil and #r.Winners == 1 and r.Forfeit == false and (r.Damage[strong.UserId] or 0) > 0 and (r.Damage[other.UserId] or 0) > 0,
			"honest: (setup) the duel is fought to the end, both sides dealt damage", r and tostring(r.Reason) or "no end")
		T.check(rwWin and rwWin.Trophies == TR.Win and rwWin.Tokens == TR.Tokens.Win * (rwWin.Double and 2 or 1) and rwWin.Xp == TR.Xp.Win and not rwWin.Practice and not rwWin.Unpaid,
			"honest: the winner of an honest duel is paid in full (trophies, tokens, XP): the gates only bite farming", rwWin and fmt("tokens %s trophies %s", tostring(rwWin.Tokens), tostring(rwWin.Trophies)) or "none")
		if winner == strong then
			T.check(tokens(strong) - tS1 == rwWin.Tokens and record(strong).Trophies == trS1 + TR.Win and (record(strong).PvPWins or 0) == winsS1 + 1, "honest: ...and the balances moved by exactly that")
		end
		K.flushErrors("p3fixsrv_duel")
		w.stop()
		cleanup({ strong, weak, other })
	end)

	------------------------------------------------------------------------------------------------
	-- p3fixsrv_raid
	------------------------------------------------------------------------------------------------
	S.p3fixsrv_raid = scenario("p3fixsrv_raid", function()
		if not ready("p3fixsrv_raid") then
			return
		end
		quietReplication()
		local bs, cat, es = BS(), BC(), ES()
		local w = watchEnded()
		endAnyRaid(bs)
		local startRaid = holdRaidSchedule(bs)
		local hero = newPlayer("ShareHero", STRONG, 20)
		local alt = newPlayer("ShareAlt", WEAK, 1)
		toArena(hero, -4, 0)
		toArena(alt, 4, 0)
		local okR, raidId = startRaid("storm_titan")
		local okJ = bs.JoinRaid(hero)
		local hpSolo = bs.GetRaidStatus().MaxHp
		local okA = bs.JoinRaid(alt)
		local hpBoth = bs.GetRaidStatus().MaxHp
		T.check(okR and okJ and okA and hpBoth <= hpSolo * 1.12 and hpBoth >= hpSolo, "raid share: an alt team of level-1 Commons grows the boss by less than 12% (weighted head count) (#1)",
			fmt("%d -> %d", hpSolo, hpBoth))
		local altTokens0, altRaids0 = tokens(alt), record(alt).Raids or 0
		local heroTokens0 = tokens(hero)
		local mark = K.logSize()
		-- the alt holds back the whole time, the hero fights; the raid is cut short as a loss (EndRaid)
		for _ = 1, 10 do
			bs.Command(alt, "Retreat")
			bs.Command(hero, "Attack")
			for slot = 1, 3 do
				bs.Command(hero, "Special", slot)
			end
			advance(2)
		end
		bs.EndRaid()
		local r = w.find(raidId)
		T.check(r ~= nil and r.Mode == "Raid", "raid share: (setup) the raid ends", r and r.Reason or "no end")
		local rwAlt, rwHero = r and r.Rewards[alt.UserId], r and r.Rewards[hero.UserId]
		local share = r and r.Shares[alt.UserId] or 1
		T.check(share < cat.Raid.MinShare, "raid share: (setup) the alt's damage share stays under Raid.MinShare", fmt("%.4f", share))
		T.check(rwAlt and rwAlt.Tier == "None" and rwAlt.Tokens == 0 and rwAlt.Xp == 0 and tokens(alt) == altTokens0 and (record(alt).Raids or 0) == altRaids0,
			"raid share: the alt gets nothing (Tier None, no tokens / XP, no Raids + 1)", rwAlt and tostring(rwAlt.Tier) or "no rewards")
		T.check(toasted(alt, "Too little damage", mark), "raid share: ...and a side toast says so")
		local loss = cat.RaidTier(1, false)
		T.check(rwHero and rwHero.Tier == "Loss" and tokens(hero) - heroTokens0 == rwHero.Tokens and rwHero.Tokens == loss.Tokens * (rwHero.Double and 2 or 1),
			"raid share: the hero who fought gets the Loss tier of the cut-short raid", rwHero and tostring(rwHero.Tier) or "none")
		T.check(r and type(r.Fighters) == "table" and #r.Fighters == 2 and contains(r.Fighters, hero.UserId), "raid share: the result lists Fighters (the raiders still in at the end)")
		advance(5)
		-- Fighters vs Participants in EventService's toast and LastRaid (a leaver is not counted)
		if es and type(es.GetState) == "function" then
			local m2 = K.logSize()
			local a, b, c = hero.UserId, alt.UserId, 963999
			bs.BattleEnded:Fire("smoke-fighters", { Mode = "Raid", BossId = "lava_golem", Winners = { a, b }, Losers = {}, Participants = { a, b, c }, Fighters = { a, b },
				Shares = { [a] = 0.6, [b] = 0.4 }, Damage = { [a] = 600, [b] = 400 }, Forfeit = false, RewardsPaid = true, Rewards = {} })
			advance(0.3)
			local okT, text = toasted(hero, "defeated by 2 raiders", m2)
			T.check(okT, "raid toast: '<Boss> was defeated by N raiders' counts the raiders still in at the end, not the leaver (lead extra)", text)
			local last = es.GetState().LastRaid
			T.check(type(last) == "table" and last.Players == 2, "raid toast: LastRaid.Players counts them too", last and tostring(last.Players) or "nil")
		else
			T.fail("raid toast: EventService.GetState missing")
		end
		K.flushErrors("p3fixsrv_raid")
		w.stop()
		cleanup({ hero, alt })
	end)

	------------------------------------------------------------------------------------------------
	-- p3fixsrv_leave
	------------------------------------------------------------------------------------------------
	S.p3fixsrv_leave = scenario("p3fixsrv_leave", function()
		if not ready("p3fixsrv_leave") then
			return
		end
		quietReplication()
		local bs, data, cat = BS(), DS(), BC()
		local w = watchEnded()
		local source = K.moduleInstance("server/Services/BattleService").Source
		T.check(source:find("game:BindToClose(", 1, true) ~= nil and type(bs.Shutdown) == "function" and type(bs.SetClosing) == "function",
			"leave: BattleService binds game:BindToClose and exposes Shutdown / SetClosing (#3)")
		-- both duellists leave in the same frame
		local a = newPlayer("DblA", STRONG, 10)
		local b = newPlayer("DblB", MID, 10)
		data.AddTrophies(a, 100)
		data.AddTrophies(b, 100)
		toArena(a, 3, 0)
		toArena(b, -3, 0)
		local ok, id = bs.StartDuel(a, b)
		T.check(ok == true, "leave: (setup) a duel starts", tostring(id))
		holdBack(bs, { a }, 12)
		local uidA, uidB = a.UserId, b.UserId
		local lossesA, lossesB = record(a).PvPLosses or 0, record(b).PvPLosses or 0
		local storedA, storedB = record(a).Trophies, record(b).Trophies
		Mock.DataStore.Latency = 0.2
		Mock.RemovePlayer(a)
		Mock.RemovePlayer(b)
		advance(0.5)
		local r = w.find(id)
		T.check(r ~= nil and #r.Winners == 0 and #r.Losers == 0 and (r.Reason == "Void" or r.Draw == true), "leave: both leaving in one frame: the duel is void (no winner, no loser)", r and tostring(r.Reason) or "no end")
		advance(13)
		Mock.DataStore.Latency = 0
		local function stored(uid)
			local key = K.config().Tokens.DataStoreName .. "/u_" .. uid
			local rec = Mock.DataStore.Data[key]
			return type(rec) == "table" and rec.Battle or {}
		end
		local sa, sb = stored(uidA), stored(uidB)
		T.check(sa.Trophies == storedA and sb.Trophies == storedB, "leave: ...neither saved profile lost trophies", fmt("A %s (was %s), B %s (was %s)", tostring(sa.Trophies), tostring(storedA), tostring(sb.Trophies), tostring(storedB)))
		T.check((sa.PvPLosses or 0) == lossesA and (sb.PvPLosses or 0) == lossesB, "leave: ...and neither got a PvP loss")
		T.check(r and r.Rewards[uidA] and r.Rewards[uidA].Void == true and r.Rewards[uidB] and r.Rewards[uidB].Void == true, "leave: ...both rewards records are Void")

		-- a shutdown: a running duel is void, a running raid pays the share so far, new battles are refused
		local c = newPlayer("ShutC", STRONG, 10)
		local d = newPlayer("ShutD", MID, 10)
		local e = newPlayer("ShutE", STRONG, 20)
		data.AddTrophies(c, 100)
		data.AddTrophies(d, 100)
		toArena(c, 3, 0)
		toArena(d, -3, 0)
		toArena(e, 0, 6)
		local okD, duelId = bs.StartDuel(c, d)
		endAnyRaid(bs)
		local startRaid = holdRaidSchedule(bs)
		local okR, raidId = startRaid("lava_golem")
		local okJ = bs.JoinRaid(e)
		T.check(okD and okR and okJ, "leave: (setup) a duel and a raid run", tostring(duelId) .. " " .. tostring(raidId))
		for _ = 1, 6 do
			bs.Command(e, "Attack")
			for slot = 1, 3 do
				bs.Command(e, "Special", slot)
			end
			advance(2)
		end
		local tc0, td0, te0 = tokens(c), tokens(d), tokens(e)
		local trC, trD = record(c).Trophies, record(d).Trophies
		local m3 = K.logSize()
		T.check(bs.Shutdown() == true, "leave: Shutdown() runs")
		local rd, rr = w.find(duelId), w.find(raidId)
		T.check(rd ~= nil and rd.Reason == "Shutdown" and #rd.Winners == 0 and #rd.Losers == 0 and tokens(c) == tc0 and tokens(d) == td0 and record(c).Trophies == trC and record(d).Trophies == trD,
			"leave: the duel ends with Reason Shutdown: no winner, no loser, no trophies or tokens moved", rd and tostring(rd.Reason) or "no end")
		local endC = lastMsg(c, "End", m3)
		T.check(endC and endC.Reason == "Shutdown" and toasted(c, "restarting", m3), "leave: ...the duellists get 'End' (Reason Shutdown) and a side toast")
		local rwE = rr and rr.Rewards[e.UserId]
		local share = rr and rr.Shares[e.UserId] or 0
		local tier = cat.RaidTier(share, true)
		T.check(rr ~= nil and rr.Reason == "Shutdown" and rwE and tier and rwE.Tier == tier.Id and rwE.Tokens > 0 and tokens(e) - te0 == rwE.Tokens and rwE.EventPet == nil,
			"leave: the raid ends with Reason Shutdown and pays the tier of the share so far (no event-pet roll)", rwE and tostring(rwE.Tier) or "none")
		T.check(bs.GetRaidStatus() == nil and not bs.IsInBattle(c) and not bs.IsInBattle(e), "leave: ...nothing is left running, everyone is free")
		toPortal(e)
		local okT, whyT = bs.StartTrial(e, 1)
		T.check(okT == false and type(whyT) == "string" and whyT:find("restarting", 1, true) ~= nil, "leave: while closing, new battles are refused", tostring(whyT))
		bs.SetClosing(false)
		local okT2, idT2 = bs.StartTrial(e, 1)
		T.check(okT2 == true, "leave: SetClosing(false) reopens battles (tests)", tostring(idT2))
		if okT2 then
			bs.Forfeit(e)
			advance(4.6)
		end
		K.flushErrors("p3fixsrv_leave")
		w.stop()
		cleanup({ c, d, e })
	end)

	------------------------------------------------------------------------------------------------
	-- p3fixsrv_net16
	------------------------------------------------------------------------------------------------
	S.p3fixsrv_net16 = scenario("p3fixsrv_net16", function()
		if not ready("p3fixsrv_net16") then
			return
		end
		quietReplication()
		local bs, Sm = BS(), Sim()
		local info = arenaInfo()
		endAnyRaid(bs)
		local okR = holdRaidSchedule(bs)("shadow_hydra")
		local raiders = {}
		local rosters = { STRONG, MID, ALT, WEAK }
		for i = 1, 16 do
			raiders[i] = newPlayer("Net16", rosters[(i - 1) % 4 + 1], 12)
			toArena(raiders[i], (i - 8) * 2, 8)
			bs.JoinRaid(raiders[i])
		end
		local watcher = newPlayer("Net16Watch", WEAK)
		Mock.Teleport(watcher, info.Floor.CFrame * CFrame.new(0, 3, 62)) -- in the stands: a spectator
		advance(2)
		local status = bs.GetRaidStatus()
		T.check(okR and status and status.Players == 16, "net16: (setup) a 16-raider Shadow Hydra raid runs", status and tostring(status.Players) or "nil")
		local mark = K.logSize()
		local seconds = 12
		for _ = 1, seconds * 2 do
			for i, p in ipairs(raiders) do
				bs.Command(p, "Attack")
				bs.Command(p, "Special", (i % 3) + 1)
			end
			advance(0.5)
		end
		local function stats(p)
			local bytes, snaps, first, last, perSecond = 0, 0, nil, nil, {}
			local t0 = nil
			local units = 0
			for _, e in ipairs(battleMsgs(p, mark)) do
				local sz = bs.EstimateBytes(e.args[2]) + 4 + #tostring(e.args[1]) + #tostring(e.args[3] or "")
				bytes = bytes + sz
				t0 = t0 or e.time
				local k = floor(e.time - t0) + 1
				perSecond[k] = (perSecond[k] or 0) + sz
				if e.args[1] == "Snapshot" then
					snaps = snaps + 1
					first = first or e.time
					last = e.time
				end
			end
			local peak = 0
			for _, v in pairs(perSecond) do
				peak = max(peak, v)
			end
			local hz = (snaps > 1 and last > first) and (snaps - 1) / (last - first) or 0
			return bytes / seconds, peak, hz
		end
		local rate, peak, hz = stats(raiders[1])
		local wRate, wPeak, wHz = stats(watcher)
		T.info(fmt("*net16: fighter %.1f KB/s (peak second %.1f KB), %.1f snapshots/s; spectator %.1f KB/s, %.1f snapshots/s", rate / 1000, peak / 1000, hz, wRate / 1000, wHz))
		T.check(rate > 0 and rate < 20000, "net16: a fighter in a full 16-raider raid gets under 20 KB/s on average (#4)", fmt("%.0f B/s", rate))
		T.check(peak < 32000, "net16: ...and no second above 32 KB", fmt("%.0f B", peak))
		T.check(hz >= 9 and hz <= 11, "net16: fighters still get ~10 snapshots per second", fmt("%.1f", hz))
		T.check(wHz >= 4 and wHz <= 6 and wRate < rate, "net16: a spectator gets ~5 snapshots per second and less traffic", fmt("%.1f Hz, %.0f B/s", wHz, wRate))
		-- the wire form and the round trip: the spectator's decoded picture equals the fighter's at the same T
		local function decodeStream(p)
			local msgs = battleMsgs(p, 0)
			local startAt = 0
			for i, e in ipairs(msgs) do
				if e.args[1] == "Start" then
					startAt = i
				end
			end
			local picture, byT, flat = nil, {}, true
			for i = startAt + 1, #msgs do
				local e = msgs[i]
				if e.args[1] == "Snapshot" then
					local payload = e.args[2]
					if type(payload.U) ~= "table" or payload.Units ~= nil then
						flat = false
					else
						for _, v in ipairs(payload.U) do
							if type(v) ~= "number" or v ~= floor(v) then
								flat = false
							end
						end
					end
					picture = Sm.DecodeSnapshot(payload, picture)
					byT[payload.T] = picture
				end
			end
			return byT, picture, flat
		end
		local fighterByT, _, flatF = decodeStream(raiders[1])
		local _, watcherPicture, flatW = decodeStream(watcher)
		local lastT = nil
		for _, e in ipairs(battleMsgs(watcher, 0, "Snapshot")) do
			lastT = e.args[2].T
		end
		T.check(flatF and flatW, "net16: every snapshot is the wire form (U: a flat array of whole numbers, no Units)")
		local same = fighterByT[lastT] ~= nil and watcherPicture ~= nil
		local compared = 0
		if same then
			for uid, s in pairs(fighterByT[lastT]) do
				local o = watcherPicture[uid]
				compared = compared + 1
				if not o or o.x ~= s.x or o.z ~= s.z or o.hp ~= s.hp or o.state ~= s.state or o.meter ~= s.meter or o.shield ~= s.shield or o.target ~= s.target then
					same = false
				end
			end
			for uid in pairs(watcherPicture) do
				if not fighterByT[lastT][uid] then
					same = false
				end
			end
		end
		T.check(same and compared >= 40, "net16: the 5 Hz spectator stream decodes to exactly the fighter's 10 Hz picture at the same T (BattleSim.DecodeSnapshot round trip)", fmt("%d units at T %s", compared, tostring(lastT)))
		bs.EndRaid()
		K.flushErrors("p3fixsrv_net16")
		local all = { watcher }
		for _, p in ipairs(raiders) do
			all[#all + 1] = p
		end
		cleanup(all)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
