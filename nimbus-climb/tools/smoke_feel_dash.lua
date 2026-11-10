-- smoke_feel_dash.lua: the battle feel, Task 2 "Melee dash, standoff 8 and the flurry"
-- (docs/superpowers/specs/2026-11-10-battle-feel-design.md decisions 1-3; plan docs/superpowers/plans/2026-11-10-battle-feel.md
-- Task 2). Loaded by tools/smoke.py in BOTH worlds (ARGS.context picks the half).
-- Server world, pure (a real BattleSim, white-box on battle.units / battle.teams):
--   feel_standoff_rest   a melee unit rests BattleCatalog.Damage.Standoff (8) farther out: the harness fighter at reach + 8 - 0.5,
--                        an NPC melee pet at reach + 8 - 0.5 of my standing fighter; Standoff = 0 gives today's reach - 0.5; a
--                        ranged NPC holds at reach - 0.3 at both settings
--   feel_standoff_dps    the same fights at Standoff 8 and 0: the melee unit's hit count differs by at most 1, its first hit is
--                        no later at 8 (a shorter walk), every NPC hit lands within reach + 8 + EngageSlack + 1.0
--   feel_standoff_zone   three NPC melee pets from one side on a 44 x 44 floor: every rest spot on the floor, >= 2.4 studs apart,
--                        all three winding up by 8 s
--   feel_standoff_wire   Validate holds; Standoff -1 / "x" / 25 fails it; the Windup event carries only type / unit / target / at
-- Client world (AttackFx on a fake clock; BattleController fed by a real BattleSim the way BattleService sends it):
--   client_feel_dash_npc     an enemy melee pet's Windup dashes it: AttackFx.Dash lands on ev.at, the pose is DashIn and at the
--                            edge at the landing, its Hit plays Dashed (no Strike), my pet flinches, DashBack from landAt + 0.20,
--                            "out" by landAt + 0.60; a dash with no hit after it returns all the same
--   client_feel_dash_mine    my melee fighter's Hit (no Windup): dashed, its impact and its number 0.30 later (fxLate); Melee.Dash =
--                            false: no dash, today's Strike, the number at the event
--   client_feel_dash_flurry  attacks 0.64 s apart stay in and bite in place (Strike Reach = Lunge on Forward = the edge), DashBack
--                            0.75 s after the last landing; attacks 1.1 s apart make a full round trip each time
--   client_feel_dash_off     a gap under MinGap 3: no dash (false); Melee.Dash = false: false; Low graphics: the dash runs, no streak
--   client_feel_dash_budget  eight melee pets dash at a boss in one frame: 4 streaks at most (mine kept), no new Instance between two
--                            Updates mid-dash, every kit back in its pool (keep size) after
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min, sqrt, floor, huge = math.abs, math.max, math.min, math.sqrt, math.floor, math.huge
local fmt = string.format

local function dist(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	return sqrt(dx * dx + dz * dz)
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function req(name)
		local inst = K.moduleInstance("shared/" .. name)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	local function load(tag)
		local BC, BS = req("BattleCatalog"), req("BattleSim")
		if not T.check(BC ~= nil and BS ~= nil and type(BC.Damage) == "table", tag .. ": BattleCatalog + BattleSim load") then
			return nil
		end
		return BC, BS
	end

	-- a Duel: my team (`mine` pet keys, Auto or a standing fighter) vs NPC pets at the given spots
	local function duel(BS, mine, auto, foes, spots, seed, zone)
		local foeList = {}
		for i = 1, #foes do
			foeList[i] = { Key = foes[i], Level = 18, NoSpecial = true, Slot = i }
		end
		local b = BS.new({ Mode = "Duel", Seed = seed or 7, Zone = zone or { X = 160, Z = 160 }, TimeLimit = 300,
			Teams = { { Owner = 1, Side = 1, Pets = { { Key = mine, Level = 20, Slot = 1 } }, Auto = auto },
				{ Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = foeList } } })
		if not b then
			return nil
		end
		local tm = b.teams[1]
		local f = tm.fighter
		f.x, f.z, f.px, f.pz = 0, 0, 0, 0
		f.maxHp, f.hp = 1e9, 1e9
		tm.wantX, tm.wantZ = 0, 0
		tm.elementReadyAt = huge
		if not auto then
			tm.noEngage = true -- (my fighter stands: the NPC walks)
		end
		local on = {}
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				on[#on + 1] = u
				local p = spots[#on]
				u.x, u.z, u.px, u.pz = p[1], p[2], p[1], p[2]
				u.maxHp, u.hp = 1e9, 1e9
			end
		end
		return b, tm, f, on
	end

	-- steps `seconds` at 10 Hz; my fighter never casts (meter 0) and, standing, never swings unless `swing`
	local function run(b, tm, f, seconds, swing, onStep)
		for _ = 1, floor(seconds / 0.1 + 0.5) do
			f.meter = 0
			if not tm.auto and not swing then
				f.nextAttack = huge
				tm.wantX, tm.wantZ = 0, 0
			end
			local evs = b:Step(0.1)
			if onStep then
				onStep(evs, b:Time())
			end
		end
	end

	local function withStandoff(BC, so, fn)
		local keep = BC.Damage.Standoff
		BC.Damage.Standoff = so
		local ok, err = pcall(fn)
		BC.Damage.Standoff = keep
		if not ok then
			error(err, 0)
		end
	end

	S.feel_standoff_rest = guarded("feel_standoff_rest", function()
		local BC, BS = load("feel standoff rest")
		if not BC then
			return
		end
		local Config = req("Config")
		local knob = Config and Config.Battle and Config.Battle.Feel and Config.Battle.Feel.Melee and Config.Battle.Feel.Melee.Standoff
		T.check(type(knob) == "number" and BC.Damage.Standoff == knob, fmt("feel standoff: BattleCatalog.Damage.Standoff = Config.Battle.Feel.Melee.Standoff (%s / %s)", tostring(BC.Damage.Standoff), tostring(knob)))
		local so8 = 8
		for _, so in ipairs({ so8, 0 }) do
			withStandoff(BC, so, function()
				-- (a) the harness fighter (Auto, melee) walks to a standing bear
				local b, tm, f, on = duel(BS, "storm_tabby", true, { "biscuit_bear" }, { { 0, 30 } })
				local bear = on[1]
				bear.moveSpeed, bear.nextAttack = 0, huge
				run(b, tm, f, 6)
				local want = f.range + bear.radius + so - 0.5
				local d = dist(f.x, f.z, bear.x, bear.z)
				T.check(not f.ranged and abs(d - want) <= 0.3, fmt("feel standoff (Standoff %d): the harness melee fighter rests at reach + %d - 0.5 of a standing bear (%.2f, want %.2f)", so, so, d, want))
				-- (b) an NPC melee pet walks to my standing fighter
				local b2, tm2, f2, on2 = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } })
				local npc = on2[1]
				run(b2, tm2, f2, 6)
				-- (an NPC stops walking once inside its reach: it rests between the orbit's reach - 0.5 and reach)
				local want2 = npc.range + f2.radius + so
				local d2 = dist(f2.x, f2.z, npc.x, npc.z)
				T.check(not npc.ranged and d2 >= want2 - 0.8 and d2 <= want2 + 0.05, fmt("feel standoff (Standoff %d): an NPC melee pet rests at reach + %d (- 0.5 .. 0) of my standing fighter (%.2f, want %.2f)", so, so, d2, want2))
				-- (c) a ranged NPC holds at the edge of its range as today
				local b3, tm3, f3, on3 = duel(BS, "storm_tabby", false, { "puddle_frog" }, { { 0, 40 } })
				local frog = on3[1]
				run(b3, tm3, f3, 6)
				local want3 = frog.range + f3.radius - 0.3
				local d3 = dist(f3.x, f3.z, frog.x, frog.z)
				T.check(frog.ranged and abs(d3 - want3) <= 0.3, fmt("feel standoff (Standoff %d): a ranged NPC holds at reach - 0.3 (no standoff) (%.2f, want %.2f)", so, d3, want3))
			end)
		end
	end)

	S.feel_standoff_dps = guarded("feel_standoff_dps", function()
		local BC, BS = load("feel standoff dps")
		if not BC then
			return
		end
		local D = BC.Damage
		local function fighterFight(so)
			local hits, first = 0, nil
			withStandoff(BC, so, function()
				local b, tm, f, on = duel(BS, "storm_tabby", true, { "biscuit_bear" }, { { 0, 30 } }, 11)
				local bear = on[1]
				bear.moveSpeed, bear.nextAttack = 0, huge
				local t0 = b:Time()
				run(b, tm, f, 30, true, function(evs, t)
					for _, ev in ipairs(evs) do
						if ev.type == "Hit" and ev.from == f.id and not ev.miss and not ev.special and not ev.element then
							hits = hits + 1
							first = first or (t - t0)
						end
					end
				end)
			end)
			return hits, first
		end
		local function npcFight(so)
			local hits, first, worst, reachMax = 0, nil, 0, 0
			withStandoff(BC, so, function()
				local b, tm, f, on = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } }, 11)
				local bear = on[1]
				reachMax = bear.range + f.radius + so + D.EngageSlack + 1.0
				local t0 = b:Time()
				run(b, tm, f, 30, false, function(evs, t)
					for _, ev in ipairs(evs) do
						if ev.type == "Hit" and ev.from == bear.id and not ev.miss and not ev.special then
							hits = hits + 1
							first = first or (t - t0)
							worst = max(worst, dist(bear.x, bear.z, f.x, f.z))
						end
					end
				end)
			end)
			return hits, first, worst, reachMax
		end
		local h8, f8 = fighterFight(8)
		local h0, f0 = fighterFight(0)
		T.check(h8 > 5 and h0 > 5 and abs(h8 - h0) <= 1, fmt("feel standoff dps: the harness melee fighter lands as many hits in 30 s at Standoff 8 as at 0 (%d vs %d)", h8, h0))
		T.check(f8 ~= nil and f0 ~= nil and f8 <= f0 + 1e-6, fmt("feel standoff dps: ... its first hit no later at 8 (a shorter walk) (%s vs %s s)", tostring(f8), tostring(f0)))
		local n8, g8, w8, r8 = npcFight(8)
		local n0, g0 = npcFight(0)
		T.check(n8 > 5 and n0 > 5 and abs(n8 - n0) <= 1, fmt("feel standoff dps: an NPC melee pet lands as many hits in 30 s at Standoff 8 as at 0 (%d vs %d)", n8, n0))
		T.check(g8 ~= nil and g0 ~= nil and g8 <= g0 + 1e-6, fmt("feel standoff dps: ... its first hit no later at 8 (%s vs %s s)", tostring(g8), tostring(g0)))
		T.check(w8 <= r8 + 1e-6, fmt("feel standoff dps: every NPC hit lands within reach + 8 + EngageSlack + 1.0 (worst %.2f, max %.2f)", w8, r8))
	end)

	S.feel_standoff_zone = guarded("feel_standoff_zone", function()
		local BC, BS = load("feel standoff zone")
		if not BC then
			return
		end
		local b, tm, f, on
		local wound = {}
		withStandoff(BC, 8, function()
			b, tm, f, on = duel(BS, "puddle_frog", false, { "biscuit_bear", "biscuit_bear", "biscuit_bear" }, { { -6, 20 }, { 0, 20 }, { 6, 20 } }, 5, { X = 44, Z = 44 })
			if b and #on == 3 then
				run(b, tm, f, 8, false, function(evs)
					for _, ev in ipairs(evs) do
						if ev.type == "Windup" then
							wound[ev.unit] = true
						end
					end
				end)
			end
		end)
		if not T.check(b ~= nil and #on == 3, "feel standoff zone: (Standoff 8) a 44 x 44 floor, three NPC melee pets") then
			return
		end
		local inside, apart, all = true, huge, true
		for i, u in ipairs(on) do
			inside = inside and abs(u.x) <= 22 + 1e-6 and abs(u.z) <= 22 + 1e-6
			all = all and wound[u.id] == true
			for j = i + 1, #on do
				apart = min(apart, dist(u.x, u.z, on[j].x, on[j].z))
			end
		end
		T.check(inside, "feel standoff zone: every rest spot is on the floor")
		T.check(apart >= 2.4, fmt("feel standoff zone: the three rest at least 2.4 studs apart (closest %.2f)", apart))
		T.check(all, "feel standoff zone: all three wind up (attack) by 8 s")
	end)

	S.feel_standoff_wire = guarded("feel_standoff_wire", function()
		local BC, BS = load("feel standoff wire")
		if not BC then
			return
		end
		T.check(select(1, BC.Validate()) == true, "feel standoff wire: BattleCatalog.Validate passes")
		local keep = BC.Damage.Standoff
		local bad = {}
		for _, v in ipairs({ -1, "x", 25 }) do
			BC.Damage.Standoff = v
			if BC.Validate() ~= false then
				bad[#bad + 1] = tostring(v)
			end
		end
		BC.Damage.Standoff = keep
		T.check(#bad == 0, "feel standoff wire: Validate catches a Standoff of -1 / \"x\" / 25 (a number 0..20)", table.concat(bad, ", "))
		-- nothing new on the wire: the Windup event is type / unit / target / at as before
		local b, tm, f = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } })
		local extra = {}
		run(b, tm, f, 6, false, function(evs)
			for _, ev in ipairs(evs) do
				if ev.type == "Windup" then
					for k in pairs(ev) do
						if k ~= "type" and k ~= "unit" and k ~= "target" and k ~= "at" then
							extra[#extra + 1] = k
						end
					end
				end
			end
		end)
		T.check(#extra == 0 and BS.Events.Windup == "Windup", "feel standoff wire: the Windup event carries type / unit / target / at only", table.concat(extra, ", "))
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local LocalPlayer = game:GetService("Players").LocalPlayer
	local V3 = Vector3.new
	local G = 3

	local function moduleAt(path)
		local ok, inst = pcall(Mock.GetPath, path)
		if not ok or not inst then
			return nil
		end
		local ok2, mod = pcall(require, inst)
		return ok2 and type(mod) == "table" and mod or nil
	end

	local function fakeMeshLibrary()
		return {
			IsReady = function(key)
				return type(key) == "string" and string.sub(key, 1, 4) == "vfx_"
			end,
			Assemble = function(spec)
				local key = type(spec) == "string" and spec or (type(spec) == "table" and spec.Key) or "?"
				local m = Instance.new("Model")
				m.Name = key
				local p = Instance.new("MeshPart")
				p.Name = "Core"
				p.Size = V3(2, 2, 2)
				p.Anchored = true
				p.Parent = m
				return m
			end,
		}
	end

	local function unitModel(parent, name, pos, size)
		local m = Instance.new("Model")
		m.Name = name
		local root = Instance.new("Part")
		root.Name = "Body"
		root.Anchored = true
		root.Size = size or V3(2, 2, 2)
		root.CFrame = CFrame.new(pos)
		root.Parent = m
		m.PrimaryPart = root
		m.Parent = parent
		return m
	end

	-- a pose's whole forward offset (pose studs): the PetPoses body's -Z plus the held edge (Forward)
	local function fwdOf(PP, pose)
		if type(pose) ~= "table" or type(pose.Name) ~= "string" then
			return 0
		end
		local s = PP.Sample(pose.Name, pose.P, pose.Ranged, pose.Amp, pose.Reach)
		return -s.Body.Position.Z + (tonumber(pose.Forward) or 0)
	end

	-- the AttackFx world on a fake clock (smoke_feel_aim's)
	local function setup(tag)
		local env = {}
		env.AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		env.Config = moduleAt(ROOTS.shared .. "/Config")
		env.PP = moduleAt(ROOTS.shared .. "/PetPoses")
		env.BB = moduleAt(ROOTS.shared .. "/BossBuilder")
		local AF = env.AF
		if not T.check(AF ~= nil and env.Config ~= nil and env.PP ~= nil, tag .. ": AttackFx, Config, PetPoses load") then
			return nil
		end
		local M = env.Config.Battle and env.Config.Battle.Feel and env.Config.Battle.Feel.Melee
		if not T.check(type(M) == "table" and type(AF.Dash) == "function" and type(AF.DashState) == "function",
			tag .. ": Config.Battle.Feel.Melee, AttackFx.Dash and AttackFx.DashState exist") then
			return nil
		end
		env.M = M
		env.saved = {}
		for k, v in pairs(M) do
			env.saved[k] = v
		end
		AF.ClearAll()
		AF._Deps({ MeshLibrary = fakeMeshLibrary() })
		AF.SetQuality("High")
		local cb = workspace:FindFirstChild("ClientBattle")
		if not cb then
			cb = Instance.new("Folder")
			cb.Name = "ClientBattle"
			cb.Parent = workspace
		end
		env.holder = Instance.new("Folder")
		env.holder.Name = "SmokeFeelDash_" .. tag
		env.holder.Parent = cb
		env.clock = 9000
		env.DT = 1 / 30
		AF.Update(env.clock)
		function env.run(seconds, each)
			local n = math.ceil(seconds / env.DT - 1e-9)
			for _ = 1, n do
				env.clock = env.clock + env.DT
				AF.Update(env.clock)
				if each then
					each(env.clock)
				end
			end
		end
		function env.runTo(at, each)
			while env.clock + env.DT <= at + 1e-9 do
				env.clock = env.clock + env.DT
				AF.Update(env.clock)
				if each then
					each(env.clock)
				end
			end
		end
		function env.fwd(unit)
			return fwdOf(env.PP, AF.Pose(unit))
		end
		function env.done()
			AF.ClearAll()
			AF._Deps({ MeshLibrary = false })
			AF.SetQuality(nil)
			for k, v in pairs(env.saved) do
				M[k] = v
			end
			pcall(env.holder.Destroy, env.holder)
		end
		return env
	end

	-- two pet stand-ins 12 studs apart: the gap = 12 - 1 - 1 - LEAP_MARGIN 0.3
	local function pair(env, x, unit)
		local a = unitModel(env.holder, "A" .. unit, V3(x, G + 1.5, 0))
		local b = unitModel(env.holder, "B" .. unit, V3(x, G + 1.5, -12))
		return { Unit = unit, Model = a, Pos = V3(x, G + 1.5, 0) }, { Unit = unit + 1000, Model = b, Pos = V3(x, G + 1.5, -12) }
	end

	----------------------------------------------------------------------------------------------
	S.client_feel_dash_flurry = guarded("client_feel_dash_flurry", function()
		local env = setup("flurry")
		if not env then
			return
		end
		local AF, M = env.AF, env.M
		local ok, err = pcall(function()
			local src, tgt = pair(env, 0, 1)
			local edge = AF.LeapReach({ Model = src.Model, Last = src.Pos }, { Model = tgt.Model, Last = tgt.Pos })
			T.check(edge ~= nil and abs(edge - 9.7) < 0.05, fmt("feel dash flurry: (setup) the gap to the edge is 9.7 studs (%s)", tostring(edge)))
			-- three attacks 0.64 s apart (a Storm pet's Charge tempo); the windup lands each 0.45 s after its request
			local starts = { env.clock + 0.05, env.clock + 0.69, env.clock + 1.33 }
			local tempos = { nil, 0.64, 0.64 }
			local results, states = {}, {}
			for i = 1, 3 do
				env.runTo(starts[i])
				states[i] = AF.DashState(1)
				results[i] = AF.Dash(1, src, tgt, starts[i] + 0.45, env.clock, { Tempo = tempos[i] })
			end
			T.check(results[1] and results[2] and results[3] and states[1] == "out", fmt("feel dash flurry: three Dash calls taken (%s %s %s), the first from \"out\"", tostring(results[1]), tostring(results[2]), tostring(results[3])))
			T.check(states[3] == "in", fmt("feel dash flurry: the third attack (0.64 s after the second) finds the pet still in (%s)", tostring(states[3])))
			local land3 = starts[3] + 0.45
			env.runTo(land3)
			local pose = AF.Pose(1)
			T.check(pose ~= nil and pose.Name == "Strike" and pose.Reach ~= nil and abs(pose.Reach - M.Lunge) < 1e-6 and abs((pose.Forward or 0) - edge) < 0.05,
				fmt("feel dash flurry: the flurry bites in place: a Strike lunge of Lunge 0.6 on Forward = the edge (%s, reach %s, forward %s)",
					tostring(pose and pose.Name), tostring(pose and pose.Reach), tostring(pose and pose.Forward)))
			local backAt = land3 + M.FlurryBelow
			env.runTo(backAt - 0.05)
			T.check(AF.DashState(1) == "in", fmt("feel dash flurry: still in until FlurryBelow 0.75 s after the last landing (%s)", AF.DashState(1)))
			env.runTo(backAt + 0.1)
			T.check(AF.DashState(1) == "back" and AF.Pose(1) ~= nil and AF.Pose(1).Name == "DashBack", fmt("feel dash flurry: ... then the hop back (%s)", AF.DashState(1)))
			env.runTo(backAt + M.Back + 0.05)
			T.check(AF.DashState(1) == "out" and AF.Pose(1) == nil, fmt("feel dash flurry: ... and back at the rest spot (%s)", AF.DashState(1)))
			-- attacks 1.1 s apart: a full round trip each time
			local trips, sawBack = 0, 0
			local nextAt = env.clock + 0.05
			for _ = 1, 3 do
				env.runTo(nextAt)
				local now = env.clock
				local before = AF.DashState(1)
				local land = now + 0.45
				if AF.Dash(1, src, tgt, land, now, { Tempo = 1.1 }) and before == "out" then
					trips = trips + 1
				end
				env.runTo(land + M.Bite + M.Hold + 0.1)
				if AF.DashState(1) == "back" then
					sawBack = sawBack + 1
				end
				nextAt = now + 1.1
			end
			T.check(trips == 3 and sawBack == 3, fmt("feel dash flurry: attacks 1.1 s apart: a full round trip each time (%d from out, %d hops back)", trips, sawBack))
		end)
		env.done()
		T.check(ok, "feel dash flurry: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	S.client_feel_dash_off = guarded("client_feel_dash_off", function()
		local env = setup("off")
		if not env then
			return
		end
		local AF, M = env.AF, env.M
		local ok, err = pcall(function()
			-- a pet already at the edge (gap 1.2 < MinGap 3): no dash
			local a = unitModel(env.holder, "Near", V3(0, G + 1.5, 0))
			local b = unitModel(env.holder, "NearT", V3(0, G + 1.5, -3.5))
			local r = AF.Dash(1, { Unit = 1, Model = a, Pos = V3(0, G + 1.5, 0) }, { Unit = 2, Model = b, Pos = V3(0, G + 1.5, -3.5) }, env.clock + 0.45, env.clock, {})
			T.check(r == false and AF.Pose(1) == nil and AF.DashState(1) == "out", "feel dash off: a gap under MinGap 3 studs: Dash returns false (today's Strike), no pose")
			-- Melee.Dash = false: false
			local src, tgt = pair(env, 20, 3)
			M.Dash = false
			T.check(AF.Dash(3, src, tgt, env.clock + 0.45, env.clock, {}) == false and AF.Pose(3) == nil, "feel dash off: Melee.Dash = false: Dash returns false")
			M.Dash = true
			-- "no hit": a dash whose hit never comes still bites and returns; no unit is left held in
			local errors0 = AF.Stats().Errors
			local land = env.clock + 0.45
			T.check(AF.Dash(3, src, tgt, land, env.clock, {}) == true, "feel dash off: a dash with no hit after it is taken")
			local streaks = AF.Stats().Streaks
			T.check(streaks == 1, fmt("feel dash off: High: one speed streak rides it (%s)", tostring(streaks)))
			local sawIn = false
			env.runTo(land - 0.1, function()
				local p = AF.Pose(3)
				sawIn = sawIn or (p ~= nil and p.Name == "DashIn")
			end)
			env.runTo(land + M.Bite + M.Hold + M.Back + 0.02)
			T.check(sawIn and AF.DashState(3) == "out" and AF.Pose(3) == nil and AF.Stats().Errors == errors0,
				fmt("feel dash off: no hit: DashIn, then out by landAt + 0.60, no error (%s)", AF.DashState(3)))
			T.check(AF.Stats().Streaks == 0, "feel dash off: ... and its streak is back in the pool")
			-- Low graphics: the dash runs, no streak
			AF.SetQuality("Low")
			AF.Update(env.clock)
			local land2 = env.clock + 0.45
			T.check(AF.Dash(3, src, tgt, land2, env.clock, { Low = true }) == true and AF.Stats().Streaks == 0, "feel dash off: Low graphics: the dash runs, no Trail kit taken")
			env.runTo(land2)
			T.check(AF.DashState(3) == "in" and abs(env.fwd(3) - 9.7) < 0.1, fmt("feel dash off: Low: at the edge at the landing (%.2f)", env.fwd(3)))
			AF.SetQuality("High")
			env.run(1)
		end)
		env.done()
		T.check(ok, "feel dash off: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	S.client_feel_dash_budget = guarded("client_feel_dash_budget", function()
		local env = setup("budget")
		if not env then
			return
		end
		local AF = env.AF
		local ok, err = pcall(function()
			local boss = env.BB and env.BB.Build("lava_golem", { Detail = "Low", CFrame = CFrame.new(0, G, -30) })
			if not T.check(boss ~= nil, "feel dash budget: (setup) a lava golem") then
				return
			end
			boss.Parent = env.holder
			local tgt = { Unit = 900, Model = boss, Pos = boss:GetPivot().Position }
			local land = env.clock + 0.45
			local taken = 0
			for i = 1, 8 do
				local x = (i - 4.5) * 4
				local m = unitModel(env.holder, "Pet" .. i, V3(x, G + 1.5, 0))
				if AF.Dash(i, { Unit = i, Model = m, Pos = V3(x, G + 1.5, 0) }, tgt, land, env.clock, { Mine = (i == 8) }) then
					taken = taken + 1
				end
			end
			local s = AF.Stats()
			local _, mine = AF.DashState(8)
			T.check(taken == 8 and s.Streaks == 4, fmt("feel dash budget: eight dashes in one frame: all taken, %d streaks (StreakMax 4)", s.Streaks or -1))
			T.check(type(mine) == "table" and mine.Streak == true, "feel dash budget: my pet's dash keeps a streak at the cap (mine first)")
			env.runTo(land - 0.15)
			local n1 = #workspace:GetDescendants()
			env.run(env.DT)
			local n2 = #workspace:GetDescendants()
			T.check(n1 == n2, fmt("feel dash budget: no new Instance between two Updates mid-dash (%d vs %d)", n1, n2))
			env.runTo(land + 1)
			local s2 = AF.Stats()
			local folder = AF.Folder()
			T.check(s2.Streaks == 0 and s2.Trails == 0 and s2.Pooled <= AF.POOL_KEEP_TOTAL and s2.PoolInstances == #folder:GetDescendants(),
				fmt("feel dash budget: after: no streak live, every kit pooled within the keep (%d pooled / %d, %d instances vs folder %d)", s2.Pooled, AF.POOL_KEEP_TOTAL, s2.PoolInstances, #folder:GetDescendants()))
			local allOut = true
			for i = 1, 8 do
				allOut = allOut and AF.DashState(i) == "out"
			end
			T.check(allOut, "feel dash budget: all eight back out")
		end)
		env.done()
		T.check(ok, "feel dash budget: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- the BattleController half: a real BattleSim stepped at 10 Hz, sent the way BattleService sends it
	----------------------------------------------------------------------------------------------
	local function driver(BS, myKey, foeKey, auto)
		local me = LocalPlayer.UserId
		local id = "feel_dash_" .. tostring(math.random(100000, 999999))
		local sim = BS.new({ Mode = "Duel", Seed = 13, Id = id, Zone = { X = 60, Z = 60 }, TimeLimit = 120,
			Teams = { { Owner = me, Side = 1, Pets = { { Key = myKey, PetId = myKey, Level = 20, Tier = "Normal", Slot = 1 } }, Auto = auto },
				{ Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = { { Key = foeKey, Level = 18, NoSpecial = true, Slot = 1 } } } } })
		if not sim then
			return nil
		end
		local d = { sim = sim, id = id, me = me, last = {} }
		local tm = sim.teams[1]
		d.tm, d.f = tm, tm.fighter
		d.f.x, d.f.z, d.f.px, d.f.pz = 0, -8, 0, -8
		d.f.maxHp, d.f.hp = 1e9, 1e9
		tm.wantX, tm.wantZ = 0, -8
		tm.elementReadyAt = huge
		for _, u in ipairs(sim.units) do
			if u.side == 2 then
				d.foe = u
				u.x, u.z, u.px, u.pz = 0, 14, 0, 14
				u.maxHp, u.hp = 1e9, 1e9
			end
		end
		local p = sim:Describe()
		p.BattleId = id
		p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = V3(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
		p.Names = { [tostring(me)] = LocalPlayer.Name }
		p.Side, p.Spectator, p.T = 1, false, sim:Time()
		local team = sim:TeamOf(me)
		if team then
			p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
				Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = {} } }
		end
		LocalPlayer:SetAttribute("InBattle", id)
		KC.toClient("BattleState", "Start", p, id)
		function d.step(each)
			d.f.meter = 0
			local evs = sim:Step(0.1)
			if #evs > 0 then
				KC.toClient("BattleState", "Events", evs, id)
			end
			local snap = sim:SnapshotDelta(d.last)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			for _ = 1, 3 do
				Mock.Step(0.1 / 3)
				if each then
					each()
				end
			end
			return evs
		end
		function d.finish()
			KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, id)
			LocalPlayer:SetAttribute("InBattle", nil)
			KC.advance(15)
			Mock.Step(0.1)
		end
		return d
	end

	-- spies on AttackFx.Dash / Play / Update and BattleController's damage numbers; undo() puts them back
	local function spies(AF, BC, PP, watch)
		local sp = { dash = {}, play = {}, frames = {}, numbers = {} }
		local realDash, realPlay, realUpdate = AF.Dash, AF.Play, AF.Update
		local Fx = BC._Fx
		local realNumber = Fx and Fx.Number
		AF.Dash = function(unit, src, tgt, landAt, now, opts)
			local r = realDash(unit, src, tgt, landAt, now, opts)
			sp.dash[#sp.dash + 1] = { Unit = unit, LandAt = landAt, Now = now, At = os.clock(), Result = r, Mine = type(opts) == "table" and opts.Mine or nil }
			return r
		end
		AF.Play = function(ctx)
			local c = { Attack = ctx.Attack, From = type(ctx.From) == "table" and ctx.From.Unit or nil, DueAt = ctx.DueAt, Dashed = ctx.Dashed == true, At = os.clock() }
			c.Result = realPlay(ctx)
			sp.play[#sp.play + 1] = c
			return c.Result
		end
		AF.Update = function(now)
			realUpdate(now)
			for _, unit in ipairs(watch) do
				local pose = AF.Pose(unit)
				sp.frames[#sp.frames + 1] = { Unit = unit, T = now, Name = pose and pose.Name or nil, Fwd = fwdOf(PP, pose), State = AF.DashState(unit) }
			end
		end
		if Fx and realNumber then
			Fx.Number = function(adornee, height, text, color, px, life)
				sp.numbers[#sp.numbers + 1] = { Text = tostring(text), At = os.clock() }
				return realNumber(adornee, height, text, color, px, life)
			end
		end
		function sp.undo()
			AF.Dash, AF.Play, AF.Update = realDash, realPlay, realUpdate
			if Fx and realNumber then
				Fx.Number = realNumber
			end
		end
		return sp
	end

	local function frameAt(sp, unit, t)
		local best, bd = nil, huge
		for _, f in ipairs(sp.frames) do
			if f.Unit == unit and abs(f.T - t) < bd then
				best, bd = f, abs(f.T - t)
			end
		end
		return best
	end

	local function loadBattle(tag)
		local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
		local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local BS = moduleAt(ROOTS.shared .. "/BattleSim")
		local PP = moduleAt(ROOTS.shared .. "/PetPoses")
		local Config = moduleAt(ROOTS.shared .. "/Config")
		local M = Config and Config.Battle and Config.Battle.Feel and Config.Battle.Feel.Melee
		if not T.check(BC ~= nil and AF ~= nil and BS ~= nil and PP ~= nil and type(M) == "table" and type(AF.Dash) == "function" and type(AF.DashState) == "function",
			tag .. ": BattleController, AttackFx (Dash, DashState), BattleSim, PetPoses, Config.Battle.Feel.Melee load") then
			return nil
		end
		AF.SetQuality("High")
		return BC, AF, BS, PP, M
	end

	-- the client world's BattleCatalog (the driver's sim reads it) at Standoff `so` for fn, put back after
	local function atStandoff(so, fn)
		local BCat = moduleAt(ROOTS.shared .. "/BattleCatalog")
		local keep = BCat and BCat.Damage.Standoff
		if BCat then
			BCat.Damage.Standoff = so
		end
		local ok, err = pcall(fn)
		if BCat then
			BCat.Damage.Standoff = keep
		end
		if not ok then
			error(err, 0)
		end
	end

	S.client_feel_dash_npc = guarded("client_feel_dash_npc", function()
		local BC, AF, BS, PP, M = loadBattle("feel dash npc")
		if not BC then
			return
		end
		atStandoff(8, function()
		local d = driver(BS, "puddle_frog", "biscuit_bear", false)
		if not T.check(d ~= nil and d.foe ~= nil, "feel dash npc: (setup) a Duel at Standoff 8: my standing frog vs an NPC bear") then
			return
		end
		d.tm.noEngage = true
		local foe, mine = d.foe.id, d.f.id
		local sp = spies(AF, BC, PP, { foe, mine })
		local ok, err = pcall(function()
			local windAt = nil
			for _ = 1, 100 do
				d.f.nextAttack = huge
				d.tm.wantX, d.tm.wantZ = 0, -8
				local evs = d.step()
				for _, ev in ipairs(evs) do
					if ev.type == "Windup" and ev.unit == foe and not windAt then
						windAt = ev.at
					end
				end
				local got = false
				for _, c in ipairs(sp.dash) do
					got = got or (c.Unit == foe and c.Result == true)
				end
				if got then
					break
				end
			end
			local call = nil
			for _, c in ipairs(sp.dash) do
				if c.Unit == foe and c.Result == true then
					call = c
					break
				end
			end
			if not T.check(windAt ~= nil and call ~= nil, fmt("feel dash npc: the bear's Windup dashes it (AttackFx.Dash taken; Windup at %s)", tostring(windAt))) then
				return
			end
			local _, info = AF.DashState(foe)
			local edge = type(info) == "table" and info.Reach or nil
			T.check(call.LandAt - call.At > 0.25 and call.LandAt - call.At < 0.6, fmt("feel dash npc: the dash lands on ev.at on the render clock (%.2f s after the Windup played)", call.LandAt - call.At))
			for _ = 1, 12 do
				d.step()
			end
			local fl = frameAt(sp, foe, call.LandAt)
			T.check(fl ~= nil and fl.Name == "DashIn" and edge ~= nil and abs(fl.Fwd - edge) < 0.35,
				fmt("feel dash npc: at the landing the bear is in DashIn at the edge (%s, %.2f of %s studs)", tostring(fl and fl.Name), fl and fl.Fwd or -1, tostring(edge)))
			local before = frameAt(sp, foe, call.LandAt - 0.12)
			T.check(before ~= nil and before.Name == "DashIn" and before.Fwd > 0.5, fmt("feel dash npc: ... running in before the hit (%s, %.2f)", tostring(before and before.Name), before and before.Fwd or -1))
			local hit = nil
			for _, c in ipairs(sp.play) do
				if c.From == foe and c.Attack == "Melee" and c.At >= call.At - 1e-6 then
					hit = c
					break
				end
			end
			T.check(hit ~= nil and hit.Result == true and hit.Dashed == true and abs(hit.DueAt - call.LandAt) < 0.2,
				fmt("feel dash npc: its Hit plays Dashed, the impact on the landing (due %s vs land %.2f)", tostring(hit and hit.DueAt), call.LandAt))
			local strike, hurt = false, false
			for _, f in ipairs(sp.frames) do
				if f.Unit == foe and f.T >= call.At and f.T <= call.LandAt + 0.6 and f.Name == "Strike" then
					strike = true
				end
				if f.Unit == mine and f.T >= call.LandAt - 0.2 and f.T <= call.LandAt + 0.5 and f.Name == "Hurt" then
					hurt = true
				end
			end
			T.check(not strike, "feel dash npc: ... with NO Strike segment (the dash is the attack)")
			T.check(hurt, "feel dash npc: my pet flinches (Hurt) at the impact")
			local back = frameAt(sp, foe, call.LandAt + M.Bite + M.Hold + 0.08)
			T.check(back ~= nil and back.Name == "DashBack", fmt("feel dash npc: DashBack from landAt + 0.20 (%s)", tostring(back and back.Name)))
			local out = frameAt(sp, foe, call.LandAt + M.Bite + M.Hold + M.Back + 0.06)
			T.check(out ~= nil and out.State == "out", fmt("feel dash npc: out by landAt + 0.60 (%s)", tostring(out and out.State)))
		end)
		sp.undo()
		d.finish()
		T.check(ok, "feel dash npc: no error", tostring(err))
		end)
	end)

	S.client_feel_dash_mine = guarded("client_feel_dash_mine", function()
		local BC, AF, BS, PP, M = loadBattle("feel dash mine")
		if not BC then
			return
		end
		local function fight(dashOn)
			M.Dash = dashOn
			local d = driver(BS, "storm_tabby", "biscuit_bear", false)
			if not d then
				M.Dash = true
				return nil
			end
			d.foe.moveSpeed, d.foe.nextAttack = 0, huge
			local mine = d.f.id
			local sp = spies(AF, BC, PP, { mine })
			local res = {}
			local ok, err = pcall(function()
				for _ = 1, 90 do
					d.foe.nextAttack = huge
					d.step()
					local n = 0
					for _, c in ipairs(sp.play) do
						if c.From == mine and c.Attack == "Melee" then
							n = n + 1
						end
					end
					if n >= 2 then
						break
					end
				end
				for _ = 1, 8 do
					d.step()
				end
				for _, c in ipairs(sp.play) do
					if c.From == mine and c.Attack == "Melee" then
						res.play = c
						break
					end
				end
				for _, c in ipairs(sp.dash) do
					if c.Unit == mine then
						res.dash = c
						break
					end
				end
				if res.play then
					-- the first number after the play's arrival (my hit on the bear)
					for _, n in ipairs(sp.numbers) do
						if n.At >= res.play.At - 1e-6 and tonumber(n.Text) then
							res.number = n
							break
						end
					end
				end
				local strike, dashIn = false, false
				for _, f in ipairs(sp.frames) do
					strike = strike or f.Name == "Strike"
					dashIn = dashIn or f.Name == "DashIn"
				end
				res.strike, res.dashIn = strike, dashIn
			end)
			sp.undo()
			d.finish()
			M.Dash = true
			if not ok then
				error(err, 0)
			end
			return res
		end
		local on, off
		atStandoff(8, function()
			on = fight(true)
			off = fight(false)
		end)
		if not T.check(on ~= nil and on.play ~= nil, "feel dash mine: my melee fighter attacks the bear (a Melee play)") then
			return
		end
		T.check(on.dash ~= nil and on.dash.Result == true and on.play.Dashed and abs(on.dash.LandAt - on.play.DueAt) < 1e-6 and on.dash.Mine == true,
			fmt("feel dash mine: my fighter's Hit (no Windup) dashes it: Dash lands at the play's DueAt (%s vs %s), Dashed, Mine",
				tostring(on.dash and on.dash.LandAt), tostring(on.play.DueAt)))
		T.check(on.play.DueAt - on.play.At >= M.In - 1e-6, fmt("feel dash mine: the impact is held In 0.30 s past the event (%.2f s after its arrival)", on.play.DueAt - on.play.At))
		T.check(on.number ~= nil and on.number.At >= on.play.DueAt - 0.06, fmt("feel dash mine: the damage number plays with the impact, 0.30 s late (fxLate) (number %.2f vs impact %.2f)",
			on.number and on.number.At or -1, on.play.DueAt))
		T.check(on.dashIn, "feel dash mine: my pet's pose is DashIn")
		if not T.check(off ~= nil and off.play ~= nil, "feel dash mine: (Melee.Dash = false) my fighter attacks") then
			return
		end
		T.check((off.dash == nil or off.dash.Result == false) and not off.play.Dashed and not off.dashIn and off.strike,
			"feel dash mine: Melee.Dash = false: no dash, today's Strike")
		T.check(off.play.DueAt - off.play.At < M.In - 0.05 and off.number ~= nil and off.number.At <= off.play.DueAt + 0.06,
			fmt("feel dash mine: ... the impact and the number at the event (fxLate 0) (due +%.2f, number %.2f vs %.2f)", off.play.DueAt - off.play.At, off.number and off.number.At or -1, off.play.DueAt))
		-- the shipped knob (Config.Battle.Feel.Melee.Standoff, 0 in sleep mode): the pet rests at today's spot and dashes only
		-- across a gap of MinGap; either way the impact and the number agree (held In when dashed, at the event when not)
		local def = fight(true)
		if T.check(def ~= nil and def.play ~= nil, "feel dash mine: (the shipped Standoff) my fighter attacks") then
			local held = def.play.DueAt - def.play.At
			local agree = def.number ~= nil and abs(def.number.At - def.play.DueAt) < 0.07
			T.check(agree and ((def.play.Dashed and def.dashIn and held >= M.In - 1e-6) or (not def.play.Dashed and def.strike and held < M.In - 0.05)),
				fmt("feel dash mine: at the shipped Standoff the bite is a dash (held %.2f) or today's Strike, the number with the impact (dashed %s)", held, tostring(def.play.Dashed)))
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
