-- smoke_evo_retreat.lua: Retreat in boss raids (docs/superpowers/specs/2026-11-01-evolved-forms-design.md; plan Task 6), loaded by tools/smoke.py in
-- BOTH worlds (ARGS.context):
--   evo_retreat_core          (server world, pure) the sim: Retreat / Engage set the team state, the short dodge, no attacks and no meter while back,
--                             helper buttons work, a Swap or a KO keeps the team retreated, boss and minions skip a retreated pet while someone
--                             fights and turn back on it when nobody does, a telegraph already placed keeps its point, the lethal knocks out only
--                             the unit, the 10 s wait, Stunned / Casting / Dashing accepted, Down refused, NoRetreat outside a raid, Result / TeamOf
--   evo_docs                  (server world, pure) README, tools/README and BUILD_STATE know the whole build
--   evo_retreat_service       (server world, booted) the remote, the argument and spam rules, the Start payload, the leash's grace, the presence check
--   evo_retreat_pay           (server world, booted) the no-free-pet rule (the owner's choice 2026-11-02): per player, against the team's OWN time in
--                             the fight; the win's medal, Tokens, XP and clock stay, the Boss Raid pet roll goes, rw.SatOut + Reason say so
--   evo_retreat_flow          (server world, booted) solo, a pocket fight, a group of three, end to end
--   client_evo_retreat        (client world) the button and the R key: only in a raid, Retreat / Engage, one remote a press, the 10 s sweep, a refusal's
--                             shake, a late joiner's Start, Graphics Low, the result card's line
--   client_evo_retreat_mobile (phone world) the button on phones: >= 44 px, in the Cheer up! row, stacked above it or under the vitals card (where
--                             the stack would cover the fighter's cards or the screen's middle: every landscape phone, a portrait phone), clear of
--                             everything, out of the screen's middle
-- White-box: the sim's units and teams (same Lua state); the service's St is an upvalue of IsInBattle, as in smoke_raid_service.lua. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, huge, min = math.abs, math.floor, math.huge, math.min
local fmt = string.format

local function near(a, b, eps)
	return type(a) == "number" and abs(a - b) <= (eps or 1e-6)
end

----------------------------------------------------------------------------------------------------
-- the server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance = K.advance

	local function shared(name)
		local inst = K.moduleInstance("shared/" .. name)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	local function pets(n, key)
		local out = {}
		for i = 1, n do
			out[i] = { Key = key or "biscuit_bear", Level = 18, Slot = i }
		end
		return out
	end

	local function place(u, x, z)
		u.x, u.z, u.px, u.pz = x, z, x, z
	end

	-- a High storm_titan raid: player teams 1 and 2 (three pets each) stood 10 from the boss on either side, the boss quiet until a test wakes it
	local function raid(opts)
		opts = opts or {}
		local teams = { { Owner = 1, Side = 1, Pets = pets(3) }, { Owner = 2, Side = 1, Pets = pets(3) } }
		if opts.Minion then
			teams[3] = { Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = { { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = 1 } } }
		end
		local b = shared("BattleSim").new({ Mode = "Raid", Seed = 7, Boss = "storm_titan", RaidTier = "High", Zone = { X = 160, Z = 160 }, TimeLimit = 600, Teams = teams })
		if not b then
			return nil
		end
		local tm, tm2 = b.teamByOwner[1], b.teamByOwner[2]
		local boss = b.boss
		place(boss, 0, 0)
		boss.maxHp, boss.hp = 1e9, 1e9
		boss.nextAttack = huge
		boss.range = 20 -- (both fighters in the basic attack's reach, whoever it picks)
		for _, entry in ipairs(boss.attacks) do
			entry.nextAt = huge
		end
		if boss.lethal then
			boss.lethal.nextAt = huge
		end
		for _, u in ipairs(b.units) do
			if u.side == 1 then
				u.maxHp, u.hp = 1e7, 1e7
			end
		end
		place(tm.fighter, -10, 0)
		place(tm2.fighter, 10, 0)
		local minion = nil
		for _, u in ipairs(b.units) do
			if u.side == 2 and u.kind ~= "Boss" then
				minion = u
				place(u, -14, 0)
				u.moveSpeed, u.nextAttack, u.hit = 0, huge, 0
			end
		end
		return b, tm, tm.fighter, tm2, tm2.fighter, boss, minion
	end

	local function steps(b, seconds, each)
		local all = {}
		for _ = 1, floor(seconds / 0.1 + 0.5) do
			for _, ev in ipairs(b:Step(0.1)) do
				all[#all + 1] = ev
				if each then
					each(ev)
				end
			end
		end
		return all
	end

	local function count(events, fn)
		local n = 0
		for _, ev in ipairs(events) do
			if fn(ev) then
				n = n + 1
			end
		end
		return n
	end

	local function orders(events, owner, order)
		return count(events, function(ev)
			return ev.type == "Order" and ev.owner == owner and ev.order == order and ev.rejected == nil
		end), count(events, function(ev)
			return ev.type == "Order" and ev.owner == owner and ev.order == order and ev.rejected ~= nil
		end)
	end

	-- the telegraph event a woken attack casts (the battle time it lands), or nil
	local function castAttack(b, boss, entry)
		entry.nextAt = b:Time()
		for _, ev in ipairs(b:Step(0.1)) do
			if ev.type == "Telegraph" then
				return ev
			end
		end
		return nil
	end

	local function stepsUntil(b, t)
		local all = {}
		while b:Time() < t - 1e-9 do
			for _, ev in ipairs(b:Step(0.1)) do
				all[#all + 1] = ev
			end
		end
		return all
	end

	S.evo_retreat_core = guarded("evo_retreat_core", function()
		local BS, BCat = shared("BattleSim"), shared("BattleCatalog")
		if not T.check(BS ~= nil and BCat ~= nil, "evo retreat: BattleSim and BattleCatalog load") then
			return
		end
		local F = BCat.Fighter
		T.check(F.RetreatWait == 10 and F.RetreatDodge == 0.5, "evo retreat: Fighter.RetreatWait 10, Fighter.RetreatDodge 0.5", tostring(F.RetreatWait) .. " " .. tostring(F.RetreatDodge))
		local inActions = {}
		for _, a in ipairs(BS.Actions) do
			inActions[a] = true
		end
		T.check(inActions.Retreat and inActions.Engage, "evo retreat: BattleSim.Actions names Retreat and Engage")

		-- the state, the lock, the dodge
		local b, tm, f, tm2, f2, boss = raid()
		if not T.check(b ~= nil, "evo retreat: (setup) a raid") then
			return
		end
		T.check(b:TeamOf(1).Retreated == false and b:TeamOf(1).Cooldowns.Retreat == 0, "evo retreat: a fresh team is not retreated and has no wait")
		b:Command(1, "Target", boss.id)
		steps(b, 0.2)
		T.check(tm.lock == boss and tm.engage ~= nil, "evo retreat: (setup) locked and engaged")
		local t0 = b:Time()
		T.check(b:Command(1, "Retreat") == true and tm.retreat ~= nil and tm.noEngage == true and tm.lock == nil and f.iframesUntil >= t0 + 0.5 - 1e-9,
			"evo retreat: Retreat sets the team state, drops the lock, the short dodge", fmt("iframes %.2f at %.2f", f.iframesUntil or -1, t0))
		T.check(tm.engage == nil, "evo retreat: ...and drops the engage at once")
		T.check(b:TeamOf(1).Retreated == true, "evo retreat: TeamOf says Retreated")
		local first = b:Step(0.1)
		T.eq((orders(first, 1, "Retreat")), 1, "evo retreat: one Order { order = \"Retreat\" } echo")
		T.eq(count(first, function(ev)
			return ev.type == "Engage" and ev.owner == 1 and ev.on == false
		end), 1, "evo retreat: one Engage { on = false }")
		T.eq(count(first, function(ev)
			return ev.type == "Dash"
		end), 0, "evo retreat: no Dash event (the dodge is silent)")
		T.check(select(2, b:Command(1, "Retreat")) == "Retreated" and select(2, b:Command(1, "Attack")) == "Retreated" and select(2, b:Command(1, "Element")) == "Retreated" and select(2, b:Command(1, "Special")) == "Retreated",
			"evo retreat: no attacks while back")
		f.meter = 100
		T.check(select(2, b:Command(1, "Special")) == "Retreated" and f.meter == 100, "evo retreat: ...a full meter stays full, the Special refused")
		f.meter = 20
		T.check(b:Command(1, "Target", boss.id) == true and tm.engage == nil, "evo retreat: Target works and does not pull the pet out")
		steps(b, 0.2)
		T.check(tm.engage == nil, "evo retreat: ...a lock set while back leaves it back")
		T.check(b:Command(1, "Cheer") == true, "evo retreat: Cheer up! works")
		T.check(b:Command(1, "Dash") == true, "evo retreat: Dash works")
		steps(b, 0.5)
		T.check(b:Command(1, "Buff", 2) == true and b:Command(1, "Swap", 3) == true and tm.retreat ~= nil,
			"evo retreat: helper buttons work; a Swap keeps the team retreated (the incoming pet too)")
		local swapped = tm.fighter
		T.check(swapped ~= f and b:TeamOf(1).Retreated == true, "evo retreat: ...the incoming pet is the fighter and TeamOf still says Retreated")
		steps(b, 0.8)
		T.check(tm.engage == nil, "evo retreat: ...it never engages by itself")

		-- back: it runs to the character, no swings, no meter, the seconds count
		b:Command(1, "Move", -35, 0)
		local meter0, sec0 = swapped.meter, tm.retreatSeconds
		local x0 = swapped.x
		local mine = 0
		steps(b, 3, function(ev)
			if ev.type == "Hit" and ev.from == swapped.id then
				mine = mine + 1
			end
		end)
		T.check(near(swapped.x, -35, 0.5), "evo retreat: 30 steps with the character 25 studs away: the fighter runs to the Move point", fmt("%.1f -> %.1f", x0, swapped.x))
		T.eq(mine, 0, "evo retreat: ...swings 0 times at the boss")
		T.check(swapped.meter == meter0, "evo retreat: ...its meter does not rise", fmt("%.1f -> %.1f", meter0, swapped.meter))
		T.check(near(tm.retreatSeconds - sec0, 3, 0.11), "evo retreat: ...team.retreatSeconds counts the 3 s", fmt("%.2f", tm.retreatSeconds - sec0))

		-- Engage: back in, the wait
		local tEngage = b:Time()
		T.check(select(2, b:Command(1, "Engage")) == nil and tm.retreat == nil and tm.noEngage == nil and near(b:TeamOf(1).Cooldowns.Retreat, 10, 1e-6),
			"evo retreat: Engage returns, the 10 s wait starts", tostring(b:TeamOf(1).Cooldowns.Retreat))
		T.check(b:TeamOf(1).Retreated == false, "evo retreat: ...TeamOf says so")
		local okC, whyC, leftC = b:Command(1, "Retreat")
		T.check(okC == false and whyC == "Cooldown" and select(2, b:Command(1, "Engage")) == "NotRetreated", "evo retreat: no retreat for 10 s; Engage without a retreat is refused", tostring(whyC))
		T.check(near(leftC, 10, 0.11), "evo retreat: ...the refusal says the seconds left", tostring(leftC))
		local back = b:Step(0.1)
		T.eq((orders(back, 1, "Engage")), 1, "evo retreat: one Order { order = \"Engage\" } echo")
		T.check(tm.engage ~= nil, "evo retreat: the next step the pet engages again")
		local swings = 0
		local meter1 = swapped.meter
		steps(b, 3.5, function(ev)
			if ev.type == "Hit" and ev.from == swapped.id and ev.to == boss.id then
				swings = swings + 1
			end
		end)
		T.check(swings >= 1, "evo retreat: ...and swings at the boss again", swings .. " hits")
		T.check(swapped.meter > meter1, "evo retreat: ...its meter ticks again")
		stepsUntil(b, tEngage + 9.8)
		T.check(select(2, b:Command(1, "Retreat")) == "Cooldown", "evo retreat: still waiting at 9.8 s")
		stepsUntil(b, tEngage + 10.05)
		T.check(b:Command(1, "Retreat") == true, "evo retreat: after 10 s of steps Retreat is accepted again")

		-- Review Focus 4: Stunned / Casting / Dashing accepted; the pet runs once it can, the dodge still applies
		for _, case in ipairs({ { "Stunned", "stunUntil" }, { "Casting", "castUntil" }, { "Dashing", "dashUntil" } }) do
			local bb, tb, fb = raid()
			steps(bb, 0.1)
			local t = bb:Time()
			fb[case[2]] = t + 1
			T.check(bb:Command(1, "Retreat") == true and tb.retreat ~= nil and fb.iframesUntil >= t + 0.5 - 1e-9, "evo retreat: Retreat while " .. case[1] .. " is accepted, the short dodge applies")
		end
		do
			local bb, tb, fb = raid()
			bb:Command(1, "Move", -30, 0)
			steps(bb, 0.1)
			local t = bb:Time()
			fb.stunUntil = t + 1
			bb:Command(1, "Retreat")
			local x = fb.x
			steps(bb, 0.8)
			T.check(near(fb.x, x, 0.01), "evo retreat: a stunned pet stands while it lasts", fmt("%.2f -> %.2f", x, fb.x))
			steps(bb, 1)
			T.check(fb.x < x - 3 and tb.retreat ~= nil, "evo retreat: ...and runs once it can", fmt("%.2f -> %.2f", x, fb.x))
		end
		-- Down: refused
		do
			local bb, tb = raid()
			for _, u in ipairs(tb.units) do
				u.alive, u.hp = false, 0
			end
			T.check(select(2, bb:Command(1, "Retreat")) == "Down" and tb.retreat == nil, "evo retreat: no living fighter: Retreat is refused Down")
		end
		-- every other mode: NoRetreat, before anything else
		for _, mode in ipairs({ "Duel", "Ring", "Dungeon" }) do
			local setup = { Mode = mode, Seed = 3, Zone = { X = 100, Z = 100 }, TimeLimit = 300, Teams = { { Owner = 1, Side = 1, Pets = pets(1) } } }
			if mode == "Ring" then
				setup.Round = 1
				setup.Teams[2] = BCat.ChampionTeam(1, 1)
			elseif mode == "Duel" then
				setup.Teams[2] = { Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = pets(1) }
			end
			local bb = BS.new(setup)
			if T.check(bb ~= nil, "evo retreat: (setup) a " .. mode) then
				local okR, whyR = bb:Command(1, "Retreat")
				local okE, whyE = bb:Command(1, "Engage")
				T.check(okR == false and whyR == "NoRetreat" and okE == false and whyE == "NoRetreat" and bb.teamByOwner[1].retreat == nil and bb:TeamOf(1).Retreated == false,
					"evo retreat: a " .. mode .. ": both are NoRetreat, nothing changes", tostring(whyR) .. " " .. tostring(whyE))
			end
		end
		-- spam: one echo per step
		do
			local bb = raid()
			steps(bb, 0.1)
			for _ = 1, 40 do
				bb:Command(1, "Retreat")
			end
			local acc, rej = orders(bb:Step(0.1), 1, "Retreat")
			T.check(acc == 1 and rej == 1, "evo retreat: 40 Retreat commands in one step: one accepted echo, one Order { rejected }", acc .. " " .. rej)
			for _ = 1, 40 do
				bb:Command(1, "Attack")
			end
			local _, rejAttack = orders(bb:Step(0.1), 1, "Attack")
			T.eq(rejAttack, 1, "evo retreat: ...and 40 refused Attacks in a step: one")
		end

		-- the boss and the minions skip a retreated pet while someone fights
		do
			local bb, tb, fb, tb2, fb2, bossB = raid()
			steps(bb, 0.1)
			tb2.noEngage = true -- (team 2 stands where it is, in reach: it is not retreated, it counts as fighting)
			place(fb, -8, 0) -- team 1 is the NEARER one: only the retreat can make the boss skip it
			place(fb2, 12, 0)
			bb:Command(1, "Retreat")
			steps(bb, 0.6) -- (the dodge runs out)
			bossB.nextAttack = 0
			local tNow = bb:Time()
			for i, entry in ipairs(bossB.attacks) do
				entry.nextAt = tNow + 0.5 * i
			end
			local onOne, onTwo, teles, offTwo = 0, 0, 0, 0
			steps(bb, 6, function(ev)
				if ev.type == "Hit" and ev.from == bossB.id and not ev.miss then
					if ev.to == fb.id then
						onOne = onOne + 1
					elseif ev.to == fb2.id then
						onTwo = onTwo + 1
					end
				elseif ev.type == "Telegraph" then
					teles = teles + 1
					if ev.shape == "Line" then
						-- the line runs from the boss toward the point it was aimed at
						local dx, dz = fb2.x - ev.x, fb2.z - ev.z
						local along = dx * math.cos(ev.angle) + dz * math.sin(ev.angle)
						local across = abs(-dx * math.sin(ev.angle) + dz * math.cos(ev.angle))
						if along < 0 or across > ev.width then
							offTwo = offTwo + 1
						end
					elseif (ev.x - fb2.x) ^ 2 + (ev.z - fb2.z) ^ 2 > ev.r ^ 2 then
						offTwo = offTwo + 1
					end
				end
			end)
			T.eq(onOne, 0, "evo retreat: the boss never hits the retreated pet while team 2 fights (60 steps)")
			T.check(onTwo >= 1, "evo retreat: ...it hits team 2", onTwo .. " hits")
			T.check(teles >= 2 and offTwo == 0, "evo retreat: ...every telegraph is aimed at team 2's fighter", teles .. " telegraphs, " .. offTwo .. " elsewhere")
			T.check(bossB.target == fb2, "evo retreat: ...and the boss looks at team 2's fighter")
			-- team 2 retreats too: the boss comes anyway, it never stalls
			bb:Command(2, "Retreat")
			steps(bb, 0.6)
			local hits, tele2 = 0, 0
			bossB.nextAttack = 0
			tNow = bb:Time()
			for i, entry in ipairs(bossB.attacks) do
				entry.nextAt = tNow + 0.1 * i
			end
			steps(bb, 3, function(ev)
				if ev.type == "Hit" and ev.from == bossB.id and not ev.miss and (ev.to == fb.id or ev.to == fb2.id) then
					hits = hits + 1
				elseif ev.type == "Telegraph" then
					tele2 = tele2 + 1
				end
			end)
			T.check(hits >= 1, "evo retreat: everyone back: within 3 s the boss hits a retreated pet", hits .. " hits")
			T.check(tele2 >= 1, "evo retreat: ...and starts a telegraph: it never stalls", tele2 .. " telegraphs")
			-- one returns: the boss looks at it, the other is safe again
			bb:Command(1, "Engage")
			steps(bb, 0.6)
			bossB.nextAttack = 0
			steps(bb, 0.2)
			T.check(tb.retreat == nil and bossB.target == fb, "evo retreat: one returns: the boss turns on it")
		end
		do
			-- nobody left but the retreated one (the other left the raid): the boss comes anyway
			local bb, tb, fb, _, _, bossB = raid()
			steps(bb, 0.1)
			bb:Command(1, "Retreat")
			bb:RemoveTeam(2)
			steps(bb, 0.6)
			bossB.nextAttack = 0
			local hits = 0
			steps(bb, 3, function(ev)
				if ev.type == "Hit" and ev.from == bossB.id and ev.to == fb.id and not ev.miss then
					hits = hits + 1
				end
			end)
			T.check(hits >= 1 and tb.retreat ~= nil, "evo retreat: the others left: the boss comes anyway", hits .. " hits")
		end
		do
			-- minions: threat, target and nearest all skip a retreated pet while someone fights
			local bb, tb, fb, tb2, fb2, _, minion = raid({ Minion = true })
			if T.check(minion ~= nil, "evo retreat: (setup) a minion") then
				tb2.noEngage = true
				steps(bb, 0.1)
				minion.threat, minion.threatAt, minion.target = fb, bb:Time(), fb
				minion.retargetAt = huge
				bb:Command(1, "Retreat")
				steps(bb, 0.2)
				T.check(minion.target == fb2, "evo retreat: a minion's threat and target leave a retreated pet at once", tostring(minion.target and minion.target.id))
				bb:Command(2, "Retreat")
				minion.retargetAt = 0
				steps(bb, 0.2)
				T.check(minion.target == fb, "evo retreat: everyone back: the minion picks the nearest retreated pet", tostring(minion.target and minion.target.id))
				T.check(tb.retreat ~= nil, "evo retreat: (still back)")
			end
		end

		-- a telegraph already placed keeps its point (Review: "the short dodge is what saves the pet")
		do
			local bb, tb, fb, _, fb2, bossB = raid()
			steps(bb, 0.1)
			place(fb2, 40, 0)
			tb.noEngage = true
			local entry = bossB.attacks[1]
			local ev = castAttack(bb, bossB, entry)
			if T.check(ev ~= nil and ev.shape == "Circle" and near(ev.x, fb.x, 0.2), "evo retreat: (setup) a slam on team 1's fighter", ev and fmt("%s %.1f", tostring(ev.shape), ev.x) or "none") then
				stepsUntil(bb, ev.at - 1.2)
				bb:Command(1, "Retreat")
				local all = stepsUntil(bb, ev.at + 0.2)
				local hit, miss = 0, 0
				for _, h in ipairs(all) do
					if h.type == "Hit" and h.to == fb.id and h.tele == ev.id then
						if h.miss then
							miss = miss + 1
						else
							hit = hit + 1
						end
					end
				end
				T.check(hit == 1 and miss == 0 and tb.retreat ~= nil, "evo retreat: a telegraph placed before the retreat resolves on the pet that stands in it", fmt("%d hits, %d misses", hit, miss))
			end
		end
		do
			-- ...and no meter from that hit
			local bb, tb, fb, _, fb2, bossB = raid()
			steps(bb, 0.1)
			place(fb2, 40, 0)
			tb.noEngage = true
			local ev = castAttack(bb, bossB, bossB.attacks[1])
			if ev then
				stepsUntil(bb, ev.at - 1.2)
				bb:Command(1, "Retreat")
				local m0 = fb.meter
				local hp0 = fb.hp
				stepsUntil(bb, ev.at + 0.2)
				T.check(fb.hp < hp0 and fb.meter == m0, "evo retreat: a hit on a retreated pet gives no meter", fmt("hp %.0f -> %.0f, meter %.1f -> %.1f", hp0, fb.hp, m0, fb.meter))
			end
		end
		do
			-- the dodge: Retreat pressed 0.3 s before the hit
			local bb, tb, fb, _, fb2, bossB = raid()
			steps(bb, 0.1)
			place(fb2, 40, 0)
			tb.noEngage = true
			local ev = castAttack(bb, bossB, bossB.attacks[1])
			if ev then
				stepsUntil(bb, ev.at - 0.3)
				local hp0 = fb.hp
				bb:Command(1, "Retreat")
				local all = stepsUntil(bb, ev.at + 0.2)
				local miss = count(all, function(h)
					return h.type == "Hit" and h.to == fb.id and h.tele == ev.id and h.miss == true
				end)
				T.check(miss == 1 and fb.hp == hp0, "evo retreat: with the dodge (Retreat 0.3 s before the hit) it misses", fmt("%d misses, hp %.0f -> %.0f", miss, hp0, fb.hp))
			end
		end
		do
			-- a Dash while back still parries, with no meter
			local bb, tb, fb, _, fb2, bossB = raid()
			steps(bb, 0.1)
			place(fb2, 40, 0)
			tb.noEngage = true
			local ev = castAttack(bb, bossB, bossB.attacks[1])
			if ev then
				stepsUntil(bb, ev.at - 1.2)
				bb:Command(1, "Retreat")
				tb.dashReadyAt = 0
				stepsUntil(bb, ev.at - 0.2)
				local m0 = fb.meter
				bb:Command(1, "Dash")
				local all = stepsUntil(bb, ev.at + 0.2)
				T.check(count(all, function(h)
					return h.type == "Parry"
				end) == 1 and fb.meter == m0, "evo retreat: a parry while back works, with no meter", fmt("meter %.1f -> %.1f", m0, fb.meter))
			end
		end
		do
			-- a lethal on a retreated fighter standing in it: only that unit, the bench swaps in, still back
			local bb, tb, fb, _, fb2, bossB = raid()
			steps(bb, 0.1)
			place(fb2, 40, 0)
			tb.noEngage = true
			bossB.lethal.nextAt = bb:Time()
			local ev = nil
			for _, e in ipairs(bb:Step(0.1)) do
				if e.type == "Telegraph" then
					ev = e
				end
			end
			if T.check(ev ~= nil and ev.lethal == true and near(ev.x, fb.x, 0.2), "evo retreat: (setup) a lethal on team 1's fighter") then
				stepsUntil(bb, ev.at - 1.2)
				bb:Command(1, "Retreat")
				local lives = bb:TeamOf(1).Lives
				stepsUntil(bb, ev.at + 0.2)
				T.check(fb.alive == false and bb:TeamOf(1).Lives == lives - 1, "evo retreat: a lethal on a retreated fighter standing in it: KO of that unit only", fmt("lives %d -> %d", lives, bb:TeamOf(1).Lives))
				T.check(tb.fighter ~= fb and tb.fighter.alive and tb.retreat ~= nil and bb:TeamOf(1).Retreated == true, "evo retreat: ...the bench swaps in, retreated too")
				T.check(fb2.alive, "evo retreat: ...the other team is untouched")
			end
		end

		-- Result: the seconds, a late joiner's own time
		do
			local bb, tb = raid()
			steps(bb, 5)
			bb:Command(1, "Retreat")
			steps(bb, 12)
			bb:Command(1, "Engage")
			steps(bb, 13)
			T.check(bb:AddTeam({ Owner = 3, Side = 1, Pets = pets(1) }) ~= nil, "evo retreat: (setup) a late joiner at t = 30")
			T.check(near(bb.teamByOwner[3].joinedAt, 30, 0.01), "evo retreat: ...its team record says joinedAt", tostring(bb.teamByOwner[3].joinedAt))
			steps(bb, 20)
			local tEnd = bb:Time()
			bb:Finish("Cleared")
			local res = bb:Result()
			T.check(type(res.Retreated) == "table" and near(res.Retreated[1], 12, 0.11) and res.Retreated[2] == 0 and res.Retreated[3] == 0,
				"evo retreat: Result().Retreated carries each team's seconds", tostring(res.Retreated and res.Retreated[1]))
			T.check(type(res.Fought) == "table" and near(res.Fought[1], tEnd, 0.11) and near(res.Fought[2], tEnd, 0.11) and near(res.Fought[3], tEnd - 30, 0.11),
				"evo retreat: Result().Fought is each team's own time in the fight, a late joiner from its AddTeam", tostring(res.Fought and res.Fought[3]))
			local owners = 0
			for owner in pairs(res.Fought or {}) do
				owners = owners + ((owner == 1 or owner == 2 or owner == 3) and 1 or 100)
			end
			T.eq(owners, 3, "evo retreat: ...player teams only")
			T.check(tb.retreat == nil, "evo retreat: (engaged at the end)")
		end
	end)

	----------------------------------------------------------------------------------------------------
	-- evo_docs
	----------------------------------------------------------------------------------------------------
	-- "rb": Windows text mode stops at byte 0x1A
	local function readFile(rel)
		for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
			local fh = io.open(prefix .. rel, "rb")
			if fh then
				local src = fh:read("*a")
				fh:close()
				return src
			end
		end
		return nil
	end

	S.evo_docs = guarded("evo_docs", function()
		local readme, tools, state = readFile("README.md"), readFile("tools/README.md"), readFile("BUILD_STATE.md")
		if not T.check(readme ~= nil and tools ~= nil and state ~= nil, "evo docs: README.md, tools/README.md and BUILD_STATE.md load") then
			return
		end
		for _, word in ipairs({ "SWITCH TARGET", "RETREAT", "Engage", "boss raids", "Shadow Pack", "a new name, look and effect" }) do
			T.check(readme:find(word, 1, true) ~= nil, "evo docs: the README says \"" .. word .. "\"")
		end
		for _, name in ipairs({ "smoke_evo_sim.lua", "smoke_evo_elements.lua", "smoke_evo_rarity.lua", "smoke_evo_looks.lua", "smoke_evo_buttons.lua", "smoke_evo_retreat.lua" }) do
			T.check(tools:find(name, 1, true) ~= nil, "evo docs: tools/README.md names " .. name)
		end
		T.check(tools:find("`forms`", 1, true) ~= nil, "evo docs: tools/README.md names the sim's forms section")
		T.check(state:find("2026-11-02 (evolved forms", 1, true) ~= nil, "evo docs: BUILD_STATE.md has a 2026-11-02 (evolved forms entry")
	end)

	----------------------------------------------------------------------------------------------------
	-- the booted fixtures (smoke_raid_service.lua's)
	----------------------------------------------------------------------------------------------------
	local seq = 0
	local COMMON = { "pebble_pup", "honey_bunny", "puddle_frog" }
	local RETURN_DELAY = 4 -- BattleService's C.RETURN_DELAY

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

	local function BSvc()
		return req("server/Services/BattleService")
	end
	local function ES()
		return req("server/Services/EventService")
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

	-- the service's St (white-box, tests only)
	local function svcState()
		local f = BSvc().IsInBattle
		for i = 1, 80 do
			local name, v = debug.getupvalue(f, i)
			if not name then
				break
			end
			if name == "St" and type(v) == "table" and type(v.battles) == "table" then
				return v
			end
		end
		return nil
	end

	local function battleOf(id)
		local St = svcState()
		return St and id and St.battles[id] or nil
	end

	local function newPlayer(prefix, level, list)
		seq = seq + 1
		local p = Mock.AddPlayer(prefix .. seq, 987000 + seq)
		advance(0.2)
		local data = DS()
		local prof = data.GetProfile(p)
		list = list or COMMON
		if prof and level then
			for _, id in ipairs(list) do
				prof.Pets[id] = (prof.Pets[id] or 0) + 1
				prof.PetLevels[id] = { Level = level, Xp = 0 }
			end
			data.MarkDirty(p)
			local ok, why = data.SetTeam(p, 1, list)
			if not ok then
				T.fail("(setup) SetTeam for " .. p.Name .. " failed", tostring(why))
			end
		end
		return p
	end

	local function arenaInfo()
		return AB().GetInfo()
	end

	local function toArena(p, dx, dz)
		Mock.Teleport(p, arenaInfo().Spawn * CFrame.new(dx or 0, 0, dz or 0))
		advance(0.05)
	end

	local function lastMsg(p, kind, fromIndex)
		local log = Mock.RemoteLog
		local found = nil
		for i = (fromIndex or 0) + 1, #log do
			local e = log[i]
			if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and e.args[1] == kind then
				found = e.args[2]
			end
		end
		return found
	end

	local function toastCount(p, pattern, fromIndex)
		local log = Mock.RemoteLog
		local n = 0
		for i = (fromIndex or 0) + 1, #log do
			local e = log[i]
			if e.remote == "Notify" and e.kind == "client" and e.userId == p.UserId and type(e.args[1]) == "string" and e.args[1]:find(pattern) then
				n = n + 1
			end
		end
		return n
	end

	-- the events `p` received since `fromIndex`, flat
	local function eventsOf(p, fromIndex)
		local out = {}
		local log = Mock.RemoteLog
		for i = (fromIndex or 0) + 1, #log do
			local e = log[i]
			if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and e.args[1] == "Events" and type(e.args[2]) == "table" then
				for _, ev in ipairs(e.args[2]) do
					out[#out + 1] = ev
				end
			end
		end
		return out
	end

	-- white-box: the fight's boss falls on the next step; every listed player has dealt damage
	local function killBoss(id, ...)
		local b = battleOf(id)
		if not b then
			T.fail("(setup) no battle " .. tostring(id))
			return
		end
		for _, p in ipairs({ ... }) do
			local team = b.Sim.teamByOwner[p.UserId]
			team.damage = team.damage + 1000
		end
		b.Sim.boss.hp = 0
		b.Sim.boss.alive = false
	end

	local function quiet(sim)
		sim.boss.nextAttack = huge
		for _, entry in ipairs(sim.boss.attacks) do
			entry.nextAt = huge
		end
		if sim.boss.lethal then
			sim.boss.lethal.nextAt = huge
		end
	end

	-- every team of the fight forfeits: lives 0 on the next step = "Wipe"
	local function wipe(id, ...)
		local b = battleOf(id)
		if not b then
			T.fail("(setup) no battle " .. tostring(id))
			return
		end
		for _, p in ipairs({ ... }) do
			local team = b.Sim.teamByOwner[p.UserId]
			team.damage = team.damage + 1000
		end
		for _, part in ipairs(b.PartList) do
			if not part.Left then
				b.Sim:Command(part.UserId, "Forfeit")
			end
		end
	end

	-- no fights, the first boss, the stand-in gate, the fake reward clock
	local fakeNow = 1000
	local fakeGate = false
	local function setUp()
		local bs = BSvc()
		bs.EndRaids("Ended")
		advance(0.2)
		local info = arenaInfo()
		fakeGate = false
		if not info.Gate then
			fakeGate = true
			info.Gate = {
				CFrame = info.Floor.CFrame * CFrame.new(0, 0, 78),
				Size = Vector3.new(11, 8, 6),
				Return = info.Floor.CFrame * CFrame.new(0, 3, 68),
			}
		end
		local St = svcState()
		if St and not St.arenaInfo.Gate then
			St.arenaInfo.Gate = info.Gate -- (a copy of the info table: same stand-in)
		end
		fakeNow = 1000
		bs.Debug = { RaidNow = function()
			return fakeNow
		end }
		bs.SetDoubleRewards(nil)
		ES().StartNow("BossRaid", BC().BossOrder[1])
		advance(0.1)
		local closed = St and St.raidClosed
		if closed then
			for tier in pairs(closed) do
				closed[tier] = nil
			end
		end
		if St then
			St.raidFloorHiddenUntil = nil
		end
		return bs
	end

	local function tearDown(players)
		local bs = BSvc()
		bs.EndRaids("Ended")
		advance(0.2)
		bs.Debug = nil
		if fakeGate then
			arenaInfo().Gate = nil
			local St = svcState()
			if St and St.arenaInfo then
				St.arenaInfo.Gate = nil
			end
		end
		K.removePlayers(players)
		advance(RETURN_DELAY + 1)
		local St = svcState()
		if St then
			for tier in pairs(St.raidClosed or {}) do
				St.raidClosed[tier] = nil
			end
			St.raidFloorHiddenUntil = nil
		end
	end

	-- the scenario's players are always taken out again, whatever failed
	local function scenario(name, fn)
		return guarded(name, function()
			if not K.needBoot() then
				return
			end
			if not BSvc() or not arenaInfo() or not ES() then
				T.fail(name .. ": skipped, no BattleService / ArenaBuilder / EventService in this build")
				return
			end
			local players = {}
			local function add(p)
				players[#players + 1] = p
				return p
			end
			local ok, err = pcall(fn, add)
			tearDown(players)
			if not ok then
				error(err, 0)
			end
			K.flushErrors(name)
			K.flushWarnings(name, { "injected end failure" })
		end)
	end

	-- a world CFrame at zone-local (x, z), 4 studs up
	local function zonePoint(b, x, z)
		return b.Zone.CFrame * CFrame.new(x, 4, z)
	end

	----------------------------------------------------------------------------------------------------
	-- evo_retreat_service
	----------------------------------------------------------------------------------------------------
	-- a won raid's medal: a Tier that is neither the loss pay nor a no-pay id
	local function medal(rw)
		return rw ~= nil and rw.Tier ~= nil and rw.Tier ~= "Loss" and rw.Tier ~= "None" and rw.Tier ~= "Cooldown" and rw.Tier ~= "SatOut"
	end

	S.evo_retreat_service = scenario("evo_retreat_service", function(add)
		local bs = setUp()
		local A, B, C = add(newPlayer("RetA", 10)), add(newPlayer("RetB", 10)), add(newPlayer("RetC", 10))
		toArena(A, 2, 0)
		toArena(B, -2, 0)
		toArena(C, 0, 2)
		local okA, id = bs.EnterRaid(A)
		if not T.check(okA == true and type(id) == "string", "evo retreat svc: (setup) A walks through the gate", tostring(id)) then
			return
		end
		local b = battleOf(id)
		local sim = b.Sim
		quiet(sim)
		advance(0.3)
		local ta = sim.teamByOwner[A.UserId]
		local cmd = K.remoteFolder():FindFirstChild("BattleCommand")

		-- the remote: A retreats
		local mark = K.logSize()
		Mock.FromClient(cmd, A, "Retreat")
		advance(0.3)
		T.check(ta.retreat ~= nil and ta.noEngage == true, "evo retreat svc: BattleCommand(\"Retreat\"): the sim team is retreated")
		local accepted = 0
		for _, ev in ipairs(eventsOf(A, mark)) do
			if ev.type == "Order" and ev.order == "Retreat" and ev.rejected == nil then
				accepted = accepted + 1
			end
		end
		T.eq(accepted, 1, "evo retreat svc: ...and the Order echo reaches the player")
		-- B joins late: its own Start, its own Retreat
		local mark2 = K.logSize()
		local okB, idB = bs.EnterRaid(B)
		T.check(okB == true and idB == id, "evo retreat svc: (setup) B joins the running fight", tostring(idB))
		quiet(sim)
		advance(0.3)
		local startB = lastMsg(B, "Start", mark2)
		T.check(startB and startB.Team and startB.Team.Retreated == false and startB.Team.Cooldowns and startB.Team.Cooldowns.Retreat == 0,
			"evo retreat svc: a late joiner's Start: Team.Retreated false, Cooldowns.Retreat 0", startB and startB.Team and tostring(startB.Team.Retreated) or "no Team")
		local tb = sim.teamByOwner[B.UserId]
		T.check(bs.Command(B, "Retreat") == true and tb.retreat ~= nil, "evo retreat svc: B's own Retreat works")
		T.check(bs.Command(B, "Engage") == true and tb.retreat == nil, "evo retreat svc: ...and its Engage")
		-- a fresh Start for a raider who is back / in the wait says so
		local mark3 = K.logSize()
		b.Pending[A] = true
		b.Pending[B] = true
		advance(0.3)
		local startA, startB2 = lastMsg(A, "Start", mark3), lastMsg(B, "Start", mark3)
		T.check(startA and startA.Team and startA.Team.Retreated == true, "evo retreat svc: a fresh Start for a retreated raider: Team.Retreated true")
		T.check(startB2 and startB2.Team and startB2.Team.Cooldowns.Retreat > 8 and startB2.Team.Cooldowns.Retreat <= 10, "evo retreat svc: ...Cooldowns.Retreat = the seconds left",
			startB2 and startB2.Team and tostring(startB2.Team.Cooldowns.Retreat) or "no Team")
		-- junk
		local okArg, whyArg = bs.Command(C, "Retreat", 5)
		T.check(okArg == false and whyArg == "NoBattle", "evo retreat svc: (not in a fight yet) NoBattle", tostring(whyArg))
		bs.EnterRaid(C)
		quiet(sim)
		advance(0.3)
		local tc = sim.teamByOwner[C.UserId]
		for _, junk in ipairs({ 5, "x", { 1, 2 }, true }) do
			local ok, why = bs.Command(C, "Retreat", junk)
			T.check(ok == false and why == "BadArg" and tc.retreat == nil, "evo retreat svc: \"Retreat\" with an argument (" .. tostring(junk) .. "): BadArg, no state change", tostring(why))
			local okE, whyE = bs.Command(C, "Engage", junk)
			T.check(okE == false and whyE == "BadArg", "evo retreat svc: ...\"Engage\" too", tostring(whyE))
		end
		local okN, whyN = bs.Command(C, "Engage")
		T.check(okN == false and whyN == "NotRetreated", "evo retreat svc: \"Engage\" when not retreated: NotRetreated", tostring(whyN))
		-- spam: 20 presses in 0.1 s
		advance(0.3)
		local mark5 = K.logSize()
		for _ = 1, 20 do
			Mock.FromClient(cmd, C, "Retreat")
		end
		advance(0.1)
		advance(0.2)
		local acc, rej = 0, 0
		for _, ev in ipairs(eventsOf(C, mark5)) do
			if ev.type == "Order" and ev.order == "Retreat" then
				if ev.rejected == nil then
					acc = acc + 1
				else
					rej = rej + 1
				end
			end
		end
		T.check(acc == 1 and tc.retreat ~= nil, "evo retreat svc: 20 presses in 0.1 s: one accepted echo", acc .. " accepted, " .. rej .. " rejected")
		T.check(rej <= 3, "evo retreat svc: ...the refusals are one echo a step", rej .. " rejected")

		-- the leash: A stands 30 studs from its retreated pet for 5 s: still in the fight; B, not retreated and held off the engage rule: out
		local fa, fb = ta.fighter, tb.fighter
		fa.run, fa.walk = 0, 0 -- (white-box: the pet cannot close the gap)
		fb.run, fb.walk = 0, 0
		tb.noEngage = true
		sim:Command(B.UserId, "Target") -- (no lock)
		local aim = (fa.x > 0) and -30 or 30
		Mock.Teleport(A, zonePoint(b, fa.x + aim, fa.z))
		aim = (fb.x > 0) and -30 or 30
		Mock.Teleport(B, zonePoint(b, fb.x + aim, fb.z))
		local fightId = id
		advance(5)
		T.check(A:GetAttribute("InBattle") == fightId and not b.Parts[A.UserId].Left, "evo retreat svc: A's character 30 studs from its retreated pet for 5 s: still in the fight",
			tostring(A:GetAttribute("InBattle")))
		T.check(B:GetAttribute("InBattle") == nil or b.Parts[B.UserId].Left, "evo retreat svc: ...the same gap on a team that is not retreated is the leash's", tostring(B:GetAttribute("InBattle")))
		-- after Engage the catch-up grace keeps it in, as a stun's does
		T.check(bs.Command(A, "Engage") == true, "evo retreat svc: (setup) A engages again")
		ta.noEngage = true -- (white-box: no engage rule, only the grace is left)
		advance(0.3)
		T.check(b.Parts[A.UserId].LeashGraceUntil > sim:Time(), "evo retreat svc: after Engage the catch-up grace runs", fmt("%.1f at %.1f", b.Parts[A.UserId].LeashGraceUntil, sim:Time()))
		advance(4)
		T.check(A:GetAttribute("InBattle") == fightId and not b.Parts[A.UserId].Left, "evo retreat svc: ...and keeps A in past the leash's 3 s")
		-- a run-off out of the arena is still the presence check's
		T.check(tc.retreat ~= nil, "evo retreat svc: (C is still back)")
		Mock.Teleport(C, CFrame.new(K.config().Lobby.Origin + Vector3.new(10, 4, 10)))
		advance(4.5) -- (bug batch 6: the fight area's warning and 3-2-1 come first; was 2)
		T.check(C:GetAttribute("InBattle") == nil or b.Parts[C.UserId].Left, "evo retreat svc: a retreated raider who runs out of the arena is out (the presence check)", tostring(C:GetAttribute("InBattle")))
	end)

	----------------------------------------------------------------------------------------------------
	-- evo_retreat_pay
	----------------------------------------------------------------------------------------------------
	S.evo_retreat_pay = scenario("evo_retreat_pay", function(add)
		local bs = setUp()
		local data = DS()
		local BCat = BC()
		-- the fight of `who` (each { player, retreated seconds, fought seconds }) at battle time 120: the boss falls -> Rewards per player.
		-- opts.rngZero: the service's rng answers 0 to every NextNumber while the fight is paid (a pet WOULD drop for anyone rolled) and
		-- counts its draws; returned third
		local draws = 0
		local function won(who, boss_wins, opts)
			opts = opts or {}
			setUp()
			fakeNow = 5000
			local ok, id
			for i, w in ipairs(who) do
				toArena(w[1], i * 2, 0)
				ok, id = bs.EnterRaid(w[1])
				if not ok then
					T.fail("(setup) could not enter: " .. tostring(id))
					return {}
				end
			end
			local b = battleOf(id)
			quiet(b.Sim)
			advance(0.2)
			b.Sim.t = 120
			for _, w in ipairs(who) do
				local team = b.Sim.teamByOwner[w[1].UserId]
				team.retreatSeconds = w[2]
				team.joinedAt = 120 - w[3]
			end
			local mark = K.logSize()
			local players = {}
			for i, w in ipairs(who) do
				players[i] = w[1]
			end
			local St, oldRng = nil, nil
			draws = 0
			if opts.rngZero then
				St = svcState()
				oldRng = St and St.rng
				if St then
					St.rng = {
						NextNumber = function()
							draws = draws + 1
							return 0
						end,
						NextInteger = function(_, lo)
							return lo
						end,
					}
				end
			end
			if boss_wins then
				wipe(id, unpack(players))
			else
				killBoss(id, unpack(players))
			end
			advance(0.3)
			if St then
				St.rng = oldRng
			end
			local out = {}
			for _, w in ipairs(who) do
				local msg = lastMsg(w[1], "End", mark)
				out[w[1]] = msg and msg.Rewards or {}
			end
			advance(RETURN_DELAY + 1)
			return out, mark, draws
		end
		local function loss(share)
			return BCat.RaidTier(share, false, "Starter")
		end

		local function win(share)
			return BCat.RaidTier(share, true, "Starter")
		end

		-- 70%: the win medal is paid and the win clock starts; the Boss Raid pet roll goes (the owner's choice 2026-11-02: no free pet); the other
		-- keeps everything
		local A, B = add(newPlayer("PayA", 10)), add(newPlayer("PayB", 10))
		local rw, mark = won({ { A, 70, 100 }, { B, 0, 100 } })
		local ra, rb = rw[A] or {}, rw[B] or {}
		T.check(ra.SatOut == true, "evo retreat pay: retreated for 70% of its time in a won fight: rw.SatOut", tostring(ra.SatOut))
		T.check(type(ra.Reason) == "string" and ra.Reason:find("sat out") ~= nil and ra.Reason:find("no Boss Raid pet") ~= nil, "evo retreat pay: ...rw.Reason says why", tostring(ra.Reason))
		T.check(medal(ra) and ra.Tier == win(0.5).Id, "evo retreat pay: ...the win medal, not the Loss tier and no tier named SatOut", tostring(ra.Tier))
		T.check(ra.Tokens == win(0.5).Tokens and ra.Xp == win(0.5).Xp, "evo retreat pay: ...paid the medal's Tokens and XP", fmt("%s tokens, %s xp", tostring(ra.Tokens), tostring(ra.Xp)))
		T.check(ra.EventPet == nil, "evo retreat pay: ...no event pet")
		T.check(data.GetBattle(A).RaidRewardAt == 5000 and data.GetBattle(A).RaidLossAt == 0, "evo retreat pay: ...RaidRewardAt stamped (a paid win), RaidLossAt not",
			fmt("%s %s", tostring(data.GetBattle(A).RaidRewardAt), tostring(data.GetBattle(A).RaidLossAt)))
		T.check(toastCount(A, "sat out more than half the fight", mark) == 1, "evo retreat pay: ...the toast says so")
		T.check(toastCount(A, "Boss defeated!", mark) == 1, "evo retreat pay: ...and the win's own toast too")
		-- the pet roll: with an rng that drops a pet on every roll the one who fought gets one and the sat-out one does not; the sat-out roll is
		-- drawn and thrown away (one rng pays every raider in turn: 2 draws a paid player, Gems then the pet), so nobody else's rolls move
		local A2, B2 = add(newPlayer("PayA2", 10)), add(newPlayer("PayB2", 10))
		local rw2, _, n = won({ { A2, 70, 100 }, { B2, 0, 100 } }, false, { rngZero = true })
		T.check(rw2[A2] and medal(rw2[A2]) and rw2[A2].SatOut == true and rw2[A2].EventPet == nil, "evo retreat pay: an rng that always drops a pet: the sat-out winner still gets none", rw2[A2] and tostring(rw2[A2].EventPet))
		T.check(rw2[B2] and medal(rw2[B2]) and type(rw2[B2].EventPet) == "string", "evo retreat pay: ...the one who fought gets a Boss Raid pet", rw2[B2] and tostring(rw2[B2].EventPet))
		T.eq(n, 4, "evo retreat pay: ...and the rng was drawn 4 times (the sat-out roll drawn and thrown away, not skipped)")
		T.check(medal(rb) and rb.SatOut == nil and rb.Reason == nil and rb.Tokens == ra.Tokens, "evo retreat pay: the one who fought gets the same medal, no line", tostring(rb.Tier) .. " " .. tostring(rb.Tokens))
		T.check(toastCount(B, "sat out", mark) == 0, "evo retreat pay: ...and no sat-out toast")
		T.check(data.GetBattle(B).RaidRewardAt == 5000 and data.GetBattle(B).RaidLossAt == 0, "evo retreat pay: ...on the win clock")
		-- 40% and exactly half: the win medal, no line, the pet roll kept (a chance, so only its absence is pinned: SatOut nil)
		local C, D = add(newPlayer("PayC", 10)), add(newPlayer("PayD", 10))
		rw = won({ { C, 40, 100 }, { D, 50, 100 } })
		T.check(medal(rw[C]) and rw[C].SatOut == nil, "evo retreat pay: retreated 40%: the win medal, no line", rw[C] and tostring(rw[C].Tier))
		T.check(medal(rw[D]) and rw[D].SatOut == nil, "evo retreat pay: retreated exactly half: still no line", rw[D] and tostring(rw[D].Tier))
		-- the boundary is "over half": 50.2 of about 100 s is, 50 is not (the fight's own 0.1 s step keeps both on their side)
		local D2 = add(newPlayer("PayD2", 10))
		rw = won({ { D2, 50.2, 100 } })
		T.check(medal(rw[D2]) and rw[D2].SatOut == true, "evo retreat pay: retreated 50.2 of 100: just over half sat out", rw[D2] and tostring(rw[D2].SatOut))
		-- the late joiner: judged against its own time, never the fight's Duration (120 s here)
		local E, G, H = add(newPlayer("PayE", 10)), add(newPlayer("PayG", 10)), add(newPlayer("PayH", 10))
		rw = won({ { E, 0, 120 }, { G, 0, 20 }, { H, 15, 20 } })
		T.check(medal(rw[G]) and rw[G].SatOut == nil, "evo retreat pay: a late joiner who fought its last 20 s keeps the win medal, no line", rw[G] and tostring(rw[G].Tier))
		T.check(medal(rw[H]) and rw[H].SatOut == true and rw[H].EventPet == nil, "evo retreat pay: a late joiner back for 15 of its 20 s sat out (not 15 of the fight's 120): the medal, no pet", rw[H] and tostring(rw[H].Tier))
		-- the boss wins: the loss medal as today, whatever the seconds, and no line (nothing was won)
		local I, J = add(newPlayer("PayI", 10)), add(newPlayer("PayJ", 10))
		rw = won({ { I, 90, 100 }, { J, 0, 100 } }, true)
		T.check(rw[I] and rw[I].Tier == "Loss" and rw[I].SatOut == nil and rw[J] and rw[J].Tier == "Loss", "evo retreat pay: the boss wins: everyone the loss medal as today, no line", (rw[I] and tostring(rw[I].Tier) or "nil") .. " " .. (rw[J] and tostring(rw[J].Tier) or "nil"))
		T.check(rw[I] and rw[I].Tokens == loss(0.5).Tokens, "evo retreat pay: ...the Loss medal's tokens", rw[I] and tostring(rw[I].Tokens))
		-- no hits at all: no reward, as today
		local L = add(newPlayer("PayL", 10))
		setUp()
		fakeNow = 5000
		toArena(L, 2, 0)
		local okL, idL = bs.EnterRaid(L)
		if T.check(okL == true, "evo retreat pay: (setup) L enters") then
			local bL = battleOf(idL)
			quiet(bL.Sim)
			advance(0.2)
			bL.Sim.teamByOwner[L.UserId].retreatSeconds = 90
			bL.Sim.teamByOwner[L.UserId].damage = 0
			bL.Sim.boss.hp = 0
			bL.Sim.boss.alive = false
			local markL = K.logSize()
			advance(0.3)
			local msgL = lastMsg(L, "End", markL)
			T.check(msgL and msgL.Rewards and msgL.Rewards.Tier == "None", "evo retreat pay: back the whole fight, no hits: the Tier None of today", msgL and msgL.Rewards and tostring(msgL.Rewards.Tier))
			advance(RETURN_DELAY + 1)
		end
		-- a sat-out win is a paid win: a second one inside the 20 minute clock pays nothing (Tier Cooldown, as any win), keeps the line, and the
		-- loss clock is never touched
		local M = add(newPlayer("PayM", 10))
		won({ { M, 70, 100 } })
		local tokensM = data.GetTokens(M)
		local stamp = data.GetBattle(M).RaidRewardAt
		T.check(stamp == 5000 and tokensM > 0, "evo retreat pay: (setup) the first sat-out win paid and stamped the win clock", fmt("%s %s", tostring(stamp), tostring(tokensM)))
		rw = won({ { M, 70, 100 } })
		T.check(rw[M] and rw[M].Tier == "Cooldown" and rw[M].SatOut == true and (rw[M].Tokens or 0) == 0 and data.GetTokens(M) == tokensM and data.GetBattle(M).RaidRewardAt == stamp,
			"evo retreat pay: a second sit-out inside the win clock pays nothing (Cooldown), keeps the line, the clock stays", rw[M] and fmt("%s %s %s", tostring(rw[M].Tier), tostring(rw[M].SatOut), tostring(rw[M].Tokens)))
		T.eq(data.GetBattle(M).RaidLossAt, 0, "evo retreat pay: ...and a sat-out win never touches the loss clock")
		rw = won({ { M, 0, 100 } })
		T.check(rw[M] and rw[M].Tier == "Cooldown" and rw[M].SatOut == nil, "evo retreat pay: ...a real win inside the same clock is Cooldown too, without the line", rw[M] and tostring(rw[M].Tier))
	end)

	----------------------------------------------------------------------------------------------------
	-- evo_retreat_flow
	----------------------------------------------------------------------------------------------------
	S.evo_retreat_flow = scenario("evo_retreat_flow", function(add)
		local bs = setUp()
		-- solo on the floor: Retreat -> the boss comes anyway -> Engage -> a win pays. The character stands by the boss, so its pet is in reach
		local function solo(p, label, spot)
			local ok, id = bs.EnterRaid(p)
			if not T.check(ok == true, label .. ": (setup) enters", tostring(id)) then
				return
			end
			local b = battleOf(id)
			local sim = b.Sim
			advance(0.3)
			local team = sim.teamByOwner[p.UserId]
			for _, u in ipairs(team.units) do
				u.maxHp, u.hp = 1e7, 1e7
			end
			sim.boss.maxHp, sim.boss.hp = 1e9, 1e9
			local boss = sim.boss
			Mock.Teleport(p, zonePoint(b, boss.x + spot, boss.z))
			advance(1)
			T.check(bs.Command(p, "Retreat") == true and team.retreat ~= nil, label .. ": Retreat is accepted")
			local hp0 = team.fighter.hp
			boss.nextAttack = 0
			local tNow = sim:Time()
			boss.attacks[1].nextAt = tNow + 0.8
			local mark = K.logSize()
			advance(3.2)
			local hits, teles = 0, 0
			for _, ev in ipairs(eventsOf(p, mark)) do
				if ev.type == "Hit" and ev.from == boss.id and ev.to == team.fighter.id and not ev.miss then
					hits = hits + 1
				elseif ev.type == "Telegraph" then
					teles = teles + 1
				end
			end
			T.check(hits >= 1 and team.fighter.hp < hp0, label .. ": nobody else fights: the boss comes anyway and hits the retreated pet", hits .. " hits")
			T.check(teles >= 1, label .. ": ...it keeps casting too", teles .. " telegraphs")
			T.check(bs.Command(p, "Engage") == true and team.retreat == nil, label .. ": Engage returns")
			advance(0.3)
			T.check(team.engage ~= nil, label .. ": ...the pet fights again")
			advance(4) -- (more of the fight engaged than back)
			local markEnd = K.logSize()
			killBoss(id, p)
			advance(0.3)
			local msg = lastMsg(p, "End", markEnd)
			local rw = msg and msg.Rewards or {}
			T.check(rw.Tier ~= nil and rw.Tier ~= "SatOut" and rw.Tier ~= "Loss" and (rw.Tokens or 0) > 0, label .. ": ...a win pays", tostring(rw.Tier) .. " " .. tostring(rw.Tokens))
			advance(RETURN_DELAY + 1)
			toArena(p, 2, 0)
		end
		local A = add(newPlayer("FlowA", 10))
		toArena(A, 2, 0)
		solo(A, "evo retreat flow solo", 8)

		-- a pocket fight (a second tier): the same. Another fight holds the floor
		setUp()
		local floorHolder = add(newPlayer("FlowF", 10))
		toArena(floorHolder, 4, 0)
		local okF, idF = bs.EnterRaid(floorHolder)
		T.check(okF == true, "evo retreat flow pocket: (setup) a Starter holds the floor", tostring(idF))
		quiet(battleOf(idF).Sim)
		local P = add(newPlayer("FlowP", 20))
		toArena(P, 6, 0)
		solo(P, "evo retreat flow pocket", 8)

		-- a group of three on the floor
		setUp()
		local X, Y, Z = add(newPlayer("FlowX", 10)), add(newPlayer("FlowY", 10)), add(newPlayer("FlowZ", 10))
		toArena(X, 2, 0)
		toArena(Y, -2, 0)
		toArena(Z, 0, 2)
		local ok1, id = bs.EnterRaid(X)
		bs.EnterRaid(Y)
		bs.EnterRaid(Z)
		if not T.check(ok1 == true, "evo retreat flow group: (setup) three walk in", tostring(id)) then
			return
		end
		local b = battleOf(id)
		local sim = b.Sim
		advance(0.3)
		local boss = sim.boss
		boss.maxHp, boss.hp = 1e9, 1e9
		for _, team in ipairs(sim.teams) do
			if team.player then
				for _, u in ipairs(team.units) do
					u.maxHp, u.hp = 1e7, 1e7
				end
			end
		end
		local tx = sim.teamByOwner[X.UserId]
		Mock.Teleport(X, zonePoint(b, boss.x + 8, boss.z))
		advance(1)
		T.check(bs.Command(X, "Retreat") == true, "evo retreat flow group: X retreats")
		advance(0.6)
		local fighterX = tx.fighter
		local hpX = fighterX.hp
		boss.nextAttack = 0
		local mark = K.logSize()
		advance(3)
		local onX, onOthers = 0, 0
		for _, ev in ipairs(eventsOf(X, mark)) do
			if ev.type == "Hit" and ev.from == boss.id and not ev.miss then
				if ev.to == fighterX.id then
					onX = onX + 1
				else
					onOthers = onOthers + 1
				end
			end
		end
		T.check(onX == 0 and fighterX.hp == hpX, "evo retreat flow group: the boss leaves the retreated pet alone", onX .. " hits")
		T.check(onOthers >= 1, "evo retreat flow group: ...and turns on the others", onOthers .. " hits")
		T.check(bs.Command(X, "Swap", 2) == true, "evo retreat flow group: a helper swaps in")
		advance(1)
		T.check(tx.retreat ~= nil and tx.fighter ~= fighterX and tx.engage == nil, "evo retreat flow group: ...and stays back")
		T.check(bs.Command(X, "Engage") == true and tx.retreat == nil, "evo retreat flow group: Engage")
		T.check(select(2, bs.Command(X, "Retreat")) == "Cooldown", "evo retreat flow group: ...no retreat for 10 s")
		advance(10.2)
		T.check(bs.Command(X, "Retreat") == true, "evo retreat flow group: ...and again after them")
		-- X sits out the end of the fight: the rule reads the real seconds; its result carries the line
		tx.retreatSeconds = sim:Time() -- (white-box: as if it had been back since the start)
		local markEnd = K.logSize()
		killBoss(id, X, Y, Z)
		advance(0.3)
		local msgX, msgY = lastMsg(X, "End", markEnd), lastMsg(Y, "End", markEnd)
		local rx, ry = msgX and msgX.Rewards or {}, msgY and msgY.Rewards or {}
		T.check(rx.SatOut == true and tostring(rx.Reason):find("sat out") ~= nil and medal(rx), "evo retreat flow group: the result carries the sat-out line and the win medal for the one who sat out", tostring(rx.Tier) .. " " .. tostring(rx.SatOut))
		T.check(msgX and msgX.Won == true, "evo retreat flow group: ...the fight is still a win for it", msgX and tostring(msgX.Won))
		T.check(ry.SatOut == nil and medal(ry), "evo retreat flow group: ...and the others keep their medals without the line", tostring(ry.Tier))
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- the client worlds
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer

	local H = {}

	function H.moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	function H.step(n, dt)
		for _ = 1, n or 1 do
			Mock.Step(dt)
		end
	end

	function H.find(path)
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local cur = pg and pg:FindFirstChild("NimbusBattle")
		for name in string.gmatch(path, "[^%.]+") do
			if not cur then
				return nil
			end
			cur = cur:FindFirstChild(name)
		end
		return cur
	end

	function H.commands(index)
		local out = {}
		for _, e in ipairs(KC.serverCalls("BattleCommand", index)) do
			out[#out + 1] = { action = e.args[1], arg = e.args[2] }
		end
		return out
	end

	function H.count(index, action)
		local n = 0
		for _, c in ipairs(H.commands(index)) do
			if c.action == action then
				n = n + 1
			end
		end
		return n
	end

	local function shownIn(obj)
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
		return cur ~= nil
	end

	local function rectOf(inst)
		local g = inst:FindFirstAncestorOfClass("ScreenGui")
		local dy = (g and g.IgnoreGuiInset) and -(Mock.TopInset or 0) or 0
		local p, s = inst.AbsolutePosition, inst.AbsoluteSize
		return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
	end

	local function overlaps(a, b)
		return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
	end

	local function rstr(r)
		return fmt("%.0f,%.0f-%.0f,%.0f", r.x0, r.y0, r.x1, r.y1)
	end

	-- a real BattleSim fed to the client the way BattleService sends it; my BattleCommand calls are forwarded into the sim unless noForward
	local Driver = {}
	Driver.__index = Driver

	function H.fight(opts)
		local Sim = H.moduleAt("shared", "BattleSim")
		local BCat = H.moduleAt("shared", "BattleCatalog")
		if not Sim or not BCat then
			return nil
		end
		local me = LocalPlayer.UserId
		local mode = opts.Mode or "Raid"
		local id = "evo_ret_" .. tostring(math.random(100000, 999999))
		local mine = {}
		for i, key in ipairs({ "ember_phoenix", "biscuit_bear", "sunbeam_bear" }) do
			mine[i] = { PetId = key, Key = key, Level = 30, Tier = "Normal", Slot = i }
		end
		local setup = { Mode = mode, Seed = 23, Id = id, Zone = { X = 90, Z = 90 }, TimeLimit = 300, Teams = { { Owner = me, Side = 1, Pets = mine } } }
		if mode == "Raid" then
			setup.Boss = "storm_titan"
		elseif mode == "Ring" then
			setup.Round = 1
			setup.Teams[2] = BCat.ChampionTeam(1, 1)
		elseif mode == "Duel" then
			setup.Teams[2] = { Owner = "frogs", Side = 2, Npc = true, Specials = false, Pets = { { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = 1 } } }
		end
		local sim = Sim.new(setup)
		if not sim then
			return nil
		end
		local d = setmetatable({ sim = sim, id = id, mode = mode, me = me, logIndex = #Mock.RemoteLog, last = {},
			dungeon = (mode == "Dungeon") and { Floor = 2, Room = 1, Wave = 1, Waves = 3, Name = "Ember Hall", Element = "Flame" } or nil }, Driver)
		for _, u in ipairs(sim.units) do
			u.maxHp, u.hp = 1e7, 1e7
			if u.side == 1 then
				u.x, u.z, u.px, u.pz = 0, 0, 0, 0
			else
				u.moveSpeed, u.nextAttack, u.hit = 0, huge, 0
				for _, entry in ipairs(u.attacks or {}) do
					entry.nextAt = huge
				end
				if u.lethal then
					u.lethal.nextAt = huge
				end
			end
		end
		d:start(opts)
		d:step()
		d:run(1.2)
		return d
	end

	function Driver:start(opts)
		local p = self.sim:Describe()
		p.BattleId = self.id
		p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
		p.Names = { [tostring(self.me)] = LocalPlayer.Name }
		p.Side, p.Spectator, p.T = 1, false, self.sim:Time()
		p.Dungeon = self.dungeon
		if self.mode == "Raid" then
			p.Raid = { Tier = "High", Pocket = true, BossId = "storm_titan" }
		end
		local team = self.sim:TeamOf(self.me)
		p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed, Retreated = team.Retreated,
			Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Cheer = team.Cooldowns.Cheer, Retreat = team.Cooldowns.Retreat, Buff = {} } }
		if opts and opts.Team then
			for k, v in pairs(opts.Team) do
				if k == "Cooldowns" then
					for ck, cv in pairs(v) do
						p.Team.Cooldowns[ck] = cv
					end
				else
					p.Team[k] = v
				end
			end
		end
		LocalPlayer:SetAttribute("InBattle", self.id)
		KC.toClient("BattleState", "Start", p, self.id)
	end

	function Driver:step()
		if self.noForward then
			self.logIndex = #Mock.RemoteLog
		else
			for _, c in ipairs(H.commands(self.logIndex)) do
				pcall(self.sim.Command, self.sim, self.me, c.action, c.arg)
			end
			self.logIndex = #Mock.RemoteLog
		end
		local evs = self.sim:Step(0.1)
		if #evs > 0 then
			KC.toClient("BattleState", "Events", evs, self.id)
		end
		local snap = self.sim:SnapshotDelta(self.last)
		snap.BattleId = self.id
		KC.toClient("BattleState", "Snapshot", snap, self.id)
		H.step(3, 0.1 / 3)
		return evs
	end

	function Driver:run(seconds)
		for _ = 1, floor(seconds / 0.1 + 0.5) do
			self:step()
		end
	end

	function H.cleanup(BC, d)
		if d and BC.GetBattle() then
			KC.toClient("BattleState", "End", { BattleId = d.id, Mode = d.mode, Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, d.id)
		end
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
		local r = H.find("Root.ResultCard.Body.OkButton")
		if r and r.Visible then
			Mock.Click(r)
		end
		Mock.Step(0.1)
	end

	local function pressR(key, kind)
		key, kind = key or "R", kind or "Keyboard"
		Mock.TriggerAction("NimbusBattleRetreat", "Begin", Mock.NewInput(key, kind, "Begin"))
		Mock.TriggerAction("NimbusBattleRetreat", "End", Mock.NewInput(key, kind, "End"))
	end

	-- what the Retreat button must keep clear of (gui-area px): smoke_wave6's cheerObstacles, and the cluster, the Cheer up! button
	local function obstacles(touch)
		local out = {}
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		for _, g in ipairs(pg and pg:GetChildren() or {}) do
			if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "NimbusBattle" and g.Name ~= "NimbusBattleFx" then
				for _, o in ipairs(g:GetDescendants()) do
					if o:IsA("GuiButton") and shownIn(o) and o.AbsoluteSize.X > 4 and o.AbsoluteSize.X < 400 then
						out[#out + 1] = { g.Name .. "." .. o.Name, rectOf(o) }
					end
				end
				for _, name in ipairs({ "Vitals", "Hotbar" }) do
					local o = g:FindFirstChild(name, true)
					if o and o:IsA("GuiObject") and shownIn(o) and o.AbsoluteSize.X > 0 then
						out[#out + 1] = { g.Name .. "." .. name, rectOf(o) }
					end
				end
			end
		end
		local root = H.find("Root")
		for _, block in ipairs(root and root:GetChildren() or {}) do
			if block:IsA("GuiObject") and block.Name ~= "Retreat" and block.Name ~= "CheerGlow" and block.Name ~= "Commands" and shownIn(block) and block.AbsoluteSize.X > 0 then
				out[#out + 1] = { "Battle." .. block.Name, rectOf(block) }
			end
		end
		local cmd = H.find("Root.Commands")
		for _, b in ipairs(cmd and cmd:GetChildren() or {}) do
			if b:IsA("GuiObject") and shownIn(b) and b.AbsoluteSize.X > 0 then
				out[#out + 1] = { "Battle.Commands." .. b.Name, rectOf(b) }
			end
		end
		if touch then
			local vp = Mock.Viewport
			local areaY = vp.Y - (Mock.TopInset or 0)
			local small = min(vp.X, vp.Y) <= 500
			local j = small and 70 or 120
			local jb = small and 20 or j * 0.75
			out[#out + 1] = { "Roblox jump", { x0 = vp.X - j * 1.5 - 10, y0 = areaY - jb - j, x1 = vp.X - j * 0.5 - 10, y1 = areaY - jb } }
			local stickW = small and 110 or 190
			local stickH = small and ((vp.Y > vp.X) and 150 or 96) or 210
			out[#out + 1] = { "Roblox stick", { x0 = 0, y0 = areaY - stickH, x1 = stickW, y1 = areaY } }
		end
		return out
	end

	-- the placement rules at the current viewport -> problem | nil, rect, how ("row" | "stack")
	local function placeProblem(touch)
		local b, c = H.find("Root.Retreat"), H.find("Root.Cheer")
		if not b or not shownIn(b) then
			return "Retreat not shown"
		end
		if not c or not shownIn(c) then
			return "Cheer up! not shown"
		end
		local r, rc = rectOf(b), rectOf(c)
		local why = {}
		local vp = Mock.Viewport
		local areaY = vp.Y - (Mock.TopInset or 0)
		-- the Cheer row: its left, 8 px apart, the same height; or stacked above it where the row sits beside the vitals card; or under the
		-- vitals card (8 px below it, from its left edge or further right) where that stack would cover the fighter's cards or the middle
		local row = abs((rc.x0 - r.x1) - 8) <= 2 and abs(r.y0 - rc.y0) <= 2 and abs(r.y1 - rc.y1) <= 2
		local stack = abs((rc.y0 - r.y1) - 8) <= 2 and abs(r.x0 - rc.x0) <= 2 and abs(r.x1 - rc.x1) <= 2
		local v = H.moduleAt("client", "Controllers/HudController").GetLayout().Vitals
		local under = v ~= nil and abs((r.y0 - (v.Y + v.H)) - 8) <= 2 and r.x0 >= v.X - 2 and r.x1 <= v.X + v.W + 2
		if not (row or stack or under) then
			why[#why + 1] = "neither left of Cheer up!, stacked above it nor under the vitals card: " .. rstr(r) .. " vs " .. rstr(rc)
		end
		if r.x0 < 0 or r.y0 < 0 or r.x1 > vp.X or r.y1 > areaY then
			why[#why + 1] = "off the screen " .. rstr(r)
		end
		if touch and (r.x1 - r.x0 < 44 or r.y1 - r.y0 < 44) then
			why[#why + 1] = fmt("tap target %.0fx%.0f < 44x44", r.x1 - r.x0, r.y1 - r.y0)
		end
		for _, o in ipairs(obstacles(touch)) do
			if overlaps(r, o[2]) then
				why[#why + 1] = fmt("covers %s %s (Retreat %s)", o[1], rstr(o[2]), rstr(r))
			end
		end
		-- the middle of the screen stays free (HudController's CENTRE_TOL)
		local cx, cy = vp.X / 2, vp.Y / 2 - (Mock.TopInset or 0)
		if r.x0 < cx + vp.X * 0.145 and r.x1 > cx - vp.X * 0.145 and r.y0 < cy + vp.Y * 0.145 and r.y1 > cy - vp.Y * 0.145 then
			why[#why + 1] = "in the middle of the screen " .. rstr(r)
		end
		return #why > 0 and table.concat(why, "; ") or nil, r, row and "row" or (stack and "stack" or (under and "under" or "none"))
	end

	------------------------------------------------------------------------------------------------
	-- client_evo_retreat
	------------------------------------------------------------------------------------------------
	S.client_evo_retreat = guarded("client_evo_retreat", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		local GQ = H.moduleAt("client", "GraphicsQuality")
		if not T.check(BC ~= nil and GQ ~= nil, "evo retreat client: BattleController and GraphicsQuality load") then
			return
		end
		local err0 = #Mock.Errors
		Mock.SetViewport(1920, 1080)
		H.step(3, 0.1)
		local d = H.fight({ Mode = "Raid" })
		if not T.check(d ~= nil and BC.GetBattle() ~= nil, "evo retreat client: (setup) a raid") then
			return
		end
		local b = H.find("Root.Retreat")
		T.check(b ~= nil and b:IsA("TextButton") and shownIn(b) and b.Text == "Retreat", "evo retreat client: a raid shows the button, it reads Retreat", b and tostring(b.Text) or "missing")
		if not b then
			H.cleanup(BC, d)
			return
		end
		local bound = Mock.BoundActions.NimbusBattleRetreat
		local keys = {}
		for _, k in ipairs(bound and bound.inputs or {}) do
			keys[k.Name] = true
		end
		T.check(keys.R and keys.DPadDown, "evo retreat client: R and D-pad down are bound while fighting a raid")
		local why, _, how = placeProblem(false)
		T.check(why == nil and how == "row", "evo retreat client 1920x1080: left of Cheer up!, same height, covering nothing", tostring(why))
		-- the key chip
		local chip = b:FindFirstChild("Key", true)
		T.check(chip ~= nil and chip.Text == "R" and shownIn(chip), "evo retreat client: the key chip says R", chip and tostring(chip.Text) or "missing")
		-- R: one remote, the echo flips the label
		local idx = #Mock.RemoteLog
		pressR()
		T.eq(H.count(idx, "Retreat"), 1, "evo retreat client: R sends ONE Retreat")
		pressR()
		T.eq(H.count(idx, "Retreat"), 1, "evo retreat client: ...a second press in the same moment sends nothing more")
		T.check(b.Text == "Retreat", "evo retreat client: ...the label waits for the server's echo", b.Text)
		d:run(0.3)
		T.check(d.sim.teams[1].retreat ~= nil, "evo retreat client: (the sim took it)")
		T.check(b.Text == "Engage" and BC.GetBattle().Retreated == true, "evo retreat client: the Order echo flips it to Engage", b.Text)
		local sweep = b:FindFirstChild("Sweep")
		T.check(sweep ~= nil and not shownIn(sweep), "evo retreat client: no sweep while back")
		-- a swap keeps it
		T.check(BC.Command("Swap", 2) == true, "evo retreat client: (setup) a helper swaps in")
		d:run(0.8)
		T.check(b.Text == "Engage" and BC.GetBattle().Retreated == true, "evo retreat client: a swap keeps Engage")
		-- R again: Engage, the sweep runs 10 s
		idx = #Mock.RemoteLog
		pressR()
		T.check(H.count(idx, "Engage") == 1 and H.count(idx, "Retreat") == 0, "evo retreat client: R sends ONE Engage", H.count(idx, "Engage") .. " Engage, " .. H.count(idx, "Retreat") .. " Retreat")
		d:run(0.3)
		T.check(b.Text == "Retreat" and BC.GetBattle().Retreated == false, "evo retreat client: the echo flips it back", b.Text)
		local left = BC.GetBattle().Cooldowns.Retreat or -1
		T.check(left > 9 and left <= 10, "evo retreat client: the 10 s wait starts", fmt("%.2f", left))
		T.check(shownIn(sweep) and abs(sweep.Size.X.Scale - left / 10) < 0.06, "evo retreat client: ...the dark sweep shows it", fmt("%.2f", sweep.Size.X.Scale))
		-- a press during the wait: nothing sent, the button shakes
		local shakes = b:GetAttribute("Shakes") or 0
		idx = #Mock.RemoteLog
		pressR()
		T.check(H.count(idx, "Retreat") == 0 and (b:GetAttribute("Shakes") or 0) == shakes + 1, "evo retreat client: a press during the wait sends nothing and shakes the button")
		-- a refused echo shakes it too
		shakes = b:GetAttribute("Shakes") or 0
		KC.toClient("BattleState", "Events", { { type = "Order", owner = d.me, order = "Retreat", rejected = "Cooldown" } }, d.id)
		T.check((b:GetAttribute("Shakes") or 0) == shakes + 1 and b.Text == "Retreat", "evo retreat client: a rejected Order shakes it, the label stays")
		shakes = b:GetAttribute("Shakes") or 0
		KC.toClient("BattleState", "Events", { { type = "Order", owner = d.me, order = "Engage", rejected = "NotRetreated" } }, d.id)
		T.check((b:GetAttribute("Shakes") or 0) == shakes + 1, "evo retreat client: ...an Engage refusal too")
		d:run(9)
		T.check(shownIn(sweep), "evo retreat client: still sweeping at 9 s")
		d:run(1.2)
		T.check(not shownIn(sweep) and (BC.GetBattle().Cooldowns.Retreat or 1) == 0, "evo retreat client: after 10 s the sweep is gone", fmt("%.2f", BC.GetBattle().Cooldowns.Retreat or -1))
		-- a click does the same; the gamepad's D-pad down too
		idx = #Mock.RemoteLog
		Mock.Click(b)
		T.eq(H.count(idx, "Retreat"), 1, "evo retreat client: a click sends ONE Retreat")
		d:run(0.3)
		idx = #Mock.RemoteLog
		pressR("DPadDown", "Gamepad1")
		T.eq(H.count(idx, "Engage"), 1, "evo retreat client: D-pad down sends ONE Engage")
		d:run(0.3)
		Mock.FireSignal(game:GetService("UserInputService"), "InputBegan", Mock.NewInput("ButtonA", "Gamepad1", "Begin"), false)
		H.step(2, 1 / 30)
		T.check(chip.Text == "\226\134\147", "evo retreat client: ...and the chip follows the gamepad", tostring(chip.Text))
		Mock.FireSignal(game:GetService("UserInputService"), "InputBegan", Mock.NewInput("F", "Keyboard", "Begin"), false)
		H.step(2, 1 / 30)
		T.check(chip.Text == "R", "evo retreat client: ...and R again on the keyboard", tostring(chip.Text))
		-- a local check: Engage with no retreat, Retreat while back: nothing sent
		idx = #Mock.RemoteLog
		T.check(BC.Command("Engage") == false and H.count(idx, "Engage") == 0, "evo retreat client: BattleController.Command(\"Engage\") with no retreat: false, nothing sent")
		H.cleanup(BC, d)
		T.check(Mock.BoundActions.NimbusBattleRetreat == nil, "evo retreat client: the fight's End unbinds it")
		T.check(not shownIn(b), "evo retreat client: ...and takes the button away")

		-- every other mode: no button, no binding, nothing sent
		for _, mode in ipairs({ "Duel", "Ring", "Dungeon" }) do
			local dm = H.fight({ Mode = mode })
			if T.check(dm ~= nil and BC.GetBattle() ~= nil, "evo retreat client: (setup) a " .. mode) then
				local rb = H.find("Root.Retreat")
				local mark = #Mock.RemoteLog
				T.check(not (rb and shownIn(rb)), "evo retreat client: a " .. mode .. " has no button")
				T.check(Mock.BoundActions.NimbusBattleRetreat == nil, "evo retreat client: ...R is free there")
				T.check(BC.Command("Retreat") == false and BC.Command("Engage") == false and H.count(mark, "Retreat") == 0 and H.count(mark, "Engage") == 0, "evo retreat client: ...and BattleController.Command sends nothing")
				H.cleanup(BC, dm)
			end
		end

		-- a late joiner's Start: the state and the wait
		d = H.fight({ Mode = "Raid", Team = { Retreated = true } })
		if T.check(d ~= nil, "evo retreat client: (setup) a Start with Team.Retreated") then
			local rb = H.find("Root.Retreat")
			T.check(rb and rb.Text == "Engage" and BC.GetBattle().Retreated == true, "evo retreat client: Start.Team.Retreated: the button says Engage", rb and rb.Text or "missing")
			H.cleanup(BC, d)
		end
		d = H.fight({ Mode = "Raid", Team = { Cooldowns = { Retreat = 6 } } })
		if T.check(d ~= nil, "evo retreat client: (setup) a Start with Cooldowns.Retreat") then
			local rb = H.find("Root.Retreat")
			local s = rb and rb:FindFirstChild("Sweep")
			local c = BC.GetBattle().Cooldowns.Retreat or -1
			T.check(rb and rb.Text == "Retreat" and s ~= nil and shownIn(s) and c > 3 and c <= 6, "evo retreat client: Start.Team.Cooldowns.Retreat: the sweep shows the seconds left", fmt("%.2f", c))
			H.cleanup(BC, d)
		end

		-- the result card's line
		d = H.fight({ Mode = "Raid" })
		if T.check(d ~= nil, "evo retreat client: (setup) a raid for the result card") then
			KC.toClient("BattleState", "End", { BattleId = d.id, Mode = "Raid", Outcome = "Win", Won = true, Spectator = false, Reason = "BossDown",
				Rewards = { Tier = "Gold", SatOut = true, Reason = "You sat out more than half the fight: no Boss Raid pet this time.", Tokens = 500, Xp = 400, Share = 0.5, Damage = 900 } }, d.id)
			LocalPlayer:SetAttribute("InBattle", nil)
			KC.advance(1)
			local card = H.find("Root.ResultCard")
			local found, raw = false, false
			for _, o in ipairs(card and card:GetDescendants() or {}) do
				if (o:IsA("TextLabel") or o:IsA("TextButton")) and shownIn(o) then
					if tostring(o.Text):find("Sat out", 1, true) and tostring(o.Text):find("no pet this time", 1, true) then
						found = true
					end
					if tostring(o.Text) == "true" or tostring(o.Text):find("SatOut", 1, true) then
						raw = true
					end
				end
			end
			T.check(found, "evo retreat client: the result card says the player sat out and gets no pet this time")
			T.check(not raw, "evo retreat client: ...in words, never the raw flag")
			local gold = false
			for _, o in ipairs(card and card:GetDescendants() or {}) do
				if (o:IsA("TextLabel") or o:IsA("TextButton")) and shownIn(o) and tostring(o.Text):find("Gold tier", 1, true) then
					gold = true
				end
			end
			T.check(gold, "evo retreat client: ...and the medal's line is still there (the win was paid)")
			H.cleanup(BC, d)
		end

		-- Graphics Low: the plain button, visible and working
		GQ.Apply("Low")
		d = H.fight({ Mode = "Raid" })
		if T.check(d ~= nil, "evo retreat client: (setup) a raid on Low") then
			local rb = H.find("Root.Retreat")
			T.check(rb ~= nil and shownIn(rb) and rb.Text == "Retreat", "evo retreat client: Low: the button is there")
			d:run(0.2)
			pressR()
			d:run(0.4)
			T.check(rb.Text == "Engage", "evo retreat client: Low: ...and works", rb.Text)
			local stroke = rb:FindFirstChildOfClass("UIStroke")
			local a = stroke and stroke.Transparency
			d:run(0.4)
			T.check(stroke ~= nil and stroke.Transparency == a and rb:GetAttribute("Pulse") ~= true, "evo retreat client: Low: ...plain: no pulse on Engage")
			H.cleanup(BC, d)
		end
		GQ.Apply("High")
		d = H.fight({ Mode = "Raid" })
		if T.check(d ~= nil, "evo retreat client: (setup) a raid on High") then
			local rb = H.find("Root.Retreat")
			d:run(0.2)
			pressR()
			d:run(0.4)
			T.check(rb and rb:GetAttribute("Pulse") == true, "evo retreat client: High: Engage pulses")
			H.cleanup(BC, d)
		end
		-- a laptop's row
		Mock.SetViewport(1366, 768)
		H.step(15, 1 / 30)
		d = H.fight({ Mode = "Raid" })
		if T.check(d ~= nil, "evo retreat client: (setup) a raid at 1366x768") then
			local problem, _, shape = placeProblem(false)
			T.check(problem == nil and shape == "row", "evo retreat client 1366x768: left of Cheer up!, covering nothing", tostring(problem))
			H.cleanup(BC, d)
		end
		Mock.SetViewport(1920, 1080)
		H.step(3, 0.1)
		T.check(#Mock.Errors == err0, "evo retreat client: no script errors", tostring(Mock.Errors[#Mock.Errors]))
		KC.flushErrors("client_evo_retreat")
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_retreat_mobile
	------------------------------------------------------------------------------------------------
	S.client_evo_retreat_mobile = guarded("client_evo_retreat_mobile", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		if not T.check(BC ~= nil, "evo retreat phone: BattleController loads") then
			return
		end
		local err0 = #Mock.Errors
		for _, size in ipairs({ { 844, 390 }, { 740, 360 }, { 749, 388 }, { 667, 375 }, { 1024, 768 }, { 390, 844 }, { 360, 640 } }) do
			Mock.SetViewport(size[1], size[2])
			H.step(15, 1 / 30)
			local tag = "evo retreat phone " .. size[1] .. "x" .. size[2] .. ": "
			local d = H.fight({ Mode = "Raid" })
			if T.check(d ~= nil and BC.GetBattle() ~= nil, tag .. "(setup) a raid") then
				local why, r, how = placeProblem(true)
				T.check(why == nil, tag .. "the button: >= 44 px, in the Cheer up! row, stacked above it or under the vitals card, on the screen, clear of everything, out of the middle", tostring(why) .. (r and (" " .. rstr(r)) or ""))
				local v = H.moduleAt("client", "Controllers/HudController").GetLayout().Vitals
				local c = H.find("Root.Cheer")
				if v and c then
					local rc = rectOf(c)
					-- Cheer up! beside the vitals card -> Retreat stacks above it, or sits under the card where the stack would cover the fighter's cards
					if rc.x1 <= v.X + 1 and rc.y1 > v.Y then
						T.check(how == "stack" or how == "under", tag .. "the row sits beside the card: it stacks above Cheer up! or sits under the card", tostring(how))
					end
				end
				local b = H.find("Root.Retreat")
				local chip = b and b:FindFirstChild("Key", true)
				T.check(chip == nil or not shownIn(chip), tag .. "no key chip on touch")
				-- the labels fit: Engage and Retreat at the button's size
				if b then
					local w = b.AbsoluteSize.X
					T.check(w >= #"Retreat" * 14 * 0.62, tag .. "Retreat fits the button at 14 px", fmt("%.0f px", w))
				end
				H.cleanup(BC, d)
			end
		end
		Mock.SetViewport(390, 844)
		H.step(3, 0.1)
		T.check(#Mock.Errors == err0, "evo retreat phone: no script errors", tostring(Mock.Errors[#Mock.Errors]))
		KC.flushErrors("client_evo_retreat_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
