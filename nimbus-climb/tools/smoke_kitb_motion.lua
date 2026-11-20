-- smoke_kitb_motion.lua: Pitch 2 item 5, the melee pet attack motion "Bounce in" A (branch kitb-p2-motion; spec
-- docs/superpowers/specs/2026-11-20-pitch2-build-design.md item 05_melee_motion, plan docs/superpowers/plans/
-- 2026-11-20-pitch2-build.md Task 11; the approved mock .superpowers/slop-audit/round3/build/PITCH2/E_motion_models/
-- 05_melee_motion_optA.gif and its timing strip on 05_melee_motion_sheet.png). The owner: "the dash back was ugly, the
-- wind-up looked wrong, it slid with no steps". Loaded by tools/smoke.py in BOTH worlds (ARGS.context picks the half).
-- Server world, pure (PetPoses only):
--   melee_bounce_timing      the shapes on the strip's beats at the shipped knobs (Melee.In 0.30 / Bite 0.08 / Hold 0.12 /
--                            Back 0.40, HIT_STOP 0.05): the melee Windup rocks back about the hind paws and is loaded
--                            (15 deg) at WINDUP_LOAD, DashIn starts from exactly that body; hop to 48 % of the gap (0.13 s),
--                            a nod on the front paws (0.04 s), a hop-bite landing on the face at DASH_RUN (the hit), the
--                            chomp (0.12 s: up, then down again), held upright at the face; DashBack (0.56 s): a hop back to
--                            45 % (0.16 s), a rock on the hind paws (0.03 s), a hop home (0.16 s) at BACK_HOME, a rocking
--                            settle, exactly at rest at p 1; the flurry's DashBite (rebound 0.7 back, rock, hop-bite on the
--                            hit), DashDouble (second bite at DOUBLE_BITE), DashThorns (head back, hop away), DashReady (on
--                            the floor and level every READY_BOUNCE). Every pose, on five sets of paw lines and two gaps:
--                            no paw ever under the floor and no paw on the floor ever moves along it (no slide); Melee.Hop 0
--                            still hops; the ranged Windup is unchanged
-- Client world (AttackFx on a fake clock, real PetBuilder pets: base Maple Fox, evolved Aurora Fox):
--   client_feel_bounce_timing  AttackFx.FeetOf measures each model's paw lines; an NPC's bite (Windup 0.45 s before the hit):
--                            the wind-up to the run, the hit frame on the hit's time, the hit stop, the way home from
--                            bk, the pose over and the pet exactly on its spot; the fast tempo (3 bites 0.5 s apart, the
--                            2nd a Double strike, the 3rd on a Thorns shield): no trip home between bites, every hit frame
--                            on its time, the second chomp's bite at DashTwist's time (land + 0.14), the Thorns hop away
--                            and the ready bounce, home from the last bite + FlurryBelow, exactly on its spot; no slide and
--                            no paw under the floor on the whole timeline, base and evolved
--   client_feel_bounce_dust  the landing dust (the spec: "lands on its front paws with dust", "each landing with a rock and
--                            dust"): a puff on the frame of each hop landing (the nod, the hops home, a flurry's rebounds,
--                            the Thorns hop away), none on the bite's landing nor the ready bounces; on the floor under
--                            the paws along the run; the kits pooled again after; none on Low
--   client_feel_bounce_battle  BattleController + a real BattleSim: an NPC bear's 1st bite carries a Double strike, its 2nd a
--                            Thorns hit (the server's event shapes): AttackFx.DashTwist runs for both, the DoubleHit sparks
--                            are due on the second chomp, the Thorns bolt on the bite, the bear plays DashDouble and
--                            DashThorns, its drawn pose carries its model's Feet into PoseBody
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min, floor, huge = math.abs, math.max, math.min, math.floor, math.huge
local fmt = string.format

-- the shipped knobs the beats are read on (Config.Battle.Feel.Melee; the server's strike window)
local IN, BITE, HOLD, BACK, BELOW, STOP = 0.30, 0.08, 0.12, 0.40, 0.75, 0.05

-- the paw heights over the floor and the paw points of a posed body (pose studs; the floor is Down under the root)
local function paws(body, feet)
	local down, front, hind = feet.Down, feet.Front, feet.Hind
	local h = body * Vector3.new(0, -down, hind)
	local f = body * Vector3.new(0, -down, -front)
	return h, f, h.Y + down, f.Y + down
end

-- where the pet stands (the root moves with a paw-pivoted turn, so the paws are read): the lower paw line's height over
-- the floor and how far that paw line has moved along the look from its rest place (forward +)
local function stand(body, feet)
	local h, f, hh, fh = paws(body, feet)
	if hh <= fh then
		return hh, -(h.Z - feet.Hind)
	end
	return fh, -(f.Z + feet.Front)
end

-- a walk of bodies (in time order): -> worst sink (lowest paw height), worst slide (a paw on the floor in two
-- consecutive frames that moved along it), and where
local function walkFeet(bodies, feet)
	local worstSink, worstSlide, sinkAt, slideAt = 0, 0, "", ""
	local prevH, prevF, prevHh, prevFh = nil, nil, nil, nil
	for _, b in ipairs(bodies) do
		local h, f, hh, fh = paws(b.Body, feet)
		local lo = min(hh, fh)
		if lo < worstSink then
			worstSink = lo
			sinkAt = fmt("sink %.5f in %s at %s", lo, tostring(b.Tag), tostring(b.T))
		end
		if prevH then
			local eps = 1e-4
			if hh <= eps and prevHh <= eps then
				local d = Vector3.new(h.X - prevH.X, 0, h.Z - prevH.Z).Magnitude
				if d > worstSlide then
					worstSlide = d
					slideAt = fmt("hind paw slides %.5f in %s at %s", d, tostring(b.Tag), tostring(b.T))
				end
			end
			if fh <= eps and prevFh <= eps then
				local d = Vector3.new(f.X - prevF.X, 0, f.Z - prevF.Z).Magnitude
				if d > worstSlide then
					worstSlide = d
					slideAt = fmt("front paw slides %.5f in %s at %s", d, tostring(b.Tag), tostring(b.T))
				end
			end
		end
		prevH, prevF, prevHh, prevFh = h, f, hh, fh
	end
	return worstSink, worstSlide, sinkAt .. " / " .. slideAt
end

----------------------------------------------------------------------------------------------------------------------
-- the server world: PetPoses, pure
----------------------------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}

	local function shared(name)
		local ok, inst = pcall(Mock.GetPath, ROOTS.shared .. "/" .. name)
		if not ok or not inst then
			return nil
		end
		local ok2, mod = pcall(require, inst)
		return ok2 and type(mod) == "table" and mod or nil
	end

	S.melee_bounce_timing = guarded("melee_bounce_timing", function()
		local P = shared("PetPoses")
		if not T.check(P ~= nil and type(P.Sample) == "function", "melee bounce: shared/PetPoses loads") then
			return
		end
		local has = {}
		for _, n in ipairs(P.Names or {}) do
			has[n] = true
		end
		T.check(has.DashIn and has.DashBack and has.DashBite and has.DashDouble and has.DashThorns and has.DashReady
			and (P.Loops or {}).DashReady == true and (P.Holds or {}).DashBite == true and (P.Holds or {}).DashThorns == true,
			"melee bounce: PetPoses has DashIn, DashBack, DashBite, DashDouble, DashThorns (holds) and DashReady (loops)")
		local R, LOAD = P.DASH_RUN, P.WINDUP_LOAD
		if not T.check(type(R) == "number" and abs(R - 5 / 7) < 1e-9 and LOAD == 0.82 and P.BACK_POSE == 1.4 and P.BACK_HOME == 0.625
			and P.DOUBLE_DUR == 0.15 and P.DOUBLE_BITE == 0.6 and P.THORN_DUR == 0.34 and P.THORN_BACK == 1.3 and P.REBOUND == 0.7
			and P.READY_BOUNCE == 0.17 and type(P.FEET) == "table",
			fmt("melee bounce: the beats are PetPoses' (DASH_RUN 5/7, WINDUP_LOAD 0.82, BACK_POSE 1.4, BACK_HOME 0.625, DOUBLE 0.15 / 0.6, THORN 0.34 / 1.3, REBOUND 0.7, READY_BOUNCE 0.17; DASH_RUN %s)", tostring(R))) then
			return
		end
		local keepHop = P.DashHop
		P.DashHop = nil
		local reach = 9.7
		local function smp(name, p, r, feet, ranged)
			return P.Sample(name, p, ranged == true, 1, r, feet)
		end
		local function pos(s)
			return s.Body.Position
		end
		local function pitchOf(s)
			local lv = s.Body.LookVector -- the pet faces -Z: + = nose up
			return math.deg(math.asin(math.max(-1, math.min(1, lv.Y))))
		end
		local function same(a, b, eps)
			eps = eps or 1e-6
			local d = a:Inverse() * b
			local _, ang = d:ToAxisAngle()
			return (a.Position - b.Position).Magnitude < eps and abs(ang) < eps * 10
		end
		local typical = P.FEET

		-- (a) the wind-up: rocked back about the hind paws, loaded 15 deg at WINDUP_LOAD; DashIn starts from that body
		local w = smp("Windup", LOAD, nil, typical)
		local h, f, hh, fh = paws(w.Body, typical)
		T.check(abs(pitchOf(w) - 15) < 0.2 and abs(hh) < 1e-6 and fh > 0.1,
			fmt("melee bounce: the Windup is loaded at WINDUP_LOAD: nose up %.1f deg (15), rocked on its hind paws (hind %.3f on the floor, front %.3f up)", pitchOf(w), hh, fh))
		local wHalf = smp("Windup", 0.6, nil, typical) -- (BattleController's held wind-up)
		T.check(pitchOf(wHalf) > 7 and abs(paws(wHalf.Body, typical).Y + typical.Down) < 1e-6 and abs(pos(wHalf).Y) < 0.5,
			fmt("melee bounce: the held Windup (p 0.6) rocks back %.1f deg on the hind paws, no crouch into the floor", pitchOf(wHalf)))
		T.check(same(smp("Windup", 1, nil, typical).Body, CFrame.new()) and same(smp("Windup", 0, nil, typical).Body, CFrame.new()),
			"melee bounce: the melee Windup is exactly at rest at p 0 and p 1 (the Strike path's push-off)")
		T.check(same(smp("DashIn", 0, reach, typical).Body, w.Body, 1e-5),
			"melee bounce: DashIn starts from exactly the Windup's loaded body (no pop when the run starts)")

		-- (b) DashIn's beats: u = the share of Melee.In 0.30 (hop 0.13, nod 0.04, hop-bite 0.13), then the chomp 0.12
		local function dIn(u)
			return smp("DashIn", u * R, reach, typical)
		end
		local function up(s)
			return (stand(s.Body, typical))
		end
		local function fwd(s)
			return select(2, stand(s.Body, typical))
		end
		local hop1Up = true
		for i = 1, 25 do
			hop1Up = hop1Up and up(dIn(i / 26 * 13 / 30)) > 1e-3
		end
		local land1 = dIn(13 / 30)
		T.check(hop1Up and abs(up(land1)) < 1e-4 and abs(fwd(land1) - 0.48 * reach) < 1e-3,
			fmt("melee bounce: hop 1 over Melee.In 0 .. 0.13 s (in the air all the way), landing at 48 %% of the gap (%.2f of %.2f studs)", fwd(land1), reach))
		local nodFlat, nodDown = true, false
		for i = 0, 8 do
			local s = dIn((13 + 4 * i / 8) / 30)
			local _, _, _, fh2 = paws(s.Body, typical)
			nodFlat = nodFlat and abs(fh2) < 1e-4
			nodDown = nodDown or pitchOf(s) < -8
		end
		T.check(nodFlat and nodDown, "melee bounce: the nod (0.13 .. 0.17 s): on its front paws, the nose dips under -8 deg")
		local biteUp = true
		for i = 1, 25 do
			biteUp = biteUp and up(dIn((17 + 13 * i / 26) / 30)) > 1e-3
		end
		local hit = smp("DashIn", R, reach, typical)
		local _, _, _, hitFront = paws(hit.Body, typical)
		T.check(biteUp and abs(fwd(hit) - reach) < 1e-3 and abs(hitFront) < 1e-4 and pitchOf(hit) < -12,
			fmt("melee bounce: the hop-bite (0.17 .. 0.30 s) lands its front paws on the face at DASH_RUN, the hit (%.2f of %.2f, nose %.1f deg)", fwd(hit), reach, pitchOf(hit)))
		-- the chomp: up, then down again, upright at the face; DashIn holds there
		local hi, lo2, phase = -huge, huge, 0
		for i = 0, 24 do
			local pc = pitchOf(smp("DashIn", R + (1 - R) * i / 24, reach, typical))
			if phase == 0 and pc > hi then
				hi = pc
			elseif phase == 0 and pc < hi - 0.5 then
				phase = 1
			end
			if phase == 1 then
				lo2 = min(lo2, pc)
			end
		end
		local held = smp("DashIn", 1, reach, typical)
		T.check(hi > -6 and lo2 < -6 and same(held.Body, CFrame.new(0, 0, -reach)),
			fmt("melee bounce: the chomp (0.12 s): the head snaps up (%.1f) and bites down again (%.1f); DashIn holds upright at (0, 0, -reach)", hi, lo2))
		-- the timeline at the shipped knobs: DashIn Dur = In / DASH_RUN, so the chomp is 0.12 s (strip 1.05 .. 1.17)
		T.check(abs(IN / R - IN - 0.12) < 1e-9, fmt("melee bounce: at Melee.In 0.30 the chomp lasts 0.12 s after the hit stop (%.3f)", IN / R - IN))

		-- (c) DashBack: Dur = Back x BACK_POSE = 0.56 s
		local dur = BACK * P.BACK_POSE
		T.check(abs(dur - 0.56) < 1e-9, fmt("melee bounce: the way home lasts Melee.Back x 1.4 = 0.56 s (%.3f)", dur))
		local function dBack(t)
			return smp("DashBack", t / 0.56, reach, typical)
		end
		T.check(same(dBack(0).Body, held.Body), "melee bounce: DashBack starts at the face DashIn holds")
		local b1Up, b2Up = true, true
		for i = 1, 15 do
			b1Up = b1Up and up(dBack(0.16 * i / 16)) > 1e-3
			b2Up = b2Up and up(dBack(0.19 + 0.16 * i / 16)) > 1e-3
		end
		local bl = dBack(0.16)
		local _, _, blHind = paws(bl.Body, typical)
		local rocked = 0
		for i = 0, 6 do
			rocked = max(rocked, pitchOf(dBack(0.16 + 0.03 * i / 6)))
		end
		T.check(b1Up and abs(blHind) < 1e-4 and abs(fwd(bl) - 0.45 * reach) < 1e-3 and rocked > 10,
			fmt("melee bounce: hop back 1 (0 .. 0.16 s) lands at 45 %% (%.2f) on its hind paws and rocks back (%.1f deg, 0.16 .. 0.19 s)", fwd(bl), rocked))
		local home = smp("DashBack", P.BACK_HOME, reach, typical)
		T.check(b2Up and abs(fwd(home)) < 1e-3 and abs(up(home)) < 1e-4, fmt("melee bounce: hop back 2 (0.19 .. 0.35 s) lands home at BACK_HOME (%.4f off its spot)", fwd(home)))
		local sMin, sMax, sOff = huge, -huge, 0
		for i = 0, 20 do
			local s = dBack(0.35 + 0.21 * i / 20)
			sMin, sMax = min(sMin, pitchOf(s)), max(sMax, pitchOf(s))
			sOff = max(sOff, select(3, paws(s.Body, typical)) < 1e-4 and abs(select(1, paws(s.Body, typical)).Z - typical.Hind) or 0)
		end
		T.check(sMin < -3 and sMax > 5 and sOff < 1e-4 and same(smp("DashBack", 1, reach, typical).Body, CFrame.new()),
			fmt("melee bounce: the settle (0.35 .. 0.56 s) rocks on the spot (%.1f .. %.1f deg, the hind paws on their spot) and ends exactly at rest", sMin, sMax))

		-- (d) the flurry's pieces
		local reb = -fwd(smp("DashBite", 14 / 30 * R, 0, typical))
		local bHit = smp("DashBite", R, 0, typical)
		T.check(abs(reb - P.REBOUND) < 1e-3 and abs(fwd(bHit)) < 1e-3 and same(smp("DashBite", 1, 0, typical).Body, CFrame.new()),
			fmt("melee bounce: DashBite from the face: a rebound hop 0.7 back (%.2f), the hop-bite on the face at DASH_RUN, held there", reb))
		local bFar = smp("DashBite", 1, P.THORN_BACK, typical)
		T.check(same(bFar.Body, CFrame.new(0, 0, -P.THORN_BACK)), "melee bounce: DashBite from 1.3 behind the face (after a Thorns hop) ends on the face")
		local dLo, dAt = huge, 0
		for i = 0, 60 do
			local pc = pitchOf(smp("DashDouble", i / 60, nil, typical))
			if i / 60 > 0.4 and pc < dLo then
				dLo, dAt = pc, i / 60
			end
		end
		T.check(dLo < -12 and abs(dAt - P.DOUBLE_BITE) < 0.04 and same(smp("DashDouble", 1, nil, typical).Body, CFrame.new()),
			fmt("melee bounce: DashDouble's second bite lands at DOUBLE_BITE (%.2f, %.1f deg), upright after", dAt, dLo))
		local th = 0
		for i = 0, 10 do
			th = max(th, pitchOf(smp("DashThorns", 0.05 / P.THORN_DUR * i / 10 + 0.05 / P.THORN_DUR * 0.5, nil, typical)))
		end
		T.check(th > 10 and same(smp("DashThorns", 1, nil, typical).Body, CFrame.new(0, 0, P.THORN_BACK)) and smp("DashThorns", 0.2, nil, typical).Lids == 1,
			fmt("melee bounce: DashThorns: the prick snaps the head back (%.1f deg), eyes shut, a hop away 1.3, held upright there", th))
		local rFloor = true
		for k = 0, 6 do
			local s = smp("DashReady", k * P.READY_BOUNCE, nil, typical)
			rFloor = rFloor and same(s.Body, CFrame.new(), 1e-5)
		end
		local rUp = pos(smp("DashReady", P.READY_BOUNCE / 2, nil, typical)).Y
		T.check(rFloor and rUp > 0.05 and rUp < 0.1, fmt("melee bounce: DashReady hops %.3f studs, on the floor and level at every READY_BOUNCE", rUp))

		-- (e) no slide, no sink: every pose, five sets of paw lines, two gaps, Melee.Hop 0.5 and 0
		local feetSets = {
			{ nil, "default" }, { { Down = 1.0, Front = 0.55, Hind = 0.6 }, "typical" }, { { Down = 1.6, Front = 0.9, Hind = 1.0 }, "evolved-size" },
			{ { Down = 0.6, Front = 0.2, Hind = 0.25 }, "small" }, { { Down = 1.2, Front = 1.4, Hind = 1.3 }, "long" },
		}
		local worstSink, worstSlide, worstAt = 0, 0, ""
		local hopTall = true
		for _, hopKnob in ipairs({ 0.5, 0 }) do
			P.DashHop = hopKnob
			for _, fs in ipairs(feetSets) do
				local feet = fs[1] or P.FEET
				for _, r in ipairs({ reach, 2.0 }) do
					local tracks = {
						{ "Windup", 1, nil }, { "DashIn", 1, r }, { "DashBack", 1, r }, { "DashBite", 1, 0 }, { "DashBite", 1, 1.3 },
						{ "DashDouble", 1, nil }, { "DashThorns", 1, min(1.3, r / 2) }, { "DashReady", 2.0, nil },
					}
					for _, tr in ipairs(tracks) do
						local bodies = {}
						local n = 720
						for i = 0, n do
							local p = tr[2] * i / n
							bodies[#bodies + 1] = { Body = P.Sample(tr[1], p, false, 1, tr[3], fs[1]).Body, T = fmt("%.4f", p), Tag = fmt("%s %s gap %.1f hop %.1f", tr[1], fs[2], r, hopKnob) }
						end
						local sk, sl, at = walkFeet(bodies, feet)
						if sk < worstSink then
							worstSink, worstAt = sk, at
						end
						if sl > worstSlide then
							worstSlide, worstAt = sl, at
						end
					end
				end
			end
			if hopKnob == 0 then
				local peak = 0
				for i = 0, 100 do
					peak = max(peak, P.Sample("DashIn", i / 100 * 13 / 30 * R, false, 1, reach).Body.Position.Y)
				end
				hopTall = peak > 0.1
			end
		end
		P.DashHop = keepHop
		T.check(worstSink > -1e-5, fmt("melee bounce: no paw ever under the floor (every pose, 5 paw sets, gaps 9.7 / 2, Hop 0.5 / 0: lowest %.5f)", worstSink), worstAt)
		T.check(worstSlide < 1e-4, fmt("melee bounce: no slide: a paw on the floor never moves along it (worst %.5f studs a frame)", worstSlide), worstAt)
		T.check(hopTall, "melee bounce: Melee.Hop 0 still hops (a hop never becomes a slide)")

		-- (f) the ranged Windup is unchanged (crouch 0.25, chin up 8, weight back 0.2)
		local rw = P.Sample("Windup", 0.6, true)
		T.check(abs(rw.Body.Position.Y + 0.25) < 1e-6 and abs(rw.Body.Position.Z - 0.2) < 1e-6 and abs(pitchOf(rw) - 8) < 0.05,
			fmt("melee bounce: the ranged Windup is unchanged (crouch %.3f, back %.3f, chin %.1f)", rw.Body.Position.Y, rw.Body.Position.Z, pitchOf(rw)))
	end)

	return S
end

----------------------------------------------------------------------------------------------------------------------
-- the client world: AttackFx on a fake clock; BattleController fed by a real BattleSim
----------------------------------------------------------------------------------------------------------------------
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
				local m = Instance.new("Model")
				m.Name = type(spec) == "table" and tostring(spec.Key) or tostring(spec)
				local p = Instance.new("MeshPart")
				p.Name = "Core"
				p.Size = V3(2, 2, 2)
				p.Anchored = true
				p.Parent = m
				return m
			end,
		}
	end

	-- a real battle pet, built like BattleController builds one (PET_SCALE 1.3), standing at `pos` facing -Z
	local function petAt(PB, PC, id, evolved, parent, pos)
		local def = nil
		for _, d in ipairs(PC.Pets) do
			if d.Id == id then
				def = d
			end
		end
		if not def then
			return nil
		end
		local m = PB.Build(def, { Scale = 1.3, Detail = "Low", Evolved = evolved and 1 or nil })
		if not m then
			return nil
		end
		m:PivotTo(CFrame.new(pos))
		m.Parent = parent
		return m
	end

	-- one pose sample the way BattleController draws it: Forward along -Z, then the PetPoses body with the model's feet
	local function bodyOf(PP, ps)
		if type(ps) ~= "table" or type(ps.Name) ~= "string" then
			return nil
		end
		local s = PP.Sample(ps.Name, ps.P, ps.Ranged, ps.Amp, ps.Reach, ps.Feet)
		return CFrame.new(0, 0, -(tonumber(ps.Forward) or 0)) * s.Body
	end

	S.client_feel_bounce_timing = guarded("client_feel_bounce_timing", function()
		local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local PP = moduleAt(ROOTS.shared .. "/PetPoses")
		local PB = moduleAt(ROOTS.shared .. "/PetBuilder")
		local PC = moduleAt(ROOTS.shared .. "/PetCatalog")
		local Config = moduleAt(ROOTS.shared .. "/Config")
		local M = Config and Config.Battle and Config.Battle.Feel and Config.Battle.Feel.Melee
		if not T.check(AF ~= nil and PP ~= nil and PB ~= nil and PC ~= nil and type(M) == "table" and type(AF.Dash) == "function",
			"bounce timing: AttackFx, PetPoses, PetBuilder, PetCatalog, Config.Battle.Feel.Melee load") then
			return
		end
		T.check(M.In == IN and M.Bite == BITE and M.Hold == HOLD and M.Back == BACK and M.FlurryBelow == BELOW and AF.HIT_STOP == STOP,
			"bounce timing: (setup) the shipped knobs: In 0.30, Bite 0.08, Hold 0.12, Back 0.40, FlurryBelow 0.75, HIT_STOP 0.05")
		if not T.check(type(AF.FeetOf) == "function" and type(AF.DashTwist) == "function", "bounce timing: AttackFx.FeetOf and AttackFx.DashTwist exist") then
			return
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
		local holder = Instance.new("Folder")
		holder.Name = "SmokeBounce"
		holder.Parent = cb
		local clock = 7000
		local DT = 1 / 120
		AF.Update(clock)
		local ok, err = pcall(function()
			for li, look in ipairs({ { "maple_fox", false, "base Maple Fox" }, { "aurora_fox", true, "evolved Aurora Fox" } }) do
				local x = 40 * li
				local me = petAt(PB, PC, look[1], look[2], holder, V3(x, G + 1.5, 0))
				local foe = petAt(PB, PC, "biscuit_bear", false, holder, V3(x, G + 1.5, -14))
				if not T.check(me ~= nil and foe ~= nil, fmt("bounce timing: (setup) the %s and a Biscuit Bear build", look[3])) then
					return
				end
				local feet = AF.FeetOf(me)
				local ext = me:GetExtentsSize()
				local sc = tonumber(me:GetAttribute("PB_Scale")) or 1
				T.check(type(feet) == "table" and feet.Down > 0.2 and feet.Down < ext.Y / sc and feet.Front > 0.05 and feet.Hind > 0.05
					and feet.Front + feet.Hind < ext.Z / sc + 1e-6,
					fmt("bounce timing: %s: FeetOf measures its paw lines (down %.2f, front %.2f, hind %.2f pose studs; the model %.2f x %.2f at scale %.2f)",
						look[3], feet and feet.Down or -1, feet and feet.Front or -1, feet and feet.Hind or -1, ext.Y, ext.Z, sc))
				if not feet then
					return
				end
				local unit = 500 + li
				local src = { Unit = unit, Model = me, Pos = V3(x, G + 1.5, 0) }
				local tgt = { Unit = unit + 1000, Model = foe, Pos = V3(x, G + 1.5, -14) }
				local frames = {}
				local function step(to, each)
					while clock + DT <= to + 1e-9 do
						clock = clock + DT
						AF.Update(clock)
						local ps = AF.Pose(unit)
						local b = bodyOf(PP, ps)
						-- Fwd: how far its standing paws are forward of their rest place (pose studs)
						frames[#frames + 1] = { T = clock, Name = ps and ps.Name or nil, P = ps and ps.P or nil, Body = b, Fwd = b and select(2, stand(b, feet)) or 0, Feet = ps and ps.Feet or nil }
						if each then
							each(clock)
						end
					end
				end
				local function frameAt(t)
					local best, bd = nil, huge
					for _, f in ipairs(frames) do
						if abs(f.T - t) < bd then
							best, bd = f, abs(f.T - t)
						end
					end
					return best
				end

				------------------------------------------------------------------ one bite (an NPC: its Windup 0.45 s ahead)
				local land = clock + 0.45
				T.check(AF.Dash(unit, src, tgt, land, clock, { Tempo = 2 }) == true, fmt("bounce timing: %s: an NPC's dash is taken", look[3]))
				local _, info = AF.DashState(unit)
				local edge = type(info) == "table" and info.Reach or nil
				local first = AF.Pose(unit)
				T.check(first ~= nil and first.Name == "Windup" and type(first.Feet) == "table",
					fmt("bounce timing: %s: from the Windup the pose is the melee Windup, with the model's Feet (%s)", look[3], tostring(first and first.Name)))
				step(land + BITE + HOLD + BACK * 1.4 + 0.1)
				local runAt = land - IN
				local preRun, atRun = frameAt(runAt - DT), frameAt(runAt + DT)
				T.check(preRun and preRun.Name == "Windup" and abs(preRun.P - PP.WINDUP_LOAD) < 0.06 and atRun and atRun.Name == "DashIn",
					fmt("bounce timing: %s: the wind-up loads until the run starts Melee.In before the hit (%s p %.2f, then %s)", look[3],
						tostring(preRun and preRun.Name), preRun and preRun.P or -1, tostring(atRun and atRun.Name)))
				-- the hit frame: the face is reached exactly on the hit's time, held through the hit stop
				local reachAt = nil
				for _, f in ipairs(frames) do
					if not reachAt and edge and f.Name == "DashIn" and f.Fwd >= edge - 0.01 then
						reachAt = f.T
					end
				end
				local stopA, stopB = frameAt(land + 0.005), frameAt(land + STOP - 0.005)
				T.check(edge ~= nil and reachAt ~= nil and abs(reachAt - land) <= DT + 1e-6 and stopA and stopB and abs(stopA.P - stopB.P) < 1e-6,
					fmt("bounce timing: %s: the hop-bite lands on the face on the server's hit time (%.4f s off), the pose held over the hit stop", look[3], reachAt and (reachAt - land) or 99))
				local bk = land + BITE + HOLD
				local hold1, back1 = frameAt(bk - 0.01), frameAt(bk + 0.02)
				T.check(hold1 and hold1.Name == "DashIn" and back1 and back1.Name == "DashBack",
					fmt("bounce timing: %s: the way home starts at the hit + Bite + Hold (%s then %s)", look[3], tostring(hold1 and hold1.Name), tostring(back1 and back1.Name)))
				local homeF = frameAt(bk + 0.35 + 0.01)
				T.check(homeF and homeF.Name == "DashBack" and abs(homeF.Fwd) < 0.12,
					fmt("bounce timing: %s: two hops home by bk + 0.35 (forward %.3f)", look[3], homeF and homeF.Fwd or -1))
				local last = nil
				for _, f in ipairs(frames) do
					if f.Body then
						last = f
					end
				end
				T.check(AF.Pose(unit) == nil and AF.DashState(unit) == "out" and last and last.T > bk + 0.5 and (last.Body.Position.Magnitude < 0.02),
					fmt("bounce timing: %s: the settle ends by bk + 0.56, the pose over, the pet on its spot (last body %.4f studs off)", look[3], last and last.Body.Position.Magnitude or -1))
				local bodies = {}
				for _, f in ipairs(frames) do
					if f.Body then
						bodies[#bodies + 1] = { Body = f.Body, T = fmt("%.3f", f.T - land), Tag = f.Name }
					end
				end
				local sink, slide, at = walkFeet(bodies, feet)
				T.check(sink > -1e-4 and slide < 1e-3, fmt("bounce timing: %s: one bite, every frame: no paw under the floor (%.5f), no slide (%.5f)", look[3], sink, slide), at)

				------------------------------------------------------------------ the fast tempo: 3 bites 0.5 s apart
				frames = {}
				clock = clock + 0.5
				AF.Update(clock)
				local L = { clock + 0.45, clock + 0.95, clock + 1.45 }
				local twistAt, thornAt = nil, nil
				-- the server's order: each bite's Windup 0.45 s before its hit; bite 2's Double strike and bite 3's Thorns
				-- hit arrive with their bites (before the next Windup)
				for i = 1, 3 do
					step(L[i] - 0.45)
					local before = AF.DashState(unit)
					T.check(AF.Dash(unit, src, tgt, L[i], clock, { Tempo = 0.5 }) == true and (i == 1 or before == "in"),
						fmt("bounce timing: %s: fast bite %d taken%s", look[3], i, i > 1 and " (still in: no trip home)" or ""))
					step(L[i])
					if i == 2 then
						twistAt = AF.DashTwist(unit, "Double", clock)
					elseif i == 3 then
						thornAt = AF.DashTwist(unit, "Thorns", clock)
					end
				end
				local bkF = L[3] + BELOW
				step(bkF + BACK * 1.4 + 0.1)
				T.check(type(twistAt) == "number" and abs(twistAt - (L[2] + STOP + PP.DOUBLE_DUR * PP.DOUBLE_BITE)) < 1e-6,
					fmt("bounce timing: %s: DashTwist Double: the second chomp bites at the hit + 0.14 (%s)", look[3], tostring(twistAt and (twistAt - L[2]))))
				T.check(type(thornAt) == "number" and abs(thornAt - L[3]) < 1e-6, fmt("bounce timing: %s: DashTwist Thorns: the bolt lands on the bite", look[3]))
				local hitsOk, hitsAt = true, {}
				for i = 1, 3 do
					local onFace = frameAt(L[i] + 0.004)
					local before = frameAt(L[i] - 0.03)
					hitsAt[i] = fmt("%s %.2f/%.2f", tostring(onFace and onFace.Name), onFace and onFace.Fwd or -1, before and before.Fwd or -1)
					hitsOk = hitsOk and onFace ~= nil and edge ~= nil and abs(onFace.Fwd - edge) < 0.02 and before ~= nil and before.Fwd < edge - 0.05
				end
				T.check(hitsOk, fmt("bounce timing: %s: fast tempo: each bite lands on the face on its hit's time, coming in from a hop (%s)", look[3], table.concat(hitsAt, ", ")))
				local nearestIn = huge
				for _, f in ipairs(frames) do
					if f.T > L[1] + 0.2 and f.T < L[3] then
						nearestIn = min(nearestIn, f.Fwd)
					end
				end
				T.check(edge ~= nil and nearestIn > edge - PP.REBOUND - 0.05, fmt("bounce timing: %s: no trip home between bites (closest to home %.2f of %.2f: the 0.7 rebound)", look[3], nearestIn, edge or -1))
				-- the second chomp's bite at DashTwist's time
				local dLo, dT = huge, nil
				for _, f in ipairs(frames) do
					if f.Name == "DashDouble" and f.Body then
						local pc = math.deg(math.asin(math.max(-1, math.min(1, f.Body.LookVector.Y))))
						if f.T > L[2] + STOP + 0.05 and pc < dLo then
							dLo, dT = pc, f.T
						end
					end
				end
				T.check(dT ~= nil and abs(dT - twistAt) <= 2 * DT + 1e-6, fmt("bounce timing: %s: the Double strike's second bite lands on DashTwist's time (%.3f s off)", look[3], dT and (dT - twistAt) or 99))
				local sawThorns, sawReady, away = false, false, 0
				for _, f in ipairs(frames) do
					if f.T > L[3] and f.T < bkF then
						sawThorns = sawThorns or f.Name == "DashThorns"
						sawReady = sawReady or f.Name == "DashReady"
						if edge then
							away = max(away, edge - f.Fwd)
						end
					end
				end
				T.check(sawThorns and sawReady and abs(away - min(PP.THORN_BACK, edge / 2)) < 0.1,
					fmt("bounce timing: %s: on Thorns it hops away (%.2f studs) and bounces ready on the spot until the last bite + FlurryBelow", look[3], away))
				local pre, post = frameAt(bkF - 0.01), frameAt(bkF + 0.02)
				T.check(pre and pre.Name ~= "DashBack" and post and post.Name == "DashBack",
					fmt("bounce timing: %s: home from the last bite + FlurryBelow (%s then %s)", look[3], tostring(pre and pre.Name), tostring(post and post.Name)))
				local lastF = nil
				for _, f in ipairs(frames) do
					if f.Body then
						lastF = f
					end
				end
				T.check(AF.Pose(unit) == nil and lastF and lastF.Body.Position.Magnitude < 0.02,
					fmt("bounce timing: %s: fast tempo: the pose over, the pet exactly on its spot (%.4f)", look[3], lastF and lastF.Body.Position.Magnitude or -1))
				bodies = {}
				for _, f in ipairs(frames) do
					if f.Body then
						bodies[#bodies + 1] = { Body = f.Body, T = fmt("%.3f", f.T - L[1]), Tag = f.Name }
					end
				end
				sink, slide, at = walkFeet(bodies, feet)
				T.check(sink > -1e-4 and slide < 1e-3, fmt("bounce timing: %s: fast tempo, every frame: no paw under the floor (%.5f), no slide (%.5f)", look[3], sink, slide), at)
				clock = clock + 1
				AF.Update(clock)
			end
		end)
		AF.ClearAll()
		AF._Deps({ MeshLibrary = false })
		AF.SetQuality(nil)
		pcall(holder.Destroy, holder)
		T.check(ok, "bounce timing: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- the landing dust (the spec's option text: "a nod as it lands on its front paws with dust", "two hops back, each
	-- landing with a rock and dust"): a puff on the frame each hop lands, never on the bite's landing (the hit's impact
	-- plays there) nor the little ready bounces; at the pet's paws on its floor; pooled kits; none on Low
	S.client_feel_bounce_dust = guarded("client_feel_bounce_dust", function()
		local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local PP = moduleAt(ROOTS.shared .. "/PetPoses")
		local PB = moduleAt(ROOTS.shared .. "/PetBuilder")
		local PC = moduleAt(ROOTS.shared .. "/PetCatalog")
		local TI = moduleAt(ROOTS.shared .. "/TextureIds")
		if not T.check(AF ~= nil and PP ~= nil and PB ~= nil and PC ~= nil and type(TI) == "table" and type(AF.Dash) == "function",
			"bounce dust: AttackFx, PetPoses, PetBuilder, PetCatalog, TextureIds load") then
			return
		end
		local L = PP.Landings
		T.check(type(L) == "table" and type(L.DashIn) == "table" and #L.DashIn == 1 and type(L.DashBack) == "table" and #L.DashBack == 2
			and type(L.DashBite) == "table" and #L.DashBite == 1 and type(L.DashThorns) == "table" and #L.DashThorns == 1 and L.DashReady == nil,
			"bounce dust: PetPoses.Landings: the p each hop lands (DashIn's nod 1, DashBack 2, DashBite's rebound 1, DashThorns 1; no ready bounce)")
		if not (type(L) == "table" and type(L.DashIn) == "table" and type(L.DashBack) == "table") then
			return
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
		local holder = Instance.new("Folder")
		holder.Name = "SmokeBounceDust"
		holder.Parent = cb
		local clock = 9000
		local DT = 1 / 120
		AF.Update(clock)
		local dustTex = "rbxassetid://" .. tostring(TI.fx_dust)
		-- where every dust host is now (a pooled emitter kit with the fx_dust sheet)
		local function dustHosts()
			local folder = type(AF.Folder) == "function" and AF.Folder() or nil
			local out = {}
			if folder then
				for _, d in ipairs(folder:GetChildren()) do
					local em = d:IsA("BasePart") and d:FindFirstChildOfClass("ParticleEmitter") or nil
					if em and em.Texture == dustTex then
						out[#out + 1] = d.Position
					end
				end
			end
			return out
		end
		local function nearest(hosts, p)
			local best = huge
			for _, q in ipairs(hosts or {}) do
				best = min(best, (q - p).Magnitude)
			end
			return best
		end
		local function kicks()
			local s = AF.Stats()
			return tonumber(s.DustKicks) or 0, tonumber(s.Dusts) or 0
		end
		local ok, err = pcall(function()
			-- one run: an NPC's bites (hits at `hits`, Windup 0.45 s ahead), twists on their hits; -> every frame
			local function run(id, evolved, x, hits, tempo, twists, opts)
				local me = petAt(PB, PC, id, evolved, holder, V3(x, G + 1.5, 0))
				local foe = petAt(PB, PC, "biscuit_bear", false, holder, V3(x, G + 1.5, -14))
				local feet = me and AF.FeetOf(me)
				if not (me and foe and feet) then
					return nil
				end
				local sc = tonumber(me:GetAttribute("PB_Scale")) or 1
				local unit = 700 + x
				local src = { Unit = unit, Model = me, Pos = V3(x, G + 1.5, 0) }
				local tgt = { Unit = unit + 1, Model = foe, Pos = V3(x, G + 1.5, -14) }
				local t0 = clock
				local frames = {}
				local nextHit, twisted = 1, {}
				local k0 = kicks()
				local edge = nil
				while clock < t0 + hits[#hits] + 1.6 do
					clock = clock + DT
					local t = clock - t0
					local h = hits[nextHit]
					if h and t >= h - 0.45 - 1e-9 then
						local o = { Tempo = tempo }
						for kk, vv in pairs(opts or {}) do
							o[kk] = vv
						end
						AF.Dash(unit, src, tgt, t0 + h, clock, o)
						nextHit = nextHit + 1
						local _, d = AF.DashState(unit)
						edge = edge or (type(d) == "table" and d.Reach) or nil
					end
					for i, hh in ipairs(hits) do
						if not twisted[i] and t >= hh - 1e-9 then
							twisted[i] = true
							if twists and twists[i] then
								AF.DashTwist(unit, twists[i], clock)
							end
						end
					end
					AF.Update(clock)
					local ps = AF.Pose(unit)
					local b = bodyOf(PP, ps)
					local kNow = kicks()
					local hgt = b and stand(b, feet) or 0
					local prevK = (#frames > 0) and frames[#frames].Kick or 0
					frames[#frames + 1] = { T = t, H = hgt, Name = ps and ps.Name, Kick = kNow - k0, Hosts = (kNow - k0 > prevK) and dustHosts() or nil }
				end
				return frames, feet, sc, edge, me
			end
			-- the hop landings of a walk: the frame the lower paw comes down after an airborne stretch that rose >= 0.15
			-- pose studs (the ready bounces rise 0.07), less those within the hit stop of a hit (the bite lands on the face)
			local function landings(frames, hits)
				local out, peak, air = {}, 0, false
				for i, f in ipairs(frames) do
					if f.H > 1e-3 then
						air, peak = true, max(peak, f.H)
					elseif air then
						air = false
						local onHit = false
						for _, h in ipairs(hits) do
							if f.T >= h - 2 * DT and f.T <= h + STOP + 2 * DT then
								onHit = true
							end
						end
						if peak >= 0.15 and not onHit then
							out[#out + 1] = i
						end
						peak = 0
					end
				end
				return out
			end
			-- the frames where the dust count went up
			local function kickFrames(frames)
				local out, last = {}, 0
				for i, f in ipairs(frames) do
					if f.Kick > last then
						for _ = 1, f.Kick - last do
							out[#out + 1] = i
						end
						last = f.Kick
					end
				end
				return out
			end
			local function sameFrames(a, b)
				if #a ~= #b then
					return false
				end
				for i = 1, #a do
					if abs(a[i] - b[i]) > 1 then -- (within one 1/120 s frame)
						return false
					end
				end
				return true
			end
			local function list(frames, idx)
				local t = {}
				for _, i in ipairs(idx) do
					t[#t + 1] = fmt("%.3f %s", frames[i].T, tostring(frames[i].Name))
				end
				return table.concat(t, ", ")
			end

			-- one bite, base Maple Fox: the nod, then two hops home -> 3 puffs, each where the paws came down
			local frames, feet, sc, edge, me = run("maple_fox", false, 40, { 0.6 }, 2, nil, nil)
			if not T.check(frames ~= nil and edge ~= nil, "bounce dust: (setup) a Maple Fox's bite runs") then
				return
			end
			local lands, kf = landings(frames, { 0.6 }), kickFrames(frames)
			T.check(#lands == 3, fmt("bounce dust: one bite: three hop landings off the hit (the nod, 2 hops home): %d", #lands), list(frames, lands))
			T.check(sameFrames(lands, kf), "bounce dust: one bite: a puff on the frame of each hop landing, no other",
				"landings " .. list(frames, lands) .. " | puffs " .. list(frames, kf))
			-- where: on its floor under the paws, along the run (the nod at 48 % of the gap, the first hop home at 45 %, home)
			local rest = V3(40, G + 1.5, 0)
			local wantFwd = { 0.48 * edge, 0.45 * edge, 0 }
			for i, fwd in ipairs(wantFwd) do
				local p = rest + V3(0, -feet.Down * sc, -fwd * sc)
				local d = kf[i] and nearest(frames[kf[i]].Hosts, p) or huge
				T.check(d <= 0.05, fmt("bounce dust: one bite: puff %d on the floor under the paws, %.2f studs along the run (%.3f off)", i, fwd * sc, d))
			end
			local _, live = kicks()
			T.check(live == 0, fmt("bounce dust: one bite: the dust kits are back in the pool afterwards (%d live)", live))

			-- the fast tempo, evolved Aurora Fox (2nd bite a Double strike, 3rd on a Thorns shield): the nod, two rebound
			-- hops, the Thorns hop away, two hops home -> 6 puffs; none on the ready bounces
			local f2 = run("aurora_fox", true, 80, { 0.6, 1.1, 1.6 }, 0.5, { [2] = "Double", [3] = "Thorns" }, nil)
			if f2 then
				local l2, k2 = landings(f2, { 0.6, 1.1, 1.6 }), kickFrames(f2)
				local names = {}
				for _, i in ipairs(k2) do
					names[#names + 1] = tostring(f2[i].Name)
				end
				T.check(#l2 == 6 and sameFrames(l2, k2), fmt("bounce dust: fast tempo: a puff on each of its 6 hop landings, no other (%d landings, %d puffs)", #l2, #k2),
					"landings " .. list(f2, l2) .. " | puffs " .. list(f2, k2))
				T.check(table.concat(names, " ") == "DashIn DashBite DashBite DashThorns DashBack DashBack",
					"bounce dust: fast tempo: the nod, 2 rebounds, the Thorns hop away, 2 hops home", table.concat(names, " "))
			else
				T.check(false, "bounce dust: (setup) the Aurora Fox's fast tempo runs")
			end

			-- Low graphics (the battle's Low flag, or the quality): the motion runs, no dust
			local before = kicks()
			local f3 = run("maple_fox", false, 120, { 0.6 }, 2, nil, { Low = true })
			AF.SetQuality("Low")
			local f4 = run("maple_fox", false, 160, { 0.6 }, 2, nil, nil)
			AF.SetQuality("High")
			T.check(f3 ~= nil and f4 ~= nil and kicks() == before, fmt("bounce dust: Low: no puff (%d)", kicks() - before))
		end)
		AF.ClearAll()
		AF._Deps({ MeshLibrary = false })
		AF.SetQuality(nil)
		pcall(holder.Destroy, holder)
		T.check(ok, "bounce dust: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- BattleController + a real BattleSim (smoke_feel_dash's driver): the bear's bite batch carries a Double strike and a
	-- Thorns hit
	----------------------------------------------------------------------------------------------
	S.client_feel_bounce_battle = guarded("client_feel_bounce_battle", function()
		local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
		local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local BS = moduleAt(ROOTS.shared .. "/BattleSim")
		local BCat = moduleAt(ROOTS.shared .. "/BattleCatalog")
		if not T.check(BC ~= nil and AF ~= nil and BS ~= nil and BCat ~= nil and type(AF.DashTwist) == "function" and BC._St ~= nil,
			"bounce battle: BattleController, AttackFx (DashTwist), BattleSim, BattleCatalog load") then
			return
		end
		AF.SetQuality("High")
		local keepSo = BCat.Damage.Standoff
		BCat.Damage.Standoff = 8
		local me = LocalPlayer.UserId
		local id = "bounce_" .. tostring(math.random(100000, 999999))
		local sim = BS.new({ Mode = "Duel", Seed = 13, Id = id, Zone = { X = 60, Z = 60 }, TimeLimit = 120,
			Teams = { { Owner = me, Side = 1, Pets = { { Key = "puddle_frog", PetId = "puddle_frog", Level = 20, Tier = "Normal", Slot = 1 } }, Auto = false },
				{ Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = { { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = 1 } } } } })
		if not T.check(sim ~= nil, "bounce battle: (setup) a Duel: my standing frog vs an NPC bear") then
			BCat.Damage.Standoff = keepSo
			return
		end
		local tm = sim.teams[1]
		local f = tm.fighter
		f.x, f.z, f.px, f.pz = 0, -8, 0, -8
		f.maxHp, f.hp = 1e9, 1e9
		tm.wantX, tm.wantZ = 0, -8
		tm.elementReadyAt = huge
		tm.noEngage = true
		local foe = nil
		for _, u in ipairs(sim.units) do
			if u.side == 2 then
				foe = u
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
		local last = {}
		local twists, plays, feetSeen, posesSeen = {}, {}, false, {}
		local realTwist, realPlay = AF.DashTwist, AF.Play
		AF.DashTwist = function(unit, kind, now)
			local r = realTwist(unit, kind, now)
			twists[#twists + 1] = { Unit = unit, Kind = kind, Result = r, At = os.clock() }
			return r
		end
		AF.Play = function(ctx)
			local c = { Twist = ctx.Twist, DueAt = ctx.DueAt, Attack = ctx.Attack, At = os.clock() }
			c.Result = realPlay(ctx)
			plays[#plays + 1] = c
			return c.Result
		end
		local injected, bites = false, 0
		local ok, err = pcall(function()
			for _ = 1, 200 do
				f.nextAttack = huge
				tm.wantX, tm.wantZ = 0, -8
				f.meter = 0
				local evs = sim:Step(0.1)
				for i = #evs, 1, -1 do
					local ev = evs[i]
					if bites < 2 and ev.type == "Hit" and ev.from == foe.id and ev.to == f.id and not ev.double and not ev.thorns then
						-- the server's shapes right after the bite (BattleSim applyDamage: a Double strike's extra Hit; a Thorns
						-- Hit back from the shield wearer): the 1st bite rolls a Double strike, the 2nd lands on Thorns
						bites = bites + 1
						if bites == 1 then
							table.insert(evs, i + 1, { type = "Hit", from = foe.id, to = f.id, amount = 1, double = true })
						else
							table.insert(evs, i + 1, { type = "Hit", from = f.id, to = foe.id, amount = 1, thorns = true })
							injected = true
						end
						break
					end
				end
				if #evs > 0 then
					KC.toClient("BattleState", "Events", evs, id)
				end
				local snap = sim:SnapshotDelta(last)
				snap.BattleId = id
				KC.toClient("BattleState", "Snapshot", snap, id)
				for _ = 1, 3 do
					Mock.Step(0.1 / 3)
					local B = BC._St.battle
					local u = B and B.units and B.units[foe.id]
					local ps = AF.Pose(foe.id)
					if ps and ps.Name then
						posesSeen[ps.Name] = true
						if u and u.poseCur and type(u.poseCur.Feet) == "table" and (ps.Name == "DashIn" or ps.Name == "DashBack") then
							feetSeen = true
						end
					end
				end
				if injected and #twists >= 2 and posesSeen.DashThorns and AF.DashState(foe.id) == "out" then
					break
				end
			end
		end)
		AF.DashTwist, AF.Play = realTwist, realPlay
		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, id)
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
		Mock.Step(0.1)
		BCat.Damage.Standoff = keepSo
		if not T.check(ok, "bounce battle: no error", tostring(err)) then
			return
		end
		T.check(injected, "bounce battle: (setup) the bear bit my frog twice: a Double strike with the 1st bite, a Thorns hit with the 2nd")
		local dbl, thr = nil, nil
		for _, t in ipairs(twists) do
			if t.Unit == foe.id and t.Kind == "Double" then
				dbl = t
			elseif t.Unit == foe.id and t.Kind == "Thorns" then
				thr = t
			end
		end
		T.check(dbl ~= nil and type(dbl.Result) == "number" and thr ~= nil and type(thr.Result) == "number",
			fmt("bounce battle: the Hit twists reach AttackFx.DashTwist for the dashing bear (Double %s, Thorns %s)", tostring(dbl and dbl.Result), tostring(thr and thr.Result)))
		local dPlay, tPlay = nil, nil
		for _, c in ipairs(plays) do
			if c.Twist == "DoubleHit" then
				dPlay = c
			elseif c.Twist == "Thorns" then
				tPlay = c
			end
		end
		T.check(dPlay ~= nil and dbl ~= nil and type(dbl.Result) == "number" and abs(dPlay.DueAt - dbl.Result) < 1e-6,
			fmt("bounce battle: the DoubleHit sparks are due on the second chomp (due %s vs %s)", tostring(dPlay and dPlay.DueAt), tostring(dbl and dbl.Result)))
		T.check(tPlay ~= nil and thr ~= nil and type(thr.Result) == "number" and abs(tPlay.DueAt - thr.Result) < 1e-6,
			fmt("bounce battle: the Thorns bolt is due on the bite (due %s vs %s)", tostring(tPlay and tPlay.DueAt), tostring(thr and thr.Result)))
		T.check(posesSeen.DashDouble == true and posesSeen.DashThorns == true, "bounce battle: the bear plays DashDouble and DashThorns")
		T.check(feetSeen, "bounce battle: the bear's drawn pose carries its model's Feet (PoseBody pivots about its paws)")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
